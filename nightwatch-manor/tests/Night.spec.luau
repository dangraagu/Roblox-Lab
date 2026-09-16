-- Pure tests for Night (how a night ends and what it pays).
-- Run from the game directory: luau tests/Night.spec.luau
--
-- Everything the player actually keeps is decided here. The failure modes are all silent and
-- all economic: a death that pays out, an extraction that does not, a night counter that runs
-- away, a best-night record that goes down.
local Night = require("../src/shared/Night")
local Upgrades = require("../src/shared/Upgrades")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function _approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local N = Config.Night
local NONE = Upgrades.effects(Config, {})

--============================================================================== relic worth

do
	eq(Night.relicWorth(Config, "trinket"), 10, "a trinket is worth what the catalog says")
	eq(Night.relicWorth(Config, "heart"), 150, "so is the rarest relic")
	eq(Night.relicWorth(Config, "not_a_relic"), 0, "an unknown relic is worth nothing, not nil")
	eq(Night.tierById(Config, "portrait").name, "Cursed Portrait", "tierById finds a tier")
	eq(Night.tierById(Config, "nope"), nil, "tierById on an unknown id -> nil")

	eq(Night.carriedWorth(Config, {}), 0, "an empty bag is worth nothing")
	eq(Night.carriedWorth(Config, { "trinket", "trinket", "heart" }), 170, "a bag is the sum of its relics")
	eq(Night.carriedWorth(Config, { "trinket", "junk" }), 10, "junk in the bag adds nothing")
end

do
	eq(Night.payout(Config, { "trinket" }, NONE), 10, "with no vault a relic banks for its worth")
	local vault = Upgrades.effects(Config, { relicvault = 2 })
	local expect = math.floor(10 * (1 + vault.relicValue))
	eq(Night.payout(Config, { "trinket" }, vault), expect, "the Relic Vault multiplies the payout")
	truthy(Night.payout(Config, { "trinket" }, vault) > Night.payout(Config, { "trinket" }, NONE),
		"...upward, which is the whole point of buying it")
	eq(Night.payout(Config, {}, vault), 0, "a multiplier on an empty bag is still nothing")
	eq(Night.payout(Config, { "heart" }, vault), math.floor(Night.payout(Config, { "heart" }, vault)),
		"payouts are whole relics")
end

--=========================================================================== how long you get

do
	eq(Night.dreadSeconds(Config, 1, NONE), N.DreadSeconds, "night 1 gives the full DreadSeconds")
	truthy(Night.dreadSeconds(Config, 10, NONE) < Night.dreadSeconds(Config, 1, NONE),
		"later nights are shorter")
	eq(Night.dreadSeconds(Config, 100000, NONE), N.DreadMin, "the night never shrinks past DreadMin")

	local lights = Upgrades.effects(Config, { floodlights = 2 })
	truthy(Night.dreadSeconds(Config, 1, lights) > Night.dreadSeconds(Config, 1, NONE),
		"floodlights buy you more time")
	local wards = Upgrades.effects(Config, { wardstones = 3 })
	truthy(Night.dreadSeconds(Config, 1, wards) > Night.dreadSeconds(Config, 1, NONE),
		"wardstones make the manor wake up slower")
	-- Even fully upgraded the night has to END, or the tycoon loop never runs.
	local everything = {}
	for _, e in Config.Upgrades.Catalog do everything[e.id] = e.max end
	local maxed = Upgrades.effects(Config, everything)
	truthy(Night.dreadSeconds(Config, 1, maxed) < math.huge, "a fully built safehouse still ends the night")
	truthy(Night.dreadSeconds(Config, 1, maxed) < 900, "and it does not turn one night into 15 minutes")
end

--=============================================================================== start state

do
	local s = Night.startState(Config, { night = 4, stash = 120, best = 3 })
	eq(s.night, 4, "the run starts on the night the profile is on")
	eq(s.stash, 120, "with the relics the profile banked")
	eq(s.best, 3, "and the record it already holds")
	eq(#s.carried, 0, "carrying nothing")
	local fresh = Night.startState(Config, {})
	eq(fresh.night, N.StartNight, "a brand new player starts on StartNight")
	eq(fresh.stash, N.StartStash, "with StartStash relics")
	eq(fresh.best, 0, "and no record")
	-- A corrupt save must not put anybody on night 0 or night -12.
	eq(Night.startState(Config, { night = 0 }).night, N.StartNight, "night 0 is corrected to StartNight")
	eq(Night.startState(Config, { night = -12 }).night, N.StartNight, "so is a negative night")
	eq(Night.startState(Config, { night = 99999 }).night, N.MaxNight, "and a night past the cap is clamped")
end

--=================================================================================== resolve

do
	local state = { night = 3, stash = 100, best = 2, carried = { "trinket", "portrait" } }
	local worth = Night.carriedWorth(Config, state.carried) -- 35

	local after, res = Night.resolve(state, Night.EXTRACTED, Config, NONE)
	eq(res.outcome, Night.EXTRACTED, "the result names the outcome")
	eq(res.gained, worth, "getting out banks the whole bag")
	eq(res.lost, 0, "and loses nothing")
	eq(after.stash, 100 + worth, "the stash grows by exactly the payout")
	eq(after.night, 4, "surviving moves you on to the next night")
	eq(after.best, 3, "and the record is the night you just survived")
	eq(#after.carried, 0, "your hands are empty again")
	-- The input must be untouched: the server resolves first and persists after.
	eq(state.stash, 100, "resolve does not mutate the state it was handed")
	eq(#state.carried, 2, "...including the bag")
end

do
	-- Caught with no Lockbox: you lose the lot and you do NOT advance.
	local state = { night = 3, stash = 100, best = 5, carried = { "heart" } }
	local after, res = Night.resolve(state, Night.CAUGHT, Config, NONE)
	eq(res.gained, 0, "caught with no lockbox banks nothing")
	eq(res.lost, 150, "the whole haul is gone")
	eq(after.stash, 100, "the stash is unchanged")
	eq(after.night, 3, "you retry the SAME night rather than losing your progress")
	eq(after.best, 5, "a death never lowers your record")
	eq(#after.carried, 0, "and the bag is empty either way")
end

do
	-- With a Lockbox you keep a slice. Rounding must never invent a relic out of nothing.
	local lock = Upgrades.effects(Config, { lockbox = 1 })
	local state = { night = 2, stash = 0, best = 0, carried = { "heart" } }
	local after, res = Night.resolve(state, Night.CAUGHT, Config, lock)
	local expect = math.floor(150 * lock.keepOnCaught)
	eq(res.gained, expect, "the lockbox keeps its fraction")
	eq(res.lost, 150 - expect, "and the rest is lost")
	eq(res.gained + res.lost, 150, "kept plus lost is exactly what you were carrying")
	eq(after.stash, expect, "the kept slice reaches the stash")
	truthy(res.gained > 0, "a bought lockbox actually does something")
end

do
	-- Thrown out at full dread. Different message, same economics as being caught — and the
	-- night must not advance, or running out the clock would be a free way to progress.
	local state = { night = 7, stash = 10, best = 6, carried = { "reliquary" } }
	local after, res = Night.resolve(state, Night.EVICTED, Config, NONE)
	eq(res.outcome, Night.EVICTED, "eviction is its own outcome so the HUD can say what happened")
	eq(res.gained, 0, "being thrown out banks nothing")
	eq(after.night, 7, "and does not advance the night")
	eq(after.best, 6, "nor the record")
end

do
	-- An empty-handed extraction is legal and must still count as surviving the night.
	local state = { night = 1, stash = 0, best = 0, carried = {} }
	local after, res = Night.resolve(state, Night.EXTRACTED, Config, NONE)
	eq(res.gained, 0, "leaving empty-handed pays nothing")
	eq(after.night, 2, "but you still survived the night")
	eq(after.best, 1, "and it counts for the record")
end

do
	-- The night counter has to stop somewhere.
	local state = { night = N.MaxNight, stash = 0, best = N.MaxNight, carried = {} }
	local after = Night.resolve(state, Night.EXTRACTED, Config, NONE)
	eq(after.night, N.MaxNight, "the night counter clamps at MaxNight")
	eq(after.best, N.MaxNight, "and so does the record")
end

do
	-- An outcome nobody defined must be LOUD. Silently treating it as a survival would hand out
	-- free nights forever, and treating it as a death would eat hauls for free.
	local state = { night = 1, stash = 0, best = 0, carried = { "trinket" } }
	local ok = pcall(function()
		return Night.resolve(state, "WANDERED_OFF", Config, NONE)
	end)
	falsy(ok, "an unknown outcome raises instead of guessing")
end

do
	eq(Night.bestAfter(3, 5), 5, "a better night raises the record")
	eq(Night.bestAfter(9, 5), 9, "a worse one leaves it alone")
	eq(Night.bestAfter(0, 1), 1, "the first survival sets it")
end

--============================================================================== CONTROL
-- A change the suite must NOT notice: relic NAMES. Worth is load-bearing, the name on the
-- pedestal is not. If renaming "Cursed Portrait" turns this red, the economics tests are
-- reading flavour text.
do
	local tier = Night.tierById(Config, "portrait")
	local before = tier.name
	tier.name = "Weeping Portrait"
	local state = { night = 2, stash = 5, best = 1, carried = { "portrait" } }
	local after, res = Night.resolve(state, Night.EXTRACTED, Config, NONE)
	local ok = res.gained == 25 and after.stash == 30 and after.night == 3
	tier.name = before
	truthy(ok, "CONTROL: renaming a relic changes nothing it is worth")
end

print(string.format("Night: %d passed, %d failed", passed, failed))
if failed > 0 then error("Night tests failed") end
