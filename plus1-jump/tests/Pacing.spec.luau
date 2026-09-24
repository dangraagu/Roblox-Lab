-- Pacing: does a normal player reach SPACE in 30-45 minutes of play? Run: luau tests/Pacing.spec.luau
--
-- There is no telemetry for this game yet, so "time to altitude" is MEASURED with a model, and the
-- model is written down rather than hidden in a number:
--
--   * the tower is the real one: Progression.stepHeight / jumpHeight / climbHeight from Config;
--   * a jump's airtime is real Roblox physics for that jump height and step (Workspace gravity 196.2);
--   * the HUMAN part is Config.Pacing.Profiles: seconds spent lining up a jump, the share of jumps
--     missed, and seconds to recover after the rescue puts you back. A miss costs the fall to the
--     rescue line (the server rescues 60 studs under the tier) plus half the 0.4 s rescue poll;
--   * hazards are included: the hit share is MEASURED by flying Config.Hazards at a climber on the
--     real tower who never reacts to a warning (tests/ClimbModel.luau `measureHazards`), which
--     over-states the cost for anyone who does;
--   * resting is excluded — the target is minutes of PLAY.
--
-- "Normal player" = the `normal` profile, no codes. The promise is asserted for a player who never
-- rebirths and for one who takes the first rebirth. A player who presses REBIRTH every time the HUD lights
-- it is an OWNER DECISION (review round 2, finding 2): by default the HUD lights every rebirth the server
-- allows, as it did before the sky, and that player reaches space after far more than 45 min. With the
-- owner's option `Config.Rebirth.HighlightFirstRebirths = 1` the same player is back in the window; both
-- are measured below, so the numbers in EYECANDY.md stay true whichever way he decides.
-- A band is REACHED when the climber stands on the first platform of tier `from` (the tier number the
-- HUD and board show). The other rows (fast, slow, rebirths at 10/18/26) are printed for EYECANDY.md.
local ClimbModel = require("./ClimbModel")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local bands = Config.Env.Bands
local profiles = Config.Pacing.Profiles
truthy(profiles.normal ~= nil and profiles.fast ~= nil and profiles.slow ~= nil, "fast/normal/slow profiles exist")

local spaceIdx = EnvBands.indexOf(bands, Config.Env.SpaceBandId)
truthy(spaceIdx ~= nil, "the band called space (Config.Env.SpaceBandId) exists")
local galaxyIdx = #bands

--================================================================ the model is sane

do
	local slow = ClimbModel.secondsPerPlatform(20, profiles.slow, 1, Config)
	local normal = ClimbModel.secondsPerPlatform(20, profiles.normal, 1, Config)
	local fast = ClimbModel.secondsPerPlatform(20, profiles.fast, 1, Config)
	truthy(fast < normal and normal < slow, "fast < normal < slow per platform")
	truthy(normal > 1.5 and normal < 12, "a normal platform takes a plausible 1.5-12 s (" .. string.format("%.2f", normal) .. ")")
end
do
	-- airtime is physics, not a constant: a 60-stud jump onto a 44-stud step
	local air = ClimbModel.airtime(60, 44, Config.Pacing.Gravity)
	truthy(math.abs(air - (math.sqrt(120 / 196.2) + math.sqrt(32 / 196.2))) < 1e-9, "airtime is ballistic up + down")
end
do
	local t1 = ClimbModel.minutesToProgress(10, profiles.normal, Config, {})
	local t2 = ClimbModel.minutesToProgress(20, profiles.normal, Config, {})
	truthy(t2 > t1 * 1.5, "twenty tiers take clearly longer than ten")
	local r = ClimbModel.minutesToProgress(20, profiles.normal, Config, { rebirthAt = { 10 } })
	truthy(r > t2, "rebirthing at 10 and climbing back to 20 costs extra time")
end
do
	local bad = pcall(function()
		ClimbModel.minutesToProgress(30, profiles.normal, Config, { rebirthAt = { 5 } })
	end)
	eq(bad, false, "the model refuses a rebirth the game would refuse (tier 5 < FirstTierRequired)")
end
do
	-- the follower model: a HUD that highlights every possible rebirth walks the player through 10, 18, 26 ...
	local always = ClimbModel.followHighlights(85, Config, function(tier, _, rebirths)
		return Progression.canRebirth(tier, rebirths, Config.Rebirth)
	end)
	eq(table.concat(always, ","), "10,18,26,34,42,50,58,66,74,82", "a player who takes EVERY rebirth offered before tier 85 takes ten")
	eq(#ClimbModel.followHighlights(85, Config, function() return false end), 0, "one who takes none takes none")
	truthy(ClimbModel.minutesToTier(85, profiles.normal, Config, { rebirthAt = always }) > 45,
		"and ten rebirths put space far outside the window: why the HUD must not highlight them all")
end

--================================================================ hazard cost is measured

-- Two bounding behaviours, both on the real tower from tier 20, 6 h each. A near-hit is a hazard
-- passing within Config.Hazards.NearMissStuds of the player's centre.
local hz = ClimbModel.measureHazards(profiles.normal, Config, { hours = 6, seed = 424242, startTier = 20, behavior = "ignore" })
local stop = ClimbModel.measureHazards(profiles.normal, Config, { hours = 6, seed = 424242, startTier = 20, behavior = "stop" })
for _, m in { { "ignores every warning", hz }, { "stops + sidesteps at the lock", stop } } do
	print(string.format("  climber who %-30s %.3f hazards/min, %.3f near-hits/min (<= %d studs), %.3f hits/min, hit share %.2f",
		m[1], m[2].perMinute, m[2].nearPerMinute, Config.Hazards.NearMissStuds, m[2].hitsPerMinute, m[2].hitShare))
end
truthy(hz.perMinute >= 1 / 3 and hz.perMinute <= 1 / 2, "on the real tower: one hazard per 2-3 min of climbing")
truthy(stop.nearPerMinute >= 1 / 3.2 and stop.nearPerMinute <= 1 / 2,
	"a player who reacts to the warning gets about one near-hit per 2-3 min (" .. string.format("%.3f", stop.nearPerMinute) .. "/min)")
eq(stop.hits, 0, "and a half-tile sidestep at the lock dodges EVERY one of them (" .. stop.spawns .. " hazards)")
-- Review round 2: the dodge must not depend on the direction. The same climber, 3 h each, walking half a
-- tile in eight directions measured from the lane's travel (0 = straight back, away from the hazard;
-- 180 = toward it). Before the fix only 90 and 270 dodged; backing away was hit every time.
do
	local worst, worstHits, spawns = nil, 0, 0
	local cells = {}
	for _, deg in { 0, 45, 90, 135, 180, 225, 270, 315 } do
		local m = ClimbModel.measureHazards(profiles.normal, Config, { hours = 3, seed = 7, startTier = 20, behavior = "stop", dodgeDegrees = deg })
		table.insert(cells, string.format("%d deg %d/%d", deg, m.hits, m.spawns))
		spawns += m.spawns
		if m.hits > worstHits then worst, worstHits = deg, m.hits end
	end
	print("  climber who stops and walks half a tile at the lock, hits by direction: " .. table.concat(cells, ", "))
	eq(worstHits, 0, "walking half a tile at the lock dodges in EVERY direction, backing away included ("
		.. spawns .. " hazards" .. (if worst then "; worst " .. worst .. " deg" else "") .. ")")
end
truthy(hz.hitShare < 0.5,
	"a player who ignores warnings but keeps climbing is hit by fewer than half (" .. string.format("%.2f", hz.hitShare) .. ")")
truthy(hz.nearPerMinute > 0 and hz.hitsPerMinute <= 1 / 5,
	"and at most once per 5 minutes (" .. string.format("%.3f", hz.hitsPerMinute) .. "/min)")

--================================================================ time to each band

local function row(name, profile, opts)
	local cells = {}
	for i, b in ipairs(bands) do
		local m = ClimbModel.minutesToTier(b.from, profile, Config, opts, hz.hitShare)
		cells[i] = string.format("%s %5.1f", b.id, m)
	end
	print(string.format("  %-22s %s", name, table.concat(cells, " | ")))
end
print("  minutes of play to stand in each band's first tier (Tier `from` on the HUD):")
-- the player who presses REBIRTH whenever the HUD highlights it (Progression.rebirthHighlighted): with the
-- default Config (every rebirth lit, as before the sky) and with the owner's first-only option
local firstOnly = table.clone(Config.Rebirth)
firstOnly.HighlightFirstRebirths = 1
local function lit(rb)
	return function(tier, best, rebirths)
		return Progression.rebirthHighlighted(tier, best, rebirths, rb)
	end
end
local followSpaceDefault = ClimbModel.followHighlights(bands[spaceIdx].from, Config, lit(Config.Rebirth))
local followSpace = ClimbModel.followHighlights(bands[spaceIdx].from, Config, lit(firstOnly))
local followGalaxy = ClimbModel.followHighlights(bands[galaxyIdx].from, Config, lit(firstOnly))
row("normal", profiles.normal, {})
row("normal, rebirth @10", profiles.normal, { rebirthAt = { 10 } })
row("normal, follows HUD (first-only option)", profiles.normal, { rebirthAt = followGalaxy })
row("normal, rebirth @10,18", profiles.normal, { rebirthAt = { 10, 18 } })
row("normal, rebirth @10,18,26", profiles.normal, { rebirthAt = { 10, 18, 26 } })
row("fast", profiles.fast, {})
row("slow", profiles.slow, {})

local target = Config.Pacing.SpaceMinutes
local spaceFrom = bands[spaceIdx].from
local normalSpace = ClimbModel.minutesToTier(spaceFrom, profiles.normal, Config, {}, hz.hitShare)
local rebirthSpace = ClimbModel.minutesToTier(spaceFrom, profiles.normal, Config, { rebirthAt = { 10 } }, hz.hitShare)
local followerSpace = ClimbModel.minutesToTier(spaceFrom, profiles.normal, Config, { rebirthAt = followSpace }, hz.hitShare)
local followerDefault = ClimbModel.minutesToTier(spaceFrom, profiles.normal, Config, { rebirthAt = followSpaceDefault }, hz.hitShare)
print(string.format("  SPACE = tier %d: normal %.1f min, with one rebirth %.1f min (target %d-%d)", spaceFrom, normalSpace, rebirthSpace, target[1], target[2]))
print(string.format("  pressing every LIT REBIRTH: default HUD (at %s) %.1f min; first-only option (at %s) %.1f min",
	table.concat(followSpaceDefault, ","), followerDefault, table.concat(followSpace, ","), followerSpace))
truthy(normalSpace >= target[1] and normalSpace <= target[2],
	"a normal player reaches space in " .. target[1] .. "-" .. target[2] .. " min (" .. string.format("%.1f", normalSpace) .. ")")
truthy(rebirthSpace >= target[1] and rebirthSpace <= target[2],
	"and still does after taking the first rebirth (" .. string.format("%.1f", rebirthSpace) .. ")")
truthy(followerSpace >= target[1] and followerSpace <= target[2],
	"with the owner's first-only option, a normal player who presses REBIRTH every time it is lit reaches space in the window too ("
		.. string.format("%.1f", followerSpace) .. " min, rebirths at " .. table.concat(followSpace, ",") .. ")")
-- the decision EYECANDY.md puts to the owner is real: with the default HUD (as before the sky) the same player
-- misses the window. If this ever fails, rebirth's value or the HUD changed: update EYECANDY.md §2 and §11.
truthy(followerDefault > target[2],
	"with the default HUD (every rebirth lit, as before the sky) a player who presses every lit REBIRTH misses the window ("
		.. string.format("%.1f", followerDefault) .. " min, rebirths at " .. table.concat(followSpaceDefault, ",") .. "): the owner's call")
-- the centre of the window, not an edge: a retune that drifts a few minutes must not silently leave it
truthy(math.abs(normalSpace - (target[1] + target[2]) / 2) <= 5,
	"the space band sits near the MIDDLE of the window (" .. string.format("%.1f", normalSpace) .. " min)")

-- the galaxy is the long-term goal: clearly beyond space, but not unreachable
local galaxyNormal = ClimbModel.minutesToTier(bands[galaxyIdx].from, profiles.normal, Config, {}, hz.hitShare)
local galaxyFollower = ClimbModel.minutesToTier(bands[galaxyIdx].from, profiles.normal, Config, { rebirthAt = followGalaxy }, hz.hitShare)
truthy(galaxyNormal >= 2 * normalSpace, "leaving the galaxy is a long-term goal: at least twice the time to space ("
	.. string.format("%.1f", galaxyNormal) .. " min)")
truthy(galaxyNormal <= 180, "but reachable in a few sessions (under 3 h of play)")
truthy(galaxyFollower <= 180, "also, with the first-only option, for a player who presses every lit REBIRTH ("
	.. string.format("%.1f", galaxyFollower) .. " min)")

-- the float-precision ceiling: the last band must start where Roblox still renders cleanly
local galaxyY = require("../src/shared/Progression").yAtProgress(bands[galaxyIdx].from, Config.Tower)
print(string.format("  last band starts at y = %.0f studs", galaxyY))
truthy(galaxyY < 100000, "the last band starts below 100 000 studs (float precision)")

-- every band is reached in order, each strictly later
do
	local prev, ok = -1, true
	for _, b in ipairs(bands) do
		local m = ClimbModel.minutesToTier(b.from, profiles.normal, Config, {}, hz.hitShare)
		if m <= prev then ok = false end
		prev = m
	end
	truthy(ok, "bands are reached strictly one after another")
end
-- no band flashes by: each lasts at least two minutes for a normal player
do
	local shortest, which = math.huge, nil
	for i = 1, #bands - 1 do
		local a = ClimbModel.minutesToTier(bands[i].from, profiles.normal, Config, {}, hz.hitShare)
		local b = ClimbModel.minutesToTier(bands[i + 1].from, profiles.normal, Config, {}, hz.hitShare)
		if b - a < shortest then shortest, which = b - a, bands[i].id end
	end
	truthy(shortest >= 2, "every band lasts at least 2 min of normal play (shortest: " .. tostring(which) .. " "
		.. string.format("%.1f", shortest) .. ")")
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
assert(failed == 0, "Pacing tests failed")
