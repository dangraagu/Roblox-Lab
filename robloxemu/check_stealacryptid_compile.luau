-- Steal a Cryptid - every game source compiles, and none requires by string.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_compile.luau 2>&1
--
-- CLAUDE.md's gate list starts with `luau-compile --binary` over every source. On 2026-09-23 the shared
-- scratchpad that held luau-compile.exe and luau-analyze.exe was wiped by another process and neither
-- binary exists on this machine any more (luau.exe survived). This file keeps the compile half of that
-- gate with the tool that is left: it compiles every bundled source with loadstring (nothing runs), and
-- it fails any source that calls require with a string, the mistake that once made a server in this
-- repo fail to load in Roblox with every unit test green. Tests and checks compile when they run.

local bundle = require("./build/steal-a-cryptid")
local passed, failed = 0, 0
local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)
for _, key in keys do
	local entry = bundle[key]
	local fn, err = loadstring(entry.source, "@" .. entry.path)
	if fn then passed += 1 else failed += 1; print("FAIL: " .. key .. " does not compile: " .. tostring(err)) end
	-- code only: comments here name the trap on purpose ("a bare `require("./X")` is invalid")
	local code = {}
	for line in string.gmatch(entry.source .. "\n", "([^\n]*)\n") do
		table.insert(code, (string.gsub(line, "%-%-.*$", "")))
	end
	local bad = string.find(table.concat(code, "\n"), "require%s*%(%s*[\"']")
	if bad then failed += 1; print("FAIL: " .. key .. " requires by string (invalid in Roblox)") else passed += 1 end
end
print(string.format("steal a cryptid compile: %d sources, %d passed, %d failed", #keys, passed, failed))
if failed > 0 then error("steal a cryptid compile check failed", 0) end
