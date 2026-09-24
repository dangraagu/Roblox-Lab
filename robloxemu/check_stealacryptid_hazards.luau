-- Steal a Cryptid - the night's HAZARDS, through the REAL server and the REAL client scripts.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_hazards.luau 2>&1
--
-- The scheduler, the zone and the gate are unit-tested (steal-a-cryptid/tests). This file checks what
-- the client DOES with them, frame by frame:
--   G  the gate, with hazards made rapid (Config.Night.Hazards.IntervalMin/Max 0.05, in memory only):
--      none before the tutorial is done; none in a camp, and a raid's teleport clears a stumble at once;
--      the first after coming home waits the settle time; none in build mode or with the Hunt panel
--      open (a hazard already flying finishes); a poacher warning removes one in flight; none near the
--      ground's edge;
--   H  a player who stays put is knocked (a stumble: PlatformStand, a horizontal push, a capped lift,
--      then back on their feet); one who steps out of the red ring after it turns red is not, in four
--      directions; the ring is drawn where they stood and exactly as wide as the hit rule; every lane
--      starts on screen; the HUD chip warns, then says to leave the red ring;
--      H7 a dodged hazard is still a near-hit (within NearMissStuds) but never flies THROUGH the avatar;
--      H8/H9 after arrival no hazard part is under the floor and the "!" marker is off; H10 repeats the
--      stay/dodge with the camera level and looking up, where lanes come DOWN at the player;
--   R  rarity at the shipped numbers: 20 minutes of walking at home, with near-hits counted; R2 20 minutes
--      of lair life (stand 12 s, walk 6 s) stepping out of the ring at every warning, R3 the same ignoring
--      every warning: the owner's "one near-hit per 2-3 minutes", and how often a non-reactor is knocked.
-- Headless limits: no physics (the knock is observed as what the client writes), nothing renders.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Night = require("../steal-a-cryptid/src/shared/Night")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-hazards", viewport = { 1280, 720 }, touch = false })

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
local W = Config.World
local DEFAULT_MIN, DEFAULT_MAX = Hz.IntervalMin, Hz.IntervalMax
-- The game's OWN Config (the module the client requires from the bundle), not this file's copy: rapid
-- hazards are set there, in memory, for the gate phases and restored for the rarity phase.
local GameHz = nil
local function rapid(on)
	GameHz.IntervalMin = if on then 0.05 else DEFAULT_MIN
	GameHz.IntervalMax = if on then 0.05 else DEFAULT_MAX
end

local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 8801
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "dogman", jar = 0 }
	-- rank 2 (a Rare): the moonrise band's bats and crows. ONE cryptid, so no poacher comes (MinCryptids 2).
	-- Tutorial 3: the first raid is still ahead; hazards must wait for it.
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 5000, savedAt = NOW, cagesUnlocked = 3, tutorial = 3, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
GameHz = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Night.Hazards
truthy(GameHz ~= Hz and GameHz.IntervalMin == Hz.IntervalMin, "the game's Config.Night.Hazards is the bundle's module, not this file's copy")
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

rapid(true) -- the client's first interval is rolled when it loads
local plr = h:join("Stumbler", ME)
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
local bus = plr.PlayerGui.CryptidHud:FindFirstChild("NightBus")
truthy(bus ~= nil, "the HUD built its NightBus")
local hudRoot = plr.PlayerGui.CryptidHud.Root
local remState = remotes:FindFirstChild("State")
local function st()
	local sent = remState:sentTo(plr)
	return sent[#sent].args[1]
end

--============================================================ frames and observation

local cam = h.workspace.CurrentCamera
local simTime = 0
local launches = {} -- { t, kind, camAngleH, camAngleV }
local activeKind = nil
local hits = {}
local maxAtOnce = 0
local statusLog = {} -- per launch: first danger text time, first "Move!" time, last danger time
local walker = nil -- { centre = Vector3, r, w, phase }

local function hazardKinds()
	local kinds, n = {}, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local k = string.match(d.Name, "^Hazard_(%a+)_")
			if k and not kinds[k] then kinds[k] = true; n += 1 end
		end
	end
	return kinds, n
end
local function part(name)
	for _, d in folder:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then return d end
	end
	return nil
end

local wasStand = false
local postArrival, underground, markerAfter, firstUnder = 0, 0, 0, nil
-- the camera: behind and above the root, looking down about 22 degrees (Roblox's usual follow camera).
-- H10 raises it to look level and up: lanes then come DOWN at the player instead of level.
local camOff, camAim = Vector3.new(0, 9, -22), Vector3.new(0, 0, 0)
local function frame(dt)
	-- the walker: a circle at 8 studs/s with its movement input held (so idle rest never starts)
	if walker then
		walker.phase += walker.w * dt
		local p = walker.centre + Vector3.new(math.cos(walker.phase) * walker.r, 0, math.sin(walker.phase) * walker.r)
		hrp.CFrame = CFrame.new(p)
		hum.MoveDirection = Vector3.new(-math.sin(walker.phase), 0, math.cos(walker.phase))
	end
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + camOff, p + camAim)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt

	local kinds, n = hazardKinds()
	maxAtOnce = math.max(maxAtOnce, n)
	local kindNow = next(kinds)
	if kindNow and activeKind == nil then
		-- a launch: where does it start, seen from the camera?
		local model = nil
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and string.find(d.Name, "^Hazard_" .. kindNow .. "_") then model = d; break end
		end
		local look = cam.CFrame.LookVector
		local to = (model.Position - cam.CFrame.Position).Unit
		local yawL, yawT = math.atan2(look.X, look.Z), math.atan2(to.X, to.Z)
		local dy = math.abs(((yawT - yawL + math.pi) % (2 * math.pi)) - math.pi)
		local dp = math.abs(math.asin(math.clamp(to.Y, -1, 1)) - math.asin(math.clamp(look.Y, -1, 1)))
		table.insert(launches, { t = simTime, kind = kindNow, h = math.deg(dy), v = math.deg(dp), startY = model.Position.Y, rootY = hrp.Position.Y })
		table.insert(statusLog, { first = nil, move = nil, last = nil })
	end
	activeKind = kindNow
	-- how close each hazard came: the nearest of its parts to the root, over its whole flight
	if activeKind and #launches > 0 then
		local l = launches[#launches]
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") and string.find(d.Name, "^Hazard_" .. activeKind .. "_") then
				l.closest = math.min(l.closest or math.huge, (d.Position - hrp.Position).Magnitude)
			end
		end
	end
	local s = bus.Status.Value
	if #statusLog > 0 and activeKind then
		local log = statusLog[#statusLog]
		if bus.StatusKind.Value == "danger" and s ~= "" then
			log.first = log.first or simTime
			log.last = simTime
			if string.sub(s, 1, 5) == "Move!" then log.move = log.move or simTime end
		end
	end
	-- after it arrives (its warning has run and gone), a hazard must not dive into the ground, and its
	-- warning marker must be off: nothing blinks "!" once the danger has passed
	if activeKind and #statusLog > 0 and statusLog[#statusLog].first and bus.StatusKind.Value ~= "danger" then
		postArrival += 1
		local floorTop = hrp.Position.Y - W.RootHeight
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") and string.find(d.Name, "^Hazard_") then
				local cf, sz = d.CFrame, d.Size
				local ey = math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
				if d.Position.Y - ey < floorTop - 0.05 then
					underground += 1
					firstUnder = firstUnder or string.format("%s bottom %.1f under the floor at %.1f", d.Name, d.Position.Y - ey, floorTop)
				end
				local bb = d:FindFirstChild("HazardMarker")
				if bb and bb.Enabled then markerAfter += 1 end
			end
		end
	end
	if hum.PlatformStand == true and not wasStand then
		local v = hrp.AssemblyLinearVelocity
		table.insert(hits, { t = simTime, v = v, launch = launches[#launches] })
	end
	wasStand = hum.PlatformStand == true
end
local function run(seconds, until_)
	local n = math.floor(seconds * 30 + 0.5)
	for _ = 1, n do
		frame(1 / 30)
		if until_ and until_() then return true end
	end
	return false
end
local function launchesSince(t)
	local n = 0
	for _, l in launches do if l.t > t then n += 1 end end
	return n
end
local function inFlight() return activeKind ~= nil end

-- my lair
run(1.5)
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
local lair = plot.Lair
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local function apron(x, z) return frameCF:PointToWorldSpace(Vector3.new(x, W.RootHeight, z)) end
local function walkAround(x, z, r)
	walker = { centre = apron(x, z), r = r or 8, w = 1, phase = 0 }
end
local function standAt(pos)
	walker = nil
	hrp.CFrame = CFrame.new(pos)
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

--============================================================ G: the gate (rapid hazards)

-- G1: the tutorial is not done (State.tutorial 3): nothing, however long
walkAround(36, 4)
run(30)
eq(st().tutorial, 3, "G1: the profile is mid-tutorial (3)")
eq(#launches, 0, "G1: no hazard before the tutorial is done (30 s, rapid hazards)")

-- a raid, left at once: the tutorial completes (endRaid), and in the camp nothing flies
standAt(apron(W.Apron.Board.x, W.Apron.Board.z - 4))
run(0.5)
fireServer("Hunt", plr, 1)
h:advance(0.05)
truthy(Night.pocketSlot(Config, hrp.Position.X) ~= nil, "G2: the server put me in a camp")
local before = #launches
run(20)
eq(#launches, before, "G2: no hazard in a camp (20 s, rapid hazards)")
fireServer("LeaveCamp", plr)
h:advance(0.05)
eq(st().tutorial, 4, "G2: leaving the first raid finished the tutorial")
local homeAt = simTime
walkAround(36, 4)
run(Hz.SettleSeconds + 4, function() return launchesSince(homeAt) > 0 end)
truthy(launchesSince(homeAt) > 0, "G3: hazards start once home and the tutorial is done")
local firstHome = nil
for _, l in launches do if l.t > homeAt then firstHome = firstHome or l.t end end
truthy(firstHome ~= nil and firstHome - homeAt >= Hz.SettleSeconds - 0.05,
	string.format("G3: the first one waited the settle time after coming home (%.2f s >= %.1f)", (firstHome or 0) - homeAt, Hz.SettleSeconds))

-- G4: build mode stops new launches; the hazard already flying finishes
run(12, inFlight)
truthy(inFlight(), "G4: a hazard is flying")
fireServer("BuildMode", plr, true)
run(0.2)
eq(st().buildMode, true, "G4: the server switched build mode on")
truthy(inFlight(), "G4: the hazard already flying was not removed by build mode (not a panic button)")
before = #launches
run(25)
eq(#launches, before, "G4: no launch in 25 s of build mode (rapid hazards)")
fireServer("BuildMode", plr, false)
run(1.5)

-- G5: the Hunt panel open (the board's real prompt): no launch; closing it settles, then they return
run(Hz.SettleSeconds + 8, inFlight)
run(10, function() return not inFlight() end)
standAt(apron(W.Apron.Board.x, W.Apron.Board.z - 4))
lair.HuntBoard.Hunt.Triggered:Fire(plr)
run(0.3)
truthy(hudRoot.HuntPanel.Visible, "G5: the board's prompt opened the HUD's Hunt panel")
walkAround(W.Apron.Board.x, W.Apron.Board.z - 4, 3) -- reading the board, shuffling about (never idle)
before = #launches
run(25)
eq(#launches, before, "G5: no launch in 25 s with the Hunt panel open")
hudRoot.HuntPanel.CloseRow.Go.Activated:Fire()
local closedAt = simTime
run(0.2)
eq(hudRoot.HuntPanel.Visible, false, "G5: the panel closed")
run(Hz.SettleSeconds + 4, function() return launchesSince(closedAt) > 0 end)
local firstAfter = nil
for _, l in launches do if l.t > closedAt then firstAfter = firstAfter or l.t end end
truthy(firstAfter ~= nil and firstAfter - closedAt >= Hz.SettleSeconds - 0.05, "G5: after the panel closed, the settle time first")

-- G6: a poacher warning removes a hazard in flight (the owner must be free to defend). The State is
-- the server's own last push with a warning added, as the server sends it at a warning.
run(12, inFlight)
truthy(inFlight(), "G6: a hazard is flying")
do
	local s = table.clone(st())
	s.poacher = { warningLeft = 10 }
	remState:FireClient(plr, s)
	run(1 / 30)
	eq(inFlight(), false, "G6: the poacher warning removed the hazard in flight at once")
	eq(part("HazardLane"), nil, "G6: and its lane")
	eq(bus.Status.Value, "", "G6: and the chip's warning")
end
run(2)

-- G7: near the ground's edge: nothing launches (a knock must never push anyone off the world)
do
	local ground = h.workspace.Road.Ground
	local edgeZ = ground.Position.Z + ground.Size.Z / 2
	walker = { centre = Vector3.new(plot.Floor.Position.X, W.RootHeight, edgeZ - 12), r = 3, w = 1, phase = 0 }
	run(1)
	run(12, function() return not inFlight() end)
	before = #launches
	run(25)
	eq(#launches, before, string.format("G7: no launch within %d studs of the ground's edge (12 studs from it for 25 s)", Hz.EdgeMarginStuds))
end

-- G8: a raid started while stumbling: the teleport clears the stumble at once, the hazard stays home
standAt(apron(W.Apron.Board.x, W.Apron.Board.z - 4))
local hitsBefore = #hits
run(Hz.SettleSeconds + 16, function() return #hits > hitsBefore end)
truthy(#hits > hitsBefore and hum.PlatformStand == true, "G8: standing still at the board, a hazard knocked me over")
run(4 / 30) -- mid-stumble
eq(hum.PlatformStand, true, "G8: still stumbling")
fireServer("Hunt", plr, 1)
h:advance(0.05)
run(1 / 30)
truthy(Night.pocketSlot(Config, hrp.Position.X) ~= nil, "G8: in a camp")
eq(hum.PlatformStand, false, "G8: the teleport into the camp cleared the stumble on the first frame")
near(hrp.AssemblyLinearVelocity.Magnitude, 0, 1e-6, "G8: and the push")
eq(inFlight(), false, "G8: no hazard followed into the camp")
before = #launches
run(15)
eq(#launches, before, "G8: none in the camp")
fireServer("LeaveCamp", plr)
h:advance(0.05)

--============================================================ H: hit and dodge (rapid hazards)

local hitRecords = {}
local ringChecks = 0
local ringOk = 0
local function oneHazard(dodgeDeg)
	-- stand still at the arrival marker; wait for a launch
	standAt(apron(36, 4))
	run(Hz.SettleSeconds + 12, inFlight)
	if not inFlight() then return nil end
	local stoodAt = hrp.Position
	local hitsAt = #hits
	local kind = activeKind
	-- wait for the lock (the chip says Move!)
	run(6, function() return string.sub(bus.Status.Value, 1, 5) == "Move!" end)
	local locked = string.sub(bus.Status.Value, 1, 5) == "Move!"
	local ring = part("HazardRing")
	if locked and ring then
		ringChecks += 1
		local k = Hz.Kinds[kind]
		local okPos = math.abs(ring.Position.X - stoodAt.X) < 0.05 and math.abs(ring.Position.Z - stoodAt.Z) < 0.05
		local okSize = math.abs(ring.Size.Y - 2 * (k.hitRadius + Hz.PlayerRadius)) < 1e-6
		local okRed = ring.Color.R > 0.9 and ring.Color.G < 0.3
		if okPos and okSize and okRed then ringOk += 1 else
			print(string.format("  ring: at (%.2f, %.2f) stood (%.2f, %.2f), %.2f wide want %.2f, colour %s", ring.Position.X, ring.Position.Z, stoodAt.X, stoodAt.Z, ring.Size.Y, 2 * (k.hitRadius + Hz.PlayerRadius), tostring(ring.Color)))
		end
	end
	if dodgeDeg then
		-- half a second to react, then a short step (0.4 s at walk speed) measured from the lane's direction
		run(0.5)
		local lane = part("HazardLane")
		local dir = if lane then lane.CFrame.LookVector else Vector3.new(0, 0, 1)
		local a = math.atan2(dir.X, dir.Z) + math.rad(dodgeDeg)
		local step = Vector3.new(math.sin(a), 0, math.cos(a))
		for _ = 1, 12 do
			hrp.CFrame = CFrame.new(hrp.Position + step * (Config.Raid.WalkSpeed / 30))
			hum.MoveDirection = step
			frame(1 / 30)
		end
		hum.MoveDirection = Vector3.new(0, 0, 0)
	end
	run(8, function() return not inFlight() end)
	local wasHit = #hits > hitsAt
	table.insert(hitRecords, { kind = kind, dodge = dodgeDeg, hit = wasHit, rec = hits[#hits], closest = launches[#launches].closest })
	-- stand up again before the next one
	run(Hz.KnockSeconds + 0.3)
	return wasHit
end

local stayHits = 0
for _ = 1, 3 do
	if oneHazard(nil) then stayHits += 1 end
end
eq(stayHits, 3, "H1: a player who stays put is knocked by 3 of 3 hazards")
for _, r in hitRecords do
	if r.hit and r.rec then
		local v = r.rec.v
		local hsp = math.sqrt(v.X * v.X + v.Z * v.Z)
		truthy(hsp >= 20, string.format("H1: the %s's push is horizontal and real (%.1f studs/s)", r.kind, hsp))
		truthy(v.Y >= 0 and v.Y <= Hz.KnockLift + 1e-6, string.format("H1: the lift is capped (%.1f <= %d): a stumble, never a launch", v.Y, Hz.KnockLift))
		-- (1e-6: simTime is a running sum of 1/30 steps, so a span of exactly 3.0 s less one frame can come out
		-- 1e-15 short of that bound: 86 % of 89-frame spans do once simTime is large; see EYECANDY.md section 13)
		truthy(r.rec.launch and r.rec.t - r.rec.launch.t >= Hz.MinTelegraphSeconds - 1 / 30 - 1e-6,
			string.format("H1: the hit came %.2f s after the launch (>= %.1f s of warning)", r.rec.t - (r.rec.launch and r.rec.launch.t or 0), Hz.MinTelegraphSeconds))
	end
end
eq(hum.PlatformStand, false, "H1: back on their feet after the stumble")
local dodgeHits = 0
for _, d in { 0, 90, 180, 270 } do
	if oneHazard(d) then dodgeHits += 1 end
end
eq(dodgeHits, 0, "H2: a player who steps out of the red ring after it turns red is never hit (0, 90, 180, 270 degrees from the lane)")
truthy(ringChecks >= 6, "H3: the ring was checked at the lock of " .. ringChecks .. " hazards")
eq(ringOk, ringChecks, "H3: every ring was drawn where the player stood, red, exactly as wide as the hit rule")

-- the chip's two lines and every lane's start
do
	local good, telegraphs = 0, {}
	for i = 2, #statusLog do
		local log = statusLog[i]
		if log.first and log.move and log.last then
			good += 1
			table.insert(telegraphs, log.last - log.first)
		end
	end
	truthy(good >= 6, "H4: the chip warned (incoming, then Move!) for " .. good .. " hazards")
	local minT = math.huge
	for _, t in telegraphs do minT = math.min(minT, t) end
	truthy(minT >= Hz.MinTelegraphSeconds - 1 / 30 - 1e-6, string.format("H4: every warning ran at least %.1f s (shortest %.2f)", Hz.MinTelegraphSeconds, minT))
	local worstH, worstV = 0, 0
	for _, l in launches do worstH = math.max(worstH, l.h); worstV = math.max(worstV, l.v) end
	truthy(worstH <= 43, string.format("H5: every lane started within 43 degrees of where the camera looks (a 4:3 screen's half width); worst %.1f", worstH))
	truthy(worstV <= 35, string.format("H5: and within 35 degrees vertically (worst %.1f)", worstV))
	local allowed = {}
	for _, k in N.Home[2].hazards do allowed[k] = true end
	local bad = 0
	for _, l in launches do if not allowed[l.kind] then bad += 1 end end
	eq(bad, 0, "H6: only the moonrise band's kinds flew (" .. table.concat(N.Home[2].hazards, ", ") .. ")")
end
eq(maxAtOnce, 1, "never two hazards at once")

--============================================================ H10: a camera looking level or up (lanes come down)

-- With the follow camera looking ~22 degrees down every lane starts level (Night.hazardPitch clamps the
-- window's top to the horizon). A player who looks level or up gets lanes that DESCEND onto them, the
-- case where a hazard could fly on into the ground after passing. Stay put for some, dodge others.
do
	local under0, post0 = underground, postArrival
	local descending = 0
	for i, view in { { Vector3.new(0, 1, -22), Vector3.new(0, 1, 0) }, { Vector3.new(0, 0, -22), Vector3.new(0, 6, 0) } } do
		camOff, camAim = view[1], view[2]
		for j = 1, 3 do
			local l0 = #launches
			local hit = oneHazard(if j == 2 then 90 else nil)
			if hit ~= nil and #launches > l0 then
				-- a descending lane: the hazard started above the root's height by more than a stud
				local l = launches[l0 + 1]
				if l and l.startY and l.startY > l.rootY + 1 then descending += 1 end
			end
		end
	end
	camOff, camAim = Vector3.new(0, 9, -22), Vector3.new(0, 0, 0)
	print(string.format("  H10: %d descending lanes (camera level or looking up); %d frames after arrival; %d parts under the floor",
		descending, postArrival - post0, underground - under0))
	truthy(descending >= 3, "H10: with the camera level or looking up, lanes come down at the player (" .. descending .. " of 6)")
end
eq(underground, 0, "H8: after it arrives a hazard never dives into the ground, whatever the camera (a flier swoops away, a meteorite ends at the ground)")
eq(markerAfter, 0, "H9: (again, with descending lanes) the marker is off after arrival")

--============================================================ R: rarity at the shipped numbers

rapid(false)
walkAround(36, 4)
run(10, function() return not inFlight() end)
local rStart = simTime
local rLaunch0 = #launches
local rHits0 = #hits
run(20 * 60)
local rl = {}
local nearHits, closestList = 0, {}
for i = rLaunch0 + 1, #launches do
	table.insert(rl, launches[i].t)
	local c = launches[i].closest or math.huge
	table.insert(closestList, string.format("%.1f", c))
	if c <= Hz.NearMissStuds then nearHits += 1 end
end
local gaps = {}
for i = 2, #rl do table.insert(gaps, rl[i] - rl[i - 1]) end
local lo, hi = math.huge, 0
for _, g in gaps do lo = math.min(lo, g); hi = math.max(hi, g) end
print(string.format("\n  R: 20 simulated minutes of walking at home: %d hazards (%.2f/min), gaps %.1f..%.1f s, %d knocks (a walker who keeps moving)",
	#rl, #rl / 20, lo, hi, #hits - rHits0))
print(string.format("  R: %d near-hits (a hazard passing within %d studs of the root) = one per %.1f min; closest approach per hazard: %s",
	nearHits, Hz.NearMissStuds, if nearHits > 0 then 20 / nearHits else math.huge, table.concat(closestList, ", ")))
do
	-- the H phase: a hazard a player stepped out of the ring from was still a close call (a near-hit)
	local dodged, dodgedNear, list = 0, 0, {}
	for _, r in hitRecords do
		if r.dodge ~= nil and not r.hit then
			dodged += 1
			table.insert(list, string.format("%.1f", r.closest or math.huge))
			if (r.closest or math.huge) <= Hz.NearMissStuds then dodgedNear += 1 end
		end
	end
	print(string.format("  H: closest approach of each dodged hazard: %s studs", table.concat(list, ", ")))
	truthy(dodged >= 6, "H7: " .. dodged .. " hazards dodged by stepping out of the ring (H2's four, H10's two)")
	eq(dodgedNear, dodged, string.format("H7: and every dodged one still passed within %d studs (a near-hit, not a non-event)", Hz.NearMissStuds))
	local through = 0
	for _, r in hitRecords do
		if r.dodge ~= nil and not r.hit and (r.closest or math.huge) < 2 then through += 1 end
	end
	eq(through, 0, "H7: but none flew THROUGH the avatar that dodged it (every part stayed 2+ studs from the root)")
end
print(string.format("  after arrival: %d frames observed, %d hazard parts under the floor%s, %d frames with the marker on",
	postArrival, underground, if firstUnder then " (first: " .. firstUnder .. ")" else "", markerAfter))
truthy(postArrival > 30, "H8: frames after a hazard's arrival were observed (" .. postArrival .. ")")
eq(underground, 0, "H8: after it arrives a hazard never dives into the ground (a flier swoops away, a meteorite ends at the ground)")
eq(markerAfter, 0, "H9: after it arrives its warning marker is off (nothing blinks '!' once the danger has passed)")
truthy(#rl >= 6 and #rl <= 11, "R: 6-11 hazards in 20 minutes (one per 2-3 minutes)")
truthy(#gaps >= 4 and lo >= Hz.IntervalMin - 0.5 and hi <= Hz.IntervalMax + 1.5,
	string.format("R: every gap between launches is IntervalMin..IntervalMax (%.1f..%.1f)", lo, hi))
eq(maxAtOnce, 1, "R: never two at once")

--============================================================ R2: a player who does what the HUD says

-- Lair life at the shipped interval: stand at an apron spot for 12 s (reading a pedestal, waiting on the
-- pad: never the 20 s that starts idle rest), walk 6 s to the next spot, repeat; and when the chip says
-- "Move!", step out of the red ring half a second later (0.4 s at walk speed, at right angles to the lane).
-- This is the owner's "about one near-hit per 2-3 minutes", measured through the real client. R3 is the
-- same lair life with every warning ignored: how often a player who never reacts is knocked over.
local function lairLife(react)
	local spots = { { 36, 4 }, { 26, 4 }, { 48, 4 }, { 62, 4 }, { 16, 4 }, { 6, 4 } }
	walker = nil
	run(10, function() return not inFlight() end)
	local l0, k0 = #launches, #hits
	local si, phase, tPhase = 1, "stand", 0
	local from, to = apron(spots[1][1], spots[1][2]), apron(spots[1][1], spots[1][2])
	hrp.CFrame = CFrame.new(from)
	local reactAt, reacted = nil, {}
	local stepLeft, stepDir = 0, Vector3.new(1, 0, 0)
	local t, dt = 0, 1 / 30
	while t < 20 * 60 do
		local nL = #launches
		if react and activeKind and string.sub(bus.Status.Value, 1, 5) == "Move!" and not reacted[nL] then
			reacted[nL] = true
			reactAt = t + 0.5
		end
		if reactAt and t >= reactAt then
			reactAt = nil
			local lane = part("HazardLane")
			local dir = if lane then lane.CFrame.LookVector else Vector3.new(0, 0, 1)
			local a = math.atan2(dir.X, dir.Z) + math.rad(90)
			stepDir = Vector3.new(math.sin(a), 0, math.cos(a))
			stepLeft = 12
		end
		if stepLeft > 0 then
			stepLeft -= 1
			hrp.CFrame = CFrame.new(hrp.Position + stepDir * (Config.Raid.WalkSpeed / 30))
			hum.MoveDirection = stepDir
			if stepLeft == 0 then
				hum.MoveDirection = Vector3.new(0, 0, 0)
				phase, tPhase = "stand", 0
			end
		elseif phase == "stand" then
			hum.MoveDirection = Vector3.new(0, 0, 0)
			tPhase += dt
			if tPhase >= 12 then
				si = si % #spots + 1
				from, to = hrp.Position, apron(spots[si][1], spots[si][2])
				phase, tPhase = "walk", 0
			end
		else
			tPhase += dt
			local f = math.min(1, tPhase / 6)
			local d = to - from
			hum.MoveDirection = if d.Magnitude > 0.01 then d.Unit else Vector3.new(0, 0, 0)
			hrp.CFrame = CFrame.new(from:Lerp(to, f))
			if f >= 1 then phase, tPhase = "stand", 0 end
		end
		frame(dt)
		t += dt
	end
	local n, near, through, list = 0, 0, 0, {}
	for i = l0 + 1, #launches do
		n += 1
		local c = launches[i].closest or math.huge
		table.insert(list, string.format("%.1f", c))
		if c <= Hz.NearMissStuds then near += 1 end
		if c < 2 then through += 1 end
	end
	return n, near, through, #hits - k0, table.concat(list, ", ")
end
do
	local n, near, through, knocks, list = lairLife(true)
	print(string.format("  R2: 20 simulated minutes of lair life, reacting to every warning: %d hazards (one per %.1f min), %d near-hits (one per %.1f min), %d knocks; closest approach per hazard: %s",
		n, 20 / math.max(1, n), near, 20 / math.max(1, near), knocks, list))
	truthy(n >= 6 and n <= 11, "R2: 6-11 hazards in 20 minutes of lair life (" .. n .. ")")
	eq(knocks, 0, "R2: a player who steps out of the ring at every warning is never knocked")
	eq(through, 0, "R2: and no hazard flies through them")
	-- (a hazard that locks while they are mid-walk passes 8-9 studs off: they out-walked the ring as well)
	truthy(near >= math.ceil(n * 0.6), string.format("R2: most hazards are near-hits for them: %d of %d within %d studs", near, n, Hz.NearMissStuds))
	run(Hz.KnockSeconds + 0.5)
	n, near, through, knocks, list = lairLife(false)
	print(string.format("  R3: the same 20 minutes ignoring every warning: %d hazards, %d knocks (one per %.1f min), %d near-hits; closest approach per hazard: %s",
		n, knocks, 20 / math.max(1, knocks), near, list))
	truthy(n >= 6 and n <= 11, "R3: 6-11 hazards in 20 minutes (" .. n .. ")")
	truthy(knocks >= 1 and knocks <= n, "R3: a player who ignores the warnings is knocked now and then (" .. knocks .. " of " .. n .. ")")
end

eq(serverCalls, ownCalls, "the clients fired no remote of their own (" .. serverCalls .. " server events, " .. ownCalls .. " by this file)")
for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid hazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid hazards check failed", 0) end
