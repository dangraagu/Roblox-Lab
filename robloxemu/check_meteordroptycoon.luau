-- Meteor Drop Tycoon — THE REAL PLAYER PATH, through the real server, headless.
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon.luau 2>&1
-- ALWAYS rebuild the bundle first: this file reads build/meteor-drop-tycoon.luau, not src/.
--
-- Why this exists: this repo once shipped 166 green unit tests with an unreachable core loop (a Part
-- that was built, sized and wired and never parented). Nothing here trusts a unit test. It asks the
-- workspace, spawns characters the way the ENGINE does (robloxemu/SPAWN-ORDER.md: CharacterAdded
-- first, placement one frame later on a SpawnLocation), walks a character onto meteors at WalkSpeed,
-- and reads back only what a client could see (the workspace, the State / Toast remotes, leaderstats)
-- plus the ServerStorage.PlotInfo debug folder.
--
-- Counts and positions are written out by hand from DESIGN.md, never recomputed with the game's modules.

local Harness = require("./emu/harness")

local h = Harness.new({ bundle = require("./build/meteor-drop-tycoon"), name = "meteor-drop-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end

local A, B, FULL, PATIENT, NEWBIE = 5150, 6161, 7272, 7373, 7474
local store = h.services.DataStoreService:GetDataStore("MeteorDropTycoon_v1")
-- a returning player whose hopper is already over its cap (s0 holds 12 ore): the refusal path
store:SetAsync("u_" .. FULL, { data = { v = 1, stardust = 3, lifetime = 3, beacon = 4, beaconAt = 1790000000,
	collector = 0, smelter = 0, hopper = 40, star = 0, starCores = 0, tutorial = 2 } })
-- REVIEW-1: a full hopper while the star is NOT on the Smelter (a big Smelter on a Beacon-0 plot, overfilled:
-- cap 141.7 at s10, melting 7.1 ore/s, so it stays full for about 36 s)
store:SetAsync("u_" .. PATIENT, { data = { v = 1, stardust = 0, lifetime = 3, beacon = 0, beaconAt = 1790000000,
	collector = 0, smelter = 10, hopper = 400, star = 0, starCores = 0, tutorial = 2 } })
-- REVIEW-1: a new player before their first purchase, whose hopper a rare filled (30 of 12: full for 30 s)
store:SetAsync("u_" .. NEWBIE, { data = { v = 1, stardust = 13, lifetime = 13, beacon = 0, beaconAt = 0,
	collector = 0, smelter = 0, hopper = 30, star = 0, starCores = 0, tutorial = 1 } })

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server script loads (" .. tostring(errServer) .. ")")
if not okServer then
	print(string.format("meteordroptycoon: %d passed, %d failed", passed, failed))
	error("meteordroptycoon check failed", 0)
end
h:advance(1)

local RS = h.ReplicatedStorage
local SS = h.game:GetService("ServerStorage")

--============================================================================ 1. the world is BUILT and PARENTED
local plots = h.workspace:FindFirstChild("Plots")
truthy(plots ~= nil and plots.Parent == h.workspace, "workspace.Plots exists and is parented")
local RING, TOP = 110, 1 -- plot ring radius; the arrival pad's top face
local function padOf(k)
	local plot = plots and plots:FindFirstChild("Plot_" .. k)
	return plot and plot:FindFirstChild("Arrival")
end
do
	local spawns = 0
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" then spawns += 1 end
	end
	eq(spawns, 8, "exactly 8 SpawnLocations in the world: one per plot, none anywhere else")
	for k = 1, 8 do
		local plot = plots:FindFirstChild("Plot_" .. k)
		truthy(plot ~= nil and plot.Parent == plots, "Plot_" .. k .. " is built and parented")
		local pad = padOf(k)
		truthy(pad ~= nil and pad.ClassName == "SpawnLocation", "Plot_" .. k .. " has its Arrival SpawnLocation")
		if pad then
			eq(pad.Enabled, true, "Plot_" .. k .. "'s arrival is enabled")
			eq(pad.Duration, 0, "...with no force-field bubble")
			eq(pad.Anchored, true, "...anchored")
			near(pad.Position.Y + pad.Size.Y / 2, TOP, 1e-6, "...with its top at y = 1")
			-- 110 - 30 = 80 studs from the observatory, on the observatory side of the plot
			local r = math.sqrt(pad.Position.X ^ 2 + pad.Position.Z ^ 2)
			near(r, 80, 1e-6, "Plot_" .. k .. "'s arrival is 80 studs from the observatory")
			local meteors = plot:FindFirstChild("Meteors")
			truthy(meteors ~= nil, "Plot_" .. k .. " has a Meteors folder")
			local smelter = plot:FindFirstChild("Smelter")
			truthy(smelter ~= nil and #smelter:GetChildren() >= 7, "Plot_" .. k .. " has a built Smelter")
			local board = plot:FindFirstChild("Board")
			local face = board and board:FindFirstChild("BoardFace")
			local prompt = face and face:FindFirstChildOfClass("ProximityPrompt")
			truthy(prompt ~= nil and prompt.Enabled, "Plot_" .. k .. "'s Star Chart has an enabled ProximityPrompt")
			if prompt and face then
				-- reachable: a player standing 4 studs in front of the board, toward the plot centre, is on
				-- the plot disc and inside the prompt's range
				local cx, cz = math.sin((k - 1) * math.pi / 4) * RING, math.cos((k - 1) * math.pi / 4) * RING
				local fp = face.Position
				local dx, dz = cx - fp.X, cz - fp.Z
				local dl = math.sqrt(dx * dx + dz * dz)
				local stand = Vector3.new(fp.X + dx / dl * 4, 3, fp.Z + dz / dl * 4)
				local onDisc = math.sqrt((stand.X - cx) ^ 2 + (stand.Z - cz) ^ 2) <= 36
				truthy(onDisc, "Plot_" .. k .. ": the ground in front of the board is the plot's own disc")
				truthy((stand - fp).Magnitude <= prompt.MaxActivationDistance,
					string.format("Plot_%d: the prompt reaches a player standing there (%.1f <= %d)", k, (stand - fp).Magnitude, prompt.MaxActivationDistance))
				local fromPad = (Vector3.new(fp.X, 0, fp.Z) - Vector3.new(pad.Position.X, 0, pad.Position.Z)).Magnitude
				near(fromPad, 14.04, 0.05, "Plot_" .. k .. ": the board stands 14 studs from the arrival, as DESIGN 9.4 says")
			end
		end
	end
	truthy(h.workspace:FindFirstChild("Baseplate") ~= nil, "the continuous ground plate exists")
end

--============================================================================ 2. budgets and the wire inventory
local function countServer()
	local parts, lights = 0, 0
	for _, d in h.workspace:GetDescendants() do
		local inChar = false
		local a = d.Parent
		while a ~= nil do
			if a:FindFirstChildOfClass("Humanoid") then inChar = true break end
			a = a.Parent
		end
		if not inChar then
			if d:IsA("BasePart") then parts += 1 end
			if d.ClassName == "PointLight" or d.ClassName == "SpotLight" or d.ClassName == "SurfaceLight" then lights += 1 end
		end
	end
	return parts, lights
end
do
	local parts, lights = countServer()
	print(string.format("  idle world: %d server parts, %d lights", parts, lights))
	truthy(parts <= 450, "the idle world is within the 450-part server budget (" .. parts .. ")")
	truthy(lights <= 16, "and the 16-light budget (" .. lights .. ")")
end
local function attributeInventory()
	local found = {}
	for _, root in { h.workspace, RS } do
		for _, d in root:GetDescendants() do
			for name in d:GetAttributes() do
				table.insert(found, d.Name .. "." .. name)
			end
		end
	end
	return found
end
local function isReddish(c)
	return c.R * 255 >= 180 and c.G * 255 <= 110 and c.B * 255 <= 110
end
local function redParts()
	local bad = {}
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Color and isReddish(d.Color) and d.Parent and not d.Parent:FindFirstChildOfClass("Humanoid") then
			table.insert(bad, d:GetFullName())
		end
	end
	return bad
end
eq(#attributeInventory(), 0, "no attribute on any Instance under workspace or ReplicatedStorage (the empty wire inventory)")
eq(#redParts(), 0, "no server part is red: red is the hazard ring's alone")

--============================================================================ 3. join and LAND, under the engine's spawn order
local remotes = RS:FindFirstChild("MeteorRemotes")
truthy(remotes ~= nil, "ReplicatedStorage.MeteorRemotes exists")
local State, Toast, Buy = remotes:FindFirstChild("State"), remotes:FindFirstChild("Toast"), remotes:FindFirstChild("Buy")
truthy(State ~= nil and Toast ~= nil and Buy ~= nil, "the State, Toast and Buy remotes exist")
local function stateOf(plr)
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function toastsOf(plr)
	local out = {}
	for _, rec in Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function lastToast(plr)
	local t = toastsOf(plr)
	return t[#t] or ""
end

local pa = h:join("Nova", A)
-- BEFORE any yield: the plot is claimed and the engine told where to put the character
local padA = pa.RespawnLocation
truthy(padA ~= nil and padA.ClassName == "SpawnLocation" and padA.Name == "Arrival",
	"PlayerAdded points RespawnLocation at the player's own arrival pad synchronously, before any yield")
local plotA = padA and padA.Parent
local ca = h.Players:simulateSpawn(pa, h.workspace)
h:advance(0.2)
local hrpA = ca:FindFirstChild("HumanoidRootPart")
local function flat(p, q) return math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2) end
truthy(flat(hrpA.Position, padA.Position) <= 4, string.format("the joining character LANDS on its own pad (%.2f studs)", flat(hrpA.Position, padA.Position)))
truthy(hrpA.Position.Y > TOP, "above the pad, not in it")

local pb = h:join("Orion", B)
local cb = h.Players:simulateSpawn(pb, h.workspace)
h:advance(0.2)
local padB = pb.RespawnLocation
truthy(padB ~= nil and padB ~= padA, "a second player gets a different plot")
local hrpB = cb:FindFirstChild("HumanoidRootPart")
truthy(flat(hrpB.Position, padB.Position) <= 4, "the second character lands on ITS OWN pad")
truthy(flat(hrpB.Position, padA.Position) > 20, "and not on the first player's")

-- respawn: the same
do
	local c2 = h.Players:simulateSpawn(pb, h.workspace)
	h:advance(0.2)
	truthy(flat(c2:FindFirstChild("HumanoidRootPart").Position, padB.Position) <= 4, "a respawn lands on the player's own pad again")
	cb = c2
	hrpB = c2:FindFirstChild("HumanoidRootPart")
end
-- belt and braces: with RespawnLocation cleared the engine picks the first enabled spawn in the tree (Plot_1's
-- pad); the CharacterAdded handler must still put the player on their OWN pad
do
	pb.RespawnLocation = nil
	local c3 = h.Players:simulateSpawn(pb, h.workspace)
	h:advance(0.5)
	local p = c3:FindFirstChild("HumanoidRootPart").Position
	truthy(flat(p, padB.Position) <= 4, string.format("with RespawnLocation cleared, the handler still moves the character to its own pad (%.1f studs)", flat(p, padB.Position)))
	cb = c3
	hrpB = c3:FindFirstChild("HumanoidRootPart")
end

--============================================================================ 4. the first meteor, the first pickup
local metA = plotA:FindFirstChild("Meteors")
local function meteorParts(folder, prefix)
	local out = {}
	for _, c in folder:GetChildren() do
		if string.sub(c.Name, 1, #prefix) == prefix then table.insert(out, c) end
	end
	return out
end
-- the check re-spawned A? No: A spawned once, 0.2 + 0.2 + 0.2 + 0.5 s ago. The first meteor is announced
-- 0.5 s after placement and lands 1.5 s later, 10 studs in front of the pad.
local announcedAt, landedAt, firstPart = nil, nil, nil
local t0 = h.scheduler:now()
for i = 1, 40 do
	local inc = meteorParts(metA, "Incoming_")
	local landed = meteorParts(metA, "Meteor_")
	if announcedAt == nil and (#inc > 0 or #landed > 0) then announcedAt = h.scheduler:now() - t0; firstPart = inc[1] or landed[1] end
	if landedAt == nil and #landed > 0 then landedAt = h.scheduler:now() - t0; firstPart = landed[1]; break end
	h:advance(0.1)
end
truthy(firstPart ~= nil, "the first meteor is announced on the player's own plot")
truthy(landedAt ~= nil, "and it lands")
if firstPart then
	local d = flat(firstPart.Position, padA.Position)
	near(d, 10, 0.01, "it lands 10 studs in front of the arrival pad (plot-local (0, -20))")
	eq(firstPart.Name, "Meteor_Common", "a common pebble")
end
print(string.format("  first meteor: seen %.1f s after the checks began, landed %.1f s", announcedAt or -1, landedAt or -1))

-- walk onto it at WalkSpeed, the way a player would
local function walkTo(hrp, target, speed)
	speed = speed or 16
	for _ = 1, 400 do
		local p = hrp.Position
		local dx, dz = target.X - p.X, target.Z - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 1 then return true end
		local step = math.min(d, speed * 0.1)
		hrp.CFrame = CFrame.new(p.X + dx / d * step, p.Y, p.Z + dz / d * step)
		h:advance(0.1)
		if firstPart and firstPart.Parent == nil then return true end
	end
	return false
end
local before = stateOf(pa)
truthy(before ~= nil, "the owner receives State")
local hopper0 = before and before.hopper or -1
walkTo(hrpA, firstPart.Position)
h:advance(0.2)
truthy(firstPart.Parent == nil, "walking over the landed meteor collects it: the part is gone")
local after = stateOf(pa)
truthy(after and after.hopper > hopper0, string.format("the hopper rises (%.2f -> %.2f)", hopper0, after and after.hopper or -1))
h:advance(2)
local melted = stateOf(pa)
truthy(melted and melted.stardust > 0, string.format("and the Smelter melts it into Stardust (%.2f)", melted and melted.stardust or -1))
eq(melted and melted.tutorial, 1, "the first pickup moves the hint on (tutorial 0 -> 1)")

--============================================================================ 5. play like the HUD says: walk, buy the star
-- A normal player: walk to the nearest landed meteor on your own plot, buy whatever the star points at.
local bought = { beacon = 0, collector = 0, smelter = 0 }
local firstBuyAt = {}
local tStart = h.scheduler:now()
local function play(plr, hrp, plot, seconds, opts)
	opts = opts or {}
	local folder = plot:FindFirstChild("Meteors")
	local target = nil
	local tEnd = h.scheduler:now() + seconds
	while h.scheduler:now() < tEnd do
		local st = stateOf(plr)
		if st and st.loaded and not opts.noBuy then
			local price = st.prices[st.best]
			if price and st.stardust >= price and (opts.only == nil or opts.only == st.best) then
				Buy:simulateFireServer(plr, st.best)
				bought[st.best] += 1
				firstBuyAt[st.best] = firstBuyAt[st.best] or (h.scheduler:now() - tStart)
			end
		end
		if target == nil or target.Parent == nil then
			target = nil
			local best, bd = nil, math.huge
			for _, m in folder:GetChildren() do
				if string.sub(m.Name, 1, 6) == "Meteor" or m.Name == "FallingStar" then
					local d = flat(m.Position, hrp.Position)
					local pri = if m.Name == "FallingStar" then -1000 else 0
					if d + pri < bd then best, bd = m, d + pri end
				end
			end
			target = best
		end
		if target then
			local p = hrp.Position
			local dx, dz = target.Position.X - p.X, target.Position.Z - p.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0.5 then
				local step = math.min(d, 16 * 0.1)
				hrp.CFrame = CFrame.new(p.X + dx / d * step, p.Y, p.Z + dz / d * step)
			end
		end
		h:advance(0.1)
		if opts.untilFn and opts.untilFn() then return true end
	end
	return false
end

local stBefore = stateOf(pa)
local leader = pa:FindFirstChild("leaderstats")
truthy(leader ~= nil and leader:FindFirstChild("Beacon") ~= nil, "leaderstats.Beacon exists")
local beam = plotA:FindFirstChild("Beacon") and plotA.Beacon:FindFirstChild("BeaconBeam")
local beamH0 = beam and beam.Size.X or -1 -- a Cylinder's length is its X
play(pa, hrpA, plotA, 120, { untilFn = function()
	local st = stateOf(pa)
	return st and st.beacon >= 1
end })
local st1 = stateOf(pa)
eq(st1 and st1.beacon, 1, "Buy('beacon') moves the level")
eq(leader.Beacon.Value, 1, "leaderstats shows it")
truthy(beam and beam.Size.X > beamH0, "and the tower's beam grows")
print(string.format("  first Beacon bought %.1f s into play", firstBuyAt.beacon or -1))
truthy((firstBuyAt.beacon or 999) <= 60, "the first purchase comes inside the first minute (DESIGN 14: ~40 s)")

-- keep playing until the Collector is the star and bought, then watch a dish catch
local dishCaught = false
play(pa, hrpA, plotA, 20 * 60, { untilFn = function()
	return bought.collector >= 1
end })
eq(bought.collector >= 1, true, "the star eventually points at the Collector and it is bought")
print(string.format("  first Smelter %.2f min, first Collector %.2f min into play", (firstBuyAt.smelter or -60) / 60, (firstBuyAt.collector or -60) / 60))
local dish = plotA:FindFirstChild("Dish") and plotA.Dish:FindFirstChild("DishRim")
truthy(dish and dish.Transparency < 1, "the dish is visible once bought")
do
	local info = SS:FindFirstChild("PlotInfo") and SS.PlotInfo:FindFirstChild(tostring(A))
	truthy(info ~= nil, "ServerStorage.PlotInfo.<userId> holds the debug values (never replicated)")
	-- the owner's Fx remote says "dish" when a meteor lands in the dish (the client draws the catch)
	local FxR = remotes:FindFirstChild("Fx")
	local function dishEvents()
		local n = 0
		for _, rec in FxR:sentTo(pa) do
			local ev = rec.args[1]
			if type(ev) == "table" and ev.kind == "dish" then n += 1 end
		end
		return n
	end
	local caught0 = dishEvents()
	local hopper0d = stateOf(pa).hopper
	-- stand still by the pad: the dish keeps catching. A level-1 dish covers 3.75% of landings, about one catch a
	-- minute at this Beacon, so wait up to 5 minutes (a miss is then e^-5 = 0.7% likely, not a coin flip)
	hrpA.CFrame = CFrame.new(padA.Position + Vector3.new(0, 3.5, 0))
	local waited = 0
	for _ = 1, 3000 do
		h:advance(0.1)
		waited += 0.1
		if dishEvents() > caught0 then dishCaught = true break end
	end
	print(string.format("  first dish catch %.1f s after standing still", waited))
	truthy(dishCaught, "a meteor that lands inside the dish is caught with no walking")
end

--============================================================================ 6. a full hopper refuses, and says so
local pf = h:join("Hoarder", FULL)
local cf = h.Players:simulateSpawn(pf, h.workspace)
h:advance(0.3)
local hrpF = cf:FindFirstChild("HumanoidRootPart")
local plotF = pf.RespawnLocation.Parent
do
	local st = stateOf(pf)
	truthy(st and st.hopperFull, "the returning player's saved hopper (40 of 12) loads full")
	-- walk to the first landed meteor and stand on it
	local refused = false
	local met = plotF:FindFirstChild("Meteors")
	for _ = 1, 100 do
		local m = meteorParts(met, "Meteor_")[1]
		if m then
			hrpF.CFrame = CFrame.new(m.Position.X, 3.5, m.Position.Z)
			h:advance(0.3)
			if m.Parent ~= nil and string.find(lastToast(pf), "Hopper full", 1, true) then refused = true break end
		end
		h:advance(0.1)
	end
	truthy(refused, "a pickup into a full hopper is refused, the meteor stays, and a toast says why: " .. lastToast(pf))
	-- REVIEW-1: the refusal follows the HUD's star; it used to say "Upgrade the Smelter" whatever the star said
	eq(stateOf(pf).best, "smelter", "set-up: a starved Smelter: the star is on it")
	truthy(string.find(lastToast(pf), "Smelter", 1, true) ~= nil, "starred: the refusal sends you to the Smelter: " .. lastToast(pf))
end
do
	local pp = h:join("Patient", PATIENT)
	local cp = h.Players:simulateSpawn(pp, h.workspace)
	h:advance(0.3)
	local hrpP = cp:FindFirstChild("HumanoidRootPart")
	local metP = pp.RespawnLocation.Parent:FindFirstChild("Meteors")
	local st = stateOf(pp)
	truthy(st and st.hopperFull, "set-up: the second hopper loads full too")
	truthy(st and st.best ~= "smelter", "set-up: but its star is on the " .. tostring(st and st.best) .. ", not the Smelter")
	local refusal = nil
	for _ = 1, 100 do
		local m = meteorParts(metP, "Meteor_")[1]
		if m then
			hrpP.CFrame = CFrame.new(m.Position.X, 3.5, m.Position.Z)
			h:advance(0.3)
			if m.Parent ~= nil and string.find(lastToast(pp), "Hopper full", 1, true) then refusal = lastToast(pp) break end
		end
		h:advance(0.1)
	end
	truthy(refusal ~= nil, "set-up: refused while full")
	eq(refusal and string.find(refusal, "Smelter", 1, true), nil,
		"star elsewhere: the refusal does not send you to the Smelter (REVIEW-1): " .. tostring(refusal))
	truthy(refusal ~= nil and string.find(refusal, "takes meteors again in %d+ s") ~= nil, "it says when the hopper takes meteors again: " .. tostring(refusal))
	h:leave(pp)
	h:advance(1)
end

do
	-- REVIEW-1: the star listens to the hopper only after the first purchase. Before it, the first-minutes hint
	-- says "buy the ★ upgrade" and that is the Beacon (DESIGN [M8]); one rare fills a fresh 12-ore hopper, and the
	-- 40-walk sweep saw the star sit on the Smelter (20) instead, pushing the first purchase from 40 s to 81 s.
	local pn = h:join("Newbie", NEWBIE)
	h.Players:simulateSpawn(pn, h.workspace)
	h:advance(10)
	local st = stateOf(pn)
	truthy(st and st.hopperFull, "set-up: the newcomer's hopper has been full for 10 s")
	eq(st and st.best, "beacon", "before the first purchase the star stays on the Beacon, however full the hopper")
	Buy:simulateFireServer(pn, "beacon")
	h:advance(10)
	st = stateOf(pn)
	truthy(st and st.hopperFull and st.tutorial >= 2, "set-up: one purchase made, the hopper still full")
	eq(st and st.best, "smelter", "after it, a hopper that keeps filling up puts the star on the Smelter")
	h:leave(pn)
	h:advance(1)
end

--============================================================================ 7. a visitor cannot collect on someone else's plot
do
	local m = nil
	for _ = 1, 60 do
		m = meteorParts(metA, "Meteor_")[1]
		if m then break end
		h:advance(0.2)
	end
	truthy(m ~= nil, "set-up: a meteor lies on Nova's plot")
	if m then
		local n0 = #toastsOf(pb)
		hrpB.CFrame = CFrame.new(m.Position.X, 3.5, m.Position.Z)
		h:advance(1)
		truthy(m.Parent ~= nil, "Orion standing on Nova's meteor does not collect it")
		truthy(#toastsOf(pb) > n0 and string.find(lastToast(pb), "Only Nova can collect here", 1, true) ~= nil,
			"and is told why: " .. lastToast(pb))
		hrpB.CFrame = CFrame.new(padB.Position + Vector3.new(0, 3.5, 0))
	end
end

--============================================================================ 7b. a teleport buys nothing: pickups use the TRUSTED position
-- The client owns its character's physics, so the root's position is a claim. The server moves its own copy
-- toward it at 21.6 studs/s with a 3 s banked burst (vault-runners' Trace). Drain the burst by teleporting
-- back and forth by the pad, then teleport onto a meteor on the far side of the plot: it must not be collected
-- that tick, and must be collected only once a walk at the trusted speed could have got there.
do
	local plotB = padB.Parent
	local metB = plotB:FindFirstChild("Meteors")
	local centreB = plotB.Smelter.SmelterBody.Position
	local side = Vector3.new(padB.Position.X - centreB.X, 0, padB.Position.Z - centreB.Z).Unit
	local lateral = Vector3.new(side.Z, 0, -side.X)
	local pA = Vector3.new(padB.Position.X, 3.5, padB.Position.Z)
	local pB = pA + lateral * 20
	for i = 1, 30 do
		hrpB.CFrame = CFrame.new(if i % 2 == 0 then pA else pB)
		h:advance(0.1)
	end
	local far, fd = nil, 0
	for _, m in metB:GetChildren() do
		if string.sub(m.Name, 1, 7) == "Meteor_" then
			local d = math.min(flat(m.Position, pA), flat(m.Position, pB))
			if d > fd then far, fd = m, d end
		end
	end
	truthy(far ~= nil and fd >= 25, string.format("set-up: a meteor lies on the far side of Orion's plot (%.1f studs from the drained trusted position)", fd))
	if far and fd >= 25 then
		hrpB.CFrame = CFrame.new(far.Position.X, 3.5, far.Position.Z)
		h:advance(0.1)
		truthy(far.Parent ~= nil, "a teleport onto a far meteor does NOT collect it in the next tick")
		-- The trusted position walks there in a straight line and collects what lies on the way; on Orion's
		-- untouched plot that can fill a fresh 12-ore hopper, and then the far meteor is refused until it melts
		-- (REVIEW-1's sweep saw it once in about 36 runs). So wait up to 60 s: "no sooner than a walk" still holds.
		local took = nil
		local full0 = #toastsOf(pb)
		for i = 1, 600 do
			h:advance(0.1)
			if far.Parent == nil then took = 0.1 + i * 0.1 break end
		end
		local refusedOnTheWay = false
		for k = full0 + 1, #toastsOf(pb) do
			if string.find(toastsOf(pb)[k], "Hopper full", 1, true) then refusedOnTheWay = true end
		end
		truthy(took ~= nil, "it is collected once the trusted position walks there"
			.. (if refusedOnTheWay then " (after a full hopper melted)" else ""))
		truthy(took ~= nil and took >= (fd - 5) / 21.6 - 0.15,
			string.format("no sooner than a 21.6 studs/s walk could reach it (%.2f s for %.1f studs; the walk needs %.2f s)",
				took or -1, fd, (fd - 5) / 21.6))
		print(string.format("  teleport onto a meteor %.1f studs away: collected after %.2f s", fd, took or -1))
	end
	hrpB.CFrame = CFrame.new(padB.Position + Vector3.new(0, 3.5, 0))
end

--============================================================================ 8. refusals always speak
do
	local n0 = #toastsOf(pb)
	Buy:simulateFireServer(pb, "teleporter")
	h:advance(0.1)
	truthy(#toastsOf(pb) > n0, "an unknown upgrade is refused with a toast: " .. lastToast(pb))
	local n1 = #toastsOf(pb)
	-- the Collector (60 Stardust), not the Beacon (12): Orion may have melted 12 Stardust by now (7b)
	Buy:simulateFireServer(pb, "collector")
	h:advance(0.1)
	truthy(#toastsOf(pb) > n1 and string.find(lastToast(pb), "Need", 1, true) ~= nil, "an unaffordable one too: " .. lastToast(pb))
	local n2 = #toastsOf(pb)
	for _ = 1, 30 do Buy:simulateFireServer(pb, "beacon") end
	h:advance(0.1)
	local slow = 0
	for _, t in toastsOf(pb) do if string.find(t, "Slow down", 1, true) then slow += 1 end end
	truthy(slow >= 1, "a flood of 30 Buy calls in one frame is cut at 8/s, with a 'Slow down' toast")
	truthy(#toastsOf(pb) - n2 <= 10, string.format("and the flood gets at most 8 refusals + 1 slow-down toast (%d)", #toastsOf(pb) - n2))
end

--============================================================================ 9. budgets and the inventory with a busy world
do
	local parts, lights = countServer()
	print(string.format("  busy world (3 players, meteors lying): %d server parts, %d lights", parts, lights))
	truthy(parts <= 450, "still within the 450-part budget (" .. parts .. ")")
	truthy(lights <= 16, "and 16 lights (" .. lights .. ")")
	eq(#attributeInventory(), 0, "and still no attributes under workspace or ReplicatedStorage")
	eq(#redParts(), 0, "and still nothing red")
	-- every plot, including the ones nobody collects on (Orion stood still; the Hoarder's hopper was full)
	local worstPlot = 0
	for _, pl in plots:GetChildren() do
		local mf = pl:FindFirstChild("Meteors")
		local n = #meteorParts(mf, "Meteor_") + #meteorParts(mf, "Incoming_")
		worstPlot = math.max(worstPlot, #meteorParts(mf, "Meteor_"))
		truthy(n <= 23, pl.Name .. " holds at most 20 lying + falling meteors + the star (" .. n .. ")")
	end
	print(string.format("  the fullest plot holds %d landed meteors (the cap is 20)", worstPlot))
	truthy(worstPlot <= 20, "no plot ever holds more than 20 landed meteors")
end

--============================================================================ 10. rejoin restores every saved field
do
	local st = stateOf(pa)
	local want = { stardust = st.stardust, beacon = st.beacon, collector = st.collector, smelter = st.smelter, tutorial = st.tutorial, star = st.star }
	h:leave(pa)
	h:advance(1)
	truthy(plotA:FindFirstChild("Sign") ~= nil, "the plot stays built when its owner leaves")
	eq(#meteorParts(metA, "Meteor_") + #meteorParts(metA, "Incoming_"), 0, "and its meteors are cleared")
	local saved = store:GetAsync("u_" .. A)
	truthy(saved and saved.data and saved.lockUntil == 0, "leaving writes the profile and RELEASES the lock")
	local pa2 = h:join("Nova", A)
	h.Players:simulateSpawn(pa2, h.workspace)
	h:advance(0.5)
	local st2 = stateOf(pa2)
	truthy(st2 and st2.loaded, "the rejoin loads")
	for field, v in want do
		if field == "stardust" then
			truthy(st2[field] >= v - 1e-6 and st2[field] - v <= math.max(3, v * 0.01),
				string.format("rejoin restores %s (%.2f vs %.2f; the saved hopper melts on for 0.5 s)", field, st2[field], v))
		else
			eq(st2[field], v, "rejoin restores " .. field)
		end
	end
	eq(pa2:FindFirstChild("leaderstats").Beacon.Value, want.beacon, "and leaderstats")
end

--============================================================================ 11. eight plots, and a ninth player
do
	local joined = {}
	for i = 1, 5 do
		local p = h:join("Filler" .. i, 9000 + i)
		table.insert(joined, p)
	end
	h:advance(0.5)
	local owners = {}
	for _, p in h.Players:GetPlayers() do
		local pad = p.RespawnLocation
		if pad then owners[pad] = (owners[pad] or 0) + 1 end
	end
	local plotsUsed, shared = 0, 0
	for _, n in owners do
		plotsUsed += 1
		if n > 1 then shared += 1 end
	end
	eq(plotsUsed, 8, "eight players hold all eight plots")
	eq(shared, 0, "no two players share a plot")
	local ninth = h:join("Ninth", 9999)
	h:advance(0.2)
	truthy(rawget(ninth, "__kicked") ~= nil, "a ninth player is kicked with a reason, never left without a plot")
	eq(ninth.RespawnLocation, nil, "and was never given a pad")
	truthy(string.find(tostring(rawget(ninth, "__kicked")), "8 plots", 1, true) ~= nil, "the reason says why: " .. tostring(rawget(ninth, "__kicked")))
	-- a leaver frees the plot for the next joiner
	h:leave(joined[1])
	h:advance(0.5)
	local tenth = h:join("Tenth", 10000)
	h:advance(0.2)
	truthy(tenth.RespawnLocation ~= nil and rawget(tenth, "__kicked") == nil, "the plot a leaver freed goes to the next joiner")
end

print("")
local stray = {}
for _, w in h.warnings do
	-- the one warning this file provokes on purpose: the ninth player (section 11)
	if not string.find(w, "a ninth player arrived", 1, true) then table.insert(stray, w) end
end
eq(#stray, 0, "the server warned about nothing else (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("meteordroptycoon: %d passed, %d failed", passed, failed))
if failed > 0 then error("meteordroptycoon check failed", 0) end
