--!strict
-- Decor.luau — the client's per-band decor and the indoor creatures' flight paths. Pure; no Roblox.
--
-- ADAPTATION of the +1 Jump template, and why it lives here and not in EnvBands.luau: the template's
-- ambient life spawns on a ring 70-900 studs around the camera (EnvBands.ambientSpawn), which suits an
-- open sky and puts every creature outside a 32-stud room. So indoor creatures fly bounded loops and
-- figure-eights computed here, and tests/Decor.spec.luau asserts every sampled position stays in the
-- room's upper volume (y 8-14, 2 studs off every wall). EnvBands.luau itself stays verbatim.
--
-- Coordinates are local to an anchor: a room's floor centre (the Atrium's, or the Roof deck's). Decor
-- lives on the ceiling or flush on the walls above 9 studs, never in front of a station's face (the
-- face plus 3 studs) and never in a doorway; the spec checks every piece against the station faces.
-- A piece: { id, size = {x,y,z}, pos = {x,y,z}, color = {r,g,b}, material, transparency?, neon? }

local Decor = {}

local function P(id: string, size: { number }, pos: { number }, color: { number }, material: string, transparency: number?): any
	return { id = id, size = size, pos = pos, color = color, material = material, transparency = transparency or 0 }
end

local PIECES: { [string]: { any } } = {}

PIECES.reception = {
	-- window blinds high on the side walls, clear of the stations' faces (z beyond +-5)
	P("blindsW1", { 0.2, 4, 6 }, { -15.85, 12.5, 10 }, { 240, 232, 214 }, "SmoothPlastic"),
	P("blindsW2", { 0.2, 4, 6 }, { -15.85, 12.5, -10 }, { 240, 232, 214 }, "SmoothPlastic"),
	P("blindsE1", { 0.2, 4, 6 }, { 15.85, 12.5, 10 }, { 240, 232, 214 }, "SmoothPlastic"),
	P("blindsE2", { 0.2, 4, 6 }, { 15.85, 12.5, -10 }, { 240, 232, 214 }, "SmoothPlastic"),
	-- sun shafts through the blinds (see-through neon slabs; the dust drifts in them)
	P("shaftW1", { 6, 0.3, 5 }, { -12.5, 11.5, 10 }, { 255, 214, 150 }, "Neon", 0.85),
	P("shaftW2", { 6, 0.3, 5 }, { -12.5, 11.5, -10 }, { 255, 214, 150 }, "Neon", 0.85),
	P("shaftE1", { 6, 0.3, 5 }, { 12.5, 11.5, 10 }, { 255, 214, 150 }, "Neon", 0.85),
	P("shaftE2", { 6, 0.3, 5 }, { 12.5, 11.5, -10 }, { 255, 214, 150 }, "Neon", 0.85),
	P("clock", { 2.4, 2.4, 0.2 }, { 8, 12.5, 15.85 }, { 250, 250, 245 }, "SmoothPlastic"),
	P("clockHands", { 0.2, 1.8, 0.1 }, { 8, 12.7, 15.7 }, { 30, 30, 30 }, "SmoothPlastic"),
	P("sign", { 8, 1.5, 0.2 }, { 0, 10.5, 15.85 }, { 40, 120, 120 }, "SmoothPlastic"),
	P("panel1", { 6, 0.2, 3 }, { -8, 15.9, -8 }, { 255, 246, 225 }, "Neon", 0.3),
	P("panel2", { 6, 0.2, 3 }, { 8, 15.9, -8 }, { 255, 246, 225 }, "Neon", 0.3),
	P("panel3", { 6, 0.2, 3 }, { -8, 15.9, 8 }, { 255, 246, 225 }, "Neon", 0.3),
	P("panel4", { 6, 0.2, 3 }, { 8, 15.9, 8 }, { 255, 246, 225 }, "Neon", 0.3),
}

PIECES.archive = {
	P("web1", { 3, 0.1, 3 }, { -14.5, 15.8, -14.5 }, { 235, 235, 235 }, "SmoothPlastic", 0.6),
	P("web2", { 3, 0.1, 3 }, { 14.5, 15.8, -14.5 }, { 235, 235, 235 }, "SmoothPlastic", 0.6),
	P("web3", { 3, 0.1, 3 }, { -14.5, 15.8, 14.5 }, { 235, 235, 235 }, "SmoothPlastic", 0.6),
	P("web4", { 3, 0.1, 3 }, { 14.5, 15.8, 14.5 }, { 235, 235, 235 }, "SmoothPlastic", 0.6),
	P("cloth1", { 4, 2.5, 0.2 }, { -6, 14.7, 4 }, { 150, 140, 125 }, "Fabric", 0.1),
	P("cloth2", { 4, 2.5, 0.2 }, { 6, 14.7, -4 }, { 150, 140, 125 }, "Fabric", 0.1),
	P("cloth3", { 4, 2.5, 0.2 }, { 0, 14.7, 9 }, { 150, 140, 125 }, "Fabric", 0.1),
	P("beam1", { 32, 1, 1.2 }, { 0, 15.5, -6 }, { 70, 48, 30 }, "Wood"),
	P("beam2", { 32, 1, 1.2 }, { 0, 15.5, 6 }, { 70, 48, 30 }, "Wood"),
	P("ledgeW", { 1.2, 0.4, 8 }, { -15.4, 12, 10 }, { 80, 55, 35 }, "Wood"),
	P("booksW", { 0.8, 1.4, 7 }, { -15.4, 12.9, 10 }, { 130, 50, 40 }, "SmoothPlastic"),
	P("ledgeE", { 1.2, 0.4, 8 }, { 15.4, 12, -10 }, { 80, 55, 35 }, "Wood"),
	P("booksE", { 0.8, 1.4, 7 }, { 15.4, 12.9, -10 }, { 40, 70, 110 }, "SmoothPlastic"),
}

PIECES.greenhouse = {
	P("pane1", { 15.8, 0.2, 15.8 }, { -8, 15.9, -8 }, { 200, 235, 255 }, "Glass", 0.6),
	P("pane2", { 15.8, 0.2, 15.8 }, { 8, 15.9, -8 }, { 200, 235, 255 }, "Glass", 0.6),
	P("pane3", { 15.8, 0.2, 15.8 }, { -8, 15.9, 8 }, { 200, 235, 255 }, "Glass", 0.6),
	P("pane4", { 15.8, 0.2, 15.8 }, { 8, 15.9, 8 }, { 200, 235, 255 }, "Glass", 0.6),
	P("vine1", { 0.4, 4, 0.4 }, { -10, 13.9, -8 }, { 60, 140, 60 }, "Grass"),
	P("vine2", { 0.4, 4, 0.4 }, { -4, 13.9, 2 }, { 60, 140, 60 }, "Grass"),
	P("vine3", { 0.4, 4, 0.4 }, { 3, 13.9, -6 }, { 60, 140, 60 }, "Grass"),
	P("vine4", { 0.4, 4, 0.4 }, { 9, 13.9, 6 }, { 60, 140, 60 }, "Grass"),
	P("vine5", { 0.4, 4, 0.4 }, { 12, 13.9, -12 }, { 60, 140, 60 }, "Grass"),
	P("vine6", { 0.4, 4, 0.4 }, { -12, 13.9, 12 }, { 60, 140, 60 }, "Grass"),
	P("leaves1", { 2, 1.5, 2 }, { -10, 15, -8 }, { 80, 170, 70 }, "Grass"),
	P("leaves2", { 2, 1.5, 2 }, { 9, 15, 6 }, { 80, 170, 70 }, "Grass"),
	P("leaves3", { 2, 1.5, 2 }, { -12, 15, 12 }, { 80, 170, 70 }, "Grass"),
	P("mistpipe", { 30, 0.4, 0.4 }, { 0, 15.2, 0 }, { 180, 190, 200 }, "Metal"),
}

PIECES.coldstore = {
	P("icicleN1", { 0.4, 1.8, 0.4 }, { -9, 15.1, -15.5 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleN2", { 0.4, 1.8, 0.4 }, { 0, 15.1, -15.5 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleN3", { 0.4, 1.8, 0.4 }, { 9, 15.1, -15.5 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleS1", { 0.4, 1.8, 0.4 }, { -9, 15.1, 15.5 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleS2", { 0.4, 1.8, 0.4 }, { 9, 15.1, 15.5 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleW1", { 0.4, 1.8, 0.4 }, { -15.5, 15.1, -9 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleW2", { 0.4, 1.8, 0.4 }, { -15.5, 15.1, 9 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleE1", { 0.4, 1.8, 0.4 }, { 15.5, 15.1, -9 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleE2", { 0.4, 1.8, 0.4 }, { 15.5, 15.1, 9 }, { 220, 240, 255 }, "Ice", 0.2),
	P("icicleE3", { 0.4, 1.8, 0.4 }, { 15.5, 15.1, 0 }, { 220, 240, 255 }, "Ice", 0.2),
	P("frostW", { 0.1, 3, 30 }, { -15.95, 14.5, 0 }, { 235, 245, 255 }, "Snow", 0.3),
	P("frostE", { 0.1, 3, 30 }, { 15.95, 14.5, 0 }, { 235, 245, 255 }, "Snow", 0.3),
	P("frostN", { 30, 3, 0.1 }, { 0, 14.5, -15.95 }, { 235, 245, 255 }, "Snow", 0.3),
	P("frostS", { 30, 3, 0.1 }, { 0, 14.5, 15.95 }, { 235, 245, 255 }, "Snow", 0.3),
	P("vent1", { 3, 0.3, 3 }, { -6, 15.85, 0 }, { 120, 130, 140 }, "DiamondPlate"),
	P("vent2", { 3, 0.3, 3 }, { 6, 15.85, 0 }, { 120, 130, 140 }, "DiamondPlate"),
}

PIECES.reactor = {
	P("pipe1", { 32, 0.8, 0.8 }, { 0, 15.2, -10 }, { 90, 96, 110 }, "Metal"),
	P("pipe2", { 32, 0.8, 0.8 }, { 0, 15.2, -3 }, { 90, 96, 110 }, "Metal"),
	P("pipe3", { 32, 0.8, 0.8 }, { 0, 15.2, 4 }, { 90, 96, 110 }, "Metal"),
	P("pipe4", { 32, 0.8, 0.8 }, { 0, 15.2, 11 }, { 90, 96, 110 }, "Metal"),
	P("neonTeal", { 32, 0.2, 0.2 }, { 0, 14.6, -7 }, { 60, 255, 230 }, "Neon"),
	P("neonViolet", { 32, 0.2, 0.2 }, { 0, 14.6, 7 }, { 170, 90, 255 }, "Neon"),
	P("stripeN", { 30, 1, 0.1 }, { 0, 12.5, -15.95 }, { 250, 200, 40 }, "SmoothPlastic"),
	P("stripeS", { 30, 1, 0.1 }, { 0, 12.5, 15.95 }, { 250, 200, 40 }, "SmoothPlastic"),
	P("stripeW", { 0.1, 1, 30 }, { -15.95, 12.5, 0 }, { 250, 200, 40 }, "SmoothPlastic"),
	P("stripeE", { 0.1, 1, 30 }, { 15.95, 12.5, 0 }, { 250, 200, 40 }, "SmoothPlastic"),
	P("orb1", { 1.2, 1.2, 1.2 }, { -14, 15, 14 }, { 60, 255, 230 }, "Neon", 0.2),
	P("orb2", { 1.2, 1.2, 1.2 }, { 14, 15, 14 }, { 170, 90, 255 }, "Neon", 0.2),
}

-- The Roof: a city skyline of lit blocks 250-500 studs out, below and around the deck.
do
	local city = {}
	local n = 24
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2 + 0.13 * math.sin(i * 1.7)
		local r = 260 + 220 * ((math.sin(i * 12.9898) * 43758.5453) % 1)
		local w = 20 + 18 * ((math.sin(i * 78.233) * 12345.678) % 1)
		local h = 70 + 130 * ((math.sin(i * 39.425) * 9876.54) % 1)
		local top = -30 + 55 * ((math.sin(i * 5.123) * 4321.0) % 1)
		local lit = (i % 3 == 0)
		table.insert(city, P("tower" .. i, { w, h, w }, { math.cos(a) * r, top - h / 2, math.sin(a) * r },
			if lit then { 255, 214, 130 } else { 36, 42, 70 }, if lit then "Neon" else "Concrete", if lit then 0.35 else 0))
	end
	PIECES.roof = city
end

function Decor.pieces(bandId: string): { any }
	return PIECES[bandId] or {}
end

-- Creature models: 1-3 small parts each. offset is from the creature's position.
Decor.CritterParts = {
	fly = {
		{ size = { 0.25, 0.25, 0.35 }, offset = { 0, 0, 0 }, color = { 25, 25, 25 }, material = "SmoothPlastic" },
		{ size = { 0.6, 0.02, 0.22 }, offset = { 0, 0.12, 0 }, color = { 220, 230, 240 }, material = "Glass", transparency = 0.5 },
	},
	moth = {
		{ size = { 0.2, 0.2, 0.45 }, offset = { 0, 0, 0 }, color = { 150, 125, 90 }, material = "Fabric" },
		{ size = { 0.9, 0.02, 0.45 }, offset = { 0, 0.1, 0 }, color = { 205, 185, 150 }, material = "Fabric" },
	},
	butterfly = {
		{ size = { 0.12, 0.12, 0.5 }, offset = { 0, 0, 0 }, color = { 30, 30, 30 }, material = "SmoothPlastic" },
		{ size = { 1.1, 0.02, 0.7 }, offset = { 0, 0.06, 0 }, color = { 255, 150, 40 }, material = "SmoothPlastic" },
	},
	drone = {
		{ size = { 1, 0.4, 1 }, offset = { 0, 0, 0 }, color = { 150, 160, 175 }, material = "Metal" },
		{ size = { 0.25, 0.25, 0.25 }, offset = { 0, -0.3, 0 }, color = { 255, 60, 60 }, material = "Neon" },
	},
	sparkbug = {
		{ size = { 0.35, 0.35, 0.35 }, offset = { 0, 0, 0 }, color = { 80, 255, 230 }, material = "Neon" },
	},
	bat = {
		{ size = { 0.4, 0.4, 0.6 }, offset = { 0, 0, 0 }, color = { 20, 20, 25 }, material = "SmoothPlastic" },
		{ size = { 1.8, 0.05, 0.6 }, offset = { 0, 0.1, 0 }, color = { 30, 28, 35 }, material = "SmoothPlastic" },
	},
}

-- Where creature `i` of `kind` is at time t (seconds), local to the anchor. Every path is a closed loop
-- inside y 8-14 and 2 studs off every wall (tests/Decor.spec.luau samples them).
function Decor.critterPos(kind: string, i: number, t: number): { x: number, y: number, z: number }
	local phase = i * 2.399963 -- the golden angle: spreads creatures of one kind round their loops
	if kind == "fly" then
		local cx = if i % 2 == 1 then -11 else 11
		local cz = if i % 2 == 1 then 9 else -9
		return {
			x = cx + 2.4 * math.cos(3.1 * t + phase) + 0.3 * math.sin(11 * t),
			y = 11 + 0.9 * math.sin(4.3 * t + phase),
			z = cz + 2.4 * math.sin(2.3 * t + phase),
		}
	elseif kind == "moth" then
		local cz = if i % 2 == 1 then -8 else 8
		local r = 1.4 + 0.4 * math.sin(2 * t + phase)
		return { x = r * math.cos(4 * t + phase), y = 13 + 0.4 * math.sin(5 * t + phase), z = cz + r * math.sin(4 * t + phase) }
	elseif kind == "butterfly" then
		local w = 0.35 + 0.03 * i
		local s = w * t + phase
		return { x = 10 * math.sin(s), y = 11 + 1.5 * math.sin(1.3 * t + phase), z = 6 * math.sin(2 * s) + 3 * math.cos(phase) }
	elseif kind == "drone" then
		local s = 0.25 * t + phase
		return { x = 12 * math.cos(s), y = 13 + 0.3 * math.sin(2 * t + phase), z = 12 * math.sin(s) }
	elseif kind == "sparkbug" then
		return {
			x = 6 * math.cos(1.2 * t + phase) + 4 * math.cos(3.1 * t),
			y = 11 + 2 * math.sin(1.7 * t + phase),
			z = 6 * math.sin(1.2 * t + phase) + 4 * math.sin(2.3 * t),
		}
	elseif kind == "bat" then
		return { x = 12 * math.cos(0.8 * t + phase), y = 11 + 2 * math.sin(2 * t + phase), z = 8 * math.sin(1.6 * t + phase) }
	end
	return { x = 0, y = 12, z = 0 }
end

return Decor
