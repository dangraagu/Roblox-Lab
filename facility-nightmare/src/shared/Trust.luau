--!strict
-- Trust.luau — where the server BELIEVES the player is, and which room that is. PURE.
--
-- In Roblox the client owns its own character's physics: `HumanoidRootPart.Position` read on the
-- server is a CLAIM. Every rule in this game — doors, pickups, fuse insertion, lit or dark, the
-- choice — reads the trusted position and trusted cell from here instead.
--
-- Three rules, following vault-runners' Trace.luau and adding the room graph it does not have:
--   1. The trusted position moves toward the claim no faster than TrustedSpeedFactor x the speed
--      the SERVER set (16, or 24 while the server says sprinting), banking up to
--      TrustedBurstSeconds of unused allowance so replication jitter is paid for out of savings.
--   2. The trusted cell changes only to an ADJACENT cell, and only through a doorway the server
--      has OPENED, crossing within the doorway's width. A claim in a room that no open doorway
--      leads to (behind a wall or a closed door, or off the grid) leaves the trusted position
--      clamped at the edge of the room it is in.
--   3. A claim in a room that open doorways DO lead to is walked there THROUGH them: square up
--      inside each doorway's band, cross, go on, all within rule 1's allowance.
--      Rule 3 is from 2026-09-17. Before it the walk was one straight line, clamped where it met a
--      wall. An honest player whose claims froze for 0.8 s as they stepped through a doorway and
--      turned along the wall then had a claim "through the wall" beside that doorway, and stayed
--      pinned in the room behind them for as long as they kept away from the doorway's line
--      (tests/Trust.spec.luau, "a claim freeze" and "HONEST WALKERS WITH LAG": 236 of 1000+ stops
--      wrong under the lag model there). Routing gives a cheat nothing: the route is legal, no
--      faster than rule 1, and never crosses a wall or a closed door ("ADVERSARIAL CLAIMS").
-- Every leg is checked in TrustSubstepStuds pieces, so a banked burst that crosses two rooms in a
-- tick still passes each doorway in turn.
--
-- What this does NOT do: punish, kick or flag. A lagging honest player and a slow cheat get the
-- same answer — nothing happens faster than a walker could make it happen. It also ignores height:
-- the facility is one storey, and falling out of the world is Humanoid.Died, a death settlement.
--
-- Grid-local studs in, grid-local studs out; the server subtracts the zone origin. Requires nothing.

local Trust = {}

-- How far inside a doorway's edge a route aims, and how far either side of the room edge it squares
-- up, so a routed crossing is perpendicular to the doorway and well inside its band.
local ROUTE_EDGE_MARGIN = 0.5
local ROUTE_TURN = 0.5

local function center(cfg: any, n: number, id: number): (number, number)
	local cx = (id - 1) % n
	local cy = (id - 1 - cx) / n
	local s = cfg.Facility.CellSize
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
	local size = cfg.Facility.CellSize
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
local function walkLeg(cfg: any, n: number, x: number, z: number, cell: number, tx: number, tz: number,
	len: number, isOpen: (number, number) -> boolean): (number, number, number)
	local dx, dz = tx - x, tz - z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-9 or len < 1e-12 then
		return x, z, cell
	end
	local half = cfg.Facility.CellSize / 2
	local door = cfg.Facility.DoorWidth / 2
	local ux, uz = dx / dist, dz / dist
	local pieces = math.max(1, math.ceil(len / cfg.Run.TrustSubstepStuds))
	local piece = len / pieces
	for _ = 1, pieces do
		local nx, nz = x + ux * piece, z + uz * piece

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

		x, z = nx, nz
	end
	return x, z, cell
end

-- One server tick. `speed` is the WalkSpeed the server itself set this tick. `isOpen(a, b)` is
-- the server's open-door set. Returns the trusted x, z and cell.
function Trust.step(cfg: any, t: any, claimX: number, claimZ: number, dt: number, speed: number,
	isOpen: (number, number) -> boolean): (number, number, number)
	if not finite(dt) or dt <= 0 or not finite(claimX) or not finite(claimZ) or not finite(speed) then
		return t.x, t.z, t.cell
	end
	local rate = speed * cfg.Run.TrustedSpeedFactor
	t.budget = math.min(speed * cfg.Run.TrustedSpeedFactor * cfg.Run.TrustedBurstSeconds, t.budget + rate * dt)

	local n = t.n
	local size = cfg.Facility.CellSize
	local half = size / 2
	local band = cfg.Facility.DoorWidth / 2 - ROUTE_EDGE_MARGIN

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
				px, pz = at(half + ROUTE_TURN)
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
		x, z, cell = walkLeg(cfg, n, x, z, cell, w[1], w[2], go, isOpen)
		left -= go
	end
	t.x, t.z, t.cell = x, z, cell
	return x, z, cell
end

return Trust
