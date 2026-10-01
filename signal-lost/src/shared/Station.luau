--!strict
-- Station.luau — the sector generator and the module geometry the server builds from it (DESIGN.md §12,
-- §2.1, §8.1). PURE: it requires nothing; `MazeGen` and the config come in as arguments.
--
-- plan(cfg, k, streams, MazeGen) -> the whole sector, drawn from FOUR independent streams, in this order:
--   1. layout: MazeGen.generate (a perfect maze, verbatim md5 c269d302...), then every closed wall between
--      neighbours opens with ExtraDoorChance (row-major, one NextNumber each), then the dock on the perimeter;
--   2. air: each module but the dock is vacuum with probability breach(k); on sector 1 every dock neighbour
--      is vacuum; then the reach rule flips the vacuum module farthest from air (lowest id first) until every
--      vacuum module is within reach(k) hatches of air. It reads walls and air only, NEVER the relay;
--   3. relay: uniform among the air modules other than the dock at doorway distance >= ceil(0.75 maxD),
--      lowering the threshold until the set is non-empty. The relay stream draws EXACTLY ONCE and drives
--      nothing visible;
--   4. loot: on sector 1 the first salvage in a dock neighbour; then salvage and canisters in distinct vacuum
--      modules, air modules (never the dock) only when vacuum runs out; then positions and heights, last.
--
-- In production every stream is `Random.new()` with no seed (engine entropy), one object per stream per
-- attempt, so there is no seed to enumerate against the walls (fork-tower REVIEW-4, trap 1) and no stream is
-- pinned by another's observations (trap 2). A stream is anything with :NextInteger(lo, hi) and :NextNumber().
--
-- Deviation from the design rig, on purpose (tests/Station.spec.luau): the rig's air fallback skipped the
-- relay module, which made the items depend on the relay stream. Here an item may land in any air module but
-- the dock, so changing the relay stream changes the relay and nothing else.

local Station = {}

--============================================================================ the grid

function Station.cellXY(n: number, id: number): (number, number)
	return (id - 1) % n, (id - 1) // n
end

-- Grid-local centre of a module (the zone origin is the grid's centre).
function Station.cellCenter(cfg: any, n: number, id: number): (number, number)
	local cx, cy = (id - 1) % n, (id - 1) // n
	local s = cfg.Station.CellSize
	return (cx - (n - 1) / 2) * s, (cy - (n - 1) / 2) * s
end

-- The module a grid-local point lies in, or nil off the grid.
function Station.moduleAt(cfg: any, n: number, x: number, z: number): number?
	if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then return nil end
	local size = cfg.Station.CellSize
	local cx = math.floor(x / size + n / 2)
	local cy = math.floor(z / size + n / 2)
	if cx < 0 or cy < 0 or cx >= n or cy >= n then
		return nil
	end
	return cy * n + cx + 1
end

local function bfs(adj: { { number } }, n2: number, srcs: { number }): { number }
	local d = {}
	for i = 1, n2 do d[i] = -1 end
	local q = {}
	for _, s in srcs do
		d[s] = 0
		table.insert(q, s)
	end
	local h = 1
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
Station.bfs = bfs

--============================================================================ the plan

-- Relay candidates of a plan: air modules other than the dock at doorway distance >= the threshold, the
-- threshold lowered from ceil(RelayDepthFrac x maxD) until the set is non-empty. Reads walls and air only.
-- Returns the list (ascending ids) and the threshold used.
function Station.relayCandidates(cfg: any, p: any): ({ number }, number)
	local thr = math.ceil(cfg.Station.RelayDepthFrac * p.maxD)
	local cand = {}
	while thr >= 1 do
		cand = {}
		for i = 1, p.n2 do
			if i ~= p.dock and not p.vac[i] and p.d[i] >= thr then
				table.insert(cand, i)
			end
		end
		if #cand > 0 then break end
		thr -= 1
	end
	return cand, thr
end

function Station.plan(cfg: any, k: number, streams: any, MazeGen: any): any
	local S = cfg.Station
	local sched = cfg.scheduleFor(k)
	local n = sched.n
	local n2 = n * n
	local lay = streams.layout

	-- 1. walls (layout)
	local grid = MazeGen.generate(n, n, lay)
	local function id(x: number, y: number): number
		return y * n + x + 1
	end
	local adj: { { number } } = {}
	for i = 1, n2 do adj[i] = {} end
	local hatches = 0
	local function link(a: number, b: number)
		table.insert(adj[a], b)
		table.insert(adj[b], a)
		hatches += 1
	end
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x < n - 1 then
				local open = grid[2 * y + 1][2 * x + 2] == false
				if not open and lay:NextNumber() < S.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x + 1, y)) end
			end
			if y < n - 1 then
				local open = grid[2 * y + 2][2 * x + 1] == false
				if not open and lay:NextNumber() < S.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x, y + 1)) end
			end
		end
	end
	local perim = {}
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 then
				table.insert(perim, id(x, y))
			end
		end
	end
	local dock = perim[lay:NextInteger(1, #perim)]
	local d = bfs(adj, n2, { dock })
	local maxD = 0
	for i = 1, n2 do
		if d[i] > maxD then maxD = d[i] end
	end

	-- 2. the air map (air); relay-independent
	local ar = streams.air
	local vac: { boolean } = {}
	for i = 1, n2 do
		local roll = ar:NextNumber()
		vac[i] = i ~= dock and roll < sched.breach
	end
	if sched.onboard then
		for _, b in adj[dock] do vac[b] = true end
	end
	local flips = 0
	while true do
		local airs = {}
		for i = 1, n2 do
			if not vac[i] then table.insert(airs, i) end
		end
		local da = bfs(adj, n2, airs)
		local worst, worstD = nil, sched.reach
		for i = 1, n2 do
			if vac[i] and da[i] > worstD then
				worst = i
				worstD = da[i]
			end
		end
		if worst == nil then break end
		vac[worst] = false
		flips += 1
	end

	local p: any = {
		k = k, n = n, n2 = n2, adj = adj, dock = dock, d = d, maxD = maxD, vac = vac,
		hatches = hatches, flips = flips, sched = sched,
	}

	-- 3. the relay (relay): exactly one draw
	local cand, thr = Station.relayCandidates(cfg, p)
	local forced = false
	if #cand == 0 then
		-- no air module besides the dock: the farthest one (lowest id) becomes air. Walls only.
		local far, fd = dock, -1
		for i = 1, n2 do
			if d[i] > fd then
				far = i
				fd = d[i]
			end
		end
		vac[far] = false
		cand = { far }
		forced = true
	end
	p.relay = cand[streams.relay:NextInteger(1, #cand)]
	p.nCand = #cand
	p.relayThr = thr
	p.forced = forced

	-- 4. loot (loot)
	local lr = streams.loot
	local pool, pool2 = {}, {}
	for i = 1, n2 do
		if i ~= dock then
			if vac[i] then table.insert(pool, i) else table.insert(pool2, i) end
		end
	end
	local kinds: { [number]: string } = {}
	local function drop(list: { number }, r: number)
		for j, c in list do
			if c == r then
				table.remove(list, j)
				return
			end
		end
	end
	local function take(): number?
		local list = if #pool > 0 then pool else pool2
		if #list == 0 then return nil end
		local j = lr:NextInteger(1, #list)
		local r = list[j]
		table.remove(list, j)
		return r
	end
	local salvageLeft = sched.salvage
	if sched.onboard then
		local near = table.clone(adj[dock])
		table.sort(near)
		if #near > 0 then
			local r = near[lr:NextInteger(1, #near)]
			kinds[r] = "salvage"
			salvageLeft -= 1
			drop(pool, r)
			drop(pool2, r)
		end
	end
	for _ = 1, salvageLeft do
		local r = take()
		if r then kinds[r] = "salvage" end
	end
	for _ = 1, sched.canisters do
		local r = take()
		if r then kinds[r] = "canister" end
	end
	-- positions and heights, last, in module order. Every item stands ItemWallClearance off every wall and
	-- out of the module's centre square (where a relay mast would be): relay-independent by construction.
	local lim = S.CellSize / 2 - S.WallThickness - S.ItemWallClearance
	local items: { [number]: any } = {}
	for m = 1, n2 do
		local kind = kinds[m]
		if kind then
			local x = -lim + 2 * lim * lr:NextNumber()
			local z = -lim + 2 * lim * lr:NextNumber()
			local u = lr:NextNumber()
			if math.abs(x) < 3 and math.abs(z) < 3 then
				x = if x >= 0 then 3 else -3
			end
			local y = if kind == "salvage" then S.SalvageHeightMin + (S.SalvageHeightMax - S.SalvageHeightMin) * u else S.CanisterHeight
			items[m] = { kind = kind, x = x, z = z, y = y }
		end
	end
	p.items = items
	local nVac = 0
	for i = 1, n2 do
		if vac[i] then nVac += 1 end
	end
	p.nVac = nVac
	return p
end

-- One Random.new() per stream, per attempt. `newRandom` is Random.new (passed in: this module reads no global).
function Station.freshStreams(newRandom: () -> any): any
	return { layout = newRandom(), air = newRandom(), loot = newRandom(), relay = newRandom() }
end

--============================================================================ hatches

function Station.hatchCenter(cfg: any, n: number, a: number, b: number): (number, number)
	local ax, az = Station.cellCenter(cfg, n, a)
	local bx, bz = Station.cellCenter(cfg, n, b)
	return (ax + bx) / 2, (az + bz) / 2
end

function Station.hatchName(a: number, b: number): string
	return "Hatch_" .. math.min(a, b) .. "_" .. math.max(a, b)
end

-- The leaf that fills a doorway, on the shared boundary. `axis` is the axis the boundary is normal to.
function Station.leafSpec(cfg: any, n: number, a: number, b: number): any
	local S = cfg.Station
	local x, z = Station.hatchCenter(cfg, n, a, b)
	local alongX = math.abs(a - b) == 1
	return {
		name = Station.hatchName(a, b),
		axis = if alongX then "x" else "z",
		pos = { x, S.HatchHeight / 2, z },
		size = if alongX then { S.LeafThickness, S.HatchHeight, S.HatchWidth } else { S.HatchWidth, S.HatchHeight, S.LeafThickness },
	}
end

-- Neighbours of `cell` whose closed hatch the trusted point (x, z) is within HatchOpenRadius of.
function Station.hatchesNear(cfg: any, p: any, cell: number, x: number, z: number, isOpen: (number, number) -> boolean): { number }
	local out = {}
	local r2 = cfg.Station.HatchOpenRadius * cfg.Station.HatchOpenRadius
	for _, nb in p.adj[cell] do
		if not isOpen(cell, nb) then
			local hx, hz = Station.hatchCenter(cfg, p.n, cell, nb)
			local dx, dz = x - hx, z - hz
			if dx * dx + dz * dz <= r2 then
				table.insert(out, nb)
			end
		end
	end
	return out
end

--============================================================================ module geometry

-- Which side of `id` its neighbour `nb` is on: "E" (+x), "W" (-x), "N" (+z), "S" (-z).
function Station.sideOf(n: number, id: number, nb: number): string
	if nb == id + 1 then return "E" end
	if nb == id - 1 then return "W" end
	if nb == id + n then return "N" end
	return "S"
end

-- The server's Parts for one module, module-local (origin: the floor's top face at the module centre).
-- { name, role, size = {x, y, z}, pos = {x, y, z}, side?, nb? }. Roles: floor, ceiling, glass, wall, fixture.
-- opts.mainArray: relay 30's control room, whose whole ceiling is glass under the dish (§7.1).
-- Walls sit INSIDE the cell (neighbours meet back to back); N/S walls span the full 32, E/W the 30 between
-- them, so no two walls overlap at a corner.
function Station.moduleParts(cfg: any, p: any, id: number, opts: any?): { any }
	local S = cfg.Station
	local o = opts or {}
	local half = S.CellSize / 2
	local inner = half - S.WallThickness
	local H = S.CeilingHeight
	local out = {}
	local function add(name: string, role: string, size: { number }, pos: { number }, side: string?, nb: number?)
		table.insert(out, { name = name, role = role, size = size, pos = pos, side = side, nb = nb })
	end
	add("Floor", "floor", { S.CellSize, 1, S.CellSize }, { 0, -0.5, 0 })
	if o.mainArray then
		add("Glass", "glass", { S.CellSize, 1, S.CellSize }, { 0, H + 0.5, 0 })
	elseif p.vac[id] then
		-- a four-part frame and a cracked glass pane in the middle: space overhead
		local q = S.CellSize / 4
		add("CeilingN", "ceiling", { S.CellSize, 1, q }, { 0, H + 0.5, half - q / 2 })
		add("CeilingS", "ceiling", { S.CellSize, 1, q }, { 0, H + 0.5, -half + q / 2 })
		add("CeilingE", "ceiling", { q, 1, S.CellSize - 2 * q }, { half - q / 2, H + 0.5, 0 })
		add("CeilingW", "ceiling", { q, 1, S.CellSize - 2 * q }, { -half + q / 2, H + 0.5, 0 })
		add("Glass", "glass", { S.CellSize - 2 * q, 0.4, S.CellSize - 2 * q }, { 0, H + 0.3, 0 })
	else
		add("Ceiling", "ceiling", { S.CellSize, 1, S.CellSize }, { 0, H + 0.5, 0 })
	end
	local x, y = (id - 1) % p.n, (id - 1) // p.n
	local nbOf = {
		E = if x < p.n - 1 then id + 1 else nil,
		W = if x > 0 then id - 1 else nil,
		N = if y < p.n - 1 then id + p.n else nil,
		S = if y > 0 then id - p.n else nil,
	}
	local hw = S.HatchWidth / 2
	for _, side in { "E", "W", "N", "S" } do
		local nb = nbOf[side]
		local open = nb ~= nil and table.find(p.adj[id], nb) ~= nil
		local alongX = side == "N" or side == "S" -- the wall runs along x
		local sgn = if side == "E" or side == "N" then 1 else -1
		local c = sgn * (inner + S.WallThickness / 2) -- the wall's centre on its normal axis
		local span = if alongX then half else inner -- half-length of the wall along it
		local function place(a0: number, a1: number, y0: number, y1: number, name: string)
			local len, mid = a1 - a0, (a0 + a1) / 2
			local size = if alongX then { len, y1 - y0, S.WallThickness } else { S.WallThickness, y1 - y0, len }
			local pos = if alongX then { mid, (y0 + y1) / 2, c } else { c, (y0 + y1) / 2, mid }
			add(name, "wall", size, pos, side, if open then nb else nil)
		end
		if open then
			place(-span, -hw, 0, H, "Wall" .. side .. "_A")
			place(hw, span, 0, H, "Wall" .. side .. "_B")
			place(-hw, hw, S.HatchHeight, H, "Wall" .. side .. "_Top")
		else
			place(-span, span, 0, H, "Wall" .. side)
		end
	end
	-- the light panel hangs under the ceiling's north strip, clear of the glass and of every doorway
	add("Fixture", "fixture", { 8, 0.4, 1.6 }, { 0, H - 0.2, half - S.CellSize / 8 })
	return out
end

-- Where the special pieces stand, module-local.
function Station.relayLayout(cfg: any): any
	local o = cfg.Station.FloorHatchOffset
	return {
		mast = { 0, 0 }, -- the relay mast, in the centre
		floorHatch = { o, o }, -- the (+x, +z) corner, off every doorway line
		console = { -o, -o }, -- the fabricator + RETURN console, the opposite corner
	}
end

-- The dock's RETURN console stands against an outer wall (the dock is on the perimeter, so one exists).
function Station.dockConsole(cfg: any, n: number, dock: number): (number, number, string)
	local x, y = (dock - 1) % n, (dock - 1) // n
	local o = cfg.Station.FloorHatchOffset
	if x == 0 then return -o, 0, "W" end
	if x == n - 1 then return o, 0, "E" end
	if y == 0 then return 0, -o, "S" end
	return 0, o, "N"
end

-- Parts a module holds beyond moduleParts: an item, the dock's console and arrival hatch, the relay's mast,
-- and after the splice its console and floor hatch. The server's builders and this count must agree
-- (check_signallost counts the built folders against the cap).
function Station.extrasCount(_cfg: any, p: any, id: number, spliced: boolean): number
	local n = 0
	if p.items[id] then n += 1 end
	if id == p.dock then n += 2 end
	if id == p.relay then
		n += 1
		if spliced then n += 2 end
	end
	return n
end

return Station
