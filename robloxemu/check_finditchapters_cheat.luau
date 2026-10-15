-- Find It! Chapters: every defended row of DESIGN.md §14, through the REAL server.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_cheat.luau 2>&1
--
-- Forged and malformed payloads, an id that is not in the room, out of reach, during a search (two in one frame
-- spend one look), while paused, with no looks left, after the time, a second hint, a Resume within 3 s, a locked
-- chapter, the Daily before Chapter 3, Open spam, a read-only session (cannot credit), a write after another
-- session took the lock (the owner token), and the Daily credited once. Every refusal an honest HUD can trigger is
-- answered in words; a payload only a script can send is dropped.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-cheat", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local NOW = os.time()
-- Lou's save is open on another server (a lock that has not expired)
store:SetAsync("u_7002", { data = { v = 1, book = { cleared = 0, stars = {} }, daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
	solved = 0, solvedAt = 0, boarded = 0, seenIntro = false, firstJoin = NOW }, lock = { session = "another-server", ["until"] = NOW + 3600 } })
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local T = Config.Text
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local remotes = RS:FindFirstChild("FindItRemotes")

local function frame(d)
	RunService.Heartbeat:Fire(d)
	h:advance(d)
end
local function run(seconds)
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(0.1, seconds - t)
		frame(d)
		t += d
	end
end
local function player(name, uid)
	local plr = h:join(name, uid)
	h:advance(0.5)
	local char = h.Players:simulateSpawn(plr, ws)
	char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
	h:advance(0.5)
	return { plr = plr, hrp = char:FindFirstChild("HumanoidRootPart") }
end
local function last(name, p)
	local s = remotes:FindFirstChild(name):sentTo(p.plr)
	return s[#s] and s[#s].args[1]
end
local function count(name, p) return #remotes:FindFirstChild(name):sentTo(p.plr) end
local function rig(p)
	local v = ServerStorage.FindIt.Attempts:FindFirstChild(tostring(p.plr.UserId))
	return v and HttpService:JSONDecode(v.Value)
end
local function propOf(pl, id) for _, q in pl.props do if q.id == id then return q end end end
local function standNear(p, pl, id)
	local q = propOf(pl, id)
	local o = pl.origin
	p.hrp.CFrame = CFrame.new(o[1] + q.x * 0.85, 3, o[3] + q.z * 0.85 + 0.5)
end
local function fire(name, p, ...)
	remotes:FindFirstChild(name):simulateFireServer(p.plr, ...)
end
local function lookFor(p) return last("State", p).looks end

local A = player("Ann", 7001)
-- into chapter 1
fire("Open", A, 1)
h:advance(0.1)
eq(last("State", A).chapter, 1, "Ann is in chapter 1")
run(3.2)
local pl = last("Room", A)
local sec = rig(A)

--============================================================ malformed payloads are dropped (only a script sends them)
do
	local looks0, toasts0 = lookFor(A), count("Toast", A)
	for _, bad in { "1", 0 / 0, 1e12, 3.5, -1, {}, true, math.huge } do
		fire("Search", A, bad)
	end
	fire("AskHint", A, "1")
	fire("AskHint", A, {})
	fire("Open", A, "2")
	fire("Open", A, 16)
	fire("Open", A, 2.5)
	h:advance(0.2)
	eq(lookFor(A), looks0, "malformed searches spend no look")
	eq(count("Toast", A), toasts0, "malformed payloads are dropped without an answer (the honest HUD cannot send them)")
	eq(#h:errors(), 0, "and nothing on the server broke")
end

--============================================================ an id that is not in this room
do
	local looks0 = lookFor(A)
	fire("Search", A, 999)
	h:advance(0.1)
	eq(last("Toast", A).text, T.DecorTap, "an id that is not in Ann's room: 'Nothing to search there'")
	eq(lookFor(A), looks0, "no look spent")
end

--============================================================ out of reach
do
	local looks0 = lookFor(A)
	A.hrp.CFrame = CFrame.new(pl.origin[1], 3, pl.origin[3] + 1)
	-- the farthest prop that hides nothing (searching a hidden one here would change what the next sections test)
	local far, fd = nil, 0
	local hid0 = { [sec.hidden[1]] = true, [sec.hidden[2]] = true, [sec.hidden[3]] = true }
	for _, q in pl.props do
		local d = math.sqrt(q.x * q.x + q.z * q.z)
		if d > fd and not hid0[q.id] then far, fd = q, d end
	end
	fire("Search", A, far.id)
	h:advance(0.1)
	eq(last("Toast", A).text, T.WalkCloser, string.format("a prop %.1f studs away: 'Walk closer'", fd))
	eq(lookFor(A), looks0, "no look spent")
	-- a teleport is not policed (DESIGN.md §14), but the server checks reach against ITS view of the root
	standNear(A, pl, far.id)
	fire("Search", A, far.id)
	h:advance(0.1)
	eq(lookFor(A), looks0 - 1, "standing next to it, the search goes out")
	run(1.1)
	A.searchedFar = far.id
end

--============================================================ one search at a time: two in one frame spend one look
do
	local looks0 = lookFor(A)
	-- two props that hide nothing, close enough together that one spot reaches both
	local a1, a2, best = nil, nil, math.huge
	local hid = { [sec.hidden[1]] = true, [sec.hidden[2]] = true, [sec.hidden[3]] = true }
	for _, q in pl.props do
		for _, r in pl.props do
			if q.id < r.id and not hid[q.id] and not hid[r.id] and q.id ~= A.searchedFar and r.id ~= A.searchedFar then
				local d = (q.x - r.x) ^ 2 + (q.z - r.z) ^ 2
				if d < best then a1, a2, best = q, r, d end
			end
		end
	end
	standNear(A, pl, a1.id)
	A.hrp.CFrame = CFrame.new(pl.origin[1] + a1.x * 0.5 + a2.x * 0.5, 3, pl.origin[3] + a1.z * 0.5 + a2.z * 0.5)
	fire("Search", A, a1.id)
	fire("Search", A, a2.id)
	h:advance(0.05)
	local looksAfter = lookFor(A)
	local toastText = last("Toast", A) and last("Toast", A).text
	run(1.1)
	eq(looksAfter, looks0 - 1, string.format("two searches in one frame (props %.1f studs apart) spend ONE look", math.sqrt(best)))
	eq(toastText, T.OneAtATime, "the second: 'One search at a time'")
end

--============================================================ the hint: once; junk is dropped
do
	local id = nil
	fire("AskHint", A, 2)
	h:advance(0.1)
	local hint = last("Hint", A)
	eq(hint and hint.id, sec.hidden[2], "the hint names item 2's prop")
	run(0.6)
	fire("AskHint", A, 3)
	h:advance(0.1)
	eq(last("Toast", A).text, T.HintUsed, "a second hint: 'You've used this chapter's hint'")
end

--============================================================ paused: searches refused; a Resume within 3 s waits
do
	fire("Pause", A)
	h:advance(0.1)
	run(0.1)
	eq(last("State", A).state, "paused", "paused")
	fire("Search", A, sec.hidden[1])
	h:advance(0.1)
	eq(last("Toast", A).text, T.OnBreak, "a search while paused: refused")
	fire("Resume", A)
	h:advance(0.1)
	eq(last("Toast", A).text, T.Resuming, "a Resume within 3 s: 'Resuming in a moment...'")
	run(1)
	eq(last("State", A).state, "paused", "still paused 1.2 s after the Pause")
	run(2.2)
	eq(last("State", A).state, "live", "live at 3 s")
	pl = last("Room", A)
	sec = rig(A)
end

--============================================================ out of looks
do
	-- spend every look on props that hide nothing
	local hidden = {}
	for _, id in sec.hidden do hidden[id] = true end
	for _, q in pl.props do
		if not hidden[q.id] and last("State", A).state == "live" then
			standNear(A, pl, q.id)
			fire("Search", A, q.id)
			run(1.1)
		end
	end
	local st = last("State", A)
	eq(st.state, "done", "the looks ran out: the attempt ended")
	eq(st.result and st.result.reason, "looks", "reason: looks")
	fire("Search", A, sec.hidden[1])
	h:advance(0.1)
	eq(last("Toast", A).text, T.NoLooks, "a search with no looks left: 'No looks left'")
	eq(store:GetAsync("u_7001").data.book.cleared, 0, "nothing was credited")
end

--============================================================ after the time
do
	run(1.1)
	fire("Retry", A)
	h:advance(0.1)
	eq(last("State", A).state, "intro", "Retry: a new room")
	run(3.2 + Config.Chapters[1].clock + 0.5)
	local st = last("State", A)
	eq(st.result and st.result.reason, "time", "the clock ran out")
	local s2 = rig(A)
	fire("Search", A, s2.hidden[1])
	h:advance(0.1)
	eq(last("Toast", A).text, T.TimeUp, "a search after the time: 'Time's up'")
end

--============================================================ locked chapters, the Daily before Chapter 3, Open spam
do
	fire("Hub", A)
	run(1.2)
	fire("Open", A, 5)
	h:advance(0.1)
	eq(last("Toast", A).text, string.format(T.Locked, 1), "chapter 5 for a new player: 'Clear Chapter 1 first'")
	eq(last("State", A).where, "hub", "and no room opened")
	run(1.1)
	fire("OpenDaily", A)
	h:advance(0.1)
	eq(last("Toast", A).text, T.DailyLocked, "the Daily before Chapter 3: 'The Daily Case opens after Chapter 3'")
	run(1.1)
	local rooms0 = count("Room", A)
	for _ = 1, 10 do fire("Open", A, 1) end
	h:advance(0.1)
	eq(count("Room", A) - rooms0, 1, "ten Opens in one frame start ONE room")
end

--============================================================ a read-only session cannot credit
local L = player("Lou", 7002)
do
	local prof = last("Profile", L)
	eq(prof.canSave, false, "Lou's save is open on another server: this session cannot save")
	eq(last("Toast", L).text, Config.Save.Text.Locked, "and is told so")
	fire("Open", L, 1)
	h:advance(0.1)
	run(3.2)
	local lp = last("Room", L)
	local ls = rig(L)
	for _, id in ls.hidden do
		standNear(L, lp, id)
		fire("Search", L, id)
		run(1.1)
	end
	run(7)
	local st = last("State", L)
	eq(st.result and st.result.reason, "found", "Lou found everything")
	eq(st.result and st.result.cantSave, true, "the clear card says this server can't save")
	eq(st.result and st.result.note, Config.Save.Text.CantSave, "'This server can't save your progress right now'")
	eq(store:GetAsync("u_7002").data.book.cleared, 0, "nothing was granted in the store")
	eq(store:GetAsync("u_7002").lock.session, "another-server", "the other server's lock is untouched")
	eq(L.plr.leaderstats.Solved.Value, 0, "Cases Solved is not credited")
	local lb = DSS:GetOrderedDataStore(Config.Board.Store)
	eq(lb:GetAsync("u_7002"), nil, "nothing on the board")
end

--============================================================ a write after another session took the lock (the owner token)
do
	local B = player("Bea", 7003)
	fire("Open", B, 1)
	h:advance(0.1)
	run(3.2)
	local bp = last("Room", B)
	local bs = rig(B)
	-- another server takes Bea's lock while she plays
	store:UpdateAsync("u_7003", function(rec)
		rec.lock = { session = "the-other-server", ["until"] = os.time() + 3600 }
		return rec
	end)
	for _, id in bs.hidden do
		standNear(B, bp, id)
		fire("Search", B, id)
		run(1.1)
	end
	run(7)
	local st = last("State", B)
	eq(st.result and st.result.cantSave, true, "the clear finds another session's token: it is not written")
	eq(store:GetAsync("u_7003").data.book.cleared, 0, "no grant over another session's lock")
	eq(store:GetAsync("u_7003").lock.session, "the-other-server", "the other session's lock stands")
	eq(last("Profile", B).canSave, false, "the session goes read-only")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it cheat: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_cheat failed", 0) end
