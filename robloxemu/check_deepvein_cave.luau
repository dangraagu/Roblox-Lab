-- Deep Vein — the strata, hazards and rest, driven through the REAL client script.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_cave.luau
--
-- The pure modules (EnvBands, Hazards, Rest, Strata) are unit-tested in deep-vein/tests. This file
-- checks the GLUE no unit test can see: that src/client/Cave.client.luau reads the miner's depth from
-- their own character in their own shaft, writes the blended bands into Lighting and glides there,
-- dresses the walls and the surface within the mobile budget, runs hazards at the measured rarity with
-- a shadow the miner can step out of, knocks the character down on a hit, freezes (never resets) the
-- hazard clock while resting, wakes on a swing, and leaks nothing: no remote, nothing collidable, no
-- change to anything the server built. It also MEASURES the budgets EYECANDY.md reports.
--
-- Headless limits, stated: nothing renders and there is no physics. Frames are driven by firing
-- RunService.RenderStepped; the character moves only when this file moves it; a knock is observed as
-- the velocity and PlatformStand the client writes. Whether any of it LOOKS right is on the Studio list.

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

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 1280, 720 },
	touch = false,
})

local VET = 3131
local VET_REBIRTHS = 24 -- wall at layer 312: every stratum exists in this shaft
local PIT = nil -- a layer where only the centre cell is dug and all four sides are rock (a one-cell pit)

-- The veteran's saved cave: the centre column dug all the way to the wall, and the cell east of it on
-- every layer but one, so the miner has an open cell beside them everywhere except in the PIT. A real
-- dig: a rebirth-24 player at their wall has dug at least this much. The pit layer is one where the
-- CAVE has rock on all four sides of the column (natural voids would otherwise leave a way out): the
-- generator is used here to FIND that layer, never to predict a count.
do
	local Config = require("../deep-vein/src/shared/Config")
	local Mine = require("../deep-vein/src/shared/Mine")
	local w = Mine.world(Config, VET_REBIRTHS)
	local c = Mine.center(Config)
	for y = 100, 200 do
		local walled = true
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if not Mine.isSolid(Config, w, c + d[1], y, c + d[2]) then walled = false end
		end
		if walled then PIT = y break end
	end
	assert(PIT ~= nil, "no walled layer between 100 and 200 for the pit")
	local dug = {}
	for y = 1, w.maxLayer do
		dug[Mine.key(c, y, c)] = true
		if y ~= PIT then dug[Mine.key(c + 1, y, c)] = true end
	end
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	store:SetAsync("u_" .. VET, { data = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 8,
		rebirths = VET_REBIRTHS, depthLayer = w.maxLayer, bestLayer = w.maxLayer,
		openedBits = Mine.packOpened(Config, w, dug),
	} })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local Mine = mod("Mine")
local Ore = mod("Ore")
local Strata = mod("Strata")
local Hazards = mod("Hazards")
local bands = Config.Env.Bands
local S = Config.Mine.CellSize
local Lighting = h.Lighting

-- the server's replicated surface, recorded before the client exists
local remotes = RS:FindFirstChild("VeinRemotes")
local serverCalls = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end
local ElevatorEvent = remotes:FindFirstChild("Elevator")

local plr = h:join("Veteran", VET)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(2)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
truthy(hrp ~= nil and hum ~= nil, "the veteran has a root part and a humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

-- a snapshot of every server-built Part's colour, material, size and attributes, to prove the client
-- changes none of them
local shafts = h.workspace:FindFirstChild("Shafts")
local function shaftOf(uid)
	for _, f in shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. uid, true) ~= nil then return f end
	end
	return nil
end
local myShaft = shaftOf(VET)
truthy(myShaft ~= nil, "the veteran's shaft exists")
local origin = Vector3.new(myShaft:FindFirstChild("DepthWall_" .. VET).Position.X, 0, 0)

-- BEFORE any client script runs: what the server built, and what the world and Lighting hold.
local serverLook = {}
for _, d in myShaft:GetDescendants() do
	if d:IsA("BasePart") then
		serverLook[d] = { d.Color, d.Material, d.Transparency, d.Size, d.CanCollide, d.CanQuery, d:GetAttribute("CellKey") }
	end
end
local workspaceBefore, lightingBefore, rsBefore = {}, {}, {}
for _, c in h.workspace:GetChildren() do workspaceBefore[c] = true end
for _, c in Lighting:GetChildren() do lightingBefore[c.Name] = c.ClassName end
-- the server's own dark preset (Fx.Presets.Horror), before the client writes anything: what the lamp was built against
local serverFill = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Exposure = Lighting.ExposureCompensation }
for _, c in RS:GetDescendants() do rsBefore[c] = true end
local expectedCalls = 0 -- remote calls THIS FILE makes (the elevator); the client must add none
local function elevator(dir)
	expectedCalls += 1
	ElevatorEvent:simulateFireServer(plr, dir)
end

local RunServiceEarly = h.game:GetService("RunService")
RunServiceEarly:setIsServer(false) -- the scripts run from here on are client scripts

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okCave, errCave = h:tryRun("client/Cave.client")
truthy(okCave, "Cave.client loads (" .. tostring(errCave) .. ")")

local folder = h.workspace:FindFirstChild("DeepVeinLocalCave")
truthy(folder ~= nil, "the client made its local cave folder")
local caveGui = plr.PlayerGui:FindFirstChild("DeepVeinCave")
local root = caveGui and caveGui:FindFirstChild("Root")
local chip = root and root:FindFirstChild("BandChip")
local restBtn = root and root:FindFirstChild("RestButton")
local warningLabel = root and root:FindFirstChild("HazardWarning")
local card = root and root:FindFirstChild("BandCard")
truthy(chip and restBtn and warningLabel and card, "chip, rest button, warning and title card exist")

local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local UIS = h.game:GetService("UserInputService")
local announced = {}
local lastCard = ""
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card and card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(announced, card.Text)
	end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			table.insert(announced, "<flash>")
		end
	end
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each and each(i) == false then return end
	end
end
-- stand the miner in layer y of their own shaft, in cell (x, z) (the server's own standY)
local C = Mine.center(Config)
local function standAt(y, x, z)
	local lp = Mine.localPos(Config, x or C, y, z or C)
	hrp.CFrame = CFrame.new(origin + Vector3.new(lp.x, Mine.floorY(Config, y) + Config.Env.RootAboveFloor, lp.z))
end

-- ── measurement helpers ─────────────────────────────────────────────────────
local Budget = Config.Budget
local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, trails = 0, hazards = 0 }
local peakWhere = {}
local function measure(where)
	local m = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, trails = 0, hazards = 0 }
	local kinds = {}
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			m.parts += 1
			local k = string.match(d.Name, "^Hazard_(%a+)$")
			if k then kinds[k] = true end
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate or 0
		elseif cls == "PointLight" and d.Enabled then
			m.lights += 1
		elseif cls == "Beam" and d.Enabled then
			m.beams += 1
		elseif cls == "Trail" and d.Enabled then
			m.trails += 1
		end
	end
	for _ in kinds do m.hazards += 1 end
	for k, v in m do
		if v > peak[k] then
			peak[k] = v
			peakWhere[k] = where
		end
	end
	return m, kinds
end
local function mining(on)
	-- a miner at work: holding a direction key would walk them off; a swing is a click
	hum.MoveDirection = Vector3.new(0, 0, 0)
	return on
end
local clickEvery, clickAcc = nil, 0
local function click()
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
end
-- a frame in which the miner swings every `clickEvery` seconds (activity, like mining)
local function workFrame(dt)
	if clickEvery then
		clickAcc += dt
		if clickAcc >= clickEvery then
			clickAcc = 0
			click()
		end
	end
	frame(dt)
end
local function work(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		workFrame(dt)
		if each and each(i) == false then return end
	end
end
local function standDepth(p, x, z)
	-- root at continuous depth p (layers) in cell (x, z)
	local lp = Mine.localPos(Config, x or C, math.max(1, math.floor(p)), z or C)
	hrp.CFrame = CFrame.new(origin + Vector3.new(lp.x, Config.Env.RootAboveFloor - p * S, lp.z))
end

--======================================================================= 1. depth is read from the server's placement

run(3, 1 / 30)
do
	local b = bands[1]
	truthy(string.find(chip.Text, b.name, 1, true) ~= nil and string.find(chip.Text, "0 m", 1, true) ~= nil,
		"at join the server placed the miner at the mouth and the chip says " .. b.name .. " at 0 m (" .. chip.Text .. ")")
	eq(announced[1], b.emoji .. " " .. string.upper(b.name), "the first card names where the miner is")
	local look = Lighting.ClockTime
	near(look, b.lighting.ClockTime, 0.05, "the surface is the client's dusk, not the server's midnight")
end

-- walk down the centre column (dug to the wall): the chip follows the layer the FEET are in
do
	local wrong = 0
	-- the last layer above each stratum and its first layer, then the bottom of the shaft
	local layers = { 1 }
	for i = 2, #bands do
		table.insert(layers, bands[i].from - 1)
		table.insert(layers, bands[i].from)
	end
	table.insert(layers, 311)
	for _, y in layers do
		standAt(y)
		run(0.5, 1 / 30)
		local b = bands[EnvBands.indexAt(bands, y)]
		local want = string.format("%s %s  ·  %d m", b.emoji, b.name, y * S)
		if string.sub(chip.Text, 1, #want) ~= want then
			wrong += 1
			print("  layer " .. y .. ": chip '" .. chip.Text .. "', want '" .. want .. "...'")
		end
	end
	eq(wrong, 0, "standing in each layer (server standY), the chip names that layer's stratum and depth in m")
	-- every band was announced exactly once on the way down, and none with a fanfare: this veteran's
	-- best is the wall at layer 312, so nothing here is a new record
	for i, b in bands do
		local seen = 0
		for _, t in announced do
			if string.find(t, string.upper(b.name), 1, true) then seen += 1 end
		end
		eq(seen, 1, "band " .. i .. " (" .. b.id .. ") got one title card on the way down")
	end
	local fanfare = false
	for _, t in announced do
		if t == "<flash>" or string.find(t, "YOU REACHED", 1, true) then fanfare = true end
	end
	eq(fanfare, false, "a veteran whose best is the core gets no \"YOU REACHED\" fanfare for strata they have seen")
end

do
	-- Resume session 2026-09-24. The server writes the root 4 studs above the floor (standY) and every
	-- stand above uses that; a real R15 then SETTLES with its root 3.0 above the floor (HipHeight 2 + half
	-- its 2-stud height), and a real humanoid hovers a hair either side of that. The name used to be read
	-- at root - 3, exactly on the floor's plane, so a settled miner a hair low read the layer BELOW.
	-- Stand one in the last layer above every stratum, 0.02 studs low: the chip must still name its own
	-- layer, with the depth the HUD shows.
	local wrong = 0
	for i = 2, #bands do
		local y = bands[i].from - 1
		local lp = Mine.localPos(Config, C, y, C)
		hrp.CFrame = CFrame.new(origin + Vector3.new(lp.x, Mine.floorY(Config, y) + 2.98, lp.z))
		run(0.3, 1 / 30)
		local b = bands[EnvBands.indexAt(bands, y)]
		local want = string.format("%s %s  ·  %d m", b.emoji, b.name, y * S)
		if string.sub(chip.Text, 1, #want) ~= want then
			wrong += 1
			print("  settled root in layer " .. y .. ": chip '" .. chip.Text .. "', want '" .. want .. "...'")
		end
	end
	eq(wrong, 0, "a settled R15 (root 2.98 above the floor) in the last layer above each stratum is named its own layer")
end

--======================================================================= 2. an elevator ride glides

do
	standAt(1)
	run(6, 1 / 30)
	local top = bands[1].lighting
	local core = bands[#bands].lighting
	-- Resume session 2026-09-24 (mutation sweep K4/K5): the series starts with the values BEFORE the ride.
	-- Starting it at the first frame after DESCEND let a snap that lands in that very frame pass as "no
	-- change", and a set piece that snaps to weight 0 is unparented at once, so it has to be followed by
	-- reference: an unparented post counts as fully transparent.
	local post = folder:FindFirstChild("HeadframePost")
	truthy(post ~= nil and post.Transparency < 0.05, "set-up: at the mouth the headframe is up and solid")
	local function postT()
		return if post and post.Parent == folder then post.Transparency else 1
	end
	-- DESCEND: the server teleports the miner to the deepest cell they opened (the wall, in the core)
	local clocks, ambR = { Lighting.ClockTime }, { Lighting.Ambient.R * 255 }
	local headframeT, worstFade = postT(), 0
	elevator("down")
	run(6, 1 / 30, function()
		table.insert(clocks, Lighting.ClockTime)
		table.insert(ambR, Lighting.Ambient.R * 255)
		local t = postT()
		worstFade = math.max(worstFade, math.abs(t - headframeT))
		headframeT = t
	end)
	local layer = Strata.layerAt(Config, Mine, hrp.Position.Y)
	truthy(layer >= 150, "set-up: DESCEND put the veteran in the core (layer " .. layer .. ")")
	local worstClock, worstAmb, overshoot = 0, 0, false
	for i = 2, #clocks do
		worstClock = math.max(worstClock, math.abs(clocks[i] - clocks[i - 1]))
		worstAmb = math.max(worstAmb, math.abs(ambR[i] - ambR[i - 1]))
		if clocks[i] > core.ClockTime + 0.01 then overshoot = true end
	end
	local span = math.abs(core.ClockTime - (clocks[1] or top.ClockTime))
	print(string.format("  DESCEND 1 -> %d: ClockTime %.2f -> %.2f, worst step %.3f (%.0f%% of the change); Ambient.R worst step %.1f",
		layer, clocks[1] or -1, clocks[#clocks] or -1, worstClock, 100 * worstClock / math.max(span, 1e-6), worstAmb))
	truthy(span > 1, string.format("set-up: the ride changes ClockTime (%.2f)", span))
	truthy(worstClock <= 0.15 * span, "the sky darkens over many frames, never in one cut")
	local ambSpan = math.abs(core.Ambient[1] - ambR[1])
	truthy(worstAmb <= 0.15 * ambSpan, string.format("…and so does the Ambient (worst step %.1f of %.1f)", worstAmb, ambSpan))
	truthy(not overshoot, "and never overshoots")
	near(clocks[#clocks], core.ClockTime, 0.05, "after 6 s it is the core's ClockTime")
	near(Lighting.Ambient.R * 255, core.Ambient[1], 2, "and the core's orange Ambient")
	truthy(worstFade <= 0.1, string.format("the headframe fades out rather than vanishing (worst %.3f per frame)", worstFade))
	-- written at most LightingHz times a second
	local writes, last = 0, Lighting.ClockTime
	elevator("up")
	run(2, 1 / 60, function()
		if Lighting.ClockTime ~= last then
			writes += 1
			last = Lighting.ClockTime
		end
	end)
	truthy(writes <= 2 * Config.Env.LightingHz + 1, "Lighting is written at most LightingHz times a second (" .. writes .. " in 2 s)")
end

--======================================================================= 3. every band and every seam, within budget

local bandRows = {}
local function luma(c3) return 255 * (0.2126 * c3.R + 0.7152 * c3.G + 0.0722 * c3.B) end
local function luma3(t) return 0.2126 * t[1] + 0.7152 * t[2] + 0.0722 * t[3] end
local fillWorst, decorGlowSeen, decorGlowBad, decorOreWorst, decorOreAt = 0, 0, 0, math.huge, ""
do
	-- review 2026-09-24, finding 6: Config.Env.LampFill quotes the server's preset; it must BE the server's preset
	local fill = Config.Env.LampFill
	local function same(c3, t) return math.abs(c3.R * 255 - t[1]) < 1 and math.abs(c3.G * 255 - t[2]) < 1 and math.abs(c3.B * 255 - t[3]) < 1 end
	truthy(same(serverFill.Ambient, fill.ReferenceAmbient) and same(serverFill.OutdoorAmbient, fill.ReferenceOutdoorAmbient)
		and math.abs(serverFill.Exposure - fill.ReferenceExposure) < 1e-6,
		"Config.Env.LampFill's references are the server's real Lighting before the client ran (Ambient " .. tostring(serverFill.Ambient) .. ")")
end
do
	mining(true)
	clickEvery = 1.0
	local stops = {}
	for i, b in bands do
		local nextFrom = if bands[i + 1] then bands[i + 1].from - (bands[i + 1].fade or 0) else b.from + 30
		table.insert(stops, { where = b.id, p = math.floor((b.from + nextFrom) / 2) + 0.0, band = i })
		if bands[i + 1] and (bands[i + 1].fade or 0) > 0 then
			table.insert(stops, { where = b.id .. " > " .. bands[i + 1].id, p = bands[i + 1].from - bands[i + 1].fade / 2, seam = true })
		end
	end
	for _, st in stops do
		standDepth(st.p)
		work(8, 1 / 30)
		-- step into the open cell beside the column and back, so critters have a trail to follow
		standDepth(st.p, C + 1, C)
		work(2, 1 / 30)
		standDepth(st.p)
		work(2, 1 / 30)
		local m = measure(st.where)
		-- the lamp stays the main light: below the surface band the fill the client wrote stays near the server's
		if st.p >= bands[2].from then
			fillWorst = math.max(fillWorst, luma(Lighting.Ambient) / luma(serverFill.Ambient), luma(Lighting.OutdoorAmbient) / luma(serverFill.OutdoorAmbient))
		end
		-- every glowing decoration the client BUILT is from its kind's palette, and passes for no ore that can sit there
		for _, d in folder:GetChildren() do
			local k = string.match(d.Name, "^Decor_(%a+)$")
			if k and d.Material == Enum.Material.Neon then
				decorGlowSeen += 1
				local rgb = { math.round(d.Color.R * 255), math.round(d.Color.G * 255), math.round(d.Color.B * 255) }
				local inPalette = false
				for _, c in (Config.Env.DecorGlow[k] or {}) do
					if c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] then inPalette = true end
				end
				if not inPalette then
					decorGlowBad += 1
					if decorGlowBad == 1 then print(string.format("  %s: Decor_%s glows {%d,%d,%d}, not from Config.Env.DecorGlow", st.where, k, rgb[1], rgb[2], rgb[3])) end
				end
				local L = Mine.layerOfY(Config, d.Position.Y - origin.Y)
				for layer = math.max(1, L - 1), L + 1 do
					for tier = 1, Config.MaxOre do
						if Ore.weight(Config, tier, layer) > 0 then
							local oc = Config.Ores.Color[tier]
							local dist = math.sqrt((rgb[1] - oc[1]) ^ 2 + (rgb[2] - oc[2]) ^ 2 + (rgb[3] - oc[3]) ^ 2)
							if dist < decorOreWorst then
								decorOreWorst = dist
								decorOreAt = string.format("%s {%d,%d,%d} vs %s at layer %d", k, rgb[1], rgb[2], rgb[3], Config.Ores.Names[tier], layer)
							end
						end
					end
				end
			end
		end
		table.insert(bandRows, string.format("  %-22s p=%6.1f  parts %3d  emitters %d (%4.1f/s)  lights %d",
			st.where, st.p, m.parts, m.emitters, m.rate, m.lights))
		if st.band then
			local b = bands[st.band]
			near(Lighting.ClockTime, b.lighting.ClockTime, 0.05, st.where .. ": ClockTime reached the band's value")
			near(Lighting.Ambient.G * 255, b.lighting.Ambient[2], 2, st.where .. ": Ambient reached the band's value")
			local atm = Lighting:FindFirstChild("FxAtmosphere")
			near(atm and atm.Density, b.atmosphere.Density, 0.01, st.where .. ": Atmosphere.Density reached the band's value")
			local cc = Lighting:FindFirstChild("FxColorCorrection")
			near(cc and cc.TintColor.B * 255, b.colorCorrection.TintColor[3], 2, st.where .. ": the colour grade reached the band's")
			-- its weather is on, and the other bands' is off
			if b.weather then
				local pe = nil
				for _, d in folder:GetDescendants() do
					if d.ClassName == "ParticleEmitter" and d.Name == "Weather_" .. b.weather.kind then pe = d end
				end
				truthy(pe ~= nil and pe.Enabled and math.abs(pe.Rate - b.weather.rate) < 0.5,
					st.where .. ": its weather (" .. b.weather.kind .. ") is on at its rate")
			end
			-- its critters are out
			for _, a in b.ambient or {} do
				local n = 0
				for _, d in folder:GetChildren() do
					if d.Name == "Critter_" .. a.kind then n += 1 end
				end
				truthy(n >= a.count, st.where .. ": " .. a.count .. " " .. a.kind .. " are out (" .. n .. " parts)")
			end
			-- its wall decor is built around the miner, and nothing from a band it is not near
			local kinds = {}
			for _, d in folder:GetChildren() do
				local k = string.match(d.Name, "^Decor_(%a+)$")
				if k then kinds[k] = true end
			end
			local own = 0
			for _, k in (b.decor or {}).kinds or {} do if kinds[k] then own += 1 end end
			truthy(own > 0, st.where .. ": its wall decorations are up")
			-- its set pieces are shown, the others are not
			local headframe = folder:FindFirstChild("HeadframePost") ~= nil
			local coreglow = folder:FindFirstChild("CoreGlow") ~= nil
			eq(headframe, b.id == "topsoil", st.where .. ": the headframe is " .. (if b.id == "topsoil" then "up" else "not parented"))
			eq(coreglow, b.id == "core", st.where .. ": the core's glowing floor is " .. (if b.id == "core" then "up" else "not parented"))
		end
	end
	print("  budget at every band and seam (after 12 s there, trail walked):")
	for _, r in bandRows do print(r) end
	print(string.format("  lamp fill below the surface: up to x%.2f of the server's; glowing decor: %d parts, worst %.1f from an ore (%s)",
		fillWorst, decorGlowSeen, decorOreWorst, decorOreAt))
	truthy(fillWorst > 0 and fillWorst <= Config.Env.LampFill.MaxAmbientRatio + 0.02, string.format(
		"below the surface the client's fill light stays within x%.2f of the server's dark preset, so the lamp stays the light (worst x%.2f)",
		Config.Env.LampFill.MaxAmbientRatio, fillWorst))
	truthy(decorGlowSeen >= 20, "set-up: glowing decorations were built and read (" .. decorGlowSeen .. ")")
	eq(decorGlowBad, 0, "every glowing decoration the client built takes its colour from Config.Env.DecorGlow")
	truthy(decorOreWorst >= Config.Env.MinDecorOreContrast, string.format(
		"…and none glows within MinDecorOreContrast of an ore that can sit beside it (worst %.1f, %s)", decorOreWorst, decorOreAt))
end

--======================================================================= 4. nothing leaks, nothing is touched

local function auditLocalParts(where)
	local bad = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			if d.CanCollide or d.CanQuery or d.CanTouch or not d.Anchored or d.CastShadow then
				bad += 1
				if bad == 1 then print("  " .. where .. ": " .. d.Name .. " is collidable/queryable/touchable/unanchored/shadowed") end
			end
		end
	end
	eq(bad, 0, where .. ": every local part is anchored and cannot be collided with, clicked, touched, or cast a shadow")
end
auditLocalParts("after the band sweep")

--======================================================================= 5. hazards: rare, telegraphed, a shadow you can step out of

local function hazardShown()
	for _, d in folder:GetChildren() do
		local k = string.match(d.Name, "^Hazard_(%a+)$")
		if k then return k end
	end
	return nil
end

-- (a) twenty minutes of mining in the Crystal Geode, standing still: every hazard hits
local hz = { spawns = 0, hits = 0, kinds = {}, warnLead = math.huge, maxAtOnce = 0, knockH = math.huge, knockV = -math.huge,
	knockBad = 0 }
do
	local geode = bands[EnvBands.indexOf(bands, "geode")]
	local p = geode.from + 3
	-- a hazard launched in an earlier section (the band sweep ends in the core) may still be in flight: it
	-- plays out before the count starts, or it is counted as a geode hazard that can never land here
	-- (mutation sweep, resume session: seen once as "only the band's own kinds fly (magma)", 7 hits of 8)
	work(10, 1 / 15, function()
		if hazardShown() == nil and not hum.PlatformStand then return false end
	end)
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	standDepth(p)
	clickEvery = 1.0
	local shownBefore = false
	local warnedAt = nil
	local standingStill = hrp.Position
	local t = 0
	local function onFrame()
		t += 1 / 15
		local k = hazardShown()
		if k and not shownBefore then
			hz.spawns += 1
			hz.kinds[k] = true
			-- the shadow / vent ring lies ON the floor of the miner's cell, whatever height the root is at
			local shadow = folder:FindFirstChild("HazardShadow")
			local floorY = origin.Y + Mine.floorY(Config, math.floor(p))
			hz.ringOff = math.max(hz.ringOff or 0, if shadow then math.abs(shadow.Position.Y - floorY) else math.huge)
			-- …and its dark disc IS the danger zone: 2 x (hitRadius + PlayerRadius) across, centred where the
			-- miner stands (mutation sweep, resume session: drawn off-centre or half as wide went unnoticed)
			local kd = Config.Hazards.Kinds[k]
			local wantD = 2 * (kd.hitRadius + Config.Hazards.PlayerRadius)
			hz.ringSize = math.max(hz.ringSize or 0, if shadow then math.max(math.abs(shadow.Size.Y - wantD),
				math.abs(shadow.Size.Z - wantD)) else math.huge)
			hz.ringCentre = math.max(hz.ringCentre or 0, if shadow then Vector3.new(shadow.Position.X - standingStill.X, 0,
				shadow.Position.Z - standingStill.Z).Magnitude else math.huge)
		end
		shownBefore = k ~= nil
		local _, kinds = measure("a hazard in flight (geode)")
		local n = 0
		for _ in kinds do n += 1 end
		hz.maxAtOnce = math.max(hz.maxAtOnce, n)
		if warningLabel.Visible and warnedAt == nil then warnedAt = t end
		if hum.PlatformStand and warnedAt then
			hz.hits += 1
			hz.warnLead = math.min(hz.warnLead, t - warnedAt)
			local v = hrp.AssemblyLinearVelocity
			hz.knockH = math.min(hz.knockH, Vector3.new(v.X, 0, v.Z).Magnitude)
			hz.knockV = math.max(hz.knockV, v.Y)
			warnedAt = nil
			-- the knock wears off by itself
			local off = false
			for _ = 1, 30 do
				workFrame(1 / 15)
				t += 1 / 15
				if not hum.PlatformStand then off = true break end
			end
			if not off then hz.knockBad += 1 end
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.CFrame = CFrame.new(standingStill) -- no physics: the push is observed, then the miner stands again
		end
		if not warningLabel.Visible and not hum.PlatformStand and hazardShown() == nil then warnedAt = nil end
	end
	work(20 * 60, 1 / 15, onFrame)
	-- a hazard launched in the window's last seconds lands after it: let it land before counting (a hazard
	-- counted at launch but not at its landing was a windowing flake, not a miss; resume session)
	work(10, 1 / 15, function()
		onFrame()
		if hazardShown() == nil and not hum.PlatformStand and not warningLabel.Visible then return false end
	end)
	local kinds = {}
	for k in hz.kinds do table.insert(kinds, k) end
	table.sort(kinds)
	print(string.format("  geode, 20 min standing still: %d hazards (%s), %d hits, warning at least %.2f s before each hit;"
		.. " knock >= %.1f studs/s sideways, <= %.1f up", hz.spawns, table.concat(kinds, ", "), hz.hits, hz.warnLead, hz.knockH, hz.knockV))
	truthy(hz.spawns >= 6 and hz.spawns <= 10, "one hazard every 2-3 minutes of mining (" .. hz.spawns .. " in 20 min)")
	eq(hz.maxAtOnce, 1, "never two hazards at once")
	for k in hz.kinds do
		truthy(table.find(geode.hazards, k) ~= nil, "only the band's own kinds fly (" .. k .. ")")
	end
	eq(hz.hits, hz.spawns, "a miner who never moves is hit by every one (the shadow is where it lands)")
	truthy((hz.ringSize or math.huge) <= 0.01, string.format(
		"the dark disc is exactly the danger zone, 2 x (hitRadius + PlayerRadius) across (worst %.3f studs off)", hz.ringSize or math.huge))
	truthy((hz.ringCentre or math.huge) <= 0.05, string.format(
		"…centred where the miner stands (worst %.3f studs off)", hz.ringCentre or math.huge))
	truthy((hz.ringOff or math.huge) <= 0.2, string.format("the ring lies on the floor of the miner's cell, not at root - 3 (worst %.2f studs off)", hz.ringOff or math.huge))
	truthy(hz.warnLead >= 3 - 1 / 15, string.format("every hit was warned at least 3 s before (%.2f s)", hz.warnLead))
	truthy(hz.knockH >= 20, string.format("a hit knocks the miner sideways (>= %.1f studs/s)", hz.knockH))
	truthy(hz.knockV <= 15, string.format("and never launches them (<= %.1f studs/s up)", hz.knockV))
	eq(hz.knockBad, 0, "the knock wears off within 2 s every time (PlatformStand released)")
end

-- (b) twenty minutes more, stepping into the open cell beside the column when the warning says MOVE
do
	local p = bands[EnvBands.indexOf(bands, "geode")].from + 3
	standDepth(p)
	local spawns, hits, dodges = 0, 0, 0
	local shownBefore = false
	local walking = nil -- target position while stepping aside
	local stepFrom = nil
	local ringDrift, ringSeen = 0, 0
	local function onFrame()
		local k = hazardShown()
		if k and not shownBefore then spawns += 1 end
		shownBefore = k ~= nil
		if walking and stepFrom then
			-- the ring locked where the miner stood; it must not follow them out of it
			local shadow = folder:FindFirstChild("HazardShadow")
			if shadow then
				ringSeen += 1
				ringDrift = math.max(ringDrift, Vector3.new(shadow.Position.X - stepFrom.X, 0, shadow.Position.Z - stepFrom.Z).Magnitude)
			end
		end
		if hum.PlatformStand then
			hits += 1
			for _ = 1, 30 do workFrame(1 / 15) if not hum.PlatformStand then break end end
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
		if warningLabel.Visible and string.find(warningLabel.Text, "MOVE!", 1, true) and walking == nil then
			-- walk (16 studs/s) one cell east, into the open cell beside the column
			local lp = Mine.localPos(Config, C + 1, math.floor(p), C)
			walking = Vector3.new(origin.X + lp.x, hrp.Position.Y, origin.Z + lp.z)
			stepFrom = hrp.Position
			dodges += 1
		end
		if walking then
			local d = walking - hrp.Position
			local step = 16 / 15
			if d.Magnitude <= step then
				hrp.CFrame = CFrame.new(walking)
			else
				hrp.CFrame = CFrame.new(hrp.Position + d.Unit * step)
			end
			hum.MoveDirection = if d.Magnitude > 0.05 then d.Unit else Vector3.new(0, 0, 0)
		end
		if walking and k == nil and not warningLabel.Visible then
			-- the danger has passed: walk back to the column for the next one
			hrp.CFrame = CFrame.new(stepFrom)
			hum.MoveDirection = Vector3.new(0, 0, 0)
			walking = nil
		end
	end
	work(20 * 60, 1 / 15, onFrame)
	-- as in (a): a hazard still in flight when the window closes is played out before counting
	work(10, 1 / 15, function()
		onFrame()
		if hazardShown() == nil and walking == nil and not hum.PlatformStand and not warningLabel.Visible then return false end
	end)
	print(string.format("  geode, 20 min stepping one cell aside at MOVE!: %d hazards, %d hits", spawns, hits))
	truthy(ringSeen > 10, "set-up: the ring was seen while the miner walked out of it (" .. ringSeen .. " frames)")
	truthy(ringDrift <= 0.05, string.format("a locked ring stays where the miner stood while they walk out of it (worst %.3f studs)", ringDrift))
	truthy(spawns >= 6, "set-up: hazards kept coming (" .. spawns .. ")")
	eq(dodges, spawns, "every hazard said MOVE! before it landed")
	eq(hits, 0, "a miner who steps into the open cell beside them is never hit")
end

-- (c) the one-cell pit: no open cell beside the miner, so a due hazard waits
do
	hum.MoveDirection = Vector3.new(0, 0, 0)
	standAt(PIT)
	-- This file moves the root by hand, 43 layers down from the geode, where nothing is streamed yet. For a few
	-- frames the pit's walls are not built and the client (which judges "open" from the Parts it can see)
	-- takes them for open cells, so a hazard due at that instant launched: a rare flake of this section
	-- (review round, reproduced by forcing a hazard due on arrival). A real arrival that far down is
	-- DESCEND, which builds the landing cell's 3x3 neighbourhood synchronously before moving the miner
	-- (REVIEW-4). So the server streams the pit in first, as DESCEND would, and the count starts in a pit.
	h:advance(1)
	local walls = 0
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		for _, p in myShaft:GetChildren() do
			if p:GetAttribute("CellKey") == Mine.key(C + d[1], PIT, C + d[2]) then walls += 1 end
		end
	end
	eq(walls, 4, "set-up: the pit's four walls are built before the count starts")
	local spawns = 0
	local shownBefore = false
	work(8 * 60, 1 / 15, function()
		local k = hazardShown()
		if k and not shownBefore then spawns += 1 end
		shownBefore = k ~= nil
	end)
	eq(spawns, 0, "eight minutes in a one-cell pit (layer " .. PIT .. "): no hazard (nowhere to step, so none is launched)")
	-- climb out to a layer with an open side: the held hazard comes at once, not after a backlog
	standAt(PIT - 1)
	local firstAt = nil
	local t = 0
	work(200, 1 / 15, function()
		t += 1 / 15
		if hazardShown() and firstAt == nil then firstAt = t end
		if firstAt then return false end
	end)
	truthy(firstAt ~= nil and firstAt < 2, "the held hazard launches as soon as there is room (" .. tostring(firstAt) .. " s)")
	-- let it land and pass
	work(8, 1 / 15)
	if hum.PlatformStand then work(2, 1 / 15) end
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end

-- (d) the surface is quiet
do
	standAt(0)
	local spawns = 0
	local shownBefore = false
	work(10 * 60, 1 / 15, function()
		local k = hazardShown()
		if k and not shownBefore then spawns += 1 end
		shownBefore = k ~= nil
	end)
	eq(spawns, 0, "ten minutes at the mouth: no hazard at the surface")
end

-- (e) a rock that hangs over a miner is drawn where they can SEE it (resume session 2026-09-24). The plan
-- keeps it `height` studs up; under an open column that is in plain sight, under a tunnel's ceiling it
-- would be inside the rock. Layer PIT + 1: the centre column is open all the way up, and the dug cell east
-- of it has rock overhead (layer PIT has only the centre dug). Hazards every 8-10 s for this section only
-- (in memory; restored below, before the rest section measures the real interval).
do
	local oldMin, oldMax = Config.Hazards.IntervalMin, Config.Hazards.IntervalMax
	Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 8, 10
	clickEvery = 1.0
	local y = PIT + 1
	-- Review 2026-09-24, finding 1: drawn "just under the ceiling", a 2-3.8-stud model in a one-layer tunnel
	-- hung THROUGH the miner's head (an R15 is ~5.2 studs, the roof 6) and dropped in one frame. Measured
	-- here with the root where a real R15 settles (floor + 3.0), not only where the server puts it (+4).
	local HEAD = Config.Env.HeadTopAboveFloor
	local function hangOf(x, rootAbove)
		-- stand in cell (x, y, C) and wait for a hazard that drops from ABOVE; follow its drawn model from the
		-- frame it appears to the frame it is gone, and report its hang, its fall, its landing and the hit
		local lp = Mine.localPos(Config, x, y, C)
		local function put()
			hrp.CFrame = CFrame.new(origin + Vector3.new(lp.x, Mine.floorY(Config, y) + rootAbove, lp.z))
		end
		put()
		work(2, 1 / 15)
		local floorY = origin.Y + Mine.floorY(Config, y)
		local r = { hangBottom = math.huge, hangTop = -math.huge, centre = nil, laneTop = -math.huge, lowBottom = math.huge,
			fallFrames = 0, descent = 0, hit = false, kind = nil }
		local prevC, firstC = nil, nil
		work(240, 1 / 15, function()
			local k = hazardShown()
			if r.kind == nil and k and Config.Hazards.Kinds[k].drop == "above" and warningLabel.Visible then r.kind = k end
			if r.kind and k == r.kind then
				-- the model's body is its tallest part (a relic's glowing plate and a shard's lit edge ride on it)
				local body = nil
				for _, d in folder:GetChildren() do
					if d.Name == "Hazard_" .. k and d.Transparency < 1 and (body == nil or d.Size.Y > body.Size.Y) then body = d end
				end
				for _, d in folder:GetChildren() do
					if d.Name == "Hazard_" .. k and d.Transparency < 1 then
						r.lowBottom = math.min(r.lowBottom, d.Position.Y - d.Size.Y / 2 - floorY)
					end
				end
				for _, d in { body } do
					if d then
						local c = d.Position.Y - floorY
						local half = d.Size.Y / 2
						firstC = firstC or c
						if math.abs(c - firstC) < 0.02 then
							-- still where it first hung (the root does not move, so neither does the hang point)
							r.hangBottom = math.min(r.hangBottom, c - half)
							r.hangTop = math.max(r.hangTop, c + half)
							r.centre = c
						end
						-- the fall that can be SEEN: frames it moves down while still above the floor (a model sinking
						-- through the floor after the hit is not a fall anyone sees)
						if prevC and c < prevC - 0.05 and c - half >= -0.05 then
							r.fallFrames += 1
							r.descent = math.max(r.descent, firstC - c)
						end
						prevC = c
					end
				end
				local lane = folder:FindFirstChild("HazardLane")
				if lane and lane.Transparency < 1 and warningLabel.Visible then
					r.laneTop = math.max(r.laneTop, lane.Position.Y + lane.Size.Y / 2 - floorY)
				end
			end
			if hum.PlatformStand and r.kind then r.hit = true end
			-- no physics: the knock is observed, the miner stays where they stood; done once it is gone
			if r.kind and k == nil and not hum.PlatformStand then return false end
		end)
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		return r
	end
	local open = hangOf(C, 3.0)
	truthy(open.kind ~= nil, "set-up: a hazard came over the open column (" .. tostring(open.kind) .. ")")
	truthy(open.centre ~= nil and open.centre >= 15, string.format(
		"under an open column it hangs at its full height, in plain sight (%.1f studs over the floor)", open.centre or -1))
	truthy(open.lowBottom >= -0.05, string.format("…and it lands ON the floor, never sinking through it (lowest bottom %.2f)", open.lowBottom))
	print(string.format("  over the open column (%s): hangs at %.1f, lowest bottom %.2f", tostring(open.kind), open.centre or -1, open.lowBottom))
	-- every kind that falls from above, in the tunnel (the band's list forced to one kind at a time, in memory)
	local bandHere = bands[EnvBands.indexAt(bands, y)]
	local kindsHere = bandHere.hazards
	local aboveKinds = {}
	for name, kd in Config.Hazards.Kinds do
		if kd.drop == "above" then table.insert(aboveKinds, name) end
	end
	table.sort(aboveKinds)
	for _, kind in aboveKinds do
		bandHere.hazards = { kind }
		local tun = hangOf(C + 1, 3.0)
		print(string.format("  in the tunnel, %-10s (roof at %d, head at %.1f): hangs %.2f..%.2f, falls %.2f studs over %d frames,"
			.. " lowest bottom %.2f, lane top %.2f, hit %s", kind, S, HEAD, tun.hangBottom, tun.hangTop, tun.descent, tun.fallFrames,
			tun.lowBottom, tun.laneTop, tostring(tun.hit)))
		eq(tun.kind, kind, "set-up: a " .. kind .. " came over the tunnel")
		truthy(tun.hangBottom >= HEAD - 0.01, string.format(
			"%s: in a one-layer tunnel it never hangs inside the miner: its bottom stays over their head (%.2f >= %.1f)", kind, tun.hangBottom, HEAD))
		truthy(S - tun.hangBottom >= 0.5, string.format(
			"%s: …and at least half a stud of it pokes out of the roof, where it can be seen (%.2f studs)", kind, S - tun.hangBottom))
		truthy(tun.fallFrames >= 6 and tun.descent >= 3, string.format(
			"%s: …then it FALLS where you can see it: %.2f studs over %d frames at 15 fps, not one frame", kind, tun.descent, tun.fallFrames))
		truthy(tun.lowBottom >= -0.05, string.format("%s: …and lands on the floor, never through it (lowest bottom %.2f)", kind, tun.lowBottom))
		truthy(tun.laneTop <= S + 0.3, string.format("%s: …its lane line runs from the model's tip down, not up through the rock (top %.2f)",
			kind, tun.laneTop))
		truthy(tun.hit, kind .. ": and it still lands on a miner who does not move (the drawing changes nothing about the hit)")
	end
	bandHere.hazards = kindsHere
	-- the server's placement (root at floor + 4) draws the same: the head clearance is from the floor, not the root
	local placed = hangOf(C + 1, Config.Env.RootAboveFloor)
	truthy(placed.kind ~= nil and placed.hangBottom >= HEAD - 0.01 and placed.hit, string.format(
		"with the root where the server places it (floor + %d) it hangs over the head too (bottom %.2f) and still hits",
		Config.Env.RootAboveFloor, placed.hangBottom))

	-- (f) review 2026-09-24, finding 4: the ring was drawn on the floor of the ROOT's layer, so a jump in the
	-- open column lifted the "shadow" 6 studs into the air, and if the plan locked mid-jump it stayed there,
	-- over the miner's head, while the banner said to step out of it. A real-speed jump (50 studs/s up,
	-- gravity 196.2: the root peaks 6.4 studs higher), off the ground the whole way, at 60 fps. Twice: once
	-- early in the warning, once timed to span the lock.
	local floorY = origin.Y + Mine.floorY(Config, y)
	local lpC = Mine.localPos(Config, C, y, C)
	local function put(hgt) hrp.CFrame = CFrame.new(origin + Vector3.new(lpC.x, Mine.floorY(Config, y) + hgt, lpC.z)) end
	local function ringOff()
		local d = folder:FindFirstChild("HazardShadow")
		if d and d.Transparency < 1 then return d.Position.Y - floorY end
		return nil
	end
	local function jumpUnder(lead)
		-- wait for an above-hazard in the open column, jump `lead(kind)` seconds after it appears; report the
		-- worst ring height over the floor during the jump, after landing, and whether it still hit
		put(3)
		work(1, 1 / 15)
		local res = { kind = nil, air = -math.huge, after = -math.huge, peak = 0, lockedInAir = false, hit = false }
		local guard = 0
		while res.kind == nil and guard < 20 * 60 do
			guard += 1
			workFrame(1 / 60)
			local k = hazardShown()
			if k and Config.Hazards.Kinds[k].drop == "above" and ringOff() then res.kind = k end
		end
		if res.kind == nil then return res end
		local waited = 0
		while waited < lead(Config.Hazards.Kinds[res.kind]) do
			frame(1 / 60)
			waited += 1 / 60
		end
		hum.FloorMaterial = Enum.Material.Air
		hum.Jump = true
		local tt = 0
		while true do
			tt += 1 / 60
			local hgt = 3 + 50 * tt - 98.1 * tt * tt
			if hgt <= 3 then break end
			put(hgt)
			hrp.AssemblyLinearVelocity = Vector3.new(0, 50 - 196.2 * tt, 0)
			frame(1 / 60)
			hum.Jump = false
			res.peak = math.max(res.peak, hgt)
			local rr = ringOff()
			if rr then res.air = math.max(res.air, math.abs(rr)) end
			if string.find(warningLabel.Text, "MOVE!", 1, true) then res.lockedInAir = true end
		end
		hum.FloorMaterial = Enum.Material.Slate
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		put(3)
		for _ = 1, 150 do
			frame(1 / 60)
			local rr = ringOff()
			if rr then res.after = math.max(res.after, math.abs(rr)) end
			if hum.PlatformStand then res.hit = true end
			if hazardShown() == nil and not hum.PlatformStand then break end
		end
		for _ = 1, 60 do
			if not hum.PlatformStand then break end
			frame(1 / 60)
		end
		hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		return res
	end
	local early = jumpUnder(function() return 0.3 end)
	local acrossLock = jumpUnder(function(kd) return (kd.telegraph - kd.commit) - 0.2 end)
	print(string.format("  a jump under a warning (%s): root peaks %.2f over the floor, ring at most %.2f off the floor in the air;"
		.. " across the lock (%s, locked in the air: %s): %.2f in the air, %.2f after landing, hit %s", tostring(early.kind), early.peak,
		early.air, tostring(acrossLock.kind), tostring(acrossLock.lockedInAir), acrossLock.air, acrossLock.after, tostring(acrossLock.hit)))
	truthy(early.kind ~= nil and early.peak >= 6, "set-up: a hazard came, and the jump lifted the root a layer (" .. string.format("%.2f", early.peak) .. ")")
	truthy(early.air <= 0.2, string.format("a jump does not lift the shadow off the floor (worst %.2f studs off)", early.air))
	truthy(acrossLock.kind ~= nil and acrossLock.lockedInAir, "set-up: the second jump spanned the lock (" .. tostring(acrossLock.kind) .. ")")
	truthy(acrossLock.air <= 0.2 and acrossLock.after <= 0.2, string.format(
		"a lock during a jump leaves the shadow on the floor, in the air and after landing (worst %.2f / %.2f studs off)", acrossLock.air, acrossLock.after))
	truthy(acrossLock.hit, "…where it still lands on a miner who came back down in it")
	Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = oldMin, oldMax
	-- let the next roll happen on the real interval: one more hazard with the real numbers restored
	work(12, 1 / 15, function()
		if hum.PlatformStand then
			for _ = 1, 30 do workFrame(1 / 15) if not hum.PlatformStand then break end end
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
	end)
end

--======================================================================= 6. rest: the cave leaves you alone, and it cannot be toggled

local function chipResting() return string.find(chip.Text, "Resting", 1, true) ~= nil end
local function chipIdle() return string.find(chip.Text, "Idle", 1, true) ~= nil end
do
	local p = bands[EnvBands.indexOf(bands, "magma")].from + 2
	standDepth(p)
	clickEvery = 1.0
	-- mine until a hazard has come and gone, so the clock position is known
	local lastHazardClock, miningClock = nil, 0
	local shownBefore = false
	local function track()
		if not (chipResting() or chipIdle()) then miningClock += 1 / 15 end
		local k = hazardShown()
		if k and not shownBefore then lastHazardClock = miningClock end
		shownBefore = k ~= nil
		if hum.PlatformStand then
			for _ = 1, 30 do workFrame(1 / 15) if not hum.PlatformStand then break end end
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			standDepth(p)
		end
	end
	work(200, 1 / 15, function()
		track()
		if lastHazardClock and not hazardShown() and not warningLabel.Visible then return false end
	end)
	truthy(lastHazardClock ~= nil, "set-up: a hazard came while mining in the magma")
	-- stop swinging for 2 s (a rest starts only after SettleSeconds of stillness), then press Rest
	clickEvery = nil
	work(2, 1 / 15, function() track() end)
	restBtn.Activated:Fire()
	work(0.2, 1 / 15, function() track() end)
	truthy(chipResting(), "pressing Rest sits the miner down: the chip says the cave leaves them alone (" .. chip.Text .. ")")
	eq(hum.Sit, true, "the character sits")
	eq(Lighting:FindFirstChild("CaveRestFocus") and Lighting.CaveRestFocus.Enabled, true, "the view softens")
	truthy(folder:FindFirstChild("RestLantern") ~= nil, "a lantern is set down beside them")
	do
		local lantern = folder:FindFirstChild("RestLantern")
		local floorY = origin.Y + Mine.floorY(Config, math.floor(p))
		local bottom = if lantern then lantern.Position.Y - lantern.Size.Y / 2 else math.huge
		truthy(math.abs(bottom - floorY) <= 0.2, string.format("…standing on the floor of their cell (%.2f studs off)", bottom - floorY))
	end
	eq(restBtn.Text, "▶ Mine", "the button says how to carry on")
	-- ten minutes of rest: nothing comes
	local restSpawns = 0
	local sb = false
	run(10 * 60, 1 / 15, function()
		local k = hazardShown()
		if k and not sb then restSpawns += 1 end
		sb = k ~= nil
	end)
	eq(restSpawns, 0, "ten minutes resting: no hazard")
	truthy(chipResting(), "and still resting (the miner did nothing)")
	-- a swing wakes them
	click()
	work(0.2, 1 / 15, function() track() end)
	truthy(not chipResting(), "a swing (a click on the world) wakes the miner (" .. chip.Text .. ")")
	eq(hum.Sit, false, "they stand up")
	eq(folder:FindFirstChild("RestLantern"), nil, "the lantern is put away")
	-- the clock was frozen, not reset: the next hazard comes 120-180 MINING seconds after the last one
	local before = lastHazardClock
	local nextClock = nil
	clickEvery = 1.0
	shownBefore = false
	work(300, 1 / 15, function()
		if not (chipResting() or chipIdle()) then miningClock += 1 / 15 end
		local k = hazardShown()
		if k and not shownBefore and nextClock == nil then nextClock = miningClock end
		shownBefore = k ~= nil
		if nextClock then return false end
	end)
	local gap = if nextClock and before then nextClock - before else nil
	truthy(gap ~= nil and gap >= Config.Hazards.IntervalMin - 1 and gap <= Config.Hazards.IntervalMax + 1,
		string.format("after a ten-minute rest the next hazard came %s mining seconds after the previous one (clock frozen, not reset)",
			tostring(gap and math.floor(gap + 0.5))))
	work(8, 1 / 15, function() track() end)
end

do
	-- right after waking, a rest is QUEUED (MinAwakeSeconds), and a swing drops it
	local p = bands[EnvBands.indexOf(bands, "magma")].from + 2
	standDepth(p)
	clickEvery = nil
	work(2, 1 / 15)
	restBtn.Activated:Fire()
	work(0.5, 1 / 15)
	truthy(chipResting(), "set-up: resting")
	click()
	work(0.2, 1 / 15)
	restBtn.Activated:Fire()
	work(0.2, 1 / 15)
	eq(restBtn.Text, "⛺ …", "a rest asked for right after waking is queued (" .. restBtn.Text .. ")")
	truthy(not chipResting(), "…not granted")
	local startedAfter = nil
	local t = 0
	work(12, 1 / 15, function()
		t += 1 / 15
		if chipResting() and startedAfter == nil then startedAfter = t end
	end)
	truthy(startedAfter ~= nil and startedAfter >= Config.Rest.MinAwakeSeconds - 0.5,
		"…and starts once the miner has been awake MinAwakeSeconds (" .. tostring(startedAfter and string.format("%.1f", startedAfter)) .. " s)")
	click()
	work(0.2, 1 / 15)

	-- the toggler: swing, press Rest, swing, press Rest, for a minute
	local rested = 0
	local t2 = 0
	work(60, 1 / 15, function()
		t2 += 1 / 15
		if t2 >= 0.5 then
			t2 = 0
			click()
			workFrame(1 / 15)
			restBtn.Activated:Fire()
		end
		if chipResting() then rested += 1 end
	end)
	eq(rested, 0, "a miner who swings and presses Rest between every swing never rests at all")
	-- the toggler's last press is still queued; a swing a moment later drops it
	work(0.5, 1 / 15)
	click()
	work(0.5, 1 / 15)
	if chipResting() then click() work(0.5, 1 / 15) end
	eq(restBtn.Text, "⛺ Rest", "set-up: no rest queued before the idle test")

	-- idle: no swing and no step for IdleSeconds
	clickEvery = nil
	local idleAt = nil
	local t3 = 0
	work(30, 1 / 15, function()
		t3 += 1 / 15
		if chipIdle() and idleAt == nil then idleAt = t3 end
	end)
	truthy(idleAt ~= nil and math.abs(idleAt - Config.Rest.IdleSeconds) < 1,
		"standing still (no swing, no step) for IdleSeconds rests the miner too, AFK-safe (" .. tostring(idleAt) .. " s)")
	eq(hum.Sit, false, "idle rest does not sit the character down")
	click()
	work(0.2, 1 / 15)
	truthy(not chipIdle(), "a swing ends idle rest")
end

do
	-- not a panic button: with a hazard on its way, Rest is queued and the hazard still lands
	local p = bands[EnvBands.indexOf(bands, "magma")].from + 2
	standDepth(p)
	clickEvery = 1.0
	local warned = false
	work(200, 1 / 15, function()
		if warningLabel.Visible and not string.find(warningLabel.Text, "MOVE!", 1, true) then warned = true return false end
		if hum.PlatformStand then
			for _ = 1, 30 do workFrame(1 / 15) if not hum.PlatformStand then break end end
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			standDepth(p)
		end
	end)
	truthy(warned, "set-up: a hazard is on its way (" .. warningLabel.Text .. ")")
	clickEvery = nil
	restBtn.Activated:Fire()
	local restedDuring, hit = false, false
	work(6, 1 / 15, function()
		if hazardShown() and chipResting() then restedDuring = true end
		if hum.PlatformStand then hit = true end
	end)
	eq(restedDuring, false, "Rest pressed with a hazard inbound does not start while it is in flight")
	truthy(hit, "and the hazard still lands on a miner who did not move")
	work(2, 1 / 15)
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	truthy(not chipResting(), "the hit voided the request")
end

do
	-- on a phone a swing is a TAP on a block; a finger dragged across the screen turns the camera and is
	-- not a swing, so it must not wake a resting miner
	local p = bands[EnvBands.indexOf(bands, "river")].from + 1
	standDepth(p)
	clickEvery = nil
	work(8, 1 / 15)
	if not chipResting() then
		restBtn.Activated:Fire()
		work(0.5, 1 / 15)
	end
	truthy(chipResting(), "set-up: resting")
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown }, false)
	work(0.5, 1 / 15)
	truthy(chipResting(), "a finger starting a camera drag does not wake the miner")
	UIS.TouchTap:Fire({ Vector2.new(400, 300) }, false)
	work(0.3, 1 / 15)
	truthy(not chipResting(), "a tap on the world (a swing on a phone) wakes them")
	UIS.TouchTap:Fire({ Vector2.new(400, 300) }, true)
	work(0.1, 1 / 15)
end

--======================================================================= 7. critters fly only where the miner has been

do
	local river = bands[EnvBands.indexOf(bands, "river")]
	local p = river.from + 2
	clickEvery = 1.0
	-- arrive by a ride (a jump of more than a cell resets the trail), then walk two cells
	standAt(0)
	work(0.5, 1 / 30)
	standDepth(p)
	work(4, 1 / 30)
	standDepth(p, C + 1, C)
	work(4, 1 / 30)
	local outside, checked = 0, 0
	local layer = math.floor(p)
	local open = {}
	for _, x in { C, C + 1 } do
		local lp = Mine.localPos(Config, x, layer, C)
		table.insert(open, origin + Vector3.new(lp.x, lp.y, lp.z))
	end
	work(30, 1 / 30, function()
		for _, d in folder:GetChildren() do
			if string.match(d.Name, "^Critter_") then
				checked += 1
				local inside = false
				for _, c in open do
					local r = d.Position - c
					if math.abs(r.X) <= S / 2 and math.abs(r.Y) <= S / 2 and math.abs(r.Z) <= S / 2 then inside = true end
				end
				if not inside then outside += 1 end
			end
		end
	end)
	truthy(checked > 100, "set-up: bats were out over the river (" .. checked .. " samples)")
	eq(outside, 0, "every critter stayed inside the two cells the miner walked through (never inside rock)")
end

--======================================================================= 8. what the client touched, and what it did not

auditLocalParts("at the end")
do
	local changed, gone = 0, 0
	for part, was in serverLook do
		if part.Parent ~= nil then
			if part.Color ~= was[1] or part.Material ~= was[2] or part.Transparency ~= was[3] or part.Size ~= was[4]
				or part.CanCollide ~= was[5] or part.CanQuery ~= was[6] or part:GetAttribute("CellKey") ~= was[7] then
				changed += 1
			end
		else
			gone += 1
		end
	end
	eq(changed, 0, "the client changed nothing the server built (colour, material, size, collision, attributes)")
	local newWs = {}
	for _, c in h.workspace:GetChildren() do
		if not workspaceBefore[c] and c ~= plr.Character then table.insert(newWs, c.Name) end
	end
	table.sort(newWs)
	eq(table.concat(newWs, ","), "DeepVeinLocalCave", "the client added exactly one thing to the workspace: its own folder")
	local newRs = 0
	for _, c in RS:GetDescendants() do if not rsBefore[c] then newRs += 1 end end
	eq(newRs, 0, "and nothing to ReplicatedStorage")
	local newLighting = {}
	for _, c in Lighting:GetChildren() do
		if lightingBefore[c.Name] == nil then table.insert(newLighting, c.Name) end
	end
	table.sort(newLighting)
	eq(table.concat(newLighting, ","), "CaveRestFocus,FxSunRays", "in Lighting it added only its rest focus and the surface's sun rays")
	eq(serverCalls, expectedCalls, "the client fired no remote (only this file's own elevator presses reached the server)")
end

--======================================================================= 9. the strata row never lands on the HUD

do
	-- check_deepvein_cave_hud.luau runs the repo's HUD gate over both scripts (off screen, tap size,
	-- touch bands, panel overlap). That gate only compares PANELS with each other; the chip and the
	-- button are a label and a button, so this compares them with every piece of the HUD at the top
	-- level (readout, hint, toast, shop, board, elevator, drawer toggles), at the same ten viewports,
	-- and the warning banner too, as if it were showing.
	local VIEWPORTS = require("./emu/hudcheck").VIEWPORTS
	local hudGui = plr.PlayerGui:FindFirstChild("DeepVeinHud")
	local bad, checked, drawerChecked = 0, 0, 0
	for _, v in VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.1)
		frame(1 / 30)
		local mine = {}
		for _, r in h:guiRects(caveGui, v.w, v.h) do
			if r.obj == chip or r.obj == restBtn or r.obj == warningLabel then
				if r.obj ~= warningLabel then
					truthy(r.shown, v.name .. ": " .. r.name .. " is showing (no HUD drawer is open)")
				end
				table.insert(mine, r)
			end
		end
		eq(#mine, 3, v.name .. ": chip, button and warning were measured")
		truthy(warningLabel.Size.X.Offset >= 200, string.format("%s: the hazard banner is wide enough to read (%d design px)", v.name,
			warningLabel.Size.X.Offset))
		local hudRoot = hudGui:FindFirstChild("Root")
		for _, r in h:guiRects(hudGui, v.w, v.h) do
			if r.obj ~= nil and r.obj.Parent == hudRoot and r.shown and r.sw > 0 and r.sh > 0 then
				for _, m in mine do
					checked += 1
					local ox = math.min(m.sx + m.sw, r.sx + r.sw) - math.max(m.sx, r.sx)
					local oy = math.min(m.sy + m.sh, r.sy + r.sh) - math.max(m.sy, r.sy)
					if ox > 1 and oy > 1 then
						bad += 1
						print(string.format("  %s: %s (x %.0f..%.0f y %.0f..%.0f) overlaps the HUD's %s (x %.0f..%.0f y %.0f..%.0f)",
							v.name, m.name, m.sx, m.sx + m.sw, m.sy, m.sy + m.sh, r.name, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh))
					end
				end
			end
		end
		-- A phone drawer (the shop on the left, the top-10 on the right) opens where the row sits. Review
		-- 2026-09-24, finding 3: the row used to HIDE, so a phone player shopping underground never saw the
		-- hazard banner or the Rest button. It steps into the side the drawer leaves free instead: shown,
		-- and overlapping nothing, the open drawer included.
		local toggles = hudRoot:FindFirstChild("Toggles")
		if toggles and toggles.Visible then
			for _, want in { "Shop", "Top" } do
				local toggle = nil
				for _, c in toggles:GetChildren() do
					if c.ClassName == "TextButton" and string.find(c.Text, want, 1, true) then toggle = c end
				end
				truthy(toggle ~= nil, v.name .. ": set-up: the " .. want .. " drawer toggle exists")
				if toggle then
					toggle.Activated:Fire()
					h:advance(0.05)
					frame(1 / 30)
					drawerChecked += 1
					local rects = {}
					for _, r in h:guiRects(caveGui, v.w, v.h) do
						if r.obj == chip or r.obj == restBtn or r.obj == warningLabel then
							if r.obj ~= warningLabel then
								truthy(r.shown, v.name .. ", " .. want .. " drawer open: " .. r.name .. " is still showing")
							end
							table.insert(rects, r)
						end
					end
					eq(#rects, 3, v.name .. ", " .. want .. " drawer open: chip, button and warning were measured")
					truthy(warningLabel.Size.X.Offset >= 200, string.format("%s, %s drawer open: the banner stays wide enough to read (%d design px)",
						v.name, want, warningLabel.Size.X.Offset))
					local drawerSeen = false
					for _, r in h:guiRects(hudGui, v.w, v.h) do
						if r.obj ~= nil and r.obj.Parent == hudRoot and r.shown and r.sw > 0 and r.sh > 0 then
							if r.obj.Name == "ShopPanel" or r.obj.Name == "Board" then drawerSeen = true end
							for _, m in rects do
								checked += 1
								local ox = math.min(m.sx + m.sw, r.sx + r.sw) - math.max(m.sx, r.sx)
								local oy = math.min(m.sy + m.sh, r.sy + r.sh) - math.max(m.sy, r.sy)
								if ox > 1 and oy > 1 then
									bad += 1
									print(string.format("  %s, %s drawer open: %s (x %.0f..%.0f y %.0f..%.0f) overlaps the HUD's %s (x %.0f..%.0f y %.0f..%.0f)",
										v.name, want, m.name, m.sx, m.sx + m.sw, m.sy, m.sy + m.sh, r.name, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh))
								end
							end
						end
					end
					truthy(drawerSeen, v.name .. ": set-up: the " .. want .. " drawer is open and was compared")
					toggle.Activated:Fire()
					h:advance(0.05)
					frame(1 / 30)
					eq(chip.Visible, true, v.name .. ": " .. want .. " drawer shut: the chip is back")
				end
			end
		end
	end
	truthy(checked > 100, "set-up: HUD pieces compared (" .. checked .. ")")
	truthy(drawerChecked >= 6, "set-up: a phone drawer was opened over the row at every phone viewport (" .. drawerChecked .. ")")
	eq(bad, 0, "the band chip, the Rest button and the warning never overlap any piece of the HUD, drawers open or shut, at all ten viewports")

	-- …and live: a phone, the shop open underground, a hazard inbound. The reviewer measured 0 of 95 frames
	-- with the banner; the ring alone was left, under the drawer's edge.
	h:setTouch(true)
	h:setViewport(800, 360)
	h:advance(0.1)
	frame(1 / 30)
	local shopToggle = nil
	for _, c in hudGui:FindFirstChild("Root"):FindFirstChild("Toggles"):GetChildren() do
		if c.ClassName == "TextButton" and string.find(c.Text, "Shop", 1, true) then shopToggle = c end
	end
	shopToggle.Activated:Fire()
	h:advance(0.05)
	local oldMin, oldMax = Config.Hazards.IntervalMin, Config.Hazards.IntervalMax
	Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 8, 10
	clickEvery = 1.0
	standAt(PIT + 1)
	local hazardFrames, bannerFrames, restShown, seen = 0, 0, 0, false
	-- the scheduler's next roll was made on the real interval (120-180 s): wait for it, then the warning
	work(200, 1 / 30, function()
		local k = hazardShown()
		local d = folder:FindFirstChild("HazardShadow")
		if k and d and d.Transparency < 1 and not hum.PlatformStand then
			seen = true
			hazardFrames += 1
			if warningLabel.Visible then bannerFrames += 1 end
			if restBtn.Visible then restShown += 1 end
		end
		if seen and k == nil and not hum.PlatformStand then return false end
	end)
	for _ = 1, 40 do
		if not hum.PlatformStand then break end
		frame(1 / 30)
	end
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = oldMin, oldMax
	local shopOpen = hudGui:FindFirstChild("Root"):FindFirstChild("ShopPanel").Visible
	print(string.format("  a phone with the shop open, a hazard inbound: banner on %d of %d warning frames, Rest button on %d", bannerFrames,
		hazardFrames, restShown))
	truthy(shopOpen and hazardFrames >= 30, "set-up: a hazard's warning ran with the shop drawer open (" .. hazardFrames .. " frames)")
	eq(bannerFrames, hazardFrames, "a phone player in the shop sees the hazard banner for the whole warning")
	eq(restShown, hazardFrames, "…and can still reach the Rest button")
	shopToggle.Activated:Fire()
	h:advance(0.05)
	h:setTouch(false)
	h:setViewport(1280, 720)
	h:advance(0.1)
end

--======================================================================= 10. the brag: the stratum next to every depth on the HUD

do
	-- the readout's best depth and every top-10 row carry the emoji of the stratum that depth reaches,
	-- read from the same band table (a depth in m is a layer x 6)
	local hudRoot = plr.PlayerGui:FindFirstChild("DeepVeinHud"):FindFirstChild("Root")
	local readout = hudRoot:FindFirstChild("Readout")
	local depthText = nil
	for _, d in readout:GetDescendants() do
		if d.ClassName == "TextLabel" and string.find(d.Text, "best", 1, true) then depthText = d.Text end
	end
	local core = bands[#bands]
	local bestM = Mine.depthStuds(Config, Mine.maxLayer(Config, VET_REBIRTHS))
	truthy(depthText ~= nil and string.find(depthText, string.format("best %dm %s", bestM, core.emoji), 1, true) ~= nil,
		"the readout shows the veteran's best with the core's emoji (" .. tostring(depthText) .. ")")
	local LeaderboardEvent = remotes:FindFirstChild("Leaderboard")
	local magma = bands[EnvBands.indexOf(bands, "magma")]
	-- The server pushes its own top-10 every 30 s; one landing between this push and the read replaced these rows
	-- (a rare flake, review round). The read retries the push if the server's board is what arrived.
	local rows = {}
	local board = hudRoot:FindFirstChild("Board")
	for _ = 1, 3 do
		LeaderboardEvent:FireClient(plr, {
			{ userId = 111, depth = 40 * S },
			{ userId = 222, depth = 17 * S },
			{ userId = 333, depth = 150 * S },
		})
		h:advance(0.05)
		rows = {}
		for _, d in board:GetDescendants() do
			if d.ClassName == "TextLabel" and string.match(d.Text, "^%d+%.") then rows[tonumber(string.match(d.Text, "^(%d+)%."))] = d.Text end
		end
		if rows[1] and string.find(rows[1], "240m", 1, true) then break end
	end
	local river = bands[EnvBands.indexAt(bands, 17)]
	truthy(rows[1] and string.sub(rows[1], -#magma.emoji) == magma.emoji, "row 1 (240 m) ends in the magma's emoji (" .. tostring(rows[1]) .. ")")
	truthy(rows[2] and string.sub(rows[2], -#river.emoji) == river.emoji, "row 2 (102 m, layer 17) ends in its stratum's emoji (" .. tostring(rows[2]) .. ")")
	truthy(rows[3] and string.sub(rows[3], -#core.emoji) == core.emoji, "row 3 (900 m) ends in the core's emoji (" .. tostring(rows[3]) .. ")")
end

--======================================================================= budgets

print(string.format("  PEAK over the whole run: parts %d (%s), emitters %d (%s), particles/s %.1f (%s), lights %d (%s), beams %d, trails %d, hazards %d",
	peak.parts, tostring(peakWhere.parts), peak.emitters, tostring(peakWhere.emitters), peak.rate, tostring(peakWhere.rate),
	peak.lights, tostring(peakWhere.lights), peak.beams, peak.trails, peak.hazards))
truthy(peak.parts <= Budget.MaxLocalParts, "local parts within budget (" .. peak.parts .. " <= " .. Budget.MaxLocalParts .. ")")
truthy(peak.emitters <= Budget.MaxEmitters, "emitters within budget (" .. peak.emitters .. " <= " .. Budget.MaxEmitters .. ")")
truthy(peak.rate <= Budget.MaxEmitterRate, "particles per second within budget, a hazard trickle included ("
	.. peak.rate .. ")")
truthy(peak.lights <= Budget.MaxLights, "point lights within budget (" .. peak.lights .. " <= " .. Budget.MaxLights .. ")")
truthy(peak.beams <= Budget.MaxBeams and peak.trails <= Budget.MaxTrails, "beams and trails within budget")
eq(peak.hazards, Budget.MaxHazards, "one hazard model at a time, at most")


print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein cave: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein cave check failed", 0)
end
