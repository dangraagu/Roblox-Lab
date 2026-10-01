-- Labyrinth Mariozo — the biomes, driven through the REAL client (src/client/Biome.client.luau).
-- Run: luau check_labyrintspill_biomes.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- The pure rules live in labyrint-spill/tests (Biomes, CellHazards, BreakRoom, Pacing specs). This
-- file checks the GLUE no unit test can see, on the real server's mazes:
--   §0 the numbers the eye-candy config mirrors from the server script are still the server's;
--   §1 the live look Biomes.Base claims is what the server really builds;
--   §2 in every biome and every seam between two: the SIGHT fields are untouched (Ambient 0, fog 45,
--      brightness, clock, atmosphere density/haze, torch range/brightness) and the HUES are the band's
--      blend at the live luma — and the budgets, measured;
--   §3 a level change GLIDES the grade (no hard cut);
--   §4 decor: the right pieces on the right walls, never glowing, never low, never in the way, and a
--      secret door dressed exactly like the plain wall it pretends to be — even when it sinks;
--   §5 inertness + leaks: nothing built is collidable/queryable/touchable, no remote fired or added,
--      no attribute written on anything the server built, no light in a maze;
--   §6 back in the lobby, everything the client tinted is back at its live value;
--   §7 (second review) no decor on the Lobby door's wall, in front of the free-break sign;
--   §8 (01.10) no critter there either: none lives in the start cell.
-- Headless limits: nothing renders, there is no physics. Whether it LOOKS right is on the Studio list.

local Lib = require("./check_labyrintspill_lib")
-- string requires must happen BEFORE boot: the harness replaces `require` with Roblox's rules
local MazeWalker = require("../labyrint-spill/tests/MazeWalker")
local T = Lib.counter("labyrintspill biomes")
local truthy, eq, near = T.truthy, T.eq, T.near

local ctx = Lib.boot({ accepted = 400, clients = Lib.CLIENTS_NO_SOUND })
local h = ctx.h
eq(#ctx.loadErrors, 0, "all 12 client scripts load (SoundClient left out, see the lib) (" .. table.concat(ctx.loadErrors, "; ") .. ")")

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local EnvBands = mod("EnvBands")
local Biomes = mod("Biomes")
local LightingPresets = mod("LightingPresets")
local L = ctx.Lighting
local rgb = Lib.rgb

--================================================================ §0 the server's own numbers

do
	local src = Lib.serverSource(ctx.bundle)
	local function num(pat)
		local v = string.match(src, pat)
		return tonumber(v)
	end
	eq(num("CellSize = (%d+)"), Biomes.Hazards.CellSize, "CONFIG.CellSize is what the hazard geometry assumes")
	eq(num("PlayerWalkSpeed = (%d+)"), Biomes.Hazards.WalkSpeed, "CONFIG.PlayerWalkSpeed is what the pacing assumes")
	eq(num("TorchRange = (%d+)"), Biomes.Base.locked.TorchRange, "CONFIG.TorchRange is the locked torch range")
	eq(num("MinRunSeconds = (%d+)"), Biomes.Rest.ServerMinRunSeconds, "CONFIG.Assist.MinRunSeconds is the free-break rule the door sign relies on")
	eq(num("INSTANCE_FOG = (%d+)"), 45, "the instances' fog distance is 45")
	eq(num("MonsterSpeedMax = (%d+)"), Biomes.Hazards.MonsterSpeedMax,
		"CONFIG.Curve.MonsterSpeedMax is the fastest monster the stagger radius is sized for (owner decision 30.09)")
	local warn = { string.match(src, "warn%s*=%s*{%s*Color = Color3.fromRGB%((%d+), (%d+), (%d+)%)") }
	local deadly = { string.match(src, "deadly%s*=%s*{%s*Color = Color3.fromRGB%((%d+), (%d+), (%d+)%)") }
	for c = 1, 3 do
		eq(tonumber(warn[c]), Biomes.Signals.trapWarn[c], "the trap WARN colour is the signal the grade keeps readable (" .. c .. ")")
		eq(tonumber(deadly[c]), Biomes.Signals.trapDeadly[c], "the trap DEADLY colour is the signal the grade keeps readable (" .. c .. ")")
	end
	local curve = string.match(src, "Curve = (%b{})")
	truthy(curve ~= nil, "the server's CONFIG.Curve block is found")
	local drift = {}
	for k, v in MazeWalker.CURVE do
		local sv = curve and tonumber(string.match(curve, k .. " = ([%d%.]+)"))
		if sv ~= v then table.insert(drift, k .. "=" .. tostring(sv) .. "/" .. tostring(v)) end
	end
	eq(#drift, 0, "tests/MazeWalker.CURVE (the pacing model) is the server's live curve (" .. table.concat(drift, ",") .. ")")
	-- (second review) the step-on palette the ring is kept away from is the server's own: the four secret-button
	-- colours in order, the guide dots, the coin, the gem and the exit pad
	local server = {}
	local pairBlock = string.match(src, "local PAIR_COLORS = (%b{})")
	truthy(pairBlock ~= nil, "the server's PAIR_COLORS block is found")
	for r, g, b in string.gmatch(pairBlock or "", "{%s*(%d+),%s*(%d+),%s*(%d+)%s*}") do
		table.insert(server, { tonumber(r), tonumber(g), tonumber(b) })
	end
	eq(#server, 4, "four secret-button colours on the server")
	-- the live builder is buildInstance (the old buildLevel above it is unused and has a red locked exit)
	local live = string.sub(src, (string.find(src, "local function buildInstance(inst)", 1, true) or 1))
	for _, name in { "GuideDot", "Coin", "Gem", "Exit" } do
		local at = string.find(live, 'Name = "' .. name .. '"', 1, true)
		local block = at and string.sub(live, at, (string.find(live, "})", at, true) or at))
		local r, g, b = string.match(block or "", "Color = Color3.fromRGB%((%d+), (%d+), (%d+)%)")
		truthy(r ~= nil, "the server's " .. name .. " colour is found")
		table.insert(server, { tonumber(r), tonumber(g), tonumber(b) })
	end
	local S = Biomes.StepOnColors or {}
	eq(#S, #server, "Biomes.StepOnColors lists every step-on colour the server builds")
	local off = {}
	for i, c in server do
		local m = S[i] and S[i].rgb
		if not (m and m[1] == c[1] and m[2] == c[2] and m[3] == c[3]) then
			table.insert(off, string.format("%d: server %s,%s,%s", i, tostring(c[1]), tostring(c[2]), tostring(c[3])))
		end
	end
	eq(#off, 0, "Biomes.StepOnColors mirrors the server's palette in order (" .. table.concat(off, "; ") .. ")")
end

--================================================================ §1 the live look

do
	local base = Biomes.Base.look
	local atmos = L:FindFirstChild("FxAtmosphere")
	local cc = L:FindFirstChild("FxColorCorrection")
	truthy(atmos ~= nil and cc ~= nil, "the server built the Maze preset's Atmosphere and ColorCorrection")
	for c = 1, 3 do
		eq(rgb(atmos.Color)[c], base.atmosColor[c], "Base.atmosColor is the server's Atmosphere colour (" .. c .. ")")
		eq(rgb(atmos.Decay)[c], base.atmosDecay[c], "Base.atmosDecay is the server's Atmosphere decay (" .. c .. ")")
		eq(rgb(cc.TintColor)[c], base.tint[c], "Base.tint is the server's colour grade (" .. c .. ")")
		eq(LightingPresets.MAZE.FogColor[c], base.fogColor[c], "Base.fogColor is LightingPresets.MAZE (" .. c .. ")")
		eq(LightingPresets.MAZE.OutdoorAmbient[c], base.outdoorAmbient[c], "Base.outdoorAmbient is LightingPresets.MAZE (" .. c .. ")")
	end
	near(atmos.Density, Biomes.Base.locked.AtmosphereDensity, 1e-9, "the atmosphere density the lock names is the server's")
	local torch = ctx.hrp:FindFirstChild("Torch")
	truthy(torch ~= nil, "the server handed the character its torch")
	for c = 1, 3 do
		eq(rgb(torch.Color)[c], base.torch[c], "Base.torch is the server's torch colour (" .. c .. ")")
	end
	eq(torch.Range, Biomes.Base.locked.TorchRange, "the torch range is the locked one")
	eq(torch.Brightness, Biomes.Base.locked.TorchBrightness, "the torch brightness is the locked one")
end

--================================================================ helpers

local function hueTarget(level)
	return Biomes.lookAt(EnvBands, level)
end
local function lookNow()
	local atmos = L:FindFirstChildOfClass("Atmosphere")
	local cc = L:FindFirstChildOfClass("ColorCorrectionEffect")
	local torch = ctx.hrp:FindFirstChild("Torch")
	return {
		fogColor = rgb(L.FogColor), outdoorAmbient = rgb(L.OutdoorAmbient), atmosColor = rgb(atmos.Color),
		atmosDecay = rgb(atmos.Decay), tint = rgb(cc.TintColor), torch = rgb(torch.Color),
	}
end
local function sightLocked(tag)
	local atmos = L:FindFirstChildOfClass("Atmosphere")
	local torch = ctx.hrp:FindFirstChild("Torch")
	local ok = rgb(L.Ambient)[1] == 0 and rgb(L.Ambient)[2] == 0 and rgb(L.Ambient)[3] == 0
		and L.FogEnd == 45 and L.FogStart == 0 and L.Brightness == 1 and L.ClockTime == 0
		and math.abs(atmos.Density - 0.35) < 1e-9 and math.abs(atmos.Haze - 1.4) < 1e-9
		and torch.Range == 28 and torch.Brightness == 2.5
	truthy(ok, tag .. ": every sight field is the live value (Ambient 0, fog 0..45, brightness 1, midnight, density 0.35, haze 1.4, torch 28 / 2.5)")
	if not ok then
		print(string.format("   Ambient %s FogEnd %s FogStart %s Brightness %s Clock %s Density %s Haze %s torch %s/%s",
			tostring(L.Ambient), L.FogEnd, L.FogStart, L.Brightness, L.ClockTime, atmos.Density, atmos.Haze, torch.Range, torch.Brightness))
	end
end

-- peak budgets over the whole file
local peak = { parts = 0, emitters = 0, rate = 0, lights = 0 }
local function sample()
	local c = Lib.census(h)
	peak.parts = math.max(peak.parts, c.parts)
	peak.emitters = math.max(peak.emitters, c.emitters)
	peak.rate = math.max(peak.rate, c.rate)
	peak.lights = math.max(peak.lights, c.lights)
	return c
end

--================================================================ §2 every band + every seam

print("== per biome (mid-band level) and per seam (a level inside the fade): hues + budgets")
print("   where                      level  parts  emitters (rate/s)  lights  decor pieces")
local B = Biomes.Bands
local stops = {}
for i, b in B do
	local nextFrom = if B[i + 1] then B[i + 1].from else b.from + 100
	table.insert(stops, { tag = b.emoji .. " " .. b.name, level = math.max(1, math.floor((math.max(1, b.from) + nextFrom) / 2)) })
	if B[i + 1] then
		local nb = B[i + 1]
		table.insert(stops, { tag = b.emoji .. " > " .. nb.emoji .. " seam", level = nb.from - math.ceil(nb.fade / 2) })
	end
end
for _, s in stops do
	ctx.startRun(s.level)
	ctx.run(2.5, 1 / 30, function() sample() end)
	sightLocked(s.tag .. " L" .. s.level)
	local want = hueTarget(s.level)
	local now = lookNow()
	local worst = 0
	for _, k in Biomes.LookKeys do
		for c = 1, 3 do
			worst = math.max(worst, math.abs(now[k][c] - want[k][c]))
		end
		local target = Biomes.luma(Biomes.Base.look[k])
		truthy(math.abs(Biomes.luma(now[k]) - target) <= math.max(0.6, target * 0.015) + 0.6,
			s.tag .. " " .. k .. " on screen keeps the live luma")
	end
	truthy(worst <= 1, string.format("%s: every hue on screen is the band's blend for L%d (worst %d/255)", s.tag, s.level, worst))
	local c = sample()
	local pieces = 0
	for _, d in c.all do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Decor_" then pieces += 1 end
	end
	print(string.format("   %-26s %5d  %5d  %d (%.1f)           %d       %d parts", s.tag, s.level, c.parts, c.emitters, c.rate, c.lights, pieces))
	eq(c.lights, 0, s.tag .. ": no light in a maze (a light would add sight)")
	truthy(c.emitters <= Biomes.Budget.MaxAirEmitters, s.tag .. ": at most two air emitters")
	truthy(c.parts <= Biomes.Budget.MaxLocalParts, s.tag .. ": within the part budget")
	truthy(pieces > 0, s.tag .. ": the walls around the start are dressed")
	-- the dungeon is the live game: its hues ARE the base values
	if s.level < B[2].from - B[2].fade then
		local diff = 0
		for _, k in Biomes.LookKeys do
			for ch = 1, 3 do
				diff += math.abs(now[k][ch] - Biomes.Base.look[k][ch])
			end
		end
		eq(diff, 0, "the dungeon (L" .. s.level .. ") shows exactly the live game's colours")
	end
end

--================================================================ §3 a level change glides

do
	-- jungle -> ice fade: L23 -> L24 moves the torch's blue channel by about a third of 87
	ctx.startRun(23)
	ctx.run(3)
	local fromLook = lookNow()
	local want = hueTarget(24)
	local seen = {}
	ctx.finishLevel()
	local f = ctx.folder()
	eq(f and h.workspace:FindFirstChild(f.Name) and ctx.plr:GetAttribute("MazeFolder") ~= nil, true, "finishing L23 advances the run")
	ctx.run(4, 1 / 30, function()
		table.insert(seen, lookNow().torch[3])
	end)
	local total = want.torch[3] - fromLook.torch[3]
	truthy(math.abs(total) >= 20, string.format("the step under test is a real change (torch blue %d -> %d)", fromLook.torch[3], want.torch[3]))
	local maxStep, monotone = 0, true
	local prev = fromLook.torch[3]
	for _, v in seen do
		maxStep = math.max(maxStep, math.abs(v - prev))
		if (v - prev) * total < -1 then monotone = false end
		prev = v
	end
	truthy(maxStep <= math.abs(total) * 0.25 + 1, string.format("no single write moves more than a quarter of the change (%d of %d)", maxStep, math.abs(total)))
	truthy(monotone, "the glide goes one way, no overshoot")
	near(seen[#seen], want.torch[3], 1, "and arrives at the new level's torch colour")
	sightLocked("during the glide")
end

--================================================================ §4 decor

local function partBottom(p)
	local cf, s = p.CFrame, p.Size
	local up = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
	return p.Position.Y - up
end

local function decorParts()
	local out = {}
	local f = h.workspace:FindFirstChild("LabyrintBiomeLocal")
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Decor_" then table.insert(out, d) end
	end
	return out
end

-- a signature of the decor around the player: piece id + position relative to the maze's floor, rounded
-- (every run builds its maze at a new 6000-stud offset, so absolute positions never repeat)
local function decorSignature()
	local items = {}
	local o = ctx.folder():FindFirstChild("Floor").Position
	for _, p in decorParts() do
		table.insert(items, string.format("%s@%.1f,%.1f,%.1f", p.Name, p.Position.X - o.X, p.Position.Y - o.Y, p.Position.Z - o.Z))
	end
	table.sort(items)
	return table.concat(items, ";"), #items
end

do
	local LEVEL = 38 -- ice cellar
	ctx.startRun(LEVEL)
	ctx.run(1.5)
	local f = ctx.folder()
	local g = Lib.grid(f)
	-- walk the player to a few cells and check every piece around them
	local badMat, badInert, badLow, badFar, badProtrude = 0, 0, 0, 0, 0
	local checked = 0
	local expectedMismatch = 0
	for _, cell in { { 0, 0 }, { 2, 1 }, { 3, 3 }, { 1, 4 }, { 4, 2 } } do
		local pos = g.world(2 * cell[1] + 1, 2 * cell[2] + 1)
		ctx.moveTo(pos)
		ctx.run(0.6)
		for _, p in decorParts() do
			checked += 1
			if p.Material.Name == "Neon" then badMat += 1 end
			if p.CanCollide or p.CanQuery or p.CanTouch or p.CastShadow or not p.Anchored then badInert += 1 end
			if partBottom(p) < g.origin.Y + 0.5 + 3 - 0.05 then badLow += 1 end
			local dx, dz = p.Position.X - pos.X, p.Position.Z - pos.Z
			if math.sqrt(dx * dx + dz * dz) > Biomes.Budget.DecorRadius + 6.5 then badFar += 1 end
		end
		-- what SHOULD be there: every open face of every wall within the radius, by the pure rule
		local want = {}
		for key, wall in g.walls do
			local fx, fy = string.match(key, "(%-?%d+),(%-?%d+)")
			fx, fy = tonumber(fx), tonumber(fy)
			local wp = wall.Position
			local d = math.sqrt((wp.X - pos.X) ^ 2 + (wp.Z - pos.Z) ^ 2)
			if d <= Biomes.Budget.DecorRadius then
				local faces = Biomes.openFaces(function(x, y) return g.walls[x .. "," .. y] ~= nil end, fx, fy, g.gCols, g.gRows)
				for _, face in faces do
					local pid = Biomes.decorFor(EnvBands, LEVEL, fx, fy, face)
					if pid then table.insert(want, { pid = pid, d = d }) end
				end
			end
		end
		table.sort(want, function(a, b) return a.d < b.d end)
		local wantCount = {}
		local nWant = math.min(#want, Biomes.Budget.MaxDecorPieces)
		for i = 1, #want do
			-- ties at the cut-off may go either way; count every piece up to the cut-off distance
			if i <= nWant or want[i].d <= want[nWant].d + 1e-6 then
				wantCount[want[i].pid] = (wantCount[want[i].pid] or 0) + 1
			end
		end
		local gotParts = {}
		for _, p in decorParts() do
			local pid = string.sub(p.Name, 7)
			gotParts[pid] = (gotParts[pid] or 0) + 1
		end
		local gotPieces = 0
		for pid, n in gotParts do
			local per = #Biomes.Pieces[pid].prims
			local pieces = n / per
			gotPieces += pieces
			if pieces ~= math.floor(pieces) or pieces > (wantCount[pid] or 0) then expectedMismatch += 1 end
		end
		if gotPieces ~= nWant then
			expectedMismatch += 1
			print(string.format("   at cell %d,%d: %d pieces shown, %d expected", cell[1], cell[2], gotPieces, nWant))
		end
	end
	truthy(checked > 20, "decor was measured on real pieces (" .. checked .. " parts)")
	eq(expectedMismatch, 0, "at every stop, exactly the pieces Biomes.decorFor names for the nearest open faces are shown")
	eq(badMat, 0, "no decor part glows (Neon)")
	eq(badInert, 0, "every decor part is anchored and non-collidable, non-queryable, non-touchable, shadowless")
	eq(badLow, 0, "no decor part reaches below 3 studs over the floor (secret-door bands and the floor stay clear)")
	eq(badFar, 0, "no decor sits outside the 24-stud radius (inside the torch's 28)")
end

-- A secret door is dressed exactly like a plain wall: the same level, the same spot, with every
-- secret door renamed to what it was before it got its button -> byte-identical decor.
do
	local LEVEL = 44
	local function secretSpot()
		local f = ctx.folder()
		local s = f:FindFirstChild("SecretWall")
		return s
	end
	ctx.startRun(LEVEL)
	local s = secretSpot()
	truthy(s ~= nil, "level " .. LEVEL .. " has a secret door")
	-- stand in the open cell next to it (kept as fine-grid coordinates: the same spot in every run)
	local g = Lib.grid(ctx.folder())
	local fx, fy = g.fine(s.Position)
	local sx, sy = fx, fy
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if g.walls[(fx + d[1]) .. "," .. (fy + d[2])] == nil then
			sx, sy = fx + d[1], fy + d[2]
			break
		end
	end
	local function spotNow() return Lib.grid(ctx.folder()).world(sx, sy) end
	ctx.moveTo(spotNow())
	ctx.run(1.5)
	local sigA, nA = decorSignature()
	ctx.toLobby()
	ctx.startRun(LEVEL)
	-- before the client's first frame in this run, every secret door becomes a plain "Wall"
	local renamed = 0
	for _, d in ctx.folder():GetChildren() do
		if d.Name == "SecretWall" then d.Name = "Wall"; renamed += 1 end
	end
	truthy(renamed >= 1, "the renaming control really renamed secret doors (" .. renamed .. ")")
	ctx.moveTo(spotNow())
	ctx.run(1.5)
	local sigB, nB = decorSignature()
	eq(sigA, sigB, string.format("secret doors and plain walls are dressed identically (%d pieces vs %d)", nA, nB))
	truthy(nA > 0, "there is decor around the secret door to compare (" .. nA .. " parts)")
end

-- (review fix) When a door's button is pressed, its dressing goes down with it and is GONE before the door is:
-- pieces that stand on the wall top (crystal spires, marble columns) reach higher above the wall's bottom than
-- the 26 studs a door sinks, and used to be left sticking 2.5-3 studs out of the floor where the door had been
-- (adversarial review: 21 parts in 10 of 16 levels; the old section here ran at an ice level, where no piece
-- reaches that high). Run at a spire level and a column level, on a door the pure rule really dresses so.
-- A standing piece's bottom is always 3+ studs over the floor (Biomes.validate), so a decor part with its
-- bottom below the floor's top can only be riding a door that has left its place.
do
	local src = Lib.serverSource(ctx.bundle)
	local WALL_H = tonumber(string.match(src, "WallHeight = (%d+)"))
	local sinkT = tonumber(string.match(src, "local drop = Vector3.new%(0, CONFIG.WallHeight %+ 2, 0%)%s*TweenService:Create%(doorPart, TweenInfo.new%(([%d%.]+), Enum.EasingStyle.Quad%)"))
	eq(WALL_H, 24, "the server's CONFIG.WallHeight is 24 (the geometry the tall pieces are measured against)")
	truthy(sinkT ~= nil, "the server's door-sink tween is found (" .. tostring(sinkT) .. " s, Quad)")
	-- Quad Out: the door's top reaches the floor when 26 * (1 - (1 - t/T)^2) = 24
	local topAtFloor = (sinkT or 0.7) * (1 - math.sqrt(2 / (WALL_H + 2)))
	local fade = tonumber(Biomes.Budget.DecorFadeSeconds) or math.huge
	truthy(fade + 2 / 30 < topAtFloor,
		string.format("the dressing fades out (%.2f s + 2 frames) before the server's door top reaches the floor (%.2f s)", fade, topAtFloor))
	local tallIds = {}
	for id, piece in Biomes.Pieces do
		for _, p in piece.prims do
			if p.at[2] + p.size[2] / 2 > WALL_H + 2 + 1e-9 then tallIds[id] = true end
		end
	end
	local function partTop(p)
		local cf, s = p.CFrame, p.Size
		return p.Position.Y + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
	end
	local covered = {}
	for _, want in { "spire", "column" } do
		-- the first level (of a few, per biome) with a door the pure rule dresses with `want`
		local found = nil
		for _, L in { 105, 120, 131, 140, 150, 250, 270, 296, 320, 340, 360, 380, 401 } do -- accepted = 400: up to 401
			if (want == "spire" and (L < 101 or (L >= 161 and L < 340))) or (want == "column" and (L < 241 or L >= 351)) then continue end
			ctx.startRun(L)
			if ctx.folder() == nil then continue end
			local gg = Lib.grid(ctx.folder())
			local function isW(x, y) return gg.walls[x .. "," .. y] ~= nil end
			for _, d in ctx.folder():GetChildren() do
				if d.Name == "SecretWall" then
					local fx, fy = gg.fine(d.Position)
					for _, face in Biomes.openFaces(isW, fx, fy, gg.gCols, gg.gRows) do
						if Biomes.decorFor(EnvBands, L, fx, fy, face) == want then found = { level = L, door = d, fx = fx, fy = fy } end
					end
				end
				if found then break end
			end
			if found then break end
		end
		truthy(found ~= nil, "a level with a secret door dressed with a " .. want .. " exists (" .. (found and ("L" .. found.level) or "none") .. ")")
		if found then
			covered[want] = found.level
			-- Two motions. "roblox": the check moves the door frame by frame the way Roblox's TweenService
			-- interpolates the server's tween (Quad Out over sinkT, 26 studs), which is what a client sees as the
			-- tween replicates. "button": the real server's button; this emulator's Tween does not interpolate
			-- (emu/services.luau: it jumps to the goal after TweenInfo.Time), which is also exactly what a client
			-- sees when it only notices the door once it is down (a hitch, or arriving late).
			for _, motion in { "roblox", "button" } do
				ctx.startRun(found.level)
				local gg = Lib.grid(ctx.folder())
				local door = gg.walls[found.fx .. "," .. found.fy]
				local stand
				for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					if gg.walls[(found.fx + dd[1]) .. "," .. (found.fy + dd[2])] == nil then stand = gg.world(found.fx + dd[1], found.fy + dd[2]); break end
				end
				ctx.moveTo(stand)
				ctx.run(1.5)
				local floor = ctx.folder():FindFirstChild("Floor")
				local floorTop = floor.Position.Y + floor.Size.Y / 2
				local tag = string.format("L%d (%s)", found.level, motion)
				-- before: the door wears its tall piece
				local before, beforeT, tallShown = {}, {}, 0
				for _, p in decorParts() do
					local dx, dz = p.Position.X - door.Position.X, p.Position.Z - door.Position.Z
					if math.abs(dx) <= 5.8 and math.abs(dz) <= 5.8 then
						before[p] = p.Position.Y
						beforeT[p] = p.Transparency
						if string.sub(p.Name, 7) == want then tallShown += 1 end
					end
				end
				truthy(tallShown > 0, string.format("%s: before it sinks, the door wears its %s (%d parts)", tag, want, tallShown))
				local startPos = door.Position
				if motion == "button" then
					-- press every button (each sinks its own door)
					for _, d in ctx.folder():GetChildren() do
						if d.Name == "SecretButton" then d.Touched:Fire(ctx.hrp) end
					end
				end
				local T = sinkT or 0.7
				local followed, pokeFrames, visibleAtFloor, pokeWorst, fullHalfDown = 0, 0, 0, 0, 0
				local doorAtFloorAt = nil
				local dt = 1 / 30
				for i = 1, math.floor(2.5 / dt) do
					if motion == "roblox" then
						local u = math.min(1, i * dt / T)
						door.Position = startPos - Vector3.new(0, (WALL_H + 2) * (1 - (1 - u) * (1 - u)), 0)
					end
					ctx.frame(dt)
					local doorTop = door.Position.Y + door.Size.Y / 2
					if doorTop <= floorTop and doorAtFloorAt == nil then doorAtFloorAt = i * dt end
					for _, p in decorParts() do
						local shown = p.Transparency < 0.999
						local y0 = before[p]
						if shown and y0 and y0 - p.Position.Y >= 5 then followed += 1 end
						-- half-way down and still at full opacity = no fade (a piece that pops out instead)
						if shown and y0 and y0 - p.Position.Y >= (WALL_H + 2) / 2 and doorTop > floorTop
							and math.abs(p.Transparency - beforeT[p]) < 1e-6 then fullHalfDown += 1 end
						if partBottom(p) < floorTop - 0.05 then
							-- riding a door that has left its place (a standing piece's bottom is 3+ studs up)
							if shown and doorTop <= floorTop then visibleAtFloor += 1 end
							if shown and doorTop <= floorTop and partTop(p) > floorTop + 0.05 then
								pokeFrames += 1
								pokeWorst = math.max(pokeWorst, partTop(p) - floorTop)
							end
						end
					end
				end
				truthy(doorAtFloorAt ~= nil, string.format("%s: the door went into the floor (its top passed the floor at %.2f s)", tag, doorAtFloorAt or -1))
				if motion == "roblox" then
					truthy(followed > 0, string.format("%s: the dressing rides down with the door while it fades (%d part-frames 5+ studs lower, still shown)", tag, followed))
					eq(fullHalfDown, 0, tag .. ": half-way down, none of it is still at full opacity (it fades; it does not pop out at the floor)")
				end
				eq(visibleAtFloor, 0, tag .. ": once the door's top is at the floor, none of its dressing is still shown")
				eq(pokeFrames, 0, string.format("%s: no %s or any other piece sticks out of the floor where the door was (worst %.2f studs)", tag, want, pokeWorst))
				-- walk away (a new decor selection) and back: nothing is ever put back on a sunk door
				ctx.moveTo(gg.world(1, 1))
				ctx.run(0.5)
				ctx.moveTo(stand)
				ctx.run(1.0)
				local onSunk = 0
				for _, p in decorParts() do
					if partBottom(p) < floorTop - 0.05 then onSunk += 1 end
				end
				eq(onSunk, 0, tag .. ": walking away and back puts no decor on a sunk door (released, not kept at transparency 1)")
				-- a sunk door must not take up the decor budget either: with the cap forced to 2 (the client reads
				-- Biomes.Budget live), the 2 nearest STANDING dressed faces are shown, not a sunk door's slots.
				-- (2026-10-01) critters share the cap (a critter takes a decor slot), so the cap is forced to 2 wall
				-- pieces PLUS the critters this level wants; the wall pieces are what this assertion is about.
				local savedCap = Biomes.Budget.MaxDecorPieces
				local critterSlots = 0
				for _, n in Biomes.crittersAt(EnvBands, found.level) do critterSlots += n end
				Biomes.Budget.MaxDecorPieces = 2 + critterSlots
				ctx.moveTo(gg.world(1, 1))
				ctx.run(0.5)
				ctx.moveTo(stand)
				ctx.run(1.0)
				local shownPieces = 0
				for _, p in decorParts() do
					if p.Transparency < 0.999 then shownPieces += 1 / #Biomes.Pieces[string.sub(p.Name, 7)].prims end
				end
				Biomes.Budget.MaxDecorPieces = savedCap
				eq(math.floor(shownPieces + 0.5), 2, tag .. ": beside the sunk door, with the cap forced to 2, two pieces are shown (a sunk door takes no slot)")
			end
		end
	end
	print(string.format("   sinking doors checked at a spire level (L%s) and a column level (L%s)", tostring(covered.spire), tostring(covered.column)))
end

--================================================================ §5 inertness + leaks

do
	ctx.startRun(130)
	ctx.run(1)
	-- snapshot the server's world: remote names, attributes on everything it built
	local remotes = {}
	for _, d in h.ReplicatedStorage:GetDescendants() do
		if d.ClassName == "RemoteEvent" or d.ClassName == "RemoteFunction" then table.insert(remotes, d:GetFullName()) end
	end
	table.sort(remotes)
	local calls = 0
	for _, d in h.ReplicatedStorage:GetDescendants() do
		if d.ClassName == "RemoteEvent" then
			d.OnServerEvent:Connect(function() calls += 1 end)
		end
	end
	local function attrSnapshot()
		local out = {}
		local function walk(n)
			for _, c in n:GetChildren() do
				if c.Name ~= "LabyrintBiomeLocal" and c.Name ~= "LabyrintBreakRoom" then
					local ok, attrs = pcall(function() return c:GetAttributes() end)
					if ok and attrs then
						for k, v in attrs do table.insert(out, c:GetFullName() .. "." .. k .. "=" .. tostring(v)) end
					end
					walk(c)
				end
			end
		end
		walk(h.workspace)
		walk(h.game:GetService("Players"))
		table.sort(out)
		return table.concat(out, "\n")
	end
	local before = attrSnapshot()
	-- walk around the level for a while: decor, air, hazards, cards all run
	local g = Lib.grid(ctx.folder())
	for i = 0, 8 do
		ctx.moveTo(g.world(2 * (i % 5) + 1, 2 * ((i * 2) % 5) + 1))
		ctx.run(0.8)
	end
	eq(calls, 0, "the biome clients never fire a remote at the server")
	local after = {}
	for _, d in h.ReplicatedStorage:GetDescendants() do
		if d.ClassName == "RemoteEvent" or d.ClassName == "RemoteFunction" then table.insert(after, d:GetFullName()) end
	end
	table.sort(after)
	eq(table.concat(after, ","), table.concat(remotes, ","), "and never add one")
	eq(attrSnapshot(), before, "no attribute written on anything the server built, or on the player")
	local bad, parts = 0, 0
	for _, n in { "LabyrintBiomeLocal", "LabyrintBreakRoom" } do
		for _, d in h.workspace:FindFirstChild(n):GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow or not d.Anchored then bad += 1 end
			end
		end
	end
	truthy(parts > 0, "the local folders hold parts to check (" .. parts .. ")")
	eq(bad, 0, "every local part is anchored, non-collidable, non-queryable, non-touchable, shadowless")
	eq(Lib.census(h).lights, 0, "no light anywhere in a maze from this work")
	local room = Lib.census(h, { "LabyrintBreakRoom" })
	eq(room.lights, 0, "the lobby campfire's light is off while the player is in a maze")
	eq(room.emitters, 0, "and its fire is out")
	-- no character CFrame writes (SPAWN-ORDER.md): the clients only push velocity on a knock
	for _, key in { "client/Biome.client", "client/RestClient.client" } do
		local src = ctx.bundle[key].source
		truthy(string.find(src, "PivotTo", 1, true) == nil and string.find(src, "rootPart.CFrame", 1, true) == nil
			and string.find(src, "hrp.CFrame", 1, true) == nil, key .. " never moves the character by CFrame")
		truthy(string.find(src, "FireServer", 1, true) == nil and string.find(src, "InvokeServer", 1, true) == nil, key .. " has no remote call at all")
		truthy(string.find(src, "SetAttribute", 1, true) == nil, key .. " sets no attribute anywhere")
	end
end

--================================================================ §6 the lobby restores

do
	ctx.startRun(75) -- the forge: the strongest grade
	ctx.run(2)
	ctx.toLobby()
	ctx.run(2)
	local atmos = L:FindFirstChildOfClass("Atmosphere")
	local cc = L:FindFirstChildOfClass("ColorCorrectionEffect")
	local torch = ctx.hrp:FindFirstChild("Torch")
	local base = Biomes.Base.look
	local off = 0
	for c = 1, 3 do
		off += math.abs(rgb(atmos.Color)[c] - base.atmosColor[c]) + math.abs(rgb(atmos.Decay)[c] - base.atmosDecay[c])
			+ math.abs(rgb(cc.TintColor)[c] - base.tint[c]) + math.abs(rgb(torch.Color)[c] - base.torch[c])
	end
	eq(off, 0, "in the lobby the atmosphere, the grade and the torch are back at their live values")
	local c = Lib.census(h)
	eq(c.emitters, 0, "no biome particles in the lobby")
	local decor = #decorParts()
	eq(decor, 0, "no decor left behind in the lobby")
	local ring = 0
	for _, d in h.workspace:FindFirstChild("LabyrintBiomeLocal"):GetDescendants() do
		if d.Name == "HazardRing" then ring += 1 end
	end
	eq(ring, 0, "no hazard drawn in the lobby")
	local room = Lib.census(h, { "LabyrintBreakRoom" })
	eq(room.lights, 1, "back in the lobby, the campfire burns again (its one light)")
	eq(room.emitters, 2, "with flames and smoke")
	near(L.FogEnd, 520, 1, "and LightingClient's own lobby fog is untouched by the biome layer")
end

--================================================================ §7 (second review) the Lobby door's wall stays clear

-- Every level starts beside the server's 🚪 Lobby door, on the start cell's back wall, and for its first seconds
-- RestClient's free-break sign hangs in front of it ("Need a break? Walk out now"). The review found decor on that
-- wall face standing in front of the sign's words (a sconce at L2 and L5, glass crystals at L103 and L108) and grates
-- sinking into the top of the door (L50, L55); L3 and L51 are controls where nothing was there. Measured through the
-- real server and client, standing at the start: decor parts between the sign and the start cell that overlap the
-- sign's 9 x 2.2-stud face, and decor parts inside the door's slab.
do
	local inFront, inDoor = {}, {}
	for _, L in { 2, 5, 103, 108, 50, 55, 3, 51 } do
		ctx.startRun(L)
		ctx.run(1.2)
		local door = ctx.folder():FindFirstChild("LobbyDoor")
		local sign = h.workspace:FindFirstChild("LabyrintBreakRoom") and h.workspace.LabyrintBreakRoom:FindFirstChild("BreakSign")
		truthy(door ~= nil and sign ~= nil and sign.Adornee == door, "L" .. L .. ": the free-break sign hangs on this run's Lobby door")
		local dp, ds = door.Position, door.Size
		local signY = dp.Y + (sign and sign.StudsOffset.Y or 7)
		local nFront, nDoor = 0, 0
		for _, p in decorParts() do
			local pp, hs = p.Position, p.Size / 2
			local r = math.max(hs.X, hs.Y, hs.Z) -- a generous half-extent whatever the part's rotation
			-- in front of the sign: nearer the start cell than the sign's plane, overlapping its face
			if pp.Z + r > dp.Z and pp.Z < dp.Z + 2 and math.abs(pp.X - dp.X) < 4.5 + r and math.abs(pp.Y - signY) < 1.1 + r then
				nFront += 1
			end
			-- inside the door slab
			if math.abs(pp.X - dp.X) < ds.X / 2 + r and math.abs(pp.Y - dp.Y) < ds.Y / 2 + r and math.abs(pp.Z - dp.Z) < ds.Z / 2 + r then
				nDoor += 1
			end
		end
		inFront[L], inDoor[L] = nFront, nDoor
		print(string.format("   L%d: %d decor parts in front of the sign, %d in the door slab", L, nFront, nDoor))
	end
	for _, L in { 2, 5, 103, 108, 50, 55, 3, 51 } do
		eq(inFront[L], 0, "L" .. L .. ": no decor stands in front of the free-break sign")
		eq(inDoor[L], 0, "L" .. L .. ": no decor sits inside the Lobby door")
	end
	ctx.toLobby()
end

--================================================================ §8 (01.10) and no critter in front of it either

-- The critters added on 01.10 (Biomes.Critters) are client-built dressing too, and their first version could make
-- its home in the start cell once the player had walked out of it: a crypt spider then climbed the Lobby door's wall
-- straight through the door slab and the free-break sign. Found by the pass-1 re-run on 01.10 (a probe over
-- L150-245: a spider in front of the sign while it was up on 28 of 96 levels, nearly all on the walk below). The
-- walk a player makes when they think about the sign: 2 s out along the route to the exit, then back toward the
-- door, every frame of the sign's window (Biomes.Rest.FreeBreakSeconds, on the level clock; the sign itself can go
-- early on a slow machine, RestClient also reads wall time). Counted: critter parts in §7's box in front of the sign,
-- inside the door slab, and anywhere in the start cell. Exposure, so a 0 means something: the sign is up, and critters
-- are on show around the player, on these walks.
do
	local LOCAL = h.workspace:FindFirstChild("LabyrintBiomeLocal")
	local function route(g, from, to)
		local key = function(x, y) return x .. "," .. y end
		local prev, q, head = { [key(from[1], from[2])] = false }, { from }, 1
		while head <= #q do
			local cur = q[head]; head += 1
			if cur[1] == to[1] and cur[2] == to[2] then break end
			for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, ny = cur[1] + dd[1], cur[2] + dd[2]
				if nx >= 0 and ny >= 0 and nx < g.gCols and ny < g.gRows and not g.walls[key(nx, ny)] and prev[key(nx, ny)] == nil then
					prev[key(nx, ny)] = cur
					table.insert(q, { nx, ny })
				end
			end
		end
		local path, cur = {}, to
		while cur do table.insert(path, 1, cur); cur = prev[key(cur[1], cur[2])] end
		return path
	end
	local WINDOW = Biomes.Rest.FreeBreakSeconds
	local front, slab, inStart, signFrames, critterFrames, frames = 0, 0, 0, 0, 0, 0
	local levelsFront = {}
	for L = 161, 200 do -- the Haunted Crypt: spiders climb walls there
		ctx.startRun(L)
		local f = ctx.folder()
		local g = Lib.grid(f)
		local door = f:FindFirstChild("LobbyDoor")
		local dp, ds = door.Position, door.Size
		local signY = dp.Y + 7
		local sx, sz = g.world(1, 1).X, g.world(1, 1).Z
		local pts = {}
		for _, c in route(g, { 1, 1 }, { g.fine(f:FindFirstChild("Exit").Position) }) do table.insert(pts, g.world(c[1], c[2])) end
		local function posAt(dist)
			local i = math.floor(dist / g.S) + 1
			if i >= #pts then return pts[#pts] end
			return pts[i] + (pts[i + 1] - pts[i]) * ((dist - (i - 1) * g.S) / g.S)
		end
		local t0, t = ctx.clock, 0
		while t < WINDOW do
			ctx.moveTo(posAt(if t < 2 then 16 * t else math.max(0, 32 - 16 * (t - 2))))
			ctx.frame(1 / 30)
			t = ctx.clock - t0
			frames += 1
			if h.workspace.LabyrintBreakRoom:FindFirstChild("BreakSign") then signFrames += 1 end
			local any = false
			for _, d in LOCAL:GetDescendants() do
				if d:IsA("BasePart") and string.sub(d.Name, 1, 8) == "Critter_" then
					any = true
					local pp, hs = d.Position, d.Size / 2
					local r = math.max(hs.X, hs.Y, hs.Z)
					if pp.Z + r > dp.Z and pp.Z < dp.Z + 2 and math.abs(pp.X - dp.X) < 4.5 + r and math.abs(pp.Y - signY) < 1.1 + r then
						front += 1
						levelsFront[L] = true
					end
					if math.abs(pp.X - dp.X) < ds.X / 2 + r and math.abs(pp.Y - dp.Y) < ds.Y / 2 + r and math.abs(pp.Z - dp.Z) < ds.Z / 2 + r then
						slab += 1
					end
					if math.abs(pp.X - sx) < g.S / 2 and math.abs(pp.Z - sz) < g.S / 2 then inStart += 1 end
				end
			end
			if any then critterFrames += 1 end
		end
	end
	local nl = 0
	for _ in levelsFront do nl += 1 end
	print(string.format("   §8 L161-200, out and back in the sign's %.0f s: %d frames (sign up in %d, critters on show in %d); critter part-frames: %d in front of the sign (%d levels), %d in the door slab, %d in the start cell",
		WINDOW, frames, signFrames, critterFrames, front, nl, slab, inStart))
	truthy(signFrames > frames / 2, "§8 the sign is up for most of these walks")
	truthy(critterFrames > frames / 2, "§8 critters are on show around the player for most of these walks")
	eq(front, 0, "§8 no critter stands in front of the free-break sign (part-frames)")
	eq(slab, 0, "§8 no critter is inside the Lobby door (part-frames)")
	eq(inStart, 0, "§8 no critter lives in the start cell, the Lobby door's cell (part-frames)")
	ctx.toLobby()
end

print("")
print(string.format("== peak over the whole run: %d local parts (budget %d), %d emitters (budget %d), %.1f particles/s (budget %d), %d lights in a maze (budget %d)",
	peak.parts, Biomes.Budget.MaxLocalParts, peak.emitters, Biomes.Budget.MaxEmitters, peak.rate, Biomes.Budget.MaxEmitterRate,
	peak.lights, Biomes.Budget.MaxMazeLights))
truthy(peak.parts <= Biomes.Budget.MaxLocalParts, "peak parts within budget")
truthy(peak.emitters <= Biomes.Budget.MaxEmitters, "peak emitters within budget")
truthy(peak.rate <= Biomes.Budget.MaxEmitterRate, "peak particle rate within budget")
T.finish(h)
