--!strict
-- HudLayout.luau — every rectangle of the phone-first HUD, for BOTH client scripts. PURE.
--
-- Hud.client.luau draws the wallet, the hopper bar, toasts, the hint, the Upgrades button and the upgrade
-- panel; Sky.client.luau draws the band chip, the Stargaze button, the hazard warning and the band title
-- card. Both call compute() with the same inputs, so their pieces can never overlap by drifting apart
-- (+1 Jump mirrored its HUD's constants by hand in two files instead). Dependencies are arguments:
-- Responsive comes in as the first parameter (a bare require("./X") is invalid in Roblox).
--
-- All rectangles are DESIGN px inside the scaling root Frame (which owns the UIScale and is sized
-- 1/scale so it still spans the screen). Layout, top to bottom, following docs/mobile-ui-brief.md:
--   * top centre: wallet, band chip, hopper bar, hazard warning, toast, hint (a stack of fixed rows);
--   * right edge, around 45-70% of the height and always ABOVE the touch controls: Upgrades, Stargaze;
--   * the upgrade panel opens at the right edge; the button column moves to its left edge;
--   * transient cards sit below the stack, left of the column.
-- Nothing tappable is ever in the bottom-left or bottom-right band (Roblox's thumbstick and jump button).
-- Spec: tests/HudLayout.spec.luau (hudcheck's ten viewports, both panel states, every piece at once).

local HudLayout = {}

HudLayout.GAP = 6
HudLayout.STACK_W = 420
HudLayout.ROWS = { wallet = 44, chip = 30, hopper = 26, warning = 30, toast = 28, hint = 28 }
HudLayout.ORDER = { "wallet", "chip", "hopper", "warning", "toast", "hint" }
HudLayout.BTN_W = 150
HudLayout.BTN_H = 40
HudLayout.PANEL_W = 300
HudLayout.ROW_H_DESKTOP = 56
HudLayout.PANEL_PAD = 4
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
function HudLayout.compute(Responsive: any, vx: number, vy: number, touch: boolean, inset: number, panelOpen: boolean): any
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

	-- the upgrade panel (right edge) and its rows
	local btnH = HudLayout.touchSize(HudLayout.BTN_H, scale, touch)
	local rowH = math.max(HudLayout.ROW_H_DESKTOP, btnH)
	local pad = HudLayout.PANEL_PAD
	local contentH = 3 * rowH + 4 * pad
	local panelW = Responsive.sideWidth(HudLayout.PANEL_W, x0, layout)
	local panelH = math.max(40, math.min(contentH, safeBottom - M))
	local panel = rect(rootW - M - panelW, M, panelW, panelH)

	-- the button column: Upgrades above Stargaze
	local btnW = HudLayout.BTN_W
	local colH = 2 * btnH + G
	local colX = if panelOpen then panel.x - G - btnW else rootW - M - btnW
	local colY = math.clamp(rootH * 0.575 - colH / 2, M, math.max(M, safeBottom - colH))
	local upgradeBtn = rect(colX, colY, btnW, btnH)
	local stargazeBtn = rect(colX, colY + btnH + G, btnW, btnH)

	-- the top stack: centred, but always ending left of the column
	local rightLimit = colX - G
	local stackW = math.min(HudLayout.STACK_W, rightLimit - M)
	local stackX = math.clamp((rootW - stackW) / 2, M, math.max(M, rightLimit - stackW))
	local out: any = {
		scale = scale,
		rootW = rootW,
		rootH = rootH,
		compact = layout.compact,
		touch = touch,
		safeBottom = safeBottom,
		rowH = rowH,
		btnH = btnH,
		upgradeBtn = upgradeBtn,
		stargazeBtn = stargazeBtn,
		panel = panel,
	}
	local y = M
	for _, name in HudLayout.ORDER do
		local h = HudLayout.ROWS[name]
		out[name] = rect(stackX, y, stackW, h)
		y += h + G
	end
	local stackBottom = y - G

	-- transient cards: below the stack, left of the column
	local regionW = rightLimit - M
	local cardW = math.min(760, regionW)
	local cardX = M + (regionW - cardW) / 2
	local cardY = math.max(stackBottom + G, rootH * 0.36)
	out.card = rect(cardX, cardY, cardW, 56)
	out.cardSub = rect(cardX, cardY + 56 + 2, cardW, 26)
	out.starCard = rect(cardX, cardY + 56 + 2 + 26 + G, cardW, 56)
	return out
end

-- The panel's three rows, relative to the panel: { y, h, buy = rect } each (BUY on the right of the row).
function HudLayout.panelRows(L: any): { any }
	local pad = HudLayout.PANEL_PAD
	local rows = {}
	-- at least a tap target wide on touch (btnH already reaches 44 screen px), else about a third of the row
	local buyW = math.max(L.btnH, math.min(96, math.max(60, L.panel.w * 0.32)))
	for i = 1, 3 do
		local y = pad + (i - 1) * (L.rowH + pad)
		table.insert(rows, {
			y = y,
			h = L.rowH,
			buy = rect(L.panel.w - pad - buyW, y + (L.rowH - L.btnH) / 2, buyW, L.btnH),
		})
	end
	return rows
end

return HudLayout
