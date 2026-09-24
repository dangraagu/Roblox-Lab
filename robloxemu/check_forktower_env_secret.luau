-- Fork Tower — the environment reveals nothing. Run: luau check_forktower_env_secret.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- The one piece of information in Fork Tower is the inscription a player pays 1.1 s to read
-- (REVIEW-2/3), and the half of every floor it sells is a server-only secret (REVIEW-4,
-- check_forktower_plansecret.luau). The environment work (src/client/Ambience.client.luau,
-- src/shared/TowerArt.luau, src/shared/Climb.luau) draws a great deal on the client, so this file
-- holds it to four things:
--
--   A. WHAT IT READS. Statically, from the sources the bundle ships: the only attributes it reads are
--      `Owner` (which lane is mine) and `Exit` (a section's top, which exists only after the door
--      was chosen); it writes none; it never names a door, a sign, the inscription, the trap or the
--      Fork module, and never talks to a remote. Adding any of that turns this red on purpose, so
--      the change has to come with a reason.
--   B. WHERE IT DRAWS, at every unread fork of a real run: nothing it places by rule comes within
--      20 studs of either door or onto the fork pad, and its scenery walls are mirror images of each
--      other about the lane's centre line. Nothing hangs on one door and not the other.
--   C. THAT A READ CHANGES NOTHING IT DRAWS. At an unread fork, everything the ambience draws that
--      does not move by itself (lighting, post-fx, sky, the walls, the chip) is recorded, the
--      inscription is read, and it is recorded again from the same place: identical. The read
--      dresses the doors; the ambience does not react to it. Both records are taken under a quiet
--      sky (no lightning bolt for 1.5 s): a flash is random in time and would differ by itself.
--   D. NO SECRET IN IT. After the run, the player's saved floor secrets are read from the record and
--      every name, text, attribute and number of EVERYTHING the ambience made during the run
--      (parented at the end or pooled out of the scene) is swept for them.
--
-- Critters, weather particles and lightning are ambient: spawned at random around the camera and
-- drifting across the view, or random in time. They are left out of B and C (they change by
-- themselves) and included in A and D (what they could read, what they could carry).

local Harness = require("./emu/harness")
local bundle = require("./build/fork-tower")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

--======================================================================= A. what it reads

local AMBIENCE_SOURCES = { "client/Ambience.client", "shared/TowerArt", "shared/Climb" }
local function codeOf(key)
	local entry = bundle[key]
	assert(entry ~= nil, "no bundle entry " .. key)
	-- comments out: the rules below are about code, and the comments explain what the code avoids
	local lines = {}
	for line in string.gmatch(entry.source .. "\n", "([^\n]*)\n") do
		local cut = string.find(line, "--", 1, true)
		lines[#lines + 1] = if cut then string.sub(line, 1, cut - 1) else line
	end
	return table.concat(lines, "\n")
end
do
	local attrs = {}
	for _, key in AMBIENCE_SOURCES do
		local code = codeOf(key)
		for name in string.gmatch(code, "GetAttribute%(%s*\"([^\"]+)\"") do attrs[name] = true end
		truthy(string.find(code, "SetAttribute", 1, true) == nil, key .. " writes no attribute")
		truthy(string.find(code, "GetAttributes", 1, true) == nil, key .. " never enumerates attributes")
		for _, token in { "Door", "Sign", "Marked", "TellKind", "RuleInverted", "Inscription", "Penalty", "Theme",
			"floorSecrets", "legacySecrets", "isTrap", "trapDoor", "ProximityPrompt", "\"Read\"", "\"Fork\"",
			"FireServer", "InvokeServer", "OnClientEvent", "RemoteEvent", "RemoteFunction", "ForkRemotes" } do
			truthy(string.find(code, token, 1, true) == nil, key .. " never mentions " .. token)
		end
	end
	local names = {}
	for n in attrs do names[#names + 1] = n end
	table.sort(names)
	eq(table.concat(names, ","), "Exit,Owner", "the only attributes the ambience reads are Owner (my lane) and Exit (a chosen section's top)")
	-- the only children it looks up by name in a lane
	local code = codeOf("client/Ambience.client")
	local finds = {}
	for n in string.gmatch(code, "FindFirstChild%(%s*\"([^\"]+)\"") do finds[n] = true end
	for n in string.gmatch(code, "FindFirstChild%(%s*\"([^\"]+)\" %.%.") do finds[n .. "<n>"] = true end
	local allowed = { Towers = true, SummitPad = true, leaderstats = true, HumanoidRootPart = true, Reveal = true,
		["ForkPad_"] = true, ["Section_"] = true, ["ForkPad_<n>"] = true, ["Section_<n>"] = true }
	local stray = {}
	for n in finds do if not allowed[n] then stray[#stray + 1] = n end end
	table.sort(stray)
	eq(#stray, 0, "the ambience looks up nothing by name beyond the pads, a section, the Reveal card and leaderstats ("
		.. table.concat(stray, ", ") .. ")")
end

--======================================================================= the world

local h = Harness.new({ bundle = bundle, name = "fork-tower", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = mod("Config")
local FLOORS = Config.Tower.Floors
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001 -- in memory: nothing flies here; B and C are about the scenery

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Reader", 6262)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okAmb, errAmb = h:tryRun("client/Ambience.client")
truthy(okAmb, "Ambience.client loads (" .. tostring(errAmb) .. ")")
local folder = h.workspace:FindFirstChild("ForkLocalEnv")
local row = plr.PlayerGui:FindFirstChild("ForkHud"):FindFirstChild("Root"):FindFirstChild("AmbienceRow")
local chip = row.ChipSlot:FindFirstChild("BandChip")
local cam = h.workspace.CurrentCamera
local Lighting = h.Lighting

local lane
for _, f in h.workspace:FindFirstChild("Towers"):GetChildren() do
	if f:GetAttribute("Owner") == plr.UserId then lane = f end
end
local laneX = lane:FindFirstChild("LobbyPad").Position.X

local camAt = nil -- when set, the camera stays here (C records from one place)
-- D sweeps EVERYTHING the ambience made in the run, not only what happens to be parented at the end:
-- a pooled part that is unparented (a band the player left, a critter between lives) still exists
-- and could still carry something. So every frame adds whatever is in the folder to this set.
local made, madeCount = {}, 0
-- Lightning (the storm, floors 7-8) is random in TIME: a bolt shows for 0.14 s and lifts the colour
-- correction's Brightness by up to 0.3, which then decays with a 0.08 s half-life (Ambience.client).
-- It depends on nothing a fork carries, but a snapshot taken inside a flash differs from one taken
-- outside it, and C compares two snapshots taken ~9 s apart: measured 2026-09-24, 1 run in 12 failed
-- C at floor 8 on an unchanged tree ("C -0.015 ..." against the storm's -0.020). So each snapshot is
-- taken under a QUIET sky: no bolt seen for 1.5 s, by when the flash is ~2^-18 of its peak and the
-- client has written the band's own value back. Bolts come every 6-12 s, so a quiet sky always
-- arrives; the wait is bounded and counted (quietFailures), so C can never pass by not looking.
local simTime, lastBoltAt = 0, -math.huge
local function frame(dt)
	cam.CFrame = camAt or CFrame.new(hrp.Position + Vector3.new(0, 9, -22), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	for _, d in folder:GetDescendants() do
		if not made[d] then
			made[d] = true
			madeCount += 1
		end
	end
	for _, p in folder:GetChildren() do
		if p.Name == "Bolt" then lastBoltAt = simTime; break end
	end
end
local function run(seconds) for _ = 1, math.floor(seconds * 30 + 0.5) do frame(1 / 30) end end
local quietFailures, quietWaits = 0, 0
local function quietSky()
	for _ = 1, 30 * 20 do
		if simTime - lastBoltAt >= 1.5 then return end
		frame(1 / 30)
		quietWaits += 1
	end
	quietFailures += 1
end
local function standOn(part)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
end

local WALL_NAMES = { Pillar = true, Torch = true, Foliage = true, Bloom = true, Gear = true, Teeth = true, StormPuff = true, Lantern = true }
local CRITTER_NAMES = { WingL = true, WingR = true, Firefly = true, Leaf = true, ShootingStar = true }
local function isAmbient(p) return CRITTER_NAMES[p.Name] == true or p.Name == "WeatherHost" end

local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local function c3(c) return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)) end

-- everything the ambience draws that does not move by itself, as one sorted text
local function snapshot(): string
	local lines = {}
	local L = Lighting
	lines[#lines + 1] = string.format("L %.3f %.3f %.3f %s %s %s %.1f %.1f", L.ClockTime, L.Brightness, L.ExposureCompensation,
		c3(L.Ambient), c3(L.OutdoorAmbient), c3(L.FogColor), L.FogStart, L.FogEnd)
	local a = L:FindFirstChild("FxAtmosphere")
	lines[#lines + 1] = string.format("A %.3f %.3f %s %s %.3f %.3f", a.Density, a.Offset, c3(a.Color), c3(a.Decay), a.Glare, a.Haze)
	local sky = L:FindFirstChild("ForkSky")
	lines[#lines + 1] = string.format("S %d %.2f %.2f", sky.StarCount, sky.MoonAngularSize, sky.SunAngularSize)
	local b = L:FindFirstChild("FxBloom")
	lines[#lines + 1] = string.format("B %.3f %.2f %.3f", b.Intensity, b.Size, b.Threshold)
	local cc = L:FindFirstChild("FxColorCorrection")
	lines[#lines + 1] = string.format("C %.3f %.3f %.3f %s", cc.Brightness, cc.Contrast, cc.Saturation, c3(cc.TintColor))
	local sr = L:FindFirstChild("FxSunRays")
	lines[#lines + 1] = string.format("R %.3f %.3f", sr.Intensity, sr.Spread)
	lines[#lines + 1] = "chip " .. chip.Text
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") and WALL_NAMES[p.Name] then
			lines[#lines + 1] = string.format("W %s %.2f,%.2f,%.2f %.2f,%.2f,%.2f %s %.2f", p.Name,
				r2(p.Position.X), r2(p.Position.Y), r2(p.Position.Z), p.Size.X, p.Size.Y, p.Size.Z, c3(p.Color), r2(p.Transparency))
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function horizontal(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

--======================================================================= B + C, fork by fork

local clearanceWorst, clearanceWhere = math.huge, nil
local mirrorMissing, mirrorExample, mirrorChecked = 0, nil, 0
local readChanged, readExample = 0, nil
local wallsSeen = 0
for level = 1, FLOORS do
	local fork = lane:FindFirstChild("Fork_" .. level)
	local pad = fork:FindFirstChild("ForkPad_" .. level)
	local doors = { fork:FindFirstChild("Door_" .. level .. "_1"), fork:FindFirstChild("Door_" .. level .. "_2") }
	standOn(pad)
	camAt = nil
	run(3)
	-- C: freeze the camera where it is, let everything settle, record; read; settle; record again
	camAt = cam.CFrame
	run(8)
	quietSky()
	local before = snapshot()
	-- B: at this unread fork, nothing placed by rule near a door or on the pad; walls mirrored
	for _, p in folder:GetDescendants() do
		if p:IsA("BasePart") and not isAmbient(p) and p.Parent ~= nil and p.Transparency < 0.99 then
			for _, d in doors do
				local dist = horizontal(p.Position, d.Position) - math.max(p.Size.X, p.Size.Z) / 2
				if dist < clearanceWorst then
					clearanceWorst = dist
					clearanceWhere = string.format("%s at floor %d", p.Name, level)
				end
			end
			local half = Vector3.new(pad.Size.X / 2, 0, pad.Size.Z / 2)
			local rel = p.Position - pad.Position
			if math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and math.abs(rel.Y) <= 20 then
				clearanceWorst = -1
				clearanceWhere = p.Name .. " ON the fork pad of floor " .. level
			end
		end
	end
	local walls = {}
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") and WALL_NAMES[p.Name] then walls[#walls + 1] = p end
	end
	wallsSeen += #walls
	for _, p in walls do
		mirrorChecked += 1
		local want = Vector3.new(2 * laneX - p.Position.X, p.Position.Y, p.Position.Z)
		local found = false
		for _, q in walls do
			if q ~= p and q.Name == p.Name and (q.Position - want).Magnitude <= 0.05 and (q.Size - p.Size).Magnitude <= 0.01
				and c3(q.Color) == c3(p.Color) and math.abs(q.Transparency - p.Transparency) <= 0.02 then
				found = true
				break
			end
		end
		if not found then
			mirrorMissing += 1
			mirrorExample = mirrorExample or string.format("%s at %.1f,%.1f,%.1f (floor %d)", p.Name, p.Position.X, p.Position.Y, p.Position.Z, level)
		end
	end
	-- the read, from the same place
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	prompt.PromptButtonHoldBegan:Fire(plr)
	run(Config.Fork.ReadSeconds + 0.02)
	prompt.Triggered:Fire(plr)
	run(8)
	truthy(fork:GetAttribute("Read") == true, "floor " .. level .. ": the inscription was read")
	quietSky()
	local after = snapshot()
	if after ~= before then
		readChanged += 1
		if readExample == nil then
			local a, b = {}, {}
			for l in string.gmatch(before, "[^\n]+") do a[l] = true end
			for l in string.gmatch(after, "[^\n]+") do b[l] = true end
			for l in b do if not a[l] then readExample = "after the read: " .. l; break end end
			if readExample == nil then for l in a do if not b[l] then readExample = "gone after the read: " .. l; break end end end
			readExample = string.format("floor %d, %s", level, tostring(readExample))
		end
	end
	camAt = nil
	-- take the safe door and climb (the read told us which)
	local m1 = doors[1]:GetAttribute("Marked") == true
	local inv = pad:GetAttribute("RuleInverted") == true
	local marked = if m1 then 1 else 2
	local safe = 3 - (if inv then 3 - marked else marked)
	doors[safe]:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	run(0.5)
	local sec = lane:FindFirstChild("Section_" .. level)
	local plats = {}
	for _, c in sec:GetChildren() do
		local i = tonumber(string.match(c.Name, "^Plat_%d+_(%d+)$"))
		if i then plats[i] = c end
	end
	for i = 1, #plats do
		standOn(plats[i])
		run(0.6)
	end
	for _, c in sec:GetChildren() do
		if c:GetAttribute("Exit") == true then c.Touched:Fire(hrp) end
	end
	run(0.3)
end
truthy(clearanceWorst >= 20, string.format("at every unread fork, nothing the ambience places by rule comes within 20 studs of either door or onto the pad (closest %.1f: %s)",
	clearanceWorst, tostring(clearanceWhere)))
truthy(wallsSeen > 0, "the walls were drawn at the forks (" .. wallsSeen .. " wall parts checked)")
eq(mirrorMissing, 0, "every wall part has its mirror twin across the lane's centre line (" .. mirrorChecked .. " checked)"
	.. (if mirrorExample then "; e.g. " .. mirrorExample else ""))
eq(readChanged, 0, "at every one of " .. FLOORS .. " forks, reading the inscription changed nothing the ambience draws"
	.. (if readExample then " (" .. readExample .. ")" else ""))
eq(quietFailures, 0, "every C snapshot was taken under a quiet sky (no lightning bolt for 1.5 s; "
	.. string.format("%.1f s spent waiting for one over the run)", quietWaits / 30))

--======================================================================= D. no secret in it

h:advance(Config.Save.AutosaveSeconds + 1) -- let the autosave write the record
local rec = store:GetAsync("u_" .. plr.UserId)
local secrets = rec and rec.data and rec.data.floorSecrets
truthy(type(secrets) == "table" and #secrets == FLOORS, "the player's floor secrets are in their saved record")
do
	local wanted = {}
	for _, s in secrets or {} do
		wanted[s] = true
	end
	local strings = {}
	for s in wanted do
		strings[#strings + 1] = tostring(s)
		strings[#strings + 1] = string.format("%x", s)
		strings[#strings + 1] = string.format("%X", s)
	end
	local hits, where, swept = 0, nil, 0
	local function checkNumber(v, what)
		if type(v) == "number" and wanted[v] then
			hits += 1
			where = where or what
		end
	end
	local function checkString(v, what)
		if type(v) ~= "string" then return end
		for _, s in strings do
			if #s >= 4 and string.find(v, s, 1, true) then
				hits += 1
				where = where or what
			end
		end
	end
	local function sweep(inst)
		swept += 1
		checkString(inst.Name, "Name of " .. inst.Name)
		for k, v in inst:GetAttributes() do
			hits += 1 -- the ambience sets no attributes at all (A); any is a finding
			where = where or ("attribute " .. k .. " on " .. inst.Name)
			checkNumber(v, k); checkString(v, k)
		end
		local okText, text = pcall(function() return (inst :: any).Text end)
		if okText then checkString(text, "Text of " .. inst.Name) end
		if inst:IsA("BasePart") then
			for _, v in { inst.Position.X, inst.Position.Y, inst.Position.Z, inst.Size.X, inst.Size.Y, inst.Size.Z,
				inst.Transparency, inst.Color.R * 255, inst.Color.G * 255, inst.Color.B * 255 } do
				checkNumber(v, "a number on " .. inst.Name)
			end
		end
		local okRate, rate = pcall(function() return (inst :: any).Rate end)
		if okRate then checkNumber(rate, "Rate of " .. inst.Name) end
	end
	-- everything the ambience ever put in its folder during the run, parented now or pooled
	for _, d in folder:GetDescendants() do
		if not made[d] then made[d] = true; madeCount += 1 end
	end
	local names = {}
	for d in made do
		sweep(d)
		names[d.Name] = true
	end
	-- the sweep reached every band's scenery, the far pieces and the life, not a lucky few
	local missing = {}
	for _, n in { "Pillar", "Torch", "Foliage", "Bloom", "BloomHead", "Gear", "Teeth", "ClockDial", "StormPuff",
		"StormDeckPuff", "Lantern", "RingedPlanet", "ConstellationStar", "GalaxyCore", "CrownStar", "WingL",
		"Firefly", "Leaf", "ShootingStar", "WeatherHost", "Bolt" } do
		if not names[n] then missing[#missing + 1] = n end
	end
	eq(#missing, 0, "the sweep reached every band's walls, far pieces, critters, weather and lightning ("
		.. madeCount .. " instances made in the run; missing: " .. table.concat(missing, ", ") .. ")")
	for _, d in row:GetDescendants() do sweep(d) end
	for _, n in { "ForkSky", "ForkRestFocus", "FxAtmosphere", "FxBloom", "FxColorCorrection", "FxSunRays" } do
		local inst = Lighting:FindFirstChild(n)
		if inst then sweep(inst) end
	end
	sweep(Lighting)
	local lantern = hrp:FindFirstChild("ForkLantern")
	if lantern then sweep(lantern) end
	print(string.format("  D swept %d instances (%d made by the ambience in the run); C waited %.1f s in all for a quiet sky",
		swept, madeCount, quietWaits / 30))
	truthy(swept > 100, "the sweep covered everything the ambience made (" .. swept .. " instances)")
	eq(hits, 0, "no floor secret, in decimal or hex, in any name, text, attribute or number the ambience made"
		.. (if where then " (" .. where .. ")" else ""))
end

eq(#h:errors(), 0, "no script errors (" .. table.concat(h:errors(), " | ") .. ")")
print(string.format("fork tower env secret: %d passed, %d failed", passed, failed))
if failed > 0 then error("fork tower env secret check failed", 0) end
