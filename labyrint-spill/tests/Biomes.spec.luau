-- Spec for Biomes: the labyrinth's environment bands, by level. Run: luau tests/Biomes.spec.luau
--
-- What this game cannot afford to get wrong, and what every assertion below pins:
--   * DARKNESS IS THE MECHANIC. A biome may shift HUES, never how far you can see: every colour a
--     biome writes keeps the luma (brightness) of the live value, the fields that decide sight
--     (Ambient, fog distance, brightness, atmosphere density, torch range) are not in a biome at
--     all, and the first biome IS the live game's look, number for number.
--   * The trap's yellow warning and orange deadly phase are the survival signal. Under every
--     biome's colour grade they must still read as two different colours.
--   * The theme shop sells wall colours. A biome never recolours a wall; it adds decor pieces.
--   * Decor must not leak: its placement is a pure function of the wall's grid position, the face
--     and the level — never of what kind of wall it is (a secret door gets exactly what a plain
--     wall at that spot would get) — and it never glows (in this maze, glow means "interactive").
--   * Bands are named by level and blend over the levels before a boundary; never a hard cut.
local EnvBands = require("../src/shared/EnvBands")
local Biomes = require("../src/shared/Biomes")
local LightingPresets = require("../src/shared/LightingPresets")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Bands = Biomes.Bands
local LOOK_KEYS = Biomes.LookKeys

--================================================================ the table itself

do
	local ok, err = EnvBands.validate(Bands)
	truthy(ok, "the band table is a valid EnvBands table (" .. tostring(err) .. ")")
	local ok2, err2 = Biomes.validate(EnvBands)
	truthy(ok2, "Biomes.validate accepts the shipped config (" .. tostring(err2) .. ")")
end
truthy(#Bands >= 7, "at least seven biomes (the owner's brief lists seven)")
eq(Bands[1].id, "dungeon", "the game starts in the stone dungeon")
eq(Bands[1].from, 0, "the first band covers level 1")
do
	local seenIds, seenEmoji = {}, {}
	for i, b in Bands do
		truthy(type(b.name) == "string" and #b.name > 0, "band " .. i .. " has a display name")
		truthy(type(b.emoji) == "string" and #b.emoji > 0, "band " .. i .. " has an emoji")
		truthy(not seenEmoji[b.emoji], "band " .. i .. " has its own emoji (the brag must tell bands apart)")
		seenEmoji[b.emoji] = true
		seenIds[b.id] = true
		if i > 1 then
			truthy(b.fade >= 2, "band " .. b.id .. " fades in over at least two levels (no hard cut)")
			truthy(b.from == math.floor(b.from), "band " .. b.id .. " starts at a whole level")
		end
	end
	-- the gem currency's emoji must not be a band's emoji: "💎 170" on a board would read as gems
	truthy(not seenEmoji["💎"], "no band uses the gem emoji")
end

--================================================================ darkness is the mechanic

-- The first band is the live game: exactly the values LightingPresets.MAZE / Fx Maze / the server's torch
-- have always had. A biome layer that changed level 1 would be a difficulty change, not polish.
do
	local base = Biomes.Base.look
	eq(base.fogColor[1], LightingPresets.MAZE.FogColor[1], "base fog colour R is the live MAZE value")
	eq(base.fogColor[3], LightingPresets.MAZE.FogColor[3], "base fog colour B is the live MAZE value")
	eq(base.outdoorAmbient[2], LightingPresets.MAZE.OutdoorAmbient[2], "base outdoor ambient is the live MAZE value")
	for _, k in LOOK_KEYS do
		for c = 1, 3 do
			eq(Bands[1].look[k][c], base[k][c], "band 1 " .. k .. "[" .. c .. "] equals the live value")
		end
	end
	eq(Biomes.Base.locked.TorchRange, 28, "the torch range stays the server's CONFIG.TorchRange")
	eq(Biomes.Base.locked.TorchBrightness, 2.5, "the torch brightness stays the server's value")
	eq(Biomes.Base.locked.AtmosphereDensity, LightingPresets.MAZE.AtmosphereDensity, "atmosphere density is locked")
	eq(Biomes.Base.locked.AtmosphereHaze, LightingPresets.MAZE.AtmosphereHaze, "atmosphere haze is locked")
end

for i, b in Bands do
	local n = 0
	for k in b.look do
		n += 1
		truthy(table.find(LOOK_KEYS, k) ~= nil, "band " .. b.id .. " writes only hue fields (found " .. tostring(k) .. ")")
	end
	eq(n, #LOOK_KEYS, "band " .. b.id .. " defines every hue field")
	for _, k in LOOK_KEYS do
		local c = b.look[k]
		local target = Biomes.luma(Biomes.Base.look[k])
		local tol = math.max(0.6, target * 0.015)
		truthy(math.abs(Biomes.luma(c) - target) <= tol,
			string.format("band %s %s keeps the live luma (%.2f vs %.2f)", b.id, k, Biomes.luma(c), target))
	end
	-- the colour grade stays mild: no channel attenuated by more than 24 %
	local t = b.look.tint
	truthy(math.min(t[1], t[2], t[3]) / math.max(t[1], t[2], t[3]) >= 0.76, "band " .. b.id .. " tint is a mild grade")
	local tc = b.look.torch
	truthy(math.min(tc[1], tc[2], tc[3]) / math.max(tc[1], tc[2], tc[3]) >= 0.6, "band " .. b.id .. " torch stays near-white")
	-- the survival signal survives the grade: warn yellow and deadly orange stay two colours
	local warnGR, deadlyGR = Biomes.signalGreenRatio(Biomes.Signals.trapWarn, t), Biomes.signalGreenRatio(Biomes.Signals.trapDeadly, t)
	truthy(warnGR >= 0.62, string.format("band %s: the yellow warning still reads yellow (G/R %.2f)", b.id, warnGR))
	truthy(deadlyGR <= 0.48, string.format("band %s: the deadly lava still reads orange (G/R %.2f)", b.id, deadlyGR))
	truthy(warnGR - deadlyGR >= 0.3, "band " .. b.id .. ": warning and deadly stay far apart")
end

-- (review fix) the falling-hazard ring has its OWN colour. Glowing yellow on this maze's floor has always meant
-- "this floor kills you in a moment" (the trap's WARNING phase); a ring in that same yellow that only knocks
-- you down teaches players that yellow is survivable, and the next yellow they shrug at is lava. So the ring is
-- cool (blue) under every grade, where both trap phases are warm: blue/red ratio >= 1.5, and at least 1.0
-- above either trap phase's.
do
	local ring = Biomes.Hazards.RingColor
	truthy(type(ring) == "table" and #ring == 3, "Biomes.Hazards.RingColor is an RGB triple")
	if type(ring) == "table" and #ring == 3 then
		truthy(ring[3] > ring[1] and ring[3] > ring[2], "the ring is blue (its dominant channel)")
		eq(Biomes.Hazards.RingWord, "blue", "and the words on screen call it blue")
		for _, b in Bands do
			local t = b.look.tint
			local rBR = Biomes.signalBlueRatio(ring, t)
			local tBR = math.max(Biomes.signalBlueRatio(Biomes.Signals.trapWarn, t), Biomes.signalBlueRatio(Biomes.Signals.trapDeadly, t))
			truthy(rBR >= 1.5, string.format("band %s: the ring reads blue through the grade (B/R %.2f)", b.id, rBR))
			truthy(rBR - tBR >= 1.0, string.format("band %s: far from both trap phases (B/R %.2f vs %.2f)", b.id, rBR, tBR))
		end
	end
	for kind in Biomes.Hazards.Kinds do
		local bn, intro = Biomes.hazardBanner(kind), Biomes.hazardIntro(kind)
		truthy(string.find(bn, Biomes.Hazards.Kinds[kind].label, 1, true) ~= nil and string.find(bn, "blue ring", 1, true) ~= nil,
			"the " .. kind .. " banner names the hazard and the blue ring: " .. bn)
		truthy(string.find(intro, Biomes.Hazards.Kinds[kind].label, 1, true) ~= nil and string.find(intro, "blue ring", 1, true) ~= nil,
			"the " .. kind .. " introduction names the hazard and the blue ring: " .. intro)
		truthy(string.find(string.lower(bn .. intro), "yellow", 1, true) == nil, "no text calls the hazard ring yellow any more (" .. kind .. ")")
	end
	local function withRing(c)
		local saved = Biomes.Hazards.RingColor
		Biomes.Hazards.RingColor = c
		local ok = Biomes.validate(EnvBands)
		Biomes.Hazards.RingColor = saved
		return ok
	end
	eq(withRing(Biomes.Signals.trapWarn), false, "a ring in the trap's warning yellow is rejected (the shipped look before the review)")
	eq(withRing(Biomes.Signals.trapDeadly), false, "a ring in the trap's deadly orange is rejected")
	eq(withRing({ 255, 80, 40 }), false, "a warm red ring is rejected")
	eq(withRing({ 150, 150, 150 }), false, "a grey ring is rejected (not clearly cool)")
	eq(withRing({ 0, 0, 0 }), false, "a black ring is rejected (no division by zero lets it through)")
	eq(withRing(nil), false, "a missing ring colour is rejected")
end

-- a blend between two luma-matched colours is luma-matched too (luma is linear), checked anyway
for L = 1, 520 do
	local look = Biomes.lookAt(EnvBands, L)
	for _, k in LOOK_KEYS do
		local target = Biomes.luma(Biomes.Base.look[k])
		local tol = math.max(0.6, target * 0.015)
		if math.abs(Biomes.luma(look[k]) - target) > tol then
			truthy(false, "blended look at level " .. L .. " keeps the luma of " .. k)
		end
	end
end
passed += 1

--================================================================ lookup + blending

eq(Biomes.bandIndex(EnvBands, 1), 1, "level 1 is the dungeon")
for i = 2, #Bands do
	eq(Biomes.bandIndex(EnvBands, Bands[i].from), i, "level " .. Bands[i].from .. " starts band " .. Bands[i].id)
	eq(Biomes.bandIndex(EnvBands, Bands[i].from - 1), i - 1, "the level before it is still " .. Bands[i - 1].id)
end
eq(Biomes.bandIndex(EnvBands, 100000), #Bands, "any level past the last boundary is the last band")
eq(Biomes.bandIndex(EnvBands, 0/0), 1, "a NaN level lands in a band")

-- the NAMED band decides the hazard, the card and the emoji; the blend only colours
for i, b in Bands do
	eq(Biomes.hazardKindAt(EnvBands, b.from), b.hazard, "band " .. b.id .. " hazard kind at its first level")
end
eq(Biomes.hazardKindAt(EnvBands, 1), nil, "no hazard in the dungeon")
eq(Biomes.hazardKindAt(EnvBands, Bands[2].from), nil, "no hazard in the second band either (players are still learning traps)")

-- never a hard cut: from level to level, no hue channel moves more than it has to over its fade
do
	local worst = 0
	for L = 1, 520 do
		local a, b = Biomes.lookAt(EnvBands, L), Biomes.lookAt(EnvBands, L + 1)
		for _, k in LOOK_KEYS do
			for c = 1, 3 do
				worst = math.max(worst, math.abs(a[k][c] - b[k][c]))
			end
		end
	end
	-- the largest single-channel difference between two bands is ~60 (torch blue); spread over >= 2
	-- levels with a smoothstep, one level may move at most ~0.75 of it
	truthy(worst < 60, string.format("one level never jumps a whole band's colour change (worst %.1f)", worst))
end
-- a blended level shows both bands in the look
do
	local b2 = Bands[2]
	local mid = b2.from - 1
	local w = Biomes.weightsAt(EnvBands, mid)
	truthy((w[2] or 0) > 0 and (w[1] or 0) > 0, "the level before a boundary already blends the next band in")
end

--================================================================ decor: no leak, no glow

-- signature: (EnvBands, level, fx, fy, face). There is nothing to pass that says "secret".
do
	local a = Biomes.decorFor(EnvBands, 40, 10, 7, 2)
	local b = Biomes.decorFor(EnvBands, 40, 10, 7, 2)
	eq(a, b, "decor placement is deterministic")
	local different = 0
	for L = 30, 40 do
		if Biomes.decorFor(EnvBands, L, 10, 7, 2) ~= Biomes.decorFor(EnvBands, L + 1, 10, 7, 2) then different += 1 end
	end
	truthy(different > 0, "the same wall spot is dressed differently on different levels")
end
do
	-- density: roughly the band's share of faces carries a piece
	local n, hits, unknown = 0, 0, 0
	local kinds = {}
	for fx = 0, 60 do
		for fy = 0, 60 do
			for face = 1, 4 do
				n += 1
				local p = Biomes.decorFor(EnvBands, 60, fx, fy, face)
				if p then
					hits += 1
					kinds[p] = true
					if Biomes.Pieces[p] == nil then unknown += 1 end
				end
			end
		end
	end
	eq(unknown, 0, "decorFor only ever returns pieces that exist")
	local share = hits / n
	local band = Bands[Biomes.bandIndex(EnvBands, 60)]
	truthy(math.abs(share - band.decor.density) < 0.05, string.format("decor share %.3f is near the band density %.2f", share, band.decor.density))
	local count = 0
	for _ in kinds do count += 1 end
	truthy(count >= 3, "a band dresses its walls with at least three different pieces")
end
do
	-- every band's kit only names pieces that exist
	for _, b in Bands do
		for _, entry in b.decor.kit do
			truthy(Biomes.Pieces[entry[1]] ~= nil, "band " .. b.id .. " kit piece " .. tostring(entry[1]) .. " exists")
			truthy(entry[2] > 0, "kit weight is positive")
		end
	end
end

-- pieces: geometry rules, in face-local studs (u along the face, v up from the wall's bottom,
-- w out of the face into the corridor)
local ALLOWED_MATERIALS = Biomes.DecorMaterials
for id, piece in Biomes.Pieces do
	truthy(#piece.prims >= 1 and #piece.prims <= Biomes.Budget.MaxPrimsPerPiece, "piece " .. id .. " has 1.." .. Biomes.Budget.MaxPrimsPerPiece .. " parts")
	local area = 0
	for pi, p in piece.prims do
		local tag = "piece " .. id .. " part " .. pi
		truthy(p.material ~= "Neon", tag .. " does not glow (Neon means interactive in this maze)")
		truthy(ALLOWED_MATERIALS[p.material] == true, tag .. " uses a known material (" .. tostring(p.material) .. ")")
		truthy(p.light == nil, tag .. " carries no light (a light would add sight)")
		local su, sv, sw = p.size[1], p.size[2], p.size[3]
		local u, v, w = p.at[1], p.at[2], p.at[3]
		truthy(v - sv / 2 >= 3 - 1e-9, tag .. " stays 3 studs above the floor (the secret-door band and the floor stay clear)")
		truthy(w + sw / 2 <= 1.2 + 1e-9, tag .. " sticks out at most 1.2 studs (coins and buttons sit 4.5 studs from a wall)")
		truthy(w + sw / 2 > 0.05 or v + sv / 2 > 24, tag .. " shows (sticks out of the face, or above the wall top)")
		truthy(math.abs(u) + su / 2 <= 4.5 + 1e-9, tag .. " stays on its own 9-stud face")
		truthy(v + sv / 2 <= 30 + 1e-9, tag .. " rises at most 6 studs above the wall top")
		if v - sv / 2 < 24 then
			area += su * math.min(sv, 24 - (v - sv / 2))
		end
		truthy(p.transparency == nil or (p.transparency >= 0 and p.transparency < 1), tag .. " transparency is valid")
	end
	truthy(area <= 0.25 * 9 * 24 + 1e-9, string.format("piece %s covers at most a quarter of its face (%.1f sq studs)", id, area))
end

-- (review fix) a secret door that sinks takes its dressing out of sight. The server sinks a door by
-- WallHeight + 2 = 26 studs; pieces that stand ON the wall top reach higher than that above the wall's bottom,
-- so following the door alone left them sticking out of the floor where the door had been (adversarial
-- review: crystal spires and marble columns, 21 parts in 10 of 16 levels). The rule: a wall whose bottom has
-- left the floor is sinking (its pieces fade out over DecorFadeSeconds, nothing new is put on it); a wall whose
-- top is at or under the floor is gone (nothing of its dressing shows, at once). Judged from the wall's
-- POSITION (what every player sees), never from its name.
do
	local tall = {}
	for id, piece in Biomes.Pieces do
		for _, p in piece.prims do
			if p.at[2] + p.size[2] / 2 > 24 + 2 + 1e-9 then tall[id] = true end
		end
	end
	truthy(tall.spire and tall.column, "(why the rule is load-bearing) spires and columns reach above WallHeight + 2, the depth a door sinks")
	-- (bottom, top, floor top): a wall is 24 tall and stands on the floor's top
	eq(Biomes.wallState(0, 24, 0), "standing", "a wall on the floor is standing")
	eq(Biomes.wallState(-0.04, 23.96, 0), "standing", "within the tolerance it is still standing")
	eq(Biomes.wallState(-0.2, 23.8, 0), "sinking", "a wall whose bottom has gone into the floor is sinking")
	eq(Biomes.wallState(-23.9, 0.1, 0), "sinking", "still sinking while any of it shows above the floor")
	eq(Biomes.wallState(-24, 0, 0), "gone", "gone once its top reaches the floor's top")
	eq(Biomes.wallState(-26, -2, 0), "gone", "a sunk door is gone")
	eq(Biomes.wallState(100 - 26, 100 - 2, 100), "gone", "relative to the floor's top, wherever the maze sits")
	eq(Biomes.wallState(100, 124, 100), "standing", "and a standing wall there is standing")
	local F = Biomes.Budget.DecorFadeSeconds
	truthy(type(F) == "number" and F > 0, "DecorFadeSeconds is a positive number")
	local function near(a, b) return math.abs(a - b) < 1e-9 end
	truthy(near(Biomes.decorAlpha(0, nil), 0), "a piece fades in from nothing")
	truthy(near(Biomes.decorAlpha(F / 2, nil), 0.5), "halfway through the fade-in")
	truthy(near(Biomes.decorAlpha(10, nil), 1), "and then stays fully shown")
	truthy(near(Biomes.decorAlpha(10, 0), 1), "the moment its wall starts to sink it is still shown")
	truthy(near(Biomes.decorAlpha(10, F / 2), 0.5), "it fades out as the wall goes down")
	truthy(near(Biomes.decorAlpha(10, F), 0), "and is gone DecorFadeSeconds later")
	truthy(near(Biomes.decorAlpha(10, F * 5), 0), "and stays gone")
	truthy(near(Biomes.decorAlpha(F / 2, F / 4), 0.5), "a piece still fading in never jumps up when its wall sinks")
	-- the door sinks WallHeight + 2 over 0.7 s with Quad easing (MazeGame.server; check_labyrintspill_biomes
	-- parses it). Its top reaches the floor at 0.7 * (1 - sqrt(2 / 26)) = 0.51 s. The fade, plus two frames to
	-- notice the move, must be over by then, or a spire rides above the floor for a moment.
	truthy(F + 2 / 30 < 0.7 * (1 - math.sqrt(2 / 26)), string.format("the dressing is gone before the door's top reaches the floor (%.2f s)", F + 2 / 30))
end

-- open faces: a pure predicate over the grid, no wall kinds anywhere
do
	local walls = { ["1,0"] = true, ["0,1"] = true, ["1,1"] = true }
	local function isWall(x, y) return walls[x .. "," .. y] == true end
	local faces = Biomes.openFaces(isWall, 1, 1, 3, 3)
	-- neighbours of (1,1): (2,1) open, (0,1) wall, (1,2) open, (1,0) wall
	eq(#faces, 2, "a wall has one face per open neighbour")
	local out = Biomes.openFaces(isWall, 0, 0, 3, 3)
	eq(#out, 0, "faces toward the outside of the grid and toward walls are not faces")
end

--================================================================ air (particles)

for L = 1, 520, 7 do
	local rates = Biomes.airAt(EnvBands, L)
	local sum = 0
	for kind, r in rates do
		truthy(Biomes.Air[kind] ~= nil, "air kind " .. tostring(kind) .. " is defined")
		sum += r
	end
	if sum > Biomes.Budget.MaxEmitterRate then truthy(false, "air at level " .. L .. " stays within the particle budget") end
end
passed += 1
for kind, a in Biomes.Air do
	truthy(a.lightEmission >= 0 and a.lightEmission <= 1, "air " .. kind .. " light emission in 0..1")
	truthy(a.size <= 0.6, "air " .. kind .. " particles are small (they must never hide a monster)")
	truthy(a.transparency >= 0.3, "air " .. kind .. " particles are see-through")
end

--================================================================ album (the brag)

do
	local album, nextIdx = Biomes.album(EnvBands, 0)
	eq(#album, #Bands, "the album lists every biome")
	eq(album[1].reached, true, "a new player has reached the dungeon")
	eq(album[2].reached, false, "and not the jungle")
	eq(nextIdx, 2, "the next biome for a new player is the second")
	local album2, next2 = Biomes.album(EnvBands, Bands[3].from - 1)
	eq(album2[3].reached, true, "clearing the level before a biome means you are about to play in it (accepted+1)")
	eq(next2, 4, "and the next one after that is listed as next")
	local _, nextLast = Biomes.album(EnvBands, 100000)
	eq(nextLast, nil, "past the last biome there is no next")
end

--================================================================ validate rejects bad configs

do
	local function withBand(i, key, value)
		local saved = Bands[i][key]
		Bands[i][key] = value
		local ok = Biomes.validate(EnvBands)
		Bands[i][key] = saved
		return ok
	end
	local bright = { fogColor = { 60, 60, 60 }, outdoorAmbient = { 20, 20, 28 }, atmosColor = { 80, 85, 105 },
		atmosDecay = { 30, 30, 45 }, tint = { 230, 225, 235 }, torch = { 255, 235, 190 } }
	eq(withBand(3, "look", bright), false, "a biome that brightens the fog is rejected")
	local extra = table.clone(Bands[3].look)
	extra.ambient = { 0, 0, 0 }
	eq(withBand(3, "look", extra), false, "a biome that writes a sight field is rejected")
	local red = table.clone(Bands[3].look)
	red.tint = { 255, 150, 150 }
	eq(withBand(3, "look", red), false, "a colour grade that turns the yellow warning orange is rejected")
	-- (resume session) the red grade above is ALSO rejected by the luma and mildness rules, so it never
	-- proved the signal rule itself. This green-cyan grade keeps the live luma and is mild, and still pulls
	-- the orange lava toward the yellow warning: only the signal rule can reject it.
	do
		local cyan = table.clone(Bands[3].look)
		cyan.tint = { 190, 237, 234 }
		local t = cyan.tint
		local baseLuma = Biomes.luma(Biomes.Base.look.tint)
		truthy(math.abs(Biomes.luma(t) - baseLuma) <= math.max(0.6, baseLuma * 0.015), "(the cyan grade keeps the live luma)")
		truthy(math.min(t[1], t[2], t[3]) / math.max(t[1], t[2], t[3]) >= 0.76, "(and is a mild grade)")
		truthy(Biomes.signalGreenRatio(Biomes.Signals.trapDeadly, t) > 0.48, "(and it does push the lava's G/R past 0.48)")
		eq(withBand(3, "look", cyan), false, "a mild, luma-true grade that makes the lava read like the warning is rejected")
	end
	eq(withBand(2, "hazard", "icicle"), false, "a hazard in the second band is rejected")
	eq(withBand(3, "hazard", "nosuchkind"), false, "an unknown hazard kind is rejected")
	-- decor is only built on walls whose centre is inside DecorRadius; the radius must stay inside the torch
	truthy(Biomes.Budget.DecorRadius <= Biomes.Base.locked.TorchRange - 4,
		string.format("decor is only built around walls inside the torch's reach (radius %d vs torch %d)", Biomes.Budget.DecorRadius, Biomes.Base.locked.TorchRange))
	do
		local saved = Biomes.Budget.DecorRadius
		Biomes.Budget.DecorRadius = Biomes.Base.locked.TorchRange
		eq((Biomes.validate(EnvBands)), false, "a decor radius that reaches the torch's edge is rejected")
		Biomes.Budget.DecorRadius = saved
	end
	local p = Biomes.Pieces[next(Biomes.Pieces)]
	local savedMat = p.prims[1].material
	p.prims[1].material = "Neon"
	eq((Biomes.validate(EnvBands)), false, "a glowing decor piece is rejected")
	p.prims[1].material = savedMat
end

--================================================================ second review (30.09)

-- (second review, finding 2) the ring must not look like anything the maze asks you to STEP ON or WALK TO.
-- On this floor a glowing blue disc is a secret button (step on it) and the "Hjelp meg" guide's cyan dots say
-- "walk here"; the ring says "step OUT of me". The first fix only held the ring away from the trap's colours, so a
-- retune to the deep-blue button's own colour passed every gate. Measured as CIE76 delta E (sRGB -> Lab, D65)
-- through every biome grade, because both colours reach the screen through the same ColorCorrection tint.
do
	-- (missing functions read as wrong answers, so a build without them fails here instead of crashing)
	local lab = Biomes.lab or function(_) return { -1, -1, -1 } end
	local deltaE = Biomes.deltaE or function(_, _) return -1 end
	local graded = Biomes.graded or function(c, _) return c end
	-- the colour maths, pinned to known values first
	local w, k = lab({ 255, 255, 255 }), lab({ 0, 0, 0 })
	truthy(math.abs(w[1] - 100) < 0.05 and math.abs(w[2]) < 0.05 and math.abs(w[3]) < 0.05, "Lab of white is (100, 0, 0)")
	truthy(math.abs(k[1]) < 0.05, "Lab of black has L 0")
	local r = lab({ 255, 0, 0 })
	truthy(math.abs(r[1] - 53.24) < 0.1 and math.abs(r[2] - 80.09) < 0.2 and math.abs(r[3] - 67.20) < 0.2,
		string.format("Lab of pure red is (53.24, 80.09, 67.20) (got %.2f, %.2f, %.2f)", r[1], r[2], r[3]))
	truthy(math.abs(deltaE({ 255, 255, 255 }, { 0, 0, 0 }) - 100) < 0.05, "white to black is delta E 100")
	local g = graded({ 200, 100, 50 }, { 255, 204, 102 })
	truthy(g[1] == 200 and g[2] == 80 and math.abs(g[3] - 20) < 1e-9, "a grade multiplies each channel by tint / 255")

	local S = Biomes.StepOnColors
	truthy(type(S) == "table" and #S == 8, "eight step-on colours are listed: four button colours, the guide dots, coin, gem, exit")
	local ring = Biomes.Hazards.RingColor
	local minDE, where = math.huge, "?"
	for _, b in Bands do
		for _, s in S or {} do
			local d = deltaE(graded(ring, b.look.tint), graded(s.rgb, b.look.tint))
			if d < minDE then minDE, where = d, s.name .. " in " .. b.id end
		end
	end
	truthy(type(Biomes.Hazards.MinRingDeltaE) == "number" and Biomes.Hazards.MinRingDeltaE >= 25,
		"the ring keeps at least delta E 25 from every step-on colour (more than twice the 11.0 that separates the cyan button from the guide dots, which players already tell apart)")
	truthy(minDE >= (Biomes.Hazards.MinRingDeltaE or math.huge), string.format("the shipped ring does: nearest is the %s at delta E %.1f", where, minDE))
	print(string.format("  ring vs step-on colours: nearest %s, delta E %.1f (floor %s)", where, minDE, tostring(Biomes.Hazards.MinRingDeltaE)))
	local function withRing(c)
		local saved = Biomes.Hazards.RingColor
		Biomes.Hazards.RingColor = c
		local ok, err = Biomes.validate(EnvBands)
		Biomes.Hazards.RingColor = saved
		return ok, err
	end
	-- each of these passes every OTHER rule (cool, far from both trap phases): only the new rule can refuse them
	local ok1, err1 = withRing({ 70, 110, 255 })
	eq(ok1, false, "a ring in the deep-blue secret button's own colour is rejected")
	truthy(err1 ~= nil and string.find(err1, "button", 1, true) ~= nil, "and the refusal names the button (" .. tostring(err1) .. ")")
	eq((withRing({ 90, 235, 255 })), false, "a ring in the guide dots' cyan is rejected")
	eq((withRing({ 60, 200, 220 })), false, "a ring in the cyan button's colour is rejected")
	eq((withRing({ 85, 135, 255 })), false, "a ring half-way between the shipped blue and the deep-blue button is rejected")
	eq((withRing({ 100, 160, 255 })), true, "the shipped ring is accepted")
end

-- (second review, finding 4) the start cell's back wall carries the server's 🚪 Lobby door and, for the first
-- seconds of a level, the free-break sign in front of it. Decor on that face stood in front of the sign's text
-- (sconces, glass crystals) and inside the top of the door slab (grates). Which face that is follows from the
-- grid alone (the server always starts a maze in cell 0,0 and puts the door on its -Z wall: fine cell 1,0, whose
-- +Z face is FACES[3]), never from what kind of wall it is.
do
	eq(Biomes.FACES[3][1] == 0 and Biomes.FACES[3][2] == 1, true, "FACES[3] is the +Z face (into the start cell)")
	local dressed, other = 0, 0
	for L = 1, 500 do
		if Biomes.decorFor(EnvBands, L, 1, 0, 3) ~= nil then dressed += 1 end
		if Biomes.decorFor(EnvBands, L, 3, 0, 3) ~= nil then other += 1 end
	end
	eq(dressed, 0, "no level dresses the Lobby door's face (fine cell 1,0, +Z)")
	truthy(other > 100, "the same face one wall along is still dressed (" .. other .. " of 500 levels)")
	local sides = 0
	for L = 1, 500 do
		if Biomes.decorFor(EnvBands, L, 1, 0, 4) ~= nil or Biomes.decorFor(EnvBands, L, 1, 2, 4) ~= nil then sides += 1 end
	end
	truthy(sides > 100, "the door wall's other face, and the start cell's far wall, are dressed as always (" .. sides .. ")")
end

-- (01.10, pass-1 re-run: finding 4 again, for critters) The critters added on 01.10 are dressing too, and the first
-- version homed them anywhere: a crypt spider climbing the start cell's back wall went straight up through the door
-- slab and the free-break sign (check_labyrintspill_biomes §8 measured 28 of 96 levels, L150-245, with a spider in
-- front of the sign while it was up). The start cell, the open cell the reserved face looks into, is no critter's
-- home. A rule on grid position only, like reservedFace; the player starts in that cell and never shares a cell with
-- a critter anyway, so nothing is lost but the one cell the sign needs clear.
do
	local free = Biomes.critterHomeFree or function(_, _) return true end
	local d = Biomes.FACES[3]
	eq(free(1 + d[1], 0 + d[2]), false, "the cell the Lobby door's face looks into (fine 1,1, the start cell) is no critter's home")
	eq(free(3, 1), true, "the next cell along the door's wall is a home as before")
	eq(free(1, 3), true, "the next cell into the maze is a home as before")
	local closed = 0
	for fx = 1, 59, 2 do
		for fy = 1, 59, 2 do
			if not free(fx, fy) then closed += 1 end
		end
	end
	eq(closed, 1, "exactly one open cell of a 30 x 30 maze is closed to critters")
end

-- (second review, finding 5) the phone budget is enforced by validate, not only measured by one headless check.
-- The structural worst case is every decor slot full of the largest piece, every hazard view drawn, and the air
-- box: MaxDecorPieces x MaxPrimsPerPiece + MaxHazardsShown x MaxHazardViewParts + 1. It must fit MaxLocalParts;
-- the emitters (two air kinds + one burst per hazard view) must fit MaxEmitters; and there is no light in a maze.
do
	local B = Biomes.Budget
	truthy(type(B.MaxHazardViewParts) == "number", "the largest hazard view's part count is in the budget (check_labyrintspill_budget measures the real views against it)")
	local bound = Biomes.partBound and Biomes.partBound() or -1
	eq(bound, (B.MaxDecorPieces or 0) * (B.MaxPrimsPerPiece or 0) + (B.MaxHazardsShown or 0) * (B.MaxHazardViewParts or 0) + 1,
		"partBound() is the structural worst case")
	truthy(bound > 0 and bound <= B.MaxLocalParts, string.format("the shipped caps fit the phone budget (%d <= %d)", bound, B.MaxLocalParts))
	local function withBudget(k, v)
		local saved = B[k]
		B[k] = v
		local ok, err = Biomes.validate(EnvBands)
		B[k] = saved
		return ok, err
	end
	local ok40, err40 = withBudget("MaxDecorPieces", 40)
	eq(ok40, false, "a decor cap of 40 is rejected (40 x 4 + 2 x 9 + 1 = 179 parts)")
	truthy(err40 ~= nil and string.find(err40, "179", 1, true) ~= nil, "and the refusal names the worst case (" .. tostring(err40) .. ")")
	eq((withBudget("MaxDecorPieces", 30)), true, "a cap of 30 still fits (139 parts)")
	eq((withBudget("MaxDecorPieces", 31)), false, "a cap of 31 does not (143 parts)")
	eq((withBudget("MaxHazardsShown", 9)), false, "nine hazard views at once are rejected (26 x 4 + 9 x 9 + 1 = 186 parts)")
	eq((withBudget("MaxPrimsPerPiece", 6)), false, "six parts per piece are rejected (26 x 6 + 19 = 175)")
	eq((withBudget("MaxLocalParts", 122)), false, "a part budget under the worst case (123) is rejected")
	eq((withBudget("MaxLocalParts", 123)), true, "a budget exactly at the worst case is accepted")
	-- 3 views: 26 x 4 + 3 x 9 + 1 = 132 parts fits, but 2 air + 3 bursts = 5 emitters does not
	eq((withBudget("MaxHazardsShown", 3)), false, "three hazard views need five emitters (two air + three bursts): over MaxEmitters 4")
	eq((withBudget("MaxEmitters", 3)), false, "an emitter budget under two air kinds + two bursts is rejected")
	eq((withBudget("MaxMazeLights", 1)), false, "a light in the maze is rejected (a light adds sight)")
	eq((withBudget("MaxHazardViewParts", nil)), false, "a budget without the hazard view's size is rejected")
end

-- (2026-10-01) CRITTERS. docs/complete-game-standard.md §2: every band has its own light, colour, scenery, CRITTERS
-- and weather. Before this each band had decor and air particles and no living thing (the jungle's fireflies were
-- the nearest). A critter is small, never glows (Neon means "interactive" here), carries no light, is inert, lives
-- inside ONE open cell of the maze (so it never pokes into a wall or blocks a corridor), and takes a decor slot:
-- Budget.MaxDecorPieces counts wall dressing and critters together, so partBound() is still the worst case.
do
	local C = Biomes.Critters
	local B = Biomes.Budget
	truthy(type(C) == "table", "Biomes.Critters exists")
	truthy(type(B.MaxCritters) == "number" and B.MaxCritters >= 1 and B.MaxCritters <= B.MaxDecorPieces,
		"Budget.MaxCritters is a number inside the decor cap (" .. tostring(B.MaxCritters) .. ")")
	C = C or {}
	local kindsSeen = {}
	for i, b in Bands do
		local n, total = 0, 0
		for kind, count in (b.critters or {}) do
			n += 1
			total += count
			kindsSeen[kind] = true
			truthy(C[kind] ~= nil, "band " .. b.id .. " names a critter that exists (" .. tostring(kind) .. ")")
		end
		truthy(n >= 1, "band " .. b.id .. " has at least one critter")
		truthy(total >= 1 and total <= (B.MaxCritters or 0), string.format("band %s: %d critters, within MaxCritters", b.id, total))
	end
	local distinct = 0
	for _ in kindsSeen do distinct += 1 end
	truthy(distinct >= 6, "at least six different critters across the eight biomes (" .. distinct .. ")")
	-- every critter: small, no Neon, no light, at most MaxPrimsPerPiece parts, a known motion
	local S, WALL = Biomes.Hazards.CellSize, 24
	for kind, def in C do
		truthy(type(def.prims) == "table" and #def.prims >= 1 and #def.prims <= B.MaxPrimsPerPiece,
			kind .. ": 1.." .. tostring(B.MaxPrimsPerPiece) .. " parts")
		for _, p in def.prims or {} do
			truthy(p.material ~= "Neon" and Biomes.DecorMaterials[p.material] == true, kind .. " uses an allowed material (" .. tostring(p.material) .. ")")
			truthy(p.light == nil, kind .. " carries no light")
			truthy(math.max(p.size[1], p.size[2], p.size[3]) <= 1.6, kind .. " is small (every part at most 1.6 studs)")
		end
		truthy(Biomes.CritterMotions[def.motion] == true, kind .. " moves in a known way (" .. tostring(def.motion) .. ")")
	end
	-- every pose, over a minute, keeps every part inside its own open cell and between the floor and the wall top
	if type(Biomes.critterPose) == "function" then
		for kind, def in C do
			local worstXZ, lowY, highY, moved = 0, math.huge, -math.huge, 0
			local lx, ly, lz = nil, nil, nil
			for face = 1, 4 do
				for step = 0, 600 do
					local t = step * 0.1
					local x, y, z = Biomes.critterPose(kind, t, 0.37 * face, S, face)
					if lx and (math.abs(x - lx) + math.abs(y - ly) + math.abs(z - lz)) > 1e-6 then moved += 1 end
					lx, ly, lz = x, y, z
					for _, p in def.prims do
						local r = math.max(p.size[1], p.size[2], p.size[3]) / 2
						local px = math.abs(x) + math.sqrt(p.at[1] ^ 2 + p.at[3] ^ 2) + r
						local pz = math.abs(z) + math.sqrt(p.at[1] ^ 2 + p.at[3] ^ 2) + r
						worstXZ = math.max(worstXZ, px, pz)
						lowY = math.min(lowY, y + p.at[2] - p.size[2] / 2)
						highY = math.max(highY, y + p.at[2] + p.size[2] / 2)
					end
				end
			end
			truthy(worstXZ <= S / 2, string.format("%s stays inside its %d-stud cell (reaches %.2f of %.1f from the centre)", kind, S, worstXZ, S / 2))
			truthy(lowY >= 0 and highY <= WALL, string.format("%s stays between the floor and the wall top (%.2f..%.2f)", kind, lowY, highY))
			truthy(moved > 2000, kind .. " is alive: it moves (" .. moved .. " of 2403 sample steps)")
		end
	else
		truthy(false, "Biomes.critterPose exists")
	end
	-- blending over a seam, capped
	if type(Biomes.crittersAt) == "function" then
		for L = 1, 420 do
			local m = Biomes.crittersAt(EnvBands, L)
			local total = 0
			for _, n in m do total += n end
			if total < 1 or total > B.MaxCritters then
				failed += 1
				print("FAIL: level " .. L .. " wants " .. total .. " critters")
				break
			end
		end
		passed += 1
		-- (01.10, pass 2 resumed: K5 survived) with the cap forced to 2, no level gets more than 2, and the trim really
		-- bound (some level wanted 3)
		local savedCap = B.MaxCritters
		B.MaxCritters = 2
		local over, trimmed = 0, 0
		for L = 1, 420 do
			local total = 0
			for _, n in Biomes.crittersAt(EnvBands, L) do total += n end
			if total > 2 then over += 1 end
		end
		B.MaxCritters = savedCap
		for L = 1, 420 do
			local total = 0
			for _, n in Biomes.crittersAt(EnvBands, L) do total += n end
			if total > 2 then trimmed += 1 end
		end
		eq(over, 0, "with MaxCritters forced to 2, crittersAt never gives a level more than 2")
		truthy(trimmed > 0, "and the trim really binds: " .. trimmed .. " of 420 levels want 3 at the shipped cap")
		local deep = Biomes.crittersAt(EnvBands, 38)
		local iceHas = false
		for kind in Bands[3].critters or {} do if deep[kind] then iceHas = true end end
		truthy(iceHas, "level 38 (deep in the Ice Cellar) has the Ice Cellar's critters")
	else
		truthy(false, "Biomes.crittersAt exists")
	end
	-- validate refuses what breaks the rules
	local function withCritter(kind, mutate)
		local saved = C[kind]
		local copy = table.clone(saved)
		copy.prims = table.clone(saved.prims)
		mutate(copy)
		C[kind] = copy
		local ok, err = Biomes.validate(EnvBands)
		C[kind] = saved
		return ok, err
	end
	local anyKind = next(C)
	if anyKind then
		eq((withCritter(anyKind, function(d) d.prims[1] = table.clone(d.prims[1]); d.prims[1].material = "Neon" end)), false, "a glowing critter is rejected")
		eq((withCritter(anyKind, function(d) d.prims[1] = table.clone(d.prims[1]); d.prims[1].light = { range = 4 } end)), false, "a critter with a light is rejected")
		eq((withCritter(anyKind, function(d) for _ = 1, 5 do table.insert(d.prims, d.prims[1]) end end)), false, "a critter with more parts than a decor piece is rejected")
		eq((withCritter(anyKind, function(d) d.prims[1] = table.clone(d.prims[1]); d.prims[1].size = { 3, 3, 3 } end)), false, "a big critter is rejected")
		eq((withCritter(anyKind, function(d) d.motion = "teleport" end)), false, "an unknown motion is rejected")
		eq((withCritter(anyKind, function(d) d.prims[1] = table.clone(d.prims[1]); d.prims[1].color = { 250, 205, 50 } end)), false,
			"a critter coloured like a coin is rejected (never like something you step on or dodge)")
		eq((withCritter(anyKind, function(d) d.prims[1] = table.clone(d.prims[1]); d.prims[1].shape = "WedgeDown" end)), false,
			"a critter shape other than Block or Ball is rejected")
	end
	local savedMax = B.MaxCritters
	B.MaxCritters = 0
	eq((Biomes.validate(EnvBands)), false, "MaxCritters 0 is rejected (at least one critter)")
	-- (01.10, pass 2 resumed: two rules no assertion held, found by the mutation sweep, K1 and K3) a critter takes a
	-- decor slot, so the critter cap may not exceed the decor cap; and no band may want more critters than the cap
	B.MaxCritters = B.MaxDecorPieces + 1
	eq((Biomes.validate(EnvBands)), false, "a critter cap over the decor cap is rejected (a critter takes a decor slot)")
	B.MaxCritters = savedMax
	local savedSky = Bands[7].critters
	Bands[7].critters = { bird = savedMax + 1 }
	local okOver, errOver = Biomes.validate(EnvBands)
	eq(okOver, false, "a band wanting more critters than MaxCritters is rejected")
	truthy(errOver ~= nil and string.find(errOver, "critters at once", 1, true) ~= nil, "for that reason (" .. tostring(errOver) .. ")")
	Bands[7].critters = savedSky
	local savedBand = Bands[2].critters
	Bands[2].critters = { dragon = 1 }
	eq((Biomes.validate(EnvBands)), false, "a band naming an unknown critter is rejected")
	Bands[2].critters = savedBand
end

print(string.format("Biomes: %d passed, %d failed", passed, failed))
if failed > 0 then error("Biomes spec failed", 0) end
