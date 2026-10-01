-- Spec for Lab: the room table, the stars, Continue, and the progress value the bands follow
-- (DESIGN.md §4, §7.1). Run: luau tests/Lab.spec.luau 2>&1
local Lab = require("../src/shared/Lab")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function approx(a, b, msg)
	if type(a) == "number" and math.abs(a - b) < 1e-9 then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

--============================================================ the V4 wing table, room for room
-- Written out by hand from DESIGN.md §4.1 rather than read back from Config: a table checked against
-- itself is not a check.
local V4 = {
	"lamp3k2", "shelf3", "lamp3k3",
	"shelf4", "lamp3k4", "shelf4",
	"lamp3k4+shelf4", "shelf4+lamp4k3", "lamp4k4+shelf4",
	"shelf4+lamp4k4", "lamp4k4+shelf4", "shelf4+lamp4k5",
	"lamp4k5+shelf5", "shelf5+lamp4k5", "lamp4k5+shelf5",
}
local DOORS = { "3:1-6", "3:1-6", "3:1-6", "3:0-9", "3:0-9", "3:0-9", "3:0-9", "3:0-9", "3:0-9",
	"3:0-9", "3:0-9", "3:0-9", "4:0-9", "4:0-9", "4:0-9" }
eq(Lab.rooms(Config), 15, "15 rooms")
for slot = 1, 15 do
	local spec = Lab.roomSpec(Config, slot)
	local parts = {}
	for _, f in spec.feeders do
		if f.kind == "lamp" then
			table.insert(parts, "lamp" .. f.n .. "k" .. f.k)
		else
			table.insert(parts, "shelf" .. f.N)
		end
	end
	eq(table.concat(parts, "+"), V4[slot], "room " .. slot .. " feeders")
	local alpha = spec.door.alphabet
	eq(spec.door.L .. ":" .. alpha[1] .. "-" .. alpha[#alpha], DOORS[slot], "room " .. slot .. " door")
	eq(spec.door.maxLines, if slot == 1 then 3 else 6, "room " .. slot .. " max door lines")
	local w, r = Lab.wingRoomOf(slot)
	eq(spec.wing, w, "room " .. slot .. " wing")
	eq(spec.room, r, "room " .. slot .. " room in wing")
	eq(Lab.slotOf(w, r), slot, "slotOf inverts wingRoomOf for " .. slot)
	eq(#spec.stations, #spec.feeders + 1, "room " .. slot .. ": feeders + the door")
	eq(spec.stations[#spec.stations], "Door", "the last station is the door")
end
eq(Lab.roomSpec(Config, 3).feeders[1].id, "A", "a one-feeder room names it A")
eq(Lab.roomSpec(Config, 7).feeders[2].id, "B", "a two-feeder room names the second B")
eq(Lab.roomSpec(Config, 0), nil, "no room 0")
eq(Lab.roomSpec(Config, 16), nil, "no room 16")

--============================================================ stars and the hands-on rule
eq(Lab.stars({ escaped = true, wrong = false, hinted = false, pair = false }), 3, "solo, clean, unaided: 3")
eq(Lab.stars({ escaped = true, wrong = true, hinted = false, pair = false }), 2, "a wrong try costs Clean")
eq(Lab.stars({ escaped = true, wrong = false, hinted = true, pair = false }), 2, "a hint costs Unaided")
eq(Lab.stars({ escaped = true, wrong = true, hinted = true, pair = false }), 1, "both: 1")
eq(Lab.stars({ escaped = true, wrong = false, hinted = false, pair = true, handsOn = true }), 3, "pair, hands on: 3")
eq(Lab.stars({ escaped = true, wrong = false, hinted = false, pair = true, handsOn = false }), 0,
	"pair, carried: 0 (a partner cannot carry you to stars)")
eq(Lab.stars({ escaped = false, wrong = false, hinted = false, pair = false }), 0, "not escaped: 0")

--============================================================ totals, frontier, Continue
do
	-- a key present means the room was escaped (a carried escape stores 0 and still advances)
	local best = {}
	eq(Lab.total(best), 0, "empty total")
	eq(Lab.frontier(best), 1, "a new player's frontier is room 1")
	eq(Lab.continueSolo(best, nil), 1, "Continue for a new player: room 1")
	best["1"] = 3
	best["2"] = 0
	eq(Lab.frontier(best), 3, "a carried escape (0 stars) still advances the frontier")
	eq(Lab.total(best), 3, "total sums the bests")
	for s = 1, 14 do best[tostring(s)] = 3 end
	eq(Lab.frontier(best), 15, "frontier 15 before the last room")
	eq(Lab.continueSolo(best, 14), 15, "Continue walks to the frontier")
	best["15"] = 2
	eq(Lab.frontier(best), 16, "all escaped: frontier 16")
	eq(Lab.continueSolo(best, 15), 15, "after the Roof: the lowest room below 3 stars")
	best["4"] = 1
	eq(Lab.continueSolo(best, 15), 4, "the LOWEST room below 3")
	for s = 1, 15 do best[tostring(s)] = 3 end
	eq(Lab.total(best), 45, "all 45")
	eq(Lab.continueSolo(best, 7), 8, "with 45 stars: the room after the one played last")
	eq(Lab.continueSolo(best, 15), 1, "wrapping from 15 to 1")
	eq(Lab.continueSolo(best, nil), 1, "no last room: room 1")
	-- the pair goes to the lower of the two Continue rooms
	eq(Lab.continuePair({ ["1"] = 3 }, 1, {}, nil), 1, "pair: new player's room 1")
	local a = {}
	for s = 1, 6 do a[tostring(s)] = 3 end
	local b = { ["1"] = 3, ["2"] = 2 }
	eq(Lab.continuePair(a, 6, b, 2), 3, "pair: the lower Continue")
end

--============================================================ the lockout and hint caps
eq(Lab.lockoutFor(Config, 1), 3, "first wrong try: 3 s")
eq(Lab.lockoutFor(Config, 2), 6, "second: 6 s")
eq(Lab.lockoutFor(Config, 3), 12, "third: 12 s")
eq(Lab.lockoutFor(Config, 4), 20, "fourth: 20 s")
eq(Lab.lockoutFor(Config, 9), 20, "and 20 s from then on")
eq(Lab.lockoutFor(Config, 0), 0, "no wrong try: no lockout")
eq(Lab.hintCap({ kind = "door", L = 3 }), 2, "door hint cap L - 1")
eq(Lab.hintCap({ kind = "shelf", N = 4 }), 2, "shelf hint cap N - 2")
eq(Lab.hintCap({ kind = "lamp", k = 5 }), 4, "lamp hint cap k - 1")
eq(Lab.hintCap({ kind = "lamp", k = 2 }), 1, "lamp hint cap never below 1")

--============================================================ progress: the game's own logic, never time
approx(Lab.progress(1, 1, 0, 2), 0, "room 1 start: p 0")
approx(Lab.progress(1, 1, 1, 2), 1 / 6, "room 1, one of two stations: 1/6")
approx(Lab.progress(1, 3, 0, 2), 2 / 3, "room 3 start: 2/3")
approx(Lab.progress(1, 3, 2, 2), 1, "room 3 door open: exactly 1, the Archive's start")
approx(Lab.progress(2, 1, 0, 2), 1, "the next wing starts where the last room ended")
approx(Lab.progress(5, 3, 3, 3), 5, "the last door open: 5, the Roof")
approx(Lab.progress(3, 2, 1, 3), 2 + (1 + 1 / 3) / 3, "mid-room")
do
	-- monotone along the whole run, one station at a time
	local last = -1
	local ok = true
	for slot = 1, 15 do
		local spec = Lab.roomSpec(Config, slot)
		local n = #spec.stations
		for solved = 0, n do
			local p = Lab.progress(spec.wing, spec.room, solved, n)
			if p < last - 1e-9 then ok = false end
			last = p
		end
	end
	truthy(ok, "progress never goes down across the 15 rooms")
end

--============================================================ where a hazard may land
do
	truthy(Lab.legalSpot(0, 0, Config), "the room's centre is a legal spot")
	truthy(not Lab.legalSpot(0, 12, Config), "4 studs from the entry doorway is not")
	truthy(Lab.legalSpot(0, 10.9, Config), "5.1 studs from the entry doorway is")
	truthy(not Lab.legalSpot(0, -12, Config), "4 studs from the exit doorway is not")
	truthy(not Lab.legalSpot(15.5, 0, Config), "half a stud from a wall is not")
	truthy(Lab.legalSpot(14.9, 0, Config), "1.1 studs from a wall is")
	truthy(not Lab.legalSpot(0, 20, Config), "inside the entry cab is not")
end

print(string.format("Lab: %d passed, %d failed", passed, failed))
if failed > 0 then error("Lab spec failed", 0) end
