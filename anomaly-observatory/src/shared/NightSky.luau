--!strict
-- NightSky.luau — the night sky outside the observatory, as pure numbers. No Roblox types.
--
-- The rule this whole module exists to keep: THE HALL NEVER CHANGES. The game is spot-the-difference
-- (Config.Anomaly): the hall is rebuilt each pass and is either clean or wrong in exactly one way,
-- so any other variation inside it reads as an anomaly. The sky therefore lives only where the hall
-- cannot show it. The concourse is a sealed box, open only at its +Z end (z = Hall.Front, behind the
-- spawn pad and behind the marketing rig's camera, which looks down the hall toward -Z). Every piece
-- of sky, and everything that moves through it, is placed BEYOND that entrance plane with Clearance
-- to spare, and `validate` refuses a config that breaks this. Nothing here reads the pass: the sky is
-- a function of the Day (already public in leaderstats) and of its own clock, and nothing else.
--
-- Also here, because it is all geometry:
--   * the moon's phase for a Day, and how far to slide a dark disc across it to draw that phase;
--   * a deterministic schedule for meteors and silent lightning;
--   * the telescope-break camera pose, and `minRayZ`, the proof that no ray from it can enter a hall;
--   * `isReddish`: two anomalies are "a red wall panel" and "the window gone red", so the sky must
--     never teach the player that red is normal;
--   * `engineSizeOk`: sizes Roblox draws as written (a Ball is forced uniform, a Cylinder round, every
--     Part axis clamped to 2048), which the emulator does not model;
--   * `breakCaption`: what a break may promise (the streak lives only for the session and Roblox
--     disconnects an idle player, so never "safe").
--
-- Dependencies (EnvBands, Rest) are passed in: `require("./X")` resolves in the luau CLI and is
-- INVALID in Roblox. Colours are {r, g, b} 0-255 arrays, never Color3, so this runs in the CLI.

export type Vec = { x: number, y: number, z: number }

local NightSky = {}

-- Everything a band can show, each blended 0..1 by EnvBands. `land` (the ridge, the mist in the
-- valley and its few lights) is not a feature: it is the place, and it is there every night.
NightSky.FEATURES = { "stars", "moon", "meteors", "aurora", "comet", "storm", "nebula", "planets", "othersky" }

local function isNaN(x: number): boolean
	return x ~= x
end

-- A small deterministic [0, 1) from a value and an index. Used for layout scatter and bolt jitter,
-- where no seeded dependency is available (layout also runs inside validate).
local function jitter(u: number, i: number): number
	local x = math.sin((u * 1000 + i * 12.9898) * 43758.5453)
	return x - math.floor(x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function saneDay(day: number): number
	if type(day) ~= "number" or isNaN(day) or day < 1 then
		return 1
	end
	return day
end

-- ------------------------------------------------------------------ geometry

-- The server's zoneOrigin(index): Vector3.new(index * 1000, 100, 0).
function NightSky.hallOrigin(hall: any, index: number): Vec
	return { x = index * hall.Spacing, y = hall.OriginY, z = 0 }
end

function NightSky.eye(hall: any, origin: Vec): Vec
	return { x = origin.x, y = origin.y + hall.EyeHeight, z = origin.z }
end

-- A point `dist` studs from `eye`: azimuth from +Z (straight out of the entrance) toward +X,
-- elevation up from the horizontal. Degrees.
function NightSky.skyPoint(eye: Vec, azDeg: number, elDeg: number, dist: number): Vec
	local az, el = math.rad(azDeg), math.rad(elDeg)
	return {
		x = eye.x + dist * math.cos(el) * math.sin(az),
		y = eye.y + dist * math.sin(el),
		z = eye.z + dist * math.cos(el) * math.cos(az),
	}
end

-- A sphere of `radius` at `centre` lies entirely beyond the hall's entrance plane with `margin` to
-- spare. The hall occupies z <= Front (relative to its origin), so this is the whole test: it holds
-- however far out to the side the sphere is.
function NightSky.clearOfHall(hall: any, origin: Vec, centre: Vec, radius: number, margin: number): boolean
	return centre.z - radius - origin.z >= hall.Front + margin
end

-- Can the engine draw this piece at the size the layout gives it? robloxemu keeps any size it is
-- given; Roblox does not: a Ball is forced to a uniform size, a Cylinder is drawn round (its Y and Z
-- must agree), and every Part axis is clamped to 2048 studs (and has a floor). A flattened sphere is
-- an "Ellipsoid": SkyArt draws it as a Block with a Sphere SpecialMesh, which fills the box.
-- (Review 2026-09-24: the storm's clouds were Balls sized (2r, 1.3r, 2r) and the Milky Way a 2200-stud
-- Block, and every headless measurement described a sky Roblox would not draw.)
NightSky.MAX_PART_AXIS = 2048
NightSky.MIN_PART_AXIS = 0.05
function NightSky.engineSizeOk(p: any): (boolean, string?)
	local s = p.size
	for _, axis in { "x", "y", "z" } do
		local v = s and s[axis]
		if type(v) ~= "number" or isNaN(v) or v < NightSky.MIN_PART_AXIS or v > NightSky.MAX_PART_AXIS then
			return false, string.format("size.%s = %s is outside the engine's %g..%d studs", axis, tostring(v),
				NightSky.MIN_PART_AXIS, NightSky.MAX_PART_AXIS)
		end
	end
	if p.shape == "Ball" and (math.abs(s.x - s.y) > 1e-6 or math.abs(s.x - s.z) > 1e-6) then
		return false, "a Ball must be uniform (Roblox forces it); use an Ellipsoid for a flattened sphere"
	end
	if p.shape == "Cylinder" and math.abs(s.y - s.z) > 1e-6 then
		return false, "a Cylinder's Y and Z must agree (Roblox draws it round)"
	end
	return true, nil
end

-- Bounding-sphere radius of a layout piece.
function NightSky.pieceRadius(p: any): number
	local s = p.size
	return 0.5 * math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z)
end

local function vscale(v: Vec, k: number): Vec
	return { x = v.x * k, y = v.y * k, z = v.z * k }
end
local function vadd(a: Vec, b: Vec): Vec
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end
local function rotatePair(a: Vec, b: Vec, deg: number): (Vec, Vec)
	local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return vadd(vscale(a, c), vscale(b, s)), vadd(vscale(a, -s), vscale(b, c))
end

-- The world directions of a piece's local X, Y and Z axes: exactly the rotation SkyArt gives the
-- Part (CFrame.fromMatrix(pos, X, Y, Z)), so the clearance proof and the rendering cannot disagree.
--   face = true   a slab turned to face the hall's eye point (X right, Y up, Z toward the eye),
--                 then rolled `roll` degrees about Z;
--   Cylinder      a disc whose axis (local X) points at the eye, tilted `tilt` degrees;
--   Wedge         an upright ridge whose triangular profile (seen along local X) faces the eye;
--                 `mirror` turns it round so neighbouring ridges slope opposite ways;
--   otherwise     world-aligned.
function NightSky.pieceAxes(p: any, eye: Vec): any
	if p.shape == "Wedge" then
		local b = NightSky.faceBasis(eye, p.pos)
		local fx, fz = b.forward.x, b.forward.z
		local l = math.sqrt(fx * fx + fz * fz)
		fx, fz = fx / l, fz / l
		local X, Y, Z = { x = fx, y = 0, z = fz }, { x = 0, y = 1, z = 0 }, { x = -fz, y = 0, z = fx }
		if p.mirror then
			X, Z = vscale(X, -1), vscale(Z, -1)
		end
		return { X = X, Y = Y, Z = Z }
	elseif p.shape == "Cylinder" and p.face then
		local b = NightSky.faceBasis(eye, p.pos)
		local X, Y = b.forward, b.up
		if p.tilt then
			X, Y = rotatePair(X, Y, p.tilt)
		end
		-- Z = X x Y keeps the frame right-handed
		return { X = X, Y = Y, Z = {
			x = X.y * Y.z - X.z * Y.y, y = X.z * Y.x - X.x * Y.z, z = X.x * Y.y - X.y * Y.x,
		} }
	elseif p.face then
		local b = NightSky.faceBasis(eye, p.pos)
		local X, Y = b.right, b.up
		if p.roll then
			X, Y = rotatePair(X, Y, p.roll)
		end
		return { X = X, Y = Y, Z = b.forward }
	end
	return { X = { x = 1, y = 0, z = 0 }, Y = { x = 0, y = 1, z = 0 }, Z = { x = 0, y = 0, z = 1 } }
end

-- The eight corners of a piece's oriented box.
function NightSky.pieceCorners(p: any, eye: Vec): { Vec }
	local ax = NightSky.pieceAxes(p, eye)
	local hx, hy, hz = vscale(ax.X, p.size.x / 2), vscale(ax.Y, p.size.y / 2), vscale(ax.Z, p.size.z / 2)
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, vadd(p.pos, vadd(vscale(hx, sx), vadd(vscale(hy, sy), vscale(hz, sz)))))
			end
		end
	end
	return out
end

-- How far beyond the hall's origin (in z) the nearest corner of a piece is.
function NightSky.pieceMinZ(p: any, eye: Vec): number
	local m = math.huge
	for _, c in NightSky.pieceCorners(p, eye) do
		if c.z < m then m = c.z end
	end
	return m
end

-- Is `point` inside the piece's oriented box grown by `pad` on every side?
function NightSky.pieceContains(p: any, eye: Vec, point: Vec, pad: number): boolean
	local ax = NightSky.pieceAxes(p, eye)
	local d = { x = point.x - p.pos.x, y = point.y - p.pos.y, z = point.z - p.pos.z }
	for _, pair in { { ax.X, p.size.x }, { ax.Y, p.size.y }, { ax.Z, p.size.z } } do
		local a, len = pair[1], pair[2]
		if math.abs(d.x * a.x + d.y * a.y + d.z * a.z) > len / 2 + pad then
			return false
		end
	end
	return true
end

-- ------------------------------------------------------------------ moon

function NightSky.moonPhase(moon: any, day: number): number
	local d = saneDay(day)
	local p = (moon.PhaseAtDay1 + (d - 1) / moon.SynodicDays) % 1
	if p < 0 then p += 1 end
	if p >= 1 then p -= 1 end
	return p
end

-- Fraction of the disc that is lit at `phase` (0 new, 0.5 full).
function NightSky.litFraction(phase: number): number
	return (1 - math.cos(2 * math.pi * phase)) / 2
end

-- Lit fraction of a unit disc when a same-size dark disc sits `offset` radii away (the drawn moon).
function NightSky.litAreaFraction(offset: number): number
	local d = math.max(0, offset)
	if d >= 2 then return 1 end
	-- lens (overlap) area of two unit circles d apart
	local lens = 2 * math.acos(d / 2) - (d / 2) * math.sqrt(4 - d * d)
	return (math.pi - lens) / math.pi
end

-- Inverse of litAreaFraction by bisection: the offset (in radii) that lights fraction k.
function NightSky.luneOffset(k: number): number
	if type(k) ~= "number" or isNaN(k) or k <= 0 then return 0 end
	if k >= 1 then return 2 end
	local lo, hi = 0, 2
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		if NightSky.litAreaFraction(mid) < k then lo = mid else hi = mid end
	end
	return (lo + hi) / 2
end

-- (offset in radii, side). side = 1: the lit limb is on the viewer's right (waxing, as seen from the
-- northern hemisphere), so the dark disc slides to the LEFT; side = -1 is waning.
function NightSky.moonShadow(moon: any, day: number): (number, number)
	local phase = NightSky.moonPhase(moon, day)
	local side = if phase < 0.5 then 1 else -1
	return NightSky.luneOffset(NightSky.litFraction(phase)), side
end

-- Glide a phase toward a target along the SHORT way round the circle, frame-rate independently
-- (`halfLife` seconds halves the gap). Gliding the drawn offset instead would, across a full moon,
-- swing the dark disc from one side to the other straight over the moon.
-- `maxRate` (cycles per second, optional) caps the speed, so a long swing (a reset back to Day 1)
-- turns the moon over seconds and never races through new moon.
function NightSky.phaseApproach(current: number, target: number, dt: number, halfLife: number, maxRate: number?): number
	if halfLife <= 0 then return target end
	local gap = ((target - current + 0.5) % 1) - 0.5
	local alpha = 1 - 0.5 ^ (math.max(dt, 0) / halfLife)
	local step = gap * alpha
	if maxRate then
		local cap = maxRate * math.max(dt, 0)
		step = math.clamp(step, -cap, cap)
	end
	local p = (current + step) % 1
	if math.abs(gap - step) < 1e-9 then p = target end
	return p
end

-- What to draw for a phase. Near full the shade is hidden (it would only hang beside the moon as a
-- dark disc); near new nothing is drawn at all.
-- Both fade rather than switch (moonAlpha, shadeAlpha in 0..1), so a phase gliding across full or
-- new moon never makes anything appear or vanish in one frame.
local MOON_FADE = { 0.004, 0.03 } -- the moon fades in over this lit fraction
local SHADE_FADE = { 0.95, 0.992 } -- the shade fades out over this lit fraction

local function smooth01(x: number): number
	if x <= 0 then return 0 end
	if x >= 1 then return 1 end
	return x * x * (3 - 2 * x)
end

function NightSky.moonDraw(phase: number): any
	local k = NightSky.litFraction(phase)
	local moonAlpha = smooth01((k - MOON_FADE[1]) / (MOON_FADE[2] - MOON_FADE[1]))
	local shadeAlpha = moonAlpha * (1 - smooth01((k - SHADE_FADE[1]) / (SHADE_FADE[2] - SHADE_FADE[1])))
	return {
		lit = k,
		offset = NightSky.luneOffset(k),
		side = if phase % 1 < 0.5 then 1 else -1,
		moonAlpha = moonAlpha,
		shadeAlpha = shadeAlpha,
		showMoon = moonAlpha > 0,
		showShade = shadeAlpha > 0,
	}
end

-- ------------------------------------------------------------------ bands

-- Feature weights at `day`: every FEATURE, as a number, in a fresh table.
function NightSky.features(bands: { any }, EnvBands: any, day: number): { [string]: number }
	local d = if type(day) == "number" and not isNaN(day) then day else 1
	local s = EnvBands.sample(bands, d, "features")
	local out = {}
	for _, k in NightSky.FEATURES do
		local v = s[k]
		out[k] = if type(v) == "number" then v else 0
	end
	return out
end

-- The band just entered, when newDay's band is HIGHER than prevDay's; nil otherwise (same band, a
-- reset back down, nonsense input). A NaN previous Day counts as Day 1.
function NightSky.bandUp(bands: { any }, EnvBands: any, prevDay: number, newDay: number): number?
	if type(newDay) ~= "number" or isNaN(newDay) then return nil end
	local a = EnvBands.indexAt(bands, saneDay(prevDay))
	local b = EnvBands.indexAt(bands, newDay)
	if b > a then return b end
	return nil
end

-- What the chip says: the band (by index) and how many Days to the next one.
function NightSky.describe(bands: { any }, EnvBands: any, day: number): any
	local d = saneDay(day)
	local i = EnvBands.indexAt(bands, d)
	local b = bands[i]
	local nb = bands[i + 1]
	return {
		index = i,
		id = b.id,
		name = b.name,
		emoji = b.emoji,
		nextIndex = if nb then i + 1 else nil,
		nextIn = if nb then nb.from - d else nil,
	}
end

-- ------------------------------------------------------------------ the break's words
-- (Review 2026-09-24.) What a break may promise. The Day streak lives only in the server's memory for
-- this session (Best Day is what is saved), and Roblox disconnects a player idle for about 20 minutes,
-- which starts a new session at Day 1. A break IS a player not touching the controls, so the caption
-- never calls the Day "safe"; once Roblox reports the player idle (Player.Idled) it says what the kick
-- costs, until any input clears it. `news` is a line about something new out here (bandNews, or on a
-- phone the join tip, introNews): a phone shows no unrequested caption over the hall, so its news waits
-- for the break, where nothing of the hall is on screen.

-- A new band, as the break announces it.
function NightSky.bandNews(band: any, compact: boolean): string
	if compact then
		return band.emoji .. " " .. band.name
	end
	return band.emoji .. " " .. band.name .. " tonight."
end

-- The join tip, which a phone shows on its first break instead of over the hall.
function NightSky.introNews(compact: boolean): string
	if compact then
		return "🔭 The sky changes as your Day grows"
	end
	return "🔭 The sky out here changes as your Day grows."
end

-- c = { day, compact, news?, idle, kickMinutes }
function NightSky.breakCaption(c: any): string
	local d = math.floor(saneDay(c.day))
	local kick = if type(c.kickMinutes) == "number" and not isNaN(c.kickMinutes) then math.floor(c.kickMinutes) else 20
	if c.idle then
		if c.compact then
			return string.format("☕ Idle %d min = disconnect, back to Day 1. Move!", kick)
		end
		return string.format("☕ Still there? Roblox disconnects players idle for %d minutes, and a new session starts at Day 1 "
			.. "(you are on Day %d). Move or press ▶ to go back.", kick, d)
	end
	local news = if type(c.news) == "string" and c.news ~= "" then c.news else nil
	if c.compact then
		if news then
			return news .. " · Move to go back."
		end
		return "☕ Break · your hall waits. Move to go back."
	end
	local body = "☕ On a break: your hall is waiting, exactly as you left it. Move or press ▶ to go back."
	if news then
		return news .. " " .. body
	end
	return body
end

-- ------------------------------------------------------------------ events
-- Time is cut into slots of SlotSeconds. Each slot MAY carry one event, which starts and ends inside
-- the slot, so two events of a kind never overlap and one pooled part per kind (two for meteors,
-- which alternate so a fading trail is never dragged across the sky) is enough. Whether a slot
-- carries one is decided by the caller on the slot's first frame: roll < Chance * weight.

function NightSky.slotOf(spec: any, t: number): number
	return math.floor(t / spec.SlotSeconds)
end

function NightSky.slotEvent(spec: any, slot: number, seed: number, EnvBands: any): any
	local salt = spec.Salt or 0
	local u = {}
	for i = 1, 6 do
		u[i] = EnvBands.hash01(slot, salt, i, seed)
	end
	local room = math.max(0, spec.SlotSeconds - spec.Duration)
	return {
		slot = slot,
		start = slot * spec.SlotSeconds + u[1] * room,
		duration = spec.Duration,
		roll = u[2],
		u = u,
	}
end

-- A meteor streak, as angles: Length degrees long, falling, entirely inside the window.
function NightSky.meteorPath(spec: any, ev: any): any
	local az0, az1 = spec.AzRange[1], spec.AzRange[2]
	local el0, el1 = spec.ElRange[1], spec.ElRange[2]
	local L = spec.Length
	-- heading: downward, between 20 and 70 degrees below the horizontal, left or right
	local down = math.rad(lerp(20, 70, ev.u[3]))
	local sgn = if ev.u[4] < 0.5 then -1 else 1
	local dAz, dEl = sgn * L * math.cos(down), -L * math.sin(down)
	-- start anywhere the whole streak still fits
	local azLo, azHi = math.max(az0, az0 - dAz), math.min(az1, az1 - dAz)
	local elLo, elHi = el0 - dEl, el1 -- dEl < 0: the start must be high enough to end inside
	local fromAz = lerp(azLo, azHi, ev.u[5])
	local fromEl = lerp(math.min(elLo, elHi), elHi, ev.u[6])
	return { from = { az = fromAz, el = fromEl }, to = { az = fromAz + dAz, el = fromEl + dEl } }
end

-- A lightning bolt inside the storm's sector: four points, each lower than the last.
function NightSky.boltPath(spec: any, ev: any): { any }
	local az0, az1 = spec.AzRange[1], spec.AzRange[2]
	local el0, el1 = spec.ElRange[1], spec.ElRange[2]
	local midAz = lerp(az0 + 3, az1 - 3, ev.u[3])
	local top = lerp(el0 + (el1 - el0) * 0.6, el1, ev.u[4])
	local bottom = lerp(el0, el0 + (el1 - el0) * 0.3, ev.u[5])
	local pts = {}
	for i = 0, 3 do
		local f = i / 3
		local jig = if i == 0 or i == 3 then 0 else (jitter(ev.u[6], i) - 0.5) * 4
		table.insert(pts, { az = math.clamp(midAz + jig, az0, az1), el = lerp(top, bottom, f) })
	end
	return pts
end

-- ------------------------------------------------------------------ the telescope break

-- Camera pose relative to the hall origin: a slow clock-drive pan. Offset is fixed; the look drifts
-- by at most YawSwayDegrees / PitchSwayDegrees around straight out of the entrance.
function NightSky.restPose(view: any, t: number): any
	local w = 2 * math.pi / view.SwayPeriod
	-- yaw and pitch drift on different periods so the pan never repeats a straight line; both are
	-- exactly zero drift at t = 0
	local yaw = view.YawSwayDegrees * math.sin(w * t)
	local pitch = view.PitchDegrees + view.PitchSwayDegrees * math.sin(w * t * 0.7)
	return {
		pos = { x = view.Offset[1], y = view.Offset[2], z = view.Offset[3] },
		look = NightSky.lookFrom(yaw, pitch),
	}
end

-- Unit look vector for a yaw (from +Z toward +X) and pitch (up), degrees.
function NightSky.lookFrom(yawDeg: number, pitchDeg: number): Vec
	local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
	return { x = math.cos(pitch) * math.sin(yaw), y = math.sin(pitch), z = math.cos(pitch) * math.cos(yaw) }
end

-- The smallest +Z component of any ray the camera draws when looking along `look` (unit) with a
-- vertical field of view `fovYDeg` on a screen of `aspect` (width / height). World up is +Y.
-- Positive means every ray leaves toward +Z, so from a camera beyond the entrance plane no ray can
-- reach anything at z <= Front: no hall, anywhere on the X axis, can be seen.
function NightSky.minRayZ(look: Vec, fovYDeg: number, aspect: number): number
	local tv = math.tan(math.rad(fovYDeg) / 2)
	local th = tv * aspect
	-- right = look x up(world), normalised; up' = right x look
	local rx, ry, rz = look.z, 0, -look.x
	local rl = math.sqrt(rx * rx + rz * rz)
	if rl < 1e-9 then
		rx, rz = 1, 0 -- looking straight up or down: any horizontal right will do
	else
		rx, rz = rx / rl, rz / rl
	end
	-- up' = right x look
	local ux = ry * look.z - rz * look.y
	local uy = rz * look.x - rx * look.z
	local uz = rx * look.y - ry * look.x
	local worst = math.huge
	for _, a in { -th, th } do
		for _, b in { -tv, tv } do
			local dx = look.x + a * rx + b * ux
			local dy = look.y + a * ry + b * uy
			local dz = look.z + a * rz + b * uz
			local z = dz / math.sqrt(dx * dx + dy * dy + dz * dz)
			if z < worst then worst = z end
		end
	end
	return worst
end

-- ------------------------------------------------------------------ colour

-- "Reads as red": hue within 20 degrees of red (330..360 or 0..20), saturated enough (>= 0.3) and
-- bright enough (>= 0.3) to be a colour at all. Amber, ochre and violet are not red.
function NightSky.isReddish(c: { number }): boolean
	local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local delta = mx - mn
	if mx < 0.3 then return false end
	if mx <= 0 or delta / mx < 0.3 then return false end
	local h
	if mx == r then
		h = 60 * (((g - b) / delta) % 6)
	elseif mx == g then
		h = 60 * ((b - r) / delta + 2)
	else
		h = 60 * ((r - g) / delta + 4)
	end
	if h < 0 then h += 360 end
	return h <= 20 or h >= 330
end

-- ------------------------------------------------------------------ layout
-- Every static piece of sky, as plain data SkyArt turns into Parts. Positions are world positions
-- for the hall at `origin`. `face = true` turns the piece's front toward the hall's eye point.
-- Shapes: "Ball", "Block", "Wedge", "Cylinder" (a disc: its axis faces the eye).

local function piece(list: { any }, p: any)
	p.transparency = p.transparency or 0
	p.material = p.material or "Neon"
	table.insert(list, p)
end

-- deterministic [0,1) for layout scatter (no dependency: layout must run in validate too)
local function scatter(i: number, salt: number): number
	return jitter(salt / 97, i)
end

function NightSky.layout(sky: any, origin: Vec): { any }
	local out = {}
	local eye = NightSky.eye(sky.Hall, origin)

	-- the place: a ridge on the horizon, mist in the valley, a few far lights
	local H = sky.Horizon
	if H then
		for i = 1, H.Count do
			local f = if H.Count > 1 then (i - 1) / (H.Count - 1) else 0.5
			local az = lerp(H.AzRange[1], H.AzRange[2], f)
			local h = lerp(H.Heights[1], H.Heights[2], scatter(i, 3))
			local w = lerp(H.Widths[1], H.Widths[2], scatter(i, 5))
			local base = NightSky.skyPoint(eye, az, 0, H.Distance)
			piece(out, {
				key = "Ridge" .. i, feature = "land", shape = "Wedge",
				pos = { x = base.x, y = eye.y - H.BelowEye + h / 2, z = base.z },
				-- a Wedge's triangle is seen along its local X: X is the depth, Z the base width
				size = { x = H.Depth, y = h, z = w }, mirror = (i % 2 == 0),
				color = H.Color, material = "SmoothPlastic",
			})
		end
	end
	local V = sky.Valley
	if V then
		for i = 1, V.MistCount do
			local az = lerp(-25, 25, if V.MistCount > 1 then (i - 1) / (V.MistCount - 1) else 0.5)
			local p = NightSky.skyPoint(eye, az, 0, V.MistDistance + (i - 1) * 90)
			piece(out, {
				key = "Mist" .. i, feature = "land", shape = "Block",
				pos = { x = p.x, y = eye.y - V.MistBelowEye, z = p.z },
				size = { x = V.MistSize[1], y = V.MistSize[2], z = V.MistSize[3] }, face = true,
				color = V.MistColor, transparency = V.MistTransparency, material = "SmoothPlastic",
			})
		end
		for i = 1, V.LightCount do
			local az = lerp(V.LightAzRange[1], V.LightAzRange[2], scatter(i, 7))
			local dist = lerp(V.LightDistance[1], V.LightDistance[2], scatter(i, 11))
			local p = NightSky.skyPoint(eye, az, 0, dist)
			piece(out, {
				key = "ValleyLight" .. i, feature = "land", shape = "Ball",
				pos = { x = p.x, y = eye.y - V.LightBelowEye + scatter(i, 13) * 12, z = p.z },
				size = { x = V.LightSize, y = V.LightSize, z = V.LightSize },
				color = V.LightColor,
			})
		end
	end

	-- the moon and the dark disc that draws its phase (SkyArt slides the shade; this is its home)
	local M = sky.Moon
	if M then
		local c = NightSky.skyPoint(eye, M.Azimuth, M.Elevation, M.Distance)
		local d = 2 * M.Radius
		piece(out, { key = "Moon", feature = "moon", shape = "Ball", pos = c, size = { x = d, y = d, z = d }, color = M.Color, role = "moon" })
		local s = NightSky.skyPoint(eye, M.Azimuth, M.Elevation, M.Distance - 2)
		piece(out, {
			key = "MoonShade", feature = "moon", shape = "Ball", pos = s, size = { x = d * 1.01, y = d * 1.01, z = d * 1.01 },
			color = M.ShadowColor, material = "SmoothPlastic", role = "shade",
		})
	end

	-- the star field: one invisible slab that twinkles (a ParticleEmitter)
	local S = sky.Stars
	if S then
		local c = NightSky.skyPoint(eye, S.Azimuth, S.Elevation, S.Distance)
		piece(out, {
			key = "StarField", feature = "stars", shape = "Block", pos = c,
			size = { x = S.Size[1], y = S.Size[2], z = S.Size[3] }, face = true,
			color = S.Color, transparency = 1, emitter = "stars",
		})
	end

	-- the meteor pool: parts that fly along NightSky.meteorPath, alternating by slot
	local Me = sky.Meteors
	if Me then
		local c = NightSky.skyPoint(eye, (Me.AzRange[1] + Me.AzRange[2]) / 2, (Me.ElRange[1] + Me.ElRange[2]) / 2, Me.Distance)
		for i = 1, Me.Pool do
			piece(out, {
				key = "Meteor" .. i, feature = "meteors", shape = "Block", pos = c,
				size = { x = Me.Size[1], y = Me.Size[2], z = Me.Size[3] },
				color = Me.Color, transparency = 1, live = true, role = "meteor",
			})
		end
	end

	-- aurora: one invisible host; the curtains are Beams between attachments SkyArt places
	local A = sky.Aurora
	if A then
		local c = NightSky.skyPoint(eye, (A.AzRange[1] + A.AzRange[2]) / 2, A.ElRange[1], A.Distance)
		piece(out, { key = "AuroraHost", feature = "aurora", shape = "Block", pos = c, size = { x = 1, y = 1, z = 1 }, color = A.Colors[1], transparency = 1, role = "auroraHost" })
	end

	-- the comet: head and coma; the tail is two Beams on the head
	local C = sky.Comet
	if C then
		local c = NightSky.skyPoint(eye, C.Azimuth, C.Elevation, C.Distance)
		local h, k = 2 * C.HeadRadius, 2 * C.ComaRadius
		piece(out, { key = "CometHead", feature = "comet", shape = "Ball", pos = c, size = { x = h, y = h, z = h }, color = C.Color, role = "cometHead" })
		piece(out, { key = "CometComa", feature = "comet", shape = "Ball", pos = c, size = { x = k, y = k, z = k }, color = C.ComaColor, transparency = C.ComaTransparency })
	end

	-- the storm: a dark cloud bank on the horizon, and the host the rain falls from
	local St = sky.Storm
	if St then
		for i = 1, St.CloudCount do
			local f = if St.CloudCount > 1 then (i - 1) / (St.CloudCount - 1) else 0.5
			local az = lerp(St.AzRange[1], St.AzRange[2], f) + (scatter(i, 17) - 0.5) * 6
			local el = lerp(St.ElRange[1], St.ElRange[2], scatter(i, 19))
			local r = lerp(St.Radius[1], St.Radius[2], scatter(i, 23))
			local p = NightSky.skyPoint(eye, az, el, St.Distance + (scatter(i, 29) - 0.5) * 60)
			-- flattened, so an Ellipsoid: a Ball cannot be (see engineSizeOk)
			piece(out, {
				key = "StormCloud" .. i, feature = "storm", shape = "Ellipsoid", pos = p,
				size = { x = 2 * r, y = 1.3 * r, z = 2 * r },
				color = St.Color, transparency = St.Transparency, material = "SmoothPlastic",
			})
		end
	end
	-- one lightning bolt: three segments SkyArt moves along NightSky.boltPath for each flash
	local Li = sky.Lightning
	if Li then
		local c = NightSky.skyPoint(eye, (Li.AzRange[1] + Li.AzRange[2]) / 2, (Li.ElRange[1] + Li.ElRange[2]) / 2, Li.Distance)
		for i = 1, 3 do
			piece(out, {
				key = "Bolt" .. i, feature = "storm", shape = "Block", pos = c,
				size = { x = Li.Thickness, y = Li.Thickness, z = 20 },
				color = Li.Color, transparency = 1, live = true, role = "bolt",
			})
		end
	end
	local R = sky.Rain
	if R then
		piece(out, {
			key = "RainHost", feature = "storm", shape = "Block",
			pos = { x = origin.x + R.Offset[1], y = origin.y + R.Offset[2], z = origin.z + R.Offset[3] },
			size = { x = R.Size[1], y = R.Size[2], z = R.Size[3] },
			color = R.Color, transparency = 1, emitter = "rain",
		})
	end

	-- deep sky: nebula clouds, the Milky Way, a distant galaxy
	local N = sky.Nebula
	if N then
		for i = 1, N.Count do
			local az = N.Azimuth + (scatter(i, 31) - 0.5) * N.Spread[1]
			local el = N.Elevation + (scatter(i, 37) - 0.5) * N.Spread[2]
			local r = lerp(N.Radius[1], N.Radius[2], scatter(i, 41))
			local p = NightSky.skyPoint(eye, az, el, N.Distance + (scatter(i, 43) - 0.5) * 80)
			piece(out, {
				key = "Nebula" .. i, feature = "nebula", shape = "Ball", pos = p,
				size = { x = 2 * r, y = 2 * r, z = 2 * r },
				color = N.Colors[(i - 1) % #N.Colors + 1], transparency = lerp(N.Transparency[1], N.Transparency[2], scatter(i, 47)),
			})
		end
		local MW = N.MilkyWay
		local mw = NightSky.skyPoint(eye, MW.Azimuth, MW.Elevation, MW.Distance)
		piece(out, {
			key = "MilkyWay", feature = "nebula", shape = "Block", pos = mw,
			size = { x = MW.Size[1], y = MW.Size[2], z = MW.Size[3] }, face = true, roll = MW.Tilt,
			color = MW.Color, transparency = MW.Transparency,
		})
		local G = N.Galaxy
		local g = NightSky.skyPoint(eye, G.Azimuth, G.Elevation, G.Distance)
		local gd = 2 * G.Radius
		piece(out, {
			key = "Galaxy", feature = "nebula", shape = "Cylinder", pos = g, size = { x = 2, y = gd, z = gd }, face = true,
			color = G.Color, transparency = G.Transparency,
		})
		local cr = G.Radius * 0.28
		piece(out, { key = "GalaxyCore", feature = "nebula", shape = "Ball", pos = g, size = { x = cr, y = cr, z = cr }, color = G.CoreColor })
	end

	-- the alignment: the planets on one line across the sky
	local P = sky.Planets
	if P then
		for _, pl in P.List do
			local p = NightSky.skyPoint(eye, pl.az, pl.el, P.Distance)
			local d = 2 * pl.r
			piece(out, { key = pl.key, feature = "planets", shape = "Ball", pos = p, size = { x = d, y = d, z = d }, color = pl.color, material = "SmoothPlastic" })
			if pl.ring then
				local rd = 2 * pl.ring
				piece(out, {
					key = pl.key .. "Ring", feature = "planets", shape = "Cylinder", pos = p, size = { x = 0.6, y = rd, z = rd }, face = true, tilt = 72,
					color = pl.ringColor, transparency = 0.35,
				})
			end
		end
	end

	-- the other sky: a second moon, a vast pale ring, and stars that have started to turn
	local O = sky.OtherSky
	if O then
		local m2 = O.Moon2
		local c = NightSky.skyPoint(eye, m2.Azimuth, m2.Elevation, m2.Distance)
		local d = 2 * m2.Radius
		piece(out, { key = "Moon2", feature = "othersky", shape = "Ball", pos = c, size = { x = d, y = d, z = d }, color = m2.Color })
		local Rg = O.Ring
		local centre = NightSky.skyPoint(eye, Rg.Azimuth, Rg.Elevation, Rg.Distance)
		local basis = NightSky.faceBasis(eye, centre)
		for i = 1, Rg.Segments do
			local a = 2 * math.pi * (i - 1) / Rg.Segments
			local p = {
				x = centre.x + Rg.Radius * (math.cos(a) * basis.right.x + math.sin(a) * basis.up.x),
				y = centre.y + Rg.Radius * (math.cos(a) * basis.right.y + math.sin(a) * basis.up.y),
				z = centre.z + Rg.Radius * (math.cos(a) * basis.right.z + math.sin(a) * basis.up.z),
			}
			piece(out, {
				key = "RingArc" .. i, feature = "othersky", shape = "Block", pos = p,
				size = { x = Rg.SegmentSize[1], y = Rg.SegmentSize[2], z = Rg.SegmentSize[3] },
				face = true, roll = math.deg(a) + 90,
				color = Rg.Color, transparency = Rg.Transparency,
			})
		end
		local Sp = O.Spiral
		local sc = NightSky.skyPoint(eye, Sp.Azimuth, Sp.Elevation, Sp.Distance)
		for i = 1, Sp.Count do
			local pos = NightSky.spiralPoint(Sp, eye, sc, i, 0)
			local sd = 2 * Sp.StarRadius
			piece(out, { key = "Turning" .. i, feature = "othersky", shape = "Ball", pos = pos, size = { x = sd, y = sd, z = sd }, color = Sp.Color, live = true, role = "spiral" })
		end
	end

	return out
end

-- Orthonormal right/up for a plane facing `eye` from `centre` (up leans to world +Y).
function NightSky.faceBasis(eye: Vec, centre: Vec): any
	local fx, fy, fz = eye.x - centre.x, eye.y - centre.y, eye.z - centre.z
	local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / fl, fy / fl, fz / fl
	-- right = up(world) x forward
	local rx, ry, rz = fz, 0, -fx
	local rl = math.sqrt(rx * rx + rz * rz)
	if rl < 1e-9 then rx, rz, rl = 1, 0, 1 end
	rx, rz = rx / rl, rz / rl
	-- up = forward x right
	local ux = fy * rz - fz * ry
	local uy = fz * rx - fx * rz
	local uz = fx * ry - fy * rx
	return { right = { x = rx, y = ry, z = rz }, up = { x = ux, y = uy, z = uz }, forward = { x = fx, y = fy, z = fz } }
end

-- Star i of the turning spiral at clock t: a two-armed logarithmic-ish spiral facing the eye,
-- rotating once every PeriodSeconds.
function NightSky.spiralPoint(Sp: any, eye: Vec, centre: Vec, i: number, t: number): Vec
	local basis = NightSky.faceBasis(eye, centre)
	local arm = (i - 1) % 2
	local k = math.floor((i - 1) / 2) / math.max(1, math.floor(Sp.Count / 2) - 1)
	local rr = Sp.Radius * (0.12 + 0.88 * k)
	local a = k * Sp.Turns * 2 * math.pi + arm * math.pi + 2 * math.pi * t / Sp.PeriodSeconds
	return {
		x = centre.x + rr * (math.cos(a) * basis.right.x + math.sin(a) * basis.up.x),
		y = centre.y + rr * (math.cos(a) * basis.right.y + math.sin(a) * basis.up.y),
		z = centre.z + rr * (math.cos(a) * basis.right.z + math.sin(a) * basis.up.z),
	}
end

-- Axis-aligned boxes around everything that MOVES or is drawn beyond a part's own box: the meteor
-- window, the bolt sector, the aurora curtains with their sway, the comet tail, the falling rain,
-- the turning stars and the twinkling star field. `validate` requires each to clear the entrance.
function NightSky.envelopes(sky: any, origin: Vec): { any }
	local out = {}
	local eye = NightSky.eye(sky.Hall, origin)
	local function boxOf(points: { Vec }, pad: number): any
		local mn = { x = math.huge, y = math.huge, z = math.huge }
		local mx = { x = -math.huge, y = -math.huge, z = -math.huge }
		for _, p in points do
			mn.x, mn.y, mn.z = math.min(mn.x, p.x), math.min(mn.y, p.y), math.min(mn.z, p.z)
			mx.x, mx.y, mx.z = math.max(mx.x, p.x), math.max(mx.y, p.y), math.max(mx.z, p.z)
		end
		return { min = { x = mn.x - pad, y = mn.y - pad, z = mn.z - pad }, max = { x = mx.x + pad, y = mx.y + pad, z = mx.z + pad } }
	end
	local function windowPoints(az: { number }, el: { number }, dist: number): { Vec }
		local pts = {}
		for i = 0, 4 do
			for j = 0, 4 do
				table.insert(pts, NightSky.skyPoint(eye, lerp(az[1], az[2], i / 4), lerp(el[1], el[2], j / 4), dist))
			end
		end
		return pts
	end
	local function add(key: string, box: any)
		box.key = key
		table.insert(out, box)
	end

	local Me = sky.Meteors
	if Me then
		add("Meteors", boxOf(windowPoints(Me.AzRange, Me.ElRange, Me.Distance), Me.Size[3] + Me.Distance * 0.02))
	end
	local Li = sky.Lightning
	if Li then
		add("Lightning", boxOf(windowPoints(Li.AzRange, Li.ElRange, Li.Distance), 30))
	end
	local A = sky.Aurora
	if A then
		add("Aurora", boxOf(windowPoints(A.AzRange, A.ElRange, A.Distance), A.Width[2] / 2 + A.SwayStuds))
	end
	local C = sky.Comet
	if C then
		local head = NightSky.skyPoint(eye, C.Azimuth, C.Elevation, C.Distance)
		local tip = NightSky.skyPoint(head, C.TailAzimuth, C.TailElevation, C.TailLength)
		add("CometTail", boxOf({ head, tip }, C.TailWidth[2] / 2))
	end
	local R = sky.Rain
	if R then
		local drift = R.Speed * R.Lifetime * math.sin(math.rad(R.SpreadDegrees))
		local fall = R.Speed * R.Lifetime
		local c = { x = origin.x + R.Offset[1], y = origin.y + R.Offset[2], z = origin.z + R.Offset[3] }
		add("Rain", {
			min = { x = c.x - R.Size[1] / 2 - drift, y = c.y - R.Size[2] / 2 - fall, z = c.z - R.Size[3] / 2 - drift },
			max = { x = c.x + R.Size[1] / 2 + drift, y = c.y + R.Size[2] / 2, z = c.z + R.Size[3] / 2 + drift },
		})
	end
	local O = sky.OtherSky
	if O then
		local Sp = O.Spiral
		local sc = NightSky.skyPoint(eye, Sp.Azimuth, Sp.Elevation, Sp.Distance)
		add("Spiral", boxOf({ sc }, Sp.Radius + Sp.StarRadius))
	end
	local S = sky.Stars
	if S then
		-- the particles are born inside the (eye-facing) star slab and never move: its exact corners
		local slab = {
			pos = NightSky.skyPoint(eye, S.Azimuth, S.Elevation, S.Distance),
			size = { x = S.Size[1], y = S.Size[2], z = S.Size[3] }, face = true, shape = "Block",
		}
		add("Stars", boxOf(NightSky.pieceCorners(slab, eye), S.ParticleSize))
	end
	return out
end

-- ------------------------------------------------------------------ validate

local function checkColour(sky: any, key: any, where: string): string?
	if type(key) ~= "string" or sky.Palette == nil or sky.Palette[key] == nil then
		return where .. " names colour '" .. tostring(key) .. "', which the palette does not have"
	end
	return nil
end

function NightSky.validate(sky: any, EnvBands: any, Rest: any): (boolean, string?)
	if type(sky) ~= "table" then return false, "no sky config" end
	local hall = sky.Hall
	if type(hall) ~= "table" or type(hall.Front) ~= "number" then return false, "no Hall geometry" end
	if type(sky.Clearance) ~= "number" or sky.Clearance < 0 then return false, "Clearance must be >= 0" end
	if type(sky.GlideHalfLife) ~= "number" or sky.GlideHalfLife <= 0 then
		return false, "GlideHalfLife must be > 0: a glide of 0 is a hard cut"
	end

	-- bands
	local bands = sky.Bands
	local okB, errB = EnvBands.validate(bands)
	if not okB then return false, "Bands: " .. tostring(errB) end
	for i, b in bands do
		if b.from ~= math.floor(b.from) then
			return false, "band " .. tostring(b.id) .. " must start on a whole Day"
		end
		if i > 1 and (b.fade or 0) < 1 then
			return false, "band " .. tostring(b.id) .. " must fade in over at least a Day (fade 0 is a hard cut)"
		end
		if type(b.name) ~= "string" or b.name == "" or type(b.emoji) ~= "string" or b.emoji == "" then
			return false, "band " .. tostring(b.id) .. " needs a name and an emoji"
		end
		if type(b.features) ~= "table" then return false, "band " .. tostring(b.id) .. " has no features" end
		for _, k in NightSky.FEATURES do
			local v = b.features[k]
			if type(v) ~= "number" or isNaN(v) or v < 0 or v > 1 then
				return false, "band " .. tostring(b.id) .. " feature '" .. k .. "' must be a number in [0, 1]"
			end
		end
	end

	-- palette
	if type(sky.Palette) ~= "table" then return false, "no Palette" end
	for name, c in sky.Palette do
		if type(c) ~= "table" or #c ~= 3 then return false, "palette colour " .. tostring(name) .. " is not {r, g, b}" end
		for _, v in c do
			if type(v) ~= "number" or v < 0 or v > 255 then
				return false, "palette colour " .. tostring(name) .. " has a channel outside 0..255"
			end
		end
		if NightSky.isReddish(c) then
			return false, "palette colour " .. tostring(name) .. " is reddish; red is how two anomalies read"
		end
	end
	if sky.Moon then
		local e = checkColour(sky, sky.Moon.Color, "Moon.Color") or checkColour(sky, sky.Moon.ShadowColor, "Moon.ShadowColor")
		if e then return false, e end
		if type(sky.Moon.MaxTurnPerSecond) ~= "number" or sky.Moon.MaxTurnPerSecond <= 0 then
			return false, "Moon.MaxTurnPerSecond must be > 0: an uncapped phase glide races through new moon on a reset"
		end
	end

	-- geometry: everything beyond the entrance, for a hall at the origin
	local origin = NightSky.hallOrigin(hall, 1)
	local eye = NightSky.eye(hall, origin)
	for _, p in NightSky.layout(sky, origin) do
		local e = checkColour(sky, p.color, "piece " .. p.key)
		if e then return false, e end
		if NightSky.pieceMinZ(p, eye) - origin.z <= hall.Front + sky.Clearance then
			return false, "piece " .. p.key .. " reaches back to the hall's entrance plane"
		end
		local okE, whyE = NightSky.engineSizeOk(p)
		if not okE then
			return false, "piece " .. p.key .. ": " .. tostring(whyE)
		end
	end
	for _, e in NightSky.envelopes(sky, origin) do
		if e.min.z - origin.z <= hall.Front + sky.Clearance then
			return false, "moving thing " .. e.key .. " can reach back to the hall's entrance plane"
		end
	end

	-- rest
	local okR, errR = Rest.validate(sky.Rest)
	if not okR then return false, "Rest: " .. tostring(errR) end
	if sky.Rest.IdleSeconds ~= 0 then
		return false, "Rest.IdleSeconds must be 0: nothing here needs pausing, and an idle timer would only take the camera away from a player who stopped to look"
	end
	if type(sky.DeathBeatSeconds) ~= "number" or sky.Rest.PendingSeconds <= sky.DeathBeatSeconds then
		return false, "Rest.PendingSeconds must outlive DeathBeatSeconds, or a break asked for during the death beat is lost"
	end
	if type(sky.IdleKickMinutes) ~= "number" or isNaN(sky.IdleKickMinutes) or sky.IdleKickMinutes < 1 then
		return false, "IdleKickMinutes (Roblox's idle disconnect) must be set: the break caption has to state what idling costs"
	end

	-- the telescope break looks away from every hall
	local view = sky.RestView
	if type(view) ~= "table" then return false, "no RestView" end
	if view.Offset[3] <= hall.Front + sky.Clearance then
		return false, "RestView.Offset puts the break camera inside the entrance plane"
	end
	-- The drift never exceeds these four corners, so checking them bounds every pose.
	for _, yaw in { -view.YawSwayDegrees, view.YawSwayDegrees } do
		for _, pitch in { view.PitchDegrees - view.PitchSwayDegrees, view.PitchDegrees + view.PitchSwayDegrees } do
			if NightSky.minRayZ(NightSky.lookFrom(yaw, pitch), view.FovDegrees, view.MaxAspect) <= 0.05 then
				return false, "the break camera can draw rays back toward the hall (yaw/pitch too wide for its field of view)"
			end
		end
	end

	-- budget
	local B = sky.Budget
	if type(B) ~= "table" then return false, "no Budget" end
	for _, k in { "MaxParts", "MaxEmitters", "MaxEmitterRate", "MaxBeams", "MaxTrails", "MaxLights" } do
		if type(B[k]) ~= "number" then return false, "Budget." .. k .. " missing" end
	end
	if B.MaxLights ~= 0 then
		return false, "Budget.MaxLights must be 0: a sky that casts light changes how the hall is lit"
	end
	return true, nil
end

return NightSky
