--!strict
-- Day.luau — the UTC day, the Door number, the countdown. Pure; no Roblox.
--
-- A day is floor(unix / 86400). The Door number shown to players is day - Config.Day.Epoch, so
-- 2026-09-30 (day 20726) is Door #1. Nothing here says anything about a day's LAYOUT: that is
-- stored data drawn from server entropy on the day itself (src/server/Dungeon.luau, DESIGN §3).

local Day = {}

function Day.index(now: number, cfg: any): number
	if type(now) ~= "number" or now ~= now then return 0 end
	return math.floor(now / cfg.SecondsPerDay)
end

function Day.doorNumber(dayIndex: number, cfg: any): number
	return dayIndex - cfg.Epoch
end

function Day.secondsToNext(now: number, cfg: any): number
	local d = Day.index(now, cfg)
	return math.max(0, math.floor((d + 1) * cfg.SecondsPerDay - now))
end

function Day.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
end

function Day.recordKey(dayIndex: number): string
	return "d_" .. tostring(math.floor(dayIndex))
end

function Day.boardScope(dayIndex: number): string
	return "d" .. tostring(math.floor(dayIndex))
end

return Day
