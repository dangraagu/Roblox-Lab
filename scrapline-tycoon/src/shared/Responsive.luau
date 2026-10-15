-- Responsive.luau — one place that decides how big the HUD is allowed to be.
--
-- Why this exists: a player reported that on a phone the HUD "covers the entire screen and
-- it's impossible to move or do anything". They were right. Every panel was sized in fixed
-- pixels (250x470 on the left, 200x300 on the right, 460-wide hint text) which is fine on a
-- 1920x1080 monitor and absurd on an 800x360 phone viewport — the left panel alone was
-- taller than the whole screen, and the bottom-left code box sat exactly on top of the
-- touch thumbstick.
--
-- The rules here are deliberately boring and pure so they can be unit-tested from the luau
-- CLI. This module requires NOTHING (a bare string require like `require("./X")` resolves
-- in the CLI but is INVALID in Roblox, and this file runs in both).
--
-- Usage from a client script:
--   local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
--   local cam = workspace.CurrentCamera
--   local function apply()
--       local v = cam.ViewportSize
--       local l = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
--       uiScale.Scale = l.scale
--       drawerButton.Visible = l.compact
--       leftPanel.Visible = not l.compact or drawerOpen
--       leftPanel.Size = UDim2.new(0, Responsive.sideWidth(250, v.X, l),
--                                  0, Responsive.fitHeight(470, Responsive.usableHeight(v.Y, l), l))
--   end
--   apply()
--   cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply)

local Responsive = {}

-- Never shrink text below this or the HUD becomes unreadable rather than merely cramped.
-- Below this point the answer is to HIDE panels (compact), not to keep scaling.
Responsive.MIN_SCALE = 0.6

-- The design was authored against a 1280x720 window; that is the 1.0 reference.
Responsive.REF_X = 1280
Responsive.REF_Y = 720

-- Breathing room we always keep between a panel and the screen edge.
Responsive.MARGIN = 12

-- Roblox draws its own touch controls on top of us: the movement thumbstick bottom-left and
-- the jump button bottom-right. Anything we put in that band is unclickable, so we reserve it.
Responsive.MAX_CONTROL_PAD = 150

export type Layout = {
	mode: string, -- "phone" | "tablet" | "desktop"
	scale: number, -- feed straight into a UIScale on the ScreenGui
	compact: boolean, -- true = collapse side panels behind a toggle button
	controlPad: number, -- screen px at the bottom owned by Roblox's touch controls
	viewportX: number,
	viewportY: number,
}

local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- Classify the window. Note the thresholds are about AVAILABLE ROOM, not about hardware:
-- a 900x500 desktop window genuinely has a phone's worth of space and should behave like one.
local function classify(vx: number, vy: number): string
	if vx < 900 or vy < 500 then return "phone" end
	if vx < 1300 then return "tablet" end
	return "desktop"
end

-- `touch` is optional. Pass UserInputService.TouchEnabled when you know it; when omitted we
-- assume anything phone/tablet-sized is touch, which is the safe guess (reserving space the
-- controls don't use costs a little room; not reserving it makes buttons untappable).
-- `physicalY` is the TRUE viewport height, used only for `controlPad`. Callers that shorten `vy`
-- by the topbar inset must pass it: the inset comes off the TOP, while Roblox draws its movement
-- thumbstick and jump button at the bottom of the PHYSICAL screen, so shortening `vy` alone
-- silently shrinks the reserved band without the band moving. Omit it and nothing changes.
function Responsive.layout(vx: number, vy: number, touch: boolean?, physicalY: number?): Layout
	-- ViewportSize is (0,0) for a frame or two at startup. Treat unknown as the worst case
	-- rather than dividing by it.
	local x = if type(vx) == "number" and vx > 0 then vx else 0
	local y = if type(vy) == "number" and vy > 0 then vy else 0

	local mode = classify(x, y)

	local raw = math.min(x / Responsive.REF_X, y / Responsive.REF_Y)
	local scale = clamp(raw, Responsive.MIN_SCALE, 1)

	local isTouch: boolean
	if touch == nil then
		isTouch = mode ~= "desktop"
	else
		isTouch = touch
	end

	local padHeight = y
	if type(physicalY) == "number" and physicalY > 0 then
		padHeight = physicalY
	end

	local controlPad = 0
	if isTouch and padHeight > 0 then
		-- Proportional so it never eats an absurd share of a short screen, capped so it never
		-- grows past what the controls actually occupy on a tall one.
		controlPad = math.min(Responsive.MAX_CONTROL_PAD, math.floor(padHeight * 0.35))
	end

	return {
		mode = mode,
		scale = scale,
		compact = mode == "phone",
		controlPad = controlPad,
		viewportX = x,
		viewportY = y,
	}
end

-- Screen px a side panel may occupy vertically, once the touch controls and the top/bottom
-- margins are taken out. This is SCREEN space — compare against `height * layout.scale`.
function Responsive.usableHeight(vy: number, l: Layout): number
	local y = if type(vy) == "number" and vy > 0 then vy else 0
	local usable = y - l.controlPad - 2 * Responsive.MARGIN
	-- Always positive: a degenerate viewport must not produce a zero-or-negative panel.
	if usable < 40 then return math.min(40, math.max(y, 1)) end
	return usable
end

-- Shrink a design-space panel height until it fits `usable` AFTER scaling. Returns the height
-- to set on the frame (design px, i.e. before UIScale). Leaves it alone when it already fits.
function Responsive.fitHeight(designH: number, usable: number, l: Layout): number
	if designH * l.scale <= usable then return designH end
	return math.max(1, math.floor(usable / l.scale))
end

-- Ceiling for a side panel's width, so a left panel plus a right panel can never cover more
-- than half the screen between them. On a phone the real fix is `compact` (hide them behind a
-- button) — this is the belt to that pair of braces.
-- vx <= 0 means "viewport not known yet"; the next frame re-runs this, so keep the design width.
function Responsive.sideWidth(designW: number, vx: number, l: Layout): number
	if type(vx) ~= "number" or vx <= 0 then return designW end
	local budget = (vx * 0.25) / l.scale
	return math.max(1, math.min(designW, math.floor(budget)))
end

return Responsive
