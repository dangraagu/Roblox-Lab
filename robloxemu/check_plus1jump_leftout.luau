-- +1 Jump Every Step — deck clouds that are LEFT OUT near the tower stay out. Run: luau check_plus1jump_leftout.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review round 1, finding 4 follow-up. SkyArt keeps deck clouds off the climb by shrinking them, and leaves
-- a cloud out entirely (unparents it) when it would have to shrink below a quarter of the smallest cloud.
-- With the live Config.Env.SceneryClearance (40) and WorldSeed 20260905 no cloud needs leaving out, so
-- check_plus1jump_world never reaches that branch and a mutation that brought left-out clouds back when
-- the band is shown again survived the sweep. This file forces the branch with a much larger clearance
-- (in memory, this run only) and checks it through the real client: clouds are left out, none is within
-- the clearance of the climb, and leaving the band and coming back shows exactly the same clouds.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Progression = h:_require(RS:FindFirstChild("Progression"))
local Tower = Config.Tower
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001
Tower.StreamAhead = 48
local CLEARANCE = 160
Config.Env.SceneryClearance = CLEARANCE -- forces left-out clouds (the live value is checked in _world)

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local towerFolder = h.workspace:FindFirstChild("Tower")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local camPos, lookAt = nil, nil
local function run(seconds)
	for _ = 1, math.floor(seconds * 10 + 0.5) do
		cam.CFrame = CFrame.new(camPos, lookAt)
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
	end
end
local function clouds()
	local out = {}
	for _, c in folder:GetChildren() do
		if c.Name == "StormDeckPuff" and c:IsA("BasePart") then table.insert(out, c) end
	end
	return out
end
local function segDist(a, b, p)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local s = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * s - p).Magnitude
end

-- the climb near the storm deck, as the server built it
local path = {}
for t = 40, 44 do
	for i = 1, Tower.TilesPerTier do
		table.insert(path, towerFolder:FindFirstChild("P_" .. t .. "_" .. i).Position + Vector3.new(0, 3.5, 0))
	end
end
local function nearestToPath(p)
	local best = math.huge
	for k = 1, #path - 1 do
		best = math.min(best, segDist(path[k], path[k + 1], p))
	end
	return best
end

local POOL = 9 * 4 -- 3x3 cells x 4 clouds per cell (SkyArt stormDeck)
local root = towerFolder:FindFirstChild("P_42_4").Position + Vector3.new(0, 3.5, 0)
local nextRoot = towerFolder:FindFirstChild("P_42_5").Position + Vector3.new(0, 3.5, 0)
hrp.CFrame = CFrame.new(root)
camPos, lookAt = root + Vector3.new(0, -6, -14), nextRoot
run(3)
local first = clouds()
print(string.format("  at P_42_4 with clearance %d: %d of %d storm clouds shown", CLEARANCE, #first, POOL))
truthy(#first < POOL, "set-up: some clouds are left out entirely (" .. (POOL - #first) .. ")")
truthy(#first > 0, "set-up: and some are still shown")
local tooClose = 0
for _, c in first do
	if nearestToPath(c.Position) - c.Size.X / 2 < CLEARANCE - 0.5 then tooClose += 1 end
end
eq(tooClose, 0, "every shown cloud keeps the clearance off the climb")

-- down out of the storm band, then back
hrp.CFrame = CFrame.new(root.X, Progression.yAtProgress(20, Tower) + 3.5, root.Z)
run(6)
eq(#clouds(), 0, "set-up: below the storm band no storm cloud is shown")
hrp.CFrame = CFrame.new(root)
run(6)
local again = clouds()
eq(#again, #first, "back at P_42_4 exactly the same number of clouds is shown: left-out clouds stay out")
tooClose = 0
for _, c in again do
	if nearestToPath(c.Position) - c.Size.X / 2 < CLEARANCE - 0.5 then tooClose += 1 end
end
eq(tooClose, 0, "and none of the shown clouds is closer than the clearance")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump leftout: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump leftout check failed", 0)
end
