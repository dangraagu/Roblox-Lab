-- Find It! Chapters: a clear is never lost to the save path (REVIEW-1 A1, A2, A3 = B6), through the REAL server.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_save.luau 2>&1
--
-- Every clear is queued in the session until a write that carries it LANDS; every write the server makes (the
-- clear's own, the autosave, the profile load, the release on leave or shutdown) folds the queue into the record
-- inside its one atomic UpdateAsync. So:
--   * a clear made inside the 6 s write gap survives the player leaving or the server closing (A1), the Daily's
--     credit and streak too;
--   * one failed UpdateAsync does not lose a clear: the next autosave carries it, the card says so honestly and Next
--     works at once (A2);
--   * clears made while the profile load is retrying are merged when it lands, as the toast promises (A3 = B6), and
--     even if the player leaves before it lands; a merge never lowers a stored count;
--   * the transform is idempotent: forced UpdateAsync re-runs credit a clear exactly once.
-- Each scenario first proves it is real (the clear was still waiting when the player left, the write really
-- failed, the load really was retrying), so a pass cannot come from a scenario that never happened.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-save", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local CFrame, Enum = dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local NOW = os.time()
local TODAY = math.floor(NOW / 86400)
local function seed(uid, data)
	local d = { v = 1, book = { cleared = 0, stars = {} }, daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
		solved = 0, solvedAt = 0, boarded = 0, seenIntro = true, firstJoin = NOW - 86400 }
	for k, v in data do d[k] = v end
	store:SetAsync("u_" .. uid, { data = d, lock = { session = "", ["until"] = 0 } })
end
-- Dee: a 5-day Daily streak; Rho: a returning player with 5 chapters cleared
seed(9604, { book = { cleared = 3, stars = {} }, daily = { lastDay = TODAY - 1, solved = 5, streak = 5, bestStreak = 5 }, solved = 8, solvedAt = NOW - 86400, boarded = 8 })
seed(9608, { book = { cleared = 5, stars = { c1 = { f = true, w = false, s = false } } }, solved = 5, solvedAt = NOW - 86400, boarded = 5 })

assert(h:tryRun("server/Main.server"))
local BOOT = h.scheduler:now()
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local ST = Config.Save.Text
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
local function since() return h.scheduler:now() - BOOT end
local function untilT(t) if since() < t then run(t - since()) end end
local function player(name, uid)
	local plr = h:join(name, uid)
	h:advance(0.5)
	local char = h.Players:simulateSpawn(plr, ws)
	char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
	h:advance(0.5)
	return { plr = plr, hrp = char:FindFirstChild("HumanoidRootPart"), uid = uid }
end
local function last(name, p)
	local s = remotes:FindFirstChild(name):sentTo(p.plr)
	return s[#s] and s[#s].args[1]
end
local function toasts(p)
	local out = {}
	for _, x in remotes.Toast:sentTo(p.plr) do table.insert(out, x.args[1].text) end
	return out
end
local function toasted(p, text)
	for _, t in toasts(p) do if t == text then return true end end
	return false
end
local function rig(p)
	local v = ServerStorage.FindIt.Attempts:FindFirstChild(tostring(p.uid))
	return v and HttpService:JSONDecode(v.Value)
end
local function fire(name, p, ...) remotes:FindFirstChild(name):simulateFireServer(p.plr, ...) end
local function stored(uid)
	local rec = store:GetAsync("u_" .. uid)
	return rec and rec.data, rec and rec.lock
end
-- open (chapter n, or the Daily with n = nil), sit out the intro, find everything: a perfect reader
local function clear(p, chapter)
	if chapter then fire("Open", p, chapter) else fire("OpenDaily", p) end
	h:advance(0.05)
	run(3.2)
	local pl, sec = last("Room", p), rig(p)
	for i = 1, #sec.hidden do
		local id = sec.hidden[i]
		for _, q in pl.props do
			if q.id == id then p.hrp.CFrame = CFrame.new(pl.origin[1] + q.x * 0.85, 3, pl.origin[3] + q.z * 0.85 + 0.5) end
		end
		if p.failOnLast and i == #sec.hidden then store.__failNext = true end
		fire("Search", p, id)
		run(1.1)
	end
	return last("State", p)
end

--============================================================ control: a clear at a quiet moment, then leave
local A = player("Ann", 9601)
untilT(2)
local st = clear(A, 1)
eq(st.result and st.result.reason, "found", "control: chapter 1 found")
eq(st.result and st.result.saving, false, "control: outside the write gap the clear saved at once")
run(1)
h:leave(A.plr)
h:advance(1)
eq((stored(9601)).book.cleared, 1, "control: the stored record has chapter 1")

--============================================================ A1: a clear inside the write gap, then the player leaves
local B = player("Bo", 9602)
untilT(15) -- the 20 s autosave writes Bo's key; his clear lands ~1.6 s later, inside the 6 s gap
st = clear(B, 1)
eq(st.result and st.result.reason, "found", "A1 leave: chapter 1 found")
eq(st.result and st.result.saving, true, "A1 leave: the clear is still waiting for the write gap (the scenario is real)")
run(1)
h:leave(B.plr)
run(8)
do
	local d, lock = stored(9602)
	eq(d.book.cleared, 1, "A1 leave: the release carried the queued clear (chapter 1 stored)")
	eq(d.solved, 1, "A1 leave: Cases Solved 1 stored")
	eq(lock.session, "", "A1 leave: and released the lock")
end

--============================================================ A1: the same, then the server closes
local C = player("Cy", 9603)
untilT(35)
st = clear(C, 1)
eq(st.result and st.result.saving, true, "A1 close: the clear is still waiting for the write gap")
run(1)
h.game:runBindToClose()
run(8)
eq((stored(9603)).book.cleared, 1, "A1 close: BindToClose carried the queued clear")

--============================================================ A1: the Daily inside the gap keeps the streak
local D = player("Dee", 9604)
untilT(53.5)
st = clear(D, nil)
eq(st.kind, "daily", "A1 daily: the Daily Case was played")
eq(st.result and st.result.saving, true, "A1 daily: the solve is waiting for the write gap")
run(1)
h:leave(D.plr)
run(8)
do
	local d = stored(9604)
	eq(d.daily.lastDay, TODAY, "A1 daily: today's credit stored")
	eq(d.daily.streak, 6, "A1 daily: the 5-day streak became 6")
	eq(d.daily.solved, 6, "A1 daily: Daily solved 6")
	eq(d.solved, 9, "A1 daily: Cases Solved 9")
end

--============================================================ A2: one failed UpdateAsync on the clear
local E = player("Eli", 9605)
run(8)
E.failOnLast = true
st = clear(E, 1)
E.failOnLast = false
run(7)
st = last("State", E)
truthy(store.__failNext == false, "A2: the injected failure was consumed by the clear's write (the scenario is real)")
eq((stored(9605)).book.cleared, 0, "A2: right after the failed write nothing is stored yet")
eq(st.result.saving, false, "A2: the card stops saying Saving...")
eq(st.result.cantSave, nil, "A2: the card does not claim the server can't save")
eq(st.result.pendingSave, true, "A2: the card says the clear is kept and saved again shortly")
eq(st.result.note, ST.SaveLater, "A2: ... in these words")
eq(last("Profile", E).cleared, 1, "A2: the Case Book counts it now")
eq(E.plr.leaderstats.Solved.Value, 0, "A2: other players see only what is stored (leaderstats 0 while it is queued)")
run(1.2)
fire("Next", E)
h:advance(0.1)
eq(last("State", E).chapter, 2, "A2: Next opens chapter 2 at once (not 'Clear Chapter 1 first')")
run(25)
eq((stored(9605)).book.cleared, 1, "A2: within one autosave the queued clear is stored")
truthy(toasted(E, ST.Saved), "A2: and the player is told it is saved")
eq(E.plr.leaderstats.Solved.Value, 1, "A2: leaderstats 1 once it is stored")
fire("Hub", E)
run(1.2)

--============================================================ A3 = B6: clears while the load retries are merged
do
	local ph = since() % 20
	run((20 - ph) + 0.5) -- join just after an autosave tick, so the retry comes ~20 s later
end
-- the store stays down until the clear is made (REVIEW-1 round 2 C3 retries a failed load within 3 s, so one
-- failed call would no longer leave the load retrying while chapter 1 is played)
store.__failAll = true
local F = player("Fay", 9606)
eq(last("Profile", F).state, "retry", "A3: the load failed (the scenario is real)")
truthy(toasted(F, ST.LoadRetry), "A3: the player is told it is retrying")
st = clear(F, 1)
run(7)
st = last("State", F)
eq(last("Profile", F).state, "retry", "A3: chapter 1 was cleared while the load was still retrying")
eq(st.result.pendingSave, true, "A3: the card says the clear is kept")
eq(st.result.note, ST.LoadPending, "A3: ... and added when the progress loads")
run(1.2)
fire("Next", F)
h:advance(0.1)
eq(last("State", F).chapter, 2, "A3: Next opens chapter 2 (not 'Clear Chapter 1 first')")
store.__failAll = false
fire("Hub", F)
-- watch for the moment the retry load lands: the store must hold the clear THEN (merged by the load's own write),
-- not only after a later autosave happens to carry it
do
	local waited = 0
	while last("Profile", F).state ~= "ready" and waited < 40 do
		run(0.1)
		waited += 0.1
	end
	eq(last("Profile", F).state, "ready", "A3: the retry load landed")
	eq((stored(9606)).book.cleared, 1, "A3: the clear made during the retry is in the store the moment the load lands")
	run(1)
end
eq(last("Profile", F).cleared, 1, "A3: and the Case Book shows it")

-- a returning player: the merge never lowers what was stored
store.__failAll = true
local G = player("Rho", 9608)
eq(last("Profile", G).state, "retry", "A3 merge: Rho's load failed")
st = clear(G, 1)
eq(last("Profile", G).state, "retry", "A3 merge: chapter 1 was replayed while the load was still retrying")
store.__failAll = false
run(30)
do
	local d = stored(9608)
	eq(last("Profile", G).state, "ready", "A3 merge: the retry landed")
	eq(d.book.cleared, 5, "A3 merge: chapter 1 replayed during the retry did not lower Rho's 5 chapters")
	eq(d.solved, 5, "A3 merge: Cases Solved stays 5")
	eq(last("Profile", G).cleared, 5, "A3 merge: the Case Book shows 5 after the load")
end
fire("Hub", G)
run(1.2)

-- leaving before the retry lands still merges the clear (the release takes the lock only if it is free)
store.__failAll = true
local K = player("Kai", 9607)
eq(last("Profile", K).state, "retry", "A3 leave: Kai's load failed")
st = clear(K, 1)
run(3)
eq(last("State", K).result.pendingSave, true, "A3 leave: the clear is kept, waiting for the store")
store.__failAll = false
h:leave(K.plr)
run(2)
do
	local d, lock = stored(9607)
	eq(d and d.book.cleared, 1, "A3 leave: leaving before the retry merged the clear into the store")
	eq(lock and lock.session, "", "A3 leave: and left the lock free")
end

--============================================================ the transform is idempotent under re-runs
local M = player("Mo", 9609)
run(8)
store.__retryCount = 2
st = clear(M, 1)
run(7)
store.__retryCount = 0
eq((stored(9609)).solved, 1, "transform re-run twice: Cases Solved credited exactly once")
eq((stored(9609)).book.cleared, 1, "... and chapter 1 stored once")

for _, err in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. err)
end
print(string.format("find it save: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_save failed", 0) end
