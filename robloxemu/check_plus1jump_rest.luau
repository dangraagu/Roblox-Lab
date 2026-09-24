-- +1 Jump Every Step — a queued rest survives the dodge the warning asks for. Run: luau check_plus1jump_rest.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17 (finding 6): EYECANDY promised "press Rest with a hazard inbound, step off its lane,
-- and the rest begins once the sky is clear". check_plus1_sky proved it by TELEPORTING the root part
-- aside with no movement input, which no player can do. Walked for real (MoveDirection held while the
-- character moves), Rest.update dropped the request on the first step, so the player who did exactly
-- what the warning said got no rest. This file walks the sidestep, through the real client script.
--
-- Headless limits: no physics. Walking is simulated by moving the root part while MoveDirection is set.

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
local Hz = Config.Hazards
-- Frequent hazards so the scenarios below do not wait minutes each (in-memory, this run only).
Hz.IntervalMin, Hz.IntervalMax = 12, 14

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local root = plr.PlayerGui:FindFirstChild("Plus1Sky"):FindFirstChild("Root")
local chip, restBtn, warning = root:FindFirstChild("BandChip"), root:FindFirstChild("RestButton"), root:FindFirstChild("HazardWarning")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

local hits = 0
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local v = hrp.AssemblyLinearVelocity
	if v and v.Magnitude > 1 then
		hits += 1
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end
local function run(seconds, dt, each)
	for _ = 1, math.floor(seconds / dt + 0.5) do
		frame(dt)
		if each and each() == false then return end
	end
end
local function hazardShown()
	for _, c in folder:GetChildren() do
		if string.match(c.Name, "^Hazard_([%a]+)_") then return true end
	end
	return false
end
local function moveToProgress(p)
	hrp.CFrame = CFrame.new(hrp.Position.X, Progression.yAtProgress(p, Config.Tower) + 3.5, hrp.Position.Z)
end

moveToProgress(26)
hrp.AssemblyLinearVelocity = Vector3.zero
run(2, 0.1)

-- walk half a tile away from the locked lane over 0.3 s, then let go of the stick
local function walkOffLane()
	local lane = folder:FindFirstChild("HazardLane")
	local dir = lane.CFrame.LookVector
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local perp = if flat.Magnitude > 1e-3 then Vector3.new(-flat.Z, 0, flat.X).Unit else Vector3.new(1, 0, 0)
	if (hrp.Position - lane.Position):Dot(perp) < 0 then perp = -perp end
	hum.MoveDirection = perp
	for _ = 1, 3 do
		hrp.CFrame = CFrame.new(hrp.Position + perp * 1.6)
		frame(0.1)
	end
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

local function nextHazard()
	hum.MoveDirection = Vector3.new(1, 0, 0) -- climbing input, so standing here never idles into rest
	run(Hz.IntervalMax + 10, 0.1, function() return not hazardShown() end)
	truthy(hazardShown(), "set-up: a hazard is inbound")
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

--======================================================================= (1) press Rest, WALK off the lane

nextHazard()
local hitsBefore = hits
restBtn.Activated:Fire()
run(0.2, 0.1)
eq(hum.Sit == true, false, "pressing Rest with a hazard inbound does not rest yet")
truthy(string.find(restBtn.Text, "…", 1, true) ~= nil, "the request is queued (" .. restBtn.Text .. ")")
local walked = false
run(8, 0.1, function()
	if not walked and warning.Visible and string.find(warning.Text, "MOVE!", 1, true) then
		walked = true
		walkOffLane()
	end
	return hazardShown()
end)
truthy(walked, "the climber saw MOVE! and WALKED off the lane (input held while moving)")
eq(hits, hitsBefore, "the walked sidestep dodged the hazard")
eq(hazardShown(), false, "the hazard has flown past")
run(1.5, 0.1)
eq(hum.Sit, true, "once the sky is clear, the queued rest begins for the player who walked aside")
truthy(string.find(chip.Text, "Resting", 1, true) ~= nil, "the chip says so (" .. chip.Text .. ")")
restBtn.Activated:Fire()
run(0.3, 0.1)
eq(hum.Sit == true, false, "pressing the button again ends it")

--======================================================================= (2) press Rest, dodge, then climb on

nextHazard()
hitsBefore = hits
restBtn.Activated:Fire()
run(0.2, 0.1)
walked = false
run(8, 0.1, function()
	if not walked and warning.Visible and string.find(warning.Text, "MOVE!", 1, true) then
		walked = true
		walkOffLane()
	end
	return hazardShown()
end)
eq(hits, hitsBefore, "set-up: dodged again")
hum.MoveDirection = Vector3.new(1, 0, 0) -- the sky is clear and the player keeps walking
run(2, 0.1)
eq(hum.Sit == true, false, "walking on under a clear sky drops the queued rest (they chose to keep climbing)")
truthy(string.find(restBtn.Text, "Rest", 1, true) ~= nil and string.find(restBtn.Text, "…", 1, true) == nil,
	"and the button is back to Rest (" .. restBtn.Text .. ")")
hum.MoveDirection = Vector3.new(0, 0, 0)
run(3, 0.1)
eq(hum.Sit == true, false, "a dropped request does not come back when they stop")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump rest: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump rest check failed", 0)
end
