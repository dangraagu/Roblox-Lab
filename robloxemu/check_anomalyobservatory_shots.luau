-- anomaly-observatory — the thumbnail shot list (EYECANDY.md §9), proved headless before the night session.
-- Run: luau check_anomalyobservatory_shots.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- (review 2026-09-24) The first shot list had every left and right mirrored and put the hero shot's
-- avatar off the bottom-left of its own frame. The cause is Roblox's camera frame: looking out of the
-- entrance (+Z), the camera's RightVector is -X, so a POSITIVE azimuth (toward +X) is on screen LEFT.
-- Nothing checked the list against the real sky, so this file does, with the server and both client
-- scripts running, exactly as the operator will (1920x1080, the thumbnail size):
--   * the Day is set the way §9 says (Server command bar: leaderstats.Day.Value = N), in §9's order,
--     and §9's wait (45 s) is long enough: the sky is settled then (nothing changes in 30 s more);
--   * each camera is §9's camera: the break view (press B, capture ~1 s in), or a scripted camera
--     built from §9's two points with CFrame.lookAt;
--   * every "must be in frame" callout is in the frame, visible, and on the side of the frame §9 says
--     (sx: -1 left edge .. +1 right edge, sy: -1 bottom .. +1 top, taken from the camera's own
--     RightVector / UpVector, so screen left/right are the player's);
--   * the moon's phase words (waxing gibbous, full, crescent) are the Day's phase, and its lit side is
--     the side §9 implies (the dark disc sits on the unlit side on screen);
--   * a camera INSIDE the hall sees the sky only through the entrance: a callout counts only when the
--     line from the lens to it passes through the doorway opening (the walls, floor and ceiling hide
--     the rest), so "in frame" means what the photograph will actually show;
--   * the hero shot's avatar, parked where §9 parks it, is wholly inside the frame, in the lower-right
--     third, and the whole doorway (all four corners of the opening) frames the sky;
--   * the storm shot catches a lightning bolt in frame within §9's minute of recording, with rain on;
--   * §9's note about the pan (what a capture 20 s into a break looks like) has the right direction.
--
-- The list as first written is kept in the scratch log of this review (13 of 42 assertions failed:
-- every left/right callout, the avatar at sx -0.97 sy -1.44, the pan note).
--
-- (review 2026-09-30, finding 6) There is ONE copy of the list now: anomaly-observatory/marketing/
-- ShotList.luau, required below, which EYECANDY.md §9 prints for the night shift. The old SHOTS table
-- here was a second copy of §9's prose, and since the luau CLI cannot read markdown, the prose could
-- drift (every left/right swapped) with this check green. This file now also asserts that no free text
-- in the list names a side of the frame (only measured `where` fields may), that every printed number
-- (`at`, the avatar's centre, the flash count, the pan) is what it measures, and that the printed table
-- carries every measured side.

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")

local Sky = Config.Sky
local List = require("../anomaly-observatory/marketing/ShotList")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- ------------------------------------------------------------------ the shot list (marketing/ShotList.luau)
local VERSION = List.version
local SHOTS = List.shots
local PAN_20S = List.pan.toward
local WAIT_SECONDS = List.waitSeconds
local AT_TOL = 0.05 -- a printed sx / sy must be within this of the measurement
-- the word a shot's note must use for its weather (2026-10-01, pass 2)
local WEATHER_WORD = { thistledown = "thistledown", snow = "snow", frost = "frost", rain = "rain", leaves = "leaves",
	motes = "motes", clear = "clear sky" }

-- No free text names a side of the frame: sides enter the prose only through measured `where` fields.
local function sideWordIn(text: string): string?
	local low = string.lower(text)
	for _, w in List.SIDE_WORDS do
		if string.find(low, "%f[%a]" .. w .. "%f[%A]") then return w end
	end
	return nil
end
do
	local named = {}
	for _, t in List.freeText(List) do
		local w = sideWordIn(t)
		if w then table.insert(named, string.format("'%s' in: %s", w, t)) end
	end
	eq(#named, 0, "no free text in the shot list names a side of the frame (only measured `where` may): " .. table.concat(named, " | "))
	-- CONTROL: the scan finds a side word planted in a copy of the list
	local copy = table.clone(List)
	copy.shots = table.clone(List.shots)
	copy.shots[1] = table.clone(List.shots[1])
	copy.shots[1].note = List.shots[1].note .. " The moon is on the left."
	local found = 0
	for _, t in List.freeText(copy) do
		if sideWordIn(t) then found += 1 end
	end
	eq(found, 1, "CONTROL: the side-word scan finds one planted in a copy of the list")
	-- the printed table carries every measured side and every title
	local printed = List.render()
	local missing = {}
	for _, shot in SHOTS do
		if not string.find(printed, shot.title, 1, true) then table.insert(missing, shot.title) end
		for _, c in shot.must do
			if c[2] ~= "" and not string.find(printed, List.calloutText(shot, c), 1, true) then
				table.insert(missing, List.calloutText(shot, c))
			end
		end
	end
	eq(#missing, 0, "the printed table carries every shot and every measured callout: " .. table.concat(missing, " | "))
end

-- ------------------------------------------------------------------ the place, as the operator has it
local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { 1920, 1080 },
	touch = false,
})
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local UIS = h.game:GetService("UserInputService")
local plr = h:join("Photographer", 8086)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
local root = char:FindFirstChild("HumanoidRootPart")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local o = NightSky.hallOrigin(Sky.Hall, tonumber(zone:GetAttribute("Index")))
local O = Vector3.new(o.x, o.y, o.z)
eq(tostring(O), tostring(Vector3.new(1000, 100, 0)), "the first player's hall is index 1, origin (1000, 100, 0), as §9 says")
local cam = h.workspace.CurrentCamera
local originalType = cam.CameraType
local folder: any = nil -- the sky client builds it on its first frame
local hallCam = CFrame.lookAt(O + Vector3.new(0, 8, 6), O + Vector3.new(0, 6, -80))

local DT = 1 / 30
local function frame()
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CFrame = hallCam end
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end
local function v3(t): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- the settled sky, to prove the wait: every non-moving part's transparency, position and size (the critters
-- fly on the sky's clock, like the meteors: 2026-10-01)
local LIVE = { "^Meteor%d", "^Bolt%d", "^Turning%d", "^Critter_" }
local function settledPrint(): string
	local rows = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local live = false
			for _, pat in LIVE do
				if string.match(d.Name, pat) then live = true end
			end
			if not live then
				table.insert(rows, string.format("%s|%.3f|%.2f,%.2f,%.2f|%s", d.Name, d.Transparency, d.Position.X, d.Position.Y,
					d.Position.Z, tostring(d.Parent and d.Parent.Parent ~= nil)))
			end
		elseif d:IsA("Beam") then
			table.insert(rows, string.format("B %s|%s", d.Name, tostring(d.Enabled)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

-- where a world point lands on the current camera's screen
local function project(p: Vector3): (number, number, number)
	local cf = cam.CFrame
	local rel = cf:PointToObjectSpace(p)
	local tv = math.tan(math.rad(cam.FieldOfView) / 2)
	local v = cam.ViewportSize
	local asp = v.X / v.Y
	-- object space: +X is the camera's RightVector (screen right), +Y its UpVector, -Z forward
	return (rel.X / -rel.Z) / (tv * asp), (rel.Y / -rel.Z) / tv, -rel.Z
end
local function inFrame(sx: number, sy: number, depth: number): boolean
	return depth > 0 and math.abs(sx) <= 1 and math.abs(sy) <= 1
end
local function matches(where: string, sx: number, sy: number): boolean
	local ok = true
	local function has(w: string): boolean
		return string.find(" " .. where .. " ", " " .. w .. " ", 1, true) ~= nil
	end
	if has("upper") and not (sy > 0) then ok = false end
	if has("lower") and not (sy < 0) then ok = false end
	if has("top") and not (sy > 1 / 3) then ok = false end
	if has("bottom") and not (sy < -1 / 3) then ok = false end
	if has("third") then
		if has("left") and not (sx < -1 / 3) then ok = false end
		if has("right") and not (sx > 1 / 3) then ok = false end
	else
		if has("left") and not (sx < 0) then ok = false end
		if has("right") and not (sx > 0) then ok = false end
	end
	if has("centre") and not (math.abs(sx) <= 1 / 3) then ok = false end
	return ok
end
local function isShown(d): boolean
	return d:IsDescendantOf(h.workspace) and d.Transparency < 1
end

-- The entrance as the server built it: inner wall faces, ceiling underside, floor top, at z = Front.
local door = nil
local function doorOf()
	if door then return door end
	local wallR, wallL, ceiling, floor = zone:FindFirstChild("WallR"), zone:FindFirstChild("WallL"), zone:FindFirstChild("Ceiling"), zone:FindFirstChild("Floor")
	door = {
		xl = wallL.Position.X + wallL.Size.X / 2, xr = wallR.Position.X - wallR.Size.X / 2,
		yf = floor.Position.Y + floor.Size.Y / 2, yc = ceiling.Position.Y - ceiling.Size.Y / 2,
		z = O.Z + Sky.Hall.Front,
	}
	return door
end
-- From a lens inside the hall, a point beyond the entrance is seen only through the opening.
local function throughDoor(p: Vector3): boolean
	local d = doorOf()
	local from = cam.CFrame.Position
	if from.Z >= d.z or p.Z <= d.z then return true end
	local t = (d.z - from.Z) / (p.Z - from.Z)
	local q = from + (p - from) * t
	return q.X > d.xl and q.X < d.xr and q.Y > d.yf and q.Y < d.yc
end

-- one callout: returns (ok, description)
local function callout(c): (boolean, string)
	local what, where = c[1], c[2]
	if string.sub(what, 1, 5) == "beam:" then
		local pat = string.sub(what, 6)
		local n, sx, sy = 0, 0, 0
		for _, b in folder:GetDescendants() do
			if b:IsA("Beam") and b.Enabled and string.match(b.Name, pat) then
				local host = b.Parent
				local a0 = host.CFrame:PointToWorldSpace(b.Attachment0.Position)
				local a1 = host.CFrame:PointToWorldSpace(b.Attachment1.Position)
				local x0, y0, d0 = project(a0)
				local x1, y1, d1 = project(a1)
				if inFrame(x0, y0, d0) and inFrame(x1, y1, d1) and throughDoor(a0) and throughDoor(a1) then
					n += 1
					sx += (x0 + x1) / 2
					sy += (y0 + y1) / 2
				end
			end
		end
		if n < (c.min or 1) then return false, string.format("%s: %d in frame, want %d", what, n, c.min or 1) end
		sx, sy = sx / n, sy / n
		return matches(where, sx, sy), string.format("%s (%d beams) at sx %+.2f sy %+.2f, want %q", what, n, sx, sy, where), sx, sy
	elseif string.sub(what, 1, 1) == "^" then
		local n, sx, sy = 0, 0, 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and string.match(d.Name, what) and isShown(d) then
				local x, y, dep = project(d.Position)
				if inFrame(x, y, dep) and throughDoor(d.Position) then
					n += 1
					sx += x
					sy += y
				end
			end
		end
		if n < (c.min or 1) then return false, string.format("%s: %d shown in frame, want %d", what, n, c.min or 1) end
		sx, sy = sx / n, sy / n
		return matches(where, sx, sy), string.format("%s (%d) centre at sx %+.2f sy %+.2f, want %q", what, n, sx, sy, where), sx, sy
	end
	local d = folder:FindFirstChild(what, true)
	if d == nil or not isShown(d) then return false, what .. " is not shown" end
	local x, y, dep = project(d.Position)
	if not inFrame(x, y, dep) then return false, string.format("%s is out of frame (sx %+.2f sy %+.2f)", what, x, y) end
	if not throughDoor(d.Position) then return false, what .. " is hidden by the hall (not seen through the doorway)" end
	return matches(where, x, y), string.format("%s at sx %+.2f sy %+.2f, want %q", what, x, y, where), x, y
end

-- the camera of a shot
local function aim(shot)
	local c = shot.cam
	if c.kind == "break" then
		UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.B, UserInputType = Enum.UserInputType.Keyboard }, false)
		run(1)
		return
	end
	local from = O + v3(c.from)
	local to
	if c.at then
		to = O + v3(c.at)
	else
		local az, p = math.rad(c.az), math.rad(c.pitch)
		to = from + Vector3.new(math.sin(az) * math.cos(p), math.sin(p), math.cos(az) * math.cos(p)) * 100
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(from, to)
	cam.FieldOfView = 70
	run(0.2)
end
local function unaim(shot)
	if shot.cam.kind == "break" then
		UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.B, UserInputType = Enum.UserInputType.Keyboard }, false)
		run(1.2)
	else
		cam.CameraType = originalType
		run(0.2)
	end
end

-- the moon words: "waxing"/"waning" and "crescent"/"gibbous"/"full"/"new" are the Day's phase
local function moonWordsOk(words: string, day: number): (boolean, string)
	local phase = NightSky.moonPhase(Sky.Moon, day)
	local lit = NightSky.litFraction(phase)
	local ok = true
	if string.find(words, "waxing", 1, true) and not (phase < 0.5) then ok = false end
	if string.find(words, "waning", 1, true) and not (phase > 0.5) then ok = false end
	if string.find(words, "crescent", 1, true) and not (lit > 0.03 and lit < 0.5) then ok = false end
	if string.find(words, "gibbous", 1, true) and not (lit >= 0.5 and lit < 0.97) then ok = false end
	if string.find(words, "full", 1, true) and not (lit >= 0.97) then ok = false end
	return ok, string.format("phase %.3f, lit %.2f", phase, lit)
end

-- ------------------------------------------------------------------ the session
print("   shot list: " .. VERSION)
run(2)
folder = h.workspace:FindFirstChild("ObservatorySky")
assert(folder ~= nil, "the sky client built no sky")
for _, shot in SHOTS do
	local tag = string.format("Shot %d '%s' (Day %d)", shot.n, shot.title, shot.day)
	-- §9: set the Day from the Server command bar, then wait
	plr.leaderstats.Day.Value = shot.day
	run(WAIT_SECONDS)
	local a = settledPrint()
	run(30)
	truthy(a == settledPrint(), tag .. ": the sky has settled within the " .. WAIT_SECONDS .. " s §9 says to wait")

	if shot.moonWords then
		local ok, why = moonWordsOk(shot.moonWords, shot.day)
		truthy(ok, tag .. ": the moon is '" .. shot.moonWords .. "' (" .. why .. ")")
	end

	-- the avatar, parked the way §9 parks it
	local avatarBox = nil
	if shot.avatar then
		root.Anchored = true
		root.CFrame = CFrame.lookAt(O + v3(shot.avatar.at), O + v3(shot.avatar.lookAt))
		avatarBox = root.CFrame
	end

	aim(shot)
	for _, c in shot.must do
		local ok, why, mx, my = callout(c)
		print(string.format("   shot %d  %s  %s", shot.n, if ok then "ok  " else "FAIL", why))
		truthy(ok, tag .. ": " .. why)
		if c.at then
			truthy(mx ~= nil and math.abs(mx - c.at[1]) <= AT_TOL and math.abs(my - c.at[2]) <= AT_TOL,
				string.format("%s: the printed position of %s (sx %+.2f, sy %+.2f) is the measured one (sx %s, sy %s)",
					tag, c[1], c.at[1], c.at[2], if mx then string.format("%+.2f", mx) else "?", if my then string.format("%+.2f", my) else "?"))
		end
	end
	if shot.moonAbove then
		local m = folder:FindFirstChild("Moon", true)
		local p = folder:FindFirstChild(shot.moonAbove, true)
		local mx, my = project(m.Position)
		local px, py = project(p.Position)
		truthy(my > py and math.abs(mx - px) < 0.1, string.format("%s: the moon is above %s (moon sx %+.2f sy %+.2f, %s sx %+.2f sy %+.2f)",
			tag, shot.moonAbove, mx, my, shot.moonAbove, px, py))
	end
	-- the lit side: the dark disc is on the unlit side, on screen
	do
		local m = folder:FindFirstChild("Moon", true)
		local s = folder:FindFirstChild("MoonShade", true)
		if m and s and isShown(m) and isShown(s) then
			local mx = project(m.Position)
			local sx = project(s.Position)
			local waxing = NightSky.moonPhase(Sky.Moon, shot.day) < 0.5
			truthy(if waxing then sx < mx else sx > mx, string.format("%s: the %s moon's lit limb is on the %s on screen (shade sx %+.3f, moon sx %+.3f)",
				tag, if waxing then "waxing" else "waning", if waxing then "right" else "left", sx, mx))
		end
	end
	if avatarBox then
		-- an R15 avatar standing on the floor: 3 wide, from the floor (root - 3) to the head (root + 2.5)
		local allIn, cx, cy = true, 0, 0
		for _, x in { -1.5, 1.5 } do
			for _, y in { -3, 2.5 } do
				for _, z in { -0.8, 0.8 } do
					local sx, sy, dep = project(avatarBox:PointToWorldSpace(Vector3.new(x, y, z)))
					if not inFrame(sx, sy, dep) then allIn = false end
					cx += sx / 8
					cy += sy / 8
				end
			end
		end
		print(string.format("   shot %d  avatar centre sx %+.2f sy %+.2f (%s)", shot.n, cx, cy, if allIn then "wholly in frame" else "CUT BY THE FRAME"))
		truthy(allIn, string.format("%s: the whole avatar is in the frame (centre sx %+.2f sy %+.2f)", tag, cx, cy))
		truthy(matches(shot.avatar.where, cx, cy), string.format("%s: the avatar is in the %s (centre sx %+.2f sy %+.2f)", tag, shot.avatar.where, cx, cy))
		truthy(math.abs(cx - shot.avatar.sxy[1]) <= AT_TOL and math.abs(cy - shot.avatar.sxy[2]) <= AT_TOL,
			string.format("%s: the printed avatar centre (sx %+.2f, sy %+.2f) is the measured one (sx %+.2f, sy %+.2f)",
				tag, shot.avatar.sxy[1], shot.avatar.sxy[2], cx, cy))
	end
	if shot.rim then
		local d = doorOf()
		local out = {}
		for _, p in { Vector3.new(d.xl, d.yc, d.z), Vector3.new(d.xr, d.yc, d.z), Vector3.new(d.xl, d.yf, d.z), Vector3.new(d.xr, d.yf, d.z) } do
			local sx, sy, dep = project(p)
			if not inFrame(sx, sy, dep) then table.insert(out, string.format("(%.1f, %.1f) at sx %+.2f sy %+.2f", p.X - O.X, p.Y - O.Y, sx, sy)) end
		end
		eq(#out, 0, tag .. ": the whole doorway frames the sky (all four corners of the opening in frame): " .. table.concat(out, "; "))
	end
	if shot.rain then
		local rainOn = false
		for _, e in folder:GetDescendants() do
			if e:IsA("ParticleEmitter") and e.Parent and e.Parent.Name == "RainHost" and e.Enabled and e.Rate > 0 then rainOn = true end
		end
		truthy(rainOn, tag .. ": the rain is falling")
	end
	-- (2026-10-01, pass 2) every band has its own weather now, and it falls in front of the lens: each shot names
	-- the weather in its frame (a kind, "rain", or "clear") and its note tells the night shift; the emitters on
	-- at the shot are exactly that
	do
		local on = {}
		for _, e in folder:GetDescendants() do
			if e:IsA("ParticleEmitter") and e.Enabled and e.Rate > 0 then
				local k = if e.Name == "Rain" then "rain" else string.match(e.Name, "^Weather_(%a+)$")
				if k then table.insert(on, k) end
			end
		end
		table.sort(on)
		local got = if #on == 0 then "clear" else table.concat(on, "+")
		eq(tostring(shot.weather), got, tag .. ": the shot list names the weather falling at the shot")
		local word = WEATHER_WORD[got] or got
		truthy(type(shot.note) == "string" and string.find(string.lower(shot.note), word, 1, true) ~= nil,
			tag .. ": and its note tells the night shift (" .. word .. ")")
	end
	if shot.bolt then
		-- §9: record a minute and pull the frame; a flash is 0.14 s, about 11 a minute
		local flashes, inside = 0, 0
		local lit = false
		for _ = 1, 60 * 30 do
			frame()
			local seg = { folder:FindFirstChild("Bolt1", true), folder:FindFirstChild("Bolt2", true), folder:FindFirstChild("Bolt3", true) }
			local on = seg[1] ~= nil and isShown(seg[1])
			if on and not lit then
				flashes += 1
				local all = true
				for _, b in seg do
					for _, zz in { -0.5, 0.5 } do
						local sx, sy, dep = project(b.CFrame:PointToWorldSpace(Vector3.new(0, 0, b.Size.Z * zz)))
						if not (b and isShown(b) and inFrame(sx, sy, dep)) then all = false end
					end
				end
				if all then inside += 1 end
			end
			lit = on
		end
		print(string.format("   shot %d  %d flashes in a minute, %d wholly in frame", shot.n, flashes, inside))
		truthy(inside >= 3, string.format("%s: a minute of recording catches lightning in frame (%d of %d flashes wholly in frame)", tag, inside, flashes))
		eq(flashes, shot.bolt.flashes, tag .. ": the printed flash count is the measured one")
		eq(inside, flashes, tag .. ": every flash of the minute is wholly in frame, as printed")
	end
	if shot.cam.kind == "break" and shot.n == 5 then
		-- §9's pan note, measured on this shot: 20 s into the break
		local m = folder:FindFirstChild("Mercury", true)
		local x1 = project(m.Position)
		run(19)
		local x20 = project(m.Position)
		local panned = if x20 > x1 then "left" else "right" -- the view turns one way, objects drift the other
		eq(panned, PAN_20S, string.format("§9's pan note: 20 s into a break the view has panned %s (Mercury sx %+.2f -> %+.2f)", PAN_20S, x1, x20))
		truthy(math.abs(x1 - List.pan.mercuryFrom) <= AT_TOL and math.abs(x20 - List.pan.mercuryTo) <= AT_TOL,
			string.format("the printed pan numbers (Mercury sx %+.2f -> %+.2f) are the measured ones (%+.2f -> %+.2f)",
				List.pan.mercuryFrom, List.pan.mercuryTo, x1, x20))
	end
	unaim(shot)
	if shot.avatar then
		root.Anchored = false
	end
end

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomalyobservatory_shots: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory shots check failed", 0)
end
