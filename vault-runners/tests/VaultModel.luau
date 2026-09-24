-- VaultModel.luau — a TEST-SIDE model of a person playing Vault Runners. Never shipped, never
-- bundled (it lives in tests/, which wrap.py does not read).
--
-- It plays the real vaults: VaultFloor.build on the real seeds, the real countdown from
-- VaultPath.countdown, the real kill rule from RunState.caught, the real hazard scheduler
-- (Hazards) with the real eligibility (VaultEnv.hazardEligible). What it cannot know is how a
-- human moves, so that part is written down as a PROFILE (Config.Pacing) instead of being hidden
-- in a number:
--   * blind exploration, like tests/Curve.spec.luau's explorer: perfect memory, uniform choice at
--     junctions, one step back out of a dead end — at `SpeedFactor` x WalkSpeed, stopping
--     `JunctionPauseSeconds` at every junction the first time they reach it to read the maze;
--   * the climb rolled hop by hop at `MissChance` (twice what the countdown prices), a miss costing
--     the fall plus Config.Ascent.ModelReapproachSeconds;
--   * a floor they die on is REPLAYED: the vault is deterministic, so the retry walks the shortest
--     route it now knows (at RetryPauseSeconds per junction);
--   * gems are banked for the ones actually walked over, times the tier's value, on an escape;
--   * `HubSecondsPerAttempt` between runs (walk to the portal, read the toast);
--   * a new tier the moment it unlocks.
-- Hazard behaviour is a separate switch, because it is the thing being measured:
--   "reacts"  — a player who sees the ring and does not stop in it (cuts a junction pause short);
--   "ignores" — a player who never reacts: stands through the warning if they happened to stop;
--   "freezes" — stands still from the moment a drop appears (the ring's own sanity case).

local VaultModel = {}

local function lcg(seed: number)
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	return function(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end
VaultModel.lcg = lcg

function VaultModel.new(deps: any): any
	local self = setmetatable({}, { __index = VaultModel })
	for k, v in deps do self[k] = v end
	return self
end

local function openNeighbours(grid: any, cells: number, cx: number, cy: number): { { number } }
	local out = {}
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local nx, ny = cx + d[1], cy + d[2]
		if nx >= 0 and nx < cells and ny >= 0 and ny < cells then
			if grid[2 * cy + 1 + d[2]][2 * cx + 1 + d[1]] == false then out[#out + 1] = { nx, ny } end
		end
	end
	return out
end

local function bfsPath(grid: any, cells: number, from: any, to: any): { { number } }
	local function id(cx: number, cy: number): number return cy * cells + cx end
	local prev = { [id(from.cx, from.cy)] = -1 }
	local q, head = { { from.cx, from.cy } }, 1
	while head <= #q do
		local c = q[head]; head += 1
		if c[1] == to.cx and c[2] == to.cy then break end
		for _, n in openNeighbours(grid, cells, c[1], c[2]) do
			local k = id(n[1], n[2])
			if prev[k] == nil then prev[k] = id(c[1], c[2]); q[#q + 1] = n end
		end
	end
	local path, k = {}, id(to.cx, to.cy)
	while k ~= -1 and k ~= nil do
		table.insert(path, 1, { k % cells, k // cells })
		k = prev[k]
	end
	return path
end

-- Build the vault a run is played in, exactly as the server does.
function VaultModel.vault(self: any, tier: number, floor: number, seed: number?): (any, any)
	local C = self.Config
	local spec = self.Progression.difficulty(C, tier, floor)
	spec.seed = seed or self.Progression.seedFor(C, tier, floor)
	local model = self.VaultFloor.build(C, spec, self.MazeGen, self.Rng)
	spec.collapseSeconds = self.VaultPath.countdown(C, model, spec.slack, self.VaultFloor)
	return model, spec
end

-- Play ONE run. opts = { profile, retry: boolean, rand, hazards: "off"|"reacts"|"ignores"|"freezes",
--   hazardState (a Hazards scheduler carried across runs), hazRand, dt }.
-- Returns { escaped, time, gems, hazards = { spawned, hits, near, landings = { distance } }, lost }.
function VaultModel.play(self: any, model: any, spec: any, opts: any): any
	local C = self.Config
	local P = opts.profile
	local rand = opts.rand
	local dt = opts.dt or 0.1
	local speed = C.Movement.WalkSpeed * P.SpeedFactor
	local S, Hh = model.cellSize, model.storeyHeight
	local rootH = C.Run.RunnerRootHeight
	local run = self.RunState.start(C, spec, 0)
	local cells = model.cells

	local function centre(cx: number, cy: number): (number, number)
		return (2 * cx + 1 - (model.gCols - 1) / 2) * S, (2 * cy + 1 - (model.gRows - 1) / 2) * S
	end

	-- gem lookup by storey + cell
	local gemAt = {}
	for _, g in model.gems do
		gemAt[g.storey * 100000 + g.cell.cy * 1000 + g.cell.cx] = g
	end
	local banked = 0

	local storey = 0
	local cur = { model.entryCells[1].cx, model.entryCells[1].cy }
	local px, pz = centre(cur[1], cur[2])
	local py = rootH
	local visited, stack, route, routeI = {}, {}, nil, 1
	local function id(cx: number, cy: number): number return cy * cells + cx end
	local function beginStorey()
		local en = model.entryCells[storey + 1]
		cur = { en.cx, en.cy }
		visited = { [id(en.cx, en.cy)] = true }
		stack = { { en.cx, en.cy } }
		if opts.retry then
			route = bfsPath(model.grids[storey + 1], cells, en, model.exitCells[storey + 1])
			routeI = 1
		end
	end
	beginStorey()

	local target: { number }? = nil -- maze cell we are walking to
	local pause = 0
	local seenJunction = {}
	local climbing, hop, hopT, fallT = false, 0, 0, 0
	local stun = 0
	local t = 0
	local out = { escaped = false, time = 0, gems = 0, hz = { spawned = 0, hits = 0, near = 0, landings = {} }, lost = 0 }

	local H = C.Hazards
	local hzOn = opts.hazards ~= nil and opts.hazards ~= "off"
	local hs = opts.hazardState
	local hzRand = opts.hazRand
	local bandKinds = opts.kinds or {}
	local lastT = 0

	local function collectHere()
		-- RunState.collect refuses a second pickup, so walking a gem cell twice counts once
		local g = gemAt[storey * 100000 + cur[2] * 1000 + cur[1]]
		if g then self.RunState.collect(run, g.id, g.value, t) end
	end
	collectHere()

	local function chooseNext(): { number }?
		if opts.retry then
			routeI += 1
			return route[routeI]
		end
		local here = stack[#stack]
		local options = {}
		for _, n in openNeighbours(model.grids[storey + 1], cells, here[1], here[2]) do
			if not visited[id(n[1], n[2])] then options[#options + 1] = n end
		end
		if #options == 0 then
			table.remove(stack)
			return stack[#stack]
		end
		local pick = options[1 + math.floor(rand() * #options)]
		visited[id(pick[1], pick[2])] = true
		stack[#stack + 1] = pick
		return pick
	end

	local guard = 0
	while true do
		guard += 1
		if guard > 200000 then break end
		t += dt
		local frozenByHazard = hzOn and opts.hazards == "freezes" and hs and hs.active ~= nil
		-- movement
		if stun > 0 then
			stun -= dt
		elseif frozenByHazard then
			-- stands still through the whole warning
		elseif climbing then
			if fallT > 0 then
				fallT -= dt
				if fallT <= 0 then py = storey * Hh + rootH; hop = 0; hopT = 0 end
			else
				hopT += dt
				if hopT >= C.Movement.ClimbSecondsPerStep then
					hopT = 0
					if rand() < P.MissChance then
						local drop = hop * model.stepRise
						fallT = self.VaultPath.fallSeconds(C, drop) + C.Ascent.ModelReapproachSeconds
					else
						hop += 1
						py = storey * Hh + rootH + hop * model.stepRise
						if hop >= math.floor(Hh / model.stepRise) then
							climbing = false
							storey += 1
							py = storey * Hh + rootH
							beginStorey()
							target = nil
						end
					end
				end
			end
		elseif pause > 0 then
			pause -= dt
			-- a player who reacts stops reading the maze once they have seen the ring (ReactSeconds in)
			if hzOn and opts.hazards == "reacts" and hs and hs.active ~= nil and hs.active.t >= P.ReactSeconds then pause = 0 end
		elseif hzOn and opts.hazards == "reacts" and hs and hs.active ~= nil and hs.active.locked and hs.active.t < hs.active.arriveAt
			and target ~= nil and (function()
				-- ...and does not walk INTO a red ring that has not landed yet: they wait a moment
				local tx, tz = centre(target[1], target[2])
				local dx, dz = tx - px, tz - pz
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 1e-6 then return false end
				local step = math.min(d, speed * dt)
				local nx, nz = px + dx / d * step, pz + dz / d * step
				local here = self.Hazards.inZone(hs.active, { x = px, y = py, z = pz }, C.Hazards.PlayerRadius)
				local there = self.Hazards.inZone(hs.active, { x = nx, y = py, z = nz }, C.Hazards.PlayerRadius)
				return there and not here
			end)() then
			-- waiting at the rim
		else
			if target == nil then
				local ex = model.exitCells[storey + 1]
				if cur[1] == ex.cx and cur[2] == ex.cy then
					if storey == model.storeys - 1 then
						local res = self.RunState.tryEscape(run, 1, t)
						out.escaped = res.ok
						out.time = t
						out.gems = res.banked
						break
					end
					climbing, hop, hopT = true, 0, 0
				else
					target = chooseNext()
					if target == nil then break end
				end
			end
			if target ~= nil then
				local tx, tz = centre(target[1], target[2])
				local dx, dz = tx - px, tz - pz
				local d = math.sqrt(dx * dx + dz * dz)
				local stepLen = speed * dt
				if d <= stepLen then
					px, pz = tx, tz
					cur = { target[1], target[2] }
					target = nil
					collectHere()
					local k = storey * 100000 + id(cur[1], cur[2])
					local nOpen = #openNeighbours(model.grids[storey + 1], cells, cur[1], cur[2])
					if nOpen >= 3 and not seenJunction[k] then
						seenJunction[k] = true
						pause = if opts.retry then P.RetryPauseSeconds else P.JunctionPauseSeconds
					end
				else
					px += dx / d * stepLen
					pz += dz / d * stepLen
				end
			end
		end

		-- the collapse and the seal, by the real rules
		if self.RunState.caught(run, model, py, t) then
			self.RunState.kill(run, t, "collapse")
			out.time = t
			break
		end
		if self.RunState.isSealed(run, t) then
			out.time = t
			break
		end

		-- hazards, by the real scheduler and the real eligibility
		if hzOn and hs then
			local pos = { x = px, y = py, z = pz }
			local planeY = self.RunState.planeY(run, model, t)
			local danger = self.VaultEnv.danger(C, model, planeY, py)
			local grounded = not climbing and stun <= 0
			local eligible = grounded and self.VaultEnv.hazardEligible(C, model, pos,
				{ elapsed = t, timeLeft = self.RunState.timeLeft(run, t), danger = danger })
			local before = if hs.active then hs.active.t else 0
			local ev = self.Hazards.step(hs, H, dt, { paused = false, eligible = eligible, kinds = bandKinds, aim = pos }, hzRand)
			if ev and ev.type == "spawn" then out.hz.spawned += 1 end
			local plan = hs.active or (ev and ev.type == "done" and ev.plan) or nil
			if plan and before < plan.arriveAt and plan.t >= plan.arriveAt then
				local z = self.Hazards.zone(plan, H.PlayerRadius)
				local ddx, ddz = px - z.x, pz - z.z
				local dist = math.sqrt(ddx * ddx + ddz * ddz)
				table.insert(out.hz.landings, dist)
				if self.Hazards.checkHit(plan, before, plan.t, pos, H.PlayerRadius) then
					plan.hit = true
					out.hz.hits += 1
					stun = P.StunSeconds
					pause = 0
				elseif dist <= P.NearStuds then
					out.hz.near += 1
				end
			end
		end
		lastT = t
	end
	if out.time == 0 then out.time = t end
	if not out.escaped then out.lost = run.lost + run.carried end
	if hs then self.Hazards.cancel(hs) end
	local _ = lastT
	return out
end

-- A normal player's career: Bronze from floor 1, each new tier the moment it unlocks.
-- Returns { reachedAt = { [bandIndex] = minutes }, runs, runMinutes, totalMinutes, hz = {...} }.
function VaultModel.career(self: any, opts: any): any
	local C = self.Config
	local P = opts.profile
	local bands = C.Env.Bands
	local rand = lcg(opts.seed or 20260923)
	local hzRand = lcg((opts.seed or 20260923) + 77)
	local hs = self.Hazards.newScheduler(C.Hazards, hzRand)
	local tier, floors, banked = 1, { 1, 1, 1 }, 0
	local attempt = 0
	local minutes, runMinutes = 0, 0
	local reachedAt = {}
	local runs = 0
	local hz = { spawned = 0, hits = 0, near = 0, landings = {}, runSeconds = 0 }
	local capMinutes = opts.capMinutes or 600
	local tierAt = { [1] = 0 }
	local unlocks = {}
	while minutes < capMinutes do
		local depth = self.VaultEnv.depth(C, tier, floors[tier])
		for i, b in bands do
			if reachedAt[i] == nil and depth >= b.from then reachedAt[i] = minutes end
		end
		if opts.stopWhenAll and reachedAt[#bands] ~= nil then break end
		local model, spec = self:vault(tier, floors[tier])
		local bandIdx = self.EnvBands.indexAt(bands, depth)
		local res = self:play(model, spec, {
			profile = P, retry = attempt > 0, rand = rand,
			hazards = opts.hazards or "off", hazardState = hs, hazRand = hzRand,
			kinds = bands[bandIdx].hazards or {},
		})
		runs += 1
		minutes += (res.time + P.HubSecondsPerAttempt) / 60
		runMinutes += res.time / 60
		hz.spawned += res.hz.spawned
		hz.hits += res.hz.hits
		hz.near += res.hz.near
		for _, d in res.hz.landings do table.insert(hz.landings, d) end
		if res.escaped then
			banked += res.gems
			floors[tier] += 1
			attempt = 0
			local nextTier = C.Tiers[tier + 1]
			if nextTier and banked >= nextTier.unlockGems then
				table.insert(unlocks, { tier = tier + 1, depthBefore = depth, minutes = minutes })
				tier += 1
				tierAt[tier] = minutes
			end
		else
			attempt += 1
		end
	end
	hz.runSeconds = runMinutes * 60
	return {
		reachedAt = reachedAt, runs = runs, runMinutes = runMinutes, totalMinutes = minutes,
		hz = hz, tierAt = tierAt, floors = floors, banked = banked, unlocks = unlocks,
	}
end

return VaultModel
