-- Steal a Cryptid - the night on a client that STARTS BEFORE THE ROAD HAS REPLICATED.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_lateroad.luau 2>&1
--
-- A LocalScript in StarterPlayerScripts can run before the server's workspace has reached the client
-- (and with StreamingEnabled, parts arrive by distance). The night reads public geometry from the road:
-- its Ground (where the far scenery is centred, and the edge rule that keeps a knock from pushing anyone
-- off the world) and its pine crowns (the owls' perches). The first build read them ONCE at start with
-- FindFirstChild: a client that started early centred the whole horizon on the world origin, never
-- perched an owl, and ran hazards with no edge rule at all. This file starts Night.client with the Road
-- unparented, then lets it "replicate" 12 s later, and checks:
--   1. while the Road is missing, no hazard launches (the edge rule cannot be judged: fail safe);
--   2. once it arrives, the far scenery is re-centred on the Ground, the owls perch on its pine crowns,
--      and hazards start (after the gate's settle time), all without a reload.
-- Headless limits: no physics, nothing renders; frames are RenderStepped fired by this file.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-lateroad", viewport = { 1280, 720 }, touch = false })

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

local W = Config.World
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 5505
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "dogman", jar = 0 }
	-- rank 2 (moonrise: owls on the road's pines), tutorial done, one cryptid (no poacher comes)
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 100, savedAt = NOW, cagesUnlocked = 3, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local GameHz = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Night.Hazards
GameHz.IntervalMin, GameHz.IntervalMax = 0.05, 0.05
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Early", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)

-- the Road has not reached this client yet
local road = h.workspace:FindFirstChild("Road")
local ground = road and road:FindFirstChild("Ground")
truthy(ground ~= nil, "the server built workspace.Road.Ground")
road.Parent = nil

assert(h:tryRun("client/Hud.client"))
local okNight, errNight = h:tryRun("client/Night.client")
truthy(okNight, "Night.client loads with no Road in the workspace (" .. tostring(errNight) .. ")")
if not okNight then error("Night.client did not load: " .. tostring(errNight), 0) end
local folder = h.workspace:FindFirstChild("CryptidNight")

local cam = h.workspace.CurrentCamera
local walker = { phase = 0 }
local launches, flyingNow = 0, false
local function flying()
	for _, d in folder:GetChildren() do
		if string.find(d.Name, "^Hazard_%a+_") then return true end
	end
	return false
end
local function frame(dt)
	-- a player walking a small circle at their arrival marker (never idle, so idle rest never starts)
	walker.phase += dt
	local c = walker.centre
	if c then
		hrp.CFrame = CFrame.new(c + Vector3.new(math.cos(walker.phase) * 6, 0, math.sin(walker.phase) * 6))
		hum.MoveDirection = Vector3.new(-math.sin(walker.phase), 0, math.cos(walker.phase))
	end
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local f = flying()
	if f and not flyingNow then launches += 1 end
	flyingNow = f
end
local function run(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do frame(1 / 30) end
end
local function parts(name)
	local out = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Name == name then table.insert(out, d) end
	end
	return out
end

walker.centre = hrp.Position
run(12)
eq(launches, 0, "1: no hazard launches while the Road (the edge rule's ground) is unknown (12 s, rapid hazards)")
truthy(#parts("FarGround") == 1, "1: the night still shows its sky and scenery meanwhile")

-- the Road arrives
road.Parent = h.workspace
run(3)
-- (since review 2026-09-24 finding 1 the far floor is four slabs framing a ravine round the Ground, not one
-- slab under it: the frame's hole is what must be centred on the road now)
local fgs = parts("FarGround")
eq(#fgs, 4, "2: the far forest floor is shown, as the four slabs that frame the ravine round the Ground")
if #fgs == 4 then
	local gx, gz = ground.Position.X, ground.Position.Z
	local xA, xB, zA, zB = nil, nil, nil, nil
	for _, s in fgs do
		local p, sz = s.Position, s.Size
		if p.Z + sz.Z / 2 <= gz then zA = p.Z + sz.Z / 2
		elseif p.Z - sz.Z / 2 >= gz then zB = p.Z - sz.Z / 2
		elseif p.X < gx then xA = p.X + sz.X / 2
		else xB = p.X - sz.X / 2 end
	end
	near(xA and xB and (xA + xB) / 2, gx, 0.5, "2: the far scenery is re-centred on the road's Ground (x)")
	near(zA and zB and (zA + zB) / 2, gz, 0.5, "2: (z)")
	near(xA and xB and (xB - xA), ground.Size.X + 2 * Config.Night.Ravine.Width, 0.5, "2: the hole is the Ground grown by the ravine (x)")
	near(zA and zB and (zB - zA), ground.Size.Z + 2 * Config.Night.Ravine.Width, 0.5, "2: (z)")
end
local owls = parts("Owl")
truthy(#owls >= 3, "2: owls perch on the road's pine crowns once they are known (" .. #owls .. ")")
local onCrown = 0
for _, o in owls do
	for _, c in road:GetChildren() do
		if string.sub(c.Name, 1, 10) == "PineCrown_" then
			local top = c.Position + Vector3.new(0, c.Size.Y / 2, 0)
			if (Vector3.new(o.Position.X, 0, o.Position.Z) - Vector3.new(top.X, 0, top.Z)).Magnitude < 0.5 and math.abs(o.Position.Y - top.Y) < 3 then
				onCrown += 1
				break
			end
		end
	end
end
eq(onCrown, #owls, "2: every owl sits on a pine crown")
local l0 = launches
run(Config.Night.Hazards.SettleSeconds + 6)
truthy(launches > l0, "2: hazards start once the Road is known (" .. (launches - l0) .. " launched)")

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid lateroad: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid lateroad check failed", 0) end
