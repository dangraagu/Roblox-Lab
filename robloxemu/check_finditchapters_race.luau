-- Find It! Chapters: a write that answers late never rolls the session back (REVIEW-1 round 2, C4), through the REAL
-- server.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_race.luau 2>&1
--
-- Round 2 found that the session took its profile from whichever write ANSWERED last, not from the newest one: an
-- autosave whose UpdateAsync answered 9 s after its transform ran landed after the chapter-6 clear's own write, put
-- the session back to 5 chapters, and Next said "Clear Chapter 6 first" for ~12 s. Now every write is numbered when
-- its transform runs, and an answer older than the last one applied changes nothing. The UpdateAsync wrapper below
-- delays the answer of exactly one write (the boot+20 autosave) after its transform ran, as a slow DataStore would.
-- Adapted from the round-2 reviewer's rev_race.luau (which printed, and asserted nothing).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-race", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local CFrame, Enum = dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local NOW = os.time()
local LAT = 9
local stars = {}
for ch = 1, 5 do stars["c" .. ch] = { f = true } end
store:SetAsync("u_701", { data = { v = 1, book = { cleared = 5, stars = stars }, daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
	solved = 5, solvedAt = NOW - 86400, boarded = 5, seenIntro = true, firstJoin = NOW - 86400 * 9 }, lock = { session = "", ["until"] = 0 } })
local orig = store.UpdateAsync
local slowNext, slowRan = 0, nil
store.UpdateAsync = function(self, key, tf)
	local lat = slowNext
	slowNext = 0
	local r = orig(self, key, tf)
	if lat > 0 then
		slowRan = h.scheduler:now()
		task.wait(lat) -- the transform ran and the record is written; the ANSWER comes late
	end
	return r
end
assert(h:tryRun("server/Main.server"))
local BOOT = h.scheduler:now()
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local remotes = RS:FindFirstChild("FindItRemotes")
local function frame(d) RunService.Heartbeat:Fire(d); h:advance(d) end
local function run(s) local t = 0 while t < s - 1e-9 do local d = math.min(0.1, s - t); frame(d); t += d end end
local function last(name) local s = remotes:FindFirstChild(name):sentTo(h.Players:GetPlayers()[1]); return s[#s] and s[#s].args[1] end
local function since() return h.scheduler:now() - BOOT end
local function untilT(t) if since() < t then run(t - since()) end end
local plr = h:join("Ann", 701)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, ws)
char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
local hrp = char:FindFirstChild("HumanoidRootPart")
h:advance(0.5)
local function fire(name, ...) remotes:FindFirstChild(name):simulateFireServer(plr, ...) end

-- clear `ch`, searching each hiding prop; `onLast` runs before the last search
local function clear(ch, onLast)
	fire("Open", ch)
	h:advance(0.05)
	while last("State").state == "intro" do run(0.1) end
	local pl = last("Room")
	local rig = HttpService:JSONDecode(ServerStorage.FindIt.Attempts:FindFirstChild("701").Value)
	for i, id in rig.hidden do
		if i == #rig.hidden and onLast then onLast() end
		for _, q in pl.props do if q.id == id then hrp.CFrame = CFrame.new(pl.origin[1] + q.x, 3, pl.origin[3] + q.z) end end
		fire("Search", id)
		run(1.05)
	end
end
local function nextUntil(want, budget)
	local presses = 0
	local t0 = since()
	while last("State").chapter ~= want and since() - t0 < budget do
		run(1.2)
		fire("Next")
		h:advance(0.1)
		presses += 1
	end
	return presses, since() - t0
end

--============================================================ C4: the boot+20 autosave answers 9 s late; chapter 6 is cleared meanwhile
untilT(11)
clear(6, function()
	untilT(19.5)
	slowNext = LAT -- the next UpdateAsync (the boot+20 autosave) answers 9 s after its transform
end)
untilT(20 + LAT + 1)
truthy(slowRan ~= nil and math.abs(slowRan - BOOT - 20) < 0.5, string.format("C4: the slow write was the boot+20 autosave (transform at boot+%.1f): the scenario is real", (slowRan or 0) - BOOT))
eq(store:GetAsync("u_701").data.book.cleared, 6, "C4: the store holds chapter 6 (the clear's own write landed meanwhile)")
eq(last("Profile").cleared, 6, "C4: the Case Book shows 6")
local presses, took = nextUntil(7, 20)
eq(presses, 1, string.format("C4: after the late answer, the first Next opens chapter 7 (%d presses, %.1f s)", presses, took))
eq(last("State").chapter, 7, "C4: chapter 7 is open")
local refused = 0
for _, x in remotes.Toast:sentTo(plr) do if string.find(x.args[1].text, "Clear Chapter 6 first", 1, true) then refused += 1 end end
eq(refused, 0, "C4: the player is never told to clear the chapter the store already has")
fire("Hub")
run(1.2)

--============================================================ control: no late answer at the next autosave
untilT(52)
clear(7, nil)
local t = 0
while (last("State").result or {}).saving and t < 10 do run(0.1); t += 0.1 end
local p2 = nextUntil(8, 20)
eq(p2, 1, "control: Next opens chapter 8 at once")
eq(store:GetAsync("u_701").data.book.cleared, 7, "control: chapter 7 stored")

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it race: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_race failed", 0) end
