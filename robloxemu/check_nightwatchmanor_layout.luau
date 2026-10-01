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
--   3. the rest button is a real tap target on touch (44 px) and not under Roblox's own touch controls;
--   4. (second review, 2026-09-30) the band chip and the hazard warning can be READ: their longest texts fit their
--      boxes at 11 screen px or more. On a 568x320 phone the chip was 94 px wide beside the Rest button, for texts of
--      up to 40 characters ("🌧️ Rain on the Glass · Night 6 · ⛈️ in 4"). Headless runs render no text, so the font
--      size is ESTIMATED from the box: GothamBold widths (capitals 0.7 em, other characters 0.6, spaces 0.28, an
--      emoji 1.25), wrapped at spaces when the label wraps, 1.2 em a line, capped by its UITextSizeConstraint
--      (scaled by the UIScale). The real look is on EYECANDY.md's Studio list.
-- Both modes: DAY (chip + rest button) and NIGHT (chip only, and a hazard warning). The HUD's ten viewports, plus
-- nine common phones (touch), in landscape and portrait.

local Kit = require("./check_nightwatchmanor_kit")
local HudCheck = require("./emu/hudcheck")

-- night 26: the Blood Moon, the brag band, whose chip is the one players photograph (the Blood Moon moved from night 20 to 26 and the Witching Hour from 40 to 50 on 2026-10-01: Config.Env.Bands)
local ctx = Kit.boot({ name = "nwm-layout", profile = { night = 26, stash = 0, best = 25, levels = {} } })
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
ctx.seconds(1)
truthy(ctx.restBtn.Visible, "CONTROL: in the safehouse the rest button is on screen")

local MIN_TAP = 44
local MIN_READ_PX = 11
local Nightfall = h:_require(ctx.RS:FindFirstChild("Nightfall"))
local EXTRA = {
	{ name = "iPhone SE (1st)", w = 568, h = 320, touch = true },
	{ name = "small Android", w = 640, h = 360, touch = true },
	{ name = "iPhone 8", w = 667, h = 375, touch = true },
	{ name = "iPhone 8 Plus", w = 736, h = 414, touch = true },
	{ name = "iPhone X", w = 812, h = 375, touch = true },
	{ name = "iPhone 13", w = 844, h = 390, touch = true },
	{ name = "iPhone 11", w = 896, h = 414, touch = true },
	{ name = "iPhone 8, portrait", w = 375, h = 667, touch = true },
	{ name = "iPhone 13, portrait", w = 390, h = 844, touch = true },
}
local VIEWPORTS = {}
for _, v in HudCheck.VIEWPORTS do table.insert(VIEWPORTS, v) end
for _, v in EXTRA do table.insert(VIEWPORTS, v) end

-- the texts each label must be able to show: every night's chip, the two resting chips, the longest warnings
local CHIP_NIGHT = {}
for n = 1, 60 do table.insert(CHIP_NIGHT, Nightfall.chipText(ctx.Config.Env.Bands, n)) end
local CHIP_DAY = table.clone(CHIP_NIGHT) -- resting is the safehouse's only
table.insert(CHIP_DAY, "☕ Resting by the fire · the manor waits")
table.insert(CHIP_DAY, "💤 Dozing by the fire · the manor waits")
local WARN_TEXTS = {}
for _, name in { "BATS", "WILL-O'-WISP", "FLYING CROCKERY", "WRAITH" } do
	table.insert(WARN_TEXTS, "⚠️ DODGE THE RING! " .. name .. " ◀")
	table.insert(WARN_TEXTS, "⚠️ " .. name .. " INCOMING ▲")
end
local function ems(s: string): number
	local w = 0
	for _, cp in utf8.codes(s) do
		if cp == 0xFE0F or cp == 0x200D then
			-- a variation selector or a joiner has no width
		elseif cp >= 0x1F000 or (cp >= 0x2600 and cp <= 0x27BF) or (cp >= 0x2B00 and cp <= 0x2BFF) then
			w += 1.25
		elseif cp == 32 then
			w += 0.28
		elseif cp >= 65 and cp <= 90 then
			w += 0.7
		else
			w += 0.6
		end
	end
	return w
end
-- the largest font (screen px) at which `text` fits a w x h box, wrapped at spaces if `wrap`; 0 if none from 4 px up
local function fitPx(text: string, w: number, hgt: number, maxPx: number, wrap: boolean): number
	local words = string.split(text, " ")
	local px = math.floor(maxPx * 4) / 4
	while px >= 4 do
		local lines, lineW, ok = 1, 0, true
		for _, word in words do
			local ww = ems(word) * px
			local add = if lineW == 0 then ww else lineW + 0.28 * px + ww
			if add <= w then
				lineW = add
			elseif wrap and lineW > 0 and ww <= w then
				lines += 1
				lineW = ww
			else
				ok = false
				break
			end
		end
		if ok and lines * px * 1.2 <= hgt then return px end
		px -= 0.25
	end
	return 0
end
local legible = {} -- rows for the print
local function readable(r: any, label: Instance, texts: { string }, where: string, failures: { string })
	local scale = ctx.root:FindFirstChildOfClass("UIScale").Scale
	local pad = label:FindFirstChildOfClass("UIPadding")
	local padL = pad and pad.PaddingLeft.Offset or 0
	local padR = pad and pad.PaddingRight.Offset or 0
	local innerW = r.sw - (padL + padR) * scale
	local cons = label:FindFirstChildOfClass("UITextSizeConstraint")
	local maxPx = if cons then cons.MaxTextSize * scale else 200
	local worst, worstText = math.huge, ""
	for _, t in texts do
		local px = fitPx(t, innerW, r.sh, maxPx, label.TextWrapped == true)
		if px < worst then worst, worstText = px, t end
	end
	table.insert(legible, string.format("   %-34s %-12s %4.0fx%-3.0f px  smallest text %.1f px", where, label.Name, r.sw, r.sh, worst))
	if worst < MIN_READ_PX then
		table.insert(failures, string.format("[%s] %s is %.0fx%.0f screen px: \"%s\" fits only at %.1f px (under %d)",
			where, label.Name, r.sw, r.sh, worstText, worst, MIN_READ_PX))
	end
end
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
	ctx.cardSub.Text = "night 26 is waiting"
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
		if r.name == "BandChip" then readable(r, ctx.chip, if mode == "DAY" then CHIP_DAY else CHIP_NIGHT, where, failures) end
		if r.name == "HazardWarning" and mode == "NIGHT" then readable(r, ctx.warning, WARN_TEXTS, where, failures) end
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
	for _, v in VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.1)
		ctx.frames(2)
		local n, m = measure(mode, v, failures)
		print(string.format("   %-5s %-28s %4dx%-4d %s  %d of ours vs %d of the HUD's", mode, v.name, v.w, v.h, v.touch and "touch" or "mouse", n, m))
	end
end
for _, row in legible do print(row) end
for _, f in failures do print("  " .. f) end
eq(#failures, 0, "the haunt's UI fits around the HUD on every viewport, day and night, and its chip and warning can be read")
ctx.finish("nightwatchmanor layout")
