-- Lost & Found Depot - every game source compiles, and none requires by string.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_compile.luau 2>&1
--
-- CLAUDE.md's gate list has `luau-compile --binary` over every source. luau-compile.exe and luau-analyze.exe
-- are no longer on this machine (the shared scratchpad that held them was wiped on 2026-09-23; luau.exe
-- survived), so this keeps the compile half of that gate with the tool that is left, the way
-- check_stealacryptid_compile.luau does: it compiles every bundled source with loadstring (nothing runs),
-- and it fails any source that calls require with a string, the mistake that once made a server in this
-- repo fail to load in Roblox with every unit test green. Tests and checks compile when they run.

local bundle = require("./build/lost-found-depot")
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
if #keys < 20 then
	failed += 1
	print("FAIL: CONTROL: the bundle holds only " .. #keys .. " sources; rebuild it with wrap.py")
end
print(string.format("lost-found-depot compile: %d sources, %d passed, %d failed", #keys, passed, failed))
if failed > 0 then error("lost-found-depot compile check failed", 0) end
