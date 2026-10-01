-- SIGNAL LOST - every game source compiles, and none requires by string.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--       luau check_signallost_compile.luau 2>&1
--
-- The checklist's gate starts with `luau-compile --binary` over every source. luau-compile.exe and luau-analyze.exe
-- no longer exist on this machine (the shared scratchpad that held them was wiped on 2026-09-23/24; luau.exe
-- survived). This keeps the compile half of that gate with the tool that is left, as the sibling games do: every
-- bundled source is compiled with loadstring (nothing runs), and any source that calls require with a string fails,
-- the mistake that once made a server in this repo fail to load in Roblox with every unit test green.
-- A control: a deliberately broken source must fail to compile here, or this file proves nothing.

local bundle = require("./build/signal-lost")
local passed, failed = 0, 0
local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)

local function stringRequire(source: string): boolean
	-- code only: comments here name the trap on purpose ("a bare `require("./X")` is invalid")
	local code = {}
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		table.insert(code, (string.gsub(line, "%-%-.*$", "")))
	end
	return string.find(table.concat(code, "\n"), "require%s*%(%s*[\"']") ~= nil
end

for _, key in keys do
	local entry = bundle[key]
	local fn, err = loadstring(entry.source, "@" .. entry.path)
	if fn then passed += 1 else failed += 1; print("FAIL: " .. key .. " does not compile: " .. tostring(err)) end
	if stringRequire(entry.source) then failed += 1; print("FAIL: " .. key .. " requires by string (invalid in Roblox)") else passed += 1 end
end

-- the controls: the harness must be able to say no
do
	local broken = loadstring("local x = = 1", "@control")
	if broken == nil then passed += 1 else failed += 1; print("FAIL: the control (a syntax error) compiled: this check proves nothing") end
	if stringRequire('local M = require("./Config")') then passed += 1 else failed += 1; print("FAIL: the string-require control was not caught") end
	if not stringRequire('local M = require(game.ReplicatedStorage:WaitForChild("Config")) -- require("./x") in a comment') then passed += 1
	else failed += 1; print("FAIL: an Instance require (with the trap named in a comment) was flagged") end
end

print(string.format("signal-lost compile: %d sources, %d passed, %d failed", #keys, passed, failed))
if failed > 0 then error("signal-lost compile check failed", 0) end
