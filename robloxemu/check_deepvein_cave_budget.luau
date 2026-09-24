-- Deep Vein — the client budgets under stress: fast elevator rides between random depths, hazards every
-- few seconds, every frame measured.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_cave_budget.luau
--
-- check_deepvein_cave.luau measures each band and seam after the miner has settled there. Normal play
-- crosses a band at a time; the elevator does not. This drives 400 cycles of either a jump to a random
-- depth anywhere in a rebirth-24 shaft (layers 0-312) or 6 s of standing and swinging somewhere, with a
-- hazard every 6-7 s (Config.Hazards.IntervalMin/Max overridden IN MEMORY for this run only), and
-- asserts Config.Budget on EVERY frame: local parts, emitters, particles per second, lights, hazards at
-- once. It also checks nothing accumulates: after the run the folder holds no more than the parts budget,
-- and every wall decoration it ever built has been destroyed or is still within DecorLayers of the miner.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 800, 360 },
	touch = true,
})

local UID = 5656
do
	local Config = require("../deep-vein/src/shared/Config")
	local Mine = require("../deep-vein/src/shared/Mine")
	local w = Mine.world(Config, 24)
	local c = Mine.center(Config)
	local dug = {}
	for y = 1, w.maxLayer do
		dug[Mine.key(c, y, c)] = true
		dug[Mine.key(c + 1, y, c)] = true
	end
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	store:SetAsync("u_" .. UID, { data = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 8,
		rebirths = 24, depthLayer = w.maxLayer, bestLayer = w.maxLayer,
		openedBits = Mine.packOpened(Config, w, dug),
	} })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Mine = mod("Mine")
local Budget = Config.Budget
local S = Config.Mine.CellSize
Config.Hazards.IntervalMin = 6 -- in memory, this run only: hazards every 6-7 s of mining
Config.Hazards.IntervalMax = 7

local plr = h:join("Stress", UID)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(2)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
local shaft = nil
for _, f in h.workspace.Shafts:GetChildren() do
	if f:FindFirstChild("SellPad_" .. UID, true) then shaft = f end
end
local origin = shaft:FindFirstChild("DepthWall_" .. UID).Position

h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okCave, errCave = h:tryRun("client/Cave.client")
truthy(okCave, "Cave.client loads (" .. tostring(errCave) .. ")")
local folder = h.workspace:FindFirstChild("DeepVeinLocalCave")

local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local UIS = h.game:GetService("UserInputService")

local seed = 12345
local function rnd()
	seed = (1103515245 * seed + 12345) % 2147483648
	return seed / 2147483648
end

local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, hazards = 0 }
local over = {}
local seen = {} -- every instance ever seen in the folder
local decorSeen = {}
local function measure(cycle)
	local m = { parts = 0, emitters = 0, rate = 0, lights = 0, hazards = 0 }
	local kinds = {}
	for _, d in folder:GetDescendants() do
		seen[d] = true
		local cls = d.ClassName
		if cls == "Part" then
			m.parts += 1
			local k = string.match(d.Name, "^Hazard_(%a+)$")
			if k and not kinds[k] then
				kinds[k] = true
				m.hazards += 1 -- hazard MODELS at once (a crumbling ruin is two parts, one model)
			end
			if string.match(d.Name, "^Decor_") then decorSeen[d] = true end
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate
		elseif cls == "PointLight" and d.Enabled then
			m.lights += 1
		end
	end
	for k, v in m do
		if v > peak[k] then peak[k] = v end
	end
	local limits = { parts = Budget.MaxLocalParts, emitters = Budget.MaxEmitters, rate = Budget.MaxEmitterRate,
		lights = Budget.MaxLights, hazards = Budget.MaxHazards }
	for k, v in m do
		if v > limits[k] and over[k] == nil then over[k] = string.format("%s = %s at cycle %d", k, tostring(v), cycle) end
	end
end

local swingAcc = 0
local function frame(dt, cycle)
	swingAcc += dt
	if swingAcc >= 1 then
		swingAcc = 0
		UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
	end
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if hum.PlatformStand then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
	measure(cycle)
end

local c = Mine.center(Config)
local hazardsSeen = 0
local wasHazard = false
for cycle = 1, 400 do
	local y = math.floor(rnd() * 313)
	local lp = Mine.localPos(Config, c, math.max(y, 0), c)
	hrp.CFrame = CFrame.new(origin.X + lp.x, Mine.floorY(Config, y) + Config.Env.RootAboveFloor, origin.Z + lp.z)
	local stay = if rnd() < 0.5 then 0.2 else 6
	for _ = 1, math.floor(stay * 30 + 0.5) do
		frame(1 / 30, cycle)
		local hz = folder:FindFirstChild("HazardRingEdge") ~= nil
		if hz and not wasHazard then hazardsSeen += 1 end
		wasHazard = hz
	end
end

print(string.format("  400 cycles: %d hazards; peak parts %d, emitters %d, particles/s %.1f, lights %d, hazards at once %d",
	hazardsSeen, peak.parts, peak.emitters, peak.rate, peak.lights, peak.hazards))
truthy(hazardsSeen >= 40, "set-up: hazards kept coming during the stress run (" .. hazardsSeen .. ")")
for _, k in { "parts", "emitters", "rate", "lights", "hazards" } do
	eq(over[k], nil, "the " .. k .. " budget held on every frame")
end

-- nothing accumulates
local stillIn, destroyed = 0, 0
local range = Config.Env.DecorLayers
local layerNow = Mine.layerOfY(Config, hrp.Position.Y) -- the client's named layer (Strata.layerAt: the root's cell)
local wrongRange = 0
for d in decorSeen do
	if d.Parent == folder then
		stillIn += 1
		local y = -(d.Position.Y) / S + 0.5
		if math.abs(y - layerNow) > range + 1.5 then wrongRange += 1 end
	else
		destroyed += 1
	end
end
print(string.format("  wall decorations built over the run: %d; destroyed %d; in the folder now %d (all within %d layers)",
	stillIn + destroyed, destroyed, stillIn, range))
truthy(destroyed > 500, "set-up: the run built and threw away lots of wall decor (" .. destroyed .. ")")
eq(wrongRange, 0, "every decoration still in the folder is within DecorLayers of the miner")
local count = 0
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") then count += 1 end
end
truthy(count <= Budget.MaxLocalParts, "after the run the folder holds " .. count .. " parts (no pile-up)")
local unique = 0
for _ in seen do unique += 1 end
print("  unique instances ever parented under the folder: " .. unique)

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein cave budget: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein cave budget check failed", 0)
end
