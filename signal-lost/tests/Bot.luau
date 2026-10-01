--!nocheck
-- Bot.luau — a headless PLAYER for SIGNAL LOST, used by tests/walk.luau and the robloxemu checks. Not a spec, not
-- game code.
--
-- It plays only on what a client could know:
--   * the workspace: its own zone's built modules (Sector.Modules.Module_<id> and their Floor), hatch leaves
--     (Sector.Hatches.Hatch_<a>_<b>, open when CanCollide is false), the HatchLamp on each doorway's lintel (AIR or
--     VACUUM behind it), Salvage and Canister parts, the RelayMast, the FloorHatch and the consoles;
--   * its own State pushes (AIR, the SIGNAL bars of the module it is in, the grid size n, the phase) and Notices.
-- It never reads ServerStorage, the plan or a stream. A module it has not opened does not exist for it.
--
-- It moves the way the emulator lets anything move: by writing the root part's CFrame once per 0.1 s tick, at the
-- WalkSpeed the SERVER wrote onto the Humanoid (times speedScale <= 1), and advancing the virtual clock by that tick.
-- It walks module centre -> hatch -> module centre, so every step is one a humanoid could take.

local Bot = {}
Bot.__index = Bot

local TICK = 0.1
local Vector3, CFrame
local CELL = 32
local STAND = 2.51

function Bot.new(h, plr, opts)
	Vector3 = h.instance.datatypes.Vector3
	CFrame = h.instance.datatypes.CFrame
	opts = opts or {}
	local remotes = h.ReplicatedStorage:FindFirstChild("SignalRemotes")
	assert(remotes, "Bot: no SignalRemotes")
	return setmetatable({
		h = h,
		plr = plr,
		remotes = remotes,
		State = remotes:FindFirstChild("State"),
		Notice = remotes:FindFirstChild("Notice"),
		noticeSeen = 0,
		notices = {},
		toasts = {},
		barsAt = {}, -- module id -> bars seen standing in it
		stats = { seconds = 0, vacuumSeconds = 0, salvage = 0, canisters = 0, hatches = 0, minAir = math.huge, modulesEntered = 0 },
		speedScale = math.min(1, opts.speedScale or 1),
		margin = opts.margin or 3,
		onTick = opts.onTick,
		log = opts.log,
	}, Bot)
end

--============================================================ reading

function Bot:state()
	local sent = self.State:getSent()
	for i = #sent, 1, -1 do
		local rec = sent[i]
		if rec.player == self.plr then return rec.args[1] end
	end
	return nil
end

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

function Bot:saw(kind)
	for _, n in self.notices do if n.kind == kind then return n end end
	return nil
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
function Bot:phase()
	local st = self:state()
	return st and st.phase
end

-- This player's zone: the one whose Pod is nearest in X.
function Bot:zone()
	local st = self.h.workspace:FindFirstChild("Station")
	local p = self:pos()
	if not st or not p then return nil end
	local best, bestD = nil, math.huge
	for _, z in st:GetChildren() do
		local pod = z:FindFirstChild("Pod")
		local fl = pod and pod:FindFirstChild("PodFloor")
		if fl then
			local d = math.abs(fl.Position.X - p.X)
			if d < bestD then best, bestD = z, d end
		end
	end
	return best
end

function Bot:sector()
	local z = self:zone()
	return z and z:FindFirstChild("Sector")
end

-- id -> { id, center (floor top), folder, lamps = { [neighbourId] = "AIR" | "VACUUM" }, items = {...} }
function Bot:modules()
	local out = {}
	local sec = self:sector()
	local mods = sec and sec:FindFirstChild("Modules")
	local st = self:state()
	local n = st and st.n or 3
	if not mods then return out end
	for _, f in mods:GetChildren() do
		local id = tonumber(string.match(f.Name, "^Module_(%d+)$"))
		local fl = f:FindFirstChild("Floor")
		if id and fl then
			local rec = { id = id, center = Vector3.new(fl.Position.X, 0, fl.Position.Z), folder = f, lamps = {}, items = {} }
			for _, c in f:GetChildren() do
				local side = string.match(c.Name, "^Wall(%u)_Top$")
				local lamp = c:FindFirstChild("HatchLamp")
				if side and lamp then
					local bar = lamp:FindFirstChild("Lamp")
					local txt = bar and bar:FindFirstChild("Text")
					local nb = if side == "E" then id + 1 elseif side == "W" then id - 1 elseif side == "N" then id + n else id - n
					rec.lamps[nb] = txt and txt.Text or "?"
				end
				if c.Name == "Salvage" or c.Name == "Canister" then
					table.insert(rec.items, c)
				end
			end
			rec.mast = f:FindFirstChild("RelayMast")
			rec.floorHatch = f:FindFirstChild("FloorHatch")
			rec.console = f:FindFirstChild("RelayConsole") or f:FindFirstChild("ReturnConsole")
			out[id] = rec
		end
	end
	return out
end

function Bot:moduleAt(mods, p)
	for id, r in mods do
		if math.abs(p.X - r.center.X) <= CELL / 2 and math.abs(p.Z - r.center.Z) <= CELL / 2 then return id end
	end
	return nil
end

-- Hatch leaves between built modules: "a_b" -> { a, b, open }
function Bot:hatches()
	local out = {}
	local sec = self:sector()
	local hs = sec and sec:FindFirstChild("Hatches")
	if not hs then return out end
	for _, l in hs:GetChildren() do
		local a, b = string.match(l.Name, "^Hatch_(%d+)_(%d+)$")
		if a then out[a .. "_" .. b] = { a = tonumber(a), b = tonumber(b), open = l.CanCollide == false, part = l } end
	end
	return out
end

--============================================================ acting

function Bot:fire(name, ...)
	self.remotes:FindFirstChild(name):simulateFireServer(self.plr, ...)
end

function Bot:tick()
	self.h:advance(TICK)
	self.stats.seconds += TICK
	local st = self:state()
	if st and st.phase == "sector" then
		if st.moduleType == "vacuum" then self.stats.vacuumSeconds += TICK end
		if st.air and st.air < self.stats.minAir then self.stats.minAir = st.air end
	end
	if self.onTick then self.onTick(self) end
	self:drainNotices()
end

function Bot:waitSeconds(s, keepPhase)
	for _ = 1, math.floor(s / TICK + 0.5) do
		if keepPhase and self:phase() ~= keepPhase then return false end
		self:tick()
	end
	return true
end

function Bot:waitPhase(phase, seconds)
	for _ = 1, math.floor(seconds / TICK + 0.5) do
		if self:phase() == phase then return true end
		self:tick()
	end
	return self:phase() == phase
end

-- Walk in a straight line at the server's WalkSpeed, at height `y` above the floor (STAND = standing).
function Bot:walkTo(target, keepPhase, y)
	local guard = 0
	while true do
		guard += 1
		if guard > 4000 then error("Bot:walkTo never arrived") end
		local hrp = self:hrp()
		if not hrp then return false end
		if keepPhase and self:phase() ~= keepPhase then return false end
		local p = hrp.Position
		local flat = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
		local d = flat.Magnitude
		local wantY = y or STAND
		if d < 0.05 then
			if math.abs(p.Y - wantY) > 0.01 then hrp.CFrame = CFrame.new(Vector3.new(p.X, wantY, p.Z)) end
			return true
		end
		local stepLen = math.min(d, self:speed() * self.speedScale * TICK)
		hrp.CFrame = CFrame.new(Vector3.new(p.X + flat.X / d * stepLen, wantY, p.Z + flat.Z / d * stepLen))
		self:tick()
	end
end

-- Walk from the spawn into the LIFT and wait for the ride to start.
function Bot:board()
	local lift = self.h.workspace.Lifeboat.Lift.LiftPad
	if not self:walkTo(Vector3.new(lift.Position.X, 0, lift.Position.Z), "hub") then return false end
	for _ = 1, 40 do
		if self:phase() == "transit" then return true end
		self:tick()
	end
	return self:phase() == "transit"
end

--============================================================ exploring a sector

-- Seconds of vacuum along a path of module ids (the first is where we stand), one full module each.
local function vacCost(self, mods, path, vacSpeed)
	local secs = 0
	for i = 2, #path do
		local m = path[i]
		local kind = mods[m] and self.kindOf[m]
		if kind == "VACUUM" then secs += CELL / vacSpeed + 0.5 end
	end
	return secs
end

-- Plan a route through built modules (BFS on built hatches), then one hop into `target` if given.
function Bot:route(mods, hs, from, to)
	local prev = { [from] = from }
	local q, h = { from }, 1
	local adj = {}
	for _, e in hs do
		if mods[e.a] and mods[e.b] then
			adj[e.a] = adj[e.a] or {}
			adj[e.b] = adj[e.b] or {}
			table.insert(adj[e.a], e.b)
			table.insert(adj[e.b], e.a)
		end
	end
	while h <= #q do
		local a = q[h]; h += 1
		if a == to then break end
		for _, b in adj[a] or {} do
			if prev[b] == nil then prev[b] = a; table.insert(q, b) end
		end
	end
	if prev[to] == nil then return nil end
	local path, c = { to }, to
	while c ~= from do c = prev[c]; table.insert(path, 1, c) end
	return path
end

-- Step from module a's centre, through the hatch toward b, to b's centre.
function Bot:cross(mods, a, b, keepPhase)
	local ca = mods[a] and mods[a].center
	if not ca then return false end
	local st = self:state()
	local n = st and st.n or 3
	local dx = if b == a + 1 then 1 elseif b == a - 1 then -1 else 0
	local dz = if b == a + n then 1 elseif b == a - n then -1 else 0
	local hatch = Vector3.new(ca.X + dx * CELL / 2, 0, ca.Z + dz * CELL / 2)
	if not self:walkTo(Vector3.new(ca.X + dx * (CELL / 2 - 7), 0, ca.Z + dz * (CELL / 2 - 7)), keepPhase) then return false end
	-- the hatch opens as we come within 8 studs; wait for the server's tick if it has not yet
	for _ = 1, 10 do
		local key = math.min(a, b) .. "_" .. math.max(a, b)
		local e = self:hatches()[key]
		if e and e.open then break end
		self:tick()
	end
	if not self:walkTo(hatch + Vector3.new(dx * 1.5, 0, dz * 1.5), keepPhase) then return false end
	local target = Vector3.new(ca.X + dx * CELL, 0, ca.Z + dz * CELL)
	if not self:walkTo(target, keepPhase) then return false end
	self.stats.modulesEntered += 1
	return true
end

function Bot:recordHere()
	local st = self:state()
	local mods = self:modules()
	local p = self:pos()
	local here = p and self:moduleAt(mods, p)
	if here and st and st.phase == "sector" then
		self.barsAt[here] = st.bars
		self.kindOf[here] = if st.moduleType == "vacuum" then "VACUUM" else "AIR"
	end
	return here, mods, st
end

-- Take every item in the module we stand in (a hop for a high salvage piece), canisters only if they help.
function Bot:takeItems(here, mods)
	local rec = mods[here]
	if not rec then return end
	for _, it in rec.items do
		if it.Parent then
			local st = self:state()
			local isCan = it.Name == "Canister"
			if not isCan or (st and st.air and st.air < st.tank - 1) then
				local p = it.Position
				local y = math.max(STAND, p.Y - 3.5)
				self:walkTo(Vector3.new(p.X, 0, p.Z), "sector", y)
				self:waitSeconds(0.3, "sector")
				self:walkTo(Vector3.new(p.X, 0, p.Z), "sector", STAND)
				if not it.Parent then
					if isCan then self.stats.canisters += 1 else self.stats.salvage += 1 end
				end
			end
		end
	end
end

-- Refill in the air module we stand in.
function Bot:refill()
	for _ = 1, 40 do
		local st = self:state()
		if not st or st.phase ~= "sector" or st.moduleType ~= "air" or st.air >= st.tank - 0.05 then return end
		self:tick()
	end
end

-- Play the sector until it is spliced, the player blacks out, or `seconds` pass. Returns "spliced" | "blackout" |
-- "timeout" | "phase".
function Bot:playSector(seconds)
	return self:explore(seconds, "relay")
end

-- Open EVERY module of the sector (nearest frontier first, air-safe), splicing on the way if the route passes the
-- mast. Returns "done" (nothing left to open) | "blackout" | "timeout" | "phase".
function Bot:exploreAll(seconds)
	return self:explore(seconds, "all")
end

function Bot:explore(seconds, mode)
	self.kindOf = self.kindOf or {}
	local t0 = self.stats.seconds
	local k = self:state() and self:state().k
	self.kindOf = {}
	self.barsAt = {}
	while self.stats.seconds - t0 < (seconds or 600) do
		local st = self:state()
		if not st or st.phase ~= "sector" then
			return if st and st.phase == "blackout" then "blackout" else "phase"
		end
		if st.spliced and mode == "relay" then return "spliced" end
		local here, mods = self:recordHere()
		if not here then self:tick() continue end
		if not self.skipItems then self:takeItems(here, mods) end -- skipItems: a check that needs pieces left behind
		st = self:state()
		if st.phase ~= "sector" then continue end
		-- the relay in sight: go to its mast
		local relay = nil
		for id, r in mods do if r.mast then relay = id end end
		if relay and mode == "relay" then
			local hs = self:hatches()
			local path = self:route(mods, hs, here, relay)
			if path then
				for i = 2, #path do
					if not self:cross(mods, path[i - 1], path[i], "sector") then break end
				end
				local r = self:modules()[relay]
				if r then self:walkTo(Vector3.new(r.center.X + 2, 0, r.center.Z), "sector") end
				for _ = 1, 40 do
					local s2 = self:state()
					if not s2 or s2.spliced or s2.phase ~= "sector" then break end
					self:tick()
				end
				continue
			end
		end
		-- choose a frontier: an unbuilt neighbour behind a lamp, from the module with the most bars
		local hs = self:hatches()
		local best, bestScore = nil, -math.huge
		for id, r in mods do
			for nb, lamp in r.lamps do
				if not mods[nb] then
					local path = self:route(mods, hs, here, id)
					if path then
						local bars = self.barsAt[id] or 1
						local score = if mode == "all" then -#path * 10 + (if lamp == "AIR" then 5 else 0)
							else bars * 100 - #path * 3 + (if lamp == "AIR" then 20 else 0)
						if score > bestScore then best, bestScore = { from = id, to = nb, lamp = lamp, path = path }, score end
					end
				end
			end
		end
		if not best then
			if mode == "all" then return "done" end
			self:tick()
			continue
		end
		-- air safety: going (vacuum along the way + the new module) and coming back, with a margin
		local vacSpeed = self:state().moduleType == "vacuum" and self:speed() or 12
		local going = vacCost(self, mods, best.path, vacSpeed) + (if best.lamp == "VACUUM" then CELL / vacSpeed + 0.5 else 0)
		local need = 2 * going + self.margin
		st = self:state()
		if best.lamp == "VACUUM" and st.air < need then
			if st.moduleType == "air" and st.air < st.tank - 0.05 then
				self:refill()
				continue
			elseif st.moduleType == "vacuum" then
				-- back to the nearest known air module
				local bestAir, bestPath = nil, nil
				for id in mods do
					if self.kindOf[id] == "AIR" then
						local p = self:route(mods, hs, here, id)
						if p and (bestPath == nil or #p < #bestPath) then bestAir, bestPath = id, p end
					end
				end
				if bestPath then
					for i = 2, #bestPath do
						if not self:cross(mods, bestPath[i - 1], bestPath[i], "sector") then break end
					end
					self:refill()
					continue
				end
			end
			-- a full tank still is not enough: go anyway (the grace is 5 s)
		end
		for i = 2, #best.path do
			if not self:cross(mods, best.path[i - 1], best.path[i], "sector") then break end
		end
		if self:phase() == "sector" then
			self:cross(self:modules(), best.from, best.to, "sector")
			self.stats.hatches += 1
		end
		local _ = k
	end
	return "timeout"
end

-- After the splice: walk to the relay module's console, or to its floor hatch.
function Bot:toRelayPiece(name)
	local mods = self:modules()
	for _, r in mods do
		local piece = r.folder:FindFirstChild(name)
		if piece then
			local p = piece.Position
			local dir = Vector3.new(r.center.X - p.X, 0, r.center.Z - p.Z)
			local off = if dir.Magnitude > 0 then dir.Unit * (if name == "FloorHatch" then 0 else 2.5) else Vector3.new()
			local arrived = self:walkTo(Vector3.new(p.X + off.X, 0, p.Z + off.Z), "sector")
			-- stepping onto the floor hatch starts the ride before the walk "arrives": that is the success
			return arrived or (name == "FloorHatch" and self:phase() == "transit")
		end
	end
	return false
end

return Bot
