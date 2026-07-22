--!strict
-- Medalje-/rekordlogikk (TrackMania-stil) for labyrint-spillet. Ren logikk,
-- ingen Roblox-API, så den kan testes med luau CLI.
--
-- "Optimal tid" (par) for et nivå regnes ut fra selve banen: korteste rute som
-- samler alle påkrevde ting (mynter) og så når utgangen. Siden banen er
-- deterministisk pr nivå, blir par — og dermed medalje-tidene — helt like for
-- alle spillere. Medaljer gis ved å slå par ganget med en faktor:
--   Diamant <= par*1.3, Gull <= par*1.8, Sølv <= par*2.5, Bronse <= par*4.0.

local Medals = {}

Medals.order = { "diamant", "gull", "solv", "bronse" }  -- raskest -> tregest

Medals.mult = { diamant = 1.3, gull = 1.8, solv = 2.5, bronse = 4.0 }

Medals.display = {
	diamant = { name = "Diamant",  color = { 120, 225, 240 } },
	gull    = { name = "Gull",     color = { 255, 215, 0 } },
	solv    = { name = "Sølv",     color = { 205, 205, 210 } },
	bronse  = { name = "Bronse",   color = { 205, 127, 50 } },
	none    = { name = "Fullført", color = { 180, 180, 180 } },
}

-- Nøkkel for en finrute-celle
local function key(x, y) return x .. "," .. y end

-- BFS fra (sx,sy) over gåbare celler (grid[y][x] == false betyr åpen).
-- Returnerer avstandskart key(x,y) -> antall steg.
function Medals.dist(grid, gCols, gRows, sx, sy)
	local dist = {}
	dist[key(sx, sy)] = 0
	local q = { { sx, sy } }
	local head = 1
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	while head <= #q do
		local cur = q[head]; head += 1
		local x, y = cur[1], cur[2]
		local dxy = dist[key(x, y)]
		for _, d in ipairs(dirs) do
			local nx, ny = x + d[1], y + d[2]
			if nx >= 0 and nx < gCols and ny >= 0 and ny < gRows
				and grid[ny] and grid[ny][nx] == false and dist[key(nx, ny)] == nil then
				dist[key(nx, ny)] = dxy + 1
				table.insert(q, { nx, ny })
			end
		end
	end
	return dist
end

-- Grådig rute (nearest-neighbor): fra start, innom hver mustVisit-celle
-- (nærmeste først), til slutt til exit. Returnerer totalt antall steg, eller
-- nil hvis noe er uinnåbart. start/exit/mustVisit = { x, y } finrute-celler.
function Medals.solveRoute(grid, gCols, gRows, start, exit, mustVisit)
	local remaining = {}
	for _, c in ipairs(mustVisit or {}) do
		table.insert(remaining, { c[1], c[2] })
	end
	local cur = { start[1], start[2] }
	local total = 0
	while #remaining > 0 do
		local dist = Medals.dist(grid, gCols, gRows, cur[1], cur[2])
		local bestIdx, bestD = nil, math.huge
		for i, c in ipairs(remaining) do
			local dd = dist[key(c[1], c[2])]
			if dd ~= nil and dd < bestD then
				bestD = dd; bestIdx = i
			end
		end
		if not bestIdx then return nil end  -- en påkrevd celle er uinnåbar
		total += bestD
		cur = remaining[bestIdx]
		table.remove(remaining, bestIdx)
	end
	local dist = Medals.dist(grid, gCols, gRows, cur[1], cur[2])
	local de = dist[key(exit[1], exit[2])]
	if de == nil then return nil end
	return total + de
end

-- Steg -> sekunder (perfekt optimal gange).
function Medals.parTime(steps, cellSize, walkSpeed)
	if not steps or walkSpeed <= 0 then return nil end
	return steps * cellSize / walkSpeed
end

-- Medalje-terskler (sekunder) fra par.
function Medals.thresholds(par)
	if not par then return nil end
	return {
		diamant = par * Medals.mult.diamant,
		gull    = par * Medals.mult.gull,
		solv    = par * Medals.mult.solv,
		bronse  = par * Medals.mult.bronse,
	}
end

-- Beste medalje for en fullført tid gitt tersklene. "none" = fullført uten medalje.
function Medals.medalFor(elapsed, thr)
	if not thr then return "none" end
	for _, id in ipairs(Medals.order) do
		if elapsed <= thr[id] then return id end
	end
	return "none"
end

-- Formater sekunder pent (delt av server og klient).
function Medals.fmtTime(t)
	if t == nil then return "-" end
	if t >= 60 then
		local m = math.floor(t / 60)
		local s = t - m * 60
		return string.format("%d:%04.1f", m, s)
	end
	return string.format("%.1fs", t)
end

return Medals
