--!strict
-- Economy.luau — prices, rates, the dish, the hopper, melting and the HUD's star. PURE.
--
-- Every function takes the game's Config as `cfg` and requires nothing (a bare `require("./X")`
-- resolves in the luau CLI and is INVALID in Roblox). The server uses this for every purchase and
-- every gram of ore; the HUD uses it to price and star the upgrade rows; tests/PlotModel.luau uses it
-- to measure the pacing, so the model and the game can never drift apart. Spec: tests/Economy.spec.luau.

local Economy = {}

Economy.KINDS = { "beacon", "collector", "smelter" }
local IS_KIND = { beacon = true, collector = true, smelter = true }

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

--============================================================================ rates
function Economy.spawnInterval(cfg: any, L: number): number
	local b = cfg.Beacon
	return math.max(b.SpawnIntervalMin, b.SpawnInterval0 * b.SpawnIntervalDecay ^ L)
end

function Economy.baseOre(cfg: any, L: number): number
	return cfg.Beacon.OreGrowth ^ L
end

function Economy.oreOf(cfg: any, L: number, rarity: string): number
	local def = cfg.Rarities.Defs[rarity]
	return Economy.baseOre(cfg, L) * (if def then def.mult else 1)
end

function Economy.smeltRate(cfg: any, s: number): number
	return cfg.Smelter.Rate0 * cfg.Smelter.RateGrowth ^ s
end

function Economy.hopperCap(cfg: any, s: number): number
	return Economy.smeltRate(cfg, s) * cfg.Smelter.HopperSeconds
end

--============================================================================ prices
local function round(x: number): number
	return math.floor(x + 0.5)
end

function Economy.beaconPrice(cfg: any, L: number): number
	return round(cfg.Beacon.Price0 * cfg.Beacon.PriceGrowth ^ L)
end

function Economy.collectorPrice(cfg: any, c: number): number?
	if c >= cfg.Collector.Max then return nil end
	return round(cfg.Collector.Price0 * cfg.Collector.PriceGrowth ^ c)
end

function Economy.smelterPrice(cfg: any, s: number): number
	return round(cfg.Smelter.Price0 * cfg.Smelter.PriceGrowth ^ s)
end

-- lv = { beacon, collector, smelter }. nil for an unknown kind or a maxed Collector.
function Economy.price(cfg: any, kind: string, lv: any): number?
	if kind == "beacon" then return Economy.beaconPrice(cfg, lv.beacon) end
	if kind == "collector" then return Economy.collectorPrice(cfg, lv.collector) end
	if kind == "smelter" then return Economy.smelterPrice(cfg, lv.smelter) end
	return nil
end

--============================================================================ the dish
function Economy.dishRadius(cfg: any, c: number): number
	if c <= 0 then return 0 end
	return cfg.Collector.Radius1 + cfg.Collector.RadiusStep * (c - 1)
end

-- Share of landings (uniform by area in LandInner..LandOuter) inside the dish.
function Economy.dishShare(cfg: any, c: number): number
	local r = Economy.dishRadius(cfg, c)
	local ri, ro = cfg.Plot.LandInner, cfg.Plot.LandOuter
	if r <= ri then return 0 end
	r = math.min(r, ro)
	return (r * r - ri * ri) / (ro * ro - ri * ri)
end

--============================================================================ bands and the meteor mix
-- The band a Beacon level is in: the last band whose `from` <= L (EnvBands.indexAt's rule, which the
-- spec checks level by level so the meteor mix and the sky can never name different bands).
function Economy.bandIndex(cfg: any, L: number): number
	local bands = cfg.Env.Bands
	local idx = 1
	for i = 2, #bands do
		if L >= bands[i].from then idx = i else break end
	end
	return idx
end

function Economy.avgMult(cfg: any, band: number): number
	local mix = cfg.Env.Bands[band].mix
	local m = 0
	for _, r in cfg.Rarities.Order do
		m += (mix[r] or 0) / 1000 * cfg.Rarities.Defs[r].mult
	end
	return m
end

-- Expected ore per second arriving on a plot at Beacon L (before the dish / hand / burn split).
function Economy.inflow(cfg: any, L: number): number
	return Economy.avgMult(cfg, Economy.bandIndex(cfg, L)) * Economy.baseOre(cfg, L) / Economy.spawnInterval(cfg, L)
end

--============================================================================ the HUD's star
-- Steady income an ACTIVE player gets from a build: the dish's share, plus what they walk to at the
-- pace the HUD assumes (HudHandRate meteors/s), capped by the Smelter. Legendaries are ignored: the
-- star should not chase a 0.5-2% event. The Smelter's cap is StarHeadroom x its rated melt (REVIEW-1):
-- rares and epics arrive in bursts, and a Smelter that only matches the average inflow keeps the hopper
-- full a fifth of the time, refusing pickups and bouncing dish catches.
function Economy.steadyIncome(cfg: any, L: number, c: number, s: number): number
	local si = Economy.spawnInterval(cfg, L)
	local share = Economy.dishShare(cfg, c)
	local outsidePerSecond = (1 - share) / si
	local hand = math.min(outsidePerSecond, cfg.Collector.HudHandRate)
	local caught = share + hand * si
	return math.min(Economy.smeltRate(cfg, s) * (cfg.Smelter.StarHeadroom or 1), Economy.inflow(cfg, L) * caught)
end

-- The share of recent time the hopper was full: a moving average with half-life Smelter.FullHalfLife.
function Economy.fullEma(cfg: any, ema: number, full: boolean, dt: number): number
	if not finite(dt) or dt <= 0 then return ema end
	local a = 1 - 0.5 ^ (dt / cfg.Smelter.FullHalfLife)
	return ema + ((if full then 1 else 0) - ema) * a
end

-- (kind, price): the machine that adds the most steady income per Stardust. When nothing adds income
-- (the Smelter exactly matches what is caught), the cheaper of Beacon and Smelter: they move together,
-- so the star never goes dark. Never a maxed Collector. `fullShare` (optional, Economy.fullEma) is what the
-- hopper actually did: at Smelter.StarFullShare or more the Smelter is the bottleneck, whatever the steady
-- rule's assumed pace says (REVIEW-1).
function Economy.bestNext(cfg: any, L: number, c: number, s: number, fullShare: number?): (string, number)
	if fullShare ~= nil and fullShare >= cfg.Smelter.StarFullShare then
		return "smelter", Economy.smelterPrice(cfg, s)
	end
	local now = Economy.steadyIncome(cfg, L, c, s)
	local best, bestPrice, bestGain = nil, 0, -1
	local function consider(kind: string, price: number?, after: number)
		if price == nil then return end
		local gain = (after - now) / price
		if gain > bestGain + 1e-12 or (math.abs(gain - bestGain) <= 1e-12 and price < bestPrice) then
			best, bestPrice, bestGain = kind, price, gain
		end
	end
	consider("beacon", Economy.beaconPrice(cfg, L), Economy.steadyIncome(cfg, L + 1, c, s))
	consider("smelter", Economy.smelterPrice(cfg, s), Economy.steadyIncome(cfg, L, c, s + 1))
	local cp = Economy.collectorPrice(cfg, c)
	if cp then consider("collector", cp, Economy.steadyIncome(cfg, L, c + 1, s)) end
	if best == nil or bestGain <= 1e-12 then
		local bp, sp = Economy.beaconPrice(cfg, L), Economy.smelterPrice(cfg, s)
		if bp <= sp then return "beacon", bp end
		return "smelter", sp
	end
	return best :: string, bestPrice
end

--============================================================================ buying
-- st = { beacon, collector, smelter, stardust }. (ok, why, price): why is "unknown" | "max" | "afford".
function Economy.check(cfg: any, st: any, kind: any): (boolean, string?, number?)
	if type(kind) ~= "string" or not IS_KIND[kind] then
		return false, "unknown", nil
	end
	local price = Economy.price(cfg, kind, st)
	if price == nil then
		return false, "max", nil
	end
	if not finite(st.stardust) or st.stardust < price then
		return false, "afford", price
	end
	return true, nil, price
end

function Economy.buy(cfg: any, st: any, kind: any): (boolean, string?, number?)
	local ok, why, price = Economy.check(cfg, st, kind)
	if not ok then return false, why, price end
	st.stardust -= price :: number
	st[kind] += 1
	return true, nil, price
end

function Economy.refusalText(cfg: any, why: string?, price: number?, stardust: number?): string
	if why == "afford" then
		return string.format("Need %s Stardust, you have %s", Economy.short(price or 0), Economy.short(stardust or 0))
	elseif why == "max" then
		return "Your Collector is at its biggest"
	elseif why == "loading" then
		return "Loading your plot…"
	end
	return "That is not something you can buy"
end

-- The "Hopper full!" refusal. It never contradicts the HUD's star (REVIEW-1: it always said "Upgrade the
-- Smelter", while the star was on the Beacon or the Collector in about half of the full moments): it names
-- the Smelter only when the star is on it, and otherwise says when the hopper takes meteors again (it
-- accepts while below its cap, so that is the time to melt the overfill, at least 1 s).
-- st = { hopper, smelter }; best = Economy.bestNext's kind.
function Economy.fullText(cfg: any, st: any, best: string): string
	if best == "smelter" then
		return "Hopper full! ★ Upgrade the Smelter, or wait a moment for it to melt."
	end
	local over = st.hopper - Economy.hopperCap(cfg, st.smelter)
	local secs = math.max(1, math.ceil(over / Economy.smeltRate(cfg, st.smelter) - 1e-9))
	return string.format("Hopper full! It takes meteors again in %d s.", secs)
end

--============================================================================ ore in, Stardust out
-- A hand pickup. "instant": a legendary, paid at once and never in the hopper (it cannot clog the
-- Smelter at the brag moment, DESIGN 4.3); "hopper": accepted while the hopper is BELOW its cap even if
-- the meteor overfills it; "refused": the hopper is full, the meteor stays where it is.
function Economy.collect(cfg: any, st: any, rarity: string, ore: number): string
	if not finite(ore) or ore < 0 then return "refused" end
	if rarity == "legendary" then
		st.stardust += ore
		st.lifetime += ore
		return "instant"
	end
	if st.hopper < Economy.hopperCap(cfg, st.smelter) then
		st.hopper += ore
		return "hopper"
	end
	return "refused"
end

-- A dish catch lands in the hopper under the same below-the-cap rule, or bounces off and is lost.
function Economy.dishCatch(cfg: any, st: any, ore: number): string
	if finite(ore) and ore >= 0 and st.hopper < Economy.hopperCap(cfg, st.smelter) then
		st.hopper += ore
		return "hopper"
	end
	return "bounced"
end

-- Melt dt seconds: hopper -> Stardust 1:1 at the Smelter's rate. Returns the amount melted.
function Economy.melt(cfg: any, st: any, dt: number): number
	if not finite(dt) or dt <= 0 or not finite(st.hopper) or st.hopper <= 0 then return 0 end
	local take = math.min(st.hopper, Economy.smeltRate(cfg, st.smelter) * dt)
	st.hopper -= take
	if st.hopper < 1e-12 then st.hopper = 0 end
	st.stardust += take
	st.lifetime += take
	return take
end

--============================================================================ formatting
local SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- "999", "1.2K", "12.3K", "123K", "3.4M". Rounded DOWN, so the HUD never shows more than you have.
function Economy.short(n: number): string
	if not finite(n) or n <= 0 then return "0" end
	if n < 1000 then return tostring(math.floor(n)) end
	local i = 0
	local v = n
	while v >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	if v < 100 then
		local t = math.floor(v * 10) / 10
		return string.format("%.1f%s", t, SUFFIX[i])
	end
	return string.format("%d%s", math.floor(v), SUFFIX[i])
end

return Economy
