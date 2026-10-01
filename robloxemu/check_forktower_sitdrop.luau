-- Fork Tower — the ☕ Hvil button's sit survives the sit's own drop. Run: luau check_forktower_sitdrop.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- Found in real Studio for +1 Jump on 2026-09-27 (commit ad62955, robloxemu/check_plus1jump_sitdrop.luau):
-- a Humanoid sat down without a seat drops onto the floor, so for about 0.3 s its root falls (vy -3 .. -26
-- studs/s), bounces (+9) and settles to 0, and FloorMaterial reads Air the whole time it is seated. A
-- rest rule that counts "seated and |vy| >= 2" as falling wakes the rest on the first frame of the drop:
-- the avatar sits, 20 ms later it stands, and the pause button does nothing. Fork Tower's
-- Ambience.client had exactly that rule (second review, 2026-09-30: 1 passed, 3 failed on its probe).
-- check_forktower_env's rest block passes on the old rule only because the emulator has no physics.
--
-- This file replays +1 Jump's measured Studio trace frame by frame through Fork Tower's real server, HUD
-- and Ambience client, on a section platform (off the fork pad, where the button is meant to be used):
--   (1) the press sits the avatar and it stays sat through the drop, the chip says Hviler and the button
--       offers ▶ Klatre, and it stays that way for 20 s of standing still;
--   (2) walk input still wakes it (rest never lets a player climb);
--   (3) a sustained fall while seated still ends it (far longer than any sit's drop).
-- Headless limits: no physics. The drop is replayed from the Studio trace; the fall is written by hand.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower", viewport = { 1280, 720 }, touch = false })
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Sitter", 4343)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)
truthy(h:tryRun("client/Hud.client"), "Hud.client loads")
local okA, errA = h:tryRun("client/Ambience.client")
truthy(okA, "Ambience.client loads (" .. tostring(errA) .. ")")
local row = plr.PlayerGui:FindFirstChild("ForkHud"):FindFirstChild("Root"):FindFirstChild("AmbienceRow")
local chip, restBtn = row:FindFirstChild("BandChip", true), row:FindFirstChild("RestButton", true)
truthy(chip ~= nil and restBtn ~= nil, "set-up: the chip and the ☕ button exist")
local cam = h.workspace.CurrentCamera

-- The Studio trace (Heartbeat, ~60 Hz) of the root's vertical velocity after Sit = true on a pad.
local DROP = { -3.27, -6.54, -9.81, -13.08, -16.35, -19.62, -22.89, -26.16, 8.91, 5.64, 2.37, -0.90, -4.17, -7.44, 3.46, 0.19 }
local sitFrame = nil
local dt = 1 / 60
local function frame()
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, -24), hrp.Position)
	if hum.Sit == true then
		sitFrame = (sitFrame or 0) + 1
		hum.FloorMaterial = Enum.Material.Air -- a seated Humanoid reports Air (measured in Studio)
		hrp.AssemblyLinearVelocity = Vector3.new(0, DROP[sitFrame] or 0, 0)
	else
		sitFrame = nil
		hum.FloorMaterial = Enum.Material.Slate
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds)
	for _ = 1, math.floor(seconds / dt + 0.5) do frame() end
end

-- on a section platform: read floor 1, take the safe door (the server puts the player on platform 1)
local lane
for _, f in h.workspace:FindFirstChild("Towers"):GetChildren() do
	if f:GetAttribute("Owner") == plr.UserId then lane = f end
end
truthy(lane ~= nil, "set-up: the player has a lane")
local fork = lane:FindFirstChild("Fork_1")
local pad = fork:FindFirstChild("ForkPad_1")
local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
prompt.PromptButtonHoldBegan:Fire(plr)
run(1.2)
prompt.Triggered:Fire(plr)
run(0.3)
local m1 = fork:FindFirstChild("Door_1_1"):GetAttribute("Marked") == true
local marked = if m1 then 1 else 2
local trap = if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
fork:FindFirstChild("Door_1_" .. (3 - trap)):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
run(0.5)
local plat2 = lane:FindFirstChild("Section_1") and lane.Section_1:FindFirstChild("Plat_1_2")
truthy(plat2 ~= nil, "set-up: floor 1's section is built")
hrp.CFrame = CFrame.new(plat2.Position + Vector3.new(0, plat2.Size.Y / 2 + 3, 0))
run(2)
truthy(string.find(restBtn.Text, "Hvil", 1, true) ~= nil, "set-up: the button offers ☕ Hvil before the press (" .. restBtn.Text .. ")")

--======================================================================= (1) the sit's drop does not wake the rest

restBtn.Activated:Fire()
run(2)
eq(hum.Sit, true, "after pressing ☕ Hvil and the sit's measured drop, the avatar is still sitting")
truthy(string.find(chip.Text, "Hviler", 1, true) ~= nil, "the chip says Hviler (" .. chip.Text .. ")")
truthy(string.find(restBtn.Text, "Klatre", 1, true) ~= nil, "the button offers ▶ Klatre (" .. restBtn.Text .. ")")
run(20)
eq(hum.Sit, true, "and it stays sitting while nothing moves (20 s)")
truthy(string.find(chip.Text, "Hviler", 1, true) ~= nil, "and the chip still says Hviler after 20 s (" .. chip.Text .. ")")

--======================================================================= (2) moving still wakes it

hum.MoveDirection = Vector3.new(1, 0, 0)
run(0.5)
eq(hum.Sit == true, false, "walk input wakes a seated rest")
truthy(string.find(restBtn.Text, "Hvil", 1, true) ~= nil, "and the button offers ☕ Hvil again (" .. restBtn.Text .. ")")
hum.MoveDirection = Vector3.new(0, 0, 0)
run(1)

--======================================================================= (3) a real fall while seated still wakes it

restBtn.Activated:Fire()
run(1.5)
eq(hum.Sit, true, "set-up: resting again after the drop")
for _ = 1, 90 do -- 1.5 s of a sustained fall, far longer than any sit's drop
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, -24), hrp.Position)
	hum.FloorMaterial = Enum.Material.Air
	hrp.AssemblyLinearVelocity = Vector3.new(0, -40, 0)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
eq(hum.Sit == true, false, "a sustained fall while seated still ends the rest")

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("fork tower sitdrop: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower sitdrop check failed", 0)
end
