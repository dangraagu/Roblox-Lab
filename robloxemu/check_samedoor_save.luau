-- The Same Door — a real player never loses a verified run to ONE transient DataStore error
-- (REVIEW-1 findings 3 and 4). Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--                                    luau check_samedoor_save.luau 2>&1
--
--   1. the save at the finish fails once: the run is KEPT, lands in the profile and on the board at
--      the next save (an autosave, 20 s), and survives a rejoin. The first build dropped it for good.
--   2. the release write on leaving fails once and the player rejoins 10 s later: the session starts
--      unranked ("open in another server"), RE-ACQUIRES the lock once it expires, says so, and the run
--      it finished while waiting lands on the board. The first build never retried: a whole session
--      saved and ranked nothing.
--   3. the player leaves while the profile is loading: the lock that load took is released, not left
--      to block the next join for 45 s.
--   4. the player list shows the streak as of today: a stored streak that broke days ago shows 0.
-- os.time moves with the scheduler, so a session lock can actually expire in simulated time.

local realOs = os
local offset = 0
os = setmetatable({ time = function(t) if t ~= nil then return realOs.time(t) end return realOs.time() + offset end }, { __index = realOs })

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")
local h = Harness.new({ bundle = bundle, name = "same-door-save", viewport = { 1280, 720 }, touch = false })
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
local realRandom = Random
local unseeded = 0
Random = { new = function(seed) if seed == nil then unseeded += 1; return realRandom.new(9090 + unseeded) end return realRandom.new(seed) end }

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.services.ReplicatedStorage
local HB = h.services.RunService.Heartbeat
local FRAME = 1 / 60
local function step(dt) h:advance(dt); offset += dt; HB:Fire(dt) end
local function wait(sec) local t = 0; while t < sec do step(0.25); t += 0.25 end end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local R = RS.SameDoorRemotes
local Config = h:_require(RS.Config)
local Medals = h:_require(RS.Medals)
local Dungeon = h:_require(h.services.ServerScriptService.Dungeon)
local HttpService = h.game:GetService("HttpService")
local rec = HttpService:JSONDecode(h.game:GetService("ServerStorage").SameDoor.Day.Value)
local world = Dungeon.fromRecord(Config, rec)
local _, path = Dungeon.perfectPath(Config, world)
local dayIndex = math.floor(os.time() / 86400)
local boardStore = h.services.DataStoreService:GetOrderedDataStore(Config.Board.StoreName, "d" .. dayIndex)
local playerStore = h.services.DataStoreService:GetDataStore(Config.Save.StoreName)

local msgs, toasts = {}, {}
R.Run.OnClientEvent:Connect(function(p) table.insert(msgs, p) end)
R.Toast.OnClientEvent:Connect(function(m) table.insert(toasts, m) end)
local function toastsSince(n)
	local out = {}
	for i = n + 1, #toasts do table.insert(out, toasts[i]) end
	return table.concat(out, " | ")
end

-- walk the day's line from the arch at `speed`; `beforeFinish` runs once, a few frames before the Door
local function walkRun(plr, hrp, speed, beforeFinish)
	local n = #msgs
	hrp.CFrame = CFrame.new(0, 3, 12)
	ws.Hub.Arch.Doorway.EnterPrompt.Triggered:Fire(plr)
	h:advance(0.05)
	local ready
	for i = n + 1, #msgs do if msgs[i].state == "ready" and msgs[i].origin then ready = msgs[i] end end
	assert(ready, "a run started")
	local o = Vector3.new(ready.origin.x, ready.origin.y, ready.origin.z)
	local pts = { { x = 72, z = -8 } }
	for _, p in path do table.insert(pts, p) end
	local a, b = pts[#pts - 1], pts[#pts]
	local L = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	table.insert(pts, { x = b.x + (b.x - a.x) / L * 2, z = b.z + (b.z - a.z) / L * 2 })
	local seg, x, z = 1, 72, -8
	for _ = 1, 60 * 120 do
		local remaining = speed * FRAME
		while remaining > 0 and seg < #pts do
			local q = pts[seg + 1]
			local dx, dz = q.x - x, q.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = q.x, q.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
		local last = path[#path]
		if beforeFinish and math.sqrt((x - last.x) ^ 2 + (z - last.z) ^ 2) < 6 then beforeFinish(); beforeFinish = nil end
		hrp.CFrame = CFrame.new(o.X + x, o.Y + 3, o.Z + z)
		step(FRAME)
		for i = n + 1, #msgs do
			if msgs[i].run == ready.run and (msgs[i].state == "finished" or msgs[i].state == "void") then
				h:advance(0.2)
				return msgs[i]
			end
		end
	end
	return nil
end
local function storedBest(uid)
	local s = playerStore:GetAsync("u_" .. uid)
	return s and s.data and s.data.today and s.data.today.bestMs
end
local function boardTime(uid)
	local v = boardStore:GetAsync("u_" .. uid)
	if v == nil then return nil end
	return (h:_require(RS.Board).decode(v, Config.Board))
end

--============================================================ 1. one failed save at the finish
do
	local A = h:join("Ada", 8001)
	h:advance(0.5)
	local ca = h.Players:simulateSpawn(A, ws)
	h:advance(1)
	local t0 = #toasts
	local fin = walkRun(A, ca.HumanoidRootPart, 16, function() playerStore.__failNext = true end)
	eq(fin and fin.state, "finished", "1. the run finishes")
	print(string.format("1. the save at the finish fails once: %s %s ms, posted %s, card reason %q", tostring(fin and fin.state),
		tostring(fin and fin.timeMs), tostring(fin and fin.posted), tostring(fin and fin.reason)))
	eq(storedBest(8001), nil, "1. right after the failed save the profile does not have it yet (the failure was real)")
	truthy(fin and fin.reason and string.find(fin.reason, "next", 1, true) ~= nil,
		"1. the finish card says the run is kept for the next save (" .. tostring(fin and fin.reason) .. ")")
	wait(Config.Save.AutosaveSeconds + 2)
	eq(storedBest(8001), fin and fin.timeMs, "1. one autosave later the run IS in the profile")
	eq(boardTime(8001), fin and fin.timeMs, "1. …and on today's board")
	eq(A.leaderstats.Best.Value, fin and Medals.formatTime(fin.timeMs), "1. …and in the player list")
	truthy(string.find(toastsSince(t0), "saved", 1, true) ~= nil, "1. …and the player is told (" .. toastsSince(t0) .. ")")
	h:leave(A)
	h:advance(2)
	local A2 = h:join("Ada", 8001)
	h:advance(0.5)
	h.Players:simulateSpawn(A2, ws)
	h:advance(2)
	eq(A2.leaderstats.Best.Value, fin and Medals.formatTime(fin.timeMs), "1. a rejoin still shows that best")
	h:leave(A2)
	h:advance(2)
end

--============================================================ 2. a stale lock: retried, re-acquired
do
	local B = h:join("Bo", 8002)
	h:advance(0.5)
	h.Players:simulateSpawn(B, ws)
	h:advance(1)
	local first = playerStore:GetAsync("u_8002")
	truthy(first and first.session ~= nil and first.lockUntil > os.time(), "2. Bo's first session holds the lock")
	playerStore.__failNext = true -- the release write on leaving fails
	h:leave(B)
	h:advance(1)
	wait(10)
	local t0 = #toasts
	local B2 = h:join("Bo", 8002)
	h:advance(0.5)
	local cb2 = h.Players:simulateSpawn(B2, ws)
	h:advance(1)
	truthy(string.find(toastsSince(t0), "another server", 1, true) ~= nil, "2. the rejoin starts unranked and says why (" .. toastsSince(t0) .. ")")
	-- a run finished BEFORE the old lock expires
	local fin1 = walkRun(B2, cb2.HumanoidRootPart, 16 / 1.3, nil)
	eq(fin1 and fin1.state, "finished", "2. a run finished while the old lock still stands")
	truthy(fin1 and fin1.unranked == true, "2. …is not ranked yet")
	eq(boardTime(8002), nil, "2. …and is not on the board yet")
	local t1 = #toasts
	wait(Config.Save.SessionLockSeconds + 15)
	local now = playerStore:GetAsync("u_8002")
	truthy(now and now.session ~= first.session, "2. once the old lock expired this session took the profile over")
	truthy(string.find(toastsSince(t1), "loaded", 1, true) ~= nil, "2. …and said so (" .. toastsSince(t1) .. ")")
	eq(storedBest(8002), fin1 and fin1.timeMs, "2. the run finished while waiting landed in the profile")
	eq(boardTime(8002), fin1 and fin1.timeMs, "2. …and on the board")
	-- and a run after that is ranked at once
	h:advance(1.2)
	R.GoHub:simulateFireServer(B2)
	h:advance(1.2)
	local fin2 = walkRun(B2, cb2.HumanoidRootPart, 16, nil)
	eq(fin2 and fin2.unranked, false, "2. a run after the takeover is ranked (" .. tostring(fin2 and fin2.reason) .. ")")
	eq(boardTime(8002), fin2 and fin2.timeMs, "2. …and improves the board")
	h:leave(B2)
	h:advance(2)
end

--============================================================ 3. leaving during the profile load
do
	local C = h:join("Cy", 8003)
	h:advance(0.5)
	h.Players:simulateSpawn(C, ws)
	h:advance(1)
	h:leave(C)
	h:advance(2)
	local before = playerStore:GetAsync("u_8003")
	eq(before and before.lockUntil, 0, "3. a normal leave releases the lock")
	-- next join: the player is gone by the time the load's UpdateAsync runs
	local origUpdate = playerStore.UpdateAsync
	local armed, left = true, false
	playerStore.UpdateAsync = function(self, key, fn)
		if key == "u_8003" and armed then
			armed = false
			for _, p in h.Players:GetPlayers() do
				if p.UserId == 8003 then h:leave(p); left = true end
			end
		end
		return origUpdate(self, key, fn)
	end
	h:join("Cy", 8003)
	h:advance(0.5)
	h:advance(2)
	playerStore.UpdateAsync = origUpdate
	truthy(left, "3. (the rig made the player leave inside the load's UpdateAsync)")
	local after = playerStore:GetAsync("u_8003")
	eq(after and after.lockUntil, 0, "3. a player who left while the profile loaded leaves no lock behind")
end

--============================================================ 4. the player list never shows a broken streak
-- (REVIEW-1, reviewer 2, finding 4) the stored streak only moves at the next finish
do
	local D = math.floor(os.time() / 86400)
	playerStore:SetAsync("u_8004", { data = { v = 1, today = { day = D - 3, bestMs = 30000, runs = 3, finishes = 1, postedMs = 30000, medal = "Gold" },
		life = { doors = 9, silverDays = 9, goldDays = 5, sealerDays = 0, streak = 5, bestStreak = 5, lastDay = D - 3, runs = 40, firstDay = D - 12 } } })
	playerStore:SetAsync("u_8005", { data = { v = 1, today = { day = D - 1, bestMs = 30000, runs = 3, finishes = 1, postedMs = 30000, medal = "Gold" },
		life = { doors = 9, silverDays = 9, goldDays = 5, sealerDays = 0, streak = 5, bestStreak = 5, lastDay = D - 1, runs = 40, firstDay = D - 12 } } })
	local E = h:join("Eli", 8004)
	local F = h:join("Fay", 8005)
	h:advance(1)
	eq(E.leaderstats.Streak.Value, 0, "4. last Door 3 days ago with a stored streak of 5: the player list shows 0")
	eq(F.leaderstats.Streak.Value, 5, "4. last Door yesterday: the streak of 5 is still alive and shows")
	h:leave(E)
	h:leave(F)
	h:advance(1)
end

local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end
print(string.format("check_samedoor_save: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor_save failed", 0) end
