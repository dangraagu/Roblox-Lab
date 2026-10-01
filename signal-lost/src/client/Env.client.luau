-- Env.client.luau — SIGNAL LOST's environment on THIS client (EYECANDY.md). Presentation only.
--
-- Every frame, in this order:
--   1. the colour grade of the band you are in: by SECTOR (the server's k, the number on the HUD and the board),
--      blended by p = (k - 1) + visited / n^2 as you open modules, gliding on a half-life so the 3 s transit ride IS
--      the transition. The lifeboat has its own grade;
--   2. the exterior: the planet's phase by band, the Main Array's dish growing through the Array Spine and lit once
--      restored, one relay beacon per relay restored, and whatever crosses the sky in this band;
--   3. the built modules of YOUR sector within DressRadius dressed with their band's kit (Dressing.luau: nothing
--      where an item stands, off every doorway's line, nothing that glows like a signal colour) and repainted with
--      its palette; a module's kit is fixed the first time it is dressed; far modules are unparented, gone ones
--      destroyed, and the total is capped at Budget.MaxDressParts (the farthest go first);
--   4. the weather of the module you are in, at most Budget.MaxWeather emitters (EnvBands.capRates), and the band's
--      harmless critters;
--   5. the rare hazard (Hazards.luau): only in a vacuum module of a band that has one, past the sector's arrival
--      grace, with AIR >= 10, not resting; one at a time; the red ring is exactly the hit zone; a player who walks on
--      into the next module leaves it to fly through the empty ring (a near-miss); called off only when the player
--      leaves the sector. A hit is a shove this client applies to its own character; nothing is lost;
--   6. rest (Rest.luau): only where there is air — REST / R / ButtonX from the HUD, a lifeboat bench, or 20 s still.
-- It fires no remote, sets no attribute, never reads ServerStorage, a plan or a stream, and creates no light
-- source. It never writes the character's CFrame; a hazard hit only sets the root's velocity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Dressing = require(ReplicatedStorage:WaitForChild("Dressing"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Air = require(ReplicatedStorage:WaitForChild("Air"))
local EnvArt = require(ReplicatedStorage:WaitForChild("EnvArt"))
local EnvBus = require(ReplicatedStorage:WaitForChild("EnvBus"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("SignalRemotes")
local StateEvent = remotes:WaitForChild("State")
local NoticeEvent = remotes:WaitForChild("Notice")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Env, St, Hz, RC, Budget = Config.Env, Config.Station, Config.Hazards, Config.Rest, Config.Budget
local bands = Env.Bands
local CELL = St.CellSize
local INNER = CELL / 2 - St.WallThickness

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if ok then
		for _, b in bands do
			local okG, whyG = Dressing.gradeOk(b.grade)
			local okP, whyP = Dressing.paletteOk(Env, b.palette)
			if not okG or not okP then
				ok, err = false, b.id .. ": " .. tostring(whyG or whyP)
				break
			end
		end
	end
	if not ok then
		warn("[SignalEnv] Config.Env is invalid (" .. tostring(err) .. "); the station stays as the server built it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validateStation(Hz)
if not hazardsOn then
	warn("[SignalEnv] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validateStation(RC)
if not restOn then
	warn("[SignalEnv] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================ the local world

local localRoot = Instance.new("Folder")
localRoot.Name = "SignalEnvLocal"
localRoot.Parent = workspace
local art = EnvArt.new(localRoot, Config, Dressing)
art:buildExterior()

-- Take over the server's Fx.applyLighting objects by name rather than stacking a second set.
local function rig(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end
local cc = rig("ColorCorrectionEffect", "FxColorCorrection")
local atmosphere = rig("Atmosphere", "FxAtmosphere")
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "SignalRestFocus"
restFocus.FarIntensity = 0.35
restFocus.FocusDistance = 10
restFocus.InFocusRadius = 14
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

--============================================================================ state from the server

local S: any = nil
StateEvent.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	if s.uid ~= nil and s.uid ~= player.UserId then return end
	S = s
end)
local bragAt: number? = nil
NoticeEvent.OnClientEvent:Connect(function(kind)
	if kind == "brag" then bragAt = -1 end
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
	if changed("tint", g.tint) then (cc :: any).TintColor = EnvArt.c3(g.tint) end
	if changed("saturation", g.saturation) then (cc :: any).Saturation = g.saturation end
	if changed("contrast", g.contrast) then (cc :: any).Contrast = g.contrast end
	if changed("brightness", g.brightness) then (cc :: any).Brightness = g.brightness end
	if changed("atmosColor", g.atmosColor) then (atmosphere :: any).Color = EnvArt.c3(g.atmosColor) end
	if changed("atmosDecay", g.atmosDecay) then (atmosphere :: any).Decay = EnvArt.c3(g.atmosDecay) end
end

--============================================================================ where am I

-- This player's zone: the one whose Pod is nearest in X to the character.
local function zoneOf(root: BasePart?): Instance?
	local station = workspace:FindFirstChild("Station")
	if not station or not root then return nil end
	local best, bestD = nil, math.huge
	for _, z in station:GetChildren() do
		local pod = z:FindFirstChild("Pod")
		local fl = pod and pod:FindFirstChild("PodFloor")
		if fl and fl:IsA("BasePart") then
			local d = math.abs(fl.Position.X - root.Position.X)
			if d < bestD then best, bestD = z, d end
		end
	end
	return best
end

local function floorTop(fl: BasePart): Vector3
	return Vector3.new(fl.Position.X, fl.Position.Y + fl.Size.Y / 2, fl.Position.Z)
end

-- The module folders of my sector: { folder, id, origin (floor top), sides = { E/W/N/S = hatch there }, keep }
local function modulesOf(zone: Instance?): { any }
	local out = {}
	local sector = zone and zone:FindFirstChild("Sector")
	local mods = sector and sector:FindFirstChild("Modules")
	if not mods then return out end
	for _, mf in mods:GetChildren() do
		local id = tonumber(string.match(mf.Name, "^Module_(%d+)$"))
		local fl = mf:FindFirstChild("Floor")
		if id and fl and fl:IsA("BasePart") then
			table.insert(out, { folder = mf, id = id, origin = floorTop(fl) })
		end
	end
	return out
end

local function moduleAt(mods: { any }, p: Vector3): any
	for _, m in mods do
		if math.abs(p.X - m.origin.X) <= CELL / 2 and math.abs(p.Z - m.origin.Z) <= CELL / 2 then return m end
	end
	return nil
end

local KEEP_NAMES = { "ReturnConsole", "RelayConsole", "FloorHatch", "RelayMast" }

-- Which keep-out parts a module has now, as one number. The splice builds the floor hatch and the relay console in
-- a module that was dressed long before (REVIEW-1 finding 6); a change here re-dresses it. Four lookups, no list.
local function keepSignature(folder: Instance): number
	local sig = 0
	for i, name in KEEP_NAMES do
		if folder:FindFirstChild(name) then sig += 2 ^ (i - 1) end
	end
	return sig
end

-- What a module's own server parts say: its doorways (walls split in three) and what the dressing must keep off.
local function layoutOf(m: any): (any, { any })
	local sides = {}
	local keep = {}
	for _, c in m.folder:GetChildren() do
		local side = string.match(c.Name, "^Wall(%u)_Top$")
		if side then sides[side] = true end
		if c:IsA("BasePart") and (c.Name == "ReturnConsole" or c.Name == "RelayConsole" or c.Name == "FloorHatch" or c.Name == "RelayMast") then
			local p = c.Position - m.origin
			table.insert(keep, { x = p.X, z = p.Z, r = 3.5 })
		end
	end
	return sides, keep
end

--============================================================================ 3. dressing

local recs: { [Instance]: any } = {}

local function dressPass(k: number, visited: number, n2: number, root: BasePart, zone: Instance?)
	local seen = {}
	local list = {}
	for _, m in modulesOf(zone) do
		seen[m.folder] = true
		local dx, dz = m.origin.X - root.Position.X, m.origin.Z - root.Position.Z
		local d = math.sqrt(dx * dx + dz * dz)
		local rec = recs[m.folder]
		local keepBand: number? = nil
		if rec and rec.k ~= k then
			art:destroyModule(rec)
			recs[m.folder] = nil
			rec = nil
		elseif rec and rec.keepSig ~= keepSignature(m.folder) then
			-- a part to keep clear appeared after the module was dressed (the splice's floor hatch and console): dress it
			-- again, around them, in the band it was first dressed in
			keepBand = rec.bandIndex
			art:destroyModule(rec)
			recs[m.folder] = nil
			rec = nil
		end
		if not rec and (d <= Env.DressRadius or keepBand ~= nil) then
			-- the kit is fixed at the progress of the moment the module is first dressed (foreshadowing)
			local bi = keepBand or Dressing.roomBand(Env, EnvBands, k, m.id, visited, n2)
			local band = bands[bi]
			local sides, keep = layoutOf(m)
			local pieces = Dressing.build(Config, band.kit, m.id, k, sides, keep)
			art:repaint(m.folder, band.palette)
			rec = art:dressModule(pieces, band.palette, (zone and zone.Name or "z") .. "_" .. m.id .. "_" .. k, m.origin)
			rec.k = k
			rec.bandIndex = bi
			rec.keepSig = keepSignature(m.folder)
			rec.module = m.folder
			recs[m.folder] = rec
		end
		if rec then
			rec.d = d
			table.insert(list, rec)
		end
	end
	for mf, rec in recs do
		if not seen[mf] then
			art:destroyModule(rec)
			recs[mf] = nil
		end
	end
	-- near first; the budget goes to the nearest modules, the farthest are put away
	table.sort(list, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		return a.key < b.key
	end)
	local used = 0
	for _, rec in list do
		local fits = rec.d <= Env.DressRadius and used + #rec.parts <= Budget.MaxDressParts
		if fits then used += #rec.parts end
		art:setParented(rec, fits)
	end
end

local function clearDressing()
	for mf, rec in recs do
		art:destroyModule(rec)
		recs[mf] = nil
	end
end

--============================================================================ 5. hazards, 6. rest

local rest = Rest.new()
local hz = Hazards.newScheduler(Hz, rand)
local zoneInside: boolean? = nil
local lastPos: Vector3? = nil
local benches: Instance? = nil
local restWant: boolean? = nil

EnvBus.on(function(kind, data)
	if kind == "restRequest" and type(data) == "table" then
		restWant = data.want == true
	end
end)

local function hazardName(kind: string): string
	local k = Hz.Kinds[kind]
	return if k and k.name then k.name else string.upper(kind)
end

local t = 0
local dressAcc = math.huge
local passK: number? = nil
local frameError = false
local exteriorWhere: string? = nil
local exteriorAt: Vector3? = nil
local exteriorDish: number? = nil
local exteriorSwing: number? = nil

local function frame(dt: number)
	t += dt
	local phase = if S then S.phase else nil
	local k = if S then S.k else nil
	local inSector = phase == "sector" or phase == "transit" or phase == "blackout"
	local root = hrp()
	local n2 = if S and S.n then S.n * S.n else 1
	local visited = if S and S.visited then S.visited else 0
	local p = if k then Dressing.progress(k, visited, n2) else 0

	-- 1. the grade
	local target = if inSector and k then EnvBands.sample(bands, p, "grade") else Env.Lifeboat.grade
	grade = EnvBands.approachTable(grade, target, dt, Env.HalfLifeSeconds)
	lightAcc += dt
	if lightAcc >= 1 / Env.LightingHz then
		lightAcc = 0
		writeGrade(grade)
	end

	-- 2. the exterior where the openings look (EnvArt.LAYOUT): beyond the lifeboat's window, fixed; in a sector
	--    overhead, following the character (re-placed once it has moved ExteriorFollowStuds)
	local camCF = camera and camera.CFrame
	local kk = k or ((S and S.best or 0) + 1)
	local bi = Dressing.bandOf(Env, kk)
	local dishScale = math.clamp((kk - 22) / 8, 0.3, 1)
	local where = if inSector and root then "sector" else "hub"
	local anchor = if where == "sector" and root then Vector3.new(root.Position.X, 0, root.Position.Z) else Vector3.new(0, 0, 0)
	if bragAt == -1 then
		bragAt = t
		art:brag(t)
	end
	local moved = exteriorAt == nil or (anchor - exteriorAt).Magnitude > Env.ExteriorFollowStuds
	if where ~= exteriorWhere or moved or dishScale ~= exteriorDish or art.swing ~= exteriorSwing then
		exteriorWhere, exteriorAt, exteriorDish, exteriorSwing = where, anchor, dishScale, art.swing
		art:placeExterior(anchor, dishScale, where)
	end
	local ex = EnvBands.sample(bands, if k then p else (kk - 1), "exterior")
	art:updateExterior(t, ex, bands[bi].exterior.phase, if S then S.best or 0 else 0, S ~= nil and S.arrayDone == true)
	local critterSpec = bands[bi].critters
	art:updateCrossers(t, critterSpec)

	-- 3. dressing: every DressEverySeconds, and at once when the sector changed
	dressAcc += dt
	local zone = if inSector then zoneOf(root) else nil
	if root and inSector and k then
		if dressAcc >= Env.DressEverySeconds or k ~= passK then
			dressAcc = 0
			passK = k
			dressPass(k, visited, n2, root, zone)
		end
	elseif passK ~= nil then
		passK = nil
		clearDressing()
	end

	-- 4. weather and critters in the module I am in
	local mods = if zone then modulesOf(zone) else {}
	local here = if root and phase == "sector" then moduleAt(mods, root.Position) else nil
	if here and k then
		local w = EnvBands.weights(bands, p)
		local rates, specs = {}, {}
		for i, weight in w do
			local spec = bands[i].weather
			rates[spec.kind] = (rates[spec.kind] or 0) + Env.WeatherRate * weight
			specs[spec.kind] = spec
		end
		art:setWeather(here.origin, EnvBands.capRates(rates, Budget.MaxWeather, Budget.WeatherMaxTotal, 0.5), specs)
		local vacHere = S.moduleType == "vacuum"
		local fits = critterSpec.where == "any" or (critterSpec.where == "vacuum" and vacHere) or (critterSpec.where == "air" and not vacHere)
		art:updateCritters(t, if fits then here.origin else nil, if fits then critterSpec else nil, if fits then 2 else 0)
	else
		art:setWeather(nil, {}, {})
		art:updateCritters(t, nil, nil, 0)
	end

	-- 5. hazards
	local hum = humanoid()
	local moving, still = false, true
	if root then
		if lastPos and dt > 0 then
			local dx, dz = root.Position.X - lastPos.X, root.Position.Z - lastPos.Z
			local speed = math.sqrt(dx * dx + dz * dz) / dt
			moving = speed > 0.5
			still = speed <= Hz.StillSpeed
		end
		lastPos = root.Position
	end
	if hum and (hum :: any).MoveDirection and (hum :: any).MoveDirection.Magnitude > 0.1 then moving = true end
	if hazardsOn and root then
		local vac = phase == "sector" and S.moduleType == "vacuum"
		local band = bands[bi]
		local eligible = here ~= nil and Rest.hazardsMayRun(rest)
			and Air.hazardEligible(Config, vac, #band.hazards > 0, S and S.secondsIn, S and S.air or 0)
		local look = if camCF then camCF.LookVector else Vector3.new(0, 0, -1)
		local ctx = {
			eligible = eligible,
			grounded = true,
			still = still,
			kinds = band.hazards,
			aim = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z },
			yaw = math.atan2(look.X, look.Z),
			pitch = math.asin(math.clamp(look.Y, -1, 1)),
			module = if here then here.id else false,
			sector = k, -- a live hazard from another sector is called off even where a module id repeats (REVIEW-1)
			box = if here then { minX = here.origin.X - INNER, maxX = here.origin.X + INNER, minY = here.origin.Y,
				maxY = here.origin.Y + St.CeilingHeight, minZ = here.origin.Z - INNER, maxZ = here.origin.Z + INNER } else nil,
		}
		local active = hz.active
		local t0 = if active then active.t else 0
		local ev = Hazards.step(hz, Hz, dt, ctx, rand)
		local floorY = if here then here.origin.Y else root.Position.Y - St.StandHeight
		if ev and ev.type == "spawn" then
			local z = Hazards.zone(ev.plan, Hz.PlayerRadius)
			art:hazardShow(ev.plan.kind, z, floorY)
			zoneInside = true
			EnvBus.fire("hazard", { phase = "warn", name = hazardName(ev.plan.kind), seconds = ev.plan.arriveAt })
		elseif ev and (ev.type == "done" or ev.type == "cancel") then
			art:hazardHide()
			zoneInside = nil
			EnvBus.fire("hazard", { phase = "clear", name = hazardName(ev.plan.kind) })
		end
		local plan = hz.active
		if plan then
			local z = Hazards.zone(plan, Hz.PlayerRadius)
			local pos = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius)
			art:hazardUpdate(pos, z, floorY, plan.locked, live, t)
			local here3 = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
			if live then
				local inside = Hazards.inZone(plan, here3, Hz.PlayerRadius)
				if inside ~= zoneInside then
					zoneInside = inside
					EnvBus.fire("hazard", { phase = "zone", inside = inside, name = hazardName(plan.kind) })
				end
			end
			if Hazards.checkHitStation(Hz, plan, t0, plan.t, here3, Hz.PlayerRadius) then
				plan.hit = true
				local v = Hazards.knockVelocity(Hz, plan, here3)
				local vel = root.AssemblyLinearVelocity or Vector3.new()
				root.AssemblyLinearVelocity = Vector3.new(v.x, vel.Y + v.y, v.z)
				FxClient.shake(0.4, 0.6)
				EnvBus.fire("hazard", { phase = "hit", name = hazardName(plan.kind) })
			end
		end
	end

	-- 6. rest: only where there is air
	if restOn then
		local where = if phase == "hub" then "hub" elseif phase == "sector" then (if S.moduleType == "vacuum" then "vacuum" else "air") else nil
		if benches == nil then
			local boat = workspace:FindFirstChild("Lifeboat")
			benches = boat and boat:FindFirstChild("Benches")
		end
		local seat = hum and (hum :: any).SeatPart
		local seated = seat ~= nil and benches ~= nil and seat:IsDescendantOf(benches)
		local ctx = { moving = moving and not seated, grounded = true, threat = hz.active ~= nil, where = where }
		local wasResting = Rest.isResting(rest)
		if restWant ~= nil then
			local want = restWant
			restWant = nil
			if want then
				local r = Rest.request(rest, RC, ctx)
				if r == "refused" then
					EnvBus.fire("restRefused", { reason = Rest.refusal(RC, where) })
				elseif r == "queued" then
					-- debris still flying through a ring the player walked out of: it starts when the flight ends (REVIEW-1)
					EnvBus.fire("restRefused", { reason = RC.Text.Queued })
				elseif r == "resting" and hum and not seated then
					pcall(function() (hum :: any).Sit = true end)
				end
			else
				Rest.stop(rest)
			end
		end
		if seated and not Rest.isResting(rest) and Rest.allowedIn(RC, where) then
			Rest.request(rest, RC, ctx)
		end
		Rest.update(rest, RC, dt, ctx)
		if Rest.isResting(rest) ~= wasResting then
			restFocus.Enabled = Rest.isResting(rest)
			if not Rest.isResting(rest) and hum and not seated then
				pcall(function() (hum :: any).Sit = false end) -- stand back up from a REST sit
			end
			EnvBus.fire("rest", { resting = Rest.isResting(rest), source = rest.source })
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken environment must not flood the output
		warn("[SignalEnv] frame error: " .. tostring(err))
	end
end)
