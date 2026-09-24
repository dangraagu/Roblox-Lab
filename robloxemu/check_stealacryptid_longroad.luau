-- Steal a Cryptid - the night's horizon stays OFF THE ROAD however long the road is.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_longroad.luau 2>&1
--
-- The server builds max(World.Plots 8, Players.MaxPlayers) plots, and the road's Ground grows with them:
-- 504 studs long at 8 players, 696 at 12 (the emulator's default), 2 520 at 50 (a reviewer probe once ran
-- the place at 50). The night's far scenery (ridges up to 620 studs wide, three UFOs with drifting tractor
-- beams, a 98-stud Bigfoot walking the horizon) is placed around the road's centre. The first build used
-- a fixed ring (ridges 820-1 000 studs out, Bigfoot at 700): fine at 8 or 12 players, but at 50 it stood
-- hills and Bigfoot on the lairs themselves. This file runs a Mythic-rank player (every home piece shown)
-- at MaxPlayers 50 and checks, on every frame for 30 s (Bigfoot and the UFOs move), that no part of the
-- horizon comes within 20 studs of the Ground. (One game per CLI process: the harness allows one. The
-- other road lengths run in check_stealacryptid_night.luau (12) and in Studio (8), and the placement rule,
-- NightArt's offRoad, is the same code for any length.)

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local HORIZON = { "Ridge", "FarPine", "Ufo", "Bigfoot_" }
local function isHorizon(name)
	for _, pre in HORIZON do
		if string.sub(name, 1, #pre) == pre then return true end
	end
	return false
end

local function runAt(maxPlayers)
	local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-longroad-" .. maxPlayers, viewport = { 1280, 720 }, touch = false })
	h.Players.MaxPlayers = maxPlayers
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	local ME = 2202
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "bigfoot", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 100, savedAt = os.time(), cagesUnlocked = 3, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman", "nessie", "bigfoot" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
	assert(h:tryRun("server/Main.server"))
	h:advance(1)
	local GameHz = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Night.Hazards
	GameHz.IntervalMin, GameHz.IntervalMax = 100000, 100001
	local RunService = h.game:GetService("RunService")
	RunService:setIsServer(false)
	local plr = h:join("Far", ME)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Grass
	hum.MoveDirection = Vector3.new(0, 0, 0)
	h:advance(0.5)
	assert(h:tryRun("client/Hud.client"))
	assert(h:tryRun("client/Night.client"))
	local folder = h.workspace:FindFirstChild("CryptidNight")
	local ground = h.workspace.Road.Ground
	local gx, gz, hx, hz = ground.Position.X, ground.Position.Z, ground.Size.X / 2, ground.Size.Z / 2
	local cam = h.workspace.CurrentCamera
	local worst, worstName, frames, seen = math.huge, "?", 0, {}
	for _ = 1, 30 * 30 do
		local p = hrp.Position
		cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		frames += 1
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") and isHorizon(d.Name) then
				local key = string.match(d.Name, "^%a+") or d.Name
				seen[key] = true
				local cf, s = d.CFrame, d.Size
				local ex = math.abs(cf.RightVector.X) * s.X / 2 + math.abs(cf.UpVector.X) * s.Y / 2 + math.abs(cf.LookVector.X) * s.Z / 2
				local ez = math.abs(cf.RightVector.Z) * s.X / 2 + math.abs(cf.UpVector.Z) * s.Y / 2 + math.abs(cf.LookVector.Z) * s.Z / 2
				-- the gap between the part's footprint and the Ground's rect (0 if they overlap)
				local dx = math.max(math.abs(d.Position.X - gx) - ex - hx, 0)
				local dz = math.max(math.abs(d.Position.Z - gz) - ez - hz, 0)
				local gap = math.sqrt(dx * dx + dz * dz)
				if gap < worst then worst, worstName = gap, d.Name end
			end
		end
	end
	local kinds = {}
	for k in seen do table.insert(kinds, k) end
	table.sort(kinds)
	print(string.format("  MaxPlayers %d: road %d x %d studs; horizon parts seen: %s; nearest to the road: %s, %.1f studs off it",
		maxPlayers, ground.Size.X, ground.Size.Z, table.concat(kinds, ", "), worstName, worst))
	truthy(seen.Ridge and seen.Ufo and seen.Bigfoot and seen.FarPine, "MaxPlayers " .. maxPlayers .. ": every horizon piece is shown at mythic night")
	truthy(worst >= 20, string.format("MaxPlayers %d: no horizon part within 20 studs of the road's Ground in %d frames (nearest %s, %.1f)", maxPlayers, frames, worstName, worst))
	-- the ravine round the long road (review 2026-09-24 finding 1; check_stealacryptid_edge.luau does the 12-player
	-- road in full): nothing local at walking height just past any edge, and the far floor beyond the ravine
	do
		local R = Config.Night.Ravine
		local top = ground.Position.Y + ground.Size.Y / 2
		local function over(x, z, test)
			for _, d in folder:GetChildren() do
				if d:IsA("BasePart") and d.Transparency < 0.95 and string.sub(d.Name, 1, 6) ~= "Hazard" then
					local cf, s = d.CFrame, d.Size
					local ex = math.abs(cf.RightVector.X) * s.X / 2 + math.abs(cf.UpVector.X) * s.Y / 2 + math.abs(cf.LookVector.X) * s.Z / 2
					local ey = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
					local ez = math.abs(cf.RightVector.Z) * s.X / 2 + math.abs(cf.UpVector.Z) * s.Y / 2 + math.abs(cf.LookVector.Z) * s.Z / 2
					if math.abs(x - d.Position.X) <= ex and math.abs(z - d.Position.Z) <= ez and test(d, d.Position.Y - ey, d.Position.Y + ey) then return true end
				end
			end
			return false
		end
		local walkable = function(_, bottom, t) return t >= top - 20 and bottom <= top + 3 end
		local farFloor = function(d, _, t) return d.Name == "FarGround" and math.abs(t - (-1.3)) < 0.05 end
		local bad, noFloor, n = 0, 0, 0
		for _, dd in { 1, 12, R.Width - 1 } do
			for t = 0, 1, 1 / 40 do
				for _, p in { { gx - hx + 2 * hx * t, gz - hz - dd }, { gx - hx + 2 * hx * t, gz + hz + dd }, { gx - hx - dd, gz - hz + 2 * hz * t }, { gx + hx + dd, gz - hz + 2 * hz * t } } do
					n += 1
					if over(p[1], p[2], walkable) then bad += 1 end
				end
			end
		end
		for _, p in { { gx - hx - R.Width - 3, gz }, { gx + hx + R.Width + 3, gz }, { gx, gz - hz - R.Width - 3 }, { gx, gz + hz + R.Width + 3 } } do
			if not over(p[1], p[2], farFloor) then noFloor += 1 end
		end
		truthy(bad == 0, string.format("MaxPlayers %d: nothing local at walking height in the ravine round the road (%d of %d points have something)", maxPlayers, bad, n))
		truthy(noFloor == 0, string.format("MaxPlayers %d: the far floor starts beyond the ravine on all four sides (%d missing)", maxPlayers, noFloor))
	end
	for _, e in h:errors() do truthy(false, "MaxPlayers " .. maxPlayers .. ": scheduler error: " .. tostring(e)) end
	for _, w in h.warnings do
		if string.find(w, "Night", 1, true) then truthy(false, "MaxPlayers " .. maxPlayers .. ": the client warned: " .. w) end
	end
end

runAt(50)

print(string.format("\nsteal a cryptid longroad: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid longroad check failed", 0) end
