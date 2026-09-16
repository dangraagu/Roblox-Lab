--!strict
-- VaultFloor.luau — selve hvelvet, som REN geometri.
--
-- Takes cfg + a floor spec + the MazeGen and Rng MODULES as arguments and returns plain tables.
-- It touches no Roblox global — not a service, not a datatype, not even Vector3 — so the whole
-- vault can be measured in the luau CLI with no engine present, and the server is left owning
-- nothing but Instance.new. A bare `require("./MazeGen")` resolves in the CLI and is INVALID in
-- Roblox; that is why nothing here requires anything.
--
-- THE RE-SKIN. labyrint-spill's shipped maze generator is copied in verbatim and asked for one
-- thing: a grid. This file stacks `storeys` of those grids into a vertical vault —
--
--   * storey s's walkable floor top is at y = s * StoreyHeight;
--   * walls run from there to the underside of the floor above (WallHeight is DERIVED, so a
--     gap band between storeys cannot be introduced by editing one number);
--   * you enter storey s at one corner cell and leave from the OPPOSITE one, and the parity
--     alternates, so storey s's exit IS storey s+1's entry — the stair, the hole in the floor
--     above, and the arrival cell are the same column by construction, not by coincidence;
--   * the floor above that column is built as four rectangles around a one-cell hole. The first
--     cut of this file used one solid slab per storey, and the spec's very first run said
--     "storey 1 floor covers its own entry hole": a beautiful vault, full of gems, that no
--     player could ever climb out of;
--   * the collapse is one kill plane sweeping from below storey 0 to above the top floor, and
--     one seal descending onto the exit. Both are pure numbers here; the server moves them.
--
-- Wall cells are RUN-LENGTH MERGED along X. That is worth roughly half the parts on a big Gold
-- floor, and tests/VaultFloor.spec.luau checks the merge cell-by-cell in both directions:
-- every wall cell covered exactly once, no open cell covered at all, and every wall edge landing
-- exactly on a grid boundary.

local VaultFloor = {}

local STOREY_SALT = 6151
local GEM_SALT = 104729

local function v3(x: number, y: number, z: number) return { x = x, y = y, z = z } end

function VaultFloor.storeySeed(spec: any, storey: number): number
	return spec.seed + storey * STOREY_SALT
end

function VaultFloor.build(cfg: any, spec: any, MazeGen: any, Rng: any): any
	local V = cfg.Vault
	local tier = cfg.Tiers[spec.tier]
	local S = V.CellSize
	local cells = spec.cells
	local storeys = spec.storeys
	local gCols, gRows = 2 * cells + 1, 2 * cells + 1
	local storeyHeight = V.StoreyHeight
	local floorT = V.FloorThickness
	local wallHeight = storeyHeight - floorT
	local halfC, halfR = (gCols - 1) / 2, (gRows - 1) / 2
	local footW, footD = gCols * S, gRows * S

	local function lx(fx: number) return (fx - halfC) * S end
	local function lz(fy: number) return (fy - halfR) * S end
	local function cellFine(cx: number, cy: number) return 2 * cx + 1, 2 * cy + 1 end

	local function entryCell(s: number)
		if s % 2 == 0 then return { cx = 0, cy = 0 } end
		return { cx = cells - 1, cy = cells - 1 }
	end
	local function exitCell(s: number)
		if s % 2 == 0 then return { cx = cells - 1, cy = cells - 1 } end
		return { cx = 0, cy = 0 }
	end

	local parts = {}
	local function block(o)
		local p = {
			name = o.name, group = o.group, storey = o.storey,
			size = o.size, position = o.position, orientation = v3(0, 0, 0),
			material = o.material, color = o.color,
			transparency = o.transparency or 0, reflectance = o.reflectance or 0,
			collide = o.collide == true, query = o.query == true,
			castShadow = o.collide == true,
		}
		parts[#parts + 1] = p
		return p
	end

	local grids, entryCells, exitCells = {}, {}, {}
	local gems = {}
	local shafts = {}

	for s = 0, storeys - 1 do
		local baseY = s * storeyHeight
		local rng = Rng.new(VaultFloor.storeySeed(spec, s))
		local grid = MazeGen.generate(cells, cells, rng)
		grids[s + 1] = grid
		entryCells[s + 1] = entryCell(s)
		exitCells[s + 1] = exitCell(s)

		-- Storey 0 stands on solid ground. Every storey above it is entered from below, through
		-- a one-cell hole over the stair, so its floor is four rectangles around that hole.
		local floorY = baseY - floorT / 2
		if s == 0 then
			block({
				name = "Floor_0", group = "floor", storey = 0,
				size = v3(footW, floorT, footD), position = v3(0, floorY, 0),
				material = "Slate", color = tier.floorColor, collide = true, query = true,
			})
		else
			local en = entryCell(s)
			local hfx, hfy = cellFine(en.cx, en.cy)
			local hx0, hx1 = lx(hfx) - S / 2, lx(hfx) + S / 2
			local hz0, hz1 = lz(hfy) - S / 2, lz(hfy) + S / 2
			local X0, X1 = -footW / 2, footW / 2
			local Z0, Z1 = -footD / 2, footD / 2
			local rects = {
				{ n = "N", x0 = X0, x1 = X1, z0 = Z0, z1 = hz0 },
				{ n = "S", x0 = X0, x1 = X1, z0 = hz1, z1 = Z1 },
				{ n = "W", x0 = X0, x1 = hx0, z0 = hz0, z1 = hz1 },
				{ n = "E", x0 = hx1, x1 = X1, z0 = hz0, z1 = hz1 },
			}
			for _, r in ipairs(rects) do
				local w, d = r.x1 - r.x0, r.z1 - r.z0
				-- The hole is always at a corner MAZE cell, which is fine cell 1 or gCols-2 —
				-- never on the outer ring — so all four rectangles have positive extent. The
				-- guard is here anyway: a zero-size Part is a Roblox error, not a no-op.
				if w > 0 and d > 0 then
					block({
						name = "Floor_" .. s .. "_" .. r.n, group = "floor", storey = s,
						size = v3(w, floorT, d),
						position = v3((r.x0 + r.x1) / 2, floorY, (r.z0 + r.z1) / 2),
						material = "Slate", color = tier.floorColor, collide = true, query = true,
					})
				end
			end
		end

		for fy = 0, gRows - 1 do
			local fx = 0
			while fx < gCols do
				if grid[fy][fx] then
					local a = fx
					while fx + 1 < gCols and grid[fy][fx + 1] do fx += 1 end
					local b = fx
					block({
						name = string.format("Wall_%d_%d_%d", s, fy, a), group = "wall", storey = s,
						size = v3((b - a + 1) * S, wallHeight, S),
						position = v3((lx(a) + lx(b)) / 2, baseY + wallHeight / 2, lz(fy)),
						material = "Brick", color = tier.wallColor, collide = true, query = true,
					})
				end
				fx += 1
			end
		end

		-- THE ASCENT. Six pads spiralling the four corners of the stairwell cell, StepReach apart,
		-- with open air between them — not the packed staircase v1 shipped. Missing one drops the
		-- runner back onto this storey's floor with the collapse still rising, which is the whole
		-- failure model of the obby: it costs SECONDS, and the countdown is what turns seconds
		-- into a lost run. See Config.Ascent and tests/VaultFloor.spec.luau `climbIsFailable`.
		if s < storeys - 1 then
			local ex = exitCells[s + 1]
			local fx, fy = cellFine(ex.cx, ex.cy)
			local cx, cz = lx(fx), lz(fy)
			local OFF = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
			local n = math.floor(storeyHeight / V.StepRise)
			local off = V.StepReach / 2
			-- The shaft has to fit the one maze cell the hole above it is cut from. Asserted, not
			-- commented: StepReach and StepSize are two numbers in two places in Config and a pad
			-- poking through the stairwell wall is a pad a runner lands on from the corridor.
			assert(off + V.StepSize / 2 <= S / 2 + 1e-9, string.format(
				"VaultFloor: a %.1f-stud pad at reach %.1f does not fit a %.1f-stud stairwell cell",
				V.StepSize, V.StepReach, S))
			local pads = {}
			for k = 1, n do
				local o = OFF[((k - 1) % 4) + 1]
				local px, pz = cx + o[1] * off, cz + o[2] * off
				local top = baseY + k * V.StepRise
				block({
					name = string.format("Step_%d_%d", s, k), group = "step", storey = s,
					size = v3(V.StepSize, 1, V.StepSize),
					position = v3(px, top - 0.5, pz),
					material = "Slate", color = tier.floorColor, collide = true, query = true,
				})
				pads[k] = { index = k, x = px, y = top, z = pz }
			end
			-- The shaft as data, so the server's crumble loop, src/shared/Ascent.luau and the
			-- headless walkthrough all read the SAME pads the parts were built from instead of
			-- three copies of this arithmetic. `y` is the pad's walkable TOP, not its centre.
			shafts[s + 1] = { storey = s, cell = ex, x = cx, z = cz, floorY = baseY, pads = pads }
		end

		local gemRng = Rng.new(VaultFloor.storeySeed(spec, s) + GEM_SALT)
		local skipEntry, skipExit = entryCells[s + 1], exitCells[s + 1]
		local dead, rest = {}, {}
		for cy = 0, cells - 1 do
			for cx = 0, cells - 1 do
				if not ((cx == skipEntry.cx and cy == skipEntry.cy)
					or (cx == skipExit.cx and cy == skipExit.cy)) then
					local fx, fy = cellFine(cx, cy)
					local open = 0
					for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
						if not grid[fy + d[2]][fx + d[1]] then open += 1 end
					end
					if open <= 1 then dead[#dead + 1] = { cx, cy } else rest[#rest + 1] = { cx, cy } end
				end
			end
		end
		local function shuffle(list)
			for i = #list, 2, -1 do
				local j = Rng.below(gemRng, i)
				list[i], list[j] = list[j], list[i]
			end
		end
		shuffle(dead); shuffle(rest)
		local pool = {}
		for _, c in ipairs(dead) do pool[#pool + 1] = c end
		for _, c in ipairs(rest) do pool[#pool + 1] = c end
		for i = 1, math.min(spec.gemsPerStorey, #pool) do
			local c = pool[i]
			local fx, fy = cellFine(c[1], c[2])
			gems[#gems + 1] = {
				id = s * 1000 + i, storey = s, value = spec.gemValue,
				-- The MAZE cell as well as the world position: VaultPath prices the detour to
				-- this gem in cell steps, and re-deriving the cell from the position would be
				-- the same arithmetic run backwards, one rounding error from a wrong answer.
				cell = { cx = c[1], cy = c[2] },
				position = v3(lx(fx), baseY + V.GemHeight, lz(fy)),
				color = tier.gemColor,
			}
		end
	end

	local top = storeys - 1
	local topBase = top * storeyHeight
	local ec = exitCells[top + 1]
	local efx, efy = cellFine(ec.cx, ec.cy)
	local exX, exZ = lx(efx), lz(efy)

	block({
		name = "ExitPad", group = "exitpad", storey = top,
		size = v3(S, 1, S), position = v3(exX, topBase + 0.5, exZ),
		material = "Neon", color = tier.gemColor, transparency = 0.15,
		collide = true, query = true,
	})

	local sealStart = topBase + wallHeight - 1
	local sealEnd = topBase + 1.5
	block({
		name = "Seal", group = "seal", storey = top,
		size = v3(S, 1.5, S), position = v3(exX, sealStart, exZ),
		material = "Neon", color = cfg.Hud.DangerColor, transparency = 0.35,
	})

	-- The height at which the collapse kills a runner STANDING on storey s. This is the only
	-- place that arithmetic exists: the server's kill test, the plane's own start, and the
	-- countdown's per-storey deadline all read it from here, so they cannot disagree.
	local killLines = {}
	for s = 0, storeys - 1 do
		killLines[s + 1] = s * storeyHeight + cfg.Run.RunnerRootHeight - cfg.Run.KillMargin
	end

	-- The plane starts KillPlaneLeadStoreys BELOW the height at which it kills a runner standing
	-- on storey 0, so the ground floor gets exactly as much collapse to outrun as every storey
	-- above it. Written as a stud offset (-10) this was 11 studs against everyone else's 18.
	local planeStart = killLines[1] - V.KillPlaneLeadStoreys * storeyHeight
	local planeEnd = topBase + V.KillPlaneTop
	block({
		name = "Collapse", group = "killplane", storey = -1,
		size = v3(footW, V.KillPlaneThickness, footD), position = v3(0, planeStart, 0),
		material = "Neon", color = cfg.Hud.DangerColor, transparency = 0.25,
	})

	local en = entryCells[1]
	local sfx, sfy = cellFine(en.cx, en.cy)

	local bounds = {
		minX = -footW / 2, maxX = footW / 2,
		minY = planeStart, maxY = topBase + wallHeight,
		minZ = -footD / 2, maxZ = footD / 2,
	}

	return {
		parts = parts, gems = gems, grids = grids, shafts = shafts,
		entryCells = entryCells, exitCells = exitCells,
		cells = cells, storeys = storeys, cellSize = S,
		gCols = gCols, gRows = gRows,
		storeyHeight = storeyHeight, wallHeight = wallHeight, floorThickness = floorT,
		stepRise = V.StepRise, stepSize = V.StepSize, stepReach = V.StepReach,
		killMargin = cfg.Run.KillMargin,
		killLines = killLines,
		footprint = { w = footW, d = footD },
		spawn = { position = v3(lx(sfx), 4, lz(sfy)), look = v3(0, 0, 1) },
		exit = { storey = top, cell = ec, position = v3(exX, topBase + V.ExitHeight, exZ),
			radius = cfg.Run.ExitRadius },
		seal = { startY = sealStart, endY = sealEnd, size = v3(S, 1.5, S), x = exX, z = exZ },
		killPlane = { startY = planeStart, endY = planeEnd,
			size = v3(footW, V.KillPlaneThickness, footD) },
		bounds = bounds,
	}
end

-- What fraction of the countdown has passed when the collapse plane reaches height `y`. The
-- plane sweeps startY -> endY over exactly one countdown, so this is the ONE place that maps a
-- height in the vault onto a moment on the clock. VaultPath.countdown solves it backwards (given
-- the moment a runner can be there, how long must the countdown be); RunState.planeY runs it
-- forwards. Neither owns the arithmetic.
function VaultFloor.planeFractionAt(model: any, y: number): number
	local k = model.killPlane
	local span = k.endY - k.startY
	if span <= 0 then return 1 end
	return (y - k.startY) / span
end

return VaultFloor
