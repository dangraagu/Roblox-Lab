-- +1 Jump Every Step — hazards are ON SCREEN while they warn, at the camera angles climbers use, and
-- never launch at an airborne player. Run: luau check_plus1jump_hazards.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17:
--   finding 1: the lane only started within ±50° of the camera's HEADING. Its climb angle came from the
--     hazard kind alone, so a weather balloon rising from -55° was never on the screen of a climber
--     looking up at the next platform (44 studs up), and a rocket stage or comet from above was never on
--     the screen of one looking down. check_plus1_sky counted a hazard as "visible" once its model
--     existed, not whether the camera could see it. Here the model is projected through the camera.
--   finding 8: replacing `grounded = grounded` with `grounded = true` in Sky.client passed every suite.
--     The rule "a hazard only launches while you stand on something" is exercised through the client.
--
-- Headless limits: nothing renders. "On screen" = the centre of the hazard model's parts projects inside
-- the camera's view: Roblox's default 70-degree vertical FOV at the emulated viewport, minus 2 degrees.

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
local EnvBands = mod("EnvBands")
local Hz = Config.Hazards
local bands = Config.Env.Bands
Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in-memory, this run only: many hazards in a short check

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0) -- climbing input: never idles into rest
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local warning = plr.PlayerGui:FindFirstChild("Plus1Sky"):FindFirstChild("Root"):FindFirstChild("HazardWarning")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

local look = Vector3.new(0, 0, 1)
local camDist = 16
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position - look * camDist, hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	hrp.AssemblyLinearVelocity = Vector3.zero -- a hit is not the subject here; keep the climber in place
end
local function moveToProgress(p)
	hrp.CFrame = CFrame.new(0, Progression.yAtProgress(p, Config.Tower) + 3.5, 0)
end
local function hazardCentre()
	local kind, sum, n = nil, Vector3.zero, 0
	for _, c in folder:GetChildren() do
		local k = string.match(c.Name, "^Hazard_([%a]+)_")
		if k and c:IsA("BasePart") then
			kind = k
			sum += c.Position
			n += 1
		end
	end
	if n == 0 then return nil, nil end
	return sum / n, kind
end
local function onScreen(p)
	local v = cam.ViewportSize
	local cf = cam.CFrame
	local rel = p - cf.Position
	local depth = rel:Dot(cf.LookVector)
	if depth <= 0 then return false end
	local x = rel:Dot(cf.RightVector) / depth
	local y = rel:Dot(cf.UpVector) / depth
	local tv = math.tan(math.rad(35))
	local th = tv * v.X / v.Y
	local margin = math.tan(math.rad(2))
	return math.abs(x) <= th - margin and math.abs(y) <= tv - margin
end

--======================================================================= finding 1: on screen while warning

local results = {}
local function sweep(bandId, pitchDeg, viewport)
	h:setViewport(viewport[1], viewport[2])
	local b = bands[EnvBands.indexOf(bands, bandId)]
	local mid = b.from + 3
	moveToProgress(mid)
	local seen, framesOn, framesOff, kinds, example = 0, 0, 0, {}, nil
	local yawDeg = 0
	local wasShown = false
	for _ = 1, 400 * 10 do -- up to 400 s
		local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
		look = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
		frame(0.1)
		local centre, kind = hazardCentre()
		if centre and not wasShown then
			seen += 1
			kinds[kind] = true
		end
		wasShown = centre ~= nil
		if centre and warning.Visible and string.find(warning.Text, "INCOMING", 1, true) then
			if onScreen(centre) then framesOn += 1 else
				framesOff += 1
				example = example or kind
			end
		end
		if centre == nil then
			yawDeg = (yawDeg + 7) % 360 -- turn the camera a little between hazards
		end
		if seen >= 8 and centre == nil then break end
	end
	local kindList = {}
	for k in kinds do table.insert(kindList, k) end
	table.sort(kindList)
	local label = string.format("%s, camera pitch %+d, %dx%d", bandId, pitchDeg, viewport[1], viewport[2])
	print(string.format("  %-44s hazards %d (%s)  warning frames on screen %d, off %d", label, seen, table.concat(kindList, ","), framesOn, framesOff))
	table.insert(results, { label = label, seen = seen, off = framesOff, on = framesOn, example = example })
end

for _, bandId in { "storm", "edge", "galaxy" } do
	for _, pitch in { -40, -20, 0, 20, 40 } do
		sweep(bandId, pitch, { 1280, 720 })
	end
	sweep(bandId, 35, { 1024, 768 })
	sweep(bandId, -35, { 1024, 768 })
end
h:setViewport(1280, 720)

do
	local worst = nil
	local fewest = math.huge
	for _, r in results do
		if r.off > 0 then worst = r.label .. " (" .. tostring(r.example) .. ", " .. r.off .. " frames off screen)" end
		if r.seen < fewest then fewest = r.seen end
	end
	truthy(fewest >= 6, "every sweep saw several hazards (fewest " .. fewest .. ")")
	eq(worst, nil, "while the warning says INCOMING, the hazard is on screen at every camera pitch and screen shape")
end

--======================================================================= finding 8: never at an airborne player

do
	look = Vector3.new(0, -0.3, 1).Unit
	moveToProgress(26)
	-- let any hazard in flight finish
	for _ = 1, 200 do
		frame(0.1)
		if hazardCentre() == nil and not warning.Visible then break end
	end
	hum.FloorMaterial = Enum.Material.Air -- in the air (a long fall, a jump that never lands in this check)
	hum.MoveDirection = Vector3.new(1, 0, 0)
	local launchedInAir = 0
	for _ = 1, (Hz.IntervalMax + 20) * 10 do
		frame(0.1)
		if hazardCentre() ~= nil then launchedInAir += 1 end
	end
	eq(launchedInAir, 0, "no hazard launches while the climber is off the ground, however long it is due")
	hum.FloorMaterial = Enum.Material.Plastic
	local landedAfter = nil
	for i = 1, 20 do
		frame(0.1)
		if hazardCentre() ~= nil then landedAfter = i * 0.1; break end
	end
	truthy(landedAfter ~= nil, "and the due hazard launches as soon as they stand on something (" .. tostring(landedAfter) .. " s)")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump hazards: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump hazards check failed", 0)
end
