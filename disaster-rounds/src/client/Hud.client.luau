-- DISASTER ROUNDS - the HUD (client, display only). Lives in StarterPlayerScripts.
--
-- Phone first (docs/new-game-checklist.md §2b, DESIGN.md §12): one root Frame owns the UIScale and is sized 1/scale;
-- layout re-runs on ViewportSize and TouchEnabled; every panel is a Frame at depth 2 so robloxemu's hudcheck can
-- measure overlaps (rule 4b, overlap = true); nothing tappable at the bottom; tap targets >= 44 screen px on touch.
--
--   top left    StatsPanel   🔥 Heat, streak and best, the band chip, survivals (not tappable)
--   top centre  PhasePanel   the phase and its clock, the rule line; under it ▶ Jump in (practice); under that the
--               BannerPanel  threat banner ("⚠️ MOVE — a ring is under you")
--   top right   ButtonsPanel ☕ Rest and 📖 Codex
--   centre      CardPanel    the name, SURVIVED, swept out, the brag (gone after 2.5 s); ToastPanel under it
--   modal       CodexPanel   4 disasters x Heat 0-5; opening it hides every other panel
--
-- Everything here is read from replicated state: Player attributes, workspace.Round attributes and the Card/Toast
-- remotes. The only things it sends are a Jump-in request and the rest button (to Sky.client, which owns rest).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Round = require(ReplicatedStorage:WaitForChild("Round"))
local MapGen = require(ReplicatedStorage:WaitForChild("MapGen"))
local Zones = require(ReplicatedStorage:WaitForChild("Zones"))
local Tornado = require(ReplicatedStorage:WaitForChild("Tornado"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end
local remotes = ReplicatedStorage:WaitForChild("DRRemotes")
local ToastEvent = remotes:WaitForChild("Toast")
local CardEvent = remotes:WaitForChild("Card")
local JumpInEvent = remotes:WaitForChild("JumpIn")
local roundFolder = workspace:WaitForChild("Round")

local Info = Config.Disasters.Info
local bands = Config.Env.Bands

--============================================================================== the clock

-- The server's clock, extrapolated at most 1.5 s past its last 1 Hz update (DESIGN.md §2.3).
local lastServerNow, lastLocal = workspace:GetAttribute("ServerNow") or 0, tick()
workspace:GetAttributeChangedSignal("ServerNow"):Connect(function()
	lastServerNow = workspace:GetAttribute("ServerNow") or 0
	lastLocal = tick()
end)
local function serverNow(): number
	return lastServerNow + math.min(1.5, tick() - lastLocal)
end

--============================================================================== the gui

local MARGIN, GAP, MIN_TAP = Responsive.MARGIN, 8, 44
local STATS_W, STATS_H, STATS_H_COMPACT = 220, 86, 74
local PHASE_H, PHASE_H_COMPACT = 58, 52
local BTN_W, BTN_H = 92, 40
local JUMP_W, JUMP_H = 240, 44
local BANNER_H = 36
local CARD_W, CARD_H = 560, 96
local TOAST_H = 34

local gui = Instance.new("ScreenGui")
gui.Name = "DRHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")
-- the rest button lives here; the rest RULES live in Sky.client (it owns the strays the rest freezes)
local restRequest = Instance.new("BindableEvent")
restRequest.Name = "RestRequest"
restRequest.Parent = gui
gui:SetAttribute("RestState", "off")
-- client-side lines from Sky.client (rest replies, band changes): shown exactly like the server's
local localToastEvent = Instance.new("BindableEvent")
localToastEvent.Name = "LocalToast"
localToastEvent.Parent = gui
local localCardEvent = Instance.new("BindableEvent")
localCardEvent.Name = "LocalCard"
localCardEvent.Parent = gui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function panel(name: string, transparency: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = root
	corner(f, 10)
	pcall(function() FxClient.theme(f) end)
	return f
end
local function text(parent: Instance, name: string, font, color: Color3, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextColor3 = color
	l.TextScaled = true
	l.Text = ""
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end
local function button(parent: Instance, name: string, label: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextScaled = true
	b.Text = label
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 18
	c.Parent = b
	return b
end

local WHITE = Color3.fromRGB(240, 244, 255)
local DIM = Color3.fromRGB(176, 186, 210)
local GOLD = Color3.fromRGB(255, 210, 90)
local FLAME = Color3.fromRGB(255, 160, 60)

-- top left: the player's own numbers
local stats = panel("StatsPanel", 0.25)
local heatLine = text(stats, "Heat", Enum.Font.GothamBlack, FLAME, 22)
local streakLine = text(stats, "Streak", Enum.Font.GothamBold, WHITE, 16)
local bandLine = text(stats, "Band", Enum.Font.GothamMedium, DIM, 15)

-- top centre: the phase
local phase = panel("PhasePanel", 0.2)
local phaseLine = text(phase, "PhaseText", Enum.Font.GothamBlack, WHITE, 22)
phaseLine.TextXAlignment = Enum.TextXAlignment.Center
local ruleLine = text(phase, "RuleText", Enum.Font.GothamBold, GOLD, 16)
ruleLine.TextXAlignment = Enum.TextXAlignment.Center

local jumpIn = button(root, "JumpInButton", "▶ Jump in (practice)", Color3.fromRGB(46, 150, 96))
jumpIn.Visible = false

local banner = panel("BannerPanel", 0.1)
banner.BackgroundColor3 = Color3.fromRGB(120, 20, 24)
banner.Visible = false
local bannerText = text(banner, "BannerText", Enum.Font.GothamBlack, Color3.fromRGB(255, 236, 140), 20)
bannerText.TextXAlignment = Enum.TextXAlignment.Center

-- top right: rest + codex
local buttons = panel("ButtonsPanel", 1)
local restBtn = button(buttons, "RestButton", "☕ Rest", Color3.fromRGB(70, 110, 170))
local codexBtn = button(buttons, "CodexButton", "📖 Codex", Color3.fromRGB(110, 80, 160))

-- centre: cards and toasts (never tappable)
local card = panel("CardPanel", 0.15)
card.Visible = false
local cardTitle = text(card, "CardTitle", Enum.Font.GothamBlack, WHITE, 34)
cardTitle.TextXAlignment = Enum.TextXAlignment.Center
local cardSub = text(card, "CardSub", Enum.Font.GothamBold, DIM, 18)
cardSub.TextXAlignment = Enum.TextXAlignment.Center

local toastPanel = panel("ToastPanel", 0.2)
toastPanel.Visible = false
local toastText = text(toastPanel, "ToastText", Enum.Font.GothamBold, WHITE, 17)
toastText.TextXAlignment = Enum.TextXAlignment.Center

-- the Codex modal
local codex = panel("CodexPanel", 0.05)
codex.Visible = false
local codexTitle = text(codex, "CodexTitle", Enum.Font.GothamBlack, GOLD, 24)
codexTitle.TextXAlignment = Enum.TextXAlignment.Center
codexTitle.Text = "📖 CODEX — the hottest Heat you survived"
local codexClose = button(codex, "CodexClose", "✕ Close", Color3.fromRGB(90, 90, 110))
local codexHint = text(codex, "CodexHint", Enum.Font.GothamMedium, DIM, 15)
codexHint.TextXAlignment = Enum.TextXAlignment.Center
local codexCells: { [string]: { TextLabel } } = {}
local codexRowLabels: { [string]: TextLabel } = {}
for _, k in Config.Disasters.Kinds do
	codexRowLabels[k] = text(codex, "Row_" .. k, Enum.Font.GothamBold, WHITE, 16)
	codexCells[k] = {}
	for h = 0, 5 do
		local c = text(codex, "Cell_" .. k .. "_" .. h, Enum.Font.GothamBlack, WHITE, 16)
		c.BackgroundTransparency = 0.2
		c.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
		c.TextXAlignment = Enum.TextXAlignment.Center
		c.Text = "🔥" .. h
		corner(c, 6)
		codexCells[k][h] = c
	end
end

--============================================================================== layout

local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
-- On touch, a tap target is at least MIN_TAP SCREEN px: the design size, or more where the UIScale shrinks it.
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	local need = math.ceil(MIN_TAP / layout.scale) + 1
	return math.max(designPx, need)
end

local rootW, rootH = Responsive.REF_X, Responsive.REF_Y
local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	local vyDraw = math.max(1, vy - inset)
	layout = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	rootW, rootH = vx / layout.scale, vyDraw / layout.scale
	local compact = layout.compact

	-- top right: two buttons side by side
	local bw, bh = touchSize(BTN_W), touchSize(BTN_H)
	local buttonsW = 2 * bw + GAP
	buttons.Size = UDim2.fromOffset(buttonsW, bh)
	buttons.Position = UDim2.fromOffset(rootW - MARGIN - buttonsW, MARGIN)
	restBtn.Size = UDim2.fromOffset(bw, bh)
	restBtn.Position = UDim2.fromOffset(0, 0)
	codexBtn.Size = UDim2.fromOffset(bw, bh)
	codexBtn.Position = UDim2.fromOffset(bw + GAP, 0)

	-- top left: the stats panel
	local sw = Responsive.sideWidth(STATS_W, vx, layout)
	local sh = if compact then STATS_H_COMPACT else STATS_H
	stats.Size = UDim2.fromOffset(sw, sh)
	stats.Position = UDim2.fromOffset(MARGIN, MARGIN)
	heatLine.Position = UDim2.fromOffset(10, 4)
	heatLine.Size = UDim2.fromOffset(sw - 20, sh * 0.36)
	streakLine.Position = UDim2.fromOffset(10, 4 + sh * 0.36)
	streakLine.Size = UDim2.fromOffset(sw - 20, sh * 0.28)
	bandLine.Position = UDim2.fromOffset(10, 4 + sh * 0.64)
	bandLine.Size = UDim2.fromOffset(sw - 20, sh * 0.3)

	-- top centre, between the two
	local left = MARGIN + sw + GAP
	local right = rootW - MARGIN - buttonsW - GAP
	local pw = math.max(120, right - left)
	local ph = if compact then PHASE_H_COMPACT else PHASE_H
	phase.Size = UDim2.fromOffset(pw, ph)
	phase.Position = UDim2.fromOffset(left, MARGIN)
	phaseLine.Position = UDim2.fromOffset(8, 2)
	phaseLine.Size = UDim2.fromOffset(pw - 16, ph * 0.55)
	ruleLine.Position = UDim2.fromOffset(8, 2 + ph * 0.55)
	ruleLine.Size = UDim2.fromOffset(pw - 16, ph * 0.4)

	local y = MARGIN + math.max(ph, sh, bh) + GAP
	local jw, jh = math.min(touchSize(JUMP_W), pw), touchSize(JUMP_H)
	jumpIn.Size = UDim2.fromOffset(jw, jh)
	jumpIn.Position = UDim2.fromOffset(left + (pw - jw) / 2, y)
	local bannerY = y + jh + GAP
	banner.Size = UDim2.fromOffset(pw, BANNER_H)
	banner.Position = UDim2.fromOffset(left, bannerY)
	bannerText.Position = UDim2.fromOffset(6, 2)
	bannerText.Size = UDim2.fromOffset(pw - 12, BANNER_H - 4)

	-- centre: the card under the banner, the toast under the card
	local cw = math.min(CARD_W, rootW - 2 * MARGIN)
	local ch = math.min(CARD_H, math.max(60, rootH * 0.18))
	local cardY = math.max(bannerY + BANNER_H + GAP, rootH * 0.3)
	card.Size = UDim2.fromOffset(cw, ch)
	card.Position = UDim2.fromOffset((rootW - cw) / 2, cardY)
	cardTitle.Position = UDim2.fromOffset(10, 4)
	cardTitle.Size = UDim2.fromOffset(cw - 20, ch * 0.58)
	cardSub.Position = UDim2.fromOffset(10, 4 + ch * 0.58)
	cardSub.Size = UDim2.fromOffset(cw - 20, ch * 0.36)
	local tw = math.min(520, rootW - 2 * MARGIN)
	toastPanel.Size = UDim2.fromOffset(tw, TOAST_H)
	toastPanel.Position = UDim2.fromOffset((rootW - tw) / 2, cardY + ch + GAP)
	toastText.Position = UDim2.fromOffset(8, 2)
	toastText.Size = UDim2.fromOffset(tw - 16, TOAST_H - 4)

	-- the Codex, centred, inside the screen
	local xw = math.min(600, rootW - 2 * MARGIN)
	local xh = math.min(330, rootH - 2 * MARGIN)
	codex.Size = UDim2.fromOffset(xw, xh)
	codex.Position = UDim2.fromOffset((rootW - xw) / 2, (rootH - xh) / 2)
	local closeW, closeH = touchSize(90), touchSize(34)
	codexClose.Size = UDim2.fromOffset(closeW, closeH)
	codexClose.Position = UDim2.fromOffset(xw - closeW - 8, 8)
	codexTitle.Position = UDim2.fromOffset(8, 8)
	codexTitle.Size = UDim2.fromOffset(xw - closeW - 24, closeH)
	local gridTop = 8 + closeH + 8
	local hintH = 24
	local rowH = math.max(20, (xh - gridTop - hintH - 16) / 4)
	local labelW = math.min(150, xw * 0.28)
	local cellW = (xw - labelW - 24) / 6
	for r, k in Config.Disasters.Kinds do
		local ry = gridTop + (r - 1) * rowH
		codexRowLabels[k].Position = UDim2.fromOffset(8, ry)
		codexRowLabels[k].Size = UDim2.fromOffset(labelW - 8, rowH - 4)
		for h = 0, 5 do
			codexCells[k][h].Position = UDim2.fromOffset(labelW + h * cellW, ry)
			codexCells[k][h].Size = UDim2.fromOffset(cellW - 4, rowH - 4)
		end
	end
	codexHint.Position = UDim2.fromOffset(8, xh - hintH - 8)
	codexHint.Size = UDim2.fromOffset(xw - 16, hintH)
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

--============================================================================== the Codex

local codexOpen = false
local function codexValues(): { [string]: number }
	local out = {}
	local s = player:GetAttribute("Codex")
	local parts = {}
	if type(s) == "string" then
		for n in string.gmatch(s, "[^,]+") do table.insert(parts, tonumber(n) or -1) end
	end
	for i, k in Config.Disasters.Kinds do out[k] = parts[i] or -1 end
	return out
end
local function drawCodex()
	local vals = codexValues()
	local hint = nil
	local filled = 0
	for _, k in Config.Disasters.Kinds do
		local info = Info[k]
		codexRowLabels[k].Text = info.icon .. " " .. string.lower(info.name):gsub("^%l", string.upper)
		for h = 0, 5 do
			local on = vals[k] >= h
			local c = codexCells[k][h]
			c.BackgroundColor3 = if on then Color3.fromRGB(230, 150, 50) else Color3.fromRGB(40, 44, 60)
			c.TextColor3 = if on then Color3.fromRGB(255, 250, 230) else Color3.fromRGB(120, 126, 150)
			if on then filled += 1 end
			if not on and hint == nil then
				hint = string.format("Survive a %s at 🔥%d to fill this", string.lower(info.name):gsub("^%l", string.upper), h)
			end
		end
	end
	codexHint.Text = (hint or "All 24 filled. The Codex is complete!") .. string.format("   (%d of 24)", filled)
end
local hideable = { stats, phase, banner, buttons, card, toastPanel }
local wasVisible: { [Instance]: boolean } = {}
local function setCodex(open: boolean)
	if open == codexOpen then return end
	codexOpen = open
	if open then
		drawCodex()
		for _, f in hideable do
			wasVisible[f] = f.Visible
			f.Visible = false
		end
		jumpIn.Visible = false
		codex.Visible = true
	else
		codex.Visible = false
		for _, f in hideable do
			if f == stats or f == phase or f == buttons then f.Visible = true end
		end
	end
end
codexBtn.Activated:Connect(function() setCodex(true) end)
codexClose.Activated:Connect(function() setCodex(false) end)
player:GetAttributeChangedSignal("Codex"):Connect(function() if codexOpen then drawCodex() end end)

--============================================================================== cards and toasts

local cardToken = 0
local function showCard(title: string, sub: string, color: Color3?, seconds: number?)
	if codexOpen then return end
	cardToken += 1
	local mine = cardToken
	cardTitle.Text = title
	cardTitle.TextColor3 = color or WHITE
	cardSub.Text = sub
	card.Visible = true
	task.delay(seconds or 2.5, function()
		if cardToken == mine then card.Visible = false end
	end)
end

local toastQueue: { string } = {}
local toastBusy = false
local function pumpToasts()
	if toastBusy then return end
	toastBusy = true
	task.spawn(function()
		while #toastQueue > 0 do
			local t = table.remove(toastQueue, 1)
			toastText.Text = t
			toastPanel.Visible = not codexOpen
			task.wait(3)
		end
		toastPanel.Visible = false
		toastBusy = false
	end)
end
local function toast(t: string)
	if #toastQueue >= 4 then table.remove(toastQueue, 1) end
	table.insert(toastQueue, t)
	pumpToasts()
end
ToastEvent.OnClientEvent:Connect(function(t)
	if type(t) == "string" then toast(t) end
end)
localToastEvent.Event:Connect(function(t)
	if type(t) == "string" then toast(t) end
end)
localCardEvent.Event:Connect(function(title, sub)
	if type(title) == "string" then showCard(title, if type(sub) == "string" then sub else "", Color3.fromRGB(200, 230, 255), 3) end
end)

local function kindTitle(kind: string): string
	local info = Info[kind]
	return if info then info.icon .. " " .. info.name else "?"
end

CardEvent.OnClientEvent:Connect(function(kind, data)
	data = if type(data) == "table" then data else {}
	if kind == "name" then
		local info = Info[data.kind]
		if info then showCard(kindTitle(data.kind), info.rule, GOLD, 2.5) end
	elseif kind == "drop" then
		showCard("Get ready…", "Something is coming. Red always shows where it hits.", WHITE, 2.5)
	elseif kind == "practice-start" then
		showCard("Practice round", "It won't count. Step out of the red!", Color3.fromRGB(150, 230, 170), 2.5)
	elseif kind == "survived" then
		local heat = tonumber(data.heat) or 0
		showCard(string.format("SURVIVED! 🔥 streak %d", tonumber(data.streak) or 0),
			if data.newBest then "New best streak!" elseif heat > 0 then "Heat " .. heat .. ": more of it aims at you" else "Keep the streak going",
			GOLD, 2.5)
		pcall(function()
			FxClient.flash(Color3.fromRGB(255, 240, 200), 0.35, 0.6)
			FxClient.fovPunch(6, 0.1, 0.5)
		end)
	elseif kind == "swept" then
		local nextIn = Round.clock(tonumber(data.nextIn) or 0)
		local sub = if data.practice then "Practice over — next round in " .. nextIn
			else string.format("Streak lost. Next round in %s", nextIn)
		showCard(tostring(data.text or "Swept away"), sub, Color3.fromRGB(255, 190, 170), 2.5)
		pcall(function() FxClient.flash(Color3.fromRGB(200, 220, 255), 0.25, 0.4) end)
	elseif kind == "practice" then
		showCard("Practice over", "It didn't count. You're in the next round.", WHITE, 2.5)
	elseif kind == "dodged" then
		showCard("Dodged!", "That's the rule: out of the red, safe.", Color3.fromRGB(150, 230, 255), 1.5)
	elseif kind == "brag" then
		showCard("☄️ THE SKY IS FALLING", tostring(tonumber(data.survived) or 21) .. " disasters survived", Color3.fromRGB(255, 200, 120), 4)
		pcall(function()
			FxClient.flash(Color3.fromRGB(255, 255, 255), 0.45, 0.9)
			FxClient.fovPunch(8, 0.12, 0.6)
		end)
	end
end)

--============================================================================== buttons

jumpIn.Activated:Connect(function()
	JumpInEvent:FireServer()
end)
restBtn.Activated:Connect(function()
	restRequest:Fire()
end)

--============================================================================== the frame

local function bandIndex(): number
	local s = player:GetAttribute("Survived")
	return EnvBands.indexAt(bands, if type(s) == "number" then s else 0)
end

-- the threat under the local player right now, from the replicated red (DESIGN.md §11)
local function threatText(t: number): string?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or (player:GetAttribute("InRound") or "") == "" then return nil end
	local p = hrp.Position
	local rings = roundFolder:FindFirstChild("Rings")
	if rings then
		for _, r in rings:GetChildren() do
			local radius = r:GetAttribute("Radius")
			local impact = r:GetAttribute("ImpactAt")
			if type(radius) == "number" and type(impact) == "number" and t < impact + 0.2
				and Zones.inDisk(r.Position.X, r.Position.Z, radius, p.X, p.Z) then
				return "⚠️ MOVE — a ring is under you"
			end
		end
	end
	local kind = roundFolder:GetAttribute("Kind")
	local island = roundFolder:FindFirstChild("Island")
	if kind == "flood" and island then
		local warnLevel = roundFolder:GetAttribute("WarnLevel")
		local riseAt = roundFolder:GetAttribute("RiseAt")
		local riseEnd = roundFolder:GetAttribute("RiseEnd")
		local i, j = MapGen.cellAt(Config.Island, p.X, p.Z)
		if i and j and type(warnLevel) == "number" and type(riseEnd) == "number" and t < riseEnd then
			local cell = island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
			local level = cell and cell:GetAttribute("Level")
			if type(level) == "number" and level <= warnLevel then
				local inS = math.max(0, (riseAt or t) - t)
				return if inS > 0 then string.format("🌊 Water rising in %d — get above the red line", math.ceil(inS))
					else "🌊 The water is rising — climb!"
			end
		end
	elseif kind == "tornado" then
		local t0, pts = Tornado.decode(roundFolder:GetAttribute("Path"))
		if t0 and pts then
			local r = Config.Tornado.HitRadius + Config.Hits.PlayerRadius
			for _, q in pts do
				if Zones.inDisk(q.x, q.z, r, p.X, p.Z) then return "🌪️ GET OFF the red path" end
			end
		end
	elseif kind == "quake" and island then
		local i, j = MapGen.cellAt(Config.Island, p.X, p.Z)
		local cell = i and j and island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
		if cell and cell:GetAttribute("CrackAt") ~= nil and cell:GetAttribute("Dropped") ~= true then
			return "🏚️ The ground is cracking — step off!"
		end
	end
	return nil
end

local frameError = false
local function frame()
	local t = serverNow()
	local phaseName = roundFolder:GetAttribute("Phase") or "intermission"
	local ends = roundFolder:GetAttribute("PhaseEnds") or t
	local kind = roundFolder:GetAttribute("Kind")
	local inRound = player:GetAttribute("InRound") or ""
	local resting = player:GetAttribute("Resting") == true
	local played = player:GetAttribute("Played") or 0
	local restState = gui:GetAttribute("RestState") or "off"

	-- stats
	local heat = player:GetAttribute("Heat") or 0
	local streak = player:GetAttribute("Streak") or 0
	local best = player:GetAttribute("Best") or 0
	local survived = player:GetAttribute("Survived") or 0
	heatLine.Text = if heat > 0 then string.rep("🔥", math.min(heat, 5)) .. " Heat " .. heat else "Heat 0 · calm"
	streakLine.Text = string.format("Streak %d · best %d · 🏆 %d", streak, best, survived)
	local bi = bandIndex()
	local b = bands[bi]
	local nb = bands[bi + 1]
	bandLine.Text = b.emoji .. " " .. b.name .. (if nb then string.format(" · %s at %d", nb.emoji, nb.from) else "")

	-- phase and rule
	local clock = Round.clock(ends - t)
	local pText, rText
	if player:GetAttribute("Loaded") ~= true then
		pText = "Loading…"
		rText = "Red always shows where it hits."
	elseif resting or restState == "resting" then
		pText = "☕ On a break"
		rText = "Move or tap ☕ to rejoin the rounds"
	elseif phaseName == "intermission" then
		pText = "Next round " .. clock
		rText = if played < 3 then "You're in! Survive the disaster. Red always shows where it hits." else "Get ready. Red shows where it hits."
		if restState == "queued" or restState == "after" then rText = "☕ Break after this round" end
	elseif phaseName == "drop" then
		pText = "🏝️ Landing… " .. clock
		rText = if inRound == "" then "A round is starting" else "Get ready…"
	elseif phaseName == "disaster" and kind then
		pText = kindTitle(kind) .. " · " .. clock
		rText = if inRound == "" then "That's a " .. Info[kind].name .. " — " .. string.lower(Info[kind].rule) else Info[kind].rule
		if restState == "after" then rText = "☕ Break after this round" end
	else
		pText = "Round over"
		rText = "Back to the Lookout"
	end
	if phaseLine.Text ~= pText then phaseLine.Text = pText end
	if ruleLine.Text ~= rText then ruleLine.Text = rText end

	-- the Jump-in button: only when the server would take it
	local swept = player:GetAttribute("SweptRound") == roundFolder:GetAttribute("RoundId")
	local rid = roundFolder:GetAttribute("RoundId")
	local open = false
	if inRound == "" and not resting and not swept and rid ~= nil then
		if phaseName == "drop" then
			open = true
		elseif phaseName == "disaster" then
			local nameAt = roundFolder:GetAttribute("NameAt")
			open = type(nameAt) == "number" and t - nameAt < Config.Round.PracticeUntilSeconds
		end
	end
	jumpIn.Visible = open and not codexOpen

	-- the banner
	local threat = threatText(t)
	banner.Visible = threat ~= nil and not codexOpen
	if threat and bannerText.Text ~= threat then bannerText.Text = threat end

	-- the rest button
	local rb = if resting or restState == "resting" then "▶ Play" elseif restState == "queued" or restState == "after" then "☕ …" else "☕ Rest"
	if restBtn.Text ~= rb then restBtn.Text = rb end
end

RunService.RenderStepped:Connect(function()
	local ok, err = pcall(frame)
	if not ok and not frameError then
		frameError = true
		warn("[DisasterRounds] HUD frame error: " .. tostring(err))
	end
end)
pcall(frame)
