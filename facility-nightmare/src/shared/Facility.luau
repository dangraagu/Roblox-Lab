--!strict
-- Facility.luau — the sublevel generator, the model explorer and the blackout front. PURE.
--
-- A function of (cfg, k, seeds, Rng, MazeGen). It requires NOTHING: a bare `require("./X")`
-- resolves in the luau CLI and is INVALID in Roblox, so every dependency is an argument, and the
-- server hands in the ReplicatedStorage copies.
--
-- The layout and loot draws are, draw for draw, the ones design-measure/sim.luau made — the
-- same MazeGen, the same row-major extra-door pass, the same entry/exit/loot order — which is
-- what lets tests/Facility.spec.luau reproduce DESIGN.md Appendix A's M1 table with THIS module.
-- If that reproduction ever breaks, re-measure M1..M11 against this file and edit the spec's
-- numbers; do not tune this file toward the rig.
--
-- Coordinates. A plan's grid is centred on the zone origin. Cell id = cy * n + cx + 1, with cx
-- running along +X and cy along +Z. Everything returned here is in studs, local to the grid
-- centre (cellCenter / doorPoint) or local to a room's centre at floor-top height (roomParts,
-- item and prop positions). The server adds the world origin; this file never sees one.
--
-- WHAT MUST NEVER LEAVE THE SERVER, and why this file does not care: a plan holds the exit,
-- every item's room, and `d[]`. Replicating any of it gives the floor away. This module only
-- computes; `Main.server.luau` decides what is written to an Instance (DESIGN.md §7.3).

local Facility = {}

--============================================================================ schedule + slack

-- §3: the first schedule row whose `upTo` covers k.
function Facility.shape(cfg: any, k: number): any
	for _, row in cfg.Facility.Schedule do
		if k <= row.upTo then
			return { grid = row.grid, fuses = row.fuses, cells = row.cells }
		end
	end
	local last = cfg.Facility.Schedule[#cfg.Facility.Schedule]
	return { grid = last.grid, fuses = last.fuses, cells = last.cells }
end

-- slack(k) = Smin + (S1 - Smin) * (1 + (k - 1) / K) ^ -e. Decays toward Smin, never reaches it.
function Facility.slack(cfg: any, k: number): number
	local f = cfg.Front
	return f.SlackMin + (f.SlackStart - f.SlackMin) * (1 + (k - 1) / f.SlackK) ^ (-f.SlackExponent)
end

-- Three independent seeds per sublevel, from an engine `Random` (or anything with NextInteger).
-- [0, 2^31 - 1) keeps every intermediate far below 2^53 (checklist: seed overflow).
function Facility.drawSeeds(random: any): any
	return {
		layout = random:NextInteger(0, 2147483646),
		loot = random:NextInteger(0, 2147483646),
		decor = random:NextInteger(0, 2147483646),
	}
end

--============================================================================ grid geometry

local function coords(n: number, id: number): (number, number)
	local cx = (id - 1) % n
	local cy = (id - 1 - cx) / n
	return cx, cy
end

function Facility.cellCenter(cfg: any, n: number, id: number): (number, number)
	local cx, cy = coords(n, id)
	local s = cfg.Facility.CellSize
	return (cx - (n - 1) / 2) * s, (cy - (n - 1) / 2) * s
end

-- The cell a grid-local point lies in, or nil outside the grid.
function Facility.cellOf(cfg: any, n: number, x: number, z: number): number?
	local s = cfg.Facility.CellSize
	local cx = math.floor(x / s + n / 2)
	local cy = math.floor(z / s + n / 2)
	if cx < 0 or cy < 0 or cx >= n or cy >= n then
		return nil
	end
	return cy * n + cx + 1
end

-- Unit axis from room a toward its grid neighbour b.
function Facility.neighbourDir(n: number, a: number, b: number): (number, number)
	local ax, ay = coords(n, a)
	local bx, by = coords(n, b)
	return bx - ax, by - ay
end

-- The midpoint of the edge a shares with b: where the doorway is.
function Facility.doorPoint(cfg: any, n: number, a: number, b: number): (number, number)
	local cx, cz = Facility.cellCenter(cfg, n, a)
	local dx, dz = Facility.neighbourDir(n, a, b)
	local half = cfg.Facility.CellSize / 2
	return cx + dx * half, cz + dz * half
end

-- The closed doorways of `cell` that a trusted position (x, z) is close enough to open.
-- `isOpen(a, b)` is the server's own open-door set. Only the trusted cell's doorways are
-- considered, so standing against a wall can never open a door in a room you are not in.
function Facility.doorsNear(cfg: any, plan: any, cell: number, x: number, z: number, isOpen: (number, number) -> boolean): { number }
	local out = {}
	local r = cfg.Facility.DoorOpenRadius
	for _, nb in plan.adj[cell] or {} do
		if not isOpen(cell, nb) then
			local px, pz = Facility.doorPoint(cfg, plan.n, cell, nb)
			local dx, dz = x - px, z - pz
			if dx * dx + dz * dz <= r * r then
				table.insert(out, nb)
			end
		end
	end
	return out
end

--============================================================================ the plan

-- A 32-bit multiply that never leaves the exact-integer range of a double (a * b can reach 2^64).
local function mul32(a: number, b: number): number
	local bl = b % 65536
	local bh = (b - bl) / 65536
	return ((a * bh) % 65536 * 65536 + a * bl) % 4294967296
end

-- The seed of ONE built room's own dressing stream: its item's offset (if it holds one), then its
-- props. murmur3's 32-bit finaliser over (seed, room): without it neighbouring rooms' streams would be
-- seeds a constant apart, and an LCG's outputs from such seeds march in lockstep from room to room.
--
-- WHY PER ROOM (REVIEW-1 A1). What a client can read off a built room must be a function of that
-- room alone. An item offset drawn from the loot stream after the room choices handed a client the
-- loot stream's whole state (`Rng.next` is state / 2^32), and from it every fuse room; props drawn
-- room after room from one decor stream shifted with every earlier room's doors and item. A room's
-- own stream can only ever tell a client about that room, which it is standing in. Recovering the
-- decor seed from it tells a client where an item WOULD stand in any room, never which rooms hold
-- one: that is the loot stream's, and nothing replicated is drawn from it.
function Facility.roomSeed(seed: number, room: number): number
	local h = (seed + room * 2654435761) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

local function bfs(adj: any, n2: number, src: number): { number }
	local d = {}
	for i = 1, n2 do d[i] = -1 end
	d[src] = 0
	local q, h = { src }, 1
	while h <= #q do
		local a = q[h]
		h += 1
		for _, b in adj[a] do
			if d[b] < 0 then
				d[b] = d[a] + 1
				table.insert(q, b)
			end
		end
	end
	return d
end

local function rectDist(a: any, b: any): number
	local gx = math.max(a.minX - b.maxX, b.minX - a.maxX, 0)
	local gz = math.max(a.minZ - b.maxZ, b.minZ - a.maxZ, 0)
	return math.sqrt(gx * gx + gz * gz)
end

-- Up to PropsPerRoomMax props against the walls of one room, from the DECOR stream only. A prop
-- is kept only if it clears every doorway opening by PropDoorClearance (one character hull, so it
-- can never narrow an approach below a body's width), stays out of the room's item pickup circle,
-- off the centre pad and off every other prop; otherwise that attempt is discarded.
local function placeProps(cfg: any, plan: any, room: number, rng: any): { any }
	local F = cfg.Facility
	local inner = F.CellSize / 2 - F.WallThickness
	local hw = F.DoorWidth / 2
	local segs = {}
	for _, nb in plan.adj[room] do
		local dx, dz = Facility.neighbourDir(plan.n, room, nb)
		if dx ~= 0 then
			table.insert(segs, { minX = dx * inner, maxX = dx * inner, minZ = -hw, maxZ = hw })
		else
			table.insert(segs, { minX = -hw, maxX = hw, minZ = dz * inner, maxZ = dz * inner })
		end
	end
	local item = plan.items[room]
	local ph = F.CenterPadHalf
	local pad = { minX = -ph, maxX = ph, minZ = -ph, maxZ = ph }

	local out = {}
	local count = rng:below(F.PropsPerRoomMax + 1) - 1
	for _ = 1, count do
		for _ = 1, F.PropAttempts do
			local kit = F.PropKit[rng:below(#F.PropKit)]
			local side = rng:below(4)
			local along = rng:next()
			local span = 2 * inner - kit.along
			local c = -inner + kit.along / 2 + along * span
			local x, z, sx, sz
			if side == 1 then
				x, z, sx, sz = inner - kit.depth / 2, c, kit.depth, kit.along
			elseif side == 2 then
				x, z, sx, sz = -inner + kit.depth / 2, c, kit.depth, kit.along
			elseif side == 3 then
				x, z, sx, sz = c, inner - kit.depth / 2, kit.along, kit.depth
			else
				x, z, sx, sz = c, -inner + kit.depth / 2, kit.along, kit.depth
			end
			local r = { minX = x - sx / 2, maxX = x + sx / 2, minZ = z - sz / 2, maxZ = z + sz / 2 }
			local ok = rectDist(r, pad) > 0
			for _, s in segs do
				if ok and rectDist(r, s) < F.PropDoorClearance then ok = false end
			end
			if ok and item then
				if rectDist(r, { minX = item.x, maxX = item.x, minZ = item.z, maxZ = item.z }) < F.PickupRadius then
					ok = false
				end
			end
			for _, o in out do
				if ok and r.minX < o.x + o.sx / 2 and o.x - o.sx / 2 < r.maxX
					and r.minZ < o.z + o.sz / 2 and o.z - o.sz / 2 < r.maxZ then
					ok = false
				end
			end
			if ok then
				table.insert(out, {
					name = kit.name, x = x, z = z, sx = sx, sz = sz,
					sy = kit.height, y = (kit.lift or 0) + kit.height / 2,
				})
				break
			end
		end
	end
	return out
end

-- spec = { n, fuses, cells, onboarding }, seeds = { layout, loot, decor }.
function Facility.plan(cfg: any, spec: any, seeds: any, Rng: any, MazeGen: any): any
	local F = cfg.Facility
	local n = spec.n
	local n2 = n * n
	local function id(x: number, y: number): number
		return y * n + x + 1
	end

	-- walls: the proven perfect maze, then extra doors, all from the LAYOUT stream
	local rng = Rng.new(seeds.layout)
	local grid = MazeGen.generate(n, n, rng)
	local adj: { [number]: { number } } = {}
	for i = 1, n2 do adj[i] = {} end
	local links = {}
	local function link(a, b)
		table.insert(adj[a], b)
		table.insert(adj[b], a)
		table.insert(links, { math.min(a, b), math.max(a, b) })
	end
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x < n - 1 then
				local open = grid[2 * y + 1][2 * x + 2] == false
				if not open and rng:next() < F.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x + 1, y)) end
			end
			if y < n - 1 then
				local open = grid[2 * y + 2][2 * x + 1] == false
				if not open and rng:next() < F.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x, y + 1)) end
			end
		end
	end

	-- entry on the perimeter, exit at maximum doorway distance
	local perim = {}
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 then
				table.insert(perim, id(x, y))
			end
		end
	end
	local entry = perim[rng:below(#perim)]
	local d = bfs(adj, n2, entry)
	local maxD, far = 0, {}
	for i = 1, n2 do
		if d[i] > maxD then
			maxD = d[i]
			far = { i }
		elseif d[i] == maxD then
			table.insert(far, i)
		end
	end
	local exit = far[rng:below(#far)]

	-- loot, from its own stream: WHICH rooms, and nothing else. An item's offset inside its room comes
	-- from that room's own decor stream below, never from here (REVIEW-1 A1: the offset replicates).
	local lr = Rng.new(seeds.loot)
	local cand = {}
	for i = 1, n2 do
		if i ~= entry and i ~= exit then table.insert(cand, i) end
	end
	local function take(list)
		local k = lr:below(#list)
		local r = list[k]
		table.remove(list, k)
		return r
	end
	local fuseRooms, cellRooms = {}, {}
	local start = 1
	if spec.onboarding then
		local nearList = {}
		for _, r in cand do
			if d[r] <= F.OnboardFuseMaxDistance then table.insert(nearList, r) end
		end
		if #nearList > 0 then
			local r = nearList[lr:below(#nearList)]
			for k, c in cand do
				if c == r then
					table.remove(cand, k)
					break
				end
			end
			table.insert(fuseRooms, r)
			start = 2
		end
	end
	for _ = start, spec.fuses do
		table.insert(fuseRooms, take(cand))
	end
	for _ = 1, spec.cells do
		if #cand > 0 then table.insert(cellRooms, take(cand)) end
	end
	local lim = F.CellSize / 2 - F.WallThickness - F.ItemWallClearance
	local items = {}
	local dressing = {} -- room -> that room's own stream: its item's offset first, then its props
	local function roomRng(r: number): any
		local g = dressing[r]
		if not g then
			g = Rng.new(Facility.roomSeed(seeds.decor, r))
			dressing[r] = g
		end
		return g
	end
	local function offset(r: number, kind: string)
		local ir = roomRng(r)
		return { kind = kind, x = -lim + 2 * lim * ir:next(), z = -lim + 2 * lim * ir:next() }
	end
	for _, r in fuseRooms do
		items[r] = offset(r, "fuse")
	end
	for _, r in cellRooms do
		items[r] = offset(r, "cell")
	end

	local plan = {
		n = n, n2 = n2, adj = adj, links = links, doors = #links,
		entry = entry, exit = exit, d = d, maxD = maxD,
		fuses = spec.fuses, cells = spec.cells, onboarding = spec.onboarding == true,
		items = items, fuseRooms = fuseRooms, cellRooms = cellRooms,
		props = {},
	}

	-- decor, from the third seed: one stream PER ROOM, so a room's props depend on its own doors and
	-- its own item only, never on how many draws the rooms before it used (REVIEW-1 A1)
	for room = 1, n2 do
		plan.props[room] = placeProps(cfg, plan, room, roomRng(room))
	end
	return plan
end

function Facility.planForSublevel(cfg: any, k: number, seeds: any, Rng: any, MazeGen: any): any
	local s = Facility.shape(cfg, k)
	return Facility.plan(cfg, { n = s.grid, fuses = s.fuses, cells = s.cells, onboarding = k == 1 }, seeds, Rng, MazeGen)
end

--============================================================================ the model explorer

-- A blind explorer with perfect memory: nearest unexplored doorway first, picks up whatever it
-- walks into, walks to the exit once it holds every fuse and has seen the exit. No threat. This is
-- design-measure/sim.luau's `explore` with the front and the battery removed and nothing else
-- changed — including the order its floating-point additions happen in, and the table it iterates
-- to break frontier ties — because M1 is reproduced against it.
-- Returns the completion time and the time the first fuse was picked up.
function Facility.modelTime(cfg: any, p: any): (number, number?)
	local F = cfg.Facility
	local stepT = F.CellSize / cfg.Movement.WalkSpeed
	local visited = { [p.entry] = true }
	local pos = p.entry
	local t = 0
	local held = 0
	local exitKnown = (p.entry == p.exit)
	local firstFuseT: number? = nil

	local function spend(dur: number)
		t += math.max(dur, 0)
	end

	local function enter(r)
		if not visited[r] then
			visited[r] = true
			local it = p.items[r]
			if r == p.exit then exitKnown = true end
			if it and it.kind == "fuse" then
				spend(F.PickupDetourSeconds)
				held += 1
				if not firstFuseT then firstFuseT = t end
			elseif it and it.kind == "cell" then
				spend(F.PickupDetourSeconds)
			end
		end
	end

	local function move(fresh: boolean)
		spend(stepT / 2)
		if fresh then spend(F.DoorOpenSeconds) end
		spend(stepT / 2)
	end

	local function knownBfs()
		local dist, par = { [pos] = 0 }, {}
		local q, h = { pos }, 1
		while h <= #q do
			local a = q[h]
			h += 1
			for _, b in p.adj[a] do
				if visited[b] and dist[b] == nil then
					dist[b] = dist[a] + 1
					par[b] = a
					table.insert(q, b)
				end
			end
		end
		return dist, par
	end

	local function walkTo(target, par)
		local path = {}
		local c = target
		while c ~= pos do
			table.insert(path, 1, c)
			c = par[c]
		end
		for _, r in path do
			local fresh = not visited[r]
			move(fresh)
			pos = r
			enter(r)
		end
	end

	local guard = 0
	while true do
		guard += 1
		if guard > 1000 then error("Facility.modelTime: explorer loop") end
		if held >= p.fuses and exitKnown then
			local _, par = knownBfs()
			walkTo(p.exit, par)
			break
		end
		local dist, par = knownBfs()
		local best: number?, bestD = nil, math.huge
		for a, da in dist do
			for _, b in p.adj[a] do
				if not visited[b] and da + 1 < bestD then
					best = b
					bestD = da + 1
					par[b] = a
				elseif not visited[b] and da + 1 == bestD and b < (best :: number) then
					best = b
					par[b] = a
				end
			end
		end
		if not best then error("Facility.modelTime: no frontier but objective incomplete") end
		walkTo(best, par)
	end
	return t, firstFuseT
end

--============================================================================ the blackout front

-- Seconds per ring. Derived from the floor, never typed in: the last ring before the exit's goes
-- dark at slack(k) x the model explorer's time. The guard rail keeps the dark from ever crossing
-- a room faster than a walking player does.
function Facility.front(cfg: any, plan: any, k: number, modelT: number): number
	local guard = cfg.Facility.CellSize / cfg.Movement.WalkSpeed
	return math.max(guard, Facility.slack(cfg, k) * modelT / (plan.maxD + cfg.Front.LeadSteps))
end

function Facility.deathTimeAtDistance(cfg: any, step: number, dist: number, hold: number): number
	return hold + (cfg.Front.LeadSteps + dist) * step
end

-- When `room` goes dark, on the run clock. math.huge while the front is HELD (hold == nil: a
-- first-ever run before its first fuse) and for a POWERED exit: the choice has no timer.
--
-- An UNPOWERED exit goes dark ExitExtraRings rings after the farthest ring (REVIEW-1 B3). It used to
-- stay lit for ever, and a run could stall in it for good: a player out of battery, with the fuses
-- they still needed beyond the grace, stood in its light while the rest of the floor died, and
-- nothing ever ended the run (600 s measured) short of the Roblox menu's Reset. A player who brings
-- every fuse powers the elevator the moment they walk in, which lights it again (the server applies
-- the insertion before it reads the light), so honest play never meets this.
function Facility.deathTime(cfg: any, plan: any, step: number, room: number, hold: number?, powered: boolean?): number
	if hold == nil then
		return math.huge
	end
	if room == plan.exit then
		if powered then
			return math.huge
		end
		return Facility.deathTimeAtDistance(cfg, step, plan.maxD + cfg.Front.ExitExtraRings, hold)
	end
	return Facility.deathTimeAtDistance(cfg, step, plan.d[room], hold)
end

function Facility.flickerTime(cfg: any, plan: any, step: number, room: number, hold: number?, powered: boolean?): number
	local t = Facility.deathTime(cfg, plan, step, room, hold, powered)
	if t == math.huge then return t end
	return t - cfg.Front.FlickerSeconds
end

--============================================================================ what the server builds

-- One wall of a room, split around its doorway when it has one. `axis` "x" = a wall on the +/-X
-- side (its length runs along Z).
local function wallParts(cfg: any, out: { any }, side: string, sign: number, hasDoor: boolean)
	local F = cfg.Facility
	local half, t, H = F.CellSize / 2, F.WallThickness, F.CeilingHeight
	local w, dh = F.DoorWidth, F.DoorHeight
	local offset = sign * (half - t / 2)
	-- X-side walls span the whole cell; Z-side walls fit between them, so no two walls overlap.
	local L = if side == "x" then F.CellSize else F.CellSize - 2 * t
	local function add(name, along, alongLen, y, height)
		if side == "x" then
			table.insert(out, { role = "wall", name = name, size = { t, height, alongLen }, pos = { offset, y, along } })
		else
			table.insert(out, { role = "wall", name = name, size = { alongLen, height, t }, pos = { along, y, offset } })
		end
	end
	local label = (if sign > 0 then "+" else "-") .. side
	if not hasDoor then
		add("Wall" .. label, 0, L, H / 2, H)
		return
	end
	local seg = (L - w) / 2
	local c = w / 2 + seg / 2
	add("Wall" .. label .. "A", -c, seg, H / 2, H)
	add("Wall" .. label .. "B", c, seg, H / 2, H)
	add("Lintel" .. label, 0, w, dh + (H - dh) / 2, H - dh)
end

-- Every Part of one room, local to its centre at floor-top height: floor, ceiling, walls (split
-- around doorways), the light fixture, the dust volume, its props and its item. Door leaves are
-- NOT here — they belong to the floor (Facility.doorLeaf). At most MaxPartsPerRoom by construction:
-- 1 + 1 + 12 + 1 + 1 + 3 + 1 = 20.
function Facility.roomParts(cfg: any, plan: any, room: number): { any }
	local F = cfg.Facility
	local H = F.CeilingHeight
	local out = {}
	table.insert(out, { role = "floor", name = "Floor", size = { F.CellSize, 1, F.CellSize }, pos = { 0, -0.5, 0 } })
	table.insert(out, { role = "ceiling", name = "Ceiling", size = { F.CellSize, 1, F.CellSize }, pos = { 0, H + 0.5, 0 } })
	local n = plan.n
	local cx, cy = coords(n, room)
	local open = {}
	for _, nb in plan.adj[room] do open[nb] = true end
	local function hasDoorTo(dx: number, dy: number): boolean
		local nx, ny = cx + dx, cy + dy
		if nx < 0 or ny < 0 or nx >= n or ny >= n then return false end
		return open[ny * n + nx + 1] == true
	end
	wallParts(cfg, out, "x", 1, hasDoorTo(1, 0))
	wallParts(cfg, out, "x", -1, hasDoorTo(-1, 0))
	wallParts(cfg, out, "z", 1, hasDoorTo(0, 1))
	wallParts(cfg, out, "z", -1, hasDoorTo(0, -1))
	table.insert(out, { role = "fixture", name = "Fixture", size = { 4, 0.4, 4 }, pos = { 0, H - 0.2, 0 } })
	table.insert(out, { role = "dust", name = "FxDustVolume", size = { F.CellSize - 4, H - 4, F.CellSize - 4 }, pos = { 0, H / 2, 0 } })
	for _, pr in plan.props[room] or {} do
		table.insert(out, { role = "prop", name = "Prop" .. pr.name, size = { pr.sx, pr.sy, pr.sz }, pos = { pr.x, pr.y, pr.z } })
	end
	local it = plan.items[room]
	if it then
		if it.kind == "fuse" then
			table.insert(out, { role = "item", name = "Fuse", size = { 0.8, 1.8, 0.8 }, pos = { it.x, 1.6, it.z } })
		else
			table.insert(out, { role = "item", name = "Cell", size = { 1, 1.4, 1 }, pos = { it.x, 1.4, it.z } })
		end
	end
	return out
end

-- §2.6: the silent figure in dark room `room`, seen from its neighbour `from` through their doorway.
-- Local to the GRID centre: stand at (x, 0, z) facing (dx, 0, dz); each limb is a size and an offset
-- in that stance (CFrame.lookAt(base, base + look) * CFrame.new(offset)).
local APPARITION_LIMBS = {
	{ name = "LegL", size = { 0.9, 3.4, 0.9 }, offset = { -0.55, 1.7, 0 } },
	{ name = "LegR", size = { 0.9, 3.4, 0.9 }, offset = { 0.55, 1.7, 0 } },
	{ name = "Torso", size = { 2.2, 3.2, 1 }, offset = { 0, 5, 0 } },
	{ name = "ArmL", size = { 0.6, 3.6, 0.6 }, offset = { -1.5, 4.6, 0 } },
	{ name = "ArmR", size = { 0.6, 3.6, 0.6 }, offset = { 1.5, 4.6, 0 } },
	{ name = "Head", size = { 1.3, 1.5, 1.3 }, offset = { 0, 7.4, 0 } },
}

function Facility.apparition(cfg: any, plan: any, room: number, from: number): any
	local F = cfg.Facility
	local dx, dz = Facility.neighbourDir(plan.n, room, from)
	local cx, cz = Facility.cellCenter(cfg, plan.n, room)
	-- DESIGN.md's spot: centred on the doorway's axis, WallOffset studs off the far wall. A prop on
	-- that wall reaches 9..13 studs off centre and used to swallow the figure (REVIEW-1 B4: 73 of 707
	-- apparitions). Where one crosses the figure's line, the figure stands in front of it instead,
	-- still on the axis. Only far-wall props can cross it: a side-wall prop starts 9 studs out from
	-- the axis, the figure is 1.8 studs wide either side of it, and a prop on the doorway's own wall
	-- is kept PropDoorClearance studs from the doorway, so it never reaches the axis either. An
	-- overhead prop is counted too: the pipe run is 1 stud deep, so standing in front of it is already
	-- behind the design spot, and min() leaves the figure where it was.
	local back = F.CellSize / 2 - F.WallThickness - cfg.Apparition.WallOffset
	local HALF_WIDTH, HALF_DEPTH, GAP = 1.8, 0.5, 0.25
	for _, pr in plan.props[room] or {} do
		local depth = -(pr.x * dx + pr.z * dz) -- how far toward the far wall the prop's centre is
		local depthHalf = if dx ~= 0 then pr.sx / 2 else pr.sz / 2
		local lat = if dx ~= 0 then pr.z else pr.x
		local latHalf = if dx ~= 0 then pr.sz / 2 else pr.sx / 2
		if math.abs(lat) < latHalf + HALF_WIDTH then
			back = math.min(back, depth - depthHalf - HALF_DEPTH - GAP)
		end
	end
	return { x = cx - dx * back, z = cz - dz * back, dx = dx, dz = dz, limbs = APPARITION_LIMBS }
end

-- The leaf closing the doorway between two rooms, local to the GRID centre.
function Facility.doorLeaf(cfg: any, n: number, a: number, b: number): any
	local F = cfg.Facility
	local lo, hi = math.min(a, b), math.max(a, b)
	local px, pz = Facility.doorPoint(cfg, n, lo, hi)
	local dx = Facility.neighbourDir(n, lo, hi)
	local size = if dx ~= 0 then { 0.4, F.DoorHeight, F.DoorWidth } else { F.DoorWidth, F.DoorHeight, 0.4 }
	return { name = "Door_" .. lo .. "_" .. hi, size = size, pos = { px, F.DoorHeight / 2, pz }, lo = lo, hi = hi }
end

return Facility
