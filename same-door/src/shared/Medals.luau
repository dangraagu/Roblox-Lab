--!strict
-- Medals.luau — a run's medal against the day's perfect line, ranks, torch colours, time text.
-- Pure; cfg is the whole Config table.
--
-- Grading is integer arithmetic (time * 100 <= P * pct), so the threshold shown in the antechamber
-- and the grader can never disagree by a rounding error.

local Medals = {}

local TIERS = { Bronze = 1, Silver = 2, Gold = 3, Sealer = 4 }
Medals.ORDER = { "Bronze", "Silver", "Gold", "Sealer" }

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Medals.tier(name: string?): number
	if name == nil then return 0 end
	return TIERS[name] or 0
end

local function pctOf(medal: string, cfg: any): number?
	if medal == "Silver" then return cfg.Medals.SilverPct end
	if medal == "Gold" then return cfg.Medals.GoldPct end
	if medal == "Sealer" then return cfg.Medals.SealerPct end
	return nil
end

-- The best medal a finish of `timeMs` earns on a day whose perfect line is `perfectMs`.
function Medals.grade(timeMs: number, perfectMs: number, cfg: any): string?
	if not finite(timeMs) or not finite(perfectMs) or perfectMs <= 0 or timeMs < 0 then return nil end
	local t = math.floor(timeMs)
	for i = #Medals.ORDER, 2, -1 do
		local m = Medals.ORDER[i]
		local pct = pctOf(m, cfg) :: number
		if t * 100 <= perfectMs * pct then return m end
	end
	return "Bronze"
end

-- The slowest time (ms) that still earns `medal`.
function Medals.thresholdMs(perfectMs: number, medal: string, cfg: any): number
	local pct = pctOf(medal, cfg)
	if pct == nil then return math.huge end
	return math.floor(perfectMs * pct / 100)
end

-- Rank index: 0 none, 1 Wanderer, 2 Gilded, 3 Sealer, 4 Warden, 5 Keeper. The highest one earned.
function Medals.rank(life: any, cfg: any): number
	if type(life) ~= "table" then return 0 end
	local doors = tonumber(life.doors) or 0
	local gold = tonumber(life.goldDays) or 0
	local sealer = tonumber(life.sealerDays) or 0
	local streak = tonumber(life.bestStreak) or 0
	if sealer >= cfg.RankRules.KeeperSealerDays then return 5 end
	if streak >= cfg.RankRules.WardenStreak then return 4 end
	if sealer >= 1 then return 3 end
	if gold >= 1 then return 2 end
	if doors >= 1 then return 1 end
	return 0
end

function Medals.rankLabel(rank: number, cfg: any): string
	local r = cfg.Ranks[rank]
	return if r then r.label else ""
end

function Medals.torch(rank: number, cfg: any): { number }
	local r = cfg.Ranks[rank]
	local c = if r then r.torch else cfg.TorchDefault
	return { c[1], c[2], c[3] }
end

-- "27.34" or "2:31.05". Hundredths TRUNCATED: the text never claims a faster time than the real one.
function Medals.formatTime(ms: number?): string
	if not finite(ms) then return "--" end
	local total = math.max(0, math.floor((ms :: number) / 10)) -- hundredths
	local cs = total % 100
	local secs = total // 100
	if secs < 60 then
		return string.format("%d.%02d", secs, cs)
	end
	return string.format("%d:%02d.%02d", secs // 60, secs % 60, cs)
end

-- A duration for a sentence or a card: "27.34 s" under a minute, "2:31.05" from a minute on (the
-- m:ss form already says what it is; "2:31.05 s" mixed the units on every first run's card).
function Medals.formatDuration(ms: number?): string
	local t = Medals.formatTime(ms)
	if t == "--" or string.find(t, ":", 1, true) then return t end
	return t .. " s"
end

return Medals
