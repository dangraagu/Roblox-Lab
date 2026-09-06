-- TouchTarget.luau — how big a control has to be DRAWN so a thumb can actually hit it.
--
-- Why this exists: Responsive shrinks the whole HUD with a UIScale so it fits a phone, and a
-- UIScale shrinks the buttons along with the text — on exactly the device where the buttons
-- need to be biggest. A toggle drawn 48 px tall comes out at 29 px on an 800x360 screen, well
-- under the 44 px that Roblox's own guidance and both mobile platform guidelines ask for.
--
-- The fix is not to stop scaling: text still has to shrink to fit. It is to size the
-- INTERACTIVE elements in screen space — divide the design size by the scale so the control
-- lands at the same physical size whatever the scale factor, and never let the result come out
-- below the 44 px floor.
--
-- Four client scripts had grown their own copy of `grow` with no floor, which is why their own
-- toggles were still 29 px. One copy lives here so they cannot drift apart again.
--
-- The rules are deliberately boring and pure so they can be unit-tested from the luau CLI.
-- This module requires NOTHING (a bare string require like `require("./X")` resolves in the
-- CLI but is INVALID in Roblox, and this file runs in both).
--
-- Usage from a client script:
--   local TouchTarget = require(ReplicatedStorage:WaitForChild("TouchTarget"))
--   local layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
--   local function tap(px) return TouchTarget.tap(px, layout) end    -- buttons, boxes
--   local function grow(px) return TouchTarget.grow(px, layout) end  -- text caps, label rows
--   closeBtn.Size = UDim2.fromOffset(tap(44), tap(44))
--   titleTsc.MaxTextSize = grow(20)
--
-- Note which one to reach for: `tap` is for something the player presses, and its floor would
-- make a 17 px text cap absurd. Everything that merely has to keep its physical size — text
-- size caps, the height of a label row inside a button that grew — uses `grow`.

local TouchTarget = {}

-- Roblox's guidance and both mobile platform guidelines: 44 screen px in both dimensions.
TouchTarget.MIN_TAP = 44

-- The scale to divide by, or nil for "leave this size exactly as it was drawn".
--
-- controlPad is non-zero exactly when Roblox is drawing its own touch controls, so this whole
-- module is a no-op for a mouse-driven window: a small desktop window keeps the pixel sizes it
-- was authored with, and at 1920x1080 (scale 1, controlPad 0) every formula below degenerates
-- to today's values.
local function touchScale(layout): number?
	if type(layout) ~= "table" then
		return nil
	end
	local pad = layout.controlPad
	if type(pad) ~= "number" or pad <= 0 then
		return nil
	end
	local scale = layout.scale
	if type(scale) ~= "number" or scale <= 0 then
		return nil
	end
	return scale
end

-- Design px that come out at `designPx` SCREEN px once the UIScale has been applied.
-- Rounds up, because half a pixel short of a tap target is still short.
function TouchTarget.grow(designPx: number, layout): number
	if type(designPx) ~= "number" then
		return designPx
	end
	local scale = touchScale(layout)
	if scale == nil then
		return designPx
	end
	return math.ceil(designPx / scale)
end

-- Same, but for something the player taps: never smaller than MIN_TAP screen px. Note the
-- floor is converted into design space too — a bare `math.max(x, 44)` would still land at
-- 26 px on screen, which is the bug this module exists to fix.
function TouchTarget.tap(designPx: number, layout): number
	if type(designPx) ~= "number" then
		return designPx
	end
	local scale = touchScale(layout)
	if scale == nil then
		return designPx
	end
	return math.max(math.ceil(designPx / scale), math.ceil(TouchTarget.MIN_TAP / scale))
end

return TouchTarget
