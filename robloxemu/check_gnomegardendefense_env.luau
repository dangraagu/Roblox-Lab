-- Gnome Garden Defense: the seasons, the hazards and PAUSE, driven through the REAL client scripts.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_env.luau
--
-- The pure modules (EnvBands, Hazards, Rest) are unit-tested in gnome-garden-defense/tests. This file checks the
-- GLUE no unit test can see: that src/client/Garden.client.luau feeds the garden's Progress into the bands,
-- writes the blended light, builds and hides scenery within the mobile budget at every band AND every seam,
-- draws at most 40 bugs, runs hazards on the band's kinds with the red ring exactly on the hit zone, dazes the
-- gardener on a hit (and the HUD's gnome sheet says so), freezes the hazard clock while paused and in band 1
-- without resetting it, and that PAUSE reaches the server and any step resumes it.
--
-- Headless limits, stated: nothing renders and there is no physics. Frames are driven by firing
-- RunService.RenderStepped; the character moves only when this file moves it; the garden's Progress / Phase
-- attributes are set here the way the server replicates them. Whether it LOOKS right is on the Studio list.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and b ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-defense", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end

assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local bands = Config.Env.Bands
local Budget = Config.Budget
local remotes = RS:FindFirstChild("GardenRemotes")
local pauseCalls = {}
remotes.SetPaused.OnServerEvent:Connect(function(_, v) table.insert(pauseCalls, v) end)

local plr = h:join("Gardener", 5252)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okG, errG = h:tryRun("client/Garden.client")
truthy(okG, "Garden.client loads (" .. tostring(errG) .. ")")

local garden = nil
for _, g in h.workspace.Gardens:GetChildren() do
	if g:GetAttribute("Owner") == plr.UserId then garden = g end
end
assert(garden, "the player's garden")
local folder = h.workspace:FindFirstChild("GardenLocal")
truthy(folder ~= nil, "the client made its local folder")
local skyGui = plr.PlayerGui:FindFirstChild("GardenSky")
local root = skyGui and skyGui:FindFirstChild("Root")
local chip = root and root:FindFirstChild("BandChip")
local pauseBtn = root and root:FindFirstChild("PauseButton")
local warning = root and root:FindFirstChild("HazardWarning")
local card = root and root:FindFirstChild("BandCard")
truthy(chip and pauseBtn and warning and card, "chip, PAUSE, warning and title card exist")
local state = plr.PlayerGui:FindFirstChild("GardenClientState")

local cam = h.workspace.CurrentCamera
local Lighting = h.Lighting
local cards = {}
local lastCard = ""
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 18, 26), hrp.Position + Vector3.new(0, 0, -30))
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
end
local function run(seconds, each)
	local dt = 1 / 30
	for i = 1, math.floor(seconds / dt + 0.5) do
		frame(dt)
		if each and each(i) == false then return end
	end
end

local BUG_PARTS = { Body = true, Shell = true, Stripe = true, Head = true }
local function census()
	local c = { parts = 0, bugParts = 0, emitters = 0, weatherOn = 0, rate = 0, lights = 0, beams = 0, hazards = 0 }
	local hazardKinds = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			if BUG_PARTS[d.Name] then c.bugParts += 1 else c.parts += 1 end
			local k = string.match(tostring(d.Name), "^Hazard_(%a+)$")
			if k then hazardKinds[k] = true end
		elseif d.ClassName == "ParticleEmitter" and d.Enabled then
			-- an emitter that is switched off costs nothing; the weather kinds keep theirs, built once
			c.emitters += 1
			if string.match(tostring(d.Name), "^Weather_") then
				c.weatherOn += 1
				c.rate += d.Rate or 0
			end
		elseif d.ClassName == "PointLight" and d.Enabled then
			c.lights += 1
		elseif d.ClassName == "Beam" and d.Enabled then
			c.beams += 1
		end
	end
	for _ in hazardKinds do c.hazards += 1 end
	return c
end
local worst = { parts = 0, emitters = 0, weatherOn = 0, rate = 0, lights = 0, beams = 0, where = {} }
local function measure(where)
	local c = census()
	for k in { parts = true, emitters = true, weatherOn = true, rate = true, lights = true, beams = true } do
		if c[k] > worst[k] then worst[k] = c[k]; worst.where[k] = where end
	end
	return c
end

--============================================================================ 0. a new gardener's first look
do
	-- the three pads that see the most path pulse until the first gnome stands
	local rims = {}
	for _, d in garden.Bed:GetChildren() do
		local rim = d:GetAttribute("PadId") and d:FindFirstChild("Rim")
		if rim then rims[d:GetAttribute("PadId")] = { part = rim, min = 1 } end
	end
	run(1.5, function()
		for _, r in rims do r.min = math.min(r.min, r.part.Transparency) end
		return nil
	end)
	local pulsing = {}
	for id, r in rims do
		if r.min < 0.3 then table.insert(pulsing, id) end
	end
	eq(#pulsing, 3, "on a new bed exactly three pads pulse (" .. table.concat(pulsing, ",") .. ")")
	h.Players.LocalPlayer = plr
	remotes.Plant:FireServer(pulsing[1] or 1, "pebble")
	run(0.6)
	-- REVIEW-2: they stop PULSING once the first gnome stands, but the best free pads keep a steady glow (the
	-- glow is now all game; REVIEW-1 had them all settle)
	for _, r in rims do r.min = 1 end
	run(1.5, function()
		for _, r in rims do r.min = math.min(r.min, r.part.Transparency) end
		return nil
	end)
	local calm, steady, total = 0, 0, 0
	for _, r in rims do
		total += 1
		if math.abs(r.part.Transparency - 0.55) < 0.03 and r.min > 0.5 then calm += 1 end
		if math.abs(r.part.Transparency - 0.25) < 0.03 and r.min > 0.2 then steady += 1 end
	end
	eq(calm + steady, total, "and they stop pulsing once the first gnome is planted")
	eq(steady, 3, "three (the best free pads for the next gnome) keep a steady glow")
	-- a gnome that fires flashes its tool for a moment (no new parts)
	local gnome = garden.Bed.Gnomes:FindFirstChild("Gnome_" .. tostring(pulsing[1] or 1))
	local tool = gnome and gnome:FindFirstChild("Tool")
	local mat0 = tool and tool.Material
	remotes.GardenTick:FireClient(plr, { o = plr.UserId, a = garden:GetAttribute("Attempt"), w = 1, b = "", s = { pulsing[1] or 1 } })
	frame(1 / 30)
	eq(tool and tool.Material, Enum.Material.Neon, "a gnome that fired this tick lights its tool")
	run(0.3)
	eq(tool and tool.Material, mat0, "and it goes back to its look")
end

--============================================================================ 1. every band, every seam
garden:SetAttribute("Phase", "build") -- garden time runs in build phases; set as the server replicates it
local function setP(p) garden:SetAttribute("Progress", p) end
for i, b in bands do
	local nb = bands[i + 1]
	local mid = if nb then (b.from + (nb.from - (nb.fade or 0))) / 2 else b.from + 3
	setP(mid)
	run(4)
	local c = measure(b.id)
	near(Lighting.ClockTime, b.lighting.ClockTime, 0.25, b.id .. ": the light reaches the band's ClockTime")
	truthy(string.find(chip.Text, b.name, 1, true) ~= nil, b.id .. ": the chip names the band (" .. chip.Text .. ")")
	truthy(c.parts <= Budget.MaxLocalParts, string.format("%s: %d local parts <= %d", b.id, c.parts, Budget.MaxLocalParts))
	truthy(c.weatherOn >= 1, b.id .. ": its weather is falling (" .. c.weatherOn .. " on)") -- the dawn too (REVIEW-1)
	if nb and (nb.fade or 0) > 0 then
		setP(nb.from - nb.fade / 2)
		run(4)
		measure(b.id .. "|" .. nb.id)
	end
end
print(string.format("  budget, worst over every band and seam: %d parts (%s), %d emitters, %d weather on (%s), %.0f particles/s, %d lights, %d beams",
	worst.parts, tostring(worst.where.parts), worst.emitters, worst.weatherOn, tostring(worst.where.weatherOn), worst.rate, worst.lights, worst.beams))
do
	-- every band past the first is announced once, in order, as the sweep climbs into it
	local seenOrder = {}
	for _, t in cards do
		for i, b in bands do
			if i > 1 and string.find(t, string.upper(b.name), 1, true) then table.insert(seenOrder, i) end
		end
	end
	eq(#seenOrder, #bands - 1, "each of the " .. (#bands - 1) .. " later bands gets its title card once (" .. #seenOrder .. ")")
	local inOrder = true
	for k = 2, #seenOrder do
		if seenOrder[k] <= seenOrder[k - 1] then inOrder = false end
	end
	truthy(inOrder, "in the order the garden reaches them")
	local moonCard = false
	for _, t in cards do
		if string.find(t, "HARVEST MOON", 1, true) then moonCard = true end
	end
	truthy(moonCard, "reaching wave 30 announces the HARVEST MOON")
end
truthy(worst.parts <= Budget.MaxLocalParts, "local scenery parts never exceed " .. Budget.MaxLocalParts)
truthy(worst.emitters <= Budget.MaxEmitters, "emitters never exceed " .. Budget.MaxEmitters)
truthy(worst.weatherOn <= Budget.MaxWeatherEmitters, "weather emitters on at once never exceed " .. Budget.MaxWeatherEmitters)
truthy(worst.rate <= Budget.MaxEmitterRate + 1e-6, "weather particles never exceed " .. Budget.MaxEmitterRate .. "/s")
truthy(worst.lights <= Budget.MaxLights, "lights never exceed " .. Budget.MaxLights)
truthy(worst.beams <= Budget.MaxBeams, "beams never exceed " .. Budget.MaxBeams)

-- the weather cap is in CODE, not only in the config: ask for four kinds at once and at most two come on
do
	local last = bands[#bands]
	local saved = last.weather
	last.weather = { { kind = "snow", rate = 30 }, { kind = "stardust", rate = 25 }, { kind = "rain", rate = 40 }, { kind = "pollen", rate = 20 } }
	setP(last.from - 1.5) -- the seam into the last band: its four kinds plus the band below's
	run(3)
	local c = census()
	print(string.format("  four weather kinds asked for: %d on, %.0f particles/s", c.weatherOn, c.rate))
	truthy(c.weatherOn <= Budget.MaxWeatherEmitters, "asked for four kinds of weather, the art switches on at most " .. Budget.MaxWeatherEmitters .. " (" .. c.weatherOn .. ")")
	truthy(c.rate <= Budget.MaxEmitterRate + 1e-6, "and scales them to at most " .. Budget.MaxEmitterRate .. " particles/s (" .. c.rate .. ")")
	last.weather = saved
	setP(30)
	run(3)
end

-- a big jump back (a lost chapter): the light GLIDES, it does not cut
do
	setP(32)
	run(4)
	local before = Lighting.ClockTime
	setP(20)
	frame(1 / 30)
	local after1 = Lighting.ClockTime
	run(5)
	print(string.format("  a 32 -> 20 jump back: ClockTime %.2f -> %.2f after one frame", before, after1))
	truthy(math.abs(after1 - before) < 2, string.format("a lost chapter's jump back glides: %.2f -> %.2f in one frame", before, after1))
	near(Lighting.ClockTime, bands[EnvBands.indexOf(bands, "harvest")].lighting.ClockTime, 0.4, "and arrives at the season it went back to")
end

-- the night bands make the path glow instead of adding lights
do
	local tile = garden.Bed:FindFirstChild("Path_1")
	setP(31.5) -- frost: morning
	run(3)
	eq(tile.Material, Enum.Material.Pebble, "by day the path is gravel")
	setP(41) -- moonlit snow: midnight
	run(4)
	eq(tile.Material, Enum.Material.Neon, "on a night band the path glows")
	setP(15.5)
	run(4)
	eq(tile.Material, Enum.Material.Pebble, "and back to gravel by day")
end

--============================================================================ 2. the Harvest Moon is the brag
do
	local w = EnvBands.weights(bands, 30)
	near(w[EnvBands.indexOf(bands, "moon")], 1, 1e-9, "the moon band is FULL at progress 30 (the instant the Queen falls)")
	local w2 = EnvBands.weights(bands, 29)
	truthy((w2[EnvBands.indexOf(bands, "moon")] or 0) > 0, "and already blending in during her fight (progress 29)")
	remotes.Fanfare:FireClient(plr, { kind = "season", o = plr.UserId, chapter = 3, wave = 30, season = "Autumn", next = "Frost", boss = "Slug Queen", brag = true })
	frame(1 / 30)
	truthy(string.find(card.Text, "HARVEST MOON", 1, true) ~= nil, "the brag card reads HARVEST MOON")
	local sub = root:FindFirstChild("BandCardSub")
	truthy(sub and string.find(sub.Text, "Slug Queen", 1, true) ~= nil, "and says the Slug Queen falls")
end

--============================================================================ 3. bugs: at most 40 drawn, 3 parts each
do
	garden:SetAttribute("Phase", "wave")
	local Wire = mod("Wire")
	local list = {}
	for i = 1, 45 do
		table.insert(list, { id = 1000 + i, kind = if i % 9 == 0 then "queen" elseif i % 2 == 0 then "beetle" else "aphid", s = i * 4, hp = 1, maxHp = 1 })
	end
	remotes.GardenTick:FireClient(plr, { o = plr.UserId, a = garden:GetAttribute("Attempt"), w = 30, b = Wire.packBugs(Config, list) })
	frame(1 / 30)
	local c = census()
	print(string.format("  45 bugs sent: %d bug parts drawn", c.bugParts))
	truthy(c.bugParts <= Budget.MaxBugParts, "bug parts stay within " .. Budget.MaxBugParts .. " (" .. c.bugParts .. ")")
	truthy(c.bugParts >= 40 * 2, "and the 40 furthest bugs ARE drawn (" .. c.bugParts .. " parts)")
	-- paused mid-wave: no ticks come, and the bugs stay where they stood (the freeze reads as a freeze)
	garden:SetAttribute("Paused", true)
	run(3)
	eq(census().bugParts, c.bugParts, "3 s into a pause the bugs are still drawn, frozen")
	garden:SetAttribute("Paused", false)
	-- a tick of another garden is ignored
	remotes.GardenTick:FireClient(plr, { o = 999, a = 1, w = 1, b = Wire.packBugs(Config, list) })
	frame(1 / 30)
	eq(census().bugParts, c.bugParts, "a tick for someone else's garden draws nothing here")
	remotes.GardenTick:FireClient(plr, { o = plr.UserId, a = garden:GetAttribute("Attempt"), w = 30, b = "" })
	frame(1 / 30)
	eq(census().bugParts, 0, "an empty tick clears the path")
	garden:SetAttribute("Phase", "build")
end

--============================================================================ 4. hazards: rare, telegraphed, the ring IS the zone
local Hz = Config.Hazards
local function hazardOut(): BasePart?
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and string.match(tostring(d.Name), "^Hazard_%a+$") and d.Name ~= "HazardRing" then return d end
	end
	return nil
end
local function ringOut(): BasePart?
	return folder:FindFirstChild("HazardZone")
end
local function waitHazard(limit)
	local t = 0
	local got = nil
	run(limit, function()
		t += 1 / 30
		got = hazardOut()
		if got then return false end
		return nil
	end)
	return got, t
end

-- band 1 has no hazards, and its seconds do not count toward the next one
do
	setP(1.5)
	run(3)
	local h1 = waitHazard(220)
	eq(h1, nil, "220 s in band 1 (sprouts): no hazard (onboarding)")
end
-- blossom: acorns
local firstAt
do
	setP(5.5)
	run(2)
	-- the clock is never reset, and the band sweep above already ran it: the first wait is shorter
	local hz, t = waitHazard(Hz.IntervalMax + 5)
	truthy(hz ~= nil, string.format("a hazard comes within IntervalMax of garden time in a hazard band (%.1f s)", t))
	firstAt = h.scheduler:now() -- when the first one was SEEN (garden time = clock time here: a build phase, unpaused)
	truthy(hz and string.find(hz.Name, "acorn", 1, true) ~= nil, "blossom drops acorns (" .. tostring(hz and hz.Name) .. ")")
	-- the ring: centred where the gardener stands, radius hitRadius + PlayerRadius
	frame(1 / 30)
	local ring = ringOut()
	truthy(ring ~= nil and ring.Parent ~= nil, "a red ring marks where it can land")
	if ring then
		local want = 2 * (Hz.Kinds.acorn.hitRadius + Hz.PlayerRadius)
		near(ring.Size.Y, want, 1e-6, "the ring's diameter is exactly the hit zone's")
		local dx, dz = ring.Position.X - hrp.Position.X, ring.Position.Z - hrp.Position.Z
		near(math.sqrt(dx * dx + dz * dz), 0, 1e-6, "centred on the gardener who stands still")
	end
	truthy(warning.Visible and string.find(warning.Text, "ACORN", 1, true) ~= nil, "the warning names it (" .. warning.Text .. ")")
	-- standing still: hit, knocked down, dazed; the HUD's sheet says so. Counted from here: a hazard can already
	-- have fallen during the band sweep above (garden time ran in hazard bands; the clock is never reset), and an
	-- absolute count of 1 failed about one run in thirty
	local hits0 = (state and state:GetAttribute("Hits")) or 0
	local hitSeen = false
	run(5, function()
		if hum.PlatformStand == true then hitSeen = true end
		return nil
	end)
	truthy(hitSeen, "standing in the ring: the acorn knocks the gardener down")
	local dazed = state and state:GetAttribute("DazedUntil")
	truthy(type(dazed) == "number" and dazed > h.scheduler:now() - 5, "and dazes them")
	eq(((state and state:GetAttribute("Hits")) or 0) - hits0, 1, "one hit")
	eq(hazardOut(), nil, "and the hazard is gone after its pass")
end
-- the next one: step out of the ring after it locks, and it misses
do
	local hz = waitHazard(Hz.IntervalMax + 5)
	truthy(hz ~= nil, "a second hazard comes")
	-- seen to seen, on the clock (REVIEW-1: the old estimate added the first one's 3.8 s flight on top of the 5 s
	-- watched DURING it, and failed whenever the drawn interval was over ~146.7 s: about one run in fifteen)
	local spacing = h.scheduler:now() - firstAt
	print(string.format("  two consecutive hazards: %.1f s of garden time apart", spacing))
	truthy(spacing >= Hz.IntervalMin - 0.5 and spacing <= Hz.IntervalMax + 0.5,
		string.format("hazards are IntervalMin..IntervalMax apart: %.1f s of garden time", spacing))
	local hits0 = state:GetAttribute("Hits") or 0
	local plan = nil
	-- wait for the lock (the ring turns red), then step 4.5 studs: out of a 3.0-stud ring
	run(Hz.Kinds.acorn.telegraph - Hz.Kinds.acorn.commit + 0.2)
	hrp.CFrame = hrp.CFrame + Vector3.new(4.5, 0, 0)
	run(4)
	eq(state:GetAttribute("Hits") or 0, hits0, "stepping out of the ring after the lock dodges it")
	hrp.CFrame = hrp.CFrame - Vector3.new(4.5, 0, 0)
end
-- pause freezes the hazard clock (never resets it); never two at once
do
	run(2) -- the server polls the character every second: let it see the step back first
	-- PAUSE through the button: reaches the server, which freezes the garden
	pauseCalls = {}
	pauseBtn.Activated:Fire()
	run(0.5)
	eq(pauseCalls[#pauseCalls], true, "PAUSE asks the server to freeze the garden")
	eq(garden:GetAttribute("Paused"), true, "and the server says it is paused")
	local pausedOverlay = root:FindFirstChild("PausedOverlay")
	truthy(pausedOverlay and pausedOverlay.Visible, "the PAUSED overlay shows")
	local hz = waitHazard(200)
	eq(hz, nil, "200 s paused: no hazard (the clock is frozen)")
	-- a respawn while paused: the client's rest state starts over, the server's pause stands, the clock stays frozen
	char = h.Players:simulateSpawn(plr, h.workspace)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
	hum.MoveDirection = Vector3.new(0, 0, 0)
	run(1)
	eq(garden:GetAttribute("Paused"), true, "a respawn leaves the garden paused")
	local hz2 = waitHazard(200)
	eq(hz2, nil, "and 200 s more of it bring no hazard either (the server's pause freezes the clock)")
	pauseCalls = {}
	pauseBtn.Activated:Fire()
	run(0.5)
	eq(pauseCalls[#pauseCalls], false, "the button reads the server: PLAY asks to resume")
	eq(garden:GetAttribute("Paused"), false, "and the garden runs")
	run(1) -- SetPaused is rate-limited to one per 0.5 s
	pauseBtn.Activated:Fire()
	run(0.6)
	eq(garden:GetAttribute("Paused"), true, "paused again for the step test")
	-- a step wakes it: the client asks to resume
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(1)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	eq(pauseCalls[#pauseCalls], false, "a step wakes the gardener: the client asks to resume")
	run(0.5)
	eq(garden:GetAttribute("Paused"), false, "and the garden runs again")
	local more, t = waitHazard(Hz.IntervalMax + 5)
	truthy(more ~= nil and t <= Hz.IntervalMax + 1, string.format("the clock resumed where it stopped: the next hazard %.1f s later", t))
	-- never two at once
	local maxOut = 0
	run(Hz.IntervalMax * 3, function()
		local n = 0
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") and string.match(tostring(d.Name), "^Hazard_%a+$") then n += 1 end
		end
		if n > maxOut then maxOut = n end
		return nil
	end)
	truthy(maxOut <= Budget.MaxHazards, "never more than one hazard out (" .. maxOut .. ")")
end
-- PAUSE pressed with a hazard on its way is queued, never a panic button
do
	local hz = waitHazard(Hz.IntervalMax + 5)
	truthy(hz ~= nil, "a hazard is on its way")
	pauseCalls = {}
	pauseBtn.Activated:Fire()
	frame(1 / 30)
	eq(#pauseCalls, 0, "PAUSE with a hazard inbound does not pause at once")
	truthy(string.find(pauseBtn.Text, "...", 1, true) ~= nil, "the button shows it is queued (" .. pauseBtn.Text .. ")")
	run(6)
	eq(pauseCalls[#pauseCalls], true, "it pauses the first still moment after the hazard has passed")
	pauseBtn.Activated:Fire()
	run(0.5)
	eq(garden:GetAttribute("Paused"), false, "and PLAY resumes")
end
-- the daze greys the gnome sheet and refuses taps with the countdown
do
	garden:SetAttribute("Phase", "build")
	state:SetAttribute("DazedUntil", h.scheduler:now() + 2.5)
	-- a tap picked by View.client reaches the HUD as GardenClientState.PickPad/PickSeq (REVIEW-1)
	state:SetAttribute("PickPad", 1)
	state:SetAttribute("PickSeq", (state:GetAttribute("PickSeq") or 0) + 1)
	frame(1 / 30)
	local hudRoot = plr.PlayerGui.GardenHud.Root
	truthy(string.find(hudRoot.GnomeSheet.SheetTitle.Text, "Seeing stars", 1, true) ~= nil, "a dazed gardener's sheet says Seeing stars")
	local planted = 0
	remotes.Plant.OnServerEvent:Connect(function() planted += 1 end)
	hudRoot.GnomeSheet.Slot1.Activated:Fire()
	frame(1 / 30)
	eq(planted, 0, "and a tap on it is refused on the client")
	truthy(string.find(hudRoot.Toast.Text, "Seeing stars...", 1, true) ~= nil, "with the countdown (" .. hudRoot.Toast.Text .. ")")
	run(3)
	hudRoot.GnomeSheet.Slot1.Activated:Fire()
	frame(1 / 30)
	eq(planted, 1, "once the daze wears off the tap plants")
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(("gnome garden env: %d passed, %d failed"):format(passed, failed))
