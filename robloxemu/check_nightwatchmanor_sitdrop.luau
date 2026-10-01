-- Nightwatch Manor — the ☕ Rest button's sit survives the sit's own drop. Run: luau check_nightwatchmanor_sitdrop.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- Found in real Studio on 2026-09-27 in +1 Jump (commit ad62955, docs/night-queue.md), and filed against this game by
-- its second reviewer (2026-09-30, HIGH): a Humanoid sat down without a seat drops onto the floor. For about 0.3 s its
-- root falls (vy -3 .. -26 studs/s), bounces (+9) and settles to 0, and FloorMaterial reads Air the whole time it is
-- seated. Haunt.client counted "seated and |vy| >= 2" as falling, so the first frame of the drop ended the rest: the
-- avatar stood straight back up and the chip went back to the band. check_nightwatchmanor_rest never saw it, because
-- the emulator has no physics. This check replays the measured Studio trace (Heartbeat, ~60 Hz) frame by frame
-- through the REAL server and the REAL clients:
--   1. pressing ☕ Rest in the safehouse: the avatar is still sitting after the drop, and for the next 20 s;
--   2. walk input still wakes a seated rest;
--   3. a rest that was QUEUED (Rest pressed in mid-air) starts on landing, and its sit survives the drop too;
--   4. a real, sustained fall while seated still ends the rest (the settle window is short, not a free pass).
--
-- Headless limits: no physics. The drop is replayed from the Studio trace; the physics step is modelled as landing
-- between two frames (the client sets Sit in one frame, the next frame sees the drop).

local Kit = require("./check_nightwatchmanor_kit")

local ctx = Kit.boot({ name = "nwm-sitdrop", profile = { night = 3, stash = 50, best = 2, levels = {} } })
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy

-- The Studio trace (2026-09-27): the root's vertical velocity on successive Heartbeat frames after Sit = true.
local DROP = { -3.27, -6.54, -9.81, -13.08, -16.35, -19.62, -22.89, -26.16, 8.91, 5.64, 2.37, -0.90, -4.17, -7.44, 3.46, 0.19 }
local DT = 1 / 60
local physics = "floor" -- "floor" | "air" (in the air, not seated: a jump) | "fall" (a sustained fall)
local sitFrames = 0 -- frames since the sit began (the drop's clock)
ctx.onFrame = function()
	-- the physics step after this frame's scripts: what the NEXT frame's client reads
	if ctx.hum.Sit == true and physics ~= "fall" then
		sitFrames += 1
		ctx.hum.FloorMaterial = Enum.Material.Air -- a seated Humanoid reports Air (measured)
		ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, DROP[sitFrames] or 0, 0)
	elseif physics == "fall" then
		ctx.hum.FloorMaterial = Enum.Material.Air
		ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, -40, 0)
	elseif physics == "air" then
		sitFrames = 0
		ctx.hum.FloorMaterial = Enum.Material.Air
		ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, 12, 0)
	else
		sitFrames = 0
		ctx.hum.FloorMaterial = Enum.Material.WoodPlanks
		ctx.hrp.AssemblyLinearVelocity = Vector3.zero
	end
end
local function run(seconds: number)
	ctx.frames(math.floor(seconds / DT + 0.5), DT)
end
local function resting(): boolean
	return string.find(ctx.chip.Text, "Resting", 1, true) ~= nil
end

run(2)
eq((ctx.lastState() or {}).phase, "DAY", "CONTROL: the player is in the safehouse")
truthy(ctx.restBtn.Visible, "CONTROL: the Rest button is offered")
truthy(not resting(), "CONTROL: not resting yet (" .. ctx.chip.Text .. ")")

--================================================================ 1. the sit's drop does not wake the rest

ctx.restBtn.Activated:Fire()
local seated, restingFrames = 0, 0
for _ = 1, 120 do
	run(DT)
	if ctx.hum.Sit == true then seated += 1 end
	if resting() then restingFrames += 1 end
end
print(string.format("  after pressing Rest: seated on %d of 120 frames, the chip said Resting on %d (%s)", seated, restingFrames, ctx.chip.Text))
eq(seated, 120, "after pressing Rest and the sit's measured drop, the avatar sits on every one of the next 120 frames")
eq(restingFrames, 120, "and the chip says Resting on every one of them")
eq(ctx.restBtn.Text, "▶ Up", "the button offers to get up (" .. ctx.restBtn.Text .. ")")
local focus = h.Lighting:FindFirstChild("NightwatchRestFocus")
truthy(focus ~= nil and focus.Enabled, "the view is softened")
run(20)
eq(ctx.hum.Sit, true, "and it stays sitting while nothing moves (20 s)")
truthy(resting(), "still resting after 20 s (" .. ctx.chip.Text .. ")")

--================================================================ 2. moving still wakes it

ctx.hum.MoveDirection = Vector3.new(1, 0, 0)
run(0.5)
eq(ctx.hum.Sit == true, false, "walk input wakes a seated rest")
truthy(not resting(), "and the chip is the band again (" .. ctx.chip.Text .. ")")
ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
run(1)

--================================================================ 3. a queued rest (pressed in mid-air) survives the drop too

physics = "air"
run(0.2)
ctx.restBtn.Activated:Fire()
run(0.2)
eq(ctx.hum.Sit == true, false, "CONTROL: pressed in mid-air, the rest is queued, not started")
eq(ctx.restBtn.Text, "☕ …", "CONTROL: the button shows the queued rest (" .. ctx.restBtn.Text .. ")")
physics = "floor"
local qSeated = 0
for _ = 1, 120 do
	run(DT)
	if ctx.hum.Sit == true then qSeated += 1 end
end
truthy(qSeated >= 110, string.format("on landing the queued rest sits you down and the drop does not stand you up (seated %d of 120 frames)", qSeated))
eq(ctx.hum.Sit, true, "still sitting 2 s after landing")
truthy(resting(), "and the chip says Resting (" .. ctx.chip.Text .. ")")
ctx.restBtn.Activated:Fire()
run(0.5)
eq(ctx.hum.Sit == true, false, "▶ Up gets you up")

--================================================================ 4. a real fall while seated still ends the rest

run(1)
ctx.restBtn.Activated:Fire()
run(1.5)
eq(ctx.hum.Sit, true, "set-up: resting again after the drop")
physics = "fall"
run(1.5) -- 1.5 s of a sustained fall, far longer than any sit's drop
physics = "floor"
eq(ctx.hum.Sit == true, false, "a sustained fall while seated still ends the rest")
truthy(not resting(), "and the chip says so (" .. ctx.chip.Text .. ")")

eq(ctx.serverCalls, 0, "the client never fired a remote")
ctx.finish("nightwatchmanor sitdrop")
