-- FIND IT! CHAPTERS: the phone-first HUD (StarterPlayerScripts). Display and buttons only: every decision is the
-- server's. DESIGN.md §17. docs/new-game-checklist.md §2b: a root Frame owns the UIScale and is sized 1/scale,
-- the layout is redone on ViewportSize and TouchEnabled, tap targets are >= 44 SCREEN px, nothing tappable sits
-- under the thumbstick (bottom-left) or the jump button (bottom-right), and no two visible panels overlap
-- (robloxemu/check_finditchapters_hud.luau runs hudcheck with overlap = true).
--
-- Layout (screen px, computed per viewport, then divided by the scale):
--   top row:  ChapterChip (left, not tappable) | ClockPanel (centre: clock + looks) | LeaveButton | PauseButton (right,
--             in a room; Leave takes two taps: REVIEW-1 round 2 D1)
--   ListPanel: one chip per item (tap: the callout with the clue in words and Hint), wrapping to rows
--   Banner:   the hazard warning, else the latest toast
--   Card / Callout / Menu: one centre slot, one at a time; their buttons sit in the thumb-free middle column
--   SelectionBar: the selected prop's label and Search, bottom centre between the thumbs (hidden under a card)
-- Hud.client is the only script on the remotes; it forwards every payload to Room.client over ClientBus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local Clue = require(ReplicatedStorage:WaitForChild("Clue"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local ClientBus = require(ReplicatedStorage:WaitForChild("ClientBus"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("FindItRemotes")
local function R(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local T = Config.Text
local GOLD = Color3.fromRGB(Config.Reserved.Gold[1], Config.Reserved.Gold[2], Config.Reserved.Gold[3])
local INK = Color3.fromRGB(46, 34, 24)
local PAPER = Color3.fromRGB(252, 244, 226)
local PANEL = Color3.fromRGB(40, 32, 26)

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

--============================================================================ the root
local gui = Instance.new("ScreenGui")
gui.Name = "FindItHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function frame(name: string, parent: Instance, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color or PANEL
	f.BackgroundTransparency = transparency or 0.15
	f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = f
	return f
end

local function text(name: string, parent: Instance, t: string, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = t
	l.TextScaled = true
	l.TextWrapped = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or PAPER
	l.Parent = parent
	return l
end

local function button(name: string, parent: Instance, t: string, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = t
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = INK
	b.BackgroundColor3 = color or PAPER
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b
	return b
end

-- panels (children of the scaling root: hudcheck's depth 2)
local chapterChip = frame("ChapterChip", root)
local chapterText = text("Text", chapterChip, "Find It! Chapters")
local clockPanel = frame("ClockPanel", root)
local clockText = text("Clock", clockPanel, "0:00")
local looksText = text("Looks", clockPanel, "")
local pauseButton = button("PauseButton", root, "II")
-- REVIEW-1 round 2 D1: a live room's own way out (two taps: the first arms it and says what leaving costs)
local leaveButton = button("LeaveButton", root, "Leave")
local listPanel = frame("ListPanel", root, PANEL, 0.35)
local banner = frame("Banner", root, Color3.fromRGB(30, 24, 20), 0.2)
local bannerText = text("Text", banner, "")
local card = frame("Card", root, PAPER, 0.02)
local cardTitle = text("Title", card, "", INK)
local cardSub = text("Sub", card, "", INK)
local cardStars = text("Stars", card, "", Color3.fromRGB(140, 96, 20))
local cardButtons = Instance.new("Frame")
cardButtons.Name = "Buttons"
cardButtons.BackgroundTransparency = 1
cardButtons.Parent = card
local nextButton = button("NextButton", cardButtons, "Next", Color3.fromRGB(255, 226, 140))
local retryButton = button("RetryButton", cardButtons, "Retry")
local hubButton = button("HubButton", cardButtons, "Hub")
local resumeButton = button("ResumeButton", cardButtons, "Resume", Color3.fromRGB(190, 230, 200))
local callout = frame("Callout", root, PAPER, 0.02)
local calloutText = text("Clue", callout, "", INK)
local calloutButtons = Instance.new("Frame")
calloutButtons.Name = "Buttons"
calloutButtons.BackgroundTransparency = 1
calloutButtons.Parent = callout
local hintButton = button("HintButton", calloutButtons, "Hint", Color3.fromRGB(255, 226, 140))
local closeCallout = button("CloseCallout", calloutButtons, "OK")
local selectBar = frame("SelectionBar", root, PANEL, 0.1)
local selectLabel = text("Label", selectBar, "")
local searchButton = button("SearchButton", selectBar, "Search", Color3.fromRGB(255, 236, 170))
local menu = frame("Menu", root, PAPER, 0.02)
local menuTitle = text("Title", menu, "THE CASE BOOK", INK)
local menuList = Instance.new("ScrollingFrame")
menuList.Name = "List"
menuList.BackgroundTransparency = 1
menuList.BorderSizePixel = 0
menuList.ScrollBarThickness = 6
menuList.Parent = menu
local menuLayout = Instance.new("UIListLayout")
menuLayout.Padding = UDim.new(0, 6)
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.Parent = menuList
local menuClose = button("CloseMenu", menu, "Close")

FxClient.theme(chapterChip)
FxClient.theme(clockPanel)

--============================================================================ state
local where = "hub"
local state: any = nil
local profile: any = nil
local roomPayload: any = nil
local foundShown: { [number]: boolean } = {}
local selected: any = nil
local hazardMsg: any = nil
local toastMsg: string? = nil
local toastUntil = 0
local now = 0
local restState = { resting = false, pending = false }
local calloutItem: number? = nil
local menuOpen = false
local stateAt = 0
local chips: { TextButton } = {}

local function bandName(i: number?): string
	local b = i and Config.Env.Bands[i]
	return if b then b.name else ""
end

local function fmtClock(sec: number): string
	sec = math.max(0, math.ceil(sec - 1e-6))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function starLine(st: any): string
	if st == nil then return "" end
	local function s(on: boolean?, name: string): string
		return (if on then "\u{2605} " else "\u{2606} ") .. name
	end
	return s(st.f, "Found") .. "   " .. s(st.w, "Swift") .. "   " .. s(st.s, "Sharp Eye")
end

--============================================================================ layout (screen px -> design px)
local layout = Responsive.layout(1280, 720, false)
local L: any = {}

local function place(f: GuiObject, x: number, y: number, w: number, h: number)
	local s = layout.scale
	f.Position = UDim2.fromOffset(x / s, y / s)
	f.Size = UDim2.fromOffset(w / s, h / s)
end

local function chipCount(): number
	return if state and state.n then state.n else 0
end

-- REVIEW-1 B4: the ScreenGui (IgnoreGuiInset = false) starts below Roblox's topbar, whose height is not a constant
-- (36 px on the old topbar, 58 px on the current one). Read it; 36 only if the engine gives nothing usable.
local function topInset(): number
	local ok, a = pcall(function() return GuiService:GetGuiInset() end)
	local y = if ok and a ~= nil then (a :: any).Y else nil
	if type(y) == "number" and y >= 0 and y < 200 then return y end
	return 36
end

local function relayout()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local touch = UserInputService.TouchEnabled
	local V, VH = vp.X, vp.Y
	local inset = topInset()
	local H = VH - inset
	layout = Responsive.layout(V, VH, touch)
	local s = layout.scale
	uiScale.Scale = s
	root.Size = UDim2.fromOffset(V / s, H / s)
	local m = 8
	local tap = if touch then math.max(48, 60 * s) else math.max(34, 52 * s)
	local band = H - layout.controlPad -- usable-space y where the thumb zones begin (touch)
	local midL, midR = 0.35 * V + m, 0.75 * V - m
	L = { V = V, H = H, m = m, tap = tap, band = band, midL = midL, midR = midR, touch = touch }

	-- top row
	local chipW = math.min(0.3 * V, 300 * s)
	place(chapterChip, m, m, chipW, tap)
	chapterText.Position = UDim2.fromScale(0.05, 0.12)
	chapterText.Size = UDim2.fromScale(0.9, 0.76)
	place(pauseButton, V - m - tap, m, tap, tap)
	place(leaveButton, V - m - tap - m - tap, m, tap, tap)
	local clockX0 = m + chipW + m
	local clockX1 = V - m - tap - m - tap - m
	local clockW = math.min(clockX1 - clockX0, 300 * s)
	place(clockPanel, (clockX0 + clockX1) / 2 - clockW / 2, m, clockW, tap)
	clockText.Position = UDim2.fromScale(0.04, 0.08)
	clockText.Size = UDim2.fromScale(0.5, 0.84)
	looksText.Position = UDim2.fromScale(0.55, 0.15)
	looksText.Size = UDim2.fromScale(0.42, 0.7)

	-- the list of chips
	local y = m + tap + m
	local n = chipCount()
	local c, g = tap, 6
	local perRow = math.max(1, math.floor((V - 2 * m + g) / (c + g)))
	local rows = if n > 0 then math.ceil(n / perRow) else 0
	local cols = math.min(n, perRow)
	local listW = math.max(c, cols * (c + g) - g + 8)
	local listH = math.max(c, rows * (c + g) - g + 8)
	place(listPanel, V / 2 - listW / 2, y, listW, listH)
	for i, chip in chips do
		local r0 = math.floor((i - 1) / perRow)
		local c0 = (i - 1) % perRow
		local inRow = math.min(perRow, n - r0 * perRow)
		local rowW = inRow * (c + g) - g
		local x0 = (listW - rowW) / 2
		chip.Position = UDim2.fromOffset((x0 + c0 * (c + g)) / s, (4 + r0 * (c + g)) / s)
		chip.Size = UDim2.fromOffset(c / s, c / s)
	end
	local listBottom = if where == "room" and listPanel.Visible then y + listH else m + tap
	-- the banner
	local bannerH = math.max(30, 0.7 * tap)
	local bannerW = math.min(V - 2 * m, 640 * s)
	local by = listBottom + m
	place(banner, V / 2 - bannerW / 2, by, bannerW, bannerH)
	bannerText.Position = UDim2.fromScale(0.03, 0.1)
	bannerText.Size = UDim2.fromScale(0.94, 0.8)
	local slotTop = by + bannerH + m
	-- the centre slot: Card, Callout, Menu (one at a time). Buttons live in the middle column.
	local slotBottom = H - m
	local wideW = math.min(V - 2 * m, 620 * s)
	local narrowW = math.max(midR - midL, 3 * tap + 24)
	local slotW = wideW
	if touch and slotBottom > band then
		-- either stay above the thumb zones, or go narrow (the middle column) and use the full height
		if band - m - slotTop >= 220 then
			slotBottom = band - m
		else
			slotW = math.min(wideW, narrowW)
		end
	end
	local slotH = math.max(tap * 2, slotBottom - slotTop)
	local slotX = V / 2 - slotW / 2
	if touch and slotW < wideW then slotX = (midL + midR) / 2 - slotW / 2 end
	local cardH = math.min(slotH, math.max(3.4 * tap, 300 * s))
	place(card, slotX, slotTop, slotW, cardH)
	cardTitle.Position = UDim2.fromScale(0.05, 0.04)
	cardTitle.Size = UDim2.fromScale(0.9, 0.26)
	cardSub.Position = UDim2.fromScale(0.05, 0.31)
	cardSub.Size = UDim2.fromScale(0.9, 0.26)
	cardStars.Position = UDim2.fromScale(0.05, 0.58)
	cardStars.Size = UDim2.fromScale(0.9, 0.12)
	local btnH = tap
	cardButtons.Position = UDim2.fromOffset(0, (cardH - btnH - 6) / s)
	cardButtons.Size = UDim2.fromOffset(slotW / s, btnH / s)
	local shownButtons = {}
	for _, b in { nextButton, retryButton, hubButton, resumeButton } do
		if b.Visible then table.insert(shownButtons, b) end
	end
	local bw = math.min((slotW - 12 - 6 * (#shownButtons - 1)) / math.max(1, #shownButtons), 160 * math.max(s, 0.6))
	bw = math.max(bw, tap)
	local totalW = #shownButtons * bw + (#shownButtons - 1) * 6
	for i, b in shownButtons do
		b.Position = UDim2.fromOffset(((slotW - totalW) / 2 + (i - 1) * (bw + 6)) / s, 0)
		b.Size = UDim2.fromOffset(bw / s, btnH / s)
	end
	local callH = math.min(slotH, math.max(2.6 * tap, 200 * s))
	place(callout, slotX, slotTop, slotW, callH)
	calloutText.Position = UDim2.fromScale(0.05, 0.06)
	calloutText.Size = UDim2.fromScale(0.9, 0.5)
	calloutButtons.Position = UDim2.fromOffset(0, (callH - btnH - 6) / s)
	calloutButtons.Size = UDim2.fromOffset(slotW / s, btnH / s)
	local cbw = math.max(tap, math.min((slotW - 18) / 2, 160 * math.max(s, 0.6)))
	hintButton.Position = UDim2.fromOffset((slotW / 2 - cbw - 3) / s, 0)
	hintButton.Size = UDim2.fromOffset(cbw / s, btnH / s)
	closeCallout.Position = UDim2.fromOffset((slotW / 2 + 3) / s, 0)
	closeCallout.Size = UDim2.fromOffset(cbw / s, btnH / s)
	-- the Case Book menu (the hub only). Close sits in its title row, so the list gets the rest of the height.
	-- REVIEW-1 B3: on a narrow touch screen (the middle column) the slot under the banner held less than one row, so
	-- there the menu runs the full usable height of the middle column (clear of the chapter chip on the left; the
	-- banner moves to the left column while it is open, below). Elsewhere it takes the slot, and on a touch screen
	-- never more than 42% of the screen height (hudcheck rule 5: a phone HUD must leave the world visible).
	local chipRight = m + chipW
	local menuTall = touch and slotW < wideW and slotX >= chipRight + m
	local menuY, menuH = slotTop, slotH
	if menuTall then
		menuY, menuH = m, H - 2 * m
	elseif touch then
		menuH = math.min(slotH, 0.42 * VH)
	end
	place(menu, slotX, menuY, slotW, menuH)
	local closeW = math.max(tap, math.min(120 * math.max(s, 0.6), 0.34 * slotW))
	menuTitle.Position = UDim2.fromOffset(8 / s, 6 / s)
	menuTitle.Size = UDim2.fromOffset(math.max(10, slotW - closeW - 22) / s, tap / s)
	menuClose.Position = UDim2.fromOffset((slotW - closeW - 6) / s, 6 / s)
	menuClose.Size = UDim2.fromOffset(closeW / s, btnH / s)
	local listTop = 6 + tap + 6
	menuList.Position = UDim2.fromOffset(6 / s, listTop / s)
	menuList.Size = UDim2.fromOffset((slotW - 12) / s, math.max(tap, menuH - listTop - 6) / s)
	for _, row in menuList:GetChildren() do
		if row:IsA("TextButton") then
			row.Size = UDim2.fromOffset((slotW - 24) / s, tap / s)
		end
	end
	if menuTall and menu.Visible then
		-- the banner (a refused row's words) goes to the left column, under the chapter chip, beside the menu
		place(banner, m, m + tap + m, chipW, math.min(2 * bannerH, math.max(bannerH, H - (m + tap + m) - m)))
	end
	menuList.CanvasSize = UDim2.fromOffset(0, (menuLayout.AbsoluteContentSize.Y / s) + 8)
	-- the selection bar: bottom centre, between the thumbs
	local barW = math.min(midR - midL, 460 * s)
	if not touch then barW = math.min(V - 2 * m, 460 * s) end
	local barH = tap + 0.55 * tap + 8
	-- a short screen (a small phone under a 58 px topbar) has no room for the label above the button between the
	-- banner and the bottom edge: the label goes left of Search, in one row (hudcheck 4b, inset 58)
	local oneRow = H - m - barH < by + bannerH + m
	if oneRow then barH = tap + 8 end
	local barX = if touch then (midL + midR) / 2 - barW / 2 else V / 2 - barW / 2
	place(selectBar, barX, H - m - barH, barW, barH)
	if oneRow then
		local lw = math.floor(0.42 * barW)
		selectLabel.Position = UDim2.fromOffset(4 / s, 4 / s)
		selectLabel.Size = UDim2.fromOffset((lw - 6) / s, tap / s)
		searchButton.Position = UDim2.fromOffset(lw / s, 4 / s)
		searchButton.Size = UDim2.fromOffset((barW - lw - 4) / s, tap / s)
	else
		selectLabel.Position = UDim2.fromOffset(4 / s, 2 / s)
		selectLabel.Size = UDim2.fromOffset((barW - 8) / s, (0.55 * tap) / s)
		searchButton.Position = UDim2.fromOffset(4 / s, (0.55 * tap + 6) / s)
		searchButton.Size = UDim2.fromOffset((barW - 8) / s, tap / s)
	end
end

--============================================================================ what shows
local function setCardButtons(list: { TextButton })
	for _, b in { nextButton, retryButton, hubButton, resumeButton } do
		b.Visible = table.find(list, b) ~= nil
	end
end

local cardKind: string? = nil
local cardUntil = 0

local function showCard(kind: string?, title: string?, sub: string?, stars: string?, buttons: { TextButton }?, seconds: number?)
	cardKind = kind
	card.Visible = kind ~= nil
	if kind then
		cardTitle.Text = title or ""
		cardSub.Text = sub or ""
		cardStars.Text = stars or ""
		setCardButtons(buttons or {})
		cardUntil = if seconds then now + seconds else math.huge
		callout.Visible = false
		calloutItem = nil
	end
end

local function refresh()
	local inRoom = where == "room" and state ~= nil
	listPanel.Visible = inRoom and not card.Visible
	clockPanel.Visible = inRoom
	pauseButton.Visible = inRoom and state.state ~= "done"
	-- the paused card has its own Hub; a finished room's card has Hub
	leaveButton.Visible = inRoom and state.state ~= "done" and state.state ~= "paused"
	menu.Visible = menuOpen and not inRoom
	selectBar.Visible = inRoom and selected ~= nil and not card.Visible and not callout.Visible and state.state == "live"
	if inRoom then
		local paused = state.state == "paused" or restState.resting
		pauseButton.Text = if paused or restState.pending then "\u{25B6}" else "II"
		chapterText.Text = if state.kind == "daily" then string.format("Daily #%d \u{00B7} %s", state.case or 0, bandName(state.band))
			else string.format("Ch %d \u{00B7} %s", state.chapter or 0, bandName(state.band))
		looksText.Text = string.format("Looks %d", state.looks or 0)
	else
		local p = profile
		chapterText.Text = if p then string.format("Cases Solved %d%s", p.solved or 0, if p.title then " \u{00B7} " .. p.title else "")
			else "Find It! Chapters"
	end
	-- the banner: a hazard first, then the latest toast, then the hub's first hint
	local msg = nil
	if hazardMsg and hazardMsg.active and hazardMsg.text then
		msg = hazardMsg.text
		banner.BackgroundColor3 = if hazardMsg.clear then Color3.fromRGB(40, 70, 46) else Color3.fromRGB(120, 24, 24)
	elseif toastMsg and now < toastUntil then
		msg = toastMsg
		banner.BackgroundColor3 = Color3.fromRGB(30, 24, 20)
	elseif not inRoom and profile and (profile.cleared or 0) == 0 and not menuOpen then
		msg = T.Hint
		banner.BackgroundColor3 = Color3.fromRGB(30, 24, 20)
	elseif inRoom and restState.pending and not restState.resting then
		msg = T.PausingAfterDrop
		banner.BackgroundColor3 = Color3.fromRGB(30, 24, 20)
	end
	banner.Visible = msg ~= nil
	bannerText.Text = msg or ""
	relayout()
end

local function toast(t: string)
	toastMsg = t
	toastUntil = now + 3.5
	refresh()
end

--============================================================================ the list chips
local function rebuildChips()
	for _, c in chips do c:Destroy() end
	table.clear(chips)
	if roomPayload == nil then return end
	for i, cl in roomPayload.clues do
		local b = Instance.new("TextButton")
		b.Name = "Chip_" .. i
		b.BorderSizePixel = 0
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundColor3 = PAPER
		b.Parent = listPanel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b
		local glyphs = Clue.glyphs(cl, Config)
		for gi, gl in glyphs do
			local g = Instance.new("TextLabel")
			g.Name = "Glyph_" .. gi
			g.BackgroundTransparency = if gl.trait == "colour" then 0 else 1
			g.BackgroundColor3 = if gl.trait == "colour" then rgb(Config.Traits.RGB[gl.value]) else PAPER
			g.TextColor3 = INK
			g.TextScaled = true
			g.Font = Enum.Font.GothamBold
			g.Text = if gl.trait == "colour" then gl.letter
				elseif gl.trait == "height" then (if gl.value == "high" then "\u{2191}H" elseif gl.value == "table" then "\u{2192}T" else "\u{2193}F")
				else string.sub(gl.word, 1, 3)
			g.Size = UDim2.fromScale(1 / #glyphs - 0.04, 0.7)
			g.Position = UDim2.fromScale((gi - 1) / #glyphs + 0.02, 0.15)
			g.Parent = b
		end
		b.Activated:Connect(function()
			calloutItem = i
			calloutText.Text = string.format("%s\nhides in %s", Config.Items.Names[cl.item] or "Something", Clue.words(cl, Config))
			callout.Visible = not card.Visible
			hintButton.Visible = not (state and state.hintUsed)
			refresh()
		end)
		table.insert(chips, b)
	end
end

local function paintChips()
	for i, b in chips do
		local found = (state and state.found and state.found[i]) or foundShown[i]
		b.BackgroundColor3 = if found then GOLD else PAPER
	end
end

--============================================================================ cards from the server's state
local lastResultKey = nil
local function onState(st: any)
	if type(st) ~= "table" then return end
	state = st
	stateAt = now
	local wasRoom = where == "room"
	where = st.where or "hub"
	ClientBus.fire("state", st)
	if where ~= "room" then
		roomPayload = nil
		selected = nil
		rebuildChips()
		if cardKind ~= "brag" then showCard(nil) end
		callout.Visible = false
		refresh()
		return
	end
	if not wasRoom then menuOpen = false end
	if st.state == "intro" then
		showCard("intro", if st.kind == "daily" then string.format("DAILY CASE #%d", st.case or 0) else string.format("CHAPTER %d", st.chapter or 0),
			st.introText or "", "", {}, nil)
	elseif st.state == "paused" then
		-- REVIEW-1 round 2 C2: the break is capped; the card counts down what is left (RenderStepped below)
		showCard("paused", "PAUSED", if type(st.breakLeft) == "number" then string.format(T.PausedLeft, fmtClock(st.breakLeft)) else T.Paused,
			"", { resumeButton, hubButton }, nil)
	elseif st.state == "done" and st.result then
		local r = st.result
		local key = tostring(st.attemptId) .. ":" .. tostring(r.saving) .. ":" .. tostring(r.first)
		local title, sub
		local buttons
		if r.reason == "found" then
			title = if st.kind == "daily" then "CASE SOLVED!" else "CHAPTER CLEARED!"
			if r.bookSolved then
				title = T.BookSolved
				local total = 0
				for _, c in Config.Chapters do total += c.n end
				sub = string.format(T.BookSolvedSub, total)
				if r.goldBook then sub = sub .. " " .. T.GoldBookToo end
			elseif r.goldBook then sub = T.GoldBook -- REVIEW-1 round 2 D6: the long-term goal, reached
			elseif r.saving then sub = "Saving..."
			elseif r.cantSave or r.pendingSave then sub = r.note
			elseif r.credited then sub = string.format("Cases Solved: %d. See you tomorrow for Case #%d!", r.solved or 0, (st.case or 0) + 1)
			elseif r.first then sub = string.format("Cases Solved: %d", r.solved or 0)
			else sub = r.note or "Stars once earned are kept." end
			buttons = if st.kind == "book" and (st.chapter or 0) < #Config.Chapters then { nextButton, retryButton, hubButton } else { retryButton, hubButton }
			if key ~= lastResultKey and not r.saving then
				FxClient.fovPunch(8, 0.35)
				if r.bookSolved then FxClient.flash(Color3.new(1, 1, 1), 0.4, 0.5) end
			end
		elseif r.reason == "time" then
			title, sub = T.TimeUp .. "!", string.format("You found %d of %d. Retry builds a new room.", r.foundCount or 0, r.n or 0)
			buttons = { retryButton, hubButton }
		elseif r.reason == "looks" then
			title, sub = "OUT OF LOOKS", T.OutOfLooks
			buttons = { retryButton, hubButton }
		elseif r.reason == "break" then
			-- REVIEW-1 round 2 C2: the room closed after the break cap; nothing earned, nothing lost
			title, sub = T.BreakOver, string.format(T.BreakOverSub, math.floor((Config.Pause.MaxBreakSeconds or 600) / 60 + 0.5))
			buttons = { retryButton, hubButton }
		else
			title, sub, buttons = "", "", { hubButton }
		end
		lastResultKey = key
		showCard(if r.bookSolved then "brag" else "result", title, sub, if r.reason == "found" then starLine(r.stars) else "", buttons, nil)
	else
		if cardKind == "intro" or cardKind == "paused" or cardKind == "result" then showCard(nil) end
	end
	paintChips()
	refresh()
end

local function onRoom(payload: any)
	if type(payload) ~= "table" then return end
	roomPayload = payload
	if not payload.redress then
		foundShown = {}
	end
	selected = nil
	rebuildChips()
	paintChips()
	ClientBus.fire("room", payload)
	refresh()
end

local rebuildMenu: () -> () = function() end
local function onProfile(p: any)
	if type(p) ~= "table" then return end
	profile = p
	ClientBus.fire("profile", p)
	-- an open Case Book shows the profile that just arrived (REVIEW-1 round 2 C3: a hopper's load lands seconds later)
	if menuOpen then rebuildMenu() end
	refresh()
end

--============================================================================ the Case Book menu
rebuildMenu = function()
	for _, c in menuList:GetChildren() do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local p = profile or { cleared = 0, stars = {}, continue = 1 }
	local order = 0
	local function row(name: string, label: string, enabled: boolean, onTap: () -> ())
		order += 1
		local b = button(name, menuList, label, if enabled then PAPER else Color3.fromRGB(200, 192, 176))
		b.LayoutOrder = order
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Activated:Connect(onTap)
		return b
	end
	-- REVIEW-1 round 2 D6: the stars toward the Gold Book (all 45) in the title, the Daily streak in its row
	local maxStars = 3 * #Config.Chapters
	menuTitle.Text = string.format(if p.goldBook then T.MenuTitleGold else T.MenuTitle, p.totalStars or 0, maxStars)
	-- REVIEW-1 round 2 C3: until the profile has loaded (a hop: the old server still holds the lock), the book in memory
	-- is empty: no "Continue: Chapter 1" for a returning player
	local loading = p.state ~= nil and p.state ~= "ready" and p.state ~= "nostore"
	if loading then
		row("Continue", T.LoadingBook, false, function() toast(T.StillLoading) end)
	else
		row("Continue", string.format("  Continue: Chapter %d", p.continue or 1), true, function()
			menuOpen = false
			R("Open"):FireServer(p.continue or 1)
			refresh()
		end)
	end
	if p.dailyOpen then
		local streak = if (p.streak or 0) > 0 then string.format("  \u{00B7} streak %d (best %d)", p.streak, math.max(p.bestStreak or 0, p.streak)) else ""
		row("Daily", string.format("  Daily Case #%d%s%s", p.caseNumber or 1, if p.dailySolvedToday then "  \u{2605} solved" else "", streak), true, function()
			menuOpen = false
			R("OpenDaily"):FireServer()
			refresh()
		end)
	end
	for ch = 1, #Config.Chapters do
		local st = p.stars and p.stars["c" .. ch]
		local open = ch <= (p.cleared or 0) + 1
		local starsTxt = if st then ((if st.f then "\u{2605}" else "\u{2606}") .. (if st.w then "\u{2605}" else "\u{2606}") .. (if st.s then "\u{2605}" else "\u{2606}")) else "\u{2606}\u{2606}\u{2606}"
		local bandIx = math.floor((ch - 1) / 3) + 1
		local lbl = string.format("  Ch %d \u{00B7} %s   %s%s", ch, Config.Env.Bands[bandIx].name, starsTxt, if open then "" else "  (locked)")
		row("Chapter_" .. ch, lbl, open, function()
			if not open then
				toast(string.format(T.Locked, (p.cleared or 0) + 1))
				return
			end
			menuOpen = false
			R("Open"):FireServer(ch)
			refresh()
		end)
	end
	relayout()
end

--============================================================================ buttons
nextButton.Activated:Connect(function() R("Next"):FireServer() end)
retryButton.Activated:Connect(function() R("Retry"):FireServer() end)
-- the card stays until the server moves the player (REVIEW-1 round 2 D4: hiding it first left a finished room with
-- nothing to press when a Hub was refused)
hubButton.Activated:Connect(function()
	R("Hub"):FireServer()
end)
local leaveArmedUntil = -math.huge
leaveButton.Activated:Connect(function()
	if now < leaveArmedUntil then
		leaveArmedUntil = -math.huge
		leaveButton.Text = "Leave"
		R("Hub"):FireServer()
	else
		leaveArmedUntil = now + 3
		leaveButton.Text = "Leave?"
		ClientBus.fire("toast", T.LeaveConfirm)
	end
end)
resumeButton.Activated:Connect(function() ClientBus.fire("resumePressed", true) end)
pauseButton.Activated:Connect(function()
	if state and (state.state == "paused" or restState.resting or restState.pending) then
		ClientBus.fire("resumePressed", true)
	else
		ClientBus.fire("pausePressed", true)
	end
end)
hintButton.Activated:Connect(function()
	if calloutItem == nil then
		toast(T.HintPick)
		return
	end
	R("AskHint"):FireServer(calloutItem)
	callout.Visible = false
	refresh()
end)
closeCallout.Activated:Connect(function()
	callout.Visible = false
	calloutItem = nil
	refresh()
end)
searchButton.Activated:Connect(function() ClientBus.fire("searchPressed", true) end)
menuClose.Activated:Connect(function()
	menuOpen = false
	refresh()
end)

--============================================================================ the server, and Room.client
R("State").OnClientEvent:Connect(onState)
R("Room").OnClientEvent:Connect(onRoom)
R("Profile").OnClientEvent:Connect(onProfile)
R("Result").OnClientEvent:Connect(function(res: any)
	if type(res) ~= "table" then return end
	if res.hit and res.item then foundShown[res.item] = true end
	ClientBus.fire("result", res)
	paintChips()
	refresh()
end)
R("Hint").OnClientEvent:Connect(function(h: any)
	if type(h) ~= "table" then return end
	ClientBus.fire("hint", h)
	toast("Look for the sparkle!")
end)
R("Toast").OnClientEvent:Connect(function(t: any)
	if type(t) == "table" and type(t.text) == "string" then toast(t.text) end
end)
R("Notice").OnClientEvent:Connect(function(n: any)
	if type(n) ~= "table" then return end
	ClientBus.fire("notice", n)
	if n.kind == "casebook" then
		-- the BOOK ONE SOLVED card can follow a player into the hub; the menu takes the centre slot from it
		if card.Visible then showCard(nil) end
		menuOpen = true
		rebuildMenu()
		refresh()
	elseif n.kind == "brag" and type(n.text) == "string" then
		toast(n.text)
	end
end)

ClientBus.on("select", function(sel: any)
	selected = sel
	if sel then
		selectLabel.Text = sel.label or ""
		searchButton.Text = if sel.inReach then "Search" else "Walk closer"
	end
	refresh()
end)
ClientBus.on("hazard", function(hz: any)
	hazardMsg = hz
	refresh()
end)
ClientBus.on("rest", function(r: any)
	restState = r or { resting = false, pending = false }
	refresh()
end)
ClientBus.on("toast", function(t: any)
	if type(t) == "string" then toast(t) end
end)

local function watchCamera()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout) end
end
watchCamera()
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(relayout)
menuLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayout)

RunService.RenderStepped:Connect(function(dt: number)
	now += dt
	if state and where == "room" then
		local live = state.state == "live"
		local clock = (state.clock or 0) + (if live then now - stateAt else 0)
		clockText.Text = fmtClock((state.limit or 0) - clock)
		clockText.TextColor3 = if (state.limit or 0) - clock < 10 and live then Color3.fromRGB(255, 120, 100) else PAPER
		if cardKind == "paused" and type(state.breakLeft) == "number" then
			cardSub.Text = string.format(T.PausedLeft, fmtClock(state.breakLeft - (now - stateAt)))
		end
	end
	if leaveArmedUntil > -math.huge and now >= leaveArmedUntil then
		leaveArmedUntil = -math.huge
		leaveButton.Text = "Leave"
	end
	if toastMsg and now >= toastUntil and banner.Visible and not (hazardMsg and hazardMsg.active) then
		toastMsg = nil
		refresh()
	end
end)

showCard(nil)
callout.Visible = false
menu.Visible = false
relayout()
refresh()
R("Hello"):FireServer()
