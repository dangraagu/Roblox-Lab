-- Labyrinth Mariozo — the falling hazards, driven through the REAL client (Biome.client + BiomeArt).
-- Run: luau check_labyrintspill_hazards.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- tests/CellHazards.spec.luau pins the pure rules and tests/Pacing.spec.luau measures the rarity on the
-- game's own mazes. This file proves the CLIENT uses exactly those rules on the real server's maze:
--   §1 rings appear only at the cells CellHazards.pick names for that level and its real trap cells
--      (so everyone on a level meets the same hazards), never on a trap, the start, the exit;
--   §2 the telegraph: the ring shows WarnSeconds before the impact, the banner names the hazard;
--   §3 a hit: standing in the ring at the impact knocks you down (PlatformStand, a horizontal push of
--      KnockPush, never up, released after KnockSeconds, a flash); the passage next door is safe;
--   §4 only within ShowRadius (inside the torch), at most MaxHazardsShown drawn;
--   §5 no hazard in the dungeon or the jungle; every later biome draws its own kind;
--   §6 the timeline is the LEVEL clock: a new run starts it again;
--   §7 a dead player is never knocked;
--   §8 (resume session) height: a player at the top of a jump in the ring is knocked (a jump is no
--      dodge), a god-mode flyer 40 studs over it is not;
--   §9-§11 (review fix) a knock is released when you leave the maze; a knock never lifts you, even on
--      a jump's way up; over whole levels where it matters, the real client keeps hazards off the
--      server's real trap cells (and misses none of the pure rule's). Also in §1: the ring's own colour.
-- The level clock here is known exactly: the client's clock is the sum of the frames this file fires.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill hazards")
local truthy, eq, near = T.truthy, T.eq, T.near

local ctx = Lib.boot({ accepted = 400, clients = Lib.CLIENTS_NO_SOUND })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local EnvBands = mod("EnvBands")
local Biomes = mod("Biomes")
local CellHazards = mod("CellHazards")
local HZ = Biomes.Hazards
local LOCAL = h.workspace:FindFirstChild("LabyrintBiomeLocal")
local banner = ctx.plr.PlayerGui:FindFirstChild("LabyrintBiome").Root.HazardBanner

local levelT0 = 0
local function start(level)
	if ctx.folder() ~= nil then ctx.toLobby() end
	levelT0 = ctx.clock
	local sr = h.ReplicatedStorage.LobbyRemotes.StartRun
	sr:simulateFireServer(ctx.plr, level, "solo")
	ctx.run(1.0) -- the client reads the grid twice before it places hazards
end
local function levelTime() return ctx.clock - levelT0 end

local function rings()
	local out = {}
	for _, d in LOCAL:GetChildren() do
		if d.Name == "HazardRing" then table.insert(out, d) end
	end
	return out
end

-- expected hazards for the level being played, from the real folder
local function expected(level)
	local g = Lib.grid(ctx.folder())
	local list = CellHazards.pick(level, g.cols, g.rows, g.traps, Biomes.Seed, HZ)
	local out = {}
	for _, hz in list do
		local w = g.world(2 * hz.cx + 1, 2 * hz.cy + 1)
		table.insert(out, { hz = hz, centre = w, g = g })
	end
	return out, g
end

-- run until level time reaches t, standing at `pos`
local function runTo(t, pos, each)
	while levelTime() < t - 1e-9 do
		if pos then ctx.moveTo(pos) end
		ctx.frame(1 / 30)
		if each then each() end
	end
end

--================================================================ §1 + §2 + §3 on an ice-cellar level

local LEVEL = 60 -- forge, 11x11: several hazards
start(LEVEL)
local list, g = expected(LEVEL)
print(string.format("== L%d (%s): %d hazard cells by the pure rule, %d trap cells in the real maze", LEVEL,
	Biomes.band(EnvBands, LEVEL).name, #list, (function() local n = 0 for _ in g.traps do n += 1 end return n end)()))
truthy(#list >= 2, "the level has hazards to check")
do
	-- none on a trap, the start, the exit (the pure rule's inputs are the server's real trap cells)
	local bad = 0
	for _, e in list do
		if g.traps[e.hz.cx .. "," .. e.hz.cy] then bad += 1 end
		if (e.hz.cx == 0 and e.hz.cy == 0) or (e.hz.cx == g.cols - 1 and e.hz.cy == g.rows - 1) then bad += 1 end
	end
	eq(bad, 0, "no hazard cell is a trap cell, the start or the exit of the real maze")
end

-- a hazard's world centre (floor level) as the client draws it
local function ringAt(e)
	for _, r in rings() do
		if math.abs(r.Position.X - e.centre.X) < 0.25 and math.abs(r.Position.Z - e.centre.Z) < 0.25 then return r end
	end
	return nil
end

do
	local e = list[1]
	local first = CellHazards.firstImpact(e.hz, HZ)
	-- the passage next to the cell: one fine step away, open by construction (the cell has an open side)
	local passage = nil
	local fx, fy = 2 * e.hz.cx + 1, 2 * e.hz.cy + 1
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if g.walls[(fx + d[1]) .. "," .. (fy + d[2])] == nil then passage = g.world(fx + d[1], fy + d[2]); break end
	end
	truthy(passage ~= nil, "the hazard cell has an open passage beside it")
	-- stand in the passage through a whole warning and the impact
	local firstSeen, bannerSeen, strayRing = nil, false, 0
	runTo(first - HZ.WarnSeconds - 0.5, passage)
	eq(ringAt(e), nil, "before the warning the cell shows nothing")
	runTo(first - 0.01, passage, function()
		local r = ringAt(e)
		if r and firstSeen == nil then firstSeen = levelTime() end
		if banner.Visible and string.find(banner.Text, HZ.Kinds[Biomes.band(EnvBands, LEVEL).hazard].label, 1, true) then bannerSeen = true end
		for _, rr in rings() do
			local ok = false
			for _, x in list do
				if math.abs(rr.Position.X - x.centre.X) < 0.25 and math.abs(rr.Position.Z - x.centre.Z) < 0.25 then ok = true end
			end
			if not ok then strayRing += 1 end
		end
	end)
	truthy(firstSeen ~= nil, "the ring appears at exactly the cell the pure rule names")
	truthy(firstSeen ~= nil and first - firstSeen >= HZ.WarnSeconds - 1 / 30 - 1e-6,
		string.format("the warning shows %.2f s before the impact (>= %.1f)", firstSeen and (first - firstSeen) or -1, HZ.WarnSeconds))
	eq(strayRing, 0, "no ring ever appears anywhere the pure rule did not put a hazard")
	truthy(bannerSeen, "the banner names the hazard while it is due and the player is near")
	local r = ringAt(e)
	near(r and r.Size.Y or 0, 2 * (HZ.StrikeRadius + HZ.PlayerRadius), 0.01, "the ring is exactly as wide as the zone the hit test uses")
	truthy(r and r.Material.Name == "Neon", "the warning ring glows (a warning is meaningful)")
	-- (review fix) the ring has its OWN colour. Glowing yellow on this maze's floor has always meant "this
	-- floor kills you in a moment" (the trap's WARNING phase); a ring in that yellow that only knocks you down
	-- teaches players that yellow is survivable. The server's own palette avoids the trap's yellow for the same
	-- reason (MazeGame.server, PAIR_COLORS). Read against the server's real TRAP_LOOK, not a copy.
	do
		local src = Lib.serverSource(ctx.bundle)
		local warn = { string.match(src, "warn%s*=%s*{%s*Color = Color3.fromRGB%((%d+), (%d+), (%d+)%)") }
		local deadly = { string.match(src, "deadly%s*=%s*{%s*Color = Color3.fromRGB%((%d+), (%d+), (%d+)%)") }
		local c = r and Lib.rgb(r.Color) or { -1, -1, -1 }
		local want = HZ.RingColor or {}
		eq(c[1] .. "," .. c[2] .. "," .. c[3], tostring(want[1]) .. "," .. tostring(want[2]) .. "," .. tostring(want[3]),
			"the real client draws the ring in Biomes.Hazards.RingColor")
		truthy(#warn == 3 and #deadly == 3, "the server's trap WARN and DEADLY colours are found")
		local function dist(a, b) return math.abs(a[1] - tonumber(b[1])) + math.abs(a[2] - tonumber(b[2])) + math.abs(a[3] - tonumber(b[3])) end
		truthy(#warn == 3 and dist(c, warn) >= 200, string.format("the ring is nothing like the trap's WARNING yellow (%s vs %s)", table.concat(c, ","), table.concat(warn, ",")))
		truthy(#deadly == 3 and dist(c, deadly) >= 200, string.format("nor the trap's DEADLY orange (%s vs %s)", table.concat(c, ","), table.concat(deadly, ",")))
		truthy(c[3] > c[1] and c[3] > c[2], "it reads blue: cold, where both trap phases are warm")
	end
	-- the impact, standing in the passage: no knock
	runTo(first + 0.2, passage)
	eq(ctx.hum.PlatformStand == true, false, "the passage beside a hazard is safe at the impact")

	-- next impact: stand at the centre of the cell
	local second = first + HZ.Period
	local centre = Vector3.new(e.centre.X, 4, e.centre.Z)
	runTo(second - 0.05, centre)
	eq(ctx.hum.PlatformStand == true, false, "standing in the ring is safe during the warning")
	local flashes = 0
	for _, gg in ctx.plr.PlayerGui:GetChildren() do if gg.Name == "FxFlash" then flashes += 1 end end
	ctx.moveTo(centre + Vector3.new(1.5, 0, 0))
	runTo(second + 1 / 30, nil)
	eq(ctx.hum.PlatformStand == true, true, "standing in the ring at the impact knocks the player down")
	local v = ctx.hrp.AssemblyLinearVelocity
	near(math.sqrt(v.X * v.X + v.Z * v.Z), HZ.KnockPush, 1e-6, "the push is KnockPush studs/s, horizontal")
	truthy(v.X > 0, "away from the impact")
	truthy(v.Y <= 0, "and never upward")
	local flashesAfter = 0
	for _, gg in ctx.plr.PlayerGui:GetChildren() do if gg.Name == "FxFlash" then flashesAfter += 1 end end
	truthy(flashesAfter > flashes, "a hit flashes the screen")
	runTo(second + HZ.KnockSeconds - 0.1, nil)
	eq(ctx.hum.PlatformStand == true, true, "still down just before KnockSeconds")
	runTo(second + HZ.KnockSeconds + 0.1, nil)
	eq(ctx.hum.PlatformStand == true, false, "up again after KnockSeconds")
	-- the edge of the zone
	local third = second + HZ.Period
	runTo(third - 0.05, centre + Vector3.new(HZ.StrikeRadius + HZ.PlayerRadius + 0.2, 0, 0))
	runTo(third + 1 / 30, nil)
	eq(ctx.hum.PlatformStand == true, false, "just outside the ring is safe at the impact")
end

--================================================================ §4 only near, at most two

do
	local maxShown, farDrawn = 0, 0
	local pos = g.world(1, 1)
	for i = 1, 40 * 30 do
		-- wander between cells so different hazards come into and out of range
		if i % 45 == 0 then
			local c = (i // 45) % (g.cols * g.rows)
			pos = g.world(2 * (c % g.cols) + 1, 2 * (c // g.cols) + 1)
		end
		ctx.moveTo(pos)
		ctx.frame(1 / 30)
		local rs = rings()
		maxShown = math.max(maxShown, #rs)
		for _, r in rs do
			local dx, dz = r.Position.X - pos.X, r.Position.Z - pos.Z
			if math.sqrt(dx * dx + dz * dz) > HZ.ShowRadius + 1e-6 then farDrawn += 1 end
		end
	end
	truthy(maxShown >= 1, "hazards were drawn during the walk (" .. maxShown .. ")")
	truthy(maxShown <= Biomes.Budget.MaxHazardsShown, "never more than MaxHazardsShown drawn at once (" .. maxShown .. ")")
	eq(farDrawn, 0, "never drawn beyond ShowRadius (a glowing ring must not reveal a cell outside the torch)")
end

--================================================================ §5 bands: none early, own kind later

local KIND_PART = { icicle = "Icicle", lavabomb = "LavaBomb", shard = "Shard", chandelier = "Hoop", lightning = "StormPuff", meteor = "Meteor" }
for _, L in { 5, 18 } do
	start(L)
	local g2 = Lib.grid(ctx.folder())
	local seen = 0
	for i = 1, 30 * 30 do
		if i % 30 == 0 then
			local c = (i // 30) % (g2.cols * g2.rows)
			ctx.moveTo(g2.world(2 * (c % g2.cols) + 1, 2 * (c // g2.cols) + 1))
		end
		ctx.frame(1 / 30)
		seen += #rings()
	end
	eq(seen, 0, "no hazard ever drawn in " .. Biomes.band(EnvBands, L).name .. " (L" .. L .. ")")
end
for i, b in Biomes.Bands do
	if b.hazard then
		local nextFrom = if Biomes.Bands[i + 1] then Biomes.Bands[i + 1].from else b.from + 50
		local L = math.floor((b.from + nextFrom) / 2)
		start(L)
		local l2 = expected(L)
		truthy(#l2 >= 1, b.name .. " L" .. L .. " has hazards")
		local e = l2[1]
		if e then
			local first = CellHazards.firstImpact(e.hz, HZ)
			runTo(first - HZ.WarnSeconds / 2, Vector3.new(e.centre.X, 4, e.centre.Z + HZ.CellSize))
			local found = false
			for _, d in LOCAL:GetChildren() do
				if d.Name == KIND_PART[b.hazard] then found = true end
			end
			truthy(found, b.name .. " draws its own hazard (" .. b.hazard .. ")")
			truthy(banner.Visible and string.find(banner.Text, HZ.Kinds[b.hazard].label, 1, true) ~= nil,
				b.name .. " banner names it: " .. tostring(banner.Text))
		end
	end
end

--================================================================ §6 the level clock restarts with the run

do
	local L = 60
	start(L)
	local l3 = expected(L)
	local e = l3[1]
	local first = CellHazards.firstImpact(e.hz, HZ)
	local centre = Vector3.new(e.centre.X, 4, e.centre.Z)
	-- let 7 s of this run pass, then start the SAME level again: the first impact is again at `first`
	runTo(7, centre)
	start(L)
	local e2 = expected(L)[1]
	eq(e2.hz.cx .. "," .. e2.hz.cy .. "," .. e2.hz.phase, e.hz.cx .. "," .. e.hz.cy .. "," .. e.hz.phase,
		"the same level places the same hazards in a new run")
	local c2 = Vector3.new(e2.centre.X, 4, e2.centre.Z)
	runTo(first - 0.05, c2)
	eq(ctx.hum.PlatformStand == true, false, "the new run's first impact has not come early")
	ctx.moveTo(c2)
	runTo(first + 1 / 30, c2)
	eq(ctx.hum.PlatformStand == true, true, "and comes exactly at the level-clock time the pure rule says")
	runTo(first + 1.2, nil)

	--================================================================ §8 height: a flyer is not hit, a jumper is
	-- (resume session) The client passes the root's height; the pure rule caps an impact at MaxHitHeight over
	-- the floor's top. Measured against the real Floor part, not the client's own number.
	local floor = ctx.folder():FindFirstChild("Floor")
	local floorTop = floor.Position.Y + floor.Size.Y / 2
	local second = first + HZ.Period
	local high = Vector3.new(c2.X, floorTop + 40, c2.Z)
	runTo(second - 0.05, high)
	runTo(second + 1 / 30, high)
	eq(ctx.hum.PlatformStand == true, false, "a god-mode flyer 40 studs over the ring is not knocked out of the air")
	local third = second + HZ.Period
	local apex = Vector3.new(c2.X, floorTop + 10.5, c2.Z)
	runTo(third - 0.05, apex)
	runTo(third + 1 / 30, apex)
	eq(ctx.hum.PlatformStand == true, true, "a player at the top of a jump in the ring IS knocked (a jump is no dodge)")
	runTo(third + 1.2, nil)

	--================================================================ §7 a dead player is never knocked
	local fourth = third + HZ.Period
	runTo(fourth - 0.1, c2)
	ctx.hum.Health = 0
	runTo(fourth + 0.1, c2)
	eq(ctx.hum.PlatformStand == true, false, "a dead player is not knocked")
end

--================================================================ (review fix) three rules no suite held
-- The adversarial review's own mutation sweep: a client that kept a knock after leaving the maze (M1) and one
-- that let a knock keep upward speed (M4) passed every suite, and a client that ignored the server's trap
-- cells (M2) or mapped them one cell off (M3) was caught only by one level of the shot-list check.

-- §9 a knock is released when you leave the maze. In the lobby the frame loop never runs the hazards, so a
-- knock kept past leaving would stand the player frozen (PlatformStand) in the lobby until the next run.
local function respawnIfDead()
	if ctx.hum.Health <= 0 then
		local char = h.Players:simulateSpawn(ctx.plr, h.workspace)
		ctx.run(0.5)
		ctx.char, ctx.hrp, ctx.hum = char, char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
		ctx.hum.FloorMaterial = Enum.Material.Plastic
		ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
	end
end
respawnIfDead()
do
	local L = 60
	start(L)
	local e = expected(L)[1]
	local first = CellHazards.firstImpact(e.hz, HZ)
	local c = Vector3.new(e.centre.X + 1, 4, e.centre.Z)
	runTo(first - 0.05, c)
	runTo(first + 1 / 30, c)
	eq(ctx.hum.PlatformStand == true, true, "§9 knocked down at the impact")
	ctx.toLobby() -- the Lobby door, 0.1 s into the knock
	eq(ctx.folder(), nil, "§9 back in the lobby")
	eq(ctx.hum.PlatformStand == true, false, "§9 leaving the maze while knocked down gets you up (no frozen player in the lobby)")
	ctx.run(2)
	eq(ctx.hum.PlatformStand == true, false, "§9 and you stay up in the lobby")
end

-- §10 a knock never lifts you, even when it lands while you are going up (a jump's take-off)
do
	local L = 60
	start(L)
	local e = expected(L)[1]
	local first = CellHazards.firstImpact(e.hz, HZ)
	local floor = ctx.folder():FindFirstChild("Floor")
	local floorTop = floor.Position.Y + floor.Size.Y / 2
	local rising = Vector3.new(e.centre.X + 1, floorTop + 5, e.centre.Z)
	runTo(first - 0.05, rising)
	ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, 25, 0) -- a jump's take-off speed, going up at the impact
	runTo(first + 1 / 30, rising)
	eq(ctx.hum.PlatformStand == true, true, "§10 a player going up in the ring is knocked (a jump is no dodge)")
	local v = ctx.hrp.AssemblyLinearVelocity
	truthy(v.Y <= 0, string.format("§10 and the knock takes the upward speed away (vy %.1f): a hazard never lifts you", v.Y))
	near(math.sqrt(v.X * v.X + v.Z * v.Z), HZ.KnockPush, 1e-6, "§10 the push is still KnockPush, horizontal")
	runTo(first + 1.2, nil)
	ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end

-- §11 the REAL client keeps its hazards off the server's real trap cells, over whole levels. Find levels where
-- the trap exclusion matters (the pure rule WITHOUT the traps would put a hazard on a trap); there, stand beside
-- every hazard cell the pure rule names (with the real traps) and see the client's ring, and beside every
-- trap cell for a whole cycle and see none. Any client that reads the trap cells wrongly (ignores them, maps
-- them one cell off, ...) either draws a ring on a trap or misses a real hazard cell.
do
	local function passageBeside(g, cx, cy)
		local fx, fy = 2 * cx + 1, 2 * cy + 1
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if g.walls[(fx + d[1]) .. "," .. (fy + d[2])] == nil then return g.world(fx + d[1], fy + d[2]) end
		end
		return nil
	end
	local levelsDone, ringsSeen, trapsWatched, ringOnTrap, missed = 0, 0, 0, 0, 0
	for L = 60, 140 do
		if levelsDone >= 2 then break end
		start(L)
		respawnIfDead()
		local g = Lib.grid(ctx.folder())
		local real = CellHazards.pick(L, g.cols, g.rows, g.traps, Biomes.Seed, HZ)
		local naive = CellHazards.pick(L, g.cols, g.rows, {}, Biomes.Seed, HZ)
		local matters = false
		for _, hz in naive do
			if g.traps[hz.cx .. "," .. hz.cy] then matters = true end
		end
		if matters then
			levelsDone += 1
			local nTraps = 0
			for _ in g.traps do nTraps += 1 end
			print(string.format("== §11 L%d: %d hazard cells, %d trap cells; without the traps the rule would put a hazard on a trap", L, #real, nTraps))
			-- every real hazard cell: its ring shows within one cycle
			for _, hz in real do
				local stand = passageBeside(g, hz.cx, hz.cy)
				local c = g.world(2 * hz.cx + 1, 2 * hz.cy + 1)
				local seen = false
				local tEnd = levelTime() + HZ.Period + 0.5
				runTo(tEnd, stand, function()
					if ringAt({ centre = c }) then seen = true end
				end)
				if seen then ringsSeen += 1 else missed += 1; print(string.format("   L%d: no ring at hazard cell %d,%d in a whole cycle", L, hz.cx, hz.cy)) end
			end
			-- every trap cell: no ring, a whole cycle long
			for key in g.traps do
				local cx, cy = string.match(key, "(%-?%d+),(%-?%d+)")
				cx, cy = tonumber(cx), tonumber(cy)
				local stand = passageBeside(g, cx, cy)
				local c = g.world(2 * cx + 1, 2 * cy + 1)
				trapsWatched += 1
				local tEnd = levelTime() + HZ.Period + 0.5
				runTo(tEnd, stand, function()
					if ringAt({ centre = c }) then ringOnTrap += 1 end
				end)
			end
		end
	end
	eq(levelsDone, 2, "§11 two levels where the trap exclusion matters were found and walked")
	truthy(ringsSeen > 0 and missed == 0, string.format("§11 the client draws a ring at every hazard cell the pure rule names with the real traps (%d seen, %d missed)", ringsSeen, missed))
	truthy(trapsWatched > 0, "§11 trap cells were watched (" .. trapsWatched .. ")")
	eq(ringOnTrap, 0, "§11 and never a ring on a trap cell, a whole cycle each")
end

T.finish(h)
