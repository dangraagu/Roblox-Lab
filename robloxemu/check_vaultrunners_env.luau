-- Vault Runners — the environment (EYECANDY.md), driven through the REAL client script.
-- Run (from robloxemu): luau check_vaultrunners_env.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- The pure rules are unit-tested in vault-runners/tests (EnvBands, VaultEnv, EnvConfig, Hazards,
-- Rest, Pacing). This file checks the GLUE no unit test can see, against the real server:
--   §1  the client takes over the server's lighting without a jump;
--   §2  the hub: the vault door, the portal signs, the chip, and no weather and no drops;
--   §3  rest: the hub's ☕ button sits you down, moving wakes you, a run starting wakes you, and it
--       is never offered (and does nothing) inside a vault;
--   §4  every one of the five strata, in real runs on the real server — Bronze 1, 4 (a blend floor),
--       5, 14, Silver 1, Gold 1: the colours on the server's walls / floors / pads, the props, the
--       sky piece, the weather, the lighting — and that the server's parts keep every property
--       physics or the obby reads (only Color and Reflectance change);
--   §5  transitions glide (hub -> vault -> hub), never cut, never overshoot;
--   §6  the obby: a crack where the runner stands, debris when the server drops the pad, a flash
--       when it comes back — and the pad is never painted while the server says it is gone;
--   §7  the collapse: dust and sparks rise as the plane closes in; the run's end clears it all;
--   §8  title cards: a card per new stratum, the fanfare only the first time this player goes deeper;
--   §9  the budgets (Config.Budget) on EVERY measured frame, and the pools do not grow;
--   §10 the leak rules: no remote fired, no attribute written, every client part inert, nothing in
--       another player's vault touched.
--
-- Headless limits, stated: nothing renders and there is no physics. Frames are driven by firing
-- RunService.RenderStepped; the character does not move unless this file moves it. Whether any of it
-- LOOKS right is on EYECANDY.md's Studio list.

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
	bundle = require("./build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local ME, OTHER = 4242, 777
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
-- every vault unlocked (the unlock is not what this file is about), every tier on floor 1
for _, uid in { ME, OTHER } do
	store:SetAsync("u_" .. uid, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
		floors = { [1] = 1, [2] = 1, [3] = 1 }, escapes = 0, wipes = 0 } })
end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local VaultEnv = mod("VaultEnv")
local VaultArt = mod("VaultArt")
local Trace = mod("Trace")
local bands = Config.Env.Bands
local Budget = Config.Budget

local Lighting = h.Lighting
local serverLighting = {
	Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
}
local serverAtmos = Lighting:FindFirstChild("FxAtmosphere")
local serverDensity = serverAtmos and serverAtmos.Density

local remotes = RS:FindFirstChild("VaultRemotes")
local serverCalls = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end
local RunRemote = remotes:FindFirstChild("Run")
-- Every call THIS FILE makes is counted here, so what is left over in serverCalls is the client's.
local ownCalls = 0
local EnterRemote = remotes:FindFirstChild("Enter")
local Enter = {
	simulateFireServer = function(_, who, ...)
		ownCalls += 1
		EnterRemote:simulateFireServer(who, ...)
	end,
}

-- A second player whose vault this client must never touch (slot 0 is theirs: they join first).
local other = h:join("Neighbour", OTHER)
h:advance(1)
h.Players:simulateSpawn(other, h.workspace)
h:advance(0.5)
Enter:simulateFireServer(other, 1)
h:advance(0.5)
local vaults = h.workspace:FindFirstChild("Vaults")
local live = vaults:FindFirstChild("Vault_" .. OTHER)
truthy(live ~= nil, "(the neighbour is in their own vault)")
-- The emulator delivers every FireClient to every client script (one process, one world), so a
-- neighbour whose run is still going would drive THIS client with their events. Their vault, as the
-- server built it, is cloned and moved aside, and their run is allowed to end before this client
-- loads: what remains is a real vault named for another player, which this client must never touch.
local otherVault = live:Clone()
for _, d in otherVault:GetDescendants() do
	if d:IsA("BasePart") then d.CFrame = d.CFrame + Vector3.new(0, 0, 900) end
end
otherVault.Parent = vaults
h:advance(120)
eq(vaults:FindFirstChild("Vault_" .. OTHER), otherVault, "(the neighbour's run is over; their vault stands)")
local otherSnapshot = {}
for _, d in otherVault:GetDescendants() do
	if d:IsA("BasePart") then otherSnapshot[d] = { Color = d.Color, Reflectance = d.Reflectance } end
end

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
-- Ceiling drops have their own check (check_vaultrunners_hazards.luau). Here they would only knock
-- the runner about between measurements, so the first one is pushed past the end of this file.
Config.Hazards.IntervalMin = 1e6
Config.Hazards.IntervalMax = 1e6 + 1

local plr = h:join("Runner", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okVault, errVault = h:tryRun("client/Vault.client")
truthy(okVault, "Vault.client loads (" .. tostring(errVault) .. ")")

local fx = h.workspace:FindFirstChild("VaultRunnersFx")
truthy(fx ~= nil, "the client made its local fx folder")
local gui = plr.PlayerGui:FindFirstChild("VaultFx")
local root = gui and gui:FindFirstChild("Root")
local row = root and root:FindFirstChild("BandRow")
local chip = row and row:FindFirstChild("BandChip")
local restBtn = row and row:FindFirstChild("RestButton")
local card = root and root:FindFirstChild("BandCard")
local warning = root and root:FindFirstChild("HazardWarning")
truthy(chip and restBtn and card and warning, "chip, rest button, title card and warning exist")

local cam = h.workspace.CurrentCamera
local announced = {}
local lastCard = ""
local flashes = 0

--============================================================================ measurement

local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, hazards = 0 }
local peakWhere = {}
local measured = 0
local function measure(where)
	local parts, emitters, rate, lights, beams = 0, 0, 0, 0, 0
	for _, d in fx:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			parts += 1
		elseif cls == "ParticleEmitter" and d.Enabled then
			emitters += 1
			rate += d.Rate or 0
		elseif cls == "PointLight" and (d.Brightness or 0) > 0 and d.Enabled ~= false then
			lights += 1
		elseif cls == "Beam" and d.Enabled ~= false then
			beams += 1
		end
	end
	measured += 1
	for k, v in { parts = parts, emitters = emitters, rate = rate, lights = lights, beams = beams } do
		if v > peak[k] then peak[k] = v; peakWhere[k] = where end
	end
	return { parts = parts, emitters = emitters, rate = rate, lights = lights, beams = beams }
end

local function c3(t) return Color3.fromRGB(math.round(t[1]), math.round(t[2]), math.round(t[3])) end
local function sameColor(a, b, tol)
	tol = tol or 1.5 / 255
	return a ~= nil and b ~= nil and math.abs(a.R - b.R) <= tol and math.abs(a.G - b.G) <= tol and math.abs(a.B - b.B) <= tol
end
local where = "hub"
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
			-- the HUD flashes at every run's end in its own colours; the fanfare is Vault.client's
			local f = g:FindFirstChildOfClass("Frame")
			if f and sameColor(f.BackgroundColor3, Color3.fromRGB(255, 244, 220)) then
				flashes += 1
				table.insert(announced, "<flash>")
			end
		end
	end
	measure(where)
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each and each(i) == false then return end
	end
end

local function lastRunEvent(kind)
	local sent = RunRemote:getSent()
	for i = #sent, 1, -1 do
		if sent[i].args[1] == kind and sent[i].player == plr then return sent[i].args[2] end
	end
	return nil
end

--============================================================================ §1 the takeover

run(1, 1 / 30)
near(Lighting.Ambient.R, serverLighting.Ambient.R, 0.01, "§1 in the hub the client keeps the server's Ambient (no jump at join)")
near(Lighting.Brightness, serverLighting.Brightness, 0.01, "§1 and Brightness")
near(Lighting.ClockTime, serverLighting.ClockTime, 0.01, "§1 and ClockTime")
near(Lighting.FogEnd, serverLighting.FogEnd, 0.5, "§1 and FogEnd")
near(serverAtmos and serverAtmos.Density, serverDensity, 0.005, "§1 and the atmosphere density")
eq(Lighting:FindFirstChild("FxAtmosphere"), serverAtmos, "§1 the client reused the server's Atmosphere, not a second one")

--============================================================================ §2 the hub

do
	local doorParts, signs = 0, {}
	for _, d in fx:GetChildren() do
		if string.sub(d.Name, 1, 4) == "Door" then doorParts += 1 end
		if string.sub(d.Name, 1, 11) == "PortalSign_" then signs[d.Name] = d end
	end
	truthy(doorParts >= 10, "§2 the hub's vault door is built (" .. doorParts .. " parts)")
	local hubParts = 0
	for _, d in fx:GetDescendants() do if d.ClassName == "Part" or d.ClassName == "WedgePart" then hubParts += 1 end end
	local signCount = 0
	for _ in signs do signCount += 1 end
	print(string.format("  §2 the hub, client-built: %d parts (vault door %d, portal sign anchors %d), 0 emitters", hubParts, doorParts, signCount))
	eq(signs["PortalSign_1"] ~= nil and signs["PortalSign_3"] ~= nil, true, "§2 each portal carries a local sign")
	truthy(string.find(chip.Text, "Hub", 1, true) ~= nil, "§2 the chip says you are in the hub (" .. chip.Text .. ")")
	eq(restBtn.Visible, true, "§2 the Rest button is offered in the hub")
	-- the hub has no weather and no drops, however long you stand there
	local hazardSeen, weatherOn = false, false
	where = "hub"
	run(600, 0.25, function()
		local ring = fx:FindFirstChild("HazardRing")
		if ring then hazardSeen = true end
		for _, d in fx:GetDescendants() do
			if d.ClassName == "ParticleEmitter" and d.Enabled then weatherOn = true end
		end
	end)
	eq(hazardSeen, false, "§2 ten minutes in the hub: not one ceiling drop")
	eq(weatherOn, false, "§2 and no particles (the hub is calm)")
end

--============================================================================ §3 rest, in the hub only

do
	restBtn.Activated:Fire()
	run(0.3, 1 / 30)
	eq(hum.Sit, true, "§3 ☕ Rest sits the runner down")
	truthy(string.find(chip.Text, "Resting", 1, true) ~= nil, "§3 the chip says so (" .. chip.Text .. ")")
	local dof = Lighting:FindFirstChild("VaultRestFocus")
	eq(dof and dof.Enabled, true, "§3 and the view softens")
	eq(restBtn.Text, "▶ Play", "§3 the button offers to get up")
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6, 1 / 30)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	eq(hum.Sit, false, "§3 moving wakes you (nothing that needs movement happens while resting)")
	restBtn.Activated:Fire()
	run(0.3, 1 / 30)
	eq(hum.Sit, true, "§3 (resting again)")
	Enter:simulateFireServer(plr, 1)
	h:advance(0.05)
	run(0.3, 1 / 30)
	eq(hum.Sit, false, "§3 a run starting wakes you: rest never follows you into a vault")
	eq(restBtn.Visible, false, "§3 and inside a vault there is no Rest button")
	restBtn.Activated:Fire()
	run(0.3, 1 / 30)
	eq(hum.Sit, false, "§3 even a press that reaches the hidden button does nothing in a vault")
	eq(dof and dof.Enabled, false, "§3 and the view is sharp")
	-- the Hud's vault list names each vault's stratum too (its rows are drawn from a state push)
	local hud = plr.PlayerGui:FindFirstChild("VaultHud")
	local tier1 = hud and hud:FindFirstChild("Tier_1", true)
	local tier3 = hud and hud:FindFirstChild("Tier_3", true)
	truthy(tier1 and string.find(tier1.Text, "Floor 1 🏦", 1, true) ~= nil, "§3 the HUD's vault row shows Bronze's stratum (" .. tostring(tier1 and tier1.Text) .. ")")
	truthy(tier3 and string.find(tier3.Text, "Floor 1 🌋", 1, true) ~= nil, "§3 and Gold's (" .. tostring(tier3 and tier3.Text) .. ")")
	-- ...and so do the portals, on this client's own signs (drawn from the same state push)
	local sign1 = fx:FindFirstChild("PortalSign_1")
	local text = sign1 and sign1:FindFirstChild("Stratum") and sign1.Stratum:FindFirstChild("Text")
	eq(text and text.Text, "Floor 1 · 🏦 Bank Vault", "§3 Bronze's portal says which stratum its next floor is in")
	local sign3 = fx:FindFirstChild("PortalSign_3")
	local text3 = sign3 and sign3:FindFirstChild("Stratum") and sign3.Stratum:FindFirstChild("Text")
	eq(text3 and text3.Text, "Floor 1 · 🌋 Volcano Temple", "§3 and Gold's (a harder vault is a deeper one)")
end

--============================================================================ runs

local ORIGINAL = {} -- server-built vault parts, recorded before the client ever sees them
local PROPS = { "Material", "Size", "CFrame", "CanCollide", "CanQuery", "CanTouch", "Anchored", "Transparency", "CastShadow" }
local function myVault() return vaults:FindFirstChild("Vault_" .. ME) end
local function snapshot(v)
	local snap = {}
	for _, d in v:GetDescendants() do
		if d:IsA("BasePart") then
			local s = {}
			for _, p in PROPS do s[p] = d[p] end
			s.attrs = 0
			for _ in d:GetAttributes() do s.attrs += 1 end
			snap[d] = s
		end
	end
	return snap
end

local function endCurrentRun()
	if myVault() == nil then return end
	-- a respawn ends the run on the server (onCharacter -> finishRun "collapse")
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

local function enter(tier)
	endCurrentRun()
	Enter:simulateFireServer(plr, tier)
	h:advance(0.05)
	local v = myVault()
	truthy(v ~= nil, "a vault was built for tier " .. tier)
	ORIGINAL = snapshot(v)
	return v, lastRunEvent("start")
end

-- honest walking, like check_vaultrunners.luau: an escape is the only way a floor number advances
local WALK_H, WALK_UP = Trace.speeds(Config)
WALK_H = WALK_H / Config.Run.TrustedSpeedFactor
WALK_UP = WALK_UP / Config.Run.TrustedClimbFactor
local function walkTo(target, stopWhen)
	for _ = 1, 4000 do
		if stopWhen and stopWhen() then break end
		local cur = hrp.Position
		local dx, dz, dy = target.X - cur.X, target.Z - cur.Z, target.Y - cur.Y
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat < 0.5 and math.abs(dy) < 0.5 then break end
		local mh = math.min(flat, WALK_H * 0.2)
		local nx = if flat > 1e-6 then cur.X + dx / flat * mh else cur.X
		local nz = if flat > 1e-6 then cur.Z + dz / flat * mh else cur.Z
		local ny = cur.Y + (if dy > 0 then math.min(dy, WALK_UP * 0.2) else dy)
		hrp.CFrame = CFrame.new(nx, ny, nz)
		h:advance(0.2)
	end
	h:advance(0.2)
end
local function escape(tier)
	Enter:simulateFireServer(plr, tier)
	h:advance(0.05)
	local v = myVault()
	walkTo(v:FindFirstChild("ExitPad").Position, function() return myVault() == nil end)
	h:advance(0.3)
	local e = lastRunEvent("end")
	return e and e.ok
end

local bandLooks = {}
local function checkBand(label, tier, expectBandId)
	local v, start = enter(tier)
	local depth = VaultEnv.depth(Config, tier, start.floor)
	local idx = EnvBands.indexAt(bands, depth)
	local b = bands[idx]
	where = label
	eq(b.id, expectBandId, label .. ": floor " .. start.floor .. " of tier " .. tier .. " is depth " .. depth .. " = " .. expectBandId)
	-- stand in the entry cell for a while; nothing moves
	run(5, 1 / 30)
	local pal = VaultEnv.palette(Config, EnvBands, depth)
	local origin = v:FindFirstChild("Floor_0").Position + Vector3.new(0, 1, 0)

	-- the colours on the server's parts, and nothing else about them
	local walls, floors, pads, wrongColour, touched = 0, 0, 0, nil, nil
	for part, s in ORIGINAL do
		local n = part.Name
		local want = nil
		if string.sub(n, 1, 5) == "Wall_" then walls += 1; want = pal.wall
		elseif string.sub(n, 1, 6) == "Floor_" then floors += 1; want = pal.floor
		elseif string.sub(n, 1, 5) == "Step_" then pads += 1; want = pal.pad end
		if want and not sameColor(part.Color, c3(want)) then wrongColour = wrongColour or n end
		for _, p in PROPS do
			-- the SERVER moves the collapse and the seal every tick and flips pads as they crumble;
			-- those are the server's writes, not the client's, and are left out of this comparison
			local serverMoves = (n == "Collapse" or n == "Seal") and p == "CFrame"
			local serverFlips = string.sub(n, 1, 5) == "Step_" and (p == "Transparency" or p == "CanCollide"
				or p == "CanQuery" or p == "CastShadow")
			if not serverMoves and not serverFlips and part[p] ~= s[p] then touched = touched or (n .. "." .. p) end
		end
		local attrs = 0
		for _ in part:GetAttributes() do attrs += 1 end
		if attrs ~= s.attrs then touched = touched or (n .. " attributes") end
	end
	truthy(walls > 0 and floors > 0 and pads > 0, string.format("%s: (%d walls, %d floors, %d pads)", label, walls, floors, pads))
	eq(wrongColour, nil, label .. ": every wall, floor and pad wears the stratum's colours")
	eq(touched, nil, label .. ": and nothing else about the server's parts changed (material, size, position, collision, transparency, attributes)")
	truthy(VaultEnv.contrast(pal.pad, pal.floor) >= Config.Env.MinPadContrast,
		string.format("%s: the pads stand out %.1f:1 against the floor", label, VaultEnv.contrast(pal.pad, pal.floor)))

	-- lighting has arrived at the stratum (5 s = 8 half-lives)
	local want = EnvBands.sample(bands, depth, "lighting")
	near(Lighting.Ambient.R * 255, want.Ambient[1], 3, label .. ": Lighting.Ambient is the stratum's (R)")
	near(Lighting.Ambient.B * 255, want.Ambient[3], 3, label .. ": (B)")
	local cc = Lighting:FindFirstChild("FxColorCorrection")
	local wantCC = EnvBands.sample(bands, depth, "colorCorrection")
	near(cc and cc.TintColor.G * 255, wantCC.TintColor[2], 3, label .. ": and the colour grade")

	-- props on this storey's ceiling and the next, of the stratum's kinds, above every head
	local props, low, kinds = 0, math.huge, {}
	for _, d in fx:GetChildren() do
		if string.sub(d.Name, 1, 4) == "Prop" then
			props += 1
			local bottom = d.Position.Y - d.Size.Y / 2 - origin.Y
			local storeyFloor = math.floor((d.Position.Y - origin.Y) / Config.Vault.StoreyHeight) * Config.Vault.StoreyHeight
			low = math.min(low, bottom - storeyFloor)
			kinds[d.Name] = true
		end
	end
	truthy(props > 0, label .. ": props hang from the ceilings (" .. props .. " parts)")
	truthy(low >= Config.Env.PropBottomAboveFloor - 0.35,
		string.format("%s: no prop reaches below %.1f studs over its floor (lowest %.2f)", label, Config.Env.PropBottomAboveFloor, low))

	-- the sky piece over the top storey, and the weather around the camera
	local pieceParts = 0
	for _, d in fx:GetChildren() do
		if (d.Name == "Ring" or d.Name == "Skylight" or d.Name == "Sun" or d.Name == "Wing" or d.Name == "Core"
			or d.Name == "Moon" or d.Name == "AuroraA" or d.Name == "Lava") then
			pieceParts += 1
			local topY = origin.Y + (start.storeys - 1) * Config.Vault.StoreyHeight + Config.Vault.StoreyHeight
			truthy(d.Position.Y > topY + 40, label .. ": the set piece floats well above the top storey (" .. d.Name .. ")")
		end
	end
	truthy(pieceParts > 0, label .. ": the stratum's set piece is up (" .. pieceParts .. " parts)")
	local weather = {}
	for _, d in fx:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled and string.sub(d.Name, 1, 8) == "Weather_" then
			weather[string.sub(d.Name, 9)] = d.Rate
		end
	end
	truthy(weather[b.weather.kind] ~= nil, label .. ": its weather (" .. b.weather.kind .. ") is falling")
	local nWeather = 0
	for _ in weather do nWeather += 1 end
	truthy(nWeather <= Budget.MaxWeatherEmitters, label .. ": at most " .. Budget.MaxWeatherEmitters .. " weather emitters")

	-- the chip names the stratum and what comes next
	truthy(string.find(chip.Text, b.name, 1, true) ~= nil, label .. ": the chip names " .. b.name .. " (" .. chip.Text .. ")")
	local nextIdx = EnvBands.nextBand(bands, depth)
	if nextIdx then
		truthy(string.find(chip.Text, bands[nextIdx].emoji, 1, true) ~= nil, label .. ": and the next stratum")
	end
	bandLooks[label] = { props = props, pieceParts = pieceParts, weather = weather, kinds = kinds, m = measure(label) }
	return v, start, pal, origin
end

--============================================================================ §4 + §5 bank, and the glide in

local glideWorst, glideTotal = 0, 0
do
	-- §5: from the hub into Bronze 1, the Ambient glides: no write moves more than a fraction of the gap
	endCurrentRun()
	run(4, 1 / 30) -- settle in the hub
	local fromR = Lighting.Ambient.R
	Enter:simulateFireServer(plr, 1)
	h:advance(0.05)
	ORIGINAL = snapshot(myVault())
	local wantR = bands[1].lighting.Ambient[1] / 255
	local prev = Lighting.Ambient.R
	local overshoot = false
	run(4, 1 / 30, function()
		local cur = Lighting.Ambient.R
		glideWorst = math.max(glideWorst, math.abs(cur - prev))
		if (wantR - fromR) * (cur - wantR) > 1e-4 then overshoot = true end
		prev = cur
	end)
	glideTotal = math.abs(wantR - fromR)
	truthy(glideTotal > 0.03, string.format("§5 (the bank's Ambient differs from the hub's: %.3f)", glideTotal))
	truthy(glideWorst <= 0.15 * glideTotal + 1e-6,
		string.format("§5 hub -> vault glides: the biggest single step is %.1f%% of the change", 100 * glideWorst / math.max(glideTotal, 1e-9)))
	eq(overshoot, false, "§5 and never overshoots")
	print(string.format("  §5 hub -> Bank Vault: Ambient.R %.3f -> %.3f, biggest single frame %.1f%% of the change, overshoot %s",
		fromR, wantR, 100 * glideWorst / math.max(glideTotal, 1e-9), tostring(overshoot)))
end
local bankVault, bankStart, bankPal, bankOrigin = checkBand("bank (Bronze 1)", 1, "bank")

--============================================================================ §6 the obby, read at a glance

do
	local v = myVault()
	local model = {}
	local pad1 = v:FindFirstChild("Step_0_1")
	truthy(pad1 ~= nil, "§6 (Bronze 1 has a shaft)")
	-- walk to pad 1's cell floor, then step up onto the pad
	local top = pad1.Position + Vector3.new(0, pad1.Size.Y / 2, 0)
	walkTo(Vector3.new(top.X, hrp.Position.Y, top.Z))
	hrp.CFrame = CFrame.new(top + Vector3.new(0, Config.Run.RunnerRootHeight, 0))
	local sawCrack, sawCrackColour, sawGone, sawDebris, paintedWhileGone, sawFlash, back = false, false, false, false, false, false, false
	local padColour = c3(bankPal.pad)
	local goneBefore = false -- the server's state when this frame's client code ran
	where = "bank, on the pads"
	run(Config.Ascent.CrumbleSeconds + Config.Ascent.RespawnSeconds + 1.5, 1 / 30, function()
		if fx:FindFirstChild("PadCrack") then sawCrack = true end
		if pad1.Transparency < 0.5 and not sameColor(pad1.Color, padColour, 0.03) and not sawGone then sawCrackColour = true end
		-- a pad the server had ALREADY dropped when the client last ran must carry no crack
		if goneBefore and pad1.Transparency > 0.5 and fx:FindFirstChild("PadCrack") then paintedWhileGone = true end
		goneBefore = pad1.Transparency > 0.5
		if pad1.Transparency > 0.5 and not sawGone then
			sawGone = true
			-- the runner falls: nobody stands where a pad has gone (this file used to leave them hovering
			-- there, and a pad that returns under a runner is cracking again at once, never flashing)
			hrp.CFrame = CFrame.new(top.X, bankOrigin.Y + Config.Run.RunnerRootHeight, top.Z)
		end
		if fx:FindFirstChild("Debris") then sawDebris = true end
		if sawGone and pad1.Transparency < 0.5 then
			back = true
			-- the flash pulls EVERY channel toward white; the crack tint raises R toward its red and drops
			-- G and B, so R alone cannot tell the two apart (it used to: a fully cracked bank pad is 9/255
			-- redder than a whole one, and passed for the flash)
			if pad1.Color.G > padColour.G + 0.02 or pad1.Color.B > padColour.B + 0.02 then sawFlash = true end
		end
	end)
	truthy(sawCrack, "§6 standing on a pad cracks it (crack lines on its top)")
	truthy(sawCrackColour, "§6 and pulls its colour toward the crack before it goes")
	truthy(sawGone, "§6 (the SERVER crumbled it)")
	eq(paintedWhileGone, false, "§6 no crack is drawn on a pad the server says is gone")
	truthy(sawDebris, "§6 debris falls when it goes")
	truthy(back, "§6 (the server brought it back)")
	truthy(sawFlash, "§6 and it flashes as it returns")
	run(1, 1 / 30)
	truthy(sameColor(pad1.Color, padColour, 2 / 255), "§6 then it is the stratum's pad colour again")
	-- back down off the pad onto the floor for what follows
	hrp.CFrame = CFrame.new(top.X, bankOrigin.Y + Config.Run.RunnerRootHeight, top.Z + 7)
	run(0.5, 1 / 30)
	local _ = model
end

--============================================================================ §7 the collapse closes in, and the end clears it

do
	local v = myVault()
	local c = fx:FindFirstChild("CeilingDust")
	local s = fx:FindFirstChild("PlaneSparks")
	truthy(c ~= nil and s ~= nil, "§7 ceiling dust and plane sparks are up during a run")
	local dust0 = c and c:FindFirstChild("Dust") and c.Dust.Rate or 0
	local spark0 = s and s:FindFirstChild("Sparks") and s.Sparks.Rate or 0
	local cc = Lighting:FindFirstChild("FxColorCorrection")
	local contrast0 = cc.Contrast
	-- stand on storey 0 while the plane rises toward us
	hrp.CFrame = CFrame.new(hrp.Position.X, bankOrigin.Y + Config.Run.RunnerRootHeight, hrp.Position.Z)
	local maxDust, maxSpark, maxContrast = dust0, spark0, contrast0
	where = "bank, collapse closing"
	run(60, 1 / 15, function()
		if myVault() == nil then return false end
		local cd = fx:FindFirstChild("CeilingDust")
		local ps = fx:FindFirstChild("PlaneSparks")
		if cd and cd:FindFirstChild("Dust") then maxDust = math.max(maxDust, cd.Dust.Rate) end
		if ps and ps:FindFirstChild("Sparks") then maxSpark = math.max(maxSpark, ps.Sparks.Rate) end
		maxContrast = math.max(maxContrast, cc.Contrast)
	end)
	truthy(maxDust > dust0 + 3, string.format("§7 dust thickens as the collapse closes in (%.1f -> %.1f /s)", dust0, maxDust))
	truthy(maxSpark > spark0 + 5, string.format("§7 sparks too (%.1f -> %.1f /s)", spark0, maxSpark))
	truthy(maxContrast > contrast0 + 0.02, string.format("§7 and the grade hardens (contrast %.3f -> %.3f)", contrast0, maxContrast))
	eq(myVault(), nil, "§7 (the collapse took the runner who stood still)")
	run(1, 1 / 30)
	local left = {}
	for _, d in fx:GetChildren() do
		if not (string.sub(d.Name, 1, 4) == "Door" or string.sub(d.Name, 1, 11) == "PortalSign_" or d.Name == "Debris") then
			table.insert(left, d.Name)
		end
	end
	eq(#left, 0, "§7 the run's end clears every prop, piece, host and drop (left: " .. table.concat(left, ",") .. ")")
	truthy(string.find(chip.Text, "Hub", 1, true) ~= nil, "§7 the chip is back in the hub")
	local _ = v
end

--============================================================================ §8 strata, by escaping deeper

do
	-- escape Bronze 1, 2, 3 to reach floor 4 (a blend floor: half bank, half tomb)
	for f = 1, 3 do
		truthy(escape(1), "§8 (escaped Bronze floor " .. f .. ")")
	end
	h:advance(0.5)
	local _v4, start4, pal4 = checkBand("blend (Bronze 4)", 1, "bank")
	eq(start4.floor, 4, "§8 (Bronze floor 4)")
	local tombPad = bands[2].palette.pad
	local blended = pal4.t > 0.25 and pal4.t < 0.75
	truthy(blended, string.format("§8 floor 4 is a blend floor (t = %.2f)", pal4.t))
	local kinds = bandLooks["blend (Bronze 4)"].kinds
	truthy(kinds.PropBulb and kinds.PropFlame, "§8 its ceilings hang both strata's props (lamps and braziers)")
	local w = bandLooks["blend (Bronze 4)"].weather
	truthy(w.glitter ~= nil and w.sand ~= nil, "§8 and both strata's weather, capped together")
	truthy(VaultEnv.contrast(pal4.pad, pal4.floor) >= Config.Env.MinPadContrast, "§8 the blend floor's pads still read")
	local _ = tombPad
	eq(#announced > 0 and announced[#announced] or "", "🏦 BANK VAULT", "§8 floor 4 is still the bank: no new card")
	local flashesBefore = flashes
	truthy(escape(1), "§8 (escaped Bronze floor 4)")
	h:advance(0.5)
	checkBand("tomb (Bronze 5)", 1, "tomb")
	eq(announced[#announced] == "<flash>" and announced[#announced - 1] or announced[#announced], "🏺 PYRAMID TOMB",
		"§8 the first run in the tomb gets its card")
	truthy(flashes > flashesBefore, "§8 and the fanfare: this player has never been this deep")
	-- a second tomb run: no card
	local cardsBefore = #announced
	endCurrentRun()
	run(1, 1 / 30)
	checkBand("tomb again (Bronze 5)", 1, "tomb")
	eq(#announced, cardsBefore, "§8 the same stratum twice in a row gets no second card")
	endCurrentRun()
	for f = 5, 13 do
		truthy(escape(1), "§8 (escaped Bronze floor " .. f .. ")")
	end
	h:advance(0.5)
	local _, start14 = checkBand("reactor (Bronze 14)", 1, "reactor")
	eq(start14.floor, 14, "§8 (Bronze floor 14)")
	-- the reactor's ring turns
	local ring = nil
	for _, d in fx:GetChildren() do if d.Name == "Ring" then ring = d; break end end
	local a = ring and ring.CFrame
	run(1, 1 / 30)
	truthy(ring ~= nil and (ring.CFrame.Position - a.Position).Magnitude > 0.5, "§8 the reactor ring over the vault turns")
	local _s, silverStart = checkBand("frozen (Silver 1)", 2, "frozen")
	eq(silverStart.floor, 1, "§8 (Silver floor 1 is depth " .. VaultEnv.depth(Config, 2, 1) .. ")")
	local beams = 0
	for _, d in fx:GetDescendants() do if d.ClassName == "Beam" and d.Enabled then beams += 1 end end
	truthy(beams >= 1, "§8 aurora ribbons over the frozen vault (" .. beams .. " beams)")
	checkBand("volcano (Gold 1)", 3, "volcano")
	truthy(string.find(chip.Text, "floor", 1, true) == nil, "§8 the deepest stratum has no 'next' (" .. chip.Text .. ")")
	endCurrentRun()
	run(2, 1 / 30)
end

--============================================================================ §5 the glide out

do
	Enter:simulateFireServer(plr, 3)
	h:advance(0.05)
	run(4, 1 / 30)
	local fromR = Lighting.Ambient.R
	endCurrentRun()
	local prev, worst = Lighting.Ambient.R, 0
	run(4, 1 / 30, function()
		worst = math.max(worst, math.abs(Lighting.Ambient.R - prev))
		prev = Lighting.Ambient.R
	end)
	local total = math.abs(Lighting.Ambient.R - fromR)
	truthy(total > 0.05, "§5 (the volcano's Ambient differs from the hub's)")
	truthy(worst <= 0.15 * total + 1e-6, string.format("§5 vault -> hub glides too (biggest step %.1f%% of the change)", 100 * worst / math.max(total, 1e-9)))
	near(Lighting.Ambient.R * 255, Config.Env.Hub.lighting.Ambient[1], 3, "§5 and arrives at the hub's own light")
	print(string.format("  §5 Volcano Temple -> hub: biggest single frame %.1f%% of the change", 100 * worst / math.max(total, 1e-9)))
end

--============================================================================ §9 budgets

do
	print(string.format("  measured %d frames; peaks: parts %d (%s), emitters %d (%s), %.1f particles/s (%s), lights %d, beams %d",
		measured, peak.parts, tostring(peakWhere.parts), peak.emitters, tostring(peakWhere.emitters), peak.rate,
		tostring(peakWhere.rate), peak.lights, peak.beams))
	for label, l in bandLooks do
		print(string.format("    %-24s parts %3d  emitters %d  %.1f/s  beams %d  lights %d", label, l.m.parts, l.m.emitters, l.m.rate, l.m.beams, l.m.lights))
	end
	truthy(peak.parts <= Budget.MaxLocalParts, string.format("§9 local parts never above %d (peak %d)", Budget.MaxLocalParts, peak.parts))
	truthy(peak.emitters <= Budget.MaxEmitters, string.format("§9 emitters never above %d (peak %d)", Budget.MaxEmitters, peak.emitters))
	truthy(peak.rate <= Budget.MaxEmitterRate, string.format("§9 particles/s never above %d (peak %.1f)", Budget.MaxEmitterRate, peak.rate))
	truthy(peak.lights <= Budget.MaxLights, string.format("§9 lights never above %d (peak %d)", Budget.MaxLights, peak.lights))
	truthy(peak.beams <= Budget.MaxBeams, string.format("§9 beams never above %d (peak %d)", Budget.MaxBeams, peak.beams))
	-- nothing stacks: the same vault entered again parents exactly as many parts as the first time
	local counts = {}
	for pass = 1, 3 do
		for _, tier in { 1, 2, 3 } do
			Enter:simulateFireServer(plr, tier)
			h:advance(0.05)
			run(3, 1 / 30)
			local m = measure("re-entry")
			counts[tier] = counts[tier] or {}
			counts[tier][pass] = m.parts
			local names = {}
			for _, d in fx:GetChildren() do names[d.Name] = (names[d.Name] or 0) + 1 end
			counts[tier]["names" .. pass] = names
			endCurrentRun()
			run(0.5, 1 / 30)
		end
	end
	for _, tier in { 1, 2, 3 } do
		if not (counts[tier][1] == counts[tier][2] and counts[tier][2] == counts[tier][3]) then
			for name, n in counts[tier].names2 do
				if (counts[tier].names1[name] or 0) ~= n then print("    differs: " .. name .. " " .. tostring(counts[tier].names1[name]) .. " -> " .. n) end
			end
		end
		truthy(counts[tier][1] == counts[tier][2] and counts[tier][2] == counts[tier][3],
			string.format("§9 tier %d entered three times parents %d / %d / %d parts: nothing stacks", tier,
				counts[tier][1], counts[tier][2], counts[tier][3]))
	end
	local left = 0
	for _, d in fx:GetChildren() do
		if not (string.sub(d.Name, 1, 4) == "Door" or string.sub(d.Name, 1, 11) == "PortalSign_" or d.Name == "Debris") then left += 1 end
	end
	eq(left, 0, "§9 and back in the hub, nothing of any vault is left parented")
end

--============================================================================ §10 the leak rules

do
	eq(serverCalls - ownCalls, 0, string.format("§10 the client fired no remote, ever (%d calls, all %d of them this file's)", serverCalls, ownCalls))
	local bad = nil
	for _, d in fx:GetDescendants() do
		if d:IsA("BasePart") then
			if d.CanCollide or d.CanQuery or d.CanTouch or not d.Anchored then bad = bad or d.Name end
		end
	end
	eq(bad, nil, "§10 every part the client made is anchored, non-collidable, non-queryable, non-touchable")
	local changed = nil
	for part, s in otherSnapshot do
		if part.Parent ~= nil and (part.Color ~= s.Color or part.Reflectance ~= s.Reflectance) then changed = changed or part.Name end
	end
	eq(changed, nil, "§10 the neighbour's vault was never repainted (this client only dresses its own)")
	local hub = h.workspace:FindFirstChild("Hub")
	local hubAttrs = 0
	for _, d in hub:GetDescendants() do
		for k in d:GetAttributes() do
			if k ~= "TierIndex" and k ~= "PetId" then hubAttrs += 1 end
		end
	end
	eq(hubAttrs, 0, "§10 no attribute the server did not write appears in the hub")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. tostring(e))
end
local frameErrors = 0
for _, w in h.warnings do
	if string.find(w, "[VaultFx]", 1, true) then frameErrors += 1; print("  warning: " .. w) end
end
eq(frameErrors, 0, "the client never warned (no frame error, no invalid config)")

print(string.format("vault-runners env: %d passed, %d failed", passed, failed))
