--!strict
-- Biomes.luau — the labyrinth's environment bands and every eye-candy number, in one block.
-- Pure data + pure helpers: no Roblox API, no `require` (EnvBands is passed in), so the whole
-- file runs in the luau CLI (tests/Biomes.spec.luau) and in the client (Biome.client.luau).
--
-- THE RULES THIS FILE EXISTS TO KEEP (the spec pins each one):
--   1. Darkness is the mechanic. A biome shifts HUE only: every colour it defines keeps the luma of
--      the live value it replaces, and the fields that decide how far you see (Ambient, fog distance,
--      brightness, clock time, atmosphere density/haze, torch range/brightness) are not biome
--      fields at all — the client never writes them. Band 1 is the live game, number for number.
--   2. The trap's yellow WARNING and orange DEADLY phase are the survival signal. Every biome's
--      colour grade keeps them two different colours (signalGreenRatio), and nothing non-lethal glows in
--      them: the falling-hazard ring is cool blue under every grade (signalBlueRatio; review fix).
--   3. Walls are never recoloured: the theme shop sells that. A biome dresses walls with small,
--      non-glowing decor pieces instead (glow means "interactive" in this maze), placed from the
--      wall's grid position, face and level only — never from what kind of wall it is, so a secret
--      door is dressed exactly like the plain wall it pretends to be.
--   4. Bands are NAMED by the level (the number the HUD shows) and BLEND over the `fade` levels
--      before a boundary (EnvBands). Time never enters; the client only glides a change.

local Biomes = {}

-- A constant, not the server's WorldSeed (which is not replicated): every client derives the same
-- decor and the same hazard cells from it, so two players on level 140 see the same level.
Biomes.Seed = 20260923

-- The only fields a biome may write. Everything else about the maze's lighting is left alone.
Biomes.LookKeys = { "fogColor", "outdoorAmbient", "atmosColor", "atmosDecay", "tint", "torch" }

-- The live game's look (LightingPresets.MAZE, Fx.Presets.Maze, the server's giveTorch), and the
-- sight fields that stay exactly as they are. `locked` is documentation the checks hold the
-- client to; nothing in the client reads it to write a value.
Biomes.Base = {
	look = {
		fogColor = { 8, 8, 12 },         -- LightingPresets.MAZE.FogColor
		outdoorAmbient = { 20, 20, 28 }, -- LightingPresets.MAZE.OutdoorAmbient
		atmosColor = { 80, 85, 105 },    -- Fx.Presets.Maze.atmosphere.Color
		atmosDecay = { 30, 30, 45 },     -- Fx.Presets.Maze.atmosphere.Decay
		tint = { 230, 225, 235 },        -- Fx.Presets.Maze.colorCorrection.TintColor
		torch = { 255, 235, 190 },       -- MazeGame.server giveTorch
	},
	locked = {
		Ambient = { 0, 0, 0 },
		Brightness = 1,
		ClockTime = 0,
		FogStart = 0,
		AtmosphereDensity = 0.35,
		AtmosphereHaze = 1.4,
		TorchRange = 28,
		TorchBrightness = 2.5,
	},
}

-- Colours whose meaning must survive every colour grade (MazeGame.server TRAP_LOOK).
Biomes.Signals = {
	trapWarn = { 255, 205, 60 },
	trapDeadly = { 230, 90, 30 },
}

-- Materials a decor piece may use. Neon is deliberately absent.
Biomes.DecorMaterials = {
	Metal = true, CorrodedMetal = true, DiamondPlate = true, Wood = true, Slate = true, Fabric = true,
	Grass = true, Ice = true, Snow = true, Glass = true, SmoothPlastic = true, Marble = true, Basalt = true,
}

--------------------------------------------------------------------------- decor pieces
-- Face-local studs: u along the face (-4.5..4.5), v up from the wall's BOTTOM (a secret door that
-- sinks takes its dressing down with it), w out of the face into the corridor. Shapes: Block, Ball,
-- Wedge (thin end up), WedgeDown (thin end down: icicles, spires upside down), CylV (vertical
-- cylinder, size = {diameter, height, diameter}), CylU (along the face, {length, d, d}).
local function P(shape: string, size: { number }, at: { number }, material: string, color: { number }, transparency: number?): any
	return { shape = shape, size = size, at = at, material = material, color = color, transparency = transparency }
end

local IRON = { 72, 72, 78 }
local WOOD = { 78, 56, 38 }
local LEAF = { 66, 128, 52 }
local BONE = { 222, 212, 188 }

Biomes.Pieces = {
	-- 🏚️ dungeon
	chain = { prims = {
		P("Block", { 0.35, 1.3, 0.35 }, { 1.8, 22.9, 0.3 }, "Metal", IRON),
		P("Block", { 0.35, 1.3, 0.35 }, { 1.8, 21.5, 0.3 }, "Metal", IRON),
		P("Block", { 0.35, 1.3, 0.35 }, { 1.8, 20.1, 0.3 }, "Metal", IRON),
		P("Block", { 0.9, 0.9, 0.5 }, { 1.8, 19.0, 0.35 }, "CorrodedMetal", { 88, 70, 60 }),
	} },
	sconce = { prims = {
		P("Block", { 0.8, 0.3, 0.9 }, { -2.0, 11.4, 0.45 }, "Metal", { 60, 58, 55 }),
		P("CylV", { 0.6, 1.4, 0.6 }, { -2.0, 12.3, 0.8 }, "Wood", WOOD),
		P("Block", { 0.5, 0.2, 0.5 }, { -2.0, 13.1, 0.8 }, "Slate", { 26, 24, 24 }),
	} },
	crack = { prims = {
		P("Block", { 3.2, 5.0, 0.12 }, { 0.6, 9.0, 0.02 }, "Slate", { 48, 48, 54 }),
		P("Block", { 1.4, 3.0, 0.12 }, { -1.4, 6.8, 0.02 }, "Slate", { 40, 40, 46 }),
	} },
	banner = { prims = {
		P("Block", { 2.6, 6.0, 0.15 }, { -0.5, 17.5, 0.12 }, "Fabric", { 112, 30, 32 }),
		P("Block", { 2.9, 0.3, 0.3 }, { -0.5, 20.6, 0.2 }, "Wood", WOOD),
	} },
	-- 🌿 jungle
	vine = { prims = {
		P("Block", { 0.35, 9.0, 0.35 }, { -1.2, 19.5, 0.25 }, "Grass", { 60, 120, 50 }),
		P("Block", { 0.3, 6.0, 0.3 }, { -0.4, 21.0, 0.3 }, "Grass", { 70, 135, 55 }),
		P("Block", { 0.3, 11.0, 0.3 }, { 0.6, 18.5, 0.25 }, "Grass", { 55, 110, 45 }),
		P("Ball", { 1.2, 1.2, 1.2 }, { -0.4, 23.6, 0.3 }, "Grass", { 80, 150, 60 }),
	} },
	leaves = { prims = {
		P("Ball", { 2.2, 2.2, 2.2 }, { 1.5, 24.2, 0.1 }, "Grass", LEAF),
		P("Ball", { 1.8, 1.8, 1.8 }, { 0.2, 24.5, 0.0 }, "Grass", { 78, 142, 58 }),
		P("Ball", { 1.6, 1.6, 1.6 }, { 2.6, 23.6, 0.2 }, "Grass", { 58, 118, 46 }),
	} },
	moss = { prims = {
		P("Block", { 3.5, 2.5, 0.1 }, { -1.0, 5.5, 0.03 }, "Grass", { 55, 95, 45 }),
		P("Block", { 2.0, 1.6, 0.1 }, { 1.8, 4.2, 0.03 }, "Grass", { 65, 105, 50 }),
	} },
	roots = { prims = {
		P("Block", { 0.5, 8.0, 0.5 }, { 2.5, 8.0, 0.3 }, "Wood", { 85, 62, 40 }),
		P("Block", { 0.4, 6.0, 0.4 }, { 1.8, 9.5, 0.28 }, "Wood", { 92, 68, 44 }),
		P("Block", { 0.6, 0.6, 1.0 }, { 2.5, 4.3, 0.5 }, "Wood", { 80, 58, 38 }),
	} },
	-- 🧊 ice
	icicles = { prims = {
		P("WedgeDown", { 0.6, 2.8, 0.6 }, { -2.0, 22.6, 0.35 }, "Ice", { 200, 230, 245 }, 0.25),
		P("WedgeDown", { 0.5, 2.0, 0.5 }, { -0.8, 23.0, 0.3 }, "Ice", { 210, 235, 250 }, 0.25),
		P("WedgeDown", { 0.7, 3.4, 0.7 }, { 0.8, 22.3, 0.4 }, "Ice", { 195, 225, 245 }, 0.25),
		P("WedgeDown", { 0.45, 1.6, 0.45 }, { 2.2, 23.2, 0.28 }, "Ice", { 215, 238, 252 }, 0.25),
	} },
	frost = { prims = {
		P("Block", { 4.0, 5.0, 0.08 }, { 0.0, 17.0, 0.02 }, "Ice", { 225, 240, 250 }, 0.35),
		P("Block", { 2.2, 3.0, 0.08 }, { -2.2, 13.0, 0.02 }, "Ice", { 230, 243, 252 }, 0.35),
	} },
	snowcap = { prims = {
		P("Block", { 9.0, 0.8, 1.6 }, { 0.0, 24.4, 0.3 }, "Snow", { 240, 245, 250 }),
		P("Block", { 9.0, 0.5, 0.2 }, { 0.0, 23.8, 0.1 }, "Snow", { 232, 240, 248 }),
	} },
	-- 🔥 forge
	grate = { prims = {
		P("Block", { 3.0, 2.4, 0.2 }, { 0.5, 8.0, 0.12 }, "DiamondPlate", { 60, 55, 55 }),
		P("Block", { 3.2, 0.25, 0.3 }, { 0.5, 9.25, 0.15 }, "Metal", { 50, 45, 45 }),
	} },
	soot = { prims = {
		P("Block", { 4.5, 7.0, 0.08 }, { -0.5, 19.0, 0.02 }, "Slate", { 22, 20, 20 }),
	} },
	pipe = { prims = {
		P("CylU", { 9.0, 0.9, 0.9 }, { 0.0, 15.0, 0.45 }, "CorrodedMetal", { 110, 78, 52 }),
		P("Block", { 0.4, 1.2, 1.0 }, { -3.0, 15.0, 0.5 }, "Metal", { 60, 56, 52 }),
		P("Block", { 0.4, 1.2, 1.0 }, { 3.0, 15.0, 0.5 }, "Metal", { 60, 56, 52 }),
	} },
	-- ✨ crystal
	crystals = { prims = {
		P("Wedge", { 0.8, 3.2, 0.9 }, { -1.5, 10.0, 0.5 }, "Glass", { 150, 205, 225 }, 0.2),
		P("Wedge", { 0.6, 2.2, 0.7 }, { -0.8, 9.4, 0.4 }, "Glass", { 190, 170, 235 }, 0.2),
		P("Wedge", { 1.0, 4.0, 1.0 }, { -2.3, 10.5, 0.55 }, "Glass", { 140, 215, 205 }, 0.2),
	} },
	geode = { prims = {
		P("Block", { 2.6, 2.6, 0.15 }, { 1.0, 15.0, 0.05 }, "Glass", { 180, 165, 230 }, 0.3),
		P("Ball", { 1.0, 1.0, 1.0 }, { 1.2, 15.2, 0.3 }, "Glass", { 200, 230, 240 }, 0.2),
	} },
	spire = { prims = {
		P("Wedge", { 1.2, 5.0, 1.2 }, { 1.5, 26.5, 0.1 }, "Glass", { 160, 210, 230 }, 0.15),
		P("Wedge", { 0.8, 3.2, 0.8 }, { 0.4, 25.6, 0.0 }, "Glass", { 185, 175, 235 }, 0.15),
	} },
	-- 💀 crypt
	skull = { prims = {
		P("Ball", { 1.1, 1.1, 1.1 }, { 0.8, 12.5, 0.6 }, "SmoothPlastic", BONE),
		P("Block", { 0.7, 0.4, 0.5 }, { 0.8, 11.9, 0.55 }, "SmoothPlastic", { 210, 200, 175 }),
		P("Block", { 2.2, 0.3, 1.0 }, { 0.8, 11.6, 0.5 }, "Slate", { 60, 58, 62 }),
	} },
	bones = { prims = {
		P("CylU", { 2.4, 0.3, 0.3 }, { -1.0, 7.0, 0.35 }, "SmoothPlastic", BONE),
		P("CylU", { 1.8, 0.3, 0.3 }, { -0.6, 6.5, 0.6 }, "SmoothPlastic", { 212, 202, 178 }),
		P("Ball", { 0.5, 0.5, 0.5 }, { -2.3, 7.0, 0.35 }, "SmoothPlastic", BONE),
	} },
	cobweb = { prims = {
		P("Block", { 2.8, 2.8, 0.05 }, { 3.0, 22.4, 0.1 }, "SmoothPlastic", { 225, 225, 230 }, 0.6),
		P("Block", { 1.6, 1.6, 0.05 }, { -3.6, 22.9, 0.1 }, "SmoothPlastic", { 225, 225, 230 }, 0.65),
	} },
	candles = { prims = {
		P("CylV", { 0.4, 1.0, 0.4 }, { -2.0, 12.8, 0.7 }, "SmoothPlastic", { 235, 230, 210 }),
		P("CylV", { 0.4, 0.7, 0.4 }, { -1.4, 12.65, 0.75 }, "SmoothPlastic", { 228, 222, 200 }),
		P("Block", { 1.8, 0.25, 1.0 }, { -1.7, 12.2, 0.5 }, "Slate", { 60, 58, 62 }),
	} },
	-- ☁️ sky ruins
	column = { prims = {
		P("CylV", { 1.6, 4.5, 1.6 }, { 2.2, 26.25, 0.3 }, "Marble", { 225, 222, 210 }),
		P("Block", { 2.2, 0.6, 1.8 }, { 2.2, 24.3, 0.3 }, "Marble", { 210, 206, 196 }),
	} },
	cloudpuff = { prims = {
		P("Ball", { 2.4, 2.4, 2.4 }, { -1.5, 24.3, -0.1 }, "SmoothPlastic", { 245, 248, 255 }, 0.2),
		P("Ball", { 1.8, 1.8, 1.8 }, { 0.0, 24.6, 0.0 }, "SmoothPlastic", { 240, 244, 255 }, 0.2),
		P("Ball", { 1.6, 1.6, 1.6 }, { 1.4, 24.2, 0.0 }, "SmoothPlastic", { 236, 241, 255 }, 0.25),
	} },
	trim = { prims = {
		P("Block", { 9.0, 0.5, 0.3 }, { 0.0, 21.0, 0.15 }, "Marble", { 205, 180, 120 }),
	} },
	-- 🌌 astral
	floatrock = { prims = {
		P("Block", { 1.2, 1.0, 1.0 }, { -1.0, 14.0, 0.7 }, "Basalt", { 62, 52, 82 }),
		P("Block", { 0.7, 0.6, 0.6 }, { 0.6, 16.0, 0.85 }, "Basalt", { 70, 58, 92 }),
		P("Block", { 0.5, 0.5, 0.5 }, { -2.2, 17.5, 0.9 }, "Basalt", { 56, 48, 76 }),
	} },
	starbits = { prims = {
		P("Ball", { 0.5, 0.5, 0.5 }, { 1.0, 19.0, 0.6 }, "Glass", { 232, 222, 255 }, 0.1),
		P("Ball", { 0.35, 0.35, 0.35 }, { 2.2, 17.8, 0.7 }, "Glass", { 220, 230, 255 }, 0.1),
		P("Ball", { 0.4, 0.4, 0.4 }, { -0.4, 20.5, 0.7 }, "Glass", { 240, 220, 255 }, 0.1),
	} },
	runes = { prims = {
		P("Block", { 3.0, 3.0, 0.08 }, { 0.0, 13.0, 0.02 }, "Slate", { 70, 55, 100 }),
		P("Block", { 0.4, 2.4, 0.1 }, { -0.8, 13.0, 0.05 }, "Slate", { 104, 84, 146 }),
		P("Block", { 1.6, 0.4, 0.1 }, { 0.4, 13.6, 0.05 }, "Slate", { 104, 84, 146 }),
	} },
}

--------------------------------------------------------------------------- air (particles)
-- One small emitter follows the player. size in studs, speed studs/s, rise = vertical drift
-- (negative falls), drift = sideways spread. Small and see-through: they must never hide a monster.
Biomes.Air = {
	dust = { color = { 205, 190, 165 }, lightEmission = 0.15, size = 0.12, transparency = 0.45, speed = 0.4, lifetime = 7, rise = 0.05, drift = 0.6 },
	fireflies = { color = { 215, 245, 120 }, lightEmission = 0.9, size = 0.16, transparency = 0.3, speed = 0.8, lifetime = 5, rise = 0.2, drift = 1.4 },
	snow = { color = { 240, 248, 255 }, lightEmission = 0.3, size = 0.18, transparency = 0.35, speed = 1.2, lifetime = 7, rise = -2.0, drift = 0.5 },
	embers = { color = { 255, 150, 60 }, lightEmission = 0.8, size = 0.12, transparency = 0.3, speed = 1.0, lifetime = 4, rise = 2.5, drift = 0.8 },
	sparkles = { color = { 215, 205, 255 }, lightEmission = 0.9, size = 0.14, transparency = 0.35, speed = 0.3, lifetime = 3, rise = 0.1, drift = 0.3 },
	mist = { color = { 195, 230, 205 }, lightEmission = 0.1, size = 0.6, transparency = 0.8, speed = 0.4, lifetime = 8, rise = 0.1, drift = 0.8 },
	wisps = { color = { 225, 232, 255 }, lightEmission = 0.2, size = 0.5, transparency = 0.75, speed = 1.6, lifetime = 6, rise = 0.0, drift = 1.8 },
	stardust = { color = { 235, 215, 255 }, lightEmission = 0.9, size = 0.12, transparency = 0.35, speed = 0.3, lifetime = 5, rise = 0.15, drift = 0.4 },
}

--------------------------------------------------------------------------- the bands
-- `from` = first level of the band. `fade` = levels over which it blends in BEFORE `from`.
-- Pacing (tests/Pacing.spec.luau prints it: the MazeWalker model, normal player, no deaths, so a lower
-- bound): level 11 after 5.1 min, 26 after 12.7, 51 after 40.6, 101 after 2.4 h, 161 after 6.3 h,
-- 241 after 17.5 h, 351 after 38.9 h.
Biomes.Bands = {
	{
		id = "dungeon", from = 0, fade = 0, name = "Stone Dungeon", emoji = "🏚️",
		look = {
			fogColor = { 8, 8, 12 }, outdoorAmbient = { 20, 20, 28 }, atmosColor = { 80, 85, 105 },
			atmosDecay = { 30, 30, 45 }, tint = { 230, 225, 235 }, torch = { 255, 235, 190 },
		},
		air = { dust = 6 },
		decor = { density = 0.35, kit = { { "chain", 3 }, { "sconce", 2 }, { "crack", 3 }, { "banner", 1 } } },
		hazard = nil,
	},
	{
		id = "jungle", from = 11, fade = 3, name = "Jungle Ruins", emoji = "🌿",
		look = {
			fogColor = { 5, 10, 5 }, outdoorAmbient = { 15, 23, 15 }, atmosColor = { 62, 95, 62 },
			atmosDecay = { 21, 35, 21 }, tint = { 210, 234, 203 }, torch = { 237, 242, 168 },
		},
		air = { fireflies = 6 },
		decor = { density = 0.45, kit = { { "vine", 4 }, { "leaves", 3 }, { "moss", 2 }, { "roots", 2 } } },
		hazard = nil,
	},
	{
		id = "ice", from = 26, fade = 4, name = "Ice Cellar", emoji = "🧊",
		look = {
			fogColor = { 5, 9, 14 }, outdoorAmbient = { 15, 21, 34 }, atmosColor = { 64, 88, 125 },
			atmosDecay = { 20, 32, 56 }, tint = { 205, 231, 253 }, torch = { 209, 242, 255 },
		},
		air = { snow = 16 },
		decor = { density = 0.5, kit = { { "icicles", 5 }, { "frost", 2 }, { "snowcap", 3 } } },
		hazard = "icicle",
	},
	{
		id = "forge", from = 51, fade = 5, name = "Lava Forge", emoji = "🔥",
		look = {
			fogColor = { 17, 6, 3 }, outdoorAmbient = { 36, 17, 11 }, atmosColor = { 137, 74, 53 },
			atmosDecay = { 61, 24, 13 }, tint = { 254, 222, 197 }, torch = { 255, 238, 157 },
		},
		air = { embers = 10 },
		decor = { density = 0.4, kit = { { "chain", 2 }, { "grate", 2 }, { "soot", 3 }, { "pipe", 2 } } },
		hazard = "lavabomb",
	},
	{
		id = "crystal", from = 101, fade = 6, name = "Crystal Caverns", emoji = "✨",
		look = {
			fogColor = { 11, 7, 17 }, outdoorAmbient = { 26, 17, 37 }, atmosColor = { 102, 75, 135 },
			atmosDecay = { 42, 25, 62 }, tint = { 239, 220, 255 }, torch = { 241, 233, 255 },
		},
		air = { sparkles = 10 },
		decor = { density = 0.45, kit = { { "crystals", 4 }, { "geode", 2 }, { "spire", 3 } } },
		hazard = "shard",
	},
	{
		id = "crypt", from = 161, fade = 8, name = "Haunted Crypt", emoji = "💀",
		look = {
			fogColor = { 4, 10, 7 }, outdoorAmbient = { 14, 23, 18 }, atmosColor = { 63, 93, 74 },
			atmosDecay = { 22, 34, 27 }, tint = { 208, 234, 210 }, torch = { 212, 246, 204 },
		},
		air = { mist = 4 },
		decor = { density = 0.45, kit = { { "skull", 2 }, { "bones", 2 }, { "cobweb", 3 }, { "candles", 2 } } },
		hazard = "chandelier",
	},
	{
		id = "sky", from = 241, fade = 10, name = "Sky Ruins", emoji = "☁️",
		look = {
			fogColor = { 5, 8, 18 }, outdoorAmbient = { 15, 20, 37 }, atmosColor = { 67, 85, 140 },
			atmosDecay = { 22, 30, 67 }, tint = { 212, 228, 255 }, torch = { 224, 238, 255 },
		},
		air = { wisps = 5 },
		decor = { density = 0.45, kit = { { "column", 3 }, { "cloudpuff", 3 }, { "trim", 2 }, { "vine", 2 } } },
		hazard = "lightning",
	},
	{
		id = "astral", from = 351, fade = 12, name = "Astral Labyrinth", emoji = "🌌",
		look = {
			fogColor = { 13, 6, 20 }, outdoorAmbient = { 27, 16, 42 }, atmosColor = { 115, 70, 151 },
			atmosDecay = { 49, 21, 75 }, tint = { 242, 218, 255 }, torch = { 254, 229, 255 },
		},
		air = { stardust = 12 },
		decor = { density = 0.45, kit = { { "floatrock", 3 }, { "starbits", 3 }, { "runes", 2 }, { "spire", 1 } } },
		hazard = "meteor",
	},
}

--------------------------------------------------------------------------- hazards (CellHazards)
-- One cycle per hazard cell on the LEVEL clock: quiet, a WarnSeconds warning (ring, shadow, the
-- object above), one impact instant, debris. Same for everyone on a level, like the lava pulse.
-- Rarity is measured, not assumed: tests/Pacing.spec.luau (about one near-hit per 2-3 minutes).
Biomes.Hazards = {
	Enabled = true,
	CellSize = 9,               -- the server's CONFIG.CellSize (check_labyrintspill_biomes parses it)
	WalkSpeed = 16,             -- the server's CONFIG.PlayerWalkSpeed
	Period = 14,                -- seconds between two impacts at one cell
	WarnSeconds = 3.0,          -- ring + shadow + the object overhead, before the impact
	MinWarnSeconds = 2.5,       -- CellHazards.validate refuses anything shorter
	DebrisSeconds = 1.2,        -- harmless shards/steam after the impact
	StrikeRadius = 3.2,         -- reach of an impact from the cell centre (studs)
	PlayerRadius = 1.0,
	KnockSeconds = 0.8,         -- knocked down (PlatformStand)
	KnockPush = 5,              -- studs/s, horizontal, away from the impact
	MaxKnockDisplacement = 4.5, -- KnockPush * KnockSeconds must stay under this
	Density = 0.03,             -- share of cells with a hazard (tuned in tests/Pacing.spec.luau)
	MaxPerLevel = 40,
	MinSpacing = 3,             -- cells between two hazard cells
	StartClearCells = 2,        -- no hazard this close to the start cell
	GraceSeconds = 4,           -- no impact in the first seconds of a level
	MaxHitHeight = 20,          -- studs over the floor an impact reaches (the object hangs at 21; a jump peaks ~10.5)
	ShowRadius = 26,            -- studs: drawn only inside the torch's 28 (a glowing ring must not show a cell the torch does not)
	NearRadius = 12,            -- studs: what the measurements count as a near-hit
	-- (review fix) the ring's OWN colour. It used to be the trap's warning yellow; but glowing yellow on this
	-- floor means "this floor kills you in a moment", and a yellow ring that only knocks you down teaches the
	-- opposite. Cool blue, where both trap phases are warm (validate holds it there under every grade).
	RingColor = { 100, 160, 255 },
	RingWord = "blue",          -- what the banner and the biome card call it
	Kinds = {
		icicle = { label = "🧊 ICICLE!" },
		lavabomb = { label = "🌋 LAVA BOMB!" },
		shard = { label = "🔷 CRYSTAL SHARD!" },
		chandelier = { label = "🕯️ CHANDELIER!" },
		lightning = { label = "⚡ LIGHTNING!" },
		meteor = { label = "☄️ METEOR!" },
	},
}

--------------------------------------------------------------------------- rest (BreakRoom + Rest)
Biomes.Rest = {
	-- the template's Rest state machine (the campfire in the lobby)
	WakeOnMove = true,
	BlockWhileThreat = true,
	RequireGrounded = true,
	IdleSeconds = 0,            -- no idle rest: the lobby has nothing to be safe from
	PendingSeconds = 3,
	WakeGraceSeconds = 0.4,
	-- the free break at the start of every level (the server's Assist rule, mirrored)
	ServerMinRunSeconds = 8,    -- MazeGame.server CONFIG.Assist.MinRunSeconds
	FreeBreakSeconds = 6,
	LatencyMarginSeconds = 1.5,
	SignFadeSeconds = 1.0,
	-- the lobby's campfire (the lobby floor is 70 x 70 around the origin)
	Campfire = { x = 24, z = -4 },
	PromptDistance = 12,
}

--------------------------------------------------------------------------- budget (mobile)
Biomes.Budget = {
	MaxLocalParts = 140,     -- every part this client builds, at once
	MaxDecorPieces = 26,
	MaxPrimsPerPiece = 4,
	DecorRadius = 24,        -- inside the torch's 28 studs: decor never shows a wall the torch does not
	MaxAirEmitters = 2,
	MaxEmitters = 4,         -- in the maze (air + one impact burst)
	MaxEmitterRate = 40,     -- particles per second, summed
	MaxMazeLights = 0,       -- a light in the maze would add sight
	MaxLobbyLights = 1,      -- the campfire
	MaxHazardsShown = 2,
	LightingHz = 10,
	GlideHalfLife = 0.6,     -- seconds; a level change glides, it never cuts
	DecorFadeSeconds = 0.35, -- decor fades in when placed, and out when its wall (a secret door) sinks
}

--------------------------------------------------------------------------- helpers

function Biomes.luma(c: { number }): number
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

-- G/R of a signal colour as it reaches the screen through a colour grade (ColorCorrection tint
-- multiplies each channel). Yellow ~0.8, orange ~0.4: the two must stay apart.
function Biomes.signalGreenRatio(signal: { number }, tint: { number }): number
	return (signal[2] * tint[2]) / (signal[1] * tint[1])
end

-- B/R of a colour through a colour grade: the falling-hazard ring (cool, >= 1.5) against the trap's two phases
-- (warm, ~0.13-0.3). The denominator never reaches zero, so a black or blue-less colour cannot slip through.
function Biomes.signalBlueRatio(signal: { number }, tint: { number }): number
	return (signal[3] * tint[3]) / math.max(1, signal[1] * tint[1])
end

-- The words on screen about a falling hazard (Biome.client shows them; check_labyrintspill_layout measures them).
function Biomes.hazardBanner(kind: string): string
	return "⚠️ " .. Biomes.Hazards.Kinds[kind].label .. " step out of the " .. Biomes.Hazards.RingWord .. " ring"
end
function Biomes.hazardIntro(kind: string): string
	return Biomes.Hazards.Kinds[kind].label .. " watch for the " .. Biomes.Hazards.RingWord .. " ring"
end

function Biomes.bandIndex(EnvBands: any, level: number): number
	return EnvBands.indexAt(Biomes.Bands, level)
end

function Biomes.band(EnvBands: any, level: number): any
	return Biomes.Bands[Biomes.bandIndex(EnvBands, level)]
end

function Biomes.weightsAt(EnvBands: any, level: number): { [number]: number }
	return EnvBands.weights(Biomes.Bands, level)
end

function Biomes.lookAt(EnvBands: any, level: number): { [string]: any }
	return EnvBands.sample(Biomes.Bands, level, "look")
end

-- The named band's hazard kind (no blending: a hazard is either there or not).
function Biomes.hazardKindAt(EnvBands: any, level: number): string?
	return Biomes.band(EnvBands, level).hazard
end

-- { [airKind] = particles per second }, blended over the fade.
function Biomes.airAt(EnvBands: any, level: number): { [string]: number }
	local i, j, t = EnvBands.locate(Biomes.Bands, level)
	local out = {}
	local wi = if j == i then 1 else 1 - t
	for kind, r in Biomes.Bands[i].air do
		out[kind] = (out[kind] or 0) + r * wi
	end
	if j ~= i then
		for kind, r in Biomes.Bands[j].air do
			out[kind] = (out[kind] or 0) + r * t
		end
	end
	return out
end

Biomes.FACES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Faces of the wall at fine-grid (fx, fy) that look into an open cell of the grid. `isWall(x, y)`
-- is the only thing asked about the maze: it treats a secret door as the wall it looks like.
function Biomes.openFaces(isWall: (number, number) -> boolean, fx: number, fy: number, gCols: number, gRows: number): { number }
	local out = {}
	for i, d in Biomes.FACES do
		local nx, ny = fx + d[1], fy + d[2]
		if nx >= 0 and ny >= 0 and nx < gCols and ny < gRows and not isWall(nx, ny) then
			table.insert(out, i)
		end
	end
	return out
end

-- Which piece (or nil) dresses face `face` (1..4) of the wall at fine-grid (fx, fy) on `level`.
-- Deterministic from those four numbers alone. In a fade, a share of the faces equal to the next
-- band's weight wears the next band's pieces, so the dungeon grows mossier level by level.
-- Each level also re-weights its band's kit (0.4x..1.6x per piece), so no two levels look alike.
function Biomes.decorFor(EnvBands: any, level: number, fx: number, fy: number, face: number): string?
	local bands = Biomes.Bands
	local i, j, t = EnvBands.locate(bands, level)
	local bi, bj = bands[i], bands[j]
	local density = bi.decor.density * (1 - t) + bj.decor.density * t
	local L = math.floor(level)
	if EnvBands.hash01(fx * 4 + face, fy, L, Biomes.Seed) >= density then
		return nil
	end
	local b = bi
	if j ~= i and EnvBands.hash01(fy * 4 + face, fx, L + 7777, Biomes.Seed) < t then
		b = bj
	end
	local weights, total = {}, 0
	for k, e in b.decor.kit do
		local w = e[2] * (0.4 + 1.2 * EnvBands.hash01(k, L, 99, Biomes.Seed))
		weights[k] = w
		total += w
	end
	local r = EnvBands.hash01(fx + 131 * face, fy, L + 31337, Biomes.Seed) * total
	for k, e in b.decor.kit do
		r -= weights[k]
		if r < 0 then return e[1] end
	end
	return b.decor.kit[#b.decor.kit][1]
end

-- (review fix) Only a secret door ever leaves its place: its button sinks it WallHeight + 2 = 26 studs into
-- the floor. Pieces that stand on the wall top reach higher than 26 studs over the wall's bottom, so a door's
-- dressing cannot simply ride it down: it would be left sticking out of the floor where the door was. So:
--   "standing" — the wall's bottom is on the floor: dressed as always;
--   "sinking"  — its bottom has gone into the floor: its pieces ride down with it while they fade out
--                (decorAlpha), and nothing new is put on it;
--   "gone"     — its top is at or below the floor's top: nothing of its dressing may show, at once (a client
--                that only sees the door after it is down, after a hitch or on arrival, never fades).
-- Judged from the wall's POSITION, which every player sees, never from its name or kind.
Biomes.SinkTolerance = 0.05
function Biomes.wallState(bottomY: number, topY: number, floorTopY: number): string
	if topY <= floorTopY + Biomes.SinkTolerance then return "gone" end
	if bottomY < floorTopY - Biomes.SinkTolerance then return "sinking" end
	return "standing"
end

-- A decor piece's opacity (0..1): it fades in over DecorFadeSeconds after it is placed (`age`), and out over
-- DecorFadeSeconds once its wall has started to sink (`sinkAge`; nil while the wall stands).
function Biomes.decorAlpha(age: number, sinkAge: number?): number
	local f = Biomes.Budget.DecorFadeSeconds
	local a = math.clamp(age / f, 0, 1)
	if sinkAge ~= nil then
		a = math.min(a, math.clamp(1 - sinkAge / f, 0, 1))
	end
	return a
end

-- The lobby's brag wall: every biome, whether this player can play in it (the next level they may
-- start is accepted + 1), and the index of the next one they have not reached (nil past the last).
function Biomes.album(EnvBands: any, accepted: number): ({ any }, number?)
	local nextLevel = math.max(1, math.floor(tonumber(accepted) or 0) + 1)
	local out, nextIdx = {}, nil
	for i, b in Biomes.Bands do
		local reached = b.from <= nextLevel
		table.insert(out, { index = i, id = b.id, name = b.name, emoji = b.emoji, from = math.max(1, b.from), reached = reached })
		if not reached and nextIdx == nil then nextIdx = i end
	end
	return out, nextIdx
end

--------------------------------------------------------------------------- validate

local function lumaOk(c: any, base: { number }): boolean
	if type(c) ~= "table" or #c ~= 3 then return false end
	for k = 1, 3 do
		if type(c[k]) ~= "number" or c[k] < 0 or c[k] > 255 then return false end
	end
	local target = Biomes.luma(base)
	return math.abs(Biomes.luma(c) - target) <= math.max(0.6, target * 0.015)
end

local function pieceOk(id: string, piece: any): (boolean, string?)
	if type(piece) ~= "table" or type(piece.prims) ~= "table" then return false, "piece " .. id .. " has no prims" end
	if #piece.prims < 1 or #piece.prims > Biomes.Budget.MaxPrimsPerPiece then
		return false, "piece " .. id .. " has " .. #piece.prims .. " parts"
	end
	local area = 0
	for _, p in piece.prims do
		if p.material == "Neon" or not Biomes.DecorMaterials[p.material] then
			return false, "piece " .. id .. " uses material " .. tostring(p.material)
		end
		if p.light ~= nil then return false, "piece " .. id .. " carries a light" end
		local su, sv, sw = p.size[1], p.size[2], p.size[3]
		local u, v, w = p.at[1], p.at[2], p.at[3]
		if v - sv / 2 < 3 - 1e-9 then return false, "piece " .. id .. " reaches below 3 studs" end
		if w + sw / 2 > 1.2 + 1e-9 then return false, "piece " .. id .. " sticks out more than 1.2 studs" end
		if math.abs(u) + su / 2 > 4.5 + 1e-9 then return false, "piece " .. id .. " leaves its face" end
		if v + sv / 2 > 30 + 1e-9 then return false, "piece " .. id .. " rises too far above the wall" end
		if v - sv / 2 < 24 then area += su * math.min(sv, 24 - (v - sv / 2)) end
	end
	if area > 0.25 * 9 * 24 + 1e-9 then return false, "piece " .. id .. " covers more than a quarter of its face" end
	return true, nil
end

-- (ok, err) for the whole eye-candy config. EnvBands passed in (dependencies as arguments).
function Biomes.validate(EnvBands: any): (boolean, string?)
	local ok, err = EnvBands.validate(Biomes.Bands)
	if not ok then return false, err end
	if type(Biomes.Budget.DecorRadius) ~= "number" or Biomes.Budget.DecorRadius > Biomes.Base.locked.TorchRange - 4 then
		return false, "DecorRadius must stay inside the torch's reach (TorchRange - 4)"
	end
	if type(Biomes.Budget.DecorFadeSeconds) ~= "number" or not (Biomes.Budget.DecorFadeSeconds > 0) then
		return false, "DecorFadeSeconds must be > 0"
	end
	local base = Biomes.Base.look
	for id, piece in Biomes.Pieces do
		local pok, perr = pieceOk(id, piece)
		if not pok then return false, perr end
	end
	local ring = Biomes.Hazards.RingColor
	if type(ring) ~= "table" or #ring ~= 3 or type(Biomes.Hazards.RingWord) ~= "string" then
		return false, "Hazards.RingColor must be an RGB triple and RingWord a word"
	end
	for k = 1, 3 do
		if type(ring[k]) ~= "number" or ring[k] < 0 or ring[k] > 255 then return false, "Hazards.RingColor channel " .. k end
	end
	for i, b in Biomes.Bands do
		local tag = "band " .. tostring(b.id)
		if type(b.look) ~= "table" then return false, tag .. " has no look" end
		local n = 0
		for k in b.look do
			n += 1
			if table.find(Biomes.LookKeys, k) == nil then return false, tag .. " writes " .. tostring(k) .. ", which is not a hue field" end
		end
		if n ~= #Biomes.LookKeys then return false, tag .. " does not define every hue field" end
		for _, k in Biomes.LookKeys do
			if not lumaOk(b.look[k], base[k]) then return false, tag .. " " .. k .. " changes the brightness" end
			if i == 1 then
				for c = 1, 3 do
					if b.look[k][c] ~= base[k][c] then return false, "the first band must be the live look (" .. k .. ")" end
				end
			end
		end
		local tint, torch = b.look.tint, b.look.torch
		if math.min(tint[1], tint[2], tint[3]) / math.max(tint[1], tint[2], tint[3]) < 0.76 then
			return false, tag .. " colour grade is too strong"
		end
		if math.min(torch[1], torch[2], torch[3]) / math.max(torch[1], torch[2], torch[3]) < 0.6 then
			return false, tag .. " torch is too coloured"
		end
		local warnGR = Biomes.signalGreenRatio(Biomes.Signals.trapWarn, tint)
		local deadlyGR = Biomes.signalGreenRatio(Biomes.Signals.trapDeadly, tint)
		if warnGR < 0.62 or deadlyGR > 0.48 or warnGR - deadlyGR < 0.3 then
			return false, tag .. " grade makes the trap warning and the lava look alike"
		end
		local ringBR = Biomes.signalBlueRatio(ring, tint)
		local trapBR = math.max(Biomes.signalBlueRatio(Biomes.Signals.trapWarn, tint), Biomes.signalBlueRatio(Biomes.Signals.trapDeadly, tint))
		if not (ringBR >= 1.5) or not (ringBR - trapBR >= 1.0) then
			return false, tag .. ": the falling-hazard ring must read cool, far from the trap's warm warning and lava"
		end
		if i <= 2 and b.hazard ~= nil then return false, tag .. " is too early for hazards" end
		if b.hazard ~= nil and Biomes.Hazards.Kinds[b.hazard] == nil then
			return false, tag .. " names an unknown hazard " .. tostring(b.hazard)
		end
		local airSum = 0
		for kind, r in b.air do
			if Biomes.Air[kind] == nil then return false, tag .. " names an unknown air kind " .. tostring(kind) end
			if type(r) ~= "number" or r < 0 then return false, tag .. " air rate" end
			airSum += r
		end
		if airSum > Biomes.Budget.MaxEmitterRate then return false, tag .. " air over budget" end
		if type(b.decor) ~= "table" or type(b.decor.density) ~= "number" or b.decor.density < 0 or b.decor.density > 0.8 then
			return false, tag .. " decor density"
		end
		for _, e in b.decor.kit do
			if Biomes.Pieces[e[1]] == nil then return false, tag .. " kit names unknown piece " .. tostring(e[1]) end
			if type(e[2]) ~= "number" or e[2] <= 0 then return false, tag .. " kit weight" end
		end
	end
	return true, nil
end

return Biomes
