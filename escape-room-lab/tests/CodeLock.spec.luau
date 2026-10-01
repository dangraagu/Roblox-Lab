-- Spec for CodeLock: the exit door's code and its clue lines (DESIGN.md §3.1, §3.4, §3.5 invariant 1).
-- Run: luau tests/CodeLock.spec.luau 2>&1
--
-- The door code is L DISTINCT digits from an alphabet. A clue line is a guess and its feedback
-- (A = right digit, right place; B = right digit, wrong place). The line set is MINIMAL: together the
-- lines fit exactly one code, and dropping any one line lets two or more fit. Some lines are HIDDEN
-- until a feeder is solved, and the visible lines alone must never pin the code down.
local CodeLock = require("../src/shared/CodeLock")
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

local D10 = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }
local D6 = { 1, 2, 3, 4, 5, 6 }

--============================================================ feedback and the published classic
do
	local a, b = CodeLock.feedback({ 6, 8, 2 }, { 0, 4, 2 })
	eq(a * 10 + b, 10, "682 against 042 is one right and in place")
	a, b = CodeLock.feedback({ 2, 0, 6 }, { 0, 4, 2 })
	eq(a * 10 + b, 2, "206 against 042 is two right but misplaced")
	a, b = CodeLock.feedback({ 7, 3, 8 }, { 0, 4, 2 })
	eq(a * 10 + b, 0, "738 against 042 is nothing")
	a, b = CodeLock.feedback({ 0, 4, 2 }, { 0, 4, 2 })
	eq(a * 10 + b, 30, "the code against itself is all in place")

	-- the classic five-line puzzle (682/614/206/738/780 -> 042) has exactly one answer under these rules
	local classic = {
		{ guess = { 6, 8, 2 }, a = 1, b = 0 }, { guess = { 6, 1, 4 }, a = 0, b = 1 },
		{ guess = { 2, 0, 6 }, a = 0, b = 2 }, { guess = { 7, 3, 8 }, a = 0, b = 0 },
		{ guess = { 7, 8, 0 }, a = 0, b = 1 },
	}
	local sols = CodeLock.solve(classic, 3, D10)
	eq(#sols, 1, "the classic puzzle has one solution")
	eq(sols[1] and table.concat(sols[1]) or "", "042", "and it is 042")
end

--============================================================ the code spaces
eq(#CodeLock.space(3, D6), 120, "3 distinct digits from 1-6: 120 codes")
eq(#CodeLock.space(3, D10), 720, "3 distinct digits from 0-9: 720 codes")
eq(#CodeLock.space(4, D10), 5040, "4 distinct digits from 0-9: 5040 codes")
truthy(CodeLock.space(3, D10) == CodeLock.space(3, D10), "the space is built once and cached")

--============================================================ valid(): what the keypad may send
truthy(CodeLock.valid({ 1, 2, 3 }, 3, D10), "123 is a valid 0-9 code")
truthy(not CodeLock.valid({ 1, 1, 3 }, 3, D10), "a repeated digit is not a code")
truthy(not CodeLock.valid({ 1, 2 }, 3, D10), "too short is not a code")
truthy(not CodeLock.valid({ 1, 2, 3, 4 }, 3, D10), "too long is not a code")
truthy(not CodeLock.valid({ 0, 2, 3 }, 3, D6), "0 is outside the 1-6 alphabet")
truthy(not CodeLock.valid({ 7, 2, 3 }, 3, D6), "7 is outside the 1-6 alphabet")
truthy(not CodeLock.valid({ 1.5, 2, 3 }, 3, D10), "a fraction is not a digit")
truthy(not CodeLock.valid({ 0 / 0, 2, 3 }, 3, D10), "NaN is not a digit")
truthy(not CodeLock.valid({ "1", 2, 3 }, 3, D10), "a string is not a digit")
truthy(not CodeLock.valid("123", 3, D10), "a string is not a code")
truthy(not CodeLock.valid(nil, 3, D10), "nil is not a code")
truthy(not CodeLock.valid({ 1, 2, 3, n = 9 }, 3, D10), "extra keys make it not a plain code")

--============================================================ generation: the fairness invariants
-- DESIGN.md §3.5 invariant 1, over many sets per door kind, plus the acceptance rules of §3.4.
local function checkDoors(label, spec, n, seed)
	local rand = randOf(seed)
	local space = CodeLock.space(spec.L, spec.alphabet)
	local bad = { unique = 0, secretFits = 0, necessary = 0, visible = 0, count = 0, hidden = 0,
		feedback = 0, guessValid = 0, guessNotSecret = 0, gens = 0 }
	local minLines, maxLines, minVis, maxVis = math.huge, 0, math.huge, 0
	local maxGen = 0
	for _ = 1, n do
		local door = CodeLock.generate(spec, rand)
		if door == nil then
			bad.gens += 1
			continue
		end
		maxGen = math.max(maxGen, door.generations)
		local lines = door.lines
		if #CodeLock.solve(lines, spec.L, spec.alphabet) ~= 1 then bad.unique += 1 end
		if not CodeLock.fits(door.secret, lines) then bad.secretFits += 1 end
		for i = 1, #lines do
			local rest = {}
			for j = 1, #lines do if j ~= i then table.insert(rest, lines[j]) end end
			if CodeLock.count(rest, spec.L, spec.alphabet, 2) < 2 then bad.necessary += 1 end
		end
		local hiddenSet = {}
		for _, i in door.hidden do hiddenSet[i] = true end
		local nHidden = 0
		for _ in hiddenSet do nHidden += 1 end
		if nHidden ~= spec.feeders then bad.hidden += 1 end
		local vis = {}
		for i, ln in lines do if not hiddenSet[i] then table.insert(vis, ln) end end
		local nv = CodeLock.count(vis, spec.L, spec.alphabet)
		if nv < 2 then bad.visible += 1 end
		minVis, maxVis = math.min(minVis, nv), math.max(maxVis, nv)
		if #lines < spec.feeders + 1 or #lines > spec.maxLines then bad.count += 1 end
		minLines, maxLines = math.min(minLines, #lines), math.max(maxLines, #lines)
		for _, ln in lines do
			local a, b = CodeLock.feedback(ln.guess, door.secret)
			if a ~= ln.a or b ~= ln.b then bad.feedback += 1 end
			if not CodeLock.valid(ln.guess, spec.L, spec.alphabet) then bad.guessValid += 1 end
			if CodeLock.equal(ln.guess, door.secret) then bad.guessNotSecret += 1 end
		end
		if not CodeLock.valid(door.secret, spec.L, spec.alphabet) then bad.guessValid += 1 end
	end
	print(string.format("  %-22s %d sets: lines %d-%d, the visible lines leave %d-%d codes, generations max %d",
		label, n, minLines, maxLines, minVis, maxVis, maxGen))
	eq(bad.gens, 0, label .. ": every generation succeeded")
	eq(bad.unique, 0, label .. ": exactly one code fits all lines")
	eq(bad.secretFits, 0, label .. ": the secret fits every line")
	eq(bad.necessary, 0, label .. ": every line is necessary")
	eq(bad.hidden, 0, label .. ": exactly one hidden line per feeder")
	eq(bad.visible, 0, label .. ": the visible lines alone leave two or more codes")
	eq(bad.count, 0, label .. ": the line count is within [f + 1, max]")
	eq(bad.feedback, 0, label .. ": each line's feedback is the guess against the secret")
	eq(bad.guessValid, 0, label .. ": every guess and the secret are valid codes")
	eq(bad.guessNotSecret, 0, label .. ": no guess is the secret")
	truthy(#space > 0, label .. ": control, the space is not empty")
end

checkDoors("room 1 (1-6, f1, <=3)", { L = 3, alphabet = D6, feeders = 1, maxLines = 3 }, 1000, 11)
checkDoors("Reception (1-6, f1)", { L = 3, alphabet = D6, feeders = 1, maxLines = 6 }, 1000, 12)
checkDoors("Archive (0-9, f1)", { L = 3, alphabet = D10, feeders = 1, maxLines = 6 }, 1000, 13)
checkDoors("Greenhouse (0-9, f2)", { L = 3, alphabet = D10, feeders = 2, maxLines = 6 }, 1000, 14)
checkDoors("Reactor (4 digits, f2)", { L = 4, alphabet = D10, feeders = 2, maxLines = 6 }, 120, 15)

--============================================================ room 1 is short
do
	local rand = randOf(21)
	local longest = 0
	for _ = 1, 300 do
		local door = CodeLock.generate({ L = 3, alphabet = D6, feeders = 1, maxLines = 3 }, rand)
		longest = math.max(longest, door and #door.lines or 99)
	end
	truthy(longest <= 3, "a first-room door has at most 3 lines (got " .. longest .. ")")
end

--============================================================ an impossible spec fails loudly, never loops
do
	local door = CodeLock.generate({ L = 3, alphabet = D10, feeders = 5, maxLines = 3, maxGenerations = 5 }, randOf(3))
	eq(door, nil, "a spec no set can meet returns nil after maxGenerations")
end

--============================================================ hints: one position the player was not told
do
	local secret = { 4, 0, 7 }
	local told = {}
	local seen = {}
	for i = 1, 2 do
		local pos, digit = CodeLock.hint(secret, told, randOf(40 + i))
		truthy(pos ~= nil, "hint " .. i .. " names a position")
		if pos then
			eq(digit, secret[pos], "hint " .. i .. " tells the right digit")
			truthy(not seen[pos], "hint " .. i .. " is a position not told before")
			seen[pos] = true
			told[pos] = true
		end
	end
	local pos = CodeLock.hint(secret, told, randOf(9))
	eq(pos, nil, "after L - 1 hints there is no more: the last digit is the player's")
	eq(CodeLock.hintCap(3), 2, "hint cap for 3 digits is 2")
	eq(CodeLock.hintCap(4), 3, "hint cap for 4 digits is 3")
end

--============================================================ the generator uses only the rand it is given
do
	local a = CodeLock.generate({ L = 3, alphabet = D10, feeders = 2, maxLines = 6 }, randOf(777))
	local b = CodeLock.generate({ L = 3, alphabet = D10, feeders = 2, maxLines = 6 }, randOf(777))
	eq(table.concat(a.secret), table.concat(b.secret), "same rand, same secret (no hidden global randomness)")
	local c = CodeLock.generate({ L = 3, alphabet = D10, feeders = 2, maxLines = 6 }, randOf(778))
	truthy(table.concat(a.secret) .. #a.lines ~= table.concat(c.secret) .. #c.lines or a.lines[1].guess[1] ~= c.lines[1].guess[1],
		"a different rand gives a different door")
end

print(string.format("CodeLock: %d passed, %d failed", passed, failed))
if failed > 0 then error("CodeLock spec failed", 0) end
