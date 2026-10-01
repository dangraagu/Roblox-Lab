-- Grow a Crystal — a client cannot predict the refraction roll (review round 2, finding 1; the queued job).
-- Run: luau check_growacrystal_salt.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The server seeded each harvest's roll with (os.time()*1000 + socketId*977 + UserId) % (2^31 - 1). Every term is
-- known to the client: its State push carries the server's `now`, and Rng, Rarity and Config sit in
-- ReplicatedStorage. A reviewer's probe predicted 48 of 48 rolls, so a script could click only on the second that
-- rolls best and farm totalDust, the leaderboard metric. The fix adds a salt the server draws for EACH harvest from
-- its own entropy-seeded Random: never saved, never sent, never an attribute.
--
-- What must hold, through the real server with 48 mature Shard crystals at luck 3:
--   * a predictor that uses everything a client can read matches the server's roll only at chance level;
--   * the seed the server rolled with (read off the Rng it hands Rarity.roll) is never the client's formula, and
--     the salt is drawn per harvest (a salt fixed for the session is a constant a client could solve for from the
--     tiers it sees);
--   * the roll itself is unchanged: every paid tier is Rarity.roll on the salted seed;
--   * the salt is nowhere a client can read (State pushes, attributes, values) and no remote was added.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
-- os.time is the emulator's virtual clock (like check_growacrystal_walk), installed before the game loads. With the
-- real clock a harvest that straddled a wall-clock second was dropped from the sample, and under load that made
-- "48 harvests measured" fail about 1 run in 40 (measured 2026-10-01). The virtual second only moves on h:advance,
-- so every harvest below is measured, and the predictor still gets exactly the second the server rolls in.
local realOs = os
local T0 = realOs.time()
os = setmetatable({
	time = function(t)
		if t ~= nil then return realOs.time(t) end
		return T0 + math.floor(h.scheduler:now())
	end,
}, { __index = realOs })
local ME = 424242
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
local plants = {}
for sid = 1, 48 do plants[tostring(sid)] = { tier = 1, at = 1 } end
store:SetAsync("u_" .. ME, { data = { dust = 10, seeds = {}, chambers = 8, luckLevel = 3, growthLevel = 0,
	plants = plants, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {} } })
assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("CrystalRemotes")
local before = {}
for _, r in remotes:GetChildren() do table.insert(before, r.Name) end
table.sort(before)

-- what a CLIENT can read: the replicated modules and its own State push
local Config = h:_require(RS:FindFirstChild("Config"))
local Rng = h:_require(RS:FindFirstChild("Rng"))
local Rarity = h:_require(RS:FindFirstChild("Rarity"))
local M = 2147483647

-- the seed the server really used: Rarity.roll receives a fresh Rng whose state IS the seed
local served = {}
local realRoll = Rarity.roll
Rarity.roll = function(seedTier, luckMult, rng, rc, maxTier)
	table.insert(served, { seedTier = seedTier, luckMult = luckMult, seed = rng.state })
	return realRoll(seedTier, luckMult, rng, rc, maxTier)
end

local plr = h:join("Predictor", ME)
h:advance(1)
local State = remotes:FindFirstChild("State")
local function lastPush()
	local s = State:sentTo(plr)
	return s[#s].args[1]
end
local s0 = lastPush()
truthy(type(s0.now) == "number" and type(s0.luckMult) == "number", "the State push carries the server's now and luckMult (what a predictor starts from)")

local function clientBase(now, sid)
	return (now * 1000 + sid * 977 + ME) % M
end
local match, total, sameSeed, reproduced = 0, 0, 0, 0
local salts, distinct = {}, 0
for sid = 1, 48 do
	local sock = h.workspace:FindFirstChild("Socket_" .. ME .. "_" .. sid, true)
	local c = sock and sock:FindFirstChild("Crystal")
	local cd = c and c:FindFirstChildOfClass("ClickDetector")
	local t = os.time()
	local guess = realRoll(1, s0.luckMult, Rng.new(clientBase(t, sid)), Config.Refraction, Config.MaxTier)
	local n0 = #served
	if cd then cd.MouseClick:Fire(plr) end
	local got = lastPush().lastHarvest
	local rec = served[n0 + 1]
	if os.time() == t and got and got.socket == sid and rec then
		total += 1
		if got.tier == guess then match += 1 end
		if rec.seed == clientBase(t, sid) then sameSeed += 1 end
		local salt = (rec.seed - clientBase(t, sid)) % M
		if not salts[salt] then salts[salt] = true; distinct += 1 end
		if realRoll(rec.seedTier, rec.luckMult, Rng.new(rec.seed), Config.Refraction, Config.MaxTier) == got.tier then
			reproduced += 1
		end
	end
end
eq(total, 48, "48 harvests measured, each inside one server second")
eq(#served, 48, "one roll per harvest")
-- chance level for a Shard at luck 3 is the sum of the squared tier odds, 0.276: about 13 of 48, sd 3.1
truthy(match <= 30, string.format("a client's prediction matches the server's roll only at chance level (%d of %d; it was 48 of 48)", match, total))
eq(sameSeed, 0, "the server never rolls with the seed a client can compute")
truthy(distinct >= 46, string.format("the salt is drawn per harvest, not fixed for the session (%d distinct salts in %d harvests)", distinct, total))
eq(reproduced, total, "the roll is unchanged: every paid tier is Rarity.roll on the salted seed")

-- the salt is nowhere a client can read
local leaked = 0
local saltSet = {}
for s in salts do
	if s > 1000 then saltSet[s] = true end -- a small number could collide with a real field
end
local function scanValue(v, depth)
	if depth > 6 then return end
	if type(v) == "number" then
		if saltSet[v] then leaked += 1 end
	elseif type(v) == "table" then
		for k, x in v do scanValue(k, depth + 1); scanValue(x, depth + 1) end
	end
end
for _, rec in State:sentTo(plr) do scanValue(rec.args, 0) end
for _, root in { h.workspace, RS, plr } do
	for _, d in root:GetDescendants() do
		for _, a in d:GetAttributes() do scanValue(a, 0) end
		local ok, v = pcall(function() return (d :: any).Value end)
		if ok then scanValue(v, 0) end
	end
end
eq(leaked, 0, "no salt appears in a State push, an attribute or a Value")
local after = {}
for _, r in remotes:GetChildren() do table.insert(after, r.Name) end
table.sort(after)
eq(table.concat(after, ","), table.concat(before, ","), "no remote was added")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no server warnings")
print(string.format("  measured: %d of %d predictions matched, %d distinct salts", match, total, distinct))
print(string.format("growacrystal salt: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal salt check failed", 0) end
