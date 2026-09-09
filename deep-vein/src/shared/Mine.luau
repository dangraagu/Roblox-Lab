--!strict
-- Mine.luau — the procedural cave, as a PURE function. No Roblox global is touched anywhere in
-- this file, dependencies (Ore) arrive as ARGUMENTS, and everything returned is a plain table.
-- The server is the only file that knows a Part exists.
--
-- WHY A GRID OF PARTS AND NOT TERRAIN
-- Roblox's voxel Terrain would look better and would be untestable: the only way to ask it what
-- is at a point is to ask a running engine. A grid answers "what is at this cell, and what does
-- breaking it yield" as arithmetic, so every rule below is asserted from the luau CLI before the
-- game is ever opened. That trade is the whole reason this file is shaped the way it is.
--
-- WHY A STATELESS HASH AND NOT AN LCG STREAM
-- Grow a Crystal seeds an Rng and walks it; the sequence is the state. That cannot work here,
-- because a player uncovers cells in whatever order they choose to dig, and a cell's contents
-- must not depend on when it was first looked at. So each cell's numbers come from a stateless
-- mixer over (seed, x, y, z, salt): order-independent, and identical in the CLI and in Roblox.
-- Determinism still comes from one WorldSeed — see `seedFor`.
--
-- COORDINATES. Cells are (x, y, z) integers. x and z run 1..GridW across the shaft; y counts
-- DOWNWARD, y = 0 being the open mouth at the surface. The world is a closed box: a bedrock ring
-- at x/z = 1 and GridW, a bedrock floor one layer past the depth wall, and open only at the top.

local Mine = {}

local MOD32 = 4294967296

-- Salts. One per stream, so adding a new one later cannot shift an existing one's numbers.
local SALT_CARVE = 1013
local SALT_ORE = 2027
local SEED_MIX = 7919
local REBIRTH_MIX = 104729

Mine.Salt = { Carve = SALT_CARVE, Ore = SALT_ORE }

--============================================================================ integer mixing

-- 32-bit multiply that is EXACT in a double. `a * b` with both near 2^32 is 2^64 and silently
-- loses its low bits, which would make the mixer's whole point (avalanche in the low bits)
-- disappear. Splitting `a` into 16-bit halves keeps every partial product under 2^48.
local function mul32(a: number, b: number): number
	local ah = math.floor(a / 65536)
	local al = a - ah * 65536
	return ((ah * b % 65536) * 65536 + al * b) % MOD32
end

local function u32(n: number): number
	-- Lua's % always returns a value with the sign of the divisor, so negatives come back
	-- non-negative here without a branch.
	return math.floor(n) % MOD32
end

-- murmur3's finalizer. Cheap, and it is the standard answer to "make these bits look random".
local function mix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 2246822507)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 3266489909)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

function Mine.hash(seed: number, x: number, y: number, z: number, salt: number?): number
	local h = mix32(u32(seed))
	h = mix32(bit32.bxor(h, mul32(u32(x), 2654435761)))
	h = mix32(bit32.bxor(h, mul32(u32(y), 2246822519)))
	h = mix32(bit32.bxor(h, mul32(u32(z), 3266489917)))
	return mix32(bit32.bxor(h, u32(salt or 0)))
end

-- The same, as a float in [0, 1).
function Mine.unit(seed: number, x: number, y: number, z: number, salt: number?): number
	return Mine.hash(seed, x, y, z, salt) / MOD32
end

--============================================================================ coherent noise

-- Value noise: hash the eight lattice corners around a point and interpolate between them with
-- a smoothstep. This is what turns independent per-cell numbers into connected voids — the
-- difference between a cave and static.
local function fade(t: number): number
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Mine.noise(seed: number, x: number, y: number, z: number, salt: number?): number
	local x0, y0, z0 = math.floor(x), math.floor(y), math.floor(z)
	local tx, ty, tz = fade(x - x0), fade(y - y0), fade(z - z0)
	local function corner(dx: number, dy: number, dz: number): number
		return Mine.unit(seed, x0 + dx, y0 + dy, z0 + dz, salt)
	end
	local x00 = lerp(corner(0, 0, 0), corner(1, 0, 0), tx)
	local x10 = lerp(corner(0, 1, 0), corner(1, 1, 0), tx)
	local x01 = lerp(corner(0, 0, 1), corner(1, 0, 1), tx)
	local x11 = lerp(corner(0, 1, 1), corner(1, 1, 1), tx)
	return lerp(lerp(x00, x10, ty), lerp(x01, x11, ty), tz)
end

--============================================================================ the world

-- Determinism, the reason a depth leaderboard means anything: same WorldSeed and same rebirth
-- count = the same cave, for every player, in every server, forever.
function Mine.seedFor(cfg: any, rebirths: number): number
	return u32(cfg.WorldSeed * SEED_MIX + (rebirths or 0) * REBIRTH_MIX)
end

-- The depth wall. Rebirth is what moves it, which is what turns "I cannot dig any deeper" into
-- a reason to prestige rather than a reason to leave.
function Mine.maxLayer(cfg: any, rebirths: number): number
	return cfg.Mine.BaseMaxLayer + (rebirths or 0) * cfg.Mine.LayersPerRebirth
end

-- One descriptor threaded through everything else, so nobody can pass a seed from one rebirth
-- alongside a depth wall from another.
export type World = { seed: number, maxLayer: number, rebirths: number }

function Mine.world(cfg: any, rebirths: number): World
	local r = rebirths or 0
	return { seed = Mine.seedFor(cfg, r), maxLayer = Mine.maxLayer(cfg, r), rebirths = r }
end

function Mine.center(cfg: any): number
	return math.floor((cfg.Mine.GridW + 1) / 2)
end

function Mine.key(x: number, y: number, z: number): string
	return x .. ":" .. y .. ":" .. z
end

function Mine.inWorld(cfg: any, w: World, x: number, y: number, z: number): boolean
	local gw = cfg.Mine.GridW
	return x >= 1 and x <= gw and z >= 1 and z <= gw and y >= 0 and y <= w.maxLayer + 1
end

--============================================================================ what is at a cell

-- Multi-octave carving field in [0, 1). Higher = more likely to be void.
function Mine.density(cfg: any, w: World, x: number, y: number, z: number): number
	local m = cfg.Mine
	local amp, freq, sum, norm = 1, 1, 0, 0
	for o = 1, m.Octaves do
		sum += amp * Mine.noise(
			w.seed + o * SEED_MIX,
			x / m.NoiseScaleXZ * freq,
			y / m.NoiseScaleY * freq,
			z / m.NoiseScaleXZ * freq,
			SALT_CARVE
		)
		norm += amp
		amp *= m.OctaveGain
		freq *= m.OctaveLacunarity
	end
	return sum / norm
end

-- The single uniform draw that decides which ore a rock cell holds. Its own salt, so retuning
-- the carving never reshuffles the veins and vice versa.
function Mine.oreRoll(cfg: any, w: World, x: number, y: number, z: number): number
	return Mine.unit(w.seed, x, y, z, SALT_ORE)
end

-- "air" | "rock" | "bedrock" | "void". Order matters: the ring is checked before the mouth, so
-- the mouth is a hole in a wall rather than an opening in the side of the map.
function Mine.kindAt(cfg: any, w: World, x: number, y: number, z: number): string
	if not Mine.inWorld(cfg, w, x, y, z) then return "void" end
	local gw = cfg.Mine.GridW
	if x == 1 or x == gw or z == 1 or z == gw then return "bedrock" end
	if y > w.maxLayer then return "bedrock" end -- the floor: this IS the depth wall
	if y < 1 then return "air" end -- the mouth you drop into
	if y <= cfg.Mine.SolidTopLayers then return "rock" end -- a new player always lands on a floor
	if Mine.density(cfg, w, x, y, z) > cfg.Mine.AirThreshold then return "air" end
	return "rock"
end

function Mine.isSolid(cfg: any, w: World, x: number, y: number, z: number): boolean
	return Mine.kindAt(cfg, w, x, y, z) ~= "air"
end

-- Block hit points: the ore's base hardness, made tougher with depth. Never below 1, or a deep
-- block with an unlucky config would be unbreakable by a swing of any size.
function Mine.hardnessAt(cfg: any, Ore: any, tier: number, y: number): number
	local base = Ore.hardness(cfg, tier)
	return math.max(1, math.floor(base * (1 + cfg.Mine.HardnessPerLayer * y)))
end

export type Cell = {
	x: number, y: number, z: number, key: string,
	kind: string, ore: number, hp: number, breakable: boolean,
}

-- THE question this module exists to answer: what is at this cell, and what does breaking it
-- yield? `ore` is the yield (0 = plain stone, worth nothing), `hp` is what it costs to get it.
function Mine.cell(cfg: any, Ore: any, w: World, x: number, y: number, z: number): Cell
	local kind = Mine.kindAt(cfg, w, x, y, z)
	if kind ~= "rock" then
		return { x = x, y = y, z = z, key = Mine.key(x, y, z),
			kind = kind, ore = 0, hp = 0, breakable = false }
	end
	local tier = Ore.tierAt(cfg, y, Mine.oreRoll(cfg, w, x, y, z))
	return {
		x = x, y = y, z = z, key = Mine.key(x, y, z),
		kind = kind, ore = tier, hp = Mine.hardnessAt(cfg, Ore, tier, y), breakable = true,
	}
end

--============================================================================ geometry mapping

-- Shaft-LOCAL studs, origin (0, 0, 0) at the centre of the mouth's surface plane. The server
-- adds the per-player shaft offset at instantiation and nowhere else.
function Mine.localPos(cfg: any, x: number, y: number, z: number): { x: number, y: number, z: number }
	local s = cfg.Mine.CellSize
	local c = (cfg.Mine.GridW + 1) / 2
	return { x = (x - c) * s, y = -(y - 0.5) * s, z = (z - c) * s }
end

-- How deep layer `y` is, in studs. This is the number on the HUD and on the leaderboard.
function Mine.depthStuds(cfg: any, y: number): number
	return y * cfg.Mine.CellSize
end

function Mine.layerAtDepth(cfg: any, studs: number): number
	return math.floor(studs / cfg.Mine.CellSize)
end

-- The Y a character standing INSIDE cell `y` has its feet on: the top face of cell y+1.
function Mine.floorY(cfg: any, y: number): number
	return -y * cfg.Mine.CellSize
end

--============================================================================ reveal

-- Walk with 6 neighbours, because that is what a player can move through.
local WALK = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

-- Collect with all 26, because that is what a player can SEE. Collecting with 6 leaves the four
-- corner columns of the ring unbuilt at every layer — a diagonal gap looking straight out of the
-- world, at the most visible place in the game. Two extra parts per corner is the cheap fix.
local LOOK = {}
for dx = -1, 1 do
	for dy = -1, 1 do
		for dz = -1, 1 do
			if not (dx == 0 and dy == 0 and dz == 0) then
				LOOK[#LOOK + 1] = { dx, dy, dz }
			end
		end
	end
end

export type Reveal = { air: { Cell }, solids: { Cell }, truncated: boolean }

-- The caller has just opened (broken, or walked into) cell (sx, sy, sz). Answer two questions:
-- which further cells are now open, and which solid faces are now visible.
--
-- MUTATES NOTHING. `opened` is read-only here; the caller marks the start cell and every
-- returned air cell as opened itself, and builds a Part for every returned solid it does not
-- already have. Keeping the mutation on the caller's side is what makes this testable with a
-- plain table and no bookkeeping.
function Mine.reveal(cfg: any, Ore: any, w: World, opened: { [string]: boolean },
	sx: number, sy: number, sz: number): Reveal
	local budget = cfg.Mine.RevealBudget
	local air: { Cell } = {}
	local solids: { Cell } = {}
	local visited: { [string]: boolean } = { [Mine.key(sx, sy, sz)] = true }
	local queue = { { sx, sy, sz } }
	local head = 1
	local truncated = false

	while head <= #queue do
		local c = queue[head]
		head += 1

		-- Every solid the player could see from this open cell gets a face.
		for _, d in LOOK do
			local nx, ny, nz = c[1] + d[1], c[2] + d[2], c[3] + d[3]
			if Mine.inWorld(cfg, w, nx, ny, nz) then
				local k = Mine.key(nx, ny, nz)
				if not visited[k] and Mine.isSolid(cfg, w, nx, ny, nz) then
					visited[k] = true
					solids[#solids + 1] = Mine.cell(cfg, Ore, w, nx, ny, nz)
				end
			end
		end

		-- And every open cell they could walk into, unless the caller already has it.
		for _, d in WALK do
			local nx, ny, nz = c[1] + d[1], c[2] + d[2], c[3] + d[3]
			if Mine.inWorld(cfg, w, nx, ny, nz) then
				local k = Mine.key(nx, ny, nz)
				if not visited[k] and not Mine.isSolid(cfg, w, nx, ny, nz) then
					visited[k] = true
					if not opened[k] then
						if #air >= budget then
							truncated = true
						else
							air[#air + 1] = Mine.cell(cfg, Ore, w, nx, ny, nz)
							queue[#queue + 1] = { nx, ny, nz }
						end
					end
				end
			end
		end
	end

	return { air = air, solids = solids, truncated = truncated }
end

-- The elevator shaft a rejoining player gets back: their own centre column, down to the depth
-- they had already reached. Their tunnels are not saved (see README) but the shaft that makes
-- the depth reachable again is.
function Mine.column(cfg: any, w: World, toLayer: number): { { x: number, y: number, z: number } }
	local c = Mine.center(cfg)
	local last = math.min(math.max(math.floor(toLayer or 0), 0), w.maxLayer)
	local out = {}
	for y = 1, last do
		out[#out + 1] = { x = c, y = y, z = c }
	end
	return out
end

return Mine
