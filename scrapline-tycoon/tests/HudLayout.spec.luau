-- HudLayout — where every piece of the phone-first HUD goes, for BOTH client scripts (Hud.client draws the
-- wallet, alert, toast, hint, the column's Line / Recycle slots and the line panel; Yard.client the band chip, the
-- ☕ Break slot and the hazard warning). One pure function computes all of it, so the two scripts can never
-- disagree. Run: luau tests/HudLayout.spec.luau
--
-- The rules are robloxemu/emu/hudcheck.luau's, applied here to every rectangle in every state (panel open and
-- closed, every row of every page, alert, warning, toast, hint and cards all showing at once), at hudcheck's ten
-- viewports: on screen, no two pieces overlapping, tap targets >= 44 screen px on touch, nothing tappable under
-- the thumbstick (bottom-left 35%) or the jump button (bottom-right 25%). The line panel PAGES instead of
-- scrolling (hudcheck measures a scrolled-away row where it would be with no scroll, under the jump button), so
-- every row of every page is checked here. The headless hudcheck then measures the real built HUD
-- (robloxemu/check_scraplinetycoon_hud.luau).

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

local PIECES = { "wallet", "chip", "alert", "warning", "toast", "hint", "slot1", "slot2", "slot3", "panel", "card", "cardSub", "bragCard" }
local TAPPABLE = { slot1 = true, slot2 = true, slot3 = true }

local function overlaps(a, b)
	return a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1
end

local worstStack, minPerPage, maxPages = math.huge, math.huge, 0
for _, v in VIEWPORTS do
	for _, open in { false, true } do
		local L = HudLayout.compute(Responsive, v.w, v.h, v.touch, INSET, open)
		local where = string.format("%s%s", v.name, if open then " (panel open)" else "")
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
				truthy(not overlaps(shown[names[i]], shown[names[j]]), string.format("%s: %s and %s do not overlap", where, names[i], names[j]))
			end
		end
		-- 3 + 4. tap targets and the touch controls
		local pad = if v.touch then math.min(150, math.floor(v.h * 0.35)) else 0
		local bandY = v.h - pad
		local function clear(s)
			local inLeft = s.x < v.w * 0.35 and s.y + s.h > bandY
			local inRight = s.x + s.w > v.w * 0.75 and s.y + s.h > bandY
			return not inLeft and not inRight
		end
		if v.touch then
			for name in TAPPABLE do
				local s = screen(shown[name])
				truthy(math.min(s.w, s.h) >= 44, string.format("%s: %s is %.0fx%.0f screen px, at least 44", where, name, s.w, s.h))
				truthy(clear(s), string.format("%s: %s is clear of the thumbstick and the jump button", where, name))
			end
		end
		-- the line panel: every row of every page, and every button in it
		if open then
			local PL = HudLayout.panelLayout(L)
			minPerPage = math.min(minPerPage, PL.perPage)
			maxPages = math.max(maxPages, PL.pages)
			truthy(PL.perPage >= 1, where .. ": at least one row per page")
			eq(math.ceil(6 / PL.perPage), PL.pages, where .. ": pages cover all six stations")
			for slotIdx = 1, PL.perPage do
				local row = HudLayout.panelRow(L, PL, slotIdx)
				truthy(row.y >= PL.headerH and row.y + row.h <= L.panel.h + 0.5,
					string.format("%s: row slot %d (y %.0f..%.0f) fits inside the panel (h %.0f), under the header", where, slotIdx, row.y, row.y + row.h, L.panel.h))
				truthy(row.text.w >= 60, string.format("%s: row slot %d leaves %.0f design px for its text", where, slotIdx, row.text.w))
				for b = 1, 2 do
					local br = row.buttons[b]
					local abs = { x = L.panel.x + br.x, y = L.panel.y + br.y, w = br.w, h = br.h }
					truthy(br.x >= 0 and br.x + br.w <= L.panel.w + 0.5 and br.y >= row.y - 0.5 and br.y + br.h <= row.y + row.h + 0.5,
						string.format("%s: row %d button %d sits inside its row", where, slotIdx, b))
					truthy(not overlaps(br, row.text), string.format("%s: row %d button %d clears the row's text", where, slotIdx, b))
					if v.touch then
						local s = screen(abs)
						truthy(math.min(s.w, s.h) >= 44, string.format("%s: row %d button %d is %.0fx%.0f screen px", where, slotIdx, b, s.w, s.h))
						truthy(clear(s), string.format("%s: row %d button %d is clear of the touch controls", where, slotIdx, b))
					end
				end
				truthy(not overlaps(row.buttons[1], row.buttons[2]), where .. ": the two buttons of a row do not overlap")
				if slotIdx > 1 then
					local prev = HudLayout.panelRow(L, PL, slotIdx - 1)
					truthy(row.y >= prev.y + prev.h, where .. ": rows do not overlap")
				end
			end
		end
		worstStack = math.min(worstStack, L.wallet.w)
		truthy(L.wallet.x + L.wallet.w <= math.min(L.slot1.x, if open then L.panel.x else math.huge) + 0.5,
			where .. ": the top stack ends left of the right-hand column")
	end
end
print(string.format("  narrowest stack %.0f design px; fewest rows on a page %d; most pages %d", worstStack, minPerPage, maxPages))
truthy(worstStack >= 260, string.format("the top stack is never narrower than 260 design px (narrowest %.0f)", worstStack))

-- the column sits between 45% and 70% of the height wherever the screen has room for it
do
	local L = HudLayout.compute(Responsive, 1920, 1080, false, INSET, false)
	local top, bottom = L.slot1.y, L.slot3.y + L.slot3.h
	truthy(top >= L.rootH * 0.45 and bottom <= L.rootH * 0.70,
		string.format("on a desktop the column sits between 45%% and 70%% of the height (%.0f..%.0f of %.0f)", top, bottom, L.rootH))
	eq(L.scale, 1, "a 1920x1080 desktop is drawn at scale 1")
	truthy(math.abs((L.wallet.x + L.wallet.w / 2) - L.rootW / 2) < 1, "and the wallet is top centre")
	local PL = HudLayout.panelLayout(HudLayout.compute(Responsive, 1920, 1080, false, INSET, true))
	eq(PL.pages, 1, "on a desktop all six stations fit on one page")
end

-- a changing panel moves the column with the panel's left edge
do
	local closed = HudLayout.compute(Responsive, 1366, 768, false, INSET, false)
	local open = HudLayout.compute(Responsive, 1366, 768, false, INSET, true)
	truthy(open.slot1.x + open.slot1.w <= open.panel.x, "with the panel open, the column sits left of it")
	truthy(closed.slot1.x > open.slot1.x, "and it moved to get there")
end

-- the page that holds a station
do
	local L = HudLayout.compute(Responsive, 800, 360, true, INSET, true)
	local PL = HudLayout.panelLayout(L)
	eq(HudLayout.pageOf(PL, 1), 1, "the Shredder is on page 1")
	eq(HudLayout.pageOf(PL, 6), PL.pages, "the Rocket Bay is on the last page")
	eq(HudLayout.slotOf(PL, PL.perPage + 1), 1, "the first station of page 2 takes the top slot")
end

print(string.format("HudLayout: %d passed, %d failed", passed, failed))
if failed > 0 then error("HudLayout spec failed", 0) end
