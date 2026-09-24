-- +1 Jump Every Step — the red ring IS the danger: stepping out of it in any direction dodges.
-- Run: luau check_plus1jump_dodge.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17, round 2 (finding 1, high): when a hazard's lane locks the client draws a red ring at
-- the player's feet and says "MOVE!". The hit test was the hazard's whole flight, a corridor as wide as the
-- ring running along the lane through the player and far past them. Measured through this client: backing
-- away (S key) was hit 98-100 % of the time, walking out of the ring away from its centre 65-72 %, A/D on
-- the better side 23-25 %; only a step at right angles to the lane dodged. A player who reacted did worse
-- than one who ignored the warning (28 %).
--
-- This file drives the REAL Sky.client. For each hazard it waits for MOVE!, reads the ring the client DREW
-- (the HazardZone part), then walks at WalkSpeed in one of eight directions (the camera's W/A/S/D and
-- diagonals, so relative to what the player sees, not to the lane) until the root is just outside the
-- drawn ring, and stands. Never hit. A player who stays put is hit every time, so the ring is not a
-- safe-everywhere decoration. The drawn ring's size and centre are checked against the kind's hit radius
-- and where the player stood.
--
-- Headless limits: no physics. Walking is a CFrame step per frame at 16 studs/s; a hit is observed as the
-- PlatformStand the client sets, and the knock is cancelled so the next hazard starts from the same tile.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local Progression = mod("Progression")
local EnvBands = mod("EnvBands")
local Hz = Config.Hazards
local bands = Config.Env.Bands
Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in-memory, this run only: many hazards in a short check

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local warning = plr.PlayerGui:FindFirstChild("Plus1Sky"):FindFirstChild("Root"):FindFirstChild("HazardWarning")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

local camLook = Vector3.new(0, -0.35, 1).Unit
local hits = 0
local DT = 1 / 30
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position - camLook * 16, hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if hum.PlatformStand then
		hits += 1
		hum.PlatformStand = false
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
end
local function hazardKind()
	for _, c in folder:GetChildren() do
		local k = string.match(c.Name, "^Hazard_([%a]+)_")
		if k then return k end
	end
	return nil
end

-- the eight ways a player on a keyboard or thumbstick walks, relative to the CAMERA
local camForward = Vector3.new(camLook.X, 0, camLook.Z).Unit
local camRight = Vector3.new(-camForward.Z, 0, camForward.X)
local MOVES = {
	{ "S (back)", -camForward },
	{ "W (toward it)", camForward },
	{ "A", -camRight },
	{ "D", camRight },
	{ "S+A", (-camForward - camRight).Unit },
	{ "S+D", (-camForward + camRight).Unit },
	{ "W+A", (camForward - camRight).Unit },
	{ "W+D", (camForward + camRight).Unit },
}

local walkedHits, walked, stayHits, stayed = 0, 0, 0, 0
local ringSizeBad, ringCentreBad, ringYBad = nil, nil, nil
local hitExample = nil
local byMove = {}
local kindsSeen = {}

local function oneHazard(home, move)
	-- never move the climber while a hazard is still flying (a teleport locks its lane where it was)
	for _ = 1, math.floor(15 / DT) do
		if hazardKind() == nil then break end
		frame(DT)
	end
	hrp.CFrame = CFrame.new(home)
	hum.MoveDirection = Vector3.new(1, 0, 0) -- climbing input while waiting: never idles into rest
	for _ = 1, math.floor((Hz.IntervalMax + 12) / DT) do
		frame(DT)
		if hazardKind() then break end
	end
	local kind = hazardKind()
	if kind == nil then return false end
	kindsSeen[kind] = true
	hum.MoveDirection = Vector3.zero
	local before = hits
	local done = false
	for _ = 1, math.floor(12 / DT) do
		if not done and warning.Visible and string.find(warning.Text, "MOVE!", 1, true) then
			done = true
			local zone = folder:FindFirstChild("HazardZone")
			local stoodAt = hrp.Position
			local radius = zone.Size.Y / 2
			local want = Hz.Kinds[kind].hitRadius + Hz.PlayerRadius
			if math.abs(radius - want) > 0.05 then
				ringSizeBad = ringSizeBad or string.format("%s ring radius %.2f, hit zone %.2f", kind, radius, want)
			end
			local centre = Vector3.new(zone.Position.X, 0, zone.Position.Z)
			local flat = Vector3.new(stoodAt.X, 0, stoodAt.Z)
			if (centre - flat).Magnitude > 0.05 then
				ringCentreBad = ringCentreBad or string.format("%s ring centred %.2f studs from where the player stood", kind, (centre - flat).Magnitude)
			end
			if math.abs(zone.Position.Y - (stoodAt.Y - 3)) > 0.05 then
				ringYBad = ringYBad or string.format("%s ring at y %.2f, feet at %.2f", kind, zone.Position.Y, stoodAt.Y - 3)
			end
			if move then
				-- walk until the root is just outside the ring as DRAWN, then let go of the stick
				local dir = move[2]
				hum.MoveDirection = dir
				for _ = 1, 60 do
					local p = hrp.Position
					if (Vector3.new(p.X, 0, p.Z) - centre).Magnitude > radius + 0.05 then break end
					hrp.CFrame = CFrame.new(p + dir * 16 * DT)
					frame(DT)
				end
				hum.MoveDirection = Vector3.zero
			end
		end
		frame(DT)
		if hazardKind() == nil then break end
	end
	local wasHit = hits > before
	if move then
		walked += 1
		byMove[move[1]] = byMove[move[1]] or { 0, 0 }
		byMove[move[1]][2] += 1
		if wasHit then
			walkedHits += 1
			byMove[move[1]][1] += 1
			hitExample = hitExample or string.format("%s, walking %s", kind, move[1])
		end
	else
		stayed += 1
		if wasHit then stayHits += 1 end
	end
	-- let the knock (if any) wear off before the next one
	for _ = 1, math.floor(1.2 / DT) do frame(DT) end
	return true
end

local SWEEP = { { "treetops", 10 }, { "cloudsea", 25 }, { "storm", 45 }, { "edge", 70 }, { "orbit", 100 }, { "deep", 160 }, { "galaxy", 250 } }
for bi, entry in SWEEP do
	local b = bands[EnvBands.indexOf(bands, entry[1])]
	truthy(b ~= nil and b.hazards and #b.hazards > 0, "band " .. entry[1] .. " has hazards")
	local home = Vector3.new(0, Progression.yAtProgress(entry[2], Config.Tower) + 3.5, 0)
	for i = 1, #MOVES do
		-- rotate which move goes with which band, so every move meets every band's kinds over the sweep
		oneHazard(home, MOVES[((i + bi) % #MOVES) + 1])
	end
	oneHazard(home, nil) -- the control: stays put
	oneHazard(home, nil)
end

local rows = {}
for _, m in MOVES do
	local r = byMove[m[1]] or { 0, 0 }
	table.insert(rows, string.format("%s %d/%d", m[1], r[1], r[2]))
end
local kinds = {}
for k in kindsSeen do table.insert(kinds, k) end
table.sort(kinds)
print(string.format("  walked out of the ring: %d hit of %d (%s)", walkedHits, walked, table.concat(rows, ", ")))
print(string.format("  stayed in the ring: %d hit of %d; kinds seen: %s", stayHits, stayed, table.concat(kinds, ",")))

truthy(walked >= 50, "the sweep walked out of many rings (" .. walked .. ")")
truthy(#kinds >= 9, "and met nearly every hazard kind (" .. #kinds .. ": " .. table.concat(kinds, ",") .. ")")
eq(walkedHits, 0, "stepping out of the drawn ring in any of the eight directions dodges" .. (if hitExample then " (hit: " .. hitExample .. ")" else ""))
truthy(stayed >= 10 and stayHits == stayed, "a player who stays in the ring is hit every time (" .. stayHits .. "/" .. stayed .. ")")
eq(ringSizeBad, nil, "the ring is drawn exactly as wide as the hit zone (hitRadius + PlayerRadius)")
eq(ringCentreBad, nil, "the ring is centred where the player stood when the lane locked")
eq(ringYBad, nil, "the ring lies at the player's feet")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump dodge: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump dodge check failed", 0)
end
