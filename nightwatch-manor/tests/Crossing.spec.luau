-- Crossing: the guard on the Servants' Exit that keeps the highscore board honest. Run from the game directory:
--   luau tests/Crossing.spec.luau
--
-- The board ranks the best night the server credited you with surviving, and the only way to survive a night is the
-- Servants' Exit. A player's character is moved by the player's own client in Roblox, so a script can put it next to
-- the exit door a second into the night and press E. The guard refuses that, with two rules, both measured by the
-- server:
--   * REACH: the character is standing within the prompt's reach of the door (plus Config.Guard.ReachSlack);
--   * TIME:  the night has run at least Crossing.minSeconds: the SHORTEST possible walk from where the night puts
--            you to within reach of the door, through the doorways, at Config.Player.WalkSpeed.
-- minDistance must be a true LOWER BOUND on every legal walk (a player walking the perfect line is never refused),
-- and tight enough to bind (a script gains nothing by being faster than a person).
local Crossing = require("../src/shared/Crossing")
local Manor = require("../src/shared/Manor")
local Rng = require("../src/shared/Rng")
local Night = require("../src/shared/Night")
local Upgrades = require("../src/shared/Upgrades")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local G = Config.Guard
truthy(type(G) == "table", "Config.Guard exists")
truthy(G.ReachSlack >= 0 and G.ReachSlack <= 6, "the reach slack is a few studs (" .. tostring(G.ReachSlack) .. ")")
truthy(G.ClockSlack >= 0 and G.ClockSlack <= 1, "the clock slack is under a second (" .. tostring(G.ClockSlack) .. ")")
eq(G.ExitPromptDistance, 12, "the exit prompt reaches 12 studs, like every prompt in the game")

local function planOf(night: number)
	return Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
end

--======================================================================= geometry primitives

approx(Crossing.pointSeg(0, 5, { x1 = -3, z1 = 0, x2 = 3, z2 = 0 }), 5, 1e-9, "a point above a segment's middle: the perpendicular")
approx(Crossing.pointSeg(6, 4, { x1 = -3, z1 = 0, x2 = 3, z2 = 0 }), 5, 1e-9, "a point past its end: the distance to the end (3-4-5)")
approx(Crossing.segSeg({ x1 = 0, z1 = 0, x2 = 0, z2 = 10 }, { x1 = 3, z1 = 0, x2 = 3, z2 = 10 }), 3, 1e-9, "two parallel segments 3 apart")
approx(Crossing.segSeg({ x1 = -5, z1 = 0, x2 = 5, z2 = 0 }, { x1 = 0, z1 = -5, x2 = 0, z2 = 5 }), 0, 1e-9, "crossing segments touch")
approx(Crossing.segSeg({ x1 = 0, z1 = 0, x2 = 4, z2 = 0 }, { x1 = 7, z1 = 4, x2 = 7, z2 = 9 }), 5, 1e-9, "end to end: 3-4-5")

--======================================================================= the doorways are where the walls' holes are

do
	local plan = planOf(7)
	local segs = Crossing.doorways(Config, plan)
	eq(#segs, #plan.links, "one doorway segment per link")
	local ok, bad = true, nil
	for _, s in segs do
		local mx, mz = Manor.doorwayBetween(Config, plan, s.a, s.b)
		local len = math.sqrt((s.x2 - s.x1) ^ 2 + (s.z2 - s.z1) ^ 2)
		local cx, cz = (s.x1 + s.x2) / 2, (s.z1 + s.z2) / 2
		if math.abs(cx - (mx :: number)) > 1e-9 or math.abs(cz - (mz :: number)) > 1e-9 or math.abs(len - Config.Manor.DoorWidth) > 1e-9 then
			ok = false; bad = bad or string.format("%d-%d", s.a, s.b)
		end
		-- the gap runs ALONG the shared wall: across the step between the two rooms
		local ra, rb = Manor.roomById(plan, s.a), Manor.roomById(plan, s.b)
		local stepX = (ra :: any).gx ~= (rb :: any).gx
		if stepX and s.x1 ~= s.x2 then ok = false; bad = bad or "orientation" end
		if not stepX and s.z1 ~= s.z2 then ok = false; bad = bad or "orientation" end
	end
	truthy(ok, "every segment is DoorWidth long, centred on the doorway, along the shared wall" .. (if bad then " (" .. bad .. ")" else ""))
end

--======================================================================= where the night puts you, where the door is

do
	local plan = planOf(3)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = Manor.roomCenter(Config, Manor.roomById(plan, plan.entranceId) :: any)
	eq(sx, ex, "the start is the entrance's centre in x ...")
	eq(sz, ez + 12, "... and 12 studs in, where beginNight teleports you")
	local dx, dz = Crossing.exitDoor(Config, plan, Manor)
	local cx, cz = Manor.roomCenter(Config, Manor.roomById(plan, plan.exitId) :: any)
	local fx, fz = Manor.exitFace(Config, plan)
	eq(dx, cx + (fx :: number) * (Config.Manor.RoomSize / 2 - 6), "the door stands six studs inside the exit face (x)")
	eq(dz, cz + (fz :: number) * (Config.Manor.RoomSize / 2 - 6), "... (z)")
end

--======================================================================= a LOWER bound on every legal walk

-- A legal walk: start -> a point on each doorway of a room path (each leg inside one convex room) -> a point
-- within reach of the door inside the exit room. Its length is >= minDistance for EVERY such walk, or a player walking
-- that line would be refused. Checked on the doorway midpoints (the natural route), on random points of each gap, and
-- on the best walk a fine search can find (11 points per gap), for nights 1-150.
local REACH = G.ExitPromptDistance + G.ReachSlack
local function legLen(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end
local function segPoint(s, t) return s.x1 + (s.x2 - s.x1) * t, s.z1 + (s.z2 - s.z1) * t end

-- DP over room paths with gaps discretised: the shortest LEGAL walk it can find (an upper bound on the true optimum).
local function searchBest(plan, segs, sx, sz, dx, dz, K)
	local byRoom: { [number]: { any } } = {}
	for _, s in segs do
		byRoom[s.a] = byRoom[s.a] or {}
		byRoom[s.b] = byRoom[s.b] or {}
		table.insert(byRoom[s.a], s)
		table.insert(byRoom[s.b], s)
	end
	-- nodes: (segment index, point k, room the walker is now in)
	local best = math.huge
	local dist: { [string]: number } = {}
	local frontier = {}
	local function push(key, d, node)
		if d < (dist[key] or math.huge) then
			dist[key] = d
			table.insert(frontier, { key = key, d = d, node = node })
		end
	end
	-- a walk ends INSIDE the exit room (pass 2, 2026-10-01: the server refuses a press from anywhere else, because the
	-- prompt needs no line of sight and reached through the wall from the room next door; on one salted night-45
	-- manor that was 0.13 s from where the night starts)
	local nearRoom = { [plan.exitId] = true }
	local function finish(room, px, pz, d)
		if nearRoom[room] then
			best = math.min(best, d + math.max(0, legLen(px, pz, dx, dz) - REACH))
		end
	end
	finish(plan.entranceId, sx, sz, 0)
	for _, s in byRoom[plan.entranceId] or {} do
		for k = 0, K do
			local px, pz = segPoint(s, k / K)
			local into = if s.a == plan.entranceId then s.b else s.a
			push(s.a .. "-" .. s.b .. ":" .. k .. ">" .. into, legLen(sx, sz, px, pz), { s = s, k = k, room = into, x = px, z = pz })
		end
	end
	while #frontier > 0 do
		local bi = 1
		for i = 2, #frontier do if frontier[i].d < frontier[bi].d then bi = i end end
		local cur = table.remove(frontier, bi)
		if cur.d <= (dist[cur.key] or math.huge) then
			local n = cur.node
			finish(n.room, n.x, n.z, cur.d)
			for _, s in byRoom[n.room] or {} do
				local into = if s.a == n.room then s.b else s.a
				for k = 0, K do
					local px, pz = segPoint(s, k / K)
					push(s.a .. "-" .. s.b .. ":" .. k .. ">" .. into, cur.d + legLen(n.x, n.z, px, pz), { s = s, k = k, room = into, x = px, z = pz })
				end
			end
		end
	end
	return best
end

do
	local rand = Rng.new(8675309)
	local midOk, randOk, searchOk, tight = 0, 0, 0, 0
	local worstGap, worstNight = 0, 0
	local minS, maxS, sumS = math.huge, 0, 0
	local NIGHTS = 150
	for night = 1, NIGHTS do
		local plan = planOf(night)
		local segs = Crossing.doorways(Config, plan)
		local sx, sz = Crossing.start(Config, plan)
		local dx, dz = Crossing.exitDoor(Config, plan, Manor)
		local lower = Crossing.minDistance(Config, plan, sx, sz, dx, dz, REACH)
		local path = Manor.pathBetween(plan, plan.entranceId, plan.exitId) :: { number }
		-- the doorway midpoints along the fewest-rooms path
		local len, px, pz = 0, sx, sz
		for i = 1, #path - 1 do
			local mx, mz = Manor.doorwayBetween(Config, plan, path[i], path[i + 1])
			len += legLen(px, pz, mx :: number, mz :: number)
			px, pz = mx :: number, mz :: number
		end
		len += math.max(0, legLen(px, pz, dx, dz) - REACH)
		if len >= lower - 1e-9 then midOk += 1 end
		-- random points in each gap along the same path, 20 times
		local allRand = true
		for _ = 1, 20 do
			local l2, qx, qz = 0, sx, sz
			for i = 1, #path - 1 do
				for _, s in segs do
					if (s.a == path[i] and s.b == path[i + 1]) or (s.b == path[i] and s.a == path[i + 1]) then
						local rx, rz = segPoint(s, rand:next())
						l2 += legLen(qx, qz, rx, rz)
						qx, qz = rx, rz
					end
				end
			end
			l2 += math.max(0, legLen(qx, qz, dx, dz) - REACH)
			if l2 < lower - 1e-9 then allRand = false end
		end
		if allRand then randOk += 1 end
		-- the best legal walk a search finds
		local found = searchBest(plan, segs, sx, sz, dx, dz, 10)
		if found >= lower - 1e-9 then searchOk += 1 end
		if found - lower <= Config.Manor.DoorWidth then tight += 1 end
		if found - lower > worstGap then worstGap, worstNight = found - lower, night end
		local secs = Crossing.minSeconds(Config, plan, Manor)
		minS, maxS, sumS = math.min(minS, secs), math.max(maxS, secs), sumS + secs
	end
	print(string.format("  nights 1-%d: the guard's minimum crossing %.1f-%.1f s (mean %.1f); the widest gap to the best walk a search found: %.1f studs (night %d)",
		NIGHTS, minS, maxS, sumS / NIGHTS, worstGap, worstNight))
	eq(midOk, NIGHTS, "the doorway-midpoint route is never shorter than the bound")
	eq(randOk, NIGHTS, "nor is any of 20 random walks through each gap, on any night")
	eq(searchOk, NIGHTS, "nor the best walk a search over 11 points per gap can find")
	eq(tight, NIGHTS, "and the bound is within one door width of that best walk on every night (it binds: a script gains ~0.5 s)")
	truthy(minS > 1, string.format("the guard binds on every night: the shortest crossing is never under a second (%.1f s)", minS))
end

--======================================================================= the verdict

do
	local plan = planOf(5)
	local need = Crossing.minSeconds(Config, plan, Manor)
	truthy(need > 0, "night 5 has a minimum crossing time (" .. string.format("%.2f", need) .. " s)")
	local sx, sz = Crossing.start(Config, plan)
	local dx, dz = Crossing.exitDoor(Config, plan, Manor)
	local dist = Crossing.minDistance(Config, plan, sx, sz, dx, dz, Crossing.reach(Config))
	approx(need, math.max(0, dist / Config.Player.WalkSpeed - G.ClockSlack), 1e-9,
		"minSeconds is the shortest crossing at WalkSpeed, less the clock slack")
	eq(Crossing.reach(Config), G.ExitPromptDistance + G.ReachSlack, "the reach is the exit prompt's own distance + the slack")
	local ok, why = Crossing.verdict(Config, plan, Manor, need + 0.01, 3)
	truthy(ok and why == nil, "at the door after the shortest crossing: the exit opens")
	ok, why = Crossing.verdict(Config, plan, Manor, need - 0.2, 3)
	truthy(not ok and why == "fast", "a fifth of a second too soon: refused as too fast")
	ok, why = Crossing.verdict(Config, plan, Manor, need + 60, Crossing.reach(Config) + 0.5)
	truthy(not ok and why == "far", "further than the prompt's reach + slack: refused as too far")
	ok, why = Crossing.verdict(Config, plan, Manor, need + 60, Crossing.reach(Config) - 0.5)
	truthy(ok, "inside the reach + slack: fine")
	ok, why = Crossing.verdict(Config, plan, Manor, 0, 99)
	eq(why, "far", "both wrong: 'far' is the one reported (stand at the door first)")
	local _, _, wait = Crossing.verdict(Config, plan, Manor, need - 2, 3)
	approx(wait, 2, 1e-9, "a refusal for speed says how long is left (2 s)")
	-- the server's form: minSeconds worked out once per night, passed in
	local ok2, why2 = Crossing.verdictFor(Config, need, need - 0.01, 3)
	truthy(not ok2 and why2 == "fast", "verdictFor: the same rule with the night's minimum passed in")
	ok2 = Crossing.verdictFor(Config, need, need, 0 / 0)
	truthy(not ok2, "no character position (NaN) is never at the door")
	-- THROUGH THE WALL (pass 2): close enough to the door, long enough into the night, but not in the exit room
	local ok3, why3 = Crossing.verdictFor(Config, need, need + 60, 3, false)
	truthy(not ok3 and why3 == "far", "within reach of the door but NOT in the exit room (through a wall): refused, stand at the exit")
	local ok4 = Crossing.verdictFor(Config, need, need + 60, 3, true)
	truthy(ok4, "the same, standing in the exit room: fine")
	local ok5, why5 = Crossing.verdict(Config, plan, Manor, need + 60, 3, false)
	truthy(not ok5 and why5 == "far", "verdict passes the room through to the same rule")
end

--======================================================================= the night is always long enough

do
	local short = 0
	local none = Upgrades.effects(Config, {})
	for night = 1, 500 do
		local plan = planOf(night)
		if Crossing.minSeconds(Config, plan, Manor) >= 0.5 * Night.dreadSeconds(Config, night, none) then short += 1 end
	end
	eq(short, 0, "on no night of 1-500 does the shortest crossing take even half the night")
end

--======================================================================= the game's manors: salted

-- Since 2026-10-01 every manor the server builds is planned from Salt halves (Salt.luau, Main.server), never from the
-- public seed the checks above walk. The same bound over salted manors: never longer than a legal walk (the doorway
-- midpoints; the best walk a search finds), within a door width of the best one, and never under 1.5 s
-- (robloxemu/check_nightwatchmanor_guard presses "too soon" about 0.9 s into a night, so that refusal is certain).
do
	local Salt = require("../src/shared/Salt")
	local src = Salt.new(20261001, 424242)
	local N, okMid, okSearch, tightN = 60, 0, 0, 0
	for i = 1, N do
		local night = i
		local plan = Manor.plan(Salt.new(Salt.step(src), Salt.step(src)), Config, night)
		local segs = Crossing.doorways(Config, plan)
		local sx, sz = Crossing.start(Config, plan)
		local dx, dz = Crossing.exitDoor(Config, plan, Manor)
		local lower = Crossing.minDistance(Config, plan, sx, sz, dx, dz, REACH)
		local path = Manor.pathBetween(plan, plan.entranceId, plan.exitId) :: { number }
		local len, px, pz = 0, sx, sz
		for k = 1, #path - 1 do
			local mx, mz = Manor.doorwayBetween(Config, plan, path[k], path[k + 1])
			len += legLen(px, pz, mx :: number, mz :: number)
			px, pz = mx :: number, mz :: number
		end
		len += math.max(0, legLen(px, pz, dx, dz) - REACH)
		if len >= lower - 1e-9 then okMid += 1 end
		local found = searchBest(plan, segs, sx, sz, dx, dz, 10)
		if found >= lower - 1e-9 then okSearch += 1 end
		if found - lower <= Config.Manor.DoorWidth then tightN += 1 end
	end
	eq(okMid, N, string.format("salted manors (nights 1-%d): the doorway-midpoint route is never shorter than the bound", N))
	eq(okSearch, N, "...nor the best walk a search over 11 points per gap can find")
	eq(tightN, N, "...and the bound is within one door width of that best walk on every one")
	local minS, maxS, sumS, M = math.huge, 0, 0, 0
	for night = 1, 60 do
		for _ = 1, 50 do
			local s = Crossing.minSeconds(Config, Manor.plan(Salt.new(Salt.step(src), Salt.step(src)), Config, night), Manor)
			minS, maxS, sumS, M = math.min(minS, s), math.max(maxS, s), sumS + s, M + 1
		end
	end
	print(string.format("  %d salted manors, nights 1-60: the guard's minimum crossing %.2f-%.2f s (mean %.2f)", M, minS, maxS, sumS / M))
	truthy(minS >= 1.5, string.format("on %d salted manors the shortest crossing is never under 1.5 s (%.2f)", M, minS))
end

--======================================================================= CONTROL

-- Renaming the exit room's kind changes no distance.
do
	local plan = planOf(9)
	local before = Crossing.minSeconds(Config, plan, Manor)
	for _, r in plan.rooms do if r.id == plan.exitId then r.kind = "chapel" end end
	eq(Crossing.minSeconds(Config, plan, Manor), before, "CONTROL: a room's kind is not geometry")
end

print(string.format("Crossing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Crossing tests failed") end
