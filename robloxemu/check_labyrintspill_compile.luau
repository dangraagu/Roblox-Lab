-- Labyrinth Mariozo — every source in the bundle compiles. Run: luau check_labyrintspill_compile.luau 2>&1
-- Rebuild the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- `rojo build` does not compile Luau, and this machine has no luau-compile binary, so this uses the same
-- compiler front end through loadstring: each module is compiled, nothing is executed. It also counts the
-- sources, so a module that silently fell out of the bundle is noticed.

local bundle = require("./build/labyrint-spill")
local passed, failed = 0, 0
local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)
for _, k in keys do
	local e = bundle[k]
	local fn, err = loadstring(e.source, "@" .. e.path)
	if fn then passed += 1 else failed += 1; print("FAIL: " .. k .. " does not compile: " .. tostring(err)) end
end
-- the eye-candy modules this work added must all be in the bundle
for _, k in { "shared/Biomes", "shared/BiomeArt", "shared/CellHazards", "shared/EnvBands", "shared/Rest", "shared/BreakRoom",
	"client/Biome.client", "client/RestClient.client" } do
	if bundle[k] then passed += 1 else failed += 1; print("FAIL: " .. k .. " is missing from the bundle") end
end
print(string.format("labyrintspill compile: %d passed, %d failed (%d sources)", passed, failed, #keys))
if failed > 0 then error("compile failed", 0) end
