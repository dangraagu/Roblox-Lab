-- PosGuard: the position guard that keeps a void night off the highscore board. Run from the game directory:
--   luau tests/PosGuard.spec.luau
--
-- The exit's guard (Crossing.spec) measures the clock and the room at the moment of the press. That left a hole
-- (second review, 2026-10-09, HIGH): the Nightwatcher sees by ROOM, so a character parked outside every room is never
-- seen; a script could wait out the clock there and teleport to the door, one safe night every ~12 s. The server now
-- samples the root every tick of a night and voids the night on either kind of evidence:
--   * OUTSIDE: in no room for more than Config.Guard.OutsideGraceSeconds of the night, in total;
--   * JUMP:    more ground covered than a walk allows (a bank of studs: JumpSlack to start, refilled at
--              WalkSpeed * (1 + SpeedSlack), capped at LagSeconds of refill, spent by the shortest LEGAL walk between
--              two samples, through the doorways).
-- Two things have to hold, and this spec is both: an honest player is NEVER voided (sections 3-4, with the margins in
-- numbers), and the cheats are (section 5).
local PosGuard = require("../src/shared/PosGuard")
local Crossing = require("../src/shared/Crossing")
local Manor = require("../src/shared/Manor")
local Rng = require("../src/shared/Rng")
local Salt = require("../src/shared/Salt")
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
local V = Config.Player.WalkSpeed
local SIZE = Config.Manor.RoomSize
local HALF_DOOR = Config.Manor.DoorWidth / 2
local TICK = Config.TickSeconds

local function publicPlan(night: number)
	return Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
end
local function dist(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end
local function step(plan, st, x, z, dt, final)
	return PosGuard.step(Config, plan, Manor, Crossing, st, x, z, dt, final)
end
local function centreOf(plan, id): (number, number)
	return Manor.roomCenter(Config, Manor.roomById(plan, id) :: any)
end
-- where a player stands to use the exit: 4 studs from the door toward the exit room's middle
local function exitStand(plan): (number, number)
	local dx, dz = Crossing.exitDoor(Config, plan, Manor)
	local cx, cz = centreOf(plan, plan.exitId)
	local d = dist(dx, dz, cx, cz)
	return dx + (cx - dx) / d * 4, dz + (cz - dz) / d * 4
end

-- a tiny generator of its own, so the spec is the same every run
local function lcg(seed: number)
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

--======================================================================= 1. the numbers

truthy(G.PositionChecks ~= false, "the position guard ships ON (only an explicit false switches it off)")
truthy(G.SpeedSlack > 0 and G.SpeedSlack <= 0.15, "the bank refills a little faster than a walk, at most 15% (" .. tostring(G.SpeedSlack) .. ")")
truthy(G.JumpSlack >= 4 and G.JumpSlack <= 12, "a few studs in hand from the start (" .. tostring(G.JumpSlack) .. ")")
truthy(G.LagSeconds >= 2 and G.LagSeconds <= 6, "the bank holds a multi-second gap, and no more than 6 s (" .. tostring(G.LagSeconds) .. ")")
truthy(G.OutsideGraceSeconds >= 2 * TICK and G.OutsideGraceSeconds <= 1, "outside is forgiven for a few ticks, under a second (" .. tostring(G.OutsideGraceSeconds) .. ")")
approx(PosGuard.rate(Config), V * (1 + G.SpeedSlack), 1e-9, "rate = WalkSpeed * (1 + SpeedSlack)")
approx(PosGuard.cap(Config), G.JumpSlack + PosGuard.rate(Config) * G.LagSeconds, 1e-9, "cap = JumpSlack + rate * LagSeconds")
local RATE, CAP = PosGuard.rate(Config), PosGuard.cap(Config)
print(string.format("  the bank: %.0f studs to start, refilled at %.1f studs/s, capped at %.0f studs (a %.2f s silence at WalkSpeed)",
	G.JumpSlack, RATE, CAP, CAP / V))
do
	-- the settle window against the shortest crossing
	local least = math.huge
	for night = 1, 150 do
		least = math.min(least, Crossing.minSeconds(Config, publicPlan(night), Manor))
	end
	local src = Salt.new(20261011, 5150)
	for i = 1, 600 do
		local night = 1 + (i % 60)
		least = math.min(least, Crossing.minSeconds(Config, Manor.plan(Salt.new(Salt.step(src), Salt.step(src)), Config, night), Manor))
	end
	truthy(G.SettleSeconds >= 1 and G.SettleSeconds <= 3, "the settle window after a server placement is 1-3 s (" .. tostring(G.SettleSeconds) .. ")")
	-- ...which can be LONGER than a crossing: so the exit's press must be judged inside the window too (5g)
	truthy(least > 1.5 and least < 3, string.format("set-up: the shortest crossing seen is %.2f s", least))
end

--======================================================================= 2. what a move costs: the shortest LEGAL walk

do
	local plan = publicPlan(9)
	local cx, cz = centreOf(plan, plan.entranceId)
	approx(PosGuard.cost(Config, plan, Manor, Crossing, cx - 5, cz, cx + 7, cz + 5), 13, 1e-9, "inside one room a move costs the straight line (5-12-13)")
	approx(PosGuard.cost(Config, plan, Manor, Crossing, cx, cz, cx, cz), 0, 1e-9, "standing still costs nothing")
	-- to a point outside every room: the straight line (the OUTSIDE rule judges that sample, not the cost)
	approx(PosGuard.cost(Config, plan, Manor, Crossing, cx, cz, cx + 5000, cz), 5000, 1e-9, "to a point in no room: the straight line")
end

-- Across a wall the cost is the walk round by the doorway. For every pair of rooms on nights 1-60 that share a wall:
--   * with a doorway: stepping through the wall 15 studs from the gap's middle costs more than the 4 studs it is;
--   * without one: the hop costs at least the walk to the nearest doorway out of the room.
do
	local viaDoorMin, noDoorMin, linkedPairs, blindPairs = math.huge, math.huge, 0, 0
	for night = 1, 60 do
		local plan = publicPlan(night)
		for _, a in plan.rooms do
			for _, b in plan.rooms do
				if a.id < b.id and math.abs(a.gx - b.gx) + math.abs(a.gz - b.gz) == 1 then
					local mx, mz = (a.gx + b.gx) / 2 * SIZE, (a.gz + b.gz) / 2 * SIZE
					local ux, uz = b.gx - a.gx, b.gz - a.gz -- across the wall
					local vx, vz = -uz, ux -- along it
					-- 15 studs along the wall from its middle (10 clear of the gap's edge), 2 studs either side
					local px, pz = mx + vx * 15 - ux * 2, mz + vz * 15 - uz * 2
					local qx, qz = mx + vx * 15 + ux * 2, mz + vz * 15 + uz * 2
					local c = PosGuard.cost(Config, plan, Manor, Crossing, px, pz, qx, qz)
					if Manor.linked(plan, a.id, b.id) then
						linkedPairs += 1
						viaDoorMin = math.min(viaDoorMin, c)
					else
						blindPairs += 1
						noDoorMin = math.min(noDoorMin, c)
					end
				end
			end
		end
	end
	truthy(linkedPairs > 100 and blindPairs > 20, string.format("set-up: %d walls with a doorway and %d without, nights 1-60", linkedPairs, blindPairs))
	-- by the gap's near edge: 2 * sqrt(10^2 + 2^2) = 20.4, less the grid's slack (one step of DoorWidth / 10)
	truthy(viaDoorMin >= 19, string.format("a 4-stud step through a wall 15 studs from its doorway costs the walk round by the gap: at least %.1f studs", viaDoorMin))
	truthy(noDoorMin >= 30, string.format("a 4-stud hop through a wall with NO doorway costs the way round: at least %.1f studs", noDoorMin))
end

-- ...and it is never MORE than a walk a player can really make (or an honest player would be overcharged): random
-- points in random rooms, joined by a walk through the doorway middles of Manor.pathBetween.
do
	local rnd = lcg(77)
	local worst, n, tight = -math.huge, 0, 0
	for night = 1, 80 do
		local plan = publicPlan(night)
		for _ = 1, 12 do
			local ra = plan.rooms[1 + math.floor(rnd() * #plan.rooms)]
			local rb = plan.rooms[1 + math.floor(rnd() * #plan.rooms)]
			local ax, az = ra.gx * SIZE + (rnd() - 0.5) * 37, ra.gz * SIZE + (rnd() - 0.5) * 37
			local bx, bz = rb.gx * SIZE + (rnd() - 0.5) * 37, rb.gz * SIZE + (rnd() - 0.5) * 37
			local path = Manor.pathBetween(plan, ra.id, rb.id) :: { number }
			local real, px, pz = 0, ax, az
			for i = 1, #path - 1 do
				local mx, mz = Manor.doorwayBetween(Config, plan, path[i], path[i + 1])
				real += dist(px, pz, mx :: number, mz :: number)
				px, pz = mx :: number, mz :: number
			end
			real += dist(px, pz, bx, bz)
			local c = PosGuard.cost(Config, plan, Manor, Crossing, ax, az, bx, bz)
			worst = math.max(worst, c - real)
			if real - c < 5 then tight += 1 end
			n += 1
		end
	end
	truthy(worst <= 1e-6, string.format("the cost is a LOWER bound on a real walk between the two points, %d pairs (worst overcharge %.6f studs)", n, worst))
	truthy(tight > n / 4, string.format("...and a tight one: within 5 studs of the doorway-middle walk on %d of %d pairs", tight, n))
end

--======================================================================= 3. the model: a walker the server samples

-- A walk is a polyline; the walker moves along it at `speed`. The server samples it every tick: what it reads is
-- where the walker WAS `lat(t)` seconds ago (latency), or nothing new at all during a silence (a lag gap: the client
-- keeps walking, the server keeps seeing the last position, then one sample jumps).
local function polyline(pts: { { number } }, speed: number)
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
	end
	local total = cum[#pts]
	return function(t: number): (number, number)
		local d = math.clamp(t * speed, 0, total)
		for i = 2, #pts do
			if d <= cum[i] then
				local span = cum[i] - cum[i - 1]
				local f = if span > 0 then (d - cum[i - 1]) / span else 0
				return pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f, pts[i - 1][2] + (pts[i][2] - pts[i - 1][2]) * f
			end
		end
		return pts[#pts][1], pts[#pts][2]
	end, total
end

-- The waypoints of a legal walk from (ax, az) in room `fromId` to (bx, bz) in room `toId`: one point on each doorway
-- of the room path, `offset(i)` studs along the gap from its middle.
local function route(plan, fromId, ax, az, toId, bx, bz, offset: ((number) -> number)?): { { number } }
	local pts = { { ax, az } }
	local path = Manor.pathBetween(plan, fromId, toId) :: { number }
	for i = 1, #path - 1 do
		local ra, rb = Manor.roomById(plan, path[i]) :: any, Manor.roomById(plan, path[i + 1]) :: any
		local mx, mz = Manor.doorwayBetween(Config, plan, path[i], path[i + 1])
		local o = if offset then offset(i) else 0
		if ra.gx ~= rb.gx then
			table.insert(pts, { mx :: number, (mz :: number) + o })
		else
			table.insert(pts, { (mx :: number) + o, mz :: number })
		end
	end
	table.insert(pts, { bx, bz })
	return pts
end

-- Feed a guard state the server's samples of `posAt` for `seconds`. opts: tick(i) -> dt, lat(t) -> seconds,
-- silence = { from, to } (seconds of the walk during which the server sees nothing new), t0 (the walker's clock at
-- the first sample). Returns ok, why, the time of the refusal, the least the bank held after a judged sample.
local function feed(plan, st, posAt, seconds: number, opts: any?): (boolean, string?, number, number)
	local o = opts or {}
	local t, i, least = o.t0 or 0, 0, math.huge
	local stop = t + seconds
	local lastLat = 0
	while t < stop - 1e-9 do
		i += 1
		local dt = if o.tick then o.tick(i) else TICK
		t += dt
		local seen = t
		if o.lat then
			-- latency never lets the server see the walker go backwards in its own time
			local l = o.lat(t)
			seen = math.max(t - l, (t - dt) - lastLat)
			lastLat = t - seen
		end
		if o.silence and seen > o.silence[1] and seen < o.silence[2] then
			seen = o.silence[1]
		end
		local x, z = posAt(seen)
		local ok, why = step(plan, st, x, z, dt)
		if not ok then return false, why, t, least end
		if st.settle <= 1e-9 then least = math.min(least, st.bank) end -- judged samples only
	end
	return true, nil, t, least
end

--======================================================================= 4. an honest player is never voided

-- 4a. THE PERFECT LINE, the walk Crossing.spec's guard is built on: from where the night puts you straight to the
-- exit, through the doorways, at WalkSpeed from the first tick, on the public manors of nights 1-150. Sampled every
-- TickSeconds. Never voided; and the bank never dips under what it started with.
do
	local voided, example, least = 0, nil, math.huge
	for night = 1, 150 do
		local plan = publicPlan(night)
		local sx, sz = Crossing.start(Config, plan)
		local ex, ez = exitStand(plan)
		local posAt, total = polyline(route(plan, plan.entranceId, sx, sz, plan.exitId, ex, ez), V)
		local st = PosGuard.seed(Config, sx, sz)
		local ok, why, _, low = feed(plan, st, posAt, total / V + 1)
		if not ok then voided += 1; example = example or string.format("night %d: %s", night, tostring(why)) end
		least = math.min(least, low)
		-- and the press at the end is judged too
		local okPress = step(plan, st, ex, ez, 0, true)
		if not okPress then voided += 1; example = example or string.format("night %d: the press", night) end
	end
	eq(voided, 0, "the perfect line at WalkSpeed is never voided, public nights 1-150 (" .. tostring(example) .. ")")
	truthy(least >= G.JumpSlack - 1e-6, string.format("...and the bank never dips under its starting %.0f studs (least %.2f)", G.JumpSlack, least))
	print(string.format("  the perfect line, nights 1-150: least bank %.2f studs", least))
end

-- 4b. THE GAME AS IT SHIPS: salted manors, a tour of every room and then out, crossing every doorway at a random
-- point of the gap (up to its very edge), ticks that jitter between 0.05 and 0.25 s, and latency that swings anywhere
-- between 0 and 0.3 s from one sample to the next.
do
	local rnd = lcg(20261011)
	local src = Salt.new(20261011, 31337)
	local voided, example, least, manors, walked = 0, nil, math.huge, 0, 0
	for i = 1, 240 do
		local night = 1 + (i % 60)
		local plan = Manor.plan(Salt.new(Salt.step(src), Salt.step(src)), Config, night)
		manors += 1
		local sx, sz = Crossing.start(Config, plan)
		local pts = { { sx, sz } }
		local at, ax, az = plan.entranceId, sx, sz
		local function go(toId, bx, bz)
			local leg = route(plan, at, ax, az, toId, bx, bz, function() return (rnd() * 2 - 1) * HALF_DOOR end)
			for k = 2, #leg do table.insert(pts, leg[k]) end
			at, ax, az = toId, bx, bz
		end
		for _ = 1, 6 do
			local r = plan.rooms[1 + math.floor(rnd() * #plan.rooms)]
			-- anywhere a root can stand, and past it: up to 19.4 studs from the centre (the wall's face is at 19.5)
			go(r.id, r.gx * SIZE + (rnd() * 2 - 1) * 19.4, r.gz * SIZE + (rnd() * 2 - 1) * 19.4)
		end
		local ex, ez = exitStand(plan)
		go(plan.exitId, ex, ez)
		local posAt, total = polyline(pts, V)
		walked += total
		local st = PosGuard.seed(Config, sx, sz)
		local ok, why, _, low = feed(plan, st, posAt, total / V + 1, {
			tick = function() return 0.05 + rnd() * 0.2 end,
			lat = function() return rnd() * 0.3 end,
		})
		if not ok then voided += 1; example = example or string.format("manor %d (night %d): %s", i, night, tostring(why)) end
		least = math.min(least, low)
		if ok and not step(plan, st, ex, ez, 0, true) then voided += 1; example = example or "the press" end
	end
	eq(voided, 0, string.format("a tour of %d salted manors (%.0f studs on foot) with jittered ticks and 0-0.3 s latency swings: never voided (%s)",
		manors, walked, tostring(example)))
	truthy(least > 0, string.format("...with studs to spare at the worst sample (least bank %.2f)", least))
	print(string.format("  salted tours: least bank %.2f studs of the starting %.0f (a 0.3 s latency swing is %.0f studs)", least, G.JumpSlack, 0.3 * V))
end

-- 4b'. The worst moment for a latency swing: the very first judged sample, with nothing in the bank but its start
-- (no settle window's refill), at full WalkSpeed. The sample then shows a tick's walk PLUS the swing.
do
	local plan = publicPlan(9)
	local cx, cz = centreOf(plan, plan.entranceId)
	local function swing(seconds: number): boolean
		local st = PosGuard.seed(Config, cx - 15, cz)
		st.settle = 0
		return (step(plan, st, cx - 15 + V * (TICK + seconds), cz, TICK))
	end
	local limit = (G.JumpSlack + (RATE - V) * TICK) / V
	truthy(swing(0.1) and swing(0.2) and swing(0.3) and swing(0.4), "a latency swing of up to 0.4 s on the first judged sample is inside the starting bank")
	truthy(not swing(0.6), string.format("...and 0.6 s is not (the stated limit there: %.2f s; it grows 0.1 s for every second walked)", limit))
	print(string.format("  latency: a swing of %.2f s is covered from the first judged sample, +%.2f s per second of walking after it", limit, (RATE - V) / V))
end

-- 4c. A LAG GAP: the client keeps walking the perfect line, the server sees nothing for `gap` seconds, then one
-- sample makes it all up. Tolerated up to the bank's cap; past it the night is voided (the stated limit).
do
	local limit = CAP / V
	local function gapRun(night: number, gap: number, standFirst: number): (boolean, string?)
		local plan = publicPlan(night)
		local sx, sz = Crossing.start(Config, plan)
		local ex, ez = exitStand(plan)
		local posAt = polyline(route(plan, plan.entranceId, sx, sz, plan.exitId, ex, ez), V)
		local st = PosGuard.seed(Config, sx, sz)
		-- standing where the night put you first (the bank fills to its cap and no further)
		if standFirst > 0 then
			feed(plan, st, function() return sx, sz end, standFirst)
		end
		local ok, why = feed(plan, st, posAt, gap + 4, { silence = { 0.6, 0.6 + gap } })
		return ok, why
	end
	local nights = { 20, 45, 64, 90, 120, 150 } -- long crossings: the walk outlasts the gap
	for _, gap in { 1, 2, 3, 3.5 } do
		local bad = 0
		for _, night in nights do
			if not gapRun(night, gap, 0) then bad += 1 end
			if not gapRun(night, gap, 30) then bad += 1 end
		end
		eq(bad, 0, string.format("a %.1f s lag gap in the middle of the walk is made up in one sample, walking or after standing 30 s", gap))
	end
	truthy(limit >= 3.5 and limit <= 6.5, string.format("the tolerated silence is CAP / WalkSpeed = %.2f s", limit))
	local caught = 0
	for _, night in nights do
		local ok, why = gapRun(night, limit + 1.5, 30)
		if not ok and why == "jump" then caught += 1 end
	end
	eq(caught, #nights, string.format("...and a %.1f s one is not (the stated limit: waiting 30 s first bought nothing)", limit + 1.5))
	print(string.format("  lag: a silence of up to %.2f s at full WalkSpeed is made up in one sample", limit))
end

-- 4d. A SERVER HITCH: one tick of 8 s (the server stalled, the client walked on). The tick's own time is always
-- usable, whatever the cap.
do
	local plan = publicPlan(120)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = exitStand(plan)
	local posAt, total = polyline(route(plan, plan.entranceId, sx, sz, plan.exitId, ex, ez), V)
	truthy(total > 8.5 * V, string.format("set-up: night 120's walk is %.0f studs, longer than 8 s of walking", total))
	local st = PosGuard.seed(Config, sx, sz)
	local ok = feed(plan, st, posAt, G.SettleSeconds + 0.3)
	local hx, hz = posAt(G.SettleSeconds + 0.3 + 8)
	ok = ok and step(plan, st, hx, hz, 8)
	truthy(ok, "one 8 s server tick with the player walking all through it is not a jump")
	truthy(st.bank <= CAP + 1e-9, "...and what is left over is capped like any other bank")
end

-- 4e. A RESPAWN IN THE NIGHT. The engine drops a new character on the safehouse's spawn pad (400 studs from the
-- manor) for a frame or more before the server's placement wins; the server re-seeds the guard at the foyer, and
-- nothing is judged while it settles.
do
	local plan = publicPlan(30)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = exitStand(plan)
	local st = PosGuard.seed(Config, sx, sz)
	local posAt = polyline(route(plan, plan.entranceId, sx, sz, plan.exitId, ex, ez), V)
	local ok = feed(plan, st, posAt, 4)
	truthy(ok, "set-up: four seconds of honest walking")
	PosGuard.reseed(Config, st, sx, sz)
	-- the world origin, then the safehouse pad, for 0.5 s; then the foyer, and the walk again
	ok = step(plan, st, -6000, 360, TICK)
	for _ = 1, 4 do ok = ok and step(plan, st, 0, 420, TICK) end
	truthy(ok, "a respawn's first samples (the world origin, the safehouse's spawn pad) are not judged while it settles")
	local ok2, why2 = feed(plan, st, posAt, 30)
	truthy(ok2, "...and the walk from the foyer after it is clean (" .. tostring(why2) .. ")")
	truthy(st.outside == 0, "...with no outside time on the record (settling samples are not counted)")
end

-- 4f. STANDING IN A DOORWAY, stepping across the shared plane every tick for a minute (roomAtWorld puts a point on
-- the plane in the higher cell, so every step is a change of room); and a knock (0.8 x WalkSpeed for 0.8 s).
do
	local plan = publicPlan(12)
	local sx, sz = Crossing.start(Config, plan)
	local bad, doors = 0, 0
	for _, l in plan.links do
		local mx, mz = Manor.doorwayBetween(Config, plan, l.a, l.b)
		local ra, rb = Manor.roomById(plan, l.a) :: any, Manor.roomById(plan, l.b) :: any
		local ux, uz = rb.gx - ra.gx, rb.gz - ra.gz
		local st = PosGuard.seed(Config, sx, sz)
		st.x, st.z, st.settle = (mx :: number) - ux, (mz :: number) - uz, 0
		doors += 1
		for i = 1, 600 do
			local s = if i % 2 == 0 then -1 else 1
			-- 2 studs a tick: exactly WalkSpeed, across the plane, at the gap's edge
			local along = HALF_DOOR - 0.01
			if not step(plan, st, (mx :: number) + ux * s + (-uz) * along, (mz :: number) + uz * s + ux * along, TICK) then
				bad += 1
				break
			end
			if not step(plan, st, (mx :: number) - ux * s + (-uz) * along, (mz :: number) - uz * s + ux * along, TICK) then
				bad += 1
				break
			end
		end
	end
	eq(bad, 0, string.format("dithering across the plane of each of night 12's %d doorways at WalkSpeed for two minutes: never voided", doors))
	local cx, cz = centreOf(plan, plan.entranceId)
	local st = PosGuard.seed(Config, cx, cz)
	st.settle = 0
	local knock = Config.Hazards.KnockSpeedFractionMax * V
	local ok = true
	for i = 1, 8 do
		ok = ok and step(plan, st, cx + knock * TICK * i, cz, TICK)
	end
	truthy(ok and st.bank >= G.JumpSlack, string.format("a knock (%.0f studs/s for 0.8 s) is slower than the bank refills", knock))
end

-- 4g. THE WALLS. A root cannot get closer to a room's edge than the wall's face (0.5) plus half its own depth (0.5):
-- 19 studs from the centre at the very most. Every such point, on every outer face of every room, is IN the room.
do
	local bad, n = 0, 0
	for night = 1, 60 do
		local plan = publicPlan(night)
		for _, r in plan.rooms do
			local cx, cz = r.gx * SIZE, r.gz * SIZE
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				for _, along in { -19, 0, 19 } do
					local x = cx + d[1] * 19 + math.abs(d[2]) * along
					local z = cz + d[2] * 19 + math.abs(d[1]) * along
					n += 1
					if Manor.roomAtWorld(plan, Config, x, z) ~= r.id then bad += 1 end
				end
			end
		end
	end
	eq(bad, 0, string.format("a root against any wall (19 studs from the centre) is inside its room: %d points, a stud clear of the edge", n))
end

--======================================================================= 5. the cheats are voided

-- 5a. THE EXPLOIT (review 2026-10-09): out of the manor a second into the night, wait in safety, come back to the
-- door. Voided for OUTSIDE within the grace, whether 400 studs out or 3 studs behind the foyer's wall.
do
	for _, how in { { "400 studs out", 400 }, { "3 studs behind the wall", SIZE / 2 + 3 } } do
		local voided, slowest, reasons, untested = 0, 0, {}, 0
		for night = 1, 150 do
			local plan = publicPlan(night)
			local sx, sz = Crossing.start(Config, plan)
			-- straight out through a face with nothing behind it: the foyer's if it has one, else the nearest room's
			local ox, oz = nil, nil
			local path = { plan.entranceId }
			for _, r in plan.rooms do table.insert(path, r.id) end
			for _, id in path do
				local cx, cz = centreOf(plan, id)
				for _, d in { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } } do
					local x, z = cx + d[1] * how[2], cz + d[2] * how[2]
					if ox == nil and Manor.roomAtWorld(plan, Config, x, z) == nil then ox, oz = x, z end
				end
			end
			if ox then
				local st = PosGuard.seed(Config, sx, sz)
				feed(plan, st, function() return sx, sz end, G.SettleSeconds + 0.2)
				local ok, why, t = feed(plan, st, function() return ox, oz end, 12)
				if not ok then
					voided += 1
					slowest = math.max(slowest, t)
					reasons[tostring(why)] = true
				end
			else
				untested += 1
			end
		end
		eq(untested, 0, "set-up: a spot outside was found on every one of nights 1-150")
		eq(voided, 150, "parked " .. how[1] .. ": voided on every one of nights 1-150")
		truthy(reasons.outside == true and reasons.jump == nil, "...for being OUTSIDE")
		truthy(slowest <= G.OutsideGraceSeconds + 2 * TICK + 1e-6,
			string.format("...within the grace and a tick (%.1f s at the slowest; the clock asks for 1.85 s at the least)", slowest))
	end
end

-- 5b. The grace is a grace: three stray samples outside and back is not a void; but the time ADDS UP over the night.
do
	local plan = publicPlan(9)
	local sx, sz = Crossing.start(Config, plan)
	local st = PosGuard.seed(Config, sx, sz)
	st.settle = 0
	local ok = true
	for _ = 1, 3 do ok = ok and step(plan, st, sx, sz + 4000, TICK) end
	ok = ok and step(plan, st, sx, sz, TICK)
	truthy(ok, "three samples outside (0.3 s) and back: forgiven")
	approx(st.outside, 0.3, 1e-9, "...and remembered")
	for _ = 1, 20 do ok = ok and step(plan, st, sx, sz, TICK) end
	local ok2, why2 = true, nil
	for _ = 1, 3 do
		if ok2 then ok2, why2 = step(plan, st, sx, sz + 4000, TICK) end
	end
	truthy(ok and not ok2 and why2 == "outside", "three more later in the night (0.6 s in total): voided, the grace does not refill")
	-- a position that is not a number is nowhere
	local st2 = PosGuard.seed(Config, sx, sz)
	st2.settle = 0
	local okN, whyN = true, nil
	for _ = 1, 8 do
		if okN then okN, whyN = step(plan, st2, 0 / 0, sz, TICK) end
	end
	truthy(not okN and whyN == "outside", "a NaN position counts as outside")
	local st3 = PosGuard.seed(Config, sx, sz)
	st3.settle = 0
	local okI, whyI = true, nil
	for _ = 1, 8 do
		if okI then okI, whyI = step(plan, st3, math.huge, sz, TICK) end
	end
	truthy(not okI and whyI == "outside", "...and so does an infinite one")
end

-- 5c. Staying INSIDE and teleporting to the door: wait in the foyer as long as you like, then jump. Voided for JUMP
-- on every manor whose legal walk to the exit is longer than the bank's cap, however long the wait.
do
	local longNights, voided, shortNights, example = 0, 0, 0, nil
	for night = 1, 150 do
		local plan = publicPlan(night)
		local sx, sz = Crossing.start(Config, plan)
		local ex, ez = exitStand(plan)
		local legal = PosGuard.cost(Config, plan, Manor, Crossing, sx, sz, ex, ez)
		if legal > CAP then
			longNights += 1
			local st = PosGuard.seed(Config, sx, sz)
			feed(plan, st, function() return sx, sz end, 60)
			approx(st.bank, CAP, 1e-6, "waiting a minute fills the bank to its cap and not a stud further (night " .. night .. ")")
			local ok, why = step(plan, st, ex, ez, TICK)
			if not ok and why == "jump" then voided += 1 else example = example or night end
		else
			shortNights += 1
		end
	end
	truthy(longNights >= 75, string.format("set-up: on %d of nights 1-150 the legal walk to the exit is longer than the cap (%.0f studs)", longNights, CAP))
	eq(voided, longNights, "wait a minute in the foyer, teleport to the door: voided for a JUMP on every one of them (" .. tostring(example) .. ")")
	print(string.format("  foyer-to-door in one hop: voided on %d of 150 public nights; on the other %d the walk is under %.0f studs (a %.1f s lag gap looks the same)",
		longNights, shortNights, CAP, CAP / V))
	-- the game as it ships: salted manors. The same rule; and how many manors are small enough for one hop.
	local src = Salt.new(20261011, 8080)
	local long, short, missed = 0, 0, 0
	for i = 1, 3000 do
		local night = 1 + (i % 60)
		local plan = Manor.plan(Salt.new(Salt.step(src), Salt.step(src)), Config, night)
		local sx, sz = Crossing.start(Config, plan)
		local ex, ez = exitStand(plan)
		if PosGuard.cost(Config, plan, Manor, Crossing, sx, sz, ex, ez) > CAP then
			long += 1
			local st = PosGuard.seed(Config, sx, sz)
			st.settle, st.bank = 0, CAP -- the fullest a bank can be
			local ok, why = step(plan, st, ex, ez, 0, true)
			if ok or why ~= "jump" then missed += 1 end
		else
			short += 1
		end
	end
	eq(missed, 0, string.format("...and on every one of %d salted manors (nights 1-60) whose walk is longer than the cap", long))
	truthy(long > short, string.format("...which is most of them: %d of 3000 (the other %d are within one %.0f-stud hop of the door)", long, short, CAP))
	print(string.format("  salted manors, nights 1-60: foyer-to-door is one hop inside the cap on %d of 3000 (%.1f%%)", short, short / 30))
end

-- 5d. The same, pressing E in the same instant (no tick in between): the press is judged with dt 0.
do
	local plan = publicPlan(120)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = exitStand(plan)
	local st = PosGuard.seed(Config, sx, sz)
	feed(plan, st, function() return sx, sz end, 30)
	local ok, why = step(plan, st, ex, ez, 0, true)
	truthy(not ok and why == "jump", "teleport and press in the same tick: the press itself is judged")
end

-- 5e. A speed hack on a legal route. 1.5 x WalkSpeed empties the bank in a second; 1.05 x is inside the slack.
do
	local plan = publicPlan(150)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = exitStand(plan)
	local pts = route(plan, plan.entranceId, sx, sz, plan.exitId, ex, ez)
	-- there and back, so the route is long enough for a slow leak to show
	for i = #pts - 1, 1, -1 do table.insert(pts, pts[i]) end
	for _, c in { { 1.5, 1.5 }, { 1.25, 3.5 } } do
		local posAt = polyline(pts, V * c[1])
		local st = PosGuard.seed(Config, sx, sz)
		st.settle = 0
		local ok, why, t = feed(plan, st, posAt, 20)
		truthy(not ok and why == "jump" and t <= c[2],
			string.format("%.2f x WalkSpeed along the legal route: voided after %.1f s (limit %.1f)", c[1], t, c[2]))
	end
	local posAt = polyline(pts, V * 1.05)
	local st = PosGuard.seed(Config, sx, sz)
	st.settle = 0
	truthy(feed(plan, st, posAt, 20), "CONTROL: 1.05 x WalkSpeed is inside the 10% slack (a measurement tolerance, not a boost)")
end

-- 5f. Walking through walls. Hopping 4 studs through a wall with no doorway, back and forth, is voided at once;
-- a noclip run in a straight line across the manor costs the legal walk, not the line.
do
	local plan, pa, pb = nil, nil, nil
	for night = 5, 60 do
		local p = publicPlan(night)
		for _, a in p.rooms do
			for _, b in p.rooms do
				if not plan and a.id < b.id and math.abs(a.gx - b.gx) + math.abs(a.gz - b.gz) == 1 and not Manor.linked(p, a.id, b.id) then
					plan, pa, pb = p, a, b
				end
			end
		end
		if plan then break end
	end
	truthy(plan ~= nil, "set-up: two rooms that share a wall with no doorway")
	if plan and pa and pb then
		local mx, mz = (pa.gx + pb.gx) / 2 * SIZE, (pa.gz + pb.gz) / 2 * SIZE
		local ux, uz = pb.gx - pa.gx, pb.gz - pa.gz
		local st = PosGuard.seed(Config, mx - ux * 2, mz - uz * 2)
		st.settle = 0
		local ok, why = step(plan, st, mx + ux * 2, mz + uz * 2, TICK)
		truthy(not ok and why == "jump", "a 4-stud hop through a wall with no doorway: voided for a JUMP")
	end
end

-- 5g. The settle window is not a hiding place. After it, the walk is measured from where the SERVER put the
-- character: one that never arrived is outside, one that used the window to cross the manor jumped; and the exit's
-- press is judged even inside the window.
do
	local plan = publicPlan(120)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = exitStand(plan)
	local st = PosGuard.seed(Config, sx, sz)
	local ok, why, t = feed(plan, st, function() return sx, sz + 4000 end, 5)
	truthy(not ok and why == "outside" and t <= G.SettleSeconds + G.OutsideGraceSeconds + 2 * TICK + 1e-6,
		string.format("never arrived in the foyer: outside, %.1f s after the placement", t))
	local st2 = PosGuard.seed(Config, sx, sz)
	local ok2, why2, t2 = feed(plan, st2, function() return ex, ez end, 5)
	truthy(not ok2 and why2 == "jump" and t2 <= G.SettleSeconds + 2 * TICK + 1e-6,
		string.format("used the window to cross the manor: a jump, judged the tick it closes (%.1f s)", t2))
	local st3 = PosGuard.seed(Config, sx, sz)
	feed(plan, st3, function() return sx, sz end, 30)
	PosGuard.reseed(Config, st3, sx, sz) -- a respawn late in the night: the clock has long passed
	local ok3, why3 = step(plan, st3, ex, ez, 0, true)
	truthy(not ok3 and why3 == "jump", "respawn, teleport to the door and press inside the settle window: the press is judged")
	local st4 = PosGuard.seed(Config, sx, sz)
	truthy(step(plan, st4, ex, ez, 0), "CONTROL: an ordinary sample inside the window is not judged")
	-- a respawn does not wipe the outside time already on the record
	local st5 = PosGuard.seed(Config, sx, sz)
	st5.settle = 0
	for _ = 1, 4 do step(plan, st5, sx, sz + 4000, TICK) end
	PosGuard.reseed(Config, st5, sx, sz)
	approx(st5.outside, 0.4, 1e-9, "a re-seed keeps the outside time already on the record")
end

-- 5h. Outside is not a free ride. A sample in no room is never a place to measure a walk FROM: step out (inside the
-- grace), travel along the outside of the manor, step back in next to the exit, and the way back in is charged
-- from the last place the character stood INSIDE.
do
	local plan = publicPlan(120)
	local sx, sz = Crossing.start(Config, plan)
	local ex, ez = exitStand(plan)
	local st = PosGuard.seed(Config, sx, sz)
	feed(plan, st, function() return sx, sz end, 30)
	local ok = step(plan, st, sx, sz + 4000, TICK) and step(plan, st, ex, ez + 4000, TICK)
	truthy(ok, "set-up: two samples outside, inside the grace")
	local ok2, why2 = step(plan, st, ex, ez, TICK)
	truthy(not ok2 and why2 == "jump", "out, along the outside, back in at the exit: charged from where it last stood inside (a JUMP)")
end

-- 5i. The first seconds of a night (independent review, 2026-10-11): the settle window and the outside grace are both
-- unjudged, so a script can sit OUTSIDE from the first tick until the grace runs out, then teleport to the door and
-- press. The bank does not refill outside, so all it holds is what the window earned, and that is under the shortest
-- walk to any door: voided on every manor.
do
	local src = Salt.new(20261011, 9090)
	local got, shortest = 0, math.huge
	for i = 1, 3000 do
		local night = 1 + (i % 60)
		local plan = Manor.plan(Salt.new(Salt.step(src), Salt.step(src)), Config, night)
		local sx, sz = Crossing.start(Config, plan)
		local ex, ez = exitStand(plan)
		shortest = math.min(shortest, PosGuard.cost(Config, plan, Manor, Crossing, sx, sz, ex, ez))
		local st = PosGuard.seed(Config, sx, sz)
		local ok, guard = true, 0
		while ok and guard < 500 do -- outside until the tick before it would void (bounded: a spec must end)
			guard += 1
			local probe = table.clone(st)
			if not step(plan, probe, sx, sz + 4000, TICK) then break end
			ok = step(plan, st, sx, sz + 4000, TICK)
		end
		if guard >= 500 or step(plan, st, ex, ez, 0, true) then got += 1 end
	end
	eq(got, 0, "outside from the first tick until the grace runs out, then the door and E: voided on all 3000 salted manors")
	local held = G.JumpSlack + RATE * G.SettleSeconds
	truthy(held < shortest, string.format("...because the bank then holds %.0f studs and the shortest walk to a door is %.0f", held, shortest))
	-- outside buys no ground, and a stray sample in a long server hitch is one sample
	local plan = publicPlan(9)
	local sx, sz = Crossing.start(Config, plan)
	local st = PosGuard.seed(Config, sx, sz)
	st.settle = 0
	local before = st.bank
	truthy(step(plan, st, sx, sz + 4000, 3), "one sample outside in a 3 s server hitch is one sample, not a void")
	eq(st.bank, before, "...and the bank does not refill outside")
	approx(st.outside, TICK, 1e-9, "...it counts as one tick of outside time")
end

print(string.format("PosGuard: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("PosGuard spec failed", 0)
end
