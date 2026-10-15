-- Gnome Garden Defense: saves, the board's store, the day's endless bed, the AFK hold and the rate limit.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_save.luau
--
-- docs/complete-game-standard.md §1 and §3: pcall everything, save only while holding the session lock, an
-- owner token on every write, string keys; the board in an OrderedDataStore keyed u_<userId>, value
-- metric * 2e9 + (2e9 - reachedAt), written only when the metric improves. DESIGN.md §3.6: every wave above 40
-- is played on the day's bed, which a restart cannot change. §3.1: an absent gardener is not sent waves.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-defense", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local DSS = h.game:GetService("DataStoreService")
local store = DSS:GetDataStore("GnomeGarden_v1")
local LOCKED, SAVER, ENDLESS_A, ENDLESS_B, IDLE, SPAM = 6001, 6002, 6003, 6004, 6005, 6006

-- someone else's server holds LOCKED's record for the next minute
store:SetAsync("u_" .. LOCKED, { data = { chapter = 3, bestWave = 25, bestAt = 1700000000 }, session = "other", jobId = "another-server", lockUntil = os.time() + 60 })
-- two endless gardeners
store:SetAsync("u_" .. ENDLESS_A, { data = { chapter = 5, bestWave = 40, bestAt = 1700000000 } })
store:SetAsync("u_" .. ENDLESS_B, { data = { chapter = 5, bestWave = 40, bestAt = 1700000100 } })

assert(h:tryRun("server/Main.server"))
h:advance(1)
local R = h.ReplicatedStorage.GardenRemotes
local toasts = {}
R.Toast.OnClientEvent:Connect(function(m) table.insert(toasts, tostring(m)) end)
local function fire(plr, name, ...)
	h.Players.LocalPlayer = plr
	R[name]:FireServer(...)
end
local function gardenOf(uid)
	for _, g in h.workspace.Gardens:GetChildren() do
		if g:GetAttribute("Owner") == uid then return g end
	end
	return nil
end
local info = h.game:GetService("ServerStorage"):FindFirstChild("GardenInfo")

--============================================================ a locked record: loads, never saves, says so
do
	local p = h:join("Locked", LOCKED)
	h:advance(1)
	eq(p:GetAttribute("Saving"), false, "a record another server holds loads READ-ONLY")
	eq(p:GetAttribute("Chapter"), 3, "but its data still loads (autumn)")
	eq(gardenOf(LOCKED):GetAttribute("Chapter"), 3, "and the garden starts autumn")
	local said = false
	for _, t in toasts do
		if string.find(t, "not being saved", 1, true) then said = true end
	end
	truthy(said, "and the player is told progress is not being saved")
	h:advance(25)
	local rec = store:GetAsync("u_" .. LOCKED)
	eq(rec.session, "other", "an autosave never writes over the other server's record")
	eq(rec.jobId, "another-server", "(its lock is untouched)")
	h:leave(p)
	h:advance(1)
	eq(store:GetAsync("u_" .. LOCKED).jobId, "another-server", "leaving does not release a lock it never held")
end

--============================================================ a normal save: token, jobId, board, lost ownership
do
	local p = h:join("Saver", SAVER)
	h:advance(1)
	eq(p:GetAttribute("Saving"), true, "a free record is taken: this server saves")
	local rec = store:GetAsync("u_" .. SAVER)
	truthy(type(rec.session) == "string" and #rec.session > 0, "the load wrote a session token")
	eq(rec.jobId, h.game.JobId, "and this server's jobId")
	-- survive wave 1 with two pebbles on the best pads
	local g = gardenOf(SAVER)
	fire(p, "Plant", 1, "pebble")
	fire(p, "Plant", 2, "pebble")
	fire(p, "Ready")
	local guard = 0
	while g:GetAttribute("Phase") == "wave" and guard < 400 do
		h:advance(0.5)
		guard += 1
	end
	local best = p:GetAttribute("BestWave")
	truthy((best or 0) >= 1, "wave 1 survived (best " .. tostring(best) .. ")")
	h:advance(21) -- one autosave
	rec = store:GetAsync("u_" .. SAVER)
	eq(rec.data.bestWave, best, "the autosave wrote the best wave")
	eq(rec.data.chapter, 1, "and the unlocked chapter")
	truthy(rec.lockUntil > os.time(), "and renewed the lock")
	local lb = DSS:GetOrderedDataStore("GnomeGarden_LB_v1")
	local v = lb:GetAsync("u_" .. SAVER)
	truthy(type(v) == "number" and math.floor(v / 2e9 + 0.5) == best, "the board holds the best wave, encoded (" .. tostring(v) .. ")")
	-- another server takes the record: this one stops saving and says so
	local stolen = store:GetAsync("u_" .. SAVER)
	stolen.session = "thief"
	stolen.data.bestWave = 0
	store:SetAsync("u_" .. SAVER, stolen)
	local before = #toasts
	h:advance(21)
	eq(store:GetAsync("u_" .. SAVER).data.bestWave, 0, "a record another session has taken is never written over")
	eq(store:GetAsync("u_" .. SAVER).session, "thief", "(its token stands)")
	local told = false
	for i = before + 1, #toasts do
		if string.find(toasts[i], "another server", 1, true) then told = true end
	end
	truthy(told, "the player is told nothing here saves any more")
	h:leave(p)
	h:advance(1)
	eq(store:GetAsync("u_" .. SAVER).session, "thief", "and leaving does not write either")
end

--============================================================ the day's endless bed is the same for everyone, every attempt
do
	local a = h:join("EndlessA", ENDLESS_A)
	local b = h:join("EndlessB", ENDLESS_B)
	h:advance(1)
	local ga, gb = gardenOf(ENDLESS_A), gardenOf(ENDLESS_B)
	eq(ga:GetAttribute("Chapter"), 5, "an endless gardener starts the Moonlit Bed")
	eq(ga:GetAttribute("Wave"), 41, "at wave 41")
	eq(ga:GetAttribute("PathCells"), gb:GetAttribute("PathCells"), "two players on one day get the same bed")
	local seedA = info:FindFirstChild(tostring(ENDLESS_A)):GetAttribute("BedSeed")
	local day = math.floor(os.time() / 86400)
	eq(DSS:GetDataStore("GnomeGarden_Daily_v1"):GetAsync("d_" .. day), seedA, "drawn once and kept in the daily store")
	-- lose on purpose (no gnomes, READY), then restart: still the same bed
	fire(a, "Ready")
	eq(ga:GetAttribute("Phase"), "reveal", "READY with no gnome is refused")
	fire(a, "Plant", 1, "pebble")
	fire(a, "Ready")
	local guard = 0
	while ga:GetAttribute("Phase") ~= "lost" and guard < 2000 do
		h:advance(1)
		guard += 1
		if ga:GetAttribute("Phase") == "build" then fire(a, "Ready") end
	end
	eq(ga:GetAttribute("Phase"), "lost", "one pebble loses the endless bed")
	local path0 = ga:GetAttribute("PathCells")
	fire(a, "Restart")
	h:advance(0.5)
	eq(ga:GetAttribute("Phase"), "reveal", "TRY AGAIN starts a new attempt")
	eq(ga:GetAttribute("PathCells"), path0, "on the SAME bed: restarting cannot fish for a better one")
	h:leave(a)
	h:leave(b)
	h:advance(1)
end

--============================================================ the AFK hold
do
	local p = h:join("Idle", IDLE)
	h:advance(1)
	local g = gardenOf(IDLE)
	-- two pebbles on the two pads that see the most path: on pads 1 and 2 of an unlucky bed the garden was LOST
	-- before the 180 s hold came round (a server-random bed: this check failed about one run in ten)
	local Cfg = require("../gnome-garden-defense/src/shared/Config")
	local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
	local path = PathGen.fromText(Cfg, g:GetAttribute("PathCells"))
	local ranked = {}
	for id, pd in PathGen.pads(Cfg, path) do
		local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, 14)
		table.insert(ranked, { id = id, cover = cover })
	end
	table.sort(ranked, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	fire(p, "Plant", ranked[1].id, "pebble")
	fire(p, "Plant", ranked[2].id, "pebble")
	fire(p, "Ready")
	local waves, held = 0, false
	local t = 0
	while t < 900 do
		h:advance(1)
		t += 1
		if g:GetAttribute("Phase") == "held" then held = true break end
		if g:GetAttribute("Phase") == "lost" then break end
	end
	print(string.format("  AFK: the garden went to held %d s after the last action (phase %s, wave %s)", t,
		tostring(g:GetAttribute("Phase")), tostring(g:GetAttribute("Wave"))))
	truthy(held, string.format("a gardener who does nothing for %d s is not sent the next wave (held)", t))
	truthy(t >= 180, "and not before the 180 s hold (" .. t .. " s)")
	local w = g:GetAttribute("Wave")
	h:advance(120)
	eq(g:GetAttribute("Phase"), "held", "the garden waits as long as they are away")
	eq(g:GetAttribute("Wave"), w, "and the wave count does not move")
	fire(p, "Upgrade", 1)
	h:advance(0.5)
	eq(g:GetAttribute("Phase"), "build", "any action brings the build timer back")
	h:advance(21)
	eq(g:GetAttribute("Phase"), "wave", "and the next wave comes")
	h:leave(p)
	h:advance(1)
end

--============================================================ the rate limit: refused out loud, never silently
do
	local p = h:join("Spammer", SPAM)
	h:advance(1)
	local before = #toasts
	for _ = 1, 60 do fire(p, "Sell", 1) end
	h:advance(0.1)
	local slow, other = 0, 0
	for i = before + 1, #toasts do
		if toasts[i] == "Slow down a little" then slow += 1 else other += 1 end
	end
	print(string.format("  60 requests in one instant: %d answered, %d 'slow down' toasts for the other 40", other, slow))
	eq(other, 20, "a burst of 20 is served (each with its own answer)")
	-- REVIEW-1: one toast per refused call let a client make the server echo thousands; the refusal is said
	-- once per Config.Net.RepeatToastSeconds instead (check_gnomegardendefense_store.luau measures a flood)
	eq(slow, 1, "and the rest are refused out loud: told once to slow down, not 40 times")
	h:advance(2)
	local before2 = #toasts
	fire(p, "Sell", 1)
	h:advance(0.1)
	eq(toasts[#toasts], "No gnome there", "two seconds later requests are served again")
	truthy(#toasts > before2, "(and answered)")
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no server thread died")
print(("gnome garden save: %d passed, %d failed"):format(passed, failed))
