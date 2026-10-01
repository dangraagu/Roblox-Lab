-- StormGrow — the sky follows the farm, glides, stays inside its budgets at every band, seam and event.
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_env.luau 2>&1
--
-- Boots the real server and all three client scripts (Hud, Farm, Sky) and drives them frame by frame.
--
-- What this run sets by hand, and why that is fair (in-memory, this process only):
--   * the local player's `Harvested` attribute. The server writes it on every harvest; the client's sky only
--     READS it. Reaching band 7 by playing takes two hours (tests/Pacing.spec.luau), so the glue is driven the
--     way the night shift's shots place drives it (DESIGN.md §14.2). The economy is not under test here.
--   * Config.Weather.ClockOffsetSeconds, to put the global clock in a clear phase, then in a storm, a frost and
--     a rainbow (DESIGN.md §2.1: the offset is inside the server clock, so server and client agree).
--   * every one of the 324 tile hitboxes' attributes, for the crop budget: six FULL farms, every crop, every
--     mark. That is the worst case the client can be handed; no real server state is faked for a player.

local Harness = require("./emu/harness")

local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-env", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Weather = mod("Weather")
local EnvBands = mod("EnvBands")
local W, Env, Bud = Config.Weather, Config.Env, Config.Budget
local bands = Env.Bands

-- start in a clear phase: 200 s past a cycle start, where the next event (the frost) is 100 s away
local function phaseOffset(targetPhaseInHour)
	local t = os.time()
	return (targetPhaseInHour - t % 3600) % 3600
end
W.ClockOffsetSeconds = phaseOffset(200 + 600) -- :13:20, clear

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local Lighting = h.Lighting

--============================================================ the first frame is band 1 (Fx.Presets.Farm)

do
	local b1 = bands[1].lighting
	eq(Lighting.ClockTime, b1.ClockTime, "the server's first frame: ClockTime is band 1's")
	eq(Lighting.Brightness, b1.Brightness, "Brightness is band 1's")
	local fog = Lighting.FogColor
	truthy(fog and math.abs(fog.R * 255 - b1.FogColor[1]) < 1 and math.abs(fog.B * 255 - b1.FogColor[3]) < 1, "FogColor is band 1's")
	local atm = Lighting:FindFirstChild("FxAtmosphere")
	eq(atm and atm.Density, bands[1].atmosphere.Density, "the Atmosphere is band 1's")
end

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("SkyWatcher", 7777)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(1, 0, 0) -- walking, so standing still never idles into rest here
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	local ok, err = h:tryRun(key)
	truthy(ok, key .. " loads (" .. tostring(err) .. ")")
end
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local probe = h.workspace:FindFirstChild("StormLocalSky"):FindFirstChild("StormSkyProbe")
local function frames(seconds, dt)
	dt = dt or 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 12, 24), hrp.Position)
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
	end
end
local function counts() return probe:Invoke("counts") end
frames(2)

--============================================================ the brag: crossing into the Eye during play
-- First, while this session has seen only band 1: the announcer remembers the highest band it showed, so
-- this has to come before the sweep below walks every band.

do
	local c0 = counts()
	eq(c0.cards, 1, "joining shows one quiet card: where your farm's sky is")
	truthy(string.find(c0.lastCard, "SUNNY MEADOW", 1, true) ~= nil, "the band you are in (" .. c0.lastCard .. ")")
	for i = 2, 5 do
		plr:SetAttribute("Harvested", bands[i].from + 1)
		frames(3)
	end
	local before = counts().cards
	eq(before, 5, "each new band on the way up shows its card (bands 2-5)")
	plr:SetAttribute("Harvested", bands[6].from + 10)
	frames(1)
	local c = counts()
	eq(c.cards, before + 1, "crossing 300,000 during play shows a card")
	truthy(string.find(c.lastCard, "YOUR FARM IS IN THE EYE OF THE STORM", 1, true) ~= nil, "the brag card (" .. c.lastCard .. ")")
	frames(6)
	local wall = 0
	for _, d in h.workspace.StormLocalSky:GetDescendants() do
		if string.match(d.Name, "^StormWall_") and d.Transparency < 0.5 and d.Size.Y > 250 then wall += 1 end
	end
	eq(wall, 24, "the storm wall stands around the valley, risen to full height")
	-- going back down and up again says nothing (the announcer remembers the highest band)
	plr:SetAttribute("Harvested", bands[5].from + 1)
	frames(3)
	plr:SetAttribute("Harvested", bands[6].from + 10)
	frames(1)
	eq(counts().cards, before + 1, "a second crossing of the same band shows no second card")
	plr:SetAttribute("Harvested", 0)
	frames(5)
end

--============================================================ bands follow Harvested, and glide

local peaks = { scenery = 0, critters = 0, lightsOn = 0, emittersOn = 0, bolts = 0, hazard = 0 }
local function track(label)
	local c = counts()
	for k in peaks do
		if type(c[k]) == "number" and c[k] > peaks[k] then peaks[k] = c[k] end
	end
	if c.scenery > Bud.MaxSceneryParts then failed += 1; print("FAIL: scenery over budget at " .. label .. ": " .. c.scenery) end
	if c.critters > Bud.MaxCritterParts then failed += 1; print("FAIL: critters over budget at " .. label .. ": " .. c.critters) end
	if c.lightsOn > Bud.MaxLights then failed += 1; print("FAIL: lights over budget at " .. label .. ": " .. c.lightsOn) end
	if c.emittersOn > Bud.MaxWeatherEmitters then failed += 1; print("FAIL: weather emitters over budget at " .. label .. ": " .. c.emittersOn) end
	return c
end

local rows = {}
for i, b in bands do
	plr:SetAttribute("Harvested", b.from + (if i == 1 then 10 else 1))
	frames(4)
	local c = track(b.id)
	local ct = Lighting.ClockTime
	truthy(math.abs(ct - b.lighting.ClockTime) < 0.05, string.format("band %d %s: ClockTime %.2f reaches the band's %.2f", i, b.id, ct, b.lighting.ClockTime))
	truthy(c.weights[i] > 0.97, string.format("band %d: its weight glides to 1 (%.3f)", i, c.weights[i]))
	local ground = h.workspace.Valley.Ground.Color
	truthy(math.abs(ground.R * 255 - b.ground[1]) < 2 and math.abs(ground.G * 255 - b.ground[2]) < 2, "band " .. i .. ": the valley floor takes the band's colour")
	table.insert(rows, string.format("%-9s scenery %3d critters %2d lights %2d emitters %d", b.id, c.scenery, c.critters, c.lightsOn, c.emittersOn))
	-- the seam into the next band: halfway through its fade, two bands' pieces at once
	local nb = bands[i + 1]
	if nb then
		plr:SetAttribute("Harvested", nb.from - nb.fade / 2)
		frames(4)
		local s = track(b.id .. "->" .. nb.id)
		table.insert(rows, string.format("  seam -> %-9s scenery %3d critters %2d lights %2d emitters %d", nb.id, s.scenery, s.critters, s.lightsOn, s.emittersOn))
	end
end
for _, r in rows do print("  " .. r) end

do
	-- a jump from band 1 to band 5 (a rejoin deep in the ladder) glides instead of cutting
	plr:SetAttribute("Harvested", 0)
	frames(5)
	local before = Lighting.ClockTime
	plr:SetAttribute("Harvested", bands[5].from + 10)
	frames(0.2)
	local after = Lighting.ClockTime
	local gap = bands[5].lighting.ClockTime - before
	local moved = (after - before) / gap
	truthy(moved > 0 and moved < 0.5, string.format("a jump of four bands moves ClockTime only %.0f %% in the first 0.2 s (it glides)", moved * 100))
	frames(5)
	truthy(math.abs(Lighting.ClockTime - bands[5].lighting.ClockTime) < 0.05, "and arrives within 5 s")
end

do
	-- Lighting is written at most LightingHz times a second
	local c0 = counts().writes
	plr:SetAttribute("Harvested", bands[3].from + 1)
	frames(3)
	local c1 = counts().writes
	-- 6 groups x ~6 fields each can change per write; the rate cap is on WRITE PASSES, so measure passes:
	-- 3 s at 10 Hz is at most 30 passes, each touching at most every field once (<= 44 fields)
	truthy(c1 - c0 <= 30 * 44, string.format("Lighting property writes in 3 s: %d (<= 30 passes x 44 fields)", c1 - c0))
end

--============================================================ every weather event, in every band

local eventRows = {}
local function goEvent(phaseInHour)
	W.ClockOffsetSeconds += phaseOffset(phaseInHour) - ((os.time() + W.ClockOffsetSeconds) % 3600 - (os.time() + W.ClockOffsetSeconds) % 3600)
end
local function setClockTo(phaseInHour)
	-- set the offset so the server clock reads `phaseInHour` seconds past the hour right now
	local sn = h.workspace:GetAttribute("ServerNow")
	local cur = sn % 3600
	W.ClockOffsetSeconds += (phaseInHour - cur) % 3600
	h:advance(1.1) -- the next ServerNow broadcast
end
for _, ev in { { "storm", 30 }, { "rainbow", 110 }, { "frost", 330 } } do
	for i, b in bands do
		plr:SetAttribute("Harvested", b.from + 1)
		setClockTo(ev[2] + (i - 1) * 0) -- a phase inside the event
		frames(6)
		local kind = Weather.at(h.workspace:GetAttribute("ServerNow"), W)
		eq(kind, ev[1], "set-up: the server clock is in a " .. ev[1])
		local c = track(ev[1] .. "@" .. b.id)
		if i == 1 or i == 6 or i == 7 then
			table.insert(eventRows, string.format("%-7s in %-9s scenery %3d lights %2d emitters %d beams %d bolts %d",
				ev[1], b.id, c.scenery, c.lightsOn, c.emittersOn, c.beams, c.bolts))
		end
		if ev[1] == "rainbow" then
			eq(c.beams, 7, "the rainbow arc is up during a rainbow (" .. b.id .. ")")
		else
			eq(c.beams, 0, "no rainbow outside one (" .. ev[1] .. ", " .. b.id .. ")")
		end
	end
end
for _, r in eventRows do print("  " .. r) end
do
	-- the storm overlay darkens: Brightness in a storm is below the band's own
	plr:SetAttribute("Harvested", bands[3].from + 1)
	setClockTo(200) -- clear
	frames(6)
	local clearB = Lighting.Brightness
	setClockTo(40) -- storm
	frames(6)
	local stormB = Lighting.Brightness
	print(string.format("  Windy Orchard, clear -> storm: Brightness %.2f -> %.2f", clearB, stormB))
	truthy(stormB < clearB * 0.7, string.format("a storm halves the light (%.2f -> %.2f)", clearB, stormB))
	local c = counts()
	truthy(c.emittersOn >= 1, "and it rains (" .. c.emittersOn .. " weather emitters on)")
	-- distant bolts during a storm
	local boltsSeen = 0
	for _ = 1, 100 do
		frames(0.1)
		if counts().bolts > 0 then boltsSeen += 1 end
	end
	truthy(boltsSeen > 0, "distant bolts flash during the storm (" .. boltsSeen .. " frames of 100 had one)")
	setClockTo(200)
	frames(6)
end

--============================================================ crops: six full farms, every mark

do
	local farms = h.workspace.Farms
	local crops = Config.Crops
	local n = 0
	local sn = h.workspace:GetAttribute("ServerNow")
	for _, model in farms:GetChildren() do
		for _, hb in model.Tiles:GetChildren() do
			if hb:GetAttribute("Key") then
				n += 1
				local c = crops[1 + (n % #crops)]
				hb:SetAttribute("Crop", c.id)
				hb:SetAttribute("PlantedAt", sn - c.grow - 10)
				hb:SetAttribute("Grow", c.grow)
				hb:SetAttribute("Marks", 7)
			end
		end
	end
	frames(2)
	local cropParts, marksFx = 0, 0
	for _, d in h.workspace.StormCrops:GetDescendants() do
		if d:IsA("BasePart") then cropParts += 1 end
		if d.ClassName == "ParticleEmitter" then marksFx += 1 end
	end
	print(string.format("  six full farms, every crop a Tempest: %d crop parts (cap %d), %d mark emitters (cap %d)", cropParts, Bud.MaxCropParts, marksFx, Bud.MaxMarkEmitters))
	eq(cropParts, 324 * 5, "324 Tempest crops are drawn with exactly 5 parts each")
	truthy(cropParts <= Bud.MaxCropParts, "crop parts within the budget")
	truthy(marksFx <= Bud.MaxMarkEmitters, "mark emitters within the budget")
	truthy(marksFx > 0, "and the nearest marked crops do sparkle")
	-- strikes: every tile strikes at once (a new LastStrike and a new mark) -> at most MaxBolts bolts
	for _, model in farms:GetChildren() do
		for _, hb in model.Tiles:GetChildren() do
			if hb:GetAttribute("Key") then
				hb:SetAttribute("Marks", 2)
			end
		end
	end
	frames(0.5)
	for _, model in farms:GetChildren() do
		for _, hb in model.Tiles:GetChildren() do
			if hb:GetAttribute("Key") then
				hb:SetAttribute("Marks", 3)
				hb:SetAttribute("LastStrike", sn + 5)
			end
		end
	end
	frames(0.1)
	local bolts = 0
	for _, d in h.workspace.StormStrikes:GetChildren() do
		if d.Name == "StrikeBolt" then bolts += 1 end
	end
	print(string.format("  324 simultaneous storm strikes -> %d bolt segments (%d bolts, cap %d)", bolts, bolts // 4, Bud.MaxBolts))
	truthy(bolts // 4 <= Bud.MaxBolts and bolts > 0, "at most MaxBolts bolts at once, nearest first")
	frames(1)
	local left = 0
	for _, d in h.workspace.StormStrikes:GetChildren() do
		if d.Name == "StrikeBolt" then left += 1 end
	end
	eq(left, 0, "and every bolt is gone a second later")
end

--============================================================ the light cap holds when it has to
-- Every band's own lights fit under MaxLights (the peak above is 12 of 12), so in this build the cap is never what
-- keeps the count down, and the 2026-10-01 mutation sweep found that deleting it changed nothing. A cap nobody
-- has seen work is a claim. So lower it in memory (this process only) and watch it hold, nearest first.

do
	plr:SetAttribute("Harvested", bands[7].from + 1)
	setClockTo(200) -- clear
	frames(5)
	local all = {}
	for _, d in h.workspace.StormLocalSky:GetDescendants() do
		if d.ClassName == "PointLight" and d.Parent and d.Parent:IsA("BasePart") then table.insert(all, d) end
	end
	truthy(#all > 5, "set-up: Starfall hangs more than 5 lights (" .. #all .. ")")
	local cap = Bud.MaxLights
	Bud.MaxLights = 5
	frames(1)
	local camPos = cam.CFrame.Position
	local on, farthestOn, nearestOff = 0, -math.huge, math.huge
	for _, l in all do
		local d = (l.Parent.Position - camPos).Magnitude
		if l.Enabled then
			on += 1
			farthestOn = math.max(farthestOn, d)
		else
			nearestOff = math.min(nearestOff, d)
		end
	end
	print(string.format("  light cap lowered to 5 in Starfall: %d of %d PointLights on", on, #all))
	eq(on, 5, "with MaxLights lowered to 5, exactly 5 of the " .. #all .. " lights stay on")
	truthy(farthestOn <= nearestOff + 1e-6, string.format("and they are the nearest to the camera (farthest on %.1f, nearest off %.1f)", farthestOn, nearestOff))
	eq(counts().lightsOn, 5, "the probe counts 5 too")
	Bud.MaxLights = cap
	frames(1)
	eq(counts().lightsOn, math.min(#all, cap), "restoring the cap turns them back on")
end

--============================================================ a slow load deep in the ladder stays quiet
-- A farmer past the brag whose farm is still held by another server joins: the load waits on the lock, and the
-- sky must say nothing until the profile is in, then show ONE quiet card for the band the farm is in. Never the
-- band-1 card first, never the brag again (DESIGN.md §3.4). The emulator's DataStore answers at once, so only a
-- lock makes the client see frames before `Loaded`; the 2026-10-01 mutation sweep found nothing else did.

do
	local Save = Config.Save
	local deep = bands[6].from + 5000
	local now = h.workspace:GetAttribute("ServerNow")
	h.services.DataStoreService:GetDataStore(Save.Store):SetAsync("u_7878", {
		v = 1, coins = 40000, harvested = deep, fields = 4, unlocked = 7, selected = "watermelon", tiles = {},
		almanac = { ["pumpkin:1"] = 1 }, almanacCount = 1, almanacAt = 1, harvests = 900,
		session = { token = "ANOTHER-SERVER", lockUntil = now + 12 },
	})
	-- this client goes away (a new client is a new process in Roblox; the emulator keeps one, so tear it down)
	h:leave(plr)
	h:advance(0.5)
	RunService.RenderStepped:DisconnectAll()
	local rem = RS.StormRemotes
	rem.Toast.OnClientEvent:DisconnectAll()
	rem.Board.OnClientEvent:DisconnectAll()
	for _, name in { "StormLocalSky", "StormCrops", "StormStrikes" } do
		local f = h.workspace:FindFirstChild(name)
		if f then f:Destroy() end
	end
	local oldView = h.workspace.Valley.AlmanacBoard:FindFirstChild("BoardView")
	if oldView then oldView:Destroy() end

	local p2 = h:join("Returner", 7878)
	h:advance(0.2)
	local char2 = h.Players:simulateSpawn(p2, h.workspace)
	h:advance(0.2)
	hrp = char2:FindFirstChild("HumanoidRootPart")
	char2:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Grass
	h.Players.LocalPlayer = p2
	for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
		local ok, err = h:tryRun(key)
		truthy(ok, "the returner's " .. key .. " loads (" .. tostring(err) .. ")")
	end
	probe = h.workspace:FindFirstChild("StormLocalSky"):FindFirstChild("StormSkyProbe")
	frames(5)
	eq(p2:GetAttribute("Loaded"), false, "set-up: the load is still waiting on the other server's lock")
	eq(counts().cards, 0, "while it waits, the sky shows no card")
	truthy(p2.PlayerGui.StormHud.Root.Loading.Visible, "and the HUD says the farm is loading")
	frames(14)
	eq(p2:GetAttribute("Loaded"), true, "the lock ran out and the farm loaded")
	eq(p2:GetAttribute("Harvested"), deep, "with the saved lifetime harvest")
	local c = counts()
	eq(c.cards, 1, "then exactly one card")
	truthy(string.find(c.lastCard, "EYE OF THE STORM", 1, true) ~= nil and string.find(c.lastCard, "YOUR FARM IS IN", 1, true) == nil,
		"the quiet card of the band the farm is in, not the brag (" .. c.lastCard .. ")")
	print(string.format("  a returner past the brag, held 12 s by another server: %d card(s), \"%s\"", c.cards, c.lastCard))
end

print(string.format("  peaks over the whole run: scenery %d/%d, critters %d/%d, lights %d/%d, weather emitters %d/%d",
	peaks.scenery, Bud.MaxSceneryParts, peaks.critters, Bud.MaxCritterParts, peaks.lightsOn, Bud.MaxLights, peaks.emittersOn, Bud.MaxWeatherEmitters))

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	if string.find(w, "frame error", 1, true) then failed += 1 end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow env: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow env check failed", 0) end
