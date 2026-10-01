-- Grow a Crystal — the first-run hint is readable on every screen. Run: luau check_growacrystal_hint.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The hint under the dust readout is the game's whole tutorial: it names the core action (plant a seed in a
-- glowing socket) and the payoff (harvest the grown crystal). docs/new-game-checklist.md §4: "On-screen hint naming
-- the exact action". Review round 2 left it open: on phones the one long sentence came out about 8 screen px,
-- because it is one TextScaled line capped at 460 design px wide under a UIScale of 0.6.
--
-- Estimated exactly like the toast in check_growacrystal_refused (one line at ~0.6 em per glyph, capped by the
-- label's height, its UISizeConstraint width and its UITextSizeConstraint): at least 12 screen px at every
-- viewport hudcheck uses, and it still names both actions.

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
assert(h:tryRun("server/Main.server"))
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Reader", 4401)
assert(h:tryRun("client/Hud.client"))
h:advance(1)

local function isHint(text: string): boolean
	local t = string.upper(text)
	return string.find(t, "PLANT", 1, true) ~= nil and string.find(t, "HARVEST", 1, true) ~= nil
end

local worst, worstAt = math.huge, ""
for _, v in HudCheck.VIEWPORTS do
	h:setTouch(v.touch)
	h:setViewport(v.w, v.h)
	h:advance(0.2)
	for _, g in plr.PlayerGui:GetChildren() do h:settleLayouts(g, v.w, v.h) end
	local shown = nil
	for _, r in h:guiRects(plr.PlayerGui.CrystalHud, v.w, v.h) do
		if r.shown and r.class == "TextLabel" and isHint(r.obj.Text) then shown = r end
	end
	truthy(shown ~= nil, v.name .. ": the hint naming PLANT and HARVEST is on screen")
	if shown then
		local m = shown.obj.Text
		local sw = shown.sw
		local sc = shown.obj:FindFirstChildOfClass("UISizeConstraint")
		if sc and sc.MaxSize.X < math.huge then sw = math.min(sw, sc.MaxSize.X * shown.scale) end
		local px = math.min(shown.sh, sw / (0.6 * utf8.len(m)))
		local cc = shown.obj:FindFirstChildOfClass("UITextSizeConstraint")
		if cc then px = math.min(px, cc.MaxTextSize * shown.scale) end
		print(string.format("  %-30s %5.1f px  %q", v.name, px, m))
		if px < worst then worst, worstAt = px, string.format("%s %dx%d: %q", v.name, v.w, v.h, m) end
		if v.touch then
			truthy(string.find(string.lower(m), "tap", 1, true) ~= nil, v.name .. ": on a touch screen it says tap, not click")
		end
	end
end
truthy(worst >= 12, string.format("the hint reads at 12 px or more on every screen (smallest %.1f px, %s)", worst, worstAt))

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal hint: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal hint failed", 0) end
