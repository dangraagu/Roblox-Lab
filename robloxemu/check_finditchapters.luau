-- Find It! Chapters: the main headless gate. Run (from robloxemu/):
--   py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--   luau check_finditchapters.luau 2>&1
--
-- Boots the REAL server and walks the real player path (docs/complete-game-standard.md §1):
--   the world is BUILT and PARENTED; HubSpawn is the one enabled SpawnLocation and a joining character LANDS on it
--   under the engine's spawn order (robloxemu/SPAWN-ORDER.md); every prompt is reachable from the spawn; the board
--   exists and renders; the lectern takes a new player straight into Chapter 1; each find is made by standing next
--   to the prop and firing Search exactly as the client does; a clear saves, opens the next chapter and writes the
--   board; the Daily opens after Chapter 3 and credits once per UTC day; a rejoin keeps everything.
-- The hidden prop is read from ServerStorage.FindIt.Attempts (the server-only rig), never from anything replicated.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-chapters", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local Vector3, CFrame = dt.Vector3, dt.CFrame
assert(h:tryRun("server/Main.server"))
h:advance(0.5)

local RS, ws = h.ReplicatedStorage, h.workspace
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Ledger, Board, Clue = mod("Config"), mod("Ledger"), mod("Board"), mod("Clue")
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local DSS = h.services.DataStoreService
local remotes = RS:FindFirstChild("FindItRemotes")
local function remote(n) return remotes and remotes:FindFirstChild(n) end

local function frame(d)
	RunService.Heartbeat:Fire(d)
	h:advance(d)
end
local function run(seconds, step)
	step = step or 0.1
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(step, seconds - t)
		frame(d)
		t += d
	end
end
local function last(name, plr)
	local s = remote(name):sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function sentCount(name, plr) return #remote(name):sentTo(plr) end

--============================================================ the world: built and parented
local world = ws:FindFirstChild("FindItWorld")
truthy(world ~= nil, "workspace.FindItWorld exists")
local hub = world and world:FindFirstChild("Hub")
truthy(hub ~= nil, "the hub is built")
local hubSpawn = hub and hub:FindFirstChild("HubSpawn")
truthy(hubSpawn ~= nil and hubSpawn.ClassName == "SpawnLocation", "HubSpawn is a SpawnLocation")
eq(hubSpawn and hubSpawn.Enabled, true, "HubSpawn is enabled")
do
	local enabled = 0
	for _, d in ws:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then enabled += 1 end
	end
	eq(enabled, 1, "exactly one enabled SpawnLocation in the world")
end
local hubParts = 0
for _, d in hub:GetDescendants() do if d:IsA("BasePart") then hubParts += 1 end end
truthy(hubParts <= Config.Budget.HubParts, string.format("hub parts %d <= %d", hubParts, Config.Budget.HubParts))
local lanes = world:FindFirstChild("Lanes")
eq(lanes and #lanes:GetChildren(), Config.World.Lanes, "12 lane shells, built at start")
do
	local worst, maxX = 0, 0
	for _, lane in lanes:GetChildren() do
		local n = 0
		for _, d in lane:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
				maxX = math.max(maxX, math.abs(d.Position.X) + d.Size.X / 2)
			end
		end
		worst = math.max(worst, n)
		truthy(lane:FindFirstChild("Floor") and lane:FindFirstChild("DoorMat") and lane:FindFirstChild("Ceiling"), lane.Name .. " has a floor, a ceiling and a door mat")
	end
	truthy(worst <= Config.Budget.LaneParts, string.format("a lane shell is %d parts <= %d", worst, Config.Budget.LaneParts))
	truthy(maxX <= 412, string.format("every coordinate is bounded: |x| <= %.0f", maxX))
end
for _, n in { "Room", "State", "Result", "Hint", "Toast", "Notice", "Board", "Profile", "Open", "OpenDaily", "Search", "AskHint",
	"Pause", "Resume", "Next", "Retry", "Hub", "Hello" } do
	truthy(remote(n) ~= nil, "remote " .. n)
end
truthy(h.Lighting:FindFirstChild("FxAtmosphere") ~= nil, "the Fx preset is applied at start (Atmosphere)")
local rigFolder = ServerStorage:FindFirstChild("FindIt")
truthy(rigFolder and rigFolder:FindFirstChild("Attempts"), "the server-only rig lives in ServerStorage")

--============================================================ REVIEW-1 B2, B7, B9: facing and walls
do
	local book = hub:FindFirstChild("CaseBook")
	local look = hubSpawn.CFrame.LookVector
	local to = Vector3.new(book.Position.X - hubSpawn.Position.X, 0, book.Position.Z - hubSpawn.Position.Z).Unit
	truthy(look.X * to.X + look.Z * to.Z > 0.95, string.format("B2: HubSpawn faces the Case Book (look %.2f, %.2f, %.2f)", look.X, look.Y, look.Z))
	-- the Daily door's sign is on its Front face: that face must look into the hub, toward the spawn
	local door = hub:FindFirstChild("DailyDoor")
	local sign = door and door:FindFirstChild("Sign")
	eq(sign and sign.Face, dt.Enum.NormalId.Front, "B7: the Daily sign is drawn on the door's Front face")
	local dl = door.CFrame.LookVector
	local toSpawn = Vector3.new(hubSpawn.Position.X - door.Position.X, 0, hubSpawn.Position.Z - door.Position.Z).Unit
	truthy(dl.X * toSpawn.X + dl.Z * toSpawn.Z > 0.5, string.format("B7: the Daily door's sign faces the hub (front . to-spawn = %.2f)", dl.X * toSpawn.X + dl.Z * toSpawn.Z))
	-- a jump from the tallest thing in the hub never clears a wall
	local tallest, wallTop = 0, math.huge
	for _, d in hub:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide ~= false then
			local top = d.Position.Y + d.Size.Y / 2
			if string.sub(d.Name, 1, 7) == "HubWall" then wallTop = math.min(wallTop, top) else tallest = math.max(tallest, top) end
		end
	end
	truthy(wallTop >= tallest + Config.World.JumpHeight + 0.5, string.format("B9: hub walls (top %.1f) stand over the tallest hub part (%.1f) + a jump (%.1f)",
		wallTop, tallest, Config.World.JumpHeight))
end

--============================================================ the board exists and renders
local board = hub:FindFirstChild("CasesBoard")
truthy(board ~= nil, "the Cases Solved board is in the hub")
local face = board and board:FindFirstChild("PublicFace")
truthy(face ~= nil and face.ClassName == "SurfaceGui", "it has a SurfaceGui face")
truthy(face and face:FindFirstChild("Row_10") ~= nil, "10 public rows")
h:advance(6)
local note = face and face:FindFirstChild("Note")
truthy(note and #note.Text > 10, "an empty public board says something (" .. tostring(note and note.Text) .. ")")
do
	-- the board's front faces the spawn
	local look = board.CFrame.LookVector
	local toSpawn = (hubSpawn.Position - board.Position)
	local flat = Vector3.new(toSpawn.X, 0, toSpawn.Z).Unit
	truthy(look.X * flat.X + look.Z * flat.Z > 0.9, "the board's face points at the spawn")
	local d = (Vector3.new(board.Position.X, 0, board.Position.Z) - Vector3.new(hubSpawn.Position.X, 0, hubSpawn.Position.Z)).Magnitude
	truthy(d >= 15 and d <= 25, string.format("the board stands %.1f studs from the spawn (about 20)", d))
end

--============================================================ join: the character lands on HubSpawn
local store = DSS:GetDataStore(Config.Save.Store)
local plr = h:join("Ann", 501)
h:advance(0.5)
eq(plr.RespawnLocation, hubSpawn, "RespawnLocation = HubSpawn before the character loads")
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = dt.Enum.Material.Plastic
h:advance(0.5)
do
	local p = hrp.Position
	truthy(math.abs(p.X - hubSpawn.Position.X) < 3 and math.abs(p.Z - hubSpawn.Position.Z) < 3, string.format("the character lands on HubSpawn (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z))
	truthy(p.Y > hubSpawn.Position.Y, "above it, not inside")
end
local ls = plr:FindFirstChild("leaderstats")
truthy(ls and ls:FindFirstChild("Solved"), "leaderstats.Solved")
local prof = last("Profile", plr)
truthy(prof and prof.loaded, "the profile loaded")
eq(prof and prof.cleared, 0, "a new player has cleared nothing")
truthy(store:GetAsync("u_501") ~= nil and store:GetAsync("u_501").lock.session ~= "", "the load took the session lock")

--============================================================ every prompt is reachable from the spawn
local landing = hrp.Position
local prompts = {}
for _, d in hub:GetDescendants() do
	if d.ClassName == "ProximityPrompt" then table.insert(prompts, d) end
end
eq(#prompts, 3, "three prompts: the Case Book, the Daily door, the board")
for _, pp in prompts do
	local host = pp.Parent
	local dist = (host.Position - landing).Magnitude
	-- walk straight toward it, stopping 1 stud short of its surface: is the prompt in range there?
	local dir = Vector3.new(host.Position.X - landing.X, 0, host.Position.Z - landing.Z)
	local reach = math.max(0, dir.Magnitude - (math.max(host.Size.X, host.Size.Z) / 2 + 1.5))
	local stand = landing + dir.Unit * reach
	local inRange = (host.Position - stand).Magnitude <= pp.MaxActivationDistance
	truthy(inRange, string.format("%s: a walk of %.1f studs from the spawn brings it in range (%.1f -> %.1f <= %d)", pp.Name, reach, dist,
		(host.Position - stand).Magnitude, pp.MaxActivationDistance))
	eq(pp.HoldDuration, 0, pp.Name .. " needs no hold")
	truthy(pp.Enabled ~= false, pp.Name .. " is enabled")
end
do
	local book = hub:FindFirstChild("CaseBook")
	local d = (Vector3.new(book.Position.X, 0, book.Position.Z) - Vector3.new(landing.X, 0, landing.Z)).Magnitude
	truthy(d <= 10.5, string.format("the Case Book is %.1f studs ahead of the spawn", d))
end

--============================================================ helpers to play like a client
local function rig(uid)
	local v = ServerStorage.FindIt.Attempts:FindFirstChild(tostring(uid))
	return v and HttpService:JSONDecode(v.Value)
end
local function stateOf(p) return last("State", p) end
local function room(p) return last("Room", p) end
local function propOf(pl, id)
	for _, q in pl.props do if q.id == id then return q end end
	return nil
end
local function standAt(p, x, z)
	p.hrp.CFrame = CFrame.new(x, 3, z)
end
-- walk next to a prop: 2 studs from it, toward the room's centre line
local function standNear(p, pl, id)
	local q = propOf(pl, id)
	local o = pl.origin
	local wx, wz = o[1] + q.x, o[3] + q.z
	local cx, cz = o[1], o[3] + pl.D / 2
	local dx, dz = cx - wx, cz - wz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then len = 1 end
	standAt(p, wx + dx / len * 2, wz + dz / len * 2)
end
local function search(p, id)
	local pl = room(p.plr)
	standNear(p, pl, id)
	remote("Search"):simulateFireServer(p.plr, id)
	run(1.1)
	return last("Result", p.plr)
end
local function playRoom(p)
	local pl = room(p.plr)
	run(3.2) -- the intro card
	local r = rig(p.plr.UserId)
	local hits = 0
	for i, id in r.hidden do
		local res = search(p, id)
		if res and res.hit and res.id == id then hits += 1 end
	end
	return hits, #r.hidden
end

local A = { plr = plr, hrp = hrp, hum = hum }

--============================================================ the lectern: a new player goes straight into Chapter 1
standAt(A, 0, 11)
local roomsBefore = sentCount("Room", plr)
hub:FindFirstChild("CaseBook"):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
h:advance(0.1)
eq(sentCount("Room", plr), roomsBefore + 1, "the Case Book prompt sends Chapter 1's room")
local st = stateOf(plr)
eq(st and st.where, "room", "the player is in a room")
eq(st and st.chapter, 1, "Chapter 1")
eq(st and st.state, "intro", "on the intro card")
local pl1 = room(plr)
eq(#pl1.props, Config.Chapters[1].S, "the payload carries chapter 1's 16 props")
do
	local o = pl1.origin
	local p = hrp.Position
	truthy(math.abs(p.X - o[1]) < 3 and p.Z - o[3] > 0 and p.Z - o[3] < 4, string.format("moved onto the lane's door mat (%.1f, %.1f)", p.X - o[1], p.Z - o[3]))
	local lane = nil
	for _, l in lanes:GetChildren() do
		local mat = l:FindFirstChild("DoorMat")
		if math.abs(mat.Position.X - p.X) < 4 then lane = l end
	end
	local floor = lane and lane:FindFirstChild("Floor")
	truthy(floor and floor.Parent ~= nil and p.Y > floor.Position.Y + floor.Size.Y / 2, "the lane's floor is built and under the player")
end
local r1 = rig(501)
truthy(r1 and #r1.hidden == 3, "the server-only rig holds 3 hidden ids")
-- a search during the intro card is refused, with words
do
	local toasts = sentCount("Toast", plr)
	remote("Search"):simulateFireServer(plr, pl1.props[1].id)
	h:advance(0.05)
	eq(sentCount("Toast", plr), toasts + 1, "a search during the intro is answered")
	eq(last("Toast", plr).text, Config.Text.GetReady, "... 'Get ready...'")
end
run(3.2)
eq(stateOf(plr).state, "live", "the clock started after the 3 s intro")
-- chapter 1: clue 1's candidates take the slots of their height band nearest the door (the first find is in view)
do
	local r = rig(501)
	local isC1 = {}
	for _, id in r.cands[1] do isC1[id] = true end
	local ok = 0
	for _, id in r.cands[1] do
		local q = propOf(pl1, id)
		local d = math.sqrt(q.x * q.x + q.z * q.z)
		local nearer = 0
		for _, o in pl1.props do
			if o.height == q.height and not isC1[o.id] and math.sqrt(o.x * o.x + o.z * o.z) < d - 1e-9 then nearer += 1 end
		end
		if nearer == 0 then ok += 1 end
	end
	eq(ok, 3, "chapter 1: no other prop of the same height band is nearer the door than clue 1's candidates")
end
-- a miss, then an off-clue search, then the finds
do
	local r = rig(501)
	local missId = nil
	for _, id in r.cands[1] do if id ~= r.hidden[1] then missId = id end end
	local looks0 = stateOf(plr).looks
	local res = search(A, missId)
	truthy(res and res.id == missId and res.hit == false, "a candidate that hides nothing: a miss")
	eq(stateOf(plr).looks, looks0 - 1, "a search spends one look")
	local again = sentCount("Toast", plr)
	remote("Search"):simulateFireServer(plr, missId)
	h:advance(0.05)
	eq(last("Toast", plr).text, Config.Text.Already, "searching it again: 'Already searched'")
	eq(stateOf(plr).looks, looks0 - 1, "free")
	-- out of reach: stand at the door, search the farthest prop
	local far, fd = nil, 0
	for _, q in pl1.props do
		local d = math.sqrt(q.x * q.x + q.z * q.z)
		if d > fd then far, fd = q, d end
	end
	standAt(A, pl1.origin[1], pl1.origin[3] + 1.5)
	remote("Search"):simulateFireServer(plr, far.id)
	h:advance(0.05)
	eq(last("Toast", plr).text, Config.Text.WalkCloser, string.format("a prop %.1f studs away is out of reach: 'Walk closer'", fd))
end
local firstFindAt = nil
do
	local r = rig(501)
	for i, id in r.hidden do
		local res = search(A, id)
		truthy(res and res.hit and res.item == i, "item " .. i .. " found by searching its prop")
	end
	run(0.2)
	st = stateOf(plr)
	eq(st.state, "done", "every item found: the room is done")
	eq(st.result and st.result.reason, "found", "reason: found")
	truthy(st.result and st.result.stars and st.result.stars.f, "the Found star")
	run(7) -- the clear waits for the 6 s write gap, then lands
	st = stateOf(plr)
	eq(st.result.saving, false, "the clear saved")
	eq(st.result.first, true, "a first clear")
	eq(st.result.solved, 1, "Cases Solved 1")
	eq(last("Profile", plr).cleared, 1, "the profile says chapter 1 cleared")
	eq(ls.Solved.Value, 1, "leaderstats.Solved = 1")
	local rec = store:GetAsync("u_501")
	eq(rec.data.book.cleared, 1, "the store holds chapter 1 cleared (written inside the atomic clear)")
	eq(rec.data.book.stars.c1.f, true, "stars under the string key c1")
end

--============================================================ Next: chapters 2 and 3
for ch = 2, 3 do
	remote("Next"):simulateFireServer(plr)
	h:advance(0.1)
	st = stateOf(plr)
	eq(st.chapter, ch, "Next opens chapter " .. ch)
	local hits, n = playRoom(A)
	eq(hits, n, string.format("chapter %d: %d of %d found", ch, hits, n))
	run(7.2)
	st = stateOf(plr)
	eq(st.result and st.result.first, true, "chapter " .. ch .. " is a first clear")
	if ch == 3 then
		eq(st.progress, 4, "clearing chapter 3 moves the room's progress to band 2 (the glide reward)")
	end
	run(1.1)
end
eq(last("Profile", plr).cleared, 3, "three chapters cleared")
eq(last("Profile", plr).dailyOpen, true, "the Daily opens after Chapter 3")
eq(ls.Solved.Value, 3, "Cases Solved 3")

--============================================================ the Daily Case
remote("Hub"):simulateFireServer(plr)
h:advance(0.1)
eq(stateOf(plr).where, "hub", "Hub returns the player to the hub")
truthy((hrp.Position - hubSpawn.Position).Magnitude < 6, "and moves them there")
local door = hub:FindFirstChild("DailyDoor")
standAt(A, door.Position.X - 4, door.Position.Z)
h:advance(1.1)
door:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
h:advance(0.1)
st = stateOf(plr)
eq(st.kind, "daily", "the Daily door opens a Daily Case")
local today = Ledger.dayIndex(os.time())
eq(st.day, today, "today's case (dayIndex " .. today .. ")")
eq(st.case, Ledger.caseNumber(today, Config), "Case #" .. Ledger.caseNumber(today, Config))
do
	local hits, n = playRoom(A)
	eq(hits, n, string.format("the Daily: %d of %d found", hits, n))
	run(7.2)
	st = stateOf(plr)
	eq(st.result.credited, true, "the first Daily solve today is credited")
	eq(st.result.solved, 4, "Cases Solved 4 (3 chapters + 1 Daily)")
	local rec = store:GetAsync("u_501")
	eq(rec.data.daily.lastDay, today, "the store records today's credit")
	eq(rec.data.daily.solved, 1, "Daily solved 1")
	-- a second solve the same day credits nothing
	run(1.1)
	remote("Retry"):simulateFireServer(plr)
	h:advance(0.1)
	local hits2, n2 = playRoom(A)
	eq(hits2, n2, "a second Daily the same day can be played")
	run(7.2)
	st = stateOf(plr)
	eq(st.result.credited, false, "... and credits nothing")
	eq(store:GetAsync("u_501").data.solved, 4, "Cases Solved stays 4")
end

--============================================================ the board: written after the profile, shown in the hub
do
	local lb = DSS:GetOrderedDataStore(Config.Board.Store)
	local v = lb:GetAsync("u_501")
	eq(Board.metricOf(v), 4, "the board holds Ann's 4 Cases Solved")
	h:advance(61)
	local row1 = face:FindFirstChild("Row_1")
	truthy(row1 and string.find(row1.Text, "Ann", 1, true) and string.find(row1.Text, "4", 1, true), "the public face shows '1. Ann 4' (" .. tostring(row1 and row1.Text) .. ")")
end

--============================================================ a death in a room ends the attempt; the engine respawns on HubSpawn
do
	remotes = RS:FindFirstChild("FindItRemotes")
	remote("Hub"):simulateFireServer(plr)
	run(1.2)
	remote("Open"):simulateFireServer(plr, 4)
	h:advance(0.1)
	eq(stateOf(plr).chapter, 4, "chapter 4 is open")
	local laneMat = nil
	local o = room(plr).origin
	hum:TakeDamage(100)
	h:advance(0.1)
	eq(stateOf(plr).where, "hub", "a death in a room ends the attempt (nothing of it was ever saved)")
	eq(ServerStorage.FindIt.Attempts:FindFirstChild("501"), nil, "and the server-only rig is cleared")
	local c3 = h.Players:simulateSpawn(plr, ws)
	h:advance(0.5)
	local p = c3:FindFirstChild("HumanoidRootPart").Position
	truthy(math.abs(p.X - hubSpawn.Position.X) < 3 and math.abs(p.Z - hubSpawn.Position.Z) < 3,
		string.format("the respawn lands on HubSpawn (%.1f, %.1f), not in the lane", p.X, p.Z))
	hrp = c3:FindFirstChild("HumanoidRootPart")
	hum = c3:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = dt.Enum.Material.Plastic
	A.hrp, A.hum = hrp, hum
end

--============================================================ the Studio shot room never runs in a live server
do
	Config.Studio.ShotSeed = 4242 -- the same table the server reads; RunService:IsStudio() is false here
	Config.Studio.Cleared = 14
	local function openOnce()
		remote("Hub"):simulateFireServer(plr)
		run(1.2)
		remote("Open"):simulateFireServer(plr, 2)
		h:advance(0.1)
		local pl = room(plr)
		local sig = {}
		for _, q in pl.props do table.insert(sig, q.kind .. q.colour .. string.format("%.2f", q.x)) end
		return table.concat(sig, ",")
	end
	local a1, a2 = openOnce(), openOnce()
	truthy(a1 ~= a2, "with a ShotSeed set, a live server still deals every room from server entropy")
	local probe = h:join("Probe", 515)
	h:advance(1)
	local pp = last("Profile", probe)
	eq(pp and pp.cleared, 0, "with Studio.Cleared set, a live server unlocks nothing for a new player")
	h:leave(probe)
	h:advance(1)
	Config.Studio.ShotSeed = nil
	Config.Studio.Cleared = nil
	remote("Hub"):simulateFireServer(plr)
	run(1.2)
end

--============================================================ rejoin keeps everything; the lock was released
remote("Hub"):simulateFireServer(plr)
run(1.1)
h:leave(plr)
h:advance(2)
eq(store:GetAsync("u_501").lock.session, "", "leaving releases the lock (session '')")
local plr2 = h:join("Ann", 501)
h:advance(1)
local char2 = h.Players:simulateSpawn(plr2, ws)
h:advance(1)
local p2 = last("Profile", plr2)
eq(p2 and p2.cleared, 3, "rejoin: 3 chapters cleared")
eq(p2 and p2.solved, 4, "rejoin: Cases Solved 4")
eq(p2 and p2.dailySolvedToday, true, "rejoin: today's Daily is solved")
eq(p2 and p2.canSave, true, "rejoin: this session can save")
eq(p2 and p2.continue, 4, "rejoin: Continue is Chapter 4")
do
	local p = char2:FindFirstChild("HumanoidRootPart").Position
	truthy(math.abs(p.X - hubSpawn.Position.X) < 3 and math.abs(p.Z - hubSpawn.Position.Z) < 3, "the rejoined character lands on HubSpawn too")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it chapters: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters failed", 0) end
