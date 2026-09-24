-- Grotto.luau — Grow a Crystal's own pure rules for the cavern's eye candy.
--
-- EnvBands, Rest and Visitors are game-agnostic templates. This module is the part that knows THIS
-- game, and like Cavern.luau it is pure: plain tables in, plain tables out, no engine datatype, no
-- service, no require. Dependencies (Rng, Cavern) are ARGUMENTS, because require("./X") resolves in
-- the luau CLI and is invalid in Roblox.
--
--   progress(chambers, max)   the band progress value: whole chambers owned, clamped, never trusted
--                             blindly (it arrives in a remote payload)
--   chipText(bands, chambers) "🍄 Mushroom Terraces · 🌊 Chamber 7"
--   burst(tier, rules)        what a harvest of that refraction tier looks like (a copy)
--   flashDue(last, now, cd)   may a harvest flash the whole screen now (at most once per cooldown)
--   pulse(t, period)          the slow "geode pulse", 0..1, smooth
--   layout(cfg, Rng, Cavern)  WHERE every client-built piece goes, in plot-local coordinates, plus
--                             the particle volumes, the critter zones and the visitors' routes
--   routePoint(route, u)      a point on a visitor's flight route, u in 0..1
--
-- The client (src/client/Grotto.client.luau via CavernArt) adds the plot origin to layout positions
-- and nothing else, exactly as the server does with Cavern.build. tests/Grotto.spec.luau pins the
-- geometry: nothing stands in the socket zone or on the walkway, nothing leaves the shell, water
-- stays in the pool, glow-worms never hang in the light-shaft hole, routes stay above every head.

local Grotto = {}

local function isNaN(x: number): boolean
	return x ~= x
end

local function copy(v: any): any
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = copy(x) end
	return out
end

--============================================================================ progress + text

function Grotto.progress(chambers: any, maxChambers: number): number
	if type(chambers) ~= "number" or isNaN(chambers) then return 1 end
	if chambers >= maxChambers then return maxChambers end
	if chambers < 1 then return 1 end
	return math.floor(chambers)
end

-- Chambers owned, read from the world: chamber c is there once its LAST socket (c * perChamber) is.
-- Counted from 1 without a gap. 0 = none of our sockets have arrived yet. `hasSocket(id)` is the caller's
-- lookup of Socket_<uid>_<id> in its own plot; the server builds every owned chamber's sockets at join and
-- on every purchase, so this needs no remote at all.
function Grotto.chambersFromSockets(hasSocket: (number) -> boolean, perChamber: number, maxChambers: number): number
	local c = 0
	while c < maxChambers and hasSocket((c + 1) * perChamber) do
		c += 1
	end
	return c
end

function Grotto.chipText(bands: { any }, chambers: number): string
	local idx = 1
	for i, b in bands do
		if chambers >= b.from then idx = i end
	end
	local b = bands[idx]
	local text = b.emoji .. " " .. b.name
	local nb = bands[idx + 1]
	if nb then
		return text .. "  ·  " .. nb.emoji .. " Chamber " .. tostring(nb.from)
	end
	return text .. "  ·  every chamber open"
end

--============================================================================ harvest + pulse

function Grotto.burst(tier: any, rules: { any }): any
	local t = 1
	if type(tier) == "number" and not isNaN(tier) then
		t = math.clamp(math.floor(tier), 1, #rules)
	end
	return copy(rules[t])
end

-- May a harvest flash the whole screen (and shake it) now? At most once per `cooldown` seconds. A Legendary
-- seed always refracts to Legendary or Mythic, so a row of them harvested at a click rate flashed on every
-- click and stacked into a wash (review 2026-09-24, finding 3). Only the full-screen part waits: the burst,
-- the beam and the card play for every harvest. `lastAt` nil = no flash yet this session.
function Grotto.flashDue(lastAt: number?, now: number, cooldown: number): boolean
	if type(lastAt) ~= "number" or isNaN(lastAt) then return true end
	if type(cooldown) ~= "number" or isNaN(cooldown) or cooldown <= 0 then return true end
	return now - lastAt >= cooldown
end

function Grotto.pulse(t: number, period: number): number
	if type(t) ~= "number" or isNaN(t) or type(period) ~= "number" or not (period > 0) then return 0 end
	return 0.5 - 0.5 * math.cos(2 * math.pi * t / period)
end

--============================================================================ routes

-- Catmull-Rom through the route's points, uniform per segment, u clamped to 0..1.
function Grotto.routePoint(route: { any }, u: number): any
	local n = #route
	if n == 0 then return { x = 0, y = 0, z = 0 } end
	if n == 1 then return { x = route[1].x, y = route[1].y, z = route[1].z } end
	local uu = if type(u) == "number" and not isNaN(u) then math.clamp(u, 0, 1) else 0
	local f = uu * (n - 1)
	local i = math.min(n - 1, math.floor(f) + 1)
	local s = f - (i - 1)
	local p0 = route[math.max(1, i - 1)]
	local p1 = route[i]
	local p2 = route[i + 1]
	local p3 = route[math.min(n, i + 2)]
	if n == 2 then
		return {
			x = p1.x + (p2.x - p1.x) * s,
			y = p1.y + (p2.y - p1.y) * s,
			z = p1.z + (p2.z - p1.z) * s,
		}
	end
	local s2, s3 = s * s, s * s * s
	local function cr(a: number, b: number, c: number, d: number): number
		return 0.5 * ((2 * b) + (-a + c) * s + (2 * a - 5 * b + 4 * c - d) * s2 + (-a + 3 * b - 3 * c + d) * s3)
	end
	return {
		x = cr(p0.x, p1.x, p2.x, p3.x),
		y = cr(p0.y, p1.y, p2.y, p3.y),
		z = cr(p0.z, p1.z, p2.z, p3.z),
	}
end

--============================================================================ layout

local function v3(x: number, y: number, z: number) return { x = x, y = y, z = z } end

-- One stream per piece, WITHOUT a plot index: every plot's cavern is the same shape, and a rejoining
-- player (on whatever plot index they get) sees their glow-worms where they left them.
local SALT = { glowworm = 41, shroom = 43, prism = 47, seam = 53 }

local function stream(Rng: any, cfg: any, salt: number): any
	return Rng.new(cfg.WorldSeed * 7919 + salt)
end

local function urange(rng: any, lo: number, hi: number): number
	return lo + rng:next() * (hi - lo)
end

local function el(o: any): any
	return {
		name = o.name,
		shape = o.shape or "Block",
		size = o.size,
		position = o.position,
		orientation = o.orientation or v3(0, 0, 0),
		material = o.material or "Neon",
		color = o.color,
		transparency = o.transparency or 0,
		water = o.water == true,
		glow = o.glow == true, -- breathes with the geode pulse
	}
end

-- Bit-reversed order of 0..n-1 (n a power of two or not): the first half of the list is spread
-- over the whole range, so a half-weight piece is thin everywhere rather than full at one end.
local function spreadOrder(n: number): { number }
	local bits = 0
	while (2 ^ bits) < n do bits += 1 end
	local out = {}
	for i = 0, (2 ^ bits) - 1 do
		local r, x = 0, i
		for _ = 1, bits do
			r = r * 2 + (x % 2)
			x = math.floor(x / 2)
		end
		if r < n then table.insert(out, r) end
	end
	return out
end

function Grotto.layout(cfg: any, Rng: any, Cavern: any): any
	local C = Cavern.Const
	local counts = cfg.Env.Layout
	local pieces = {}

	--------------------------------------------------------------- pool shimmer (on the water)
	-- The server's Water top is y 20.8; the shimmer lies a hair above it, inside the basin footprint.
	pieces.poolShimmer = {
		el({ name = "Shimmer_1", size = v3(52, 0.05, 18), position = v3(0, 20.84, 119),
			color = { 120, 220, 235 }, transparency = 0.85, water = true, glow = true }),
		el({ name = "Shimmer_2", size = v3(40, 0.05, 12), position = v3(0, 20.86, 119), orientation = v3(0, 8, 0),
			color = { 170, 240, 250 }, transparency = 0.9, water = true, glow = true }),
	}

	--------------------------------------------------------------- glow-worms (hang from the ceiling)
	do
		local rng = stream(Rng, cfg, SALT.glowworm)
		local n = counts.Glowworms
		local z0, z1 = -10, 132
		local slot = (z1 - z0) / n
		local strands = {}
		for s = 0, n - 1 do
			local x, z
			repeat
				x = urange(rng, -29, 29)
				z = urange(rng, z0 + s * slot, z0 + (s + 1) * slot)
				-- the light-shaft hole (|x| < 14, 112 < z < 126) has no ceiling to hang from
			until not (math.abs(x) < 15 and z > 111 and z < 127)
			strands[s] = { x = x, z = z, len = urange(rng, 3, 7) }
		end
		local list = {}
		for _, s in spreadOrder(n) do
			local st = strands[s]
			table.insert(list, el({ name = "Worm_" .. s .. "_Thread", size = v3(0.08, st.len, 0.08),
				position = v3(st.x, C.CEIL_UNDER - st.len / 2, st.z), color = { 150, 230, 240 }, transparency = 0.55 }))
			table.insert(list, el({ name = "Worm_" .. s .. "_Bead", shape = "Ball", size = v3(0.45, 0.45, 0.45),
				position = v3(st.x, C.CEIL_UNDER - st.len, st.z), color = { 120, 255, 230 }, transparency = 0.05, glow = true }))
		end
		pieces.glowworms = list
	end

	--------------------------------------------------------------- giant mushrooms (against the walls)
	-- One per terrace 1..6, on the side AWAY from the server's small mushroom clusters, with the cap's
	-- inner edge beyond the socket zone (|x| 24.5) and the stem against the wall, like the boulders.
	do
		local rng = stream(Rng, cfg, SALT.shroom)
		local SIDES = { 1, 1, -1, -1, 1, 1 }
		local HUES = { { 200, 120, 255 }, { 255, 170, 90 }, { 90, 230, 210 } }
		local list = {}
		local n = math.min(counts.Shrooms, #SIDES)
		for k = 1, n do
			local c = k
			local side = SIDES[k]
			local x = side * 29.5
			local z = C.PITCH * c + 7
			local ground = C.RISE * c
			local h = urange(rng, 6.5, 9)
			local hue = HUES[1 + math.floor(rng:next() * #HUES)]
			local UP = v3(0, 0, 90)
			table.insert(list, el({ name = "Giant_" .. k .. "_Stem", shape = "Cylinder", size = v3(h, 1.4, 1.4),
				position = v3(x, ground + h / 2, z), orientation = UP, material = "SmoothPlastic", color = { 78, 80, 96 } }))
			table.insert(list, el({ name = "Giant_" .. k .. "_Cap", shape = "Ball", size = v3(6.5, 6.5, 6.5),
				position = v3(x, ground + h + 1.2, z), color = hue, transparency = 0.2, glow = true }))
			table.insert(list, el({ name = "Giant_" .. k .. "_Gills", shape = "Cylinder", size = v3(0.35, 8, 8),
				position = v3(x, ground + h, z), orientation = UP,
				color = { math.min(255, hue[1] + 40), math.min(255, hue[2] + 40), math.min(255, hue[3] + 40) }, transparency = 0.1, glow = true }))
		end
		pieces.shrooms = list
	end

	--------------------------------------------------------------- the waterfall (into the pool)
	-- Pours from a crack in the back ceiling (x -18) straight into the water; every part of it stays
	-- inside the pool's footprint, so the only way to walk through it is to wade.
	do
		local UP = v3(0, 0, 90)
		pieces.waterfall = {
			el({ name = "Fall_Sheet", size = v3(7, 23.4, 0.5), position = v3(-18, 32.5, 128.2),
				color = { 150, 220, 240 }, transparency = 0.55, water = true }),
			el({ name = "Fall_Core", size = v3(3.5, 23.4, 0.3), position = v3(-18, 32.5, 128.0),
				color = { 210, 245, 255 }, transparency = 0.35, water = true, glow = true }),
			el({ name = "Fall_Foam", shape = "Cylinder", size = v3(0.5, 9, 9), position = v3(-18, 20.95, 125.5),
				orientation = UP, color = { 235, 250, 255 }, transparency = 0.4, water = true }),
			el({ name = "Fall_Spray", shape = "Cylinder", size = v3(0.3, 10, 10), position = v3(-18, 21.3, 125),
				orientation = UP, color = { 200, 240, 255 }, transparency = 0.75, water = true }),
		}
	end

	--------------------------------------------------------------- the heart of the geode (walls around the pool)
	-- Crystal prisms growing out of the back wall and the side walls above the pool, high enough that
	-- nobody walking the pool ring passes through one (bottom above y 30).
	do
		local rng = stream(Rng, cfg, SALT.prism)
		local COLORS = { { 170, 110, 230 }, { 255, 90, 200 }, { 90, 200, 255 }, { 255, 190, 60 } }
		local list = {}
		-- every third prism on a side wall (alternating sides), the rest spread across the back wall in equal
		-- slots, so the geode wall is lined end to end instead of wherever the draws happened to fall
		local backCount = counts.GeodePrisms - math.floor(counts.GeodePrisms / 3)
		local backSlot, sideTurn = 0, 0
		for i = 1, counts.GeodePrisms do
			local w = urange(rng, 1.4, 2.6)
			local h = urange(rng, 5, 9)
			local tilt = urange(rng, 25, 55)
			local y = urange(rng, 36, 41)
			local color = COLORS[1 + math.floor(rng:next() * #COLORS)]
			local pos, ori
			if i % 3 ~= 0 then
				-- back wall: tilted around X so it juts out toward the cavern
				local slotW = 52 / backCount
				pos = v3(-26 + slotW * (backSlot + urange(rng, 0.15, 0.85)), y, 132.5)
				backSlot += 1
				ori = v3(-tilt, urange(rng, -20, 20), 0)
			else
				-- side walls beside the pool
				sideTurn += 1
				local side = if sideTurn % 2 == 1 then -1 else 1
				pos = v3(side * 31, y, urange(rng, 106, 128))
				ori = v3(0, urange(rng, -20, 20), side * tilt)
			end
			table.insert(list, el({ name = "Prism_" .. i, size = v3(w, h, w), position = pos, orientation = ori,
				color = color, transparency = 0.2, glow = true }))
		end
		pieces.geodeHeart = list
	end

	--------------------------------------------------------------- crystal seams (ceiling + upper walls)
	do
		local rng = stream(Rng, cfg, SALT.seam)
		local COLORS = { { 170, 110, 230 }, { 90, 200, 255 }, { 255, 90, 200 } }
		local list = {}
		for i = 1, counts.Seams do
			local len = urange(rng, 8, 18)
			local color = COLORS[1 + math.floor(rng:next() * #COLORS)]
			if i % 2 == 1 then
				-- across the ceiling over the terraces
				table.insert(list, el({ name = "Seam_" .. i, size = v3(0.35, 0.25, len),
					position = v3(urange(rng, -24, 24), C.CEIL_UNDER - 0.15, urange(rng, 6, 96)),
					orientation = v3(0, urange(rng, -35, 35), 0), color = color, transparency = 0.2, glow = true }))
			else
				-- high on a side wall, above the server's own veins (which stop at y 30), the two walls in turn
				local side = if i % 4 == 2 then 1 else -1
				table.insert(list, el({ name = "Seam_" .. i, size = v3(0.3, 1, len),
					position = v3(side * 31.85, urange(rng, 33, 40), urange(rng, 12, 96)),
					orientation = v3(urange(rng, -25, 25), 0, 0), color = color, transparency = 0.2, glow = true }))
			end
		end
		pieces.seams = list
	end

	for _, list in pieces do
		for i, e in list do e.order = i end
	end

	--------------------------------------------------------------- particle volumes (the "weather")
	local emitters = {
		drips = { position = v3(0, 43, 56), size = v3(56, 1, 120), color = { 150, 210, 230 } },
		spores = { position = v3(0, 14, 50), size = v3(56, 18, 100), color = { 220, 160, 255 } },
		mist = { position = v3(-18, 22, 125), size = v3(12, 2, 8), color = { 200, 235, 245 } },
		sparkle = { position = v3(0, 36, 119), size = v3(44, 14, 26), color = { 255, 200, 255 } },
	}

	--------------------------------------------------------------- critter zones (above every head)
	local zones = {
		moth = { min = v3(-28, 31, -8), max = v3(28, 40, 100) },
		bat = { min = v3(-28, 34, -8), max = v3(28, 42, 130) },
		-- wisps rise out of the water and up the light shaft
		wisp = { min = v3(-9, 21, 111), max = v3(9, 47, 127) },
	}

	--------------------------------------------------------------- visitor routes (enter and leave by the shaft)
	local routes = {
		batSwoop = {
			v3(0, 50, 119), v3(-2, 40, 116), v3(-14, 37, 100), v3(-18, 36, 72), v3(-4, 34, 48), v3(14, 34, 24),
			v3(16, 36, 2), v3(0, 37, -8), v3(-16, 36, 6), v3(-18, 37, 34), v3(-6, 38, 66), v3(6, 38, 94),
			v3(4, 41, 114), v3(0, 50, 120),
		},
		mothSwirl = {
			v3(0, 50, 119), v3(5, 40, 121), v3(-5, 36, 116), v3(0, 35, 106), v3(6, 33, 96), v3(0, 33, 86),
			v3(-6, 33, 96), v3(-3, 35, 108), v3(4, 38, 118), v3(0, 50, 119),
		},
	}

	return { pieces = pieces, emitters = emitters, zones = zones, routes = routes }
end

return Grotto
