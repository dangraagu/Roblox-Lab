-- Vault Runners — static checks over the built bundle: every source compiles, and the eye-candy
-- client cannot talk to the server or mark server objects.
-- Run (from robloxemu): luau check_vaultrunners_static.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- Why this exists: luau-compile and luau-analyze were not available to the session that built the
-- environment (the shared scratchpad's copies were removed mid-session), and "it compiled" must not
-- rest on the headless checks happening to load every file. `loadstring` is the Luau compiler: a
-- chunk that fails to compile returns nil and the error. The leak rules below are the ones EYECANDY.md
-- promises, checked against the source text rather than trusted from a comment.

local bundle = require("./build/vault-runners")

local passed, failed = 0, 0
local function ok(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end

local keys = {}
for k in bundle do table.insert(keys, k) end
table.sort(keys)
ok(#keys >= 20, "the bundle carries every source (" .. #keys .. " modules)")

-- source lines with comments removed (good enough for these checks: no string here contains "--")
local function code(src: string): { string }
	local out = {}
	for line in string.gmatch(src, "[^\n]+") do
		local cut = string.find(line, "--", 1, true)
		local c = if cut then string.sub(line, 1, cut - 1) else line
		if string.find(c, "%S") then table.insert(out, c) end
	end
	return out
end

for _, k in keys do
	local entry = bundle[k]
	local fn, err = loadstring(entry.source, "@" .. entry.path)
	ok(fn ~= nil, k .. " compiles" .. (if err then (": " .. err) else ""))
	-- Roblox's require takes an Instance. A string require resolves in the CLI and fails in game.
	local bad = nil
	for _, line in code(entry.source) do
		if string.find(line, "require%(%s*[\"']") then bad = line end
	end
	ok(bad == nil, k .. " never requires by string path" .. (if bad then (": " .. bad) else ""))
end

-- the eye candy never speaks to the server, and never writes an attribute on anything
local CLIENT_ONLY = { "client/Vault.client", "shared/VaultArt", "shared/VaultEnv", "shared/EnvBands", "shared/Hazards", "shared/Rest" }
for _, k in CLIENT_ONLY do
	local src = bundle[k] and bundle[k].source or ""
	ok(#src > 0, k .. " is in the bundle")
	ok(string.find(src, "FireServer", 1, true) == nil, k .. " fires no RemoteEvent")
	ok(string.find(src, "InvokeServer", 1, true) == nil, k .. " invokes no RemoteFunction")
	ok(string.find(src, "SetAttribute", 1, true) == nil, k .. " writes no attribute")
	ok(string.find(src, "Instance.new(\"RemoteEvent\")", 1, true) == nil and string.find(src, "Instance.new(\"RemoteFunction\")", 1, true) == nil,
		k .. " adds no remote")
end

-- the pure modules require nothing at all (dependencies are arguments)
for _, k in { "shared/EnvBands", "shared/Hazards", "shared/Rest", "shared/VaultEnv", "shared/VaultArt" } do
	local src = bundle[k] and bundle[k].source or ""
	ok(string.find(src, "require%(") == nil, k .. " requires nothing")
	ok(string.find(src, "game:GetService", 1, true) == nil, k .. " reaches no service")
end

-- on the server's parts the client writes colour and shine only. Its handles on server parts are
-- named `part` (the re-skin and the pad loop); anything else it writes to is its own.
do
	local src = bundle["client/Vault.client"].source
	local writes = {}
	for _, line in code(src) do
		for prop in string.gmatch(line, "[^%w_]part%.(%a+)%s*=[^=]") do
			writes[prop] = (writes[prop] or 0) + 1
		end
	end
	local names = {}
	for prop, n in writes do
		table.insert(names, prop .. " x" .. n)
		ok(prop == "Color" or prop == "Reflectance", "Vault.client writes " .. prop .. " on a server part")
	end
	table.sort(names)
	print("  writes on server parts in Vault.client: " .. table.concat(names, ", "))
	ok(writes.Color ~= nil, "(the re-skin writes Color, so this check is reading the right lines)")
end

print(string.format("vault-runners static: %d passed, %d failed", passed, failed))
