-- HudLayout — where every piece of the phone-first HUD goes, for BOTH client scripts (Hud.client draws the
-- wallet, hopper, toast, hint, Upgrades button and panel; Sky.client the band chip, Stargaze button,
-- hazard warning and title card). One pure function computes all of it, so the two scripts can never
-- disagree. Run: luau tests/HudLayout.spec.luau
--
-- The rules are robloxemu/emu/hudcheck.luau's, applied here to every rectangle in every state (panel
-- open and closed, warning, toast, hint and cards all showing at once), at hudcheck's ten viewports:
-- on screen, no two pieces overlapping, tap targets >= 44 screen px on touch, nothing tappable under the
-- thumbstick (bottom-left 35%) or the jump button (bottom-right 25%). The headless hudcheck then measures
-- the real built HUD (robloxemu/check_meteordroptycoon_hud.luau).

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

local PIECES = { "wallet", "chip", "hopper", "warning", "toast", "hint", "upgradeBtn", "stargazeBtn", "panel",
	"card", "cardSub", "starCard" }
local TAPPABLE = { upgradeBtn = true, stargazeBtn = true }

local function overlaps(a, b)
	return a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1
end

local worstStack = math.huge
for _, v in VIEWPORTS do
	for _, open in { false, true } do
		local L = HudLayout.compute(Responsive, v.w, v.h, v.touch, INSET, open)
		local where = string.format("%s%s", v.name, if open then " (panel open)" else "")
		-- screen px of a design rect: the root is scaled by L.scale and pushed down by the inset
		local function screen(r)
			return { x = r.x * L.scale, y = INSET + r.y * L.scale, w = r.w * L.scale, h = r.h * L.scale }
		end
		local shown = {}
		for _, name in PIECES do
			local r = L[name]
			truthy(type(r) == "table" and r.w > 0 and r.h > 0, where .. ": " .. name .. " has a size")
			if name ~= "panel" or open then shown[name] = r end
		end
		-- 1. on screen
		for name, r in shown do
			local s = screen(r)
			truthy(s.x >= -1 and s.y >= INSET - 1 and s.x + s.w <= v.w + 1 and s.y + s.h <= v.h + 1,
				string.format("%s: %s is on screen (x %.0f..%.0f, y %.0f..%.0f in %dx%d)", where, name, s.x, s.x + s.w, s.y, s.y + s.h, v.w, v.h))
		end
		-- 2. nothing overlaps anything
		local names = {}
		for name in shown do table.insert(names, name) end
		table.sort(names)
		for i = 1, #names do
			for j = i + 1, #names do
				local a, b = shown[names[i]], shown[names[j]]
				truthy(not overlaps(a, b), string.format("%s: %s and %s do not overlap", where, names[i], names[j]))
			end
		end
		-- 3 + 4. tap targets and the touch controls
		if v.touch then
			local pad = math.min(150, math.floor(v.h * 0.35))
			local bandY = v.h - pad
			for name in TAPPABLE do
				local s = screen(shown[name])
				truthy(math.min(s.w, s.h) >= 44, string.format("%s: %s is %.0fx%.0f screen px, at least 44", where, name, s.w, s.h))
				local inLeft = s.x < v.w * 0.35 and s.y + s.h > bandY
				local inRight = s.x + s.w > v.w * 0.75 and s.y + s.h > bandY
				truthy(not inLeft and not inRight, string.format("%s: %s is clear of the thumbstick and the jump button", where, name))
			end
			-- the panel's rows: every BUY button is a tap target, laid out inside the panel with no scrolling
			if open then
				local rows = HudLayout.panelRows(L)
				eq(#rows, 3, where .. ": three rows (Beacon, Collector, Smelter)")
				for i, row in rows do
					local abs = { x = L.panel.x + row.buy.x, y = L.panel.y + row.buy.y, w = row.buy.w, h = row.buy.h }
					local s = screen(abs)
					truthy(math.min(s.w, s.h) >= 44, string.format("%s: BUY %d is %.0fx%.0f screen px", where, i, s.w, s.h))
					truthy(row.y + row.h <= L.panel.h + 0.5, string.format("%s: row %d fits inside the panel with no scrolling", where, i))
					truthy(not (s.x + s.w > v.w * 0.75 and s.y + s.h > bandY), string.format("%s: BUY %d is clear of the jump button", where, i))
				end
			end
		end
		worstStack = math.min(worstStack, L.wallet.w)
		-- the stack and the right column share nothing horizontally
		truthy(L.wallet.x + L.wallet.w <= math.min(L.upgradeBtn.x, if open then L.panel.x else math.huge) + 0.5,
			where .. ": the top stack ends left of the right-hand column")
	end
end
truthy(worstStack >= 260, string.format("the top stack is never narrower than 260 design px (narrowest %.0f)", worstStack))

-- the column sits between 45% and 70% of the height wherever the screen has room for it
do
	local L = HudLayout.compute(Responsive, 1920, 1080, false, INSET, false)
	local top, bottom = L.upgradeBtn.y, L.stargazeBtn.y + L.stargazeBtn.h
	truthy(top >= L.rootH * 0.45 and bottom <= L.rootH * 0.70,
		string.format("on a desktop the buttons sit between 45%% and 70%% of the height (%.0f..%.0f of %.0f)", top, bottom, L.rootH))
	eq(L.scale, 1, "a 1920x1080 desktop is drawn at scale 1")
	truthy(math.abs((L.wallet.x + L.wallet.w / 2) - L.rootW / 2) < 1, "and the wallet is top centre")
end

-- a changing panel moves the column with the panel's left edge
do
	local closed = HudLayout.compute(Responsive, 1366, 768, false, INSET, false)
	local open = HudLayout.compute(Responsive, 1366, 768, false, INSET, true)
	truthy(open.upgradeBtn.x + open.upgradeBtn.w <= open.panel.x, "with the panel open, the buttons sit left of it")
	truthy(closed.upgradeBtn.x > open.upgradeBtn.x, "and they moved to get there")
end

print(string.format("HudLayout: %d passed, %d failed", passed, failed))
if failed > 0 then error("HudLayout spec failed", 0) end
