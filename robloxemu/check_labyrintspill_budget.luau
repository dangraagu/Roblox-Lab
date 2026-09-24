-- Labyrinth Mariozo — the eye-candy budgets under load, asserted on every frame.
-- Run: luau check_labyrintspill_budget.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- check_labyrintspill_biomes measures each biome where a run starts (a maze corner). This walks the
-- player through the middle of the BIGGEST mazes (30x30, every biome from the sky ruins' size up is
-- 30x30; earlier biomes at their largest size), so decor saturates, hazards come and go, and then
-- hops between biomes through the lobby and advances level after level across a seam. On every frame:
-- local parts, enabled emitters and their summed rate, lights, drawn hazards — against Biomes.Budget.
-- It also counts every instance the client EVER creates: pools must stop growing once warm.
-- (resume session) Last, the decor cap is forced low in memory to prove the client honours it at all.
-- (review fix) The documented peak comes from a visit to EVERY open cell of each biggest maze (a sampled walk
-- understated it: 41 vs 49), and a structural bound from the real builder holds whatever the position.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill budget")
local truthy, eq = T.truthy, T.eq

local ctx = Lib.boot({ accepted = 480, clients = Lib.CLIENTS_NO_SOUND })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local Biomes = h:_require(h.ReplicatedStorage:FindFirstChild("Biomes"))
local EnvBands = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBands"))
local B = Biomes.Budget
local LOCAL = h.workspace:FindFirstChild("LabyrintBiomeLocal")

-- unique instances ever seen under the folder (a pooled part is re-parented, not re-created: DescendantAdded
-- fires again for it, so it is counted once by identity)
local created = 0
local seen = setmetatable({}, { __mode = "k" })
LOCAL.DescendantAdded:Connect(function(d)
	if not seen[d] then
		seen[d] = true
		created += 1
	end
end)

local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, rings = 0, decor = 0 }
local over = 0
local function measure(tag)
	local c = Lib.census(h)
	local rings, decor = 0, 0
	for _, d in c.all do
		if d.Name == "HazardRing" then rings += 1 end
		if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Decor_" then decor += 1 end
	end
	peak.parts = math.max(peak.parts, c.parts)
	peak.emitters = math.max(peak.emitters, c.emitters)
	peak.rate = math.max(peak.rate, c.rate)
	peak.lights = math.max(peak.lights, c.lights)
	peak.rings = math.max(peak.rings, rings)
	peak.decor = math.max(peak.decor, decor)
	if c.parts > B.MaxLocalParts or c.emitters > B.MaxEmitters or c.rate > B.MaxEmitterRate + 1e-6
		or c.lights > B.MaxMazeLights or rings > B.MaxHazardsShown then
		over += 1
		if over <= 5 then
			print(string.format("   OVER BUDGET at %s: %d parts, %d emitters (%.1f/s), %d lights, %d rings", tag, c.parts, c.emitters, c.rate, c.lights, rings))
		end
	end
	return c, rings, decor
end
ctx.onFrame = function() measure("frame") end

--================================================================ walk the middle of big mazes

print("== walking 60 cells through the middle of each biome's biggest maze")
print("   biome                 level size  peak parts  peak decor parts  peak emitters (rate)  rings")
for i, b in Biomes.Bands do
	local nextFrom = if Biomes.Bands[i + 1] then Biomes.Bands[i + 1].from else 481
	local L = nextFrom - 1
	ctx.startRun(L)
	local g = Lib.grid(ctx.folder())
	local bandPeak = { parts = 0, decor = 0, emitters = 0, rate = 0, rings = 0 }
	-- a serpentine through the inner cells, 0.5 s per cell
	local n = 0
	for cy = 1, g.rows - 2, 2 do
		for k = 1, g.cols - 2, 2 do
			local cx = if (cy // 2) % 2 == 0 then k else g.cols - 1 - k
			ctx.moveTo(g.world(2 * cx + 1, 2 * cy + 1))
			ctx.run(0.5, 1 / 30, function()
				local c, rings, decor = measure(b.name)
				bandPeak.parts = math.max(bandPeak.parts, c.parts)
				bandPeak.decor = math.max(bandPeak.decor, decor)
				bandPeak.emitters = math.max(bandPeak.emitters, c.emitters)
				bandPeak.rate = math.max(bandPeak.rate, c.rate)
				bandPeak.rings = math.max(bandPeak.rings, rings)
			end)
			n += 1
			if n >= 60 then break end
		end
		if n >= 60 then break end
	end
	print(string.format("   %-2s %-18s %5d  %2dx%-2d  %10d  %16d  %13d (%.1f)  %5d", b.emoji, b.name, L, g.cols, g.rows,
		bandPeak.parts, bandPeak.decor, bandPeak.emitters, bandPeak.rate, bandPeak.rings))
	truthy(bandPeak.decor > 0, b.name .. ": decor was built along the walk")
end

--================================================================ (review fix) EVERY open cell of each biggest maze
-- The 60-cell walk above reported a peak of 41 local parts; the adversarial review visited every open cell and
-- found 49 (L25). A sampled walk understates a peak, so the peak this game documents comes from here: every
-- open fine cell of each biome's biggest maze, standing at its centre for one frame (decor is re-selected on
-- entering a cell). Then the bound that holds whatever the position: MaxDecorPieces x MaxPrimsPerPiece decor
-- parts + MaxHazardsShown hazard views of the largest kind (built by the real BiomeArt) + the air box.

print("== every open cell of each biome's biggest maze (one frame per cell)")
print("   biome                 level  cells  peak parts  peak decor parts  where")
local sweepPeak = { parts = 0, decor = 0, level = 0 }
for i, b in Biomes.Bands do
	local nextFrom = if Biomes.Bands[i + 1] then Biomes.Bands[i + 1].from else 481
	local L = nextFrom - 1
	ctx.startRun(L)
	local g = Lib.grid(ctx.folder())
	local bp, bd, cells, where = 0, 0, 0, ""
	for fx = 1, g.gCols - 2 do
		for fy = 1, g.gRows - 2 do
			if g.walls[fx .. "," .. fy] == nil then
				ctx.moveTo(g.world(fx, fy))
				local c, _, decor = measure(b.name .. " sweep")
				ctx.frame(1 / 30)
				c, _, decor = measure(b.name .. " sweep")
				cells += 1
				if c.parts > bp then bp = c.parts; where = fx .. "," .. fy end
				bd = math.max(bd, decor)
			end
		end
	end
	print(string.format("   %-2s %-18s %5d  %5d  %10d  %16d  %s", b.emoji, b.name, L, cells, bp, bd, where))
	if bp > sweepPeak.parts then sweepPeak = { parts = bp, decor = bd, level = L } end
	truthy(cells > 0 and bp <= B.MaxLocalParts, string.format("%s L%d: every open cell visited (%d), peak %d parts within %d", b.name, L, cells, bp, B.MaxLocalParts))
end
print(string.format("== every-cell peak: %d local parts (%d decor) at L%d", sweepPeak.parts, sweepPeak.decor, sweepPeak.level))
truthy(sweepPeak.parts >= 41, "the every-cell peak is at least the sampled walk's (a sweep cannot see less than a sample of it)")

do
	local BiomeArt = h:_require(h.ReplicatedStorage:FindFirstChild("BiomeArt"))
	local scratch = Instance.new("Folder")
	scratch.Name = "BudgetScratch"
	scratch.Parent = h.workspace
	local maxView = 0
	for kind in Biomes.Hazards.Kinds do
		local v = BiomeArt.buildHazardView(scratch, 4.2, Color3.fromRGB(100, 160, 255))
		BiomeArt.showHazardView(v, kind, Vector3.new(0, 0, 0), "warn", 0.5, 0, false)
		local n = 0
		for _, d in scratch:GetDescendants() do
			if d:IsA("BasePart") then n += 1 end
		end
		maxView = math.max(maxView, n)
		scratch:ClearAllChildren()
	end
	scratch:Destroy()
	local bound = B.MaxDecorPieces * B.MaxPrimsPerPiece + B.MaxHazardsShown * maxView + 1
	print(string.format("== structural bound: %d x %d decor + %d x %d (largest hazard view) + 1 air box = %d parts (budget %d)",
		B.MaxDecorPieces, B.MaxPrimsPerPiece, B.MaxHazardsShown, maxView, bound, B.MaxLocalParts))
	truthy(maxView >= 5, "the largest hazard view was really built (" .. maxView .. " parts)")
	truthy(bound <= B.MaxLocalParts, string.format("whatever the position, the maze's local parts stay within budget (%d <= %d)", bound, B.MaxLocalParts))
end

--================================================================ hop between biomes through the lobby

local createdWarm = created
local LEVELS = { 5, 380, 18, 200, 38, 300, 75, 131 }
for cycle = 1, 3 do
	for _, L in LEVELS do
		ctx.startRun(L)
		local g = Lib.grid(ctx.folder())
		ctx.moveTo(g.world(2 * (g.cols // 2) + 1, 2 * (g.rows // 2) + 1))
		ctx.run(1.2)
	end
	if cycle == 1 then createdWarm = created end
end
local grewAfterWarm = created - createdWarm
print(string.format("== hops: %d instances created in total; %d more after the first round of %d hops (pools warm)", created, grewAfterWarm, #LEVELS))
truthy(grewAfterWarm <= 12, string.format("pools stop growing: at most a dozen new instances in two more rounds (%d)", grewAfterWarm))

--================================================================ advance level after level across a seam

ctx.startRun(95)
for _ = 1, 10 do
	ctx.run(0.6)
	ctx.finishLevel()
end
ctx.run(2)

--================================================================ (resume session) the decor cap really binds
-- No real maze position wants more than ~15 pieces inside the 24-stud radius, so the 26-piece cap never binds
-- in the walks above and a client that ignored it passed every suite (mutation G11). Force a small cap in
-- memory (the client reads Biomes.Budget live) and check it is honoured, then that it grows back.
do
	local saved = B.MaxDecorPieces
	local function piecesShown()
		local byId = {}
		for _, d in LOCAL:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Decor_" then
				local id = string.sub(d.Name, 7)
				byId[id] = (byId[id] or 0) + 1
			end
		end
		local n = 0
		for id, parts in byId do n += parts / #Biomes.Pieces[id].prims end
		return n
	end
	ctx.startRun(200)
	local g = Lib.grid(ctx.folder())
	local mid = g.world(2 * (g.cols // 2) + 1, 2 * (g.rows // 2) + 1)
	ctx.moveTo(mid)
	ctx.run(1.0)
	local free = piecesShown()
	print(string.format("== decor cap: %d pieces in the middle of L200 with the real cap (%d)", free, saved))
	truthy(free > 5, string.format("uncapped, the middle of L200 shows more than 5 pieces (%d)", free))
	B.MaxDecorPieces = 5
	ctx.startRun(200)
	ctx.moveTo(Lib.grid(ctx.folder()).world(2 * (g.cols // 2) + 1, 2 * (g.rows // 2) + 1))
	ctx.run(1.0)
	eq(piecesShown(), 5, "with MaxDecorPieces forced to 5, exactly 5 pieces are shown")
	B.MaxDecorPieces = saved
	ctx.startRun(200)
	ctx.moveTo(Lib.grid(ctx.folder()).world(2 * (g.cols // 2) + 1, 2 * (g.rows // 2) + 1))
	ctx.run(1.0)
	eq(piecesShown(), free, "and with the real cap back, the same spot shows all of them again")
end

print(string.format("== peak on any frame: %d parts (budget %d), %d decor parts, %d emitters (budget %d), %.1f particles/s (budget %d), %d lights (budget %d), %d hazards drawn (budget %d)",
	peak.parts, B.MaxLocalParts, peak.decor, peak.emitters, B.MaxEmitters, peak.rate, B.MaxEmitterRate, peak.lights, B.MaxMazeLights, peak.rings, B.MaxHazardsShown))
eq(over, 0, "no frame over any budget")
truthy(peak.decor <= B.MaxDecorPieces * B.MaxPrimsPerPiece, "decor never beyond MaxDecorPieces x MaxPrimsPerPiece parts")
T.finish(h)
