-- Tornado: one funnel, a red path that shows exactly the next 4 s and nothing further (DESIGN.md §2.5).
-- Run: luau tests/Tornado.spec.luau
local Tornado = require("../src/shared/Tornado")
local Zones = require("../src/shared/Zones")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local TC = Config.Tornado
local seed = 31337
local function rand(): number
	seed = (1664525 * seed + 1013904223) % 4294967296
	return seed / 4294967296
end
local half = Config.Island.Grid * Config.Island.CellStuds / 2
local inner = half - TC.EdgeInset

--======================================================================= 500 rounds, every rule

local touchdownOk = true
local startFar, startEdge, speedOk, turnOk, insideOk, horizonOk, noFuture = true, true, true, true, true, true, true
local minStart, maxTurn, worstHorizon = math.huge, 0, 0
local earliest = math.huge
local chased, total = 0, 0
for round = 1, 500 do
	local players = {}
	for k = 1, (if round % 2 == 0 then 8 else 1) do
		table.insert(players, { x = (rand() * 2 - 1) * 40, z = (rand() * 2 - 1) * 40 })
	end
	local s = Tornado.start(Config, players, rand)
	local p0 = s.points[1]
	if p0.t ~= TC.TouchdownAt then touchdownOk = false end
	for _, p in players do
		local d = math.sqrt((p.x - p0.x) ^ 2 + (p.z - p0.z) ^ 2)
		minStart = math.min(minStart, d)
		if d < TC.MinStartStuds - 1e-6 then startFar = false end
	end
	if math.max(math.abs(p0.x), math.abs(p0.z)) < inner - 1 then startEdge = false end
	-- the earliest moment a player standing where they were at the name could be inside the funnel's zone
	for _, p in players do
		local d = math.sqrt((p.x - p0.x) ^ 2 + (p.z - p0.z) ^ 2)
		earliest = math.min(earliest, TC.TouchdownAt + math.max(0, (d - Zones.funnelRadius(Config))) / TC.Speed)
	end
	-- at the name the first 4 s of path are drawn; afterwards the server extends to now + 4 every tick
	Tornado.extend(Config, s, TC.TouchdownAt + TC.HorizonSeconds, players, rand)
	local t = 0
	while t <= Config.Round.DisasterSeconds do
		local upto = math.max(t, TC.TouchdownAt) + TC.HorizonSeconds
		Tornado.extend(Config, s, upto, players, rand)
		local last = s.points[#s.points].t
		worstHorizon = math.max(worstHorizon, last - upto)
		if last < upto - 1e-9 or last > upto + TC.StepSeconds + 1e-9 then horizonOk = false end
		for _, q in Tornado.window(s, t - 0.25, t + 100) do
			if q.t > upto + TC.StepSeconds + 1e-9 then noFuture = false end
		end
		-- players wander
		for _, p in players do
			p.x = math.clamp(p.x + (rand() * 2 - 1) * 1.6, -48, 48)
			p.z = math.clamp(p.z + (rand() * 2 - 1) * 1.6, -48, 48)
		end
		t += 0.1
	end
	for k = 2, #s.points do
		local a, b = s.points[k - 1], s.points[k]
		local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		if math.abs(d - TC.Speed * TC.StepSeconds) > 1e-6 then speedOk = false end
		if math.max(math.abs(b.x), math.abs(b.z)) > inner + 1e-6 then insideOk = false end
		if k >= 3 and not b.reflected then
			local pa = s.points[k - 2]
			local h1 = math.atan2(a.z - pa.z, a.x - pa.x)
			local h2 = math.atan2(b.z - a.z, b.x - a.x)
			local dh = math.abs((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)
			maxTurn = math.max(maxTurn, math.deg(dh))
			if math.deg(dh) > TC.TurnDegPerSecond * TC.StepSeconds + 1e-6 then turnOk = false end
		end
	end
	chased += s.chases
	total += s.retargets
end
truthy(touchdownOk, "500 rounds: the funnel always touches down 3 s after the name")
truthy(startFar, string.format("500 rounds: the funnel always touches down >= 20 studs from every player (closest %.1f)", minStart))
truthy(startEdge, "and always at the island's edge")
truthy(speedOk, "every 0.25 s step is 9 x 0.25 = 2.25 studs: the funnel moves at 9 studs/s, walking speed is 16")
truthy(turnOk, string.format("it never turns more than 30 deg/s, except when it reflects off the edge (max %.2f deg per step)", maxTurn))
truthy(insideOk, "it never leaves the island")
truthy(horizonOk, string.format("the path always reaches exactly now + 4 s (overshoot at most %.2f s)", worstHorizon))
truthy(noFuture, "and no point beyond that horizon exists anywhere: the path past 4 s is not decided yet")
truthy(earliest >= 4.5 - 1e-6, string.format("the earliest possible hit on a starting player is 4.5 s (measured %.2f s)", earliest))
local share = chased / math.max(1, total)
truthy(share > 0.4 and share < 0.6, string.format("half the targets are a player (%.2f of %d)", share, total))

--======================================================================= positionAt and the published path

do
	local s = Tornado.start(Config, { { x = 0, z = 0 } }, rand)
	Tornado.extend(Config, s, 7, { { x = 0, z = 0 } }, rand)
	eq((Tornado.positionAt(s, 2.9)), nil, "before touchdown there is no funnel")
	local x, z = Tornado.positionAt(s, 3)
	eq(x, s.points[1].x, "at touchdown it is at the first point (x)")
	eq(z, s.points[1].z, "(z)")
	local xm, zm = Tornado.positionAt(s, 3.125)
	local a, b = s.points[1], s.points[2]
	truthy(math.abs(xm - (a.x + b.x) / 2) < 1e-9 and math.abs(zm - (a.z + b.z) / 2) < 1e-9, "between points it is interpolated")
	local enc = Tornado.encode(s, 3, 7)
	local t0, pts = Tornado.decode(enc)
	eq(t0, 3, "the published path starts at its first point's time")
	eq(#pts, 17, "4 s of path at 0.25 s is 17 points")
	truthy(math.abs(pts[17].x - s.points[17].x) < 0.01, "and decodes back to the same points (to 0.01 stud)")
	eq(Tornado.decode("garbage"), nil, "a malformed path decodes to nothing")
	local t1 = Tornado.decode(Tornado.encode(s, 3, 7, 1000))
	eq(t1, 1003, "with the name's server time as offset, t0 is a server time")
	-- the red path a client draws covers exactly what the funnel will touch in the next 4 s
	local onPath = Tornado.onPath(s, 3, 7, Zones.funnelRadius(Config), s.points[9].x, s.points[9].z)
	truthy(onPath, "the funnel's point 2 s ahead is on the drawn path")
end

--======================================================================= a broken position never breaks the funnel

do
	local nan = 0 / 0
	local ok, s = pcall(Tornado.start, Config, { { x = nan, z = nan }, { x = 0, z = 0 } }, rand)
	truthy(ok and s ~= nil and s.points[1].x == s.points[1].x, "a NaN player position is ignored: the funnel still touches down")
	local ok2, s2 = pcall(Tornado.start, Config, { { x = nan, z = nan } }, rand)
	truthy(ok2 and s2 ~= nil, "even when it is the only player")
end

print(string.format("Tornado: %d passed, %d failed", passed, failed))
assert(failed == 0, "Tornado tests failed")
