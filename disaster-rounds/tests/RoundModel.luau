-- RoundModel.luau - the pacing model of DESIGN.md §2.8, rebuilt on the game's REAL modules (not a spec; Pacing.spec
-- plays it). design/pacing_model.py was the design-time copy; this one reads the real Config and calls the real
-- MapGen, Strikes, Zones, Flood, Tornado, Quake, Progress and EnvBands, so a tuning change in the game moves these
-- numbers. What stays the model's own is the human part, written down in Config.Pacing.Profiles: a reaction time
-- (lognormal around `react`, sigma 0.35), lapses (a threat noticed 1-4 s late, a flood warning 2-8 s late), and
-- players who walk at 16 studs/s to the nearest point outside all the red they have noticed.
--
--   * per-round tables: the chance to survive each disaster at each Heat, per profile (rings x the disaster itself);
--   * sessions: join at a random point of the 88 s cycle, play 4 h of rounds at the measured odds, track streak ->
--     Heat, lifetime survivals -> bands, the Codex and the best streak.

local MapGen = require("../src/shared/MapGen")
local Strikes = require("../src/shared/Strikes")
local Zones = require("../src/shared/Zones")
local Flood = require("../src/shared/Flood")
local Tornado = require("../src/shared/Tornado")
local Quake = require("../src/shared/Quake")
local Progress = require("../src/shared/Progress")
local Round = require("../src/shared/Round")
local Rng = require("../src/shared/Rng")

local RoundModel = {}

local WALK = 16

--======================================================================= randomness

local function newRand(seed: number)
	local r = Rng.new(seed)
	local self = {}
	function self.u(): number return r:next() end
	function self.range(a: number, b: number): number return a + (b - a) * r:next() end
	function self.pick(t: { any }): any return t[math.min(#t, 1 + math.floor(r:next() * #t))] end
	function self.gauss(): number
		local u1 = math.max(1e-12, r:next())
		local u2 = r:next()
		return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	end
	return self
end
RoundModel.newRand = newRand

local function react(R: any, prof: any, big: boolean): number
	if prof.fixed then return prof.react end
	local t = prof.react * math.exp(R.gauss() * 0.35)
	local lapse = if big then prof.lapseBig else prof.lapseRing
	if R.u() < lapse then
		t += if big then R.range(2, 8) else R.range(1, 4)
	end
	return t
end

--======================================================================= a walker the server sees one latency late

local function mover(x: number, z: number): any
	return { x = x, z = z, tx = nil, tz = nil, hist = {}, alive = true }
end
local function step(m: any, t: number, dt: number)
	if m.tx then
		local dx, dz = m.tx - m.x, m.tz - m.z
		local d = math.sqrt(dx * dx + dz * dz)
		local s = WALK * dt
		if d <= s then
			m.x, m.z, m.tx, m.tz = m.tx, m.tz, nil, nil
		else
			m.x += dx / d * s
			m.z += dz / d * s
		end
	end
	table.insert(m.hist, { t, m.x, m.z })
	if #m.hist > 40 then table.remove(m.hist, 1) end
end
local function seenAt(m: any, s: number, latency: number): (number, number)
	local want = s - latency
	local best = m.hist[1] or { s, m.x, m.z }
	for _, h in m.hist do
		if h[1] <= want + 1e-9 then best = h end
	end
	return best[2], best[3]
end

-- nearest point outside every disk {x, z, r} (+ margin) inside bounds; never across a landing ring
local function crossesLanding(x0: number, z0: number, x1: number, z1: number, timed: { any }, now: number): boolean
	local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local T = L / WALK
	for _, r in timed do
		local lo, hi = r.impact - 0.15 - now, r.impact + 0.25 - now
		if hi >= 0 then
			local s = math.max(0, lo)
			while s <= hi do
				local f = if T > 0 then math.min(1, s / T) else 1
				local px, pz = x0 + (x1 - x0) * f, z0 + (z1 - z0) * f
				if (px - r.x) ^ 2 + (pz - r.z) ^ 2 < r.r * r.r then return true end
				s += 0.05
			end
		end
	end
	return false
end
local function nearestFree(x: number, z: number, disks: { any }, bounds: (number, number) -> boolean, timed: { any }?, now: number): (number, number)
	local margin = 0.8
	local function blocked(px: number, pz: number): boolean
		for _, d in disks do
			if (px - d.x) ^ 2 + (pz - d.z) ^ 2 < (d.r + margin) ^ 2 then return true end
		end
		return false
	end
	if not blocked(x, z) then return x, z end
	for k = 1, 60 do
		local d = 0.5 * k
		for a = 0, 31 do
			local ang = a * math.pi / 16
			local px, pz = x + math.cos(ang) * d, z + math.sin(ang) * d
			if bounds(px, pz) and not blocked(px, pz) and not (timed and crossesLanding(x, z, px, pz, timed, now)) then
				return px, pz
			end
		end
	end
	return x, z
end

--======================================================================= the aimed rings (Strikes + Zones, real)

-- One round of aimed rings on a flat square [-half, half]^2. -> survived flags, rings per player
function RoundModel.ringRound(Config: any, R: any, prof: any, kind: string, heat: number, nPlayers: number, half: number,
	capArea: number?, tEnd: number?): ({ boolean }, { number })
	local ringR = Zones.ringRadius(Config)
	local area = capArea or (2 * half) ^ 2
	local latency = Config.Pacing.LatencySeconds
	local grace = Config.Hits.LagGrace
	local tel, pass = Config.Strikes.TelegraphSeconds, Config.Strikes.PassSeconds
	local endT = tEnd or Config.Round.DisasterSeconds
	local bounds = function(px: number, pz: number): boolean return math.abs(px) <= half and math.abs(pz) <= half end
	local ps = {}
	for _ = 1, nPlayers do
		local x, z = 0, 0
		for _ = 1, 200 do
			x, z = R.range(-half + 2, half - 2), R.range(-half + 2, half - 2)
			local ok = true
			for _, q in ps do
				if (x - q.x) ^ 2 + (z - q.z) ^ 2 < 16 then ok = false end
			end
			if ok then break end
		end
		local m = mover(x, z)
		m.ps = Strikes.newPlayer(Config, kind, heat, 0, R.u)
		table.insert(ps, m)
	end
	local rings = {}
	local count = {}
	for k = 1, nPlayers do count[k] = 0 end
	local dt = 0.05
	local t = 0
	while t <= endT + 1e-9 do
		local live = {}
		for _, r in rings do
			if r.ends > t then table.insert(live, r) end
		end
		-- spawn
		for k, p in ps do
			if p.alive and Strikes.due(Config, p.ps, t, endT) then
				local sx, sz = seenAt(p, t, latency)
				local disks = {}
				for _, r in live do table.insert(disks, { x = r.x, z = r.z, r = ringR }) end
				local others = {}
				for _, q in ps do
					if q.alive then table.insert(others, { x = q.x, z = q.z }) end
				end
				if Strikes.canPlace(Config, { x = sx, z = sz }, disks, others, bounds, area, Zones.exitDistance) then
					local r = { x = sx, z = sz, impact = t + tel, ends = t + tel + pass, seenAt = {}, judged = false }
					for j = 1, nPlayers do r.seenAt[j] = t + react(R, prof, false) end
					table.insert(rings, r)
					table.insert(live, r)
					count[k] += 1
					Strikes.placed(Config, p.ps, t, R.u)
				else
					Strikes.deferred(Config, p.ps, t)
				end
			end
		end
		-- react: walk to the nearest point outside every ring noticed, never across one as it lands
		for k, p in ps do
			if p.alive then
				local noticed, timed = {}, {}
				for _, r in live do
					if r.seenAt[k] <= t and r.impact + 0.25 > t then
						table.insert(noticed, { x = r.x, z = r.z, r = ringR })
						table.insert(timed, { x = r.x, z = r.z, r = ringR, impact = r.impact })
					end
				end
				if #noticed > 0 then
					local gx, gz = p.tx or p.x, p.tz or p.z
					local bad = false
					for _, d in noticed do
						if (gx - d.x) ^ 2 + (gz - d.z) ^ 2 < (d.r + 0.3) ^ 2 then bad = true end
					end
					if not bad and p.tx then bad = crossesLanding(p.x, p.z, p.tx, p.tz, timed, t) end
					if bad then
						local fx, fz = nearestFree(p.x, p.z, noticed, bounds, timed, t)
						if fx ~= p.x or fz ~= p.z then p.tx, p.tz = fx, fz end
					end
				end
			end
		end
		for _, p in ps do
			if p.alive then step(p, t, dt) end
		end
		-- judge with the real rule: every server sample in [impact, impact + grace] inside = hit
		for _, r in live do
			if not r.judged and t >= r.impact + grace - 1e-9 then
				r.judged = true
				for _, p in ps do
					if p.alive then
						local j = Zones.newJudge(r.impact, grace)
						local verdict = nil
						local s = r.impact
						while s <= r.impact + grace + 1e-9 and verdict == nil do
							local sx, sz = seenAt(p, s, latency)
							verdict = Zones.judgeSample(j, 1, s, Zones.inDisk(r.x, r.z, ringR, sx, sz))
							s += Config.Round.TickSeconds
						end
						if verdict == "hit" then p.alive = false end
					end
				end
			end
		end
		t += dt
	end
	local alive = {}
	for k, p in ps do alive[k] = p.alive end
	return alive, count
end

--======================================================================= the flood (Flood + MapGen, real)

function RoundModel.floodRound(Config: any, R: any, prof: any, levels: { { number } }): (boolean, number)
	local n = #levels
	local cells = {}
	for i = 1, n do
		for j = 1, n do
			if levels[i][j] >= 1 then table.insert(cells, { i, j }) end
		end
	end
	local c = R.pick(cells)
	local i, j = c[1], c[2]
	local threats = 0
	local fc = Config.Flood
	local avail = fc.WarnSeconds + fc.RiseSeconds / 2 + Config.Hits.GroundGrace
	local cell = Config.Island.CellStuds
	for k, rise in Flood.plan(Config) do
		local covered = rise.level + 1 -- this rise floods levels < covered
		if levels[i][j] < covered then
			threats += 1
			local _, dist = MapGen.floodEscape(levels, covered)
			local d = dist[i][j]
			if d == math.huge then return false, threats end
			local studs = d * cell + cell / 2
			local need = react(R, prof, true) + studs * Config.Island.PathFactor / WALK
			if need > avail then return false, threats end
			while dist[i][j] > 0 do
				local moved = false
				for _, dd in MapGen.DIRS do
					local a, b = i + dd[1], j + dd[2]
					if a >= 1 and a <= n and b >= 1 and b <= n and levels[a][b] >= covered - 1 and dist[a][b] == dist[i][j] - 1
						and math.abs(levels[a][b] - levels[i][j]) <= 1 then
						i, j = a, b
						moved = true
						break
					end
				end
				if not moved then break end
			end
		end
		local _ = k
	end
	return true, threats
end

--======================================================================= the tornado (Tornado, real)

function RoundModel.tornadoRound(Config: any, R: any, prof: any, nPlayers: number): { any }
	local half = Config.Island.Grid * Config.Island.CellStuds / 2 - 2
	local zone = Zones.funnelRadius(Config)
	local latency = Config.Pacing.LatencySeconds
	local tc = Config.Tornado
	local bounds = function(px: number, pz: number): boolean return math.abs(px) <= half and math.abs(pz) <= half end
	local ps = {}
	for _ = 1, nPlayers do
		local x, z = 0, 0
		for _ = 1, 200 do
			x, z = R.range(-half + 4, half - 4), R.range(-half + 4, half - 4)
			local ok = true
			for _, q in ps do
				if (x - q.x) ^ 2 + (z - q.z) ^ 2 < 100 then ok = false end
			end
			if ok then break end
		end
		table.insert(ps, mover(x, z))
	end
	local function positions()
		local out = {}
		for _, p in ps do
			if p.alive then table.insert(out, { x = p.x, z = p.z }) end
		end
		return out
	end
	local s = Tornado.start(Config, positions(), R.u)
	Tornado.extend(Config, s, tc.TouchdownAt + tc.HorizonSeconds, positions(), R.u)
	local threats, covered, seenT, dwell = {}, {}, {}, Zones.newDwell()
	for k = 1, nPlayers do threats[k], covered[k] = 0, false end
	local dt = 0.05
	local t = 0
	while t <= Config.Round.DisasterSeconds + 1e-9 do
		Tornado.extend(Config, s, math.max(t, tc.TouchdownAt) + tc.HorizonSeconds, positions(), R.u)
		local ribbon = {}
		for _, q in Tornado.window(s, t - 0.3, math.max(t, tc.TouchdownAt) + tc.HorizonSeconds) do
			table.insert(ribbon, { x = q.x, z = q.z, r = zone })
		end
		for k, p in ps do
			if p.alive then
				local on = false
				for _, d in ribbon do
					if (p.x - d.x) ^ 2 + (p.z - d.z) ^ 2 < d.r * d.r then on = true break end
				end
				local gx, gz = p.tx or p.x, p.tz or p.z
				local goalOn = false
				for _, d in ribbon do
					if (gx - d.x) ^ 2 + (gz - d.z) ^ 2 < (d.r + 0.3) ^ 2 then goalOn = true break end
				end
				if (on or goalOn) and not covered[k] then
					covered[k] = true
					threats[k] += 1
					seenT[k] = t + react(R, prof, false)
				end
				if not on and not goalOn then covered[k] = false end
				if covered[k] and seenT[k] and t >= seenT[k] and goalOn then
					p.tx, p.tz = nearestFree(p.x, p.z, ribbon, bounds, nil, t)
				end
			end
		end
		for _, p in ps do
			if p.alive then step(p, t, dt) end
		end
		local fx, fz = Tornado.positionAt(s, t)
		if fx and fz then
			for k, p in ps do
				if p.alive then
					local sx, sz = seenAt(p, t, latency)
					if Zones.dwell(dwell, k, Zones.inDisk(fx, fz, zone, sx, sz), t, Config.Hits.LagGrace) then p.alive = false end
				end
			end
		end
		t += dt
	end
	local out = {}
	for k, p in ps do out[k] = { alive = p.alive, threats = threats[k] } end
	return out
end

--======================================================================= the quake (Quake, real)

function RoundModel.quakeRound(Config: any, R: any, prof: any, levels: { { number } }, nPlayers: number): ({ any }, number, number)
	local n = #levels
	local cellS = Config.Island.CellStuds
	local qc = Config.Quake
	local q = Quake.new()
	local cells = {}
	for i = 1, n do
		for j = 1, n do
			if levels[i][j] >= 1 then table.insert(cells, { i, j }) end
		end
	end
	local pos = {}
	for k = 1, nPlayers do
		local c = R.pick(cells)
		pos[k] = { i = c[1], j = c[2], ox = R.range(0.15, 0.85), oz = R.range(0.15, 0.85), alive = true, threats = 0 }
	end
	local minMargin = 99
	for _, t in Quake.batchTimes(Config) do
		Quake.update(q, t)
		local standing = {}
		for _, p in pos do
			if p.alive then table.insert(standing, { i = p.i, j = p.j }) end
		end
		local batch = Quake.pickBatch(Config, levels, q, standing, R.u)
		Quake.crack(q, batch, t, qc.CrackSeconds)
		for _, p in pos do
			if p.alive and Quake.isCracking(q, p.i, p.j) then
				p.threats += 1
				local best = nil
				for _, dd in MapGen.DIRS do
					local a, b = p.i + dd[1], p.j + dd[2]
					if a >= 1 and a <= n and b >= 1 and b <= n and not Quake.isDropped(q, a, b) and not Quake.isCracking(q, a, b)
						and math.abs(levels[a][b] - levels[p.i][p.j]) <= 1 then
						local d
						if a == p.i + 1 then d = (1 - p.ox) * cellS
						elseif a == p.i - 1 then d = p.ox * cellS
						elseif b == p.j + 1 then d = (1 - p.oz) * cellS
						else d = p.oz * cellS end
						d += Config.Hits.PlayerRadius + 0.5
						if best == nil or d < best.d then best = { d = d, a = a, b = b } end
					end
				end
				if best == nil then
					p.alive = false
				else
					local need = react(R, prof, false) + best.d * 1.15 / WALK
					local margin = qc.CrackSeconds + Config.Hits.LagGrace - need
					if prof.fixed then minMargin = math.min(minMargin, margin) end
					if margin < 0 then
						p.alive = false
					else
						local ni, nj = best.a, best.b
						p.ox = if ni > p.i then R.range(0.2, 0.5) elseif ni < p.i then R.range(0.5, 0.8) else p.ox
						p.oz = if nj > p.j then R.range(0.2, 0.5) elseif nj < p.j then R.range(0.5, 0.8) else p.oz
						p.i, p.j = ni, nj
					end
				end
			end
		end
	end
	Quake.update(q, 1e9)
	local out = {}
	for k, p in pos do out[k] = { alive = p.alive, threats = p.threats } end
	return out, Quake.brokenCount(q) / (n * n), minMargin
end

--======================================================================= per-round tables

function RoundModel.tables(Config: any, R: any, opts: any): any
	local rounds = opts.rounds or 150
	local maps = {}
	for _ = 1, opts.maps or 60 do
		table.insert(maps, (MapGen.generate(Config.Island, R.u)).levels)
	end
	local out = { ring = {}, ringsN = {}, glob = {}, threats = {}, quakeShare = {}, quakeMargin = 99 }
	for _, pname in opts.profiles do
		local prof = Config.Pacing.Profiles[pname]
		local rr = if prof.fixed then math.max(50, math.floor(rounds / 2)) else rounds
		for _, sched in { "meteor", "other" } do
			local kind = if sched == "meteor" then "meteor" else "flood"
			for heat = 0, 5 do
				local ok, n, rings = 0, 0, 0
				for _ = 1, rr do
					local alive, cnt = RoundModel.ringRound(Config, R, prof, kind, heat, 1, 40)
					if alive[1] then ok += 1 end
					n += 1
					rings += cnt[1]
				end
				out.ring[pname .. ":" .. sched .. ":" .. heat] = ok / n
				out.ringsN[sched .. ":" .. heat] = rings / n
			end
		end
		local fs, ft = 0, 0
		for k = 1, rounds do
			local a, th = RoundModel.floodRound(Config, R, prof, maps[(k - 1) % #maps + 1])
			if a then fs += 1 end
			ft += th
		end
		out.glob[pname .. ":flood"] = fs / rounds
		out.threats["flood:" .. pname] = ft / rounds
		local ts, tn, tt = 0, 0, 0
		for k = 1, math.max(20, math.floor(rounds / 4)) do
			for _, r in RoundModel.tornadoRound(Config, R, prof, if k % 2 == 1 then 1 else 8) do
				if r.alive then ts += 1 end
				tn += 1
				tt += r.threats
			end
		end
		out.glob[pname .. ":tornado"] = ts / tn
		out.threats["tornado:" .. pname] = tt / tn
		local qs, qn, qt = 0, 0, 0
		for k = 1, rounds do
			local res, share, margin = RoundModel.quakeRound(Config, R, prof, maps[(k - 1) % #maps + 1], if k % 2 == 1 then 1 else 8)
			table.insert(out.quakeShare, share)
			if prof.fixed then out.quakeMargin = math.min(out.quakeMargin, margin) end
			for _, r in res do
				if r.alive then qs += 1 end
				qn += 1
				qt += r.threats
			end
		end
		out.glob[pname .. ":quake"] = qs / qn
		out.threats["quake:" .. pname] = qt / qn
		out.glob[pname .. ":meteor"] = 1
	end
	return out
end

function RoundModel.pSurvive(tables: any, pname: string, kind: string, heat: number): number
	local sched = if kind == "meteor" then "meteor" else "other"
	return tables.glob[pname .. ":" .. kind] * tables.ring[pname .. ":" .. sched .. ":" .. heat]
end

--======================================================================= sessions

-- (first time on the island, first counted drop), seconds after joining at `phase` into the cycle
function RoundModel.firstAndStart(Config: any, phase: number): (number, number)
	local rc = Config.Round
	local I, D, W = rc.IntermissionSeconds, rc.DropSeconds, rc.PracticeUntilSeconds
	local cyc = Round.cycleSeconds(rc)
	local tap = 3.0
	if phase < I then return I - phase, I - phase end
	local nxt = cyc - phase + I
	if phase + tap <= I + D + W then return tap, nxt end
	return nxt, nxt
end

function RoundModel.session(Config: any, R: any, tables: any, pname: string, minutes: number, untilCodex: boolean?): any
	local rc = Config.Round
	local cyc = Round.cycleSeconds(rc)
	local bands = Config.Env.Bands
	local phase = R.range(0, cyc)
	local first, t = RoundModel.firstAndStart(Config, phase)
	local p = Progress.default()
	local bandT = {}
	local maxHeatT, codexT = nil, nil
	local bestAt, codexAt = {}, {}
	local lookout = 0
	local endT = minutes * 60
	while t < endT do
		local kind = Round.pickKind(Config.Disasters.Kinds, R.u, nil) -- the server's own pick (REVIEW-1 F4: an even draw)
		local heat = Progress.heat(Config, p.streak)
		local roundEnd = t + rc.DropSeconds + rc.DisasterSeconds
		if R.u() < RoundModel.pSurvive(tables, pname, kind, heat) then
			Progress.survive(p, Config, kind, heat, roundEnd)
			for b = 2, #bands do
				if bandT[b] == nil and p.survived >= bands[b].from then bandT[b] = roundEnd / 60 end
			end
			if maxHeatT == nil and Progress.heat(Config, p.streak) == Config.Heat.Max then maxHeatT = roundEnd / 60 end
			if codexT == nil and Progress.codexCount(p) == 24 then codexT = roundEnd / 60 end
			lookout += rc.IntermissionSeconds
		else
			Progress.eliminate(p, kind)
			local outAt = R.range(5, rc.DisasterSeconds)
			lookout += rc.IntermissionSeconds + rc.OutroSeconds + (rc.DisasterSeconds - outAt)
		end
		for _, m in { 30, 60, 120, 240 } do
			if bestAt[m] == nil and roundEnd >= m * 60 then
				bestAt[m] = p.best
				codexAt[m] = Progress.codexCount(p)
			end
		end
		t += cyc
		if untilCodex and codexT ~= nil then break end
	end
	return { first = first, bandT = bandT, maxHeatT = maxHeatT, codexT = codexT, bestAt = bestAt, codexAt = codexAt,
		survived = p.survived, lookoutShare = lookout / math.max(1, t) }
end

function RoundModel.pct(v: { number }, q: number): number
	if #v == 0 then return 0 end
	local s = table.clone(v)
	table.sort(s)
	return s[math.min(#s, math.floor(q * (#s - 1) + 0.5) + 1)]
end

return RoundModel
