-- How long the day's P (Dungeon.tightLine) costs a server: one mint, with its retries, and
-- one validate (every server validates the stored day once when it loads it).
-- Run (from this folder): luau timing.luau
local root = "../../"
local Dungeon = require(root .. "src/server/Dungeon")
local Config = require(root .. "src/shared/Config")
local Rng = require(root .. "src/shared/Rng")
local r = Rng.new(4242)
local draw = function(n) return r:below(n) end
local N = 100
local recs = {}
local t0 = os.clock()
for i = 1, N do recs[i] = Dungeon.mint(Config, draw, 20726, 0) end
local t1 = os.clock()
for i = 1, N do assert(Dungeon.validate(Config, recs[i], 20726)) end
local t2 = os.clock()
local worst = 0
for i = 1, N do
	local a = os.clock()
	Dungeon.validate(Config, recs[i], 20726)
	worst = math.max(worst, os.clock() - a)
end
print(string.format("%d days: mint %.1f ms mean, validate %.1f ms mean, validate worst %.1f ms (luau CLI, this PC)",
	N, (t1 - t0) / N * 1000, (t2 - t1) / N * 1000, worst * 1000))
