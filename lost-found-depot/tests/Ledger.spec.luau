-- Ledger: the server's travel ledger, which decides whether a Perfect Shift counts on the highscore board.
-- Run: luau tests/Ledger.spec.luau 2>&1
--
-- DESIGN.md §10.3 priced it and §15 made it the board's prerequisite: "If a leaderboard is ever added, the
-- ledger is its prerequisite". From a shift's first accepted interaction (pick, deposit, put-back), each one
-- adds  max(0, |p - pPrev| - PositionSlack) / (WalkSpeed * SpeedTolerance)  seconds to `required`, where p
-- is the server-observed root-part position, and the ledger holds while  elapsed + LatencySlack >= required.
-- The latency slack is granted ONCE per ledger, never per leg (design/model.luau: a per-leg slack let a bot
-- clear 30 items in 4.3 s).
--
-- In this game the ledger REFUSES NOTHING: a shift that breaks it still pays, still counts as a Perfect for
-- the player and for their personal best. It only is not counted on the board, and the player is told why.
-- So a false alarm costs an honest player one board count, never a sort; the slack is generous on purpose
-- (LatencySlack 1.5 s where the design model used 0.3), and the Monte Carlo below measures how often an
-- honest player with a noisy server view would lose one.
local Ledger = require("../src/shared/Ledger")
local Layout = require("../src/shared/Layout")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local lc = Config.Ledger

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end

truthy(type(lc) == "table", "Config.Ledger exists")
-- the promise, pinned as literals (a retune has to change this file, and say why)
eq(lc.PositionSlack, 2, "2 studs of position slack per leg (DESIGN.md §10.3)")
eq(lc.SpeedTolerance, 1.25, "walking may look 25% faster than the shoes allow (DESIGN.md §10.3)")
eq(lc.LatencySlack, 1.5, "1.5 s of latency slack, once per shift")

--======================================================================= the rule

do
	local L = Ledger.new()
	eq(Ledger.verified(L), true, "a new ledger holds")
	eq(Ledger.step(L, 100, 0, 0, 16, lc), true, "the first interaction always holds (it starts the ledger)")
	-- 30 studs at walk 16: the walk takes 1.875 s; the ledger requires (30 - 2) / (16 * 1.25) = 1.4 s
	eq(Ledger.step(L, 101.875, 30, 0, 16, lc), true, "walking 30 studs at exactly walk speed holds")
	eq(Ledger.step(L, 101.9, 30, 1.5, 16, lc), true, "a step inside the position slack costs nothing")
	eq(Ledger.verified(L), true, "an honest walk keeps the ledger")
end

do
	-- a teleport: 60 studs in no time needs (60 - 2) / 20 = 2.9 s; 0.05 s + the 1.5 s slack is not enough
	local L = Ledger.new()
	Ledger.step(L, 100, 0, 0, 16, lc)
	eq(Ledger.step(L, 100.05, 60, 0, 16, lc), false, "60 studs in 0.05 s breaks the ledger")
	eq(Ledger.verified(L), false, "and the shift is not verified")
	-- sticky: whatever comes later, this shift stays uncounted
	eq(Ledger.step(L, 200, 60, 0, 16, lc), true, "a later honest step holds on its own terms")
	eq(Ledger.verified(L), false, "but a broken ledger never heals within the shift")
	-- the slack is once per shift: ONE early 30-stud hop fits inside it ((30 - 2) / 20 = 1.4 s < 1.55 s), a
	-- teleporter's whole shift does not
	local one = Ledger.new()
	Ledger.step(one, 0, 0, 0, 16, lc)
	eq(Ledger.step(one, 0.05, 30, 0, 16, lc), true, "one 30-stud hop at the start fits inside the latency slack")
	local tele = Ledger.new()
	Ledger.step(tele, 0, 0, 0, 16, lc)
	for i = 1, 30 do
		local bx, bz = Layout.binStand(Config, ((i - 1) % 6) + 1)
		Ledger.step(tele, i * 0.2, bx, bz, 16, lc)
		Ledger.step(tele, i * 0.2 + 0.1, 0, 0, 16, lc)
	end
	eq(Ledger.verified(tele), false, "a shift of teleports (every deposit 0.1 s after the pick) is not counted")
end

do
	-- the latency slack is granted once: short legs at twice the allowed pace pass at first, then fail
	-- (each leg of 7 studs requires (7 - 2) / 20 = 0.25 s; taken every 0.125 s: exact binary fractions)
	local L = Ledger.new()
	Ledger.step(L, 0, 0, 0, 16, lc)
	local firstFail = nil
	for i = 1, 40 do
		local ok = Ledger.step(L, i * 0.125, (i % 2) * 7, 0, 16, lc)
		if not ok and firstFail == nil then firstFail = i end
	end
	truthy(firstFail ~= nil and firstFail > 1, "short fast legs pass while the one latency slack lasts (first fail at leg "
		.. tostring(firstFail) .. ")")
	-- required after n legs 0.25 n; elapsed 0.125 n + 1.5: it breaks at the first n with 0.125 n > 1.5, n = 13
	eq(firstFail, 13, "and break exactly where the slack runs out: leg 13 (a per-leg slack would never break)")
end

do
	-- speed hacks: 1.2x holds (inside the 1.25 tolerance), 1.5x breaks, on a real route of 30 deposits
	local function route(factor)
		local L = Ledger.new()
		local t, x, z = 0, 0, 0
		Ledger.step(L, t, x, z, 16, lc)
		for i = 1, 30 do
			local bx, bz = Layout.binStand(Config, ((i - 1) % 6) + 1)
			t += math.sqrt((bx - x) ^ 2 + (bz - z) ^ 2) / (16 * factor)
			x, z = bx, bz
			Ledger.step(L, t, x, z, 16, lc)
			t += math.sqrt(x * x + z * z) / (16 * factor)
			x, z = 0, 0
			Ledger.step(L, t, x, z, 16, lc)
		end
		return Ledger.verified(L)
	end
	eq(route(1.0), true, "walking a whole shift at walk speed, no pauses: counted")
	eq(route(1.2), true, "20% faster than the shoes (inside the tolerance): counted")
	eq(route(1.5), false, "a 1.5x speed hack: not counted")
	eq(route(3.0), false, "a 3x speed hack: not counted")
end

do
	-- the speed is the one the shoes give at each step (a purchase mid-shift only loosens the ledger)
	local L = Ledger.new()
	Ledger.step(L, 0, 0, 0, 22, lc)
	-- 40 studs in 1.5 s: (40 - 2) / (22 * 1.25) = 1.38 s required, 1.5 + 1.5 elapsed with slack
	eq(Ledger.step(L, 1.5, 40, 0, 22, lc), true, "at walk 22, 40 studs in 1.5 s holds")
	local L16 = Ledger.new()
	Ledger.step(L16, 0, 0, 0, 16, lc)
	eq(Ledger.step(L16, 1.2, 60, 0, 16, lc), false, "at walk 16, 60 studs in 1.2 s does not ((60 - 2) / 20 = 2.9 s > 2.7)")
end

do
	-- junk in: never an error, never a pass it did not earn
	local L = Ledger.new()
	Ledger.step(L, 0, 0, 0, 16, lc)
	eq(Ledger.step(L, 1, 0 / 0, 0, 16, lc), false, "a NaN position breaks the ledger (fail closed)")
	local L2 = Ledger.new()
	Ledger.step(L2, 0, 0, 0, 16, lc)
	eq(Ledger.step(L2, 1, 5, 0, 0, lc), false, "a walk speed of 0 breaks it rather than dividing by zero")
end

--======================================================================= honest players with a noisy server view

-- What the server sees of an honest player is late and a little off. The model: every interaction's
-- position is off by up to `pos` studs (uniform in a disc) and it is seen up to `lag` seconds late (uniform;
-- latency only delays). Each profile sorts 30 items: it picks `carry` items at the pick point P (bay-local
-- origin), `decode` seconds to read each tag and `act` to tap, walks to each item's bin stand
-- (Layout.binStand) and back. Seeded: the same numbers every run.
local PROFILES = {
	{ name = "first-timer", speed = 16, decode = 3.0, act = 0.5, carry = 2 },
	{ name = "regular+kit", speed = 22, decode = 1.5, act = 0.5, carry = 5 },
	{ name = "expert+kit", speed = 22, decode = 0.8, act = 0.5, carry = 5 },
	-- a player who never pauses: reads in no time, taps in 0.1 s, walks every leg at full speed
	{ name = "no-pause+kit", speed = 22, decode = 0, act = 0.1, carry = 5 },
}
local function honestShift(rng, prof, pos, lag): boolean
	local L = Ledger.new()
	local t, x, z = 0, 0, 0
	local function seen()
		local a, r = rng:next() * 2 * math.pi, math.sqrt(rng:next()) * pos
		Ledger.step(L, t + rng:next() * lag, x + r * math.cos(a), z + r * math.sin(a), prof.speed, lc)
	end
	local left = 30
	while left > 0 do
		local k = math.min(prof.carry, left)
		for _ = 1, k do
			t += prof.decode + prof.act
			seen()
		end
		for _ = 1, k do
			local bx, bz = Layout.binStand(Config, rng:below(6))
			t += math.sqrt((bx - x) ^ 2 + (bz - z) ^ 2) / prof.speed + prof.act
			x, z = bx, bz
			seen()
		end
		t += math.sqrt(x * x + z * z) / prof.speed
		x, z = 0, 0
		left -= k
	end
	return Ledger.verified(L)
end
local SHIFTS = 2000
local lines = {}
local function sweep(pos, lag): number
	local lost = 0
	for pi, prof in PROFILES do
		local rng = Rng.new(900000 + pi * 7919 + math.floor(pos * 100) + math.floor(lag * 1000))
		local n = 0
		for _ = 1, SHIFTS do
			if not honestShift(rng, prof, pos, lag) then n += 1 end
		end
		lost += n
		table.insert(lines, string.format("  noise %.0f studs / %.1f s: %-13s %d of %d shifts not counted", pos, lag, prof.name, n, SHIFTS))
	end
	return lost
end
eq(sweep(0, 0), 0, "a perfect server view: no honest shift is ever uncounted (4 profiles x " .. SHIFTS .. ")")
eq(sweep(2, 1.0), 0, "2 studs and 1.0 s of error: still none (4 profiles x " .. SHIFTS .. ")")
local heavy = sweep(4, 1.4)
truthy(heavy <= 4 * SHIFTS / 100, "4 studs and 1.4 s of error (a bad phone connection): at most 1% uncounted ("
	.. heavy .. " of " .. 4 * SHIFTS .. ")")
for _, l in lines do print(l) end

print(string.format("Ledger: %d passed, %d failed", passed, failed))
if failed > 0 then error("Ledger tests failed") end
