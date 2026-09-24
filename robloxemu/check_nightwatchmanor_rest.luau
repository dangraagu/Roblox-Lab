-- Nightwatch Manor — rest is the safehouse, and only the safehouse. Run: luau check_nightwatchmanor_rest.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- The rules are pure-tested (Rest.spec from the template; Nightfall.spec: rest is never allowed in the
-- NIGHT phase, and a config that allows it is rejected). This drives the real client:
--   1. in the safehouse the Rest button sits you by the fire, softens the view and says so;
--   2. any movement wakes you (nothing that needs movement can happen while resting);
--   3. the button toggles; standing still 45 s dozes (no sit);
--   4. five minutes of rest change NOTHING the server keeps (night, relics, best): nothing earned, nothing lost;
--   5. walking to the door and entering the manor ends rest, and the night gives none back: the button
--      is gone, the chip never says resting, and pressing it does nothing;
--   6. (review 4) resting is resting: night 7 is Rain on the Glass, whose sheet lightning flashes the safehouse
--      windows and room while you stand about, and not once while you sit or doze by the fire.

local Kit = require("./check_nightwatchmanor_kit")

local ctx = Kit.boot({ name = "nwm-rest", profile = { night = 7, stash = 123, best = 6, levels = { lanterns = 2 } } })
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local focus = h.Lighting:FindFirstChild("NightwatchRestFocus")
truthy(focus ~= nil, "the client made its own rest focus effect (the server's DepthOfField is left alone)")

-- lightning strikes, told apart by whether the chip said we were resting (seated or dozing) on that frame
local strikes = { awake = 0, resting = 0, restSeconds = 0 }
do
	local lastOn = false
	local cc = h.Lighting:FindFirstChild("FxColorCorrection")
	local base = cc and cc.Brightness or 0
	ctx.onFrame = function(dt)
		local on = false
		for _, d in ctx.folder:GetDescendants() do
			if d.Name == "LightningFlash" and d.Enabled then on = true end
		end
		local resting = string.find(ctx.chip.Text, "Resting", 1, true) ~= nil or string.find(ctx.chip.Text, "Dozing", 1, true) ~= nil
		-- the grade's flash boost is a strike too, even with no window to light
		if cc and cc.Brightness > base + 0.06 then on = true end
		if on and not lastOn then
			if resting then strikes.resting += 1 else strikes.awake += 1 end
		end
		if resting then strikes.restSeconds += dt end
		lastOn = on
	end
end

ctx.seconds(30)
truthy(strikes.awake >= 1, string.format("CONTROL: standing about in the safehouse on night 7 (Rain on the Glass), the lightning does flash (%d strikes in 30 s)", strikes.awake))
truthy(ctx.restBtn.Visible, "in the safehouse the Rest button is offered")
local before = ctx.lastState()

--================================================================ 1-3

ctx.restBtn.Activated:Fire()
ctx.frames(2)
eq(ctx.hum.Sit, true, "Rest sits you down")
truthy(focus and focus.Enabled, "and softens the view")
truthy(string.find(ctx.chip.Text, "Resting by the fire", 1, true) ~= nil, "the chip says so (" .. ctx.chip.Text .. ")")
eq(ctx.restBtn.Text, "▶ Up", "the button offers to get up")

-- (the template's WakeGraceSeconds: the first 0.4 s of a rest ignore movement, so sitting down cannot wake you)
ctx.seconds(1)
ctx.hum.MoveDirection = Vector3.new(1, 0, 0)
ctx.frames(2)
ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
eq(ctx.hum.Sit, false, "moving wakes you")
truthy(focus and not focus.Enabled, "and the view sharpens")
truthy(string.find(ctx.chip.Text, "Resting", 1, true) == nil, "the chip is the band again (" .. ctx.chip.Text .. ")")

ctx.seconds(1)
ctx.restBtn.Activated:Fire()
ctx.frames(2)
eq(ctx.hum.Sit, true, "rest again")
ctx.restBtn.Activated:Fire()
ctx.frames(2)
eq(ctx.hum.Sit, false, "the button toggles it off")

ctx.seconds(ctx.Config.Rest.IdleSeconds + 1, 0.1)
truthy(string.find(ctx.chip.Text, "Dozing", 1, true) ~= nil, "standing still " .. ctx.Config.Rest.IdleSeconds .. " s dozes by the fire (" .. ctx.chip.Text .. ")")
eq(ctx.hum.Sit, false, "without sitting you down")

-- dozing is rest too: the button reads "▶ Up", and pressing it wakes you instead of sitting you down
eq(ctx.restBtn.Text, "▶ Up", "while dozing the button offers to get up")
ctx.restBtn.Activated:Fire()
ctx.frames(2)
truthy(string.find(ctx.chip.Text, "Dozing", 1, true) == nil, "pressing it wakes you from the doze (" .. ctx.chip.Text .. ")")
eq(ctx.hum.Sit, false, "...still standing")

--================================================================ 4. nothing earned, nothing lost

ctx.restBtn.Activated:Fire()
ctx.frames(2)
eq(ctx.hum.Sit, true, "Rest again: sat by the fire for the long rest")
ctx.seconds(300, 0.1)
-- anything the server keeps would have been pushed; nothing was, and what it holds is what it held
local after = ctx.lastState()
eq(after and after.night, before and before.night, "five minutes of rest: the same night")
eq(after and after.stash, before and before.stash, "the same relics")
eq(after and after.best, before and before.best, "the same best night")
eq(after and after.phase, "DAY", "and still the day: rest starts nothing and stops nothing")
-- and what the server SAVED over those five minutes (it autosaves every AutosaveSeconds) is the profile it loaded
do
	local rec = ctx.store:GetAsync("u_" .. ctx.ME)
	local d = rec and rec.data
	truthy(rec and rec.lock ~= nil, "CONTROL: the server has saved this profile during the rest (it holds the lock)")
	eq(d and d.night, 7, "the saved night is the one it loaded")
	eq(d and d.stash, 123, "the saved relics too")
	eq(d and d.best, 6, "and the saved best night")
	eq(d and d.levels and d.levels.lanterns, 2, "and the saved upgrades")
end

-- 6. five minutes by the fire in a lightning band, and the doze before it: not one flash
print(string.format("  lightning in the safehouse: %d strikes while up and about, %d in %.0f s of rest", strikes.awake, strikes.resting, strikes.restSeconds))
truthy(strikes.restSeconds >= 300, string.format("CONTROL: the player rested (seated or dozing) for over five minutes (%.0f s)", strikes.restSeconds))
eq(strikes.resting, 0, "resting by the fire, not one lightning flash: the band's rain goes on, the flashes do not")

--================================================================ 5. into the manor: rest is over

eq(ctx.hum.Sit, true, "CONTROL: still resting at the door")
ctx.pressDoor()
ctx.frames(3)
eq((ctx.lastState() or {}).phase, "NIGHT", "the night began")
eq(ctx.hum.Sit, false, "entering the manor ends rest")
truthy(focus and not focus.Enabled, "and its soft focus: the chase is played in the server's own view")
eq(ctx.restBtn.Visible, false, "no Rest button inside the manor")
ctx.restBtn.Activated:Fire()
ctx.frames(3)
eq(ctx.hum.Sit, false, "pressing it anyway does nothing")
local said = false
for _ = 1, 30 do
	ctx.frame(1 / 30)
	if string.find(ctx.chip.Text, "Resting", 1, true) or string.find(ctx.chip.Text, "Dozing", 1, true) then said = true end
end
eq(said, false, "the chip never says resting at night")
-- standing still in the manor for longer than IdleSeconds dozes nobody off either
ctx.seconds(ctx.Config.Rest.IdleSeconds + 2, 0.1)
truthy(ctx.manor() == nil or (string.find(ctx.chip.Text, "Dozing", 1, true) == nil), "no idle rest inside the manor (" .. ctx.chip.Text .. ")")

eq(ctx.serverCalls, 0, "the client never fired a remote")
ctx.finish("nightwatchmanor rest")
