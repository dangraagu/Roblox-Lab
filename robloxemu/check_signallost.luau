-- SIGNAL LOST: Derelict Station — the main headless check. Run: luau check_signallost.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--
-- Boots the REAL server (and, for the board, the real Board.client) and asserts what DESIGN.md §19 lists for this
-- file, through the server's own rules: the world is BUILT and PARENTED before anyone joins; a joining character
-- LANDS on HubSpawn under the engine's spawn order; every prompt is reachable and does what it says; the board
-- exists and renders; the lift builds only the dock; hatches open only on a trusted approach; a teleport claim
-- neither opens hatches nor picks up; AIR drains in vacuum on the virtual clock; a blackout wakes the player in a
-- new dock with half banked; the splice banks, advances the best and lights the sector; a purchase whose write
-- fails is refused and rolled back; a reset settles once and respawns on HubSpawn; an open sector settles once on
-- rejoin; zones carry zero attributes and the debug names are nowhere a client can read; the part caps hold on
-- built folders; every glyph is one photographed in Studio.

local Harness = require("./emu/harness")
local Bot = require("../signal-lost/tests/Bot")

local h = Harness.new({ bundle = require("./build/signal-lost"), name = "signal-lost", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local DSS = h.services.DataStoreService
local profileStore = DSS:GetDataStore("SignalLost_v1")
local orderedStore = DSS:GetOrderedDataStore("SignalLost_Relays_v1")
local RS = h.game:GetService("RunService")
local SS = h.game:GetService("ServerStorage")

-- saved profiles, before the server starts
local NOW = os.time()
profileStore:SetAsync("u_7001", { data = { v = 1, salvage = 500, salvageEarned = 500, best = 4, bestAt = NOW - 1000,
	up = { tank = 0, boots = 0 }, blackouts = 0, attempts = 4 } })
profileStore:SetAsync("u_7002", { data = { v = 1, salvage = 10, salvageEarned = 10, best = 2, bestAt = NOW - 900,
	up = { tank = 0, boots = 0 }, blackouts = 0, attempts = 3, open = { id = "crashed-attempt", k = 3, carried = 41 } },
	lock = { owner = "a-dead-server", expires = NOW - 5 } })
profileStore:SetAsync("u_7003", { data = { v = 1, salvage = 0, best = 0, up = {} }, lock = { owner = "another-server", expires = NOW + 600 } })
profileStore:SetAsync("u_7004", { data = { v = 1, salvage = 0, salvageEarned = 0, best = 22, bestAt = NOW - 100, up = { tank = 4, boots = 4 } } })

--=========================================================================== A. the world is built and parented
section("A. boot: the world is BUILT and PARENTED before anyone joins")
local okBoot, errBoot = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads (" .. tostring(errBoot) .. ")")
local W = h.workspace
local boat = W:FindFirstChild("Lifeboat")
truthy(boat ~= nil and boat.Parent == W, "workspace.Lifeboat exists and is parented")
local hubSpawn = boat and boat:FindFirstChild("HubSpawn")
truthy(hubSpawn ~= nil and hubSpawn.ClassName == "SpawnLocation", "HubSpawn is a real SpawnLocation")
if hubSpawn then
	eq(hubSpawn.Enabled, true, "HubSpawn is enabled")
	eq(hubSpawn.Duration, 0, "no ForceField")
	eq(hubSpawn.Neutral, true, "neutral")
	eq(hubSpawn.Anchored, true, "anchored")
end
for _, name in { "HubFloor", "HubCeiling", "HubWallE", "HubWallW", "HubWallS", "PlanetWindow", "HubArrival", "Fabricator", "RelayBoard" } do
	local p = boat and boat:FindFirstChild(name)
	truthy(p ~= nil and p:IsA("BasePart") and p.Anchored == true, "the lifeboat has " .. name)
end
truthy(boat and boat:FindFirstChild("Lift") and boat.Lift:FindFirstChild("LiftPad") ~= nil, "the LIFT pad")
local benches = boat and boat:FindFirstChild("Benches")
local seats = 0
if benches then for _, c in benches:GetChildren() do if c.ClassName == "Seat" then seats += 1 end end end
eq(seats, 2, "two real Seats (the benches)")
truthy(W:FindFirstChild("Station") ~= nil, "workspace.Station (the zones' parent) exists")
local remotes = h.ReplicatedStorage:FindFirstChild("SignalRemotes")
for _, n in { "State", "Notice", "Board", "Announce", "BuyUpgrade" } do
	truthy(remotes and remotes:FindFirstChild(n) ~= nil and remotes[n].ClassName == "RemoteEvent", "remote " .. n)
end
truthy(h.Lighting:FindFirstChild("FxAtmosphere") ~= nil and h.Lighting:FindFirstChild("FxColorCorrection") ~= nil, "Fx.Presets.Station is applied")
local function enabledSpawns()
	local n, where = 0, {}
	for _, d in W:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then n += 1; table.insert(where, d:GetFullName()) end
	end
	return n, table.concat(where, ", ")
end
do
	local n, where = enabledSpawns()
	eq(n, 1, "HubSpawn is the only enabled SpawnLocation at boot (" .. where .. ")")
end

--=========================================================================== B. the spawn, under the engine's order
section("B. a joining character LANDS on HubSpawn under the engine's spawn order")
local plr = h:join("Ava", 501)
eq(plr.RespawnLocation, hubSpawn, "RespawnLocation points at HubSpawn before the character exists")
local char = h.Players:simulateSpawn(plr, W)
local hrp = char:FindFirstChild("HumanoidRootPart")
h:advance(0.5)
do
	local p = hrp.Position
	local sp = hubSpawn.Position
	truthy(math.abs(p.X - sp.X) <= hubSpawn.Size.X / 2 and math.abs(p.Z - sp.Z) <= hubSpawn.Size.Z / 2,
		string.format("the root stands over HubSpawn's footprint (%.2f, %.2f, %.2f)", p.X, p.Y, p.Z))
	truthy(p.Y > sp.Y + hubSpawn.Size.Y / 2, "above its top face")
	local hum = char:FindFirstChildOfClass("Humanoid")
	eq(hum.WalkSpeed, 16, "WalkSpeed 16 in the lifeboat")
	eq(hum.JumpHeight, 7.2, "JumpHeight 7.2")
	eq(char.Parent, W, "the character is in the world")
end
local src = require("./build/signal-lost")["server/Main.server"].source
do -- CharacterAdded writes no CFrame and never yields (read off the source: the handler is onCharacter)
	local body = string.match(src, "local function onCharacter%(.-\nend\n")
	truthy(body ~= nil, "onCharacter found")
	if body then
		body = string.gsub(body, "%-%-[^\n]*", "") -- code only: its comments SAY what it never does
		truthy(string.find(body, "CFrame", 1, true) == nil and string.find(body, "PivotTo", 1, true) == nil, "onCharacter writes no CFrame")
		truthy(string.find(body, "task.wait", 1, true) == nil and string.find(body, "WaitForChild", 1, true) == nil, "onCharacter never yields")
	end
end

-- the board renders, drawn by the real Board.client for this player
RS:setIsServer(false)
local okBoardClient, errBC = h:tryRun("client/Board.client")
truthy(okBoardClient, "Board.client loads (" .. tostring(errBC) .. ")")
local okHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads")
local bot = Bot.new(h, plr, { onTick = function() RS.RenderStepped:Fire(0.1) end })
bot:waitSeconds(1)

--=========================================================================== C. every prompt is reachable
section("C. every prompt is reachable and does what it says")
local H = { SizeX = 60, SizeZ = 40 }
local function walkable(p)
	-- inside the lifeboat's floor, 1.5 studs off the walls, not on the lift pad, not inside a bench or console
	if math.abs(p.X) > H.SizeX / 2 - 1.5 or math.abs(p.Z) > H.SizeZ / 2 - 1.5 then return false end
	for _, d in boat:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide ~= false and d.Name ~= "HubFloor" and d.Name ~= "HubCeiling" and d.Name ~= "HubSpawn"
			and d.Name ~= "LiftPad" then
			local s, c = d.Size, d.Position
			if math.abs(p.X - c.X) < s.X / 2 + 1 and math.abs(p.Z - c.Z) < s.Z / 2 + 1 and c.Y - s.Y / 2 < 5 then return false end
		end
	end
	local lift = boat.Lift.LiftPad
	if math.abs(p.X - lift.Position.X) <= 4.5 and math.abs(p.Z - lift.Position.Z) <= 4.5 then return false end
	return true
end
local function promptPos(pr)
	local host = pr.Parent
	if host.ClassName == "Attachment" then
		return host.Parent.CFrame * host.Position
	end
	return host.Position
end
local prompts = {}
for _, d in boat:GetDescendants() do
	if d.ClassName == "ProximityPrompt" then table.insert(prompts, d) end
end
eq(#prompts, 2, "the lifeboat has two prompts (the board, the fabricator)")
for _, pr in prompts do
	local at = promptPos(pr)
	local best = nil
	for x = -29, 29, 1 do
		for z = -19, 19, 1 do
			local p = Vector3.new(x, 3, z)
			local d = (Vector3.new(at.X, 3, at.Z) - p).Magnitude
			if d <= pr.MaxActivationDistance - 1 and walkable(p) then
				if not best or d < best.d then best = { p = p, d = d } end
			end
		end
	end
	truthy(best ~= nil, pr:GetFullName() .. " can be reached from a walkable spot" .. (if best then string.format(" (%.1f studs, at %.0f, %.0f)", best.d, best.p.X, best.p.Z) else ""))
	truthy(#pr.ActionText > 0 and pr.HoldDuration == 0 and pr.Enabled ~= false, pr.Name .. " says what it does and is a tap")
end
do -- the fabricator's prompt opens the panel; the board's toggles the view
	local fab = boat.Fabricator:FindFirstChildOfClass("ProximityPrompt")
	bot:walkTo(Vector3.new(boat.Fabricator.Position.X, 0, boat.Fabricator.Position.Z + 4), "hub")
	fab.Triggered:Fire(plr)
	bot:waitSeconds(0.3)
	truthy(bot:saw("shop") ~= nil, "the fabricator's prompt opens the upgrade panel")
	eq(bot:state().nearFab, true, "and the State says the fabricator is in reach")
end

--=========================================================================== D. the board exists and renders
section("D. the highscore board exists near spawn and renders")
local board = boat.RelayBoard
do
	local d = board.Position - hubSpawn.Position
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	truthy(flat <= 30, string.format("the board is near spawn (%.1f studs)", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(hubSpawn.Position.X - board.Position.X, 0, hubSpawn.Position.Z - board.Position.Z)
	truthy((look.X * toSpawn.X + look.Z * toSpawn.Z) / toSpawn.Magnitude > 0.9, "its face turns toward the spawn")
	local sg = board:FindFirstChildWhichIsA("SurfaceGui", true)
	truthy(sg ~= nil and sg.Face == Enum.NormalId.Front, "Board.client drew a SurfaceGui on its front face")
	local texts = {}
	if sg then for _, t in sg:GetDescendants() do if t.ClassName == "TextLabel" and t.Visible ~= false then table.insert(texts, t.Text) end end end
	local all = table.concat(texts, " | ")
	truthy(string.find(all, "RELAYS RESTORED", 1, true) ~= nil, "it says RELAYS RESTORED")
	truthy(string.find(all, "PUBLIC", 1, true) ~= nil, "it starts on PUBLIC")
	truthy(string.find(all, "No relays restored yet", 1, true) ~= nil or string.find(all, "Loading", 1, true) ~= nil, "an empty board says something useful (" .. all .. ")")
	truthy(plr.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui")
	local bp = board:FindFirstChildWhichIsA("ProximityPrompt", true)
	bot:walkTo(Vector3.new(board.Position.X - 6, 0, board.Position.Z), "hub")
	bp.Triggered:Fire(plr)
	bot:waitSeconds(1)
	local sent = remotes.Board:sentTo(plr)
	eq(sent[#sent] and sent[#sent].args[1].mode, "friends", "the board's prompt toggles to FRIENDS for this player")
end

--=========================================================================== E. the lift builds only the dock
section("E. the LIFT, the dock, and what never replicates")
local function debugOf(p) return SS.SignalDebug:FindFirstChild("Run_" .. p.UserId) end
local function zoneOf(p)
	local d = debugOf(p)
	local idx = d and d:GetAttribute("ZoneIndex")
	return idx and W.Station:FindFirstChild("Zone_" .. idx)
end
local function builtModules(p)
	local z = zoneOf(p)
	local mods = z and z:FindFirstChild("Sector") and z.Sector:FindFirstChild("Modules")
	local out = {}
	if mods then for _, m in mods:GetChildren() do out[tonumber(string.match(m.Name, "%d+"))] = m end end
	return out
end
local function count(t) local n = 0 for _ in t do n += 1 end return n end
local MASTS = function()
	local n = 0
	for _, d in W:GetDescendants() do if d.Name == "RelayMast" then n += 1 end end
	return n
end
bot:walkTo(Vector3.new(boat.Lift.LiftPad.Position.X - 8, 0, 0), "hub")
truthy(bot:board(), "standing in the LIFT starts the ride")
truthy(bot:waitPhase("sector", 5), "the ride arrives")
local dbg = debugOf(plr)
truthy(dbg ~= nil, "ServerStorage.SignalDebug.Run_501 exists (server-only)")
local dock = dbg:GetAttribute("DockCell")
local relay = dbg:GetAttribute("RelayCell")
local built = builtModules(plr)
eq(count(built), 1, "on arrival only ONE module exists")
truthy(built[dock] ~= nil, "and it is the dock")
eq(MASTS(), 0, "no relay mast anywhere in the workspace before its module is built")
do
	local st = bot:state()
	local keys = {}
	for k in st do table.insert(keys, k) end
	table.sort(keys)
	eq(table.concat(keys, ","), "air,arrayDone,band,bars,best,boarding,carried,grace,hypoxic,k,loaded,moduleType,n,nearFab,phase,recommended,salvage,saving,secondsIn,spliced,splicing,storeless,tank,uid,up,upRows,visited",
		"the State payload's keys, exactly: no cell, no relay, no air map, no distance")
	eq(st.k, 1, "sector 1")
	eq(st.moduleType, "air", "the dock is air")
	eq(st.air, 20, "a full 20 s tank")
end
local function attributeSweep()
	local zoneAttrs, leaks = 0, {}
	for _, d in W.Station:GetDescendants() do
		for name in d:GetAttributes() do zoneAttrs += 1; table.insert(leaks, d:GetFullName() .. "." .. name) end
	end
	for _, root in { W, h.ReplicatedStorage } do
		for _, d in root:GetDescendants() do
			for name in d:GetAttributes() do
				if name == "Sector" or name == "DockCell" or name == "RelayCell" or name == "AirMap" or name == "SalvageCells"
					or name == "CanisterCells" or name == "TrustedCell" or name == "AttemptId" then
					table.insert(leaks, d:GetFullName() .. "." .. name)
				end
			end
			if string.match(d.Name, "^Run_%d+$") or d.Name == "SignalDebug" then table.insert(leaks, d:GetFullName()) end
		end
	end
	return zoneAttrs, leaks
end
do
	local zoneAttrs, leaks = attributeSweep()
	eq(zoneAttrs, 0, "zero attributes under every zone (the expected list is empty)")
	eq(#leaks, 0, "no debug name anywhere in Workspace or ReplicatedStorage (" .. table.concat(leaks, "; ") .. ")")
	local n = enabledSpawns()
	eq(n, 1, "mid-run, with a sector built, HubSpawn is still the only enabled SpawnLocation")
end

--=========================================================================== F. trust: hatches, teleports, pickups
section("F. hatches open only on a trusted approach; a teleport buys nothing")
local ZoneIdx = dbg:GetAttribute("ZoneIndex")
local O = Vector3.new(400 * ZoneIdx, 0, 0)
local N = dbg:GetAttribute("Grid")
local function centre(id)
	local cx, cy = (id - 1) % N, (id - 1) // N
	return O + Vector3.new((cx - (N - 1) / 2) * 32, 0, (cy - (N - 1) / 2) * 32)
end
local function hatchesOpen(p)
	local z = zoneOf(p)
	local n = 0
	for _, l in z.Sector.Hatches:GetChildren() do if l.CanCollide == false then n += 1 end end
	return n
end
do
	local rc = centre(relay)
	hrp.CFrame = CFrame.new(rc + Vector3.new(0, 2.51, 0)) -- a teleport claim straight into the relay module
	bot:waitSeconds(0.1)
	eq(debugOf(plr):GetAttribute("TrustedCell"), dock, "a teleport claim does not move the trusted module")
	eq(count(builtModules(plr)), 1, "and builds nothing")
	eq(hatchesOpen(plr), 0, "and opens no hatch")
	eq(bot:state().spliced, false, "and splices nothing")
	-- the salvage floating next to the dock (sector 1), claimed from where it floats
	local salv = tonumber(string.match(debugOf(plr):GetAttribute("SalvageCells"), "^(%d+)"))
	local sc = centre(salv)
	hrp.CFrame = CFrame.new(sc + Vector3.new(0, 4, 0))
	bot:waitSeconds(0.3)
	eq(bot:state().carried, 0, "a teleport claim onto an unopened module's salvage picks nothing up")
	local dc = centre(dock)
	hrp.CFrame = CFrame.new(dc + Vector3.new(0, 2.51, 0))
	bot:waitSeconds(3.5) -- the trust walks back (nothing to walk: it never left) and banks its burst
	eq(debugOf(plr):GetAttribute("TrustedCell"), dock, "back in the dock")
end

--=========================================================================== G. AIR on the virtual clock
section("G. AIR drains in vacuum on the virtual clock, refills in air")
-- the onboarding salvage: the one in a module the dock has a DOORWAY to (Station.plan puts it there, and makes every
-- such module vacuum). A second piece may sit anywhere, air included, and may be next to the dock with no doorway:
-- picking that one was REVIEW-1's flake (2 of 60 runs: the bot "crossed" a wall, no hatch opened, G-H cascaded).
local salvCell
local dockLamps = bot:modules()[dock].lamps
for c in string.gmatch(debugOf(plr):GetAttribute("SalvageCells"), "%d+") do
	local id = tonumber(c)
	local ax, ay, bx, by = (id - 1) % N, (id - 1) // N, (dock - 1) % N, (dock - 1) // N
	if math.abs(ax - bx) + math.abs(ay - by) == 1 and dockLamps[id] ~= nil then salvCell = id end
end
truthy(salvCell ~= nil, "sector 1 has a salvage piece behind one of the dock's hatches")
local airMap = debugOf(plr):GetAttribute("AirMap")
eq(string.sub(airMap, salvCell, salvCell), "0", "sector 1's first salvage floats in a vacuum module")
local vacModule = salvCell
local mods = bot:modules()
truthy(bot:cross(mods, dock, vacModule, "sector"), "walk through the hatch into the vacuum module")
bot:waitSeconds(0.3)
do
	eq(bot:state().moduleType, "vacuum", "the State says vacuum")
	eq(plr.Character.Humanoid.WalkSpeed, 12, "the server set WalkSpeed 12 in vacuum")
	eq(plr.Character.Humanoid.JumpHeight, 1.8, "and JumpHeight 1.8")
	truthy(hatchesOpen(plr) >= 1, "the hatch opened on the approach")
	local a0 = bot:state().air
	bot:waitSeconds(3)
	local a1 = bot:state().air
	truthy(math.abs((a0 - a1) - 3) <= 0.25, string.format("three seconds in vacuum drain 3 s of air (%.2f -> %.2f)", a0, a1))
end

--=========================================================================== H. the blackout
section("H. blackout at the grace: a new dock, half banked, once")
local mods2 = bot:modules()
bot:takeItems(vacModule, mods2)
local carried = bot:state().carried
eq(carried, 5, "picked up the sector-1 salvage (value(1) = 5)")
local wallet0 = bot:state().salvage
local attempt0 = debugOf(plr):GetAttribute("AttemptId")
local hyp, black = nil, nil
for _ = 1, 400 do
	bot:tick()
	local n = bot.notices[#bot.notices]
	if not hyp and bot:saw("hypoxic") then hyp = bot.stats.seconds end
	if bot:saw("blackout") then black = bot.stats.seconds break end
end
truthy(hyp ~= nil and black ~= nil, "the player went hypoxic, then blacked out")
bot:waitSeconds(0.3) -- the next State push (5 Hz) carries the beat
if hyp and black then
	truthy(math.abs((black - hyp) - 5) <= 0.25, string.format("the blackout came %.2f s after the air ran out (grace 5)", black - hyp))
end
local bo = bot:saw("blackout")
eq(bo and bo.data.kept, 2, "kept floor(5 / 2) = 2")
eq(bo and bo.data.of, 5, "of 5 carried")
eq(bot:state().salvage, wallet0 + 2, "banked into the wallet at once")
eq(bot:state().phase, "blackout", "the beat")
eq(plr.Character.Humanoid.Health, 100, "the Humanoid does not die")
truthy(bot:waitPhase("sector", 4), "after the beat the player wakes in a sector")
local dbg2 = debugOf(plr)
truthy(dbg2:GetAttribute("AttemptId") ~= attempt0, "a NEW attempt (fresh entropy)")
eq(dbg2:GetAttribute("Sector"), 1, "the same sector number")
eq(dbg2:GetAttribute("TrustedCell"), dbg2:GetAttribute("DockCell"), "in its new dock")
eq(count(builtModules(plr)), 1, "rebuilt from scratch: one module")
eq(bot:state().carried, 0, "nothing carried")
eq(bot:state().air, 20, "a full tank")
bot:waitSeconds(1)
eq(bot:state().salvage, wallet0 + 2, "and paid only once")

--=========================================================================== I. the splice
section("I. the splice banks, advances best, lights the sector; the floor hatch")
local w1 = bot:state().salvage
local r = bot:playSector(300)
eq(r, "spliced", "the sector is spliced")
local sp
for i = #bot.notices, 1, -1 do if bot.notices[i].kind == "spliced" then sp = bot.notices[i].data break end end
local st = bot:state()
eq(st.salvage, w1 + (sp and sp.carried or 0) + 10, "banked carried + bonus(1) = 10")
eq(st.best, 1, "relays restored: 1")
eq(plr.leaderstats.Relays.Value, 1, "leaderstats.Relays = 1")
bot:waitSeconds(1.5)
do
	local lit, total = 0, 0
	for _, m in builtModules(plr) do
		local fx = m:FindFirstChild("Fixture")
		local l = fx and fx:FindFirstChild("ModuleLight")
		total += 1
		if l and l.Brightness == 2.2 then lit += 1 end
	end
	eq(lit, total, "every built module's light is at full (" .. lit .. "/" .. total .. ")")
	eq(MASTS(), 1, "one relay mast, in the built relay module")
	local relayMod = builtModules(plr)[debugOf(plr):GetAttribute("RelayCell")]
	truthy(relayMod and relayMod:FindFirstChild("FloorHatch") ~= nil, "the floor hatch opened")
	truthy(relayMod and relayMod:FindFirstChild("RelayConsole") ~= nil, "the console woke up")
	local rec = profileStore:GetAsync("u_501")
	eq(rec and rec.data.best, 1, "the splice wrote the profile (best 1)")
	eq(rec and rec.data.open, nil, "with the sector closed in the same write")
end
truthy(bot:toRelayPiece("FloorHatch"), "the floor hatch")
truthy(bot:waitPhase("sector", 5), "drops into sector 2")
eq(bot:state().k, 2, "sector 2")

--=========================================================================== J. purchases
section("J. purchases: refused with reasons, rolled back when the write fails")
local buyer = h:join("Buyer", 7001)
local bchar = h.Players:simulateSpawn(buyer, W)
local bbot = Bot.new(h, buyer, {})
bbot:waitSeconds(1)
eq(bbot:state().salvage, 500, "set-up: the buyer loaded 500 salvage")
local function lastToast(b)
	return b.toasts[#b.toasts]
end
remotes.BuyUpgrade:simulateFireServer(buyer, "tank")
bbot:waitSeconds(0.6)
eq(lastToast(bbot), "Stand at a fabricator to buy upgrades.", "away from a fabricator: refused, with the reason")
eq(bbot:state().salvage, 500, "nothing spent")
bbot:walkTo(Vector3.new(boat.Fabricator.Position.X, 0, boat.Fabricator.Position.Z + 3), "hub")
remotes.BuyUpgrade:simulateFireServer(buyer, 42)
bbot:waitSeconds(0.6)
eq(lastToast(bbot), "That upgrade does not exist.", "a nonsense argument: refused, with the reason")
profileStore.__failNext = true
remotes.BuyUpgrade:simulateFireServer(buyer, "tank")
bbot:waitSeconds(0.6)
eq(lastToast(bbot), "Couldn't reach the save server — nothing was spent.", "the write fails: refused and said so")
eq(bbot:state().salvage, 500, "rolled back: 500")
eq(bbot:state().up.tank, 0, "rolled back: rank 0")
remotes.BuyUpgrade:simulateFireServer(buyer, "tank")
bbot:waitSeconds(0.6)
eq(bbot:state().up.tank, 1, "the retry buys rank 1")
eq(bbot:state().salvage, 380, "for 120")
eq(profileStore:GetAsync("u_7001").data.up.tank, 1, "and it is in the store")
remotes.BuyUpgrade:simulateFireServer(buyer, "boots")
remotes.BuyUpgrade:simulateFireServer(buyer, "boots")
bbot:waitSeconds(0.6)
eq(bbot:state().up.boots, 1, "two requests inside 0.5 s buy once")
eq(lastToast(bbot), "One moment…", "the second one is told why")

--=========================================================================== K. a reset settles once, respawns on HubSpawn
section("K. TakeDamage in a sector: one settlement, HubSpawn")
do
	truthy(bbot:board(), "the buyer boards")
	truthy(bbot:waitPhase("sector", 5), "and arrives in sector 5")
	local r2 = bbot:playSector(15) -- a little exploring; some salvage perhaps
	local c0 = bbot:state().carried or 0
	local w0 = bbot:state().salvage
	local hum = buyer.Character:FindFirstChildOfClass("Humanoid")
	hum:TakeDamage(200)
	bbot:waitSeconds(0.5)
	eq(bbot:state().phase, "hub", "the reset ends the sector")
	eq(bbot:state().salvage, w0 + c0 // 2, string.format("and banks floor(%d / 2)", c0))
	local c2 = h.Players:simulateSpawn(buyer, W)
	bbot:waitSeconds(0.5)
	local p = c2.HumanoidRootPart.Position
	truthy(math.abs(p.X - hubSpawn.Position.X) <= 3 and math.abs(p.Z - hubSpawn.Position.Z) <= 3, "the respawn lands on HubSpawn")
	eq(bbot:state().salvage, w0 + c0 // 2, "the new character settles nothing again (idempotent)")
	local _ = r2
end

--=========================================================================== L. an open sector settles once on rejoin
section("L. a crashed server's open sector settles once, on the next load")
do
	local c = h:join("Crash", 7002)
	h.Players:simulateSpawn(c, W)
	local cb = Bot.new(h, c, {})
	cb:waitSeconds(1)
	eq(cb:state().salvage, 10 + 20, "the load banks floor(41 / 2) = 20 before anything else")
	truthy(string.find(cb.toasts[1] or "", "you kept 20 salvage", 1, true) ~= nil, "and says so (" .. tostring(cb.toasts[1]) .. ")")
	eq(profileStore:GetAsync("u_7002").data.open, nil, "the stored profile is closed")
	h:leave(c)
	h:advance(1)
	local c2 = h:join("Crash", 7002)
	h.Players:simulateSpawn(c2, W)
	local cb2 = Bot.new(h, c2, {})
	cb2:waitSeconds(1)
	eq(cb2:state().salvage, 30, "a second load pays nothing more")
	h:leave(c2)
end

--=========================================================================== L2. a file open elsewhere
section("L2. a file open on another server: read-only, the LIFT says why")
do
	local o = h:join("Other", 7003)
	h.Players:simulateSpawn(o, W)
	local ob = Bot.new(h, o, {})
	ob:waitSeconds(1)
	truthy(table.find(ob.toasts, "Your file is open on another server — retrying.") ~= nil, "the join says the file is open elsewhere")
	ob:walkTo(Vector3.new(boat.Lift.LiftPad.Position.X, 0, 0), "hub")
	ob:waitSeconds(1.5)
	eq(ob:phase(), "hub", "the LIFT does not start a sector")
	eq(ob.toasts[#ob.toasts], "Your file is open on another server — retrying.", "and says why")
	h:leave(o)
end

--=========================================================================== L3. after the splice
section("L3. after the splice: leftover salvage is never a silent +0, and a blackout wakes in the NEXT sector")
do
	-- skipItems leaves sector 1's salvage floating, but a route that runs through a salvage module still picks it up
	-- (REVIEW-1: 3 of 60 runs splice with none left, and the set-up failed). A fresh player tries again, at most 5 times.
	local post, pb
	local spliced, tries = 0, 0
	for attempt = 1, 5 do
		tries = attempt
		local p = h:join("Post" .. attempt, 7005 + (attempt - 1) * 100)
		h.Players:simulateSpawn(p, W)
		local b = Bot.new(h, p, {})
		b:waitSeconds(1)
		if b:board() and b:waitPhase("sector", 5) then
			b.skipItems = true
			local r = b:playSector(300)
			b.skipItems = false
			local picked = 0
			for _, n in b.notices do if n.kind == "salvage" then picked += 1 end end
			local pieces = 0
			for _ in string.gmatch(debugOf(p):GetAttribute("SalvageCells") or "", "%d+") do pieces += 1 end
			if r == "spliced" then spliced += 1 end
			if r == "spliced" and picked < pieces then
				post, pb = p, b
				break
			end
		end
		h:leave(p)
		b:waitSeconds(0.5)
	end
	truthy(pb ~= nil, string.format("a fresh player boards, splices relay 1 and leaves salvage floating (%d of %d tries spliced)", spliced, tries))
	if pb then -- the rest of L3 needs the set-up; its absence is already a failure above
		local splicedAt = #pb.notices
		local wallet = pb:state().salvage
		-- open every module that is left (the leftover salvage floats in some of them), picking up what it can
		local res = pb:exploreAll(300)
		truthy(res == "done" or res == "blackout", "the spliced sector explored (" .. tostring(res) .. ")")
		-- walk up to a leftover piece if one still floats in a built module: it must stay, and the player be told why
		if pb:phase() == "sector" then
			local here, mods = pb:recordHere()
			local holder = nil
			for id, r in mods do
				for _, it in r.items do if it.Name == "Salvage" and it.Parent then holder = id end end
			end
			if holder and here then
				local path = pb:route(mods, pb:hatches(), here, holder)
				if path then
					for i = 2, #path do
						if not pb:cross(mods, path[i - 1], path[i], "sector") then break end
					end
				end
				pb:takeItems(holder, pb:modules())
				-- said once per sector, so it may already have been said while exploring: count from the splice
				local told = false
				for i = splicedAt + 1, #pb.notices do
					local n = pb.notices[i]
					if n.kind == "toast" and string.find(tostring(n.data), "already logged", 1, true) then told = true end
				end
				truthy(told, "reaching a leftover piece after the splice says why it stays")
				local still = false
				for _, it in (pb:modules()[holder] or { items = {} }).items do if it.Name == "Salvage" and it.Parent then still = true end end
				truthy(still, "and the piece stays where it floats")
			else
				truthy(false, "set-up: a leftover salvage piece floats in a built module after the splice")
			end
		end
		local zero, after = 0, 0
		for i = splicedAt + 1, #pb.notices do
			local n = pb.notices[i]
			if n.kind == "salvage" then
				after += 1
				if (n.data and n.data.value or 0) <= 0 then zero += 1 end
			end
		end
		eq(after, 0, "no salvage is picked up after the splice: no '+0' (" .. zero .. " of them worth 0)")
		eq(pb:state().carried or 0, 0, "nothing is carried in a spliced sector")
		-- now stay in vacuum until the air runs out
		if pb:phase() == "sector" then
			local here, mods = pb:recordHere()
			-- a vacuum module, read the way a player reads it: the red lamp over a hatch says VACUUM behind it
			local target = nil
			for _, r in mods do
				for nb, lamp in r.lamps do if lamp == "VACUUM" and mods[nb] then target = nb end end
			end
			truthy(target ~= nil, "the spliced sector has a vacuum module to wander into")
			if target and here then
				local path = pb:route(mods, pb:hatches(), here, target)
				if path then
					for i = 2, #path do
						if not pb:cross(mods, path[i - 1], path[i], "sector") then break end
					end
				end
				for _ = 1, 600 do
					if pb:phase() ~= "sector" then break end
					pb:tick()
				end
			end
		end
		eq(pb:phase(), "blackout", "the air ran out in the spliced sector")
		truthy(pb:waitPhase("sector", 5), "after the beat the player wakes in a sector")
		eq(pb:state().k, 2, "in sector 2 (best + 1), not the relay already spliced")
		eq(debugOf(post):GetAttribute("Sector"), 2, "the server agrees: sector 2")
		eq(pb:state().best, 1, "relays restored still 1")
		eq(pb:state().salvage, wallet, "the blackout banked nothing: nothing was carried")
		h:leave(post)
	end
end

--=========================================================================== L4. the dock's RETURN console
section("L4. the dock's RETURN console: refused from too far, then home with half of what was carried")
do
	local rp = h:join("Returner", 7006)
	h.Players:simulateSpawn(rp, W)
	local rb = Bot.new(h, rp, {})
	rb:waitSeconds(1)
	truthy(rb:board(), "a fresh player boards")
	truthy(rb:waitPhase("sector", 5), "and arrives in sector 1's dock")
	local mods = rb:modules()
	local dockId, salvageId
	for id, r in mods do if r.folder:FindFirstChild("ReturnConsole") then dockId = id end end
	truthy(dockId ~= nil, "the dock has a RETURN console")
	-- the onboarding salvage floats in a module next to the dock: fetch it, come back
	for nb, lamp in (dockId and mods[dockId].lamps or {}) do
		local _ = lamp
		local d = debugOf(rp)
		for c in string.gmatch(d:GetAttribute("SalvageCells"), "%d+") do if tonumber(c) == nb then salvageId = nb end end
	end
	truthy(salvageId ~= nil, "set-up: a salvage piece next to the dock")
	if dockId and salvageId then
		rb:cross(mods, dockId, salvageId, "sector")
		rb:takeItems(salvageId, rb:modules())
		rb:cross(rb:modules(), salvageId, dockId, "sector")
	end
	local carried = rb:state().carried or 0
	eq(carried, 5, "carrying the piece (value(1) = 5) back in the dock")
	local console = dockId and rb:modules()[dockId].folder.ReturnConsole
	local pr = console and console:FindFirstChild("ReturnPrompt")
	truthy(pr ~= nil and pr.HoldDuration == 0 and #pr.ActionText > 0, "the RETURN prompt is a tap and says what it does")
	if pr then
		local dc = rb:modules()[dockId].center
		rb:walkTo(Vector3.new(dc.X, 0, dc.Z), "sector")
		rb:waitSeconds(0.3)
		local flat = Vector3.new(console.Position.X - dc.X, 0, console.Position.Z - dc.Z).Magnitude
		pr.Triggered:Fire(rp)
		rb:waitSeconds(0.3)
		eq(rb.toasts[#rb.toasts], "Step closer to the RETURN console.", string.format("from the dock's centre (%.1f studs away) it is refused, with the reason", flat))
		eq(rb:phase(), "sector", "and nothing happens")
		local p = console.Position
		local toward = Vector3.new(dc.X - p.X, 0, dc.Z - p.Z).Unit
		rb:walkTo(Vector3.new(p.X + toward.X * 3, 0, p.Z + toward.Z * 3), "sector")
		rb:waitSeconds(0.3)
		local wallet = rb:state().salvage
		pr.Triggered:Fire(rp)
		rb:waitSeconds(0.3)
		local n = rb:saw("returning")
		truthy(n ~= nil and n.data.unspliced == true, "standing at it, RETURN works")
		eq(n and n.data.paid, 2, "and banks floor(5 / 2) = 2, the same as a blackout")
		eq(rb:state().salvage, wallet + 2, "into the wallet")
		truthy(rb:waitPhase("hub", 5), "the ride ends in the lifeboat")
		local home = rb:pos()
		local arr = boat.HubArrival.Position
		truthy(math.abs(home.X - arr.X) < 4 and math.abs(home.Z - arr.Z) < 4, "on HubArrival")
		eq(rb:state().carried or 0, 0, "carrying nothing")
		rb:waitSeconds(1)
		eq(rb:state().salvage, wallet + 2, "and it was paid once")
	end
	h:leave(rp)
end

--=========================================================================== M. part caps on built folders
section("M. at most 20 Parts per module and 900 per zone, counted from the built folders")
local worstModule, worstZone, modulesSeen = 0, 0, 0
local function measure(p)
	local z = zoneOf(p)
	if not z then return end
	local zoneParts = 0
	for _, d in z:GetDescendants() do if d:IsA("BasePart") then zoneParts += 1 end end
	worstZone = math.max(worstZone, zoneParts)
	for _, m in builtModules(p) do
		local n = 0
		for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
		worstModule = math.max(worstModule, n)
		modulesSeen += 1
	end
end
do
	-- a 6x6 sector (the Array Spine), every module opened by a walker with every upgrade
	local deep = h:join("Deep", 7004)
	h.Players:simulateSpawn(deep, W)
	local db = Bot.new(h, deep, { onTick = function(self) measure(deep) end })
	db:waitSeconds(1)
	truthy(db:board(), "the deep walker boards")
	truthy(db:waitPhase("sector", 5), "and arrives")
	eq(db:state().k, 23, "in sector 23 (6x6)")
	local opened = db:exploreAll(900)
	local z = zoneOf(deep)
	local nMods = count(builtModules(deep))
	print(string.format("   explored: %d of 36 modules built, zone %d Parts at most, worst module %d", nMods, worstZone, worstModule))
	truthy(nMods >= 30, "most of the 6x6 sector was opened (" .. nMods .. ")")
	local _ = opened
	local _z = z
end
measure(plr)
truthy(worstModule <= 20, "no built module ever held more than 20 Parts (worst " .. worstModule .. " over " .. modulesSeen .. " module samples)")
truthy(worstZone <= 900, "no zone ever held more than 900 Parts (worst " .. worstZone .. ")")

--=========================================================================== N. glyphs
section("N. every glyph is one photographed rendering in Studio")
do
	local SEEN = { [0x2014] = true, [0x2026] = true, [0x2605] = true }
	local unseen = {}
	local function inspect(s, where)
		if type(s) ~= "string" then return end
		for _, cp in utf8.codes(s) do
			if cp >= 0x2000 and not SEEN[cp] then table.insert(unseen, string.format("U+%X in %s", cp, where)) end
		end
	end
	local n = 0
	for _, root in { W, plr.PlayerGui } do
		for _, d in root:GetDescendants() do
			if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then inspect(d.Text, d:GetFullName()); n += 1 end
			if d.ClassName == "ProximityPrompt" then inspect(d.ActionText, d:GetFullName()); inspect(d.ObjectText, d:GetFullName()); n += 1 end
		end
	end
	for _, rec in remotes.Notice:getSent() do
		if rec.args[1] == "toast" then inspect(rec.args[2], "toast"); n += 1 end
	end
	eq(#unseen, 0, "every one of " .. n .. " strings uses only photographed glyphs (" .. table.concat(unseen, "; ") .. ")")
end

--=========================================================================== done
print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings")
print(string.format("signal-lost: %d passed, %d failed", passed, failed))
if failed > 0 then error("signal-lost check failed", 0) end
