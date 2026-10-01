-- SIGNAL LOST — REVIEW-1's regressions, through the REAL server. Run: luau check_signallost_review.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--
-- R1. A client that writes its own position pays the AIR of the vacuum it crosses (finding 1): the trusted path's
--     vacuum distance is charged, not only the module a tick ends in; an honest walk pays what it paid before.
-- R2. A leaving or shutting-down session stops (finding 2): no tick, splice or blackout after the leave, and no
--     save that re-takes the lock after the release, with 0.5-0.6 s of DataStore latency.
-- R3. BuyUpgrade answers a flood at most once per cooldown (finding 3), and a single call is still answered.
-- The reviewers' probes these come from: scratchpad rev_exploit_sl/robloxemu/check_rev_{trust,relock,shutdown,flood}.

local Harness = require("./emu/harness")
local Bot = require("../signal-lost/tests/Bot")

local h = Harness.new({ bundle = require("./build/signal-lost"), name = "signal-lost", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local DSS = h.services.DataStoreService
local ps = DSS:GetDataStore("SignalLost_v1")
local SS = h.game:GetService("ServerStorage")
local Vector3, CFrame = h.instance.datatypes.Vector3, h.instance.datatypes.CFrame

-- DataStore latency for R2: same-key requests stay in the order they were sent, the way Roblox queues them
local LAT = 0
local origUpdate = ps.UpdateAsync
ps.UpdateAsync = function(self, key, fn)
	if LAT > 0 and coroutine.running() then h.scheduler:wait(LAT) end
	return origUpdate(self, key, fn)
end
local NOW = os.time()
ps:SetAsync("u_9301", { data = { v = 1, salvage = 5000, salvageEarned = 5000, best = 3, bestAt = NOW - 100, up = { tank = 0, boots = 0 } } })

local okBoot, errBoot = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads (" .. tostring(errBoot) .. ")")
local W = h.workspace
local Config = h.modules["shared/Config"].value
local AirMod = h.modules["shared/Air"].value

-- every vacuum second the SERVER applies goes through Air.step(cfg, suit, seconds, true): count them
local drained = 0
local origStep = AirMod.step
AirMod.step = function(cfg, s, dt, vac)
	if vac and type(dt) == "number" and dt > 0 then drained += dt end
	return origStep(cfg, s, dt, vac)
end

local function dbgOf(p) return SS.SignalDebug:FindFirstChild("Run_" .. p.UserId) end
local function centre(p, id)
	local d = dbgOf(p)
	local N, Z = d:GetAttribute("Grid"), d:GetAttribute("ZoneIndex")
	local cx, cy = (id - 1) % N, (id - 1) // N
	return Vector3.new(400 * Z + (cx - (N - 1) / 2) * 32, 0, (cy - (N - 1) / 2) * 32)
end

--=========================================================================== R1
section("R1. a client that writes its own position pays the AIR of the vacuum it crosses")
do
	local plr = h:join("Writer", 9001)
	h.Players:simulateSpawn(plr, W)
	local bot = Bot.new(h, plr, {})
	bot:waitSeconds(1)
	truthy(bot:board() and bot:waitPhase("sector", 6), "set-up: in sector 1")
	bot:waitSeconds(0.3)
	local d = dbgOf(plr)
	local dock = d:GetAttribute("DockCell")
	local mods = bot:modules()
	local V
	for nb, lamp in mods[dock].lamps do if lamp == "VACUUM" then V = nb end end
	truthy(V ~= nil, "set-up: the dock has a VACUUM neighbour (sector 1's onboarding salvage)")
	local VS = Config.Move.VacWalkSpeed
	local HALFV = 16 / VS -- the vacuum half of a centre-to-centre crossing, walked: 1.33 s

	-- the honest walk first: dock -> V -> dock pays the time it spends in vacuum, as before the fix
	drained = 0
	truthy(bot:cross(mods, dock, V, "sector"), "honest: into the vacuum module")
	local m2 = bot:modules()
	truthy(bot:cross(m2, V, dock, "sector"), "honest: and back to the dock")
	bot:waitSeconds(0.3)
	print(string.format("  honest dock -> V -> dock: %.2f s of AIR applied", drained))
	truthy(drained >= 2 * HALFV - 0.25 and drained <= 2 * HALFV + 0.35,
		string.format("honest: dock -> V -> dock costs about the 2 x 1.33 s it walks in vacuum (%.2f)", drained))

	-- the writer: stand in the dock 3.5 s (the trust banks a full burst at the air speed), then claim V's centre
	local hrp = bot:hrp()
	local dc, vc = centre(plr, dock), centre(plr, V)
	hrp.CFrame = CFrame.new(dc + Vector3.new(0, 2.51, 0))
	bot:waitSeconds(3.5)
	local tank = bot:state().tank
	eq(bot:state().air, tank, "set-up: a full tank in the dock")
	drained = 0
	local visit = 0
	local ticks = 0
	while d:GetAttribute("TrustedCell") ~= V and ticks < 10 do
		hrp.CFrame = CFrame.new(vc + Vector3.new(0, 2.51, 0))
		bot:tick()
		ticks += 1
	end
	eq(d:GetAttribute("TrustedCell"), V, "the written position is trusted into V")
	print(string.format("  writer dock -> V centre: %d tick(s), %.2f s of AIR applied", ticks, drained))
	truthy(drained >= HALFV - 0.05,
		string.format("crossing into V between ticks costs the 16 vacuum studs walked (>= %.2f s), not one tick (%.2f)", HALFV - 0.05, drained))
	bot:waitSeconds(0.25)
	local st = bot:state()
	truthy(st and tank - st.air >= HALFV - 0.05,
		string.format("…and the State says so: AIR %.2f of %d", st and st.air or -1, tank))
	visit = drained

	-- and straight back over the opened route, ending in air: the exit tick is charged too. The 0.25 s just paid
	-- standing in V is credit (Air.vacuumCharge, at most CreditSeconds): it covers part of the walk out
	drained = 0
	ticks = 0
	while d:GetAttribute("TrustedCell") ~= dock and ticks < 10 do
		hrp.CFrame = CFrame.new(dc + Vector3.new(0, 2.51, 0))
		bot:tick()
		ticks += 1
	end
	eq(d:GetAttribute("TrustedCell"), dock, "the written position is trusted back into the dock")
	print(string.format("  writer V centre -> dock: %d tick(s), %.2f s of AIR applied", ticks, drained))
	truthy(drained >= HALFV - Config.Air.CreditSeconds - 0.05,
		string.format("leaving vacuum between ticks costs the 16 vacuum studs walked, less the credit (>= %.2f s), not 0 (%.2f)",
			HALFV - Config.Air.CreditSeconds - 0.05, drained))
	visit += drained
	print(string.format("  writer's whole visit to V (in, 0.25 s standing, out): %.2f s of AIR", visit))
	truthy(visit >= 2 * HALFV - 0.05,
		string.format("the writer's whole visit costs at least what walking 32 vacuum studs costs (%.2f >= %.2f)", visit, 2 * HALFV - 0.05))
	h:leave(plr)
	bot:waitSeconds(0.5)
end

--=========================================================================== R2
section("R2. a leaving or shutting-down session stops: no stray lock, no splice after the leave")
local function fresh(uid)
	local p = h:join("P" .. uid, uid)
	h.Players:simulateSpawn(p, W)
	local b = Bot.new(h, p, {})
	b:waitSeconds(1)
	return p, b
end
local function leaveNow(p, lat)
	LAT = lat
	h.scheduler:spawn(function() h:leave(p) end) -- Roblox runs PlayerRemoving on its own thread
	local c = p.Character
	if c then c:Destroy() end -- and removes the character while the handler waits
end
local function settle(seconds)
	for _ = 1, math.floor(seconds / 0.1) do h:advance(0.1) end
	LAT = 0
end
local function stored(uid)
	local rec = ps:GetAsync("u_" .. uid)
	return rec and rec.lock, rec and rec.data or {}
end
local function rejoinBoards(tag, uid)
	local p, b = fresh(uid)
	local st = b:state()
	eq(st and st.saving, true, tag .. ": the rejoin holds its own file")
	truthy(b:board(), tag .. ": and the LIFT takes it down")
	h:leave(p)
	b:waitSeconds(0.5)
end

do -- A. leave in the last 0.4 s of the LIFT ride
	local uid = 9201
	local p, b = fresh(uid)
	truthy(b:board(), "A set-up: riding")
	b:waitSeconds(2.6)
	eq(b:phase(), "transit", "A set-up: still riding")
	leaveNow(p, 0.5)
	settle(6)
	local lock, data = stored(uid)
	eq(lock, nil, "A: left in the last 0.4 s of the ride, 0.5 s latency: the lock is released and stays released")
	eq(data.open, nil, "A: the attempt is settled")
	rejoinBoards("A", uid)
end

do -- B. leave hypoxic with 0.2-0.4 s of grace left
	local uid = 9202
	local p, b = fresh(uid)
	truthy(b:board() and b:waitPhase("sector", 5), "B set-up: in a sector")
	local mods = b:modules()
	local dock = dbgOf(p):GetAttribute("DockCell")
	local V
	for nb, lamp in mods[dock].lamps do if lamp == "VACUUM" then V = nb end end
	truthy(b:cross(mods, dock, V, "sector"), "B set-up: into vacuum")
	for _ = 1, 400 do
		local st = b:state()
		if st.hypoxic and st.grace <= 0.4 then break end
		b:tick()
	end
	truthy(b:state().hypoxic, "B set-up: hypoxic at the leave")
	leaveNow(p, 0.5)
	settle(8)
	local lock, data = stored(uid)
	eq(lock, nil, "B: left hypoxic, 0.5 s latency: the lock is released and stays released")
	eq(data.blackouts or 0, 0, "B: no blackout happened after the leave")
	eq(data.open, nil, "B: the attempt is settled")
	rejoinBoards("B", uid)
end

do -- C. leave while the splice countdown runs
	local uid = 9203
	local p, b = fresh(uid)
	truthy(b:board() and b:waitPhase("sector", 5), "C set-up: in a sector")
	local tick0 = b.tick
	b.tick = function(self)
		tick0(self)
		if self:saw("splicing") then error("STOP", 0) end
	end
	pcall(function() b:playSector(300) end)
	b.tick = tick0
	b:waitSeconds(1.7)
	local st = b:state()
	truthy(st.splicing > 0 and st.spliced == false, string.format("C set-up: splicing %.2f, not spliced yet", st.splicing))
	local carried = st.carried or 0
	leaveNow(p, 0.5)
	settle(6)
	local lock, data = stored(uid)
	eq(lock, nil, "C: left 0.3 s before the splice, 0.5 s latency: the lock is released and stays released")
	eq(data.best, 0, "C: the splice did not complete after the leave")
	eq(data.salvage, carried // 2, string.format("C: paid once, the leave's half of %d", carried))
	-- the board is a separate store: a splice that completed after the leave would write relay 1 to it on its own
	local ov = DSS:GetOrderedDataStore("SignalLost_Relays_v1"):GetAsync("u_" .. uid)
	eq(if type(ov) == "number" then math.floor(ov / 2e9) else 0, 0, "C: the public board did not record the relay the player left before splicing")
	rejoinBoards("C", uid)
end

do -- D. a shutdown with six players mid-ride, 0.6 s latency
	local players = {}
	for i = 1, 6 do
		local p = h:join("S" .. i, 9500 + i)
		h.Players:simulateSpawn(p, W)
		players[i] = p
	end
	h:advance(1)
	local lift = W.Lifeboat.Lift.LiftPad.Position
	for i = 1, 6 do
		players[i].Character.HumanoidRootPart.CFrame = CFrame.new(lift + Vector3.new(0, 2.71, 0))
		h:advance(0.5)
	end
	h:advance(0.6)
	LAT = 0.6
	local done = false
	h.scheduler:spawn(function() h.game:runBindToClose(); done = true end)
	for i = 1, 6 do local c = players[i].Character; if c then c:Destroy() end end
	local guard = 0
	while not done and guard < 600 do h:advance(0.05); guard += 1 end
	truthy(done, "D: BindToClose returns")
	print(string.format("  BindToClose returned after %.2f s", guard * 0.05))
	-- the six releasing writes run at once: the shutdown waits for the slowest, not their sum (6 x 0.6 = 3.6 s
	-- before the fix), so it stays inside Roblox's 30 s at any player count
	truthy(guard * 0.05 <= 1.5, string.format("D: six players' writes at 0.6 s latency finish in at most 1.5 s (%.2f)", guard * 0.05))
	LAT = 0
	local held, open = 0, 0
	for i = 1, 6 do
		local lock, data = stored(9500 + i)
		if lock then held += 1 end
		if data.open then open += 1 end
	end
	eq(held, 0, "D: a shutdown at 0.6 s latency leaves none of 6 riders' files locked")
	eq(open, 0, "D: and every attempt is settled")
	for i = 1, 6 do h:leave(players[i]) end
	h:advance(0.5)
end

--=========================================================================== R3
section("R3. BuyUpgrade answers a flood at most once per cooldown; a single call is still answered")
do
	-- the server is past its BindToClose in this harness; a fresh server would be cleaner, but nothing in R3 touches
	-- closing: the buyer joins after it, as a new session
	local p, b = fresh(9301)
	local remotes = h.ReplicatedStorage.SignalRemotes
	local function replies() local n = 0 for _, r in remotes.Notice:getSent() do if r.player == p then n += 1 end end return n end
	for _, case in { { "id 42", 42 }, { "id 'x'", "x" }, { "'tank' away from the fabricator", "tank" } } do
		local n0, w0 = replies(), ps.__calls
		for _ = 1, 1000 do remotes.BuyUpgrade:simulateFireServer(p, case[2]) end
		h:advance(0.05)
		local n = replies() - n0
		print(string.format("  %s: 1000 calls in one frame -> %d replies, %d DataStore calls", case[1], n, ps.__calls - w0))
		truthy(n >= 1 and n <= 2, string.format("%s: 1000 calls in one frame get at most 2 replies (%d), at least 1", case[1], n))
		b:waitSeconds(0.6)
	end
	local n0 = replies()
	remotes.BuyUpgrade:simulateFireServer(p, 42)
	b:waitSeconds(0.1)
	eq(replies() - n0, 1, "one nonsense call, after the cooldown: answered once")
	b:drainNotices()
	eq(b.toasts[#b.toasts], "That upgrade does not exist.", "…with the reason")
	b:waitSeconds(0.6)
	local fab = W.Lifeboat.Fabricator
	b:walkTo(Vector3.new(fab.Position.X, 0, fab.Position.Z + 3), "hub")
	b:waitSeconds(1)
	local n1, w1 = replies(), ps.__calls
	for _ = 1, 1000 do remotes.BuyUpgrade:simulateFireServer(p, "tank") end
	h:advance(0.05)
	b:waitSeconds(0.3)
	local n = replies() - n1
	print(string.format("  'tank' at the fabricator: 1000 calls -> %d replies, %d DataStore calls, rank %d", n, ps.__calls - w1, b:state().up.tank))
	eq(b:state().up.tank, 1, "at the fabricator, 1000 calls buy one rank")
	truthy(n <= 2, string.format("…and get at most 2 replies (%d)", n))
	h:leave(p)
end

print(string.format("\nsignal-lost review: %d passed, %d failed, %d errors", passed, failed, #h:errors()))
for _, e in h:errors() do print("ERR " .. e) end
assert(failed == 0 and #h:errors() == 0, "signal-lost review check failed")
