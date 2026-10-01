-- Grow a Crystal — a session that cannot save says so, and saves again as soon as it can (standard §1, pass 2b).
-- Run: luau check_growacrystal_rejoin.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- Measured on 2026-10-01 before the fix, through the real server:
--   * a player who rejoined within 45 s of a server crash (the dead server's lock still on the record) got NO
--     message and a session that never saved, not even two minutes later when the lock had long expired: they
--     bought a seed, and the record still said 1234 dust;
--   * a returning player (4321 dust) whose load call failed once was shown a brand-new profile (30 dust), told
--     nothing, and nothing they did was saved;
--   * a server with no DataStore (Studio with API access off) told the player nothing either.
-- The fork-tower/escape-room-lab pattern: tell the player, retry on every autosave, take the lock back when it is
-- free. What must hold:
--   * locked at join: told once; codes and chambers refused (nothing could persist); when the dead server's lock
--     expires and nobody has written the record since this session read it, this session takes the lock and
--     saves what the player did meanwhile; told that saving is back;
--   * locked by a server that keeps renewing: never overwritten; when that server releases with newer data, this
--     session loads that data (it is newer than the copy it played on), takes the lock and says so;
--   * a failed load: told; nothing granted that could not persist; the next autosave loads the real profile and
--     rebuilds the cavern to it (chambers, crystals);
--   * Studio with API access off (every call fails): the session never saves, says so once, never "retries"
--     forever, and grants the public codes for the session (nothing persists, so nothing can be duplicated;
--     the clip list in MARKETING.md is staged that way, check_growacrystal_clips);
--   * every message reads at 12 px or more on every screen.
-- os.time is the emulator's virtual clock (like check_growacrystal_walk) so a 45-s lock can expire.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function has(s, w) return type(s) == "string" and string.find(string.lower(s), string.lower(w), 1, true) ~= nil end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })

local realOs = os
local T0 = realOs.time()
os = setmetatable({
	time = function(t)
		if t ~= nil then return realOs.time(t) end
		return T0 + math.floor(h.scheduler:now())
	end,
}, { __index = realOs })

local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
local function data(d)
	local out = { dust = 100, seeds = { [1] = 3 }, chambers = 1, luckLevel = 0, growthLevel = 0,
		plants = {}, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {} }
	for k, v in d or {} do out[k] = v end
	return out
end
-- a server that crashed 0 s ago: its 45-s lock is on the record and nobody will ever renew or release it
store:SetAsync("u_5050", { jobId = "CRASHED", session = "CRASHED-S", lockUntil = T0 + 45, data = data({ dust = 1234 }) })
-- a server that is still alive (the player teleported out of it): it renews, then releases with newer data
store:SetAsync("u_5151", { jobId = "LIVE", session = "LIVE-S", lockUntil = T0 + 45, data = data({ dust = 500, chambers = 2 }) })
-- a returning player whose load call is going to fail once
store:SetAsync("u_6060", { data = data({ dust = 4321, chambers = 3, plants = { [1] = { tier = 1, at = T0 - 1000 } } }) })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local R = RS:FindFirstChild("CrystalRemotes")
local State, Toast, Redeem, Buy = R:FindFirstChild("State"), R:FindFirstChild("Toast"), R:FindFirstChild("Redeem"), R:FindFirstChild("Buy")
local AUTOSAVE = Config.Save.AutosaveSeconds

local function lastState(plr)
	local s = State:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function toasts(plr): { string }
	local out = {}
	for _, r in Toast:sentTo(plr) do table.insert(out, tostring(r.args[1])) end
	return out
end
local function lastToast(plr) local t = toasts(plr); return t[#t] end
local function until_(t: number) h:advance(math.max(0, t - h.scheduler:now())) end
local allMsgs, seen = {}, {}
local function collect(plr)
	for _, m in toasts(plr) do
		if not seen[m] then seen[m] = true; table.insert(allMsgs, m) end
	end
end

--=========================================================================== 1. joined while a crashed server's lock is on the record

local crash = h:join("Rejoiner", 5050)
local held = h:join("Teleported", 5151)
h:advance(1)
local ct = toasts(crash)
eq(#ct, 1, "locked at join: the player is told at once")
truthy(has(ct[1], "another server"), string.format("... why: the save is open on another server (%q)", tostring(ct[1])))
truthy(has(ct[1], "retry"), string.format("... and that it is retrying (%q)", tostring(ct[1])))
eq((lastState(crash) or {}).dust, 1234, "the saved profile is shown while waiting")
local res = Redeem:simulateInvokeServer(crash, "WELCOME")
truthy(type(res) == "table" and res.ok == false, "a code is refused while the session cannot save (" .. tostring(res and res.reason) .. ")")
local t0 = #toasts(crash)
Buy:simulateFireServer(crash, "chamber")
h:advance(0.5)
eq((lastState(crash) or {}).chambers, 1, "a chamber is not bought on a copy that cannot save")
truthy(#toasts(crash) > t0 and has(lastToast(crash), "save"), string.format("... and the player is told why (%q)", tostring(lastToast(crash))))
Buy:simulateFireServer(crash, "seed", 1)
h:advance(0.5)
eq((lastState(crash) or {}).dust, 1234 - Config.Economy.SeedCost[1], "playing on goes on: a seed is bought")
Buy:simulateFireServer(held, "seed", 1) -- the other waiting player plays on too (on a copy that will turn out stale)
h:advance(0.5)

-- The live server renews its lock 5 s before each of this server's autosaves (15, 35, 55, 75 s), for as long
-- as the test runs sections 1 and 2; the crashed server never does.
local function renewLive()
	local r = store:GetAsync("u_5151")
	r.lockUntil = os.time() + 45
	store:SetAsync("u_5151", r)
end
local function untilRenewing(t: number)
	for _, at in { AUTOSAVE - 5, 2 * AUTOSAVE - 5, 3 * AUTOSAVE - 5, 4 * AUTOSAVE - 5 } do
		if at > h.scheduler:now() and at <= t then
			until_(at)
			renewLive()
		end
	end
	until_(t)
end

untilRenewing(2 * AUTOSAVE + 1) -- two autosaves while the dead server's lock is still on the record
local rec = store:GetAsync("u_5050")
eq(rec.jobId, "CRASHED", "while the lock is held, this session writes nothing (" .. tostring(rec.jobId) .. ")")
eq(rec.data.dust, 1234, "... the record is untouched")

untilRenewing(3 * AUTOSAVE + 1) -- the lock (45 s) has expired by the third autosave
rec = store:GetAsync("u_5050")
eq(rec.jobId, h.game.JobId, "the lock expired: this session takes it")
truthy(rec.session ~= nil and rec.session ~= "CRASHED-S", "with a session token of its own")
eq(rec.data.dust, 1234 - Config.Economy.SeedCost[1], "and saves what the player did while waiting (nobody wrote the record since)")
truthy(has(lastToast(crash), "save"), string.format("the player is told saving is back (%q)", tostring(lastToast(crash))))
local res2 = Redeem:simulateInvokeServer(crash, "WELCOME")
truthy(type(res2) == "table" and res2.ok == true, "a code redeems once the session holds the lock")
eq(store:GetAsync("u_5050").data.redeemed.WELCOME, true, "... and is saved with it")
Buy:simulateFireServer(crash, "chamber")
h:advance(0.5)
eq((lastState(crash) or {}).chambers, 2, "and a chamber can be bought again")

--=========================================================================== 2. a live server renews, then releases with newer data

untilRenewing(4 * AUTOSAVE + 1)
local r2 = store:GetAsync("u_5151")
eq(r2.jobId, "LIVE", "a lock that keeps being renewed is never taken (four autosaves)")
eq(r2.data.dust, 500, "... and the live server's record is never overwritten")
eq(#toasts(held), 1, "the player whose other server is alive was told once, not on every autosave")
-- the live server releases, with the progress it made after this session read the record
until_(4 * AUTOSAVE + 10)
store:SetAsync("u_5151", { jobId = "LIVE", session = "LIVE-S", lockUntil = 0, data = data({ dust = 777, chambers = 3 }) })
until_(5 * AUTOSAVE + 1)
local r3 = store:GetAsync("u_5151")
eq(r3.jobId, h.game.JobId, "released: this session takes the lock")
eq((lastState(held) or {}).dust, 777, "and plays on the NEWER data the other server saved (not the stale copy it waited on)")
eq((lastState(held) or {}).chambers, 3, "... chambers included")
truthy(h.workspace:FindFirstChild("Socket_5151_18", true) ~= nil, "the cavern was rebuilt to chamber 3 (socket 18 is there)")
eq(r3.data.dust, 777, "the record keeps the other server's dust")
truthy(has(lastToast(held), "load"), string.format("the player is told their save loaded (%q)", tostring(lastToast(held))))

--=========================================================================== 3. the load call fails once

store.__failNext = true
local unlucky = h:join("Unlucky", 6060)
h:advance(1)
local ut = toasts(unlucky)
eq(#ut, 1, "a failed load: the player is told at once")
truthy(has(ut[1], "load") and has(ut[1], "retry"), string.format("... that the save could not load and it is retrying (%q)", tostring(ut[1])))
local resU = Redeem:simulateInvokeServer(unlucky, "MYTHIC")
truthy(type(resU) == "table" and resU.ok == false, "no code is granted that could not persist")
local tU = #toasts(unlucky)
Buy:simulateFireServer(unlucky, "chamber")
h:advance(0.5)
truthy(#toasts(unlucky) > tU and has(lastToast(unlucky), "save"), "a chamber is refused, with the reason")
until_(h.scheduler:now() + AUTOSAVE + 1)
local su = lastState(unlucky) or {}
eq(su.dust, 4321, "the next autosave loaded the real profile")
eq(su.chambers, 3, "... with its chambers")
truthy(h.workspace:FindFirstChild("Socket_6060_18", true) ~= nil, "the cavern was rebuilt to chamber 3")
local s1 = h.workspace:FindFirstChild("Socket_6060_1", true)
truthy(s1 ~= nil and s1:FindFirstChild("Crystal") ~= nil, "the saved crystal stands on socket 1")
eq(store:GetAsync("u_6060").jobId, h.game.JobId, "and the session holds the lock")
truthy(has(lastToast(unlucky), "load"), string.format("the player is told their save loaded (%q)", tostring(lastToast(unlucky))))

--=========================================================================== 3b. a failed load that then finds the record locked

-- The first retry can read the record but not take it: it now knows the real profile, shows it, and waits for the
-- lock like a session that was locked at join.
local tNow = os.time()
store:SetAsync("u_6161", { jobId = "CRASHED-2", session = "C2", lockUntil = tNow + 30, data = data({ dust = 2222, chambers = 2 }) })
store.__failNext = true
local both = h:join("Both", 6161)
h:advance(1)
eq((lastState(both) or {}).dust, Config.Economy.StartDust, "a failed load shows the starting profile at first")
local nextSave = (math.floor(h.scheduler:now() / AUTOSAVE) + 1) * AUTOSAVE
until_(nextSave + 1)
eq((lastState(both) or {}).dust, 2222, "the first retry, still locked out, loads and shows the real profile")
eq((lastState(both) or {}).chambers, 2, "... with its chambers")
truthy(h.workspace:FindFirstChild("Socket_6161_12", true) ~= nil, "and builds them (socket 12)")
eq(store:GetAsync("u_6161").jobId, "CRASHED-2", "but does not write a record that is still locked")
until_(nextSave + 2 * AUTOSAVE + 1) -- the 30-s lock is gone by the second retry after that
eq(store:GetAsync("u_6161").jobId, h.game.JobId, "once the lock is gone, the session takes it")
eq(store:GetAsync("u_6161").data.dust, 2222, "and the record keeps the real profile")
collect(both)
h:leave(both)
h:advance(1)

--=========================================================================== 4. leaving releases what was taken

for _, p in { crash, held, unlucky } do collect(p) end
h:leave(crash); h:leave(held); h:leave(unlucky)
h:advance(1)
for _, uid in { 5050, 5151, 6060 } do
	eq(store:GetAsync("u_" .. uid).lockUntil, 0, "u_" .. uid .. ": leaving releases the lock")
end

--=========================================================================== 5. Studio with API access off: every call fails

-- A place opened in Studio with "Enable Studio Access to API Services" off has a DataStore object whose every call
-- raises. Nothing can ever save in that session, so it must not "retry" every 20 s for the rest of the session.
rawset(h.game:GetService("RunService"), "IsStudio", function() return true end)
store.__failAll = true
local studio = h:join("Studio", 7171)
h:advance(1)
local st = toasts(studio)
eq(#st, 1, "Studio without API access: told once at join")
truthy(has(st[1], "won't save"), string.format("... that progress here won't save (%q)", tostring(st[1])))
local resS = Redeem:simulateInvokeServer(studio, "WELCOME")
truthy(type(resS) == "table" and resS.ok == true, "a session that can never save grants the public codes for the session")
eq((lastState(studio) or {}).dust, Config.Economy.StartDust + 100, "... WELCOME's 100 dust")
h:advance(3 * AUTOSAVE)
eq(#toasts(studio), 1, "and does not retry or nag on every autosave")
collect(studio)
store.__failAll = false

--=========================================================================== 6. every message is readable on every screen

do
	h.game:GetService("RunService"):setIsServer(false)
	h.Players.LocalPlayer = studio
	assert(h:tryRun("client/Hud.client"))
	h:advance(0.2)
	local HudCheck = require("./emu/hudcheck")
	truthy(#allMsgs >= 6, string.format("%d different messages collected", #allMsgs))
	for _, m in allMsgs do print("    toast: " .. m) end
	local worst, worstAt = math.huge, ""
	for _, v in HudCheck.VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.1)
		for _, m in allMsgs do
			Toast.OnClientEvent:Fire(m)
			h:advance(0.05)
			for _, g in studio.PlayerGui:GetChildren() do h:settleLayouts(g, v.w, v.h) end
			local shown = nil
			for _, r in h:guiRects(studio.PlayerGui.CrystalHud, v.w, v.h) do
				if r.shown and r.class == "TextLabel" and r.obj.Text == m then shown = r end
			end
			if shown then
				local sw = shown.sw
				local sc = shown.obj:FindFirstChildOfClass("UISizeConstraint")
				if sc and sc.MaxSize.X < math.huge then sw = math.min(sw, sc.MaxSize.X * shown.scale) end
				local px = math.min(shown.sh, sw / (0.6 * utf8.len(m)))
				local cc = shown.obj:FindFirstChildOfClass("UITextSizeConstraint")
				if cc then px = math.min(px, cc.MaxTextSize * shown.scale) end
				if px < worst then worst, worstAt = px, string.format("%s %dx%d: %q", v.name, v.w, v.h, m) end
			else
				worst, worstAt = -1, v.name .. ": not on screen: " .. m
			end
		end
	end
	truthy(worst >= 12, string.format("every save message reads at 12 px or more on every screen (smallest %.1f px, %s)", worst, worstAt))
	print(string.format("  smallest save-message text: %.1f px (%s)", worst, worstAt))
end

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal rejoin: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal rejoin check failed", 0) end
