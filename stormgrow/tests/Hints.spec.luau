-- Spec for Hints: the one-line hint under the farm, from state alone. Run: luau tests/Hints.spec.luau
--
-- DESIGN.md §11: the first 60 seconds are taught by hints that come from STATE (harvests, empty and ripe
-- tiles, coins) and need no tutorial flag, so a returning player with a planted farm never sees them. After
-- that the same line carries the forecast's hold cue, the core decision of the game.
local Hints = require("../src/shared/Hints")
local Config = require("../src/shared/Config")
local Weather = require("../src/shared/Weather")

local passed, failed = 0, 0
local function has(text, needle, msg)
	if type(text) == "string" and string.find(text, needle, 1, true) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(text))
	end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local HOUR = 1790002800
local function st(over)
	local s = {
		now = HOUR + 200, harvests = 0, planted = 0, owned = 9, ripe = 0, ripeValue = 0, coins = 20,
		unlocked = 1, fields = 1, heldMarked = 0,
	}
	for k, v in over or {} do s[k] = v end
	return s
end

has(Hints.pick(st(), Config, Weather), "Tap a glowing tile to plant a Radish (free)", "a brand-new farm: plant")
has(Hints.pick(st({ planted = 3 }), Config, Weather), "Plant the rest", "some planted: plant the rest")
has(Hints.pick(st({ planted = 9, ripe = 2, ripeValue = 5 }), Config, Weather), "Ripe! Tap to harvest", "ripe crops: harvest")
has(Hints.pick(st({ planted = 9, ripe = 2, ripeValue = 5 }), Config, Weather), "(+5)", "and names what one sells for")
has(Hints.pick(st({ planted = 9, harvests = 9, coins = 65 }), Config, Weather), "Unlock the Carrot", "enough coins: unlock the Carrot")
has(Hints.pick(st({ planted = 9, harvests = 9, coins = 65 }), Config, Weather), "50", "at its price")

-- the hold cue: an event within 60 s, ripe crops in the ground
has(Hints.pick(st({ now = HOUR - 42, planted = 9, harvests = 40, ripe = 3, coins = 5000, unlocked = 4 }), Config, Weather),
	"Storm in 0:42", "60 s before a storm with ripe crops: the hold cue")
has(Hints.pick(st({ now = HOUR - 42, planted = 9, harvests = 40, ripe = 3, coins = 5000, unlocked = 4 }), Config, Weather),
	"Charged (x5)", "and what the storm does")
has(Hints.pick(st({ now = HOUR + 30, planted = 9, harvests = 40, ripe = 3, coins = 5000, unlocked = 4 }), Config, Weather),
	"STORM", "during the storm, with ripe crops: say so")
has(Hints.pick(st({ now = HOUR + 300 - 20, planted = 9, harvests = 40, ripe = 1, coins = 5000, unlocked = 4 }), Config, Weather),
	"Frosted (x5)", "before a frost the cue names Frosted")
has(Hints.pick(st({ now = HOUR + 100, planted = 9, harvests = 40, ripe = 1, coins = 5000, unlocked = 4 }), Config, Weather),
	"Prismatic (x8)", "during a rainbow the cue names Prismatic")
has(Hints.pick(st({ now = HOUR + 30, planted = 9, harvests = 40, ripe = 0, heldMarked = 2, coins = 5000, unlocked = 4 }), Config, Weather),
	"tap", "marked crops the running event cannot improve: tap them")

-- a returning player with a planted farm, clear sky, nothing to cue: no hint at all
eq(Hints.pick(st({ now = HOUR + 200, planted = 27, owned = 27, harvests = 500, coins = 900, unlocked = 3, fields = 3 }), Config, Weather), nil,
	"a returning player with a planted farm sees no tutorial hint")
-- never tutorial text once they have harvested plenty, even with an empty tile
eq(Hints.pick(st({ now = HOUR + 200, planted = 20, owned = 27, harvests = 500, coins = 900, unlocked = 3, fields = 3 }), Config, Weather), nil,
	"an experienced player with a free tile is not told how to plant")

print(string.format("Hints: %d passed, %d failed", passed, failed))
assert(failed == 0, "Hints tests failed")
