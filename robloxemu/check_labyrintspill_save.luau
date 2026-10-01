-- Labyrinth Mariozo — saving: the session lock, the owner token and one-time grants.
-- Run: luau check_labyrintspill_save.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- docs/complete-game-standard.md §1: "pcall everything, canSave only while holding the session lock, an owner
-- token on every write (fork-tower old.session), string keys, one-time grants inside one atomic UpdateAsync."
-- Before 2026-10-01 the player store was written only with SetAsync (a load-failure guard, no lock, no token), so
-- two servers holding the same player could each write over the other, and a daily reward granted in memory stayed
-- granted when its write failed. Everything here runs through the REAL server script against the emulator's
-- DataStore (JSON round-trip, UpdateAsync that may abort). os.time() is real time; the lock is judged on it.
--
-- The record stays FLAT (the live game's `p_<userId>` shape, every existing field where it was) and gains three
-- fields: `session` (the owner token), `lockUntil` (unix seconds; 0 = released) and `jobId`.

local Harness = require("./emu/harness")
local Lib = require("./check_labyrintspill_lib")
local c = Lib.counter("labyrintspill save")

local h = Harness.new({ bundle = require("./build/labyrint-spill"), name = "labyrint-spill", viewport = { 1280, 720 }, touch = false })
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("LabyrintSpill_v1")
local today = math.floor(os.time() / 86400)
local src = Lib.serverSource(require("./build/labyrint-spill"))

-- saved players, written the way the live game wrote them before this change (flat, no lock fields)
store:SetAsync("p_701", { coins = 1234, gems = 7, trophies = 3, owned = { classic = true, lego = true }, theme = "lego",
	accepted = 12, level = 13, bestByLevel = { ["1"] = 9.5 }, rewardDay = today, streak = 2, gifts = {} })
-- held by another live server right now
store:SetAsync("p_702", { coins = 500, accepted = 4, rewardDay = today - 1, streak = 1,
	session = "tok-other", jobId = "other-server", lockUntil = os.time() + 600 })
-- a lock left behind by a server that crashed (expired)
store:SetAsync("p_703", { coins = 80, accepted = 2, rewardDay = today, session = "tok-crashed", jobId = "crashed-server", lockUntil = os.time() - 5 })
-- daily reward due (yesterday), and the write that grants it fails
store:SetAsync("p_704", { coins = 100, rewardDay = today - 1, streak = 3 })
-- daily reward due, and the write lands
store:SetAsync("p_705", { coins = 100, rewardDay = today - 1, streak = 3 })

local ok, err = h:tryRun("server/MazeGame.server")
c.truthy(ok, "the server runs: " .. tostring(err))
local RS = h.ReplicatedStorage

-- count every write the server makes to the player store from here on
local sets, updates = 0, 0
local failOn = {} -- key -> the nth UpdateAsync on that key raises
local callsOn = {}
do
	local oSet, oUpd = store.SetAsync, store.UpdateAsync
	store.SetAsync = function(self, ...) sets += 1; return oSet(self, ...) end
	store.UpdateAsync = function(self, key, ...)
		updates += 1
		callsOn[key] = (callsOn[key] or 0) + 1
		if failOn[key] == callsOn[key] then error("robloxemu: injected failure on " .. key .. " call " .. callsOn[key], 0) end
		return oUpd(self, key, ...)
	end
end
local function rec(uid) return store.__data["p_" .. uid] end
local broadcast = RS:WaitForChild("HudRemotes"):WaitForChild("Broadcast")
local function toldAbout(plr, needle)
	for _, r in broadcast:sentTo(plr) do
		if not r.all and type(r.args[2]) == "string" and string.find(string.lower(r.args[2]), needle, 1, true) then return r.args[2] end
	end
	return nil
end
local function coinsOf(plr) return plr:FindFirstChild("leaderstats") and plr.leaderstats.Coins.Value end
local buyTheme = RS:WaitForChild("ShopRemotes"):WaitForChild("BuyTheme")
local rewardRemote = RS.HudRemotes:WaitForChild("Reward")
local function join(name, uid)
	local p = h:join(name, uid)
	h:advance(0.2)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.2)
	return p
end

--========================================================================= 0. the settings

local lockSecs = tonumber(string.match(src, "SessionLockSeconds%s*=%s*(%d+)"))
local autoSecs = tonumber(string.match(src, "AutosaveSeconds%s*=%s*(%d+)"))
c.truthy(lockSecs ~= nil and autoSecs ~= nil, "CONFIG has SessionLockSeconds and AutosaveSeconds")
lockSecs, autoSecs = lockSecs or 180, autoSecs or 60
c.truthy(autoSecs * 2 < lockSecs, string.format("two autosaves fit inside one lock (%d x 2 < %d): a live session never lets its lock lapse", autoSecs, lockSecs))
c.eq(string.find(src, "dataStore:SetAsync", 1, true), nil, "the server never writes the player store with SetAsync")

--========================================================================= 1. load takes the lock, keeps the data

print("== 1. an old record loads and takes the lock ==")
local A = join("Ava", 701)
local r = rec(701)
c.eq(type(r.session), "string", "loading takes the lock: the record carries an owner token")
c.truthy(type(r.lockUntil) == "number" and r.lockUntil > os.time() + lockSecs - 10, "lockUntil is about SessionLockSeconds ahead (" .. tostring(r.lockUntil and r.lockUntil - os.time()) .. " s)")
c.eq(r.jobId, h.game.JobId, "and names this server")
c.eq(r.coins, 1234, "taking the lock changed no saved field (coins)")
c.eq(r.owned and r.owned.lego, true, "(owned themes)")
c.eq(r.bestByLevel and r.bestByLevel["1"], 9.5, "(string-keyed personal bests)")
c.eq(coinsOf(A), 1234, "the saved coins are loaded")
c.eq(A.leaderstats.Level.Value ~= nil, true, "leaderstats exist")
local tokenA = r.session

--========================================================================= 2. every write carries the token

print("== 2. a purchase and an autosave, written with the token ==")
local res = buyTheme:simulateInvokeServer(A, "ice", "coins")
c.eq(res and res.ok, true, "set-up: Ava buys the Ice Cave theme for 500 coins")
h:advance(7) -- the shop's 6 s debounce
c.eq(rec(701).coins, 734, "the purchase is saved (1234 - 500)")
c.eq(rec(701).owned and rec(701).owned.ice, true, "with the theme")
c.eq(rec(701).session, tokenA, "and the same owner token")
local u0 = updates
h:advance(autoSecs + 1)
c.truthy(updates > u0, "the autosave loop wrote within AutosaveSeconds (" .. (updates - u0) .. " writes)")
c.truthy((rec(701).lockUntil or 0) >= os.time() + lockSecs - 10, "and renewed the lock")
c.eq(sets, 0, "no SetAsync anywhere so far")

--========================================================================= 3. leaving releases, rejoining re-takes

print("== 3. leave and rejoin ==")
h:leave(A)
h:advance(0.5)
c.eq(rec(701).lockUntil, 0, "leaving releases the lock (lockUntil = 0)")
c.eq(rec(701).coins, 734, "and saves")
local A2 = join("Ava", 701)
c.eq(coinsOf(A2), 734, "rejoining loads what was saved")
c.truthy(rec(701).session ~= tokenA and type(rec(701).session) == "string", "with a NEW owner token")
c.truthy((rec(701).lockUntil or 0) > os.time(), "holding the lock again")
h:advance(3) -- the server's notices wait 2.5 s for the HUD, like the daily reward
c.eq(toldAbout(A2, "not be saved"), nil, "a normal rejoin says nothing about saving")

--========================================================================= 4. another session took the record

print("== 4. a newer session owns the record: this one stops writing ==")
do
	local stolen = rec(701)
	stolen.session = "tok-newer"
	stolen.coins = 999
	store.__data["p_701"] = stolen
	local res2 = buyTheme:simulateInvokeServer(A2, "forest", "coins")
	c.eq(res2 and res2.ok, true, "set-up: Ava buys another theme in the old session")
	h:advance(7)
	c.eq(rec(701).coins, 999, "the old session's write is refused (the newer session's coins stand)")
	c.eq(rec(701).session, "tok-newer", "and the newer token stands")
	c.truthy(toldAbout(A2, "another server") ~= nil, "the player is told why their progress stops saving: " .. tostring(toldAbout(A2, "another server")))
	local before = updates
	h:advance(autoSecs * 2 + 1)
	c.eq(updates, before, "and it stops trying: no autosave writes after that")
	h:leave(A2)
	h:advance(0.5)
	c.eq(rec(701).session, "tok-newer", "leaving does not release a lock it no longer holds")
	c.eq(rec(701).coins, 999, "nor write")
end

--========================================================================= 5. locked by a live server

print("== 5. joining while another live server holds the record ==")
do
	local before = table.clone(rec(702))
	local B = join("Bo", 702)
	c.eq(coinsOf(B), 500, "the real data is loaded (never defaults)")
	c.eq(rec(702).session, "tok-other", "the other server's lock is left alone")
	c.eq(rec(702).lockUntil, before.lockUntil, "untouched")
	h:advance(3)
	c.truthy(toldAbout(B, "not be saved") ~= nil, "the player is told this session will not be saved: " .. tostring(toldAbout(B, "not be saved")))
	c.eq(#rewardRemote:sentTo(B), 0, "no daily reward is granted in a session that cannot save it")
	c.eq(coinsOf(B), 500, "(coins unchanged)")
	local w0 = updates
	buyTheme:simulateInvokeServer(B, "lego", "coins")
	h:advance(autoSecs + 8)
	h:leave(B)
	h:advance(0.5)
	c.eq(updates, w0, "no write is even attempted, including on leave")
	c.eq(rec(702).coins, 500, "the stored coins are unchanged")
end

--========================================================================= 6. an expired lock is taken over

print("== 6. a crashed server's expired lock ==")
do
	local C = join("Cy", 703)
	c.truthy(rec(703).session ~= "tok-crashed", "an expired lock is taken over")
	c.eq(coinsOf(C), 80, "with the data")
	h:leave(C)
	h:advance(0.5)
	c.eq(rec(703).lockUntil, 0, "and released on leave")
end

--========================================================================= 7. one-time grants are atomic

print("== 7. the daily reward: granted inside the write, or not at all ==")
do
	failOn["p_704"] = 2 -- call 1 = the load, call 2 = the grant's write
	local D = join("Dee", 704)
	h:advance(3)
	c.eq(coinsOf(D), 100, "the grant's write failed: no coins were granted")
	c.eq(rec(704).rewardDay, today - 1, "nothing about the reward was stored")
	c.eq(#rewardRemote:sentTo(D), 0, "and no reward popup claims otherwise")
	h:leave(D)
	h:advance(0.5)
	c.eq(rec(704).rewardDay, today - 1, "leaving does not sneak the reward in either")
	c.eq(rec(704).coins, 100, "(coins)")
	failOn["p_704"] = nil
	callsOn["p_704"] = nil
	local D2 = join("Dee", 704)
	h:advance(3)
	c.eq(coinsOf(D2), 100 + 150 * 4, "the next session grants it: day 4 of the streak, 600 coins")
	h:leave(D2)
	h:advance(0.5)

	local w0 = callsOn["p_705"] or 0
	local E = join("Eli", 705)
	local grantWrites = (callsOn["p_705"] or 0) - w0 - 1
	c.eq(grantWrites, 1, "a granted reward is exactly one write after the load")
	c.eq(rec(705).coins, 700, "and that write holds the coins (100 + 600)")
	c.eq(rec(705).rewardDay, today, "and the day together")
	c.eq(rec(705).streak, 4, "and the streak")
	h:advance(3)
	c.eq(#rewardRemote:sentTo(E), 1, "one reward popup")
	h:leave(E)
	h:advance(0.5)
	local F = join("Eli", 705)
	h:advance(3)
	c.eq(coinsOf(F), 700, "rejoining the same day grants nothing more")
	c.eq(#rewardRemote:sentTo(F), 0, "(no popup)")
	h:leave(F)
	h:advance(0.5)
end

--========================================================================= 8. a failed load never writes

print("== 8. the load itself fails ==")
do
	store.__data["p_706"] = { coins = 42, accepted = 1, rewardDay = today }
	failOn["p_706"] = 1
	local G = join("Gus", 706)
	h:advance(3)
	c.truthy(toldAbout(G, "not be saved") ~= nil, "the player is told: " .. tostring(toldAbout(G, "not be saved")))
	local w0 = callsOn["p_706"]
	buyTheme:simulateInvokeServer(G, "lego", "coins")
	h:advance(autoSecs + 8)
	h:leave(G)
	h:advance(0.5)
	c.eq(callsOn["p_706"], w0, "nothing is written after a failed load")
	c.eq(rec(706).coins, 42, "the stored record is intact")
end

--========================================================================= 9. a new player, and a shutdown

print("== 9. a brand-new player, then the server closes ==")
do
	local N = join("Nia", 707)
	c.eq(type(rec(707)) == "table" and type(rec(707).session), "string", "a new player's record is created holding the lock")
	h.services.runBindToClose()
	h:advance(0.5)
	c.eq(rec(707).lockUntil, 0, "BindToClose saves and releases")
	c.eq(rec(707).coins ~= nil, true, "with the data written")
	h:leave(N)
end

c.eq(sets, 0, "in the whole run the player store saw no SetAsync")
for _, w in h.warnings do print("warning: " .. w) end
c.finish(h)
