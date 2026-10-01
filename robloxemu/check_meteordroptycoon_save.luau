-- Meteor Drop Tycoon — saving, the session lock, the owner token and the one-time Falling Star.
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon_save.luau 2>&1
--
-- The emulator's DataStore does a real JSON round trip, runs UpdateAsync transforms that may be retried,
-- aborts a write when a transform returns nil, and can be made to fail on demand (__failAll). This file
-- drives the real server through the cases docs/complete-game-standard.md §1 names:
--   A. two sessions on one profile: the second loads the real data READ-ONLY and never writes it;
--   B. a late write from a session that no longer owns the record is CANCELLED by the owner token;
--   C. the Falling Star's grant while the store is failing: no star, a toast, then the star once a write lands;
--   D. a star granted and not caught falls again on rejoin, and catching it writes star = 2 with its payout;
--   E. a store that fails at load: a non-saving session, said out loud, that never writes;
--   F. UpdateAsync that runs its transform three times still loads and saves the same profile;
--   G. a non-saving session (locked elsewhere) reaching the Starfall band: the star falls at once, because a
--      grant that is never written cannot be redeemed twice (steal-a-cryptid's rule), and nothing is written.
-- REVIEW-1 (2026-10-01) added, each written failing first:
--   H. a lock that clears 2 s after the join: the join waits for it (told once) and the session SAVES;
--   I. a lock still held after the join wait: read-only, then the lock lapses and the session takes over;
--   J. ...but if the other server WROTE meanwhile, the session stays unsaved and says rejoin;
--   K. ONE transient failure at load: the retry loads the real profile, writable;
--   L. a Falling Star never outlives its owner's plot (latency injected: the owner leaves mid-load (L1),
--      mid-grant (L2), or before a grant write slower than the leave's wait for it (L3));
--   M. the Collector's sleep survives a rejoin (an auto-rejoin macro cannot re-arm it);
--   N. catching the Falling Star never stalls another player's plot, whatever the write's latency;
--   O. a slow older write never lands over a newer one (writes are serialised per session);
--   P. a change made while a write is in flight is written at the next flush tick.
-- robloxemu's os.time() is the wall clock while its task clock is virtual, so these cases move locks by
-- editing the record, never by waiting for os.time() to pass a lockUntil.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/meteor-drop-tycoon"), name = "meteor-drop-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("MeteorDropTycoon_v1")
local T = os.time()
local LOCKED, TAKEN, STAR, UNSAVED, RETRY, LOCKSTAR = 101, 202, 303, 404, 505, 606

-- A: another live server holds this profile's lock
store:SetAsync("u_" .. LOCKED, { session = "someone-else", jobId = "another-server", lockUntil = T + 100,
	data = { v = 1, stardust = 500, lifetime = 900, beacon = 9, beaconAt = T - 50, collector = 1, smelter = 3, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })
-- C/D: one Beacon level from the Falling Star, with the Stardust to buy it (price of 21 -> 22 is 1 538)
store:SetAsync("u_" .. STAR, { data = { v = 1, stardust = 1600, lifetime = 50000, beacon = 21, beaconAt = T - 500,
	collector = 5, smelter = 15, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })
-- E: a Beacon-21 profile that will be loaded while the store is down
store:SetAsync("u_" .. UNSAVED, { data = { v = 1, stardust = 1600, lifetime = 50000, beacon = 21, beaconAt = T - 500,
	collector = 0, smelter = 15, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })

-- G: Beacon 21, enough Stardust for 22, and locked by another live server
store:SetAsync("u_" .. LOCKSTAR, { session = "someone-else", jobId = "another-server", lockUntil = T + 300,
	data = { v = 1, stardust = 1600, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 0, smelter = 15, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
-- a join that finds the record locked waits LockWaitSeconds (re-reading it) before it plays read-only
local WAIT = (Config.Save.LockWaitSeconds or 0) + 1
local remotes = h.ReplicatedStorage:FindFirstChild("MeteorRemotes")
local State, Toast, Buy, FxR, Announce = remotes.State, remotes.Toast, remotes.Buy, remotes.Fx, remotes.Announce
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
	local char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.3)
	return plr, char:FindFirstChild("HumanoidRootPart")
end
-- The Falling Star lands 4 studs in front of the arrival pad, inside a player's 5-stud pickup radius if they
-- are still standing on the pad; these cases move the player to the far side of the plot first, so the
-- star is caught only when the case walks to it.
local function farSide(plr, hrp)
	local plot = plr.RespawnLocation.Parent
	local centre = plot.Smelter.SmelterBody.Position
	local pad = plr.RespawnLocation.Position
	local out = Vector3.new(centre.X - pad.X, 0, centre.Z - pad.Z).Unit
	hrp.CFrame = CFrame.new(centre.X + out.X * 25, 3.5, centre.Z + out.Z * 25)
end
local function starPart(plr)
	local plot = plr.RespawnLocation.Parent
	local m = plot:FindFirstChild("Meteors")
	return m:FindFirstChild("Incoming_Star") or m:FindFirstChild("FallingStar")
end

--============================================================================ A. two sessions on one profile
do
	local before = store:GetAsync("u_" .. LOCKED)
	local plr = join("Second", LOCKED)
	h:advance(WAIT) -- the join waits for the lock first (H)
	local st = stateOf(plr)
	truthy(st and st.loaded, "A: the locked profile still loads")
	eq(st and st.saving, false, "A: ...READ-ONLY: this session will not save")
	eq(st and st.beacon, 9, "A: ...with the real saved data (Beacon 9), not a blank profile")
	truthy(anyToast(plr, Config.Tutorial.NotSavingLocked), "A: and the player is told, with what happens next")
	-- earn and spend for a while; nothing may reach the store
	Buy:simulateFireServer(plr, "beacon")
	h:advance(30)
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. LOCKED)
	eq(after.session, "someone-else", "A: the other session still owns the record")
	eq(after.data.beacon, before.data.beacon, "A: and its data was never overwritten (Beacon stays 9)")
	eq(after.data.stardust, before.data.stardust, "A: (Stardust too)")
	local board = h.services.DataStoreService:GetOrderedDataStore("MeteorDropTycoon_Board_v1")
	eq(board:GetAsync("u_" .. LOCKED), nil, "A: and a read-only session never writes the Star Chart (it ranks only what was saved)")
end

--============================================================================ B. the owner token cancels a late write
do
	local plr = join("Taken", TAKEN)
	local st = stateOf(plr)
	eq(st and st.saving, true, "B: a fresh profile loads writable")
	h:advance(8) -- one flush tick: the record now carries this session's token
	local mine = store:GetAsync("u_" .. TAKEN)
	truthy(type(mine.session) == "string" and #mine.session > 0, "B: the load wrote an owner token")
	-- another server takes the record (its load wrote its own token)
	mine.session = "newer-session"
	mine.jobId = "another-server"
	mine.lockUntil = os.time() + 120
	mine.data = { v = 1, stardust = 777, lifetime = 777, beacon = 3, beaconAt = T, collector = 0, smelter = 0, hopper = 0, star = 0, starCores = 0, tutorial = 3 }
	store:SetAsync("u_" .. TAKEN, mine)
	local warns0 = #h.warnings
	-- this session keeps playing: its next write (the 60 s autosave at the latest), and its releasing write on
	-- leaving, must both be cancelled. The window covers the autosave whatever the draw: if a pickup made the
	-- session write just before the takeover (8 s in), its autosave is due 60 s after that write and runs at the
	-- next 7 s flush tick. (It was 62 s, which a pickup on the pad could outrun: REVIEW-1's sweep caught it once.)
	h:advance(Config.Save.AutosaveSeconds + 2 * Config.Save.FlushTickSeconds + 1)
	eq(stateOf(plr).saving, false, "B: the old session notices it lost the record and stops saving")
	truthy(anyToast(plr, "not being saved"), "B: and says so")
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. TAKEN)
	eq(after.session, "newer-session", "B: the late releasing write did not re-release the newer session's record")
	eq(after.data.stardust, 777, "B: and did not write over its data")
	truthy(after.lockUntil > 0, "B: the lock is still held by the newer session")
	truthy(#h.warnings > warns0, "B: the server logged the takeover")
end

--============================================================================ C. the Falling Star while the store is failing
local plrS, hrpS = join("Stargazer", STAR)
do
	local st = stateOf(plrS)
	eq(st and st.beacon, 21, "C: set-up: Beacon 21")
	eq(st and st.star, 0, "C: set-up: no star yet")
	farSide(plrS, hrpS)
	store.__failAll = true
	Buy:simulateFireServer(plrS, "beacon")
	h:advance(0.5)
	eq(stateOf(plrS).beacon, 22, "C: the purchase itself goes through (Beacon 22, the Starfall band)")
	eq(starPart(plrS), nil, "C: but no star falls while its grant cannot be written")
	eq(stateOf(plrS).star, 0, "C: the grant is not recorded in memory either")
	truthy(anyToast(plrS, "Falling Star is waiting"), "C: and the player is told it is waiting")
	h:advance(10) -- a flush tick with the store still down: still nothing
	eq(starPart(plrS), nil, "C: still nothing after a failed retry")
	store.__failAll = false
	h:advance(8) -- the next flush tick writes the grant
	local rec = store:GetAsync("u_" .. STAR)
	eq(rec.data.star, 1, "C: once the store recovers, the grant is written (star = 1) with the rest of the profile")
	eq(rec.data.beacon, 22, "C: in the same write as Beacon 22")
	truthy(starPart(plrS) ~= nil, "C: and only then does the star fall")
	eq(stateOf(plrS).star, 1, "C: the HUD sees it granted, not caught")
end

--============================================================================ D. not caught: it falls again on rejoin; caught: star = 2
do
	h:leave(plrS)
	h:advance(1)
	eq(store:GetAsync("u_" .. STAR).data.star, 1, "D: leaving with the star uncaught keeps star = 1")
	plrS, hrpS = join("Stargazer", STAR)
	farSide(plrS, hrpS)
	h:advance(0.5)
	local sp = starPart(plrS)
	truthy(sp ~= nil, "D: on rejoin the star falls again (its payout was never saved, so it is not a duplicate)")
	h:advance(5) -- StarFallSeconds = 4
	sp = starPart(plrS)
	eq(sp and sp.Name, "FallingStar", "D: it lands as the FallingStar")
	local dust0 = stateOf(plrS).stardust
	local ann0 = #Announce:getSent()
	if sp then
		-- walk to it
		for _ = 1, 100 do
			local p, q = hrpS.Position, sp.Position
			local dx, dz = q.X - p.X, q.Z - p.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if sp.Parent == nil or d < 0.5 then break end
			local step = math.min(d, 1.6)
			hrpS.CFrame = CFrame.new(p.X + dx / d * step, p.Y, p.Z + dz / d * step)
			h:advance(0.1)
		end
		h:advance(0.3)
	end
	local st = stateOf(plrS)
	eq(sp and sp.Parent, nil, "D: walking to the star catches it")
	eq(st.star, 2, "D: star = 2")
	-- a legendary at Beacon 22: 1.14^22 x 100 = 1 786 ore, paid at once (not through the hopper)
	truthy(st.stardust - dust0 >= 1786 - 1, string.format("D: it pays its 1 786 Stardust at once (+%.1f)", st.stardust - dust0))
	eq(store:GetAsync("u_" .. STAR).data.star, 2, "D: the catch is written at once, with the Stardust it paid")
	truthy(#Announce:getSent() > ann0, "D: the whole server is told")
	local crown = plrS.RespawnLocation.Parent.Beacon:FindFirstChild("Crown")
	truthy(crown ~= nil, "D: and the Beacon wears the gold crown")
	h:leave(plrS)
	h:advance(1)
	plrS = join("Stargazer", STAR)
	h:advance(6)
	eq(starPart(plrS), nil, "D: a caught star never falls again")
end

--============================================================================ E. the store fails at load, through every retry
do
	store.__failAll = true
	local plr = join("Offline", UNSAVED)
	h:advance(6) -- LoadAttempts (3) tries, 1 s then 2 s apart: every one fails
	store.__failAll = false
	local st = stateOf(plr)
	truthy(st and st.loaded, "E: the session still starts")
	eq(st and st.saving, false, "E: as a NON-saving session (it never switches to saving mid-session)")
	truthy(anyToast(plr, "not being saved"), "E: and says so")
	-- it plays from a fresh profile in memory; nothing reaches the record
	local before = store:GetAsync("u_" .. UNSAVED)
	h:advance(20)
	local after = store:GetAsync("u_" .. UNSAVED)
	eq(after.data.stardust, before.data.stardust, "E: the saved profile is untouched")
	eq(stateOf(plr).saving, false, "E: still not saving after the store recovers")
	h:leave(plr)
	h:advance(1)
end

--============================================================================ F. retried transforms
do
	store.__retryCount = 2 -- every UpdateAsync runs its transform three times
	local plr = join("Retry", RETRY)
	h:advance(1)
	eq(stateOf(plr).saving, true, "F: a retried load still takes the lock exactly once")
	h:advance(30)
	h:leave(plr)
	h:advance(1)
	local rec = store:GetAsync("u_" .. RETRY)
	eq(rec.lockUntil, 0, "F: and a retried release still releases")
	truthy(rec.data and rec.data.v == 1, "F: with the profile written")
	store.__retryCount = 0
	local numeric = 0
	for k in rec.data do if type(k) ~= "string" then numeric += 1 end end
	eq(numeric, 0, "F: no integer keys in a saved profile, after the JSON round trip")
end

--============================================================================ G. the star in a non-saving session
do
	local plr, hrp = join("ReadOnly", LOCKSTAR)
	farSide(plr, hrp)
	h:advance(WAIT)
	eq(stateOf(plr).saving, false, "G: set-up: a read-only session")
	Buy:simulateFireServer(plr, "beacon")
	h:advance(0.5)
	eq(stateOf(plr).beacon, 22, "G: Beacon 22")
	truthy(starPart(plr) ~= nil, "G: the star falls at once: an unsaved grant can never be redeemed twice")
	eq(stateOf(plr).star, 1, "G: granted in memory")
	h:leave(plr)
	h:advance(1)
	local rec = store:GetAsync("u_" .. LOCKSTAR)
	eq(rec.data.star, 0, "G: and nothing reached the record")
	eq(rec.data.beacon, 21, "G: (still Beacon 21 there)")
end

--============================================================================ REVIEW-1 cases
local LATE, HELD, CHANGED, BLIP, OWNER1, OWNER2, STRANGER, AFK, CATCH, BYST = 707, 708, 709, 710, 711, 712, 713, 714, 715, 716
local NOT_YET = "\0never-matches\0" -- a toast this build does not have yet must FAIL the check, not error it
local function nine(locked: boolean)
	return { session = if locked then "someone-else" else nil, jobId = if locked then "another-server" else nil,
		lockUntil = if locked then os.time() + 300 else 0,
		data = { v = 1, stardust = 500, lifetime = 900, beacon = 9, beaconAt = T - 50, collector = 1, smelter = 3, hopper = 0,
			star = 0, starCores = 0, tutorial = 3 } }
end
local function walkTo(hrp, part, maxSteps)
	for _ = 1, maxSteps do
		if part.Parent == nil then return end
		local p, q = hrp.Position, part.Position
		local dx, dz = q.X - p.X, q.Z - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 0.5 then return end
		local step = math.min(d, 1.6)
		hrp.CFrame = CFrame.new(p.X + dx / d * step, p.Y, p.Z + dz / d * step)
		h:advance(0.1)
	end
end

--============================================================================ H. a lock that clears seconds after the join
do
	local rec0 = nine(true)
	rec0.session, rec0.jobId, rec0.lockUntil = "old-session", "old-server", os.time() + 110
	store:SetAsync("u_" .. LATE, rec0)
	local plr = join("Late", LATE)
	local st = stateOf(plr)
	eq(st and st.loaded, false, "H: the join finds the record locked and WAITS for it (not loaded yet)")
	truthy(anyToast(plr, Config.Tutorial.LockWaiting or NOT_YET), "H: and says it is waiting")
	h:advance(2)
	local rec = store:GetAsync("u_" .. LATE)
	rec.lockUntil = 0 -- the old server's leave-write lands, 2 s late
	store:SetAsync("u_" .. LATE, rec)
	h:advance(Config.Save.LockRetrySeconds or 5)
	st = stateOf(plr)
	eq(st and st.loaded, true, "H: the next read finds it free and loads")
	eq(st and st.saving, true, "H: ...WRITABLE: this session saves (REVIEW-1: it used to play 600 s unsaved)")
	eq(st and st.beacon, 9, "H: with the real saved data")
	Buy:simulateFireServer(plr, "beacon")
	h:advance(8)
	rec = store:GetAsync("u_" .. LATE)
	eq(rec.data.beacon, 10, "H: a purchase reaches the store")
	truthy(rec.session ~= "old-session", "H: under this session's own token")
	h:leave(plr)
	h:advance(1)
	eq(store:GetAsync("u_" .. LATE).lockUntil, 0, "H: and leaving releases it")
end

--============================================================================ I. still locked after the wait: read-only, then it takes over
do
	store:SetAsync("u_" .. HELD, nine(true))
	local plr = join("Held", HELD)
	h:advance(WAIT)
	local st = stateOf(plr)
	eq(st and st.loaded, true, "I: after the join wait the session plays")
	eq(st and st.saving, false, "I: read-only while the other server holds the lock")
	Buy:simulateFireServer(plr, "beacon")
	h:advance(0.5)
	eq(stateOf(plr).beacon, 10, "I: set-up: a purchase in memory")
	local rec = store:GetAsync("u_" .. HELD)
	rec.lockUntil = 0 -- the other server lets go with its data unchanged (its leave-write was late, or it crashed)
	store:SetAsync("u_" .. HELD, rec)
	h:advance((Config.Save.LockRecheckSeconds or 15) + 1)
	st = stateOf(plr)
	eq(st.saving, true, "I: the session re-checks, finds the lock free and the data as it read it, and takes over")
	truthy(anyToast(plr, Config.Tutorial.LockTaken or NOT_YET), "I: and says so")
	h:advance(8)
	rec = store:GetAsync("u_" .. HELD)
	eq(rec.data.beacon, 10, "I: the purchase made while read-only is saved")
	truthy(rec.session ~= "someone-else" and (rec.lockUntil or 0) > 0, "I: under this session's own lock")
	h:leave(plr)
	h:advance(1)
	eq(store:GetAsync("u_" .. HELD).lockUntil, 0, "I: released on leaving")
end

--============================================================================ J. the other server wrote meanwhile: never overwrite it
do
	store:SetAsync("u_" .. CHANGED, nine(true))
	local plr = join("Changed", CHANGED)
	h:advance(WAIT)
	eq(stateOf(plr).saving, false, "J: set-up: read-only")
	local rec = store:GetAsync("u_" .. CHANGED)
	rec.data.beacon = 11
	rec.data.stardust = 4321
	rec.lockUntil = 0 -- the other server saved new progress, then let go
	store:SetAsync("u_" .. CHANGED, rec)
	h:advance((Config.Save.LockRecheckSeconds or 15) + 1)
	eq(stateOf(plr).saving, false, "J: data that changed since this session read it is never overwritten: still not saving")
	truthy(anyToast(plr, Config.Tutorial.LockChanged or NOT_YET), "J: and the player is told to rejoin")
	Buy:simulateFireServer(plr, "beacon")
	h:advance(70)
	h:leave(plr)
	h:advance(1)
	local after = store:GetAsync("u_" .. CHANGED)
	eq(after.data.beacon, 11, "J: the other server's Beacon 11 stands")
	eq(after.data.stardust, 4321, "J: (and its Stardust)")
end

--============================================================================ K. one transient failure at load
do
	store:SetAsync("u_" .. BLIP, { data = { v = 1, stardust = 1500, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 5, smelter = 15, hopper = 0, star = 2, starCores = 1, tutorial = 3 } })
	store.__failNext = true -- the load's own UpdateAsync is the next call (PlayerAdded spawns it at once)
	local plr = join("Blip", BLIP)
	h:advance(3)
	local st = stateOf(plr)
	eq(st and st.saving, true, "K: one failed read at the join is retried and the session saves (REVIEW-1: it used to be final)")
	eq(st and st.beacon, 21, "K: with the real profile (Beacon 21), not a blank one")
	eq(st and st.collector, 5, "K: (Collector 5)")
	h:leave(plr)
	h:advance(1)
	eq(store:GetAsync("u_" .. BLIP).data.beacon, 21, "K: and the record is intact")
end

--============================================================================ L. a Falling Star never outlives its owner's plot
local board = h.services.DataStoreService:GetOrderedDataStore("MeteorDropTycoon_Board_v1")
local function strangerGetsNothing(tag, plot)
	local ann0 = #Announce:getSent()
	local plr = join("Stranger", STRANGER)
	eq(plr.RespawnLocation.Parent, plot, tag .. ": set-up: the next player claims the freed plot")
	h:advance(8) -- standing on the pad, 4 studs from where a star would lie
	local st = stateOf(plr)
	eq(st.starCores, 0, tag .. ": the stranger is paid no Falling Star")
	truthy(st.stardust < 100, string.format(tag .. ": (Stardust %.0f)", st.stardust))
	local stray = false
	for i = ann0 + 1, #Announce:getSent() do
		if string.find(tostring(Announce:getSent()[i].args[1].text), "Stranger", 1, true) then stray = true end
	end
	eq(stray, false, tag .. ": and nobody is told the stranger caught one")
	h:leave(plr)
	h:advance(1)
	store:RemoveAsync("u_" .. STRANGER)
end
do
	-- L1, the join path: the owner leaves while afterLoad waits on its board read
	store:SetAsync("u_" .. OWNER1, { data = { v = 1, stardust = 0, lifetime = 9e6, beacon = 40, beaconAt = T - 500,
		collector = 8, smelter = 40, hopper = 0, star = 1, starCores = 0, tutorial = 3 } })
	local origU, origG = store.UpdateAsync, board.GetAsync
	store.UpdateAsync = function(self, k, f) task.wait(0.3); return origU(self, k, f) end
	board.GetAsync = function(self, k) task.wait(1.5); return origG(self, k) end
	local plr = h:join("Owner", OWNER1)
	h.Players:simulateSpawn(plr, h.workspace)
	local plot = plr.RespawnLocation.Parent
	h:advance(0.6) -- the load landed; afterLoad is inside its board GetAsync
	task.spawn(function() h:leave(plr) end)
	h:advance(4)
	store.UpdateAsync, board.GetAsync = origU, origG
	local m = plot:FindFirstChild("Meteors")
	eq(m:FindFirstChild("Incoming_Star") or m:FindFirstChild("FallingStar"), nil,
		"L1: no star is left on the plot its owner left during the load (REVIEW-1: a stranger was paid 18 888)")
	eq(store:GetAsync("u_" .. OWNER1).data.star, 1, "L1: the owner keeps their uncaught star for their next join")
	strangerGetsNothing("L1", plot)
end
do
	-- L2, the grant path: the owner leaves while the grant's write is in flight
	store:SetAsync("u_" .. OWNER2, { data = { v = 1, stardust = 1600, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 0, smelter = 15, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })
	local plr, hrp = join("Granted", OWNER2)
	h:advance(1)
	local plot = plr.RespawnLocation.Parent
	farSide(plr, hrp)
	local origU = store.UpdateAsync
	store.UpdateAsync = function(self, k, f) task.wait(1.0); return origU(self, k, f) end
	task.spawn(function() Buy:simulateFireServer(plr, "beacon") end) -- Roblox runs each OnServerEvent in its own thread
	h:advance(0.2)
	task.spawn(function() h:leave(plr) end)
	h:advance(5)
	store.UpdateAsync = origU
	local m = plot:FindFirstChild("Meteors")
	eq(m:FindFirstChild("Incoming_Star") or m:FindFirstChild("FallingStar"), nil, "L2: no star on the plot its owner left mid-grant")
	local rec = store:GetAsync("u_" .. OWNER2)
	eq(rec.lockUntil, 0, "L2: the record is released after the grant's write, never re-locked by it")
	truthy(rec.data.star == 0 or rec.data.star == 1, "L2: and the grant is either saved uncaught or not at all (star " .. tostring(rec.data.star) .. ")")
	strangerGetsNothing("L2", plot)
end

do
	-- L3: the grant's write outlasts the leave's wait for it (WriteQueueSeconds), so the plot is freed BEFORE the
	-- write lands and the grant continues: only spawnStar's own ownership check stands between the star and the
	-- plot's next owner (L1 and L2 are also covered by afterLoad's re-check and by freeing after the release)
	local OWNER3 = 719
	store:SetAsync("u_" .. OWNER3, { data = { v = 1, stardust = 1600, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 0, smelter = 15, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })
	local plr, hrp = join("Slowgrant", OWNER3)
	h:advance(1)
	local plot = plr.RespawnLocation.Parent
	farSide(plr, hrp)
	local origU = store.UpdateAsync
	local slowDone = false
	store.UpdateAsync = function(self, k, f)
		if k == "u_" .. OWNER3 and not slowDone then
			slowDone = true
			task.wait(Config.Save.WriteQueueSeconds + 5)
		end
		return origU(self, k, f)
	end
	task.spawn(function() Buy:simulateFireServer(plr, "beacon") end)
	h:advance(0.5)
	task.spawn(function() h:leave(plr) end)
	h:advance(Config.Save.WriteQueueSeconds + 8)
	store.UpdateAsync = origU
	local m = plot:FindFirstChild("Meteors")
	eq(m:FindFirstChild("Incoming_Star") or m:FindFirstChild("FallingStar"), nil,
		"L3: a grant that lands after its owner's plot was freed spawns nothing there")
	eq(store:GetAsync("u_" .. OWNER3).lockUntil, 0, "L3: and its late write does not lock the record again")
end

--============================================================================ M. the Collector's sleep survives a rejoin
local function dishCatches(plr)
	local n = 0
	for _, rec in FxR:sentTo(plr) do
		if type(rec.args[1]) == "table" and rec.args[1].kind == "dish" then n += 1 end
	end
	return n
end
local function standAside(plr, hrp)
	-- 40 studs out from the plot centre, away from the observatory: past the landing ring (r <= 32) by more than
	-- the 5-stud pickup radius, so no meteor can land within reach and nothing is ever picked up by hand
	local plot = plr.RespawnLocation.Parent
	local c = plot.Smelter.SmelterBody.Position
	local p = plr.RespawnLocation.Position
	local to = Vector3.new(p.X - c.X, 0, p.Z - c.Z).Unit
	hrp.CFrame = CFrame.new(c.X - to.X * 40, 3.5, c.Z - to.Z * 40)
end
do
	store:SetAsync("u_" .. AFK, { data = { v = 1, stardust = 0, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 5, smelter = 15, hopper = 0, star = 2, starCores = 1, tutorial = 3 } })
	local plr, hrp = join("Afk", AFK)
	standAside(plr, hrp)
	h:advance(Config.Collector.IdleSeconds + 15) -- no hand pickup for over 10 minutes
	eq(stateOf(plr).awake, 0, "M: set-up: the Collector fell asleep")
	h:leave(plr)
	h:advance(1)
	plr, hrp = join("Afk", AFK)
	standAside(plr, hrp)
	h:advance(1)
	eq(stateOf(plr).awake, 0, "M: a rejoin with no hand pickup does not wake it (REVIEW-1: it re-armed for 599 s)")
	local d0 = dishCatches(plr)
	h:advance(120)
	eq(dishCatches(plr) - d0, 0, "M: and it catches nothing in the next 2 minutes")
	h:leave(plr)
	h:advance(1)
	-- a brand-new player still starts awake: the first Collector they buy works at once
	local fresh = join("Newcomer", AFK + 1000)
	h:advance(1)
	local until_ = h.game:GetService("ServerStorage").PlotInfo:FindFirstChild(tostring(AFK + 1000)):GetAttribute("CollectorAwakeUntil")
	truthy(until_ - h.scheduler:now() > Config.Collector.IdleSeconds - 5,
		string.format("M: a brand-new player still starts awake (%.0f s left)", until_ - h.scheduler:now()))
	h:leave(fresh)
	h:advance(1)
end

--============================================================================ N. the catch never stalls anyone else's plot
do
	store:SetAsync("u_" .. CATCH, { data = { v = 1, stardust = 1600, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 0, smelter = 15, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })
	store:SetAsync("u_" .. BYST, { data = { v = 1, stardust = 0, lifetime = 50000, beacon = 21, beaconAt = T - 500,
		collector = 0, smelter = 15, hopper = 300, star = 2, starCores = 1, tutorial = 3 } })
	local pa, hrpA = join("Catcher", CATCH)
	local pb, hrpB = join("Bystander", BYST)
	h:advance(1)
	farSide(pa, hrpA)
	h:advance(1)
	local LAT = 3
	local origU = store.UpdateAsync
	store.UpdateAsync = function(self, k, f) task.wait(LAT); return origU(self, k, f) end
	task.spawn(function() Buy:simulateFireServer(pa, "beacon") end)
	h:advance(LAT + 5.5) -- the grant's write lands and the star falls (4 s)
	local star = starPart(pa)
	truthy(star ~= nil and star.Name == "FallingStar", "N: set-up: the star has landed")
	local info = h.game:GetService("ServerStorage").PlotInfo:FindFirstChild(tostring(BYST))
	local base = hrpB.Position
	local dir, last, frozen, longest = 1, nil, 0, 0
	for _ = 1, 150 do
		local p = hrpB.Position
		if math.abs(p.X - base.X) > 10 then dir = -dir end
		hrpB.CFrame = CFrame.new(p.X + dir * 1.2, p.Y, p.Z) -- the bystander walks every tick
		if star and star.Parent ~= nil then
			local a, q = hrpA.Position, star.Position
			local dx, dz = q.X - a.X, q.Z - a.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0.5 then hrpA.CFrame = CFrame.new(a.X + dx / d * math.min(d, 1.6), a.Y, a.Z + dz / d * math.min(d, 1.6)) end
		end
		h:advance(0.1)
		local x = info:GetAttribute("TrustedX")
		if x == last then frozen += 0.1 else frozen = 0 end
		longest = math.max(longest, frozen)
		last = x
	end
	store.UpdateAsync = origU
	eq(stateOf(pa).star, 2, "N: set-up: the star was caught")
	print(string.format("  N: with %d s per profile write, the bystander's plot stood still for at most %.1f s", LAT, longest))
	truthy(longest <= 0.25, string.format("N: the catch's write never stalls another player's plot (froze %.1f s; REVIEW-1: 3.0 s)", longest))
	h:advance(10)
	eq(store:GetAsync("u_" .. CATCH).data.star, 2, "N: and the catch is still written, star = 2")
	h:leave(pa)
	h:leave(pb)
	h:advance(1)
end

--============================================================================ O/P. writes are serialised; a change made during one is not lost
-- The catch now writes from its own thread, so two writes of one session can overlap. A write packs the profile
-- before it yields: without serialising, a slow older write landing after a fast newer one put old data back.
local SLOW1, SLOW2 = 717, 718
local function slowFirstWrite(uid)
	-- the next UpdateAsync on this key takes 3 s, every later one 0.3 s; returns a probe of when the slow one is in flight
	local origU = store.UpdateAsync
	local probe = { started = false, landed = false }
	store.UpdateAsync = function(self, k, f)
		if k == "u_" .. uid and not probe.started then
			probe.started = true
			task.wait(3)
			local r = origU(self, k, f)
			probe.landed = true
			return r
		end
		if k == "u_" .. uid then task.wait(0.3) end
		return origU(self, k, f)
	end
	return probe, function() store.UpdateAsync = origU end
end
do
	-- O: a slow flush is in flight; the player buys again and leaves (a fast release write)
	store:SetAsync("u_" .. SLOW1, nine(false))
	local plr = join("Slow", SLOW1)
	h:advance(1)
	eq(stateOf(plr).saving, true, "O: set-up: writable")
	local probe, restore = slowFirstWrite(SLOW1)
	Buy:simulateFireServer(plr, "beacon") -- Beacon 10: pending; the next flush tick writes it, slowly
	for _ = 1, 100 do
		if probe.started then break end
		h:advance(0.1)
	end
	truthy(probe.started and not probe.landed, "O: set-up: the flush carrying Beacon 10 is in flight")
	Buy:simulateFireServer(plr, "beacon") -- Beacon 11, in memory
	eq(stateOf(plr).beacon, 11, "O: set-up: Beacon 11 in memory")
	task.spawn(function() h:leave(plr) end)
	h:advance(6)
	restore()
	local rec = store:GetAsync("u_" .. SLOW1)
	eq(rec.data.beacon, 11, "O: the slow older write never lands over the newer one (the record ends at Beacon 11)")
	eq(rec.lockUntil, 0, "O: and the record is released")
end
do
	-- P: a purchase made while a write is in flight reaches the store at the next flush tick, not the autosave
	store:SetAsync("u_" .. SLOW2, nine(false))
	local plr = join("Slow2", SLOW2)
	h:advance(1)
	local probe, restore = slowFirstWrite(SLOW2)
	Buy:simulateFireServer(plr, "beacon") -- Beacon 10
	for _ = 1, 100 do
		if probe.started then break end
		h:advance(0.1)
	end
	Buy:simulateFireServer(plr, "beacon") -- Beacon 11 while Beacon 10's write is in flight
	h:advance(3.5)
	truthy(probe.landed, "P: set-up: the slow write has landed")
	eq(store:GetAsync("u_" .. SLOW2).data.beacon, 10, "P: set-up: it carried Beacon 10")
	h:advance(Config.Save.FlushTickSeconds + 1)
	restore()
	eq(store:GetAsync("u_" .. SLOW2).data.beacon, 11,
		"P: Beacon 11, bought during that write, is written at the next flush tick (not left for the 60 s autosave)")
	h:leave(plr)
	h:advance(1)
end

-- the only warnings allowed are the ones this file provoked: failures (C, E, K) and the takeover (B)
local unexpected = {}
for _, w in h.warnings do
	if not (string.find(w, "save failed", 1, true) or string.find(w, "load failed", 1, true) or string.find(w, "newer session", 1, true)) then
		table.insert(unexpected, w)
	end
end
eq(#unexpected, 0, "no warning this file did not provoke (" .. table.concat(unexpected, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("meteordroptycoon save: %d passed, %d failed", passed, failed))
if failed > 0 then error("meteordroptycoon save check failed", 0) end
