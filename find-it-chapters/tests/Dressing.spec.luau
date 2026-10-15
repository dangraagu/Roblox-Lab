-- Spec for Dressing: the room generator and the re-dress on resume (DESIGN.md §3.3, §9, §19.2).
-- Run: luau tests/Dressing.spec.luau 2>&1
--
-- The rules every room keeps, by construction: exactly k props fit each clue, no prop fits two clues, no clue
-- contains another, partial-match decoys at the chapter's share, spacing and door clearance, every prop on a
-- surface of its height band, ids and positions dealt after a shuffle (so neither says anything about a role
-- beyond the public traits), and a payload built from an allowlist.
local Dressing = require("../src/shared/Dressing")
local Clue = require("../src/shared/Clue")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local R = Config.Room
local ROOMS = 300 -- per chapter (the design model used 2000; 300 x 16 specs = 4800 rooms here)

local function randOf(seed)
	local g = Rng.new(seed)
	return function() return g:next() end
end

local specs = {}
for ch = 1, 15 do table.insert(specs, Dressing.spec("book", ch, Config)) end
table.insert(specs, Dressing.spec("daily", 20733, Config))

eq(#specs, 16, "15 chapters and the Daily")
eq(specs[1].n, 3, "chapter 1: 3 items")
eq(specs[1].nearDoorFirst, true, "chapter 1 puts clue 1's candidates nearest the door")
eq(specs[2].nearDoorFirst, false, "only chapter 1 does")
eq(specs[16].n, 6, "the Daily: 6 items")
eq(specs[16].clock, 195, "the Daily's clock")
eq(specs[15].looks, 9 * 5 + 2, "looks = n * k + 2")
eq(specs[16].looks, 6 * 4 + 2, "the Daily: 26 looks")

local function inRect(x, z, cx, cz, hw, hd)
	return math.abs(x - cx) <= hw and math.abs(z - cz) <= hd
end

--============================================================ the rules, room after room
local worstAttempts, sumAttempts, rooms = 0, 0, 0
local partialShare = {}
for si, spec in specs do
	local rand = randOf(1000 + si)
	local bad = { k = 0, disjoint = 0, overlap = 0, count = 0, ids = 0, bounds = 0, door = 0, spacing = 0, surface = 0,
		tableClear = 0, shelfWall = 0, valid = 0, reach = 0, corner = 0 }
	local fill, partial = 0, 0
	for _ = 1, ROOMS do
		local room, attempts = Dressing.build(spec, rand, Config)
		rooms += 1
		sumAttempts += attempts
		worstAttempts = math.max(worstAttempts, attempts)
		local props = room.props
		if #props ~= spec.S then bad.count += 1 end
		-- ids 1..S, each once
		local seen = {}
		for i, p in props do
			if p.id ~= room.idBase + i or seen[p.id] then bad.ids += 1 end
			seen[p.id] = true
			if not Clue.validProp(p, Config) then bad.valid += 1 end
		end
		-- exact k, disjoint, no overlapping clues
		for ci, c in room.clues do
			local m = {}
			for _, p in props do
				if Clue.matches(p, c, Config) then table.insert(m, p.id) end
			end
			table.sort(m)
			local cands = table.clone(room.cands[ci])
			table.sort(cands)
			if #m ~= spec.k or table.concat(m, ",") ~= table.concat(cands, ",") then bad.k += 1 end
			for cj = ci + 1, #room.clues do
				if Clue.overlaps(c, room.clues[cj], Config) then bad.overlap += 1 end
			end
		end
		for _, p in props do
			local fits = 0
			for _, c in room.clues do
				if Clue.matches(p, c, Config) then fits += 1 end
			end
			if fits > 1 then bad.disjoint += 1 end
		end
		-- geometry: inside the room, clear of the door, on the surface of its height band
		local floors = {}
		for _, p in props do
			local hw = spec.W / 2
			if p.x < -hw or p.x > hw or p.z < 0 or p.z > spec.D then bad.bounds += 1 end
			if math.sqrt(p.x * p.x + p.z * p.z) < R.DoorClear then bad.door += 1 end
			if p.height == "floor" then
				if p.y ~= 0 then bad.surface += 1 end
				if p.x < -hw + R.Margin or p.x > hw - R.Margin or p.z < R.Margin or p.z > spec.D - R.Margin then bad.bounds += 1 end
				for _, t in room.tables do
					if inRect(p.x, p.z, t.x, t.z, R.TableSize[1] / 2 + R.TableClear, R.TableSize[2] / 2 + R.TableClear) then bad.tableClear += 1 end
				end
				table.insert(floors, p)
				-- a floor prop (about 2 studs across) never reaches into a corner square kept for decor
				local cc = R.CornerClear + 1
				if math.abs(p.x) > spec.W / 2 - cc and (p.z < cc or p.z > spec.D - cc) then bad.corner += 1 end
			elseif p.height == "table" then
				if p.y ~= R.TableTop then bad.surface += 1 end
				local on = false
				for _, t in room.tables do
					if inRect(p.x, p.z, t.x, t.z, R.TableSize[1] / 2, R.TableSize[2] / 2) then on = true end
				end
				if not on then bad.surface += 1 end
			else
				if p.y ~= R.ShelfY then bad.surface += 1 end
				local nearWall = math.abs(p.x + hw) <= R.ShelfOff + 0.01 or math.abs(p.x - hw) <= R.ShelfOff + 0.01
					or math.abs(p.z) <= R.ShelfOff + 0.01 or math.abs(p.z - spec.D) <= R.ShelfOff + 0.01
				if not nearWall then bad.shelfWall += 1 end
			end
		end
		for i = 1, #floors do
			for j = i + 1, #floors do
				local a, b = floors[i], floors[j]
				if math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) < R.Spacing - 1e-9 then bad.spacing += 1 end
			end
		end
		-- tables stay inside, clear of the door, of the corner squares and of each other
		for i, t in room.tables do
			local tx0, tx1 = math.abs(t.x) - R.TableSize[1] / 2, math.abs(t.x) + R.TableSize[1] / 2
			local tz0, tz1 = t.z - R.TableSize[2] / 2, t.z + R.TableSize[2] / 2
			if tx1 > spec.W / 2 - R.CornerClear - 0.5 and (tz0 < R.CornerClear + 0.5 or tz1 > spec.D - R.CornerClear - 0.5) then bad.corner += 1 end
			if math.abs(t.x) > spec.W / 2 - R.TableSize[1] / 2 - 1 or t.z < R.DoorClear or t.z > spec.D - R.TableSize[2] / 2 - 1 then bad.bounds += 1 end
			for j = i + 1, #room.tables do
				local u = room.tables[j]
				if math.abs(t.x - u.x) < R.TableGapX and math.abs(t.z - u.z) < R.TableGapZ then bad.tableClear += 1 end
			end
		end
		-- every prop can be reached: some floor spot inside the room, off every table, within Reach - 1
		for _, p in props do
			local ok = false
			for gx = -spec.W / 2 + 1, spec.W / 2 - 1, 2 do
				for gz = 1, spec.D - 1, 2 do
					local free = true
					for _, t in room.tables do
						if inRect(gx, gz, t.x, t.z, R.TableSize[1] / 2 + 0.5, R.TableSize[2] / 2 + 0.5) then free = false end
					end
					if free and math.sqrt((gx - p.x) ^ 2 + (gz - p.z) ^ 2) <= Config.Search.Reach - 1 then ok = true break end
				end
				if ok then break end
			end
			if not ok then bad.reach += 1 end
		end
		for _, p in props do
			if room.role[p.id] ~= "cand" then
				fill += 1
				if room.role[p.id] == "partial" then partial += 1 end
			end
		end
	end
	local name = if spec.kind == "daily" then "daily" else "ch" .. spec.chapter
	for what, n in bad do
		eq(n, 0, name .. ": " .. what .. " violations over " .. ROOMS .. " rooms")
	end
	partialShare[si] = partial / math.max(1, fill)
end
print(string.format("  generator: %d rooms, attempts mean %.3f, max %d", rooms, sumAttempts / rooms, worstAttempts))
truthy(worstAttempts <= 20, "the generator never needs more than 20 restarts (" .. worstAttempts .. ")")
do
	local line = {}
	for si, s in partialShare do table.insert(line, string.format("%.2f", s)) end
	print("  partial-match share of fillers, ch1..15 + daily: " .. table.concat(line, " "))
	-- chapters whose forms are all two-trait reach rho; chapter 1/2 mix in K clues (no partials for those)
	for si = 3, 16 do
		local rho = specs[si].rho
		truthy(math.abs(partialShare[si] - rho) <= 0.05, string.format("%s: partial share %.2f within 0.05 of rho %.2f",
			if si == 16 then "daily" else "ch" .. si, partialShare[si], rho))
	end
end

--============================================================ ids and positions say nothing about a role
do
	-- over many chapter-8 rooms: P(the prop with id 1 is a candidate) = n*k/S, and the mean id of candidates equals
	-- the mean id of everything (a generation-order leak would put candidates first)
	local spec = specs[8]
	local rand = randOf(77)
	local N = 2000
	local firstIsCand, candIdSum, candCount = 0, 0, 0
	local nearSame, nearAll = 0, 0
	for _ = 1, N do
		local room = Dressing.build(spec, rand, Config)
		if room.role[room.idBase + 1] == "cand" then firstIsCand += 1 end
		for _, p in room.props do
			if room.role[p.id] == "cand" then
				candIdSum += p.id - room.idBase
				candCount += 1
			end
		end
	end
	local pExp = spec.n * spec.k / spec.S
	local sd = math.sqrt(N * pExp * (1 - pExp))
	truthy(math.abs(firstIsCand - N * pExp) <= 4.9 * sd,
		string.format("id 1 is a candidate %d times in %d, expected %.0f +- %.0f (4.9 sd)", firstIsCand, N, N * pExp, 4.9 * sd))
	local meanCand = candIdSum / candCount
	local meanAll = (spec.S + 1) / 2
	-- a uniform deal gives the candidates' mean id sd about sqrt((S^2-1)/12 / (N*n*k))
	local sdMean = math.sqrt((spec.S ^ 2 - 1) / 12 / candCount)
	truthy(math.abs(meanCand - meanAll) <= 4.9 * sdMean,
		string.format("candidates' mean id %.2f vs %.2f (4.9 sd = %.2f)", meanCand, meanAll, 4.9 * sdMean))
	print(string.format("  ids: id 1 a candidate %d / %d (expected %.0f); candidates' mean id %.2f vs %.2f", firstIsCand, N, N * pExp, meanCand, meanAll))
end
do
	-- within a height band, a candidate's distance from the door has the same mean as a filler's
	local spec = specs[12]
	local rand = randOf(78)
	local sums = { cand = { 0, 0 }, other = { 0, 0 } }
	local sq = { cand = 0, other = 0 }
	for _ = 1, 1000 do
		local room = Dressing.build(spec, rand, Config)
		for _, p in room.props do
			if p.height == "floor" then
				local d = math.sqrt(p.x * p.x + p.z * p.z)
				local key = if room.role[p.id] == "cand" then "cand" else "other"
				sums[key][1] += d
				sums[key][2] += 1
				sq[key] += d * d
			end
		end
	end
	local mc, mo = sums.cand[1] / sums.cand[2], sums.other[1] / sums.other[2]
	local vc = sq.cand / sums.cand[2] - mc * mc
	local vo = sq.other / sums.other[2] - mo * mo
	local se = math.sqrt(vc / sums.cand[2] + vo / sums.other[2])
	truthy(math.abs(mc - mo) <= 4.9 * se, string.format("floor props: candidates %.2f vs others %.2f studs from the door (4.9 se = %.2f)", mc, mo, 4.9 * se))
	print(string.format("  positions: candidates %.2f vs others %.2f studs from the door (floor band, ch12)", mc, mo))
end

--============================================================ chapter 1: clue 1's candidates nearest the door
do
	local spec = specs[1]
	local rand = randOf(91)
	local ok = true
	for _ = 1, 300 do
		local room = Dressing.build(spec, rand, Config)
		for _, id in room.cands[1] do
			local p = room.props[id - room.idBase]
			local d = math.sqrt(p.x * p.x + p.z * p.z)
			-- no non-clue-1 prop of the same height band is nearer the door
			for _, q in room.props do
				if q.height == p.height and room.clueOf[q.id] ~= 1 then
					if math.sqrt(q.x * q.x + q.z * q.z) < d - 1e-9 then ok = false end
				end
			end
		end
	end
	truthy(ok, "chapter 1: clue 1's candidates take their band's positions nearest the door")
end

--============================================================ determinism
do
	local a = Dressing.build(specs[9], randOf(5), Config)
	local b = Dressing.build(specs[9], randOf(5), Config)
	local same = #a.props == #b.props
	for i, p in a.props do
		local q = b.props[i]
		if p.kind ~= q.kind or p.colour ~= q.colour or p.height ~= q.height or p.x ~= q.x or p.z ~= q.z then same = false end
	end
	truthy(same, "the same draws build the same room (the server's draws are never repeatable; tests pass Rng)")
end

--============================================================ the payload: an allowlist, nothing about roles
do
	local room = Dressing.build(specs[10], randOf(11), Config)
	local items = {}
	for i = 1, specs[10].n do items[i] = "key" end
	local pl = Dressing.payload(room, items, 4, Config)
	local allowedProp = { id = true, kind = true, colour = true, height = true, x = true, y = true, z = true, yaw = true, variant = true }
	local allowedClue = { form = true, kind = true, colour = true, height = true, item = true, found = true }
	local leak = nil
	for _, p in pl.props do
		for k in p do
			if not allowedProp[k] then leak = leak or ("prop field " .. tostring(k)) end
		end
	end
	for _, c in pl.clues do
		for k in c do
			if not allowedClue[k] then leak = leak or ("clue field " .. tostring(k)) end
		end
	end
	local allowedTop = { v = true, kind = true, chapter = true, day = true, band = true, W = true, D = true, idBase = true,
		props = true, clues = true, tables = true, shelves = true, looks = true, clock = true }
	for k in pl do
		if not allowedTop[k] then leak = leak or ("top field " .. tostring(k)) end
	end
	eq(leak, nil, "the payload carries only allowlisted fields (no role, no candidate list, no clue index on a prop)")
	eq(#pl.props, specs[10].S, "every prop is in the payload")
	eq(#pl.clues, specs[10].n, "every clue is in the payload")
	-- the payload's prop order is by id (dealt after the shuffle), never generation order
	local sorted = true
	for i = 2, #pl.props do
		if pl.props[i].id <= pl.props[i - 1].id then sorted = false end
	end
	truthy(sorted, "the payload lists props in id order")
end

--============================================================ the re-dress keeps each item's count [DESIGN §9]
do
	local spec = specs[15]
	local rand = randOf(321)
	local bad = { count = 0, disjoint = 0, ids = 0, total = 0, found = 0, overlap = 0 }
	for trial = 1, 300 do
		local room = Dressing.build(spec, rand, Config)
		-- some items found (count 0), others with 1..k unsearched candidates left
		local counts = {}
		for i = 1, spec.n do
			local r = rand()
			counts[i] = if r < 0.3 then 0 else 1 + math.floor(rand() * spec.k)
		end
		local re = Dressing.redress(room, counts, rand, Config)
		if #re.props ~= spec.S then bad.total += 1 end
		if re.idBase < room.idBase + spec.S then bad.ids += 1 end
		for i = 1, spec.n do
			local m = 0
			if counts[i] > 0 then
				for _, p in re.props do
					if Clue.matches(p, re.clues[i], Config) then m += 1 end
				end
				if m ~= counts[i] or #re.cands[i] ~= counts[i] then bad.count += 1 end
			else
				if #re.cands[i] ~= 0 then bad.found += 1 end
			end
		end
		for _, p in re.props do
			local fits = 0
			for i, c in re.clues do
				if counts[i] > 0 and Clue.matches(p, c, Config) then fits += 1 end
			end
			if fits > 1 then bad.disjoint += 1 end
		end
		for i = 1, spec.n do
			for j = i + 1, spec.n do
				if counts[i] > 0 and counts[j] > 0 and Clue.overlaps(re.clues[i], re.clues[j], Config) then bad.overlap += 1 end
			end
		end
	end
	for what, n in bad do eq(n, 0, "re-dress: " .. what .. " violations over 300 re-dresses") end
end

print(string.format("Dressing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Dressing spec failed", 0) end
