--!strict
-- RunState.luau — one run, as the server sees it (DESIGN §5). Pure; ServerScriptService.
--
-- phase: "ready" (in the antechamber, no clock yet) -> "running" (the line was crossed) ->
--        "finished" (the Door, with 3 seals) | "void" (a failed check, or the run cap).
--
-- step(run, dt, x, y, z) takes one Heartbeat sample of the root in lane-local coordinates and
-- returns events for the server to act on:
--   { type = "start", at }             the official clock started (interpolated crossing)
--   { type = "reveal", cells = {i} }   cells newly within RevealSteps of a visited cell (sent once)
--   { type = "seal", seal, count, at } a seal was taken (segment test: a fast step never skips one)
--   { type = "doorLocked", count }     the Door was reached with fewer than 3 seals (once per entry)
--   { type = "finish", timeMs }        the Door, with 3 seals: the official time
--   { type = "void", reason }          stopped, with a reason; nothing is revealed after this
-- No remote can reach any of this: the only input is the server's own sample of the root.
--
-- Dependencies come in as an argument (deps = { RunCheck, Grid, Dungeon }): a bare string require
-- resolves in the luau CLI and is invalid in Roblox, so this module requires nothing.

local RunState = {}

function RunState.new(cfg: any, world: any, deps: any): any
	return {
		cfg = cfg,
		world = world,
		deps = deps,
		guard = deps.RunCheck.new(cfg, world, deps.Dungeon.funnel),
		phase = "ready",
		clock = 0,
		startClock = nil,
		sealTaken = {},
		sealCount = 0,
		visited = {},
		visitedList = {},
		revealed = {},
		inDoorZone = false,
		away = false, -- ready phase: the last sample was outside the lane (ignored)
		x = nil,
		z = nil,
		voidAt = nil,
		timeMs = nil,
	}
end

local function revealNew(run: any, from: { number }, steps: number): { number }
	local set = run.deps.Dungeon.revealFrom(run.world, from, steps)
	local out = {}
	for c in set do
		if not run.revealed[c] then
			run.revealed[c] = true
			table.insert(out, c)
		end
	end
	table.sort(out)
	return out
end

-- The run begins in the antechamber: the antechamber counts as a visited cell joined to the
-- entrance, so the first batch is every cell within RevealSteps - 1 of the entrance.
function RunState.arrive(run: any): { any }
	local cfg = run.cfg
	local Grid, RunCheck = run.deps.Grid, run.deps.RunCheck
	local ax, az = Grid.centre(cfg.Grid.EntranceX, -1, cfg)
	run.x, run.z = ax, az
	RunCheck.arrive(run.guard, ax, az, 0)
	local cells = revealNew(run, { run.world.entrance }, cfg.Grid.RevealSteps - 1)
	return { { type = "reveal", cells = cells } }
end

local function void(run: any, reason: string): { any }
	run.phase = "void"
	run.voidAt = run.clock
	return { { type = "void", reason = reason } }
end

function RunState.step(run: any, dt: number, x: number, y: number, z: number): { any }
	if run.phase ~= "ready" and run.phase ~= "running" then return {} end
	local cfg = run.cfg
	local Grid, RunCheck = run.deps.Grid, run.deps.RunCheck
	local events = {}
	local prevClock = run.clock
	run.clock += dt
	local px, pz = run.x or x, run.z or z

	if run.clock > cfg.RunCapSeconds then
		return void(run, "The torches burned out (15 min). Run not counted.")
	end
	if run.phase == "ready" then
		-- Before the line no clock runs, so a sample from outside the lane is ignored rather than
		-- voided: right after the server's PivotTo a client-owned character can still report its old
		-- hub position for a frame or two (needs-Studio). But a client owns its character, so a
		-- script can ALSO step out on purpose, wait, and re-appear anywhere (REVIEW-1 finding 1: the
		-- ignored samples froze the guard's clock, the gap widened the continuity allowance, and the
		-- re-entry sample started the clock inside seal 1's circle). So the only way back in is the
		-- antechamber, as a fresh arrival: a re-entry anywhere else voids, before it can start a
		-- clock, take a seal or reveal a cell.
		local _, _, k0 = Grid.cellOf(x, z, cfg)
		if k0 == nil then
			run.away = true
			return events
		end
		if run.away then
			run.away = false
			if k0 ~= "ante" then
				return void(run, "Run not ranked: you re-appeared inside the halls without walking in from the antechamber. Nothing was posted.")
			end
			RunCheck.arrive(run.guard, x, z, run.clock)
			run.x, run.z = x, z
			return events
		end
	end
	local ok, reason = RunCheck.sample(run.guard, run.clock, x, y, z)
	if not ok then
		return void(run, reason :: string)
	end
	run.x, run.z = x, z

	if run.phase == "ready" then
		local f = Grid.lineCrossing(px, pz, x, z, cfg)
		if f ~= nil then
			run.phase = "running"
			run.startClock = prevClock + f * dt
			RunCheck.startPath(run.guard, run.startClock, px + (x - px) * f, 0)
			table.insert(events, { type = "start", at = run.startClock })
		end
	end

	local cx, cy, kind = Grid.cellOf(x, z, cfg)
	if kind == "grid" then
		local i = Grid.index(cx :: number, cy :: number, cfg.Grid.W)
		if not run.visited[i] then
			run.visited[i] = true
			table.insert(run.visitedList, i)
			local cells = revealNew(run, { i }, cfg.Grid.RevealSteps)
			if #cells > 0 then table.insert(events, { type = "reveal", cells = cells }) end
		end
	end

	if run.phase ~= "running" then return events end

	local W = cfg.Grid.W
	local R = cfg.Pickup.Radius
	for k, s in run.world.seals do
		if not run.sealTaken[k] then
			local sx, sz = Grid.centre(s % W, s // W, cfg)
			local f = Grid.entryFraction(px, pz, x, z, sx, sz, R)
			if f ~= nil then
				run.sealTaken[k] = true
				run.sealCount += 1
				RunCheck.waypoint(run.guard, s, px + (x - px) * f, pz + (z - pz) * f)
				table.insert(events, { type = "seal", seal = k, count = run.sealCount, at = prevClock + f * dt })
			end
		end
	end

	local d = run.world.door
	local dx, dz = Grid.centre(d % W, d // W, cfg)
	local f = Grid.entryFraction(px, pz, x, z, dx, dz, R)
	local inside = (x - dx) ^ 2 + (z - dz) ^ 2 <= R * R
	if f ~= nil then
		if run.sealCount >= 3 then
			local at = prevClock + f * dt
			local fx, fz = px + (x - px) * f, pz + (z - pz) * f
			local okRun, why = RunCheck.finishCheck(run.guard, at, fx, fz, run.startClock)
			if not okRun then
				for _, e in void(run, why :: string) do table.insert(events, e) end
				return events
			end
			run.phase = "finished"
			run.timeMs = math.max(1, math.floor((at - run.startClock) * 1000 + 0.5))
			table.insert(events, { type = "finish", timeMs = run.timeMs })
			return events
		elseif not run.inDoorZone then
			run.inDoorZone = true
			table.insert(events, { type = "doorLocked", count = run.sealCount })
		end
	end
	if not inside then run.inDoorZone = false end
	return events
end

return RunState
