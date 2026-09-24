-- anomaly-observatory — the night sky, driven by the REAL server's Day through the REAL client.
-- Run: luau check_anomalyobservatory_sky.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- The pure rules (NightSky, EnvBands, Rest, Config.Sky, pacing) are unit-tested in
-- anomaly-observatory/tests. This file checks the GLUE no unit test can see, with the server
-- script and both client scripts running and every pass answered through the server's own prompts:
--
--   1. the sky follows the server's Day: every Day from 1 to 52 is played for real, and the band
--      the client shows is the band of that Day; a wrong call's reset glides it back to Day 1;
--   2. THE HALL NEVER CHANGES: every clean pass, at every Day, fingerprints identical to the first
--      clean pass (every BasePart in the zone, the same fingerprint check_anomaly_attrs uses), and
--      nothing the sky builds is anywhere inside a zone;
--   3. the sky is the SAME for a clean and an anomalous pass of the same Day: the settled sky of
--      every Day of a second climb is compared with the first climb's, and pairs where one pass
--      was clean and the other anomalous are counted and required;
--   4. every part the sky builds lies beyond the hall's entrance plane with Clearance to spare
--      (measured from the Parts' real CFrames and Sizes, all eight corners), so it is behind the
--      marketing rig's camera (hall-local z = +4, looking down -Z) and outside the hall;
--   5. never a hard cut: no non-flashing sky part's transparency moves more than 0.03 in a frame,
--      nothing pops in visible or vanishes while visible, across every band change and the reset;
--   6. Lighting is exactly the server's Horror preset on EVERY frame (this file takes no break);
--   7. no colour the sky shows is reddish, no Light exists, nothing is collidable, touchable or
--      ray-queryable, and the client fires no remote;
--   8. the budgets, measured on every frame and after every Day settles, per band and per seam.
--
-- Headless limits: nothing renders. This proves where things are, what they are and when they
-- change; whether it LOOKS good is on the Studio list in EYECANDY.md.

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")
local EnvBands = require("../anomaly-observatory/src/shared/EnvBands")

local Sky = Config.Sky
local bands = Sky.Bands

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

-- ------------------------------------------------------------------ the server, before any client
assert(h:tryRun("server/Main.server"))
local Lighting = h.Lighting

-- Lighting as the server's Fx.applyLighting(Horror) left it, as one string.
local LIGHT_PROPS = { "Ambient", "OutdoorAmbient", "Brightness", "ExposureCompensation", "ClockTime",
	"EnvironmentDiffuseScale", "EnvironmentSpecularScale", "Technology", "GeographicLatitude", "FogStart", "FogEnd", "FogColor" }
local CHILD_PROPS = {
	FxAtmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	FxBloom = { "Intensity", "Size", "Threshold", "Enabled" },
	FxColorCorrection = { "Brightness", "Contrast", "Saturation", "TintColor", "Enabled" },
	FxDoF = { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity", "Enabled" },
}
local function lightingPrint(): string
	local rows = {}
	for _, k in LIGHT_PROPS do table.insert(rows, k .. "=" .. tostring(Lighting[k])) end
	local names = {}
	-- the Sky object is tracked on its own (skyObject below): the client adds it once at start
	for _, c in Lighting:GetChildren() do
		if c.ClassName ~= "Sky" then table.insert(names, c.ClassName .. ":" .. c.Name) end
	end
	table.sort(names)
	table.insert(rows, "children=" .. table.concat(names, ","))
	for name, props in CHILD_PROPS do
		local c = Lighting:FindFirstChild(name)
		if c then
			for _, k in props do table.insert(rows, name .. "." .. k .. "=" .. tostring(c[k])) end
		end
	end
	return table.concat(rows, "|")
end
local serverLighting = lightingPrint()
truthy(Lighting:FindFirstChild("FxAtmosphere") ~= nil, "the server's Horror preset built its Atmosphere")

-- (review 2026-09-24) Without a Sky object Roblox draws its default night sky, whose own moon (no
-- phases) would hang behind the phased one. The sky client adds exactly one Sky with no sun or moon
-- drawn, once, at start, and never touches it again (the hall's Mirror reflects the skybox, so it
-- must be the same on every pass and every Day).
local function skyObject(): string
	local n, row = 0, "none"
	for _, c in Lighting:GetChildren() do
		if c.ClassName == "Sky" then
			n += 1
			row = string.format("%s|bodies=%s|stars=%s|bk=%s|moon=%s", c.Name, tostring(c.CelestialBodiesShown),
				tostring(c.StarCount), tostring(c.SkyboxBk), tostring(c.MoonTextureId))
		end
	end
	return n .. "|" .. row
end
eq(skyObject(), "0|none", "the server builds no Sky: the one the sky shows is the client's")

-- Count every client -> server remote call.
local remotes = h.ReplicatedStorage:FindFirstChild("AnomalyRemotes")
local serverCalls = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Stargazer", 31415)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)

assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
assert(zone ~= nil, "the player got no concourse")
local index = tonumber(zone:GetAttribute("Index"))
local origin = NightSky.hallOrigin(Sky.Hall, index)
local eye = NightSky.eye(Sky.Hall, origin)
local skyGui = plr.PlayerGui:FindFirstChild("ObservatorySky")
local breakBtn = skyGui and skyGui:FindFirstChild("Root") and skyGui.Root:FindFirstChild("BreakButton")
truthy(breakBtn ~= nil, "the sky's break button exists")

local function infoOf()
	local root = h.game:GetService("ServerStorage"):FindFirstChild("PassInfo")
	return root and root:FindFirstChild(tostring(plr.UserId))
end
local function day(): number
	local ls = plr:FindFirstChild("leaderstats")
	local d = ls and ls:FindFirstChild("Day")
	return d and d.Value or -1
end

-- ------------------------------------------------------------------ 0. the hall is where Config.Sky says
do
	local floor = zone:FindFirstChild("Floor")
	local ceiling = zone:FindFirstChild("Ceiling")
	local wallR = zone:FindFirstChild("WallR")
	local startPad = zone:FindFirstChild("StartPad")
	local ox, oy, oz = origin.x, origin.y, origin.z
	truthy(math.abs(startPad.Position.X - ox) < 1e-6 and math.abs(startPad.Position.Y - (oy + 1)) < 1e-6
		and math.abs(startPad.Position.Z - (oz - 4)) < 1e-6,
		"Config.Sky.Hall's origin (Spacing, OriginY) is the server's zoneOrigin: the StartPad sits at origin + (0, 1, -4)")
	local front = floor.Position.Z + floor.Size.Z / 2 - oz
	eq(front, Sky.Hall.Front, "the floor ends at the entrance plane Config.Sky.Hall.Front")
	eq(ceiling.Position.Z + ceiling.Size.Z / 2 - oz, Sky.Hall.Front, "and so does the ceiling")
	eq(wallR.Position.Z + wallR.Size.Z / 2 - oz, Sky.Hall.Front, "and the walls")
	eq(ceiling.Position.Y + ceiling.Size.Y / 2 - oy, Sky.Hall.Top, "the roof top is Config.Sky.Hall.Top")
	eq(wallR.Position.X + wallR.Size.X / 2 - ox, Sky.Hall.HalfWidth, "the outer wall face is Config.Sky.Hall.HalfWidth")
	-- nothing of the shell reaches past the entrance plane
	local past = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") and d.Position.Z + d.Size.Z / 2 - oz > Sky.Hall.Front + 1e-6 then
			table.insert(past, d.Name)
		end
	end
	eq(#past, 0, "nothing the server builds pokes out past the entrance plane: " .. table.concat(past, ", "))
end

-- ------------------------------------------------------------------ helpers
local cam = h.workspace.CurrentCamera
-- the default camera, played by this file: behind the character at the start pad, down the hall
local hallCam = CFrame.lookAt(Vector3.new(origin.x, origin.y + 8, origin.z + 6), Vector3.new(origin.x, origin.y + 6, origin.z - 80))
cam.CFrame = hallCam

local folder: any = nil
local LIVE = { "^Meteor%d", "^Bolt%d", "^Turning%d" }
local function isLive(name: string): boolean
	for _, pat in LIVE do
		if string.match(name, pat) then return true end
	end
	return false
end

local function colourOf(c): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

-- budgets, measured
local peak = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0 }
local peakAt = {}
local function stats()
	local s = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0 }
	if folder == nil then return s end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then s.parts += 1
		elseif d:IsA("ParticleEmitter") then if d.Enabled then s.emitters += 1; s.rate += d.Rate end
		elseif d:IsA("Beam") then if d.Enabled then s.beams += 1 end
		elseif d:IsA("Trail") then if d.Enabled then s.trails += 1 end
		elseif d:IsA("Light") then s.lights += 1 end
	end
	for _, d in cam:GetDescendants() do
		if d:IsA("Light") then s.lights += 1 end
	end
	return s
end

-- per-frame watchers
local lightingBad, lightingFrames = 0, 0
local maxStep, maxStepAt = 0, ""
local popIn, popOut = {}, {}
local lastT: { [any]: number } = {}
local frames = 0
local currentLabel = "join"

local skyObjectSeen: string? = nil
local skyObjectBad = 0
local function watch()
	frames += 1
	lightingFrames += 1
	if lightingPrint() ~= serverLighting then
		lightingBad += 1
	end
	local so = skyObject()
	if skyObjectSeen == nil then skyObjectSeen = so end
	if so ~= skyObjectSeen then skyObjectBad += 1 end
	if folder == nil then
		folder = h.workspace:FindFirstChild("ObservatorySky")
	end
	local s = stats()
	for k, v in s do
		if v > peak[k] then
			peak[k] = v
			peakAt[k] = currentLabel
		end
	end
	if folder == nil then return end
	local seen = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and not isLive(d.Name) then
			seen[d] = true
			local t = d.Transparency
			local last = lastT[d]
			if last == nil then
				if t < 0.97 then table.insert(popIn, d.Name .. " @" .. currentLabel .. string.format(" (%.2f)", t)) end
			else
				local step = math.abs(t - last)
				if step > maxStep then
					maxStep = step
					maxStepAt = d.Name .. " @" .. currentLabel
				end
			end
			lastT[d] = t
		end
	end
	for d, t in lastT do
		if not seen[d] then
			if t < 0.97 then table.insert(popOut, d.Name .. " @" .. currentLabel .. string.format(" (%.2f)", t)) end
			lastT[d] = nil
		end
	end
end

local DT = 1 / 30
local function frame()
	cam.CFrame = hallCam
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	watch()
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end

-- The settled sky, as a string: every non-flashing part (colour, size, where, how visible), every
-- emitter and every beam, and the band the button names. Moving things (meteors, the bolt, the
-- turning stars, the aurora's sway) are left out: they depend on the sky's clock, not the Day.
local function skyPrint(): string
	local rows = { "button=" .. tostring(breakBtn and breakBtn.Text) }
	if folder == nil then return table.concat(rows, "\n") end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and not isLive(d.Name) then
			local c = colourOf(d.Color)
			table.insert(rows, string.format("%s/%s|T%.4f|P%.3f,%.3f,%.3f|S%.2f,%.2f,%.2f|C%d,%d,%d",
				d.Parent.Name, d.Name, d.Transparency, d.Position.X, d.Position.Y, d.Position.Z,
				d.Size.X, d.Size.Y, d.Size.Z, c[1], c[2], c[3]))
		elseif d:IsA("ParticleEmitter") then
			table.insert(rows, string.format("E %s|%s|%.4f", d.Name, tostring(d.Enabled), d.Rate))
		elseif d:IsA("Beam") then
			local kp = d.Transparency.Keypoints
			table.insert(rows, string.format("B %s|%s|%.4f,%.4f", d.Name, tostring(d.Enabled), kp[1].Value, kp[#kp].Value))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

-- Print the rows two sky prints disagree on (a few of each), so a mismatch is diagnosable.
local function showDiff(label: string, a: string, b: string)
	local inA, inB = {}, {}
	for line in string.gmatch(a, "[^\n]+") do inA[line] = true end
	for line in string.gmatch(b, "[^\n]+") do inB[line] = true end
	local n = 0
	for line in inA do
		if not inB[line] and n < 6 then print("   " .. label .. " only in first : " .. line); n += 1 end
	end
	n = 0
	for line in inB do
		if not inA[line] and n < 6 then print("   " .. label .. " only in second: " .. line); n += 1 end
	end
end

-- Settle: run at least `minSeconds` (the glide needs GlideHalfLife x log2(500) = 10.8 s to close a
-- full step to the 0.002 snap; mid-glide, changes under 0.004 are not written, so "no change for a
-- second" alone is NOT arrival - the first version of this file was fooled by exactly that), then
-- until the print is unchanged for a second, or give up after `limit` seconds.
local function settle(limit: number, minSeconds: number?): (string, number)
	local t = 0
	local floor = minSeconds or 12
	while t < floor do
		run(0.5)
		t += 0.5
	end
	local last, same = skyPrint(), 0
	while t < limit do
		run(0.5)
		t += 0.5
		local now = skyPrint()
		if now == last then
			same += 1
			if same >= 2 then return now, t end
		else
			same = 0
			last = now
		end
	end
	return last, t
end

-- The hall, reduced to a string (check_anomaly_attrs.luau's fingerprint, relative to the origin).
local function hallPrint(): string
	local rows = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			x -= origin.x
			table.insert(rows, string.format(
				"%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d,%d,%d|%.2f|%.2f|%s",
				tostring(d.Name), x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22,
				d.Size.X, d.Size.Y, d.Size.Z,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
				d.Transparency, d.Reflectance, tostring(d.Material)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end

-- Answer the live pass through the server's own prompt. `right` = answer correctly.
local function answer(right: boolean)
	local info = infoOf()
	local clean = info:GetAttribute("Clean")
	local advance = (clean == true) == right
	local pad = zone:FindFirstChild(if advance then "AdvancePad" else "BackPad")
	assert(pad ~= nil, "no decision pad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	local ok, err = coroutine.resume(co)
	assert(ok, "prompt handler errored: " .. tostring(err))
end

-- the geometry and hygiene of everything the sky has built so far
local geomBad, reddish, hygiene, inZone, engineBad = {}, {}, {}, {}, {}
local function inspect(label: string)
	if folder == nil then return end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			local minZ = math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local wpt = d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						if wpt.Z < minZ then minZ = wpt.Z end
					end
				end
			end
			if minZ - origin.z <= Sky.Hall.Front + Sky.Clearance then
				table.insert(geomBad, string.format("%s nearest corner z %.1f @%s", d.Name, minZ - origin.z, label))
			end
			if d.Transparency < 1 and NightSky.isReddish(colourOf(d.Color)) then
				table.insert(reddish, d.Name)
			end
			-- (review 2026-09-24) sizes the engine draws as written: robloxemu keeps any size, Roblox
			-- forces a Ball uniform, draws a Cylinder round (Y = Z) and clamps every axis to 2048
			local sz = d.Size
			for _, v in { sz.X, sz.Y, sz.Z } do
				if not (v >= 0.05 and v <= 2048) then
					table.insert(engineBad, string.format("%s axis %.1f outside 0.05..2048", d.Name, v))
					break
				end
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			if d.Shape == Enum.PartType.Ball and mesh == nil and (math.abs(sz.X - sz.Y) > 1e-6 or math.abs(sz.X - sz.Z) > 1e-6) then
				table.insert(engineBad, string.format("%s is a non-uniform Ball (%.1f, %.1f, %.1f)", d.Name, sz.X, sz.Y, sz.Z))
			end
			if d.Shape == Enum.PartType.Cylinder and math.abs(sz.Y - sz.Z) > 1e-6 then
				table.insert(engineBad, d.Name .. " is an oval Cylinder")
			end
			if string.match(d.Name, "^StormCloud%d") and not (mesh and mesh.MeshType == Enum.MeshType.Sphere
				and d.Shape ~= Enum.PartType.Ball and sz.Y < sz.X and sz.Y < sz.Z) then
				table.insert(engineBad, d.Name .. " is not a flattened ellipsoid (a Block with a Sphere mesh)")
			end
			if d.Anchored ~= true or d.CanCollide ~= false or d.CanQuery ~= false or d.CanTouch ~= false or d.CastShadow ~= false then
				table.insert(hygiene, d.Name)
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			for _, kp in d.Color.Keypoints do
				if NightSky.isReddish(colourOf(kp.Value)) then table.insert(reddish, d.Name) end
			end
		end
	end
	-- nothing of the sky inside any zone
	for _, z in h.workspace:GetChildren() do
		if string.sub(z.Name, 1, 10) == "Concourse_" then
			for _, d in z:GetDescendants() do
				if d:IsA("Beam") or d:IsA("Trail") or string.sub(d.Name, 1, 4) == "Sky_" or d.Name == "ObservatorySky"
					or d.Name == "Moon" or d.Name == "StarField" or d.Name == "RainHost" then
					table.insert(inZone, d.Name .. " in " .. z.Name)
				end
			end
		end
	end
end

-- ------------------------------------------------------------------ 1. climb from Day 1 to Day 52
currentLabel = "Day 1 (join)"
local firstPrint = {} -- day -> settled sky print
local firstClean = {} -- day -> was that pass clean
local perDay = {} -- day -> stats
local refHall: string? = nil
local cleanHalls, cleanMismatch = 0, 0
local bandShown = {}
local unsettled = {}

-- The drawn moon is THIS Day's phase: the dark disc sits where NightSky.moonDraw puts it for the
-- Day (offset and side), and the moon and the disc are as visible as the phase and the band's moon
-- weight say. (Added in the resume session: a mutation that pinned the phase to Day 1 survived every
-- suite, because a Day-to-Day print difference is also caused by the band blend.)
local moonBad, moonDays = {}, 0
local function moonCheck(d: number)
	local mf = folder and folder:FindFirstChild("Sky_moon")
	local moon = mf and mf:FindFirstChild("Moon")
	local shade = mf and mf:FindFirstChild("MoonShade")
	if moon == nil or shade == nil then
		table.insert(moonBad, "Day " .. d .. ": no moon parts")
		return
	end
	moonDays += 1
	local M = Sky.Moon
	local draw = NightSky.moonDraw(NightSky.moonPhase(M, d))
	local w = NightSky.features(bands, EnvBands, d).moon
	local wantMoonT = if draw.showMoon then 1 - w * draw.moonAlpha else 1
	if math.abs(moon.Transparency - wantMoonT) > 1e-3 then
		table.insert(moonBad, string.format("Day %d: moon transparency %.4f, want %.4f", d, moon.Transparency, wantMoonT))
	end
	if draw.showMoon and draw.showShade then
		local home = NightSky.skyPoint(eye, M.Azimuth, M.Elevation, M.Distance - 2)
		local basis = NightSky.faceBasis(eye, home)
		local k = -draw.side * draw.offset * M.Radius
		local want = Vector3.new(home.x + basis.right.x * k, home.y + basis.right.y * k, home.z + basis.right.z * k)
		if (shade.Position - want).Magnitude > 0.02 then
			table.insert(moonBad, string.format("Day %d: shade %.2f studs from where phase %.3f puts it", d,
				(shade.Position - want).Magnitude, NightSky.moonPhase(M, d)))
		end
		local wantShadeT = 1 - w * draw.shadeAlpha
		if math.abs(shade.Transparency - wantShadeT) > 1e-3 then
			table.insert(moonBad, string.format("Day %d: shade transparency %.4f, want %.4f", d, shade.Transparency, wantShadeT))
		end
	elseif shade.Transparency < 1 then
		table.insert(moonBad, string.format("Day %d: a shade is drawn (%.3f) where the phase needs none", d, shade.Transparency))
	end
end

local function measureDay(tag: string)
	local d = day()
	currentLabel = tag .. " Day " .. d
	local sp, took = settle(24)
	if took >= 24 then table.insert(unsettled, d) end
	inspect(currentLabel)
	moonCheck(d)
	local info = infoOf()
	local clean = info:GetAttribute("Clean") == true
	if clean then
		local hp = hallPrint()
		cleanHalls += 1
		if refHall == nil then
			refHall = hp
		elseif hp ~= refHall then
			cleanMismatch += 1
		end
	end
	return d, sp, clean
end

do
	local d, sp, clean = measureDay("climb")
	eq(d, 1, "the night starts on Day 1")
	firstPrint[d], firstClean[d] = sp, clean
	perDay[d] = stats()
	local desc = NightSky.describe(bands, EnvBands, d)
	bandShown[d] = string.find(breakBtn.Text, desc.name, 1, true) ~= nil
end

local TOP = 52
for _ = 2, TOP do
	answer(true)
	local d, sp, clean = measureDay("climb")
	firstPrint[d], firstClean[d] = sp, clean
	perDay[d] = stats()
	local desc = NightSky.describe(bands, EnvBands, d)
	bandShown[d] = string.find(breakBtn.Text, desc.name, 1, true) ~= nil
end
eq(day(), TOP, "every pass of the climb was scored correct: Day " .. TOP .. " reached")
do
	local wrong = {}
	for d = 1, TOP do
		if not bandShown[d] then table.insert(wrong, tostring(d)) end
	end
	eq(#wrong, 0, "on every Day the client names the band of the server's Day: " .. table.concat(wrong, ","))
	eq(#unsettled, 0, "every Day's sky settled within 24 s: " .. table.concat(unsettled, ","))
end
-- The bands really differ: the settled sky changes at every band boundary.
do
	local same = {}
	for i = 2, #bands do
		local d0, d1 = math.max(1, bands[i - 1].from), bands[i].from
		if firstPrint[d0] == firstPrint[d1] then table.insert(same, bands[i].id) end
	end
	eq(#same, 0, "every band looks different from the one before it: " .. table.concat(same, ","))
	-- and the moon's phase moves the shade from Day to Day inside a band
	truthy(firstPrint[2] ~= firstPrint[3], "the moon's phase changes the sky from Day 2 to Day 3 (same band)")
	truthy(moonDays >= TOP, "the drawn moon was checked on every Day of the climb (" .. moonDays .. ")")
end

-- ------------------------------------------------------------------ 2. a wrong call: back to Day 1, gliding
currentLabel = "reset"
answer(false)
run(0.2)
eq(day(), 1, "a wrong call resets the Day to 1 (leaderstats)")
do
	local stepBefore = maxStep
	local sp = settle(60, 40)
	currentLabel = "after reset Day 1"
	truthy(sp == firstPrint[1], "after the reset the sky settles back to exactly the Day-1 sky")
	if sp ~= firstPrint[1] then showDiff("Day 1", firstPrint[1], sp) end
	truthy(maxStep == stepBefore or maxStep <= 0.03, "the reset from the last band to the first glided (no step > 0.03)")
end

-- ------------------------------------------------------------------ 3. a second climb: same Day, same sky
local compared, mixed, diffDays = 0, 0, {}
do
	local sp = skyPrint()
	local info = infoOf()
	local clean = info:GetAttribute("Clean") == true
	compared += 1
	if sp ~= firstPrint[1] then table.insert(diffDays, "1") end
	if clean ~= firstClean[1] then mixed += 1 end
end
for _ = 2, 18 do
	answer(true)
	local d, sp, clean = measureDay("second climb")
	compared += 1
	if sp ~= firstPrint[d] then
		table.insert(diffDays, tostring(d))
		showDiff("Day " .. d, firstPrint[d], sp)
	end
	if clean ~= firstClean[d] then mixed += 1 end
end
eq(#diffDays, 0, "every Day of the second climb has exactly the first climb's sky: " .. table.concat(diffDays, ","))
print(string.format("   compared %d Days across two climbs; %d of them pair a CLEAN pass with an ANOMALOUS one", compared, mixed))
truthy(mixed >= 2, "the comparison includes clean-vs-anomalous pairs of the same Day (" .. mixed .. ")")

-- ------------------------------------------------------------------ 4..8. the verdicts
print(string.format("   %d clean passes seen, all fingerprinted against the first", cleanHalls))
print(string.format("   measured: largest one-frame transparency step %.4f (%s); Lighting compared on %d frames",
	maxStep, maxStepAt, lightingFrames))
truthy(cleanHalls >= 10, "enough clean passes were seen to matter (" .. cleanHalls .. ")")
eq(cleanMismatch, 0, "THE HALL NEVER CHANGES: every clean pass at every Day fingerprints identical to the first")
eq(#inZone, 0, "nothing the sky builds is inside any zone: " .. table.concat(inZone, ", "))
do
	local shown = {}
	for i = 1, math.min(6, #moonBad) do shown[i] = moonBad[i] end
	eq(#moonBad, 0, string.format("on every Day of both climbs (%d checks) the drawn moon is that Day's phase: %s%s", moonDays,
		table.concat(shown, "; "), if #moonBad > 6 then string.format(" ... (%d in all)", #moonBad) else ""))
end
eq(#geomBad, 0, "every sky part's every corner is beyond the entrance plane + Clearance: " .. table.concat(geomBad, "; "))
do
	local shown = {}
	local seenName = {}
	for _, e in engineBad do
		local k = string.match(e, "^(%S+)")
		if not seenName[k] and #shown < 12 then seenName[k] = true; table.insert(shown, e) end
	end
	eq(#engineBad, 0, "every sky part has a size the engine draws as built (Ball uniform, Cylinder round, axes <= 2048, clouds are ellipsoid meshes): "
		.. table.concat(shown, "; "))
end
truthy(skyObjectSeen ~= nil and string.sub(skyObjectSeen, 1, 2) == "1|" and string.find(skyObjectSeen, "bodies=false", 1, true) ~= nil,
	"the client added exactly one Sky, with no sun or moon drawn: " .. tostring(skyObjectSeen))
eq(skyObjectBad, 0, "and it never changed on any of " .. lightingFrames .. " frames")
eq(#reddish, 0, "nothing visible in the sky is reddish: " .. table.concat(reddish, ", "))
eq(#hygiene, 0, "every sky part is anchored, non-collidable, non-queryable, non-touchable and casts no shadow: " .. table.concat(hygiene, ", "))
eq(lightingBad, 0, string.format("Lighting is the server's Horror preset on every one of %d frames", lightingFrames))
eq(serverCalls, 0, "the client fired no remote")
truthy(maxStep <= 0.03, string.format("never a hard cut: the biggest one-frame transparency step of any sky part is %.4f (%s)", maxStep, maxStepAt))
eq(#popIn, 0, "nothing pops in already visible: " .. table.concat(popIn, ", "))
eq(#popOut, 0, "nothing vanishes while still visible: " .. table.concat(popOut, ", "))
do
	local names = {}
	for _, c in cam:GetChildren() do table.insert(names, c.Name) end
	eq(#names, 0, "the camera carries nothing outside a break: " .. table.concat(names, ", "))
end
-- the replicated surface carries no roll, with the sky running
do
	local BANNED = { Clean = true, AnomalyId = true, Serial = true }
	local found = {}
	for _, root in { h.workspace, h.ReplicatedStorage } do
		for _, d in root:GetDescendants() do
			for name in d:GetAttributes() do
				if BANNED[name] then table.insert(found, d.Name .. "." .. name) end
			end
		end
	end
	eq(#found, 0, "nothing a client can see carries the roll, with the sky running: " .. table.concat(found, ", "))
end
-- the client source never reaches for the pass
do
	local bundle = require("./build/anomaly-observatory")
	for _, key in { "client/Sky.client", "shared/SkyArt", "shared/NightSky" } do
		local src = bundle[key] and bundle[key].source or ""
		truthy(#src > 0, key .. " is in the bundle")
		-- code only: the comments explain at length that none of this is read
		src = string.gsub(src, "%-%-[^\n]*", "")
		for _, banned in { "PassInfo", "ServerStorage", "AnomalyId", "FireServer", "InvokeServer", "WaitForChild(\"Anomaly\")",
			"\"PointLight\"", "\"SpotLight\"", "\"SurfaceLight\"" } do
			truthy(string.find(src, banned, 1, true) == nil, key .. " never mentions " .. banned)
		end
	end
end

-- ------------------------------------------------------------------ the budget table
local B = Sky.Budget
print("")
print("   Day  band                 parts emitters rate  beams trails lights")
local function bandLabel(d)
	local i, j, t = EnvBands.locate(bands, d)
	if j ~= i and t > 0 then
		return string.format("%s > %s", bands[i].id, bands[j].id)
	end
	return bands[i].id
end
local over = {}
for d = 1, TOP do
	local s = perDay[d]
	print(string.format("   %3d  %-20s %5d %8d %5.1f %6d %6d %6d", d, bandLabel(d), s.parts, s.emitters, s.rate, s.beams, s.trails, s.lights))
	if s.parts > B.MaxParts or s.emitters > B.MaxEmitters or s.rate > B.MaxEmitterRate + 1e-6 or s.beams > B.MaxBeams
		or s.trails > B.MaxTrails or s.lights > B.MaxLights then
		table.insert(over, tostring(d))
	end
end
print(string.format("   PEAK over %d frames: parts %d (%s), emitters %d, rate %.1f/s (%s), beams %d, trails %d, lights %d",
	frames, peak.parts, tostring(peakAt.parts), peak.emitters, peak.rate, tostring(peakAt.rate), peak.beams, peak.trails, peak.lights))
eq(#over, 0, "every settled Day is within Config.Sky.Budget: " .. table.concat(over, ","))
truthy(peak.parts <= B.MaxParts, string.format("peak parts %d <= %d, on every frame including transitions", peak.parts, B.MaxParts))
truthy(peak.emitters <= B.MaxEmitters, string.format("peak emitters %d <= %d", peak.emitters, B.MaxEmitters))
truthy(peak.rate <= B.MaxEmitterRate + 1e-6, string.format("peak particle rate %.1f <= %d", peak.rate, B.MaxEmitterRate))
truthy(peak.beams <= B.MaxBeams, string.format("peak beams %d <= %d", peak.beams, B.MaxBeams))
truthy(peak.trails <= B.MaxTrails, string.format("peak trails %d <= %d", peak.trails, B.MaxTrails))
eq(peak.lights, 0, "the sky never owns a Light")

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end
for _, w in h.warnings do print("   warn: " .. tostring(w)) end

print(string.format("\ncheck_anomalyobservatory_sky: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory sky check failed", 0)
end
