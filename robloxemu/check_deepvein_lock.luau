-- Deep Vein — EVERY WRITE CARRIES ITS OWNER. Review 2026-09-30, finding 2.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_lock.luau
--
-- saveProfile's UpdateAsync used to write `old.data` without looking at who held the record, and the only
-- owner stamp was game.JobId, which names a server, not a session. So when server A's lock lapsed (its
-- autosave failing for longer than SessionLockSeconds) and the player carried on in server B, A's copy of
-- the player leaving rolled B's progress back and RELEASED B's lock (the reviewer's probe: cash 999999 and
-- rebirths 5 written by the other server came back as 100 and 0, lockUntil 0).
-- complete-game-standard §1: an owner token on every write (fork-tower's `old.session`).
--
-- The other server is simulated the way a real one would behave: it writes the record in one UpdateAsync
-- with its own jobId, its own session token and a fresh lock; once WITHOUT a token at all; and once the way
-- the review's probe did, leaving the token field (still this server's) alone, as a server running code from
-- before tokens would. This file then asserts that nothing this server does lands on that record.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 1280, 720 },
	touch = false,
})

local Config = require("../deep-vein/src/shared/Config")
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local TAKEN, TOKENLESS, REBIRTHER, CALM, OLDCODE, SAMESERVER = 7171, 7272, 7373, 7474, 7575, 7676
local function base(extra)
	local d = { cash = 100, totalCash = 100, inventory = {}, pickTier = 1, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depthLayer = 0, bestLayer = 0 }
	for k, v in extra or {} do d[k] = v end
	return d
end
for _, uid in { TAKEN, TOKENLESS, CALM, OLDCODE, SAMESERVER } do
	store:SetAsync("u_" .. uid, { data = base() })
end
store:SetAsync("u_" .. REBIRTHER, { data = base({ runEarned = 1e12, cash = 1e6 }) })

assert(h:tryRun("server/Main.server"))
h:advance(1)
local remotes = h.ReplicatedStorage:FindFirstChild("VeinRemotes")
local StateEvent = remotes:FindFirstChild("State")
local ToastEvent = remotes:FindFirstChild("Toast")
local RebirthEvent = remotes:FindFirstChild("Rebirth")
local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function toastsOf(plr)
	local out = {}
	for _, rec in ToastEvent:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function record(uid) return store:GetAsync("u_" .. uid) end
local function joinAndSpawn(name, uid)
	local plr = h:join(name, uid)
	h:advance(1)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	return plr
end
-- another server takes the record: its own job, its own session (or none), a fresh lock, its own progress.
-- keepToken: a server running code from before session tokens (the review's probe) leaves the field alone.
-- job: the jobId the taker stamps (another server's by default; this server's for a newer session on it).
local function takeOver(uid, token, keepToken, job)
	store:UpdateAsync("u_" .. uid, function(old)
		old.jobId = job or "OTHER-SERVER"
		if not keepToken then old.session = token end
		old.lockUntil = os.time() + 600
		old.data.cash = 999999
		old.data.rebirths = 5
		return old
	end)
end
local function untouched(uid, token, what, job)
	local rec = record(uid)
	eq(rec.data.cash, 999999, what .. ": the other server's cash is still there")
	eq(rec.data.rebirths, 5, what .. ": …and its rebirths")
	eq(rec.jobId, job or "OTHER-SERVER", what .. ": …and its jobId")
	eq(rec.session, token, what .. ": …and its session token")
	truthy((tonumber(rec.lockUntil) or 0) > os.time(), what .. ": …and its lock is still held (lockUntil "
		.. tostring(rec.lockUntil) .. ")")
end

--======================================================================= the lock carries a session token
local calm = joinAndSpawn("Calm", CALM)
local rec0 = record(CALM)
truthy(type(rec0.session) == "string" and #rec0.session > 0, "taking the lock writes a session token (" .. tostring(rec0.session) .. ")")
truthy(rec0.session ~= rec0.jobId, "…which is not the server's JobId: a server holds many sessions")
local taken = joinAndSpawn("Taken", TAKEN)
truthy(record(TAKEN).session ~= rec0.session, "two sessions never share a token")

--======================================================================= a takeover: no write lands
takeOver(TAKEN, "OTHER-SESSION")
h:advance(Config.Save.AutosaveSeconds + 1) -- an autosave comes due
untouched(TAKEN, "OTHER-SESSION", "after this server's autosave")
eq(stateOf(taken).canSave, false, "this session knows it has lost the profile (the HUD's not-saving warning)")
local told = false
for _, t in toastsOf(taken) do
	if string.find(t, "another server", 1, true) then told = true end
end
truthy(told, "…and the player is told why nothing here saves any more")
h:leave(taken)
h:advance(2)
untouched(TAKEN, "OTHER-SESSION", "after this server's final save on leaving")

--======================================================================= a takeover by a write with no token
local tokenless = joinAndSpawn("Tokenless", TOKENLESS)
takeOver(TOKENLESS, nil)
h:leave(tokenless)
h:advance(2)
untouched(TOKENLESS, nil, "a takeover that wrote no token")

--======================================================================= a takeover by a server that never heard of tokens
-- (the review's own probe, and any server still running code from before this change during a rollout: it takes
-- the lock under its jobId and leaves the session field, which is still OURS, alone)
local oldcode = joinAndSpawn("OldCode", OLDCODE)
local ourToken = record(OLDCODE).session
takeOver(OLDCODE, nil, true)
h:leave(oldcode)
h:advance(2)
untouched(OLDCODE, ourToken, "a takeover by a server that wrote no token of its own")

--======================================================================= a takeover by a newer session on THIS server
-- game.JobId names a server, not a session (the review's point). A newer session of the same player on THIS
-- server (a quick rejoin while this session's copy still writes) stamps this server's jobId, so only the
-- session token tells the two apart: every check above would still pass if saveProfile compared jobIds alone.
local same = joinAndSpawn("SameServer", SAMESERVER)
local thisJob = record(SAMESERVER).jobId
truthy(type(thisJob) == "string" and #thisJob > 0, "set-up: this server stamps its jobId (" .. tostring(thisJob) .. ")")
takeOver(SAMESERVER, "NEWER-SESSION-SAME-SERVER", false, thisJob)
h:advance(Config.Save.AutosaveSeconds + 1) -- the older session's autosave comes due
untouched(SAMESERVER, "NEWER-SESSION-SAME-SERVER", "a newer session on this server, after the older one's autosave", thisJob)
eq(stateOf(same).canSave, false, "…and the older session knows it has lost the profile")
h:leave(same)
h:advance(2)
untouched(SAMESERVER, "NEWER-SESSION-SAME-SERVER", "a newer session on this server, after the older one's final save", thisJob)

--======================================================================= a rebirth after a takeover is rolled back
local reb = joinAndSpawn("Rebirther", REBIRTHER)
takeOver(REBIRTHER, "OTHER-SESSION-2")
RebirthEvent:simulateFireServer(reb)
h:advance(1)
eq(stateOf(reb).rebirths, 0, "a rebirth whose atomic flush hit another session's record is rolled back")
untouched(REBIRTHER, "OTHER-SESSION-2", "after the refused rebirth")

--======================================================================= CONTROL: the owner still saves
do
	local before = record(CALM)
	h:advance(Config.Save.AutosaveSeconds + 1)
	local mid = record(CALM)
	eq(mid.session, before.session, "CONTROL: the owner's autosave keeps its own token")
	truthy((tonumber(mid.lockUntil) or 0) > os.time(), "CONTROL: …and renews its lock")
	h:leave(calm)
	h:advance(2)
	local after = record(CALM)
	eq(after.lockUntil, 0, "CONTROL: the owner's final save releases the lock")
	eq(after.data.cash, 100, "CONTROL: …and writes its data")
	local again = joinAndSpawn("Calm", CALM)
	local rec2 = record(CALM)
	truthy(type(rec2.session) == "string" and rec2.session ~= before.session, "CONTROL: a rejoin takes the lock with a NEW token")
	eq(stateOf(again).canSave, true, "CONTROL: …and saves")
end

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein lock: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein lock check failed", 0)
end
