-- anomaly-observatory — the telescope break (what "rest" means here), through the REAL client.
-- Run: luau check_anomalyobservatory_rest.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- A Roblox server cannot pause, and this game has nothing to pause: no clock inside a pass (the
-- server's MIN_PASS_SECONDS is a floor against bots, not a timer), no chaser, no hazard. So a break is
-- the player stepping out to the telescope: the local camera fades to a view beyond the hall's
-- entrance, looking up and away from every hall, and fades back when they move or press the button.
-- This file proves, with the server and both client scripts running, that a break:
--
--   1. changes NOTHING the game depends on: no remote is fired, the pass (Serial, roll, the zone's
--      every BasePart), the Day, the character and the humanoid are exactly as before, after a
--      10-minute break; the same pass is still live and scores when answered afterwards;
--   2. cannot be used to look at the hall: on every frame the camera is out, it is beyond the
--      entrance plane and every ray of its frustum heads away (+Z), measured on 16:9, a 32:9
--      ultrawide and a portrait phone. The hall is sealed everywhere else, so no hall is visible;
--   3. never shows the hall differently: Lighting differs from the server's preset, and the break's
--      grade is on, ONLY on frames where the camera is out; the camera moves out and back only on a
--      fully black frame; afterwards camera type, CFrame and field of view are exactly restored;
--   4. ends on movement, on a jump, on the button, on the B key, on a wrong call's death beat and on
--      a respawn (the new character is standing still, so nothing but the respawn can end it);
--      cannot START during the death beat (it queues, and starts only after the beat), and a queued
--      break is dropped when the player walks on;
--   5. does not fight another camera owner (a cutscene or the capture rig: CameraType Scriptable);
--   6. never re-enables its ScreenGui after the capture rig switched every gui off.

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")

local Sky = Config.Sky

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
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

assert(h:tryRun("server/Main.server"))
local Lighting = h.Lighting
local function lightingPrint(): string
	local rows = {}
	for _, k in { "Ambient", "OutdoorAmbient", "Brightness", "ExposureCompensation", "ClockTime", "EnvironmentDiffuseScale",
		"EnvironmentSpecularScale", "Technology" } do
		table.insert(rows, k .. "=" .. tostring(Lighting[k]))
	end
	for _, c in Lighting:GetChildren() do
		local props = {}
		for _, k in { "Density", "Offset", "Color", "Decay", "Glare", "Haze", "Intensity", "Size", "Threshold", "Brightness",
			"Contrast", "Saturation", "TintColor", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity", "Enabled",
			"CelestialBodiesShown", "StarCount" } do
			local ok, v = pcall(function() return c[k] end)
			if ok and v ~= nil then table.insert(props, k .. "=" .. tostring(v)) end
		end
		table.sort(props)
		table.insert(rows, c.ClassName .. ":" .. c.Name .. "{" .. table.concat(props, ",") .. "}")
	end
	table.sort(rows)
	return table.concat(rows, "|")
end
local serverLighting = lightingPrint()

local remotes = h.ReplicatedStorage:FindFirstChild("AnomalyRemotes")
local serverCalls = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local UIS = h.game:GetService("UserInputService")

local plr = h:join("Resting", 27182)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
local hrp = char:FindFirstChild("HumanoidRootPart")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)

assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))
-- (review 2026-09-24) The sky client adds ONE thing to Lighting at start, and never touches it again:
-- a Sky with no sun or moon drawn, so Roblox's default (phaseless, full) moon cannot hang behind the
-- phased one. That is the only difference from the server's preset; from here on it is the baseline
-- a break must restore. check_anomalyobservatory_sky asserts the Sky itself on every frame.
do
	local before, after = {}, {}
	for row in string.gmatch(serverLighting, "[^|]+") do before[row] = true end
	local added, lost = {}, {}
	for row in string.gmatch(lightingPrint(), "[^|]+") do
		after[row] = true
		if not before[row] then table.insert(added, row) end
	end
	for row in string.gmatch(serverLighting, "[^|]+") do
		if not after[row] then table.insert(lost, row) end
	end
	truthy(#added == 1 and string.sub(added[1], 1, 4) == "Sky:" and #lost == 0,
		"starting the sky client adds exactly one Sky to Lighting and changes nothing else: +" .. table.concat(added, ",") .. " -" .. table.concat(lost, ","))
	serverLighting = lightingPrint()
end

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local origin = NightSky.hallOrigin(Sky.Hall, tonumber(zone:GetAttribute("Index")))
local skyGui = plr.PlayerGui:FindFirstChild("ObservatorySky")
local breakBtn = skyGui.Root:FindFirstChild("BreakButton")
local caption = skyGui.Root:FindFirstChild("SkyCaption")
local fadeFrame = skyGui:FindFirstChild("BreakFade")
truthy(breakBtn ~= nil and caption ~= nil and fadeFrame ~= nil, "the break button, caption and fade exist")

local cam = h.workspace.CurrentCamera
local originalType = cam.CameraType
local hallCam = CFrame.lookAt(Vector3.new(origin.x, origin.y + 8, origin.z + 6), Vector3.new(origin.x, origin.y + 6, origin.z - 80))
cam.CFrame = hallCam

local function infoOf()
	return h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId))
end
local function day(): number
	return plr.leaderstats.Day.Value
end
local function hallPrint(): string
	local rows = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			table.insert(rows, string.format("%s|%s|%s|%d,%d,%d|%.2f|%.2f|%s", d.Name, tostring(d.CFrame), tostring(d.Size),
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
				d.Transparency, d.Reflectance, tostring(d.Material)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end
local function humPrint(): string
	return string.format("%s|%s|%s|%s|%s|%s", tostring(hum.WalkSpeed), tostring(hum.JumpPower), tostring(hum.Sit),
		tostring(hum.PlatformStand), tostring(hum.Health), tostring(hrp.CFrame))
end

-- ------------------------------------------------------------------ frames, with the invariants
local camOut = function(): boolean
	return cam.CFrame.Position.Z - origin.z > Sky.Hall.Front + Sky.Clearance
end
local outFrames, badGrade, badLighting, badRay, badSwap, badType = 0, 0, 0, 0, 0, 0
local worstRay = math.huge
local wasScriptable = false
local checkOwnsCamera = false -- section 5: this file plays another camera owner
local yawMin, yawMax = math.huge, -math.huge
local function grade()
	return cam:FindFirstChild("ObservatoryBreakGrade")
end

local DT = 1 / 30
local function frame(dt: number?)
	local step = dt or DT
	-- this file plays Roblox's default camera: it follows the character unless someone scripts it
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = hallCam
	end
	RunService.RenderStepped:Fire(step)
	h:advance(step)

	local out = camOut()
	local g = grade()
	if g and g.Enabled and not out then badGrade += 1 end
	if lightingPrint() ~= serverLighting and not out then badLighting += 1 end
	local scripted = cam.CameraType == Enum.CameraType.Scriptable
	if scripted ~= wasScriptable and not checkOwnsCamera then
		-- the camera went out or came back: the screen must be fully black on that frame
		if not (fadeFrame.Visible and fadeFrame.BackgroundTransparency <= 1e-6) then badSwap += 1 end
		wasScriptable = scripted
	end
	if scripted and not out and not checkOwnsCamera then badType += 1 end
	if out then
		outFrames += 1
		local look = cam.CFrame.LookVector
		local v = cam.ViewportSize
		local z = NightSky.minRayZ({ x = look.X, y = look.Y, z = look.Z }, cam.FieldOfView, v.X / v.Y)
		if z < worstRay then worstRay = z end
		if z <= 0 then badRay += 1 end
		local yaw = math.deg(math.atan2(look.X, look.Z))
		yawMin, yawMax = math.min(yawMin, yaw), math.max(yawMax, yaw)
	end
end
local function run(seconds: number, dt: number?)
	local step = dt or DT
	for _ = 1, math.floor(seconds / step + 0.5) do frame(step) end
end

local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function answer(right: boolean)
	local clean = infoOf():GetAttribute("Clean")
	local advance = (clean == true) == right
	local pad = zone:FindFirstChild(if advance then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8)
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
end
local function pressB()
	UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.B, UserInputType = Enum.UserInputType.Keyboard }, false)
end

-- Up to Day 3, and let the sky settle.
run(14)
answer(true)
run(2)
answer(true)
run(14)
eq(day(), 3, "the player is on Day 3")

-- ------------------------------------------------------------------ 1. a ten-minute break changes nothing
local serial0 = infoOf():GetAttribute("Serial")
local clean0 = infoOf():GetAttribute("Clean")
local id0 = infoOf():GetAttribute("AnomalyId")
local hall0 = hallPrint()
local hum0 = humPrint()
local fov0 = cam.FieldOfView
local calls0 = serverCalls

breakBtn.Activated:Fire()
run(1)
truthy(cam.CameraType == Enum.CameraType.Scriptable and camOut(), "pressing Break takes the camera out to the telescope")
-- (review 2026-09-24) This line used to REQUIRE "Day 3" in the caption, which was the caption saying
-- "Day 3 is safe". It is not: the streak lives only in the server's memory for this session, and
-- Roblox disconnects a player idle for ~20 minutes (a break IS a player not touching the controls),
-- which starts a new session at Day 1. The caption now promises nothing it cannot keep, and warns
-- once Roblox reports the player idle (Player.Idled).
local function capHas(s: string): boolean
	return string.find(caption.Text, s, 1, true) ~= nil
end
truthy(caption.Visible and caption.Text ~= "", "the break has a caption: " .. caption.Text)
truthy(not string.find(string.lower(caption.Text), "safe", 1, true), "the break caption does not promise the Day is safe: " .. caption.Text)
truthy(not string.find(string.lower(caption.Text), "disconnect", 1, true), "and does not alarm a player who is not idle: " .. caption.Text)
truthy(string.find(breakBtn.Text, "Back", 1, true) ~= nil, "the button now reads Back: " .. breakBtn.Text)
plr.Idled:Fire(120) -- Roblox: the player has been idle for two minutes
run(0.5)
truthy(capHas("20") and capHas("Day 1") and capHas("Day 3"),
	"once Roblox reports the player idle, the caption says a 20-minute idle disconnect starts over at Day 1, and names Day 3: " .. caption.Text)
truthy(not string.find(string.lower(caption.Text), "safe", 1, true), "and still promises nothing: " .. caption.Text)
run(600, 0.1) -- ten minutes on the roof
truthy(capHas("Day 1") and capHas("20"), "the warning stays up for as long as nobody touches anything: " .. caption.Text)
UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, KeyCode = Enum.KeyCode.Unknown }, false)
run(0.5)
truthy(not string.find(string.lower(caption.Text), "disconnect", 1, true) and caption.Text ~= "",
	"any input (a mouse move) clears the warning: " .. caption.Text)
truthy(cam.CameraType == Enum.CameraType.Scriptable and camOut(), "and a mouse move does not end the break (only moving the character does)")
truthy(yawMax - yawMin > 8, string.format("the telescope drifts slowly (yaw %.1f..%.1f)", yawMin, yawMax))
eq(serverCalls - calls0, 0, "a 10-minute break fires no remote")
eq(infoOf():GetAttribute("Serial"), serial0, "the pass is the same pass (Serial)")
eq(infoOf():GetAttribute("Clean"), clean0, "with the same roll (Clean)")
eq(infoOf():GetAttribute("AnomalyId"), id0, "and the same anomaly id")
eq(hallPrint(), hall0, "every BasePart of the hall is exactly as it was")
eq(day(), 3, "the Day is untouched")
eq(humPrint(), hum0, "the character and humanoid are untouched")

-- move to wake
hum.MoveDirection = Vector3.new(0, 0, -1)
run(1.2)
hum.MoveDirection = Vector3.new(0, 0, 0)
run(0.5)
eq(cam.CameraType, originalType, "moving ends the break: camera type restored")
eq(tostring(cam.CFrame), tostring(hallCam), "the camera CFrame is exactly where it was")
eq(cam.FieldOfView, fov0, "the field of view is restored")
eq(lightingPrint(), serverLighting, "Lighting is exactly the server's preset again")
truthy(grade() == nil or grade().Enabled == false, "the break grade is off")
truthy(string.find(breakBtn.Text, "Break", 1, true) ~= nil, "the button reads Break again: " .. breakBtn.Text)

-- the same pass is still live and scores
answer(true)
run(1)
eq(day(), 4, "the pass that was live before the break is answered and scored afterwards (Day 4)")
eq(infoOf():GetAttribute("Serial"), serial0 + 1, "and the next pass is the next serial: nothing was skipped or re-rolled")

-- ------------------------------------------------------------------ 2. every way to end a break
local function isOut(): boolean
	return cam.CameraType == Enum.CameraType.Scriptable and camOut()
end
local function backHome(): boolean
	return cam.CameraType == originalType and tostring(cam.CFrame) == tostring(hallCam) and lightingPrint() == serverLighting
end

breakBtn.Activated:Fire()
run(1)
truthy(isOut(), "button: out")
breakBtn.Activated:Fire()
run(1)
truthy(backHome(), "button: back, everything restored")

pressB()
run(1)
truthy(isOut(), "B key: out")
pressB()
run(1)
truthy(backHome(), "B key: back")

breakBtn.Activated:Fire()
run(1)
truthy(isOut(), "jump test: out")
hum.FloorMaterial = Enum.Material.Air -- a jump leaves the ground
run(1)
hum.FloorMaterial = Enum.Material.Plastic
run(0.5)
truthy(backHome(), "a jump ends the break")

-- asked for mid-air: queued, starts on landing
hum.FloorMaterial = Enum.Material.Air
breakBtn.Activated:Fire()
run(0.5)
truthy(not isOut(), "a break asked for mid-air does not start in the air")
hum.FloorMaterial = Enum.Material.Plastic
run(1.2)
truthy(isOut(), "and starts once the player stands still on the floor")
breakBtn.Activated:Fire()
run(1)
truthy(backHome(), "back")

-- ------------------------------------------------------------------ 3. the death beat
-- a wrong call: the break cannot start during the beat, it queues and starts after
answer(false)
run(0.1)
eq(day(), 1, "the wrong call reset the Day")
breakBtn.Activated:Fire()
run(0.1)
truthy(string.find(caption.Text, "queued", 1, true) ~= nil, "during the death beat the break is queued, and says so: " .. caption.Text)
local outDuringBeat = false
for _ = 1, math.floor(2.8 / DT) do
	frame()
	if isOut() then outDuringBeat = true end
end
truthy(not outDuringBeat, "the camera never leaves during the death beat")
run(1.5)
truthy(isOut(), "the queued break starts after the beat is over")
eq(day(), 1, "(the new pass began meanwhile, on Day 1)")
breakBtn.Activated:Fire()
run(1)
truthy(backHome(), "back")

-- a break in progress ends for a death beat (a wrong call answered while away)
breakBtn.Activated:Fire()
run(1)
truthy(isOut(), "out again")
answer(false)
run(1)
truthy(backHome(), "a wrong call's death beat ends the break and brings the camera home")
run(3)

-- a queued break is dropped when the player walks on after the beat
answer(false)
run(0.1)
breakBtn.Activated:Fire()
run(0.1)
hum.MoveDirection = Vector3.new(0, 0, -1)
run(4)
hum.MoveDirection = Vector3.new(0, 0, 0)
run(2)
truthy(not isOut(), "walking on after the beat drops the queued break")

-- ------------------------------------------------------------------ 4. other screens
for _, vp in { { 2560, 720, "32:9 ultrawide" }, { 414, 800, "portrait phone" } } do
	h:setViewport(vp[1], vp[2])
	run(0.2)
	breakBtn.Activated:Fire()
	run(3)
	truthy(isOut(), "a break on a " .. vp[3])
	breakBtn.Activated:Fire()
	run(1)
	truthy(backHome(), "and back on a " .. vp[3])
end
h:setViewport(1280, 720)
run(0.2)

-- ------------------------------------------------------------------ 5. another camera owner
checkOwnsCamera = true
cam.CameraType = Enum.CameraType.Scriptable
wasScriptable = true
local g0 = grade() and grade().Enabled
breakBtn.Activated:Fire()
run(1)
truthy(string.find(caption.Text, "busy", 1, true) ~= nil, "with the camera scripted by someone else the break says so: " .. caption.Text)
eq(grade() and grade().Enabled, g0, "and changes nothing")
eq(lightingPrint(), serverLighting, "Lighting untouched")
cam.CameraType = originalType
wasScriptable = false
checkOwnsCamera = false
run(0.5)

-- ------------------------------------------------------------------ 6. the capture rig's HUD_OFF
for _, g in plr.PlayerGui:GetChildren() do
	if g:IsA("ScreenGui") then g.Enabled = false end
end
local reEnabled = false
answer(true)
for _ = 1, 3 do
	answer(true)
	for _ = 1, 30 do
		frame()
		if skyGui.Enabled then reEnabled = true end
	end
end
eq(day(), 5, "four correct calls later (a new band on the way)")
truthy(not reEnabled, "the sky's ScreenGui stays off while the rig has switched every gui off, through a band change")
for _, g in plr.PlayerGui:GetChildren() do
	if g:IsA("ScreenGui") then g.Enabled = true end
end

-- ------------------------------------------------------------------ 7. a respawn during a break
-- (resume session: a mutation that let a break outlive the character survived every suite)
breakBtn.Activated:Fire()
run(1)
truthy(isOut(), "respawn test: out at the telescope")
do
	local char2 = h.Players:simulateSpawn(plr, h.workspace)
	local hum2 = char2:FindFirstChildOfClass("Humanoid")
	-- the new character stands still on the floor, so only the respawn itself can end the break
	hum2.FloorMaterial = Enum.Material.Plastic
	hum2.MoveDirection = Vector3.new(0, 0, 0)
	run(1)
	truthy(backHome(), "a respawn during a break brings the camera home, everything restored")
	eq(serverCalls, 0, "and still no remote")
end

-- ------------------------------------------------------------------ the invariants, over every frame
print(string.format("   %d frames out at the telescope; worst +Z ray component %.3f", outFrames, worstRay))
truthy(outFrames > 1000, "the break was actually exercised (" .. outFrames .. " frames out)")
eq(badRay, 0, "on every frame out, every frustum ray heads away from the halls")
eq(badGrade, 0, "the break grade is never on while the camera is not out")
eq(badLighting, 0, "Lighting never differs from the server's preset while the camera is not out")
eq(badSwap, 0, "the camera only goes out and comes back on a fully black frame")
eq(badType, 0, "the camera is never scripted anywhere but out at the telescope")
eq(serverCalls, 0, "the client fired no remote in the whole run")

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end
for _, w in h.warnings do print("   warn: " .. tostring(w)) end

print(string.format("\ncheck_anomalyobservatory_rest: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory rest check failed", 0)
end
