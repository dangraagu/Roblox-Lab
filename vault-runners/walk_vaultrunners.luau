-- walk_vaultrunners.luau — PLAY THE GAME. Run: luau walk_vaultrunners.luau 2>&1
--
--   cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--   cd ../vault-runners && luau walk_vaultrunners.luau
--
-- Green tests are not a working game. tests/Curve.spec.luau measures the difficulty curve against
-- a MODEL of a player; this file boots the real server script and walks a real character through
-- the real maze, corridor by corridor, at the speed the server wrote onto the Humanoid, with
-- src/shared/Trace.luau's anti-teleport throttle in the way — and reports what came out.
--
-- Two runners per floor, so the numbers bracket a real player:
--
--   SOLVER   walks the BFS-optimal corridor to the stair on every storey and takes whatever gems
--            happen to be on it. Nobody plays this well; it is the ceiling.
--   GRABBER  detours for gems, nearest first, and gives up on the rest of a storey once it has
--            spent its share of the clock. This is roughly what playing looks like.
--   FUMBLER  a GRABBER who misses the TOP hop of every shaft, once. Fifteen studs down, back to
--            pad 1, and whatever the crumbled pads make them wait for. It is there so the table
--            has a column that is a FAILED JUMP rather than a probability.
--
-- ALL THREE CLIMB THE SHAFT PAD BY PAD. The first version of this file flew straight up the
-- middle of the stairwell to the next storey's floor height, which is the one thing a player
-- cannot do — and it meant the obby was invisible to the only tool in the repo that plays the
-- game. A pad that has crumbled is WAITED FOR, because that is what a runner standing under it
-- has to do.
--
-- Nothing here reads VaultPath.wastedCells or the slack schedule. It reads the countdown the
-- SERVER sent the client, and the banked total the SERVER wrote to leaderstats.

local Harness = require("../robloxemu/emu/harness")
local Config = require("./src/shared/Config")
local Progression = require("./src/shared/Progression")
local VaultFloor = require("./src/shared/VaultFloor")
local VaultPath = require("./src/shared/VaultPath")
local MazeGen = require("./src/shared/MazeGen")
local Rng = require("./src/shared/Rng")
local Trace = require("./src/shared/Trace")

local h = Harness.new({
	bundle = require("../robloxemu/build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local ME = 909
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")

local WALK_H, WALK_UP = Trace.speeds(Config)
WALK_H = WALK_H / Config.Run.TrustedSpeedFactor
WALK_UP = WALK_UP / Config.Run.TrustedClimbFactor
local STEP = Config.Run.TickSeconds

--============================================================================ boot

store:SetAsync("u_" .. ME, {
	data = { gems = 0, totalBanked = 999999, pets = {}, equipped = nil,
		floors = { [1] = 1, [2] = 1, [3] = 1 }, escapes = 0, wipes = 0 },
})
assert(h:tryRun("server/Main.server"))
h:advance(1)
local me = h:join("Runner", ME)
h:advance(1)
h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

local remotes = h.services.ReplicatedStorage:FindFirstChild("VaultRemotes")
local Enter = remotes:FindFirstChild("Enter")
local RunRemote = remotes:FindFirstChild("Run")
local vaults = h.workspace:FindFirstChild("Vaults")
local ls = me:FindFirstChild("leaderstats")
local gemsValue = ls:FindFirstChild("Gems")

local seenUpTo = 0
local function drain()
	local sent = RunRemote:getSent()
	local out = {}
	for i = seenUpTo + 1, #sent do out[#out + 1] = sent[i] end
	seenUpTo = #sent
	return out
end
local function lastOf(kind)
	local sent = RunRemote:getSent()
	for i = #sent, 1, -1 do if sent[i].args[1] == kind then return sent[i].args[2] end end
	return nil
end

--============================================================================ routing on the real grid

local function neighbourCells(model, s, cx, cy)
	local grid, cells = model.grids[s + 1], model.cells
	local out = {}
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local nx, ny = cx + d[1], cy + d[2]
		if nx >= 0 and nx < cells and ny >= 0 and ny < cells then
			local row = grid[2 * cy + 1 + d[2]]
			if row ~= nil and row[2 * cx + 1 + d[1]] == false then out[#out + 1] = { nx, ny } end
		end
	end
	return out
end

-- the corridor a player would actually walk between two cells, as a list of cells
local function route(model, s, from, to)
	local dist = VaultPath.distances(model, s, from)
	local d = dist[to.cy * model.cells + to.cx]
	if d == nil then return nil end
	local path = { { to.cx, to.cy } }
	local cur = { to.cx, to.cy }
	while d > 0 do
		for _, n in ipairs(neighbourCells(model, s, cur[1], cur[2])) do
			if dist[n[2] * model.cells + n[1]] == d - 1 then
				cur = n; d -= 1; table.insert(path, 1, { cur[1], cur[2] }); break
			end
		end
	end
	return path, dist[to.cy * model.cells + to.cx]
end

--============================================================================ one run

-- Park-Miller, so a run is repeatable: two identical rows in the table below are the same run,
-- not a coincidence.
local function lcg(seed)
	local st = seed % 2147483647
	if st <= 0 then st += 2147483646 end
	return function(n) st = (st * 16807) % 2147483647; return 1 + (st % n) end
end

local function playFloor(tier, floor, style)
	-- LEAVE FIRST, THEN WRITE. Escaping a vault advances p.floors, and leaving flushes the live
	-- profile to the store — so writing the floor before the leave has the server's own flush
	-- land on top of it, and the next run is a floor deeper than the one being reported. The
	-- first version of this file did exactly that and printed two different countdowns for what
	-- it labelled the same floor, which is what gave it away.
	h:leave(me)
	h:advance(1)
	store:SetAsync("u_" .. ME, {
		data = { gems = 0, totalBanked = 999999, pets = {}, equipped = nil,
			floors = { [1] = floor, [2] = floor, [3] = floor }, escapes = 0, wipes = 0 },
	})
	h:advance(0.2)
	me = h:join("Runner", ME)
	h:advance(1)
	h.Players:simulateSpawn(me, h.workspace)
	h:advance(1)
	ls = me:FindFirstChild("leaderstats")
	gemsValue = ls:FindFirstChild("Gems")
	local hrp = me.Character:FindFirstChild("HumanoidRootPart")

	drain()
	Enter:simulateFireServer(me, tier)
	h:advance(0.4)

	local vault = vaults:GetChildren()[1]
	if vault == nil then return { error = "no vault was built" } end
	local start = lastOf("start")
	local countdown = start.collapseSeconds

	-- rebuild the same maze locally, purely to know where the corridors are
	local spec = Progression.difficulty(Config, tier, floor)
	spec.seed = Progression.seedFor(Config, tier, floor)
	local model = VaultFloor.build(Config, spec, MazeGen, Rng)

	-- the vault's world origin, read off a part the server actually placed
	local floor0 = vault:FindFirstChild("Floor_0")
	local originX = floor0.Position.X
	local originY = floor0.Position.Y + Config.Vault.FloorThickness / 2
	local originZ = floor0.Position.Z
	local S = model.cellSize
	local function worldOf(s, cx, cy)
		return
			originX + (2 * cx + 1 - model.cells) * S,
			originY + s * model.storeyHeight + Config.Run.RunnerRootHeight,
			originZ + (2 * cy + 1 - model.cells) * S
	end

	local elapsed = 0
	local alive = true
	local falls, fallSeconds, waitedForPads = 0, 0, 0
	local rand = lcg(tier * 7919 + floor * 104729 + (style == "solver" and 1 or style == "grabber" and 2 or 3))
	local missMillionths = math.floor(Config.Ascent.ModelMissChance * 1e6 + 0.5)
	local function stepTo(tx, ty, tz)
		for _ = 1, 3000 do
			if #vaults:GetChildren() == 0 then alive = false; return end
			local cur = hrp.Position
			local dx, dz = tx - cur.X, tz - cur.Z
			local dy = ty - cur.Y
			local flat = math.sqrt(dx * dx + dz * dz)
			if flat < 0.6 and math.abs(dy) < 0.6 then return end
			local moveH = math.min(flat, WALK_H * STEP)
			local nx = flat > 1e-6 and (cur.X + dx / flat * moveH) or cur.X
			local nz = flat > 1e-6 and (cur.Z + dz / flat * moveH) or cur.Z
			local ny = cur.Y + (dy > 0 and math.min(dy, WALK_UP * STEP) or dy)
			hrp.CFrame = CFrame.new(nx, ny, nz)
			h:advance(STEP)
			elapsed += STEP
		end
	end
	local function walkCells(s, cells)
		for _, c in ipairs(cells) do
			if not alive then return end
			stepTo(worldOf(s, c[1], c[2]))
		end
	end

	for s = 0, model.storeys - 1 do
		if not alive then break end
		local at = model.entryCells[s + 1]
		local exitCell = model.exitCells[s + 1]

		if style == "grabber" or style == "fumbler" then
			-- nearest-first gem grab, until this storey's share of the clock is spent
			local left = {}
			for _, g in ipairs(model.gems) do
				if g.storey == s and g.cell ~= nil then left[#left + 1] = g.cell end
			end
			-- WHEN THE PLANE GETS HERE, not a flat share of the clock. The collapse reaches
			-- storey s at planeFractionAt(killLines[s]) of the countdown, and on a 5-storey vault
			-- storey 0's share is 20%, not 100/5 = 20% of the WALL CLOCK measured from the top.
			-- Budgeting the naive way drowned the grabber on the ground floor of Bronze.
			local deadline = (s < model.storeys - 1)
				and VaultFloor.planeFractionAt(model, model.killLines[s + 1]) * countdown
				or countdown
			-- SECONDS OF AIR THE RUNNER REFUSES TO SPEND — and it has to include the shaft now.
			-- The deadline is the moment the plane reaches this storey's kill line, and the runner
			-- has to be clear of that height by then; a MISSED HOP puts them straight back on this
			-- floor. Budgeting only the walk back to the stair drowned this runner on Gold floor 1
			-- and Gold floor 400 the first time the shaft was walked pad by pad: it arrived at the
			-- stair with four seconds in hand, fell twice, and the plane was there when it landed.
			-- That is a real property of the game with the obby in it, not a quirk of this file —
			-- a gem-greedy player has to leave room for a fall. Reserving only the EXPECTED retry
			-- was not enough either: the runner is still at storey height for the first hop or two,
			-- so what has to be reserved is the whole climb. On the top storey there is no shaft,
			-- and the deadline is the countdown itself, so nothing is reserved there.
			local KEEP = 4 + ((s < model.storeys - 1) and VaultPath.climbSeconds(Config, model) or 0)
			while #left > 0 and alive do
				local dist = VaultPath.distances(model, s, at)
				local bi, bd = nil, math.huge
				for i, c in ipairs(left) do
					local dd = dist[c.cy * model.cells + c.cx]
					if dd ~= nil and dd < bd then bi, bd = i, dd end
				end
				if bi == nil then break end
				-- would going there still leave time to reach the stair before the plane?
				local backHome = VaultPath.stepsBetween(model, s, left[bi], exitCell) or 0
				local cost = (bd + backHome) * VaultPath.studsPerStep(model) / Config.Movement.WalkSpeed
				if elapsed + cost + KEEP > deadline then break end
				local p = route(model, s, at, left[bi])
				walkCells(s, p)
				at = left[bi]
				table.remove(left, bi)
			end
		end

		if not alive then break end
		local p = route(model, s, at, exitCell)
		walkCells(s, p)
		if not alive then break end

		if s < model.storeys - 1 then
			-- THE ASCENT, pad by pad. Six 3x3 pads with five studs of open air between them, each
			-- one crumbling a beat after it is stood on. A miss drops the runner to this storey's
			-- floor and the shaft starts again at pad 1 — no checkpoint, and the collapse does not
			-- pause while it happens.
			local sh = model.shafts[s + 1]
			local floorY = originY + s * model.storeyHeight + Config.Run.RunnerRootHeight
			local k, guard = 1, 0
			-- FUMBLER misses the last hop of every shaft, once. Everybody else rolls it.
			local fumbled = false
			while k <= #sh.pads and alive do
				guard += 1
				if guard > 300 then break end
				local pad = sh.pads[k]
				local part = vault:FindFirstChild(string.format("Step_%d_%d", s, k))
				-- A pad that has crumbled is not there to land on. Wait under it, like a player.
				local waited = 0
				while part ~= nil and not part.CanCollide and alive and waited < 20 do
					if #vaults:GetChildren() == 0 then alive = false; break end
					h:advance(STEP); elapsed += STEP; waited += STEP; waitedForPads += STEP
				end
				if not alive then break end
				local wx, wy, wz = originX + pad.x, originY + pad.y + Config.Run.RunnerRootHeight,
					originZ + pad.z
				local miss
				if style == "fumbler" and k == #sh.pads and not fumbled then
					miss = true; fumbled = true
				else
					miss = rand(1000000) <= missMillionths
				end
				if miss then
					-- short of the pad, into the gap, down to the floor
					local drop = (pad.y - model.stepRise) - 0
					local fall = VaultPath.fallSeconds(Config, math.max(drop, 0))
					stepTo(wx, floorY, wz)
					h:advance(fall); elapsed += fall
					falls += 1; fallSeconds += fall
					k = 1
				else
					stepTo(wx, wy, wz)
					k += 1
				end
			end
			-- ...and off the top pad onto the floor above, which is the one move in the shaft that
			-- is a step rather than a jump.
			if alive then
				local tx, _, tz = worldOf(s, exitCell.cx, exitCell.cy)
				local _, ny = worldOf(s + 1, exitCell.cx, exitCell.cy)
				stepTo(tx, ny, tz)
			end
		end
	end

	-- the exit pad, and out
	if alive then
		local pad = vault:FindFirstChild("ExitPad")
		if pad then stepTo(pad.Position.X, pad.Position.Y + Config.Run.RunnerRootHeight, pad.Position.Z) end
	end
	for _ = 1, 60 do
		if #vaults:GetChildren() == 0 then break end
		h:advance(STEP); elapsed += STEP
	end

	local ended = lastOf("end")
	return {
		countdown = countdown, elapsed = elapsed, ended = ended,
		storeys = start.storeys, gemsOnFloor = start.gems,
		wallet = gemsValue.Value,
		falls = falls, fallSeconds = fallSeconds, waitedForPads = waitedForPads,
	}
end

--============================================================================ walk it

print("Vault Runners — walking the real server. WalkSpeed on the Humanoid: "
	.. tostring(me.Character:FindFirstChildOfClass("Humanoid").WalkSpeed))
print("")
print("tier    floor | countdown | runner  | took   | outcome  | banked / gems | falls (lost s)")
for _, tf in ipairs({ { 1, 1 }, { 3, 1 }, { 3, 30 }, { 3, 100 }, { 3, 400 } }) do
	for _, style in ipairs({ "solver", "grabber", "fumbler" }) do
		local r = playFloor(tf[1], tf[2], style)
		if r.error then
			print(string.format("%-7s %5d | %s", Config.Tiers[tf[1]].name, tf[2], r.error))
		else
			local e = r.ended or {}
			print(string.format("%-7s %5d | %6ds   | %-7s | %5.1fs | %-8s | %3d / %-3d     | %d (%.1fs fall, %.1fs waiting)",
				Config.Tiers[tf[1]].id, tf[2], r.countdown, style, r.elapsed,
				tostring(e.reason), e.banked or 0, r.gemsOnFloor,
				r.falls, r.fallSeconds, r.waitedForPads))
		end
	end
end
print("")
print("done")
