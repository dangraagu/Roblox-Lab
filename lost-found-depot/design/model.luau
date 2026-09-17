--!nonstrict
-- Lost & Found Depot -- DESIGN-TIME MEASUREMENT MODEL. Not game code; nothing here ships.
--
-- Every number DESIGN.md states about rule coverage, bin shares, walking geometry, shift length,
-- throughput, the travel floor and the economy is printed by this file. Re-run it after changing
-- any constant below and re-read the numbers before touching the spec:
--
--   luau design/model.luau 2>&1        (about 90 seconds)
--
-- What this is NOT: a physics model. Walking is straight lines at exactly WalkSpeed between stand
-- points on an open floor. Decode times and error rates per player profile are ASSUMPTIONS, stated
-- in PROFILES below; the model reports what follows from them, and DESIGN.md says so wherever a
-- number rests on one. The first real play session replaces them.

--============================================================================ constants
local C = {
	Letters = { "B", "E", "K", "T" },
	LetterBin = { B = "BAGS", E = "ELECTRONICS", K = "KEYS", T = "TOYS" },
	Bins = { "BAGS", "ELECTRONICS", "KEYS", "TOYS", "REPAIR", "CLAIMS" },
	Conditions = 5,
	Routes = { "RED", "GREEN", "BLUE", "YELLOW", "PURPLE", "WHITE" },
	TornChance = 0.25,

	-- geometry (studs). The pick point P is the origin; bins sit on an arc of ArcRadius around P.
	WalkSpeed = 16,
	ArcRadius = 28,
	BinStand = 5, -- an honest player deposits standing this far short of the bin centre
	BinPromptDistance = 6,
	ItemReach = 12,
	TrayRows = 2,
	TrayCols = 4,
	TraySpacing = 4,
	TrayRowGap = 3,
	PickStandOffset = 5, -- the tray's front row is this far behind P
	SpawnBehindTray = 6, -- the spawn pad is this far behind the tray's back row

	-- actions (seconds)
	PickAction = 0.5,
	DepositAction = 0.5,
	MisfilePenalty = 8,
	ShiftSeconds = 330,

	-- server travel floor
	SpeedTolerance = 1.25,
	PositionSlack = 2,
	LatencySlack = 0.3,

	-- economy
	PayFirstTry = 10,
	ComboStep = 0.1,
	ComboCap = 10,
	PayResort = 5,
	PerfectBonus = 100,
	PerfectMaxMisfiles = 3,
}

--============================================================================ rng (the repo's LCG)
local Rng = {}
Rng.__index = Rng
local MOD = 4294967296
function Rng.new(seed: number)
	return setmetatable({ s = math.floor(seed) % MOD }, Rng)
end
function Rng:next(): number
	self.s = (1664525 * self.s + 1013904223) % MOD
	return self.s / MOD
end
function Rng:below(n: number): number
	local v = math.floor(self:next() * n) + 1
	return if v > n then n else v
end

-- murmur3 finalizer with an exact 32-bit multiply (Deep Vein's Mine.hash technique)
local function mul32(a: number, b: number): number
	local aH, aL = a // 65536, a % 65536
	local bH, bL = b // 65536, b % 65536
	return ((aH * bL + aL * bH) % 65536 * 65536 + aL * bL) % MOD
end
local function fmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end
local function seedFor(worldSeed: number, userId: number, shift: number, salt: number): number
	local h = fmix(worldSeed % MOD)
	h = fmix(bit32.bxor(h, userId % 1000003))
	h = fmix(bit32.bxor(h, shift % MOD))
	return fmix(bit32.bxor(h, salt % MOD))
end

print("== PART 0: why the shift seed is hashed ==")
do
	local sameRaw, sameHash, N = 0, 0, 20000
	local prevRaw, prevHash
	for shift = 0, N do
		local raw = Rng.new(123456 * 4096 + shift):below(4)
		local hashed = Rng.new(seedFor(20260916, 123456, shift, 987654321)):below(4)
		if prevRaw and raw == prevRaw then
			sameRaw += 1
		end
		if prevHash and hashed == prevHash then
			sameHash += 1
		end
		prevRaw, prevHash = raw, hashed
	end
	print(string.format("  first letter repeats between consecutive shifts: raw seed+1 %.1f%%, hashed %.1f%% (independent = 25.0%%)", sameRaw / N * 100, sameHash / N * 100))
	-- mul32's largest intermediate: (aH*bL + aL*bH) with every half at most 65535, plus aL*bL
	local worst = 2 * 65535 * 65535 + 65535 * 65535
	print(string.format("  mul32 largest intermediate %.0f, under 2^53 = %.0f by a factor of %.0f", worst, 2 ^ 53, 2 ^ 53 / worst))
end

--============================================================================ rules
local function baseRules()
	local lm = {}
	for k, v in C.LetterBin do
		lm[k] = v
	end
	return { claim = { RED = true }, broken = { [5] = true }, letterMap = lm, name = "base", family = "base" }
end

-- tag = { letter, cond, route, torn = nil|"letter"|"cond"|"route" }, look = the item's true category letter
local function resolve(tag, look: string, rules): (string, string)
	if tag.torn ~= "route" and rules.claim[tag.route] then
		return "CLAIMS", "route"
	end
	if tag.torn == "cond" then
		return "REPAIR", "torn-cond"
	end
	if rules.broken[tag.cond] then
		return "REPAIR", "cond"
	end
	if tag.torn == "letter" then
		return rules.letterMap[look], "torn-letter"
	end
	return rules.letterMap[tag.letter], "letter"
end

local function memos()
	local list = {}
	for _, col in C.Routes do
		if col ~= "RED" then
			local r = baseRules()
			r.claim[col] = true
			r.name, r.family = "EXTRA_CLAIM " .. col, "EXTRA_CLAIM"
			table.insert(list, r)
		end
	end
	local r4 = baseRules()
	r4.broken[4] = true
	r4.name, r4.family = "EXTRA_BROKEN 4", "EXTRA_BROKEN"
	table.insert(list, r4)
	for i = 1, 4 do
		for j = i + 1, 4 do
			local r = baseRules()
			local a, b = C.Letters[i], C.Letters[j]
			r.letterMap[a], r.letterMap[b] = r.letterMap[b], r.letterMap[a]
			r.name, r.family = "SWAP " .. a .. "/" .. b, "SWAP"
			table.insert(list, r)
		end
	end
	return list
end

--============================================================================ part 1: exact shares
local function enumerate(rules, tornChance: number, fn)
	local tornStates = { { nil, 1 - tornChance }, { "letter", tornChance / 3 }, { "cond", tornChance / 3 }, { "route", tornChance / 3 } }
	local pl, pc, pr = 1 / #C.Letters, 1 / C.Conditions, 1 / #C.Routes
	for _, letter in C.Letters do
		for cond = 1, C.Conditions do
			for _, route in C.Routes do
				for _, ts in tornStates do
					for _, look in C.Letters do
						local p = pl * pc * pr * ts[2] * pl
						if p > 0 then
							fn({ letter = letter, cond = cond, route = route, torn = ts[1] }, look, p)
						end
					end
				end
			end
		end
	end
end

local function pct(x: number): string
	return string.format("%5.1f%%", x * 100)
end

print("\n== PART 1: bin shares and rule coverage (exact enumeration) ==")
local function sharesFor(rules, torn: number, label: string)
	local share, deciding = {}, {}
	local lookOnly, letterOnly, noMemo = 0, 0, 0
	local base = baseRules()
	enumerate(rules, torn, function(tag, look, p)
		local bin, why = resolve(tag, look, rules)
		share[bin] = (share[bin] or 0) + p
		deciding[why] = (deciding[why] or 0) + p
		if rules.letterMap[look] == bin then
			lookOnly += p -- sorts by what the item looks like, ignoring the tag
		end
		local l = if tag.torn == "letter" then look else tag.letter
		if rules.letterMap[l] == bin then
			letterOnly += p -- reads only the letter
		end
		if resolve(tag, look, base) == bin then
			noMemo += p -- applies the manual perfectly, ignores the memo
		end
	end)
	local parts = {}
	for _, b in C.Bins do
		table.insert(parts, b .. " " .. pct(share[b] or 0))
	end
	print(string.format("  [%s] %s", label, table.concat(parts, "  ")))
	print(
		string.format(
			"      decided by: route %s  cond %s  torn-cond %s  letter %s  torn-letter %s",
			pct(deciding["route"] or 0),
			pct(deciding["cond"] or 0),
			pct(deciding["torn-cond"] or 0),
			pct(deciding["letter"] or 0),
			pct(deciding["torn-letter"] or 0)
		)
	)
	print(string.format("      correct if you sort by LOOK: %s   by LETTER only: %s   ignoring the memo: %s", pct(lookOnly), pct(letterOnly), pct(noMemo)))
end

sharesFor(baseRules(), 0, "stage 1: base rules, no torn tags")
sharesFor(baseRules(), C.TornChance, "stage 2: + torn tags")
local seenFamily = {}
for _, m in memos() do
	if not seenFamily[m.family] then
		seenFamily[m.family] = true
		sharesFor(m, C.TornChance, "stage 3: " .. m.name .. " (every " .. m.family .. " memo measures the same)")
	end
end
do
	local unresolved, checked = 0, 0
	local all = { baseRules() }
	for _, m in memos() do
		table.insert(all, m)
	end
	for _, r in all do
		enumerate(r, C.TornChance, function(tag, look, _p)
			checked += 1
			local bin = resolve(tag, look, r)
			if not table.find(C.Bins, bin) then
				unresolved += 1
			end
		end)
	end
	print(string.format("  %d memos; %d (tag, look, rule set) combinations checked, %d resolve to no bin", #memos(), checked, unresolved))
end
do
	-- How often each clause actually decides something in a 30-item shift, at stage 2 base rules.
	local items = 30
	for _, tc in { 0.15, 0.25, 0.35 } do
		local dec = {}
		enumerate(baseRules(), tc, function(tag, look, p)
			local _, why = resolve(tag, look, baseRules())
			dec[why] = (dec[why] or 0) + p
		end)
		local function atLeastOne(q)
			return 1 - (1 - q) ^ items
		end
		print(
			string.format(
				"  TornChance %.2f, %d items: torn-cond decides %.2f items (>=1 in %s of shifts), torn-letter %.2f (>=1 in %s)",
				tc,
				items,
				dec["torn-cond"] * items,
				pct(atLeastOne(dec["torn-cond"])),
				dec["torn-letter"] * items,
				pct(atLeastOne(dec["torn-letter"]))
			)
		)
	end
	local lo, hi = math.huge, 0
	for _, m in memos() do
		local changed = 0
		enumerate(m, C.TornChance, function(tag, look, p)
			if resolve(tag, look, baseRules()) ~= resolve(tag, look, m) then
				changed += p
			end
		end)
		lo, hi = math.min(lo, changed * items), math.max(hi, changed * items)
	end
	print(string.format("  a memo changes the answer for %.1f .. %.1f of %d items", lo, hi, items))
end

--============================================================================ part 2: geometry
print("\n== PART 2: bay geometry ==")
local angles = {}
for i = 1, 6 do
	angles[i] = math.rad(15 + 30 * (i - 1))
end
local function binCentre(slot: number)
	return C.ArcRadius * math.cos(angles[slot]), C.ArcRadius * math.sin(angles[slot])
end
local function dist(ax, ay, bx, by)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
local chordCentres = 2 * C.ArcRadius * math.sin(math.rad(15))
local standR = C.ArcRadius - C.BinStand
local chordStand = 2 * standR * math.sin(math.rad(15))
print(string.format("  adjacent bin centres %.2f studs apart; two prompt radii %.1f -> clear gap %.2f", chordCentres, 2 * C.BinPromptDistance, chordCentres - 2 * C.BinPromptDistance))
print(string.format("  P -> any bin stand point %.1f studs (%.2f s at %d); adjacent stand points %.2f studs (%.2f s)", standR, standR / C.WalkSpeed, C.WalkSpeed, chordStand, chordStand / C.WalkSpeed))
local slots = {}
for row = 1, C.TrayRows do
	for col = 1, C.TrayCols do
		table.insert(slots, { x = (col - (C.TrayCols + 1) / 2) * C.TraySpacing, y = -C.PickStandOffset - (row - 1) * C.TrayRowGap })
	end
end
local farP, farSpawn = 0, 0
local spawnY = -C.PickStandOffset - (C.TrayRows - 1) * C.TrayRowGap - C.SpawnBehindTray
for _, s in slots do
	farP = math.max(farP, dist(0, 0, s.x, s.y))
	farSpawn = math.max(farSpawn, dist(0, spawnY, s.x, s.y))
end
print(string.format("  farthest tray slot: %.2f studs from P, %.2f from the spawn pad centre (ItemReach %d)", farP, farSpawn, C.ItemReach))
local nearest = math.huge
for i = 1, 6 do
	local bx, by = binCentre(i)
	for _, s in slots do
		nearest = math.min(nearest, dist(bx, by, s.x, s.y))
	end
end
print(string.format("  nearest bin centre to any tray slot %.2f studs; ItemReach + prompt %d -> at least %.2f studs of walking between a pick and a deposit", nearest, C.ItemReach + C.BinPromptDistance, nearest - C.ItemReach - C.BinPromptDistance))

--============================================================================ part 3: shift simulation
local function makeShift(rng, n: number, torn: number, rules)
	local items = {}
	for i = 1, n do
		local tag = { letter = C.Letters[rng:below(4)], cond = rng:below(C.Conditions), route = C.Routes[rng:below(#C.Routes)], torn = nil }
		if rng:next() < torn then
			-- a torn part does not exist, on the server either: there is no hidden value to leak
			tag.torn = ({ "letter", "cond", "route" })[rng:below(3)]
			tag[tag.torn] = nil
		end
		local look = C.Letters[rng:below(4)]
		items[i] = { tag = tag, look = look, bin = (resolve(tag, look, rules)), known = false, read = false }
	end
	local perm = { 1, 2, 3, 4, 5, 6 }
	for i = 6, 2, -1 do
		local j = rng:below(i)
		perm[i], perm[j] = perm[j], perm[i]
	end
	local slotOf = {}
	for i, b in C.Bins do
		slotOf[b] = perm[i]
	end
	return items, slotOf
end

-- THE TRAVEL LEDGER (evaluated for DESIGN.md and NOT shipped in v1). From the first accepted interaction, every
-- accepted interaction adds  max(0, |p - pPrev| - PositionSlack) / (WalkSpeed * SpeedTolerance)
-- seconds to `required`, where p is the server-observed root-part position. An interaction is accepted
-- when  elapsed + LatencySlack >= required.  The latency slack is granted ONCE per ledger, not per
-- leg: an earlier draft subtracted it per leg, and this model measured a bot clearing 30 items in
-- 4.3 seconds through it, because on short legs the per-leg slack is bigger than the leg.
local function newLedger()
	return { t0 = nil :: number?, required = 0, x = 0, y = 0 }
end
-- returns accepted(boolean), and the time at which it WOULD be accepted
local function ledgerCheck(L, now: number, x: number, y: number, speed: number): (boolean, number)
	if L.t0 == nil then
		return true, now
	end
	local d = dist(L.x, L.y, x, y)
	local req = L.required + math.max(0, d - C.PositionSlack) / (speed * C.SpeedTolerance)
	local okAt = (L.t0 :: number) + req - C.LatencySlack
	return now >= okAt, okAt
end
local function ledgerCommit(L, now: number, x: number, y: number, speed: number)
	if L.t0 == nil then
		L.t0 = now
	else
		L.required += math.max(0, dist(L.x, L.y, x, y) - C.PositionSlack) / (speed * C.SpeedTolerance)
	end
	L.x, L.y = x, y
end

-- noise = { pos = studs, time = seconds }: how wrong the SERVER's view of an honest player is.
-- Position error is uniform in a disc; latency is uniform in [0, time] (it only ever delays).
local function simulate(profile, rng, n: number, torn: number, rules, memoActive: boolean, limit: number?, noise)
	local items, slotOf = makeShift(rng, n, torn, rules)
	local cart = table.clone(items)
	local tray = {}
	local traySize = C.TrayRows * C.TrayCols
	local function refill()
		while #tray < traySize and #cart > 0 do
			table.insert(tray, table.remove(cart, 1))
		end
	end
	refill()
	local bot = profile.floorBot == true
	local pickX, pickY = 0, 0
	local depositR = C.ArcRadius - C.BinStand
	if bot then
		-- as far toward the bins as reach + position slack allows, at both ends
		pickY = (C.ItemReach + C.PositionSlack) - farP
		depositR = C.ArcRadius - (C.BinPromptDistance + C.PositionSlack)
	end
	local function standPoint(slot)
		return depositR * math.cos(angles[slot]), depositR * math.sin(angles[slot])
	end
	local function routeLen(set): number
		local list = {}
		for s in set do
			table.insert(list, s)
		end
		table.sort(list)
		local px, py, len = pickX, pickY, 0
		for _, s in list do
			local x, y = standPoint(s)
			len += dist(px, py, x, y)
			px, py = x, y
		end
		return len + dist(px, py, pickX, pickY)
	end

	local clock, sorted, misfiles, firstTry, combo, pay, refused = 0, 0, 0, 0, 0, 0, 0
	local ledger = newLedger()
	local function walk(ax, ay, bx, by)
		if not bot then
			clock += dist(ax, ay, bx, by) / profile.speed
		end
	end
	-- an interaction at (x, y). A bot waits for the ledger; an honest player is checked against it.
	local function interact(x: number, y: number)
		local ox, oy, lag = x, y, 0
		if noise and not bot then
			local a, r = rng:next() * 2 * math.pi, math.sqrt(rng:next()) * noise.pos
			ox, oy = x + r * math.cos(a), y + r * math.sin(a)
			lag = rng:next() * noise.time
		end
		local seen = clock + lag
		local ok, okAt = ledgerCheck(ledger, seen, ox, oy, profile.speed)
		if not ok then
			if bot then
				clock = okAt
				seen = okAt
			else
				refused += 1
				-- the honest player presses again; count it and let it through when time allows
				clock = math.max(clock, okAt)
				seen = okAt
			end
		end
		ledgerCommit(ledger, seen, ox, oy, profile.speed)
	end
	local function decodeCost(it)
		if bot or it.known or it.read then
			return 0
		end
		it.read = true
		local d = profile.decode
		if it.tag.torn then
			d += profile.tornExtra
		end
		if memoActive then
			d += profile.memoExtra
		end
		return d
	end
	local pickAction = if bot then 0 else C.PickAction
	local depositAction = if bot then 0 else C.DepositAction

	while sorted < n and not (limit and clock >= limit) do
		local k = math.min(profile.cap, #tray)
		local pick = {}
		if profile.plan and #tray > k then
			for _, it in tray do
				clock += decodeCost(it)
			end
			local best, bestCost = nil, math.huge
			local chosen = {}
			local function rec(start)
				if #chosen == k then
					local set = {}
					for _, idx in chosen do
						set[slotOf[tray[idx].bin]] = true
					end
					local cost = routeLen(set) / k
					if cost < bestCost then
						bestCost, best = cost, table.clone(chosen)
					end
					return
				end
				for i = start, #tray do
					table.insert(chosen, i)
					rec(i + 1)
					table.remove(chosen)
				end
			end
			rec(1)
			pick = best :: any
		else
			for i = 1, k do
				pick[i] = i
				clock += decodeCost(tray[i])
			end
		end
		table.sort(pick, function(a, b)
			return a > b
		end)
		local carried = {}
		for _, idx in pick do
			table.insert(carried, table.remove(tray, idx))
			clock += pickAction
			interact(pickX, pickY)
		end
		refill()
		local stops = {}
		for _, it in carried do
			local target = it.bin
			if not it.known and rng:next() < profile.err then
				local others = {}
				for _, b in C.Bins do
					if b ~= it.bin then
						table.insert(others, b)
					end
				end
				target = others[rng:below(5)]
			end
			local s = slotOf[target]
			stops[s] = stops[s] or {}
			table.insert(stops[s], { it = it, target = target })
		end
		local order = {}
		for s in stops do
			table.insert(order, s)
		end
		table.sort(order)
		local px, py = pickX, pickY
		for _, s in order do
			local x, y = standPoint(s)
			walk(px, py, x, y)
			px, py = x, y
			for _, d in stops[s] do
				clock += depositAction
				interact(x, y)
				if d.target == d.it.bin then
					sorted += 1
					if d.it.known then
						pay += C.PayResort
					else
						combo += 1
						pay += C.PayFirstTry * (1 + C.ComboStep * math.min(combo, C.ComboCap))
						firstTry += 1
					end
				else
					misfiles += 1
					combo = 0
					clock += C.MisfilePenalty
					d.it.known = true
					table.insert(tray, d.it)
					if #tray > traySize then
						table.insert(cart, 1, table.remove(tray))
					end
				end
			end
		end
		walk(px, py, pickX, pickY)
	end
	local cleared = sorted == n and (not limit or clock <= limit)
	local perfect = cleared and misfiles <= C.PerfectMaxMisfiles
	if perfect then
		pay += C.PerfectBonus
	end
	return { clock = clock, sorted = sorted, misfiles = misfiles, pay = math.floor(pay), firstTry = firstTry, cleared = cleared, perfect = perfect, refused = refused }
end

local PROFILES = {
	-- ASSUMPTIONS, not measurements. decode = seconds to read one tag and decide; tornExtra / memoExtra
	-- are added when the tag is torn / a memo is active. err = chance a first attempt goes to a wrong bin.
	["first-timer"] = { decode = 3.0, tornExtra = 1.0, memoExtra = 1.0, err = 0.20, cap = 2, speed = 16, plan = false },
	["regular"] = { decode = 1.5, tornExtra = 0.5, memoExtra = 0.5, err = 0.08, cap = 2, speed = 16, plan = false },
	["regular+kit"] = { decode = 1.5, tornExtra = 0.5, memoExtra = 0.5, err = 0.08, cap = 5, speed = 22, plan = false },
	["expert+kit"] = { decode = 0.8, tornExtra = 0.3, memoExtra = 0.3, err = 0.02, cap = 5, speed = 22, plan = true },
	["guesser"] = { decode = 0.0, tornExtra = 0.0, memoExtra = 0.0, err = 5 / 6, cap = 2, speed = 16, plan = false },
	["bot@floor+kit"] = { decode = 0.0, tornExtra = 0.0, memoExtra = 0.0, err = 0.0, cap = 5, speed = 22, plan = true, floorBot = true },
}
local ORDER = { "first-timer", "regular", "regular+kit", "expert+kit", "guesser", "bot@floor+kit" }

local function quant(list, q)
	local s = table.clone(list)
	table.sort(s)
	return s[math.max(1, math.floor(#s * q + 0.5))]
end

local SEEDS = 2000
local MEMOS = memos()
-- stage 1 = base rules, no torn tags; stage 2 = + torn tags; stage 3 = + a memo
local function run(name: string, n: number, stage: number, limit: number?, noise)
	local p = PROFILES[name]
	local out = { clock = {}, pay = {}, misfiles = {}, sorted = {}, firstTry = {}, cleared = 0, perfect = 0, refused = 0, refusedShifts = 0 }
	for seed = 1, SEEDS do
		local rng = Rng.new(seedFor(20260916, 777, seed, 1))
		local rules = if stage >= 3 then MEMOS[rng:below(#MEMOS)] else baseRules()
		local torn = if stage >= 2 then C.TornChance else 0
		local r = simulate(p, rng, n, torn, rules, stage >= 3, limit, noise)
		table.insert(out.clock, r.clock)
		table.insert(out.pay, r.pay)
		table.insert(out.misfiles, r.misfiles)
		table.insert(out.sorted, r.sorted)
		table.insert(out.firstTry, r.firstTry)
		out.cleared += if r.cleared then 1 else 0
		out.perfect += if r.perfect then 1 else 0
		out.refused += r.refused
		out.refusedShifts += if r.refused > 0 then 1 else 0
	end
	return out
end

print("\n== PART 3: seconds to clear a whole shift, no clock (median / p90), 2000 seeds, penalty " .. C.MisfilePenalty .. " s ==")
for _, n in { 20, 30, 40 } do
	print(string.format("  --- %d items ---", n))
	for _, name in ORDER do
		local s1, s3 = run(name, n, 1), run(name, n, 3)
		print(
			string.format(
				"  %-14s stage1 %6.1f / %6.1f   stage3 %6.1f / %6.1f   stage3 misfiles p50 %d p90 %d",
				name,
				quant(s1.clock, 0.5),
				quant(s1.clock, 0.9),
				quant(s3.clock, 0.5),
				quant(s3.clock, 0.9),
				quant(s3.misfiles, 0.5),
				quant(s3.misfiles, 0.9)
			)
		)
	end
end

print("\n== PART 4: planning gain vs visible tray size (expert+kit, 30 items, stage 3, median s) ==")
for _, cols in { 2, 3, 4, 6 } do
	C.TrayCols = cols
	print(string.format("  tray %2d slots: %.1f s", C.TrayRows * cols, quant(run("expert+kit", 30, 3).clock, 0.5)))
end
C.TrayCols = 4

print("\n== PART 5: the misfile penalty -- does reading beat guessing for a SLOW reader? (30 items, no clock, median s) ==")
do
	local keep = C.MisfilePenalty
	for _, pen in { 5, 8, 10 } do
		C.MisfilePenalty = pen
		local ft1, gu1 = run("first-timer", 30, 1), run("guesser", 30, 1)
		local ft3, gu3 = run("first-timer", 30, 3), run("guesser", 30, 3)
		print(
			string.format(
				"  penalty %2d s: stage1 first-timer %.1f vs guesser %.1f (guess/read %.2f) | stage3 %.1f vs %.1f (%.2f)",
				pen,
				quant(ft1.clock, 0.5),
				quant(gu1.clock, 0.5),
				quant(gu1.clock, 0.5) / quant(ft1.clock, 0.5),
				quant(ft3.clock, 0.5),
				quant(gu3.clock, 0.5),
				quant(gu3.clock, 0.5) / quant(ft3.clock, 0.5)
			)
		)
	end
	C.MisfilePenalty = keep
end

print("\n== PART 6: the shift clock (30 items, penalty " .. C.MisfilePenalty .. " s): cleared / PERFECT (cleared with <= " .. C.PerfectMaxMisfiles .. " misfiles) ==")
for _, limit in { 270, 300, 330, 360 } do
	local line = {}
	for _, name in { "first-timer", "regular", "guesser" } do
		local s1, s2, s3 = run(name, 30, 1, limit), run(name, 30, 2, limit), run(name, 30, 3, limit)
		table.insert(line, string.format("%s s1 %s/%s s2 %s s3 %s/%s", name, pct(s1.cleared / SEEDS), pct(s1.perfect / SEEDS), pct(s2.cleared / SEEDS), pct(s3.cleared / SEEDS), pct(s3.perfect / SEEDS)))
	end
	print(string.format("  %d s: %s", limit, table.concat(line, " | ")))
end

print("\n== PART 7: the server travel ledger ==")
do
	local e, b = run("expert+kit", 30, 3), run("bot@floor+kit", 30, 3)
	print(string.format("  30 items, stage 3, median: expert+kit %.1f s | a bot held to the ledger %.1f s (p10 %.1f, p90 %.1f) | a teleporting bot with no ledger: 0 s", quant(e.clock, 0.5), quant(b.clock, 0.5), quant(b.clock, 0.1), quant(b.clock, 0.9)))
	for _, tol in { 1.0, 1.1, 1.25 } do
		C.SpeedTolerance = tol
		local line = {}
		for _, nz in { { pos = 1, time = 0.3 }, { pos = 2, time = 0.6 }, { pos = 4, time = 1.2 } } do
			local worst = 0
			local worstShifts = 0
			for _, name in { "first-timer", "regular", "regular+kit", "expert+kit" } do
				local r = run(name, 30, 3, nil, nz)
				worst += r.refused
				worstShifts = math.max(worstShifts, r.refusedShifts)
			end
			table.insert(line, string.format("noise pos %d time %.1f: %d refusals, worst profile %d of %d shifts", nz.pos, nz.time, worst, worstShifts, SEEDS))
		end
		local bb = run("bot@floor+kit", 30, 3)
		print(string.format("  tolerance %.2f: bot %.1f s | honest players, 4 profiles x %d shifts: %s", tol, quant(bb.clock, 0.5), SEEDS, table.concat(line, "; ")))
	end
	C.SpeedTolerance = 1.25
end

print("\n== PART 8: economy per shift (30 items, " .. C.ShiftSeconds .. " s clock) ==")
for _, name in { "first-timer", "regular", "regular+kit", "expert+kit", "guesser" } do
	local s1, s3 = run(name, 30, 1, C.ShiftSeconds), run(name, 30, 3, C.ShiftSeconds)
	print(
		string.format(
			"  %-12s stage1 pay p50 %d p10 %d | stage3 pay p50 %d p10 %d, first-try sorts p50 %d, shift length p50 %.0f s",
			name,
			quant(s1.pay, 0.5),
			quant(s1.pay, 0.1),
			quant(s3.pay, 0.5),
			quant(s3.pay, 0.1),
			quant(s3.firstTry, 0.5),
			math.min(C.ShiftSeconds, quant(s3.clock, 0.5))
		)
	)
end
do
	local total = 0
	for c = 1, 30 do
		total += C.PayFirstTry * (1 + C.ComboStep * math.min(c, C.ComboCap))
	end
	print(string.format("  max possible pay in one shift: %d (%d from sorts + %d perfect bonus)", math.floor(total + C.PerfectBonus), math.floor(total), C.PerfectBonus))
end

print("\n== PART 9: a career, shift by shift (30 items, " .. C.ShiftSeconds .. " s clock, stage by shift number) ==")
-- A player who never improves, starts with no kit, and buys the cheapest next upgrade the moment
-- they can afford it. Carry 2 -> 3 -> 4 -> 5 and walk speed 16 -> 18 -> 20 -> 22.
local INTERMISSION = 4
local function career(base, label: string, prices, backlogSize: number)
	local cash, carryLv, speedLv, backlog, minutes = 0, 0, 0, 0, 0
	local allKit, ending
	local purchases = {}
	for shift = 1, 80 do
		local p = table.clone(base)
		p.cap = 2 + carryLv
		p.speed = 16 + 2 * speedLv
		PROFILES["_career"] = p
		local stage = if shift == 1 then 1 elseif shift == 2 then 2 else 3
		local r = run("_career", 30, stage, C.ShiftSeconds)
		local len = math.min(C.ShiftSeconds, quant(r.clock, 0.5))
		cash += quant(r.pay, 0.5)
		backlog += quant(r.firstTry, 0.5)
		minutes += (len + INTERMISSION) / 60
		while true do
			local nc = if carryLv < 3 then prices[carryLv + 1] else math.huge
			local ns = if speedLv < 3 then prices[speedLv + 1] else math.huge
			local price = math.min(nc, ns)
			if price == math.huge or cash < price then
				break
			end
			cash -= price
			if nc <= ns then
				carryLv += 1
				table.insert(purchases, string.format("carry%d@%d", carryLv, shift))
			else
				speedLv += 1
				table.insert(purchases, string.format("speed%d@%d", speedLv, shift))
			end
		end
		if carryLv == 3 and speedLv == 3 and not allKit then
			allKit = { shift, minutes }
		end
		if backlog >= backlogSize and not ending then
			ending = { shift, minutes }
		end
		if allKit and ending then
			break
		end
	end
	print(
		string.format(
			"  %-12s prices %s: %s | full kit after shift %s (%.0f min) | backlog %d cleared after shift %s (%.0f min)",
			label,
			table.concat(prices, "/"),
			table.concat(purchases, " "),
			allKit and tostring(allKit[1]) or ">80",
			allKit and allKit[2] or 0,
			backlogSize,
			ending and tostring(ending[1]) or ">80",
			ending and ending[2] or 0
		)
	)
end
for _, prices in { { 250, 600, 1400 }, { 250, 800, 2000 } } do
	career(PROFILES["regular"], "regular", prices, 500)
	career(PROFILES["first-timer"], "first-timer", prices, 500)
	career(PROFILES["guesser"], "guesser", prices, 500)
end

print("\n== PART 10: tag text contrast (WCAG 2 relative luminance; AA for normal text is 4.5:1) ==")
do
	local function lin(c: number): number
		c = c / 255
		return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	local function lum(rgb): number
		return 0.2126 * lin(rgb[1]) + 0.7152 * lin(rgb[2]) + 0.0722 * lin(rgb[3])
	end
	local function ratio(a, b): number
		local x, y = lum(a), lum(b)
		if x < y then
			x, y = y, x
		end
		return (x + 0.05) / (y + 0.05)
	end
	local TAG = { 34, 36, 42 }
	local COLOURS = {
		{ "RED", { 255, 90, 90 } },
		{ "GREEN", { 80, 220, 110 } },
		{ "BLUE", { 110, 170, 255 } },
		{ "YELLOW", { 255, 215, 60 } },
		{ "PURPLE", { 200, 130, 255 } },
		{ "WHITE", { 245, 245, 245 } },
		{ "text", { 245, 245, 245 } },
		{ "torn ?", { 150, 150, 160 } },
	}
	local worst = math.huge
	for _, c in COLOURS do
		local r = ratio(c[2], TAG)
		worst = math.min(worst, r)
		print(string.format("  %-7s (%d,%d,%d) on the tag (34,36,42): %.2f:1", c[1], c[2][1], c[2][2], c[2][3], r))
	end
	print(string.format("  worst %.2f:1", worst))
end
