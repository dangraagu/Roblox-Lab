-- Disaster Rounds - the red you can SEE on terraced ground, through the real server and World.client.
-- Run: luau check_disasterrounds_terrace.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- REVIEW-1 F7 and F8 (disaster-rounds/REVIEW-1.md). The hit tests are 2-D; the island is terraced. The first build drew
-- every ring as a flat disc at the top of the cell under its centre and the tornado's path at the funnel's own cell:
-- on a higher terrace that red was buried inside the cell's column (34-35 % of rings had part of their reach hidden,
-- and a player who stepped up out of the red they could see was hit), and the funnel's own disc was drawn only 0.25-2.5
-- studs behind its centre while it hits 6.5 studs all round (a player who stopped 4 studs behind it, on unmarked
-- ground, was caught in 6 of 6 seeds). This file asks the built world:
--   1. every ring of crowded Meteor and Earthquake rounds is a red volume that shows at the ground of EVERY cell its
--      reach touches: from <= 0.05 over the lowest top to >= 0.25 over the highest;
--   2. the review's case: a ring 1 stud from a step up, the player 1.5 studs up onto the higher terrace: red shows there;
--   3. the tornado, sampled every 0.1 s at 120 points: every point within the funnel's reach now or on its drawn path
--      ahead is under a red piece that shows at that point's ground, and no point 0.05 studs outside all of that is red;
--   4. the review's case: a player who walks up behind the funnel and stops 4 studs from its centre stands in red.

local SEED = 31077
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

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local ws = h.workspace
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local MapGen = h:_require(RS:FindFirstChild("MapGen"))
local Tornado = h:_require(RS:FindFirstChild("Tornado"))
local IC = Config.Island
local rf = ws:FindFirstChild("Round")
local card = RS:FindFirstChild("DRRemotes"):FindFirstChild("Card")
local RunService = h.game:GetService("RunService")
local RING_R = Config.Strikes.HitRadius + Config.Hits.PlayerRadius
local FUNNEL_R = Config.Tornado.HitRadius + Config.Hits.PlayerRadius
h.game:GetService("RunService"):setIsServer(false)

local players = {}
for k = 1, 8 do
	local p = h:join("T" .. k, 8800 + k)
	h.Players:simulateSpawn(p, ws)
	table.insert(players, p)
end
local A = players[1]
h.Players.LocalPlayer = A
local okW, errW = h:tryRun("client/World.client")
truthy(okW, "World.client loads (" .. tostring(errW) .. ")")

local function now(): number return h.scheduler:now() end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function cellPart(i: number, j: number)
	local island = rf:FindFirstChild("Island")
	return island and island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
end
-- the ground's top at (x, z), or nil off the island or over a dropped cell
local function groundAt(x: number, z: number): number?
	local i, j = MapGen.cellAt(IC, x, z)
	local c = i and cellPart(i, j)
	if not c or c:GetAttribute("Dropped") == true then return nil end
	return MapGen.topY(IC, c:GetAttribute("Level"))
end
local function place(p, x: number, z: number)
	root(p).CFrame = CFrame.new(x, (groundAt(x, z) or 0) + 3, z)
end
local function frame() RunService.RenderStepped:Fire(0) end
local function step(dt: number)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function untilPhase(ph: string, lim: number, each: ((number) -> ())?): boolean
	local n = 0
	while rf:GetAttribute("Phase") ~= ph and n < lim / 0.1 do
		if each then each(0.1) end
		step(0.1)
		n += 1
	end
	return rf:GetAttribute("Phase") == ph
end
local function swept(p): string?
	for _, r in card:sentTo(p) do
		if r.args[1] == "swept" then return tostring(r.args[2] and r.args[2].text) end
	end
	return nil
end

-- the cells a disc reaches, by brute geometry (independent of Zones): the square's nearest point to the centre
local function cellsUnderDisk(cx: number, cz: number, r: number): { any }
	local out = {}
	for i = 1, IC.Grid do
		for j = 1, IC.Grid do
			local mx, mz = MapGen.cellCenter(IC, i, j)
			local s = IC.CellStuds / 2
			local dx = math.max(math.abs(cx - mx) - s, 0)
			local dz = math.max(math.abs(cz - mz) - s, 0)
			if dx * dx + dz * dz <= r * r then table.insert(out, { i = i, j = j }) end
		end
	end
	return out
end

-- a red Part's footprint test and vertical span. A Cylinder's axis is its local X: vertical means a flat disc.
local function redSpanOf(part): (number, number)
	if part.Shape == Enum.PartType.Cylinder then
		return part.Position.Y - part.Size.X / 2, part.Position.Y + part.Size.X / 2
	end
	return part.Position.Y - part.Size.Y / 2, part.Position.Y + part.Size.Y / 2
end
local function covers(part, x: number, z: number, slack: number): boolean
	local c = part.Position
	if part.Shape == Enum.PartType.Cylinder then
		local r = part.Size.Y / 2
		return (x - c.X) ^ 2 + (z - c.Z) ^ 2 <= (r + slack) ^ 2
	end
	local look = part.CFrame.LookVector
	local L = math.sqrt(look.X * look.X + look.Z * look.Z)
	local lx, lz = look.X / L, look.Z / L
	local dx, dz = x - c.X, z - c.Z
	local along, across = dx * lx + dz * lz, -dx * lz + dz * lx
	return math.abs(along) <= part.Size.Z / 2 + slack and math.abs(across) <= part.Size.X / 2 + slack
end
-- does red SHOW at the ground at (x, z)? some piece covers the point and its volume reaches from <= 0.05 over the
-- ground to >= 0.25 over it (the old flat disc's own extent)
local function showsAt(pieces: { any }, x: number, z: number, ground: number): boolean
	for _, part in pieces do
		if covers(part, x, z, 0) then
			local lo, hi = redSpanOf(part)
			if lo <= ground + 0.05 + 1e-6 and hi >= ground + 0.25 - 1e-6 then return true end
		end
	end
	return false
end
local function anyCovers(pieces: { any }, x: number, z: number, slack: number): boolean
	for _, part in pieces do
		if covers(part, x, z, slack) then return true end
	end
	return false
end

--======================================================================= 1. every ring shows at every cell it reaches

print("1. rings on terraces")
local bots = {}
for _, p in players do table.insert(bots, Bot.new(h, p, { react = 0.6 })) end
local function botStep(dt: number)
	for _, b in bots do Bot.step(b, dt) end
end
Config.Shots.ForceHeat = 5
local ringsSeen, ringsBad, multiLevel, cellsChecked = 0, 0, 0, 0
local badSample = nil
for _, kind in { "meteor", "quake", "meteor" } do
	Config.Shots.ForceKind = kind
	untilPhase("intermission", 100, botStep)
	truthy(untilPhase("disaster", 40, botStep), kind .. ": a round at Heat 5 with 8 players")
	local seen = {}
	while rf:GetAttribute("Phase") == "disaster" do
		botStep(0.1)
		step(0.1)
		for _, r in rf.Rings:GetChildren() do
			if not seen[r] then
				seen[r] = true
				ringsSeen += 1
				local lo, hi = redSpanOf(r)
				local levels = {}
				local bad = false
				for _, c in cellsUnderDisk(r.Position.X, r.Position.Z, RING_R) do
					local cp = cellPart(c.i, c.j)
					if cp and cp:GetAttribute("Dropped") ~= true then
						cellsChecked += 1
						local top = MapGen.topY(IC, cp:GetAttribute("Level"))
						levels[top] = true
						if not (lo <= top + 0.05 + 1e-6 and hi >= top + 0.25 - 1e-6) then bad = true end
					end
				end
				local nl = 0
				for _ in levels do nl += 1 end
				if nl > 1 then multiLevel += 1 end
				local okShape = r.Shape == Enum.PartType.Cylinder and math.abs(r.Size.Y - 2 * RING_R) < 1e-6
					and math.abs(r.Size.Z - 2 * RING_R) < 1e-6 and math.abs(math.abs(r.CFrame.RightVector.Y) - 1) < 1e-6
				if bad or not okShape then
					ringsBad += 1
					badSample = badSample or string.format("ring at (%.1f, %.1f) spans y %.2f..%.2f over %d level(s)", r.Position.X, r.Position.Z, lo, hi, nl)
				end
			end
		end
	end
end
truthy(ringsSeen >= 60, string.format("%d rings over 3 crowded rounds", ringsSeen))
truthy(multiLevel > 0, string.format("%d of them (%.0f %%) reach cells on more than one level", multiLevel, 100 * multiLevel / math.max(1, ringsSeen)))
eq(ringsBad, 0, string.format("every ring shows red at the ground of every one of the %d cells it reaches (%s)", cellsChecked, badSample or "none bad"))
print(string.format("  %d rings, %d (%.0f %%) over more than one level, %d ring-cells checked, %d without red at their ground", ringsSeen, multiLevel,
	100 * multiLevel / math.max(1, ringsSeen), cellsChecked, ringsBad))
Config.Shots.ForceHeat = nil
bots = {}

--======================================================================= 2. the review's step-up case

print("2. one stud from a step up")
Config.Shots.ForceKind = "meteor"
for k = 2, #players do
	h.ReplicatedStorage.DRRemotes.SetRest:simulateFireServer(players[k], true) -- only A this round
end
untilPhase("intermission", 100)
truthy(untilPhase("drop", 40), "a drop")
eq(A:GetAttribute("InRound"), "counted", "A is in it, alone")
-- a level-L cell whose +X neighbour is level L+1, nearest to where A landed
local p0 = root(A).Position
local best, bestD = nil, math.huge
for i = 2, IC.Grid - 2 do
	for j = 2, IC.Grid - 1 do
		local c, n = cellPart(i, j), cellPart(i + 1, j)
		if c and n and c:GetAttribute("Level") >= 1 and n:GetAttribute("Level") == c:GetAttribute("Level") + 1 then
			local cx, cz = MapGen.cellCenter(IC, i, j)
			local d = math.sqrt((cx - p0.X) ^ 2 + (cz - p0.Z) ^ 2)
			if d < bestD then best, bestD = { i = i, j = j, L = c:GetAttribute("Level") }, d end
		end
	end
end
truthy(best ~= nil, "the island has a one-level step up")
if best then
	local cx, cz = MapGen.cellCenter(IC, best.i, best.j)
	local edgeX = cx + IC.CellStuds / 2
	-- walk to 1 stud short of the step, at 15 studs/s
	local function walkTo(x: number, z: number)
		for _ = 1, 400 do
			local p = root(A).Position
			local dx, dz = x - p.X, z - p.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < 0.01 then return end
			local s = math.min(d, 15 * 0.05)
			place(A, p.X + dx / d * s, p.Z + dz / d * s)
			step(0.05)
		end
	end
	walkTo(edgeX - 1, cz)
	card:clearSent()
	local ring = nil
	while ring == nil and rf:GetAttribute("Phase") ~= "outro" do
		step(0.05)
		for _, r in rf.Rings:GetChildren() do ring = r end
	end
	truthy(ring ~= nil, "a ring comes at A, 1 stud from the step")
	if ring then
		walkTo(edgeX + 1.5, cz) -- up onto the higher terrace, 1.5 studs past the edge (2.5 from the centre, inside 4.5)
		local p = root(A).Position
		local top = groundAt(p.X, p.Z) :: number
		eq(top, MapGen.topY(IC, best.L + 1), "A stands on the higher terrace")
		truthy(showsAt({ ring }, p.X, p.Z, top), string.format("red shows under A there (the ring spans y %.2f..%.2f, this terrace's top is %d)",
			select(1, redSpanOf(ring)), select(2, redSpanOf(ring)), top))
		local t0 = now()
		while now() - t0 < 4 do step(0.05) end
		eq(swept(A), "💥 " .. Config.Disasters.RingHit.meteor, "and where red shows, it hits")
	end
end
for k = 2, #players do h.ReplicatedStorage.DRRemotes.SetRest:simulateFireServer(players[k], false) end

--======================================================================= 3. the tornado: red exactly where the funnel reaches

print("3. the tornado's red")
Config.Strikes.FirstAfterSeconds = 1e6 -- no aimed rings: the only red is the funnel's
Config.Shots.ForceKind = "tornado"
untilPhase("intermission", 100)
h:advance(1.1)
truthy(untilPhase("disaster", 40), "a tornado is named")
local s3 = 777
local function r01(): number
	s3 = (1664525 * s3 + 1013904223) % 4294967296
	return s3 / 4294967296
end
-- the funnel's reach now and on its published path ahead: the anchor and the points after it (before touchdown, the
-- touchdown point and on); the distance from (x, z) to that track
local function track(): { any }?
	local _, pts = Tornado.decode(rf:GetAttribute("Path"))
	if not pts then return nil end
	local anchor = rf:FindFirstChild("Funnel")
	local out = {}
	if anchor and anchor.Position.Y > -100 then
		table.insert(out, { x = anchor.Position.X, z = anchor.Position.Z })
	else
		table.insert(out, pts[1])
	end
	for k = 2, #pts do table.insert(out, pts[k]) end
	return out
end
local function distTo(tr: { any }, x: number, z: number): number
	local best = math.huge
	if #tr == 1 then return math.sqrt((x - tr[1].x) ^ 2 + (z - tr[1].z) ^ 2) end
	for k = 2, #tr do
		local a, b = tr[k - 1], tr[k]
		local abx, abz = b.x - a.x, b.z - a.z
		local len2 = abx * abx + abz * abz
		local f = if len2 > 0 then math.clamp(((x - a.x) * abx + (z - a.z) * abz) / len2, 0, 1) else 0
		best = math.min(best, math.sqrt((a.x + abx * f - x) ^ 2 + (a.z + abz * f - z) ^ 2))
	end
	return best
end
local inside, insideBad, outside, outsideBad, frames = 0, 0, 0, 0, 0
local badIn, badOut = nil, nil
local beforeTouchdown = 0
while rf:GetAttribute("Phase") == "disaster" do
	step(0.1)
	frame()
	local tr = track()
	local world = ws:FindFirstChild("DRLocalWorld")
	if tr and world then
		frames += 1
		local pieces = world.PathRibbon:GetChildren()
		local anchor = rf:FindFirstChild("Funnel")
		if not (anchor and anchor.Position.Y > -100) and #pieces > 0 then beforeTouchdown += 1 end
		local pts = {}
		-- random points near the track, and points 0.05 either side of the funnel's own disc and of every segment
		for _ = 1, 60 do
			local base = tr[1 + math.floor(r01() * #tr)]
			table.insert(pts, { x = base.x + (r01() * 2 - 1) * 12, z = base.z + (r01() * 2 - 1) * 12 })
		end
		local a0 = tr[1]
		for k = 0, 15 do
			local ang = k * math.pi / 8
			for _, d in { FUNNEL_R - 0.05, FUNNEL_R + 0.05 } do
				table.insert(pts, { x = a0.x + math.cos(ang) * d, z = a0.z + math.sin(ang) * d })
			end
		end
		for k = 2, #tr do
			local a, b = tr[k - 1], tr[k]
			local dx, dz = b.x - a.x, b.z - a.z
			local L = math.sqrt(dx * dx + dz * dz)
			if L > 0.01 then
				local nx, nz = -dz / L, dx / L
				local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
				for _, d in { FUNNEL_R - 0.05, FUNNEL_R + 0.05 } do
					for _, sgn in { 1, -1 } do table.insert(pts, { x = mx + nx * d * sgn, z = mz + nz * d * sgn }) end
				end
			end
		end
		for _, q in pts do
			local g = groundAt(q.x, q.z)
			if g then
				local d = distTo(tr, q.x, q.z)
				if d <= FUNNEL_R - 0.05 then
					inside += 1
					if not showsAt(pieces, q.x, q.z, g) then
						insideBad += 1
						badIn = badIn or string.format("(%.2f, %.2f) %.2f studs from the track, ground %d", q.x, q.z, d, g)
					end
				elseif d >= FUNNEL_R + 0.05 then
					outside += 1
					if anyCovers(pieces, q.x, q.z, 0) then
						outsideBad += 1
						badOut = badOut or string.format("(%.2f, %.2f) %.2f studs from the track", q.x, q.z, d)
					end
				end
			end
		end
	end
end
truthy(frames >= 100, string.format("%d frames of a tornado sampled", frames))
truthy(beforeTouchdown > 0, string.format("the path is drawn from the name, before the funnel touches down (%d frames)", beforeTouchdown))
eq(insideBad, 0, string.format("all %d sampled points within the funnel's reach (now or on its path ahead) show red at their ground (%s)", inside, badIn or "none missed"))
eq(outsideBad, 0, string.format("none of %d points 0.05 studs or more outside it is red (%s)", outside, badOut or "none"))
print(string.format("  tornado: %d frames (%d before touchdown); %d points inside the reach, %d without red; %d outside, %d red", frames,
	beforeTouchdown, inside, insideBad, outside, outsideBad))

--======================================================================= 4. the review's wake case

print("4. behind the funnel")
untilPhase("intermission", 70)
for k = 2, #players do h.ReplicatedStorage.DRRemotes.SetRest:simulateFireServer(players[k], true) end
truthy(untilPhase("disaster", 40), "a tornado, A alone")
card:clearSent()
local nameAt = rf:GetAttribute("NameAt")
local DT = 0.02
local D = 14
local closeFrames, closeOffRed = 0, 0
local caught = nil
local function funnelNow()
	local t0, pts = Tornado.decode(rf:GetAttribute("Path"))
	if not t0 or not pts or #pts < 3 then return nil end
	local stepS = Config.Tornado.StepSeconds
	local k = math.floor((now() - t0) / stepS) + 1
	if k < 1 or k >= #pts then return nil end
	local f = (now() - (t0 + (k - 1) * stepS)) / stepS
	local a, b = pts[k], pts[k + 1]
	local hx, hz = b.x - a.x, b.z - a.z
	local hl = math.sqrt(hx * hx + hz * hz)
	if hl < 1e-6 then return nil end
	return { x = a.x + hx * f, z = a.z + hz * f, hx = hx / hl, hz = hz / hl }
end
while rf:GetAttribute("Phase") == "disaster" and caught == nil do
	local F = funnelNow()
	if F and now() - nameAt > Config.Tornado.TouchdownAt + 0.5 then
		local p = root(A).Position
		local behind = (p.X - F.x) * F.hx + (p.Z - F.z) * F.hz < 0
		local tx, tz
		if behind then
			D = math.max(4, D - 3 * DT)
			tx, tz = F.x - F.hx * D, F.z - F.hz * D
		else
			local sx, sz = -F.hz, F.hx
			local side = if (p.X - F.x) * sx + (p.Z - F.z) * sz >= 0 then 1 else -1
			tx, tz = F.x + sx * side * (FUNNEL_R + 6) - F.hx * 6, F.z + sz * side * (FUNNEL_R + 6) - F.hz * 6
		end
		local lim = MapGen.halfSize(IC) - 2
		tx, tz = math.clamp(tx, -lim, lim), math.clamp(tz, -lim, lim)
		local dx, dz = tx - p.X, tz - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		local s = 15 * DT
		if d <= s then place(A, tx, tz) elseif d > 0 then place(A, p.X + dx / d * s, p.Z + dz / d * s) end
		frame()
		p = root(A).Position
		local anchor = rf:FindFirstChild("Funnel")
		local g = groundAt(p.X, p.Z)
		if anchor and g and math.sqrt((p.X - anchor.Position.X) ^ 2 + (p.Z - anchor.Position.Z) ^ 2) <= FUNNEL_R - 0.05 then
			closeFrames += 1
			if not showsAt(ws.DRLocalWorld.PathRibbon:GetChildren(), p.X, p.Z, g) then closeOffRed += 1 end
		end
	end
	step(DT)
	caught = swept(A)
end
eq(caught, Config.Disasters.Info.tornado.icon .. " " .. Config.Disasters.Info.tornado.hit, "A, closing in behind the funnel to 4 studs, is caught")
truthy(closeFrames > 0, string.format("%d frames inside the funnel's reach before that", closeFrames))
eq(closeOffRed, 0, "and in every one of them A stood on red")
print(string.format("  behind the funnel: %d frames inside its reach, %d off red; %s", closeFrames, closeOffRed, tostring(caught)))
for k = 2, #players do h.ReplicatedStorage.DRRemotes.SetRest:simulateFireServer(players[k], false) end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("disasterrounds terrace: %d passed, %d failed", passed, failed))
