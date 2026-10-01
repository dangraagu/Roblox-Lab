-- Station.spec — the sector generator (DESIGN.md §12) and the module geometry the server builds from it.
-- Run: luau tests/Station.spec.luau
--
-- The numbered sections are DESIGN.md §19's list for this file. One deliberate deviation from the rig
-- (design-measure/station.luau), stated because §19.8 asks for it: when the vacuum modules run out, the rig
-- put the remaining items in air modules OTHER THAN THE RELAY. That makes the items depend on the relay
-- stream, which breaks relay independence (§12, spec 3). The real module lets an item land in any air
-- module but the dock, the relay's included. So walls, dock, air map and relay reproduce the rig on every
-- plan, and the items on every plan that never falls back to air (section 8 counts both).
local Config = require("../src/shared/Config")
local MazeGen = require("../src/shared/MazeGen")
local Station = require("../src/shared/Station")
local Streams = require("./Streams")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function plan(k, i, salt)
	return Station.plan(Config, k, Streams.fromSeeds(Streams.seedsFor(i, salt or k)), MazeGen)
end

local function bfs(p, src)
	local d = {}
	for m = 1, p.n2 do d[m] = -1 end
	d[src] = 0
	local q, h = { src }, 1
	while h <= #q do
		local a = q[h]; h += 1
		for _, b in p.adj[a] do
			if d[b] < 0 then d[b] = d[a] + 1; table.insert(q, b) end
		end
	end
	return d
end

local function perimeter(n, id)
	local x, y = (id - 1) % n, (id - 1) // n
	return x == 0 or y == 0 or x == n - 1 or y == n - 1
end

--================================================================ 1. reachable, dock on the perimeter
do
	local shapes = { { k = 1, n = 3 }, { k = 3, n = 4 }, { k = 10, n = 5 }, { k = 23, n = 6 } }
	for _, s in shapes do
		local bad, off, adjBad = 0, 0, 0
		for i = 1, 10000 do
			local p = plan(s.k, i)
			if p.n ~= s.n then bad += 1 end
			local d = bfs(p, p.dock)
			for m = 1, p.n2 do
				if d[m] < 0 then bad += 1; break end
				if d[m] ~= p.d[m] then bad += 1; break end
			end
			if not perimeter(p.n, p.dock) then off += 1 end
			for a = 1, p.n2 do
				for _, b in p.adj[a] do
					if not table.find(p.adj[b], a) then adjBad += 1 end
					local ax, ay = (a - 1) % p.n, (a - 1) // p.n
					local bx, by = (b - 1) % p.n, (b - 1) // p.n
					if math.abs(ax - bx) + math.abs(ay - by) ~= 1 then adjBad += 1 end
				end
			end
		end
		eq(bad, 0, string.format("%dx%d: every module reachable from the dock, and d[] is the doorway distance (10 000 plans)", s.n, s.n))
		eq(off, 0, string.format("%dx%d: the dock is always on the perimeter", s.n, s.n))
		eq(adjBad, 0, string.format("%dx%d: hatches are symmetric and join grid neighbours only", s.n, s.n))
	end
end

--================================================================ 2. the relay: air, far, uniform
do
	local bad = 0
	for _, k in { 1, 2, 3, 5, 10, 16, 23, 30, 40, 60, 100 } do
		for i = 1, 1500 do
			local p = plan(k, i)
			local thr0 = math.ceil(Config.Station.RelayDepthFrac * p.maxD)
			local ok = p.vac[p.relay] == false and p.relay ~= p.dock
			if not p.forced then
				-- at or past the threshold actually used, which is ceil(0.75 maxD) unless no air module was that far
				if p.d[p.relay] < p.relayThr or p.relayThr > thr0 then ok = false end
				if p.relayThr < thr0 then
					for m = 1, p.n2 do
						if m ~= p.dock and not p.vac[m] and p.d[m] > p.relayThr then ok = false end
					end
				end
			end
			if not ok then bad += 1 end
		end
	end
	eq(bad, 0, "the relay is always air, never the dock, and at doorway distance >= ceil(0.75 maxD) or the lowered threshold")
end
do
	-- uniform among the candidates: fix layout / air / loot, vary only the relay stream
	local base, cand
	for i = 4242, 4400 do -- the first plan from here with at least 4 candidates
		base = Streams.seedsFor(i, 23)
		cand = Station.relayCandidates(Config, Station.plan(Config, 23, Streams.fromSeeds(base), MazeGen))
		if #cand >= 4 then break end
	end
	truthy(#cand >= 3, "set-up: a plan with at least 3 relay candidates (" .. #cand .. ")")
	local counts, N = {}, 20000
	for _, c in cand do counts[c] = 0 end
	for i = 1, N do
		local seeds = table.clone(base)
		seeds.relay = 900001 + 7 * i
		local p = Station.plan(Config, 23, Streams.fromSeeds(seeds), MazeGen)
		counts[p.relay] = (counts[p.relay] or -1e9) + 1
	end
	local chi, expect = 0, N / #cand
	local outside = false
	for m, c in counts do
		if c < 0 then outside = true end
		chi += (c - expect) ^ 2 / expect
	end
	truthy(not outside, "the relay is only ever a candidate")
	-- df = #cand - 1; the 0.1 % critical value is 13.8 for df 2, 16.3 for 3, 18.5 for 4, 20.5 for 5
	local crit = ({ [1] = 10.8, [2] = 13.8, [3] = 16.3, [4] = 18.5, [5] = 20.5, [6] = 22.5, [7] = 24.3 })[#cand - 1] or 30
	print(string.format("  chi-square %.2f over %d candidates", chi, #cand)); truthy(chi < crit, string.format("uniform among the %d candidates over %d relay streams (chi-square %.2f < %.1f)", #cand, N, chi, crit))
end

--================================================================ 3. relay independence
local function sameExceptRelay(a, b)
	if a.dock ~= b.dock or a.n ~= b.n then return false, "dock" end
	for m = 1, a.n2 do
		if a.vac[m] ~= b.vac[m] then return false, "air map" end
		if #a.adj[m] ~= #b.adj[m] then return false, "walls" end
		for j, x in a.adj[m] do if b.adj[m][j] ~= x then return false, "walls" end end
		local ia, ib = a.items[m], b.items[m]
		if (ia == nil) ~= (ib == nil) then return false, "items" end
		if ia and (ia.kind ~= ib.kind or ia.x ~= ib.x or ia.z ~= ib.z or ia.y ~= ib.y) then return false, "items" end
	end
	return true, nil
end
do
	local differs, changedRelay, total = 0, 0, 0
	local why = nil
	for _, k in { 1, 2, 3, 5, 10, 23, 40 } do
		for i = 1, 400 do
			local base = Streams.seedsFor(i, k)
			local a = Station.plan(Config, k, Streams.fromSeeds(base), MazeGen)
			for j = 1, 3 do
				local s2 = table.clone(base)
				s2.relay = base.relay + 104729 * j
				local b = Station.plan(Config, k, Streams.fromSeeds(s2), MazeGen)
				local same, w = sameExceptRelay(a, b)
				total += 1
				if not same then differs += 1; why = why or w end
				if a.relay ~= b.relay then changedRelay += 1 end
			end
		end
	end
	eq(differs, 0, "changing ONLY the relay stream changes nothing but the relay (walls, air map, items identical)" .. (if why then " — " .. why else ""))
	truthy(changedRelay > total / 4, "and it does move the relay (" .. changedRelay .. " of " .. total .. ")")
end
do
	-- the relay stream is read the same way whatever the other streams hold: exactly one NextInteger(1, #cand)
	local bad = 0
	for i = 1, 600 do
		local log = {}
		local st = Streams.fromSeeds(Streams.seedsFor(i, 10))
		st.relay = Streams.spy(77 + i, log)
		local p = Station.plan(Config, 10, st, MazeGen)
		if #log ~= 1 or log[1] ~= "NextInteger" then bad += 1 end
		local _ = p
	end
	eq(bad, 0, "the relay stream draws exactly once (NextInteger), whatever the layout, air and loot streams hold")
end

--================================================================ 4. the reach rule, and air independent of the relay
do
	local bad = 0
	for _, k in { 1, 2, 3, 5, 9, 10, 16, 23, 30, 31, 45, 60, 80, 120 } do
		local reach = Config.scheduleFor(k).reach
		for i = 1, 800 do
			local p = plan(k, i)
			local airs = {}
			for m = 1, p.n2 do if not p.vac[m] then table.insert(airs, m) end end
			-- multi-source distance from air
			local d = {}
			for m = 1, p.n2 do d[m] = -1 end
			local q, h = {}, 1
			for _, s in airs do d[s] = 0; table.insert(q, s) end
			while h <= #q do
				local a = q[h]; h += 1
				for _, b in p.adj[a] do if d[b] < 0 then d[b] = d[a] + 1; table.insert(q, b) end end
			end
			for m = 1, p.n2 do
				if p.vac[m] and (d[m] < 0 or d[m] > reach) then bad += 1; break end
			end
			if p.vac[p.dock] then bad += 1 end
		end
	end
	eq(bad, 0, "every vacuum module is within reach(k) hatches of air, the dock is air (14 sectors x 800 plans)")
end

--================================================================ 5. sector 1 onboarding
do
	local bad, salvageNext, relayNext = 0, 0, 0
	for i = 1, 3000 do
		local p = plan(1, i)
		local found = false
		for _, nb in p.adj[p.dock] do
			if not p.vac[nb] then bad += 1 end
			if p.items[nb] and p.items[nb].kind == "salvage" then found = true end
			if nb == p.relay then relayNext += 1 end
		end
		if found then salvageNext += 1 end
	end
	eq(bad, 0, "sector 1: every dock neighbour is vacuum (3 000 plans)")
	eq(salvageNext, 3000, "sector 1: a salvage floats in a dock neighbour on every plan")
	eq(relayNext, 0, "sector 1: the relay is never next to the dock")
end

--================================================================ 6. items
do
	local countBad, vacFirst, perModule, posBad, heightBad, dockItem = 0, 0, 0, 0, 0, 0
	local lim = Config.Station.CellSize / 2 - Config.Station.WallThickness - Config.Station.ItemWallClearance
	local fellBack = 0
	for _, k in { 1, 2, 3, 5, 10, 16, 23, 30, 31, 60 } do
		local sc = Config.scheduleFor(k)
		for i = 1, 600 do
			local p = plan(k, i)
			local nS, nC, nVacFree = 0, 0, 0
			for m = 1, p.n2 do if p.vac[m] and m ~= p.dock then nVacFree += 1 end end
			local inAir = false
			for m, it in p.items do
				if it.kind == "salvage" then nS += 1 else nC += 1 end
				if not p.vac[m] then inAir = true end
				if m == p.dock then dockItem += 1 end
				if math.abs(it.x) > lim + 1e-9 or math.abs(it.z) > lim + 1e-9 then posBad += 1 end
				if math.abs(it.x) < 3 - 1e-9 and math.abs(it.z) < 3 - 1e-9 then posBad += 1 end
				if it.kind == "salvage" and (it.y < Config.Station.SalvageHeightMin or it.y > Config.Station.SalvageHeightMax) then heightBad += 1 end
			end
			local want = sc.salvage + sc.canisters
			local have = nS + nC
			if have ~= math.min(want, p.n2 - 1) then countBad += 1 end
			if inAir then
				fellBack += 1
				if nVacFree >= want then vacFirst += 1 end
			end
		end
	end
	eq(countBad, 0, "item counts follow the §3 schedule (as many as there are modules besides the dock)")
	eq(vacFirst, 0, "items go in vacuum first: an item in air only when the vacuum modules ran out")
	eq(dockItem, 0, "never an item in the dock")
	eq(posBad, 0, "every item stands >= 6 studs off every wall and out of the module's centre (the relay mast)")
	eq(heightBad, 0, "salvage floats 3..8 studs above the floor")
	print(string.format("  items fell back to air modules on %d of 6000 plans (sectors 1-3 only)", fellBack))
end

--================================================================ 7. only NextInteger / NextNumber; nothing else touched
do
	local log = {}
	local st = {
		layout = Streams.spy(1, log), air = Streams.spy(2, log), loot = Streams.spy(3, log), relay = Streams.spy(4, log),
	}
	Station.plan(Config, 23, st, MazeGen)
	local other = {}
	for _, key in log do if key ~= "NextInteger" and key ~= "NextNumber" then table.insert(other, key) end end
	eq(#other, 0, "the generator calls only NextInteger / NextNumber on its streams (" .. table.concat(other, ",") .. ")")
	truthy(#log > 20, "and it does call them (" .. #log .. " calls)")
end

--================================================================ 8. the rig reproduces
do
	local ok, Rig = pcall(require, "../design-measure/station")
	truthy(ok, "the design rig loads (design-measure/station.luau)")
	if ok then
		local plans, core, itemsSame, itemsComparable = 0, 0, 0, 0
		for _, k in { 1, 3, 5, 10, 16, 23, 30 } do
			for i = 1, 2000 do
				local seeds = Rig.seedsFor(i, k)
				local r = Rig.plan(k, seeds)
				local p = Station.plan(Config, k, Streams.fromSeeds(seeds), MazeGen)
				plans += 1
				local same = r.entry == p.dock and r.relay == p.relay and r.maxD == p.maxD and r.flips == p.flips
				for m = 1, p.n2 do
					if r.vac[m] ~= p.vac[m] or #r.adj[m] ~= #p.adj[m] then same = false end
				end
				if same then core += 1 end
				local rigAir = false
				for m in r.item do if not r.vac[m] then rigAir = true end end
				if not rigAir then
					itemsComparable += 1
					local sameItems = true
					for m = 1, p.n2 do
						local a, b = r.item[m], p.items[m]
						if (a == nil) ~= (b == nil) or (a and a ~= b.kind) then sameItems = false end
					end
					if sameItems then itemsSame += 1 end
				end
			end
		end
		eq(core, plans, "walls, dock, air map, reach flips and relay are the rig's on every plan (" .. core .. "/" .. plans .. ")")
		eq(itemsSame, itemsComparable, "items are the rig's on every plan that did not fall back to air (" .. itemsSame .. "/" .. itemsComparable .. ")")
	end
end

--================================================================ module geometry the server builds
do
	local S = Config.Station
	local worst, bad, doorwayBad = 0, 0, 0
	for _, k in { 1, 5, 10, 23, 30 } do
		for i = 1, 200 do
			local p = plan(k, i)
			for m = 1, p.n2 do
				for _, spliced in { false, true } do
					local parts = Station.moduleParts(Config, p, m, { spliced = spliced, mainArray = k == Config.Brag.Sector and m == p.relay })
					local extra = Station.extrasCount(Config, p, m, spliced)
					local n = #parts + extra
					if n > worst then worst = n end
					if n > S.MaxPartsPerModule then bad += 1 end
				end
				-- a doorway gap exactly where a hatch is, a solid wall where none is
				local parts = Station.moduleParts(Config, p, m, {})
				for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local x, y = (m - 1) % p.n, (m - 1) // p.n
					local nx, ny = x + side[1], y + side[2]
					local nb = if nx >= 0 and ny >= 0 and nx < p.n and ny < p.n then ny * p.n + nx + 1 else nil
					local open = nb ~= nil and table.find(p.adj[m], nb) ~= nil
					-- probe the doorway's middle at 5 studs up, just inside the wall
					local px = side[1] * (S.CellSize / 2 - S.WallThickness / 2)
					local pz = side[2] * (S.CellSize / 2 - S.WallThickness / 2)
					local blocked = false
					for _, sp in parts do
						if sp.role == "wall" then
							local hx, hy, hz = sp.size[1] / 2, sp.size[2] / 2, sp.size[3] / 2
							if math.abs(px - sp.pos[1]) <= hx and math.abs(5 - sp.pos[2]) <= hy and math.abs(pz - sp.pos[3]) <= hz then
								blocked = true
							end
						end
					end
					if blocked == open then doorwayBad += 1 end
				end
			end
		end
	end
	eq(bad, 0, "no module ever needs more than 20 Parts (worst " .. worst .. "), with the splice's extras counted")
	eq(doorwayBad, 0, "a doorway gap exactly where a hatch is, and a solid wall everywhere else")
	local p = plan(23, 7)
	local vacM, airM
	for m = 1, p.n2 do
		if p.vac[m] and not vacM then vacM = m end
		if not p.vac[m] and not airM then airM = m end
	end
	local function roles(list)
		local r = {}
		for _, sp in list do r[sp.role] = (r[sp.role] or 0) + 1 end
		return r
	end
	local rv, ra = roles(Station.moduleParts(Config, p, vacM, {})), roles(Station.moduleParts(Config, p, airM, {}))
	eq(rv.glass, 1, "a vacuum module has a cracked glass viewport in its ceiling")
	eq(ra.glass, nil, "an air module has a solid ceiling")
	eq(rv.floor, 1, "one floor")
	eq(rv.fixture, 1, "one light fixture")
end
do
	-- hatch geometry: a leaf fills the doorway on the shared boundary; the approach test reads the trusted point
	local p = plan(10, 3)
	local a = p.dock
	local b = p.adj[a][1]
	local leaf = Station.leafSpec(Config, p.n, a, b)
	local ax, az = Station.cellCenter(Config, p.n, a)
	local bx, bz = Station.cellCenter(Config, p.n, b)
	truthy(math.abs(leaf.pos[1] - (ax + bx) / 2) < 1e-9 and math.abs(leaf.pos[3] - (az + bz) / 2) < 1e-9, "a leaf sits on the boundary between its two modules")
	eq(leaf.pos[2], Config.Station.HatchHeight / 2, "and stands on the floor")
	local hx, hz = Station.hatchCenter(Config, p.n, a, b)
	local open = function() return false end
	local near = Station.hatchesNear(Config, p, a, hx + (ax - hx) * 0.1, hz + (az - hz) * 0.1, open)
	truthy(table.find(near, b) ~= nil, "standing at the hatch from the adjacent module is near it")
	local far = Station.hatchesNear(Config, p, a, ax, az, open)
	truthy(table.find(far, b) == nil, "the module's centre (16 studs away) is not")
	local shut = Station.hatchesNear(Config, p, a, hx, hz, function() return true end)
	eq(#shut, 0, "an already open hatch is not reported again")
	eq(Station.moduleAt(Config, p.n, ax, az), a, "moduleAt: a module's own centre")
	eq(Station.moduleAt(Config, p.n, 9999, 0), nil, "moduleAt: off the grid is nil")
end

print(string.format("Station: %d passed, %d failed", passed, failed))
assert(failed == 0, "Station tests failed")
