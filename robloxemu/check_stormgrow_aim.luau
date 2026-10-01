-- StormGrow — A TAP LANDS ON THE TILE YOU SEE (REVIEW-1, findings B1 and B3).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_aim.luau 2>&1
--
-- Before REVIEW-1 every check fired the tile it MEANT straight into the server, so nothing could see that from in
-- front of a field Roblox delivered two taps in three to ANOTHER tile (the invisible 6-stud hitboxes stood in
-- front of the tiles behind them), or that a tap beyond 32 studs did nothing and said nothing. This check aims
-- like a player on an 800 x 360 phone: it stands where a farmer stands to work a field, puts the camera behind
-- the character, picks a point on something it can SEE (a crop part, the soil around it), projects it to the
-- screen and taps that screen point. Then it asks which tile answered.
--
-- The grading is the test's own (stormgrow/tests/Aim.luau): its projection, and an oracle that walks the ray
-- through every part drawn as a surface (Transparency < 0.6, characters excluded). The tile owning the
-- first drawn part is the tile under the thumb, so it is the tile that must answer. Both ways a tile can be
-- reached are tried on every tap: the client's own tap handler (UserInputService.TouchTap) and Roblox's
-- ClickDetector delivery (first CanQuery part, a ClickDetector, within MaxActivationDistance), so the same file
-- measures the old design and the new one.
--
-- In-memory changes this run makes (this process only, never src/): Config.Weather.ClockOffsetSeconds, so the
-- server boots at :16:40 (clear for 200 s: no strike changes a crop's look while the check aims).

local Harness = require("./emu/harness")
local Aim = require("../stormgrow/tests/Aim")

local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-aim", viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
mod("Config").Weather.ClockOffsetSeconds = (1000 - os.time() % 3600) % 3600

-- Two saved farmers. The OWNER has all six fields planted with every crop (ripe, many marked: ice shells,
-- halos, sparks), tall Sunflowers in the near row of field 1, so tall crops stand in front of short ones.
-- The AIMER owns field 1 and 2 and taps the owner's farm (refused, so nothing it taps changes the scene) and
-- then its own.
local CROPS = { "radish", "carrot", "corn", "tomato", "sunflower", "pumpkin", "watermelon", "stormfruit" }
local store = h.services.DataStoreService:GetDataStore("StormGrow_v1")
local T0 = os.time()
do
	local tiles = {}
	for f = 1, 6 do
		for t = 1, 9 do
			local c = CROPS[(f * 3 + t) % 8 + 1]
			if f == 1 and t <= 3 then c = "sunflower" end
			tiles[f .. "_" .. t] = { c = c, at = T0 - 20000, m = (f + t) % 8 }
		end
	end
	store:SetAsync("u_7001", { v = 1, coins = 0, harvested = 400000, fields = 6, unlocked = 8, selected = "radish",
		tiles = tiles, almanac = {}, almanacCount = 0, almanacAt = 0, harvests = 100 })
	store:SetAsync("u_7002", { v = 1, coins = 1000, harvested = 900, fields = 2, unlocked = 2, selected = "carrot",
		tiles = {}, almanac = {}, almanacCount = 0, almanacAt = 0, harvests = 40 })
end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local Config, Farm = mod("Config"), mod("Farm")
local F = Config.Farm
local owner = h:join("Owner", 7001)
h:advance(0.3)
local aimer = h:join("Aimer", 7002) -- the LocalPlayer from here on
local char = h.Players:simulateSpawn(aimer, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	assert(h:tryRun(key))
end
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
for _ = 1, 10 do
	RunService.RenderStepped:Fire(0.1)
	h:advance(0.1)
end
local S, A = owner:GetAttribute("Slot"), aimer:GetAttribute("Slot")
eq(owner:GetAttribute("Loaded") and aimer:GetAttribute("Loaded"), true, "set-up: both farms loaded")
eq(owner:GetAttribute("Fields"), 6, "set-up: the owner has six fields")

local aim = Aim.new(h, { touch = true })
local remotes = RS.StormRemotes
local responses = {}
local tapRemote = remotes:FindFirstChild("Tap")
if tapRemote then
	tapRemote.OnServerEvent:Connect(function(plr, slot, key)
		table.insert(responses, { via = "tap", plr = plr, slot = slot, key = key })
	end)
end
local function toastCount(plr)
	local n = 0
	for _ in remotes.Toast:sentTo(plr) do n += 1 end
	return n
end
local function lastToast(plr)
	local last = ""
	for _, rec in remotes.Toast:sentTo(plr) do last = tostring(rec.args[1]) end
	return last
end

local function standFor(k, f) return aim:standFor(Farm, F, k, f) end
local function targetsFor(k, key) return aim:targetsFor(k, key) end
local within = Aim.within

--============================================================ 1. on the owner's farm: every tap answers the tile you see

local counted, own, wrong, silent, doubled, offscreen, notTile = 0, 0, 0, 0, 0, 0, 0
local wrongEx = {}
local byField = {}
for f = 1, 6 do
	byField[f] = { counted = 0, own = 0 }
	local pos, facing = standFor(S, f)
	hrp.CFrame = CFrame.new(pos)
	local visibleAll = within(aim:parts("visible"), pos, 120)
	local queryAll = within(aim:parts("query"), pos, 120)
	for _, pose in { { 25, 12.5 }, { 35, 12.5 }, { 50, 12.5 }, { 25, 20 }, { 35, 20 }, { 50, 20 } } do
		aim:pose(pos, facing, pose[1], pose[2])
		local camPos = cam.CFrame.Position
		for t = 1, 9 do
			local key = f .. "_" .. t
			for _, pt in targetsFor(S, key) do
				local vx, vy, ok = aim:screenOf(pt)
				if not ok then
					offscreen += 1
					continue
				end
				local seen = aim:firstVisible(camPos, pt, visibleAll)
				local ss, sk = aim:tileOf(seen)
				if ss == nil then
					notTile += 1 -- a fence, the ground, a sign: no tile is under the thumb there
					continue
				end
				table.clear(responses)
				local toasts0 = toastCount(aimer)
				aim:tap(vx :: number, vy :: number)
				local engineHit = aim:engineClick(aimer, camPos, pt, queryAll)
				h:advance(0.02)
				local answers = {}
				for _, r in responses do table.insert(answers, { slot = r.slot, key = r.key }) end
				if engineHit then
					local es, ek = aim:tileOf(engineHit)
					table.insert(answers, { slot = es, key = ek })
				end
				counted += 1
				byField[f].counted += 1
				if #answers == 0 then
					silent += 1
					if toastCount(aimer) == toasts0 and #wrongEx < 12 then
						table.insert(wrongEx, string.format("field %d pitch %d zoom %.1f: aimed at %s, nothing answered", f, pose[1], pose[2], sk))
					end
				elseif #answers > 1 then
					doubled += 1
				elseif answers[1].slot == ss and answers[1].key == sk then
					own += 1
					byField[f].own += 1
				else
					wrong += 1
					if #wrongEx < 12 then
						table.insert(wrongEx, string.format("field %d pitch %d zoom %.1f: saw %s, %s answered", f, pose[1], pose[2], sk, tostring(answers[1].key)))
					end
				end
			end
		end
	end
end
local perField = {}
for f = 1, 6 do table.insert(perField, string.format("field %d %d/%d", f, byField[f].own, byField[f].counted)) end
print(string.format("aimed taps on a full farm: %d counted, %d answered by the tile under the thumb, %d by another tile, %d by none, %d twice; skipped %d off-screen or under a touch control, %d on no tile",
	counted, own, wrong, silent, doubled, offscreen, notTile))
print("  " .. table.concat(perField, " · "))
for _, e in wrongEx do print("  e.g. " .. e) end
truthy(counted >= 600, string.format("the sample is large: %d aimed taps on visible tiles over 6 fields x 6 camera poses", counted))
eq(own, counted, "every tap is answered by the tile the player sees under their thumb")
eq(doubled, 0, "and only once (never both a ClickDetector and the tap handler)")
for f = 1, 6 do
	truthy(byField[f].counted >= 40, string.format("field %d was aimed at from its working spot (%d taps)", f, byField[f].counted))
end

--============================================================ 2. the aimer's own farm: no tap is silent (B3)

-- Field 2 of the aimer's farm from the PAD (where a farmer spawns), the camera turned towards field 2: its
-- tiles are 25-45 studs away. Each tap must plant, or say why not.
do
	local pad = h.workspace.Farms["Farm_" .. A]:FindFirstChild("FarmPad_" .. A)
	local pos = pad.Position + Vector3.new(0, 2.5, 0)
	hrp.CFrame = CFrame.new(pos)
	local cx, cz = Farm.fieldCentre(A, 2, F)
	local facing = Vector3.new(cx - pos.X, 0, cz - pos.Z).Unit
	aim:pose(pos, facing, 30, 12.5)
	local camPos = cam.CFrame.Position
	local visible = within(aim:parts("visible"), pos, 120)
	local query = within(aim:parts("query"), pos, 120)
	local tiles = h.workspace.Farms["Farm_" .. A].Tiles
	local n, planted, walkCloser, quiet, other = 0, 0, 0, 0, 0
	local farthest = 0
	for t = 1, 9 do
		local key = "2_" .. t
		local soil = tiles["Soil_" .. key]
		local pt = soil.Position + Vector3.new(0, soil.Size.Y / 2, 0)
		local vx, vy, ok = aim:screenOf(pt)
		local ss, sk = aim:tileOf(aim:firstVisible(camPos, pt, visible))
		if ok and ss == A and sk == key then
			n += 1
			farthest = math.max(farthest, (pt - pos).Magnitude)
			local before = toastCount(aimer)
			aim:tap(vx :: number, vy :: number)
			aim:engineClick(aimer, camPos, pt, query)
			h:advance(0.25)
			local said = toastCount(aimer) > before
			if tiles["Tile_" .. key]:GetAttribute("Crop") ~= "" then
				planted += 1
			elseif said and string.find(lastToast(aimer), "Walk closer", 1, true) then
				walkCloser += 1
			elseif said then
				other += 1
			else
				quiet += 1
			end
		end
	end
	print(string.format("field 2 from the pad: %d visible tiles tapped (up to %.0f studs away): %d planted, %d told to walk closer, %d told something else, %d silent",
		n, farthest, planted, walkCloser, other, quiet))
	truthy(n >= 6, "set-up: most of field 2 is visible and tappable from the pad (" .. n .. ")")
	truthy(farthest > 40, string.format("set-up: some of them are beyond the server's 40-stud reach (%.0f)", farthest))
	eq(quiet, 0, "no tap on your own field is silent: each one plants or says why not")
	truthy(walkCloser >= 1, "a tile beyond reach says 'Walk closer'")
	truthy(planted >= 1, "a tile within reach plants")
end

--============================================================ 3. a tap the HUD or a touch control took is not a farm tap

do
	local pos = h.workspace.Farms["Farm_" .. A]:FindFirstChild("FarmPad_" .. A).Position + Vector3.new(0, 2.5, 0)
	hrp.CFrame = CFrame.new(pos)
	local _, facing = standFor(A, 1)
	aim:pose(pos, facing, 35, 12.5)
	local soil = h.workspace.Farms["Farm_" .. A].Tiles["Soil_1_5"]
	local vx, vy, ok = aim:screenOf(soil.Position + Vector3.new(0, soil.Size.Y / 2, 0))
	truthy(ok, "set-up: field 1's middle tile is on screen from the pad")
	table.clear(responses)
	aim:tap(vx :: number, vy :: number, true) -- gameProcessed: a button or the thumbstick had it
	h:advance(0.25)
	eq(#responses, 0, "a processed tap sends nothing")
	eq(h.workspace.Farms["Farm_" .. A].Tiles.Tile_1_5:GetAttribute("Crop"), "", "and plants nothing")
	aim:tap(vx :: number, vy :: number, false)
	aim:engineClick(aimer, cam.CFrame.Position, soil.Position + Vector3.new(0, soil.Size.Y / 2, 0))
	h:advance(0.25)
	eq(h.workspace.Farms["Farm_" .. A].Tiles.Tile_1_5:GetAttribute("Crop"), "carrot", "the same tap, not processed, plants that tile")
end

--============================================================ 4. the spawn view: nothing stands between the camera and field 1

-- (REVIEW-1, found measuring the hazard ring) The owner's sign stood 3 studs tall and 12 wide at the porch's front
-- edge, 4.5 studs behind the spawn pad: from a camera behind a farmer on the pad at a 15-20 degree pitch it hid all
-- 27 soil points of field 1, and the ground around the farmer's feet (where the hazard ring is drawn) at most
-- pitches. Roblox's camera can start shallow, so the first view of the game must show field 1 at every usual pitch.
do
	local farm = h.workspace.Farms["Farm_" .. A]
	local pad = farm:FindFirstChild("FarmPad_" .. A)
	local root, facing = standFor(A, 1)
	hrp.CFrame = CFrame.new(root)
	local visible = within(aim:parts("visible"), root, 120)
	local hiddenSoil, nSoil, hiddenFeet, nFeet, worst = 0, 0, 0, 0, {}
	for _, pitch in { 10, 15, 20, 25, 30, 35, 45 } do
		for _, zoom in { 12.5, 20 } do
			aim:pose(root, facing, pitch, zoom)
			local camPos = cam.CFrame.Position
			for t = 1, 9 do
				local soil = farm.Tiles["Soil_1_" .. t]
				for _, off in { Vector3.new(0, 0.3, 0), Vector3.new(2.5, 0.3, 2.5), Vector3.new(-2.5, 0.3, -2.5) } do
					local pt = soil.Position + off
					local _, _, ok = aim:screenOf(pt)
					if ok then
						nSoil += 1
						local hit = aim:firstVisible(camPos, pt, visible)
						if hit ~= soil and not (aim:tileOf(hit) == A) then
							hiddenSoil += 1
							local k = hit and hit.Name or "nothing"
							worst[k] = (worst[k] or 0) + 1
						end
					end
				end
			end
			for i = 0, 7 do
				local a = i * math.pi / 4
				local pt = pad.Position + Vector3.new(math.cos(a) * 2.6, pad.Size.Y / 2, math.sin(a) * 2.6)
				nFeet += 1
				local hit = aim:firstVisible(camPos, pt, visible)
				if hit ~= pad then
					hiddenFeet += 1
					local k = hit and hit.Name or "nothing"
					worst[k] = (worst[k] or 0) + 1
				end
			end
		end
	end
	local w = {}
	for k, v in worst do table.insert(w, k .. " " .. v) end
	print(string.format("spawn view, 7 pitches x 2 zooms: %d of %d field-1 soil points and %d of %d pad points around the feet hidden (%s)",
		hiddenSoil, nSoil, hiddenFeet, nFeet, table.concat(w, ", ")))
	eq(hiddenSoil, 0, "from the spawn camera at every usual pitch, nothing hides field 1 (only its own crops may)")
	eq(hiddenFeet, 0, "nor the pad around the farmer's feet, where a hazard's ring is drawn")
end

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	if string.find(w, "frame error", 1, true) then failed += 1 end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow aim: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow aim check failed", 0) end
