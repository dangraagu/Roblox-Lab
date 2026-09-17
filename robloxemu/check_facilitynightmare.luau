-- FACILITY: Endless Nightmare — the world has to be BUILT and PARENTED, a joining character has to
-- LAND where the engine will put it, and the loop has to be playable from join to a second run.
--
-- Run:  py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       luau check_facilitynightmare.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Written from DESIGN.md §14's check list BEFORE the server existed. Every player below plays
-- through tests/Bot.luau, which moves the root part at the server's WalkSpeed one server tick at a
-- time and knows only what a client could know (the workspace and its own State/Notice). The
-- oracle for what the floor SHOULD be is ServerStorage.FacilityDebug — test-only data that never
-- replicates, and which section H proves never reaches Workspace or ReplicatedStorage.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")

local h = Harness.new({
	bundle = require("./build/facility-nightmare"),
	name = "facility-nightmare",
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
local function near(a, b, tol, msg)
	if type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b) .. " +- " .. tostring(tol))
	end
end
local function section(name) print("== " .. name) end

-- Written out, not read from Config: a number checked against itself is not a check.
local CELL, LEAD, RIDE, BEAT, GRACE, BOARD = 28, 2, 4, 2.5, 4, 1.5
local SPACING = 400

local VET, TESTER, NEWBIE, SHOPPER, CRASHED, CLOSER = 7001, 7002, 7003, 7004, 7005, 7006
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
local function profile(extra)
	local p = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 0, runs = 1, extractions = 0,
		perks = { deepCell = 0, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } }
	for k, v in extra or {} do p[k] = v end
	return { data = p }
end
-- VET carries Deep Cell 3 (75 s of battery; a possible profile after one deep run: 220 banked).
-- Sections D and E need the bot to clear sublevel 1 twice, and without it a 16 studs/s bot died
-- on sublevel 1 on 3 of 11 000 probe floors, and this file failed on it twice in about 1 370
-- runs. Nothing VET is used to check depends on the battery's size.
store:SetAsync("u_" .. VET, profile({ essenceEarned = 220,
	perks = { deepCell = 3, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } }))
-- TESTER is on a first-ever run (runs 0): the front is HELD until a fuse, so the trust tests in
-- section F cannot be cut short by the dark.
store:SetAsync("u_" .. TESTER, profile({ runs = 0 }))
store:SetAsync("u_" .. SHOPPER, profile({ essence = 30, runs = 3 }))
store:SetAsync("u_" .. CRASHED, profile({ essence = 5, runs = 2,
	openRun = { id = "crashed-run", sublevel = 3, runEssence = 45, keepPercent = 35 } }))
store:SetAsync("u_" .. CLOSER, profile())
-- NEWBIE has no record at all: a first-ever player.

local function stored(uid)
	local rec = store:GetAsync("u_" .. uid)
	return rec and rec.data
end

--=========================================================================== A. boot
section("A. the server boots and builds the hub")

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "server/Main.server loads (" .. tostring(bootErr) .. ")")
if not okBoot then
	print(string.format("check_facilitynightmare: %d passed, %d failed", passed, failed + 1))
	return
end
h:advance(1)

do -- visuals from the first build
	local amb = h.Lighting.Ambient
	truthy(amb ~= nil and amb.R * 255 <= 6 and amb.G * 255 <= 6 and amb.B * 255 <= 8,
		"Lighting uses the Facility preset: an unlit room reads DARK (ambient " .. tostring(amb) .. ")")
	truthy(h.Lighting:FindFirstChild("FxAtmosphere") ~= nil, "…with its Atmosphere")
end

local hub = h.workspace:FindFirstChild("Hub")
truthy(hub ~= nil, "workspace.Hub exists")
local hubSpawn = hub and hub:FindFirstChild("HubSpawn")
local hubArrival = hub and hub:FindFirstChild("HubArrival")
truthy(hubSpawn ~= nil and hubSpawn.ClassName == "SpawnLocation", "Hub.HubSpawn is a SpawnLocation")
truthy(hubSpawn and hubSpawn.Enabled == true, "…Enabled")
eq(hubSpawn and hubSpawn.Duration, 0, "…with Duration 0 (no ForceField)")
eq(hubSpawn and hubSpawn:IsDescendantOf(h.workspace), true, "…and parented into the Workspace")
truthy(hubArrival ~= nil and hubArrival:IsA("BasePart") and hubArrival.ClassName ~= "SpawnLocation", "Hub.HubArrival is a plain Part")

do
	local enabled = {}
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then table.insert(enabled, d:GetFullName()) end
	end
	eq(#enabled, 1, "HubSpawn is the ONLY enabled SpawnLocation (" .. table.concat(enabled, ", ") .. ")")
end

local remotes = h.ReplicatedStorage:FindFirstChild("FacilityRemotes")
truthy(remotes ~= nil, "ReplicatedStorage.FacilityRemotes exists")
for _, name in { "State", "Notice", "Flashlight", "Sprint", "Choose", "BuyPerk" } do
	truthy(remotes and remotes:FindFirstChild(name) ~= nil and remotes:FindFirstChild(name).ClassName == "RemoteEvent",
		"remote " .. name)
end
local StateR, NoticeR = remotes:FindFirstChild("State"), remotes:FindFirstChild("Notice")

do -- the hub is a sealed room with a roof, which is exactly why the spawn must be a SpawnLocation
	local roofOverOrigin = false
	for _, d in hub:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide ~= false and d.Position.Y > 8
			and math.abs(d.Position.X) <= d.Size.X / 2 and math.abs(d.Position.Z) <= d.Size.Z / 2 then
			roofOverOrigin = true
		end
	end
	truthy(roofOverOrigin, "control: the hub HAS a roof over the origin (without a SpawnLocation you would land on it)")
end

--=========================================================================== B. spawning
section("B. a joining character lands on HubSpawn under the engine's spawn order")

local vet = h:join("Vet", VET)
h:advance(0.5)
eq(vet.RespawnLocation, hubSpawn, "PlayerAdded points RespawnLocation at HubSpawn before the character loads")
local ls = vet:FindFirstChild("leaderstats")
truthy(ls ~= nil and ls:FindFirstChild("Deepest") ~= nil, "leaderstats.Deepest")

h.Players:simulateSpawn(vet, h.workspace)
local function hrpOf(plr)
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end
do
	local r = hrpOf(vet)
	truthy(r ~= nil, "the character spawned")
	local top = hubSpawn.Position.Y + hubSpawn.Size.Y / 2
	near(r.Position.X, hubSpawn.Position.X, 0.01, "landed over HubSpawn in X")
	near(r.Position.Z, hubSpawn.Position.Z, 0.01, "…and in Z")
	truthy(r.Position.Y > top and r.Position.Y < top + 5, "…standing on it (y " .. string.format("%.2f", r.Position.Y) .. ")")
	h:advance(1)
	near(r.Position.X, hubSpawn.Position.X, 0.01, "…and still there a second later (nothing races the engine)")
	local hum = vet.Character:FindFirstChildOfClass("Humanoid")
	eq(hum.WalkSpeed, 16, "the server assigned WalkSpeed 16")
	print(string.format("  landed at %.2f, %.2f, %.2f", r.Position.X, r.Position.Y, r.Position.Z))
end

--=========================================================================== C. reachability
section("C. every prompt and the elevator are reachable")

do
	local term = hub:FindFirstChild("PerkTerminal")
	local prompt = term and term:FindFirstChildOfClass("ProximityPrompt")
	truthy(prompt ~= nil and prompt.Enabled ~= false, "the perk terminal carries an enabled ProximityPrompt")
	if prompt then
		-- the nearest standable point inside the hub, 3 studs off the wall the terminal hangs on
		local halfZ = hub:FindFirstChild("HubFloor").Size.Z / 2
		local stand = Vector3.new(term.Position.X, 3, math.sign(term.Position.Z) * (halfZ - 3))
		local d = (stand - term.Position).Magnitude
		truthy(d <= prompt.MaxActivationDistance, string.format("the prompt reaches a player standing in the hub (%.1f <= %d)", d, prompt.MaxActivationDistance))
		eq(prompt.RequiresLineOfSight, false, "…with no line-of-sight test to fail on a wall-mounted part")
		NoticeR:clearSent()
		prompt.Triggered:Fire(vet)
		local sent = NoticeR:sentTo(vet)
		eq(sent[1] and sent[1].args[1], "perks", "triggering it opens the perk panel for that player")
	end
	local car = hub:FindFirstChild("HubCar")
	local plate = car and car:FindFirstChild("CarFloor")
	truthy(plate ~= nil, "the hub car has a floor")
	if plate then
		local from = hubSpawn.Position
		local to = plate.Position
		local blocked = {}
		for _, p in hub:GetDescendants() do
			if p:IsA("BasePart") and p.CanCollide ~= false and p ~= plate and p ~= hubSpawn and p.Name ~= "HubFloor"
				and p.Position.Y - p.Size.Y / 2 < 5 then
				-- does the walk line (y = 3) pass through this box?
				local hit = false
				for i = 0, 40 do
					local q = from:Lerp(to, i / 40)
					if math.abs(q.X - p.Position.X) < p.Size.X / 2 and math.abs(q.Z - p.Position.Z) < p.Size.Z / 2 then hit = true end
				end
				if hit then table.insert(blocked, p.Name) end
			end
		end
		eq(#blocked, 0, "nothing solid stands between the spawn and the car (" .. table.concat(blocked, ",") .. ")")
		near((to - from).Magnitude, 16, 0.5, "the car is 16 studs from the spawn (1 s at walk)")
	end
end

--=========================================================================== D. a whole run
section("D. join -> car -> sublevel 1 -> extract (VET, runs = 1)")

local vetBot = Bot.new(h, vet)
local function debugOf(uid)
	local ss = h.services.game:GetService("ServerStorage")
	local root = ss:FindFirstChild("FacilityDebug")
	return root and root:FindFirstChild("Run_" .. uid)
end
local function zoneOf(uid)
	local dbg = debugOf(uid)
	local idx = dbg and dbg:GetAttribute("ZoneIndex")
	local fac = h.workspace:FindFirstChild("Facility")
	return fac and idx and fac:FindFirstChild("Zone_" .. idx), idx
end
local function cellCenterWorld(uid, cell)
	local dbg = debugOf(uid)
	local n = dbg:GetAttribute("Grid")
	local idx = dbg:GetAttribute("ZoneIndex")
	local cx = (cell - 1) % n
	local cy = (cell - 1 - cx) / n
	return Vector3.new(SPACING * idx + (cx - (n - 1) / 2) * CELL, 0, (cy - (n - 1) / 2) * CELL)
end

local tBoard0 = h.scheduler:now()
truthy(vetBot:board(hub), "walking into the car starts a run")
local boardSeconds = h.scheduler:now() - tBoard0
print(string.format("  spawn -> ride started: %.1f s (walk 16 studs + %.1f s boarding)", boardSeconds, BOARD))
truthy(boardSeconds <= 5, "the core action lands inside 5 seconds of standing on the spawn")

do
	local zone, idx = zoneOf(VET)
	truthy(zone ~= nil, "the run has a zone, workspace.Facility.Zone_" .. tostring(idx))
	local r = hrpOf(vet)
	near(r.Position.X, SPACING * (idx or 0), 6, "the character rides in its own zone's ride car")
	local rooms = zone and zone:FindFirstChild("Floor") and zone.Floor:FindFirstChild("Rooms")
	eq(rooms and #rooms:GetChildren(), 1, "during the ride only the entry room exists")
end

local tRide = h.scheduler:now()
truthy(vetBot:waitPhase("floor", RIDE + 1), "the ride ends on sublevel 1")
near(h.scheduler:now() - tRide, RIDE, 0.35, "the ride lasts RideSeconds")

do
	local dbg = debugOf(VET)
	truthy(dbg ~= nil, "ServerStorage.FacilityDebug.Run_<uid> exists (control for section H)")
	local entry = dbg:GetAttribute("EntryCell")
	local c = cellCenterWorld(VET, entry)
	local r = hrpOf(vet)
	near(r.Position.X, c.X, 1, "the car doors open in the entry room (X)")
	near(r.Position.Z, c.Z, 1, "…(Z)")
	local zone = zoneOf(VET)
	local floor = zone.Floor
	local roomList = floor.Rooms:GetChildren()
	eq(#roomList, 1, "on arrival only ONE room is built")
	eq(roomList[1] and roomList[1].Name, "Room_" .. entry, "…the entry")
	local leaves = floor.Doors:GetChildren()
	truthy(#leaves >= 1, "the entry has at least one door leaf")
	local allClosed, allEntry = true, true
	for _, l in leaves do
		if l.CanCollide == false then allClosed = false end
		local lo, hi = string.match(l.Name, "^Door_(%d+)_(%d+)$")
		if tonumber(lo) ~= entry and tonumber(hi) ~= entry then allEntry = false end
	end
	truthy(allClosed, "every door into an unbuilt room is present and CLOSED (never a hole into the void)")
	truthy(allEntry, "every leaf belongs to a doorway of the entry")
	eq(#floor.EntryCar:GetChildren(), 6, "the entry car is 6 Parts")
	eq(floor:FindFirstChild("ExitLift"), nil, "the exit lift does not exist before its room is opened")
	eq(dbg:GetAttribute("HoldSeconds"), 0, "a veteran's front is not held")
end

local runStats = {}
local result1 = vetBot:clearFloor()
eq(result1, "powered", "the bot clears sublevel 1 and powers the elevator")
local st = vetBot:state()
eq(st.run.runEssence, 10, "powering sublevel 1 pays 10 into the run")
do
	local choice
	for _, n in vetBot.notices do if n.kind == "choice" then choice = n.data end end
	truthy(choice ~= nil and choice.bank == 10 and choice.nextPay == 15 and choice.keepPercent == 25,
		"the choice panel offers bank 10 / next pays 15 / keep 25%")
	eq(stored(VET).openRun and stored(VET).openRun.runEssence, 10, "the checkpoint is written at powering")
	eq(stored(VET).bestSublevel, 1, "…with bestSublevel 1")
	eq(vet.leaderstats.Deepest.Value, 1, "leaderstats.Deepest = 1")
	-- counted from the SERVER's notices: the bot's own counters miss an item walked over on the way
	-- to something else (this line printed "0 fuses" for a powered floor)
	local fuses, cells = 0, 0
	for _, n in vetBot.notices do
		if n.kind == "fuse" then fuses += 1 elseif n.kind == "cell" then cells += 1 end
	end
	table.insert(runStats, string.format("sublevel 1 powered at %.1f s on the bot clock (car and ride included), %d doors, %d fuses, %d cells, %.1f s in dark rooms, light on %.1f s",
		vetBot.stats.seconds, vetBot.stats.doorsOpened, fuses, cells, vetBot.stats.darkSeconds, vetBot.stats.lightSeconds))
end

do -- CHOOSE is only accepted standing at the elevator. Found missing by the mutation sweep: with
	-- the exit-cell check deleted, every gate stayed green.
	local rooms, doors = vetBot:rooms(), vetBot:doors()
	local exitRoom = vetBot:exitRoom(rooms)
	local nb
	for _, d in doors do
		if d.open and (d.lo == exitRoom or d.hi == exitRoom) then
			local other = if d.lo == exitRoom then d.hi else d.lo
			if rooms[other] then nb = other; break end
		end
	end
	truthy(nb ~= nil, "control: the exit room has an opened neighbour to step into")
	vetBot:cross(rooms, exitRoom, nb)
	vetBot:waitSeconds(0.5)
	local toasts0 = #vetBot.toasts
	local essence0 = stored(VET).essence
	vetBot:fire("Choose", "extract")
	vetBot:waitSeconds(0.3)
	eq(vetBot:phase(), "floor", "EXTRACT from the next room is refused: still on the floor")
	eq(stored(VET).essence, essence0, "…nothing paid")
	eq(#vetBot.toasts - toasts0, 1, "…and the player is told why")
	truthy(string.find(vetBot.toasts[#vetBot.toasts] or "", "freight elevator", 1, true) ~= nil,
		"…'" .. tostring(vetBot.toasts[#vetBot.toasts]) .. "'")
	if vetBot:phase() == "floor" then
		vetBot:cross(vetBot:rooms(), nb, exitRoom)
	end
	vetBot:waitSeconds(0.5)
end

do -- H/budget: count what the workspace holds with a floor partly opened
	local zone = zoneOf(VET)
	local worstRoom, rooms = 0, 0
	for _, f in zone.Floor.Rooms:GetChildren() do
		rooms += 1
		local n = 0
		for _, d in f:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
		worstRoom = math.max(worstRoom, n)
	end
	local leaves = #zone.Floor.Doors:GetChildren()
	local total = 0
	for _, d in zone:GetDescendants() do if d:IsA("BasePart") then total += 1 end end
	print(string.format("  zone after sublevel 1: %d rooms built, worst room %d Parts, %d door leaves, %d Parts in the zone", rooms, worstRoom, leaves, total))
	truthy(worstRoom <= 20, "no room holds more than 20 Parts")
	truthy(leaves <= 40, "no floor holds more than 40 door leaves")
	truthy(total <= 600, "the zone holds at most 600 Parts")
	eq(#zone.Floor.ExitLift:GetChildren(), 8, "the exit lift is 8 Parts")
end

do -- which way the world's labels FACE. A SurfaceGui draws on one face only; on the wrong one it
	-- is a blank slab. Axis-aligned parts only (every labelled part here is built unrotated), so a
	-- face's outward normal is fixed: Front is -Z, Back +Z, Left -X, Right +X, Top +Y, Bottom -Y.
	local function normalOf(face)
		if face == Enum.NormalId.Front then return Vector3.new(0, 0, -1)
		elseif face == Enum.NormalId.Back then return Vector3.new(0, 0, 1)
		elseif face == Enum.NormalId.Left then return Vector3.new(-1, 0, 0)
		elseif face == Enum.NormalId.Right then return Vector3.new(1, 0, 0)
		elseif face == Enum.NormalId.Top then return Vector3.new(0, 1, 0)
		end
		return Vector3.new(0, -1, 0)
	end
	local function facing(part, toward)
		local d = Vector3.new(toward.X - part.Position.X, 0, toward.Z - part.Position.Z)
		local toward_, away = {}, {}
		for _, g in part:GetChildren() do
			if g.ClassName == "SurfaceGui" then
				local dot = normalOf(g.Face):Dot(d)
				if dot > 0 then table.insert(toward_, g) elseif dot < 0 then table.insert(away, g) end
			end
		end
		return toward_, away
	end
	-- controls: the hub's two labels already face the player
	local sign = hub.HubCar.CarSign
	local signIn = facing(sign, hubSpawn.Position)
	eq(#signIn, 1, "control: SERVICE ELEVATOR faces the spawn")
	local term = hub.PerkTerminal
	local termIn = facing(term, Vector3.new(0, 0, 0))
	eq(#termIn, 1, "control: the PERKS label faces into the break room")
	-- the fuse panel stands on one edge of an open lift: a player sees it from inside the lift
	-- (where they stand to choose) or from outside, depending on the doorway they came in by
	local zone = zoneOf(VET)
	local lift = zone.Floor.ExitLift
	local inward, outward = facing(lift.FusePanel, lift.LiftPlatform.Position)
	eq(#inward, 1, "the fuse slots face INTO the lift, where the player stands to choose")
	eq(#outward, 1, "…and OUT, toward a player walking up to it")
	local titles = {}
	for _, g in lift.FusePanel:GetChildren() do
		local t = g.ClassName == "SurfaceGui" and g:FindFirstChild("Title")
		if t then table.insert(titles, t.Text) end
	end
	local fuses = debugOf(VET) and #string.split(tostring(debugOf(VET):GetAttribute("FuseCells")), ",")
	local want = "FUSES " .. tostring(fuses) .. "/" .. tostring(fuses)
	local allRight = #titles >= 2
	for _, t in titles do if t ~= want then allRight = false end end
	truthy(allRight, "every face of the panel reads " .. want .. " once powered (" .. table.concat(titles, " | ") .. ")")

	-- A SurfaceGui's canvas is stretched onto its face. A 400x200 canvas on a 7 x 1.6 stud sign
	-- draws every letter 2.2 times too wide; on a 4 x 5 terminal, 2.5 times too tall. Compared
	-- for every SurfaceGui in the world, with a floor built.
	local surfaces, stretched = 0, {}
	for _, g in h.workspace:GetDescendants() do
		if g.ClassName == "SurfaceGui" and g.Parent and g.Parent:IsA("BasePart") then
			surfaces += 1
			local s = g.Parent.Size
			local w, hh
			if g.Face == Enum.NormalId.Left or g.Face == Enum.NormalId.Right then
				w, hh = s.Z, s.Y
			elseif g.Face == Enum.NormalId.Top or g.Face == Enum.NormalId.Bottom then
				w, hh = s.X, s.Z
			else
				w, hh = s.X, s.Y
			end
			local faceAspect = w / hh
			local canvasAspect = g.CanvasSize.X / g.CanvasSize.Y
			local ratio = canvasAspect / faceAspect
			if ratio > 1.05 or ratio < 1 / 1.05 then
				table.insert(stretched, string.format("%s (face %.1fx%.1f, canvas %dx%d: x%.2f)",
					g:GetFullName(), w, hh, g.CanvasSize.X, g.CanvasSize.Y, if ratio >= 1 then ratio else 1 / ratio))
			end
		end
	end
	truthy(surfaces >= 4, "control: " .. surfaces .. " SurfaceGuis in the world (2 hub labels, 2 panel faces)")
	eq(#stretched, 0, "no SurfaceGui canvas is stretched onto its face by more than 5% (" .. table.concat(stretched, "; ") .. ")")
end

do
	local before = stored(VET).essence
	vetBot:fire("Choose", "extract")
	h:advance(0.2)
	eq(stored(VET).essence, before + 10, "EXTRACT pays the whole run, at once")
	eq(stored(VET).openRun, nil, "…and clears the checkpoint in the same write")
	eq(stored(VET).extractions, 1, "…counted as an extraction")
	truthy(vetBot:waitPhase("hub", RIDE + 1), "the ride goes back up to the hub")
	local r = hrpOf(vet)
	near(r.Position.X, hubArrival.Position.X, 1, "…and lands on HubArrival (X)")
	near(r.Position.Z, hubArrival.Position.Z, 1, "…(Z)")
	local zone = zoneOf(VET)
	eq(zone:FindFirstChild("Floor"), nil, "the old floor is gone")
end

--=========================================================================== E. the second loop
section("E. a second run: descend, the front, a death in the dark (VET)")

truthy(vetBot:board(hub), "the second run starts from HubArrival")
truthy(vetBot:waitPhase("floor", RIDE + 1), "sublevel 1 again")
eq(vetBot:clearFloor(), "powered", "sublevel 1 cleared again — a floor that has never existed before")
do
	local s1 = debugOf(VET):GetAttribute("LayoutSeed")
	-- the flashlight is left ON at the exit, the way a player in a hurry would leave it
	-- (the clock is advanced directly: the bot's own tick would switch the light off in a lit room)
	vetBot:fire("Flashlight", true)
	h:advance(0.3)
	do
		local st = vetBot:state()
		local rooms = vetBot:rooms()
		local recent = {}
		for i = math.max(1, #vetBot.toasts - 2), #vetBot.toasts do table.insert(recent, vetBot.toasts[i]) end
		eq(st.run and st.run.lightOn, true, string.format(
			"control: the light is on when DESCEND is chosen (phase %s, battery %s, powered %s, bot in room %s, exit room %s, last toasts: %s)",
			tostring(st.phase), tostring(st.run and st.run.battery), tostring(st.run and st.run.powered),
			tostring(vetBot:roomAt(rooms, vetBot:pos())), tostring(vetBot:exitRoom(rooms)), table.concat(recent, " / ")))
	end
	vetBot:fire("Choose", "descend")
	-- measure the arrival moment on sublevel 2 by watching the character, one tick at a time
	local arrived, tArrive = false, nil
	for _ = 1, 80 do
		h:advance(0.1)
		local dbg = debugOf(VET)
		if dbg:GetAttribute("Sublevel") == 2 then
			local c = cellCenterWorld(VET, dbg:GetAttribute("EntryCell"))
			local r = hrpOf(vet)
			if (Vector3.new(r.Position.X, 0, r.Position.Z) - c).Magnitude < 1 then arrived, tArrive = true, h.scheduler:now(); break end
		end
	end
	truthy(arrived, "DESCEND rides down into sublevel 2's entry car")
	h:advance(0.25)
	eq(vetBot:state().run.lightOn, false, "the flashlight starts OFF on a new sublevel: a light left on at the exit does not drain the battery in the lit entry")
	truthy(debugOf(VET):GetAttribute("LayoutSeed") ~= s1, "sublevel 2 has a fresh layout seed")
	eq(stored(VET).openRun and stored(VET).openRun.runEssence, 10, "the run is still open with 10 in it")

	-- ring 0: flicker, then dark, at LeadSteps * step on the run clock
	local dbg = debugOf(VET)
	local step = dbg:GetAttribute("StepSeconds")
	local zone = zoneOf(VET)
	local entryRoom = zone.Floor.Rooms:FindFirstChild("Room_" .. dbg:GetAttribute("EntryCell"))
	local light = entryRoom.Fixture.RoomLight
	local expected = tArrive + LEAD * step
	local lastB, changes, tDark = light.Brightness, 0, nil
	while h.scheduler:now() < expected + 1 do
		h:advance(0.05)
		if light.Enabled == false then tDark = h.scheduler:now(); break end
		if light.Brightness ~= lastB then changes += 1; lastB = light.Brightness end
	end
	print(string.format("  sublevel 2: step %.2f s, entry dark expected at +%.2f s, observed at +%.2f s, %d flicker changes",
		step, LEAD * step, (tDark or -1) - tArrive, changes))
	near(tDark, expected, 0.25, "ring 0 goes dark at the virtual time the plan says")
	truthy(changes >= 8, "…after a visible flicker (Brightness changed " .. changes .. " times)")
	h:advance(0.25) -- one State push
	eq(vetBot:state().run.dark, true, "the State says the player's room is dark")

	-- H. leaks, mid-run with the dark spreading
	section("H. replication leaks, mid-run")
	local fac = h.workspace:FindFirstChild("Facility")
	local attrs, instances = {}, 0
	for _, z in fac:GetChildren() do
		for k in z:GetAttributes() do table.insert(attrs, z.Name .. "." .. k) end
		for _, d in z:GetDescendants() do
			instances += 1
			for k in d:GetAttributes() do table.insert(attrs, d:GetFullName() .. "@" .. k) end
		end
	end
	truthy(instances > 20, "control: the zones are not empty (" .. instances .. " instances)")
	eq(#attrs, 0, "enumerated attributes under every zone: exactly none (" .. table.concat(attrs, ", ") .. ")")
	local DEBUG_NAMES = { "Sublevel", "LayoutSeed", "LootSeed", "DecorSeed", "EntryCell", "ExitCell", "FuseCells",
		"BatteryCells", "StepSeconds", "HoldSeconds", "ModelSeconds", "ZoneIndex", "Grid", "TrustedCell", "RunClock" }
	local present = 0
	for _, name in DEBUG_NAMES do
		if dbg:GetAttribute(name) ~= nil then present += 1 end
	end
	eq(present, #DEBUG_NAMES, "control: the ServerStorage mirror carries all " .. #DEBUG_NAMES .. " debug attributes")
	local leaked = {}
	for _, root in { h.workspace, h.ReplicatedStorage } do
		for _, d in root:GetDescendants() do
			for _, name in DEBUG_NAMES do
				if d:GetAttribute(name) ~= nil then table.insert(leaked, d:GetFullName() .. "@" .. name) end
			end
		end
	end
	eq(#leaked, 0, "no debug attribute name appears anywhere in Workspace or ReplicatedStorage (" .. table.concat(leaked, ", ") .. ")")
	-- Counted again NOW, with zones, ride cars and a floor built. Section A counted at boot, before
	-- any zone existed, and the mutation sweep showed a stray spawn in a zone sailing past it.
	local enabledNow = {}
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then table.insert(enabledNow, d:GetFullName()) end
	end
	eq(#enabledNow, 1, "mid-run, HubSpawn is still the only enabled SpawnLocation (" .. table.concat(enabledNow, ", ") .. ")")
	-- The State payload, ENUMERATED against the exact key set (fork-tower REVIEW-3: the
	-- enumeration is the test, so a renamed leak still fails; a word blacklist would not).
	local payload = vetBot:state()
	local TOP = { phase = true, loaded = true, saving = true, storeless = true, essence = true, bestSublevel = true,
		runs = true, perks = true, perkRows = true, boarding = true, run = true }
	local RUN = { k = true, fuses = true, fusesIn = true, fusesNeeded = true, battery = true, batteryCap = true,
		exposure = true, stamina = true, staminaCap = true, lightOn = true, sprinting = true, runEssence = true,
		keepPercent = true, dark = true, flicker = true, powered = true, secondWinds = true, atLift = true }
	local PERK_ROW = { id = true, name = true, blurb = true, rank = true, max = true, price = true }
	local bad = {}
	for k in payload do if not TOP[k] then table.insert(bad, tostring(k)) end end
	for k in payload.run or {} do if not RUN[k] then table.insert(bad, "run." .. tostring(k)) end end
	for k in payload.perks or {} do
		if not ({ deepCell = true, nightEyes = true, marathon = true, soulAnchor = true, secondWind = true })[k] then
			table.insert(bad, "perks." .. tostring(k))
		end
	end
	for _, row in payload.perkRows or {} do
		for k in row do if not PERK_ROW[k] then table.insert(bad, "perkRows[]." .. tostring(k)) end end
	end
	truthy(payload.run ~= nil, "control: the payload was taken mid-run")
	eq(#bad, 0, "the State payload holds exactly the expected keys — no cell, seed, exit, step or hold (" .. table.concat(bad, ", ") .. ")")

	-- the dark takes a player who keeps the light off
	section("E2. death at grace, settled at keep")
	vetBot:fire("Flashlight", false)
	local essenceBefore = stored(VET).essence
	local tDead
	for _ = 1, 80 do
		h:advance(0.1)
		if vetBot:phase() == "dying" then tDead = h.scheduler:now(); break end
	end
	truthy(tDead ~= nil, "standing in the dark with the light off, the dark takes you")
	near((tDead or 0) - tDark, GRACE, 0.45, "…at the grace (4 s after the room died, +- one tick and one push)")
	eq(stored(VET).essence, essenceBefore + 2, "the death settles at once: floor(25% of 10) = 2")
	eq(stored(VET).openRun, nil, "…and closes the run")
	local death
	for _, n in vetBot:drainNotices() do if n.kind == "death" then death = n.data end end
	for _, n in vetBot.notices do if n.kind == "death" then death = n.data end end
	truthy(death ~= nil and death.kept == 2 and death.of == 10, "the death card says kept 2 of 10")
	h:advance(BEAT + 0.3)
	local r = hrpOf(vet)
	near(r.Position.X, hubArrival.Position.X, 1, "after the beat the server moves you to HubArrival")
	eq(vetBot:phase(), "hub", "…back in the hub")
	eq(vet.Character:FindFirstChildOfClass("Humanoid").Health > 0, true, "a dark death does NOT kill the Humanoid")
	eq(zone:FindFirstChild("Floor"), nil, "the dead floor is cleaned up")
end

--=========================================================================== F. trust and forged input
section("F. trusted position, doors, forged remotes (TESTER)")

local tester = h:join("Tester", TESTER)
h:advance(0.5)
h.Players:simulateSpawn(tester, h.workspace)
h:advance(0.5)
local tBot = Bot.new(h, tester)
do
	-- stepping out of the car cancels, with a toast
	local car = hub.HubCar.CarFloor.Position
	tBot:walkTo(Vector3.new(car.X, 3, car.Z))
	tBot:waitSeconds(0.8)
	tBot:walkTo(Vector3.new(car.X - 12, 3, car.Z))
	tBot:waitSeconds(0.5)
	local cancelled = false
	for _, t in tBot.toasts do if string.find(string.lower(t), "cancel", 1, true) then cancelled = true end end
	truthy(cancelled, "stepping out of the car mid-boarding cancels with a toast")
	eq(tBot:phase(), "hub", "…and no run starts")
	local before = #tBot.toasts
	tBot:fire("Sprint", true)
	tBot:waitSeconds(0.2)
	eq(#tBot.toasts - before, 1, "asking to sprint in the break room is answered, not silently ignored")
	tBot:fire("Sprint", false)
	tBot:waitSeconds(0.2)
	eq(#tBot.toasts - before, 1, "…and letting go of Shift there says nothing")
end
truthy(tBot:board(hub) and tBot:waitPhase("floor", RIDE + 1), "TESTER reaches sublevel 1")
do
	local dbg = debugOf(TESTER)
	local n, entry = dbg:GetAttribute("Grid"), dbg:GetAttribute("EntryCell")
	local zone, idx = zoneOf(TESTER)
	local _, vetIdx = zoneOf(VET)
	truthy(idx ~= vetIdx, "two players hold two different zones")
	local center = cellCenterWorld(TESTER, entry)
	local hrp = hrpOf(tester)
	local function claim(v)
		hrp.CFrame = CFrame.new(v + Vector3.new(0, 3, 0))
	end
	local ex = (entry - 1) % n
	local ey = (entry - 1 - ex) / n
	local function idAt(dx, dy)
		local x, y = ex + dx, ey + dy
		if x < 0 or y < 0 or x >= n or y >= n then return nil end
		return y * n + x + 1
	end
	local function leaves()
		local out = {}
		for _, l in zone.Floor.Doors:GetChildren() do
			local lo, hi = string.match(l.Name, "^Door_(%d+)_(%d+)$")
			lo, hi = tonumber(lo), tonumber(hi)
			-- once a neighbour is built the folder also holds ITS leaves; only the entry's count here
			if lo == entry then out[hi] = l elseif hi == entry then out[lo] = l end
		end
		return out
	end

	-- (1) A TELEPORT onto a fuse room, with every door shut and a full 3 s burst banked
	-- (3 s x 21.6 = 64.8 studs). For that tick a closed door is a wall, burst or not.
	tBot:waitSeconds(3)
	local allShut = true
	for _, l in leaves() do if l.CanCollide == false then allShut = false end end
	truthy(allShut, "control: every entry door is shut before the teleport")
	local fuses = string.split(tostring(dbg:GetAttribute("FuseCells")), ",")
	claim(cellCenterWorld(TESTER, tonumber(fuses[#fuses])))
	h:advance(0.1)
	eq(debugOf(TESTER):GetAttribute("TrustedCell"), entry, "a teleport claim onto a fuse room is walked, not jumped: one tick later the trusted cell is still the entry")
	claim(center)
	h:advance(3)
	eq(tBot:state().run.fuses, 0, "…and nothing was collected")

	-- (2) A CLAIM THROUGH THE PERIMETER WALL. The entry is always on the perimeter, so this wall
	-- always exists, and its middle is 19.8 studs from any doorway.
	local out
	for _, dxy in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if idAt(dxy[1], dxy[2]) == nil then out = Vector3.new(dxy[1], 0, dxy[2]); break end
	end
	truthy(out ~= nil, "control: the entry has a perimeter side")
	local roomsBefore = #zone.Floor.Rooms:GetChildren()
	claim(center + out * 60)
	h:advance(3)
	eq(debugOf(TESTER):GetAttribute("TrustedCell"), entry, "a claim out through the perimeter wall leaves the trusted cell in the entry")
	eq(#zone.Floor.Rooms:GetChildren(), roomsBefore, "…and builds nothing")
	claim(center)
	h:advance(3)

	-- (3) …and through an interior wall, where the entry has one
	local conn = leaves()
	local wallNb
	for _, dxy in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local id = idAt(dxy[1], dxy[2])
		if id and not conn[id] then wallNb = { dir = Vector3.new(dxy[1], 0, dxy[2]), id = id }; break end
	end
	if wallNb then
		claim(center + wallNb.dir * CELL)
		h:advance(3)
		eq(debugOf(TESTER):GetAttribute("TrustedCell"), entry, "a claim into the room behind an interior wall leaves the trusted cell in the entry")
		eq(zone.Floor.Rooms:FindFirstChild("Room_" .. wallNb.id), nil, "…and that room is never built")
		claim(center)
		h:advance(3)
	else
		-- Every in-grid neighbour is a doorway, so there is no interior wall to claim through; claim
		-- through a CORNER instead, into the diagonal room, which no doorway can ever reach directly.
		local dirs = {}
		for _, dxy in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if idAt(dxy[1], dxy[2]) then table.insert(dirs, dxy) end
		end
		local a = dirs[1]
		local b
		for _, d in dirs do if d[1] ~= a[1] and d[2] ~= a[2] then b = d; break end end
		local diag = idAt(a[1] + b[1], a[2] + b[2])
		print("  (the entry has no interior wall on this floor; claiming through a corner into room " .. tostring(diag) .. ")")
		claim(center + Vector3.new(a[1] + b[1], 0, a[2] + b[2]) * CELL)
		h:advance(3)
		eq(debugOf(TESTER):GetAttribute("TrustedCell"), entry, "a claim through a corner into the diagonal room leaves the trusted cell in the entry")
		eq(zone.Floor.Rooms:FindFirstChild("Room_" .. tostring(diag)), nil, "…and that room is never built")
		claim(center)
		h:advance(3)
	end

	-- (4) a legitimate approach opens a door and builds the room behind it
	local nb, leaf
	for id, l in leaves() do
		if nb == nil or (leaf.CanCollide == false and l.CanCollide ~= false) then nb, leaf = id, l end
	end
	local nx = (nb - 1) % n
	local ny = (nb - 1 - nx) / n
	local dir = Vector3.new(nx - ex, 0, ny - ey)
	tBot:walkTo(center + dir * 7 + Vector3.new(0, 3, 0))
	tBot:waitSeconds(0.2)
	eq(leaf.CanCollide, false, "walking to 7 studs from a doorway opens it")
	truthy(zone.Floor.Rooms:FindFirstChild("Room_" .. nb) ~= nil, "…and builds the room behind it")
	tBot:walkTo(center + Vector3.new(0, 3, 0))

	-- flashlight and battery
	local b0 = tBot:state().run.battery
	tBot:fire("Flashlight", true)
	tBot:waitSeconds(2)
	local s1 = tBot:state().run
	eq(s1.lightOn, true, "the flashlight is on")
	near(s1.battery, b0 - 2, 0.35, "…and drains 1 s per second even in a lit room")
	local head = tester.Character:FindFirstChild("Head") or hrpOf(tester)
	local spot = head:FindFirstChild("Flashlight")
	truthy(spot ~= nil and spot.ClassName == "SpotLight" and spot.Enabled == true, "the SpotLight on the character mirrors it")
	eq(spot and spot.Range, 40, "…Range 40")
	tBot:fire("Flashlight", false)
	tBot:waitSeconds(0.5)
	local b1 = tBot:state().run.battery
	tBot:waitSeconds(2)
	near(tBot:state().run.battery, b1, 0.01, "light off: no drain")
	eq(spot and spot.Enabled, false, "…and the SpotLight is off")

	-- sprint follows the server's stamina
	tBot:fire("Sprint", true)
	tBot:waitSeconds(0.3)
	eq(tester.Character:FindFirstChildOfClass("Humanoid").WalkSpeed, 24, "sprint: the server sets WalkSpeed 24")
	tBot:waitSeconds(5)
	eq(tester.Character:FindFirstChildOfClass("Humanoid").WalkSpeed, 16, "…and back to 16 when stamina runs out, still requested")
	tBot:fire("Sprint", false)

	-- forged remotes: every refusal answered, nothing granted
	local toastsBefore = #tBot.toasts
	tBot:fire("Choose", "extract")
	tBot:fire("Choose", 42)
	tBot:fire("BuyPerk", "deepCell")
	tBot:fire("Flashlight", "on")
	tBot:fire("BuyPerk", { "deepCell" })
	tBot:waitSeconds(0.3)
	eq(#tBot.toasts - toastsBefore, 5, "five forged requests, five toasts — nothing fails silently")
	eq(stored(TESTER).essence, 0, "…and nothing was paid")
	eq(tBot:phase(), "floor", "…and the run is still on")
end

-- clear the floor, descend, and die by TakeDamage in the ride
eq(tBot:clearFloor(), "powered", "TESTER clears sublevel 1")
section("G. the reset path: TakeDamage settles once, the respawn lands on HubSpawn")
do
	tBot:fire("Choose", "descend")
	h:advance(1)
	eq(tBot:phase(), "ride", "riding down to sublevel 2")
	local before = stored(TESTER).essence
	tester.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(1000)
	h:advance(0.3)
	eq(stored(TESTER).essence, before + 2, "Humanoid.Died during a run pays what the dark pays: 2")
	eq(stored(TESTER).openRun, nil, "…and closes the run")
	eq(tBot:phase(), "hub", "…and the player is back in the hub phase")
	h.Players:simulateSpawn(tester, h.workspace)
	h:advance(1)
	local r = hrpOf(tester)
	near(r.Position.X, hubSpawn.Position.X, 0.01, "the respawn lands on HubSpawn (X)")
	near(r.Position.Z, hubSpawn.Position.Z, 0.01, "…(Z)")
	eq(stored(TESTER).essence, before + 2, "CharacterAdded's settle is idempotent: paid once")
	local zone = zoneOf(TESTER)
	eq(zone:FindFirstChild("Floor"), nil, "the abandoned floor is cleaned up")
end

--=========================================================================== I. first-ever run
section("I. a first-ever player: the front waits for the first fuse (NEWBIE)")
do
	local newbie = h:join("Newbie", NEWBIE)
	h:advance(0.5)
	h.Players:simulateSpawn(newbie, h.workspace)
	h:advance(0.5)
	local nBot = Bot.new(h, newbie)
	truthy(nBot:board(hub) and nBot:waitPhase("floor", RIDE + 1), "NEWBIE reaches sublevel 1")
	local dbg = debugOf(NEWBIE)
	eq(dbg:GetAttribute("HoldSeconds"), -1, "the front is held (HoldSeconds -1)")
	local zone = zoneOf(NEWBIE)
	local light = zone.Floor.Rooms:FindFirstChild("Room_" .. dbg:GetAttribute("EntryCell")).Fixture.RoomLight
	nBot:waitSeconds(60)
	eq(light.Enabled, true, "60 s standing in the entry: still lit")
	-- the onboarding fuse is within 2 doorways; the bot finds it and the front starts
	local tFuse
	local r = nBot:clearFloor()
	for _, n in nBot.notices do
		if n.kind == "fuse" and tFuse == nil then tFuse = n.at end
	end
	eq(r, "powered", "a first-ever player clears sublevel 1")
	local hold = debugOf(NEWBIE):GetAttribute("HoldSeconds")
	truthy(type(hold) == "number" and hold >= 60, "…and the front started at the first fuse pickup (HoldSeconds " .. tostring(hold) .. ")")
	local powerFailing = false
	for _, n in nBot.notices do if n.kind == "powerFailing" then powerFailing = true end end
	truthy(powerFailing, "…with THE POWER IS FAILING notice")
	h:leave(newbie)
	h:advance(0.5)
	eq(stored(NEWBIE).openRun, nil, "leaving mid-run settles the run")
	eq(stored(NEWBIE).essence, 2, "…paying exactly what the dark pays: floor(25% of 10) = 2")
	eq(stored(NEWBIE).runs, 1, "…and the first-ever run is over")
	local fac = h.workspace:FindFirstChild("Facility")
	local _, idx = nil, dbg:GetAttribute("ZoneIndex")
	eq(fac:FindFirstChild("Zone_" .. tostring(idx)), nil, "the leaver's zone is destroyed")
	eq(debugOf(NEWBIE), nil, "…and their debug mirror")
end

--=========================================================================== J. purchases
section("J. a purchase is refused and rolled back when the store write fails (SHOPPER)")
do
	local shopper = h:join("Shopper", SHOPPER)
	h:advance(0.5)
	h.Players:simulateSpawn(shopper, h.workspace)
	h:advance(0.5)
	local sBot = Bot.new(h, shopper)
	store.__failAll = true
	sBot:fire("BuyPerk", "deepCell")
	h:advance(0.3)
	store.__failAll = false
	eq(sBot:state().essence, 30, "a failed flush spends nothing")
	eq(sBot:state().perks.deepCell, 0, "…and grants nothing")
	local said = false
	sBot:drainNotices()
	for _, t in sBot.toasts do if string.find(t, "nothing was spent", 1, true) then said = true end end
	truthy(said, "…and says so: 'Couldn't reach the save server — nothing was spent.'")
	eq(stored(SHOPPER).essence, 30, "…and the store still holds 30")
	sBot:fire("BuyPerk", "deepCell")
	h:advance(0.3)
	eq(sBot:state().essence, 5, "with the store back, Deep Cell costs 25")
	eq(stored(SHOPPER).perks.deepCell, 1, "…and the rank is on disk before it is granted")
	sBot:fire("BuyPerk", "deepCell")
	h:advance(0.3)
	eq(stored(SHOPPER).essence, 5, "5 Essence cannot buy rank 2")
	-- the perk applies to the next run
	truthy(sBot:board(hub) and sBot:waitPhase("floor", RIDE + 1), "SHOPPER starts a run")
	eq(sBot:state().run.batteryCap, 55, "Deep Cell rank 1: the run's battery is 55 s")
	h:leave(shopper)
	h:advance(0.5)
end

section("J2. walking into the car while a purchase is still saving, and the save fails (SLOWBUY)")
do
	-- The emulator's store never yields; Roblox's does, and a write to a key written moments ago
	-- can wait seconds. This store takes 6 s over the purchase and then raises. The player walks
	-- straight to the car meanwhile. Whatever the server decides about that boarding, the run the
	-- player then plays must be a real run: checkpointed, offered the choice, paid.
	local SLOWBUY = 7008
	store:SetAsync("u_" .. SLOWBUY, profile({ essence = 30, runs = 3 }))
	local realUpdate = getmetatable(store).UpdateAsync
	local slowFail = false
	store.UpdateAsync = function(self, k, transform)
		if slowFail and k == "u_" .. SLOWBUY then
			slowFail = false
			h.scheduler:wait(6)
			error("robloxemu (check): injected slow failure", 0)
		end
		return realUpdate(self, k, transform)
	end
	local sb = h:join("SlowBuy", SLOWBUY)
	h:advance(0.5)
	h.Players:simulateSpawn(sb, h.workspace)
	h:advance(0.5)
	local sBot = Bot.new(h, sb)
	slowFail = true
	-- fired from a scheduler thread, as the engine runs a remote handler, so the save may yield
	h.scheduler:spawn(function()
		remotes:FindFirstChild("BuyPerk"):simulateFireServer(sb, "deepCell")
	end)
	local car = hub.HubCar.CarFloor.Position
	sBot:walkTo(Vector3.new(car.X, 3, car.Z))
	sBot:waitSeconds(3)
	eq(sBot:phase(), "hub", "no run starts while a purchase is still being saved")
	local told = false
	for _, t in sBot.toasts do if string.find(string.lower(t), "saving", 1, true) then told = true end end
	truthy(told, "…and the elevator says why")
	sBot:waitSeconds(4) -- the save fails at 6 s
	eq(sBot:state().essence, 30, "the failed purchase spent nothing")
	eq(sBot:state().perks.deepCell, 0, "…and granted nothing")
	truthy(sBot:waitPhase("ride", 12), "standing in the car, the run starts once the save has answered")
	truthy(sBot:waitPhase("floor", RIDE + 1), "…and reaches sublevel 1")
	local n0 = #sBot.notices
	eq(sBot:clearFloor(), "powered", "SLOWBUY powers sublevel 1")
	local choice
	for i = n0 + 1, #sBot.notices do
		if sBot.notices[i].kind == "choice" then choice = sBot.notices[i].data end
	end
	truthy(choice ~= nil and choice.bank == 10, "…and is offered the choice, bank 10")
	eq(stored(SLOWBUY).openRun and stored(SLOWBUY).openRun.runEssence, 10, "…with the checkpoint on disk")
	sBot:fire("Choose", "extract")
	h:advance(0.3)
	eq(stored(SLOWBUY).essence, 40, "EXTRACT banks it: 30 + 10")
	h:leave(sb)
	h:advance(0.5)
	store.UpdateAsync = nil -- back to the real method
end

--=========================================================================== K. crash recovery
section("K. an open checkpoint settles on the next join, once (CRASHED)")
do
	local c1 = h:join("Crashed", CRASHED)
	h:advance(0.5)
	eq(stored(CRASHED).openRun, nil, "the stale checkpoint is settled on load")
	eq(stored(CRASHED).essence, 5 + 15, "…at the death share: floor(35% of 45) = 15")
	eq(stored(CRASHED).runs, 3, "…counted as a run")
	h:leave(c1)
	h:advance(0.5)
	local c2 = h:join("Crashed", CRASHED)
	h:advance(0.5)
	eq(stored(CRASHED).essence, 20, "rejoining pays nothing again")
	h:leave(c2)
	h:advance(0.5)
end

--=========================================================================== L. shutdown
section("K2. the save server fails on join, then comes back (FAILER)")
do
	local FAILER = 7007
	store:SetAsync("u_" .. FAILER, profile({ essence = 40, runs = 4 }))
	store.__failNext = true -- exactly the join's UpdateAsync
	local f = h:join("Failer", FAILER)
	h:advance(0.5)
	h.Players:simulateSpawn(f, h.workspace)
	h:advance(0.5)
	local fBot = Bot.new(h, f)
	fBot:drainNotices()
	local saidStore, saidOther = false, false
	for _, t in fBot.toasts do
		if string.find(t, "save server", 1, true) then saidStore = true end
		if string.find(t, "another server", 1, true) then saidOther = true end
	end
	truthy(saidStore, "a failed load says the save server could not be reached")
	eq(saidOther, false, "…and does not claim the file is open on another server")
	local car = hub.HubCar.CarFloor.Position
	local toastsBefore = #fBot.toasts
	fBot:walkTo(Vector3.new(car.X, 3, car.Z))
	fBot:waitSeconds(2)
	eq(fBot:phase(), "hub", "no run starts while nothing could be saved")
	local refusal = fBot.toasts[toastsBefore + 1]
	truthy(refusal ~= nil and string.find(refusal, "save server", 1, true) ~= nil,
		"…and the elevator says why, truthfully: '" .. tostring(refusal) .. "'")
	fBot:walkTo(Vector3.new(car.X - 12, 3, car.Z))
	fBot:waitSeconds(21) -- one autosave period: the loop retries the claim
	eq(fBot:state().essence, 40, "the retry loads the real profile (40 Essence)")
	truthy(fBot:board(hub), "…and the elevator works again")
	eq(fBot:phase(), "ride", "…into a run")
	h:leave(f)
	h:advance(0.5)
	eq(stored(FAILER).runs, 5, "leaving settles that run on the recovered file")
end

section("K3. leaving while the join's lock claim is still in flight releases the lock (LEAVER, REVIEW-1 A2)")
do
	-- Roblox's UpdateAsync yields; this one takes 1.5 s over the JOIN's claim and then commits
	-- normally. The player leaves 0.5 s into it. The claim then writes a lock naming a session that
	-- no longer exists, and nothing released it: the next join was told "open on another server"
	-- and could not board or buy for 59.1 s (measured by the reviewer's probe, os.time on the
	-- virtual clock). Here os.time is the real clock, so a lock left behind outlives the whole file.
	local LEAVER = 7009
	store:SetAsync("u_" .. LEAVER, profile({ essence = 12, runs = 2 }))
	local realUpdate = getmetatable(store).UpdateAsync
	local slowOnce = true
	local claimsSeen = 0
	store.UpdateAsync = function(self, k, transform)
		if k == "u_" .. LEAVER then
			claimsSeen += 1
			if slowOnce then
				slowOnce = false
				h.scheduler:wait(1.5)
			end
		end
		return realUpdate(self, k, transform)
	end
	-- joined from a scheduler thread, as the engine runs PlayerAdded, so the claim may yield
	h.scheduler:spawn(function()
		h:join("Leaver", LEAVER)
	end)
	h:advance(0.5)
	local l1 = h.Players:FindFirstChild("Leaver")
	truthy(l1 ~= nil, "control: the leaver joined")
	h:leave(l1)
	h:advance(2.5)
	truthy(claimsSeen >= 1, "control: the join's claim reached the store (" .. claimsSeen .. " UpdateAsync calls)")
	local rec = store:GetAsync("u_" .. LEAVER)
	eq(rec and rec.lock, nil, "no lock is left behind by a session that left before its claim came back")
	eq(rec and rec.data and rec.data.essence, 12, "…and the file itself is untouched")
	store.UpdateAsync = nil -- back to the real method
	local l2 = h:join("Leaver", LEAVER)
	h:advance(0.5)
	h.Players:simulateSpawn(l2, h.workspace)
	h:advance(0.5)
	local lBot = Bot.new(h, l2)
	lBot:drainNotices()
	eq(lBot:state() and lBot:state().saving, true, "rejoining at once, the file can be saved")
	local saidOther = false
	for _, t in lBot.toasts do
		if string.find(t, "another server", 1, true) then saidOther = true end
	end
	eq(saidOther, false, "…and nobody is told their file is open on another server")
	truthy(lBot:board(hub), "…and the elevator takes them straight down")
	h:leave(l2)
	h:advance(0.5)

	-- The release gives back only its OWN lock. Here another server has taken the file by the time
	-- the release runs (written into the store just before it); that lock must survive.
	local LEAVER2 = 7010
	store:SetAsync("u_" .. LEAVER2, profile({ essence = 3, runs = 1 }))
	local calls = 0
	store.UpdateAsync = function(self, k, transform)
		if k == "u_" .. LEAVER2 then
			calls += 1
			if calls == 1 then
				h.scheduler:wait(1.5) -- the join's claim, slow
			elseif calls == 2 then
				local rec2 = store:GetAsync(k)
				store:SetAsync(k, { data = rec2 and rec2.data, lock = { owner = "another-server", expires = os.time() + 45 } })
			end
		end
		return realUpdate(self, k, transform)
	end
	h.scheduler:spawn(function()
		h:join("Leaver2", LEAVER2)
	end)
	h:advance(0.5)
	h:leave(h.Players:FindFirstChild("Leaver2"))
	h:advance(2.5)
	store.UpdateAsync = nil
	truthy(calls >= 2, "control: the claim and the release both reached the store (" .. calls .. " calls)")
	local rec2 = store:GetAsync("u_" .. LEAVER2)
	eq(rec2 and rec2.lock and rec2.lock.owner, "another-server", "the release never clears a lock another server now holds")
end

section("L. BindToClose settles a run in progress (CLOSER)")
do
	local closer = h:join("Closer", CLOSER)
	h:advance(0.5)
	h.Players:simulateSpawn(closer, h.workspace)
	h:advance(0.5)
	local cBot = Bot.new(h, closer)
	truthy(cBot:board(hub) and cBot:waitPhase("floor", RIDE + 1), "CLOSER is mid-run")
	h.services.runBindToClose()
	eq(stored(CLOSER).openRun, nil, "server shutdown settles the open run")
	eq(stored(CLOSER).runs, 2, "…as a run")
	local rec = store:GetAsync("u_" .. CLOSER)
	eq(rec.lock, nil, "…and releases the session lock")
end

--=========================================================================== M. glyphs
section("M. every glyph in the world and every notice is one Studio has rendered")
do
	-- robloxemu/check_forktower.luau GLYPHS_SEEN_IN_STUDIO, the photographed list.
	local SEEN = {
		[0x2014] = true, [0x2026] = true, [0x2605] = true, [0x2744] = true, [0xFE0F] = true,
		[0x1F30C] = true, [0x1F441] = true, [0x1F451] = true, [0x1F4A8] = true, [0x1F500] = true,
		[0x1F512] = true, [0x1F525] = true, [0x1F5FF] = true, [0x1F34C] = true, [0x1F0CF] = true, [0x1F6AA] = true,
	}
	local unseen = {}
	local texts = 0
	local function inspect(s, where)
		if type(s) ~= "string" then return end
		texts += 1
		for _, cp in utf8.codes(s) do
			if cp >= 0x2000 and not SEEN[cp] then table.insert(unseen, string.format("U+%X in %s", cp, where)) end
		end
	end
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then inspect(d.Text, d:GetFullName()) end
		if d.ClassName == "ProximityPrompt" then inspect(d.ActionText, d:GetFullName()); inspect(d.ObjectText, d:GetFullName()) end
	end
	local worldTexts = texts
	local function walk(v, where)
		if type(v) == "string" then inspect(v, where)
		elseif type(v) == "table" then for k, x in v do walk(x, where .. "." .. tostring(k)) end end
	end
	for i, rec in NoticeR:getSent() do walk(rec.args[2], "Notice#" .. i .. ":" .. tostring(rec.args[1])) end
	-- Two controls, each on a count that cannot drift with the floor a run happened to generate:
	-- the hub's own labels and prompt (4 strings) and the Notice strings since section C, which
	-- include section F's five forged-request toasts on every run.
	truthy(worldTexts >= 4, "control: " .. worldTexts .. " world strings inspected")
	truthy(texts - worldTexts >= 5, "control: " .. (texts - worldTexts) .. " notice strings inspected")
	eq(#unseen, 0, "no unphotographed glyph (" .. table.concat(unseen, "; ") .. ")")
end

--=========================================================================== done
section("summary")
for _, line in runStats do print("  " .. line) end
local errs = h:errors()
eq(#errs, 0, "no scheduler errors (" .. table.concat(errs, " | ") .. ")")
eq(#h.warnings, 0, "no warnings (" .. table.concat(h.warnings, " | ") .. ")")
print(string.format("check_facilitynightmare: %d passed, %d failed", passed, failed))
