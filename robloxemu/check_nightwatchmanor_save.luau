-- Nightwatch Manor — a save lands only while this session still OWNS the profile. Run: luau check_nightwatchmanor_save.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- The second reviewer (2026-09-30, MEDIUM; docs/complete-game-standard.md §1: "canSave only while holding the session
-- lock, an owner token on every write"): saveProfile wrote whenever the stored lock was nil or older than
-- SessionLockSeconds, WHOEVER's token it carried, and prof.canSave never turned false. So: a server whose saves stall
-- past 45 s loses the lock, the player carries on on another server, that server releases the lock on leaving, and
-- the stale server's next autosave rolls the player back (night, stash, best night, upgrades).
--
-- One REAL server; each case is its own player (its own userId and record). Session A joins, loads and takes the lock,
-- then "another session" writes the record the way this game's own server writes it, and A's autosave runs:
--   1. another session saved newer progress and RELEASED the lock (lock = nil, the old release format): A's autosave
--      and A's leaving must not touch it, and A is told its progress is no longer being saved;
--   2. the same with the lock released the way the server releases it now (the token kept, `at` = 0);
--   3. another session's lock has EXPIRED (it stalled too): still not A's to write over;
--   4. CONTROL: another session's lock is fresh: refused (that case already worked; it proves the probe sees a refusal);
--   5. CONTROL: A still owns the record (its own token, even with A's own lock stale because A's saves stalled and
--      nobody took over): A's progress IS saved, so the refusals above are not a save that never happens;
--   6. leaving releases the lock, and the next session on the same record takes it and saves.

local Harness = require("./emu/harness")
-- the Servants' Exit opens only to a player standing at it after the shortest walk (Crossing.luau): Kit.extract
local Kit = require("./check_nightwatchmanor_kit")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/nightwatch-manor"), name = "nwm-save", viewport = { 1280, 720 }, touch = false })
local store = h.services.DataStoreService:GetDataStore("NightwatchManor_v1")
assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local notice = h.ReplicatedStorage:FindFirstChild("ManorRemotes"):FindFirstChild("Notice")
local nextId = 5000

-- A new player with the record { night = 5, stash = 10, best = 5 }: join, let the load land.
local function boot(label: string)
	nextId += 1
	local ME = nextId
	local KEY = "u_" .. ME
	store:SetAsync(KEY, { data = { night = 5, stash = 10, best = 5, levels = { lanterns = 1 } } })
	local plr = h:join("Session" .. ME, ME)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(1)
	local c = { h = h, store = store, plr = plr, Config = Config, notice = notice, ME = ME, KEY = KEY }
	function c.record() return store:GetAsync(KEY) end
	function c.write(v) store:SetAsync(KEY, v) end
	function c.readonly(): number
		local n = 0
		for _, s in notice:sentTo(plr) do
			local p = s.args[1]
			if type(p) == "table" and p.kind == "READONLY" then n += 1 end
		end
		return n
	end
	function c.autosave() h:advance(Config.Save.AutosaveSeconds + 1) end
	function c.finish() end
	local rec = c.record()
	truthy(rec and rec.lock and type(rec.lock.token) == "string" and rec.lock.token ~= "", label .. ": CONTROL: session A loaded and took the lock")
	c.token = rec and rec.lock and rec.lock.token
	eq(c.readonly(), 0, label .. ": CONTROL: A was not told it is read-only (it holds the lock)")
	return c
end

-- What another session leaves behind: newer progress, and a lock that is not A's.
local NEWER = { night = 9, stash = 999, best = 9, levels = { lanterns = 4, wardstones = 2 } }
local function takenOver(c: any, lock: any)
	c.write({ data = NEWER, lock = lock })
end
local function stillNewer(c: any, label: string)
	local d = (c.record() or {}).data or {}
	eq(d.night, 9, label .. ": the other session's night survives")
	eq(d.stash, 999, label .. ": ...and its relics")
	eq(d.best, 9, label .. ": ...and its best night")
	eq(d.levels and d.levels.lanterns, 4, label .. ": ...and its upgrades")
end

--================================================================ 1-3: A no longer owns the record

for _, case in {
	{ "released (lock = nil)", function(_c) return nil end },
	{ "released (token kept, at = 0)", function(_c) return { token = "B-session", at = 0 } end },
	{ "expired foreign lock", function(_c) return { token = "B-session", at = os.time() - 1000 } end },
} do
	local label = case[1]
	local c = boot(label)
	takenOver(c, case[2](c))
	c.autosave()
	stillNewer(c, label .. ", after A's autosave")
	eq(c.readonly(), 1, label .. ": A is told once that its progress is no longer being saved")
	c.autosave()
	stillNewer(c, label .. ", after a second autosave")
	eq(c.readonly(), 1, label .. ": ...and told only once")
	c.h:leave(c.plr)
	c.h:advance(1)
	stillNewer(c, label .. ", after A leaves")
	c.finish()
end

--================================================================ 4. CONTROL: a fresh foreign lock

do
	local label = "CONTROL fresh foreign lock"
	local c = boot(label)
	takenOver(c, { token = "B-session", at = os.time() })
	c.autosave()
	stillNewer(c, label)
	c.finish()
end

--================================================================ 5. CONTROL: A still owns it, so A's progress is saved

do
	local label = "CONTROL A owns it"
	local c = boot(label)
	-- A's own lock gone stale (its saves stalled for longer than SessionLockSeconds), and nobody took over
	local rec = c.record()
	c.write({ data = rec.data, lock = { token = c.token, at = os.time() - 1000 } })
	-- A survives a night on the real server: 5 -> 6
	local zone = c.h.workspace:FindFirstChild("Zone_" .. c.ME)
	zone:FindFirstChild("Safehouse").ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(c.plr)
	local began = c.h.scheduler:now()
	c.h:advance(0.6)
	local exit = zone:FindFirstChild("Manor") and zone.Manor:FindFirstChild("ExitDoor")
	truthy(exit ~= nil, label .. ": CONTROL: the night began")
	if exit then Kit.extract(c.h, c.plr, c.ME, began, function(s) c.h:advance(s) end) end
	c.h:advance(c.Config.BeatSeconds + 0.5)
	c.autosave()
	local d = (c.record() or {}).data or {}
	eq(d.night, 6, label .. ": A's autosave saved the night it just survived")
	eq(((c.record() or {}).lock or {}).token, c.token, label .. ": ...and renewed its own lock")
	eq(c.readonly(), 0, label .. ": ...and A was never told it is read-only")
	c.finish()
end

--================================================================ 6. leaving releases; the next session takes over

do
	local label = "release"
	local c = boot(label)
	c.h:leave(c.plr)
	c.h:advance(1)
	local rec = c.record() or {}
	eq((rec.data or {}).night, 5, label .. ": leaving saved the profile")
	truthy(rec.lock == nil or (tonumber(rec.lock.at) or 0) == 0, label .. ": ...and released the lock")
	local again = c.h:join("SessionAgain", c.ME)
	c.h.Players:simulateSpawn(again, c.h.workspace)
	c.h:advance(1)
	local rec2 = c.record() or {}
	truthy(rec2.lock and rec2.lock.token ~= nil and rec2.lock.token ~= c.token and (tonumber(rec2.lock.at) or 0) > 0,
		label .. ": the next session took the released lock with its own token")
	local n = 0
	for _, s in c.notice:sentTo(again) do
		if type(s.args[1]) == "table" and s.args[1].kind == "READONLY" then n += 1 end
	end
	eq(n, 0, label .. ": ...and can save (not read-only)")
	c.finish()
end

for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings from the server")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("nightwatchmanor save: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("nightwatchmanor save failed", 0)
end
