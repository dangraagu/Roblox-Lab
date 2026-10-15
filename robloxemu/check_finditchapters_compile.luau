-- Find It! Chapters - every game source compiles, none requires by string, none writes an attribute.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--       luau check_finditchapters_compile.luau 2>&1
--
-- The standard's gate is `luau-compile --binary` over every source; luau-compile.exe and luau-analyze.exe are
-- not on this machine (copied from check_escaperoomlab_compile.luau, which says the same). This keeps the compile
-- half: every bundled source compiles with loadstring (nothing runs). It fails a source that requires by string
-- (resolves in the luau CLI, fails in Roblox) and a source that writes an attribute (this game's attribute
-- allowlist is empty: nothing a client can read may carry state, DESIGN.md §12.3).

local bundle = require("./build/find-it-chapters")
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
	local text = table.concat(code, "\n")
	if string.find(text, "require%s*%(%s*[\"']") then
		failed += 1
		print("FAIL: " .. key .. " requires by string (invalid in Roblox)")
	else
		passed += 1
	end
	if string.find(text, ":SetAttribute%s*%(") then
		failed += 1
		print("FAIL: " .. key .. " writes an attribute")
	else
		passed += 1
	end
end
if #keys < 22 then
	failed += 1
	print("FAIL: CONTROL: the bundle holds only " .. #keys .. " sources; rebuild it with wrap.py")
end
print(string.format("find-it-chapters compile: %d sources, %d passed, %d failed", #keys, passed, failed))
if failed > 0 then error("find-it-chapters compile check failed", 0) end
