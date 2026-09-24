-- Steal a Cryptid - THE NIGHT, driven through the REAL server and the REAL client scripts.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_night.luau 2>&1
--
-- The pure rules (bands, floor, gate, habitats) are unit-tested in steal-a-cryptid/tests. This file
-- checks the GLUE no unit test can see, against what the client actually writes:
--   1. the take-over at join glides from the server's v1 lighting to the player's band, never through
--      daylight and never below the readability floor;
--   2. the home sky follows the Journal's rank as the REAL server reports it after REAL purchases at the
--      pedestals (Common -> Rare -> Legendary -> Mythic), gliding, with a title card per new band;
--   3. each camp tier, entered with the real Hunt remote from the real board, gets its own place: its
--      lighting on every frame is readable, no depth of field, and no local part (scenery, critter,
--      weather host) ever enters the camp or the camera's corridor behind the gate; leaving glides home;
--   4. your own occupied cages get habitat patches sitting on the server's cage bases, the rarest one
--      lit; a released cryptid's habitat goes; another player's lair is never dressed;
--   5. budgets (parts, emitters, particles/s, beams, trails, lights) at every band, every camp and on
--      every frame of every seam;
--   6. leaks: the client fires no remote, sets no attribute, and everything it builds is local,
--      anchored and non-collidable, non-queryable, non-touchable.
-- Headless limits: nothing renders, there is no physics; frames are RenderStepped fired by this file.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local EnvBands = require("../steal-a-cryptid/src/shared/EnvBands")
local Night = require("../steal-a-cryptid/src/shared/Night")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-night", viewport = { 1280, 720 }, touch = false })

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
local W = Config.World
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)

local function cagesWith(fill)
	local out = {}
	for i = 1, 9 do out[i] = { sp = "", jar = 0 } end
	for col, sp in fill do out[col] = { sp = sp, jar = 0 } end
	return out
end
local function profile(essence, journal, fill)
	return { data = { v = 1, essence = essence, savedAt = NOW, cagesUnlocked = 9, tutorial = 4, cages = cagesWith(fill),
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = journal,
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } }
end
local ME, OTHER = 7707, 7708
store:SetAsync("u_" .. ME, profile(10000000, { "jackalope" }, { [5] = "jackalope" }))
store:SetAsync("u_" .. OTHER, profile(0, { "bigfoot" }, { [5] = "bigfoot", [4] = "nessie" }))

--============================================================ boot: server, a neighbour, then me with both client scripts

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Lighting = h.Lighting
local v1 = { clock = Lighting.ClockTime, density = Lighting:FindFirstChild("FxAtmosphere").Density }

local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local serverCalls, ownCalls = 0, 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end
local function fireServer(name, plr, ...)
	ownCalls += 1
	remotes:FindFirstChild(name):simulateFireServer(plr, ...)
end

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

-- ROUTING. The emulator's RemoteEvent:FireClient records the target player but fires OnClientEvent
-- for every listener, so with two players in the server the one client under test would hear the
-- neighbour's State too (its rank, its cages). Roblox delivers a FireClient to that player's client
-- only. This shim (in this file, emu/ untouched) makes each remote's OnClientEvent deliver only what
-- was sent to Players.LocalPlayer or to all, which is what the real client would receive.
do
	for _, r in remotes:GetChildren() do
		if r.ClassName == "RemoteEvent" then
			local sig = h.instance.getSignal(r, "OnClientEvent")
			local fire = getmetatable(sig).Fire
			sig.Fire = function(self, ...)
				local sent = r:getSent()
				local rec = sent[#sent]
				if rec and not rec.all and rec.player ~= h.Players.LocalPlayer then return end
				return fire(self, ...)
			end
		end
	end
end

local other = h:join("Neighbour", OTHER)
h.Players:simulateSpawn(other, h.workspace)
local plr = h:join("Nightwatcher", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okNight, errNight = h:tryRun("client/Night.client")
truthy(okNight, "Night.client loads (" .. tostring(errNight) .. ")")
if not okNight then
	print(string.format("steal a cryptid night: %d passed, %d failed", passed, failed))
	error("Night.client did not load", 0)
end

local folder = h.workspace:FindFirstChild("CryptidNight")
truthy(folder ~= nil, "the client made its local folder workspace.CryptidNight")
local nightGui = plr.PlayerGui:FindFirstChild("CryptidNight")
local card = nightGui and nightGui:FindFirstChild("Root") and nightGui.Root:FindFirstChild("Card")
truthy(card ~= nil, "the client made its title card")

--============================================================ frames, measurement

local cam = h.workspace.CurrentCamera
local remState = remotes:FindFirstChild("State")
local function st()
	local sent = remState:sentTo(plr)
	return sent[#sent].args[1]
end

local cards = {}
local lastCard = ""
local budget = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0 }
local budgetWhere = {}
local unreadable, daylight, dofInCamp, keepOutHits = {}, 0, 0, {}
local camera = "behind" -- behind the root, looking the way the raider faces (+z) in a camp
local sceneNow = "home"

local function color(c) return { c.R * 255, c.G * 255, c.B * 255 } end
local function readGroups()
	local atm = Lighting:FindFirstChild("FxAtmosphere")
	local bloom = Lighting:FindFirstChild("FxBloom")
	local cc = Lighting:FindFirstChild("FxColorCorrection")
	return {
		lighting = { Brightness = Lighting.Brightness, ExposureCompensation = Lighting.ExposureCompensation,
			FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd, Ambient = color(Lighting.Ambient),
			OutdoorAmbient = color(Lighting.OutdoorAmbient), ClockTime = Lighting.ClockTime },
		atmosphere = { Density = atm and atm.Density, Haze = atm and atm.Haze },
		bloom = { Threshold = bloom and bloom.Threshold },
		colorCorrection = { Saturation = cc and cc.Saturation, Brightness = cc and cc.Brightness },
	}
end

local function measure(where)
	local parts, emitters, rate, beams, trails, lights = 0, 0, 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			parts += 1
		elseif cls == "ParticleEmitter" and d.Enabled then
			emitters += 1
			rate += d.Rate or 0
		elseif cls == "Beam" and d.Enabled then
			beams += 1
		elseif cls == "Trail" and d.Enabled then
			trails += 1
		elseif (cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight") and d.Enabled then
			lights += 1
		end
	end
	local m = { parts = parts, emitters = emitters, rate = rate, beams = beams, trails = trails, lights = lights }
	for k, v in m do
		if v > budget[k] then budget[k] = v; budgetWhere[k] = where end
	end
	return m
end

-- pocket-local keep-out: every parented local part's footprint circle must be clear of it
local function checkKeepOut(where)
	local x = hrp.Position.X
	local slot = Night.pocketSlot(Config, x)
	if slot == nil then return end
	local ox = Night.pocketOriginX(Config, slot)
	for _, d in folder:GetDescendants() do
		if (d.ClassName == "Part" or d.ClassName == "WedgePart") then
			local p = d.Position
			-- the part's world-aligned footprint (a rotated trunk's length is its height, not its reach)
			local cf, s = d.CFrame, d.Size
			local rx, uy, lz = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = math.abs(rx.X) * s.X / 2 + math.abs(uy.X) * s.Y / 2 + math.abs(lz.X) * s.Z / 2
			local ey = math.abs(rx.Y) * s.X / 2 + math.abs(uy.Y) * s.Y / 2 + math.abs(lz.Y) * s.Z / 2
			local ez = math.abs(rx.Z) * s.X / 2 + math.abs(uy.Z) * s.Y / 2 + math.abs(lz.Z) * s.Z / 2
			local lx = p.X - ox
			-- a part wholly under the camp's floor (its ground, the loch) can hide nothing; anything else
			-- near this pocket must keep its footprint out of the camp and the camera corridor
			if p.Y + ey > -1.0 and math.abs(lx - 36) < 1500 and not Night.boxClearOfCamp(Config, lx - ex, lx + ex, p.Z - ez, p.Z + ez) then
				local key = d.Name
				if keepOutHits[key] == nil then
					keepOutHits[key] = string.format("%s at pocket-local (%.1f, %.1f) half %.1f x %.1f (%s)", d.Name, lx, p.Z, ex, ez, where)
				end
			end
		end
	end
end

local simTime = 0
local function frame(dt, where)
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 10, -24), p)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	if card and card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
	local g = readGroups()
	local ok, why = Night.readable(Config, g)
	if not ok and #unreadable < 5 then table.insert(unreadable, string.format("t=%.2f %s: %s", simTime, where or "?", tostring(why))) end
	local c = Lighting.ClockTime
	if c > 6.001 and c < 17.499 then daylight += 1 end
	if Night.pocketSlot(Config, p.X) ~= nil then
		local dof = Lighting:FindFirstChild("CryptidRestFocus")
		if dof and dof.Enabled then dofInCamp += 1 end
		checkKeepOut(where or "?")
	end
	measure(where or "?")
end
local function run(seconds, where)
	local n = math.floor(seconds * 30 + 0.5)
	for _ = 1, n do frame(1 / 30, where) end
end

local function shown(prefix)
	local n = 0
	for _, d in folder:GetDescendants() do
		if (d.ClassName == "Part" or d.ClassName == "WedgePart") and string.sub(d.Name, 1, #prefix) == prefix then n += 1 end
	end
	return n
end

-- the first part name each piece builds (NightArt): a piece is shown when any of its parts is parented
local PIECE_PART = {
	farGround = "FarGround", ridges = "Ridge", farPines = "FarPine", owls = "Owl", auroraGreen = "AuroraGreenHost",
	auroraGold = "AuroraGoldHost", ufos = "Ufo", bigfoot = "Bigfoot_", campSand = "CampSand", mesas = "Mesa",
	cacti = "Cactus", campNeedles = "CampNeedles", pineRing = "RingPine", campShore = "CampShore", loch = "LochWater",
	castle = "Castle", nessie = "Nessie", campFerns = "CampFerns", redwoods = "Redwood", bigfootGlimpse = "Glimpse",
}
for _, list in { N.Home, N.Camp } do
	for _, b in list do
		for _, id in b.pieces do truthy(PIECE_PART[id] ~= nil, "this check knows piece " .. id) end
	end
end

local bandRows = {}
local function atBand(b, where)
	local m = measure(where)
	table.insert(bandRows, string.format("    %-26s parts %3d  emitters %d (%4.1f/s)  beams %d  trails %d  lights %d", where, m.parts, m.emitters, m.rate, m.beams, m.trails, m.lights))
	near(Night.clockTime(b.lighting.ClockTime), Lighting.ClockTime, 0.05, where .. ": Lighting.ClockTime reached the band's night hour")
	near(Lighting:FindFirstChild("FxAtmosphere").Density, b.atmosphere.Density, 0.01, where .. ": FxAtmosphere.Density reached the band's")
	near(Lighting.Brightness, b.lighting.Brightness, 0.02, where .. ": Brightness reached the band's")
	local sky = Lighting:FindFirstChild("CryptidSky")
	near(sky and sky.StarCount, b.sky.StarCount, 2, where .. ": CryptidSky.StarCount reached the band's")
	for _, id in b.pieces do
		truthy(shown(PIECE_PART[id]) > 0, where .. ": piece " .. id .. " is shown")
	end
end
local function notShown(ids, where)
	for _, id in ids do
		eq(shown(PIECE_PART[id]), 0, where .. ": piece " .. id .. " is not shown (unparented)")
	end
end
local function piecesOf(list, except)
	local out, seen = {}, {}
	for _, b in list do
		for _, id in b.pieces do
			if not seen[id] and not (except and table.find(except.pieces, id)) then seen[id] = true; table.insert(out, id) end
		end
	end
	return out
end

--============================================================ 1. the take-over at join

run(0.2, "join")
near(Lighting.ClockTime, v1.clock, 0.6, "the first frames still show the server's ClockTime (a glide, no cut)")
run(8, "join")
local dusk = N.Home[1]
eq(st().rank, 1, "the server reports rank 1 (a Jackalope in the Journal)")
eq(st().plot ~= nil, true, "the server reports the owner's plot")
atBand(dusk, "rank 1 dusk")
notShown(piecesOf(N.Home, dusk), "rank 1 dusk")
notShown(piecesOf(N.Camp), "rank 1 dusk")
eq(daylight, 0, "the glide from v1's midnight to dusk showed no daylight frame")
truthy(#cards >= 1 and string.find(cards[1], string.upper(dusk.name), 1, true) ~= nil, "the first card names the band (" .. tostring(cards[1]) .. ")")
truthy(Lighting:FindFirstChild("FxAtmosphere") ~= nil and #Lighting:GetChildren() > 0, "the client reused the server's Atmosphere")
do
	local n = 0
	for _, c in Lighting:GetChildren() do if c.ClassName == "Atmosphere" then n += 1 end end
	eq(n, 1, "exactly one Atmosphere (the client took over FxAtmosphere, it did not stack a second)")
end

--============================================================ helpers: my lair

local plotIndex = st().plot
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. plotIndex)
local lair = plot:FindFirstChild("Lair")
truthy(string.find(plot.Sign.Label.Text.Text, plr.Name, 1, true) ~= nil, "State.plot is the plot whose sign carries my name")
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local function apron(x, z) return frameCF:PointToWorldSpace(Vector3.new(x, W.RootHeight, z)) end
local function standAt(x, z)
	hrp.CFrame = CFrame.new(apron(x, z))
end

local function buyP3(label)
	local a = W.Apron.P3
	standAt(a.x, a.z - 4)
	local ped = lair.Pedestals:FindFirstChild("Pedestal_3")
	local prompt = ped:FindFirstChild("Buy")
	local d = (hrp.Position - ped.Position).Magnitude
	truthy(d <= prompt.MaxActivationDistance, label .. ": the P3 Buy prompt is in reach (" .. string.format("%.1f", d) .. ")")
	local before = st().rank
	prompt.Triggered:Fire(plr)
	h:advance(0.05)
	return before
end

--============================================================ 2. rank -> band, through real purchases

for i = 2, #N.Home do
	local b = N.Home[i]
	local before = buyP3("rank " .. i)
	local cardsBefore = #cards
	run(0.3, "seam " .. N.Home[i - 1].id .. ">" .. b.id)
	eq(st().rank, i, "buying the next tier's cryptid at P3 raised the Journal's rank " .. before .. " -> " .. i)
	-- the glide: mid-seam the ClockTime is between the two bands (never a cut)
	local cNow = Lighting.ClockTime
	local from, to = Night.clockTime(N.Home[i - 1].lighting.ClockTime), Night.clockTime(b.lighting.ClockTime)
	local fromH, toH = N.Home[i - 1].lighting.ClockTime, b.lighting.ClockTime
	local hNow = if cNow < 12 then cNow + 24 else cNow
	truthy(hNow > fromH + 0.05 and hNow < toH - 0.05, string.format("%s: 0.3 s after the rank rose the night is gliding (%.2f between %.2f and %.2f)", b.id, cNow, from, to))
	run(8, b.id)
	atBand(b, "rank " .. i .. " " .. b.id)
	notShown(piecesOf(N.Home, b), "rank " .. i .. " " .. b.id)
	local sawCard = false
	for k = cardsBefore + 1, #cards do
		if string.find(cards[k], string.upper(b.name), 1, true) then sawCard = true end
	end
	truthy(sawCard, b.id .. ": a title card announced " .. string.upper(b.name))
	run(2.5, b.id) -- the pedestal refills (BuyTweenSeconds) before the next purchase
end
eq(daylight, 0, "no daylight frame through all four home bands")

--============================================================ 4. habitats (before the camps: all four tiers now in my cages)

do
	local s = st()
	local occupied = 0
	for col = 1, 9 do
		local c = s.cages[col]
		local parts = shown("Habitat_" .. col .. "_")
		if c.sp ~= "" then
			occupied += 1
			truthy(parts >= 2, string.format("cage %d (%s) has a habitat (%d parts)", col, c.sp, parts))
			local base = lair.Cages:FindFirstChild("Cage_" .. col)
			local patch = nil
			for _, d in folder:GetDescendants() do
				if d.Name == "Habitat_" .. col .. "_Patch" then patch = d end
			end
			if base and patch then
				near(patch.Position.X, base.Position.X, 0.05, "cage " .. col .. ": the habitat patch sits on the server's cage base (x)")
				near(patch.Position.Z, base.Position.Z, 0.05, "cage " .. col .. ": (z)")
				truthy(patch.Position.Y - patch.Size.Y / 2 >= base.Position.Y + base.Size.Y / 2 - 0.01, "cage " .. col .. ": on top of the base, not inside it")
				truthy(patch.Size.X <= base.Size.X and patch.Size.Z <= base.Size.Z, "cage " .. col .. ": no wider than the base")
			else
				truthy(false, "cage " .. col .. ": found both the server's base and the habitat patch")
			end
		else
			eq(parts, 0, "empty cage " .. col .. " has no habitat")
		end
	end
	eq(occupied, 4, "four cryptids in my cages (jackalope + three bought)")
	-- the lit (particles) habitat is the rarest: the Mythic's
	local lit = {}
	for _, d in folder:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled and d.Parent and string.find(d.Parent.Name, "^Habitat_") then
			table.insert(lit, d.Parent.Name)
		end
	end
	truthy(#lit <= N.Budget.MaxHabitatEmitters, "habitat emitters on: " .. #lit .. " <= " .. N.Budget.MaxHabitatEmitters)
	local mythicCol = nil
	for col = 1, 9 do if s.cages[col].tier == 4 then mythicCol = col end end
	truthy(mythicCol ~= nil and #lit == 1 and string.find(lit[1], "^Habitat_" .. mythicCol .. "_") ~= nil,
		"the one lit habitat is the Mythic's (cage " .. tostring(mythicCol) .. "): " .. table.concat(lit, ","))
	-- the neighbour's lair (a Bigfoot and a Nessie) is never dressed: every habitat part is over MY plot
	local mine = plot.Floor
	local outside = 0
	for _, d in folder:GetDescendants() do
		if (d.ClassName == "Part" or d.ClassName == "WedgePart") and string.find(d.Name, "^Habitat_") then
			local lp = mine.CFrame:PointToObjectSpace(d.Position)
			if math.abs(lp.X) > mine.Size.X / 2 or math.abs(lp.Z) > mine.Size.Z / 2 then outside += 1 end
		end
	end
	eq(outside, 0, "no habitat part outside my own plot (the neighbour's Bigfoot cage stays plain)")
	-- a released cryptid's habitat goes with it (the server's 1 s hold, through the real prompt)
	local col = 5
	local base = lair.Cages:FindFirstChild("Cage_" .. col)
	standAt(36, 80)
	local rel = base:FindFirstChild("Release")
	rel.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Economy.ReleaseHoldSeconds + 0.05)
	rel.Triggered:Fire(plr)
	run(1.5, "release")
	eq(st().cages[col].sp, "", "the Jackalope was released (cage 5 empty)")
	eq(shown("Habitat_" .. col .. "_"), 0, "and its habitat is gone")
end

--============================================================ 3. every camp tier, through the real board

local function enterCamp(tier)
	local b = W.Apron.Board
	standAt(b.x, b.z - 4)
	local cb = #cards
	fireServer("Hunt", plr, tier)
	h:advance(0.05)
	return cb
end

local homeTop = N.Home[#N.Home]
for tier = 1, #Config.Camps do
	local b = N.Camp[tier]
	local cardsBefore = enterCamp(tier)
	truthy(Night.pocketSlot(Config, hrp.Position.X) ~= nil, "camp " .. tier .. ": the server put me in a pocket")
	eq(st().raid and st().raid.tier, tier, "camp " .. tier .. ": the server reports a tier-" .. tier .. " raid")
	run(8, "camp " .. tier)
	atBand(b, "camp " .. tier .. " " .. b.id)
	notShown(piecesOf(N.Home), "camp " .. tier)
	notShown(piecesOf(N.Camp, b), "camp " .. tier)
	eq(#cards, cardsBefore, "camp " .. tier .. ": no title card over a camp (it would cover the nets)")
	fireServer("LeaveCamp", plr)
	h:advance(0.05)
	truthy(Night.pocketSlot(Config, hrp.Position.X) == nil, "camp " .. tier .. ": left, home again")
	run(0.4, "leaving camp " .. tier)
	local hNow = Lighting.ClockTime
	hNow = if hNow < 12 then hNow + 24 else hNow
	truthy(math.abs(hNow - homeTop.lighting.ClockTime) > 0.05, "camp " .. tier .. ": 0.4 s after leaving the night is still gliding home (no cut)")
	run(8, "home after camp " .. tier)
	atBand(homeTop, "home after camp " .. tier)
	notShown(piecesOf(N.Camp), "home after camp " .. tier)
	run(Config.Raid.RestartCooldownSeconds - 0.5, "home")
end
eq(dofInCamp, 0, "no depth of field on any camp frame (DESIGN.md 13)")
do
	local list = {}
	for _, v in keepOutHits do table.insert(list, v) end
	eq(#list, 0, "no local part ever entered a camp or the camera corridor behind its gate" .. (if #list > 0 then ": " .. table.concat(list, "; ") else ""))
end

--============================================================ 5. budgets

local B = N.Budget
print("\n  per band, after 8 s there:")
for _, row in bandRows do print(row) end
print("\n  budget peaks (every frame of this run):")
for _, k in { "parts", "emitters", "rate", "beams", "trails", "lights" } do
	print(string.format("    %-9s %6.1f  at %s", k, budget[k], tostring(budgetWhere[k])))
end
truthy(budget.parts <= B.MaxLocalParts, "local parts peak " .. budget.parts .. " <= " .. B.MaxLocalParts)
truthy(budget.emitters <= B.MaxEmitters, "emitters peak " .. budget.emitters .. " <= " .. B.MaxEmitters)
truthy(budget.rate <= B.MaxEmitterRate + 1e-6, "particles/s peak " .. budget.rate .. " <= " .. B.MaxEmitterRate)
truthy(budget.beams <= B.MaxBeams, "beams peak " .. budget.beams .. " <= " .. B.MaxBeams)
truthy(budget.trails <= B.MaxTrails, "trails peak " .. budget.trails .. " <= " .. B.MaxTrails)
truthy(budget.lights <= B.MaxLights, "lights peak " .. budget.lights .. " <= " .. B.MaxLights)
eq(#unreadable, 0, "every frame written (join, 4 bands, 4 camps, every seam) met the readability floor" .. (if #unreadable > 0 then ": " .. table.concat(unreadable, " | ") else ""))
eq(daylight, 0, "no frame of the whole run showed daylight")

--============================================================ 6. leaks

eq(serverCalls, ownCalls, "the clients fired no remote of their own (" .. serverCalls .. " server events, " .. ownCalls .. " fired by this file)")
do
	local bad = 0
	local first = nil
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local ok = d.Anchored == true and d.CanCollide == false and d.CanQuery == false and d.CanTouch == false and d.CastShadow == false
			if not ok then bad += 1; first = first or d.Name end
		end
	end
	eq(bad, 0, "every local part is anchored, non-collidable, non-queryable, non-touchable, casts no shadow" .. (if first then " (first: " .. first .. ")" else ""))
	local attrs = 0
	local where = nil
	for _, root in { h.workspace, h.ReplicatedStorage } do
		for _, d in root:GetDescendants() do
			if next(d:GetAttributes()) ~= nil then attrs += 1; where = where or d:GetFullName() end
		end
	end
	eq(attrs, 0, "no attribute on any Instance under workspace or ReplicatedStorage" .. (if where then " (first: " .. where .. ")" else ""))
	for _, key in { "client/Night.client", "shared/NightArt", "shared/Night" } do
		local src = bundle[key] and bundle[key].source or ""
		truthy(#src > 0, key .. " is in the bundle")
		for _, bad2 in { "FireServer", "InvokeServer", "SetAttribute", "Instance.new(\"RemoteEvent\")", "Instance.new(\"RemoteFunction\")" } do
			eq(string.find(src, bad2, 1, true), nil, key .. " never calls " .. bad2)
		end
	end
end
for _, e in h:errors() do
	truthy(false, "scheduler error: " .. tostring(e))
end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid night: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid night check failed", 0) end
