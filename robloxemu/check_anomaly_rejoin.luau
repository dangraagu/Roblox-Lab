-- anomaly-observatory — the run survives a disconnect, and a wrong call survives everything.
-- Run: luau check_anomaly_rejoin.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- OWNER DECISION (2026-09-30, "take the recommended option for all"; EYECANDY.md §10). The Day streak used
-- to live only in the server's memory, so an idle kick (Roblox: ~20 min without input), a phone switching
-- apps or a dropped connection cost the whole run. The owner's brief is "never punishing", and the brief
-- for rest is "you must be able to press pause". The run is now saved, WITH the live pass, which is what
-- keeps it from being exploitable:
--
--   1. leave mid-pass and rejoin: the same Day and the SAME hall (same roll, same anomaly, the same
--      parts) come back, so leaving is never a re-roll of a pass you could not read. It then scores;
--   2. a wrong call resets the saved run AT ONCE (flushed, not left for the autosave), without its pass
--      (the answer to that pass was just shown to the player), and leaving during the death beat does
--      not undo it: the rejoin is on Day 1 with a fresh roll;
--   3. a session that could not take the save lock (the previous one is still releasing it) starts from
--      the stored run, read-only, and says so. When it wins the lock later:
--        * if the stored run is still the one it loaded, it keeps its own progress on it;
--        * if the stored run CHANGED meanwhile (the other session wrote a wrong call's reset), it adopts
--          the stored one: a run ended by a wrong call can never be resumed from a stale copy;
--        * if it made its own wrong call meanwhile, that reset stands;
--   4. `SavesRun` on the player says truthfully whether this session saves (the break's idle caption
--      promises "saved" only then).

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local A = Config.Anomaly
local originalA = {}
for k, v in A do originalA[k] = v end
local store = h.game:GetService("DataStoreService"):GetDataStore(Config.Save.Store)
local UID = 31337
local KEY = "u_" .. UID

local function zoneOf(plr)
	return h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
end
local function infoOf(plr)
	return h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId))
end
local function day(plr): number
	return plr.leaderstats.Day.Value
end
local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function answer(plr, right: boolean)
	local clean = infoOf(plr):GetAttribute("Clean") == true
	local pad = zoneOf(plr):FindFirstChild(if clean == right then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
end
-- the hall as drawn, relative to its origin (check_anomaly_attrs' fingerprint)
local function fingerprint(zone): string
	local ox = (tonumber(zone:GetAttribute("Index")) or 0) * 1000
	local rows = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			table.insert(rows, string.format("%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d,%d,%d|%.2f|%.2f|%s",
				d.Name, x - ox, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, d.Size.X, d.Size.Y, d.Size.Z,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
				d.Transparency, d.Reflectance, tostring(d.Material)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end
local function storedRun()
	local rec = store.__data[KEY]
	return rec and rec.run
end

--============================================================ 1. leave mid-pass, rejoin: same Day, same hall
local p1 = h:join("Rejoiner", UID)
h:advance(0.2)
eq(p1:GetAttribute("SavesRun"), true, "a session holding the save lock says it saves the run")
answer(p1, true); h:advance(0.2)
answer(p1, true); h:advance(0.2)
-- the next pass is forced anomalous (door_extra), so the restore is tested on a hall that differs from clean
A.Catalog = { originalA.Catalog[2] }
A.StartPool, A.PoolPerDay, A.BaseChance, A.ChancePerDay, A.MaxChance = 1, 0, 1, 0, 1
answer(p1, true); h:advance(0.2)
for k, v in originalA do A[k] = v end
eq(day(p1), 4, "three right calls: Day 4")
eq(infoOf(p1):GetAttribute("AnomalyId"), "door_extra", "the live pass on Day 4 is the forced door_extra")
local fp4 = fingerprint(zoneOf(p1))
h:leave(p1)
h:advance(0.2)
local r = storedRun()
truthy(r ~= nil and r.day == 4, "leaving saved the run on Day 4 (stored day " .. tostring(r and r.day) .. ")")
truthy(r ~= nil and type(r.pass) == "table" and r.pass.anomalyId == "door_extra", "with its live pass (" .. tostring(r and r.pass and r.pass.anomalyId) .. ")")

local p2 = h:join("Rejoiner", UID)
h:advance(0.2)
eq(day(p2), 4, "the rejoin is on Day 4")
eq(infoOf(p2):GetAttribute("AnomalyId"), "door_extra", "with the same anomaly (not a re-roll; the catalog is back to all 24)")
eq(infoOf(p2):GetAttribute("Clean"), false, "and the same roll")
truthy(fingerprint(zoneOf(p2)) == fp4, "and the same hall, part for part")
answer(p2, true); h:advance(0.2)
eq(day(p2), 5, "the restored pass is scored like any other (Day 5)")

--============================================================ 2. a wrong call is saved at once, without its pass
answer(p2, false)
h:advance(0.1) -- inside the 2.5 s death beat
local rw = storedRun()
truthy(rw ~= nil and rw.day == 1, "a wrong call writes the reset to the store at once (stored day " .. tostring(rw and rw.day) .. ")")
truthy(rw ~= nil and rw.pass == nil, "without the pass whose answer the player was just shown")
h:leave(p2) -- during the death beat
h:advance(3)
local p3 = h:join("Rejoiner", UID)
h:advance(0.2)
eq(day(p3), 1, "leaving during the death beat does not undo the wrong call: the rejoin is on Day 1")
truthy(infoOf(p3) ~= nil and infoOf(p3):GetAttribute("Serial") == 1, "with a fresh pass")
h:leave(p3)
h:advance(0.2)

--============================================================ 3. the read-only window
local function seed(run, lockedBy: string?)
	local rec = store.__data[KEY] or {}
	rec.run = run
	rec.lock = if lockedBy then { token = lockedBy, at = os.time() } else nil
	store.__data[KEY] = rec
end
local function releaseForeignLock(newRun)
	local rec = store.__data[KEY]
	rec.lock = nil
	if newRun ~= nil then rec.run = newRun end
end

-- 3a. the stored run changed while this session was read-only: the other session's reset wins
seed({ id = "run-A", day = 9, pass = { clean = true } }, "another-server")
local q1 = h:join("Rejoiner", UID)
h:advance(0.2)
eq(q1:GetAttribute("SavesRun"), false, "a session locked out of the save says it does not save the run")
eq(day(q1), 9, "it starts from the stored run (Day 9), read-only")
eq(infoOf(q1):GetAttribute("Clean"), true, "on the stored pass")
answer(q1, true); h:advance(0.2)
eq(day(q1), 10, "and can play on (Day 10, not saved)")
releaseForeignLock({ id = "run-B", day = 1 }) -- the other session's last write: a wrong call's reset
h:advance(Config.Save.AutosaveSeconds + 1)
eq(q1:GetAttribute("SavesRun"), true, "once the lock is free the session takes it")
eq(day(q1), 1, "and adopts the stored run the other session reset: a stale copy cannot resume it")
h:advance(Config.Save.AutosaveSeconds + 1)
local ra = storedRun()
truthy(ra ~= nil and ra.day == 1, "the store keeps Day 1 (" .. tostring(ra and ra.day) .. ")")
h:leave(q1)
h:advance(0.2)

-- 3b. the stored run did not change: the session keeps its own progress on it
seed({ id = "run-C", day = 9, pass = { clean = true } }, "another-server")
local q2 = h:join("Rejoiner", UID)
h:advance(0.2)
answer(q2, true); h:advance(0.2)
eq(day(q2), 10, "read-only on the stored run: Day 10")
releaseForeignLock(nil)
h:advance(Config.Save.AutosaveSeconds + 1)
eq(q2:GetAttribute("SavesRun"), true, "the lock is taken")
eq(day(q2), 10, "the session keeps its own progress on the unchanged run")
h:advance(Config.Save.AutosaveSeconds + 1)
local rb = storedRun()
truthy(rb ~= nil and rb.day == 10, "and saves it (" .. tostring(rb and rb.day) .. ")")
h:leave(q2)
h:advance(0.2)

-- 3c. a wrong call made while read-only stands, whatever the store says
seed({ id = "run-D", day = 9, pass = { clean = true } }, "another-server")
local q3 = h:join("Rejoiner", UID)
h:advance(0.2)
answer(q3, false); h:advance(3)
eq(day(q3), 1, "a wrong call while read-only: Day 1")
releaseForeignLock({ id = "run-E", day = 12 })
h:advance(Config.Save.AutosaveSeconds + 1)
eq(day(q3), 1, "the session's own reset stands when it takes the lock")
h:advance(Config.Save.AutosaveSeconds + 1)
local rc = storedRun()
truthy(rc ~= nil and rc.day == 1, "and is what gets saved (" .. tostring(rc and rc.day) .. ")")
h:leave(q3)
h:advance(0.2)

--============================================================ nonsense in the store never breaks a join
seed({ id = 5, day = "lots", pass = { clean = "yes", anomalyId = "no_such_anomaly" } }, nil)
local q4 = h:join("Rejoiner", UID)
h:advance(0.2)
eq(day(q4), 1, "a malformed stored run is ignored: Day 1")
truthy(infoOf(q4) ~= nil and type(infoOf(q4):GetAttribute("Clean")) == "boolean", "with a fresh, valid pass")
h:leave(q4)
h:advance(0.2)
seed({ id = "run-F", day = 7, pass = { clean = false, anomalyId = "no_such_anomaly" } }, nil)
local q5 = h:join("Rejoiner", UID)
h:advance(0.2)
eq(day(q5), 7, "a stored run whose anomaly this catalog no longer has keeps its Day (7)")
local id5 = infoOf(q5):GetAttribute("AnomalyId")
truthy(id5 == nil or A.Catalog[1] ~= nil and id5 ~= "no_such_anomaly", "and gets a valid roll instead of the unknown anomaly (" .. tostring(id5) .. ")")
h:leave(q5)

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomaly_rejoin: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly rejoin check failed", 0)
end
