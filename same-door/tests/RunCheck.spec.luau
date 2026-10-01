-- Spec for RunCheck (the movement guard) and RunState (the server's run machine).
-- Run: luau tests/RunCheck.spec.luau
--
-- The server samples every player in a run each Heartbeat and keeps the run clock as the sum of the
-- Heartbeat dt. No remote carries a time, a position, a seal or a finish, so these two modules are
-- the whole of what decides a ranked time (DESIGN §5, §11). Pinned here:
--   * honest traces pass: walking the perfect line at 16 studs/s, with frame jitter, with a lag gap;
--   * every threat row voids: teleport, noclip through a wall, a 2x burst, a whole run that beats the
--     legal line through its own halls (1.03x on the tight line, 1.10x on P), a lag-switched start,
--     flying over the walls, leaving the lane, a ready-phase hop back into the lane;
--   * a walk of the published P finishes in P and never under it; the corridor stays connected;
--   * the stated residual is real and stated: 1.015x on the tight legal line is NOT caught;
--   * the clock starts at the interpolated line crossing and stops at the interpolated Door entry;
--   * seals in any order, the Door refuses fewer than 3 (once per entry, never silently);
--   * reveal follows validated movement only and stops at the first void.
local RunCheck = require("../src/server/RunCheck")
local RunState = require("../src/server/RunState")
local Dungeon = require("../src/server/Dungeon")
local Grid = require("../src/shared/Grid")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local cfg = Config
local function drawOf(seed)
	local r = Rng.new(seed)
	return function(n) return r:below(n) end
end
local rec = Dungeon.mint(cfg, drawOf(2026), 20726, 1790730000)
local world = Dungeon.fromRecord(cfg, rec)
local pathLen, path = Dungeon.perfectPath(cfg, world)
local W = cfg.Grid.W

-- Positions along a polyline at `speed` studs/s, one per dt (dt may vary), starting at `from`.
local function trace(points, speed, dts)
	local out = {}
	local seg, segPos = 1, 0
	local x, z = points[1].x, points[1].z
	local k = 1
	while true do
		local dt = dts(k)
		k += 1
		local remaining = speed * dt
		while remaining > 0 and seg < #points do
			local a, b = points[seg], points[seg + 1]
			local L = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
			local left = L - segPos
			if remaining < left then
				segPos += remaining
				remaining = 0
			else
				remaining -= left
				seg += 1
				segPos = 0
			end
			local A, B = points[seg], points[math.min(seg + 1, #points)]
			local LL = math.max(math.sqrt((B.x - A.x) ^ 2 + (B.z - A.z) ^ 2), 1e-9)
			x = A.x + (B.x - A.x) * math.min(segPos / LL, 1)
			z = A.z + (B.z - A.z) * math.min(segPos / LL, 1)
		end
		table.insert(out, { dt = dt, x = x, z = z })
		if seg >= #points then break end
		if #out > 200000 then break end
	end
	return out
end

-- From the antechamber centre to the line, then the perfect line, then 2 studs on into the Door's
-- circle as a player keeps walking (a walker that stops dead on the last point is seen a frame late:
-- the server interpolates the entry along the last sample step as if all of it had been walked).
local function fullPath()
	local pts = { { x = 72, z = -8 } }
	for _, p in path do table.insert(pts, p) end
	local a, b = pts[#pts - 1], pts[#pts]
	local L = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	table.insert(pts, { x = b.x + (b.x - a.x) / L * 2, z = b.z + (b.z - a.z) / L * 2 })
	return pts
end

local function frame() return 1 / 60 end

-- Run a trace through a fresh RunState; returns the run and every event.
local DEPS = { RunCheck = RunCheck, Grid = Grid, Dungeon = Dungeon }
local function play(samples, ly)
	local run = RunState.new(cfg, world, DEPS)
	local events = {}
	for _, e in RunState.arrive(run) do table.insert(events, e) end
	for _, s in samples do
		for _, e in RunState.step(run, s.dt, s.x, s.y or ly or 3, s.z) do
			table.insert(events, e)
		end
		if run.phase == "finished" or run.phase == "void" then break end
	end
	return run, events
end
local function find(events, kind)
	for _, e in events do if e.type == kind then return e end end
	return nil
end

--================================================================ an honest perfect run
do
	local run, ev = play(trace(fullPath(), 16, frame))
	local fin = find(ev, "finish")
	truthy(fin ~= nil, "an honest walk along the perfect line finishes")
	eq(find(ev, "void"), nil, "…and is not voided")
	eq(run.sealCount, 3, "…with all 3 seals")
	-- P ends ON the Door's pickup circle (Dungeon.tightLine), where the clock stops: the time is P
	truthy(fin and math.abs(fin.timeMs - rec.perfectMs) <= 2,
		string.format("the time %s ms is P (%d ms) within 2 ms", tostring(fin and fin.timeMs), rec.perfectMs))
	truthy(fin and fin.timeMs >= rec.perfectMs - 1, "a walk of the published line never beats P (REVIEW-1 finding 5)")
	local st = find(ev, "start")
	local toLine = math.sqrt((path[1].x - 72) ^ 2 + (path[1].z + 8) ^ 2)
	truthy(st ~= nil and math.abs(st.at - toLine / 16) <= 1 / 60,
		string.format("the clock starts at the interpolated line crossing (%.1f studs at 16/s = %.3f s)", toLine, toLine / 16))
end

--================================================================ honest variants pass
do
	local r = Rng.new(77)
	local _, ev = play(trace(fullPath(), 16, function() return (1 / 60) * (0.7 + 0.6 * r:next()) end))
	truthy(find(ev, "finish") ~= nil and find(ev, "void") == nil, "honest walking under +-30 % frame jitter is ranked")
	-- a 0.4 s network stall: the server sees no movement, then the real position (walked at 16)
	local samples = trace(fullPath(), 16, frame)
	local function stallAt(at: number): (any, { any })
		local stalled = {}
		for i, s in samples do
			if i > at and i <= at + 24 then
				table.insert(stalled, { dt = s.dt, x = samples[at].x, z = samples[at].z })
			else
				table.insert(stalled, s)
			end
		end
		return play(stalled)
	end
	local _, ev2 = stallAt(200)
	truthy(find(ev2, "finish") ~= nil and find(ev2, "void") == nil, "a 0.4 s replication stall, then the real position, is ranked")
	-- ...and wherever it lands: the first build tested ONE spot, where the line turned; on a straight
	-- stretch the 0.5 s window then saw 16 x 0.9 = 14.4 studs against a 14.0 limit and voided an honest
	-- walk at 25 of 44 spots (REVIEW-1 pass; Config.Check slacks). A stall that straddles a pickup can
	-- still make the server's chord miss that seal: then the seal stays lit and the player steps back
	-- into it (a visible second, never a void), so those spots count separately.
	local voided, missed, tried, firstWhy = 0, 0, 0, nil
	for at = 60, #samples - 30, 40 do
		local run, evs = stallAt(at)
		tried += 1
		local v = find(evs, "void")
		if v then
			voided += 1
			firstWhy = firstWhy or (tostring(at) .. ": " .. tostring(v.reason))
		elseif find(evs, "finish") == nil then
			-- unfinished: only allowed when the stall straddled the pickup of a seal the server missed
			local straddled = false
			for k, sc in world.seals do
				if not run.sealTaken[k] then
					local cx, cz = Grid.centre(sc % W, sc // W, cfg)
					for i = at, math.min(at + 25, #samples) do
						local p = samples[i]
						if (p.x - cx) ^ 2 + (p.z - cz) ^ 2 <= cfg.Pickup.Radius ^ 2 then straddled = true end
					end
				end
			end
			if straddled then
				missed += 1
			else
				voided += 1
				firstWhy = firstWhy or (tostring(at) .. ": no finish, and the stall straddled no missed seal")
			end
		end
	end
	eq(voided, 0, string.format("a 0.4 s replication stall never voids or stalls an honest walk (%d spots; %d straddled a pickup, whose seal stayed lit%s)",
		tried, missed, if firstWhy then "; " .. firstWhy else ""))
	print(string.format("  0.4 s stalls along the line: %d spots, none voided, %d straddled a pickup the server then missed", tried, missed))
end

do
	-- right after the server's pivot, a client-owned character may still report its hub position
	local s = trace(fullPath(), 16, frame)
	local stale = { { dt = 1 / 60, x = -900, z = -1000 }, { dt = 1 / 60, x = -900, z = -1000 } }
	for _, p in s do table.insert(stale, p) end
	local _, ev = play(stale)
	truthy(find(ev, "finish") ~= nil and find(ev, "void") == nil, "two stale hub samples before the line are ignored, not voided")
	-- but a sample inside the maze that is not continuous from the antechamber still voids
	local jump = { { dt = 1 / 60, x = 72, z = 60 } }
	for _, p in s do table.insert(jump, p) end
	local _, ev2 = play(jump)
	truthy(find(ev2, "void") ~= nil, "a pre-line sample deep in the maze still voids (no shortcut through the leniency)")
end

--================================================================ every threat voids
local function voidReason(samples, ly)
	local _, ev = play(samples, ly)
	local v = find(ev, "void")
	return v and v.reason or nil, ev
end

do -- teleport: 20 studs along the route in one frame
	local s = trace(fullPath(), 16, frame)
	local out = {}
	for i, p in s do
		if i == 300 then
			local q = s[math.min(i + 75, #s)]
			table.insert(out, { dt = p.dt, x = q.x, z = q.z })
			for j = i + 76, #s do table.insert(out, s[j]) end
			break
		end
		table.insert(out, p)
	end
	local reason = voidReason(out)
	truthy(reason ~= nil, "a 20-stud teleport voids (" .. tostring(reason) .. ")")
end

do -- burst: 2x for one second
	local s = trace(fullPath(), 16, function(k) return if k > 240 and k <= 300 then 2 / 60 else 1 / 60 end)
	for i, p in s do if i > 240 and i <= 300 then p.dt = 1 / 60 end end
	local reason = voidReason(s)
	truthy(reason ~= nil and string.find(reason, "fast") ~= nil, "a 2x burst for 1 s voids (" .. tostring(reason) .. ")")
end

do -- the whole run may not beat the legal line through the halls it took
	-- (a) the published line P at 1.10x: the time beats the taut line through its own corridor and
	-- pickup points at 16 * 1.02
	local reason = voidReason(trace(fullPath(), 16 * 1.10, frame))
	truthy(reason ~= nil and string.find(reason, "shortest line") ~= nil, "a whole run at 1.10x voids (" .. tostring(reason) .. ")")
	-- (b) the TIGHT legal line: take an honest run's corridor and pickup points (nudged 0.3 studs into
	-- each pickup circle, so a walker on it surely enters), string-pull it, and walk THAT line
	local run = play(trace(fullPath(), 16, frame))
	local g = run.guard
	local sealsByCell = {}
	for _, s in world.seals do
		local sx, sz = Grid.centre(s % W, s // W, cfg)
		sealsByCell[s] = { sx, sz }
	end
	for _, wp in g.waypoints do
		local cell = g.cells[wp.index]
		local c = sealsByCell[cell]
		local dx, dz = c[1] - wp.x, c[2] - wp.z
		local L = math.sqrt(dx * dx + dz * dz)
		wp.x += dx / L * 0.3
		wp.z += dz / L * 0.3
	end
	local tight, tightPts = RunCheck.tautLine(g, run.x, run.z)
	local pts = { { x = 72, z = -8 } }
	for _, p in tightPts do table.insert(pts, p) end
	do -- end half a stud inside the Door's circle, so the last sample surely enters it
		local d = world.door
		local dx, dz = Grid.centre(d % W, d // W, cfg)
		local last = pts[#pts]
		local ex, ez = dx - last.x, dz - last.z
		local L = math.sqrt(ex * ex + ez * ez)
		table.insert(pts, { x = last.x + ex / L * 0.5, z = last.z + ez / L * 0.5 })
	end
	print(string.format("  the tight legal line of this run: %.1f studs (the published P: %.1f)", tight, pathLen))
	local _, evA = play(trace(pts, 16, frame))
	truthy(find(evA, "finish") ~= nil and find(evA, "void") == nil, "an honest 1.00x walk of the tight legal line is ranked")
	local _, evB = play(trace(pts, 16 * 1.015, frame))
	truthy(find(evB, "finish") ~= nil and find(evB, "void") == nil,
		"RESIDUAL, stated: the tight line at 1.015x is not caught (the 2 % tolerance)")
	local rC = voidReason(trace(pts, 16 * 1.03, frame))
	truthy(rC ~= nil and string.find(rC, "shortest line") ~= nil, "the tight line at 1.03x voids (" .. tostring(rC) .. ")")
end

do -- noclip: walk straight through a closed wall between two grid cells
	local a, b
	for i = 0, W * W - 1 do
		local x = i % W
		if x + 1 < W and not world.maze.openE[i] and i ~= world.entrance then a, b = i, i + 1; break end
	end
	local ax, az = Grid.centre(a % W, a // W, cfg)
	local bx, bz = Grid.centre(b % W, b // W, cfg)
	-- walk honestly to cell a first (the whole route in cells is not needed: the guard only looks at
	-- neighbour cells, so start the trace inside a after a clean arrival and crossing)
	local run = RunState.new(cfg, world, DEPS)
	RunState.arrive(run)
	local events = {}
	local function stepTo(x, z)
		for _, e in RunState.step(run, 1 / 60, x, 3, z) do table.insert(events, e) end
	end
	-- cross the line and reach the entrance
	for k = 1, 30 do stepTo(72, -8 + k * 16 / 60) end
	-- now, pretend the route into cell a was walked honestly: jump the guard's idea of the cell
	RunCheck.debugPlace(run.guard, a, ax, az, run.clock)
	for k = 1, 40 do
		local t = k / 40
		stepTo(ax + (bx - ax) * t, az + (bz - az) * t)
		if run.phase == "void" then break end
	end
	local v = find(events, "void")
	truthy(v ~= nil and string.find(v.reason, "wall") ~= nil, "walking through a closed wall voids (" .. tostring(v and v.reason) .. ")")
end

do -- lag switch: the crossing is seen late, then a catch-up of 3 s of walking in one sample
	local s = trace(fullPath(), 16, frame)
	local out = {}
	for i, p in s do
		if i <= 20 then table.insert(out, p)
		elseif i <= 200 then table.insert(out, { dt = p.dt, x = s[20].x, z = s[20].z })
		else table.insert(out, p) end
	end
	local reason = voidReason(out)
	truthy(reason ~= nil, "a lag-switched start with a 3 s catch-up voids (" .. tostring(reason) .. ")")
end

do -- flying over the walls
	local s = trace(fullPath(), 16, frame)
	for i, p in s do if i > 200 then p.y = 15 end end
	local reason = voidReason(s)
	truthy(reason ~= nil and string.find(reason, "height") ~= nil, "a root 15 studs over the floor voids (" .. tostring(reason) .. ")")
	local s2 = trace(fullPath(), 16, frame)
	for i, p in s2 do if i > 200 then p.y = 9.5 end end
	local r2 = voidReason(s2)
	eq(r2, nil, "a jump peak (root about 10 over the floor) is fine")
end

do -- leaving the lane (standing on the roof of the next lane, say)
	local s = trace(fullPath(), 16, frame)
	s[250] = { dt = 1 / 60, x = 300, z = 40 }
	local reason = voidReason(s)
	truthy(reason ~= nil, "a sample outside the lane voids (" .. tostring(reason) .. ")")
end

do -- every void explains itself
	local _, ev = play(trace(fullPath(), 16 * 1.10, frame))
	local v = find(ev, "void")
	truthy(v ~= nil and #v.reason > 20, "a void carries a human reason")
end

--================================================================ seals, the Door, reveal
do
	-- visit the Door with fewer than 3 seals: walk straight to it through the maze's own passages
	local m = world.maze
	local dist, parent = Dungeon.bfs(m, world.entrance)
	local cells = { world.door }
	while cells[1] ~= world.entrance do table.insert(cells, 1, parent[cells[1]]) end
	local pts = { { x = 72, z = -8 }, { x = 72, z = 0 } }
	for _, c in cells do
		local x, z = Grid.centre(c % W, c // W, cfg)
		table.insert(pts, { x = x, z = z })
	end
	local run = RunState.new(cfg, world, DEPS)
	local events = {}
	for _, e in RunState.arrive(run) do table.insert(events, e) end
	for _, smp in trace(pts, 16, frame) do
		for _, e in RunState.step(run, smp.dt, smp.x, 3, smp.z) do table.insert(events, e) end
	end
	-- stand at the Door for a second
	local dx, dz = Grid.centre(world.door % W, world.door // W, cfg)
	for _ = 1, 60 do
		for _, e in RunState.step(run, 1 / 60, dx, 3, dz) do table.insert(events, e) end
	end
	local locked = 0
	for _, e in events do if e.type == "doorLocked" then locked += 1 end end
	eq(locked, 1, "the Door refuses fewer than 3 seals once per entry, not every frame")
	eq(find(events, "finish"), nil, "and does not finish")
	eq(run.phase, "running", "the run goes on")
	local _ = dist
end

do
	-- the reveal: every Cell sent is within 2 steps of a visited cell at send time; nothing twice
	local run = RunState.new(cfg, world, DEPS)
	local sent, twice, far = {}, 0, 0
	local function check(evs)
		for _, e in evs do
			if e.type == "reveal" then
				local near = Dungeon.revealFrom(world, run.visitedList, 2)
				-- the antechamber counts as a visited node joined to the entrance
				local nearAnte = Dungeon.revealFrom(world, { world.entrance }, 1)
				for _, c in e.cells do
					if sent[c] then twice += 1 end
					sent[c] = true
					if not near[c] and not nearAnte[c] then far += 1 end
				end
			end
		end
	end
	check(RunState.arrive(run))
	for _, s in trace(fullPath(), 16, frame) do
		check(RunState.step(run, s.dt, s.x, 3, s.z))
		if run.phase ~= "running" and run.phase ~= "ready" then break end
	end
	eq(twice, 0, "no cell is sent twice")
	eq(far, 0, "every cell sent was within 2 open steps of a visited cell when it was sent")
	local n = 0
	for _ in sent do n += 1 end
	truthy(n < W * W, string.format("walking the perfect line reveals %d of %d cells, not the whole day", n, W * W))
end

do
	-- after a void, nothing more is revealed
	local run = RunState.new(cfg, world, DEPS)
	RunState.arrive(run)
	local s = trace(fullPath(), 16, frame)
	local revealedAfter = 0
	for i, p in s do
		local x, z = p.x, p.z
		if i == 150 then x += 30 end -- teleport: void
		for _, e in RunState.step(run, p.dt, x, 3, z) do
			if e.type == "reveal" and run.voidAt ~= nil then revealedAfter += #e.cells end
		end
	end
	eq(run.phase, "void", "the run is void")
	eq(revealedAfter, 0, "no cell is revealed after the void")
end

do
	-- the run cap: 900 s of standing in the antechamber ends the run
	local run = RunState.new(cfg, world, DEPS)
	RunState.arrive(run)
	local capped = nil
	for _ = 1, 901 do
		for _, e in RunState.step(run, 1, 72, 3, -8) do if e.type == "void" then capped = e end end
		if capped then break end
	end
	truthy(capped ~= nil and string.find(capped.reason, "torches") ~= nil, "at the 15-minute cap the run ends and says why")
end

do
	-- a single fast frame that passes over a seal still takes it (segment test, not a point test)
	local run = RunState.new(cfg, world, DEPS)
	RunState.arrive(run)
	local sx, sz = Grid.centre(world.seals[1] % W, world.seals[1] // W, cfg)
	RunCheck.debugPlace(run.guard, world.seals[1], sx - 5, sz, 0)
	run.phase = "running"
	run.startClock = 0
	local taken = false
	for _, e in RunState.step(run, 1 / 60, sx + 0.2, 3, sz) do
		if e.type == "seal" then taken = true end
	end
	truthy(taken, "a step from 5 studs west of a seal to just past its centre takes it")
end

--================================================================ the ready phase (REVIEW-1, finding 1)
-- Before the line, samples from outside the lane are ignored (the pivot race: a client-owned
-- character can report its hub position for a frame or two after the server's PivotTo). A client
-- owns its character, so a script can step out of the lane, wait, and re-appear anywhere. That
-- re-entry must never start a clock, take a seal, reveal a cell or widen the continuity allowance:
-- the only way back in is the antechamber, as a fresh arrival.
do
	local function readyThenAway(awaySeconds: number, x: number, z: number)
		local run = RunState.new(cfg, world, DEPS)
		local events, first = {}, 0
		local function take(evs) for _, e in evs do table.insert(events, e) end end
		for _, e in RunState.arrive(run) do
			table.insert(events, e)
			if e.type == "reveal" then first += #e.cells end
		end
		for _ = 1, 10 do take(RunState.step(run, 1 / 60, 72, 3, -8)) end
		take(RunState.step(run, 1 / 60, 72, 3, -0.05)) -- the last in-lane sample: just south of the line
		local t = 0
		while t < awaySeconds do
			take(RunState.step(run, 0.25, -60, 3, -60)) -- anywhere outside the grid and the antechamber
			t += 0.25
		end
		for _ = 1, 6 do take(RunState.step(run, 1 / 60, x, 3, z)) end
		local revealed = 0
		for _, e in events do if e.type == "reveal" then revealed += #e.cells end end
		return run, events, revealed - first
	end
	local sx, sz = Grid.centre(world.seals[1] % W, world.seals[1] // W, cfg)
	local run, ev, extra = readyThenAway(55, sx - 3.5, sz)
	eq(find(ev, "start"), nil, "ready phase: 55 s out of the lane, then inside seal 1's circle: no clock starts")
	eq(find(ev, "seal"), nil, "…no seal is taken")
	eq(extra, 0, "…no cell is revealed beyond the arrival batch (the map dump)")
	eq(run.phase, "void", "…and the run is void")
	-- re-appear 15 studs into the entrance cell, across the line, after 1 s away
	local run2, ev2 = readyThenAway(1, 72, 15)
	eq(find(ev2, "start"), nil, "ready phase: 1 s away, then 15 studs past the line: no clock starts")
	eq(run2.phase, "void", "…and the run is void")
	-- re-appear just across the entrance cell's CLOSED west wall, on the line (the wall skip)
	truthy(not world.maze.openE[world.entrance - 1], "the spec day's entrance has a closed west wall")
	local run3, ev3 = readyThenAway(55, 62, 0.5)
	eq(find(ev3, "start"), nil, "ready phase: 55 s away, then across the closed entrance wall: no clock starts")
	eq(run3.phase, "void", "…and the run is void")
	-- the honest case: back into the antechamber is a fresh arrival, and the run goes on
	local run4 = readyThenAway(0.5, 72, -8)
	eq(run4.phase, "ready", "ready phase: away 0.5 s, then back in the antechamber: still ready, not void")
	local evs4 = {}
	for _, s in trace(fullPath(), 16, frame) do
		for _, e in RunState.step(run4, s.dt, s.x, 3, s.z) do table.insert(evs4, e) end
		if run4.phase ~= "ready" and run4.phase ~= "running" then break end
	end
	truthy(find(evs4, "finish") ~= nil and find(evs4, "void") == nil, "…and the honest walk from there finishes, ranked")
	-- a fresh arrival wherever in the antechamber: the character waits a second by the line, is away
	-- 0.25 s, and comes back in the antechamber's far corner, 16.4 studs from where it waited; the
	-- windows start over instead of reading that as a 16-stud burst
	do
		local run5 = RunState.new(cfg, world, DEPS)
		RunState.arrive(run5)
		for k = 1, 30 do RunState.step(run5, 1 / 60, 72, 3, -8 + k * 7.95 / 30) end
		for _ = 1, 60 do RunState.step(run5, 1 / 60, 72, 3, -0.05) end
		RunState.step(run5, 0.25, -60, 3, -60)
		for _ = 1, 3 do RunState.step(run5, 1 / 60, 66.5, 3, -15.5) end
		eq(run5.phase, "ready", "ready phase: back in the antechamber's far corner after 0.25 s is a fresh arrival, not a burst")
	end
end

do -- a 2.5 s SERVER hitch mid-run: the corridor is filled along open passages, never across a wall
	local s = trace(fullPath(), 16, frame)
	local out, acc = {}, 0
	for i, p in s do
		if i > 400 and i <= 550 then
			acc += p.dt
		elseif i == 551 then
			table.insert(out, { dt = p.dt + acc, x = p.x, z = p.z })
		else
			table.insert(out, p)
		end
	end
	local run, ev = play(out)
	eq(find(ev, "void"), nil, "a 2.5 s server hitch mid-run is not voided (" .. tostring(find(ev, "void") and find(ev, "void").reason) .. ")")
	local g = run.guard
	local broken = 0
	for k = 2, #g.cells do
		local ok = false
		for _, n in Dungeon.neighbours(world.maze, g.cells[k - 1]) do if n == g.cells[k] then ok = true end end
		if not ok then broken += 1 end
	end
	eq(broken, 0, "every consecutive pair in the run's corridor shares an open passage (" .. #g.cells .. " cells)")
end

print(string.format("RunCheck: %d passed, %d failed", passed, failed))
if failed > 0 then error("RunCheck spec failed", 0) end
