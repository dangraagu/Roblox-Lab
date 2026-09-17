-- Fx.spec — the visual kit (Fx.luau, FxClient.luau). Both reach for `game` at load, so unlike the
-- other specs this one runs them inside robloxemu's harness, from the built bundle.
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       cd ../facility-nightmare && luau tests/Fx.spec.luau
local Harness = require("../../robloxemu/emu/harness")
local bundle = require("../../robloxemu/build/facility-nightmare")

local h = Harness.new({ bundle = bundle, name = "fx-spec" })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- `require` itself is a builtin the compiler resolves in this chunk, so the harness's Instance-taking
-- version is reached through the harness directly.
local Fx = h:_require(h.ReplicatedStorage:FindFirstChild("Fx"))
local FxClient = h:_require(h.ReplicatedStorage:FindFirstChild("FxClient"))

--============================================================ the Facility preset

local P, Hr = Fx.Presets.Facility, Fx.Presets.Horror
truthy(P ~= nil, "Fx.Presets.Facility exists")
local function darker(a, b) return a.R <= b.R and a.G <= b.G and a.B <= b.B and (a.R + a.G + a.B) < (b.R + b.G + b.B) end
truthy(darker(P.lighting.Ambient, Hr.lighting.Ambient), "its Ambient is darker than Horror's (an unlit room reads DARK, not dim)")
truthy(darker(P.lighting.OutdoorAmbient, Hr.lighting.OutdoorAmbient), "…and so is its OutdoorAmbient")
eq(P.lighting.FogStart, nil, "no legacy fog fields: an Atmosphere replaces them")
truthy(P.atmosphere ~= nil and P.bloom ~= nil and P.colorCorrection ~= nil, "atmosphere, bloom and colour correction")

Fx.applyLighting(P)
local L = h.Lighting
eq(L.Ambient, P.lighting.Ambient, "applyLighting writes Ambient")
eq(L.Brightness, P.lighting.Brightness, "…and Brightness")
for _, name in { "FxAtmosphere", "FxBloom", "FxColorCorrection", "FxDoF" } do
	truthy(L:FindFirstChild(name) ~= nil, "applyLighting creates " .. name)
end
eq(L:FindFirstChild("FxSunRays"), nil, "…and no sun rays underground")
Fx.applyLighting(P)
local count = 0
for _, c in L:GetChildren() do if c.Name == "FxAtmosphere" then count += 1 end end
eq(count, 1, "applying twice does not stack effects")

--============================================================ helpers the build uses

do
	local folder = Instance.new("Folder")
	folder.Parent = h.workspace
	local vol = Fx.dustVolume(folder, Vector3.new(24, 10, 24), CFrame.new(1, 2, 3), Color3.new(1, 1, 1), 4)
	eq(vol.Parent, folder, "dustVolume parents its host part")
	eq(vol.Transparency, 1, "…invisible")
	eq(vol.CanCollide, false, "…not solid")
	eq(vol.CanQuery, false, "…not queryable")
	local em = vol:FindFirstChild("FxDust")
	truthy(em ~= nil and em.ClassName == "ParticleEmitter", "…with a dust emitter")
	eq(em and em.Rate, 4, "…at the rate asked for")

	local p = Instance.new("Part")
	p.Parent = folder
	local glow = Fx.attachGlow(p, Color3.new(1, 0.5, 0), 1.5, 12)
	eq(glow.Parent, p, "attachGlow parents a PointLight")
	eq(glow.Range, 12, "…with the range asked for")
end

do
	local gui = Instance.new("Frame")
	FxClient.theme(gui, { corner = 10, stroke = Color3.new(1, 1, 1) })
	truthy(gui:FindFirstChildOfClass("UICorner") ~= nil, "FxClient.theme rounds a frame")
	truthy(gui:FindFirstChildOfClass("UIStroke") ~= nil, "…and strokes it")
	FxClient.theme(gui, { corner = 10, stroke = Color3.new(1, 1, 1) })
	local corners = 0
	for _, c in gui:GetChildren() do if c.ClassName == "UICorner" then corners += 1 end end
	eq(corners, 1, "…idempotently")
	local ok = pcall(function()
		FxClient.shake(0.5, 1)
		FxClient.flash(Color3.new(1, 0, 0), 0.5, 0.5)
		FxClient.fovPunch(-3, 0.1, 0.2)
	end)
	truthy(ok, "the camera juice is a safe no-op on the server")
end

eq(#h:errors(), 0, "no scheduler errors")
print(string.format("Fx: %d passed, %d failed", passed, failed))
