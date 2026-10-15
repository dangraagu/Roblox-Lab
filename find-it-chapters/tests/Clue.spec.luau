-- Spec for Clue: traits, clue forms, matching, words and glyphs (DESIGN.md §3.1-3.2).
-- Run: luau tests/Clue.spec.luau 2>&1
local Clue = require("../src/shared/Clue")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local blueBoxHigh = { kind = "box", colour = "blue", height = "high" }
local blueJarTable = { kind = "jar", colour = "blue", height = "table" }
local whiteBoxFloor = { kind = "box", colour = "white", height = "floor" }

--============================================================ matching
truthy(Clue.matches(blueBoxHigh, { form = "K", kind = "box" }, Config), "K: any BOX fits 'a BOX'")
truthy(Clue.matches(whiteBoxFloor, { form = "K", kind = "box" }, Config), "K ignores colour and height")
truthy(not Clue.matches(blueJarTable, { form = "K", kind = "box" }, Config), "a JAR is not a BOX")
truthy(Clue.matches(blueBoxHigh, { form = "CK", colour = "blue", kind = "box" }, Config), "CK: a BLUE BOX")
truthy(not Clue.matches(whiteBoxFloor, { form = "CK", colour = "blue", kind = "box" }, Config), "CK needs the colour")
truthy(Clue.matches(blueJarTable, { form = "CH", colour = "blue", height = "table" }, Config), "CH: BLUE on a TABLE")
truthy(not Clue.matches(blueBoxHigh, { form = "CH", colour = "blue", height = "table" }, Config), "CH needs the height")
truthy(Clue.matches(blueBoxHigh, { form = "KH", kind = "box", height = "high" }, Config), "KH: a BOX up HIGH")
truthy(not Clue.matches(whiteBoxFloor, { form = "KH", kind = "box", height = "high" }, Config), "KH needs the height")
-- a clue's unused traits never matter, even when present in the table
truthy(Clue.matches(blueJarTable, { form = "K", kind = "jar", colour = "green", height = "floor" }, Config),
	"traits the form does not name are ignored")

--============================================================ subsumption: a clue that contains another
truthy(Clue.subsumes({ form = "K", kind = "box" }, { form = "CK", colour = "blue", kind = "box" }, Config),
	"every BLUE BOX is a BOX: 'a BOX' subsumes 'a BLUE BOX'")
truthy(not Clue.subsumes({ form = "CK", colour = "blue", kind = "box" }, { form = "K", kind = "box" }, Config),
	"but not the other way")
truthy(Clue.overlaps({ form = "CK", colour = "blue", kind = "box" }, { form = "K", kind = "box" }, Config),
	"overlaps is symmetric")
truthy(not Clue.overlaps({ form = "CK", colour = "blue", kind = "box" }, { form = "CH", colour = "blue", height = "high" }, Config),
	"a BLUE BOX and BLUE up HIGH do not contain each other (they share props, which the generator rules out by construction)")
truthy(Clue.overlaps({ form = "CK", colour = "blue", kind = "box" }, { form = "CK", colour = "blue", kind = "box" }, Config),
	"a clue overlaps an identical clue")

--============================================================ words, labels, glyphs [DESIGN §3.2, §17.2]
eq(Clue.words({ form = "K", kind = "basket" }, Config), "a BASKET", "K words")
eq(Clue.words({ form = "CK", colour = "blue", kind = "box" }, Config), "a BLUE BOX", "CK words")
eq(Clue.words({ form = "CH", colour = "yellow", height = "high" }, Config), "something YELLOW up HIGH", "CH words, high")
eq(Clue.words({ form = "CH", colour = "white", height = "table" }, Config), "something WHITE on a TABLE", "CH words, table")
eq(Clue.words({ form = "KH", kind = "jar", height = "floor" }, Config), "a JAR on the FLOOR", "KH words, floor")
eq(Clue.label(blueBoxHigh, Config), "BLUE BOX \u{00B7} HIGH", "the label chip of a selected prop names all three traits")
eq(Clue.label(whiteBoxFloor, Config), "WHITE BOX \u{00B7} FLOOR", "floor label")
eq(Clue.name(whiteBoxFloor, Config), "WHITE BOX", "the name used in 'That WHITE BOX doesn't fit...'")
do
	local g = Clue.glyphs({ form = "CH", colour = "yellow", height = "high" }, Config)
	eq(#g, 2, "a two-trait clue is two glyphs")
	eq(g[1].trait, "colour", "colour first")
	eq(g[1].value, "yellow", "the swatch value")
	eq(g[1].letter, "Y", "a colour swatch carries its initial letter (colour-blind fallback)")
	eq(g[2].trait, "height", "then the height arrow")
	local k = Clue.glyphs({ form = "K", kind = "chest" }, Config)
	eq(#k, 1, "a one-trait clue is one glyph")
	eq(k[1].trait, "kind", "the kind silhouette")
end

--============================================================ validation
truthy(Clue.validProp(blueBoxHigh, Config), "a prop with three known traits is valid")
truthy(not Clue.validProp({ kind = "box", colour = "red", height = "high" }, Config), "red is never a prop colour")
truthy(not Clue.validProp({ kind = "box", colour = "gold", height = "high" }, Config), "gold is never a prop colour")
truthy(not Clue.validProp({ kind = "lamp", colour = "blue", height = "high" }, Config), "unknown kinds are invalid")
truthy(Clue.validClue({ form = "CH", colour = "green", height = "floor" }, Config), "a valid CH clue")
truthy(not Clue.validClue({ form = "CH", colour = "green" }, Config), "a clue missing a named trait is invalid")
truthy(not Clue.validClue({ form = "XY", colour = "green" }, Config), "an unknown form is invalid")

--============================================================ every form names traits that exist, none reserved
do
	local ok = true
	for name, attrs in Config.Forms do
		for _, a in attrs do
			if a ~= "kind" and a ~= "colour" and a ~= "height" then ok = false end
		end
	end
	truthy(ok, "every form names only kind / colour / height")
	for _, c in Config.Traits.Colours do
		truthy(c ~= "red" and c ~= "gold", "clue colour " .. c .. " is neither red nor gold")
		truthy(Config.Traits.RGB[c] ~= nil, "clue colour " .. c .. " has an RGB")
	end
	eq(#Config.Traits.Kinds, 8, "8 kinds")
	eq(#Config.Traits.Colours, 4, "4 colours")
	eq(#Config.Traits.Heights, 3, "3 heights")
end

print(string.format("Clue: %d passed, %d failed", passed, failed))
if failed > 0 then error("Clue spec failed", 0) end
