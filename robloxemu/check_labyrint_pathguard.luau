-- Labyrinth Mariozo — the path guard, through the REAL server. Run: luau check_labyrint_pathguard.luau 2>&1
-- Rebuild the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- The HIGH from the second review (labyrint-spill/EYECANDY.md, "Night shift 2026-10-09", finding 1): the walk guard
-- refused only an exit reached SOONER than Progression.minClearSeconds, so a script could wait that long at the
-- spawn and then teleport onto the exit pad. That wrote a record no human can beat into LabyrintRekord_v1 and
-- raised `accepted` on the public board LabyrintTopp_v3.
--
-- This drives server/MazeGame.server from the wrapped bundle (no clients: the guard is the server's) and holds:
--   §1 wait, then teleport to the exit: refused, the player is told why, and NOTHING is written to either store,
--      not then, not after standing on the pad for minutes, not after an autosave;
--   §2 nothing is permanent: back at the start, the same run walked honestly counts, and both stores get it;
--   §3 the server's own move (advanceInstance to the next level) re-seeds: the next level, run at the top speed
--      with the speed perk (19 studs/s), counts;
--   §4 after a death and a respawn in the lobby, the next attempt counts, and so does a 3 s lag gap whose
--      catch-up lands on the exit pad in the same frame as the touch;
--   §5 a run through an opened secret door (a real shortcut) counts;
--   §6 the switches: CONFIG.PathGuard.Enabled is on and the time floor is still applied (read from the source).
-- NOT covered here: god-mode runs (the allow-list is one named user; finishRun skips both guards for them, as
-- before), and group / friends runs with several participants (only the SOLVER's path is judged; every participant
-- is seeded by the same placeInInstance / advanceInstance lines this check exercises with one player).
-- Headless limits: no physics. "Walking" is this check moving the root part along cell centres at a walking speed,
-- one frame at a time; a teleport is the same root part written far away in one frame. The server cannot tell the
-- difference in any other way either: it reads the root part's position.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrint pathguard")
local truthy, eq = T.truthy, T.eq

local UID = 7301
local ctx = Lib.boot({ accepted = 60, coins = 0, clients = {}, userId = UID, name = "Runner" })
local h = ctx.h
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local records = DSS:GetDataStore("LabyrintRekord_v1")
local board = DSS:GetOrderedDataStore("LabyrintTopp_v3")
local profile = DSS:GetDataStore("LabyrintSpill_v1")
local completes = RS:WaitForChild("HudRemotes"):WaitForChild("LevelComplete")
local notices = RS.HudRemotes:WaitForChild("Broadcast")
local levelInfo = RS.HudRemotes:WaitForChild("LevelInfo")

local function dump(v: any): string
	if type(v) ~= "table" then return tostring(v) end
	local keys = {}
	for k in v do table.insert(keys, tostring(k)) end
	table.sort(keys)
	local out = {}
	for _, k in keys do
		local val = v[k]
		if val == nil then val = v[tonumber(k) :: number] end
		table.insert(out, k .. "=" .. dump(val))
	end
	return "{" .. table.concat(out, ",") .. "}"
end
local function stores(): string
	return "records " .. dump(records.__data) .. " | board " .. dump(board.__data)
end
local function lastInfo()
	local sent = levelInfo:sentTo(ctx.plr)
	return sent[#sent] and sent[#sent].args[1]
end
local function lastNotice(): string?
	local sent = notices:sentTo(ctx.plr)
	local r = sent[#sent]
	return r and not r.all and r.args[2] or nil
end
local function nCompletes(): number return #completes:sentTo(ctx.plr) end
local function boardLevel(): number?
	local v = board.__data["u_" .. UID]
	return type(v) == "number" and math.floor(v / 2e9 + 0.5) or nil
end
local function folder(): any return ctx.folder() end

-- the fine-grid route between two cells; `openDoor` = a wall cell to treat as open (a secret door that sank)
local function route(g: any, from: { number }, to: { number }, openDoor: string?): { { number } }?
	local key = function(x, y) return x .. "," .. y end
	local prev, q, head = { [key(from[1], from[2])] = false }, { from }, 1
	while head <= #q do
		local cur = q[head]; head += 1
		if cur[1] == to[1] and cur[2] == to[2] then break end
		for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nx, ny = cur[1] + dd[1], cur[2] + dd[2]
			local k = key(nx, ny)
			if nx >= 0 and ny >= 0 and nx < g.gCols and ny < g.gRows and (not g.walls[k] or k == openDoor) and prev[k] == nil then
				prev[k] = cur
				table.insert(q, { nx, ny })
			end
		end
	end
	if prev[key(to[1], to[2])] == nil then return nil end
	local path, cur = {}, to
	while cur do
		table.insert(path, 1, cur)
		cur = prev[key(cur[1], cur[2])]
	end
	return path
end

-- walk: straight segments between cell centres at `speed` studs/s, 30 frames a second
local function walkTo(target: Vector3, speed: number)
	local from = ctx.hrp.Position
	local flat = Vector3.new(target.X, from.Y, target.Z)
	local dist = (flat - from).Magnitude
	local n = math.max(1, math.ceil(dist / speed * 30))
	for i = 1, n do
		ctx.hrp.CFrame = CFrame.new(from:Lerp(flat, i / n))
		h:advance(1 / 30)
	end
end
local function walkCells(g: any, cells: { { number } }, speed: number): number
	for i = 2, #cells do walkTo(g.world(cells[i][1], cells[i][2]), speed) end
	return (#cells - 1) * g.S / speed
end
local function touchExit()
	local exit = folder():FindFirstChild("Exit")
	exit.Touched:Fire(ctx.hrp)
	h:advance(0.5)
end
local function respawn()
	local char = h.Players:simulateSpawn(ctx.plr, h.workspace)
	h:advance(0.5)
	ctx.char, ctx.hrp, ctx.hum = char, char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
end
local function startRun(level: number)
	RS:WaitForChild("LobbyRemotes"):WaitForChild("StartRun"):simulateFireServer(ctx.plr, level, "solo")
	h:advance(0.3)
end

local src = Lib.serverSource(ctx.bundle)
truthy(string.find(src, "PathGuard = {", 1, true) ~= nil, "the server has a CONFIG.PathGuard block")
truthy(ctx.bundle["shared/PathGuard"] ~= nil, "and the bundle carries shared/PathGuard")

--================================================================ §1 wait, then teleport

print("== 1. wait at the spawn, then teleport to the exit ==")
startRun(61)
local f = folder()
truthy(f ~= nil, "set-up: in level 61")
eq(lastInfo() and lastInfo().level, 61, "set-up: level 61 (accepted 60 + 1)")
local g = Lib.grid(f)
local startPos = ctx.hrp.Position
local startCell = { g.fine(startPos) }
local exitPart = f:FindFirstChild("Exit")
local exitCell = { g.fine(exitPart.Position) }
local before = stores()
local c0 = nCompletes()
local trophies0 = ctx.plr.leaderstats.Trophies.Value
do
	h:advance(120) -- far longer than anyone needs to walk a 12x12 maze: the old time floor is long past
	ctx.hrp.CFrame = CFrame.new(exitPart.Position + Vector3.new(0, 3, 0))
	touchExit()
	eq(nCompletes() - c0, 0, "wait 120 s, teleport onto the exit pad: no level-complete card")
	eq(lastInfo() and lastInfo().level, 61, "still on level 61 (the run did not advance)")
	eq(lastInfo() and lastInfo().accepted, 60, "accepted is still 60")
	eq(ctx.plr.leaderstats.Trophies.Value, trophies0, "no trophy")
	local note = lastNotice()
	truthy(note ~= nil and string.find(string.lower(note), "walk", 1, true) ~= nil, "the player is told why: " .. tostring(note))
	truthy(note ~= nil and string.find(note, "Too fast", 1, true) == nil, "and it is not the time floor's message (120 s is not too fast)")
	eq(stores(), before, "nothing was written to LabyrintRekord_v1 or LabyrintTopp_v3")
	-- and without touching anything they are told, within a couple of seconds, that the path is lost
	h:advance(2)
	local lostNote = lastNotice()
	truthy(lostNote ~= nil and string.find(lostNote, "lost track", 1, true) ~= nil, "a moment later they are told the path is lost: " .. tostring(lostNote))
	local sentThen = #notices:sentTo(ctx.plr)
	h:advance(20)
	eq(#notices:sentTo(ctx.plr) - sentThen, 0, "once, not on every sample")
	-- stand on the pad for five minutes, touching it all the time
	for _ = 1, 60 do
		h:advance(5)
		exitPart.Touched:Fire(ctx.hrp)
	end
	h:advance(1)
	eq(nCompletes() - c0, 0, "five minutes standing on the pad: still nothing")
	-- step off and on again in small moves around the exit (a script wiggling): still nothing
	for i = 1, 40 do
		ctx.hrp.CFrame = CFrame.new(exitPart.Position + Vector3.new((i % 2) * 2, 3, 0))
		h:advance(0.25)
		exitPart.Touched:Fire(ctx.hrp)
	end
	h:advance(140) -- two autosaves
	eq(nCompletes() - c0, 0, "wiggling on the pad: still nothing")
	eq(stores(), before, "and still nothing in either store after two autosaves")
	local saved = profile.__data["p_" .. UID]
	eq(saved and saved.accepted, 60, "the saved profile still says accepted 60")
	eq(boardLevel(), 60, "the board still holds level 60 for them (written at join)")
	eq(records.__data["lvl_61"], nil, "level 61 has no record")
end

--================================================================ §2 nothing is permanent

print("== 2. back at the start, the same run walked honestly counts ==")
do
	eq(folder(), f, "the same maze is still there")
	ctx.hrp.CFrame = CFrame.new(startPos)
	h:advance(1)
	local back = lastNotice()
	truthy(back ~= nil and string.find(back, "Back on track", 1, true) ~= nil, "back at the start they are told the path is found: " .. tostring(back))
	local cells = route(g, startCell, exitCell) :: { { number } }
	local nWalk = #notices:sentTo(ctx.plr)
	local secs = walkCells(g, cells, 16)
	print(string.format("  walked %d cells in %.1f s", #cells - 1, secs))
	touchExit()
	eq(nCompletes() - c0, 1, "walked at 16 studs/s, the exit counts")
	eq(#notices:sentTo(ctx.plr) - nWalk, 0, "with no notice of any kind on the way")
	eq(lastInfo() and lastInfo().accepted, 61, "accepted is 61")
	eq(lastInfo() and lastInfo().level, 62, "and the run goes on to level 62")
	h:advance(2)
	eq(boardLevel(), 61, "LabyrintTopp_v3 holds level 61 for them")
	truthy(records.__data["lvl_61"] ~= nil, "and LabyrintRekord_v1 has the time")
end

--================================================================ §3 the server's own move re-seeds

print("== 3. level 62, straight from the server's move to its start, at 19 studs/s ==")
do
	f = folder()
	g = Lib.grid(f)
	local here = { g.fine(ctx.hrp.Position) }
	eq(here[1] .. "," .. here[2], "1,1", "the server put them on the start cell of level 62")
	local exit = f:FindFirstChild("Exit")
	local cells = route(g, here, { g.fine(exit.Position) }) :: { { number } }
	local c1 = nCompletes()
	-- the guard is armed on a level the server moved them to as well: wait, teleport, refused
	local was = ctx.hrp.Position
	h:advance(90)
	ctx.hrp.CFrame = CFrame.new(exit.Position + Vector3.new(0, 3, 0))
	touchExit()
	eq(nCompletes() - c1, 0, "level 62: wait 90 s, teleport to the exit: refused here too")
	eq(lastInfo() and lastInfo().accepted, 61, "accepted is still 61")
	ctx.hrp.CFrame = CFrame.new(was)
	h:advance(4) -- past the notice throttle
	local n1 = #notices:sentTo(ctx.plr)
	walkCells(g, cells, 19)
	touchExit()
	eq(nCompletes() - c1, 1, "run at the top speed with the speed perk, the exit counts")
	eq(lastInfo() and lastInfo().accepted, 62, "accepted is 62")
	eq(#notices:sentTo(ctx.plr) - n1, 0, "and nobody was told off on the way")
end

--================================================================ §4 death, respawn, again

print("== 4. die on level 63, respawn in the lobby, run it again ==")
do
	f = folder()
	g = Lib.grid(f)
	local exit = f:FindFirstChild("Exit")
	local cells = route(g, { g.fine(ctx.hrp.Position) }, { g.fine(exit.Position) }) :: { { number } }
	local half = {}
	for i = 1, math.max(2, #cells // 2) do half[i] = cells[i] end
	walkCells(g, half, 16)
	ctx.hum.Health = 0
	h:advance(0.3)
	respawn()
	eq(ctx.plr:GetAttribute("MazeFolder"), nil, "dead: back in the lobby")
	h:advance(3)
	startRun(63)
	f = folder()
	truthy(f ~= nil, "in level 63 again")
	g = Lib.grid(f)
	exit = f:FindFirstChild("Exit")
	cells = route(g, { g.fine(ctx.hrp.Position) }, { g.fine(exit.Position) }) :: { { number } }
	local c1 = nCompletes()
	local n1 = #notices:sentTo(ctx.plr)
	-- ... all but the last five cells. Then a lag gap: the server sees nothing for 3 s, and the catch-up (the five
	-- cells a walker covers in that time) arrives in the SAME frame as the touch on the pad. finishRun takes a fresh
	-- sample before it judges, so the arrival counts at once and not one sampler tick later.
	local head, tail = {}, {}
	for i = 1, #cells - 5 do head[i] = cells[i] end
	walkCells(g, head, 19)
	h:advance(3)
	local last = g.world(cells[#cells][1], cells[#cells][2])
	ctx.hrp.CFrame = CFrame.new(last.X, ctx.hrp.Position.Y, last.Z)
	exit.Touched:Fire(ctx.hrp) -- no frame in between
	h:advance(0.1)
	eq(nCompletes() - c1, 1, "the second attempt counts, with a 3 s lag gap that catches up on the exit pad itself")
	eq(#notices:sentTo(ctx.plr) - n1, 0, "and nobody was told off")
	eq(lastInfo() and lastInfo().accepted, 63, "accepted is 63")
end

--================================================================ §5 through a secret door

print("== 5. a shortcut through an opened secret door ==")
do
	-- out, and look for a level whose secret door is a real shortcut: the way round it is long
	local function toLobby()
		local door = folder() and folder():FindFirstChild("LobbyDoor")
		door:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(ctx.plr)
		h:advance(1)
	end
	toLobby()
	-- "Real" here means: from the cell in front of the door, every cell of the route BEHIND the door is at least FAR
	-- cells away with the door shut. FAR is more than a full bank reaches, so a guard whose grid has that door shut
	-- (the server's old bug: it read the door plan after the button loop had emptied it) can never follow the runner
	-- to the exit, while the real guard follows them straight through.
	local FAR = 40
	local function closedDist(g2: any, from: { number }): { [string]: number }
		local dist, q, head = { [from[1] .. "," .. from[2]] = 0 }, { from }, 1
		while head <= #q do
			local cur = q[head]; head += 1
			for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, ny = cur[1] + dd[1], cur[2] + dd[2]
				local k = nx .. "," .. ny
				if nx >= 0 and ny >= 0 and nx < g2.gCols and ny < g2.gRows and not g2.walls[k] and dist[k] == nil then
					dist[k] = dist[cur[1] .. "," .. cur[2]] + 1
					table.insert(q, { nx, ny })
				end
			end
		end
		return dist
	end
	local found = nil
	for L = 60, 10, -1 do
		startRun(L)
		f = folder()
		g = Lib.grid(f)
		local start = { g.fine(ctx.hrp.Position) }
		local exitC = { g.fine(f:FindFirstChild("Exit").Position) }
		local closed = #(route(g, start, exitC) :: any) - 1
		for _, d in f:GetChildren() do
			if d.Name == "SecretWall" and not found then
				local dc = { g.fine(d.Position) }
				local k = dc[1] .. "," .. dc[2]
				local open = route(g, start, exitC, k)
				-- the two cells on either side of the door, and the way round between them with the door shut
				local a, b
				if not g.walls[(dc[1] - 1) .. "," .. dc[2]] then a, b = { dc[1] - 1, dc[2] }, { dc[1] + 1, dc[2] }
				else a, b = { dc[1], dc[2] - 1 }, { dc[1], dc[2] + 1 } end
				local around = route(g, a, b)
				local nearest, front = math.huge, nil
				if open and around then
					-- the route's cell in front of the door, and how near the route behind the door comes to it
					local di = 0
					for i, cc in open do if cc[1] == dc[1] and cc[2] == dc[2] then di = i end end
					if di > 1 then
						front = open[di - 1]
						local dist = closedDist(g, front)
						for i = di + 1, #open do nearest = math.min(nearest, dist[open[i][1] .. "," .. open[i][2]] or math.huge) end
					end
				end
				if open and around and #open - 1 <= closed - 20 and nearest >= FAR and nearest < math.huge then
					found = { L = L, door = d, key = k, start = start, exitC = exitC, closed = closed, open = #open - 1, around = #around - 1, nearest = nearest, front = front }
				end
			end
		end
		if found then break end
		toLobby()
	end
	truthy(found ~= nil, "set-up: a level between 10 and 60 has a secret door that is a real shortcut to the exit")
	if found then
		print(string.format("  level %d: %d cells by the door, %d without it (the way round the door is %d cells; behind it the route stays >= %d cells from the cell in front of it)",
			found.L, found.open, found.closed, found.around, found.nearest))
		-- which button opens it? Walk to each button (honestly) until the door sinks.
		local y0 = found.door.Position.Y
		local here = found.start
		local opened = false
		for _, b in f:GetChildren() do
			if b.Name == "SecretButton" and not opened then
				local bc = { g.fine(b.Position) }
				local doorOpen = nil
				walkCells(g, route(g, here, bc, doorOpen) :: any, 16)
				here = bc
				b.Touched:Fire(ctx.hrp)
				h:advance(1.5)
				opened = found.door.Position.Y < y0 - 1
			end
		end
		truthy(opened, "set-up: walked to its button, and the door sank")
		local c1 = nCompletes()
		local n0 = #notices:sentTo(ctx.plr)
		-- to the cell in front of the door (the button may be anywhere), then THROUGH it and on to the exit
		walkCells(g, route(g, here, found.front) :: any, 19)
		local onward = route(g, found.front, found.exitC, found.key) :: any
		local through = false
		for _, cc in onward do if cc[1] .. "," .. cc[2] == found.key then through = true end end
		truthy(through, "set-up: the way on from there goes through the door cell")
		walkCells(g, onward, 19)
		local at = { g.fine(ctx.hrp.Position) }
		eq(at[1] .. "," .. at[2], found.exitC[1] .. "," .. found.exitC[2], "set-up: ran through the door to the exit cell")
		touchExit()
		eq(nCompletes() - c1, 1, "the shortcut run through the opened door counts")
		eq(#notices:sentTo(ctx.plr) - n0, 0, "and nobody was told off on the way")
	end
end

--================================================================ §6 the rest of the rules are where they were

print("== 6. the switch, and the notice ==")
do
	truthy(string.find(src, "PathGuard = {%s*Enabled = true") ~= nil, "CONFIG.PathGuard.Enabled is true")
	truthy(string.find(src, "WalkGuard = {%s*Enabled = true") ~= nil, "the time floor (CONFIG.WalkGuard) is still on")
	truthy(string.find(src, "walked < inst.minClear", 1, true) ~= nil, "and finishRun still applies it")
end

for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings")
T.finish(h)
