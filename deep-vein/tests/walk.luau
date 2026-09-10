-- Deep Vein — THE PLAYER'S PATH, walked in the built world.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       cd ../deep-vein && luau tests/walk.luau
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- WHY THIS EXISTS ALONGSIDE robloxemu/check_deepvein.luau. That file is the emulator's own gate
-- and it is not ours to edit; it also freezes two things this round had to change — a surface
-- deck whose top face was deliberately coplanar with the breakable rock it hid inside, and a dug
-- column addressed by a literal z instead of by the spawn the game actually uses. Everything here
-- is either (a) a finding from REVIEW-2 that needed an assertion which did not exist anywhere, or
-- (b) the thing green tests keep failing to be: somebody walking the loop from spawn to rebirth
-- and reporting what they saw.
--
-- On requiring the game's own modules: this file uses them to ADDRESS things (which cell is a
-- position in, what a rebirth costs) and never to predict counts. Counts are written out by hand,
-- because a count recomputed from the generator grades the generator against itself.

local Harness = require("../../robloxemu/emu/harness")
local Config = require("../src/shared/Config")
local Mine = require("../src/shared/Mine")
local Ore = require("../src/shared/Ore")
local Prestige = require("../src/shared/Prestige")

local h = Harness.new({
	bundle = require("../../robloxemu/build/deep-vein"),
	name = "deep-vein-walk",
	viewport = { 1280, 720 },
	touch = false,
})

-- THE PART FACTORY, WRAPPED BEFORE THE SERVER EVER RUNS.
--
-- Transparent while `poisonParts` is 0, which is all but one moment of this file. It has to be
-- installed up here rather than at the point of use: Luau caches a chunk's global lookups the
-- first time it runs them, so a swap made after the server has already built a Part is a swap the
-- server never sees. (Measured: swapping mid-run, 0 calls intercepted out of 109 Parts built;
-- swapping before the first run, all 200.)
local realInstance = Instance
local poisonParts = 0
Instance = {
	new = function(className, ...)
		if className == "Part" and poisonParts > 0 then
			poisonParts -= 1
			error("injected: the Part factory failed", 0)
		end
		return realInstance.new(className, ...)
	end,
}

-- …and the same trick on `warn`, for the one thing a pcall around the drain could never catch:
-- the ERROR HANDLER failing. drainBuild reports a cell it could not build by calling warn, and
-- that call is outside the per-cell pcall by construction, so a warn that throws takes the whole
-- pump thread down with it.
local realWarn = warn
local poisonWarns = 0
warn = function(...)
	if poisonWarns > 0 then
		poisonWarns -= 1
		error("injected: warn itself failed", 0)
	end
	return realWarn(...)
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function gt(a, b, msg)
	if type(a) == "number" and a > b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want > " .. tostring(b))
	end
end

local CELL = Config.Mine.CellSize

local WALKER, RELOG, PUMPER, STREAM = 4001, 4002, 4003, 4004

local remotesReady = false
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)

-- A VETERAN WITH A DEEP SHAFT ALREADY DUG, for the streaming section (7). Rebirth 8 puts the wall
-- at layer 120, and the saved cave is the elevator column all the way down to it — the state
-- REVIEW-3 left open, where every join rebuilt the whole excavation and kept it.
--
-- Mine.packOpened is used here to SET UP a state, which is what this file allows itself to use the
-- modules for; every count below is written out by hand.
local STREAM_REBIRTHS = 8
do
	local w = Mine.world(Config, STREAM_REBIRTHS)
	local c = Mine.center(Config)
	local dug = {}
	for y = 1, w.maxLayer do dug[Mine.key(c, y, c)] = true end
	store:SetAsync("u_" .. STREAM, {
		data = {
			cash = 0, totalCash = 0, inventory = {},
			pickTier = 5, backpackLevel = 12, lampLevel = 0,
			rebirths = STREAM_REBIRTHS, depthLayer = w.maxLayer, bestLayer = w.maxLayer,
			openedBits = Mine.packOpened(Config, w, dug),
		},
	})
end

assert(h:tryRun("server/Main.server"))
h:advance(1)

local remotes = h.services.ReplicatedStorage:FindFirstChild("VeinRemotes")
remotesReady = remotes ~= nil
truthy(remotesReady, "the server published its remotes")
local StateEvent = remotes:FindFirstChild("State")
local ElevatorEvent = remotes:FindFirstChild("Elevator")
local BuyEvent = remotes:FindFirstChild("Buy")
local RebirthEvent = remotes:FindFirstChild("Rebirth")
local ToastEvent = remotes:FindFirstChild("Toast")

local toasts = {}
ToastEvent.OnClientEvent:Connect(function(msg) table.insert(toasts, tostring(msg)) end)
local function lastToast(): string return toasts[#toasts] or "" end

local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end

local shafts = h.workspace:FindFirstChild("Shafts")

local function shaftOf(uid)
	for _, f in shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. uid, true) ~= nil then return f end
	end
	return nil
end

local function blocksOf(folder)
	local out = {}
	if folder == nil then return out end
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("CellKey") ~= nil then out[#out + 1] = d end
	end
	return out
end

local function blockAt(folder, k)
	for _, d in blocksOf(folder) do
		if d:GetAttribute("CellKey") == k then return d end
	end
	return nil
end

local function partCount()
	local n = 0
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

-- The highest thing under (x, z) whose top face is at or below `fromY`: what a character standing
-- there actually lands on.
local function groundUnder(folder, x, z, fromY)
	local bestTop, bestPart = -math.huge, nil
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local p, s = d.Position, d.Size
			if math.abs(p.X - x) <= s.X / 2 and math.abs(p.Z - z) <= s.Z / 2 then
				local top = p.Y + s.Y / 2
				if top <= fromY + 0.001 and top > bestTop then bestTop, bestPart = top, d end
			end
		end
	end
	return bestPart, bestTop
end

-- THE MINER HAS TO BE STANDING THERE.
--
-- Every gate in this repo used to fire ClickDetectors from wherever the character happened to be
-- — REVIEW-3 listed "the real MaxActivationDistance" as a thing the suite cannot see — and once
-- the shaft only holds Parts for the layers around the miner, a test that swings at layer 24 from
-- the surface is not just cheating, it is testing a state no player can be in. So: stand on top of
-- the block before swinging at it, which is what digging down IS, and record the worst reach the
-- walk ever used so the number is measured rather than assumed.
local worstReach = 0
local function standOn(hrp, part)
	if hrp == nil or part == nil then return end
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, CELL, 0))
	local d = (hrp.CFrame.Position - part.Position).Magnitude
	if d > worstReach then worstReach = d end
end

-- Break one block, respecting the server's own cooldown. Returns true if it came out.
local function mineOut(plr, part, maxSwings, hrp)
	local cd = part and part:FindFirstChildOfClass("ClickDetector")
	if cd == nil then return false end
	standOn(hrp, part)
	for _ = 1, maxSwings or 40 do
		if part.Parent == nil then return true end
		cd.MouseClick:Fire(plr)
		h:advance(Config.Mine.SwingCooldown + 0.02)
	end
	return part.Parent == nil
end

-- Parts in one shaft, split the way the streaming fix splits them: cell blocks (which come and go
-- with the miner) and shell slabs (which are the box and never do).
local function census(folder)
	local n = { cells = 0, shell = 0, other = 0, deepest = -1, shallowest = 1e9 }
	if folder == nil then return n end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("CellKey") ~= nil then
				n.cells += 1
				local y = d:GetAttribute("Layer") or 0
				if y > n.deepest then n.deepest = y end
				if y < n.shallowest then n.shallowest = y end
			elseif d:GetAttribute("Shell") ~= nil then
				n.shell += 1
			else
				n.other += 1
			end
		end
	end
	return n
end

--=================================================================== 1. a fresh miner has ground

local walker = h:join("Walker", WALKER)
h:advance(1)
h.Players:simulateSpawn(walker, h.workspace)
h:advance(1)

local wShaft = shaftOf(WALKER)
truthy(wShaft ~= nil, "the walker got a shaft")
local wHrp = walker.Character:FindFirstChild("HumanoidRootPart")
truthy(wHrp ~= nil, "…and a character to stand in it")

do
	local at = wHrp.CFrame.Position
	local part, top = groundUnder(wShaft, at.X, at.Z, at.Y)
	truthy(part ~= nil, "the spawn point has ground under it")
	if part then
		truthy(at.Y - top <= 8, "…within a step (" .. string.format("%.1f", at.Y - top)
			.. " studs onto " .. tostring(part.Name) .. ")")
	end
end

do
	-- REVIEW-2, still open: "no SpawnLocation anywhere". Roblox picks the spawn for the frame or
	-- two before CharacterAdded lands, and with none it picks the world origin — which in this
	-- game is the middle of the first player's mouth.
	local pad = h.workspace:FindFirstChild("MinersRest")
	truthy(pad ~= nil, "the world has a SpawnLocation for the frame before the game takes over")
	if pad then
		eq(pad.ClassName, "SpawnLocation", "…and it really is a SpawnLocation, not a decorative slab")
		eq(pad.Anchored, true, "…anchored")
		eq(pad.CanCollide, true, "…and solid enough to land on")
		truthy(pad.Parent == h.workspace, "…parented to the workspace, not to a shaft that gets destroyed")
		-- and it must not be standing inside anybody's mine
		local inside = nil
		for _, f in shafts:GetChildren() do
			for _, d in f:GetChildren() do
				if d:IsA("BasePart") then
					local dx = math.abs(d.Position.X - pad.Position.X)
					local dz = math.abs(d.Position.Z - pad.Position.Z)
					if dx < (d.Size.X + pad.Size.X) / 2 and dz < (d.Size.Z + pad.Size.Z) / 2 then
						inside = d.Name
					end
				end
			end
		end
		eq(inside, nil, "…and it does not overlap anybody's shaft (" .. tostring(inside) .. ")")
	end
end

--============================================== 2. the surface deck: size, plane and reachability

local deck = wShaft and wShaft:FindFirstChild("SurfaceDeck_" .. WALKER, true)
local landingKey = deck and deck:GetAttribute("LandingCell")

do
	truthy(deck ~= nil, "the mouth has a surface deck under the landing point")
	if deck then
		eq(deck:FindFirstChildOfClass("ClickDetector"), nil, "…and it is not something you can mine")
		eq(deck.Anchored, true, "…and it is anchored, so nothing can drop it down the shaft")
		eq(deck.CanCollide, true, "…and you can stand on it")

		-- REVIEW-2: "THE DECK'S LANDING FOOTPRINT IS ASSERTED NOWHERE". The review shrank this
		-- part to a 1x1 stud pillar under a 6x6 cell and all 1797 assertions in the repo stayed
		-- green. It is the ONLY ground the SURFACE button guarantees; if it does not cover the
		-- cell, the button drops the player off the edge of it.
		gt(deck.Size.X, CELL * 0.85, "the deck covers the landing cell across X (" .. tostring(deck.Size.X)
			.. " of " .. CELL .. ")")
		gt(deck.Size.Z, CELL * 0.85, "…and across Z (" .. tostring(deck.Size.Z) .. " of " .. CELL .. ")")
		truthy(deck.Size.X <= CELL and deck.Size.Z <= CELL,
			"…and does not spill out of it into the neighbouring cells")

		-- REVIEW-2, broken by the previous round: the deck was COPLANAR and volume-overlapping
		-- with the breakable rock it sits inside — same 6x6 footprint, same top face at y = 0, at
		-- the one tile the game points every new player at. Opaque coplanar faces z-fight, and a
		-- mouse ray aimed straight down resolves to a tie, so a click on the spawn cell could be a
		-- silent no-op on the first block a player ever tries to mine.
		local top = deck.Position.Y + deck.Size.Y / 2
		truthy(top < 0, "the deck's top face is BELOW the mouth floor, not in the same plane as it ("
			.. string.format("%.2f", top) .. ")")
		truthy(top >= -CELL, "…but still inside the cell it holds up (" .. string.format("%.2f", top) .. ")")
		eq(deck.CanQuery, false, "…and a mouse ray passes straight through it, so no click can tie")

		-- The deck is INSIDE the rock, which is the whole design — a buried slab is invisible and
		-- costs nothing. What must never happen is two opaque faces in the SAME PLANE, because
		-- that is what z-fights and what makes a click ambiguous. So: no face of the deck may
		-- share a plane with a face of any block that overlaps it.
		local function planes(part)
			return {
				part.Position.Y + part.Size.Y / 2, part.Position.Y - part.Size.Y / 2,
				part.Position.X + part.Size.X / 2, part.Position.X - part.Size.X / 2,
				part.Position.Z + part.Size.Z / 2, part.Position.Z - part.Size.Z / 2,
			}
		end
		local deckPlanes = planes(deck)
		local coplanar = {}
		for _, d in blocksOf(wShaft) do
			local overlaps = math.abs(d.Position.X - deck.Position.X) < (d.Size.X + deck.Size.X) / 2
				and math.abs(d.Position.Z - deck.Position.Z) < (d.Size.Z + deck.Size.Z) / 2
				and math.abs(d.Position.Y - deck.Position.Y) < (d.Size.Y + deck.Size.Y) / 2
			if overlaps then
				for i, dp in planes(d) do
					if math.abs(dp - deckPlanes[i]) < 0.001 then
						coplanar[#coplanar + 1] = d.Name .. "/face" .. i
					end
				end
			end
		end
		eq(#coplanar, 0, "no face of a block that overlaps the deck shares a plane with it ("
			.. table.concat(coplanar, ",") .. ")")

		truthy(landingKey ~= nil, "the deck publishes the cell it holds up, so a test need not guess it")
	end
end

do
	-- REVIEW-2: "THE SURFACE TEST IS BOUND TO A HARD-CODED COLUMN". The column dug here is the one
	-- the game itself says the landing stands on, so moving the spawn moves the test with it.
	local lx, ly, lz = Mine.parseKey(tostring(landingKey))
	truthy(lx ~= nil, "the landing cell parses")

	ElevatorEvent:simulateFireServer(walker, "up")
	h:advance(0.5)
	local spawnAt = wHrp.CFrame.Position
	-- and the landing really is over that cell, or the attribute is decoration
	local lp = Mine.localPos(Config, lx, ly, lz)
	local origin = wShaft:FindFirstChild("SellPad_" .. WALKER, true).Position
		- Vector3.new(Mine.localPos(Config, Mine.center(Config), 0, 3).x, 0,
			Mine.localPos(Config, Mine.center(Config), 0, 3).z)
	truthy(math.abs((origin.X + lp.x) - spawnAt.X) < 0.01
		and math.abs((origin.Z + lp.z) - spawnAt.Z) < 0.01,
		"SURFACE lands the miner over the cell the deck says it holds up")

	local broke = 0
	for y = ly, Mine.maxLayer(Config, 0) do
		local b = blockAt(wShaft, Mine.key(lx, y, lz))
		if b and mineOut(walker, b, 12, wHrp) then broke += 1 end
	end
	h:advance(2)
	gt(broke, 8, "CONTROL: the spawn column really was dug out (" .. broke .. " cells broken)")

	ElevatorEvent:simulateFireServer(walker, "up")
	h:advance(1)
	local at = wHrp.CFrame.Position
	truthy(math.abs(at.X - spawnAt.X) < 0.01 and math.abs(at.Z - spawnAt.Z) < 0.01,
		"SURFACE still aims at the surface")
	local part, top = groundUnder(wShaft, at.X, at.Z, at.Y)
	truthy(part ~= nil, "SURFACE puts the miner over something solid after the column is gone")
	if part then
		local drop = at.Y - top
		print(string.format("  SURFACE: whole spawn column dug out (%d cells), landing y=%.2f,"
			.. " ground %s top y=%.2f, drop %.2f studs", broke, at.Y, tostring(part.Name), top, drop))
		truthy(drop <= 8, "…and within a step of it (drop " .. string.format("%.1f", drop)
			.. " studs onto " .. tostring(part.Name) .. ")")
		eq(part:FindFirstChildOfClass("ClickDetector"), nil,
			"…and that floor is not something they can mine away too (" .. tostring(part.Name) .. ")")
	end
end

--============================================================ 3. NO PART EVER STANDS IN OPEN SPACE

-- The dead branch the review found in drainBuild claimed to stop this; the branch could not fire,
-- so what protects it now is the symptom, measured. A Part standing in a cell the player has dug
-- out is a block that grew back — the whole of REVIEW #1 — whichever code path put it there.
do
	-- Everything the walker has dug so far, checked from the outside: the cells they broke must
	-- still be empty, and nothing may have been rebuilt on top of them.
	local lx, ly, lz = Mine.parseKey(tostring(landingKey))
	local standing = {}
	for y = ly, Mine.maxLayer(Config, 0) do
		local k = Mine.key(lx, y, lz)
		if blockAt(wShaft, k) ~= nil then standing[#standing + 1] = k end
	end
	eq(#standing, 0, "not one cell of the dug column has been rebuilt (" .. table.concat(standing, ",") .. ")")
end

--=========================================== 4. ONE BAD PART MUST NOT STOP THE WORLD FOR EVERYBODY

do
	-- REVIEW-2: `pumping` is one module-level boolean with no pcall around the drain, so any error
	-- thrown inside makeCellPart killed the pump thread with the flag stuck true and NO PART WAS
	-- EVER BUILT AGAIN for any player in the server. The review could not reach an error through a
	-- legitimate path, so it reported the finding at reading level. This reaches it: the Part
	-- factory itself is made to fail once, from outside the game, which is the one thing that can
	-- go wrong inside makeCellPart that the game cannot cause on its own.
	local pumper = h:join("Pumper", PUMPER)
	h:advance(1)
	h.Players:simulateSpawn(pumper, h.workspace)
	h:advance(2)
	local pShaft = shaftOf(PUMPER)
	truthy(pShaft ~= nil, "the pump tester got a shaft")
	local pHrp = pumper.Character and pumper.Character:FindFirstChild("HumanoidRootPart")

	local warnBefore = #h.warnings
	poisonParts = 1

	-- dig down the centre; the first break reveals far more than one frame's worth of faces, so
	-- the poisoned Part lands inside the pump rather than inside the click handler.
	local burstBefore = partCount()
	local dug = 0
	for y = 1, 8 do
		local b = blockAt(pShaft, Mine.key(5, y, 5))
		if b and mineOut(pumper, b, 12, pHrp) then dug += 1 end
	end
	h:advance(3)

	local built = partCount() - burstBefore
	eq(poisonParts, 0, "CONTROL: the injected failure really did fire")
	gt(dug, 3, "CONTROL: …and the miner kept digging through it (" .. dug .. " of 8 layers)")
	truthy(#h.warnings > warnBefore, "the failed Part is reported rather than swallowed")
	truthy(string.find(tostring(h.warnings[warnBefore + 1] or ""), "could not build cell") ~= nil,
		"…by name, as ONE cell rather than as the whole queue ("
			.. tostring(h.warnings[warnBefore + 1]) .. ")")
	gt(built, 20, "…and the rest of the cave was still built around it (" .. built .. " parts)")
	print(string.format("  PUMP: one Part poisoned mid-dig -> %d of 8 layers still dug, %d further"
		.. " parts built around the missing one", dug, built))

	-- AND THE PUMP IS NOT WEDGED. This is the finding itself: with the flag stuck up, no Part is
	-- ever built again for anybody. So break new ground — the deepest cell of the centre column,
	-- whose neighbours below have never been exposed — and watch the world grow past the block
	-- that was just removed.
	local after = partCount()
	local nextBlock, nextKey = nil, nil
	for y = 9, Mine.maxLayer(Config, 0) do
		local k = Mine.key(5, y, 5)
		local b = blockAt(pShaft, k)
		if b and b:FindFirstChildOfClass("ClickDetector") then nextBlock, nextKey = b, k break end
	end
	truthy(nextBlock ~= nil, "there is unbroken ground below the dig to swing at")
	if nextBlock then
		truthy(mineOut(pumper, nextBlock, 40, pHrp), "…and it breaks (" .. tostring(nextKey) .. ")")
		h:advance(2)
		gt(partCount(), after, "a swing AFTER the failure still builds the faces behind it ("
			.. after .. " -> " .. partCount() .. ")")
	end
	-- AND THE CASE A pcall CANNOT COVER: the failure handler itself throwing. That kills the pump
	-- thread outright, wherever the pcall boundaries are — so what has to hold is not "the error
	-- was caught" but "a dead pump does not stay dead". The lease is what makes that true.
	local wedgeBefore = partCount()
	poisonParts = 1
	poisonWarns = 1
	for y = 10, 14 do
		local b = blockAt(pShaft, Mine.key(5, y, 5))
		if b then mineOut(pumper, b, 20, pHrp) end
	end
	h:advance(3)
	eq(poisonParts, 0, "CONTROL: the second injected Part failure fired")
	eq(poisonWarns, 0, "CONTROL: …and took the pump thread down with it")

	-- Now play on. The faces the dead pump never built are not there to click, so the miner does
	-- what a player would: swings at the deepest thing still standing. Within a second of that,
	-- a fresh pump must have taken over and the world must start growing again.
	local recovered = false
	for _ = 1, 12 do
		local target, deepest = nil, -1
		for _, d in blocksOf(pShaft) do
			local layer = d:GetAttribute("Layer") or 0
			if d:FindFirstChildOfClass("ClickDetector") ~= nil
				and string.match(tostring(d.Name), "^Bedrock_") == nil and layer > deepest then
				target, deepest = d, layer
			end
		end
		if target == nil then break end
		local before = partCount()
		mineOut(pumper, target, 25, pHrp)
		h:advance(1.2)
		if partCount() > before then recovered = true break end
	end
	truthy(recovered, "a pump killed by its own error handler does not stay dead — the world grows again")
	print("  PUMP: pump thread killed by a failing warn -> world grew again: " .. tostring(recovered))
	gt(partCount(), wedgeBefore - 40, "…and the shaft is still a shaft (" .. partCount() .. " parts)")

	h:leave(pumper)
	h:advance(1)
end

--================================================== 5. THE CAVE SURVIVES A REJOIN (the printer)

do
	-- REVIEW-2, still open #1: `opened` was per-session, so a rejoining player found every cell
	-- except the centre column standing again, ore and all. Measured end to end by the review:
	-- mine the eight ore cells in the mouth, sell for $48, leave, rejoin, and all eight are back;
	-- sell them again for another $48; repeat at will.
	local relog = h:join("Relog", RELOG)
	h:advance(1)
	h.Players:simulateSpawn(relog, h.workspace)
	h:advance(2)
	local rShaft = shaftOf(RELOG)
	truthy(rShaft ~= nil, "the relogger got a shaft")
	local rHrp = relog.Character and relog.Character:FindFirstChild("HumanoidRootPart")

	-- mine every ore cell exposed in the mouth, plus a side tunnel that is NOT the centre column
	local mined = {}
	for _, d in blocksOf(rShaft) do
		if (d:GetAttribute("Ore") or 0) > 0 then
			local k = tostring(d:GetAttribute("CellKey"))
			if mineOut(relog, d, 40, rHrp) then mined[#mined + 1] = k end
		end
	end
	for _, cell in { { 4, 1, 6 }, { 4, 2, 6 }, { 3, 2, 6 } } do
		local k = Mine.key(cell[1], cell[2], cell[3])
		local b = blockAt(rShaft, k)
		if b and mineOut(relog, b, 40, rHrp) then mined[#mined + 1] = k end
	end
	h:advance(2)
	gt(#mined, 5, "CONTROL: the relogger really did mine some cells out (" .. #mined .. ")")
	print("  RELOG: mined " .. #mined .. " cells out before leaving")

	ElevatorEvent:simulateFireServer(relog, "up")
	h:advance(1)
	local sold = stateOf(relog)
	local cashBefore = sold.cash
	local earnedBefore = sold.earned
	gt(cashBefore, 0, "CONTROL: and sold the haul for something ($" .. cashBefore .. ")")

	h:leave(relog)
	h:advance(2)

	local relog2 = h:join("Relog", RELOG)
	h:advance(1)
	h.Players:simulateSpawn(relog2, h.workspace)
	h:advance(6) -- the restore builds the first frame outright and pumps the rest
	local rShaft2 = shaftOf(RELOG)
	truthy(rShaft2 ~= nil, "…and got one back on rejoin")

	local backFromTheDead = {}
	for _, k in mined do
		if blockAt(rShaft2, k) ~= nil then backFromTheDead[#backFromTheDead + 1] = k end
	end
	eq(#backFromTheDead, 0, "not one mined cell is standing again after a rejoin ("
		.. #backFromTheDead .. " of " .. #mined .. ": " .. table.concat(backFromTheDead, ",") .. ")")
	print("  RELOG: after leaving and rejoining, " .. #backFromTheDead .. " of " .. #mined
		.. " mined cells are standing again; cash $" .. cashBefore .. " came back")

	local s2 = stateOf(relog2)
	eq(s2.cash, cashBefore, "their cash came back")
	eq(s2.earned, earnedBefore, "…and this run's earnings, which is what the rebirth gate reads")

	-- and the sale cannot be repeated: there is nothing left to pick up in those cells
	local pad = rShaft2:FindFirstChild("SellPad_" .. RELOG, true)
	pad:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(relog2)
	h:advance(1)
	eq(stateOf(relog2).cash, cashBefore, "selling again pays nothing — the ore is gone, not respawned")
	truthy(string.find(lastToast(), "Nothing to sell") ~= nil,
		"…and says so rather than paying twice (" .. lastToast() .. ")")

	-- THE TUNNELS come back too, not just the centre column: the side cells at x=4/3, z=6 are not
	-- on the column and were gone in the version that only replayed Mine.column.
	local sideRestored = 0
	for _, cell in { { 4, 1, 6 }, { 4, 2, 6 }, { 3, 2, 6 } } do
		if blockAt(rShaft2, Mine.key(cell[1], cell[2], cell[3])) == nil then sideRestored += 1 end
	end
	eq(sideRestored, 3, "the side tunnel is still a tunnel, not just the elevator column")

	-- and the restored world is not a shell: the faces around the dig are real Parts
	gt(#blocksOf(rShaft2), 100, "the restored shaft has its walls (" .. #blocksOf(rShaft2) .. " blocks)")
	h:leave(relog2)
	h:advance(1)
end

--=========================================== 5b. THE BOX IS FIVE SLABS, NOT TEN THOUSAND CUBES

do
	-- REVIEW-3's open finding, and the measurement that decides what to do about it: a fully
	-- excavated shaft at the deepest wall is 10 097 Parts and every single one of them is bedrock —
	-- the ring (10 048) and the floor (49). There is no rock left to cull. So the ring and the floor
	-- are geometry now: four wall slabs and a floor slab, whatever the depth.
	local n = census(wShaft)
	eq(n.shell, 5, "the box is five slabs (" .. n.shell .. ")")

	local bedrockCubes = 0
	for _, d in wShaft:GetDescendants() do
		if d:IsA("BasePart") and string.match(tostring(d.Name), "^Bedrock_") then bedrockCubes += 1 end
	end
	eq(bedrockCubes, 0, "…and not one bedrock cube is left (" .. bedrockCubes .. ")")

	-- AND IT IS STILL A SEALED BOX. This is the thing the slabs must not lose: the ring is what
	-- stops a player walking out of the world, and the rim is three cells tall because one cell is
	-- 6 studs and a Roblox jump clears 7.2. Checked by sampling the centre of every ring cell of the
	-- mouth's own layers and asking whether a slab is standing in it.
	local slabs = {}
	for _, d in wShaft:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Shell") ~= nil then slabs[#slabs + 1] = d end
	end
	-- Where this shaft's local origin sits in the world, read off the one part whose cell the
	-- server states out loud: the SELL pad stands on cell (centre, 0, 3), half a stud proud of the
	-- cell floor.
	local padCell = Mine.localPos(Config, Mine.center(Config), 0, 3)
	local padPos = wShaft:FindFirstChild("SellPad_" .. WALKER, true).Position
	local origin = padPos - Vector3.new(padCell.x, padCell.y - CELL / 2 + 0.5, padCell.z)
	local gaps, ringSamples = {}, 0
	for y = 0, 24 do
		for x = 1, 9 do
			for z = 1, 9 do
				if x == 1 or x == 9 or z == 1 or z == 9 then
					ringSamples += 1
					local lp = Mine.localPos(Config, x, y, z)
					local at = origin + Vector3.new(lp.x, lp.y, lp.z)
					local sealed = false
					for _, s in slabs do
						if math.abs(at.X - s.Position.X) <= s.Size.X / 2
							and math.abs(at.Y - s.Position.Y) <= s.Size.Y / 2
							and math.abs(at.Z - s.Position.Z) <= s.Size.Z / 2 then sealed = true end
					end
					if not sealed and #gaps < 5 then gaps[#gaps + 1] = Mine.key(x, y, z) end
				end
			end
		end
	end
	gt(ringSamples, 700, "CONTROL: the sample really covered the ring (" .. ringSamples .. " cells)")
	eq(#gaps, 0, "every ring cell of the shaft is inside a slab — the box is still sealed ("
		.. table.concat(gaps, ",") .. ")")

	-- the rim: the wall has to stand PROUD of the mouth, or a jump clears it
	local wallTop = -math.huge
	for _, s in slabs do
		if s:GetAttribute("Shell") == "wall" then
			wallTop = math.max(wallTop, s.Position.Y + s.Size.Y / 2)
		end
	end
	gt(wallTop, CELL, "the wall stands proud of the mouth floor, so nobody jumps out (top y="
		.. string.format("%.1f", wallTop) .. ")")

	-- and the depth wall can still explain itself, off the floor slab rather than 49 cubes
	local floorSlab = nil
	for _, s in slabs do if s:GetAttribute("Shell") == "floor" then floorSlab = s end end
	truthy(floorSlab ~= nil, "the depth wall is a slab")
	truthy(floorSlab and floorSlab:FindFirstChildOfClass("ClickDetector") ~= nil,
		"…and it is clickable, so hitting the bottom of the cave says why")
end

--============================== 7. NOTHING UNLOADED — a deep shaft used to be rebuilt and kept

do
	-- THE FINDING, END TO END. A veteran whose elevator column runs 120 layers down used to have
	-- every face of it rebuilt on join and held for the whole session. Now the Parts exist for the
	-- layers around the miner and nowhere else — and `opened`, which IS the cave, is untouched by
	-- any of it, so nothing about the save or the restore changes.
	local streamer = h:join("Streamer", STREAM)
	h:advance(1)
	h.Players:simulateSpawn(streamer, h.workspace)
	h:advance(6)
	local sShaft = shaftOf(STREAM)
	truthy(sShaft ~= nil, "the deep veteran got a shaft")
	local sHrp = streamer.Character:FindFirstChild("HumanoidRootPart")

	local s = stateOf(streamer)
	eq(s.rebirths, STREAM_REBIRTHS, "CONTROL: they really are eight rebirths in")
	eq(s.depth, 720, "CONTROL: …with a 120-layer column already dug (720 studs)")
	eq(s.maxDepth, 720, "CONTROL: …which is exactly the depth wall of that cave")

	local atTop = census(sShaft)
	print(string.format("  STREAM: 120-layer column, miner at the mouth -> %d cell parts + %d slabs,"
		.. " layers %d..%d", atTop.cells, atTop.shell, atTop.shallowest, atTop.deepest))
	gt(atTop.cells, 30, "CONTROL: the mouth of the restored shaft IS built (" .. atTop.cells .. " parts)")
	truthy(atTop.cells < 900, "a miner standing at the mouth does not hold the whole 120-layer shaft ("
		.. atTop.cells .. " parts)")
	truthy(atTop.deepest <= Config.Mine.StreamLayers + 1,
		"…and nothing below the band is built (deepest layer " .. atTop.deepest .. ")")

	-- DESCEND. The bottom of the shaft has to be there when they arrive — not a frame later, or the
	-- miner falls through the floor that has not been built yet and lands on bedrock.
	ElevatorEvent:simulateFireServer(streamer, "down")
	-- NOT ADVANCED. The ground has to be under them the instant they arrive, in the same frame the
	-- CFrame is set — a pump that gets round to it next frame is a miner falling through a floor
	-- that does not exist yet, and the only other thing under a dug shaft is the bedrock 720 studs
	-- down. Everything below this line is allowed to take a frame; this is not.
	do
		local at = sHrp.CFrame.Position
		local ground, top = groundUnder(sShaft, at.X, at.Z, at.Y)
		truthy(ground ~= nil, "DESCEND has ground under the landing IN THE SAME FRAME it lands")
		if ground then
			truthy(at.Y - top <= 8, "…within a step, before the pump has run once (drop "
				.. string.format("%.1f", at.Y - top) .. " onto " .. tostring(ground.Name) .. ")")
		end

		-- …AND THE WHOLE LANDING COLUMN, not whichever faces the pump's first budget happened to
		-- reach. The pump drains an arbitrarily ordered list PartsPerFrame at a time, so "the floor
		-- was there" can be luck; what cannot be luck is every solid cell of the 3x3 column around
		-- the landing being up while the pump is still visibly behind. Mine is used here to ADDRESS
		-- which cells are solid, never to predict how many.
		local w = Mine.world(Config, STREAM_REBIRTHS)
		local c = Mine.center(Config)
		local ly = w.maxLayer
		local wantCol, haveCol = 0, 0
		for dx = -1, 1 do
			for dz = -1, 1 do
				for y = ly - Config.Mine.StreamLandingLayers, ly do
					local x, z = c + dx, c + dz
					if not (dx == 0 and dz == 0) and Mine.isSolid(Config, w, x, y, z) then
						wantCol += 1
						if blockAt(sShaft, Mine.key(x, y, z)) ~= nil then haveCol += 1 end
					end
				end
			end
		end
		gt(wantCol, 5, "CONTROL: the landing column has solid cells to build (" .. wantCol .. ")")
		eq(haveCol, wantCol, "the whole landing column is up in the landing frame (" .. haveCol
			.. " of " .. wantCol .. ")")
		truthy(census(sShaft).cells < 92, "CONTROL: …while the pump is still behind ("
			.. census(sShaft).cells .. " of the band's 92 built so far)")
	end
	h:advance(3)
	local atBottom = census(sShaft)
	print(string.format("  STREAM: after DESCEND -> %d cell parts + %d slabs, layers %d..%d",
		atBottom.cells, atBottom.shell, atBottom.shallowest, atBottom.deepest))
	gt(atBottom.deepest, 100, "DESCEND built the bottom of the shaft (deepest layer "
		.. atBottom.deepest .. ")")
	gt(atBottom.shallowest, 90, "…and let the top of it go (shallowest layer "
		.. atBottom.shallowest .. ")")
	truthy(atBottom.cells < 900, "…without ever holding both ends at once (" .. atBottom.cells .. " parts)")

	-- and they landed on something, which is the thing the synchronous landing build exists for
	local at = sHrp.CFrame.Position
	local ground, top = groundUnder(sShaft, at.X, at.Z, at.Y)
	truthy(ground ~= nil, "DESCEND put the miner over something solid")
	if ground then
		truthy(at.Y - top <= 8, "…and within a step of it (drop "
			.. string.format("%.1f", at.Y - top) .. " onto " .. tostring(ground.Name) .. ")")
	end

	-- THE CAVE IS NOT THE PARTS. Unloading a Part must not unmark a dug cell: mine one more layer
	-- at the bottom, ride to the surface (which unloads all of it), come back down, and the cell
	-- must still be dug and the ore must still be gone.
	local deepest = nil
	for _, d in blocksOf(sShaft) do
		local y = d:GetAttribute("Layer") or 0
		if d:FindFirstChildOfClass("ClickDetector") ~= nil and y >= atBottom.deepest - 2
			and (deepest == nil or y > (deepest:GetAttribute("Layer") or 0)) then deepest = d end
	end
	truthy(deepest ~= nil, "there is rock at the bottom of the shaft to swing at")
	local deepKey = deepest and tostring(deepest:GetAttribute("CellKey"))
	if deepest then
		truthy(mineOut(streamer, deepest, 12, sHrp), "…and it breaks (" .. tostring(deepKey) .. ")")
	end
	h:advance(1)

	-- AND A QUEUE LEFT OVER FROM THE OLD BAND MUST NOT BUILD ITSELF ANYWAY. Riding up one frame
	-- after riding down leaves the bottom band's faces still queued; if the drain does not re-check
	-- the band, every one of them is built behind the miner who has just left.
	-- Start from the TOP, or DESCEND is a no-op: the band is already where it would move to and
	-- nothing gets queued at all.
	ElevatorEvent:simulateFireServer(streamer, "up")
	h:advance(2)
	ElevatorEvent:simulateFireServer(streamer, "down")
	-- NO advance. The pump builds its first budget inside the caller's own frame and leaves the
	-- rest queued, so pressing SURFACE right now moves the band with that queue still full — the
	-- only moment the drain's own band re-check can be observed at all.
	ElevatorEvent:simulateFireServer(streamer, "up")
	-- …and sampled EVERY FRAME, not once at the end. The periodic sweep tidies up 0.35 s later, so
	-- a single measurement after the fact sees a clean world whether the drain re-checked or not.
	-- What the check actually prevents is the SPIKE: a queue full of faces built behind a miner who
	-- has already left, one frame before something else destroys them again.
	local spike = 0
	for _ = 1, 10 do
		h:advance(1 / 60)
		spike = math.max(spike, census(sShaft).deepest)
	end
	truthy(spike <= Config.Mine.StreamLayers + 2,
		"a build queued for the bottom does not build itself after the miner has gone back up"
			.. " (deepest layer seen in any frame: " .. spike .. ")")
	h:advance(2)

	ElevatorEvent:simulateFireServer(streamer, "down")
	h:advance(3)
	ElevatorEvent:simulateFireServer(streamer, "up")
	h:advance(2)
	local backUp = census(sShaft)
	print(string.format("  STREAM: after SURFACE -> %d cell parts + %d slabs, layers %d..%d",
		backUp.cells, backUp.shell, backUp.shallowest, backUp.deepest))
	truthy(backUp.deepest <= Config.Mine.StreamLayers + 1,
		"riding back up unloads the bottom of the shaft again (deepest layer "
			.. backUp.deepest .. ")")
	eq(blockAt(sShaft, tostring(deepKey)), nil,
		"CONTROL: the cell mined at the bottom is not standing in the mouth's band either")

	ElevatorEvent:simulateFireServer(streamer, "down")
	h:advance(3)
	eq(blockAt(sShaft, tostring(deepKey)), nil,
		"a cell mined before the unload is STILL mined after the reload — the cave is `opened`,"
			.. " not the Parts")
	gt(census(sShaft).deepest, 100, "CONTROL: …and the bottom of the shaft really was rebuilt")

	-- A HALF-BROKEN BLOCK KEEPS ITS DAMAGE. Everything else about a Part is re-derivable; the hit
	-- points a player has already knocked off it are not, and healing a block because they walked
	-- away is a swing they paid for and did not get.
	-- It has to be a block ONE SWING CANNOT FINISH, or "it was damaged" and "it was destroyed" are
	-- the same observation: a Singularity Bore does 170 and capped stone at this depth is 24. The
	-- deepest tiers are the only rock in the game tougher than that (diamond 220, obsidian 396).
	-- And it has to be near the BOTTOM, so coming back down puts it inside the band rather than
	-- just outside it.
	local deepNow = census(sShaft).deepest
	local victim = nil
	for _, d in blocksOf(sShaft) do
		local y = d:GetAttribute("Layer") or 0
		if d:FindFirstChildOfClass("ClickDetector") ~= nil and y >= deepNow - 3
			and (d:GetAttribute("Ore") or 0) >= 4 then victim = d break end
	end
	truthy(victim ~= nil, "there is a tough block at the bottom to half-break")
	if victim then
		local vkey = tostring(victim:GetAttribute("CellKey"))
		standOn(sHrp, victim)
		victim:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(streamer)
		h:advance(0.4)
		local damaged = victim.Size.X
		truthy(damaged < CELL, "CONTROL: one swing damaged it (" .. string.format("%.2f", damaged) .. ")")
		ElevatorEvent:simulateFireServer(streamer, "up")
		h:advance(2)
		eq(blockAt(sShaft, vkey), nil, "CONTROL: …and it was unloaded when the miner left")
		ElevatorEvent:simulateFireServer(streamer, "down")
		h:advance(3)
		local back = blockAt(sShaft, vkey)
		truthy(back ~= nil, "…and rebuilt when they came back")
		if back then
			truthy(back.Size.X < CELL, "…still carrying the damage it had (" ..
				string.format("%.2f", back.Size.X) .. " of " .. CELL .. ")")
		end
	end

	-- WALKING DOWN, WITHOUT THE ELEVATOR. Every band move above came from a teleport, which moves
	-- it explicitly. A player who falls down their own open column moves the band by MOVING, and
	-- the only thing that notices is the periodic sweep — without it they walk out of their own
	-- lit world into a shaft with no walls and stop being able to dig at all.
	ElevatorEvent:simulateFireServer(streamer, "up")
	h:advance(2)
	truthy(census(sShaft).deepest <= Config.Mine.StreamLayers + 2,
		"CONTROL: back at the mouth, the deep end is unloaded again")
	local midLayer = 40
	sHrp.CFrame = CFrame.new(sHrp.CFrame.Position.X,
		Mine.floorY(Config, midLayer) + 4, sHrp.CFrame.Position.Z)
	h:advance(Config.Mine.StreamPeriod * 4)
	local mid = census(sShaft)
	print(string.format("  STREAM: walked (not teleported) to layer %d -> %d cell parts,"
		.. " layers %d..%d", midLayer, mid.cells, mid.shallowest, mid.deepest))
	gt(mid.deepest, midLayer - 2, "walking down the shaft brings the walls with you (deepest layer "
		.. mid.deepest .. ")")
	gt(mid.shallowest, 2, "…and lets the mouth go behind you (shallowest layer "
		.. mid.shallowest .. ")")

	h:leave(streamer)
	h:advance(1)
end

--=================================================== 6. THE WHOLE LOOP, SPAWN TO REBIRTH, WALKED

local walkReport = { swings = 0, broke = 0, sells = 0, buys = 0, trips = 0, deepest = 0, peak = 0 }

do
	-- Everything above tests one rule each. This plays the game: dig, fill the bag, ride up, sell,
	-- buy what you can afford, go back down, until the rebirth is affordable — and then take it.
	-- Four games in this repo shipped with thousands of green assertions and a core loop that was
	-- unreachable in the built world, so this is the assertion that matters most.
	local s = stateOf(walker)
	truthy(s ~= nil, "the walker has a state to play against")

	local SWING_BUDGET = 6000
	local guard = 0
	while guard < SWING_BUDGET do
		guard += 1
		s = stateOf(walker)
		if s.canRebirth then break end

		-- bag full? ride up, sell, shop, ride back down.
		if s.carried >= s.capacity then
			ElevatorEvent:simulateFireServer(walker, "up")
			h:advance(0.4)
			walkReport.trips += 1
			walkReport.sells += 1
			local before = stateOf(walker)
			for _, kind in { "pickaxe", "backpack", "lamp" } do
				BuyEvent:simulateFireServer(walker, kind)
				h:advance(0.1)
			end
			if stateOf(walker).pickTier > before.pickTier then walkReport.buys += 1 end
			ElevatorEvent:simulateFireServer(walker, "down")
			h:advance(0.4)
		end

		-- pick a target: the deepest ore in the world, else the deepest breakable rock.
		-- The bedrock FLOOR carries a ClickDetector on purpose, so it can explain itself instead
		-- of being a rock that ignores you — so a "deepest clickable block" policy hammers the
		-- depth wall for ever. (It did: 6000 swings, 0 blocks broken, on the first run of this
		-- file. That is a real thing a player can do too; the toast is what stops them.)
		local best, bestScore = nil, -1
		for _, d in blocksOf(wShaft) do
			if d:FindFirstChildOfClass("ClickDetector") ~= nil
				and string.match(tostring(d.Name), "^Bedrock_") == nil then
				local layer = d:GetAttribute("Layer") or 0
				local ore = d:GetAttribute("Ore") or 0
				local score = layer * 10 + (ore > 0 and 5 or 0)
				if score > bestScore then best, bestScore = d, score end
			end
		end
		if best == nil then break end
		if (best:GetAttribute("Layer") or 0) > walkReport.deepest then
			walkReport.deepest = best:GetAttribute("Layer")
		end

		local cd = best:FindFirstChildOfClass("ClickDetector")
		local before = best.Parent
		-- walk over to it first: a swing has to come from inside ReachStuds of the block
		standOn(wHrp, best)
		cd.MouseClick:Fire(walker)
		h:advance(Config.Mine.SwingCooldown + 0.02)
		walkReport.swings += 1
		if before ~= nil and best.Parent == nil then walkReport.broke += 1 end
		local live = census(wShaft).cells
		if live > walkReport.peak then walkReport.peak = live end
	end

	s = stateOf(walker)
	print(string.format("  WALK: %d swings, %d blocks broken, %d surface trips, deepest layer %d,"
		.. " $%d earned, rebirth needs $%d",
		walkReport.swings, walkReport.broke, walkReport.trips, walkReport.deepest,
		s.earned, s.rebirthCost))
	print(string.format("  WALK: peak %d cell parts + 5 slabs held at once; worst swing reached"
		.. " %.1f studs (ReachStuds %d)", walkReport.peak, worstReach, Config.Mine.ReachStuds))

	-- THE REACH. REVIEW-3 listed this as something neither gate could see: both fired
	-- ClickDetectors from wherever the character happened to be, so "can a player actually get
	-- close enough to swing at that" was never asked. Every swing above came from a miner standing
	-- on the block, and this is the number that says so.
	truthy(worstReach <= Config.Mine.ReachStuds, "every swing in this file was inside the server's"
		.. " own reach (" .. string.format("%.1f", worstReach) .. " of " .. Config.Mine.ReachStuds .. ")")
	gt(worstReach, 0, "CONTROL: the miner really did have to move to reach them")

	-- …and the shaft never held more than a band's worth while they did it. Un-banded, a
	-- rebirth-0 dig to the wall is 1080 Parts and a rebirth-24 one is 11960.
	truthy(walkReport.peak <= 1600, "the whole walk never held more than a band of Parts ("
		.. walkReport.peak .. ")")

	gt(walkReport.broke, 50, "the walker actually mined (" .. walkReport.broke .. " blocks)")
	gt(walkReport.trips, 0, "…had to haul up and sell at least once")
	gt(s.earned, 0, "…and earned something for it ($" .. s.earned .. ")")
	gt(walkReport.deepest, 5, "…and got below the surface layers (layer " .. walkReport.deepest .. ")")
	truthy(s.canRebirth, "A PLAYER CAN REACH THE FIRST REBIRTH BY PLAYING ("
		.. "$" .. s.earned .. " earned vs $" .. s.rebirthCost .. " needed, "
		.. walkReport.swings .. " swings)")
	eq(s.rebirthCost, Prestige.requirement(Config, Ore, 0),
		"…and the price the HUD is quoting is the one the module charges")
end

do
	-- And the button at the end of it works.
	local before = stateOf(walker)
	RebirthEvent:simulateFireServer(walker)
	h:advance(3)
	local after = stateOf(walker)
	eq(after.rebirths, before.rebirths + 1, "the rebirth went through")
	eq(after.cash, 0, "cash is wiped")
	eq(after.earned, 0, "this run's earnings are wiped — the next price is a new cave's price")
	eq(after.depth, 0, "this run's depth is wiped")
	eq(after.maxDepth, 216, "and the wall moved 12 layers deeper, to 216 studs")
	truthy(math.abs(after.mult - 1.8) < 1e-6, "the multiplier is live (x" .. tostring(after.mult) .. ")")
	gt(after.rebirthCost, before.rebirthCost, "…and the next rebirth is priced against the bigger cave")

	local fresh = shaftOf(WALKER)
	local n = #blocksOf(fresh)
	eq(n, 49, "the new cave is a fresh 49-cell mouth, not the old one with holes in it ("
		.. n .. " blocks)")
	eq(census(fresh).shell, 5, "…inside a fresh five-slab box")
end

do
	-- REBIRTH THROWS THE OLD CAVE AWAY, INCLUDING ITS SAVE. A rebirth that kept openedBits would
	-- punch the old cave's holes into a world generated from a different seed.
	h:leave(walker)
	h:advance(2)
	local again = h:join("Walker", WALKER)
	h:advance(1)
	h.Players:simulateSpawn(again, h.workspace)
	h:advance(4)
	local sh = shaftOf(WALKER)
	local n = #blocksOf(sh)
	eq(n, 49, "rejoining after a rebirth builds a clean 49-cell mouth (" .. n .. ")")
	local s = stateOf(again)
	eq(s.rebirths, 1, "…with the rebirth kept")
	eq(s.depth, 0, "…and no depth carried over from the cave that was thrown away")
end

--============================================================================ done

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
-- The two failures this file injects on purpose are not defects; anything else is.
for _, e in h:errors() do
	if string.find(tostring(e), "injected: ") ~= nil then
		print("  [injected, expected] " .. e)
	else
		print("scheduler error: " .. e)
		failed += 1
	end
end
print(string.format("deep vein WALK: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein walk failed", 0)
end
