-- ESCAPE ROOM LAB — the HUD. Client only (StarterPlayerScripts). Phone first (DESIGN.md §17.2).
--
-- Display and input only: every verdict is the server's. The overlay sends Act(station, verb, ...) and
-- nothing else; no remote here carries a star, a result, a time or a position. It shows what the server
-- sent this player (RoomState, Hint, Notice, Profile, Board) and what Lab.client posts on ClientBus
-- (the hazard banner, the Break state, band title cards).
--
-- The phone rules (docs/new-game-checklist.md §2b), and where each is kept:
--   * a root Frame owns the UIScale and is sized 1/scale, so it still spans the screen after scaling;
--   * every tap target is >= 44 SCREEN px on touch (designFor), measured by check_escaperoomlab_hud;
--   * nothing tappable in the bottom-left (thumbstick) or bottom-right (jump): on a landscape phone the
--     station overlay is the middle 40% column, the one strip those controls leave free at full height;
--     elsewhere it sits above the control band;
--   * while the overlay is open the star chip hides, so no two visible panels ever overlap (rule 4b);
--   * everything re-lays-out on ViewportSize AND TouchEnabled changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local Text = require(ReplicatedStorage:WaitForChild("Text"))
local ClientBus = require(ReplicatedStorage:WaitForChild("ClientBus"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local remotes = ReplicatedStorage:WaitForChild("LabRemotes")
local Act = remotes:WaitForChild("Act") :: RemoteEvent
local RoomStateEv = remotes:WaitForChild("RoomState") :: RemoteEvent
local HintEv = remotes:WaitForChild("Hint") :: RemoteEvent
local Notice = remotes:WaitForChild("Notice") :: RemoteEvent
local ProfileEv = remotes:WaitForChild("Profile") :: RemoteEvent
local BoardEv = remotes:WaitForChild("Board") :: RemoteEvent
local OpenEv = remotes:WaitForChild("Open") :: RemoteEvent
local Hello = remotes:WaitForChild("Hello") :: RemoteEvent

local STAR = "\u{2605}"
local FLASK_COLORS = {
	Color3.fromRGB(230, 60, 60), Color3.fromRGB(60, 110, 240), Color3.fromRGB(60, 200, 90),
	Color3.fromRGB(245, 215, 60), Color3.fromRGB(160, 80, 220),
}
local PANEL = Color3.fromRGB(20, 24, 36)
local ACCENT = Color3.fromRGB(90, 220, 255)
local GOLD = Color3.fromRGB(255, 214, 90)
local WHITE = Color3.fromRGB(240, 242, 248)

--============================================================================ state
local roomState: any = nil       -- the newest RoomState payload
local profile: any = nil
local openId: string? = nil      -- the station whose overlay is open
local collapsed = false          -- a hazard folded the overlay to its title bar
local hazard: any = nil          -- ClientBus "hazard"
local rest: any = { resting = false, pending = false }
local entered: { number } = {}   -- the door keypad's digits, never sent until ENTER
local selectedFlask: number? = nil
local hints: { [string]: any } = {}
local doorView = "clues"         -- compact screens show the clues or the keypad, one at a time
local toastText: string? = nil
local toastUntil = 0
local lockedUntil: { [string]: number } = {}
local lastRoomCard: any = nil

--============================================================================ widgets
local function make(className: string, name: string, parent: Instance?, props: { [string]: any }?): any
	local o = Instance.new(className)
	o.Name = name
	if props then
		for k, v in props do (o :: any)[k] = v end
	end
	if parent then o.Parent = parent end
	return o
end

local function corner(o: Instance, r: number)
	make("UICorner", "Corner", o, { CornerRadius = UDim.new(0, r) })
end

local function textLabel(name: string, parent: Instance, maxSize: number?): TextLabel
	local l = make("TextLabel", name, parent, {
		BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextScaled = true,
		TextWrapped = true, Text = "",
	})
	make("UITextSizeConstraint", "Max", l, { MaxTextSize = maxSize or 22 })
	return l
end

local function button(name: string, parent: Instance, text: string, color: Color3?): TextButton
	local b = make("TextButton", name, parent, {
		BackgroundColor3 = color or Color3.fromRGB(46, 54, 76), TextColor3 = WHITE, Font = Enum.Font.GothamBlack,
		TextScaled = true, TextWrapped = true, Text = text, AutoButtonColor = true, BorderSizePixel = 0,
	})
	corner(b, 8)
	make("UITextSizeConstraint", "Max", b, { MaxTextSize = 24 })
	return b
end

local gui = make("ScreenGui", "LabHud", nil, { ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false, DisplayOrder = 3 })
gui.Parent = player:WaitForChild("PlayerGui")

local root = make("Frame", "Root", gui, { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
local uiScale = make("UIScale", "Scale", root)

local starChip = make("Frame", "StarChip", root, { BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, BorderSizePixel = 0 })
corner(starChip, 10)
FxClient.theme(starChip, { stroke = ACCENT, strokeThickness = 1 })
local starText = textLabel("StarText", starChip, 20)
starText.Size = UDim2.new(1, -16, 1, 0)
starText.Position = UDim2.fromOffset(8, 0)
starText.TextXAlignment = Enum.TextXAlignment.Left

local breakBtn = button("BreakButton", root, "\u{2615} Break", Color3.fromRGB(70, 110, 170))

local banner = textLabel("Banner", root, 20)
banner.BackgroundTransparency = 0.15
banner.BackgroundColor3 = PANEL
banner.Visible = false
corner(banner, 10)

local card = textLabel("Card", root, 44)
card.Font = Enum.Font.GothamBlack
card.TextStrokeTransparency = 0.4
card.Visible = false
local cardSub = textLabel("CardSub", root, 22)
cardSub.TextStrokeTransparency = 0.5
cardSub.Visible = false

local overlay = make("Frame", "Overlay", root, { BackgroundColor3 = PANEL, BackgroundTransparency = 0.08, BorderSizePixel = 0,
	Visible = false })
corner(overlay, 12)
FxClient.theme(overlay, { stroke = ACCENT, strokeThickness = 1.5 })
local titleBar = make("Frame", "TitleBar", overlay, { BackgroundTransparency = 1 })
local titleLabel = textLabel("TitleLabel", titleBar, 22)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = GOLD
local toggleBtn = button("ToggleButton", titleBar, "123")
local hintBtn = button("HintButton", titleBar, "?", Color3.fromRGB(60, 90, 120))
local closeBtn = button("CloseButton", titleBar, "X", Color3.fromRGB(120, 50, 60))
local body = make("Frame", "Body", overlay, { BackgroundTransparency = 1 })

-- per-kind content, built when a station opens
local content: any = {}

--============================================================================ layout
local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local geo: any = { tap = 44, g = 6, column = false }

-- Design px whose on-screen size is strictly more than `screenPx` after the UIScale.
local function designFor(screenPx: number): number
	local n = math.ceil(screenPx / layout.scale)
	if n * layout.scale <= screenPx then n += 1 end
	return n
end

local function stationOf(id: string?): any
	if roomState == nil or id == nil then return nil end
	if id == "Door" then return roomState.door end
	for _, s in roomState.stations do
		if s.id == id then return s end
	end
	return nil
end

local function kindTitle(id: string, st: any): string
	if id == "Door" then return "DOOR" end
	return (if st.kind == "lamp" then "LAMP GRID " else "FLASK SHELF ") .. id
end

local function fitCanvas(scroll: ScrollingFrame, list: UIListLayout)
	local function update()
		local s = uiScale.Scale
		if s <= 0 then s = 1 end
		scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(list.AbsoluteContentSize.Y / s) + 4)
	end
	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
	update()
end

local function scrollList(name: string, parent: Instance, gap: number): (ScrollingFrame, UIListLayout)
	local sf = make("ScrollingFrame", name, parent, { BackgroundColor3 = Color3.fromRGB(12, 14, 22), BackgroundTransparency = 0.3,
		BorderSizePixel = 0, ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.fromOffset(0, 0) })
	corner(sf, 8)
	local list = make("UIListLayout", "List", sf, { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap) })
	fitCanvas(sf, list)
	return sf, list
end

-- Lay out the open station's content inside a body of bw x bh design px.
local function layoutContent(bw: number, bh: number)
	local st = stationOf(openId)
	if st == nil or content.kind == nil then return end
	local tap, g = geo.tap, geo.g
	if content.kind == "lamp" then
		local n = content.n
		local cell = math.floor(math.min((bw - (n - 1) * g) / n, (bh - (n - 1) * g) / n, tap * 1.6))
		cell = math.max(cell, tap)
		local total = n * cell + (n - 1) * g
		local x0 = math.floor((bw - total) / 2)
		for i, b in content.buttons do
			local r = math.floor((i - 1) / n)
			local c = (i - 1) % n
			b.Position = UDim2.fromOffset(x0 + c * (cell + g), r * (cell + g))
			b.Size = UDim2.fromOffset(cell, cell)
		end
	elseif content.kind == "shelf" then
		local N = content.N
		local fw = math.floor(math.min(tap * 1.5, (bw - (N - 1) * g) / N))
		fw = math.max(fw, tap)
		local fh = math.max(tap, math.floor(math.min(fw * 1.3, bh * 0.3)))
		local total = N * fw + (N - 1) * g
		local x0 = math.floor((bw - total) / 2)
		for s, b in content.buttons do
			b.Position = UDim2.fromOffset(x0 + (s - 1) * (fw + g), 0)
			b.Size = UDim2.fromOffset(fw, fh)
		end
		local listH = math.max(tap, bh - fh - tap - 2 * g)
		content.clues.Position = UDim2.fromOffset(0, fh + g)
		content.clues.Size = UDim2.fromOffset(bw, listH)
		local rowH = math.max(math.floor(tap * 0.62), 26)
		for _, l in content.clueLabels do l.Size = UDim2.new(1, -10, 0, rowH) end
		content.test.Position = UDim2.fromOffset(0, fh + g + listH + g)
		content.test.Size = UDim2.fromOffset(bw, tap)
	else
		local wide = not layout.compact and bw >= 560
		local keys = content.keyList
		local key = tap
		local dispH = math.max(math.floor(tap * 0.7), 30)
		-- the fewest columns whose keypad fits the body's height (3 x 4 on a tall screen, 4 x 3 or
		-- 6 x 2 on a short one); every key stays a full tap target either way
		local cols, rows, kh = 3, 0, 0
		for _, c in { 3, 4, 6 } do
			cols = c
			rows = math.ceil(#keys / cols)
			kh = dispH + g + rows * key + (rows - 1) * g
			if kh <= bh then break end
		end
		local kw = cols * key + (cols - 1) * g
		local cluesW, keyX = bw, 0
		if wide then
			cluesW = bw - kw - g
			keyX = cluesW + g
		else
			keyX = math.floor((bw - kw) / 2)
		end
		content.clues.Visible = wide or doorView == "clues"
		content.keypad.Visible = wide or doorView == "keypad"
		content.clues.Position = UDim2.fromOffset(0, 0)
		content.clues.Size = UDim2.fromOffset(cluesW, bh)
		local rowH = math.max(math.floor(tap * 1.15), 52)
		for _, row in content.lineRows do row.Size = UDim2.new(1, -10, 0, rowH) end
		content.keypad.Position = UDim2.fromOffset(keyX, 0)
		content.keypad.Size = UDim2.fromOffset(kw, math.min(kh, bh))
		content.display.Position = UDim2.fromOffset(0, 0)
		content.display.Size = UDim2.fromOffset(kw, dispH)
		for i, b in keys do
			local r = math.floor((i - 1) / cols)
			local c = (i - 1) % cols
			b.Position = UDim2.fromOffset(c * (key + g), dispH + g + r * (key + g))
			b.Size = UDim2.fromOffset(key, key)
		end
		toggleBtn.Text = if doorView == "clues" then "123" else "Clues"
	end
end

local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, tl = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and tl ~= nil then tl.Y else 0
	end
	local vyDraw = math.max(1, vy - inset)
	layout = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)
	local s = layout.scale
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
	local rootW, rootH = vx / s, vyDraw / s
	local M = Responsive.MARGIN
	local tap = if layout.controlPad > 0 then designFor(44) else 44
	local g = designFor(4)
	geo.tap, geo.g = tap, g
	local padBottom = layout.controlPad / s
	geo.column = UserInputService.TouchEnabled and layout.compact and vx > vy

	-- the top row: star chip left, Break right
	local breakW = math.max(tap, 130)
	breakBtn.Position = UDim2.fromOffset(rootW - M - breakW, M)
	breakBtn.Size = UDim2.fromOffset(breakW, tap)
	local chipW = math.max(120, math.min(460, rootW - 3 * M - breakW))
	starChip.Position = UDim2.fromOffset(M, M)
	starChip.Size = UDim2.fromOffset(chipW, tap)

	local bw = math.min(760, rootW - 2 * M)
	local bannerX, bannerY, bannerW, bannerH = (rootW - bw) / 2, M + tap + g, bw, tap
	local open = openId ~= nil
	if open then
		local ox, oy, ow, oh
		if geo.column then
			ox, ow = 0.35 * rootW + 1, 0.40 * rootW - 2
			oy, oh = M, rootH - 2 * M
			-- the banner takes the left strip, where the (hidden) star chip was
			bannerX, bannerY, bannerW, bannerH = M, M, 0.35 * rootW - M - g, tap * 2
		else
			ow = math.min(760, rootW - 2 * M)
			ox = (rootW - ow) / 2
			oy = M + tap + g + bannerH + g
			-- never more than ~46% of the screen's height: a tall phone keeps the room in view
			-- (hudcheck rule 5: panels may not cover half a touch screen)
			oh = math.min(rootH - padBottom - M - oy, math.max(0.46 * rootH, 6 * tap))
		end
		local pad = g
		local shown = if collapsed then tap + 2 * pad else oh
		overlay.Position = UDim2.fromOffset(ox, oy)
		overlay.Size = UDim2.fromOffset(ow, shown)
		titleBar.Position = UDim2.fromOffset(pad, pad)
		titleBar.Size = UDim2.fromOffset(ow - 2 * pad, tap)
		local x = ow - 2 * pad - tap
		closeBtn.Position = UDim2.fromOffset(x, 0)
		closeBtn.Size = UDim2.fromOffset(tap, tap)
		x -= g + tap
		hintBtn.Position = UDim2.fromOffset(x, 0)
		hintBtn.Size = UDim2.fromOffset(tap, tap)
		local st = stationOf(openId)
		local wideDoor = openId == "Door" and not layout.compact and (ow - 2 * pad) >= 560
		toggleBtn.Visible = openId == "Door" and not wideDoor
		if toggleBtn.Visible then
			local tw = math.max(tap, math.floor(tap * 1.5))
			x -= g + tw
			toggleBtn.Position = UDim2.fromOffset(x, 0)
			toggleBtn.Size = UDim2.fromOffset(tw, tap)
		end
		titleLabel.Position = UDim2.fromOffset(0, 0)
		titleLabel.Size = UDim2.fromOffset(math.max(10, x - g), tap)
		body.Visible = not collapsed
		body.Position = UDim2.fromOffset(pad, pad + tap + pad)
		body.Size = UDim2.fromOffset(ow - 2 * pad, oh - tap - 3 * pad)
		if st then layoutContent(ow - 2 * pad, oh - tap - 3 * pad) end
	end
	banner.Position = UDim2.fromOffset(bannerX, bannerY)
	banner.Size = UDim2.fromOffset(bannerW, bannerH)

	local cardW = math.min(820, rootW - 2 * M)
	local cardH = math.min(80, rootH * 0.14)
	card.Position = UDim2.fromOffset((rootW - cardW) / 2, rootH * 0.3)
	card.Size = UDim2.fromOffset(cardW, cardH)
	cardSub.Position = UDim2.fromOffset((rootW - cardW) / 2, rootH * 0.3 + cardH + 4)
	cardSub.Size = UDim2.fromOffset(cardW, math.min(56, rootH * 0.1))
end

--============================================================================ the banner, the chip, cards

local function guidance(): string?
	if roomState == nil or roomState.where == "atrium" then
		if profile and profile.frontier == 1 and profile.stars == 0 then
			return "Walk into the SOLO LIFT. Stand inside and the doors close."
		end
		return nil
	end
	if roomState.where ~= "room" then return nil end
	if roomState.state == "escaped" then return "Step into the exit lift and press NEXT." end
	for _, s in roomState.stations do
		if not s.solved then return "Open the " .. kindTitle(s.id, s) .. " on the " .. (if s.id == "A" then "left" else "right") .. " wall." end
	end
	if not roomState.door.solved then return "Every line is lit: crack the DOOR code." end
	return nil
end

local function ruleFor(id: string): string
	local st = stationOf(id)
	if id == "Door" then return Text.DoorRule end
	if st and st.kind == "lamp" then return Text.LampRule end
	return Text.ShelfRule
end

local function refreshBanner()
	local t = tick()
	local text: string? = nil
	local color = PANEL
	if hazard and hazard.active then
		text = hazard.text
		color = if hazard.clear then Color3.fromRGB(30, 110, 60) else Color3.fromRGB(150, 24, 24)
	elseif toastText and t < toastUntil then
		text = toastText
	elseif openId then
		local lock = (lockedUntil[openId] or 0) - t
		if lock > 0 then
			text = string.format("Locked for %d s after a wrong try.", math.ceil(lock))
		elseif hints[openId] then
			text = "Hint: " .. hints[openId].text
			color = Color3.fromRGB(24, 70, 90)
		else
			text = ruleFor(openId)
		end
	else
		text = guidance()
	end
	if rest.resting and not (hazard and hazard.active) then
		text = "\u{2615} Break - the Lab leaves you alone. Move to carry on."
		color = Color3.fromRGB(40, 60, 100)
	end
	banner.Text = text or ""
	banner.BackgroundColor3 = color
	banner.Visible = text ~= nil and text ~= ""
end

local function refreshChip()
	local stars = if profile then profile.stars else 0
	local where = "Atrium"
	if roomState and roomState.where == "room" then
		where = string.format("%s %d/3", roomState.wingName, roomState.room)
	elseif roomState and roomState.where == "roof" then
		where = "Roof"
	end
	starText.Text = string.format("%s %d/%d  \u{00B7}  %s", STAR, stars, Config.Stars.Max, where)
	starChip.Visible = openId == nil
	breakBtn.Text = if rest.resting then "\u{25B6} Carry on" elseif rest.pending then "\u{2615} ..." else "\u{2615} Break"
end

local function showToast(text: string, seconds: number?)
	toastText = text
	toastUntil = tick() + (seconds or 4)
	refreshBanner()
end

local cardToken = 0
local function showCard(title: string, sub: string?, celebrate: boolean?)
	cardToken += 1
	local mine = cardToken
	card.Text = title
	cardSub.Text = sub or ""
	card.TextTransparency = 0
	cardSub.TextTransparency = 0
	card.Visible = true
	cardSub.Visible = sub ~= nil and sub ~= ""
	if celebrate then
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.45, 0.9)
		FxClient.fovPunch(8, 0.12, 0.6)
	end
	task.delay(if celebrate then 4.5 else 3.5, function()
		if cardToken ~= mine then return end
		local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tw = TweenService:Create(card, info, { TextTransparency = 1 })
		TweenService:Create(cardSub, info, { TextTransparency = 1 }):Play()
		tw.Completed:Connect(function()
			if cardToken ~= mine then return end
			card.Visible = false
			cardSub.Visible = false
		end)
		tw:Play()
	end)
end

--============================================================================ the overlay

local function clearContent()
	for _, c in body:GetChildren() do c:Destroy() end
	content = {}
end

local function send(verb: string, a: any?, b: any?)
	if openId == nil then return end
	Act:FireServer(openId, verb, a, b)
end

local function buildContent()
	clearContent()
	local st = stationOf(openId)
	if st == nil then return end
	if openId == "Door" then
		content.kind = "door"
		local clues, _ = scrollList("DoorClues", body, geo.g)
		content.clues = clues
		content.lineRows = {}
		for i = 1, #st.lines do
			local row = make("Frame", "Line_" .. i, clues, { BackgroundTransparency = 1, LayoutOrder = i })
			local gl = textLabel("Guess", row, 26)
			gl.Font = Enum.Font.GothamBlack
			gl.TextColor3 = GOLD
			gl.Size = UDim2.fromScale(1, 0.48)
			gl.TextXAlignment = Enum.TextXAlignment.Left
			local tl = textLabel("Sentence", row, 18)
			tl.Font = Enum.Font.Gotham
			tl.Position = UDim2.fromScale(0, 0.5)
			tl.Size = UDim2.fromScale(1, 0.5)
			tl.TextXAlignment = Enum.TextXAlignment.Left
			content.lineRows[i] = row
		end
		local keypad = make("Frame", "Keypad", body, { BackgroundTransparency = 1 })
		content.keypad = keypad
		local display = textLabel("CodeDisplay", keypad, 30)
		display.Font = Enum.Font.GothamBlack
		display.BackgroundTransparency = 0.2
		display.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
		content.display = display
		content.keyList = {}
		content.keyOf = {}
		for _, d in st.alphabet do
			local b = button("Key_" .. d, keypad, tostring(d))
			b.Activated:Connect(function()
				-- a used digit greys out (codes never repeat a digit), and a full code takes no more
				if table.find(entered, d) or #entered >= st.L then return end
				table.insert(entered, d)
				if content.refresh then content.refresh() end
			end)
			table.insert(content.keyList, b)
			content.keyOf[d] = b
		end
		local back = button("Key_Back", keypad, "\u{232B}", Color3.fromRGB(90, 70, 50))
		back.Activated:Connect(function()
			if #entered > 0 then table.remove(entered) end
			if content.refresh then content.refresh() end
		end)
		table.insert(content.keyList, back)
		local enter = button("Key_Enter", keypad, "ENTER", Color3.fromRGB(40, 120, 80))
		enter.Activated:Connect(function()
			local s2 = stationOf("Door")
			if s2 == nil then return end
			if #entered < s2.L then
				return showToast(string.format("The code has %d digits. None repeat.", s2.L))
			end
			send("enter", table.clone(entered))
			table.clear(entered)
			if content.refresh then content.refresh() end
		end)
		table.insert(content.keyList, enter)
		content.refresh = function()
			local s2 = stationOf("Door")
			if s2 == nil then return end
			for i, ln in s2.lines do
				local row = content.lineRows[i]
				if row then
					local gl = row:FindFirstChild("Guess") :: TextLabel
					local tl = row:FindFirstChild("Sentence") :: TextLabel
					if ln.dark then
						gl.Text = string.rep("? ", s2.L - 1) .. "?"
						tl.Text = "Lit by " .. (if (stationOf(ln.by) or {}).kind == "shelf" then "FLASK SHELF " else "LAMP GRID ") .. tostring(ln.by)
						gl.TextColor3 = Color3.fromRGB(120, 130, 150)
					else
						gl.Text = ln.guess
						tl.Text = ln.text
						gl.TextColor3 = GOLD
					end
				end
			end
			local shown = {}
			for i = 1, s2.L do shown[i] = if entered[i] ~= nil then tostring(entered[i]) else "_" end
			local disp = table.concat(shown, " ")
			if s2.lastWrong and (s2.lockedFor or 0) > 0 and #entered == 0 then disp = s2.lastWrong .. "  X" end
			if not s2.enterable and not s2.solved then disp = "DARK: " .. disp end
			content.display.Text = disp
			for d, b in content.keyOf do
				local used = table.find(entered, d) ~= nil or #entered >= s2.L
				b.BackgroundColor3 = if used then Color3.fromRGB(30, 32, 40) else Color3.fromRGB(46, 54, 76)
				b.TextTransparency = if used then 0.6 else 0
			end
		end
	elseif st.kind == "lamp" then
		content.kind = "lamp"
		content.n = st.size
		content.buttons = {}
		local grid = make("Frame", "LampGrid", body, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		for i = 1, st.size * st.size do
			local b = button("Lamp_" .. i, grid, "")
			b.Activated:Connect(function()
				-- a lamp hint names one press: once it is made, the ring and the banner go (review 2026-10-01:
				-- they stayed, and a second press on the ringed lamp undid the move)
				local hint = hints[openId]
				if hint and hint.lamp == i then hints[openId] = nil end
				send("press", i)
				if content.refresh then content.refresh() end
				refreshBanner()
			end)
			content.buttons[i] = b
		end
		content.refresh = function()
			local s2 = stationOf(openId)
			if s2 == nil or s2.lamps == nil then return end
			local h = hints[openId]
			for i, b in content.buttons do
				local lit = s2.lamps[i]
				b.Text = if lit then "\u{25CF}" else "\u{25CB}"
				b.BackgroundColor3 = if lit then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(34, 38, 50)
				b.TextColor3 = if lit then Color3.fromRGB(80, 60, 10) else Color3.fromRGB(150, 160, 180)
				local stroke = b:FindFirstChildOfClass("UIStroke")
				if h and h.lamp == i and not s2.solved then
					if stroke == nil then
						make("UIStroke", "HintStroke", b, { Color = ACCENT, Thickness = 3 })
					end
				elseif stroke then
					stroke:Destroy()
				end
			end
		end
	else
		content.kind = "shelf"
		content.N = st.size
		content.buttons = {}
		local row = make("Frame", "FlaskRow", body, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		for s = 1, st.size do
			local b = button("Flask_" .. s, row, "")
			b.Activated:Connect(function()
				if selectedFlask == nil then
					selectedFlask = s
				elseif selectedFlask == s then
					selectedFlask = nil
				else
					local a = selectedFlask
					selectedFlask = nil
					send("swap", a, s)
				end
				if content.refresh then content.refresh() end
			end)
			content.buttons[s] = b
		end
		local clues, _ = scrollList("ClueList", body, geo.g)
		content.clues = clues
		content.clueLabels = {}
		for i, c in st.clues do
			local l = textLabel("Clue_" .. i, clues, 18)
			l.Font = Enum.Font.Gotham
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.LayoutOrder = i
			l.Text = c
			content.clueLabels[i] = l
		end
		local test = button("TestButton", body, "TEST", Color3.fromRGB(40, 120, 80))
		test.Activated:Connect(function() send("test") end)
		content.test = test
		content.refresh = function()
			local s2 = stationOf(openId)
			if s2 == nil or s2.flasks == nil then return end
			for s, b in content.buttons do
				local c = s2.flasks[s]
				b.Text = Text.FlaskLetters[c] or "?"
				b.BackgroundColor3 = FLASK_COLORS[c] or Color3.new(0.5, 0.5, 0.5)
				local stroke = b:FindFirstChildOfClass("UIStroke")
				if selectedFlask == s then
					if stroke == nil then make("UIStroke", "Selected", b, { Color = Color3.new(1, 1, 1), Thickness = 4 }) end
				elseif stroke then
					stroke:Destroy()
				end
			end
		end
	end
end

local function refreshOverlay()
	if openId == nil then return end
	local st = stationOf(openId)
	if st == nil then return end
	titleLabel.Text = kindTitle(openId, st) .. (if st.solved then "  -  solved" else "")
	if content.refresh then content.refresh() end
end

local function closeOverlay()
	if openId == nil then return end
	openId = nil
	collapsed = false
	selectedFlask = nil
	table.clear(entered)
	overlay.Visible = false
	clearContent()
	ClientBus.fire("overlay", { open = false })
	applyLayout()
	refreshChip()
	refreshBanner()
end

local function openOverlay(id: string)
	if stationOf(id) == nil then return end
	openId = id
	collapsed = hazard ~= nil and hazard.active == true
	selectedFlask = nil
	table.clear(entered)
	doorView = if id == "Door" and roomState.door.enterable then "keypad" else "clues"
	overlay.Visible = true
	buildContent()
	ClientBus.fire("overlay", { open = true, station = id })
	applyLayout()
	refreshOverlay()
	refreshChip()
	refreshBanner()
end

closeBtn.Activated:Connect(closeOverlay)
hintBtn.Activated:Connect(function() send("hint") end)
toggleBtn.Activated:Connect(function()
	doorView = if doorView == "clues" then "keypad" else "clues"
	applyLayout()
end)
breakBtn.Activated:Connect(function() ClientBus.fire("breakPressed", true) end)

--============================================================================ the friends view on the board (local only)

local friendsGui: SurfaceGui? = nil
local function renderFriends(payload: any)
	local atrium = workspace:FindFirstChild("Atrium")
	local boardPart = atrium and atrium:FindFirstChild("StarBoard")
	if boardPart == nil then return end
	if friendsGui == nil or friendsGui.Parent == nil then
		local g = make("SurfaceGui", "FriendsFace", nil, { Face = Enum.NormalId.Left, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40, LightInfluence = 0, ZOffset = 1 })
		local bg = make("Frame", "Bg", g, { BackgroundColor3 = Color3.fromRGB(24, 28, 44), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
		local t = textLabel("Title", bg, 60)
		t.Text = "STAR BOARD"
		t.TextColor3 = GOLD
		t.Position = UDim2.fromScale(0.03, 0.02)
		t.Size = UDim2.fromScale(0.94, 0.12)
		local m = textLabel("Mode", bg, 30)
		m.Text = "FRIENDS"
		m.Position = UDim2.fromScale(0.03, 0.14)
		m.Size = UDim2.fromScale(0.94, 0.06)
		for i = 1, Config.Board.FriendsRows do
			local r = textLabel("Row_" .. i, bg, 30)
			r.TextXAlignment = Enum.TextXAlignment.Left
			r.Position = UDim2.fromScale(0.06, 0.21 + (i - 1) * 0.068)
			r.Size = UDim2.fromScale(0.88, 0.062)
		end
		local n = textLabel("Note", bg, 26)
		n.Font = Enum.Font.Gotham
		n.Position = UDim2.fromScale(0.05, 0.9)
		n.Size = UDim2.fromScale(0.9, 0.08)
		g.Parent = boardPart
		friendsGui = g
	end
	local g = friendsGui :: SurfaceGui
	g.Enabled = payload.mode == "friends"
	if payload.mode ~= "friends" then return end
	local bg = g:FindFirstChild("Bg") :: Frame
	for i = 1, Config.Board.FriendsRows do
		local r = (payload.rows or {})[i]
		local l = bg:FindFirstChild("Row_" .. i) :: TextLabel
		l.Text = if r then string.format("%d.  %s   %s %d%s", r.rank, r.name, STAR, r.stars, if r.you then "  (you)" else "") else ""
		l.TextColor3 = if r and r.you then GOLD else WHITE
	end
	(bg:FindFirstChild("Note") :: TextLabel).Text = payload.message or ""
end

--============================================================================ remotes in

RoomStateEv.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then return end
	ClientBus.fire("roomState", payload)
	local newRoom = roomState == nil or payload.roomId ~= roomState.roomId
	roomState = payload
	if payload.where ~= "room" then
		closeOverlay()
	else
		local t = tick()
		for _, s in payload.stations do lockedUntil[s.id] = t + (s.lockedFor or 0) end
		lockedUntil.Door = t + (payload.door.lockedFor or 0)
		if newRoom then
			hints = {}
			closeOverlay()
		elseif openId then
			local st = stationOf(openId)
			if st == nil then
				closeOverlay()
			else
				if openId == "Door" and st.enterable and doorView == "clues" and not layout.compact then doorView = "keypad" end
				refreshOverlay()
			end
		end
	end
	refreshChip()
	refreshBanner()
end)

OpenEv.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" and type(payload.station) == "string" then
		openOverlay(payload.station)
	end
end)

HintEv.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then return end
	hints[payload.station] = payload
	refreshOverlay()
	refreshBanner()
end)

ProfileEv.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then return end
	ClientBus.fire("profile", payload)
	profile = payload
	refreshChip()
	refreshBanner()
end)

BoardEv.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" then renderFriends(payload) end
end)

Notice.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then return end
	ClientBus.fire("notice", payload)
	local kind = payload.kind
	if kind == "room" then
		lastRoomCard = { title = string.format("ROOM %d \u{00B7} %s", payload.slot, string.upper(payload.wingName)), at = tick() }
		showCard(lastRoomCard.title, payload.text, false)
	elseif kind == "escape" then
		closeOverlay()
		local sub = if payload.reasons and #payload.reasons > 0 then table.concat(payload.reasons, "  ") else "Clean and unaided: every star."
		showCard(payload.text, sub, true)
	elseif kind == "roof" then
		showCard("YOU ESCAPED THE LAB", if payload.first then "The Roof is yours. Take a friend up any time." else "Back on the Roof.", true)
	else
		showToast(tostring(payload.text))
	end
end)

--============================================================================ ClientBus in

ClientBus.on("hazard", function(h: any)
	local was = hazard and hazard.active
	hazard = h
	if openId then
		if h and h.active then
			collapsed = true
		elseif was then
			-- reopen if the player is still within reach of the station, otherwise close
			local st = roomState and roomState.origin and Config.World.Stations[openId]
			local char = player.Character
			local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local near = false
			if st and r then
				local o = roomState.origin
				local p = Vector3.new(o[1] + st[1], o[2] + st[2], o[3] + st[3])
				near = (r.Position - p).Magnitude <= Config.Act.StationReach
			end
			if near then collapsed = false else closeOverlay() end
		end
		applyLayout()
	end
	refreshBanner()
end)
ClientBus.on("rest", function(r: any)
	local was = rest.resting
	rest = r
	-- a Break is a pause from the room, never a way to solve it: starting one closes the overlay
	if r.resting and not was then closeOverlay() end
	refreshChip()
	refreshBanner()
end)
ClientBus.on("card", function(c: any)
	-- a new wing's title card arrives with that wing's first room: keep the room's name under it
	local sub = c.sub
	if lastRoomCard and tick() - lastRoomCard.at < 1.5 then sub = lastRoomCard.title end
	showCard(c.title, sub, c.celebrate)
end)

--============================================================================ go

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
refreshChip()
refreshBanner()
Hello:FireServer() -- every handler is connected: ask for this player's state

task.spawn(function()
	while true do
		task.wait(0.25)
		refreshBanner()
		refreshChip()
	end
end)
