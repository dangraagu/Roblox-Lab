-- Spec for Shelf: the Flask Shelf feeder (DESIGN.md §3.2, §3.4, §3.5 invariant 2).
-- Run: luau tests/Shelf.spec.luau 2>&1
--
-- N flasks of N distinct colours (of five) in N slots, and a MINIMAL set of true clue sentences that
-- fit exactly one order. The shelf starts in a random order that is never the answer. A hint names one
-- flask's slot, at most N - 2 per shelf, so the last step is always the player's.
local Shelf = require("../src/shared/Shelf")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function randOf(seed)
	local r = Rng.new(seed)
	return function() return r:next() end
end

eq(#Shelf.perms(3), 6, "3 flasks: 6 orders")
eq(#Shelf.perms(4), 24, "4 flasks: 24 orders")
eq(#Shelf.perms(5), 120, "5 flasks: 120 orders")

-- holds(): the six clue types on a hand-written order. pos[color] = slot.
do
	local pos = { [1] = 1, [2] = 3, [3] = 2 } -- Red slot 1, Green slot 2, Blue slot 3
	truthy(Shelf.holds({ t = "left", a = 1, b = 2 }, pos, 3), "Red left of Blue")
	truthy(not Shelf.holds({ t = "left", a = 2, b = 1 }, pos, 3), "Blue is not left of Red")
	truthy(Shelf.holds({ t = "adj", a = 3, b = 2 }, pos, 3), "Green next to Blue")
	truthy(not Shelf.holds({ t = "adj", a = 1, b = 2 }, pos, 3), "Red is not next to Blue")
	truthy(Shelf.holds({ t = "notadj", a = 1, b = 2 }, pos, 3), "Red not next to Blue")
	truthy(Shelf.holds({ t = "notslot", a = 1, k = 2 }, pos, 3), "Red not in slot 2")
	truthy(not Shelf.holds({ t = "notslot", a = 1, k = 1 }, pos, 3), "Red IS in slot 1")
	truthy(Shelf.holds({ t = "atend", a = 2 }, pos, 3), "Blue at an end")
	truthy(not Shelf.holds({ t = "atend", a = 3 }, pos, 3), "Green not at an end")
	truthy(Shelf.holds({ t = "notend", a = 3 }, pos, 3), "Green not at either end")
end

local function checkShelves(N, n, seed, maxClues)
	local rand = randOf(seed)
	local bad = { unique = 0, necessary = 0, start = 0, perm = 0, count = 0, colors = 0, truth = 0, gens = 0 }
	local lo, hi = math.huge, 0
	for _ = 1, n do
		local s = Shelf.generate({ N = N, maxClues = maxClues }, rand)
		if s == nil then
			bad.gens += 1
			continue
		end
		local sols = Shelf.solve(s.colors, s.clues)
		if #sols ~= 1 or not Shelf.same(sols[1], s.secret) then bad.unique += 1 end
		for i = 1, #s.clues do
			local rest = {}
			for j = 1, #s.clues do if j ~= i then table.insert(rest, s.clues[j]) end end
			if #Shelf.solve(s.colors, rest) < 2 then bad.necessary += 1 end
		end
		if Shelf.same(s.start, s.secret) then bad.start += 1 end
		if not Shelf.isArrangement(s.start, s.colors) or not Shelf.isArrangement(s.secret, s.colors) then bad.perm += 1 end
		if #s.clues > maxClues or #s.clues < 1 then bad.count += 1 end
		lo, hi = math.min(lo, #s.clues), math.max(hi, #s.clues)
		local seen = {}
		for _, c in s.colors do
			if c < 1 or c > 5 or seen[c] then bad.colors += 1 end
			seen[c] = true
		end
		if #s.colors ~= N then bad.colors += 1 end
		if not Shelf.fits(s.secret, s.clues) then bad.truth += 1 end
	end
	print(string.format("  N=%d: %d shelves, %d-%d clues", N, n, lo, hi))
	eq(bad.gens, 0, "N=" .. N .. ": every generation succeeded")
	eq(bad.unique, 0, "N=" .. N .. ": exactly one order fits, and it is the secret")
	eq(bad.necessary, 0, "N=" .. N .. ": every clue is necessary")
	eq(bad.start, 0, "N=" .. N .. ": the start order is never the answer")
	eq(bad.perm, 0, "N=" .. N .. ": start and secret are arrangements of the shelf's colours")
	eq(bad.count, 0, "N=" .. N .. ": clue count within 1.." .. maxClues)
	eq(bad.colors, 0, "N=" .. N .. ": N distinct colours out of five")
	eq(bad.truth, 0, "N=" .. N .. ": every clue is true for the secret")
end
checkShelves(3, 1000, 31, 7)
checkShelves(4, 1000, 32, 7)
checkShelves(5, 1000, 33, 7)

-- arrangements and swaps
do
	truthy(Shelf.isArrangement({ 2, 5, 1 }, { 1, 2, 5 }), "a permutation of the colours is an arrangement")
	truthy(not Shelf.isArrangement({ 2, 2, 1 }, { 1, 2, 5 }), "a repeat is not")
	truthy(not Shelf.isArrangement({ 2, 5 }, { 1, 2, 5 }), "too short is not")
	truthy(not Shelf.isArrangement({ 2, 5, 3 }, { 1, 2, 5 }), "a colour not on the shelf is not")
	local o = { 1, 2, 3 }
	Shelf.swap(o, 1, 3)
	eq(table.concat(o), "321", "swap exchanges two slots")
end

-- hints: a flask's right slot, a flask not already told, at most N - 2
do
	local s = Shelf.generate({ N = 5, maxClues = 7 }, randOf(90))
	local told = {}
	for i = 1, 3 do
		local color, slot = Shelf.hint(s.secret, told, randOf(100 + i))
		truthy(color ~= nil, "shelf hint " .. i .. " exists")
		if color then
			eq(s.secret[slot], color, "shelf hint " .. i .. " names the colour's real slot")
			truthy(not told[color], "shelf hint " .. i .. " is new")
			told[color] = true
		end
	end
	eq((Shelf.hint(s.secret, told, randOf(7))), nil, "no fourth hint on a 5-flask shelf (cap N - 2 = 3)")
	eq(Shelf.hintCap(3), 1, "3 flasks: 1 hint")
end

-- the generator uses only the rand it is given
do
	local a = Shelf.generate({ N = 4, maxClues = 7 }, randOf(5))
	local b = Shelf.generate({ N = 4, maxClues = 7 }, randOf(5))
	eq(table.concat(a.secret), table.concat(b.secret), "same rand, same shelf")
end

print(string.format("Shelf: %d passed, %d failed", passed, failed))
if failed > 0 then error("Shelf spec failed", 0) end
