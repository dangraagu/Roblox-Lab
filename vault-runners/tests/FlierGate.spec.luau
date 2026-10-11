-- FlierGate — is this escape one a RUNNER could have made. Run: luau tests/FlierGate.spec.luau
--
-- Owner decision 2026-10-11: fliers must NOT top the DEEPEST ESCAPES board. `Trace` bounds a
-- runner's speed and nothing else, so a noclip client goes to the exit through walls and floors
-- and escapes every vault. `FlierGate` is the geometry half: it keeps a VALIDATED position, moves
-- it only onto a claim that is reachable from it through the vault's walkable layout inside the
-- distance a runner could have covered, and an escape counts for the board only if that validated
-- position could be at the exit when the escape is banked.
--
-- Two properties, and each needs the other:
--   * A FLIER IS NOT RANKED: straight to the exit, straight up through the floors, waiting it out
--     at the spawn and then teleporting, or stepping back "in sync" for the last sample.
--   * AN HONEST RUNNER IS NEVER EXCLUDED: the shortest possible line at full WalkSpeed, the chained
--     hops, a fall, a drop back down the hole, a hazard knock, sample jitter, a multi-second lag gap.
--     The margins are PRINTED, not asserted against themselves.
--
-- What makes the second one a proof and not a tuning: the gate prices a move at the true geodesic
-- (the shortest line that stays inside the corridors), which no honest path can be shorter than.
-- §2 checks that number against a brute-force search that shares no code with the module, and
-- points exactly on a cell edge against the points beside them. The "racing" runner below walks the
-- module's own line, so it measures the MARGIN at the shortest line, not the line; the "centres"
-- runner, tests/VaultModel.luau and walk_vaultrunners.luau find their own way.

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local MazeGen = require("../src/shared/MazeGen")
local VaultFloor = require("../src/shared/VaultFloor")
local VaultPath = require("../src/shared/VaultPath")
local Progression = require("../src/shared/Progression")
local RunState = require("../src/shared/RunState")
local Trace = require("../src/shared/Trace")
local Hazards = require("../src/shared/Hazards")
local VaultEnv = require("../src/shared/VaultEnv")
local EnvBands = require("../src/shared/EnvBands")
local VaultModel = require("./VaultModel")
local FlierGate = require("../src/shared/FlierGate")

local passed, failed = 0, 0
local function ok(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-6) then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end

local C = Config
local G = C.Gate
local W = C.Movement.WalkSpeed
local J, GRAV = C.Movement.JumpPower, C.Movement.Gravity
local ROOT = C.Run.RunnerRootHeight
local DT = C.Ascent.SampleSeconds
local S = C.Vault.CellSize
local HS = C.Vault.StoreyHeight

local VM = VaultModel.new({
	Config = C, Progression = Progression, VaultFloor = VaultFloor, MazeGen = MazeGen, Rng = Rng,
	VaultPath = VaultPath, RunState = RunState, Hazards = Hazards, VaultEnv = VaultEnv, EnvBands = EnvBands,
})

local function at(x, y, z) return { x = x, y = y, z = z } end
local function centre(model, fx, fy)
	return (fx - (model.gCols - 1) / 2) * S, (fy - (model.gRows - 1) / 2) * S
end
local function cellCentre(model, c) return centre(model, 2 * c.cx + 1, 2 * c.cy + 1) end
local function fineOf(model, x, z)
	return math.floor(x / S + (model.gCols - 1) / 2 + 0.5), math.floor(z / S + (model.gRows - 1) / 2 + 0.5)
end
local function isOpen(model, s, x, z)
	local fx, fy = fineOf(model, x, z)
	local row = model.grids[s + 1][fy]
	return row ~= nil and row[fx] == false
end
local function dist3(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local flatRate, upRate = FlierGate.speeds(C)

--============================================================================ 1. the numbers

do
	near(flatRate, W * G.SpeedFactor, 1e-9, "the flat allowance is WalkSpeed x Gate.SpeedFactor")
	ok(G.SpeedFactor > 1, "and it is strictly more than a runner has")
	-- No runner gains height faster than a chain of jumps each landed at its apex: J^2/2g studs
	-- every J/g seconds, which is J/2.
	near(upRate, J / 2 * G.ClimbFactor, 1e-9, "the upward allowance is the apex-chain rate (JumpPower / 2) x Gate.ClimbFactor")
	ok(G.ClimbFactor > 1, "and that factor is more than 1 too")
	ok(G.BurstSeconds >= 3 and G.BurstSeconds <= 6, "the bank is a FEW seconds (" .. tostring(G.BurstSeconds) .. ")")
	ok(G.WallTolerance > 0 and G.WallTolerance < S / 4, "the wall tolerance is positive and far thinner than a wall")
	-- The game has ONE speed. If a speed upgrade is ever added, this gate reads the wrong number.
	local speedy = false
	for _, pet in ipairs(C.Pets.List) do
		for k in pairs(pet) do if string.find(string.lower(k), "speed") then speedy = true end end
	end
	ok(not speedy, "no pet carries a speed bonus: Config.Movement.WalkSpeed IS the top speed")
end

--============================================================================ 2. the geodesic is the true one

-- A hand-made corner. Three fine cells of 12: west arm (-12, 0), the corner (0, 0), south arm (0, 12).
do
	local T, F = true, false
	local grid = { [0] = { [0] = T, T, T }, [1] = { [0] = F, F, T }, [2] = { [0] = T, F, T } }
	local m = { grids = { grid }, gCols = 3, gRows = 3, cellSize = 12, storeys = 1, storeyHeight = 18 }
	local function len(ax, az, bx, bz)
		local _, l = FlierGate.path(m, 0, at(ax, 3, az), at(bx, 3, bz))
		return l
	end
	near(len(-16, 0, -8, 0), 8, 1e-9, "inside one cell the route is the straight line")
	near(len(-16, 2, 4, -3), math.sqrt(400 + 25), 1e-9, "down a straight corridor it is the straight line too")
	-- Round the corner: the inside corner of the wall is at (-6, 6).
	local want = math.sqrt(100 + 4) + math.sqrt(4 + 100)
	near(len(-16, 4, -4, 16), want, 1e-9, "round a corner it bends at the wall's inside corner (20.396, not the 16.97 through the wall)")
	near(len(-4, 16, -16, 4), want, 1e-9, "and the same length walked the other way")
	local pts = FlierGate.path(m, 0, at(-16, 4, 0), at(-4, 3, 16))
	ok(pts ~= nil and #pts >= 2, "the route comes back as points")
	ok(FlierGate.path(m, 0, at(-16, 3, 4), at(12, 3, 12)) == nil, "a point inside a wall has no route")
end

-- A POINT EXACTLY ON A CELL EDGE (review 2026-10-11: the funnel bent round the far end of the edge it
-- started on and returned 31.90 for a 16.88-stud move). A length is continuous: a point on an edge
-- costs what the points a hair either side of it cost. Every edge and corner of the route, both ends.
do
	near(select(2, FlierGate.path(VM:vault(1, 1), 0, at(34.4892, 3, -30), at(17.7268, 3, -29.7206))), 16.88, 0.05,
		"the reviewer's pair: an end exactly on an edge is priced like its neighbours (it read 31.90)")
	local worst, pairsSeen = 0, 0
	for _, tf in ipairs({ { 1, 1 }, { 3, 30 } }) do
		local model = VM:vault(tf[1], tf[2])
		for s = 0, model.storeys - 1 do
			local ax, az = cellCentre(model, model.entryCells[s + 1])
			local ex, ez = cellCentre(model, model.exitCells[s + 1])
			local pts = FlierGate.path(model, s, at(ax + 2.7, 0, az - 1.3), at(ex - 1.1, 0, ez + 3.1))
			local ends = { at(ax + 2.7, 0, az - 1.3), at(ex - 1.1, 0, ez + 3.1) }
			for fy = 1, model.gRows - 2 do
				for fx = 1, model.gCols - 2 do
					if model.grids[s + 1][fy][fx] == false then
						local cx, cz = centre(model, fx, fy)
						-- the four edge midpoints, the four corners and two off-centre edge points of this cell
						for _, o in ipairs({ { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 }, { 6, 6 }, { -6, 6 }, { 6, -6 }, { -6, -6 }, { 6, 2.5 }, { -3.25, -6 } }) do
							local px, pz = cx + o[1], cz + o[2]
							for _, other in ipairs(ends) do
								local _, exact = FlierGate.path(model, s, at(px, 0, pz), other)
								local _, back = FlierGate.path(model, s, other, at(px, 0, pz))
								-- the cheapest of the points just inside this cell
								local inside = math.huge
								for _, n in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
									local _, l = FlierGate.path(model, s, at(px + n[1] * 1e-6, 0, pz + n[2] * 1e-6), other)
									if l ~= nil then inside = math.min(inside, l) end
								end
								if exact ~= nil and inside < math.huge then
									pairsSeen += 1
									worst = math.max(worst, exact - inside, (back or math.huge) - inside)
								end
							end
						end
					end
				end
			end
			local _ = pts
		end
	end
	print(string.format("  points exactly on a cell edge or corner, %d pairs: priced at most %.6f studs over the point a hair inside", pairsSeen, worst))
	ok(pairsSeen > 2000, "enough edge points were tried (" .. pairsSeen .. ")")
	ok(worst < 1e-3, string.format("a point ON an edge is never priced over its neighbour just inside (worst %.4f studs)", worst))
end

-- Every storey's corridors are a TREE, so there is exactly one corridor between two points and the
-- funnel over it is THE shortest line, not one of several.
do
	local trees, storeys = 0, 0
	for _, tf in ipairs({ { 1, 1 }, { 2, 7 }, { 3, 1 }, { 3, 60 }, { 3, 400 } }) do
		local model = VM:vault(tf[1], tf[2])
		for s = 0, model.storeys - 1 do
			local grid = model.grids[s + 1]
			local cellsOpen, edges = 0, 0
			for fy = 0, model.gRows - 1 do
				for fx = 0, model.gCols - 1 do
					if grid[fy][fx] == false then
						cellsOpen += 1
						if fx + 1 < model.gCols and grid[fy][fx + 1] == false then edges += 1 end
						if fy + 1 < model.gRows and grid[fy + 1][fx] == false then edges += 1 end
					end
				end
			end
			storeys += 1
			if edges == cellsOpen - 1 then trees += 1 end
		end
	end
	ok(trees == storeys, string.format("every storey's open cells form a tree (%d of %d)", trees, storeys))
end

-- BRUTE FORCE, sharing nothing with the module: Dijkstra over a 2-stud lattice, 16 directions,
-- a move allowed only if every point along it is in an open cell. A lattice route is a real route,
-- so the module's length may never be longer than it; and it is the same route to within what a
-- lattice costs (a few percent), so the module is not flattering a wall-cut either. Three sources
-- on every storey of Bronze floor 1, every seventh lattice point as the other end.
do
	local model = VM:vault(1, 1)
	local lo, hi = math.huge, 0
	local longer, compared = 0, 0
	for s = 0, model.storeys - 1 do
		local half = model.gCols * S / 2
		local n = model.gCols * S / 2      -- lattice points per axis, 2 studs apart, never on a cell edge
		local function coord(i) return -half + 1 + 2 * i end
		local nodes, idOf = {}, {}
		for iz = 0, n - 1 do
			for ix = 0, n - 1 do
				if isOpen(model, s, coord(ix), coord(iz)) then
					nodes[#nodes + 1] = { ix, iz }
					idOf[iz * n + ix] = #nodes
				end
			end
		end
		local moves = {}
		for _, mv in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 }, { 1, 2 }, { 2, 1 }, { 1, -2 }, { 2, -1 } }) do
			moves[#moves + 1] = mv
			moves[#moves + 1] = { -mv[1], -mv[2] }
		end
		local function clear(ax, az, bx, bz)
			for k = 1, 15 do
				local f = k / 16
				if not isOpen(model, s, ax + (bx - ax) * f, az + (bz - az) * f) then return false end
			end
			return true
		end
		for _, corner in ipairs({ model.entryCells[s + 1], model.exitCells[s + 1], { cx = 1, cy = 2 } }) do
		local sx, sz = cellCentre(model, corner)
		sx += 1; sz += 1   -- onto the lattice
		local src = idOf[((sz + half - 1) / 2) * n + (sx + half - 1) / 2]
		local dist, done = {}, {}
		for i = 1, #nodes do dist[i] = math.huge end
		dist[src] = 0
		for _ = 1, #nodes do
			local best, bi = math.huge, nil
			for i = 1, #nodes do
				if not done[i] and dist[i] < best then best, bi = dist[i], i end
			end
			if bi == nil then break end
			done[bi] = true
			local ix, iz = nodes[bi][1], nodes[bi][2]
			for _, mv in ipairs(moves) do
				local jx, jz = ix + mv[1], iz + mv[2]
				local j = (jx >= 0 and jx < n and jz >= 0 and jz < n) and idOf[jz * n + jx] or nil
				if j ~= nil and not done[j] and clear(coord(ix), coord(iz), coord(jx), coord(jz)) then
					local d = best + 2 * math.sqrt(mv[1] * mv[1] + mv[2] * mv[2])
					if d < dist[j] then dist[j] = d end
				end
			end
		end
		for i = 1, #nodes, 7 do
			local tx, tz = coord(nodes[i][1]), coord(nodes[i][2])
			local _, l = FlierGate.path(model, s, at(sx, s * HS + ROOT, sz), at(tx, s * HS + ROOT, tz))
			local straight = math.sqrt((tx - sx) ^ 2 + (tz - sz) ^ 2)
			compared += 1
			if l == nil or l > dist[i] + 1e-6 or l < straight - 1e-6 then longer += 1 end
			if l ~= nil and dist[i] > 30 then
				lo, hi = math.min(lo, l / dist[i]), math.max(hi, l / dist[i])
			end
		end
		end
	end
	print(string.format("  geodesic vs a 2-stud lattice search, %d point pairs: module / lattice = %.4f .. %.4f", compared, lo, hi))
	ok(compared > 1000, "enough pairs were compared (" .. compared .. ")")
	ok(longer == 0, "the module's route is NEVER longer than a real route found by brute force, and never shorter than the straight line (" .. longer .. " broke it)")
	-- (a lattice route cannot touch a wall corner, it passes a stud wide of it, and it turns in 16
	-- directions only: that is the few percent. A line that cut one corner cell would read near 0.7.)
	ok(lo > 0.9, string.format("and it is the same route, not a cut through a wall (ratio never under %.4f)", lo))
end

--============================================================================ the server, in miniature

-- Exactly what Main.server does with a sample: Trace and the gate are both stepped on the claim at
-- Ascent.SampleSeconds, the exit is judged on the TRUSTED position at Run.TickSeconds, and the
-- gate is asked once, when the escape is banked.
local function judge(model, samples)
	local trace = Trace.new(C, model.spawn.position)
	local gate = FlierGate.new(C, model, model.spawn.position)
	local t, since = 0, 0
	local minSpare = math.huge
	for _, smp in ipairs(samples) do
		local dt = smp.dt or DT
		local tick = if dt == dt then dt else DT   -- (a nan dt is handed to both as it came; this clock is the spec's own)
		t += tick
		local tp = Trace.step(trace, smp, dt)
		if FlierGate.step(gate, model, smp, dt) then minSpare = math.min(minSpare, gate.budgetH) end
		since += tick
		if since >= C.Run.TickSeconds - 1e-6 then
			since = math.min(since - C.Run.TickSeconds, C.Run.TickSeconds)
			if dist3(tp, model.exit.position) <= C.Run.ExitRadius then
				local traced, why = FlierGate.traced(C, gate, model)
				return { escaped = true, t = t, traced = traced, why = why, gate = gate, minSpare = minSpare }
			end
		end
	end
	return { escaped = false, t = t, traced = false, gate = gate, minSpare = minSpare }
end

--============================================================================ an honest runner, as samples

-- A runner made of the game's own physics: WalkSpeed on the flat, a jump launched at JumpPower
-- under Gravity, a fall from rest. `line = "racing"` walks the shortest line there is (it hugs every
-- inside corner), `"centres"` walks cell centre to cell centre like walk_vaultrunners.luau.
local function newRunner(model, opts)
	opts = opts or {}
	local r = { model = model, samples = {}, t = 0 }
	local p = at(model.spawn.position.x, model.spawn.position.y, model.spawn.position.z)
	local speed = W * (opts.speedFactor or 1)
	local function emit()
		r.t += DT
		local y = p.y
		if opts.hop and r.onFloor then
			-- jumping the whole way, as players do: one full jump after another, no pause between
			local tau = r.t % (2 * J / GRAV)
			y += J * tau - GRAV * tau * tau / 2
		end
		r.samples[#r.samples + 1] = { x = p.x, y = y, z = p.z, dt = DT, t = r.t }
	end
	function r.pos() return at(p.x, p.y, p.z) end
	function r.stand(seconds)
		for _ = 1, math.ceil(seconds / DT) do emit() end
	end
	-- straight, on the flat, at `v`
	function r.walkTo(x, z, v)
		v = v or speed
		while true do
			local dx, dz = x - p.x, z - p.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= v * DT then p.x, p.z = x, z; emit(); return end
			p.x += dx / d * v * DT; p.z += dz / d * v * DT
			emit()
		end
	end
	function r.settle(y) p.y = y end
	-- across storey s to (x, z)
	function r.cross(s, x, z)
		r.onFloor = true
		if opts.line == "centres" then
			local fx, fy = fineOf(model, p.x, p.z)
			local tx, tz = fineOf(model, x, z)
			local from = { cx = (fx - 1) // 2, cy = (fy - 1) // 2 }
			local to = { cx = (tx - 1) // 2, cy = (tz - 1) // 2 }
			local dist = VaultPath.distances(model, s, from)
			local cells, cur = { to }, to
			local d = dist[to.cy * model.cells + to.cx]
			while d > 0 do
				for _, dd in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local nx, ny = cur.cx + dd[1], cur.cy + dd[2]
					if nx >= 0 and nx < model.cells and ny >= 0 and ny < model.cells
						and model.grids[s + 1][2 * cur.cy + 1 + dd[2]][2 * cur.cx + 1 + dd[1]] == false
						and dist[ny * model.cells + nx] == d - 1 then
						cur = { cx = nx, cy = ny }; d -= 1
						table.insert(cells, 1, cur)
						break
					end
				end
			end
			for _, c in ipairs(cells) do
				local cx, cz = cellCentre(model, c)
				r.walkTo(cx, cz)
			end
			r.walkTo(x, z)
		else
			local pts = FlierGate.path(model, s, p, at(x, p.y, z))
			assert(pts ~= nil, "the honest runner asked for a route that does not exist")
			for i = 2, #pts do r.walkTo(pts[i].x, pts[i].z) end
		end
		r.onFloor = false
	end
	-- one jump onto a surface whose standing root height is `y`, over at (x, z)
	function r.jump(x, z, y)
		local rise = y - p.y
		local disc = J * J - 2 * GRAV * rise
		assert(disc >= 0, "the honest runner was asked for a jump higher than a jump goes")
		local tLand = (J + math.sqrt(disc)) / GRAV
		local dx, dz = x - p.x, z - p.z
		local d = math.sqrt(dx * dx + dz * dz)
		assert(d <= W * tLand + 1e-6, string.format("the honest runner was asked for a %.1f-stud jump (reach %.1f)", d, W * tLand))
		local x0, y0, z0 = p.x, p.y, p.z
		local tt = 0
		while tt + DT < tLand do
			tt += DT
			p.x, p.z = x0 + dx * tt / tLand, z0 + dz * tt / tLand
			p.y = y0 + J * tt - GRAV * tt * tt / 2
			emit()
		end
		p.x, p.y, p.z = x, y, z
		emit()
	end
	-- dropped from rest to a surface whose standing root height is `y`
	function r.fall(y)
		local y0, tt = p.y, 0
		while true do
			tt += DT
			local ny = y0 - GRAV * tt * tt / 2
			if ny <= y then p.y = y; emit(); return end
			p.y = ny; emit()
		end
	end
	-- THE SHAFT out of storey s. `stride` 1 takes every pad; 2 takes every other one (a 6-stud rise,
	-- 0.32 s in the air), which is the fastest climb the pads allow. `missAt` falls off that pad once.
	function r.climb(s, stride, missAt)
		local sh = model.shafts[s + 1]
		local floorY = s * HS + ROOT
		local lip = C.Ascent.StandRadius * 0.9   -- how far from a pad's centre a runner in a hurry lands
		local k = 0
		local missed = false
		while k < #sh.pads do
			local nk = math.min(k + stride, #sh.pads)
			local pad = sh.pads[nk]
			local dx, dz = pad.x - p.x, pad.z - p.z
			local d = math.sqrt(dx * dx + dz * dz)
			local tx, tz = pad.x, pad.z
			if d > lip then tx, tz = pad.x - dx / d * lip, pad.z - dz / d * lip end
			-- as far toward it as what they stand on allows, then jump
			local rise = pad.y + ROOT - p.y
			local tLand = (J + math.sqrt(J * J - 2 * GRAV * rise)) / GRAV
			local need = math.sqrt((tx - p.x) ^ 2 + (tz - p.z) ^ 2)
			local carry = W * tLand * 0.98
			if need > carry then
				r.walkTo(p.x + (tx - p.x) / need * (need - carry), p.z + (tz - p.z) / need * (need - carry))
			end
			if missAt == nk and not missed then
				missed = true
				r.walkTo((p.x + tx) / 2, (p.z + tz) / 2)   -- short of the pad, into the gap
				r.fall(floorY)
				k = 0
			else
				r.jump(tx, tz, pad.y + ROOT)
				k = nk
			end
		end
		-- pad 6 is flush with the floor above: a step, not a jump
		p.y = (s + 1) * HS + ROOT
	end
	-- the whole vault, honestly: across each storey to its stairwell, up the shaft, and out
	function r.run(plan)
		plan = plan or {}
		r.settle(ROOT)
		for s = 0, model.storeys - 1 do
			local ex_x, ex_z = cellCentre(model, model.exitCells[s + 1])
			if plan.before then plan.before(r, s) end
			r.cross(s, ex_x, ex_z)
			if s < model.storeys - 1 then
				r.climb(s, plan.stride or 1, plan.missAt and plan.missAt[s] or nil)
			end
		end
		r.stand(2)
		return r.samples
	end
	return r
end

--============================================================================ 3. the honest runner is ranked

local honestCases = { { 1, 1 }, { 1, 12 }, { 2, 1 }, { 2, 20 }, { 3, 1 }, { 3, 30 }, { 3, 400 } }

do
	local worstSpare, rejects, runs = math.huge, 0, 0
	for _, tf in ipairs(honestCases) do
		for _, line in ipairs({ "racing", "centres" }) do
			for _, stride in ipairs({ 1, 2 }) do
				local model = VM:vault(tf[1], tf[2])
				local res = judge(model, newRunner(model, { line = line }).run({ stride = stride }))
				runs += 1
				ok(res.escaped and res.traced, string.format(
					"an honest runner is RANKED: tier %d floor %d, %s line, stride %d (%s)", tf[1], tf[2], line, stride, tostring(res.why)))
				rejects += res.gate.rejected
				worstSpare = math.min(worstSpare, res.minSpare)
			end
		end
	end
	print(string.format("  honest, full speed, %d runs: %d samples refused; the flat bank never under %.2f studs after an accepted sample", runs, rejects, worstSpare))
	ok(rejects == 0, "and not ONE of their samples was refused on the way (" .. rejects .. ")")
	ok(worstSpare >= 0, "the bank never went negative")
end

-- The margin on speed, measured: how much FASTER than a runner the same racing line can be walked
-- before the gate refuses a single sample. It has to be well over 1, or an honest runner is on the edge.
do
	local model = VM:vault(3, 1)
	local lastClean, lastRanked = 1, 1
	local cleanOpen, rankedOpen = true, true
	local refusedAt160 = 0
	for f = 100, 300, 5 do
		local res = judge(model, newRunner(model, { line = "racing", speedFactor = f / 100 }).run({ stride = 1 }))
		local ranked = res.escaped and res.traced
		if cleanOpen and ranked and res.gate.rejected == 0 then lastClean = f / 100 else cleanOpen = false end
		if rankedOpen and ranked then lastRanked = f / 100 else rankedOpen = false end
		if f == 160 then refusedAt160 = res.gate.rejected end
	end
	print(string.format("  speed margin: the racing line is walked with NO sample refused up to %.2fx WalkSpeed; a flat-out speeder who still climbs honestly keeps the rank up to %.2fx (the bank refills in every shaft)",
		lastClean, lastRanked))
	ok(lastClean >= 1.25, string.format("an honest runner has at least 25%% of speed in hand before one sample is refused (%.2fx)", lastClean))
	ok(refusedAt160 > 0, "and at 1.6x the gate is refusing samples (" .. refusedAt160 .. ")")
end

-- The climb, measured: the fastest chain the pads allow against the upward allowance.
do
	local model = VM:vault(3, 1)
	local r = newRunner(model, { line = "racing" })
	r.settle(ROOT)
	local hx, hz = cellCentre(model, model.exitCells[1])
	r.walkTo(hx, hz)   -- (placed in the stairwell; the gate below starts here)
	local gate = FlierGate.new(C, model, r.pos())
	for _ = 1, 1 / DT do FlierGate.step(gate, model, r.pos(), DT) end   -- one second on their feet
	local n0 = #r.samples
	r.climb(0, 2, nil)
	local refused, peak, t = 0, 0, 0
	for i = n0 + 1, #r.samples do
		t += DT
		peak = math.max(peak, r.samples[i].y - r.samples[i - 1].y)
		if not FlierGate.step(gate, model, r.samples[i], DT) then refused += 1 end
	end
	local rate = HS / t
	print(string.format("  the fastest climb the pads allow: %.0f studs in %.2f s = %.1f studs/s, against an allowance of %.2f (x%.2f); the biggest single sample is %.2f studs up against %.2f a sample (the bank pays the start of a jump)",
		HS, t, rate, upRate, upRate / rate, peak, upRate * DT))
	ok(refused == 0, "a runner chaining double hops up the shaft is never refused (" .. refused .. ")")
	ok(upRate / rate > 1.2, "with at least 20% in hand")
end

--============================================================================ 4. falls, drops, knocks

do
	local model = VM:vault(3, 30)
	-- a missed hop on every shaft: fifteen studs down, and up again
	local missAt = {}
	for s = 0, model.storeys - 2 do missAt[s] = 5 end
	local res = judge(model, newRunner(model, { line = "racing" }).run({ stride = 1, missAt = missAt }))
	ok(res.escaped and res.traced and res.gate.rejected == 0,
		"a runner who falls off pad 4 of every shaft and climbs again is ranked, no sample refused (" .. res.gate.rejected .. ")")

	-- jumping all the way across every storey (6.4 studs up, 25 studs/s at the start of each jump)
	local resH = judge(model, newRunner(model, { line = "racing", hop = true }).run({ stride = 1 }))
	ok(resH.escaped and resH.traced and resH.gate.rejected == 0,
		"a runner who jumps the whole way across every storey is ranked, no sample refused (" .. resH.gate.rejected .. ")")

	-- a drop back DOWN the hole from the storey above, then up again
	local res2 = judge(model, newRunner(model, { line = "racing" }).run({ stride = 1, before = function(r, s)
		if s == 1 then
			local hx, hz = cellCentre(model, model.entryCells[2])
			r.walkTo(hx, hz)            -- back over the hole they just came out of...
			r.fall(0 * HS + ROOT)       -- ...and down it, eighteen studs
			r.climb(0, 1, nil)
		end
	end }))
	ok(res2.escaped and res2.traced and res2.gate.rejected == 0,
		"a runner who drops back down the hole to the storey below and climbs out again is ranked (" .. res2.gate.rejected .. " refused)")

	-- the ceiling drop's knock: Hazards.MaxKnock studs/s for KnockSeconds, with its little lift
	local Hz = C.Hazards
	local res3 = judge(model, newRunner(model, { line = "racing" }).run({ stride = 1, before = function(r, s)
		if s ~= 2 then return end
		local ex_x, ex_z = cellCentre(model, model.exitCells[s + 1])
		local pts = FlierGate.path(model, s, r.pos(), at(ex_x, 0, ex_z))
		-- knocked along the corridor they are in, both ways: forward (the worst for speed), then back
		for _, sign in ipairs({ 1, -1 }) do
			local p0 = r.pos()
			local dx, dz = (pts[2].x - p0.x) * sign, (pts[2].z - p0.z) * sign
			local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-6)
			local slide = math.min(Hz.MaxKnock * Hz.KnockSeconds, d - 0.5, 5)
			r.settle(p0.y + Hz.KnockLift * DT)
			r.walkTo(p0.x + dx / d * slide, p0.z + dz / d * slide, Hz.MaxKnock)
			r.settle(s * HS + ROOT - 2)   -- lying on the floor (PlatformStand)
			r.stand(Hz.KnockSeconds)
			r.settle(s * HS + ROOT)
		end
	end }))
	ok(res3.escaped and res3.traced and res3.gate.rejected == 0,
		"a runner knocked down by a ceiling drop (MaxKnock for KnockSeconds, twice) is ranked (" .. res3.gate.rejected .. " refused)")
	ok(Hz.MaxKnock < flatRate, string.format("the hardest knock (%d studs/s) is slower than the flat allowance (%.1f)", Hz.MaxKnock, flatRate))
end

--============================================================================ 5. lag

-- A client that stops replicating for `gap` seconds: the server reads the same position every
-- sample, then the runner is suddenly where they have run to in the meantime.
local function lagged(samples, fromT, gap)
	local out, frozen = {}, nil
	for _, smp in ipairs(samples) do
		if smp.t >= fromT and smp.t < fromT + gap then
			frozen = frozen or smp
			out[#out + 1] = { x = frozen.x, y = frozen.y, z = frozen.z, dt = smp.dt, t = smp.t }
		else
			out[#out + 1] = smp
		end
	end
	return out
end

do
	local limit = G.BurstSeconds * G.SpeedFactor
	local model = VM:vault(3, 30)
	local base = newRunner(model, { line = "racing" }).run({ stride = 1 })
	local total = base[#base].t
	local worstOk, firstLost = 0, nil
	for _, gap in ipairs({ 1, 2, 3, 4, 5, 5.5, 6, 7, 9 }) do
		local all = true
		-- the gap dropped at every point of the run in turn, including across a climb
		for fromT = 1, total - gap - 2.5, 2.3 do
			local res = judge(model, lagged(base, fromT, gap))
			if not (res.escaped and res.traced) then all = false end
		end
		if all then worstOk = gap elseif firstLost == nil then firstLost = gap end
	end
	print(string.format("  lag: a full-speed runner frozen for up to %.1f s ANYWHERE in a Gold floor-30 run is still ranked (BurstSeconds x SpeedFactor = %.1f s); first lost at %s s",
		worstOk, limit, tostring(firstLost)))
	ok(worstOk >= 5, "a five-second lag gap at full speed, anywhere in the run, never costs the rank (" .. worstOk .. ")")
	ok(firstLost ~= nil and firstLost <= 9, "and the bank IS capped: a gap far past it is not waved through (" .. tostring(firstLost) .. ")")

	-- ...and a slower runner has more: the cap is a distance, not a time
	local slow = newRunner(model, { line = "centres", speedFactor = 0.6 }).run({ stride = 1 })
	local res = judge(model, lagged(slow, 12, 8))
	ok(res.escaped and res.traced, "a runner at 60% speed survives an eight-second gap (the cap is studs of route, not seconds)")

	-- jitter: every sample arrives late and in bursts (0, 0, 0, then four samples' worth at once)
	local bursty = {}
	for i, smp in ipairs(base) do
		local hold = base[math.max(1, (i - 1) // 4 * 4)]
		bursty[i] = if i % 4 == 0 then smp else { x = hold.x, y = hold.y, z = hold.z, dt = smp.dt, t = smp.t }
	end
	local resB = judge(model, bursty)
	ok(resB.escaped and resB.traced, "positions arriving four samples at a time (0.2 s bursts) are ranked")

	-- one garbage sample (the hub, a nan) in the middle of an honest run changes nothing
	local dirty = table.clone(base)
	local mid = #dirty // 2
	dirty[mid] = { x = 0, y = -246, z = 0, dt = DT, t = dirty[mid].t }
	dirty[mid + 40] = { x = 0 / 0, y = 3, z = 0, dt = DT, t = dirty[mid + 40].t }
	dirty[mid + 80] = { x = dirty[mid + 80].x, y = dirty[mid + 80].y, z = dirty[mid + 80].z, dt = 0 / 0, t = dirty[mid + 80].t }
	local resD = judge(model, dirty)
	ok(resD.escaped and resD.traced, "a stray sample from outside the vault, a nan position and a nan dt are refused and forgotten")
	ok(resD.gate.rejected >= 2 and resD.gate.rejected <= 3, "(they WERE refused: " .. resD.gate.rejected .. ")")
end

--============================================================================ 6. the game's own player model

-- tests/VaultModel.luau is the model every completion number in this repo comes from. Here it is
-- run at the top speed the game has (SpeedFactor 1, no pauses), over a spread of floors, with its
-- position handed to the gate sample by sample. Its climb teleports three studs up per hop (it has
-- no arc), which is harsher on the upward allowance than a jump is.
do
	local profile = { SpeedFactor = 1, JunctionPauseSeconds = 0, RetryPauseSeconds = 0, MissChance = 0.08,
		HubSecondsPerAttempt = 0, StunSeconds = 1.2, ReactSeconds = 0.5, NearStuds = 8 }
	local runs, escaped, traced, refused, samples = 0, 0, 0, 0, 0
	for tier = 1, 3 do
		for _, floor in ipairs({ 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233 }) do
			for _, retry in ipairs({ false, true }) do
				local model, spec = VM:vault(tier, floor)
				local gate = FlierGate.new(C, model, model.spawn.position)
				local last = nil
				local res = VM:play(model, spec, {
					profile = profile, retry = retry, rand = VaultModel.lcg(tier * 1000 + floor), dt = DT, hazards = "off",
					onSample = function(x, y, z)
						last = at(x, y, z)
						samples += 1
						if not FlierGate.step(gate, model, last, DT) then refused += 1 end
					end,
				})
				runs += 1
				if res.escaped then
					escaped += 1
					if FlierGate.traced(C, gate, model) then traced += 1 end
				end
			end
		end
	end
	print(string.format("  VaultModel at full speed: %d runs, %d escaped, %d of those ranked; %d of %d samples refused",
		runs, escaped, traced, refused, samples))
	ok(samples > 50000, "the model's position reached the gate (" .. samples .. " samples)")
	ok(escaped >= 30, "enough of the model's runs escape to mean something (" .. escaped .. ")")
	ok(traced == escaped, string.format("EVERY escape the game's own player model makes is ranked (%d of %d)", traced, escaped))
	ok(refused == 0, "and none of its samples is refused (" .. refused .. ")")
end

--============================================================================ 7. the flier is not ranked

local function straight(model, speed, upSpeed, seconds)
	-- a noclip run: from the drop-in in a straight line to the exit, through whatever is in the way
	local out = {}
	local p = at(model.spawn.position.x, model.spawn.position.y, model.spawn.position.z)
	local e = model.exit.position
	for _ = 1, math.ceil(seconds / DT) do
		local dx, dz = e.x - p.x, e.z - p.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 1e-9 then
			local m = math.min(d, speed * DT)
			p.x += dx / d * m; p.z += dz / d * m
		end
		p.y = math.min(e.y, p.y + upSpeed * DT)
		out[#out + 1] = { x = p.x, y = p.y, z = p.z, dt = DT }
	end
	return out
end

do
	local fliers, escaped, ranked = 0, 0, 0
	local fastest = math.huge
	for tier = 1, 3 do
		for floor = 1, 60, (tier == 3 and 3 or 7) do
			local model = VM:vault(tier, floor)
			local e = model.exit.position
			for _, kind in ipairs({ "teleport", "fly", "sprintfly" }) do
				local samples
				if kind == "teleport" then
					samples = {}
					for _ = 1, 120 / DT do samples[#samples + 1] = { x = e.x, y = e.y, z = e.z, dt = DT } end
				elseif kind == "fly" then
					samples = straight(model, W, W, 120)
				else
					samples = straight(model, flatRate, upRate, 120)   -- exactly as fast as the gate allows, in a straight line
				end
				local res = judge(model, samples)
				fliers += 1
				if res.escaped then escaped += 1; fastest = math.min(fastest, res.t) end
				if res.escaped and res.traced then ranked += 1 end
			end
		end
	end
	print(string.format("  fliers: %d straight-line runs, %d escaped (the economy is unchanged; fastest %.1f s), %d ranked", fliers, escaped, fastest, ranked))
	ok(escaped == fliers, "CONTROL: every one of them still ESCAPES (Trace lets them, and the gate does not touch the economy)")
	ok(ranked == 0, "and NOT ONE of them is ranked (" .. ranked .. " of " .. fliers .. ")")
end

do
	local model = VM:vault(3, 1)
	local e = model.exit.position
	local sp = model.spawn.position
	local m = VaultPath.measure(C, model)

	-- PATIENCE. Wait at the drop-in for as long as the whole route takes a perfect runner, then
	-- teleport: time alone must not buy the route. This is what the cap on the bank is for.
	local samples = {}
	for _ = 1, math.ceil((m.totalSeconds + 5) / DT) do samples[#samples + 1] = { x = sp.x, y = ROOT, z = sp.z, dt = DT } end
	for _ = 1, 60 / DT do samples[#samples + 1] = { x = e.x, y = e.y, z = e.z, dt = DT } end
	local res = judge(model, samples)
	ok(res.escaped and not res.traced, string.format(
		"waiting %.0f s at the drop-in and then teleporting to the exit escapes, and is not ranked", m.totalSeconds + 5))

	-- BACK IN STEP FOR THE LAST SAMPLE. Claim the exit until the trusted position is nearly there,
	-- then claim the drop-in column again (which the gate accepts) while the trusted position coasts
	-- in. Whether or not Trace banks that, it is never ranked: what must reach the exit is the
	-- VALIDATED position, not the latest accepted sample.
	local trace = Trace.new(C, sp)
	local gate = FlierGate.new(C, model, sp)
	local banked, rankedAny, acceptedBack = false, false, 0
	for i = 1, 200 / DT do
		local tp = at(trace.x, trace.y, trace.z)
		local closeIn = dist3(tp, e) <= C.Run.ExitRadius + 1.2
		local claim = if closeIn then at(sp.x, ROOT, sp.z) else at(e.x, e.y, e.z)
		tp = Trace.step(trace, claim, DT)
		if FlierGate.step(gate, model, claim, DT) and closeIn then acceptedBack += 1 end
		if i % 4 == 0 and dist3(tp, e) <= C.Run.ExitRadius then
			banked = true
			if FlierGate.traced(C, gate, model) then rankedAny = true end
			break
		end
	end
	print("  the in-step trick: banked by Trace = " .. tostring(banked) .. ", samples accepted back at the drop-in = " .. acceptedBack)
	-- (Trace follows a claim DOWN at once, so stepping back to the drop-in drops the trusted position
	-- too and this trick does not even bank: `banked` reads false and nothing above can fail. It is
	-- kept as a record of the attempt. The rule itself is asserted directly below.)
	ok(acceptedBack > 0 and not rankedAny, "stepping back to an accepted position for the last sample is not ranked")
	-- a gate whose validated position is at the drop-in, IN STEP (its last sample accepted), with a FULL bank
	local gFull = FlierGate.new(C, model, sp)
	for _ = 1, 60 / DT do FlierGate.step(gFull, model, at(sp.x, ROOT, sp.z), DT) end
	ok(gFull.accepted > 0 and not FlierGate.traced(C, gFull, model), "in step at the drop-in with a full bank is not at the exit")
	-- directly UNDER the exit, one storey down: nine studs short in height is inside ExitRadius, the floor between is not
	local gUnder = FlierGate.new(C, model, at(e.x, e.y - HS, e.z))
	for _ = 1, 60 / DT do FlierGate.step(gUnder, model, at(e.x, e.y - HS, e.z), DT) end
	ok(not FlierGate.traced(C, gUnder, model), "standing under the exit on the storey below is not at the exit")
	local gAt = FlierGate.new(C, model, at(e.x + 4, e.y, e.z))
	FlierGate.step(gAt, model, at(e.x + 4, e.y, e.z), DT)
	ok(FlierGate.traced(C, gAt, model), "CONTROL: a validated position on the exit pad is at the exit")

	-- UP THROUGH THE FLOOR. Straight up from a cell that is not the stairwell: refused, however slowly.
	local g2 = FlierGate.new(C, model, sp)
	local refusedAbove = true
	for i = 1, 30 / DT do
		local y = math.min(ROOT + HS, ROOT + i * DT * 2)   -- two studs a second
		local acc = FlierGate.step(g2, model, at(sp.x, y, sp.z), DT)
		if y >= HS and acc then refusedAbove = false end
	end
	ok(refusedAbove, "rising through the ceiling anywhere but the stairwell is refused at any speed")
	ok(g2.y < HS, "and the validated position stayed on the storey below (" .. string.format("%.1f", g2.y) .. ")")

	-- ...and up the stairwell itself is the legitimate way, so the same rise there is accepted.
	local hx, hz = cellCentre(model, model.exitCells[1])
	local g3 = FlierGate.new(C, model, at(hx, ROOT, hz))
	local okAll = true
	for i = 1, 12 / DT do
		local y = math.min(ROOT + HS, ROOT + i * DT * 2)
		if not FlierGate.step(g3, model, at(hx, y, hz), DT) then okAll = false end
	end
	ok(okAll and math.abs(g3.y - (ROOT + HS)) < 1e-6, "CONTROL: the same rise up the stairwell is accepted all the way")

	-- ...but not five storeys of it at once: the stairwell is a way up, not a lift.
	local g4 = FlierGate.new(C, model, at(hx, ROOT, hz))
	FlierGate.step(g4, model, at(hx, ROOT, hz), DT)
	ok(not FlierGate.step(g4, model, at(hx, ROOT + HS, hz), DT), "a whole storey in one sample is refused even in the stairwell")

	-- THROUGH A WALL. Two points a wall apart whose corridor is longer than the whole bank.
	local found = nil
	for s = 0, model.storeys - 1 do
		for cy = 0, model.cells - 1 do
			for cx = 0, model.cells - 2 do
				local a, b = { cx = cx, cy = cy }, { cx = cx + 1, cy = cy }
				if model.grids[s + 1][2 * cy + 1][2 * cx + 2] == true then
					local ax, az = cellCentre(model, a)
					local bx, bz = cellCentre(model, b)
					local _, l = FlierGate.path(model, s, at(ax, 0, az), at(bx, 0, bz))
					if l ~= nil and l > flatRate * G.BurstSeconds + 20 and found == nil then
						found = { s = s, ax = ax, az = az, bx = bx, bz = bz, l = l }
					end
				end
			end
		end
	end
	ok(found ~= nil, "set-up: Gold floor 1 has two neighbouring cells whose corridor is longer than the bank")
	if found then
		local y = found.s * HS + ROOT
		local g5 = FlierGate.new(C, model, at(found.ax, y, found.az))
		for _ = 1, 60 / DT do FlierGate.step(g5, model, at(found.ax, y, found.az), DT) end   -- a full bank
		near(g5.budgetH, flatRate * G.BurstSeconds, 1e-6, "the bank stops at BurstSeconds of allowance however long they wait")
		local acc = FlierGate.step(g5, model, at(found.bx, y, found.bz), DT)
		ok(not acc, string.format("stepping through a wall (24 studs apart, %.0f studs by corridor) is refused with a full bank", found.l))
		-- the wall itself
		ok(not FlierGate.step(g5, model, at((found.ax + found.bx) / 2, y, found.az), DT), "and so is standing inside the wall")
		near(g5.x, found.ax, 1e-9, "the validated position did not move")
	end

	-- A WALL HOP THE BANK CAN PAY FOR is charged the CORRIDOR, not the hop.
	local short = nil
	for cy = 0, model.cells - 1 do
		for cx = 0, model.cells - 2 do
			if model.grids[1][2 * cy + 1][2 * cx + 2] == true and short == nil then
				local ax, az = cellCentre(model, { cx = cx, cy = cy })
				local bx, bz = cellCentre(model, { cx = cx + 1, cy = cy })
				local _, l = FlierGate.path(model, 0, at(ax, 0, az), at(bx, 0, bz))
				if l ~= nil and l < flatRate * G.BurstSeconds - 10 then short = { ax = ax, az = az, bx = bx, bz = bz, l = l } end
			end
		end
	end
	if short then
		local g6 = FlierGate.new(C, model, at(short.ax, ROOT, short.az))
		for _ = 1, 60 / DT do FlierGate.step(g6, model, at(short.ax, ROOT, short.az), DT) end
		local before = g6.budgetH
		ok(FlierGate.step(g6, model, at(short.bx, ROOT, short.bz), DT), "a wall hop whose corridor the bank covers is accepted (it is what a lag gap looks like)")
		near(before - g6.budgetH, short.l, 1e-6, string.format("and it cost the %.0f studs of corridor, not the 24 of the hop", short.l))
	end
	ok(short ~= nil, "set-up: Gold floor 1 has a wall hop whose corridor the bank covers")
end

--============================================================================ 8. where a position is

do
	local model = VM:vault(1, 1)
	local sp = model.spawn.position
	ok(FlierGate.locate(model, sp, G.WallTolerance) ~= nil, "the drop-in is a place")
	local loc = FlierGate.locate(model, at(sp.x, HS + ROOT, sp.z), G.WallTolerance)
	ok(loc ~= nil and loc.storey == 1, "a height one storey up is storey 1")
	ok(FlierGate.locate(model, at(sp.x, -0.5, sp.z), G.WallTolerance) == nil, "under the ground floor is nowhere")
	ok(FlierGate.locate(model, at(sp.x, model.storeys * HS + 1, sp.z), G.WallTolerance) == nil, "above the top storey is nowhere")
	ok(FlierGate.locate(model, at(1e6, ROOT, 0), G.WallTolerance) == nil, "outside the vault is nowhere")
	ok(FlierGate.locate(model, at(0 / 0, ROOT, 0), G.WallTolerance) == nil, "a nan is nowhere")
	-- the drop-in cell's outer wall: 6 studs from its centre
	local wx = sp.x - S / 2
	local skin = FlierGate.locate(model, at(wx - G.WallTolerance + 0.01, ROOT, sp.z), G.WallTolerance)
	ok(skin ~= nil and math.abs(skin.x - wx) < 1e-9, "a root pressed a hair into a wall is pulled back to the corridor's edge")
	ok(FlierGate.locate(model, at(wx - G.WallTolerance - 0.01, ROOT, sp.z), G.WallTolerance) == nil, "past the tolerance it is in the wall")
end

--============================================================================ 9. the server moved them

do
	local model = VM:vault(1, 1)
	local gate = FlierGate.new(C, model, model.spawn.position)
	for _ = 1, 100 do FlierGate.step(gate, model, model.spawn.position, DT) end
	ok(gate.budgetH > 0, "set-up: a bank was built")
	local ex, ez = cellCentre(model, model.exitCells[1])
	FlierGate.reseed(gate, at(ex, ROOT, ez))
	near(gate.x, ex, 1e-9, "after a move the SERVER made, the validated position is where the server put them")
	near(gate.budgetH, 0, 1e-9, "and the bank starts again from nothing, like a new run's")
	ok(FlierGate.step(gate, model, at(ex + 0.5, ROOT, ez), DT), "and the run carries on from there")
end

--============================================================================ 10. pure

do
	local model = VM:vault(2, 5)
	local a = judge(model, newRunner(model, { line = "racing" }).run({ stride = 1 }))
	local b = judge(model, newRunner(model, { line = "racing" }).run({ stride = 1 }))
	ok(a.t == b.t and a.gate.accepted == b.gate.accepted and a.gate.budgetH == b.gate.budgetH, "the same run gives the same verdict, to the bit")
	-- CONTROL: the gate reads the vault and the movement numbers, nothing else
	local painted = {}
	for k, v in pairs(C) do painted[k] = v end
	painted.Hud = { AccentColor = { r = 255, g = 0, b = 255 }, DangerColor = { r = 0, g = 255, b = 0 }, PanelColor = { r = 0, g = 0, b = 0 } }
	local f1, u1 = FlierGate.speeds(painted)
	near(f1, flatRate, 1e-12, "CONTROL: repainting the HUD does not change the flat allowance")
	near(u1, upRate, 1e-12, "CONTROL: nor the upward one")
end

print(string.format("FlierGate: %d passed, %d failed", passed, failed))
if failed > 0 then error("FlierGate spec failed", 0) end
