-- Disaster Rounds - rest and the Lookout strays, through the real server and Sky.client / Hud.client.
-- Run: luau check_disasterrounds_rest.luau 2>&1   (regenerate the bundle first)
--
-- docs/complete-game-standard.md §2: "the player can take a break somehow. A rest must never become an exploit: it
-- freezes the hazard clock and earns nothing it should not." DESIGN.md §5 and §4.2, measured here:
--   1. ☕ on the deck: a break; the next drop leaves you on the Lookout; moving brings you back;
--   2. ☕ on the island: held until the round is over (it never ends a round early), then a break;
--   3. a server move (a drop, a return) neither wakes a break nor resets the idle clock;
--   4. an AFK player is dropped into at most 2 rounds before idle rest takes them off the rosters;
--   5. strays: one at a time, only on the deck while awake, their red ring on the deck's top face, a knock that can
--      never lift a player over the 4-stud rail, and a clock that rest FREEZES (never resets): toggling rest does
--      not thin them out;
--   6. ☕ with a stray inbound is queued, and the stray still arrives.

local SEED = 515
local Datatypes = require("./emu/datatypes")
do
	local realNew = Datatypes.Random.new
	local n = SEED
	Datatypes.Random.new = function(seed)
		if seed == nil then
			n += 1
			return realNew(n * 7919)
		end
		return realNew(seed)
	end
end
local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local LC = Config.Lookout
h.game:GetService("RunService"):setIsServer(false)
local A = h:join("Rester", 901)
local char = h.Players:simulateSpawn(A, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
for _, c in { "client/Hud.client", "client/Sky.client", "client/World.client" } do
	local ok, err = h:tryRun(c)
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
local rf = h.workspace:FindFirstChild("Round")
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local hudGui = A.PlayerGui:FindFirstChild("DRHud")
local restBtn = hudGui:FindFirstChild("RestButton", true)
local sky = h.workspace:FindFirstChild("DRLocalSky")

local strays: { [any]: boolean } = {}
local strayCount = 0
local ringYs = {}
local DT = 1 / 20
local function frame()
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(-10, 6, 0), hrp.Position + Vector3.new(20, 0, 0)) -- facing the island
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	for _, d in sky:GetChildren() do
		if string.sub(d.Name, 1, 6) == "Stray_" and not strays[d] then
			strays[d] = true
			strayCount += 1
		end
		if d.Name == "StrayRing" then table.insert(ringYs, d.Position.Y) end
	end
end
local function run(seconds: number) for _ = 1, math.floor(seconds / DT + 0.5) do frame() end end
local function untilPhase(phase: string, limit: number)
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / DT do frame() n += 1 end
end
local function press() restBtn.Activated:Fire() frame() end
local function walk(on: boolean) hum.MoveDirection = if on then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 0) end

--======================================================================= 1. a break on the deck

untilPhase("intermission", 5)
run(1)
press()
run(0.5)
eq(A:GetAttribute("Resting"), true, "☕ on the deck: the server knows Ava is on a break")
eq(hudGui:GetAttribute("RestState"), "resting", "the HUD says so")
local phaseText = hudGui:FindFirstChild("PhaseText", true)
truthy(string.find(phaseText.Text, "break", 1, true) ~= nil, "\"" .. phaseText.Text .. "\"")
untilPhase("drop", 30)
eq(A:GetAttribute("InRound"), "", "the drop leaves a resting player on the Lookout")
untilPhase("intermission", 100)
walk(true)
run(1)
walk(false)
eq(A:GetAttribute("Resting"), false, "moving wakes the break")
untilPhase("drop", 30)
eq(A:GetAttribute("InRound"), "counted", "and the next drop takes her again")

--======================================================================= 2. ☕ on the island waits for the round to end

untilPhase("disaster", 10)
run(1)
press()
run(0.5)
eq(hudGui:GetAttribute("RestState"), "after", "☕ on the island: \"break after this round\"")
eq(A:GetAttribute("Resting"), false, "the server is not told yet: the round goes on")
eq(A:GetAttribute("InRound"), "counted", "and she is still in it")
-- she stays until she is swept out (she stands still) or the round ends; then the break starts on the deck
untilPhase("intermission", 100)
run(1.5)
eq(A:GetAttribute("Resting"), true, "back on the deck, the break starts")
untilPhase("drop", 30)
eq(A:GetAttribute("InRound"), "", "and the next round goes on without her")

--======================================================================= 3. server moves never wake a break

do
	-- a server move while resting: the MoveSeq bump and a teleport across the deck
	local seq = A:GetAttribute("MoveSeq") or 0
	A:SetAttribute("MoveSeq", seq + 1)
	hrp.CFrame = CFrame.new(-68, LC.FloorY + 3, 9)
	run(0.5)
	eq(A:GetAttribute("Resting"), true, "a server move (MoveSeq bumped, root teleported) does not wake the break")
	press() -- end the break by hand
	run(0.5)
	eq(A:GetAttribute("Resting"), false, "tapping ☕ again ends it")
end

--======================================================================= 4. an AFK player: at most 2 rounds

do
	walk(false)
	local survived0 = A:GetAttribute("Survived")
	local drops, lastRound = 0, nil
	local t0 = h.scheduler:now()
	while A:GetAttribute("Resting") ~= true and h.scheduler:now() - t0 < 400 do
		frame()
		local rid = rf:GetAttribute("RoundId")
		if A:GetAttribute("InRound") == "counted" and rid ~= lastRound then
			drops += 1
			lastRound = rid
		end
	end
	local took = h.scheduler:now() - t0
	eq(A:GetAttribute("Resting"), true, "a player who never moves goes on a break by themselves")
	truthy(took >= Config.Rest.IdleSeconds - 1 and took <= Config.Rest.IdleSeconds + 10,
		string.format("after %.0f s (IdleSeconds %d): the drops, returns, strays and knocks did not reset the AFK clock", took, Config.Rest.IdleSeconds))
	-- DESIGN.md §5 counted "at most 2 rounds" for 88 s cycles; alone on the island the round ends the moment the AFK
	-- player is swept out, so cycles are ~35 s here. What matters: an AFK player never survives one.
	truthy(drops <= 5, "and was dropped into " .. drops .. " round(s) on the way (alone: each one ends early)")
	eq(A:GetAttribute("Survived"), survived0, "surviving none of them: AFK farms nothing")
	print(string.format("  AFK: on a break after %.0f s of no input, dropped into %d round(s) on the way, survived none", took, drops))
	walk(true)
	run(1)
	walk(false)
end

--======================================================================= 5. strays: only on the deck, awake; one at a time

-- Keeping a player on the deck through the drops without touching their client: the server's own Resting flag is set
-- for the moment of each drop (what SetRest would do) and cleared after, so the client stays awake on the deck.
local function skipDrops()
	if rf:GetAttribute("Phase") == "intermission" and (rf:GetAttribute("PhaseEnds") or 0) - h.scheduler:now() < 0.3 then
		A:SetAttribute("Resting", true)
	elseif rf:GetAttribute("Phase") == "drop" and hudGui:GetAttribute("RestState") ~= "resting" then
		A:SetAttribute("Resting", false)
	end
end

do
	-- stay on the deck, awake, through several rounds: rest pressed just before each drop so Ava is never dropped,
	-- and woken right after: the stray clock must keep running while awake on the deck and nothing else
	local function stayOnDeck(seconds: number, resting: boolean)
		local t0 = h.scheduler:now()
		while h.scheduler:now() - t0 < seconds do
			if resting and A:GetAttribute("Resting") ~= true then press() end
			if not resting and A:GetAttribute("Resting") == true then press() end
			if not resting then skipDrops() end
			frame()
		end
	end
	strayCount = 0
	table.clear(strays)
	stayOnDeck(600, true)
	eq(strayCount, 0, "10 minutes on a break: no stray")
	strayCount = 0
	table.clear(strays)
	stayOnDeck(600, false)
	local awake10 = strayCount
	truthy(awake10 >= 6 and awake10 <= 11, string.format("10 minutes awake on the deck: %d strays (one per 60-90 s)", awake10))
	-- toggling rest every 4 s: the clock freezes, never resets, so awake time still brings them
	strayCount = 0
	table.clear(strays)
	local t0 = h.scheduler:now()
	local awake = 0
	while h.scheduler:now() - t0 < 1200 do
		local on = math.floor((h.scheduler:now() - t0) / 4) % 2 == 0
		if on and A:GetAttribute("Resting") ~= true and hudGui:GetAttribute("RestState") == "off" then press() end
		if not on and (A:GetAttribute("Resting") == true or hudGui:GetAttribute("RestState") == "queued") then press() end
		if hudGui:GetAttribute("RestState") ~= "resting" then skipDrops() end
		if hudGui:GetAttribute("RestState") ~= "resting" and A:GetAttribute("InRound") == "" then awake += DT end
		frame()
	end
	truthy(strayCount >= math.floor(awake / 90) and strayCount <= math.ceil(awake / 60) + 1,
		string.format("toggling rest every 4 s for 20 min (%.0f s awake): %d strays, one per 60-90 s of awake time: never thinned", awake, strayCount))
	truthy(#ringYs > 0, "the red stray ring was drawn")
	local off = 0
	for _, y in ringYs do
		if math.abs(y - (LC.FloorY + 0.08)) > 0.01 then off += 1 end
	end
	eq(off, 0, "always on the deck's top face (y = FloorY + 0.08)")
	print(string.format("  strays: 0 in 10 min resting, %d in 10 min awake, %d in 20 min toggling (%.0f s awake)", awake10, strayCount, awake))
end

--======================================================================= 6. a stray hit, and ☕ with a stray inbound

do
	if hudGui:GetAttribute("RestState") ~= "off" then press() end
	run(0.5)
	A:SetAttribute("Resting", false)
	walk(false)
	-- wait on the deck for the next stray, standing still in its ring
	local hitV = nil
	local queued = false
	local seen6, lastS = 0, nil
	local t0 = h.scheduler:now()
	while h.scheduler:now() - t0 < 200 and hitV == nil do
		skipDrops()
		walk(false)
		frame()
		local s = nil
		for _, d in sky:GetChildren() do
			if string.sub(d.Name, 1, 6) == "Stray_" then s = d end
		end
		if s and s ~= lastS then
			seen6 += 1
			lastS = s
		end
		if s and not queued then
			queued = true
			press()
			eq(hudGui:GetAttribute("RestState"), "queued", "☕ with a stray inbound is queued, not a panic button")
			truthy(hum.Sit ~= true, "the break has not started (Ava is not sitting)")
		end
		if hum.PlatformStand == true then
			hitV = hrp.AssemblyLinearVelocity
		end
	end
	truthy(hitV ~= nil, string.format("standing still in the ring, the stray knocks Ava (%d strays came, resting %s)", seen6, tostring(A:GetAttribute("Resting"))))
	if hitV then
		truthy(hitV.Y <= Config.Hazards.KnockLift + 1e-6, string.format("the knock lifts %.1f studs/s: %.2f studs, never over the %d-stud rail",
			hitV.Y, hitV.Y ^ 2 / (2 * 196.2), LC.RailHeight))
		truthy(math.sqrt(hitV.X ^ 2 + hitV.Z ^ 2) > 10, "and pushes her sideways (a stumble)")
	end
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("disasterrounds rest: %d passed, %d failed", passed, failed))
