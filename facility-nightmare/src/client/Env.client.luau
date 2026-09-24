-- Env.client.luau — FACILITY's environment on THIS client (EYECANDY.md). Presentation only.
--
-- Every frame, in this order:
--   1. the colour grade of the band you are in, by SUBLEVEL (the server's run.k — the number on the HUD
--      and in leaderstats.Deepest), never by time; the break room has its own warm grade. It glides with a
--      half-life, so the 4 s ride down IS the transition. Never brighter than the server's preset.
--   2. the built rooms of YOUR floor within DressRadius are dressed with their band's kit and recoloured
--      with its palette (Dressing.luau: nothing where an item can stand, nothing between an eye and one,
--      nothing in front of a doorway, nothing that glows like a fuse or a cell); rooms that fall out of
--      range are unparented, rooms whose floor is gone are destroyed. A pass runs every DressEverySeconds,
--      and AT ONCE on the frame a room that should be dressed is not (a door just opened, the player just
--      arrived), so a room is ready on the first frame it can be seen. During the ride (the car is closed on
--      all sides) the entry room is dressed wherever it is, so it is ready the moment the player arrives in it;
--   3. the rare environmental hazard (Hazards.luau), only in a lit room, never on the car or lift pad,
--      never in the first ArrivalGraceSeconds on a sublevel, called off if its room flickers; floors are
--      first person, so the HUD banner (over EnvBus) says STEP OUT while the player is in the ring and
--      YOU ARE CLEAR once out; then glow follows each room's own light (off when it is off, flickering
--      when it flickers), the rooms sharing what the hazard leaves of the emitter budget;
--   4. the break room's dressing while you are in it, and its DEPTH RECORD board;
--   5. rest (Rest.luau): only in the break room — a bench, or standing still there.
-- It fires no remote, adds no remote, sets no attribute, never reads ServerStorage, an item, a plan or a
-- seed, and creates no light source. It never writes the character's CFrame; a hazard hit only sets the
-- character's velocity (the client owns its own character's physics) and nothing is lost by it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Dressing = require(ReplicatedStorage:WaitForChild("Dressing"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local EnvArt = require(ReplicatedStorage:WaitForChild("EnvArt"))
local EnvBus = require(ReplicatedStorage:WaitForChild("EnvBus"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("FacilityRemotes")
local StateEvent = remotes:WaitForChild("State")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Env, F, Hz, RestCfg, Budget = Config.Env, Config.Facility, Config.Hazards, Config.Rest, Config.Budget
local bands = Env.Bands
local INNER = F.CellSize / 2 - F.WallThickness

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if ok then
		for _, b in bands do
			local okG, whyG = Dressing.gradeOk(Env, b.grade)
			local okP, whyP = Dressing.paletteOk(Env, b.palette)
			if not okG or not okP then
				ok, err = false, b.id .. ": " .. tostring(whyG or whyP)
				break
			end
		end
	end
	if not ok then
		warn("[FacilityEnv] Config.Env is invalid (" .. tostring(err) .. "); the facility stays as the server built it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[FacilityEnv] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[FacilityEnv] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================ the local world

local folder = Instance.new("Folder")
folder.Name = "FacilityEnvLocal"
folder.Parent = workspace
local art = EnvArt.new(folder, Config, Dressing)
art:buildHub(bands)

-- Take over the server's Fx.applyLighting objects by name rather than stacking a second set.
local function rig(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end
local cc = rig("ColorCorrectionEffect", "FxColorCorrection")
local atmosphere = rig("Atmosphere", "FxAtmosphere")
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "FacilityRestFocus"
restFocus.FarIntensity = 0.3
restFocus.FocusDistance = 12
restFocus.InFocusRadius = 16
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

--============================================================================ state from the server

local S: any = nil
StateEvent.OnClientEvent:Connect(function(s)
	S = s
end)

local function hrp(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

--============================================================================ 1. the grade

local grade: any = nil
local written: { [string]: any } = {}
local lightAcc = math.huge

local function c3(v: { number }): Color3
	return Color3.fromRGB(math.clamp(math.floor(v[1] + 0.5), 0, 255), math.clamp(math.floor(v[2] + 0.5), 0, 255),
		math.clamp(math.floor(v[3] + 0.5), 0, 255))
end
local function changed(key: string, v: any): boolean
	local last = written[key]
	if type(v) == "table" then
		if last and math.abs(last[1] - v[1]) < 0.5 and math.abs(last[2] - v[2]) < 0.5 and math.abs(last[3] - v[3]) < 0.5 then
			return false
		end
		written[key] = { v[1], v[2], v[3] }
		return true
	end
	if last ~= nil and math.abs(last - v) < 1e-3 then return false end
	written[key] = v
	return true
end
local function writeGrade(g: any)
	if changed("tint", g.tint) then (cc :: any).TintColor = c3(g.tint) end
	if changed("saturation", g.saturation) then (cc :: any).Saturation = g.saturation end
	if changed("contrast", g.contrast) then (cc :: any).Contrast = g.contrast end
	if changed("brightness", g.brightness) then (cc :: any).Brightness = g.brightness end
	if changed("atmosColor", g.atmosColor) then (atmosphere :: any).Color = c3(g.atmosColor) end
	if changed("atmosDecay", g.atmosDecay) then (atmosphere :: any).Decay = c3(g.atmosDecay) end
end

--============================================================================ 2. dressing

local recs: { [Instance]: any } = {}
local myZone: Instance? = nil

local function zoneOf(root: BasePart?): Instance?
	local fac = workspace:FindFirstChild("Facility")
	if not fac or not root then return nil end
	local best, bestD = nil, math.huge
	for _, z in fac:GetChildren() do
		local car = z:FindFirstChild("RideCar")
		local plate = car and car:FindFirstChild("RideFloor")
		if plate then
			local d = math.abs((plate :: BasePart).Position.X - root.Position.X)
			if d < bestD then best, bestD = z, d end
		end
	end
	return best
end

local function floorTop(fl: BasePart): Vector3
	return Vector3.new(fl.Position.X, fl.Position.Y + fl.Size.Y / 2, fl.Position.Z)
end

-- The room's server props as room-local boxes (what Dressing.build steers around).
local function propsOf(rf: Instance, o: Vector3): { any }
	local out = {}
	for _, c in rf:GetChildren() do
		if c:IsA("BasePart") and string.sub(c.Name, 1, 4) == "Prop" then
			local p, s = c.Position - o, c.Size
			table.insert(out, { name = string.sub(c.Name, 5),
				min = { p.X - s.X / 2, p.Y - s.Y / 2, p.Z - s.Z / 2 }, max = { p.X + s.X / 2, p.Y + s.Y / 2, p.Z + s.Z / 2 } })
		end
	end
	return out
end

local function recolourDoors(floor: Instance, k: number)
	local doors = floor:FindFirstChild("Doors")
	if not doors then return end
	for _, leaf in doors:GetChildren() do
		local lo = tonumber(string.match(leaf.Name, "^Door_(%d+)_%d+$"))
		if lo and leaf:IsA("BasePart") then
			art:recolourDoor(leaf, bands[Dressing.roomBand(Env, EnvBands, k, lo)].palette)
		end
	end
end

local function dressPass(inRun: boolean, k: number?, riding: boolean)
	local root = hrp()
	local seen = {}
	myZone = if inRun then zoneOf(root) else nil
	if inRun and myZone and k and root then
		local floor = myZone:FindFirstChild("Floor")
		local rooms = floor and floor:FindFirstChild("Rooms")
		if floor and rooms then
			local newRoom = false
			for _, rf in rooms:GetChildren() do
				local id = tonumber(string.match(rf.Name, "^Room_(%d+)$"))
				local fl = rf:FindFirstChild("Floor")
				if id and fl and fl:IsA("BasePart") then
					seen[rf] = true
					local o = floorTop(fl)
					local dx, dz = o.X - root.Position.X, o.Z - root.Position.Z
					local d = math.sqrt(dx * dx + dz * dz)
					local bi = Dressing.roomBand(Env, EnvBands, k, id)
					local key = bi .. ":" .. k .. ":" .. myZone.Name .. ":" .. id
					local rec = recs[rf]
					if rec and rec.key ~= key then
						art:destroyRoom(rec)
						recs[rf] = nil
						rec = nil
					end
					if d <= Env.DressRadius or riding then
						if not rec then
							local props = propsOf(rf, o)
							local parts = Dressing.build(Env, F, bands[bi].kit, id, k, props)
							local ok, why = Dressing.check(Env, F, parts, props)
							if not ok then
								-- belt and braces: a room whose dressing fails the rules gets none, not a bad one
								warn("[FacilityEnv] dressing for " .. rf.Name .. " failed its check (" .. tostring(why) .. "); left bare.")
								parts = {}
							end
							rec = art:dressRoom(rf, parts, bands[bi], key, o)
							rec.id = id
							rec.k = k
							rec.bandIndex = bi
							recs[rf] = rec
							newRoom = true
						end
						art:setParented(rec, true)
					elseif rec then
						art:setParented(rec, false)
					end
				end
			end
			if newRoom then recolourDoors(floor, k) end
		end
	end
	for rf, rec in recs do
		if not seen[rf] then
			art:destroyRoom(rec)
			recs[rf] = nil
		end
	end
end

-- Is a built room of my floor that should be dressed not dressed for this sublevel yet? Within DressRadius, or any
-- room during the ride. Checked EVERY frame, so a room the server just built (a door opened) or one the player just
-- arrived beside is dressed and repainted before the frame is drawn, instead of showing the server's colours until
-- the next pass (EYECANDY.md §11, review finding 2). Cheap: at most 25 rooms, and a room already dressed for this
-- sublevel costs one table lookup.
local function undressedInView(k: number, root: BasePart, riding: boolean): boolean
	local floor = myZone and myZone:FindFirstChild("Floor")
	local rooms = floor and floor:FindFirstChild("Rooms")
	if not rooms then return false end
	local r2 = Env.DressRadius * Env.DressRadius
	for _, rf in rooms:GetChildren() do
		local rec = recs[rf]
		if not (rec and rec.parented and rec.k == k) and string.match(rf.Name, "^Room_%d+$") then
			local fl = rf:FindFirstChild("Floor")
			if fl and fl:IsA("BasePart") then
				local dx, dz = fl.Position.X - root.Position.X, fl.Position.Z - root.Position.Z
				if riding or dx * dx + dz * dz <= r2 then return true end
			end
		end
	end
	return false
end

local function updateRooms(t: number, hazardEmitters: number)
	local root = hrp()
	if not root then return end
	local list = {}
	for _, rec in recs do
		if rec.parented then
			local dx, dz = rec.origin.X - root.Position.X, rec.origin.Z - root.Position.Z
			table.insert(list, { rec = rec, d = math.sqrt(dx * dx + dz * dz) })
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		return a.rec.key < b.rec.key
	end)
	local emitBudget = Budget.MaxEmitters - hazardEmitters
	local screenBudget = Budget.MaxScreens
	for _, e in list do
		local rec = e.rec
		local near = e.d <= Env.EmitterRadius
		local powered = EnvArt.roomPowered(rec.folder, F.RoomLightBrightness)
		local emitterOn = false
		-- a dark room's emitters are off (every particle follows power), so they take none of the budget
		if near and powered and #rec.emitters > 0 and emitBudget >= #rec.emitters then
			emitterOn = true
			emitBudget -= #rec.emitters
		end
		local screensOn = near and screenBudget >= #rec.screens
		if screensOn then screenBudget -= #rec.screens end
		art:updateRoom(rec, t, powered, near, emitterOn, screensOn)
	end
end

-- The room folder of MY floor that the character stands in, and its floor-top centre.
local function roomAt(root: BasePart?): (Instance?, number?, Vector3?)
	if not root or not myZone then return nil, nil, nil end
	local floor = myZone:FindFirstChild("Floor")
	local rooms = floor and floor:FindFirstChild("Rooms")
	if not rooms then return nil, nil, nil end
	local p = root.Position
	for _, rf in rooms:GetChildren() do
		local fl = rf:FindFirstChild("Floor")
		if fl and fl:IsA("BasePart") and math.abs(p.X - fl.Position.X) <= F.CellSize / 2 and math.abs(p.Z - fl.Position.Z) <= F.CellSize / 2 then
			return rf, tonumber(string.match(rf.Name, "^Room_(%d+)$")), floorTop(fl)
		end
	end
	return nil, nil, nil
end

-- Does this room hold the entry car or the exit lift (both visible the moment the room is)?
local function hasPad(o: Vector3): boolean
	local floor = myZone and myZone:FindFirstChild("Floor")
	if not floor then return false end
	for _, spec in { { "EntryCar", "CarFloor" }, { "ExitLift", "LiftPlatform" } } do
		local m = floor:FindFirstChild(spec[1])
		local plate = m and m:FindFirstChild(spec[2])
		if plate and plate:IsA("BasePart") and math.abs(plate.Position.X - o.X) < F.CellSize / 2
			and math.abs(plate.Position.Z - o.Z) < F.CellSize / 2 then
			return true
		end
	end
	return false
end

--============================================================================ 5. rest, 6. hazards

local rest = Rest.new()
local hz = Hazards.newScheduler(Hz, rand)
local zoneInside: boolean? = nil -- during a warning: is the player inside its zone (last told to the HUD)
local floorK: number? = nil -- the sublevel this client last saw the player arrive on (nil: not on a floor)
local floorSeconds: number? = nil -- seconds since that arrival
local lastPos: Vector3? = nil
local benches: Instance? = nil

local function hazardName(kind: string): string
	local k = Hz.Kinds[kind]
	return if k and k.name then k.name else string.upper(kind)
end

local t = 0
local dressAcc = math.huge
local passInRun: boolean? = nil -- what the last dressing pass saw: in a run, and on which sublevel
local passK: number? = nil
local frameError = false

local function frame(dt: number)
	t += dt
	local phase = if S then S.phase else nil
	local run = S and S.run
	local k = if run then run.k else nil
	local inRun = phase == "ride" or phase == "floor" or phase == "dying"
	local root = hrp()

	-- 1. the grade
	local target = if inRun and k then EnvBands.sample(bands, k, "grade") else Env.BreakRoom.grade
	grade = EnvBands.approachTable(grade, target, dt, Env.HalfLifeSeconds)
	lightAcc += dt
	if lightAcc >= 1 / Env.LightingHz then
		lightAcc = 0
		writeGrade(grade)
	end

	-- 2. dressing: every DressEverySeconds, and at once when the run or the sublevel changed or a room that should be
	-- dressed is not (a room is ready on the first frame it can be seen, never a pass later)
	dressAcc += dt
	local riding = phase == "ride"
	if dressAcc >= Env.DressEverySeconds or inRun ~= passInRun or k ~= passK
		or (inRun and k ~= nil and root ~= nil and undressedInView(k, root, riding)) then
		dressAcc = 0
		passInRun, passK = inRun, k
		dressPass(inRun, k, riding)
	end

	-- 3. hazards (before the rooms take their emitters: a live hazard's warning is one of the budget's)
	if hazardsOn and root then
		local ctx: any = { eligible = false, kinds = {}, spot = nil, room = nil, activeRoomLit = nil }
		local rf, id, o = roomAt(root)
		-- a new sublevel (or a new run) starts the arrival grace; the ride and the break room clear it
		local onK = if phase == "floor" and run then run.k else nil
		if onK ~= floorK then
			floorK = onK
			floorSeconds = if onK then 0 else nil
		end
		if floorSeconds then floorSeconds += dt end
		if phase == "floor" and run and rf and id and o and Rest.hazardsMayRun(rest) and Hazards.arrivalOk(Hz, floorSeconds) then
			local lit = EnvArt.roomPowered(rf, F.RoomLightBrightness) and not run.flicker and not run.dark
			if lit then
				ctx.eligible = true
				ctx.kinds = bands[Dressing.roomBand(Env, EnvBands, k, id)].hazards
				ctx.room = rf
				local p = root.Position
				if Hazards.spotOk(Hz, INNER, p.X - o.X, p.Z - o.Z, hasPad(o)) then
					ctx.spot = { x = p.X, y = o.Y, z = p.Z }
				end
			end
		end
		local active = hz.active
		if active then
			local ar = active.room
			local lit = phase == "floor" and ar.Parent ~= nil and EnvArt.roomPowered(ar, F.RoomLightBrightness)
			if ar == rf and run then lit = lit and not run.flicker and not run.dark end
			ctx.activeRoomLit = lit
		end
		local t0 = if active then active.t else 0
		local ev = Hazards.step(hz, Hz, dt, ctx, rand)
		if ev and ev.type == "spawn" then
			art:hazardShow(ev.plan.kind, Vector3.new(ev.plan.x, ev.plan.y, ev.plan.z), ev.plan.radius, ev.plan.y + F.CeilingHeight)
			-- the player stands at the zone's centre by construction; the banner lasts exactly the telegraph
			zoneInside = true
			EnvBus.fire("hazard", { phase = "warn", name = hazardName(ev.plan.kind), seconds = ev.plan.burstAt })
		elseif ev and (ev.type == "done" or ev.type == "cancel") then
			art:hazardHide()
			zoneInside = nil
			EnvBus.fire("hazard", { phase = "clear", name = hazardName(ev.plan.kind) })
		end
		local plan = hz.active or (if ev and ev.type == "done" then ev.plan else nil)
		if plan then
			if hz.active then
				local ph = Hazards.phase(plan)
				art:hazardUpdate(ph, math.clamp(plan.t / plan.burstAt, 0, 1), t)
				-- Floors are first person: a ring at your own feet and a source straight overhead are both
				-- out of view. The HUD banner is the telegraph a player can see, so it says whether the step
				-- out of the ring worked (EYECANDY.md §3).
				if ph == "warn" then
					local p = root.Position
					local inside = rf == plan.room and Hazards.inZone(plan, { x = p.X, y = p.Y, z = p.Z })
					if inside ~= zoneInside then
						zoneInside = inside
						EnvBus.fire("hazard", { phase = "zone", inside = inside, name = hazardName(plan.kind) })
					end
				end
			end
			if ev and ev.type == "burst" then
				EnvBus.fire("hazard", { phase = "burst", name = hazardName(plan.kind) })
			end
			local p = root.Position
			if Hazards.checkHit(plan, t0, plan.t, { x = p.X, y = p.Y, z = p.Z }, rf == plan.room) then
				plan.hit = true
				local camCF = camera and camera.CFrame
				local look = if camCF then camCF.LookVector else Vector3.new(0, 0, -1)
				local v = Hazards.knockVelocity(Hz, plan, { x = p.X, y = p.Y, z = p.Z }, { x = -look.X, y = 0, z = -look.Z })
				local vel = root.AssemblyLinearVelocity or Vector3.new()
				root.AssemblyLinearVelocity = Vector3.new(v.x, vel.Y + v.y, v.z)
				FxClient.shake(0.5, 0.7)
				local look2 = EnvArt.HAZARD_KINDS[plan.kind]
				FxClient.flash(if look2 then Color3.fromRGB(look2.burst[1], look2.burst[2], look2.burst[3]) else Color3.new(1, 1, 1), 0.25, 0.4)
				EnvBus.fire("hazard", { phase = "hit", name = hazardName(plan.kind) })
			end
		end
	end

	-- 3b. glow follows each room's power; rooms share what the hazard leaves of the emitter budget
	updateRooms(t, if hz.active then 1 else 0)

	-- 4. the break room
	art:setHubParented(not inRun)
	if S then art:updateBoard(S.bestSublevel or 0) end

	-- 5. rest
	if restOn then
		if benches == nil then
			local hub = workspace:FindFirstChild("Hub")
			benches = hub and hub:FindFirstChild("Benches")
		end
		local hum = humanoid()
		local seat = hum and (hum :: any).SeatPart
		local seated = seat ~= nil and benches ~= nil and seat:IsDescendantOf(benches)
		local moving = false
		if hum and (hum :: any).MoveDirection and (hum :: any).MoveDirection.Magnitude > 0.1 then moving = true end
		if root then
			if lastPos and (root.Position - lastPos).Magnitude > 0.2 then moving = true end
			lastPos = root.Position
		end
		local wasResting = Rest.isResting(rest)
		Rest.update(rest, RestCfg, dt, { phase = phase, seated = seated, moving = moving,
			boarding = S ~= nil and (S.boarding or 0) > 0 })
		if Rest.isResting(rest) ~= wasResting then
			restFocus.Enabled = Rest.isResting(rest)
			EnvBus.fire("rest", { resting = Rest.isResting(rest), source = rest.source })
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken environment must not flood the output
		warn("[FacilityEnv] frame error: " .. tostring(err))
	end
end)
