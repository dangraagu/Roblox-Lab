-- Find It! Chapters: the hazards and the Pause, through the REAL server and client scripts (DESIGN.md §8, §9).
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_hazards.luau 2>&1
--
--   * the first drop comes after the arrival grace plus 100-140 s of exposed time, never two at once;
--   * the red ring IS the hit zone: standing still in it is a hit (a 0.6 s stumble, no look, no item, no star
--     taken); one step out of it, the moment it shows, is a dodge;
--   * the hazard clock freezes off a legal spot (the door mat) and while the attempt is not live (the intro, a
--     pause, a finished room), and it is never reset;
--   * the Pause: the HUD button rests, the server stops the chapter clock and refuses searches; a move wakes it and
--     the server re-dresses the room no sooner than 3 s after the pause; a pause asked for during a drop waits for
--     the drop (the hazard still comes), so the Pause is never a panic button.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-hazards", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
do
	local stars = {}
	for ch = 1, 14 do stars["c" .. ch] = { f = true, w = false, s = false } end
	DSS:GetDataStore("FindIt_Players_v1"):SetAsync("u_909", { data = { v = 1, book = { cleared = 14, stars = stars },
		daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 }, solved = 14, solvedAt = 1791000000, boarded = 14, seenIntro = true, firstJoin = 1791000000 } })
end
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Hazards = mod("Config"), mod("Hazards")
local Bus = mod("ClientBus")
local RunService = h.game:GetService("RunService")
local remotes = RS:FindFirstChild("FindItRemotes")
local Hz = Config.Hazards

local plr = h:join("Haz", 909)
h:advance(1)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Room.client"))
local hud = plr.PlayerGui:FindFirstChild("FindItHud").Root

local T = 0
local function frame(d)
	RunService.Heartbeat:Fire(d)
	RunService.RenderStepped:Fire(d)
	h:advance(d)
	T += d
end
local function stats()
	local s = {}
	Bus.fire("__stats", s)
	return s
end
local function last(name)
	local s = remotes:FindFirstChild(name):sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function ring() return ws.FindItLocalRoom:FindFirstChild("HazardRing") end
-- run until `cond()` or `limit` seconds; returns the seconds it took (or nil)
local function runUntil(limit, cond, step)
	step = step or 1 / 20
	local t = 0
	while t < limit do
		frame(step)
		t += step
		if cond() then return t end
	end
	return nil
end
local function run(seconds) runUntil(seconds, function() return false end) end

local function openRoom(ch)
	if last("State") and last("State").where == "room" then
		remotes.Hub:simulateFireServer(plr)
		run(1.1)
	end
	remotes.Open:simulateFireServer(plr, ch)
	run(0.1)
	local pl = last("Room")
	return pl, Vector3.new(pl.origin[1], pl.origin[2], pl.origin[3])
end
local function standLocal(o, x, z)
	hrp.CFrame = CFrame.new(o.X + x, 3, o.Z + z)
end

--============================================================ the first drop: grace + 100-140 s of exposed time
local pl, o = openRoom(15)
standLocal(o, 0, pl.D / 2)
local s0 = stats()
local firstAt = runUntil(200, function() return stats().scheduler.active ~= nil end)
truthy(firstAt ~= nil, "a drop comes in chapter 15's room")
local lo = Config.World.ArrivalGrace + Hz.IntervalMin
local hi = Config.World.ArrivalGrace + Hz.IntervalMax + 0.5
truthy(firstAt and firstAt >= lo - 0.2 and firstAt <= hi, string.format("the first drop came %.1f s after arrival (grace %d + %d-%d s)", firstAt or -1, Config.World.ArrivalGrace, Hz.IntervalMin, Hz.IntervalMax))
local plan = stats().scheduler.active
local spawnClock = stats().scheduler.clock
print(string.format("  the first drop: %.2f s after arrival", firstAt or -1))
-- the drop starts under the ceiling, straight above the player (ctx.pitch = rad(85)); a lane aimed from the camera's
-- pitch would start up to 11.6 studs to the side, through a wall (escape-room-lab trap 4)
do
	local aim = { x = hrp.Position.X, y = hrp.Position.Y, z = hrp.Position.Z }
	local up = plan.start.y - plan.target.y
	local side = math.sqrt((plan.start.x - aim.x) ^ 2 + (plan.start.z - aim.z) ^ 2)
	print(string.format("  the drop starts %.2f studs above the aim and %.2f to the side (ceiling at %d)", up, side, Config.Room.Height))
	truthy(up >= 11.5, string.format("the drop starts high above the player (%.2f studs)", up))
	truthy(side <= 2, string.format("and straight above (%.2f studs to the side, jitter included)", side))
	truthy(plan.start.y - o.Y <= Config.Room.Height, "under the ceiling")
end
eq(plan and plan.kind, "pebble", "the observatory's hazard is the meteorite pebble")

--============================================================ the ring is the hit zone: stand still -> hit
do
	local rp = ring()
	truthy(rp ~= nil, "the red ring shows the moment the drop is planned")
	local zone = Hazards.zone(plan, Hz.PlayerRadius)
	eq(rp and math.floor(rp.Size.Y * 100 + 0.5) / 100, 2 * (plan.hitRadius + Hz.PlayerRadius), "the ring's diameter is 2 x (hitRadius + PlayerRadius) = 7 studs")
	truthy(rp and math.abs(rp.Position.X - zone.x) < 1e-6 and math.abs(rp.Position.Z - zone.z) < 1e-6, "the ring is centred on the hit zone")
	truthy(rp and math.abs(rp.Position.X - hrp.Position.X) < 1e-6 and math.abs(rp.Position.Z - hrp.Position.Z) < 1e-6, "on the player's feet")
	truthy(rp and math.abs(rp.Color.R - 1) < 0.01 and rp.Color.G < 0.2, "and it is red")
	truthy(string.find(hud.Banner.Text.Text, "STEP OUT OF THE RING", 1, true) ~= nil, "the banner says STEP OUT OF THE RING")
	local looks0, found0 = last("State").looks, 0
	for _, f in last("State").found do if f then found0 += 1 end end
	local hitAt = runUntil(5, function() return stats().hits > s0.hits end)
	print(string.format("  standing still in the ring: hit %.2f s after the ring showed (arrival at %.1f s)", hitAt or -1, plan.arriveAt))
	truthy(hitAt ~= nil, "standing still in the ring is a hit")
	truthy(hitAt and hitAt <= plan.arriveAt, string.format("the hit lands %.2f s after the ring showed", hitAt or -1))
	eq(hum.PlatformStand, true, "a hit is a stumble (PlatformStand)")
	run(0.7)
	eq(hum.PlatformStand, false, "for KnockSeconds (0.6 s), then the player stands")
	eq(last("State").looks, looks0, "a hit takes no look")
	local found1 = 0
	for _, f in last("State").found do if f then found1 += 1 end end
	eq(found1, found0, "a hit takes no item")
	run(2)
	eq(ring(), nil, "the ring is gone after the drop")
end

--============================================================ one step out of the ring, the moment it shows: a dodge
do
	local hits0 = stats().hits
	local s = stats()
	local gap = s.scheduler.nextAt - spawnClock
	truthy(gap >= Hz.IntervalMin - 1e-6 and gap <= Hz.IntervalMax + 1e-6, string.format("the next drop is due %.1f s of exposed time after the first (%d-%d)", gap, Hz.IntervalMin, Hz.IntervalMax))
	local at = runUntil(Hz.IntervalMax + 10, function() return stats().scheduler.active ~= nil end)
	truthy(at ~= nil, "the second drop comes")
	-- one step: 4 studs sideways (the zone's radius is 3.5)
	hrp.CFrame = hrp.CFrame + Vector3.new(4, 0, 0)
	hum.MoveDirection = Vector3.new(1, 0, 0)
	frame(1 / 20)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	run(4)
	eq(stats().hits, hits0, "stepping out of the ring dodges")
	eq(stats().scheduler.active, nil, "the drop has passed")
end

--============================================================ never two at once; frozen off a legal spot and when not live
do
	-- the door mat is not a legal spot: an hour of standing there brings nothing
	local p2, o2 = openRoom(9)
	run(3.5)
	standLocal(o2, 0, 1.5)
	local c0 = stats().scheduler.clock
	local spawned0 = stats().hazards
	run(150)
	eq(stats().hazards, spawned0, "no drop on the door mat (not a legal spot)")
	truthy(math.abs(stats().scheduler.clock - c0) < 1e-6, "the hazard clock does not run there (frozen, not reset)")
	-- time's up: the room is done, the clock freezes
	run(math.max(0, Config.Chapters[9].clock - 150 + 1))
	eq(last("State").state, "done", "the room timed out")
	standLocal(o2, 0, p2.D / 2)
	local c1 = stats().scheduler.clock
	run(30)
	truthy(math.abs(stats().scheduler.clock - c1) < 1e-6, "a finished room runs no hazard clock")
	-- the intro card: no exposure
	remotes.Retry:simulateFireServer(plr)
	run(0.1)
	eq(last("State").state, "intro", "a retry starts on its card")
	local c2 = stats().scheduler.clock
	run(1)
	truthy(math.abs(stats().scheduler.clock - c2) < 1e-6, "no hazard clock during the intro card")
end

--============================================================ the Pause: rest, a stopped clock, a refused search, the re-dress
do
	local p3, o3 = openRoom(6)
	standLocal(o3, 0, p3.D / 2)
	run(6)
	eq(last("State").state, "live", "chapter 6 is live")
	local clock0 = last("State").clock
	local hz0 = stats().scheduler.clock
	hud.PauseButton.Activated:Fire()
	run(0.2)
	eq(last("State").state, "paused", "the Pause button pauses the attempt on the server")
	truthy(stats().rest.resting, "the client is resting")
	truthy(hud.Card.Visible and string.find(hud.Card.Sub.Text, "clock is stopped", 1, true) ~= nil, "the paused card says the clock is stopped and things get moved")
	run(20)
	local stP = last("State")
	truthy(math.abs(stP.clock - clock0) < 0.25, string.format("the chapter clock is stopped (%.2f -> %.2f)", clock0, stP.clock))
	truthy(math.abs(stats().scheduler.clock - hz0) < 0.25, "the hazard clock is frozen too (never reset)")
	local toasts = #remotes.Toast:sentTo(plr)
	remotes.Search:simulateFireServer(plr, p3.props[1].id)
	run(0.1)
	eq(last("Toast").text, Config.Text.OnBreak, "a search while paused: 'You're on a break: move or tap Resume'")
	-- a move wakes it; the server re-dresses
	local rooms0 = #remotes.Room:sentTo(plr)
	hum.MoveDirection = Vector3.new(0, 0, 1)
	run(0.6)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	run(0.5)
	eq(last("State").state, "live", "a move wakes the Pause and the room is live again")
	eq(#remotes.Room:sentTo(plr), rooms0 + 1, "the server re-dressed the room on Resume")
	truthy(last("Room").redress == true and last("Room").idBase > p3.idBase, "every prop moved (new ids)")
	-- REVIEW-1 A4: right after a re-dress the next Pause is refused in words (no rest, the clock keeps running)
	local clockR = last("State").clock
	hud.PauseButton.Activated:Fire()
	run(0.2)
	eq(last("State").state, "live", "a Pause right after a re-dress is refused: the room stays live")
	truthy(not stats().rest.resting, "a refused Pause does not rest the client")
	truthy(hud.Banner.Visible and string.find(hud.Banner.Text.Text, "pause again in", 1, true) ~= nil,
		"the refused Pause says when it can pause again: " .. tostring(hud.Banner.Text.Text))
	-- the door mat runs no hazard clock, so nothing drops while the window runs out
	standLocal(o3, 0, 1)
	run(Config.Pause.EverySeconds + 1)
	truthy(last("State").clock - clockR >= Config.Pause.EverySeconds, "the attempt clock ran through the pause window")
	-- a Resume sooner than 3 s after the Pause waits until 3 s
	hud.PauseButton.Activated:Fire()
	run(0.2)
	eq(last("State").state, "paused", "paused again once Pause.EverySeconds of clock has run")
	local pausedAt = T
	remotes.Resume:simulateFireServer(plr)
	local waited = runUntil(5, function() return last("State").state == "live" end, 0.05)
	truthy(waited and waited >= Config.Pause.ResumeMinSeconds - 0.3, string.format("a Resume 0.2 s after the Pause lands %.2f s later (>= %d s after the Pause)", (waited or 0) + 0.2, Config.Pause.ResumeMinSeconds))
end

--============================================================ a Pause asked for during a drop waits for the drop
do
	local p4, o4 = openRoom(10)
	standLocal(o4, 0, p4.D / 2)
	local at = runUntil(170, function() return stats().scheduler.active ~= nil end)
	truthy(at ~= nil, "a drop comes in chapter 10")
	local hits0 = stats().hits
	hud.PauseButton.Activated:Fire()
	run(0.1)
	truthy(stats().rest.pending and not stats().rest.resting, "the Pause is queued while the drop is on its way")
	truthy(last("State").state == "live", "the server is not paused yet")
	truthy(string.find(hud.Banner.Text.Text, "STEP OUT", 1, true) ~= nil, "the warning still shows")
	run(4)
	truthy(stats().hits > hits0, "the drop still comes (the Pause is not a panic button)")
	run(1.5)
	eq(last("State").state, "paused", "after the drop, standing still, the Pause starts")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	failed += 1
	print("FAIL: a warning: " .. w)
end
print(string.format("find it hazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_hazards failed", 0) end
