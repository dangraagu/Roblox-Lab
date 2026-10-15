-- Outpost Zero — the Grand Airship's hand-over, frame by frame: the client's flying copy must become the server's
-- moored airship without a jump, a turn or a blank frame (round 2, finding B2; EYECANDY §8 #5 "Does the hand-over
-- jump?"). The brag moment, thumbnail 1 and clip 2 all end on this frame.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_handover.luau 2>&1
--
-- 60 frames a second through the real server and the real Sky.client. robloxemu replicates instantly, so the
-- moored model appears the server tick after the flight ends; on Roblox it arrives later, and the copy must wait
-- for it (asserted here by holding the model back). (origin: the reviewer's rv_handover2.luau)

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 4646
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, seed = 4646, credits = 1e15, lifetime = 1e15, lots = {}, savedAt = os.time(),
	ordersUntil = os.time() + 600, popAt = 0, airshipSeen = false, tutorial = 3 } })
assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
-- a filler takes shelf 1 first, so the player's shelf is turned on the ring (its yaw is not the world's)
local filler = h:join("Filler", 999)
h:advance(1)
local plr = h:join("Hand", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Rock
hum.MoveDirection = Vector3.new(0, 0, 0)
h:leave(filler)
h:advance(1)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))
local State = RS.CityRemotes.State
local function st() local s = State:sentTo(plr); return s[#s] and s[#s].args[1] end
local shelf = plr.RespawnLocation.Parent
local sky = h.workspace:FindFirstChild("OutpostLocalSky")
local probe = plr.PlayerGui.OutpostSky:FindFirstChild("OutpostSkyProbe")
local DT = 1 / 60
local function frame() RunService.RenderStepped:Fire(DT); h:advance(DT) end

local function yawOf(cf) local r = cf.RightVector; return math.deg(math.atan2(r.X, r.Z)) end
local function turn(a, b) return math.abs(((a - b + 540) % 360) - 180) end
-- the angle of the rotation between two frames: trace(Ra^T Rb) = the sum of the dot products of their axes
local function angleBetween(a: CFrame, b: CFrame): number
	local tr = a.RightVector:Dot(b.RightVector) + a.UpVector:Dot(b.UpVector) + a.LookVector:Dot(b.LookVector)
	return math.deg(math.acos(math.clamp((tr - 1) / 2, -1, 1)))
end
local function flightPart(name)
	local p = sky:FindFirstChild("Flight_" .. name)
	if p and p.Parent and p.Transparency < 1 then return p end
	return nil
end

--============================================================================ 1. the flight, every frame, to 3 s after the mooring
-- buy with the ★ until the purchase that opens the Skyport
while st().population < Config.Districts[Config.SkyportDistrict].open do
	local s = st()
	shelf.Lots:FindFirstChild("Lot_" .. s.star.key).Post.BuildPrompt.Triggered:Fire(plr)
	for _ = 1, 8 do frame() end
end
local frames, blank, maxYawStep, flightFrames = 0, 0, 0, 0
local lastFlight, lastYaw = nil, nil
local flightPoses = {} -- the last flight frame's pose of every part
local mooredAt, mooredFrame = nil, nil
local afterMoor, both = 0, 0
for _ = 1, 60 * 30 do
	frame()
	frames += 1
	local g = flightPart("Gondola")
	local moored = shelf:FindFirstChild("Airship")
	if g then
		flightFrames += 1
		local y = yawOf(g.CFrame)
		if lastYaw then maxYawStep = math.max(maxYawStep, turn(y, lastYaw)) end
		lastYaw = y
		lastFlight = g.CFrame
		for _, d in sky:GetChildren() do
			local n = string.match(d.Name, "^Flight_(.+)$")
			if n and d:IsA("BasePart") then flightPoses[n] = d.CFrame end
		end
	end
	if moored and mooredAt == nil then mooredAt = frames end
	if g == nil and moored == nil and flightFrames > 0 then blank += 1 end
	if g ~= nil and moored ~= nil then both += 1 end
	if mooredAt then
		afterMoor += 1
		if afterMoor >= 180 then break end
	end
end
truthy(flightFrames > 60 * 10, "set-up: the flight was drawn (" .. flightFrames .. " frames)")
truthy(mooredAt ~= nil, "set-up: the server moored the airship")
print(string.format("  flight: %d frames drawn; frames with no airship on screen: %d; largest turn between two frames: %.2f deg",
	flightFrames, blank, maxYawStep))
eq(blank, 0, "no frame between the flight and the mooring shows no airship")
print(string.format("  frames that drew the flying copy and the moored airship together: %d", both))
truthy(both <= 1, string.format("the copy goes the frame the moored airship is there, not later (%d frames with both)", both))
truthy(maxYawStep <= 1, string.format("the flying copy never snaps round (largest turn between frames %.2f deg)", maxYawStep))

--============================================================================ 2. the hand-over pose: the copy's last frame IS the moored airship
local ship = shelf:FindFirstChild("Airship")
local worstMove, worstTurn, matched = 0, 0, 0
local detail = {}
if ship then
	for _, d in ship:GetChildren() do
		if d:IsA("BasePart") then
			local fp = flightPoses[d.Name]
			if fp then
				matched += 1
				local mv = (fp.Position - d.CFrame.Position).Magnitude
				local tn = angleBetween(fp, d.CFrame)
				if mv > worstMove or tn > worstTurn then
					table.insert(detail, string.format("%s %.2f studs %.1f deg", d.Name, mv, tn))
				end
				worstMove = math.max(worstMove, mv)
				worstTurn = math.max(worstTurn, tn)
			end
		end
	end
end
print(string.format("  hand-over: %d parts compared; the largest jump %.3f studs, the largest turn %.2f deg", matched, worstMove, worstTurn))
eq(matched, 12, "every one of the 12 parts is in both the flying copy and the moored airship")
truthy(worstMove <= 0.05, string.format("no part jumps at the hand-over (largest %.3f studs: %s)", worstMove, table.concat(detail, ", ")))
truthy(worstTurn <= 0.5, string.format("no part turns at the hand-over (largest %.2f deg)", worstTurn))
if ship then
	-- the moored pose itself is the one the shot list frames (EYECANDY §9 #1: past the Town Hall toward district 1, the
	-- airship broadside): its nose lies across the shelf's line to the ring's centre, not along it
	local c = shelf:FindFirstChild("Rock").Position
	local inward = Vector3.new(-c.X, 0, -c.Z).Unit
	local nose = ship.Gondola.CFrame.RightVector
	truthy(math.abs(nose:Dot(inward)) < 1e-6, string.format("moored broadside to the plaza's view toward district 1 (nose . inward = %.3f)", nose:Dot(inward)))
end
eq(probe:Invoke().flightActive, false, "once moored, the flying copy is gone")
eq(flightPart("Gondola"), nil, "...and not drawn")

--============================================================================ 3. the copy waits for a mooring that replicates late, and never forever
-- On Roblox the moored model reaches the client a moment after the flight ends. Model that with an arrival nobody
-- moors (a flight announced to the shelf the filler left): the copy holds its last pose a while, then goes.
do
	local emptyK = 1
	local mast = shelf.Parent:FindFirstChild("Shelf_" .. emptyK).TownHall.HallBody.Position + Vector3.new(0, 30, 0)
	local Announce = RS.CityRemotes.Announce
	Announce:FireAllClients({ kind = "airship", shelf = emptyK, mast = { mast.X, mast.Y, mast.Z }, seconds = Config.Airship.FlightSeconds, name = "Nobody" })
	local drawnAfterEnd, held = 0, nil
	for i = 1, 60 * 20 do
		frame()
		local g = flightPart("Gondola")
		local t = i * DT
		if g and t > Config.Airship.FlightSeconds + 0.1 then
			drawnAfterEnd += 1
			if held == nil then held = g.CFrame elseif (g.CFrame.Position - held.Position).Magnitude > 1e-6 then held = false end
		end
	end
	local hold = drawnAfterEnd * DT
	print(string.format("  a mooring that never comes: the copy held its last pose %.2f s after the flight, then went", hold))
	truthy(hold > 1, string.format("the copy waits at its last pose for a mooring that replicates late (%.2f s)", hold))
	truthy(held ~= false, "...without moving")
	truthy(hold <= (Config.Airship.HandOverSeconds or 0) + 0.1, string.format("...and never forever (%.2f s, at most %s)", hold, tostring(Config.Airship.HandOverSeconds)))
	eq(probe:Invoke().flightActive, false, "and then the copy is gone")
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero handover: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero handover check failed", 0) end
