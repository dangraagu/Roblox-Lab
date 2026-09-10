--!strict
-- Manor.luau — the seeded procedural manor layout. PURE LOGIC, no Roblox globals: the server
-- turns the plan it returns into parts, and the luau-CLI spec exercises the same plan with no
-- engine present.
--
-- NOTE: this module deliberately does NOT `require` Rng. A bare string require like
-- `require("./Rng")` resolves in the luau CLI and is INVALID in Roblox (require takes an
-- Instance), which would make the whole server script fail to load while every unit test
-- stayed green. The rng is passed IN and used through its methods (`rng:next()`,
-- `rng:below(n)`), and the config is passed in too. Same rule for every module in src/shared.
export type RngLike = { next: (any) -> number, below: (any, number) -> number }

export type Room = { id: number, gx: number, gz: number, kind: string, depth: number }
export type Link = { a: number, b: number }
export type RelicSpot = { roomId: number, slot: number, tier: string }
export type Plan = {
	night: number,
	rooms: { Room },
	links: { Link },
	relics: { RelicSpot },
	patrol: { number },
	entranceId: number,
	exitId: number,
}

local Manor = {}

-- The four orthogonal grid steps, in a FIXED order. The rng picks an index into this list, so
-- reordering it changes every layout in the game — treat it as part of the seed.
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function cellKey(gx: number, gz: number): string
	return gx .. "," .. gz
end

-- Weighted pick over a parallel list of weights. Consumes exactly ONE draw, and goes through
-- `next()` (high bits) rather than any modulo, so a power-of-two list length cannot collapse
-- it onto the seed's low bits — the defect that pinned a sibling game to one outcome forever.
local function weightedIndex(rng: RngLike, weights: { number }): number
	local total = 0
	for _, w in weights do
		total += math.max(w, 0)
	end
	if total <= 0 then
		return 1
	end
	local roll = rng:next() * total
	local acc = 0
	for i, w in weights do
		acc += math.max(w, 0)
		if roll < acc then
			return i
		end
	end
	return #weights
end

-- ------------------------------------------------------------------ catalog + curves

function Manor.kindById(cfg: any, id: string): any
	for _, k in cfg.Manor.Kinds do
		if k.id == id then
			return k
		end
	end
	return nil
end

-- The layout seed. Folds the WorldSeed and the NIGHT and nothing else — no userId — so night
-- N is the same manor for every player, which is the only reason "I survived night 14" says
-- anything. Both products stay far below 2^53, so no low bits are lost to float rounding.
function Manor.seedFor(cfg: any, night: number): number
	return cfg.WorldSeed * cfg.SeedPrimeA + math.floor(math.max(night, 0)) * cfg.SeedPrimeB
end

-- How many rooms this night gets. Grows with the NIGHT and with nothing else.
--
-- It used to fold in the player's hub level, and that was the single most expensive line in the
-- game. It made the headline claim ("night 7 is the same manor for everybody") false, so no two
-- best-night numbers were comparable; and because the exit is always the DEEPEST room, it meant
-- every upgrade anybody bought lengthened their own walk out — a silent anti-synergy in a tycoon,
-- with nothing on screen to explain it. The size of a night is a property of the night.
-- This returns the GROWTH TARGET, not the size of the finished manor: the dead-end repair pass in
-- `plan` may add up to `MaxRepairRooms` more on top. `MaxRooms` is the cap on the TOTAL, so the
-- target has to stop that far short of it — otherwise the number in the config is not a maximum of
-- anything, and worse, on any night where the target reaches MaxRooms the repair pass is left with
-- a budget of zero and the dead ends it exists to close come straight back. It used to clamp AT
-- MaxRooms, which put 468 of nights 1-500 over the config's own limit (largest manor 23 against a
-- MaxRooms of 18).
function Manor.roomCount(cfg: any, night: number): number
	local M = cfg.Manor
	local n = M.BaseRooms + math.floor((math.max(night, 1) - 1) * M.RoomsPerNight)
	return clamp(n, 2, math.max(M.MaxRooms - M.MaxRepairRooms, 2)) -- never below entrance + exit
end

-- How many relics are placed. IMPORTANT: this must stay <= (roomCount - 1) * MaxPerRoom for
-- every night, or `plan` places fewer than it promises. The spec asserts the equality, so a
-- retune that breaks the relationship fails the suite rather than quietly shorting the player.
function Manor.relicCount(cfg: any, night: number): number
	local R = cfg.Relics
	local n = R.Base + math.floor((math.max(night, 1) - 1) * R.PerNight)
	return clamp(n, 1, R.Max)
end

-- Waypoints on the Nightwatcher's route. Never longer than the manor itself.
function Manor.patrolCount(cfg: any, night: number, rooms: number): number
	local M = cfg.Manor
	local hi = math.min(M.PatrolMax, math.max(math.floor(rooms), 1))
	local n = M.PatrolBase + math.floor((math.max(night, 1) - 1) * M.PatrolPerNight)
	return clamp(n, math.min(2, hi), hi)
end

-- Relic-tier draw weights at a given room depth. Depth never touches the commonest tier, and
-- lifts each rarer tier by DepthBias per tier-step per room of depth: the far end of the manor
-- is where the good stuff is, which is the only thing making the walk worth the dread.
function Manor.tierWeights(cfg: any, depth: number): { number }
	local out = {}
	local d = math.max(depth, 0)
	for i, t in cfg.Relics.Tiers do
		out[i] = t.weight * (1 + d * cfg.Relics.DepthBias * (i - 1))
	end
	return out
end

-- ------------------------------------------------------------------ plan queries

function Manor.roomById(plan: Plan, id: number): Room?
	for _, r in plan.rooms do
		if r.id == id then
			return r
		end
	end
	return nil
end

-- Grid cell -> world studs, relative to the manor's own origin. The server adds the zone
-- offset; nothing here knows where in the world the manor sits.
function Manor.roomCenter(cfg: any, room: Room): (number, number)
	return room.gx * cfg.Manor.RoomSize, room.gz * cfg.Manor.RoomSize
end

-- World studs -> room id, or nil when the point is not inside any room. Returning "the nearest
-- room" instead of nil would make the watcher's room-based line of sight true out in the void.
function Manor.roomAtWorld(plan: Plan, cfg: any, x: number, z: number): number?
	local size = cfg.Manor.RoomSize
	local gx = math.floor(x / size + 0.5)
	local gz = math.floor(z / size + 0.5)
	for _, r in plan.rooms do
		if r.gx == gx and r.gz == gz then
			return r.id
		end
	end
	return nil
end

function Manor.linked(plan: Plan, a: number, b: number): boolean
	for _, l in plan.links do
		if (l.a == a and l.b == b) or (l.a == b and l.b == a) then
			return true
		end
	end
	return false
end

function Manor.neighbours(plan: Plan, id: number): { number }
	local out = {}
	for _, l in plan.links do
		if l.a == id then
			table.insert(out, l.b)
		elseif l.b == id then
			table.insert(out, l.a)
		end
	end
	return out
end

-- Shortest room-to-room walk, as a list of room ids starting at `from` and ending at `to`.
-- Nil when either end does not exist or nothing connects them.
--
-- This is the Nightwatcher's chase: it beelines toward the CENTRE OF THE NEXT ROOM ON THIS
-- PATH rather than at the player directly, which is what keeps it going through doorways
-- instead of through walls. A BFS over at most MaxRooms nodes is nothing at runtime, and being
-- pure Luau it is testable here — unlike Roblox's PathfindingService, which the brief rules
-- out and which this deliberately is not.
function Manor.pathBetween(plan: Plan, from: number, to: number): { number }?
	local exists = {}
	for _, r in plan.rooms do
		exists[r.id] = true
	end
	if not exists[from] or not exists[to] then
		return nil
	end
	if from == to then
		return { from }
	end

	local adj: { [number]: { number } } = {}
	for _, r in plan.rooms do
		adj[r.id] = {}
	end
	for _, l in plan.links do
		if adj[l.a] and adj[l.b] then
			table.insert(adj[l.a], l.b)
			table.insert(adj[l.b], l.a)
		end
	end

	local prev: { [number]: number } = {}
	local seen = { [from] = true }
	local queue, head = { from }, 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		if id == to then
			local path = { to }
			local cur = to
			while cur ~= from do
				cur = prev[cur]
				table.insert(path, 1, cur)
			end
			return path
		end
		for _, nb in adj[id] do
			if not seen[nb] then
				seen[nb] = true
				prev[nb] = id
				table.insert(queue, nb)
			end
		end
	end
	return nil
end

-- Where the doorway between two rooms IS, in the manor's own studs. `buildWall` splits a shared
-- wall into two jambs of `(RoomSize - DoorWidth) / 2` with the gap in the MIDDLE, so the middle
-- of the shared edge is the middle of the hole. Nil when the two rooms do not share a wall.
function Manor.doorwayBetween(cfg: any, plan: Plan, a: number, b: number): (number?, number?)
	local ra, rb = Manor.roomById(plan, a), Manor.roomById(plan, b)
	if not ra or not rb then
		return nil, nil
	end
	if math.abs(ra.gx - rb.gx) + math.abs(ra.gz - rb.gz) ~= 1 then
		return nil, nil
	end
	local s = cfg.Manor.RoomSize
	return (ra.gx + rb.gx) / 2 * s, (ra.gz + rb.gz) / 2 * s
end

-- Which face of the exit room the way OUT should be built on, as a unit grid step. Nil when the
-- plan has no exit room.
--
-- The server hangs a 10-wide, 12-tall slab six studs inside this face. `DoorWidth` is also 10 and
-- a doorway is the middle ten studs of a shared wall, so a face that HAS a doorway gets the slab
-- planted squarely in the gap — on 61 of 120 nights with the shipped generator, and on one of
-- them in the exit room's only doorway. So: prefer a face with nothing behind it at all (the
-- outside of the manor, which is where a servants' exit belongs anyway); then a face shared with
-- a room the exit is NOT linked to, which is still solid wall; and only if the exit room is
-- somehow doored on all four sides, the last face, so the server always has somewhere to build.
-- Deterministic: DIRS is walked in its fixed order and the first match wins.
function Manor.exitFace(cfg: any, plan: Plan): (number?, number?)
	local exit = Manor.roomById(plan, plan.exitId)
	if not exit then
		return nil, nil
	end
	local occupied: { [string]: number } = {}
	for _, r in plan.rooms do
		occupied[cellKey(r.gx, r.gz)] = r.id
	end
	local fallback: { number }? = nil
	for _, d in DIRS do
		local nb = occupied[cellKey(exit.gx + d[1], exit.gz + d[2])]
		if nb == nil then
			return d[1], d[2] -- the outside of the manor: nothing to block, nothing to be blocked by
		end
		if fallback == nil and not Manor.linked(plan, exit.id, nb) then
			fallback = d -- a shared wall with no hole in it
		end
	end
	if fallback then
		return fallback[1], fallback[2]
	end
	local last = DIRS[#DIRS]
	return last[1], last[2]
end

-- Where something standing at (x, z) in room `fromId` should walk NEXT in order to reach room
-- `toId`. Nil when it is already there (the caller then aims at the quarry itself) or when
-- nothing connects the two.
--
-- This exists because "aim at the centre of the next room on the path" is only wall-safe from a
-- room CENTRE, and the Nightwatcher is never at a centre once a hunt has started — it has been
-- walking at a player. From a corner, the line to the next centre crosses the wall, and the
-- player cannot follow it: walls are real parts with a DoorWidth hole in the middle. The chase
-- was being run on two different maps, and the one the hunter used was the shorter one. So it
-- steers at the DOORWAY until it is standing in the gap, and only then at the room beyond.
--
-- The clearance is a quarter of DoorWidth rather than a bare constant so a retune of the doorway
-- carries it. Without it the walk DEADLOCKS: `roomAtWorld` resolves a point exactly on a shared
-- plane to the higher cell, so a hunter that arrives at a doorway heading toward the LOWER cell
-- is still "in" the room it came from, still targeting the doorway it is standing on, zero studs
-- away, and never moves again.
function Manor.chaseStep(cfg: any, plan: Plan, fromId: number, x: number, z: number, toId: number): (number?, number?)
	if fromId == toId then
		return nil, nil
	end
	local path = Manor.pathBetween(plan, fromId, toId)
	local nextId = path and path[2]
	if not nextId then
		return nil, nil
	end
	local nextRoom = Manor.roomById(plan, nextId)
	if not nextRoom then
		return nil, nil
	end
	local cx, cz = Manor.roomCenter(cfg, nextRoom)
	local dx, dz = Manor.doorwayBetween(cfg, plan, fromId, nextId)
	if dx == nil then
		return cx, cz
	end
	local clear = cfg.Manor.DoorWidth * 0.25
	if (x - (dx :: number)) ^ 2 + (z - (dz :: number)) ^ 2 <= clear * clear then
		return cx, cz
	end
	return dx, dz
end

-- ------------------------------------------------------------------ generation

-- Build one night's manor. Deterministic in (rng seed, cfg, night) and NOTHING else — no
-- userId, no hub level, no profile. That is what makes "I got out of night 14" a claim two
-- players can compare, and it is the only reason memorisable layouts are worth accepting.
--
-- Growth, not carving: start with the foyer at (0,0) and repeatedly attach a new room to a
-- random room that still has a free orthogonal neighbour. Every room is therefore reachable by
-- construction — no isolated wing, no unreachable exit — and it terminates, because each pass
-- either places a room or permanently retires a full one.
--
-- THEN LOOPS. Attachment alone yields a tree, and a tree is a manor with no way round: every
-- branch ends in a dead end, so a player being chased runs until the rooms stop and is then
-- caught no matter how much faster they are. Measured on these exact seeds: 4-6 of every 6-11
-- rooms were dead ends, and a fleeing player was cornered on 8 of nights 1-12 even against a
-- Nightwatcher it outran by 7.5 studs/s. So each new room also opens a doorway, with
-- probability `ExtraDoorChance`, through every OTHER wall it already shares with a built room.
-- Doorways are only ever ADDED, so nothing can become unreachable; what changes is that the
-- manor now contains circuits you can run around, which is what "keep moving" needs to be true.
function Manor.plan(rng: RngLike, cfg: any, night: number): Plan
	local M = cfg.Manor
	local target = Manor.roomCount(cfg, night)

	local rooms: { Room } = {}
	local links: { Link } = {}
	local cells: { [string]: number } = {}

	local function inBounds(gx: number, gz: number): boolean
		return math.abs(gx) <= M.GridSpan and math.abs(gz) <= M.GridSpan
	end
	local function freeDirs(room: Room): { { number } }
		local out = {}
		for _, d in DIRS do
			local gx, gz = room.gx + d[1], room.gz + d[2]
			if inBounds(gx, gz) and cells[cellKey(gx, gz)] == nil then
				table.insert(out, d)
			end
		end
		return out
	end

	rooms[1] = { id = 1, gx = 0, gz = 0, kind = "foyer", depth = 0 }
	cells[cellKey(0, 0)] = 1

	local open = { 1 } -- room ids that MIGHT still have a free neighbour
	while #rooms < target and #open > 0 do
		local pick = rng:below(#open)
		local room = rooms[open[pick]]
		local fd = freeDirs(room)
		if #fd == 0 then
			table.remove(open, pick) -- retired: boxed in on all four sides
		else
			-- Prefer a cell that ALREADY touches other built rooms. A uniform pick grows tendrils,
			-- and a tendril is a corridor of dead ends; weighting by how many built walls the new
			-- cell would share makes the manor close on itself into circuits instead.
			local w = {}
			for i, cand in fd do
				local cx, cz = room.gx + cand[1], room.gz + cand[2]
				local touch = 0
				for _, dd in DIRS do
					if cells[cellKey(cx + dd[1], cz + dd[2])] ~= nil then
						touch += 1
					end
				end
				w[i] = touch * touch -- touch is at least 1: the room it is growing from
			end
			local d = fd[weightedIndex(rng, w)]
			local id = #rooms + 1
			rooms[id] = { id = id, gx = room.gx + d[1], gz = room.gz + d[2], kind = "hall", depth = 0 }
			cells[cellKey(rooms[id].gx, rooms[id].gz)] = id
			table.insert(links, { a = room.id, b = id })
			table.insert(open, id)

			-- ...and a doorway through every OTHER wall this room already shares with a built
			-- one, so the manor has circuits in it rather than only branches.
			for _, dd in DIRS do
				local nb = cells[cellKey(rooms[id].gx + dd[1], rooms[id].gz + dd[2])]
				if nb ~= nil and nb ~= room.id and rng:next() < M.ExtraDoorChance then
					table.insert(links, { a = nb, b = id })
				end
			end
		end
	end

	-- CLOSE THE DEAD ENDS. A room with a single doorway is a room a chased player cannot leave,
	-- and being faster than the Nightwatcher only means something if running has somewhere to go:
	-- with the speeds fixed but the dead ends left in, a fleeing player was still cornered on 3
	-- of nights 1-20, every time in a one-door room. Each pass takes a dead end and puts a NEW
	-- room in a free cell that touches BOTH it and something else already built — so the dead end
	-- gains a second doorway and the new room is born with two, which is why this pass cannot
	-- create the problem it exists to fix. It consumes no rng draws (the shape decides
	-- everything), so the layout downstream of it is unchanged. It stops when no such cell exists
	-- — some shapes genuinely cannot be closed — or when the repair budget runs out.
	do
		-- ...and the total stays inside MaxRooms by construction, because `roomCount` above stops
		-- the growth target MaxRepairRooms short of it. That is the whole cap: one clamp, in one
		-- place, that a test can actually kill. There WAS a second `math.min(..., M.MaxRooms)`
		-- here; with the target already clamped it was arithmetically unreachable for every legal
		-- config, and an unreachable guard is the thing this review keeps finding. What it was
		-- standing in for is a config invariant, and Manor.spec asserts that instead:
		--     MaxRooms >= MaxRepairRooms + 2
		-- (below which `roomCount`'s floor at 2 could out-vote the cap).
		local budget = target + M.MaxRepairRooms
		while #rooms < budget do
			local deg: { [number]: number } = {}
			for _, r in rooms do
				deg[r.id] = 0
			end
			for _, l in links do
				deg[l.a] += 1
				deg[l.b] += 1
			end

			local function addRoom(cx: number, cz: number): number
				local id = #rooms + 1
				rooms[id] = { id = id, gx = cx, gz = cz, kind = "hall", depth = 0 }
				cells[cellKey(cx, cz)] = id
				for _, dd in DIRS do
					local nb = cells[cellKey(cx + dd[1], cz + dd[2])]
					if nb ~= nil and nb ~= id then
						table.insert(links, { a = nb, b = id })
					end
				end
				return id
			end
			local function freeCell(cx: number, cz: number): boolean
				return inBounds(cx, cz) and cells[cellKey(cx, cz)] == nil
			end
			local function builtNeighbours(cx: number, cz: number): number
				local n = 0
				for _, dd in DIRS do
					if cells[cellKey(cx + dd[1], cz + dd[2])] ~= nil then
						n += 1
					end
				end
				return n
			end

			local placed = false
			for _, r in rooms do
				if deg[r.id] > 1 then
					continue
				end
				-- Cheapest close: one new room touching this dead end AND something else.
				for _, d in DIRS do
					local cx, cz = r.gx + d[1], r.gz + d[2]
					if freeCell(cx, cz) and builtNeighbours(cx, cz) >= 2 then
						addRoom(cx, cz)
						placed = true
						break
					end
				end
				-- Failing that, square the corner: two new rooms alongside this one and the room
				-- it hangs off, which makes a 2x2 block and therefore a circuit. Costs one extra
				-- room and always works when the two cells are free, which a snaking manor —
				-- the shape that produces long dead ends — nearly always leaves open.
				if not placed and #rooms + 2 <= budget then
					-- `rooms` is indexed by id, so the room on the other end of the link is a
					-- straight lookup.
					local host: Room? = nil
					for _, l in links do
						if l.a == r.id then
							host = rooms[l.b]
						elseif l.b == r.id then
							host = rooms[l.a]
						end
						if host then
							break
						end
					end
					if host then
						local px, pz = -(r.gz - host.gz), r.gx - host.gx -- perpendicular to the link
						for _, sign in { 1, -1 } do
							local ax, az = r.gx + px * sign, r.gz + pz * sign
							local bx, bz = host.gx + px * sign, host.gz + pz * sign
							if freeCell(ax, az) and freeCell(bx, bz) then
								addRoom(ax, az)
								addRoom(bx, bz)
								placed = true
								break
							end
						end
					end
				end
				if placed then
					break
				end
			end
			if not placed then
				break
			end
		end
	end

	-- Depth is the number of DOORWAYS from the foyer, measured on the finished graph. It has to
	-- be computed here rather than stamped on at placement: an extra doorway is a shortcut, and
	-- a room's parent is no longer necessarily its closest way home.
	do
		local adjD: { [number]: { number } } = {}
		for _, r in rooms do
			adjD[r.id] = {}
		end
		for _, l in links do
			table.insert(adjD[l.a], l.b)
			table.insert(adjD[l.b], l.a)
		end
		local seen = { [1] = true }
		local queue, head = { 1 }, 1
		rooms[1].depth = 0
		while head <= #queue do
			local id = queue[head]
			head += 1
			for _, nb in adjD[id] do
				if not seen[nb] then
					seen[nb] = true
					rooms[nb].depth = rooms[id].depth + 1
					table.insert(queue, nb)
				end
			end
		end
	end

	-- The exit is the DEEPEST room: you always have to cross the whole manor to leave. Ties go
	-- to the lowest id, which is deterministic (iteration is in insertion order).
	local exitId, best = 1, -1
	for _, r in rooms do
		if r.depth > best then
			best = r.depth
			exitId = r.id
		end
	end

	-- Flavour kinds for everything that is not the entrance or the exit.
	local drawable, weights = {}, {}
	for _, k in M.Kinds do
		if k.weight and k.weight > 0 then
			table.insert(drawable, k.id)
			table.insert(weights, k.weight)
		end
	end
	for _, r in rooms do
		if r.id == 1 then
			r.kind = "foyer"
		elseif r.id == exitId then
			r.kind = "vestibule"
		elseif #drawable > 0 then
			r.kind = drawable[weightedIndex(rng, weights)]
		end
	end

	-- Relics. Every non-foyer room contributes MaxPerRoom candidate slots weighted by depth, and
	-- the draw is WITHOUT REPLACEMENT so two relics can never spawn inside each other.
	local slots: { { roomId: number, slot: number, depth: number } } = {}
	for _, r in rooms do
		if r.id ~= 1 then
			for s = 1, cfg.Relics.MaxPerRoom do
				table.insert(slots, { roomId = r.id, slot = s, depth = r.depth })
			end
		end
	end
	local relics: { RelicSpot } = {}
	local want = math.min(Manor.relicCount(cfg, night), #slots)
	for _ = 1, want do
		local w = {}
		for i, s in slots do
			w[i] = 1 + s.depth
		end
		local idx = weightedIndex(rng, w)
		local chosen = table.remove(slots, idx)
		if chosen then
			local tiers = cfg.Relics.Tiers
			local tier = tiers[weightedIndex(rng, Manor.tierWeights(cfg, chosen.depth))]
			table.insert(relics, { roomId = chosen.roomId, slot = chosen.slot, tier = tier.id })
		end
	end

	-- Patrol route: a walk along LINKED rooms, so the Nightwatcher goes through doorways. It
	-- avoids turning straight back the way it came unless the room is a dead end.
	local adj: { [number]: { number } } = {}
	for _, r in rooms do
		adj[r.id] = {}
	end
	for _, l in links do
		table.insert(adj[l.a], l.b)
		table.insert(adj[l.b], l.a)
	end

	local pc = Manor.patrolCount(cfg, night, #rooms)
	local startPool = {}
	for _, r in rooms do
		if r.id ~= 1 or #rooms == 1 then
			table.insert(startPool, r.id)
		end
	end
	if #startPool == 0 then
		startPool = { 1 }
	end
	local current = startPool[rng:below(#startPool)]
	local patrol = { current }
	local prev: number? = nil
	while #patrol < pc do
		local nbs = adj[current]
		if #nbs == 0 then
			break
		end
		local pool = {}
		for _, nb in nbs do
			if nb ~= prev then
				table.insert(pool, nb)
			end
		end
		if #pool == 0 then
			pool = nbs
		end
		local nxt = pool[rng:below(#pool)]
		table.insert(patrol, nxt)
		prev = current
		current = nxt
	end

	return {
		night = night,
		rooms = rooms,
		links = links,
		relics = relics,
		patrol = patrol,
		entranceId = 1,
		exitId = exitId,
	}
end

return Manor
