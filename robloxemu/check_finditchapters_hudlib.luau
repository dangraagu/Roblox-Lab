-- Find It! Chapters: headless HUD fit check, panel-overlap rule ON (docs/complete-game-standard.md §2).
-- The sweep itself. Run it through check_finditchapters_hud.luau (inset 36) and check_finditchapters_hud58.luau
-- (inset 58): the harness installs once per process, so each inset is its own CLI run.
--
-- Most of this HUD is built by remote handlers (the chips, the cards, the menu), so an idle sweep would measure
-- almost nothing (hudcheck's own header: the anomaly tint-swatch lesson). Every viewport is measured in FOURTEEN
-- modes, each put in place by a `before` hook that pushes what the server pushes: the hub (a new player's hint),
-- the Case Book menu (all 15 chapters and the Daily, the stars toward the Gold Book, the streak), the menu with a
-- locked row's words, the menu while the profile is still loading (REVIEW-1 round 2 C3), a live room with 9 chips
-- (chapter 15, the worst case, built by the game's own Dressing), a selected prop and the Leave button (round 2 D1),
-- the intro card, two clear cards, the callout over a chip, the paused card with its break countdown, the BREAK OVER
-- card (round 2 C2), the GOLD BOOK card (round 2 D6), a hazard banner with a selection, and the BOOK ONE SOLVED card.
-- Each hook also checks that every shown control lies inside its own panel (hudcheck does not measure spills).

local HudCheck = require("./emu/hudcheck")


local W = {}

local function setup(h, player)
	local RS = h.ReplicatedStorage
	local function mod(name) return h:_require(RS:FindFirstChild(name)) end
	local Config, Dressing, Rng, Clue = mod("Config"), mod("Dressing"), mod("Rng"), mod("Clue")
	W.Bus = mod("ClientBus")
	W.Config = Config
	local r = Rng.new(2026)
	local spec = Dressing.spec("book", 15, Config)
	local room = Dressing.build(spec, function() return r:next() end, Config)
	local items = { "key", "duck", "teacup", "coin", "gem", "toycar", "starmap", "moonrock", "planet" }
	local payload = Dressing.payload(room, items, 5, Config)
	payload.origin = { 0, 0, -240 }
	payload.attemptId = 1
	W.payload = payload
	W.firstProp = payload.props[1]
	W.label = Clue.label(payload.props[1], Config)
	local remotes = RS:FindFirstChild("FindItRemotes")
	W.R = function(n) return remotes:FindFirstChild(n) end
	local stars = {}
	for ch = 1, 14 do stars["c" .. ch] = { f = true, w = ch % 2 == 0, s = ch % 3 == 0 } end
	W.profileFull = { cleared = 14, stars = stars, solved = 20, totalStars = 30, continue = 15, dailyOpen = true, dailySolvedToday = false,
		dailySolved = 6, streak = 3, bestStreak = 4, title = nil, caseNumber = 12, bookSolved = false, canSave = true, loaded = true, state = "ready" }
	W.profileNew = { cleared = 0, stars = {}, solved = 0, totalStars = 0, continue = 1, dailyOpen = false, dailySolvedToday = false,
		dailySolved = 0, streak = 0, bestStreak = 0, caseNumber = 1, bookSolved = false, canSave = true, loaded = true, state = "ready" }
	local found = {}
	for i = 1, 9 do found[i] = i <= 3 end
	W.state = function(over)
		local s = { where = "room", kind = "book", chapter = 15, band = 5, progress = 15, n = 9, items = items, state = "live", clock = 42,
			limit = 285, looks = 40, found = found, hintUsed = false, searching = false, origin = { 0, 0, -240 }, attemptId = 1, W = 48, D = 38,
			introText = string.format(Config.Text.Intro, 9) }
		for k, v in over or {} do s[k] = v end
		return s
	end
end

local function hub(h, player, menuOpen)
	W.R("State"):FireClient(player, { where = "hub" })
	W.R("Profile"):FireClient(player, if menuOpen then W.profileFull else W.profileNew)
	W.Bus.fire("hazard", { active = false })
	if menuOpen then W.R("Notice"):FireClient(player, { kind = "casebook" }) end
end

local function inRoom(h, player, over)
	W.R("Profile"):FireClient(player, W.profileFull)
	W.R("State"):FireClient(player, { where = "hub" })
	W.R("Room"):FireClient(player, W.payload)
	W.R("State"):FireClient(player, W.state(over))
	W.Bus.fire("hazard", { active = false })
end

local function hudRoot(player)
	return player.PlayerGui:FindFirstChild("FindItHud"):FindFirstChild("Root")
end
local function shown(player, name)
	local f = hudRoot(player):FindFirstChild(name)
	return f and f.Visible
end

local MODES = {
	{ name = "hub, new player", before = function(h, player)
		hub(h, player, false)
		local banner = hudRoot(player):FindFirstChild("Banner")
		assert(banner.Visible and string.find(banner:FindFirstChild("Text").Text, "Case Book", 1, true), "the hub's first hint is not showing")
	end },
	{ name = "case book menu", before = function(h, player)
		hub(h, player, true)
		assert(shown(player, "Menu"), "the Case Book menu did not open")
		assert(hudRoot(player):FindFirstChild("Chapter_15", true), "the menu has no chapter 15 row")
		assert(hudRoot(player):FindFirstChild("Daily", true), "the menu has no Daily row")
		-- REVIEW-1 round 2 D6: the long-term goals are on show: the stars toward the Gold Book, the Daily streak
		local title = hudRoot(player):FindFirstChild("Menu"):FindFirstChild("Title").Text
		assert(string.find(title, "30/45", 1, true), "D6: the menu title does not show the stars toward the Gold Book: " .. title)
		local daily = hudRoot(player):FindFirstChild("Daily", true).Text
		assert(string.find(daily, "streak 3", 1, true) and string.find(daily, "best 4", 1, true), "D6: the Daily row does not show the streak: " .. daily)
	end },
	-- REVIEW-1 round 2 C3: a hopper whose load still waits on the old server's lock sees a loading Case Book, never
	-- "Continue: Chapter 1"; when the load lands, the open menu is rebuilt with the real book
	{ name = "case book menu, still loading", before = function(h, player)
		hub(h, player, false)
		local p = table.clone(W.profileNew)
		p.state, p.canSave = "locked", false
		W.R("Profile"):FireClient(player, p)
		W.R("Notice"):FireClient(player, { kind = "casebook" })
		h:advance(0.05)
		assert(shown(player, "Menu"), "the Case Book menu did not open")
		local cont = hudRoot(player):FindFirstChild("Continue", true)
		assert(cont and string.find(string.lower(cont.Text), "loading", 1, true) and not string.find(cont.Text, "Chapter", 1, true),
			"C3: a still-loading Case Book offers: " .. tostring(cont and cont.Text))
		W.R("Profile"):FireClient(player, W.profileFull)
		h:advance(0.05)
		cont = hudRoot(player):FindFirstChild("Continue", true)
		assert(cont and string.find(cont.Text, "Chapter 15", 1, true), "C3: once loaded, the open menu shows the real book: " .. tostring(cont and cont.Text))
		W.R("Profile"):FireClient(player, p)
		h:advance(0.05)
	end },
	-- the menu with a refusal showing: a tapped locked row puts its words in the banner beside the open menu
	{ name = "case book menu, a locked row", before = function(h, player)
		hub(h, player, true)
		local p = table.clone(W.profileFull)
		p.cleared, p.continue, p.dailyOpen = 3, 4, true
		W.R("Profile"):FireClient(player, p)
		W.R("Notice"):FireClient(player, { kind = "casebook" })
		h:advance(0.05)
		local row = hudRoot(player):FindFirstChild("Chapter_9", true)
		assert(row, "the menu has no chapter 9 row")
		row.Activated:Fire()
		h:advance(0.05)
		assert(shown(player, "Menu"), "the menu closed on a locked row")
		local banner = hudRoot(player):FindFirstChild("Banner")
		assert(banner.Visible and string.find(banner:FindFirstChild("Text").Text, "Clear Chapter 4", 1, true),
			"the locked row's words are not in the banner: " .. tostring(banner:FindFirstChild("Text").Text))
	end },
	{ name = "room live, selected", before = function(h, player)
		inRoom(h, player, {})
		W.Bus.fire("select", { id = W.firstProp.id, label = W.label, inReach = true })
		assert(shown(player, "SelectionBar"), "the selection bar is not showing")
		assert(hudRoot(player):FindFirstChild("ListPanel"):FindFirstChild("Chip_9"), "9 chips are not there")
		assert(shown(player, "PauseButton") and shown(player, "ClockPanel"), "the clock or the pause button is missing")
		-- REVIEW-1 round 2 D1: a live room has its own way out
		assert(shown(player, "LeaveButton"), "D1: a live room shows no Leave button")
	end },
	{ name = "intro card", before = function(h, player)
		inRoom(h, player, { state = "intro", intro = 3 })
		assert(shown(player, "Card"), "the intro card is not showing")
	end },
	{ name = "clear card", before = function(h, player)
		inRoom(h, player, { state = "done", result = { reason = "found", stars = { f = true, w = true, s = false }, saving = false, first = true, solved = 15, n = 9, foundCount = 9 } })
		assert(shown(player, "Card"), "the clear card is not showing")
		assert(hudRoot(player):FindFirstChild("NextButton", true).Visible == false, "chapter 15 has no Next")
	end },
	{ name = "clear card ch 4", before = function(h, player)
		inRoom(h, player, { chapter = 4, band = 2, state = "done", result = { reason = "found", stars = { f = true, w = false, s = true }, saving = false, first = true, solved = 4, n = 9, foundCount = 9 } })
		assert(hudRoot(player):FindFirstChild("NextButton", true).Visible, "Next is not showing")
	end },
	{ name = "callout", before = function(h, player)
		inRoom(h, player, {})
		local chip = hudRoot(player):FindFirstChild("ListPanel"):FindFirstChild("Chip_5")
		chip.Activated:Fire()
		assert(shown(player, "Callout"), "the callout did not open")
	end },
	{ name = "paused card", before = function(h, player)
		inRoom(h, player, { state = "paused", breakLeft = 540 })
		assert(shown(player, "Card"), "the paused card is not showing")
		assert(hudRoot(player):FindFirstChild("ResumeButton", true).Visible, "Resume is not showing")
		-- REVIEW-1 round 2 C2: the break is capped, and the card says how much is left
		local sub = hudRoot(player):FindFirstChild("Card"):FindFirstChild("Sub").Text
		assert(string.find(sub, "9:00", 1, true), "C2: the paused card does not say how much break is left: " .. sub)
	end },
	{ name = "break over card", before = function(h, player)
		inRoom(h, player, { state = "done", result = { reason = "break", stars = { f = false, w = false, s = false }, saving = false, n = 9, foundCount = 3 } })
		assert(shown(player, "Card"), "C2: the room-closed card is not showing")
		local title = hudRoot(player):FindFirstChild("Card"):FindFirstChild("Title").Text
		assert(title == W.Config.Text.BreakOver, "C2: the room-closed card's title: " .. title)
		assert(hudRoot(player):FindFirstChild("RetryButton", true).Visible and hudRoot(player):FindFirstChild("HubButton", true).Visible, "C2: Retry and Hub")
	end },
	{ name = "gold book card", before = function(h, player)
		inRoom(h, player, { chapter = 9, band = 3, state = "done", result = { reason = "found", stars = { f = true, w = true, s = true }, saving = false, first = false, goldBook = true, solved = 20, n = 9, foundCount = 9 } })
		assert(shown(player, "Card"), "D6: the Gold Book card is not showing")
		local sub = hudRoot(player):FindFirstChild("Card"):FindFirstChild("Sub").Text
		assert(string.find(sub, "GOLD BOOK", 1, true), "D6: the card does not celebrate the Gold Book: " .. sub)
	end },
	{ name = "hazard banner", before = function(h, player)
		inRoom(h, player, {})
		W.Bus.fire("select", { id = W.firstProp.id, label = W.label, inReach = false })
		W.Bus.fire("hazard", { active = true, text = "\u{26A0} METEORITE PEBBLE - STEP OUT OF THE RING", clear = false })
		local banner = hudRoot(player):FindFirstChild("Banner")
		assert(banner.Visible and string.find(banner:FindFirstChild("Text").Text, "PEBBLE", 1, true), "the hazard banner is not showing")
	end },
	{ name = "book solved", before = function(h, player)
		inRoom(h, player, { state = "done", result = { reason = "found", stars = { f = true, w = true, s = true }, saving = false, first = true, bookSolved = true, solved = 15, n = 9, foundCount = 9 } })
		assert(shown(player, "Card"), "the brag card is not showing")
	end },
}

-- every shown control inside its own panel (1 px slack); rows inside a ScrollingFrame scroll, so only the frame counts
local spills, measured = {}, 0
local menuShort, menuMeasured = {}, 0
local PANELS = { "Card", "Callout", "Menu", "SelectionBar", "ListPanel", "ClockPanel", "ChapterChip", "Banner" }
local function contained(h, player, v, label)
	local gui = player.PlayerGui:FindFirstChild("FindItHud")
	local rects = h:guiRects(gui, v.w, v.h)
	for _, pname in PANELS do
		local pr = nil
		for _, r in rects do if r.name == pname and r.depth == 2 then pr = r end end
		if pr and pr.shown then
			for _, r in rects do
				if r.shown and r.obj ~= pr.obj and r.obj:IsDescendantOf(pr.obj) then
					local inScroll = false
					local node = r.obj.Parent
					while node and node ~= pr.obj do
						if node.ClassName == "ScrollingFrame" then inScroll = true end
						node = node.Parent
					end
					if not inScroll then
						measured += 1
						if r.sx < pr.sx - 1 or r.sy < pr.sy - 1 or r.sx + r.sw > pr.sx + pr.sw + 1 or r.sy + r.sh > pr.sy + pr.sh + 1 then
							table.insert(spills, string.format("[%s] %s spills out of %s: x %.0f..%.0f y %.0f..%.0f, panel x %.0f..%.0f y %.0f..%.0f",
								label, r.name, pname, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh, pr.sx, pr.sx + pr.sw, pr.sy, pr.sy + pr.sh))
						end
					end
				end
			end
		end
	end
	-- REVIEW-1 B3: the Case Book list shows at least three whole rows, the first (Continue) whole; on a touch screen the
	-- row is >= 44 px (a mouse row may be smaller: hudcheck asks 44 px of touch targets only)
	if string.find(label, "case book menu", 1, true) then
		local list, first = nil, nil
		for _, r in rects do
			if r.name == "List" and r.obj.ClassName == "ScrollingFrame" then list = r end
			if r.name == "Continue" then first = r end
		end
		menuMeasured += 1
		if list == nil or first == nil then
			table.insert(menuShort, string.format("[%s] the menu list or its Continue row was not measured", label))
		else
			local rows = list.sh / (first.sh + 6 * first.sh / math.max(1, first.obj.Size.Y.Offset))
			if (v.touch and first.sh < 44) or first.sy < list.sy - 1 or first.sy + first.sh > list.sy + list.sh + 1 or rows < 3 then
				table.insert(menuShort, string.format("[%s] the Case Book list window is %.0f px: %.2f rows of %.0f px (Continue y %.0f..%.0f, list y %.0f..%.0f)",
					label, list.sh, rows, first.sh, first.sy, first.sy + first.sh, list.sy, list.sy + list.sh))
			end
		end
	end
end

-- REVIEW-1 B4: the HUD must read the topbar inset (GuiService:GetGuiInset) rather than assume 36 px. The emulator's
-- 36 px is one run; 58 px (the inset the reviewer measured siblings at) is another, with GetGuiInset and the gate's
-- own geometry (Harness.GUI_INSET_Y) both moved.
local Harness = require("./emu/harness")
return function(inset: number)
	local viewports = {}
	for _, mode in MODES do
		for _, v in HudCheck.VIEWPORTS do
			local entry = { name = string.format("%s / %s / inset %d", v.name, mode.name, inset), w = v.w, h = v.h, touch = v.touch }
			entry.before = function(h, player)
				mode.before(h, player)
				h:advance(0.05)
				contained(h, player, v, entry.name)
			end
			table.insert(viewports, entry)
		end
	end
	Harness.GUI_INSET_Y = inset
	local insetRead = nil
	local ok, err = pcall(HudCheck.run, {
		overlap = true,
		game = "find-it-chapters",
		bundle = require("./build/find-it-chapters"),
		server = "server/Main.server",
		clients = { "client/Hud.client", "client/Room.client", "client/Board.client" },
		warmup = function(h, player)
			local vec2 = h.instance.datatypes.Vector2
			local gs = h.game:GetService("GuiService")
			rawset(gs, "GetGuiInset", function() return vec2.new(0, inset), vec2.new(0, 0) end)
			local a = gs:GetGuiInset()
			insetRead = a and a.Y
			setup(h, player)
		end,
		viewports = viewports,
	})
	print(string.format("find-it-chapters HUD (inset %d): %d viewport x mode measurements; %d panel controls checked for containment, %d spill; %d Case Book menus measured, %d too short",
		inset, #viewports, measured, #spills, menuMeasured, #menuShort))
	for _, c in spills do print("   " .. c) end
	for _, c in menuShort do print("   " .. c) end
	if not ok then print("   " .. tostring(err)) end
	if insetRead ~= inset then error(string.format("CONTROL: GuiService:GetGuiInset() read %s, want %d", tostring(insetRead), inset), 0) end
	if not ok or #spills > 0 or #menuShort > 0 then error("find-it-chapters HUD: a hudcheck rule, a spill or a short Case Book list", 0) end
	if measured < 1000 then error("CONTROL: only " .. measured .. " panel controls were measured; the containment sweep saw too little", 0) end
	if menuMeasured < #HudCheck.VIEWPORTS then error("CONTROL: only " .. menuMeasured .. " Case Book menus were measured", 0) end
	print(string.format("PASS (inset %d)", inset))
end
