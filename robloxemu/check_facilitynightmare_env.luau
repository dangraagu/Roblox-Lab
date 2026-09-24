-- FACILITY: Endless Nightmare — the ENVIRONMENT (EYECANDY.md), through the real server and the real
-- client: src/client/Env.client.luau and the HUD, in one harness, driven by tests/Bot.luau.
--
-- Run:  py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       luau check_facilitynightmare_env.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- The pure specs (tests/Dressing, EnvConfig, Hazards, Rest, EnvBands) prove the rules on data. This
-- proves the GLUE: that the client really drives the band by the server's sublevel, glides the grade,
-- dresses the rooms it should with what the rules allow, switches glow off with the room's own light,
-- changes nothing of the server's world but colours, leaks nothing, rests only in the break room, and
-- stays inside the budgets EYECANDY.md reports. RunService.RenderStepped is fired once per bot tick.
--
-- Where every band has to be seen, the band table's `from` values are shifted IN MEMORY so the band
-- under test covers sublevel 1 (the check's own copy of Config; nothing on disk changes). Real
-- progression 1 -> 2 -> 3 is also played through the server, so the sublevel really is what drives it.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")
local bundle = require("./build/facility-nightmare")

local h = Harness.new({ bundle = bundle, name = "facility-nightmare-env", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Env, Budget = Config.Env, Config.Budget
local bands = Env.Bands
local Dressing = h:_require(h.ReplicatedStorage:FindFirstChild("Dressing"))
local EnvBands = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBands"))
local EnvBus = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBus"))
local Fx = h:_require(h.ReplicatedStorage:FindFirstChild("Fx"))

-- Written out, not read from Config: a number checked against itself is not a check.
local INNER, WALLBAND, OVERHEAD, DOORHALF, DOORTOP, EYE = 13, 2.5, 6.5, 3 + 4, 9.5, 4.5
-- The review's finding 1 (EYECANDY.md §11), re-derived on the instances: the colours Main.server.luau builds a room's
-- wall, floor and door leaf with (section A proves Config.Env.Base equals them), a surface returning 60-100 % of the
-- server's light, and a closed door standing out from its wall 90-110 % as much as the server built it. LINEAR light.
local SERVER_WALL, SERVER_FLOOR, SERVER_DOOR = { 150, 158, 150 }, { 88, 92, 90 }, { 96, 100, 104 }
local REFLECT_MIN, DOOR_MIN, DOOR_MAX = 0.6, 0.9, 1.1
local function lin(v)
	local c = v / 255
	return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
local function Y(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
local function rgbOf(c3) return { math.floor(c3.R * 255 + 0.5), math.floor(c3.G * 255 + 0.5), math.floor(c3.B * 255 + 0.5) } end
-- A ParticleEmitter's LightInfluence defaults to 0 in Roblox (unaffected by light) and reads nil here when never
-- written. A particle that is not self-lit must be lit by the scene (1); a self-lit one says so (0). Review finding 5.
local function influenceOk(pe)
	if (pe.LightEmission or 0) > 0 then return pe.LightInfluence == 0 end
	return pe.LightInfluence == 1
end
-- The longest hint the HUD showed before the environment existed ("Saving is off on this server — progress will
-- not be kept. Walk into the elevator."). Nothing headless can see how a phone wraps a 16 px hint in its 44 px box.
local LONGEST_OLD_HINT = 81

--=========================================================================== A. the shipped source
section("A. what the environment client can do, read off the shipped source")

for _, key in { "client/Env.client", "shared/EnvArt", "shared/Dressing", "shared/Hazards", "shared/Rest", "shared/EnvBus" } do
	local src = bundle[key] and bundle[key].source or ""
	truthy(#src > 0, key .. " is in the bundle")
	-- code only: block comments, then line comments (the files SAY what they never do)
	src = string.gsub(src, "%-%-%[(=*)%[.-%]%1%]", "")
	src = string.gsub(src, "%-%-[^\n]*", "")
	for _, bad in { "FireServer", "InvokeServer", "SetAttribute", "PointLight", "SpotLight", "SurfaceLight", "ServerStorage",
		"FacilityDebug", "OnServerEvent", "PivotTo" } do
		truthy(string.find(src, bad, 1, true) == nil, key .. " never uses " .. bad)
	end
end
for _, mod in { "Facility", "Trust", "Survival", "Economy", "MazeGen", "Rng" } do
	truthy(string.find(bundle["client/Env.client"].source, 'WaitForChild("' .. mod .. '")', 1, true) == nil,
		"Env.client does not require " .. mod .. " (it never sees a plan, a seed or an item)")
end
do -- Config.Env.Base is what the game really uses: the Facility preset...
	local P = Fx.Presets.Facility
	local B = Env.Base
	local function same(c3, t) return c3 ~= nil and math.floor(c3.R * 255 + 0.5) == t[1] and math.floor(c3.G * 255 + 0.5) == t[2] and math.floor(c3.B * 255 + 0.5) == t[3] end
	truthy(same(P.colorCorrection.TintColor, B.tint), "Base.tint is Fx.Presets.Facility's TintColor")
	eq(P.colorCorrection.Brightness, B.brightness, "Base.brightness is the preset's")
	eq(P.colorCorrection.Contrast, B.contrast, "Base.contrast is the preset's")
	eq(P.colorCorrection.Saturation, B.saturation, "Base.saturation is the preset's")
	truthy(same(P.atmosphere.Color, B.atmosColor), "Base.atmosColor is the preset's")
	truthy(same(P.atmosphere.Decay, B.atmosDecay), "Base.atmosDecay is the preset's")
	-- ...and the colours Main.server.luau builds rooms and items with
	local main = bundle["server/Main.server"].source
	for name, want in { ROOM_WALL = B.wall, ROOM_FLOOR = B.floor, FUSE_COLOR = B.fuse, CELL_COLOR = B.cell } do
		local r, g, b = string.match(main, name .. " = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
		eq(string.format("%s,%s,%s", tostring(r), tostring(g), tostring(b)), table.concat(want, ","), "Base matches the server's " .. name)
	end
	local function after(anchor, what)
		local i = string.find(main, anchor, 1, true)
		local r, g, b = string.match(string.sub(main, i or 1), "Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
		eq(string.format("%s,%s,%s", tostring(r), tostring(g), tostring(b)), table.concat(what, ","), "Base matches the server's colour after '" .. anchor .. "'")
	end
	after('s.role == "ceiling"', B.ceiling)
	after('light.Name = "RoomLight"', B.light)
	after("local spec = Facility.doorLeaf", B.door)
end

--=========================================================================== boot
local UID = 9301
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
-- runs 0: a first-ever run, so sublevel 1's front is HELD until the first fuse (the band sweep in D
-- needs lit rooms for as long as it takes). Every perk, so the bot survives three sublevels in F.
store:SetAsync("u_" .. UID, { data = { v = 1, essence = 0, essenceEarned = 900, bestSublevel = 0, runs = 0, extractions = 0,
	perks = { deepCell = 3, nightEyes = 3, marathon = 3, soulAnchor = 0, secondWind = 1 } } })

assert(h:tryRun("server/Main.server"))
h:advance(1)

local plr = h:join("Scenery", UID)
h:advance(0.5)
local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "client/Hud.client loads (" .. tostring(errHud) .. ")")
local okEnv, errEnv = h:tryRun("client/Env.client")
truthy(okEnv, "client/Env.client loads (" .. tostring(errEnv) .. ")")
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)

local RS = h.game:GetService("RunService")
local busLog = {}
EnvBus.on(function(kind, data) table.insert(busLog, { kind = kind, data = data, at = h.scheduler:now() }) end)
local envFolder = h.workspace:FindFirstChild("FacilityEnvLocal")
truthy(envFolder ~= nil, "Env.client made its local folder")
local hudRoot = plr.PlayerGui.FacilityHud.Root
local cc = h.Lighting:FindFirstChild("FxColorCorrection")
local atm = h.Lighting:FindFirstChild("FxAtmosphere")

--=========================================================================== census + safety helpers

local peaks = {}
local peakWhere = {}
local function census()
	local c = { parts = 0, emitters = 0, rate = 0, screens = 0, lights = 0, hazardParts = 0, glowSeen = 0, dullSeen = 0, influenceWrong = 0 }
	for _, d in envFolder:GetDescendants() do
		if d:IsA("BasePart") then
			c.parts += 1
			local hz = envFolder:FindFirstChild("Hazard")
			if hz and d:IsDescendantOf(hz) then c.hazardParts += 1 end
		elseif d.ClassName == "ParticleEmitter" then
			if d.Enabled then c.emitters += 1; c.rate += d.Rate end
			if (d.LightEmission or 0) > 0 then c.glowSeen += 1 else c.dullSeen += 1 end
			if not influenceOk(d) then c.influenceWrong += 1 end
		elseif d.ClassName == "SurfaceGui" then
			if d.Enabled ~= false then c.screens += 1 end
		elseif d.ClassName == "PointLight" or d.ClassName == "SpotLight" or d.ClassName == "SurfaceLight" then
			c.lights += 1
		end
	end
	return c
end
local where = "boot"
local function track()
	local c = census()
	for k, v in c do
		if v > (peaks[k] or -1) then peaks[k] = v; peakWhere[k] = where end
	end
end
local function frame(dt)
	RS.RenderStepped:Fire(dt)
	track()
end
local bot = Bot.new(h, plr, { onTick = function() frame(0.1) end, maxSeconds = 900 })

local function aabb(p)
	local cf, s = p.CFrame, p.Size
	local c = cf.Position
	local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local ex = math.abs(R.X) * hx + math.abs(U.X) * hy + math.abs(L.X) * hz
	local ey = math.abs(R.Y) * hx + math.abs(U.Y) * hy + math.abs(L.Y) * hz
	local ez = math.abs(R.Z) * hx + math.abs(U.Z) * hy + math.abs(L.Z) * hz
	return { min = { c.X - ex, c.Y - ey, c.Z - ez }, max = { c.X + ex, c.Y + ey, c.Z + ez } }
end
local function localBox(b, o)
	return { min = { b.min[1] - o.X, b.min[2] - o.Y, b.min[3] - o.Z }, max = { b.max[1] - o.X, b.max[2] - o.Y, b.max[3] - o.Z } }
end
local function overlap(a, b, pad)
	pad = pad or 0
	for i = 1, 3 do
		if a.min[i] >= b.max[i] + pad - 0.02 or b.min[i] >= a.max[i] + pad - 0.02 then return false end
	end
	return true
end
local function segHits(p, q, b)
	local t0, t1 = 0, 1
	for i = 1, 3 do
		local d = q[i] - p[i]
		local lo, hi = b.min[i] + 1e-6, b.max[i] - 1e-6
		if math.abs(d) < 1e-12 then
			if p[i] <= lo or p[i] >= hi then return false end
		else
			local a, c = (lo - p[i]) / d, (hi - p[i]) / d
			if a > c then a, c = c, a end
			t0, t1 = math.max(t0, a), math.min(t1, c)
			if t0 >= t1 then return false end
		end
	end
	return true
end

local function myFloor()
	local z = bot:zone()
	return z and z:FindFirstChild("Floor")
end
local function roomFolders()
	local fl = myFloor()
	local rooms = fl and fl:FindFirstChild("Rooms")
	return rooms and rooms:GetChildren() or {}
end
local function originOf(rf)
	local fl = rf:FindFirstChild("Floor")
	return Vector3.new(fl.Position.X, fl.Position.Y + fl.Size.Y / 2, fl.Position.Z)
end
local function dressOf(rf)
	local rooms = envFolder:FindFirstChild("Rooms")
	return rooms and rooms:FindFirstChild("Dress_" .. rf.Name)
end

-- Every rule of Dressing.luau, re-derived on the INSTANCES the client built in the real world, against
-- the room's real server props and real item. Returns a list of problems.
local function auditRoom(rf, problems)
	local d = dressOf(rf)
	if not d then return 0 end
	local o = originOf(rf)
	local props, item = {}, nil
	for _, c in rf:GetChildren() do
		if c:IsA("BasePart") and string.sub(c.Name, 1, 4) == "Prop" then table.insert(props, localBox(aabb(c), o)) end
		if c.Name == "Fuse" or c.Name == "Cell" then item = localBox(aabb(c), o) end
	end
	local boxes, n = {}, 0
	for _, p in d:GetDescendants() do
		if p:IsA("BasePart") then
			n += 1
			local b = localBox(aabb(p), o)
			local film = b.max[2] <= 0.2 + 1e-6
			local wall = b.min[1] >= INNER - WALLBAND - 1e-6 or b.max[1] <= -INNER + WALLBAND + 1e-6
				or b.min[3] >= INNER - WALLBAND - 1e-6 or b.max[3] <= -INNER + WALLBAND + 1e-6
			local k = 5.5
			local column = b.max[1] > -k and b.min[1] < k and b.max[3] > -k and b.min[3] < k
			-- bob animation may lift a part up to 0.4 above its resting box
			if not film and not wall and (b.min[2] < OVERHEAD - 1e-6 or column) then
				table.insert(problems, rf.Name .. "." .. p.Name .. " is neither in the wall band, overhead nor a film")
			end
			for ax = 1, 3, 2 do
				if b.min[ax] < -INNER - 1e-3 or b.max[ax] > INNER + 1e-3 then table.insert(problems, p.Name .. " pokes through a wall") end
			end
			if not film and b.min[2] < DOORTOP then
				if (b.max[1] > INNER - WALLBAND and b.max[3] > -DOORHALF and b.min[3] < DOORHALF)
					or (b.min[1] < -INNER + WALLBAND and b.max[3] > -DOORHALF and b.min[3] < DOORHALF)
					or (b.max[3] > INNER - WALLBAND and b.max[1] > -DOORHALF and b.min[1] < DOORHALF)
					or (b.min[3] < -INNER + WALLBAND and b.max[1] > -DOORHALF and b.min[1] < DOORHALF) then
					table.insert(problems, rf.Name .. "." .. p.Name .. " stands in front of a doorway's place")
				end
			end
			if not film then
				for _, pr in props do
					if overlap(b, pr) then table.insert(problems, rf.Name .. "." .. p.Name .. " intersects a prop") end
				end
				if item and overlap(b, item, 1) then table.insert(problems, rf.Name .. "." .. p.Name .. " within a stud of the room's " .. "item") end
			end
			if p.CanQuery ~= false or p.CanTouch ~= false or p.Anchored ~= true then
				table.insert(problems, p.Name .. " is queryable, touchable or unanchored")
			end
			if p.CanCollide == true and not (wall and b.min[2] < 0.5) then
				table.insert(problems, p.Name .. " collides but is not floor furniture in the wall band")
			end
			if not film and (p.Transparency or 0) < 0.95 then table.insert(boxes, b) end
			local gui = p:FindFirstChildOfClass("SurfaceGui")
			if gui then
				local cf = p.CFrame
				local face = gui.Face and gui.Face.Name
				local nrm = if face == "Left" then -cf.RightVector elseif face == "Right" then cf.RightVector
					elseif face == "Front" then cf.LookVector elseif face == "Back" then -cf.LookVector
					elseif face == "Top" then cf.UpVector else -cf.UpVector
				local toCentre = Vector3.new(o.X - p.Position.X, 0, o.Z - p.Position.Z)
				if nrm.X * toCentre.X + nrm.Z * toCentre.Z <= 0 then
					table.insert(problems, rf.Name .. "." .. p.Name .. "'s screen faces the wall, not the room (" .. tostring(face) .. ")")
				end
			end
		end
	end
	if item then
		local c = { (item.min[1] + item.max[1]) / 2, (item.min[2] + item.max[2]) / 2, (item.min[3] + item.max[3]) / 2 }
		for ex = -10.5, 10.5, 3 do
			for ez = -10.5, 10.5, 3 do
				local standable = true
				for _, b in boxes do
					if b.min[1] - 1 < ex and ex < b.max[1] + 1 and b.min[3] - 1 < ez and ez < b.max[3] + 1 and b.min[2] < EYE then standable = false end
				end
				for _, pr in props do
					if pr.min[1] - 1 < ex and ex < pr.max[1] + 1 and pr.min[3] - 1 < ez and ez < pr.max[3] + 1 then standable = false end
				end
				if standable then
					for _, b in boxes do
						if segHits({ ex, EYE, ez }, c, b) then
							table.insert(problems, string.format("%s: dressing between an eye at (%g, %g) and the item", rf.Name, ex, ez))
						end
					end
				end
			end
		end
	end
	return n
end

local function palette(rf)
	local wall, light
	for _, c in rf:GetChildren() do
		if string.sub(c.Name, 1, 4) == "Wall" then wall = c.Color end
	end
	local fx = rf:FindFirstChild("Fixture")
	light = fx and fx:FindFirstChild("RoomLight")
	return wall, light and light.Color
end
-- within 1.5 of 255 per channel: values are written as whole numbers, and only once they move by 0.5
local function same(c3, t)
	return c3 ~= nil and math.abs(c3.R * 255 - t[1]) <= 1.5 and math.abs(c3.G * 255 - t[2]) <= 1.5 and math.abs(c3.B * 255 - t[3]) <= 1.5
end

--=========================================================================== B. the break room
section("B. the break room: its grade, its dressing, the benches, rest")

do
	where = "break room"
	bot:waitSeconds(5)
	local benches = h.workspace.Hub:FindFirstChild("Benches")
	local seats = 0
	for _, c in benches and benches:GetChildren() or {} do if c.ClassName == "Seat" then seats += 1 end end
	eq(seats, 2, "the break room has two benches (real Seats, built by the server)")
	local enabled = 0
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then enabled += 1 end
	end
	eq(enabled, 1, "HubSpawn is still the only enabled SpawnLocation")
	truthy(envFolder:FindFirstChild("BreakRoom") ~= nil, "the break room's dressing is shown in the break room")
	truthy(same(cc.TintColor, Env.BreakRoom.grade.tint), "the break room's warm grade is on (" .. tostring(cc.TintColor) .. ")")
	local board = envFolder.BreakRoom:FindFirstChild("DepthBoard")
	local best = board and board.Screen:FindFirstChild("Best")
	eq(best and best.Text, "DEEPEST: —", "the DEPTH RECORD board, for a player who has never gone down")
	local row1 = board and board.Screen:FindFirstChild("Row1")
	eq(row1 and row1.Text, " 1  ???", "…names nothing it has not seen")
	-- review finding 4: the row of the band you have reached is highlighted in amber, THE VOID (the last row, the
	-- brag) included. On a second EnvArt in memory, never parented, so the live board is untouched.
	do
		local EnvArt = h:_require(h.ReplicatedStorage:FindFirstChild("EnvArt"))
		local art2 = EnvArt.new(Instance.new("Folder"), Config, Dressing)
		art2:buildHub(bands)
		local AMBER = { 255, 196, 92 }
		local function lit()
			local out = {}
			for i, r in art2.hub.rows do
				if same(r.label.TextColor3, AMBER) then table.insert(out, tostring(i)) end
			end
			return table.concat(out, ",")
		end
		-- written out: the bands as shipped start on sublevels 1, 3, 5, 7, 9, 11, 13
		for _, case in { { 0, "" }, { 1, "1" }, { 2, "1" }, { 3, "2" }, { 4, "2" }, { 11, "6" }, { 12, "6" }, { 13, "7" }, { 20, "7" } } do
			art2:updateBoard(case[1])
			eq(lit(), case[2], "the DEPTH RECORD board at DEEPEST " .. case[1] .. " highlights row '" .. case[2] .. "' and no other")
		end
		eq(art2.hub.rows[7].label.Text, "13  THE VOID", "…and at 20 it names THE VOID")
	end

	-- nothing solid of the dressing on the walk from the spawn to the elevator, or from the arrival pad back
	local blocked = {}
	local corridor = { min = { -30, 0, -6 }, max = { 18, 10, 6 } }
	for _, p in envFolder.BreakRoom:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide and overlap(aabb(p), corridor) then table.insert(blocked, p.Name) end
		if p:IsA("BasePart") and aabb(p).max[2] > 0.2 then -- a floor film (the rug) lies under things
			for _, other in { benches, h.workspace.Hub:FindFirstChild("PerkTerminal"), h.workspace.Hub:FindFirstChild("HubCar") } do
				local parts = if other:IsA("BasePart") then { other } else other:GetDescendants()
				for _, q in parts do
					if q:IsA("BasePart") and overlap(aabb(p), aabb(q)) then table.insert(blocked, p.Name .. " in " .. q.Name) end
				end
			end
		end
	end
	eq(#blocked, 0, "the break room's dressing keeps off the spawn -> car -> arrival path, the benches, the terminal and the car (" .. table.concat(blocked, ", ") .. ")")
	local hubParts = 0
	for _, p in envFolder.BreakRoom:GetDescendants() do if p:IsA("BasePart") then hubParts += 1 end end
	truthy(hubParts <= Budget.MaxHubParts, "the break room's dressing is " .. hubParts .. " parts (budget " .. Budget.MaxHubParts .. ")")

	local hum = plr.Character:FindFirstChildOfClass("Humanoid")
	hum.SeatPart = benches:FindFirstChild("Bench1")
	hum.Sit = true
	bot:waitSeconds(0.3)
	local last = EnvBus.last("rest")
	truthy(last ~= nil and last.resting == true and last.source == "bench", "sitting on a bench: resting")
	truthy(h.Lighting.FacilityRestFocus.Enabled == true, "…the view softens")
	truthy(string.find(hudRoot.Hint.Text, "Resting", 1, true) ~= nil, "…and the HUD says so: " .. hudRoot.Hint.Text)
	truthy(utf8.len(hudRoot.Hint.Text) <= LONGEST_OLD_HINT, "…in no more characters than the longest hint the HUD already had (" .. utf8.len(hudRoot.Hint.Text) .. ")")
	hum.SeatPart = nil
	hum.Sit = false
	bot:waitSeconds(0.3)
	eq(EnvBus.last("rest").resting, false, "standing up ends it")
	eq(h.Lighting.FacilityRestFocus.Enabled, false, "…the view clears")
	eq(hudRoot.Hint.Text, "Walk into the elevator to go down.", "…and the hint is the ordinary one")

	bot:waitSeconds(19)
	eq(EnvBus.last("rest").resting, false, "19 s standing still: not resting yet")
	bot:waitSeconds(1.5)
	truthy(EnvBus.last("rest").resting == true and EnvBus.last("rest").source == "idle", "20 s standing still in the break room: resting")
	local p = bot:pos()
	bot:walkTo(Vector3.new(p.X + 2, 3, p.Z))
	bot:waitSeconds(0.2)
	eq(EnvBus.last("rest").resting, false, "a step wakes an idle rest")

	local hazards = 0
	for _, m in busLog do if m.kind == "hazard" then hazards += 1 end end
	eq(hazards, 0, "no hazard in the break room")
end

--=========================================================================== C. the first ride down
section("C. the ride to sublevel 1: the grade glides, the HUD names the band, the room is dressed")

local entryRoom
do
	where = "ride 1"
	local startTint = cc.TintColor
	local target = bands[1].grade.tint
	local total = math.abs(startTint.R * 255 - target[1]) + math.abs(startTint.G * 255 - target[2]) + math.abs(startTint.B * 255 - target[3])
	local worstStep, prev = 0, startTint
	local writes = 0
	local conn = cc:GetPropertyChangedSignal("TintColor"):Connect(function()
		local c = cc.TintColor
		local step = math.abs(c.R - prev.R) * 255 + math.abs(c.G - prev.G) * 255 + math.abs(c.B - prev.B) * 255
		worstStep = math.max(worstStep, step)
		prev = c
		writes += 1
	end)
	truthy(bot:board(h.workspace.Hub), "boarded the hub car")
	truthy(string.find(hudRoot.Banner.Text, "SUBLEVEL 1 — ADMIN OFFICES", 1, true) ~= nil, "the banner names the band: " .. hudRoot.Banner.Text)
	bot:waitSeconds(0.3)
	-- written out: the offices' band line, shown on the ride down (it was dead config before the resume session)
	eq(hudRoot.Hint.Text, "Going down to the ADMIN OFFICES… Someone left in a hurry.", "…and so does the ride's hint, with the band's line")
	truthy(envFolder:FindFirstChild("BreakRoom") == nil, "the break room's dressing is put away for the ride")
	truthy(bot:waitPhase("floor", 8), "arrived on sublevel 1")
	conn:Disconnect()
	local left = math.abs(cc.TintColor.R * 255 - target[1]) + math.abs(cc.TintColor.G * 255 - target[2]) + math.abs(cc.TintColor.B * 255 - target[3])
	print(string.format("    ride: %d tint writes, largest step %.1f of a %.1f change, %.1f left on arrival", writes, worstStep, total, left))
	truthy(total > 5, "control: the break room and the offices really are graded differently (" .. total .. ")")
	truthy(writes >= 8, "the grade changed over many writes, not one")
	truthy(worstStep <= 0.2 * total + 1.5, "no single write moved more than a fifth of the change (never a hard cut)")
	truthy(left <= 0.1 * total + 1.5, "by arrival the grade is (almost) the band's")
	bot:waitSeconds(3)
	truthy(same(cc.TintColor, target), "…and then exactly the band's")
	truthy(same(atm.Color, bands[1].grade.atmosColor), "…atmosphere colour too")

	local rooms = bot:rooms()
	entryRoom = bot:roomAt(rooms, bot:pos())
	local rf = rooms[entryRoom].folder
	truthy(dressOf(rf) ~= nil, "the entry room is dressed")
	local wall, light = palette(rf)
	truthy(same(wall, bands[1].palette.wall), "its walls wear the offices' palette")
	truthy(same(light, bands[1].palette.light), "…its light the offices' tint")
	local rl = rf.Fixture.RoomLight
	eq(rl.Enabled, true, "the server's light is still on (the client never switches it)")
	eq(rl.Brightness, Config.Facility.RoomLightBrightness, "…at the server's brightness")
end

--=========================================================================== D. every band, one floor
section("D. every band on the same held floor: dressing, palette, grade, budgets, rules on real rooms")

local snapshot
do
	-- open every door of the entry room from INSIDE it (items are never in the entry room, so nothing is
	-- picked up and the first-run front stays held), so the neighbours are built too
	local rooms = bot:rooms()
	local c = rooms[entryRoom].center
	for _, d in bot:doors() do
		if (d.lo == entryRoom or d.hi == entryRoom) and not d.open then
			local leaf = d.part.Position
			local dir = Vector3.new(leaf.X - c.X, 0, leaf.Z - c.Z).Unit
			bot:walkTo(Vector3.new(leaf.X - dir.X * 6, 3, leaf.Z - dir.Z * 6), "floor")
			local w = 0
			while d.part.CanCollide ~= false and w < 50 do bot:tick(); w += 1 end
			bot:walkTo(Vector3.new(c.X, 3, c.Z), "floor")
		end
	end
	bot:waitSeconds(1)
	local built = #roomFolders()
	truthy(built >= 2, "the entry and its neighbours are built (" .. built .. " rooms)")

	-- everything of the server's world that the client must NOT change
	local function snap()
		local s = {}
		local fl = myFloor()
		for _, d in fl:GetDescendants() do
			if d:IsA("BasePart") then
				s[d] = { d.CFrame.Position, d.Size, d.CanCollide, d.Transparency, d.Anchored, d.Parent }
			elseif d.ClassName == "PointLight" then
				s[d] = { d.Enabled, d.Brightness, d.Range, d.Parent }
			end
		end
		return s
	end
	snapshot = snap()

	local original = {}
	for i, b in bands do original[i] = { from = b.from, fade = b.fade } end
	local function onlyBand(i)
		for j, b in bands do
			if j < i then b.from, b.fade = -1000 + j, 0
			elseif j == i then b.from, b.fade = 0, 0
			else b.from, b.fade = 1000 + j, 0 end
		end
	end
	local perBand = {}
	for i, b in bands do
		onlyBand(i)
		where = "band " .. b.id
		bot:waitSeconds(7)
		local problems, parts = {}, 0
		local rooms2 = 0
		for _, rf in roomFolders() do
			local n = auditRoom(rf, problems)
			if dressOf(rf) then
				rooms2 += 1
				parts += n
				local wall, light = palette(rf)
				if not same(wall, b.palette.wall) or not same(light, b.palette.light) then
					table.insert(problems, rf.Name .. " does not wear the " .. b.id .. " palette")
				end
			end
		end
		for j = 1, math.min(6, #problems) do print("   " .. problems[j]) end
		eq(#problems, 0, b.id .. ": every dressed room obeys every rule, on the real rooms (" .. rooms2 .. " rooms, " .. parts .. " parts)")
		-- review finding 1: on the instances, a closed door still stands out from its wall as the server built it,
		-- and the repainted wall, floor and door still return 60-100 % of the server's light (white light)
		do
			local seen, bad = 0, {}
			local serverRatio = Y(SERVER_WALL) / Y(SERVER_DOOR)
			for _, leaf in myFloor().Doors:GetChildren() do
				local lo = tonumber(string.match(leaf.Name, "^Door_(%d+)_%d+$"))
				local rf = lo and myFloor().Rooms:FindFirstChild("Room_" .. lo)
				if rf and dressOf(rf) and leaf:IsA("BasePart") then
					seen += 1
					local wallC = palette(rf)
					local wall, door, fl = rgbOf(wallC), rgbOf(leaf.Color), rgbOf(rf.Floor.Color)
					if not same(leaf.Color, b.palette.door) then table.insert(bad, leaf.Name .. " does not wear the band's door colour") end
					local c = (Y(wall) / Y(door)) / serverRatio
					if c < DOOR_MIN or c > DOOR_MAX then
						table.insert(bad, string.format("%s stands out from %s's wall %.0f %% as much as the server built it", leaf.Name, rf.Name, 100 * c))
					end
					for _, s in { { "wall", wall, SERVER_WALL }, { "floor", fl, SERVER_FLOOR }, { "door", door, SERVER_DOOR } } do
						local r = Y(s[2]) / Y(s[3])
						if r < REFLECT_MIN or r > 1 + 1e-6 then
							table.insert(bad, string.format("%s's %s returns %.0f %% of the server's light", rf.Name, s[1], 100 * r))
						end
					end
				end
			end
			for j = 1, math.min(4, #bad) do print("   " .. bad[j]) end
			truthy(seen >= 1, b.id .. ": control, door leaves of dressed rooms were measured (" .. seen .. ")")
			eq(#bad, 0, b.id .. ": on the real instances every closed door stands out from its wall as the server built it (90-110 %), and wall, floor and door return 60-100 % of the server's light")
		end
		truthy(same(cc.TintColor, b.grade.tint), b.id .. ": the grade is the band's (" .. tostring(cc.TintColor) .. ")")
		local c2 = census()
		perBand[b.id] = { rooms = rooms2, parts = c2.parts, emitters = c2.emitters, rate = c2.rate, screens = c2.screens }
		truthy(c2.lights == 0, b.id .. ": no light source")
	end
	for i, b in bands do b.from, b.fade = original[i].from, original[i].fade end
	where = "held floor, restored"
	bot:waitSeconds(4)
	print("    per band, the held floor's built rooms (parts / emitters on (rate) / screens on):")
	for _, b in bands do
		local s = perBand[b.id]
		print(string.format("      %-9s %d rooms: %3d parts, %d emitters (%2d/s), %2d screens", b.id, s.rooms, s.parts, s.emitters, s.rate, s.screens))
	end

	-- the server's world after all that re-dressing: only colours and materials changed
	local now = snap()
	local changed = {}
	for inst, before in snapshot do
		local after = now[inst]
		if after == nil then
			table.insert(changed, inst.Name .. " vanished")
		else
			for j, v in before do
				local w = after[j]
				local differs = if typeof(v) == "Vector3" then (v - w).Magnitude > 1e-6 else v ~= w
				if differs then table.insert(changed, inst.Name .. " field " .. j) end
			end
		end
	end
	for j = 1, math.min(5, #changed) do print("   " .. changed[j]) end
	eq(#changed, 0, "the client changed nothing of the server's floor but colours and materials")
	local attrs = 0
	for _, d in h.workspace.Facility:GetDescendants() do
		for _ in d:GetAttributes() do attrs += 1 end
	end
	eq(attrs, 0, "…and the zones still carry zero attributes")
end

--=========================================================================== D1. range and the emitter cap
section("D1. rooms out of range are put away; the emitter cap holds when rooms want more")

do
	-- the flooded kit hangs a dripping pipe in EVERY room (chance 1), so every dressed room has an emitter
	local original = {}
	for i, b in bands do original[i] = { from = b.from, fade = b.fade } end
	for j, b in bands do
		if j < 4 then b.from, b.fade = -1000 + j, 0 elseif j == 4 then b.from, b.fade = 0, 0 else b.from, b.fade = 1000 + j, 0 end
	end
	where = "caps"
	local c = bot:rooms()[entryRoom].center
	bot:walkTo(Vector3.new(c.X, 3, c.Z), "floor")
	bot:waitSeconds(2, "floor")
	local function enabledEmitters()
		local n = 0
		for _, d in envFolder.Rooms:GetDescendants() do
			if d.ClassName == "ParticleEmitter" and d.Enabled then n += 1 end
		end
		return n
	end
	local nearWithEmitter, far = 0, 0
	for _, rf in roomFolders() do
		local o = originOf(rf)
		local dist = math.sqrt((o.X - c.X) ^ 2 + (o.Z - c.Z) ^ 2)
		local d = dressOf(rf)
		if d and dist <= Env.EmitterRadius then
			for _, x in d:GetDescendants() do
				if x.ClassName == "ParticleEmitter" then nearWithEmitter += 1; break end
			end
		end
		if dist > 20 then far += 1 end
	end
	-- a live hazard's warning takes one emitter from the rooms (Env.client), so expect one fewer then
	local function hazardLive() return #envFolder.Hazard:GetChildren() > 0 end
	truthy(nearWithEmitter >= 2, "control: at least two dressed rooms near the player carry an emitter (" .. nearWithEmitter .. ")")
	eq(enabledEmitters(), math.min(nearWithEmitter, Budget.MaxEmitters - (if hazardLive() then 1 else 0)),
		"every near room's emitter runs while the cap allows it")
	local cap = Budget.MaxEmitters
	Budget.MaxEmitters = 1 -- in memory: fewer than the rooms want
	bot:waitSeconds(1, "floor")
	eq(enabledEmitters(), if hazardLive() then 0 else 1, "with the cap at 1, exactly one room's emitter runs (the nearest), not " .. nearWithEmitter)
	Budget.MaxEmitters = cap

	truthy(far >= 1, "control: at least one built room is more than 20 studs from the player (" .. far .. ")")
	local radius = Env.DressRadius
	Env.DressRadius = 20 -- in memory
	bot:waitSeconds(1, "floor")
	local stillOut, kept = 0, 0
	for _, rf in roomFolders() do
		local o = originOf(rf)
		local dist = math.sqrt((o.X - c.X) ^ 2 + (o.Z - c.Z) ^ 2)
		if dist > 20 and dressOf(rf) ~= nil then stillOut += 1 end
		if dist <= 20 and dressOf(rf) ~= nil then kept += 1 end
	end
	eq(stillOut, 0, "a room out of DressRadius is put away (its dressing unparented), not left drawing")
	eq(kept, 1, "…while the player's own room stays dressed")
	Env.DressRadius = radius
	bot:waitSeconds(1, "floor")
	local back = 0
	for _, rf in roomFolders() do if dressOf(rf) ~= nil then back += 1 end end
	truthy(back >= 2, "…and back in range, the others are dressed again (" .. back .. " rooms)")

	-- the screen cap: find a kit whose near rooms carry at least two screens, then allow one (in memory).
	-- A room's screens run all or none, nearest room first.
	local function screensOn()
		local n = 0
		for _, d in envFolder.Rooms:GetDescendants() do
			if d.ClassName == "SurfaceGui" and d.Enabled then n += 1 end
		end
		return n
	end
	local tested = nil
	for i = 1, #bands do
		for j, b in bands do
			if j < i then b.from, b.fade = -1000 + j, 0 elseif j == i then b.from, b.fade = 0, 0 else b.from, b.fade = 1000 + j, 0 end
		end
		bot:waitSeconds(1.5, "floor")
		local nearScreens = 0
		for _, rf in roomFolders() do
			local o = originOf(rf)
			local d = dressOf(rf)
			if d and math.sqrt((o.X - c.X) ^ 2 + (o.Z - c.Z) ^ 2) <= Env.EmitterRadius then
				for _, x in d:GetDescendants() do
					if x.ClassName == "SurfaceGui" then nearScreens += 1 end
				end
			end
		end
		if nearScreens >= 2 then
			eq(screensOn(), math.min(nearScreens, Budget.MaxScreens), bands[i].id .. ": every near screen runs while the cap allows it")
			local scap = Budget.MaxScreens
			Budget.MaxScreens = 1
			bot:waitSeconds(1, "floor")
			truthy(screensOn() <= 1, bands[i].id .. ": with the screen cap at 1, at most one runs, not " .. nearScreens .. " (" .. screensOn() .. ")")
			Budget.MaxScreens = scap
			tested = bands[i].id
			break
		end
	end
	truthy(tested ~= nil, "control: some kit put at least two screens near the player, so the screen cap was tested (" .. tostring(tested) .. ")")
	for i, b in bands do b.from, b.fade = original[i].from, original[i].fade end
	bot:waitSeconds(2, "floor")
end

--=========================================================================== D2. the densest floor
section("D2. the densest floor: every room reachable without touching a fuse, every band, centres and corners")

local densest = {}
do
	-- Open every door the player can reach without walking into a room that holds a fuse (picking one up
	-- would start the first run's front). Cells are fine: they do not.
	local visited = {}
	local order = {}
	local function doorsOf(room)
		local out = {}
		for _, d in bot:doors() do
			if d.lo == room or d.hi == room then table.insert(out, d) end
		end
		return out
	end
	local function explore(room)
		visited[room] = true
		table.insert(order, room)
		local rooms = bot:rooms()
		local c = rooms[room].center
		for _, d in doorsOf(room) do
			if not d.open then
				local leaf = d.part.Position
				local dir = Vector3.new(leaf.X - c.X, 0, leaf.Z - c.Z).Unit
				bot:walkTo(Vector3.new(leaf.X - dir.X * 6, 3, leaf.Z - dir.Z * 6), "floor")
				local w = 0
				while d.part.CanCollide ~= false and w < 50 do bot:tick(); w += 1 end
				bot:walkTo(Vector3.new(c.X, 3, c.Z), "floor")
			end
		end
		for _, d in doorsOf(room) do
			local nb = if d.lo == room then d.hi else d.lo
			rooms = bot:rooms()
			if d.part.CanCollide == false and rooms[nb] and not visited[nb] and rooms[nb].folder:FindFirstChild("Fuse") == nil then
				bot:cross(rooms, room, nb)
				explore(nb)
				rooms = bot:rooms()
				bot:cross(rooms, nb, room)
			end
		end
	end
	explore(entryRoom)
	eq(bot:state().run.fuses, 0, "control: no fuse was picked up, so the front is still held")
	-- Routes below go only through rooms without a fuse. A route through any open door once walked the bot
	-- through a fuse room D2 had never entered: it picked the fuse up, the first run's front started, and the
	-- floor could end under the check (seen in 1 of 8 runs as "attempt to index nil with 'center'").
	local function safeDoors()
		local rooms = bot:rooms()
		local out = {}
		for _, d in bot:doors() do
			local a, b = rooms[d.lo], rooms[d.hi]
			if a and b and a.folder:FindFirstChild("Fuse") == nil and b.folder:FindFirstChild("Fuse") == nil then
				table.insert(out, d)
			end
		end
		return out
	end
	print(string.format("    %d rooms walked, %d built", #order, #roomFolders()))

	local original = {}
	for i, b in bands do original[i] = { from = b.from, fade = b.fade } end
	local function onlyBand(i)
		for j, b in bands do
			if j < i then b.from, b.fade = -1000 + j, 0
			elseif j == i then b.from, b.fade = 0, 0
			else b.from, b.fade = 1000 + j, 0 end
		end
	end
	for i, b in bands do
		onlyBand(i)
		local peak = { parts = 0, emitters = 0, rate = 0, screens = 0 }
		local function sample()
			local c = census()
			for k in peak do peak[k] = math.max(peak[k], c[k]) end
		end
		where = "densest " .. b.id
		bot:waitSeconds(1)
		local problems = {}
		local noPath = 0
		for idx, room in order do
			local rooms = bot:rooms()
			if idx > 1 then
				local path = bot:route(rooms, safeDoors(), bot:roomAt(rooms, bot:pos()), room)
				if path then bot:followPath(path) else noPath += 1 end
				rooms = bot:rooms()
			end
			local c = rooms[room].center
			for _, off in { { 0, 0 }, { 9, 9 }, { -9, 9 }, { -9, -9 }, { 9, -9 } } do
				bot:walkTo(Vector3.new(c.X + off[1], 3, c.Z + off[2]), "floor")
				bot:waitSeconds(0.3, "floor")
				sample()
			end
		end
		for _, rf in roomFolders() do auditRoom(rf, problems) end
		for j = 1, math.min(4, #problems) do print("   " .. problems[j]) end
		eq(#problems, 0, "densest floor, " .. b.id .. ": every dressed room obeys every rule")
		densest[b.id] = peak
		-- back to the entry for the next band
		local rooms = bot:rooms()
		local path = bot:route(rooms, safeDoors(), bot:roomAt(rooms, bot:pos()), entryRoom)
		if path then bot:followPath(path) else noPath += 1 end
		eq(noPath, 0, "densest floor, " .. b.id .. ": every room was reached through fuse-free rooms")
		eq(bot:state().run.fuses, 0, "densest floor, " .. b.id .. ": control, no fuse picked up (the front is still held)")
	end
	for i, b in bands do b.from, b.fade = original[i].from, original[i].fade end
	bot:waitSeconds(2)
	print("    the densest floor, per band (peak while walking every room's centre and corners):")
	for _, b in bands do
		local p = densest[b.id]
		print(string.format("      %-9s %3d parts, %d emitters on (%2d/s), %2d screens on", b.id, p.parts, p.emitters, p.rate, p.screens))
		truthy(p.parts <= Budget.MaxLocalParts and p.emitters <= Budget.MaxEmitters and p.rate <= Budget.MaxEmitterRate
			and p.screens <= Budget.MaxScreens, b.id .. ": within every budget on the densest floor")
	end
	local c = bot:rooms()[entryRoom].center
	bot:walkTo(Vector3.new(c.X, 3, c.Z), "floor")
end

--=========================================================================== E. glow follows the room's power
section("E. glow follows each room's own light")

do
	-- the server rooms' racks glow; dress the held floor as a server vault for this
	local original = {}
	for i, b in bands do original[i] = { from = b.from, fade = b.fade } end
	for j, b in bands do
		if j < 3 then b.from, b.fade = -1000 + j, 0 elseif j == 3 then b.from, b.fade = 0, 0 else b.from, b.fade = 1000 + j, 0 end
	end
	where = "power test"
	bot:waitSeconds(2)
	local rooms = bot:rooms()
	local rf = rooms[entryRoom].folder
	local d = dressOf(rf)
	local function glowState()
		local neon, glowScreensOn, glowEmitOn, glows = 0, 0, 0, 0
		for _, p in d:GetDescendants() do
			if p:IsA("BasePart") and (p.Material == Enum.Material.Neon) then neon += 1 end
			if p.ClassName == "SurfaceGui" and p.LightInfluence == 0 then
				glows += 1
				if p.Enabled then glowScreensOn += 1 end
			end
			-- review finding 5: EVERY particle counts, not only self-lit ones (steam and drips left running in a dark
			-- room are landmarks in the dark if Roblox draws them unlit)
			if p.ClassName == "ParticleEmitter" and p.Enabled then glowEmitOn += 1 end
		end
		return neon, glowScreensOn, glowEmitOn, glows
	end
	local n0, s0, _, g0 = glowState()
	truthy(n0 + s0 > 0, "control: the lit server vault has something glowing (" .. n0 .. " neon, " .. s0 .. " of " .. g0 .. " screens)")
	local rl = rf.Fixture.RoomLight
	-- what the server does when a room dies (applyLight): the light goes off
	rl.Enabled = false
	bot:tick()
	local n1, s1, e1 = glowState()
	eq(n1 + s1 + e1, 0, "its light off: not one self-lit thing left in the room")
	rl.Enabled = true
	rl.Brightness = Config.Facility.FlickerLowBrightness -- the flicker's low step
	bot:tick()
	local n2, s2, e2 = glowState()
	eq(n2 + s2 + e2, 0, "the flicker's low step: off too (it flickers WITH the room)")
	rl.Brightness = Config.Facility.RoomLightBrightness
	bot:tick()
	local n3, s3 = glowState()
	eq(n3 + s3, n0 + s0, "back on: all of it back")

	-- review finding 5: particles that are NOT self-lit follow the room's power too. The flooded kit hangs a dripping
	-- pipe (light emission 0) in every room.
	for j, b in bands do
		if j < 4 then b.from, b.fade = -1000 + j, 0 elseif j == 4 then b.from, b.fade = 0, 0 else b.from, b.fade = 1000 + j, 0 end
	end
	where = "power test, flooded"
	bot:waitSeconds(2)
	d = dressOf(rf)
	local function drips()
		local on, plain = 0, 0
		for _, p in d:GetDescendants() do
			if p.ClassName == "ParticleEmitter" and (p.LightEmission or 0) == 0 then
				plain += 1
				if p.Enabled then on += 1 end
			end
		end
		return on, plain
	end
	local on0, plain0 = drips()
	truthy(plain0 >= 1 and on0 >= 1, "control: the lit flooded room's dripping pipe runs (" .. on0 .. " of " .. plain0 .. ")")
	rl.Enabled = false
	bot:tick()
	eq((drips()), 0, "its light off: the drips stop too (nothing moves in a dark room)")
	rl.Enabled = true
	rl.Brightness = Config.Facility.FlickerLowBrightness
	bot:tick()
	eq((drips()), 0, "the flicker's low step: stopped too")
	rl.Brightness = Config.Facility.RoomLightBrightness
	bot:tick()
	eq((drips()), on0, "back on: dripping again")
	for i, b in bands do b.from, b.fade = original[i].from, original[i].fade end
	bot:waitSeconds(2)
end

--=========================================================================== F. the real sublevels
section("F. played through the server: sublevels 1 -> 2 -> 3, the real front, the real bands")

do
	local darkSeen, violations = 0, 0
	local function powerAudit()
		for _, rf in roomFolders() do
			local d = dressOf(rf)
			local fx = rf:FindFirstChild("Fixture")
			local rl = fx and fx:FindFirstChild("RoomLight")
			if d and d.Parent and rl and (rl.Enabled == false or rl.Brightness < 0.8) then
				darkSeen += 1
				for _, p in d:GetDescendants() do
					if (p:IsA("BasePart") and p.Material == Enum.Material.Neon)
						or (p.ClassName == "SurfaceGui" and p.LightInfluence == 0 and p.Enabled)
						or (p.ClassName == "ParticleEmitter" and p.Enabled) then -- any particle (review finding 5)
						violations += 1
					end
				end
			end
		end
	end
	bot.onTick = function() frame(0.1); powerAudit() end

	local reached, attempts = 1, 0
	local restMidRun = false
	while reached < 3 and attempts < 3 do
		attempts += 1
		if bot:phase() == "hub" then
			assert(bot:board(h.workspace.Hub), "reboard")
			assert(bot:waitPhase("floor", 8), "arrive")
		end
		local k = bot:state().run.k
		where = "sublevel " .. k
		local r = bot:clearFloor()
		if r == "powered" then
			if k >= 2 and not restMidRun then
				-- rest never happens in a run, seated or not
				local hum = plr.Character:FindFirstChildOfClass("Humanoid")
				hum.SeatPart = h.workspace.Hub.Benches.Bench1
				hum.Sit = true
				bot:waitSeconds(2, "floor")
				restMidRun = EnvBus.last("rest") ~= nil and EnvBus.last("rest").resting == true
				truthy(not restMidRun, "sitting down in a run is not rest (seated for 2 s on sublevel " .. k .. ")")
				eq(h.Lighting.FacilityRestFocus.Enabled, false, "…the view does not soften")
				hum.SeatPart = nil
				hum.Sit = false
				restMidRun = true
			end
			bot:fire("Choose", "descend")
			assert(bot:waitPhase("ride", 3), "the ride down")
			local nk = k + 1
			local name = bands[EnvBands.indexAt(bands, nk)].name
			truthy(string.find(hudRoot.Banner.Text, "SUBLEVEL " .. nk .. " — " .. name, 1, true) ~= nil,
				"sublevel " .. nk .. "'s banner names its band: " .. hudRoot.Banner.Text)
			bot:waitSeconds(1, "ride")
			local line = bands[EnvBands.indexAt(bands, nk)].line
			eq(hudRoot.Hint.Text, "Going down to the " .. name .. "… " .. line, "…and the ride's hint gives the band's line")
			truthy(utf8.len(hudRoot.Hint.Text) <= LONGEST_OLD_HINT, "…no longer than the longest hint the HUD already had (" .. utf8.len(hudRoot.Hint.Text) .. ")")
			if nk == 3 then
				-- a band whose name already has its article: in memory, the void covers sublevel 3 for a moment
				local saved = {}
				for i, b in bands do saved[i] = { from = b.from, fade = b.fade } end
				for j, b in bands do
					if j < #bands then b.from, b.fade = -1000 + j, 0 else b.from, b.fade = 0, 0 end
				end
				bot:waitSeconds(0.3, "ride")
				eq(hudRoot.Hint.Text, "Going down to THE VOID… There was never a sublevel this deep.",
					"a band named THE ... is not 'the THE ...' on the ride's hint")
				for i, b in bands do b.from, b.fade = saved[i].from, saved[i].fade end
			end
			truthy(bot:waitPhase("floor", 8), "arrived on sublevel " .. nk)
			reached = math.max(reached, nk)
			bot:waitSeconds(4)
			local target = EnvBands.sample(bands, nk, "grade").tint
			truthy(same(cc.TintColor, target), string.format("sublevel %d's grade is the blend at %d (%s)", nk, nk, tostring(cc.TintColor)))
			local wrong = 0
			for _, rf in roomFolders() do
				if dressOf(rf) then
					local id = tonumber(string.match(rf.Name, "%d+"))
					local want = bands[Dressing.roomBand(Env, EnvBands, nk, id)].palette.light
					local _, light = palette(rf)
					if not same(light, want) then wrong += 1 end
				end
			end
			eq(wrong, 0, "every dressed room on sublevel " .. nk .. " wears the band Dressing.roomBand gives it")
		else
			print("    the bot's floor " .. k .. " ended " .. tostring(r) .. "; going again")
			bot:waitPhase("hub", 10)
		end
	end
	eq(reached, 3, "the bot reached sublevel 3 (in " .. attempts .. " attempt(s))")
	do
		local labs = 0
		for _, rf in roomFolders() do
			local _, light = palette(rf)
			if dressOf(rf) and same(light, bands[2].palette.light) then labs += 1 end
		end
		truthy(labs >= 1, "sublevel 3 is the laboratories (" .. labs .. " rooms)")
	end
	local r = bot:clearFloor()
	if r == "powered" then
		bot:fire("Choose", "extract")
		truthy(bot:waitPhase("hub", 8), "extracted to the break room")
		bot:waitSeconds(1)
		local board = envFolder:FindFirstChild("BreakRoom") and envFolder.BreakRoom.DepthBoard.Screen
		truthy(board ~= nil, "the break room's dressing is back")
		eq(board and board.Best.Text, "DEEPEST: SUBLEVEL 3", "the board brags")
		eq(board and board.Row2.Text, " 3  LABORATORIES", "…and names the laboratories now")
		eq(board and board.Row3.Text, " 5  ???", "…but not the server vault")
	else
		print("    floor 3 ended " .. tostring(r) .. " (the board is checked on the next join instead)")
		bot:waitPhase("hub", 10)
		bot:waitSeconds(1)
		local board = envFolder.BreakRoom.DepthBoard.Screen
		truthy(string.find(board.Best.Text, "SUBLEVEL", 1, true) ~= nil, "the board brags: " .. board.Best.Text)
	end
	print(string.format("    power audit: %d dark or flickering dressed-room observations, %d glowing things in them", darkSeen, violations))
	truthy(darkSeen > 0, "control: the audit saw rooms go dark under the real front")
	eq(violations, 0, "nothing self-lit in a dark or flickering room, ever")
	bot.onTick = function() frame(0.1) end
end

--=========================================================================== G. budgets
section("G. budgets (every frame of this file)")

print(string.format("    parts %d (budget %d) at %s", peaks.parts, Budget.MaxLocalParts, tostring(peakWhere.parts)))
print(string.format("    emitters on %d (budget %d), %d particles/s (budget %d) at %s", peaks.emitters, Budget.MaxEmitters, peaks.rate, Budget.MaxEmitterRate, tostring(peakWhere.rate)))
print(string.format("    screens on %d (budget %d) at %s; lights %d (budget %d); hazard parts %d", peaks.screens, Budget.MaxScreens, tostring(peakWhere.screens), peaks.lights, Budget.MaxLights, peaks.hazardParts))
truthy(peaks.parts <= Budget.MaxLocalParts, "local parts within budget")
truthy(peaks.emitters <= Budget.MaxEmitters, "emitters within budget")
truthy(peaks.rate <= Budget.MaxEmitterRate, "particles per second within budget")
truthy(peaks.screens <= Budget.MaxScreens, "screens within budget")
eq(peaks.lights, 0, "no light source, ever")
truthy(peaks.glowSeen > 0 and peaks.dullSeen > 0, "control: the census saw self-lit and plain particle emitters (" .. peaks.glowSeen .. ", " .. peaks.dullSeen .. ")")
eq(peaks.influenceWrong, 0, "every particle emitter is lit by the scene (LightInfluence 1) unless it is self-lit (0), at every frame")

--=========================================================================== H. clean
local envWarnings = 0
for _, w in h.warnings do
	if string.find(w, "FacilityEnv", 1, true) then envWarnings += 1; print("   warn: " .. w) end
end
eq(envWarnings, 0, "Env.client never warned (no invalid config, no failed dressing, no frame error)")
eq(#h:errors(), 0, "no scheduler errors")
for _, e in h:errors() do print("   " .. e) end

print(string.format("check_facilitynightmare_env: %d passed, %d failed", passed, failed))
