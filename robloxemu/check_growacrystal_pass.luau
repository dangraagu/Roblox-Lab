-- Grow a Crystal — a paid pass never moves the highscore board (owner decision, DECIDED 2026-09-30 (owner: take
-- recommended); EYECANDY.md §11). Run: luau check_growacrystal_pass.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The open question was: "if DoubleDust is ever switched on it doubles harvest dust and so the board metric: decide
-- first whether a paid pass may move the board". The owner's brief is fair, never exploitable, and the standard says
-- "never gambling or pay-to-win" (docs/complete-game-standard.md §3). So the pass may double the dust a player SPENDS,
-- but the board counts every harvest at its un-doubled value: two players with the same harvests stand on the same
-- points whether or not one of them paid.
--
-- Driven through the REAL server: two saved profiles with the same six ripe Legendary crystals, one owning DoubleDust.
-- Every crystal is clicked, both players leave (the leave saves and writes the board), and the saved records and the
-- board store are read back.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local profiles = DSS:GetDataStore("GrowCrystal_v1")

local PAY, FREE = 701, 702
local START_TOTAL = 20000 -- 200 points already on the board
local function seed(uid, passes)
	local plants = {}
	for sid = 1, 6 do plants[tostring(sid)] = { tier = 5, at = 1 } end
	profiles:SetAsync("u_" .. uid, { data = { dust = 0, seeds = {}, chambers = 5, luckLevel = 0, growthLevel = 0,
		plants = plants, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = START_TOTAL, boardAt = 1700000000,
		boardMetric = 200, passes = passes } })
end
seed(PAY, { DoubleDust = true })
seed(FREE, {})

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local bc = Config.Board
local lb = DSS:GetOrderedDataStore(Config.Save.Leaderboard)
local State = RS:FindFirstChild("CrystalRemotes"):FindFirstChild("State")

local function harvestAll(name, uid)
	local plr = h:join(name, uid)
	h:advance(1)
	local base, n = 0, 0
	for sid = 1, 6 do
		local sock = h.workspace:FindFirstChild("Socket_" .. uid .. "_" .. sid, true)
		local c = sock and sock:FindFirstChild("Crystal")
		local cd = c and c:FindFirstChildOfClass("ClickDetector")
		if cd then cd.MouseClick:Fire(plr) end
		local s = State:sentTo(plr)
		local last = s[#s].args[1].lastHarvest
		-- copy the scalars now (the emulator records payloads by reference)
		if last and last.socket == sid then
			n += 1
			base += Config.Economy.DustValue[last.tier]
		end
	end
	local s = State:sentTo(plr)
	local dustShown = s[#s].args[1].dust
	h:leave(plr)
	h:advance(1)
	return base, n, dustShown
end

local payBase, payN, payShown = harvestAll("Payer", PAY)
local freeBase, freeN = harvestAll("Free", FREE)
eq(payN, 6, "the pass owner harvested all six crystals")
eq(freeN, 6, "the other player harvested all six crystals")

local paySaved = profiles:GetAsync("u_" .. PAY)
local freeSaved = profiles:GetAsync("u_" .. FREE)
truthy(paySaved and paySaved.data and freeSaved and freeSaved.data, "both leaves saved the profile")
local pd, fd = paySaved and paySaved.data or {}, freeSaved and freeSaved.data or {}

-- the pass still does what it is sold as: the player's own dust is doubled (without this the run tests nothing)
eq(payShown, 2 * payBase, "DoubleDust doubles the dust the pass owner can spend")
eq(pd.dust, 2 * payBase, "the doubled dust is saved")
-- ... and never the board's metric
eq(pd.totalDust, START_TOTAL + payBase, "the board metric (totalDust) counts the pass owner's harvests un-doubled")
eq(fd.dust, freeBase, "without the pass a harvest pays its value")
eq(fd.totalDust, START_TOTAL + freeBase, "without the pass the board metric counts the same value")

local function points(uid)
	local v = lb:GetAsync(Board.key(uid))
	if v == nil then return nil end
	return Board.metricOf(v)
end
eq(points(PAY), Board.metricOfDust(START_TOTAL + payBase, bc), "the board shows the pass owner's un-doubled points")
eq(points(FREE), Board.metricOfDust(START_TOTAL + freeBase, bc), "the board shows the other player's points")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("  measured: pass owner harvested %d dust of value (spendable %s, saved totalDust %s); other player %d",
	payBase, tostring(pd.dust), tostring(pd.totalDust), freeBase))
print(string.format("growacrystal pass: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal pass check failed", 0) end
