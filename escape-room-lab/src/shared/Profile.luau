--!strict
-- Profile.luau — the saved record and the only ways it changes. Pure; no Roblox.
--
-- { v = 1, best = { ["1"] = 0..3, ... }, starsAt, escapedAt, boarded, rooms }
--   best      the best stars per room, keyed by the STRINGS "1".."15" (JSON turns sparse integer keys
--             into strings, docs/new-game-checklist.md). A key present = that room was escaped; a
--             carried escape in a pair stores 0 and still advances the frontier.
--   starsAt   unix time the current total was FIRST reached: the board's tie-break
--   escapedAt unix time of the first Roof arrival (0 until then)
--   boarded   the star total last written to the board
--   rooms     rooms escaped, ever (stats)
-- Derived, never stored: the total, the frontier, Continue. Nothing about a room in progress is saved,
-- so a read-only session has no saved secret to reveal (fork-tower REVIEW-4 §9).

local Profile = {}

Profile.ROOMS = 15

function Profile.new(): any
	return { v = 1, best = {}, starsAt = 0, escapedAt = 0, boarded = 0, rooms = 0 }
end

function Profile.total(p: any): number
	local t = 0
	for _, v in p.best do t += v end
	return t
end

local function allEscaped(best: { [string]: number }): boolean
	for s = 1, Profile.ROOMS do
		if best[tostring(s)] == nil then return false end
	end
	return true
end

local function num(x: any): number?
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil end
	return x
end

-- Anything loaded from the store goes through here. Unknown keys dropped; bests floored and clamped
-- to 0..3; only rooms 1..15; times clamped to 0..now + 60; escapedAt only if every room is escaped;
-- boarded never above the total.
function Profile.sanitize(raw: any, now: number): any
	local p = Profile.new()
	if type(raw) ~= "table" then return p end
	if type(raw.best) == "table" then
		for k, v in raw.best do
			local slot = tonumber(k)
			local val = num(v)
			if slot and slot % 1 == 0 and slot >= 1 and slot <= Profile.ROOMS and val then
				p.best[tostring(slot)] = math.clamp(math.floor(val), 0, 3)
			end
		end
	end
	local cap = now + 60
	p.starsAt = math.clamp(math.floor(num(raw.starsAt) or 0), 0, cap)
	p.escapedAt = math.clamp(math.floor(num(raw.escapedAt) or 0), 0, cap)
	if not allEscaped(p.best) then p.escapedAt = 0 end
	p.rooms = math.max(0, math.floor(num(raw.rooms) or 0))
	p.boarded = math.clamp(math.floor(num(raw.boarded) or 0), 0, Profile.total(p))
	return p
end

-- One escape of `slot` with `stars` (0..3). Keeps the best; moves starsAt only when the total rises;
-- stamps escapedAt the first time every room has been escaped. -> { total, rose, roofFirst }
function Profile.record(p: any, slot: number, stars: number, now: number): any
	local before = Profile.total(p)
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Profile.ROOMS then
		return { total = before, rose = false, roofFirst = false }
	end
	local key = tostring(slot)
	local s = math.clamp(math.floor(stars), 0, 3)
	local old = p.best[key]
	if old == nil or s > old then p.best[key] = s end
	p.rooms += 1
	local after = Profile.total(p)
	local rose = after > before
	if rose then p.starsAt = now end
	local roofFirst = false
	if p.escapedAt == 0 and allEscaped(p.best) then
		p.escapedAt = now
		roofFirst = true
	end
	return { total = after, rose = rose, roofFirst = roofFirst }
end

return Profile
