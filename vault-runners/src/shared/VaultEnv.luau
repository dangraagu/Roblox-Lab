--!strict
-- VaultEnv.luau — where in the vault the player is, and what the environment may do about it. PURE.
--
-- The vault-specific half of the eye candy (EYECANDY.md). The game-agnostic half — band blending,
-- the hazard scheduler, rest — is EnvBands / Hazards / Rest, copied from +1 Jump's template.
--
--   * DEPTH is the progress value the whole environment follows: the floor of the run the SERVER
--     started, plus how deep that tier's vault is buried (Config.Env.TierDepth). It never comes from
--     a clock, and the client only ever learns it from the run's own "start" event.
--   * A ceiling drop may land only where it cannot touch what the countdown prices: never in the
--     climb shaft (the obby's pads must stay readable), never near the hole in the floor above a
--     shaft (a knock must never send anyone back down a storey), never in a run's first seconds,
--     never in its last seconds before the seal, never with the collapse close behind.
--   * Decoration is placed from (storey, cell, floor seed) ONLY. It never reads the maze, the route
--     or the gems, so a lamp cannot tell a player which corridor is the dead end.
--
-- cfg + plain tables in, plain values out. Like every module in src/shared it requires NOTHING:
-- `model` is exactly what VaultFloor.build returned.

local VaultEnv = {}

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

--================================================================ depth

-- How deep the vault of (tier, floor) is. Unknown tiers read as the first and floors below 1 as
-- floor 1, so a malformed remote can only ever show the shallowest band.
function VaultEnv.depth(cfg: any, tierIndex: number, floor: number): number
	local d = cfg.Env.TierDepth
	local base = d[tierIndex]
	if type(base) ~= "number" then base = d[1] end
	local f = if type(floor) == "number" and floor == floor then math.max(1, math.floor(floor)) else 1
	return base + f
end

-- The deepest floor this player has CLEARED, as a depth, from the per-tier NEXT-floor numbers the
-- server already pushes in its state (floors[t] = the floor they will play next in tier t).
-- 0 when nothing is cleared. Keys may be strings after a JSON round trip.
function VaultEnv.deepestCleared(cfg: any, floors: any): number
	if type(floors) ~= "table" then return 0 end
	local best = 0
	for t = 1, #cfg.Tiers do
		local f = floors[t]
		if f == nil then f = floors[tostring(t)] end
		f = tonumber(f)
		if f ~= nil and f >= 2 then
			best = math.max(best, cfg.Env.TierDepth[t] + math.floor(f) - 1)
		end
	end
	return best
end

--================================================================ where the player is

-- `pos` is a VAULT-LOCAL root position ({x, y, z}: world minus the vault origin).
-- storey: the storey whose floor the feet are over (clamped into the vault);
-- fx, fy: the fine-grid column and row (the maze grid VaultFloor builds walls from);
-- onFloor: the feet are on that storey's floor (not on a pad, not in the air);
-- inside: within the vault's footprint.
function VaultEnv.locate(cfg: any, model: any, pos: any): any
	local S, H = model.cellSize, model.storeyHeight
	local feet = pos.y - cfg.Run.RunnerRootHeight
	local storey = clamp(math.floor((feet + 1) / H), 0, model.storeys - 1)
	local fx = math.floor(pos.x / S + (model.gCols - 1) / 2 + 0.5)
	local fy = math.floor(pos.z / S + (model.gRows - 1) / 2 + 0.5)
	return {
		storey = storey,
		fx = fx,
		fy = fy,
		feet = feet,
		onFloor = math.abs(feet - storey * H) <= 1,
		inside = math.abs(pos.x) <= model.footprint.w / 2 and math.abs(pos.z) <= model.footprint.d / 2,
	}
end

local function cheb(ax: number, ay: number, bx: number, by: number): number
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- In the climb shaft: the stairwell cell of the storey the feet are over (every pad sits inside
-- it), or the hole's column above it (the top pad is flush with the next storey's floor, so a
-- runner arriving on it reads as standing on that storey, in its entry cell).
function VaultEnv.inShaft(cfg: any, model: any, pos: any): boolean
	local loc = VaultEnv.locate(cfg, model, pos)
	local ex = model.exitCells[loc.storey + 1]
	if ex and loc.fx == 2 * ex.cx + 1 and loc.fy == 2 * ex.cy + 1 then return true end
	if loc.storey > 0 then
		local en = model.entryCells[loc.storey + 1]
		if en and loc.fx == 2 * en.cx + 1 and loc.fy == 2 * en.cy + 1 then return true end
	end
	return false
end

-- May a ceiling drop start on this runner now? (ok, reason). `run` = { elapsed, timeLeft, danger }.
-- Reasons: "norun", "outside", "floor", "shaft", "hole", "grace", "seal", "collapse".
function VaultEnv.hazardEligible(cfg: any, model: any, pos: any, run: any): (boolean, string?)
	if type(run) ~= "table" or model == nil then return false, "norun" end
	local H = cfg.Hazards
	local loc = VaultEnv.locate(cfg, model, pos)
	if not loc.inside then return false, "outside" end
	if not loc.onFloor then return false, "floor" end
	local margin = H.ShaftMarginCells
	local ex = model.exitCells[loc.storey + 1]
	if cheb(loc.fx, loc.fy, 2 * ex.cx + 1, 2 * ex.cy + 1) < margin then return false, "shaft" end
	local en = model.entryCells[loc.storey + 1]
	if cheb(loc.fx, loc.fy, 2 * en.cx + 1, 2 * en.cy + 1) < margin then return false, "hole" end
	if (run.elapsed or 0) < H.GraceSeconds then return false, "grace" end
	if (run.timeLeft or 0) < H.QuietBeforeSealSeconds then return false, "seal" end
	if (run.danger or 0) > H.MaxDanger then return false, "collapse" end
	return true, nil
end

--================================================================ the collapse, as the runner feels it

-- 0 while the kill plane is DangerStuds or more below the height at which it would catch this
-- runner (RunState.caught: root <= plane + killMargin), rising to 1 at that height. Both heights are
-- vault-local. Read from the plane the server actually moves, never from a timer.
function VaultEnv.danger(cfg: any, model: any, planeY: number, rootY: number): number
	local gap = rootY - (planeY + model.killMargin)
	local span = cfg.Env.DangerStuds
	if span <= 0 then return if gap <= 0 then 1 else 0 end
	return 1 - clamp(gap / span, 0, 1)
end

--================================================================ decoration sites

-- Deterministic [0, 1) from integers (the same arithmetic as EnvBands.hash01, kept here so this
-- module requires nothing). Intermediates stay under 2^53.
local function hash01(a: number, b: number, c: number, seed: number): number
	local h = (seed % 2147483647 + 2147483647) % 2147483647
	for _, x0 in { a, b, c } do
		local x = (math.floor(x0) % 2147483647 + 2147483647) % 2147483647
		h = (h * 31 + x + 7919) % 2147483647
		h = (h * 48271) % 2147483647
		h = (h * 16807 + 12345) % 2147483647
	end
	return h / 2147483647
end

-- Maze cells of `storey` that get a ceiling prop, each with a second roll the art uses to pick a
-- band while two bands blend. A function of (cells, storey, seed, density) ONLY: the walls, the
-- route and the gems are never read, so two different mazes of one size hang identical props and
-- no lamp marks a dead end. The shaft cell and the hole cell are skipped — both are fixed corners
-- of every storey, not part of the route.
function VaultEnv.propSites(model: any, storey: number, seed: number, density: number): { any }
	local out = {}
	if density <= 0 then return out end
	local en, ex = model.entryCells[storey + 1], model.exitCells[storey + 1]
	local s = seed % 1000000007
	for cy = 0, model.cells - 1 do
		for cx = 0, model.cells - 1 do
			local skip = (en and cx == en.cx and cy == en.cy) or (ex and cx == ex.cx and cy == ex.cy)
			if not skip then
				local roll = hash01(cx, cy, storey, s)
				if roll < density then
					out[#out + 1] = { cx = cx, cy = cy, roll = hash01(cy, cx, storey + 97, s) }
				end
			end
		end
	end
	return out
end

--================================================================ readability

-- WCAG contrast ratio between two {r, g, b} (0..255) colours; 1 (same) .. 21 (black on white).
local function lum(c: any): number
	local function ch(x: number): number
		local v = x / 255
		return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	local r, g, b = c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0
	return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end

function VaultEnv.contrast(a: any, b: any): number
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- THE PAD COLOUR IS CHOSEN, NOT BLENDED. Where two bands blend (a fade floor), walls and floors lerp
-- between the two palettes — and a lerped pad can land on the lerped floor: the reactor's cyan pad
-- over the frozen vault's white floor meet at a grey-blue on grey, 1.2:1, a shaft nobody can read.
-- So the pad is whichever candidate stands out most against the floor it will be seen over, and when
-- none reaches `minContrast`, plain black or white, whichever reads.
function VaultEnv.readablePad(floor: any, candidates: { any }, minContrast: number): any
	local best, bestC = nil, -1
	for _, c in candidates do
		local k = VaultEnv.contrast(c, floor)
		if k > bestC then best, bestC = c, k end
	end
	if best ~= nil and bestC >= minContrast then return best end
	local white, black = { 245, 245, 245 }, { 16, 16, 16 }
	if VaultEnv.contrast(white, floor) >= VaultEnv.contrast(black, floor) then return white end
	return black
end

local function lerp3(a: any, b: any, t: number): { number }
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- The colours the client paints on the vault at `depth` (EnvBands is passed in: this module
-- requires nothing). Walls, accents and glows BLEND between the two bands of a fade floor; the
-- FLOOR is the dominant band's own floor (a lerp between a dark and a light floor passes through a
-- mid grey no pad colour can stand out on); the PAD is chosen by VaultEnv.readablePad against that
-- floor. Every colour is a fresh {r, g, b} array.
function VaultEnv.palette(cfg: any, EnvBands: any, depth: number): any
	local bands = cfg.Env.Bands
	local i, j, t = EnvBands.locate(bands, depth)
	local a, b = bands[i].palette, bands[j].palette
	local dominant = if t < 0.5 then a else b
	local floor = { dominant.floor[1], dominant.floor[2], dominant.floor[3] }
	return {
		wall = lerp3(a.wall, b.wall, t),
		floor = floor,
		pad = table.clone(VaultEnv.readablePad(floor, { a.pad, b.pad }, cfg.Env.MinPadContrast)),
		accent = lerp3(a.accent, b.accent, t),
		glow = lerp3(a.glow, b.glow, t),
		crack = lerp3(a.crack, b.crack, t),
		wallReflect = (a.wallReflect or 0) + ((b.wallReflect or 0) - (a.wallReflect or 0)) * t,
		band = i, next = j, t = t,
	}
end

-- A pad `progress` (0..1) of the way through its crumble: pulled toward the palette's crack colour by
-- Env.CrackBlend at progress 1. tests/EnvConfig.spec.luau holds it visible against the floor.
function VaultEnv.crackedPad(cfg: any, pal: any, progress: number): { number }
	local k = math.clamp(progress, 0, 1) * cfg.Env.CrackBlend
	return lerp3(pal.pad, pal.crack, k)
end

--================================================================ the pad's look follows the server's pad

-- WHAT A SHAFT PAD LOOKS LIKE, FROM WHAT THIS CLIENT CAN SEE. The server owns the pad: it drops it
-- CrumbleSeconds after its TRUSTED position (Trace) first stood on it, on its own tick, and the drop
-- replicates back — so it goes a beat, plus ping, after the client's own landing says it should.
-- The first cut ran the crack on the client's clock alone and ended it at CrumbleSeconds, and the pad
-- then read WHOLE (or flashed "it's back") for 0.07-0.25 s plus ping before it fell: "safe", at the
-- last moment a jump would still have saved the runner (EYECANDY.md §12).
--
--   * the crack starts when the runner first stands on the pad since the server last put it back;
--   * it spreads over CrumbleSeconds and is then HELD at full until the server drops the pad —
--     for as long as the runner still stands on it (the server will count that stand once its
--     trusted position arrives), and for Env.CrackHoldSeconds past the crumble once they have left
--     (a pad only brushed on the way past may never have been counted, and then it never drops);
--   * nothing is drawn on a pad the server says is gone;
--   * a pad that comes back is a FRESH pad and flashes for Env.PadFlashSeconds — unless the runner is
--     on it, and then it is cracking, which cancels the flash for good (a flash that resumed after a
--     crack would say "it's back" about a pad that never went).
--
-- `st` is this pad's own record (a table the caller owns and keeps), `standing` = the runner is on it
-- now (geometry only), `gone` = the server has dropped it, `now` = seconds. Returns "whole",
-- "crack" + its progress 0..1, "flash" + what is left of it 1..0, or "gone".
function VaultEnv.padLook(cfg: any, st: any, standing: boolean, gone: boolean, now: number): (string, number?)
	if gone then
		st.gone = true
		return "gone", nil
	end
	local E = cfg.Env
	if st.gone then
		st.gone = false
		st.at = nil
		st.flashUntil = now + E.PadFlashSeconds
	end
	local crumble = cfg.Ascent.CrumbleSeconds
	if st.at ~= nil and not standing and now - st.at >= crumble + E.CrackHoldSeconds then
		st.at = nil
	end
	if st.at == nil and standing then st.at = now end
	if st.at ~= nil then
		st.flashUntil = nil
		if crumble <= 0 then return "crack", 1 end
		return "crack", clamp((now - st.at) / crumble, 0, 1)
	end
	if st.flashUntil ~= nil and now < st.flashUntil and E.PadFlashSeconds > 0 then
		return "flash", (st.flashUntil - now) / E.PadFlashSeconds
	end
	st.flashUntil = nil
	return "whole", nil
end

--================================================================ gems stay findable

-- How well colour `c` reads over `floor` AND in front of `wall`, as a share of the bars: >= 1 reads.
local function gemScore(c: any, floor: any, wall: any, minFloor: number, minWall: number): number
	return math.min(VaultEnv.contrast(c, floor) / minFloor, VaultEnv.contrast(c, wall) / minWall)
end

-- A GEM KEEPS ITS TIER'S COLOUR WHERE THAT STILL READS. The client repaints walls and floors per
-- stratum, and a gem that kept the tier's colour regardless read 1.10:1 on the Frozen Vault's ice.
-- So: the tier's colour if it stands out `minFloor`:1 against the floor and `minWall`:1 against the
-- wall; else the candidate (the stratum's own gem colours) that reads best; else black or white,
-- whichever reads better. Returns one of the given tables, or a fresh fallback.
function VaultEnv.readableGem(tierGem: any, floor: any, wall: any, candidates: { any }, minFloor: number, minWall: number): any
	if gemScore(tierGem, floor, wall, minFloor, minWall) >= 1 then return tierGem end
	local best, bestS = nil, -1
	for _, c in candidates do
		local s = gemScore(c, floor, wall, minFloor, minWall)
		if s > bestS then best, bestS = c, s end
	end
	if best ~= nil and bestS >= 1 then return best end
	local white, black = { 245, 245, 245 }, { 16, 16, 16 }
	if gemScore(white, floor, wall, minFloor, minWall) >= gemScore(black, floor, wall, minFloor, minWall) then return white end
	return black
end

-- The colour the client paints on the gems (and the exit pad) of tier `tierIndex` under palette
-- `pal` (VaultEnv.palette): the two blending bands' own `palette.gem` are the candidates. A fresh
-- {r, g, b} array.
function VaultEnv.gem(cfg: any, pal: any, tierIndex: number): { number }
	local g = cfg.Tiers[tierIndex].gemColor
	local own = { g.r, g.g, g.b }
	local bands = cfg.Env.Bands
	local candidates = {}
	for _, id in { pal.band, pal.next } do
		local c = bands[id] and bands[id].palette and bands[id].palette.gem
		if c then table.insert(candidates, c) end
	end
	local chosen = VaultEnv.readableGem(own, pal.floor, pal.wall, candidates, cfg.Env.MinGemContrast, cfg.Env.MinGemWallContrast)
	return { chosen[1], chosen[2], chosen[3] }
end

--================================================================ the drop's ring stays visible

-- A disc of `color` drawn at `transparency` over `floor`, as the eye gets it.
function VaultEnv.ringOver(color: any, transparency: number, floor: any): { number }
	local a = 1 - transparency
	return {
		color[1] * a + floor[1] * transparency,
		color[2] * a + floor[2] * transparency,
		color[3] * a + floor[3] * transparency,
	}
end

-- THE RING IS THE DANGER ZONE, so it must be seen: the first candidate ({ color, transparency }, in
-- order of preference) that stands out `minContrast`:1 against the floor through its own
-- transparency; when none does, the one that reads best. Returns one of the candidates.
function VaultEnv.readableRing(floor: any, candidates: { any }, minContrast: number): any
	local best, bestC = candidates[1], -1
	for _, c in candidates do
		local k = VaultEnv.contrast(VaultEnv.ringOver(c.color, c.transparency, floor), floor)
		if k >= minContrast then return c end
		if k > bestC then best, bestC = c, k end
	end
	return best
end

-- The ring a drop draws over `floor`: Env.RingFollow while it follows the runner, Env.RingLock once
-- it has locked.
function VaultEnv.ring(cfg: any, floor: any, locked: boolean): any
	local E = cfg.Env
	return VaultEnv.readableRing(floor, if locked then E.RingLock else E.RingFollow, E.MinRingContrast)
end

return VaultEnv
