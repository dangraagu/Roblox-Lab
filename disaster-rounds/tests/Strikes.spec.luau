-- Strikes: the rings aimed at each player, scaled by Heat (DESIGN.md §2.4). Run: luau tests/Strikes.spec.luau
--
-- What has to hold:
--   * rings per player per round match DESIGN.md §2.4 within 5 % at every Heat, for the Meteor and the other schedule;
--   * the first ring at a player comes >= 5 s after the name, and an idle player is always ringed by 20 s (so a
--     player who never moves is swept out in every disaster: AFK and jiggle-bots farm nothing);
--   * no ring appears that could not land before the disaster ends;
--   * the placement rule (ExitStuds 7): a ring is placed only if everyone it covers can stand outside all red within
--     7 studs; otherwise it waits RetrySeconds and tries again. A lone ring always passes (7 > 4.5 + 0.8);
--   * the coverage cap: live rings never cover more than a quarter of the walkable area.
local Strikes = require("../src/shared/Strikes")
local Zones = require("../src/shared/Zones")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local SC = Config.Strikes
local seed = 20261007
local function rand(): number
	seed = (1664525 * seed + 1013904223) % 4294967296
	return seed / 4294967296
end

eq(Strikes.interval(Config, "meteor", 0), 6.0, "Meteor at Heat 0: a ring every 6.0 s")
eq(Strikes.interval(Config, "meteor", 5), 2.5, "Meteor at Heat 5: every 2.5 s")
eq(Strikes.interval(Config, "flood", 0), 15, "the other disasters at Heat 0: every 15 s")
eq(Strikes.interval(Config, "quake", 5), 5.0, "and at Heat 5: every 5.0 s")
eq(Strikes.interval(Config, "tornado", 9), 5.0, "Heat above 5 is read as 5")
eq(Strikes.interval(Config, "tornado", -2), 15, "and below 0 as 0")
eq(Strikes.heatOf(Config, 0), 0, "streak 0: Heat 0")
eq(Strikes.heatOf(Config, 3), 1, "streak 3: Heat 1 (every two rounds in a row)")
eq(Strikes.heatOf(Config, 10), 5, "streak 10: Heat 5")
eq(Strikes.heatOf(Config, 999), 5, "and never above 5")

--======================================================================= the cap

do
	local island = Config.Island.Grid * Config.Island.Grid * Config.Island.CellStuds ^ 2
	eq(Strikes.coverageCap(Config, island), 42, "the coverage rule alone would let a whole island hold 42 live rings (a quarter of 10 816 sq studs)")
	-- REVIEW-1 F11: the server's Part budget is capped in code, so the rings (its only Parts that grow with players and
	-- Heat) are capped too: Config.Budget.Rings, one projectile each on the client (Budget.Projectiles)
	eq(Config.Budget.Rings, 16, "the ring budget is 16")
	eq(Strikes.maxLive(Config, island), Config.Budget.Rings, "so a whole island holds at most 16 live rings")
	eq(Strikes.maxLive(Config, 18 * 64), 4, "an 18-cell flood plateau holds at most 4")
	eq(Strikes.maxLive(Config, 10), 1, "a tiny area still allows one ring")
	local far = {}
	for k = 1, Config.Budget.Rings do table.insert(far, { x = -50 + 6 * k, z = -45, r = Zones.ringRadius(Config) }) end
	local anywhere = function(): boolean return true end
	local ok, why = Strikes.canPlace(Config, { x = 0, z = 40 }, far, { { x = 0, z = 40 } }, anywhere, island, Zones.exitDistance)
	eq(ok, false, "with 16 rings live, a 17th waits, however much room is left")
	eq(why, "cap", "(the cap)")
	table.remove(far)
	truthy((Strikes.canPlace(Config, { x = 0, z = 40 }, far, { { x = 0, z = 40 } }, anywhere, island, Zones.exitDistance)),
		"with 15 live, the 16th is placed")
end

--======================================================================= rings per round: one player who steps out of every ring

local DESIGN = {
	meteor = { 8.7, 10.3, 12.3, 14.8, 17.2, 20.6 },
	other = { 3.4, 4.3, 5.5, 6.9, 8.7, 10.4 },
}
local ringR = Zones.ringRadius(Config)
local open = function(x: number, z: number): boolean return math.abs(x) <= 50 and math.abs(z) <= 50 end

local function oneRound(kind: string, heat: number): (number, number)
	-- the disaster is named at t = 0 and ends at t = 60; the server ticks at 10 Hz
	local ps = Strikes.newPlayer(Config, kind, heat, 0, rand)
	local px, pz = 0, 0
	local live = {}
	local count, firstAt = 0, nil
	local t = 0
	while t <= Config.Round.DisasterSeconds + 1e-9 do
		local keep = {}
		for _, r in live do if r.ends > t then table.insert(keep, r) end end
		live = keep
		if Strikes.due(Config, ps, t, Config.Round.DisasterSeconds) then
			local ok = Strikes.canPlace(Config, { x = px, z = pz }, live, { { x = px, z = pz } }, open, 10816, Zones.exitDistance)
			if ok then
				table.insert(live, { x = px, z = pz, r = ringR, ends = t + SC.TelegraphSeconds + SC.PassSeconds })
				count += 1
				firstAt = firstAt or t
				Strikes.placed(Config, ps, t, rand)
				-- the player steps 6 studs out of the ring, somewhere free
				local a = rand() * math.pi * 2
				px = math.clamp(px + math.cos(a) * 6, -45, 45)
				pz = math.clamp(pz + math.sin(a) * 6, -45, 45)
			else
				Strikes.deferred(Config, ps, t)
			end
		end
		t = math.floor((t + 0.1) * 10 + 0.5) / 10
	end
	return count, firstAt or math.huge
end

local firstWorst = { meteor = 0, other = 0 }
local firstBest = math.huge
for sched, rows in DESIGN do
	local kind = if sched == "meteor" then "meteor" else "flood"
	local measured = {}
	for heat = 0, 5 do
		local total, n = 0, 0
		for _ = 1, 2000 do
			local c, first = oneRound(kind, heat)
			total += c
			n += 1
			if heat == 0 then firstWorst[sched] = math.max(firstWorst[sched], first) end
			firstBest = math.min(firstBest, first)
		end
		local mean = total / n
		table.insert(measured, string.format("%.2f", mean))
		local want = rows[heat + 1]
		truthy(math.abs(mean - want) / want <= 0.05,
			string.format("%s at Heat %d: %.2f rings per round, DESIGN.md says %.1f (within 5 %%)", sched, heat, mean, want))
	end
	print(string.format("  rings per player per round, %s Heat 0-5: %s", sched, table.concat(measured, " / ")))
end
truthy(firstBest >= SC.FirstAfterSeconds - 1e-9, string.format("no ring before 5 s after the name (earliest %.1f s)", firstBest))
truthy(firstWorst.other <= 20 + 1e-9, string.format("an idle player at Heat 0 is ringed by 20 s in every round (latest first ring %.1f s)", firstWorst.other))
truthy(firstWorst.meteor <= 11 + 1e-9, string.format("in a Meteor Shower by 11 s (latest %.1f s)", firstWorst.meteor))
print(string.format("  first ring after the name, Heat 0: latest %.1f s (other), %.1f s (meteor)", firstWorst.other, firstWorst.meteor))

--======================================================================= no ring that cannot land in time

do
	local ps = Strikes.newPlayer(Config, "meteor", 5, 0, rand)
	ps.nextAt = 57.05
	eq(Strikes.due(Config, ps, 57.1, 60), false, "a ring due at 57.1 s would land after 60 s: none")
	eq(ps.nextAt, math.huge, "and that player gets no more rings this round")
	local ps2 = Strikes.newPlayer(Config, "meteor", 5, 0, rand)
	ps2.nextAt = 56.9
	eq(Strikes.due(Config, ps2, 57.0, 60), true, "a ring due at 57.0 s lands at 60.0 s: allowed")
end

--======================================================================= practice landings get the same grace

do
	local ps = Strikes.newPlayer(Config, "flood", 0, 30, rand)
	truthy(ps.nextAt >= 35 - 1e-9 and ps.nextAt <= 50 + 1e-9, string.format("a practice landing at 30 s: first ring 35-50 s (%.1f)", ps.nextAt))
end

--======================================================================= the placement rule

do
	-- a lone ring on a lone player always passes
	truthy(Strikes.canPlace(Config, { x = 0, z = 0 }, {}, { { x = 0, z = 0 } }, open, 10816, Zones.exitDistance), "a lone ring always passes (7 > 4.5 + 0.8)")
	-- a player boxed in by live rings: a new ring that would leave them no exit within 7 studs waits
	local live = {}
	for a = 0, 7 do
		local ang = a * math.pi / 4
		table.insert(live, { x = math.cos(ang) * 9, z = math.sin(ang) * 9, r = ringR })
	end
	eq(Strikes.canPlace(Config, { x = 0, z = 0 }, live, { { x = 0, z = 0 } }, open, 10816, Zones.exitDistance), false,
		"a ring on a player ringed in on all eight sides waits")
	-- the same ring with the player's neighbour further away is fine for the neighbour (not covered)
	truthy(Strikes.canPlace(Config, { x = 0, z = 0 }, {}, { { x = 0, z = 0 }, { x = 20, z = 0 } }, open, 10816, Zones.exitDistance),
		"a player 20 studs away is not covered by the ring and does not block it")
	-- against a wall in a corner: the corner of a 50-stud box, the exit is still within 7 studs inward
	truthy(Strikes.canPlace(Config, { x = 49, z = 49 }, {}, { { x = 49, z = 49 } }, open, 10816, Zones.exitDistance), "a ring in a corner leaves an exit inward")
	-- a player NOT covered by the new ring, standing on red ground (a cracking cell), whose only way off is where the
	-- ring would land: the ring waits (fairness check 2026-10-07: a bot was cornered by a crack, a hole and a ring)
	do
		local cracking = function(x: number, z: number): boolean
			-- the only solid ground is the one neighbour cell west of the player (x -12..-4, z -4..4); the player's own
			-- cell is cracking and everything else is a hole
			return x >= -12 and x <= -4 and math.abs(z) <= 4
		end
		eq(Strikes.canPlace(Config, { x = -6, z = 0 }, {}, { { x = 0, z = 0 } }, cracking, 10816, Zones.exitDistance), false,
			"a ring on the only way off a cracking cell waits, even though it does not cover the player (6 studs away)")
		truthy(Strikes.canPlace(Config, { x = -30, z = 0 }, {}, { { x = 0, z = 0 } }, cracking, 10816, Zones.exitDistance),
			"a ring far from that player is fine")
	end
	-- the coverage cap
	local full = {}
	for k = 1, 4 do table.insert(full, { x = k * 12 - 30, z = 0, r = ringR }) end
	eq(Strikes.canPlace(Config, { x = 0, z = 20 }, full, { { x = 0, z = 20 } }, open, 18 * 64, Zones.exitDistance), false,
		"an 18-cell plateau with 4 live rings takes no fifth (the coverage cap)")
	local ps = Strikes.newPlayer(Config, "meteor", 0, 0, rand)
	ps.nextAt = 10
	Strikes.deferred(Config, ps, 10)
	eq(ps.nextAt, 10 + SC.RetrySeconds, "a ring that cannot be placed waits 0.25 s and tries again")
end

--======================================================================= jitter

do
	local lo, hi = math.huge, 0
	for _ = 1, 5000 do
		local ps = Strikes.newPlayer(Config, "meteor", 0, 0, rand)
		Strikes.placed(Config, ps, 100, rand)
		lo = math.min(lo, ps.nextAt - 100)
		hi = math.max(hi, ps.nextAt - 100)
	end
	truthy(lo >= 6 * 0.8 - 1e-9 and hi <= 6 * 1.2 + 1e-9, string.format("intervals stay within +-20 %% (%.2f..%.2f s)", lo, hi))
	truthy(lo < 6 * 0.85 and hi > 6 * 1.15, "and use the whole +-20 % (no steady beat to stop watching)")
end

print(string.format("Strikes: %d passed, %d failed", passed, failed))
assert(failed == 0, "Strikes tests failed")
