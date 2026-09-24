-- Nightwatch Manor — a hostile config costs the polish, never the game or the chase.
-- Run all three cases (one harness per process, so one case per run):
--   luau check_nightwatchmanor_fairgate.luau -a light 2>&1
--   luau check_nightwatchmanor_fairgate.luau -a hazards 2>&1
--   luau check_nightwatchmanor_fairgate.luau -a rest 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- The rules are pure-tested (Nightfall.spec: fairness, validateHazards, validateRest). Haunt.client runs each
-- one at load and switches OFF only the part that failed. This boots the REAL server and client three times,
-- each with one rule broken IN MEMORY (the source is never touched), and checks what the player gets:
--   1. an UNFAIR band (the Blood Moon tinting the whole screen red): a loud warning, and the lighting stays
--      exactly the server's tuned preset, the one the chase was balanced under. The windows, the chip and the
--      rest of the eye candy still follow the night;
--   2. a hazard config that would let a knock outrun walking: a warning, and no hazard ever launches;
--   3. a rest config that would allow resting DURING the night (the timed round): a warning, and no rest
--      button anywhere, not even in the safehouse.

local Kit = require("./check_nightwatchmanor_kit")

local CASE = ...
if CASE ~= "light" and CASE ~= "hazards" and CASE ~= "rest" then
	-- no silent default: a gate run without its case must not pass having checked a third of itself
	error("usage: luau check_nightwatchmanor_fairgate.luau -a light|hazards|rest (got " .. tostring(CASE) .. ")", 0)
end

local total = { passed = 0, failed = 0 }
local function rgb255(c: Color3): { number }
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end
local function near(c: Color3, want: { number }, tol: number): boolean
	local r = rgb255(c)
	return math.abs(r[1] - want[1]) <= tol and math.abs(r[2] - want[2]) <= tol and math.abs(r[3] - want[3]) <= tol
end
-- Each case expects exactly ONE warning from the client, naming the rule it broke; it is consumed here so the
-- kit's "no warnings" rule still guards against any OTHER warning.
local function takeWarning(ctx: any, needle: string): boolean
	local found, others = false, {}
	for _, w in ctx.h.warnings do
		if string.find(w, needle, 1, true) then found = true else table.insert(others, w) end
	end
	table.clear(ctx.h.warnings)
	for _, w in others do table.insert(ctx.h.warnings, w) end
	return found
end
local function done(ctx: any, label: string)
	local ok = pcall(ctx.finish, label)
	total.passed += ctx.passed
	total.failed += ctx.failed
	local _ = ok
end

--================================================================ 1. an unfair band: lighting stays the server's

if CASE == "light" then
	local ctx = Kit.boot({
		name = "nwm-fairgate-light",
		profile = { night = 20, stash = 0, best = 19, levels = {} },
		beforeClient = function(c)
			c.Config.Env.Bands[5].colorCorrection.TintColor = { 255, 170, 170 }
		end,
	})
	local eq, truthy = ctx.eq, ctx.truthy
	local bands = ctx.Config.Env.Bands
	eq(bands[5].id, "blood", "CONTROL: band 5 is the Blood Moon, where night 20 is")
	truthy(takeWarning(ctx, "not fair to the chase"), "the client warns that the config is not fair to the chase")
	ctx.seconds(6, 0.1)
	local L = ctx.h.Lighting
	local cc = L:FindFirstChild("FxColorCorrection")
	local atm = L:FindFirstChild("FxAtmosphere")
	local b1 = bands[1]
	truthy(cc and near(cc.TintColor, b1.colorCorrection.TintColor, 1), "the grade stays the server's preset tint ("
		.. (cc and table.concat(rgb255(cc.TintColor), ",") or "?") .. "), not the red one")
	truthy(cc and math.abs(cc.Contrast - b1.colorCorrection.Contrast) < 1e-6, "and its contrast")
	truthy(atm and math.abs(atm.Density - b1.atmosphere.Density) < 1e-6, "the fog density stays the preset's, the one the chase was tuned in")
	truthy(near(L.Ambient, b1.lighting.Ambient, 1), "and the ambient light")
	-- the rest of the eye candy still follows the night
	truthy(string.find(ctx.chip.Text, "Blood Moon", 1, true) ~= nil, "the chip still names the Blood Moon (" .. ctx.chip.Text .. ")")
	local sky = nil
	for _, d in ctx.folder:GetChildren() do
		if d.Name == "WinSky" and not ctx.folder:FindFirstChild("Bolt1") then sky = d end
	end
	truthy(sky ~= nil and near(sky.Color, bands[5].glow.sky, 3), "and the windows still show the Blood Moon's sky")
	done(ctx, "fairgate: unfair lighting")
end

--================================================================ 2. an invalid hazard config: no hazards at all

if CASE == "hazards" then
	local ctx = Kit.boot({
		name = "nwm-fairgate-hazards",
		profile = { night = 12, stash = 0, best = 11, levels = {} },
		beforeClient = function(c)
			local Hz = c.Config.Hazards
			Hz.IntervalMin, Hz.IntervalMax = 1, 1
			Hz.Kinds.wraith.knock = c.Config.Player.WalkSpeed -- a knock as fast as walking: a speed boost
		end,
	})
	local eq, truthy = ctx.eq, ctx.truthy
	truthy(takeWarning(ctx, "hazards are OFF"), "the client warns that hazards are off")
	ctx.pressDoor()
	ctx.seconds(0.3, 0.1)
	truthy(ctx.manor() ~= nil, "CONTROL: the night began")
	local seen = 0
	ctx.onFrame = function()
		for _, d in ctx.folder:GetChildren() do
			if string.match(tostring(d.Name), "^Hazard_") or d.Name == "HazardZone" then seen += 1 end
		end
		if ctx.warning.Visible then seen += 1 end
	end
	ctx.seconds(20, 1 / 30)
	eq(seen, 0, "twenty seconds of night with a 1 s interval: not one hazard, ring or warning")
	ctx.onFrame = nil
	done(ctx, "fairgate: invalid hazards")
end

--================================================================ 3. rest inside the round: no rest at all

if CASE == "rest" then
	local ctx = Kit.boot({
		name = "nwm-fairgate-rest",
		profile = { night = 5, stash = 0, best = 4, levels = {} },
		beforeClient = function(c)
			c.Config.Rest.Phases.NIGHT = true
		end,
	})
	local eq, truthy = ctx.eq, ctx.truthy
	truthy(takeWarning(ctx, "rest is OFF"), "the client warns that rest is off")
	ctx.seconds(1)
	eq(ctx.restBtn.Visible, false, "no rest button in the safehouse either: a config that reaches into the night gets no rest at all")
	ctx.restBtn.Activated:Fire()
	ctx.frames(3)
	truthy(ctx.hum.Sit ~= true, "pressing it anyway sits nobody down (Sit " .. tostring(ctx.hum.Sit) .. ")")
	ctx.seconds(ctx.Config.Rest.IdleSeconds + 2, 0.1)
	truthy(string.find(ctx.chip.Text, "Dozing", 1, true) == nil, "nor does standing still doze you off (" .. ctx.chip.Text .. ")")
	ctx.pressDoor()
	ctx.seconds(ctx.Config.Rest.IdleSeconds + 2, 0.1)
	truthy(string.find(ctx.chip.Text, "Dozing", 1, true) == nil and string.find(ctx.chip.Text, "Resting", 1, true) == nil,
		"and never at night (" .. ctx.chip.Text .. ")")
	done(ctx, "fairgate: rest in the night")
end

print(string.format("nightwatchmanor fairgate [%s]: %d passed, %d failed", CASE, total.passed, total.failed))
if total.failed > 0 then
	error("nightwatchmanor fairgate [" .. CASE .. "] failed", 0)
end
