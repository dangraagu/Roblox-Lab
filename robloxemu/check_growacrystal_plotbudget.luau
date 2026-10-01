-- Grow a Crystal — the server's per-plot lights and sparkles are capped, and nothing is rebuilt every 5 s
-- (review round 2, finding 4; standard §2 "budgets are measured and capped in code").
-- Run: luau check_growacrystal_plotbudget.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- refreshSocketVisual gave every mature crystal a sparkle emitter and every mature tier-3+ crystal a PointLight,
-- with no cap, and the 5-second refresh loop destroyed and rebuilt every crystal. A reviewer's probe measured a
-- returning idle player at chamber 8 (48 crystals that matured offline, the normal case): 58 PointLights,
-- 50 ParticleEmitters and 322 particles/s in one plot, and 144 instances destroyed and recreated every 5 s,
-- every sparkle restarting at once. The docs said "10 lights, 2 emitters per plot".
--
-- What must hold, through the real server:
--   * crystal lights: at most Config.PlotBudget.CrystalLights per plot, on the rarest ready crystals (tier 3+);
--   * sparkles: every ready crystal still glints (the "ready to harvest" cue stays true for all of them), and
--     their summed rate is at most Config.PlotBudget.SparkleRate particles/s; a few ready crystals keep the
--     full per-crystal rate;
--   * nothing is destroyed or recreated while nothing changes, and a harvest re-deals the budget.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
local function profile(uid, tiers: { number }, chambers: number, growingFrom: number?)
	local plants = {}
	for sid, tier in tiers do
		plants[tostring(sid)] = { tier = tier, at = if growingFrom and sid >= growingFrom then os.time() - 10 else 1 }
	end
	store:SetAsync("u_" .. uid, { data = { dust = 10, seeds = {}, chambers = chambers, luckLevel = 0, growthLevel = 0,
		plants = plants, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {} } })
end
local function all(tier, n)
	local t = {}
	for i = 1, n do t[i] = tier end
	return t
end
profile(1001, {}, 8)                   -- nothing planted: the cavern's own lamps and dust
profile(1002, all(6, 48), 8)            -- 48 ready Mythic
profile(1003, all(3, 48), 8)            -- 48 ready Amethyst
local mixed = all(3, 48)
for _, sid in { 5, 17, 23, 31, 40, 44 } do mixed[sid] = 6 end
for _, sid in { 2, 9 } do mixed[sid] = 5 end
profile(1004, mixed, 8)                 -- 6 Mythic and 2 Legendary among Amethyst
profile(1005, { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, 2, 4) -- 3 ready Shards, 9 still growing

assert(h:tryRun("server/Main.server"))
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local B = Config.PlotBudget
truthy(type(B) == "table" and type(B.CrystalLights) == "number" and type(B.SparkleRate) == "number",
	"Config.PlotBudget names the per-plot crystal light and sparkle budgets")
B = B or { CrystalLights = 0, SparkleRate = 0 }

local players = {}
local function measure(uid)
	local plr = players[uid]
	if plr == nil then
		plr = h:join("P" .. uid, uid)
		players[uid] = plr
		h:advance(6)
	end
	local folder = h.workspace:FindFirstChild("Socket_" .. uid .. "_1", true).Parent
	local m = { lights = 0, emitters = 0, rate = 0, crystalLights = 0, sparkles = 0, sparkleRate = 0,
		ready = 0, readyGlinting = 0, lit = {}, folder = folder, plr = plr }
	for _, d in folder:GetDescendants() do
		if d.ClassName == "PointLight" then
			m.lights += 1
			if d.Parent and d.Parent.Name == "Crystal" then
				m.crystalLights += 1
				local sid = d.Parent.Parent:GetAttribute("SocketId")
				m.lit[sid] = true
			end
		end
		if d.ClassName == "ParticleEmitter" and d.Enabled ~= false then
			m.emitters += 1
			m.rate += d.Rate
			if d.Parent and d.Parent.Name == "Crystal" then
				m.sparkles += 1
				m.sparkleRate += d.Rate
			end
		end
	end
	for _, s in folder:GetChildren() do
		local c = s:FindFirstChild("Crystal")
		if c and s:GetAttribute("SocketId") then
			if c.Size.Y >= 5.99 then
				m.ready += 1
				local e = c:FindFirstChildOfClass("ParticleEmitter")
				if e and e.Enabled ~= false and e.Rate > 0 then m.readyGlinting += 1 end
			end
		end
	end
	return m
end

local base = measure(1001)
print(string.format("  empty plot at chamber 8: %d PointLights, %d emitters, %d particles/s", base.lights, base.emitters, base.rate))
for _, case in { { 1002, "48 ready Mythic" }, { 1003, "48 ready Amethyst" }, { 1004, "6 Mythic + 2 Legendary + 40 Amethyst" } } do
	local m = measure(case[1])
	print(string.format("  %s: %d PointLights (%d on crystals), %d emitters (%d sparkles, %.1f/s), %d particles/s",
		case[2], m.lights, m.crystalLights, m.emitters, m.sparkles, m.sparkleRate, m.rate))
	truthy(m.crystalLights <= B.CrystalLights, string.format("%s: at most %d crystal lights (%d)", case[2], B.CrystalLights, m.crystalLights))
	eq(m.lights, base.lights + math.min(B.CrystalLights, 48), case[2] .. ": the plot's lights are its lamps plus the capped crystal lights")
	eq(m.ready, 48, case[2] .. ": all 48 crystals are ready")
	eq(m.readyGlinting, 48, case[2] .. ": every ready crystal still glints (the ready-to-harvest cue)")
	truthy(m.sparkleRate <= B.SparkleRate + 1e-6, string.format("%s: the sparkles sum to at most %d particles/s (%.1f)", case[2], B.SparkleRate, m.sparkleRate))
	truthy(m.rate <= base.rate + B.SparkleRate + 1e-6, string.format("%s: the plot's particles/s stay within the lamps' dust plus the sparkle budget (%.1f)", case[2], m.rate))
end
do
	local m = measure(1004)
	local rareLit = 0
	for _, sid in { 5, 17, 23, 31, 40, 44 } do if m.lit[sid] then rareLit += 1 end end
	eq(rareLit, math.min(6, B.CrystalLights), "the lights go to the rarest crystals: every Mythic is lit first")
	local legLit = (if m.lit[2] then 1 else 0) + (if m.lit[9] then 1 else 0)
	eq(legLit, math.clamp(B.CrystalLights - 6, 0, 2), "... then the Legendaries")
end
do
	local m = measure(1005)
	eq(m.ready, 3, "3 ready Shards among 9 growing ones")
	eq(m.readyGlinting, 3, "each ready Shard glints")
	eq(m.crystalLights, 0, "a Shard never gets a light (tier 3 and up only, as before)")
	eq(m.sparkleRate, 3 * 6, "a few ready crystals keep the full 6 particles/s each")
end

-- no churn: 30 s of the refresh loop with nothing changing destroys and recreates nothing
do
	local m = measure(1002)
	local function snapshot()
		local s = {}
		for _, d in m.folder:GetDescendants() do
			if d.ClassName == "ParticleEmitter" or d.ClassName == "PointLight" or d.Name == "Crystal" then s[d] = true end
		end
		return s
	end
	local s0 = snapshot()
	local n0 = 0
	for _ in s0 do n0 += 1 end
	h:advance(30)
	local s1 = snapshot()
	local gone, new = 0, 0
	for d in s0 do if not s1[d] then gone += 1 end end
	for d in s1 do if not s0[d] then new += 1 end end
	eq(gone, 0, string.format("30 s with nothing changing: none of the %d crystals, lights and sparkles is destroyed", n0))
	eq(new, 0, "... and none is recreated")

	-- a harvest re-deals the budget: still capped, every remaining ready crystal still glints
	local lit
	for sid in m.lit do lit = sid; break end
	local sock = h.workspace:FindFirstChild("Socket_1002_" .. tostring(lit or 1), true)
	local cd = sock:FindFirstChild("Crystal"):FindFirstChildOfClass("ClickDetector")
	cd.MouseClick:Fire(m.plr)
	h:advance(0.5)
	local m2 = measure(1002)
	eq(m2.ready, 47, "one crystal harvested")
	eq(m2.crystalLights, math.min(B.CrystalLights, 47), "the harvested crystal's light goes to another Mythic")
	eq(m2.readyGlinting, 47, "every remaining ready crystal still glints")
	truthy(m2.sparkleRate <= B.SparkleRate + 1e-6, string.format("the sparkles still sum to at most %d/s (%.1f)", B.SparkleRate, m2.sparkleRate))
end

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no server warnings")
print(string.format("growacrystal plotbudget: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal plotbudget check failed", 0) end
