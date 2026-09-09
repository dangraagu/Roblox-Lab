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

-- How many rooms this night gets. Grows with the night AND with how much safehouse the player
-- has built (a bigger manor is more loot and more walking, i.e. more dread spent).
function Manor.roomCount(cfg: any, night: number, hubLevel: number): number
	local M = cfg.Manor
	local n = M.BaseRooms
		+ math.floor((math.max(night, 1) - 1) * M.RoomsPerNight + math.max(hubLevel, 0) * M.RoomsPerHubLevel)
	return clamp(n, 2, M.MaxRooms) -- never below entrance + exit
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

-- ------------------------------------------------------------------ generation

-- Build one night's manor. Deterministic in (rng seed, cfg, night, hubLevel).
--
-- Growth, not carving: start with the foyer at (0,0) and repeatedly attach a new room to a
-- random room that still has a free orthogonal neighbour. That yields a connected TREE by
-- construction — every room reachable, no isolated wing, no unreachable exit — and it
-- terminates, because each pass either places a room or permanently retires a full one.
function Manor.plan(rng: RngLike, cfg: any, night: number, hubLevel: number): Plan
	local M = cfg.Manor
	local target = Manor.roomCount(cfg, night, hubLevel)

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
			local d = fd[rng:below(#fd)]
			local id = #rooms + 1
			rooms[id] = { id = id, gx = room.gx + d[1], gz = room.gz + d[2], kind = "hall", depth = room.depth + 1 }
			cells[cellKey(rooms[id].gx, rooms[id].gz)] = id
			table.insert(links, { a = room.id, b = id })
			table.insert(open, id)
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
