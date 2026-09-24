-- Spec for Strata: what the rock and the walls look like at a depth. Run: luau tests/Strata.spec.luau
--
-- Deep Vein's environment follows DEPTH, the game's real progress value: the layer the miner stands
-- in, derived from where their character is, never from a clock. This module is the pure,
-- Deep-Vein-specific half of that (EnvBands, copied from +1 Jump, is the generic half):
--   * depth and the named layer from a root part's shaft-local height, on the same arithmetic the
--     server uses to place a miner (Mine.floorY + 4) and to stream the shaft (Mine.layerOfY);
--   * the rock's colour and material at a layer: the band's palette, blended across the band's fade
--     so strata never change with a hard line, with the server's existing per-cell jitter and an
--     occasional accent cell (a rust streak, a moss patch);
--   * which of the four cells beside a miner are open (somewhere to step out of a falling rock's
--     shadow), from the cells the client can SEE, never from the cave generator;
--   * where the decorations sit on the inner faces of the bedrock walls, deterministically.
-- No Roblox anywhere; dependencies (Mine, EnvBands) are arguments.
local Strata = require("../src/shared/Strata")
local Mine = require("../src/shared/Mine")
local EnvBands = require("../src/shared/EnvBands")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- A spec-owned config: the real numbers live in Config and are checked by EnvConfig.spec.
local cfg = {
	WorldSeed = 1,
	Mine = { CellSize = 6, GridW = 9, BaseMaxLayer = 24, LayersPerRebirth = 12, RimCells = 3 },
	Env = {
		RootAboveFloor = 4,
		JitterRange = 11,
		DecorMargin = 3,
		Bands = {
			{ id = "top", from = 0, fade = 0,
				rock = { color = { 110, 80, 50 }, material = "Ground", accent = { 80, 60, 40 }, accentChance = 0.1 },
				decor = { kinds = { "roots" }, perLayer = 0.5 } },
			{ id = "grey", from = 4, fade = 2,
				rock = { color = { 100, 100, 110 }, material = "Slate", accent = { 80, 80, 90 }, accentChance = 0.2 },
				decor = { kinds = { "seam", "pebbles" }, perLayer = 1.0 } },
			{ id = "hot", from = 20, fade = 4,
				rock = { color = { 60, 40, 40 }, material = "Basalt", accent = { 140, 50, 20 }, accentChance = 0.3 } },
		},
	},
}
local bands = cfg.Env.Bands
local S = cfg.Mine.CellSize

--================================================================ depth and layer from a root part

do
	-- The server stands a miner in layer y with their root at Mine.floorY(y) + 4 (standY). Depth and the
	-- named layer must both read y there, at every layer the deepest wall can reach.
	local worst, wrong = 0, 0
	for y = 0, 324 do
		local rootY = Mine.floorY(cfg, y) + 4
		local d = Strata.depthAt(cfg, rootY)
		worst = math.max(worst, math.abs(d - y))
		if Strata.layerAt(cfg, Mine, rootY) ~= y then wrong += 1 end
	end
	truthy(worst < 1e-9, "a miner the server stands in layer y reads depth y (worst error " .. worst .. ")")
	eq(wrong, 0, "…and is NAMED as layer y, at all 325 layers")
	approx(Strata.depthAt(cfg, 40), 0, "standing above the mouth (on the rim, a jump) is depth 0, never negative")
	eq(Strata.layerAt(cfg, Mine, 40), 0, "…and layer 0")
	local prev = -1
	local mono = true
	for i = 0, 2000 do
		local d = Strata.depthAt(cfg, 10 - i * 0.37)
		if d < prev - 1e-12 then mono = false end
		prev = d
	end
	truthy(mono, "depth never decreases as the root goes down (continuous, so blends cannot jump)")
	-- Resume session 2026-09-24: the name used to be read at the FEET (root - 3). A real R15 root settles
	-- HipHeight 2 + half its 2-stud height = 3.0 studs above the floor, so the feet sit ON the floor's
	-- plane and a root a hair low read the layer BELOW: the chip, the fanfare, the hazard kinds and the
	-- critter trail one layer too deep. The name is now the server's own minerLayer arithmetic,
	-- Mine.layerOfY at the ROOT, which is mid-cell for a standing, settled or seated miner.
	local wrongSettled, wrongSeated, wrongServer = 0, 0, 0
	for y = 1, 324 do
		for _, off in { 2.9, 2.95, 2.999, 3, 3.001, 3.05, 3.1 } do
			if Strata.layerAt(cfg, Mine, Mine.floorY(cfg, y) + off) ~= y then wrongSettled += 1 end
		end
		for _, off in { 1.2, 1.6, 2.0 } do
			if Strata.layerAt(cfg, Mine, Mine.floorY(cfg, y) + off) ~= y then wrongSeated += 1 end
		end
		for _, off in { 0.01, 1, 2.5, 3, 4, 5.5, 5.99 } do
			local rootY = Mine.floorY(cfg, y) + off
			if Strata.layerAt(cfg, Mine, rootY) ~= Mine.layerOfY(cfg, rootY) then wrongServer += 1 end
		end
	end
	eq(wrongSettled, 0, "a real R15 root settled 3.0 studs above the floor, a hair high or low, is named its own layer")
	eq(wrongSeated, 0, "…and so is a seated (resting) miner, whose root drops toward the floor")
	eq(wrongServer, 0, "the named layer IS Mine.layerOfY at the root: the server's minerLayer, one arithmetic")
end

--================================================================ the rock at a layer

local function look(layer, j, a)
	return Strata.rockLook(cfg, EnvBands, layer, j, a)
end

do
	local l = look(10, 0.5, 0.99)
	eq(l.material, "Slate", "inside a band the rock has that band's material")
	eq(l.accent, false, "a high accent roll is plain rock")
	eq(l.color[1], 100, "…in exactly the band's colour at the jitter midpoint (r)")
	eq(l.color[3], 110, "(b)")
	local lo = look(10, 0, 0.99)
	local hi = look(10, 0.9999, 0.99)
	eq(lo.color[1], 100 - cfg.Env.JitterRange, "the darkest jitter is -JitterRange (the server's old ±11 stays)")
	eq(hi.color[1], 100 + cfg.Env.JitterRange - 1, "the lightest is +JitterRange - 1 (floor of 22 steps, as before)")
	local acc = look(10, 0.5, 0.05)
	eq(acc.accent, true, "a low accent roll is an accent cell")
	eq(acc.color[1], 80, "…in the band's accent colour")
	eq(acc.material, "Slate", "…and the band's material")
end

do
	-- accent frequency ≈ accentChance
	local n, hits = 4000, 0
	for i = 1, n do
		if look(12, 0.5, (i - 0.5) / n).accent then hits += 1 end
	end
	approx(hits / n, 0.2, "accents turn up at the band's accentChance", 0.002)
end

do
	-- the seam between two bands is a gradient over `fade` layers, never a line
	local c3, c4 = look(2, 0.5, 0.99).color, look(4, 0.5, 0.99).color
	eq(c3[1], 110, "above the fade the rock is still the upper band's")
	eq(c4[1], 100, "at the band's `from` it is the lower band's")
	local mid = look(3, 0.5, 0.99)
	truthy(mid.color[1] > 100 and mid.color[1] < 110, "halfway through the fade it is between the two (" .. mid.color[1] .. ")")
	-- per-layer change across every seam, compared with the jump the bands would make with no fade
	local worstStep, worstJump = 0, 0
	for y = 1, 40 do
		local a, b = look(y - 1, 0.5, 0.99).color, look(y, 0.5, 0.99).color
		local d = Strata.contrast(a, b)
		if d > worstStep then worstStep = d end
	end
	worstJump = Strata.contrast(bands[2].rock.color, bands[3].rock.color)
	truthy(worstStep < worstJump * 0.5,
		string.format("no layer-to-layer colour step is more than half a band's jump (%.1f vs %.1f)", worstStep, worstJump))
	eq(look(1, 0.5, 0.99).material, "Ground", "material: the upper band's before mid-fade")
	eq(look(4, 0.5, 0.99).material, "Slate", "…the lower band's after it (a material cannot be half of each)")
	for y = 0, 60 do
		for _, j in { 0, 0.5, 0.9999 } do
			for _, a in { 0, 0.5, 0.9999 } do
				local c = look(y, j, a).color
				for k = 1, 3 do
					if c[k] < 0 or c[k] > 255 or c[k] ~= math.floor(c[k]) then
						failed += 1
						print("FAIL: colour component out of range / not an integer at layer " .. y)
					end
				end
			end
		end
	end
	passed += 1
end

do
	local a, b = look(33, 0.31, 0.77), look(33, 0.31, 0.77)
	truthy(a.color[1] == b.color[1] and a.color[2] == b.color[2] and a.color[3] == b.color[3] and a.material == b.material,
		"the same cell always looks the same (everybody sees the same strata)")
	approx(Strata.contrast({ 0, 0, 0 }, { 3, 4, 0 }), 5, "contrast is the RGB distance")
	approx(Strata.contrast({ 10, 20, 30 }, { 10, 20, 30 }), 0, "…zero for equal colours")
end

--================================================================ cells beside the miner

do
	for x = 1, 9 do
		local lp = Mine.localPos(cfg, x, 5, 7)
		local cx, cz = Strata.cellXZ(cfg, lp.x, lp.z)
		eq(cx, x, "cellXZ inverts Mine.localPos (x = " .. x .. ")")
		eq(cz, 7, "(z)")
	end
	local cx, cz = Strata.cellXZ(cfg, 2.9, -2.9)
	eq(cx, 5, "a root 2.9 studs off the centre is still in the centre cell (x)")
	eq(cz, 5, "(z)")
end

do
	local solid = {}
	local function isSolid(k) return solid[k] == true end
	-- a one-cell pit: all four sides are built rock
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		solid[Mine.key(5 + d[1], 10, 5 + d[2])] = true
	end
	eq(#Strata.openSides(cfg, Mine, isSolid, 5, 10, 5), 0, "a miner in a one-cell pit has nowhere to step")
	solid[Mine.key(6, 10, 5)] = nil
	local open = Strata.openSides(cfg, Mine, isSolid, 5, 10, 5)
	eq(#open, 1, "dig out one side and there is one way out")
	eq(open[1].x, 1, "…toward +x")
	eq(open[1].z, 0, "…and not along z")
	-- against the ring: the bedrock wall is never a way out, even though it has no cell Part
	local edge = Strata.openSides(cfg, Mine, function() return false end, 2, 10, 8)
	for _, o in edge do
		truthy(2 + o.x >= 2 and 2 + o.x <= 8 and 8 + o.z >= 2 and 8 + o.z <= 8,
			"a side through the bedrock ring is never offered")
	end
	eq(#edge, 2, "a corner cell with open neighbours has exactly its two inner sides")
end

--================================================================ the ceiling over a miner
-- Resume session 2026-09-24. A falling rock hangs `height` (20-22) studs over the miner, and the Hazards
-- plan keeps it there. Under an open column that is in plain sight; under a tunnel's ceiling it is inside
-- the rock, and nothing of it shows until the last instant of its fall. The client draws it just under
-- the real ceiling instead, which it finds from the cells it can see: every cell next to an opened one
-- is revealed, so walking up from the miner's own (opened) cell, a cell without a Part is open air and
-- the first cell with one is the ceiling.

do
	local solid = {}
	local function isSolid(k) return solid[k] == true end
	eq(Strata.openAbove(cfg, Mine, isSolid, 5, 30, 5, 4), 4, "an open column: no ceiling within reach (capped at maxLayers)")
	solid[Mine.key(5, 29, 5)] = true
	eq(Strata.openAbove(cfg, Mine, isSolid, 5, 30, 5, 4), 0, "rock straight overhead: no open layer above")
	solid[Mine.key(5, 29, 5)] = nil
	solid[Mine.key(5, 27, 5)] = true
	eq(Strata.openAbove(cfg, Mine, isSolid, 5, 30, 5, 4), 2, "two open layers, then rock")
	solid[Mine.key(6, 28, 5)] = true
	eq(Strata.openAbove(cfg, Mine, isSolid, 5, 30, 5, 4), 2, "rock beside the column is not a ceiling")
	eq(Strata.openAbove(cfg, Mine, isSolid, 5, 2, 5, 4), 4, "the mouth (layer 0) and the sky over it are open: no ceiling")
	-- the ceiling's height, shaft-local: the bottom face of the first solid cell above
	approx(Strata.ceilingY(cfg, Mine, 30, 0), Mine.floorY(cfg, 30) + S, "rock straight overhead: the ceiling is one cell above the floor")
	approx(Strata.ceilingY(cfg, Mine, 30, 2), Mine.floorY(cfg, 30) + 3 * S, "two open layers: three cells above the floor")
end

--================================================================ where a falling hazard is DRAWN
-- Review 2026-09-24, finding 1. Drawn "just under the ceiling", a 2-3.8-stud rock in a one-layer tunnel
-- (a 6-stud ceiling over a 5.3-stud avatar) was drawn THROUGH the miner's head for its whole warning and
-- then dropped in one frame. Strata.dropY is the drawing, never the plan: it hangs the model where it is
-- seen and never inside the miner (poking out of a roof too low for both), falls from there so that it
-- passes the plan's aim height at the plan's own moment (the hit), and lands on the floor.

do
	local F = Mine.floorY(cfg, 30)
	local HEAD = F + 5.3 -- the top of a standing avatar's head
	local hang, arrive = 2.6, 3.2 -- a rock: telegraph 3.2, fall 0.6
	local target = F + 3 -- a settled R15's root
	local function at(t, half, ceiling, targetY)
		return Strata.dropY({ t = t, hang = hang, arrive = arrive, startY = (targetY or target) + 22, targetY = targetY or target,
			half = half, floorY = F, ceilingY = ceiling, headTop = HEAD })
	end
	-- an open column: exactly the plan's own height while it hangs, and through the root at the hit
	approx(at(0, 1.3, nil), target + 22, "open column: it hangs at the plan's height")
	approx(at(hang, 1.3, nil), target + 22, "…until the plan lets go")
	approx(at(arrive, 1.3, nil), target, "…and passes the miner's root at the moment the plan does (the hit)", 1e-6)
	approx(at(arrive + 0.5, 1.3, nil), F + 1.3, "…then lands on the floor and lies there, never sinking through it")
	-- a one-layer tunnel: the roof is 6 studs up, the avatar 5.3
	local ceil1 = F + S
	local yHang = at(1.0, 1.3, ceil1)
	truthy(yHang - 1.3 >= HEAD - 1e-9, string.format(
		"a tunnel: while it hangs its bottom never dips into the miner's head (bottom %.2f, head %.2f over the floor)", yHang - 1.3 - F, HEAD - F))
	truthy(ceil1 - (yHang - 1.3) >= 0.5, string.format(
		"…and at least half a stud of it pokes out of the roof, where it can be seen (%.2f studs)", ceil1 - (yHang - 1.3)))
	local stal = at(1.0, 1.9, ceil1)
	truthy(stal - 1.9 >= HEAD - 1e-9 and ceil1 - (stal - 1.9) >= 0.5, string.format(
		"…a 3.8-stud stalactite too (bottom %.2f)", stal - 1.9 - F))
	approx(at(arrive, 1.3, ceil1), target, "…falls from the roof and passes the root at the plan's moment", 1e-6)
	truthy(at(hang, 1.3, ceil1) - at(arrive, 1.3, ceil1) >= 3, string.format(
		"…a fall you can see: %.2f studs in the plan's %.1f s, not one frame", at(hang, 1.3, ceil1) - at(arrive, 1.3, ceil1), arrive - hang))
	approx(at(arrive + 1, 1.3, ceil1), F + 1.3, "…and lands on the floor")
	local mono, prev = true, math.huge
	for i = 0, 500 do
		local y = at(i * 0.01, 1.3, ceil1)
		if y > prev + 1e-9 then mono = false end
		prev = y
	end
	truthy(mono, "…it only ever moves down")
	-- a two-layer room: room for the whole rock between the head and the roof
	local ceil2 = F + 2 * S
	local y2 = at(1.0, 1.3, ceil2)
	truthy(y2 + 1.3 <= ceil2 + 1e-9 and y2 - 1.3 >= HEAD - 1e-9, string.format(
		"a two-layer room: the whole rock hangs between the head and the roof (%.2f..%.2f)", y2 - 1.3 - F, y2 + 1.3 - F))
	-- a roof above the plan's own height changes nothing
	approx(at(1.0, 1.3, F + 60), target + 22, "a roof higher than the plan's hang point changes nothing")
	-- degenerate: an aim point above where it is drawn (a mid-air lock) still falls, to the floor
	local odd = at(arrive + 3, 1.3, ceil1, F + 9)
	approx(odd, F + 1.3, "an aim above the drawn hang point still ends on the floor, never floating")
end

--================================================================ where the ring lies
-- Review 2026-09-24, finding 4. The ring was drawn on the floor of the ROOT's layer. A jump lifts the root
-- into the layer above, so the "shadow" leapt 6 studs into the air, and stayed there if the plan locked
-- mid-jump. The ring lies on the floor the miner last STOOD on while the hazard still follows them, and
-- once it locks it stays put, wherever the miner goes.

do
	eq(Strata.ringLayer(nil, 30, true, false), 30, "a new hazard: the ring starts on the floor the miner stands on")
	eq(Strata.ringLayer(nil, 29, false, false), 29, "…or wherever the root is, if there is nothing better yet")
	eq(Strata.ringLayer(30, 31, true, false), 31, "while it follows the miner, the ring follows the floor they stand on")
	eq(Strata.ringLayer(30, 29, false, false), 30, "a jump (root in the layer above, off the ground) does not lift the ring")
	eq(Strata.ringLayer(30, 29, false, true), 30, "…nor a jump across the lock")
	eq(Strata.ringLayer(30, 31, true, true), 30, "once locked it stays, even when the miner steps down into the cell below")
end

--================================================================ the inner faces of the bedrock walls

do
	local w = Mine.world(cfg, 0)
	local shell = Mine.shell(cfg, w)
	local faces = Strata.wallFaces(cfg)
	local count = 0
	for _, f in faces do
		count += 1
		-- the face plane is the inner face of one slab: a point just inside the plane is in a slab,
		-- a point just outside (into the shaft) is not
		local inside = { x = f.x - f.nx * 0.01, z = f.z - f.nz * 0.01 }
		local outside = { x = f.x + f.nx * 0.01, z = f.z + f.nz * 0.01 }
		local function inSlab(p)
			for _, s in shell do
				if s.kind == "wall" and math.abs(p.x - s.x) <= s.sx / 2 and math.abs(p.z - s.z) <= s.sz / 2 then
					return true
				end
			end
			return false
		end
		truthy(inSlab(inside), "face " .. f.name .. " sits on a bedrock wall")
		truthy(not inSlab(outside), "…and its normal points into the shaft")
		approx(f.half, (cfg.Mine.GridW - 2) * S / 2, "…and spans the diggable interior")
	end
	eq(count, 4, "four inner wall faces")
end

--================================================================ decorations on the walls

do
	local a = Strata.decorAt(cfg, EnvBands, 12, 777)
	local b = Strata.decorAt(cfg, EnvBands, 12, 777)
	eq(#a, #b, "decor is deterministic: same layer, same seed, same list")
	for i = 1, #a do
		truthy(a[i].kind == b[i].kind and a[i].wall == b[i].wall and a[i].u == b[i].u, "…item " .. i .. " identical")
	end
	local total, perBand, badKind, outside = 0, {}, 0, 0
	local faces = Strata.wallFaces(cfg)
	for y = 1, 400 do
		for _, item in Strata.decorAt(cfg, EnvBands, y, 777) do
			total += 1
			local bi = EnvBands.indexAt(bands, y)
			perBand[bi] = (perBand[bi] or 0) + 1
			local kinds = (bands[bi].decor or {}).kinds or {}
			if not table.find(kinds, item.kind) then badKind += 1 end
			local f = faces[item.wall]
			if f == nil or math.abs(item.u) > f.half - cfg.Env.DecorMargin + 1e-9 or item.v < -0.5 or item.v > 0.5 then
				outside += 1
			end
		end
	end
	eq(badKind, 0, "every decoration belongs to the band that owns its layer")
	eq(outside, 0, "every decoration sits on a wall face, DecorMargin clear of the corners, within its layer")
	eq(perBand[3], nil, "a band with no decor list has none")
	local greyLayers = 20 - 4
	local rate = (perBand[2] or 0) / greyLayers
	truthy(rate > 0.6 and rate < 1.4, string.format("decor density follows perLayer (%.2f per layer for 1.0)", rate))
	eq(#Strata.decorAt(cfg, EnvBands, 0, 777), 0, "layer 0 (the mouth room) has no wall decor: the surface has set pieces")
	local other = Strata.decorAt(cfg, EnvBands, 12, 778)
	local same = #other == #a
	if same then
		for i = 1, #a do
			if other[i].u ~= a[i].u or other[i].wall ~= a[i].wall then same = false end
		end
	end
	truthy(not same or #a == 0, "a different seed lays the walls out differently")
end

print(string.format("Strata: %d passed, %d failed", passed, failed))
assert(failed == 0, "Strata tests failed")
