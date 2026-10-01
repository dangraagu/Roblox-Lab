-- +1 Jump Every Step — the red ring and the MOVE! banner stay up for as long as the hazard can still hit.
-- Run: luau check_plus1jump_ringtime.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Second review, night of 2026-09-27 (LOW finding 1, docs/night-queue.md "H. Eye-candy - plus1-jump"): the
-- client hid the ring and the banner at the hazard's arrival time, but the hit test runs until the end of the
-- flight. The lane is aimed at a point up to AimJitter (1.2 studs) from where the player stood, so a player on
-- the far side of the ring from that point is reached AFTER the arrival time: hit, with no ring and no banner
-- on screen. Measured in tests/EnvConfig.spec.luau: 30 of 4 000 random points inside the ring, up to 0.08 s late.
--
-- This file drives the REAL Sky.client. At MOVE! it reads the ring and the lane the client DREW, works out
-- where the lane is really aimed (the drawn lane runs from the hazard through that point and 30 studs past),
-- and walks the player to a point inside the ring that the hazard reaches only after it has passed that point.
-- Then it stands there and records, frame by frame, whether the ring is drawn and the banner shows. Every hit
-- must come with the ring drawn on that frame and on the frame before, and the banner up on the frame before.
-- The lane line (the way in) goes at the arrival time, as before. And once the hazard has gone, the ring is
-- gone too (it does not stay up for ever).
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
local plr = h:join("Climber", 4343)
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
local DT = 1 / 30
local hitThisFrame = false
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position - camLook * 16, hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	hitThisFrame = false
	if hum.PlatformStand then
		hitThisFrame = true
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
local function ringDrawn()
	return folder:FindFirstChild("HazardZone") ~= nil
end

-- A point inside the drawn ring (horizontally, at the player's height) that the locked lane reaches only
-- after it has passed its aim point, by at least `delay` seconds. nil if the jitter leaves no such point.
local function lateSpot(zone, lane, speed, y, delay)
	local R = zone.Size.Y / 2
	local u = lane.CFrame.LookVector
	local beyond = lane.Position + u * (lane.Size.Z / 2)
	local aimPoint = beyond - u * 30
	local centre = Vector3.new(zone.Position.X, y, zone.Position.Z)
	local best, bestScore = nil, -math.huge
	for _, frac in { 0.95, 0.85, 0.7, 0.5 } do
		for deg = 0, 357, 3 do
			local a = math.rad(deg)
			local q = centre + Vector3.new(math.cos(a), 0, math.sin(a)) * (R * frac)
			local d = q - aimPoint
			local along = d:Dot(u)
			local perp = (d - u * along).Magnitude
			if perp < R - 0.2 then
				local contact = along - math.sqrt(R * R - perp * perp) -- studs past the aim point at first contact
				if contact / speed >= delay and contact > bestScore then
					best, bestScore = q, contact
				end
			end
		end
	end
	return best, bestScore
end

local forced, hits, missing = 0, 0, 0
local ringGoneBad, bannerGoneBad, ringHitFrameBad, ringStuck = 0, 0, 0, 0
local laneLate = 0
local example = nil
local kindsForced = {}
local notForceable = 0

local function oneHazard(home)
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
	hum.MoveDirection = Vector3.zero
	local target = nil
	local prevRing, prevBanner = true, true
	local wasHit = false
	for _ = 1, math.floor(12 / DT) do
		if target == nil and warning.Visible and string.find(warning.Text, "MOVE!", 1, true) then
			local zone = folder:FindFirstChild("HazardZone")
			local lane = folder:FindFirstChild("HazardLane")
			if zone and lane then
				target = lateSpot(zone, lane, Hz.Kinds[kind].speed, hrp.Position.Y, 0.04)
			end
			if target == nil then
				notForceable += 1
				target = false
			else
				forced += 1
				kindsForced[kind] = (kindsForced[kind] or 0) + 1
				-- walk there at WalkSpeed, then let go of the stick
				local p = hrp.Position
				local dir = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
				hum.MoveDirection = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zero
				for _ = 1, 60 do
					p = hrp.Position
					local rest = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
					if rest.Magnitude <= 16 * DT then
						hrp.CFrame = CFrame.new(Vector3.new(target.X, p.Y, target.Z))
						break
					end
					hrp.CFrame = CFrame.new(p + rest.Unit * 16 * DT)
					prevRing, prevBanner = ringDrawn(), warning.Visible
					frame(DT)
					if hitThisFrame then break end
				end
				hum.MoveDirection = Vector3.zero
			end
		end
		if not hitThisFrame then
			prevRing, prevBanner = ringDrawn(), warning.Visible
			frame(DT)
		end
		if hitThisFrame then
			hitThisFrame = false
			if target then
				wasHit = true
				hits += 1
				if not prevRing then
					ringGoneBad += 1
					example = example or kind .. ": hit with no ring on screen the frame before"
				end
				if not prevBanner then
					bannerGoneBad += 1
					example = example or kind .. ": hit with no banner on screen the frame before"
				end
				if not ringDrawn() then
					ringHitFrameBad += 1
					example = example or kind .. ": the ring vanished on the frame of the hit"
				end
				-- the lane line shows the way IN: it has gone once the hazard is past its aim point
				if folder:FindFirstChild("HazardLane") ~= nil then laneLate += 1 end
			end
		end
		if hazardKind() == nil then break end
	end
	if target and not wasHit then missing += 1 end
	if hazardKind() == nil and ringDrawn() then ringStuck += 1 end
	for _ = 1, math.floor(1.2 / DT) do frame(DT) end
	return true
end

local SWEEP = { { "treetops", 10 }, { "cloudsea", 25 }, { "storm", 45 }, { "edge", 70 }, { "orbit", 100 }, { "deep", 160 }, { "galaxy", 250 } }
for _, entry in SWEEP do
	local b = bands[EnvBands.indexOf(bands, entry[1])]
	truthy(b ~= nil and b.hazards and #b.hazards > 0, "band " .. entry[1] .. " has hazards")
	local home = Vector3.new(0, Progression.yAtProgress(entry[2], Config.Tower) + 3.5, 0)
	for _ = 1, 40 do
		oneHazard(home)
	end
end

local kinds = {}
for k, n in kindsForced do table.insert(kinds, k .. " " .. n) end
table.sort(kinds)
print(string.format("  stood inside the ring where the hazard arrives late: %d hazards (%s), %d hit, %d not placeable (jitter)",
	forced, table.concat(kinds, ", "), hits, notForceable))
print(string.format("  hits with no ring the frame before %d, no banner the frame before %d, ring gone on the hit frame %d; rings left after the hazard %d; lane still drawn at a late hit %d",
	ringGoneBad, bannerGoneBad, ringHitFrameBad, ringStuck, laneLate))

truthy(forced >= 8, "set-up: many hazards could be met late inside the ring (" .. forced .. ")")
eq(missing, 0, "set-up: every one of them hit (a player inside the ring is in danger)")
eq(ringGoneBad, 0, "every hit came with the ring drawn the frame before" .. (if example then " (" .. example .. ")" else ""))
eq(bannerGoneBad, 0, "and with the MOVE! banner up the frame before")
eq(ringHitFrameBad, 0, "and the ring still drawn on the frame of the hit")
eq(ringStuck, 0, "once the hazard has gone, the ring is gone too")
eq(laneLate, 0, "while the lane line (the way in) is gone by the time a late hit lands")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump ringtime: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump ringtime check failed", 0)
end
