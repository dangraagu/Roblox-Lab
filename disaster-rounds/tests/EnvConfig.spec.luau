-- Disaster Rounds' environment, stray and rest config, checked against the rules the generic modules and
-- DESIGN.md §3-§5 set. Run: luau tests/EnvConfig.spec.luau
--
-- The generic modules (EnvBands, Hazards, Rest: plus1-jump's, byte-identical) validate SHAPE. This file checks the
-- game's specifics: six bands on lifetime survivals, every band blending every field, red reserved for danger,
-- strays that cannot lift a player over the rail, a rest that cannot be an exploit, and the shots switches off.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local Env, Hz = Config.Env, Config.Hazards
local bands = Env.Bands

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "Config.Env.Bands validates (" .. tostring(err) .. ")")
	local ok2, err2 = Hazards.validate(Hz)
	truthy(ok2, "Config.Hazards validates (" .. tostring(err2) .. ")")
	local ok3, err3 = Rest.validate(Config.Rest)
	truthy(ok3, "Config.Rest validates (" .. tostring(err3) .. ")")
end

--======================================================================= six bands on lifetime survivals

eq(#bands, 6, "six bands (the standard asks for at least five)")
do
	local want = { 0, 2, 6, 12, 21, 100 }
	local fades = { 0, 1, 2, 3, 4, 20 }
	for i, b in bands do
		eq(b.from, want[i], "band " .. i .. " (" .. b.name .. ") starts at " .. want[i] .. " survivals")
		eq(b.fade or 0, fades[i], "and fades in over " .. fades[i])
	end
	eq(bands[5].id, Config.Brag.BandId, "band 5 is the brag band (Falling Sky)")
	truthy(bands[5].celebrate == true, "and it celebrates")
end

--======================================================================= every band blends every field

local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sunRays", "sky" }
for _, g in GROUPS do
	local keys = nil
	local same = true
	for _, b in bands do
		local t = b[g]
		truthy(type(t) == "table", b.id .. " has a " .. g .. " table")
		if type(t) == "table" then
			local ks = {}
			for k in t do table.insert(ks, k) end
			table.sort(ks)
			local s = table.concat(ks, ",")
			if keys == nil then keys = s elseif keys ~= s then same = false end
		end
	end
	truthy(same, "every band sets the same " .. g .. " fields, so a fade never drops one (" .. tostring(keys) .. ")")
end
do
	-- every overlay field exists in the bands, so EnvBands.overlay blends it instead of switching it
	for kind, over in Env.Overlays do
		for g, t in over do
			for k in t do
				truthy(bands[1][g] ~= nil and bands[1][g][k] ~= nil, string.format("overlay %s.%s.%s is a band field", kind, g, k))
			end
		end
	end
	for _, k in Config.Disasters.Kinds do
		truthy(Env.Overlays[k] ~= nil, "the " .. k .. " has an overlay")
	end
end
do
	-- something to see in every band: scenery, critters, weather
	for _, b in bands do
		truthy(#(b.pieces or {}) >= 1, b.name .. " has far scenery")
		truthy(#(b.critters or {}) >= 1, b.name .. " has critters")
		truthy(b.weather ~= nil and b.weather.rate > 0, b.name .. " has weather")
		for _, c in b.critters or {} do
			truthy(Env.Critters[c.kind] ~= nil, b.name .. ": critter " .. c.kind .. " is defined")
		end
		local count = 0
		for _, c in b.critters or {} do count += c.count end
		truthy(count <= Config.Budget.Critters, b.name .. ": " .. count .. " critters fit the budget of " .. Config.Budget.Critters)
	end
	-- each band looks different from the last: its light moves
	for i = 2, #bands do
		local a, b = bands[i - 1].lighting, bands[i].lighting
		truthy(math.abs(a.ClockTime - b.ClockTime) >= 1.5, string.format("%s -> %s: the time of day moves (%.1f -> %.1f)",
			bands[i - 1].name, bands[i].name, a.ClockTime, b.ClockTime))
	end
end

--======================================================================= red is reserved for danger

local function redness(c: { number }): number
	return (c[1] - math.max(c[2], c[3])) / 255
end
do
	local worst, where = -1, ""
	for _, b in bands do
		local r = redness(b.colorCorrection.TintColor)
		if r > worst then worst, where = r, b.name end
	end
	for kind, over in Env.Overlays do
		if over.colorCorrection and over.colorCorrection.TintColor then
			local r = redness(over.colorCorrection.TintColor)
			if r > worst then worst, where = r, kind .. " overlay" end
		end
	end
	truthy(worst <= 0.15, string.format("no band or overlay tint has red more than 0.15 above green and blue (worst %.3f, %s)", worst, where))
	-- island palettes: no saturated red (ochre and sand are fine: green stays above 60 % of red)
	local bad = {}
	for _, s in Config.Island.Styles do
		for lv, c in s.levels do
			if c[2] < 0.6 * c[1] then table.insert(bad, s.id .. " level " .. (lv - 1)) end
		end
	end
	eq(#bad, 0, "no island palette colour is red (" .. table.concat(bad, ", ") .. ")")
	eq(#Config.Island.Styles, 3, "three island styles")
end

--======================================================================= the Lookout strays (Hazards.luau)

do
	eq(Hz.IntervalMin, 60, "a stray every 60-90 s of Lookout time")
	eq(Hz.IntervalMax, 90, "(rarer than the standard's 2-3 min: the disasters supply the near-misses)")
	truthy(Hz.MinTelegraphSeconds >= 3, "every stray gives at least 3 s of warning")
	local longest = 0
	for _, k in Hz.Kinds do longest = math.max(longest, k.telegraph + k.pass) end
	eq(longest, 5.7, "the longest stray flight is 5.7 s")
	truthy(Config.Rest.PendingSeconds >= longest + 2, string.format("a queued rest (%.1f s) outlives the longest stray flight by 2 s", Config.Rest.PendingSeconds))
	local lift = Hz.KnockLift ^ 2 / (2 * 196.2)
	truthy(lift < Config.Lookout.RailHeight / 4, string.format("a knock lifts %.2f studs: never over the %d-stud rail", lift, Config.Lookout.RailHeight))
	for _, kind in Config.Disasters.Kinds do
		local s = Hz.ByDisaster[kind]
		truthy(s ~= nil and Hz.Kinds[s] ~= nil, "the " .. kind .. " throws a defined stray (" .. tostring(s) .. ")")
	end
	for name, k in Hz.Kinds do
		truthy(k.visualRadius == nil or k.visualRadius >= k.hitRadius, name .. ": the hitbox is never bigger than what the player sees")
	end
end

--======================================================================= rest can never be an exploit

do
	local R = Config.Round
	-- the longest still stretch of an engaged player: from a landing, the drop, the whole disaster, the outro, the
	-- intermission, the next drop and up to 20 s until the first ring forces a step
	local still = R.DropSeconds + R.DisasterSeconds + R.OutroSeconds + R.IntermissionSeconds + R.DropSeconds + 20
	eq(still, 112, "the longest still stretch while playing is 112 s")
	truthy(Config.Rest.IdleSeconds > still, string.format("idle rest (%d s) never fires during normal play", Config.Rest.IdleSeconds))
	truthy(Config.Rest.IdleSeconds < 2 * (R.DropSeconds + R.DisasterSeconds + R.OutroSeconds + R.IntermissionSeconds),
		"and two full cycles of AFK can never pass without it")
	truthy(Config.Rest.WakeOnMove and Config.Rest.BlockWhileThreat, "moving wakes you; a stray inbound queues the request")
end

--======================================================================= the ring rules

do
	local ringR = Config.Strikes.HitRadius + Config.Hits.PlayerRadius
	truthy(Config.Strikes.ExitStuds > ringR + 0.8, "ExitStuds 7 > 4.5 + 0.8: a lone ring always passes the placement rule")
	eq(Config.Strikes.TelegraphSeconds, Hz.MinTelegraphSeconds, "a ring's warning is the template's minimum, 3.0 s")
	truthy(ringR < Config.Island.CellStuds * 0.6, "a ring is about one cell wide (9 studs across, cells are 8)")
end

--======================================================================= budgets capped in code (REVIEW-1 F11)

-- The first build called these "enforced in code" and only measured them. Each one now has a code cap, and these
-- are the sums that make the caps add up: the far scenery is trimmed per piece (SkyArt.updatePiece), the live rings
-- are capped in Strikes.maxLive, and the server's fixed Parts plus its capped ones fit ServerParts
-- (robloxemu/check_disasterrounds_env.luau counts the fixed ones on the running server).
do
	local B = Config.Budget
	local most = 0
	for _, b in Config.Env.Bands do most = math.max(most, #(b.pieces or {})) end
	truthy(type(B.SceneryPartsPerPiece) == "number" and most * B.SceneryPartsPerPiece <= B.SceneryPartsPerBand,
		string.format("a band has at most %d far pieces of at most %s Parts each: never over %d per band", most,
			tostring(B.SceneryPartsPerPiece), B.SceneryPartsPerBand))
	truthy(2 * B.SceneryPartsPerBand <= B.SceneryParts, "two bands at a seam fit the scenery cap of " .. B.SceneryParts)
	truthy(type(B.Rings) == "number" and B.Rings <= B.Projectiles, "one projectile per live ring fits the projectile budget")
end

--======================================================================= the shots switches are off in src/

eq(Config.Shots.ForceKind, nil, "Config.Shots.ForceKind is nil in src/")
eq(Config.Shots.ForceHeat, nil, "Config.Shots.ForceHeat is nil in src/")
eq(Config.Shots.IslandSeed, nil, "Config.Shots.IslandSeed is nil in src/")

--======================================================================= nothing costs Robux

do
	local function scan(t: any, path: string): string?
		for k, v in t do
			local name = string.lower(tostring(k))
			if string.find(name, "robux", 1, true) or string.find(name, "gamepass", 1, true) or string.find(name, "price", 1, true)
				or string.find(name, "devproduct", 1, true) then
				return path .. "." .. tostring(k)
			end
			if type(v) == "table" then
				local r = scan(v, path .. "." .. tostring(k))
				if r then return r end
			end
		end
		return nil
	end
	eq(scan(Config, "Config"), nil, "Config has no price, gamepass or Robux anything")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
assert(failed == 0, "EnvConfig tests failed")
