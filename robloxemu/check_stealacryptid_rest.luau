-- Steal a Cryptid - REST, through the REAL server, the REAL HUD and the REAL night client.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_rest.luau 2>&1
--
-- Rest is a state of THIS player's client: the HUD's Rest button sits you down by a campfire at home and
-- the night's critters leave you alone. It must never become an exploit, so this file checks both what it
-- does and everything it must NOT do:
--   1. the button: sit, campfire, soft focus, the chip says poachers still come; a minute of rest with
--      hazards made rapid launches none (the clock is frozen); moving wakes you and they return;
--   2. not a panic button: pressed with a hazard inbound it only queues, the hazard still arrives, a hit
--      voids the request; stepping out of the ring keeps it and rest starts once the sky is clear;
--   3. idle rest: standing still 20 s pauses them too (not seated, no campfire);
--   4. a raid is never paused: starting one while resting ends the rest on the teleport, and in a camp
--      the button is gone and a press does nothing;
--   5. income is never protected: jars fill at the same rate while resting, and the first poacher comes
--      while you rest, on the server's schedule, and takes half the jar it walked to;
--   6. the clients fire no remote of their own, at any point.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Night = require("../steal-a-cryptid/src/shared/Night")
local Economy = require("../steal-a-cryptid/src/shared/Economy")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-rest", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local N = Config.Night
local Hz = N.Hazards
local T = N.Text
local W = Config.World

local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 9902
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "dogman", jar = 0 }
	cages[4] = { sp = "jackalope", jar = 0 }
	-- two cryptids: the first poacher comes FirstAfterSeconds into the session
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 1000, savedAt = NOW, cagesUnlocked = 3, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local GameHz = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Night.Hazards
local function rapid(on)
	GameHz.IntervalMin = if on then 0.05 else Hz.IntervalMin
	GameHz.IntervalMax = if on then 0.05 else Hz.IntervalMax
end
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local serverCalls, ownCalls = 0, 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then r.OnServerEvent:Connect(function() serverCalls += 1 end) end
end
local function fireServer(name, plr, ...)
	ownCalls += 1
	remotes:FindFirstChild(name):simulateFireServer(plr, ...)
end
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

rapid(true)
local plr = h:join("Rester", ME)
local joinedAt = h.scheduler:now()
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
local okNight, errNight = h:tryRun("client/Night.client")
truthy(okNight, "Night.client loads (" .. tostring(errNight) .. ")")
if not okNight then error("Night.client did not load: " .. tostring(errNight), 0) end

local folder = h.workspace:FindFirstChild("CryptidNight")
local hudRoot = plr.PlayerGui.CryptidHud.Root
local bus = plr.PlayerGui.CryptidHud.NightBus
local restButton = hudRoot.Toggles:FindFirstChild("RestToggle")
truthy(restButton ~= nil, "the HUD has a Rest toggle in its top-right row")
local remState = remotes:FindFirstChild("State")
local function st()
	local sent = remState:sentTo(plr)
	return sent[#sent].args[1]
end
local dof = h.Lighting:FindFirstChild("CryptidRestFocus")

local cam = h.workspace.CurrentCamera
local simTime = 0
local launches = 0
local inFlightNow = false
local walker = nil
local function flying()
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and string.find(d.Name, "^Hazard_%a+_") then return true end
	end
	return false
end
local function campfireParts()
	local n, pos = 0, nil
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 9) == "Campfire_" then
			n += 1
			if d.Name == "Campfire_Flame" then pos = d.Position end
		end
	end
	return n, pos
end
local hitCount = 0
local wasStand = false
local function frame(dt)
	if walker then
		walker.phase += dt
		local p = walker.centre + Vector3.new(math.cos(walker.phase) * 6, 0, math.sin(walker.phase) * 6)
		hrp.CFrame = CFrame.new(p)
		hum.MoveDirection = Vector3.new(-math.sin(walker.phase), 0, math.cos(walker.phase))
	end
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	local f = flying()
	if f and not inFlightNow then launches += 1 end
	inFlightNow = f
	if hum.PlatformStand == true and not wasStand then hitCount += 1 end
	wasStand = hum.PlatformStand == true
end
local function run(seconds, until_)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		frame(1 / 30)
		if until_ and until_() then return true end
	end
	return false
end

run(1.5)
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
local lair = plot.Lair
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local function apron(x, z) return frameCF:PointToWorldSpace(Vector3.new(x, W.RootHeight, z)) end
local function standAt(pos)
	walker = nil
	hrp.CFrame = CFrame.new(pos)
	hum.MoveDirection = Vector3.new(0, 0, 0)
end
local function walkAround(pos) walker = { centre = pos, phase = 0 } end
local function press() restButton.Activated:Fire() end

--============================================================ 1. the button

standAt(apron(36, 4))
run(0.2)
eq(flying(), false, "1: nothing is flying yet (the gate is still settling)")
eq(restButton.Visible, true, "1: the Rest button shows at home")
eq(restButton.Text, T.RestButton, "1: it reads Rest")
press()
run(0.1)
eq(restButton.Text, T.RestingButton, "1: pressed with a clear sky: resting at once")
eq(hum.Sit, true, "1: the character sits down")
eq(bus.Status.Value, T.Resting, "1: the chip says so, and that poachers still come")
eq(hudRoot.RaidChip.Visible, true, "1: the HUD shows the chip")
eq(hudRoot.RaidChip.Text.Text, T.Resting, "1: with the rest line")
local n, flame = campfireParts()
truthy(n >= 3, "1: a campfire appears (" .. n .. " parts)")
truthy(flame and (Vector3.new(flame.X, 0, flame.Z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude < 6, "1: beside the resting player")
truthy(flame and math.abs(flame.Y - (hrp.Position.Y - W.RootHeight)) < 2, "1: on the ground")
eq(dof and dof.Enabled, true, "1: the view softens (depth of field, at home only)")
local jar0, ess0 = st().cages[5].jar, st().essence
local rate5 = Economy.rate(Config, "dogman")
local launches0 = launches
run(60)
eq(launches, launches0, "1: a minute of rest with hazards made rapid launched none (the clock is frozen)")
eq(restButton.Text, T.RestingButton, "1: still resting after a minute")
local grown = st().cages[5].jar - jar0
near(grown, rate5 * 60, rate5 * 1.5, string.format("1: the Dogman's jar kept filling while resting (%.0f in 60 s at %d/s)", grown, rate5))
eq(st().essence, ess0, "1: and nothing else changed on the server (Essence untouched)")
eq(serverCalls, ownCalls, "1: resting fired no remote")
-- moving wakes you, and the critters come back
hum.MoveDirection = Vector3.new(1, 0, 0)
run(Config.Night.Rest.WakeGraceSeconds + 0.1)
eq(restButton.Text, T.RestButton, "1: moving woke me")
eq(hum.Sit, false, "1: standing again")
eq((campfireParts()), 0, "1: the campfire is gone")
eq(dof and dof.Enabled, false, "1: the view is sharp again")
walkAround(apron(36, 4))
local wokeAt = simTime
run(Hz.SettleSeconds + 4, function() return launches > launches0 end)
truthy(launches > launches0, string.format("1: hazards came back after waking (%.1f s)", simTime - wokeAt))

--============================================================ 2. not a panic button

-- 2a: pressed with a hazard inbound: queued; the hazard arrives anyway; the hit voids the request
run(10, function() return not inFlightNow end)
run(12, function() return inFlightNow end)
truthy(inFlightNow, "2a: a hazard is flying")
standAt(hrp.Position)
press()
run(0.1)
eq(restButton.Text, T.QueuedButton, "2a: pressed with a hazard inbound, rest is only queued")
eq(hum.Sit, false, "2a: not seated")
eq(flying(), true, "2a: the hazard was NOT removed")
local hits0 = hitCount
run(8, function() return hitCount > hits0 end)
eq(hitCount, hits0 + 1, "2a: it arrived and knocked the player who stayed put")
run(0.1)
eq(restButton.Text, T.RestButton, "2a: the hit voided the queued rest")
run(Hz.KnockSeconds + 0.2)

-- 2b: pressed with a hazard inbound, then stepping out of the red ring: the request survives the dodge
run(10, function() return not inFlightNow end)
run(12, function() return inFlightNow end)
standAt(hrp.Position)
press()
run(0.1)
eq(restButton.Text, T.QueuedButton, "2b: queued again")
run(6, function() return string.sub(bus.Status.Value, 1, 5) == "Move!" end)
run(0.4)
for _ = 1, 12 do
	hrp.CFrame = CFrame.new(hrp.Position + Vector3.new(Config.Raid.WalkSpeed / 30, 0, 0))
	hum.MoveDirection = Vector3.new(1, 0, 0)
	frame(1 / 30)
end
hum.MoveDirection = Vector3.new(0, 0, 0)
hits0 = hitCount
eq(restButton.Text, T.QueuedButton, "2b: stepping out of the ring keeps the request")
run(8, function() return restButton.Text == T.RestingButton end)
eq(hitCount, hits0, "2b: the dodge worked")
eq(restButton.Text, T.RestingButton, "2b: rest began once the sky was clear and I stood still")
eq(hum.Sit, true, "2b: seated")
local l0 = launches
run(20)
eq(launches, l0, "2b: and nothing launched while resting (rapid hazards)")
press()
run(0.1)
eq(restButton.Text, T.RestButton, "2b: pressing again ends rest")
eq(hum.Sit, false, "2b: standing")

--============================================================ 3. idle rest (the shipped interval)

rapid(false)
walkAround(apron(36, 4))
-- intervals rolled in rapid mode are spent on the last hazard or two; after them the next is minutes away
local quietFor = 0
run(60, function()
	quietFor = if inFlightNow then 0 else quietFor + 1 / 30
	return quietFor >= 10
end)
truthy(quietFor >= 10, "3: the sky went quiet at the shipped interval")
standAt(apron(36, 4))
run(Config.Night.Rest.IdleSeconds + 0.5)
eq(bus.Status.Value, T.Idle, "3: standing still " .. Config.Night.Rest.IdleSeconds .. " s: idle rest (the chip says critters leave you alone)")
eq(hum.Sit, false, "3: idle rest does not sit you down")
eq((campfireParts()), 0, "3: and lights no campfire")
eq(restButton.Text, T.RestingButton, "3: the button shows resting")
walkAround(apron(36, 4))
run(1)
eq(bus.Status.Value, "", "3: moving ends idle rest")

--============================================================ 4. a raid is never paused

rapid(true)
standAt(apron(W.Apron.Board.x, W.Apron.Board.z - 4))
run(0.2)
run(10, function() return not inFlightNow end)
press()
run(12, function() return restButton.Text == T.RestingButton end)
eq(restButton.Text, T.RestingButton, "4: resting by the Hunt Board")
fireServer("Hunt", plr, 1)
h:advance(0.05)
run(1 / 30)
truthy(Night.pocketSlot(Config, hrp.Position.X) ~= nil, "4: the raid started (in a camp)")
eq(restButton.Text, T.RestButton, "4: the teleport ended the rest on the first frame")
eq(hum.Sit, false, "4: not seated in the camp")
eq((campfireParts()), 0, "4: no campfire in the camp")
eq(dof and dof.Enabled, false, "4: no depth of field in the camp (DESIGN.md 13)")
run(0.3)
eq(restButton.Visible, false, "4: no Rest button while raiding")
bus.RestPresses.Value += 1 -- a press that reaches the night anyway (an old tap, a script)
run(1)
eq(restButton.Text, T.RestButton, "4: a press in a camp does not rest")
eq(hum.Sit, false, "4: still standing")
local timeLeft0 = st().raid and st().raid.timeLeft
run(5)
local timeLeft1 = st().raid and st().raid.timeLeft
truthy(timeLeft0 and timeLeft1 and timeLeft0 - timeLeft1 >= 4, string.format("4: the raid's clock kept running (%s -> %s)", tostring(timeLeft0), tostring(timeLeft1)))
fireServer("LeaveCamp", plr)
h:advance(0.05)
run(1)

--============================================================ 5. income is never protected: the poacher comes while you rest

rapid(false)
walkAround(apron(36, 4))
local warnAt = joinedAt + Config.Poacher.FirstAfterSeconds
run(math.max(0, warnAt - h.scheduler:now() - 25))
standAt(apron(36, 4))
run(10, function() return not inFlightNow end)
press()
run(12, function() return restButton.Text == T.RestingButton end)
eq(restButton.Text, T.RestingButton, "5: resting at home before the first poacher is due")
local sawWarning, restingAtWarning, sawPoacher, restingWithPoacher = false, false, false, false
local chipAtWarning = ""
local jarBefore = nil
local target = nil
run(90, function()
	local s = st()
	if s.poacher and s.poacher.warningLeft and not sawWarning then
		sawWarning = true
		restingAtWarning = restButton.Text == T.RestingButton
		run(0.2)
		chipAtWarning = hudRoot.RaidChip.Text.Text
		local fullest, best = nil, -1
		for col = 1, 9 do if s.cages[col].sp ~= "" and s.cages[col].jar > best then fullest, best = col, s.cages[col].jar end end
		target = fullest
	end
	if #h.workspace.Poachers:GetChildren() > 0 and not sawPoacher then
		sawPoacher = true
		restingWithPoacher = restButton.Text == T.RestingButton
		jarBefore = target and st().cages[target].jar
	end
	return sawPoacher and #h.workspace.Poachers:GetChildren() == 0
end)
truthy(sawWarning, "5: the poacher's warning came on the server's schedule")
truthy(restingAtWarning, "5: while I was resting")
truthy(string.find(chipAtWarning, "poacher", 1, true) ~= nil, "5: the chip shows the poacher, not the rest line ('" .. chipAtWarning .. "')")
truthy(sawPoacher, "5: the poacher walked into my yard")
truthy(restingWithPoacher, "5: while I was still resting")
local toastThief = false
for _, rec in remotes.Toast:sentTo(plr) do
	if string.find(tostring(rec.args[1]), "poacher grabbed", 1, true) then toastThief = true end
end
truthy(toastThief, "5: it took Essence from my jar (rest protects no income)")
if target and jarBefore then
	truthy(st().cages[target].jar < jarBefore, string.format("5: cage %d's jar dropped at the grab (%.0f before the visit, %.0f after)", target, jarBefore, st().cages[target].jar))
end

--============================================================ 6. leaks

eq(serverCalls, ownCalls, "6: the clients fired no remote of their own (" .. serverCalls .. " server events, " .. ownCalls .. " by this file)")
for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid rest: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid rest check failed", 0) end
