--!strict
-- CryptidModel.luau - the eight cryptids as plain Part descriptions. Pure data out.
--
-- DESIGN.md section 7: four body plans (quadruped, biped, winged biped, serpent) built from Parts,
-- with per-species proportions and colours from Config.Species[].look, at most 14 Parts each.
-- Code-only, no assets. The server turns each description into a Model once, into
-- ServerStorage.CryptidTemplates, and clones it; a spec checks every model here without Roblox.
--
-- Model space: origin on the ground at the model's centre, +y up, the FACE looks towards -z (the
-- yard, when caged; the road, on a pedestal). Sizes and positions in studs.
--
-- Pure: cfg in, tables out. Requires NOTHING.

local CryptidModel = {}

local function v(x: number, y: number, z: number): any
	return { x = x, y = y, z = z }
end

local function add(out: { any }, name: string, shape: string, material: string, color: { number }, size: any, pos: any)
	table.insert(out, { name = name, shape = shape, material = material, color = color, size = size, pos = pos })
end

local function quadruped(s: number, look: any, out: { any })
	local body, accent, eye = look.body, look.accent, look.eye
	add(out, "Body", "Block", "Fabric", body, v(1.6 * s, 1.2 * s, 2.6 * s), v(0, 1.6 * s, 0))
	add(out, "Head", "Block", "Fabric", body, v(1.0 * s, 0.9 * s, 1.0 * s), v(0, 2.2 * s, -1.6 * s))
	local legs: { { name: string, sx: number, sz: number } } = {
		{ name = "LegFL", sx = -1, sz = -1 },
		{ name = "LegFR", sx = 1, sz = -1 },
		{ name = "LegBL", sx = -1, sz = 1 },
		{ name = "LegBR", sx = 1, sz = 1 },
	}
	for _, leg in legs do
		add(out, leg.name, "Block", "Fabric", body, v(0.4 * s, 1.0 * s, 0.4 * s), v(leg.sx * 0.55 * s, 0.5 * s, leg.sz * 0.95 * s))
	end
	add(out, "EyeL", "Ball", "Neon", eye, v(0.25 * s, 0.25 * s, 0.25 * s), v(-0.25 * s, 2.35 * s, -2.12 * s))
	add(out, "EyeR", "Ball", "Neon", eye, v(0.25 * s, 0.25 * s, 0.25 * s), v(0.25 * s, 2.35 * s, -2.12 * s))
	add(out, "Tail", "Block", "Fabric", accent, v(0.25 * s, 0.25 * s, 0.9 * s), v(0, 1.9 * s, 1.7 * s))
	if look.antlers then
		add(out, "AntlerL", "Block", "Slate", accent, v(0.15 * s, 1.0 * s, 0.15 * s), v(-0.35 * s, 3.1 * s, -1.5 * s))
		add(out, "AntlerR", "Block", "Slate", accent, v(0.15 * s, 1.0 * s, 0.15 * s), v(0.35 * s, 3.1 * s, -1.5 * s))
	end
	if look.horns then
		add(out, "HornL", "Block", "Slate", accent, v(0.2 * s, 0.6 * s, 0.2 * s), v(-0.4 * s, 2.9 * s, -1.4 * s))
		add(out, "HornR", "Block", "Slate", accent, v(0.2 * s, 0.6 * s, 0.2 * s), v(0.4 * s, 2.9 * s, -1.4 * s))
	end
	if look.ridge then
		add(out, "Ridge", "Block", "Slate", accent, v(0.3 * s, 0.35 * s, 2.2 * s), v(0, 2.35 * s, 0))
	end
	if look.spines then
		add(out, "SpineF", "Block", "Slate", accent, v(0.2 * s, 0.6 * s, 0.2 * s), v(0, 2.5 * s, -0.5 * s))
		add(out, "SpineB", "Block", "Slate", accent, v(0.2 * s, 0.6 * s, 0.2 * s), v(0, 2.5 * s, 0.5 * s))
	end
end

local function biped(s: number, look: any, out: { any })
	local body, accent, eye = look.body, look.accent, look.eye
	add(out, "LegL", "Block", "Fabric", body, v(0.5 * s, 1.8 * s, 0.5 * s), v(-0.35 * s, 0.9 * s, 0))
	add(out, "LegR", "Block", "Fabric", body, v(0.5 * s, 1.8 * s, 0.5 * s), v(0.35 * s, 0.9 * s, 0))
	add(out, "Torso", "Block", "Fabric", body, v(1.6 * s, 1.8 * s, 0.9 * s), v(0, 2.7 * s, 0))
	add(out, "ArmL", "Block", "Fabric", body, v(0.45 * s, 1.7 * s, 0.45 * s), v(-1.05 * s, 2.65 * s, 0))
	add(out, "ArmR", "Block", "Fabric", body, v(0.45 * s, 1.7 * s, 0.45 * s), v(1.05 * s, 2.65 * s, 0))
	add(out, "Head", "Block", "Fabric", accent, v(0.9 * s, 0.9 * s, 0.9 * s), v(0, 4.05 * s, 0))
	add(out, "EyeL", "Ball", "Neon", eye, v(0.2 * s, 0.2 * s, 0.2 * s), v(-0.22 * s, 4.15 * s, -0.46 * s))
	add(out, "EyeR", "Ball", "Neon", eye, v(0.2 * s, 0.2 * s, 0.2 * s), v(0.22 * s, 4.15 * s, -0.46 * s))
	if look.snout then
		add(out, "Snout", "Block", "Fabric", accent, v(0.45 * s, 0.35 * s, 0.5 * s), v(0, 3.9 * s, -0.65 * s))
	end
	if look.ears then
		add(out, "EarL", "Block", "Fabric", accent, v(0.2 * s, 0.45 * s, 0.15 * s), v(-0.3 * s, 4.7 * s, 0))
		add(out, "EarR", "Block", "Fabric", accent, v(0.2 * s, 0.45 * s, 0.15 * s), v(0.3 * s, 4.7 * s, 0))
	end
	if not look.snout then
		-- the large ape silhouette: a heavy brow and a chest of darker fur
		add(out, "Brow", "Block", "Fabric", accent, v(1.0 * s, 0.25 * s, 0.3 * s), v(0, 4.35 * s, -0.4 * s))
		add(out, "Chest", "Block", "Fabric", accent, v(1.2 * s, 1.0 * s, 0.2 * s), v(0, 2.9 * s, -0.5 * s))
	end
end

local function winged(s: number, look: any, out: { any })
	local body, accent, eye = look.body, look.accent, look.eye
	add(out, "LegL", "Block", "Fabric", body, v(0.4 * s, 1.4 * s, 0.4 * s), v(-0.3 * s, 0.7 * s, 0))
	add(out, "LegR", "Block", "Fabric", body, v(0.4 * s, 1.4 * s, 0.4 * s), v(0.3 * s, 0.7 * s, 0))
	add(out, "Torso", "Block", "Fabric", body, v(1.2 * s, 1.6 * s, 0.8 * s), v(0, 2.2 * s, 0))
	add(out, "Head", "Block", "Fabric", body, v(0.8 * s, 0.8 * s, 0.8 * s), v(0, 3.4 * s, 0))
	add(out, "WingL", "Block", "Fabric", accent, v(2.0 * s, 1.8 * s, 0.15 * s), v(-1.5 * s, 2.6 * s, 0.45 * s))
	add(out, "WingR", "Block", "Fabric", accent, v(2.0 * s, 1.8 * s, 0.15 * s), v(1.5 * s, 2.6 * s, 0.45 * s))
	local eyeSize = if look.bigEyes then 0.4 * s else 0.22 * s
	add(out, "EyeL", "Ball", "Neon", eye, v(eyeSize, eyeSize, eyeSize), v(-0.2 * s, 3.5 * s, -0.42 * s))
	add(out, "EyeR", "Ball", "Neon", eye, v(eyeSize, eyeSize, eyeSize), v(0.2 * s, 3.5 * s, -0.42 * s))
	if look.horns then
		add(out, "HornL", "Block", "Slate", accent, v(0.15 * s, 0.5 * s, 0.15 * s), v(-0.25 * s, 4.05 * s, 0))
		add(out, "HornR", "Block", "Slate", accent, v(0.15 * s, 0.5 * s, 0.15 * s), v(0.25 * s, 4.05 * s, 0))
		add(out, "Tail", "Block", "Fabric", accent, v(0.2 * s, 0.2 * s, 1.4 * s), v(0, 1.4 * s, 1.0 * s))
	end
end

local function serpent(s: number, look: any, out: { any })
	local body, accent, eye = look.body, look.accent, look.eye
	add(out, "Hump1", "Ball", "SmoothPlastic", body, v(1.6 * s, 1.6 * s, 1.6 * s), v(0, 0.8 * s, 0.6 * s))
	add(out, "Hump2", "Ball", "SmoothPlastic", body, v(1.3 * s, 1.3 * s, 1.3 * s), v(0, 0.65 * s, 2.1 * s))
	add(out, "Hump3", "Ball", "SmoothPlastic", body, v(1.0 * s, 1.0 * s, 1.0 * s), v(0, 0.5 * s, 3.2 * s))
	add(out, "Neck", "Block", "SmoothPlastic", body, v(0.6 * s, 3.0 * s, 0.6 * s), v(0, 1.9 * s, -0.7 * s))
	add(out, "Head", "Block", "SmoothPlastic", accent, v(0.7 * s, 0.6 * s, 1.2 * s), v(0, 3.6 * s, -1.1 * s))
	add(out, "EyeL", "Ball", "Neon", eye, v(0.18 * s, 0.18 * s, 0.18 * s), v(-0.3 * s, 3.75 * s, -1.3 * s))
	add(out, "EyeR", "Ball", "Neon", eye, v(0.18 * s, 0.18 * s, 0.18 * s), v(0.3 * s, 3.75 * s, -1.3 * s))
	add(out, "FlipperL", "Block", "SmoothPlastic", accent, v(1.0 * s, 0.15 * s, 0.6 * s), v(-1.0 * s, 0.3 * s, 0.2 * s))
	add(out, "FlipperR", "Block", "SmoothPlastic", accent, v(1.0 * s, 0.15 * s, 0.6 * s), v(1.0 * s, 0.3 * s, 0.2 * s))
	add(out, "Tail", "Block", "SmoothPlastic", accent, v(0.4 * s, 0.3 * s, 1.2 * s), v(0, 0.2 * s, 3.9 * s))
end

local PLANS = {
	quadruped = quadruped,
	biped = biped,
	winged = winged,
	serpent = serpent,
}

local function speciesOf(cfg: any, id: string): any
	for _, s in cfg.Species do
		if s.id == id then return s end
	end
	return nil
end

-- A list of { name, shape, material, color {r,g,b}, size {x,y,z}, pos {x,y,z} }; empty for an
-- unknown species.
function CryptidModel.parts(cfg: any, id: string): { any }
	local s = speciesOf(cfg, id)
	local out = {}
	if not s then return out end
	local build = PLANS[s.plan]
	if build then
		build(s.look.scale, s.look, out)
	end
	return out
end

-- The top of the model, for label heights and the carried offset.
function CryptidModel.height(cfg: any, id: string): number
	local top = 0
	for _, p in CryptidModel.parts(cfg, id) do
		top = math.max(top, p.pos.y + p.size.y / 2)
	end
	return top
end

-- Tier aura: Rare dust, Legendary glow + sparkle, Mythic the same in gold.
function CryptidModel.aura(cfg: any, id: string): string
	local s = speciesOf(cfg, id)
	if not s then return "none" end
	return ({ "none", "dust", "glow", "gold" })[s.tier] or "none"
end

return CryptidModel
