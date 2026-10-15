-- Find It! Chapters: a clear that the RELEASE write carries reaches the public board (REVIEW-1 round 2, C1), through
-- the REAL server.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_release.luau 2>&1
--
-- A clear made inside the 6 s write gap is queued; when the player leaves (or the server shuts down) before the gap
-- ends, the release write carries it into the profile (round 1, A1). Round 2 found that nothing then wrote the
-- board: the profile said 15 and the public Cases Solved board said 14 until the player came back, and forever if
-- they never did, the likeliest case being BOOK ONE SOLVED, right before a player quits. Here: Ann (14 chapters)
-- clears Chapter 15 inside the gap and leaves; Bo does the same and the server closes. Each scenario first proves
-- it is real (the card still said Saving... when the player went), then reads the stores.
-- Adapted from the round-2 reviewer's rev_boardgap.luau (which printed, and asserted nothing).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-release", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local CFrame, Enum = dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local NOW = os.time()
local stars = {}
for ch = 1, 14 do stars["c" .. ch] = { f = true } end
for _, uid in { 611, 612 } do
	store:SetAsync("u_" .. uid, { data = { v = 1, book = { cleared = 14, stars = stars }, daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
		solved = 14, solvedAt = NOW - 86400, boarded = 14, seenIntro = true, firstJoin = NOW - 86400 * 9 }, lock = { session = "", ["until"] = 0 } })
end
assert(h:tryRun("server/Main.server"))
local BOOT = h.scheduler:now()
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Board = mod("Config"), mod("Board")
local lb = DSS:GetOrderedDataStore(Config.Board.Store)
for _, uid in { 611, 612 } do lb:SetAsync("u_" .. uid, Board.encode(14, NOW - 86400, Config.Board)) end
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local remotes = RS:FindFirstChild("FindItRemotes")
local function frame(d) RunService.Heartbeat:Fire(d); h:advance(d) end
local function run(s) local t = 0 while t < s - 1e-9 do local d = math.min(0.1, s - t); frame(d); t += d end end
local function last(name, p) local s = remotes:FindFirstChild(name):sentTo(p); return s[#s] and s[#s].args[1] end
local function fire(name, p, ...) remotes:FindFirstChild(name):simulateFireServer(p, ...) end
local function since() return h.scheduler:now() - BOOT end
local function untilT(t) if since() < t then run(t - since()) end end
local function join(name, uid)
	local plr = h:join(name, uid)
	h:advance(0.5)
	local char = h.Players:simulateSpawn(plr, ws)
	char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
	h:advance(0.5)
	return { plr = plr, hrp = char:FindFirstChild("HumanoidRootPart"), uid = uid }
end
-- open chapter 15, sit out the intro, search the nine hiding props (the test peeks at the server-only rig)
local function solve15(p)
	fire("Open", p.plr, 15)
	h:advance(0.05)
	while last("State", p.plr).state == "intro" do run(0.1) end
	local pl = last("Room", p.plr)
	local rig = HttpService:JSONDecode(ServerStorage.FindIt.Attempts:FindFirstChild(tostring(p.uid)).Value)
	for _, id in rig.hidden do
		for _, q in pl.props do if q.id == id then p.hrp.CFrame = CFrame.new(pl.origin[1] + q.x, 3, pl.origin[3] + q.z) end end
		fire("Search", p.plr, id)
		run(1.05)
	end
	return last("State", p.plr)
end
local function boardOf(uid) return Board.metricOf(lb:GetAsync("u_" .. uid)) end

local A = join("Ann", 611)
local B = join("Bo", 612)

--============================================================ C1: leave inside the write gap
untilT(8.6) -- the boot+20 autosave writes Ann's key; her Chapter 15 (3 s intro + 9 searches) ends ~1 s after it
local st = solve15(A)
eq(st.result and st.result.reason, "found", "C1 leave: Ann found everything in Chapter 15")
eq(st.result and st.result.saving, true, string.format("C1 leave: at boot+%.1f the clear is still waiting for the write gap (the scenario is real)", since()))
eq(st.result and st.result.bookSolved, nil, "C1 leave: the card has no outcome yet")
run(1.5)
eq(boardOf(611), 14, "C1 leave: the board still says 14 while the clear is queued")
h:leave(A.plr)
run(4)
do
	local rec = store:GetAsync("u_611")
	eq(rec.data.solved, 15, "C1 leave: the release write carried the clear (stored Cases Solved 15)")
	truthy(rec.data.bookSolvedAt ~= nil, "C1 leave: ... and BOOK ONE SOLVED")
	eq(rec.lock.session, "", "C1 leave: ... and freed the lock")
	eq(boardOf(611), 15, "C1 leave: the public board got the 15 right after the release landed")
end

--============================================================ C1: the server shuts down inside the write gap
untilT(28.6) -- the boot+40 autosave writes Bo's key; his Chapter 15 ends ~1 s after it
st = solve15(B)
eq(st.result and st.result.saving, true, string.format("C1 close: at boot+%.1f Bo's clear is still waiting for the write gap", since()))
run(1.5)
h.game:runBindToClose()
run(10)
do
	local rec = store:GetAsync("u_612")
	eq(rec.data.solved, 15, "C1 close: BindToClose carried Bo's clear (stored 15)")
	eq(boardOf(612), 15, "C1 close: the public board got Bo's 15 before the server went")
end

--============================================================ control: a later load never lowers the board
local A2 = join("Ann", 611)
run(3)
eq(last("Profile", A2.plr).cleared, 15, "rejoin: Ann's Case Book shows 15")
eq(boardOf(611), 15, "rejoin: the board still says 15")

--============================================================ REVIEW-1 round 2 D6: the Gold Book reaches the player
-- Gil has every chapter at three stars but Chapter 15's Sharp Eye; a perfect replay of Chapter 15 earns the 45th star.
do
	local s3 = {}
	for ch = 1, 15 do s3["c" .. ch] = { f = true, w = true, s = ch ~= 15 } end
	store:SetAsync("u_613", { data = { v = 1, book = { cleared = 15, stars = s3 }, daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
		solved = 15, solvedAt = NOW - 86400, boarded = 15, bookSolvedAt = NOW - 86400, seenIntro = true, firstJoin = NOW - 86400 * 9 }, lock = { session = "", ["until"] = 0 } })
	local G = join("Gil", 613)
	run(8)
	eq(last("Profile", G.plr).totalStars, 44, "D6: Gil has 44 stars")
	eq(last("Profile", G.plr).goldBook, false, "D6: ... and no Gold Book yet")
	local sg = solve15(G)
	local t = 0
	while (last("State", G.plr).result or {}).saving and t < 10 do run(0.1); t += 0.1 end
	sg = last("State", G.plr)
	eq(sg.result and sg.result.stars and sg.result.stars.s, true, "D6: the perfect replay earned Sharp Eye")
	eq(sg.result and sg.result.goldBook, true, "D6: the result card is told: GOLD BOOK")
	eq(last("Profile", G.plr).totalStars, 45, "D6: 45 stars")
	eq(last("Profile", G.plr).goldBook, true, "D6: the Case Book is the Gold Book")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it release: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_release failed", 0) end
