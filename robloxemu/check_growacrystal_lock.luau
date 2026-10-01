-- Grow a Crystal — a save never lands over a session another server holds (review round 2, finding 5; standard §1).
-- Run: luau check_growacrystal_lock.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- saveProfile used to write old.data and jobId without asking who held the record. A reviewer's probe put
-- another server's live record in the store (jobId SERVER-B, lock +45 s, dust 99999, chambers 5, totalDust 5000,
-- WELCOME redeemed); ONE autosave from this server replaced it with dust 100, chambers 1, totalDust 0 and made
-- WELCOME redeemable again. That happens for real when a server stalls past the 45 s lock and the player
-- rejoins elsewhere.
--
-- What must hold (the fork-tower pattern, standard §1 "an owner token on every write"):
--   * the load that takes the lock writes a stable per-session token; every write lands only while the
--     record still carries it (and this server's jobId); otherwise the write is cancelled;
--   * a session that lost its record stops saving, grants no code it cannot persist, and tells the player;
--   * leaving does not release a lock that another server holds;
--   * the normal path is unchanged: saves land, leaving releases, a rejoin takes the lock again, a record
--     saved before this change (no token) is taken over, and a retried UpdateAsync transform is harmless.

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
local function data(d)
	local out = { dust = 100, seeds = { [1] = 3 }, chambers = 1, luckLevel = 0, growthLevel = 0,
		plants = {}, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {} }
	for k, v in d or {} do out[k] = v end
	return out
end
store:SetAsync("u_7070", { data = data() })
-- a record saved before this change: no session token, an expired lock from another server
store:SetAsync("u_8080", { jobId = "OLD-SERVER", lockUntil = os.time() - 5, data = data({ dust = 777 }) })
assert(h:tryRun("server/Main.server"))
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local R = h.ReplicatedStorage:FindFirstChild("CrystalRemotes")
local Toast, Redeem = R:FindFirstChild("Toast"), R:FindFirstChild("Redeem")

-- ── the takeover ──────────────────────────────────────────────────────────────
local plr = h:join("Owner", 7070)
h:advance(1)
local mine = store:GetAsync("u_7070")
truthy(type(mine.session) == "string" and #mine.session >= 16, "the load that took the lock wrote a session token")
eq(mine.jobId, h.game.JobId, "... and this server's jobId")
local token = mine.session

local theirs = { jobId = "SERVER-B", session = "SERVER-B-SESSION", lockUntil = os.time() + 45,
	data = data({ dust = 99999, chambers = 5, totalDust = 5000, redeemed = { WELCOME = true } }) }
store:SetAsync("u_7070", theirs)
local toasts0 = #Toast:sentTo(plr)
h:advance(Config.Save.AutosaveSeconds + 1) -- one autosave
local after = store:GetAsync("u_7070")
eq(after.data.dust, 99999, "an autosave does not overwrite the other server's dust")
eq(after.data.chambers, 5, "... or its chambers")
eq(after.data.totalDust, 5000, "... or its totalDust (the leaderboard metric)")
eq(after.data.redeemed.WELCOME, true, "... or its redeemed codes")
eq(after.jobId, "SERVER-B", "... or its jobId")
eq(after.session, "SERVER-B-SESSION", "... or its session token")
eq(after.lockUntil, theirs.lockUntil, "... or its lock")
truthy(#Toast:sentTo(plr) > toasts0, "the player is told this session no longer saves")

-- this session can no longer persist, so it must not grant a one-time code
local res = Redeem:simulateInvokeServer(plr, "CRYSTAL")
truthy(type(res) == "table" and res.ok == false, "a code is refused while this session cannot save (" .. tostring(res and res.reason) .. ")")
h:advance(Config.Save.AutosaveSeconds + 1)
eq(store:GetAsync("u_7070").data.dust, 99999, "a second autosave writes nothing either")
eq(#Toast:sentTo(plr) - toasts0, 1, "the player is told once, not on every autosave")

-- leaving does not release the other server's lock
h:leave(plr)
h:advance(1)
local left = store:GetAsync("u_7070")
eq(left.lockUntil, theirs.lockUntil, "leaving does not release a lock another server holds")
eq(left.session, "SERVER-B-SESSION", "... and does not write its token back")

-- a takeover by a server that predates the token (it writes jobId and lockUntil, keeps our session field)
store:SetAsync("u_7070", { jobId = "SERVER-C", session = nil, lockUntil = 0, data = data({ dust = 1 }) })
local again = h:join("Owner", 7070)
h:advance(1)
local rec2 = store:GetAsync("u_7070")
truthy(rec2.session ~= nil and rec2.session ~= token, "a rejoin takes the lock with a NEW session token")
local oldCode = table.clone(rec2)
oldCode.jobId = "SERVER-D-OLD-CODE" -- an old-code server loaded: new jobId, our token left in place
oldCode.lockUntil = os.time() + 45
oldCode.data = data({ dust = 4242 })
store:SetAsync("u_7070", oldCode)
h:advance(Config.Save.AutosaveSeconds + 1)
eq(store:GetAsync("u_7070").data.dust, 4242, "a record another server's jobId holds is not overwritten either")
h:leave(again)
h:advance(1)

-- the SAME server, a newer session (the player rejoined here while an older session's write was pending):
-- the jobId matches, the token does not, and the write must not land
store:SetAsync("u_7070", { data = data({ dust = 60 }) })
local third = h:join("Owner", 7070)
h:advance(1)
local cur = store:GetAsync("u_7070")
cur.session = "A-NEWER-SESSION-ON-THIS-SERVER"
cur.data = data({ dust = 31337 })
store:SetAsync("u_7070", cur)
h:advance(Config.Save.AutosaveSeconds + 1)
eq(store:GetAsync("u_7070").data.dust, 31337, "a newer session on this same server is not overwritten (the token, not just the jobId)")
h:leave(third)
h:advance(1)

-- ── the normal path is unchanged ────────────────────────────────────────────
store:SetAsync("u_7070", { data = data({ dust = 50 }) })
local normal = h:join("Owner", 7070)
h:advance(1)
local Buy = R:FindFirstChild("Buy")
Buy:simulateFireServer(normal, "seed", 1)
h:advance(0.5)
store.__retryCount = 2 -- the transform may run more than once
h:advance(Config.Save.AutosaveSeconds + 1)
store.__retryCount = 0
local saved = store:GetAsync("u_7070")
eq(saved.data.dust, 50 - Config.Economy.SeedCost[1], "an autosave in a session that holds the lock lands (with retried transforms)")
truthy(saved.lockUntil > os.time(), "... and renews the lock")
local res2 = Redeem:simulateInvokeServer(normal, "WELCOME")
truthy(type(res2) == "table" and res2.ok == true, "a code redeems while this session holds the lock")
eq(store:GetAsync("u_7070").data.redeemed.WELCOME, true, "... and is saved at once")
h:leave(normal)
h:advance(1)
eq(store:GetAsync("u_7070").lockUntil, 0, "leaving releases the lock")
local back = h:join("Owner", 7070)
h:advance(1)
eq(store:GetAsync("u_7070").jobId, h.game.JobId, "a rejoin takes it again")
h:leave(back)
h:advance(1)

-- a record saved before this change is taken over and saved normally
local legacy = h:join("Legacy", 8080)
h:advance(1)
local lrec = store:GetAsync("u_8080")
truthy(type(lrec.session) == "string", "a record without a token gets one when its expired lock is taken")
Buy:simulateFireServer(legacy, "seed", 1)
h:advance(Config.Save.AutosaveSeconds + 1)
eq(store:GetAsync("u_8080").data.dust, 777 - Config.Economy.SeedCost[1], "... and its saves land")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal lock: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal lock check failed", 0) end
