-- Deep Vein — A SESSION LOCK IS NOT LEAKED, AND A LOCKED LOAD IS RETRIED. Second review 2026-10-09, MEDIUM.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_lockleak.luau
--
-- Two holes in the session lock, both of which cost an honest player a whole session of progress:
--   A. A player who LEFT WHILE THEIR PROFILE WAS LOADING left the lock that load had just taken in the record for
--      SessionLockSeconds. Nothing released it: PlayerRemoving had run before the profile existed. A rejoin on
--      another server inside that window was read-only for its whole life.
--   B. A load that found the record locked (an ordinary server hop: the old server's final save lands a moment
--      after the new server's load), or that simply failed, was never tried again. One unlucky second, one
--      unsaved session.
-- The load now retries a few times (Config.Save.LoadRetries x LoadRetrySeconds) before it settles for read-only,
-- and a load that finishes for a player who has already gone gives its lock straight back.
--
-- The emulated DataStore never yields, so "left during the load" is staged where it really happens: the test
-- wraps this store's UpdateAsync and removes the player the moment the load's own call returns.

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
local RETRIES = Config.Save.LoadRetries or 3
local RETRY_S = Config.Save.LoadRetrySeconds or 2
local WINDOW = RETRIES * RETRY_S
local LEAVER, HOPPER, FLAKY, CRASHED, CALM, WAITLEAVER = 8181, 8282, 8383, 8484, 8585, 8686
local function base(extra)
	local d = { cash = 100, totalCash = 100, inventory = {}, pickTier = 1, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depthLayer = 0, bestLayer = 0, runEarned = 100 }
	for k, v in extra or {} do d[k] = v end
	return d
end
local function lockedByOther(uid, extra)
	store:SetAsync("u_" .. uid, { data = base(extra), jobId = "OTHER-SERVER", session = "OTHER-SESSION",
		lockUntil = os.time() + 3600 })
end
local function rec(uid) return store:GetAsync("u_" .. uid) end
local function locked(uid)
	local r = rec(uid)
	return r ~= nil and (tonumber(r.lockUntil) or 0) > os.time()
end

store:SetAsync("u_" .. LEAVER, { data = base() })
lockedByOther(HOPPER)
store:SetAsync("u_" .. FLAKY, { data = base({ cash = 321, runEarned = 321 }) })
lockedByOther(CRASHED, { cash = 555, runEarned = 555 })
store:SetAsync("u_" .. CALM, { data = base() })
lockedByOther(WAITLEAVER)

assert(h:tryRun("server/Main.server"))
h:advance(1)

local remotes = h.services.ReplicatedStorage:FindFirstChild("VeinRemotes")
local StateEvent = remotes:FindFirstChild("State")
local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	local r = sent[#sent]
	return r and r.args[1] or nil
end
local function hasShaft(uid)
	for _, f in h.workspace.Shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. uid, true) ~= nil then return true end
	end
	return false
end
local function shaftCount() return #h.workspace.Shafts:GetChildren() end

--======================================================================= CONTROL: an unlocked join is not slowed down
do
	local plr = h:join("Calm", CALM)
	h:advance(0.1)
	truthy(hasShaft(CALM), "an unlocked profile is loaded and its shaft built at once (no retry wait)")
	truthy(locked(CALM), "...and the session holds the lock")
	h:leave(plr)
	h:advance(1)
	eq(locked(CALM), false, "an ordinary leave releases the lock")
end

--======================================================================= A. left while the profile was loading
do
	local shaftsBefore = shaftCount()
	local orig = store.UpdateAsync
	local armed = true
	store.UpdateAsync = function(self, key, transform)
		local a, b = orig(self, key, transform)
		if armed and key == "u_" .. LEAVER then
			-- the server's own PlayerAdded handler runs first, so the player is found the way a server would
			for _, p in h.Players:GetPlayers() do
				if p.UserId == LEAVER then
					armed = false
					h:leave(p) -- the player goes while the load's UpdateAsync is still in flight
				end
			end
		end
		return a, b
	end
	h:join("Leaver", LEAVER)
	h:advance(1)
	store.UpdateAsync = orig
	eq(armed, false, "the staged leave really happened inside the load")
	eq(shaftCount(), shaftsBefore, "no shaft is built for a player who left during the load")
	eq(locked(LEAVER), false, "the lock that load took is given back (it used to stay for SessionLockSeconds)")
	eq(rec(LEAVER).data.cash, 100, "...and the saved data is untouched")
	eq(#h:errors(), 0, "no error from the cancelled join")
end

--======================================================================= A2. ...and the release never touches somebody else's lock
do
	-- The same staged leave, but by the time the load's call returns the record already belongs to ANOTHER session
	-- (this load's lock lapsed, or an old server wrote over it). Giving "our" lock back must not open theirs.
	local orig = store.UpdateAsync
	local armed = true
	store.UpdateAsync = function(self, key, transform)
		local a, b = orig(self, key, transform)
		if armed and key == "u_" .. LEAVER then
			for _, p in h.Players:GetPlayers() do
				if p.UserId == LEAVER then
					armed = false
					h:leave(p)
					orig(self, key, function(old)
						old.jobId, old.session, old.lockUntil = "OTHER-SERVER", "OTHER-SESSION", os.time() + 3600
						return old
					end)
				end
			end
		end
		return a, b
	end
	h:join("Leaver", LEAVER)
	h:advance(1)
	store.UpdateAsync = orig
	eq(armed, false, "the second staged leave happened")
	truthy(locked(LEAVER) and rec(LEAVER).session == "OTHER-SESSION", "a lock another session took meanwhile is left alone")
	eq(#h:errors(), 0, "no error from it")
end

--======================================================================= B1. a server hop: the old lock goes a moment later
do
	local plr = h:join("Hopper", HOPPER)
	h:advance(RETRY_S * 0.5)
	-- the old server's final save lands now: fresh data, lock released
	store:UpdateAsync("u_" .. HOPPER, function(old)
		old.data.cash = 777
		old.data.runEarned = 777
		old.lockUntil = 0
		return old
	end)
	h:advance(WINDOW + 1)
	truthy(hasShaft(HOPPER), "the hopper is in the game after the retry window")
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	local s = stateOf(plr)
	eq(s and s.cash, 777, "the retry loaded what the old server saved last, not the stale copy")
	truthy(locked(HOPPER) and rec(HOPPER).session ~= "OTHER-SESSION", "the retry took the lock for this session")
	h:leave(plr)
	h:advance(1)
	eq(locked(HOPPER), false, "...so this session saves and releases on leaving (it was read-only for life before)")
end

--======================================================================= B2. a load that simply failed is tried again
do
	store.__failNext = true
	local plr = h:join("Flaky", FLAKY)
	h:advance(WINDOW + 1)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	local s = stateOf(plr)
	eq(s and s.cash, 321, "after one failed call the profile is loaded on the retry")
	truthy(locked(FLAKY), "...and this session holds the lock")
	h:leave(plr)
	h:advance(1)
	eq(locked(FLAKY), false, "...and releases it on leaving")
end

--======================================================================= B3. a crashed server's lock outlasts the window
do
	local plr = h:join("Crashed", CRASHED)
	h:advance(WINDOW + 1)
	truthy(hasShaft(CRASHED), "a profile locked for an hour still gets INTO the game after the bounded wait")
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(2)
	eq(rec(CRASHED).session, "OTHER-SESSION", "...read-only: the other session's record is not taken")
	eq(rec(CRASHED).data.cash, 555, "...and not written")
	h:leave(plr)
	h:advance(1)
	eq(rec(CRASHED).session, "OTHER-SESSION", "leaving a read-only session writes nothing either")
	truthy(locked(CRASHED), "...and does not release a lock it never held")
end

--======================================================================= C. leaving during the retry wait
do
	local shaftsBefore = shaftCount()
	local plr = h:join("WaitLeaver", WAITLEAVER)
	h:advance(RETRY_S * 0.5)
	h:leave(plr)
	store:UpdateAsync("u_" .. WAITLEAVER, function(old) old.lockUntil = 0; return old end) -- the old lock goes
	-- from here on the server has no business with this record at all: count its calls
	local orig, calls = store.UpdateAsync, 0
	store.UpdateAsync = function(self, key, transform)
		if key == "u_" .. WAITLEAVER then calls += 1 end
		return orig(self, key, transform)
	end
	h:advance(WINDOW + 2)
	store.UpdateAsync = orig
	eq(calls, 0, "the load stops trying once the player has gone (no further DataStore calls for them)")
	eq(shaftCount(), shaftsBefore, "no shaft for a player who left while the load was waiting to retry")
	eq(locked(WAITLEAVER), false, "...and no lock taken for them afterwards")
	eq(#h:errors(), 0, "no error from it")
end

print(string.format("deepvein lockleak: %d passed, %d failed", passed, failed))
assert(failed == 0, "deepvein lockleak check failed")
