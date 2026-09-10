-- Nightwatch Manor — does the server actually REFUSE TO BOOT on a config that would make the
-- game unplayable, and does it actually WARN on one that has quietly killed its own tuning knobs?
--
-- Run from this directory, one case per CLI invocation (a Harness is process-wide):
--   py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
--   luau check_boot_guard.luau -a control
--   luau check_boot_guard.luau -a fraction
--   luau check_boot_guard.luau -a walkspeed
--   luau check_boot_guard.luau -a saturated
--
-- Why this file exists. `tests/Watcher.spec.luau` proves `Watcher.speedAudit` and
-- `Watcher.ceilingBinds` return the right answers, but nothing proved the SERVER acts on them.
-- A review changed the guard's condition to `if worst >= walk and false then` and all 592
-- assertions in the repo stayed green, so the guard was decoration. The only thing that can
-- catch that is a boot with a hostile config that has to fail — which is this.
--
-- One case per process because emu/harness.luau asserts a single installed Harness per CLI
-- invocation (its globals are module-wide), and because a server that raised at load has left
-- half a world behind it and must not be run again on top of itself.

local CASE = ... or "control"

local Harness = require("../../robloxemu/emu/harness")
local bundle = require("./build/nightwatch-manor")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

-- The retune is applied to Config's SOURCE TEXT, not to a table after the fact, so what boots is
-- the file somebody would really have edited. An exact-match patcher that refuses on a miss:
-- a mutation that silently did not apply is a green run that proves nothing, and that is how a
-- mutation sweep ends up reporting a broken harness as 11/11 killed.
local function retune(from: string, to: string)
	local entry = bundle["shared/Config"]
	assert(entry ~= nil, "the bundle has no shared/Config — re-run wrap.py")
	local before = entry.source
	local after, n = string.gsub(before, from, to, 1)
	assert(n == 1, "retune did not apply: no match for '" .. from .. "' in Config.luau")
	bundle["shared/Config"] = { path = entry.path, source = after }
end

local expect -- a fragment the error/warning has to contain, or nil for "it must boot clean"
if CASE == "control" then
	expect = nil
elseif CASE == "fraction" then
	-- The one case the OLD guard could catch: a ceiling at or above the player. 3.0 * 20 = 60
	-- studs/s against a player who walks at 20 — being seen is being caught, forever.
	retune("MaxSpeedFraction = 0%.65", "MaxSpeedFraction = 3.0")
	expect = "MaxSpeedFraction"
elseif CASE == "walkspeed" then
	-- The state the whole defect started in: nothing in the game knew how fast the player was.
	retune("WalkSpeed = 20", "WalkSpeed = 0")
	expect = "WalkSpeed"
elseif CASE == "saturated" then
	-- The case the old guard could NOT catch, and the shape of every retune anyone will really
	-- make: (8 + 12) * 1.2 = 24 studs/s of raw curve against a ceiling of 13. The clamp holds,
	-- so the game is still playable and the server still boots — but the watcher is pinned at
	-- the ceiling for essentially the whole night and BaseSpeed / SpeedPerDread / HuntSpeedMul
	-- have stopped changing anything. That must not be silent.
	retune("SpeedPerDread = 2%.4", "SpeedPerDread = 12")
	expect = "SpeedPerDread"
else
	error("unknown case '" .. tostring(CASE) .. "' — use control | fraction | walkspeed | saturated", 0)
end

local h = Harness.new({
	bundle = bundle,
	name = "nightwatch-manor-guard",
	viewport = { 1280, 720 },
	touch = false,
})

local ok, err = h:tryRun("server/Main.server")

if CASE == "control" then
	truthy(ok, "CONTROL: the shipped config boots (else every refusal below proves nothing)")
	eq(#h.warnings, 0, "CONTROL: and boots without a single warning")
elseif CASE == "saturated" then
	-- Still playable, so it must still boot...
	truthy(ok, "a curve that saturates the ceiling still BOOTS — the clamp holds the chase together")
	-- ...but it must not be silent. The headless gate asserts zero warnings, so this is caught.
	truthy(#h.warnings > 0, "...and it WARNS, so a retune that killed its own knobs is not silent")
	local said = table.concat(h.warnings, " | ")
	truthy(string.find(said, expect :: string) ~= nil,
		"...naming " .. tostring(expect) .. " (said: " .. said .. ")")
	truthy(string.find(said, "ceiling") ~= nil, "...and saying the ceiling is what is now doing the work")
else
	falsy(ok, "the server REFUSES to boot with " .. CASE .. " retuned into the unplayable range")
	truthy(err ~= nil and string.find(tostring(err), expect :: string) ~= nil,
		"...and the refusal names " .. tostring(expect) .. " (said: " .. tostring(err) .. ")")
	truthy(err ~= nil and string.find(tostring(err), "Nightwatch") ~= nil, "...tagged so it is findable in F9")
	-- A world half-built by a script that then raised is worse than no world: check nothing was
	-- left standing for a player to join into.
	local zones = 0
	for _, c in h.workspace:GetChildren() do
		if string.match(tostring(c.Name), "^Zone_") then zones += 1 end
	end
	eq(zones, 0, "...and no player zone was left standing by the failed boot")
end

print(string.format("boot guard [%s]: %d passed, %d failed", CASE, passed, failed))
if failed > 0 then
	error("boot guard check failed", 0)
end
