--!strict
-- Trust.luau — where the server BELIEVES the player is, and which module that is. PURE.
--
-- Copied from facility-nightmare/src/shared/Trust.luau (md5 d750d34a...) with its spec. Adapted only in what
-- it reads (DESIGN.md §14): the config paths (Config.Station / Config.Server), and the speed the caller passes
-- is the speed the SERVER set for the module type the player is trusted to be in (16 in air, 12 + Mag-Boots in
-- vacuum), so the cap follows the module. New: clampHeight, the one place height matters (the salvage window).
-- New (REVIEW-1 finding 1): an optional isVac(cell) argument to step(); each step then reports in t.vacStuds how far
-- the trusted position walked through vacuum modules, so the server charges AIR for vacuum DISTANCE as well as time
-- (Air.vacuumCharge). Without isVac it reports 0 and step() behaves exactly as the original.
--
-- In Roblox the client owns its own character's physics: `HumanoidRootPart.Position` read on the server is a
-- CLAIM. Every rule in this game — hatches, pickups, the splice, the floor hatch, air or vacuum, consoles —
-- reads the trusted position and trusted module from here instead.
--
-- Three rules, from vault-runners' Trace.luau plus the room graph:
--   1. The trusted position moves toward the claim no faster than TrustedSpeedFactor x the speed the server
--      set, banking up to TrustedBurstSeconds of unused allowance so replication jitter is paid out of savings.
--   2. The trusted module changes only to an ADJACENT module, and only through a hatch the server has OPENED,
--      crossing within the hatch's width. A claim that no open hatch leads to is clamped at the module's edge.
--   3. A claim in a module that open hatches DO lead to is walked there THROUGH them: square up inside each
--      doorway's band, cross, go on, all within rule 1's allowance (facility-nightmare trap 15: an honest
--      player whose claims froze while stepping through a doorway was otherwise pinned in the module behind).
-- Every leg is checked in TrustSubstepStuds pieces, so a banked burst that crosses two modules in a tick
-- still passes each hatch in turn. It never punishes, kicks or flags. Grid-local studs in and out; the
-- server subtracts the zone origin. Requires nothing.

local Trust = {}

-- How far inside a doorway's edge a route aims, and how far either side of the room edge it squares
-- up, so a routed crossing is perpendicular to the doorway and well inside its band.
local ROUTE_EDGE_MARGIN = 0.5
local ROUTE_TURN = 0.5
-- The least a route aims past the last doorway's edge (REVIEW-1 finding 1), so its crossing is never lost to rounding.
local ROUTE_LAND = 0.05

local function center(cfg: any, n: number, id: number): (number, number)
	local cx = (id - 1) % n
	local cy = (id - 1 - cx) / n
	local s = cfg.Station.CellSize
	return (cx - (n - 1) / 2) * s, (cy - (n - 1) / 2) * s
end

function Trust.new(cfg: any, n: number, cell: number, x: number, z: number): any
	return { n = n, cell = cell, x = x, z = z, budget = 0, throttled = 0 }
end

-- Where the SERVER put the player (a car, a respawn): a new cell and position, and no banked burst.
function Trust.reset(t: any, cell: number, x: number, z: number)
	t.cell = cell
	t.x = x
	t.z = z
	t.budget = 0
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The grid cell a grid-local point lies in, or nil off the grid.
local function cellAt(cfg: any, n: number, x: number, z: number): number?
	local size = cfg.Station.CellSize
	local cx = math.floor(x / size + n / 2)
	local cy = math.floor(z / size + n / 2)
	if cx < 0 or cy < 0 or cx >= n or cy >= n then
		return nil
	end
	return cy * n + cx + 1
end

-- The cells after `from` on a shortest route to `to` through OPEN doorways, or nil if none.
local function route(n: number, from: number, to: number, isOpen: (number, number) -> boolean): { number }?
	local prev: { [number]: number } = { [from] = from }
	local q, h = { from }, 1
	while h <= #q do
		local a = q[h]
		h += 1
		local ax = (a - 1) % n
		local nbs = {}
		if ax < n - 1 then table.insert(nbs, a + 1) end
		if ax > 0 then table.insert(nbs, a - 1) end
		if a + n <= n * n then table.insert(nbs, a + n) end
		if a - n >= 1 then table.insert(nbs, a - n) end
		for _, b in nbs do
			if prev[b] == nil and isOpen(a, b) then
				prev[b] = a
				if b == to then
					local path = { b }
					local c = a
					while c ~= from do
						table.insert(path, 1, c)
						c = prev[c]
					end
					return path
				end
				table.insert(q, b)
			end
		end
	end
	return nil
end

-- Walk `len` studs (already paid for) of one straight leg from (x, z) in `cell` toward (tx, tz), in
-- substeps: a room edge is crossed only inside an open doorway's band, and clamped otherwise.
-- The fourth result is the distance walked through vacuum modules (isVac), a substep that changes module counting half.
local function walkLeg(cfg: any, n: number, x: number, z: number, cell: number, tx: number, tz: number,
	len: number, isOpen: (number, number) -> boolean, isVac: ((number) -> boolean)?): (number, number, number, number)
	local dx, dz = tx - x, tz - z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-9 or len < 1e-12 then
		return x, z, cell, 0
	end
	local vacStuds = 0
	local half = cfg.Station.CellSize / 2
	local door = cfg.Station.HatchWidth / 2
	local ux, uz = dx / dist, dz / dist
	local pieces = math.max(1, math.ceil(len / cfg.Server.TrustSubstepStuds))
	local piece = len / pieces
	for _ = 1, pieces do
		local nx, nz = x + ux * piece, z + uz * piece
		local fromCell = cell

		-- across an X edge?
		local cx = (cell - 1) % n
		local ccx, ccz = center(cfg, n, cell)
		if nx > ccx + half then
			if cx < n - 1 and math.abs(nz - ccz) <= door and isOpen(cell, cell + 1) then
				cell += 1
			else
				nx = ccx + half
			end
		elseif nx < ccx - half then
			if cx > 0 and math.abs(nz - ccz) <= door and isOpen(cell, cell - 1) then
				cell -= 1
			else
				nx = ccx - half
			end
		end

		-- across a Z edge? (checked against the cell we are in now)
		local cy = ((cell - 1) - ((cell - 1) % n)) / n
		ccx, ccz = center(cfg, n, cell)
		if nz > ccz + half then
			if cy < n - 1 and math.abs(nx - ccx) <= door and isOpen(cell, cell + n) then
				cell += n
			else
				nz = ccz + half
			end
		elseif nz < ccz - half then
			if cy > 0 and math.abs(nx - ccx) <= door and isOpen(cell, cell - n) then
				cell -= n
			else
				nz = ccz - half
			end
		end

		if isVac then
			local moved = math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
			local share = (if isVac(fromCell) then 0.5 else 0) + (if isVac(cell) then 0.5 else 0)
			vacStuds += moved * share
		end
		x, z = nx, nz
	end
	return x, z, cell, vacStuds
end

-- One server tick. `speed` is the WalkSpeed the server itself set this tick. `isOpen(a, b)` is
-- the server's open-door set; `isVac(cell)`, optional, which modules are vacuum. Returns the trusted x, z and
-- cell, and leaves in t.vacStuds the distance this tick walked through vacuum (0 without isVac).
function Trust.step(cfg: any, t: any, claimX: number, claimZ: number, dt: number, speed: number,
	isOpen: (number, number) -> boolean, isVac: ((number) -> boolean)?): (number, number, number)
	t.vacStuds = 0
	if not finite(dt) or dt <= 0 or not finite(claimX) or not finite(claimZ) or not finite(speed) then
		return t.x, t.z, t.cell
	end
	local rate = speed * cfg.Server.TrustedSpeedFactor
	t.budget = math.min(speed * cfg.Server.TrustedSpeedFactor * cfg.Server.TrustedBurstSeconds, t.budget + rate * dt)

	local n = t.n
	local size = cfg.Station.CellSize
	local half = size / 2
	local band = cfg.Station.HatchWidth / 2 - ROUTE_EDGE_MARGIN

	-- Waypoints: through each open doorway on the way to the claim's room (rule 3), then the claim.
	-- In a straight line, a claim in the same room stays inside that convex room, and a claim with
	-- no open route is clamped where the line meets a wall (rule 2).
	local legs: { { number } } = {}
	local claimCell = cellAt(cfg, n, claimX, claimZ)
	if claimCell ~= nil and claimCell ~= t.cell then
		local path = route(n, t.cell, claimCell, isOpen)
		if path then
			local px, pz, a = t.x, t.z, t.cell
			for _, b in path do
				local acx, acz = center(cfg, n, a)
				local bcx, bcz = center(cfg, n, b)
				local alongX = bcx ~= acx
				local sign = if alongX then (bcx - acx) / size else (bcz - acz) / size
				local current = if alongX then pz - acz else px - acx
				local lat = math.clamp(current, -band, band)
				local function at(depth: number): (number, number)
					if alongX then
						return acx + sign * depth, acz + lat
					end
					return acx + lat, acz + sign * depth
				end
				if math.abs(current) > band then
					-- outside the doorway's band: square up first, still inside room a
					local bx, bz = at(half - ROUTE_TURN)
					table.insert(legs, { bx, bz })
				end
				-- the last doorway: never aim past the claim's own depth into its module, or a claim just over the
				-- edge is walked 0.5 past it and back, and that detour would be charged as vacuum distance
				-- (REVIEW-1 finding 1: an honest walker pays what it walks, not the route's overshoot)
				local depth = half + ROUTE_TURN
				if b == claimCell then
					local claimDepth = sign * (if alongX then claimX - acx else claimZ - acz)
					depth = math.clamp(claimDepth, half + ROUTE_LAND, half + ROUTE_TURN)
				end
				px, pz = at(depth)
				table.insert(legs, { px, pz })
				a = b
			end
		end
	end
	table.insert(legs, { claimX, claimZ })

	local total = 0
	local lx, lz = t.x, t.z
	for _, w in legs do
		total += math.sqrt((w[1] - lx) ^ 2 + (w[2] - lz) ^ 2)
		lx, lz = w[1], w[2]
	end
	if total < 1e-9 then
		return t.x, t.z, t.cell
	end
	local allowed = math.min(total, t.budget)
	t.budget -= allowed
	if allowed + 1e-9 < total then
		t.throttled += 1
	end

	local x, z, cell = t.x, t.z, t.cell
	local left = allowed
	for _, w in legs do
		if left <= 1e-12 then
			break
		end
		local go = math.min(math.sqrt((w[1] - x) ^ 2 + (w[2] - z) ^ 2), left)
		local vacStuds
		x, z, cell, vacStuds = walkLeg(cfg, n, x, z, cell, w[1], w[2], go, isOpen, isVac)
		t.vacStuds += vacStuds
		left -= go
	end
	t.x, t.z, t.cell = x, z, cell
	return x, z, cell
end

-- A claimed root height, module-local (the floor's top is 0): never above one jump's apex from standing
-- (+0.5 of slack), never below the floor. Only the salvage window reads height (§8.1, §14).
function Trust.clampHeight(cfg: any, claimY: number, vacuum: boolean): number
	local stand = cfg.Station.StandHeight
	if type(claimY) ~= "number" or claimY ~= claimY then
		return stand
	end
	local M = cfg.Move
	local apex = if vacuum then M.VacJumpHeight / M.VacGravityFactor else M.AirJumpHeight
	return math.clamp(claimY, 0, stand + apex + 0.5)
end

return Trust
