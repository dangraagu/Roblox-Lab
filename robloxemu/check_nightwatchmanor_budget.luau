-- Nightwatch Manor — the client's budgets, at their WORST, through the REAL server and the REAL client.
-- Run: luau check_nightwatchmanor_budget.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- check_nightwatchmanor_haunt.luau holds every budget through a NORMAL session. This one builds the worst case
-- and holds every budget in Config.Budget on every frame of it:
--   * every upgrade maxed, so the safehouse stands at its cosiest (fire, embers, fire light, every prop);
--   * IN MEMORY ONLY, before the client loads: every band flies all four hazard kinds back to back (an interval
--     of 1 s, so one is always in flight) and throws lightning every 0.3-0.5 s, bolt drawn;
--   * IN MEMORY ONLY: the Thunderstorm asks for 90 drops/s of rain and 30 dust motes/s, past the rate budget,
--     so the client's own cap has to hold it (the shipped bands never get near it);
--   * for every band, the night inside it whose manor has the most Portrait Halls (the most client parts),
--     reached by real extractions; the safehouse by day, then every room of the manor at night, the player
--     teleported through each one the Nightwatcher is not near.
-- Per frame: parts, emitters and their summed rate, lights, windows, portraits and hazards parented at once.
-- Also per frame: no Neon part, light or particle the client parents is within SignatureDistanceMin of the
-- Nightwatcher's own light colours, nor (review 4) of the Servants' Exit's green light (Config's fairness rule
-- checks the config's colours; this checks what was actually built, including the hard-coded hazard models), and
-- every client part stays inert. And (review 4) the config asks for lightning every 0.3-0.5 s: the client must
-- still never put two flashes closer than Nightfall.HARD.FlashGapMin.
-- The per-band table this prints is EYECANDY.md §7.

local Kit = require("./check_nightwatchmanor_kit")

local maxed = {}
local ctx = Kit.boot({
	name = "nwm-budget",
	profile = { night = 1, stash = 0, best = 0, levels = { lanterns = 5, wardstones = 5, beartraps = 5, relicvault = 5, alarmbell = 3, lockbox = 3, floodlights = 4 } },
	beforeClient = function(c)
		local Hz = c.Config.Hazards
		Hz.IntervalMin, Hz.IntervalMax = 1, 1
		local all = {}
		for k in Hz.Kinds do table.insert(all, k) end
		table.sort(all)
		for _, b in c.Config.Env.Bands do
			b.hazards = all
			b.lightning = { everyMin = 0.3, everyMax = 0.5, bolt = true }
		end
		-- a retune that asks for more weather than the budget: the Thunderstorm pours 90 drops/s and 30 motes/s.
		-- The shipped bands never exceed the rate budget (EnvConfig.spec), so without this the client's cap
		-- (EnvBands.capRates in HauntArt:updateWeather) would never be exercised by any gate.
		for _, b in c.Config.Env.Bands do
			if b.id == "storm" then
				b.outside.rain = 90
				b.inside.dust = 30
			end
		end
		maxed = c.Config.Upgrades.Catalog
	end,
})
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local B = Config.Budget
local bands = Config.Env.Bands
local function mod(name) return h:_require(ctx.RS:FindFirstChild(name)) end
local Nightfall = mod("Nightfall")
local Manor = mod("Manor")
local Rng = mod("Rng")
local size = Config.Manor.RoomSize

-- the profile really is maxed (the catalog decides what "max" is; the profile above must match it)
do
	local st = ctx.lastState() or {}
	local want = 0
	for _, e in maxed do want += e.max end
	eq(st.hubLevel, want, "CONTROL: every upgrade is maxed (hub level " .. tostring(st.hubLevel) .. ")")
	eq(Nightfall.cosyTier(Config.Env.Cosy, st.hubLevel or 0), #Config.Env.Cosy, "CONTROL: so the safehouse is at its cosiest tier")
end

--================================================================ what is parented, every frame

local sig = Config.Env.WatcherSignature
local sigMin = Nightfall.HARD.SignatureDistanceMin
local function dist(c: Color3, s: { number }): number
	local r, g, b = c.R * 255 - s[1], c.G * 255 - s[2], c.B * 255 - s[3]
	return math.sqrt(r * r + g * g + b * b)
end
-- A decoy is a light or glow that could pass for the Nightwatcher's red head light or its pale lamp. Every Neon
-- part, point light and particle the client parents is asserted on every frame, the hard-coded ones included
-- (hazard models, stars, the distant manor's lit windows, the bolt) - with one exception. The three pieces of
-- window glass whose colour GLIDES with the band (sky, moon, corona) are a picture on the wall behind a frame;
-- their steady colours are the band colours Nightfall.fairness already checks, but while a look glides between
-- bands a pale moon fading to a dark one passes near the grey axis, which the lamp's (150, 200, 210) sits 45 from.
-- Those three are reported, not asserted.
local GLIDING_GLASS = { WinSky = true, WinMoon = true, WinCorona = true }
local worstSig, worstSigWhat = math.huge, "?"
local worstGlass, worstGlassWhat = math.huge, "?"
-- review 4: the same rule for the way out. A decoy for the exit is a glow that could pass for its green light (the
-- ghosts glowed (120, 255, 140), 35 from it, in a colour no config rule saw).
-- (the literal is the colour Main.server builds, so a config without the signature is still measured; the CONTROL
-- below fails it, and check_nightwatchmanor_haunt pins the signature to the built exit)
local exitSig = Config.Env.ExitSignature or { { 120, 220, 140 } }
local worstExit, worstExitWhat = math.huge, "?"
local worstExitGlass, worstExitGlassWhat = math.huge, "?"
local function sigCheck(c: Color3, what: string)
	local glass = GLIDING_GLASS[what] == true
	for _, s in sig do
		local d = dist(c, s)
		if glass then
			if d < worstGlass then worstGlass, worstGlassWhat = d, what end
		elseif d < worstSig then
			worstSig, worstSigWhat = d, what
		end
	end
	for _, s in exitSig do
		local d = dist(c, s)
		if glass then
			if d < worstExitGlass then worstExitGlass, worstExitGlassWhat = d, what end
		elseif d < worstExit then
			worstExit, worstExitWhat = d, what
		end
	end
end

local function census()
	local c = { parts = 0, emitters = 0, rate = 0, lights = 0, windows = 0, portraits = 0, hazards = 0, solid = 0 }
	local kinds = {}
	for _, d in ctx.folder:GetDescendants() do
		if d:IsA("BasePart") then
			c.parts += 1
			if d.Name == "WinSky" then c.windows += 1 end
			if d.Name == "PortraitCanvas" then c.portraits += 1 end
			local k = string.match(tostring(d.Name), "^Hazard_(%a+)_")
			if k then kinds[k] = true end
			if not (d.Anchored and d.CanCollide == false and d.CanQuery == false and d.CanTouch == false) then c.solid += 1 end
			if d.Material == Enum.Material.Neon and d.Transparency < 1 then sigCheck(d.Color, d.Name) end
		elseif d.ClassName == "ParticleEmitter" and d.Enabled then
			c.emitters += 1
			c.rate += d.Rate or 0
			for _, kp in d.Color.Keypoints do sigCheck(kp.Value, d.Name .. " particles") end
		elseif d.ClassName == "PointLight" and d.Enabled then
			c.lights += 1
			sigCheck(d.Color, d.Name)
		end
	end
	for _ in kinds do c.hazards += 1 end
	return c
end

local KEYS = { "parts", "emitters", "rate", "lights", "windows", "portraits", "hazards" }
local LIMIT = { parts = B.MaxParts, emitters = B.MaxEmitters, rate = B.MaxEmitterRate, lights = B.MaxLights,
	windows = B.MaxWindowsShown, portraits = B.MaxPortraitsShown, hazards = B.MaxHazards }
local rows = {} -- rows[key] = peaks
local order = {}
local over, overExample, solid, frames = 0, nil, 0, 0
local current = "boot"
local peak = {}
local peakAt = {}
local flashesSeen, hazardFrames, nightFrames, boltDark, boltDarkWhere = 0, 0, 0, 0, nil
local strikeTimes, boltWas = {}, false
ctx.onFrame = function()
	frames += 1
	local c = census()
	local row = rows[current]
	if row == nil then
		row = {}
		for _, k in KEYS do row[k] = 0 end
		rows[current] = row
		table.insert(order, current)
	end
	for _, k in KEYS do
		row[k] = math.max(row[k], c[k])
		if c[k] > (peak[k] or -1) then peak[k], peakAt[k] = c[k], current end
		if c[k] > LIMIT[k] + 1e-6 then
			over += 1
			overExample = overExample or string.format("%s: %s %s > %s", current, k, tostring(c[k]), tostring(LIMIT[k]))
		end
	end
	solid += c.solid
	local bolt = ctx.folder:FindFirstChild("Bolt1") ~= nil
	if bolt and not boltWas then table.insert(strikeTimes, ctx.time) end
	boltWas = bolt
	if bolt then
		flashesSeen += 1
		-- a bolt in the glass always comes with its light: the room is lit FROM the window
		local host = ctx.folder:FindFirstChild("FlashHost")
		local l = host and host:FindFirstChild("LightningFlash")
		if not (l and l.Enabled) then
			boltDark += 1
			boltDarkWhere = boltDarkWhere or current
		end
	end
	if c.hazards > 0 then hazardFrames += 1 end
	if string.find(current, "NIGHT", 1, true) then nightFrames += 1 end
end

--================================================================ the tour

local function watcherPos(): Vector3?
	local m = ctx.manor()
	local w = m and m:FindFirstChild("Nightwatcher")
	return w and w:GetPivot().Position
end
local function safeFrom(p: Vector3): boolean
	local w = watcherPos()
	return w == nil or (Vector3.new(w.X, 0, w.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude > size * 1.6
end

-- the night in [from, to] whose manor has the most Portrait Halls (ties: the most rooms)
local function richestNight(from: number, to: number): number
	local best, bestScore = from, -1
	for n = from, to do
		local plan = Manor.plan(Rng.new(Manor.seedFor(Config, n)), Config, n)
		local halls = 0
		for _, r in plan.rooms do
			if r.kind == "hall" then halls += 1 end
		end
		local score = halls * 100 + #plan.rooms
		if score > bestScore then best, bestScore = n, score end
	end
	return best
end

local toured = {}
for i, b in bands do
	local nextFrom = if bands[i + 1] then bands[i + 1].from - 1 else b.from + 10
	local target = richestNight(math.max(b.from, 1), nextFrom)
	-- reach it by real extractions (each one is a real night on the real server)
	current = "travel"
	local guard = 0
	while ((ctx.lastState() or {}).night or 1) < target and guard < 80 do
		ctx.surviveNights(1, 0.1)
		guard += 1
	end
	local night = (ctx.lastState() or {}).night
	eq(night, target, b.id .. ": reached the richest night of the band by extraction (night " .. tostring(night) .. ")")

	-- the safehouse by day: 4 s of lightning, rain, the fire
	current = string.format("%-9s DAY   n%-3d", b.id, night)
	ctx.hrp.CFrame = CFrame.new(ctx.house().Floor.Position + Vector3.new(0, 4, -20))
	ctx.seconds(4, 1 / 30)

	-- the manor by night: every room the Nightwatcher is not near, 20 frames each
	ctx.pressDoor()
	current = string.format("%-9s NIGHT n%-3d", b.id, night)
	ctx.seconds(0.3, 1 / 30)
	local m = ctx.manor()
	local rooms, visited = 0, 0
	if m then
		for _, f in m:GetChildren() do
			local floor = string.match(tostring(f.Name), "^Room%d+_") and f:FindFirstChild("Floor")
			if floor and ctx.manor() ~= nil then
				rooms += 1
				if safeFrom(floor.Position) then
					ctx.hrp.CFrame = CFrame.new(floor.Position + Vector3.new(0, 4, 0))
					ctx.seconds(20 / 30, 1 / 30)
					visited += 1
				end
			end
		end
	end
	toured[b.id] = { night = night, rooms = rooms, visited = visited }
	truthy(visited >= 3, string.format("%s: toured night %s's manor (%d of %d rooms)", b.id, tostring(night), visited, rooms))
	if ctx.manor() ~= nil then
		ctx.pressExit()
	end
	current = "travel"
	ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
end

--================================================================ verdicts

print("  worst case per band (peaks; windows / portraits / hazards are what is parented at once):")
print("  where                    parts  emitters  particles/s  lights  windows  portraits  hazards")
for _, key in order do
	if key ~= "travel" and key ~= "boot" then
		local r = rows[key]
		print(string.format("  %s  %5d  %8d  %11.0f  %6d  %7d  %9d  %7d", key, r.parts, r.emitters, r.rate, r.lights, r.windows, r.portraits, r.hazards))
	end
end
print("  budget (Config.Budget)      " .. string.format("%5d  %8d  %11d  %6d  %7d  %9d  %7d",
	B.MaxParts, B.MaxEmitters, B.MaxEmitterRate, B.MaxLights, B.MaxWindowsShown, B.MaxPortraitsShown, B.MaxHazards))
local tourLine = {}
for _, b in bands do
	local t = toured[b.id]
	if t then table.insert(tourLine, string.format("%s n%d %d/%d", b.id, t.night, t.visited, t.rooms)) end
end
print("  toured (band, night, rooms visited/built): " .. table.concat(tourLine, ", "))
print(string.format("  overall peaks: %d parts (%s), %d emitters, %.0f particles/s, %d lights, %d windows, %d portraits, %d hazards",
	peak.parts, tostring(peakAt.parts), peak.emitters, peak.rate, peak.lights, peak.windows, peak.portraits, peak.hazards))
print(string.format("  %d frames (%d on a manor tour); lightning bolt drawn on %d of them; a hazard in flight on %d", frames, nightFrames, flashesSeen, hazardFrames))
print(string.format("  closest any asserted glow came to the Nightwatcher's lights: %.1f (%s); the rule is >= %d", worstSig, worstSigWhat, sigMin))
print(string.format("  gliding window glass (sky, moon, corona; reported, not a rule): closest %.1f (%s)", worstGlass, worstGlassWhat))
print(string.format("  closest any asserted glow came to the Servants' Exit's green: %.1f (%s); gliding glass %.1f (%s)",
	worstExit, worstExitWhat, worstExitGlass, worstExitGlassWhat))
local minStrikeGap = math.huge
for i = 2, #strikeTimes do minStrikeGap = math.min(minStrikeGap, strikeTimes[i] - strikeTimes[i - 1]) end
print(string.format("  lightning asked for every 0.3-0.5 s: %d strikes with a bolt, the closest two %.2f s apart", #strikeTimes, minStrikeGap))

eq(over, 0, "every frame of the worst case stayed inside Config.Budget (" .. tostring(overExample) .. ")")
truthy(flashesSeen > 20, "CONTROL: the stress really did throw lightning (" .. flashesSeen .. " frames with a bolt)")
eq(boltDark, 0, "every frame with a bolt in the glass has the window's flash light on, night after night (first dark bolt: "
	.. tostring(boltDarkWhere) .. ")")
truthy(hazardFrames > nightFrames / 2, string.format("CONTROL: on the manor tours a hazard was in flight on most frames (%d of %d)", hazardFrames, nightFrames))
do
	local stormNight = nil
	for key, r in rows do
		if string.find(key, "storm", 1, true) and string.find(key, "NIGHT", 1, true) then stormNight = r end
	end
	truthy(stormNight ~= nil and stormNight.rate >= B.MaxEmitterRate - 1, string.format(
		"CONTROL: the flooded Thunderstorm pushed the weather to the rate cap (%.1f of %d/s): the cap is what held it",
		stormNight and stormNight.rate or -1, B.MaxEmitterRate))
end
truthy(peak.portraits >= 2, "CONTROL: the tour stood among portraits (" .. tostring(peak.portraits) .. ")")
truthy(peak.windows >= 4, "CONTROL: and among windows (" .. tostring(peak.windows) .. ")")
truthy(peak.lights >= 2, "CONTROL: and saw two lights at once (" .. tostring(peak.lights) .. ")")
truthy(worstSig >= sigMin, string.format("no glow the client built came within %d of the Nightwatcher's light colours (closest %.0f: %s)", sigMin, worstSig, worstSigWhat))
truthy(Config.Env.ExitSignature ~= nil and #Config.Env.ExitSignature >= 1, "CONTROL: Config.Env.ExitSignature names the exit's light colour")
truthy(worstExit >= sigMin, string.format("no glow the client built came within %d of the Servants' Exit's green (closest %.0f: %s)", sigMin, worstExit, worstExitWhat))
truthy(#strikeTimes >= 10, "CONTROL: the lightning struck again and again (" .. #strikeTimes .. " strikes)")
-- 4 s is the rule itself (the brief's no-strobe floor), not whatever Nightfall.HARD says, so a weakened floor fails here too
truthy(minStrikeGap >= 4 - 1e-6, string.format(
	"a config asking for lightning every 0.3-0.5 s still never gets two flashes closer than 4 s (closest %.2f)", minStrikeGap))
eq(solid, 0, "every client part stayed anchored and non-colliding, non-queryable, non-touchable on every frame")
eq(ctx.serverCalls, 0, "the client never fired a remote")
ctx.finish("nightwatchmanor budget")
