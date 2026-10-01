-- The Same Door — every threat row of DESIGN §11, through the REAL server's Heartbeat monitor.
-- Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--       luau check_samedoor_cheat.luau 2>&1
--
-- tests/RunCheck.spec pins the pure guard. This file drives the built server the way a client can:
-- by moving its own character and by firing the three client->server remotes. Each threat must void
-- the run with a reason the player can read, and must write NOTHING to the board or the profile. An
-- honest walker in the same server must still be ranked (a guard that voids everything would pass
-- every other row). Forged remotes: junk arguments are ignored, spam is rate-limited, and nothing a
-- remote says can start a clock, take a seal or finish a run.

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")

local h = Harness.new({ bundle = bundle, name = "same-door-cheat", viewport = { 1280, 720 }, touch = false })
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
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(20261002 + unseeded * 7919)
		end
		return realRandom.new(seed)
	end,
}

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

assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local RS = h.services.ReplicatedStorage
local R = RS.SameDoorRemotes
local Config = h:_require(RS.Config)
local Dungeon = h:_require(h.services.ServerScriptService.Dungeon)
local HttpService = h.game:GetService("HttpService")
local rec = HttpService:JSONDecode(h.game:GetService("ServerStorage").SameDoor.Day.Value)
local world = Dungeon.fromRecord(Config, rec)
local _, path = Dungeon.perfectPath(Config, world)
local dayIndex = math.floor(os.time() / 86400)
local boardStore = h.services.DataStoreService:GetOrderedDataStore("SameDoor_Board_v1", "d" .. dayIndex)
local playerStore = h.services.DataStoreService:GetDataStore("SameDoor_Players_v1")
local W = Config.Grid.W

local CHEAT = 6666
local cheat = h:join("Cheater", CHEAT)
h:advance(0.5)
local char = h.Players:simulateSpawn(cheat, ws)
h:advance(0.2)
local hrp = char.HumanoidRootPart

local msgs = {}
R.Run.OnClientEvent:Connect(function(p) table.insert(msgs, p) end)
local toasts = {}
R.Toast.OnClientEvent:Connect(function(m) table.insert(toasts, m) end)

local origin = Vector3.new(0, 0, 1000)
local function startRun()
	local n = #msgs
	h:advance(1.1)
	if #msgs == 0 or msgs[#msgs].state == "hub" or msgs[#msgs].state == nil then
		hrp.CFrame = CFrame.new(0, 3, 12)
		ws.Hub.Arch.Doorway.EnterPrompt.Triggered:Fire(cheat)
	else
		R.RunAgain:simulateFireServer(cheat)
	end
	h:advance(0.05)
	for i = n + 1, #msgs do if msgs[i].state == "ready" then return msgs[i] end end
	return nil
end

-- walk the perfect line at `speed`, letting `mutate(k, x, y, z)` change the sample the server sees.
-- Returns the final state message ("finished" or "void") or nil.
local function run(speed, mutate, maxT)
	local ready = startRun()
	assert(ready, "a run started")
	local pts = { { x = 72, z = -8 } }
	for _, p in path do table.insert(pts, p) end
	local seg, x, z, k = 1, 72, -8, 0
	local n = #msgs
	for _ = 1, 60 * (maxT or 80) do
		k += 1
		local remaining = speed * FRAME
		while remaining > 0 and seg < #pts do
			local b = pts[seg + 1]
			local dx, dz = b.x - x, b.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
		local sx, sy, sz = x, 3, z
		if mutate then sx, sy, sz = mutate(k, x, 3, z) end
		hrp.CFrame = CFrame.new(origin.X + sx, origin.Y + sy, origin.Z + sz)
		step(FRAME)
		for i = n + 1, #msgs do
			if msgs[i].state == "finished" or msgs[i].state == "void" then return msgs[i] end
		end
	end
	return nil
end

local function noWrites(label)
	local last = msgs[#msgs]
	print(string.format("  %-15s -> %s: %s", label, tostring(last and last.state), tostring(last and last.reason)))
	eq(boardStore:GetAsync("u_" .. CHEAT), nil, label .. ": nothing on the board")
	local prof = playerStore:GetAsync("u_" .. CHEAT)
	eq(prof and prof.data and prof.data.today and prof.data.today.bestMs, nil, label .. ": no best in the profile")
end

--============================================================ each threat voids, writes nothing
do -- teleport 30 studs along the route
	local teleported = false
	local r = run(16, function(k, x, y, z)
		if k >= 200 then teleported = true; return x, y, math.min(z + 30, 140) end
		return x, y, z
	end)
	eq(r and r.state, "void", "teleport: the run is voided")
	truthy(r and r.reason and #r.reason > 20, "teleport: the void says why (" .. tostring(r and r.reason) .. ")")
	noWrites("teleport")
end

do -- speed hack: 1.6x the whole way
	local r = run(16 * 1.6, nil)
	eq(r and r.state, "void", "a 1.6x speed hack is voided")
	truthy(r and string.find(r.reason, "faster than walking", 1, true) ~= nil, "…as moving faster than walking (" .. tostring(r and r.reason) .. ")")
	noWrites("speed")
end

do -- REVIEW-1 finding 2: a script walking the PUBLISHED line 3 % fast. The first build's P was looser
	-- than the server's own check, so this passed (the reviewer measured up to 1.095x on this day).
	local r = run(16 * 1.03, nil)
	eq(r and r.state, "void", "a script walking the published perfect line at 1.03x is voided")
	truthy(r and string.find(r.reason, "shortest line", 1, true) ~= nil, "…by the whole-run check (" .. tostring(r and r.reason) .. ")")
	noWrites("P at 1.03x")
end

do -- a 2x burst for one second, honest otherwise
	local extra = 0
	local r = run(16, function(k, x, y, z)
		if k > 240 and k <= 300 then extra += 16 * FRAME end
		-- push ahead along +z in the same cell column only while it stays in the grid
		return x, y, math.clamp(z + extra, -15, 143)
	end)
	eq(r and r.state, "void", "a 2x burst for a second is voided")
	noWrites("burst")
end

do -- noclip: find a closed wall next to the route's first cells and walk through it
	local m = world.maze
	local a, b
	for i = 0, W * W - 1 do
		if i % W + 1 < W and not m.openE[i] and not m.openE[i] then
			a, b = i, i + 1
			break
		end
	end
	local ax, az = (a % W + 0.5) * 16, (a // W + 0.5) * 16
	local bx, bz = (b % W + 0.5) * 16, (b // W + 0.5) * 16
	-- reach cell a honestly would need a route; instead: after the line, a straight walk through
	-- cells from the entrance ignoring every wall (the noclip is the whole walk)
	local r = run(16, function(k, x, y, z)
		if k < 40 then return x, y, z end
		local t = math.min((k - 40) / 120, 1)
		return 72 + (ax - 72) * t + (bx - ax) * math.max(0, (k - 160) / 60), y, 8 + (az - 8) * t
	end, 12)
	eq(r and r.state, "void", "walking through walls is voided")
	truthy(r and (string.find(r.reason, "wall", 1, true) or string.find(r.reason, "jumped", 1, true)) ~= nil,
		"…as a wall or a jump between cells that do not connect (" .. tostring(r and r.reason) .. ")")
	noWrites("noclip")
end

do -- fly over the walls
	local r = run(16, function(k, x, y, z)
		if k > 120 then return x, 16, z end
		return x, y, z
	end)
	eq(r and r.state, "void", "flying over the walls is voided")
	truthy(r and string.find(r.reason, "height", 1, true) ~= nil, "…as leaving the halls' height (" .. tostring(r and r.reason) .. ")")
	noWrites("fly")
end

do -- lag switch: the crossing seen late, then 3 s of walking caught up in one sample
	local frozen = nil
	local r = run(16, function(k, x, y, z)
		if k == 20 then frozen = { x, z } end
		if k > 20 and k <= 200 then return frozen[1], y, frozen[2] end
		return x, y, z
	end)
	eq(r and r.state, "void", "a lag-switched start is voided")
	noWrites("lag switch")
end

--============================================================ the ready phase (REVIEW-1 finding 1)
-- Before the line the server ignores samples from outside the lane (the pivot race). A script owns
-- its character: it steps out of the lane, waits, and re-appears inside seal 1's circle, or across
-- a closed entrance wall. The re-entry must void before it can start a clock, take a seal or reveal
-- a cell; the first review found it started the clock on that very sample and topped the board.
do
	local function cellsSentFor(runId)
		local n = 0
		for _, rec2 in R.Cell:sentTo(cheat) do
			if rec2.args[1].run == runId then n += #rec2.args[1].cells end
		end
		return n
	end
	local function readyHop(awaySeconds, lx, lz)
		local ready = startRun()
		assert(ready, "a run started")
		local o = Vector3.new(ready.origin.x, ready.origin.y, ready.origin.z)
		local n = #msgs
		local arrival = cellsSentFor(ready.run)
		local function at(x, z) hrp.CFrame = CFrame.new(o.X + x, o.Y + 3, o.Z + z) end
		at(72, -8)
		for _ = 1, 10 do step(FRAME) end
		at(72, -0.05)
		step(FRAME)
		at(-60, -60) -- out of the lane, anywhere
		local t = 0
		while t < awaySeconds do step(0.25); t += 0.25 end
		at(lx, lz)
		for _ = 1, 6 do step(FRAME) end
		local states = {}
		local last = nil
		for i = n + 1, #msgs do
			if msgs[i].run == ready.run and msgs[i].state then
				states[msgs[i].state] = true
				if msgs[i].taken then states.taken = true end
				last = msgs[i]
			end
		end
		if last == nil or last.state ~= "void" then
			-- (only a broken guard gets here) leave the run so the next case can start one
			h:advance(1.1)
			R.Leave:simulateFireServer(cheat)
			h:advance(1.1)
		end
		return states, last, cellsSentFor(ready.run) - arrival
	end
	local s1 = world.seals[1]
	local sx, sz = (s1 % W + 0.5) * 16, (s1 // W + 0.5) * 16
	local st, last, extra = readyHop(55, sx - 3.5, sz)
	eq(st.running, nil, "ready-phase hop into seal 1's circle (55 s out of the lane): the clock never starts")
	eq(st.taken, nil, "…no seal is taken")
	eq(extra, 0, "…no cell beyond the arrival batch is sent (no map dump)")
	eq(last and last.state, "void", "…the run is void")
	truthy(last and last.reason and string.find(last.reason, "antechamber", 1, true) ~= nil,
		"…and the void says why (" .. tostring(last and last.reason) .. ")")
	noWrites("ready hop")
	-- across the entrance cell's west or east wall, whichever is closed (else 15 studs past the line)
	local m = world.maze
	local ex = world.entrance
	local lx = if not m.openE[ex - 1] then 62 elseif not m.openE[ex] then 82 else 72
	local lz = if lx == 72 then 15 else 0.5
	local st2, last2 = readyHop(55, lx, lz)
	eq(st2.running, nil, string.format("ready-phase hop to (%d, %.1f) after 55 s away: the clock never starts", lx, lz))
	eq(last2 and last2.state, "void", "…the run is void")
	noWrites("ready wall skip")
end

--============================================================ forged remotes do nothing
do
	local before = #msgs
	R.RunAgain:simulateFireServer(cheat, { timeMs = 1, seals = 3, finished = true })
	h:advance(0.05)
	local finishedByRemote = false
	for i = before + 1, #msgs do if msgs[i].state == "finished" then finishedByRemote = true end end
	eq(finishedByRemote, false, "a RunAgain carrying {timeMs = 1, seals = 3} finishes nothing (its arguments are ignored)")
	local t0 = #toasts
	for _ = 1, 20 do R.RunAgain:simulateFireServer(cheat) end
	local limited = 0
	for i = t0 + 1, #toasts do if toasts[i] == "One moment..." or toasts[i] == "You are already in a run." then limited += 1 end end
	truthy(limited >= 19, string.format("20 RunAgain fires in one frame: %d refused with a reason", limited))
	h:advance(1.1)
	R.Leave:simulateFireServer(cheat)
	h:advance(1.1)
	local t1 = #toasts
	R.Leave:simulateFireServer(cheat)
	eq(toasts[#toasts], "You are not in a run.", "Leave outside a run is refused with a reason")
	truthy(#toasts > t1, "…never silently")
	noWrites("forged remotes")
end

--============================================================ an honest walker in the same server is ranked
local HONEST = 6667
local honest = h:join("Honest", HONEST)
h:advance(0.5)
local hchar = h.Players:simulateSpawn(honest, ws)
h:advance(0.2)
local hhrp = hchar.HumanoidRootPart
local hmsgs = {}
R.Run.OnClientEvent:Connect(function(p) table.insert(hmsgs, p) end)
local cellsTo = {}
hhrp.CFrame = CFrame.new(0, 3, 12)
ws.Hub.Arch.Doorway.EnterPrompt.Triggered:Fire(honest)
h:advance(0.05)
local hready = nil
for _, rec in R.Run:sentTo(honest) do
	local m = rec.args[1]
	if m.state == "ready" and m.origin then hready = m end
end
-- (the cheater left its last run above, so its lane went back to the pool: REVIEW-1 lanes)
truthy(hready ~= nil, "the honest player gets a lane (x = " .. tostring(hready and hready.origin.x) .. ")")
local ho = Vector3.new(hready.origin.x, hready.origin.y, hready.origin.z)
do
	local pts = { { x = 72, z = -8 } }
	for _, p in path do table.insert(pts, p) end
	local seg, x, z = 1, 72, -8
	local done = nil
	for _ = 1, 60 * 80 do
		local remaining = 16 * FRAME
		while remaining > 0 and seg < #pts do
			local b = pts[seg + 1]
			local dx, dz = b.x - x, b.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
		hhrp.CFrame = CFrame.new(ho.X + x, ho.Y + 3, ho.Z + z)
		step(FRAME)
		for _, m in hmsgs do
			if m.run == hready.run and (m.state == "finished" or m.state == "void") then done = m end
		end
		if done then break end
	end
	eq(done and done.state, "finished", "the honest walker at 16 studs/s is ranked (" .. tostring(done and done.reason) .. ")")
	-- walking the published line, it finishes in P: never under (REVIEW-1 finding 5), at most the frame
	-- in which this walker stops dead on the line's last point over
	truthy(done and done.timeMs >= rec.perfectMs - 1 and done.timeMs <= rec.perfectMs + 18,
		string.format("…in %s ms against P %d ms (never under P)", tostring(done and done.timeMs), rec.perfectMs))
	truthy(boardStore:GetAsync("u_" .. HONEST) ~= nil, "…and on the board")
end
-- a player's cells go to that player only
do
	for _, rec2 in R.Cell:getSent() do
		if rec2.player == honest then
			for _, other in R.Cell:getSent() do
				if other.player == cheat and other.args[1].run == rec2.args[1].run then cellsTo.mixed = true end
			end
		end
	end
	eq(cellsTo.mixed, nil, "no Cell payload of one player's run was sent to another player")
end

local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end
print(string.format("check_samedoor_cheat: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor_cheat failed", 0) end
