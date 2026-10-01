-- Escape Room Lab — the release write on leave vs a save already in flight (review 2026-10-01).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_release.luau 2>&1
--
-- UpdateAsync is given a latency (the emulator's own is 0), and a player leaves around an autosave tick,
-- so that tick's save is in flight together with the leave's release write. Before the fix the tick's
-- write landed after the release and re-took the lock for 45 s: a rejoin was told "open on another
-- server", started at 0 stars and saved nothing. Now the release is final: no later write of the same
-- session lands, and the rejoin loads and saves. Three orders:
--   * leave 0.10 s and 0.25 s BEFORE the tick (0.3 s per call): the tick's save starts after the release;
--   * leave 0.10 s AFTER the tick, with the tick's save slower (0.5 s) than the release (0.1 s): the save
--     started first and lands last, the case the transform's own check is for.
-- Review-1 A3: a player who leaves while the LOAD is still in flight leaves no lock behind (two orders,
-- below the three above).

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy
local Config
local LAT = 0.3 -- UpdateAsync latency (the emulator's own is 0)
local queue = {} -- per-call latencies to use before LAT, in call order
-- per-call modes, in call order: "late" (default: the transform runs when the write lands, after the
-- latency) or "early" (the transform runs when the call is made and its result is written after the
-- latency: Roblox runs the transform when the service has read the key, before the write commits)
local modes = {}
local sched2
local function deepCopy(x)
	if type(x) ~= "table" then return x end
	local o = {}
	for k, v in x do o[k] = deepCopy(v) end
	return o
end
local vet11 = { v = 1, best = { ["1"] = 3, ["2"] = 3, ["3"] = 3, ["4"] = 2 }, starsAt = 1790100000, escapedAt = 0, boarded = 11, rooms = 4 }
local w2 = Lib.boot({ name = "escape-room-lab-save-release", preload = { [6004] = deepCopy(vet11), [6005] = deepCopy(vet11) },
	beforeServer = function(h2)
	sched2 = h2.scheduler
	local st = h2.services.DataStoreService:GetDataStore("EscapeRoomLab_v1")
	local orig = st.UpdateAsync
	st.UpdateAsync = function(self, key, fn)
		local lat = if #queue > 0 then table.remove(queue, 1) else LAT
		local mode = if #modes > 0 then table.remove(modes, 1) else "late"
		if mode == "early" then
			local out = fn(deepCopy(self.__data[key]))
			sched2:wait(lat)
			if out == nil then return self.__data[key] end
			return orig(self, key, function() return out end)
		end
		sched2:wait(lat)
		return orig(self, key, fn)
	end
end })
local h2 = w2.h
Config = w2.Config
local bootClock = sched2:now() - 0.5 -- Lib.boot advanced 0.5 s after the server started
local store2 = h2.services.DataStoreService:GetDataStore("EscapeRoomLab_v1")
local function step2() h2:advance(0.1) end
local results = {}
local cases = {
	{ uid = 6001, offset = 0.1, label = "left 0.10 s before the tick" },
	{ uid = 6002, offset = 0.25, label = "left 0.25 s before the tick" },
	{ uid = 6003, offset = -0.1, slow = { 0.5, 0.1 }, label = "left 0.10 s after the tick, the tick's save 0.5 s, the release 0.1 s" },
}
for _, case in cases do
	local uid, OFFSET = case.uid, case.offset
	local e = Lib.player(w2, "Eve" .. uid, uid)
	h2:advance(2)
	Lib.intoSoloLift(w2, e)
	h2:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
	Lib.solveRoom(w2, e, step2)
	h2:advance(Config.Save.CoalesceSeconds + 1)
	-- leave OFFSET seconds before the next autosave tick (negative: after it)
	local A = Config.Save.AutosaveSeconds
	local now = sched2:now()
	local k = math.ceil((now - bootClock) / A + 1e-9)
	local tickAt = bootClock + k * A
	if tickAt - math.max(OFFSET, 0) <= now + 0.05 then tickAt += A end
	if case.slow then
		h2:advance(tickAt - 0.05 - now)
		for _, l in case.slow do table.insert(queue, l) end -- the tick's save, then the release
		h2:advance(0.05 - OFFSET)
	else
		h2:advance(tickAt - OFFSET - now)
	end
	sched2:spawn(function() h2:leave(e.plr) end)
	h2:advance(3)
	table.clear(queue)
	local rec = store2.__data["u_" .. uid]
	local untilT = rec and rec.lock and tonumber(rec.lock["until"]) or -1
	truthy(untilT <= os.time(), string.format("%s: the lock stays released (until %d, now %d)", case.label, untilT, os.time()))
	local e2 = Lib.player(w2, "Eve" .. uid, uid)
	h2:advance(2)
	local p2 = Lib.last(w2, "Profile", e2.plr)
	local told = false
	for _, n in w2.R.Notice:sentTo(e2.plr) do
		if type(n.args[1]) == "table" and string.find(tostring(n.args[1].text), "open on another server", 1, true) then told = true end
	end
	eq(p2.canSave, true, case.label .. ": an immediate rejoin can save")
	eq(p2.stars, 3, case.label .. ": and has the room it played")
	truthy(not told, case.label .. ": and is not told the save is open on another server")
	table.insert(results, string.format("%s: lock until %d (now %d), rejoin canSave %s, stars %d", case.label, untilT, os.time(), tostring(p2.canSave), p2.stars))
	-- gone again, so the next case's tick saves only its own player (the latency queue is per call)
	sched2:spawn(function() h2:leave(e2.plr) end)
	h2:advance(2)
end
-- Review-1 finding A3: a player who leaves while their LOAD is still in flight. Before the fix the load landed
-- after the leave, took the lock for SessionLockSeconds with nobody left to release it, and an immediate
-- rejoin showed 0 of 11 stars with saving off ("open on another server") for about a minute. Two orders:
--   * the transform runs when the write lands (after the leave): it must not take the lock. Any later write
--     is given 5 s, so a lock taken and released afterwards would still be held when the rejoin loads: the
--     transform's own check has to hold by itself;
--   * the transform ran before the leave and the write lands after it: the lock it took is released.
for _, case in {
	{ uid = 6004, mode = "late", lat = { 1.0, 5.0 }, label = "left 0.3 s into a 1.0 s load (the transform runs at landing)" },
	{ uid = 6005, mode = "early", lat = { 1.0 }, label = "left 0.3 s into a 1.0 s load (the transform ran before the leave)" },
} do
	for _, l in case.lat do table.insert(queue, l) end
	table.insert(modes, case.mode)
	local plr = h2:join("Vet" .. case.uid, case.uid)
	h2:advance(0.3)
	sched2:spawn(function() h2:leave(plr) end)
	h2:advance(1.5)
	table.clear(queue)
	table.clear(modes)
	local rec = store2.__data["u_" .. case.uid]
	local lock = rec and rec.lock
	local held = type(lock) == "table" and lock.session ~= "" and (tonumber(lock["until"]) or 0) > os.time()
	eq(held, false, case.label .. ": no lock is left behind by a session that is gone")
	eq(rec and rec.data and rec.data.best and rec.data.best["4"], 2, case.label .. ": the stored stars are untouched")
	local e2 = Lib.player(w2, "Vet" .. case.uid, case.uid)
	h2:advance(2)
	local p2 = Lib.last(w2, "Profile", e2.plr) or {}
	local told = false
	for _, n in w2.R.Notice:sentTo(e2.plr) do
		if type(n.args[1]) == "table" and string.find(tostring(n.args[1].text), "open on another server", 1, true) then told = true end
	end
	eq(p2.stars, 11, case.label .. ": an immediate rejoin shows all 11 stars")
	eq(p2.canSave, true, case.label .. ": and can save")
	truthy(not told, case.label .. ": and is not told the save is open on another server")
	table.insert(results, string.format("%s: lock left held %s; rejoin stars %s, canSave %s", case.label, tostring(held),
		tostring(p2.stars), tostring(p2.canSave)))
	sched2:spawn(function() h2:leave(e2.plr) end)
	h2:advance(2)
end
for _, r in results do print("  " .. r) end

t.finish("escape-room-lab release", h2)
