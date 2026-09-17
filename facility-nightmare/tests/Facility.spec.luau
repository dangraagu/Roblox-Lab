-- Facility.spec — DESIGN.md §14 invariants 1-12 for the pure generator, written before the module.
-- Run: luau tests/Facility.spec.luau
--
-- Counts that matter are written out by hand or taken from the design's measurement table
-- (Appendix A, M1), never recomputed from the module under test: a number recomputed from the
-- generator grades the generator against itself.
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local MazeGen = require("../src/shared/MazeGen")
local Facility = require("../src/shared/Facility")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b) .. " +- " .. tol)
	end
end

local function pct(list, q) -- identical to design-measure/sim.luau M.pct
	table.sort(list)
	local k = math.max(1, math.min(#list, math.floor(q * #list + 0.5)))
	return list[k]
end

local function planOf(n, fuses, cells, onboarding, layout, loot, decor)
	return Facility.plan(Config, { n = n, fuses = fuses, cells = cells, onboarding = onboarding },
		{ layout = layout, loot = loot, decor = decor or 99 }, Rng, MazeGen)
end

local function bfs(plan, src)
	local d = {}
	for i = 1, plan.n2 do d[i] = -1 end
	d[src] = 0
	local q, h = { src }, 1
	while h <= #q do
		local a = q[h]; h += 1
		for _, b in plan.adj[a] do
			if d[b] < 0 then d[b] = d[a] + 1; table.insert(q, b) end
		end
	end
	return d
end

--============================================================ shape schedule and slack

do
	local s1, s4, s9 = Facility.shape(Config, 1), Facility.shape(Config, 4), Facility.shape(Config, 9)
	eq(s1.grid .. "/" .. s1.fuses .. "/" .. s1.cells, "4/3/2", "sublevel 1 shape")
	eq(s4.grid .. "/" .. s4.fuses .. "/" .. s4.cells, "5/4/2", "sublevel 4 shape")
	eq(s9.grid .. "/" .. s9.fuses .. "/" .. s9.cells, "5/5/1", "sublevel 9 shape")
end

do -- invariant 10, with M6's printed values
	eq(string.format("%.3f", Facility.slack(Config, 1)), "2.000", "slack(1)")
	eq(string.format("%.3f", Facility.slack(Config, 4)), "1.571", "slack(4)")
	eq(string.format("%.3f", Facility.slack(Config, 8)), "1.364", "slack(8)")
	eq(string.format("%.3f", Facility.slack(Config, 30)), "1.121", "slack(30)")
	eq(string.format("%.3f", Facility.slack(Config, 100)), "1.039", "slack(100)")
	local ok = true
	for k = 1, 1000 do
		local s = Facility.slack(Config, k)
		if not (s > 1) then ok = false end
		if k > 1 and not (s < Facility.slack(Config, k - 1)) then ok = false end
	end
	truthy(ok, "slack is strictly decreasing and > 1 for k = 1..1000")
end

--============================================================ 1-3: reachability, entry, exit, loot

do
	local unreachable, notPerim, notFar, exitIsEntry = 0, 0, 0, 0
	local lootBad, countBad, positionBad = 0, 0, 0
	for _, sh in { { 4, 3, 2, true }, { 5, 4, 2, false }, { 5, 5, 1, false } } do
		local n = sh[1]
		for i = 1, 10000 do
			local p = planOf(n, sh[2], sh[3], sh[4], 1000003 * i + 17 + n, 7919 * i + 104729, i)
			local d = bfs(p, p.entry)
			local maxD = 0
			for r = 1, p.n2 do
				if d[r] < 0 then unreachable += 1 end
				if d[r] > maxD then maxD = d[r] end
			end
			local ex = (p.entry - 1) % n
			local ey = (p.entry - 1 - ex) / n
			if not (ex == 0 or ey == 0 or ex == n - 1 or ey == n - 1) then notPerim += 1 end
			if d[p.exit] ~= maxD or p.maxD ~= maxD then notFar += 1 end
			if p.exit == p.entry then exitIsEntry += 1 end
			local seen, fuses, cells = {}, 0, 0
			for room, item in p.items do
				if room == p.entry or room == p.exit or seen[room] then lootBad += 1 end
				seen[room] = true
				if item.kind == "fuse" then fuses += 1 elseif item.kind == "cell" then cells += 1 end
				local lim = Config.Facility.CellSize / 2 - Config.Facility.WallThickness - Config.Facility.ItemWallClearance
				if math.abs(item.x) > lim + 1e-9 or math.abs(item.z) > lim + 1e-9 then positionBad += 1 end
			end
			if fuses ~= sh[2] or cells ~= sh[3] then countBad += 1 end
		end
	end
	eq(unreachable, 0, "1. every room is reachable from the entry (30 000 plans over three shapes)")
	eq(notPerim, 0, "2. the entry is on the perimeter")
	eq(notFar, 0, "2. the exit is at maximum BFS distance")
	eq(exitIsEntry, 0, "2. exit ~= entry")
	eq(lootBad, 0, "3. fuses and cells sit in distinct rooms, never the entry or the exit")
	eq(countBad, 0, "3. item counts equal the §3 schedule")
	eq(positionBad, 0, "an item stands at least ItemWallClearance studs from every wall")
end

--============================================================ 4: the onboarding fuse

do
	local far, noOnboard = 0, 0
	for i = 1, 20000 do
		local p = Facility.planForSublevel(Config, 1, { layout = (i * 2654435761) % 4294967296,
			loot = (i * 40503 + 7) % 4294967296, decor = i }, Rng, MazeGen)
		local best = math.huge
		for _, r in p.fuseRooms do
			best = math.min(best, p.d[r])
		end
		if best > Config.Facility.OnboardFuseMaxDistance then far += 1 end
		if p.d[p.fuseRooms[1]] > 2 then noOnboard += 1 end
	end
	eq(far, 0, "4. sublevel 1 has a fuse within 2 doorways of the entry on EVERY seed (20 000)")
	eq(noOnboard, 0, "4. …and it is the first fuse drawn")
	local p2 = Facility.planForSublevel(Config, 2, { layout = 5, loot = 6, decor = 7 }, Rng, MazeGen)
	eq(p2.onboarding, false, "sublevel 2 has no onboarding placement")
end

--============================================================ 5: independent streams

do
	local function wallsOf(p)
		local parts = {}
		for _, l in p.links do table.insert(parts, l[1] .. "-" .. l[2]) end
		return table.concat(parts, ",") .. "|" .. p.entry .. "|" .. p.exit
	end
	local function lootRooms(p)
		local parts = {}
		for _, r in p.fuseRooms do table.insert(parts, "f" .. r) end
		for _, r in p.cellRooms do table.insert(parts, "c" .. r) end
		return table.concat(parts, ",")
	end
	-- an item's offset in its room must not depend on the walls: compared room by room, for every
	-- room that holds an item in both plans
	local function sameOffsetsWhereBothHold(p, q)
		local shared = 0
		for r, it in p.items do
			local jt = q.items[r]
			if jt then
				shared += 1
				if it.x ~= jt.x or it.z ~= jt.z then return false, shared end
			end
		end
		return true, shared
	end
	local wallsSame, offsetsSame, decorSame, sharedRooms = true, true, true, 0
	for i = 1, 300 do
		local a = planOf(5, 4, 2, false, 777 * i, 1000 + i, 5)
		local b = planOf(5, 4, 2, false, 777 * i, 9000 + 3 * i, 5)
		if wallsOf(a) ~= wallsOf(b) then wallsSame = false end
		local c = planOf(5, 4, 2, false, 123457 * i + 1, 1000 + i, 5)
		local same, shared = sameOffsetsWhereBothHold(a, c)
		sharedRooms += shared
		if not same then offsetsSame = false end
		local e = planOf(5, 4, 2, false, 777 * i, 1000 + i, 424242 + i)
		if wallsOf(a) ~= wallsOf(e) or lootRooms(a) ~= lootRooms(e) then decorSame = false end
	end
	truthy(wallsSame, "5. same layoutSeed, different lootSeed -> identical walls, entry and exit")
	truthy(offsetsSame and sharedRooms > 100, "5. different layoutSeed -> a room holding an item in both plans holds it at the same offset (" .. sharedRooms .. " rooms compared)")
	truthy(decorSame, "5. a different decorSeed changes neither walls nor which rooms hold which items")
end

--============================================================ 5b: what a BUILT room shows gives nothing else away
-- REVIEW-1 finding A1. An item's (x, z) used to be the next two draws of the LOOT stream, after the
-- room choices. `Rng.next` returns the LCG's whole state / 2^32, so one replicated Fuse position
-- handed a client the loot stream's state; stepping it back to the seed replayed every room choice.
-- The reviewer's probe did it from the replicated Part alone, 0.4-0.5 s into a run, on 18 of 18
-- floors. Props leaked the same way through the decor stream, which ran room after room: where a
-- room's props started in it depended on how many draws every earlier room had used, and that
-- depended on those rooms' doors and on whether an item sat there.
--
-- The property that closes the class: everything a built room shows (its item's offset, its
-- props) is a function of that room alone — its own doors, its own item — and of a seed that
-- decides nothing hidden.

do
	local MOD = 4294967296
	-- (a) the attack itself, with exact doubles (stronger than the float32 a client reads): does any
	-- item coordinate equal an output of the loot stream?
	local lim = Config.Facility.CellSize / 2 - Config.Facility.WallThickness - Config.Facility.ItemWallClearance
	local leakedPlans, plansWithItems = 0, 0
	for i = 1, 600 do
		for _, k in { 1, 5, 9 } do
			local seeds = { layout = (i * 2654435761 + k) % 2147483647, loot = (i * 40503 + 977 * k) % 2147483647, decor = (i * 69069 + 3) % 2147483647 }
			local p = Facility.planForSublevel(Config, k, seeds, Rng, MazeGen)
			local outputs = {}
			local lr = Rng.new(seeds.loot)
			for _ = 1, 64 do
				outputs[-lim + 2 * lim * lr:next()] = true
			end
			local any = false
			for _, it in p.items do
				if outputs[it.x] or outputs[it.z] then any = true end
			end
			if next(p.items) ~= nil then plansWithItems += 1 end
			if any then leakedPlans += 1 end
		end
	end
	truthy(plansWithItems == 1800, "control: every one of 1800 plans holds items (" .. plansWithItems .. ")")
	eq(leakedPlans, 0, "5b. no item coordinate is an output of the loot stream (1800 plans, first 64 loot draws)")

	-- (b) the property: change ONLY the loot seed. A room holding an item in both plans holds it at the
	-- same offset, and a room whose own item is the same in both plans has exactly the same props.
	local function propsKey(list)
		local parts = {}
		for _, pr in list or {} do
			table.insert(parts, string.format("%s@%.9f,%.9f", pr.name, pr.x, pr.z))
		end
		return table.concat(parts, ";")
	end
	local offsetDiffers, propsDiffer, compared, propRooms = 0, 0, 0, 0
	for i = 1, 400 do
		for _, sh in { { 4, 3, 2, true }, { 5, 4, 2, false }, { 5, 5, 1, false } } do
			local layout, decor = 31 * i + sh[1], 7 * i + 11
			local a = planOf(sh[1], sh[2], sh[3], sh[4], layout, 1000 + i, decor)
			local b = planOf(sh[1], sh[2], sh[3], sh[4], layout, 555555 + 13 * i, decor)
			for room = 1, a.n2 do
				local ia, ib = a.items[room], b.items[room]
				if ia and ib and (ia.x ~= ib.x or ia.z ~= ib.z) then offsetDiffers += 1 end
				local sameOwnItem = (ia == nil and ib == nil) or (ia ~= nil and ib ~= nil and ia.x == ib.x and ia.z == ib.z)
				if sameOwnItem then
					compared += 1
					if #(a.props[room] or {}) > 0 then propRooms += 1 end
					if propsKey(a.props[room]) ~= propsKey(b.props[room]) then propsDiffer += 1 end
				end
			end
		end
	end
	truthy(compared > 3000 and propRooms > 1000, "control: " .. compared .. " rooms compared, " .. propRooms .. " of them with props")

	-- (c) per room must not mean ALIKE. Rooms are dressed from their own streams, and those streams
	-- must not march in lockstep from one room id to the next: the first draw of room r against the
	-- first draw of room r + 1, over 20 000 decor seeds, binned 10 x 10, fills every bin (independent:
	-- about 200 each). Seeds a constant apart put every pair on a handful of lines.
	local bins, pairsN = {}, 0
	truthy(type(Facility.roomSeed) == "function", "control: Facility.roomSeed exists")
	for i = 1, if type(Facility.roomSeed) == "function" then 20000 else 0 do
		local seed = (i * 2246822519) % 2147483647
		local room = 1 + i % 24
		local u = Rng.new(Facility.roomSeed(seed, room)):next()
		local v = Rng.new(Facility.roomSeed(seed, room + 1)):next()
		local key = math.floor(u * 10) * 10 + math.floor(v * 10)
		bins[key] = (bins[key] or 0) + 1
		pairsN += 1
	end
	local thin = 0
	for b = 0, 99 do
		if (bins[b] or 0) < 120 then thin += 1 end
	end
	eq(thin, 0, "5b. neighbouring rooms' streams are independent: all 100 bins of (room r, room r + 1) hold >= 120 of " .. pairsN .. " pairs")
	local sharedOffset = 0
	for i = 1, 300 do
		local p = Facility.planForSublevel(Config, 1 + i % 12, { layout = i * 3 + 1, loot = i * 5 + 2, decor = i * 11 + 3 }, Rng, MazeGen)
		local seen = {}
		for _, it in p.items do
			local key = string.format("%.9f,%.9f", it.x, it.z)
			if seen[key] then sharedOffset += 1 end
			seen[key] = true
		end
	end
	eq(sharedOffset, 0, "5b. no two items on one floor stand at the same offset in their rooms (300 floors)")
	eq(offsetDiffers, 0, "5b. another loot seed never moves an item within its room")
	eq(propsDiffer, 0, "5b. another loot seed never moves a prop in a room whose own item is unchanged")
end

--============================================================ 6-9: model time and the front

do
	local p = planOf(4, 3, 2, true, 31337, 4242, 1)
	local t1, f1 = Facility.modelTime(Config, p)
	local t2, f2 = Facility.modelTime(Config, p)
	eq(t1, t2, "6. modelTime is deterministic")
	eq(f1, f2, "6. …and so is its first-fuse time")
	truthy(t1 > 0, "6. a floor takes time")
end

do
	local guardBad, lastBad, beyondBad, exitBad, heldBad, orderBad = 0, 0, 0, 0, 0, 0
	local exitUnpoweredBad, exitNotLast = 0, 0
	local minStep = Config.Facility.CellSize / Config.Movement.WalkSpeed
	for i = 1, 3000 do
		for _, k in { 1, 4, 9, 30, 100 } do
			local p = Facility.planForSublevel(Config, k, { layout = i * 131 + k * 7919, loot = i * 7 + 12345, decor = i }, Rng, MazeGen)
			local T = Facility.modelTime(Config, p)
			local step = Facility.front(Config, p, k, T)
			if step < minStep - 1e-12 then guardBad += 1 end
			local hold = (i % 3) * 7.25
			local guardBinds = minStep >= Facility.slack(Config, k) * T / (p.maxD + Config.Front.LeadSteps)
			if not guardBinds then
				local atMax = Facility.deathTimeAtDistance(Config, step, p.maxD, hold)
				if math.abs(atMax - (hold + Facility.slack(Config, k) * T)) > 1e-9 then lastBad += 1 end
				for r = 1, p.n2 do
					if r ~= p.exit and Facility.deathTime(Config, p, step, r, hold) > hold + Facility.slack(Config, k) * T + 1e-9 then
						beyondBad += 1
					end
				end
			end
			-- REVIEW-1 B3: an exit that never failed let a run stall for ever (a player with no battery and
			-- fuses out of reach waited in its light; 600 s measured, nothing happened). A POWERED exit
			-- never fails, so the choice keeps no timer; an unpowered one fails one ring after the last.
			if Facility.deathTime(Config, p, step, p.exit, hold, true) ~= math.huge then exitBad += 1 end
			local exitDark = Facility.deathTime(Config, p, step, p.exit, hold)
			if math.abs(exitDark - (hold + (2 + p.maxD + 1) * step)) > 1e-9 then exitUnpoweredBad += 1 end
			for r = 1, p.n2 do
				if r ~= p.exit and not (Facility.deathTime(Config, p, step, r, hold) < exitDark) then exitNotLast += 1 end
			end
			if Facility.deathTime(Config, p, step, p.entry, nil) ~= math.huge then heldBad += 1 end
			-- rings die in order of doorway distance
			for r = 1, p.n2 do
				for _, b in p.adj[r] do
					if b ~= p.exit and r ~= p.exit and p.d[b] > p.d[r]
						and not (Facility.deathTime(Config, p, step, b, hold) > Facility.deathTime(Config, p, step, r, hold)) then
						orderBad += 1
					end
				end
			end
		end
	end
	eq(guardBad, 0, "7. step >= CellSize / WalkSpeed (15 000 floors)")
	eq(lastBad, 0, "8. a room at the exit's distance would die at exactly hold + slack * Tmodel")
	eq(beyondBad, 0, "8. every non-exit room is dark by hold + slack * Tmodel")
	eq(exitBad, 0, "9. a POWERED exit never dies (the choice has no timer)")
	eq(exitUnpoweredBad, 0, "9. an unpowered exit dies one ring after the farthest ring: hold + (LeadSteps + maxD + 1) * step")
	eq(exitNotLast, 0, "9. …so every other room is dark before it")
	eq(heldBad, 0, "a held front (hold = nil) kills nothing")
	eq(orderBad, 0, "the dark spreads outward: a room one doorway farther dies strictly later")
end

do -- the entry ring dies at LeadSteps * step, flickering FlickerSeconds first
	local p = planOf(4, 3, 2, true, 99, 98, 97)
	local T = Facility.modelTime(Config, p)
	local step = Facility.front(Config, p, 1, T)
	near(Facility.deathTime(Config, p, step, p.entry, 0), Config.Front.LeadSteps * step, 1e-9, "entry dies at LeadSteps * step")
	near(Facility.flickerTime(Config, p, step, p.entry, 5), 5 + Config.Front.LeadSteps * step - Config.Front.FlickerSeconds, 1e-9,
		"flicker starts FlickerSeconds before death")
end

--============================================================ 11: reproduce Appendix A M1

do
	local N = 3000
	local function row(n, fuses, cells, onboard)
		local T, D, FF, DR = {}, {}, {}, {}
		for i = 1, N do
			local p = planOf(n, fuses, cells, onboard, 1000003 * i + 17, 7919 * i + 104729, i)
			local t, ff = Facility.modelTime(Config, p)
			table.insert(T, t); table.insert(D, p.maxD); table.insert(FF, ff)
			table.insert(DR, p.doors / p.n2)
		end
		local s = 0
		for _, v in DR do s += v end
		return string.format("%.1f %.1f %.1f %.1f | %d %d | %.1f %.1f | %.2f",
			pct(T, 0.1), pct(T, 0.5), pct(T, 0.9), pct(T, 1.0), pct(D, 0.5), pct(D, 1.0),
			pct(FF, 0.5), pct(FF, 0.9), s / #DR)
	end
	-- Verbatim from `luau m1_nofront.luau` (DESIGN.md Appendix A, M1).
	eq(row(4, 3, 2, true), "32.3 45.2 62.2 87.2 | 7 15 | 5.4 17.9 | 1.05", "11. M1 row '4x4 F3 onboard' reproduces with the real module")
	eq(row(4, 3, 2, false), "32.3 45.2 61.3 87.2 | 7 15 | 8.6 22.4 | 1.05", "11. M1 row '4x4 F3' reproduces")
	eq(row(5, 4, 3, false), "54.5 74.3 96.6 133.8 | 10 22 | 10.8 27.8 | 1.09", "11. M1 row '5x5 F4' reproduces")
end

--============================================================ 12: Rng discipline, seeds, props

do
	-- An Rng whose low-bit path explodes. If the generator ever reaches for Rng.int, this raises.
	local Strict = setmetatable({}, { __index = Rng })
	Strict.new = function(seed)
		local r = Rng.new(seed)
		return setmetatable({ state = r.state }, { __index = function(_, k)
			if k == "int" then error("Rng.int used", 2) end
			return (Rng :: any)[k]
		end })
	end
	local ok, err = pcall(function()
		for i = 1, 200 do
			for _, k in { 1, 5, 12 } do
				Facility.planForSublevel(Config, k, { layout = i, loot = i + 1, decor = i + 2 }, Strict, MazeGen)
			end
		end
	end)
	truthy(ok, "12. the generator never calls Rng.int (" .. tostring(err) .. ")")
end

do
	local fake = { calls = {}, NextInteger = function(self, lo, hi)
		table.insert(self.calls, { lo, hi })
		return hi
	end }
	local seeds = Facility.drawSeeds(fake)
	eq(#fake.calls, 3, "12. three independent seeds per sublevel")
	local under = true
	for _, c in fake.calls do
		if c[1] ~= 0 or c[2] >= 2 ^ 31 then under = false end
	end
	truthy(under, "12. each seed is drawn in [0, 2^31) — far below 2^53")
	truthy(seeds.layout ~= nil and seeds.loot ~= nil and seeds.decor ~= nil, "12. layout, loot and decor seeds")
end

local function rectDist(a, b)
	local gx = math.max(a.minX - b.maxX, b.minX - a.maxX, 0)
	local gz = math.max(a.minZ - b.maxZ, b.minZ - a.maxZ, 0)
	return math.sqrt(gx * gx + gz * gz)
end

do
	local doorBad, pickupBad, overlapBad, padBad, total, maxProps = 0, 0, 0, 0, 0, 0
	local inner = Config.Facility.CellSize / 2 - Config.Facility.WallThickness
	local hw = Config.Facility.DoorWidth / 2
	for i = 1, 3000 do
		for _, k in { 1, 5, 10 } do
			local p = Facility.planForSublevel(Config, k, { layout = i * 17 + k, loot = i * 29 + 3, decor = i * 31 + 5 }, Rng, MazeGen)
			for room = 1, p.n2 do
				local props = p.props[room] or {}
				maxProps = math.max(maxProps, #props)
				total += #props
				-- doorway opening segments on this room's interior wall faces
				local segs = {}
				for _, nb in p.adj[room] do
					local dx, dz = Facility.neighbourDir(p.n, room, nb)
					if dx ~= 0 then
						table.insert(segs, { minX = dx * inner, maxX = dx * inner, minZ = -hw, maxZ = hw })
					else
						table.insert(segs, { minX = -hw, maxX = hw, minZ = dz * inner, maxZ = dz * inner })
					end
				end
				for j, pr in props do
					local r = { minX = pr.x - pr.sx / 2, maxX = pr.x + pr.sx / 2, minZ = pr.z - pr.sz / 2, maxZ = pr.z + pr.sz / 2 }
					for _, s in segs do
						if rectDist(r, s) < Config.Facility.PropDoorClearance - 1e-9 then doorBad += 1 end
					end
					local it = p.items[room]
					if it then
						local pt = { minX = it.x, maxX = it.x, minZ = it.z, maxZ = it.z }
						if rectDist(r, pt) < Config.Facility.PickupRadius - 1e-9 then pickupBad += 1 end
					end
					local ph = Config.Facility.CenterPadHalf
					if rectDist(r, { minX = -ph, maxX = ph, minZ = -ph, maxZ = ph }) <= 0 then padBad += 1 end
					for j2 = j + 1, #props do
						local q = props[j2]
						local r2 = { minX = q.x - q.sx / 2, maxX = q.x + q.sx / 2, minZ = q.z - q.sz / 2, maxZ = q.z + q.sz / 2 }
						if r.minX < r2.maxX and r2.minX < r.maxX and r.minZ < r2.maxZ and r2.minZ < r.maxZ then overlapBad += 1 end
					end
					if r.minX < -inner - 1e-9 or r.maxX > inner + 1e-9 or r.minZ < -inner - 1e-9 or r.maxZ > inner + 1e-9 then padBad += 1 end
				end
			end
		end
	end
	eq(doorBad, 0, "12. no prop comes within 4 studs of a doorway opening")
	eq(pickupBad, 0, "12. no prop overlaps an item's pickup circle")
	eq(overlapBad, 0, "props never overlap each other")
	eq(padBad, 0, "props stay inside the room and off the centre pad")
	truthy(maxProps <= Config.Facility.PropsPerRoomMax, "at most 3 props per room")
	truthy(total > 0, "props are actually placed (" .. total .. " over 9000 floors)")
end

--============================================================ geometry: cells, doors, the part budget

do
	local n = 5
	local cx, cz = Facility.cellCenter(Config, n, 1)
	eq(cx .. "," .. cz, "-56,-56", "cell 1 of a 5x5 grid is the (-x, -z) corner")
	local mx, mz = Facility.cellCenter(Config, n, 13)
	eq(mx .. "," .. mz, "0,0", "cell 13 is the centre of a 5x5 grid")
	eq(Facility.cellOf(Config, n, 0, 0), 13, "cellOf the origin")
	eq(Facility.cellOf(Config, n, 13.9, -13.9), 13, "cellOf just inside the centre cell's corner")
	eq(Facility.cellOf(Config, n, 14.1, 0), 14, "cellOf across the +x edge")
	eq(Facility.cellOf(Config, n, 0, 14.1), 18, "cellOf across the +z edge")
	eq(Facility.cellOf(Config, n, 71, 0), nil, "cellOf outside the grid is nil")
	local dx, dz = Facility.doorPoint(Config, n, 13, 14)
	eq(dx .. "," .. dz, "14,0", "the doorway between 13 and 14 is on their shared edge")
	local ax, az = Facility.neighbourDir(n, 13, 8)
	eq(ax .. "," .. az, "0,-1", "cell 8 is -z of cell 13")
end

do
	local p = planOf(5, 4, 2, false, 2024, 2025, 2026)
	local cell = p.entry
	local cx, cz = Facility.cellCenter(Config, p.n, cell)
	local nb = p.adj[cell][1]
	local px, pz = Facility.doorPoint(Config, p.n, cell, nb)
	local closed = function() return false end
	eq(#Facility.doorsNear(Config, p, cell, cx, cz, closed), 0, "from the room centre (14 studs) no door opens")
	local ux, uz = (px - cx) / 14, (pz - cz) / 14
	local list = Facility.doorsNear(Config, p, cell, px - ux * 7.9, pz - uz * 7.9, closed)
	local found = false
	for _, b in list do if b == nb then found = true end end
	truthy(found, "7.9 studs from a doorway, it opens")
	eq(#Facility.doorsNear(Config, p, cell, px - ux * 7.9, pz - uz * 7.9, function() return true end), 0,
		"an already-open door is not opened again")
	local list2 = Facility.doorsNear(Config, p, cell, px - ux * 8.1, pz - uz * 8.1, closed)
	local found2 = false
	for _, b in list2 do if b == nb then found2 = true end end
	truthy(not found2, "8.1 studs from a doorway, it stays shut")
end

do
	local worst, worstLeaves, overBudget, missingFloor = 0, 0, 0, 0
	for i = 1, 2000 do
		for _, k in { 1, 6, 12 } do
			local p = Facility.planForSublevel(Config, k, { layout = i * 7 + k, loot = i * 11, decor = i * 13 }, Rng, MazeGen)
			for room = 1, p.n2 do
				local parts = Facility.roomParts(Config, p, room)
				worst = math.max(worst, #parts)
				if #parts > Config.Facility.MaxPartsPerRoom then overBudget += 1 end
				local roles = {}
				for _, s in parts do roles[s.role] = (roles[s.role] or 0) + 1 end
				if roles.floor ~= 1 or roles.ceiling ~= 1 or roles.fixture ~= 1 or roles.dust ~= 1 then missingFloor += 1 end
			end
			worstLeaves = math.max(worstLeaves, #p.links)
		end
	end
	eq(overBudget, 0, "no room exceeds 20 Parts (door leaves excluded), 18 000 floors")
	truthy(worst <= 20, "worst room " .. worst .. " Parts")
	eq(missingFloor, 0, "every room has one floor, ceiling, fixture and dust volume")
	truthy(worstLeaves <= Config.Facility.MaxDoorLeavesPerFloor, "door leaves per floor <= 40 (worst " .. worstLeaves .. ")")
end

do -- a wall with a doorway is split into exactly three pieces, and leaves a 6x9 gap
	local p = planOf(4, 3, 2, true, 555, 556, 557)
	local room = p.entry
	local parts = Facility.roomParts(Config, p, room)
	local walls = 0
	for _, s in parts do if s.role == "wall" then walls += 1 end end
	local doors = #p.adj[room]
	eq(walls, (4 - doors) * 1 + doors * 3, "walls: one Part per solid wall, three per doorway wall")
	local leaf = Facility.doorLeaf(Config, p.n, room, p.adj[room][1])
	truthy(leaf.name == "Door_" .. math.min(room, p.adj[room][1]) .. "_" .. math.max(room, p.adj[room][1]), "door leaf name is Door_<lo>_<hi>")
	local big = math.max(leaf.size[1], leaf.size[3])
	eq(big .. "x" .. leaf.size[2], "6x9", "the leaf fills the 6x9 doorway")
end

--============================================================ the apparition stands in the room, not in its furniture
-- REVIEW-1 finding B4. The figure stood 2 studs off the wall opposite the doorway with no look at
-- the room's props; a desk, crate or cabinet on that wall reaches 9..13 studs off centre, so the
-- figure stood waist-deep in one on 53 of 727 apparitions (reviewer) / 73 of 707 (this pass).
-- Facility.apparition is the ONE description the server builds from, so this tests what ships.

do
	local inner = Config.Facility.CellSize / 2 - Config.Facility.WallThickness
	local design = inner - Config.Apparition.WallOffset
	local EPS = 0.01
	-- a limb's world-axis box in grid-local coordinates. CFrame.lookAt(base, base + look) has
	-- RightVector (-dz, 0, dx) and its local +Z pointing AWAY from `look`.
	local function limbBox(spec, limb)
		local dx, dz = spec.dx, spec.dz
		local rx, rz = -dz, dx
		local ox, oy, oz = limb.offset[1], limb.offset[2], limb.offset[3]
		local cx = spec.x + rx * ox - dx * oz
		local cz = spec.z + rz * ox - dz * oz
		local hx = math.abs(rx) * limb.size[1] / 2 + math.abs(dx) * limb.size[3] / 2
		local hz = math.abs(rz) * limb.size[1] / 2 + math.abs(dz) * limb.size[3] / 2
		return { cx - hx, cx + hx, oy - limb.size[2] / 2, oy + limb.size[2] / 2, cz - hz, cz + hz }
	end
	local function partBox(roomCx, roomCz, s)
		return { roomCx + s.pos[1] - s.size[1] / 2, roomCx + s.pos[1] + s.size[1] / 2,
			s.pos[2] - s.size[2] / 2, s.pos[2] + s.size[2] / 2,
			roomCz + s.pos[3] - s.size[3] / 2, roomCz + s.pos[3] + s.size[3] / 2 }
	end
	local function overlap(a, b)
		return a[1] < b[2] - EPS and b[1] < a[2] - EPS and a[3] < b[4] - EPS and b[3] < a[4] - EPS and a[5] < b[6] - EPS and b[5] < a[6] - EPS
	end
	local figures, inProp, inOther, outside, offAxis, notOnDesignSpot, blockedSpots, limbsBad = 0, 0, 0, 0, 0, 0, 0, 0
	local okCall, err = pcall(function()
		for i = 1, 150 do
			for _, k in { 1, 5, 12 } do
				local p = Facility.planForSublevel(Config, k, { layout = i * 101 + k, loot = i * 13 + 1, decor = i * 7919 + k }, Rng, MazeGen)
				for room = 1, p.n2 do
					if room ~= p.exit then
						local rcx, rcz = Facility.cellCenter(Config, p.n, room)
						local parts = Facility.roomParts(Config, p, room)
						for _, nb in p.adj[room] do
							local spec = Facility.apparition(Config, p, room, nb)
							figures += 1
							if #spec.limbs ~= 6 then limbsBad += 1 end
							local ndx, ndz = Facility.neighbourDir(p.n, room, nb)
							if spec.dx ~= ndx or spec.dz ~= ndz then offAxis += 1 end
							-- on the doorway's axis, so it is seen through the doorway
							local lateral = if ndx ~= 0 then spec.z - rcz else spec.x - rcx
							if math.abs(lateral) > 1e-9 then offAxis += 1 end
							local back = -((spec.x - rcx) * ndx + (spec.z - rcz) * ndz)
							local farProp = false
							for _, s in parts do
								if s.role == "prop" then
									-- a prop against the far wall, across the figure's line
									local depth = -(s.pos[1] * ndx + s.pos[3] * ndz)
									local lat = if ndx ~= 0 then s.pos[3] else s.pos[1]
									local latHalf = if ndx ~= 0 then s.size[3] / 2 else s.size[1] / 2
									if depth > 0 and math.abs(lat) < latHalf + 1.8 and s.pos[2] - s.size[2] / 2 < 8.2 then farProp = true end
								end
							end
							if farProp then blockedSpots += 1 end
							if not farProp and math.abs(back - design) > 1e-9 then notOnDesignSpot += 1 end
							local hitProp, hitOther, out = false, false, false
							for _, limb in spec.limbs do
								local b = limbBox(spec, limb)
								if b[1] < rcx - inner or b[2] > rcx + inner or b[5] < rcz - inner or b[6] > rcz + inner or b[3] < -EPS then out = true end
								for _, s in parts do
									if s.role ~= "floor" and s.role ~= "ceiling" and s.role ~= "dust" and overlap(b, partBox(rcx, rcz, s)) then
										if s.role == "prop" then hitProp = true else hitOther = true end
									end
								end
							end
							if hitProp then inProp += 1 end
							if hitOther then inOther += 1 end
							if out then outside += 1 end
						end
					end
				end
			end
		end
	end)
	truthy(okCall, "Facility.apparition exists and runs (" .. tostring(err) .. ")")
	print("  apparition spots " .. figures .. ", blocked " .. blockedSpots)
	truthy(figures > 15000 and blockedSpots > 500, "control: " .. figures .. " figure spots, " .. blockedSpots .. " with a prop across the far wall's line")
	eq(inProp, 0, "B4. no apparition limb stands inside a prop")
	eq(inOther, 0, "B4. …or inside a wall, lintel, light or item")
	eq(outside, 0, "B4. …and every limb stays inside the room, above its floor")
	eq(offAxis, 0, "B4. it stands on the doorway's axis, facing the doorway")
	eq(notOnDesignSpot, 0, "B4. with nothing on the far wall it stands where DESIGN.md §2.6 puts it (2 studs off the wall)")
	eq(limbsBad, 0, "B4. six parts")
end

print(string.format("Facility: %d passed, %d failed", passed, failed))
