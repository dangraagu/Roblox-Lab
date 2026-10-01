-- Spec for Night: the rules behind Steal a Cryptid's eye candy (EYECANDY.md). Pure, no Roblox.
-- Run from the game directory: luau tests/Night.spec.luau
--
-- What it pins, rule by rule:
--   * READABILITY FLOOR. No environment band may be darker or foggier than the game as it shipped
--     (Config.Lighting, DESIGN.md section 13): a raider reads a whole camp from its gate, tiers are
--     colour-coded, neon nets must bloom. Night.readable judges a band AND any written frame.
--   * NIGHT HOURS. Bands write ClockTime as hours after noon-of-yesterday (18 = 6 pm, 27 = 3 am) and
--     stay inside 17.5..30, so a glide between two bands never passes through daylight.
--   * PROGRESS. The home sky follows the Journal's rank (Economy.rank: the highest tier ever owned),
--     never a timer, and never goes backwards within a session.
--   * WHERE. A root in a pocket (x past the pocket origin) is in a camp; its tier comes from the raid
--     the server reported. Camp scenery stays out of the yard and out of the camera's view of it.
--   * THE HAZARD GATE. Hazards only ever run at home, after the tutorial, with no poacher about, no
--     panel or build mode open, away from the ground's edge, and only after a settle time.
--   * HABITATS. Your own cages get a habitat patch per species; only the rarest few get particles.
--   * TEXT. Every string the night writes on the HUD chip fits the chip (ASCII, <= ChipMaxChars).
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Layout")
local Night = require("../src/shared/Night")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local function deep(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deep(x) end
	return out
end

--================================================================ the readability floor

local base = Night.baseGroups(Config)
do
	local ok, why = Night.readable(Config, base)
	truthy(ok, "the game as it shipped (Config.Lighting) meets its own floor (" .. tostring(why) .. ")")
	near(base.lighting.ClockTime, 24.2, 1e-9, "v1's ClockTime 0.2 is written as night hour 24.2")
	eq(base.atmosphere.Density, Config.Lighting.atmosphere.Density, "base atmosphere density is v1's")
	eq(base.sunRays.Intensity, 0, "v1 had no sun rays")
	truthy(type(base.sky.StarCount) == "number", "the base sky has a StarCount")
end

-- every field of the floor, broken one at a time, must fail and say which
local cases = {
	{ "lighting", "Brightness", -0.01, "Brightness" },
	{ "lighting", "ExposureCompensation", -0.01, "ExposureCompensation" },
	{ "lighting", "FogStart", -1, "FogStart" },
	{ "lighting", "FogEnd", -1, "FogEnd" },
	{ "atmosphere", "Density", 0.01, "Density" },
	{ "atmosphere", "Haze", 0.05, "Haze" },
	{ "bloom", "Threshold", 0.01, "Threshold" },
	{ "colorCorrection", "Saturation", -0.01, "Saturation" },
	{ "colorCorrection", "Brightness", -0.01, "colorCorrection.Brightness" },
}
for _, c in cases do
	local g = deep(base)
	g[c[1]][c[2]] += c[3]
	local ok, why = Night.readable(Config, g)
	eq(ok, false, "a frame with " .. c[1] .. "." .. c[2] .. " moved the wrong way is not readable")
	truthy(type(why) == "string" and string.find(why, c[4], 1, true) ~= nil, "  and the reason names " .. c[4] .. " (" .. tostring(why) .. ")")
end
do
	local g = deep(base)
	g.lighting.Ambient = { 10, 10, 10 }
	local ok, why = Night.readable(Config, g)
	eq(ok, false, "a darker Ambient is not readable")
	truthy(why and string.find(why, "Ambient", 1, true) ~= nil, "  and the reason names Ambient")
	g = deep(base)
	g.lighting.OutdoorAmbient = { 5, 5, 5 }
	eq((Night.readable(Config, g)), false, "a darker OutdoorAmbient is not readable")
	-- brighter, clearer, more saturated: all fine
	g = deep(base)
	g.lighting.Brightness = 2
	g.atmosphere.Density = 0.2
	g.colorCorrection.Saturation = 0.2
	g.lighting.FogEnd = 900
	g.lighting.Ambient = { 90, 90, 90 }
	eq((Night.readable(Config, g)), true, "brighter, clearer and more saturated is readable")
	-- a colour ambient with more blue but less luminance is still darker
	g = deep(base)
	g.lighting.Ambient = { 0, 10, 250 }
	near(Night.luminance({ 0, 10, 250 }), 0.2126 * 0 + 0.7152 * 10 + 0.0722 * 250, 1e-9, "luminance is Rec.709 relative luminance")
end

--================================================================ checkBand: one band's shape

local function goodBand()
	local b = deep(base)
	b.id = "t"
	b.from = 0
	b.name = "Test"
	b.sub = "a test band"
	b.lighting.ClockTime = 20
	b.pieces, b.hazards, b.ambient = {}, {}, {}
	return b
end
do
	local ok, why = Night.checkBand(Config, goodBand())
	truthy(ok, "a well-formed band passes checkBand (" .. tostring(why) .. ")")
	for _, h in { 17.4, 12, 30.1, 6, -1 } do
		local b = goodBand()
		b.lighting.ClockTime = h
		local ok2, why2 = Night.checkBand(Config, b)
		eq(ok2, false, "ClockTime " .. h .. " (outside night hours 17.5..30) is rejected")
		truthy(why2 and string.find(why2, "ClockTime", 1, true) ~= nil, "  and says ClockTime")
	end
	for _, h in { 17.5, 18, 24, 26.9, 30 } do
		local b = goodBand()
		b.lighting.ClockTime = h
		eq((Night.checkBand(Config, b)), true, "ClockTime " .. h .. " is a night hour")
	end
	local b = goodBand()
	b.atmosphere.Glare = nil
	eq((Night.checkBand(Config, b)), false, "a band missing a field (atmosphere.Glare) is rejected")
	b = goodBand()
	b.depthOfField = { FarIntensity = 0.3 }
	local okD, whyD = Night.checkBand(Config, b)
	eq(okD, false, "a band with depth of field is rejected (DESIGN.md 13: it blurs the far side of a camp)")
	truthy(whyD and string.find(whyD, "depth", 1, true) ~= nil, "  and says depth of field")
	b = goodBand()
	b.atmosphere.Density = 0.6
	eq((Night.checkBand(Config, b)), false, "a band foggier than v1 is rejected by checkBand too")
	b = goodBand()
	b.name = "Moon \u{1F315}"
	eq((Night.checkBand(Config, b)), false, "a band name with an emoji is rejected (Roblox's font draws some as boxes)")
	b = goodBand()
	b.sub = ""
	eq((Night.checkBand(Config, b)), false, "a band without a subtitle is rejected")
end

--================================================================ night hours

near(Night.clockTime(26.8), 2.8, 1e-9, "night hour 26.8 is ClockTime 2.8")
near(Night.clockTime(18.15), 18.15, 1e-9, "night hour 18.15 is ClockTime 18.15")
near(Night.clockTime(24), 0, 1e-9, "night hour 24 is midnight")
near(Night.clockTime(30), 6, 1e-9, "night hour 30 is 6 am")
do
	-- a plain lerp between 18.15 and 24.2 never passes a daylight hour (6..17.5) once wrapped
	local worst = true
	for i = 0, 100 do
		local h = 18.15 + (24.2 - 18.15) * i / 100
		local c = Night.clockTime(h)
		if c > 6 and c < 17.5 then worst = false end
	end
	truthy(worst, "a glide from dusk (18.15) to v1's midnight (24.2) never shows daylight")
	-- the bug night hours exist to prevent: the same glide in 0-24 clock time
	local dayFrames = 0
	for i = 0, 100 do
		local c = 18.15 + (0.2 - 18.15) * i / 100
		if c > 6 and c < 17.5 then dayFrames += 1 end
	end
	truthy(dayFrames > 50, "(control) the same glide in raw ClockTime spends " .. dayFrames .. " of 101 frames in daylight")
end

--================================================================ progress = the Journal's rank

eq(Night.rank(Config, nil, nil), 0, "no State yet: rank 0")
eq(Night.rank(Config, nil, 3), 3, "no State: keep the rank already seen")
eq(Night.rank(Config, { rank = 2 }, nil), 2, "State.rank 2")
eq(Night.rank(Config, { rank = 2 }, 3), 3, "rank never goes backwards within a session")
eq(Night.rank(Config, { rank = 9 }, 0), #Config.Tiers, "rank is clamped to the top tier")
eq(Night.rank(Config, { rank = -3 }, 0), 0, "a negative rank reads 0")
eq(Night.rank(Config, { rank = 0 / 0 }, 1), 1, "a NaN rank keeps the rank already seen")
eq(Night.rank(Config, { rank = "4" }, 0), 4, "a numeric string is read as a number")
eq(Night.rank(Config, { rank = 2.7 }, 0), 2, "a fractional rank is floored")
eq(Night.rank(Config, {}, 1), 1, "a State without rank keeps the rank already seen")

--================================================================ the home sky's level: the rank, then the gathering

-- docs/complete-game-standard.md section 2 asks for at least 5 bands. The Journal's rank names four (dusk .. mythic);
-- the fifth, the gathering, is one step past the Mythic, once the best lair income the player has ever had (State.best,
-- the Top Lairs board's metric) reaches Config.Night.GatheringRate. Never a timer, never backwards.
do
	local G = Config.Night.GatheringRate
	local top = #Config.Tiers
	eq(Night.level(Config, nil, nil), 0, "no State yet: level 0")
	eq(Night.level(Config, { rank = 2, best = 30 }, nil), 2, "below the Mythic the level is the rank")
	eq(Night.level(Config, { rank = top, best = G - 1 }, nil), top, "the Mythic with a lair below GatheringRate: level = rank")
	eq(Night.level(Config, { rank = top, best = G }, nil), top + 1, "the Mythic and a best lair at GatheringRate: one step past it")
	eq(Night.level(Config, { rank = top - 1, best = G * 10 }, nil), top - 1, "a big best without the Mythic in the Journal is not the gathering")
	eq(Night.level(Config, { rank = top, best = 0 }, top + 1), top + 1, "never backwards (a later State with a lower best)")
	eq(Night.level(Config, { rank = 1 }, 3), 3, "never below the level already seen")
	eq(Night.level(Config, { rank = top, best = "lots" }, nil), top, "a best that is not a number counts as none")
	eq(Night.level(Config, { rank = top, best = 0 / 0 }, nil), top, "a NaN best counts as none")
	eq(Night.level(Config, { rank = top, best = tostring(G) }, nil), top + 1, "a numeric string best is read as a number")
	eq(Night.level(Config, { rank = 99, best = 1e12 }, nil), top + 1, "clamped to the last band")
	eq(Night.level(Config, {}, 2), 2, "a State without rank or best keeps the level already seen")
end

--================================================================ where: home or a camp pocket

local W = Config.World
eq(Night.pocketSlot(Config, 0), nil, "the Trailhead is not in a pocket")
eq(Night.pocketSlot(Config, 900), nil, "the far end of a 12-plot road is not in a pocket")
eq(Night.pocketSlot(Config, W.PocketOriginX - W.PocketPitch / 2 - 0.01), nil, "just before the first pocket's slice")
eq(Night.pocketSlot(Config, W.PocketOriginX - W.PocketPitch / 2), 0, "the first pocket's slice starts half a pitch before its origin")
eq(Night.pocketSlot(Config, W.PocketOriginX + 36), 0, "the middle of pocket 0")
eq(Night.pocketSlot(Config, W.PocketOriginX + W.PocketPitch / 2 - 0.01), 0, "the end of pocket 0's slice")
eq(Night.pocketSlot(Config, W.PocketOriginX + W.PocketPitch / 2), 1, "the start of pocket 1's slice")
eq(Night.pocketSlot(Config, W.PocketOriginX + W.PocketPitch * 5 + 30), 5, "pocket 5")
eq(Night.pocketOriginX(Config, 5), W.PocketOriginX + W.PocketPitch * 5, "pocket 5's origin")
eq(Night.pocketSlot(Config, 0 / 0), nil, "NaN is nowhere")
do
	local where, tier, slot = Night.scene(Config, 100, { raid = { tier = 3 } }, nil)
	eq(where, "home", "a root on the road is home even when the State already says raid (teleport not seen yet)")
	eq(tier, nil, "  with no camp tier")
	where, tier, slot = Night.scene(Config, W.PocketOriginX + 20, { raid = { tier = 3 } }, nil)
	eq(where, "camp", "a root in a pocket is in a camp")
	eq(tier, 3, "  of the raid's tier")
	eq(slot, 0, "  in pocket 0")
	where, tier = Night.scene(Config, W.PocketOriginX + 20, { raid = nil }, 2)
	eq(tier, 2, "in a pocket before the State says raid: the tier from the raidStart event")
	where, tier = Night.scene(Config, W.PocketOriginX + 20, nil, nil)
	eq(tier, 1, "in a pocket with nothing known: tier 1")
	where, tier = Night.scene(Config, W.PocketOriginX + 20, { raid = { tier = 9 } }, nil)
	eq(tier, #Config.Camps, "a tier past the last camp is clamped")
	where, tier = Night.scene(Config, W.PocketOriginX + 20, { raid = { tier = 0 } }, nil)
	eq(tier, 1, "a tier below 1 is clamped")
end

--================================================================ camp keep-out: scenery stays out of the yard and the view

do
	local m = Config.Night.CampMargin
	truthy(type(m) == "number" and m >= 4, "Config.Night.CampMargin is at least 4 studs")
	-- every cell of the camp's grid, gate and fence rows included, is kept clear
	local worstClear = 0
	for row = 0, W.CageRow do
		for col = 1, W.YardCols do
			local x, z = Layout.cellCenter(Config, col, row)
			for _, dx in { -W.CellSize / 2, 0, W.CellSize / 2 } do
				for _, dz in { -W.CellSize / 2, 0, W.CellSize / 2 } do
					if Night.clearOfCamp(Config, x + dx, z + dz, 0) then worstClear += 1 end
				end
			end
		end
	end
	eq(worstClear, 0, "no point of the camp's 9 x 10 grid (cell centres, edges, corners) is clear for scenery")
	-- the fences and the camp sign (plot-local, the server's buildPocket)
	eq(Night.clearOfCamp(Config, -0.5, 56, 0), false, "the left fence is kept clear")
	eq(Night.clearOfCamp(Config, W.PlotWidth + 0.5, 56, 0), false, "the right fence is kept clear")
	eq(Night.clearOfCamp(Config, 36, W.ApronDepth + W.CellSize * (W.CageRow + 1) + 0.5, 0), false, "the back fence is kept clear")
	local gx = Layout.cellCenter(Config, W.GateCol, 0)
	eq(Night.clearOfCamp(Config, gx, W.ApronDepth - 0.5, 0), false, "the camp sign in front of the gate is kept clear")
	-- the margin
	eq(Night.clearOfCamp(Config, -1 - m + 0.5, 56, 0), false, "inside the margin left of the fence")
	eq(Night.clearOfCamp(Config, -1 - m - 0.5, 56, 0), true, "just outside the margin left of the fence")
	eq(Night.clearOfCamp(Config, -1 - m - 3, 56, 4), false, "a 4-stud ball 3 studs past the margin still reaches in")
	eq(Night.clearOfCamp(Config, -1 - m - 5, 56, 4), true, "a 4-stud ball 5 studs past the margin is clear")
	-- the camera sits behind the raider at the gate: nothing between it and the camp
	eq(Night.clearOfCamp(Config, gx, -20, 0), false, "20 studs behind the gate (where the camera is) is kept clear")
	eq(Night.clearOfCamp(Config, gx + 25, -60, 0), false, "the camera corridor is kept clear 60 studs back")
	eq(Night.clearOfCamp(Config, gx + 60, -40, 0), true, "well to the side of the corridor is clear")
	eq(Night.clearOfCamp(Config, 36, 200, 0), true, "far behind the cages is clear")
	-- boxes (a part's footprint): a wide box behind the camp is clear even though a circle round it is not
	local z1 = W.ApronDepth + W.CellSize * (W.CageRow + 1) + 1 + m
	eq(Night.boxClearOfCamp(Config, -74, 146, z1 + 1, z1 + 60), true, "a 220-wide box starting 1 stud behind the margin is clear")
	eq(Night.clearOfCamp(Config, 36, z1 + 31, math.sqrt(110 ^ 2 + 30 ^ 2)), false, "(the same box as a circle is not: why boxes are tested as boxes)")
	eq(Night.boxClearOfCamp(Config, -74, 146, z1 - 1, z1 + 60), false, "the same box reaching 1 stud into the margin is not")
	eq(Night.boxClearOfCamp(Config, 10, 20, 40, 50), false, "a box inside the yard is not")
	eq(Night.boxClearOfCamp(Config, gx - 5, gx + 5, -50, -40), false, "a box in the camera corridor is not")
	eq(Night.boxClearOfCamp(Config, -200, -150, -300, 400), true, "a box far to the side is")
end

--================================================================ the hazard gate

do
	local H = Config.Night.Hazards
	local function ctx(over)
		local c = { loaded = true, scene = "home", tutorial = 4, buildMode = false, poacher = false, panelOpen = false, edge = 100 }
		for k, v in over or {} do c[k] = v end
		return c
	end
	local g = Night.newGate()
	local run, why = Night.stepGate(g, Config, 1 / 30, ctx())
	eq(run, false, "a gate that just opened waits out its settle time")
	eq(why, "settling", "  and says settling")
	-- frame 1 is done; frames 2 .. N-1 still settle, frame N (N / 30 = SettleSeconds) opens
	local frames = math.round(H.SettleSeconds * 30)
	for _ = 2, frames - 1 do
		run, why = Night.stepGate(g, Config, 1 / 30, ctx())
	end
	eq(run, false, "still settling a frame before SettleSeconds")
	run, why = Night.stepGate(g, Config, 1 / 30, ctx())
	eq(run, true, "open after SettleSeconds (" .. H.SettleSeconds .. " s)")
	eq(why, "open", "  and says open")

	local blocks = {
		{ { loaded = false }, "loading", true },
		{ { scene = "camp" }, "camp", true },
		{ { tutorial = H.AfterTutorial - 1 }, "tutorial", false },
		{ { poacher = true }, "poacher", true },
		{ { buildMode = true }, "build", false },
		{ { panelOpen = true }, "panel", false },
		{ { edge = H.EdgeMarginStuds - 0.5 }, "edge", false },
	}
	for _, b in blocks do
		local gate = Night.newGate()
		for _ = 1, math.ceil(H.SettleSeconds * 30) + 2 do Night.stepGate(gate, Config, 1 / 30, ctx()) end
		local r0 = Night.stepGate(gate, Config, 1 / 30, ctx())
		eq(r0, true, b[2] .. ": the gate was open before")
		local r1, w1 = Night.stepGate(gate, Config, 1 / 30, ctx(b[1]))
		eq(r1, false, b[2] .. ": closes the gate")
		eq(w1, b[2], b[2] .. ": and names it")
		eq(Night.cancelsFlight(w1), b[3], b[2] .. ": " .. (if b[3] then "removes" else "does not remove") .. " a hazard already in flight")
		local r2, w2 = Night.stepGate(gate, Config, 1 / 30, ctx())
		eq(r2, false, b[2] .. ": reopening settles again first")
		eq(w2, "settling", b[2] .. ": says settling")
	end
	-- precedence: the most important reason is the one reported
	local gate = Night.newGate()
	local _, w = Night.stepGate(gate, Config, 1 / 30, ctx({ scene = "camp", buildMode = true, poacher = true }))
	eq(w, "camp", "camp outranks every other reason")
	_, w = Night.stepGate(gate, Config, 1 / 30, ctx({ poacher = true, buildMode = true, panelOpen = true }))
	eq(w, "poacher", "a poacher outranks build mode and an open panel")
	eq(Night.cancelsFlight("open"), false, "an open gate cancels nothing")
	eq(Night.cancelsFlight("settling"), false, "settling cancels nothing")
end

--================================================================ the camera: lanes never start underground

do
	local H = Config.Night.Hazards
	local maxDown = math.rad(H.MaxLookDownDegrees)
	local ok, p = Night.hazardPitch(Config, math.rad(-22))
	eq(ok, true, "a camera looking 22 degrees down may launch")
	near(p, math.rad(-H.ViewPitchDegrees), 1e-9, "  with the window's centre raised to -ViewPitchDegrees, so its top is the horizon")
	ok, p = Night.hazardPitch(Config, math.rad(10))
	eq(ok, true, "a camera looking 10 degrees up may launch")
	near(p, math.rad(10), 1e-9, "  with its own pitch")
	ok, p = Night.hazardPitch(Config, -maxDown - 0.01)
	eq(ok, false, "a camera looking down more steeply than MaxLookDownDegrees holds the launch")
	ok, p = Night.hazardPitch(Config, -maxDown + 0.01)
	eq(ok, true, "just inside MaxLookDownDegrees may launch")
	ok, p = Night.hazardPitch(Config, 0 / 0)
	eq(ok, true, "a NaN pitch reads as level")
	near(p, 0, 1e-9, "  pitch 0")
end

--================================================================ where a hazard is DRAWN (visual only)

-- The template (+1 Jump) flies a hazard on along its lane after it arrives: in open sky that is fine. Here
-- the lane comes DOWN at a player standing on the ground, so after passing the player a crow would fly on
-- into the ground (with its warning marker still blinking through it), and a player who left the ring by
-- stepping along the lane or toward the hazard would see it fly straight through them with no knock.
-- Night.drawPosition draws: exactly the lane until arrival (what the warning showed); after arrival a
-- flier swoops up and away and an `impact` kind (the meteorite) ends, striking the ring; and for a player
-- who has left the ring (`avoid`) the drawn path rises over a smooth bump, ClearStuds over their root.
-- The HIT rule is untouched (Hazards.checkHit on the lane, inside the ring).
do
	local Hazards = require("../src/shared/Hazards")
	local H = Config.Night.Hazards
	local ground = 0
	local root = { x = 0, y = ground + Config.World.RootHeight, z = 0 }
	local s0 = 4242
	local function r01()
		s0 = (1664525 * s0 + 1013904223) % 4294967296
		return s0 / 4294967296
	end
	local function dist(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	truthy(type(H.SwoopDegrees) == "number" and H.SwoopDegrees >= 20 and H.SwoopDegrees <= 60, "Config.Night.Hazards.SwoopDegrees is 20..60")
	truthy(type(H.ClearStuds) == "number" and H.ClearStuds >= 4, "Config.Night.Hazards.ClearStuds clears an avatar's head (>= 4 studs over the root)")
	local impactKinds = 0
	for _, k in H.Kinds do if k.impact then impactKinds += 1 end end
	truthy(impactKinds >= 1, "at least one kind (the meteorite) ends where it arrives")

	local offLane, dive, meteorAfter, meteorHidden, horiz, jumps, rawDive = 0, 0, 0, 0, 0, 0, 0
	local samples = 0
	local dodgers, throughRaw, throughDrawn, bumpJumps, closestDrawn = 0, 0, 0, 0, math.huge
	local dt = 1 / 60
	for kind, k in H.Kinds do
		for _ = 1, 40 do
			local pitch = math.rad(-20 + 40 * r01())
			local plan = Hazards.plan(H, kind, root, r01() * math.pi * 2, r01, pitch)
			local arrive = Hazards.positionAt(plan, plan.arriveAt)
			local prev = nil
			local sawRawBelow = false
			for i = 0, math.floor(plan.duration / dt) do
				local t = i * dt
				local lane = Hazards.positionAt(plan, t)
				local p, vis = Night.drawPosition(Config, plan, t, nil)
				samples += 1
				if t <= plan.arriveAt then
					if not vis or dist(p, lane) > 1e-9 then offLane += 1 end
				elseif k.impact then
					if vis then meteorAfter += 1 else meteorHidden += 1 end
					if lane.y < ground then sawRawBelow = true end
				else
					if not vis or p.y < arrive.y - 1e-9 then dive += 1 end
					if math.abs(p.x - lane.x) > 1e-9 or math.abs(p.z - lane.z) > 1e-9 then horiz += 1 end
					if lane.y < ground then sawRawBelow = true end
				end
				if prev and vis and prev.vis and dist(p, prev.p) > 1.3 * k.speed * dt + 1e-9 then jumps += 1 end
				prev = { p = p, vis = vis }
			end
			if sawRawBelow then rawDive += 1 end
			-- players who left the ring: 6.4 studs from the aim point in 8 directions (0 = on along the lane)
			local vh = math.sqrt(plan.velocity.x ^ 2 + plan.velocity.z ^ 2)
			for d = 0, 315, 45 do
				local a = math.atan2(plan.velocity.x / vh, plan.velocity.z / vh) + math.rad(d)
				local me = { x = root.x + math.sin(a) * 6.4, y = root.y, z = root.z + math.cos(a) * 6.4 }
				dodgers += 1
				local rawMin, drawnMin = math.huge, math.huge
				local last = nil
				for i = 0, math.floor(plan.duration / dt) do
					local t = i * dt
					local lane = Hazards.positionAt(plan, t)
					local p, vis = Night.drawPosition(Config, plan, t, me)
					if lane.y >= ground then rawMin = math.min(rawMin, dist(lane, me)) end
					if vis then
						-- the promise is for everything at or above the dodger's root height; only a meteorite
						-- goes lower (its last studs before the ground, by their feet)
						if p.y >= me.y - 1e-9 then drawnMin = math.min(drawnMin, dist(p, me)) end
						if last and dist(p, last) > 2.2 * k.speed * dt + 1e-9 then bumpJumps += 1 end
						last = p
					else
						last = nil
					end
				end
				if rawMin < 2 then throughRaw += 1 end
				if drawnMin < H.ClearStuds - 1e-6 then throughDrawn += 1 end
				closestDrawn = math.min(closestDrawn, drawnMin)
			end
		end
	end
	eq(offLane, 0, "until it arrives, a hazard is drawn exactly on the lane its warning showed (" .. samples .. " samples)")
	eq(dive, 0, "after it arrives, a flier swoops up and away: never drawn below its arrival height")
	eq(horiz, 0, "  and its horizontal path carries on unchanged")
	truthy(rawDive > 0, "(control) " .. rawDive .. " of the raw lanes fly on into the ground after arrival")
	eq(meteorAfter, 0, "a meteorite ends where it arrives (it strikes the ring): never drawn after arrival, so never under the ground")
	truthy(meteorHidden > 0, "  (" .. meteorHidden .. " samples after arrival, all hidden)")
	eq(jumps, 0, "no frame-to-frame jump (<= 1.3 x speed per frame)")
	print(string.format("  drawn paths: %d players who left the ring (8 directions); the raw lane passes within 2 studs of %d of them; the drawn path within %.1f of %d (closest %.2f)",
		dodgers, throughRaw, H.ClearStuds, throughDrawn, closestDrawn))
	truthy(throughRaw > 0, "(control) the raw lane flies through some players who left the ring")
	eq(throughDrawn, 0, "the drawn path never comes within ClearStuds of a player who left the ring")
	eq(bumpJumps, 0, "  and rising over them never jumps (<= 2.2 x speed per frame)")
	-- the hit rule is untouched: a player who stays put is still hit on the lane
	local plan = Hazards.plan(H, "crow", root, 0, function() return 0.5 end, 0)
	eq(Hazards.checkHit(plan, 0, plan.duration, root, H.PlayerRadius), true, "a player who stays put is still hit (the rule is the lane's, not the drawing's)")
end

--================================================================ the warning lasts as long as the hazard can hit

-- Second review of the night, 2026-09-30 (finding 1): the ring and the chip went at arriveAt and the drawing
-- swooped away (a meteorite vanished) at arriveAt, but Hazards.checkHit runs until `duration`, and the lane
-- is aimed at a point up to AimJitter from the ring's centre: a player standing on the far side of the ring
-- was knocked up to 0.2 s later with nothing on screen and nothing near them. The client now keeps the ring
-- and the warning up while Hazards.threatLive(plan, PlayerRadius, before) holds (the +1 Jump template's rule),
-- and Night.drawPosition's fifth argument `liveUntil` (the last flight time the warning was up) keeps the
-- drawing honest: until then the hazard stays on its lane's line (level, never lower than where it arrived,
-- so it never dives into the ground), and only then swoops away or, a meteorite, is gone.
-- This block replays the client's per-frame rule purely (the reviewer's probe, the game's own kinds).
do
	local Hazards = require("../src/shared/Hazards")
	local H = Config.Night.Hazards
	local PR = H.PlayerRadius
	local root = { x = 0, y = Config.World.RootHeight, z = 0 }
	local s0 = 930
	local function r01()
		s0 = (1664525 * s0 + 1013904223) % 4294967296
		return s0 / 4294967296
	end
	local function dist(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	local dt = 1 / 60
	local out = {}
	local lingerMax = 0
	for kind, k in H.Kinds do
		local o = { hits = 0, late = 0, notLive = 0, hidden = 0, far = 0, oldHidden = 0, oldFar = 0, offLine = 0, below = 0, afterVisible = 0, jumps = 0 }
		out[kind] = o
		for i = 1, 300 do
			local pitch = if i % 3 == 0 then 0 else math.rad(-20 + 60 * r01())
			local plan0 = Hazards.plan(H, kind, root, r01() * math.pi * 2, r01, pitch)
			local zone = Hazards.zone(plan0, PR)
			local arriveY = Hazards.positionAt(plan0, plan0.arriveAt).y
			-- players who stand still inside the ring from the lock on (a polar grid, the far side included)
			for ri = 1, 6 do
				for ai = 0, 7 do
					local rr = zone.radius * ri / 6 * 0.999
					local a = ai / 8 * 2 * math.pi + r01() * 0.3
					local me = { x = zone.x + rr * math.cos(a), y = root.y, z = zone.z + rr * math.sin(a) }
					local plan = table.clone(plan0)
					plan.t, plan.hit = 0, false
					local liveUntil = 0
					local prev = nil
					while plan.t < plan.duration do
						local before = plan.t
						plan.t += dt
						-- the client's order: is the warning up this frame (from `before`), then the hit test
						local live = Hazards.threatLive(plan, PR, before)
						if live then liveUntil = plan.t end
						if Hazards.checkHit(plan, before, plan.t, me, PR) then
							plan.hit = true
							o.hits += 1
							if plan.t > plan.arriveAt then o.late += 1 end
							if not live then o.notLive += 1 end
							local p, vis = Night.drawPosition(Config, plan, plan.t, nil, liveUntil)
							if not vis then o.hidden += 1 elseif dist(p, me) > zone.radius + k.speed * dt + 1e-6 then o.far += 1 end
							local q, qvis = Night.drawPosition(Config, plan, plan.t, nil)
							if not qvis then o.oldHidden += 1 elseif dist(q, me) > zone.radius + k.speed * dt + 1e-6 then o.oldFar += 1 end
						end
						local p, vis = Night.drawPosition(Config, plan, plan.t, nil, liveUntil)
						local lane = Hazards.positionAt(plan, plan.t)
						if plan.t > plan.arriveAt and plan.t <= liveUntil then
							-- lingering: on the lane's line, level, never lower than where it arrived
							if not vis or math.abs(p.x - lane.x) > 1e-9 or math.abs(p.z - lane.z) > 1e-9 then o.offLine += 1 end
							if vis and p.y < arriveY - 1e-9 then o.below += 1 end
						end
						if plan.t > math.max(plan.arriveAt, liveUntil) and k.impact and vis then o.afterVisible += 1 end
						if prev and vis and prev.vis and dist(p, prev.p) > 1.3 * k.speed * dt + 1e-9 then o.jumps += 1 end
						prev = { p = p, vis = vis }
					end
					lingerMax = math.max(lingerMax, liveUntil - plan.arriveAt)
				end
			end
		end
	end
	local total = { hits = 0, late = 0, notLive = 0, hidden = 0, far = 0, oldHidden = 0, oldFar = 0, offLine = 0, below = 0, afterVisible = 0, jumps = 0 }
	for kind, o in out do
		print(string.format("  %-9s %6d hits, %4d after arrival; old rule: %4d with the model hidden, %4d drawn farther than the ring; new: %d, %d",
			kind, o.hits, o.late, o.oldHidden, o.oldFar, o.hidden, o.far))
		for key, v in o do total[key] += v end
	end
	truthy(total.late > 0, "(set-up) some standers inside the ring are hit AFTER arrival (" .. total.late .. " of " .. total.hits .. ")")
	truthy(total.oldHidden + total.oldFar > 0, "(control) the old drawing had the model gone or away at some of those hits (" .. total.oldHidden .. " hidden, " .. total.oldFar .. " farther than the ring)")
	eq(total.notLive, 0, "every hit lands on a frame where the ring and the warning are up (Hazards.threatLive)")
	eq(total.hidden, 0, "at every hit the hazard is drawn (a meteorite has not vanished yet)")
	eq(total.far, 0, "at every hit the drawn hazard is within the ring's radius of the player (plus one frame of flight)")
	eq(total.offLine, 0, "while the ring lingers after arrival, the drawing stays on the lane's line")
	eq(total.below, 0, "  level: never lower than where it arrived (it does not dive into the ground)")
	eq(total.afterVisible, 0, "a meteorite is gone once the warning is (it struck)")
	eq(total.jumps, 0, "no frame-to-frame jump in the drawing (<= 1.3 x speed per frame)")
	print(string.format("  the ring lingers after arrival at most %.2f s (stationary players inside it)", lingerMax))
	truthy(lingerMax > 0 and lingerMax < 1.5, string.format("the ring lingers after arrival, and never more than 1.5 s (%.2f s)", lingerMax))
	-- liveUntil nil or at/before arrival is exactly the old drawing
	local plan = Hazards.plan(H, "bat", root, 1, function() return 0.3 end, math.rad(20))
	local same = 0
	for i = 0, 200 do
		local t = i / 50
		local a, av = Night.drawPosition(Config, plan, t, nil)
		local b, bv = Night.drawPosition(Config, plan, t, nil, plan.arriveAt - 0.5)
		if av == bv and dist(a, b) < 1e-12 then same += 1 end
	end
	eq(same, 201, "liveUntil at or before arrival draws exactly as before")
end

--================================================================ the ground's edge

do
	local rect = { cx = 100, cz = 0, sx = 400, sz = 260 }
	near(Night.edgeDistance(rect, 100, 0), 130, 1e-9, "the centre of a 400 x 260 ground is 130 studs from its nearest edge")
	near(Night.edgeDistance(rect, 290, 0), 10, 1e-9, "10 studs from the +x end")
	near(Night.edgeDistance(rect, 100, -125), 5, 1e-9, "5 studs from the -z edge")
	near(Night.edgeDistance(rect, 310, 0), -10, 1e-9, "10 studs past the +x end is -10")
	eq(Night.edgeDistance(nil, 0, 0), math.huge, "no ground known: no edge")
end

--================================================================ critters keep out of a camp by what they DRAW
-- A critter is tested at its centre, but it is drawn with wings, a bob and a halo: a wisp's halo (2.4 studs)
-- turned 45 degrees spans 1.7 studs each way along a world axis, and its bob moves it 1.2 more, so its drawn
-- footprint reaches 2.9 studs from the centre on each axis. The first night's test was a 3-stud CIRCLE,
-- which near a rect's corner lets that box in diagonally: check_stealacryptid_night once caught a WispHalo
-- 0.2 studs into the corridor's corner (1 run in about 30). Night.critterClear tests the box.

do
	local okFn = type(Night.critterClear) == "function"
	truthy(okFn, "Night.critterClear exists")
	if okFn then
		local DRAWN = 1.2 + 1.2 * math.sqrt(2) -- the wisp: bob + a 45-degree halo's half extent (the widest critter)
		local circleLets, boxLets, tried = 0, 0, 0
		for _, r in Night.keepOut(Config) do
			for _, c in { { r.x0, r.z0, -1, -1 }, { r.x1, r.z0, 1, -1 }, { r.x0, r.z1, -1, 1 }, { r.x1, r.z1, 1, 1 } } do
				for dx = 0, 4, 0.1 do
					for dz = 0, 4, 0.1 do
						local x, z = c[1] + c[3] * dx, c[2] + c[4] * dz
						local drawnClear = Night.boxClearOfCamp(Config, x - DRAWN, x + DRAWN, z - DRAWN, z + DRAWN)
						tried += 1
						if Night.clearOfCamp(Config, x, z, 3) and not drawnClear then circleLets += 1 end
						if Night.critterClear(Config, x, z, 3) and not drawnClear then boxLets += 1 end
					end
				end
			end
		end
		truthy(circleLets > 0, "(control) the old 3-stud circle lets a drawn wisp into a keep-out corner at " .. circleLets .. " of " .. tried .. " spots")
		eq(boxLets, 0, "critterClear with reach 3 never lets a drawn critter (reach 2.9) into the keep-out")
		eq(Night.critterClear(Config, 36, 56, 3), false, "a critter in the yard is not clear")
		eq(Night.critterClear(Config, 36, -300, 3), true, "one far behind the corridor is")
	end
end

--================================================================ the world's edge: a ravine, never a false floor
-- The server's Ground is the only floor at home; past its edge is the void. The first night laid one
-- 2 048-stud local "forest floor" under everything, 1.1 studs below the Ground's top: the edge vanished,
-- and a player who walked onto the grass beyond it fell through the world (review 2026-09-24, finding
-- 1). The far floor is now a FRAME around a hole: the Ground grown by Ravine.Width is left empty (a
-- gully no one can jump across, with cliff faces), and the forest floor starts beyond it.

do
	local R = Config.Night.Ravine
	local okFn = type(Night.farGroundRects) == "function" and type(R) == "table"
	truthy(okFn, "Night.farGroundRects and Config.Night.Ravine exist")
	if okFn then
		local function covers(s, x, z)
			return math.abs(x - s.cx) < s.sx / 2 and math.abs(z - s.cz) < s.sz / 2
		end
		-- nothing known yet (a client that started before the road): one slab round the origin, no hole
		local one = Night.farGroundRects(nil, R)
		eq(#one, 1, "no road known: a single far floor slab")
		eq(one[1] and one[1].sx, 2 * R.FarHalf, "...FarHalf x 2 wide")
		-- the road at 8, 12 and 50 players (504 / 696 / 2 520 studs), and an off-centre odd one
		local roads = {
			{ cx = 156, cz = 0, sx = 504, sz = 260 },
			{ cx = 252, cz = 0, sx = 696, sz = 260 },
			{ cx = 1164, cz = 0, sx = 2520, sz = 260 },
			{ cx = -40, cz = 30, sx = 100, sz = 80 },
		}
		for _, rect in roads do
			local tag = string.format("road %d x %d", rect.sx, rect.sz)
			local slabs = Night.farGroundRects(rect, R)
			eq(#slabs, 4, tag .. ": four slabs frame the ravine")
			local hx, hz = rect.sx / 2 + R.Width, rect.sz / 2 + R.Width
			local ox = math.max(R.FarHalf, hx + R.MinFar)
			local oz = math.max(R.FarHalf, hz + R.MinFar)
			local area, positive = 0, true
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, s in slabs do
				if not (s.sx > 0 and s.sz > 0) then positive = false end
				area += s.sx * s.sz
				minX, maxX = math.min(minX, s.cx - s.sx / 2), math.max(maxX, s.cx + s.sx / 2)
				minZ, maxZ = math.min(minZ, s.cz - s.sz / 2), math.max(maxZ, s.cz + s.sz / 2)
			end
			truthy(positive, tag .. ": every slab has a positive size")
			near(area, (2 * ox) * (2 * oz) - (2 * hx) * (2 * hz), 1e-6, tag .. ": the slabs cover exactly the frame (outer box minus the hole)")
			near(minX, rect.cx - ox, 1e-9, tag .. ": far floor reaches FarHalf (or MinFar past the ravine) toward -x")
			near(maxX, rect.cx + ox, 1e-9, tag .. ": ...+x")
			near(minZ, rect.cz - oz, 1e-9, tag .. ": ...-z")
			near(maxZ, rect.cz + oz, 1e-9, tag .. ": ...+z")
			-- every point: in the hole covered by nothing, in the frame by exactly one slab
			local bad, badAt = 0, nil
			local step = 7.3
			local x = rect.cx - ox + 0.37
			while x < rect.cx + ox do
				local z = rect.cz - oz + 0.61
				while z < rect.cz + oz do
					local n = 0
					for _, s in slabs do if covers(s, x, z) then n += 1 end end
					local inHole = math.abs(x - rect.cx) < hx and math.abs(z - rect.cz) < hz
					local onRim = math.abs(math.abs(x - rect.cx) - hx) < 1e-6 or math.abs(math.abs(z - rect.cz) - hz) < 1e-6
					if not onRim and n ~= (if inHole then 0 else 1) then
						bad += 1
						badAt = badAt or string.format("(%.1f, %.1f) covered %d times", x, z, n)
					end
					z += step
				end
				x += step
			end
			eq(bad, 0, tag .. ": the hole is empty and the frame singly covered (" .. tostring(badAt) .. ")")
			-- the ravine band itself, walked round the Ground's edge 0.25 .. Width - 0.25 studs out
			local inRavine, walked = 0, 0
			for _, d in { 0.25, 1, 5, 12, R.Width - 0.25 } do
				for t = 0, 1, 0.05 do
					for _, p in {
						{ rect.cx - rect.sx / 2 + rect.sx * t, rect.cz - rect.sz / 2 - d },
						{ rect.cx - rect.sx / 2 + rect.sx * t, rect.cz + rect.sz / 2 + d },
						{ rect.cx - rect.sx / 2 - d, rect.cz - rect.sz / 2 + rect.sz * t },
						{ rect.cx + rect.sx / 2 + d, rect.cz - rect.sz / 2 + rect.sz * t },
					} do
						walked += 1
						for _, s in slabs do if covers(s, p[1], p[2]) then inRavine += 1 end end
					end
				end
			end
			eq(inRavine, 0, tag .. ": no far floor anywhere in the ravine (" .. walked .. " points up to " .. (R.Width - 0.25) .. " studs past the edge)")
			-- and the forest floor is there just beyond it, on every side
			local beyond = 0
			for _, p in {
				{ rect.cx, rect.cz - hz - 1 }, { rect.cx, rect.cz + hz + 1 }, { rect.cx - hx - 1, rect.cz }, { rect.cx + hx + 1, rect.cz },
			} do
				for _, s in slabs do if covers(s, p[1], p[2]) then beyond += 1 end end
			end
			eq(beyond, 4, tag .. ": the far floor starts 1 stud past the ravine on all four sides")
		end
	end
end

--================================================================ a knock never carries anyone off the world
-- The edge margin stops LAUNCHES near the edge, but a player can walk toward the edge while a hazard
-- flies, stop in the ring, and be pushed on toward it: 24 of 24 such hits landed 17.8-19.4 studs from
-- the edge, 19-20 of them with a frictionless slide ending past it (review 2026-09-24, finding 2).
-- Night.limitKnock cuts the OUTWARD part of the push, axis by axis, so that the slide (velocity x
-- KnockSeconds, the same upper bound as the edge margin) ends at least PlayerRadius inside the Ground.

do
	local okFn = type(Night.limitKnock) == "function"
	truthy(okFn, "Night.limitKnock exists")
	if okFn then
		local H = Config.Night.Hazards
		local T, keep = H.KnockSeconds, H.PlayerRadius
		local rect = { cx = 252, cz = 0, sx = 696, sz = 260 }
		local X0, X1, Z0, Z1 = rect.cx - rect.sx / 2, rect.cx + rect.sx / 2, rect.cz - rect.sz / 2, rect.cz + rect.sz / 2
		-- the reviewer's hit: 17.8 studs from the -x end, pushed (-28.1, 8, 10.5)
		local pos = { x = X0 + 17.8, y = 3, z = 0 }
		local kv = Night.limitKnock(rect, pos, { x = -28.1, y = 8, z = 10.5 }, T, keep)
		near(pos.x + kv.x * T, X0 + keep, 1e-9, "the reviewer's hit: the slide now stops PlayerRadius inside the -x end")
		near(kv.z, 10.5, 1e-12, "...the push along the edge is untouched")
		near(kv.y, 8, 1e-12, "...and so is the lift")
		-- no road known: nothing to cut
		local same = Night.limitKnock(nil, pos, { x = -28.1, y = 8, z = 10.5 }, T, keep)
		eq(same.x, -28.1, "no ground known: the push is unchanged")
		-- far from every edge: exactly the template's push
		local mid = Night.limitKnock(rect, { x = 252, y = 3, z = 0 }, { x = -34, y = 8, z = 0.5 }, T, keep)
		eq(mid.x, -34, "in the middle of the road a full knock is untouched (x)")
		eq(mid.z, 0.5, "(z)")
		-- already inside the keep band: pushed no further out, inward still allowed
		local at = { x = X1 - 1, y = 3, z = Z1 - 0.5 }
		local k2 = Night.limitKnock(rect, at, { x = 30, y = 8, z = 5 }, T, keep)
		eq(k2.x, 0, "1 stud from the +x end: no push further out along x")
		eq(k2.z, 0, "0.5 studs from the +z edge: no push further out along z")
		local k3 = Night.limitKnock(rect, at, { x = -30, y = 8, z = -5 }, T, keep)
		eq(k3.x, -30, "...but a push back inward is kept (x)")
		eq(k3.z, -5, "(z)")
		-- every position (a grid that hugs all four edges and corners), every heading, soft and hard knocks
		local cases, offEnd, grew, flipped, changedFar, lostLift = 0, 0, 0, 0, 0, 0
		local worst = math.huge
		local xs, zs = {}, {}
		for _, d in { 0, 0.5, 1.4, 2, 5, 10, 17.8, 20, 25, 31, 40, 80 } do
			table.insert(xs, X0 + d); table.insert(xs, X1 - d)
			table.insert(zs, Z0 + d); table.insert(zs, Z1 - d)
		end
		table.insert(xs, rect.cx); table.insert(zs, rect.cz)
		for _, px in xs do
			for _, pz in zs do
				for deg = 0, 355, 7.5 do
					for _, mag in { 24, 30.6, 34 } do
						cases += 1
						local a = math.rad(deg)
						local v0 = { x = math.cos(a) * mag, y = 8, z = math.sin(a) * mag }
						local p = { x = px, y = 3, z = pz }
						local v = Night.limitKnock(rect, p, v0, T, keep)
						local ex, ez = px + v.x * T, pz + v.z * T
						-- the slide's end: inside the keep band's inner rect, or (starting in the band) no farther out per axis
						local function axisOk(e, s, c, half)
							local lim = half - keep
							return math.abs(e - c) <= math.max(lim, math.abs(s - c)) + 1e-9
						end
						if not (axisOk(ex, px, rect.cx, rect.sx / 2) and axisOk(ez, pz, rect.cz, rect.sz / 2)) then offEnd += 1 end
						if Night.edgeDistance(rect, px, pz) >= keep then worst = math.min(worst, Night.edgeDistance(rect, ex, ez)) end
						if math.abs(v.x) > math.abs(v0.x) + 1e-12 or math.abs(v.z) > math.abs(v0.z) + 1e-12 then grew += 1 end
						if v.x * v0.x < 0 or v.z * v0.z < 0 then flipped += 1 end
						if v.y ~= v0.y then lostLift += 1 end
						if Night.edgeDistance(rect, px, pz) >= mag * T + keep and (v.x ~= v0.x or v.z ~= v0.z) then changedFar += 1 end
					end
				end
			end
		end
		eq(offEnd, 0, string.format("%d knocks: no slide ends outside the Ground's inner keep band (or farther out than it started)", cases))
		truthy(worst >= keep - 1e-9, string.format("...from anywhere at least PlayerRadius inside, every slide ends at least PlayerRadius inside (closest %.2f)", worst))
		eq(grew, 0, "no push is made stronger along any axis")
		eq(flipped, 0, "no push is turned around (cut to zero at most)")
		eq(lostLift, 0, "the lift is never changed")
		eq(changedFar, 0, "a knock whose slide cannot reach the keep band is exactly the template's")
		print(string.format("  knocks: %d cases (every edge band, 48 headings, 3 strengths); a slide from PlayerRadius or more inside ends at least %.2f studs inside", cases, worst))
	end
end

--================================================================ the camera's view of a camp
-- Camp scenery (a ring of pines 80-150 studs out, redwoods 90-175) keeps out of the camp and the
-- corridor behind the gate, but a raider who zooms out and orbits looks at the camp across it: a pine
-- crown or redwood trunk hid the raider in 15 of 900 far-zoom camera spots per camp (review 2026-09-24,
-- finding 3). Every line of sight from the camera to any point of the camp, at any height, projects into
-- the 2-D convex hull of the camera's position and the camp's rect; a part whose footprint misses that
-- hull cannot hide anything of the camp. NightArt hides every part inside it.

do
	local okFn = type(Night.viewHull) == "function" and type(Night.boxOverlapsHull) == "function" and type(Night.hidesCamp) == "function"
	truthy(okFn, "Night.viewHull, Night.boxOverlapsHull and Night.hidesCamp exist")
	if okFn then
		local camp = Night.keepOut(Config)[1]
		local cxm, czm = (camp.x0 + camp.x1) / 2, (camp.z0 + camp.z1) / 2
		local function cross(o, a, b) return (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x) end
		local function inside(poly, x, z)
			for i = 1, #poly do
				local a, b = poly[i], poly[i % #poly + 1]
				if cross(a, b, { x = x, z = z }) < -1e-9 then return false end
			end
			return true
		end
		-- the hull: convex, counter-clockwise, and holding the camera and all four corners
		local Rng = require("../src/shared/Rng") -- (the CLI has no Roblox Random)
		local lcg = Rng.new(20260924)
		local rng = { NextNumber = function(_, a, b) return a + (b - a) * lcg:next() end }
		local hullBad = 0
		for i = 1, 400 do
			local px, pz = cxm + rng:NextNumber(-400, 400), czm + rng:NextNumber(-400, 400)
			if i <= 3 then px, pz = cxm, czm end -- the camera inside the camp: the hull is the camp itself
			local poly = Night.viewHull(px, pz, camp.x0, camp.x1, camp.z0, camp.z1)
			local ok = #poly >= 3
			for j = 1, #poly do
				if cross(poly[j], poly[j % #poly + 1], poly[(j + 1) % #poly + 1]) <= 0 then ok = false end
			end
			for _, q in { { px, pz }, { camp.x0, camp.z0 }, { camp.x1, camp.z0 }, { camp.x1, camp.z1 }, { camp.x0, camp.z1 } } do
				if not inside(poly, q[1], q[2]) then ok = false end
			end
			if not ok then hullBad += 1 end
		end
		eq(hullBad, 0, "400 cameras: the view hull is convex, counter-clockwise and holds the camera and the camp")
		eq(#Night.viewHull(cxm, czm, camp.x0, camp.x1, camp.z0, camp.z1), 4, "a camera inside the camp: the hull is the camp's own four corners")
		-- SAT against sampling: a box with any sampled point inside the polygon must overlap it
		local satMiss = 0
		for _ = 1, 400 do
			local px, pz = cxm + rng:NextNumber(-300, 300), czm + rng:NextNumber(-300, 300)
			local poly = Night.viewHull(px, pz, camp.x0, camp.x1, camp.z0, camp.z1)
			local bx, bz = cxm + rng:NextNumber(-250, 250), czm + rng:NextNumber(-250, 250)
			local hw, hd = rng:NextNumber(0.5, 30), rng:NextNumber(0.5, 30)
			local any = false
			for u = 0, 1, 0.125 do
				for w = 0, 1, 0.125 do
					if inside(poly, bx - hw + 2 * hw * u, bz - hd + 2 * hd * w) then any = true end
				end
			end
			if any and not Night.boxOverlapsHull(poly, bx - hw, bx + hw, bz - hd, bz + hd) then satMiss += 1 end
		end
		eq(satMiss, 0, "400 random boxes: every box with a point inside the hull is found to overlap it")
		-- named cases (pocket-local; the camp centre is (36, 56))
		local function hides(cx, cz, x, z, r) return Night.hidesCamp(Config, cx, cz, x - r, x + r, z - r, z + r) end
		eq(hides(36, 56, -60, 56, 6), false, "a camera inside the camp: a pine outside it hides nothing")
		eq(hides(-150, 56, -60, 56, 6), true, "a camera far to the -x side: a pine between it and the camp hides it")
		eq(hides(-150, 56, -60, 220, 6), false, "...a pine well off that line does not")
		eq(hides(-150, 56, 160, 56, 6), false, "...a pine beyond the camp does not")
		eq(hides(-150, 56, -230, 56, 6), false, "...a pine behind the camera does not")
		eq(hides(36, -40, 36, 0, 3), true, "the gate camera: anything in the corridor in front of it would hide the gate")
		eq(hides(36, -40, 110, -20, 6), false, "the gate camera: a cactus off to the side does not")
		eq(hides(36, 400, 36, 250, 20), true, "a camera far behind the cages: Nessie between it and the back fence is hidden")
		-- soundness: 6 000 random cameras (up to 400 studs out, Roblox's default maximum zoom) and random parts
		-- outside the camp. Whenever a straight segment from the camera to ANY sampled point of the camp crosses
		-- the part's footprint, hidesCamp must say so (it may say so more often: it is conservative).
		local targets = {}
		for u = 0, 1, 1 / 12 do
			for w = 0, 1, 1 / 14 do
				table.insert(targets, { camp.x0 + (camp.x1 - camp.x0) * u, camp.z0 + (camp.z1 - camp.z0) * w })
			end
		end
		local function segHitsBox(ax, az, bx, bz, x0, x1, z0, z1)
			local t0, t1 = 0, 1
			local dx, dz = bx - ax, bz - az
			for _, s in { { -dx, ax - x0 }, { dx, x1 - ax }, { -dz, az - z0 }, { dz, z1 - az } } do
				local p, q = s[1], s[2]
				if math.abs(p) < 1e-12 then
					if q < 0 then return false end
				else
					local r = q / p
					if p < 0 then t0 = math.max(t0, r) else t1 = math.min(t1, r) end
					if t0 > t1 then return false end
				end
			end
			return true
		end
		local blocking, missed, flagged = 0, 0, 0
		for _ = 1, 6000 do
			local ang, dist = rng:NextNumber(0, 2 * math.pi), rng:NextNumber(20, 400)
			local px, pz = cxm + math.sin(ang) * (dist + 50), czm + math.cos(ang) * (dist + 60)
			local bx, bz = cxm + rng:NextNumber(-350, 350), czm + rng:NextNumber(-350, 350)
			local hw, hd = rng:NextNumber(1, 25), rng:NextNumber(1, 25)
			local x0, x1, z0, z1 = bx - hw, bx + hw, bz - hd, bz + hd
			local outsideCamp = x1 < camp.x0 or x0 > camp.x1 or z1 < camp.z0 or z0 > camp.z1
			local camOutsidePart = not (px > x0 and px < x1 and pz > z0 and pz < z1)
			if outsideCamp and camOutsidePart then
				local hits = false
				for _, t in targets do
					if segHitsBox(px, pz, t[1], t[2], x0, x1, z0, z1) then hits = true; break end
				end
				local said = Night.hidesCamp(Config, px, pz, x0, x1, z0, z1)
				if said then flagged += 1 end
				if hits then
					blocking += 1
					if not said then missed += 1 end
				end
			end
		end
		truthy(blocking >= 100, "the soundness sweep met real blockers (" .. blocking .. ")")
		eq(missed, 0, string.format("of %d parts standing on some line of sight to the camp, hidesCamp missed none (%d flagged in all)", blocking, flagged))
		-- ...and tight: the hull IS the union of the camera's lines of sight to the rect, so what it flags is (up to
		-- the targets' 6-stud grid) exactly what stands on one. A looser test (a box round the hull, say) would hide
		-- scenery that hides nothing.
		truthy(flagged <= blocking + math.ceil(blocking * 0.05), string.format("hidesCamp is tight: %d flagged, %d on a sampled line of sight", flagged, blocking))
		print(string.format("  camp view: %d random parts stood on a line of sight from a camera 70-460 studs out to the camp; hidesCamp flagged all of them (%d flagged in all)", blocking, flagged))
	end
end

--================================================================ the rest campfire stays on the Ground
-- Second review of the night, 2026-09-30, finding 3: the fire went Campfire.Distance ahead of the resting player
-- with no look at the Ground, so at the cliff it floated over the ravine. Night.campfireSpot puts it at the
-- first of ahead / behind / right / left whose whole ring (Campfire.Radius) is on the Ground; if none is (a
-- corner nook), the one of those, pulled onto the Ground, that is farthest from the player.
do
	local C = Config.Night.Campfire
	local PR = Config.Night.Hazards.PlayerRadius
	local okFn = type(Night.campfireSpot) == "function" and type(C.Distance) == "number" and type(C.Radius) == "number"
	truthy(okFn, "Night.campfireSpot, Campfire.Distance and Campfire.Radius exist")
	if okFn then
		truthy(C.Distance >= C.Radius + PR, "the fire's ring never reaches the sitter (Distance >= Radius + PlayerRadius)")
		local rect = { cx = 252, cz = 0, sx = 696, sz = 260 }
		local function inside(x, z)
			return math.abs(x - rect.cx) <= rect.sx / 2 - C.Radius + 1e-9 and math.abs(z - rect.cz) <= rect.sz / 2 - C.Radius + 1e-9
		end
		-- far from every edge: exactly ahead, as before
		local x, z = Night.campfireSpot(Config, rect, 100, 10, 0, 1)
		near(x, 100, 1e-9, "mid-road: the fire is straight ahead (x)")
		near(z, 10 + C.Distance, 1e-9, "mid-road: the fire is straight ahead (z)")
		-- the reviewer's spots: 0.5 and 2.0 studs from the back edge, facing the ravine
		for _, d in { 0.5, 2.0 } do
			local fx, fz = Night.campfireSpot(Config, rect, 300, 130 - d, 0, 1)
			truthy(inside(fx, fz), string.format("%.1f studs from the back edge facing out: the whole ring is on the Ground (%.2f, %.2f)", d, fx, fz))
			near(math.sqrt((fx - 300) ^ 2 + (fz - (130 - d)) ^ 2), C.Distance, 1e-9, string.format("  and it keeps its distance (%.1f)", d))
		end
		-- no road known: straight ahead (the Ground cannot be judged)
		local nx, nz = Night.campfireSpot(Config, nil, 5, 5, 1, 0)
		near(nx, 5 + C.Distance, 1e-9, "no Ground known: straight ahead")
		near(nz, 5, 1e-9, "no Ground known: straight ahead (z)")
		-- a sweep: every point of the Ground (edges and corners included), 24 headings
		local s0 = 3009
		local function r01()
			s0 = (1664525 * s0 + 1013904223) % 4294967296
			return s0 / 4294967296
		end
		local out, notAhead, aheadFits, tooClose, n = 0, 0, 0, 0, 0
		for i = 1, 20000 do
			local px, pz
			if i % 2 == 0 then
				px, pz = rect.cx - rect.sx / 2 + rect.sx * r01(), rect.cz - rect.sz / 2 + rect.sz * r01()
			else
				-- hug an edge or a corner
				local e = 8 * r01()
				px = if r01() < 0.5 then rect.cx - rect.sx / 2 + e else rect.cx + rect.sx / 2 - e
				pz = if r01() < 0.5 then rect.cz - rect.sz / 2 + 8 * r01() else rect.cz + rect.sz / 2 - 8 * r01()
				if r01() < 0.5 then px = rect.cx - rect.sx / 2 + rect.sx * r01() else pz = rect.cz - rect.sz / 2 + rect.sz * r01() end
			end
			local a = (i % 24) / 24 * 2 * math.pi + r01() * 0.1
			local lx, lz = math.sin(a), math.cos(a)
			local fx, fz = Night.campfireSpot(Config, rect, px, pz, lx, lz)
			n += 1
			if not inside(fx, fz) then out += 1 end
			local ax, az = px + lx * C.Distance, pz + lz * C.Distance
			if inside(ax, az) then
				aheadFits += 1
				if math.abs(fx - ax) > 1e-9 or math.abs(fz - az) > 1e-9 then notAhead += 1 end
			end
			if math.sqrt((fx - px) ^ 2 + (fz - pz) ^ 2) < C.Radius + PR - 1e-9 then tooClose += 1 end
		end
		eq(out, 0, "sweep: the whole ring is on the Ground at every one of " .. n .. " spots")
		eq(notAhead, 0, "sweep: wherever straight ahead fits (" .. aheadFits .. "), that is where it goes")
		print(string.format("  campfire sweep: %d spots, ahead fits at %d; the ring reaches the sitter at %d (corner nooks only)", n, aheadFits, tooClose))
	end
end

--================================================================ habitats: your own cages

do
	local function cage(sp, tier, unlocked)
		return { sp = sp, tier = tier, unlocked = unlocked ~= false }
	end
	local cages = {}
	for col = 1, 9 do cages[col] = cage("", 0, col >= 3 and col <= 7) end
	cages[5] = cage("jackalope", 1)
	cages[4] = cage("nessie", 3)
	cages[6] = cage("mothman", 3)
	cages[3] = cage("bigfoot", 4)
	cages[7] = cage("hodag", 1)
	cages[1] = cage("dogman", 2, false) -- a locked cage never shows a habitat
	cages[8] = cage("yeti", 2)          -- not a species this game has
	local hab = Night.habitats(Config, cages, 1)
	local n = 0
	for _ in hab do n += 1 end
	eq(n, 5, "one habitat per occupied, unlocked cage of a known species")
	eq(hab[1], nil, "a locked cage has none")
	eq(hab[8], nil, "an unknown species has none")
	eq(hab[2], nil, "an empty cage has none")
	eq(hab[5].kind, Config.Night.Habitats.Species.jackalope, "the Jackalope gets its habitat kind")
	eq(hab[3].lit, true, "with one emitter allowed, the Mythic habitat is the one lit")
	eq(hab[4].lit, false, "  not a Legendary")
	local lit = 0
	for _, x in hab do if x.lit then lit += 1 end end
	eq(lit, 1, "exactly one lit")
	-- two emitters: Mythic, then the Legendary nearer the centre in CageOrder (4 before 6)
	hab = Night.habitats(Config, cages, 2)
	eq(hab[3].lit and hab[4].lit and not hab[6].lit, true, "two lit: the Mythic, then the Legendary first in CageOrder")
	hab = Night.habitats(Config, cages, 0)
	lit = 0
	for _, x in hab do if x.lit then lit += 1 end end
	eq(lit, 0, "none lit when no emitter is allowed")
	-- glow brightens with the tier
	hab = Night.habitats(Config, cages, 1)
	truthy(hab[3].glow < hab[4].glow and hab[4].glow < hab[5].glow, "a rarer habitat glows brighter (lower transparency)")
	eq(next(Night.habitats(Config, nil, 1)), nil, "no cages: no habitats")
	-- every species this game has maps to a habitat the art knows
	for _, s in Config.Species do
		truthy(type(Config.Night.Habitats.Species[s.id]) == "string", s.id .. " has a habitat kind")
	end
end

--================================================================ text on the HUD chip

do
	local T = Config.Night.Text
	eq(Night.sideText("left"), "the left", "left")
	eq(Night.sideText("right"), "the right", "right")
	eq(Night.sideText("ahead"), "ahead", "ahead")
	eq(Night.sideText("behind"), "behind", "behind")
	eq(Night.sideText("sideways"), "ahead", "an unknown bearing reads ahead")
	local longest = 0
	for kind, k in Config.Night.Hazards.Kinds do
		for _, b in { "left", "right", "ahead", "behind" } do
			for _, locked in { false, true } do
				local s = Night.alertText(Config, kind, b, locked)
				longest = math.max(longest, #s)
				truthy(#s <= T.ChipMaxChars, string.format("alert '%s' fits the chip (%d <= %d)", s, #s, T.ChipMaxChars))
				truthy(not string.find(s, "[\128-\255]"), "alert '" .. s .. "' is ASCII")
				if locked then
					truthy(string.find(string.lower(s), "red ring", 1, true) ~= nil, "a locked alert says to leave the red ring")
				else
					truthy(string.find(s, Night.sideText(b), 1, true) ~= nil, "an incoming alert says where it comes from")
				end
				truthy(string.find(string.lower(s), string.lower(k.label), 1, true) ~= nil, "the alert names the " .. kind)
			end
		end
	end
	print(string.format("  longest hazard alert: %d characters (chip limit %d)", longest, T.ChipMaxChars))
	eq(Night.restText(Config, "manual"), T.Resting, "manual rest text")
	eq(Night.restText(Config, "idle"), T.Idle, "idle rest text")
	eq(Night.restText(Config, "queued"), T.Queued, "queued rest text")
	eq(Night.restText(Config, nil), "", "not resting: no text")
	truthy(string.find(string.lower(T.Resting), "poacher", 1, true) ~= nil, "the rest text says poachers still come (rest does not protect income)")
	for _, s in { T.Resting, T.Idle, T.Queued } do
		truthy(#s <= T.ChipMaxChars, "'" .. s .. "' fits the chip")
	end
	eq(Night.restLabel(Config, true, false), T.RestingButton, "resting: the button says so")
	eq(Night.restLabel(Config, false, true), T.QueuedButton, "queued: the button says so")
	eq(Night.restLabel(Config, false, false), T.RestButton, "awake: Rest")
end

--================================================================ the budget is capped in code
-- Second review of the night, 2026-09-30, finding 5: Config.Night.Budget was only asserted by the checks. Now
-- every piece of scenery, critter and habitat is ADMITTED against Budget minus Budget.Reserve (what the
-- always-shown pieces keep: a hazard, its lane and ring, the campfire, the weather host) before it is drawn,
-- and the particle emitters are capped every frame in priority order (Night.capEmitters).
do
	local okFns = type(Night.budgetGate) == "function" and type(Night.admit) == "function" and type(Night.release) == "function"
		and type(Night.capEmitters) == "function"
	truthy(okFns, "Night.budgetGate, admit, release and capEmitters exist")
	if okFns then
		local B = Config.Night.Budget
		local g = Night.budgetGate(Config)
		eq(g.limit.parts, B.MaxLocalParts - B.Reserve.parts, "gated parts = MaxLocalParts - Reserve.parts")
		eq(g.limit.beams, B.MaxBeams - B.Reserve.beams, "gated beams = MaxBeams - Reserve.beams")
		eq(g.limit.trails, B.MaxTrails - B.Reserve.trails, "gated trails = MaxTrails - Reserve.trails")
		eq(g.limit.lights, B.MaxLights - B.Reserve.lights, "gated lights = MaxLights - Reserve.lights")
		-- admit until full; a refused item costs nothing; a release makes room again
		local small = { parts = 10, beams = 1, trails = 0, lights = 0 }
		local n = 0
		while Night.admit(g, small) do n += 1 end
		eq(n, math.min(math.floor(g.limit.parts / 10), g.limit.beams), "items are admitted until one budget would overflow")
		eq(g.refused, 1, "the one that would overflow is refused and counted")
		eq(g.used.beams, n, "  a refused item adds nothing")
		truthy(g.used.parts <= g.limit.parts and g.used.beams <= g.limit.beams, "never past a limit")
		Night.release(g, small)
		eq(Night.admit(g, small), true, "a released item makes room for the next")
		eq(Night.admit(g, { parts = 0, beams = 0, trails = 0, lights = 1 + g.limit.lights }), false, "a single item over a limit is never admitted")
		-- emitters: in priority order, while both the count and the particles per second fit
		local keep = Night.capEmitters({ 8, 12, 12, 4 }, 4, 40)
		eq(table.concat({ tostring(keep[1]), tostring(keep[2]), tostring(keep[3]), tostring(keep[4]) }, ","), "true,true,true,true", "4 emitters, 36/s: all kept under 4 and 40/s")
		keep = Night.capEmitters({ 8, 12, 12, 4 }, 2, 40)
		eq(table.concat({ tostring(keep[1]), tostring(keep[2]), tostring(keep[3]), tostring(keep[4]) }, ","), "true,true,false,false", "a count of 2: the first two in priority order")
		keep = Night.capEmitters({ 8, 12, 12, 4 }, 4, 12)
		eq(table.concat({ tostring(keep[1]), tostring(keep[2]), tostring(keep[3]), tostring(keep[4]) }, ","), "true,false,false,true", "12/s: the first, then whatever still fits (the 4/s habitat)")
		-- the shipped config: weather (<= MaxWeatherEmitters at <= MaxWeatherRate), the lit habitat and the
		-- campfire all fit at once, so the cap never trims the shipped look
		local want = { Config.Night.Campfire.Rate }
		for _ = 1, B.MaxWeatherEmitters do table.insert(want, B.MaxWeatherRate / B.MaxWeatherEmitters) end
		for _ = 1, B.MaxHabitatEmitters do table.insert(want, Config.Night.Habitats.EmitterRate) end
		local all = true
		for _, k in Night.capEmitters(want, B.MaxEmitters, B.MaxEmitterRate) do all = all and k end
		truthy(all, "the shipped emitters (campfire, weather at its cap, the lit habitat) all fit the budget at once")
	end
end

print(string.format("Night: %d passed, %d failed", passed, failed))
if failed > 0 then error("Night spec failed", 0) end
