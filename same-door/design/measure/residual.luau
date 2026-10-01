-- The speed-hack residual against the PUBLISHED line (REVIEW-1 findings 2 and 5). Not game code.
-- Run (from this folder): luau residual.luau [-a days]
--
-- For each day: walk the day's P polyline (Dungeon.perfectPath) from the antechamber at 16 x factor
-- studs/s, 60 Hz, through the real RunState / RunCheck, and record
--   * the official time of the 1.00x walk against P (an honest walk of "perfect" may not beat it),
--   * the server's own taut line at the finish against P's length,
--   * the fastest factor (in steps of 0.005) at which a script walking that same line is NOT voided.
-- Reviewer 1 measured the first build with the same method (scratch tautvsP.luau / check_sdx_speed):
-- taut/P 0.915-0.973 (p50 0.947), official/P 0.9886-0.9926, a P-line script passing at up to
-- 1.048x-1.114x (p50 1.077x).
local root = "../../"
local Dungeon = require(root .. "src/server/Dungeon")
local RunCheck = require(root .. "src/server/RunCheck")
local RunState = require(root .. "src/server/RunState")
local Grid = require(root .. "src/shared/Grid")
local Config = require(root .. "src/shared/Config")
local Rng = require(root .. "src/shared/Rng")
local N = tonumber((...)) or 200
local deps = { RunCheck = RunCheck, Grid = Grid, Dungeon = Dungeon }

local captured = nil
local realFinish = RunCheck.finishCheck
RunCheck.finishCheck = function(guard, t, x, z, t0)
	captured = RunCheck.tautLength(guard, x, z)
	return realFinish(guard, t, x, z, t0)
end

local function walk(w, pts, factor): (string, number?)
	local list = { { x = 72, z = -8 } }
	for _, p in pts do table.insert(list, p) end
	local a, b = list[#list - 1], list[#list]
	local L = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	table.insert(list, { x = b.x + (b.x - a.x) / L * 2, z = b.z + (b.z - a.z) / L * 2 })
	local run = RunState.new(Config, w, deps)
	RunState.arrive(run)
	local seg, x, z, dt = 1, 72, -8, 1 / 60
	for _ = 1, 60 * 120 do
		local remaining = 16 * factor * dt
		while remaining > 0 and seg < #list do
			local q = list[seg + 1]
			local dx, dz = q.x - x, q.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = q.x, q.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
		for _, e in RunState.step(run, dt, x, 3, z) do
			if e.type == "finish" then return "finish", e.timeMs end
			if e.type == "void" then return "void", nil end
		end
		if seg >= #list then break end
	end
	return "none", nil
end

local r = Rng.new(777)
local draw = function(n) return r:below(n) end
local official, taut, passes = {}, {}, {}
local done = 0
while done < N do
	local rec = Dungeon.mint(Config, draw, 1, 1)
	if rec then
		done += 1
		local w = Dungeon.fromRecord(Config, rec)
		local Plen, pts = Dungeon.perfectPath(Config, w)
		captured = nil
		local how, ms = walk(w, pts, 1.00)
		assert(how == "finish", "the 1.00x walk of P finished")
		table.insert(official, (ms :: number) / rec.perfectMs)
		table.insert(taut, (captured :: number) / Plen)
		local best = 1.00
		local f = 1.005
		while f <= 1.15 do
			if walk(w, pts, f) == "finish" then best = f else break end
			f += 0.005
		end
		table.insert(passes, best)
	end
end
table.sort(official); table.sort(taut); table.sort(passes)
local function q(t, p) return t[math.max(1, math.ceil(p * #t))] end
print(string.format("%d days. official time of a 1.00x walk of P / P: min %.4f p50 %.4f max %.4f", N, official[1], q(official, 0.5), official[#official]))
print(string.format("the server's taut line of that walk / P: min %.4f p50 %.4f max %.4f", taut[1], q(taut, 0.5), taut[#taut]))
print(string.format("the fastest factor a script walking the published line still passes at: min %.3f p50 %.3f max %.3f",
	passes[1], q(passes, 0.5), passes[#passes]))
