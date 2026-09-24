-- Spec for Deep Vein's REAL environment config (Config.Env, Config.Hazards, Config.Rest, Config.Budget).
-- Run: luau tests/EnvConfig.spec.luau
--
-- The module specs (EnvBands, Hazards, Rest, Strata) carry their own small configs. This file checks the
-- numbers the game actually ships with: that the bands are well formed and every band sets the same
-- lighting fields (so a blend never leaves a property behind), that they sit on the game's own depth
-- scale and are reachable, that every ore stays readable against every stratum it can appear in, that
-- the hazards are rare, telegraphed and dodgeable on a 6-stud grid, and that rest cannot be toggled
-- against them.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Strata = require("../src/shared/Strata")
local Mine = require("../src/shared/Mine")
local Ore = require("../src/shared/Ore")
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

local Env, Hz, RestCfg, Budget = Config.Env, Config.Hazards, Config.Rest, Config.Budget
local bands = Env and Env.Bands
truthy(type(Env) == "table" and type(bands) == "table", "Config.Env.Bands exists")
if type(bands) ~= "table" then
	print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
	error("EnvConfig tests failed", 0)
end

--================================================================ the bands

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "the bands validate (" .. tostring(err) .. ")")
	truthy(#bands >= 8, "at least eight strata, so the walk down never runs out of change (" .. #bands .. ")")
	for i, b in bands do
		truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string" and #b.emoji > 0,
			"band " .. i .. " has a name and an emoji for the chip, the cards and the board")
	end
end

-- Every group every band sets, with the same fields in every band: a field only some bands set would
-- be left at whatever the last band wrote when you walk back out of it.
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sunRays" }
for _, g in GROUPS do
	local keys = {}
	for k in bands[1][g] or {} do keys[k] = true end
	truthy(next(keys) ~= nil, "band 1 sets " .. g)
	for i, b in bands do
		local same = type(b[g]) == "table"
		if same then
			for k in keys do if b[g][k] == nil then same = false end end
			for k in b[g] do if not keys[k] then same = false end end
		end
		truthy(same, "band " .. i .. " (" .. tostring(b.id) .. ") sets exactly the same " .. g .. " fields as band 1")
	end
end

do
	-- the underground is night, and a blend from the dusk surface never passes through noon
	local surfaceClock = bands[1].lighting.ClockTime
	for i = 2, #bands do
		local c = bands[i].lighting.ClockTime
		truthy(c >= surfaceClock and c <= 24, "band " .. i .. "'s ClockTime lies between the surface's dusk and midnight ("
			.. c .. "), so blending toward it only ever darkens")
	end
end

-- Materials the rock may use: real Enum.Material names.
local MATERIALS = {
	Slate = true, Basalt = true, Rock = true, Ground = true, Mud = true, Sandstone = true, Limestone = true,
	Marble = true, Granite = true, Pebble = true, Cobblestone = true, CrackedLava = true, Salt = true,
	Glacier = true, Asphalt = true, Concrete = true,
}
for i, b in bands do
	local r = b.rock
	truthy(type(r) == "table" and type(r.color) == "table" and #r.color == 3 and type(r.accent) == "table"
		and type(r.accentChance) == "number" and r.accentChance >= 0 and r.accentChance <= 0.5,
		"band " .. i .. " has a rock palette (colour, accent, accentChance <= 0.5)")
	truthy(r and MATERIALS[r.material] == true, "band " .. i .. "'s rock material is a real Enum.Material (" .. tostring(r and r.material) .. ")")
	truthy(r and r.material ~= "Neon", "…and never Neon: glowing is what ore does")
end

--================================================================ on the game's own depth scale

local maxRebirthWall = Mine.maxLayer(Config, Config.Prestige.MaxRebirths)
local wall0 = Config.Mine.BaseMaxLayer
do
	for i, b in bands do
		truthy(b.from <= maxRebirthWall - 6, "band " .. i .. " (" .. b.id .. ", layer " .. b.from
			.. ") starts at least a cell above the deepest wall a player can ever reach (" .. maxRebirthWall .. ")")
	end
	local before0 = 0
	for _, b in bands do
		if b.from <= wall0 - 4 then before0 += 1 end
	end
	truthy(before0 >= 4, "a new player passes through at least four strata before their first rebirth (" .. before0 .. ")")
	-- every band after the first opens inside SOME rebirth's shaft with room to stand in it
	for i = 2, #bands do
		local r = 0
		while Mine.maxLayer(Config, r) < bands[i].from + 4 and r < Config.Prestige.MaxRebirths do r += 1 end
		truthy(Mine.maxLayer(Config, r) >= bands[i].from + 4, "band " .. bands[i].id .. " is reachable (rebirth " .. r .. ")")
	end
	local celebrate = {}
	for _, b in bands do if b.celebrate then table.insert(celebrate, b.id) end end
	truthy(#celebrate >= 1 and bands[#bands].celebrate == true, "the deepest band is celebrated (the long-term goal): "
		.. table.concat(celebrate, ", "))
end

--================================================================ every ore stays readable in every stratum

do
	-- For every layer a player can reach, every ore that can exist there is compared with the darkest and
	-- lightest jitter of both the plain and the accent rock at that layer (seams included). Ore is Neon
	-- and glows, but a copper vein on brown topsoil has to read as copper without the glow too.
	local worst, worstAt = math.huge, ""
	for layer = 1, maxRebirthWall do
		local looks = {}
		for _, j in { 0, 0.9999 } do
			for _, a in { 0, 0.9999 } do
				table.insert(looks, Strata.rockLook(Config, EnvBands, layer, j, a))
			end
		end
		for tier = 1, Config.MaxOre do
			if Ore.weight(Config, tier, layer) > 0 then
				local oc = Ore.color(Config, tier)
				for _, l in looks do
					local c = Strata.contrast(oc, l.color)
					if c < worst then
						worst = c
						worstAt = Ore.name(Config, tier) .. " at layer " .. layer .. " vs " .. (if l.accent then "accent " else "")
							.. l.material
					end
				end
			end
		end
	end
	print(string.format("  ore readability: worst contrast %.1f (%s), floor %d", worst, worstAt, Env.MinOreContrast))
	truthy(worst >= Env.MinOreContrast, "every ore stays at least MinOreContrast from the rock around it (worst "
		.. string.format("%.1f", worst) .. ", " .. worstAt .. ")")
	truthy(Env.MinOreContrast >= 60, "…and the floor itself is not set low to pass (" .. Env.MinOreContrast .. ")")
end

--================================================================ the bedrock still reads as the boundary
-- Review 2026-09-24, finding 2. The four wall slabs and the floor slab are near-black Basalt and carry no
-- ClickDetector on the walls (REVIEW-4). Before the strata, the closest stone came to them was 106 RGB on
-- a different material, so the edge of the claim read at a glance. The obsidian slate came within 4.5 of
-- it and the core and magma used Basalt itself, so from rebirth 9 on the unbreakable walls looked like the
-- rock beside them. Rule: no stone uses the bedrock's material, and every stone look a player can meet
-- stays further from the bedrock than two stone cells of one stratum can be from each other.

do
	local bed = Config.Mine.BedrockColor
	local bedMat = Config.Mine.BedrockMaterial
	truthy(type(bed) == "table" and #bed == 3 and type(bedMat) == "string",
		"the bedrock's look is config (Config.Mine.BedrockColor / BedrockMaterial), so this rule can see it")
	local jitterSpan = 2 * Env.JitterRange * math.sqrt(3)
	truthy(type(Env.MinBedrockContrast) == "number" and Env.MinBedrockContrast > jitterSpan, string.format(
		"MinBedrockContrast (%s) is more than two cells of one stratum can differ by jitter alone (%.1f)",
		tostring(Env.MinBedrockContrast), jitterSpan))
	if type(bed) == "table" and type(Env.MinBedrockContrast) == "number" then
		local worst, worstAt, sameMat = math.huge, "", {}
		for layer = 1, maxRebirthWall do
			for _, j in { 0, 0.9999 } do
				for _, a in { 0, 0.9999 } do
					local l = Strata.rockLook(Config, EnvBands, layer, j, a)
					local c = Strata.contrast(l.color, bed)
					if c < worst then
						worst = c
						worstAt = string.format("layer %d %s{%d,%d,%d} %s", layer, if l.accent then "accent " else "",
							l.color[1], l.color[2], l.color[3], l.material)
					end
					if l.material == bedMat then sameMat[layer] = true end
				end
			end
		end
		local n = 0
		for _ in sameMat do n += 1 end
		print(string.format("  bedrock: closest stone %.1f RGB (%s), floor %d; stone layers on the bedrock's %s: %d",
			worst, worstAt, Env.MinBedrockContrast, tostring(bedMat), n))
		eq(n, 0, "no stone Part at any layer is made of the bedrock's material (" .. tostring(bedMat) .. ")")
		truthy(worst >= Env.MinBedrockContrast, string.format(
			"every stone look at every layer stays at least MinBedrockContrast from the bedrock (worst %.1f, %s)", worst, worstAt))
	end
end

--================================================================ glowing decor never passes for ore
-- Review 2026-09-24, finding 5. Ice-blue crystals were 15.7 RGB from diamond, the ruins' glyphs 11.9 from
-- gold. Decor sits on the bedrock walls with no ClickDetector, so a find that looks like ore is a tap that
-- does nothing. Every GLOWING decor colour (Config.Env.DecorGlow, which CaveArt builds from) keeps the same
-- distance from every ore that can exist at a layer where that decor can be, as ore keeps from rock.

do
	local glow = Env.DecorGlow
	truthy(type(glow) == "table", "the glowing decor colours are config (Config.Env.DecorGlow)")
	truthy(type(Env.MinDecorOreContrast) == "number" and Env.MinDecorOreContrast >= Env.MinOreContrast,
		"MinDecorOreContrast is at least the ore-vs-rock floor (" .. tostring(Env.MinDecorOreContrast) .. ")")
	if type(glow) == "table" and type(Env.MinDecorOreContrast) == "number" then
		local worst, worstAt, checked = math.huge, "", 0
		for layer = 1, maxRebirthWall do
			local b = bands[EnvBands.indexAt(bands, layer)]
			for _, kind in (b.decor and b.decor.kinds) or {} do
				for _, c in glow[kind] or {} do
					for tier = 1, Config.MaxOre do
						if Ore.weight(Config, tier, layer) > 0 then
							checked += 1
							local d = Strata.contrast(c, Ore.color(Config, tier))
							if d < worst then
								worst = d
								worstAt = string.format("%s {%d,%d,%d} vs %s at layer %d", kind, c[1], c[2], c[3], Ore.name(Config, tier), layer)
							end
						end
					end
				end
			end
		end
		print(string.format("  glowing decor vs ore: worst %.1f (%s), floor %d, %d pairs", worst, worstAt, Env.MinDecorOreContrast, checked))
		truthy(checked > 1000, "set-up: glowing decor was compared with ore at every layer (" .. checked .. ")")
		truthy(worst >= Env.MinDecorOreContrast, string.format(
			"no glowing decoration is within MinDecorOreContrast of an ore that can sit beside it (worst %.1f, %s)", worst, worstAt))
		for _, kind in { "waterfall", "shrooms", "lavacrack", "lavafall", "crystals", "arch", "glyphs", "shards", "runes" } do
			truthy(type(glow[kind]) == "table" and #glow[kind] >= 1, "DecorGlow lists the glow of " .. kind)
		end
	end
end

--================================================================ the lamp stays the main light underground
-- Review 2026-09-24, finding 6. The server's mine preset (Fx.Presets.Horror, Main.server: "the head lamp
-- and the glowing ore are ALL the light") is what the paid lamp track (26 -> 74 studs) was built against.
-- The strata wrote 1.6-2.9x its ambient fill underground, which lights what the lamp is for. The fill may
-- carry a stratum's hue, not its brightness: Ambient and OutdoorAmbient luma within MaxAmbientRatio of the
-- server's, exposure within MaxExposureLift of it, at every layer below the surface band.
-- (check_deepvein_cave compares LampFill's reference numbers with the server's real Lighting.)

do
	local fill = Env.LampFill
	truthy(type(fill) == "table" and type(fill.ReferenceAmbient) == "table" and type(fill.ReferenceOutdoorAmbient) == "table"
		and type(fill.ReferenceExposure) == "number", "Config.Env.LampFill holds the server preset's fill")
	if type(fill) == "table" and type(fill.ReferenceAmbient) == "table" then
		truthy(fill.MaxAmbientRatio <= 1.25 and fill.MaxExposureLift <= 0.1,
			string.format("…and the allowance is small (x%.2f, +%.2f EV)", fill.MaxAmbientRatio, fill.MaxExposureLift))
		local function luma(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
		local refA, refO = luma(fill.ReferenceAmbient), luma(fill.ReferenceOutdoorAmbient)
		local worstA, worstO, worstE, at = 0, 0, -math.huge, ""
		for layer = bands[2].from, maxRebirthWall do
			local l = EnvBands.sample(bands, layer, "lighting")
			local a, o = luma(l.Ambient) / refA, luma(l.OutdoorAmbient) / refO
			if a > worstA then worstA, at = a, "layer " .. layer end
			worstO = math.max(worstO, o)
			worstE = math.max(worstE, l.ExposureCompensation)
		end
		print(string.format("  lamp fill below the surface: Ambient up to x%.2f (%s), OutdoorAmbient up to x%.2f, exposure up to %+.2f (server %+.2f)",
			worstA, at, worstO, worstE, fill.ReferenceExposure))
		truthy(worstA <= fill.MaxAmbientRatio + 1e-9, string.format(
			"underground Ambient stays within x%.2f of the server's dark preset (worst x%.2f, %s)", fill.MaxAmbientRatio, worstA, at))
		truthy(worstO <= fill.MaxAmbientRatio + 1e-9, string.format(
			"…and OutdoorAmbient (worst x%.2f)", worstO))
		truthy(worstE <= fill.ReferenceExposure + fill.MaxExposureLift + 1e-9, string.format(
			"…and exposure stays within +%.2f EV of it (worst %+.2f)", fill.MaxExposureLift, worstE))
	end
end

--================================================================ the drawn hazard never hangs inside the miner

do
	local head = Env.HeadTopAboveFloor
	truthy(type(head) == "number" and head >= 5 and head < Config.Mine.CellSize, string.format(
		"HeadTopAboveFloor is a standing avatar's height and fits a one-layer tunnel (%s < %d)", tostring(head), Config.Mine.CellSize))
end

--================================================================ hazards: rare, telegraphed, dodgeable

do
	local ok, err = Hazards.validate(Hz)
	truthy(ok, "Config.Hazards validates (" .. tostring(err) .. ")")
	eq(#(bands[1].hazards or {}), 0, "no hazards at the surface (the mouth, the sell pad, the spawn)")
	local S = Config.Mine.CellSize
	local walk = Hz.WalkSpeed
	truthy(type(walk) == "number" and walk > 0, "Config.Hazards.WalkSpeed is the humanoid's walk speed the dodge assumes")
	for name, k in Hz.Kinds do
		truthy(k.drop == "above" or k.drop == "below", name .. " is vertical: nothing flies in sideways through rock")
		local zoneR = k.hitRadius + Hz.PlayerRadius
		truthy(zoneR * 2 <= S + 1e-9, string.format("%s's ring (%.1f studs across) is no wider than one cell", name, zoneR * 2))
		truthy(k.commit * walk >= 2 * S, string.format("%s: after the lock there is time to walk two cells (%.1f studs)", name, k.commit * walk))
		truthy(k.telegraph >= 3, name .. " is telegraphed for at least 3 s (" .. k.telegraph .. ")")
		truthy(k.knock <= 40, name .. " knocks you down, it does not launch you (" .. k.knock .. ")")
	end
	truthy(Hz.KnockLift <= 12, "the knock's lift stays small (" .. Hz.KnockLift .. ")")
	local used = {}
	for i, b in bands do
		for _, kind in b.hazards or {} do
			truthy(Hz.Kinds[kind] ~= nil, "band " .. i .. "'s hazard " .. kind .. " exists")
			used[kind] = true
		end
		if i > 1 then truthy(#(b.hazards or {}) >= 1, "band " .. i .. " has at least one hazard") end
	end
	for name in Hz.Kinds do truthy(used[name] == true, "hazard kind " .. name .. " is used by some band") end
end

do
	-- rarity on the real config: 20 h of mining, hazards only where the band has them
	local seed = 20260923
	local function rand()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
	local s = Hazards.newScheduler(Hz, rand)
	local spawns, dt = 0, 0.1
	local kinds = bands[3].hazards
	for _ = 1, 20 * 36000 do
		local ev = Hazards.step(s, Hz, dt, { resting = false, grounded = true, kinds = kinds, aim = { x = 0, y = -60, z = 0 },
			yaw = 0, pitch = 0, canDodge = true }, rand)
		if ev and ev.type == "spawn" then spawns += 1 end
	end
	local perMin = spawns / (20 * 60)
	print(string.format("  rarity on the real config: %d hazards in 20 h of mining = one per %.1f s", spawns, 20 * 3600 / spawns))
	truthy(perMin >= 1 / 3 and perMin <= 1 / 2, "about one hazard per 2-3 minutes of mining (" .. string.format("%.3f", perMin) .. "/min)")
end

--================================================================ rest

do
	local ok, err = Rest.validate(RestCfg)
	truthy(ok, "Config.Rest validates (" .. tostring(err) .. ")")
	truthy((RestCfg.SettleSeconds or 0) > 0, "SettleSeconds is on: progress here is clicking, so a rest must wait for stillness")
	truthy((RestCfg.MinAwakeSeconds or 0) > 0, "MinAwakeSeconds is on: rest cannot be toggled between swings")
	local longest = 0
	for _, k in Hz.Kinds do longest = math.max(longest, k.telegraph + k.pass) end
	truthy(RestCfg.PendingSeconds >= longest + 2, string.format(
		"a queued rest outlives the longest hazard (%.1f s vs %.1f s), so a dodge keeps the request", RestCfg.PendingSeconds, longest))
end

--================================================================ budgets are numbers, and the config fits them

do
	for _, k in { "MaxLocalParts", "MaxEmitters", "MaxEmitterRate", "MaxWeatherEmitters", "MaxLights", "MaxHazards" } do
		truthy(type(Budget[k]) == "number" and Budget[k] > 0, "Config.Budget." .. k .. " is set")
	end
	truthy(Budget.MaxWeatherEmitters < Budget.MaxEmitters, "weather leaves an emitter free for a hazard's dust or steam")
	eq(Budget.MaxHazards, 1, "one hazard at a time")
	for i, b in bands do
		truthy(b.weather == nil or b.weather.rate <= Budget.MaxEmitterRate, "band " .. i .. "'s weather fits the particle budget")
	end
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
assert(failed == 0, "EnvConfig tests failed")
