-- Pacing — the brag moment's minutes, measured from the rules that ship. Run: luau tests/Pacing.spec.luau
--
-- tests/PlotModel.luau plays the game's own Economy / Meteors rules against Config.Pacing's player
-- profiles (ASSUMPTIONS until real sessions replace them) and this file asserts what the standard asks:
--   * the brag moment (catching the Falling Star) lands in 30-45 minutes of normal play;
--   * a long-term goal beyond it: the Galactic Core at least 2x later and under 3 hours;
--   * every band lasts at least 2 minutes, so no sky flashes past;
--   * the core action inside 5 seconds of joining, and the first purchase is the one the star points at;
--   * a script cannot inflate the Star Chart: a perfect bot collects at most 1.05x a normal player at the
--     same build, and an anti-AFK jiggle + auto-buy macro gains at most 1 Beacon level in 8 hours.
-- Every number it asserts on is printed.

local Config = require("../src/shared/Config")
local Model = require("./PlotModel")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config
local P = C.Pacing.Profiles
local pct = Model.pct
local BANDS = Model.BANDS
local SEEDS = 20

local function f1(x) return string.format("%.1f", x) end

--============================================================================ normal and slow followers
local runs = {}
for _, pname in { "normal", "slow", "fast" } do
	local brag, bandT = {}, {}
	for b = 1, BANDS do bandT[b] = {} end
	local list = {}
	for seed = 1, SEEDS do
		local S = Model.simulate({ profile = P[pname], seed = seed * 7919 + 17, minutes = 240, snapAt = { 2100 },
			stopWhen = function(S) return S.bandAt[BANDS] ~= nil and S.bragAt ~= nil end })
		table.insert(brag, (S.bragAt or math.huge) / 60)
		for b = 1, BANDS do table.insert(bandT[b], (S.bandAt[b] or math.huge) / 60) end
		table.insert(list, S)
	end
	runs[pname] = { brag = brag, bandT = bandT, list = list }
	local parts = {}
	for b = 2, BANDS do table.insert(parts, C.Env.Bands[b].id .. " " .. f1(pct(bandT[b], 0.5))) end
	print(string.format("  %-6s Falling Star caught at min: p10 %s  median %s  p90 %s;  bands entered (median min): %s",
		pname, f1(pct(brag, 0.1)), f1(pct(brag, 0.5)), f1(pct(brag, 0.9)), table.concat(parts, ", ")))
end

local lo, hi = C.Pacing.BragMinutes[1], C.Pacing.BragMinutes[2]
for _, pname in { "normal", "slow" } do
	local m = pct(runs[pname].brag, 0.5)
	truthy(m >= lo and m <= hi, string.format("the %s player catches the Falling Star in %s min, inside %d-%d", pname, f1(m), lo, hi))
end
do
	local r = runs.normal
	local brag = pct(r.brag, 0.5)
	local core = pct(r.bandT[BANDS], 0.5)
	print(string.format("  normal: the Galactic Core at %s min = %.2fx the brag moment", f1(core), core / brag))
	truthy(core >= 2 * brag, "the long-term goal (the Galactic Core) comes at least 2x after the brag moment")
	truthy(core < 180, "and under 3 hours")
	-- every band lasts >= 2 min, per seed (the shortest of all 20)
	local shortest, which = math.huge, ""
	for _, S in r.list do
		for b = 1, BANDS - 1 do
			local d = ((S.bandAt[b + 1] or math.huge) - (S.bandAt[b] or 0)) / 60
			if d < shortest then shortest, which = d, C.Env.Bands[b].id end
		end
	end
	print(string.format("  the shortest band of any normal seed: %s, %.1f min", which, shortest))
	truthy(shortest >= 2, "every band lasts at least 2 minutes for every normal seed")
end

--============================================================================ REVIEW-1: the hopper is rarely full on the way to the star
-- With the star buying the Smelter only when the AVERAGE inflow outran it, rares and epics overfilled the
-- hopper in bursts: the normal player's hopper was full 19.5% of the time to the star (median, 10 seeds;
-- the scripted walker 19-56%) and the dish lost 16% of its catches to it. Config.Smelter.StarHeadroom.
do
	local fulls, bounces = {}, {}
	for _, S in runs.normal.list do
		table.insert(fulls, S.preBrag.full / math.max(1, S.preBrag.ticks))
		local caught = S.preBrag.dish + S.preBrag.bounced
		if caught > 0 then table.insert(bounces, S.preBrag.bounced / caught) end
	end
	print(string.format("  normal, join to the star: hopper full %.1f%% of the time (median; p90 %.1f%%), the dish loses %.1f%% of its catches (median; p90 %.1f%%)",
		100 * pct(fulls, 0.5), 100 * pct(fulls, 0.9), 100 * pct(bounces, 0.5), 100 * pct(bounces, 0.9)))
	truthy(pct(fulls, 0.5) <= 0.08, "the normal player's hopper is full at most 8% of the time on the way to the star (median)")
	truthy(pct(bounces, 0.5) <= 0.08, "and the dish loses at most 8% of what it catches to a full hopper (median)")
end

--============================================================================ the first minute
do
	local firstPickup, firstBuy, kinds = {}, {}, {}
	for seed = 1, SEEDS do
		local S = Model.simulate({ profile = P.normal, seed = seed * 7919 + 17, minutes = 1.5 })
		table.insert(firstPickup, S.firstPickupAt or math.huge)
		table.insert(firstBuy, S.firstBuyAt or math.huge)
		kinds[S.firstBuyKind or "none"] = (kinds[S.firstBuyKind or "none"] or 0) + 1
	end
	print(string.format("  first pickup at s: median %s (max %s); first purchase at s: median %s; first purchase is a Beacon for %d of %d",
		f1(pct(firstPickup, 0.5)), f1(pct(firstPickup, 1)), f1(pct(firstBuy, 0.5)), kinds.beacon or 0, SEEDS))
	truthy(pct(firstPickup, 1) <= 5, "the core action (a pickup) happens within 5 s of joining, for every seed")
	truthy((kinds.beacon or 0) == SEEDS, "the first purchase is the Beacon the star points at, for every seed")
end

--============================================================================ the script bound
-- The same build, the same meteors: a bot with no reaction time and perfect lines at the trusted-speed
-- cap against the normal player. Frozen at the normal player's median build at 35 minutes.
local start
do
	local Ls, cs, ss = {}, {}, {}
	for _, S in runs.normal.list do
		local sn = S.snapshots[2100]
		if sn then
			table.insert(Ls, sn.L); table.insert(cs, sn.c); table.insert(ss, sn.s)
		end
	end
	start = { L = pct(Ls, 0.5), c = pct(cs, 0.5), s = pct(ss, 0.5), dust = 0, starGranted = true }
	local res = {}
	for _, pname in { "normal", "bot" } do
		local tot = {}
		for seed = 1, 10 do
			local S = Model.simulate({ profile = P[pname], seed = seed * 104729 + 3, minutes = 30, startState = start, freezeBuilds = true })
			table.insert(tot, S.minted / 30)
		end
		res[pname] = pct(tot, 0.5)
	end
	print(string.format("  frozen build L%d c%d s%d: normal %s, bot %s Stardust/min, bot/normal %.3f",
		start.L, start.c, start.s, f1(res.normal), f1(res.bot), res.bot / res.normal))
	truthy(res.bot / res.normal <= 1.05, "a perfect bot collects at most 1.05x a normal player at the same build")
end

do
	local afkL = {}
	for seed = 1, 6 do
		local A = Model.simulate({ profile = P.normal, seed = seed * 31337 + 1, minutes = 8 * 60, startState = start,
			afk = true, afkBuyEvery = 60 })
		table.insert(afkL, A.lv.beacon)
	end
	local gained = pct(afkL, 1) - start.L
	print(string.format("  anti-AFK jiggle + auto-buy macro, 8 h from Beacon %d: reaches %d at most (gains %d)", start.L, pct(afkL, 1), gained))
	truthy(gained <= 1, "the macro gains at most 1 Beacon level in 8 hours: the Collector sleeps")
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
