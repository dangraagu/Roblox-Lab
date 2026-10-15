-- Scrapline Tycoon — saving, the session lock, the owner token, and the RECYCLE: the game's one irreversible action.
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_save.luau 2>&1
--
-- The emulator's DataStore does a real JSON round trip, runs UpdateAsync transforms that may be retried, aborts a
-- write when a transform returns nil, and can be made to fail on demand (__failAll). This file drives the real
-- server through the cases docs/complete-game-standard.md §1 and DESIGN.md 9.2 / 11.1 name:
--   A. two sessions on one profile: the second loads the real data READ-ONLY, never writes it, and cannot recycle;
--   B. a late write from a session that no longer owns the record is CANCELLED by the owner token;
--   C. a recycle with the store failing: nothing changes, a toast says so; once the store recovers it works;
--   D. a line one level short of the requirement is refused with the rate in the toast; one upgrade later the
--      recycle wipes and keeps exactly DESIGN 9.2's fields, in ONE write, the grade repaints, the board is written once;
--   E. a store that fails at load: a non-saving session, said out loud, that never writes and never recycles;
--   F. UpdateAsync that runs its transform three times still loads and saves the same profile;
--   G. a lock that clears 2 s after the join: the join waits for it and the session SAVES;
--   H. a recycle whose owner token was taken by another server: refused, the other server's record untouched;
--   I. two Recycle calls at once (a double tap, or a macro): exactly one Gold Bolt;
--   J. a recycle that has to wait for a slow write already in flight: it waits its turn and lands once.
-- robloxemu's os.time() is the wall clock while its task clock is virtual, so these cases move locks by editing the
-- record, never by waiting for os.time() to pass a lockUntil.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("ScraplineTycoon_Board_v1")
local T = os.time()
local IDS = { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" }
-- a line whose rocket rate is set by its twinned Shredder at `shredderL` (every other station far ahead):
-- twinned level 30 ships 2 x 1.25^29 = 1292.5 rockets/s, level 31 1615.5 (DESIGN 9.2: 1500 for the first bolt)
local function line(shredderL)
	local st = {}
	for i, id in IDS do st[id] = { n = 2, L = if i == 1 then shredderL else 40, j = 0 } end
	return st
end
local function profile(shredderL, extra)
	local d = { v = 1, cash = 5e9, stations = line(shredderL), jamIn = 123.5, tier = 6, bolts = 0, boltsAt = 0, tutorial = 4 }
	for k2, v in extra or {} do d[k2] = v end
	return d
end
local LOCKED, TAKEN, FAILREC, SHORT, UNSAVED, RETRY, LOCKCLEAR, STOLEN, DOUBLE, SLOW = 101, 202, 303, 404, 505, 606, 707, 808, 909, 1010
-- (2 Gold Bolts already: a read-only session must not put them on the board either; only the owner's session ranks)
store:SetAsync("u_" .. LOCKED, { session = "someone-else", jobId = "another-server", lockUntil = T + 300, data = profile(34, { bolts = 2, boltsAt = T - 50 }) })
store:SetAsync("u_" .. FAILREC, { data = profile(31) })
store:SetAsync("u_" .. SHORT, { data = profile(30) })
store:SetAsync("u_" .. UNSAVED, { data = profile(31) })
store:SetAsync("u_" .. RETRY, { data = profile(12, { tier = 3 }) })
store:SetAsync("u_" .. LOCKCLEAR, { session = "old-server", jobId = "old-server", lockUntil = T + 300, data = profile(20) })
store:SetAsync("u_" .. STOLEN, { data = profile(31) })
store:SetAsync("u_" .. DOUBLE, { data = profile(31) })
store:SetAsync("u_" .. SLOW, { data = profile(31) })

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local WAIT = Config.Save.LockWaitSeconds + 1
local remotes = h.ReplicatedStorage:FindFirstChild("ScraplineRemotes")
local State, Toast, Buy, Recycle = remotes.State, remotes.Toast, remotes.Buy, remotes.Recycle
local function stateOf(plr)
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function toasts(plr)
	local out = {}
	for _, rec in Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function anyToast(plr, needle)
	for _, t in toasts(plr) do
		if string.find(t, needle, 1, true) then return true end
	end
	return false
end
local function join(name, uid)
	local plr = h:join(name, uid)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.6)
	return plr
end
local function rec(uid) return store:GetAsync("u_" .. uid) end

--============================================================================ A. two sessions on one profile
do
	local before = rec(LOCKED)
	local plr = join("Second", LOCKED)
	h:advance(WAIT) -- the join waits for the lock first (G)
	local st = stateOf(plr)
	truthy(st and st.loaded, "A: the locked profile still loads")
	eq(st and st.saving, false, "A: ...READ-ONLY: this session will not save")
	eq(st and st.stations[1].L, 34, "A: ...with the real saved data (Shredder level 34), not a blank profile")
	truthy(anyToast(plr, Config.Tutorial.NotSavingLocked), "A: and the player is told")
	truthy(st and st.recycleReady, "A: set-up: its line ships enough rockets")
	Recycle:simulateFireServer(plr)
	h:advance(0.5)
	truthy(anyToast(plr, "Recycling needs your save"), "A: a non-saving session is REFUSED a recycle, with the reason")
	eq(stateOf(plr).bolts, 2, "A: and no bolt is added in memory either (a bolt that vanished at the next join would wipe a run for nothing)")
	Buy:simulateFireServer(plr, "up", "shredder")
	h:advance(30)
	h:leave(plr)
	h:advance(1)
	local after = rec(LOCKED)
	eq(after.session, "someone-else", "A: the other session still owns the record")
	eq(after.data.stations.shredder.L, before.data.stations.shredder.L, "A: and its data was never overwritten")
	eq(board:GetAsync("u_" .. LOCKED), nil, "A: and a read-only session never writes the board")
end

--============================================================================ B. the owner token cancels a late write
do
	local plr = join("Taken", TAKEN)
	eq(stateOf(plr).saving, true, "B: a fresh profile loads writable")
	h:advance(8)
	local mine = rec(TAKEN)
	truthy(type(mine.session) == "string" and #mine.session > 0, "B: the load wrote an owner token")
	mine.session = "newer-session"
	mine.jobId = "another-server"
	mine.lockUntil = os.time() + 120
	mine.data = profile(5, { cash = 777 })
	store:SetAsync("u_" .. TAKEN, mine)
	local warns0 = #h.warnings
	Buy:simulateFireServer(plr, "build", "shredder") -- a change, so the next flush writes
	h:advance(Config.Save.AutosaveSeconds + 2 * Config.Save.FlushTickSeconds + 1)
	eq(stateOf(plr).saving, false, "B: the old session notices it lost the record and stops saving")
	truthy(anyToast(plr, "not being saved"), "B: and says so")
	h:leave(plr)
	h:advance(1)
	local after = rec(TAKEN)
	eq(after.session, "newer-session", "B: the late releasing write did not touch the newer session's record")
	eq(after.data.cash, 777, "B: and did not write over its data")
	truthy(after.lockUntil > 0, "B: the lock is still held by the newer session")
	truthy(#h.warnings > warns0, "B: the server logged the takeover")
end

--============================================================================ C. a recycle while the store is failing
do
	local plr = join("Failing", FAILREC)
	local st0 = stateOf(plr)
	truthy(st0.saving and st0.recycleReady, "C: set-up: a saving session with a line ready to recycle")
	local before = rec(FAILREC)
	store.__failAll = true
	Recycle:simulateFireServer(plr)
	h:advance(0.5)
	truthy(anyToast(plr, "The recycle didn't save. Nothing changed"), "C: the failed write is told, in so many words")
	local st = stateOf(plr)
	eq(st.bolts, 0, "C: no bolt")
	eq(st.stations[6].n, 2, "C: the line is untouched (the Rocket Bay still stands)")
	truthy(st.cash > 1e9, "C: and the cash")
	eq(st.recycling, false, "C: and the session is not left stuck in 'recycling'")
	store.__failAll = false
	local mid = rec(FAILREC)
	eq(mid.data.bolts, before.data.bolts, "C: the record is untouched")
	h:advance(1)
	-- REVIEW-2 X3: a try inside RetrySeconds of the failed write is held (no store call), and says so
	local calls0 = store.__calls
	Recycle:simulateFireServer(plr)
	h:advance(0.5)
	eq(stateOf(plr).bolts, 0, "C: a try 1 s after the failed write is held")
	eq(store.__calls - calls0, 0, "C: ...without a store call")
	truthy(anyToast(plr, "try again in"), "C: ...and the toast says when to try again")
	h:advance(Config.Recycle.RetrySeconds)
	Recycle:simulateFireServer(plr)
	h:advance(0.5)
	eq(stateOf(plr).bolts, 1, "C: once the store recovers and the hold is over, the recycle goes through")
	eq(rec(FAILREC).data.bolts, 1, "C: and the bolt is saved")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ D. the requirement, the wipe and the keep, the grade, the board
do
	local plr = join("Short", SHORT)
	local st = stateOf(plr)
	truthy(st.saving and not st.recycleReady, string.format("D: set-up: a line one level short (%.1f rockets/s against 1500)", st.rocketRate))
	local writes0 = board.__calls
	Recycle:simulateFireServer(plr)
	h:advance(0.3)
	local t = toasts(plr)
	eq(t[#t], "Ship 1.5K rockets a second to recycle (now 1.2K/s)", "D: refused, and the toast names both rates")
	eq(stateOf(plr).bolts, 0, "D: no bolt")
	-- one Shredder level later
	Buy:simulateFireServer(plr, "up", "shredder")
	h:advance(0.5)
	truthy(stateOf(plr).recycleReady, "D: one upgrade later the line ships enough (" .. string.format("%.1f", stateOf(plr).rocketRate) .. "/s)")
	local jamInBefore = h.game:GetService("ServerStorage").PlotInfo[tostring(SHORT)]:GetAttribute("JamIn")
	local wall = plr.RespawnLocation.Parent.FactoryWall
	local wallBefore = wall.Color
	Recycle:simulateFireServer(plr)
	h:advance(0.5)
	local r = rec(SHORT).data
	eq(r.bolts, 1, "D: +1 Gold Bolt, saved")
	truthy(math.abs(r.boltsAt - os.time()) <= 5, "D: boltsAt is when it was reached")
	eq(r.cash, 0, "D: cash wiped to 0, in the same write")
	eq(r.stations.shredder.n, 1, "D: the Shredder comes back built")
	eq(r.stations.shredder.L, 1, "D: ...at level 1")
	local rest = 0
	for i = 2, 6 do rest += r.stations[IDS[i]].n end
	eq(rest, 0, "D: every other station is gone")
	eq(r.tier, 0, "D: the tier is back to 0")
	truthy(math.abs(r.jamIn - jamInBefore) <= 1, string.format("D: the jam clock is KEPT (%.1f -> %.1f)", jamInBefore, r.jamIn))
	eq(r.tutorial, 4, "D: the tutorial is kept")
	local st2 = stateOf(plr)
	eq(st2.bolts, 1, "D: the HUD sees the bolt")
	eq(st2.mult, 1.5, "D: everything ships for x1.5")
	truthy(wall.Color ~= wallBefore, "D: the factory is repainted")
	h:advance(2)
	local v = board:GetAsync("u_" .. SHORT)
	eq(v, 1 * 2e9 + (2e9 - r.boltsAt), "D: the board holds bolts x 2e9 + (2e9 - boltsAt), written from the saved profile")
	local boardWrites = board.__calls - writes0
	h:advance(70)
	eq(board:GetAsync("u_" .. SHORT), v, "D: and nothing rewrites it while the count stands")
	-- Buy and Fix wait out the recycle sequence
	h:leave(plr)
	h:advance(1)
	print(string.format("  D: board store calls during the recycle: %d", boardWrites))
end

--============================================================================ E. a store that fails at load
do
	store.__failAll = true
	local plr = join("Unsaved", UNSAVED)
	h:advance(Config.Save.LoadRetrySeconds * 3 + 1)
	store.__failAll = false
	local st = stateOf(plr)
	truthy(st and st.loaded, "E: the session still plays")
	eq(st and st.saving, false, "E: ...but does not save")
	truthy(anyToast(plr, "not being saved"), "E: and says so")
	Recycle:simulateFireServer(plr)
	h:advance(0.3)
	truthy(anyToast(plr, "Recycling needs your save"), "E: a recycle is refused")
	local before = rec(UNSAVED)
	h:advance(70)
	h:leave(plr)
	h:advance(1)
	local after = rec(UNSAVED)
	eq(after.data.stations.shredder.L, before.data.stations.shredder.L, "E: nothing was ever written")
	eq(after.session, nil, "E: (not even a lock)")
end

--============================================================================ F. UpdateAsync retries its transform
do
	store.__retryCount = 2
	local plr = join("Retry", RETRY)
	local st = stateOf(plr)
	eq(st and st.stations[1].L, 12, "F: a transform run three times still loads the profile")
	eq(st and st.saving, true, "F: and holds the lock")
	Buy:simulateFireServer(plr, "up", "shredder")
	h:advance(8)
	eq(rec(RETRY).data.stations.shredder.L, 13, "F: and saves it")
	store.__retryCount = 0
	h:leave(plr)
	h:advance(1)
end

--============================================================================ G. a lock that clears soon after the join
do
	local plr = h:join("Patient", LOCKCLEAR)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	local r = rec(LOCKCLEAR)
	r.lockUntil = 0 -- the old server's leave-write lands
	store:SetAsync("u_" .. LOCKCLEAR, r)
	h:advance(WAIT)
	local st = stateOf(plr)
	eq(st and st.saving, true, "G: the join waited for the lock and the session SAVES")
	truthy(anyToast(plr, "Waiting for it"), "G: the player was told it was waiting")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ H. a recycle whose owner token is gone
do
	local plr = join("Stolen", STOLEN)
	h:advance(8)
	local r = rec(STOLEN)
	r.session = "thief-session"
	r.jobId = "another-server"
	r.lockUntil = os.time() + 300
	store:SetAsync("u_" .. STOLEN, r)
	Recycle:simulateFireServer(plr)
	h:advance(0.5)
	eq(stateOf(plr).bolts, 0, "H: a recycle without the owner token mints nothing")
	truthy(anyToast(plr, "didn't save"), "H: and says the recycle did not save")
	eq(rec(STOLEN).data.bolts, 0, "H: the other server's record is untouched")
	eq(rec(STOLEN).session, "thief-session", "H: and still theirs")
	eq(stateOf(plr).saving, false, "H: this session stops saving")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ I. two recycles at once
do
	local plr = join("Double", DOUBLE)
	-- the second call arrives while the first one's write is in flight
	local orig = store.UpdateAsync
	store.UpdateAsync = function(self, k2, fn)
		task.wait(0.4)
		return orig(self, k2, fn)
	end
	Recycle:simulateFireServer(plr)
	h:advance(0.1)
	Recycle:simulateFireServer(plr)
	h:advance(2)
	store.UpdateAsync = orig
	eq(stateOf(plr).bolts, 1, "I: two Recycle calls at once mint exactly ONE bolt")
	eq(rec(DOUBLE).data.bolts, 1, "I: and one is saved")
	truthy(anyToast(plr, "Recycling… one moment"), "I: the second call is told to wait")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ J. a recycle behind a slow write already in flight
do
	local plr = join("Slow", SLOW)
	local orig = store.UpdateAsync
	local inFlight = 0
	store.UpdateAsync = function(self, k2, fn)
		inFlight += 1
		task.wait(1.5)
		local r = orig(self, k2, fn)
		inFlight -= 1
		return r
	end
	Buy:simulateFireServer(plr, "up", "furnace") -- marks the profile for the next flush
	-- wait until the flush's write is in flight, then recycle
	for _ = 1, 100 do
		h:advance(0.1)
		if inFlight > 0 then break end
	end
	truthy(inFlight > 0, "J: set-up: a profile write is in flight")
	Recycle:simulateFireServer(plr)
	h:advance(5)
	store.UpdateAsync = orig
	eq(stateOf(plr).bolts, 1, "J: the recycle waited its turn and landed")
	eq(rec(SLOW).data.bolts, 1, "J: and the record holds the new run (not overwritten by the older write)")
	eq(rec(SLOW).data.stations.rocketbay.n, 0, "J: ...the new run, wiped")
	h:advance(10)
	eq(rec(SLOW).data.bolts, 1, "J: and the next flush keeps it")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ K. a full server: a leaving player's factory is free at once (REVIEW-1 A1)
-- Roblox frees the leaver's player slot at once and runs each PlayerRemoving handler on its own thread, so a new
-- player can arrive while the leave's save is still landing. The joiner must get the factory, not a kick.
do
	local orig = store.UpdateAsync
	local outcomes = {}
	for _, lat in { 0.3, 1, 3 } do
		local ps = {}
		-- the leaver can afford a Furnace: a late Buy from them must not build it on the joiner's plot
		store:SetAsync("u_" .. math.floor(11000 + lat * 100 + 6), { data = { v = 1, cash = 1e6, stations = {}, jamIn = 240, tier = 0,
			bolts = 0, boltsAt = 0, tutorial = 0 } })
		for i = 1, 6 do ps[i] = join("Full" .. lat .. "_" .. i, math.floor(11000 + lat * 100 + i)) end
		h:advance(8)
		local leaver = ps[6]
		local leaverPlot = leaver.RespawnLocation.Parent
		Buy:simulateFireServer(leaver, "build", "shredder")
		h:advance(0.6)
		local leaverId = leaver.UserId
		local cashAtLeave = stateOf(leaver).cash
		store.UpdateAsync = function(self, k2, fn)
			task.wait(lat)
			return orig(self, k2, fn)
		end
		task.spawn(function() h:leave(leaver) end) -- the engine runs PlayerRemoving on its own thread
		h:advance(0.05)
		local nj = h:join("Newcomer" .. lat, math.floor(12000 + lat * 100))
		local kicked = rawget(nj, "__kicked")
		-- a remote from the leaver that arrives while its save is still landing acts on nothing
		Buy:simulateFireServer(leaver, "build", "furnace")
		h:advance(0.05)
		local furnaces = leaverPlot:FindFirstChild("Station_Furnace")
		eq(furnaces and furnaces:FindFirstChild("Machine_Furnace_a"), nil,
			"K: a Buy from the leaver during its leave builds nothing on the plot the joiner now has")
		h.Players:simulateSpawn(nj, h.workspace)
		h:advance(lat * 3 + 2)
		store.UpdateAsync = orig
		table.insert(outcomes, string.format("latency %.1f s: %s", lat, if kicked then "KICKED" else "got a factory"))
		eq(kicked, nil, string.format("K: a joiner 0.05 s after a leave, the store answering in %.1f s, is not kicked", lat))
		eq(nj.RespawnLocation and nj.RespawnLocation.Parent, leaverPlot, "K: ...and gets the factory the leaver left")
		local sNew = stateOf(nj)
		truthy(sNew ~= nil and sNew.loaded and sNew.stations[1].n == 0, "K: ...with their own (fresh) line, not the leaver's")
		local r = rec(leaverId)
		truthy(r ~= nil and r.data.stations.shredder.n == 1 and r.data.cash >= cashAtLeave - 1e-6,
			"K: the leaver's save still landed in full (the Shredder they built, the cash they had)")
		truthy((r and tonumber(r.lockUntil) or 1) == 0, "K: ...and released the lock")
		for _, p in ps do if p ~= leaver then h:leave(p) end end
		h:leave(nj)
		h:advance(2)
	end
	print("  K: " .. table.concat(outcomes, "; "))
end

--============================================================================ L. rejoining THE SAME server while the leave is still saving (REVIEW-1 A3)
-- The lock lets a session on the same JobId through, so a rejoin's load used to take the owner token while the
-- leave's release write was still in flight; that write was then cancelled and the progress since the last flush
-- lost. The first UpdateAsync after the leave (or the recycle) is slow, every later one fast: the worst order.
do
	local orig = store.UpdateAsync
	local function slowFirst(seconds)
		local n = 0
		store.UpdateAsync = function(self, k2, fn)
			n += 1
			task.wait(if n == 1 then seconds else 0.1)
			return orig(self, k2, fn)
		end
	end
	-- 1. no recycle: the leave's write is slow, the rejoin's load is fast
	local UID1 = 1301
	store:SetAsync("u_" .. UID1, { data = profile(31) })
	local p = join("Back", UID1)
	Buy:simulateFireServer(p, "up", "furnace")
	h:advance(8) -- one flush lands
	h:advance(40) -- 40 s of income since that flush, not yet written
	local before = stateOf(p)
	slowFirst(3)
	task.spawn(function() h:leave(p) end)
	h:advance(0.3)
	local p2 = join("Back", UID1)
	h:advance(6)
	store.UpdateAsync = orig
	local r = rec(UID1)
	local lost = before.cash - r.data.cash
	print(string.format("  L1: cash in memory at the leave %.0f, in the record after the rejoin %.0f: lost %.1f s of income",
		before.cash, r.data.cash, lost / before.income))
	truthy(lost <= before.income * 1, "L1: a same-server rejoin during a slow leave-save loses at most 1 s of income")
	local s2 = stateOf(p2)
	truthy(s2 ~= nil and s2.loaded and s2.saving and s2.cash >= before.cash - before.income,
		"L1: the rejoined session loads what the leave saved, and saves")
	eq(s2 and s2.stations[2].L, before.stations[2].L, "L1: ...with the upgrade bought before the leave")
	h:leave(p2)
	h:advance(2)
	-- 2. a recycle in flight at the leave: its write is slow, the rejoin's load fast
	local UID2 = 1302
	store:SetAsync("u_" .. UID2, { data = profile(31) })
	local q = join("Recycler", UID2)
	h:advance(8)
	slowFirst(3)
	task.spawn(function() Recycle:simulateFireServer(q) end)
	h:advance(0.05)
	task.spawn(function() h:leave(q) end)
	h:advance(0.3)
	local q2 = join("Recycler", UID2)
	h:advance(8)
	store.UpdateAsync = orig
	local r2 = rec(UID2)
	eq(r2.data.bolts, 1, "L2: a recycle confirmed just before the leave still lands (the Gold Bolt is kept)")
	eq(r2.data.stations.rocketbay.n, 0, "L2: ...with the wiped run")
	local s3 = stateOf(q2)
	eq(s3 and s3.bolts, 1, "L2: the rejoined session loads the Gold Bolt")
	eq(s3 and s3.saving, true, "L2: ...and saves")
	h:leave(q2)
	h:advance(2)
end

--============================================================================ M. leave, rejoin THE SAME server, leave again while the first leave still saves (REVIEW-2 X1)
-- Every UpdateAsync on this key takes LAT seconds, so writes land in the order they were sent (Roblox's per-key
-- order). The second session leaves while its load still waits for the first leave (REVIEW-1 A3's wait): it must
-- neither take the owner token (that cancelled the first leave's release write) nor drop the first leave's
-- registration (a third join would then not wait for it).
do
	local orig = store.UpdateAsync
	local UID = 1401
	local LAT = 10
	store:SetAsync("u_" .. UID, { data = profile(31) })
	local p = join("Hopper", UID)
	h:advance(8) -- the load and one flush land
	local sent = 0
	store.UpdateAsync = function(self, k2, fn)
		if k2 == "u_" .. UID then
			sent += 1
			task.wait(LAT)
		end
		return orig(self, k2, fn)
	end
	local warn0 = #h.warnings
	Buy:simulateFireServer(p, "up", "shredder") -- pending: the next flush writes Shredder L32
	local n0 = sent
	for _ = 1, 100 do
		h:advance(0.1)
		if sent > n0 then break end
	end
	truthy(sent > n0, "M: set-up: a flush is in flight")
	Buy:simulateFireServer(p, "up", "furnace") -- bought while that flush is in flight: only the leave's write carries it
	h:advance(0.5)
	local want = stateOf(p).stations[2].L
	task.spawn(function() h:leave(p) end) -- leave #1: its release write queues behind the flush
	h:advance(3)
	local p2 = h:join("Hopper", UID) -- back on the same server: its load waits for leave #1
	h.Players:simulateSpawn(p2, h.workspace)
	h:advance(3)
	task.spawn(function() h:leave(p2) end) -- leave #2, while its load still waits
	h:advance(0.5)
	-- a THIRD join while leave #1 is still writing: it must still wait for leave #1 (leave #2 never loaded, so it must
	-- not have replaced or cleared leave #1's registration)
	local p3 = h:join("Hopper", UID)
	h.Players:simulateSpawn(p3, h.workspace)
	h:advance(5 * LAT + 10)
	local r = rec(UID)
	print(string.format("  M: %d UpdateAsync on the key; the record holds Furnace L%d (bought before leave #1: L%d), Shredder L%d",
		sent, r.data.stations.furnace.L, want, r.data.stations.shredder.L))
	eq(r.data.stations.furnace.L, want, "M: the upgrade bought before leave #1 is saved, though two more sessions came meanwhile")
	eq(r.data.stations.shredder.L, 32, "M: ...and so is the one the flush carried")
	local lostOwner = 0
	for i = warn0 + 1, #h.warnings do
		if string.find(h.warnings[i], "Hopper: a newer session owns", 1, true) then lostOwner += 1 end
	end
	eq(lostOwner, 0, "M: no write of leave #1 was cancelled by the owner token")
	local s3 = stateOf(p3)
	eq(s3 and s3.stations[2].L, want, "M: the third join, made while leave #1 still wrote, loads the upgrade")
	eq(s3 and s3.saving, true, "M: ...and saves")
	store.UpdateAsync = orig
	h:leave(p3)
	h:advance(2)
end

print("")
local stray = {}
for _, w in h.warnings do
	-- the warnings these cases provoke on purpose: injected store failures and the takeovers
	if not string.find(w, "injected DataStore failure", 1, true) and not string.find(w, "newer session owns", 1, true)
		and not string.find(w, "load failed", 1, true) then
		table.insert(stray, w)
	end
end
eq(#stray, 0, "no other warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("scraplinetycoon save: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon save check failed", 0) end
