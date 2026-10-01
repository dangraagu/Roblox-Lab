-- StormGrow — hazards on flat ground: rare, telegraphed, one at a time, the red ring IS the hit zone.
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_hazards.luau 2>&1
--
-- Through the real Sky.client (Hazards.luau verbatim + HazardGlue), frame by frame. DESIGN.md §4 asks the
-- build to measure: every warning frame has the ring and the banner on screen at camera pitches -60..+20
-- (16:9 and 4:3); the hazard MODEL is on screen from launch where that is possible (boundary reported);
-- no drawn lane point below ground + 1; walkers out of the drawn ring in 8 directions are never hit and
-- players who stay are always hit; and the rarity.
--
-- Headless limits: no physics. Walking is moving the root part while MoveDirection is set; "hit" is read
-- from what the client does to the character on a hit (a knock velocity and PlatformStand).
-- Set by hand (this process only): the local player's `Harvested` attribute, to put the farm in a band
-- (the client only reads it); the probe's "force" hook, which makes the next hazard due NOW instead of
-- waiting up to 180 s, except in part H, which measures the real interval.

local Harness = require("./emu/harness")
local Aim = require("../stormgrow/tests/Aim")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-hazards", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Hazards = mod("Config"), mod("Hazards")
local Hz, bands = Config.Hazards, Config.Env.Bands
local GROUND = Config.Farm.GroundY

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Dodger", 5151)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	assert(h:tryRun(key))
end
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local sky = h.workspace:FindFirstChild("StormLocalSky")
local probe = sky:FindFirstChild("StormSkyProbe")
local hazardFolder = sky.ValleyArt.Hazard
local banner = plr.PlayerGui.StormHud.Root.HazardBanner

-- the root stands 3 studs over the ground, as a Roblox R15 root does
local home = Vector3.new(hrp.Position.X, GROUND + 3, hrp.Position.Z)
hrp.CFrame = CFrame.new(home)
local camPitch = -20
local camYaw = 0
local function placeCamera()
	local p = math.rad(camPitch)
	local look = Vector3.new(math.sin(camYaw) * math.cos(p), math.sin(p), math.cos(camYaw) * math.cos(p))
	cam.CFrame = CFrame.lookAt(hrp.Position - look * 14, hrp.Position)
end
local knocked = 0
local lowestDrawn = math.huge
local maxHazardParts = 0
local function frame(dt)
	placeCamera()
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local v = hrp.AssemblyLinearVelocity
	if v and v.Magnitude > 1 then
		knocked += 1
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	local n = 0
	for _, d in hazardFolder:GetChildren() do
		n += 1
		if string.match(d.Name, "^Hazard_") then
			lowestDrawn = math.min(lowestDrawn, d.Position.Y)
		end
	end
	maxHazardParts = math.max(maxHazardParts, n)
end
local function run(seconds, dt, each)
	for _ = 1, math.floor(seconds / dt + 0.5) do
		frame(dt)
		if each and each() == false then return end
	end
end
local function active() return probe:Invoke("plan") end
-- A player who stands still for 20 s rests (Rest.IdleSeconds) and then no hazard launches, by design. So
-- between trials the farmer takes a step (walking input for half a second), as a player working the farm does.
local function stir()
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6, 0.1)
	hum.MoveDirection = Vector3.new(0, 0, 0)
end
local function setBand(i)
	plr:SetAttribute("Harvested", bands[i].from + 1)
	run(1, 0.1)
	stir()
end
local function ring()
	return hazardFolder:FindFirstChild("HazardRing")
end

--============================================================ A. band 1 is hazard-free

setBand(1)
local spawned0 = probe:Invoke("counts").hazardSpawned
hum.MoveDirection = Vector3.new(1, 0, 0) -- working the farm, never idle
run(400, 0.25)
hum.MoveDirection = Vector3.new(0, 0, 0)
eq(probe:Invoke("counts").resting, false, "set-up: the farmer was playing, not resting")
eq(probe:Invoke("counts").hazardSpawned - spawned0, 0, "no hazard in 400 s of play in band 1 (the first minutes are for learning)")

--============================================================ B+C. the ring is the zone; stepping out dodges, staying is hit

local function nextHazard()
	-- A hazard the hazard clock launched on its own may still be in the air (rarely: the clock left over from part
	-- A can come due in the 1.6 s a trial spends changing band). Forcing then only QUEUES a launch for the moment it
	-- lands, the trial adopted that older plan aimed where the farmer stood a trial before, and every trial after it
	-- did the same: in ~2% of runs (2 of 96 before REVIEW-1, 2 of 96 after) no stayer was hit and some dodgers were.
	-- So: let it land first, then force.
	if active() ~= nil then
		local where = hrp.CFrame
		local waited = 0
		while active() ~= nil and waited < 10 do
			frame(1 / 30)
			waited += 1 / 30
		end
		run(1.2, 0.1) -- (a knock from it wears off)
		hrp.CFrame = where
	end
	probe:Invoke("force")
	run(0.2, 0.05)
	local plan = active()
	truthy(plan ~= nil, "set-up: a hazard launched")
	return plan
end

local dirs = {}
for i = 0, 7 do table.insert(dirs, i * math.pi / 4) end
local dodgeHits, stayHits, stays, warnFramesBad, ringMismatch = 0, 0, 0, 0, 0
local bandCycle = { 2, 3, 4, 5, 6, 7 }
local kindsSeen = {}
local nKinds = 0
-- 24 trials over bands 2-7, then (REVIEW-1: the mutation sweep's CONTROL went red once on "all five kinds", 4 of 5,
-- and a run of 40 once more: the kind is drawn at random among the band's two or three) more trials, each in a band
-- that has a kind not seen yet, until every kind has been seen, at most 30. They run the same assertions.
local trial, extra = 0, 0
local function bandWithMissingKind(): number
	local candidates = {}
	for i = 2, #bands do
		for _, k in bands[i].hazards or {} do
			if not kindsSeen[k] then table.insert(candidates, i) break end
		end
	end
	return candidates[(extra - 1) % #candidates + 1]
end
while trial < 24 or (nKinds < 5 and extra < 30) do
	trial += 1
	if trial > 24 then extra += 1 end
	setBand(if trial <= 24 then bandCycle[(trial - 1) % #bandCycle + 1] else bandWithMissingKind())
	hrp.CFrame = CFrame.new(home)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local plan = nextHazard()
	if plan == nil then continue end
	if not kindsSeen[plan.kind] then nKinds += 1 end
	kindsSeen[plan.kind] = true
	local k0 = knocked
	local stay = trial % 3 == 0
	local stepped = false
	while active() == plan do
		frame(1 / 30)
		local live = Hazards.threatLive(plan, Hz.PlayerRadius)
		local r = ring()
		if live and not plan.hit then
			-- every warning frame: the ring is up, the banner is up
			if r == nil or r.Transparency >= 1 or not banner.Visible then warnFramesBad += 1 end
			if r then
				local z = Hazards.zone(plan, Hz.PlayerRadius)
				local c = r.Position
				if math.abs(c.X - z.x) > 0.01 or math.abs(c.Z - z.z) > 0.01 or math.abs(r.Size.Y / 2 - z.radius) > 0.01 then
					ringMismatch += 1
				end
			end
		end
		if plan.locked and not stepped and not stay then
			-- step out of the drawn ring, in one of 8 directions, the way a player walks: input held
			stepped = true
			local z = Hazards.zone(plan, Hz.PlayerRadius)
			local a = dirs[(trial - 1) % 8 + 1]
			hum.MoveDirection = Vector3.new(math.cos(a), 0, math.sin(a))
			local target = Vector3.new(z.x + math.cos(a) * (z.radius + 1.2), home.Y, z.z + math.sin(a) * (z.radius + 1.2))
			for s = 1, 6 do
				hrp.CFrame = CFrame.new(hrp.Position:Lerp(target, s / 6))
				frame(1 / 30)
			end
			hum.MoveDirection = Vector3.new(0, 0, 0)
		end
	end
	if stay then
		stays += 1
		if knocked > k0 then stayHits += 1 end
	elseif knocked > k0 then
		dodgeHits += 1
	end
	run(1.2, 0.1) -- the knock wears off
end
eq(warnFramesBad, 0, "every warning frame shows the ring and the banner")
eq(ringMismatch, 0, "the ring is drawn exactly where and as big as Hazards.zone says (hitRadius + 1.5)")
eq(dodgeHits, 0, string.format("%d players who stepped out of the ring in 8 directions: never hit", trial - stays))
eq(stayHits, stays, "every player who stayed in the ring was hit (" .. stayHits .. "/" .. stays .. ")")
do
	local names = {}
	for k in kindsSeen do table.insert(names, k) end
	table.sort(names)
	print(string.format("  kinds exercised: %s (%d trials, %d of them extra)", table.concat(names, ", "), trial, extra))
	eq(#names, 5, "all five kinds were exercised")
end
truthy(lowestDrawn >= GROUND + 1 - 1e-6, string.format("no drawn hazard point below ground + 1 (lowest centre %.2f)", lowestDrawn))
truthy(maxHazardParts <= Config.Budget.MaxHazardParts, "hazard parts within budget (" .. maxHazardParts .. ")")
do
	-- one at a time: a model of one kind plus ring and lane
	truthy(maxHazardParts <= 5, "never two hazards at once (at most one model + ring + lane: " .. maxHazardParts .. " parts)")
end

--============================================================ D. a hit costs a little, never a run

do
	setBand(4)
	hrp.CFrame = CFrame.new(home)
	local coinsBefore = plr:GetAttribute("Coins")
	local plan = nextHazard()
	local k0 = knocked
	local maxLift, stood = 0, false
	while active() == plan do
		frame(1 / 30)
		local v = hrp.AssemblyLinearVelocity
		if v.Magnitude > 1 then maxLift = math.max(maxLift, v.Y) end
		if hum.PlatformStand then stood = true end
	end
	truthy(knocked > k0, "set-up: the player who stayed was hit")
	truthy(stood, "a hit knocks the farmer over (PlatformStand)")
	run(1.5, 0.1)
	eq(hum.PlatformStand, false, "and they are back up within KnockSeconds")
	eq(plr:GetAttribute("Coins"), coinsBefore, "a hit costs no coins (hazards are client-only and touch no server state)")
end

--============================================================ E. on screen at every pitch (16:9 and 4:3)

local function onScreen(camCF, p, aspect, margin)
	local rel = camCF:PointToObjectSpace(p)
	local depth = -rel.Z
	if depth <= 0 then return false end
	local tv = math.tan(math.rad(35 - margin))
	local th = math.tan(math.rad(math.deg(math.atan(math.tan(math.rad(35)) * aspect)) - margin))
	return math.abs(rel.X / depth) <= th and math.abs(rel.Y / depth) <= tv
end
local pitchRows = {}
local ringOff, bannerOff = 0, 0
for _, pitch in { -60, -40, -20, 0, 20 } do
	camPitch = pitch
	local launchOn, launches = { [16 / 9] = 0, [4 / 3] = 0 }, 0
	for trial = 1, 12 do
		setBand(2 + trial % 6)
		hrp.CFrame = CFrame.new(home)
		camYaw = trial * 0.7
		local plan = nextHazard()
		if plan then
			launches += 1
			local model = nil
			for _, d in hazardFolder:GetChildren() do
				if string.match(d.Name, "^Hazard_") then model = d end
			end
			for aspect in launchOn do
				if model and onScreen(cam.CFrame, model.Position, aspect, 2) then launchOn[aspect] += 1 end
			end
			-- walk out so the next trial starts clean; check the ring on every warning frame
			while active() == plan do
				frame(1 / 30)
				if Hazards.threatLive(plan, Hz.PlayerRadius) and not plan.hit then
					local r = ring()
					for _, aspect in { 16 / 9, 4 / 3 } do
						if r == nil or not onScreen(cam.CFrame, r.Position, aspect, 2) then ringOff += 1 end
					end
					if not banner.Visible then bannerOff += 1 end
				end
			end
			run(1.2, 0.1)
		end
	end
	table.insert(pitchRows, string.format("pitch %+3d: model on screen at launch %2d/%d (16:9), %2d/%d (4:3)",
		pitch, launchOn[16 / 9], launches, launchOn[4 / 3], launches))
end
for _, r in pitchRows do print("  " .. r) end
eq(ringOff, 0, "the ring is on screen on every warning frame, pitches -60..+20, 16:9 and 4:3")
eq(bannerOff, 0, "and so is the banner")
camPitch = -20

--============================================================ G. the ring is SEEN on whatever the farmer stands on

-- (REVIEW-1, found while chasing a rare walk flake) The ring was drawn 0.05-0.25 studs above the GROUND: inside the
-- porch (top 0.4), the farm pad (top 1.0) and the soil plates (top 0.6), so wherever a farmer usually stands it was
-- hidden under the floor; only on bare grass could anyone see it. Here a hazard is launched at a farmer on each
-- surface, and points on the ring's top face are checked with the test's own oracle (stormgrow/tests/Aim.luau: the
-- first part drawn along the camera ray): the ring has to be the first thing seen there.
do
	local Farm = mod("Farm")
	local F = Config.Farm
	local aim = Aim.new(h, { touch = false })
	local slot = plr:GetAttribute("Slot")
	local function at(lx, lz)
		local x, z = Farm.toWorld(slot, lx, lz, F)
		return Vector3.new(x, 0, z)
	end
	local tx, tz = Farm.tileLocal(1, 5, F)
	local spots = {
		{ "the farm pad", at(0, F.PadLocalZ) },
		{ "the porch", at(-9, F.PorchDepth / 2) },
		{ "a soil plate", at(tx, tz) },
		{ "the bed between fields", at(F.FieldSize / 2 + F.PathWidth / 2, tz) },
		{ "the grass outside the farm", at(0, -12) },
	}
	local results = {}
	for _, spot in spots do
		local name, p = spot[1], spot[2]
		setBand(3)
		hrp.CFrame = CFrame.new(p.X, GROUND + 3.5, p.Z)
		local seen, total = 0, 0
		local plan = nextHazard()
		if plan then
			local _, facing = aim:standFor(Farm, F, slot, 1)
			for _ = 1, 8 do
				frame(1 / 30)
				local r = ring()
				if r and r.Transparency < 1 then
					aim:pose(hrp.Position, facing, 35, 14)
					local camPos = h.workspace.CurrentCamera.CFrame.Position
					-- (the Aim oracle looks past transient effects, the hazard's own art included; the ring is what
					-- this part measures, so it is put back in the list)
					local visible = Aim.within(aim:parts("visible"), hrp.Position, 60)
					table.insert(visible, r)
					local rad = r.Size.Y / 2
					local topY = r.Position.Y + r.Size.X / 2
					for i = 0, 7 do
						local a = i * math.pi / 4
						for _, f in { 0.45, 0.85 } do
							local pt = Vector3.new(r.Position.X + math.cos(a) * rad * f, topY, r.Position.Z + math.sin(a) * rad * f)
							total += 1
							if aim:firstVisible(camPos, pt, visible) == r then seen += 1 end
						end
					end
					break
				end
			end
			while active() == plan do frame(1 / 30) end
			run(1.2, 0.1)
		end
		table.insert(results, string.format("%s %d/%d", name, seen, total))
		truthy(total > 0 and seen / total >= 0.8, string.format("the ring is seen on %s (%d of %d points on its face)", name, seen, total))
	end
	print("  the ring seen from behind the farmer (pitch 35, 14 studs): " .. table.concat(results, " · "))
	-- the glue's map of what a farmer stands on matches the parts the server built: on a grid over farm 1 and the
	-- market, the top of the highest floor part (ground, square, pads, porch, bed, soil) under each point
	local HazardGlue = mod("HazardGlue")
	local floors = {}
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Ground" or d.Name == "MarketSquare" or d.Name == "MarketPad" or d.Name == "Porch"
			or d.Name == "Bed" or string.match(d.Name, "^Soil_") or string.match(d.Name, "^FarmPad_")) then
			table.insert(floors, d)
		end
	end
	local checked, wrong, example = 0, 0, ""
	local function topAt(x, z)
		local top = -math.huge
		for _, d in floors do
			local l = d.CFrame:PointToObjectSpace(Vector3.new(x, d.Position.Y, z))
			if math.abs(l.X) <= d.Size.X / 2 and math.abs(l.Z) <= d.Size.Z / 2 then
				top = math.max(top, d.Position.Y + d.Size.Y / 2)
			end
		end
		return top
	end
	for lx = -40, 40, 1.7 do
		for lz = -20, 62, 1.7 do
			local x, z = Farm.toWorld(1, lx, lz, F)
			-- skip points within 0.05 studs of a part's edge, where the two sides round apart
			local want, got = topAt(x, z), HazardGlue.surfaceY(x, z, F, Farm)
			checked += 1
			if math.abs(want - got) > 1e-6 then
				local near = math.abs(topAt(x + 0.06, z) - topAt(x - 0.06, z)) > 1e-6 or math.abs(topAt(x, z + 0.06) - topAt(x, z - 0.06)) > 1e-6
				if not near then
					wrong += 1
					if example == "" then example = string.format(" (e.g. local %.1f, %.1f: parts %.2f, glue %.2f)", lx, lz, want, got) end
				end
			end
		end
	end
	for x = -40, 40, 2.3 do
		for z = -40, 40, 2.3 do
			checked += 1
			if math.abs(topAt(x, z) - HazardGlue.surfaceY(x, z, F, Farm)) > 1e-6 then wrong += 1 end
		end
	end
	eq(wrong, 0, string.format("the glue's floor heights match the server's parts at %d points%s", checked, example))
end

--============================================================ H. rarity, on the real clock

do
	setBand(3)
	hrp.CFrame = CFrame.new(home)
	hum.MoveDirection = Vector3.new(1, 0, 0) -- working the farm: never idle, so the hazard clock runs
	local c0 = probe:Invoke("counts").hazardSpawned
	local seconds = 20 * 60
	local lastT, gaps = nil, {}
	local t = 0
	run(seconds, 0.25, function()
		t += 0.25
		local plan = active()
		if plan and plan.t < 0.3 then
			if lastT == nil or t - lastT > 5 then
				if lastT then table.insert(gaps, t - lastT) end
				lastT = t
			end
		end
		-- dodge every one (walk out when it locks) so play continues
		if plan and plan.locked and not plan.__walked then
			plan.__walked = true
			local z = Hazards.zone(plan, Hz.PlayerRadius)
			hrp.CFrame = CFrame.new(Vector3.new(z.x + z.radius + 2, home.Y, z.z))
		end
		return true
	end)
	local n = probe:Invoke("counts").hazardSpawned - c0
	local minGap, maxGap = math.huge, 0
	for _, g in gaps do minGap, maxGap = math.min(minGap, g), math.max(maxGap, g) end
	print(string.format("  20 min in Windy Orchard: %d hazards, one per %.0f s (gaps %.0f..%.0f s)", n, seconds / math.max(n, 1), minGap, maxGap))
	truthy(n >= 6 and n <= 10, "about one hazard per 2-3 minutes of play (" .. n .. " in 20 min)")
	truthy(minGap >= Hz.IntervalMin - 7, "never two within IntervalMin of play (plus the flight time)")
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
print(string.format("stormgrow hazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow hazards check failed", 0) end
