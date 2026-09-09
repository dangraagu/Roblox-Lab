-- Fx.luau — reusable visual-polish helpers, code-only (no art assets needed).
-- Server-side: builds a lighting rig + post-processing (Atmosphere/Bloom/ColorCorrection/
-- DepthOfField/SunRays) and particle helpers (dust motes, glow, sparkles, trails, beams).
-- Shared across the Roblox-Lab games; each game picks a preset from Fx.Presets.
--
-- Pure Instance creation — safe to call once at server start. Camera/HUD juice lives in the
-- sibling FxClient module (client-only).

local Lighting = game:GetService("Lighting")

local Fx = {}

-- create-or-update a single child of `parent` by class+name (idempotent).
local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local function applyProps(inst: Instance, props: { [string]: any }?)
	if not props then return end
	for k, v in props do
		(inst :: any)[k] = v
	end
end

-- Apply a full lighting preset. `preset` fields (all optional):
--   lighting = { Ambient, OutdoorAmbient, Brightness, ExposureCompensation, ClockTime,
--                GeographicLatitude, FogStart, FogEnd, FogColor, EnvironmentDiffuseScale,
--                EnvironmentSpecularScale, Technology }
--   atmosphere / bloom / colorCorrection / depthOfField / sunRays = prop tables (nil = remove)
function Fx.applyLighting(preset)
	preset = preset or {}
	local L = preset.lighting
	if L then
		for k, v in L do
			pcall(function()
				(Lighting :: any)[k] = v
			end)
		end
	end
	local map = {
		{ "atmosphere", "Atmosphere", "FxAtmosphere" },
		{ "bloom", "BloomEffect", "FxBloom" },
		{ "colorCorrection", "ColorCorrectionEffect", "FxColorCorrection" },
		{ "depthOfField", "DepthOfFieldEffect", "FxDoF" },
		{ "sunRays", "SunRaysEffect", "FxSunRays" },
	}
	for _, m in map do
		local key, className, name = m[1], m[2], m[3]
		local props = preset[key]
		if props then
			applyProps(ensure(Lighting, className, name), props)
		else
			local old = Lighting:FindFirstChild(name)
			if old then old:Destroy() end
		end
	end
end

-- A PointLight glow on a part. Returns the light.
function Fx.attachGlow(part: BasePart, color: Color3, brightness: number?, range: number?): PointLight
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Brightness = brightness or 2
	pl.Range = range or 16
	pl.Name = "FxGlow"
	pl.Parent = part
	return pl
end

-- Generic ParticleEmitter builder parented to `part`.
function Fx.emitter(part: BasePart, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = props.Name or "FxEmitter"
	for k, v in props do
		if k ~= "Name" then
			(pe :: any)[k] = v
		end
	end
	pe.Parent = part
	return pe
end

-- Floating dust motes inside a volume. `host` is an invisible anchored part you size/place.
function Fx.dust(host: BasePart, color: Color3?, rate: number?): ParticleEmitter
	return Fx.emitter(host, {
		Name = "FxDust",
		Rate = rate or 12,
		Lifetime = NumberRange.new(6, 12),
		Speed = NumberRange.new(0.2, 0.8),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(color or Color3.fromRGB(220, 225, 235)),
		Acceleration = Vector3.new(0, -0.4, 0),
		LightEmission = 0.4,
		LockedToPart = false,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
	})
end

-- An invisible volume part to host dust (parents itself to `parent`).
function Fx.dustVolume(parent: Instance, size: Vector3, cframe: CFrame, color: Color3?, rate: number?): BasePart
	local p = Instance.new("Part")
	p.Name = "FxDustVolume"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	Fx.dust(p, color, rate)
	return p
end

-- Sparkle glints (great for crystals/gems).
function Fx.sparkle(part: BasePart, color: Color3?): ParticleEmitter
	return Fx.emitter(part, {
		Name = "FxSparkle",
		Rate = 6,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(0, 0.5),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0.12),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(color or Color3.fromRGB(255, 255, 255)),
		LightEmission = 1,
		Rotation = NumberRange.new(0, 360),
	})
end

-- A motion Trail between two attachments on a part (e.g. a jumping player root).
function Fx.trail(part: BasePart, color: Color3?, lifetime: number?): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = "FxTrailA0"
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "FxTrailA1"
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Name = "FxTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = lifetime or 0.5
	trail.Color = ColorSequence.new(color or Color3.fromRGB(160, 210, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = part
	return trail
end

-- ---------------------------------------------------------------- Presets
Fx.Presets = {
	-- cold, dark, dense — anomaly / horror
	Horror = {
		lighting = {
			Technology = Enum.Technology.Future,
			Ambient = Color3.fromRGB(20, 22, 30),
			OutdoorAmbient = Color3.fromRGB(15, 18, 28),
			Brightness = 1,
			ExposureCompensation = -0.15,
			ClockTime = 0.2,
			FogStart = 10,
			FogEnd = 120,
			FogColor = Color3.fromRGB(12, 14, 22),
			EnvironmentDiffuseScale = 0.4,
			EnvironmentSpecularScale = 0.4,
		},
		atmosphere = { Density = 0.42, Offset = 0.1, Color = Color3.fromRGB(90, 100, 120), Decay = Color3.fromRGB(30, 34, 46), Glare = 0.1, Haze = 1.6 },
		bloom = { Intensity = 0.5, Size = 24, Threshold = 1.1 },
		colorCorrection = { Brightness = -0.02, Contrast = 0.18, Saturation = -0.35, TintColor = Color3.fromRGB(200, 210, 235) },
		depthOfField = { FarIntensity = 0.08, FocusDistance = 40, InFocusRadius = 30, NearIntensity = 0.35 },
	},
	-- warm, glowing, teal/amber — grow-a-crystal cavern
	Cozy = {
		lighting = {
			Technology = Enum.Technology.Future,
			Ambient = Color3.fromRGB(40, 44, 58),
			OutdoorAmbient = Color3.fromRGB(35, 40, 55),
			Brightness = 2,
			ExposureCompensation = 0.1,
			ClockTime = 0,
			FogStart = 20,
			FogEnd = 240,
			FogColor = Color3.fromRGB(22, 26, 40),
		},
		atmosphere = { Density = 0.3, Offset = 0.2, Color = Color3.fromRGB(120, 150, 170), Decay = Color3.fromRGB(60, 80, 110), Glare = 0.2, Haze = 1.2 },
		bloom = { Intensity = 0.9, Size = 30, Threshold = 0.9 },
		colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.18, TintColor = Color3.fromRGB(220, 235, 245) },
		depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
	},
	-- bright, airy, sun-rayed — +1 jump sky temple
	Temple = {
		lighting = {
			Technology = Enum.Technology.Future,
			Ambient = Color3.fromRGB(120, 125, 140),
			OutdoorAmbient = Color3.fromRGB(150, 160, 185),
			Brightness = 3,
			ExposureCompensation = 0.15,
			ClockTime = 15.5,
			GeographicLatitude = 20,
			FogStart = 100,
			FogEnd = 900,
			FogColor = Color3.fromRGB(200, 220, 245),
		},
		atmosphere = { Density = 0.32, Offset = 0.25, Color = Color3.fromRGB(200, 220, 245), Decay = Color3.fromRGB(130, 160, 200), Glare = 0.4, Haze = 2 },
		bloom = { Intensity = 1.1, Size = 28, Threshold = 0.85 },
		colorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.15, TintColor = Color3.fromRGB(255, 250, 240) },
		sunRays = { Intensity = 0.18, Spread = 0.9 },
	},
	-- moody, torch-lit — maze (layered ON TOP of the maze's own per-level fog; no fog override)
	Maze = {
		atmosphere = { Density = 0.35, Offset = 0.15, Color = Color3.fromRGB(80, 85, 105), Decay = Color3.fromRGB(30, 30, 45), Glare = 0.15, Haze = 1.4 },
		bloom = { Intensity = 0.7, Size = 26, Threshold = 1 },
		colorCorrection = { Brightness = -0.01, Contrast = 0.14, Saturation = -0.1, TintColor = Color3.fromRGB(230, 225, 235) },
		depthOfField = { FarIntensity = 0.06, FocusDistance = 35, InFocusRadius = 28, NearIntensity = 0.25 },
	},
}

return Fx
