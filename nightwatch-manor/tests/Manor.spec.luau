-- Pure tests for Manor (the seeded procedural manor layout).
-- Run from the game directory: luau tests/Manor.spec.luau
--
-- Manor.plan is the whole night. If it hands back a layout whose exit is unreachable, whose
-- patrol crosses a wall, or whose relics sit in a room that was never built, the player finds
-- out by walking into it in the dark. None of that needs Roblox to test, so none of it is
-- tested in Roblox.
local Manor = require("../src/shared/Manor")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local M = Config.Manor

--============================================================================== catalog sanity

do
	local seen, dupe = {}, false
	for _, k in M.Kinds do
		if seen[k.id] then dupe = true end
		seen[k.id] = true
	end
	truthy(not dupe, "room kind ids are unique")
	truthy(seen.foyer and seen.vestibule, "the catalog carries the two forced kinds")
	eq(Manor.kindById(Config, "library").id, "library", "kindById finds the kind with that id")
	eq(Manor.kindById(Config, "no_such_room"), nil, "kindById on an unknown id -> nil")
end

--=================================================================================== the seed

do
	local a = Manor.seedFor(Config, 1)
	local b = Manor.seedFor(Config, 1)
	local c = Manor.seedFor(Config, 2)
	eq(a, b, "seedFor is a pure function of the night")
	truthy(a ~= c, "different nights get different seeds")
	eq(a, math.floor(a), "the seed is an integer")
	truthy(a < 2 ^ 53, "the seed stays inside exact-integer range (no low bits lost)")
	-- The whole point of a WorldSeed: the seed must NOT depend on who is playing.
	eq(Manor.seedFor(Config, 9), Config.WorldSeed * Config.SeedPrimeA + 9 * Config.SeedPrimeB,
		"the seed folds ONLY WorldSeed and the night")
end

--=========================================================================== size / count curves

eq(Manor.roomCount(Config, 1), M.BaseRooms, "night 1 == BaseRooms")
truthy(Manor.roomCount(Config, 10) > Manor.roomCount(Config, 1), "the manor grows with the night")
-- `MaxRooms` is the hard cap on the TOTAL, repair rooms included, so the growth target has to
-- stop short of it by the repair budget. It used to clamp AT MaxRooms and the repair pass then
-- appended up to MaxRepairRooms on top, which put 96 of nights 1-120 over the number in the
-- config (largest manor: 23 against a MaxRooms of 18) with nothing asserting otherwise.
eq(Manor.roomCount(Config, 100000), M.MaxRooms - M.MaxRepairRooms,
	"the growth target stops MaxRepairRooms short of MaxRooms, leaving the repair pass room inside the cap")
truthy(Manor.roomCount(Config, 0) >= 2, "there is always room for an entrance and an exit")
truthy(Manor.roomCount(Config, -5) >= 2, "negative inputs cannot shrink it below 2")

-- THE headline claim, asserted as a property rather than as prose: night N is the same manor for
-- everybody. It was FALSE. `roomCount` folded in the player's hub level, so every upgrade anybody
-- bought quietly grew their manor, moved the exit and re-rolled the relics — and since the exit is
-- always the DEEPEST room, every purchase in a tycoon game silently lengthened the walk out.
-- Nothing but the seed may reach the layout, so a stray extra argument has to change nothing.
do
	local function signature(plan)
		local out = {}
		for _, r in plan.rooms do
			table.insert(out, string.format("%d:%s@%d,%d", r.id, r.kind, r.gx, r.gz))
		end
		table.insert(out, "exit=" .. tostring(plan.exitId))
		for _, s in plan.relics do
			table.insert(out, string.format("r%d/%d:%s", s.roomId, s.slot, s.tier))
		end
		for _, id in plan.patrol do
			table.insert(out, "p" .. tostring(id))
		end
		return table.concat(out, "|")
	end
	for _, night in { 1, 7, 14 } do
		local fresh = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
		local veteran = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night, 12)
		eq(signature(veteran), signature(fresh),
			"night " .. night .. " is the SAME manor for a hub-level-12 player as for a brand new one")
	end
end

eq(Manor.relicCount(Config, 1), Config.Relics.Base, "night 1 relic count == Base")
truthy(Manor.relicCount(Config, 12) > Manor.relicCount(Config, 1), "more relics on later nights")
eq(Manor.relicCount(Config, 100000), Config.Relics.Max, "relic count clamps at Max")

eq(Manor.patrolCount(Config, 1, M.MaxRooms), M.PatrolBase, "night 1 patrol == PatrolBase")
truthy(Manor.patrolCount(Config, 40, M.MaxRooms) > M.PatrolBase, "the patrol lengthens with the night")
eq(Manor.patrolCount(Config, 100000, M.MaxRooms), M.PatrolMax, "patrol clamps at PatrolMax")
truthy(Manor.patrolCount(Config, 100000, 3) <= 3, "the patrol can never be longer than the manor")

--=================================================================================== the plan

local function planFor(night, hub)
	return Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
end

local plan = planFor(1)

-- roomCount is the TARGET the manor is grown to; the dead-end repair pass may then add up to
-- MaxRepairRooms more while closing one-door rooms, and nothing else may.
truthy(#plan.rooms >= Manor.roomCount(Config, 1), "the plan holds at least roomCount rooms")
truthy(#plan.rooms <= Manor.roomCount(Config, 1) + M.MaxRepairRooms, "...and never more than the repair budget on top")

-- ...and MaxRooms means what it says, on every night the game can reach. This is a part budget as
-- much as a layout one: a room is 13 BaseParts before its furniture, and the manor is rebuilt
-- from scratch every night for every player in the server.
do
	local worst, worstNight, over = 0, 0, 0
	for night = 1, Config.Night.MaxNight do
		local n = #Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night).rooms
		if n > worst then worst, worstNight = n, night end
		if n > M.MaxRooms then over += 1 end
	end
	print(string.format("  nights 1-%d: largest manor %d rooms (night %d), %d nights over MaxRooms (%d)",
		Config.Night.MaxNight, worst, worstNight, over, M.MaxRooms))
	eq(over, 0, string.format("no night in 1-%d exceeds Config.Manor.MaxRooms", Config.Night.MaxNight))

	-- Two guards hold that number: `roomCount` stops the growth target MaxRepairRooms short, and
	-- `plan` caps the repair budget itself. With today's constants the first makes the second
	-- unreachable, so the second is exercised here the way Upgrades.spec exercises the effect
	-- ceilings — against a config that puts pressure on it. Without this the cap in `plan` is a
	-- line no test can kill, and a later retune of BaseRooms would blow the part budget silently.
	-- The cap holds by construction rather than by a second clamp: `roomCount` stops the growth
	-- target MaxRepairRooms short of MaxRooms, and the repair pass may spend exactly that. The one
	-- way that arithmetic fails is a config where roomCount's floor at 2 out-votes the subtraction,
	-- so THAT is the thing to assert. It is a live constraint on a retune anybody might make
	-- ("smaller manors": MaxRooms 18 -> 6 with the repair budget left at 5), and the failure is
	-- silent: more rooms than the config says, every night, and a part budget nobody costed.
	truthy(M.MaxRooms >= M.MaxRepairRooms + 2, string.format(
		"Config.Manor.MaxRooms (%d) leaves room for the repair budget (%d) above the two rooms a manor must have",
		M.MaxRooms, M.MaxRepairRooms))
	truthy(Manor.roomCount(Config, Config.Night.MaxNight) + M.MaxRepairRooms <= M.MaxRooms, string.format(
		"...so the largest target (%d) plus the whole repair budget still fits inside MaxRooms",
		Manor.roomCount(Config, Config.Night.MaxNight)))
	truthy(worst > M.MaxRooms - M.MaxRepairRooms, string.format(
		"CONTROL: the repair pass really does spend its budget (largest %d vs target cap %d)", worst, M.MaxRooms - M.MaxRepairRooms))
end
eq(plan.night, 1, "the plan remembers its night")

-- Determinism: same seed, same manor. This is the entire claim behind "night 7 is night 7
-- for everybody", so it is checked field by field rather than by identity.
do
	local a, b = planFor(5), planFor(5)
	local same = #a.rooms == #b.rooms and a.entranceId == b.entranceId and a.exitId == b.exitId
		and #a.relics == #b.relics and #a.patrol == #b.patrol and #a.links == #b.links
	if same then
		for i, r in a.rooms do
			local s = b.rooms[i]
			if r.id ~= s.id or r.gx ~= s.gx or r.gz ~= s.gz or r.kind ~= s.kind or r.depth ~= s.depth then
				same = false
			end
		end
		for i, r in a.relics do
			local s = b.relics[i]
			if r.roomId ~= s.roomId or r.slot ~= s.slot or r.tier ~= s.tier then same = false end
		end
		for i, p in a.patrol do
			if b.patrol[i] ~= p then same = false end
		end
	end
	truthy(same, "the same night generates a byte-identical manor")
end

-- ...and different nights do NOT all generate the same manor.
do
	local distinct = {}
	for night = 1, 25 do
		local p = planFor(night)
		local key = ""
		for _, r in p.rooms do key ..= string.format("%d:%d:%s|", r.gx, r.gz, r.kind) end
		distinct[key] = true
	end
	local n = 0
	for _ in distinct do n += 1 end
	truthy(n >= 15, "25 nights produce at least 15 distinct layouts (got " .. n .. ")")
end

--============================================================ structure, over a lot of nights

do
	local cellsOk, boundsOk, linkAdjacent, linkSym, connected = true, true, true, true, true
	local entranceOk, exitOk, exitDeepest, depthOk = true, true, true, true

	for night = 1, 60 do
		local p = planFor(night, night % 7)
		local byId, cells = {}, {}
		for _, r in p.rooms do
			byId[r.id] = r
			local key = r.gx .. "," .. r.gz
			if cells[key] then cellsOk = false end
			cells[key] = r.id
			if math.abs(r.gx) > M.GridSpan or math.abs(r.gz) > M.GridSpan then boundsOk = false end
		end

		-- links join orthogonally adjacent cells, both ways
		local adj = {}
		for _, r in p.rooms do adj[r.id] = {} end
		for _, l in p.links do
			local a, b = byId[l.a], byId[l.b]
			if not a or not b then
				linkAdjacent = false
			else
				local d = math.abs(a.gx - b.gx) + math.abs(a.gz - b.gz)
				if d ~= 1 then linkAdjacent = false end
				table.insert(adj[l.a], l.b)
				table.insert(adj[l.b], l.a)
			end
			if not Manor.linked(p, l.a, l.b) or not Manor.linked(p, l.b, l.a) then linkSym = false end
		end

		-- BFS from the entrance: everything reachable, and `depth` is the real distance
		local dist, queue, head = { [p.entranceId] = 0 }, { p.entranceId }, 1
		while head <= #queue do
			local id = queue[head]; head += 1
			for _, nb in adj[id] do
				if dist[nb] == nil then
					dist[nb] = dist[id] + 1
					table.insert(queue, nb)
				end
			end
		end
		for _, r in p.rooms do
			if dist[r.id] == nil then connected = false
			elseif dist[r.id] ~= r.depth then depthOk = false end
		end

		if byId[p.entranceId] == nil or byId[p.entranceId].kind ~= "foyer" then entranceOk = false end
		if byId[p.exitId] == nil or byId[p.exitId].kind ~= "vestibule" then exitOk = false end
		if p.exitId == p.entranceId then exitOk = false end
		local maxDepth = 0
		for _, r in p.rooms do maxDepth = math.max(maxDepth, r.depth) end
		if byId[p.exitId] and byId[p.exitId].depth ~= maxDepth then exitDeepest = false end
	end

	truthy(cellsOk, "no two rooms ever share a grid cell")
	truthy(boundsOk, "every room stays inside GridSpan")
	truthy(linkAdjacent, "every link joins two orthogonally adjacent rooms")
	truthy(linkSym, "Manor.linked agrees with the link list in both directions")
	truthy(connected, "every room is reachable from the entrance")
	truthy(depthOk, "room.depth is the real BFS distance from the entrance")
	truthy(entranceOk, "the entrance is always the foyer")
	truthy(exitOk, "the exit is always a vestibule and never the entrance")
	truthy(exitDeepest, "the exit is always the deepest room (you have to cross the manor)")
end

--======================================================================== relics on the plan

do
	local countOk, roomOk, slotOk, tierOk, perRoomOk = true, true, true, true, true
	local tierSeen = {}
	local validTier = {}
	for _, t in Config.Relics.Tiers do validTier[t.id] = true end

	for night = 1, 60 do
		local p = planFor(night, night % 5)
		if #p.relics ~= Manor.relicCount(Config, night) then countOk = false end
		local byId = {}
		for _, r in p.rooms do byId[r.id] = r end
		local perRoom, slotKey = {}, {}
		for _, rel in p.relics do
			if byId[rel.roomId] == nil or rel.roomId == p.entranceId then roomOk = false end
			local key = rel.roomId .. "#" .. rel.slot
			if slotKey[key] then slotOk = false end
			slotKey[key] = true
			if not validTier[rel.tier] then tierOk = false end
			tierSeen[rel.tier] = true
			perRoom[rel.roomId] = (perRoom[rel.roomId] or 0) + 1
		end
		for _, n in perRoom do
			if n > Config.Relics.MaxPerRoom then perRoomOk = false end
		end
	end

	truthy(countOk, "the plan places exactly relicCount relics")
	truthy(roomOk, "no relic is placed in the foyer or in a room that does not exist")
	truthy(slotOk, "no two relics share a (room, slot) — they would spawn inside each other")
	truthy(tierOk, "every placed relic is a tier the catalog knows")
	truthy(perRoomOk, "no room holds more than MaxPerRoom relics")
	local kinds = 0
	for _ in tierSeen do kinds += 1 end
	truthy(kinds >= 3, "over 60 nights the generator actually uses several relic tiers (got " .. kinds .. ")")
end

-- Depth bias: deeper rooms must weight the RARER tiers more, and must not touch the first.
do
	local w0 = Manor.tierWeights(Config, 0)
	local w5 = Manor.tierWeights(Config, 5)
	eq(#w0, #Config.Relics.Tiers, "tierWeights returns one weight per tier")
	approx(w0[1], Config.Relics.Tiers[1].weight, 1e-9, "at depth 0 the weights are the base weights")
	approx(w0[#w0], Config.Relics.Tiers[#w0].weight, 1e-9, "...for the last tier too")
	eq(w5[1], w0[1], "depth never boosts the commonest tier")
	truthy(w5[#w5] > w0[#w0], "depth boosts the rarest tier")
	truthy(w5[#w5] / w5[1] > w0[#w0] / w0[1], "the rare:common ratio genuinely rises with depth")
end

--======================================================================== the patrol route

do
	local lenOk, linkedOk, idsOk = true, true, true
	for night = 1, 60 do
		local p = planFor(night, night % 5)
		if #p.patrol ~= Manor.patrolCount(Config, night, #p.rooms) then lenOk = false end
		local byId = {}
		for _, r in p.rooms do byId[r.id] = r end
		for i, id in p.patrol do
			if byId[id] == nil then idsOk = false end
			if i > 1 and not Manor.linked(p, p.patrol[i - 1], id) then linkedOk = false end
		end
	end
	truthy(lenOk, "the patrol has exactly patrolCount waypoints")
	truthy(idsOk, "every patrol waypoint is a real room")
	truthy(linkedOk, "consecutive patrol waypoints are LINKED — the watcher walks doorways, not walls")
end

--=========================================================== shortest path through the rooms

-- The Nightwatcher hunts along this. If it returns a path whose steps are not linked, the
-- chase walks through walls; if it returns nothing between two connected rooms, the chase
-- simply stops and the game has no threat in it at all.
do
	local endpointsOk, stepsLinkedOk, shortestOk, selfOk, missingOk = true, true, true, true, true
	for night = 1, 40 do
		local p = planFor(night, night % 4)
		local byId = {}
		for _, r in p.rooms do byId[r.id] = r end

		local path = Manor.pathBetween(p, p.entranceId, p.exitId)
		if path == nil or #path < 2 then
			endpointsOk = false
		else
			if path[1] ~= p.entranceId or path[#path] ~= p.exitId then endpointsOk = false end
			for i = 2, #path do
				if not Manor.linked(p, path[i - 1], path[i]) then stepsLinkedOk = false end
			end
			-- The layout is a tree, so the shortest entrance->exit walk is exactly the exit's depth.
			if #path - 1 ~= byId[p.exitId].depth then shortestOk = false end
		end

		local same = Manor.pathBetween(p, p.exitId, p.exitId)
		if same == nil or #same ~= 1 or same[1] ~= p.exitId then selfOk = false end

		if Manor.pathBetween(p, p.entranceId, 9999) ~= nil then missingOk = false end
	end
	truthy(endpointsOk, "pathBetween starts at `from` and ends at `to`")
	truthy(stepsLinkedOk, "every step of the path crosses a real doorway")
	truthy(shortestOk, "the path is the SHORTEST one (its length is the exit's depth)")
	truthy(selfOk, "a path to the room you are already in is just that room")
	truthy(missingOk, "pathBetween to a room that does not exist -> nil")
end

--=================================================================== world-space conversions

do
	local p = planFor(3)
	local room = p.rooms[#p.rooms]
	local x, z = Manor.roomCenter(Config, room)
	approx(x, room.gx * M.RoomSize, 1e-9, "roomCenter maps the grid onto studs (x)")
	approx(z, room.gz * M.RoomSize, 1e-9, "roomCenter maps the grid onto studs (z)")
	eq(Manor.roomAtWorld(p, Config, x, z), room.id, "roomAtWorld finds the room at its own centre")
	eq(Manor.roomAtWorld(p, Config, x + M.RoomSize * 0.4, z), room.id, "...and anywhere inside it")
	-- A point far outside the manor belongs to no room. Returning some room anyway would make
	-- the watcher's room-based line of sight true in the middle of nowhere.
	eq(Manor.roomAtWorld(p, Config, (M.GridSpan + 4) * M.RoomSize, 0), nil,
		"roomAtWorld outside the manor -> nil")
end

--=========================================== the chase goes through doorways, not through walls

-- Manor.luau's own comment says the Nightwatcher "beelines toward the CENTRE OF THE NEXT ROOM
-- ON THIS PATH ... which is what keeps it going through doorways instead of through walls".
-- That was only true from a room CENTRE. A hunter standing anywhere else in the room — which is
-- where it always is after a hunt, because it walks at the player — aimed diagonally at the next
-- centre and crossed the wall. The player cannot do that (walls are 1 stud of Brick with a
-- DoorWidth gap), so the chase was being run on two different maps.
do
	local p = planFor(6)
	local a = p.rooms[1]
	local nbs = Manor.neighbours(p, a.id)
	truthy(#nbs > 0, "the foyer has a neighbour to chase into")
	local b = Manor.roomById(p, nbs[1])

	local dx, dz = Manor.doorwayBetween(Config, p, a.id, b.id)
	truthy(dx ~= nil, "doorwayBetween gives a point for two adjacent rooms")
	approx(dx, (a.gx + b.gx) / 2 * M.RoomSize, 1e-9, "...on the shared wall (x)")
	approx(dz, (a.gz + b.gz) / 2 * M.RoomSize, 1e-9, "...on the shared wall (z)")

	-- The doorway is the MIDDLE of the shared edge, which is exactly where buildWall leaves the
	-- gap: two jambs of (RoomSize - DoorWidth)/2 and a DoorWidth hole between them.
	local ax, az = Manor.roomCenter(Config, a)
	local off = math.abs(dx - ax) + math.abs(dz - az)
	approx(off, M.RoomSize / 2, 1e-9, "...half a room from the centre it belongs to")

	-- Non-adjacent rooms share no wall, so there is no doorway between them at all.
	local far
	for _, r in p.rooms do
		if math.abs(r.gx - a.gx) + math.abs(r.gz - a.gz) > 1 then far = r; break end
	end
	truthy(far ~= nil, "the manor has a room that is not next door")
	eq((Manor.doorwayBetween(Config, p, a.id, far.id)), nil, "doorwayBetween on two rooms that share no wall -> nil")
	eq((Manor.doorwayBetween(Config, p, a.id, 9999)), nil, "doorwayBetween on a room that does not exist -> nil")
end

do
	local p = planFor(9)
	local M2 = Config.Manor
	-- Walk a hunter from every room to every other room using ONLY chaseStep, and check that no
	-- step of that walk ever passes through a wall. This is the assertion the old inline
	-- "aim at the next room's centre" could not pass.
	local function insideWall(x1, z1, x2, z2): boolean
		-- sample the segment; a point is in a wall when it is within half a stud of a shared
		-- plane and outside the DoorWidth gap on it (or the plane has no doorway at all)
		local steps = math.max(4, math.ceil(math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) / 0.25))
		for i = 0, steps do
			local t = i / steps
			local x, z = x1 + (x2 - x1) * t, z1 + (z2 - z1) * t
			local gx = math.floor(x / M2.RoomSize + 0.5)
			local gz = math.floor(z / M2.RoomSize + 0.5)
			local function cellAt(cx, cz)
				for _, r in p.rooms do
					if r.gx == cx and r.gz == cz then return r.id end
				end
				return nil
			end
			for k = gx - 1, gx do
				if math.abs(x - (k * M2.RoomSize + M2.RoomSize / 2)) <= 0.5 then
					local A, B = cellAt(k, gz), cellAt(k + 1, gz)
					if A ~= nil or B ~= nil then
						if not (A and B and Manor.linked(p, A, B)) then return true end
						if math.abs(z - gz * M2.RoomSize) > M2.DoorWidth / 2 then return true end
					end
				end
			end
			for m = gz - 1, gz do
				if math.abs(z - (m * M2.RoomSize + M2.RoomSize / 2)) <= 0.5 then
					local A, B = cellAt(gx, m), cellAt(gx, m + 1)
					if A ~= nil or B ~= nil then
						if not (A and B and Manor.linked(p, A, B)) then return true end
						if math.abs(x - gx * M2.RoomSize) > M2.DoorWidth / 2 then return true end
					end
				end
			end
		end
		return false
	end

	local crossings, walks, stuck = 0, 0, 0
	for _, from in p.rooms do
		for _, to in p.rooms do
			if from.id ~= to.id then
				walks += 1
				local x, z = Manor.roomCenter(Config, from)
				-- start OFF centre, in the corner: that is where a hunter that has just walked at
				-- a player stands, and it is the case the old code got wrong.
				x += M2.RoomSize / 2 - 4
				z += M2.RoomSize / 2 - 4
				local here = from.id
				local guard = 0
				while here ~= to.id and guard < 200 do
					guard += 1
					local tx, tz = Manor.chaseStep(Config, p, here, x, z, to.id)
					if tx == nil then break end
					if insideWall(x, z, tx, tz) then crossings += 1 end
					x, z = tx, tz
					here = Manor.roomAtWorld(p, Config, x, z) or here
				end
				if here ~= to.id then stuck += 1 end
			end
		end
	end
	print(string.format("  chaseStep: %d room-to-room walks, %d wall crossings, %d never arrived", walks, crossings, stuck))
	eq(crossings, 0, "a hunter steered by chaseStep never crosses a wall")
	eq(stuck, 0, "...and always arrives")
	eq((Manor.chaseStep(Config, p, 1, 0, 0, 1)), nil, "chaseStep to the room you are already in -> nil (aim at the quarry)")
	eq((Manor.chaseStep(Config, p, 1, 0, 0, 9999)), nil, "chaseStep to a room that does not exist -> nil")
end

--===================================== the way OUT does not stand in the way of the way IN

-- The server builds the ExitDoor as a 10x12 slab six studs inside one face of the exit room, and
-- it always used the +Z face. `DoorWidth` is also 10, and a doorway is the middle ten studs of a
-- shared wall — so on any night where the exit room has a doorway to the cell at (gx, gz+1), the
-- slab stands directly in the gap, exactly aligned with it. Measured on the shipped generator:
-- 61 of 120 nights, and on one of those it was the exit room's ONLY doorway, i.e. the only way
-- into the room you have to reach was a 10-wide hole with a 10-wide slab six studs behind it.
-- Nothing in the repo asserted otherwise, because nothing in the repo knew where the door was.
do
	local blocked, noOuter, outer, worst = 0, 0, 0, nil
	for night = 1, Config.Night.MaxNight do
		local nightPlan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
		local dx, dz = Manor.exitFace(Config, nightPlan)
		if dx == nil then
			noOuter += 1
		else
			local exit = Manor.roomById(nightPlan, nightPlan.exitId) :: any
			local ex, ez = Manor.roomCenter(Config, exit)
			local behind = Manor.roomAtWorld(nightPlan, Config, ex + (dx :: number) * M.RoomSize, ez + (dz :: number) * M.RoomSize)
			if behind == nil then
				outer += 1
			elseif Manor.linked(nightPlan, nightPlan.exitId, behind) then
				blocked += 1
				worst = worst or night
			end
		end
	end
	print(string.format("  nights 1-%d: exit door stands in a live doorway on %d, on the manor's outer wall on %d, no face found on %d",
		Config.Night.MaxNight, blocked, outer, noOuter))
	eq(noOuter, 0, "every exit room has a face the door can stand on")
	eq(blocked, 0, "the exit door never stands in front of a doorway" .. (worst and (" (first: night " .. worst .. ")") or ""))
	-- ...and it is the way OUT of the building, not a glowing slab on an internal wall between
	-- two rooms. A face with nothing behind it exists on almost every night, so the generator has
	-- to actually prefer one; "some solid wall" is not the same requirement.
	truthy(outer >= Config.Night.MaxNight - 5, string.format(
		"the exit door is on the manor's OUTER wall on all but a handful of nights (%d of %d)", outer, Config.Night.MaxNight))
end

do
	-- ...and the face it picks is a real one: a unit step on the grid, one axis only.
	local p12 = Manor.plan(Rng.new(Manor.seedFor(Config, 12)), Config, 12)
	local dx, dz = Manor.exitFace(Config, p12)
	truthy(dx ~= nil, "exitFace answers for a real plan")
	if dx then
		eq(math.abs(dx :: number) + math.abs(dz :: number), 1, "...with a unit orthogonal direction")
	end
	-- A plan whose exit room does not exist has no face at all, rather than a direction into
	-- nothing that the server would then build a door in mid-air on.
	local broken = { rooms = {}, links = {}, relics = {}, patrol = {}, entranceId = 1, exitId = 1, night = 1 }
	eq((Manor.exitFace(Config, broken :: any)), nil, "exitFace on a plan with no exit room -> nil")
end

--============================================================================ CONTROL
-- A change the suite must NOT notice: room NAMES are cosmetic. If renaming a kind turns this
-- suite red, the suite is asserting on flavour text instead of on structure, and every future
-- copy edit becomes a test failure. (The id, by contrast, is load-bearing everywhere.)
do
	local before = Manor.kindById(Config, "cellar").name
	Manor.kindById(Config, "cellar").name = "Wine Cellar"
	local p = planFor(4)
	local ok = #p.rooms >= Manor.roomCount(Config, 4) and p.exitId ~= p.entranceId
		and #p.relics == Manor.relicCount(Config, 4)
	Manor.kindById(Config, "cellar").name = before
	truthy(ok, "CONTROL: renaming a room kind changes nothing structural")
end

print(string.format("Manor: %d passed, %d failed", passed, failed))
if failed > 0 then error("Manor tests failed") end
