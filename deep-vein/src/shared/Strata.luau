--!strict
-- Strata.luau — what the rock and the walls look like at a depth. Deep Vein's own half of the
-- environment bands (EnvBands, copied verbatim from +1 Jump, is the game-agnostic half). Pure.
--
-- The progress value is DEPTH: the layer the miner is standing in, read from their own character's
-- height, never from a clock. Everything here takes its dependencies as arguments (Mine, EnvBands),
-- because a bare require("./X") resolves in the luau CLI and is invalid in Roblox.
--
-- Used by the server (the rock colour and material of each cell Part it builds, so everyone looking
-- at a shaft sees the same strata) and by the client (depth, the band, where decorations sit, which
-- cells beside the miner are open). Nothing here reads the cave generator: the client decides
-- "open" from the Parts it can already see, so no decoration can reveal a cell the player has not
-- uncovered. tests/Strata.spec.luau pins every rule.

local Strata = {}

-- Continuous depth, in layers, of a character whose root part is at shaft-local height `rootY`.
-- The server stands a miner in layer y with the root at Mine.floorY(y) + 4, so that reads exactly y.
-- Clamped at 0: standing on the rim above the mouth is the surface, not negative depth.
function Strata.depthAt(cfg: any, rootY: number): number
	local d = (cfg.Env.RootAboveFloor - rootY) / cfg.Mine.CellSize
	if d ~= d or d < 0 then return 0 end
	return d
end

-- The whole layer the miner is NAMED by (chip, cards, which hazards come, the cell they stand in): the
-- layer their ROOT is in, by Mine.layerOfY — exactly the server's minerLayer, so the two cannot disagree.
-- The root is mid-cell for a miner the server placed (floor + 4), a real R15 that settled (floor + 3.0)
-- and a seated one. It used to be read at the feet (root - 3): for a settled R15 that is ON the floor's
-- plane, and a root a hair low read the layer below (resume session 2026-09-24, Strata.spec).
function Strata.layerAt(cfg: any, Mine: any, rootY: number): number
	return Mine.layerOfY(cfg, rootY)
end

-- The look of one stone cell at `layer`: the bands' rock palette blended across the fade (so a stratum
-- boundary is a gradient over `fade` layers), then the per-cell jitter the server always had
-- (floor(unit * 22) - 11 on each channel), and an accent cell (a rust streak, moss) when accentUnit
-- falls under the band's accentChance. Colours are {r, g, b} integers in 0..255; material is the name
-- of an Enum.Material, switching at the middle of the fade.
function Strata.rockLook(cfg: any, EnvBands: any, layer: number, jitterUnit: number, accentUnit: number): any
	local rock = EnvBands.sample(cfg.Env.Bands, layer, "rock")
	local range = cfg.Env.JitterRange or 11
	local j = math.floor(math.clamp(jitterUnit, 0, 0.999999) * (2 * range)) - range
	local accent = type(rock.accentChance) == "number" and accentUnit < rock.accentChance and rock.accent ~= nil
	local base = if accent then rock.accent else rock.color
	local out = {}
	for k = 1, 3 do
		out[k] = math.clamp(math.round(base[k] + j), 0, 255)
	end
	return { color = out, material = rock.material, accent = accent }
end

-- Distance between two {r, g, b} colours. The readability rule in EnvConfig.spec: every ore that can
-- exist in a band stays this far from that band's rock, jitter and accents included.
function Strata.contrast(a: { number }, b: { number }): number
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dr * dr + dg * dg + db * db)
end

-- Horizontal cell of a shaft-local point: the inverse of Mine.localPos on x and z.
function Strata.cellXZ(cfg: any, localX: number, localZ: number): (number, number)
	local c = (cfg.Mine.GridW + 1) / 2
	local s = cfg.Mine.CellSize
	return c + math.round(localX / s), c + math.round(localZ / s)
end

-- The horizontal neighbours of cell (x, y, z) a miner can step into: inside the diggable interior
-- (never through the bedrock ring) and not holding a built rock Part. The reveal builds every solid
-- cell next to an opened one, and the miner's own cell is opened, so "no Part there" means open —
-- from what the client can already see, not from the cave generator. Returns { {x = dx, z = dz} }.
local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
function Strata.openSides(cfg: any, Mine: any, isSolid: (string) -> boolean, x: number, y: number, z: number): { any }
	local gw = cfg.Mine.GridW
	local out = {}
	for _, d in SIDES do
		local nx, nz = x + d[1], z + d[2]
		if nx >= 2 and nx <= gw - 1 and nz >= 2 and nz <= gw - 1 and not isSolid(Mine.key(nx, y, nz)) then
			table.insert(out, { x = d[1], z = d[2] })
		end
	end
	return out
end

-- How many open layers there are straight above cell (x, y, z), counting up from y - 1 and stopping at the
-- first cell holding a built Part, capped at maxLayers (which also means "no ceiling within reach"). The
-- mouth (layer 0) and the sky over it are open. Valid from the Parts the client can see: every cell next
-- to an opened one is revealed, so going up from the miner's own opened cell, a cell with no Part is open.
function Strata.openAbove(cfg: any, Mine: any, isSolid: (string) -> boolean, x: number, y: number, z: number,
	maxLayers: number): number
	local n = 0
	for layer = y - 1, y - maxLayers, -1 do
		if layer < 1 then return maxLayers end
		if isSolid(Mine.key(x, layer, z)) then return n end
		n += 1
	end
	return n
end

-- Shaft-local height of the ceiling over a miner in layer y with `open` open layers above: the bottom face
-- of the first solid cell above.
function Strata.ceilingY(cfg: any, Mine: any, y: number, open: number): number
	return Mine.floorY(cfg, y - open) + cfg.Mine.CellSize
end

-- Where a hazard that drops from ABOVE is DRAWN: the height of its model's centre at plan time a.t. The
-- plan (Hazards) hangs it `height` studs over the aim point and drops it at its own speed, and the hit
-- test uses the plan: nothing here changes where, when or whom it hits. The drawing differs so that the
-- player can SEE it (review 2026-09-24, finding 1):
--   * while it hangs it is in view and never inside the miner: just under a ceiling within reach
--     (a.ceilingY; nil = none), and never lower than a.headTop + half its height. Under a roof too low
--     for both (a one-layer tunnel is 6 studs, a standing avatar 5.3) it pokes out of the roof: a rock
--     working loose, not a rock stuck through the miner's head;
--   * it falls from where it is drawn and passes the plan's aim height (a.targetY) at a.arrive, the
--     plan's own moment, then lands on the floor (a.floorY + half) and lies there.
-- a = { t, hang, arrive, startY, targetY, half, floorY, ceilingY?, headTop }, all heights in one frame.
local MIN_DRAWN_FALL_SPEED = 4 -- studs/s: a degenerate aim above the hang point still falls to the floor
function Strata.dropY(a: any): number
	local hangY = a.startY
	if a.ceilingY ~= nil then
		hangY = math.min(hangY, a.ceilingY - a.half - 0.1)
	end
	hangY = math.max(hangY, a.headTop + a.half)
	if a.t <= a.hang then
		return hangY
	end
	local speed = math.max((hangY - a.targetY) / math.max(a.arrive - a.hang, 1e-3), MIN_DRAWN_FALL_SPEED)
	return math.max(a.floorY + a.half, hangY - speed * (a.t - a.hang))
end

-- The layer whose floor the danger ring lies on (review 2026-09-24, finding 4). While the hazard still
-- follows the miner it is the floor they STAND on: a jump lifts the root into the layer above, and the
-- ring used to leap up with it (and hang in mid-air if the plan locked during the jump). Once the plan
-- locks, the ring stays where it is, wherever the miner goes. `prev` is nil on a new hazard.
function Strata.ringLayer(prev: number?, rootLayer: number, grounded: boolean, locked: boolean): number
	if prev == nil then
		return rootLayer
	end
	if grounded and not locked then
		return rootLayer
	end
	return prev
end

-- The four inner faces of the bedrock ring, shaft-local: a point on the plane (x, z), the normal into
-- the shaft (nx, nz), the axis along the face (ux, uz) and its half-length. Mine.shell's walls, seen
-- from inside.
function Strata.wallFaces(cfg: any): { [string]: any }
	local s = cfg.Mine.CellSize
	local gw = cfg.Mine.GridW
	local c = (gw + 1) / 2
	local inner = (gw - c) * s + s / 2 - s
	local half = (gw - 2) * s / 2
	return {
		N = { name = "N", x = 0, z = -inner, nx = 0, nz = 1, ux = 1, uz = 0, half = half },
		S = { name = "S", x = 0, z = inner, nx = 0, nz = -1, ux = -1, uz = 0, half = half },
		W = { name = "W", x = -inner, z = 0, nx = 1, nz = 0, ux = 0, uz = -1, half = half },
		E = { name = "E", x = inner, z = 0, nx = -1, nz = 0, ux = 0, uz = 1, half = half },
	}
end

local WALLS = { "N", "E", "S", "W" }

-- The decorations on the wall faces of `layer`: { kind, wall, u (along the face, studs), v (offset
-- within the layer, -0.3..0.3 of a cell), scale, roll }. Deterministic in (layer, seed), so walking
-- away and back rebuilds exactly the same wall, and the same for every client. The band that OWNS
-- the layer supplies the kinds; `perLayer` is the expected count. Layer 0 (the mouth room) has none:
-- the surface is dressed by set pieces instead.
function Strata.decorAt(cfg: any, EnvBands: any, layer: number, seed: number): { any }
	local out = {}
	if layer < 1 then return out end
	local bands = cfg.Env.Bands
	local band = bands[EnvBands.indexAt(bands, layer)]
	local d = band.decor
	if d == nil or d.kinds == nil or #d.kinds == 0 then return out end
	local per = d.perLayer or 0
	local n = math.floor(per)
	if EnvBands.hash01(layer, 0, 11, seed) < per - n then n += 1 end
	local face = Strata.wallFaces(cfg)
	local margin = cfg.Env.DecorMargin or 3
	for i = 1, n do
		local function h(k: number): number
			return EnvBands.hash01(layer, i * 16 + k, 29, seed)
		end
		local wall = WALLS[1 + math.floor(h(1) * 4) % 4]
		local half = face[wall].half - margin
		table.insert(out, {
			kind = d.kinds[1 + math.floor(h(2) * #d.kinds) % #d.kinds],
			wall = wall,
			u = (h(3) * 2 - 1) * half,
			v = (h(4) - 0.5) * 0.6,
			scale = 0.8 + 0.4 * h(5),
			roll = h(6),
		})
	end
	return out
end

return Strata
