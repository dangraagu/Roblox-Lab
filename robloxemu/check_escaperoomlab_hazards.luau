-- Escape Room Lab — the rare hazards and the Break, through the REAL clients (DESIGN.md §8, §9).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_hazards.luau 2>&1
--
-- Config.Hazards.IntervalMin/Max are set to 8/9 IN MEMORY for this run only, before Lab.client loads, so a
-- short check meets many hazards. Everything else is the shipped config and the shipped glue.
--   * Reception (the onboarding wing) never releases one, however long you stay (the quiet-band rule);
--   * the Atrium and the lift cabs FREEZE the clock; a room's first 8 s are grace;
--   * a lane starts under the 16-stud ceiling, straight above the player (ctx.pitch = rad(85), trap 4);
--   * the red ring drawn at the feet IS the hit zone: 7 studs wide, centred where the player stands;
--   * standing still is hit (a 20 studs/s sideways stumble, PlatformStand 0.6 s, nothing lost);
--     stepping out of the ring dodges, and the banner turns to CLEAR; review-1 B1: the lane locks on its
--     first frame, so a step 0.3 s after the ring shows dodges and the ring never moves;
--   * review-1 B4: the clock is frozen at the door station and in the arrival grace too, so no hazard is
--     held there and released the moment the player steps onto a legal spot or the grace ends;
--   * the station overlay folds to its title bar while a hazard is live and reopens when it is gone;
--   * the Break: it sits, freezes the hazard clock, is QUEUED (not granted) with a hazard inbound, and
--     ends when a station is opened.

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local w = Lib.boot({ name = "escape-room-lab-hazards" })
local h, ws = w.h, w.ws
local Config = w.Config
local W, Hz = Config.World, Config.Hazards
Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in memory, this run only
local p = Lib.player(w, "Dodger", 9301)
h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Lab.client"))
local RunService = h.game:GetService("RunService")
local cam = ws.CurrentCamera
local env = ws.LabLocalEnv
local hud = p.plr.PlayerGui.LabHud.Root
local ClientBus = w.mod("ClientBus")

local clock = 0
local spawns = {} -- { at, where }
local wasShown = false
local arrivedAt, lastRoomId = nil, nil -- when this client got the RoomState of a NEW room
local function hazardParts()
	local n, centre = 0, Vector3.zero
	for _, d in env:GetChildren() do
		if string.match(d.Name, "^Hazard_") then
			n += 1
			centre += d.Position
		end
	end
	return n, if n > 0 then centre / n else nil
end
local function ring() return env:FindFirstChild("HazardRing") end
local function frame(dt)
	cam.CFrame = CFrame.new(p.hrp.Position + Vector3.new(0, 4, 10), p.hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	clock += dt
	local cur = Lib.last(w, "RoomState", p.plr)
	if cur and cur.roomId and cur.roomId ~= lastRoomId then
		lastRoomId = cur.roomId
		arrivedAt = clock
	end
	local n = hazardParts()
	if n > 0 and not wasShown then
		local rs = Lib.last(w, "RoomState", p.plr)
		table.insert(spawns, { at = clock, where = rs and rs.where or "?", slot = rs and rs.slot })
	end
	wasShown = n > 0
	p.hrp.AssemblyLinearVelocity = Vector3.zero
end
local function run(sec) for _ = 1, math.floor(sec * 20 + 0.5) do frame(0.05) end end
local function step() frame(0.05) end
local function waitForHazard(maxSec)
	local t0 = clock
	while clock - t0 < maxSec do
		frame(0.05)
		if hazardParts() > 0 then return clock - t0 end
	end
	return nil
end
local function waitNoHazard(maxSec)
	local t0 = clock
	while clock - t0 < maxSec and hazardParts() > 0 do frame(0.05) end
end

--============================================================ the Atrium freezes the clock
run(30)
eq(#spawns, 0, "30 s in the Atrium with an 8-9 s interval: no hazard (the clock is frozen)")

--============================================================ Reception is quiet: rooms 1-3, with long waits
Lib.intoSoloLift(w, p)
run(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 0.5)
local receptionSeconds = 0
for slot = 1, 3 do
	local rs = Lib.last(w, "RoomState", p.plr)
	eq(rs.slot, slot, "in room " .. slot)
	p.hrp.CFrame = CFrame.new(Lib.origin(w, p.plr) + Vector3.new(0, 3, 0))
	run(25)
	receptionSeconds += 25
	Lib.solveRoom(w, p, step)
	Lib.next(w, p)
	run(Config.Lift.RideSeconds + 0.5)
end
eq(#spawns, 0, string.format("%d s standing in Reception's rooms: no hazard (the onboarding wing is quiet)", receptionSeconds))

--============================================================ the Archive: grace, lane, ring, hit
local rs4 = Lib.last(w, "RoomState", p.plr)
eq(rs4.slot, 4, "room 4, the Archive")
local o = Lib.origin(w, p.plr)
local arrival = arrivedAt
p.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3, 0)) -- the room's centre: a legal spot
local dt1 = waitForHazard(20)
truthy(dt1 ~= nil, "a spider comes in the Archive")
local since = clock - arrival
truthy(since >= Config.Lift.ArrivalGraceSeconds - 0.05, string.format("not before the 8 s arrival grace (it came %.2f s after arrival)", since))
do
	local n, centre = hazardParts()
	truthy(n >= 1 and env:FindFirstChild("Hazard_spider_1") ~= nil, "the Archive's hazard is the spider, drawn (" .. n .. " parts)")
	local local_ = centre - o
	truthy(local_.Y <= W.RoomHeight - 0.9, string.format("its lane starts under the ceiling (y %.2f of 16)", local_.Y))
	-- the lane starts at most 1.046 studs sideways of its target (EnvConfig.spec), and the target is at
	-- most AimJitter (0.8) from the player: 1.85 at most, directly overhead in a 32-stud room
	local horiz = math.sqrt((centre.X - p.hrp.Position.X) ^ 2 + (centre.Z - p.hrp.Position.Z) ^ 2)
	truthy(horiz <= 1.046 + Hz.AimJitter + 0.01, string.format("straight above the player (%.2f studs sideways)", horiz))
	truthy(local_.Y > p.hrp.Position.Y - o.Y + 8, "from well above the head")
	local r = ring()
	truthy(r ~= nil, "a red ring is drawn at the feet")
	if r then
		local zoneR = Hz.Kinds.spider.hitRadius + Hz.PlayerRadius
		truthy(math.abs(r.Size.Y - 2 * zoneR) < 1e-6 and math.abs(r.Size.Z - 2 * zoneR) < 1e-6,
			string.format("the ring is exactly the zone: %.2f studs across (2 x (hit %.1f + player %.1f))", r.Size.Y, Hz.Kinds.spider.hitRadius, Hz.PlayerRadius))
		local off = math.sqrt((r.Position.X - p.hrp.Position.X) ^ 2 + (r.Position.Z - p.hrp.Position.Z) ^ 2)
		truthy(off < 0.01, string.format("centred where the player stands (%.3f studs off)", off))
		truthy(math.abs(r.Position.Y - (p.hrp.Position.Y - Hz.RootHeight + 0.06)) < 1e-6, "on the floor, at the feet")
	end
	truthy(hud.Banner.Visible and string.find(hud.Banner.Text, "SPIDER", 1, true) ~= nil and string.find(hud.Banner.Text, "STEP OUT", 1, true) ~= nil,
		"the banner warns: " .. hud.Banner.Text)
end
-- stand still: hit
local rsBefore = Lib.last(w, "RoomState", p.plr)
local hit = false
local knock = nil
for _ = 1, 100 do
	cam.CFrame = CFrame.new(p.hrp.Position + Vector3.new(0, 4, 10), p.hrp.Position)
	RunService.RenderStepped:Fire(0.05)
	if p.hum.PlatformStand == true and not hit then
		hit = true
		knock = p.hrp.AssemblyLinearVelocity
	end
	h:advance(0.05)
	clock += 0.05
	p.hrp.AssemblyLinearVelocity = Vector3.zero
	if hazardParts() == 0 then break end
end
truthy(hit, "standing still in the ring: hit")
if knock then
	truthy(math.abs(math.sqrt(knock.X ^ 2 + knock.Z ^ 2) - 20) < 0.01 and knock.Y == 0,
		string.format("a 20 studs/s sideways stumble, no lift (%.1f, %.1f, %.1f)", knock.X, knock.Y, knock.Z))
end
run(1)
eq(p.hum.PlatformStand, false, "the stumble wears off (PlatformStand 0.6 s)")
eq(Lib.last(w, "RoomState", p.plr), rsBefore, "nothing about the room changed: a hit costs nothing")

--============================================================ step out of the ring: dodged, CLEAR
local dodged, sawClear = 0, false
for trial = 1, 3 do
	p.hrp.CFrame = CFrame.new(o + Vector3.new(-4 + trial * 2, 3, 2))
	local got = waitForHazard(20)
	truthy(got ~= nil, "hazard " .. trial .. " comes")
	-- wait for the lock (telegraph - commit: 0 s since review-1 B1), then walk 4 studs out
	run(Hz.Kinds.spider.telegraph - Hz.Kinds.spider.commit + 0.1)
	local start = p.hrp.Position
	for i = 1, 5 do
		p.hrp.CFrame = CFrame.new(start + Vector3.new(0, 0, -4 * i / 5))
		frame(0.05)
	end
	local stood = false
	for _ = 1, 80 do
		frame(0.05)
		if p.hum.PlatformStand then stood = true end
		if string.find(hud.Banner.Text, "CLEAR", 1, true) then sawClear = true end
		if hazardParts() == 0 then break end
	end
	if not stood then dodged += 1 end
end
eq(dodged, 3, "stepping out of the ring after the lock dodges, 3 of 3")
truthy(sawClear, "the banner turns to CLEAR once out of the ring")

--============================================================ review-1 B1: step out at once, and the ring stays put
-- Before: the lane re-aimed at the player for 1.5 s after the ring showed, so a player who stepped out
-- straight away took the ring along and was hit (reviewer: 5 of 5 for a step 1.0 s after the ring showed).
local early, ringMoved = 0, 0
for trial = 1, 3 do
	p.hrp.CFrame = CFrame.new(o + Vector3.new(-4 + trial * 2, 3, -2))
	local got = waitForHazard(20)
	truthy(got ~= nil, "early-step hazard " .. trial .. " comes")
	local r0 = ring() and ring().Position
	run(0.3)
	local start = p.hrp.Position
	for i = 1, 5 do
		p.hrp.CFrame = CFrame.new(start + Vector3.new(4 * i / 5, 0, 0))
		frame(0.05)
		local r = ring()
		if r0 and r then ringMoved = math.max(ringMoved, (r.Position - r0).Magnitude) end
	end
	local stood = false
	for _ = 1, 80 do
		frame(0.05)
		local r = ring()
		if r0 and r then ringMoved = math.max(ringMoved, (r.Position - r0).Magnitude) end
		if p.hum.PlatformStand then stood = true end
		if hazardParts() == 0 then break end
	end
	if not stood then early += 1 end
end
eq(early, 3, "stepping out of the ring 0.3 s after it shows dodges, 3 of 3")
truthy(ringMoved < 0.01, string.format("the ring never moves once it shows (moved %.3f studs)", ringMoved))

--============================================================ the overlay folds, and reopens
do
	local stA = nil
	for _, s in Lib.last(w, "RoomState", p.plr).stations do stA = stA or s end
	Lib.standNear(w, p, stA.id)
	run(0.2)
	local pp = Lib.zone(w, p.plr):FindFirstChild("Station_" .. stA.id, true):FindFirstChildOfClass("ProximityPrompt")
	pp.Triggered:Fire(p.plr)
	run(0.2)
	local ov = hud.Overlay
	truthy(ov.Visible and ov.Body.Visible, "the station overlay is open")
	local fullH = ov.Size.Y.Offset
	waitForHazard(20)
	run(0.2)
	truthy(ov.Visible and not ov.Body.Visible and ov.Size.Y.Offset < fullH,
		string.format("a hazard folds the overlay to its title bar (%d -> %d design px)", fullH, ov.Size.Y.Offset))
	-- step out and wait it out, staying within reach
	p.hrp.CFrame = p.hrp.CFrame + Vector3.new(0, 0, 4.5)
	waitNoHazard(10)
	run(0.3)
	truthy(ov.Visible and ov.Body.Visible and ov.Size.Y.Offset == fullH, "and reopens when it has passed, within reach")
	hud.Overlay.TitleBar.CloseButton.Activated:Fire()
	run(0.2)
end

--============================================================ the Break
do
	p.hrp.CFrame = CFrame.new(o + Vector3.new(4, 3, 4))
	waitNoHazard(10)
	run(0.5)
	local n0 = #spawns
	hud.BreakButton.Activated:Fire()
	run(0.2)
	eq(p.hum.Sit, true, "Break sits the avatar down")
	truthy(string.find(hud.BreakButton.Text, "Carry on", 1, true) ~= nil, "the button offers to carry on: " .. hud.BreakButton.Text)
	truthy(string.find(hud.Banner.Text, "leaves you alone", 1, true) ~= nil, "the banner says so: " .. hud.Banner.Text)
	run(40)
	eq(#spawns, n0, "40 s of Break with an 8-9 s interval: no hazard (the clock is frozen, never reset)")
	-- moving wakes it
	p.hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6)
	p.hum.MoveDirection = Vector3.zero
	eq(p.hum.Sit, false, "moving ends the Break")
	local soon = waitForHazard(12)
	print(string.format("  after the Break the next hazard came %.2f s later (interval 8-9 s)", soon or -1))
	truthy(soon ~= nil and soon < 10, string.format("the frozen clock resumes where it stopped: a hazard %.1f s after the Break (the interval is 8-9)", soon or -1))
	-- a Break pressed with a hazard inbound is queued, never granted
	hud.BreakButton.Activated:Fire()
	run(0.1)
	eq(p.hum.Sit, false, "with a hazard inbound the Break is not granted")
	truthy(string.find(hud.BreakButton.Text, "...", 1, true) ~= nil, "it is queued: " .. hud.BreakButton.Text)
	-- dodge the way the ring asks: after the lane locks, step out (moving while a threat is live keeps
	-- the queued request; a HIT would cancel it, as in +1 Jump)
	run(Hz.Kinds.spider.telegraph - Hz.Kinds.spider.commit)
	local s0 = p.hrp.Position
	for i = 1, 5 do
		p.hrp.CFrame = CFrame.new(s0 + Vector3.new(-4.5 * i / 5, 0, 0))
		frame(0.05)
	end
	waitNoHazard(10)
	run(1)
	eq(p.hum.Sit, true, "the queued Break starts once the sky is clear and the player stands still")
	-- opening a station ends it
	local stA = Lib.last(w, "RoomState", p.plr).stations[1]
	Lib.standNear(w, p, stA.id)
	run(0.1)
	Lib.zone(w, p.plr):FindFirstChild("Station_" .. stA.id, true):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(p.plr)
	run(0.2)
	eq(p.hum.Sit, false, "opening a station ends the Break: it is never a hazard-free way to solve")
	eq(ClientBus.last("rest").resting, false, "and the Break state says so")
	hud.Overlay.TitleBar.CloseButton.Activated:Fire()
end

--============================================================ cabs freeze the clock too
-- Freezing is not the same as waiting: a clock that ran on in the cab would have a hazard DUE the moment
-- the player steps back into the room. So: straight after a hazard ends (its 8-9 s interval started at its
-- launch, 3.6 s ago), 30 s in the entry cab, then back to a legal spot: the next hazard must still take
-- the rest of that interval (about 4.4-5.4 s), not come at once.
do
	p.hrp.CFrame = CFrame.new(o + Vector3.new(3, 3, 3))
	waitForHazard(20)
	local s0 = p.hrp.Position
	run(Hz.Kinds.spider.telegraph - Hz.Kinds.spider.commit + 0.1)
	p.hrp.CFrame = CFrame.new(s0 + Vector3.new(4.5, 0, 0)) -- dodge
	waitNoHazard(10)
	local n0 = #spawns
	p.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3.5, W.RoomHalf + W.Wall + W.CabHalf))
	run(30)
	eq(#spawns, n0, "30 s in the entry cab: no hazard")
	p.hrp.CFrame = CFrame.new(o + Vector3.new(-3, 3, -3))
	local waitAfter = waitForHazard(20)
	truthy(waitAfter ~= nil and waitAfter >= 3, string.format(
		"back in the room, the next hazard still took %.1f s: the clock was FROZEN in the cab, not running", waitAfter or -1))
end

--============================================================ review-1 B4: no backlog at the door, none at the end of the grace
-- Before: away from a legal spot (the door station, within 5 studs of a doorway) and during the 8 s arrival
-- grace the clock RAN and a due hazard was held, so it fired the moment the player stepped onto a legal spot,
-- or exactly as the next room's grace ended (reviewer: 15 of 40 hazards came 8.0 s after arrival). Now the
-- clock is frozen wherever no hazard may be released, like in the cabs.
do
	-- (i) the door station: 30 s there right after a hazard, then a legal spot
	p.hrp.CFrame = CFrame.new(o + Vector3.new(-3, 3, 3))
	waitForHazard(20)
	local s0 = p.hrp.Position
	run(0.3)
	p.hrp.CFrame = CFrame.new(s0 + Vector3.new(4.5, 0, 0)) -- dodge
	waitNoHazard(10)
	local n0 = #spawns
	p.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3, -12)) -- at the keypad: not a legal spot
	run(30)
	eq(#spawns, n0, "30 s at the door station: no hazard")
	p.hrp.CFrame = CFrame.new(o + Vector3.new(3, 3, -3))
	local waitAfter = waitForHazard(20)
	truthy(waitAfter ~= nil and waitAfter >= 3, string.format(
		"back on a legal spot, the next hazard still took %.1f s: the clock was frozen at the door, nothing was held", waitAfter or -1))
	-- (ii) the arrival grace: right after a hazard, on to the next Archive room, and straight to a legal spot
	local s1 = p.hrp.Position
	run(0.3)
	p.hrp.CFrame = CFrame.new(s1 + Vector3.new(-4.5, 0, 0)) -- dodge
	waitNoHazard(10)
	Lib.solveRoom(w, p, step)
	waitNoHazard(10)
	Lib.next(w, p)
	run(0.2)
	local rs5 = Lib.last(w, "RoomState", p.plr)
	local waited = 0
	while (rs5 == nil or rs5.slot ~= 5) and waited < 10 do
		step()
		waited += 0.05
		rs5 = Lib.last(w, "RoomState", p.plr)
	end
	eq(rs5 and rs5.slot, 5, "on to room 5, the Archive's second room")
	local arrival5 = arrivedAt
	p.hrp.CFrame = CFrame.new(Lib.origin(w, p.plr) + Vector3.new(0, 3, 0))
	local got = waitForHazard(30)
	local since = got and (clock - arrival5) or -1
	print(string.format("  room 5: the first hazard came %.2f s after arrival (grace %d s)", since, Config.Lift.ArrivalGraceSeconds))
	truthy(got ~= nil and since >= Config.Lift.ArrivalGraceSeconds + 2.5, string.format(
		"the first hazard in room 5 came %.2f s after arrival, not as the 8 s grace ended: the clock was frozen in the grace", since))
end

print(string.format("  hazards met: %d, all in the Archive (slots %s)", #spawns, (function()
	local s = {}
	for _, x in spawns do table.insert(s, tostring(x.slot)) end
	return table.concat(s, ",")
end)()))
for _, x in spawns do truthy(x.where == "room" and (x.slot == 4 or x.slot == 5), "every hazard came inside an Archive room (4 or 5)") end
t.finish("escape-room-lab hazards", h)
