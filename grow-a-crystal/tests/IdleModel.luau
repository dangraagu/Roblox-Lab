-- IdleModel.luau — test-side model of a player working their cavern, built ONLY from the game's own
-- pure rules (Economy, Growth, Rarity, Codex, Rng) and Config. Not shipped, not in the bundle.
--
-- It answers the one question the environment bands depend on: when does a player own each chamber
-- (the band progress value), and when do they first see each refraction tier?
--
-- There is no telemetry yet, so the human part is written down in Config.Pacing.Profiles instead of
-- being hidden in a number:
--   checkEvery   seconds between the player's visits to their sockets while playing
--   codes        codes redeemed in the first minute (the store page and README advertise them)
--   selectTier   the seed tier the player keeps selected (the HUD starts on Shard)
--   buy          "cheapest": after replanting, buy the cheapest upgrade the shop offers (chamber,
--                luck, growth) while keeping enough dust to replant every empty socket
-- Mirrors the server: a click on an empty socket auto-buys a seed of the selected tier when the player
-- has none (tryPlant), a harvest rolls refraction with a fresh Rng and pays DustValue[final]
-- (grantHarvest). Offline growth is NOT modelled: every minute here is a minute played, so real
-- players who leave their crystals growing overnight get there sooner.
local Economy = require("../src/shared/Economy")
local Growth = require("../src/shared/Growth")
local Rarity = require("../src/shared/Rarity")
local Codex = require("../src/shared/Codex")
local Rng = require("../src/shared/Rng")

local IdleModel = {}

-- Expected Gem Dust from harvesting one crystal grown from `seedTier` at `luckMult`.
function IdleModel.expectedDust(cfg: any, seedTier: number, luckMult: number): number
	local ev, carry, t = 0, 1, seedTier
	while true do
		if t >= cfg.MaxTier then
			ev += carry * cfg.Economy.DustValue[t]
			break
		end
		local c = Rarity.upgradeChance(t, luckMult, cfg.Refraction)
		ev += carry * (1 - c) * cfg.Economy.DustValue[t]
		carry *= c
		t += 1
	end
	return ev
end

-- One simulated session. Returns { chamberAt = {[k] = seconds}, codexAt = {[t] = seconds}, final = profile }.
function IdleModel.run(cfg: any, profile: any, seed: number, seconds: number): any
	local p = {
		dust = cfg.Economy.StartDust, seeds = { [1] = 3 }, chambers = cfg.Economy.StartChambers,
		luckLevel = 0, growthLevel = 0, plants = {}, codex = {}, totalDust = 0,
	}
	local chamberAt = { [p.chambers] = 0 }
	local codexAt = {}
	local rolls = 0

	for code in profile.codes or {} do
		local reward = cfg.Codes[code]
		if reward then
			if reward.dust then p.dust += reward.dust end
			if reward.seedTier then p.seeds[reward.seedTier] = (p.seeds[reward.seedTier] or 0) + 1 end
		end
	end

	local function plantAll(now: number)
		local total = Economy.totalSockets(p.chambers, cfg.Economy)
		for s = 1, total do
			if p.plants[s] == nil then
				-- a gift seed of another tier (the GEODE code) is planted first, as a player would
				local tier = profile.selectTier
				for t = cfg.MaxTier, 1, -1 do
					if t ~= profile.selectTier and (p.seeds[t] or 0) > 0 then tier = t; break end
				end
				if (p.seeds[tier] or 0) <= 0 then
					if not Economy.buySeed(p, tier, cfg.Economy) then break end
				end
				p.seeds[tier] -= 1
				p.plants[s] = { tier = tier, at = now }
			end
		end
	end

	local now = 0
	plantAll(now)
	while now < seconds do
		now += profile.checkEvery
		local gm = Growth.growthMult(p.growthLevel, cfg.Boosters)
		local lm = Rarity.luckMult(p.luckLevel, cfg.Boosters)
		for s, plant in p.plants do
			if Growth.isMature(plant.at, now, plant.tier, cfg.Growth, gm) then
				rolls += 1
				local final = Rarity.roll(plant.tier, lm, Rng.new(seed * 7919 + rolls * 104729), cfg.Refraction, cfg.MaxTier)
				local dust = Economy.harvestDust(final, false, cfg.Economy)
				p.dust += dust
				p.totalDust += dust
				if Codex.discover(p.codex, final) and codexAt[final] == nil then codexAt[final] = now end
				p.plants[s] = nil
			end
		end
		if profile.buy == "cheapest" then
			while true do
				local empty = 0
				for s = 1, Economy.totalSockets(p.chambers, cfg.Economy) do
					if p.plants[s] == nil then empty += 1 end
				end
				local reserve = empty * cfg.Economy.SeedCost[profile.selectTier]
				local best, bestCost = nil, math.huge
				if p.chambers < cfg.Economy.MaxChambers then
					best, bestCost = "chamber", Economy.chamberCost(p.chambers, cfg.Economy)
				end
				local luckCost = Economy.boosterCost(p.luckLevel, cfg.Boosters.Luck)
				if p.luckLevel < cfg.Boosters.Luck.MaxLevel and luckCost < bestCost then best, bestCost = "Luck", luckCost end
				local growCost = Economy.boosterCost(p.growthLevel, cfg.Boosters.Growth)
				if p.growthLevel < cfg.Boosters.Growth.MaxLevel and growCost < bestCost then best, bestCost = "Growth", growCost end
				if best == nil or p.dust - bestCost < reserve then break end
				if best == "chamber" then
					Economy.buyChamber(p, cfg.Economy)
					if chamberAt[p.chambers] == nil then chamberAt[p.chambers] = now end
				else
					Economy.buyBooster(p, best, cfg.Boosters)
				end
			end
		end
		plantAll(now)
	end
	return { chamberAt = chamberAt, codexAt = codexAt, final = p }
end

-- Many seeded sessions: for every chamber k and codex tier t, the sorted list of arrival times
-- (math.huge when a session never got there).
function IdleModel.sweep(cfg: any, profile: any, runs: number, seconds: number): any
	local chambers, codex = {}, {}
	for k = 1, cfg.Economy.MaxChambers do chambers[k] = {} end
	for t = 1, cfg.MaxTier do codex[t] = {} end
	for r = 1, runs do
		local out = IdleModel.run(cfg, profile, 1000 + r * 31, seconds)
		for k = 1, cfg.Economy.MaxChambers do table.insert(chambers[k], out.chamberAt[k] or math.huge) end
		for t = 1, cfg.MaxTier do table.insert(codex[t], out.codexAt[t] or math.huge) end
	end
	for _, list in chambers do table.sort(list) end
	for _, list in codex do table.sort(list) end
	return { chambers = chambers, codex = codex, runs = runs }
end

-- The q-quantile (0..1) of a sorted list.
function IdleModel.quantile(sorted: { number }, q: number): number
	local i = math.clamp(math.ceil(q * #sorted), 1, #sorted)
	return sorted[i]
end

return IdleModel
