-- Outpost Zero — saving, the session lock and the owner token, through the real server.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_save.luau 2>&1
--
-- The emulator's DataStore does a real JSON round trip, runs UpdateAsync transforms that may be retried, aborts a
-- write when a transform returns nil, and can be made to fail on demand (__failAll / __failNext). The cases
-- (docs/complete-game-standard.md §1, DESIGN 10.1; the meteor-drop-tycoon REVIEW-1 lock cases carried over):
--   A. two sessions on one profile: the second loads the real data READ-ONLY, pays nothing it can keep, writes
--      nothing (not the board either);
--   B. a late write from a session that no longer owns the record is CANCELLED by the owner token;
--   E. a store that fails at load through every retry: a non-saving session, said out loud, that never writes;
--   F. UpdateAsync running its transform three times still loads and saves the same profile, string keys only;
--   H. a lock that clears seconds after the join: the join waits (told once) and the session SAVES;
--   I. a lock still held after the wait: read-only, then it lapses and the session takes over;
--   J. ...but if the other server WROTE meanwhile, the session stays unsaved and says rejoin;
--   K. ONE transient failure at load: the retry loads the real profile, writable;
--   V. a record from a newer version (v = 2) is played in memory and never written or locked;
--   S. a corrupt seed is redrawn (a new layout beats a city that cannot load) and the record is repaired;
--   O. offline earnings in a read-only session are shown but never saved, so the next saving session pays them once.
-- robloxemu's os.time() is the wall clock while its task clock is virtual, so these cases move locks and absences by
-- editing the record, never by waiting for os.time() to pass.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("OutpostZero_Census_v1")
local T = os.time()
local LOCKED, TAKEN, UNSAVED, RETRY, LATE, HELD, CHANGED, BLIP, FUTURE, BADSEED, AWAY = 101, 202, 404, 505, 707, 708, 709, 710, 711, 712, 713

-- a small city: 2 Homes and 2 Workshops' worth on seed 4242 is laid out by the server; this profile only names
-- storeys on lots 1_1..1_6, so its population depends on the seed's zones (each district is 3 + 3)
local function city(locked: boolean, credits: number?)
	return { session = if locked then "someone-else" else nil, jobId = if locked then "another-server" else nil,
		lockUntil = if locked then T + 300 else 0,
		data = { v = 1, seed = 4242, credits = credits or 500, lifetime = 900,
			lots = { ["1_1"] = 3, ["1_2"] = 3, ["1_3"] = 3, ["1_4"] = 3, ["1_5"] = 3, ["1_6"] = 3 },
			savedAt = T, ordersUntil = T + 600, popAt = T - 50, airshipSeen = false, tutorial = 3 } }
end
store:SetAsync("u_" .. LOCKED, city(true))
store:SetAsync("u_" .. UNSAVED, city(false))

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local WAIT = Config.Save.LockWaitSeconds + 1
local remotes = h.ReplicatedStorage:FindFirstChild("CityRemotes")
local State, Toast = remotes.State, remotes.Toast
local function stateOf(plr)
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function anyToast(plr, needle)
	for _, rec in Toast:sentTo(plr) do
		if string.find(tostring(rec.args[1]), needle, 1, true) then return true end
	end
	return false
end
local function join(name, uid)
	local plr = h:join(name, uid)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.3)
	return plr, char:FindFirstChild("HumanoidRootPart")
end
-- press the ★ lot once (stood at its post); returns true when a storey was bought
local function pressStar(plr, hrp)
	local st = stateOf(plr)
	if st == nil or st.star == nil then return false end
	local shelf = plr.RespawnLocation.Parent
	local post = shelf.Lots:FindFirstChild("Lot_" .. st.star.key).Post
	hrp.CFrame = CFrame.new(post.Position + Vector3.new(0, 1.5, 0))
	local s0 = st.settlers + st.jobs
	post.BuildPrompt.Triggered:Fire(plr)
	h:advance(0.2)
	local st2 = stateOf(plr)
	return st2.settlers + st2.jobs > s0
end
local function storeysSum(data)
	local n = 0
	for _, s in data.lots do n += s end
	return n
end

--============================================================================ A. two sessions on one profile
do
	local before = store:GetAsync("u_" .. LOCKED)
	local plr, hrp = join("Second", LOCKED)
	h:advance(WAIT) -- the join waits for the lock first (H)
	local st = stateOf(plr)
	truthy(st and st.loaded, "A: the locked profile still loads")
	eq(st and st.saving, false, "A: ...READ-ONLY: this session will not save")
	eq(#plr.RespawnLocation.Parent.Lots:GetChildren(), 6, "A: ...with the real saved city (the Landing Field built), not a blank profile")
	truthy(st and st.settlers + st.jobs == 72, "A: (18 storeys x 4 people)")
	truthy(anyToast(plr, Config.Tutorial.NotSavingLocked), "A: and the player is told, with what happens next")
	truthy(pressStar(plr, hrp), "A: the city still plays in memory (a storey bought)")
	h:advance(70)
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. LOCKED)
	eq(after.session, "someone-else", "A: the other session still owns the record")
	eq(storeysSum(after.data), storeysSum(before.data), "A: and its data was never overwritten (the same storeys)")
	eq(after.data.credits, before.data.credits, "A: (the same credits)")
	eq(board:GetAsync("u_" .. LOCKED), nil, "A: and a read-only session never writes the Census (it ranks only what was saved)")
end

--============================================================================ B. the owner token cancels a late write
do
	local plr, hrp = join("Taken", TAKEN)
	h:advance(1)
	local st = stateOf(plr)
	eq(st and st.saving, true, "B: a fresh profile loads writable")
	pressStar(plr, hrp)
	h:advance(8) -- one flush tick: the record now carries this session's token and the new city
	local mine = store:GetAsync("u_" .. TAKEN)
	truthy(type(mine.session) == "string" and #mine.session > 0, "B: the load wrote an owner token")
	truthy(type(mine.data.seed) == "number" and mine.data.seed >= 1, "B: and the first write saved the drawn seed")
	-- another server takes the record (its load wrote its own token)
	mine.session = "newer-session"
	mine.jobId = "another-server"
	mine.lockUntil = os.time() + 120
	mine.data.credits = 777
	store:SetAsync("u_" .. TAKEN, mine)
	local warns0 = #h.warnings
	pressStar(plr, hrp) -- a change that wants a write
	h:advance(Config.Save.AutosaveSeconds + 2 * Config.Save.FlushTickSeconds + 1)
	eq(stateOf(plr).saving, false, "B: the old session notices it lost the record and stops saving")
	truthy(anyToast(plr, "not being saved"), "B: and says so")
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. TAKEN)
	eq(after.session, "newer-session", "B: the late releasing write did not re-release the newer session's record")
	eq(after.data.credits, 777, "B: and did not write over its data")
	truthy(after.lockUntil > 0, "B: the lock is still held by the newer session")
	truthy(#h.warnings > warns0, "B: the server logged the takeover")
end

--============================================================================ E. the store fails at load, through every retry
do
	store.__failAll = true
	local plr, hrp = join("Offline", UNSAVED)
	h:advance(6) -- LoadAttempts (3) tries, 1 s then 2 s apart: every one fails
	store.__failAll = false
	local st = stateOf(plr)
	truthy(st and st.loaded, "E: the session still starts")
	eq(st and st.saving, false, "E: as a NON-saving session (it never switches to saving mid-session)")
	truthy(anyToast(plr, "not being saved"), "E: and says so")
	local before = store:GetAsync("u_" .. UNSAVED)
	pressStar(plr, hrp)
	h:advance(20)
	local after = store:GetAsync("u_" .. UNSAVED)
	eq(storeysSum(after.data), storeysSum(before.data), "E: the saved profile is untouched")
	eq(stateOf(plr).saving, false, "E: still not saving after the store recovers")
	h:leave(plr)
	h:advance(1)
	eq(storeysSum(store:GetAsync("u_" .. UNSAVED).data), storeysSum(before.data), "E: not even by the leave")
end

--============================================================================ F. retried transforms
do
	store.__retryCount = 2 -- every UpdateAsync runs its transform three times
	local plr, hrp = join("Retry", RETRY)
	h:advance(1)
	eq(stateOf(plr).saving, true, "F: a retried load still takes the lock exactly once")
	pressStar(plr, hrp)
	pressStar(plr, hrp)
	h:advance(30)
	h:leave(plr)
	h:advance(1)
	local rec = store:GetAsync("u_" .. RETRY)
	eq(rec.lockUntil, 0, "F: and a retried release still releases")
	truthy(rec.data and rec.data.v == 1 and storeysSum(rec.data) == 2, "F: with the profile written (2 storeys)")
	store.__retryCount = 0
	local numeric = 0
	for k in rec.data do if type(k) ~= "string" then numeric += 1 end end
	for k in rec.data.lots do if type(k) ~= "string" then numeric += 1 end end
	eq(numeric, 0, "F: no integer keys in a saved profile or its lots, after the JSON round trip")
	truthy(type(rec.data.savedAt) == "number" and rec.data.savedAt > 0, "F: savedAt is written with the credits")
end

--============================================================================ H. a lock that clears seconds after the join
do
	local rec0 = city(true)
	rec0.session, rec0.jobId, rec0.lockUntil = "old-session", "old-server", os.time() + 110
	store:SetAsync("u_" .. LATE, rec0)
	local plr, hrp = join("Late", LATE)
	local st = stateOf(plr)
	eq(st and st.loaded, false, "H: the join finds the record locked and WAITS for it (not loaded yet)")
	truthy(anyToast(plr, Config.Tutorial.LockWaiting), "H: and says it is waiting")
	h:advance(2)
	local rec = store:GetAsync("u_" .. LATE)
	rec.lockUntil = 0 -- the old server's leave-write lands, 2 s late
	store:SetAsync("u_" .. LATE, rec)
	h:advance(Config.Save.LockRetrySeconds)
	st = stateOf(plr)
	eq(st and st.loaded, true, "H: the next read finds it free and loads")
	eq(st and st.saving, true, "H: ...WRITABLE: this session saves")
	local n0 = storeysSum(rec.data)
	pressStar(plr, hrp)
	h:advance(8)
	rec = store:GetAsync("u_" .. LATE)
	eq(storeysSum(rec.data), n0 + 1, "H: a purchase reaches the store")
	truthy(rec.session ~= "old-session", "H: under this session's own token")
	h:leave(plr)
	h:advance(1)
	eq(store:GetAsync("u_" .. LATE).lockUntil, 0, "H: and leaving releases it")
end

--============================================================================ I. still locked after the wait: read-only, then it takes over
do
	store:SetAsync("u_" .. HELD, city(true))
	local plr, hrp = join("Held", HELD)
	h:advance(WAIT)
	local st = stateOf(plr)
	eq(st and st.loaded, true, "I: after the join wait the session plays")
	eq(st and st.saving, false, "I: read-only while the other server holds the lock")
	local n0 = storeysSum(store:GetAsync("u_" .. HELD).data)
	truthy(pressStar(plr, hrp), "I: set-up: a purchase in memory")
	local rec = store:GetAsync("u_" .. HELD)
	rec.lockUntil = 0 -- the other server lets go with its data unchanged
	store:SetAsync("u_" .. HELD, rec)
	h:advance(Config.Save.LockRecheckSeconds + 1)
	eq(stateOf(plr).saving, true, "I: the session re-checks, finds the lock free and the data as it read it, and takes over")
	truthy(anyToast(plr, Config.Tutorial.LockTaken), "I: and says so")
	h:advance(8)
	rec = store:GetAsync("u_" .. HELD)
	eq(storeysSum(rec.data), n0 + 1, "I: the purchase made while read-only is saved")
	truthy(rec.session ~= "someone-else" and (rec.lockUntil or 0) > 0, "I: under this session's own lock")
	h:leave(plr)
	h:advance(1)
	eq(store:GetAsync("u_" .. HELD).lockUntil, 0, "I: released on leaving")
end

--============================================================================ J. the other server wrote meanwhile: never overwrite it
do
	store:SetAsync("u_" .. CHANGED, city(true))
	local plr, hrp = join("Changed", CHANGED)
	h:advance(WAIT)
	eq(stateOf(plr).saving, false, "J: set-up: read-only")
	local rec = store:GetAsync("u_" .. CHANGED)
	rec.data.lots["1_1"] = 9
	rec.data.credits = 4321
	rec.lockUntil = 0 -- the other server saved new progress, then let go
	store:SetAsync("u_" .. CHANGED, rec)
	h:advance(Config.Save.LockRecheckSeconds + 1)
	eq(stateOf(plr).saving, false, "J: data that changed since this session read it is never overwritten: still not saving")
	truthy(anyToast(plr, Config.Tutorial.LockChanged), "J: and the player is told to rejoin")
	pressStar(plr, hrp)
	h:advance(70)
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. CHANGED)
	eq(after.data.lots["1_1"], 9, "J: the other server's storeys stand")
	eq(after.data.credits, 4321, "J: (and its credits)")
end

--============================================================================ K. one transient failure at load
do
	store:SetAsync("u_" .. BLIP, city(false, 1234))
	store.__failNext = true -- the load's own UpdateAsync is the next call
	local plr = join("Blip", BLIP)
	h:advance(3)
	local st = stateOf(plr)
	eq(st and st.saving, true, "K: one failed read at the join is retried and the session saves")
	eq(st and st.settlers + st.jobs, 72, "K: with the real city, not a blank one")
	h:leave(plr)
	h:advance(1)
	eq(storeysSum(store:GetAsync("u_" .. BLIP).data), 18, "K: and the record is intact")
end

--============================================================================ V. a record from a newer version is never written
do
	local rec0 = city(false, 999)
	rec0.data.v = 2
	rec0.data.newField = "from the future"
	store:SetAsync("u_" .. FUTURE, rec0)
	local warns0 = #h.warnings
	local plr, hrp = join("Future", FUTURE)
	h:advance(2)
	local st = stateOf(plr)
	truthy(st and st.loaded, "V: a v2 record still plays (in memory)")
	eq(st and st.saving, false, "V: but this version never saves it")
	truthy(#h.warnings > warns0, "V: and the server logs why")
	pressStar(plr, hrp)
	h:advance(70)
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. FUTURE)
	eq(after.data.v, 2, "V: the record is still v2")
	eq(after.data.newField, "from the future", "V: with its unknown fields intact")
	eq(after.data.credits, 999, "V: and its credits")
	eq(after.session, nil, "V: never locked by this version")
end

--============================================================================ S. a corrupt seed is redrawn and repaired
do
	local rec0 = city(false)
	rec0.data.seed = -5
	store:SetAsync("u_" .. BADSEED, rec0)
	local warns0 = #h.warnings
	local plr = join("BadSeed", BADSEED)
	h:advance(9)
	local st = stateOf(plr)
	truthy(st and st.loaded and st.saving, "S: a record with a corrupt seed still loads, writable")
	eq(#plr.RespawnLocation.Parent.Lots:GetChildren(), 6, "S: on a newly drawn layout")
	truthy(#h.warnings > warns0, "S: the server logs the redraw")
	local seed = store:GetAsync("u_" .. BADSEED).data.seed
	truthy(type(seed) == "number" and seed >= 1 and seed <= 2147483646, "S: and the repaired seed is saved (" .. tostring(seed) .. ")")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ O. offline earnings: a read-only session never banks them
do
	local rec0 = city(true, 100)
	rec0.data.savedAt = T - 300 -- away 5 minutes, with 2 minutes of Orders left when they left
	rec0.data.ordersUntil = T - 180
	store:SetAsync("u_" .. AWAY, rec0)
	local plr = join("Away", AWAY)
	h:advance(WAIT)
	local st = stateOf(plr)
	eq(st.saving, false, "O: set-up: read-only (locked elsewhere)")
	local shown = st.credits - 100
	truthy(shown > 0, string.format("O: the offline earnings are shown (+%.1f)", shown))
	h:leave(plr)
	h:advance(1)
	local mid = store:GetAsync("u_" .. AWAY)
	eq(mid.data.credits, 100, "O: but never saved by the read-only session")
	eq(mid.data.savedAt, T - 300, "O: (savedAt untouched, so the absence is still unpaid)")
	mid.lockUntil = 0
	store:SetAsync("u_" .. AWAY, mid)
	local plr2 = join("Away", AWAY)
	h:advance(2)
	local st2 = stateOf(plr2)
	eq(st2.saving, true, "O: the next session saves")
	local paid = st2.credits - 100
	truthy(math.abs(paid - shown) <= st2.income * 3 + 0.01, string.format("O: and pays the same absence once (+%.1f vs +%.1f shown)", paid, shown))
	h:advance(8)
	local rec = store:GetAsync("u_" .. AWAY)
	truthy(rec.data.savedAt >= T and math.abs(rec.data.credits - st2.credits) < st2.income * 9 + 1, "O: credits and savedAt are written together")
	h:leave(plr2)
	h:advance(1)
	local plr3 = join("Away", AWAY)
	h:advance(2)
	local c3 = stateOf(plr3).credits
	truthy(c3 - stateOf(plr2).credits <= stateOf(plr3).income * 4 + 0.01, "O: a third join pays nothing more")
	h:leave(plr3)
	h:advance(1)
end

print("")
local stray = {}
for _, w in h.warnings do
	-- the warnings this file provokes on purpose
	if not (string.find(w, "newer session owns", 1, true) or string.find(w, "load failed", 1, true)
		or string.find(w, "newer version", 1, true) or string.find(w, "seed was invalid", 1, true)) then
		table.insert(stray, w)
	end
end
eq(#stray, 0, "the server warned about nothing else (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero save: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero save check failed", 0) end
