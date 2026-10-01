-- CropArt.luau — the crop models on every tile, and their marks (DESIGN.md §3.4). Required by Farm.client only.
-- Code-only art: at most Config.Budget.MaxPartsPerCrop (5) Parts per crop: a foliage part and a produce part,
-- plus one part per mark. Every part is client-built, anchored, and CanCollide / CanQuery / CanTouch false,
-- so a tap on a tall sunflower lands on its tile's hitbox, never on the crop (DESIGN.md §12.2).
--
-- The marks differ in SHAPE and MOTION, not only colour (a colour-blind player must tell them apart):
--   ⚡ Charged   a jagged neon spark that flickers and jumps around the produce;
--   ❄️ Frosted   an angular ice shell that encloses it, still;
--   🌈 Prismatic a flat halo ring above it that turns and cycles through the rainbow.
-- A Tempest (all three) wears all of them and the whole crop turns slowly. Ripe crops glow and bob.

local CropArt = {}

local SHAPES = {
	root = { foliage = { size = Vector3.new(1.4, 1.6, 1.4), y = 1.1 }, produce = { shape = "Ball", size = Vector3.new(1.5, 1.5, 1.5), y = 0.45 } },
	stalk = { foliage = { size = Vector3.new(0.6, 5, 0.6), y = 2.5 }, produce = { shape = "Block", size = Vector3.new(0.9, 1.9, 0.9), y = 3.1, x = 0.55 } },
	bush = { foliage = { size = Vector3.new(3, 2.6, 3), y = 1.3, ball = true }, produce = { shape = "Ball", size = Vector3.new(1.3, 1.3, 1.3), y = 1.9, z = -1.3 } },
	flower = { foliage = { size = Vector3.new(0.45, 6, 0.45), y = 3 }, produce = { shape = "Cylinder", size = Vector3.new(0.5, 3.2, 3.2), y = 6.2 } },
	gourd = { foliage = { size = Vector3.new(3.4, 0.3, 3.4), y = 0.15 }, produce = { shape = "Ball", size = Vector3.new(3.4, 2.6, 3.4), y = 1.3 } },
	melon = { foliage = { size = Vector3.new(3.6, 0.3, 3.6), y = 0.15 }, produce = { shape = "Ball", size = Vector3.new(4, 2.5, 2.9), y = 1.25 } },
	orb = { foliage = { size = Vector3.new(0.5, 4, 0.5), y = 2 }, produce = { shape = "Ball", size = Vector3.new(2.4, 2.4, 2.4), y = 4.4, neon = true } },
}

local function c3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function newPart(folder: Instance, name: string, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do (p :: any)[k] = v end
	p.Parent = folder
	return p
end

-- A crop view on the soil top `base` (CFrame, Y up). -> view
function CropArt.build(folder: Instance, crop: any, base: CFrame): any
	local shape = SHAPES[crop.shape] or SHAPES.root
	local f = shape.foliage
	local foliage = newPart(folder, "Foliage", { Size = f.size, Color = c3(crop.leaf), Material = Enum.Material.Grass,
		Shape = if f.ball then Enum.PartType.Ball else Enum.PartType.Block })
	local pr = shape.produce
	local produce = newPart(folder, "Produce", { Size = pr.size, Color = c3(crop.color),
		Shape = Enum.PartType[pr.shape], Material = if pr.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic })
	return {
		crop = crop, base = base, shape = shape, foliage = foliage, produce = produce, folder = folder,
		marks = 0, ice = nil, halo = nil, spark = nil, emitter = nil, stage = -1, ripe = false,
	}
end

function CropArt.partCount(view: any): number
	local n = 2
	if view.ice then n += 1 end
	if view.halo then n += 1 end
	if view.spark then n += 1 end
	return n
end

local function produceCF(view: any, lift: number): CFrame
	local pr = view.shape.produce
	local s = 0.25 + 0.75 * math.max(view.stage, 0)
	local cf = view.base * CFrame.new(pr.x or 0, pr.y * (0.4 + 0.6 * s) + lift, pr.z or 0)
	if pr.shape == "Cylinder" then cf = cf * CFrame.Angles(0, math.rad(90), 0) end
	return cf
end

-- Growth stage 0..1 and ripeness. Only called when the stage bucket or ripeness changed.
function CropArt.setStage(view: any, stage: number, ripe: boolean)
	view.stage = stage
	view.ripe = ripe
	local f = view.shape.foliage
	local fs = 0.4 + 0.6 * math.min(1, stage * 1.5)
	view.foliage.Size = f.size * fs
	view.foliage.CFrame = view.base * CFrame.new(0, f.y * fs, 0)
	local ps = 0.2 + 0.8 * stage
	view.produce.Size = view.shape.produce.size * ps
	view.produce.CFrame = produceCF(view, 0)
	local col = c3(view.crop.color)
	view.produce.Color = if ripe then col:Lerp(Color3.new(1, 1, 1), 0.2) else col
	view.produce.Transparency = if stage < 0.15 then 1 else 0
end

function CropArt.setMarks(view: any, marks: number, M: any)
	if marks == view.marks then return end
	view.marks = marks
	local size = view.shape.produce.size
	local d = math.max(size.X, size.Z)
	local function has(kind: string): boolean
		return bit32.band(marks, M[kind].bit) ~= 0
	end
	if has("frost") and view.ice == nil then
		view.ice = newPart(view.folder, "IceShell", { Size = size * 1.35, Color = Color3.fromRGB(200, 235, 255),
			Material = Enum.Material.Ice, Transparency = 0.45 })
	elseif not has("frost") and view.ice then
		view.ice:Destroy()
		view.ice = nil
	end
	if has("rainbow") and view.halo == nil then
		view.halo = newPart(view.folder, "PrismHalo", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, d * 1.5, d * 1.5),
			Material = Enum.Material.Neon, Transparency = 0.25 })
	elseif not has("rainbow") and view.halo then
		view.halo:Destroy()
		view.halo = nil
	end
	if has("storm") and view.spark == nil then
		view.spark = newPart(view.folder, "ChargeSpark", { Size = Vector3.new(0.25, d * 1.1, 0.25), Color = Color3.fromRGB(140, 200, 255),
			Material = Enum.Material.Neon })
	elseif not has("storm") and view.spark then
		view.spark:Destroy()
		view.spark = nil
	end
end

-- Per-frame motion, only for crops near the camera (Farm.client decides).
function CropArt.animate(view: any, t: number, phase: number)
	local lift = if view.ripe then 0.25 + math.sin(t * 3 + phase) * 0.25 else 0
	local spin = if view.marks == 7 then CFrame.Angles(0, t * 0.8, 0) else CFrame.new()
	local pcf = produceCF(view, lift) * spin
	view.produce.CFrame = pcf
	local pos = pcf.Position
	if view.ice then view.ice.CFrame = pcf end
	if view.halo then
		local d = math.max(view.produce.Size.X, view.produce.Size.Z)
		view.halo.CFrame = CFrame.new(pos + Vector3.new(0, view.produce.Size.Y / 2 + 0.5, 0)) * CFrame.Angles(0, t * 1.5, math.rad(90))
		view.halo.Color = Color3.fromHSV((t * 0.25 + phase * 0.1) % 1, 0.8, 1)
		view.halo.Size = Vector3.new(0.2, d * 1.4, d * 1.4)
	end
	if view.spark then
		local a = math.floor(t * 12 + phase) * 2.4
		local r = math.max(view.produce.Size.X, view.produce.Size.Z) * 0.6
		view.spark.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r)) * CFrame.Angles(0.5 * math.sin(a), a, 0.6)
		view.spark.Transparency = if math.sin(t * 30 + phase) > -0.2 then 0 else 0.9
	end
end

-- A particle emitter for a marked crop (Farm.client keeps only the nearest MaxMarkEmitters).
function CropArt.setEmitter(view: any, on: boolean, M: any)
	if on and view.emitter == nil and view.marks ~= 0 then
		local e = Instance.new("ParticleEmitter")
		e.Name = "MarkFx"
		local cols = {}
		if bit32.band(view.marks, M.storm.bit) ~= 0 then table.insert(cols, Color3.fromRGB(140, 200, 255)) end
		if bit32.band(view.marks, M.frost.bit) ~= 0 then table.insert(cols, Color3.fromRGB(240, 250, 255)) end
		if bit32.band(view.marks, M.rainbow.bit) ~= 0 then table.insert(cols, Color3.fromRGB(255, 120, 220)) end
		e.Color = if #cols >= 2 then ColorSequence.new(cols[1], cols[#cols]) else ColorSequence.new(cols[1])
		e.Size = NumberSequence.new(0.2)
		e.Rate = 6
		e.Lifetime = NumberRange.new(0.4, 0.9)
		e.Speed = NumberRange.new(1, 3)
		e.LightEmission = 1
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = view.produce
		view.emitter = e
	elseif (not on or view.marks == 0) and view.emitter then
		view.emitter:Destroy()
		view.emitter = nil
	end
end

-- The view's folder goes too: Farm.client builds a fresh Crop_<slot>_<key> folder for every planting, and until
-- REVIEW-1 the old one stayed behind empty (one Folder per harvest for the whole session; check_stormgrow_stream).
function CropArt.destroy(view: any)
	for _, k in { "foliage", "produce", "ice", "halo", "spark" } do
		if view[k] then
			view[k]:Destroy()
			view[k] = nil
		end
	end
	view.emitter = nil
	if view.folder then
		view.folder:Destroy()
		view.folder = nil
	end
end

return CropArt
