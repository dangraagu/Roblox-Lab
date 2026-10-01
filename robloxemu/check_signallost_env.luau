-- SIGNAL LOST — the ENVIRONMENT (EYECANDY.md) through the real server and the real clients: src/client/Env.client,
-- Hud.client and Move.client in one harness, driven by tests/Bot.luau. RunService.RenderStepped and Heartbeat are
-- fired once per bot tick (0.1 s).
--
-- Run:  py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--       luau check_signallost_env.luau
--
-- The pure specs (EnvBands, EnvConfig, Hazards, Rest) prove the rules on data. This proves the GLUE: the band follows
-- the server's sector number and blends as modules open; the grade glides; built modules are dressed within the
-- rules on the real instances; budgets hold in every band; hazards come only where the design says, the ring is the
-- zone, walking on into the next module lets one fly past, a step out of the ring dodges and standing still is a hit; rest is refused
-- in vacuum with the reason and allowed in air; low gravity is on in vacuum only; nothing leaks.
--
-- Bands 3-7 are reached by copying each band's CONTENT (grade, palette, kit, weather, critters, exterior, hazards)
-- into band 2's slot IN MEMORY (the check's own copy of Config) before a transit, so each is seen on real sectors
-- without playing 60 of them. Bands 1 and 2 are reached by real play.

local Harness = require("./emu/harness")
local Bot = require("../signal-lost/tests/Bot")
local bundle = require("./build/signal-lost")

local h = Harness.new({ bundle = bundle, name = "signal-lost-env", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local RSx = h.ReplicatedStorage
local Config = h:_require(RSx:FindFirstChild("Config"))
local Dressing = h:_require(RSx:FindFirstChild("Dressing"))
local EnvBands = h:_require(RSx:FindFirstChild("EnvBands"))
local EnvBus = h:_require(RSx:FindFirstChild("EnvBus"))
local Env, Budget, Hz = Config.Env, Config.Budget, Config.Hazards
local bands = Env.Bands

-- Written out, not read from Config: a number checked against itself is not a check.
local INNER, WALLBAND, ITEM_LIM, DOORHALF = 15, 2.5, 9, 4 + 4

--=========================================================================== A. the shipped source
section("A. what the environment client can do, read off the shipped source")
for _, key in { "client/Env.client", "client/Move.client", "shared/EnvArt", "shared/Dressing", "shared/Hazards", "shared/Rest", "shared/EnvBus" } do
	local src = bundle[key] and bundle[key].source or ""
	truthy(#src > 0, key .. " is in the bundle")
	src = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	src = string.gsub(src, "%-%-[^\n]*", "")
	for _, bad in { "FireServer", "InvokeServer", "SetAttribute", "PointLight", "SpotLight", "SurfaceLight", "ServerStorage",
		"SignalDebug", "OnServerEvent", "PivotTo" } do
		truthy(string.find(src, bad, 1, true) == nil, key .. " never uses " .. bad)
	end
end
for _, mod in { "Station", "Trust", "Economy", "MazeGen", "Rng", "Meter" } do
	truthy(string.find(bundle["client/Env.client"].source, 'WaitForChild("' .. mod .. '")', 1, true) == nil,
		"Env.client does not require " .. mod .. " (it never sees a plan, a stream or the relay)")
end

--=========================================================================== boot
local okS = h:tryRun("server/Main.server")
truthy(okS, "the server loads")
local plr = h:join("Env", 4401)
h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local RS = h.game:GetService("RunService")
RS:setIsServer(false)
for _, c in { "client/Hud.client", "client/Env.client", "client/Move.client" } do
	local ok, err = h:tryRun(c)
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
local W = h.workspace
local LOCAL = W:FindFirstChild("SignalEnvLocal")
truthy(LOCAL ~= nil, "the environment's local folder exists")
local cc = h.Lighting:FindFirstChild("FxColorCorrection")
local frames = 0
local lastTint, maxJump = nil, 0
local hazardEvents = {}
EnvBus.on(function(kind, data)
	if kind == "hazard" then table.insert(hazardEvents, { phase = data.phase, name = data.name, inside = data.inside, at = h.scheduler:now() }) end
end)
local budgetViolations = {}
local peak = { dress = 0, perModule = 0, weather = 0, emitters = 0, critters = 0, exterior = 0, lights = 0, hazards = 0 }
local function audit()
	-- every frame: the budgets the design caps in code
	local dressParts, perModuleMax, weather, emitters, critters, exterior, lights, hazards = 0, 0, 0, 0, 0, 0, 0, 0
	for _, f in LOCAL.Dressing:GetChildren() do
		local n = 0
		for _, d in f:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
		dressParts += n
		perModuleMax = math.max(perModuleMax, n)
	end
	for _, d in LOCAL:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled ~= false then emitters += 1 end
		if d.ClassName == "PointLight" or d.ClassName == "SpotLight" or d.ClassName == "SurfaceLight" then lights += 1 end
	end
	for _, d in LOCAL.Weather:GetChildren() do if d:IsA("BasePart") then weather += 1 end end
	for _, d in LOCAL.Critters:GetChildren() do if d:IsA("BasePart") and d.Transparency < 1 then critters += 1 end end
	for _, d in LOCAL.Exterior:GetDescendants() do if d:IsA("BasePart") then exterior += 1 end end
	if LOCAL.Hazard:FindFirstChild("Debris") then hazards += 1 end
	peak.dress = math.max(peak.dress, dressParts); peak.perModule = math.max(peak.perModule, perModuleMax)
	peak.weather = math.max(peak.weather, weather); peak.emitters = math.max(peak.emitters, emitters)
	peak.critters = math.max(peak.critters, critters); peak.exterior = math.max(peak.exterior, exterior)
	peak.lights = math.max(peak.lights, lights); peak.hazards = math.max(peak.hazards, hazards)
	local function over(name, v, cap)
		if v > cap then table.insert(budgetViolations, string.format("%s %d > %d at t=%.1f", name, v, cap, h.scheduler:now())) end
	end
	over("dressing parts", dressParts, Budget.MaxDressParts)
	over("dressing parts in one module", perModuleMax, Budget.MaxDressPartsPerModule)
	over("weather emitters", weather, Budget.MaxWeather)
	over("active emitters", emitters, Budget.MaxEmitters)
	over("critters", critters, Budget.MaxCritters)
	over("exterior parts", exterior, Budget.MaxExteriorParts)
	over("light sources", lights, 0)
	over("hazards", hazards, Budget.MaxHazards)
end
local function frame()
	RS.RenderStepped:Fire(0.1)
	RS.Heartbeat:Fire(0.1)
	frames += 1
	local tc = cc.TintColor
	if tc and lastTint then
		local j = math.max(math.abs(tc.R - lastTint.R), math.abs(tc.G - lastTint.G), math.abs(tc.B - lastTint.B)) * 255
		if j > maxJump then maxJump = j end
	end
	lastTint = tc
	audit()
end
local bot = Bot.new(h, plr, { onTick = frame })
bot:waitSeconds(3)

local function rgbOf(c3) return { math.floor(c3.R * 255 + 0.5), math.floor(c3.G * 255 + 0.5), math.floor(c3.B * 255 + 0.5) } end
local function near(c3, t, tol)
	local c = rgbOf(c3)
	return math.abs(c[1] - t[1]) <= tol and math.abs(c[2] - t[2]) <= tol and math.abs(c[3] - t[3]) <= tol
end

--=========================================================================== what the openings show
-- The exterior is only eye candy if a player can SEE it, and the only ways out are the lifeboat's PlanetWindow and a
-- vacuum module's Glass pane. Geometry on the REAL instances (no renderer needed): an opening is an axis-aligned part;
-- a target is a ball (radius Size.X / 2) or a small part (its centre). A ray "shows" a target when it leaves the eye,
-- crosses the opening's plane inside the opening (0.2 studs in from its edges) and then meets the target.
local function normalAxis(op)
	local s = op.Size
	return if s.X <= s.Y and s.X <= s.Z then "X" elseif s.Y <= s.Z then "Y" else "Z"
end
local function crossesOpening(eye, dir, op)
	local n = normalAxis(op)
	local c, s = op.Position, op.Size
	if math.abs(dir[n]) < 1e-9 then return false end
	local t = (c[n] - eye[n]) / dir[n]
	if t <= 0 then return false end
	local p = eye + dir * t
	for _, a in { "X", "Y", "Z" } do
		if a ~= n and math.abs(p[a] - c[a]) > s[a] / 2 - 0.2 then return false end
	end
	return true
end
local function raySphere(o, d, c, r)
	local oc = o - c
	local b = oc:Dot(d)
	local disc = b * b - (oc:Dot(oc) - r * r)
	return disc >= 0 and (-b + math.sqrt(disc)) > 0
end
-- the share of an 11 x 11 grid of rays from `eye` through the opening that meet the ball
local function ballFill(eye, op, ball)
	local n = normalAxis(op)
	local axes = {}
	for _, a in { "X", "Y", "Z" } do if a ~= n then table.insert(axes, a) end end
	local c, s = op.Position, op.Size
	local hits = 0
	for i = 0, 10 do
		for j = 0, 10 do
			local off = { X = 0, Y = 0, Z = 0 }
			off[axes[1]] = (i / 10 - 0.5) * (s[axes[1]] - 0.4)
			off[axes[2]] = (j / 10 - 0.5) * (s[axes[2]] - 0.4)
			local pt = c + Vector3.new(off.X, off.Y, off.Z)
			if raySphere(eye, (pt - eye).Unit, ball.Position, ball.Size.X / 2) then hits += 1 end
		end
	end
	return hits / 121
end
local function seesPart(eye, op, part)
	return crossesOpening(eye, (part.Position - eye).Unit, op)
end
local function beaconsSeen(eye, op)
	local n = 0
	for i = 1, 30 do
		local b = LOCAL.Exterior:FindFirstChild("Beacon" .. i)
		if b and seesPart(eye, op, b) then n += 1 end
	end
	return n
end
local viewNotes = {}

--=========================================================================== B. the lifeboat
section("B. the lifeboat: its own grade, the exterior, no light source")
truthy(near(cc.TintColor, Env.Lifeboat.grade.tint, 2), "the lifeboat's grade after 3 s (" .. table.concat(rgbOf(cc.TintColor), ",") .. ")")
do
	local n = 0
	for _, d in LOCAL.Exterior:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	eq(n, Dressing.EXTERIOR_PARTS, "the exterior model is " .. Dressing.EXTERIOR_PARTS .. " parts (planet 2, dish 8, 30 beacons, beam, 3 crossers)")
	local lit = 0
	for i = 1, 30 do
		local b = LOCAL.Exterior:FindFirstChild("Beacon" .. i)
		if b and b.Material == Enum.Material.Neon then lit += 1 end
	end
	eq(lit, 0, "a new player: no relay beacon lit")
	local planet = LOCAL.Exterior.Planet
	truthy(planet.Size.X <= 2048 and planet.CanCollide == false and planet.CanQuery == false, "the planet is under 2048 studs, non-collidable, non-queryable")
	-- the lifeboat's window, from where a player looks out of it: both benches (they face it) and the spawn
	local window = W.Lifeboat.PlanetWindow
	local bowl = LOCAL.Exterior.DishBowl
	for _, v in {
		{ "bench 1", Vector3.new(W.Lifeboat.Benches.Bench1.Position.X, 5, W.Lifeboat.Benches.Bench1.Position.Z + 0.8) },
		{ "bench 2", Vector3.new(W.Lifeboat.Benches.Bench2.Position.X, 5, W.Lifeboat.Benches.Bench2.Position.Z + 0.8) },
		{ "the spawn", W.Lifeboat.HubSpawn.Position + Vector3.new(0, 5.5, 0) },
	} do
		local fill, nb, dish = ballFill(v[2], window, planet), beaconsSeen(v[2], window), seesPart(v[2], window, bowl)
		table.insert(viewNotes, string.format("lifeboat window from %s: planet %.0f %%, beacons %d / 30, dish %s", v[1], fill * 100, nb, tostring(dish)))
		truthy(fill >= 0.08, string.format("from %s the window shows the planet (%.0f %% of the window)", v[1], fill * 100))
		truthy(nb >= 25, string.format("from %s the window shows the relay beacons (%d of 30)", v[1], nb))
		truthy(dish, "from " .. v[1] .. " the window shows the Main Array's dish")
	end
	truthy(planet.Position.Y + planet.Size.Y / 2 < 0 or (planet.Position - window.Position).Magnitude > planet.Size.X / 2 + 300,
		"the planet stays far from the lifeboat")
end

do -- the lifeboat's benches are real Seats: sitting on one is rest (the hub has air)
	local restEv = {}
	local off = EnvBus.on(function(kind, data) if kind == "rest" then table.insert(restEv, data.resting) end end)
	local hum = plr.Character:FindFirstChildOfClass("Humanoid")
	hum.SeatPart = W.Lifeboat.Benches.Bench1
	bot:waitSeconds(0.3)
	eq(restEv[1], true, "sitting on a lifeboat bench is rest")
	hum.SeatPart = nil
	local p = bot:pos()
	bot:walkTo(Vector3.new(p.X - 3, 0, p.Z), "hub")
	bot:waitSeconds(0.2)
	eq(restEv[#restEv], false, "standing up and walking wakes you")
	off()
end

--=========================================================================== C. sector 1: band 1 by real play
section("C. sector 1 (DOCKING RING): the grade by sector, dressing on real modules")
truthy(bot:board(), "board the LIFT")
local transitTint = {}
for _ = 1, 32 do
	bot:tick()
	table.insert(transitTint, rgbOf(cc.TintColor))
	if bot:phase() == "sector" then break end
end
eq(bot:phase(), "sector", "arrived")
truthy(near(cc.TintColor, bands[1].grade.tint, 3), "after the 3 s ride the grade is the Docking Ring's (" .. table.concat(rgbOf(cc.TintColor), ",") .. ")")
truthy(maxJump <= 20, string.format("the grade glides: the biggest one-frame step in any tint channel was %.1f of 255", maxJump))
print(string.format("   measured: the ride's grade, biggest one-frame step %.1f of 255 in a tint channel", maxJump))

local function sectorModules()
	local out = {}
	for _, z in W.Station:GetChildren() do
		local sec = z:FindFirstChild("Sector")
		if sec then
			for _, m in sec.Modules:GetChildren() do table.insert(out, m) end
		end
	end
	return out
end
local function dressingAudit(bandIndex, label)
	local band = bands[bandIndex]
	local kitNames = {}
	for _, piece in Dressing.KITS[band.kit] do kitNames[piece.name] = true end
	local modules, dressed, wrongKit, placeBad, hueBad, paletteBad = 0, 0, 0, 0, 0, 0
	for _, m in sectorModules() do
		modules += 1
		local fl = m:FindFirstChild("Floor")
		local o = Vector3.new(fl.Position.X, fl.Position.Y + fl.Size.Y / 2, fl.Position.Z)
		local id = tonumber(string.match(m.Name, "%d+"))
		local folder
		for _, f in LOCAL.Dressing:GetChildren() do
			if string.find(f.Name, "_" .. id .. "_", 1, true) then folder = f end
		end
		if folder then
			dressed += 1
			local doors = {}
			for _, c in m:GetChildren() do
				local s = string.match(c.Name, "^Wall(%u)_Top$")
				if s then doors[s] = true end
			end
			for _, part in folder:GetChildren() do
				if not kitNames[part.Name] then
					-- foreshadowing may dress it with the NEXT band's kit
					local nextKit = bands[bandIndex + 1] and Dressing.KITS[bands[bandIndex + 1].kit]
					local ok = false
					for _, piece in nextKit or {} do if piece.Name == part.Name or piece.name == part.Name then ok = true end end
					if not ok then wrongKit += 1 end
				end
				local p, s = part.Position - o, part.Size
				local x0, x1, z0, z1 = p.X - s.X / 2, p.X + s.X / 2, p.Z - s.Z / 2, p.Z + s.Z / 2
				local hug = (x0 >= INNER - WALLBAND - 1e-3) or (x1 <= -INNER + WALLBAND + 1e-3) or (z0 >= INNER - WALLBAND - 1e-3) or (z1 <= -INNER + WALLBAND + 1e-3)
				local inItems = x1 > -ITEM_LIM and x0 < ITEM_LIM and z1 > -ITEM_LIM and z0 < ITEM_LIM
				local onDoor = false
				for side in doors do
					if side == "E" and x1 > INNER - 2.6 and z1 > -DOORHALF and z0 < DOORHALF then onDoor = true end
					if side == "W" and x0 < -INNER + 2.6 and z1 > -DOORHALF and z0 < DOORHALF then onDoor = true end
					if side == "N" and z1 > INNER - 2.6 and x1 > -DOORHALF and x0 < DOORHALF then onDoor = true end
					if side == "S" and z0 < -INNER + 2.6 and x1 > -DOORHALF and x0 < DOORHALF then onDoor = true end
				end
				if not hug or inItems or onDoor then placeBad += 1 end
				if part.Material == Enum.Material.Neon and not Dressing.hueOk(Config, rgbOf(part.Color)) then hueBad += 1 end
			end
			local wall = m:FindFirstChild("WallE") or m:FindFirstChild("WallE_A")
			if wall then
				local want = nil
				for bi = bandIndex, math.min(bandIndex + 1, #bands) do
					if near(wall.Color, bands[bi].palette.wall, 1) then want = bi end
				end
				if want == nil then paletteBad += 1 end
			end
		end
	end
	truthy(modules > 0 and dressed == modules, string.format("%s: every built module in range is dressed (%d of %d)", label, dressed, modules))
	eq(wrongKit, 0, label .. ": every piece is from this band's kit (or, foreshadowing, the next band's)")
	eq(placeBad, 0, label .. ": every piece hugs a wall, stays out of the item square and off every doorway's line (real instances)")
	eq(hueBad, 0, label .. ": nothing that glows comes within 30 degrees of a signal colour (real instances)")
	eq(paletteBad, 0, label .. ": the walls wear this band's palette on this client")
end

bot:waitSeconds(0.5)
dressingAudit(1, "sector 1")
do
	local lg = plr.Character.HumanoidRootPart:FindFirstChild("LowGravity")
	truthy(lg ~= nil and lg.Enabled == false, "in the dock (air) the low-gravity force is off")
end

--=========================================================================== D. vacuum: low gravity, rest refused
section("D. vacuum: low gravity on, REST refused with the reason; air: rest allowed")
local mods = bot:modules()
local here = bot:moduleAt(mods, bot:pos())
local vacNb
for n, lamp in mods[here].lamps do if lamp == "VACUUM" then vacNb = n end end
truthy(bot:cross(mods, here, vacNb, "sector"), "into a vacuum module")
bot:waitSeconds(0.3)
do
	local lg = plr.Character.HumanoidRootPart:FindFirstChild("LowGravity")
	truthy(lg ~= nil and lg.Enabled == true, "in vacuum the low-gravity force is on")
	truthy(lg and math.abs(lg.Force.Y - 13.5 * 196.2 * 0.8) < 1, string.format("lifting 80 %% of the weight (%.1f)", lg and lg.Force.Y or -1))
	local refusals = {}
	local off = EnvBus.on(function(kind, data) if kind == "restRefused" then table.insert(refusals, data.reason) end end)
	plr.PlayerGui.SignalHud.Root.RestButton.Activated:Fire()
	bot:waitSeconds(0.2)
	off()
	eq(refusals[1], Config.Rest.Text.NoAir, "REST in vacuum is refused with the reason")
	eq(plr.PlayerGui.SignalHud.Root.Toast.Text, Config.Rest.Text.NoAir, "and the HUD shows it (never a silent no-op)")
	-- the cracked glass overhead, from the module's centre and from four points 6 studs off it diagonally: the
	-- exterior must be up where the glass looks, wherever in the module the player stands
	local vm = bot:modules()[vacNb].folder
	local glass = vm:FindFirstChild("Glass")
	truthy(glass ~= nil, "a vacuum module has a glass pane overhead")
	if glass then
		local fl = vm.Floor
		local top = fl.Position.Y + fl.Size.Y / 2
		for _, off in { { 0, 0 }, { 6, 6 }, { -6, -6 }, { 6, -6 }, { -6, 6 } } do
			bot:walkTo(Vector3.new(glass.Position.X + off[1], 0, glass.Position.Z + off[2]), "sector")
			bot:waitSeconds(0.2)
			local eye = Vector3.new(glass.Position.X + off[1], top + 5, glass.Position.Z + off[2])
			local planet = LOCAL.Exterior.Planet
			local fill, nb, dish = ballFill(eye, glass, planet), beaconsSeen(eye, glass), seesPart(eye, glass, LOCAL.Exterior.DishBowl)
			local where = if off[1] == 0 then "the module's centre" else string.format("(%+d, %+d) off it", off[1], off[2])
			table.insert(viewNotes, string.format("vacuum glass from %s: planet %.0f %%, beacons %d / 30, dish %s", where, fill * 100, nb, tostring(dish)))
			truthy(fill >= 0.08, string.format("from %s the glass shows the planet (%.0f %% of the pane)", where, fill * 100))
			if off[1] == 0 then
				truthy(nb >= 25, string.format("from %s the glass shows the relay beacons (%d of 30)", where, nb))
				truthy(dish, "from " .. where .. " the glass shows the Main Array's dish")
			end
		end
		bot:walkTo(Vector3.new(glass.Position.X, 0, glass.Position.Z), "sector")
	end
	for _, note in viewNotes do print("   measured: " .. note) end
end
truthy(bot:cross(bot:modules(), vacNb, here, "sector"), "back into the air")
bot:waitSeconds(2.2)
do
	local restOn = {}
	local off = EnvBus.on(function(kind, data) if kind == "rest" then table.insert(restOn, data.resting) end end)
	plr.PlayerGui.SignalHud.Root.RestButton.Activated:Fire()
	bot:waitSeconds(0.3)
	eq(restOn[1], true, "REST in an air module: resting")
	truthy(h.Lighting:FindFirstChild("SignalRestFocus").Enabled, "the view softens")
	eq(plr.PlayerGui.SignalHud.Root.Hint.Text, Config.Rest.Text.Resting, "the HUD says what rest means")
	local p = bot:pos()
	bot:walkTo(Vector3.new(p.X + 4, 0, p.Z), "sector")
	bot:waitSeconds(0.3)
	eq(restOn[#restOn], false, "moving wakes you")
	off()
end

--=========================================================================== E. band 1: no hazards; the blend into band 2
section("E. sectors 1-4: no hazards in the tutorial band; sector 4 blends toward HYDROPONICS as it opens")
local function playOn(label)
	local r = bot:playSector(600)
	if r == "blackout" then
		bot:waitPhase("sector", 6)
		r = bot:playSector(600)
	end
	truthy(r == "spliced", label .. " spliced (" .. tostring(r) .. ")")
	truthy(bot:toRelayPiece("FloorHatch"), label .. ": the floor hatch")
	bot:waitPhase("sector", 6)
end
playOn("sector 1")
playOn("sector 2")
playOn("sector 3")
eq(#hazardEvents, 0, "no hazard in the Docking Ring (sectors 1-3)")
eq(bot:state().k, 4, "in sector 4")
local tintAt = {}
local watch = function()
	local st = bot:state()
	if st and st.k == 4 and st.visited then
		tintAt[st.visited] = rgbOf(cc.TintColor)
	end
end
local oldTick = bot.onTick
bot.onTick = function(self) oldTick(self); watch() end
playOn("sector 4")
bot.onTick = oldTick
do
	local vs = {}
	for v in tintAt do table.insert(vs, v) end
	table.sort(vs)
	local first, last = tintAt[vs[1]], tintAt[vs[#vs]]
	local hydro = bands[2].grade.tint
	local function dist(c, t) return math.abs(c[1] - t[1]) + math.abs(c[2] - t[2]) + math.abs(c[3] - t[3]) end
	truthy(#vs >= 2 and dist(last, hydro) < dist(first, hydro), string.format("opening sector 4's modules moves the grade toward Hydroponics (%s -> %s over %d..%d modules)",
		table.concat(first or {}, ","), table.concat(last or {}, ","), vs[1] or -1, vs[#vs] or -1))
end
eq(#hazardEvents, 0, "still no hazard in sector 4")
eq(bot:state().k, 5, "sector 5: HYDROPONICS")
bot:waitSeconds(1)
truthy(near(cc.TintColor, bands[2].grade.tint, 4), "the grade is Hydroponics' (" .. table.concat(rgbOf(cc.TintColor), ",") .. ")")
dressingAudit(2, "sector 5")

--=========================================================================== F. hazards through the real client
section("F. the first hazard: after 30 s of eligible time, only in vacuum, the ring is the zone")
-- shuttle between a vacuum module and air: stand still in vacuum while AIR >= 10 (the eligible time), refill in air
local function vacuumPair()
	-- an air module with a vacuum neighbour behind a lamp; when none is known yet, walk on through air until one is
	for _ = 1, 12 do
		local ms = bot:modules()
		local cur = bot:moduleAt(ms, bot:pos())
		bot:recordHere()
		for id, r in ms do
			if bot.kindOf[id] == "AIR" then
				for n, lamp in r.lamps do
					if lamp == "VACUUM" then return id, n end
				end
			end
		end
		local step = nil
		for id, r in ms do
			if bot.kindOf[id] == "AIR" then
				for n, lamp in r.lamps do
					if lamp == "AIR" and not ms[n] then step = { id, n } end
				end
			end
		end
		if not step then return nil end
		local path = bot:route(ms, bot:hatches(), cur, step[1])
		if path then for i = 2, #path do bot:cross(bot:modules(), path[i - 1], path[i], "sector") end end
		bot:cross(bot:modules(), step[1], step[2], "sector")
		bot:recordHere()
	end
	return nil
end
local spawnEv, spawnAt, airAtSpawn, eligibleSince = nil, nil, nil, 0
local stats = { visits = 0, standVacuum = 0 }
do
	-- a NEW sector: forget what the bot learned in the last one. Module ids repeat from sector to sector, and a
	-- stale "AIR" once sent this shuttle to refill in a vacuum module until it blacked out (2 of 6 runs failed).
	bot.kindOf = {}
	bot:recordHere()
	for visit = 1, 12 do
		local a, v = vacuumPair()
		if not a then break end
		local ms = bot:modules()
		local cur = bot:moduleAt(ms, bot:pos())
		if cur ~= a then
			local path = bot:route(ms, bot:hatches(), cur, a)
			if path then for i = 2, #path do bot:cross(bot:modules(), path[i - 1], path[i], "sector") end end
		end
		bot:cross(bot:modules(), a, v, "sector")
		stats.visits += 1
		-- stand still until AIR is under 10.5 or a hazard spawns
		for _ = 1, 150 do
			bot:tick()
			local st = bot:state()
			for _, e in hazardEvents do
				if e.phase == "warn" and not spawnEv then spawnEv = e; spawnAt = h.scheduler:now(); airAtSpawn = st.air end
			end
			if spawnEv or st.air < 10.5 then break end
			stats.standVacuum += 0.1
		end
		if spawnEv then break end
		bot:cross(bot:modules(), v, a, "sector")
		bot:refill()
	end
end
truthy(spawnEv ~= nil, string.format("a hazard came (after %d vacuum visits, %.1f s standing in vacuum)", stats.visits, stats.standVacuum))
print(string.format("   measured: the first hazard of the session came on vacuum visit %d, after %.1f s standing still in vacuum in HYDROPONICS (sector %d), AIR %.1f s at the spawn",
	stats.visits, stats.standVacuum, bot:state().k, airAtSpawn or -1))
if spawnEv then
	truthy(airAtSpawn >= 10, string.format("never below 10 s of AIR (%.1f at the spawn)", airAtSpawn))
	eq(bot:state().moduleType, "vacuum", "only in vacuum")
	eq(spawnEv.name, Hz.Kinds[bands[2].hazards[1]].name, "the band's own kind (" .. spawnEv.name .. ")")
	local ring = LOCAL.Hazard:FindFirstChild("Ring")
	local debris = LOCAL.Hazard:FindFirstChild("Debris")
	truthy(ring ~= nil and debris ~= nil, "the debris and its red ring are drawn")
	if ring then
		local kind = Hz.Kinds[bands[2].hazards[1]]
		eq(ring.Size.Y / 2, kind.hitRadius + Hz.PlayerRadius, "the ring's radius is exactly the zone (hitRadius + PlayerRadius)")
		local p = bot:pos()
		truthy(math.abs(ring.Position.X - p.X) < 0.01 and math.abs(ring.Position.Z - p.Z) < 0.01, "centred where the player stands")
		truthy(ring.Color.R > 0.9 and ring.Color.G < 0.3, "red")
		eq(plr.PlayerGui.SignalHud.Root.Banner.Text, spawnEv.name .. " — STEP OUT OF THE RING", "the banner says what to do")
		-- a still player in the ring: the lane locks, the debris arrives, the shove
		local root = plr.Character.HumanoidRootPart
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		local hit = false
		for _ = 1, 60 do
			bot:tick()
			local v = root.AssemblyLinearVelocity
			if v and math.sqrt(v.X * v.X + v.Z * v.Z) > 1 then hit = true break end
		end
		truthy(hit, "standing still in the ring: hit")
		local v = root.AssemblyLinearVelocity
		local hv = math.sqrt(v.X * v.X + v.Z * v.Z)
		truthy(math.abs(hv - kind.knock) < 0.01, string.format("a horizontal shove of the kind's knock (%.2f)", hv))
		truthy(v.Y <= (kind.lift or 0) + 1e-6, "no launch")
		eq(bot:state().air > 0 and bot:state().phase, "sector", "and nothing is lost: still in the sector")
	end
end
bot:waitSeconds(2)
local warned = 0
for _, e in hazardEvents do if e.phase == "warn" then warned += 1 end end
eq(warned, 1, "one hazard at a time, and rarely: exactly one in this stretch")

section("G. the next hazard: stepping out of the ring dodges; walking on through a hatch is a near-miss, not a vanish")
-- force the next one due sooner is not possible from outside: keep shuttling until it comes (80..120 s eligible)
local function nextWarn(fromCount)
	for visit = 1, 30 do
		local a, v = vacuumPair()
		if not a then return nil end
		local ms = bot:modules()
		local cur = bot:moduleAt(ms, bot:pos())
		if cur ~= a then
			local path = bot:route(ms, bot:hatches(), cur, a)
			if path then for i = 2, #path do bot:cross(bot:modules(), path[i - 1], path[i], "sector") end end
		end
		bot:cross(bot:modules(), a, v, "sector")
		for _ = 1, 150 do
			bot:tick()
			local n = 0
			for _, e in hazardEvents do if e.phase == "warn" then n += 1 end end
			if n > fromCount then return a, v end
			if bot:state().air < 10.5 then break end
		end
		bot:cross(bot:modules(), v, a, "sector")
		bot:refill()
	end
	return nil
end
do
	local a, v = nextWarn(1)
	truthy(a ~= nil, "a second hazard came")
	if a then
		-- The lane re-aims at the player while its warning runs (the template: it visibly comes FOR you), so the ring
		-- follows a step taken early. It LOCKS `commit` seconds before arrival; stepping out after that dodges.
		local kind = Hz.Kinds[bands[2].hazards[1]]
		local lockIn = kind.telegraph - kind.commit
		bot:waitSeconds(lockIn + 0.2, "sector")
		local root = plr.Character.HumanoidRootPart
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		local p = bot:pos()
		local centre = bot:modules()[v].center
		local dir = (Vector3.new(centre.X, 0, centre.Z) - Vector3.new(p.X, 0, p.Z))
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
		bot:walkTo(Vector3.new(p.X + dir.X * 6, 0, p.Z + dir.Z * 6), "sector")
		local clearSeen = false
		local hit = false
		for _ = 1, 60 do
			bot:tick()
			local vv = root.AssemblyLinearVelocity
			if vv and math.sqrt(vv.X * vv.X + vv.Z * vv.Z) > 1 then hit = true end
			for _, e in hazardEvents do if e.phase == "zone" and e.inside == false then clearSeen = true end end
			if not LOCAL.Hazard:FindFirstChild("Debris") then break end
		end
		truthy(clearSeen, "stepping out of the ring: the banner says YOU ARE CLEAR")
		eq(hit, false, "and the hazard passes without a shove")
	end
	local a2, v2 = nextWarn(2)
	truthy(a2 ~= nil, "a third hazard came")
	if a2 then
		-- REVIEW-1 finding 4: walking on through the hatch (what a player in vacuum does, AIR draining) used to call the
		-- hazard off mid-telegraph, so the warning just vanished. Now its lane locks and it flies on through the ring
		-- the player left: the banner says YOU ARE CLEAR, the debris passes, nobody is shoved.
		local before = #hazardEvents
		bot:cross(bot:modules(), v2, a2, "sector")
		local clearedAt, clearSeen, hit = nil, false, false
		for i = before + 1, #hazardEvents do if hazardEvents[i].phase == "clear" then clearedAt = i end end
		eq(clearedAt, nil, "walking into the air module does NOT call the hazard off")
		truthy(LOCAL.Hazard:FindFirstChild("Debris") ~= nil, "its debris is still in flight")
		-- REST tapped now, in air, while that debris still flies: queued (BlockWhileThreat), and SAID, never silent
		local notes = {}
		local off = EnvBus.on(function(kind, data) if kind == "restRefused" then table.insert(notes, data.reason) end end)
		plr.PlayerGui.SignalHud.Root.RestButton.Activated:Fire()
		bot:tick()
		off()
		truthy(type(Config.Rest.Text.Queued) == "string", "Config.Rest.Text.Queued exists")
		eq(notes[1], Config.Rest.Text.Queued, "REST while the debris still flies is queued, and the player is told so")
		eq(plr.PlayerGui.SignalHud.Root.Toast.Text, Config.Rest.Text.Queued, "on the HUD")
		local root = plr.Character.HumanoidRootPart
		for _ = 1, 80 do
			bot:tick()
			local vv = root.AssemblyLinearVelocity
			if vv and math.sqrt(vv.X * vv.X + vv.Z * vv.Z) > 1 then hit = true end
			for i = before + 1, #hazardEvents do
				local e = hazardEvents[i]
				if e.phase == "zone" and e.inside == false then clearSeen = true end
				if e.phase == "clear" then clearedAt = i end
			end
			if clearedAt then break end
		end
		truthy(clearSeen, "the banner says YOU ARE CLEAR once the player is out of the ring")
		truthy(clearedAt ~= nil, "the flight finishes")
		eq(hit, false, "the player who walked on is not shoved")
		eq(LOCAL.Hazard:FindFirstChild("Debris"), nil, "the debris is gone after its flight")
		eq(plr.PlayerGui.SignalHud.Root.Banner.Visible, false, "and so is its banner")
	end
end

--=========================================================================== H. every band's content on real sectors
section("H. bands 3-7: content in band 2's slot (in memory), dressing, weather, budgets")
local slot = bands[2]
local original = {}
for _, f in { "grade", "palette", "kit", "weather", "critters", "exterior", "hazards" } do original[f] = slot[f] end
-- finish sector 5 first
do
	local st = bot:state()
	if not st.spliced then
		local r = bot:playSector(600)
		truthy(r == "spliced" or r == "blackout", "sector 5 finished (" .. tostring(r) .. ")")
		if r == "blackout" then bot:waitPhase("sector", 6); bot:playSector(600) end
	end
end
local originals = {}
for i, bd in bands do
	originals[i] = {}
	for _, f in { "grade", "palette", "kit", "weather", "critters", "exterior", "hazards" } do originals[i][f] = bd[f] end
end
for b = 3, #bands do
	local src = bands[b]
	local slotIndex = Dressing.bandOf(Env, bot:state().k + 1) -- the band the NEXT sector belongs to
	slot = bands[slotIndex]
	for _, f in { "grade", "palette", "kit", "weather", "critters", "exterior", "hazards" } do slot[f] = src[f] end
	truthy(bot:toRelayPiece("FloorHatch"), src.id .. ": the floor hatch")
	bot:waitPhase("sector", 6)
	bot:waitSeconds(1.5)
	truthy(near(cc.TintColor, src.grade.tint, 4), src.id .. ": the grade after the ride (" .. table.concat(rgbOf(cc.TintColor), ",") .. ")")
	dressingAudit(slotIndex, src.id .. " (sector " .. bot:state().k .. ")")
	local wk = {}
	for _, host in LOCAL.Weather:GetChildren() do table.insert(wk, host.Name) end
	truthy(table.find(wk, "Weather_" .. src.weather.kind) ~= nil, src.id .. ": its weather (" .. table.concat(wk, ",") .. ")")
	for _, host in LOCAL.Weather:GetChildren() do
		local pe = host:FindFirstChild("Weather")
		truthy(pe and (pe.LightInfluence == 0 or pe.LightInfluence == 1), src.id .. ": " .. host.Name .. " writes its LightInfluence")
	end
	local r = bot:playSector(600)
	if r == "blackout" then bot:waitPhase("sector", 6); r = bot:playSector(600) end
	truthy(r == "spliced", src.id .. ": spliced (" .. tostring(r) .. ")")
end
for i, saved in originals do
	for f, v in saved do bands[i][f] = v end
end

--=========================================================================== I. budgets, every frame
section("I. budgets, audited on every one of " .. frames .. " frames")
print(string.format("   measured peaks: dressing %d / %d (worst module %d / %d), weather emitters %d / %d, active emitters %d / %d, critters %d / %d, exterior parts %d / %d, light sources %d / 0, hazards %d / %d",
	peak.dress, Budget.MaxDressParts, peak.perModule, Budget.MaxDressPartsPerModule, peak.weather, Budget.MaxWeather, peak.emitters, Budget.MaxEmitters,
	peak.critters, Budget.MaxCritters, peak.exterior, Budget.MaxExteriorParts, peak.lights, peak.hazards, Budget.MaxHazards))
eq(#budgetViolations, 0, "no budget exceeded on any frame (" .. table.concat(budgetViolations, "; ", 1, math.min(#budgetViolations, 5)) .. ")")
do
	local zoneAttrs = 0
	for _, d in W.Station:GetDescendants() do for _ in d:GetAttributes() do zoneAttrs += 1 end end
	eq(zoneAttrs, 0, "the environment set no attribute on any zone")
	local n = 0
	for _, rec in h.ReplicatedStorage.SignalRemotes.BuyUpgrade:getSent() do n += 1 end
	local _ = n
end

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings (the environment switched nothing off)")
print(string.format("signal-lost env: %d passed, %d failed", passed, failed))
if failed > 0 then error("signal-lost env check failed", 0) end
