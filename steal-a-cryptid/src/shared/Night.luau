--!strict
-- Night.luau - the RULES behind Steal a Cryptid's eye candy (EYECANDY.md). Pure: no Roblox, requires
-- nothing (cfg and any module it needs come in as arguments). tests/Night.spec.luau pins every rule.
--
--   * The readability floor. No band may be darker or foggier than the game as it shipped
--     (Config.Lighting, DESIGN.md section 13): a raider reads a whole camp from its gate, tier colours
--     must survive, neon nets must bloom, nothing may blur the far side of a camp. `readable` judges a
--     band and any frame the client writes, and every blend of two readable bands is readable too
--     (each rule is a bound on a quantity that blends linearly).
--   * Night hours. Bands write ClockTime as hours since noon the day before (18 = 6 pm, 27 = 3 am),
--     inside 17.5..30, so a glide between two bands never passes daylight. `clockTime` wraps it.
--   * Progress. The home sky follows the Journal's rank (Economy.rank, the highest tier ever owned;
--     the server reports it in State.rank). Never a timer, never backwards within a session.
--   * Where. A root in a pocket slice (x past the pocket origin) is in a camp; camp scenery keeps out
--     of the yard and out of the camera's corridor behind the gate, so it can never hide a net.
--   * The hazard gate. Hazards run only at home, after the tutorial, with no poacher about, no Hunt
--     panel or build mode open, away from the ground's edge, and only after a settle time.
--   * The world's edge (review 2026-09-24). The far forest floor frames a ravine round the Ground, never
--     a false floor at walking height beside it (farGroundRects); a hazard's knock is cut so it cannot
--     carry anyone off the Ground (limitKnock).
--   * The camera's view (review 2026-09-24). Scenery or a critter whose footprint enters the hull of the
--     camera and the camp (campViewHull), or at home of the camera and the player, could stand between
--     them: NightArt hides it. Critters are kept out by what they draw (critterClear), a box, not a circle.
--   * Habitats. Your own occupied cages get a patch per species; only the rarest few get particles.

local Night = {}

Night.MIN_CLOCK = 17.5
Night.MAX_CLOCK = 30

Night.GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }

-- The fields every band defines, so a blend never snaps a property that only one side has.
Night.KEYS = ({
	lighting = { "ClockTime", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd",
		"FogColor", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" },
	atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	sky = { "StarCount", "MoonAngularSize", "SunAngularSize" },
	bloom = { "Intensity", "Size", "Threshold" },
	colorCorrection = { "Brightness", "Contrast", "Saturation", "TintColor" },
	sunRays = { "Intensity", "Spread" },
} :: { [string]: { string } })

-- Rec. 709 relative luminance of an {r, g, b} colour (0..255 per channel).
function Night.luminance(c: { number }): number
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

function Night.clockTime(nightHour: number): number
	return nightHour % 24
end

local function copy(v: any): any
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = copy(x) end
	return out
end

-- The game as it shipped, as band-shaped groups: the client's take-over start point and the floor.
-- v1 sets no Sky and no sun rays: Roblox's default sky (3 000 stars, moon 11, sun 21) and none.
function Night.baseGroups(cfg: any): any
	local L = cfg.Lighting
	local lighting = copy(L.lighting)
	lighting.Technology = nil
	lighting.ClockTime = (L.lighting.ClockTime < 12) and (L.lighting.ClockTime + 24) or L.lighting.ClockTime
	return {
		id = "v1",
		lighting = lighting,
		atmosphere = copy(L.atmosphere),
		sky = { StarCount = 3000, MoonAngularSize = 11, SunAngularSize = 21 },
		bloom = copy(L.bloom),
		colorCorrection = copy(L.colorCorrection),
		sunRays = { Intensity = 0, Spread = 0 },
	}
end

-- (ok, why). A frame is readable when it is at least as light, clear and saturated as v1.
function Night.readable(cfg: any, g: any): (boolean, string?)
	local L = cfg.Lighting
	local eps = 1e-6
	local function atLeast(v: any, floor: number, name: string): string?
		if type(v) ~= "number" or v < floor - eps then
			return string.format("%s %s is below v1's %s", name, tostring(v), tostring(floor))
		end
		return nil
	end
	local function atMost(v: any, ceil: number, name: string): string?
		if type(v) ~= "number" or v > ceil + eps then
			return string.format("%s %s is above v1's %s", name, tostring(v), tostring(ceil))
		end
		return nil
	end
	local l, a, b, cc = g.lighting or {}, g.atmosphere or {}, g.bloom or {}, g.colorCorrection or {}
	local why = atLeast(l.Brightness, L.lighting.Brightness, "Brightness")
		or atLeast(l.ExposureCompensation, L.lighting.ExposureCompensation, "ExposureCompensation")
		or atLeast(l.FogStart, L.lighting.FogStart, "FogStart")
		or atLeast(l.FogEnd, L.lighting.FogEnd, "FogEnd")
		or atMost(a.Density, L.atmosphere.Density, "atmosphere Density")
		or atMost(a.Haze, L.atmosphere.Haze, "atmosphere Haze")
		or atMost(b.Threshold, L.bloom.Threshold, "bloom Threshold")
		or atLeast(cc.Saturation, L.colorCorrection.Saturation, "colorCorrection Saturation")
		or atLeast(cc.Brightness, L.colorCorrection.Brightness, "colorCorrection.Brightness")
	if why then return false, why end
	for _, k in { "Ambient", "OutdoorAmbient" } do
		local c = l[k]
		if type(c) ~= "table" or Night.luminance(c) < Night.luminance(L.lighting[k]) - eps then
			return false, k .. " is darker than v1's"
		end
	end
	return true, nil
end

local function ascii(s: any): boolean
	return type(s) == "string" and #s > 0 and string.find(s, "[\128-\255]") == nil
end

-- (ok, why) for one band: every field present, night hours, readable, no depth of field, ASCII text.
function Night.checkBand(cfg: any, b: any): (boolean, string?)
	local label = tostring(b and b.id)
	if type(b) ~= "table" then return false, "a band is not a table" end
	if b.depthOfField ~= nil then
		return false, label .. ": no depth of field in a band (it blurs the far side of a camp)"
	end
	for g, keys in Night.KEYS do
		local grp = b[g]
		if type(grp) ~= "table" then return false, label .. ": missing " .. g end
		for _, k in keys do
			if grp[k] == nil then return false, label .. ": missing " .. g .. "." .. k end
		end
	end
	local h = b.lighting.ClockTime
	if type(h) ~= "number" or h < Night.MIN_CLOCK or h > Night.MAX_CLOCK then
		return false, label .. ": ClockTime " .. tostring(h) .. " is not a night hour (17.5..30)"
	end
	local ok, why = Night.readable(cfg, b)
	if not ok then return false, label .. ": " .. tostring(why) end
	if not ascii(b.name) then return false, label .. ": name must be non-empty ASCII (no emoji)" end
	if not ascii(b.sub) then return false, label .. ": sub must be non-empty ASCII (no emoji)" end
	return true, nil
end

-- (ok, why) for Config.Night: both band lists (EnvBands rules + checkBand).
function Night.validate(cfg: any, EnvBands: any): (boolean, string?)
	local N = cfg.Night
	if type(N) ~= "table" then return false, "no Config.Night" end
	for _, name in { "Home", "Camp" } do
		local list = N[name]
		local ok, why = EnvBands.validate(list)
		if not ok then return false, "Night." .. name .. ": " .. tostring(why) end
		for _, b in list do
			local ok2, why2 = Night.checkBand(cfg, b)
			if not ok2 then return false, "Night." .. name .. ": " .. tostring(why2) end
		end
	end
	return true, nil
end

--============================================================================ progress

-- The Journal's rank the server reported (State.rank), clamped, floored, never below `prev`.
function Night.rank(cfg: any, state: any, prev: number?): number
	local keep = prev or 0
	if type(state) ~= "table" then return keep end
	local r = tonumber(state.rank)
	if r == nil or r ~= r then return keep end
	r = math.clamp(math.floor(r), 0, #cfg.Tiers)
	return math.max(r, keep)
end

--============================================================================ where

-- Pocket s owns the slice [origin(s) - pitch/2, origin(s) + pitch/2). Home is everything before slot 0.
function Night.pocketSlot(cfg: any, x: number): number?
	if type(x) ~= "number" or x ~= x then return nil end
	local W = cfg.World
	local rel = x - (W.PocketOriginX - W.PocketPitch / 2)
	if rel < 0 then return nil end
	return math.floor(rel / W.PocketPitch)
end

function Night.pocketOriginX(cfg: any, slot: number): number
	return cfg.World.PocketOriginX + cfg.World.PocketPitch * slot
end

-- ("home") or ("camp", tier, slot). WHERE comes from the root's position (a State can arrive before the
-- teleport does); the camp's TIER from the raid the server reported, else the raidStart event's.
function Night.scene(cfg: any, x: number, state: any, lastTier: number?): (string, number?, number?)
	local slot = Night.pocketSlot(cfg, x)
	if slot == nil then return "home", nil, nil end
	local tier = nil
	if type(state) == "table" and type(state.raid) == "table" then tier = tonumber(state.raid.tier) end
	tier = tier or lastTier or 1
	tier = math.clamp(math.floor(tier :: number), 1, #cfg.Camps)
	return "camp", tier, slot
end

-- Pocket-local rects (x0, x1, z0, z1) no camp scenery or critter may enter: the camp itself (fences,
-- sign and cage row) grown by CampMargin, and the corridor behind the gate where the camera sits.
function Night.keepOut(cfg: any): { any }
	local W = cfg.World
	local m = cfg.Night.CampMargin
	local zBack = W.ApronDepth + W.CellSize * (W.CageRow + 1) + 1
	local gx = W.CellSize * (W.GateCol - 0.5)
	local half = cfg.Night.CameraCorridorHalfWidth
	return {
		{ x0 = -1 - m, x1 = W.PlotWidth + 1 + m, z0 = W.ApronDepth - 1 - m, z1 = zBack + m },
		{ x0 = gx - half, x1 = gx + half, z0 = -cfg.Night.CameraCorridorDepth, z1 = W.ApronDepth },
	}
end

-- Is a ball of `radius` at pocket-local (x, z) clear of every keep-out rect?
function Night.clearOfCamp(cfg: any, x: number, z: number, radius: number): boolean
	for _, r in Night.keepOut(cfg) do
		local dx = math.max(r.x0 - x, 0, x - r.x1)
		local dz = math.max(r.z0 - z, 0, z - r.z1)
		if dx * dx + dz * dz <= radius * radius then return false end
	end
	return true
end

-- Is the pocket-local box x0..x1, z0..z1 (a part's world-aligned footprint) clear of every keep-out rect?
function Night.boxClearOfCamp(cfg: any, x0: number, x1: number, z0: number, z1: number): boolean
	for _, r in Night.keepOut(cfg) do
		if x0 < r.x1 and r.x0 < x1 and z0 < r.z1 and r.z0 < z1 then return false end
	end
	return true
end

-- Is a critter centred at pocket-local (x, z) clear of every keep-out rect? A critter is DRAWN with wings, a
-- bob and a halo reaching up to `reach` studs from its centre along each world axis, so the test is a box: a
-- circle of the same radius lets that box in diagonally at a rect's corner (a wisp's halo was once caught 0.2
-- studs into the corridor's corner by check_stealacryptid_night).
function Night.critterClear(cfg: any, x: number, z: number, reach: number): boolean
	return Night.boxClearOfCamp(cfg, x - reach, x + reach, z - reach, z + reach)
end

-- Studs from (x, z) to the nearest edge of the ground rect { cx, cz, sx, sz }; negative outside it.
function Night.edgeDistance(rect: any, x: number, z: number): number
	if rect == nil then return math.huge end
	local dx = rect.sx / 2 - math.abs(x - rect.cx)
	local dz = rect.sz / 2 - math.abs(z - rect.cz)
	return math.min(dx, dz)
end

--============================================================================ the world's edge

-- The far forest floor, as rects { cx, cz, sx, sz }. The server's Ground is the only floor at home and
-- past its edge is the void, so the local far floor must never continue it at walking height: a floor
-- 1.1 studs below the Ground's top made the edge invisible and dropped players through the world (review
-- 2026-09-24, finding 1). It is a FRAME round a hole, the Ground grown by R.Width (a ravine no one can
-- jump across; NightArt hangs cliff faces on both sides of it), reaching R.FarHalf from the road's centre,
-- or R.MinFar past the ravine on a road longer than that. No road known yet: one slab round the origin.
function Night.farGroundRects(rect: any, R: any): { any }
	if rect == nil then
		return { { cx = 0, cz = 0, sx = 2 * R.FarHalf, sz = 2 * R.FarHalf } }
	end
	local hx, hz = rect.sx / 2 + R.Width, rect.sz / 2 + R.Width
	local ox = math.max(R.FarHalf, hx + R.MinFar)
	local oz = math.max(R.FarHalf, hz + R.MinFar)
	local cx, cz = rect.cx, rect.cz
	return {
		-- the -z and +z bands run the full outer width; the -x and +x bands fill between them
		{ cx = cx, cz = cz - (hz + oz) / 2, sx = 2 * ox, sz = oz - hz },
		{ cx = cx, cz = cz + (hz + oz) / 2, sx = 2 * ox, sz = oz - hz },
		{ cx = cx - (hx + ox) / 2, cz = cz, sx = ox - hx, sz = 2 * hz },
		{ cx = cx + (hx + ox) / 2, cz = cz, sx = ox - hx, sz = 2 * hz },
	}
end

-- The push a hazard's hit gives, cut so that it cannot carry anyone off the world. Its frictionless slide
-- (velocity x seconds: the same upper bound the launch margin EdgeMarginStuds is sized by) must end at
-- least `keepIn` studs inside the ground rect. The Ground is an axis-aligned rect, so each axis is cut on
-- its own; a slide that starts and ends inside the inner rect never leaves it. Only the OUTWARD part is
-- cut, and never past zero (a push is never turned around); along the edge, inward and the lift are left
-- alone; far from the edge nothing changes. (Review 2026-09-24, finding 2: the margin only gated
-- launches, so a player who walked toward the edge while a hazard flew was knocked on toward it.)
function Night.limitKnock(rect: any, pos: any, kv: any, seconds: number, keepIn: number): any
	if rect == nil or not (seconds > 0) then
		return { x = kv.x, y = kv.y, z = kv.z }
	end
	local function axis(v: number, p: number, c: number, half: number): number
		if v > 0 then
			return math.min(v, math.max(0, (c + half - keepIn - p) / seconds))
		elseif v < 0 then
			return math.max(v, math.min(0, (c - half + keepIn - p) / seconds))
		end
		return v
	end
	return { x = axis(kv.x, pos.x, rect.cx, rect.sx / 2), y = kv.y, z = axis(kv.z, pos.z, rect.cz, rect.sz / 2) }
end

--============================================================================ the camera's view of a camp

-- The 2-D convex hull (counter-clockwise in x/z, as { x, z } points) of a point and an axis-aligned rect.
function Night.viewHull(px: number, pz: number, x0: number, x1: number, z0: number, z1: number): { any }
	local pts = { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 }, { px, pz } }
	table.sort(pts, function(a: any, b: any): boolean
		return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
	end)
	local function cross(o: any, a: any, b: any): number
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	-- Andrew's monotone chain
	local lower, upper = {}, {}
	for _, p in pts do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do table.remove(lower) end
		table.insert(lower, p)
	end
	for i = #pts, 1, -1 do
		local p = pts[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do table.remove(upper) end
		table.insert(upper, p)
	end
	table.remove(lower)
	table.remove(upper)
	local hull = {}
	for _, p in lower do table.insert(hull, { x = p[1], z = p[2] }) end
	for _, p in upper do table.insert(hull, { x = p[1], z = p[2] }) end
	return hull
end

-- Does the axis-aligned box x0..x1, z0..z1 overlap the convex polygon `hull` (touching counts)? Separating axes.
function Night.boxOverlapsHull(hull: { any }, x0: number, x1: number, z0: number, z1: number): boolean
	local hx0, hx1, hz0, hz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in hull do
		hx0, hx1 = math.min(hx0, p.x), math.max(hx1, p.x)
		hz0, hz1 = math.min(hz0, p.z), math.max(hz1, p.z)
	end
	if hx1 < x0 or x1 < hx0 or hz1 < z0 or z1 < hz0 then return false end
	local n = #hull
	for i = 1, n do
		local a, b = hull[i], hull[i % n + 1]
		local nx, nz = b.z - a.z, a.x - b.x
		local lo, hi = math.huge, -math.huge
		for _, p in hull do
			local d = p.x * nx + p.z * nz
			lo, hi = math.min(lo, d), math.max(hi, d)
		end
		local b0, b1 = math.huge, -math.huge
		for _, c in { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } } do
			local d = c[1] * nx + c[2] * nz
			b0, b1 = math.min(b0, d), math.max(b1, d)
		end
		if b1 < lo or hi < b0 then return false end
	end
	return true
end

-- The hull a camera at pocket-local (camX, camZ) sees the camp through: every line of sight from the camera to
-- any point of the camp (Night.keepOut's first rect: fences, sign and cage row grown by CampMargin), at any
-- height, projects inside it. So a part whose footprint misses it can hide nothing of the camp; one that
-- overlaps it might, and NightArt hides it while it does (review 2026-09-24, finding 3: a pine crown or a
-- redwood hid the raider from a zoomed-out camera outside the corridor behind the gate).
function Night.campViewHull(cfg: any, camX: number, camZ: number): { any }
	local r = Night.keepOut(cfg)[1]
	return Night.viewHull(camX, camZ, r.x0, r.x1, r.z0, r.z1)
end

-- Would a part whose world-aligned footprint is the pocket-local box x0..x1, z0..z1 stand between a camera
-- at pocket-local (camX, camZ) and the camp? (Conservative: it may say yes for a part the view passes over.)
function Night.hidesCamp(cfg: any, camX: number, camZ: number, x0: number, x1: number, z0: number, z1: number): boolean
	return Night.boxOverlapsHull(Night.campViewHull(cfg, camX, camZ), x0, x1, z0, z1)
end

--============================================================================ the hazard gate

-- Reasons in order of precedence, and which of them remove a hazard already in flight: leaving home
-- (a raid's teleport, a respawn) and a poacher (the owner must be free to defend) do; the player's own
-- choices (a panel, build mode) and the edge only stop new launches.
local CANCELS = { loading = true, camp = true, poacher = true }

function Night.cancelsFlight(reason: string?): boolean
	return reason ~= nil and CANCELS[reason] == true
end

function Night.newGate(): any
	return { openFor = 0 }
end

-- One frame: (run, reason). ctx = { loaded, scene, tutorial, poacher, buildMode, panelOpen, edge }.
-- A gate that reopens settles for Hazards.SettleSeconds before hazards run again.
function Night.stepGate(g: any, cfg: any, dt: number, ctx: any): (boolean, string)
	local H = cfg.Night.Hazards
	local why: string? = nil
	if not ctx.loaded then
		why = "loading"
	elseif ctx.scene ~= "home" then
		why = "camp"
	elseif (tonumber(ctx.tutorial) or 0) < H.AfterTutorial then
		why = "tutorial"
	elseif ctx.poacher then
		why = "poacher"
	elseif ctx.buildMode then
		why = "build"
	elseif ctx.panelOpen then
		why = "panel"
	elseif (ctx.edge or math.huge) < H.EdgeMarginStuds then
		why = "edge"
	end
	if why then
		g.openFor = 0
		return false, why :: string
	end
	g.openFor += dt
	if g.openFor < H.SettleSeconds - 1e-9 then
		return false, "settling"
	end
	return true, "open"
end

-- (mayLaunch, pitchForHazards). The template (Hazards) starts a lane within +-ViewPitchDegrees of the
-- camera's pitch, which in +1 Jump's open sky is always on screen. Here the camera looks DOWN at a player
-- on the ground, and a window centred below the horizon starts lanes inside the ground. So the window's
-- centre is raised to at least -ViewPitchDegrees (its top is the horizon or higher) and, while the camera
-- looks down more steeply than MaxLookDownDegrees (where a level lane would start above the screen), a
-- launch waits (the caller reports "not grounded": the hazard stays due, nothing is reset).
function Night.hazardPitch(cfg: any, camPitch: number): (boolean, number)
	local H = cfg.Night.Hazards
	local p = if camPitch ~= camPitch then 0 else camPitch
	if p < -math.rad(H.MaxLookDownDegrees) then
		return false, p
	end
	return true, math.max(p, -math.rad(H.ViewPitchDegrees))
end

--============================================================================ where a hazard is drawn

-- Where to DRAW hazard `plan` at flight time t: (pos, visible). Visual only: the hit rule stays the lane's
-- (Hazards.checkHit, inside the ring), so nothing drawn here can hit or spare anyone.
--   * until it arrives: exactly on the lane its warning showed;
--   * after it arrives: a flier keeps its heading and swoops UP at SwoopDegrees instead of flying on into
--     the ground (the template's lanes were for open sky); an `impact` kind (the meteorite) ends there:
--     it strikes the ring its warning drew, and is hidden from then on;
--   * avoid = the root of a player who has LEFT the ring: the drawn point rises over a smooth bump,
--     ClearStuds high over that root and zero 2 x ClearStuds away, so the model passes over a dodger
--     instead of through them. The bump never lowers a point. (+1 Jump's open question 22, closed here.)
--     (No drawn point is below the root's height: lanes come down TO it and then end or climb. Should one
--     ever be, it is lifted less the lower it is, reaching zero ClearStuds down, so the path never jumps.)
function Night.drawPosition(cfg: any, plan: any, t: number, avoid: any?): (any, boolean)
	local H = cfg.Night.Hazards
	local k = H.Kinds[plan.kind] or {}
	local st, vel = plan.start, plan.velocity
	local x, y, z = st.x + vel.x * t, st.y + vel.y * t, st.z + vel.z * t
	local visible = true
	if t > plan.arriveAt then
		if k.impact then
			visible = false
		else
			local arriveY = st.y + vel.y * plan.arriveAt
			local vh = math.sqrt(vel.x * vel.x + vel.z * vel.z)
			y = arriveY + (t - plan.arriveAt) * vh * math.tan(math.rad(H.SwoopDegrees))
		end
	end
	if avoid ~= nil and visible then
		local c = H.ClearStuds
		local r = 2 * c
		local dx, dz = x - avoid.x, z - avoid.z
		local dh2 = dx * dx + dz * dz
		if dh2 < r * r then
			local u = 1 - dh2 / (r * r)
			if y >= avoid.y then
				y = math.max(y, avoid.y + c * u * u)
			else
				y += c * u * u * math.max(0, 1 - (avoid.y - y) / c)
			end
		end
	end
	return { x = x, y = y, z = z }, visible
end

--============================================================================ habitats

-- { [col] = { sp, kind, tier, glow, lit } } for every unlocked cage holding a species this game has.
-- `lit` (particles on) goes to the `maxLit` rarest, ties broken by Config.World.CageOrder (centre first).
function Night.habitats(cfg: any, cages: any, maxLit: number): { [number]: any }
	local out = {}
	if type(cages) ~= "table" then return out end
	local H = cfg.Night.Habitats
	local list = {}
	for col = 1, 9 do
		local c = cages[col]
		if type(c) == "table" and c.unlocked ~= false and type(c.sp) == "string" and c.sp ~= "" then
			local kind = H.Species[c.sp]
			local tier = tonumber(c.tier)
			if kind and tier and tier >= 1 and tier <= #cfg.Tiers then
				out[col] = { sp = c.sp, kind = kind, tier = tier, glow = H.GlowTransparency[tier], lit = false }
				table.insert(list, col)
			end
		end
	end
	local order = {}
	for i, col in cfg.World.CageOrder do order[col] = i end
	table.sort(list, function(a: number, b: number): boolean
		if out[a].tier ~= out[b].tier then return out[a].tier > out[b].tier end
		return (order[a] or a) < (order[b] or b)
	end)
	for i = 1, math.min(#list, math.max(0, math.floor(maxLit))) do
		out[list[i]].lit = true
	end
	return out
end

--============================================================================ text

local SIDES = { left = "the left", right = "the right", ahead = "ahead", behind = "behind" }

function Night.sideText(bearing: string): string
	return SIDES[bearing] or "ahead"
end

-- The HUD chip while a hazard flies: where it comes from, then (locked) what to do.
function Night.alertText(cfg: any, kind: string, bearing: string, locked: boolean): string
	local T = cfg.Night.Text
	local k = cfg.Night.Hazards.Kinds[kind]
	local label = if k then k.label else kind
	if locked then
		return string.format(T.Locked, string.lower(label))
	end
	return string.format(T.Incoming, label, Night.sideText(bearing))
end

-- "manual" | "idle" | "queued" | nil
function Night.restText(cfg: any, which: string?): string
	local T = cfg.Night.Text
	if which == "manual" then return T.Resting end
	if which == "idle" then return T.Idle end
	if which == "queued" then return T.Queued end
	return ""
end

-- The HUD's Rest button label (the client writes it to the HUD's NightBus).
function Night.restLabel(cfg: any, resting: boolean, pending: boolean): string
	local T = cfg.Night.Text
	if resting then return T.RestingButton end
	if pending then return T.QueuedButton end
	return T.RestButton
end

return Night
