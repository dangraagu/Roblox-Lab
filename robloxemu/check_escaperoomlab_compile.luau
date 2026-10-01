-- Escape Room Lab - every game source compiles, and none requires by string.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--       luau check_escaperoomlab_compile.luau 2>&1
--
-- The standard's gate is `luau-compile --binary` over every source. luau-compile.exe and luau-analyze.exe
-- are not on this machine (only luau.exe is), so this keeps the compile half of that gate the way
-- check_lostfounddepot_compile.luau does: it compiles every bundled source with loadstring (nothing runs),
-- and it fails any source that calls require with a string, which resolves in the luau CLI and fails in
-- Roblox. Tests and checks compile when they run.

local bundle = require("./build/escape-room-lab")
local passed, failed = 0, 0
local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)
for _, key in keys do
	local entry = bundle[key]
	local fn, err = loadstring(entry.source, "@" .. entry.path)
	if fn then passed += 1 else failed += 1; print("FAIL: " .. key .. " does not compile: " .. tostring(err)) end
	-- code only: comments here name the trap on purpose
	local code = {}
	for line in string.gmatch(entry.source .. "\n", "([^\n]*)\n") do
		table.insert(code, (string.gsub(line, "%-%-.*$", "")))
	end
	local bad = string.find(table.concat(code, "\n"), "require%s*%(%s*[\"']")
	if bad then failed += 1; print("FAIL: " .. key .. " requires by string (invalid in Roblox)") else passed += 1 end
	-- no attribute writes anywhere in the game (the attribute allowlist is empty, DESIGN.md §12.3)
	if string.find(table.concat(code, "\n"), ":SetAttribute%s*%(") then
		failed += 1
		print("FAIL: " .. key .. " writes an attribute")
	else
		passed += 1
	end
end
if #keys < 20 then
	failed += 1
	print("FAIL: CONTROL: the bundle holds only " .. #keys .. " sources; rebuild it with wrap.py")
end
print(string.format("escape-room-lab compile: %d sources, %d passed, %d failed", #keys, passed, failed))
if failed > 0 then error("escape-room-lab compile check failed", 0) end
