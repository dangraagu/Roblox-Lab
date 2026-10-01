-- Spec for Text: every sentence a player reads, and its inverse (DESIGN.md §3.1, §3.2, §18.2).
-- Run: luau tests/Text.spec.luau 2>&1
--
-- A clue must never render blank, and a sentence must never be ambiguous: the headless walk reads
-- the rendered sentence back into numbers exactly the way a player does, so every sentence has a
-- parse, and parse(render(x)) == x is asserted for every form.
local Text = require("../src/shared/Text")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function ascii(s: string): boolean
	for i = 1, #s do
		local b = string.byte(s, i)
		if b < 32 or b > 126 then return false end
	end
	return true
end

--============================================================ code lines: every (A, B)
for _, L in { 3, 4 } do
	local seen = {}
	local forms = 0
	for a = 0, L do
		for b = 0, L - a do
			if not (a == L and b == 0) then
				forms += 1
				local s = Text.codeSentence(a, b)
				truthy(type(s) == "string" and #s > 5, string.format("L%d (%d,%d) has a sentence", L, a, b))
				truthy(ascii(s), string.format("L%d (%d,%d) sentence is plain ASCII: %s", L, a, b, tostring(s)))
				truthy(not seen[s], string.format("L%d (%d,%d) sentence is unique", L, a, b))
				seen[s] = true
				local pa, pb = Text.parseCodeSentence(s)
				eq(pa, a, string.format("L%d (%d,%d) parses back A", L, a, b))
				eq(pb, b, string.format("L%d (%d,%d) parses back B", L, a, b))
			end
		end
	end
	truthy(forms >= 9, "L" .. L .. " covers at least 9 forms")
end
eq(Text.codeSentence(0, 0), "Nothing is correct.", "(0,0)")
eq(Text.codeSentence(1, 0), "One digit is correct and well placed.", "(1,0)")
eq(Text.codeSentence(2, 0), "Two digits are correct and well placed.", "(2,0)")
eq(Text.codeSentence(0, 1), "One digit is correct but wrongly placed.", "(0,1)")
eq(Text.codeSentence(1, 1), "One digit is correct and well placed, one is correct but wrongly placed.", "(1,1)")
eq(Text.parseCodeSentence("gibberish"), nil, "an unknown sentence does not parse")

eq(Text.codeGuess({ 4, 8, 1 }), "4 8 1", "a guess reads as spaced digits")
do
	local g = Text.parseCodeGuess("4 8 1")
	eq(g and table.concat(g) or "", "481", "spaced digits parse back")
	eq(Text.parseCodeGuess("4 x 1"), nil, "a non-digit does not parse")
end

--============================================================ shelf clues: every type, every colour pair
do
	local names = Text.FlaskNames
	eq(#names, 5, "five flask colours")
	eq(table.concat(Text.FlaskLetters), "RBGYP", "letters R B G Y P")
	local types = { "left", "adj", "notadj", "notslot", "atend", "notend" }
	local seen = {}
	for _, t in types do
		for a = 1, 5 do
			for b = 1, 5 do
				if a ~= b then
					for k = 1, 5 do
						local clue = { t = t, a = a, b = b, k = k }
						local s = Text.shelfClue(clue)
						truthy(type(s) == "string" and #s > 5 and ascii(s), "shelf clue " .. t .. " renders ASCII")
						local back = Text.parseShelfClue(s)
						local same = back ~= nil and back.t == t and back.a == a
						if t == "left" or t == "adj" or t == "notadj" then same = same and back.b == b end
						if t == "notslot" then same = same and back.k == k end
						if not same then
							failed += 1
							print("FAIL: shelf clue does not parse back: " .. s)
						else
							passed += 1
						end
						seen[t] = true
					end
				end
			end
		end
	end
	for _, t in types do truthy(seen[t], "clue type " .. t .. " covered") end
	eq(Text.shelfClue({ t = "left", a = 1, b = 2 }), "Red stands somewhere left of Blue.", "left")
	eq(Text.shelfClue({ t = "notslot", a = 3, k = 2 }), "Green is not in slot 2.", "notslot")
	eq(Text.shelfClue({ t = "atend", a = 4 }), "Yellow stands at one end.", "atend")
	eq(Text.shelfClue({ t = "notend", a = 5 }), "Purple is not at either end.", "notend")
	eq(Text.parseShelfClue("Red is in slot 2."), nil, "an answer is not a clue sentence")
end

--============================================================ hints and room text are plain ASCII too
truthy(ascii(Text.doorHint(2, 7)) and Text.doorHint(2, 7) == "Digit 2 is 7.", "door hint")
truthy(ascii(Text.shelfHint(3, 3)) and Text.shelfHint(3, 3) == "Green goes in slot 3.", "shelf hint")
truthy(ascii(Text.lampHint(5, 3)), "lamp hint")
for _, key in { "LampRule", "ShelfRule", "DoorRule", "DoorDark" } do
	truthy(type(Text[key]) == "string" and ascii(Text[key]), "rule text " .. key .. " is ASCII")
end

print(string.format("Text: %d passed, %d failed", passed, failed))
if failed > 0 then error("Text spec failed", 0) end
