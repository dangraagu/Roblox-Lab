-- Cavern.luau — "The Sunken Grotto": the per-plot cavern geometry, as a PURE function.
--
-- Returns plain Lua tables describing parts. Nothing Roblox-specific is referenced (no engine
-- datatype, no service, no scheduler), so the whole generator runs in the luau CLI with no
-- engine present and every containment / reachability / budget invariant is unit-assertable.
-- The server turns the returned tables into real Parts and is the only place that knows about
-- the engine.
--
-- COORDINATES ARE PLOT-LOCAL, origin (0,0,0). The server adds (plotIndex * 80, 0, 0) at
-- instantiation and nowhere else. Local X is across the slice, Z is depth, Y is up.
--
-- Dependencies are ARGUMENTS, never a relative require: a bare require("./Rng") resolves in the
-- luau CLI and is invalid in Roblox, so `build` takes the Rng module the caller already has.
--
-- Layout, in one paragraph: eight 13-stud terraces climb 3 studs each from an entrance apron at
-- y = 0 to a pool at y = 21, joined by full-width two-step stairs with no edge to fall off. Each
-- terrace carries one chamber's six socket plates. Behind the top terrace is a shallow basin of
-- glowing water with a light shaft falling into it through a hole in the ceiling. The shell is
-- sealed on all six sides except that hole, so nobody can leave the slice or fall out of it.

local Cavern = {}

--============================================================================ constants

local PITCH = 13        -- Z per terrace
local RISE = 3          -- Y per terrace
local HALF_W = 32       -- interior half-width; interior x in [-32, +32]
local WALL_T = 4        -- walls occupy x in [+-32, +-36]
local DECK_BOTTOM = -3  -- every deck/tread slab reaches down to y = -3
local CEIL_UNDER = 44
local CEIL_TOP = 48
local G = 8             -- chambers / terraces

Cavern.Const = {
	PITCH = PITCH, RISE = RISE, HALF_W = HALF_W, WALL_T = WALL_T,
	DECK_BOTTOM = DECK_BOTTOM, CEIL_UNDER = CEIL_UNDER, CEIL_TOP = CEIL_TOP, G = G,
}

-- Per-feature salts. One stream per decoration group, so adding or removing a group later
-- cannot shift another group's numbers.
local SALT = {
	stalactite = 11, boulder = 13, rubble = 17, mushroom = 19, vein = 23, lock = 29,
}
local SEED_MIX = 7919
local PLOT_MIX = 104729
local SOCKET_SALT = 31

local DEFAULT_COUNTS = {
	Stalactites = 16, Boulders = 14, Rubble = 10, Veins = 10, Mushrooms = 12,
}

local RAD = math.pi / 180

--============================================================================ tiny helpers

local function v3(x, y, z) return { x = x, y = y, z = z } end
local function rgb(r, g, b) return { r = r, g = g, b = b } end

-- Every draw uses rng:next() -- state / 2^32, the HIGH bits. Never rng:int(): that is
-- `min + state % span`, the low bits of an LCG, and it collapses to one value per row.
local function urange(rng, lo, hi) return lo + rng:next() * (hi - lo) end
local function upick(rng, list) return list[math.min(#list, 1 + math.floor(rng:next() * #list))] end

local function stream(Rng, cfg, plotIndex, salt)
	return Rng.new(cfg.WorldSeed * SEED_MIX + plotIndex * PLOT_MIX + salt)
end

-- Rows of Rx*Ry*Rz (the engine's Angles order), signed.
local function rotRows(ori)
	local cx, sx = math.cos(ori.x * RAD), math.sin(ori.x * RAD)
	local cy, sy = math.cos(ori.y * RAD), math.sin(ori.y * RAD)
	local cz, sz = math.cos(ori.z * RAD), math.sin(ori.z * RAD)
	return {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
end

local function halfExtents(size, ori)
	local r = rotRows(ori)
	local h = { size.x / 2, size.y / 2, size.z / 2 }
	local out = {}
	for i = 1, 3 do
		out[i] = math.abs(r[i][1]) * h[1] + math.abs(r[i][2]) * h[2] + math.abs(r[i][3]) * h[3]
	end
	return out[1], out[2], out[3]
end

-- The walkable top at a given depth: apron, terrace, one of its two treads, or the pool shelf.
local function groundAt(z)
	if z < 0 then return 0 end
	if z >= PITCH * G then return 21 end
	local c = math.floor(z / PITCH)
	local r = z - PITCH * c
	if r >= 11 then return RISE * c + 3 end
	if r >= 9 then return RISE * c + 1.5 end
	return RISE * c
end

--============================================================================ socket grid

-- socketId is the identity the save file and every remote already use; it is never a position.
-- The jitter stream carries NO plotIndex: claimPlot recycles indices, so a rejoining player has
-- to find their grid exactly where muscle memory expects it.
local function jitterTable(cfg, Rng)
	local total = cfg.Economy.MaxChambers * cfg.Economy.SocketsPerChamber
	local rng = Rng.new(cfg.WorldSeed * SEED_MIX + SOCKET_SALT)
	local out = {}
	for s = 1, total do out[s] = urange(rng, -0.75, 0.75) end
	return out
end

local function socketAt(cfg, socketId, jitter)
	local per = cfg.Economy.SocketsPerChamber
	local c = math.floor((socketId - 1) / per)
	local col = (socketId - 1) % per
	return v3(col * 8 - 20 + jitter, RISE * c, PITCH * c + 5)
end

-- Pure: same cfg, same socketId, same answer, on every plot and in every process.
function Cavern.socketPos(cfg, socketId, Rng)
	return socketAt(cfg, socketId, jitterTable(cfg, Rng)[socketId])
end

function Cavern.spawn(_cfg)
	-- Floor point (0,0,-6); the root part sits 4 studs up; you look down +Z into the cavern, so
	-- the first frame is terrace 0's six plates 8 studs ahead and the lit pool 120 studs away.
	return { position = v3(0, 4, -6), look = v3(0, 0, 1) }
end

--============================================================================ part construction

local function makePart(o)
	return {
		name = o.name,
		group = o.group,
		shape = o.shape or "Block",
		size = o.size,
		position = o.position,
		orientation = o.orientation or v3(0, 0, 0),
		material = o.material,
		color = o.color,
		transparency = o.transparency or 0,
		reflectance = o.reflectance or 0,
		collide = o.collide == true,
		query = o.query == true,
		castShadow = o.collide == true, -- castShadow == collide, for every part, always
		walkable = o.walkable == true,
		chamber = o.chamber or -1,
		chamberLabel = o.chamberLabel,
	}
end

-- A solid, axis-aligned, walkable slab. Every one of the 36 colliders is built through here, so
-- "colliders are axis-aligned" is structural rather than a thing to remember.
local function slab(name, group, size, position, color, walkable)
	return makePart({
		name = name, group = group, size = size, position = position,
		material = (group == "wall" or group == "ceiling") and "Rock" or "Slate",
		color = color, collide = true, query = true, walkable = walkable,
	})
end

local function deco(name, group, shape, size, position, orientation, material, color, transparency)
	return makePart({
		name = name, group = group, shape = shape, size = size, position = position,
		orientation = orientation, material = material, color = color,
		transparency = transparency, collide = false, query = false, walkable = false,
	})
end

--============================================================================ build

function Cavern.build(cfg, plotIndex, Rng)
	local counts = cfg.Cavern or DEFAULT_COUNTS
	local parts = {}
	local function add(p) parts[#parts + 1] = p end

	-- ── mushrooms are generated FIRST (into a holding list) because the five cluster hues also
	--    colour five of the ten lights, and the lights are emitted before the decoration block.
	local CLUSTERS = {
		{ x = -29, z = -4 }, { x = 29, z = 6 }, { x = -29, z = 32 },
		{ x = 29, z = 58 }, { x = -29, z = 84 },
	}
	local HUES = { rgb(90, 220, 210), rgb(170, 130, 240), rgb(255, 190, 120) }
	local shroomRng = stream(Rng, cfg, plotIndex, SALT.mushroom)
	local hues, shrooms = {}, {}
	do
		local n = counts.Mushrooms
		local base = math.floor(n / #CLUSTERS)
		local rem = n - base * #CLUSTERS
		for i, cl in ipairs(CLUSTERS) do
			hues[i] = upick(shroomRng, HUES)
			local gy = groundAt(cl.z)
			local mine = base + (i <= rem and 1 or 0)
			for j = 1, mine do
				local x = cl.x + urange(shroomRng, -2.5, 2.5)
				local z = cl.z + urange(shroomRng, -3, 3)
				shrooms[#shrooms + 1] = { i = i, j = j, x = x, z = z, y = gy, hue = hues[i] }
			end
		end
	end

	--------------------------------------------------------------- 1-8: terrace decks
	for c = 0, G - 1 do
		add(slab("Deck_" .. c, "deck",
			v3(HALF_W * 2, RISE * c + 3, PITCH),
			v3(0, 1.5 * c - 1.5, PITCH * c + 6.5),
			rgb(56 - 3 * c, 62 - 3 * c, 76 - 3 * c), true))
	end

	--------------------------------------------------------------- 9-22: stair treads
	-- Each slab's own front face IS the riser, so a terrace costs one part. Two 1.5-stud steps,
	-- full 64-stud width, symmetric up and down: there is no edge anywhere to fall off.
	local TREAD_COLOR = rgb(64, 70, 84)
	for c = 0, G - 2 do
		add(slab("TreadA_" .. c, "tread", v3(HALF_W * 2, RISE * c + 4.5, 2),
			v3(0, 1.5 * c - 0.75, PITCH * c + 10), TREAD_COLOR, true))
		add(slab("TreadB_" .. c, "tread", v3(HALF_W * 2, RISE * c + 6, 2),
			v3(0, 1.5 * c, PITCH * c + 12), TREAD_COLOR, true))
		-- The chamber's price is painted on the TOP of the last step up to it, not on the deck
		-- riser. Review measured the deck version and found it 100% buried on all seven: a deck's
		-- -Z face at z = PITCH*c is exactly coplanar with, and the same width and height as, the
		-- back face of this very tread - an opaque 2-stud collider. 384/384 studs buried on
		-- Deck_1, 1536/1536 on Deck_7. Seven signs, fourteen replicated instances per plot, and
		-- not one pixel of it ever reached a player.
		-- This face is the step you walk up, flush with the deck above and exposed, so the price
		-- is under your feet as you arrive at the terrace it belongs to.
		parts[#parts].chamberLabel = c + 1
	end

	--------------------------------------------------------------- 23: entrance apron
	add(slab("Apron", "apron", v3(HALF_W * 2, 3, 14), v3(0, -1.5, -7), rgb(56, 62, 76), true))

	--------------------------------------------------------------- 24-28: pool shelf + basin
	-- All four shelf strips top out at 21, flush with Deck_7, so you walk onto the pool ring
	-- with no step. Their inner faces are the basin walls at zero extra cost.
	local SHELF_COLOR = rgb(38, 48, 60)
	add(slab("ShelfFront", "shelf", v3(64, 3, 4), v3(0, 19.5, 106), SHELF_COLOR, true))
	add(slab("ShelfBack", "shelf", v3(64, 3, 4), v3(0, 19.5, 132), SHELF_COLOR, true))
	add(slab("ShelfLeft", "shelf", v3(4, 3, 22), v3(-30, 19.5, 119), SHELF_COLOR, true))
	add(slab("ShelfRight", "shelf", v3(4, 3, 22), v3(30, 19.5, 119), SHELF_COLOR, true))
	add(slab("BasinFloor", "basin", v3(56, 3, 22), v3(0, 17.9, 119), SHELF_COLOR, true))

	--------------------------------------------------------------- 29-30: water + its glow bed
	-- 1.4 studs deep against a 1.6-stud lip: under R15's hip height, so you step out anywhere,
	-- and there is no Terrain here, so a Humanoid never enters Swimming. Do not deepen it.
	add(makePart({
		name = "Water", group = "water", size = v3(56, 0.6, 22), position = v3(0, 20.5, 119),
		material = "SmoothPlastic", color = rgb(60, 130, 150), transparency = 0.5, reflectance = 0.3,
	}))
	add(deco("GlowBed", "glow", "Block", v3(54, 0.4, 20), v3(0, 19.6, 119), nil,
		"Neon", rgb(70, 190, 200), 0.35))

	--------------------------------------------------------------- 31-33: the light shaft
	-- A Cylinder runs along its local X, so orientation (0,0,90) stands it up and
	-- size = (length, diameter, diameter). Two concentric cylinders fake a falloff one cannot.
	local UP = v3(0, 0, 90)
	add(deco("ShaftInner", "shaft", "Cylinder", v3(24, 12, 12), v3(0, 32.8, 119), UP,
		"Neon", rgb(205, 230, 245), 0.82))
	add(deco("ShaftOuter", "shaft", "Cylinder", v3(24, 24, 24), v3(0, 32.8, 119), UP,
		"Neon", rgb(180, 215, 240), 0.93))
	add(deco("ShaftSplash", "shaft", "Cylinder", v3(0.4, 26, 26), v3(0, 20.9, 119), UP,
		"Neon", rgb(170, 220, 235), 0.7))

	--------------------------------------------------------------- 34-37: ceiling, with the hole
	local CEIL_COLOR = rgb(34, 36, 46)
	local CEIL_MID = (CEIL_UNDER + CEIL_TOP) / 2
	add(slab("CeilFront", "ceiling", v3(72, 4, 130), v3(0, CEIL_MID, 47), CEIL_COLOR, false))
	add(slab("CeilBack", "ceiling", v3(72, 4, 12), v3(0, CEIL_MID, 132), CEIL_COLOR, false))
	add(slab("CeilLeft", "ceiling", v3(22, 4, 14), v3(-25, CEIL_MID, 119), CEIL_COLOR, false))
	add(slab("CeilRight", "ceiling", v3(22, 4, 14), v3(25, CEIL_MID, 119), CEIL_COLOR, false))

	--------------------------------------------------------------- 38-41: the sealing shell
	-- Highest walkable point is 21 and the walls top out at 48 — 27 studs above, far beyond a
	-- ~7.2-stud jump. Closed on all six sides bar the shaft hole.
	local WALL_COLOR = rgb(38, 40, 52)
	local WALL_MID = (CEIL_TOP + -6) / 2
	local WALL_H = CEIL_TOP + 6
	add(slab("WallLeft", "wall", v3(WALL_T, WALL_H, 156), v3(-(HALF_W + WALL_T / 2), WALL_MID, 60),
		WALL_COLOR, false))
	add(slab("WallRight", "wall", v3(WALL_T, WALL_H, 156), v3(HALF_W + WALL_T / 2, WALL_MID, 60),
		WALL_COLOR, false))
	add(slab("WallFront", "wall", v3(72, WALL_H, WALL_T), v3(0, WALL_MID, -16), WALL_COLOR, false))
	add(slab("WallBack", "wall", v3(72, WALL_H, WALL_T), v3(0, WALL_MID, 136), WALL_COLOR, false))

	--------------------------------------------------------------- 42-51: lamp nubs
	-- Ten lights per plot, against 96 in the build this replaces. The preset sets ClockTime = 0,
	-- so there is no sun and no fill: if these do not parent, the cavern is pitch black. The
	-- emulator gate asserts the light count for exactly that reason.
	local LAMPS = {
		{ name = "Lamp_ShaftBase", pos = v3(0, 22.5, 119), color = rgb(200, 230, 245), b = 3.0, r = 60 },
		{ name = "Lamp_PoolDeep", pos = v3(0, 19.9, 119), color = rgb(80, 200, 210), b = 2.0, r = 40 },
		{ name = "Lamp_Shroom1", pos = v3(-29, 2.5, -4), color = hues[1], b = 1.4, r = 24 },
		{ name = "Lamp_Shroom2", pos = v3(29, 2.5, 6), color = hues[2], b = 1.4, r = 24 },
		{ name = "Lamp_Shroom3", pos = v3(-29, 8.5, 32), color = hues[3], b = 1.4, r = 24 },
		{ name = "Lamp_Shroom4", pos = v3(29, 14.5, 58), color = hues[4], b = 1.4, r = 24 },
		{ name = "Lamp_Shroom5", pos = v3(-29, 20.5, 84), color = hues[5], b = 1.4, r = 24 },
		{ name = "Lamp_VeinLow", pos = v3(-31, 10, 20), color = rgb(110, 190, 220), b = 1.3, r = 34 },
		{ name = "Lamp_VeinMid", pos = v3(31, 18, 62), color = rgb(110, 190, 220), b = 1.3, r = 34 },
		{ name = "Lamp_Entrance", pos = v3(0, 20, -11), color = rgb(255, 186, 120), b = 1.8, r = 44 },
	}
	local lights = {}
	for _, l in ipairs(LAMPS) do
		-- The nub itself is a neutral invisible cube on every plot; only its LIGHT carries the
		-- cluster hue, so the parts array stays byte-identical across plots.
		add(makePart({
			name = l.name, group = "lamp", size = v3(0.4, 0.4, 0.4), position = l.pos,
			material = "SmoothPlastic", color = rgb(255, 255, 255), transparency = 1,
		}))
		lights[#lights + 1] = {
			name = l.name, position = l.pos, color = l.color, brightness = l.b, range = l.r,
		}
	end

	--------------------------------------------------------------- 52-125: decoration
	-- Everything below is collide = false, query = false, castShadow = false, and seeded per
	-- feature. This is the only block that varies from plot to plot.

	-- stalactites: silhouettes against the glow from below, one part each
	do
		local rng = stream(Rng, cfg, plotIndex, SALT.stalactite)
		for i = 1, counts.Stalactites do
			local w = urange(rng, 1.4, 2.6)
			local h = urange(rng, 6, 12)
			local x = urange(rng, -30, 30)
			local z = urange(rng, -10, 100)
			local rx = urange(rng, -6, 6)
			local rz = urange(rng, -6, 6)
			add(deco("Stalactite_" .. i, "stalactite", "Block", v3(w, h, w),
				v3(x, CEIL_UNDER - h / 2, z), v3(rx, 0, rz), "Rock", rgb(30, 32, 42), 0))
		end
	end

	-- boulders: buried in the side walls and around the pool. Free rotation plus burial depth is
	-- what makes an axis-agnostic box read as a rock lump with no seam.
	--
	-- The distance out from the centre line is DERIVED from the rotated half-extent rather than
	-- drawn independently: that is what keeps every boulder simultaneously clear of the outermost
	-- socket plate (|x| = 23.75) and inside the shell (|x| = 36), for any size and any angle.
	do
		local rng = stream(Rng, cfg, plotIndex, SALT.boulder)
		local poolFrom = counts.Boulders - 4
		for i = 1, counts.Boulders do
			local size = v3(urange(rng, 4, 7), urange(rng, 4, 7), urange(rng, 6, 10))
			local ori = v3(urange(rng, -8, 8), urange(rng, -25, 25), urange(rng, -8, 8))
			local hx = halfExtents(size, ori)
			local lo = 24.5 + hx
			local hi = HALF_W + WALL_T - hx
			local mag = lo + rng:next() * math.max(hi - lo, 0)
			local sign = rng:next() < 0.5 and -1 or 1
			local z = (i > poolFrom) and urange(rng, 106, 132) or urange(rng, 2, 100)
			local tint = urange(rng, -6, 6)
			add(deco("Boulder_" .. i, "boulder", "Block", size,
				v3(sign * mag, groundAt(z) + size.y * 0.3, z), ori,
				"Rock", rgb(44 + tint, 46 + tint, 58 + tint), 0))
		end
	end

	-- rubble: loose stones on the apron and the first three terraces. Pushed clear of the spawn
	-- keep-out whenever the draw would have landed in it.
	do
		local rng = stream(Rng, cfg, plotIndex, SALT.rubble)
		for i = 1, counts.Rubble do
			local size = v3(urange(rng, 1, 3), urange(rng, 1, 3), urange(rng, 1, 3))
			local ori = v3(urange(rng, -20, 20), urange(rng, 0, 360), urange(rng, -20, 20))
			local x = urange(rng, -30, 30)
			local z = urange(rng, -13, 35)
			local hx, _, hz = halfExtents(size, ori)
			if z - hz < 0.5 and z + hz > -12.5 then
				local need = 6.5 + hx
				local sign = x < 0 and -1 or 1
				if math.abs(x) < need then x = sign * need end
			end
			-- And clear of the socket grid, which rubble was the one decoration group with no
			-- keep-out from. Review measured 114 rubble-vs-plate and 25 rubble-vs-crystal
			-- intersections across 20 plots: about a third of a new player's visible sockets had
			-- a rock through the glowing plate, and roughly one crystal per plot grew out of a
			-- stone. Harmless - rubble is collide=false, query=false, so it never blocks a click
			-- and never traps anyone - but it reads as a bug, and every geometry check in the
			-- spec filters on walkable/query/collide, so nothing could see it.
			-- Boulders already derive the same clamp; rubble now uses it. |x| = 23.75 is the
			-- outer edge of the outermost socket plate.
			-- A socket row sits at z = PITCH*c + 5 and its plates are 6 deep, so the band is
			-- +/- 3 around that. Rubble only ever reaches z = 35, so this is chambers 0-2.
			for c = 0, 2 do
				local rowZ = PITCH * c + 5
				if z - hz < rowZ + 3 and z + hz > rowZ - 3 then
					local need = 23.75 + hx
					if math.abs(x) < need then
						x = (x < 0 and -1 or 1) * need
					end
					break
				end
			end
			add(deco("Rubble_" .. i, "rubble", "Block", size,
				v3(x, groundAt(z) + size.y * 0.3, z), ori, "Rock", rgb(48, 50, 62), 0))
		end
	end

	-- veins: 0.1 proud of the wall face. Neon blooms under the preset's threshold-0.9 Bloom, so
	-- these glow at zero light cost.
	do
		local rng = stream(Rng, cfg, plotIndex, SALT.vein)
		for i = 1, counts.Veins do
			local len = urange(rng, 10, 20)
			local sign = rng:next() < 0.5 and -1 or 1
			local y = urange(rng, 4, 30)
			local z = urange(rng, 0, 120)
			add(deco("Vein_" .. i, "vein", "Block", v3(0.4, 1.2, len),
				v3(sign * 31.9, y, z), nil, "Neon", rgb(90, 180, 205), 0.25))
		end
	end

	-- mushrooms: a Ball renders as a sphere of its smallest axis, so the cap stays uniform.
	for _, m in ipairs(shrooms) do
		local tag = m.i .. "_" .. m.j
		add(deco("Shroom_" .. tag .. "_Stem", "stem", "Cylinder", v3(2.5, 0.9, 0.9),
			v3(m.x, m.y + 1.25, m.z), v3(0, 0, 90), "SmoothPlastic", rgb(70, 74, 88), 0))
		add(deco("Shroom_" .. tag .. "_Cap", "cap", "Ball", v3(2.6, 2.6, 2.6),
			v3(m.x, m.y + 2.5, m.z), nil, "Neon", m.hue, 0.15))
	end

	--------------------------------------------------------------- 126-149: chamber lock caps
	-- A locked chamber gets near-black rubble over its socket row and a price on the riser face.
	-- Never a wall, a plug or a door: these neither collide nor block a ray, so the worst thing a
	-- failed teardown can do is leave a stale rock over working sockets. Nobody can ever be
	-- stranded behind geometry they paid for.
	do
		-- NO plotIndex in this stream. Section 5 of the spec lists the 24 lock caps among the
		-- things that are identical on every plot, and it has to be: claimPlot recycles indices,
		-- so the rubble over a chamber you have not bought yet must not change shape because
		-- somebody else left the server. Same reason the socket jitter carries no plotIndex.
		local rng = Rng.new(cfg.WorldSeed * SEED_MIX + SALT.lock)
		for c = 0, G - 1 do
			for i = 0, 2 do
				local ry = urange(rng, -14, 14)
				local p = deco("Lock_" .. c .. "_" .. i, "lock", "Block", v3(20, 1.2, 7),
					v3(-16 + 16 * i, RISE * c + 0.6, PITCH * c + 5), v3(0, ry, 0),
					"Rock", rgb(26, 27, 34), 0)
				p.chamber = c
				add(p)
			end
		end
	end

	--------------------------------------------------------------- sockets, stands, bounds
	local jitter = jitterTable(cfg, Rng)
	local total = cfg.Economy.MaxChambers * cfg.Economy.SocketsPerChamber
	local sockets, stands = {}, {}
	for s = 1, total do
		local sp = socketAt(cfg, s, jitter[s])
		sockets[s] = sp
		-- bare deck, one stud past the top tread of the terrace below, four studs in front of
		-- the plate: a ~5.7-stud sight line against a 32-stud activation distance.
		stands[s] = v3(sp.x, sp.y, PITCH * math.floor((s - 1) / cfg.Economy.SocketsPerChamber) + 1)
	end

	local bounds = {
		minX = math.huge, maxX = -math.huge, minY = math.huge,
		maxY = -math.huge, minZ = math.huge, maxZ = -math.huge,
	}
	for _, p in ipairs(parts) do
		local hx, hy, hz = halfExtents(p.size, p.orientation)
		bounds.minX = math.min(bounds.minX, p.position.x - hx)
		bounds.maxX = math.max(bounds.maxX, p.position.x + hx)
		bounds.minY = math.min(bounds.minY, p.position.y - hy)
		bounds.maxY = math.max(bounds.maxY, p.position.y + hy)
		bounds.minZ = math.min(bounds.minZ, p.position.z - hz)
		bounds.maxZ = math.max(bounds.maxZ, p.position.z + hz)
	end

	return {
		parts = parts,
		lights = lights,
		dust = {
			{ name = "Dust_Shaft", position = v3(0, 32, 119), size = v3(28, 26, 20),
				color = rgb(210, 235, 245), rate = 22 },
			{ name = "Dust_Grotto", position = v3(0, 20, 50), size = v3(64, 40, 110),
				color = rgb(150, 200, 220), rate = 12 },
		},
		sockets = sockets,
		stands = stands,
		spawn = Cavern.spawn(cfg),
		camera = {
			hero = { from = v3(-9, 9.5, 34), at = v3(2, 22, 116) },
			wide = { from = v3(0, 25, 130), at = v3(0, 2, 0) },
		},
		bounds = bounds,
	}
end

return Cavern
