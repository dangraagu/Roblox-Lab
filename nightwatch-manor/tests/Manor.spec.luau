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
	eq(Manor.kindById(Config, "library").name, "Library", "kindById finds a kind")
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

eq(Manor.roomCount(Config, 1, 0), M.BaseRooms, "night 1 with no hub == BaseRooms")
truthy(Manor.roomCount(Config, 10, 0) > Manor.roomCount(Config, 1, 0), "the manor grows with the night")
truthy(Manor.roomCount(Config, 1, 10) > Manor.roomCount(Config, 1, 0), "the manor grows with hub level")
eq(Manor.roomCount(Config, 100000, 100000), M.MaxRooms, "room count clamps at MaxRooms")
truthy(Manor.roomCount(Config, 0, 0) >= 2, "there is always room for an entrance and an exit")
truthy(Manor.roomCount(Config, -5, -5) >= 2, "negative inputs cannot shrink it below 2")

eq(Manor.relicCount(Config, 1), Config.Relics.Base, "night 1 relic count == Base")
truthy(Manor.relicCount(Config, 12) > Manor.relicCount(Config, 1), "more relics on later nights")
eq(Manor.relicCount(Config, 100000), Config.Relics.Max, "relic count clamps at Max")

eq(Manor.patrolCount(Config, 1, M.MaxRooms), M.PatrolBase, "night 1 patrol == PatrolBase")
truthy(Manor.patrolCount(Config, 40, M.MaxRooms) > M.PatrolBase, "the patrol lengthens with the night")
eq(Manor.patrolCount(Config, 100000, M.MaxRooms), M.PatrolMax, "patrol clamps at PatrolMax")
truthy(Manor.patrolCount(Config, 100000, 3) <= 3, "the patrol can never be longer than the manor")

--=================================================================================== the plan

local function planFor(night, hub)
	return Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night, hub or 0)
end

local plan = planFor(1)

eq(#plan.rooms, Manor.roomCount(Config, 1, 0), "the plan holds exactly roomCount rooms")
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

--============================================================================ CONTROL
-- A change the suite must NOT notice: room NAMES are cosmetic. If renaming a kind turns this
-- suite red, the suite is asserting on flavour text instead of on structure, and every future
-- copy edit becomes a test failure. (The id, by contrast, is load-bearing everywhere.)
do
	local before = Manor.kindById(Config, "cellar").name
	Manor.kindById(Config, "cellar").name = "Wine Cellar"
	local p = planFor(4)
	local ok = #p.rooms == Manor.roomCount(Config, 4, 0) and p.exitId ~= p.entranceId
		and #p.relics == Manor.relicCount(Config, 4)
	Manor.kindById(Config, "cellar").name = before
	truthy(ok, "CONTROL: renaming a room kind changes nothing structural")
end

print(string.format("Manor: %d passed, %d failed", passed, failed))
if failed > 0 then error("Manor tests failed") end
