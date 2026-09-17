-- Lost & Found Depot — saving when the DataStore TAKES TIME, and the server paths a client can
-- spam. REVIEW-1 R1-1..R1-5, R2-6 and the "deposit after zero" finding, as assertions.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_save.luau
--
-- WHY THIS FILE EXISTS. robloxemu's DataStore answers instantly, and Roblox's does not. Every
-- defect below lives in the gap between a request leaving and its answer coming back, so every
-- other gate was blind to it:
--   * an autosave that fires while the PlayerRemoving release is in flight re-locked the record for
--     a session that no longer existed, and the player's next session was read-only (all 12 of 12
--     after a mass leave);
--   * a leaver's bay was only freed after the release save returned, so a newcomer who joined in
--     that window got no bay and stood in the Break Room forever;
--   * a session that did not get the lock at join (a crashed server's lock, a rejoin during the
--     first load, or a load that raised) stayed read-only for the whole session, and nothing it
--     earned was ever written;
--   * one load error dropped a veteran into the tutorial with 0 cash;
--   * a shift that timed out after the player left was saved as played.
-- And two paths a client drives at will: 100 door presses were 100 DataStore writes, and 10,000
-- Select events were 9,999 full State payloads (14.4 MB).
--
-- THE LATENCY MODEL. `UpdateAsync` waits `latency` seconds of virtual clock and then runs the real
-- emulator call, so the transform sees the store AT COMMIT TIME. That is Roblox's contract too: an
-- UpdateAsync whose key changed between its read and its write re-runs its transform, so a
-- transform always decides against the value it actually overwrites. Requests do not queue behind
-- each other; each takes `latency`.
--
-- One harness per process (it installs globals), so the scenarios run in sequence on one server
-- and each uses its own user ids.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-save", viewport = { 1280, 720 }, touch = false })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
do -- the salt, pinned, so a failure replays
	local realRandom = Random
	local unseeded = 0
	Random = {
		new = function(seed)
			if seed == nil then
				unseeded += 1
				return realRandom.new(4400 + unseeded * 31)
			end
			return realRandom.new(seed)
		end,
	}
end

-- Instances the game makes, counted from boot. Installed BEFORE the server runs: Luau resolves
-- `Instance.new` once when a script loads, so a wrapper installed later is never called.
local instancesMade = 0
do
	local I = h.instance.Instance
	local realNew = I.new
	I.new = function(cls, ...)
		instancesMade += 1
		return realNew(cls, ...)
	end
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("LostFoundDepot_v1")
local realUpdate = getmetatable(store).UpdateAsync
local latency = 0
-- LOST ANSWERS: the next `landThenRaise` calls commit their write and THEN raise, as a request whose
-- response never came back. The emulator's own failure injection raises before writing, which
-- cannot show what a server does with a lock it took without knowing it.
local landThenRaise = 0
-- PER-REQUEST LATENCY: when non-empty, each request takes the next value in this list instead of
-- `latency`, so a request that left first can come back last.
local latencies = {}
rawset(store, "UpdateAsync", function(self, key, fn)
	local lat = if #latencies > 0 then table.remove(latencies, 1) else latency
	if lat > 0 and coroutine.isyieldable() then
		h.scheduler:wait(lat)
	end
	local out = realUpdate(self, key, fn)
	if landThenRaise > 0 then
		landThenRaise -= 1
		error("robloxemu (save check): the write landed, the answer was lost", 0)
	end
	return out
end)

local function vet(extra)
	local r = { v = 1, cash = 1000, cartLevel = 1, shoesLevel = 1, shifts = 7, perfects = 2, backlog = 120,
		bestPerfectSeconds = 90, endingSeen = false, redeemed = { SORTED = true } }
	for k, v in extra or {} do r[k] = v end
	return r
end

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot save: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
local BOOT = h.scheduler:now()
h:advance(1)

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Rules = h:_require(h.ReplicatedStorage:FindFirstChild("Rules"))
local remotes = h.ReplicatedStorage:FindFirstChild("DepotRemotes")
local StateEvent, NoticeEvent, SceneEvent, SelectEvent = remotes.State, remotes.Notice, remotes.Scene, remotes.Select
local AUTOSAVE = Config.Save.AutosaveSeconds

--============================================================================ helpers

local function state(plr)
	local s = StateEvent:sentTo(plr)
	return s[#s] and s[#s].args[1] or nil
end
local function noticeTexts(plr, from)
	local out = {}
	local all = NoticeEvent:sentTo(plr)
	for i = (from or 0) + 1, #all do table.insert(out, all[i].args[1].text) end
	return out
end
local function told(plr, text, from)
	for _, t in noticeTexts(plr, from) do
		if t == text then return true end
	end
	return false
end
local function rec(uid) return store:GetAsync("u_" .. uid) end
local function bayOf(plr) return plr.RespawnLocation and plr.RespawnLocation.Parent end
local function hrpOf(plr) return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") end
local function W(bay, x, y, z) return Vector3.new(bay.BayPad.Position.X + x, y, z) end
local function advanceTo(t) h:advance(math.max(0, t - h.scheduler:now())) end
-- the next autosave tick strictly after now (the loop started at BOOT)
local function nextTick()
	local now = h.scheduler:now()
	return BOOT + AUTOSAVE * (math.floor((now - BOOT) / AUTOSAVE) + 1)
end
-- joins and leaves on their own threads: a handler that yields on a slow store must be allowed to
local function join(name, uid)
	h.scheduler:spawn(function() h:join(name, uid) end)
	for _, p in h.Players:GetPlayers() do
		if p.UserId == uid and p.Parent ~= nil then return p end
	end
	return nil
end
local function joinSpawn(name, uid)
	local p = join(name, uid)
	h:advance(0.1)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	return p
end
local function leave(plr) h.scheduler:spawn(function() h:leave(plr) end) end

local BIN_OF_NAME, LETTER_OF_NAME = {}, {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end
local function readTray(bay)
	local out = {}
	for s = 1, 8 do
		local p = bay:FindFirstChild("Slot_" .. s)
		if p and p.Tag.Enabled then
			table.insert(out, { slot = s, click = p:FindFirstChildOfClass("ClickDetector"),
				line = (string.gsub(p.Tag.TagLine.Text, "<[^>]*>", "")), name = p.Tag.ItemName.Text })
		end
	end
	return out
end
local function readRules(bay)
	local text = bay.MemoBoard.SignGui.Label.Text
	for _, m in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, m), 1, true) then return Rules.withMemo(Config, m) end
	end
	return Rules.base(Config)
end
local function binFor(bay, entry)
	local mis = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
	local id = if mis then BIN_OF_NAME[mis]
		else (Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], readRules(bay)))
	for k = 1, 6 do
		local m = bay:FindFirstChild("Bin_" .. k)
		if BIN_OF_NAME[m.Sign.SignGui.Label.Text] == id then return m end
	end
end
local function standAtBin(plr, binModel)
	local bay = bayOf(plr)
	local b = binModel.Base.Position
	local flat = Vector3.new(b.X, 3, b.Z)
	hrpOf(plr).CFrame = CFrame.new(flat + (W(bay, 0, 3, 0) - flat).Unit * 5)
end
-- one correct first-try sort, read off the world; returns the cash it paid
local function sortOne(plr)
	local bay = bayOf(plr)
	hrpOf(plr).CFrame = CFrame.new(W(bay, 0, 3, 0))
	readTray(bay)[1].click.MouseClick:Fire(plr)
	h:advance(0.35)
	local before = state(plr).cash
	local entry = state(plr).shift.carried[1]
	local m = binFor(bay, entry)
	standAtBin(plr, m)
	SelectEvent:simulateFireServer(plr, 1)
	m.Base.Drop.Triggered:Fire(plr)
	return state(plr).cash - before
end

--============================================================================ R1-1: the release race

do
	local UID = 9001
	store:SetAsync("u_" .. UID, { data = vet() })
	local plr = joinSpawn("Hopper", UID)
	eq(state(plr).canSave, true, "CONTROL: a clean join holds the lock")
	-- leave 0.2 s before an autosave tick, with every store request taking 0.5 s
	advanceTo(nextTick() - 0.2)
	latency = 0.5
	leave(plr)
	h:advance(2)
	latency = 0
	local r = rec(UID)
	eq(r.lock, nil, "R1-1: an autosave firing while the release save is in flight does not re-lock the record")
	eq(r.data.cash, 1000, "... and the data is intact")
	local back = joinSpawn("Hopper", UID)
	eq(state(back).canSave, true, "R1-1: the player's next session can save")
	leave(back)
	h:advance(1)
end

do
	-- The other order: an autosave ALREADY IN FLIGHT when the player leaves, and slower than the
	-- release, so it lands after the release took the lock off. Only a check made inside the
	-- transform, against the record at commit time, can refuse it.
	local UID = 9009
	store:SetAsync("u_" .. UID, { data = vet() })
	local plr = joinSpawn("SlowSave", UID)
	advanceTo(nextTick() - 0.01)
	latencies = { 1.0, 0.2 } -- the autosave takes 1.0 s, the release 0.2 s
	h:advance(0.02) -- the autosave tick fires and its request leaves
	leave(plr)
	h:advance(2)
	latencies = {}
	eq(rec(UID).lock, nil, "R1-1: an autosave in flight when the player left, landing after the release, does not re-lock the record")
	h:advance(1)
end

do
	-- a release that raises once is tried again
	local UID = 9010
	store:SetAsync("u_" .. UID, { data = vet() })
	local plr = joinSpawn("Retry", UID)
	store.__failNext = true
	leave(plr)
	h:advance(5)
	eq(rec(UID).lock, nil, "a release save that raises once is retried, and the record is unlocked")
end

do
	-- the same race for a whole server at once (a mass leave, a shutdown migration)
	local players = {}
	for i = 1, 12 do
		store:SetAsync("u_" .. (9100 + i), { data = vet() })
		players[i] = joinSpawn("M" .. i, 9100 + i)
	end
	advanceTo(nextTick() - 0.2)
	latency = 0.5
	for _, p in players do leave(p) end
	h:advance(2)
	latency = 0
	local locked, readOnly = 0, 0
	for i = 1, 12 do
		if rec(9100 + i).lock ~= nil then locked += 1 end
	end
	eq(locked, 0, "R1-1: 12 players leaving together with slow saves leave 0 records locked")
	local back = {}
	for i = 1, 12 do
		back[i] = joinSpawn("M" .. i, 9100 + i)
		if state(back[i]).canSave ~= true then readOnly += 1 end
	end
	eq(readOnly, 0, "... and 0 of 12 come back read-only")
	for _, p in back do leave(p) end
	h:advance(1)
end

--============================================================================ a shift that ends after the player left

do
	local UID = 9002
	store:SetAsync("u_" .. UID, { data = vet() })
	local plr = joinSpawn("Quitter", UID)
	local bay = bayOf(plr)
	hrpOf(plr).CFrame = CFrame.new(W(bay, 0, 3, 0))
	readTray(bay)[1].click.MouseClick:Fire(plr)
	h:advance(0.35)
	local endsAt = state(plr).shift.endsAt
	advanceTo(endsAt - 0.6)
	latency = 1.0
	leave(plr)
	h:advance(3)
	latency = 0
	local r = rec(UID)
	eq(r.data.shifts, 7, "a shift the player walked out of is not saved as played, even when its clock hits zero during the release save")
	eq(r.lock, nil, "... and the record is not re-locked by that shift's end")
end

--============================================================================ R1-2: a full server

do
	local players = {}
	for i = 1, 12 do players[i] = joinSpawn("F" .. i, 9200 + i) end
	eq(#h.Players:GetPlayers(), 12, "CONTROL: 12 players seated")
	latency = 1.0
	leave(players[1])
	h:advance(0.3)
	local newcomer = join("Newcomer", 9300)
	h:advance(3)
	latency = 0
	h.Players:simulateSpawn(newcomer, h.workspace)
	h:advance(0.5)
	local st = state(newcomer)
	truthy(bayOf(newcomer) ~= nil, "R1-2: a player who joins while a leaver's save is in flight gets the freed bay")
	eq(st and st.loaded, true, "... and their profile loads")
	local root = hrpOf(newcomer)
	local bay = bayOf(newcomer)
	truthy(root ~= nil and bay ~= nil and math.abs(root.Position.X - bay.BayPad.Position.X) <= 3,
		"... and they stand on its pad, not in the Break Room")
	for i = 2, 12 do leave(players[i]) end
	leave(newcomer)
	h:advance(1)
end

--============================================================================ R1-3: a load that raises

do
	local UID = 9005
	store:SetAsync("u_" .. UID, { data = vet() })
	store.__failNext = true
	local plr = joinSpawn("Unlucky", UID)
	h:advance(5)
	local st = state(plr)
	eq(st.loaded, true, "R1-3: one DataStore error at join: the profile still loads")
	eq(st.cash, 1000, "... with the veteran's cash, not 0")
	eq(st.shifts, 7, "... and career, not the tutorial")
	eq(st.canSave, true, "... and saving")
	eq(told(plr, "Progress will not save this session."), false, "... and no read-only warning")
	leave(plr)
	h:advance(1)
end

do
	-- every attempt raises: the player plays from defaults, read-only; when the store comes back
	-- the session writes what it earned ON TOP of the real record, never over it
	local UID = 9006
	store:SetAsync("u_" .. UID, { data = vet() })
	store.__failAll = true
	local plr = joinSpawn("Outage", UID)
	h:advance(10)
	store.__failAll = false
	local st = state(plr)
	eq(st.loaded, true, "R1-3: a store that keeps raising still lets the player play")
	eq(st.canSave, false, "... read-only")
	truthy(told(plr, "Progress will not save this session."), "... and says so")
	local earned = sortOne(plr)
	truthy(earned > 0, "CONTROL: the read-only session earned " .. earned)
	eq(rec(UID).data.cash, 1000, "CONTROL: nothing was written while the store was down")
	local mark = #NoticeEvent:sentTo(plr)
	h:advance(AUTOSAVE + 1)
	st = state(plr)
	eq(st.canSave, true, "R2-6: once the store answers, the session takes the lock and saves again")
	truthy(told(plr, "Progress is saving again.", mark), "... and tells the player")
	local r = rec(UID)
	eq(r.data.cash, 1000 + earned, "... writing the stored 1000 PLUS what it earned, not its own default-based cash")
	eq(r.data.shifts, 7, "... keeping the stored career")
	eq(r.data.cartLevel, 1, "... and the stored upgrades")
	eq(r.data.backlog, 121, "... and adding its backlog")
	eq(st.cash, 1000 + earned, "the live profile now carries the merged cash")
	eq(st.shifts, 7, "... and the real career, for the next shift's stage")
	leave(plr)
	h:advance(1)
	eq(rec(UID).lock, nil, "... and releases the lock on leave")
end

do
	-- Every load attempt's write LANDS but its answer is lost: the store holds a lock this session
	-- took without knowing it. The session plays from defaults. It must never treat that lock as
	-- its own, because "its own" means "write the whole profile", and this profile is the defaults.
	local UID = 9007
	store:SetAsync("u_" .. UID, { data = vet() })
	landThenRaise = Config.Save.Attempts
	local plr = joinSpawn("LostAnswers", UID)
	h:advance(10)
	landThenRaise = 0
	eq(state(plr).canSave, false, "CONTROL: every load answer was lost, so the session is read-only on defaults")
	local earned = sortOne(plr)
	h:advance(AUTOSAVE + 1)
	local r = rec(UID)
	eq(r.data.cash, 1000, "a load whose writes landed unseen never lets the defaults overwrite the record (cash)")
	eq(r.data.shifts, 7, "... (career)")
	-- the stray lock expires, and the session's own delta lands on top
	r.lock.expires = os.time() - 1
	store:SetAsync("u_" .. UID, r)
	h:advance(AUTOSAVE + 1)
	eq(state(plr).canSave, true, "after the stray lock expires the session saves")
	eq(rec(UID).data.cash, 1000 + earned, "... what it earned, on top of the record")
	leave(plr)
	h:advance(1)
end

do
	-- A read-only session's MERGE write lands but its answer is lost, while the record holds progress
	-- this session never saw (another server's 5000 cash). The next write must not take that lock
	-- for its own and write the un-merged profile over the 5000.
	local UID = 9008
	store:SetAsync("u_" .. UID, { data = vet(), lock = { token = "OTHER-SERVER", expires = os.time() + 3600 } })
	local plr = joinSpawn("Unheard", UID)
	eq(state(plr).canSave, false, "CONTROL: read-only behind another server's live lock")
	local earned = sortOne(plr)
	-- the other server saved 5000 and died; its lock expires
	store:SetAsync("u_" .. UID, { data = vet({ cash = 5000 }), lock = { token = "OTHER-SERVER", expires = os.time() - 1 } })
	landThenRaise = 1
	h:advance(AUTOSAVE + 1)
	landThenRaise = 0
	eq(rec(UID).data.cash, 5000 + earned, "CONTROL: the merge write landed (5000 + what this session earned)")
	h:advance(AUTOSAVE + 1)
	truthy(rec(UID).data.cash >= 5000 + earned, "a merge whose answer was lost is never overwritten by the un-merged profile (stored "
		.. tostring(rec(UID).data.cash) .. ", un-merged would be " .. (1000 + earned) .. ")")
	leave(plr)
	h:advance(1)
end

do
	-- Two writes for one session in flight at once, landing out of order, at the moment a read-only
	-- session takes the lock: an autosave (slow) is in flight when the shift's clock runs out, and
	-- the shift end's own save (fast) lands first. The store meanwhile holds another server's 5000.
	-- Whatever lands last must not put back a snapshot older than the one before it.
	local UID = 9011
	store:SetAsync("u_" .. UID, { data = vet(), lock = { token = "OTHER-SERVER", expires = os.time() + 3600 } })
	local plr = joinSpawn("TwoWrites", UID)
	eq(state(plr).canSave, false, "CONTROL: read-only behind another server's live lock")
	-- start the clock so that zero falls 0.6 s after an autosave tick
	local tick = BOOT + AUTOSAVE * (math.floor((h.scheduler:now() + Config.Shift.Seconds + 5 - BOOT) / AUTOSAVE) + 1)
	advanceTo(tick + 0.6 - Config.Shift.Seconds)
	local earned = sortOne(plr)
	local endsAt = state(plr).shift.endsAt
	truthy(endsAt - tick > 0 and endsAt - tick < 1.0, string.format("CONTROL: an autosave tick at %.2f falls within 1 s before zero at %.2f", tick, endsAt))
	-- the other server's lock stays live until a second before that tick; then it has saved 5000
	-- and died
	advanceTo(tick - 1)
	eq(state(plr).canSave, false, "CONTROL: still read-only just before the tick")
	store:SetAsync("u_" .. UID, { data = vet({ cash = 5000 }), lock = { token = "OTHER-SERVER", expires = os.time() - 1 } })
	advanceTo(tick - 0.01)
	latencies = { 1.0, 0.2 }
	h:advance(1.5)
	latencies = {}
	eq(state(plr).shift.state, "SUMMARY", "CONTROL: the shift ended while the autosave was in flight")
	h:advance(1)
	local r = rec(UID)
	eq(r.data.cash, 5000 + earned, "out-of-order writes: the store keeps the other server's 5000 plus what this session earned")
	eq(r.data.shifts, 8, "... and the shift that just ended")
	leave(plr)
	h:advance(1)
end

--============================================================================ R2-6: a lock another session left behind

do
	local UID = 9003
	store:SetAsync("u_" .. UID, { data = vet() })
	local first = joinSpawn("Crash", UID)
	advanceTo(nextTick() + 1) -- the lock was just renewed
	store.__failAll = true -- the release save never lands: a crash, or an outage at the wrong moment
	leave(first)
	h:advance(8)
	store.__failAll = false
	truthy(rec(UID).lock ~= nil, "CONTROL: the dead session's lock is still in the store")

	local plr = joinSpawn("Crash", UID)
	eq(state(plr).canSave, false, "a rejoin while that lock is live is read-only")
	local earned = sortOne(plr)
	h:advance(AUTOSAVE + 1)
	eq(state(plr).canSave, false, "CONTROL: while the other lock has not expired, the session stays read-only")
	eq(rec(UID).data.cash, 1000, "CONTROL: ... and writes nothing")

	-- the stale lock expires (what 45 s of wall clock does to it)
	local r = rec(UID)
	r.lock.expires = os.time() - 1
	store:SetAsync("u_" .. UID, r)
	h:advance(AUTOSAVE + 1)
	eq(state(plr).canSave, true, "R2-6: after the stale lock expires, the session takes it and saves")
	eq(rec(UID).data.cash, 1000 + earned, "... with what it earned while read-only")
	leave(plr)
	h:advance(1)
	eq(rec(UID).lock, nil, "... and releases it on leave")
end

do
	-- the reviewer's rejoin-during-the-first-load: A's load takes the lock, A leaves mid-load, B's
	-- load reads A's lock before A hands it back
	local UID = 9004
	store:SetAsync("u_" .. UID, { data = vet() })
	latency = 0.5
	local a = join("Twice", UID)
	h:advance(0.2)
	leave(a)
	local b = join("Twice", UID)
	h:advance(3)
	latency = 0
	h.Players:simulateSpawn(b, h.workspace)
	h:advance(AUTOSAVE + 1)
	eq(state(b).canSave, true, "R2-6: a rejoin during the first session's load can save within one autosave period")
	eq(rec(UID).data.cash, 1000, "... without touching the data")
	leave(b)
	h:advance(1)
end

--============================================================================ R1-4: door spam

do
	local UID = 9400
	store:SetAsync("u_" .. UID, { data = vet({ backlog = 500 }) })
	local plr = joinSpawn("Keeper", UID)
	local bay = bayOf(plr)
	hrpOf(plr).CFrame = CFrame.new(W(bay, 0, 3, -32))
	local calls0 = store.__calls
	local scenes0 = #SceneEvent:sentTo(plr)
	for _ = 1, 100 do bay.Door.Open.Triggered:Fire(plr) end
	h:advance(0.1)
	truthy(store.__calls - calls0 <= 1, "R1-4: 100 door presses in one frame make at most 1 DataStore call (made "
		.. (store.__calls - calls0) .. ")")
	eq(#SceneEvent:sentTo(plr) - scenes0, 1, "... and send the note once")
	eq(rec(UID).data.endingSeen, true, "... and the one write records the ending")
	local mark = #NoticeEvent:sentTo(plr)
	bay.Door.Open.Triggered:Fire(plr)
	truthy(#NoticeEvent:sentTo(plr) > mark, "a press inside the cooldown is answered, not silent")
	truthy(type(Config.Bay.SceneCooldownSeconds) == "number", "Config.Bay.SceneCooldownSeconds is the door's note cooldown")
	h:advance((tonumber(Config.Bay.SceneCooldownSeconds) or 3) + 0.1)
	local calls1 = store.__calls
	bay.Door.Open.Triggered:Fire(plr)
	h:advance(0.1)
	eq(#SceneEvent:sentTo(plr) - scenes0, 2, "a press after the cooldown re-sends the note")
	eq(store.__calls - calls1, 0, "... and writes nothing: the ending was recorded when it was first seen")
	leave(plr)
	h:advance(1)
end

--============================================================================ R1-5: Select spam

do
	local plr = joinSpawn("Spammer", 9500)
	local bay = bayOf(plr)
	hrpOf(plr).CFrame = CFrame.new(W(bay, 0, 3, 0))
	local tray = readTray(bay)
	tray[1].click.MouseClick:Fire(plr)
	tray[2].click.MouseClick:Fire(plr)
	h:advance(0.35)
	eq(#state(plr).shift.carried, 2, "CONTROL: carrying two")
	eq(state(plr).shift.selected, 1, "CONTROL: the first pick stays selected (a pick does not move the selection: REVIEW-1 pass 3, U2)")
	local before = #StateEvent:sentTo(plr)
	for i = 1, 10000 do SelectEvent:simulateFireServer(plr, (i % 2) + 1) end
	h:advance(0.5)
	local sent = #StateEvent:sentTo(plr) - before
	truthy(sent <= 2, "R1-5: 10,000 Select events in one frame send at most 2 State payloads (sent " .. sent .. ")")
	eq(state(plr).shift.selected, 1, "... and the last one sent is the selection the client sees")
	-- one honest tap still answers at once
	before = #StateEvent:sentTo(plr)
	SelectEvent:simulateFireServer(plr, 2)
	eq(#StateEvent:sentTo(plr) - before, 1, "a single Select after a quiet moment is answered in the same frame")
	eq(state(plr).shift.selected, 2, "... with the new selection")
	leave(plr)
	h:advance(1)
end

--============================================================================ a deposit after zero

do
	local plr = joinSpawn("Late", 9600)
	local bay = bayOf(plr)
	hrpOf(plr).CFrame = CFrame.new(W(bay, 0, 3, 0))
	-- start the clock at a time whose zero falls between two 0.25 s timer polls
	local now = h.scheduler:now()
	local frac = (now - BOOT) % Config.Shift.TimerPoll
	h:advance(Config.Shift.TimerPoll - frac + 0.05)
	readTray(bay)[1].click.MouseClick:Fire(plr)
	h:advance(0.35)
	local st = state(plr)
	local endsAt = st.shift.endsAt
	local m = binFor(bay, st.shift.carried[1])
	standAtBin(plr, m)
	advanceTo(endsAt + 0.01)
	local lastPoll = BOOT + Config.Shift.TimerPoll * math.floor((h.scheduler:now() - BOOT) / Config.Shift.TimerPoll)
	truthy(lastPoll < endsAt, "CONTROL: no timer poll has run since zero")
	local cash = state(plr).cash
	SelectEvent:simulateFireServer(plr, 1)
	m.Base.Drop.Triggered:Fire(plr)
	st = state(plr)
	eq(st.cash, cash, "a deposit 0.01 s after the clock hit zero pays nothing")
	eq(st.shift.state, "SUMMARY", "... the shift is over")
	eq(st.shift.summary and st.shift.summary.timedOut, true, "... timed out")
	eq(st.shift.summary and st.shift.summary.sorted, 0, "... with that item unsorted")
	leave(plr)
	h:advance(1)
end

--============================================================================ E2: a server hop spends cash twice

-- REVIEW-1 pass 3, exploit finding 2 (the reviewer's rev_hop.luau, as assertions). Session A buys
-- the cart twice (1050 -> 0) and nothing is written yet. The player hops: B's load lands BEFORE A's
-- release, so B is read-only and shows the stale 1050. B bought the shoes twice. When A's release
-- landed and B took the lock, the merge kept both purchases and floored cash at 0: the store held
-- cart 2 AND shoes 2 for 1050 cash.
do
	local UID = 9750
	store:SetAsync("u_" .. UID, { data = vet({ cash = 1050, cartLevel = 0, shoesLevel = 0 }) })
	local a = joinSpawn("Hopper", UID)
	advanceTo(nextTick() + 0.5) -- the whole hop happens between two autosave ticks
	local function atLocker(p)
		hrpOf(p).CFrame = CFrame.new(W(bayOf(p), 12, 3, 11))
		return bayOf(p).Locker
	end
	local lockerA = atLocker(a)
	lockerA.Cart.Triggered:Fire(a)
	lockerA.Cart.Triggered:Fire(a)
	eq(state(a).cartLevel, 2, "CONTROL: A bought the cart twice")
	eq(state(a).cash, 0, "CONTROL: ... spending all 1050")
	eq(rec(UID).data.cash, 1050, "CONTROL: ... and nothing is written yet")

	-- the hop: A's release takes 1.0 s, B's load 0.2 s
	latencies = { 1.0, 0.2 }
	leave(a)
	local b = nil
	h.scheduler:spawn(function() h:join("Hopper", UID) end)
	for _, p in h.Players:GetPlayers() do
		if p.UserId == UID and p ~= a and p.Parent ~= nil then b = p end
	end
	h:advance(3)
	latencies = {}
	h.Players:simulateSpawn(b, h.workspace)
	h:advance(0.5)
	eq(state(b).canSave, false, "CONTROL: B loaded before A's release landed, read-only")
	eq(state(b).cash, 1050, "CONTROL: ... showing the stale 1050")

	local lockerB = atLocker(b)
	local mark = #NoticeEvent:sentTo(b)
	lockerB.Shoes.Triggered:Fire(b)
	lockerB.Shoes.Triggered:Fire(b)
	eq(state(b).shoesLevel, 0, "E2: a session that is not saving cannot buy on a balance the store may no longer hold")
	eq(state(b).cash, 1050, "E2: ... and keeps its cash")
	truthy(told(b, "Upgrades wait until your progress is saving. Try again in a moment.", mark), "E2: ... and is told why")

	h:advance(AUTOSAVE + 1)
	local r = rec(UID).data
	eq(state(b).canSave, true, "CONTROL: B took the lock once A's release landed")
	local worth = 0
	for _, field in { "cartLevel", "shoesLevel" } do
		for l = 1, r[field] do worth += Config.Economy.Prices[l] end
	end
	truthy(worth + r.cash <= 1050, string.format("E2: the store holds no more than the 1050 ever earned (cash %d + upgrades worth %d)", r.cash, worth))
	eq(state(b).carry, 4, "E2: B's live profile adopted the stored cart")
	eq(hrpOf(b).Parent.Humanoid.WalkSpeed, Config.Economy.WalkSpeed[r.shoesLevel + 1], "E2: ... and B walks at the stored shoes' speed")

	-- CONTROL: saving again, a purchase goes through the normal path
	mark = #NoticeEvent:sentTo(b)
	lockerB.Shoes.Triggered:Fire(b)
	truthy(told(b, "Shoes (speed 18) costs 250. You have 0.", mark), "CONTROL: once saving, B's purchase is judged on the real balance")
	leave(b)
	h:advance(2)
end

do
	-- A merge that changes the upgrades under a live character. The hop above cannot show it once a
	-- read-only purchase is refused (the shoes never change there). Here B is read-only behind another
	-- server's live lock with shoes 0 loaded; that server saves shoes 2 and dies; B's next autosave
	-- takes the lock with a merge, and the live profile adopts shoes 2.
	local UID = 9760
	store:SetAsync("u_" .. UID, { data = vet({ shoesLevel = 0 }), lock = { token = "OTHER-SERVER", expires = os.time() + 3600 } })
	local b = joinSpawn("Adopter", UID)
	eq(state(b).canSave, false, "CONTROL: read-only behind another server's live lock")
	eq(hrpOf(b).Parent.Humanoid.WalkSpeed, Config.Economy.WalkSpeed[1], "CONTROL: walking at the loaded shoes' speed")
	store:SetAsync("u_" .. UID, { data = vet({ shoesLevel = 2 }), lock = { token = "OTHER-SERVER", expires = os.time() - 1 } })
	h:advance(AUTOSAVE + 1)
	eq(state(b).canSave, true, "CONTROL: the session took the lock with a merge")
	eq(state(b).shoesLevel, 2, "CONTROL: the live profile adopted the stored shoes")
	eq(hrpOf(b).Parent.Humanoid.WalkSpeed, Config.Economy.WalkSpeed[3], "E2: a merge that changes the shoes changes how fast the character walks")
	leave(b)
	h:advance(1)
end

--============================================================================ E1: pick / put-back churn, refusal spam

-- REVIEW-1 pass 3, exploit reviewer finding 1. Only Select was throttled. A player standing
-- legally at their own tray fired the Slot_1 ClickDetector and Tray.PutBack 10,000 times in one
-- frame: every pair was accepted, 20,000 State payloads (17.9 MB) and 70,000 Instance.new calls
-- (each put-back rebuilds the item Model, each pick builds the crate and its weld), all in the
-- shared workspace. Refusals were a Notice each: 10,000 Redeem "NOPE" = 10,000 toasts.
do
	local plr = joinSpawn("Churner", 9700)
	local bay = bayOf(plr)
	hrpOf(plr).CFrame = CFrame.new(W(bay, 0, 3, 2)) -- 2 studs in front of the tray: an honest spot
	local tile = bay.Slot_1
	local putBack = bay.Tray.PutBack
	local function pair()
		local click = tile:FindFirstChild("Item") and tile.Item:FindFirstChildOfClass("ClickDetector")
			or tile:FindFirstChildOfClass("ClickDetector")
		click.MouseClick:Fire(plr)
		putBack.Triggered:Fire(plr)
	end

	-- CONTROL: one honest pair works and costs what it costs
	local s0, m0 = #StateEvent:sentTo(plr), instancesMade
	pair()
	eq(#state(plr).shift.carried, 0, "CONTROL: one pick + put-back leaves the hands empty")
	local honestPayloads, honestMade = #StateEvent:sentTo(plr) - s0, instancesMade - m0
	truthy(honestPayloads >= 1 and honestMade >= 1, string.format("CONTROL: one honest pair sends %d State payloads and makes %d Instances",
		honestPayloads, honestMade))
	h:advance(3)

	-- the burst
	s0, m0 = #StateEvent:sentTo(plr), instancesMade
	local n0 = #NoticeEvent:sentTo(plr)
	for _ = 1, 10000 do pair() end
	local burstPayloads, burstMade = #StateEvent:sentTo(plr) - s0, instancesMade - m0
	print(string.format("  E1 one honest pair: %d State payloads, %d Instances; 10,000 pairs in one frame: %d payloads, %d Instances, %d toasts",
		honestPayloads, honestMade, burstPayloads, burstMade, #NoticeEvent:sentTo(plr) - n0))
	truthy(burstPayloads <= 20, "E1: 10,000 pick + put-back pairs in one frame send at most 20 State payloads (sent " .. burstPayloads .. ")")
	truthy(burstMade <= 100, "E1: ... and make at most 100 Instances (made " .. burstMade .. ")")
	truthy(#NoticeEvent:sentTo(plr) - n0 <= 3, "E1: ... and send at most 3 toasts (sent " .. (#NoticeEvent:sentTo(plr) - n0) .. ")")
	truthy(told(plr, "Slow down - one thing at a time.", n0), "E1: ... and the refused ones are told why, once")
	h:advance(1)
	local items = 0
	for s = 1, 8 do
		if bay["Slot_" .. s]:FindFirstChild("Item") then items += 1 end
	end
	eq(items, 8, "E1: after the burst the tray still holds 8 items")
	eq(#state(plr).shift.carried, 0, "E1: ... and the hands are empty")

	-- sustained: one pair every frame for 10 s
	h:advance(3)
	s0, m0 = #StateEvent:sentTo(plr), instancesMade
	for _ = 1, 600 do
		pair()
		h:advance(1 / 60)
	end
	local sustained = #StateEvent:sentTo(plr) - s0
	print(string.format("  E1 a pair every frame for 10 s: %d payloads, %d Instances", sustained, instancesMade - m0))
	truthy(sustained <= 80, "E1: a pair every frame for 10 s sends at most 80 State payloads (sent " .. sustained .. ")")
	truthy(instancesMade - m0 <= 400, "E1: ... and makes at most 400 Instances (made " .. (instancesMade - m0) .. ")")
	h:advance(3)

	-- CONTROL: a brisk honest pace is never refused (a pick and a put-back every 0.5 s for 10 s)
	for _ = 1, 5 do
		if #state(plr).shift.carried == 0 then break end
		putBack.Triggered:Fire(plr)
		h:advance(0.5)
	end
	eq(#state(plr).shift.carried, 0, "CONTROL: hands emptied before the honest pace")
	h:advance(3)
	local n1 = #NoticeEvent:sentTo(plr)
	local accepted = 0
	for _ = 1, 20 do
		tile = bay.Slot_1
		local click = tile:FindFirstChild("Item") and tile.Item:FindFirstChildOfClass("ClickDetector")
		click.MouseClick:Fire(plr)
		if #state(plr).shift.carried == 1 then accepted += 1 end
		h:advance(0.25)
		putBack.Triggered:Fire(plr)
		if #state(plr).shift.carried == 0 then accepted += 1 end
		h:advance(0.25)
	end
	eq(accepted, 40, "CONTROL: 40 actions at 4 per second are all accepted")
	eq(told(plr, "Slow down - one thing at a time.", n1), false, "CONTROL: ... and none is told to slow down")

	-- a click with full hands, 10,000 times
	tile = bay.Slot_1
	local tray = readTray(bay)
	tray[1].click.MouseClick:Fire(plr)
	tray[2].click.MouseClick:Fire(plr)
	h:advance(0.5)
	eq(#state(plr).shift.carried, 2, "CONTROL: hands full at carry 2")
	local n2 = #NoticeEvent:sentTo(plr)
	local third = readTray(bay)[1].click
	for _ = 1, 10000 do third.MouseClick:Fire(plr) end
	local full = #NoticeEvent:sentTo(plr) - n2
	truthy(full >= 1 and full <= 3, "E1: 10,000 clicks with full hands send 1 to 3 toasts (sent " .. full .. ")")
	h:advance(1)
	local n3 = #NoticeEvent:sentTo(plr)
	third.MouseClick:Fire(plr)
	eq(#NoticeEvent:sentTo(plr) - n3, 1, "CONTROL: the same refusal a second later is told again")

	-- Redeem garbage, 10,000 times
	h:advance(3)
	local n4 = #NoticeEvent:sentTo(plr)
	for _ = 1, 10000 do remotes.Redeem:simulateFireServer(plr, "NOPE") end
	local codes = #NoticeEvent:sentTo(plr) - n4
	print(string.format("  E1 10,000 full-hands clicks: %d toasts; 10,000 Redeem NOPE: %d toasts", full, codes))
	truthy(codes >= 1 and codes <= 3, "E1: 10,000 Redeem 'NOPE' events send 1 to 3 toasts (sent " .. codes .. ")")

	leave(plr)
	h:advance(1)
end

--============================================================================ nothing died

for _, e in h:errors() do print("scheduler error: " .. e) end
eq(#h:errors(), 0, "no server thread died")
print(string.format("lost-found-depot save: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot save check failed", 0) end
