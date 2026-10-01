-- Spec for Profile: what is saved, and sanitize() against hostile records (DESIGN.md §12.1).
-- Run: luau tests/Profile.spec.luau 2>&1
local Profile = require("../src/shared/Profile")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local NOW = 1790726400

--============================================================ defaults
do
	local p = Profile.new()
	eq(p.v, 1, "version 1")
	eq(next(p.best), nil, "no rooms escaped")
	eq(p.starsAt, 0, "starsAt 0")
	eq(p.escapedAt, 0, "escapedAt 0")
	eq(p.boarded, 0, "boarded 0")
	eq(p.rooms, 0, "rooms 0")
	eq(Profile.total(p), 0, "total 0")
end

--============================================================ sanitize: hostile records
do
	local p = Profile.sanitize(nil, NOW)
	eq(Profile.total(p), 0, "nil loads as a new profile")
	p = Profile.sanitize("garbage", NOW)
	eq(Profile.total(p), 0, "a string loads as a new profile")
	p = Profile.sanitize({
		v = 1,
		best = { ["1"] = 3, ["2"] = 7, ["3"] = -2, ["4"] = 1.9, ["16"] = 3, ["0"] = 3, x = 3, ["5"] = "3", ["6"] = 0 / 0 },
		starsAt = NOW + 999999, escapedAt = -5, boarded = 99, rooms = -1, evil = true,
	}, NOW)
	eq(p.best["1"], 3, "a legal best stays")
	eq(p.best["2"], 3, "a best above 3 is clamped to 3")
	eq(p.best["3"], 0, "a negative best is clamped to 0 (escaped, no stars)")
	eq(p.best["4"], 1, "a fractional best is floored")
	eq(p.best["16"], nil, "room 16 does not exist")
	eq(p.best["0"], nil, "room 0 does not exist")
	eq(p.best.x, nil, "a non-room key is dropped")
	eq(p.best["5"], nil, "a non-number best is dropped")
	eq(p.best["6"], nil, "a NaN best is dropped")
	eq(p.evil, nil, "unknown top-level keys are dropped")
	eq(p.starsAt, NOW + 60, "starsAt is clamped to now + 60")
	eq(p.escapedAt, 0, "escapedAt clamped to 0..")
	eq(p.boarded, Profile.total(p), "boarded clamped to the total")
	eq(p.rooms, 0, "rooms clamped to >= 0")
end
do
	-- integer keys (a JSON round trip of an old record) are normalised to strings
	local p = Profile.sanitize({ best = { [1] = 2, [2] = 3 } }, NOW)
	eq(p.best["1"], 2, "integer key 1 becomes \"1\"")
	eq(p.best["2"], 3, "integer key 2 becomes \"2\"")
	eq(p.best[1], nil, "no integer keys survive")
end
do
	-- escapedAt is only true if every room has been escaped
	local best = {}
	for s = 1, 14 do best[tostring(s)] = 3 end
	local p = Profile.sanitize({ best = best, escapedAt = NOW - 10 }, NOW)
	eq(p.escapedAt, 0, "escapedAt is cleared while a room is unescaped")
	best["15"] = 1
	p = Profile.sanitize({ best = best, escapedAt = NOW - 10 }, NOW)
	eq(p.escapedAt, NOW - 10, "and kept once all 15 are escaped")
end

--============================================================ record: best only, starsAt only on a rise
do
	local p = Profile.new()
	local r = Profile.record(p, 1, 2, NOW)
	eq(r.total, 2, "first escape: total 2")
	truthy(r.rose, "the total rose")
	eq(p.starsAt, NOW, "starsAt is the time the total was reached")
	eq(p.rooms, 1, "rooms escaped 1")
	r = Profile.record(p, 1, 1, NOW + 100)
	eq(r.total, 2, "a worse replay keeps the best")
	truthy(not r.rose, "and the total did not rise")
	eq(p.starsAt, NOW, "starsAt does not move without a rise")
	eq(p.rooms, 2, "but it counts as an escape")
	r = Profile.record(p, 1, 3, NOW + 200)
	eq(r.total, 3, "a better replay raises the best to 3")
	eq(p.starsAt, NOW + 200, "starsAt moves with the rise")
	r = Profile.record(p, 2, 0, NOW + 300)
	eq(p.best["2"], 0, "a carried escape stores 0")
	truthy(not r.rose, "and does not raise the total")
	eq(p.starsAt, NOW + 200, "or move starsAt")
	eq(Profile.record(p, 0, 3, NOW).total, 3, "room 0 is refused (total unchanged)")
	eq(Profile.record(p, 16, 3, NOW).total, 3, "room 16 is refused")
	eq(Profile.record(p, 3, 4, NOW).total, 6, "stars are clamped to 3")
	eq(p.best["3"], 3, "clamped")
end
do
	local p = Profile.new()
	for s = 1, 14 do Profile.record(p, s, 3, NOW + s) end
	truthy(Profile.record(p, 15, 3, NOW + 50).roofFirst == true, "the 15th escape is the first Roof")
	eq(p.escapedAt, NOW + 50, "escapedAt set on the first Roof")
	local again = Profile.record(p, 15, 3, NOW + 90)
	truthy(not again.roofFirst, "a second Roof is not a first")
	eq(p.escapedAt, NOW + 50, "escapedAt keeps the first time")
end

print(string.format("Profile: %d passed, %d failed", passed, failed))
if failed > 0 then error("Profile spec failed", 0) end
