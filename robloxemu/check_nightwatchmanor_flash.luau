-- Nightwatch Manor — what flashes, how often, and the way to turn it off. Through the REAL server and client.
-- Run both cases (one harness per process):
--   luau check_nightwatchmanor_flash.luau -a storm 2>&1
--   luau check_nightwatchmanor_flash.luau -a calm 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- Review 4 (2026-09-24) measured, through this same client: 20 lightning strikes in 113 s of a night-43 Witching
-- Hour, the closest two 2.67 s apart at dread 0.96, although the config said "at least 5 s" and a spec checked
-- the config (the client ran its countdown at (1 + dread) x real time). The pure rule is Nightfall.boltGap
-- (Nightfall.spec); this checks that the client obeys it, frame by frame:
--   storm: a whole night-43 night stood in the room the patrol reaches least, dread run to the top: the closest
--          two strikes are at least Nightfall.HARD.FlashGapMin apart. A hazard's amber light and its locked
--          marker blink at most HARD.BlinkHzMax times a second. A knock flashes the screen (CONTROL for calm).
--   calm:  Roblox's Reduced Motion setting on (GuiService.ReducedMotionEnabled, set before the client loads): the
--          same night has NO lightning (no flash light, no bolt, no grade boost) while the rain still falls, a
--          knock flashes nothing, and the hazard's light and marker hold steady. Then the setting is switched
--          off in the safehouse and the lightning comes back: the setting is read live, and it is what did it.

local Kit = require("./check_nightwatchmanor_kit")

local CASE = ...
if CASE ~= "storm" and CASE ~= "calm" then
	error("usage: luau check_nightwatchmanor_flash.luau -a storm|calm (got " .. tostring(CASE) .. ")", 0)
end
local NIGHT = 43

local ctx = Kit.boot({
	name = "nwm-flash-" .. CASE,
	profile = { night = NIGHT, stash = 0, best = NIGHT - 1, levels = {} },
	beforeClient = function(c)
		-- hazards often enough to watch their warning blink (in memory only)
		c.Config.Hazards.IntervalMin = 6
		c.Config.Hazards.IntervalMax = 8
		if CASE == "calm" then
			c.h.game:GetService("GuiService").ReducedMotionEnabled = true
		end
	end,
})
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local function mod(name) return h:_require(ctx.RS:FindFirstChild(name)) end
local Nightfall = mod("Nightfall")
local Manor = mod("Manor")
local Rng = mod("Rng")
local bands = Config.Env.Bands
local band = bands[Nightfall.bandIndex(bands, NIGHT)]
truthy(band.lightning ~= nil, "CONTROL: night " .. NIGHT .. "'s band has lightning (" .. band.id .. ")")
local H = Nightfall.HARD
-- the rules themselves, not whatever the module says (so a weakened HARD is caught here too)
local GAP, BLINK = 4, 2
truthy(type(H.FlashGapMin) == "number" and H.FlashGapMin >= GAP, "Nightfall.HARD.FlashGapMin is at least 4 s (" .. tostring(H.FlashGapMin) .. ")")
truthy(type(H.BlinkHzMax) == "number" and H.BlinkHzMax <= BLINK, "Nightfall.HARD.BlinkHzMax is at most 2 (" .. tostring(H.BlinkHzMax) .. ")")
local pg = ctx.me:FindFirstChild("PlayerGui")
local cc = h.Lighting:FindFirstChild("FxColorCorrection")

--================================================================ what we watch, every frame

local W = {
	strikes = {}, -- { t, dread }
	lightOns = {}, markerOns = {}, -- rising edges of the hazard's amber light / its marker, while a hazard is shown
	lightOffFrames = 0, markerOffFrames = 0, shownFrames = 0, lockedFrames = 0,
	screenFlashes = 0, rainFrames = 0, boltFrames = 0, graceBoost = 0,
}
local lastStrike, lastLight, lastMarker, lastScreen = false, nil, nil, false
local ccBase = -math.huge
for _, b in bands do ccBase = math.max(ccBase, b.colorCorrection.Brightness) end
local function hazardItem(): (Instance?, Instance?)
	for _, d in ctx.folder:GetChildren() do
		if string.match(tostring(d.Name), "^Hazard_") then
			local l = d:FindFirstChild("HazardBlink")
			local bb = d:FindFirstChild("HazardWarning")
			if l or bb then return l, bb end
		end
	end
	return nil, nil
end
ctx.onFrame = function()
	local on = false
	for _, d in ctx.folder:GetDescendants() do
		if d.Name == "LightningFlash" and d.Enabled then on = true end
		if d.Name == "Rain" and d.Enabled then W.rainFrames += 1 end
	end
	if ctx.folder:FindFirstChild("Bolt1") then W.boltFrames += 1; on = true end
	-- the grade's boost is +0.12 on a band whose own Brightness is at most ccBase
	if cc and cc.Brightness > ccBase + 0.05 then on = true; W.graceBoost += 1 end
	if on and not lastStrike then
		local s = ctx.lastState() or {}
		table.insert(W.strikes, { t = ctx.time, dread = s.dread or 0, phase = s.phase })
	end
	lastStrike = on
	local light, bb = hazardItem()
	if light and bb then
		W.shownFrames += 1
		local locked = string.find(ctx.warning.Text, "DODGE", 1, true) ~= nil
		if lastLight ~= nil and light.Enabled and not lastLight then table.insert(W.lightOns, ctx.time) end
		if not light.Enabled then W.lightOffFrames += 1 end
		if locked then
			W.lockedFrames += 1
			if lastMarker ~= nil and bb.Enabled and not lastMarker then table.insert(W.markerOns, ctx.time) end
			if not bb.Enabled then W.markerOffFrames += 1 end
		end
		lastLight, lastMarker = light.Enabled, bb.Enabled
	else
		lastLight, lastMarker = nil, nil
	end
	-- the knock's own screen flash (230, 236, 240); the HUD's flashes for CAUGHT / EVICTED are the server game's
	-- one-off notices, not this client's, and are told apart by colour
	local screen = false
	for _, g in (pg and pg:GetChildren() or {}) do
		local f = g.Name == "FxFlash" and g:FindFirstChildOfClass("Frame")
		if f then
			local c = f.BackgroundColor3
			if math.abs(c.R * 255 - 230) < 2 and math.abs(c.G * 255 - 236) < 2 and math.abs(c.B * 255 - 240) < 2 then screen = true end
		end
	end
	if screen and not lastScreen then W.screenFlashes += 1 end
	lastScreen = screen
end

-- The most rising edges inside any one second.
local function mostPerSecond(times: { number }): number
	local most = 0
	for i = 1, #times do
		local n = 0
		for j = i, #times do
			if times[j] - times[i] < 1 - 1e-9 then n += 1 end
		end
		most = math.max(most, n)
	end
	return most
end

--================================================================ a whole night, where the patrol reaches least

ctx.pressDoor()
ctx.seconds(0.3, 0.1)
local manor = ctx.manor()
truthy(manor ~= nil, "night " .. NIGHT .. " began")
local plan = Manor.plan(Rng.new(Manor.seedFor(Config, NIGHT)), Config, NIGHT)
local patrolAt = {}
local cells = {}
for _, f in manor:GetChildren() do
	local id = tonumber(string.match(tostring(f.Name), "^Room(%d+)_"))
	local floor = f:FindFirstChild("Floor")
	if id and floor then
		table.insert(cells, floor.Position)
		for _, pid in plan.patrol do
			if pid == id then table.insert(patrolAt, floor.Position) end
		end
	end
end
local far, fd = nil, -1
for _, c in cells do
	local d = math.huge
	for _, pp in patrolAt do d = math.min(d, (Vector3.new(pp.X, 0, pp.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude) end
	if d > fd then far, fd = c, d end
end
ctx.hrp.CFrame = CFrame.new(far + Vector3.new(0, 4, 0))
-- no physics: a knocked character would slide forever; stand it back on its spot once the knock wears off
local prevFrame = ctx.onFrame
ctx.onFrame = function(dt)
	prevFrame(dt)
	if ctx.hum.PlatformStand ~= true then
		ctx.hrp.AssemblyLinearVelocity = Vector3.zero
		if ctx.manor() ~= nil then ctx.hrp.CFrame = CFrame.new(far + Vector3.new(0, 4, 0)) end
	end
end
local t0 = ctx.time
local topDread = 0
local nightEnd = nil
while ctx.manor() ~= nil and ctx.time - t0 < 400 do
	ctx.frame(1 / 30)
	topDread = math.max(topDread, (ctx.lastState() or {}).dread or 0)
	if topDread >= 0.97 and nightEnd == nil then
		-- leave just before the eviction, so the night ends quietly (EXTRACTED)
		nightEnd = ctx.time
		ctx.pressExit()
	end
end
local nightStrikes = {}
for _, s in W.strikes do
	if s.phase == "NIGHT" then table.insert(nightStrikes, s) end
end
local minGap, minGapDread = math.huge, 0
for i = 2, #nightStrikes do
	local g = nightStrikes[i].t - nightStrikes[i - 1].t
	if g < minGap then minGap, minGapDread = g, nightStrikes[i].dread end
end
print(string.format("  [%s] night %d: %.0f s of night up to dread %.2f; %d lightning strikes, closest two %.2f s apart (at dread %.2f); "
	.. "a hazard shown on %d frames (locked on %d); %d screen flashes; rain on %d frames",
	CASE, NIGHT, ctx.time - t0, topDread, #nightStrikes, minGap, minGapDread, W.shownFrames, W.lockedFrames, W.screenFlashes, W.rainFrames))
truthy(topDread >= 0.9, string.format("CONTROL: the night ran up to high dread (%.2f), where the lightning is fastest", topDread))
truthy(W.shownFrames > 60 and W.lockedFrames > 20, string.format("CONTROL: hazards flew and locked on the player (%d / %d frames)", W.shownFrames, W.lockedFrames))
truthy(W.rainFrames > 100, "CONTROL: the rain fell all night (" .. W.rainFrames .. " frames)")

if CASE == "storm" then
	truthy(#nightStrikes >= 12, string.format("CONTROL: the Witching Hour's lightning struck all night (%d strikes)", #nightStrikes))
	truthy(minGap >= GAP - 1e-6, string.format(
		"no two lightning flashes closer than %.0f s, even at dread %.2f (closest %.2f s; review 4 measured 2.67 s)", GAP, minGapDread, minGap))
	-- A blink rate, measured on 30 Hz frames: consecutive "on" edges of a BLINK-per-second blink are 1/BLINK s apart,
	-- give or take one frame. (Counting edges inside a 1 s window aliases: a true 2 Hz blink sampled at 30 Hz can
	-- show 3 edges in 0.97 s; that is still inside WCAG's "no more than three flashes in any one second".)
	local function closest(times: { number }): number
		local g = math.huge
		for i = 2, #times do g = math.min(g, times[i] - times[i - 1]) end
		return g
	end
	local lightMost, markerMost = mostPerSecond(W.lightOns), mostPerSecond(W.markerOns)
	local lightGap, markerGap = closest(W.lightOns), closest(W.markerOns)
	print(string.format("  hazard warning: amber light on %d times (closest two %.3f s apart, most in one second %d), locked marker on %d times (%.3f s, %d)",
		#W.lightOns, lightGap, lightMost, #W.markerOns, markerGap, markerMost))
	truthy(#W.lightOns >= 4 and #W.markerOns >= 2, "CONTROL: the warning really blinked (" .. #W.lightOns .. " / " .. #W.markerOns .. ")")
	truthy(lightGap >= 1 / BLINK - 1 / 30 - 1e-6, string.format("the hazard's amber light blinks at most %d times a second (on-edges %.3f s apart)", BLINK, lightGap))
	truthy(markerGap >= 1 / BLINK - 1 / 30 - 1e-6, string.format("its locked marker too (%.3f s apart; it blinked 3 times a second)", markerGap))
	truthy(lightMost <= 3 and markerMost <= 3, string.format("and neither breaks WCAG's three flashes in any one second (%d, %d)", lightMost, markerMost))
	truthy(W.screenFlashes >= 1, "CONTROL: a knock flashes the screen when Reduced Motion is off (" .. W.screenFlashes .. ")")
else
	eq(#nightStrikes, 0, "Reduced Motion on: a whole Witching Hour night without one lightning flash")
	eq(W.boltFrames, 0, "...no bolt drawn in any window")
	eq(W.graceBoost, 0, "...and the colour grade never jumped")
	eq(W.screenFlashes, 0, "a knock flashes nothing on the screen")
	eq(W.lightOffFrames, 0, string.format("the hazard's amber light holds steady (off on %d of %d frames)", W.lightOffFrames, W.shownFrames))
	eq(W.markerOffFrames, 0, string.format("and its locked marker too (off on %d of %d locked frames)", W.markerOffFrames, W.lockedFrames))
end

--================================================================ calm: switch the setting off, live

if CASE == "calm" then
	ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
	eq((ctx.lastState() or {}).phase, "DAY", "back in the safehouse")
	ctx.hrp.CFrame = CFrame.new(ctx.house().Floor.Position + Vector3.new(0, 4, -20))
	local before = #W.strikes
	ctx.seconds(30, 1 / 30)
	eq(#W.strikes, before, "still calm in the safehouse: 30 s without a flash")
	h.game:GetService("GuiService").ReducedMotionEnabled = false
	ctx.seconds(30, 1 / 30)
	truthy(#W.strikes > before, string.format("Reduced Motion switched off: the lightning comes back at once (%d strikes in 30 s): the setting is read live",
		#W.strikes - before))
end

eq(ctx.serverCalls, 0, "the client never fired a remote")
ctx.finish("nightwatchmanor flash [" .. CASE .. "]")
