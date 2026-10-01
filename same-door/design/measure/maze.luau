--!strict
-- THROWAWAY measurement kit for the The Same Door design spec. Not game code.
-- Grid maze (recursive backtracker + extra loop openings), placement of 3 seals + door + hazards,
-- par route (best of 6 seal orders, cell steps), funnel (string-pulled) length along that route.

local M = {}

-- MINSTD read through high bits (checklist: never state % span).
function M.rng(seed: number): any
	local r = { state = (math.floor(math.abs(seed)) % 2147483646) + 1 }
	function r.NextNumber(self: any): number
		self.state = (self.state * 48271) % 2147483647
		return (self.state - 1) / 2147483646
	end
	function r.NextInteger(self: any, a: number, b: number): number
		local n = a + math.floor(self:NextNumber() * (b - a + 1))
		if n > b then n = b end
		return n
	end
	return r
end

-- cells are 0-based index i = y*W + x. openE[i]: passage to (x+1,y). openN[i]: passage to (x,y+1).
function M.generate(W: number, H: number, loops: number, rng: any, entrance: { number }): any
	local openE, openN = {}, {}
	for i = 0, W * H - 1 do openE[i] = false; openN[i] = false end
	local visited = {}
	local sx, sy = entrance[1], entrance[2]
	local stack = { { sx, sy } }
	visited[sy * W + sx] = true
	while #stack > 0 do
		local cur = stack[#stack]
		local cx, cy = cur[1], cur[2]
		local nb = {}
		if cx + 1 < W and not visited[cy * W + cx + 1] then table.insert(nb, { cx + 1, cy }) end
		if cx - 1 >= 0 and not visited[cy * W + cx - 1] then table.insert(nb, { cx - 1, cy }) end
		if cy + 1 < H and not visited[(cy + 1) * W + cx] then table.insert(nb, { cx, cy + 1 }) end
		if cy - 1 >= 0 and not visited[(cy - 1) * W + cx] then table.insert(nb, { cx, cy - 1 }) end
		if #nb > 0 then
			local p = nb[rng:NextInteger(1, #nb)]
			local nx, ny = p[1], p[2]
			if nx > cx then openE[cy * W + cx] = true
			elseif nx < cx then openE[cy * W + nx] = true
			elseif ny > cy then openN[cy * W + cx] = true
			else openN[ny * W + cx] = true end
			visited[ny * W + nx] = true
			table.insert(stack, { nx, ny })
		else
			table.remove(stack)
		end
	end
	-- extra loop openings: random closed internal walls
	local closed = {}
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local i = y * W + x
			if x + 1 < W and not openE[i] then table.insert(closed, { "E", i }) end
			if y + 1 < H and not openN[i] then table.insert(closed, { "N", i }) end
		end
	end
	for _ = 1, loops do
		if #closed == 0 then break end
		local k = rng:NextInteger(1, #closed)
		local w = table.remove(closed, k)
		if w[1] == "E" then openE[w[2]] = true else openN[w[2]] = true end
	end
	return { W = W, H = H, openE = openE, openN = openN }
end

function M.neighbours(m: any, i: number): { number }
	local W, H = m.W, m.H
	local x, y = i % W, i // W
	local out = {}
	if x + 1 < W and m.openE[i] then table.insert(out, i + 1) end
	if x - 1 >= 0 and m.openE[i - 1] then table.insert(out, i - 1) end
	if y + 1 < H and m.openN[i] then table.insert(out, i + W) end
	if y - 1 >= 0 and m.openN[i - W] then table.insert(out, i - W) end
	return out
end

function M.bfs(m: any, src: number, allowed: any?): ({ [number]: number }, { [number]: number })
	local dist, parent = { [src] = 0 }, {}
	local q, head = { src }, 1
	while head <= #q do
		local c = q[head]; head += 1
		for _, n in M.neighbours(m, c) do
			if dist[n] == nil and (allowed == nil or allowed[n]) then
				dist[n] = dist[c] + 1
				parent[n] = c
				table.insert(q, n)
			end
		end
	end
	return dist, parent
end

function M.pathTo(parent: { [number]: number }, src: number, dst: number): { number }
	local p = { dst }
	local c = dst
	while c ~= src do
		c = parent[c]
		if c == nil then return {} end
		table.insert(p, 1, c)
	end
	return p
end

local PERMS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
M.PERMS = PERMS

-- placement. rules = { sealAMin, sealAMax, sealMin, sealSep, doorFrac, doorSealSep, hazards, hazardMinE, hazardSep }
function M.place(m: any, entrance: number, rules: any, rng: any): any?
	local n = m.W * m.H
	local dE = M.bfs(m, entrance)
	local maxE = 0
	for _, d in dE do if d > maxE then maxE = d end end
	local function pick(pred: (number) -> boolean): number?
		local c = {}
		for i = 0, n - 1 do if pred(i) then table.insert(c, i) end end
		if #c == 0 then return nil end
		return c[rng:NextInteger(1, #c)]
	end
	local dists = {}
	local function d(a: number, b: number): number
		if dists[a] == nil then dists[a] = (M.bfs(m, a)) end
		return dists[a][b]
	end
	local a = pick(function(i) return dE[i] >= rules.sealAMin and dE[i] <= rules.sealAMax end)
	if a == nil then return nil end
	local b = pick(function(i) return i ~= a and dE[i] >= rules.sealMin and d(a, i) >= rules.sealSep end)
	if b == nil then return nil end
	local c = pick(function(i) return i ~= a and i ~= b and dE[i] >= rules.sealMin and d(a, i) >= rules.sealSep and d(b, i) >= rules.sealSep end)
	if c == nil then return nil end
	local door = pick(function(i)
		return i ~= a and i ~= b and i ~= c and dE[i] >= rules.doorFrac * maxE
			and d(a, i) >= rules.doorSealSep and d(b, i) >= rules.doorSealSep and d(c, i) >= rules.doorSealSep
	end)
	if door == nil then return nil end
	return { entrance = entrance, seals = { a, b, c }, door = door, dE = dE, maxE = maxE, d = d }
end

-- best order: returns steps, order, cell route (list of cells incl. entrance ... door), legs (waypoint indices)
function M.route(m: any, p: any): any
	local best, bestOrder = math.huge, nil
	for _, o in PERMS do
		local s = p.seals
		local L = p.dE[s[o[1]]] + p.d(s[o[1]], s[o[2]]) + p.d(s[o[2]], s[o[3]]) + p.d(s[o[3]], p.door)
		if L < best then best, bestOrder = L, o end
	end
	local pts = { p.entrance, p.seals[bestOrder[1]], p.seals[bestOrder[2]], p.seals[bestOrder[3]], p.door }
	local cells = { p.entrance }
	local waypointAt = { 1 }
	for k = 1, 4 do
		local _, parent = M.bfs(m, pts[k])
		local seg = M.pathTo(parent, pts[k], pts[k + 1])
		for j = 2, #seg do table.insert(cells, seg[j]) end
		table.insert(waypointAt, #cells)
	end
	return { steps = best, order = bestOrder, cells = cells, waypointAt = waypointAt }
end

-- ---------------------------------------------------------------- funnel (string pulling)
local function triarea2(a: any, b: any, c: any): number
	local ax, ay = b.x - a.x, b.y - a.y
	local bx, by = c.x - a.x, c.y - a.y
	return bx * ay - ax * by
end
local function veq(a: any, b: any): boolean
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < 1e-12
end
local function dist(a: any, b: any): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
M.dist = dist

function M.centre(m: any, i: number, cell: number): any
	return { x = (i % m.W + 0.5) * cell, y = (i // m.W + 0.5) * cell }
end

-- portal between consecutive cells a -> b; flip swaps left/right (orientation convention check)
local function portal(m: any, a: number, b: number, cell: number, margin: number, flip: boolean): (any, any)
	local ax, ay = a % m.W, a // m.W
	local bx, by = b % m.W, b // m.W
	local L, R
	if bx > ax then -- east: edge x = bx*cell, y in [ay*cell, (ay+1)*cell]; left = north
		local xb = bx * cell
		L = { x = xb, y = (ay + 1) * cell - margin }; R = { x = xb, y = ay * cell + margin }
	elseif bx < ax then -- west: left = south
		local xb = ax * cell
		L = { x = xb, y = ay * cell + margin }; R = { x = xb, y = (ay + 1) * cell - margin }
	elseif by > ay then -- north: left = west
		local yb = by * cell
		L = { x = ax * cell + margin, y = yb }; R = { x = (ax + 1) * cell - margin, y = yb }
	else -- south: left = east
		local yb = ay * cell
		L = { x = (ax + 1) * cell - margin, y = yb }; R = { x = ax * cell + margin, y = yb }
	end
	if flip then return R, L end
	return L, R
end

function M.stringPull(portals: { any }): (number, { any })
	local pts = {}
	local apex, pl, pr = portals[1][1], portals[1][1], portals[1][2]
	local ai, li, ri = 1, 1, 1
	table.insert(pts, apex)
	local i = 2
	local n = #portals
	while i <= n do
		local left, right = portals[i][1], portals[i][2]
		local restarted = false
		if triarea2(apex, pr, right) <= 0 then
			if veq(apex, pr) or triarea2(apex, pl, right) > 0 then
				pr = right; ri = i
			else
				table.insert(pts, pl)
				apex = pl; ai = li
				pl = apex; pr = apex; li = ai; ri = ai
				i = ai + 1
				restarted = true
			end
		end
		if not restarted then
			if triarea2(apex, pl, left) >= 0 then
				if veq(apex, pl) or triarea2(apex, pr, left) < 0 then
					pl = left; li = i
				else
					table.insert(pts, pr)
					apex = pr; ai = ri
					pl = apex; pr = apex; li = ai; ri = ai
					i = ai + 1
					restarted = true
				end
			end
		end
		if not restarted then i += 1 end
	end
	local last = portals[n][1]
	if not veq(pts[#pts], last) then table.insert(pts, last) end
	local len = 0
	for k = 2, #pts do len += dist(pts[k - 1], pts[k]) end
	return len, pts
end

-- funnel length of a cell sequence from point s to point e
function M.funnel(m: any, cells: { number }, s: any, e: any, cell: number, margin: number, flip: boolean): number
	local portals = { { s, s } }
	for k = 2, #cells do
		local L, R = portal(m, cells[k - 1], cells[k], cell, margin, flip)
		table.insert(portals, { L, R })
	end
	table.insert(portals, { e, e })
	return (M.stringPull(portals))
end

return M
