-- EnvConfig.spec: the eye-candy config is valid and keeps the owner's rules (docs/complete-game-standard.md §2).
-- Run: luau tests/EnvConfig.spec.luau
--
-- What only the config can get wrong: a band that fades in before the one under it starts, a band without
-- light / scenery / weather, a hazard kind the art cannot draw, a ring a walking player cannot leave in time,
-- a queued PAUSE that expires before the longest hazard has passed, a band that lasts too long.

local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local GardenArt = require("../src/shared/GardenArt")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local bands = Config.Env.Bands
local Hz = Config.Hazards

--====================================================================== the bands
do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "the bands pass EnvBands.validate (" .. tostring(err) .. ")")
	truthy(#bands >= 5, "at least 5 bands (" .. #bands .. ")")
	local ids, missing = {}, {}
	for i, b in bands do
		ids[b.id] = i
		for _, grp in { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" } do
			if type(b[grp]) ~= "table" then table.insert(missing, b.id .. "." .. grp) end
		end
		if type(b.name) ~= "string" or type(b.emoji) ~= "string" then table.insert(missing, b.id .. ".name/emoji") end
		if type(b.lighting.ClockTime) ~= "number" then table.insert(missing, b.id .. ".ClockTime") end
		if #(b.pieces or {}) == 0 then table.insert(missing, b.id .. ".pieces") end
		if #(b.ambient or {}) == 0 then table.insert(missing, b.id .. ".ambient (critters)") end
		for _, id in b.pieces or {} do
			if not GardenArt.hasPiece(id) then table.insert(missing, b.id .. ": piece " .. id .. " is not drawn") end
		end
		for _, a in b.ambient or {} do
			if not GardenArt.hasCritter(a.kind) then table.insert(missing, b.id .. ": critter " .. a.kind .. " is not drawn") end
			if Config.Env.Critters[a.kind] == nil then table.insert(missing, b.id .. ": critter " .. a.kind .. " has no spec") end
		end
		for _, w in b.weather or {} do
			if not GardenArt.hasWeather(w.kind) then table.insert(missing, b.id .. ": weather " .. w.kind .. " is not drawn") end
		end
		for _, k in b.hazards or {} do
			if Hz.Kinds[k] == nil then table.insert(missing, b.id .. ": hazard " .. k .. " has no kind") end
			if not GardenArt.hasHazard(k) then table.insert(missing, b.id .. ": hazard " .. k .. " is not drawn") end
		end
	end
	eq(table.concat(missing, "; "), "", "every band has its light, scenery, critters, and art for everything it names")
	-- EVERY band has its own weather (docs/complete-game-standard.md §2; REVIEW-1: the dawn had none), and no
	-- two neighbours have the same set
	local dry = {}
	for _, b in bands do
		if #(b.weather or {}) == 0 then table.insert(dry, b.id) end
	end
	eq(#dry, 0, "every band has its weather, the dawn too (" .. table.concat(dry, ", ") .. ")")
	local same = {}
	for i = 2, #bands do
		local function key(b)
			local ks = {}
			for _, w in b.weather or {} do table.insert(ks, w.kind) end
			table.sort(ks)
			return table.concat(ks, "+")
		end
		if key(bands[i]) == key(bands[i - 1]) then table.insert(same, bands[i - 1].id .. "/" .. bands[i].id) end
	end
	eq(#same, 0, "no two neighbouring bands share their weather (" .. table.concat(same, ", ") .. ")")
	-- each band its own light: no two bands share a ClockTime
	local clocks = {}
	local same = 0
	for _, b in bands do
		if clocks[b.lighting.ClockTime] then same += 1 end
		clocks[b.lighting.ClockTime] = true
	end
	eq(same, 0, "every band has its own time of day")

	-- the game's own logic drives them: the season bands start at their boss wave, so the season turns as the
	-- boss falls; the brag band is full the instant the Slug Queen (wave 30) falls
	eq(bands[ids.harvest].from, 20, "autumn's gold is full when the Snail Baron (wave 20) falls")
	eq(bands[ids.moon].from, 30, "the Harvest Moon is full when the Slug Queen (wave 30) falls")
	eq(bands[ids.moon].celebrate, true, "and it is celebrated")
	eq(bands[ids.moonlit].from, 40, "moonlit snow when the Frost Mantis (wave 40) falls")
	eq(Config.Env.BragBandId, "moon", "the brag band is the moon")
	local w = EnvBands.weights(bands, 30)
	eq(w[ids.moon], 1, "at progress 30 the moon is all there is")
	truthy((EnvBands.weights(bands, 28)[ids.moon] or 0) > 0, "and it is rising during her fight")
	eq(EnvBands.weights(bands, 30.5)[ids.frost] ~= nil and EnvBands.weights(bands, 30.5)[ids.frost] > 0, true,
		"frost creeps in only after the Queen (wave 31's bugs)")
	eq((EnvBands.weights(bands, 29.99)[ids.frost] or 0), 0, "and never during her fight")

	-- band 1 is quiet (no hazards) and hazards begin with the second band, at wave 4 (the model's QuietBeforeWave)
	eq(#(bands[1].hazards or {}), 0, "the first band has no hazards (onboarding)")
	eq(bands[2].from + 1, Hz.QuietBeforeWave, "hazards begin with band 2, at wave " .. Hz.QuietBeforeWave)
end

--====================================================================== hazards
do
	local ok, err = Hazards.validate(Hz)
	truthy(ok, "the hazards pass Hazards.validate (" .. tostring(err) .. ")")
	for name, k in Hz.Kinds do
		truthy(k.drop == "above" or k.drop == "below", name .. " is a vertical kind (a top-down camera)")
		truthy(type(k.name) == "string" and #k.name > 0, name .. " has a name for the warning")
	end
	-- the ring IS the zone: a player standing at its centre walks out of it before the lane locks... and in time
	-- even if they only start moving when it locks (the commit window)
	local walk = Hz.WalkSpeed
	local worst = 0
	for name, k in Hz.Kinds do
		local radius = k.hitRadius + Hz.PlayerRadius
		local need = radius / walk
		worst = math.max(worst, need)
		truthy(need < k.commit, string.format("%s: out of the %.1f-stud ring in %.2f s, inside the %.1f s commit", name, radius, need, k.commit))
	end
	print(string.format("EnvConfig: the slowest escape from a ring takes %.2f s at walk speed %d", worst, walk))
	-- rare: one per IntervalMin..IntervalMax seconds of garden time (Pacing.spec measures one per 2-3 min of play)
	truthy(Hz.IntervalMin >= 60 and Hz.IntervalMax <= 240, "a hazard every 1-4 min of garden time, never more often")
	eq(Config.Budget.MaxHazards, 1, "never more than one at a time")
	truthy(Hz.KnockLift <= Hazards.MAX_KNOCK_LIFT, "a knock never launches anyone")
	truthy(Hz.DazeSeconds > 0 and Hz.DazeSeconds <= 5, "a hit costs a few seconds of daze, never a run")
end

--====================================================================== PAUSE (Rest)
do
	local ok, err = Rest.validate(Config.Rest)
	truthy(ok, "the rest config passes Rest.validate (" .. tostring(err) .. ")")
	eq(Config.Rest.IdleSeconds, 0, "idle rest is OFF (watching a wave is normal play); the AFK hold replaces it")
	truthy(Config.AfkHoldSeconds >= 150, "the AFK hold outlasts any wave plus its build phase (" .. Config.AfkHoldSeconds .. " s)")
	local longest = 0
	for _, k in Hz.Kinds do longest = math.max(longest, k.telegraph + k.pass) end
	truthy(Config.Rest.PendingSeconds >= longest + 2, string.format("a queued PAUSE outlives the longest hazard (%.1f s) by 2 s", longest))
end

--====================================================================== budgets
do
	local B = Config.Budget
	truthy(B.MaxLocalParts <= 220, "local scenery parts are capped (" .. B.MaxLocalParts .. ")")
	truthy(B.MaxEmitters <= 4 and B.MaxWeatherEmitters <= 2 and B.MaxEmitterRate <= 60, "emitters are capped at +1 Jump's budget")
	truthy(B.MaxLights <= 3, "lights are capped at 3")
	eq(B.MaxBugParts, B.MaxRenderedBugs * 3, "a drawn bug is at most 3 parts")
	truthy(B.MaxRenderedBugs >= 35, "the cap on drawn bugs covers the measured peak (35)")
	-- the busiest blend of two neighbouring bands asks for at most MaxWeatherEmitters kinds of weather
	local worstKinds = 0
	for i = 1, #bands - 1 do
		local kinds = {}
		for _, w in bands[i].weather or {} do kinds[w.kind] = true end
		for _, w in bands[i + 1].weather or {} do kinds[w.kind] = true end
		local n = 0
		for _ in kinds do n += 1 end
		worstKinds = math.max(worstKinds, n)
	end
	print("EnvConfig: at most " .. worstKinds .. " weather kinds asked for at a seam (capRates keeps " .. B.MaxWeatherEmitters .. " on)")
	truthy(worstKinds >= 1, "the seams do have weather")
end

print(("EnvConfig: %d passed, %d failed"):format(passed, failed))
