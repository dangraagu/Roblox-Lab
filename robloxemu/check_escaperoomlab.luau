-- Escape Room Lab — the world has to be BUILT and PARENTED, a joining character has to LAND where the
-- engine puts it, every ProximityPrompt has to be reachable from a floor and has to answer, and the
-- Star Board has to exist and render.
--
-- Run:  py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--       luau check_escaperoomlab.luau 2>&1
-- ALWAYS rebuild the bundle first: this file reads build/, not the game's src/ (deep-vein's lesson).
--
-- Why this file exists: Grow a Crystal once shipped 166 green unit tests and an unreachable core loop
-- (a Part built and never parented). Nothing but asking the workspace catches that. So this asks the
-- workspace, puts a character where the engine would (robloxemu/SPAWN-ORDER.md), walks into the Solo
-- Lift, and solves room 1 from what the world shows: the lamp parts and the door board's text, through
-- the game's own pure solvers, the way a player reads them. No answer mirror exists to cheat with.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/escape-room-lab"),
	name = "escape-room-lab",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server loads (" .. tostring(errServer) .. ")")
if not okServer then
	print(string.format("escape-room-lab: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(0.5)

local RS = h.ReplicatedStorage
local ws = h.workspace
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Text = mod("Text")
local Lamps = mod("Lamps")
local CodeLock = mod("CodeLock")
local Config = mod("Config")

--============================================================ 1. the world is built and parented
local atrium = ws:FindFirstChild("Atrium")
local roof = ws:FindFirstChild("Roof")
local zonesFolder = ws:FindFirstChild("Zones")
truthy(atrium ~= nil, "workspace.Atrium exists")
truthy(roof ~= nil, "workspace.Roof exists")
truthy(zonesFolder ~= nil, "workspace.Zones exists")
local function countParts(root)
	local n = 0
	if root == nil then return 0 end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end
local atriumParts, roofParts = countParts(atrium), countParts(roof)
print(string.format("  boot: Atrium %d parts, Roof %d parts, Zones %d children", atriumParts, roofParts,
	zonesFolder and #zonesFolder:GetChildren() or -1))
truthy(atriumParts >= 12, "the Atrium has its floor, walls, lifts and board (" .. atriumParts .. " parts)")
truthy(roofParts >= 6, "the Roof has its deck, railing, dome and telescope (" .. roofParts .. " parts)")

-- exactly one enabled SpawnLocation, and it is AtriumSpawn (SPAWN-ORDER.md §7: the engine picks at
-- random among several; with none, new players would start on the Roof deck at y 150)
local spawns = {}
for _, d in ws:GetDescendants() do
	if d:IsA("SpawnLocation") and d.Enabled ~= false then table.insert(spawns, d) end
end
eq(#spawns, 1, "exactly one enabled SpawnLocation in the world")
local spawn = spawns[1]
eq(spawn and spawn.Name, "AtriumSpawn", "and it is AtriumSpawn")
eq(spawn and spawn.Neutral, true, "AtriumSpawn is Neutral")
eq(spawn and spawn.Duration, 0, "AtriumSpawn gives no ForceField (Duration 0)")
truthy(spawn and spawn:IsDescendantOf(ws), "AtriumSpawn is in the workspace")

local remotes = RS:FindFirstChild("LabRemotes")
truthy(remotes ~= nil, "ReplicatedStorage.LabRemotes exists")
local R = {}
for _, name in { "Act", "RoomState", "Hint", "Notice", "Profile", "Board", "Open" } do
	R[name] = remotes and remotes:FindFirstChild(name)
	truthy(R[name] ~= nil and R[name]:IsA("RemoteEvent"), "remote " .. name .. " exists")
end

--============================================================ 2. a joining character lands on AtriumSpawn
local plr = h:join("Ada", 7001)
eq(plr.RespawnLocation, spawn, "PlayerAdded points RespawnLocation at AtriumSpawn before any yield")
h:advance(1)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
local function xzDist(a, x, z) return math.sqrt((a.X - x) ^ 2 + (a.Z - z) ^ 2) end
local spawnTop = spawn.Position.Y + spawn.Size.Y / 2
truthy(xzDist(hrp.Position, spawn.Position.X, spawn.Position.Z) < 0.01,
	string.format("the root lands over AtriumSpawn (%.2f, %.2f, %.2f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
truthy(hrp.Position.Y > spawnTop, "and above the pad")
h:advance(2)
truthy(xzDist(hrp.Position, spawn.Position.X, spawn.Position.Z) < 0.01, "and is still there 2 s later (no late write moves it)")
eq(hum.WalkSpeed, Config.World.WalkSpeed, "the server set WalkSpeed 16")
local stats = plr:FindFirstChild("leaderstats")
local starsValue = stats and stats:FindFirstChild("Stars")
truthy(starsValue ~= nil, "leaderstats.Stars exists")
eq(starsValue and starsValue.Value, 0, "a new player has 0 stars")

local function lastTo(remote, p)
	local sent = remote:sentTo(p)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local prof = lastTo(R.Profile, plr)
truthy(prof ~= nil, "the server sent the Profile payload")
eq(prof and prof.frontier, 1, "frontier 1")
eq(prof and prof.continue, 1, "Continue goes to room 1")

--============================================================ 3. the Star Board exists and renders
local board = atrium and atrium:FindFirstChild("StarBoard")
truthy(board ~= nil and board:IsA("BasePart"), "the Star Board is a part in the Atrium")
local face = board and board:FindFirstChild("BoardFace")
truthy(face ~= nil and face:IsA("SurfaceGui"), "it carries the public SurfaceGui")
local function labelText(root, name)
	local l = root and root:FindFirstChild(name, true)
	return l and l.Text or nil
end
eq(labelText(face, "Title"), "STAR BOARD", "the board reads STAR BOARD")
do
	local rows = 0
	for i = 1, 10 do if face and face:FindFirstChild("Row_" .. i, true) then rows += 1 end end
	eq(rows, 10, "ten row labels")
	eq(labelText(face, "Note"), Config.Board.Text.EmptyPublic, "an empty public board says something useful")
	local d = (board.Position - spawn.Position).Magnitude
	truthy(d < 20, string.format("the board stands %.1f studs from the spawn", d))
end

--============================================================ 4. every prompt: reachable from a floor, and it answers
-- A stand point for a prompt: move from the prompt's part toward the middle of its space until the root
-- (3 studs over the floor) is inside the walkable area; it must then be within MaxActivationDistance.
local W = Config.World
local function walkableAtrium(p)
	return math.abs(p.X) <= W.AtriumHalfX - 1.5 and math.abs(p.Z) <= W.AtriumHalfZ - 1.5
end
local function standPoint(prompt, centre, floorY, walkable)
	local pos = prompt.Parent.Position
	local flat = Vector3.new(centre.X - pos.X, 0, centre.Z - pos.Z)
	local dir = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, 1)
	for d = 0, 20, 0.25 do
		local s = Vector3.new(pos.X + dir.X * d, floorY + 3, pos.Z + dir.Z * d)
		if walkable(s) then return s end
	end
	return nil
end

local responses = {}
local function sentCount(p)
	local n = 0
	for _, name in { "Notice", "Open", "Board", "RoomState", "Profile" } do n += #R[name]:sentTo(p) end
	return n
end
local function checkPrompt(prompt, centre, floorY, walkable, label)
	local part = prompt.Parent
	truthy(part ~= nil and part:IsA("BasePart") and part:IsDescendantOf(ws), label .. ": the prompt sits on a part in the world")
	eq(prompt.RequiresLineOfSight, false, label .. ": RequiresLineOfSight is off (wall stations)")
	local s = standPoint(prompt, centre, floorY, walkable)
	truthy(s ~= nil, label .. ": a floor point exists in front of it")
	if s == nil then return end
	local d = (s - part.Position).Magnitude
	truthy(d <= prompt.MaxActivationDistance, string.format("%s: reachable, %.1f studs from the floor (reach %.0f)",
		label, d, prompt.MaxActivationDistance))
	hrp.CFrame = CFrame.new(s)
	h:advance(0.1)
	local before, where = sentCount(plr), hrp.Position
	prompt.Triggered:Fire(plr)
	h:advance(0.3)
	local answered = sentCount(plr) > before or (hrp.Position - where).Magnitude > 1
	truthy(answered, label .. ": triggering it answers the player (a toast, a view or a move)")
	table.insert(responses, label)
end

local atriumPrompts = {}
for _, d in atrium:GetDescendants() do
	if d:IsA("ProximityPrompt") then table.insert(atriumPrompts, d) end
end
table.sort(atriumPrompts, function(a, b) return a.Parent.Name < b.Parent.Name end)
truthy(#atriumPrompts >= 3, "the Atrium has its prompts: Pair Lift GO, Star Board, Roof Access (" .. #atriumPrompts .. ")")
for _, p in atriumPrompts do
	checkPrompt(p, Vector3.new(0, 0, 0), 0, walkableAtrium, "Atrium " .. p.Parent.Name)
end
do
	-- a non-escapee at the Roof door is told why, in words
	local n = lastTo(R.Notice, plr)
	local found = false
	for _, rec in R.Notice:sentTo(plr) do
		if type(rec.args[1]) == "table" and string.find(tostring(rec.args[1].text), "Roof access is for Lab escapees", 1, true) then
			found = true
		end
	end
	truthy(found, "the Roof door tells a non-escapee why it stays shut")
	local b = lastTo(R.Board, plr)
	truthy(b ~= nil and b.mode == "friends", "the board prompt asks for the friends view")
	eq(b and b.message, Config.Board.Text.FriendsFailed,
		"with no GetFriendsAsync (the emulator has none) the friends view says it could not load, in words")
	local _ = n
end

--============================================================ 5. into the Solo Lift and room 1
hrp.CFrame = CFrame.new(W.SoloCab[1], 3.5, W.SoloCab[2])
h:advance(Config.Lift.BoardSeconds + 0.5)
h:advance(Config.Lift.RideSeconds + 0.5)
local rs = lastTo(R.RoomState, plr)
truthy(rs ~= nil and rs.where == "room", "the Solo Lift took the player into a room")
eq(rs and rs.slot, 1, "room 1")
local origin = rs and Vector3.new(rs.origin[1], rs.origin[2], rs.origin[3]) or Vector3.zero
local loc = hrp.Position - origin
truthy(math.abs(loc.X) <= W.CabHalf and loc.Z >= W.RoomHalf + W.Wall and loc.Z <= W.RoomHalf + W.Wall + 2 * W.CabHalf,
	string.format("the root stands in the entry cab (local %.1f, %.1f, %.1f)", loc.X, loc.Y, loc.Z))
local zone = nil
for _, z in zonesFolder:GetChildren() do
	if z:FindFirstChild("Station_A", true) then zone = z end
end
truthy(zone ~= nil, "the room is built and parented under workspace.Zones")
local roomParts = countParts(zone)
print(string.format("  room 1: %d server parts (cap %d)", roomParts, W.MaxRoomParts))
truthy(roomParts > 40 and roomParts <= W.MaxRoomParts, "room parts within the cap")

local roomPrompts = {}
for _, d in zone:GetDescendants() do
	if d:IsA("ProximityPrompt") then table.insert(roomPrompts, d) end
end
local names = {}
for _, p in roomPrompts do names[p.Parent.Name] = p end
for _, n in { "Station_A", "Door", "LeaveEntry", "NextPanel", "LeaveExit" } do
	truthy(names[n] ~= nil, "room prompt on " .. n)
end
local function walkableRoom(p)
	local l = p - origin
	local inRoom = math.abs(l.X) <= W.RoomHalf - 1 and math.abs(l.Z) <= W.RoomHalf - 1
	local inCab = math.abs(l.X) <= W.CabHalf - 1 and ((l.Z >= W.RoomHalf + W.Wall + 1 and l.Z <= W.RoomHalf + W.Wall + 2 * W.CabHalf - 1)
		or (l.Z <= -(W.RoomHalf + W.Wall + W.CorridorLength + 1) and l.Z >= -(W.RoomHalf + W.Wall + W.CorridorLength + 2 * W.CabHalf - 1)))
	return inRoom or inCab
end
for _, n in { "Station_A", "Door" } do
	checkPrompt(names[n], origin, 0, walkableRoom, "room " .. n)
	local o = lastTo(R.Open, plr)
	eq(o and o.station, if n == "Station_A" then "A" else "Door", "the " .. n .. " prompt opens that station")
end
do
	-- the exit lift's prompts wait for the door
	eq(names.NextPanel.Enabled, false, "NEXT is off until the door opens")
end

--============================================================ 6. solve room 1 from what the world shows
local function readLamps(panel)
	local lamps = {}
	for _, c in panel:GetChildren() do
		local i = tonumber(string.match(c.Name, "^Lamp_(%d+)$"))
		if i then lamps[i] = c.Material == Enum.Material.Neon end
	end
	return lamps
end
-- THE DOOR GATE (CLAUDE.md trap 1): while a line is dark the keypad takes no code at all, right or
-- wrong, and says why. Every valid code is tried, so the right one is among them.
do
	hrp.CFrame = CFrame.new(origin + Vector3.new(0, 3, -12))
	local n0 = #R.Notice:sentTo(plr)
	local rsd = lastTo(R.RoomState, plr)
	local tried = 0
	for _, code in CodeLock.space(rsd.door.L, rsd.door.alphabet) do
		R.Act:simulateFireServer(plr, "Door", "enter", table.clone(code))
		tried += 1
		h:advance(0.11) -- inside the 10/s rate limit
	end
	local rsAfter = lastTo(R.RoomState, plr)
	eq(rsAfter.door.solved, false, string.format("the gate: %d codes tried while a line is dark, the door stays shut", tried))
	eq(rsAfter.door.lockedFor, 0, "and no lockout started: nothing was even judged")
	local dark = false
	for _, rec in R.Notice:sentTo(plr) do
		if type(rec.args[1]) == "table" and string.find(tostring(rec.args[1].text), "keypad is dark", 1, true) then dark = true end
	end
	truthy(dark and #R.Notice:sentTo(plr) > n0, "the player is told the keypad is dark and which station lights it")
	eq(starsValue.Value, 0, "no star from guessing")
end

local stationA = zone:FindFirstChild("Station_A", true)
local grid = readLamps(stationA)
local n = math.floor(math.sqrt(#grid) + 0.5)
truthy(#grid == 9 and not Lamps.allLit(grid), "room 1's lamp grid is 3x3 and not lit")
hrp.CFrame = CFrame.new(origin + Vector3.new(-12, 3, 0))
local presses = Lamps.solve(grid, n)
print(string.format("  lamp grid A: %d unlit, solved in %d presses read off the lamp parts", (function()
	local c = 0
	for _, v in grid do if not v then c += 1 end end
	return c
end)(), #presses))
for _, i in presses do
	R.Act:simulateFireServer(plr, "A", "press", i)
	h:advance(0.2)
end
truthy(Lamps.allLit(readLamps(stationA)), "the lamp parts are all lit after the presses")
local rs2 = lastTo(R.RoomState, plr)
truthy(rs2 and rs2.stations[1].solved, "the server solved station A")
truthy(rs2 and rs2.door.enterable, "every door line is lit: the keypad wakes")

local boardPart = zone:FindFirstChild("DoorBoard", true)
local lines = {}
for i = 1, 6 do
	local g = labelText(boardPart, "RowGuess_" .. i)
	local t = labelText(boardPart, "RowText_" .. i)
	if g and g ~= "" and t and t ~= "" then
		local guess = Text.parseCodeGuess(g)
		local a, b = Text.parseCodeSentence(t)
		truthy(guess ~= nil and a ~= nil, "door board row " .. i .. " parses: " .. g .. " / " .. t)
		if guess and a then table.insert(lines, { guess = guess, a = a, b = b }) end
	end
end
local codes = CodeLock.solve(lines, rs2.door.L, rs2.door.alphabet)
eq(#codes, 1, "the lit lines on the board fit exactly one code")
hrp.CFrame = CFrame.new(origin + Vector3.new(0, 3, -12))
local noticesBefore = #R.Notice:sentTo(plr)
R.Act:simulateFireServer(plr, "Door", "enter", codes[1])
h:advance(0.5)
local escaped = nil
for i = noticesBefore + 1, #R.Notice:sentTo(plr) do
	local p = R.Notice:sentTo(plr)[i].args[1]
	if type(p) == "table" and p.kind == "escape" then escaped = p end
end
truthy(escaped ~= nil, "the right code opens the door (an escape notice)")
eq(escaped and escaped.stars, 3, "3 stars: escaped, clean, unaided")
eq(starsValue.Value, 3, "leaderstats.Stars shows 3")
eq(names.NextPanel.Enabled, true, "NEXT lights up after the escape")
local leaf = zone:FindFirstChild("DoorLeaf", true)
truthy(leaf and leaf.CanCollide == false, "the door leaf no longer blocks the doorway")

-- NEXT from the exit cab takes the lift on to room 2
checkPrompt(names.NextPanel, origin, 0, walkableRoom, "room NextPanel")
h:advance(Config.Lift.RideSeconds + 0.5)
local rs3 = lastTo(R.RoomState, plr)
eq(rs3 and rs3.slot, 2, "NEXT rode on to room 2")
-- ATRIUM from the entry cab takes the player home
local zone2 = nil
for _, z in zonesFolder:GetChildren() do
	if z:FindFirstChild("LeaveEntry", true) then zone2 = z end
end
local leave = zone2 and zone2:FindFirstChild("LeaveEntry", true)
local leavePrompt = leave and leave:FindFirstChildOfClass("ProximityPrompt")
truthy(leavePrompt ~= nil, "room 2 has its ATRIUM prompt in the entry cab")
if leavePrompt then
	local o2 = Vector3.new(rs3.origin[1], rs3.origin[2], rs3.origin[3])
	origin = o2
	checkPrompt(leavePrompt, o2 + Vector3.new(0, 0, W.RoomHalf + W.Wall + W.CabHalf), 0, walkableRoom, "room LeaveEntry")
	truthy(xzDist(hrp.Position, W.Arrival[1], W.Arrival[2]) < 0.5, "ATRIUM put the player on AtriumArrival")
	eq(lastTo(R.RoomState, plr).where, "atrium", "and told the client it is in the Atrium")
end

--============================================================ 7. the Roof's prompt
do
	local back = roof:FindFirstChild("BackDown", true)
	local bp = back and back:FindFirstChildOfClass("ProximityPrompt")
	truthy(bp ~= nil, "the Roof has its Back down prompt")
	if bp then
		checkPrompt(bp, Vector3.new(0, W.RoofY, 0), W.RoofY, function(p)
			return math.abs(p.X) <= W.RoofHalf - 1.5 and math.abs(p.Z) <= W.RoofHalf - 1.5
		end, "Roof BackDown")
		truthy(xzDist(hrp.Position, W.Arrival[1], W.Arrival[2]) < 0.5 and hrp.Position.Y < 20, "Back down brings the player to the Atrium")
	end
end

--============================================================ 8. the board renders a row once a star exists
h:advance(Config.Board.PublicCacheSeconds + 1)
local row1 = labelText(face, "Row_1")
truthy(row1 ~= nil and string.find(row1, "Ada", 1, true) ~= nil and string.find(row1, "3", 1, true) ~= nil,
	"after the refresh the public board shows Ada with 3 stars (" .. tostring(row1) .. ")")

--============================================================ 9. a respawn lands on AtriumSpawn again
local char2 = h.Players:simulateSpawn(plr, ws)
local hrp2 = char2:FindFirstChild("HumanoidRootPart")
truthy(xzDist(hrp2.Position, spawn.Position.X, spawn.Position.Z) < 0.01, "a second spawn lands on AtriumSpawn too")

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("  prompts answered: %s", table.concat(responses, ", ")))
print(string.format("escape-room-lab: %d passed, %d failed", passed, failed))
if failed > 0 then error("escape-room-lab check failed", 0) end
