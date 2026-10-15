--!strict
-- HudLayout.luau — every rectangle of the phone-first HUD, for BOTH client scripts. PURE.
--
-- meteor-drop-tycoon's HudLayout, adapted: three column slots instead of two, and a line panel of six station
-- rows that PAGES instead of scrolling. Hud.client.luau draws the wallet, the alert line, toasts, the hint, column
-- slots 1 and 3 (🏭 Line / ♻ Recycle, and their panel and confirm modes) and the line panel; Yard.client.luau
-- draws the band chip, slot 2 (☕ Break) and the hazard warning. Both call compute() with the same inputs, so
-- their pieces can never overlap by drifting apart. Dependencies are arguments: Responsive comes in first.
--
-- Why pages: robloxemu's hudcheck measures a row scrolled out of a ScrollingFrame where it would sit with no
-- scroll (under the jump button), and Roblox gives a scrolled list no thumb-safe guarantee either. A page holds
-- as many rows as fit above the touch controls; the column's ▲ / ▼ slots turn the page.
--
-- All rectangles are DESIGN px inside the scaling root Frame (which owns the UIScale and is sized 1/scale).
--   * top centre: wallet, band chip, alert (a sputter), hazard warning, toast, hint (a stack of fixed rows);
--   * right edge, around 45-70% of the height and always ABOVE the touch controls: three column slots;
--   * the line panel opens at the right edge; the column moves to its left edge;
--   * transient cards sit below the stack, left of the column.
-- Spec: tests/HudLayout.spec.luau (hudcheck's ten viewports, both panel states, every row of every page).

local HudLayout = {}

HudLayout.GAP = 6
HudLayout.STACK_W = 420
HudLayout.ROWS = { wallet = 44, chip = 30, alert = 30, warning = 30, toast = 28, hint = 28 }
HudLayout.ORDER = { "wallet", "chip", "alert", "warning", "toast", "hint" }
HudLayout.BTN_W = 150
HudLayout.BTN_H = 40
HudLayout.PANEL_W = 340
HudLayout.PANEL_PAD = 4
HudLayout.HEADER_H = 28
HudLayout.ROW_BTN_W = 76 -- a row button, design px (at least a tap target wide on touch)
HudLayout.TEXT_MIN = 110 -- a row keeps its buttons beside its text only if the text keeps this much
HudLayout.TALL_TEXT_H = 40 -- a tall row's two text lines, above its buttons
HudLayout.MIN_TAP = 44
HudLayout.STATIONS = 6

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

	-- the line panel (right edge): wide rows (text | buttons) when the panel is wide enough, else tall rows
	-- (text over buttons); as many rows per page as fit above the touch controls
	local btnH = HudLayout.touchSize(HudLayout.BTN_H, scale, touch)
	local pad = HudLayout.PANEL_PAD
	local panelW = Responsive.sideWidth(HudLayout.PANEL_W, x0, layout)
	local rowBtnW = math.max(btnH, HudLayout.ROW_BTN_W)
	local wide = panelW - 2 * pad - 2 * rowBtnW - G - 8 >= HudLayout.TEXT_MIN
	local rowH = if wide then math.max(52, btnH + 2 * pad) else HudLayout.TALL_TEXT_H + btnH + 3 * pad
	local avail = math.max(1, safeBottom - M)
	local perPage = math.clamp(math.floor((avail - HudLayout.HEADER_H - pad) / (rowH + pad)), 1, HudLayout.STATIONS)
	local panelH = HudLayout.HEADER_H + perPage * (rowH + pad) + pad
	local panel = rect(rootW - M - panelW, M, panelW, panelH)

	-- the button column: three slots
	local btnW = HudLayout.BTN_W
	local colH = 3 * btnH + 2 * G
	local colX = if panelOpen then panel.x - G - btnW else rootW - M - btnW
	local colY = math.clamp(rootH * 0.575 - colH / 2, M, math.max(M, safeBottom - colH))

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
		btnH = btnH,
		slot1 = rect(colX, colY, btnW, btnH),
		slot2 = rect(colX, colY + btnH + G, btnW, btnH),
		slot3 = rect(colX, colY + 2 * (btnH + G), btnW, btnH),
		panel = panel,
		pl = { wide = wide, rowH = rowH, rowBtnW = rowBtnW, perPage = perPage,
			pages = math.ceil(HudLayout.STATIONS / perPage), headerH = HudLayout.HEADER_H },
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
	out.bragCard = rect(cardX, cardY + 56 + 2 + 26 + G, cardW, 56)
	return out
end

function HudLayout.panelLayout(L: any): any
	return L.pl
end

-- Row slot `slotIdx` (1..perPage) of the panel, relative to the panel: { y, h, text = rect, buttons = { b1, b2 } }.
-- A row with one button (Build) uses buttons[2]; a locked row uses none.
function HudLayout.panelRow(L: any, PL: any, slotIdx: number): any
	local pad, G = HudLayout.PANEL_PAD, HudLayout.GAP
	local w = L.panel.w
	local y = PL.headerH + pad + (slotIdx - 1) * (PL.rowH + pad)
	local h = PL.rowH
	local btnH = L.btnH
	if PL.wide then
		local bw = PL.rowBtnW
		local by = y + (h - btnH) / 2
		local b2 = rect(w - pad - bw, by, bw, btnH)
		local b1 = rect(b2.x - G - bw, by, bw, btnH)
		local tx = pad + 4
		return { y = y, h = h, text = rect(tx, y, b1.x - G - tx, h), buttons = { b1, b2 } }
	end
	local tx = pad + 4
	local text = rect(tx, y + pad, w - 2 * tx, HudLayout.TALL_TEXT_H)
	local by = y + pad + HudLayout.TALL_TEXT_H + pad
	local bw = (w - 2 * pad - G) / 2
	local b1 = rect(pad, by, bw, btnH)
	local b2 = rect(pad + bw + G, by, bw, btnH)
	return { y = y, h = h, text = text, buttons = { b1, b2 } }
end

function HudLayout.pageOf(PL: any, t: number): number
	return math.ceil(t / PL.perPage)
end

function HudLayout.slotOf(PL: any, t: number): number
	return (t - 1) % PL.perPage + 1
end

return HudLayout
