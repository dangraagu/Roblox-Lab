-- Lost & Found Depot — the tags, boards and taps stay exactly as readable with the WINGS built.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_wingview.luau 2>&1
--
-- WHY. The job is reading tags. check_lostfounddepot_view.luau measured what a tap hits and what a camera
-- sees in a bare bay (the ~99.4% front-row tap figure, 0 blocked sightlines). The wings add roofs, lamps,
-- string lights, wall signs, a weather host and landmarks, all built by src/client/Wings.client.luau. This
-- file runs the SAME model (copied from _view: rays against oriented part boxes, one-sided SurfaceGuis, the
-- ClickDetector-in-a-Model rule, the Popper camera that CanCollide = false parts do not pull in) on the
-- local player's bay twice in the same run: bare, then with the real Wings client built for every wing.
-- The wings' parts join the scene as occluders (every one that is parented, at its current transparency;
-- anything not fully invisible stops the eye, which is conservative for the 0.72 glass). The numbers must
-- be IDENTICAL, and no sightline may end on a wing part.
--
-- Two camera sets. The sorting cameras of _view (8-16 studs back, 5-45 degrees down: at most 15.8 studs
-- up) with the client's camera held low, so every roof is at full weight. And zoomed-out cameras (24-40
-- studs back, 30-60 degrees down: 16.5-39 studs up, above the walls) with the client's camera held high,
-- where Config.Env.OverheadFade takes the roof away. Hazards are switched off for the measurement (in
-- memory): they are meant to be seen, for a few seconds every 2-3 minutes.
--
-- THE MODEL is _view's, and everything in it is on the Studio list: nothing here renders.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-wingview", viewport = { 1280, 720 }, touch = false })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(3000 + unseeded * 17)
		end
		return realRandom.new(seed)
	end,
}

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- the same depot _view measures: a stage-3 sorter's bay, the local player
local store = h.services.DataStoreService:GetDataStore("LostFoundDepot_v1")
local UID = 840004
store:SetAsync("u_" .. UID, { data = { v = 1, shifts = 9, redeemed = {} } })

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot wingview: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local EnvBands = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBands"))

local plr = h:join("Reader", UID)
h:advance(0.1)
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)
local bay = plr.RespawnLocation.Parent
local OX = bay:FindFirstChild("BayPad").Position.X

--============================================================================ _view's model, verbatim

local V3 = Vector3.new

local function segBox(p0, p1, part)
	local cf = part.CFrame
	local a = cf:PointToObjectSpace(p0)
	local b = cf:PointToObjectSpace(p1)
	local hx, hy, hz = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
	local tmin, tmax = 0, 1
	local A = { a.X, a.Y, a.Z }
	local D = { b.X - a.X, b.Y - a.Y, b.Z - a.Z }
	local H = { hx, hy, hz }
	for i = 1, 3 do
		if math.abs(D[i]) < 1e-9 then
			if A[i] < -H[i] or A[i] > H[i] then return nil end
		else
			local t1 = (-H[i] - A[i]) / D[i]
			local t2 = (H[i] - A[i]) / D[i]
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	return tmin
end

local FACE_AXIS = { Right = { 1, 1 }, Left = { 1, -1 }, Top = { 2, 1 }, Bottom = { 2, -1 }, Back = { 3, 1 }, Front = { 3, -1 } }
local function faceName(face) return string.match(tostring(face), "(%a+)$") end
local function opaqueGuiFace(part)
	for _, c in part:GetChildren() do
		if c.ClassName == "SurfaceGui" and c.Enabled ~= false then
			for _, g in c:GetDescendants() do
				if (g.ClassName == "TextLabel" or g.ClassName == "Frame" or g.ClassName == "TextButton"
					or g.ClassName == "ImageLabel") and g.BackgroundTransparency < 1 then
					return faceName(c.Face)
				end
			end
		end
	end
	return nil
end
local function occludeT(part, p0, p1)
	if part.Transparency < 1 then
		return segBox(p0, p1, part)
	end
	local face = opaqueGuiFace(part)
	if face == nil then return nil end
	local ax = FACE_AXIS[face]
	local a = part.CFrame:PointToObjectSpace(p0)
	local b = part.CFrame:PointToObjectSpace(p1)
	local A, B = { a.X, a.Y, a.Z }, { b.X, b.Y, b.Z }
	local H = { part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2 }
	local i, s = ax[1], ax[2]
	if s * A[i] <= H[i] then return nil end
	local d = B[i] - A[i]
	if math.abs(d) < 1e-9 then return nil end
	local t = (s * H[i] - A[i]) / d
	if t < 0 or t > 1 then return nil end
	for j = 1, 3 do
		if j ~= i and math.abs(A[j] + (B[j] - A[j]) * t) > H[j] then return nil end
	end
	return t
end
local function reachesSlot(hit, slot)
	if hit == nil then return false end
	if hit == slot then return slot:FindFirstChildOfClass("ClickDetector") ~= nil end
	local item = slot:FindFirstChild("Item")
	return item ~= nil and hit:IsDescendantOf(item) and item:FindFirstChildOfClass("ClickDetector") ~= nil
end
local function collect(roots)
	local out = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, { part = d, pos = d.Position, r = d.Size.Magnitude / 2 })
			end
		end
	end
	return out
end
local function first(parts, p0, p1, filter)
	local dir = p1 - p0
	local len = dir.Magnitude
	local best, bestT = nil, math.huge
	for _, e in parts do
		local w = e.pos - p0
		local s = if len > 0 then math.clamp(w:Dot(dir) / (len * len), 0, 1) else 0
		if (e.pos - (p0 + dir * s)).Magnitude <= e.r + 1e-6 and filter(e.part) then
			local t = segBox(p0, p1, e.part)
			if t and t < bestT then best, bestT = e.part, t end
		end
	end
	return best, bestT
end
local function firstVisible(parts, p0, p1, exclude)
	local dir = p1 - p0
	local len = dir.Magnitude
	local best, bestT = nil, math.huge
	for _, e in parts do
		local w = e.pos - p0
		local s = if len > 0 then math.clamp(w:Dot(dir) / (len * len), 0, 1) else 0
		if (e.pos - (p0 + dir * s)).Magnitude <= e.r + 1e-6 and not (exclude and exclude(e.part)) then
			local t = occludeT(e.part, p0, p1)
			if t and t < bestT then best, bestT = e.part, t end
		end
	end
	return best, bestT
end
local function camera(parts, rootPos, lookFlat, d, pitchDeg)
	local focus = rootPos + V3(0, 1.5, 0)
	local p = math.rad(pitchDeg)
	local cam = focus - lookFlat * (d * math.cos(p)) + V3(0, d * math.sin(p), 0)
	local hit, t = first(parts, focus, cam, function(q) return q.CanCollide and q.Transparency < 0.25 end)
	if hit then
		local len = (cam - focus).Magnitude
		cam = focus + (cam - focus) * math.max(0, t - 0.5 / len)
	end
	return cam
end
local function flatDir(from, to)
	local v = V3(to.X - from.X, 0, to.Z - from.Z)
	if v.Magnitude < 1e-6 then return V3(0, 0, -1) end
	return v.Unit
end
local ROOT_Y = 3.51

local TAP_STANDS = {
	bin = { { -4, -1 }, { 0, 0 }, { 4, -1 }, { -6, 1.5 }, { 6, 1.5 } },
	pad = { { -4, 12 }, { 0, 14 }, { 4, 12 }, { -6, 11 }, { 6, 11 } },
}
local POINTS = { { 0, 0, 0 }, { 0, 0.3, 0 }, { 0.3, 0, 0 }, { -0.3, 0, 0 }, { 0, 0, 0.3 }, { 0, 0, -0.3 } }
local LOW_TAP_CAMS = { { 8, 10 }, { 8, 30 }, { 12.5, 15 }, { 12.5, 35 }, { 16, 20 }, { 16, 45 } }
local LOW_READ_CAMS = {}
for _, d in { 8, 12.5, 16 } do
	for _, p in { 5, 10, 15, 20, 25, 30, 45 } do table.insert(LOW_READ_CAMS, { d, p }) end
end
local HIGH_CAMS = {}
for _, d in { 24, 32, 40 } do
	for _, p in { 30, 45, 60 } do table.insert(HIGH_CAMS, { d, p }) end
end

local function isItem(q)
	local node = q.Parent
	return node ~= nil and node.Name == "Item"
end
local function tagPoint(s)
	local slot = bay:FindFirstChild("Slot_" .. s)
	local tag = slot:FindFirstChild("Tag")
	local anchor = tag.Adornee or slot
	return anchor.Position + tag.StudsOffset, tag.Enabled
end

-- Taps from _view's stands and cameras; sightlines from _view's readers to every read target.
-- `wingSet` names the wing parts; returns a result table.
local function measure(parts, tapCams, readCams, wingSet)
	local res = { tapTot = 0, tapOk = 0, sight = 0, blocked = 0, byWing = 0, wingNames = {}, maxCamY = 0 }
	local P = V3(OX, ROOT_Y, 0)
	-- taps
	for s = 1, 8 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		local item = slot:FindFirstChild("Item")
		if item then
			local pieces = {}
			for _, c in item:GetDescendants() do
				if c:IsA("BasePart") then pieces[c] = true end
			end
			for _, stands in TAP_STANDS do
				for _, st in stands do
					local root = V3(OX + st[1], ROOT_Y, st[2])
					if (root - slot.Position).Magnitude <= Config.Bay.ItemReach then
						for _, cm in tapCams do
							local cam = camera(parts, root, flatDir(root, slot.Position), cm[1], cm[2])
							res.maxCamY = math.max(res.maxCamY, cam.Y)
							for piece in pieces do
								for _, o in POINTS do
									local pt = (piece.CFrame * CFrame.new(o[1] * piece.Size.X, o[2] * piece.Size.Y, o[3] * piece.Size.Z)).Position
									local seg = pt - cam
									local past = cam + seg * (1 + 0.05 / math.max(seg.Magnitude, 1e-6))
									local vis = firstVisible(parts, cam, past, nil)
									if vis and wingSet[vis] then
										res.byWing += 1
										res.wingNames[vis.Name] = true
									end
									if vis and pieces[vis] then
										res.tapTot += 1
										local hit = first(parts, cam, past, function(q) return q.CanQuery end)
										if reachesSlot(hit, slot) then res.tapOk += 1 end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	-- sightlines
	local function sight(root, lookAt, target, targetPart)
		for _, cm in readCams do
			local cam = camera(parts, root, flatDir(root, lookAt), cm[1], cm[2])
			res.maxCamY = math.max(res.maxCamY, cam.Y)
			res.sight += 1
			local hit = firstVisible(parts, cam, target, function(q) return q == targetPart or isItem(q) end)
			if hit then
				res.blocked += 1
				if wingSet[hit] then
					res.byWing += 1
					res.wingNames[hit.Name] = true
				end
			end
		end
	end
	local door = bay:FindFirstChild("Door")
	local backlog = bay:FindFirstChild("BacklogSign")
	for _, st in { { 0, 14 }, { -4, 12 }, { 4, 12 } } do
		local root = V3(OX + st[1], ROOT_Y, st[2])
		local ahead = V3(OX + st[1], ROOT_Y, -30)
		for s = 1, 8 do
			local pt, shown = tagPoint(s)
			if shown then sight(root, ahead, pt, nil) end
		end
		sight(root, ahead, door.Position, door)
		sight(root, ahead, backlog.Position, backlog)
	end
	for k = 1, 6 do
		local base = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Base")
		local flat = V3(base.Position.X, ROOT_Y, base.Position.Z)
		local root = flat + (P - flat).Unit * 5
		for s = 1, 8 do
			local pt, shown = tagPoint(s)
			if shown then sight(root, P, pt, nil) end
		end
	end
	for k = 1, 6 do
		local sign = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Sign")
		sight(P, sign.Position, sign.Position, sign)
	end
	for _, n in { "MemoBoard", "NameSign", "ManualBoard" } do
		local b = bay:FindFirstChild(n)
		sight(P, b.Position, b.Position, b)
	end
	local nameSign = bay:FindFirstChild("NameSign")
	for k = 1, 6 do
		local base = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Base")
		local flat = V3(base.Position.X, ROOT_Y, base.Position.Z)
		sight(flat + (P - flat).Unit * 5, nameSign.Position, nameSign.Position, nameSign)
	end
	return res
end

--============================================================================ bare bay

local bayOnly = collect({ bay })
local bareLow = measure(bayOnly, LOW_TAP_CAMS, LOW_READ_CAMS, {})
local bareHigh = measure(bayOnly, HIGH_CAMS, HIGH_CAMS, {})
print(string.format("  bare bay, sorting cameras (up to %.1f studs): taps %d/%d reach the item (%.1f%%), %d sightlines, %d blocked by a fixture",
	bareLow.maxCamY, bareLow.tapOk, bareLow.tapTot, 100 * bareLow.tapOk / math.max(1, bareLow.tapTot), bareLow.sight, bareLow.blocked))
print(string.format("  bare bay, zoomed-out cameras (up to %.1f studs): taps %d/%d, %d sightlines, %d blocked",
	bareHigh.maxCamY, bareHigh.tapOk, bareHigh.tapTot, bareHigh.sight, bareHigh.blocked))
truthy(bareLow.tapTot > 1000 and bareLow.sight > 1000, "CONTROL: the bare measurement saw the tray and the boards")
truthy(bareHigh.maxCamY > 30 and bareHigh.tapTot > 1000, "CONTROL: the zoomed-out set really looked down from above the walls")
-- The sorting set reaches 16.3 studs (16 back, 45 degrees down), a little above OverheadFade.Gone. It is
-- measured with every roof at FULL weight all the same (the client's camera is held at 11), which is the
-- harder case: in play the roof is already gone for those few cameras.

--============================================================================ the wings, every one

local Hz = Config.Hazards
Hz.IntervalMin = 1e9 -- in memory, this run only: no hazard during the measurement
Hz.IntervalMax = 1e9 + 1
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okW, errW = h:tryRun("client/Wings.client")
truthy(okW, "Wings.client loads (" .. tostring(errW) .. ")")
local folder = h.workspace:FindFirstChild("DepotWings")
local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
local hum = plr.Character:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hrp.CFrame = CFrame.new(OX, 3, 0)
local StateEvent = h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("State")
local sent = StateEvent:sentTo(plr)
local base = sent[#sent].args[1]
local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in t do o[k] = copy(v) end
	return o
end
local cam = h.workspace.CurrentCamera
local function frames(seconds, camY)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		cam.CFrame = CFrame.new(Vector3.new(OX, camY, 14), Vector3.new(OX, 3, 0))
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end

local bands = Config.Env.Bands
for _, b in bands do
	local p = copy(base)
	p.shifts = b.from
	StateEvent:FireClient(plr, p) -- the server's own payload with the career set: the HUD passes it on
	frames(8, 11) -- a sorting camera: every roof at full weight
	local wingParts, wingSet = {}, {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(wingParts, d)
			wingSet[d] = true
		end
	end
	local shownRoof = 0
	for _, d in wingParts do
		if (d.Name == "CityRoof" or d.Name == "AirportRoof" or d.Name == "TrainShed" or d.Name == "ParkLights" or d.Name == "StationDome")
			and d.Transparency < 0.99 then
			shownRoof += 1
		end
	end
	local scene = collect({ bay, folder })
	local low = measure(scene, LOW_TAP_CAMS, LOW_READ_CAMS, wingSet)
	frames(3, 30) -- zoomed out above the walls: the roof fades away
	local highParts = 0
	for _, d in folder:GetDescendants() do if d:IsA("BasePart") then highParts += 1 end end
	local scene2 = collect({ bay, folder })
	local wingSet2 = {}
	for _, d in folder:GetDescendants() do if d:IsA("BasePart") then wingSet2[d] = true end end
	local high = measure(scene2, HIGH_CAMS, HIGH_CAMS, wingSet2)
	local names = {}
	for n in low.wingNames do table.insert(names, n) end
	for n in high.wingNames do table.insert(names, n) end
	table.sort(names)
	print(string.format("  %-20s %3d wing parts (%2d roof shown to a sorting camera; %3d when zoomed out): taps %d/%d, sightlines blocked %d / %d (zoomed %d / %d), on a wing part %d",
		b.name, #wingParts, shownRoof, highParts, low.tapOk, low.tapTot, low.blocked, low.sight, high.blocked, high.sight, low.byWing + high.byWing))
	eq(low.tapTot, bareLow.tapTot, b.name .. ": exactly the same tray points are visible to a sorting camera as in the bare bay")
	eq(low.tapOk, bareLow.tapOk, b.name .. ": and every tap reaches the same item (" .. string.format("%.1f%%", 100 * low.tapOk / math.max(1, low.tapTot)) .. ")")
	eq(low.blocked, bareLow.blocked, b.name .. ": no sightline to a tag, board, sign or the door is newly blocked")
	eq(high.tapTot, bareHigh.tapTot, b.name .. ": zoomed out above the walls, the same tray points are visible")
	eq(high.tapOk, bareHigh.tapOk, b.name .. ": ... and the same taps land")
	eq(high.blocked, bareHigh.blocked, b.name .. ": ... and no sightline is newly blocked (the roof has faded away)")
	eq(low.byWing + high.byWing, 0, b.name .. ": no sightline ends on a wing part (" .. table.concat(names, ",") .. ")")
	truthy(#wingParts > 20 and shownRoof > 10, "CONTROL: " .. b.name .. "'s wing was built, roof and all (" .. #wingParts .. " parts)")
	truthy(highParts < #wingParts, "CONTROL: zoomed out, the roof really went (" .. highParts .. " < " .. #wingParts .. ")")
end

--============================================================================ the landmarks show over the walls

-- The walls are 16 studs high and the sorting cameras sit at most ~16 up, so a landmark that is too low or
-- too far down the sky hides behind them for the whole job. Every landmark must show over the walls to a
-- sorting camera that looks its way: from the pick point and every bin stand, each of _view's sorting
-- cameras turned toward the landmark, a landmark counts as seen when the top of any of its parts is not
-- hidden by the bay (walls, boards, fixtures).
do
	local LANDMARK = {
		CitySkyline = "city skyline", Airfield = "airfield", Viaduct = "viaduct", TrainCar = "viaduct",
		ParkRides = "rides", WheelRim = "rides", WheelSpoke = "rides", Gondola = "rides",
		EarthView = "Earth", GalaxyView = "galaxy",
	}
	local seen, looked, heroName = {}, {}, {}
	local P = V3(OX, ROOT_Y, 0)
	local readers = { P }
	for k = 1, 6 do
		local base = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Base")
		local flat = V3(base.Position.X, ROOT_Y, base.Position.Z)
		table.insert(readers, flat + (P - flat).Unit * 5)
	end
	for _, b in bands do
		local p = copy(base)
		p.shifts = b.from
		StateEvent:FireClient(plr, p)
		frames(8, 11)
		local groups = {}
		for _, d in folder:GetChildren() do
			local g = d:IsA("BasePart") and d.Transparency < 1 and LANDMARK[d.Name]
			if g then
				groups[g] = groups[g] or {}
				table.insert(groups[g], d)
			end
		end
		for g, parts in groups do
			-- the landmark's HERO: its biggest part (the Earth, the galaxy disc, the viaduct deck, a wheel
			-- spoke, the tallest tower, the terminal). Cameras turn toward it; it counts as seen when a
			-- point on its upper half (its top, a quarter of the way along either way) is not hidden.
			local hero = parts[1]
			for _, d in parts do if d.Size.Magnitude > hero.Size.Magnitude then hero = d end end
			local cf, sz = hero.CFrame, hero.Size
			local ex = math.abs(cf.RightVector.X) * sz.X / 2 + math.abs(cf.UpVector.X) * sz.Y / 2 + math.abs(cf.LookVector.X) * sz.Z / 2
			local ey = math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
			local ez = math.abs(cf.RightVector.Z) * sz.X / 2 + math.abs(cf.UpVector.Z) * sz.Y / 2 + math.abs(cf.LookVector.Z) * sz.Z / 2
			local c = hero.Position
			local pts = { V3(c.X, c.Y + ey * 0.9, c.Z) }
			for _, o in { { 0.25, 0 }, { -0.25, 0 }, { 0, 0.25 }, { 0, -0.25 } } do
				table.insert(pts, V3(c.X + o[1] * 2 * ex, c.Y + ey * 0.5, c.Z + o[2] * 2 * ez))
			end
			heroName[g] = heroName[g] or string.format("%.0f x %.0f x %.0f", sz.X, sz.Y, sz.Z)
			for _, root in readers do
				for _, cm in LOW_READ_CAMS do
					local cam = camera(bayOnly, root, flatDir(root, c), cm[1], cm[2])
					looked[g] = (looked[g] or 0) + 1
					local any = false
					for _, pt in pts do
						if firstVisible(bayOnly, cam, pt, nil) == nil then any = true; break end
					end
					if any then seen[g] = (seen[g] or 0) + 1 end
				end
			end
		end
	end
	local names = {}
	for g in looked do table.insert(names, g) end
	table.sort(names)
	local line = {}
	for _, g in names do table.insert(line, string.format("%s (%s) %.0f%%", g, heroName[g], 100 * (seen[g] or 0) / looked[g])) end
	print("  landmarks over the walls, share of sorting cameras turned their way that see them: " .. table.concat(line, ", "))
	eq(#names, 6, "CONTROL: all six landmark sets were looked for")
	for _, g in names do
		truthy((seen[g] or 0) / looked[g] >= 0.5, string.format("the %s shows over the walls to at least half the sorting cameras turned its way (%.0f%%)",
			g, 100 * (seen[g] or 0) / looked[g]))
	end
end

eq(#h:errors(), 0, "no thread died")
for _, e in h:errors() do print("scheduler error: " .. e) end
print(string.format("lost-found-depot wingview: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot wingview check failed", 0) end
