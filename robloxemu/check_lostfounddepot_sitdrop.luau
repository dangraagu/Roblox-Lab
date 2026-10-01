-- Lost & Found Depot — the BREAK survives the sit's own drop. Run: luau check_lostfounddepot_sitdrop.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--
-- Found in real Studio on 2026-09-27 in +1 Jump (commit ad62955), and by the third review of this game
-- (2026-09-30) in Wings.client, which had the same rule. A Humanoid sat down without a seat drops onto the
-- floor: for about 0.3 s its root falls (vy -3 .. -26 studs/s), bounces (+9) and settles to 0, and
-- FloorMaterial reads Air the whole time it is seated. Wings.client counted a seated player as supported only
-- while |vy| < 2, and Rest ends a rest the moment the player is not supported, so TAKE A BREAK sat the avatar
-- and stood it up on the first frame of the drop, and the panel flipped straight back. A break booked
-- mid-shift was seated for one frame when the shift ran out. The emulator has no physics, so no gate saw it.
-- This file replays +1 Jump's measured Studio trace through the real server, HUD and Wings.client.
--
-- Headless limits: no physics. The sit's drop is replayed from the Studio trace, frame by frame; the check
-- sets FloorMaterial = Air while seated (measured in Studio) and the root's vertical velocity from the trace.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-sitdrop", viewport = { 1280, 720 }, touch = false })
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
-- the salt, pinned per call (CLAUDE.md traps): the same depot every run, consecutive shifts independent
local realRandom = Random
local unseeded = 0
Random = { new = function(seed)
	if seed == nil then unseeded += 1; return realRandom.new(4242 + unseeded * 7919) end
	return realRandom.new(seed)
end }

-- a returning player in the second wing (5 shifts done), so the booked break below ends a real shift
local UID = 7102
h.services.DataStoreService:GetDataStore("LostFoundDepot_v1"):SetAsync("u_" .. UID, {
	data = { v = 1, cash = 900, cartLevel = 3, shoesLevel = 3, shifts = 5, perfects = 2, backlog = 150,
		bestPerfectSeconds = 80, endingSeen = false, redeemed = {} },
})
assert(h:tryRun("server/Main.server"))
h:advance(1)
local plr = h:join("Sitter", UID)
h:advance(0.2)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okW, errW = h:tryRun("client/Wings.client")
truthy(okW, "Wings.client loads (" .. tostring(errW) .. ")")

local panel = plr.PlayerGui:FindFirstChild("DepotWings"):FindFirstChild("Root"):FindFirstChild("WingPanel")
local breakBtn = panel:FindFirstChild("BreakButton")
local wingNext = panel:FindFirstChild("WingNext")
local StateEv = h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("State")
local function last() local s = StateEv:sentTo(plr); return s[#s].args[1] end
StateEv:FireClient(plr, last()) -- the HUD's own join push, handed to the client as Roblox would
local cam = h.workspace.CurrentCamera
local bay = plr.RespawnLocation.Parent
local OX = bay:FindFirstChild("BayPad").Position.X

-- The Studio trace (Heartbeat, ~60 Hz) of the root's vertical velocity after Sit = true (+1 Jump, 2026-09-27).
local TRACE = { -3.27, -6.54, -9.81, -13.08, -16.35, -19.62, -22.89, -26.16, 8.91, 5.64, 2.37, -0.90, -4.17, -7.44, 3.46, 0.19 }
local drop = TRACE
local sitFrame = nil
local fallVy = nil -- a sustained fall while seated (scenario 4)
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	if hum.Sit == true then
		sitFrame = (sitFrame or 0) + 1
		hum.FloorMaterial = Enum.Material.Air -- a seated Humanoid reports Air (measured)
		hrp.AssemblyLinearVelocity = Vector3.new(0, fallVy or drop[sitFrame] or 0, 0)
	else
		sitFrame = nil
		hum.FloorMaterial = Enum.Material.Plastic
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds, dt)
	dt = dt or 1 / 60
	local seated = 0
	local n = math.max(1, math.floor(seconds / dt + 0.5))
	for _ = 1, n do
		frame(dt)
		if hum.Sit == true then seated += 1 end
	end
	return seated, n
end

hrp.CFrame = CFrame.new(OX, 3, 0)
run(2)
eq(last().shift.state, "ARMED", "set-up: between shifts, the tray armed")
eq(breakBtn.Text, "TAKE A BREAK", "set-up: the button offers a break")

--======================================================================= (1) TAKE A BREAK survives the drop

breakBtn.Activated:Fire()
local seated, frames = run(2)
print(string.format("  TAKE A BREAK + the Studio sit-drop trace: seated %d of %d frames, Sit now %s, button %q, panel %q",
	seated, frames, tostring(hum.Sit), breakBtn.Text, wingNext.Text))
eq(hum.Sit, true, "after TAKE A BREAK and the sit's measured drop, the avatar is still sitting")
eq(seated, frames, "seated on every frame of the drop and after it")
eq(breakBtn.Text, "BACK TO WORK", "the button offers BACK TO WORK")
truthy(string.find(wingNext.Text, "On break", 1, true) ~= nil, "the panel says On break (" .. wingNext.Text .. ")")
seated, frames = run(20, 1 / 30)
eq(seated, frames, "and it stays sitting while nothing moves (20 s)")

--======================================================================= (2) moving still wakes it

hum.MoveDirection = Vector3.new(1, 0, 0)
run(0.5)
eq(hum.Sit == true, false, "walk input wakes a seated break")
eq(breakBtn.Text, "TAKE A BREAK", "and the button offers a break again")
hum.MoveDirection = Vector3.new(0, 0, 0)
run(1)

--======================================================================= (3) a real fall while seated still wakes it

breakBtn.Activated:Fire()
run(1.5)
eq(hum.Sit, true, "set-up: on a break again after the drop")
fallVy = -40
local woke = nil
for f = 1, 90 do -- 1.5 s of a sustained fall, far longer than any sit's drop
	frame(1 / 60)
	if woke == nil and hum.Sit ~= true then woke = f end
end
fallVy = nil
truthy(woke ~= nil, "a sustained fall while seated still ends the break")
run(1)

--======================================================================= (4) a pickup during the drop still ends the break at once

breakBtn.Activated:Fire()
run(0.1) -- mid-drop: the settle window has not passed
eq(hum.Sit, true, "set-up: sitting, mid-drop")
hrp.CFrame = CFrame.new(OX, 3, 0)
bay:FindFirstChild("Slot_1"):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
run(0.1)
eq(last().shift.state, "RUNNING", "set-up: the pickup started the clock")
eq(hum.Sit == true, false, "the first pickup ends the break at once, even inside the sit's settle")
eq(breakBtn.Text, "BREAK AFTER SHIFT", "mid-shift the button books a break")

--======================================================================= (5) a booked break survives the drop

breakBtn.Activated:Fire()
run(0.2)
eq(breakBtn.Text, "BREAK BOOKED", "set-up: pressed mid-shift, the break is booked")
local satFrames, ranOut = 0, nil
local dt = 1 / 30
for f = 1, math.floor(345 / dt) do -- the 330 s clock runs out with nothing sorted
	frame(dt)
	if ranOut == nil and last().shift.state ~= "RUNNING" then ranOut = f end
	if ranOut and hum.Sit == true then satFrames += 1 end
end
truthy(ranOut ~= nil, "set-up: the shift ran out")
local after = math.floor(345 / dt) - (ranOut or 0)
print(string.format("  a break booked mid-shift: seated %d of the %d frames after the shift ran out; Sit now %s, button %q",
	satFrames, after, tostring(hum.Sit), breakBtn.Text))
eq(hum.Sit, true, "the booked break is still sitting after the shift ran out and the sit's drop")
truthy(satFrames >= after - 2, string.format("seated from the shift's end on (%d of %d frames)", satFrames, after))
eq(breakBtn.Text, "BACK TO WORK", "the booked break is a break: BACK TO WORK")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("lost-found-depot sitdrop: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lost-found-depot sitdrop check failed", 0)
end
