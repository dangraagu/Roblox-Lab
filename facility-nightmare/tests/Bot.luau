--!nocheck
-- Bot.luau — a headless PLAYER for FACILITY, used by tests/walk.luau and by
-- robloxemu/check_facilitynightmare.luau. Not a spec and not game code.
--
-- It plays only on what a client could know:
--   * the workspace: built rooms (Room_<id> folders and their Floor parts), door leaves
--     (Door_<lo>_<hi>, open when CanCollide is false), Fuse and Cell parts, the ExitLift, and each
--     room's RoomLight;
--   * its own State pushes (battery, fuses x/N, phase) and Notices.
-- It never reads ServerStorage, the plan, or a seed. A room it has not opened does not exist for
-- it, exactly as for a player.
--
-- It moves the way the emulator lets anything move: by writing the root part's CFrame once per
-- server tick, at the speed the SERVER wrote onto the Humanoid, and advancing the virtual clock by
-- that tick. It walks room centre -> doorway -> room centre, so every step it takes is one a
-- humanoid could take (no diagonal through a wall).

local Bot = {}
Bot.__index = Bot

local TICK = 0.1
-- A required module does not see the harness globals (the luau CLI gives each module its own
-- globals table), so the datatypes come from the harness itself in Bot.new.
local Vector3, CFrame
local CELL = 28

function Bot.new(h, plr, opts)
	Vector3 = h.instance.datatypes.Vector3
	CFrame = h.instance.datatypes.CFrame
	opts = opts or {}
	local remotes = h.ReplicatedStorage:FindFirstChild("FacilityRemotes")
	assert(remotes, "Bot: no FacilityRemotes")
	local self = setmetatable({
		h = h,
		plr = plr,
		remotes = remotes,
		State = remotes:FindFirstChild("State"),
		Notice = remotes:FindFirstChild("Notice"),
		noticeSeen = 0,
		notices = {},
		toasts = {},
		lightWanted = false,
		stats = { seconds = 0, darkSeconds = 0, lightSeconds = 0, doorsOpened = 0, fuses = 0, cells = 0, maxExposure = 0 },
		log = opts.log,
		maxSeconds = opts.maxSeconds or 600,
		onTick = opts.onTick,
		-- DESIGN.md §0 stands human inefficiency in for by walking slower: 1 = the "perfect" 16
		-- studs/s explorer, 0.65 = the "slow" 10.4. Never above 1: nothing here outruns the server.
		speedScale = math.min(1, opts.speedScale or 1),
	}, Bot)
	return self
end

--============================================================ reading

function Bot:state()
	local sent = self.State:getSent()
	for i = #sent, 1, -1 do
		local rec = sent[i]
		if rec.player == self.plr then
			return rec.args[1]
		end
	end
	return nil
end

-- New notices since the last call, also recorded on self.notices / self.toasts.
function Bot:drainNotices()
	local sent = self.Notice:getSent()
	local out = {}
	for i = self.noticeSeen + 1, #sent do
		local rec = sent[i]
		if rec.player == self.plr then
			local n = { kind = rec.args[1], data = rec.args[2], at = self.h.scheduler:now() }
			table.insert(out, n)
			table.insert(self.notices, n)
			if n.kind == "toast" then table.insert(self.toasts, tostring(n.data)) end
		end
	end
	self.noticeSeen = #sent
	return out
end

function Bot:hrp()
	local c = self.plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

function Bot:pos()
	local r = self:hrp()
	return r and r.Position
end

function Bot:speed()
	local c = self.plr.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	return hum and hum.WalkSpeed or 16
end

-- The zone folder this player's character is in: the one whose ride car is nearest in X.
function Bot:zone()
	local fac = self.h.workspace:FindFirstChild("Facility")
	local p = self:pos()
	if not fac or not p then return nil end
	local best, bestD = nil, math.huge
	for _, z in fac:GetChildren() do
		local car = z:FindFirstChild("RideCar")
		local plate = car and car:FindFirstChild("RideFloor")
		if plate then
			local d = math.abs(plate.Position.X - p.X)
			if d < bestD then best, bestD = z, d end
		end
	end
	return best
end

function Bot:floor()
	local z = self:zone()
	return z and z:FindFirstChild("Floor")
end

-- id -> { id, center = Vector3 (floor top), folder, light }
function Bot:rooms()
	local out = {}
	local fl = self:floor()
	local rooms = fl and fl:FindFirstChild("Rooms")
	if not rooms then return out end
	for _, f in rooms:GetChildren() do
		local id = tonumber(string.match(f.Name, "^Room_(%d+)$"))
		local floorPart = f:FindFirstChild("Floor")
		if id and floorPart then
			local fixture = f:FindFirstChild("Fixture")
			out[id] = {
				id = id,
				center = Vector3.new(floorPart.Position.X, 0, floorPart.Position.Z),
				folder = f,
				light = fixture and fixture:FindFirstChild("RoomLight"),
			}
		end
	end
	return out
end

-- list of { lo, hi, part, open, pos }
function Bot:doors()
	local out = {}
	local fl = self:floor()
	local doors = fl and fl:FindFirstChild("Doors")
	if not doors then return out end
	for _, d in doors:GetChildren() do
		local lo, hi = string.match(d.Name, "^Door_(%d+)_(%d+)$")
		if lo then
			table.insert(out, { lo = tonumber(lo), hi = tonumber(hi), part = d, open = d.CanCollide == false, name = d.Name })
		end
	end
	return out
end

function Bot:roomAt(rooms, p)
	for id, r in rooms do
		if math.abs(p.X - r.center.X) <= CELL / 2 and math.abs(p.Z - r.center.Z) <= CELL / 2 then
			return id
		end
	end
	return nil
end

function Bot:exitRoom(rooms)
	local fl = self:floor()
	local lift = fl and fl:FindFirstChild("ExitLift")
	local plat = lift and lift:FindFirstChild("LiftPlatform")
	if not plat then return nil end
	return self:roomAt(rooms, plat.Position)
end

--============================================================ acting

function Bot:fire(name, ...)
	self.remotes:FindFirstChild(name):simulateFireServer(self.plr, ...)
end

-- One tick: manage the flashlight from what the player can SEE (is my room's light on?), then let
-- the clock run.
function Bot:tick()
	local p = self:pos()
	local st = self:state()
	if p and st and st.phase == "floor" and st.run then
		local rooms = self:rooms()
		local here = self:roomAt(rooms, p)
		local r = here and rooms[here]
		local dark = r ~= nil and r.light ~= nil and r.light.Enabled == false
		local want = dark and (st.run.battery or 0) > 0
		if want ~= self.lightWanted then
			self.lightWanted = want
			self:fire("Flashlight", want)
		end
		if dark then self.stats.darkSeconds += TICK end
		if st.run.lightOn then self.stats.lightSeconds += TICK end
		if (st.run.exposure or 0) > self.stats.maxExposure then self.stats.maxExposure = st.run.exposure end
	end
	self.h:advance(TICK)
	if self.onTick then self.onTick(self) end
	self.stats.seconds += TICK
	self:drainNotices()
end

function Bot:phase()
	local st = self:state()
	return st and st.phase
end

-- Walk in a straight line at the server's WalkSpeed. Returns false if the phase left "floor".
function Bot:walkTo(target, keepPhase)
	local guard = 0
	while true do
		guard += 1
		if guard > 20000 then error("Bot:walkTo never arrived") end
		local hrp = self:hrp()
		if not hrp then return false end
		if keepPhase and self:phase() ~= keepPhase then return false end
		local p = hrp.Position
		local flat = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
		local d = flat.Magnitude
		if d < 0.05 then return true end
		local stepLen = math.min(d, self:speed() * self.speedScale * TICK)
		local np = Vector3.new(p.X + flat.X / d * stepLen, 3, p.Z + flat.Z / d * stepLen)
		hrp.CFrame = CFrame.new(np)
		self:tick()
	end
end

function Bot:waitSeconds(s, keepPhase)
	for _ = 1, math.floor(s / TICK + 0.5) do
		if keepPhase and self:phase() ~= keepPhase then return false end
		self:tick()
	end
	return true
end

-- Walk out of a car to the hub car and stand in it until the ride starts.
function Bot:board(hub)
	local car = hub:FindFirstChild("HubCar")
	local plate = car and car:FindFirstChild("CarFloor")
	assert(plate, "Bot:board: the hub has no HubCar.CarFloor")
	self:walkTo(Vector3.new(plate.Position.X, 3, plate.Position.Z))
	local guard = 0
	while self:phase() ~= "ride" do
		guard += 1
		if guard > 100 then return false end
		self:tick()
	end
	return true
end

function Bot:waitPhase(phase, maxSeconds)
	local t = 0
	while self:phase() ~= phase do
		if t > maxSeconds then return false end
		self:tick()
		t += TICK
	end
	return true
end

--============================================================ exploring a floor

-- BFS over rooms the player has opened, through open doors.
function Bot:route(rooms, doors, from, to)
	local adj = {}
	for _, d in doors do
		if d.open and rooms[d.lo] and rooms[d.hi] then
			adj[d.lo] = adj[d.lo] or {}
			adj[d.hi] = adj[d.hi] or {}
			table.insert(adj[d.lo], d.hi)
			table.insert(adj[d.hi], d.lo)
		end
	end
	local prev, q, h = { [from] = from }, { from }, 1
	while h <= #q do
		local a = q[h]; h += 1
		if a == to then break end
		for _, b in adj[a] or {} do
			if prev[b] == nil then prev[b] = a; table.insert(q, b) end
		end
	end
	if prev[to] == nil then return nil end
	local path = { to }
	local c = to
	while c ~= from do c = prev[c]; table.insert(path, 1, c) end
	return path
end

-- From the centre of room a, through the (open) doorway, to the centre of room b.
function Bot:cross(rooms, a, b)
	local ca = rooms[a].center
	local cb = rooms[b] and rooms[b].center
	local door = (ca + (cb or ca)) / 2
	if not self:walkTo(Vector3.new(door.X, 3, door.Z), "floor") then return false end
	if not self:walkTo(Vector3.new(cb.X, 3, cb.Z), "floor") then return false end
	return true
end

function Bot:followPath(path)
	for i = 2, #path do
		local rooms = self:rooms()
		if not self:cross(rooms, path[i - 1], path[i]) then return false end
	end
	return true
end

-- Walk to a closed door from inside `room`, wait for it to open, go through. The neighbour's
-- centre is mirrored through the leaf, since that room does not exist yet.
function Bot:openThrough(room, door)
	local rooms = self:rooms()
	local c = rooms[room].center
	local leaf = door.part.Position
	local dir = Vector3.new(leaf.X - c.X, 0, leaf.Z - c.Z).Unit
	local approach = Vector3.new(leaf.X - dir.X * 6, 3, leaf.Z - dir.Z * 6)
	if not self:walkTo(approach, "floor") then return false end
	local waited = 0
	while door.part.CanCollide ~= false do
		if self:phase() ~= "floor" then return false end
		waited += TICK
		if waited > 5 then error("Bot: door " .. door.name .. " never opened with the player 6 studs from it") end
		self:tick()
	end
	self.stats.doorsOpened += 1
	local other = Vector3.new(leaf.X + dir.X * CELL / 2, 3, leaf.Z + dir.Z * CELL / 2)
	if not self:walkTo(Vector3.new(leaf.X, 3, leaf.Z), "floor") then return false end
	return self:walkTo(other, "floor")
end

function Bot:itemsIn(rooms)
	local out = {}
	for id, r in rooms do
		for _, name in { "Fuse", "Cell" } do
			local part = r.folder:FindFirstChild(name)
			if part then table.insert(out, { room = id, part = part, kind = name }) end
		end
	end
	return out
end

-- Play one floor until its elevator powers (returns "powered"), the player dies ("dead"), or
-- time runs out. opts.exploreAll opens every door before going to the exit.
function Bot:clearFloor(opts)
	opts = opts or {}
	local started = self.stats.seconds
	local skipCells = {}
	local stale = 0
	while true do
		if self.stats.seconds - started > self.maxSeconds then return "timeout" end
		local st = self:state()
		if not st or st.phase ~= "floor" then return st and st.phase == "dying" and "dead" or tostring(st and st.phase) end
		local run = st.run
		local rooms = self:rooms()
		local doors = self:doors()
		local p = self:pos()
		local here = self:roomAt(rooms, p)
		if not here then error("Bot: standing in no built room at " .. tostring(p)) end
		if run.powered then
			-- The elevator can power while the player is only passing through its room on the way
			-- to something else; the choice is only accepted standing there, so go back.
			local exitRoom = self:exitRoom(rooms)
			if exitRoom and here ~= exitRoom then
				local path = self:route(rooms, doors, here, exitRoom)
				if not path or not self:followPath(path) then return "dead" end
				local c = rooms[exitRoom].center
				self:walkTo(Vector3.new(c.X, 3, c.Z), "floor")
				self:waitSeconds(0.2, "floor")
			end
			return "powered"
		end

		-- 1. an item in a room we can reach
		local target, targetPath = nil, nil
		for _, it in self:itemsIn(rooms) do
			local want = it.kind == "Fuse" or (it.kind == "Cell" and run.battery < run.batteryCap - 0.5 and not skipCells[it.part])
			if want then
				local path = self:route(rooms, doors, here, it.room)
				if path and (targetPath == nil or #path < #targetPath) then target, targetPath = it, path end
			end
		end
		if target then
			if not self:followPath(targetPath) then return self:phase() == "dying" and "dead" or "left" end
			local ip = target.part.Position
			local before = run.fuses
			if not self:walkTo(Vector3.new(ip.X, 3, ip.Z), "floor") then return "dead" end
			self:waitSeconds(0.3, "floor")
			if target.part.Parent ~= nil then
				skipCells[target.part] = true -- a full battery leaves a cell where it is
			elseif target.kind == "Fuse" then
				self.stats.fuses += 1
			else
				self.stats.cells += 1
			end
			local c = rooms[target.room].center
			if not self:walkTo(Vector3.new(c.X, 3, c.Z), "floor") then return "dead" end
			continue
		end

		-- 2. every fuse in hand or in the panel, and the exit is known: go
		local exitRoom = self:exitRoom(rooms)
		local closed = {}
		for _, d in doors do
			if not d.open and (rooms[d.lo] == nil or rooms[d.hi] == nil) then table.insert(closed, d) end
		end
		local haveAll = (run.fuses + run.fusesIn) >= run.fusesNeeded
		if exitRoom and haveAll and (not opts.exploreAll or #closed == 0) then
			local path = self:route(rooms, doors, here, exitRoom)
			if not path then error("Bot: exit room " .. exitRoom .. " is built but unreachable") end
			if not self:followPath(path) then return "dead" end
			local waited = 0
			while self:phase() == "floor" and not self:state().run.powered do
				waited += TICK
				if waited > 3 then error("Bot: stood in the exit room with every fuse and nothing powered") end
				self:tick()
			end
			continue
		end

		-- 3. the nearest closed door out of the known map
		local best, bestPath, bestFrom = nil, nil, nil
		for _, d in closed do
			local from = rooms[d.lo] and d.lo or d.hi
			local path = self:route(rooms, doors, here, from)
			if path and (bestPath == nil or #path < #bestPath) then best, bestPath, bestFrom = d, path, from end
		end
		if not best then
			-- State is pushed every 0.2 s but a picked-up fuse's Part is destroyed at once, so for a
			-- moment the workspace has no fuse left while the counter still says one is missing
			-- (found by tests/curve.luau; a probe measured 3 bot errors in 595 floors before this wait and 0
			-- in 600 after). Give the push a beat to land.
			stale += 1
			if stale <= 5 then
				self:tick()
				continue
			end
			error("Bot: nothing left to open and the objective is incomplete (fuses "
				.. tostring(run.fuses) .. "+" .. tostring(run.fusesIn) .. "/" .. tostring(run.fusesNeeded) .. ")")
		end
		stale = 0
		if not self:followPath(bestPath) then return "dead" end
		if not self:openThrough(bestFrom, best) then return "dead" end
	end
end

return Bot
