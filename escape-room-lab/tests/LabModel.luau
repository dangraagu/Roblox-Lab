-- LabModel.luau — the pacing model behind tests/Pacing.spec.luau (DESIGN.md §10).
--
-- Ported from design/model.luau Part 5, with one change that matters: the rooms a simulated player
-- meets come from THIS GAME'S generators (src/shared/CodeLock, Shelf) and THIS GAME'S wing table
-- (Config.Lab.Wings), not from the design's reference copies. So a change to the table, the door rules
-- or a generator moves the brag minute here, and the spec's bounds catch the drift.
--
-- What this is NOT: a model of real humans. Every reading, thinking and error rate below is an
-- ASSUMPTION ([A] in DESIGN.md §10.1). The first real play session replaces them; retune the profiles
-- first, then the wing table.
local CodeLock = require("../src/shared/CodeLock")
local Shelf = require("../src/shared/Shelf")
local Lab = require("../src/shared/Lab")
local Rng = require("../src/shared/Rng")

local LabModel = {}

LabModel.PROFILES = {
	careful = {
		doorRead = 3, doorThink = 8, shelfRead = 3, shelfThink = 5, lampThink = 3, lampWaste = 1.2,
		pWrongDoor3 = 0.03, pWrongDoor4 = 0.04, pWrongShelf = 0.03, pHintDoor3 = 0, pHintDoor4 = 0,
		pHintShelf = 0, pHintLamp = 0,
	},
	normal = {
		doorRead = 4, doorThink = 11, shelfRead = 4, shelfThink = 7, lampThink = 5, lampWaste = 1.8,
		pWrongDoor3 = 0.15, pWrongDoor4 = 0.25, pWrongShelf = 0.12, pHintDoor3 = 0.08, pHintDoor4 = 0.15,
		pHintShelf = 0.08, pHintLamp = 0.10,
	},
	firstTimer = {
		doorRead = 5, doorThink = 16, shelfRead = 5, shelfThink = 10, lampThink = 8, lampWaste = 2.5,
		pWrongDoor3 = 0.28, pWrongDoor4 = 0.40, pWrongShelf = 0.22, pHintDoor3 = 0.20, pHintDoor4 = 0.35,
		pHintShelf = 0.20, pHintLamp = 0.25,
	},
}

-- [A] unless marked [R] (worked from the room geometry, DESIGN.md §5, at WalkSpeed 16) or [C] (Config)
LabModel.MODEL = {
	Door4Factor = 1.5, ShelfSizeFactor = 1.3, TapSeconds = 0.6, DialSeconds = 1.2,
	HintSaves = 0.4, RethinkShare = 0.3,
	OpenSeconds = 0.5, StationWalk = 1.6, EntryWalk = 1.0, ExitWalk = 1.5, -- [R]
	RoomIntro = 3, HazardCostSeconds = 2.5,
}

local function quantiles(xs)
	local s = table.clone(xs)
	table.sort(s)
	local n = #s
	local function q(p) return s[math.clamp(math.floor(p * (n - 1) + 0.5) + 1, 1, n)] end
	local sum = 0
	for _, v in s do sum += v end
	return { min = s[1], p10 = q(0.10), p50 = q(0.50), p90 = q(0.90), max = s[n], mean = sum / n }
end
LabModel.quantiles = quantiles

-- Pools of what the generators really produce: door line counts per room kind, shelf clue counts per N.
function LabModel.pools(cfg, seed)
	local r = Rng.new(seed)
	local rand = function() return r:next() end
	local doors, shelves = {}, {}
	local doorN = { [3] = 250, [4] = 80 }
	for slot = 1, Lab.rooms(cfg) do
		local spec = Lab.roomSpec(cfg, slot)
		local key = string.format("L%d:%d:f%d:%d", spec.door.L, #spec.door.alphabet, #spec.feeders, spec.door.maxLines)
		if doors[key] == nil then
			local pool = {}
			for _ = 1, doorN[spec.door.L] do
				local d = CodeLock.generate({ L = spec.door.L, alphabet = spec.door.alphabet, feeders = #spec.feeders,
					maxLines = spec.door.maxLines }, rand)
				table.insert(pool, #d.lines)
			end
			doors[key] = pool
		end
		for _, f in spec.feeders do
			if f.kind == "shelf" and shelves[f.N] == nil then
				local pool = {}
				for _ = 1, 250 do
					table.insert(pool, #Shelf.generate({ N = f.N, maxClues = cfg.Puzzles.MaxShelfClues }, rand).clues)
				end
				shelves[f.N] = pool
			end
		end
	end
	return { doors = doors, shelves = shelves }
end

local function doorKey(spec)
	return string.format("L%d:%d:f%d:%d", spec.door.L, #spec.door.alphabet, #spec.feeders, spec.door.maxLines)
end

-- One room for one simulated player: seconds, stars, seconds exposed to hazards.
function LabModel.playRoom(cfg, pools, p, rng, slot)
	local M = LabModel.MODEL
	local spec = Lab.roomSpec(cfg, slot)
	local function pick(pool) return pool[rng:below(#pool)] end
	local function lockout(n) return Lab.lockoutFor(cfg, n) end
	local t = M.RoomIntro + M.EntryWalk
	local wrong, hinted = false, false
	for _, f in spec.feeders do
		local st = M.OpenSeconds
		if f.kind == "lamp" then
			local think = f.k * p.lampThink * (if f.n == 4 then 1.25 else 1)
			if rng:next() < p.pHintLamp then hinted = true; think *= (1 - M.HintSaves) end
			st += think + math.ceil(f.k * p.lampWaste) * M.TapSeconds
		else
			local m = pick(pools.shelves[f.N])
			local think = m * (p.shelfRead + p.shelfThink * M.ShelfSizeFactor ^ (f.N - 3))
			if rng:next() < p.pHintShelf then hinted = true; think *= (1 - M.HintSaves) end
			st += think + (f.N - 1) * M.TapSeconds + 0.5
			local tries = 0
			while rng:next() < p.pWrongShelf * (if tries == 0 then 1 else 0.5) do
				tries += 1
				wrong = true
				st += lockout(tries) + think * M.RethinkShare + (f.N - 1) * M.TapSeconds + 0.5
				if tries > 6 then break end
			end
		end
		t += st + M.StationWalk
	end
	-- review-1 B4: the hazard clock runs only on a legal spot past the arrival grace, so the door station
	-- (where a room's longest think happens) and the first 8 s are not exposed: the feeders are
	local exposedUntil = t
	local four = spec.door.L == 4
	local m = pick(pools.doors[doorKey(spec)])
	local think = m * (p.doorRead + p.doorThink * (if four then M.Door4Factor else 1))
	if rng:next() < (if four then p.pHintDoor4 else p.pHintDoor3) then hinted = true; think *= (1 - M.HintSaves) end
	local dt = M.OpenSeconds + think + spec.door.L * M.DialSeconds + 0.5
	local tries = 0
	local pWrong = if four then p.pWrongDoor4 else p.pWrongDoor3
	while rng:next() < pWrong * (if tries == 0 then 1 else 0.5) do
		tries += 1
		wrong = true
		dt += lockout(tries) + think * M.RethinkShare + spec.door.L * M.DialSeconds + 0.5
		if tries > 6 then break end
	end
	t += dt + M.ExitWalk
	-- hazards: none in the first wing; each costs a dodge
	local exposed = 0
	if #cfg.Env.Bands[spec.wing].hazards > 0 then
		exposed = math.max(0, exposedUntil - cfg.Lift.ArrivalGraceSeconds)
		local mean = (cfg.Hazards.IntervalMin + cfg.Hazards.IntervalMax) / 2
		local expected = exposed / mean
		local n = math.floor(expected)
		if rng:next() < expected - n then n += 1 end
		t += n * M.HazardCostSeconds
	end
	local stars = Lab.stars({ escaped = true, wrong = wrong, hinted = hinted, pair = false })
	local lift = cfg.Lift.BoardSeconds + cfg.Lift.RideSeconds -- [C]
	return t + lift, stars, exposed
end

-- players simulated walks of one profile: to the Roof, then Continue to 45 stars.
function LabModel.run(cfg, pools, profileName, players, seed)
	local p = LabModel.PROFILES[profileName]
	local rng = Rng.new(seed)
	local rooms = Lab.rooms(cfg)
	local out = { roofMin = {}, star45Min = {}, starsFirst = {}, bandMin = {}, hazards = {}, firstHazardMin = {} }
	for w = 1, #cfg.Lab.Wings do out.bandMin[w] = {} end
	local mean = (cfg.Hazards.IntervalMin + cfg.Hazards.IntervalMax) / 2
	for _ = 1, players do
		local clock, hz = 0, 0
		local best = {}
		local firstHazard = nil
		for w = 1, #cfg.Lab.Wings do
			local w0 = clock
			if firstHazard == nil and #cfg.Env.Bands[w].hazards > 0 then firstHazard = clock end
			for r = 1, #cfg.Lab.Wings[w].rooms do
				local slot = Lab.slotOf(w, r)
				local t, s, exposed = LabModel.playRoom(cfg, pools, p, rng, slot)
				clock += t
				hz += exposed / mean
				best[tostring(slot)] = s
			end
			table.insert(out.bandMin[w], (clock - w0) / 60)
		end
		table.insert(out.roofMin, clock / 60)
		table.insert(out.hazards, hz)
		table.insert(out.firstHazardMin, (firstHazard or 0) / 60)
		table.insert(out.starsFirst, Lab.total(best))
		local last = rooms
		while Lab.total(best) < 3 * rooms and clock < 20 * 3600 do
			local slot = Lab.continueSolo(best, last, rooms)
			local t, s = LabModel.playRoom(cfg, pools, p, rng, slot)
			clock += t
			if s > (best[tostring(slot)] or 0) then best[tostring(slot)] = s end
			last = slot
		end
		table.insert(out.star45Min, clock / 60)
	end
	return out
end

return LabModel
