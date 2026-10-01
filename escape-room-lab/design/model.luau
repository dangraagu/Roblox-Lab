--!nonstrict
-- Escape Room Lab -- DESIGN-TIME MEASUREMENT MODEL. Not game code; nothing here ships.
--
-- Every number DESIGN.md tags [M n] is printed by Part n of this file. Re-run it after changing any
-- constant below and re-read the numbers before touching the spec:
--
--   luau design/model.luau 2>&1
--
-- What this is: the three puzzle generators DESIGN.md specifies (Code Lock, Flask Shelf, Lamp Grid),
-- written the simplest correct way, run thousands of times to measure what they produce; then a
-- pacing model that walks simulated players through the 15 rooms using those generated rooms.
--
-- What this is NOT: a model of real humans. Reading, thinking and error rates per profile are
-- ASSUMPTIONS, stated in PROFILES below. The model reports what follows from them; DESIGN.md tags every
-- number that rests on one. The first real play session replaces them.
--
-- The generators here are the SPEC for src/shared/{CodeLock,Shelf,Lamps}.luau, not their source: the
-- build writes those modules test-first against DESIGN.md, and may copy from here.

--============================================================================ rng (the repo's LCG)
local Rng = {}
Rng.__index = Rng
local MOD = 4294967296
function Rng.new(seed)
	local s = math.floor(seed) % MOD
	if s < 0 then s += MOD end
	return setmetatable({ state = s }, Rng)
end
function Rng:next()
	self.state = (1664525 * self.state + 1013904223) % MOD
	return self.state / MOD
end
-- 1..n from the HIGH bits (docs/new-game-checklist.md "LCG low bits")
function Rng:below(n)
	local v = math.floor(self:next() * n) + 1
	if v > n then v = n end
	return v
end

local function shuffle(rng, t)
	for i = #t, 2, -1 do
		local j = rng:below(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function quantiles(xs)
	local s = table.clone(xs)
	table.sort(s)
	local n = #s
	local function q(p)
		return s[math.clamp(math.floor(p * (n - 1) + 0.5) + 1, 1, n)]
	end
	local sum = 0
	for _, v in s do sum += v end
	return { min = s[1], p10 = q(0.10), p50 = q(0.50), p90 = q(0.90), max = s[n], mean = sum / n }
end

local function fmtQ(q, dp)
	local f = "%." .. (dp or 0) .. "f"
	return string.format("min " .. f .. " / p10 " .. f .. " / p50 " .. f .. " / p90 " .. f .. " / max " .. f .. " (mean %.2f)",
		q.min, q.p10, q.p50, q.p90, q.max, q.mean)
end

local function hist(xs)
	local h, keys = {}, {}
	for _, v in xs do
		if h[v] == nil then h[v] = 0; table.insert(keys, v) end
		h[v] += 1
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in keys do table.insert(parts, tostring(k) .. ":" .. h[k]) end
	return table.concat(parts, "  ")
end

--============================================================================ Code Lock
-- A code of L DISTINCT digits drawn from `alphabet`. A clue line is a guess (also L distinct digits from
-- the same alphabet) with its feedback against the secret: A = digits right AND in place, B = digits right
-- but in the wrong place. The line set is MINIMAL: all lines together leave exactly one code, and dropping
-- any single line leaves two or more.
local CodeLock = {}

function CodeLock.space(L, alphabet)
	local out, cur, used = {}, {}, {}
	local function rec(pos)
		if pos > L then
			out[#out + 1] = table.clone(cur)
			return
		end
		for _, d in alphabet do
			if not used[d] then
				used[d] = true
				cur[pos] = d
				rec(pos + 1)
				used[d] = false
			end
		end
	end
	rec(1)
	return out
end

function CodeLock.feedback(g, c)
	local a, common = 0, 0
	local L = #g
	for i = 1, L do
		local gi = g[i]
		if gi == c[i] then a += 1 end
		for j = 1, L do
			if gi == c[j] then common += 1; break end
		end
	end
	return a, common - a
end

local function consistent(code, lines, skip)
	for i, ln in lines do
		if i ~= skip then
			local a, b = CodeLock.feedback(ln.guess, code)
			if a ~= ln.a or b ~= ln.b then return false end
		end
	end
	return true
end

-- how many codes of `space` fit every line except `skip`; stops counting at `cap` (nil = count all)
function CodeLock.count(space, lines, skip, cap)
	local n = 0
	for _, code in space do
		if consistent(code, lines, skip) then
			n += 1
			if cap and n >= cap then return n end
		end
	end
	return n
end

-- { secret, lines, draws, restarts } or nil
function CodeLock.generate(space, rng, maxDraws)
	for restart = 0, 20 do
		local secret = space[rng:below(#space)]
		local cands = space
		local lines = {}
		local draws = 0
		while #cands > 1 and draws < maxDraws do
			draws += 1
			local guess = space[rng:below(#space)]
			if guess ~= secret then
				local a, b = CodeLock.feedback(guess, secret)
				local nextC = {}
				for _, c in cands do
					local ca, cb = CodeLock.feedback(guess, c)
					if ca == a and cb == b then nextC[#nextC + 1] = c end
				end
				if #nextC < #cands then
					lines[#lines + 1] = { guess = guess, a = a, b = b }
					cands = nextC
				end
			end
		end
		if #cands == 1 then
			-- minimise: drop lines, in a random order, while the code stays unique
			local order = {}
			for i = 1, #lines do order[i] = i end
			shuffle(rng, order)
			local keep = {}
			for i = 1, #lines do keep[i] = true end
			for _, i in order do
				keep[i] = false
				local trial = {}
				for j = 1, #lines do if keep[j] then trial[#trial + 1] = lines[j] end end
				if CodeLock.count(space, trial, nil, 2) ~= 1 then keep[i] = true end
			end
			local out = {}
			for j = 1, #lines do if keep[j] then out[#out + 1] = lines[j] end end
			shuffle(rng, out)
			return { secret = secret, lines = out, draws = draws, restarts = restart }
		end
	end
	return nil
end

--============================================================================ Flask Shelf
-- N flasks in N slots. Clue sentences about the SECRET order; the set is minimal as above.
local Shelf = {}
Shelf.Colors = { "Red", "Blue", "Green", "Yellow", "Purple" }
Shelf.Types = { "left", "adj", "notadj", "notslot", "atend", "notend" }

function Shelf.perms(N)
	local out, cur, used = {}, {}, {}
	local function rec(pos)
		if pos > N then out[#out + 1] = table.clone(cur); return end
		for c = 1, N do
			if not used[c] then used[c] = true; cur[pos] = c; rec(pos + 1); used[c] = false end
		end
	end
	rec(1)
	-- store as pos[color] = slot as well, for fast clue evaluation
	local posOf = {}
	for i, p in out do
		local pos = {}
		for slot, c in p do pos[c] = slot end
		posOf[i] = pos
	end
	return out, posOf
end

function Shelf.holds(clue, pos, N)
	local t = clue.t
	if t == "left" then return pos[clue.a] < pos[clue.b] end
	if t == "adj" then return math.abs(pos[clue.a] - pos[clue.b]) == 1 end
	if t == "notadj" then return math.abs(pos[clue.a] - pos[clue.b]) > 1 end
	if t == "notslot" then return pos[clue.a] ~= clue.k end
	if t == "atend" then return pos[clue.a] == 1 or pos[clue.a] == N end
	if t == "notend" then return pos[clue.a] ~= 1 and pos[clue.a] ~= N end
	error("clue type " .. tostring(t))
end

local function shelfCount(posOf, N, clues, skip, cap)
	local n = 0
	for _, pos in posOf do
		local ok = true
		for i, cl in clues do
			if i ~= skip and not Shelf.holds(cl, pos, N) then ok = false; break end
		end
		if ok then
			n += 1
			if cap and n >= cap then return n end
		end
	end
	return n
end

function Shelf.generate(N, posOf, rng, maxDraws)
	for restart = 0, 20 do
		local secret = posOf[rng:below(#posOf)]
		local cands = posOf
		local clues = {}
		local draws = 0
		while #cands > 1 and draws < maxDraws do
			draws += 1
			local t = Shelf.Types[rng:below(#Shelf.Types)]
			local a = rng:below(N)
			local b = rng:below(N - 1)
			if b >= a then b += 1 end
			local clue = { t = t, a = a, b = b, k = rng:below(N) }
			if Shelf.holds(clue, secret, N) then
				local nextC = {}
				for _, p in cands do if Shelf.holds(clue, p, N) then nextC[#nextC + 1] = p end end
				if #nextC < #cands then
					clues[#clues + 1] = clue
					cands = nextC
				end
			end
		end
		if #cands == 1 then
			local order = {}
			for i = 1, #clues do order[i] = i end
			shuffle(rng, order)
			local keep = {}
			for i = 1, #clues do keep[i] = true end
			for _, i in order do
				keep[i] = false
				local trial = {}
				for j = 1, #clues do if keep[j] then trial[#trial + 1] = clues[j] end end
				if shelfCount(posOf, N, trial, nil, 2) ~= 1 then keep[i] = true end
			end
			local out = {}
			for j = 1, #clues do if keep[j] then out[#out + 1] = clues[j] end end
			return { secret = secret, clues = out, draws = draws, restarts = restart }
		end
	end
	return nil
end

--============================================================================ Lamp Grid (lights out)
-- n x n lamps, goal ALL LIT. Pressing a lamp flips it and its up/down/left/right neighbours. A puzzle is
-- made by pressing a hidden set S from the solved board; its minimum number of presses is taken over S
-- plus every press set that changes nothing (the null space). Generation keeps S only when that minimum
-- is exactly k, so the difficulty knob is exact.
local Lamps = {}

local function bit(i) return 2 ^ (i - 1) end
local function xor(a, b) return bit32.bxor(a, b) end
local function popcount(x)
	local n = 0
	while x > 0 do
		n += x % 2
		x = math.floor(x / 2)
	end
	return n
end
Lamps.popcount = popcount

function Lamps.effects(n)
	local eff = {}
	for r = 1, n do
		for c = 1, n do
			local i = (r - 1) * n + c
			local m = bit(i)
			if r > 1 then m += bit(i - n) end
			if r < n then m += bit(i + n) end
			if c > 1 then m += bit(i - 1) end
			if c < n then m += bit(i + 1) end
			eff[i] = m
		end
	end
	return eff
end

function Lamps.apply(eff, set)
	local s = 0
	local i = 1
	local x = set
	while x > 0 do
		if x % 2 == 1 then s = xor(s, eff[i]) end
		x = math.floor(x / 2)
		i += 1
	end
	return s
end

function Lamps.nullspace(n, eff)
	local out = {}
	for set = 0, 2 ^ (n * n) - 1 do
		if Lamps.apply(eff, set) == 0 then out[#out + 1] = set end
	end
	return out
end

function Lamps.minPresses(null, set)
	local best = math.huge
	for _, v in null do
		local p = popcount(xor(set, v))
		if p < best then best = p end
	end
	return best
end

function Lamps.generate(n, k, eff, null, rng)
	for attempt = 1, 500 do
		local cells = {}
		for i = 1, n * n do cells[i] = i end
		shuffle(rng, cells)
		local set = 0
		for i = 1, k do set += bit(cells[i]) end
		if Lamps.minPresses(null, set) == k then
			return { set = set, state = Lamps.apply(eff, set), attempts = attempt }
		end
	end
	return nil
end

--============================================================================ the Lab (DESIGN.md §6)
-- Five wings of three rooms. A room = one Code Lock on the exit door + f feeder stations. Solving a feeder
-- lights one hidden line of the door's board. The door takes no code until every line is lit.
local DIGITS10 = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }
local DIGITS6 = { 1, 2, 3, 4, 5, 6 }

-- door = code config id; feeders per room (in order): "lamp3:k" / "lamp4:k" / "shelf:N".
-- Several candidate tables are measured side by side in Part 5b; SHIP names the one DESIGN.md specifies.
local LABS = {
	-- V1: the first draft. 4-digit doors in both of the last two wings, a 3-feeder finale.
	V1 = {
		{ id = "reception", door = "L3D6", rooms = { { "lamp3:2" }, { "shelf:3" }, { "lamp3:3" } } },
		{ id = "archive", door = "L3D10", rooms = { { "shelf:3", "lamp3:3" }, { "lamp3:3", "shelf:4" }, { "shelf:4", "lamp3:4" } } },
		{ id = "greenhouse", door = "L3D10", rooms = { { "lamp3:4", "shelf:4" }, { "shelf:4", "lamp4:3" }, { "lamp4:4", "shelf:4" } } },
		{ id = "coldstore", door = "L4D10", rooms = { { "shelf:4", "lamp4:4" }, { "lamp4:4", "shelf:5" }, { "shelf:5", "lamp4:5" } } },
		{ id = "reactor", door = "L4D10", rooms = { { "lamp4:5", "shelf:5" }, { "shelf:5", "lamp4:5" }, { "lamp4:5", "shelf:5", "lamp3:4" } } },
	},
	-- V2: 3-digit doors through Cold Storage; no 3-feeder room.
	V2 = {
		{ id = "reception", door = "L3D6", rooms = { { "lamp3:2" }, { "shelf:3" }, { "lamp3:3" } } },
		{ id = "archive", door = "L3D10", rooms = { { "shelf:3", "lamp3:3" }, { "lamp3:3", "shelf:4" }, { "shelf:4", "lamp3:4" } } },
		{ id = "greenhouse", door = "L3D10", rooms = { { "lamp3:4", "shelf:4" }, { "shelf:4", "lamp4:3" }, { "lamp4:4", "shelf:4" } } },
		{ id = "coldstore", door = "L3D10", rooms = { { "shelf:4", "lamp4:4" }, { "lamp4:4", "shelf:5" }, { "shelf:5", "lamp4:5" } } },
		{ id = "reactor", door = "L4D10", rooms = { { "lamp4:5", "shelf:5" }, { "shelf:5", "lamp4:5" }, { "lamp4:5", "shelf:5" } } },
	},
	-- V3: V2 with one feeder in the Archive: the second feeder arrives with the third band.
	V3 = {
		{ id = "reception", door = "L3D6", rooms = { { "lamp3:2" }, { "shelf:3" }, { "lamp3:3" } } },
		{ id = "archive", door = "L3D10", rooms = { { "shelf:4" }, { "lamp3:4" }, { "shelf:4" } } },
		{ id = "greenhouse", door = "L3D10", rooms = { { "lamp3:4", "shelf:4" }, { "shelf:4", "lamp4:3" }, { "lamp4:4", "shelf:4" } } },
		{ id = "coldstore", door = "L3D10", rooms = { { "shelf:4", "lamp4:4" }, { "lamp4:4", "shelf:5" }, { "shelf:5", "lamp4:5" } } },
		{ id = "reactor", door = "L4D10", rooms = { { "lamp4:5", "shelf:5" }, { "shelf:5", "lamp4:5" }, { "lamp4:5", "shelf:5" } } },
	},
	-- V4: V3 with the 5-flask shelf only in the Reactor.
	V4 = {
		{ id = "reception", door = "L3D6", rooms = { { "lamp3:2" }, { "shelf:3" }, { "lamp3:3" } } },
		{ id = "archive", door = "L3D10", rooms = { { "shelf:4" }, { "lamp3:4" }, { "shelf:4" } } },
		{ id = "greenhouse", door = "L3D10", rooms = { { "lamp3:4", "shelf:4" }, { "shelf:4", "lamp4:3" }, { "lamp4:4", "shelf:4" } } },
		{ id = "coldstore", door = "L3D10", rooms = { { "shelf:4", "lamp4:4" }, { "lamp4:4", "shelf:4" }, { "shelf:4", "lamp4:5" } } },
		{ id = "reactor", door = "L4D10", rooms = { { "lamp4:5", "shelf:5" }, { "shelf:5", "lamp4:5" }, { "lamp4:5", "shelf:5" } } },
	},
}
local SHIP = "V4"
local LAB = LABS[SHIP]

local DOORS = {
	L2D10 = { L = 2, alphabet = DIGITS10 },
	L3D6 = { L = 3, alphabet = DIGITS6 },
	L3D8 = { L = 3, alphabet = { 1, 2, 3, 4, 5, 6, 7, 8 } },
	L3D10 = { L = 3, alphabet = DIGITS10 },
	L4D10 = { L = 4, alphabet = DIGITS10 },
}

--============================================================================ player profiles [A]
-- Seconds. Every one of these is an ASSUMPTION (DESIGN.md "How to read the numbers").
--   doorRead/doorThink: per clue line on the door (think x Door4Factor for 4-digit codes)
--   shelfRead/shelfThink: per clue sentence (x ShelfSizeFactor^(N-3))
--   lampThink: per press in the minimum; lampWaste: presses made per press needed
--   pWrong*: chance a submission is wrong; pHint*: chance a hint is taken on a station
local PROFILES = {
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
local MODEL = {
	Door4Factor = 1.5,     -- a 4-digit line is harder to combine than a 3-digit one [A]
	ShelfSizeFactor = 1.3, -- each extra flask makes every clue slower to apply [A]
	TapSeconds = 0.6,      -- one lamp press / one swap, including the tap and the server round trip [A]
	DialSeconds = 1.2,     -- setting one dial of the keypad [A]
	HintSaves = 0.4,       -- a hint removes this share of the remaining think time [A]
	RethinkShare = 0.3,    -- after a wrong try, this share of the think time is spent again [A]
	-- walking and overheads, [R] from the room geometry in DESIGN.md §4 at WalkSpeed 16:
	OpenSeconds = 0.5,     -- prompt + overlay open
	StationWalk = 1.6,     -- about 24 studs between stations = 1.5 s, plus turning [R]
	EntryWalk = 1.0,       -- lift door to the first station, 14 studs [R]
	ExitWalk = 1.5,        -- door to the exit lift, through the corridor [R]
	LiftSeconds = 3.5,     -- BoardSeconds 1.0 + RideSeconds 2.5 (DESIGN.md §6.2)
	RoomIntro = 3,         -- reading the room card on arrival [A]
	-- the wrong-try lockout (DESIGN.md §6.3): 3, 6, 12, then 20 s per wrong try
	Lockout = { 3, 6, 12, 20 },
	HazardMeanSeconds = 150, -- the template scheduler's 120-180 s uniform interval (plus1-jump Hazards.spec: 150.9)
	HazardCostSeconds = 2.5, -- a dodge: collapse the overlay, step out, reopen (DESIGN.md §9) [A]
}

--============================================================================ Part 0: sanity
print("== Part 0: sanity")
do
	local r = Rng.new(7)
	local seen = {}
	for _ = 1, 6000 do
		local v = r:below(6)
		seen[v] = (seen[v] or 0) + 1
	end
	print(string.format("  Rng.below(6) x6000: %d %d %d %d %d %d", seen[1], seen[2], seen[3], seen[4], seen[5], seen[6]))
	local a, b = CodeLock.feedback({ 6, 8, 2 }, { 0, 4, 2 })
	local a2, b2 = CodeLock.feedback({ 2, 0, 6 }, { 0, 4, 2 })
	print(string.format("  feedback 682 vs 042 = (%d,%d), 206 vs 042 = (%d,%d)  [want (1,0), (0,2)]", a, b, a2, b2))
	-- the classic published puzzle (682/614/206/738/780 -> 042) must be unique under our rules
	local space = CodeLock.space(3, DIGITS10)
	local classic = {
		{ guess = { 6, 8, 2 }, a = 1, b = 0 }, { guess = { 6, 1, 4 }, a = 0, b = 1 },
		{ guess = { 2, 0, 6 }, a = 0, b = 2 }, { guess = { 7, 3, 8 }, a = 0, b = 0 },
		{ guess = { 7, 8, 0 }, a = 0, b = 1 },
	}
	local n = CodeLock.count(space, classic)
	local found
	for _, c in space do if consistent(c, classic) then found = c end end
	print(string.format("  classic 5-line puzzle: %d solution(s): %d%d%d  [want 1: 042]", n, found[1], found[2], found[3]))
end

--============================================================================ Part 1: Code Lock
print("\n== Part 1: Code Lock (distinct digits; minimal line sets)")
local DOOR_POOL = {}
do
	local N = { L2D10 = 2000, L3D6 = 2000, L3D8 = 2000, L3D10 = 2000, L4D10 = 600 }
	for _, id in { "L2D10", "L3D6", "L3D8", "L3D10", "L4D10" } do
		local cfg = DOORS[id]
		local space = CodeLock.space(cfg.L, cfg.alphabet)
		local rng = Rng.new(1000 + cfg.L * 10 + #cfg.alphabet)
		local ms, draws, restarts, times, fbTypes = {}, {}, {}, {}, {}
		local hiddenCands = { {}, {}, {} }
		local tooFew = { 0, 0, 0 }
		local fails, notMinimal = 0, 0
		local pool = {}
		for trial = 1, N[id] do
			local t0 = os.clock()
			local g = CodeLock.generate(space, rng, 200)
			times[#times + 1] = (os.clock() - t0) * 1000
			if g == nil then
				fails += 1
			else
				ms[#ms + 1] = #g.lines
				draws[#draws + 1] = g.draws
				restarts[#restarts + 1] = g.restarts
				for _, ln in g.lines do fbTypes[#fbTypes + 1] = ln.a .. "/" .. ln.b end
				-- every line necessary?
				for i = 1, #g.lines do
					if CodeLock.count(space, g.lines, i, 2) < 2 then notMinimal += 1 end
				end
				-- hide f lines: how many codes do the VISIBLE lines alone still allow?
				for f = 1, 3 do
					if #g.lines >= f + 1 then
						local vis = {}
						local idx = {}
						for i = 1, #g.lines do idx[i] = i end
						shuffle(rng, idx)
						for j = f + 1, #idx do vis[#vis + 1] = g.lines[idx[j]] end
						table.insert(hiddenCands[f], CodeLock.count(space, vis))
					else
						tooFew[f] += 1
					end
				end
				if #pool < 400 then pool[#pool + 1] = #g.lines end
			end
		end
		DOOR_POOL[id] = pool
		print(string.format("  %s  space %d codes, %d generated, %d failed, %d lines not necessary", id, #space, #ms, fails, notMinimal))
		print("    lines m       " .. fmtQ(quantiles(ms)))
		print("    m histogram   " .. hist(ms))
		print("    draws         " .. fmtQ(quantiles(draws)) .. "; restarts max " .. quantiles(restarts).max)
		print("    gen ms (CLI)  " .. fmtQ(quantiles(times), 2))
		print("    feedback A/B  " .. hist(fbTypes))
		for f = 1, 3 do
			if #hiddenCands[f] > 0 then
				print(string.format("    hide %d: visible lines alone leave %s codes; m < %d+1 in %d of %d sets",
					f, fmtQ(quantiles(hiddenCands[f])), f, tooFew[f], #ms))
			end
		end
	end
end

--============================================================================ Part 2: Flask Shelf
print("\n== Part 2: Flask Shelf (minimal clue sets)")
local SHELF_POOL = {}
do
	for _, N in { 3, 4, 5 } do
		local _, posOf = Shelf.perms(N)
		local rng = Rng.new(2000 + N)
		local ms, times, types, restarts = {}, {}, {}, {}
		local fails, notMinimal = 0, 0
		local pool = {}
		for trial = 1, 3000 do
			local t0 = os.clock()
			local g = Shelf.generate(N, posOf, rng, 400)
			times[#times + 1] = (os.clock() - t0) * 1000
			if g == nil then fails += 1 else
				ms[#ms + 1] = #g.clues
				restarts[#restarts + 1] = g.restarts
				for _, cl in g.clues do types[#types + 1] = cl.t end
				for i = 1, #g.clues do
					if shelfCount(posOf, N, g.clues, i, 2) < 2 then notMinimal += 1 end
				end
				if #pool < 400 then pool[#pool + 1] = #g.clues end
			end
		end
		SHELF_POOL[N] = pool
		print(string.format("  N=%d  %d orders, %d generated, %d failed, %d clues not necessary, restarts max %d",
			N, #posOf, #ms, fails, notMinimal, quantiles(restarts).max))
		print("    clues m       " .. fmtQ(quantiles(ms)))
		print("    m histogram   " .. hist(ms))
		print("    clue types    " .. hist(types))
		print("    gen ms (CLI)  " .. fmtQ(quantiles(times), 3))
	end
end

--============================================================================ Part 1b: the shipped door rules
-- A door set is accepted only if: at least one line is visible from the start (m >= f + 1), it fits the
-- board (m <= MaxDoorLines), and in the very first room of the Lab it is short (m <= FirstRoomMaxLines).
-- Anything else is regenerated. Pools keyed "<door>:f<f>[:first]" feed the pacing model.
local RULES = { MaxDoorLines = 6, FirstRoomMaxLines = 3, MaxShelfClues = 7 }
print("\n== Part 1b: the shipped door rules (m >= f+1, m <= " .. RULES.MaxDoorLines .. ", room 1: m <= " .. RULES.FirstRoomMaxLines .. ")")
local ACCEPTED = {}
do
	local keys = {
		{ key = "L3D6:f1:first", door = "L3D6", f = 1, first = true },
		{ key = "L3D6:f1", door = "L3D6", f = 1 },
		{ key = "L3D10:f1", door = "L3D10", f = 1 },
		{ key = "L3D10:f2", door = "L3D10", f = 2 },
		{ key = "L4D10:f2", door = "L4D10", f = 2 },
		{ key = "L4D10:f3", door = "L4D10", f = 3 }, -- only the V1 draft uses it (Part 5b)
	}
	for _, k in keys do
		local cfg = DOORS[k.door]
		local space = CodeLock.space(cfg.L, cfg.alphabet)
		local rng = Rng.new(4000 + #k.key * 7 + k.f)
		local ms, attempts, times, visible = {}, {}, {}, {}
		local n = (k.door == "L4D10") and 400 or 1500
		for _ = 1, n do
			local t0 = os.clock()
			local tries = 0
			local g
			repeat
				tries += 1
				g = CodeLock.generate(space, rng, 200)
				local ok = g ~= nil and #g.lines >= k.f + 1 and #g.lines <= RULES.MaxDoorLines
					and (not k.first or #g.lines <= RULES.FirstRoomMaxLines)
				if not ok then g = nil end
			until g ~= nil or tries >= 50
			times[#times + 1] = (os.clock() - t0) * 1000
			attempts[#attempts + 1] = tries
			if g then
				ms[#ms + 1] = #g.lines
				visible[#visible + 1] = #g.lines - k.f
			end
		end
		ACCEPTED[k.key] = ms
		print(string.format("  %-14s accepted %d of %d; generations per door %s", k.key, #ms, n, fmtQ(quantiles(attempts))))
		print("    lines m     " .. hist(ms) .. "   visible at start " .. hist(visible))
		print("    ms per door (CLI) " .. fmtQ(quantiles(times), 2))
	end
end

print("\n== Part 2b: the shipped shelf rule (m <= " .. RULES.MaxShelfClues .. ")")
local SHELF_ACCEPTED = {}
do
	for _, N in { 3, 4, 5 } do
		local _, posOf = Shelf.perms(N)
		local rng = Rng.new(2500 + N)
		local ms, attempts = {}, {}
		for _ = 1, 2000 do
			local tries = 0
			local g
			repeat
				tries += 1
				g = Shelf.generate(N, posOf, rng, 400)
				if g ~= nil and #g.clues > RULES.MaxShelfClues then g = nil end
			until g ~= nil or tries >= 50
			attempts[#attempts + 1] = tries
			if g then ms[#ms + 1] = #g.clues end
		end
		SHELF_ACCEPTED[N] = ms
		print(string.format("  N=%d accepted %d of 2000; generations per shelf %s; m %s", N, #ms, fmtQ(quantiles(attempts)), hist(ms)))
	end
end

--============================================================================ Part 3: Lamp Grid
print("\n== Part 3: Lamp Grid (lights out, goal all lit)")
local LAMP = {}
do
	for _, n in { 3, 4 } do
		local eff = Lamps.effects(n)
		local t0 = os.clock()
		local null = Lamps.nullspace(n, eff)
		LAMP[n] = { eff = eff, null = null }
		print(string.format("  %dx%d: null space has %d press sets (dimension %d), found in %.1f ms",
			n, n, #null, math.log(#null, 2), (os.clock() - t0) * 1000))
		local rng = Rng.new(3000 + n)
		for k = 2, (n == 3 and 5 or 7) do
			local attempts, times, lit = {}, {}, {}
			local fails = 0
			for trial = 1, 2000 do
				local t1 = os.clock()
				local g = Lamps.generate(n, k, eff, null, rng)
				times[#times + 1] = (os.clock() - t1) * 1000
				if g == nil then fails += 1 else
					attempts[#attempts + 1] = g.attempts
					-- lamps lit at the start (the goal is all n*n lit)
					lit[#lit + 1] = n * n - popcount(g.state)
				end
			end
			if #attempts > 0 then
				print(string.format("    k=%d: %d failed; attempts %s; lit at start %s; gen ms p90 %.3f",
					k, fails, fmtQ(quantiles(attempts)), fmtQ(quantiles(lit)), quantiles(times).p90))
			else
				print(string.format("    k=%d: all %d failed", k, fails))
			end
		end
	end
end

--============================================================================ Part 4: brute force vs the lockout
print("\n== Part 4: trying every answer against the lockout (3, 6, 12, then 20 s per wrong try)")
local function lockoutFor(wrongIndex)
	local L = MODEL.Lockout
	return L[math.min(wrongIndex, #L)]
end
local function bruteSeconds(space, perTry)
	-- uniform secret, candidates tried in a fixed order: expected over the secret's position
	local total = 0
	for pos = 1, space do
		local t = pos * perTry
		for w = 1, pos - 1 do t += lockoutFor(w) end
		total += t
	end
	return total / space
end
do
	local rows = {
		{ "door L3D6", 120, 3 * MODEL.DialSeconds + 0.5 },
		{ "door L3D10", 720, 3 * MODEL.DialSeconds + 0.5 },
		{ "door L4D10", 5040, 4 * MODEL.DialSeconds + 0.5 },
		{ "shelf N=3", 6, 2 * MODEL.TapSeconds + 0.5 },
		{ "shelf N=4", 24, 3 * MODEL.TapSeconds + 0.5 },
		{ "shelf N=5", 120, 4 * MODEL.TapSeconds + 0.5 },
	}
	for _, r in rows do
		local s = bruteSeconds(r[2], r[3])
		print(string.format("  %-11s %5d answers: expected %.0f s (%.1f min, %.2f h)", r[1], r[2], s, s / 60, s / 3600))
	end
end

--============================================================================ Part 5: pacing
print("\n== Part 5: pacing (15 rooms to the roof, then replays to 45 stars)")
local function pick(rng, pool) return pool[rng:below(#pool)] end

local function parseFeeder(s)
	local kind, v = string.match(s, "^(%a+%d?):(%d+)$")
	return kind, tonumber(v)
end

-- seconds a profile spends on one station, with ok flags for the stars
local function stationTime(p, rng, kind, v)
	local t = MODEL.OpenSeconds
	local wrong, hint = false, false
	if kind == "lamp3" or kind == "lamp4" then
		local k = v
		local think = k * p.lampThink * (kind == "lamp4" and 1.25 or 1)
		if rng:next() < p.pHintLamp then hint = true; think *= (1 - MODEL.HintSaves) end
		t += think + math.ceil(k * p.lampWaste) * MODEL.TapSeconds
	elseif kind == "shelf" then
		local N = v
		local m = pick(rng, SHELF_ACCEPTED[N])
		local factor = MODEL.ShelfSizeFactor ^ (N - 3)
		local think = m * (p.shelfRead + p.shelfThink * factor)
		if rng:next() < p.pHintShelf then hint = true; think *= (1 - MODEL.HintSaves) end
		t += think + (N - 1) * MODEL.TapSeconds + 0.5
		local tries = 0
		while rng:next() < p.pWrongShelf * (tries == 0 and 1 or 0.5) do
			tries += 1
			wrong = true
			t += lockoutFor(tries) + think * MODEL.RethinkShare + (N - 1) * MODEL.TapSeconds + 0.5
			if tries > 6 then break end
		end
	end
	return t, wrong, hint
end

local function doorTime(p, rng, doorId, poolKey)
	local cfg = DOORS[doorId]
	local m = pick(rng, ACCEPTED[poolKey])
	local four = cfg.L == 4
	local think = m * (p.doorRead + p.doorThink * (four and MODEL.Door4Factor or 1))
	local hint = false
	local pHint = four and p.pHintDoor4 or p.pHintDoor3
	if rng:next() < pHint then hint = true; think *= (1 - MODEL.HintSaves) end
	local t = MODEL.OpenSeconds + think + cfg.L * MODEL.DialSeconds + 0.5
	local wrong = false
	local tries = 0
	local pWrong = four and p.pWrongDoor4 or p.pWrongDoor3
	while rng:next() < pWrong * (tries == 0 and 1 or 0.5) do
		tries += 1
		wrong = true
		t += lockoutFor(tries) + think * MODEL.RethinkShare + cfg.L * MODEL.DialSeconds + 0.5
		if tries > 6 then break end
	end
	return t, wrong, hint, m
end

-- one room: seconds, stars (1-3), seconds spent where hazards can come
local function playRoom(p, rng, lab, wingIdx, roomIdx)
	local wing = lab[wingIdx]
	local feeders = wing.rooms[roomIdx]
	local t = MODEL.RoomIntro + MODEL.EntryWalk
	local anyWrong, anyHint = false, false
	for _, f in feeders do
		local kind, v = parseFeeder(f)
		local st, w, h = stationTime(p, rng, kind, v)
		t += st + MODEL.StationWalk
		anyWrong = anyWrong or w
		anyHint = anyHint or h
	end
	local key = wing.door .. ":f" .. #feeders .. ((wingIdx == 1 and roomIdx == 1) and ":first" or "")
	local dt, w, h = doorTime(p, rng, wing.door, key)
	t += dt + MODEL.ExitWalk
	anyWrong = anyWrong or w
	anyHint = anyHint or h
	-- hazards (none in the first wing): each one costs a dodge
	local exposed = (wingIdx >= 2) and t or 0
	if wingIdx >= 2 then
		local expected = t / MODEL.HazardMeanSeconds
		local n = math.floor(expected)
		if rng:next() < expected - n then n += 1 end
		t += n * MODEL.HazardCostSeconds
	end
	local stars = 1 + (anyWrong and 0 or 1) + (anyHint and 0 or 1)
	return t + MODEL.LiftSeconds, stars, exposed
end

local function runPacing(lab, name, players, seed)
	local p = PROFILES[name]
	local rng = Rng.new(seed)
	local out = { roofMin = {}, star45Min = {}, starsFirst = {}, replays = {}, bandMin = {}, hazards = {}, firstHazardBandMin = {} }
	local rooms = 0
	for wi = 1, #lab do out.bandMin[wi] = {}; rooms += #lab[wi].rooms end
	for _ = 1, players do
		local clock = 0
		local best, slots = {}, {}
		local hz = 0
		for wi = 1, #lab do
			local w0 = clock
			for ri = 1, #lab[wi].rooms do
				local t, s, exposed = playRoom(p, rng, lab, wi, ri)
				clock += t
				hz += exposed / MODEL.HazardMeanSeconds
				table.insert(best, s)
				table.insert(slots, { wi, ri })
			end
			table.insert(out.bandMin[wi], (clock - w0) / 60)
			if wi == 1 then table.insert(out.firstHazardBandMin, clock / 60) end
		end
		table.insert(out.roofMin, clock / 60)
		table.insert(out.hazards, hz)
		local total = 0
		for i = 1, rooms do total += best[i] end
		table.insert(out.starsFirst, total)
		-- after the roof: Continue = the lowest room with < 3 stars, until every room has 3 (20 h cap)
		local n = 0
		while total < 3 * rooms and clock < 20 * 3600 do
			for i = 1, rooms do
				if best[i] < 3 then
					local t, s = playRoom(p, rng, lab, slots[i][1], slots[i][2])
					clock += t
					n += 1
					if s > best[i] then total += s - best[i]; best[i] = s end
					break
				end
			end
		end
		table.insert(out.star45Min, clock / 60)
		table.insert(out.replays, n)
	end
	return out
end

local PACING = {}
for _, name in { "careful", "normal", "firstTimer" } do
	local r = runPacing(LAB, name, 1500, 5000 + #name)
	PACING[name] = r
	print(string.format("  %s (table %s)", name, SHIP))
	print("    minutes to the roof        " .. fmtQ(quantiles(r.roofMin), 1))
	print("    stars after the first pass " .. fmtQ(quantiles(r.starsFirst)))
	print("    replays to 45 stars        " .. fmtQ(quantiles(r.replays)))
	print("    minutes to 45 stars        " .. fmtQ(quantiles(r.star45Min), 1))
	print("    minute the first hazard band (Archive) starts " .. fmtQ(quantiles(r.firstHazardBandMin), 1))
	print("    hazards met on the way to the roof " .. fmtQ(quantiles(r.hazards), 1))
	for wi = 1, #LAB do
		print(string.format("    band %-10s minutes %s", LAB[wi].id, fmtQ(quantiles(r.bandMin[wi]), 1)))
	end
end

print("\n== Part 5b: the candidate wing tables side by side (minutes to the roof, p50 [p10-p90])")
for _, id in { "V1", "V2", "V3", "V4" } do
	local cells = {}
	for _, name in { "careful", "normal", "firstTimer" } do
		local q = quantiles(runPacing(LABS[id], name, 800, 7000 + #name).roofMin)
		table.insert(cells, string.format("%s %.1f [%.1f-%.1f]", name, q.p50, q.p10, q.p90))
	end
	print(string.format("  %s%s  %s", id, id == SHIP and "*" or " ", table.concat(cells, "   ")))
end
print("  (* = the table DESIGN.md specifies)")

--============================================================================ Part 6: the board value
print("\n== Part 6: board value = stars * 2e9 + (2e9 - reachedAtUnix)")
do
	local now = 1790726400 -- 2026-09-30 00:00 UTC
	local function value(stars, t) return stars * 2e9 + (2e9 - t) end
	local maxV = value(45, now)
	print(string.format("  largest value %.0f (< 2^53 = %.0f: %s)", maxV, 2 ^ 53, tostring(maxV < 2 ^ 53)))
	-- a higher star count always ranks higher, while every reachedAt is later than `now`:
	-- value(s, t1) > value(s-1, t2)  <=>  t1 - t2 < 2e9
	local last = now + 2e9 - 1
	print(string.format("  order by stars holds for any two reachedAt in [%d, %d] (years 2026-%d)",
		now, last, 1970 + math.floor(last / 31556952)))
	print(string.format("  value(45, now) = %.0f; value(44, now) = %.0f; value(45, now+1) = %.0f",
		value(45, now), value(44, now), value(45, now + 1)))
	print(string.format("  integer: %s", tostring(value(45, now) % 1 == 0)))
end

print("\ndone")
