--!strict
-- Economy.luau — pay, Perfect Shifts, the upgrade ladder and the save sanitizer (DESIGN.md §6.4,
-- §8.1). Pure: nothing here mutates its input, and nothing requires anything.
--
-- Pay, in integers only:
--   a correct FIRST try   pays PayFirstTry + min(combo, ComboCap), combo counting this sort,
--                         grows the combo and takes one item off the backlog;
--   a correct RE-SORT     (after an earlier misfile of that item) pays PayResort, and leaves the
--                         combo and the backlog alone;
--   a misfile             pays nothing and resets the combo.
-- 30 first tries pay 11 + 12 + ... + 20 + 20 * 20 = 555; a Perfect Shift adds 100 [M 8].

local Economy = {}

export type Run = { combo: number, misfiles: number, sorted: number, firstTry: number, pay: number }

function Economy.newRun(): Run
	return { combo = 0, misfiles = 0, sorted = 0, firstTry = 0, pay = 0 }
end

-- -> the next run, what this deposit paid, and how much backlog it cleared.
function Economy.deposit(cfg: any, run: Run, correct: boolean, firstTry: boolean): (Run, number, number)
	local E = cfg.Economy
	local nextRun: Run = {
		combo = run.combo,
		misfiles = run.misfiles,
		sorted = run.sorted,
		firstTry = run.firstTry,
		pay = run.pay,
	}
	if not correct then
		nextRun.misfiles += 1
		nextRun.combo = 0
		return nextRun, 0, 0
	end
	nextRun.sorted += 1
	if firstTry then
		nextRun.combo += 1
		nextRun.firstTry += 1
		local pay = E.PayFirstTry + math.min(nextRun.combo, E.ComboCap)
		nextRun.pay += pay
		return nextRun, pay, 1
	end
	nextRun.pay += E.PayResort
	return nextRun, E.PayResort, 0
end

-- A Perfect Shift: all of them sorted, at most PerfectMaxMisfiles wrong bins, before the clock.
function Economy.isPerfect(cfg: any, sorted: number, total: number, misfiles: number, timedOut: boolean): boolean
	return not timedOut and sorted >= total and misfiles <= cfg.Shift.PerfectMaxMisfiles
end

function Economy.shiftPay(cfg: any, sortPay: number, perfect: boolean): number
	return sortPay + (if perfect then cfg.Economy.PerfectBonus else 0)
end

-- The fastest Perfect Shift, in whole seconds; 0 means none yet.
function Economy.betterBest(best: number, seconds: number): number
	if best <= 0 or seconds < best then
		return seconds
	end
	return best
end

local function clampLevel(cfg: any, level: number): number
	local n = math.floor(tonumber(level) or 0)
	return math.clamp(n, 0, cfg.Economy.MaxLevel)
end

-- The price of the NEXT level from `level`, or nil when there is none.
function Economy.price(cfg: any, level: number): number?
	return cfg.Economy.Prices[clampLevel(cfg, level) + 1]
end

function Economy.carry(cfg: any, cartLevel: number): number
	return cfg.Economy.Carry[clampLevel(cfg, cartLevel) + 1]
end

function Economy.walkSpeed(cfg: any, shoesLevel: number): number
	return cfg.Economy.WalkSpeed[clampLevel(cfg, shoesLevel) + 1]
end

local TRACK_FIELD = { cart = "cartLevel", shoes = "shoesLevel" }

-- -> true, the new profile, the price paid   |   false, "max" | "cash" | "track", the price
function Economy.buy(cfg: any, profile: any, track: string): (boolean, any, number?)
	local field = TRACK_FIELD[track]
	if field == nil then
		return false, "track", nil
	end
	local level = clampLevel(cfg, profile[field])
	local price = Economy.price(cfg, level)
	if level >= cfg.Economy.MaxLevel or price == nil then
		return false, "max", nil
	end
	if (tonumber(profile.cash) or 0) < price then
		return false, "cash", price
	end
	local nextProfile = table.clone(profile)
	nextProfile.cash = profile.cash - price
	nextProfile[field] = level + 1
	return true, nextProfile, price
end

function Economy.defaultProfile(_cfg: any)
	return {
		v = 1,
		cash = 0,
		cartLevel = 0,
		shoesLevel = 0,
		shifts = 0,
		perfects = 0,
		backlog = 0,
		bestPerfectSeconds = 0,
		endingSeen = false,
		redeemed = {} :: { [string]: boolean },
	}
end

local MAX_SAFE = 9007199254740991

-- A non-negative whole number, or 0 for anything else (NaN, infinities, strings, tables).
local function count(v: any): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	local n = math.floor(v)
	if n < 0 then
		return 0
	end
	return math.min(n, MAX_SAFE)
end

-- Every load runs this. Unknown keys are dropped, so nothing about a shift can come back from a
-- save — resuming a shift would mean persisting the cart queue, which must never leave the server.
function Economy.sanitize(cfg: any, raw: any)
	local p = Economy.defaultProfile(cfg)
	if type(raw) ~= "table" then
		return p
	end
	p.cash = count(raw.cash)
	p.cartLevel = math.min(count(raw.cartLevel), cfg.Economy.MaxLevel)
	p.shoesLevel = math.min(count(raw.shoesLevel), cfg.Economy.MaxLevel)
	p.shifts = count(raw.shifts)
	p.perfects = math.min(count(raw.perfects), p.shifts)
	p.backlog = math.min(count(raw.backlog), cfg.Economy.BacklogSize)
	p.bestPerfectSeconds = count(raw.bestPerfectSeconds)
	p.endingSeen = raw.endingSeen == true
	if type(raw.redeemed) == "table" then
		for k, v in raw.redeemed do
			if type(k) == "string" and #k > 0 and #k <= cfg.Codes.MaxLength and v == true then
				p.redeemed[k] = true
			end
		end
	end
	return p
end

-- A session that did not hold the save lock (another server's lock had not expired at join, or
-- the load failed and it started from defaults) writes its OWN DELTA on top of what the store
-- holds now: stored + (current - base), clamped by sanitize. Never its whole profile, because the
-- store may hold progress this session never saw (REVIEW-1 R1-3, R2-6). Pure; mutates nothing.
function Economy.merge(cfg: any, storedRaw: any, baseRaw: any, currentRaw: any)
	local stored = Economy.sanitize(cfg, storedRaw)
	local base = Economy.sanitize(cfg, baseRaw)
	local current = Economy.sanitize(cfg, currentRaw)
	local out = Economy.defaultProfile(cfg)
	local E = cfg.Economy
	-- PURCHASES ARE RE-PRICED, NOT ADDED. A level this session bought on its own (stale) balance lands
	-- on the stored level and costs THAT level's price; a level past MaxLevel is not bought at all; and
	-- a purchase the stored cash plus this session's earnings cannot cover is undone, most expensive
	-- first. Adding the cash delta and flooring it at 0 kept every purchase: a server hop let 1050
	-- cash buy 2100 of upgrades (REVIEW-1 pass 3, exploit finding 2).
	local function cost(from: number, to: number): number
		local total = 0
		for l = from + 1, to do
			total += E.Prices[l]
		end
		return total
	end
	-- -> the level a track lands on, and what the re-pricing refunds (+) or charges (-)
	local function landed(storedLevel: number, baseLevel: number, currentLevel: number): (number, number)
		local bought = math.max(0, currentLevel - baseLevel)
		local fits = math.clamp(bought, 0, E.MaxLevel - storedLevel)
		return storedLevel + fits, cost(baseLevel, baseLevel + bought) - cost(storedLevel, storedLevel + fits)
	end
	local cart, cartAdjust = landed(stored.cartLevel, base.cartLevel, current.cartLevel)
	local shoes, shoesAdjust = landed(stored.shoesLevel, base.shoesLevel, current.shoesLevel)
	local cash = stored.cash + (current.cash - base.cash) + cartAdjust + shoesAdjust
	while cash < 0 do
		local cartRefund = if cart > stored.cartLevel then E.Prices[cart] else 0
		local shoesRefund = if shoes > stored.shoesLevel then E.Prices[shoes] else 0
		if cartRefund == 0 and shoesRefund == 0 then
			break
		end
		if cartRefund >= shoesRefund then
			cart -= 1
			cash += cartRefund
		else
			shoes -= 1
			cash += shoesRefund
		end
	end
	out.cash = cash
	out.cartLevel = cart
	out.shoesLevel = shoes
	out.shifts = stored.shifts + (current.shifts - base.shifts)
	out.perfects = stored.perfects + (current.perfects - base.perfects)
	out.backlog = stored.backlog + (current.backlog - base.backlog)
	local best = stored.bestPerfectSeconds
	if current.bestPerfectSeconds > 0 then
		best = Economy.betterBest(best, current.bestPerfectSeconds)
	end
	out.bestPerfectSeconds = best
	out.endingSeen = stored.endingSeen or current.endingSeen
	for code in stored.redeemed do
		out.redeemed[code] = true
	end
	for code in current.redeemed do
		out.redeemed[code] = true
	end
	return Economy.sanitize(cfg, out)
end

return Economy
