-- +1 Jump Every Step — the Rest button's sit survives the sit's own drop. Run: luau check_plus1jump_sitdrop.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Found in real Studio on 2026-09-27 (night shift, job H). Pressing ☕ Rest set Humanoid.Sit = true,
-- the chip said "Resting", and 20 ms later the rest ended and the avatar stood up again. Measured in
-- Studio with a Heartbeat trace: a Humanoid sat down without a seat drops onto the floor, so for about
-- 0.3 s its root falls (vy -3 .. -26 studs/s), bounces (+9) and settles to 0, and FloorMaterial reads
-- Air the whole time it is seated. Sky.client treated "seated and |vy| >= 2" as falling, so the first
-- frame of the drop woke the rest. The emulator has no physics, so no check saw it. This file replays
-- the measured trace through the real client script.
--
-- Headless limits: no physics. The sit's drop is replayed from the Studio trace, frame by frame.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local Progression = mod("Progression")

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Sitter", 4343)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local root = plr.PlayerGui:FindFirstChild("Plus1Sky"):FindFirstChild("Root")
local chip, restBtn = root:FindFirstChild("BandChip"), root:FindFirstChild("RestButton")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

-- The Studio trace (Heartbeat, ~60 Hz) of the root's vertical velocity after Sit = true on a Slate pad.
local DROP = { -3.27, -6.54, -9.81, -13.08, -16.35, -19.62, -22.89, -26.16, 8.91, 5.64, 2.37, -0.90, -4.17, -7.44, 3.46, 0.19 }
local sitFrame = nil
local dt = 1 / 60
local function frame()
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	if hum.Sit == true then
		sitFrame = (sitFrame or 0) + 1
		hum.FloorMaterial = Enum.Material.Air -- a seated Humanoid reports Air (measured)
		hrp.AssemblyLinearVelocity = Vector3.new(0, DROP[sitFrame] or 0, 0)
	else
		sitFrame = nil
		hum.FloorMaterial = Enum.Material.Slate
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds)
	for _ = 1, math.floor(seconds / dt + 0.5) do frame() end
end

hrp.CFrame = CFrame.new(0, Progression.yAtProgress(0.5, Config.Tower) + 3.5, 0)
run(2)

--======================================================================= (1) the sit's drop does not wake the rest

restBtn.Activated:Fire()
run(2)
eq(hum.Sit, true, "after pressing Rest and the sit's measured drop, the avatar is still sitting")
truthy(string.find(chip.Text, "Resting", 1, true) ~= nil, "the chip still says Resting (" .. chip.Text .. ")")
truthy(string.find(restBtn.Text, "Climb", 1, true) ~= nil, "the button offers Climb (" .. restBtn.Text .. ")")
run(20)
eq(hum.Sit, true, "and it stays sitting while nothing moves (20 s)")

--======================================================================= (2) moving still wakes it

hum.MoveDirection = Vector3.new(1, 0, 0)
run(0.5)
eq(hum.Sit == true, false, "walk input wakes a seated rest")
hum.MoveDirection = Vector3.new(0, 0, 0)
run(1)

--======================================================================= (3) a real fall while seated still wakes it

restBtn.Activated:Fire()
run(1.5)
eq(hum.Sit, true, "set-up: resting again after the drop")
hum.Sit = true
for _ = 1, 90 do -- 1.5 s of a sustained fall, far longer than any sit's drop
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	hum.FloorMaterial = Enum.Material.Air
	hrp.AssemblyLinearVelocity = Vector3.new(0, -40, 0)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
eq(hum.Sit == true, false, "a sustained fall while seated still ends the rest")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump sitdrop: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump sitdrop check failed", 0)
end
