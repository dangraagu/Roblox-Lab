-- Economy.spec: prices, refunds, caps and the rules that keep the seed economy honest (DESIGN.md §3.2-§3.3).
-- Run: luau tests/Economy.spec.luau

local Config = require("../src/shared/Config")
local Waves = require("../src/shared/Waves")
local PathGen = require("../src/shared/PathGen")
local Garden = require("../src/shared/Garden")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local DEPS = { Waves = Waves, PathGen = PathGen }

--====================================================================== prices
do
	local worst, worstName = math.huge, ""
	for kind, def in Config.Gnomes do
		eq(#def.levels, 3, kind .. " has three levels (plant, two upgrades)")
		local paid, first = 0, nil
		for i, lv in def.levels do
			truthy(lv.cost > 0 and lv.cost % 1 == 0, kind .. " L" .. i .. " costs a whole number of seeds")
			paid += lv.cost
			local perSeed = (lv.dmg / lv.cd) / paid
			first = first or perSeed
			if perSeed / first < worst then worst, worstName = perSeed / first, kind .. " L" .. i end
			if i > 1 then
				truthy(lv.dmg > def.levels[i - 1].dmg, kind .. " L" .. i .. " hits harder than L" .. (i - 1))
				truthy(lv.range >= def.levels[i - 1].range, kind .. " L" .. i .. " reaches at least as far")
			end
		end
	end
	print(string.format("Economy: the worst upgrade keeps %.1f%% of planting's damage per seed (%s)", worst * 100, worstName))
	truthy(worst >= 0.95, "no upgrade drops below 95% of planting's damage per seed")
end

--====================================================================== the start and the first seconds
do
	eq(Config.Chapters[1].seeds, 120, "spring starts with 120 seeds")
	eq(math.floor(Config.Chapters[1].seeds / Config.Gnomes.pebble.levels[1].cost), 2, "which buys exactly two pebbles: the core action, free")
	for c = 2, #Config.Chapters do
		truthy(Config.Chapters[c].seeds > Config.Chapters[c - 1].seeds, "chapter " .. c .. " starts richer than chapter " .. (c - 1))
	end
	eq(Config.Chapters[#Config.Chapters].endless, true, "the last chapter is the endless one")
	-- every chapter unlocks at most one new gnome, and every gnome is unlocked by some chapter
	local unlockedBy = {}
	for c, ch in Config.Chapters do
		for _, k in ch.unlock do unlockedBy[k] = c end
	end
	for kind in Config.Gnomes do
		truthy(unlockedBy[kind] ~= nil, kind .. " is unlocked by a chapter")
	end
end

--====================================================================== income
do
	-- bounty grows inside a chapter, but slower than hit points (a chapter gets harder toward its boss)
	for _, kind in { "aphid", "beetle", "snail" } do
		local b1, b10 = Waves.bounty(Config, kind, 1), Waves.bounty(Config, kind, 10)
		truthy(b10 >= b1, kind .. ": a wave-10 bounty is at least a wave-1 bounty")
		local hp1, hp10 = Config.Bugs[kind].hp * Waves.hpMult(Config, 1), Config.Bugs[kind].hp * Waves.hpMult(Config, 10)
		truthy(b10 / b1 < hp10 / hp1, kind .. ": bounty grows slower than hit points (" .. b10 .. "/" .. b1 .. " vs x" .. string.format("%.2f", hp10 / hp1) .. ")")
	end
	eq(Waves.clearBonus(Config, 1), 18, "surviving wave 1 pays 18")
	eq(Waves.clearBonus(Config, 10), 45, "surviving a boss wave pays 45")
	eq(Waves.clearBonus(Config, 11), 18, "and the next chapter starts the count again")
	for _, boss in Config.BossCycle do
		eq(Config.Bugs[boss].bite, Config.Carrots, Config.Bugs[boss].name .. " eats the whole patch")
	end
end

--====================================================================== caps and refunds
do
	truthy(Config.SellRefund < 1, "selling returns less than was paid (once the bed's first wave has come)")
	eq(Config.RevealRefund, 1, "before it, a sale gives everything back: nothing has been fought, nothing is gained")
	local minPads = math.huge
	for s = 1, 200 do
		minPads = math.min(minPads, #PathGen.pads(Config, PathGen.genPath(Config, Rng.new(77000 + s))))
	end
	truthy(minPads >= Config.MaxGnomes, "every bed has room for the full 14 gnomes (fewest pads over 200 beds: " .. minPads .. ")")
	-- a plant/sell loop on one pad loses 30% every time, after the bed's first wave (a played wave 11, as the
	-- server plays it: READY, fixed steps, finishWave)
	local g = Garden.new(Config, 2, PathGen.genPath(Config, Rng.new(5)), DEPS)
	assert(Garden.plant(Config, g, "pebble", 3))
	assert(Garden.ready(Config, g))
	while g.phase == "wave" and not g.waveDone do Garden.step(Config, g, Config.Dt) end
	Garden.finishWave(Config, g)
	eq(g.phase, "build", "(wave 11 survived: the build phase)")
	local start = g.seeds
	assert(Garden.plant(Config, g, "mushroom", 1))
	local _, refund = Garden.sell(Config, g, 1)
	eq(refund, 77, "a mushroom (110) sells for 77")
	eq(start - g.seeds, 33, "so a plant and sell costs 33 seeds")
	-- upgrade then sell: 70% of everything paid in
	assert(Garden.plant(Config, g, "pebble", 2))
	assert(Garden.upgrade(Config, g, 2))
	local _, r2 = Garden.sell(Config, g, 2)
	eq(r2, math.floor((50 + 70) * Config.SellRefund), "an upgraded pebble returns 70% of 120")
end

--====================================================================== nothing for Robux
do
	local found = {}
	local function scan(t, path)
		for k, v in t do
			local lk = string.lower(tostring(k))
			if string.find(lk, "robux", 1, true) or string.find(lk, "gamepass", 1, true) or string.find(lk, "product", 1, true) then
				table.insert(found, path .. "." .. tostring(k))
			end
			if type(v) == "table" then scan(v, path .. "." .. tostring(k)) end
		end
	end
	scan(Config, "Config")
	eq(#found, 0, "the config has no Robux price, game pass or developer product (" .. table.concat(found, ", ") .. ")")
end

print(("Economy: %d passed, %d failed"):format(passed, failed))
