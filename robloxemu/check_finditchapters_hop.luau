-- Find It! Chapters: a server hop onto a profile lock the old server still holds (REVIEW-1 round 2, C3), through the
-- REAL server.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_hop.luau 2>&1
--
-- Round 2 found that a returning player who joins while the old server is still releasing the lock got a fresh,
-- empty Case Book for up to ~20 s (the load was retried only on the 20 s autosave tick), a toast saying the session
-- "won't save" (false: clears made meanwhile are merged when the load lands, round 1 A3), and a press of the Case
-- Book threw them into Chapter 1 (the first-timer shortcut fired on the empty book). Now:
--   * a locked or failed first load is retried after Config.Save.QuickRetrySeconds, up to QuickRetries times, before
--     the 20 s tick takes over: three hoppers whose old lock is freed 1 s after they join (at autosave phases 0, 10
--     and 18 s) are ready within 5 s of the lock being freed, wherever the 20 s tick stands;
--   * the Case Book prompt opens a room straight away only for a LOADED first-timer (state ready or nostore); a
--     hopper whose load is still waiting gets the menu (the HUD says it is loading: check_finditchapters_hud);
--   * no toast says the session won't save; the locked toast says it is retrying, once, also when the other server
--     keeps the lock for good (Stuck).
-- Adapted from the round-2 reviewer's rev_hop.luau (which printed, and asserted nothing).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-hop", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local CFrame, Enum = dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local NOW = os.time()
local stars = {}
for ch = 1, 14 do stars["c" .. ch] = { f = true, w = true, s = true } end
local function seed(uid, holder)
	store:SetAsync("u_" .. uid, { data = { v = 1, book = { cleared = 14, stars = stars }, daily = { lastDay = math.floor(NOW / 86400) - 1, solved = 9, streak = 9, bestStreak = 9 },
		solved = 23, solvedAt = NOW - 86400, boarded = 23, seenIntro = true, firstJoin = NOW - 30 * 86400 },
		lock = { session = holder, ["until"] = NOW + 3600 } })
end
for _, uid in { 1201, 1202, 1203 } do seed(uid, "old-server") end
seed(1204, "busy-server")
assert(h:tryRun("server/Main.server"))
local BOOT = h.scheduler:now()
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local ST = Config.Save.Text
local RunService = h.game:GetService("RunService")
local remotes = RS:FindFirstChild("FindItRemotes")
local function frame(d) RunService.Heartbeat:Fire(d); h:advance(d) end
local function run(s) local t = 0 while t < s - 1e-9 do local d = math.min(0.1, s - t); frame(d); t += d end end
local function last(name, p) local s = remotes:FindFirstChild(name):sentTo(p.plr); return s[#s] and s[#s].args[1] end
local function since() return h.scheduler:now() - BOOT end
local function untilT(t) if since() < t then run(t - since()) end end
local function toasts(p)
	local out = {}
	for _, x in remotes.Toast:sentTo(p.plr) do table.insert(out, x.args[1].text) end
	return out
end
local book = ws.FindItWorld.Hub.CaseBook
local function join(name, uid)
	local plr = h:join(name, uid)
	h:advance(0.5)
	local char = h.Players:simulateSpawn(plr, ws)
	char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
	h:advance(0.5)
	return { plr = plr, hrp = char:FindFirstChild("HumanoidRootPart"), uid = uid, name = name }
end
local function free(uid)
	store:UpdateAsync("u_" .. uid, function(rec) rec.lock = { session = "", ["until"] = 0 }; return rec end)
end

-- the stuck one first: another server keeps the lock for good
local S = join("Stuck", 1204)

for _, case in { { uid = 1201, at = 2 }, { uid = 1202, at = 10 }, { uid = 1203, at = 18 } } do
	-- join when the 20 s autosave tick stands at `at` seconds (the next such moment)
	local A = Config.Save.AutosaveSeconds
	untilT(math.ceil((since() - case.at - 1) / A) * A + case.at - 1)
	local p = join("Hopper" .. case.uid, case.uid)
	local phase = since() % Config.Save.AutosaveSeconds
	local tag = string.format("C3 hopper at autosave phase %.1f s", phase)
	eq(last("Profile", p).state, "locked", tag .. ": the old server still holds the lock (the scenario is real)")
	run(1)
	free(case.uid)
	local freedAt = since()
	-- the player walks to the lectern and presses E while the load is still waiting
	p.hrp.CFrame = CFrame.new(book.Position.X, 3, book.Position.Z + 4)
	run(0.2)
	local states0 = #remotes.State:sentTo(p.plr)
	book:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(p.plr)
	h:advance(0.1)
	local st = last("State", p)
	truthy(st == nil or st.where == "hub", tag .. ": the Case Book prompt does not throw a loading player into a room")
	eq(#remotes.State:sentTo(p.plr) - states0, 0, tag .. ": ... no room state was sent")
	eq(last("Notice", p) and last("Notice", p).kind, "casebook", tag .. ": ... it opens the Case Book menu")
	local t = 0
	while last("Profile", p).state ~= "ready" and t < 30 do run(0.1); t += 0.1 end
	local wait = since() - freedAt
	eq(last("Profile", p).state, "ready", tag .. ": the load lands")
	print(string.format("  %s: ready %.1f s after the lock was freed", tag, wait))
	truthy(wait <= 5, string.format("%s: ready %.1f s after the lock was freed (<= 5 s, the 20 s tick would be up to 20)", tag, wait))
	eq(last("Profile", p).cleared, 14, tag .. ": the Case Book shows 14 chapters")
	eq(last("Profile", p).continue, 15, tag .. ": Continue is chapter 15")
	eq(p.plr.leaderstats.Solved.Value, 23, tag .. ": leaderstats 23")
	local lies = 0
	for _, x in toasts(p) do if string.find(string.lower(x), "won't save", 1, true) then lies += 1 end end
	eq(lies, 0, tag .. ": no toast says the session won't save")
end

-- Stuck: the other server never lets go. Quick retries, then the 20 s tick; one toast, worded as a retry.
do
	untilT(40)
	eq(last("Profile", S).state, "locked", "C3 stuck: still locked after 40 s")
	local n, said = 0, nil
	for _, x in toasts(S) do
		if x == ST.Locked then n += 1 end
		said = said or x
	end
	eq(n, 1, "C3 stuck: the locked toast is said once, not at every retry")
	truthy(string.find(string.lower(ST.Locked), "won't save", 1, true) == nil and string.find(string.lower(ST.Locked), "retry", 1, true) ~= nil,
		"C3 stuck: it says the server keeps retrying: " .. ST.Locked)
	S.hrp.CFrame = CFrame.new(book.Position.X, 3, book.Position.Z + 4)
	run(0.2)
	book:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(S.plr)
	h:advance(0.1)
	eq(last("Notice", S) and last("Notice", S).kind, "casebook", "C3 stuck: the Case Book prompt opens the menu, never Chapter 1")
	-- the player may still choose a chapter in the menu: chapter 1 opens (it is queued and merged when the lock frees)
	remotes.Open:simulateFireServer(S.plr, 1)
	h:advance(0.1)
	eq(last("State", S).chapter, 1, "C3 stuck: a chapter picked in the menu still opens")
end

-- control: a real first-timer (loaded, nothing cleared) still goes straight into Chapter 1
do
	local f = join("Newbie", 1299)
	run(1)
	eq(last("Profile", f).state, "ready", "control: a new player's load lands at once")
	f.hrp.CFrame = CFrame.new(book.Position.X, 3, book.Position.Z + 4)
	run(0.2)
	book:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(f.plr)
	h:advance(0.1)
	eq(last("State", f) and last("State", f).where, "room", "control: the Case Book prompt takes a loaded first-timer straight into a room")
	eq(last("State", f) and last("State", f).chapter, 1, "control: ... Chapter 1")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it hop: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_hop failed", 0) end
