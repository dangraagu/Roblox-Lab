-- StormGrow — every game source compiles, and none requires by string.
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_compile.luau 2>&1
--
-- The checklist's gate starts with `luau-compile --binary` over every source; that binary is not on this
-- machine (only luau.exe is), so this keeps the compile half of the gate with loadstring (nothing runs),
-- and fails any source that calls require with a string: that resolves in the luau CLI and FAILS in
-- Roblox, the mistake that once made a server in this repo fail to load with every unit test green.
-- It also fails any source that reads os.clock() for game timing: os.clock is CPU time, frozen in the
-- headless emulator (deep-vein Main.server.luau:1108), so a cooldown built on it can never be tested.

local bundle = require("./build/stormgrow")
local passed, failed = 0, 0
local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)
for _, key in keys do
	local entry = bundle[key]
	local fn, err = loadstring(entry.source, "@" .. entry.path)
	if fn then passed += 1 else failed += 1; print("FAIL: " .. key .. " does not compile: " .. tostring(err)) end
	local code = {}
	for line in string.gmatch(entry.source .. "\n", "([^\n]*)\n") do
		table.insert(code, (string.gsub(line, "%-%-.*$", "")))
	end
	local src = table.concat(code, "\n")
	if string.find(src, "require%s*%(%s*[\"']") then failed += 1; print("FAIL: " .. key .. " requires by string (invalid in Roblox)") else passed += 1 end
	if string.find(src, "os%.clock%s*%(") then failed += 1; print("FAIL: " .. key .. " times something with os.clock()") else passed += 1 end
end
print(string.format("stormgrow compile: %d sources, %d passed, %d failed", #keys, passed, failed))
if failed > 0 then error("stormgrow compile check failed", 0) end
