-- Deep Vein — the shaft has to be IN THE WORLD, and swinging at it has to actually mine.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein.luau
--
-- ALWAYS re-run wrap.py first. This file reads build/deep-vein.luau, not the game's src/, and a
-- stale bundle cost half an hour during this build: a fix that was already on disk (os.clock ->
-- tick, because os.clock is CPU time and barely moves headless, so the swing cooldown refused
-- every swing the emulator made) simply was not in the bundle, and the dig loop looked broken
-- when it was not.
--
-- WHY THIS FILE EXISTS AT ALL. Grow a Crystal shipped with `part.Parent` missing from makeSocket.
-- The Part was built, sized, positioned, named, given its attributes and handed a ClickDetector,
-- and then left unparented — so the entire core loop of a published game was unreachable, and
-- all 166 unit tests stayed green, because not one of them could see the workspace. An
-- unparented Instance raises nothing and warns nothing. The only thing that catches it is asking
-- the workspace. So this file asks the workspace, and then it digs.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 1280, 720 },
	touch = false,
})

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

local ME, STRANGER, LOADED, GHOST, REUSER = 5150, 6161, 7272, 8383, 9494
local CELL = 6 -- Config.Mine.CellSize
local RIM_MULT = 3

--============================================================ preloaded saves

-- The server stores under "u_<uid>" with the profile inside `.data`, and the emulator's
-- DataStore does a real JSON round-trip on write — so the integer `inventory` keys below come
-- back as STRINGS and the server's numKeys normalisation is exercised rather than assumed.
local store = h.services.DataStoreService:GetDataStore("DeepVein_v1")

-- A veteran: rich enough to rebirth, already 24 layers down (so the elevator column is
-- restored), and carrying a completely full backpack of iron.
store:SetAsync("u_" .. LOADED, {
	data = {
		cash = 40000, totalCash = 40000, inventory = { [2] = 12 },
		pickTier = 2, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depthLayer = 24, bestLayer = 24,
	},
})

assert(h:tryRun("server/Main.server"))
h:advance(1)

local remotes = h.services.ReplicatedStorage:FindFirstChild("VeinRemotes")
truthy(remotes ~= nil, "the server published its remotes")
local StateEvent = remotes:FindFirstChild("State")
local ElevatorEvent = remotes:FindFirstChild("Elevator")
local BuyEvent = remotes:FindFirstChild("Buy")
local RebirthEvent = remotes:FindFirstChild("Rebirth")
local ToastEvent = remotes:FindFirstChild("Toast")

local toasts = {}
ToastEvent.OnClientEvent:Connect(function(msg) table.insert(toasts, tostring(msg)) end)
local function lastToast(): string
	return toasts[#toasts] or ""
end

-- The newest state payload the server pushed to this player.
local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end

local me = h:join("Digger", ME)
h:advance(1)
h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

--============================================================ the shaft is in the world

local shafts = h.workspace:FindFirstChild("Shafts")
-- CONTROL for the diagnosis, not for the logic: if the FOLDER is missing too, the failure is
-- "nothing was built at all", which is a different bug from "the blocks were orphaned".
truthy(shafts ~= nil, "workspace.Shafts exists (control: the builder ran at all)")
local shaft0 = shafts and shafts:FindFirstChild("Shaft_0")
truthy(shaft0 ~= nil, "the joining player got workspace.Shafts.Shaft_0")

local function scan(folder)
	local n = { parts = 0, rock = 0, ore = 0, bedrock = 0, pads = 0, lights = 0, clicks = 0 }
	if not folder then return n end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			n.parts += 1
			local nm = tostring(d.Name)
			if string.match(nm, "^Rock_") then n.rock += 1 end
			if string.match(nm, "^Ore_") then n.ore += 1 end
			if string.match(nm, "^Bedrock_") then n.bedrock += 1 end
			if string.match(nm, "^SellPad_") then n.pads += 1 end
		end
		if d.ClassName == "PointLight" then n.lights += 1 end
		if d.ClassName == "ClickDetector" then n.clicks += 1 end
	end
	return n
end

do
	local n = scan(shaft0)
	print(string.format("  Shaft_0 on join: %d parts (%d rock, %d ore, %d bedrock, %d pad), %d clickdetectors",
		n.parts, n.rock, n.ore, n.bedrock, n.pads, n.clicks))
	gt(n.parts, 0, "the shaft is parented into the workspace at all")
	-- The recorded figure for a brand new miner: the 7x7 mouth exposes 49 floor cells (41 plain
	-- rock + 8 copper at layer 1) plus the 32-cell bedrock ring at layer 0 and the 32 behind the
	-- floor at layer 1, plus the SELL pad. Spelled out rather than recomputed from the module,
	-- because recomputing it here would grade the generator against itself.
	eq(n.parts, 114, "a fresh miner's shaft holds exactly 114 BaseParts")
	eq(n.rock + n.ore, 49, "the whole 7x7 floor of the mouth is exposed")
	eq(n.bedrock, 64, "…ringed by bedrock at layer 0 and layer 1")
	eq(n.pads, 1, "…with one SELL pad")
	-- Only what you can swing at gets a detector: 49 floor cells + the pad. 32 more per bedrock
	-- ring layer would buy nothing.
	eq(n.clicks, 50, "every minable face is clickable and the ring is not")
end

do
	-- Every block has to say which cell it is and who owns it, or the server cannot route a click
	-- and two players in one server would mine each other's shafts.
	local untagged, unowned = 0, 0
	for _, d in shaft0:GetDescendants() do
		if d:IsA("BasePart") and not string.match(tostring(d.Name), "^SellPad_") then
			if d:GetAttribute("CellKey") == nil then untagged += 1 end
			if d:GetAttribute("Owner") ~= ME then unowned += 1 end
		end
	end
	eq(untagged, 0, "every block carries its cell key")
	eq(unowned, 0, "every block is tagged with its owner")
end

do
	-- The rim. One cell is 6 studs and a Roblox jump clears about 7.2, so a one-cell lip would
	-- let a player hop straight out of the mine and stand on the roof of the world.
	local rim = shaft0:FindFirstChild("Bedrock_" .. ME .. "_1:0:5", true)
	truthy(rim ~= nil, "the mouth has a bedrock rim")
	if rim then
		eq(rim.Size.Y, CELL * RIM_MULT, "the rim is three cells tall — you cannot jump out of the mine")
		eq(rim:FindFirstChildOfClass("ClickDetector"), nil, "and the rim is not something you can swing at")
	end
end

--============================================================ digging actually digs

local function blockAt(uid, k)
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Owner") == uid and d:GetAttribute("CellKey") == k then
			return d
		end
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

do
	local floor = blockAt(ME, "5:1:5")
	truthy(floor ~= nil, "there is a block directly under the spawn to start digging")
	local cd = floor and floor:FindFirstChildOfClass("ClickDetector")
	truthy(cd ~= nil, "…and it carries a ClickDetector, so a click can reach the server")

	if cd then
		local sizeBefore = floor.Size.X
		local partsBefore = partCount()

		-- Swing one: 10 hit points, a rusty pick does 5, so the block survives and shows it.
		cd.MouseClick:Fire(me)
		local afterOne = floor.Size.X
		truthy(afterOne < sizeBefore, "one swing visibly damages the block ("
			.. tostring(sizeBefore) .. " -> " .. tostring(afterOne) .. ")")

		-- …and two more clicks in the SAME instant, which the server's cooldown has to throw
		-- away. A ClickDetector fires as fast as the client sends, so without a server-side rate
		-- limit an autoclicker mines the entire shaft in one frame and the pickaxe tiers, the
		-- ore hardness curve and the depth wall all stop meaning anything. A mutation sweep
		-- removed the cooldown entirely and this whole file stayed green until this assertion
		-- existed.
		cd.MouseClick:Fire(me)
		cd.MouseClick:Fire(me)
		h:advance(0.5)
		eq(floor.Size.X, afterOne, "three clicks in the same instant land exactly ONE swing")
		truthy(floor.Parent ~= nil, "…so an autoclicker cannot break it early")

		-- The next swing, once the cooldown has passed, breaks it — and the faces behind it
		-- appear. THIS is the procedural part: the world is only built where the player has
		-- actually exposed it.
		cd.MouseClick:Fire(me)
		h:advance(0.5)
		eq(floor.Parent, nil, "the swing after the cooldown breaks the block out of the world")
		gt(partCount(), partsBefore, "breaking a block reveals the faces behind it ("
			.. partsBefore .. " -> " .. partCount() .. " parts)")
		truthy(blockAt(ME, "5:2:5") ~= nil or blockAt(ME, "4:1:5") ~= nil,
			"the newly exposed cell is a real Part in the world, not just a table entry")

		local s = stateOf(me)
		truthy(s ~= nil, "the server pushed a state update after the break")
		if s then
			gt(s.depth, 0, "the depth readout moved (" .. tostring(s.depth) .. " studs)")
		end
	end
end

do
	-- Somebody else's shaft is not yours. The server checks `clicker ~= plr`, and this is the
	-- assertion that keeps that check honest.
	local other = h:join("Tourist", STRANGER)
	h:advance(1)
	h.Players:simulateSpawn(other, h.workspace)
	h:advance(1)
	local mine = blockAt(ME, "4:1:5") or blockAt(ME, "6:1:5")
	truthy(mine ~= nil, "there is a block of mine left to try to steal")
	if mine then
		local cd = mine:FindFirstChildOfClass("ClickDetector")
		local sizeBefore = mine.Size.X
		for _ = 1, 6 do
			cd.MouseClick:Fire(other)
			h:advance(0.4)
		end
		eq(mine.Size.X, sizeBefore, "a stranger swinging at my block does not even scratch it")
		truthy(mine.Parent ~= nil, "…and certainly does not break it")
	end
	h:leave(other)
	h:advance(1)
end

--============================================================ ore, backpack, sale

do
	-- Find one of the eight copper blocks on my floor and mine it out. This is the only path in
	-- the game that puts anything in the backpack, so if it does not work there is no economy.
	local oreBlock = nil
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Owner") == ME and (d:GetAttribute("Ore") or 0) > 0 then
			oreBlock = d
			break
		end
	end
	truthy(oreBlock ~= nil, "there is ore exposed in the mouth of a new shaft")

	if oreBlock then
		local cd = oreBlock:FindFirstChildOfClass("ClickDetector")
		local carriedBefore = (stateOf(me) or {}).carried or 0
		for _ = 1, 20 do
			if oreBlock.Parent == nil then break end
			cd.MouseClick:Fire(me)
			h:advance(0.4)
		end
		eq(oreBlock.Parent, nil, "the ore block is mined out")
		local s = stateOf(me)
		gt(s.carried, carriedBefore, "the ore went into the backpack (" .. tostring(s.carried) .. " units)")
		gt(s.haulValue, 0, "and the haul is worth something (" .. tostring(s.haulValue) .. ")")
		eq(s.cash, 0, "but it is not money until it is sold")
	end
end

do
	-- The SELL pad. A pad you cannot click is a haul you can never spend.
	local pad = shaft0:FindFirstChild("SellPad_" .. ME, true)
	truthy(pad ~= nil, "the sell pad is in the world")
	local cd = pad and pad:FindFirstChildOfClass("ClickDetector")
	truthy(cd ~= nil, "…and it is clickable")

	local ls = me:FindFirstChild("leaderstats")
	local cashValue = ls and ls:FindFirstChild("Cash")
	truthy(cashValue ~= nil, "the player has a Cash readout to check against")

	if cd and cashValue then
		local before = cashValue.Value
		cd.MouseClick:Fire(me)
		h:advance(1)
		gt(cashValue.Value, before, "selling paid out (" .. before .. " -> " .. cashValue.Value .. ")")
		local s = stateOf(me)
		eq(s.carried, 0, "and emptied the backpack")
		eq(s.haulValue, 0, "…so there is nothing left to sell")
	end
end

do
	-- Buying an upgrade with no money must be refused, and must SAY so. A silent return here is
	-- the exact defect that produced "i cant even place a seed" in the sibling game.
	local s = stateOf(me)
	local cashNow = s.cash
	BuyEvent:simulateFireServer(me, "pickaxe")
	h:advance(0.5)
	eq(stateOf(me).pickTier, 1, "a pickaxe you cannot afford is not granted")
	eq(stateOf(me).cash, cashNow, "…and costs nothing")
	truthy(string.find(lastToast(), "Not enough") ~= nil,
		"…and the player is told why, rather than nothing happening (" .. lastToast() .. ")")
end

--============================================================ the elevator

do
	local hrp = me.Character:FindFirstChild("HumanoidRootPart")
	truthy(hrp ~= nil, "the miner has a root part to move")

	-- Down first: the elevator has to land you at the bottom of your own dig, not at the top.
	ElevatorEvent:simulateFireServer(me, "down")
	h:advance(0.5)
	local downY = hrp.CFrame.Position.Y
	truthy(downY < 0, "DESCEND puts you below the surface (y = " .. tostring(downY) .. ")")

	ElevatorEvent:simulateFireServer(me, "up")
	h:advance(0.5)
	local upY = hrp.CFrame.Position.Y
	gt(upY, downY, "SURFACE brings you back up (" .. tostring(downY) .. " -> " .. tostring(upY) .. ")")
	truthy(math.abs(upY - 4) < 0.01, "…to exactly the spawn height, standing on the mouth floor")
end

--============================================================ the veteran: column, wall, rebirth

local loaded = h:join("Veteran", LOADED)
h:advance(1)
h.Players:simulateSpawn(loaded, h.workspace)
h:advance(6) -- the restore of a 24-layer elevator column yields every 40 parts

local shaft1 = shafts:FindFirstChild("Shaft_1")
truthy(shaft1 ~= nil, "the second player got their own shaft folder")

do
	local s = stateOf(loaded)
	truthy(s ~= nil, "the veteran got a state push")
	eq(s.cash, 40000, "their saved cash came back")
	eq(s.pickTier, 2, "…and their pickaxe")
	-- The integer-key trap, and it is subtler than it looks. `inventory` went through the
	-- emulator's real JSON round-trip on write, so it came back with STRING keys. Counting the
	-- UNITS does not catch that — Economy.carried sums the values over pairs() and does not care
	-- what the keys are, so a sweep that deleted numKeys left this figure at a perfect 12. What
	-- breaks is every lookup BY tier: Ore.value(cfg, "2") is nil, so 12 iron silently becomes
	-- worth nothing and the HUD's per-ore rows all read zero. So price the haul, do not count it.
	eq(s.carried, 12, "…and their backpack survived the DataStore's JSON round-trip")
	eq(s.haulValue, 240, "…and it is still worth 12 iron at 20 each, not zero (numKeys held)")
	eq(s.depth, 144, "…and their 24 layers of depth (144 studs)")
	eq(s.maxDepth, 144, "the depth wall at rebirth 0 is 144 studs down")

	-- The elevator shaft is REBUILT, not just remembered as a number.
	truthy(blockAt(LOADED, "5:25:5") ~= nil or blockAt(LOADED, "4:24:5") ~= nil,
		"the restored column actually put blocks at the bottom of the shaft")
	local n = scan(shaft1)
	gt(n.parts, 200, "restoring 24 layers built a real shaft (" .. n.parts .. " parts)")
end

do
	-- A full backpack must refuse the swing BEFORE the block is ground down, and say so.
	local oreBlock = nil
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Owner") == LOADED and (d:GetAttribute("Ore") or 0) > 0 then
			oreBlock = d
			break
		end
	end
	truthy(oreBlock ~= nil, "the veteran has ore in reach")
	if oreBlock then
		local cd = oreBlock:FindFirstChildOfClass("ClickDetector")
		local sizeBefore = oreBlock.Size.X
		cd.MouseClick:Fire(loaded)
		h:advance(0.5)
		eq(oreBlock.Size.X, sizeBefore, "a full backpack refuses the swing instead of wasting the vein")
		truthy(string.find(lastToast(), "full") ~= nil,
			"…and says so (" .. lastToast() .. ")")
	end
end

do
	-- The depth wall explains itself. Bedrock below the wall is clickable ON PURPOSE: a rock
	-- that silently ignores you is indistinguishable from a broken game.
	local floorBlock = blockAt(LOADED, "5:25:5")
	if floorBlock == nil then
		-- The column stops at the wall; the cell directly under it is the floor. Look for any
		-- bedrock the restore exposed at layer 25.
		for _, d in h.workspace:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Owner") == LOADED
				and d:GetAttribute("Layer") == 25 then floorBlock = d end
		end
	end
	truthy(floorBlock ~= nil, "the bedrock floor of the world is built")
	if floorBlock then
		local cd = floorBlock:FindFirstChildOfClass("ClickDetector")
		truthy(cd ~= nil, "the depth wall is clickable so it can explain itself")
		if cd then
			for _ = 1, 5 do
				cd.MouseClick:Fire(loaded)
				h:advance(0.4)
			end
			truthy(floorBlock.Parent ~= nil, "bedrock never breaks, however long you hit it")
			truthy(string.find(lastToast(), "Bedrock") ~= nil,
				"…and it tells you to rebirth (" .. lastToast() .. ")")
		end
	end
end

do
	-- REBIRTH: the payoff, and the only irreversible button in the game.
	local oresBefore = {}
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Owner") == LOADED and (d:GetAttribute("Ore") or 0) > 0 then
			oresBefore[tostring(d:GetAttribute("CellKey"))] = d:GetAttribute("Ore")
		end
	end

	RebirthEvent:simulateFireServer(loaded)
	h:advance(2)

	local s = stateOf(loaded)
	eq(s.rebirths, 1, "the rebirth went through")
	eq(s.cash, 0, "cash is wiped")
	eq(s.pickTier, 1, "the pickaxe goes back to rusty")
	eq(s.carried, 0, "the haul is wiped")
	eq(s.depth, 0, "this run's depth is wiped")
	eq(s.maxDepth, 216, "and the depth wall moved 12 layers deeper, to 216 studs")
	truthy(math.abs(s.mult - 1.8) < 1e-6, "the permanent multiplier is live (x" .. tostring(s.mult) .. ")")

	-- A NEW cave, not the old one with the numbers reset. This is the line in the paste-ready
	-- description that a lazier implementation would leave as a lie.
	local newShaft = shafts:FindFirstChild("Shaft_1")
	truthy(newShaft ~= nil, "the veteran still has a shaft after rebirth")
	local n = scan(newShaft)
	eq(n.parts, 114, "…and it is a fresh 114-part shaft, rebuilt from scratch")

	local moved = 0
	local seen = 0
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Owner") == LOADED and (d:GetAttribute("Ore") or 0) > 0 then
			seen += 1
			if oresBefore[tostring(d:GetAttribute("CellKey"))] ~= d:GetAttribute("Ore") then moved += 1 end
		end
	end
	gt(seen, 0, "the new cave has ore of its own")
	gt(moved, 0, "the veins MOVED — rebirth really did regenerate the cave, not just reset the numbers")
end

--============================================================ leaving takes the whole shaft

do
	local before = #shafts:GetChildren()
	local ghost = h:join("Passerby", GHOST)
	h:advance(1)
	eq(#shafts:GetChildren(), before + 1, "a third player got their own shaft folder")

	local ghostShaft = nil
	for _, f in shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. GHOST, true) ~= nil then ghostShaft = f.Name end
	end
	truthy(ghostShaft ~= nil, "the third player's shaft is identifiable by their sell pad")

	h:leave(ghost)
	h:advance(1)
	eq(#shafts:GetChildren(), before, "leaving destroyed the WHOLE shaft, not just the blocks")
	eq(blockAt(GHOST, "5:1:5"), nil, "…and none of their blocks are left behind in the workspace")

	-- A freed index has to come back, or a server slowly walks its shafts out along +X until they
	-- are kilometres apart. The count above is satisfied perfectly well by a leaked index, so the
	-- index is checked by name.
	local reuser = h:join("Reuser", REUSER)
	h:advance(1)
	local reuserShaft = nil
	for _, f in shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. REUSER, true) ~= nil then reuserShaft = f.Name end
	end
	eq(reuserShaft, ghostShaft, "the next player REUSES the freed shaft index instead of taking a new one")
	h:leave(reuser)
	h:advance(1)
	eq(#shafts:GetChildren(), before, "and that shaft goes away too")
end

--============================================================ the HUD loads and its buttons work

do
	h.Players.LocalPlayer = me
	local ok, err = h:tryRun("client/Hud.client")
	truthy(ok, "the HUD loads against the real remotes" .. (ok and "" or (": " .. tostring(err))))
	h:advance(1)

	local pg = me:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("DeepVeinHud")
	truthy(hud ~= nil, "the HUD is parented into the PlayerGui")

	if hud then
		local root = hud:FindFirstChild("Root")
		truthy(root ~= nil, "the HUD has a root frame")
		-- A UIScale parented to a ScreenGui does nothing; it has to be on the root frame.
		truthy(root and root:FindFirstChildOfClass("UIScale") ~= nil,
			"the UIScale is on the root frame, not on the ScreenGui")

		local elevator = root and root:FindFirstChild("Elevator")
		truthy(elevator ~= nil, "the elevator controls exist")
		local buttons = {}
		if elevator then
			for _, c in elevator:GetChildren() do
				if c.ClassName == "TextButton" then table.insert(buttons, c) end
			end
		end
		eq(#buttons, 2, "there are exactly two elevator buttons")

		-- Press SURFACE for real and check it reaches the server. A button wired to nothing looks
		-- identical to a working one in every screenshot.
		if #buttons == 2 then
			local hrp = me.Character:FindFirstChild("HumanoidRootPart")
			ElevatorEvent:simulateFireServer(me, "down")
			h:advance(0.5)
			local low = hrp.CFrame.Position.Y
			buttons[1].Activated:Fire()
			h:advance(0.5)
			gt(hrp.CFrame.Position.Y, low, "pressing SURFACE in the HUD actually moved the miner")
		end
	end
end

--============================================================================ done

print("")
eq(#h.warnings, 0, "the server built every shaft without warnings")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein check failed", 0)
end
