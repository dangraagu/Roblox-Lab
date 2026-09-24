-- FACILITY: Endless Nightmare — a room is dressed and repainted on the FIRST frame it can be seen.
--
-- Run:  py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       luau check_facilitynightmare_firstframe.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- The review's finding 2 (EYECANDY.md §11): Env.client dressed and recoloured rooms only in its 4 Hz pass, so
-- through every door that opened, and on arrival, the player saw a room in the SERVER's pale grey-green for up to
-- 14 frames and then a hard cut to the band's palette with its furniture popping in. The brief rules hard cuts out.
--
-- Through the real server and the real Env.client, with RenderStepped fired at 60 Hz (six frames per 0.1 s server
-- tick; a room the server builds appears between two frames), this audits AFTER EVERY FRAME:
--   * every built room of the player's floor whose centre is within 60 studs (DressRadius, written out), and during
--     a ride every built room (the car is closed on all four sides, so the entry room must be ready on arrival), is
--     dressed, its dressing parented, its walls and its light wearing the palette of the band Dressing.roomBand
--     gives it;
--   * every door leaf of such a room wears the door colour of its band.
-- It opens doors in the void (the band furthest from the server's colours, in memory), walks on through fuse-free
-- rooms, then plays sublevel 1 for real and rides down to sublevel 2.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")
local bundle = require("./build/facility-nightmare")

local h = Harness.new({ bundle = bundle, name = "facility-nightmare-firstframe", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Env = Config.Env
local bands = Env.Bands
local Dressing = h:_require(h.ReplicatedStorage:FindFirstChild("Dressing"))
local EnvBands = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBands"))

local DRESS_RADIUS = 60 -- written out: Config.Env.DressRadius as shipped

local UID = 9311
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
-- runs 0: a first-ever run, so sublevel 1's front is HELD until the first fuse; every perk, so the bot powers it
store:SetAsync("u_" .. UID, { data = { v = 1, essence = 0, essenceEarned = 900, bestSublevel = 0, runs = 0, extractions = 0,
	perks = { deepCell = 3, nightEyes = 3, marathon = 3, soulAnchor = 0, secondWind = 1 } } })

assert(h:tryRun("server/Main.server"))
h:advance(1)
local plr = h:join("FirstFrame", UID)
h:advance(0.5)
truthy((h:tryRun("client/Hud.client")), "client/Hud.client loads")
truthy((h:tryRun("client/Env.client")), "client/Env.client loads")
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)

local RS = h.game:GetService("RunService")
local envFolder = h.workspace:FindFirstChild("FacilityEnvLocal")
truthy(envFolder ~= nil, "Env.client made its local folder")

local function same(c3, t)
	return c3 ~= nil and math.abs(c3.R * 255 - t[1]) <= 1.5 and math.abs(c3.G * 255 - t[2]) <= 1.5 and math.abs(c3.B * 255 - t[3]) <= 1.5
end

--=========================================================================== the audit, after every frame
local bot
local auditOn = true
local frames = 0
local stats = { roomsSeen = 0, roomFrames = 0, rideFrames = 0, leafFrames = 0, violations = 0, worst = 0 }
local firstSeen = {} -- room folder -> frame it was first seen
local stale = {} -- room folder -> consecutive frames it has been in view and not ready
local examples = {}

local function note(msg)
	stats.violations += 1
	if #examples < 8 then table.insert(examples, msg) end
end

local function audit()
	local st = bot:state()
	if not st or not st.run or (st.phase ~= "ride" and st.phase ~= "floor") then return end
	local k = st.run.k
	local fl = bot:floor()
	local rooms = fl and fl:FindFirstChild("Rooms")
	local doors = fl and fl:FindFirstChild("Doors")
	local root = bot:pos()
	if not rooms or not root then return end
	local riding = st.phase == "ride"
	for _, rf in rooms:GetChildren() do
		local id = tonumber(string.match(rf.Name, "^Room_(%d+)$"))
		local floorPart = rf:FindFirstChild("Floor")
		if id and floorPart then
			if not firstSeen[rf] then
				firstSeen[rf] = frames
				stats.roomsSeen += 1
			end
			local dx, dz = floorPart.Position.X - root.X, floorPart.Position.Z - root.Z
			if riding or dx * dx + dz * dz <= DRESS_RADIUS * DRESS_RADIUS then
				stats.roomFrames += 1
				if riding then stats.rideFrames += 1 end
				local pal = bands[Dressing.roomBand(Env, EnvBands, k, id)].palette
				local problem = nil
				local dress = envFolder.Rooms:FindFirstChild("Dress_" .. rf.Name)
				if not dress then
					problem = "not dressed"
				else
					for _, c in rf:GetChildren() do
						if string.sub(c.Name, 1, 4) == "Wall" and not same(c.Color, pal.wall) then problem = "walls in " .. tostring(c.Color) end
					end
					local fx = rf:FindFirstChild("Fixture")
					local rl = fx and fx:FindFirstChild("RoomLight")
					if rl and not same(rl.Color, pal.light) then problem = "light in " .. tostring(rl.Color) end
				end
				for _, leaf in doors and doors:GetChildren() or {} do
					local lo, hi = string.match(leaf.Name, "^Door_(%d+)_(%d+)$")
					lo, hi = tonumber(lo), tonumber(hi)
					if lo and (lo == id or hi == id) and leaf:IsA("BasePart") then
						stats.leafFrames += 1
						local want = bands[Dressing.roomBand(Env, EnvBands, k, lo)].palette.door
						if not same(leaf.Color, want) then problem = (problem or "") .. " door " .. leaf.Name .. " in " .. tostring(leaf.Color) end
					end
				end
				if problem then
					stale[rf] = (stale[rf] or 0) + 1
					stats.worst = math.max(stats.worst, stale[rf])
					note(string.format("sublevel %d %s %s: %s, %d frame(s) after it appeared", k, if riding then "(riding)" else "", rf.Name,
						problem, frames - firstSeen[rf]))
				else
					stale[rf] = 0
				end
			end
		end
	end
end

local function sixty()
	for _ = 1, 6 do
		RS.RenderStepped:Fire(1 / 60)
		frames += 1
		if auditOn then audit() end
	end
end
bot = Bot.new(h, plr, { onTick = sixty, maxSeconds = 1200 })

local original = {}
for i, b in bands do original[i] = { from = b.from, fade = b.fade } end
local function onlyBand(i)
	for j, b in bands do
		if j < i then b.from, b.fade = -1000 + j, 0 elseif j == i then b.from, b.fade = 0, 0 else b.from, b.fade = 1000 + j, 0 end
	end
end
local function restoreBands()
	for i, b in bands do b.from, b.fade = original[i].from, original[i].fade end
end
-- a band switched IN MEMORY re-dresses every room on the next pass; that is the check's own doing, not a new room,
-- so the audit pauses for it
local function switchBands(fn)
	auditOn = false
	fn()
	bot:waitSeconds(1)
	auditOn = true
end

--=========================================================================== A. the first ride down
section("A. the ride to sublevel 1: the entry room is dressed during the ride, ready on arrival")

truthy(bot:board(h.workspace.Hub), "boarded the hub car")
truthy(bot:waitPhase("floor", 8), "arrived on sublevel 1")
bot:waitSeconds(1, "floor")
truthy(stats.rideFrames > 0, "control: the audit saw the ride (" .. stats.rideFrames .. " room-frames)")
local afterRide = stats.violations
eq(afterRide, 0, "the entry room was dressed and repainted on every frame of the ride and of the arrival")

--=========================================================================== B. doors opening in the void
section("B. every door that opens: the room behind it is ready on the first frame")

local rooms = bot:rooms()
local entry = bot:roomAt(rooms, bot:pos())
switchBands(function() onlyBand(#bands) end)
local seenBefore = stats.roomsSeen
local function openAllFrom(room)
	local rs = bot:rooms()
	local c = rs[room].center
	for _, d in bot:doors() do
		if (d.lo == room or d.hi == room) and not d.open then
			local leaf = d.part.Position
			local dir = Vector3.new(leaf.X - c.X, 0, leaf.Z - c.Z).Unit
			bot:walkTo(Vector3.new(leaf.X - dir.X * 6, 3, leaf.Z - dir.Z * 6), "floor")
			local w = 0
			while d.part.CanCollide ~= false and w < 50 do bot:tick(); w += 1 end
			bot:walkTo(Vector3.new(c.X, 3, c.Z), "floor")
		end
	end
end
openAllFrom(entry)
-- on through rooms without a fuse (picking one up would start the first run's front before section C)
local visited = { [entry] = true }
local walked = 0
for _ = 1, 3 do
	rooms = bot:rooms()
	local here = bot:roomAt(rooms, bot:pos())
	local nextRoom = nil
	for _, d in bot:doors() do
		local nb = if d.lo == here then d.hi elseif d.hi == here then d.lo else nil
		if nb and d.open and rooms[nb] and not visited[nb] and rooms[nb].folder:FindFirstChild("Fuse") == nil then
			nextRoom = nb
			break
		end
	end
	if not nextRoom then break end
	bot:cross(rooms, here, nextRoom)
	visited[nextRoom] = true
	walked += 1
	openAllFrom(nextRoom)
end
eq(bot:state().run.fuses, 0, "control: no fuse picked up, so the floor is still held")
local opened = stats.roomsSeen - seenBefore
print(string.format("    %d rooms appeared behind opening doors (%d fuse-free rooms walked into)", opened, walked))
-- (the entry's only neighbours may hold the onboarding fuse, so this can be one room; C opens the rest of the floor)
truthy(opened >= 1, "control: rooms appeared in the void while the audit watched (" .. opened .. ")")
eq(stats.violations - afterRide, 0, "each was dressed and repainted, doors included, on the first frame it existed")
switchBands(restoreBands)

--=========================================================================== C. a real sublevel, and the ride down
section("C. played for real: sublevel 1 cleared, the ride to sublevel 2, its entry room ready on arrival")

local rideBefore = stats.rideFrames
local reached, attempts = false, 0
while not reached and attempts < 3 do
	attempts += 1
	if bot:phase() == "hub" then
		-- the dark took the bot (rare with every perk): another run, another audited ride
		assert(bot:board(h.workspace.Hub), "reboard")
		assert(bot:waitPhase("floor", 8), "arrive")
	end
	local r = bot:clearFloor()
	if r == "powered" then
		bot:fire("Choose", "descend")
		truthy(bot:waitPhase("ride", 3), "the ride down")
		reached = bot:waitPhase("floor", 8)
		bot:waitSeconds(2, "floor")
	else
		print("    the floor ended " .. tostring(r) .. "; going again")
		bot:waitPhase("hub", 10)
	end
end
truthy(reached, "arrived on sublevel 2 (in " .. attempts .. " attempt(s))")
truthy(stats.rideFrames > rideBefore, "control: the audit saw the second ride (" .. (stats.rideFrames - rideBefore) .. " room-frames)")
truthy(stats.roomsSeen >= 6, "control: at least six rooms appeared while the audit watched, over two sublevels (" .. stats.roomsSeen .. ")")

--=========================================================================== summary
print(string.format("    %d frames at 60 Hz, %d rooms seen, %d room-frames and %d door-frames audited (%d during rides)",
	frames, stats.roomsSeen, stats.roomFrames, stats.leafFrames, stats.rideFrames))
for _, e in examples do print("   " .. e) end
print(string.format("    the worst room was in view and not ready for %d frame(s)", stats.worst))
eq(stats.violations, 0, "no room was ever in view in the server's colours or undressed, not for a single frame")
eq(stats.worst, 0, "…so the longest wait is 0 frames")

local envWarnings = 0
for _, w in h.warnings do
	if string.find(w, "FacilityEnv", 1, true) then envWarnings += 1; print("   warn: " .. w) end
end
eq(envWarnings, 0, "Env.client never warned")
eq(#h:errors(), 0, "no scheduler errors")
for _, e in h:errors() do print("   " .. e) end

print(string.format("check_facilitynightmare_firstframe: %d passed, %d failed", passed, failed))
