-- Disaster Rounds - THE RED IS THE HIT ZONE, through the real server and World.client.
-- Run: luau check_disasterrounds_zones.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- docs/complete-game-standard.md §2: "a red ring marks exactly where a hit can land, so stepping out of it always
-- dodges". DESIGN.md §4.1 promised this check: in every disaster, what is DRAWN red is what the server's hit test
-- uses; a root just inside the red is hit and a root just outside is not. The unit specs prove the rules on the pure
-- modules (Zones, Flood, Tornado, Quake); this file asks the built world, the way a player meets it:
--   1. rings (Meteor Shower): every ring Part is a red disc 2 x Radius across, Radius = HitRadius + PlayerRadius,
--      centred on its target's root, a volume from 0.05 over the lowest top its reach touches to 0.25 over the highest
--      (REVIEW-1 F7; check_disasterrounds_terrace.luau shows that red at the ground); a root 0.05 studs outside a ring
--      through its impact is not hit, 0.05 studs inside is ("Hit by a meteor");
--   2. flood: the cells World.client tints red at each warning are exactly the cells under water when that rise ends,
--      the red line sits at that water height; a root 0.05 studs on the red side of a beach edge is swept by the
--      flood, 0.05 studs on the dry side is not, and is swept by the next rise, when its own cell turns red;
--   3. tornado: every red path piece is 2 x (HitRadius + PlayerRadius) across: a disc on the funnel and on each
--      published point ahead of it, a box joining each two (REVIEW-1 F8);
--      a root riding 0.25 studs outside the funnel's reach is never caught, 0.25 studs inside is caught;
--   4. earthquake: the cells tinted red are exactly the cells with a crack; a root 0.05 studs over the edge onto the
--      intact neighbour when a cell drops is not hit, 0.05 studs inside a dropping cell's edge is.
-- Parts 2-4 switch the aimed rings off (Config.Strikes.FirstAfterSeconds), so every verdict there is the disaster's
-- own. Every scripted player walks at 15 studs/s at most, so the movement guard (28 studs in any 1 s) never trips.
-- The tornado's margin is 0.25 studs, not 0.05: the funnel moves 9 studs/s and the server samples at 10 Hz, so a
-- rider re-placed every 0.02 s is off by at most 0.18 studs from where the server's sample sees the funnel.

local SEED = 777001
local Datatypes = require("./emu/datatypes")
do
	local realNew = Datatypes.Random.new
	local n = SEED
	Datatypes.Random.new = function(seed)
		if seed == nil then
			n += 1
			return realNew(n * 7919)
		end
		return realNew(seed)
	end
end
local CFrame = Datatypes.CFrame
local Harness = require("./emu/harness")
local Bot = require("./check_disasterrounds_bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg) truthy(math.abs(a - b) <= tol, string.format("%s (%.4f vs %.4f)", msg, a, b)) end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local MapGen = h:_require(RS:FindFirstChild("MapGen"))
local Tornado = h:_require(RS:FindFirstChild("Tornado"))
local IC = Config.Island
local rf = h.workspace:FindFirstChild("Round")
local card = RS:FindFirstChild("DRRemotes"):FindFirstChild("Card")
local RunService = h.game:GetService("RunService")
local RING_R = Config.Strikes.HitRadius + Config.Hits.PlayerRadius
local FUNNEL_R = Config.Tornado.HitRadius + Config.Hits.PlayerRadius
local HALF = MapGen.halfSize(IC)

h.game:GetService("RunService"):setIsServer(false)
local A = h:join("Zed", 4201)
h.Players:simulateSpawn(A, h.workspace)
local B = h:join("Yan", 4202) -- keeps a flood round alive (the round ends the moment nobody is on the island)
h.Players:simulateSpawn(B, h.workspace)
local C = h:join("Xia", 4203)
h.Players:simulateSpawn(C, h.workspace)
h.Players.LocalPlayer = A
local okW, errW = h:tryRun("client/World.client")
truthy(okW, "World.client loads (" .. tostring(errW) .. ")")
local SetRest = RS:FindFirstChild("DRRemotes"):FindFirstChild("SetRest")
local function rest(p, on: boolean)
	SetRest:simulateFireServer(p, on)
	eq(p:GetAttribute("Resting"), on, p.Name .. (if on then " takes a break" else " is back"))
end

local now = function(): number return h.scheduler:now() end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function cellPart(i: number, j: number)
	local island = rf:FindFirstChild("Island")
	return island and island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
end
local function standY(x: number, z: number): number
	local i, j = MapGen.cellAt(IC, x, z)
	local c = i and cellPart(i, j)
	return MapGen.topY(IC, if c then c:GetAttribute("Level") else 0) + 3
end
local function place(p, x: number, z: number)
	root(p).CFrame = CFrame.new(x, standY(x, z), z)
end
-- goals: [player] = { x, z } walked toward at 15 studs/s each step
local goals = {}
local function step(dt: number)
	for p, g in goals do
		local r = root(p)
		if r and (p:GetAttribute("InRound") or "") ~= "" then
			local pos = r.Position
			local dx, dz = g.x - pos.X, g.z - pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			local s = 15 * dt
			if d <= s then place(p, g.x, g.z) else place(p, pos.X + dx / d * s, pos.Z + dz / d * s) end
		end
	end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
-- World.client draws on RenderStepped, BEFORE the server's tick in the same step: one more frame with no time passing
-- makes what is drawn match the server state this check is about to compare it with
local function frame()
	RunService.RenderStepped:Fire(0)
end
local function untilPhase(phase: string, limit: number): boolean
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / 0.1 do
		step(0.1)
		n += 1
	end
	return rf:GetAttribute("Phase") == phase
end
local function sweptTexts(p): { string }
	local out = {}
	for _, rec in card:sentTo(p) do
		if rec.args[1] == "swept" then table.insert(out, tostring(rec.args[2] and rec.args[2].text)) end
	end
	return out
end
-- is this cell tinted red by World.client (its colour lerped 0.65 toward the danger red)?
local function tinted(c): boolean
	local col = c.Color
	return col.R - math.max(col.G, col.B) > 0.3
end
local function rel(): number return now() - (rf:GetAttribute("NameAt") or now()) end
local function allCells()
	local island = rf:FindFirstChild("Island")
	return if island then island.Cells:GetChildren() else {}
end

--======================================================================= 0. every ring of a crowded round

-- the shape of EVERY ring: three dodging players at Heat 5 for one Meteor Shower (rings every 2.5 s each)
-- the lowest and highest tops of the (intact) cells a disc reaches, by brute geometry
local function topsUnder(cx: number, cz: number, rad: number): (number?, number?)
	local lo, hi = nil, nil
	for i = 1, IC.Grid do
		for j = 1, IC.Grid do
			local mx, mz = MapGen.cellCenter(IC, i, j)
			local dx = math.max(math.abs(cx - mx) - IC.CellStuds / 2, 0)
			local dz = math.max(math.abs(cz - mz) - IC.CellStuds / 2, 0)
			local c = cellPart(i, j)
			if dx * dx + dz * dz <= rad * rad and c and c:GetAttribute("Dropped") ~= true then
				local top = MapGen.topY(IC, c:GetAttribute("Level"))
				lo = if lo then math.min(lo, top) else top
				hi = if hi then math.max(hi, top) else top
			end
		end
	end
	return lo, hi
end
-- REVIEW-1 F7: a ring is a red volume from 0.05 over the lowest top its reach touches to 0.25 over the highest (over
-- flat ground, the old flat disc 0.2 thick), so its red shows on every terrace it reaches
local function ringOk(r): boolean
	local radius = r:GetAttribute("Radius")
	local sz = r.Size
	local right = r.CFrame.RightVector -- a Cylinder's axis is its local X: vertical means a flat disc
	local lo, hi = topsUnder(r.Position.X, r.Position.Z, RING_R)
	local bottom, top = r.Position.Y - sz.X / 2, r.Position.Y + sz.X / 2
	local ok = r.Shape == Enum.PartType.Cylinder and type(radius) == "number" and math.abs(radius - RING_R) < 1e-9
		and math.abs(sz.Y - 2 * radius) < 1e-6 and math.abs(sz.Z - 2 * radius) < 1e-6 and math.abs(math.abs(right.Y) - 1) < 1e-6
		and lo ~= nil and math.abs(bottom - (lo + 0.05)) < 1e-6 and math.abs(top - (hi + 0.25)) < 1e-6
		and math.abs(r.Color.R * 255 - 255) < 1 and math.abs(r.Color.G * 255 - 40) < 1 and math.abs(r.Color.B * 255 - 40) < 1
	if not ok then
		print(string.format("  ring: shape %s radius %s size (%.2f, %.2f, %.2f) axis.Y %.3f spans y %.2f..%.2f over tops %s..%s",
			tostring(r.Shape), tostring(radius), sz.X, sz.Y, sz.Z, right.Y, bottom, top, tostring(lo), tostring(hi)))
	end
	return ok
end
print("0. every ring")
Config.Shots.ForceKind = "meteor"
Config.Shots.ForceHeat = 5
local crowd = { Bot.new(h, A, { react = 0.6 }), Bot.new(h, B, { react = 0.6 }), Bot.new(h, C, { react = 0.6 }) }
truthy(untilPhase("disaster", 40), "a Meteor Shower at Heat 5")
local crowdRings, crowdBad, crowdOff = 0, 0, 0
local crowdSeen = {}
while rf:GetAttribute("Phase") == "disaster" do
	for _, b in crowd do Bot.step(b, 0.1) end
	step(0.1)
	for _, r in rf.Rings:GetChildren() do
		if not crowdSeen[r] then
			crowdSeen[r] = true
			crowdRings += 1
			if not ringOk(r) then crowdBad += 1 end
			-- centred on its target's root, as the server saw it the moment the ring appeared
			local target = h.Players:GetPlayerByUserId(r:GetAttribute("TargetId"))
			local tr = target and root(target)
			if not tr or math.abs(tr.Position.X - r.Position.X) > 1e-6 or math.abs(tr.Position.Z - r.Position.Z) > 1e-6 then
				crowdOff += 1
			end
		end
	end
end
truthy(crowdRings >= 30, string.format("a crowded round: %d rings", crowdRings))
eq(crowdBad, 0, string.format("every one is a red disc %.1f studs across (2 x (HitRadius %.1f + PlayerRadius %.1f)), from just over the lowest top it reaches to just over the highest",
	2 * RING_R, Config.Strikes.HitRadius, Config.Hits.PlayerRadius))
eq(crowdOff, 0, "every one is centred on its target's root where it stood when the ring appeared")
untilPhase("intermission", 10)
step(1.1)

--======================================================================= 1. rings, Meteor Shower

print("1. rings")
Config.Shots.ForceKind = "meteor"
Config.Shots.ForceHeat = 0
-- Yan and Xia sit this one out on the deck: rings aimed at them would land near Zed's test spots
rest(B, true)
rest(C, true)
truthy(untilPhase("disaster", 40), "a Meteor Shower starts")
eq(A:GetAttribute("InRound"), "counted", "Zed is in it")
eq(B:GetAttribute("InRound"), "", "Yan is not (on a break at the drop)")
local ringsChecked, geomBad, centreBad = 0, 0, 0
local seen = {}
local mine = {} -- rings aimed at Zed, in order
local outsideDone, insideDone = false, false
local outsideVerdict, insideVerdict = nil, nil
card:clearSent()
while rf:GetAttribute("Phase") == "disaster" and not insideDone do
	for _, r in rf.Rings:GetChildren() do
		if not seen[r] then
			seen[r] = true
			ringsChecked += 1
			if not ringOk(r) then geomBad += 1 end
			if r:GetAttribute("TargetId") == A.UserId then
				local ar = root(A).Position
				if math.abs(ar.X - r.Position.X) > 1e-6 or math.abs(ar.Z - r.Position.Z) > 1e-6 then centreBad += 1 end
				table.insert(mine, { part = r, x = r.Position.X, z = r.Position.Z, impact = r:GetAttribute("ImpactAt") })
			end
		end
	end
	-- the tests: the first ring at Zed is met from 0.05 studs OUTSIDE, the second from 0.05 studs INSIDE
	local k = if not outsideDone then 1 else 2
	local ring = mine[k]
	if ring and now() >= ring.impact - 0.3 and now() <= ring.impact + 0.6 then
		local dx, dz = -ring.x, -ring.z -- toward the island's centre: still on the island, on standing ground
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 1 then dx, dz, d = 1, 0, 1 end
		local off = if k == 1 then RING_R + 0.05 else RING_R - 0.05
		place(A, ring.x + dx / d * off, ring.z + dz / d * off)
	end
	step(0.05)
	if ring and now() > ring.impact + 0.6 then
		local texts = sweptTexts(A)
		if k == 1 and not outsideDone then
			outsideDone = true
			outsideVerdict = #texts
		elseif k == 2 then
			insideDone = true
			insideVerdict = texts[1]
		end
	end
end
if outsideDone and not insideDone and mine[2] then
	-- the hit emptied the island, and an empty island ends the disaster at once (DESIGN.md §2.1)
	insideDone = true
	insideVerdict = sweptTexts(A)[1]
end
truthy(ringsChecked >= 2, string.format("rings fell (%d checked)", ringsChecked))
eq(geomBad, 0, string.format("every ring is a red disc %.1f studs across (2 x (HitRadius %.1f + PlayerRadius %.1f)), from just over the lowest top it reaches to just over the highest",
	2 * RING_R, Config.Strikes.HitRadius, Config.Hits.PlayerRadius))
eq(centreBad, 0, "every ring at Zed is centred on Zed's root where it stood when the ring appeared")
truthy(outsideDone, "the outside test ran")
eq(outsideVerdict, 0, string.format("a root %.2f studs from the centre (0.05 outside the red) through the impact is NOT hit", RING_R + 0.05))
truthy(insideDone, "the inside test ran")
eq(insideVerdict, "💥 " .. Config.Disasters.RingHit.meteor,
	string.format("a root %.2f studs from the centre (0.05 inside the red) through the impact IS hit", RING_R - 0.05))
untilPhase("intermission", 70)
step(1.1)
rest(B, false)

-- from here on, no aimed rings: each verdict is the disaster's own
Config.Strikes.FirstAfterSeconds = 1e6

--======================================================================= 2. flood

print("2. flood")
Config.Shots.ForceKind = "flood"
truthy(untilPhase("drop", 40), "a drop")
eq(A:GetAttribute("InRound"), "counted", "Zed is in the flood round")
eq(B:GetAttribute("InRound"), "counted", "Yan too")
-- Yan waits on the highest cell (levels 3-4 never flood); Zed walks to a beach edge: a level-0 cell (red at the
-- first warning) next to a level-1 cell (dry until the second), and stands 0.05 studs on the DRY side
local levels = {}
for _, c in allCells() do levels[c:GetAttribute("I") * 1000 + c:GetAttribute("J")] = c:GetAttribute("Level") end
local function lv(i, j) return levels[i * 1000 + j] end
local hi, hiLevel = nil, -1
local edge = nil
local ar = root(A).Position
local bestD = math.huge
for i = 1, IC.Grid do
	for j = 1, IC.Grid do
		if lv(i, j) > hiLevel then hi, hiLevel = { i = i, j = j }, lv(i, j) end
		if lv(i, j) == 0 then
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local ni, nj = i + d[1], j + d[2]
				if ni >= 2 and ni <= IC.Grid - 1 and nj >= 2 and nj <= IC.Grid - 1 and lv(ni, nj) == 1 then
					local cx, cz = MapGen.cellCenter(IC, ni, nj)
					local dd = (cx - ar.X) ^ 2 + (cz - ar.Z) ^ 2
					if dd < bestD then bestD, edge = dd, { i = i, j = j, ni = ni, nj = nj, di = d[1], dj = d[2] } end
				end
			end
		end
	end
end
truthy(hiLevel >= IC.HighLevel and edge ~= nil, "the island has a dry top and a beach edge")
local bx, bz = MapGen.cellCenter(IC, hi.i, hi.j)
goals[B] = { x = bx, z = bz }
-- the shared edge between the red cell and its dry neighbour, and the two test spots across it
local rcx, rcz = MapGen.cellCenter(IC, edge.i, edge.j)
local ex, ez = rcx + edge.di * IC.CellStuds / 2, rcz + edge.dj * IC.CellStuds / 2
-- slide along the edge to the middle of the shared side (it is), then 0.05 studs either way across it
local dryX, dryZ = ex + edge.di * 0.05, ez + edge.dj * 0.05
local wetX, wetZ = ex - edge.di * 0.05, ez - edge.dj * 0.05
eq(lv(MapGen.cellAt(IC, dryX, dryZ)), 1, "the dry spot is over the level-1 cell")
eq(lv(MapGen.cellAt(IC, wetX, wetZ)), 0, "the wet spot is over the level-0 cell")
goals[A] = { x = dryX, z = dryZ }
card:clearSent()
-- a third player on the wet side: Xia comes back for this one, after the roster froze, so she jumps in
rest(C, false)
truthy(untilPhase("disaster", 10), "the flood is named")
-- Xia was resting at the freeze: she jumps in for practice and walks to the wet spot (practice is judged the same way)
RS:FindFirstChild("DRRemotes").JumpIn:simulateFireServer(C)
step(0.1)
eq(C:GetAttribute("InRound"), "practice", "Xia jumps in")
goals[C] = { x = wetX, z = wetZ }
local rises = {}
local lastWarn = nil
local floodHits = {}
while rf:GetAttribute("Phase") == "disaster" do
	step(0.1)
	local warn = rf:GetAttribute("WarnLevel")
	if warn ~= nil and warn ~= lastWarn then
		lastWarn = warn
		frame()
		local set, n = {}, 0
		for _, c in allCells() do
			if tinted(c) then set[c] = true n += 1 end
		end
		local slab = rf:FindFirstChild("FloodLine")
		table.insert(rises, { level = warn, tinted = set, n = n, slabY = slab.Position.Y, slabShown = slab.Transparency < 1,
			waterTo = rf:GetAttribute("WaterTo"), riseAt = rf:GetAttribute("RiseAt"), riseEnd = rf:GetAttribute("RiseEnd"),
			warnAt = now(), warnRel = rel(), checked = false })
	end
	for _, r in rises do
	if not r.checked and now() >= r.riseEnd + 0.1 then
		r.checked = true
		local water = rf:FindFirstChild("Water")
		r.waterTop = water.Position.Y + 0.5
		local wrong, flooded = 0, 0
		for _, c in allCells() do
			local isFlooded = MapGen.topY(IC, c:GetAttribute("Level")) < r.waterTop - 1e-9
			if isFlooded then flooded += 1 end
			if isFlooded ~= (r.tinted[c] == true) then wrong += 1 end
		end
		r.flooded, r.wrong = flooded, wrong
	end
	end
	for _, p in { A, C } do
		for _, t in sweptTexts(p) do
			if floodHits[p] == nil then floodHits[p] = { text = t, rise = #rises, rel = rel() } end
		end
	end
end
eq(#rises, #Config.Flood.Levels, "three warnings")
for k, r in rises do
	truthy(r.checked, "rise " .. k .. " was measured")
	truthy(r.n > 0, string.format("rise %d: %d cells tinted red at the warning (%.1f s after the name)", k, r.n, r.warnRel))
	eq(r.wrong, 0, string.format("rise %d: the red cells are exactly the %d cells under water when it ends", k, r.flooded or -1))
	truthy(r.slabShown, "rise " .. k .. ": the red line is shown")
	near(r.slabY, r.waterTop or -999, 1e-6, "rise " .. k .. ": the red line is at the height the water stops")
	near(r.slabY, r.waterTo, 1e-6, "rise " .. k .. ": and at the published WaterTo")
	truthy(r.riseAt - r.warnAt >= Config.Flood.WarnSeconds - 0.15,
		string.format("rise %d: the red shows %.1f s before the water starts to rise", k, r.riseAt - r.warnAt))
end
local floodText = Config.Disasters.Info.flood.icon .. " " .. Config.Disasters.Info.flood.hit
eq(floodHits[C] and floodHits[C].text, floodText, "Xia, 0.05 studs on the red side of the beach edge, is swept by the flood")
eq(floodHits[C] and floodHits[C].rise, 1, "by the first rise")
eq(floodHits[A] and floodHits[A].text, floodText, "Zed, 0.05 studs on the dry side, is swept only when his own cell turns red")
eq(floodHits[A] and floodHits[A].rise, 2, "by the second rise, not the first")
eq(#sweptTexts(B), 0, "Yan, on the highest cell, is never swept")
goals = {}
untilPhase("intermission", 70)

--======================================================================= 3. tornado

print("3. tornado")
Config.Shots.ForceKind = "tornado"
step(1.1)
rest(B, true)
rest(C, true)
truthy(untilPhase("disaster", 40), "a tornado is named")
eq(A:GetAttribute("InRound"), "counted", "Zed is in it")
card:clearSent()
-- the funnel's centre at server time t, from the published path (points every StepSeconds, from t0)
local function funnelAt(t: number): (number?, number?)
	local t0, pts = Tornado.decode(rf:GetAttribute("Path"))
	if not t0 or not pts or #pts < 2 then return nil, nil end
	local stepS = Config.Tornado.StepSeconds
	local k = math.floor((t - t0) / stepS) + 1
	if k < 1 or k >= #pts then return nil, nil end
	local f = (t - (t0 + (k - 1) * stepS)) / stepS
	local a, b = pts[k], pts[k + 1]
	return a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
end
local ribbonsChecked, ribbonBad = 0, 0
local dir = nil
local outsideFrom, outsideUntil, caughtOutside = nil, nil, false
local insideFrom, caughtAt = nil, nil
local DT = 0.02
while rf:GetAttribute("Phase") == "disaster" and caughtAt == nil do
	-- the ribbon: every segment as wide as the funnel's reach, between two published points
	frame()
	local world = h.workspace:FindFirstChild("DRLocalWorld")
	local _, pts = Tornado.decode(rf:GetAttribute("Path"))
	if pts and world then
		-- REVIEW-1 F8: the red is the funnel's reach now and along its path ahead: a disc on the funnel (or, before
		-- touchdown, on the touchdown point) and on every published point after it, and a box as wide as the reach
		-- joining each two in a row. Its track starts at the funnel, never behind it.
		local anchor = rf:FindFirstChild("Funnel")
		local tr = {}
		if anchor and anchor.Position.Y > -100 then
			table.insert(tr, { x = anchor.Position.X, z = anchor.Position.Z })
		else
			table.insert(tr, pts[1])
		end
		for k = 2, #pts do table.insert(tr, pts[k]) end
		for _, seg in world.PathRibbon:GetChildren() do
			ribbonsChecked += 1
			local c = seg.Position
			local ok = false
			if seg.Shape == Enum.PartType.Cylinder then
				for _, q in tr do
					if math.abs(c.X - q.x) < 1e-6 and math.abs(c.Z - q.z) < 1e-6 and math.abs(seg.Size.Y - 2 * FUNNEL_R) < 1e-6
						and math.abs(seg.Size.Z - 2 * FUNNEL_R) < 1e-6 then ok = true end
				end
			else
				for k = 2, #tr do
					local mx, mz = (tr[k - 1].x + tr[k].x) / 2, (tr[k - 1].z + tr[k].z) / 2
					local len = math.sqrt((tr[k].x - tr[k - 1].x) ^ 2 + (tr[k].z - tr[k - 1].z) ^ 2)
					if math.abs(c.X - mx) < 1e-6 and math.abs(c.Z - mz) < 1e-6 and math.abs(seg.Size.Z - len) < 1e-6
						and math.abs(seg.Size.X - 2 * FUNNEL_R) < 1e-6 then ok = true end
				end
			end
			if not ok then ribbonBad += 1 end
		end
	end
	local t = now()
	local fx, fz = funnelAt(t + DT / 2)
	if fx and rel() >= Config.Tornado.TouchdownAt + 0.3 then
		local p = root(A).Position
		if dir == nil then
			local dx, dz = p.X - fx, p.Z - fz -- approach from Zed's own side: he never crosses the funnel's disc
			local d = math.sqrt(dx * dx + dz * dz)
			dir = { x = dx / d, z = dz / d }
		end
		local off = if insideFrom then FUNNEL_R - 0.25 else FUNNEL_R + 0.25
		local gx, gz = fx + dir.x * off, fz + dir.z * off
		local dx, dz = gx - p.X, gz - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if outsideFrom == nil and d <= 15 * DT then outsideFrom = t end
		if outsideFrom and insideFrom == nil and t - outsideFrom >= 3 then insideFrom = t end
		if outsideFrom then
			place(A, gx, gz) -- riding: re-placed every 0.02 s (at most 0.18 studs per step, under the guard)
		else
			local s = 15 * DT
			place(A, p.X + dx / d * s, p.Z + dz / d * s)
		end
	end
	step(DT)
	if #sweptTexts(A) > 0 then
		if insideFrom then caughtAt = now() - insideFrom else caughtOutside = true break end
	end
end
truthy(ribbonsChecked > 0, string.format("the red path was drawn (%d segment frames checked)", ribbonsChecked))
eq(ribbonBad, 0, string.format("every red path piece is %.1f studs across (2 x the funnel's reach): a disc on the funnel or a published point ahead of it, or a box joining two in a row", 2 * FUNNEL_R))
truthy(outsideFrom ~= nil, "Zed reached the funnel's side")
eq(caughtOutside, false, string.format("riding %.2f studs from the funnel's centre (0.25 outside the red) for 3 s: never caught", FUNNEL_R + 0.25))
truthy(caughtAt ~= nil and caughtAt <= Config.Hits.LagGrace + 0.25,
	string.format("riding %.2f studs from it (0.25 inside): caught after %.2f s", FUNNEL_R - 0.25, caughtAt or -1))
eq(sweptTexts(A)[1], Config.Disasters.Info.tornado.icon .. " " .. Config.Disasters.Info.tornado.hit, "by the tornado")
untilPhase("intermission", 70)

--======================================================================= 4. earthquake

print("4. earthquake")
Config.Shots.ForceKind = "quake"
truthy(untilPhase("disaster", 40), "an earthquake is named")
eq(A:GetAttribute("InRound"), "counted", "Zed is in it")
card:clearSent()
local tintBad, batches = 0, 0
local lastCracks = 0
local test = nil -- { phase = "outside"|"inside", dropAt, x, z }
local outsideOk, insideText = nil, nil
local function crackPairs()
	local out = {}
	for _, c in allCells() do
		if c:GetAttribute("CrackAt") ~= nil and c:GetAttribute("Dropped") ~= true then
			local i, j = c:GetAttribute("I"), c:GetAttribute("J")
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local n = cellPart(i + d[1], j + d[2])
				if n and n:GetAttribute("CrackAt") == nil and n:GetAttribute("Dropped") ~= true then
					table.insert(out, { c = c, n = n, i = i, j = j, di = d[1], dj = d[2], dropAt = c:GetAttribute("DropAt") })
				end
			end
		end
	end
	return out
end
-- does the straight walk from p to (x, z) pass over a hole?
local function crossesHole(p, x: number, z: number): boolean
	local L = math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2)
	for k = 0, math.ceil(L / 0.5) do
		local f = if L > 0 then math.min(1, k * 0.5 / L) else 1
		local i, j = MapGen.cellAt(IC, p.X + (x - p.X) * f, p.Z + (z - p.Z) * f)
		local c = i and cellPart(i, j)
		if not c or c:GetAttribute("Dropped") == true then return true end
	end
	return false
end
while rf:GetAttribute("Phase") == "disaster" and insideText == nil do
	step(0.05)
	frame()
	-- the red cells are exactly the cracked ones
	local cracks = 0
	for _, c in allCells() do
		local cracked = c:GetAttribute("CrackAt") ~= nil and c:GetAttribute("Dropped") ~= true
		if cracked then cracks += 1 end
		if cracked ~= tinted(c) then tintBad += 1 end
		if cracked and (math.abs(c.Size.X - IC.CellStuds) > 1e-6 or math.abs(c.Size.Z - IC.CellStuds) > 1e-6) then tintBad += 1 end
	end
	if cracks > lastCracks then batches += 1 end
	lastCracks = cracks
	-- pick a test at a fresh batch: the nearest crack edge Zed can walk to without crossing a hole, in time
	if test == nil and insideText == nil then
		local p = root(A).Position
		local best, bestD = nil, math.huge
		for _, pr in crackPairs() do
			local cx, cz = MapGen.cellCenter(IC, pr.i, pr.j)
			local ex, ez = cx + pr.di * IC.CellStuds / 2, cz + pr.dj * IC.CellStuds / 2
			local sgn = if outsideOk == nil then 1 else -1 -- outside: on the neighbour; inside: on the dropping cell
			local x, z = ex + pr.di * 0.05 * sgn, ez + pr.dj * 0.05 * sgn
			local d = math.sqrt((x - p.X) ^ 2 + (z - p.Z) ^ 2)
			if d < bestD and d / 15 < pr.dropAt - now() - 0.4 and not crossesHole(p, x, z) then best, bestD = { x = x, z = z, dropAt = pr.dropAt }, d end
		end
		if best then
			test = best
			goals[A] = { x = best.x, z = best.z }
		end
	end
	if test and now() > test.dropAt + 0.5 then
		local texts = sweptTexts(A)
		if outsideOk == nil then
			outsideOk = #texts == 0
			test = nil
		else
			insideText = texts[1] or "not hit"
		end
	end
end
if test and outsideOk ~= nil and insideText == nil then
	insideText = sweptTexts(A)[1] or "not hit" -- the hit emptied the island and ended the round at once
end
truthy(batches >= 2, string.format("cracks came (%d batches seen)", batches))
eq(tintBad, 0, "every frame, the red cells are exactly the cracked cells, each a whole 8 x 8 cell")
eq(outsideOk, true, "0.05 studs over the edge on the intact neighbour when the cell drops: NOT hit")
eq(insideText, Config.Disasters.Info.quake.icon .. " " .. Config.Disasters.Info.quake.hit,
	"0.05 studs inside the dropping cell's edge: hit, the ground gave way")
goals = {}

local riseCells = {}
for _, r in rises do table.insert(riseCells, tostring(r.n)) end
print(string.format("  %d rings in a crowded round + %d in the edge tests; flood red cells per rise %s, each exactly the flooded set; %d ribbon segment frames; %d quake batches, red = cracked every frame; tornado caught %.2f s after crossing in",
	crowdRings, ringsChecked, table.concat(riseCells, "/"), ribbonsChecked, batches, caughtAt or -1))
for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	if string.find(w, "failed", 1, true) or string.find(w, "error", 1, true) then
		failed += 1
		print("FAIL: the game warned: " .. w)
	end
end
print(string.format("disasterrounds zones: %d passed, %d failed", passed, failed))
