-- StormGrow — saving: the session lock, the owner token on every write, read-only when locked, and a
-- failed load that never writes a default over real data (DESIGN.md §8.4, the standard §1).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_save.luau 2>&1
--
-- The emulator's DataStore does Roblox's JSON round trip, aborts on a nil transform, can run a transform
-- more than once (__retryCount) and can fail on demand (__failNext / __failAll). "Another server" is a
-- record written straight into the store with a foreign session token, which is exactly what a second
-- server's load leaves behind.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-save", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- REVIEW-1: a tile is tapped by the client's pick (Farm.client + Pick.luau), which sends Tap(slot, key). Where this
-- check exercises the SERVER's rules it sends exactly that; check_stormgrow_aim and tests/walk.luau tap the screen.
local function tapTile(plr, hb)
	h.ReplicatedStorage.StormRemotes.Tap:simulateFireServer(plr, hb:GetAttribute("Farm"), hb:GetAttribute("Key"))
end

local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("StormGrow_v1")
local ods = DSS:GetOrderedDataStore("StormGrowAlmanac_v1")

local function farmer(uid, fields)
	local doc = { v = 1, coins = 777, harvested = 5000, fields = 2, unlocked = 3, selected = "corn",
		tiles = { ["1_1"] = { c = "corn", at = 100, m = 5 } }, almanac = { ["corn:5"] = 100 }, almanacCount = 1, almanacAt = 100, harvests = 99 }
	for k, v in fields or {} do doc[k] = v end
	return doc
end

-- the clock the server will run on: os.time() at boot
local T0 = os.time()
-- records written by "another server" before this one boots
store:SetAsync("u_301", farmer(301, { session = { token = "OTHER-SERVER", lockUntil = T0 + 100000 } })) -- locked for a day
store:SetAsync("u_302", farmer(302, { session = { token = "OTHER-SERVER", lockUntil = T0 + 12 } })) -- lock runs out in 12 s
store:SetAsync("u_303", farmer(303)) -- a real record the failed load must not overwrite
store:SetAsync("u_304", farmer(304)) -- will be stolen mid-session
store:SetAsync("u_305", farmer(305)) -- retries of the transform

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local remotes = h.ReplicatedStorage.StormRemotes
local function toasts(plr)
	local out = {}
	for _, rec in remotes.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return table.concat(out, " | ")
end
local function tap(plr, key)
	if plr.Character == nil then
		h.Players:simulateSpawn(plr, h.workspace) -- lands on the farm pad: field 1 is within reach
		h:advance(0.1)
	end
	local hb = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles["Tile_" .. key]
	tapTile(plr, hb)
	h:advance(0.15)
end

--============================================================ 1. a new farmer: the load takes the lock

local p1 = h:join("Fresh", 300)
h:advance(0.5)
local doc = store:GetAsync("u_300")
truthy(doc ~= nil, "a new farmer's first load writes their record")
truthy(doc and type(doc.session.token) == "string" and #doc.session.token > 10, "with a session token (a GUID)")
truthy(doc and doc.session.lockUntil > T0, "and a lock in the future")
eq(doc and doc.coins, 20, "the default profile, 20 coins")
eq(p1:GetAttribute("CanSave"), true, "the session can save")
local token1 = doc.session.token
for t = 1, 5 do tap(p1, "1_" .. t) end
h:advance(61) -- one autosave
doc = store:GetAsync("u_300")
eq(doc.session.token, token1, "the autosave keeps the SAME token (a stable per-session token, not a timestamp)")
eq(doc.tiles["1_3"] and doc.tiles["1_3"].c, "radish", "the autosave wrote the planted tiles")
truthy(doc.session.lockUntil > T0 + 60, "and renewed the lock")

--============================================================ 2. locked by another server: read-only

local p2 = h:join("Hopper", 301)
h:advance(0.5)
truthy(string.find(toasts(p2), "still open in another server", 1, true) ~= nil, "a locked farm says it is waiting (" .. toasts(p2) .. ")")
h:advance(31) -- 6 retries x 5 s
truthy(string.find(toasts(p2), "progress here won't save", 1, true) ~= nil, "after 30 s it plays read-only and says so")
eq(p2:GetAttribute("CanSave"), false, "CanSave is false")
eq(p2:GetAttribute("Loaded"), true, "but the farm still loads and plays")
eq(p2:GetAttribute("Coins"), 777, "with the saved farm's state")
tap(p2, "1_2")
h:advance(61)
h:leave(p2)
h:advance(0.5)
local d2 = store:GetAsync("u_301")
eq(d2.session.token, "OTHER-SERVER", "the other server's lock is untouched")
eq(d2.tiles["1_2"], nil, "nothing the read-only session did was written")
eq(ods:GetAsync("u_301"), nil, "and a read-only session never writes the board")

--============================================================ 3. a lock that runs out while waiting

do
	-- the other server's lock runs out 12 s from NOW on the server clock
	local d = store:GetAsync("u_302")
	d.session.lockUntil = h.workspace:GetAttribute("ServerNow") + 12
	store:SetAsync("u_302", d)
end
local p3 = h:join("Patient", 302)
h:advance(0.5)
eq(p3:GetAttribute("Loaded"), false, "set-up: still waiting for the other server's lock")
h:advance(16)
eq(p3:GetAttribute("Loaded"), true, "the lock ran out (12 s) and the retry took it")
eq(p3:GetAttribute("CanSave"), true, "and this session can save")
local d3 = store:GetAsync("u_302")
truthy(d3.session.token ~= "OTHER-SERVER", "the record now carries this session's token")

--============================================================ 4. a failed load never writes a default over real data

-- (an OUTAGE: since REVIEW-1 A2 a single failed call is retried, part 10)
store.__failAll = true
local p4 = h:join("Unlucky", 303)
h:advance(20)
truthy(string.find(toasts(p4), "Couldn't load your farm", 1, true) ~= nil, "a failed load says so")
eq(p4:GetAttribute("CanSave"), false, "and the session cannot save")
tap(p4, "1_1")
h:advance(61)
h:leave(p4)
h:advance(0.5)
store.__failAll = false
local d4 = store:GetAsync("u_303")
eq(d4.coins, 777, "the real record keeps its 777 coins (no default 20 written over it)")
eq(d4.almanacCount, 1, "and its Almanac")

--============================================================ 5. another session takes the record: this one stops writing

local p5 = h:join("Robbed", 304)
h:advance(0.5)
eq(p5:GetAttribute("CanSave"), true, "set-up: loaded and saving")
do
	-- another server's load takes the record (its lock ran out while this server lagged)
	local d = store:GetAsync("u_304")
	d.session = { token = "THIEF", lockUntil = T0 + 100000 }
	d.coins = 12345
	store:SetAsync("u_304", d)
end
tap(p5, "1_2")
h:advance(61) -- the autosave finds a foreign token
local d5 = store:GetAsync("u_304")
eq(d5.coins, 12345, "the autosave did NOT overwrite the newer session's record")
eq(d5.session.token, "THIEF", "nor its lock")
eq(p5:GetAttribute("CanSave"), false, "this session stopped saving")
truthy(string.find(toasts(p5), "opened in another server", 1, true) ~= nil, "and said so")
h:leave(p5)
h:advance(0.5)
d5 = store:GetAsync("u_304")
eq(d5.session.lockUntil, T0 + 100000, "the late release on leave did NOT unlock the newer session's record")

--============================================================ 6. a transform that runs more than once

store.__retryCount = 2
local p6 = h:join("Retried", 305)
h:advance(0.5)
store.__retryCount = 0
eq(p6:GetAttribute("CanSave"), true, "a load whose transform ran three times still takes the lock once")
eq(p6:GetAttribute("Coins"), 777, "with the right data")

--============================================================ 8. a dead server's lock runs out: the session takes it (REVIEW-1 A1)

-- The server a farmer was on crashed (no release) 135 s after its last autosave: its lock has 45 s left when the
-- farmer rejoins. The 30 s wait ends read-only; once the lock has run out and nobody has written since, the
-- session takes the lock and saves on, with what it played in the meantime.
do
	local now = h.workspace:GetAttribute("ServerNow")
	store:SetAsync("u_310", farmer(310, { session = { token = "DEAD-SERVER", lockUntil = now + 45 } }))
	local p = h:join("Crashed", 310)
	h:advance(31.5)
	eq(p:GetAttribute("CanSave"), false, "set-up: after the 30 s wait the session plays read-only (the dead lock has 13 s left)")
	tap(p, "1_2") -- plays read-only: plants a Corn
	h:advance(40) -- the lock ran out ~27 s ago
	eq(p:GetAttribute("CanSave"), true, "once the dead server's lock ran out untouched, the session takes it and can save")
	truthy(string.find(toasts(p), "saving again", 1, true) ~= nil, "and says so (" .. toasts(p) .. ")")
	local d = store:GetAsync("u_310")
	truthy(d.session.token ~= "DEAD-SERVER", "the record now carries this session's token")
	eq(d.tiles["1_2"] and d.tiles["1_2"].c, "corn", "and what was played read-only is in it")
	h:leave(p)
	h:advance(0.5)
	eq(store:GetAsync("u_310").session.lockUntil, 0, "the leave releases it as usual")
end

--============================================================ 9. a lock that MOVES ON is never taken (A1, the other side)

do
	local now = h.workspace:GetAttribute("ServerNow")
	store:SetAsync("u_311", farmer(311, { session = { token = "LIVE-SERVER", lockUntil = now + 45 } }))
	local p = h:join("Twice", 311)
	h:advance(31.5)
	eq(p:GetAttribute("CanSave"), false, "set-up: read-only behind a live server's lock")
	-- the live server autosaves: its lock moves on, and so does its data
	local d = store:GetAsync("u_311")
	d.session.lockUntil = now + 225
	d.coins = 4242
	store:SetAsync("u_311", d)
	tap(p, "1_2")
	h:advance(60)
	eq(p:GetAttribute("CanSave"), false, "a lock that was renewed is never taken over")
	h:leave(p)
	h:advance(0.5)
	local d2 = store:GetAsync("u_311")
	eq(d2.session.token, "LIVE-SERVER", "the live server keeps its record")
	eq(d2.coins, 4242, "with its data")
	-- and a release (lockUntil = 0) by the other server is not a takeover either: this session played on a copy
	-- loaded BEFORE that server's last save, so writing it would throw that save away
	now = h.workspace:GetAttribute("ServerNow")
	store:SetAsync("u_312", farmer(312, { session = { token = "SLOW-SERVER", lockUntil = now + 45 } }))
	local q = h:join("Slow", 312)
	h:advance(31.5)
	local d3 = store:GetAsync("u_312")
	d3.session.lockUntil = 0
	d3.coins = 999
	store:SetAsync("u_312", d3)
	h:advance(60)
	eq(q:GetAttribute("CanSave"), false, "a record released after the wait ended is not overwritten by the stale copy")
	h:leave(q)
	h:advance(0.5)
	eq(store:GetAsync("u_312").coins, 999, "it keeps the other server's last save")
end

--============================================================ 10. a DataStore blip is retried; an outage recovers (A2)

do
	store:SetAsync("u_320", farmer(320, { coins = 250000 }))
	store.__failNext = true
	local p = h:join("Blip", 320)
	local firstCoins, waited = nil, 0
	while p:GetAttribute("Loaded") ~= true and waited < 15 do
		h:advance(0.1)
		waited += 0.1
	end
	firstCoins = p:GetAttribute("Coins")
	eq(firstCoins, 250000, "one failed load call is retried at once: the first farm the player sees is the real one")
	eq(p:GetAttribute("CanSave"), true, "and it saves")
	truthy(string.find(toasts(p), "Couldn't load", 1, true) == nil, "and the player is never told it failed (" .. toasts(p) .. ")")
	truthy(waited <= 3, string.format("within a few seconds (%.1f s)", waited))
	h:leave(p)
	h:advance(0.5)
	-- an outage longer than the retries: a fresh farm that will not save, until the store answers again
	store:SetAsync("u_321", farmer(321, { coins = 123456 }))
	store.__failAll = true
	local q = h:join("Outage", 321)
	h:advance(25)
	eq(q:GetAttribute("Loaded"), true, "during an outage the farmer still gets a farm to play")
	eq(q:GetAttribute("CanSave"), false, "which does not save")
	truthy(string.find(toasts(q), "Couldn't load your farm", 1, true) ~= nil, "and is told so")
	tap(q, "1_1")
	h:advance(20)
	store.__failAll = false
	h:advance(40)
	eq(q:GetAttribute("CanSave"), true, "when the DataStore answers again, the session loads the real farm and can save")
	eq(q:GetAttribute("Coins"), 123456, "the real farm's coins")
	truthy(string.find(toasts(q), "loaded", 1, true) ~= nil, "and the farmer is told (" .. toasts(q) .. ")")
	h:leave(q)
	h:advance(0.5)
	eq(store:GetAsync("u_321").coins, 123456, "nothing of the fresh farm was ever written over the real one")
end

--============================================================ 11. a record from a NEWER version is never written (A4)

do
	store:SetAsync("u_330", farmer(330, { v = 2, unlocked = 9, rebirths = 3, selected = "moonmelon",
		almanac = { ["moonmelon:7"] = 50, ["corn:5"] = 100 }, almanacCount = 2,
		tiles = { ["1_1"] = { c = "moonmelon", at = 100, m = 7 }, ["1_2"] = { c = "corn", at = 100, m = 0 } } }))
	local p = h:join("Future", 330)
	h:advance(2)
	eq(p:GetAttribute("Loaded"), true, "a record written by a newer version still loads (to look at)")
	eq(p:GetAttribute("CanSave"), false, "but this older server never saves it")
	truthy(string.find(toasts(p), "older version", 1, true) ~= nil, "and says why (" .. toasts(p) .. ")")
	tap(p, "1_3")
	h:advance(61)
	h:leave(p)
	h:advance(0.5)
	local d = store:GetAsync("u_330")
	eq(d.v, 2, "the record keeps its version")
	eq(d.rebirths, 3, "the fields this version does not know")
	eq(d.almanac and d.almanac["moonmelon:7"], 50, "the Almanac entries for crops it does not know")
	eq(d.unlocked, 9, "and the unlocks")
	eq(d.tiles and d.tiles["1_1"] and d.tiles["1_1"].c, "moonmelon", "and the tiles")
	eq(ods:GetAsync("u_330"), nil, "nor is the board written from it")
end

--============================================================ 12. a save still in flight at the leave never re-locks the record

-- (found while reviewing REVIEW-1's soon-save: more saves in flight make it likelier) An autosave whose UpdateAsync is
-- slow (3 s: queued behind other writes) is still in flight when the farmer leaves; the leave's release lands first.
-- The late autosave must not write its older copy over the release, nor lock the record again for 180 s (the next
-- join would wait 30 s and then play read-only).
do
	local orig = store.UpdateAsync
	local slowKey, armed, started = "u_340", false, false
	store.UpdateAsync = function(self, k, f)
		if armed and k == slowKey then
			armed, started = false, true
			h.scheduler:wait(3)
		end
		return orig(self, k, f)
	end
	local p = h:join("Racer", 340)
	h:advance(0.5)
	eq(p:GetAttribute("CanSave"), true, "set-up: loaded and saving")
	tap(p, "1_2")
	armed = true
	local waited = 0
	while not started and waited < 70 do
		h:advance(0.25)
		waited += 0.25
	end
	truthy(started, "set-up: the next autosave started and is held for 3 s")
	tap(p, "1_3") -- planted after that autosave took its copy: only the release carries it
	h:leave(p)
	h:advance(5)
	store.UpdateAsync = orig
	local d = store:GetAsync("u_340")
	eq(d.session.lockUntil, 0, "the late autosave did not lock the record again")
	eq(d.tiles["1_3"] and d.tiles["1_3"].c, "radish", "nor write its older copy over the release's")
	local back = h:join("Racer", 340)
	h:advance(0.5)
	eq(back:GetAttribute("CanSave"), true, "the farmer's next join loads at once and can save")
	h:leave(back)
	h:advance(0.5)
end

--============================================================ 7. leave releases with the owner token; BindToClose releases everyone

h:leave(p1)
h:advance(0.5)
doc = store:GetAsync("u_300")
eq(doc.session.lockUntil, 0, "leaving writes lockUntil = 0")
eq(doc.session.token, token1, "with the owner token")
local back = h:join("Fresh", 300)
h:advance(0.5)
eq(back:GetAttribute("CanSave"), true, "a released record loads writable at once (no 30 s wait)")
h.services.runBindToClose()
h:advance(0.5)
for _, uid in { 300, 302, 305 } do
	eq(store:GetAsync("u_" .. uid).session.lockUntil, 0, "BindToClose released u_" .. uid)
end

print("")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow save: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow save check failed", 0) end
