-- Escape Room Lab — THE PLAYER'S PATH, walked through the real server and the real HUD.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--       cd ../escape-room-lab && luau tests/walk.luau 2>&1
-- ALWAYS rebuild the bundle first: this file reads the bundle, not src/.
--
-- A new player on a 800x360 touch phone joins, walks into the Solo Lift, plays room 1 (a Lamp Grid and
-- the door) and room 2 (a Flask Shelf and the door): every action is a tap on a HUD button (which fires
-- Act through the LocalPlayer, exactly as a phone would), every station is opened through its
-- ProximityPrompt, and every puzzle is read off what the OVERLAY renders (lamp glyphs, flask letters,
-- clue sentences, door lines) and solved with the game's own pure solvers. Nothing reads the server's
-- answers; none exist outside its script memory.
--
-- Durations are LOWER BOUNDS on a human's: zero reading and thinking time, instant taps, straight-line
-- walking at exactly WalkSpeed 16. The pacing model (tests/Pacing.spec.luau) adds the human part.

local Harness = require("../../robloxemu/emu/harness")
local h = Harness.new({
	bundle = require("../../robloxemu/build/escape-room-lab"),
	name = "escape-room-lab-walk",
	viewport = { 800, 360 },
	touch = true,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS, ws = h.ReplicatedStorage, h.workspace
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Text, Lamps, Shelf, CodeLock = mod("Config"), mod("Text"), mod("Lamps"), mod("Shelf"), mod("CodeLock")
local W = Config.World
local R = {}
for _, n in { "Act", "RoomState", "Notice", "Profile", "Open" } do R[n] = RS.LabRemotes:FindFirstChild(n) end

local plr = h:join("Walker", 4711)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Lab.client"))
local RunService = h.game:GetService("RunService")
local cam = ws.CurrentCamera
local hud = plr.PlayerGui:FindFirstChild("LabHud"):FindFirstChild("Root")
local overlay = hud:FindFirstChild("Overlay")
local banner = hud:FindFirstChild("Banner")
local cardLabel = hud:FindFirstChild("Card")

local clock, studs, taps = 0, 0, 0
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 4, 10), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	clock += dt
end
local function wait(sec)
	local t = 0
	while t < sec - 1e-9 do
		frame(0.1)
		t += 0.1
	end
end
-- walk in a straight line at WalkSpeed, 10 frames a second, with the stick held (MoveDirection)
local function walkTo(target)
	local start = hrp.Position
	local flat = Vector3.new(target.X - start.X, 0, target.Z - start.Z)
	local d = flat.Magnitude
	if d < 0.05 then return 0 end
	hum.MoveDirection = flat.Unit
	local steps = math.max(1, math.ceil(d / (W.WalkSpeed * 0.1)))
	for i = 1, steps do
		hrp.CFrame = CFrame.new(start + flat * (i / steps) + Vector3.new(0, target.Y - start.Y, 0) * (i / steps))
		frame(d / steps / W.WalkSpeed)
	end
	hum.MoveDirection = Vector3.zero
	studs += d
	return d
end
local function tap(btn)
	assert(btn ~= nil, "a button to tap")
	taps += 1
	btn.Activated:Fire()
	frame(0.1)
end
local function last(remote)
	local s = remote:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function noticesSince(n, kind)
	local out = {}
	local list = R.Notice:sentTo(plr)
	for i = n + 1, #list do
		local p = list[i].args[1]
		if type(p) == "table" and (kind == nil or p.kind == kind) then table.insert(out, p) end
	end
	return out
end
local function zoneFolder()
	for _, z in ws.Zones:GetChildren() do
		if z:FindFirstChild("DoorBoard", true) then return z end
	end
	return nil
end
local function promptOn(partName)
	local z = zoneFolder()
	local p = z and z:FindFirstChild(partName, true)
	return p and p:FindFirstChildOfClass("ProximityPrompt")
end
local function origin()
	local rs = last(R.RoomState)
	return Vector3.new(rs.origin[1], rs.origin[2], rs.origin[3])
end

--============================================================ join
print("== the walk: a new player on a 800x360 touch phone")
local spawn = ws.Atrium.AtriumSpawn
print(string.format("  spawned at (%.2f, %.2f, %.2f), %.2f studs (xz) from AtriumSpawn's centre", hrp.Position.X, hrp.Position.Y,
	hrp.Position.Z, math.sqrt((hrp.Position.X - spawn.Position.X) ^ 2 + (hrp.Position.Z - spawn.Position.Z) ^ 2)))
wait(0.5)
truthy(banner.Visible and string.find(banner.Text, "SOLO LIFT", 1, true) ~= nil, "the HUD tells a new player where to go: " .. banner.Text)
local arrow = ws.LabLocalEnv:FindFirstChild("GuideArrow")
truthy(arrow and arrow.Transparency < 1, "a guide arrow bobs over the Solo Lift")
print("  HUD: " .. banner.Text)

--============================================================ into the Solo Lift
local t0 = clock
walkTo(Vector3.new(W.SoloCab[1], 3.5, W.SoloCab[2]))
local reachLift = clock - t0
local n0 = #R.Notice:sentTo(plr)
local waited = 0
-- the doors (review-1 A2): they shut for THIS rider only, a local part that only the rider's own character
-- collides with; the server never shuts a door, so riders on a loop cannot keep anyone else out
local localDoor, serverDoorShut = nil, false
while last(R.RoomState) == nil or last(R.RoomState).where ~= "room" do
	frame(0.1)
	waited += 0.1
	local ld = ws.LabLocalEnv:FindFirstChild("SoloDoorLocal")
	if ld and ld.CanCollide and ld.Transparency < 0.5 then localDoor = localDoor or ld end
	for _, d in ws.Atrium:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and string.find(d.Name, "Door", 1, true) then serverDoorShut = true end
	end
	if waited > 10 then break end
end
truthy(localDoor ~= nil, "the doors close for the ride: the rider's own, collidable and visible")
if localDoor then
	local off = (localDoor.Position - Vector3.new(W.SoloCab[1], localDoor.Position.Y, W.SoloCab[2] + W.CabHalf)).Magnitude
	truthy(off < 0.5 and localDoor.Size.X >= 2 * W.CabHalf - 0.01 and localDoor.Size.Y >= 9,
		string.format("they fill the Solo Lift's doorway (%.2f studs off its centre line, %.1f x %.1f)", off, localDoor.Size.X, localDoor.Size.Y))
end
eq(serverDoorShut, false, "the server shuts no door: nobody else is kept out of the Solo Lift")
local ride = noticesSince(n0, "ride")[1]
truthy(ride ~= nil, "the lift says where it is going: " .. tostring(ride and ride.text))
wait(0.1)
eq(ws.LabLocalEnv:FindFirstChild("SoloDoorLocal"), nil, "the rider's doors are gone once the room is reached")
local rs = last(R.RoomState)
eq(rs and rs.slot, 1, "the lift took the new player to room 1")
print(string.format("  walked %.1f studs to the Solo Lift in %.2f s; the doors closed and the ride took %.1f s more", studs, reachLift, waited))
wait(0.2)
truthy(string.find(cardLabel.Text, "ROOM 1", 1, true) ~= nil, "the room card: " .. cardLabel.Text)
print("  card: " .. cardLabel.Text .. " / " .. hud.CardSub.Text)

--============================================================ one room, through the overlay
local function standAt(id)
	local o = origin()
	local p = W.Stations[id]
	local target
	if id == "Door" then target = o + Vector3.new(0, 3, -12)
	else target = o + Vector3.new(p[1] * 0.78, 3, p[3]) end
	walkTo(target)
end
local function openStation(id)
	standAt(id)
	local pp = promptOn(if id == "Door" then "Door" else "Station_" .. id)
	assert(pp, "a prompt for " .. id)
	pp.Triggered:Fire(plr)
	frame(0.1)
	truthy(overlay.Visible, id .. ": the prompt opens the overlay")
end
local function close()
	tap(overlay:FindFirstChild("CloseButton", true))
end

local function playLamp(id)
	openStation(id)
	local grid = {}
	local n = 0
	for _, b in overlay:FindFirstChild("LampGrid", true):GetChildren() do
		local i = tonumber(string.match(b.Name, "^Lamp_(%d+)$"))
		if i then
			grid[i] = b.Text == "\u{25CF}"
			n += 1
		end
	end
	local size = math.floor(math.sqrt(n) + 0.5)
	local presses = Lamps.solve(grid, size)
	local before = taps
	for _, i in presses do tap(overlay:FindFirstChild("Lamp_" .. i, true)) end
	local rs2 = last(R.RoomState)
	local solved = false
	for _, s in rs2.stations do if s.id == id then solved = s.solved end end
	truthy(solved, id .. ": the lamp grid read off the overlay is solved by its taps")
	print(string.format("  %s LAMP GRID %dx%d: %d taps on the glyphs the overlay drew; banner: %s", id, size, size, taps - before, banner.Text))
	close()
end

local function playShelf(id)
	openStation(id)
	local flasks, clues = {}, {}
	for s = 1, 5 do
		local b = overlay:FindFirstChild("Flask_" .. s, true)
		if b then flasks[s] = table.find(Text.FlaskLetters, b.Text) end
	end
	local list = overlay:FindFirstChild("ClueList", true)
	for i = 1, 9 do
		local l = list:FindFirstChild("Clue_" .. i)
		if l then table.insert(clues, Text.parseShelfClue(l.Text)) end
	end
	local colors = table.clone(flasks)
	local sols = Shelf.solve(colors, clues)
	eq(#sols, 1, id .. ": the clue sentences the overlay shows fit exactly one order")
	local target = sols[1]
	local before = taps
	for i = 1, #target do
		local cur = {}
		for s = 1, #target do cur[s] = table.find(Text.FlaskLetters, overlay:FindFirstChild("Flask_" .. s, true).Text) end
		if cur[i] ~= target[i] then
			local j = table.find(cur, target[i])
			tap(overlay:FindFirstChild("Flask_" .. i, true))
			tap(overlay:FindFirstChild("Flask_" .. j, true))
		end
	end
	tap(overlay:FindFirstChild("TestButton", true))
	local rs2 = last(R.RoomState)
	local solved = false
	for _, s in rs2.stations do if s.id == id then solved = s.solved end end
	truthy(solved, id .. ": TEST accepts the order the clues allow")
	print(string.format("  %s FLASK SHELF of %d: %d clues read, %d taps (swaps + TEST)", id, #target, #clues, taps - before))
	close()
end

local function playDoor()
	openStation("Door")
	local lines = {}
	local list = overlay:FindFirstChild("DoorClues", true)
	for i = 1, 6 do
		local row = list:FindFirstChild("Line_" .. i)
		if row then
			local g = Text.parseCodeGuess(row.Guess.Text)
			local a, b = Text.parseCodeSentence(row.Sentence.Text)
			truthy(g ~= nil and a ~= nil, "door line " .. i .. " parses off the overlay: " .. row.Guess.Text .. " / " .. row.Sentence.Text)
			if g and a then table.insert(lines, { guess = g, a = a, b = b }) end
		end
	end
	local rs2 = last(R.RoomState)
	local codes = CodeLock.solve(lines, rs2.door.L, rs2.door.alphabet)
	eq(#codes, 1, "the door lines on the overlay fit exactly one code")
	local toggle = overlay:FindFirstChild("ToggleButton", true)
	if toggle.Visible and not overlay:FindFirstChild("Keypad", true).Visible then tap(toggle) end
	local before = taps
	local n = #R.Notice:sentTo(plr)
	for _, d in codes[1] do tap(overlay:FindFirstChild("Key_" .. d, true)) end
	truthy(string.find(overlay:FindFirstChild("CodeDisplay", true).Text, Text.codeGuess(codes[1]), 1, true) ~= nil,
		"the keypad shows the code before ENTER")
	tap(overlay:FindFirstChild("Key_Enter", true))
	wait(0.3)
	local esc = noticesSince(n, "escape")[1]
	truthy(esc ~= nil, "ENTER opens the door")
	print(string.format("  DOOR: %d lines read, %d taps on the keypad; card: %s", #lines, taps - before, cardLabel.Text))
	return esc
end

local function playRoom()
	local rs0 = last(R.RoomState)
	local s0, st0, tap0 = clock, studs, taps
	local firstAction = nil
	for _, s in rs0.stations do
		if s.kind == "lamp" then playLamp(s.id) else playShelf(s.id) end
		firstAction = firstAction or (clock - s0)
	end
	local esc = playDoor()
	truthy(not overlay.Visible, "the overlay closes on the escape")
	-- into the exit cab, NEXT
	local o = origin()
	walkTo(o + Vector3.new(0, 3, -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)))
	return { slot = rs0.slot, stars = esc and esc.stars, seconds = clock - s0, studs = studs - st0, taps = taps - tap0, first = firstAction }
end

local spawnClock = t0
local r1 = playRoom()
print(string.format("  ROOM 1: escaped with %d stars; %.1f s (lower bound), %.1f studs, %d taps; first station solved %.1f s after arrival",
	r1.stars or -1, r1.seconds, r1.studs, r1.taps, r1.first or -1))
eq(r1.stars, 3, "room 1: 3 stars (no wrong try, no hint)")
eq(plr.leaderstats.Stars.Value, 3, "leaderstats 3")
local nextPrompt = promptOn("NextPanel")
truthy(nextPrompt and nextPrompt.Enabled, "NEXT is lit in the exit cab")
local n1 = #R.Notice:sentTo(plr)
nextPrompt.Triggered:Fire(plr)
wait(Config.Lift.RideSeconds + 0.3)
local rsB = last(R.RoomState)
eq(rsB.slot, 2, "NEXT took the lift on to room 2: the second loop")
print(string.format("  NEXT: %s", tostring((noticesSince(n1, "ride")[1] or {}).text)))
local r2 = playRoom()
print(string.format("  ROOM 2: escaped with %d stars; %.1f s (lower bound), %.1f studs, %d taps", r2.stars or -1, r2.seconds, r2.studs, r2.taps))
eq(r2.stars, 3, "room 2: 3 stars")
eq(plr.leaderstats.Stars.Value, 6, "leaderstats 6 after two rooms")
local prof = last(R.Profile)
eq(prof.frontier, 3, "the frontier moved to room 3")
eq(prof.continue, 3, "Continue points at room 3")
local localParts = 0
for _, d in ws.LabLocalEnv:GetDescendants() do if d:IsA("BasePart") then localParts += 1 end end
print(string.format("  totals: %.1f s from the first step to room 2's exit cab, %.1f studs walked, %d taps, %d stars; %d local parts",
	clock - spawnClock, studs, taps, prof.stars, localParts))
print(string.format("  the chip reads: %s", hud.StarChip.StarText.Text))

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do print("  [warn] " .. w) end
print(string.format("walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
