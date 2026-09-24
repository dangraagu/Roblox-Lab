-- Steal a Cryptid - the WORLD'S EDGE at night, through the REAL server and the REAL client scripts.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_edge.luau 2>&1
--
-- Review 2026-09-24 (EYECANDY.md section 13), two findings about the edge of the server's Ground, the only
-- floor at home (696 x 260 studs at 12 players, top at y -0.2; past it is the void):
--   1. The night laid a 2 048-stud local FarGround under everything, 1.1 studs below the Ground's top,
--      opaque grass, non-collidable. The edge vanished: a player who walked behind a lair or past the end
--      of the road stepped onto it and fell through the world. The far floor must never continue the
--      Ground at walking height. Now: a ravine (Config.Night.Ravine.Width) with cliff faces, then the
--      far floor. Checked at two bands (the piece is in all four) by sampling every side of the Ground:
--        E1 nothing local stands in the ravine at walking height (y in groundTop-20 .. groundTop+3);
--        E2 a cliff face (one local part from just under the Ground's top to 40+ studs down) hangs under
--           every edge, and the far rim has its own face, hanging from just under the far floor;
--        E3 the far floor is still there beyond the ravine, at its old height (the look is kept).
--   2. The edge margin (EdgeMarginStuds) only stops LAUNCHES. A player who walks toward the edge while a
--      hazard flies and stops in its ring was hit 17.8-19.4 studs from the edge, pushed on toward it: 19-20
--      of 24 frictionless slides ended past the edge (the reviewer's probe, reproduced before this fix).
--        K1 walk toward each of the four edges (6 trials each, rapid hazards) at rank 2 (bat, crow) and
--           rank 4 (meteorite, wisp: the hardest knock): every hit's frictionless slide (push x
--           KnockSeconds, the bound EYECANDY uses) ends at least PlayerRadius inside the Ground;
--        K2 control: a hit far from every edge keeps the template's full knock (nothing cut needlessly).
-- Headless limits: no physics (the slide is the frictionless upper bound), nothing renders.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-edge", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local W = Config.World
local N = Config.Night
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 5505
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "dogman", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 10000000, savedAt = NOW, cagesUnlocked = 9, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
-- rapid hazards (the bundle's own Config, before the client starts its scheduler), as the reviewer's probe
local GameConfig = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local GameHz = GameConfig.Night.Hazards
GameConfig.Poacher.FirstAfterSeconds = 1e6 -- no poacher walks in (it closes the hazard gate); rank 4 owns 3 cryptids
GameHz.IntervalMin, GameHz.IntervalMax = 0.05, 0.05
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Edgewalker", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local bus = plr.PlayerGui.CryptidHud.NightBus
local folder = h.workspace:FindFirstChild("CryptidNight")
local cam = h.workspace.CurrentCamera
local ground = h.workspace.Road.Ground
local GX, GZ, HX, HZ = ground.Position.X, ground.Position.Z, ground.Size.X / 2, ground.Size.Z / 2
local TOP = ground.Position.Y + ground.Size.Y / 2
local X0, X1, Z0, Z1 = GX - HX, GX + HX, GZ - HZ, GZ + HZ
local R = N.Ravine or { Width = 24, Depth = 80 }
print(string.format("  the Ground: x %.0f..%.0f, z %.0f..%.0f, top y %.2f; ravine %d studs wide", X0, X1, Z0, Z1, TOP, R.Width))

local function st()
	local sent = remotes.State:sentTo(plr)
	return sent[#sent].args[1]
end

local wasStand, hitAt = false, nil
local function frame(dt)
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p) -- a follow camera facing +z, ~22 degrees down
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if hum.PlatformStand == true and not wasStand then hitAt = { pos = hrp.Position, v = hrp.AssemblyLinearVelocity } end
	wasStand = hum.PlatformStand == true
end
local function run(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do frame(1 / 30) end
end
local function inFlight()
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and string.find(d.Name, "^Hazard_%a+_") then return true end
	end
	return false
end

--============================================================ helpers: what local part stands over a point

local function extents(d)
	local cf, s = d.CFrame, d.Size
	local ex = math.abs(cf.RightVector.X) * s.X / 2 + math.abs(cf.UpVector.X) * s.Y / 2 + math.abs(cf.LookVector.X) * s.Z / 2
	local ey = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
	local ez = math.abs(cf.RightVector.Z) * s.X / 2 + math.abs(cf.UpVector.Z) * s.Y / 2 + math.abs(cf.LookVector.Z) * s.Z / 2
	return ex, ey, ez
end
-- every parented, visible local BasePart whose world-aligned footprint covers (x, z): { part, bottom, top }
local function over(x, z)
	local out = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and string.sub(d.Name, 1, 6) ~= "Hazard" then
			local ex, ey, ez = extents(d)
			if math.abs(x - d.Position.X) <= ex and math.abs(z - d.Position.Z) <= ez then
				table.insert(out, { part = d, bottom = d.Position.Y - ey, top = d.Position.Y + ey })
			end
		end
	end
	return out
end
-- points round the Ground, `d` studs past its edge (negative = inside), every `step` studs along each side
local function ring(d, step)
	local pts = {}
	-- (inside the Ground, d < 0, keep the along-the-side coordinate |d| inside too: a point ON the Ground's
	-- edge line is not "0.5 studs inside" it)
	local inset = math.max(0, -d)
	local x = X0 + inset
	while x <= X1 - inset + 1e-6 do
		table.insert(pts, { x, Z0 - d, "front" })
		table.insert(pts, { x, Z1 + d, "back" })
		x += step
	end
	local z = Z0 + inset
	while z <= Z1 - inset + 1e-6 do
		table.insert(pts, { X0 - d, z, "-x end" })
		table.insert(pts, { X1 + d, z, "+x end" })
		z += step
	end
	if d > 0 then
		for _, c in { { X0 - d, Z0 - d }, { X1 + d, Z0 - d }, { X0 - d, Z1 + d }, { X1 + d, Z1 + d } } do
			table.insert(pts, { c[1], c[2], "corner" })
		end
	end
	return pts
end

--============================================================ 1. the ravine (E1-E3)

local function ravine(label)
	-- E1: nothing local at walking height anywhere in the ravine
	local sampled, falseFloor, firstFalse = 0, 0, nil
	for _, d in { 0.25, 1, 3, 6, 10, 15, 20, R.Width - 0.5 } do
		for _, p in ring(d, 6) do
			sampled += 1
			for _, o in over(p[1], p[2]) do
				if o.top >= TOP - 20 and o.bottom <= TOP + 3 then
					falseFloor += 1
					firstFalse = firstFalse or string.format("%s at (%.1f, %.1f), %.2f studs past the %s edge, top y %.2f", o.part.Name, p[1], p[2], d, p[3], o.top)
					break
				end
			end
		end
	end
	eq(falseFloor, 0, label .. " E1: of " .. sampled .. " points 0.25.." .. (R.Width - 0.5) .. " studs past the Ground's edge, none has a local part at walking height (" .. tostring(firstFalse) .. ")")
	-- the reviewer's two points: behind the lairs (48, 135) and past the -x end of the road
	for _, p in { { 48, Z1 + 5, "5 studs behind the back edge, between Plot_0 and Plot_2" }, { X0 - 10, 0, "10 studs past the -x end of the road" } } do
		local near = 0
		for _, o in over(p[1], p[2]) do
			if o.top >= TOP - 20 and o.bottom <= TOP + 3 then near += 1 end
		end
		eq(near, 0, label .. " E1: nothing to stand on " .. p[3])
	end
	-- E2: a cliff face under every edge (the bluff), and one on the far rim
	local noFace, firstNoFace, noRim, firstNoRim = 0, nil, 0, nil
	for _, p in ring(-0.5, 12) do
		local ok = false
		for _, o in over(p[1], p[2]) do
			-- ONE face hanging from just under the Ground's top (its slab is 1 stud thick) at least 40 studs down
			if o.top <= TOP + 1e-6 and o.top >= TOP - 1.5 and o.bottom <= TOP - 40 then ok = true end
		end
		if not ok then noFace += 1; firstNoFace = firstNoFace or string.format("(%.1f, %.1f) %s", p[1], p[2], p[3]) end
	end
	for _, p in ring(R.Width + 0.5, 12) do
		local ok = false
		for _, o in over(p[1], p[2]) do
			-- a cliff face hanging from just under the far floor's rim (y -1.3), not a wall standing above it
			if o.bottom <= TOP - 40 and o.top <= -1.3 + 0.01 and o.top >= -1.3 - 1.5 then ok = true end
		end
		if not ok then noRim += 1; firstNoRim = firstNoRim or string.format("(%.1f, %.1f) %s", p[1], p[2], p[3]) end
	end
	eq(noFace, 0, label .. " E2: a cliff face hangs from just under every edge of the Ground at least 40 studs down, never above its top (" .. tostring(firstNoFace) .. ")")
	eq(noRim, 0, label .. " E2: the far rim of the ravine has its own cliff face (" .. tostring(firstNoRim) .. ")")
	-- E3: the far floor beyond the ravine, at its old height (y -1.3)
	local noFloor, firstNoFloor, n = 0, nil, 0
	for _, d in { R.Width + 3, R.Width + 60, 400 } do
		for _, p in ring(d, 48) do
			n += 1
			local ok = false
			for _, o in over(p[1], p[2]) do
				if o.part.Name == "FarGround" and math.abs(o.top - (-1.3)) < 0.05 then ok = true end
			end
			if not ok then noFloor += 1; firstNoFloor = firstNoFloor or string.format("(%.1f, %.1f) %.0f past the %s edge", p[1], p[2], d, p[3]) end
		end
	end
	eq(noFloor, 0, label .. " E3: the forest floor is there beyond the ravine at y -1.3 (" .. n .. " points; " .. tostring(firstNoFloor) .. ")")
	-- the far pines stand wholly beyond the ravine
	local pineIn = 0
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 7) == "FarPine" then
			local ex, _, ez = extents(d)
			local gx = math.max(math.abs(d.Position.X - GX) - ex - HX, 0)
			local gz = math.max(math.abs(d.Position.Z - GZ) - ez - HZ, 0)
			if math.sqrt(gx * gx + gz * gz) < R.Width then pineIn += 1 end
		end
	end
	eq(pineIn, 0, label .. " E3: no far pine overhangs the ravine")
end

hrp.CFrame = CFrame.new(GX, W.RootHeight, 0)
run(8)
eq(st().rank, 2, "the server reports rank 2 (a Dogman in the Journal): moonrise")
ravine("rank 2 moonrise")

--============================================================ 2. knocks near the edge (K1)

local KEEP = N.Hazards.PlayerRadius
local T = N.Hazards.KnockSeconds
local function edgeDist(x, z)
	return math.min(HX - math.abs(x - GX), HZ - math.abs(z - GZ))
end
local DIRS = {
	{ name = "-x end", start = function() return Vector3.new(X0 + 45, W.RootHeight, 0) end, dir = Vector3.new(-1, 0, 0) },
	{ name = "+x end", start = function() return Vector3.new(X1 - 45, W.RootHeight, 0) end, dir = Vector3.new(1, 0, 0) },
	{ name = "back (+z)", start = function() return Vector3.new(48, W.RootHeight, Z1 - 45) end, dir = Vector3.new(0, 0, 1) },
	{ name = "front (-z)", start = function() return Vector3.new(48, W.RootHeight, Z0 + 45) end, dir = Vector3.new(0, 0, -1) },
}
local function knockTrials(label, perDir)
	local trials, hits, past, worst, rows = 0, 0, 0, math.huge, {}
	for _, D in DIRS do
		for _ = 1, perDir do
			hrp.CFrame = CFrame.new(D.start())
			hum.MoveDirection = Vector3.new(0, 0, 0)
			hitAt = nil
			local n = 0
			while not inFlight() and n < 30 * 30 do frame(1 / 30); n += 1 end
			if inFlight() then
				trials += 1
				-- walk toward the edge until the chip says Move! (the lane locks on you), then stop in the ring
				local k = 0
				while string.sub(bus.Status.Value, 1, 5) ~= "Move!" and k < 150 do
					hrp.CFrame = CFrame.new(hrp.Position + D.dir * (16 / 30))
					hum.MoveDirection = D.dir
					frame(1 / 30)
					k += 1
				end
				hum.MoveDirection = Vector3.new(0, 0, 0)
				local stopAt = edgeDist(hrp.Position.X, hrp.Position.Z)
				local m = 0
				while inFlight() and m < 30 * 10 do frame(1 / 30); m += 1 end
				if hitAt then
					hits += 1
					local v = hitAt.v
					local ex, ez = hitAt.pos.X + v.X * T, hitAt.pos.Z + v.Z * T
					local endEdge = edgeDist(ex, ez)
					worst = math.min(worst, endEdge)
					if endEdge < KEEP - 1e-6 then past += 1 end
					if #rows < 3 or endEdge < KEEP - 1e-6 then
						table.insert(rows, string.format("    %s: stopped %.1f from the edge, push (%.1f, %.1f, %.1f), frictionless slide ends %.1f %s", D.name, stopAt, v.X, v.Y, v.Z,
							math.abs(endEdge), if endEdge >= 0 then "inside" else "PAST the edge"))
					end
				end
				for _ = 1, 45 do frame(1 / 30) end -- the stumble wears off
			end
		end
	end
	print(string.format("  %s: %d hazards launched at walkers heading for the edge, %d hit them; closest slide end %.2f studs inside the Ground", label, trials, hits, worst))
	for _, r in rows do print(r) end
	truthy(trials >= 4 * perDir - 2, label .. " K1: hazards launched in the walk-to-the-edge set-up (" .. trials .. ")")
	truthy(hits >= math.floor(0.8 * trials), label .. " K1: the walkers who stopped in the ring were hit, as the reviewer's were (" .. hits .. " of " .. trials .. ")")
	eq(past, 0, label .. " K1: no knock's frictionless slide ends within PlayerRadius of the edge or past it (" .. hits .. " hits)")
end

knockTrials("rank 2 (bat, crow)", 6)

--============================================================ rank 4: the hardest knock (meteorite) and every home piece

local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
local lair = plot:FindFirstChild("Lair")
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
for target = 3, 4 do
	local a = W.Apron.P3
	hrp.CFrame = CFrame.new(frameCF:PointToWorldSpace(Vector3.new(a.x, W.RootHeight, a.z - 4)))
	local ped = lair.Pedestals:FindFirstChild("Pedestal_3")
	ped:FindFirstChild("Buy").Triggered:Fire(plr)
	h:advance(0.05)
	run(3)
	eq(st().rank, target, "a purchase at P3 raised the Journal's rank to " .. target)
end
hrp.CFrame = CFrame.new(GX, W.RootHeight, 0)
run(8)
ravine("rank 4 mythic night")
knockTrials("rank 4 (meteorite, wisp)", 6)

--============================================================ K2: control, far from every edge

do
	local full, cut, n = 0, 0, 0
	for _ = 1, 4 do
		hrp.CFrame = CFrame.new(GX, W.RootHeight, 0)
		hum.MoveDirection = Vector3.new(0, 0, 0)
		hitAt = nil
		local k = 0
		while not inFlight() and k < 30 * 30 do frame(1 / 30); k += 1 end
		local kind = nil
		for _, d in folder:GetChildren() do
			local m = d:IsA("BasePart") and string.match(d.Name, "^Hazard_(%a+)_")
			if m then kind = m end
		end
		local m = 0
		while inFlight() and m < 30 * 10 do frame(1 / 30); m += 1 end
		if hitAt and kind and N.Hazards.Kinds[kind] then
			n += 1
			local hv = Vector3.new(hitAt.v.X, 0, hitAt.v.Z).Magnitude
			if math.abs(hv - N.Hazards.Kinds[kind].knock) < 0.01 then full += 1 else cut += 1 end
		end
		for _ = 1, 45 do frame(1 / 30) end
	end
	truthy(n >= 3, "K2: a player standing in the middle of the road was hit (" .. n .. " of 4)")
	eq(cut, 0, "K2: far from every edge the knock is the template's full push (" .. full .. " full)")
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid edge: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid edge check failed", 0) end
