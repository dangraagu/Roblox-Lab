-- Vault Runners — the flier gate, through the REAL server from the bundle.
-- Run (from robloxemu): luau check_vaultrunners_fliergate.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- Owner decision 2026-10-11: fliers must NOT top the DEEPEST ESCAPES board. `Trace` bounds a runner's
-- speed, not the geometry, so a noclip client goes to the exit through the walls and floors and escapes
-- every vault. src/shared/FlierGate.luau keeps a validated position per run; an escape it cannot follow
-- through the vault is banked exactly as before and is NOT counted for the board.
--
--   (a) a straight-line noclip run to the exit (teleported, and flown at walking pace): the escape is
--       banked, the floor advances, and NOTHING is written to the board's store;
--   (b) an honest run through the corridors and up the shafts: written;
--   and what follows from those: the board counts TRACED escapes only (flying to floor 3 and then walking
--   one vault is depth 1, not 3), it survives a rejoin, an old save keeps its depth, and the player is told once.
--
-- tests/FlierGate.spec.luau holds the gate's own rules and the honest runner's margins. This file holds the
-- WIRING: that the server asks the gate, and that the board, the reach time and the friends view all read
-- what it said. Harness shaped after check_vaultrunners_board.luau.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/vault-runners"), name = "vault-runners", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

local profilesStore = DSS:GetDataStore("VaultRunners_v1")
local function seed(uid, floors, extra)
	local d = { gems = 0, totalBanked = 0, pets = {}, equipped = nil, floors = floors, escapes = 0, wipes = 0 }
	for k, v in extra or {} do d[k] = v end
	profilesStore:SetAsync("u_" .. uid, { data = d })
end
seed(704, { 13, 1, 1 }, { bestAt = 1780000000 })                              -- Old: saved before the gate existed, depth 12
seed(705, { 9, 1, 1 }, { bestAt = 1781000000, traced = { 4, 1, 1 } })         -- Mix: cleared 8 Bronze floors, 3 of them traced
seed(706, { 3, 1, 1 }, { bestAt = 1782000000, traced = { 50, 1, 1 } })        -- Odd: a record claiming more traced than cleared
seed(708, { 1, 1, 1 }, { totalBanked = 9000 })                                 -- Wes: Gold is open, nothing cleared

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local Progression = h:_require(RS:FindFirstChild("Progression"))
local VaultFloor = h:_require(RS:FindFirstChild("VaultFloor"))
local VaultPath = h:_require(RS:FindFirstChild("VaultPath"))
local MazeGen = h:_require(RS:FindFirstChild("MazeGen"))
local Rng = h:_require(RS:FindFirstChild("Rng"))
local bc = Config.Board

local gateModule = RS:FindFirstChild("FlierGate")
truthy(gateModule ~= nil, "the bundle carries the FlierGate module")
truthy(type(Config.Gate) == "table", "and Config.Gate")

local lb = DSS:GetOrderedDataStore(Config.Save.Board)
local writes = 0
do
	local oUpdate, oSet = lb.UpdateAsync, lb.SetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
end
local function stored(uid) return lb.__data["u_" .. uid] end
local function depthOf(uid)
	local v = stored(uid)
	if type(v) ~= "number" then return nil end
	return (Board.decode(v))
end

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(1)
	return p
end

local remotes = RS:FindFirstChild("VaultRemotes")
local Enter = remotes:FindFirstChild("Enter")
local RunRemote = remotes:FindFirstChild("Run")
local ToastRemote = remotes:FindFirstChild("Toast")
local vaults = h.workspace:FindFirstChild("Vaults")

local function lastRunEvent(plr, kind)
	local sent = RunRemote:sentTo(plr)
	for i = #sent, 1, -1 do
		if sent[i].args[1] == kind then return sent[i].args[2], i end
	end
	return nil, 0
end
-- the one line that tells a player their escape was not ranked (the number in it varies)
local untracedText = bc.Text and bc.Text.Untraced
local untracedNeedle = type(untracedText) == "string" and string.match(untracedText, "[Nn]ot on the board[^%%]*") or "\0no such text"
local function toldUntraced(plr)
	local n = 0
	for _, rec in ToastRemote:sentTo(plr) do
		if type(rec.args[1]) == "string" and string.find(rec.args[1], untracedNeedle, 1, true) then n += 1 end
	end
	return n
end
local function savedData(uid)
	local rec = profilesStore:GetAsync("u_" .. uid)
	return rec and rec.data
end
local function num(t, i) return t and tonumber(t[i] or t[tostring(i)]) end

local W = Config.Movement.WalkSpeed
local DT = Config.Ascent.SampleSeconds
local ROOT = Config.Run.RunnerRootHeight
local HS = Config.Vault.StoreyHeight

local function vaultOf(plr) return vaults:FindFirstChild("Vault_" .. plr.UserId) end
local function enter(plr, tier)
	local _, endsBefore = lastRunEvent(plr, "end")
	Enter:simulateFireServer(plr, tier)
	h:advance(0.4)
	local v = vaultOf(plr)
	if v == nil then return nil end
	local f0 = v:FindFirstChild("Floor_0")
	return {
		plr = plr, vault = v, endsBefore = endsBefore,
		hrp = plr.Character:FindFirstChild("HumanoidRootPart"),
		origin = f0.Position + Vector3.new(0, Config.Vault.FloorThickness / 2, 0),
		floor = v:GetAttribute("Floor"), tier = tier,
	}
end
local function ended(run, waitSeconds)
	for _ = 1, math.ceil((waitSeconds or 0) / 0.5) + 1 do
		local e, i = lastRunEvent(run.plr, "end")
		if i > run.endsBefore then return e end
		h:advance(0.5)
	end
	return nil
end

-- (a) THE FLIERS.
-- teleport: write the root part onto the exit and wait for the trusted position to get there.
local function teleportRun(plr, tier)
	local run = enter(plr, tier)
	if not run then return nil end
	run.hrp.CFrame = CFrame.new(run.vault:FindFirstChild("ExitPad").Position + Vector3.new(0, ROOT - 0.5, 0))
	return ended(run, 120), run
end
-- noclip: fly from the drop-in to the exit in a STRAIGHT LINE at walking pace, through every wall and floor.
local function noclipRun(plr, tier)
	local run = enter(plr, tier)
	if not run then return nil end
	local target = run.vault:FindFirstChild("ExitPad").Position + Vector3.new(0, ROOT - 0.5, 0)
	for _ = 1, 6000 do
		if vaultOf(plr) == nil then break end
		local cur = run.hrp.Position
		local d = target - cur
		if d.Magnitude < 0.3 then h:advance(DT) else
			local step = math.min(d.Magnitude, W * DT)
			run.hrp.CFrame = CFrame.new(cur + d.Unit * step)
			h:advance(DT)
		end
	end
	return ended(run, 5), run
end

-- (b) THE HONEST RUNNER: cell centre to cell centre along the corridor, pad by pad up every shaft, at
-- WalkSpeed, and never through anything. `opts.lag = { at = seconds, gap = seconds }` stops the root
-- part replicating for `gap` seconds (the runner keeps running; the server sees them jump ahead).
-- `opts.dropAt = storey` drops back down the hole they just climbed out of, once, and climbs again.
-- `opts.throughWalls = true` is NOT honest: the same runner, same speed, same climbs, but every storey is
-- crossed in a straight line from where they came up to the stairwell, through whatever walls are in the way.
local function honestRun(plr, tier, opts)
	opts = opts or {}
	local run = enter(plr, tier)
	if not run then return nil end
	local spec = Progression.difficulty(Config, tier, run.floor)
	spec.seed = Progression.seedFor(Config, tier, run.floor)
	local model = VaultFloor.build(Config, spec, MazeGen, Rng)
	local S = model.cellSize
	local function centre(c) return (2 * c.cx + 1 - model.cells) * S, (2 * c.cy + 1 - model.cells) * S end

	local at = run.hrp.Position - run.origin
	local px, py, pz = at.X, ROOT, at.Z
	local clock = 0
	local function tick()
		clock += DT
		local frozen = opts.lag ~= nil and clock >= opts.lag.at and clock < opts.lag.at + opts.lag.gap
		if not frozen then run.hrp.CFrame = CFrame.new(run.origin + Vector3.new(px, py, pz)) end
		h:advance(DT)
	end
	local function moveTo(x, y, z, up)
		for _ = 1, 4000 do
			if vaultOf(plr) == nil then return end
			local dx, dz, dy = x - px, z - pz, y - py
			local flat = math.sqrt(dx * dx + dz * dz)
			if flat < 1e-6 and math.abs(dy) < 1e-6 then return end
			local m = math.min(flat, W * DT)
			if flat > 1e-6 then px += dx / flat * m; pz += dz / flat * m end
			py += if dy > 0 then math.min(dy, (up or 6) * DT) else dy
			tick()
		end
	end
	local function cross(s, from, to)
		local dist = VaultPath.distances(model, s, from)
		local cells, cur = { to }, to
		local d = dist[to.cy * model.cells + to.cx]
		while d > 0 do
			for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, ny = cur.cx + dd[1], cur.cy + dd[2]
				if nx >= 0 and nx < model.cells and ny >= 0 and ny < model.cells
					and model.grids[s + 1][2 * cur.cy + 1 + dd[2]][2 * cur.cx + 1 + dd[1]] == false
					and dist[ny * model.cells + nx] == d - 1 then
					cur = { cx = nx, cy = ny }; d -= 1
					table.insert(cells, 1, cur)
					break
				end
			end
		end
		for _, c in cells do
			local x, z = centre(c)
			moveTo(x, s * HS + ROOT, z)
		end
	end
	local function climb(s)
		for _, pad in model.shafts[s + 1].pads do
			moveTo(pad.x, pad.y + ROOT, pad.z)
		end
		local x, z = centre(model.exitCells[s + 1])
		moveTo(x, (s + 1) * HS + ROOT, z)
	end
	for s = 0, model.storeys - 1 do
		if opts.throughWalls then
			local x, z = centre(model.exitCells[s + 1])
			moveTo(x, s * HS + ROOT, z)
		else
			cross(s, model.entryCells[s + 1], model.exitCells[s + 1])
		end
		if s < model.storeys - 1 then
			climb(s)
			if opts.dropAt == s then
				-- back down the hole: eighteen studs, straight down, and up the shaft again
				local x, z = centre(model.exitCells[s + 1])
				moveTo(x, s * HS + ROOT, z)
				h:advance(Config.Ascent.RespawnSeconds + Config.Ascent.CrumbleSeconds)   -- (the pads come back)
				clock += Config.Ascent.RespawnSeconds + Config.Ascent.CrumbleSeconds
				climb(s)
			end
		end
	end
	return ended(run, 5), run, model
end

--======================================================================= (a) a flier is not ranked

local Fay = joinAs("Fay", 701)
do
	eq(stored(701), nil, "set-up: Fay has never escaped, and is not on the board")
	local w0 = writes
	local e = teleportRun(Fay, 1)
	truthy(e ~= nil and e.ok and e.reason == "escaped", "a TELEPORT to the exit still escapes: the economy is unchanged (" .. tostring(e and e.reason) .. ")")
	h:advance(Config.Save.FlushTickSeconds + 1)
	local d = savedData(701)
	eq(num(d and d.floors, 1), 2, "her Bronze floor advanced and was saved")
	eq(d and d.escapes, 1, "the escape was counted")
	eq(d and d.gems, e and e.banked, "and what she carried was banked")
	eq(e and e.ranked, false, "the run's end says it was NOT ranked")
	eq(stored(701), nil, "(a) the teleported escape is NOT in the board's store")
	eq(writes, w0, "and the board's store was not written at all")
	eq(toldUntraced(Fay), 1, "she was told why, once")
	eq(num(d and d.traced, 1), 1, "the saved profile counts no traced escape in Bronze")
	eq(d and tonumber(d.bestAt) or 0, 0, "and no reach time was stamped: there is nothing on the board to time")

	-- the straight-line noclip run, at walking pace: no faster than a runner, and through everything
	local e2 = noclipRun(Fay, 1)
	truthy(e2 ~= nil and e2.ok, "a straight-line NOCLIP flight to the exit at walking pace escapes too (" .. tostring(e2 and e2.reason) .. ")")
	h:advance(Config.Save.FlushTickSeconds + 1)
	d = savedData(701)
	eq(num(d and d.floors, 1), 3, "her Bronze floor advanced again")
	eq(e2 and e2.ranked, false, "and that run was not ranked either")
	eq(stored(701), nil, "(a) the noclip escape is NOT in the board's store")
	eq(writes, w0, "still not one write to the board")
	eq(toldUntraced(Fay), 2, "told once per escape, not once per sample")
end

--======================================================================= (b) an honest runner is

local Hal = joinAs("Hal", 702)
do
	local w0 = writes
	local e = honestRun(Hal, 1)
	truthy(e ~= nil and e.ok and e.reason == "escaped", "set-up: Hal walks the corridors and climbs the shafts out of Bronze floor 1 (" .. tostring(e and e.reason) .. ")")
	h:advance(1)
	eq(e and e.ranked, true, "the run's end says it WAS ranked")
	eq(depthOf(702), 1, "(b) the honest escape IS in the board's store, at depth 1")
	eq(writes, w0 + 1, "one write")
	eq(toldUntraced(Hal), 0, "and he was told nothing about tracing")
	local d = savedData(702)
	eq(num(d and d.traced, 1), 2, "the saved profile counts one traced escape in Bronze")
	truthy(d ~= nil and (tonumber(d.bestAt) or 0) > 0, "and the reach time was stamped")
end

--======================================================================= flying deep, then walking once

do
	-- Fay has flown Bronze floors 1 and 2. Now she walks floor 3 honestly.
	local w0 = writes
	local e = honestRun(Fay, 1)
	truthy(e ~= nil and e.ok, "set-up: Fay walks Bronze floor 3 honestly (" .. tostring(e and e.reason) .. ")")
	h:advance(1)
	eq(e and e.ranked, true, "that run is ranked")
	local d = savedData(701)
	eq(num(d and d.floors, 1), 4, "she has cleared three Bronze floors")
	eq(depthOf(701), 1, "and the board holds depth 1 for her, not 3: the two she flew through do not count")
	eq(writes, w0 + 1, "(one write)")
	eq(toldUntraced(Fay), 2, "no new warning for an honest run")

	-- and she flies floor 4: banked, and the board does not move
	local before = stored(701)
	local e2 = teleportRun(Fay, 1)
	truthy(e2 ~= nil and e2.ok, "set-up: she flies Bronze floor 4")
	h:advance(Config.Save.FlushTickSeconds + 1)
	eq(stored(701), before, "a flown escape after a ranked one leaves the board exactly as it was")
	eq(num(savedData(701).floors, 1), 5, "(her floor did advance)")
end

--======================================================================= patience, and walls only

do
	-- PATIENCE. Fly to the top storey, hover out of the collapse's way until the countdown is nearly
	-- spent, then step onto the exit: all the time in the world, and none of the route. The bank is
	-- capped at a few seconds so that time alone cannot buy the vault.
	local Pat = joinAs("Pat", 707)
	local run = enter(Pat, 1)
	local start = lastRunEvent(Pat, "start")
	local pad = run.vault:FindFirstChild("ExitPad").Position
	local far = Vector3.new(2 * run.origin.X - pad.X, pad.Y + ROOT - 0.5, 2 * run.origin.Z - pad.Z)   -- the opposite corner, top storey
	run.hrp.CFrame = CFrame.new(far)
	h:advance(start.collapseSeconds - 12)
	truthy(vaultOf(Pat) ~= nil, "set-up: Pat hovered on the top storey for " .. (start.collapseSeconds - 12) .. " s and the run is still on")
	run.hrp.CFrame = CFrame.new(pad + Vector3.new(0, ROOT - 0.5, 0))
	local e = ended(run, 12)
	truthy(e ~= nil and e.ok, "set-up: and then escaped (" .. tostring(e and e.reason) .. ")")
	h:advance(1)
	eq(e and e.ranked, false, "waiting out the countdown before stepping onto the exit is not ranked: time does not buy the route")
	eq(stored(707), nil, "and is not on the board")

	-- WALLS ONLY. Wes climbs every shaft like a runner and never leaves the floor, but crosses each
	-- storey of Gold floor 1 in a straight line through the maze's walls, at walking pace.
	local Wes = joinAs("Wes", 708)
	local e2, _, model = honestRun(Wes, 3, { throughWalls = true })
	truthy(e2 ~= nil and e2.ok, "set-up: Wes escapes Gold floor 1 walking straight through its walls (" .. tostring(e2 and e2.reason) .. ")")
	local longest = 0
	for _, n in VaultPath.measure(Config, model).walkSteps do longest = math.max(longest, n) end
	truthy(longest >= 14, "set-up: that vault has a storey whose corridor is far longer than the straight line (" .. longest .. " cell steps against 10)")
	h:advance(1)
	eq(e2 and e2.ranked, false, "walking through walls is not ranked, even with every climb done honestly")
	eq(stored(708), nil, "and is not on the board")
	eq(toldUntraced(Wes), 1, "(he was told)")
end

--======================================================================= lag, and a drop down the hole

do
	local Lia = joinAs("Lia", 703)
	-- frozen for four seconds in the middle of the first storey, then suddenly four seconds further on
	local e = honestRun(Lia, 1, { lag = { at = 3, gap = 4 } })
	truthy(e ~= nil and e.ok, "set-up: Lia escapes Bronze floor 1 through a four-second freeze (" .. tostring(e and e.reason) .. ")")
	h:advance(1)
	eq(e and e.ranked, true, "an honest runner who lags out for four seconds is still ranked")
	eq(depthOf(703), 1, "and is on the board")
	-- and again, frozen across the first climb
	local e2 = honestRun(Lia, 1, { lag = { at = 7, gap = 4 }, dropAt = 0 })
	truthy(e2 ~= nil and e2.ok, "set-up: Lia escapes floor 2, with a freeze, and a drop back down the hole (" .. tostring(e2 and e2.reason) .. ")")
	h:advance(1)
	eq(e2 and e2.ranked, true, "a drop back down the stairwell and a second climb are a runner's moves: ranked")
	eq(depthOf(703), 2, "depth 2")
	eq(toldUntraced(Lia), 0, "and she was never told otherwise")
end

--======================================================================= what was saved before, and after

do
	-- a save from before the gate existed keeps the depth it had
	local Old = joinAs("Old", 704)
	eq(depthOf(704), 12, "a profile saved before the gate existed keeps its depth (12) on the board")
	local _ = Old
	-- a profile with eight floors cleared and three of them traced is depth 3
	local Mix = joinAs("Mix", 705)
	eq(depthOf(705), 3, "a returning player's board depth is their TRACED escapes (3), not the floors cleared (8)")
	local _ = Mix
	-- a record that claims more traced escapes than floors cleared is held to the floors
	joinAs("Odd", 706)
	eq(depthOf(706), 2, "a saved count of traced escapes can never exceed the floors actually cleared")

	-- Fay leaves and comes back: the board is offered what was TRACED, again
	local before = stored(701)
	h:leave(Fay)
	h:advance(1)
	lb.__data["u_701"] = nil   -- (as if the board had lost her row)
	Fay = joinAs("Fay", 701)
	eq(depthOf(701), 1, "after a rejoin her saved depth for the board is still 1 (four floors cleared, one traced)")
	local m, t = Board.decode(stored(701))
	local _, tBefore = Board.decode(before)
	eq(t, tBefore, "with the reach time of the ranked escape")
	local _ = m
end

--======================================================================= the friends view reads it too

do
	-- Hal's friends list: Fay (in this server, four floors cleared, one traced). Her row comes from memory.
	Players.GetFriendsAsync = function(_self, _userId)
		local pages = { IsFinished = true }
		function pages:GetCurrentPage() return { { Id = 701, Username = "Fay", DisplayName = "Fay", IsOnline = true } } end
		function pages:AdvanceToNextPageAsync() end
		return pages
	end
	local hub = h.workspace:FindFirstChild("Hub")
	local board = hub and hub:FindFirstChild("DeepestBoard")
	local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
	local boardRemote = remotes:FindFirstChild("Board")
	if prompt then prompt.Triggered:Fire(Hal) end
	h:advance(2)
	local sent = boardRemote:sentTo(Hal)
	local view = sent[#sent] and sent[#sent].args[1]
	truthy(view ~= nil and view.mode == "friends", "set-up: Hal's board is on FRIENDS")
	local fay = nil
	for _, r in (view and view.rows or {}) do if r.userId == 701 then fay = r end end
	eq(fay and fay.depth, 1, "a friend in this server is ranked at her TRACED depth (1), not the floors she flew through (4)")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("vaultrunners fliergate: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("vaultrunners fliergate check failed", 0)
end
