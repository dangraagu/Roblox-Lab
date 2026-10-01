--!strict
-- pacing-model.luau — DESIGN-TIME model for StormGrow: Mutation Farm. Not game code, not shipped.
--
-- Every timing number in ../DESIGN.md that says "modelled" comes from this file. It carries its own
-- copy of the design numbers (the tables below mirror DESIGN.md §2). When the game is built,
-- tests/Pacing.spec.luau must re-measure the same quantities against the REAL src/shared/Config.luau
-- and the real pure modules; this file is then retired, not kept in sync.
--
-- Run:  luau design/pacing-model.luau        (from D:\Claude\Roblox\stormgrow)
--
-- What it simulates, second by second:
--   * the global weather clock (DESIGN.md §2.1), aligned to Unix time, joined at a random phase;
--   * strike ticks every TickSeconds during an event: each RIPE crop lacking that event's mark gets it
--     with a per-tick chance q, where 1 - (1 - q)^ticks = the event's per-crop chance;
--   * a player who sweeps the farm every `checkEvery` seconds; one tap = harvest + replant, costing
--     `tap` seconds; a ripe crop is HELD (not harvested) while an event runs or one starts within
--     `holdHorizon` seconds (the HUD's "keep ripe crops in the ground" cue);
--   * purchases: cheapest affordable of {next field, next crop unlock}; a new crop becomes the
--     selected seed (the HUD auto-selects the newest unlock);
--   * hazards: a reacting player spends `dodge` seconds stepping out of a ring once per
--     HazardEverySeconds of play from band 2 on (DESIGN.md §4);
--   * no offline growth: every minute is a minute played; rest excluded.

local M = {}

---------------------------------------------------------------------------------------------- numbers
M.Weather = {
	Cycle = 600, -- a storm starts every 10 minutes: :00, :10, :20 ...
	StormFrom = 0, StormLen = 90,
	RainbowFrom = 90, RainbowLen = 60, -- only in the first cycle of each 30 minutes (:01:30, :31:30)
	FrostFrom = 300, FrostLen = 90, -- :05, :15, :25 ...
	TickSeconds = 5,
	Chance = { storm = 0.5, frost = 0.5, rainbow = 0.35 },
}

-- id, unlock price, seed price, sell value, grow seconds
M.Crops = {
	{ id = "radish", unlock = 0, seed = 0, sell = 5, grow = 30 },
	{ id = "carrot", unlock = 50, seed = 5, sell = 20, grow = 60 },
	{ id = "corn", unlock = 250, seed = 20, sell = 80, grow = 120 },
	{ id = "tomato", unlock = 1000, seed = 60, sell = 280, grow = 180 },
	{ id = "sunflower", unlock = 3500, seed = 150, sell = 750, grow = 240 },
	{ id = "pumpkin", unlock = 10000, seed = 400, sell = 2400, grow = 360 },
	{ id = "watermelon", unlock = 35000, seed = 1000, sell = 6500, grow = 480 },
	{ id = "stormfruit", unlock = 120000, seed = 2500, sell = 20000, grow = 720, needBand = 6 },
}

M.StartCoins = 20
M.TilesPerField = 9
M.FieldCosts = { 400, 3000, 20000, 1500000, 6000000 } -- fields 2..6 (field 1 is free)

-- mark bits: 1 = Charged (storm), 2 = Frosted (frost), 4 = Prismatic (rainbow)
M.Mult = { [0] = 1, [1] = 5, [2] = 5, [4] = 8, [3] = 25, [5] = 40, [6] = 40, [7] = 200 } -- marks multiply: 5x5, 5x8, 5x8, 5x5x8

-- worth thresholds (lifetime coins earned) of bands 2..7; band 1 starts at 0
M.Bands = { 150, 1200, 9000, 55000, 300000, 11000000 }
M.BandNames = { "Sunny Meadow", "Golden Fields", "Windy Orchard", "Thunder Plains", "Frost Highlands", "Eye of the Storm", "Starfall Summit" }

M.HazardEverySeconds = 150 -- mean of the 120..180 s clock

M.Profiles = {
	normal = { checkEvery = 15, tap = 1.0, holdHorizon = 60, dodge = 1.5 },
	fast = { checkEvery = 5, tap = 0.7, holdHorizon = 90, dodge = 1.0 },
	slow = { checkEvery = 40, tap = 1.5, holdHorizon = 30, dodge = 2.5 },
	-- ignores the forecast entirely: harvests the moment it looks, never holds for weather
	nohold = { checkEvery = 15, tap = 1.0, holdHorizon = -1, dodge = 1.5, neverHold = true },
	-- the Almanac hunter: also holds a marked crop when the NEXT event could add a mark it lacks
	-- and starts within comboHorizon seconds, and plants the unlocked crop with the fewest entries
	planner = { checkEvery = 10, tap = 1.0, holdHorizon = 90, dodge = 1.5, combo = true, comboHorizon = 420, hunt = true },
	-- a normal player who has read the Almanac hint: keeps marked crops for the next event, no hunting
	combo = { checkEvery = 15, tap = 1.0, holdHorizon = 60, dodge = 1.5, combo = true, comboHorizon = 420 },
}

----------------------------------------------------------------------------------------------- weather
-- (kind, startedAt, endsAt) for Unix-aligned second t; kind "clear" has no window.
function M.weatherAt(t: number): (string, number, number)
	local W = M.Weather
	local base = t - t % W.Cycle
	local p = t % W.Cycle
	local golden = (t % (3 * W.Cycle)) < W.Cycle
	if p >= W.StormFrom and p < W.StormFrom + W.StormLen then
		return "storm", base + W.StormFrom, base + W.StormFrom + W.StormLen
	end
	if golden and p >= W.RainbowFrom and p < W.RainbowFrom + W.RainbowLen then
		return "rainbow", base + W.RainbowFrom, base + W.RainbowFrom + W.RainbowLen
	end
	if p >= W.FrostFrom and p < W.FrostFrom + W.FrostLen then
		return "frost", base + W.FrostFrom, base + W.FrostFrom + W.FrostLen
	end
	return "clear", 0, 0
end

-- (kind, startsAt) of the first event starting strictly after t. Events start on multiples of 30 s.
function M.nextEvent(t: number): (string, number)
	local s = (math.floor(t / 30) + 1) * 30
	while true do
		local k, st = M.weatherAt(s)
		if k ~= "clear" and st == s then
			return k, st
		end
		s += 30
	end
end

local BIT = { storm = 1, frost = 2, rainbow = 4 }

local function perTick(event: string): number
	local W = M.Weather
	local len = if event == "rainbow" then W.RainbowLen elseif event == "frost" then W.FrostLen else W.StormLen
	local ticks = len / W.TickSeconds
	return 1 - (1 - W.Chance[event]) ^ (1 / ticks)
end

------------------------------------------------------------------------------------------------ player
local function bandOf(worth: number): number
	local b = 1
	for i, th in ipairs(M.Bands) do
		if worth >= th then b = i + 1 end
	end
	return b
end

-- One session of `seconds` played. joinUnix: the Unix second of the join (sets the weather phase).
function M.run(profile: any, seed: number, joinUnix: number, seconds: number): any
	math.randomseed(seed)
	local p = {
		coins = M.StartCoins, worth = 0, fields = 1, unlocked = 1, selected = 1,
		tiles = {}, almanac = {}, almanacCount = 0,
	}
	local out = { bandAt = { [1] = 0 }, almanacAt = {}, firstMark = nil, firstCombo = nil, firstTempest = nil, harvests = 0, marked = 0, boughtAt = {}, worthAt = {} }
	local nextCheck = 0
	local hazardClock = 0
	local lastBand = 1

	local function tileCount(): number
		return p.fields * M.TilesPerField
	end

	local function isRipe(tile: any, now: number): boolean
		return tile ~= nil and now >= tile.at + M.Crops[tile.c].grow
	end

	-- The HUD's rule, which the normal player follows: while an event runs, or one starts within
	-- holdHorizon, leave ripe crops in the ground, EXCEPT a crop that already carries the running
	-- event's mark (it cannot gain more from this event; the HUD shows it as "tap to harvest xN").
	-- The planner also keeps a marked crop when the next event could add a mark it lacks.
	local function comboWait(tile: any, now: number): boolean
		if not profile.combo or tile.m == 0 or tile.m == 7 then return false end
		local nk, ns = M.nextEvent(now)
		return bit32.band(tile.m, BIT[nk]) == 0 and ns - now <= profile.comboHorizon
	end
	local function held(tile: any, now: number): boolean
		if profile.neverHold then return false end
		local kind = M.weatherAt(now)
		if kind ~= "clear" then
			if bit32.band(tile.m, BIT[kind]) ~= 0 then return comboWait(tile, now) end
			return true
		end
		local _, ns = M.nextEvent(now)
		if ns - now <= profile.holdHorizon then return true end
		return comboWait(tile, now)
	end

	local function grant(tile: any, now: number)
		local key = tile.c * 8 + tile.m
		if not p.almanac[key] then
			p.almanac[key] = now
			p.almanacCount += 1
			out.almanacAt[p.almanacCount] = now
		end
	end

	local function pickCrop(): number
		if profile.hunt then
			-- fewest entries among unlocked crops, ties to the richer crop
			local best, bestN = p.unlocked, math.huge
			for c = p.unlocked, 1, -1 do
				local n = 0
				for m = 1, 7 do
					if p.almanac[c * 8 + m] then n += 1 end
				end
				if n < bestN and p.coins >= M.Crops[c].seed then best, bestN = c, n end
			end
			return best
		end
		local c = p.selected
		while c > 1 and p.coins < M.Crops[c].seed do c -= 1 end
		return c
	end

	local function buy()
		while true do
			local fieldPrice = M.FieldCosts[p.fields] -- next field (index = fields owned)
			local nextCrop = M.Crops[p.unlocked + 1]
			local cropPrice = if nextCrop and bandOf(p.worth) >= (nextCrop.needBand or 1) then nextCrop.unlock else nil
			local choice, price = nil, math.huge
			if fieldPrice and fieldPrice < price then choice, price = "field", fieldPrice end
			if cropPrice and cropPrice < price then choice, price = "crop", cropPrice end
			if choice == nil or p.coins < price then return end
			p.coins -= price
			if choice == "field" then
				p.fields += 1
				out.boughtAt["field " .. p.fields] = out.now
			else
				out.boughtAt[M.Crops[p.unlocked + 1].id] = out.now
				p.unlocked += 1
				p.selected = p.unlocked
			end
		end
	end

	for t = 0, seconds - 1 do
		local now = joinUnix + t
		out.now = t
		if t % 60 == 0 then out.worthAt[t // 60] = p.worth end
		-- weather strike ticks
		local kind = M.weatherAt(now)
		if kind ~= "clear" and now % M.Weather.TickSeconds == 0 then
			local q = perTick(kind)
			local b = BIT[kind]
			for i = 1, tileCount() do
				local tile = p.tiles[i]
				if isRipe(tile, now) and bit32.band(tile.m, b) == 0 and math.random() < q then
					tile.m = bit32.bor(tile.m, b)
					out.marked += 1
					out.firstMark = out.firstMark or t
					if tile.m == 3 or tile.m == 5 or tile.m == 6 then out.firstCombo = out.firstCombo or t end
					if tile.m == 7 then out.firstTempest = out.firstTempest or t end
					grant(tile, t)
				end
			end
		end
		-- the player's sweep
		if t >= nextCheck then
			buy()
			local elapsed = 0
			for i = 1, tileCount() do
				local tile = p.tiles[i]
				local clock = now + elapsed
				if tile ~= nil and isRipe(tile, clock) and not held(tile, clock) then
					local v = M.Crops[tile.c].sell * M.Mult[tile.m]
					p.coins += v
					p.worth += v
					out.harvests += 1
					p.tiles[i] = nil
					tile = nil
				end
				if tile == nil then
					local c = pickCrop()
					p.coins -= M.Crops[c].seed
					p.tiles[i] = { c = c, at = clock + profile.tap, m = 0 }
					elapsed += profile.tap
				end
			end
			buy()
			-- hazards: from band 2 on, one ring to step out of per HazardEverySeconds of play
			if bandOf(p.worth) >= 2 then
				hazardClock += elapsed + profile.checkEvery
				while hazardClock >= M.HazardEverySeconds do
					hazardClock -= M.HazardEverySeconds
					elapsed += profile.dodge
				end
			end
			nextCheck = t + math.max(1, math.floor(elapsed + profile.checkEvery + 0.5))
		end
		local b = bandOf(p.worth)
		while lastBand < b do
			lastBand += 1
			out.bandAt[lastBand] = t
		end
	end
	out.final = p
	return out
end

------------------------------------------------------------------------------------------------ report
local function pct(list: { number }, q: number): number
	if #list == 0 then return math.huge end
	table.sort(list)
	local i = math.clamp(math.floor(q * (#list - 1) + 0.5) + 1, 1, #list)
	return list[i]
end

local function fmt(sec: number): string
	if sec == math.huge then return "   never" end
	return string.format("%7.1f", sec / 60)
end

function M.report(runs: number, seconds: number)
	local JOIN0 = 1790000000 -- 2026-09-21 13:33:20 UTC; only its phase matters
	for _, name in { "normal", "fast", "slow", "nohold", "combo", "planner" } do
		local prof = M.Profiles[name]
		local bandT = {}
		for b = 1, #M.BandNames do bandT[b] = {} end
		local firstMark, firstCombo, firstTempest = {}, {}, {}
		local alm30, alm60, alm180, almAll = {}, {}, {}, {}
		for r = 1, runs do
			local join = JOIN0 + ((r * 7919) % 1800)
			local o = M.run(prof, 1000 + r, join, seconds)
			for b = 1, #M.BandNames do
				table.insert(bandT[b], o.bandAt[b] or math.huge)
			end
			table.insert(firstMark, o.firstMark or math.huge)
			table.insert(firstCombo, o.firstCombo or math.huge)
			table.insert(firstTempest, o.firstTempest or math.huge)
			local function countBy(limit: number): number
				local n = 0
				for _, at in o.almanacAt do
					if at <= limit then n += 1 end
				end
				return n
			end
			table.insert(alm30, countBy(1800))
			table.insert(alm60, countBy(3600))
			table.insert(alm180, countBy(10800))
			table.insert(almAll, o.almanacAt[56] or math.huge)
		end
		print(string.format("== %s (%d runs, %d min each; minutes: p10 / median / p90)", name, runs, seconds // 60))
		for b = 2, #M.BandNames do
			print(string.format("  band %d %-16s %s %s %s", b, M.BandNames[b], fmt(pct(bandT[b], 0.1)), fmt(pct(bandT[b], 0.5)), fmt(pct(bandT[b], 0.9))))
		end
		print(string.format("  first mutation           %s %s %s", fmt(pct(firstMark, 0.1)), fmt(pct(firstMark, 0.5)), fmt(pct(firstMark, 0.9))))
		print(string.format("  first double (combo)     %s %s %s", fmt(pct(firstCombo, 0.1)), fmt(pct(firstCombo, 0.5)), fmt(pct(firstCombo, 0.9))))
		print(string.format("  first Tempest            %s %s %s", fmt(pct(firstTempest, 0.1)), fmt(pct(firstTempest, 0.5)), fmt(pct(firstTempest, 0.9))))
		print(string.format("  almanac entries @30/60/180 min (median): %d / %d / %d ; all 56 by (min, median): %s",
			pct(alm30, 0.5), pct(alm60, 0.5), pct(alm180, 0.5), fmt(pct(almAll, 0.5))))
	end
end

-- median worth per minute and median purchase times, for the normal player
function M.curve(runs: number, seconds: number)
	local JOIN0 = 1790000000
	local worth, bought = {}, {}
	for r = 1, runs do
		local o = M.run(M.Profiles.normal, 1000 + r, JOIN0 + ((r * 7919) % 1800), seconds)
		for m, w in o.worthAt do
			worth[m] = worth[m] or {}
			table.insert(worth[m], w)
		end
		for k, at in o.boughtAt do
			bought[k] = bought[k] or {}
			table.insert(bought[k], at)
		end
	end
	local line = {}
	for _, m in { 3, 5, 8, 10, 15, 20, 25, 30, 35, 37, 40, 45, 60, 90, 120, 150, 180, 240 } do
		if worth[m] then table.insert(line, string.format("%d:%d", m, pct(worth[m], 0.5))) end
	end
	print("normal median worth by minute  " .. table.concat(line, "  "))
	local names = { "carrot", "field 2", "corn", "tomato", "field 3", "sunflower", "pumpkin", "field 4", "watermelon", "stormfruit", "field 5", "field 6" }
	local line2 = {}
	for _, k in names do
		local list = bought[k] or {}
		local missing = runs - #list
		for _ = 1, missing do table.insert(list, math.huge) end
		table.insert(line2, string.format("%s %s", k, fmt(pct(list, 0.5))))
	end
	print("normal median minute of purchase  " .. table.concat(line2, " |"))
end

local mode = "all"
if mode == "all" then
	M.report(200, 4 * 3600)
	M.curve(200, 4 * 3600)
elseif mode == "curve" then
	M.curve(200, 4 * 3600)
elseif mode == "almanac" then
	-- the long-term goal: hours to all 56 entries, and entries after 1/3/10/20 hours
	local JOIN0 = 1790000000
	for _, name in { "planner", "combo" } do
		local done, e1, e3, e10, e20 = {}, {}, {}, {}, {}
		for r = 1, 40 do
			local o = M.run(M.Profiles[name], 5000 + r, JOIN0 + ((r * 7919) % 1800), 30 * 3600)
			table.insert(done, o.almanacAt[56] or math.huge)
			local function by(h: number): number
				local n = 0
				for _, at in o.almanacAt do
					if at <= h * 3600 then n += 1 end
				end
				return n
			end
			table.insert(e1, by(1)); table.insert(e3, by(3)); table.insert(e10, by(10)); table.insert(e20, by(20))
		end
		local function h(x: number): string
			return if x == math.huge then "never(30h)" else string.format("%.1f h", x / 3600)
		end
		print(string.format("%s (40 x 30 h): all 56 at p10 %s / median %s / p90 %s ; entries @1/3/10/20 h (median) %d / %d / %d / %d",
			name, h(pct(done, 0.1)), h(pct(done, 0.5)), h(pct(done, 0.9)), pct(e1, 0.5), pct(e3, 0.5), pct(e10, 0.5), pct(e20, 0.5)))
	end
end

return M
