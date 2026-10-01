-- Meteor Drop Tycoon — every game source compiles, none requires by string, and every Enum item it names is
-- one Roblox actually has.
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon_compile.luau 2>&1
--
-- luau-compile.exe and luau-analyze.exe are gone from this machine (steal-a-cryptid's compile check records
-- when), so the compile half of the checklist's gate is kept with loadstring (nothing runs). Two more traps
-- the emulator cannot see on its own:
--   * `require("./X")` resolves in the luau CLI and FAILS in Roblox;
--   * robloxemu's Enum is permissive (an unknown item is created on first touch), so `Enum.Material.Nean`
--     would pass every headless check and raise in Roblox. Every Enum.Family.Item in the sources must be on
--     the list below, which was written by hand from the Roblox API, not from the sources.

local bundle = require("./build/meteor-drop-tycoon")

local KNOWN = {
	Material = { "Neon", "Metal", "SmoothPlastic", "Glass", "Grass", "Concrete", "Wood", "Slate", "Marble", "Air",
		"Snow", "Sand", "Rock", "Ice", "Foil", "DiamondPlate", "Basalt", "Plastic" },
	PartType = { "Ball", "Cylinder", "Block" },
	Font = { "Gotham", "GothamBold", "GothamBlack" },
	EasingStyle = { "Quad", "Sine", "Quart", "Linear", "Back" },
	EasingDirection = { "In", "Out", "InOut" },
	TextXAlignment = { "Left", "Right", "Center" },
	Technology = { "Future" },
	SurfaceType = { "Smooth" },
	ZIndexBehavior = { "Sibling" },
	SurfaceGuiSizingMode = { "PixelsPerStud", "FixedSize" },
	NormalId = { "Front", "Top", "Back", "Bottom", "Left", "Right" },
	ApplyStrokeMode = { "Border", "Contextual" },
	ScrollingDirection = { "Y", "X", "XY" },
	RenderPriority = { "Camera" },
	ParticleEmitterShapeStyle = { "Volume", "Surface" },
	ParticleEmitterShape = { "Box" },
	DataStoreRequestType = { "GetAsync" },
	CameraType = { "Scriptable", "Custom" },
}
local known = {}
for fam, items in KNOWN do
	for _, item in items do known[fam .. "." .. item] = true end
end

local passed, failed = 0, 0
local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)
local enumUses = 0
for _, key in keys do
	local src = bundle[key].source
	local fn, err = loadstring(src, "@" .. key)
	if fn then passed += 1 else failed += 1; print("FAIL: " .. key .. " does not compile: " .. tostring(err)) end
	-- code only: line comments are stripped first (the sources explain the trap in comments, which is fine)
	local code = {}
	for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
		local cut = string.find(line, "--", 1, true)
		table.insert(code, if cut then string.sub(line, 1, cut - 1) else line)
	end
	local codeText = table.concat(code, "\n")
	local stringRequire = string.match(codeText, "require%s*%(%s*[\"']")
	if stringRequire then failed += 1; print("FAIL: " .. key .. " requires by string (invalid in Roblox)") else passed += 1 end
	for fam, item in string.gmatch(codeText, "Enum%.(%a+)%.(%a+)") do
		enumUses += 1
		if known[fam .. "." .. item] then passed += 1 else
			failed += 1
			print("FAIL: " .. key .. " names Enum." .. fam .. "." .. item .. ", which is not on the known list")
		end
	end
end
print(string.format("meteordroptycoon compile: %d sources, %d Enum uses; %d passed, %d failed", #keys, enumUses, passed, failed))
if failed > 0 then error("meteordroptycoon compile check failed", 0) end
