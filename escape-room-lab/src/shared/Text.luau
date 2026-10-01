--!strict
-- Text.luau — every sentence the Lab shows a player, and its exact inverse. Pure; no Roblox.
--
-- Two rules this module exists to keep (tests/Text.spec.luau pins both):
--   * a clue is a SENTENCE, never a coloured peg, and every (A, B) and every shelf clue type has one,
--     so a rare form can never render blank;
--   * every sentence parses back to the numbers it was made from. The headless walk reads the door
--     and the shelf the way a player does, from the rendered text, and solves from that alone
--     (DESIGN.md §3.5 invariant 4). A sentence that did not parse back would make that proof lie.
-- Clue sentences are plain ASCII (the HUD's own glyphs are a Studio question, DESIGN.md §20 item 18).

local Text = {}

Text.FlaskNames = { "Red", "Blue", "Green", "Yellow", "Purple" }
Text.FlaskLetters = { "R", "B", "G", "Y", "P" }

local WORDS = { "One", "Two", "Three", "Four", "Five" }

Text.LampRule = "Tap a lamp: it and its neighbours switch. Light them all."
Text.ShelfRule = "Tap two flasks to swap them. When every clue is true, pull TEST."
Text.DoorRule = "Every lit line is true for the code. No digit repeats."
Text.DoorDark = "The keypad is dark: solve %s to light the last line."

--============================================================================ door lines

-- The sentence for feedback (A in place, B misplaced). (L, 0) never occurs: that line is the answer.
function Text.codeSentence(a: number, b: number): string
	if a == 0 and b == 0 then
		return "Nothing is correct."
	end
	local function lead(n: number, tail: string): string
		if n == 1 then
			return "One digit is correct " .. tail
		end
		return WORDS[n] .. " digits are correct " .. tail
	end
	if b == 0 then
		return lead(a, "and well placed.")
	end
	if a == 0 then
		return lead(b, "but wrongly placed.")
	end
	local second = string.lower(WORDS[b]) .. (if b == 1 then " is" else " are") .. " correct but wrongly placed."
	return lead(a, "and well placed, " .. second)
end

-- sentence -> (a, b), built once from the renderer so the two can never disagree
local CODE_PARSE: { [string]: { number } } = {}
for a = 0, 5 do
	for b = 0, 5 - a do
		if a + b > 0 or (a == 0 and b == 0) then
			CODE_PARSE[Text.codeSentence(a, b)] = { a, b }
		end
	end
end

function Text.parseCodeSentence(s: string): (number?, number?)
	local ab = CODE_PARSE[s]
	if ab == nil then return nil, nil end
	return ab[1], ab[2]
end

function Text.codeGuess(guess: { number }): string
	local parts = {}
	for i, d in guess do parts[i] = tostring(d) end
	return table.concat(parts, " ")
end

function Text.parseCodeGuess(s: string): { number }?
	local out = {}
	for token in string.gmatch(s, "%S+") do
		local d = tonumber(token)
		if d == nil or string.match(token, "^%d$") == nil then return nil end
		table.insert(out, d)
	end
	if #out == 0 then return nil end
	return out
end

--============================================================================ shelf clues

-- clue = { t, a, b?, k? }; a and b are indices into FlaskNames, k a slot.
function Text.shelfClue(clue: any): string
	local A = Text.FlaskNames[clue.a]
	local B = if clue.b then Text.FlaskNames[clue.b] else "?"
	local t = clue.t
	if t == "left" then return A .. " stands somewhere left of " .. B .. "." end
	if t == "adj" then return A .. " stands right next to " .. B .. "." end
	if t == "notadj" then return A .. " does not stand next to " .. B .. "." end
	if t == "notslot" then return A .. " is not in slot " .. tostring(clue.k) .. "." end
	if t == "atend" then return A .. " stands at one end." end
	if t == "notend" then return A .. " is not at either end." end
	error("Text.shelfClue: unknown clue type " .. tostring(t))
end

local SHELF_PARSE: { [string]: any } = {}
for _, t in { "left", "adj", "notadj", "notslot", "atend", "notend" } do
	for a = 1, #Text.FlaskNames do
		for b = 1, #Text.FlaskNames do
			for k = 1, #Text.FlaskNames do
				local clue = { t = t, a = a, b = b, k = k }
				local s = Text.shelfClue(clue)
				if SHELF_PARSE[s] == nil then
					local stored: any = { t = t, a = a }
					if t == "left" or t == "adj" or t == "notadj" then stored.b = b end
					if t == "notslot" then stored.k = k end
					SHELF_PARSE[s] = stored
				end
			end
		end
	end
end

function Text.parseShelfClue(s: string): any
	local c = SHELF_PARSE[s]
	if c == nil then return nil end
	return table.clone(c)
end

--============================================================================ hints

function Text.doorHint(position: number, digit: number): string
	return "Digit " .. tostring(position) .. " is " .. tostring(digit) .. "."
end

function Text.shelfHint(color: number, slot: number): string
	return Text.FlaskNames[color] .. " goes in slot " .. tostring(slot) .. "."
end

function Text.lampHint(index: number, n: number): string
	local row = math.floor((index - 1) / n) + 1
	local col = (index - 1) % n + 1
	return "Try the lamp in row " .. tostring(row) .. ", column " .. tostring(col) .. "."
end

return Text
