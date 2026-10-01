-- StormGrow — rest is a pause that is never an exploit (DESIGN.md §5).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_rest.luau 2>&1
--
-- Through the real server, HUD and Sky.client:
--   1. ☕ with a hazard inbound only QUEUES (no sit); the hazard still arrives and a player who stays is hit;
--   2. ☕ under a clear sky sits you down and freezes ONLY the hazard clock (frozen, never reset);
--   3. moving wakes you;
--   4. a server-accepted farm action wakes you (ActionSeq), because a tap does not move the character;
--   5. standing still for Config.Rest.IdleSeconds (90 s since REVIEW-1 B2) rests you (idle), and moving ends it;
--   6. growth and the weather do NOT pause: a crop planted before resting is ripe on time, and the server
--      clock and strike loop run on;
--   7. toggling rest does not thin hazards: the same stretch of PLAY time gives the same hazard clock.
-- Set by hand (this process only): `Harvested` (to put the farm in a hazard band; the client only reads it)
-- and the probe's "force" hook (a hazard due NOW), as in check_stormgrow_hazards.luau.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-rest", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- REVIEW-1: a tile is tapped by the client's pick (Farm.client + Pick.luau), which sends Tap(slot, key). Where this
-- check exercises the SERVER's rules it sends exactly that; check_stormgrow_aim and tests/walk.luau tap the screen.
local function tapTile(plr, hb)
	h.ReplicatedStorage.StormRemotes.Tap:simulateFireServer(plr, hb:GetAttribute("Farm"), hb:GetAttribute("Key"))
end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local bands = Config.Env.Bands

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Napper", 6262)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	assert(h:tryRun(key))
end
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local probe = h.workspace.StormLocalSky.StormSkyProbe
local restButton = plr.PlayerGui.StormHud.Root.Toggles.RestButton
local chip = plr.PlayerGui.StormHud.Root.TopBar.BandChip
local home = Vector3.new(hrp.Position.X, 3, hrp.Position.Z)
hrp.CFrame = CFrame.new(home)
local knocked = 0
local function frame(dt)
	cam.CFrame = CFrame.lookAt(hrp.Position + Vector3.new(0, 8, -14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local v = hrp.AssemblyLinearVelocity
	if v and v.Magnitude > 1 then
		knocked += 1
		hrp.AssemblyLinearVelocity = Vector3.zero
		-- a seated Humanoid is unseated by the knock; physics would drop it; nothing else to do headless
	end
end
local function run(seconds, dt) for _ = 1, math.floor(seconds / (dt or 0.1) + 0.5) do frame(dt or 0.1) end end
local function c() return probe:Invoke("counts") end
local function walk(seconds)
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(seconds)
	hum.MoveDirection = Vector3.new(0, 0, 0)
end
local function state() return plr:GetAttribute("RestState") end

plr:SetAttribute("Harvested", bands[3].from + 1)
walk(1)

--============================================================ 1. no rest with a hazard inbound

probe:Invoke("force")
run(0.3)
truthy(c().hazardActive, "set-up: a hazard is inbound")
restButton.Activated:Fire()
run(0.2)
eq(hum.Sit == true, false, "pressing ☕ with a hazard inbound does not sit you down")
eq(state(), "queued", "the request is queued (RestState)")
truthy(string.find(restButton.Text, "…", 1, true) ~= nil, "the button says so (" .. restButton.Text .. ")")
local k0 = knocked
while c().hazardActive do run(0.1) end
truthy(knocked > k0, "the hazard still arrived: the player who stayed put was hit (rest is no panic button)")
run(1.5)
walk(1) -- the queued request drops when you walk on under a clear sky
eq(state(), nil, "walking on drops the queued request")

--============================================================ 2. rest freezes only the hazard clock

run(1)
local clock0 = c().hazardClock
restButton.Activated:Fire()
run(0.2)
eq(hum.Sit, true, "☕ under a clear sky sits you down")
eq(state(), "resting", "RestState = resting")
run(0.4) -- the HUD refreshes its labels at 5 Hz
truthy(string.find(chip.Text, "Resting", 1, true) ~= nil, "the band chip says so (" .. chip.Text .. ")")
local server0 = h.workspace:GetAttribute("ServerNow")
run(30)
local clock1 = c().hazardClock
truthy(math.abs(clock1 - clock0) < 0.3, string.format("the hazard clock is frozen while resting (%.2f -> %.2f)", clock0, clock1))
truthy(h.workspace:GetAttribute("ServerNow") - server0 >= 29, "the server clock (growth, weather) runs on")
eq(c().hazardSpawned >= 0 and c().hazardActive, false, "no hazard launches during 30 s of rest")

--============================================================ 3. moving wakes you

walk(0.6)
eq(state(), nil, "moving wakes you")
eq(hum.Sit == true, false, "and stands you up")
local clock2 = c().hazardClock
truthy(clock2 >= clock1, "the hazard clock resumed from where it froze, never reset")

--============================================================ 4. a farm action wakes you

do
	local tile = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles.Tile_1_5
	run(0.5)
	restButton.Activated:Fire()
	run(0.2)
	eq(state(), "resting", "set-up: resting")
	local seq0 = plr:GetAttribute("ActionSeq")
	tapTile(plr, tile) -- plants a Radish: the server accepts it
	run(0.3)
	truthy(plr:GetAttribute("ActionSeq") > seq0, "set-up: the server accepted the tap (ActionSeq went up)")
	eq(state(), nil, "a farm action wakes you: no hazard-free farming while seated")
	eq(hum.Sit == true, false, "and stands you up")
end

--============================================================ 5. idle rest after IdleSeconds, ended by moving

local IDLE = Config.Rest.IdleSeconds
do
	walk(0.5)
	run(IDLE - 1)
	eq(state(), nil, string.format("%d s standing still: not resting yet", IDLE - 1))
	run(1.5)
	eq(state(), "idle", string.format("%d s standing still: idle rest (the AFK safety)", IDLE))
	truthy(string.find(chip.Text, "Idle", 1, true) ~= nil, "the chip says so (" .. chip.Text .. ")")
	walk(0.6)
	eq(state(), nil, "moving ends it")
end

--============================================================ 6. growth never pauses

do
	local tile = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles.Tile_1_5
	eq(tile:GetAttribute("Crop"), "radish", "set-up: the Radish planted in part 4")
	restButton.Activated:Fire()
	run(0.2)
	eq(state(), "resting", "set-up: resting")
	run(31)
	local sn = h.workspace:GetAttribute("ServerNow")
	truthy(sn >= tile:GetAttribute("PlantedAt") + 30, "30 s of rest later the Radish is ripe on the server clock")
	local coins = plr:GetAttribute("Coins")
	-- (the real clock's phase decides whether a storm, frost or rainbow ran while it ripened, so the sale is
	-- 5 x the multiplier of whatever marks it caught, exactly what a player standing still would get)
	local marks = tile:GetAttribute("Marks")
	local mult = 1
	for _, m in Config.Marks do
		if bit32.band(marks, m.bit) ~= 0 then mult *= m.mult end
	end
	tapTile(plr, tile)
	run(0.3)
	eq(plr:GetAttribute("Coins") - coins, 5 * mult, "and harvests for 5 x its marks (" .. mult .. "): rest earns exactly what standing still earns, no more")
	eq(state(), nil, "(the harvest woke the farmer)")
end

--============================================================ 7. toggling rest does not thin hazards

do
	-- 120 s of PLAY with rest toggled on for 7 s after every 7 s of play, vs 120 s of plain play: the hazard
	-- clock (seconds of play) advances the same amount either way
	walk(0.5)
	local a0 = c().hazardClock
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(120)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local plain = c().hazardClock - a0
	local b0 = c().hazardClock
	local played = 0
	for _ = 1, 17 do
		hum.MoveDirection = Vector3.new(1, 0, 0)
		run(7)
		played += 7
		hum.MoveDirection = Vector3.new(0, 0, 0)
		run(0.5) -- stop, then ☕ (a short stop is not "idle")
		restButton.Activated:Fire()
		run(7)
	end
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(1)
	played += 1
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local toggled = c().hazardClock - b0
	print(string.format("  hazard clock over %d s of play: %.1f s plain, %.1f s with rest toggled every 7 s (plus 8.5 s of stops)", played, plain, toggled))
	truthy(math.abs(toggled - (played + 17 * 0.5)) < 3, "toggling rest froze the clock only while resting: play time is still counted")
	truthy(toggled >= plain - 3, "so toggling does not thin hazards")
end

--============================================================ 8. tapping is activity: no idle rest while farming

do
	-- tests/walk.luau, 2026-10-01: a farmer standing on the porch and tapping crops every few seconds fell
	-- into IDLE rest, because only movement reset the idle timer. The hazard clock froze while they were busy
	-- farming. A server-accepted farm action counts as activity for the idle timer too. Taps every IDLE/2 s for
	-- 2 x IDLE: without that rule the idle timer passes IDLE between the second and third tap.
	walk(0.5)
	local tiles = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles
	local idleSeen = false
	local clockA = c().hazardClock
	local every = IDLE / 2
	for i = 1, 4 do
		for _ = 1, math.floor(every / 0.1 + 0.5) do
			frame(0.1)
			if state() == "idle" then idleSeen = true end
		end
		tapTile(plr, tiles["Tile_1_" .. (i % 9 + 1)])
		run(0.2)
		if state() == "idle" then idleSeen = true end
	end
	eq(idleSeen, false, string.format("a farmer tapping every %d s while standing still never goes idle", every))
	local total = 4 * (every + 0.2)
	truthy(c().hazardClock - clockA > total - 5, string.format("and the hazard clock ran the whole time (%.1f s of %.1f)", c().hazardClock - clockA, total))
end

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	if string.find(w, "frame error", 1, true) then failed += 1 end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow rest: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow rest check failed", 0) end
