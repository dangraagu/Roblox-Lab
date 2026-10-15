-- Scrapline Tycoon — the eye-candy glue: every band and its seam, the glide, budgets every frame, belt items, the
-- machines moving, the lift-off, the recycle's snap under the flash, ☕ Break, and a client that fires nothing and
-- writes nothing the server built.
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_yard.luau 2>&1
--
-- The tier is raised the way a player raises it: Buy("build", <next station>) over the real remote, paid from a
-- seeded profile, and the band changes when the new product actually SHIPS (the server's own tick), so every sky
-- change here comes from the server's State payload. Every frame the local yard folder is counted against
-- Config.Budget (parts, emitters, beams, trails, lights, weather). Nothing renders headless: "a band shows" means
-- its Parts are parented and opaque enough.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 4242
local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, cash = 1e12, stations = { shredder = { n = 1, L = 1, j = 0 } }, jamIn = 210, tier = 1,
	bolts = 0, boltsAt = 0, tutorial = 4 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Fx = mod("Fx")
local B = Config.Budget
local bands = Config.Env.Bands

--============================================================================ Fx.Presets.Junkyard = band 1
do
	local d, b1 = Fx.Presets.Junkyard, bands[1]
	local function rgb(c) return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) } end
	local mismatches = {}
	for group, props in { lighting = d.lighting, atmosphere = d.atmosphere, bloom = d.bloom, colorCorrection = d.colorCorrection, sunRays = d.sunRays } do
		for k, v in b1[group] do
			local pv = props[k]
			if type(v) == "table" then
				local c = pv and rgb(pv)
				if c == nil or c[1] ~= v[1] or c[2] ~= v[2] or c[3] ~= v[3] then table.insert(mismatches, group .. "." .. k) end
			elseif pv ~= v then
				table.insert(mismatches, group .. "." .. k .. " " .. tostring(pv) .. " vs " .. tostring(v))
			end
		end
	end
	eq(#mismatches, 0, "the server's starting light (Fx.Presets.Junkyard) equals band 1 on every field band 1 defines (" .. table.concat(mismatches, ", ") .. ")")
	eq(h.Lighting.ClockTime, 13.0, "the server set it first thing: dusty midday")
end

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Yardie", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Concrete
hum.MoveDirection = Vector3.new(0.01, 0, 1) -- steering input: never idles into a rest
assert(h:tryRun("client/Hud.client"))
local probe = nil
local okYard, errYard = h:tryRun("client/Yard.client")
truthy(okYard, "Yard.client loads (" .. tostring(errYard) .. ")")

local remotes = RS:FindFirstChild("ScraplineRemotes")
local Buy, Recycle = remotes.Buy, remotes.Recycle
local myCalls, serverEvents = 0, 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverEvents += 1 end)
	end
end
local folder = h.workspace:FindFirstChild("ScraplineLocalYard")
truthy(folder ~= nil, "the client builds its local yard folder")
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local Lighting = h.Lighting
local yardGui = plr.PlayerGui:FindFirstChild("ScraplineYard")
local card = yardGui.Root:FindFirstChild("BandCard")
probe = yardGui:FindFirstChild("YardProbe")
local pad = plr.RespawnLocation
local plot = pad.Parent

-- the budget, every frame
local worst = { parts = 0, emitters = 0, beams = 0, trails = 0, lights = 0, weather = 0, rate = 0, items = 0 }
local overBudget = {}
local function measure(where)
	local parts, emitters, beams, trails, lights, weatherOn, rate, items = 0, 0, 0, 0, 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		local c = d.ClassName
		if d:IsA("BasePart") then
			parts += 1
			if string.sub(d.Name, 1, 9) == "BeltItem_" then items += 1 end
		elseif c == "ParticleEmitter" and d.Enabled ~= false then
			emitters += 1
			if string.sub(d.Name, 1, 8) == "Weather_" then
				weatherOn += 1
				rate += d.Rate
			end
		elseif c == "Beam" and d.Enabled ~= false then beams += 1
		elseif c == "Trail" and d.Enabled ~= false then trails += 1
		elseif (c == "PointLight" or c == "SpotLight") and d.Enabled ~= false then lights += 1
		end
	end
	for _, d in char:GetDescendants() do
		if d.ClassName == "PointLight" and d.Enabled ~= false and (d.Brightness or 1) > 0 then lights += 1 end
	end
	local now = { parts = parts, emitters = emitters, beams = beams, trails = trails, lights = lights, weather = weatherOn, rate = rate, items = items }
	for k, v in now do worst[k] = math.max(worst[k], v) end
	local caps = { parts = B.MaxLocalParts, emitters = B.MaxEmitters, beams = B.MaxBeams, trails = B.MaxTrails, lights = B.MaxLights,
		weather = B.MaxWeatherEmitters, rate = B.MaxEmitterRate + 1e-6, items = B.BeltItemsOwn }
	for k, cap in caps do
		if now[k] > cap and #overBudget < 10 then table.insert(overBudget, string.format("%s: %s %s > %s", where, k, tostring(now[k]), tostring(cap))) end
	end
end

local clockSeen = {}
local liftSeen = false
local function frame(dt)
	-- the default camera follows the character, except while a script owns it (Scriptable: ☕ Break's drift)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, -18), hrp.Position)
	end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	table.insert(clockSeen, Lighting.ClockTime)
	if probe and probe:Invoke().liftoff then liftSeen = true end
end
local function run(seconds, where)
	for _ = 1, math.floor(seconds / 0.05) do
		frame(0.05)
		measure(where)
	end
end
local function stateOf()
	local sent = remotes.State:sentTo(plr)
	return sent[#sent].args[1]
end
local function shown(name)
	for _, d in folder:GetChildren() do
		if d.Name == name and d:IsA("BasePart") and d.Transparency < 0.95 then return true end
	end
	return false
end
local function critterKinds()
	local kinds = {}
	for _, d in folder:GetChildren() do
		local k = string.match(d.Name, "^Critter_(%a+)_")
		if k then kinds[k] = true end
	end
	return kinds
end
local PIECE_PART = { junkMounds = "JunkMound", tyreStacks = "TyreStack", carHulks = "CarHulk", brickChimneys = "BrickChimney",
	girders = "GirderPost", waterTower = "WaterTank", farGears = "FarGear", neonSigns = "NeonSign", holoBoards = "HoloBoard",
	searchlights = "Searchlight", gantry = "GantryTower", bigMoon = "Moon", sweepLights = "SweepLamp" }
local function checkBand(i, where)
	local b = bands[i]
	for _, id in b.pieces do
		truthy(shown(PIECE_PART[id]), b.id .. ": its scenery piece " .. id .. " is up " .. where)
	end
	-- critters, seen over the next 10 frames: a critter that leaves the sky is respawned on the same frame but drawn
	-- (at weight 0, invisible) only from the next, so a single-frame look missed the fast far rocket in about 3 runs in
	-- 8 (REVIEW-2: a flake of this check, not of the game)
	local kinds = critterKinds()
	for _ = 1, 10 do
		frame(0.05)
		for k in critterKinds() do kinds[k] = true end
	end
	for _, a in b.ambient do
		truthy(kinds[a.kind], b.id .. ": its critter " .. a.kind .. " is out " .. where)
	end
	local host = folder:FindFirstChild("WeatherHost")
	local pe = host and host:FindFirstChild("Weather_" .. b.weather.kind)
	truthy(pe ~= nil and pe.Enabled, b.id .. ": its weather (" .. b.weather.kind .. ") is falling " .. where)
	truthy(math.abs(Lighting.ClockTime - b.lighting.ClockTime) < 0.03,
		string.format("%s: ClockTime reaches the band's %.1f %s (%.3f)", b.id, b.lighting.ClockTime, where, Lighting.ClockTime))
end

run(3, "join")
eq(stateOf().tier, 1, "set-up: a returning Junkyard line (tier 1, scrap)")
eq(card.Visible, false, "a player who joins already in a band gets a quiet chip, not a title card")
checkBand(1, "at join (tier 1)")
do
	local items = 0
	for _, d in folder:GetChildren() do if string.sub(d.Name, 1, 9) == "BeltItem_" then items += 1 end end
	truthy(items > 0, "belt items ride the player's own line (" .. items .. " on the belt)")
	truthy(shown("Anim_Roller"), "the Shredder's rollers turn (a client part on top of the machine)")
end

--============================================================================ every band, entered by SHIPPING a new product
local IDS = Config.Stations.Order
local glideChecked = false
for i = 2, #bands do
	local b = bands[i]
	local before = Lighting.ClockTime
	local t0 = h.scheduler:now()
	Buy:simulateFireServer(plr, "build", IDS[i]) -- the station that makes band i's product
	myCalls += 1
	-- the band changes only once its product ships (a whole item sold at the dock)
	local entered = nil
	for _ = 1, 200 do
		frame(0.05)
		measure(b.id .. " entering")
		if stateOf().tier >= b.from then entered = h.scheduler:now() - t0 break end
	end
	truthy(entered ~= nil, b.id .. ": entered when the first " .. b.product .. " shipped (" .. string.format("%.2f", entered or -1) .. " s after building)")
	if not glideChecked then
		run(0.35, b.id .. " first frames")
		local early = Lighting.ClockTime - before
		local want = b.lighting.ClockTime - before
		print(string.format("  entering %s: ClockTime +%.3f in the first 0.35 s (target +%.1f)", b.name, early, want))
		truthy(early > 0 and early < 0.2 * want, "a new band GLIDES: in its first 0.35 s the sky moves under a fifth of the way")
		glideChecked = true
	end
	run(10, b.id)
	checkBand(i, "at tier " .. b.from)
	truthy(card.Visible or string.find(card.Text, string.upper(b.name), 1, true) ~= nil, b.id .. ": its title card showed: " .. card.Text)
	for _, id in bands[i - 1].pieces do
		if not table.find(b.pieces, id) then
			truthy(not shown(PIECE_PART[id]), b.id .. ": the previous band's " .. id .. " has gone")
		end
	end
	if i == #bands then
		-- the brag moment: the first Rocket lifts off from this plot
		truthy(liftSeen, "the first Rocket's lift-off played on the launch pad")
	end
end
do
	-- the lift-off was seen rising
	local items = {}
	for _, d in folder:GetChildren() do
		if string.sub(d.Name, 1, 9) == "BeltItem_" then items[string.sub(d.Name, 10)] = true end
	end
	truthy(items.Rocket or items.Robot, "rockets (or robots on their way) ride the belt now")
end
print(string.format("  worst frame over all bands and seams: %d parts (%d belt items), %d emitters, %d beams, %d trails, %d lights, %d weather at %.1f/s",
	worst.parts, worst.items, worst.emitters, worst.beams, worst.trails, worst.lights, worst.weather, worst.rate))
eq(#overBudget, 0, "every frame of every band and seam stays within Config.Budget (" .. table.concat(overBudget, "; ") .. ")")

--============================================================================ the Lighting write cap
do
	local p0 = probe:Invoke()
	run(1, "idle")
	local p1 = probe:Invoke()
	print(string.format("  Lighting writes in 1 s at rest at the Launch Site: %d", p1.lightingWrites - p0.lightingWrites))
	truthy(p1.lightingWrites - p0.lightingWrites <= 40 * Config.Env.LightingHz, "Lighting is written at most LightingHz times a second")
end

--============================================================================ the recycle: the sky snaps back to midday under the white flash
do
	-- follow the ★ until the line ships enough rockets (1500/s for the first bolt), paid from the seeded cash
	local buys = 0
	for _ = 1, 600 do
		local st = stateOf()
		if st.recycleReady then break end
		if st.star then
			Buy:simulateFireServer(plr, st.star.kind, st.star.id)
			myCalls += 1
			buys += 1
		end
		h:advance(0.13)
	end
	frame(0.05)
	truthy(stateOf().recycleReady, string.format("set-up: %d purchases later the line ships %.0f rockets/s, enough to recycle", buys, stateOf().rocketRate))
	run(2, "ready")
	truthy(math.abs(Lighting.ClockTime - 22.5) < 0.03, "set-up: the Launch Site's deep night (22.5)")
	table.clear(clockSeen)
	Recycle:simulateFireServer(plr)
	myCalls += 1
	local flashSeen = false
	for _ = 1, 20 do
		frame(0.05)
		measure("recycle")
		if plr.PlayerGui:FindFirstChild("FxFlash") then flashSeen = true end
	end
	eq(stateOf().bolts, 1, "the recycle went through: 1 Gold Bolt")
	eq(stateOf().tier, 0, "the yard is a junkyard again (tier 0)")
	truthy(flashSeen, "a white flash covers the screen")
	local between = 0
	for _, c in clockSeen do
		if c > 13.05 and c < 22.45 then between += 1 end
	end
	eq(between, 0, "the sky never sweeps backwards through the day: ClockTime jumps 22.5 -> 13.0 behind the flash")
	eq(Lighting.ClockTime, 13.0, "and it is midday at once")
	run(4, "after the recycle")
	checkBand(1, "after the recycle")
	local wall = plot.FactoryWall.Color
	eq(string.format("%d,%d,%d", math.round(wall.R * 255), math.round(wall.G * 255), math.round(wall.B * 255)), "230,190,60",
		"the factory is repainted: 1 bolt is Painted (safety yellow)")
end

--============================================================================ the client fires nothing and writes nothing the server built
do
	eq(serverEvents, myCalls, "every client -> server event in this run was one of this check's own calls: the yard and the HUD fired none")
	local snap = {}
	for _, d in h.workspace:FindFirstChild("Plots"):GetDescendants() do
		if d:IsA("BasePart") then
			snap[d] = { d.Color, d.Transparency, d.Size, d.CFrame, d.Parent, d.Material }
		end
	end
	for _ = 1, 300 do RunService.RenderStepped:Fire(1 / 30) end
	local changed = 0
	for d, s in snap do
		if d.Color ~= s[1] or d.Transparency ~= s[2] or d.Size ~= s[3] or d.CFrame ~= s[4] or d.Parent ~= s[5] or d.Material ~= s[6] then changed += 1 end
	end
	eq(changed, 0, "300 client frames change nothing on any server-built part")
	local strays = 0
	for _, d in h.workspace:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "Baseplate" then strays += 1 end
	end
	eq(strays, 0, "every client-built part lives in the local yard folder")
	local attrs = 0
	for _, d in folder:GetDescendants() do
		for _ in d:GetAttributes() do attrs += 1 end
	end
	eq(attrs, 0, "and carries no attributes")
end

--============================================================================ ☕ Break
do
	local btn = yardGui.Root:FindFirstChild("BreakSlot"):FindFirstChild("BreakButton")
	for _ = 1, 400 do
		if not probe:Invoke().hazardActive then break end
		frame(0.05)
	end
	eq(probe:Invoke().hazardActive, false, "set-up: nothing is falling")
	hum.MoveDirection = Vector3.new(0, 0, 0)
	btn.Activated:Fire()
	run(0.5, "break")
	eq(probe:Invoke().resting, true, "☕ Break starts a rest on the ground")
	eq(hum.Sit, true, "the player sits")
	eq(cam.CameraType, Enum.CameraType.Scriptable, "and the camera takes over to drift along the line")
	local chip = yardGui.Root:FindFirstChild("BandChip"):FindFirstChild("ChipText")
	truthy(string.find(chip.Text, "On break", 1, true) ~= nil and string.find(chip.Text, "line keeps running", 1, true) ~= nil, "the chip says so: " .. chip.Text)
	eq(btn.Text, "▶ Carry on", "the button offers the way back")
	local cash0 = stateOf().cash
	run(4, "break")
	truthy(stateOf().cash > cash0, "the line keeps earning during a break (the same as standing still)")
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6, "wake")
	eq(probe:Invoke().resting, false, "moving wakes the player")
	eq(cam.CameraType, Enum.CameraType.Custom, "and gives the camera back")
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
end

--============================================================================ ☕ Break lets go of the camera completely (REVIEW-1 B2)
-- The first version drifted the camera with an endlessly repeating tween (RepeatCount -1, reverses) and never
-- cancelled it: after the break it kept writing Camera.CFrame for the rest of the session. robloxemu applies a
-- tween's goal when its Time is up, so a tween left running shows up as a camera write after the break.
do
	local TS = h.game:GetService("TweenService")
	local btn = yardGui.Root:FindFirstChild("BreakSlot"):FindFirstChild("BreakButton")
	local function cameraTweensPlaying()
		local n = 0
		for _, tw in TS:getCreated() do
			if rawget(tw, "__target") == cam and string.find(tostring(tw.PlaybackState), "Playing", 1, true) then n += 1 end
		end
		return n
	end
	-- frames with nobody else touching the camera: any change is the game's own write
	local function untouched(seconds)
		local sentinel = CFrame.new(1, 2, 3)
		cam.CFrame = sentinel
		for _ = 1, math.floor(seconds / 0.05) do
			RunService.RenderStepped:Fire(0.05)
			h:advance(0.05)
		end
		return cam.CFrame == sentinel
	end
	for round = 1, 2 do
		for _ = 1, 400 do
			if not probe:Invoke().hazardActive then break end
			frame(0.05)
		end
		hum.MoveDirection = Vector3.new(0, 0, 0)
		btn.Activated:Fire()
		run(2, "break")
		eq(cam.CameraType, Enum.CameraType.Scriptable, "set-up " .. round .. ": on break, the camera drifts along the line")
		local c1 = cam.CFrame
		run(4, "break")
		truthy(cam.CFrame ~= c1, "round " .. round .. ": during the break the camera moves (it drifts, chute to dock)")
		if round == 1 then
			hum.MoveDirection = Vector3.new(1, 0, 0) -- walk away
		else
			btn.Activated:Fire() -- ▶ Carry on
		end
		run(0.6, "wake")
		eq(cam.CameraType, Enum.CameraType.Custom, "round " .. round .. ": the break ends and the camera is given back")
		eq(cameraTweensPlaying(), 0, "round " .. round .. ": no camera tween is left playing after the break")
		truthy(untouched(30), "round " .. round .. ": for 30 s after the break nothing in the game writes Camera.CFrame")
		hum.MoveDirection = Vector3.new(0.01, 0, 1)
		run(0.5, "after")
	end
	-- the break's own words: the line keeps running, and so does the jam clock (REVIEW-1 B6)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	btn.Activated:Fire()
	run(0.5, "break")
	local chip = yardGui.Root:FindFirstChild("BandChip"):FindFirstChild("ChipText")
	truthy(string.find(chip.Text, "jam", 1, true) ~= nil, "on break, the chip says machines can still jam: " .. chip.Text)
	btn.Activated:Fire()
	run(0.5, "wake")
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("scraplinetycoon yard: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon yard check failed", 0) end
