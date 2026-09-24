-- fork-tower — the HUD's panels that OPEN, with the ambience row: the phone drawers and the Build Reveal
-- card. Run: luau check_forktower_hud_open.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- check_forktower_hud.luau runs emu/hudcheck with the drawers CLOSED and the Build Reveal card hidden, and
-- neither is measured there ("position unmeasured"). On a phone the menu (☰ Meny: Skip, Rebirth, the code
-- box) and the leaderboard (🏆 Topp) are drawers, and the summit's Build Reveal card is the reward screen.
-- The environment work put the ambience row (the band chip and the ☕ Hvil button) between the toast and
-- the HUD's `bandTop`, where all three hung. Measured 2026-09-24 on a LANDSCAPE phone (800x360 and
-- 640x300, how most Roblox phone players hold the phone): both drawers and the card were 1 px tall, the
-- card's close button drawn above it, the Rebirth button out of reach. Nothing was red. Before the
-- ambience row the same phone had 35 px drawers and a 35 px card (1 px at 640x300): cramped already.
--
-- emu/hudcheck cannot measure an open drawer usefully: it reports every control that has scrolled out of
-- the drawer's window as sitting under the thumbstick, because it does not clip a ScrollingFrame's content
-- (Roblox does, and the player scrolls it up into the window). So this file asks the questions that
-- matter, of the panel's own frame, at every hudcheck viewport:
--   A. each drawer, opened through its real toggle: open, at least a thumb's row tall (hudcheck's 44
--      screen px), ending above Roblox's touch controls, covering nothing else the HUD shows; and the
--      ambience row is back once it is closed;
--   B. the Build Reveal card, shown: its close button lies inside it, is thumb-sized and clear of the
--      touch controls, the card leaves both drawer toggles uncovered (the menu holds Rebirth), and it never
--      sits over a VISIBLE ambience row (where it has to cover the row, the row is hidden while it is up);
--      and the ambience row is back once the card is closed.
-- The card is shown by setting its Visible, as the HUD's own reveal does; its layout does not depend on
-- how it was opened.

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")

-- hudcheck's own numbers (emu/hudcheck.luau), so the two gates agree on what a phone's controls cover
local MIN_TAP = 44
local MAX_CONTROL_PAD = 150

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local VIEWPORTS = HudCheck.VIEWPORTS
local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower", viewport = { VIEWPORTS[1].w, VIEWPORTS[1].h }, touch = VIEWPORTS[1].touch })
assert(h:tryRun("server/Main.server"))
local player = h:join("OpenPanelTester", 5551313)
h:advance(1)
assert(h:tryRun("client/Hud.client"))
local okAmb, errAmb = h:tryRun("client/Ambience.client")
truthy(okAmb, "Ambience.client loads (" .. tostring(errAmb) .. ")")
h:advance(0.5)
local gui = player.PlayerGui:FindFirstChild("ForkHud")
local root = gui:FindFirstChild("Root")

local function measure(v)
	h:setTouch(v.touch)
	h:setViewport(v.w, v.h)
	h:advance(0.1)
	h:settleLayouts(gui, v.w, v.h)
	h:advance(0.05)
	local top, all = {}, {}
	for _, r in h:guiRects(gui, v.w, v.h) do
		if r.depth == 2 then top[r.name] = r end
		all[r.name] = all[r.name] or r
	end
	return top, all
end
local function controlsFrom(v)
	return v.h - math.min(MAX_CONTROL_PAD, math.floor(v.h * 0.35))
end
local function overlaps(a, b)
	local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
	local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
	return ox > 1 and oy > 1
end
local function span(r) return string.format("y %.0f..%.0f x %.0f..%.0f", r.sy, r.sy + r.sh, r.sx, r.sx + r.sw) end

--======================================================================= A. the drawers

local DRAWERS = {
	{ toggle = "MenuToggle", frame = "Stats", label = "menu drawer (☰ Meny)" },
	{ toggle = "TopToggle", frame = "Leaderboard", label = "leaderboard drawer (🏆 Topp)" },
}
local compactSeen = 0
for _, d in DRAWERS do
	-- open it through its real toggle (the toggles are exclusive: opening one closes the other)
	local toggle = root:FindFirstChild(d.toggle)
	truthy(toggle ~= nil, d.toggle .. " exists")
	toggle.Activated:Fire()
	h:advance(0.1)
	for _, v in VIEWPORTS do
		local rs = measure(v)
		local where = string.format("[%s %dx%d] %s", v.name, v.w, v.h, d.label)
		local frame = rs[d.frame]
		if toggle.Visible == true then compactSeen += 1 end
		truthy(frame ~= nil and frame.shown, where .. " is open")
		if frame ~= nil and frame.shown then
			truthy(frame.sh >= MIN_TAP, string.format("%s is at least a thumb's row tall (%.0f screen px >= %d)", where, frame.sh, MIN_TAP))
			if v.touch then
				truthy(frame.sy + frame.sh <= controlsFrom(v) + 1, string.format("%s ends above the touch controls (%s, controls from y %d)",
					where, span(frame), controlsFrom(v)))
			end
			-- nothing else the HUD shows at the top level: the counter, the inscription, the toast, the
			-- ambience row, the toggles, the other panel
			local hit = {}
			for name, other in rs do
				if name ~= d.frame and other.shown and other.sw > 1 and other.sh > 1 and overlaps(frame, other) then
					hit[#hit + 1] = name .. " " .. span(other)
				end
			end
			table.sort(hit)
			truthy(#hit == 0, string.format("%s (%s) covers nothing else the HUD shows (%s)", where, span(frame), table.concat(hit, "; ")))
		end
	end
	-- close it again: the ambience row is back on a phone
	toggle.Activated:Fire()
	h:advance(0.1)
	local rs = measure(VIEWPORTS[1])
	truthy(rs.AmbienceRow ~= nil and rs.AmbienceRow.shown and rs.AmbienceRow.sh > 0,
		"with the " .. d.label .. " closed again, the ambience row is shown on " .. VIEWPORTS[1].name)
	truthy(rs[d.frame] == nil or not rs[d.frame].shown, "and the " .. d.label .. " is closed on " .. VIEWPORTS[1].name)
end
truthy(compactSeen >= 8, "set-up: the phone (compact) layouts were among those measured (" .. compactSeen .. " drawer x viewport runs)")

--======================================================================= B. the Build Reveal card

local card = root:FindFirstChild("Reveal")
truthy(card ~= nil, "the Build Reveal card exists")
card.Visible = true
h:advance(0.1)
for _, v in VIEWPORTS do
	local rs, all = measure(v)
	local where = string.format("[%s %dx%d] Build Reveal card", v.name, v.w, v.h)
	local c, close = rs.Reveal, all.CardClose
	truthy(c ~= nil and c.shown, where .. " is shown")
	if c ~= nil and c.shown and close ~= nil then
		truthy(close.sy >= c.sy - 1 and close.sy + close.sh <= c.sy + c.sh + 1,
			string.format("%s: its close button lies inside it (card %s, button %s)", where, span(c), span(close)))
		if v.touch then
			truthy(close.sh >= MIN_TAP, string.format("%s: its close button is thumb-sized (%.0f px)", where, close.sh))
			truthy(c.sy + c.sh <= controlsFrom(v) + 1, string.format("%s ends above the touch controls (%s, controls from y %d)",
				where, span(c), controlsFrom(v)))
		end
		for _, t in { "MenuToggle", "TopToggle" } do
			local tg = rs[t]
			if tg ~= nil and tg.shown then
				truthy(not overlaps(c, tg), string.format("%s leaves %s uncovered (card %s, toggle %s)", where, t, span(c), span(tg)))
			end
		end
		-- Hud.client's own rule: never over the inscription (a rebirth taken with the card open lands the
		-- player on a live fork), nor over the floor counter
		for _, n in { "Rule", "Counter" } do
			local o = rs[n]
			if o ~= nil and o.shown then
				truthy(not overlaps(c, o), string.format("%s never covers the %s (card %s, %s %s)", where,
					if n == "Rule" then "inscription" else "floor counter", span(c), n, span(o)))
			end
		end
		local row = rs.AmbienceRow
		truthy(row == nil or not row.shown or not overlaps(c, row),
			string.format("%s never sits over a visible ambience row (card %s, row %s)", where, span(c), row and span(row) or "-"))
	end
end
card.Visible = false
h:advance(0.1)
do
	local rs = measure(VIEWPORTS[1])
	truthy(rs.AmbienceRow ~= nil and rs.AmbienceRow.shown and rs.AmbienceRow.sh > 0,
		"with the card closed, the ambience row is shown on " .. VIEWPORTS[1].name)
end

truthy(#h:errors() == 0, "no script errors (" .. table.concat(h:errors(), " | ") .. ")")
print(string.format("fork tower hud open: %d passed, %d failed", passed, failed))
if failed > 0 then error("fork tower hud open check failed", 0) end
