-- Pure tests for CryptidModel: procedural Part models from the species table.
-- Run from the game directory: luau tests/CryptidModel.spec.luau
local Config = require("../src/shared/Config")
local CryptidModel = require("../src/shared/CryptidModel")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local MAX_PARTS = 14 -- DESIGN.md section 3: twelve models are the bulk of a lair's 300-part budget
local CAGE_INNER = 7 -- the cage is one 8-stud cell; a model must fit inside its bars
local CAGE_HEIGHT = 8
local SHAPES = { Block = true, Ball = true, Cylinder = true }
local MATERIALS = { SmoothPlastic = true, Neon = true, Fabric = true, Slate = true, Glass = true }

local function bbox(parts)
	local b = { x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge, z0 = math.huge, z1 = -math.huge }
	for _, p in parts do
		b.x0 = math.min(b.x0, p.pos.x - p.size.x / 2); b.x1 = math.max(b.x1, p.pos.x + p.size.x / 2)
		b.y0 = math.min(b.y0, p.pos.y - p.size.y / 2); b.y1 = math.max(b.y1, p.pos.y + p.size.y / 2)
		b.z0 = math.min(b.z0, p.pos.z - p.size.z / 2); b.z1 = math.max(b.z1, p.pos.z + p.size.z / 2)
	end
	return b
end

local PLAN_MARKERS = {
	quadruped = { "LegFL", "LegFR", "LegBL", "LegBR" },
	biped = { "LegL", "LegR", "ArmL", "ArmR" },
	winged = { "WingL", "WingR", "LegL", "LegR" },
	serpent = { "Hump1", "Hump2", "Neck" },
}

local total = 0
for _, s in Config.Species do
	local parts = CryptidModel.parts(Config, s.id)
	local n = #parts
	total += n
	truthy(n >= 6 and n <= MAX_PARTS, string.format("%s has %d parts (6..%d)", s.id, n, MAX_PARTS))
	local names = {}
	local eyes = 0
	for _, p in parts do
		truthy(names[p.name] == nil, s.id .. " part names are unique: " .. p.name)
		names[p.name] = true
		truthy(p.size.x > 0 and p.size.y > 0 and p.size.z > 0, s.id .. "." .. p.name .. " has a positive size")
		truthy(SHAPES[p.shape] == true, s.id .. "." .. p.name .. " shape " .. tostring(p.shape))
		truthy(MATERIALS[p.material] == true, s.id .. "." .. p.name .. " material " .. tostring(p.material))
		truthy(type(p.color) == "table" and #p.color == 3, s.id .. "." .. p.name .. " colour is {r,g,b}")
		if p.name == "EyeL" or p.name == "EyeR" then
			eyes += 1
			eq(p.material, "Neon", s.id .. " eyes glow")
			eq(p.color[1] .. "," .. p.color[2] .. "," .. p.color[3], table.concat(s.look.eye, ","), s.id .. " eyes use the species' eye colour")
		end
	end
	eq(eyes, 2, s.id .. " has two eyes")
	for _, marker in PLAN_MARKERS[s.plan] do
		truthy(names[marker], string.format("%s (%s) has %s", s.id, s.plan, marker))
	end
	local b = bbox(parts)
	truthy(math.abs(b.y0) < 0.05, string.format("%s stands on the ground (lowest point %.2f)", s.id, b.y0))
	truthy(b.y1 <= CAGE_HEIGHT, string.format("%s fits under the cage roof (%.2f <= %d)", s.id, b.y1, CAGE_HEIGHT))
	truthy(b.x1 - b.x0 <= CAGE_INNER and b.z1 - b.z0 <= CAGE_INNER,
		string.format("%s fits between the bars (%.2f x %.2f)", s.id, b.x1 - b.x0, b.z1 - b.z0))
	eq(CryptidModel.height(Config, s.id), b.y1, s.id .. " height() is the model's top")
	-- deterministic: a pure function of the species table
	local again = CryptidModel.parts(Config, s.id)
	local same = #again == n
	for i = 1, math.min(#again, n) do
		if again[i].name ~= parts[i].name or again[i].size.x ~= parts[i].size.x or again[i].pos.y ~= parts[i].pos.y then same = false end
	end
	truthy(same, s.id .. " builds the same model every time")
end
print(string.format("  %d parts across all eight models", total))

eq(#CryptidModel.parts(Config, "skinwalker"), 0, "an unknown species builds nothing")

eq(CryptidModel.aura(Config, "hodag"), "none", "Commons have no aura")
eq(CryptidModel.aura(Config, "dogman"), "dust", "Rares get dust")
eq(CryptidModel.aura(Config, "mothman"), "glow", "Legendaries get glow + sparkle")
eq(CryptidModel.aura(Config, "bigfoot"), "gold", "Mythics get the gold glow")

-- silhouettes differ between body plans, not just colours
local function dims(id)
	local b = bbox(CryptidModel.parts(Config, id))
	return string.format("%.1fx%.1fx%.1f", b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0)
end
local seen = {}
for _, s in Config.Species do
	local d = dims(s.id)
	truthy(seen[d] == nil, s.id .. " has its own bounding box " .. d)
	seen[d] = true
end

print(string.format("CryptidModel: %d passed, %d failed", passed, failed))
if failed > 0 then error("CryptidModel tests failed") end
