-- Find It! Chapters: the board across a UTC midnight, with a faked os.time (REVIEW-1 round 2, C2), through the REAL
-- server.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_midnight.luau 2>&1
--
-- Round 2 found two ways a LATER reach of a count out-ranked an EARLIER one: a Daily credit was stamped with 00:00
-- of its day (so 22:00 beat 01:00), and a Daily credited by the day its attempt STARTED could be paused across
-- midnight for hours and still be stamped yesterday. Now every rise is stamped with the UTC day it happened on, and
-- a room closes after Config.Pause.MaxBreakSeconds of break. Four players at 21 Cases Solved on day N:
--   * Ann clears Chapter 15 at 10:00 (22 on day N);
--   * Kim solves Case N at 22:00 (22 on day N): the same day, so she ties Ann and never out-ranks her;
--   * Lee opens Case N at 23:58 and pauses: after the break cap his room closes, nothing is credited; he plays
--     Case N+1 at 09:00 the next day (22 on day N+1);
--   * Sly opens Case N at 23:59 and solves it at 00:00:30 without a long break: it credits Case N (his streak goes
--     on) but he reached 22 on day N+1, so Ann and Kim rank above him; then he solves Case N+1 (23).
-- Adapted from the round-2 reviewer's rev_midnight.luau (which printed, and asserted nothing).

local realOs = os
local FAKE = 0
os = setmetatable({ time = function(t) if t ~= nil then return realOs.time(t) end return FAKE end }, { __index = realOs })

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-midnight", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local CFrame, Enum = dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local N = 20745
local D = 86400
FAKE = N * D + 10 * 3600 - 120 -- 09:58 on day N
local function seed(uid, cleared, dsolved)
	local stars = {}
	for ch = 1, cleared do stars["c" .. ch] = { f = true } end
	store:SetAsync("u_" .. uid, { data = { v = 1, book = { cleared = cleared, stars = stars }, daily = { lastDay = N - 1, solved = dsolved, streak = 3, bestStreak = 3 },
		solved = cleared + dsolved, solvedAt = (N - 1) * D, boarded = cleared + dsolved, seenIntro = true, firstJoin = (N - 30) * D }, lock = { session = "", ["until"] = 0 } })
end
seed(1101, 14, 7) -- Ann: 21
seed(1102, 15, 6) -- Kim: 21
seed(1103, 15, 6) -- Lee: 21
seed(1104, 15, 6) -- Sly: 21
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Board = mod("Config"), mod("Board")
local lb = DSS:GetOrderedDataStore(Config.Board.Store)
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local remotes = RS:FindFirstChild("FindItRemotes")
local function frame(d) RunService.Heartbeat:Fire(d); h:advance(d) end
local function run(s) local t = 0 while t < s - 1e-9 do local d = math.min(0.1, s - t); frame(d); t += d end end
local function last(name, p) local s = remotes:FindFirstChild(name):sentTo(p.plr); return s[#s] and s[#s].args[1] end
local function fire(name, p, ...) remotes:FindFirstChild(name):simulateFireServer(p.plr, ...) end
local function join(name, uid)
	local plr = h:join(name, uid)
	h:advance(0.5)
	local char = h.Players:simulateSpawn(plr, ws)
	char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
	h:advance(0.5)
	return { plr = plr, hrp = char:FindFirstChild("HumanoidRootPart"), uid = uid }
end
-- sit out the intro and search every hiding prop (the test peeks at the server-only rig); `beforeLast` runs just
-- before the last search
local function solve(p, beforeLast)
	while last("State", p).state == "intro" do run(0.1) end
	local pl = last("Room", p)
	local rig = HttpService:JSONDecode(ServerStorage.FindIt.Attempts:FindFirstChild(tostring(p.uid)).Value)
	for i, id in rig.hidden do
		if i == #rig.hidden and beforeLast then beforeLast() end
		for _, q in pl.props do if q.id == id then p.hrp.CFrame = CFrame.new(pl.origin[1] + q.x, 3, pl.origin[3] + q.z) end end
		fire("Search", p, id)
		run(1.1)
	end
	local t = 0
	while (last("State", p).state ~= "done" or (last("State", p).result or {}).saving) and t < 20 do run(0.1); t += 0.1 end
	return last("State", p)
end
local function value(uid) return lb:GetAsync("u_" .. uid) or 0 end
local function stored(uid) return store:GetAsync("u_" .. uid).data end
local function toHub(p) run(1.2); fire("Hub", p); run(1.2) end

local Ann, Kim, Lee, Sly = join("Ann", 1101), join("Kim", 1102), join("Lee", 1103), join("Sly", 1104)
run(1)

-- 10:00 day N: Ann clears Chapter 15
FAKE = N * D + 10 * 3600
fire("Open", Ann, 15); h:advance(0.05)
local sa = solve(Ann)
eq(sa.result.solved, 22, "Ann reached 22 at 10:00 on day N (Chapter 15)")
toHub(Ann)

-- 22:00 day N: Kim solves Case N
FAKE = N * D + 22 * 3600
fire("OpenDaily", Kim); h:advance(0.05)
eq(last("State", Kim).kind, "daily", "Kim opened the Daily")
local sk = solve(Kim)
eq(sk.result.credited, true, "Kim's Case N is credited")
eq(sk.result.solved, 22, "Kim reached 22 at 22:00 on day N")
run(2)
eq(stored(1101).solvedAt, N * D, "C2: Ann's 22 is stamped with day N")
eq(stored(1102).solvedAt, N * D, "C2: Kim's 22 is stamped with day N")
truthy(value(1102) <= value(1101), "C2: Kim, who reached 22 later the same day, never out-ranks Ann (they tie)")
toHub(Kim)

-- 23:58 day N: Lee opens Case N and pauses; the server keeps running
FAKE = N * D + 23 * 3600 + 58 * 60
fire("OpenDaily", Lee); h:advance(0.05)
eq(last("State", Lee).case, Config and (N - Config.Daily.FirstDay + 1), "Lee opened Case N at 23:58")
while last("State", Lee).state == "intro" do run(0.1) end
run(4)
fire("Pause", Lee); h:advance(0.1); run(0.2)
eq(last("State", Lee).state, "paused", "Lee paused")
local cap = Config.Pause.MaxBreakSeconds
local left0 = last("State", Lee).breakLeft
truthy(type(left0) == "number" and math.abs(left0 - cap) < 1, string.format("C2: the paused card is told the break left (%s of %d s)", tostring(left0), cap))
local closedAt = nil
for i = 1, 70 do
	FAKE += 10
	run(10)
	if closedAt == nil and last("State", Lee).state == "done" then closedAt = i * 10 end
end
eq(last("State", Lee).state, "done", "C2: a break past the cap closes Lee's room")
eq(last("State", Lee).result and last("State", Lee).result.reason, "break", "C2: ... reason 'break'")
truthy(closedAt ~= nil and closedAt >= cap - 10 and closedAt <= cap + 10, string.format("C2: ... after %s s of break (cap %d)", tostring(closedAt), cap))
FAKE = (N + 1) * D + 9 * 3600 -- 09:00 the next day
fire("Resume", Lee); h:advance(0.1); run(4)
eq(last("State", Lee).state, "done", "C2: a Resume the next morning does not reopen the room")
eq(stored(1103).solved, 21, "C2: Case N was never credited to Lee")
eq(stored(1103).daily.lastDay, N - 1, "C2: ... his last credited day is still N-1")
toHub(Lee)
fire("OpenDaily", Lee); h:advance(0.05)
eq(last("State", Lee).case, N + 1 - Config.Daily.FirstDay + 1, "Lee plays today's Case N+1")
local sl = solve(Lee)
eq(sl.result.credited, true, "Lee's Case N+1 is credited")
eq(sl.result.solved, 22, "Lee reached 22 on day N+1")
toHub(Lee)

-- Sly opens Case N at 23:59 on day N and solves it at 00:00:30 on day N+1, without a long break
FAKE = N * D + 23 * 3600 + 59 * 60
fire("OpenDaily", Sly); h:advance(0.05)
local caseN = last("State", Sly).case
local ss = solve(Sly, function() FAKE = (N + 1) * D + 30 end)
eq(ss.result.reason, "found", "Sly solved the Case he opened at 23:59")
eq(ss.result.credited, true, "C2: an attempt started on day N credits Case N after midnight (the start day)")
eq(stored(1104).daily.lastDay, N, "C2: ... day N is credited")
eq(stored(1104).daily.streak, 4, "C2: ... and his streak goes on (3 -> 4)")
eq(stored(1104).solved, 22, "Sly reached 22")
eq(stored(1104).solvedAt, (N + 1) * D, "C2: but he reached it on day N+1, the day he solved it")
truthy(value(1104) < value(1101) and value(1104) < value(1102), "C2: so Ann and Kim (22 on day N) rank above Sly (22 on day N+1)")
truthy(value(1104) == value(1103), "C2: and Sly ties Lee (22 on day N+1)")
toHub(Sly)
fire("OpenDaily", Sly); h:advance(0.05)
eq(last("State", Sly).case, caseN + 1, "Sly then plays today's Case N+1")
local s2 = solve(Sly)
eq(s2.result.credited, true, "Case N+1 credited")
eq(s2.result.solved, 23, "Sly 23")

-- the public board's order
do
	local entries = {}
	for _, uid in { 1101, 1102, 1103, 1104 } do table.insert(entries, { userId = uid, value = value(uid) }) end
	local rows = Board.publicView(Board.rank(entries, 10), Config.Board).rows
	local names = { [1101] = "Ann", [1102] = "Kim", [1103] = "Lee", [1104] = "Sly" }
	local line = {}
	for _, r in rows do table.insert(line, string.format("%d %s %d", r.rank, names[r.userId], r.solved)) end
	print("  board: " .. table.concat(line, " | "))
	eq(rows[1] and names[rows[1].userId], "Sly", "the board: Sly 23 first")
	eq(rows[2] and rows[2].rank, 2, "the board: then rank 2 ...")
	eq(rows[3] and rows[3].rank, 2, "... shared by Ann and Kim (22 on day N)")
	eq(rows[4] and names[rows[4].userId], "Lee", "the board: Lee (22 on day N+1) last")
	eq(rows[4] and rows[4].rank, 4, "... rank 4")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it midnight: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_midnight failed", 0) end
