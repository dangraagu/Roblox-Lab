-- Hud.client.luau — FACILITY: Endless Nightmare HUD. DISPLAY ONLY: the server decides everything,
-- this file draws what State and Notice say and turns input into "I would like X" requests.
--
-- Built for a PHONE first (docs/mobile-ui-brief.md, checklist §2b):
--   1. One root Frame owns the UIScale, sized fromScale(1/scale, 1/scale) so it still spans the
--      screen after scaling. The ScreenGui ignores the topbar inset and every top-edge element is
--      pushed below it by hand, in design px.
--   2. Modals (the EXTRACT/DESCEND choice, the perk panel) are fitted between the top panels and
--      the band Roblox's own touch controls own, and the perk list is a ScrollingFrame whose
--      canvas is converted from SCREEN px back to design px.
--   3. Nothing tappable in the bottom-left or bottom-right. LIGHT and SPRINT sit on the right edge
--      ABOVE the jump button's band — DESIGN.md §12 asked for 45-70% of the screen height, but on a
--      640x300 phone 70% is inside that band, so the band wins and the stack moves up.
--   4. Layout re-runs on ViewportSize AND on TouchEnabled.
--
-- Labels are plain text. Only glyphs photographed rendering in Studio may ship (the list in
-- robloxemu/check_forktower.luau): here that is the em dash and the ellipsis, nothing else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("FacilityRemotes")
local StateEvent = remotes:WaitForChild("State")
local NoticeEvent = remotes:WaitForChild("Notice")
local FlashlightEvent = remotes:WaitForChild("Flashlight")
local SprintEvent = remotes:WaitForChild("Sprint")
local ChooseEvent = remotes:WaitForChild("Choose")
local BuyPerkEvent = remotes:WaitForChild("BuyPerk")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local function rgb(t)
	return Color3.fromRGB(t.r, t.g, t.b)
end
local ACCENT = rgb(Config.Hud.Accent)
local DANGER = rgb(Config.Hud.Danger)
local GOOD = rgb(Config.Hud.Good)
local PANEL = rgb(Config.Hud.Panel)
local TEXT = Color3.fromRGB(236, 234, 228)
local MUTED = Color3.fromRGB(160, 158, 150)

local M = 12 -- design-px margin

--============================================================================ scaffolding

local gui = Instance.new("ScreenGui")
gui.Name = "FacilityHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = root

-- Full-screen effects live in their own ScreenGui, outside the scaled root: they are not panels.
local overlay = Instance.new("ScreenGui")
overlay.Name = "FacilityOverlay"
overlay.ResetOnSpawn = false
overlay.IgnoreGuiInset = true
overlay.DisplayOrder = 5
overlay.Parent = playerGui

local function panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.Parent = parent
	FxClient.theme(f, { corner = 10, stroke = ACCENT, strokeThickness = 1.2, strokeTransparency = 0.6 })
	return f
end

local function text(parent: Instance, name: string, size: number, color: Color3, align): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = ""
	t.Parent = parent
	return t
end

local function button(parent: Instance, name: string, label: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 18
	b.TextColor3 = color
	b.Text = label
	b.Parent = parent
	FxClient.theme(b, { corner = 10, stroke = color, strokeThickness = 1.5, strokeTransparency = 0.3 })
	return b
end

--============================================================================ pieces

-- top-left: where you are
local STATUS_W, STATUS_H = 230, 64
local status = panel("Status", root)
local statusTop = text(status, "Title", 20, ACCENT)
statusTop.Position = UDim2.fromOffset(12, 6)
statusTop.Size = UDim2.new(1, -24, 0, 26)
local statusSub = text(status, "Sub", 15, TEXT)
statusSub.Position = UDim2.fromOffset(12, 34)
statusSub.Size = UDim2.new(1, -24, 0, 22)

-- top-right: battery and the run's Essence
local POWER_W, POWER_H = 250, 64
local power = panel("Power", root)
power.AnchorPoint = Vector2.new(1, 0)
local powerTop = text(power, "Battery", 16, TEXT)
powerTop.Position = UDim2.fromOffset(12, 6)
powerTop.Size = UDim2.new(1, -24, 0, 20)
local barBg = Instance.new("Frame")
barBg.Name = "BarBg"
barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
barBg.BorderSizePixel = 0
barBg.Position = UDim2.fromOffset(12, 30)
barBg.Size = UDim2.new(1, -24, 0, 10)
barBg.Parent = power
FxClient.theme(barBg, { corner = 4 })
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.BackgroundColor3 = ACCENT
bar.BorderSizePixel = 0
bar.Size = UDim2.fromScale(1, 1)
bar.Parent = barBg
FxClient.theme(bar, { corner = 4 })
local powerSub = text(power, "Essence", 14, MUTED)
powerSub.Position = UDim2.fromOffset(12, 42)
powerSub.Size = UDim2.new(1, -24, 0, 18)

local toast = text(root, "Toast", 18, ACCENT, Enum.TextXAlignment.Center)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextStrokeTransparency = 0.3
toast.TextWrapped = true
toast.TextTruncate = Enum.TextTruncate.None
toast.Visible = false

local hint = text(root, "Hint", 16, TEXT, Enum.TextXAlignment.Center)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.TextStrokeTransparency = 0.4
hint.TextWrapped = true
hint.TextTruncate = Enum.TextTruncate.None

local banner = text(root, "Banner", 30, DANGER, Enum.TextXAlignment.Center)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Font = Enum.Font.GothamBlack
banner.TextStrokeTransparency = 0.2
banner.TextWrapped = true
banner.TextTruncate = Enum.TextTruncate.None
banner.Visible = false

local boarding = panel("Boarding", root)
boarding.AnchorPoint = Vector2.new(0.5, 0)
boarding.Visible = false
local boardingText = text(boarding, "Text", 16, ACCENT, Enum.TextXAlignment.Center)
boardingText.Position = UDim2.fromOffset(8, 4)
boardingText.Size = UDim2.new(1, -16, 0, 20)
boardingText.Text = "Going down…"
local boardBg = Instance.new("Frame")
boardBg.Name = "BarBg"
boardBg.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
boardBg.BorderSizePixel = 0
boardBg.Position = UDim2.fromOffset(12, 28)
boardBg.Size = UDim2.new(1, -24, 0, 8)
boardBg.Parent = boarding
local boardBar = Instance.new("Frame")
boardBar.Name = "Bar"
boardBar.BackgroundColor3 = ACCENT
boardBar.BorderSizePixel = 0
boardBar.Size = UDim2.fromScale(0, 1)
boardBar.Parent = boardBg

local perksButton = button(root, "PerksButton", "PERKS", GOOD)
local lightButton = button(root, "LightButton", "LIGHT", ACCENT)
local sprintButton = button(root, "SprintButton", "SPRINT", TEXT)

-- the choice
local choice = panel("Choice", root)
choice.Visible = false
local choiceTitle = text(choice, "Title", 22, GOOD, Enum.TextXAlignment.Center)
choiceTitle.Text = "ELEVATOR POWERED"
local choiceBody = text(choice, "Body", 15, TEXT, Enum.TextXAlignment.Center)
choiceBody.TextWrapped = true
choiceBody.TextTruncate = Enum.TextTruncate.None
local extractButton = button(choice, "ExtractButton", "EXTRACT", GOOD)
local descendButton = button(choice, "DescendButton", "DESCEND", DANGER)

-- the perk panel
local perks = panel("Perks", root)
perks.Visible = false
local perksTitle = text(perks, "Title", 20, GOOD)
perksTitle.Text = "PERKS"
local perksClose = button(perks, "CloseButton", "CLOSE", TEXT)
local perksList = Instance.new("ScrollingFrame")
perksList.Name = "List"
perksList.BackgroundTransparency = 1
perksList.BorderSizePixel = 0
perksList.ScrollBarThickness = 6
perksList.CanvasSize = UDim2.new()
perksList.Parent = perks
local perksLayout = Instance.new("UIListLayout")
perksLayout.Padding = UDim.new(0, 8)
perksLayout.SortOrder = Enum.SortOrder.LayoutOrder
perksLayout.Parent = perksList

local perkRows: { [string]: any } = {}
for i, id in Config.Perks.Order do
	local p = Config.Perks.Catalog[id]
	local row = Instance.new("Frame")
	row.Name = "Row_" .. id
	row.BackgroundTransparency = 1
	row.LayoutOrder = i
	row.Parent = perksList
	local name = text(row, "Name", 17, TEXT)
	name.Position = UDim2.fromOffset(4, 2)
	name.Text = p.name
	local blurb = text(row, "Blurb", 13, MUTED)
	blurb.Text = p.blurb
	local buy = button(row, "BuyButton", "BUY", ACCENT)
	buy.AnchorPoint = Vector2.new(1, 0)
	buy.Activated:Connect(function()
		BuyPerkEvent:FireServer(id)
	end)
	perkRows[id] = { row = row, name = name, blurb = blurb, buy = buy }
end

-- the death card and the exposure vignette
local deathCard = Instance.new("Frame")
deathCard.Name = "DeathCard"
deathCard.Size = UDim2.fromScale(1, 1)
deathCard.BackgroundColor3 = Color3.new(0, 0, 0)
deathCard.BackgroundTransparency = 0.05
deathCard.BorderSizePixel = 0
deathCard.Visible = false
deathCard.Parent = overlay
local deathText = text(deathCard, "Text", 30, DANGER, Enum.TextXAlignment.Center)
deathText.Size = UDim2.new(0.9, 0, 0.3, 0)
deathText.Position = UDim2.fromScale(0.05, 0.35)
deathText.TextWrapped = true
deathText.TextTruncate = Enum.TextTruncate.None
deathText.Font = Enum.Font.GothamBlack

local vignette = {}
for _, side in { "Top", "Bottom", "Left", "Right" } do
	local f = Instance.new("Frame")
	f.Name = "Vignette" .. side
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = overlay
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Rotation = if side == "Top" then 90 elseif side == "Bottom" then -90 elseif side == "Left" then 0 else 180
	g.Parent = f
	vignette[side] = f
end

--============================================================================ state

local S: any = nil -- last State
local perksOpen = false
local wantSprint = false
local hintOverride, hintUntil = nil, 0
local layout = Responsive.layout(1280, 720, false)

local function now()
	-- tick(), not os.clock(): os.clock is CPU time and barely moves under the headless virtual clock
	return tick()
end

--============================================================================ layout

local function applyLayout()
	local v = camera.ViewportSize
	local touch = UserInputService.TouchEnabled
	local inset = 36
	local okInset, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if okInset and topLeft then inset = topLeft.Y end
	layout = Responsive.layout(v.X, v.Y - inset, touch, v.Y)
	local sc = layout.scale
	uiScale.Scale = sc
	root.Size = UDim2.fromScale(1 / sc, 1 / sc)

	local designW = v.X / sc
	local topY = inset / sc + 8
	-- the lowest design-px y anything tappable may reach: above Roblox's own touch controls
	local bandTop = (v.Y - layout.controlPad - M) / sc
	local minTap = if touch then math.ceil(46 / sc) else 0
	local btnH = math.max(44, minTap)

	-- top panels; stacked when the screen is too narrow to hold both side by side
	local statusW = math.min(STATUS_W, designW - 2 * M)
	local powerW = math.min(POWER_W, designW - 2 * M)
	status.Size = UDim2.fromOffset(statusW, STATUS_H)
	status.Position = UDim2.fromOffset(M, topY)
	power.Size = UDim2.fromOffset(powerW, POWER_H)
	local stacked = statusW + powerW + 3 * M > designW
	local powerY = if stacked then topY + STATUS_H + 8 else topY
	power.Position = UDim2.new(0, designW - M, 0, powerY)
	local inRun = S ~= nil and S.run ~= nil
	power.Visible = inRun
	local topBottom = if stacked and inRun then powerY + POWER_H else topY + STATUS_H

	-- hub row: PERKS under the status panel
	local inHub = S == nil or S.phase == "hub"
	perksButton.Visible = inHub and not perksOpen
	perksButton.Size = UDim2.fromOffset(math.max(120, minTap), btnH)
	perksButton.Position = UDim2.fromOffset(M, topBottom + 8)
	local rowBottom = if perksButton.Visible then topBottom + 8 + btnH else topBottom

	local midW = math.min(560, designW - 2 * M)
	toast.Size = UDim2.fromOffset(midW, 48)
	toast.Position = UDim2.new(0, designW / 2, 0, rowBottom + 8)
	hint.Size = UDim2.fromOffset(midW, 44)
	hint.Position = UDim2.new(0, designW / 2, 0, rowBottom + 60)
	banner.Size = UDim2.fromOffset(midW, 76)
	banner.Position = UDim2.new(0, designW / 2, 0, rowBottom + 108)
	boarding.Size = UDim2.fromOffset(math.min(300, midW), 44)
	boarding.Position = UDim2.new(0, designW / 2, 0, rowBottom + 108)

	-- LIGHT and SPRINT: right edge, bottom at 70% of the screen or the top of the jump band
	local inFloor = S ~= nil and S.phase == "floor"
	-- The choice is shown only standing in the powered lift, the one place it is accepted. It used to
	-- stay up wherever the player walked, and it hid LIGHT and SPRINT: a phone player who stepped out
	-- for a cell had no flashlight button in the next dark room (REVIEW-1 B2).
	local choiceShown = inFloor and S.run ~= nil and S.run.powered == true and S.run.atLift == true
	local bw = math.max(128, minTap)
	local bottomY = math.min((0.70 * v.Y) / sc, bandTop)
	lightButton.Size = UDim2.fromOffset(bw, btnH)
	sprintButton.Size = UDim2.fromOffset(bw, btnH)
	lightButton.Position = UDim2.fromOffset(designW - M - bw, bottomY - 2 * btnH - 8)
	sprintButton.Position = UDim2.fromOffset(designW - M - bw, bottomY - btnH)
	lightButton.Visible = inFloor and not choiceShown
	sprintButton.Visible = inFloor and not choiceShown

	-- modals: between the top panels and the touch band, never under either
	local modalTop = topBottom + 8
	local room = math.max(60, bandTop - modalTop - 8)
	local cw = math.min(440, designW - 2 * M)
	local bodyH = if layout.compact then 34 else 48
	local ch = math.min(room, 12 + 26 + 4 + bodyH + 8 + btnH + 12)
	choice.Size = UDim2.fromOffset(cw, ch)
	choice.Position = UDim2.fromOffset(designW / 2 - cw / 2, modalTop + math.max(0, (room - ch) / 2))
	choiceTitle.Position = UDim2.fromOffset(12, 10)
	choiceTitle.Size = UDim2.new(1, -24, 0, 26)
	choiceBody.Position = UDim2.fromOffset(12, 40)
	choiceBody.Size = UDim2.new(1, -24, 0, bodyH)
	extractButton.Size = UDim2.new(0.5, -18, 0, btnH)
	extractButton.Position = UDim2.new(0, 12, 0, ch - 12 - btnH)
	descendButton.Size = UDim2.new(0.5, -18, 0, btnH)
	descendButton.Position = UDim2.new(0.5, 6, 0, ch - 12 - btnH)
	choice.Visible = choiceShown
	-- A PC player is in LockFirstPerson here, and Roblox pins the cursor to the screen centre unless a
	-- VISIBLE GuiButton is Modal (REVIEW-1 B1). Up exactly while the panel is shown: a Modal button
	-- left on while exploring would break mouse-look. The keys name themselves where there is a keyboard.
	extractButton.Modal = choiceShown
	extractButton.Text = if touch then "EXTRACT" else "EXTRACT (E)"
	descendButton.Text = if touch then "DESCEND" else "DESCEND (Q)"

	local pw = math.min(500, designW - 2 * M)
	local ph = math.min(470, room)
	perks.Size = UDim2.fromOffset(pw, ph)
	perks.Position = UDim2.fromOffset(designW / 2 - pw / 2, modalTop)
	perksTitle.Position = UDim2.fromOffset(12, 10)
	perksTitle.Size = UDim2.new(1, -40 - math.max(96, minTap), 0, btnH)
	perksClose.Size = UDim2.fromOffset(math.max(96, minTap), btnH)
	perksClose.Position = UDim2.new(1, -12 - math.max(96, minTap), 0, 8)
	perksList.Position = UDim2.fromOffset(12, 16 + btnH)
	perksList.Size = UDim2.new(1, -24, 1, -(28 + btnH))
	local rowH = math.max(58, btnH)
	for _, r in perkRows do
		r.row.Size = UDim2.new(1, -10, 0, rowH)
		r.name.Size = UDim2.new(1, -(math.max(110, minTap) + 16), 0, 22)
		r.blurb.Position = UDim2.fromOffset(4, 26)
		r.blurb.Size = UDim2.new(1, -(math.max(110, minTap) + 16), 0, 18)
		r.buy.Size = UDim2.fromOffset(math.max(110, minTap), math.min(rowH, btnH))
		r.buy.Position = UDim2.new(1, 0, 0, 0)
	end
	perks.Visible = perksOpen and inHub
	perksClose.Modal = perks.Visible -- the cursor is free while the panel is open, whatever the camera
	perksList.CanvasSize = UDim2.fromOffset(0, math.ceil(perksLayout.AbsoluteContentSize.Y / math.max(sc, 0.01)) + 12)

	-- vignette thickness follows exposure (screen px, outside the scale)
	local ex = if S and S.run and inFloor then S.run.exposure or 0 else 0
	local thick = math.floor(math.min(v.X, v.Y) * 0.45 * ex)
	for side, f in vignette do
		f.Visible = thick > 0
		if side == "Top" then
			f.Size = UDim2.fromOffset(v.X, thick); f.Position = UDim2.fromOffset(0, 0)
		elseif side == "Bottom" then
			f.Size = UDim2.fromOffset(v.X, thick); f.Position = UDim2.fromOffset(0, v.Y - thick)
		elseif side == "Left" then
			f.Size = UDim2.fromOffset(thick, v.Y); f.Position = UDim2.fromOffset(0, 0)
		else
			f.Size = UDim2.fromOffset(thick, v.Y); f.Position = UDim2.fromOffset(v.X - thick, 0)
		end
	end
end

perksLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	perksList.CanvasSize = UDim2.fromOffset(0, math.ceil(perksLayout.AbsoluteContentSize.Y / math.max(uiScale.Scale, 0.01)) + 12)
end)

--============================================================================ painting

local toastToken = 0
local function showToast(msg: string, seconds: number?)
	toastToken += 1
	local mine = toastToken
	toast.Text = msg
	toast.Visible = true
	task.delay(seconds or 4, function()
		if toastToken == mine then toast.Visible = false end
	end)
end

local bannerToken = 0
local function showBanner(msg: string, color: Color3?)
	bannerToken += 1
	local mine = bannerToken
	banner.Text = msg
	banner.TextColor3 = color or DANGER
	banner.Visible = true
	task.delay(3, function()
		if bannerToken == mine then banner.Visible = false end
	end)
end

local function setHint(msg: string, seconds: number)
	hintOverride = msg
	hintUntil = now() + seconds
end

local function paint()
	if not S then return end
	local run = S.run
	if S.phase == "hub" then
		statusTop.Text = "BREAK ROOM"
		statusSub.Text = string.format("ESSENCE %d   DEEPEST %d", S.essence or 0, S.bestSublevel or 0)
	elseif run then
		statusTop.Text = "SUBLEVEL " .. tostring(run.k)
		statusSub.Text = string.format("FUSES %d/%d", (run.fuses or 0) + (run.fusesIn or 0), run.fusesNeeded or 0)
	end
	if run then
		local frac = if run.batteryCap > 0 then math.clamp(run.battery / run.batteryCap, 0, 1) else 0
		powerTop.Text = string.format("BATTERY %d s%s", math.ceil(run.battery - 1e-6), if run.lightOn then "  LIGHT ON" else "")
		bar.Size = UDim2.fromScale(frac, 1)
		bar.BackgroundColor3 = if frac < 0.2 then DANGER else ACCENT
		powerSub.Text = string.format("RUN %d ESSENCE   KEEP %d%%", run.runEssence or 0, run.keepPercent or 0)
		lightButton.Text = if run.lightOn then "LIGHT: ON" else "LIGHT"
		sprintButton.Text = if run.sprinting then "SPRINTING" else "SPRINT"
	end

	boarding.Visible = S.phase == "hub" and (S.boarding or 0) > 0
	boardBar.Size = UDim2.fromScale(S.boarding or 0, 1)

	-- the hint line: an event's hint wins for a few seconds, then the standing one
	local h = ""
	if hintOverride and now() < hintUntil then
		h = hintOverride
	elseif S.phase == "hub" then
		if S.storeless then
			h = "Saving is off on this server — progress will not be kept. Walk into the elevator."
		elseif not S.loaded then
			h = "Loading your file…"
		else
			h = "Walk into the elevator to go down."
		end
	elseif S.phase == "ride" then
		h = "Going down…"
	elseif S.phase == "floor" and run then
		local have, needed = (run.fuses or 0) + (run.fusesIn or 0), run.fusesNeeded or 0
		if run.dark and not run.lightOn then
			h = "Your room is dark — turn on your flashlight (F / LIGHT)."
		elseif run.flicker then
			h = "Your room is going dark — turn on your flashlight."
		elseif run.powered and run.atLift then
			h = if UserInputService.TouchEnabled then "EXTRACT to bank it, or DESCEND for more."
				else "EXTRACT (E) to bank it, or DESCEND (Q) for more."
		elseif run.powered then
			h = "Back to the freight elevator to EXTRACT or DESCEND."
		elseif have >= needed then
			h = "You have every fuse. Find the freight elevator."
		elseif have == 0 then
			h = string.format("Find %d fuses. Bring them to the elevator.", needed)
		else
			-- what is still MISSING (REVIEW-1 B3: a player with 2 of 3 in read "Find 3 fuses")
			local missing = needed - have
			h = string.format("Find %d more fuse%s. Bring them to the elevator.", missing, if missing == 1 then "" else "s")
		end
	end
	hint.Text = h

	if perksOpen and S.perkRows then
		perksTitle.Text = string.format("PERKS — %d ESSENCE", S.essence or 0)
		for _, r in S.perkRows do
			local row = perkRows[r.id]
			if row then
				row.name.Text = string.format("%s  %d/%d", r.name, r.rank, r.max)
				if r.price then
					row.buy.Text = tostring(r.price)
					row.buy.TextColor3 = if (S.essence or 0) >= r.price then ACCENT else MUTED
				else
					row.buy.Text = "MAX"
					row.buy.TextColor3 = MUTED
				end
			end
		end
	end
end

StateEvent.OnClientEvent:Connect(function(s)
	local wasPhase = S and S.phase
	S = s
	if s.phase ~= "hub" then
		perksOpen = false
	end
	if wasPhase ~= s.phase then
		applyLayout()
	end
	paint()
	applyLayout()
end)

--============================================================================ notices

NoticeEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "toast" then
		showToast(tostring(data))
	elseif kind == "perks" then
		perksOpen = true
	elseif kind == "boarding" then
		setHint("Going down…", 2)
	elseif kind == "sublevel" then
		showBanner("SUBLEVEL " .. tostring(data.k), ACCENT)
		FxClient.shake(0.6, 0.8)
	elseif kind == "arrive" then
		-- the server cleared both requests on arrival; keep this side's idea of them in step
		wantSprint = false
		setHint(string.format("Find %d fuses. Bring them to the elevator.", data.fuses), 6)
	elseif kind == "powerFailing" then
		showBanner("THE POWER IS FAILING — STAY IN THE LIGHT")
		setHint("F / LIGHT button: flashlight. It drains your battery.", 6)
	elseif kind == "roomDying" then
		setHint("Your room is going dark — turn on your flashlight.", 3)
	elseif kind == "roomDied" then
		-- DESIGN.md §11.4: the room the player is standing in has just died around them
		FxClient.shake(0.5, 0.6)
	elseif kind == "batteryEmpty" then
		showToast("Battery empty — find a green cell.")
	elseif kind == "fuse" then
		FxClient.fovPunch(-3, 0.06, 0.2)
		showToast(string.format("FUSE %d/%d", data.held + data.fusesIn, data.needed), 2)
	elseif kind == "cell" then
		showToast("Battery cell +" .. Config.Battery.CellSeconds .. " s", 2)
	elseif kind == "inserted" then
		showToast(string.format("Fuses in: %d/%d", data.fusesIn, data.needed), 3)
	elseif kind == "choice" then
		perksOpen = false
		choiceBody.Text = string.format("EXTRACT: bank %d Essence.  DESCEND: sublevel %d pays +%d; if the dark takes you, you keep %d%%.",
			data.bank, data.k + 1, data.nextPay, data.keepPercent)
		FxClient.flash(GOOD, 0.25, 0.5)
	elseif kind == "extracted" then
		showBanner(string.format("BANKED %d ESSENCE", data.banked), GOOD)
		FxClient.flash(GOOD, 0.35, 0.7)
	elseif kind == "death" then
		deathText.Text = string.format("THE DARK TOOK YOU — kept %d of %d Essence", data.kept, data.of)
		deathCard.Visible = true
		FxClient.shake(0.8, 2)
		FxClient.flash(DANGER, 0.5, 0.8)
		task.delay(Config.Run.DeathBeatSeconds + 0.3, function()
			deathCard.Visible = false
		end)
	elseif kind == "secondWind" then
		showBanner("SECOND WIND", GOOD)
		FxClient.flash(GOOD, 0.4, 0.6)
	elseif kind == "purchased" then
		showToast(string.format("%s rank %d", data.name, data.rank), 3)
	end
	paint()
	applyLayout()
end)

--============================================================================ input

local function setLight(on: boolean)
	FlashlightEvent:FireServer(on)
end
-- A held key (Shift) sends a press and a release, once each.
local function setSprint(on: boolean)
	if wantSprint == on then return end
	wantSprint = on
	SprintEvent:FireServer(on)
end
-- A tap (the SPRINT button, gamepad L3) asks for the OPPOSITE of what the server last said it is
-- doing, and always sends: after the bar runs out the request is still "on" here while the server
-- is walking, and a tap must mean "sprint" then, not "release" (the server re-arms on a press).
local function toggleSprint()
	local on = not (S ~= nil and S.run ~= nil and S.run.sprinting == true)
	wantSprint = on
	SprintEvent:FireServer(on)
end

lightButton.Activated:Connect(function()
	setLight(not (S and S.run and S.run.lightOn))
end)
sprintButton.Activated:Connect(toggleSprint)
perksButton.Activated:Connect(function()
	perksOpen = true
	paint()
	applyLayout()
end)
perksClose.Activated:Connect(function()
	perksOpen = false
	applyLayout()
end)
extractButton.Activated:Connect(function()
	ChooseEvent:FireServer("extract")
end)
descendButton.Activated:Connect(function()
	ChooseEvent:FireServer("descend")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local inFloor = S ~= nil and S.phase == "floor"
	local kc = input.KeyCode
	if kc == Enum.KeyCode.F or kc == Enum.KeyCode.ButtonY then
		if inFloor then setLight(not (S.run and S.run.lightOn)) end
	elseif kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then
		if inFloor then setSprint(true) end
	elseif kc == Enum.KeyCode.ButtonL3 then
		if inFloor then toggleSprint() end
	elseif kc == Enum.KeyCode.E or kc == Enum.KeyCode.Q then
		-- only while the choice is on screen (REVIEW-1 B1: with the cursor pinned, a PC player had no
		-- way to press either button)
		if choice.Visible then
			ChooseEvent:FireServer(if kc == Enum.KeyCode.E then "extract" else "descend")
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local kc = input.KeyCode
	if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
local okTouch, touchErr = pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
if not okTouch then
	warn("[Facility] no TouchEnabled listener; layout follows the viewport only: " .. tostring(touchErr))
end

--============================================================================ the apparition, hidden by the CLIENT

-- It changes no rule, so hiding it is presentation (DESIGN.md §2.6): once it has been on screen
-- MinVisibleSeconds and the camera turns HideAngle away, or the character comes within HideRadius,
-- it vanishes for this player. LocalTransparencyModifier never replicates.
local seen: { [Instance]: number } = {}
local hidden: { [Instance]: boolean } = {}
local cosHide = math.cos(math.rad(Config.Apparition.HideAngle))
task.spawn(function()
	while true do
		task.wait(0.1)
		local fac = workspace:FindFirstChild("Facility")
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if fac and hrp and camera then
			for _, zone in fac:GetChildren() do
				local fl = zone:FindFirstChild("Floor")
				local fig = fl and fl:FindFirstChild("Apparition")
				local head = fig and fig:FindFirstChild("Torso")
				if fig and head and not hidden[fig] then
					local toFig = (head :: BasePart).Position - camera.CFrame.Position
					local dist = toFig.Magnitude
					if dist < 120 then
						local look = camera.CFrame.LookVector
						local cosA = if dist > 0 then look:Dot(toFig / dist) else 1
						if cosA >= cosHide and seen[fig] == nil then
							seen[fig] = now()
						end
						local near = ((head :: BasePart).Position - (hrp :: BasePart).Position).Magnitude < Config.Apparition.HideRadius
						local lookedAway = seen[fig] ~= nil and now() - seen[fig] >= Config.Apparition.MinVisibleSeconds and cosA < cosHide
						if near or lookedAway then
							hidden[fig] = true
							for _, p in fig:GetChildren() do
								if p:IsA("BasePart") then
									(p :: BasePart).LocalTransparencyModifier = 1
								end
							end
						end
					end
				end
			end
		end
	end
end)

-- the hint's timeout and the vignette's pulse need a slow repaint even without a State push
task.spawn(function()
	while true do
		task.wait(0.5)
		paint()
		if S and S.run and S.phase == "floor" and (S.run.exposure or 0) > 0.5 then
			FxClient.shake(0.25, 0.3)
		end
	end
end)
