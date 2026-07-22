--!strict
-- Vegg-temaer for labyrint-spillet. Ren data (ingen Roblox-API), så den kan
-- brukes av både server, klient og tester. Farger er {r, g, b} (0-255) og
-- gjøres om til Color3 der de faktisk brukes.
--
-- Hvert tema: id, navn (norsk), wall/secret/floor-farge, og pris i BEGGE
-- valutaer (coinPrice = Mynter, gemPrice = Edelstener). "classic" er gratis
-- og eies fra start (pris 0 = ikke til salgs, men default-eid).

local Themes = {}

Themes.default = "classic"

Themes.List = {
	-- material = Roblox Enum.Material (gir ekte overflate-detalj/mønster på veggene).
	{ id = "classic",   name = "Klassisk",        wall = {90, 94, 105},   secret = {70, 66, 78},   floor = {60, 62, 70},    coinPrice = 0,    gemPrice = 0,  material = "Slate" },
	{ id = "bubblegum", name = "Tyggegummi",      wall = {255, 120, 175}, secret = {255, 140, 190}, floor = {200, 240, 225}, coinPrice = 500,  gemPrice = 25, material = "Pebble" },
	{ id = "lego",      name = "LEGO-klosser",    wall = {35, 120, 220},  secret = {55, 135, 230}, floor = {250, 230, 140}, coinPrice = 500,  gemPrice = 25, material = "SmoothPlastic" },
	{ id = "ice",       name = "Isgrotte",        wall = {150, 190, 215}, secret = {165, 200, 210}, floor = {80, 110, 140},  coinPrice = 500,  gemPrice = 25, material = "Ice" },
	{ id = "forest",    name = "Dyp skog",        wall = {80, 135, 75},   secret = {95, 145, 70},  floor = {120, 130, 100}, coinPrice = 500,  gemPrice = 25, material = "Grass" },
	{ id = "desert",    name = "Ørkensandstein",  wall = {200, 165, 120}, secret = {205, 155, 105}, floor = {150, 120, 90},  coinPrice = 500,  gemPrice = 25, material = "Sandstone" },
	{ id = "coral",     name = "Korallrev",       wall = {215, 125, 140}, secret = {210, 120, 155}, floor = {55, 135, 140},  coinPrice = 800,  gemPrice = 40, material = "Sand" },
	{ id = "autumn",    name = "Høstskog",        wall = {190, 125, 75},  secret = {195, 115, 65}, floor = {120, 110, 85},  coinPrice = 800,  gemPrice = 40, material = "WoodPlanks" },
	{ id = "christmas", name = "Jul",             wall = {210, 70, 72},   secret = {218, 90, 82},  floor = {222, 233, 245}, coinPrice = 800,  gemPrice = 40, material = "Brick" },
	{ id = "halloween", name = "Halloween",       wall = {245, 160, 55},  secret = {250, 175, 75}, floor = {120, 100, 165}, coinPrice = 800,  gemPrice = 40, material = "Cobblestone" },
	{ id = "nebula",    name = "Stjernetåke",     wall = {55, 105, 205},  secret = {70, 110, 198}, floor = {48, 52, 98},    coinPrice = 1000, gemPrice = 45, material = "Slate" },
	{ id = "alienhive", name = "Romvesenbol",     wall = {35, 178, 140},  secret = {48, 176, 126}, floor = {28, 68, 60},    coinPrice = 1000, gemPrice = 45, material = "Foil" },
	{ id = "synthwave", name = "Synthwave",       wall = {230, 65, 150},  secret = {216, 82, 158}, floor = {62, 52, 125},   coinPrice = 1200, gemPrice = 55, material = "Metal" },
	{ id = "arcade",    name = "Retro-arkade",    wall = {120, 70, 215},  secret = {128, 82, 208}, floor = {40, 58, 92},    coinPrice = 1200, gemPrice = 55, material = "DiamondPlate" },
	{ id = "gold",      name = "Gulltempel",      wall = {170, 138, 86},  secret = {176, 140, 78}, floor = {110, 86, 54},   coinPrice = 1500, gemPrice = 60, material = "Sandstone" },
	{ id = "marble",    name = "Marmorpalass",    wall = {208, 200, 182}, secret = {200, 198, 188}, floor = {150, 146, 140}, coinPrice = 1500, gemPrice = 60, material = "Marble" },
	{ id = "onyx",      name = "Onyks",           wall = {72, 80, 94},    secret = {80, 86, 98},   floor = {64, 58, 56},    coinPrice = 1500, gemPrice = 60, material = "Basalt" },
}

local index = {}
for _, t in ipairs(Themes.List) do
	index[t.id] = t
end

function Themes.byId(id)
	return index[id]
end

return Themes
