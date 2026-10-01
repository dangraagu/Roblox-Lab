-- The Same Door — THE PLAYER'S PATH, walked in the built world, from join into a second loop.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../same-door --out build/same-door.luau
--       cd ../same-door && luau tests/walk.luau
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Not a unit test and not the gate (robloxemu/check_samedoor*.luau are). This is somebody walking the
-- loop the way a player meets it and writing down, in numbers, what happened: spawn, the arch, the
-- antechamber card, the line, three seals, the Door, the finish card, Run again, a second run, the
-- board flipped to friends, a rest by the fire, a run left through the pause sheet, and a rejoin.
-- Assertions guard the path so a broken loop cannot print a happy story.
--
-- HONEST PLAYER, NOT A BOT ON THE SECRET LINE. The walker knows only what the player's own client
-- shows: it reads workspace.SameDoorLocal (the veils still standing, the walls the client built, the
-- Seal and Door models, the red rings) and the Run payloads the HUD gets. It never reads the server's
-- day record or the perfect line.
--   loop 1, a first-timer: explores at 0.85 x 16 studs/s, cell centre to cell centre; goes for a Seal
--     it can see, then the Door once it carries 3, otherwise the nearest revealed cell it has not
--     stood in; hesitates 0.8 s at a new fork and 0.6 s at a dead end (DESIGN §6.3 "normal"); waits
--     at the edge of a ring that is pulsing, and stands still while knocked down;
--   loop 2, the same player knowing the halls: plans the best Seal order over the passages it SAW in
--     loop 1 and walks the shortest line through them at full speed (a best case for run 2: the
--     model's players carry slop on top of this).
-- The game's Dungeon module is used only to string-pull that line over the player's OWN map
-- (Dungeon.tightLine, the geometry the day's P is measured in, on a maze holding only the passages
-- the player saw).

local Harness = require("../../robloxemu/emu/harness")
local bundle = require("../../robloxemu/build/same-door")

local h = Harness.new({ bundle = bundle, name = "same-door-walk", viewport = { 800, 360 }, touch = true })
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
-- The server's entropy is pinned so the walk replays; `luau tests/walk.luau -a <n>` pins another day.
local PIN = 20261001 + (tonumber((...)) or 0) * 104729
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(PIN + unseeded * 7919)
		end
		return realRandom.new(seed)
	end,
}
-- The emulator has no GetFriendsAsync: this walker has one friend, who has not played today.
local ME, FRIEND = 4242, 4243
h.Players.GetFriendsAsync = function(_self, uid)
	local list = if uid == ME then { { Id = FRIEND, Username = "Ana", DisplayName = "Ana", IsOnline = false } } else {}
	return { IsFinished = true, GetCurrentPage = function() return list end, AdvanceToNextPageAsync = function() end }
end

local problems = 0
local function need(c, msg)
	if not c then
		problems += 1
		print("  PROBLEM: " .. msg)
	end
end

local HB = h.services.RunService.Heartbeat
local FRAME = 1 / 60
local clock = 0
local function step(dt)
	h:advance(dt)
	HB:Fire(dt)
	clock += dt
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local RS = h.services.ReplicatedStorage
local R = RS.SameDoorRemotes
local Config = h:_require(RS.Config)
local Grid = h:_require(RS.Grid)
local Medals = h:_require(RS.Medals)
local Dungeon = h:_require(h.services.ServerScriptService.Dungeon) -- the line-puller only (see header)
local G = Config.Grid
local W, H, CELL = G.W, G.H, G.Cell

print("THE SAME DOOR - one walk, from join into a second loop (phone landscape 800x360, touch)")
print(string.format("  today: Door #%s; public facts: P = %s s (%.1f studs), Sealer <= %s, Gold <= %s, Silver <= %s",
	tostring(R:GetAttribute("Door")), Medals.formatTime(R:GetAttribute("PerfectMs")), R:GetAttribute("PerfectMs") / 1000 * Config.Walk.Speed,
	Medals.formatTime(R:GetAttribute("SealerMs")), Medals.formatTime(R:GetAttribute("GoldMs")), Medals.formatTime(R:GetAttribute("SilverMs"))))

local me = h:join("FirstTimer", ME)
h:advance(0.5)
for _, key in { "client/Hud.client", "client/Dungeon.client", "client/Board.client" } do
	local ok, err = h:tryRun(key)
	need(ok, key .. " failed to load: " .. tostring(err))
end
local msgs, toasts, cells = {}, {}, 0
R.Run.OnClientEvent:Connect(function(p) table.insert(msgs, { t = clock, p = p }) end)
R.Toast.OnClientEvent:Connect(function(m) table.insert(toasts, { t = clock, m = m }) end)
R.Cell.OnClientEvent:Connect(function(p) cells += #p.cells end)
local boardMsgs = {}
R.Board.OnClientEvent:Connect(function(p) table.insert(boardMsgs, p) end)

local char = h.Players:simulateSpawn(me, ws)
h:advance(0.2)
local hrp = char.HumanoidRootPart
local hum = char.Humanoid
local hud = me.PlayerGui.SameDoorHud.Root
local sp = ws.Hub.HubSpawn.Position
print(string.format("\n0.0 s  JOIN: landed at (%.1f, %.1f, %.1f) on HubSpawn (%.0f, %.0f); the hint reads: \"%s\"",
	hrp.Position.X, hrp.Position.Y, hrp.Position.Z, sp.X, sp.Z, hud.HintBar.Text.Text))
need(math.abs(hrp.Position.X - sp.X) < 0.01 and math.abs(hrp.Position.Z - sp.Z) < 0.01, "the character did not land on HubSpawn")

--============================================================================ walking in the hub
local function stand(seconds)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	for _ = 1, math.floor(seconds * 60 + 0.5) do step(FRAME) end
end

-- walk straight at 16 studs/s toward `target` (world XZ) until within `stop` studs; returns seconds
local function hubWalk(target, stop)
	local t = 0
	while t < 20 do
		local d = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
		if d.Magnitude <= stop then break end
		local u = d.Unit
		hum.MoveDirection = u
		local s = math.min(16 * FRAME, d.Magnitude - stop + 0.01)
		hrp.CFrame = CFrame.new(hrp.Position + u * s)
		step(FRAME)
		t += FRAME
	end
	hum.MoveDirection = Vector3.new(0, 0, 0)
	return t
end

local prompt = ws.Hub.Arch.Doorway.EnterPrompt
local tWalk = hubWalk(prompt.Parent.Position, prompt.MaxActivationDistance - 0.5)
print(string.format("%.1f s  the arch prompt \"%s\" comes up after %.2f s of walking (%.1f studs)", clock, prompt.ActionText, tWalk, tWalk * 16))
need(tWalk <= 5, "the core action takes more than 5 s to reach")
prompt.Triggered:Fire(me)
h:advance(0.05)
local ready = msgs[#msgs].p
need(ready.state == "ready", "the arch did not start a run")
local origin = Vector3.new(ready.origin.x, ready.origin.y, ready.origin.z)
print(string.format("%.1f s  ANTECHAMBER (lane at x %d, z %d): card \"%s\" / \"%s\"; %d cells sent so far",
	clock, origin.X, origin.Z, hud.Card.Title.Text, (string.gsub(hud.Card.Body.Text, "\n", " | ")), cells))

--============================================================================ what the player's client shows
local function idx(x, y) return y * W + x end
local function xyOf(i) return i % W, i // W end
local function localFolder() return ws:FindFirstChild("SameDoorLocal") and ws.SameDoorLocal:FindFirstChild("Run") end

-- The player's map, from the workspace only. Kept across runs (the player remembers what they saw).
local map = { revealed = {}, open = {}, seals = {}, door = nil, hazards = {} }
local function look()
	local f = localFolder()
	if f == nil then return end
	local veiled = {}
	for _, v in f.Veils:GetChildren() do veiled[v:GetAttribute("Cell")] = true end
	local walls = {}
	for _, w in f.Walls:GetChildren() do walls[w:GetAttribute("Edge")] = true end
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			if not veiled[x .. "," .. y] then
				local i = idx(x, y)
				map.revealed[i] = true
				for _, s in { { "N", 0, 1 }, { "E", 1, 0 }, { "S", 0, -1 }, { "W", -1, 0 } } do
					local nx, ny = x + s[2], y + s[3]
					if nx >= 0 and nx < W and ny >= 0 and ny < H then
						local key = Grid.edgeKey(x, y, s[1], Config)
						if not walls[key] and not Grid.isPerimeter(key, Config) then map.open[key] = true end
					end
				end
			end
		end
	end
	for _, m in f.Contents:GetChildren() do
		if m.Name == "Seal" then
			local cs = m:GetAttribute("Cell")
			local x, y = string.match(cs, "^(%d+),(%d+)$")
			map.seals[idx(tonumber(x), tonumber(y))] = true
		elseif m.Name == "Door" then
			local p = m.PrimaryPart.Position - origin
			map.door = idx(math.floor(p.X / CELL), math.floor(p.Z / CELL))
		elseif m.Name == "Hazard" then
			local ring = m:FindFirstChild("Ring")
			local p = ring.Position - origin
			map.hazards[idx(math.floor(p.X / CELL), math.floor(p.Z / CELL))] = true
		end
	end
end
local function neighbours(i)
	local x, y = xyOf(i)
	local out = {}
	for _, s in { { "N", 0, 1 }, { "E", 1, 0 }, { "S", 0, -1 }, { "W", -1, 0 } } do
		if map.open[Grid.edgeKey(x, y, s[1], Config)] then table.insert(out, idx(x + s[2], y + s[3])) end
	end
	return out
end
local function bfs(src)
	local dist, parent, q, head = { [src] = 0 }, {}, { src }, 1
	while head <= #q do
		local c = q[head]; head += 1
		for _, n in neighbours(c) do
			if dist[n] == nil then dist[n] = dist[c] + 1; parent[n] = c; table.insert(q, n) end
		end
	end
	return dist, parent
end
local function firstStep(src, dst, parent)
	local c = dst
	while parent[c] ~= nil and parent[c] ~= src do c = parent[c] end
	return c
end
local function rings()
	local out = {}
	local f = localFolder()
	if f == nil then return out end
	for _, m in f.Contents:GetChildren() do
		local ring = m.Name == "Hazard" and m:FindFirstChild("Ring")
		if ring then table.insert(out, { pos = ring.Position, r = ring.Size.Y / 2, bright = ring.Transparency < 0.6 }) end
	end
	return out
end

--============================================================================ walking in the dungeon
local runMsgsFrom = 1
local function runEnded()
	for i = runMsgsFrom, #msgs do
		local s = msgs[i].p.state
		if s == "finished" or s == "void" or s == "ended" then return msgs[i] end
	end
	return nil
end
local function carried()
	local n = 0
	for i = runMsgsFrom, #msgs do
		if type(msgs[i].p.seals) == "number" and msgs[i].p.seals > n then n = msgs[i].p.seals end
	end
	return n
end
local stats = { waitRing = 0, knocked = 0, hesitate = 0 }

-- one frame of walking toward (lx, lz) lane-local at `speed`; false when there already
local function stride(lx, lz, speed)
	if hum.PlatformStand then
		hum.MoveDirection = Vector3.new(0, 0, 0)
		step(FRAME)
		stats.knocked += FRAME
		return true
	end
	local p = hrp.Position
	local dx, dz = origin.X + lx - p.X, origin.Z + lz - p.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-6 then return false end
	local s = math.min(speed * FRAME, d)
	local nx, nz = p.X + dx / d * s, p.Z + dz / d * s
	-- a pulsing ring ahead: wait at its edge (a player who is already inside keeps going and gets out)
	for _, rg in rings() do
		if rg.bright then
			local edge = rg.r + 1
			local now = math.sqrt((p.X - rg.pos.X) ^ 2 + (p.Z - rg.pos.Z) ^ 2)
			local nxt = math.sqrt((nx - rg.pos.X) ^ 2 + (nz - rg.pos.Z) ^ 2)
			if now > edge and nxt <= edge then
				hum.MoveDirection = Vector3.new(0, 0, 0)
				step(FRAME)
				stats.waitRing += FRAME
				return true
			end
		end
	end
	hum.MoveDirection = Vector3.new(dx / d, 0, dz / d)
	hrp.CFrame = CFrame.new(nx, origin.Y + 3, nz)
	step(FRAME)
	return true
end

local function walkTo(lx, lz, speed)
	for _ = 1, 60 * 120 do
		if runEnded() then return end
		if not stride(lx, lz, speed) then return end
	end
	need(false, "a stride never arrived")
end

local function waitFor(seconds)
	local t = 0
	while t < seconds and not runEnded() do
		-- never stand in a pulsing ring
		local p = hrp.Position
		for _, rg in rings() do
			if rg.bright and math.sqrt((p.X - rg.pos.X) ^ 2 + (p.Z - rg.pos.Z) ^ 2) <= rg.r + 1 then return end
		end
		hum.MoveDirection = Vector3.new(0, 0, 0)
		step(FRAME)
		t += FRAME
		stats.hesitate += FRAME
	end
end

local function centreOf(i)
	local x, y = xyOf(i)
	return Grid.centre(x, y, Config)
end

local function report(label, speed, t0, c0)
	local fin = runEnded()
	local startAt, seals = nil, {}
	for i = runMsgsFrom, #msgs do
		local m = msgs[i]
		if m.p.state == "running" and startAt == nil then startAt = m.t end
		if m.p.taken and seals[m.p.seals] == nil then seals[m.p.seals] = m.t end
	end
	stand(0.25) -- let the 10 Hz look writer catch up before reading the band
	print(string.format("\n%s (%s)", label, speed))
	print(string.format("  %.1f s  the line: the clock starts (%.2f s after arrival)", startAt or -1, (startAt or t0) - t0))
	for k = 1, 3 do
		if seals[k] then
			print(string.format("  %.1f s  seal %d/3 at %s into the run; the halls turn to %s", seals[k], k,
				Medals.formatTime((seals[k] - startAt) * 1000), Config.Env.Bands[k + 1].name))
		end
	end
	local p = fin and fin.p or {}
	print(string.format("  %.1f s  THE DOOR: %s, official %s (display clock %s), medal %s", fin and fin.t or -1,
		tostring(p.state), Medals.formatDuration(p.timeMs), Medals.formatDuration((me:GetAttribute("SameDoorClock") or 0) * 1000), tostring(p.medal)))
	print(string.format("         card: \"%s\" / \"%s\"", hud.Card.Title.Text, (string.gsub(hud.Card.Body.Text, "\n", " | "))))
	print(string.format("         %d cells revealed this run of %d; best today %s; streak %s; rank %s%s",
		cells - c0, W * H, Medals.formatTime(p.bestMs), tostring(p.streak), tostring(p.rankLabel),
		if p.brag then "; THE DOOR IS SEALED (the brag moment)" else ""))
	local knocks, near = me:GetAttribute("SameDoorKnocks") or 0, me:GetAttribute("SameDoorNear") or 0
	print(string.format("         hazards: %d knock(s), %d near-miss(es); %.1f s waiting at red rings, %.1f s knocked down; band now %d (%s)",
		knocks, near, stats.waitRing, stats.knocked, me:GetAttribute("SameDoorBand") or 0,
		(Config.Env.Bands[me:GetAttribute("SameDoorBand") or 1] or {}).name or "?"))
	return p
end

-- LOOP 1: explore with only what the client shows
local function explore(speed)
	local t0, c0 = clock, cells
	stats = { waitRing = 0, knocked = 0, hesitate = 0 }
	local ax, az = Grid.centre(G.EntranceX, G.EntranceY, Config)
	walkTo(ax, az, speed) -- from the antechamber across the line into the entrance cell
	local here = idx(G.EntranceX, G.EntranceY)
	local stood = { [here] = true }
	local hesitated = {}
	local decisions = 0
	for _ = 1, 2000 do
		if runEnded() then break end
		look()
		local dist, parent = bfs(here)
		local target = nil
		local n = carried()
		if n >= 3 and map.door and dist[map.door] then
			target = map.door
		else
			local best = math.huge
			for s in map.seals do
				if dist[s] and dist[s] < best then best, target = dist[s], s end
			end
			if target == nil then
				for i in map.revealed do
					if not stood[i] and dist[i] and (dist[i] < best or (dist[i] == best and i < target)) then best, target = dist[i], i end
				end
			end
		end
		if target == nil then
			need(false, string.format("loop 1 is stuck in cell %d with %d seal(s): nothing left to explore", here, n))
			break
		end
		if target == here then
			-- standing on a seal the server has not counted yet: step across its centre
			local cx, cz = centreOf(here)
			walkTo(cx + 0.01, cz, speed)
			map.seals[here] = nil
		else
			local nxt = firstStep(here, target, parent)
			local cx, cz = centreOf(nxt)
			walkTo(cx, cz, speed)
			here = nxt
			if not stood[here] then
				stood[here] = true
				local open = #neighbours(here)
				if not hesitated[here] then
					hesitated[here] = true
					if open >= 3 then waitFor(0.8) elseif open == 1 then waitFor(0.6) end
				end
			end
			-- a seal model that is gone was taken
			look()
			local f = localFolder()
			if f then
				local still = {}
				for _, m in f.Contents:GetChildren() do
					if m.Name == "Seal" then
						local x, y = string.match(m:GetAttribute("Cell"), "^(%d+),(%d+)$")
						still[idx(tonumber(x), tonumber(y))] = true
					end
				end
				map.seals = still
			end
		end
		decisions += 1
	end
	return t0, c0, decisions
end

-- LOOP 2: plan over the player's own map and walk the tightest line through it
local sealCells = {}
local function planOwnLine()
	local m = Dungeon.newMaze(W, H)
	for key in map.open do
		local k, x, y = string.match(key, "^([EN]):(%d+),(%d+)$")
		if k == "E" then m.openE[idx(tonumber(x), tonumber(y))] = true else m.openN[idx(tonumber(x), tonumber(y))] = true end
	end
	local entrance = idx(G.EntranceX, G.EntranceY)
	local len, pts, _, lineCells = Dungeon.tightLine(Config, m, { entrance = entrance, seals = sealCells, door = map.door })
	return len, pts, #lineCells - 1
end

for _ = 1, 240 do step(FRAME) end -- reads the card for 4 s
runMsgsFrom = #msgs
-- remember where the seals were when first seen (the models vanish when taken)
local seenSeal = {}
local sealWatch = R.Cell.OnClientEvent:Connect(function(p)
	for _, c in p.cells do
		if c.kind == "seal" and not seenSeal[idx(c.x, c.y)] then
			seenSeal[idx(c.x, c.y)] = true
			table.insert(sealCells, idx(c.x, c.y))
		end
	end
end)
-- (the Cell payload is what the client builds the Seal models from; the explorer's own look() reads
-- the models, this only keeps their cells after they are gone)
local t1, c1, decisions = explore(Config.Walk.Speed * 0.85)
local p1 = report("LOOP 1: a first-timer exploring", string.format("%.1f studs/s, %d decisions, %.1f s hesitating", Config.Walk.Speed * 0.85, decisions, stats.hesitate), t1, c1)
need(p1.state == "finished", "loop 1 did not finish: " .. tostring(p1.state) .. " " .. tostring(p1.reason))
need(p1.medal ~= nil, "loop 1 earned no medal")
need(string.find(hud.Card.Title.Text, ":%d%d%.%d%d s") == nil, "the finish card mixes m:ss with seconds: " .. hud.Card.Title.Text)
local revealed1 = 0
for _ in map.revealed do revealed1 += 1 end
local fx, fz = hrp.Position.X - origin.X, hrp.Position.Z - origin.Z
print(string.format("         the player now knows %d of %d cells; the finish moved them to the Dawn Sanctum (lane-local %.0f, %.0f)",
	revealed1, W * H, fx, fz))
need(fz > H * CELL, "the finish did not move the player to the Sanctum")

-- RUN AGAIN from the finish card
local againBtn = hud.Card.Buttons.RunAgainButton
need(hud.Card.Visible and againBtn.Visible, "the finish card has no Run again button")
stand(1.1) -- the remote's 1 s rate limit is not this player's problem, but a person takes a second
againBtn.Activated:Fire()
h:advance(0.05)
need(msgs[#msgs].p.state == "ready", "Run again did not start a run")
print(string.format("\n%.1f s  RUN AGAIN: same layout, fresh clock (run %s)", clock, tostring(msgs[#msgs].p.run)))
for _ = 1, 60 do step(FRAME) end
runMsgsFrom = #msgs
local ownLen, ownPts, ownSteps = planOwnLine()
local t2, c2 = clock, cells
stats = { waitRing = 0, knocked = 0, hesitate = 0 }
walkTo(72, -8 + 0.001, 16)
for _, pt in ownPts do
	if runEnded() then break end
	walkTo(pt.x, pt.z, Config.Walk.Speed)
end
local p2 = report("LOOP 2: the same player, knowing the halls",
	string.format("the shortest line through what it saw: %d cell steps, %.1f studs, at 16 studs/s", ownSteps, ownLen), t2, c2)
need(p2.state == "finished", "loop 2 did not finish: " .. tostring(p2.state) .. " " .. tostring(p2.reason))
need((p2.timeMs or math.huge) < (p1.timeMs or 0), "loop 2 was not faster")
-- the player's own line can never be shorter than the day's P (P is the shortest line through ALL
-- passages; the player's map holds a subset): found 2026-10-01, when it was 16 studs shorter
need(ownLen >= R:GetAttribute("PerfectMs") / 1000 * Config.Walk.Speed - 0.02,
	string.format("the player's own line (%.1f studs) beat the day's perfect line P (%.1f)", ownLen, R:GetAttribute("PerfectMs") / 1000 * Config.Walk.Speed))
sealWatch:Disconnect()

--============================================================================ the hub: board, rest, pause
local hubBtn = hud.Card.Buttons.HubButton
stand(1.1)
hubBtn.Activated:Fire()
h:advance(0.05)
stand(0.5)
print(string.format("\n%.1f s  HUB: back at (%.1f, %.1f); the Rest button is %s", clock, hrp.Position.X, hrp.Position.Z,
	if hud.RestPanel.Visible then "showing" else "hidden"))
need(hud.RestPanel.Visible, "the Rest button is not offered in the hub")

for _ = 1, 3 do stand(1) end
local board = ws.Hub.DoorBoard
local view = board:FindFirstChild("BoardView")
-- a board row is four labels: rank, name, time, medal (or the SEALED plate)
local function rowText(k)
	local r = view:FindFirstChild("Row" .. k)
	if r == nil then return "" end
	return (string.gsub(string.format("%s %s %s %s", r.Rank.Text, r.Who.Text, r.Time.Text, r.Medal.Text), "^%s+", ""))
end
local tBoard = hubWalk(board.Position, board.TogglePrompt.MaxActivationDistance - 0.5)
print(string.format("%.1f s  THE BOARD (%.1f s walk): \"%s\" / \"%s\" / row 1 \"%s\"", clock, tBoard, view.Title.Text, view.Sub.Text, rowText(1)))
need(string.find(rowText(1), "FirstTimer", 1, true) ~= nil, "the public board does not show the walker")
need(string.find(rowText(1), Medals.formatTime(p2.timeMs), 1, true) ~= nil, "the public board does not show the best time")
board.TogglePrompt.Triggered:Fire(me)
stand(1)
print(string.format("%.1f s  flipped to friends: \"%s\" / row 1 \"%s\" / row 2 \"%s\" / \"%s\"", clock, view.Sub.Text, rowText(1),
	rowText(2), view.Foot.Text))
need(string.find(view.Sub.Text, "Friends", 1, true) ~= nil, "the board did not flip to friends")
need(string.find(rowText(1), "FirstTimer", 1, true) ~= nil, "the friends board does not show the player themself")
board.TogglePrompt.Triggered:Fire(me)
stand(0.5)
need(string.find(view.Sub.Text, "Public", 1, true) ~= nil, "the board did not flip back to public")

local fire = ws.Hub.Campfire.Fire
local restPrompt = fire:FindFirstChild("RestPrompt")
local tFire = hubWalk(fire.Position, restPrompt.MaxActivationDistance - 1)
restPrompt.Triggered:Fire(me)
stand(5)
print(string.format("%.1f s  REST by the fire (%.1f s walk): sitting %s, view softened %s, hint \"%s\"", clock, tFire, tostring(hum.Sit),
	tostring(h.services.Lighting.SameDoorRest.Enabled), hud.HintBar.Text.Text))
need(hum.Sit == true, "resting did not sit the player")
local before = hrp.Position
hubWalk(before + Vector3.new(0, 0, 3), 0.1)
stand(0.5)
print(string.format("%.1f s  one step wakes them: sitting %s, view softened %s", clock, tostring(hum.Sit), tostring(h.services.Lighting.SameDoorRest.Enabled)))
need(hum.Sit == false, "moving did not wake the player")

-- a third run, left through the pause sheet
hubWalk(prompt.Parent.Position, prompt.MaxActivationDistance - 0.5)
prompt.Triggered:Fire(me)
h:advance(0.05)
runMsgsFrom = #msgs
for _ = 1, 30 do step(FRAME) end
local ax, az = Grid.centre(G.EntranceX, G.EntranceY, Config)
walkTo(ax, az, 16)
local clockAtPause = me:GetAttribute("SameDoorClock")
hud.PauseBox.PauseButton.Activated:Fire()
stand(2)
local clockAfter = me:GetAttribute("SameDoorClock")
print(string.format("\n%.1f s  PAUSE in a run: the sheet says \"%s\"; the clock went %.2f -> %.2f while it was open", clock,
	hud.PauseSheet.Text.Text, clockAtPause or -1, clockAfter or -1))
need(hud.PauseSheet.Visible, "the pause sheet did not open")
need((clockAfter or 0) > (clockAtPause or 0) + 1.9, "the run clock stopped under the pause sheet")
hud.PauseSheet.Buttons.LeaveButton.Activated:Fire()
h:advance(0.05)
stand(1)
print(string.format("%.1f s  LEAVE RUN: the server says \"%s\"; the player is at (%.1f, %.1f) by the fire, sitting %s; nothing was posted (best still %s)",
	clock, tostring(msgs[#msgs].p.state), hrp.Position.X, hrp.Position.Z, tostring(hum.Sit), me.leaderstats.Best.Value))
need(msgs[#msgs].p.state == "ended", "leaving did not end the run")
need(hum.Sit == true, "leaving a run did not land the player resting at the fire")
need(me.leaderstats.Best.Value == Medals.formatTime(p2.timeMs), "leaving a run changed the best")

-- rejoin
local best = me.leaderstats.Best.Value
h:leave(me)
h:advance(1)
local me2 = h:join("FirstTimer", ME)
h:advance(1)
print(string.format("\nREJOIN: leaderstats Best %s (was %s), Streak %d", me2.leaderstats.Best.Value, best, me2.leaderstats.Streak.Value))
need(me2.leaderstats.Best.Value == best, "the rejoin lost the best")

print(string.format("\nIN NUMBERS: spawn->prompt %.2f s; loop 1 %s (%s, exploring, %d cells seen); loop 2 %s (%s, %.1f %% faster); %d problem(s)",
	tWalk, Medals.formatDuration(p1.timeMs), tostring(p1.medal), revealed1, Medals.formatDuration(p2.timeMs), tostring(p2.medal),
	(1 - (p2.timeMs or 0) / math.max(p1.timeMs or 1, 1)) * 100, problems))
for _, e in h:errors() do print("  scheduler: " .. e) end
if problems > 0 or #h:errors() > 0 then error("the walk hit problems", 0) end
