-- Grow a Crystal — the answer to a code must be readable on a phone.
-- Run: luau check_growacrystal_redeem.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The code drawer's Redeem button also shows the server's answer ("✅ Redeemed!", "Already used",
-- "Invalid code") for 2 s. On a phone the drawer is one row (box + button) so the button stays out of the
-- thumbstick's band on a 640x300 screen, and the button is only a thumb wide there: 45 x 44 screen px, so a
-- TextScaled "Invalid code" came out at about 6 px (adversarial review 2026-09-24, finding 2). Codes are
-- how a player gets past the first chamber at all (EYECANDY.md §2), so the answer matters.
--
-- Measured here, through the real server's Redeem function, at the phone viewports and two mouse windows:
--   * the answer is on screen, not under Roblox's touch controls, in text at least MIN_TEXT screen px tall
--     (estimated like the review: TextScaled fits one line at ~0.6 em per glyph, capped by the element's
--     height and by any UITextSizeConstraint times its UIScale, with the parent's UIPadding taken off);
--   * while it shows, nothing tappable in the drawer is under a 44-px tap target, and nothing tappable is
--     covered by it (a covered button still takes a tap nobody can see);
--   * after 2 s the row is back: the box (still holding a mistyped code, so it can be corrected) and a
--     44-px "Redeem" button; on desktop a second answer 1 s after the first keeps its full 2 s;
--   * the empty box's hint is readable too (in portrait the one-row box is ~49 screen px wide).
-- For scale: the narrow button gave 6.3 px; the stacked drawer before the thumbstick fix gave about 20 px
-- on a landscape phone and 13 px in portrait, where the drawer is narrower. 12 px is the floor.

local Harness = require("./emu/harness")

local MIN_TEXT = 12
local MIN_TAP = 44
local THUMBSTICK_FRACTION, JUMP_FRACTION, MAX_CONTROL_PAD = 0.35, 0.25, 150 -- emu/hudcheck.luau's values

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 640, 300 },
	touch = true,
})
assert(h:tryRun("server/Main.server"))
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Coder", 3131)
h:advance(1)
assert(h:tryRun("client/Hud.client"))
h:advance(0.1)

local gui = plr.PlayerGui.CrystalHud
local root = gui.Root
local codeBox = nil
for _, d in gui:GetDescendants() do
	if d.ClassName == "TextBox" then codeBox = d end
end
assert(codeBox ~= nil, "the HUD has a code box")
local codeFrame = codeBox.Parent
local codeBtn = nil
for _, d in codeFrame:GetChildren() do
	if d.ClassName == "TextButton" then codeBtn = d end
end
assert(codeBtn ~= nil and codeBtn.Text == "Redeem", "the code drawer has a Redeem button")

local function openCodeDrawer()
	local toggles = root:FindFirstChild("Toggles")
	if toggles == nil or not toggles.Visible then return end
	for _, b in toggles:GetChildren() do
		if b.ClassName == "TextButton" and string.find(b.Text, "Code", 1, true) then
			if b.BackgroundColor3 ~= Color3.fromRGB(70, 150, 90) then b.Activated:Fire() end
		end
	end
	h:advance(0.1)
end

local function textPx(r, text: string): number
	-- guiRects resolves a child against its parent's whole box; Roblox takes the parent's UIPadding off
	-- first, and that shrinks whatever part of the size is Scale. Put it back, so the estimate is not flattered.
	local sw, sh = r.sw, r.sh
	local pad = r.obj.Parent and r.obj.Parent:FindFirstChildOfClass("UIPadding")
	if pad then
		sw -= r.obj.Size.X.Scale * (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) * r.scale
		sh -= r.obj.Size.Y.Scale * (pad.PaddingTop.Offset + pad.PaddingBottom.Offset) * r.scale
	end
	local px = math.min(sh, sw / (0.6 * utf8.len(text)))
	local cc = r.obj:FindFirstChildOfClass("UITextSizeConstraint")
	if cc then px = math.min(px, cc.MaxTextSize * r.scale) end
	return px
end

local report = {}
local function redeem(v, input: string, want: string)
	codeBox.Text = input
	codeBtn.Activated:Fire()
	h:advance(0.1)
	local where = string.format("%s %dx%d, '%s'", v.name, v.w, v.h, want)
	local controlPad = if v.touch then math.min(MAX_CONTROL_PAD, math.floor(v.h * 0.35)) else 0
	local bandY = v.h - controlPad
	local best, bestPx = nil, -1
	local smallTap = nil
	for _, r in h:guiRects(gui, v.w, v.h) do
		if r.shown and r.obj.Text == want then
			local px = textPx(r, want)
			if px > bestPx then best, bestPx = r, px end
		end
		if r.shown and r.obj:IsDescendantOf(codeFrame) and (r.class == "TextButton" or r.class == "TextBox") then
			if v.touch and math.min(r.sw, r.sh) < MIN_TAP then smallTap = smallTap or string.format("%s %.0fx%.0f", r.class, r.sw, r.sh) end
		end
	end
	truthy(best ~= nil, where .. ": the answer is on screen")
	if best then
		table.insert(report, string.format("  %-30s %-13s in a %5.1f x %4.1f px %-10s -> %4.1f px text", v.name .. " " .. v.w .. "x" .. v.h,
			want, best.sw, best.sh, best.class, bestPx))
		truthy(bestPx >= MIN_TEXT, string.format("%s: the answer is readable (%.1f px, floor %d)", where, bestPx, MIN_TEXT))
		local r = best
		truthy(r.sx >= -1 and r.sy >= -1 and r.sx + r.sw <= v.w + 1 and r.sy + r.sh <= v.h + 1, where .. ": inside the screen")
		if v.touch then
			local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
				return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
			end
			local under = overlaps(r.sx, r.sy, r.sw, r.sh, 0, bandY, v.w * THUMBSTICK_FRACTION, controlPad)
				or overlaps(r.sx, r.sy, r.sw, r.sh, v.w * (1 - JUMP_FRACTION), bandY, v.w * JUMP_FRACTION, controlPad)
			truthy(not under, where .. ": not under Roblox's touch controls")
		end
		-- nothing tappable hides under the answer: a covered box or button still takes a tap nobody can see
		local covered = nil
		for _, o in h:guiRects(gui, v.w, v.h) do
			if o.shown and o.obj ~= r.obj and (o.class == "TextButton" or o.class == "TextBox") then
				local ox = math.min(o.sx + o.sw, r.sx + r.sw) - math.max(o.sx, r.sx)
				local oy = math.min(o.sy + o.sh, r.sy + r.sh) - math.max(o.sy, r.sy)
				if ox > 1 and oy > 1 then covered = covered or (o.class .. " '" .. tostring(o.obj.Text) .. "'") end
			end
		end
		eq(covered, nil, where .. ": nothing tappable is covered by the answer")
	end
	eq(smallTap, nil, where .. ": nothing tappable in the drawer is under a 44-px tap target while it shows")

	h:advance(2.1)
	local still = false
	for _, r in h:guiRects(gui, v.w, v.h) do
		if r.shown and r.obj.Text == want and r.obj ~= codeBox then still = true end
	end
	truthy(not still, where .. ": gone after 2 s")
	local boxShown, btnShown, btnR = false, false, nil
	for _, r in h:guiRects(gui, v.w, v.h) do
		if r.obj == codeBox then boxShown = r.shown end
		if r.obj == codeBtn then btnShown = r.shown; btnR = r end
	end
	truthy(boxShown and btnShown, where .. ": the box and the button are back")
	eq(codeBtn.Text, "Redeem", where .. ": the button says Redeem again")
	if v.touch and btnR then
		truthy(math.min(btnR.sw, btnR.sh) >= MIN_TAP, string.format("%s: Redeem is a 44-px tap target again (%.0fx%.0f)", where, btnR.sw, btnR.sh))
	end
end

local VIEWPORTS = {
	{ name = "small phone", w = 640, h = 300, touch = true, all = true },
	{ name = "phone", w = 667, h = 375, touch = true },
	{ name = "phone landscape", w = 800, h = 360, touch = true },
	{ name = "big phone", w = 896, h = 414, touch = true },
	{ name = "phone portrait", w = 414, h = 800, touch = true, all = true },
	{ name = "small mouse window", w = 800, h = 600, touch = false },
	{ name = "laptop", w = 1280, h = 720, touch = false, twice = true },
}

local first = true
for _, v in VIEWPORTS do
	h:setTouch(v.touch)
	h:setViewport(v.w, v.h)
	h:advance(0.1)
	openCodeDrawer()
	-- the empty box's hint is text the player must read too; in portrait the one-row box is ~49 px wide
	for _, r in h:guiRects(gui, v.w, v.h) do
		if r.obj == codeBox then
			local px = textPx(r, codeBox.PlaceholderText)
			table.insert(report, string.format("  %-30s %-13s in a %5.1f x %4.1f px %-10s -> %4.1f px text", v.name .. " " .. v.w .. "x" .. v.h,
				"'" .. codeBox.PlaceholderText .. "'", r.sw, r.sh, "TextBox", px))
			truthy(r.shown, v.name .. ": the code box is on screen")
			truthy(px >= MIN_TEXT, string.format("%s: the empty box's hint '%s' is readable (%.1f px, floor %d)", v.name, codeBox.PlaceholderText, px, MIN_TEXT))
		end
	end
	if first then
		-- a real code once (the server takes it), then the same code again
		redeem(v, "welcome", "✅ Redeemed!")
		eq(codeBox.Text, "", v.name .. ": a redeemed code is cleared from the box")
		redeem(v, "WELCOME", "Already used")
		first = false
	elseif v.all then
		redeem(v, "CRYSTAL", "✅ Redeemed!")
		redeem(v, "CRYSTAL", "Already used")
	end
	redeem(v, "NOPE", "Invalid code")
	eq(codeBox.Text, "NOPE", v.name .. ": a mistyped code stays in the box, to be corrected")
	codeBox.Text = ""
	if v.twice then
		-- On desktop the button stays tappable while it shows an answer, so a second try can come 1 s after
		-- the first: the second answer gets its full 2 s, and the first one's timer must not cut it short.
		-- (On a phone the button is hidden while an answer shows, so two can never overlap there.)
		codeBox.Text = "NOPE"; codeBtn.Activated:Fire(); h:advance(1)
		codeBox.Text = "NOPE2"; codeBtn.Activated:Fire(); h:advance(1.2)
		eq(codeBtn.Text, "Invalid code", v.name .. ": a second answer 1 s after the first stays up its full 2 s (1.2 s in)")
		h:advance(1)
		eq(codeBtn.Text, "Redeem", v.name .. ": and then goes")
		codeBox.Text = ""
	end
end

print("measured (estimated TextScaled size of the answer, screen px):")
for _, line in report do print(line) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no warnings")
print(string.format("growacrystal redeem: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal redeem check failed", 0) end
