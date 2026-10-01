--!strict
-- Highscore.luau — the Field Guide board's value, as pure numbers (queued job A, owner design 2026-09-16).
--
-- The board ranks on Field Guide completion: anomaly TYPES caught (Codex.countKnown, 0..the catalog's
-- size), ties broken by who reached that count FIRST. One OrderedDataStore integer carries both:
--
--     value = caught * 2e9 + (2e9 - reachedAtUnix)
--
-- GetSortedAsync(false, ...) sorts descending, so more types come first and, among equal counts, the
-- larger tie-break (the EARLIER time) first. The tie-break is clamped to 0 .. 2e9 - 1 so it can never
-- reach into the next count: after 2033-05-18 (unix 2e9) ties stop being ordered, the counts do not.
-- A count is clamped to 0 .. cap (the catalog's size), both writing and reading, and `range` is the
-- query window the board asks the store for, so a fabricated value above the cap is never even fetched.
-- No `require`: pure, and runs in the luau CLI (tests/Highscore.spec.luau).

local Highscore = {}

Highscore.SCALE = 2000000000

local function isNaN(x: number): boolean
	return x ~= x
end

local function clampCount(caught: number, cap: number): number
	if type(caught) ~= "number" or isNaN(caught) then
		return 0
	end
	return math.clamp(math.floor(caught), 0, math.max(0, math.floor(cap)))
end

function Highscore.encode(caught: number, reachedAt: number, cap: number): number
	local c = clampCount(caught, cap)
	local t = if type(reachedAt) == "number" and not isNaN(reachedAt) then math.floor(reachedAt) else Highscore.SCALE
	local tie = math.clamp(Highscore.SCALE - t, 0, Highscore.SCALE - 1)
	return c * Highscore.SCALE + tie
end

-- -> caught (clamped to 0..cap), reachedAt
function Highscore.decode(value: number, cap: number): (number, number)
	if type(value) ~= "number" or isNaN(value) or value < 0 then
		return 0, Highscore.SCALE
	end
	local v = math.floor(value)
	local c = math.floor(v / Highscore.SCALE)
	local tie = v - c * Highscore.SCALE
	return clampCount(c, cap), Highscore.SCALE - tie
end

-- The board's GetSortedAsync window: at least one type caught, at most `cap` with any tie-break.
function Highscore.range(cap: number): (number, number)
	return Highscore.SCALE, (math.floor(cap) + 1) * Highscore.SCALE - 1
end

function Highscore.key(userId: number): string
	return "u_" .. tostring(userId)
end

function Highscore.userIdFromKey(key: any): number?
	if type(key) ~= "string" then
		return nil
	end
	local digits = string.match(key, "^u_(%d+)$")
	return if digits then tonumber(digits) else nil
end

return Highscore
