-- Steal a Cryptid - the GUARDS, in the real server script: every place a player (or an exploiter,
-- or a slow DataStore) can get something the rules say they cannot.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_guards.luau 2>&1
--
-- ALWAYS re-run wrap.py first. This file reads build/steal-a-cryptid.luau, not the game's src/.
--
-- Each block below is one finding of REVIEW-1 (two reviewer probes run against the first build,
-- re-run by the build pass that wrote this file and confirmed with the numbers quoted in the
-- block). Every block was written BEFORE its fix and watched fail. G15-G24 are the findings of the
-- second review round, recorded in steal-a-cryptid/REVIEW-1.md (A1-A6, B1-B4); each was run against a
-- byte-identical copy of the reviewed build and watched fail there before the game was changed. check_stealacryptid.luau owns
-- "is the world built, parented, reachable"; this file owns "does every guard hold".
--
-- TWO THINGS THIS FILE DOES THAT THE EMULATOR DOES NOT DO BY ITSELF, and why neither is an
-- emulator affordance:
--   * Players join on their OWN THREAD (joinOnThread). Roblox runs a PlayerAdded handler on a
--     fresh thread; `Players:simulateJoin` fires it inline, and a scheduler wait from the main
--     thread only moves the clock without waking anybody. The game's load now retries with a
--     wait between attempts, so an inline join would test a server the engine never runs.
--   * UpdateAsync can be made to YIELD (and then fail). A real UpdateAsync always yields, and on a
--     key written seconds ago it can queue for seconds; the emulator's returns at once, which
--     hides every bug that lives in "the player kept playing while the write was in flight".
--     The wrapper waits on the virtual clock and then calls the emulator's own UpdateAsync, so the
--     store's semantics (JSON round-trip, failure injection) are unchanged.

local Harness = require("./emu/harness")
local Datatypes = require("./emu/datatypes")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Rng = require("../steal-a-cryptid/src/shared/Rng")
local Layout = require("../steal-a-cryptid/src/shared/Layout")
local Heist = require("../steal-a-cryptid/src/shared/Heist")
local Economy = require("../steal-a-cryptid/src/shared/Economy")

local h = Harness.new({
	bundle = require("./build/steal-a-cryptid"),
	name = "steal-a-cryptid guards",
	viewport = { 1280, 720 },
	touch = false,
})
local inst = h.instance
local sched = h.scheduler
local V3, CF = Datatypes.Vector3, Datatypes.CFrame
local ServerStorage = h.game:GetService("ServerStorage")
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function le(a, b, msg)
	if type(a) == "number" and a <= b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want <= " .. tostring(b))
	end
end
local function ge(a, b, msg)
	if type(a) == "number" and a >= b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want >= " .. tostring(b))
	end
end

--============================================================ a DataStore whose writes take time

-- SLOW[key] = { yield = seconds, fail = bool, times = n (nil = every call), when = fn(record)? }
-- `when` sees what the call WOULD commit (the transform run on a scratch copy; the server's
-- transforms are safe to re-run, the emulator's own __retryCount does exactly that) so a rule can
-- pick out one write, e.g. the grant, and let the periodic flushes around it through.
-- COMMITS[key] = every committed record, in commit order (for the write-ordering block)
local SLOW, COMMITS = {}, {}
local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepCopy(x) end
	return out
end
local baseUpdate = (getmetatable(store) :: any).UpdateAsync
store.UpdateAsync = function(self, key, transform)
	local rule = SLOW[key]
	local applies = rule ~= nil and (rule.times == nil or rule.times > 0)
	if applies and rule.when then
		local peek = transform(deepCopy(rawget(self, "__data")[key]))
		applies = peek ~= nil and rule.when(peek)
	end
	if applies then
		if rule.times then rule.times -= 1 end
		rule.started = (rule.started or 0) + 1
		sched:wait(rule.yield)
		rule.finished = (rule.finished or 0) + 1
		if rule.fail then error("guards: modelled write failure after the yield", 0) end
	end
	local out = baseUpdate(self, key, transform)
	COMMITS[key] = COMMITS[key] or {}
	if out ~= nil then table.insert(COMMITS[key], { t = sched:now(), rec = out }) end
	return out
end

local function cages(fill)
	local out = {}
	for i = 1, 9 do out[i] = { sp = "", jar = 0 } end
	for col, c in fill or {} do out[col] = c end
	return out
end
local function seedProfile(uid, data)
	local d = {
		v = 1, essence = 0, savedAt = NOW, cagesUnlocked = 3, tutorial = 4, cages = cages({ [5] = { sp = "jackalope", jar = 0 } }),
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 },
	}
	for k, v in data do d[k] = v end
	store:SetAsync("u_" .. uid, { data = d })
end

-- the lair cells used below are computed from each player's own seed, the way the server does
local function lairOfSeed(uid) return Layout.generateLair(Config, Rng, Layout.lairSeed(Config, uid)) end
local function firstLegal(uid, kind, minRow)
	local L = lairOfSeed(uid)
	for row = minRow or 1, 7 do
		for col = 1, 9 do
			if Layout.validatePlacement(Config, L, col, row, kind) then return col, row end
		end
	end
end
local function firstFence(uid)
	local L = lairOfSeed(uid)
	for col = 1, 9 do
		if Layout.cellKind(L, col, Config.World.LairFenceRows[1]) == "fence" then return col, Config.World.LairFenceRows[1] end
	end
end

local MINT, DUP, BANK, CARRY, GRAB, ABORT, CHURN, RETRY, FAILALL, HOP, GRANT, GRANT2, TAKE, CLICK =
	424201, 424202, 990011, 880088, 770077, 660066, 777001, 404040, 808080, 626262, 313131, 313132, 515152, 424208

seedProfile(MINT, { essence = 1000 })
seedProfile(CLICK, { essence = 1000 })
local dupL, dupR = firstLegal(DUP, "laser")
local dupFenceC, dupFenceR = firstFence(DUP)
seedProfile(DUP, { essence = 500, traps = {
	Layout.trapString("laser", dupL, dupR), Layout.trapString("laser", dupL, dupR), Layout.trapString("laser", dupL, dupR),
	Layout.trapString("snare", dupL, dupR), Layout.trapString("snare", dupFenceC, dupFenceR),
} })
seedProfile(BANK, {})
seedProfile(CARRY, {})
seedProfile(GRAB, {})
seedProfile(ABORT, {})
seedProfile(CHURN, {})
seedProfile(RETRY, { essence = 123456, cages = cages({ [5] = { sp = "nessie", jar = 0 } }), journal = { "nessie" } })
seedProfile(FAILALL, { essence = 5000000, cagesUnlocked = 7, cages = cages({ [5] = { sp = "bigfoot", jar = 0 } }), journal = { "bigfoot" } })
seedProfile(HOP, { essence = 900 })
seedProfile(GRANT, { essence = 5000 })
seedProfile(GRANT2, { essence = 5000 })
seedProfile(TAKE, { essence = 50 })

--============================================================ boot

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server script loads: " .. tostring(errServer))
if not okServer then
	print(string.format("steal a cryptid guards: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local R = {}
for _, name in { "State", "Toast", "Fx", "Hunt", "LeaveCamp", "Reroll", "Expand", "BuildMode", "TrapAction" } do
	R[name] = remotes:FindFirstChild(name)
end
local lairs = h.workspace:FindFirstChild("Lairs")
local pockets = h.workspace:FindFirstChild("Pockets")

local function descendants(root)
	local out = {}
	local function walk(node)
		for _, c in inst.stateOf(node).children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(root)
	return out
end
local function toastsOf(plr)
	local out = {}
	for _, rec in R.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function toastCount(plr) return #R.Toast:sentTo(plr) end
local function toastSince(plr, n, needle)
	local all = toastsOf(plr)
	for i = n + 1, #all do
		if string.find(string.lower(all[i]), string.lower(needle), 1, true) then return all[i] end
	end
	return nil
end
local function toastsSince(plr, n)
	local all = toastsOf(plr)
	local out = {}
	for i = n + 1, #all do table.insert(out, all[i]) end
	return table.concat(out, " | ")
end
local function stateOf(plr)
	local sent = R.State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function hrpOf(plr)
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function joinOnThread(name, uid)
	local plr = inst.Instance.new("Player")
	plr.Name = name
	plr.UserId = uid
	local pg = inst.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = plr
	plr.Parent = h.Players
	local sig = inst.stateOf(h.Players).signals["PlayerAdded"]
	sig:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, plr)
	return plr
end
local function joinHome(name, uid)
	local plr = joinOnThread(name, uid)
	h:advance(0.5)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	return plr
end

local function plotOf(plr)
	for _, plot in lairs:GetChildren() do
		local lair = plot:FindFirstChild("Lair")
		if lair and string.find(tostring(plot.Sign.Label.Text.Text), plr.Name, 1, true) then
			return plot, lair
		end
	end
end
local function lairOf(plr) local _, lair = plotOf(plr); return lair end
local function footprintInside(part, frame, rect)
	local lp = frame:PointToObjectSpace(part.Position)
	return lp.X > rect.x0 and lp.X < rect.x1 and lp.Z > rect.z0 and lp.Z < rect.z1
end
local function plotFrame(plot) return plot.Floor.CFrame * CF.new(-36, 0.5, -48) end
local function atHome(plr)
	local plot, lair = plotOf(plr)
	local hrp = hrpOf(plr)
	if not (lair and hrp) then return false, math.huge end
	local a = lair.Arrival.Position
	local d = math.sqrt((hrp.Position.X - a.X) ^ 2 + (hrp.Position.Z - a.Z) ^ 2)
	return d <= 4, d
end

local function raidInfo(plr)
	return ServerStorage.RaidInfo:FindFirstChild(tostring(plr.UserId))
end
local function goToBoard(plr)
	local lair = lairOf(plr)
	hrpOf(plr).CFrame = CF.new(lair.HuntBoard.Position + lair.HuntBoard.CFrame.LookVector * 4)
	h:advance(0.1)
end
local function restartWait()
	h:advance((Config.Raid.RestartCooldownSeconds or 0) + 0.1)
end
local function startHunt(plr, tier)
	goToBoard(plr)
	R.Hunt:simulateFireServer(plr, tier)
	local info = raidInfo(plr)
	if not info then return nil end
	local pocket = pockets:FindFirstChild("Pocket_" .. info:GetAttribute("Pocket"))
	return {
		info = info, pocket = pocket, tier = tier, start = sched:now(),
		frame = pocket.Floor.CFrame * CF.new(-36, 0.5, -56),
		camp = Layout.generateCamp(Config, Rng, info:GetAttribute("Seed"), tier),
	}
end
local function claim(plr, raid, x, z)
	hrpOf(plr).CFrame = CF.new(raid.frame:PointToWorldSpace(V3.new(x, Config.World.RootHeight, z)))
end
local function trusted(raid) return raid.info:GetAttribute("TrustedX"), raid.info:GetAttribute("TrustedZ") end
local function leaveCamp(plr)
	R.LeaveCamp:simulateFireServer(plr)
	h:advance(0.2)
end
local function prizeOf(camp)
	for _, c in camp.cages do if c.prize then return c.col, c.sp end end
end

local function bfsPath(camp, from, to)
	local key = Layout.key
	local prev, seen = {}, { [key(from[1], from[2])] = true }
	local q, head = { from }, 1
	while head <= #q do
		local u = q[head]; head += 1
		if u[1] == to[1] and u[2] == to[2] then break end
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nc, nr = u[1] + d[1], u[2] + d[2]
			local k = key(nc, nr)
			if not seen[k] and Layout.cellKind(camp, nc, nr) == "floor" and Layout.trapAt(camp, nc, nr) == nil then
				seen[k] = true; prev[k] = u
				table.insert(q, { nc, nr })
			end
		end
	end
	local k = key(to[1], to[2])
	if not seen[k] then return nil end
	local path = { to }
	while prev[k] do
		table.insert(path, 1, prev[k]); k = key(prev[k][1], prev[k][2])
	end
	return path
end

-- Walk cell centre to cell centre at `speed`, one raid tick at a time. Stops (returns false) the
-- moment the server ends the raid: a character the server sent home is not still in the pocket.
local function walkCells(plr, raid, cells, speed)
	for i = 2, #cells do
		local ax, az = Layout.cellCenter(Config, cells[i - 1][1], cells[i - 1][2])
		local bx, bz = Layout.cellCenter(Config, cells[i][1], cells[i][2])
		local steps = math.ceil((Config.World.CellSize / speed) / Config.Raid.TickSeconds)
		for k = 1, steps do
			if not raidInfo(plr) then return false end
			local f = k / steps
			claim(plr, raid, ax + (bx - ax) * f, az + (bz - az) * f)
			h:advance(Config.Raid.TickSeconds)
		end
	end
	return true
end

-- A tier-1 camp with a TRAP-FREE walk from the gate to the prize's grab cell. Camps are random
-- (a server-only salt), so this retries; failing to find one in 12 camps is itself a failure.
local function huntWithCleanPath(plr, tier)
	for _ = 1, 12 do
		local raid = startHunt(plr, tier)
		if not raid then return nil end
		local prize = prizeOf(raid.camp)
		local path = bfsPath(raid.camp, { Config.World.GateCol, 0 }, { prize, Config.World.CageWalkRow })
		if path then
			raid.path = path
			raid.prize = prize
			return raid
		end
		leaveCamp(plr)
		restartWait()
	end
	return nil
end

-- stand on the prize's grab cell and hold the prompt the honest way
local function holdGrab(plr, raid)
	local anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. raid.prize)
	anchor.Grab.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Camps[raid.tier].hold + 0.05)
	anchor.Grab.Triggered:Fire(plr)
	h:advance(0.1)
	local s = stateOf(plr)
	return s and s.raid and s.raid.carrying ~= nil
end

local function block(name, fn)
	print(name)
	local ok, err = pcall(fn)
	if not ok then
		failed += 1
		print("FAIL: " .. name .. " crashed: " .. tostring(err))
	end
end

--============================================================ G1. a trap cleared through an aliased cell

block("G1. clearing a trap through Layout.key's alias", function()
	-- REVIEW-1 R1-1, measured on the first build: place a laser, clear it at (col + 32, row - 1).
	-- The clear refunded 250 and left the saved string behind; 40 cycles and a rejoin turned a
	-- stored 1 000 Essence into 11 000.
	local p = joinHome("Minter", MINT)
	local col, row = firstLegal(MINT, "laser", 2)
	truthy(col ~= nil, "a legal laser cell in rows 2..7 of Minter's lair")
	R.BuildMode:simulateFireServer(p, true)
	h:advance(0.2)
	R.TrapAction:simulateFireServer(p, col, row, "laser")
	h:advance(0.2)
	eq(stateOf(p).essence, 750, "placing a laser costs 250")
	eq(stateOf(p).lasers, 1, "...and it is placed")
	do
		-- G12's rule in a lair: a placed laser's cell is visible while its net is off
		local plot, lair = plotOf(p)
		local net = lair.Traps:FindFirstChild("Laser_" .. col .. "_" .. row)
		local visible = 0
		for _, d in descendants(lair.Traps) do
			if d:IsA("BasePart") and d ~= net and d.Transparency < 1 and d.CanCollide == false
				and footprintInside(d, plotFrame(plot), Layout.cellRect(Config, col, row)) then
				visible += 1
			end
		end
		truthy(visible >= 1, "G12: a laser placed in a lair has a visible, walk-through marker besides its net")
	end
	for _, alias in { { col + 32, row - 1 }, { col - 32, row + 1 }, { col + 0.5, row }, { col, 0 }, { col, 8 } } do
		local n = toastCount(p)
		R.TrapAction:simulateFireServer(p, alias[1], alias[2], "clear")
		h:advance(0.2)
		eq(stateOf(p).essence, 750, string.format("clear at (%s, %s) refunds nothing", tostring(alias[1]), tostring(alias[2])))
		eq(stateOf(p).lasers, 1, "...and the laser is still there")
		truthy(toastCount(p) > n and toastSince(p, n, "cleared") == nil, "...and the player is told why: " .. toastsSince(p, n))
	end
	local peak = 750
	for _ = 1, 10 do
		R.TrapAction:simulateFireServer(p, col, row, "laser")
		R.TrapAction:simulateFireServer(p, col + 32, row - 1, "clear")
		h:advance(0.26)
		peak = math.max(peak, stateOf(p).essence)
	end
	eq(peak, 750, "ten place + alias-clear cycles never raise Essence")
	R.TrapAction:simulateFireServer(p, col, row, "clear")
	h:advance(0.2)
	eq(stateOf(p).essence, 1000, "clearing at the laser's own cell refunds it")
	h:advance(Config.Save.FlushTickSeconds + 1)
	local rec = store:GetAsync("u_" .. MINT)
	eq(#rec.data.traps, 0, "the store holds no trap strings")
	h:leave(p)
	h:advance(1)
	local back = joinOnThread("Minter", MINT)
	h:advance(1)
	eq(stateOf(back).essence, 1000, "a rejoin mints nothing")
	h:leave(back)
	h:advance(1)
end)

block("G1b. a save naming one cell several times", function()
	-- The only way a save names a cell twice is a desync like G1's. Only the FIRST string for a cell
	-- is ever refunded, and a string on a cell the rules now reject (a fence) is refunded once.
	local p = joinOnThread("Doubler", DUP)
	h:advance(1)
	local s = stateOf(p)
	eq(s.lasers, 1, "the first laser string for the cell is kept")
	eq(s.snares, 0, "the snare string for the same cell is not")
	eq(s.essence, 500 + Config.Traps.SnarePrice, "only the snare on a fence cell is refunded (+100), none of the copies")
	h:leave(p)
	h:advance(1)
end)

--============================================================ G2. a banked jump through an ON net

block("G2. a jump claimed the tick after a net is painted ON", function()
	-- REVIEW-1 R1-4, measured on the first build: 0 of 4 jumps caught, 4 of 4 honest walks caught.
	local p = joinHome("Banker", BANK)
	local tried, caught = 0, 0
	for _ = 1, 12 do
		if tried >= 3 then break end
		local raid = startHunt(p, 1)
		if not raid then break end
		local laser
		for _, t in Layout.traps(raid.camp) do if t.kind == "laser" then laser = t end end
		local path = bfsPath(raid.camp, { 5, 0 }, { laser.col, laser.row - 1 })
		if not path then
			leaveCamp(p)
			restartWait()
		else
			tried += 1
			walkCells(p, raid, path, 16)
			local x = Layout.cellCenter(Config, laser.col, laser.row)
			local d = Layout.dangerRect(Config, raid.camp, laser.col, laser.row)
			local _, zBelow = Layout.cellCenter(Config, laser.col, laser.row - 1)
			for z = zBelow, d.z0 - 0.5, 1 do claim(p, raid, x, z); h:advance(0.1) end
			claim(p, raid, x, d.z0 - 0.5)
			local net = raid.pocket.Traps:FindFirstChild("Laser_" .. laser.col .. "_" .. laser.row)
			local guard = 0
			while net.Transparency ~= 1 and guard < 100 do h:advance(0.1); guard += 1 end
			while not (net.Transparency < 0.5 and net.Color.R > 0.9 and net.Color.G < 0.3) and guard < 200 do h:advance(0.1); guard += 1 end
			local n = toastCount(p)
			claim(p, raid, x, d.z0 - 0.5 + 10.7)
			h:advance(1.0)
			if toastSince(p, n, "caught by a laser net") then caught += 1 end
			if raidInfo(p) then leaveCamp(p) end
			restartWait()
		end
	end
	eq(tried, 3, "three camps with a trap-free walk to their net")
	eq(caught, tried, "every jump across a net painted ON is caught")
	h:leave(p)
	h:advance(1)
end)

--============================================================ G3/G4. escaping through the fence; collecting mid-raid

block("G3. a carrier pushed into the front fence away from the gate", function()
	-- REVIEW-1 R1-5, measured on the first build: carrying from cell (9,1) into the front fence
	-- escaped, 4 cells (2.7 s at carry speed) short of the gate.
	local p = joinHome("Carrier", CARRY)
	local done = false
	for _ = 1, 12 do
		if done then break end
		local raid = huntWithCleanPath(p, 1)
		truthy(raid ~= nil, "a tier-1 camp with a clean path to its prize")
		if not raid then return end

		-- G4 first, while the raid is fresh: the Collect Pad pays nothing mid-raid
		local lair = lairOf(p)
		h:advance(3)
		local e0 = stateOf(p).essence
		local n4 = toastCount(p)
		hrpOf(p).CFrame = CF.new(lair.CollectPad.Position + V3.new(0, 3, 0))
		lair.CollectPad.Touched:Fire(hrpOf(p))
		eq(stateOf(p).essence, e0, "G4: stepping on the Collect Pad during a raid collects nothing")
		truthy(toastSince(p, n4, "hunt") ~= nil, "G4: ...and says why: " .. toastsSince(p, n4))
		claim(p, raid, 36, 20)
		h:advance(1.5)

		walkCells(p, raid, raid.path, 16)
		truthy(holdGrab(p, raid), "holding the grab on the grab cell carries the prize")
		-- a row-1 cell away from the gate, reachable trap-free, from which the gate is reachable
		local best
		for c = 1, 9 do
			if c ~= 5 and Layout.cellKind(raid.camp, c, 1) == "floor" and Layout.trapAt(raid.camp, c, 1) == nil then
				local there = bfsPath(raid.camp, { raid.prize, 8 }, { c, 1 })
				local back = bfsPath(raid.camp, { c, 1 }, { 5, 0 })
				if there and back and (not best or math.abs(c - 5) > math.abs(best.col - 5)) then
					best = { col = c, there = there, back = back }
				end
			end
		end
		if not best then
			leaveCamp(p)
			restartWait()
		else
			done = true
			walkCells(p, raid, best.there, 12)
			local bx = Layout.cellCenter(Config, best.col, 1)
			for _ = 1, 20 do
				if not raidInfo(p) then break end
				claim(p, raid, bx, 10) -- straight into the solid front fence
				h:advance(Config.Raid.TickSeconds)
			end
			truthy(raidInfo(p) ~= nil, string.format("pressing into the front fence from (%d,1) does not end the raid", best.col))
			eq(stateOf(p).stats.steals, 0, "...and steals nothing")
			if raidInfo(p) then
				local _, tz = trusted(raid)
				ge(tz, 23, "...the trusted position stops 1 stud into the fence")
				claim(p, raid, bx, Layout.cellRect(Config, best.col, 1).z0 + 4)
				h:advance(1)
				walkCells(p, raid, best.back, 12)
				h:advance(0.3)
				eq(stateOf(p).stats.steals, 1, "walking out through the gate steals the prize")
			end
		end
	end
	truthy(done, "found a camp with a row-1 cell off the gate column")
	h:leave(p)
	h:advance(1)
end)

--============================================================ G5. the grab hold

block("G5. the grab hold is paid standing on the grab cell", function()
	-- REVIEW-1, measured on the first build: a grab prompt fired from 15.78 studs away, while still
	-- walking in, completed on arrival after 0.10 s of standing against a 1.0 s hold.
	local p = joinHome("Grabber", GRAB)
	local hold = Config.Camps[1].hold
	local raid = huntWithCleanPath(p, 1)
	truthy(raid ~= nil, "a tier-1 camp with a clean path to its prize")
	if not raid then return end
	local anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. raid.prize)
	local grabCell = raid.path[#raid.path]
	local short = table.clone(raid.path)
	table.remove(short)
	walkCells(p, raid, short, 16)
	-- (a) fired one cell short of the grab cell, then walk on and stand: nothing is carried
	local n = toastCount(p)
	anchor.Grab.Triggered:Fire(p)
	h:advance(0.05)
	truthy(toastSince(p, n, "in front of the cage") ~= nil, "(a) a grab fired off the grab cell is refused at once: " .. toastsSince(p, n))
	walkCells(p, raid, { short[#short], grabCell }, 16)
	h:advance(hold + 0.3)
	local s = stateOf(p)
	truthy(s.raid and not s.raid.carrying, "(a) ...and walking onto the cell afterwards carries nothing")

	-- (b) fired on the cell with no hold (fireproximityprompt): the whole hold is charged
	anchor.Grab.Triggered:Fire(p)
	h:advance(hold - 0.2)
	truthy(not stateOf(p).raid.carrying, "(b) a no-hold grab on the cell is not carrying before the hold has passed")
	h:advance(0.4)
	truthy(stateOf(p).raid and stateOf(p).raid.carrying ~= nil, "(b) ...and is carrying once it has")
	leaveCamp(p)
	restartWait()

	-- (c) a no-hold grab on the cell, then a step off the cell and back inside the hold
	raid = huntWithCleanPath(p, 1)
	truthy(raid ~= nil, "a second tier-1 camp")
	if not raid then return end
	anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. raid.prize)
	walkCells(p, raid, raid.path, 16)
	local gx, gz = Layout.cellCenter(Config, raid.prize, 8)
	anchor.Grab.Triggered:Fire(p)
	h:advance(0.1)
	-- step 7 studs toward the cell the path came from (trap-free floor by construction; a first
	-- version stepped straight down into row 7 and, on a camp with a snare there, got the raider
	-- caught: 1 flaky run in 10) - 3 studs past the grab cell's edge - and straight back
	local prev = raid.path[#raid.path - 1]
	local px, pz = Layout.cellCenter(Config, prev[1], prev[2])
	local ux, uz = (px - gx) / 8, (pz - gz) / 8
	for _, k in { 2, 4, 6, 7, 6, 4, 2, 0 } do
		claim(p, raid, gx + ux * k, gz + uz * k)
		h:advance(0.1)
	end
	h:advance(hold)
	truthy(stateOf(p).raid and not stateOf(p).raid.carrying, "(c) stepping off the grab cell mid-hold cancels the grab")
	-- (d) the honest hold still works
	truthy(holdGrab(p, raid), "(d) HoldBegan on the cell, a full hold, Triggered: carrying")
	leaveCamp(p)
	restartWait()

	-- (e) an honest player who presses on the very tick they step into the grab spot. The server reads
	-- positions once per raid tick, so its trusted position reaches the spot up to a tick AFTER the
	-- HoldBegan arrives; that press must still count, from the moment the server sees them arrive.
	-- (REVIEW-1.md B2 made the spot a 5-stud disc round the anchor. This block first pressed on entering
	-- the grab CELL, which the disc reaches a stud earlier, so the press no longer came early and
	-- sweep mutation M08 survived. It now presses on entering the disc, and checks the server had not.)
	raid = huntWithCleanPath(p, 1)
	truthy(raid ~= nil, "a third tier-1 camp")
	if not raid then return end
	anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. raid.prize)
	short = table.clone(raid.path)
	table.remove(short)
	walkCells(p, raid, short, 16)
	local ax, az = Layout.cellCenter(Config, short[#short][1], short[#short][2])
	gx, gz = Layout.cellCenter(Config, raid.prize, 8)
	local pressedAt, serverHadIt = nil, nil
	for k = 1, 5 do
		local x, z = ax + (gx - ax) * k / 5, az + (gz - az) * k / 5
		claim(p, raid, x, z)
		if not pressedAt and (x - gx) ^ 2 + (z - gz) ^ 2 <= anchor.Grab.MaxActivationDistance ^ 2 then
			local tx, tz = trusted(raid)
			serverHadIt = (tx - gx) ^ 2 + (tz - gz) ^ 2 <= anchor.Grab.MaxActivationDistance ^ 2
			anchor.Grab.PromptButtonHoldBegan:Fire(p)
			pressedAt = sched:now()
		end
		h:advance(0.1)
	end
	truthy(pressedAt ~= nil, "(e) the walker pressed as it stepped into the prompt's reach")
	eq(serverHadIt, false, "(e) ...a tick before the server's trusted position got there")
	h:advance(math.max(0, pressedAt + hold + 0.02 - sched:now()))
	anchor.Grab.Triggered:Fire(p)
	h:advance(0.25)
	truthy(stateOf(p).raid and stateOf(p).raid.carrying ~= nil, "(e) a press on the tick of arrival grabs within a raid tick of the client's full hold")
	leaveCamp(p)
	h:leave(p)
	h:advance(1)
end)

--============================================================ G6. a raid ended by a respawn or a death

block("G6. a raid ended by a respawn or a death says so", function()
	-- REVIEW-1 (reach lens), measured on the first build: a respawn or a death mid-raid ended it
	-- with no toast at all, and the permit gone.
	local p = joinHome("Unlucky", ABORT)
	local raid = startHunt(p, 1)
	truthy(raid ~= nil, "a tier-1 raid")
	local n = toastCount(p)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	eq(raidInfo(p), nil, "a respawn ends the raid")
	truthy(toastSince(p, n, "hunt") ~= nil, "...and tells the player: " .. toastsSince(p, n))
	local home, d = atHome(p)
	truthy(home, string.format("...and the respawned character lands home (%.2f studs from the marker)", d))
	restartWait()
	raid = startHunt(p, 1)
	truthy(raid ~= nil, "another tier-1 raid")
	n = toastCount(p)
	local hum = p.Character:FindFirstChildOfClass("Humanoid")
	hum:TakeDamage(1000)
	h:advance(0.3)
	eq(raidInfo(p), nil, "a death ends the raid")
	truthy(toastSince(p, n, "hunt") ~= nil, "...and tells the player: " .. toastsSince(p, n))
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	truthy((atHome(p)), "...and the next character lands home")
	h:leave(p)
	h:advance(1)
end)

--============================================================ G7. churn

block("G7. how much a client can make the server build", function()
	-- REVIEW-1, measured on the first build: a Hunt(1) + LeaveCamp loop built 79 pockets (491 parts
	-- a second) in 10 s, and BuildMode(true) spam rebuilt every tile 80 times (352 parts a second).
	local p = joinHome("Churner", CHURN)
	local board = lairOf(p).HuntBoard
	local seen, n0 = {}, toastCount(p)
	local t0 = sched:now()
	while sched:now() - t0 < 10 do
		hrpOf(p).CFrame = CF.new(board.Position + board.CFrame.LookVector * 4)
		R.Hunt:simulateFireServer(p, 1)
		local info = raidInfo(p)
		if info then seen[info] = true end
		h:advance(0.0625)
		R.LeaveCamp:simulateFireServer(p)
		h:advance(0.0625)
	end
	local built = 0
	for _ in seen do built += 1 end
	local cd = Config.Raid.RestartCooldownSeconds or 0
	print(string.format("   Hunt/LeaveCamp spam for 10 s built %d pockets (restart cooldown %.1f s)", built, cd))
	-- written out, not read from Config: a 3 s restart cooldown allows at most 10 / 3 + 1 = 4.33
	le(built, 5, "a hunt restart cooldown bounds pocket builds to one per 3 s")
	ge(built, 2, "...and still lets a player hunt again")
	truthy(toastSince(p, n0, "again in") ~= nil, "...and a refused hunt says when")
	h:advance(1.2)

	R.BuildMode:simulateFireServer(p, true)
	h:advance(0.2)
	local lair = lairOf(p)
	local first = lair:FindFirstChild("BuildTiles")
	truthy(first ~= nil, "build mode builds its tiles")
	for _ = 1, 16 do
		R.BuildMode:simulateFireServer(p, true)
		h:advance(0.13)
	end
	eq(lair:FindFirstChild("BuildTiles"), first, "BuildMode(true) while already on rebuilds nothing")
	local rebuilds, last = 0, first
	t0 = sched:now()
	local on = false
	while sched:now() - t0 < 10 do
		R.BuildMode:simulateFireServer(p, on)
		on = not on
		h:advance(0.125)
		local tiles = lair:FindFirstChild("BuildTiles")
		if tiles and tiles ~= last then rebuilds += 1 end
		last = tiles or last
	end
	print(string.format("   BuildMode on/off spam for 10 s rebuilt the tiles %d times", rebuilds))
	le(rebuilds, 11, "toggling build mode rebuilds the tiles at most once a second")
	R.BuildMode:simulateFireServer(p, false)
	h:leave(p)
	h:advance(1)
end)

--============================================================ G8/G9. loading

block("G8. a load that fails once", function()
	-- REVIEW-1, measured on the first build: ONE failed UpdateAsync at join gave a veteran a blank
	-- 30-Essence profile for the whole session, with canSave false.
	store.__failNext = true
	local p = joinOnThread("Veteran", RETRY)
	h:advance(6)
	local s = stateOf(p)
	truthy(s ~= nil, "the profile loaded")
	eq(s and s.canSave, true, "one transient failure is retried: the session saves")
	eq(s and s.essence, 123456, "...with the real profile")
	h:leave(p)
	h:advance(1)
end)

block("G8b. a load that never succeeds", function()
	store.__failAll = true
	local p = joinOnThread("Stranded", FAILALL)
	h:advance(10)
	store.__failAll = false
	local s = stateOf(p)
	truthy(s ~= nil, "the lair still loads (in memory)")
	eq(s and s.canSave, false, "a profile that could not be read is never written")
	truthy(s and string.find(string.lower(tostring(s.saveBanner)), "could not be loaded", 1, true) ~= nil,
		"...and the banner says the save could not be loaded: " .. tostring(s and s.saveBanner))
	h:advance(130)
	h:leave(p)
	h:advance(1)
	local rec = store:GetAsync("u_" .. FAILALL)
	eq(rec.data.essence, 5000000, "the real save is untouched")
	eq(rec.jobId, nil, "...and carries no lock")
end)

block("G9. leaving while the load is still in flight", function()
	-- REVIEW-1, measured with a yielding UpdateAsync: the lock this server took stayed behind for
	-- 120 s, so the player's next server played them unsaved.
	SLOW["u_" .. HOP] = { yield = 1.0, times = 1 }
	local p = joinOnThread("Hopper", HOP)
	h:advance(0.3)
	h:leave(p)
	h:advance(3)
	SLOW["u_" .. HOP] = nil
	local rec = store:GetAsync("u_" .. HOP)
	eq(rec.jobId, nil, "a player who left during the load leaves no lock behind")
	eq(rec.data.essence, 900, "...and the save is unchanged")
end)

--============================================================ G10. the grant's write takes time

local function walkPlanned(plr, raid, plan, onTick)
	local anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. prizeOf(raid.camp))
	local hold = Config.Camps[raid.tier].hold
	local began, fired = false, false
	local function routeAt(route, t)
		if t <= route[1].t then return route[1].x, route[1].z end
		for i = 2, #route do
			local a, b = route[i - 1], route[i]
			if t <= b.t then
				local f = if b.t > a.t then (t - a.t) / (b.t - a.t) else 1
				return a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
			end
		end
		return route[#route].x, route[#route].z
	end
	local start = sched:now()
	while sched:now() - start < plan.total + 3 do
		local tNext = sched:now() - start + Config.Raid.TickSeconds
		local x, z = routeAt(plan.route, tNext)
		claim(plr, raid, x, z)
		if not began and tNext >= plan.inTime + 0.05 then
			anchor.Grab.PromptButtonHoldBegan:Fire(plr)
			began = true
		end
		h:advance(Config.Raid.TickSeconds)
		if began and not fired and sched:now() - start >= plan.inTime + 0.05 + hold then
			anchor.Grab.Triggered:Fire(plr)
			fired = true
		end
		if onTick and onTick() then return true end
		if not raidInfo(plr) then return true end
	end
	return false
end

block("G10. a grant whose write yields, then fails", function()
	-- REVIEW-1, measured with a yielding UpdateAsync on the first build: while the grant's write
	-- was in flight the pocket was already destroyed (the character stood over nothing), a tier-2
	-- hunt could start, and the rollback restored a snapshot taken before the write, clobbering
	-- the permit that hunt spent and every jar that filled meanwhile.
	local p = joinHome("Racer", GRANT)
	local raid = startHunt(p, 2)
	truthy(raid ~= nil, "a tier-2 raid")
	if not raid then return end
	eq(stateOf(p).essence, 5000 - Economy.permit(Config, 2), "the permit is spent at the start")
	local plan = Heist.solveRaid(Config, Layout, raid.camp, { pad = Config.Raid.HumanPad })
	local jarAtEscape = nil
	local escaped = walkPlanned(p, raid, plan, function()
		local s = stateOf(p)
		if s.raid and s.raid.carrying and SLOW["u_" .. GRANT] == nil then
			SLOW["u_" .. GRANT] = { yield = 4.5, fail = true, times = 1, when = function(rec)
				return rec.data and rec.data.stats and rec.data.stats.steals >= 1
			end }
		end
		if s.cages[5] then jarAtEscape = s.cages[5].jar end
		return false
	end)
	truthy(escaped, "the planned route reaches the gate")
	local rule = SLOW["u_" .. GRANT]
	truthy(rule ~= nil and rule.started == 1 and (rule.finished or 0) == 0, "the grant's write is in flight right now")
	local home, d = atHome(p)
	truthy(home, string.format("while the write is in flight the raider already stands at home (%.2f studs off)", d))

	-- try to spend the in-flight grant, and to start another hunt, while the write yields
	local lair = lairOf(p)
	local nT = toastCount(p)
	lair.Cages.Cage_4.Release.Triggered:Fire(p)
	goToBoard(p)
	-- tier 1, not tier 2: the grant already wrote tier 2's Heat into memory, which would refuse a
	-- tier-2 hunt for the wrong reason
	R.Hunt:simulateFireServer(p, 1)
	eq(raidInfo(p), nil, "a hunt fired while the grant is saving starts nothing")
	truthy(toastSince(p, nT, "saving") ~= nil, "...and says the steal is still saving: " .. toastsSince(p, nT))
	-- the write yields 4.5 s; measure 0.5 s after it fails. Income ticks once a second, so a jar that
	-- kept filling holds at least 4 more than the last State before the escape (which is at most one
	-- tick stale), and a jar restored from a pre-write snapshot holds at most 2 more.
	h:advance(4.8)
	SLOW["u_" .. GRANT] = nil
	local s = stateOf(p)
	truthy(toastSince(p, nT, "could not be saved") ~= nil, "the failed write is reported")
	eq(s.essence, 5000, "the permit is refunded exactly once, and nothing else was paid out")
	local rares = 0
	for _, c in s.cages do if Economy.tierOf(Config, c.sp) == 2 then rares += 1 end end
	eq(rares, 0, "the stolen Rare is not in any cage")
	eq(s.stats.steals, 0, "no steal is counted")
	eq(s.camps[2].heatLeft, 0, "no Heat is kept")
	eq(s.journal, 1, "the Journal did not gain the Rare")
	truthy(jarAtEscape ~= nil and s.cages[5].jar >= jarAtEscape + 4,
		string.format("the Jackalope's jar kept filling through the rollback (%.1f at escape, %.1f after)", jarAtEscape or -1, s.cages[5].jar))
	h:leave(p)
	h:advance(1)
end)

block("G10b. a grant written while an older write is still in flight", function()
	-- The periodic flush takes its copy of the profile BEFORE its UpdateAsync yields. If the
	-- grant's write lands first, the older copy lands on top of it and the store loses the steal.
	local p = joinHome("Queuer", GRANT2)
	restartWait()
	local raid = startHunt(p, 2)
	truthy(raid ~= nil, "a tier-2 raid")
	if not raid then return end
	-- the flush tick after the raid start writes the permit spend; make THAT write slow
	SLOW["u_" .. GRANT2] = { yield = 40, times = 1, when = function(rec)
		return rec.data and rec.data.stats and rec.data.stats.steals == 0
	end }
	local plan = Heist.solveRaid(Config, Layout, raid.camp, { pad = Config.Raid.HumanPad })
	truthy(walkPlanned(p, raid, plan), "the planned route reaches the gate")
	local rule = SLOW["u_" .. GRANT2]
	truthy(rule.started == 1, "an older flush was in flight when the steal escaped")
	local guard = 0
	while (rule.finished or 0) < 1 and guard < 600 do h:advance(0.1); guard += 1 end
	h:advance(2)
	SLOW["u_" .. GRANT2] = nil
	local commits = COMMITS["u_" .. GRANT2] or {}
	local stale, grant = nil, nil
	for i, c in commits do
		if c.rec.data.stats.steals == 0 and c.rec.data.essence == 5000 - Economy.permit(Config, 2) then stale = i end
		if c.rec.data.stats.steals == 1 and not grant then grant = i end
	end
	truthy(stale ~= nil and grant ~= nil, string.format("both writes committed (%d commits)", #commits))
	truthy(stale and grant and grant > stale, string.format("the grant is committed AFTER the older write (older #%s, grant #%s)", tostring(stale), tostring(grant)))
	local rec = store:GetAsync("u_" .. GRANT2)
	eq(rec.data.stats.steals, 1, "the store ends holding the steal")
	h:leave(p)
	h:advance(1)
end)

--============================================================ G11. a lock taken over mid-session

block("G11. a lock taken over mid-session turns the banner on", function()
	local p = joinHome("Twin", TAKE)
	eq(stateOf(p).canSave, true, "a fresh session saves")
	local rec = store:GetAsync("u_" .. TAKE)
	rec.jobId = "the-server-that-took-over"
	rec.lockUntil = os.time() + 100
	store:SetAsync("u_" .. TAKE, rec)
	h:advance(3)
	local lair = lairOf(p)
	hrpOf(p).CFrame = CF.new(lair.CollectPad.Position + V3.new(0, 3, 0))
	lair.CollectPad.Touched:Fire(hrpOf(p))
	h:advance(Config.Save.FlushTickSeconds * 2 + 1)
	local s = stateOf(p)
	eq(s.canSave, false, "a session whose lock another server took stops claiming to save")
	truthy(string.find(string.lower(tostring(s.saveBanner)), "another server", 1, true) ~= nil, "...and says why: " .. tostring(s.saveBanner))
	eq(store:GetAsync("u_" .. TAKE).jobId, "the-server-that-took-over", "...and never writes over the other server")
	h:leave(p)
	h:advance(1)
end)

--============================================================ G12-G14. what a client can see and hit

block("G12. an armed gap is visible while its net is off", function()
	-- REVIEW-1, measured on the first build: in 20 of 20 fresh tier-1 camps the armed gap was
	-- named in the workspace (Laser_c_r) while its net was fully transparent. Names carry only
	-- what is visible, so an armed cell must be visible whatever its net is doing.
	local p = joinHome("Looker", BANK + 1)
	local raid = startHunt(p, 3 - 2)
	truthy(raid ~= nil, "a tier-1 raid")
	if not raid then return end
	local lasers = 0
	for _, t in Layout.traps(raid.camp) do
		if t.kind == "laser" then
			lasers += 1
			local net = raid.pocket.Traps:FindFirstChild("Laser_" .. t.col .. "_" .. t.row)
			eq(net and net.Transparency, 1, string.format("laser (%d,%d)'s net is fully off at the start", t.col, t.row))
			local marker = 0
			for _, d in descendants(raid.pocket) do
				if d:IsA("BasePart") and d ~= net and d.Transparency < 1 and d.CanCollide == false
					and footprintInside(d, raid.frame, Layout.cellRect(Config, t.col, t.row)) then
					marker += 1
				end
			end
			truthy(marker >= 1, string.format("laser (%d,%d) has a visible, walk-through marker on its cell besides the net", t.col, t.row))
		end
	end
	ge(lasers, 1, "the camp has a laser")
	leaveCamp(p)
	h:leave(p)
	h:advance(1)
end)

block("G13. a trap never blocks the click on its own build tile", function()
	-- REVIEW-1, measured on the first build: the snare Part (5.5 x 0.4 x 5.5, CanQuery on) covers
	-- 55 % of its tile's top face, so a click on the middle of a snared tile hits the snare, and the
	-- snare can only be cleared by clicking the tile's rim.
	local p = joinHome("Clicker", CLICK)
	local lair = lairOf(p)
	local plot = plotOf(p)
	local sc, sr = firstLegal(CLICK, "snare")
	R.BuildMode:simulateFireServer(p, true)
	h:advance(0.2)
	R.TrapAction:simulateFireServer(p, sc, sr, "snare")
	h:advance(0.2)
	local lc, lr
	do
		local L = lairOfSeed(CLICK)
		Layout.place(Config, L, sc, sr, "snare")
		for row = 1, 7 do
			for col = 1, 9 do
				if not lc and Layout.validatePlacement(Config, L, col, row, "laser") then lc, lr = col, row end
			end
		end
	end
	R.TrapAction:simulateFireServer(p, lc, lr, "laser")
	h:advance(0.2)
	truthy(lair.Traps:FindFirstChild("Snare_" .. sc .. "_" .. sr) ~= nil, "a snare placed through the remote")
	truthy(lair.Traps:FindFirstChild("Laser_" .. tostring(lc) .. "_" .. tostring(lr)) ~= nil, "a laser placed through the remote")
	R.BuildMode:simulateFireServer(p, false)
	h:advance(1.2)
	R.BuildMode:simulateFireServer(p, true)
	h:advance(0.2)
	local frame = plotFrame(plot)
	local blocked = {}
	for _, tile in lair.BuildTiles:GetChildren() do
		local top = tile.Position + V3.new(0, tile.Size.Y / 2, 0)
		for _, d in descendants(plot) do
			if d:IsA("BasePart") and d ~= tile and d.CanQuery ~= false then
				local lp = d.CFrame:PointToObjectSpace(top + V3.new(0, 0.05, 0))
				if math.abs(lp.X) <= d.Size.X / 2 and math.abs(lp.Z) <= d.Size.Z / 2 and d.Position.Y + d.Size.Y / 2 > top.Y then
					table.insert(blocked, tile.Name .. " under " .. d.Name)
				end
			end
		end
	end
	eq(#blocked, 0, "no queryable Part sits over the middle of any build tile: " .. table.concat(blocked, ", "))
	R.BuildMode:simulateFireServer(p, false)
	h:leave(p)
	h:advance(1)
end)

block("G14. an empty cage-row cell in a camp is solid", function()
	-- REVIEW-1 (reach lens), measured on the first build: 1 008-1 080 standing points per camp lay
	-- outside the trusted map, all in row 9 where no cage stands. The trusted position clamps at
	-- the row's edge while the character walks on, then lags behind on the way back.
	local p = joinHome("Wanderer", GRAB + 1)
	local raid = startHunt(p, 1)
	truthy(raid ~= nil, "a tier-1 raid")
	if not raid then return end
	local caged = {}
	for _, c in raid.camp.cages do caged[c.col] = true end
	for col = 1, 9 do
		if not caged[col] then
			local x, z = Layout.cellCenter(Config, col, Config.World.CageRow)
			local world = raid.frame:PointToWorldSpace(V3.new(x, 2, z))
			local solid = false
			for _, d in descendants(raid.pocket) do
				if d:IsA("BasePart") and d.CanCollide ~= false then
					local lp = d.CFrame:PointToObjectSpace(world)
					if math.abs(lp.X) <= d.Size.X / 2 and math.abs(lp.Y) <= d.Size.Y / 2 and math.abs(lp.Z) <= d.Size.Z / 2 then solid = true end
				end
			end
			truthy(solid, string.format("cage-row cell %d holds no cage and is solid", col))
		end
	end
	leaveCamp(p)
	h:leave(p)
	h:advance(1)
end)

--============================================================ REVIEW-1.md B1. a freeze at the corner into a fence gap

-- The trusted step as the 2026-09-17 build had it (a straight move, clamped at the map's edge, no
-- slide). Kept here ONLY to find the freeze phases that locked that build, so the block below keeps
-- testing the geometry that failed whatever the game's step does now. Nothing is asserted with it.
local function oldClip(r, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local s0, s1 = 0, 1
	local ps, qs = { -dx, dx, -dz, dz }, { ax - r.x0, r.x1 - ax, az - r.z0, r.z1 - az }
	for i = 1, 4 do
		local pp, q = ps[i], qs[i]
		if pp == 0 then
			if q < 0 then return nil end
		else
			local u = q / pp
			if pp < 0 then
				if u > s1 then return nil end
				if u > s0 then s0 = u end
			else
				if u < s0 then return nil end
				if u < s1 then s1 = u end
			end
		end
	end
	if s0 > s1 then return nil end
	return s0, s1
end
local function oldStep(t, rects, cx, cz, dt, speed)
	local dx, dz = cx - t.x, cz - t.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= 1e-9 then return end
	local allowed = math.min(dist, speed * Config.Raid.TrustedSpeedFactor * math.min(dt, Config.Raid.MaxTrustedTickSeconds))
	local ux, uz = dx / dist, dz / dist
	local spans = {}
	for _, r in rects do
		local s0, s1 = oldClip(r, t.x, t.z, t.x + ux * allowed, t.z + uz * allowed)
		if s0 then table.insert(spans, { s0, s1 }) end
	end
	local cur = 0
	while cur < 1 do
		local best = cur
		for _, sp in spans do if sp[1] <= cur + 1e-9 and sp[2] > best then best = sp[2] end end
		if best <= cur then break end
		cur = best
	end
	t.x += ux * allowed * math.min(cur, 1)
	t.z += uz * allowed * math.min(cur, 1)
end
-- resample a polyline at `speed` studs/s, one raid tick per point
local function resample(poly, speed)
	local pts = { { poly[1][1], poly[1][2] } }
	local step = speed * Config.Raid.TickSeconds
	local carry = 0
	local marks = {}
	for i = 2, #poly do
		local ax, az, bx, bz = poly[i - 1][1], poly[i - 1][2], poly[i][1], poly[i][2]
		local d = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local pos = step - carry
		while pos <= d + 1e-9 do
			table.insert(pts, { ax + (bx - ax) * pos / d, az + (bz - az) * pos / d })
			pos += step
		end
		carry = d - (pos - step)
		marks[i] = #pts
	end
	local last = poly[#poly]
	if math.abs(pts[#pts][1] - last[1]) + math.abs(pts[#pts][2] - last[2]) > 1e-6 then table.insert(pts, { last[1], last[2] }) end
	return pts, marks
end
-- the freeze offsets around `corner` (a point index) at which the OLD step never reaches the end
local function oldLocks(rects, pts, corner, ticks, speed)
	local out = {}
	for off = -12, 4 do
		local from = corner + off
		if from > 1 and from + ticks <= #pts then
			local t = { x = pts[1][1], z = pts[1][2] }
			for i, p in pts do
				local c = if i >= from and i < from + ticks then pts[from - 1] else p
				oldStep(t, rects, c[1], c[2], Config.Raid.TickSeconds, speed)
			end
			for _ = 1, 30 do oldStep(t, rects, pts[#pts][1], pts[#pts][2], Config.Raid.TickSeconds, speed) end
			if math.sqrt((t.x - pts[#pts][1]) ^ 2 + (t.z - pts[#pts][2]) ^ 2) > 1 then table.insert(out, off) end
		end
	end
	return out
end
-- walk `pts` one raid tick per point, the server reading the point `from - 1` for `ticks` ticks
local function walkFrozen(plr, raid, pts, from, ticks)
	for i, pt in pts do
		if not raidInfo(plr) then return false end
		local frozen = from ~= nil and i >= from and i < from + ticks
		if frozen then claim(plr, raid, pts[from - 1][1], pts[from - 1][2]) else claim(plr, raid, pt[1], pt[2]) end
		h:advance(Config.Raid.TickSeconds)
	end
	return true
end

local CUT, PULL, SQUEEZE = 919191, 919192, 919193
seedProfile(CUT, {})
seedProfile(PULL, {})
seedProfile(SQUEEZE, {})

block("G15. a half-second freeze while turning into a fence gap (REVIEW-1.md B1)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_corner_e2e): a raider hugging the fence at
	-- 1.5 studs with a 0.5 s freeze at the turn left the trusted position at (46.88, 49.00) while the
	-- root stood on the grab cell; 20 holds over 40 s were refused and the raid ended at dawn.
	local p = joinHome("Cutter", CUT)
	local C, FREEZE = 1.5, 5
	local done = false
	for _ = 1, 60 do
		if done then break end
		local raid = startHunt(p, 1)
		if not raid then break end
		local camp = raid.camp
		local plan = Heist.solveRaid(Config, Layout, camp, { pad = Config.Raid.HumanPad })
		local cells = {}
		for _, pt in plan.route do
			if pt.grab then break end
			local c, r = Layout.cellAt(Config, pt.x, pt.z)
			if #cells == 0 or cells[#cells].c ~= c or cells[#cells].r ~= r then table.insert(cells, { c = c, r = r, x = pt.x, z = pt.z }) end
		end
		-- a turn from along a row into an unarmed gap straight above, and no trap anywhere on the route
		local turnAt, trapOnRoute = nil, false
		for _, c in cells do if Layout.trapAt(camp, c.c, c.r) then trapOnRoute = true end end
		for i = 3, #cells do
			local g, below, before = cells[i], cells[i - 1], cells[i - 2]
			local gapRow = false
			for _, line in camp.lines do if line.row == g.r then gapRow = true end end
			if not turnAt and gapRow and below.c == g.c and below.r == g.r - 1 and before.r == g.r - 1 and before.c ~= g.c then turnAt = i - 1 end
		end
		local picked = nil
		if turnAt and not trapOnRoute then
			local g, before = cells[turnAt + 1], cells[turnAt - 1]
			local gx0 = (g.c - 1) * Config.World.CellSize
			local fz0 = Config.World.ApronDepth + Config.World.CellSize * g.r
			local cornerX = if before.c < g.c then gx0 + C else gx0 + Config.World.CellSize - C
			local hugTo, hugFrom = turnAt + 1, turnAt
			while hugTo < #cells and cells[hugTo + 1].c == g.c do hugTo += 1 end
			while hugFrom > 1 and cells[hugFrom - 1].r == g.r - 1 do hugFrom -= 1 end
			local poly = {}
			for i, c in cells do
				if i == turnAt then table.insert(poly, { cornerX, fz0 - C })
				elseif i > turnAt and i <= hugTo then table.insert(poly, { cornerX, c.z })
				elseif i >= hugFrom and i < turnAt then table.insert(poly, { c.x, fz0 - C })
				else table.insert(poly, { c.x, c.z }) end
			end
			local pts, marks = resample(poly, Config.Raid.WalkSpeed)
			local rects = Layout.freeRects(Config, camp)
			local locks = oldLocks(rects, pts, marks[turnAt] or #pts, FREEZE, Config.Raid.WalkSpeed)
			if #locks > 0 then picked = { poly = poly, pts = pts, from = (marks[turnAt] or #pts) + locks[1], turnAt = turnAt } end
		end
		if not picked then
			leaveCamp(p)
			restartWait()
		else
			done = true
			local s0 = stateOf(p).stats.steals
			local n0 = toastCount(p)
			walkFrozen(p, raid, picked.pts, picked.from, FREEZE)
			h:advance(0.5)
			local anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. prizeOf(camp))
			local n = toastCount(p)
			anchor.Grab.PromptButtonHoldBegan:Fire(p)
			h:advance(Config.Camps[1].hold + 0.2)
			anchor.Grab.Triggered:Fire(p)
			h:advance(0.3)
			local tx, tz = trusted(raid)
			local last = picked.pts[#picked.pts]
			truthy(stateOf(p).raid and stateOf(p).raid.carrying ~= nil,
				string.format("the grab after the freeze carries the prize (trusted (%.2f, %.2f), root (%.2f, %.2f)): %s", tx, tz, last[1], last[2], toastsSince(p, n)))
			-- and out again at carry speed, with the same freeze at the same corner on the way down
			local back = {}
			for i = #picked.poly, 1, -1 do table.insert(back, picked.poly[i]) end
			local bpts, bmarks = resample(back, Config.Raid.CarrySpeed)
			local corner = bmarks[#picked.poly - picked.turnAt + 1] or 2
			local blocks = oldLocks(Layout.freeRects(Config, camp), bpts, corner, FREEZE, Config.Raid.CarrySpeed)
			walkFrozen(p, raid, bpts, if #blocks > 0 then corner + blocks[1] else nil, FREEZE)
			for _ = 1, 20 do
				if not raidInfo(p) then break end
				claim(p, raid, 36, 20)
				h:advance(0.1)
			end
			eq(stateOf(p).stats.steals, s0 + 1, "...and carrying it back out through the gate steals it")
			eq(toastSince(p, n0, "pulled back"), nil, "...with the trusted position sliding round the corner, never pulled back")
		end
	end
	truthy(done, "found a tier-1 camp whose route turns into a gap where a 0.5 s freeze locked the old trusted step")
	h:leave(p)
	h:advance(1)
end)

block("G15b. a trusted position that cannot follow is pulled back, and says so (REVIEW-1.md B1)", function()
	-- The backstop behind the slide: a character that has been where the trusted position cannot
	-- follow for Raid.StuckSeconds (a noclip, or a freeze geometry the slide does not undo) is moved
	-- back to where the server last saw it, into standable space. Measured on the 2026-09-17 build:
	-- nothing moved it, and nothing was said.
	local p = joinHome("Clipper", PULL)
	local raid = startHunt(p, 1)
	truthy(raid ~= nil, "a tier-1 raid")
	if not raid then return end
	local camp = raid.camp
	local row = camp.lines[1].row
	local target
	for col = 1, 9 do
		if not target and Layout.cellKind(camp, col, row) == "fence" and Layout.trapAt(camp, col, row - 1) == nil then
			local path = bfsPath(camp, { 5, 0 }, { col, row - 1 })
			if path then target = { col = col, path = path } end
		end
	end
	truthy(target ~= nil, "a fence cell with a trap-free walk to the cell below it")
	if not target then return end
	walkCells(p, raid, target.path, 16)
	local x = Layout.cellCenter(Config, target.col, row - 1)
	local fenceZ0 = Config.World.ApronDepth + Config.World.CellSize * row
	local n = toastCount(p)
	claim(p, raid, x, fenceZ0 + 12) -- through the fence, and left there
	h:advance((Config.Raid.StuckSeconds or 1.0) + 0.6)
	local root = raid.frame:PointToObjectSpace(hrpOf(p).Position)
	local tx, tz = trusted(raid)
	print(string.format("   noclip claim (%.2f, %.2f); trusted (%.2f, %.2f); root now (%.2f, %.2f)", x, fenceZ0 + 12, tx, tz, root.X, root.Z))
	truthy(math.abs(root.X - x) < 0.01 and math.abs(root.Z - (fenceZ0 - 1)) < 0.01,
		string.format("after %.1f s the character stands where the server last saw it, 1 stud off the fence (%.2f, %.2f)", Config.Raid.StuckSeconds or 1.0, root.X, root.Z))
	truthy(toastSince(p, n, "pulled back") ~= nil, "...and the player is told: " .. toastsSince(p, n))
	truthy(raidInfo(p) ~= nil, "...and the raid goes on")
	leaveCamp(p)
	h:leave(p)
	h:advance(1)
end)

--============================================================ REVIEW-1.md A6. corner squeezes

block("G16. no squeeze between corner-touching rocks (REVIEW-1.md A6)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_squeeze): walls at (5,6) and (4,7), a claim
	-- from (4,6) straight to (5,7) put the trusted position in (5,7); the Parts leave 0.57 studs.
	local p = joinHome("Squeezer", SQUEEZE)
	local function floorAt(L, c, r) return Layout.cellKind(L, c, r) == "floor" end
	local done = false
	for _ = 1, 60 do
		if done then break end
		local raid = startHunt(p, 1)
		if not raid then break end
		local L = raid.camp
		local pick = nil
		for r = 1, 7 do
			for c = 1, 9 do
				for _, dx in { 1, -1 } do
					local nc, nr = c + dx, r + 1
					if not pick and floorAt(L, c, r) and floorAt(L, nc, nr) and not floorAt(L, nc, r) and not floorAt(L, c, nr)
						and Layout.trapAt(L, c, r) == nil and Layout.trapAt(L, nc, nr) == nil then
						local path = bfsPath(L, { 5, 0 }, { c, r })
						if path then pick = { c = c, r = r, nc = nc, nr = nr, path = path } end
					end
				end
			end
		end
		if not pick then
			leaveCamp(p)
			restartWait()
		else
			done = true
			walkCells(p, raid, pick.path, 16)
			local ax, az = Layout.cellCenter(Config, pick.c, pick.r)
			local bx, bz = Layout.cellCenter(Config, pick.nc, pick.nr)
			for k = 1, 12 do
				local f = math.min(1, k / 8)
				claim(p, raid, ax + (bx - ax) * f, az + (bz - az) * f)
				h:advance(0.1)
			end
			local tx, tz = trusted(raid)
			local tc, tr = Layout.cellAt(Config, tx, tz)
			truthy(not (tc == pick.nc and tr == pick.nr),
				string.format("walls at (%d,%d) and (%d,%d): a claim from (%d,%d) straight to (%d,%d) leaves the trusted position at (%.2f, %.2f), cell (%d,%d)",
					pick.nc, pick.r, pick.c, pick.nr, pick.c, pick.r, pick.nc, pick.nr, tx, tz, tc, tr))
		end
	end
	truthy(done, "found a tier-1 camp with a reachable corner squeeze")
	if raidInfo(p) then leaveCamp(p) end
	h:leave(p)
	h:advance(1)
end)

--============================================================ REVIEW-1.md B2. where the Grab prompt shows is where a grab works

local REACHER = 919194
seedProfile(REACHER, {})

block("G17. the Grab prompt shows exactly where the server grabs (REVIEW-1.md B2)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_reach): against the bars 3.5 studs off the
	-- cage's centre the root is 4.61 studs from the anchor, past the 4.25 reach, so no prompt shows on
	-- ground the server would grab from; and 0.1 studs into row 7 the prompt shows (4.10) where the
	-- server refuses the grab.
	local p = joinHome("Reacher", REACHER)
	local done = false
	for _ = 1, 40 do
		if done then break end
		local raid = startHunt(p, 1)
		if not raid then break end
		local camp = raid.camp
		-- a cage whose grab cell is walkable trap-free, with open trap-free floor in row 7 below it
		local pick
		for _, cg in camp.cages do
			if not pick and Layout.cellKind(camp, cg.col, 7) == "floor" and Layout.trapAt(camp, cg.col, 7) == nil then
				local path = bfsPath(camp, { 5, 0 }, { cg.col, 8 })
				if path then pick = { col = cg.col, path = path } end
			end
		end
		if not pick then
			leaveCamp(p)
			restartWait()
		else
			done = true
			local anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. pick.col)
			local pp = anchor.Grab
			local ax, az = Layout.cellCenter(Config, pick.col, 8)
			walkCells(p, raid, pick.path, 16)
			local function standAt(x, z)
				for _ = 1, 5 do claim(p, raid, x, z); h:advance(0.1) end
			end
			local function reach() return (hrpOf(p).Position - anchor.Position).Magnitude end
			local function tryGrab()
				local n = toastCount(p)
				pp.PromptButtonHoldBegan:Fire(p)
				h:advance(Config.Camps[1].hold + 0.05)
				pp.Triggered:Fire(p)
				h:advance(0.2)
				local s = stateOf(p)
				return s.raid ~= nil and s.raid.carrying ~= nil, toastsSince(p, n)
			end

			-- (a) against the bars, 3.5 studs off-centre
			local side = if pick.col < 9 then 1 else -1
			standAt(ax + 3.5 * side, 87)
			local d = reach()
			truthy(d <= pp.MaxActivationDistance, string.format("(a) against the cage's bars 3.5 studs off-centre the prompt shows (%.2f of %.2f studs)", d, pp.MaxActivationDistance))
			local got, why = tryGrab()
			truthy(got, "(a) ...and the hold grabs: " .. why)
			leaveCamp(p)
			restartWait()

			-- (b) a step back into row 7, still inside the prompt's reach
			raid = startHunt(p, 1)
			if not raid then return end
			-- the same seed is not guaranteed: find the cage again in this camp
			camp = raid.camp
			pick = nil
			for _, cg in camp.cages do
				if not pick and Layout.cellKind(camp, cg.col, 7) == "floor" and Layout.trapAt(camp, cg.col, 7) == nil then
					local path = bfsPath(camp, { 5, 0 }, { cg.col, 8 })
					if path then pick = { col = cg.col, path = path } end
				end
			end
			if not pick then
				leaveCamp(p)
				return
			end
			anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. pick.col)
			pp = anchor.Grab
			ax, az = Layout.cellCenter(Config, pick.col, 8)
			walkCells(p, raid, pick.path, 16)
			local rimZ = az - pp.MaxActivationDistance + 0.1
			standAt(ax, rimZ)
			d = reach()
			truthy(d <= pp.MaxActivationDistance, string.format("(b) %.2f studs in front of the anchor (z %.2f, row 7) the prompt shows (%.2f)", az - rimZ, rimZ, d))
			got, why = tryGrab()
			truthy(got, "(b) ...and wherever it shows, the hold grabs: " .. why)
			leaveCamp(p)
			restartWait()

			-- (c) just outside the reach: no prompt, and a fired one (fireproximityprompt) is refused
			raid = startHunt(p, 1)
			if not raid then return end
			camp = raid.camp
			pick = nil
			for _, cg in camp.cages do
				if not pick and Layout.cellKind(camp, cg.col, 7) == "floor" and Layout.trapAt(camp, cg.col, 7) == nil then
					local path = bfsPath(camp, { 5, 0 }, { cg.col, 8 })
					if path then pick = { col = cg.col, path = path } end
				end
			end
			if not pick then
				leaveCamp(p)
				return
			end
			anchor = raid.pocket.Cages:FindFirstChild("GrabAnchor_" .. pick.col)
			pp = anchor.Grab
			ax, az = Layout.cellCenter(Config, pick.col, 8)
			walkCells(p, raid, pick.path, 16)
			local outZ = az - pp.MaxActivationDistance - 0.3
			standAt(ax, outZ)
			d = reach()
			truthy(d > pp.MaxActivationDistance, string.format("(c) %.2f studs in front of the anchor the prompt does not show (%.2f)", az - outZ, d))
			got, why = tryGrab()
			truthy(not got and string.find(why, "in front of the cage", 1, true) ~= nil, "(c) ...and a grab fired from there is refused, with the reason: " .. why)
			leaveCamp(p)
		end
	end
	truthy(done, "found a tier-1 camp with a cage whose row-7 cell is open floor")
	h:leave(p)
	h:advance(1)
end)

--============================================================ REVIEW-1.md A3/A4. writes that overlap

local function leaveOnThread(plr)
	local sig = inst.stateOf(h.Players).signals["PlayerRemoving"]
	sig:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, plr)
	plr.Parent = nil
end

block("G18. a grant and a leave both queued behind one write leave no lock behind (REVIEW-1.md A3)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_race): the autosave's forced write yields
	-- 2 s, the carrier escapes during it and leaves 0.005-0.095 s later. In 6 of 10 offsets the leave's
	-- release landed BEFORE the queued grant, whose write then set the lock again for 120 s with the
	-- player gone, so their next server played them unsaved.
	local relocked, steals, trials = {}, 0, 0
	for trial, delta in { 0.005, 0.015, 0.025, 0.035, 0.045, 0.055, 0.065, 0.075, 0.085, 0.095 } do
		local uid = 9990100 + trial
		seedProfile(uid, {})
		local p = joinHome("Racer" .. trial, uid)
		local key = "u_" .. uid
		local raid = huntWithCleanPath(p, 1)
		local ok = raid ~= nil
		if ok then
			walkCells(p, raid, raid.path, 16)
			ok = holdGrab(p, raid)
		end
		local back = ok and bfsPath(raid.camp, { raid.prize, 8 }, { 5, 1 })
		if back then walkCells(p, raid, back, 12) end
		if ok and back and raidInfo(p) then
			trials += 1
			SLOW[key] = { yield = 2.0, times = 1 }
			local g = 0
			while (SLOW[key].started or 0) == 0 and g < 20000 do
				claim(p, raid, 36, 28)
				h:advance(0.02)
				g += 1
			end
			claim(p, raid, 36, 20)
			local g2 = 0
			while raidInfo(p) and g2 < 200 do h:advance(0.01); g2 += 1 end
			h:advance(delta)
			leaveOnThread(p)
			h:advance(8)
			SLOW[key] = nil
			local rec = store:GetAsync(key)
			if rec.jobId ~= nil then table.insert(relocked, string.format("%.3f s", delta)) end
			if rec.data.stats.steals == 1 then steals += 1 end
		else
			if raidInfo(p) then leaveCamp(p) end
			h:leave(p)
			h:advance(1)
		end
	end
	eq(trials, 10, "ten carriers escaped while the autosave's write was in flight")
	eq(#relocked, 0, "no record is left locked after its player left: " .. table.concat(relocked, ", "))
	eq(steals, trials, "...and every steal is in the store")
end)

local EXPANDER = 6660001
seedProfile(EXPANDER, { essence = 100000 })

block("G19. a change made while a write is in flight is saved at the next flush (REVIEW-1.md A4)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_save D1): an Expand made 0.55 s into a 2 s
	-- flush reached the store 52.4 s later, at the autosave; the flush that landed marked it saved.
	-- The same change with no write in flight took 5.0 s.
	local p = joinOnThread("Expander", EXPANDER)
	h:advance(1)
	local key = "u_" .. EXPANDER
	R.Expand:simulateFireServer(p)
	h:advance(0.05)
	SLOW[key] = { yield = 2.0, times = 1, when = function(rec) return rec.data and rec.data.cagesUnlocked == 4 end }
	local guard = 0
	while (SLOW[key].started or 0) == 0 and guard < 400 do h:advance(0.05); guard += 1 end
	truthy((SLOW[key].started or 0) == 1, "the flush of the first change is in flight")
	h:advance(0.5)
	R.Expand:simulateFireServer(p)
	h:advance(0.05)
	eq(stateOf(p).cagesUnlocked, 5, "a second change is made while it yields")
	local tChange, landed = sched:now(), nil
	for _ = 1, 700 do
		h:advance(0.1)
		local rec = store:GetAsync(key)
		if rec and rec.data and rec.data.cagesUnlocked == 5 then landed = sched:now(); break end
	end
	SLOW[key] = nil
	local took = (landed or math.huge) - tChange
	print(string.format("   a change made during a 2 s write reached the store %.1f s later", took))
	le(took, Config.Save.FlushTickSeconds + 2 + 1, "...within one flush tick of the write landing, not at the 60 s autosave")

	-- the other half of the same rule: a flush that FAILS carried the change nowhere, so it is tried
	-- again at the next flush tick (pending is cleared before the write now, and set again on failure)
	R.Expand:simulateFireServer(p)
	h:advance(0.05)
	eq(stateOf(p).cagesUnlocked, 6, "a third change")
	SLOW[key] = { yield = 0.5, fail = true, times = 1, when = function(rec) return rec.data and rec.data.cagesUnlocked == 6 end }
	local tFail, landedAgain = sched:now(), nil
	for _ = 1, 700 do
		h:advance(0.1)
		local rec = store:GetAsync(key)
		if rec and rec.data and rec.data.cagesUnlocked == 6 then landedAgain = sched:now(); break end
	end
	truthy((SLOW[key].finished or 0) == 1, "its first write failed")
	SLOW[key] = nil
	local retried = (landedAgain or math.huge) - tFail
	print(string.format("   a change whose write failed reached the store %.1f s after it was made", retried))
	le(retried, 2 * Config.Save.FlushTickSeconds + 1, "...and is retried at the next flush tick, not at the autosave")
	h:leave(p)
	h:advance(1)
end)

--============================================================ REVIEW-1.md A1. a lock that clears after the join

local HANDOFF, EXPIRED, OVERWRITTEN = 6660002, 6660003, 6660004
local function lockedRecord(uid, essence)
	store:SetAsync("u_" .. uid, { jobId = "old-server-job", lockUntil = os.time() + 120, data = {
		v = 1, essence = essence, savedAt = os.time(), cagesUnlocked = 5, tutorial = 4,
		cages = cages({ [5] = { sp = "dogman", jar = 0 }, [4] = { sp = "jerseydevil", jar = 0 } }),
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman", "jerseydevil" },
		stats = { steals = 3, caught = 0, poachersCaught = 0 },
	} })
end
local function releaseOld(uid, newEssence)
	store:UpdateAsync("u_" .. uid, function(old)
		old.jobId = nil
		old.lockUntil = 0
		if newEssence then
			old.data.essence = newEssence
			old.data.savedAt = os.time()
		end
		return old
	end)
end
local function collectFor(plr, seconds)
	local lair = lairOf(plr)
	local got = 0
	for _ = 1, math.floor(seconds / 20) do
		h:advance(20)
		hrpOf(plr).CFrame = CF.new(lair.CollectPad.Position + V3.new(0, 3, 0))
		local e0 = stateOf(plr).essence
		lair.CollectPad.Touched:Fire(hrpOf(plr))
		h:advance(0.1)
		got += stateOf(plr).essence - e0
	end
	return got
end
local LOCK_WAIT = Config.Save.LockWaitSeconds or 15
local LOCK_RECHECK = Config.Save.LockRecheckSeconds or 15

block("G20. a save lock the old server releases after the join (REVIEW-1.md A1)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_save D2): a record locked by another server
	-- whose lock cleared 1 s after the join was never re-read. After 603 s of play canSave was still
	-- false, 17 877 Essence had been collected, and the store still held 250 000 after the player left.
	lockedRecord(HANDOFF, 250000)
	local p = joinOnThread("Handoff", HANDOFF)
	h:advance(1)
	truthy(toastSince(p, 0, "another server") ~= nil, "(a) a join that finds its save locked says it is waiting: " .. toastsSince(p, 0))
	releaseOld(HANDOFF)
	h:advance(LOCK_WAIT + 1)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	local s = stateOf(p)
	eq(s and s.canSave, true, "(a) the lock released 1 s after the join: the session saves")
	eq(s and s.saveBanner, nil, "(a) ...with no not-saving banner")
	eq(s and s.essence, 250000, "(a) ...on the saved profile")
	local got = collectFor(p, 120)
	h:leave(p)
	h:advance(1)
	local rec = store:GetAsync("u_" .. HANDOFF)
	eq(rec.data.essence, 250000 + got, string.format("(a) the %d Essence collected in the session is in the store", got))
	eq(rec.jobId, nil, "(a) ...and the lock is released")

	-- (b) a lock held past the wait (a crashed server), then expiring with the save untouched
	lockedRecord(EXPIRED, 90000)
	local q = joinOnThread("Expired", EXPIRED)
	h:advance(LOCK_WAIT + 2)
	h.Players:simulateSpawn(q, h.workspace)
	h:advance(0.5)
	s = stateOf(q)
	eq(s and s.canSave, false, "(b) still locked after the wait: plays unsaved")
	truthy(s and string.find(tostring(s.saveBanner), "another server", 1, true) ~= nil, "(b) ...and says why: " .. tostring(s and s.saveBanner))
	local nq = toastCount(q)
	releaseOld(EXPIRED)
	h:advance(LOCK_RECHECK + 2)
	s = stateOf(q)
	eq(s.canSave, true, "(b) once the lock is gone and the save is untouched, the session takes it and saves")
	eq(s.saveBanner, nil, "(b) ...the banner goes")
	truthy(toastSince(q, nq, "saving") ~= nil, "(b) ...and the player is told: " .. toastsSince(q, nq))
	local e1 = s.essence
	got = collectFor(q, 40)
	h:leave(q)
	h:advance(1)
	rec = store:GetAsync("u_" .. EXPIRED)
	eq(rec.data.essence, e1 + got, "(b) progress from the session is in the store")
	eq(rec.jobId, nil, "(b) ...and the lock is released")

	-- (c) the lock goes, but the other server wrote the save first: taking it would lose that write
	lockedRecord(OVERWRITTEN, 70000)
	local w = joinOnThread("Overwritten", OVERWRITTEN)
	h:advance(LOCK_WAIT + 2)
	h.Players:simulateSpawn(w, h.workspace)
	h:advance(0.5)
	releaseOld(OVERWRITTEN, 71234)
	h:advance(LOCK_RECHECK + 2)
	s = stateOf(w)
	eq(s.canSave, false, "(c) a save another server changed after the join is never written over")
	truthy(string.find(string.lower(tostring(s.saveBanner)), "rejoin", 1, true) ~= nil, "(c) ...and the banner says to rejoin: " .. tostring(s.saveBanner))
	collectFor(w, 40)
	h:leave(w)
	h:advance(1)
	rec = store:GetAsync("u_" .. OVERWRITTEN)
	eq(rec.data.essence, 71234, "(c) the other server's write is kept")

	-- (d) the player leaves while the session's own take-over write is in flight: the lock it takes
	-- is handed straight back
	local LEAVER = 6660005
	lockedRecord(LEAVER, 50000)
	local lv = joinOnThread("Leaver", LEAVER)
	h:advance(LOCK_WAIT + 2)
	eq(stateOf(lv).canSave, false, "(d) locked past the wait")
	releaseOld(LEAVER)
	SLOW["u_" .. LEAVER] = { yield = 2.0, times = 1, when = function(r) return r.jobId ~= nil end }
	local g = 0
	while (SLOW["u_" .. LEAVER].started or 0) == 0 and g < 400 do h:advance(0.1); g += 1 end
	truthy((SLOW["u_" .. LEAVER].started or 0) == 1, "(d) the session's take-over write is in flight")
	leaveOnThread(lv)
	h:advance(4)
	SLOW["u_" .. LEAVER] = nil
	rec = store:GetAsync("u_" .. LEAVER)
	eq(rec.jobId, nil, "(d) a take-over that lands after the player left leaves no lock")
	eq(rec.data.essence, 50000, "(d) ...and writes no data")
end)

--============================================================ REVIEW-1.md A5. a snare dropped on the poacher

local TRAPPER = 7770001
seedProfile(TRAPPER, { essence = 1000, cages = cages({ [5] = { sp = "chupacabra", jar = 0 }, [4] = { sp = "hodag", jar = 0 }, [6] = { sp = "jackalope", jar = 0 } }), journal = { "chupacabra", "hodag", "jackalope" } })

block("G21. a trap set under a poacher that is already in the yard (REVIEW-1.md A5)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_poacher): reading the poacher's cell from the
	-- workspace, snaring it and clearing the snare once it was gone caught 5 of 5 visits in 1 300 s,
	-- +180 bounty each for a net trap cost of 0 (the refund is 100 %).
	local p = joinHome("Trapper", TRAPPER)
	local plot, lair = plotOf(p)
	local frame = plotFrame(plot)
	R.BuildMode:simulateFireServer(p, true)
	h:advance(0.2)
	local poachers = h.workspace:FindFirstChild("Poachers")
	local modelName = "Poacher_" .. string.match(plot.Name, "%d+")
	-- honest defence during the WARNING still works: a snare placed before the poacher comes
	local warnedPlaced = false
	local t0 = sched:now()
	while sched:now() - t0 < 400 and not poachers:FindFirstChild(modelName) do
		h:advance(0.5)
		local s = stateOf(p)
		if not warnedPlaced and s.poacher and s.poacher.warningLeft then
			local L = lairOfSeed(TRAPPER)
			for row = 7, 1, -1 do
				for col = 1, 9 do
					if not warnedPlaced and Layout.validatePlacement(Config, L, col, row, "snare") then
						R.TrapAction:simulateFireServer(p, col, row, "snare")
						h:advance(0.1)
						warnedPlaced = stateOf(p).snares == 1
						R.TrapAction:simulateFireServer(p, col, row, "clear")
						h:advance(0.1)
					end
				end
			end
		end
	end
	truthy(warnedPlaced, "a snare can be set during the poacher warning")
	truthy(poachers:FindFirstChild(modelName) ~= nil, "the poacher came")
	local tries, placed, n = 0, 0, toastCount(p)
	local caught0 = stateOf(p).stats.poachersCaught
	while poachers:FindFirstChild(modelName) and sched:now() - t0 < 500 do
		local m = poachers:FindFirstChild(modelName)
		local lp = frame:PointToObjectSpace(m.Body.Position)
		local c, r = Layout.cellAt(Config, lp.X, lp.Z)
		if r >= 1 and r <= 7 and not (c == 5 and r == 1) then
			tries += 1
			local before = stateOf(p).snares
			R.TrapAction:simulateFireServer(p, c, r, "snare")
			h:advance(0.13)
			if stateOf(p).snares > before then
				placed += 1
				R.TrapAction:simulateFireServer(p, c, r, "clear")
			end
		end
		h:advance(0.13)
	end
	h:advance(1)
	ge(tries, 5, "the poacher was tried for on at least five of its cells")
	eq(placed, 0, "no trap can be set while a poacher is in the yard")
	truthy(toastSince(p, n, "poacher is in your yard") ~= nil, "...and the player is told why: " .. toastsSince(p, n))
	eq(stateOf(p).stats.poachersCaught, caught0, "...so no bounty is paid for it")
	R.BuildMode:simulateFireServer(p, false)
	h:leave(p)
	h:advance(1)
end)

--============================================================ REVIEW-1.md A2. predicting the next camp

local PLANNER, RIVAL = 7770002, 7770003
seedProfile(PLANNER, {})
seedProfile(RIVAL, {})

block("G22. the next camp cannot be computed from the ones before it (REVIEW-1.md A2)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_salt + predict_next): a camp's seed is
	-- recoverable from its sign and layout (1 candidate of 2^31, 95 s of interpreted Luau), and every
	-- later camp's seed followed from it: seed + 2 654 435 761 per raid on the server, + 104 729 per
	-- tier. The next tier-2 camp was predicted before its permit was paid, down to its laser phases.
	-- The server's seeds, read back here, stand in for the recovered ones.
	local p = joinHome("Planner", PLANNER)
	local q = joinHome("Rival", RIVAL)
	local P = 2147483647
	local seeds = {}
	for i = 1, 12 do
		local raid = startHunt(p, 1)
		if raid then
			table.insert(seeds, raid.info:GetAttribute("Seed"))
			leaveCamp(p)
		end
		if i % 4 == 0 then
			local other = startHunt(q, 1)
			if other then leaveCamp(q) end
		end
		restartWait()
	end
	eq(#seeds, 12, "twelve camps entered")
	local affine, stepped, repeated = 0, 0, 0
	for i = 2, #seeds do
		if seeds[i] == (seeds[i - 1] + 2654435761) % P or seeds[i] == (seeds[i - 1] + 2 * 2654435761) % P then stepped += 1 end
		for j = 1, i - 1 do if seeds[j] == seeds[i] then repeated += 1 end end
		if i >= 3 and (seeds[i] - seeds[i - 1]) % P == (seeds[i - 1] - seeds[i - 2]) % P then affine += 1 end
	end
	eq(stepped, 0, "no camp seed is the previous one plus the design's per-raid step")
	eq(affine, 0, "no three camps in a row are evenly spaced (any per-raid step, any salt)")
	eq(repeated, 0, "no camp repeats")
	h:leave(p)
	h:leave(q)
	h:advance(1)
end)

--============================================================ REVIEW-1.md B4. a slow load does not yank a walking player

block("G23. a character that walks away while its lair loads stays where it walked (REVIEW-1.md B4)", function()
	-- Measured on the 2026-09-17 build (the reviewer's probe_joinload): with a 0.6 s load the root was
	-- moved from plot-local x 45.6 back to the marker at t = 0.6 s; after one failed attempt and a
	-- retry, 35.2 studs back at t = 2.2 s.
	for _, case in { { uid = 91001, yield = 0.6, fail = false }, { uid = 91002, yield = 0.6, fail = true } } do
		local key = "u_" .. case.uid
		SLOW[key] = { yield = case.yield, times = if case.fail then 1 else 1, fail = case.fail }
		local plr = joinOnThread("J" .. case.uid, case.uid)
		h.Players:simulateSpawn(plr, h.workspace)
		local plot
		for _, pl in lairs:GetChildren() do
			if string.find(tostring(pl.Sign.Label.Text.Text), plr.Name, 1, true) then plot = pl end
		end
		local frame = plotFrame(plot)
		local hrp = hrpOf(plr)
		local lp0 = frame:PointToObjectSpace(hrp.Position)
		truthy(math.abs(lp0.X - 36) < 0.5 and math.abs(lp0.Z - 8) < 0.5, string.format("the character lands on its marker before the load is done (%.2f, %.2f)", lp0.X, lp0.Z))
		local yanked = nil
		for i = 1, 40 do
			hrp.CFrame = CF.new(frame:PointToWorldSpace(V3.new(36 + 1.6 * i, 3, 4)))
			h:advance(0.1)
			local lp = frame:PointToObjectSpace(hrp.Position)
			if not yanked and math.abs(lp.X - (36 + 1.6 * i)) > 0.5 then
				yanked = string.format("at %.1f s moved from x %.1f to (%.2f, %.2f)", i * 0.1, 36 + 1.6 * i, lp.X, lp.Z)
			end
		end
		SLOW[key] = nil
		truthy(plot:FindFirstChild("Lair") ~= nil, string.format("%s load: the lair is built", if case.fail then "a failed-then-retried" else "a 0.6 s"))
		eq(yanked, nil, "...and the walking character is never moved back to the marker")
		h:leave(plr)
		h:advance(1)
	end
	-- a character that already existed before PlayerAdded ran (Studio play-solo) still lands home
	local plr = inst.Instance.new("Player")
	plr.Name = "Early"
	plr.UserId = 91003
	local pg = inst.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = plr
	plr.Parent = h.Players
	h.Players:simulateSpawn(plr, h.workspace)
	inst.stateOf(h.Players).signals["PlayerAdded"]:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, plr)
	h:advance(1)
	local plot
	for _, pl in lairs:GetChildren() do
		if string.find(tostring(pl.Sign.Label.Text.Text), plr.Name, 1, true) then plot = pl end
	end
	local lp = plotFrame(plot):PointToObjectSpace(hrpOf(plr).Position)
	truthy(math.abs(lp.X - 36) < 0.5 and math.abs(lp.Z - 8) < 0.5, string.format("a character that spawned before PlayerAdded still lands on its marker (%.2f, %.2f)", lp.X, lp.Z))
	h:leave(plr)
	h:advance(1)
end)

--============================================================ REVIEW-1.md B1. a slide judged leg by leg

local GLANCE = 919195
seedProfile(GLANCE, {})

block("G24. a slide along a fence into a burning net is caught on that tick (REVIEW-1.md B1)", function()
	-- The slide bends a tick's trusted path. Judged as one chord from its start to its end, a path that
	-- slides along the fence's 1-stud margin into a gap's net only TOUCHES the net at its last point
	-- and is not caught; judged leg by leg it is. Measured with the fixed modules over 1 440 000 random
	-- ticks in 600 camps: the two disagree on 694 (the legs catch 685 the chord misses, the chord 9 the
	-- legs do not, each where the path goes round a corner of a net). This block plays one such tick:
	-- from 1.5 studs left of a gap and 0.36 into the fence margin, a claim up and right through the
	-- fence (0.06 studs past the gap's edge, 4 studs up) slides along z = fence + 1 into the gap.
	local p = joinHome("Glancer", GLANCE)
	local done = false
	for _ = 1, 40 do
		if done then break end
		local raid = startHunt(p, 1)
		if not raid then break end
		local camp = raid.camp
		local laser
		for _, t in Layout.traps(camp) do if t.kind == "laser" then laser = t end end
		local g, lr = laser.col, laser.row
		local path = g >= 2 and Layout.cellKind(camp, g - 1, lr - 1) == "floor" and Layout.trapAt(camp, g - 1, lr - 1) == nil
			and bfsPath(camp, { 5, 0 }, { g - 1, lr - 1 })
		if not path then
			leaveCamp(p)
			restartWait()
		else
			done = true
			walkCells(p, raid, path, 16)
			local gx0 = (g - 1) * Config.World.CellSize
			local fz0 = Config.World.ApronDepth + Config.World.CellSize * lr
			local p0x, p0z = gx0 - 1.5, fz0 + 0.36
			local qx, qz = gx0 + 0.06, fz0 + 4
			local function raidT() return sched:now() - raid.start end
			local function hold(x, z, n) for _ = 1, n do claim(p, raid, x, z); h:advance(0.1) end end
			hold(p0x, p0z, 5)
			local function waitFor(dangerous)
				local guard = 0
				while guard < 100 do
					local tt = raidT()
					if Heist.dangerousAt(Config, laser, tt) == dangerous and Heist.dangerousAt(Config, laser, tt + 0.1) == dangerous
						and Heist.dangerousAt(Config, laser, tt + 0.2) == dangerous then return true end
					hold(p0x, p0z, 1)
					guard += 1
				end
				return false
			end
			-- control: the same tick while the net is OFF is no catch
			truthy(waitFor(false), "the net goes OFF")
			local n = toastCount(p)
			hold(qx, qz, 1)
			hold(p0x, p0z, 3)
			truthy(raidInfo(p) ~= nil and toastSince(p, n, "caught") == nil, "(control) sliding into the gap while its net is OFF is no catch: " .. toastsSince(p, n))
			-- the same tick while it burns
			truthy(waitFor(true), "the net burns")
			n = toastCount(p)
			hold(qx, qz, 1)
			hold(p0x, p0z, 3)
			truthy(toastSince(p, n, "caught by a laser net") ~= nil, "sliding along the fence into the gap while its net burns is caught: " .. toastsSince(p, n))
			eq(raidInfo(p), nil, "...and the raid is over")
		end
	end
	truthy(done, "found a tier-1 camp with open floor below-left of its net's gap")
	if raidInfo(p) then leaveCamp(p) end
	h:leave(p)
	h:advance(1)
end)

--============================================================ text lengths the HUD was sized for

do
	-- check_stealacryptid_hud.luau proves a 100-character toast and a 90-character banner are
	-- legible on a phone. That proof is only worth something if the server never sends longer, so
	-- every toast and every banner this run actually produced is measured here.
	local longestToast, longestBanner, toastText, bannerText = 0, 0, "", ""
	for _, rec in R.Toast:getSent() do
		local t = tostring(rec.args[1])
		if #t > longestToast then longestToast, toastText = #t, t end
	end
	for _, rec in R.State:getSent() do
		local b = rec.args[1] and rec.args[1].saveBanner
		if type(b) == "string" and #b > longestBanner then longestBanner, bannerText = #b, b end
	end
	print(string.format("   longest toast sent: %d chars; longest banner: %d chars", longestToast, longestBanner))
	le(longestToast, 100, "every toast this run sent fits the HUD's 100-character proof: " .. toastText)
	le(longestBanner, 90, "every banner this run sent fits the HUD's 90-character proof: " .. bannerText)
end

--============================================================ done

print("")
for _, w in h.warnings do
	if not string.find(w, "injected DataStore failure", 1, true) and not string.find(w, "modelled write failure", 1, true)
		and not string.find(w, "locked by another server", 1, true) then
		print("  [warn] " .. w)
	end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("steal a cryptid guards: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid guards failed", 0) end
