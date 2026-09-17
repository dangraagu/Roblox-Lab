-- Steal a Cryptid - the world has to be BUILT, PARENTED and REACHABLE, and the raid rules have to
-- hold against claimed positions, in the real server script.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid.luau 2>&1
--
-- ALWAYS re-run wrap.py first. This file reads build/steal-a-cryptid.luau, not the game's src/.
--
-- WHY THIS FILE EXISTS. Grow a Crystal shipped with a Part that was built, sized, named, given a
-- ClickDetector and never parented: its whole core loop was unreachable and 166 unit tests stayed
-- green. Fork Tower shipped with every player spawning 174 studs from their own tower, because
-- CharacterAdded fires while the character is still UNPARENTED and the engine then places it on
-- the SpawnLocation, discarding the handler's CFrame. Neither is visible to a unit test. Both are
-- visible to a file that asks the WORKSPACE, so that is what this does.
--
-- The game's own modules are required below only to ADDRESS things (which cell a position is in,
-- the camp a server-only seed produces, a route through it). Counts and places are asserted
-- against the built world.

local Harness = require("./emu/harness")
local Datatypes = require("./emu/datatypes")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Rng = require("../steal-a-cryptid/src/shared/Rng")
local Layout = require("../steal-a-cryptid/src/shared/Layout")
local Heist = require("../steal-a-cryptid/src/shared/Heist")
local Economy = require("../steal-a-cryptid/src/shared/Economy")

local h = Harness.new({
	bundle = require("./build/steal-a-cryptid"),
	name = "steal-a-cryptid",
	viewport = { 1280, 720 },
	touch = false,
})

local inst = h.instance
local sched = h.scheduler
local V3, CF = Datatypes.Vector3, Datatypes.CFrame
local ServerStorage = h.game:GetService("ServerStorage")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s (+/- %s)", msg, tostring(a), tostring(b), tostring(tol)))
	end
end
local function le(a, b, msg)
	if type(a) == "number" and a <= b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want <= " .. tostring(b))
	end
end

-- os.time() is the REAL clock here (the emulator advances tick(), not os.time()), which is exactly
-- how the game uses it: persisted timestamps only. Seeded timestamps below are relative to it.
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)

--============================================================ seeded profiles (before the server runs)

local A, B, C, D1, D2, D3, F, E = 5150, 6161, 7272, 8301, 8302, 8303, 9404, 9505

local function cages(fill)
	local out = {}
	for i = 1, 9 do out[i] = { sp = "", jar = 0 } end
	for col, c in fill do out[col] = c end
	return out
end

-- a Rare hunter whose grant will be made to fail
store:SetAsync("u_" .. C, { data = {
	v = 1, essence = 5000, savedAt = NOW, cagesUnlocked = 3, tutorial = 4,
	cages = cages({ [5] = { sp = "jackalope", jar = 0 } }), traps = {},
	heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope" }, stats = { steals = 0, caught = 0, poachersCaught = 0 },
} })
-- offline jars: 100 s ago, ten days ago, and a savedAt from a clock in the future
store:SetAsync("u_" .. D1, { data = { v = 1, essence = 0, savedAt = NOW - 100, cagesUnlocked = 3, tutorial = 4, journal = { "hodag" },
	cages = cages({ [5] = { sp = "hodag", jar = 12.5 } }) } })
store:SetAsync("u_" .. D2, { data = { v = 1, essence = 0, savedAt = NOW - 10 * 86400, cagesUnlocked = 3, tutorial = 4, journal = { "hodag" },
	cages = cages({ [5] = { sp = "hodag", jar = 12.5 } }) } })
store:SetAsync("u_" .. D3, { data = { v = 1, essence = 0, savedAt = NOW + 5000, cagesUnlocked = 3, tutorial = 4, journal = { "hodag" },
	cages = cages({ [5] = { sp = "hodag", jar = 12.5 } }) } })
-- another server holds this profile's lock
store:SetAsync("u_" .. F, { jobId = "some-other-server", lockUntil = NOW + 100, data = { v = 1, essence = 777, savedAt = NOW,
	cagesUnlocked = 3, tutorial = 4, journal = {}, cages = cages({}) } })

-- THE WORST LAIR the game can reach, for the part budget: nine cages unlocked, every one holding
-- the species with the most Parts, the trap caps full on cells the current rules accept.
local FULL = 9606
local heaviest, heaviestParts = nil, -1
do
	local CryptidModel = require("../steal-a-cryptid/src/shared/CryptidModel")
	for _, sp in Config.Species do
		local n = #CryptidModel.parts(Config, sp.id)
		if n > heaviestParts then heaviest, heaviestParts = sp.id, n end
	end
	local L = Layout.generateLair(Config, Rng, Layout.lairSeed(Config, FULL))
	local traps = {}
	for _, kind in { "laser", "snare" } do
		for row = 1, 7 do
			for col = 1, 9 do
				if Layout.place(Config, L, col, row, kind) then table.insert(traps, Layout.trapString(kind, col, row)) end
			end
		end
	end
	local full = {}
	for col = 1, 9 do full[col] = { sp = heaviest, jar = 0 } end
	store:SetAsync("u_" .. FULL, { data = { v = 1, essence = 0, savedAt = NOW, cagesUnlocked = 9, tutorial = 4,
		journal = { heaviest }, cages = full, traps = traps } })
end

--============================================================ boot

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server script loads: " .. tostring(errServer))
if not okServer then
	print(string.format("steal a cryptid: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
truthy(remotes ~= nil, "ReplicatedStorage.CryptidRemotes exists")
local R = {}
for _, name in { "State", "Toast", "Fx", "Hunt", "LeaveCamp", "Reroll", "Expand", "BuildMode", "TrapAction" } do
	R[name] = remotes and remotes:FindFirstChild(name)
	truthy(R[name] ~= nil and R[name].ClassName == "RemoteEvent", "remote " .. name .. " is a RemoteEvent")
end

local function toastsOf(plr)
	local out = {}
	for _, rec in R.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function toastCount(plr) return #R.Toast:sentTo(plr) end
local function toastSince(plr, n, needle)
	local all = toastsOf(plr)
	for i = n + 1, #all do
		if string.find(string.lower(all[i]), string.lower(needle), 1, true) then return all[i] end
	end
	return nil
end
local function stateOf(plr)
	local sent = R.State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function fxSince(plr, n, kind)
	local sent = R.Fx:sentTo(plr)
	for i = n + 1, #sent do
		if sent[i].args[1] == kind then return sent[i] end
	end
	return nil
end

local function descendants(root)
	local out = {}
	local function walk(node)
		for _, c in inst.stateOf(node).children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(root)
	return out
end
local function countParts(root)
	local n = 0
	for _, d in descendants(root) do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end
local function hrpOf(plr)
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end
local function fmt(v) return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z) end

--============================================================ 1. the road, the Trailhead, the plots

print("1. the world at boot")
local lairs = h.workspace:FindFirstChild("Lairs")
local pockets = h.workspace:FindFirstChild("Pockets")
truthy(lairs ~= nil, "workspace.Lairs exists")
truthy(pockets ~= nil, "workspace.Pockets exists")

local expectedPlots = math.max(Config.World.Plots, h.Players.MaxPlayers)
do
	local n = 0
	for _, c in lairs:GetChildren() do
		if string.match(c.Name, "^Plot_%d+$") then n += 1 end
	end
	eq(n, expectedPlots, string.format("max(World.Plots %d, MaxPlayers %d) plots are built", Config.World.Plots, h.Players.MaxPlayers))
	for i = 0, expectedPlots - 1 do
		local plot = lairs:FindFirstChild("Plot_" .. i)
		local floor = plot and plot:FindFirstChild("Floor")
		truthy(floor ~= nil and floor:IsA("BasePart") and floor:IsDescendantOf(h.workspace), "Plot_" .. i .. " has a Floor in the workspace")
	end
end

local trailhead = h.workspace:FindFirstChild("Trailhead")
do
	truthy(trailhead ~= nil and trailhead.ClassName == "SpawnLocation", "workspace.Trailhead is a SpawnLocation")
	local enabled, underPlay = 0, 0
	for _, d in descendants(h.workspace) do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then
			enabled += 1
			if d:IsDescendantOf(lairs) or d:IsDescendantOf(pockets) then underPlay += 1 end
		end
	end
	eq(enabled, 1, "exactly ONE enabled SpawnLocation in the whole workspace")
	eq(underPlay, 0, "...and none of them in a lair or a pocket")
	if trailhead then
		eq(fmt(trailhead.Position), "0.00, 0.50, 0.00", "the Trailhead sits at the origin")
		eq(fmt(trailhead.Size), "12.00, 1.00, 12.00", "the Trailhead is 12 x 1 x 12")
	end
	local roadParts = 0
	for _, d in descendants(h.workspace) do
		if d:IsA("BasePart") and not d:IsDescendantOf(lairs) and not d:IsDescendantOf(pockets)
			and not (h.workspace:FindFirstChild("Poachers") and d:IsDescendantOf(h.workspace:FindFirstChild("Poachers"))) then
			roadParts += 1
		end
	end
	le(roadParts, Config.World.RoadPartBudget, "road + Trailhead part budget")
	print(string.format("   road + trailhead: %d BaseParts", roadParts))
end

do
	local templates = ServerStorage:FindFirstChild("CryptidTemplates")
	truthy(templates ~= nil, "ServerStorage.CryptidTemplates exists")
	local n = 0
	for _, s in Config.Species do
		local m = templates and templates:FindFirstChild(s.id)
		if m then
			n += 1
			le(countParts(m), 14, s.id .. " template is at most 14 parts")
		end
	end
	eq(n, 8, "all eight cryptid templates are built")
	eq(h.ReplicatedStorage:FindFirstChild("CryptidTemplates", true), nil, "no templates replicate from ReplicatedStorage")
end

--============================================================ 2. joining and landing (the engine's order)

-- The frame of a plot, read back from its Floor: plot-local (36, -0.5, 48) is the Floor's centre.
local function plotFrame(index)
	local floor = lairs:FindFirstChild("Plot_" .. index):FindFirstChild("Floor")
	return floor.CFrame * CF.new(-36, 0.5, -48)
end
local function plotOf(plr)
	for i = 0, expectedPlots - 1 do
		local plot = lairs:FindFirstChild("Plot_" .. i)
		local lair = plot and plot:FindFirstChild("Lair")
		if lair and plot:FindFirstChild("Sign") and string.find(tostring(plot.Sign.Label.Text.Text), plr.Name, 1, true) then
			return i, plot, lair
		end
	end
	return nil
end
local function assertHome(tag, plr)
	local i, plot, lair = plotOf(plr)
	truthy(i ~= nil, tag .. ": " .. plr.Name .. " owns a plot")
	if not i then return end
	local arrival = lair:FindFirstChild("Arrival")
	local hrp = hrpOf(plr)
	truthy(arrival ~= nil and hrp ~= nil, tag .. ": arrival marker and root exist")
	if not (arrival and hrp) then return end
	local d = math.sqrt((hrp.Position.X - arrival.Position.X) ^ 2 + (hrp.Position.Z - arrival.Position.Z) ^ 2)
	le(d, 4, string.format("%s: %s stands on their own arrival marker (XZ %.2f studs off; root %s)", tag, plr.Name, d, fmt(hrp.Position)))
	local t = math.sqrt(hrp.Position.X ^ 2 + hrp.Position.Z ^ 2)
	truthy(t > 12, tag .. ": ...and not on the Trailhead")
	truthy(hrp.Position.Y > 0 and hrp.Position.Y < 10, tag .. ": ...at standing height, not on a roof (y " .. string.format("%.2f", hrp.Position.Y) .. ")")
end

print("2. landing")
local pA = h:join("Digger", A)
h:advance(0.5)
do
	local i, plot, lair = plotOf(pA)
	eq(i, 0, "the first joiner is seated on Plot_0")
	truthy(lair ~= nil and lair.Parent == plot, "Plot_0.Lair is built and parented")
end

-- the recorded Studio order, replayed by hand: CharacterAdded on an unparented model at the
-- origin, the deferred queue drains, THEN the engine parents it and puts it on the Trailhead
do
	local char = inst.Instance.new("Model")
	char.Name = pA.Name
	local hrp = inst.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Parent = char
	local hum = inst.Instance.new("Humanoid")
	hum.Parent = char
	char.PrimaryPart = hrp
	hrp.CFrame = CF.new(0, 0, 0)
	pA.Character = char
	local sig = inst.stateOf(pA).signals["CharacterAdded"]
	truthy(sig ~= nil, "the server connected CharacterAdded")
	if sig then sig:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, char) end
	sched:advance(0)
	truthy(char.Parent == nil, "recorded order: still unparented when the deferred queue drains")
	char.Parent = h.workspace
	hrp.CFrame = CF.new(trailhead.Position.X, trailhead.Position.Y + 0.5 + 2.51, trailhead.Position.Z)
	h:advance(0.5)
	assertHome("recorded engine order", pA)
end

local pB = h:join("Sneak", B)
h:advance(0.5)
h.Players:simulateSpawn(pB, h.workspace)
h:advance(0.5)
assertHome("simulateSpawn", pB)
eq((plotOf(pB)), 1, "the second joiner is seated on Plot_1")
do
	local a, b = hrpOf(pA), hrpOf(pB)
	truthy((a.Position - b.Position).Magnitude > 20, "two players do not land on each other")
end
h.Players:simulateSpawn(pA, h.workspace)
h:advance(0.5)
assertHome("respawn", pA)

--============================================================ 3. every prompt and click is reachable

print("3. reachability")
local function applyAtRoot(frame, lx, lz) return frame:PointToWorldSpace(V3.new(lx, Config.World.RootHeight, lz)) end

local function apronStandPoints(index, lair)
	local frame = plotFrame(index)
	local blockers = {}
	for _, d in descendants(lair) do
		if d:IsA("BasePart") and d.CanCollide and (string.match(d.Name, "^Pedestal_") or d.Name == "HuntBoard") then
			local p = frame:PointToObjectSpace(d.Position)
			table.insert(blockers, { x = p.X, z = p.Z, hx = d.Size.X / 2 + 1, hz = d.Size.Z / 2 + 1 })
		end
	end
	local pts = {}
	for x = 1, 71, 2 do
		for z = 1, 15, 2 do
			local blocked = false
			for _, b in blockers do
				if math.abs(x - b.x) < b.hx and math.abs(z - b.z) < b.hz then blocked = true end
			end
			if not blocked then table.insert(pts, applyAtRoot(frame, x, z)) end
		end
	end
	return pts
end

local promptNames = {}
do
	local index, plot, lair = plotOf(pA)
	local frame = plotFrame(index)
	local apron = apronStandPoints(index, lair)
	truthy(#apron > 100, "the apron has somewhere to stand (" .. #apron .. " points)")
	-- the yard floor a player can actually walk to: the lair layout from the same seed
	local L = Layout.generateLair(Config, Rng, Layout.lairSeed(Config, A))
	local reach = Layout.reachableFrom(L, 5, 1)
	local yard = {}
	for row = 1, 8 do
		for col = 1, 9 do
			if reach[Layout.key(col, row)] then
				local x, z = Layout.cellCenter(Config, col, row)
				table.insert(yard, applyAtRoot(frame, x, z))
			end
		end
	end
	local stands = table.clone(apron)
	for _, p in yard do table.insert(stands, p) end

	local prompts, unknown = 0, {}
	for _, d in descendants(lair) do
		if d.ClassName == "ProximityPrompt" then
			prompts += 1
			promptNames[d.Name] = (promptNames[d.Name] or 0) + 1
			local host = d.Parent
			truthy(host:IsA("BasePart") and host:IsDescendantOf(h.workspace), d:GetFullName() .. " hangs on a Part in the workspace")
			truthy(d.Enabled ~= false, d:GetFullName() .. " is enabled")
			local best = math.huge
			for _, p in stands do best = math.min(best, (p - host.Position).Magnitude) end
			le(best, d.MaxActivationDistance, string.format("%s reachable: nearest standing root %.2f studs", d:GetFullName(), best))
			if d.Name ~= "Buy" and d.Name ~= "Release" and d.Name ~= "Hunt" then table.insert(unknown, d.Name) end
		end
	end
	eq(promptNames.Buy, 3, "three Buy prompts, one per pedestal")
	eq(promptNames.Release, 3, "a Release prompt on each of the three unlocked cages")
	eq(promptNames.Hunt, 1, "one Hunt prompt, on the board")
	eq(#unknown, 0, "no prompt of an unaccounted kind: " .. table.concat(unknown, ","))

	-- a pedestal's prompt belongs to the pedestal you stand at. Measured, not assumed: the arrival
	-- marker is 10 studs from P1 on the flat, and the prompt hangs on the pedestal's centre 1.5 studs
	-- below a standing root, so AT the marker no prompt is in reach (10.11) and the first purchase
	-- is one step away. Standing at P1's front, P1 is in reach and its neighbour P2 is not.
	local peds = lair:FindFirstChild("Pedestals")
	local p1, p2 = peds:FindFirstChild("Pedestal_1"), peds:FindFirstChild("Pedestal_2")
	local fromArrival = applyAtRoot(frame, Config.World.Apron.Arrival.x, Config.World.Apron.Arrival.z)
	local dArrival = (fromArrival - p1.Position).Magnitude
	print(string.format("   arrival marker to P1's prompt: %.2f studs (reach %d)", dArrival, p1.Buy.MaxActivationDistance))
	le(dArrival, p1.Buy.MaxActivationDistance + 0.5, "P1's prompt is at most a half-stud step from the arrival marker")
	local atP1 = applyAtRoot(frame, Config.World.Apron.P1.x, Config.World.Apron.P1.z - 3)
	le((atP1 - p1.Position).Magnitude, p1.Buy.MaxActivationDistance, "standing at P1's front, P1's prompt is in reach")
	truthy((atP1 - p2.Position).Magnitude > p2.Buy.MaxActivationDistance, "...and P2's is not, so a prompt belongs to the pedestal you stand at")
	local atP2 = applyAtRoot(frame, Config.World.Apron.P2.x, Config.World.Apron.P2.z - 3)
	truthy((atP2 - p1.Position).Magnitude > p1.Buy.MaxActivationDistance and (atP2 - peds.Pedestal_3.Position).Magnitude > 10,
		"standing at P2's front, neither neighbour's prompt is in reach")

	-- the Collect Pad is touchable and on the apron
	local pad = lair:FindFirstChild("CollectPad")
	truthy(pad ~= nil and pad.CanTouch ~= false, "the Collect Pad exists and can be touched")

	-- REVIEW-1.md B3 / DESIGN.md section 13: "a faint glow rim on every interactable (pedestals, pad,
	-- board, cage prompts)". Measured on the 2026-09-17 build: no cage carried one.
	local unglowed = {}
	for _, d in descendants(lair) do
		if d.ClassName == "ProximityPrompt" and not d.Parent:FindFirstChild("FxGlow") then
			table.insert(unglowed, d:GetFullName())
		end
	end
	eq(#unglowed, 0, "every Part carrying a prompt in the lair glows: " .. table.concat(unglowed, ", "))

	-- build tiles: clickable from EVERY apron point (design: farthest pairing 101.98 < 128)
	R.BuildMode:simulateFireServer(pA, true)
	h:advance(0.1)
	local tiles = lair:FindFirstChild("BuildTiles")
	truthy(tiles ~= nil, "build mode builds a BuildTiles folder")
	local nTiles, worst = 0, 0
	for _, tile in (tiles and tiles:GetChildren() or {}) do
		local cd = tile:FindFirstChildOfClass("ClickDetector")
		truthy(cd ~= nil and tile:IsA("BasePart") and tile:IsDescendantOf(h.workspace), tile.Name .. " is a Part in the workspace with a ClickDetector")
		if cd then
			nTiles += 1
			for _, p in apron do
				worst = math.max(worst, (p - tile.Position).Magnitude)
			end
			le(worst, cd.MaxActivationDistance, tile.Name .. " clickable from anywhere on the apron")
		end
	end
	-- every floor cell in rows 1..7 a player could reach, minus the entry
	local want = 0
	for row = 1, 7 do
		for col = 1, 9 do
			if reach[Layout.key(col, row)] and not (col == 5 and row == 1) then want += 1 end
		end
	end
	eq(nTiles, want, "one build tile per reachable, buildable yard cell")
	print(string.format("   %d prompts, %d build tiles, farthest apron-to-tile %.2f studs", prompts, nTiles, worst))
	local lairParts = countParts(plot)
	le(lairParts, Config.World.LairPartBudget, "lair part budget with build mode on")
	print(string.format("   Plot_%d with build mode on: %d BaseParts", index, lairParts))
	R.BuildMode:simulateFireServer(pA, false)
	h:advance(0.1)
	eq(lair:FindFirstChild("BuildTiles") and #lair.BuildTiles:GetChildren() or 0, 0, "build mode off removes the tiles")
end

do
	local pFull = h:join("Hoarder", FULL)
	h:advance(0.5)
	h.Players:simulateSpawn(pFull, h.workspace)
	h:advance(0.5)
	R.BuildMode:simulateFireServer(pFull, true)
	h:advance(0.2)
	local s = stateOf(pFull)
	eq(s.lasers, Config.Traps.MaxLasers, "the worst lair holds the laser cap")
	eq(s.snares, Config.Traps.MaxSnares, "...and the snare cap")
	local index, plot = plotOf(pFull)
	local n = countParts(plot)
	le(n, Config.World.LairPartBudget, "the WORST lair (9 x " .. heaviest .. ", full traps, build mode on) is inside the budget")
	print(string.format("   worst lair: 9 x %s (%d parts each), %d lasers + %d snares, build tiles on: %d BaseParts", heaviest, heaviestParts, s.lasers, s.snares, n))
	R.BuildMode:simulateFireServer(pFull, false)
	h:leave(pFull)
	h:advance(0.5)
end

--============================================================ 4. the first minute, through real prompts

print("4. the first minute")
local function lairOf(plr)
	local _, _, lair = plotOf(plr)
	return lair
end
do
	local lair = lairOf(pA)
	local s0 = stateOf(pA)
	eq(s0 and s0.essence, 30, "a new player starts with 30 Essence")
	eq(s0 and s0.offers[1].sp, "jackalope", "P1 shows the Jackalope")
	eq(s0 and s0.offers[1].price, 30, "...at 30")
	eq(s0 and s0.tutorial, 0, "tutorial step 0")

	-- somebody else pressing A's pedestal is told whose lair it is
	local nB = toastCount(pB)
	lair.Pedestals.Pedestal_1.Buy.Triggered:Fire(pB)
	truthy(toastSince(pB, nB, "Digger's lair") ~= nil, "another player's purchase attempt names the owner")
	eq(stateOf(pA).essence, 30, "...and buys nothing")

	lair.Pedestals.Pedestal_1.Buy.Triggered:Fire(pA)
	h:advance(0.1)
	local s1 = stateOf(pA)
	eq(s1.essence, 0, "buying the Jackalope spends all 30")
	eq(s1.cages[5].sp, "jackalope", "it goes into the centre cage")
	eq(s1.tutorial, 1, "tutorial step 1")
	eq(s1.journal, 1, "Journal 1/8")
	h:advance(Config.Economy.BuyTweenSeconds + 0.2)
	truthy(lair.Cages:FindFirstChild("Cryptid_5") ~= nil, "the Jackalope model stands in cage 5")
	truthy(stateOf(pA).offers[1].sp ~= "", "P1 has refilled after the delivery")

	h:advance(6)
	local jar = stateOf(pA).cages[5].jar
	truthy(jar >= 5, string.format("six seconds later the jar holds %.1f", jar))
	local pad = lair.CollectPad
	local hrp = hrpOf(pA)
	-- a touch fired while the root is at the Hunt Board, 14 studs off the pad, collects nothing
	hrp.CFrame = CF.new(lair.HuntBoard.Position)
	pad.Touched:Fire(hrp)
	eq(stateOf(pA).essence, 0, "a pad touch from 14 studs away collects nothing")
	hrp.CFrame = CF.new(pad.Position + V3.new(0, 3, 0))
	pad.Touched:Fire(hrp)
	h:advance(0.1)
	local s2 = stateOf(pA)
	truthy(s2.essence >= 5, string.format("collecting pays the jar (%d Essence)", s2.essence))
	eq(s2.cages[5].jar, 0, "...and empties it")
	eq(s2.tutorial, 2, "tutorial step 2")
	pad.Touched:Fire(hrp)
	eq(stateOf(pA).essence, s2.essence, "a second touch inside the debounce collects nothing more")

	-- the board
	local nFx = #R.Fx:sentTo(pA)
	lair.HuntBoard.Hunt.Triggered:Fire(pA)
	truthy(fxSince(pA, nFx, "openHunt") ~= nil, "the Hunt Board prompt opens the Hunt panel")
	local camps = stateOf(pA).camps
	eq(camps[1].unlocked, true, "Camp 1 open")
	eq(camps[1].permit, 0, "...and free")
	eq(camps[2].unlocked, true, "Camp 2 open with a Common in the Journal")
	eq(camps[2].permit, 360, "...permit 360")
	eq(camps[3].unlocked, false, "Camp 3 locked")
	truthy(type(camps[3].reason) == "string" and #camps[3].reason > 0, "...with its reason: " .. tostring(camps[3].reason))
end

--============================================================ 5. a raid walked along a real route

-- The route is planned against the camp the server's own seed produces, read back from
-- ServerStorage.RaidInfo (server-only), and followed by writing the character's root every tick:
-- exactly the claim a client makes.
local function raidInfo(plr)
	local folder = ServerStorage:FindFirstChild("RaidInfo")
	return folder and folder:FindFirstChild(tostring(plr.UserId))
end
local function pocketFrameOf(plr)
	local info = raidInfo(plr)
	local pocket = info and pockets:FindFirstChild("Pocket_" .. info:GetAttribute("Pocket"))
	local floor = pocket and pocket:FindFirstChild("Floor")
	return floor and floor.CFrame * CF.new(-36, 0.5, -56), pocket
end
local function campOf(plr)
	local info = raidInfo(plr)
	return Layout.generateCamp(Config, Rng, info:GetAttribute("Seed"), info:GetAttribute("Tier"))
end
local function routeAt(route, t)
	if t <= route[1].t then return route[1].x, route[1].z end
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		if t <= b.t then
			local f = if b.t > a.t then (t - a.t) / (b.t - a.t) else 1
			return a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
		end
	end
	return route[#route].x, route[#route].z
end
-- Walking to the board takes time, and raids may only START once per Raid.RestartCooldownSeconds
-- (a churn bound, check_stealacryptid_guards G7), so this spends that long getting there.
local function goToBoard(plr)
	local lair = lairOf(plr)
	hrpOf(plr).CFrame = CF.new(lair.HuntBoard.Position + lair.HuntBoard.CFrame.LookVector * 4)
	h:advance(Config.Raid.RestartCooldownSeconds + 0.1)
end

-- Walk a planned raid. Returns the server's final raid state (nil once it ended) and the clock.
local function walkRaid(plr, plan, prizeCol)
	local frame, pocket = pocketFrameOf(plr)
	local start = sched:now()
	local grabAt, grabEnd = plan.inTime, plan.inTime + Config.Camps[raidInfo(plr):GetAttribute("Tier")].hold
	local anchor = pocket.Cages:FindFirstChild("GrabAnchor_" .. prizeCol)
	local began, fired = false, false
	local hrp = hrpOf(plr)
	while sched:now() - start < plan.total + 3 do
		local tNext = sched:now() - start + Config.Raid.TickSeconds
		local x, z = routeAt(plan.route, tNext)
		hrp.CFrame = CF.new(frame:PointToWorldSpace(V3.new(x, Config.World.RootHeight, z)))
		if not began and tNext >= grabAt then
			anchor.Grab.PromptButtonHoldBegan:Fire(plr)
			began = true
		end
		h:advance(Config.Raid.TickSeconds)
		if began and not fired and sched:now() - start >= grabEnd then
			anchor.Grab.Triggered:Fire(plr)
			fired = true
		end
		local s = stateOf(plr)
		if s and s.raid == nil and sched:now() - start > 0.5 then break end
	end
	return stateOf(plr), sched:now() - start
end

print("5. raid: escape")
do
	-- a hunt started away from your own Hunt Board is refused, with the reason (sweep M15 found no
	-- assertion here)
	hrpOf(pA).CFrame = CF.new(lairOf(pA).Pedestals.Pedestal_3.Position + V3.new(0, 3, -3))
	h:advance(0.1)
	local nFar = toastCount(pA)
	R.Hunt:simulateFireServer(pA, 1)
	truthy(toastSince(pA, nFar, "Stand at your Hunt Board") ~= nil, "a hunt from the far pedestal is refused with the reason")
	eq(raidInfo(pA), nil, "...and starts nothing")
	h:advance(0.2)
	goToBoard(pA)
	local n = toastCount(pA)
	R.Hunt:simulateFireServer(pA, 1)
	local info = raidInfo(pA)
	truthy(info ~= nil, "a raid publishes ServerStorage.RaidInfo for the checks")
	if info then
		local frame, pocket = pocketFrameOf(pA)
		truthy(pocket ~= nil and pocket:IsDescendantOf(h.workspace), "the pocket is built and parented")
		local hrp = hrpOf(pA)
		local lp = frame:PointToObjectSpace(hrp.Position)
		near(lp.X, 36, 0.01, "the raider is put on the pocket's gate cell (x)")
		near(lp.Z, 20, 0.01, "...(z)")
		local camp = campOf(pA)
		-- the replayed camp IS the built camp: every laser part at the generator's cells, phases equal
		local phases = {}
		for _, t in Layout.traps(camp) do
			if t.kind == "laser" then table.insert(phases, string.format("%d,%d:%.6f", t.col, t.row, t.phase)) end
			local part = pocket.Traps:FindFirstChild((t.kind == "laser" and "Laser_" or "Snare_") .. t.col .. "_" .. t.row)
			truthy(part ~= nil, "pocket has " .. t.kind .. " at " .. t.col .. "," .. t.row)
		end
		eq(info:GetAttribute("LaserPhases"), table.concat(phases, ";"), "RaidInfo.LaserPhases matches the replayed generator")
		local prize
		for _, c in camp.cages do if c.prize then prize = c.col end end
		eq(info:GetAttribute("PrizeColumn"), prize, "RaidInfo.PrizeColumn matches the replayed generator")
		le(countParts(pocket), Config.World.PocketPartBudget, "pocket part budget")
		print(string.format("   pocket: %d BaseParts, camp %s", countParts(pocket), tostring(pocket.CampSign.Label.Text.Text)))

		for _, cg in camp.cages do
			local a = pocket.Cages:FindFirstChild("GrabAnchor_" .. cg.col)
			local pp = a and a:FindFirstChildOfClass("ProximityPrompt")
			truthy(pp ~= nil and a:IsDescendantOf(h.workspace), "cage " .. cg.col .. " has a Grab prompt on an anchor in the workspace")
			-- REVIEW-1.md B3: the grab spot glows, so a tier-1 camp (Commons carry no aura) shows where to stand
			truthy(a ~= nil and a:FindFirstChild("FxGlow") ~= nil, "cage " .. cg.col .. "'s Grab anchor glows")
			if pp then
				eq(pp.HoldDuration, Config.Camps[1].hold, "the Grab hold is the tier's")
				-- REVIEW-1.md B2: every point a 2 x 2 body can stand on in the grab cell, asked of the BUILT
				-- pocket (the first version tested four points inset 1 stud on both axes, but row 8 is open
				-- along x): the whole cage front is in reach, and nearly all of the cell
				local r = Layout.cellRect(Config, cg.col, 8)
				local colliders = {}
				for _, d in descendants(pocket) do
					if d:IsA("BasePart") and d.CanCollide ~= false and d.Position.Y + d.Size.Y / 2 > 0.6 then table.insert(colliders, d) end
				end
				local standing, shown, frontStanding, frontShown = 0, 0, 0, 0
				for x = r.x0, r.x1 - 0.25, 0.25 do
					for z = r.z0, r.z1, 0.25 do
						local world = frame:PointToWorldSpace(V3.new(x, 3, z))
						local blocked = false
						for _, d in colliders do
							local lp = d.CFrame:PointToObjectSpace(V3.new(world.X, d.Position.Y, world.Z))
							if math.abs(lp.X) < d.Size.X / 2 + 1 and math.abs(lp.Z) < d.Size.Z / 2 + 1 then blocked = true; break end
						end
						if not blocked then
							standing += 1
							local inReach = (world - a.Position).Magnitude <= pp.MaxActivationDistance
							if inReach then shown += 1 end
							if z >= r.z1 - 1.5 then
								frontStanding += 1
								if inReach then frontShown += 1 end
							end
						end
					end
				end
				truthy(frontStanding > 0 and frontShown == frontStanding, string.format("cage %d: the Grab prompt shows all along the cage front (%d of %d points)", cg.col, frontShown, frontStanding))
				truthy(standing > 0 and shown / standing >= 0.97, string.format("cage %d: ...and on %.1f %% of the %d points a body stands on in its grab cell", cg.col, 100 * shown / math.max(1, standing), standing))
			end
		end
		local plan = Heist.solveRaid(Config, Layout, camp, { pad = Config.Raid.HumanPad })
		truthy(plan ~= nil, "the camp has a padded route")
		local beforeRaid = stateOf(pA)
		local s, took = walkRaid(pA, plan, prize)
		eq(s.raid, nil, string.format("the raid ended after %.1f s (plan %.2f s)", took, plan.total))
		local escaped = toastSince(pA, n, "you stole")
		truthy(escaped ~= nil, "escaping with the prize says so: " .. tostring(escaped))
		local prizeSp
		for _, c in camp.cages do if c.prize then prizeSp = c.sp end end
		local got, stolenCol = 0, nil
		for col, c in s.cages do
			if c.sp == prizeSp then got += 1 end
			-- the cage the steal filled (the prize can be the species A already bought)
			if c.sp == prizeSp and beforeRaid.cages[col].sp == "" then stolenCol = col end
		end
		truthy(got >= 1, "the stolen " .. tostring(prizeSp) .. " is in a cage")
		-- REVIEW-1.md B3 / DESIGN.md section 12: "the stolen Common walks into cage 2", the way a bought
		-- one walks from its pedestal. Measured on the 2026-09-17 build: it appeared in the cage.
		do
			local lairA = lairOf(pA)
			local model = stolenCol and lairA.Cages:FindFirstChild("Cryptid_" .. stolenCol)
			local base = stolenCol and lairA.Cages:FindFirstChild("Cage_" .. stolenCol)
			truthy(model ~= nil and base ~= nil, "the stolen cryptid's model and its cage exist")
			if model and base then
				local function flatOff()
					local mp = model:GetPivot().Position
					return math.sqrt((mp.X - base.Position.X) ^ 2 + (mp.Z - base.Position.Z) ^ 2)
				end
				local early = flatOff()
				h:advance(Config.Economy.BuyTweenSeconds + 0.3)
				local late = flatOff()
				truthy(early > 20, string.format("right after the escape the stolen cryptid is still on its way, %.1f studs from its cage", early))
				le(late, 1, string.format("...and %.1f s later it stands in the cage (%.2f studs off)", Config.Economy.BuyTweenSeconds + 0.3, late))
			end
		end
		eq(s.stats.steals, 1, "stats.steals 1")
		eq(s.tutorial, 4, "the first raid ending finishes the tutorial")
		truthy(s.camps[1].heatLeft > 0 and s.camps[1].heatLeft <= 30, "Camp 1 is on alert for up to 30 s: " .. tostring(s.camps[1].heatLeft))
		eq(raidInfo(pA), nil, "RaidInfo is cleared after the raid")
		eq(#pockets:GetChildren(), 0, "the pocket is destroyed")
		assertHome("after the raid", pA)
		-- the grant reached the store in one write
		local saved = store:GetAsync("u_" .. A)
		local inStore = 0
		for _, c in (saved and saved.data and saved.data.cages or {}) do if c.sp == prizeSp then inStore += 1 end end
		truthy(inStore >= 1, "the steal is in the DataStore immediately")
		eq(saved and saved.jobId, "robloxemu-headless", "the store record carries this session's lock token")
		-- a second tier-1 hunt while the camp is on alert is refused with the reason
		goToBoard(pA)
		local n2 = toastCount(pA)
		R.Hunt:simulateFireServer(pA, 1)
		truthy(toastSince(pA, n2, "alert") ~= nil, "Heat refuses the next tier-1 hunt with a reason")
		eq(raidInfo(pA), nil, "...and starts nothing")
	end
end

--============================================================ 6. raid rules against claimed positions

print("6. raid: the catch, the teleport, the noclip")
local function bfsPath(camp, from, to)
	local key = Layout.key
	local prev, seen = {}, { [key(from[1], from[2])] = true }
	local q, head = { from }, 1
	while head <= #q do
		local u = q[head]; head += 1
		if u[1] == to[1] and u[2] == to[2] then break end
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nc, nr = u[1] + d[1], u[2] + d[2]
			local k = key(nc, nr)
			if not seen[k] and Layout.cellKind(camp, nc, nr) == "floor" and Layout.trapAt(camp, nc, nr) == nil then
				seen[k] = true; prev[k] = u
				table.insert(q, { nc, nr })
			end
		end
	end
	local path, k = { to }, key(to[1], to[2])
	if not seen[k] then return nil end
	while prev[k] do
		table.insert(path, 1, prev[k]); k = key(prev[k][1], prev[k][2])
	end
	return path
end
-- Walk the root cell to cell. It STOPS the moment the server ends the raid: a client whose
-- character the server has just sent home is not still standing in the pocket, and a walker that
-- kept writing pocket positions would drag the character back and fail the home check on
-- whichever tick the catch happened to land (seen: a flaky CONTROL in the first mutation sweep).
local function walkCells(plr, frame, cells, speed)
	local hrp = hrpOf(plr)
	for i = 2, #cells do
		local ax, az = Layout.cellCenter(Config, cells[i - 1][1], cells[i - 1][2])
		local bx, bz = Layout.cellCenter(Config, cells[i][1], cells[i][2])
		local steps = math.ceil((Config.World.CellSize / speed) / Config.Raid.TickSeconds)
		for k = 1, steps do
			local s = stateOf(plr)
			if not (s and s.raid) then return false end
			local f = k / steps
			hrp.CFrame = CF.new(frame:PointToWorldSpace(V3.new(ax + (bx - ax) * f, 3, az + (bz - az) * f)))
			h:advance(Config.Raid.TickSeconds)
		end
	end
	return true
end

do
	-- (a) walking into an ON net
	-- Camps are random (a server-only salt), and a legal camp can wall off the cell below its net from
	-- the gate side (seed 651182418: rocks at (3,1), (4,2), (3,3) close off (2,3); 1 run in 60 hit
	-- one). So draw camps until one has a trap-free walk there; 12 misses in a row is a failure.
	local n, start, info, camp, frame, laser, below
	for attempt = 1, 12 do
		goToBoard(pB)
		n = toastCount(pB)
		R.Hunt:simulateFireServer(pB, 1)
		start = sched:now()
		info = raidInfo(pB)
		if not info then break end
		camp = campOf(pB)
		frame = pocketFrameOf(pB)
		laser = nil
		for _, t in Layout.traps(camp) do if t.kind == "laser" then laser = t end end
		below = bfsPath(camp, { 5, 0 }, { laser.col, laser.row - 1 })
		if below then break end
		print(string.format("   camp seed %d has no trap-free walk to the cell below its net; drawing another", info:GetAttribute("Seed")))
		R.LeaveCamp:simulateFireServer(pB)
		h:advance(0.2)
	end
	truthy(info ~= nil, "B's tier-1 raid started")
	print(string.format("   caught test camp seed %d", info:GetAttribute("Seed")))
	truthy(below ~= nil, "a trap-free way to the cell below the camp's laser")
	walkCells(pB, frame, below, 12)
	-- wait beside the net until stepping in lands inside a dangerous window
	local depart = sched:now() - start
	while not (Heist.dangerousAt(Config, laser, depart + 0.45) and Heist.dangerousAt(Config, laser, depart + 0.9)) do
		depart += 0.05
	end
	h:advance(math.max(0, depart - (sched:now() - start)))
	walkCells(pB, frame, { { laser.col, laser.row - 1 }, { laser.col, laser.row } }, 16)
	h:advance(0.6)
	local s = stateOf(pB)
	eq(s.raid, nil, "walking into an ON net ends the raid")
	truthy(toastSince(pB, n, "caught by a laser net") ~= nil, "...with 'Caught by a laser net'")
	eq(s.stats.caught, 1, "stats.caught 1")
	eq(s.stats.steals, 0, "no steal")
	eq(s.camps[1].heatLeft, 0, "a failure sets no Heat")
	assertHome("after being caught", pB)
	truthy(fxSince(pB, 0, "caught") ~= nil, "the caught camera juice is sent")

	-- (b) a claimed teleport to the prize
	goToBoard(pB)
	R.Hunt:simulateFireServer(pB, 1)
	info = raidInfo(pB)
	truthy(info ~= nil, "B's second raid started (a failure left no Heat)")
	camp = campOf(pB)
	frame = pocketFrameOf(pB)
	local _, pocket = pocketFrameOf(pB)
	local prize
	for _, c in camp.cages do if c.prize then prize = c.col end end
	local gx, gz = Layout.cellCenter(Config, prize, 8)
	local hrp = hrpOf(pB)
	hrp.CFrame = CF.new(frame:PointToWorldSpace(V3.new(gx, 3, gz)))
	h:advance(Config.Raid.TickSeconds)
	local tx, tz = info:GetAttribute("TrustedX"), info:GetAttribute("TrustedZ")
	local moved = math.sqrt((tx - 36) ^ 2 + (tz - 20) ^ 2)
	le(moved, 16 * 1.35 * 0.1 + 1e-6, string.format("a claimed teleport moves the trusted position %.2f studs in one tick", moved))
	-- back to the gate (so the straight-line catch-up never wanders into a net), then fire the grab
	-- prompt with no hold, the way fireproximityprompt does
	hrp.CFrame = CF.new(frame:PointToWorldSpace(V3.new(36, 3, 20)))
	local n2 = toastCount(pB)
	pocket.Cages["GrabAnchor_" .. prize].Grab.Triggered:Fire(pB)
	h:advance(Config.Camps[1].hold + 0.2)
	truthy(toastSince(pB, n2, "in front of the cage") ~= nil, "the grab is refused: the trusted position is not at the cage")
	truthy(stateOf(pB).raid ~= nil and not stateOf(pB).raid.carrying, "...and nothing is carried")

	-- (c) a claimed noclip straight through a fence
	R.LeaveCamp:simulateFireServer(pB)
	h:advance(0.2)
	eq(stateOf(pB).raid, nil, "Leave camp ends the raid")
	goToBoard(pB)
	R.Hunt:simulateFireServer(pB, 1)
	info = raidInfo(pB)
	camp = campOf(pB)
	frame = pocketFrameOf(pB)
	-- a fence cell of row 4 with a trap-free walk to the cell below it
	local target
	for col = 1, 9 do
		if Layout.cellKind(camp, col, 4) == "fence" and Layout.cellKind(camp, col, 3) == "floor" and Layout.trapAt(camp, col, 3) == nil then
			local p = bfsPath(camp, { 5, 0 }, { col, 3 })
			if p and not target then target = { col = col, path = p } end
		end
	end
	truthy(target ~= nil, "a fence cell to noclip through")
	walkCells(pB, frame, target.path, 12)
	local fx = Layout.cellCenter(Config, target.col, 3)
	for _ = 1, 30 do
		if not stateOf(pB).raid then break end
		hrpOf(pB).CFrame = CF.new(frame:PointToWorldSpace(V3.new(fx, 3, 90)))
		h:advance(Config.Raid.TickSeconds)
	end
	tz = info:GetAttribute("TrustedZ")
	near(tz, 49, 1e-6, "a claimed noclip through a row-4 fence stops 1 stud into it (z 49)")
	eq(info:GetAttribute("TrustedX"), fx, "...without being rerouted towards a gap")
	R.LeaveCamp:simulateFireServer(pB)
	h:advance(0.2)

	-- (d) DESIGN.md section 9's last landing case: a character that respawns DURING a raid, under
	-- the engine's spawn order, lands on its own apron and not in the pocket or on the Trailhead
	goToBoard(pB)
	R.Hunt:simulateFireServer(pB, 1)
	truthy(raidInfo(pB) ~= nil, "B's fourth raid started")
	h.Players:simulateSpawn(pB, h.workspace)
	h:advance(0.5)
	eq(raidInfo(pB), nil, "a respawn during a raid ends it")
	eq(#pockets:GetChildren(), 0, "...and destroys the pocket")
	assertHome("respawn during a raid", pB)
end

--============================================================ 7. a grant whose write fails is rolled back

print("7. rollback")
do
	local pC = h:join("Hunter", C)
	h:advance(0.5)
	h.Players:simulateSpawn(pC, h.workspace)
	h:advance(0.5)
	eq(stateOf(pC).essence, 5000, "C loaded with 5000 Essence")
	goToBoard(pC)
	R.Hunt:simulateFireServer(pC, 2)
	eq(stateOf(pC).essence, 4640, "the tier-2 permit (360) is spent at the start")
	local camp = campOf(pC)
	local prize, prizeSp
	for _, c in camp.cages do if c.prize then prize, prizeSp = c.col, c.sp end end
	local plan = Heist.solveRaid(Config, Layout, camp, { pad = Config.Raid.HumanPad })
	store.__failAll = true
	local n = toastCount(pC)
	local s = walkRaid(pC, plan, prize)
	store.__failAll = false
	eq(s.raid, nil, "the raid ended")
	truthy(toastSince(pC, n, "could not be saved") ~= nil, "the player is told the steal could not be saved")
	eq(s.essence, 5000, "the permit is refunded")
	local rares = 0
	for _, c in s.cages do if Economy.tierOf(Config, c.sp) == 2 then rares += 1 end end
	eq(rares, 0, "the " .. tostring(prizeSp) .. " is rolled back out of the cages")
	eq(s.camps[2].heatLeft, 0, "no Heat was kept")
	eq(s.stats.steals, 0, "no steal was counted")
	eq(s.journal, 1, "the Journal did not gain the Rare")
end

--============================================================ 8. offline jars, the session lock

print("8. offline jars and locks")
do
	local p1 = h:join("Sleeper", D1)
	local p2 = h:join("Hibernator", D2)
	local p3 = h:join("TimeTraveller", D3)
	local first = function(plr) local sent = R.State:sentTo(plr); return sent[1] and sent[1].args[1] end
	local j1 = first(p1).cages[5].jar
	truthy(j1 >= 212.5 and j1 <= 214.5, string.format("100 s offline at 2/s: jar 12.5 -> %.1f (212.5 + at most 2 s of clock tick)", j1))
	eq(first(p2).cages[5].jar, 57600, "ten days offline mints exactly one full jar")
	eq(first(p3).cages[5].jar, 12.5, "a savedAt in the future adds nothing")

	-- A locked record is re-read for Save.LockWaitSeconds before the session plays unsaved
	-- (REVIEW-1.md A1), so this join YIELDS: it runs on its own thread, the way Roblox runs a
	-- PlayerAdded handler (h:join fires it inline, where a wait cannot resume).
	local pF = inst.Instance.new("Player")
	pF.Name = "Twin"
	pF.UserId = F
	local pgF = inst.Instance.new("PlayerGui")
	pgF.Name = "PlayerGui"
	pgF.Parent = pF
	pF.Parent = h.Players
	inst.stateOf(h.Players).signals["PlayerAdded"]:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, pF)
	h:advance(1)
	eq(stateOf(pF), nil, "while the lock is waited for, no lair state is sent yet")
	truthy(toastSince(pF, 0, "waiting") ~= nil, "...and the player is told the save is being waited for")
	h:advance(Config.Save.LockWaitSeconds + 1)
	local sF = stateOf(pF)
	eq(sF.canSave, false, "a profile still locked by another server after the wait is a non-saving session")
	truthy(string.find(string.lower(tostring(sF.saveBanner)), "rejoin in 2 minutes", 1, true) ~= nil, "...and the banner says when to come back: " .. tostring(sF.saveBanner))
	eq(sF.essence, 777, "...but it plays with the saved progress")
	local lairF = lairOf(pF)
	lairF.Pedestals.Pedestal_1.Buy.Triggered:Fire(pF)
	h:advance(Config.Save.FlushTickSeconds * 2 + 1)
	local rec = store:GetAsync("u_" .. F)
	eq(rec.jobId, "some-other-server", "the other server's lock is untouched")
	eq(rec.data.essence, 777, "...and nothing was ever written")
end

do
	-- A lock taken over MID-SESSION: our lock lapsed (say a stalled autosave) and another server
	-- claimed the record. This session still believes it can save, so the only thing standing
	-- between it and overwriting the other server's data is the guard inside the flush itself.
	-- Sweep M12 removed that guard and nothing noticed, because a session locked at LOAD never
	-- flushes at all.
	local key = "u_" .. A
	local rec = store:GetAsync(key)
	rec.jobId = "the-server-that-took-over"
	rec.lockUntil = os.time() + 100
	rec.data.essence = 424242
	store:SetAsync(key, rec)
	local lairA = lairOf(pA)
	hrpOf(pA).CFrame = CF.new(lairA.CollectPad.Position + V3.new(0, 3, 0))
	h:advance(1)
	lairA.CollectPad.Touched:Fire(hrpOf(pA)) -- a real change that marks a save
	h:advance(Config.Save.FlushTickSeconds * 2 + 1)
	local after = store:GetAsync(key)
	eq(after.jobId, "the-server-that-took-over", "a lock taken over mid-session is left with its new owner")
	eq(after.data.essence, 424242, "...and this session's flush does not overwrite that server's data")
	-- hand the record back so later sections run on a saving session again
	after.jobId = nil
	after.lockUntil = 0
	store:SetAsync(key, after)
end

--============================================================ 9. remotes: validation and rate limits

print("9. remotes")
do
	local n = toastCount(pA)
	R.Hunt:simulateFireServer(pA, "four")
	truthy(toastSince(pA, n, "camp") ~= nil, "Hunt with a string is refused with a toast")
	n = toastCount(pA)
	R.Hunt:simulateFireServer(pA, 9)
	truthy(toastSince(pA, n, "camp") ~= nil, "Hunt(9) is refused with a toast")
	n = toastCount(pA)
	R.TrapAction:simulateFireServer(pA, 2, 3, "laser")
	truthy(toastSince(pA, n, "build mode") ~= nil, "a trap outside build mode is refused with a toast")
	h:advance(1.1)
	n = toastCount(pA)
	for _ = 1, 20 do R.Reroll:simulateFireServer(pA) end
	local slow = 0
	for i, t in toastsOf(pA) do
		if i > n and string.find(t, "Slow down", 1, true) then slow += 1 end
	end
	eq(slow, 1, "20 re-rolls in one tick: exactly one 'Slow down' toast")
	-- in-world prompts and build tiles go through the same limiter: fireproximityprompt in a loop
	-- must not schedule hundreds of server-timed holds
	h:advance(5.1)
	n = toastCount(pA)
	local lairA = lairOf(pA)
	for _ = 1, 20 do lairA.Cages.Cage_5.Release.Triggered:Fire(pA) end
	R.BuildMode:simulateFireServer(pA, true)
	h:advance(0.1)
	local tile = lairA.BuildTiles:GetChildren()[1]
	for _ = 1, 20 do tile.Click.MouseClick:Fire(pA) end
	slow = 0
	for i, t in toastsOf(pA) do
		if i > n and string.find(t, "Slow down", 1, true) then slow += 1 end
	end
	eq(slow, 1, "20 prompt triggers and 20 tile clicks in one tick: exactly one 'Slow down' toast (5 s cooldown)")
	local cells = 0
	for _, rec in R.Fx:sentTo(pA) do if rec.args[1] == "buildCell" then cells += 1 end end
	le(cells, Config.Remotes.MaxPerSecond, "a tile clicked 20 times in a tick answers at most 8 times")
	R.BuildMode:simulateFireServer(pA, false)
	h:advance(1.2)
end

--============================================================ 10. the wire: no attributes anywhere a client can read

print("10. the attribute inventory")
do
	-- put as much of the game on screen as possible first: a raid in progress, build mode on
	goToBoard(pB)
	R.Hunt:simulateFireServer(pB, 1)
	R.BuildMode:simulateFireServer(pA, true)
	h:advance(1)
	truthy(#pockets:GetChildren() == 1, "a pocket exists while inventorying")
	local found = {}
	for _, root in { h.workspace, h.ReplicatedStorage } do
		for _, d in descendants(root) do
			for name in d:GetAttributes() do
				table.insert(found, d:GetFullName() .. " :: " .. name)
			end
		end
	end
	for i = 1, math.min(#found, 10) do print("   ATTRIBUTE " .. found[i]) end
	eq(#found, 0, "no attribute on any Instance under workspace or ReplicatedStorage")
	R.LeaveCamp:simulateFireServer(pB)
	R.BuildMode:simulateFireServer(pA, false)
	h:advance(0.2)
end

--============================================================ 11. leaving frees the plot

print("11. leaving")
do
	local index = plotOf(pB)
	h:leave(pB)
	h:advance(0.5)
	local plot = lairs:FindFirstChild("Plot_" .. index)
	eq(plot:FindFirstChild("Lair"), nil, "a leaver's lair is destroyed")
	eq(#pockets:GetChildren(), 0, "...with no pocket left behind")
	eq(store:GetAsync("u_" .. B).jobId, nil, "...and the session lock is released")
	local pE = h:join("Newcomer", E)
	h:advance(0.5)
	eq((plotOf(pE)), index, "the next joiner reuses the freed plot")
	h.Players:simulateSpawn(pE, h.workspace)
	h:advance(0.5)
	assertHome("reused plot", pE)
end

--============================================================ text lengths the HUD was sized for

do
	-- check_stealacryptid_hud.luau proves a 100-character toast and a 90-character banner are
	-- legible on a phone. That proof is only worth something if the server never sends longer, so
	-- every toast and every banner this run actually produced is measured here.
	local longestToast, longestBanner, toastText, bannerText = 0, 0, "", ""
	for _, rec in R.Toast:getSent() do
		local t = tostring(rec.args[1])
		if #t > longestToast then longestToast, toastText = #t, t end
	end
	for _, rec in R.State:getSent() do
		local b = rec.args[1] and rec.args[1].saveBanner
		if type(b) == "string" and #b > longestBanner then longestBanner, bannerText = #b, b end
	end
	print(string.format("   longest toast sent: %d chars; longest banner: %d chars", longestToast, longestBanner))
	le(longestToast, 100, "every toast this run sent fits the HUD's 100-character proof: " .. toastText)
	le(longestBanner, 90, "every banner this run sent fits the HUD's 90-character proof: " .. bannerText)
end

--============================================================ done

print("")
for _, w in h.warnings do print("  [warn] " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("steal a cryptid: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid check failed", 0) end
