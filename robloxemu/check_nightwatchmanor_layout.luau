-- Nightwatch Manor — the haunt's UI fits around the HUD on every viewport, in the day and at night.
-- Run: luau check_nightwatchmanor_layout.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- check_nightwatch_hud.luau measures the HUD alone (and its overlap rule counts Frames only). Haunt.client
-- adds a band chip, a rest button, a hazard warning and a title card, all TextLabels/TextButtons, laid out
-- around the HUD by mirroring its sizes. This measures them, on the same ten viewports, against every
-- visible element of the HUD (both phone drawers OPEN, the "IT SEES YOU" banner and the toasts forced on,
-- because each can be on screen at the same time as ours):
--   1. nothing of ours hangs off the screen;
--   2. nothing of ours overlaps anything of the HUD's, or anything else of ours;
--   3. the rest button is a real tap target on touch (44 px) and not under Roblox's own touch controls.
-- Both modes: DAY (chip + rest button) and NIGHT (chip only, and a hazard warning).

local Kit = require("./check_nightwatchmanor_kit")
local HudCheck = require("./emu/hudcheck")

local ctx = Kit.boot({ name = "nwm-layout", profile = { night = 20, stash = 0, best = 19, levels = {} } })
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
ctx.seconds(1)
truthy(ctx.restBtn.Visible, "CONTROL: in the safehouse the rest button is on screen")

local MIN_TAP = 44
local function overlaps(a, b): (boolean, number, number)
	local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
	local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
	return ox > 1 and oy > 1, ox, oy
end

local function measure(mode: string, v: any, failures: { string })
	-- force on everything of the HUD's that can be up at the same time as ours
	local hudRoot = ctx.hud:FindFirstChild("Root")
	local forced = {}
	for _, d in hudRoot:GetChildren() do
		if d:IsA("GuiObject") and d.Visible == false and d.ClassName == "TextLabel" then
			d.Visible = true -- the "IT SEES YOU" banner
			table.insert(forced, d)
		end
	end
	local mineForced = {}
	for _, d in { ctx.card, ctx.cardSub, if mode == "NIGHT" then ctx.warning else nil } do
		if d and not d.Visible then
			d.Visible = true
			table.insert(mineForced, d)
		end
	end
	ctx.warning.Text = "⚠️ DODGE THE RING! FLYING CROCKERY ◀"
	ctx.card.Text = "🩸 THE BLOOD MOON RISES"
	ctx.cardSub.Text = "night 20 is waiting"
	h:settleLayouts(ctx.hud, v.w, v.h)
	h:settleLayouts(ctx.gui, v.w, v.h)

	local hudRects, mine = {}, {}
	for _, r in h:guiRects(ctx.hud, v.w, v.h) do
		if r.shown and r.depth == 2 then table.insert(hudRects, r) end
	end
	for _, r in h:guiRects(ctx.gui, v.w, v.h) do
		if r.shown and r.depth == 2 then table.insert(mine, r) end
	end
	local where = v.name .. " / " .. mode
	for _, r in mine do
		if r.sx < -1 or r.sy < -1 or r.sx + r.sw > v.w + 1 or r.sy + r.sh > v.h + 1 then
			table.insert(failures, string.format("[%s] %s is off screen: x %.0f..%.0f y %.0f..%.0f", where, r.name, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh))
		end
		for _, o in hudRects do
			local hit, ox, oy = overlaps(r, o)
			if hit then
				table.insert(failures, string.format("[%s] %s overlaps the HUD's %s (%s) by %.0fx%.0f px", where, r.name, o.name, o.class, ox, oy))
			end
		end
		for _, o in mine do
			if o ~= r and o.name < r.name then
				local hit, ox, oy = overlaps(r, o)
				if hit then
					table.insert(failures, string.format("[%s] %s overlaps %s by %.0fx%.0f px", where, r.name, o.name, ox, oy))
				end
			end
		end
		if r.class == "TextButton" and v.touch then
			if math.min(r.sw, r.sh) < MIN_TAP then
				table.insert(failures, string.format("[%s] %s is %.0fx%.0f px, under the %d px tap target", where, r.name, r.sw, r.sh, MIN_TAP))
			end
			local pad = math.min(150, math.floor(v.h * 0.35))
			local band = v.h - pad
			local inLeft = r.sy + r.sh > band and r.sx < v.w * 0.35
			local inRight = r.sy + r.sh > band and r.sx + r.sw > v.w * 0.75
			if inLeft or inRight then
				table.insert(failures, string.format("[%s] %s sits under Roblox's touch controls", where, r.name))
			end
		end
	end
	for _, d in forced do d.Visible = false end
	for _, d in mineForced do d.Visible = false end
	return #mine, #hudRects
end

local failures = {}
for _, mode in { "DAY", "NIGHT" } do
	if mode == "NIGHT" then
		ctx.pressDoor()
		ctx.seconds(0.5)
		eq((ctx.lastState() or {}).phase, "NIGHT", "CONTROL: the night began")
		truthy(not ctx.restBtn.Visible, "CONTROL: at night the rest button is gone")
	end
	for _, v in HudCheck.VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.1)
		ctx.frames(2)
		local n, m = measure(mode, v, failures)
		print(string.format("   %-5s %-28s %4dx%-4d %s  %d of ours vs %d of the HUD's", mode, v.name, v.w, v.h, v.touch and "touch" or "mouse", n, m))
	end
end
for _, f in failures do print("  " .. f) end
eq(#failures, 0, "the haunt's UI fits around the HUD on every viewport, day and night")
ctx.finish("nightwatchmanor layout")
