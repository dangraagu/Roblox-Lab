-- Steal a Cryptid - NOTHING LOCAL STANDS BETWEEN THE CAMERA AND WHAT THE PLAYER MUST SEE, from anywhere.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_view.luau 2>&1
--
-- Review 2026-09-24 (EYECANDY.md section 13), finding 3: camp scenery keeps out of the camp and of the
-- corridor behind the gate (Night.keepOut), but a raider who zooms out and orbits looks at the camp across
-- the rest of it. With the reviewer's probe (5 raider spots, zoom 20-128, 36 yaws, 25 degrees down), a
-- pine crown hid the raider in 15 of 900 camera spots in the Rare camp, a redwood in 15 of 900 in the
-- Mythic one. This file, before the fix (camera targets include the camp's corners and zoom reaches 400):
-- 114 / 625 / 1 / 745 of 2 880 spots per tier (mesas, cacti, pines, redwoods, a bat, wisps). Now NightArt
-- hides every scenery part and the client recycles every critter whose footprint enters the 2-D hull of
-- the camera and the camp (Night.campViewHull), on the same frame the camera moves.
-- The same class at HOME, found by extending the probe: a far pine stood between a zoomed-out camera and
-- the player at 1-4 of 72 spots per zoom (60-400) at the back and front strips. Home scenery is now hidden
-- while it is inside the hull of the camera and the player's root (Config.Night.HomeViewRadius).
--
-- Real server, real Hunt remote, real client. For every camp tier:
--   V1 5 raider spots x zoom 20, 40, 60, 90, 128, 200, 300, 400 (Roblox's default CameraMaxZoomDistance is
--      400 and the game sets none) x 24 yaws x 3 pitches (10, 25, 50 degrees down) = 2 880 camera spots,
--      one client frame each: no shown local part (scenery or critter; each tested as the oriented box of
--      its declared Size, a superset of any Ball/Cylinder drawn inside it) crosses the line from the camera
--      to the raider's root, nor to any of 10 points of the camp (its four corners low and high, the gate,
--      the middle of the cage row);
--   V2 not vacuous: from the side at far zoom the guard really hid scenery, and never most of it;
--   V3 the usual raid view (the follow camera behind the gate) and a camera over the camp hide nothing;
--      after the far spots every hidden part comes back.
-- At home (rank 4: every home piece):
--   H1 6 spots (apron, behind the cage row, the back and front strips, the road's centre and its -x end) x
--      the same zooms, yaws and pitches: no shown local SCENERY part crosses the line from the camera to the
--      player (root, head, 1.5 studs to each side) (critters at home are small moving life and are not hidden: see EYECANDY.md);
--   H2 the follow camera hides nothing; H3 not vacuous, and everything comes back; H4 a pine that the line to the
--      root just misses but the line to the player's side crosses is hidden (the view box is the character's).
-- And V4: a camera held behind the loch for Nessie's whole lap: an ANIMATED piece is judged where it is, every
-- frame (she is hidden while she crosses the view, and nothing ever stands in it).
-- Headless limits: nothing renders; there is no Poppercam (these parts are non-collidable, so Roblox's
-- Poppercam would not pull the camera in front of them either).

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Night = require("../steal-a-cryptid/src/shared/Night")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-view", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local W = Config.World
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 6606
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "jackalope", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 1e9, savedAt = NOW, cagesUnlocked = 9, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman", "nessie", "bigfoot" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end
assert(h:tryRun("server/Main.server"))
h:advance(1)
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Viewer", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local cam = h.workspace.CurrentCamera
local folder = h.workspace:FindFirstChild("CryptidNight")

local function follow(dt)
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
for _ = 1, 60 do follow(1 / 30) end
local sent = remotes.State:sentTo(plr)
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. sent[#sent].args[1].plot)
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local boardPos = frameCF:PointToWorldSpace(Vector3.new(W.Apron.Board.x, W.RootHeight, W.Apron.Board.z - 4))

-- scenery = the camp pieces' parts (critters and the weather host are not scenery; critters are still tested in V1)
local SCENERY = { "Mesa", "Cactus", "RingPine", "Redwood", "Castle", "Glimpse", "Nessie" }
local function isScenery(name)
	for _, pre in SCENERY do
		if string.sub(name, 1, #pre) == pre then return true end
	end
	return false
end
local function shownParts()
	local out = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and d.Position.X > 3500 and d.Name ~= "WeatherHost" then
			table.insert(out, d)
		end
	end
	return out
end
local function sceneryShown()
	local n = 0
	for _, d in shownParts() do
		if isScenery(d.Name) then n += 1 end
	end
	return n
end

-- the segment camera -> target against a part's oriented box (its declared Size); a camera inside the box is
-- not counted (the renderer culls back faces: a camera inside a part does not see it)
local function segHitsBox(a, b, cf, size)
	local la, lb = cf:PointToObjectSpace(a), cf:PointToObjectSpace(b)
	local half = size / 2
	if math.abs(la.X) <= half.X and math.abs(la.Y) <= half.Y and math.abs(la.Z) <= half.Z then return false end
	local t0, t1 = 0, 1
	for _, ax in { "X", "Y", "Z" } do
		local d = lb[ax] - la[ax]
		local lo, hi = -half[ax], half[ax]
		if math.abs(d) < 1e-9 then
			if la[ax] < lo or la[ax] > hi then return false end
		else
			local ta, tb = (lo - la[ax]) / d, (hi - la[ax]) / d
			if ta > tb then ta, tb = tb, ta end
			t0, t1 = math.max(t0, ta), math.min(t1, tb)
			if t0 > t1 then return false end
		end
	end
	return true
end

local totals = { spots = 0, blocked = 0 }
local byTier = {}
for tier = 1, 4 do
	hrp.CFrame = CFrame.new(boardPos)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	for _ = 1, 120 do follow(1 / 30) end -- the restart cooldown
	remotes:FindFirstChild("Hunt"):simulateFireServer(plr, tier)
	h:advance(0.05)
	local slot = Night.pocketSlot(Config, hrp.Position.X)
	truthy(slot ~= nil, "tier " .. tier .. ": the Hunt remote took me into a camp")
	if not slot then continue end
	local ox = Night.pocketOriginX(Config, slot)
	for _ = 1, 180 do follow(1 / 30) end -- 6 s: the camp's place has faded in
	-- V3: a camera over the middle of the camp sees everything; the gate follow camera hides nothing more
	cam.CFrame = CFrame.new(Vector3.new(ox + 36, 220, 57), Vector3.new(ox + 36, 0, 56))
	RunService.RenderStepped:Fire(1 / 30)
	h:advance(1 / 30)
	for _ = 1, 15 do RunService.RenderStepped:Fire(1 / 30); h:advance(1 / 30) end
	local ref = sceneryShown()
	for _ = 1, 15 do follow(1 / 30) end
	local atGate = sceneryShown()
	eq(atGate, ref, string.format("tier %d V3: the raid's follow camera behind the gate hides no scenery (%d of %d shown)", tier, atGate, ref))

	local spots = { { "entry", 36, 28 }, { "mid", 36, 56 }, { "cage walk", 36, 84 }, { "left side", 4, 56 }, { "right side", 68, 56 } }
	local camp = { x0 = -1, x1 = W.PlotWidth + 1, z0 = W.ApronDepth - 1, z1 = W.ApronDepth + W.CellSize * (W.CageRow + 1) + 1 }
	local targets = {}
	for _, c in { { camp.x0, camp.z0 }, { camp.x1, camp.z0 }, { camp.x1, camp.z1 }, { camp.x0, camp.z1 } } do
		table.insert(targets, Vector3.new(ox + c[1], 1, c[2]))
		table.insert(targets, Vector3.new(ox + c[1], W.FenceHeight, c[2]))
	end
	table.insert(targets, Vector3.new(ox + W.CellSize * (W.GateCol - 0.5), 2, W.ApronDepth + W.CellSize / 2)) -- the gate
	table.insert(targets, Vector3.new(ox + W.PlotWidth / 2, 3, W.ApronDepth + W.CellSize * (W.CageRow + 0.5))) -- the cage row
	local total, blocked, first = 0, 0, nil
	local byName = {}
	local zooms = { 20, 40, 60, 90, 128, 200, 300, 400 }
	local byZoom = {}
	local hidMost, hidAny = 0, 0
	for _, sp in spots do
		local root = Vector3.new(ox + sp[2], W.RootHeight, sp[3])
		for _, D in zooms do
			for yawDeg = 0, 345, 15 do
				for _, pitchDeg in { 10, 25, 50 } do
					local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
					local camPos = root + Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)) * D
					cam.CFrame = CFrame.lookAt(camPos, root)
					RunService.RenderStepped:Fire(1 / 30)
					h:advance(1 / 30)
					total += 1
					byZoom[D] = byZoom[D] or { 0, 0 }
					byZoom[D][1] += 1
					local parts = shownParts()
					local hit = nil
					for _, p in parts do
						if segHitsBox(camPos, root, p.CFrame, p.Size) then hit = p; break end
						for _, t in targets do
							if segHitsBox(camPos, t, p.CFrame, p.Size) then hit = p; break end
						end
						if hit then break end
					end
					if hit then
						blocked += 1
						byZoom[D][2] += 1
						byName[hit.Name] = (byName[hit.Name] or 0) + 1
						first = first or string.format("%s between a camera at zoom %d, yaw %d, pitch %d and the %s spot", hit.Name, D, yawDeg, pitchDeg, sp[1])
					end
					local shown = sceneryShown()
					if shown < ref then hidAny += 1 end
					hidMost = math.max(hidMost, ref - shown)
				end
			end
		end
	end
	local names = {}
	for n, c in byName do table.insert(names, n .. " " .. c) end
	local zl = {}
	for _, D in zooms do table.insert(zl, string.format("%d: %d/%d", D, byZoom[D][2], byZoom[D][1])) end
	print(string.format("  tier %d camp: %d scenery parts; a local part between the camera and the raider or the camp at %d of %d camera spots (zoom %s)%s",
		tier, ref, blocked, total, table.concat(zl, ", "), if #names > 0 then "; " .. table.concat(names, ", ") else ""))
	print(string.format("    the guard hid scenery at %d spots, at most %d of %d parts at once", hidAny, hidMost, ref))
	eq(blocked, 0, string.format("tier %d V1: no local part stands between the camera and the raider or the camp at any of %d camera spots (%s)", tier, total, tostring(first)))
	truthy(hidMost <= math.floor(ref * 2 / 3), string.format("tier %d V2: the guard never hides more than two thirds of the scenery (at most %d of %d at once)", tier, hidMost, ref))
	byTier[tier] = hidAny
	totals.spots += total
	totals.blocked += blocked
	-- back to the follow camera: whatever was hidden comes back
	for _ = 1, 30 do follow(1 / 30) end
	eq(sceneryShown(), ref, "tier " .. tier .. " V3: back behind the gate, every hidden scenery part is shown again")
	remotes:FindFirstChild("LeaveCamp"):simulateFireServer(plr)
	h:advance(0.05)
	for _ = 1, 30 do follow(1 / 30) end
end
truthy((byTier[2] or 0) > 0 and (byTier[4] or 0) > 0, string.format("V2: the guard really hid scenery in the Rare and Mythic camps from far to the side (%d and %d spots)", byTier[2] or 0, byTier[4] or 0))
print(string.format("  all camps: %d of %d camera spots with a local part in the way", totals.blocked, totals.spots))

-- V4: an ANIMATED piece is judged where it IS, every frame. The Loch Shore camp again (its own hunt: the raid
-- clock allows 150 s), a camera held far behind the loch, low (y 8, so its lines of sight to the camp cross the
-- water where Nessie swims at z 250), for her whole 520-stud lap (130 s): on no frame may she (or anything)
-- stand between the camera and the camp, and she must really have crossed the view (the guard hid her).
do
	hrp.CFrame = CFrame.new(boardPos)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	for _ = 1, 120 do follow(1 / 30) end
	remotes:FindFirstChild("Hunt"):simulateFireServer(plr, 3)
	h:advance(0.05)
	local slot = Night.pocketSlot(Config, hrp.Position.X)
	truthy(slot ~= nil, "V4: back in a Loch Shore camp")
	if slot then
		local ox = Night.pocketOriginX(Config, slot)
		for _ = 1, 90 do follow(1 / 30) end
		local camPos = Vector3.new(ox + 36, 8, 460)
		local targets = {}
		for _, c in { { -1, 15 }, { W.PlotWidth + 1, 15 }, { W.PlotWidth + 1, 97 }, { -1, 97 }, { 36, 56 } } do
			table.insert(targets, Vector3.new(ox + c[1], 1, c[2]))
			table.insert(targets, Vector3.new(ox + c[1], W.FenceHeight, c[2]))
		end
		local blockedF, hiddenF, shownF, first = 0, 0, 0, nil
		for _ = 1, 30 * 132 do
			cam.CFrame = CFrame.lookAt(camPos, Vector3.new(ox + 36, 3, 56))
			RunService.RenderStepped:Fire(1 / 30)
			h:advance(1 / 30)
			if Night.pocketSlot(Config, hrp.Position.X) == nil then break end
			local nessie = 0
			for _, p in shownParts() do
				if string.sub(p.Name, 1, 6) == "Nessie" then nessie += 1 end
				for _, t in targets do
					if segHitsBox(camPos, t, p.CFrame, p.Size) then
						blockedF += 1
						first = first or p.Name
						break
					end
				end
			end
			if nessie == 0 then hiddenF += 1 else shownF += 1 end
		end
		print(string.format("  V4 loch, a fixed camera behind the water for Nessie's lap: %d frames with a part in the way; Nessie hidden on %d frames, shown on %d", blockedF, hiddenF, shownF))
		eq(blockedF, 0, "V4: no frame of Nessie's lap has a local part between the fixed camera and the camp (" .. tostring(first) .. ")")
		truthy(hiddenF > 0 and shownF > 0, "V4: she really swam through the view (hidden on some frames, shown on others)")
		remotes:FindFirstChild("LeaveCamp"):simulateFireServer(plr)
		h:advance(0.05)
		for _ = 1, 30 do follow(1 / 30) end
	end
end

--============================================================ home (H1-H3)

-- home scenery: the horizon pieces (the floor pieces lie under the Ground; the auroras ride with the camera)
local HOME_SCENERY = { "Ridge", "FarPine", "Ufo", "Bigfoot_" }
local function isHomeScenery(name)
	if name == "Owl" then return true end -- (not "OwlEye": the eyes blink, which is not the guard)
	for _, pre in HOME_SCENERY do
		if string.sub(name, 1, #pre) == pre then return true end
	end
	return false
end
local function homeShown()
	local out = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and isHomeScenery(d.Name) then table.insert(out, d) end
	end
	return out
end
do
	for _ = 1, 150 do follow(1 / 30) end -- home: the mythic night has faded in again
	eq(Night.pocketSlot(Config, hrp.Position.X), nil, "home: back from the last camp")
	local spots = {
		{ "the apron", 0, 24 }, { "behind the cage row", 0, 114 }, { "the back strip", 48, 125 },
		{ "the road's centre", 252, 0 }, { "the road's -x end", -90, 0 }, { "the front strip", 48, -125 },
	}
	local total, blocked, first, hidAny, hidMost, refMin, byName = 0, 0, nil, 0, 0, math.huge, {}
	-- the whole character, not just the root: root, head, and 1.5 studs to each side
	local body = { Vector3.zero, Vector3.new(0, 2.5, 0), Vector3.new(1.5, 0, 0), Vector3.new(-1.5, 0, 0), Vector3.new(0, 0, 1.5), Vector3.new(0, 0, -1.5) }
	local zooms = { 20, 40, 60, 90, 128, 200, 300, 400 }
	for _, sp in spots do
		local root = Vector3.new(sp[2], W.RootHeight, sp[3])
		hrp.CFrame = CFrame.new(root)
		-- reference: a camera straight over the player hides nothing; then the usual follow camera
		cam.CFrame = CFrame.new(root + Vector3.new(0, 60, 0.01), root)
		for _ = 1, 15 do RunService.RenderStepped:Fire(1 / 30); h:advance(1 / 30) end
		local ref = #homeShown()
		refMin = math.min(refMin, ref)
		for _ = 1, 15 do follow(1 / 30) end
		eq(#homeShown(), ref, "home H2 at " .. sp[1] .. ": the follow camera hides no scenery")
		for _, D in zooms do
			for yawDeg = 0, 345, 15 do
				for _, pitchDeg in { 10, 25, 50 } do
					local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
					local camPos = root + Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)) * D
					cam.CFrame = CFrame.lookAt(camPos, root)
					RunService.RenderStepped:Fire(1 / 30)
					h:advance(1 / 30)
					total += 1
					local parts = homeShown()
					for _, p in parts do
						local hitIt = false
						for _, t in body do
							if segHitsBox(camPos, root + t, p.CFrame, p.Size) then hitIt = true; break end
						end
						if hitIt then
							blocked += 1
							byName[p.Name] = (byName[p.Name] or 0) + 1
							first = first or string.format("%s between a camera at zoom %d, yaw %d, pitch %d and the player at %s", p.Name, D, yawDeg, pitchDeg, sp[1])
							break
						end
					end
					if #parts < ref then hidAny += 1 end
					hidMost = math.max(hidMost, ref - #parts)
				end
			end
		end
		for _ = 1, 30 do follow(1 / 30) end
		eq(#homeShown(), ref, "home H3 at " .. sp[1] .. ": back to the follow camera, every hidden part is shown again")
	end
	local names = {}
	for n, c in byName do table.insert(names, n .. " " .. c) end
	print(string.format("  home: %d scenery parts or more; a scenery part between the camera and the player at %d of %d camera spots%s; the guard hid scenery at %d spots, at most %d at once",
		refMin, blocked, total, if #names > 0 then " (" .. table.concat(names, ", ") .. ")" else "", hidAny, hidMost))
	eq(blocked, 0, string.format("home H1: no scenery part stands between the camera and the player (root, head, sides) at any of %d camera spots (%s)", total, tostring(first)))
	-- H4: the view is kept clear round the CHARACTER (Config.Night.HomeViewRadius), not along a line to its root.
	-- Built on purpose: a far pine beyond the back or front edge; the player 20 studs from it and a camera 200 beyond
	-- it on the other side, both on a line 1 stud outside the pine's footprint. That line misses the pine; the
	-- line to the player's side (1.5 studs toward it) crosses it. The pine must be hidden.
	local pine = nil
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Name == "FarPine" and d.Transparency < 0.95 and math.abs(d.Position.Z) > 170 then pine = d; break end
	end
	truthy(pine ~= nil, "home H4: a far pine beyond the back or front edge to build the case on")
	if pine then
		local cf, s = pine.CFrame, pine.Size
		local ex = math.abs(cf.RightVector.X) * s.X / 2 + math.abs(cf.UpVector.X) * s.Y / 2 + math.abs(cf.LookVector.X) * s.Z / 2
		local sgn = if pine.Position.Z > 0 then 1 else -1
		local x = pine.Position.X + ex + 1
		local root = Vector3.new(x, W.RootHeight, pine.Position.Z - sgn * 20)
		local camPos = Vector3.new(x, W.RootHeight, pine.Position.Z + sgn * 200)
		hrp.CFrame = CFrame.new(root)
		for _ = 1, 3 do
			cam.CFrame = CFrame.lookAt(camPos, root)
			RunService.RenderStepped:Fire(1 / 30)
			h:advance(1 / 30)
		end
		truthy(not segHitsBox(camPos, root, cf, s), "home H4 (set-up): the line to the root passes 1 stud beside the pine")
		truthy(segHitsBox(camPos, root + Vector3.new(-1.5, 0, 0), cf, s), "home H4 (set-up): the line to the player's side crosses it")
		truthy(pine.Parent == nil or pine.Transparency >= 0.95, "home H4: that pine is hidden: the kept-clear view is the character's, not a line to its root")
	end
	truthy(hidAny > 0, "home H3: the guard really hid scenery from far out (" .. hidAny .. " spots)")
	truthy(hidMost <= math.floor(refMin / 3), string.format("home H3: it never hides more than a third of the horizon at once (at most %d of %d)", hidMost, refMin))
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid view: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid view check failed", 0) end
