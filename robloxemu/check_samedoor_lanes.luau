-- The Same Door — lanes go back to the pool when a player leaves them (REVIEW-1, reviewer 2,
-- finding 5). Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--                   luau check_samedoor_lanes.luau 2>&1
--
-- The first build kept a player's lane for the whole session (until they left the GAME), so once 12
-- players had each entered one run, a 13th could never run, however long the 12 sat in the hub, and
-- the toast's "in a moment" was untrue. A lane is now held from the arch until the player is back in
-- the hub (Leave run, the Hub button, death or a reset): standing on the finish card keeps it (Run
-- again reuses it). MaxPlayers 12 = MaxLanes is a place setting (needs-Studio); this is the code's half.

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")
local h = Harness.new({ bundle = bundle, name = "same-door-lanes", viewport = { 1280, 720 }, touch = false })
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
Random = { new = function(seed) if seed == nil then unseeded += 1; return realRandom.new(5150 + unseeded) end return realRandom.new(seed) end }

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.services.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local R = RS.SameDoorRemotes
local Config = h:_require(RS.Config)
local HB = h.services.RunService.Heartbeat
local function step(dt) h:advance(dt); HB:Fire(dt) end

local function lastRun(plr)
	local last = nil
	for _, rec in R.Run:sentTo(plr) do
		local p = rec.args[1]
		if p.state then last = p end
	end
	return last
end
local function lastToast(plr)
	local sent = R.Toast:sentTo(plr)
	return sent[#sent] and sent[#sent].args[1]
end
local players = {}
local function newPlayer(k)
	local p = h:join("Lane" .. k, 7100 + k)
	h:advance(0.2)
	local c = h.Players:simulateSpawn(p, ws)
	h:advance(0.2)
	players[k] = { p = p, hrp = c.HumanoidRootPart }
	return players[k]
end
local function enter(pl)
	pl.hrp.CFrame = CFrame.new(0, 3, 12)
	ws.Hub.Arch.Doorway.EnterPrompt.Triggered:Fire(pl.p)
	h:advance(0.1)
	local r = lastRun(pl.p)
	return (r ~= nil and r.state == "ready" and r.origin ~= nil), r
end

local N = Config.World.MaxLanes
for k = 1, N do
	local ok = enter(newPlayer(k))
	truthy(ok, "player " .. k .. " of " .. N .. " gets a lane")
end
local extra = newPlayer(N + 1)
local ok13 = enter(extra)
eq(ok13, false, "with " .. N .. " runs going, player " .. (N + 1) .. " gets no lane")
truthy(string.find(tostring(lastToast(extra.p)), "hub", 1, true) ~= nil,
	"…and the toast says when one frees (" .. tostring(lastToast(extra.p)) .. ")")

-- players leave through the pause sheet: their lanes free up
h:advance(1.2)
R.Leave:simulateFireServer(players[1].p)
h:advance(1.2)
local ok2 = enter(extra)
truthy(ok2, "after player 1 left their run (Leave run), player " .. (N + 1) .. " gets a lane")
-- player 2: still in a run; Leave, then a 14th player needs that lane
h:advance(1.2)
R.Leave:simulateFireServer(players[2].p)
h:advance(1.2)
local p14 = newPlayer(N + 2)
truthy((enter(p14)), "after player 2 left too, player " .. (N + 2) .. " gets a lane")

-- player 3 dies in the antechamber: back in the hub, the lane is free again
local hum3 = players[3].p.Character.Humanoid
hum3:TakeDamage(500)
h:advance(0.5)
local p15 = newPlayer(N + 3)
truthy((enter(p15)), "after player 3 died in a run, player " .. (N + 3) .. " gets a lane")

-- the lane is NOT taken from someone still in a run: everybody else is mid-run
local p16 = newPlayer(N + 4)
eq((enter(p16)), false, "with every lane in a live run, the next player still waits")

-- player 5's run is voided (a jump deep into the halls); on the void card they press Hub: free
do
	local r5 = lastRun(players[5].p)
	local o = Vector3.new(r5.origin.x, r5.origin.y, r5.origin.z)
	players[5].hrp.CFrame = CFrame.new(o.X + 72, o.Y + 3, o.Z + 60)
	for _ = 1, 3 do step(1 / 60) end
	eq(lastRun(players[5].p).state, "void", "player 5's run is void")
	eq((enter(p16)), false, "a void run still holds its lane (the player stands in it, on the void card)")
	h:advance(1.2)
	R.GoHub:simulateFireServer(players[5].p)
	h:advance(1.2)
	truthy((enter(p16)), "after player 5 pressed Hub on the void card, the waiting player gets a lane")
end

-- a player back in the hub can run again (gets some lane once one is free)
h:advance(1.2)
R.Leave:simulateFireServer(players[4].p)
h:advance(1.2)
truthy((enter(players[1])), "player 1, back from the hub, gets a lane again")

local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end
print(string.format("check_samedoor_lanes: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor_lanes failed", 0) end
