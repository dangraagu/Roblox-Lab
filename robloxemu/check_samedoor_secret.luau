-- The Same Door — nothing about the day reaches a client before the player walks to it.
-- Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--       luau check_samedoor_secret.luau 2>&1
--
-- DESIGN §3.4: the layout is secret data drawn on the day, held in server memory and ONE server-only
-- copy (ServerStorage.SameDoor.Day). A client is sent a cell only after the server has seen it walk
-- within 2 open steps of it. This file checks, on the real server and the real client:
--   1. a PRE-SEEDED record for today is used verbatim (every server reads the same stored day);
--   2. every Cell payload holds only cells within 2 open steps of a cell the walker had visited when
--      it was sent (BFS written here, over the record, independently of the game's revealFrom);
--   3. at every frame of the walk, no client-built Part stands in an unrevealed cell except its veil;
--   4. after a void, no further cell is sent for that run;
--   5. no replicated value, text, name or attribute and no remote payload (all 5 server->client
--      remotes, every message) holds 8 characters of the day's passage string;
--   6. CONTROL: the same scanner FINDS the string once it is planted in a workspace StringValue, a
--      player attribute and a Toast payload. Without this, a scanner that saw nothing would pass.

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")

local h = Harness.new({ bundle = bundle, name = "same-door-secret", viewport = { 1280, 720 }, touch = false })
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

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.services.ReplicatedStorage
local Config = h:_require(RS.Config)
local Dungeon = h:_require(h.services.ServerScriptService.Dungeon)
local Rng = h:_require(RS.Rng)
local HttpService = h.game:GetService("HttpService")

--============================================================ 1. a pre-seeded day is used verbatim
local dayIndex = math.floor(os.time() / 86400)
local r = Rng.new(424242)
local seeded = Dungeon.mint(Config, function(n) return r:below(n) end, dayIndex, os.time())
h.services.DataStoreService:GetDataStore(Config.Day.StoreName):SetAsync("d_" .. dayIndex, seeded)

local HB = h.services.RunService.Heartbeat
local FRAME = 1 / 60
local function step(dt)
	h:advance(dt)
	HB:Fire(dt)
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local R = RS.SameDoorRemotes
local copy = HttpService:JSONDecode(h.game:GetService("ServerStorage").SameDoor.Day.Value)
eq(copy.open, seeded.open, "the server uses the stored record's passages verbatim")
eq(copy.perfectMs, seeded.perfectMs, "…and its perfect line")
eq(copy.mintedAt, seeded.mintedAt, "…and did not re-mint (same mintedAt)")

local W = Config.Grid.W
local maze = Dungeon.decodeOpen(seeded.open, W, Config.Grid.H)
local function neighbours(i)
	local x, y = i % W, i // W
	local out = {}
	if x + 1 < W and maze.openE[i] then table.insert(out, i + 1) end
	if x > 0 and maze.openE[i - 1] then table.insert(out, i - 1) end
	if y + 1 < Config.Grid.H and maze.openN[i] then table.insert(out, i + W) end
	if y > 0 and maze.openN[i - W] then table.insert(out, i - W) end
	return out
end
-- cells within `d` open steps of any cell in `from` (written here, not the game's revealFrom)
local function within(from, d)
	local depth, q, head = {}, {}, 1
	for _, c in from do depth[c] = 0; table.insert(q, c) end
	while head <= #q do
		local c = q[head]; head += 1
		if depth[c] < d then
			for _, n in neighbours(c) do
				if depth[n] == nil then depth[n] = depth[c] + 1; table.insert(q, n) end
			end
		end
	end
	return depth
end
local entrance = seeded.entrance.y * W + seeded.entrance.x

local me = h:join("Seeker", 9101)
h:advance(0.5)
for _, key in { "client/Hud.client", "client/Dungeon.client", "client/Board.client" } do
	assert(h:tryRun(key))
end
local char = h.Players:simulateSpawn(me, ws)
h:advance(0.2)
local hrp = char.HumanoidRootPart

-- record every Cell payload with the walker's visited cells at the moment it arrived
local visited = {}
local visitedList = {}
local farCells, sentTotal = 0, 0
local revealed = {}
R.Cell.OnClientEvent:Connect(function(p)
	-- the antechamber counts as a visited node joined to the entrance
	local ok = within(visitedList, 2)
	local okAnte = within({ entrance }, 1)
	for _, c in p.cells do
		local i = c.y * W + c.x
		sentTotal += 1
		revealed[i] = true
		if ok[i] == nil and okAnte[i] == nil then farCells += 1 end
	end
end)

ws.Hub.Arch.Doorway.EnterPrompt.Triggered:Fire(me)
h:advance(0.05)
local runMsgs = {}
R.Run.OnClientEvent:Connect(function(p) table.insert(runMsgs, p) end)
local origin = Vector3.new(0, 0, 1000)

--============================================================ 2 + 3. walk, and check every frame
local world = Dungeon.fromRecord(Config, seeded)
local _, path = Dungeon.perfectPath(Config, world)
local pts = { { x = 72, z = -8 } }
for _, p in path do table.insert(pts, p) end
local localRoot = ws.SameDoorLocal
local strays, frames = 0, 0
local function cellOfWorld(p)
	local lx, lz = p.X - origin.X, p.Z - origin.Z
	local cx, cy = math.floor(lx / 16), math.floor(lz / 16)
	if cx < 0 or cx >= W or cy < 0 or cy >= Config.Grid.H then return nil end
	return cy * W + cx
end
local function checkFrame()
	frames += 1
	local run = localRoot:FindFirstChild("Run")
	if run == nil then return end
	for _, d in run:GetDescendants() do
		if d:IsA("BasePart") then
			local i = cellOfWorld(d.Position)
			if i ~= nil and not revealed[i] then
				local ok = d.Name == "Veil"
				if d.Name == "Wall" then
					-- a wall on an edge borders two cells; one of them must be revealed
					local key = d:GetAttribute("Edge") or ""
					local k, xs, ys = string.match(key, "^([EN]):(%-?%d+),(%-?%d+)$")
					local x, y = tonumber(xs), tonumber(ys)
					if k == "E" then ok = revealed[y * W + x] or revealed[y * W + x + 1] end
					if k == "N" then ok = revealed[y * W + x] or revealed[(y + 1) * W + x] end
				end
				if not ok then
					strays += 1
					if strays <= 3 then print("  stray: " .. d.Name .. " in unrevealed cell " .. i) end
				end
			elseif i ~= nil and revealed[i] and d.Name == "Veil" then
				strays += 1
				if strays <= 3 then print("  stray: a veil left in revealed cell " .. i) end
			end
		end
	end
end

local seg, x, z = 1, 72, -8
local finished = nil
for _ = 1, 60 * 90 do
	if seg < #pts then
		local remaining = 16 * FRAME
		while remaining > 0 and seg < #pts do
			local b = pts[seg + 1]
			local dx, dz = b.x - x, b.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
	end
	hrp.CFrame = CFrame.new(origin.X + x, origin.Y + 3, origin.Z + z)
	local ci = cellOfWorld(hrp.Position)
	if ci and not visited[ci] then visited[ci] = true; table.insert(visitedList, ci) end
	step(FRAME)
	checkFrame()
	for _, m in runMsgs do if m.state == "finished" then finished = m end end
	if finished then break end
end
truthy(finished ~= nil, "the seeded day's perfect line is walkable to the Door")
eq(farCells, 0, string.format("all %d cells sent were within 2 open steps of a visited cell when sent", sentTotal))
local nRevealed = 0
for _ in revealed do nRevealed += 1 end
truthy(nRevealed < W * Config.Grid.H, string.format("a perfect run revealed %d of %d cells, not the whole day", nRevealed, W * Config.Grid.H))
eq(strays, 0, string.format("over %d frames no client Part stood in an unrevealed cell except its veil", frames))

--============================================================ 4. after a void, nothing more is sent
h:advance(1.2)
R.RunAgain:simulateFireServer(me)
h:advance(0.1)
local sentBefore = sentTotal
revealed = {}
visited, visitedList = {}, {}
-- walk to the line and 4 cells in, then teleport 40 studs up the route
seg, x, z = 1, 72, -8
local walked = 0
local voidMsg = nil
for _ = 1, 60 * 20 do
	if walked < 60 then
		local remaining = 16 * FRAME
		while remaining > 0 and seg < #pts do
			local b = pts[seg + 1]
			local dx, dz = b.x - x, b.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
		walked += 16 * FRAME
		hrp.CFrame = CFrame.new(origin.X + x, origin.Y + 3, origin.Z + z)
	elseif voidMsg == nil then
		hrp.CFrame = CFrame.new(origin.X + x, origin.Y + 3, origin.Z + math.min(z + 40, 140))
	end
	step(FRAME)
	for _, m in runMsgs do if m.state == "void" then voidMsg = m end end
	if voidMsg then break end
end
truthy(voidMsg ~= nil, "a 40-stud teleport voids the run (" .. tostring(voidMsg and voidMsg.reason) .. ")")
local sentAtVoid = sentTotal
-- keep walking honestly through the rest of the route: nothing more may arrive for this run
for _ = 1, 60 * 20 do
	local remaining = 16 * FRAME
	while remaining > 0 and seg < #pts do
		local b = pts[seg + 1]
		local dx, dz = b.x - x, b.z - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
	end
	hrp.CFrame = CFrame.new(origin.X + x, origin.Y + 3, origin.Z + z)
	step(FRAME)
end
eq(sentTotal, sentAtVoid, "after the void, walking on reveals nothing (" .. (sentAtVoid - sentBefore) .. " cells were sent before it)")

--============================================================ 5. nothing replicated holds the passage string
local probe = string.sub(seeded.open, 9, 16)
local function scan(): (number, { string })
	local hits, where = 0, {}
	local function test(v, label)
		if type(v) == "string" and string.find(v, probe, 1, true) then
			hits += 1
			table.insert(where, label)
		end
	end
	for _, container in { ws, RS, h.Players } do
		for _, d in container:GetDescendants() do
			for _, prop in { "Value", "Text", "Name" } do
				local ok, v = pcall(function() return d[prop] end)
				if ok then test(v, d:GetFullName() .. "." .. prop) end
			end
			for k, v in d:GetAttributes() do test(v, d:GetFullName() .. "@" .. k) end
		end
	end
	for _, n in { "Cell", "Run", "Board", "Toast", "DayInfo" } do
		for _, rec in R[n]:getSent() do
			for i = 1, rec.args.n do
				local ok, s = pcall(function() return HttpService:JSONEncode(rec.args[i]) end)
				if ok then test(s, n .. " payload") elseif type(rec.args[i]) == "string" then test(rec.args[i], n .. " payload") end
			end
		end
	end
	return hits, where
end
local sentMessages = 0
for _, n in { "Cell", "Run", "Board", "Toast", "DayInfo" } do sentMessages += #R[n]:getSent() end
local hits, where = scan()
eq(hits, 0, string.format("no replicated value or any of %d remote messages holds 8 characters of the passage string", sentMessages)
	.. (hits > 0 and (" (" .. table.concat(where, ", ") .. ")") or ""))

--============================================================ 6. CONTROL: a planted leak is found
local planted = Instance.new("StringValue")
planted.Name = "Planted"
planted.Value = HttpService:JSONEncode(seeded)
planted.Parent = ws
me:SetAttribute("Planted", seeded.open)
R.Toast:FireClient(me, "debug " .. seeded.open)
local hits2, where2 = scan()
local found = { value = false, attr = false, toast = false }
for _, w in where2 do
	if w == "Workspace.Planted.Value" then found.value = true end
	if string.find(w, "@Planted", 1, true) then found.attr = true end
	if w == "Toast payload" then found.toast = true end
end
truthy(found.value and found.attr and found.toast,
	"CONTROL: the scanner finds the record planted in a workspace StringValue, a player attribute and a Toast payload ("
	.. table.concat(where2, ", ") .. ")")

local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end
print(string.format("check_samedoor_secret: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor_secret failed", 0) end
