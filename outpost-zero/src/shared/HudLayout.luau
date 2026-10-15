--!strict
-- HudLayout.luau — every rectangle of the phone-first HUD, for BOTH client scripts. PURE.
--
-- Hud.client.luau draws the credits row, the balance bar, the Orders chip, the ★ line, toasts, the hint and the
-- ★ Show me button; Sky.client.luau draws the band / population chip, the ☕ Break button, the hazard warning and
-- the title card. Both call compute() with the same inputs, so their pieces can never overlap by drifting apart
-- (meteor-drop-tycoon's pattern). Dependencies are arguments: Responsive comes in as the first parameter.
--
-- All rectangles are DESIGN px inside the scaling root Frame (which owns the UIScale and is sized 1/scale so it
-- still spans the screen). Following docs/mobile-ui-brief.md and DESIGN 15:
--   * top centre: credits, population chip, balance bar, Orders, ★ line, hazard warning, toast, hint;
--   * right edge, around 45-70% of the height and always ABOVE the touch controls: ☕ Break, ★ Show me;
--   * the transient title card sits below the stack, left of the column.
-- Nothing tappable is ever in the bottom-left or bottom-right band (Roblox's thumbstick and jump button). Building
-- happens at the lot, through the prompt Roblox draws itself, so the HUD has no panel to cover the world.
-- Spec: tests/HudLayout.spec.luau (hudcheck's ten viewports, every piece at once).

local HudLayout = {}

HudLayout.GAP = 6
HudLayout.STACK_W = 420
HudLayout.ROWS = { credits = 44, chip = 30, balance = 26, orders = 26, star = 28, warning = 30, toast = 28, hint = 28 }
HudLayout.ORDER = { "credits", "chip", "balance", "orders", "star", "warning", "toast", "hint" }
HudLayout.BTN_W = 150
HudLayout.BTN_H = 40
HudLayout.MIN_TAP = 44

type Rect = { x: number, y: number, w: number, h: number }

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- Design px that reach at least 44 SCREEN px on a touch screen (after the UIScale); unchanged on a mouse.
function HudLayout.touchSize(designPx: number, scale: number, touch: boolean): number
	if not touch then return designPx end
	local wanted = math.max(designPx, HudLayout.MIN_TAP)
	return math.max(designPx, math.ceil((wanted + 0.5) / scale))
end

-- vx, vy: the viewport; inset: the topbar inset the ScreenGui is pushed down by (0 when IgnoreGuiInset).
function HudLayout.compute(Responsive: any, vx: number, vy: number, touch: boolean, inset: number): any
	local x0 = if type(vx) == "number" and vx > 0 then vx else Responsive.REF_X
	local y0 = if type(vy) == "number" and vy > 0 then vy else Responsive.REF_Y
	local vyDraw = math.max(1, y0 - (inset or 0))
	local layout = Responsive.layout(x0, vyDraw, touch, y0)
	local scale = layout.scale
	local M, G = Responsive.MARGIN, HudLayout.GAP
	local rootW, rootH = x0 / scale, vyDraw / scale

	-- the lowest design y anything tappable may reach: above Roblox's touch controls
	local safeBottom = rootH - M
	if layout.controlPad > 0 then
		safeBottom = math.min(safeBottom, (y0 - layout.controlPad - (inset or 0)) / scale - M)
	end

	-- the button column: ☕ Break above ★ Show me
	local btnH = HudLayout.touchSize(HudLayout.BTN_H, scale, touch)
	local btnW = HudLayout.BTN_W
	local colH = 2 * btnH + G
	local colX = rootW - M - btnW
	local colY = math.clamp(rootH * 0.575 - colH / 2, M, math.max(M, safeBottom - colH))
	local out: any = {
		scale = scale,
		rootW = rootW,
		rootH = rootH,
		compact = layout.compact,
		touch = touch,
		safeBottom = safeBottom,
		btnH = btnH,
		breakBtn = rect(colX, colY, btnW, btnH),
		showBtn = rect(colX, colY + btnH + G, btnW, btnH),
	}

	-- the top stack: centred, but always ending left of the column
	local rightLimit = colX - G
	local stackW = math.min(HudLayout.STACK_W, rightLimit - M)
	local stackX = math.clamp((rootW - stackW) / 2, M, math.max(M, rightLimit - stackW))
	local y = M
	for _, name in HudLayout.ORDER do
		local h = HudLayout.ROWS[name]
		out[name] = rect(stackX, y, stackW, h)
		y += h + G
	end
	local stackBottom = y - G

	-- the transient title card: below the stack, left of the column
	local regionW = rightLimit - M
	local cardW = math.min(760, regionW)
	local cardX = M + (regionW - cardW) / 2
	local cardY = math.max(stackBottom + G, rootH * 0.36)
	out.card = rect(cardX, cardY, cardW, 56)
	out.cardSub = rect(cardX, cardY + 56 + 2, cardW, 26)
	return out
end

return HudLayout
