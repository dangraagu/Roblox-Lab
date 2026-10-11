--!strict
-- FlierGate.luau — er dette en flukt en LØPER kunne ha gjort. REN logikk.
--
-- Owner decision 2026-10-11: fliers must NOT top the DEEPEST ESCAPES board.
--
-- `Trace` (the file next to this one) bounds how FAST the server's own position for a runner may
-- move, and says in its header what it does not do: it does not test walls. A noclip client goes
-- to the exit in a straight line, through every wall and floor, and escapes at close to 100% at
-- every depth. While the only thing that bought was the cheater's own gems, that was a bounded
-- cheat. With a public board it is the top ten.
--
-- This module is the geometry half, and it decides ONE thing: whether an escape counts for the
-- board. It does not throttle, kick, or touch the economy: gems, floors and the run itself are
-- still judged on `Trace`, exactly as before.
--
-- HOW. The gate keeps a VALIDATED position for the run, seeded from where the SERVER dropped the
-- runner. Each sample of the client's claimed position is accepted, and becomes the validated
-- position, only if
--   * it is in walkable space (an open maze cell of its storey, inside the vault), and
--   * it can be reached from the validated position through the vault's layout: along the
--     corridors of a storey, and between storeys only through the stairwell (the shaft and the
--     hole above it are one maze cell, and that column is the only opening in a floor), and
--   * the shortest such route is no longer than a runner could have covered: an allowance that
--     accrues at WalkSpeed x Gate.SpeedFactor (and, for height gained, at the fastest a chain of
--     jumps can climb x Gate.ClimbFactor) and BANKS only Gate.BurstSeconds of itself.
-- A sample that fails is simply not accepted. Nothing else happens: the validated position stays
-- where it was and the next sample is measured from there. So one stray position, a burst of late
-- replication or a short freeze costs an honest runner nothing; they are back in step as soon as a
-- sample is reachable again.
--
-- An escape is TRACED when, at the moment the server banks it, the exit is itself a position the
-- gate would accept: reachable from the validated position inside the allowance in hand. A flier
-- who went through the walls left their validated position behind at the last place they could
-- honestly have been, and it is not at the exit.
--
-- WHY THE BANK IS CAPPED, which is the whole design. Without the cap, time alone buys distance:
-- stand at the drop-in for as long as the route takes, teleport to the exit, and the route is
-- "reachable in the time". With it, no single accepted move is longer than a few seconds of
-- running, so the validated position can only get to the exit by being SEEN along the way.
--
-- WHY AN HONEST RUNNER IS NEVER REFUSED, as an argument and not a tuning. A move is priced at the
-- true geodesic (never more; the spec checks it against two searches that share no code with it): the shortest line from A to B that stays inside the corridors (`path`, a funnel
-- over the one corridor a perfect maze has between two cells). No path a body can take is shorter,
-- so a runner who covered it at WalkSpeed is inside WalkSpeed x SpeedFactor with the factor to
-- spare. Between storeys the price is a LOWER bound (the stairwell cell's own half-diagonal is
-- forgiven on each side). And no runner gains height faster than jumps chained apex to apex:
-- JumpPower^2 / 2g studs every JumpPower / g seconds, which is JumpPower / 2.
-- tests/FlierGate.spec.luau measures every one of those margins and prints them.
--
-- WHAT THIS DOES NOT DO, so nobody reads more into it than is here:
--   * it does not stop a cheat that FOLLOWS THE ROUTE. A script that walks the real corridors, or
--     teleports along them in hops the bank can pay for, is a runner as far as geometry can tell.
--     What it has left is Gate.SpeedFactor of speed on the flat and the time the pads would have
--     cost in the shaft.
--   * it does not forgive a freeze longer than the bank. A runner at full speed who vanishes for
--     more than BurstSeconds x SpeedFactor seconds comes back further along the route than one
--     accepted move can reach, and unless they come back toward where they were seen last, that
--     run's escape is not ranked. Their gems, their floor and their next run are untouched.
--   * it assumes the maze is PERFECT (one corridor between two cells), which MazeGen's recursive
--     backtracker guarantees and tests/FlierGate.spec.luau asserts. In a maze with loops the route
--     found here could be the longer way round, and an honest runner could be refused.
--
-- Pure: cfg + the model VaultFloor.build returned + plain {x,y,z} tables in vault-local studs.
-- No Roblox global, no clock of its own. And, like every other module in src/shared, it requires
-- nothing: a bare `require("./X")` resolves in the luau CLI and is INVALID in Roblox.

local FlierGate = {}

local SQRT_HALF = math.sqrt(0.5)

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

--============================================================================ the allowances

-- flat: WalkSpeed with a tolerance, the same shape as Trace's.
-- up:   the fastest any chain of jumps gains height (each landed at its own apex), with a tolerance.
function FlierGate.speeds(cfg: any): (number, number)
	local mv = cfg.Movement
	return mv.WalkSpeed * cfg.Gate.SpeedFactor, mv.JumpPower / 2 * cfg.Gate.ClimbFactor
end

--============================================================================ where a position is

local function cellOpen(model: any, storey: number, fx: number, fy: number): boolean
	local row = model.grids[storey + 1][fy]
	return row ~= nil and row[fx] == false
end

local function cellCentre(model: any, fx: number, fy: number): (number, number)
	local S = model.cellSize
	return (fx - (model.gCols - 1) / 2) * S, (fy - (model.gRows - 1) / 2) * S
end

-- The storey and fine cell a root position is in, or nil when it is not in walkable space.
-- Returns { storey, fx, fy, x, z }; x and z are the position itself, or, for a root pressed up to
-- `tolerance` studs into a wall (a body is not a point, and physics is not exact), the nearest
-- point of the corridor it is leaning out of.
--
-- A storey is the band from its own floor top to the next one's: a root is never below the floor
-- it stands on, and it only crosses a band inside the stairwell, which is an open cell of both.
function FlierGate.locate(model: any, pos: any, tolerance: number): any
	if type(pos) ~= "table" or not (finite(pos.x) and finite(pos.y) and finite(pos.z)) then return nil end
	local storey = math.floor(pos.y / model.storeyHeight)
	if storey < 0 or storey > model.storeys - 1 then return nil end
	local S = model.cellSize
	local fx = math.floor(pos.x / S + (model.gCols - 1) / 2 + 0.5)
	local fy = math.floor(pos.z / S + (model.gRows - 1) / 2 + 0.5)
	if cellOpen(model, storey, fx, fy) then
		return { storey = storey, fx = fx, fy = fy, x = pos.x, z = pos.z }
	end
	local best = nil
	local bestD = tolerance
	for dy = -1, 1 do
		for dx = -1, 1 do
			if (dx ~= 0 or dy ~= 0) and cellOpen(model, storey, fx + dx, fy + dy) then
				local cx, cz = cellCentre(model, fx + dx, fy + dy)
				local nx = math.clamp(pos.x, cx - S / 2, cx + S / 2)
				local nz = math.clamp(pos.z, cz - S / 2, cz + S / 2)
				local d = math.sqrt((nx - pos.x) ^ 2 + (nz - pos.z) ^ 2)
				if d <= bestD then
					bestD = d
					best = { storey = storey, fx = fx + dx, fy = fy + dy, x = nx, z = nz }
				end
			end
		end
	end
	return best
end

--============================================================================ the shortest line

-- The corridor between two open fine cells of one storey, as the list of cells walked through.
-- Breadth-first, like VaultPath.distances, and for the same reason: "there is only one" is a
-- property of the generator, not of this file.
local function cellRoute(model: any, storey: number, ax: number, ay: number, bx: number, by: number): any
	if ax == bx and ay == by then return { { ax, ay } } end
	local cols = model.gCols
	local prev = { [ay * cols + ax] = -1 }
	local queue, head = { { ax, ay } }, 1
	local found = false
	while head <= #queue and not found do
		local c = queue[head]
		head += 1
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, ny = c[1] + d[1], c[2] + d[2]
			local k = ny * cols + nx
			if prev[k] == nil and cellOpen(model, storey, nx, ny) then
				prev[k] = c[2] * cols + c[1]
				if nx == bx and ny == by then found = true; break end
				queue[#queue + 1] = { nx, ny }
			end
		end
	end
	if not found then return nil end
	local out = {}
	local k = by * cols + bx
	while k ~= -1 do
		table.insert(out, 1, { k % cols, k // cols })
		k = prev[k]
	end
	return out
end

-- Twice the signed area of (a, b, c) in the x-z plane.
local function area2(ax: number, az: number, bx: number, bz: number, cx: number, cz: number): number
	return (cx - ax) * (bz - az) - (bx - ax) * (cz - az)
end

-- THE GEODESIC on one storey: the shortest line from `from` to `to` that stays inside the open
-- cells. Returns the line as points ({x, z}, both ends included) and its length, or nil when
-- either end is in a wall or there is no corridor between them.
--
-- The corridor is a strip of squares joined edge to edge, so this is the textbook funnel: every
-- shared edge is a portal, and the line is pulled tight through them, bending only at the wall
-- corners it has to go round.
--
-- `from` and `to` are what `locate` returned ({ fx, fy, x, z }): a point ON a cell edge belongs to
-- the open cell it touches, which only `locate` decides. `FlierGate.path` below takes bare points.
local function pull(model: any, storey: number, from: any, to: any): (any, number?)
	local S = model.cellSize
	local cells = cellRoute(model, storey, from.fx, from.fy, to.fx, to.fy)
	if cells == nil then return nil, nil end

	-- AN END EXACTLY ON A SHARED EDGE is already in the next cell, so the cell it was filed under is
	-- dropped from that end of the strip. Left in, the end point sits ON its own first portal, the
	-- funnel has no width there, and the line is bent round the far end of that edge: up to 24 studs
	-- LONGER than the true route, which is the direction that refuses an honest runner (review,
	-- 2026-10-11; tests/FlierGate.spec.luau pins it against points a hair either side of the edge).
	local function onSharedEdge(pt: any, c: any, n: any): boolean
		local cx, cz = cellCentre(model, c[1], c[2])
		if n[1] ~= c[1] then return math.abs(pt.x - (cx + (n[1] - c[1]) * S / 2)) < 1e-9 end
		return math.abs(pt.z - (cz + (n[2] - c[2]) * S / 2)) < 1e-9
	end
	while #cells >= 2 and onSharedEdge(from, cells[1], cells[2]) do table.remove(cells, 1) end
	while #cells >= 2 and onSharedEdge(to, cells[#cells], cells[#cells - 1]) do table.remove(cells) end

	-- portals[i] = { leftX, leftZ, rightX, rightZ }; the first and last are the two end points
	local portals = { { from.x, from.z, from.x, from.z } }
	for i = 1, #cells - 1 do
		local c, n = cells[i], cells[i + 1]
		local dx, dy = n[1] - c[1], n[2] - c[2]
		local cx, cz = cellCentre(model, c[1], c[2])
		local mx, mz = cx + dx * S / 2, cz + dy * S / 2
		-- the shared edge, its two ends named as seen walking from c to n
		portals[#portals + 1] = { mx - dy * S / 2, mz + dx * S / 2, mx + dy * S / 2, mz - dx * S / 2 }
	end
	portals[#portals + 1] = { to.x, to.z, to.x, to.z }

	local pts = { { x = from.x, z = from.z } }
	local apexX, apexZ = from.x, from.z
	local leftX, leftZ, rightX, rightZ = apexX, apexZ, apexX, apexZ
	local apexI, leftI, rightI = 1, 1, 1
	local i = 2
	while i <= #portals do
		local p = portals[i]
		local restarted = false
		-- tighten the right side
		if area2(apexX, apexZ, rightX, rightZ, p[3], p[4]) <= 0 then
			if (apexX == rightX and apexZ == rightZ) or area2(apexX, apexZ, leftX, leftZ, p[3], p[4]) > 0 then
				rightX, rightZ, rightI = p[3], p[4], i
			else
				-- the right side crossed the left: the left corner is a bend
				pts[#pts + 1] = { x = leftX, z = leftZ }
				apexX, apexZ, apexI = leftX, leftZ, leftI
				leftX, leftZ, rightX, rightZ = apexX, apexZ, apexX, apexZ
				leftI, rightI = apexI, apexI
				i = apexI + 1
				restarted = true
			end
		end
		-- tighten the left side
		if not restarted and area2(apexX, apexZ, leftX, leftZ, p[1], p[2]) >= 0 then
			if (apexX == leftX and apexZ == leftZ) or area2(apexX, apexZ, rightX, rightZ, p[1], p[2]) < 0 then
				leftX, leftZ, leftI = p[1], p[2], i
			else
				pts[#pts + 1] = { x = rightX, z = rightZ }
				apexX, apexZ, apexI = rightX, rightZ, rightI
				leftX, leftZ, rightX, rightZ = apexX, apexZ, apexX, apexZ
				leftI, rightI = apexI, apexI
				i = apexI + 1
				restarted = true
			end
		end
		if not restarted then i += 1 end
	end
	pts[#pts + 1] = { x = to.x, z = to.z }

	local length = 0
	for k = 2, #pts do
		length += math.sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].z - pts[k - 1].z) ^ 2)
	end
	return pts, length
end

function FlierGate.path(model: any, storey: number, from: any, to: any): (any, number?)
	local y = storey * model.storeyHeight
	local a = FlierGate.locate(model, { x = from.x, y = y, z = from.z }, 0)
	local b = FlierGate.locate(model, { x = to.x, y = y, z = to.z }, 0)
	if a == nil or b == nil then return nil, nil end
	return pull(model, storey, a, b)
end

--============================================================================ what a move costs

-- The cost of getting from `from` to `to` through the vault: studs on the flat and studs of height
-- gained. nil (and a word saying why) when there is no way: an end in a wall or outside the vault.
--
-- On one storey the flat cost is the geodesic. Across storeys the only way is the stairwell column
-- of every floor in between, so it is the corridor to that cell, the whole crossing of any storey
-- passed through, and the corridor from the last hole; each leg is measured to the stairwell's
-- CENTRE and forgiven the cell's half-diagonal, because the runner may have gone through any point
-- of it. That makes it a lower bound, never more than a body walked. It is also never less than
-- the straight line.
--
-- `limit` is optional: a move whose STRAIGHT line is already longer than it is refused as "far"
-- without looking for the corridor (the corridor is never shorter than the straight line). That is
-- what a flier parked on the exit costs the server every sample: two lookups and a square root.
function FlierGate.cost(model: any, from: any, to: any, tolerance: number, limit: number?): (number?, any)
	local a = FlierGate.locate(model, from, tolerance)
	if a == nil then return nil, "lost" end
	local b = FlierGate.locate(model, to, tolerance)
	if b == nil then return nil, "wall" end
	local up = math.max(0, to.y - from.y)
	local straight = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	if limit ~= nil and straight > limit then return nil, "far" end

	if a.storey == b.storey then
		local _, length = pull(model, a.storey, a, b)
		if length == nil then return nil, "wall" end
		return length, up
	end

	local lo, hi = a, b
	if a.storey > b.storey then lo, hi = b, a end
	local forgiven = model.cellSize * SQRT_HALF
	local function hole(k: number): any   -- the stairwell between storey k and storey k + 1
		local c = model.exitCells[k + 1]
		local x, z = cellCentre(model, 2 * c.cx + 1, 2 * c.cy + 1)
		return { fx = 2 * c.cx + 1, fy = 2 * c.cy + 1, x = x, z = z }
	end
	local flat = 0
	local at = lo
	for k = lo.storey, hi.storey - 1 do
		local h = hole(k)
		local _, leg = pull(model, k, at, h)
		if leg == nil then return nil, "wall" end
		flat += math.max(0, leg - (if k == lo.storey then forgiven else 2 * forgiven))
		at = h
	end
	local _, last = pull(model, hi.storey, at, hi)
	if last == nil then return nil, "wall" end
	flat += math.max(0, last - forgiven)
	return math.max(flat, straight), up
end

--============================================================================ the gate

-- `start` is where the SERVER put the runner, in vault-local studs; never a position the client
-- supplied. The allowances start EMPTY, like Trace's: a run does not open with a free move.
function FlierGate.new(cfg: any, _model: any, start: any): any
	local flat, up = FlierGate.speeds(cfg)
	local burst = cfg.Gate.BurstSeconds
	return {
		x = start.x, y = start.y, z = start.z,
		budgetH = 0, budgetUp = 0,
		maxBudgetH = flat * burst, maxBudgetUp = up * burst,
		speedH = flat, speedUp = up,
		tolerance = cfg.Gate.WallTolerance,
		-- Diagnostics only; nothing in the game reads these. They exist so a spec can prove a
		-- sample was refused (or was not) instead of inferring it from the verdict.
		accepted = 0, rejected = 0, lastReason = nil,
	}
end

-- A move the SERVER made (a respawn, a checkpoint, any CFrame it wrote itself): the validated
-- position is where the server put them and the allowances start again. Vault Runners makes one
-- such move per run, the drop-in, and `new` is that one; this is here so the next one cannot be
-- added without a way to tell the gate.
function FlierGate.reseed(gate: any, pos: any)
	gate.x, gate.y, gate.z = pos.x, pos.y, pos.z
	gate.budgetH, gate.budgetUp = 0, 0
end

-- One sample. `observed` is the client's claim in vault-local studs, `dt` the seconds since the
-- last call. Returns true when the claim was accepted and is now the validated position.
function FlierGate.step(gate: any, model: any, observed: any, dt: number): boolean
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then dt = 0 end
	gate.budgetH = math.min(gate.maxBudgetH, gate.budgetH + gate.speedH * dt)
	gate.budgetUp = math.min(gate.maxBudgetUp, gate.budgetUp + gate.speedUp * dt)

	local flat, up = FlierGate.cost(model, gate, observed, gate.tolerance, gate.budgetH + 1e-9)
	local reason = nil
	if flat == nil then
		reason = up
	elseif flat > gate.budgetH + 1e-9 then
		reason = "far"
	elseif up > gate.budgetUp + 1e-9 then
		reason = "high"
	end
	if reason ~= nil then
		gate.rejected += 1
		gate.lastReason = reason
		return false
	end

	local where = FlierGate.locate(model, observed, gate.tolerance)
	gate.x, gate.y, gate.z = where.x, observed.y, where.z
	gate.budgetH = math.max(0, gate.budgetH - (flat :: number))
	gate.budgetUp = math.max(0, gate.budgetUp - up)
	gate.accepted += 1
	return true
end

-- IS THE ESCAPE TRACED. Asked once, when the server banks an escape: could the validated position
-- be at the exit right now? It is the same question `step` asks of a sample, asked of the exit
-- itself, with the exit's own radius forgiven (the escape rule is "within Run.ExitRadius of it").
-- Not "was the last sample accepted": a flier can claim the exit until the trusted position is
-- nearly there and then claim a legitimate spot for one sample.
function FlierGate.traced(cfg: any, gate: any, model: any): (boolean, string?)
	local flat, up = FlierGate.cost(model, gate, model.exit.position, gate.tolerance)
	if flat == nil then return false, up end
	local radius = cfg.Run.ExitRadius
	if flat - radius > gate.budgetH + 1e-9 then return false, "far" end
	if up - radius > gate.budgetUp + 1e-9 then return false, "high" end
	return true, nil
end

return FlierGate
