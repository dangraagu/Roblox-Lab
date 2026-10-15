-- Gnome Garden Defense: the DataStore findings of REVIEW-1, each played on stores that YIELD as Roblox's do.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_store.luau
--
-- robloxemu's DataStore answers at once; Roblox's yields. Every UpdateAsync here is wrapped to wait LAT[store]
-- seconds first, and failures are injected with the emulator's __failNext / __failAll. What is checked:
--   1. a session that loaded READ-ONLY (another server's lock) keeps trying, takes the record once the lock is
--      gone, and then saves what was played meanwhile (it never stays read-only for the whole session);
--   2. one failed read at join is retried: the veteran's real garden comes back, and nothing is ever written
--      over the stored record while the read had failed;
--   3. a player who leaves while the profile loads leaves no lock behind, and a tap in the load window is
--      answered, not dropped;
--   4. an endless gardener who leaves while the day's bed is drawn (the first draw of the day on this server: run
--      before anything else draws it) leaves no board behind, no garden step fails, and the next gardener in that
--      slot has exactly one board, which answers them;
--   5. a season's win is saved off the simulation thread: other gardens keep moving while it yields, and a leave
--      right after the win ends with the record released, never re-locked by the late win save;
--   6. a flood of refused requests is told once a second, not echoed one toast per call.

local Harness = require("./emu/harness")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local Cfg = require("../gnome-garden-defense/src/shared/Config")
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-store", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local DSS = h.game:GetService("DataStoreService")
local store = DSS:GetDataStore("GnomeGarden_v1")
local daily = DSS:GetDataStore("GnomeGarden_Daily_v1")
local lb = DSS:GetOrderedDataStore("GnomeGarden_LB_v1")

-- latency injection: a call waits LAT[name] seconds, then runs; `calls` logs every profile call per key
local LAT = { profile = 0, daily = 0, board = 0 }
local calls = {}
local function slow(ds, name)
	local orig = ds.UpdateAsync
	ds.UpdateAsync = function(self, k, f)
		local rec = { key = k, name = name, enter = tick() }
		table.insert(calls, rec)
		local wait = LAT[name]
		if type(wait) == "function" then wait = wait(k, rec) end
		if wait and wait > 0 then task.wait(wait) end
		local r = orig(self, k, f)
		rec.exit = tick()
		return r
	end
end
slow(store, "profile")
slow(daily, "daily")
slow(lb, "board")

local LOCKED, VET, QUICK, ENDLESS, NEXT, A, B1, B2, B3, SPAM = 9101, 9102, 9103, 9104, 9105, 9106, 9107, 9108, 9109, 9110
store:SetAsync("u_" .. LOCKED, { data = { chapter = 1, bestWave = 0, bestAt = 0, published = 0, tutorialDone = true },
	session = "crashed", jobId = "server-that-crashed", lockUntil = os.time() + 600 })
store:SetAsync("u_" .. VET, { data = { chapter = 5, bestWave = 52, bestAt = 1700000000, published = 52, tutorialDone = true } })
store:SetAsync("u_" .. ENDLESS, { data = { chapter = 5, bestWave = 44, bestAt = 1700000000, published = 44, tutorialDone = true } })
for _, uid in { B1, B2, B3 } do
	store:SetAsync("u_" .. uid, { data = { chapter = 5, bestWave = 40, bestAt = 1700000000, published = 40, tutorialDone = true } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local R = h.ReplicatedStorage.GardenRemotes
local toasts = {} -- { who, msg } (the emulator's FireClient reaches every listener: the recorder knows who)
local function toastsTo(plr)
	local out = {}
	for _, rec in R.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
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
local function joinAsync(name, uid)
	local out
	task.spawn(function() out = h:join(name, uid) end)
	return function() return out or h.Players:FindFirstChild(name) end
end
-- PlayerRemoving's handler saves, and a save YIELDS on these stores. robloxemu fires PlayerRemoving on the
-- caller's thread, so a leave is asked from a thread of its own (Roblox gives every handler one).
local function leave(plr)
	task.spawn(function() h:leave(plr) end)
end
local function stepWarnings()
	local n = 0
	for _, w in h.warnings do
		if string.find(w, "garden step failed", 1, true) then n += 1 end
	end
	return n
end

--============================================================ 1. a crashed server's lock: read-only, then saving
do
	local p = h:join("Locked", LOCKED)
	h:advance(1)
	eq(p:GetAttribute("Saving"), false, "a record another server still holds loads READ-ONLY")
	-- play: two pebbles survive wave 1 (best wave 0 -> 1 in memory)
	local g = gardenOf(LOCKED)
	fire(p, "Plant", 1, "pebble")
	fire(p, "Plant", 2, "pebble")
	fire(p, "Ready")
	local guard = 0
	while g:GetAttribute("Phase") == "wave" and guard < 600 do h:advance(0.5) guard += 1 end
	eq(p:GetAttribute("BestWave"), 1, "wave 1 survived while read-only (best wave 1 in memory)")
	h:advance(25)
	eq(store:GetAsync("u_" .. LOCKED).session, "crashed", "while the other lock holds, nothing is written over it")
	-- the crashed server's lock runs out (its lockUntil passes): the record is free now
	local rec = store:GetAsync("u_" .. LOCKED)
	rec.lockUntil = 0
	store:SetAsync("u_" .. LOCKED, rec)
	local freedAt = tick()
	local guard2 = 0
	while p:GetAttribute("Saving") ~= true and guard2 < 120 do h:advance(0.5) guard2 += 1 end
	eq(p:GetAttribute("Saving"), true, "once the lock is gone the session takes the record and starts saving")
	print(string.format("  read-only -> saving %.1f s after the old lock was freed", tick() - freedAt))
	truthy(tick() - freedAt <= 12, "within 12 s (the retry backs off to every 10 s)")
	h:advance(1)
	rec = store:GetAsync("u_" .. LOCKED)
	eq(rec.data.bestWave, 1, "and what was played while read-only is saved (best wave 1)")
	eq(rec.jobId, h.game.JobId, "under this server's jobId")
	local told = false
	for _, t in toastsTo(p) do
		if string.find(t, "saved again", 1, true) then told = true end
	end
	truthy(told, "and the player is told their progress is saved again")
	leave(p)
	h:advance(1)
	rec = store:GetAsync("u_" .. LOCKED)
	eq(rec.lockUntil, 0, "leaving releases the lock this session took")
	eq(rec.data.bestWave, 1, "with the best wave kept")
end

--============================================================ 4. an endless gardener leaves while the day's bed is drawn
do
	-- the draw (2 s) outlasts the leave's save (0.5 s): whatever the draw builds after it comes back is for a
	-- player who has gone
	LAT.profile, LAT.daily = 0.5, 2.0
	local before = stepWarnings()
	local dailyBefore = 0
	for _, c in calls do if c.name == "daily" then dailyBefore += 1 end end
	local get = joinAsync("Endless", ENDLESS)
	h:advance(0.7) -- the profile is in; the day's bed is being drawn
	leave(get())
	h:advance(4)
	local dailyCalls = 0
	for _, c in calls do if c.name == "daily" then dailyCalls += 1 end end
	truthy(dailyCalls > dailyBefore, "(the day's bed was really being drawn from the store when they left)")
	local boards = h.workspace.GardenBoards:GetChildren()
	eq(#boards, 0, "a gardener who left while the bed was drawn leaves no board behind")
	eq(gardenOf(ENDLESS), nil, "and no garden")
	eq(stepWarnings() - before, 0, "and no garden step fails meanwhile")
	LAT.profile, LAT.daily = 0, 0
	local n = h:join("Next", NEXT)
	h:advance(1)
	boards = h.workspace.GardenBoards:GetChildren()
	eq(#boards, 1, "the next gardener in that slot has exactly one board")
	local mine = boards[1]
	eq(mine and mine:GetAttribute("BoardOf"), NEXT, "and it is theirs")
	local before2 = #R.Board:sentTo(n)
	local prompt = mine and mine:FindFirstChild("BoardPrompt", true)
	if prompt then prompt.Triggered:Fire(n) end
	h:advance(0.5)
	local sent = R.Board:sentTo(n)
	local last = sent[#sent] and sent[#sent].args[1]
	truthy(#sent > before2 and last and last.mode == "friends", "its prompt answers its owner (friends view)")
	leave(n)
	h:advance(1)
end

--============================================================ 2. one failed read at join is retried
do
	store.__failNext = true
	local p = h:join("Veteran", VET)
	h:advance(0.5)
	local g = gardenOf(VET)
	eq(store:GetAsync("u_" .. VET).data.bestWave, 52, "(the failed read wrote nothing)")
	local guard = 0
	while p:GetAttribute("Saving") ~= true and guard < 60 do h:advance(0.5) guard += 1 end
	eq(p:GetAttribute("Saving"), true, "a failed read is retried, and the retry takes the record")
	g = gardenOf(VET)
	eq(g and g:GetAttribute("Chapter"), 5, "the veteran's garden is the Moonlit Bed again, not Spring")
	eq(p:GetAttribute("BestWave"), 52, "with their best wave of 52")
	eq(store:GetAsync("u_" .. VET).data.bestWave, 52, "and the stored record still says 52")
	-- the store goes down for 40 s: a joiner in that window never writes defaults over a real record
	leave(p)
	h:advance(1)
	store.__failAll = true
	local p2 = h:join("Veteran", VET)
	h:advance(30)
	eq(p2:GetAttribute("Saving"), false, "with the store down nothing is saved")
	store.__failAll = false
	local guard2 = 0
	while p2:GetAttribute("Saving") ~= true and guard2 < 120 do h:advance(0.5) guard2 += 1 end
	eq(p2:GetAttribute("Saving"), true, "and when it is back, the session loads and saves again")
	eq(store:GetAsync("u_" .. VET).data.bestWave, 52, "the record was never overwritten with a fresh profile")
	eq(store:GetAsync("u_" .. VET).data.chapter, 5, "(chapter 5 kept)")
	leave(p2)
	h:advance(1)
end

--============================================================ 3. leaving while the profile loads
do
	LAT.profile = 0.5
	local get = joinAsync("Quick", QUICK)
	h:advance(0.2)
	local q = get()
	fire(q, "Plant", 1, "pebble")
	fire(q, "SetPaused", true)
	h:advance(0.05)
	local said = toastsTo(q)
	truthy(#said >= 1, "a tap in the load window is answered (" .. tostring(said[1]) .. ")")
	truthy(#said <= 2, "once per request at most (" .. #said .. ")")
	leave(q)
	h:advance(2)
	local rec = store:GetAsync("u_" .. QUICK)
	truthy(rec == nil or (tonumber(rec.lockUntil) or 0) <= os.time(),
		"a player who left during the load leaves no lock (lockUntil-now = " .. tostring(rec and ((rec.lockUntil or 0) - os.time())) .. ")")
	LAT.profile = 0
end

--============================================================ 5. a season won is saved off the simulation thread
local function rankPads(g)
	local p = PathGen.fromText(Cfg, g:GetAttribute("PathCells"))
	local out = {}
	for id, pd in PathGen.pads(Cfg, p) do
		local _, cover = PathGen.rangeMask(p, pd.cx, pd.cz, 14)
		table.insert(out, { id = id, cover = cover })
	end
	table.sort(out, function(x, y) if x.cover ~= y.cover then return x.cover > y.cover end return x.id < y.id end)
	return out
end
local function botTurn(plr, g, rk)
	local seeds = g:GetAttribute("Seeds") or 0
	local want = { "pebble", "sprinkler", "pebble", "pebble", "sprinkler", "pebble", "pebble", "sprinkler" }
	local have, planted = 0, {}
	for _, d in g:FindFirstChild("Bed"):GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Kind") then have += 1; planted[d:GetAttribute("Pad")] = d end
	end
	if have < #want then
		local kind = want[have + 1]
		if seeds >= Cfg.Gnomes[kind].levels[1].cost then
			for _, r in rk do if not planted[r.id] then fire(plr, "Plant", r.id, kind) return end end
		end
		return
	end
	local pick, lvl = nil, 99
	for _, r in rk do
		local m = planted[r.id]
		if m and (m:GetAttribute("Level") or 3) < lvl then pick, lvl = r.id, m:GetAttribute("Level") end
	end
	if pick and lvl < 3 then
		local m = planted[pick]
		if seeds >= Cfg.Gnomes[m:GetAttribute("Kind")].levels[lvl + 1].cost then fire(plr, "Upgrade", pick) end
	end
end
do
	local a = h:join("Winner", A)
	local bs = { h:join("Endless1", B1), h:join("Endless2", B2), h:join("Endless3", B3) }
	h:advance(1)
	local gA = gardenOf(A)
	local gBs = {}
	local missing = gA == nil
	for i, b in bs do
		gBs[i] = gardenOf(b.UserId)
		if gBs[i] == nil then missing = true end
	end
	truthy(not missing, "four joiners in a row each get a garden")
	if missing then
		for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
		print(("gnome garden store: %d passed, %d failed"):format(passed, failed + 1))
		return
	end
	local ticks = { {}, {}, {} }
	R.GardenTick.OnClientEvent:Connect(function(t)
		if type(t) ~= "table" then return end
		for i, b in bs do
			if t.o == b.UserId then table.insert(ticks[i], tick()) end
		end
	end)
	-- the server unlocks summer on the player (attribute Chapter = 2) the moment the Stag Beetle falls, before
	-- it saves: that marks the win, and the winner's next profile write is the win's save
	local wonAt = nil
	a:GetAttributeChangedSignal("Chapter"):Connect(function()
		if a:GetAttribute("Chapter") == 2 and wonAt == nil then wonAt = tick() end
	end)
	-- from now on every profile and board write takes 1.0 s; the winner's FIRST save after the win takes 2.5 s
	-- (a slow write that finishes after a quick later one must not undo it)
	local firstAfterWin = true
	LAT.profile = function(k, rec)
		if k == "u_" .. A and wonAt and firstAfterWin then
			firstAfterWin = false
			rec.winSave = true
			return 2.5
		end
		return 1.0
	end
	LAT.board = 1.0
	local rkA = rankPads(gA)
	local rkB = {}
	for i, g in gBs do rkB[i] = rankPads(g) end
	local guard = 0
	local leftAt = nil
	while guard < 24000 do -- 2400 s: a spring lost once and won on the retry fits (6000 failed 1 run in 64)
		guard += 1
		local ph = gA:GetAttribute("Phase")
		if leftAt or gA.Parent == nil then
			-- the winner has gone
		elseif ph == "lost" then fire(a, "Restart"); h:advance(0.1); rkA = rankPads(gA)
		elseif ph ~= "won" then
			botTurn(a, gA, rkA)
			if ph ~= "wave" then fire(a, "Ready") end
		end
		for i, b in bs do
			local g = gBs[i]
			local phb = g:GetAttribute("Phase")
			if phb == "lost" then fire(b, "Restart"); rkB[i] = rankPads(g)
			else
				botTurn(b, g, rkB[i])
				if phb ~= "wave" then fire(b, "Ready") end
			end
		end
		h:advance(0.1)
		if wonAt and not leftAt and tick() - wonAt >= 0.3 then
			-- the winner leaves 0.3 s after the boss falls, while the win's save is still in flight
			leave(a)
			leftAt = tick()
		end
		if leftAt and tick() - leftAt > 8 then break end
	end
	truthy(wonAt ~= nil, "the scripted winner won spring (" .. tostring(wonAt and string.format("t=%.1f", wonAt)) .. ")")
	local win = nil
	for _, c in calls do
		if c.winSave then win = c end
	end
	truthy(win ~= nil, "the win was saved (a profile write started after the boss fell)")
	if win and win.exit then
		print(string.format("  the win's save: t=%.2f .. %.2f", win.enter, win.exit))
		-- the gardens that were mid-wave all through that window: their ticks must keep coming at 10 Hz
		local measured, worst = 0, 0
		for i, list in ticks do
			local inWindow, first, last = {}, nil, nil
			for _, t in list do
				if t >= win.enter - 0.25 and t <= win.exit + 0.25 then table.insert(inWindow, t) end
			end
			if #inWindow >= 2 and inWindow[1] <= win.enter + 0.15 and inWindow[#inWindow] >= win.exit - 0.15 then
				measured += 1
				for j = 2, #inWindow do worst = math.max(worst, inWindow[j] - inWindow[j - 1]) end
			end
			first, last = first, last
		end
		print(string.format("  %d other garden(s) were mid-wave through the win's save; their largest tick gap %.2f s", measured, worst))
		truthy(measured >= 1, "at least one other garden was mid-wave through the win's save (precondition)")
		truthy(worst <= 0.25, string.format("other gardens keep their 10 Hz while the win is saved (largest gap %.2f s)", worst))
	end
	local rec = store:GetAsync("u_" .. A)
	eq(rec and rec.data and rec.data.chapter, 2, "the win is in the record (summer unlocked)")
	eq(rec and rec.data and rec.data.bestWave, 10, "with best wave 10")
	eq(rec and rec.lockUntil, 0, "and the lock is released: the slow win save did not re-lock it after the leave")
	for _, b in bs do leave(b) end
	h:advance(5)
	LAT.profile, LAT.board = 0, 0
end

--============================================================ 6. a flood of refused requests
do
	local p = h:join("Spammer", SPAM)
	h:advance(1)
	local before = #toastsTo(p)
	for _ = 1, 1000 do fire(p, "SetPaused", "x") end
	for _ = 1, 1000 do fire(p, "Plant", 1, "pebble") end
	h:advance(0.1)
	local got = #toastsTo(p) - before
	print(string.format("  2000 requests in one instant -> %d toasts back", got))
	truthy(got <= 21, "a flood is answered by the 20 the bucket serves plus one 'slow down', not one toast per call (" .. got .. ")")
	local slowSaid = 0
	for i, t in toastsTo(p) do
		if i > before and t == "Slow down a little" then slowSaid += 1 end
	end
	eq(slowSaid, 1, "the refusal is still said (once)")
	h:advance(3)
	local before2 = #toastsTo(p)
	fire(p, "Sell", 1)
	h:advance(0.1)
	local after = toastsTo(p)
	eq(after[#after], "No gnome there", "a few seconds later a request is served and answered again")
	truthy(#after > before2, "(answered)")
	leave(p)
	h:advance(1)
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no server thread died")
print(("gnome garden store: %d passed, %d failed"):format(passed, failed))
