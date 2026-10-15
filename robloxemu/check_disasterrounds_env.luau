-- Disaster Rounds - the eye-candy glue, through the real server and the real client scripts.
-- Run: luau check_disasterrounds_env.luau 2>&1   (regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds
-- --out build/disaster-rounds.luau)
--
-- docs/complete-game-standard.md §2 and DESIGN.md §3: the environment changes with the game's own progress (lifetime
-- counted survivals, the server-written `Survived` attribute), never with time; every value glides; the running
-- disaster lays its overlay on top; budgets are measured and capped in code. Here:
--   1. the server's first frame is band 1 (Fx.Presets.Coast == Config.Env.Bands[1]);
--   2. each band, reached by `Survived`, sets its own light, scenery, critters and weather, and the HUD names it;
--   3. a jump across bands glides (no cut); a fade between two bands mixes them;
--   4. each disaster's overlay weighs in over 3 s and out over 3 s;
--   5. budgets at every band, every seam and during every disaster with 8 players at Heat 5;
--   6. nothing the sky builds is red (red means "it hits here").

local SEED = 777
local Datatypes = require("./emu/datatypes")
do
	local realNew = Datatypes.Random.new
	local n = SEED
	Datatypes.Random.new = function(seed)
		if seed == nil then
			n += 1
			return realNew(n * 7919)
		end
		return realNew(seed)
	end
end
local Harness = require("./emu/harness")
local Bot = require("./check_disasterrounds_bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg) truthy(type(a) == "number" and math.abs(a - b) <= tol, msg .. string.format(" (%.3f vs %.3f)", tonumber(a) or -1, b)) end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local bands = Config.Env.Bands
local Lighting = h.Lighting
local B = Config.Budget

--======================================================================= 1. the first frame is band 1

do
	local L = bands[1].lighting
	near(Lighting.ClockTime, L.ClockTime, 1e-6, "the server's first frame: ClockTime is Calm Cove's")
	near(Lighting.Brightness, L.Brightness, 1e-6, "Brightness")
	near(Lighting.FogEnd, L.FogEnd, 1e-6, "FogEnd")
	local fog = Lighting.FogColor
	truthy(math.abs(fog.R * 255 - L.FogColor[1]) < 1 and math.abs(fog.G * 255 - L.FogColor[2]) < 1, "FogColor")
	local atm = Lighting:FindFirstChild("FxAtmosphere")
	near(atm and atm.Density, bands[1].atmosphere.Density, 1e-6, "Atmosphere Density")
	local cc = Lighting:FindFirstChild("FxColorCorrection")
	near(cc and cc.Saturation, bands[1].colorCorrection.Saturation, 1e-6, "ColorCorrection Saturation")
end

--======================================================================= the player and the clients

h.game:GetService("RunService"):setIsServer(false)
local A = h:join("Sky", 801)
local char = h.Players:simulateSpawn(A, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
for _, c in { "client/Hud.client", "client/Sky.client", "client/World.client" } do
	local ok, err = h:tryRun(c)
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local function frames(seconds: number)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		cam.CFrame = CFrame.new(char.HumanoidRootPart.Position + Vector3.new(-12, 8, 0), Vector3.new(0, 0, 0))
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end
local sky = h.workspace:FindFirstChild("DRLocalSky")
local world = h.workspace:FindFirstChild("DRLocalWorld")
local function countClass(root, class: string): number
	local n = 0
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA(class) then n += 1 end
		end
	end
	return n
end
local function sceneryParts(): number
	return countClass(sky and sky:FindFirstChild("Scenery"), "BasePart")
end
local function critters(): number
	local c = sky and sky:FindFirstChild("Critters")
	return if c then #c:GetChildren() else 0
end
local function weatherEmitters(): number
	local host = sky and sky:FindFirstChild("WeatherHost")
	return if host then #host:GetChildren() else 0
end
local function lights(): number
	return countClass(sky, "PointLight") + countClass(world, "PointLight")
end
local bandLabel = function(): string
	local l = A.PlayerGui:FindFirstChild("DRHud"):FindFirstChild("Band", true)
	return if l then l.Text else ""
end

--======================================================================= 2 + 5. every band, and every seam

-- On a break the player is off every roster, so the server neither drops them nor rewrites `Survived` (it writes it
-- at a round's end): the band can be set by hand, as the shots place does from the command bar (EYECANDY.md).
A:SetAttribute("Resting", true)
frames(1)

local worstParts, worstCritters, worstWeather, worstLights = 0, 0, 0, 0
local rows = {}
for i, b in bands do
	A:SetAttribute("Survived", b.from)
	frames(6)
	local L = b.lighting
	near(Lighting.ClockTime, L.ClockTime, 0.05, b.name .. " (" .. b.from .. " survivals): its own ClockTime")
	near(Lighting.Brightness, L.Brightness, 0.05, b.name .. ": its own Brightness")
	local present = 0
	for _, id in b.pieces do
		if sky.Scenery:FindFirstChild(id) then present += 1 end
	end
	eq(present, #b.pieces, b.name .. ": its far scenery is built (" .. table.concat(b.pieces, ", ") .. ")")
	local want = 0
	for _, c in b.critters do want += c.count end
	eq(critters(), math.min(want, B.Critters), b.name .. ": its critters fly")
	truthy(weatherEmitters() >= 1, b.name .. ": its weather falls")
	truthy(string.find(bandLabel(), b.name, 1, true) ~= nil, b.name .. ": the HUD names it (" .. bandLabel() .. ")")
	worstParts = math.max(worstParts, sceneryParts())
	worstCritters = math.max(worstCritters, critters())
	worstWeather = math.max(worstWeather, weatherEmitters())
	worstLights = math.max(worstLights, lights())
	table.insert(rows, string.format("%s %d parts", b.id, sceneryParts()))
	truthy(sceneryParts() <= B.SceneryPartsPerBand, string.format("%s: %d scenery Parts (cap %d per band)", b.name, sceneryParts(), B.SceneryPartsPerBand))
	-- the seam into the next band: both bands' scenery, half and half
	local nb = bands[i + 1]
	if nb then
		A:SetAttribute("Survived", nb.from - (nb.fade or 0) / 2)
		frames(4)
		local w = EnvBands.weights(bands, nb.from - (nb.fade or 0) / 2)
		if (w[i + 1] or 0) > 0 then
			truthy(sceneryParts() <= B.SceneryParts, string.format("the seam %s/%s: %d scenery Parts (cap %d)", b.id, nb.id, sceneryParts(), B.SceneryParts))
			worstParts = math.max(worstParts, sceneryParts())
			worstWeather = math.max(worstWeather, weatherEmitters())
			worstCritters = math.max(worstCritters, critters())
		end
	end
end
truthy(worstCritters <= B.Critters, "critters never over " .. B.Critters .. " (" .. worstCritters .. ")")
truthy(worstWeather <= B.WeatherEmitters, "weather emitters never over " .. B.WeatherEmitters .. " (" .. worstWeather .. ")")
truthy(worstLights <= B.Lights, "client PointLights never over " .. B.Lights .. " (" .. worstLights .. ")")
print("  scenery per band: " .. table.concat(rows, ", ") .. string.format("; worst %d parts, %d critters, %d weather emitters, %d lights",
	worstParts, worstCritters, worstWeather, worstLights))

--======================================================================= 3. a jump glides

do
	A:SetAttribute("Survived", 0)
	frames(8)
	local from = Lighting.ClockTime
	A:SetAttribute("Survived", 21)
	frames(0.12)
	local to = bands[5].lighting.ClockTime
	local moved = (Lighting.ClockTime - from) / (to - from)
	truthy(moved > 0 and moved < 0.25, string.format("a jump from band 1 to band 5 glides: %.0f %% of the way after 0.12 s", moved * 100))
	frames(6)
	near(Lighting.ClockTime, to, 0.05, "and arrives")
	-- in a fade, two bands mix
	A:SetAttribute("Survived", 100 - 10)
	frames(8)
	local mixed = EnvBands.sample(bands, 90, "lighting").ClockTime
	near(Lighting.ClockTime, mixed, 0.05, "halfway through New Dawn's 20-survival fade, the light is the mix of the two bands")
end

--======================================================================= 4. the disaster overlay

do
	A:SetAttribute("Survived", 0)
	frames(8)
	local rf = h.workspace:FindFirstChild("Round")
	local base = Lighting.Brightness
	rf:SetAttribute("Kind", "flood")
	frames(1)
	local partial = Lighting.Brightness
	frames(4)
	local full = Lighting.Brightness
	truthy(partial < base and partial > full, string.format("the flood darkens over 3 s (%.2f -> %.2f -> %.2f)", base, partial, full))
	near(full, base * 0.6, 0.06, "to 0.6 x the band's Brightness")
	rf:SetAttribute("Kind", nil)
	frames(5)
	near(Lighting.Brightness, base, 0.06, "and back after the disaster")
	for _, kind in Config.Disasters.Kinds do
		rf:SetAttribute("Kind", kind)
		frames(7) -- 3 s of weight, then the 0.6 s half-life closes the rest
		local cc = Lighting:FindFirstChild("FxColorCorrection")
		local want = Config.Env.Overlays[kind].colorCorrection.TintColor
		truthy(cc and math.abs(cc.TintColor.R * 255 - want[1]) < 3 and math.abs(cc.TintColor.B * 255 - want[3]) < 3,
			kind .. string.format(": its overlay tint is on (%.0f, %.0f, %.0f)", cc.TintColor.R * 255, cc.TintColor.G * 255, cc.TintColor.B * 255))
		rf:SetAttribute("Kind", nil)
		frames(4)
	end
end

--======================================================================= 4b. the scenery caps are code, not just measured (REVIEW-1 F11)

-- SkyArt trims a far piece to Budget.SceneryPartsPerPiece Parts and all the far scenery to Budget.SceneryParts. Lower
-- both on the running client and the pieces it builds obey them.
do
	local perPiece, total = B.SceneryPartsPerPiece, B.SceneryParts
	A:SetAttribute("Survived", 0)
	frames(8)
	B.SceneryPartsPerPiece = 3
	A:SetAttribute("Survived", bands[3].from)
	frames(8)
	local built, over = 0, 0
	for _, id in bands[3].pieces do
		local m = sky.Scenery:FindFirstChild(id)
		if m then
			built += 1
			if countClass(m, "BasePart") > 3 then over += 1 end
		end
	end
	eq(built, #bands[3].pieces, bands[3].name .. "'s pieces are built with the per-piece cap lowered to 3")
	eq(over, 0, "and none has more than 3 Parts")
	B.SceneryPartsPerPiece = perPiece
	A:SetAttribute("Survived", 0)
	frames(8)
	B.SceneryParts = 10
	A:SetAttribute("Survived", bands[3].from)
	frames(8)
	truthy(sceneryParts() <= 10, string.format("with the total cap lowered to 10, the far scenery has %d Parts", sceneryParts()))
	print(string.format("  scenery caps in code: per piece lowered to 3 -> %d of %d pieces over it; total lowered to 10 -> %d Parts",
		over, built, sceneryParts()))
	B.SceneryParts = total
	A:SetAttribute("Survived", 0)
	frames(8)
end

--======================================================================= 6. nothing the sky builds is red

do
	local red = {}
	for _, d in sky:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "StrayRing" then
			local c = d.Color
			if c.R - math.max(c.G, c.B) > 0.25 then table.insert(red, d.Name) end
		end
	end
	eq(#red, 0, "no scenery, critter or weather Part is red (" .. table.concat(red, ", ") .. ")")
end

--======================================================================= 5 (cont). every disaster, 8 players at Heat 5

A:SetAttribute("Resting", false)
local maxv = { projectiles = 0, chunks = 0, debris = 0, ribbon = 0, auras = 0, billboards = 0, emitters = 0, rings = 0, serverParts = 0, lights = 0 }
do
	local Cfg = Config
	Cfg.Shots.ForceHeat = 5
	local bots = { Bot.new(h, A, { react = 0.6 }) }
	for k = 1, 7 do
		local p = h:join("Heat" .. k, 810 + k)
		h.Players:simulateSpawn(p, h.workspace)
		table.insert(bots, Bot.new(h, p, { react = 0.6 }))
	end
	h.Players.LocalPlayer = A
	A:SetAttribute("Survived", 21) -- the brightest sky: comet and meteors, the most lights
	local rf = h.workspace:FindFirstChild("Round")
	local function serverParts(): number
		local n = 0
		for _, root in { h.workspace:FindFirstChild("Lookout"), rf, h.workspace:FindFirstChild("Sea") } do
			if root then
				if root:IsA("BasePart") then n += 1 end
				for _, d in root:GetDescendants() do
					if d:IsA("BasePart") then n += 1 end
				end
			end
		end
		return n
	end
	local function measure()
		maxv.projectiles = math.max(maxv.projectiles, #world.Projectiles:GetChildren())
		maxv.chunks = math.max(maxv.chunks, #world.Chunks:GetChildren())
		maxv.debris = math.max(maxv.debris, #world.Debris:GetChildren())
		maxv.ribbon = math.max(maxv.ribbon, #world.PathRibbon:GetChildren())
		local auras, boards = 0, 0
		for _, p in h.Players:GetPlayers() do
			local c = p.Character
			if c and c:FindFirstChild("HumanoidRootPart"):FindFirstChild("HeatAura") then auras += 1 end
		end
		boards = #world.Auras:GetChildren()
		maxv.auras = math.max(maxv.auras, auras)
		maxv.billboards = math.max(maxv.billboards, boards)
		maxv.emitters = math.max(maxv.emitters, countClass(world.Fx, "ParticleEmitter"))
		maxv.rings = math.max(maxv.rings, #rf.Rings:GetChildren())
		maxv.serverParts = math.max(maxv.serverParts, serverParts())
		maxv.lights = math.max(maxv.lights, lights())
	end
	for _, kind in Config.Disasters.Kinds do
		Cfg.Shots.ForceKind = kind
		local n = 0
		while rf:GetAttribute("Phase") ~= "disaster" and n < 1200 do
			for _, b in bots do Bot.step(b, 0.1) end
			cam.CFrame = CFrame.new(char.HumanoidRootPart.Position + Vector3.new(-12, 8, 0), Vector3.new(0, 0, 0))
			RunService.RenderStepped:Fire(0.1)
			h:advance(0.1)
			n += 1
		end
		while rf:GetAttribute("Phase") == "disaster" do
			for _, b in bots do Bot.step(b, 0.1) end
			cam.CFrame = CFrame.new(char.HumanoidRootPart.Position + Vector3.new(-12, 8, 0), Vector3.new(0, 0, 0))
			RunService.RenderStepped:Fire(0.1)
			h:advance(0.1)
			measure()
		end
	end
	truthy(maxv.projectiles <= B.Projectiles, string.format("projectiles never over %d (%d)", B.Projectiles, maxv.projectiles))
	truthy(maxv.chunks <= B.Chunks, string.format("falling chunks never over %d (%d)", B.Chunks, maxv.chunks))
	truthy(maxv.debris <= B.Debris, string.format("tornado debris never over %d (%d)", B.Debris, maxv.debris))
	truthy(maxv.ribbon <= B.PathRibbon, string.format("path ribbon Parts never over %d (%d)", B.PathRibbon, maxv.ribbon))
	truthy(maxv.auras <= B.Auras, string.format("Heat auras never over %d (%d)", B.Auras, maxv.auras))
	truthy(maxv.billboards <= B.Billboards, string.format("Heat billboards never over %d (%d)", B.Billboards, maxv.billboards))
	truthy(maxv.emitters <= B.DisasterEmitters, string.format("disaster emitters never over %d (%d)", B.DisasterEmitters, maxv.emitters))
	truthy(maxv.rings <= B.Rings, string.format("live rings never over %d (%d)", B.Rings, maxv.rings))
	truthy(maxv.serverParts <= B.ServerParts, string.format("server Parts never over %d (%d)", B.ServerParts, maxv.serverParts))
	-- REVIEW-1 F11: capped in code, not just measured. The server's only Parts that vary are the island's cells (Grid^2),
	-- its props (MaxProps, capped in buildProp) and the rings (Budget.Rings, capped in Strikes.maxLive); the rest is fixed
	do
		local island = rf:FindFirstChild("Island")
		local cells = if island then #island.Cells:GetChildren() else 0
		local props = if island then #island.Props:GetChildren() else 0
		local fixed = serverParts() - cells - props - #rf.Rings:GetChildren()
		local ceiling = fixed + Config.Island.Grid ^ 2 + Config.Island.MaxProps + B.Rings
		truthy(island ~= nil and ceiling <= B.ServerParts, string.format("every server Part source at its cap: %d fixed + %d cells + %d props + %d rings = %d, under %d",
			fixed, Config.Island.Grid ^ 2, Config.Island.MaxProps, B.Rings, ceiling, B.ServerParts))
		print(string.format("  server Parts at every cap: %d fixed + %d cells + %d props + %d rings = %d (cap %d)",
			fixed, Config.Island.Grid ^ 2, Config.Island.MaxProps, B.Rings, ceiling, B.ServerParts))
	end
	truthy(maxv.lights <= B.Lights, string.format("client PointLights never over %d (%d)", B.Lights, maxv.lights))
	truthy(maxv.projectiles > 0 and maxv.chunks > 0 and maxv.debris > 0 and maxv.ribbon > 0 and maxv.auras > 0,
		"and the show actually ran: projectiles, chunks, debris, the red path and Heat flames were all seen")
	print(string.format("  8 players at Heat 5, all four disasters, peak: %d projectiles, %d chunks, %d debris, %d ribbon, %d auras, %d billboards, %d emitters, %d rings, %d server Parts, %d lights",
		maxv.projectiles, maxv.chunks, maxv.debris, maxv.ribbon, maxv.auras, maxv.billboards, maxv.emitters, maxv.rings, maxv.serverParts, maxv.lights))
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	if string.find(w, "error", 1, true) or string.find(w, "failed", 1, true) then
		failed += 1
		print("FAIL: warning: " .. w)
	end
end
print(string.format("disasterrounds env: %d passed, %d failed", passed, failed))
