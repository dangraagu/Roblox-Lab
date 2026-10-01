-- fork-tower — the HUD keeps off the player's own character. Run: luau check_forktower_hud_play.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- Review 2026-09-24. hudcheck (check_forktower_hud) and check_forktower_hud_open measure the HUD against
-- the SCREEN: edges, the touch controls, each other. Neither knows where the game is drawn. On a landscape
-- phone (800x360, 640x300, 844x390, 926x428: how most phone players hold the phone) the environment
-- work's ambience row (the band chip, 80 % opaque, and the opaque ☕ Hvil button) sat across the middle
-- of the screen, over the player's own avatar from head to waist and over the spot where a hazard
-- strikes, the whole time; and the band's title card hung under it, over the avatar's legs and the
-- platform, and off the bottom of a 640x300 phone. Nothing was red.
--
-- So this file puts the avatar on the screen the way Roblox's default camera draws it, and measures the
-- HUD against that, at every hudcheck viewport plus the reviewer's two extra landscape phones and a
-- 1280x720 window:
--   A. THE ALWAYS-ON HUD (what shows in ordinary play, drawers closed: the counter, the inscription, the
--      toggles, the ambience row with its chip and button, and the side panels where they never close)
--      never covers the avatar: the character's box from its feet to the top of its head, arms out, and
--      the red ring at its feet where a hazard hits, at camera pitches -30, -15 and 0 degrees;
--   B. THE BAND TITLE CARD, shown: on screen and below the topbar, clear of the avatar the same way, never
--      over the inscription, the counter, the toast's slot (the server's notice comes with it), a toggle,
--      the ☕ button, or an open drawer (each opened through its real toggle); where it covers the chip at
--      all, it lies inside the chip;
--   C. IT STAYS READABLE: the chip keeps at least 130 screen px of width (the longest warning, "⚠️ FLYTT
--      DEG! URVERKSFUGL ◀", in two lines) and a thumb's height on touch; the card's title is at least 18
--      screen px tall.
--
-- THE CAMERA, stated because every number below rests on it: Roblox's default follow camera, focus =
-- HumanoidRootPart + (0, 1.5, 0) drawn at the centre of the viewport, 12.5 studs zoom (the default
-- start), FieldOfView 70 (vertical, over the full viewport height, topbar included). The avatar is the
-- default R15 box, generously: feet 3 studs below the root, head top 2.5 above it, 4 studs across the
-- arms, 2 deep. The ring is the widest hazard ring (Config.Hazards: 6.8 studs across, at the feet).
-- A player who zooms in draws a bigger avatar; nothing can keep off that.
--
-- THE TOPBAR INSET. The harness resolves a panel's y as (inset + design y) * scale, so under a UIScale it
-- draws the whole HUD 36 * (1 - scale) px too HIGH (14 px on a phone). Roblox pins the scaled root at the
-- inset and scales what is inside it: screen y = inset + design y * scale. Every rect here is corrected to
-- that, because it is compared with where the camera draws the avatar, which the harness does not model.

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local MIN_TAP = 44
local MIN_CHIP_W = 130
local MIN_TITLE_H = 18
local INSET = Harness.GUI_INSET_Y

local VIEWPORTS = {}
for _, v in HudCheck.VIEWPORTS do table.insert(VIEWPORTS, v) end
table.insert(VIEWPORTS, { name = "phone landscape 844", w = 844, h = 390, touch = true })
table.insert(VIEWPORTS, { name = "phone landscape 926", w = 926, h = 428, touch = true })
table.insert(VIEWPORTS, { name = "window 1280", w = 1280, h = 720, touch = false })
-- NARROW LANDSCAPE PHONES (second review, 2026-09-30, finding 2). Every landscape viewport this file
-- measured was 640 px wide or more, and the row's move into the header needed about 617 px: below that it
-- stayed in the centred stack, over the avatar, and the ☰ Meny drawer (the only Rebirth button) came out
-- 1 px tall. 568x320 is the iPhone SE (1st gen) and iPod touch; 592x360 is a 360x640 dp Android phone
-- with its navigation bar at the side; 480x270 is the smallest the reviewer measured.
local NARROW = {
	{ name = "narrow landscape 610", w = 610, h = 343, touch = true },
	{ name = "Android landscape, side nav bar", w = 592, h = 360, touch = true },
	{ name = "iPhone SE landscape", w = 568, h = 320, touch = true },
	{ name = "narrow landscape 540", w = 540, h = 304, touch = true },
	{ name = "narrow landscape 520", w = 520, h = 292, touch = true },
	{ name = "narrow landscape 480", w = 480, h = 270, touch = true },
}
for _, v in NARROW do table.insert(VIEWPORTS, v) end

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower", viewport = { VIEWPORTS[1].w, VIEWPORTS[1].h }, touch = VIEWPORTS[1].touch })
assert(h:tryRun("server/Main.server"))
local player = h:join("PlayAreaTester", 5551317)
h:advance(1)
assert(h:tryRun("client/Hud.client"))
local okAmb, errAmb = h:tryRun("client/Ambience.client")
truthy(okAmb, "Ambience.client loads (" .. tostring(errAmb) .. ")")
h:advance(0.5)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local gui = player.PlayerGui:FindFirstChild("ForkHud")
local root = gui:FindFirstChild("Root")
local row = root:FindFirstChild("AmbienceRow")
local chip = row and row:FindFirstChild("BandChip", true)
local restBtn = row and row:FindFirstChild("RestButton", true)
local card = row and row:FindFirstChild("BandCard", true)
local sub = row and row:FindFirstChild("BandCardSub", true)
truthy(chip ~= nil and restBtn ~= nil and card ~= nil and sub ~= nil, "set-up: the chip, the ☕ button and the band card are in the HUD's ambience row")

-- the widest red ring any hazard draws: 2 * (hitRadius + PlayerRadius) (Hazards.zone)
local RING = 0
for _, k in Config.Hazards.Kinds do RING = math.max(RING, 2 * (k.hitRadius + Config.Hazards.PlayerRadius)) end
truthy(RING >= 6, string.format("set-up: the widest hazard ring is %.1f studs across", RING))

--======================================================================= the camera

-- screen box of a set of world points (relative to the root) under the default camera at `pitch`
local function project(v, pitchDeg, pts)
	local pitch = math.rad(pitchDeg)
	local fwd = Vector3.new(0, math.sin(pitch), math.cos(pitch))
	local up = Vector3.new(0, math.cos(pitch), -math.sin(pitch))
	local focus = Vector3.new(0, 1.5, 0)
	local camPos = focus - fwd * 12.5
	local f = (v.h / 2) / math.tan(math.rad(35))
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in pts do
		local d = p - camPos
		local depth = d:Dot(fwd)
		local sx = v.w / 2 + f * d.X / depth
		local sy = v.h / 2 - f * d:Dot(up) / depth
		x0, x1 = math.min(x0, sx), math.max(x1, sx)
		y0, y1 = math.min(y0, sy), math.max(y1, sy)
	end
	return { sx = x0, sy = y0, sw = x1 - x0, sh = y1 - y0 }
end
local AVATAR = {}
for _, x in { -2, 2 } do
	for _, y in { -3, 2.5 } do
		for _, z in { -1, 1 } do table.insert(AVATAR, Vector3.new(x, y, z)) end
	end
end
local RINGPTS = {}
for i = 0, 23 do
	local a = i / 24 * 2 * math.pi
	table.insert(RINGPTS, Vector3.new(math.cos(a) * RING / 2, -3, math.sin(a) * RING / 2))
end
local PITCHES = { -30, -15, 0 }
local function playBoxes(v)
	local out = {}
	for _, p in PITCHES do
		table.insert(out, { what = string.format("the avatar (pitch %d)", p), r = project(v, p, AVATAR) })
		table.insert(out, { what = string.format("the hazard ring at its feet (pitch %d)", p), r = project(v, p, RINGPTS) })
	end
	return out
end

--======================================================================= the HUD, in screen px

local function real(r)
	-- see THE TOPBAR INSET above
	return { name = r.name, class = r.class, shown = r.shown, depth = r.depth, obj = r.obj,
		sx = r.sx, sw = r.sw, sh = r.sh, sy = r.sy + INSET * (1 - r.scale) }
end
local function measure(v)
	h:setTouch(v.touch)
	h:setViewport(v.w, v.h)
	h:advance(0.1)
	h:settleLayouts(gui, v.w, v.h)
	h:advance(0.05)
	local top, byObj = {}, {}
	for _, r0 in h:guiRects(gui, v.w, v.h) do
		local r = real(r0)
		if r.depth == 2 then top[r.name] = r end
		byObj[r.obj] = r
	end
	return top, byObj
end
local function overlaps(a, b)
	local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
	local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
	return ox > 1 and oy > 1
end
local function inside(a, b)
	return a.sx >= b.sx - 1 and a.sy >= b.sy - 1 and a.sx + a.sw <= b.sx + b.sw + 1 and a.sy + a.sh <= b.sy + b.sh + 1
end
local function union(a, b)
	local x0, y0 = math.min(a.sx, b.sx), math.min(a.sy, b.sy)
	local x1, y1 = math.max(a.sx + a.sw, b.sx + b.sw), math.max(a.sy + a.sh, b.sy + b.sh)
	return { sx = x0, sy = y0, sw = x1 - x0, sh = y1 - y0 }
end
local function span(r) return string.format("x %.0f..%.0f y %.0f..%.0f", r.sx, r.sx + r.sw, r.sy, r.sy + r.sh) end

-- the always-on HUD: every shown panel (drawers closed) but the toast (3.5 s after a notice) and the
-- Build Reveal card (the summit's), plus the chip and the button themselves
local TRANSIENT = { Toast = true, Reveal = true }

-- ONE PRE-EXISTING EXCEPTION, bounded and reported. On the 640x300 phone the inscription panel (HEAD's
-- layout, from before the environment work; the review took it as the baseline, "nothing that stays on
-- screen reached below y 124", which is 138 once the inset is corrected) ends at y 138, and the avatar
-- box's top is at 127-131 (pitch -30..0): its bottom edge crosses the top 7-11 px of the box, the crown of
-- a tall avatar's head. With the head's own top at root + 2.2 (R15, no hat) the overlap is 0-8 px. It is
-- the game's one indispensable panel and was not moved. It may not end lower than it did at HEAD, and it
-- is on EYECANDY.md's Studio list. Nothing the environment work draws is exempt from anything here.
local HEAD_OVERLAP = { ["small phone"] = { Rule = 138.5 } }
-- The same inscription, at the same place, on the narrow landscape phones: at scale 0.6 (the HUD's floor)
-- it ends at y 138 whatever the width, and the shorter the screen, the higher the avatar's head. Held
-- there, not lower, and reported like the 640x300 case (EYECANDY.md §10 item 24).
for _, v in NARROW do HEAD_OVERLAP[v.name] = { Rule = 138.5 } end
local exceptionsSeen = {}

--======================================================================= A + C: ordinary play

local toastOverAvatar = {}
for _, v in VIEWPORTS do
	local top, byObj = measure(v)
	local where = string.format("[%s %dx%d]", v.name, v.w, v.h)
	local always = {}
	for name, r in top do
		if r.shown and not TRANSIENT[name] and r.sw > 1 and r.sh > 1 then always[name] = r end
	end
	local c, b = byObj[chip], byObj[restBtn]
	if c then always["BandChip"] = c end
	if b then always["RestButton"] = b end
	for _, box in playBoxes(v) do
		local hit = {}
		for name, r in always do
			if overlaps(r, box.r) then
				local bound = HEAD_OVERLAP[v.name] and HEAD_OVERLAP[v.name][name]
				if bound ~= nil and r.sy + r.sh <= bound then
					exceptionsSeen[string.format("%s %s ends at y %.0f, box top %.0f", where, name, r.sy + r.sh, box.r.sy)] = true
				else
					table.insert(hit, name .. " " .. span(r))
				end
			end
		end
		table.sort(hit)
		truthy(#hit == 0, string.format("%s the always-on HUD keeps off %s at %s (%s)", where, box.what, span(box.r), table.concat(hit, "; ")))
	end
	-- report only: the server's toast is shown for 3.5 s after each notice (pre-existing, not the review's)
	local toast = top.Toast
	if toast then
		for _, box in playBoxes(v) do
			if overlaps(toast, box.r) then toastOverAvatar[where] = true end
		end
	end
	-- C: readable
	truthy(c ~= nil and c.shown and c.sw >= MIN_CHIP_W, string.format("%s the band chip is shown and at least %d px wide (%s)", where, MIN_CHIP_W, c and span(c) or "-"))
	if v.touch then
		truthy(c ~= nil and c.sh >= MIN_TAP - 0.5 and b ~= nil and b.sh >= MIN_TAP - 0.5 and b.sw >= MIN_TAP - 0.5,
			string.format("%s the chip and the ☕ button keep a thumb's height (chip %s, button %s)", where, c and span(c) or "-", b and span(b) or "-"))
	end
	-- the narrow landscape phones (second review 2026-09-30): the counter gives up width before the drawer
	-- toggles give up their words, so from 568 px up they still say "☰ Meny" and "🏆 Topp"; only below that
	-- are they a thumb's square with the glyph alone, and still a thumb's square
	local menuT, topT = root:FindFirstChild("MenuToggle"), root:FindFirstChild("TopToggle")
	if menuT and menuT.Visible and v.touch and v.w < 640 and v.w > v.h then
		local worded = string.find(menuT.Text, "Meny", 1, true) ~= nil and string.find(topT.Text, "Topp", 1, true) ~= nil
		if v.w >= 568 then
			truthy(worded, string.format("%s the drawer toggles keep their words (%s | %s)", where, menuT.Text, topT.Text))
		else
			truthy(not worded, string.format("%s the drawer toggles are glyphs (%s | %s)", where, menuT.Text, topT.Text))
			local mr = byObj[menuT]
			truthy(mr ~= nil and mr.sw >= MIN_TAP - 0.5 and mr.sh >= MIN_TAP - 0.5, string.format("%s and still a thumb's square (%s)", where, mr and span(mr) or "-"))
		end
	end
end

--======================================================================= B: the band title card, shown

-- shown as Ambience shows it: its text, and every frame from it up to the row visible
local function showCard(on)
	card.Text = "🌿 DEN GJENGRODDE HAGEN"
	sub.Text = "etasje 3"
	local node = card
	while node ~= nil and node ~= row do
		node.Visible = on
		node = node.Parent
	end
	sub.Visible = on
	card.TextTransparency = 0
	sub.TextTransparency = 0
end
showCard(true)
local DRAWERS = { { toggle = "MenuToggle", frame = "Stats" }, { toggle = "TopToggle", frame = "Leaderboard" } }
for _, v in VIEWPORTS do
	local top, byObj = measure(v)
	local where = string.format("[%s %dx%d] band card", v.name, v.w, v.h)
	local cr, sr = byObj[card], byObj[sub]
	truthy(cr ~= nil and sr ~= nil and cr.shown and sr.shown, where .. " is shown")
	if cr and sr then
		local u = union(cr, sr)
		for n, o in byObj do
			-- a background plate behind the title, if the card has one, is part of the card
			if o.shown and n ~= card and n ~= sub and (n:IsDescendantOf(row)) and card:IsDescendantOf(n) and n ~= row
				and n.ClassName == "Frame" and o.depth > 3 then
				u = union(u, o)
			end
		end
		truthy(u.sy >= INSET - 1 and u.sy + u.sh <= v.h + 1 and u.sx >= -1 and u.sx + u.sw <= v.w + 1,
			string.format("%s is on screen, below the topbar (%s in %dx%d)", where, span(u), v.w, v.h))
		for _, box in playBoxes(v) do
			truthy(not overlaps(u, box.r), string.format("%s keeps off %s (card %s, %s)", where, box.what, span(u), span(box.r)))
		end
		for _, n in { "Rule", "Counter", "Toast", "MenuToggle", "TopToggle" } do
			local o = top[n]
			-- the toast's SLOT counts whether or not a toast is up: the floor-clear notice comes with the card
			if o and (o.shown or n == "Toast") and o.sw > 1 and o.sh > 1 then
				truthy(not overlaps(u, o), string.format("%s never covers the %s (card %s, %s %s)", where, n, span(u), n, span(o)))
			end
		end
		local b, c = byObj[restBtn], byObj[chip]
		truthy(b == nil or not overlaps(u, b), string.format("%s leaves the ☕ button uncovered (card %s, button %s)", where, span(u), b and span(b) or "-"))
		if c and overlaps(u, c) then
			truthy(inside(u, c), string.format("%s: where it covers the chip it lies inside the chip (card %s, chip %s)", where, span(u), span(c)))
		end
		truthy(cr.sh >= MIN_TITLE_H, string.format("%s: its title is at least %d px tall (%.0f)", where, MIN_TITLE_H, cr.sh))
	end
end
-- and with each drawer open (on a phone they hang where a card could go)
for _, d in DRAWERS do
	local toggle = root:FindFirstChild(d.toggle)
	toggle.Activated:Fire()
	h:advance(0.1)
	for _, v in VIEWPORTS do
		local top, byObj = measure(v)
		local fr = top[d.frame]
		local cr, sr = byObj[card], byObj[sub]
		if fr and fr.shown and cr and sr then
			local u = union(cr, sr)
			truthy(not overlaps(u, fr), string.format("[%s %dx%d] band card with the %s open: it never covers the drawer (card %s, drawer %s)",
				v.name, v.w, v.h, d.frame, span(u), span(fr)))
		end
	end
	toggle.Activated:Fire()
	h:advance(0.1)
end
showCard(false)

--======================================================================= D: climbing on a landscape phone

-- OWNER DECISION, 2026-09-30 ("take the recommended option for all"; EYECANDY.md §10 items 22 and 23). On
-- a landscape phone the inscription panel, centred just above the character, hid 64-74 % of a hazard's
-- flight frames at pitch -15/-30 (review 2026-09-24), and the server's toast covered the character's
-- head for 3.5 s after every notice. The inscription only matters at a fork, and hazards fly only while
-- the player climbs a section. So while the player climbs, on a landscape phone (the layout is compact
-- and wider than tall), the inscription is not drawn and the toast takes its slot, above the character.
-- At a fork both are back where they were: nothing the read needs is ever hidden.
do
	local Hazards = h:_require(h.ReplicatedStorage:FindFirstChild("Hazards"))
	local remotes = h.ReplicatedStorage:FindFirstChild("ForkRemotes")
	local lane = nil
	for _, f in h.workspace:FindFirstChild("Towers"):GetChildren() do
		if f:GetAttribute("Owner") == player.UserId then lane = f end
	end
	truthy(lane ~= nil, "D set-up: the player has a lane")
	-- floor 1's door, unread (a guess): the server puts the player on the section, stage "climb"
	lane:FindFirstChild("Fork_1"):FindFirstChild("Door_1_1"):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
	h:advance(0.3)
	truthy(lane:FindFirstChild("Section_1") ~= nil, "D set-up: the player is climbing floor 1's section")
	local function landscapePhone(v)
		return (v.w < 900 or v.h - INSET < 500) and v.w > v.h
	end
	-- the hazards' own flights, as the default camera draws them (the reviewer's measurement, 2026-09-24)
	local st = 12345
	local function rand() st = (1664525 * st + 1013904223) % 4294967296; return st / 4294967296 end
	local kinds = {}
	for k in Config.Hazards.Kinds do table.insert(kinds, k) end
	table.sort(kinds)
	local function screenOf(v, pitchDeg, p)
		local r = project(v, pitchDeg, { Vector3.new(p.x, p.y, p.z) })
		return r.sx, r.sy
	end
	local landscapes, worstShare, strikeHidden = 0, 0, 0
	local shareOf = {} -- viewport -> the worst share of a flight behind the HUD over the three pitches
	for _, v in VIEWPORTS do
		local top, byObj = measure(v)
		local where = string.format("[%s %dx%d] climbing", v.name, v.w, v.h)
		local rule = top.Rule
		if landscapePhone(v) then
			landscapes += 1
			truthy(rule == nil or not rule.shown, where .. ": on a landscape phone the inscription is not drawn while climbing")
			local toast = top.Toast
			truthy(toast ~= nil, where .. ": set-up: the toast's slot is measured")
			if toast then
				for _, box in playBoxes(v) do
					-- in the inscription's slot it inherits the inscription's one bounded exception on the
					-- short phones (above: never lower than y 138.5, the crown of a tall avatar's head)
					local bound = HEAD_OVERLAP[v.name] and HEAD_OVERLAP[v.name].Rule
					if overlaps(toast, box.r) and bound ~= nil and toast.sy + toast.sh <= bound then
						exceptionsSeen[string.format("%s Toast (in the inscription's slot) ends at y %.0f, box top %.0f", where, toast.sy + toast.sh, box.r.sy)] = true
					else
						truthy(not overlaps(toast, box.r), string.format("%s: the toast's slot keeps off %s (%s, %s)", where, box.what, span(toast), span(box.r)))
					end
				end
			end
			-- what still stands between the player and a hazard's flight: every always-on panel
			-- (the AmbienceRow frame itself is a transparent container: what it draws is the chip and the button)
			local rects = {}
			for name, r in top do
				if r.shown and not TRANSIENT[name] and name ~= "AmbienceRow" and r.sw > 1 and r.sh > 1 then table.insert(rects, r) end
			end
			for _, o in { chip, restBtn } do
				local r = byObj[o]
				if r and r.shown then table.insert(rects, r) end
			end
			local function hidden(x, y)
				for _, r in rects do
					if x >= r.sx and x <= r.sx + r.sw and y >= r.sy and y <= r.sy + r.sh then return true end
				end
				return false
			end
			for _, pitch in PITCHES do
				local frames, behind = 0, 0
				for i = 1, 160 do
					local plan = Hazards.plan(Config.Hazards, kinds[1 + (i - 1) % #kinds], { x = 0, y = 0, z = 0 }, 0, rand, math.rad(pitch))
					local t = 0
					while t <= plan.arriveAt + 1e-9 do
						local x, y = screenOf(v, pitch, Hazards.positionAt(plan, t))
						frames += 1
						if hidden(x, y) then behind += 1 end
						t += 1 / 30
					end
					local ix, iy = screenOf(v, pitch, Hazards.positionAt(plan, plan.arriveAt))
					if hidden(ix, iy) then strikeHidden += 1 end
				end
				worstShare = math.max(worstShare, behind / frames)
				shareOf[where] = math.max(shareOf[where] or 0, behind / frames)
			end
		else
			truthy(rule ~= nil and rule.shown, where .. ": everywhere else the inscription stays where it is")
		end
	end
	local list = {}
	for w, sh in shareOf do table.insert(list, string.format("%s %.0f%%", w, 100 * sh)) end
	table.sort(list)
	print(string.format("  climbing on %d landscape phone viewports, the share of a hazard's flight frames behind the HUD (worst of 3 pitches, 160 flights each): %s; strike point hidden %d times",
		landscapes, table.concat(list, ", "), strikeHidden))
	truthy(landscapes >= 8, string.format("D set-up: the landscape phones were among those measured (%d)", landscapes))
	truthy(strikeHidden == 0, string.format("climbing on a landscape phone, no hazard's strike point is ever behind the HUD (%d)", strikeHidden))
	-- the phones the review measured (64-74 % behind the inscription on 800x360) and the iPhone SE
	for _, name in { "phone landscape", "small phone", "phone landscape 844", "phone landscape 926", "iPhone SE landscape" } do
		for w, sh in shareOf do
			if string.find(w, "[" .. name .. " ", 1, true) == 1 then
				truthy(sh <= 0.15, string.format("%s: at most 15 %% of any hazard's flight is behind the HUD while climbing (%.0f %%)", w, 100 * sh))
			end
		end
	end
	truthy(worstShare < 0.5, string.format("and on every landscape viewport, less than half of any flight (worst %.0f %%, a 480x270 screen, behind the band chip in the header)", 100 * worstShare))
	-- back at a fork (a rebirth puts the player on floor 1's pad): the inscription is back
	remotes:FindFirstChild("Rebirth"):simulateFireServer(player)
	h:advance(0.5)
	for _, v in VIEWPORTS do
		if landscapePhone(v) then
			local top = measure(v)
			truthy(top.Rule ~= nil and top.Rule.shown, string.format("[%s %dx%d] at a fork the inscription is drawn again", v.name, v.w, v.h))
		end
	end
end

local notes = {}
for w in toastOverAvatar do table.insert(notes, w) end
table.sort(notes)
print("  report only (pre-existing, not asserted): the server's toast, shown 3.5 s after a notice, overlaps the avatar at: "
	.. (if #notes > 0 then table.concat(notes, ", ") else "none"))
local ex = {}
for w in exceptionsSeen do table.insert(ex, w) end
table.sort(ex)
print("  the bounded pre-existing exception, where it applied: " .. (if #ex > 0 then table.concat(ex, "; ") else "nowhere"))

truthy(#h:errors() == 0, "no script errors (" .. table.concat(h:errors(), " | ") .. ")")
print(string.format("fork tower hud play: %d passed, %d failed", passed, failed))
if failed > 0 then error("fork tower hud play check failed", 0) end
