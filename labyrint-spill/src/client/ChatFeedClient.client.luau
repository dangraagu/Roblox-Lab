--[[==================================================================
	LABYRINT-SPILL  -  GLOBAL-CHAT-FEED (klient)
	Laget for Marius & onkel :)

	Viser de siste meldingene fra chat-en ØVERST på skjermen (et lite, lesbart
	utdrag), i tillegg til den vanlige chat-boksen nede. Bare visning — man
	skriver fortsatt i den vanlige chatten. Alt spiller-synlig er engelsk.

	Bruker moderne TextChatService (standard i nye Roblox-opplevelser). Meldingene
	som kommer inn er allerede filtrert av Roblox, så vi bare tegner dem.
==================================================================]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAX_LINES = 4  -- hvor mange siste meldinger som vises

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("ChatFeed")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ChatFeed"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 8            -- under HUD (12) og butikk-vinduer
gui.Parent = playerGui

-- Panel øverst-i-midten, RETT under HUD/daglig-belønning-sonen. Vokser nedover
-- med antall linjer (AutomaticSize). Halvgjennomsiktig så det ikke stjeler fokus.
local panel = Instance.new("Frame")
panel.Name = "Feed"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 172)
panel.Size = UDim2.new(0.5, 0, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Active = false            -- ikke fang trykk (viktig på mobil)
panel.Parent = gui

local sizeC = Instance.new("UISizeConstraint")
sizeC.MaxSize = Vector2.new(460, 260)
sizeC.MinSize = Vector2.new(240, 0)
sizeC.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 78, 100)
stroke.Thickness = 1
stroke.Transparency = 0.3
stroke.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = panel

-- Liten overskrift.
local header = Instance.new("TextLabel")
header.Name = "Header"
header.LayoutOrder = 0
header.Size = UDim2.new(1, 0, 0, 16)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBold
header.TextSize = 12
header.TextColor3 = Color3.fromRGB(150, 200, 255)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "💬 Chat"
header.Parent = panel

-- Plassholder til første melding kommer.
local placeholder = Instance.new("TextLabel")
placeholder.Name = "Placeholder"
placeholder.LayoutOrder = 1
placeholder.Size = UDim2.new(1, 0, 0, 18)
placeholder.BackgroundTransparency = 1
placeholder.Font = Enum.Font.GothamMedium
placeholder.TextSize = 14
placeholder.TextColor3 = Color3.fromRGB(150, 156, 170)
placeholder.TextXAlignment = Enum.TextXAlignment.Left
placeholder.TextTruncate = Enum.TextTruncate.AtEnd
placeholder.Text = "Chat appears here…"
placeholder.Parent = panel

--==========================  LINJER  ============================--
local lines = {}       -- rullerende liste av melding-etiketter (eldst først)
local nextOrder = 2    -- LayoutOrder teller (0 = header, 1 = placeholder)

local function addLine(text)
	if placeholder then placeholder:Destroy(); placeholder = nil end

	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 14
	l.TextColor3 = Color3.fromRGB(232, 236, 244)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd  -- én linje, klippes pent om lang
	l.RichText = false                        -- rå tekst: ingen markup-injeksjon
	l.Text = text
	l.LayoutOrder = nextOrder
	nextOrder += 1
	l.Parent = panel

	lines[#lines + 1] = l
	while #lines > MAX_LINES do
		local old = table.remove(lines, 1)
		if old then old:Destroy() end
	end
end

-- Navn på avsender (visningsnavn hvis mulig), ellers nil for system-meldinger.
local function senderName(message)
	local src = message.TextSource
	if src then
		local plr = Players:GetPlayerByUserId(src.UserId)
		if plr then
			return plr.DisplayName
		end
		return "Player"
	end
	return nil
end

--==========================  KOBLE TIL CHAT  ====================--
-- pcall rundt hele koblingen: skulle en gammel/legacy chat-oppsett mangle
-- MessageReceived, står feeden bare tom i stedet for å krasje.
pcall(function()
	TextChatService.MessageReceived:Connect(function(message)
		local body = message.Text
		if type(body) ~= "string" or body == "" then return end
		local nm = senderName(message)
		local text = nm and (nm .. ": " .. body) or body
		addLine(text)
	end)
end)
