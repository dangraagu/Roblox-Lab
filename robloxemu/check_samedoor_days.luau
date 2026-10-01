-- The Same Door — the day's life cycle on a live server: a failing store, midnight, bad records.
-- Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--       luau check_samedoor_days.luau 2>&1
--
-- DESIGN §3.3, §3.5, §3.6, one server, os.time overridden (installed BEFORE the server loads, so its
-- first lookup of os.time already sees the wrapper):
--   1. the Days store fails and IsStudio is false: the arch refuses with "still being carved", no run
--      starts, and the server retries on its schedule until the store answers;
--   2. midnight: a run in progress keeps the day it started on and posts to THAT day's board; the next
--      Run again uses the new Door and says so;
--   3. a stored record that fails validation fails CLOSED: runs refused, and the stored value is never
--      re-minted over;
--   4. a record of an unknown version tells the player the server is out of date.

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")

-- os.time follows the VIRTUAL clock (so h:advance moves the date) plus an offset the check controls.
local realOs = os
local offset = 0
local h
os = setmetatable({
	time = function(t)
		if t ~= nil then return realOs.time(t) end
		local v = if h then h.scheduler:now() else 0
		return math.floor(offset + v)
	end,
}, { __index = realOs })

h = Harness.new({ bundle = bundle, name = "same-door-days", viewport = { 1280, 720 }, touch = false })
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

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local HB = h.services.RunService.Heartbeat
local FRAME = 1 / 60
local function step(dt)
	h:advance(dt)
	HB:Fire(dt)
end

-- land 70 s before the next UTC midnight (virtual clock 0 at boot)
local now0 = realOs.time()
offset = (math.floor(now0 / 86400) + 1) * 86400 - 70
local D = math.floor(os.time() / 86400)

local days = h.services.DataStoreService:GetDataStore(h:_require(h.services.ReplicatedStorage.Config).Day.StoreName)
days.__failAll = true

assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local RS = h.services.ReplicatedStorage
local R = RS.SameDoorRemotes
local Config = h:_require(RS.Config)
local Dungeon = h:_require(h.services.ServerScriptService.Dungeon)
local HttpService = h.game:GetService("HttpService")

local me = h:join("Night", 5501)
h:advance(0.5)
local char = h.Players:simulateSpawn(me, ws)
h:advance(0.2)
local hrp = char.HumanoidRootPart
local msgs, toasts, dayMsgs = {}, {}, {}
R.Run.OnClientEvent:Connect(function(p) table.insert(msgs, p) end)
R.Toast.OnClientEvent:Connect(function(m) table.insert(toasts, m) end)
R.DayInfo.OnClientEvent:Connect(function(d) table.insert(dayMsgs, d) end)
local prompt = ws.Hub.Arch.Doorway.EnterPrompt

--============================================================ 1. a failing Days store
hrp.CFrame = CFrame.new(0, 3, 12)
prompt.Triggered:Fire(me)
h:advance(0.05)
eq(toasts[#toasts], "Today's Door is still being carved; retrying", "with the Days store down, the arch says why")
eq(#msgs, 0, "…and no run starts")
eq(ws.Hub.Arch.Doorway.Sign.Text.Text, "Today's Door is still being carved; retrying", "the arch sign says it too")
local callsDown = days.__calls
days.__failAll = false
h:advance(3) -- the first retry comes 2 s after the failure
truthy(days.__calls > callsDown, "the server retried the store on its schedule")
truthy(#h.game:GetService("ServerStorage").SameDoor.Day.Value > 100, "…and loaded the day once the store answered")
prompt.Triggered:Fire(me)
h:advance(0.05)
local ready = msgs[#msgs]
eq(ready and ready.state, "ready", "now the arch starts a run")
local recD = HttpService:JSONDecode(h.game:GetService("ServerStorage").SameDoor.Day.Value)
eq(recD.day, D, "the day loaded is today (" .. D .. ")")

--============================================================ 2. midnight during a run
-- walk the day's line slowly enough that midnight falls mid-run (70 s to go at arrival)
local world = Dungeon.fromRecord(Config, recD)
local _, path = Dungeon.perfectPath(Config, world)
local pts = { { x = 72, z = -8 } }
for _, p in path do table.insert(pts, p) end
local origin = Vector3.new(ready.origin.x, ready.origin.y, ready.origin.z)
-- pre-seed tomorrow+1 with an INVALID record and tomorrow+2 with an unknown version
local r1 = Dungeon.mint(Config, (function() local rr = h:_require(RS.Rng).new(7); return function(n) return rr:below(n) end end)(), D + 2, 0)
r1.perfectMs += 5
days:SetAsync("d_" .. (D + 2), r1)
days:SetAsync("d_" .. (D + 3), { v = 99, day = D + 3 })

h:advance(60) -- stand in the antechamber until 10 s before midnight
local seg, x, z = 1, 72, -8
local fin = nil
for _ = 1, 60 * 200 do
	local remaining = 5 * FRAME -- a slow walk: about 100 s for the line
	while remaining > 0 and seg < #pts do
		local b = pts[seg + 1]
		local dx, dz = b.x - x, b.z - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
	end
	hrp.CFrame = CFrame.new(origin.X + x, origin.Y + 3, origin.Z + z)
	step(FRAME)
	for _, m in msgs do if m.state == "finished" or m.state == "void" then fin = m end end
	if fin then break end
end
truthy(math.floor(os.time() / 86400) == D + 1, "midnight passed during the run")
eq(fin and fin.state, "finished", "the run that straddled midnight still finishes on its own Door")
eq(fin and fin.door, D - Config.Day.Epoch, "…as the Door it started on (#" .. (D - Config.Day.Epoch) .. ")")
eq(fin and fin.newDoor, D + 1 - Config.Day.Epoch, "…and the card announces the new Door")
local oldBoard = h.services.DataStoreService:GetOrderedDataStore("SameDoor_Board_v1", "d" .. D)
local newBoard = h.services.DataStoreService:GetOrderedDataStore("SameDoor_Board_v1", "d" .. (D + 1))
truthy(oldBoard:GetAsync("u_5501") ~= nil, "the time went on yesterday's board (the day it was run on)")
eq(newBoard:GetAsync("u_5501"), nil, "…not on today's")
local recD1 = HttpService:JSONDecode(h.game:GetService("ServerStorage").SameDoor.Day.Value)
eq(recD1.day, D + 1, "the server minted and loaded the new day")
truthy(recD1.open ~= recD.open, "…a different dungeon")
h:advance(1.1)
R.RunAgain:simulateFireServer(me)
h:advance(0.05)
local again = msgs[#msgs]
eq(again and again.state, "ready", "Run again after midnight starts a run")
eq(again and again.door, D + 1 - Config.Day.Epoch, "…on the new Door")
R.Leave:simulateFireServer(me)
h:advance(1.1)

--============================================================ 3. an invalid stored record fails closed
offset += 86400
h:advance(2)
local info = dayMsgs[#dayMsgs]
eq(info and info.state, "failed", "a stored record that fails validation is refused")
local before = days:GetAsync("d_" .. (D + 2))
hrp.CFrame = CFrame.new(0, 3, 12)
prompt.Triggered:Fire(me)
h:advance(0.05)
truthy(string.find(toasts[#toasts], "failed its check", 1, true) ~= nil, "the arch refuses with a reason (" .. tostring(toasts[#toasts]) .. ")")
h:advance(40)
local after = days:GetAsync("d_" .. (D + 2))
eq(after.perfectMs, before.perfectMs, "the bad record is never re-minted over (a day's layout never changes mid-day)")
eq(after.open, r1.open, "…its passages are untouched")

--============================================================ 4. an unknown version
offset += 86400
h:advance(2)
local info2 = dayMsgs[#dayMsgs]
eq(info2 and info2.state, "outdated", "a record of an unknown version marks this server out of date")
eq(info2 and info2.message, "This server is out of date for today's Door; rejoin", "…and tells the player to rejoin")

local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end
print(string.format("check_samedoor_days: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor_days failed", 0) end
