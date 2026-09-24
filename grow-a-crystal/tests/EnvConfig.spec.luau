-- Spec for Grow a Crystal's eye-candy CONFIG (Config.Env, Config.Visitors, Config.Rest, Config.Budget).
-- Run: luau tests/EnvConfig.spec.luau
--
-- The modules are tested on their own configs in their own specs. This one checks the numbers this
-- game actually ships, because a valid module with a bad table is still a broken cavern:
--   * the bands validate, every band defines the same fields (a blend never falls back to one
--     side), the first band IS the server's Cozy preset (the client takes over without a jump), and
--     there is never a sun underground;
--   * every chamber purchase changes the cavern, and a later band never loses what an earlier one
--     had (the cavern grows richer, it does not swap one look for another);
--   * the first band has no visitors (a new player learns the loop in peace);
--   * there are NO knock-down hazards in this game (EYECANDY.md §3 says why);
--   * rest validates and its idle trigger is off (standing still IS playing an idle game);
--   * every count the client can build fits the budget.
local EnvBands = require("../src/shared/EnvBands")
local Rest = require("../src/shared/Rest")
local Visitors = require("../src/shared/Visitors")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Env = Config.Env
truthy(type(Env) == "table", "Config.Env exists")
local bands = Env and Env.Bands or {}
local MAXC = Config.Economy.MaxChambers

--=========================================================================== bands
do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "Config.Env.Bands validates (" .. tostring(err) .. ")")
	truthy(#bands >= 4, "at least four looks across the eight chambers (" .. #bands .. ")")
	truthy(bands[#bands].from <= MAXC, "the last band is reachable: it opens at or before chamber " .. MAXC)
	truthy(bands[2] and bands[2].from - (bands[2].fade or 0) <= 1, "the first change is under way by the second chamber")

	local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "depthOfField", "pulse" }
	for _, g in GROUPS do
		local keys = {}
		for k in bands[1][g] or {} do keys[k] = true end
		for _, b in bands do
			truthy(type(b[g]) == "table", "band " .. b.id .. " defines " .. g)
			local mine = {}
			for k in b[g] or {} do mine[k] = true end
			for k in keys do truthy(mine[k], "band " .. b.id .. " sets " .. g .. "." .. k .. " like band 1") end
			for k in mine do truthy(keys[k], "band " .. b.id .. " sets no extra " .. g .. "." .. k) end
		end
	end
	for _, b in bands do
		eq(b.lighting.ClockTime, 0, "band " .. b.id .. " keeps ClockTime 0: no sun underground")
		truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string", "band " .. b.id .. " has a name and an emoji")
		truthy(b.pulse.period >= 4, "band " .. b.id .. " pulses slowly (period " .. b.pulse.period .. " s)")
		truthy(b.pulse.depth >= 0 and b.pulse.depth <= 0.5, "band " .. b.id .. " pulse depth is gentle (" .. b.pulse.depth .. ")")
	end

	-- band 1 is the server's Fx.Presets.Cozy, number for number (Fx needs the Lighting service, so the
	-- CLI cannot load it; robloxemu/check_growacrystal_env.luau compares against the REAL server write)
	local cozy = {
		lighting = { Ambient = { 40, 44, 58 }, OutdoorAmbient = { 35, 40, 55 }, Brightness = 2, ExposureCompensation = 0.1,
			ClockTime = 0, FogStart = 20, FogEnd = 240, FogColor = { 22, 26, 40 } },
		atmosphere = { Density = 0.3, Offset = 0.2, Color = { 120, 150, 170 }, Decay = { 60, 80, 110 }, Glare = 0.2, Haze = 1.2 },
		bloom = { Intensity = 0.9, Size = 30, Threshold = 0.9 },
		colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.18, TintColor = { 220, 235, 245 } },
		depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
	}
	for g, want in cozy do
		for k, v in want do
			local got = bands[1][g] and bands[1][g][k]
			if type(v) == "table" then
				truthy(type(got) == "table" and got[1] == v[1] and got[2] == v[2] and got[3] == v[3],
					"band 1 " .. g .. "." .. k .. " is the Cozy preset's")
			else
				eq(got, v, "band 1 " .. g .. "." .. k .. " is the Cozy preset's")
			end
		end
	end

	-- every chamber purchase changes the cavern
	for c = 1, MAXC - 1 do
		local a, b = EnvBands.weights(bands, c), EnvBands.weights(bands, c + 1)
		local differs = false
		for i = 1, #bands do
			if math.abs((a[i] or 0) - (b[i] or 0)) > 0.05 then differs = true end
		end
		truthy(differs, "buying chamber " .. (c + 1) .. " visibly changes the cavern")
	end

	-- richer, never poorer: a band keeps every piece and every critter kind of the band before it
	for i = 2, #bands do
		local have = {}
		for _, id in bands[i].pieces do have[id] = true end
		for _, id in bands[i - 1].pieces do
			truthy(have[id], "band " .. bands[i].id .. " keeps " .. id .. " from " .. bands[i - 1].id)
		end
		truthy(#bands[i].pieces > #bands[i - 1].pieces, "band " .. bands[i].id .. " adds a piece")
	end

	eq(#(bands[1].visitors or {}), 0, "the first band has no visitors: a new player learns the loop in peace")
	for i = 2, #bands do
		truthy(#(bands[i].visitors or {}) >= 1, "band " .. bands[i].id .. " has at least one visitor kind")
		for _, k in bands[i].visitors do
			truthy(Config.Visitors.Kinds[k] ~= nil, "band " .. bands[i].id .. " visitor " .. k .. " is defined")
		end
	end
end

--=========================================================================== no hazards
do
	eq(Config.Hazards, nil, "Grow a Crystal has no knock-down hazards (an idle game must not punish waiting)")
	for _, b in bands do
		eq(b.hazards, nil, "band " .. b.id .. " lists no hazards")
	end
end

--=========================================================================== visitors + rest
do
	local ok, err = Visitors.validate(Config.Visitors)
	truthy(ok, "Config.Visitors validates (" .. tostring(err) .. ")")
	truthy(Config.Visitors.IntervalMin >= 120 and Config.Visitors.IntervalMax <= 180,
		"a visitor every 2-3 minutes of play, as the owner's brief sets for near-passes")
	local rok, rerr = Rest.validate(Config.Rest)
	truthy(rok, "Config.Rest validates (" .. tostring(rerr) .. ")")
	eq(Config.Rest.IdleSeconds, 0, "idle rest is OFF: standing still is how an idle game is played, and nothing here can hurt an AFK player")
	eq(Config.Rest.WakeOnMove, true, "moving always ends a rest")
end

--=========================================================================== harvest + budget
do
	for t = 1, Config.MaxTier do
		truthy(type(Env.Harvest[t]) == "table", "harvest rule for tier " .. t)
	end
	-- the Legendary/Mythic full-screen flash (review 2026-09-24, finding 3)
	local F = Env.HarvestFlash
	truthy(type(F) == "table", "Config.Env.HarvestFlash is set")
	F = F or {}
	truthy(type(F.alpha) == "number" and F.alpha > 0 and F.alpha <= 0.5,
		"a harvest flash is a tint, never a white-out (alpha " .. tostring(F.alpha) .. ")")
	truthy(type(F.fade) == "number" and F.fade > 0, "a harvest flash fades out (" .. tostring(F.fade) .. " s)")
	truthy(type(F.cooldown) == "number" and type(F.fade) == "number" and F.cooldown >= F.fade,
		"the flash cooldown (" .. tostring(F.cooldown) .. " s) outlasts a flash's fade: two harvest flashes are never on screen together")
	truthy(type(F.cooldown) == "number" and F.cooldown <= 5,
		"but it is short enough that a Legendary a few seconds later still celebrates")
	local B = Config.Budget
	for _, k in { "MaxLocalParts", "MaxScenery", "MaxEmitters", "MaxWeatherEmitters", "MaxEmitterRate", "MaxLights",
		"MaxShards", "MaxVisitors" } do
		truthy(type(B[k]) == "number" and B[k] >= 0, "Config.Budget." .. k .. " is set")
	end
	eq(B.MaxVisitors, 1, "one visitor at a time")
	truthy(B.MaxWeatherEmitters <= B.MaxEmitters, "weather fits the emitter budget")

	-- the worst band blend: every critter of two neighbouring bands at full count, plus the scenery,
	-- a visitor in flight and a full harvest burst, fits MaxLocalParts
	local partsPer = Env.CritterParts
	local worstCritters = 0
	for i = 1, #bands do
		local n = 0
		local seen = {}
		for _, j in { i, i + 1 } do
			local b = bands[j]
			if b then
				for _, a in b.ambient do
					seen[a.kind] = math.max(seen[a.kind] or 0, a.count)
				end
			end
		end
		for kind, count in seen do
			truthy(partsPer[kind] ~= nil, "critter " .. kind .. " has a part count")
			n += count * (partsPer[kind] or 0)
		end
		worstCritters = math.max(worstCritters, n)
	end
	local worstVisitor = 0
	for _, k in Config.Visitors.Kinds do
		worstVisitor = math.max(worstVisitor, k.parts or 0)
	end
	local bound = B.MaxScenery + worstCritters + worstVisitor + B.MaxShards + 3 + 8 -- ring + 2 beam parts, emitter hosts
	print(string.format("  worst case by construction: %d scenery + %d critters + %d visitor + %d shards + 11 = %d (budget %d)",
		B.MaxScenery, worstCritters, worstVisitor, B.MaxShards, bound, B.MaxLocalParts))
	truthy(bound <= B.MaxLocalParts, "the worst case by construction fits MaxLocalParts")

	-- weather rates: a single band never asks for more than the total particle budget
	for _, b in bands do
		local sum = 0
		for _, w in b.weather do sum += w.rate end
		truthy(sum <= B.MaxEmitterRate, "band " .. b.id .. " weather fits MaxEmitterRate (" .. sum .. ")")
		truthy(#b.weather <= B.MaxWeatherEmitters, "band " .. b.id .. " switches on at most MaxWeatherEmitters")
	end
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
if failed > 0 then error("EnvConfig spec failed", 0) end
