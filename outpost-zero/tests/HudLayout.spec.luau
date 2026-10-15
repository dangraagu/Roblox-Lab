-- HudLayout — where every piece of the phone-first HUD goes, for BOTH client scripts (Hud.client draws credits,
-- the balance bar, the Orders chip, the ★ line, toasts, the hint and ★ Show me; Sky.client the band chip, ☕ Break,
-- the hazard warning and the title card). One pure function computes all of it, so the two scripts can never
-- disagree. Run: luau tests/HudLayout.spec.luau  (adapted from meteor-drop-tycoon's HudLayout.spec)
--
-- The rules are robloxemu/emu/hudcheck.luau's, applied to every rectangle with every piece showing at once, at
-- hudcheck's ten viewports: on screen, no two pieces overlapping, tap targets >= 44 screen px on touch, nothing
-- tappable under the thumbstick (bottom-left 35%) or the jump button (bottom-right 25%). The headless hudcheck
-- then measures the real built HUD (robloxemu/check_outpostzero_hud.luau).

local Responsive = require("../src/shared/Responsive")
local HudLayout = require("../src/shared/HudLayout")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

-- hudcheck.luau's list, verbatim, including the flag-flip pairs
local VIEWPORTS = {
	{ name = "phone landscape", w = 800, h = 360, touch = true },
	{ name = "small phone", w = 640, h = 300, touch = true },
	{ name = "phone portrait", w = 414, h = 800, touch = true },
	{ name = "small mouse window", w = 800, h = 600, touch = false },
	{ name = "tablet", w = 1024, h = 768, touch = true },
	{ name = "laptop", w = 1366, h = 768, touch = false },
	{ name = "laptop, touch", w = 1366, h = 768, touch = true },
	{ name = "desktop", w = 1920, h = 1080, touch = false },
	{ name = "phone landscape, mouse", w = 800, h = 360, touch = false },
	{ name = "phone landscape, touch again", w = 800, h = 360, touch = true },
}
local INSET = 36 -- Roblox's topbar, as robloxemu models it (Harness.GUI_INSET_Y)

local PIECES = { "credits", "chip", "balance", "orders", "star", "warning", "toast", "hint", "breakBtn", "showBtn", "card", "cardSub" }
local TAPPABLE = { breakBtn = true, showBtn = true }

local function overlaps(a, b)
	return a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1
end

local narrowest = math.huge
for _, v in VIEWPORTS do
	local L = HudLayout.compute(Responsive, v.w, v.h, v.touch, INSET)
	local where = v.name
	local function screen(r)
		return { x = r.x * L.scale, y = INSET + r.y * L.scale, w = r.w * L.scale, h = r.h * L.scale }
	end
	for _, name in PIECES do
		local r = L[name]
		truthy(type(r) == "table" and r.w > 0 and r.h > 0, where .. ": " .. name .. " has a size")
	end
	-- 1. on screen
	for _, name in PIECES do
		local s = screen(L[name])
		truthy(s.x >= -1 and s.y >= INSET - 1 and s.x + s.w <= v.w + 1 and s.y + s.h <= v.h + 1,
			string.format("%s: %s is on screen (x %.0f..%.0f, y %.0f..%.0f in %dx%d)", where, name, s.x, s.x + s.w, s.y, s.y + s.h, v.w, v.h))
	end
	-- 2. nothing overlaps anything (every piece at once: the worst case)
	for i = 1, #PIECES do
		for j = i + 1, #PIECES do
			local a, b = L[PIECES[i]], L[PIECES[j]]
			truthy(not overlaps(a, b), string.format("%s: %s and %s do not overlap", where, PIECES[i], PIECES[j]))
		end
	end
	-- 3 + 4. tap targets and the touch controls
	if v.touch then
		local pad = math.min(150, math.floor(v.h * 0.35))
		local bandY = v.h - pad
		for name in TAPPABLE do
			local s = screen(L[name])
			truthy(math.min(s.w, s.h) >= 44, string.format("%s: %s is %.0fx%.0f screen px, at least 44", where, name, s.w, s.h))
			local inLeft = s.x < v.w * 0.35 and s.y + s.h > bandY
			local inRight = s.x + s.w > v.w * 0.75 and s.y + s.h > bandY
			truthy(not inLeft and not inRight, string.format("%s: %s is clear of the thumbstick and the jump button", where, name))
		end
	end
	narrowest = math.min(narrowest, L.credits.w)
	truthy(L.credits.x + L.credits.w <= L.breakBtn.x + 0.5, where .. ": the top stack ends left of the button column")
	eq(L.showBtn.x, L.breakBtn.x, where .. ": the two buttons share one column")
	truthy(L.showBtn.y > L.breakBtn.y, where .. ": ★ Show me sits below ☕ Break")
end
truthy(narrowest >= 260, string.format("the top stack is never narrower than 260 design px (narrowest %.0f)", narrowest))

-- the column sits between 45% and 70% of the height wherever the screen has room for it
do
	local L = HudLayout.compute(Responsive, 1920, 1080, false, INSET)
	local top, bottom = L.breakBtn.y, L.showBtn.y + L.showBtn.h
	truthy(top >= L.rootH * 0.45 and bottom <= L.rootH * 0.70,
		string.format("on a desktop the buttons sit between 45%% and 70%% of the height (%.0f..%.0f of %.0f)", top, bottom, L.rootH))
	eq(L.scale, 1, "a 1920x1080 desktop is drawn at scale 1")
	truthy(math.abs((L.credits.x + L.credits.w / 2) - L.rootW / 2) < 1, "and the credits are top centre")
	-- the stack's order (DESIGN 15): credits, population chip, balance, Orders, ★ line, then warning, toast, hint
	local order = { "credits", "chip", "balance", "orders", "star", "warning", "toast", "hint" }
	for i = 2, #order do
		truthy(L[order[i]].y > L[order[i - 1]].y, order[i] .. " sits below " .. order[i - 1])
	end
end
-- design px that reach 44 screen px on touch, unchanged with a mouse
do
	eq(HudLayout.touchSize(40, 1, false), 40, "a mouse keeps the design size")
	eq(HudLayout.touchSize(40, 0.6, true), 75, "touch at scale 0.6: ceil(44.5 / 0.6) = 75 design px")
	eq(HudLayout.touchSize(40, 1, true), 45, "touch at scale 1: 45 design px")
end

print(string.format("HudLayout: %d passed, %d failed", passed, failed))
if failed > 0 then error("HudLayout spec failed", 0) end
