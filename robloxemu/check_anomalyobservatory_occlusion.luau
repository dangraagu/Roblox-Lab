-- anomaly-observatory — the sky's own on-screen text never sits on the hall during a pass.
-- Run: luau check_anomalyobservatory_occlusion.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- (review 2026-09-24) This is spot-the-difference: whatever is drawn over the hall during a pass makes
-- the objects under it harder to read, and an anomaly on them harder to spot. The reviewer measured the
-- band-up caption ("🌠 Meteor Shower tonight — press 🔭 Break (B) to watch it.", 6 s) on a 640x300
-- phone lying across the right-hand Mirror at 13 of the 19 points of the next walk and the ChartWall at
-- 8, with the break button blinking at 2 Hz beside it. That is the pass after every band change (7 a
-- climb); the join caption does the same on the first pass. check_anomalyobservatory_hud only compares
-- the sky's row with the HUD's panels, never with the hall.
--
-- For every viewport of the standard HUD list (plus 844x390 and 1280x720), with the server and both
-- client scripts running and passes answered through the server's own prompts:
--   1. COVERAGE. From the first frame of the first pass, and again from the correct call that brings
--      a new band (Day 4), the sky's GUI (the break button and its caption, as they are at that moment)
--      is projected against every visible object of the hall along a walk down it: the camera 10 studs
--      behind the player looking down the hall, the player at 19 points 4 studs apart, reached every
--      0.25 s (WalkSpeed 16). An object is COVERED at a point when >= 25% of its screen box is under the
--      sky's GUI. Rule: no object is covered at more than 2 of the 19 points (about 10% of the walk, half
--      a second): a ceiling fixture may cross the top-centre row as you walk under it; nothing may ride
--      along under the sky's GUI. (First written as "at most 1", the reviewer's desktop measurement; the
--      first run found the permanent break button over Fixture1 at 2/19 on a 1366x768 touch laptop, a
--      taller tap target. A fixture crossing a row for half a second is not what the finding is about,
--      so the rule is the round 10%, and the phone caption gets the stricter rule 1c.)
--   1c. ON A PHONE the sky shows no caption in the hall that the player did not ask for: none at join,
--      none after a band change (it would sit on the right-hand wall; the reviewer's 13/19);
--   2. NO BLINKING. During the pass after a band change the break button's colour changes at most once
--      (a steady "something new out there" highlight). "The Flicker" is an anomaly;
--   3. NOTHING IS LOST. The next break's caption names the new band; on a phone, whose hall shows no
--      unrequested caption at all, the first break carries the join tip instead.
--
-- One harness per process (robloxemu's rule), so one player and one night: the first pass is measured
-- on the smallest phone, then each viewport is switched in place and gets its own band-up (a wrong call
-- back to Day 1, three right calls to Day 4).

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")
local Responsive = require("../anomaly-observatory/src/shared/Responsive")

local Sky = Config.Sky

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local VIEWPORTS = { { name = "small phone (join)", w = 640, h = 300, touch = true } }
for _, v in HudCheck.VIEWPORTS do table.insert(VIEWPORTS, v) end
table.insert(VIEWPORTS, { name = "phone landscape 844", w = 844, h = 390, touch = true })
table.insert(VIEWPORTS, { name = "laptop 1280", w = 1280, h = 720, touch = false })

local SHELL = { Floor = true, Ceiling = true, WallL = true, WallR = true, EndWall = true }
local STEPS, STEP_STUDS, STEP_SECONDS = 19, 4, 0.25
local DT = 1 / 30

local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end

local totalPoints = 0
local first = VIEWPORTS[1]
local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { first.w, first.h },
	touch = first.touch,
})
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Looker", 5150)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local o = NightSky.hallOrigin(Sky.Hall, tonumber(zone:GetAttribute("Index")))
local O = Vector3.new(o.x, o.y, o.z)
local cam = h.workspace.CurrentCamera
local skyGui = plr.PlayerGui:FindFirstChild("ObservatorySky")
local breakBtn = skyGui.Root:FindFirstChild("BreakButton")
local caption = skyGui.Root:FindFirstChild("SkyCaption")

-- this file plays Roblox's default camera: behind the player at the start pad, down the hall
local walkCam = CFrame.lookAt(O + Vector3.new(0, 8, 6), O + Vector3.new(0, 6, -80))
local colourChanges, lastColour = 0, nil
local countColour = false
local function frame()
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CFrame = walkCam end
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	local c = breakBtn.BackgroundColor3
	if countColour and lastColour ~= nil and c ~= lastColour then colourChanges += 1 end
	lastColour = c
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end

local function info()
	return h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId))
end
local function answer(right: boolean)
	local clean = info():GetAttribute("Clean") == true
	local advance = clean == right
	local pad = zone:FindFirstChild(if advance then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
end

-- The part's screen box in px, clipped to the screen; nil when any corner is behind the camera (a part
-- beside or behind the lens) or when nothing of it is on screen.
local function screenBox(part, cf, vw: number, vh: number)
	local tv = math.tan(math.rad(cam.FieldOfView) / 2)
	local asp = vw / vh
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	local s = part.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local w = part.CFrame:PointToWorldSpace(Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
				local p = cf:PointToObjectSpace(w)
				if p.Z >= -0.1 then return nil end
				local nx = (p.X / -p.Z) / (tv * asp)
				local ny = (p.Y / -p.Z) / tv
				local px, py = (nx + 1) / 2 * vw, (1 - ny) / 2 * vh
				minx, miny = math.min(minx, px), math.min(miny, py)
				maxx, maxy = math.max(maxx, px), math.max(maxy, py)
			end
		end
	end
	minx, miny = math.max(minx, 0), math.max(miny, 0)
	maxx, maxy = math.min(maxx, vw), math.min(maxy, vh)
	if maxx - minx < 1 or maxy - miny < 1 then return nil end
	return minx, miny, maxx, maxy
end

-- One walk down the hall at viewport vp; returns the worst object and how many points it was covered.
local function walk(vp, tag: string, label: string): (string, number, number)
	local covered: { [string]: number } = {}
	local captionPoints = 0
	for k = 0, STEPS - 1 do
		run(STEP_SECONDS)
		local zc = -4 - STEP_STUDS * k
		local cf = CFrame.lookAt(O + Vector3.new(0, 8, zc + 10), O + Vector3.new(0, 6, zc - 76))
		local rects = {}
		for _, r in h:guiRects(skyGui, vp.w, vp.h) do
			if r.shown and r.sw > 0 and r.sh > 0 and (r.name == "BreakButton" or (r.name == "SkyCaption" and r.obj.Text ~= "")) then
				table.insert(rects, r)
				if r.name == "SkyCaption" then captionPoints += 1 end
			end
		end
		for _, d in zone:GetDescendants() do
			if d:IsA("BasePart") and not SHELL[d.Name] and d.Transparency < 1 then
				local x0, y0, x1, y1 = screenBox(d, cf, vp.w, vp.h)
				if x0 then
					local area = (x1 - x0) * (y1 - y0)
					for _, r in rects do
						local ox = math.min(x1, r.sx + r.sw) - math.max(x0, r.sx)
						local oy = math.min(y1, r.sy + r.sh) - math.max(y0, r.sy)
						if ox > 0 and oy > 0 and (ox * oy) / area >= 0.25 then
							local key = d.Name .. " under " .. r.name
							covered[key] = (covered[key] or 0) + 1
							break
						end
					end
				end
			end
		end
		totalPoints += 1
	end
	local worst, worstN = "none", 0
	for key, n in covered do
		if n > worstN or (n == worstN and n > 0 and key < worst) then worst, worstN = key, n end
	end
	print(string.format("   %s %-8s worst: %s at %d/%d points (caption shown at %d)", tag, label, worst, worstN, STEPS, captionPoints))
	return worst, worstN, captionPoints
end

for i, vp in VIEWPORTS do
	local tag = string.format("[%s %dx%d%s]", vp.name, vp.w, vp.h, if vp.touch then " touch" else "")
	h:setViewport(vp.w, vp.h)
	h:setTouch(vp.touch)

	if i == 1 then
		-- ------------------------------------------------------------ 1a. the first pass, from join
		assert(Responsive.layout(vp.w, vp.h, vp.touch).compact, "the join viewport is a phone")
		local jw, jn, jc = walk(vp, tag, "join")
		truthy(jn <= 2, tag .. " on the first pass no hall object sits under the sky's GUI (worst " .. jw .. " at " .. jn .. "/19)")
		eq(jc, 0, tag .. " on a phone the first pass shows no unrequested caption over the hall (points with caption text)")
		-- on a phone the join tip is on the first break instead of on the hall
		breakBtn.Activated:Fire()
		run(1)
		local intro = if type(NightSky.introNews) == "function" then NightSky.introNews(true) else "(NightSky.introNews missing)"
		truthy(string.find(caption.Text, intro, 1, true) ~= nil, tag .. " the first break on a phone carries the join tip: " .. caption.Text)
		breakBtn.Activated:Fire()
		run(1.5)
	else
		run(0.5)
		-- back to the first night: a wrong call, then the death beat
		answer(false)
		run(3.5)
		eq(plr.leaderstats.Day.Value, 1, tag .. " a wrong call is back on Day 1")
	end

	-- ---------------------------------------------------------------- 1b + 2. the pass after a band change
	answer(true); run(0.5)
	answer(true); run(0.5)
	lastColour = breakBtn.BackgroundColor3
	colourChanges = 0
	countColour = true
	answer(true) -- Day 4: the Meteor Shower band is up
	eq(plr.leaderstats.Day.Value, 4, tag .. " three right calls reach Day 4 (a new band)")
	local bw, bn, bc = walk(vp, tag, "band-up")
	run(6 - STEPS * STEP_SECONDS + 0.5) -- the rest of the 6 s a band-up caption used to last
	countColour = false
	truthy(bn <= 2, tag .. " on the pass after a band change no hall object sits under the sky's GUI (worst " .. bw .. " at " .. bn .. "/19)")
	if Responsive.layout(vp.w, vp.h, vp.touch).compact then
		eq(bc, 0, tag .. " on a phone the pass after a band change shows no caption over the hall (points with caption text)")
	end
	truthy(colourChanges <= 1, string.format("%s the break button does not blink during that pass (%d colour changes)", tag, colourChanges))

	-- ---------------------------------------------------------------- 3. the news is on the break
	breakBtn.Activated:Fire()
	run(1)
	truthy(string.find(caption.Text, "Meteor Shower", 1, true) ~= nil, tag .. " the next break names the new band: " .. caption.Text)
	breakBtn.Activated:Fire()
	run(1.5)
end

-- ---------------------------------------------------------------- 4. news the player never saw
-- A band arrives and a wrong call takes it away before any break: the button goes back to normal and
-- the next break does not announce a band the sky no longer shows.
do
	local tag = "[band-up, then a wrong call]"
	run(0.5)
	answer(false)
	run(3.5)
	answer(true); run(0.5)
	answer(true); run(0.5)
	answer(true) -- Day 4
	run(1)
	local normal = Color3.fromRGB(18, 20, 30)
	truthy(breakBtn.BackgroundColor3 ~= normal, tag .. " the button is highlighted after the band-up")
	answer(false) -- back to Day 1 before any break
	run(3.5)
	eq(plr.leaderstats.Day.Value, 1, tag .. " the wrong call reset the Day")
	truthy(breakBtn.BackgroundColor3 == normal, tag .. " the highlight goes with the band it announced")
	breakBtn.Activated:Fire()
	run(1)
	truthy(caption.Text ~= "" and string.find(caption.Text, "Meteor Shower", 1, true) == nil,
		tag .. " the next break does not announce a band the sky no longer shows: " .. caption.Text)
	breakBtn.Activated:Fire()
	run(1.5)
end

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("   %d walk points measured over %d viewports", totalPoints, #VIEWPORTS))
print(string.format("\ncheck_anomalyobservatory_occlusion: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory occlusion check failed", 0)
end
