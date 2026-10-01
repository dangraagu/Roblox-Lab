-- The Same Door — boot the REAL server, ask the workspace, and walk the player's path.
-- Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--       luau check_samedoor.luau 2>&1
--
-- ALWAYS re-run wrap.py first: this reads build/same-door.luau, not the game's src/.
--
-- Why: this repo once shipped 166 green unit tests with an unreachable core loop (Grow a Crystal's
-- socket Part was never parented). So this file asks the workspace, not the modules:
--   A. every source compiles (rojo build does not compile Luau);
--   B. the world is BUILT and PARENTED: the hub, the one enabled SpawnLocation, the arch, the board,
--      the campfire; the server-only day copy exists in ServerStorage and nowhere replicated;
--   C. a joining character LANDS on HubSpawn under the engine's spawn order (SPAWN-ORDER.md);
--   D. every prompt is REACHABLE by walking from the spawn (the arch, the board), and the core action
--      happens within ~5 s of spawning;
--   E. one full loop, walked: the arch, the antechamber, the line, 3 seals, the Door. The time is
--      within a frame of path / speed, the profile and the board are written, the board RENDERS;
--   F. Run again: a faster run improves the best and the board; a slower one changes neither;
--   G. rejoin keeps the best and the streak; the friends board works and an empty one says so.
-- The walker reads the day from ServerStorage.SameDoor.Day and uses the game's own Dungeon module
-- only to ADDRESS the route (where the perfect line goes); every count and time asserted is either
-- written out or derived from geometry, never recomputed by the code under test.

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")

--============================================================ A. every source compiles
local compiled, compileFailed = 0, 0
do
	local keys = {}
	for k in bundle do table.insert(keys, k) end
	table.sort(keys)
	for _, k in keys do
		local e = bundle[k]
		local fn, err = loadstring(e.source, "@" .. e.path)
		if fn then compiled += 1 else compileFailed += 1; print("FAIL: " .. k .. " does not compile: " .. tostring(err)) end
	end
end

local h = Harness.new({ bundle = bundle, name = "same-door", viewport = { 1280, 720 }, touch = false })

-- Rojo puts src/server/*.luau (not .server) into ServerScriptService as ModuleScripts; the harness
-- models only src/shared. Register them exactly as check_lostfounddepot.luau does, nothing more.
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end

-- Pin the server's entropy so a failure can be replayed: unseeded Randoms become seeded ones.
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(20261001 + unseeded * 7919)
		end
		return realRandom.new(seed)
	end,
}

-- The emulator has no Players:GetFriendsAsync. A stub with Roblox's page shape: friends of ME are
-- FRIEND (who has a time today) and SILENT (who does not). Everyone else has no friends.
local ME, FRIEND, SILENT, LONER = 7001, 7002, 7003, 7004
local friendsOf = { [ME] = { FRIEND, SILENT } }
h.Players.GetFriendsAsync = function(_self, uid)
	local list = {}
	for _, id in friendsOf[uid] or {} do table.insert(list, { Id = id, Username = "U" .. id, DisplayName = "U" .. id, IsOnline = false }) end
	return {
		IsFinished = true,
		GetCurrentPage = function() return list end,
		AdvanceToNextPageAsync = function() end,
	}
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
eq(compileFailed, 0, "every source in the bundle compiles (" .. compiled .. " sources)")
truthy(compiled >= 23, "the bundle holds all 23 sources")

local HB = h.services.RunService.Heartbeat
local FRAME = 1 / 60
local function step(dt)
	h:advance(dt)
	HB:Fire(dt)
end

--============================================================ boot
assert(h:tryRun("server/Main.server"))
h:advance(1)

local ws = h.workspace
local RS = h.services.ReplicatedStorage
local SS = h.game:GetService("ServerStorage")
local remotes = RS:FindFirstChild("SameDoorRemotes")
truthy(remotes ~= nil, "the server published SameDoorRemotes")
local R = {}
for _, n in { "Cell", "Run", "Board", "Toast", "DayInfo", "Leave", "RunAgain", "GoHub" } do
	R[n] = remotes and remotes:FindFirstChild(n)
	truthy(R[n] ~= nil, "remote " .. n .. " exists")
end

--============================================================ B. the world is built and parented
local hub = ws:FindFirstChild("Hub")
truthy(hub ~= nil and hub.Parent == ws, "workspace.Hub is built and parented")
local spawns = {}
for _, d in ws:GetDescendants() do
	if d.ClassName == "SpawnLocation" and d.Enabled ~= false then table.insert(spawns, d) end
end
eq(#spawns, 1, "exactly one enabled SpawnLocation in the world")
local hubSpawn = hub and hub:FindFirstChild("HubSpawn")
eq(spawns[1], hubSpawn, "…and it is HubSpawn")
local arch = hub and hub:FindFirstChild("Arch")
local doorway = arch and arch:FindFirstChild("Doorway")
local archPrompt = doorway and doorway:FindFirstChild("EnterPrompt")
truthy(archPrompt ~= nil and archPrompt.ClassName == "ProximityPrompt", "the arch carries its ProximityPrompt")
eq(archPrompt and archPrompt.ActionText, "Enter Today's Door", "…named Enter Today's Door")
eq(archPrompt and archPrompt.HoldDuration, 0, "…with no hold")
local boardPart = hub and hub:FindFirstChild("DoorBoard")
local boardPrompt = boardPart and boardPart:FindFirstChild("TogglePrompt")
truthy(boardPart ~= nil and boardPart.Parent == hub, "the board Part stands in the hub")
truthy(boardPrompt ~= nil, "…with its Public/Friends prompt")
truthy(hub and hub:FindFirstChild("YesterdayPlaque") ~= nil, "the yesterday plaque stands beside it")
local camp = hub and hub:FindFirstChild("Campfire")
truthy(camp ~= nil and camp:FindFirstChild("Fire") ~= nil, "the campfire is built")
local lanes = ws:FindFirstChild("Lanes")
truthy(lanes ~= nil and lanes.Parent == ws, "workspace.Lanes exists")
eq(lanes and #lanes:GetChildren(), 0, "no lane is built before anyone enters")

-- the day: minted, stored, and held server-only
local dayCopy = SS:FindFirstChild("SameDoor") and SS.SameDoor:FindFirstChild("Day")
truthy(dayCopy ~= nil and #dayCopy.Value > 100, "the day record's server-only copy is in ServerStorage.SameDoor.Day")
local HttpService = h.game:GetService("HttpService")
local rec = HttpService:JSONDecode(dayCopy.Value)
local Dungeon = h:_require(h.services.ServerScriptService:FindFirstChild("Dungeon"))
local Config = h:_require(RS:FindFirstChild("Config"))
local dayIndex = math.floor(os.time() / 86400)
truthy((Dungeon.validate(Config, rec, dayIndex)), "the stored record validates for today (day " .. dayIndex .. ")")
local stored = h.services.DataStoreService:GetDataStore(Config.Day.StoreName):GetAsync("d_" .. dayIndex)
eq(stored and stored.open, rec.open, "the Days store holds the same record under d_<day>")
do
	-- nothing replicated carries 8 characters of the passage string
	local probe = string.sub(rec.open, 5, 16)
	local leaks = 0
	for _, container in { ws, RS } do
		for _, d in container:GetDescendants() do
			for _, prop in { "Value", "Text", "Name" } do
				local ok, v = pcall(function() return d[prop] end)
				if ok and type(v) == "string" and string.find(v, probe, 1, true) then leaks += 1 end
			end
			for _, v in d:GetAttributes() do
				if type(v) == "string" and string.find(v, probe, 1, true) then leaks += 1 end
			end
		end
	end
	eq(leaks, 0, "no replicated value, text, name or attribute holds the day's passage string")
end

--============================================================ C. joining lands on HubSpawn
local me = h:join("Walker", ME)
h:advance(0.5)
eq(me.RespawnLocation, hubSpawn, "PlayerAdded points RespawnLocation at HubSpawn before the character loads")
for _, key in { "client/Hud.client", "client/Dungeon.client", "client/Board.client" } do
	local ok, err = h:tryRun(key)
	truthy(ok, key .. " loads (" .. tostring(err) .. ")")
end
h:advance(0.5)
local char = h.Players:simulateSpawn(me, ws)
h:advance(0.1)
local hrp = char:FindFirstChild("HumanoidRootPart")
do
	local p = hrp.Position
	local s = hubSpawn.Position
	truthy(math.abs(p.X - s.X) < 0.01 and math.abs(p.Z - s.Z) < 0.01, string.format("the character lands on HubSpawn (%.1f, %.1f)", p.X, p.Z))
	truthy(p.Y > s.Y, "…above it, not inside it")
	eq(char.Parent, ws, "…parented to the workspace")
end
do
	-- the HUD loaded AFTER the server's DayInfo went out; it must still know the Door (the facts are
	-- attributes on the remotes folder too) and tell a new player the first thing to do
	step(FRAME)
	local hud = me.PlayerGui:FindFirstChild("SameDoorHud")
	local chip = hud and hud.Root.DayChip.Text.Text
	truthy(chip and string.find(chip, "Door #" .. (dayIndex - 20725), 1, true) ~= nil, "the day chip shows today's Door (" .. tostring(chip) .. ")")
	eq(hud and hud.Root.HintBar.Text.Text, "Walk to the glowing arch and press E (tap ENTER)", "the first hint names the action and the key")
	eq(hud and hud.Root.HintBar.Visible, true, "…and is on screen")
end
local ls = me:FindFirstChild("leaderstats")
truthy(ls ~= nil and ls:FindFirstChild("Best") ~= nil and ls:FindFirstChild("Streak") ~= nil, "leaderstats Best and Streak exist")

-- recorders
local runMsgs, toasts, cellsSent = {}, {}, {}
R.Run.OnClientEvent:Connect(function(p) table.insert(runMsgs, p) end)
R.Toast.OnClientEvent:Connect(function(m) table.insert(toasts, m) end)
R.Cell.OnClientEvent:Connect(function(p) for _, c in p.cells do table.insert(cellsSent, c) end end)
local function lastRun() return runMsgs[#runMsgs] end

--============================================================ D. prompts are reachable by walking
local function setRoot(x, y, z)
	hrp.CFrame = CFrame.new(x, y, z)
end
-- walk in a straight line at `speed` until `stop(pos)` is true or `limit` seconds pass; returns seconds
local function walkTo(tx, tz, speed, stop, limit)
	local t = 0
	while t < (limit or 30) do
		local p = hrp.Position
		if stop and stop(p) then return t end
		local dx, dz = tx - p.X, tz - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 0.01 then return t end
		local s = math.min(speed * FRAME, d)
		setRoot(p.X + dx / d * s, p.Y, p.Z + dz / d * s)
		step(FRAME)
		t += FRAME
	end
	return t
end
local function within(prompt)
	return function(p)
		local pp = prompt.Parent.Position
		return (p - pp).Magnitude <= prompt.MaxActivationDistance
	end
end
do
	local startDist = (hrp.Position - doorway.Position).Magnitude
	truthy(startDist > archPrompt.MaxActivationDistance, string.format("the arch is %.1f studs away: a few steps, not in your face", startDist))
	local t = walkTo(0, 20, 16, within(archPrompt), 5)
	truthy(within(archPrompt)(hrp.Position), string.format("walking north reaches the arch prompt after %.2f s", t))
	truthy(t <= 5, "the core action is reachable within 5 s of spawning")
	print(string.format("  spawn -> arch prompt in range: %.2f s of walking", t))
end

--============================================================ E. one full loop, walked
local function reachArch()
	walkTo(0, 12, 16, within(archPrompt), 10)
	archPrompt.Triggered:Fire(me)
	h:advance(0.05)
end
reachArch()
local ready = lastRun()
eq(ready and ready.state, "ready", "the arch starts a run (Run payload 'ready')")
local lane1 = lanes:FindFirstChild("Lane_1")
truthy(lane1 ~= nil and lane1.Parent == lanes, "the first lane is built and parented")
do
	local n = 0
	for _, d in lane1:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	-- 7 perimeter pieces + floor/ceiling, 5 antechamber pieces, the start line, 8 in the Sanctum + its 4 rails
	eq(n, 25, "the lane shell is 25 server Parts (identical every day)")
	truthy(lane1:FindFirstChild("AnteFloor") ~= nil, "…with the antechamber floor, built before the move")
	-- The Dawn Sanctum is an open-air balcony over nothing: every finish lands there, and a player
	-- reading the card must not be able to walk (or jump) off the edge into the void. Walk out from its
	-- centre in 16 directions at root height (3) and at the top of a jump (3 + 7.2): every ray must hit
	-- a collidable part before it leaves the floor.
	local sanct = lane1:FindFirstChild("Sanctum")
	local floor = sanct and sanct:FindFirstChild("SanctumFloor")
	truthy(floor ~= nil, "the Sanctum has a floor")
	if floor then
		local solid = {}
		for _, d in lane1:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide ~= false and d ~= floor then table.insert(solid, d) end
		end
		local function blocked(p)
			for _, s in solid do
				local c, sz = s.Position, s.Size
				if math.abs(p.X - c.X) <= sz.X / 2 and math.abs(p.Y - c.Y) <= sz.Y / 2 and math.abs(p.Z - c.Z) <= sz.Z / 2 then return true end
			end
			return false
		end
		local fc, fs = floor.Position, floor.Size
		local open = 0
		for k = 0, 15 do
			local a = k / 16 * 2 * math.pi
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			for _, hgt in { 3, 3 + 7.2 } do
				local hit = false
				for r = 0, 40, 0.25 do
					local p = Vector3.new(fc.X, fc.Y + fs.Y / 2 + hgt, fc.Z) + dir * r
					if blocked(p) then hit = true; break end
					if math.abs(p.X - fc.X) > fs.X / 2 or math.abs(p.Z - fc.Z) > fs.Z / 2 then break end
				end
				if not hit then open += 1 end
			end
		end
		eq(open, 0, "the Dawn Sanctum is fenced: no walk or jump from its centre leaves the floor (32 rays)")
	end
end
local origin = Vector3.new(ready.origin.x, ready.origin.y, ready.origin.z)
eq(origin.X, 0, "lane 1 sits at x = 0"); eq(origin.Z, 1000, "…and z = +1000")
do
	local p = hrp.Position - origin
	truthy(math.abs(p.X - 72) < 0.01 and math.abs(p.Z + 8) < 0.01, string.format("the character stands in the antechamber (%.1f, %.1f)", p.X, p.Z))
end
do
	-- the first batch: the entrance and the cells one open step beyond it, read off the entrance's own
	-- payload (its open sides, minus the south opening onto the line), not recomputed by the game
	local ent = nil
	for _, c in cellsSent do if c.x == rec.entrance.x and c.y == rec.entrance.y then ent = c end end
	truthy(ent ~= nil, "the first Cell batch arrives with the move and holds the entrance")
	local open = 0
	for _, bit in { 1, 2, 8 } do if ent and bit32.band(ent.sides, bit) ~= 0 then open += 1 end end
	eq(#cellsSent, 1 + open, string.format("…and exactly the entrance plus its %d open neighbours, nothing further", open))
end

local world = Dungeon.fromRecord(Config, rec)
local pathLen, path = Dungeon.perfectPath(Config, world)
local function walkPath(speed)
	local pts = { { x = 72, z = -8 } }
	for _, p in path do table.insert(pts, p) end
	local seg, t = 1, 0
	local x, z = 72, -8
	local finished = nil
	local startCount = #runMsgs
	while seg < #pts and t < 200 do
		local remaining = speed * FRAME
		while remaining > 0 and seg < #pts do
			local b = pts[seg + 1]
			local dx, dz = b.x - x, b.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then
				x, z = b.x, b.z
				remaining -= d
				seg += 1
			else
				x += dx / d * remaining
				z += dz / d * remaining
				remaining = 0
			end
		end
		setRoot(origin.X + x, origin.Y + 3, origin.Z + z)
		step(FRAME)
		t += FRAME
		for i = startCount + 1, #runMsgs do
			if runMsgs[i].state == "finished" or runMsgs[i].state == "void" then finished = runMsgs[i] end
		end
		if finished then break end
	end
	-- a couple of frames for the finish to land
	for _ = 1, 3 do step(FRAME) end
	for i = startCount + 1, #runMsgs do
		if runMsgs[i].state == "finished" or runMsgs[i].state == "void" then finished = runMsgs[i] end
	end
	return finished, t
end

local sealToasts0 = #toasts
-- loop 1 at 13 studs/s: 16/13 = 1.23 P, Gold, so loop 2 at 16 is the FIRST Sealer (the brag)
local fin1, walked1 = walkPath(13)
truthy(fin1 ~= nil and fin1.state == "finished", "loop 1 (walked at 13 studs/s) finishes (" .. tostring(fin1 and fin1.state) .. " " .. tostring(fin1 and fin1.reason) .. ")")
eq(fin1 and fin1.medal, "Gold", "loop 1 at 13 studs/s (1.23 P) is Gold")
-- P ends ON the Door's pickup circle, where the clock stops (REVIEW-1): the time is path / 14, plus
-- at most the frame in which this walker stops dead on the line's last point
local expect1 = pathLen / 13 * 1000
truthy(fin1 and fin1.timeMs >= expect1 - 1 and fin1.timeMs <= expect1 + 1000 / 60 + 1,
	string.format("loop 1 time %s ms is within a frame of path / 13 = %.0f ms", tostring(fin1 and fin1.timeMs), expect1))
do
	local seals = 0
	for i = sealToasts0 + 1, #toasts do if string.find(toasts[i], "/3 Seals") then seals += 1 end end
	eq(seals, 3, "three seal toasts on the way")
end
local medal1 = fin1 and fin1.medal
print(string.format("  loop 1: %.2f s walked, official %s, medal %s, P %.2f s, path %.1f studs", walked1, tostring(fin1 and fin1.timeMs), tostring(medal1), rec.perfectMs / 1000, pathLen))
do
	local p = hrp.Position - origin
	truthy(p.Z > 144, string.format("the finish moves the character to the Dawn Sanctum (z %.0f, north of the grid)", p.Z))
end
-- the profile and the board
local playerStore = h.services.DataStoreService:GetDataStore("SameDoor_Players_v1")
local prof = playerStore:GetAsync("u_" .. ME)
eq(prof and prof.data and prof.data.today and prof.data.today.bestMs, fin1 and fin1.timeMs, "the profile holds today's best")
eq(prof and prof.data and prof.data.life and prof.data.life.doors, 1, "…and one Door day")
eq(prof and prof.data and prof.data.life and prof.data.life.streak, 1, "…and a streak of 1")
local boardStore = h.services.DataStoreService:GetOrderedDataStore("SameDoor_Board_v1", "d" .. dayIndex)
local v1 = boardStore:GetAsync("u_" .. ME)
local Board = h:_require(RS:FindFirstChild("Board"))
eq(v1 and (Board.decode(v1, Config.Board)), fin1 and fin1.timeMs, "the board holds the verified time under u_<userId>")
eq(me.leaderstats.Best.Value, fin1 and h:_require(RS:FindFirstChild("Medals")).formatTime(fin1.timeMs), "leaderstats Best shows today's time")

--============================================================ F. Run again
local runsBefore = #runMsgs
R.RunAgain:simulateFireServer(me)
h:advance(0.05)
local again = nil
for i = runsBefore + 1, #runMsgs do if runMsgs[i].state == "ready" then again = runMsgs[i] end end
truthy(again ~= nil, "Run again starts a new run on the same layout")
truthy(again and again.run ~= ready.run, "…with a new run id (a fresh clock)")
do
	local p = hrp.Position - origin
	truthy(math.abs(p.X - 72) < 0.01 and math.abs(p.Z + 8) < 0.01, "…back in the antechamber")
end
h:advance(1.1) -- the one-per-second remote limit
local fin2 = walkPath(16)
truthy(fin2 ~= nil and fin2.state == "finished", "loop 2 (at 16 studs/s) finishes")
truthy(fin2 and fin1 and fin2.timeMs < fin1.timeMs, string.format("loop 2 is faster: %s ms vs %s ms", tostring(fin2 and fin2.timeMs), tostring(fin1 and fin1.timeMs)))
eq(fin2 and fin2.improved, true, "…and is reported as a new best")
eq(fin2 and fin2.medal, "Sealer", "loop 2 on the published line at 16 studs/s is Sealer")
if fin2 and fin2.medal == "Sealer" then
	eq(fin2.brag, true, "the first Sealer ever is THE brag moment")
	local hud = me.PlayerGui:FindFirstChild("SameDoorHud")
	local cardTitle = hud and hud.Root.Card.Title.Text
	eq(cardTitle, "THE DOOR IS SEALED", "…and the finish card says THE DOOR IS SEALED")
end
local v2 = boardStore:GetAsync("u_" .. ME)
eq(v2 and (Board.decode(v2, Config.Board)), fin2 and fin2.timeMs, "the board took the faster time")
print(string.format("  loop 2: official %s ms, medal %s (Sealer needs <= %s ms)", tostring(fin2 and fin2.timeMs), tostring(fin2 and fin2.medal),
	tostring(h:_require(RS:FindFirstChild("Medals")).thresholdMs(rec.perfectMs, "Sealer", Config))))
-- a slower third run changes neither
h:advance(1.1)
R.RunAgain:simulateFireServer(me)
h:advance(1.1)
local fin3 = walkPath(12)
truthy(fin3 ~= nil and fin3.state == "finished", "loop 3 (slower) finishes")
eq(fin3 and fin3.improved, false, "…and is not a new best")
eq(boardStore:GetAsync("u_" .. ME), v2, "the board keeps the better time (writes only improve)")
eq(playerStore:GetAsync("u_" .. ME).data.life.doors, 1, "three finishes on one day are still one Door day")

--============================================================ the board renders
h:advance(61) -- the public cache refreshes
do
	local view = boardPart:FindFirstChild("BoardView")
	truthy(view ~= nil, "the client drew a SurfaceGui on the board Part")
	local row1 = view and view:FindFirstChild("Row1")
	local row1Text = if row1 then string.format("%s %s %s %s", row1.Rank.Text, row1.Who.Text, row1.Time.Text, row1.Medal.Text) else nil
	truthy(row1 ~= nil and string.find(row1.Who.Text, "Walker", 1, true) ~= nil, "row 1 shows the walker's name (" .. tostring(row1Text) .. ")")
	eq(row1 and row1.Time.Text, h:_require(RS:FindFirstChild("Medals")).formatTime(fin2.timeMs), "…and the best time in hundredths")
	eq(row1 and row1.Medal.Text, "SEALED", "…and the Sealer run carries the SEALED plate")
	eq(row1 and row1.Plate.Visible, true, "…drawn as a plate")
	truthy(view and view:FindFirstChild("Title") and string.find(view.Title.Text, "Door #", 1, true) ~= nil, "the board is titled with the Door number")
end

-- every label on the board and on the plaque stays on its Part, and every label whose text varies
-- shrinks to fit (TextScaled, capped by a UITextSizeConstraint) or truncates (REVIEW-1, reviewer 2,
-- finding 2): a SurfaceGui clips to its canvas, and the first build's footer straddled the board's
-- bottom edge (450..510 px on a 480 px canvas), so the empty-friends message lost its useful half,
-- and the sub-line and SEALED rows ran off the right edge. How big the text then renders is a
-- needs-Studio item (EYECANDY §7); the font-width measurement is design/measure/boardtext.py.
do
	local function audit(part, viewName)
		local view = part:FindFirstChild(viewName)
		if view == nil then return -1, -1, 0 end
		local W, H = part.Size.X * view.PixelsPerStud, part.Size.Y * view.PixelsPerStud
		local outside, unguarded, labels = 0, 0, 0
		local function walk(inst, ox, oy, pw, ph)
			for _, g in inst:GetChildren() do
				if g:IsA("GuiObject") then
					local x = ox + g.Position.X.Scale * pw + g.Position.X.Offset
					local y = oy + g.Position.Y.Scale * ph + g.Position.Y.Offset
					local w = g.Size.X.Scale * pw + g.Size.X.Offset
					local hh = g.Size.Y.Scale * ph + g.Size.Y.Offset
					if x < -0.5 or y < -0.5 or x + w > W + 0.5 or y + hh > H + 0.5 then
						outside += 1
						print(string.format("    %s.%s at (%.0f, %.0f) size (%.0f, %.0f) leaves the %.0f x %.0f canvas", viewName, g.Name, x, y, w, hh, W, H))
					end
					if g:IsA("TextLabel") then
						labels += 1
						local cap = g:FindFirstChildOfClass("UITextSizeConstraint")
						local scaled = g.TextScaled == true and cap ~= nil
						local truncated = g.TextTruncate == Enum.TextTruncate.AtEnd and g.TextScaled ~= true and g.TextWrapped ~= true
						if not scaled and not truncated then
							unguarded += 1
							print(string.format("    %s.%s neither shrinks nor truncates", viewName, g.Name))
						end
					end
					walk(g, x, y, w, hh)
				end
			end
		end
		walk(view, 0, 0, W, H)
		return outside, unguarded, labels
	end
	local bo, bu, bl = audit(boardPart, "BoardView")
	eq(bo, 0, "every board label lies on the 12 x 12-stud board")
	eq(bu, 0, string.format("…and each of its %d labels shrinks or truncates to fit", bl))
	local plaque = ws.Hub:FindFirstChild("YesterdayPlaque")
	local po, pu, pl = audit(plaque, "PlaqueView")
	eq(po, 0, "every plaque label lies on the plaque")
	eq(pu, 0, string.format("…and each of its %d labels shrinks or truncates to fit", pl))
	local foot = boardPart.BoardView:FindFirstChild("Foot")
	truthy(foot and foot.TextWrapped == true and foot.TextScaled == true, "the board's footer wraps and shrinks (the empty-board messages)")
end

--============================================================ G. friends, empty friends, rejoin
-- FRIEND has a time today; write it the way the server would (an encoded value).
boardStore:SetAsync("u_" .. FRIEND, Board.encode(40000, os.time() - 100, Config.Board))
h.Players:GetNameFromUserIdAsync(FRIEND) -- warm nothing; names resolve on demand

R.GoHub:simulateFireServer(me)
h:advance(0.1)
do
	local t = walkTo(boardPart.Position.X, boardPart.Position.Z - 6, 16, within(boardPrompt), 10)
	truthy(within(boardPrompt)(hrp.Position), string.format("the board prompt is reachable on foot (%.2f s from the hub spawn)", t))
end
local boardMsgs = {}
R.Board.OnClientEvent:Connect(function(p) table.insert(boardMsgs, p) end)
boardPrompt.Triggered:Fire(me)
h:advance(0.5)
local friendsRows = nil
for _, m in boardMsgs do if m.mode == "friends" and not m.loading then friendsRows = m end end
truthy(friendsRows ~= nil, "toggling the board sends a friends view")
eq(friendsRows and #friendsRows.rows, 2, "…with me and the friend who has a time (the silent friend has no row)")
eq(friendsRows and friendsRows.rows[1] and friendsRows.rows[1].userId, ME, "…me first (faster)")
eq(friendsRows and friendsRows.rows[2] and friendsRows.rows[2].userId, FRIEND, "…then the friend")
do
	local view = boardPart:FindFirstChild("BoardView")
	truthy(view and string.find(view.Sub.Text, "Friends", 1, true) ~= nil, "the board now reads Friends for this player")
	eq(boardPrompt.ActionText, "Show public", "…and its prompt offers the way back")
end

-- rejoin keeps best and streak
local bestText = me.leaderstats.Best.Value
h:leave(me)
h:advance(1)
eq(playerStore:GetAsync("u_" .. ME).lockUntil, 0, "leaving releases the session lock")
local me2 = h:join("Walker", ME)
h:advance(1)
eq(me2.leaderstats.Best.Value, bestText, "a rejoin shows the same best (" .. tostring(bestText) .. ")")
eq(me2.leaderstats.Streak.Value, 1, "…and the same streak")

-- an empty friends board says something useful
local loner = h:join("Loner", LONER)
h:advance(1)
h.Players:simulateSpawn(loner, ws)
h:advance(0.2)
local lonerRoot = loner.Character.HumanoidRootPart
lonerRoot.CFrame = CFrame.new(boardPart.Position.X, 3, boardPart.Position.Z - 6)
local before = #boardMsgs
boardPrompt.Triggered:Fire(loner)
h:advance(0.5)
local lonerView = nil
for i = before + 1, #boardMsgs do
	local m = boardMsgs[i]
	if m.mode == "friends" and not m.loading then lonerView = m end
end
truthy(lonerView ~= nil and lonerView.empty ~= nil and string.find(lonerView.empty, "same dungeon", 1, true) ~= nil,
	"an empty friends board says why and what to do")

--============================================================ H. a newer session owns the profile: this one stops writing
-- fork-tower REVIEW-4 §10: every profile write lands only while the record carries THIS session's
-- token. Simulate another server taking the profile over, then finish a run here.
do
	local char2 = h.Players:simulateSpawn(me2, ws)
	h:advance(0.2)
	hrp = char2.HumanoidRootPart
	local rec0 = playerStore:GetAsync("u_" .. ME)
	rec0.session = "another-server"
	playerStore:SetAsync("u_" .. ME, rec0)
	local finishesBefore = rec0.data.today.finishes
	local n0 = #runMsgs
	h.Players.LocalPlayer = me2
	hrp.CFrame = CFrame.new(0, 3, 12)
	archPrompt.Triggered:Fire(me2)
	h:advance(0.05)
	local r2 = nil
	for i = n0 + 1, #runMsgs do if runMsgs[i].state == "ready" then r2 = runMsgs[i] end end
	truthy(r2 ~= nil, "the rejoined player starts a run")
	origin = Vector3.new(r2.origin.x, r2.origin.y, r2.origin.z)
	local fin4 = walkPath(16)
	eq(fin4 and fin4.state, "finished", "the run finishes")
	eq(fin4 and fin4.unranked, true, "…but is shown as not saved")
	truthy(fin4 and fin4.reason and string.find(fin4.reason, "newer session", 1, true) ~= nil,
		"…and says a newer session owns the profile (" .. tostring(fin4 and fin4.reason) .. ")")
	local after = playerStore:GetAsync("u_" .. ME)
	eq(after.session, "another-server", "the other session's token is untouched")
	eq(after.data.today.finishes, finishesBefore, "…and so is its data (no finish was written over it)")
end

--============================================================ done
local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end

print(string.format("check_samedoor: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor failed", 0) end
