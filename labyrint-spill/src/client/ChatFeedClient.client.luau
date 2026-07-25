--[[==================================================================
	LABYRINT-SPILL  -  GLOBAL-CHAT-FEED (klient)
	Laget for Marius & onkel :)

	Viser de siste chat-meldingene ØVERST-TIL-VENSTRE (et lite, lesbart utdrag), i
	tillegg til den vanlige chat-boksen. Bare visning — man skriver fortsatt i den
	vanlige chatten. Ligger oppe i hjørnet så den ikke dekker selve spillet.

	Robust mot BEGGE chat-systemene: moderne TextChatService (MessageReceived) OG
	det gamle Legacy-chat-systemet (DefaultChatSystemChatEvents). Det aktive
	systemet fyrer; det andre finnes ikke og hoppes trygt over. Meldingene er
	allerede filtrert av Roblox — vi bare tegner dem. All spiller-tekst er engelsk.
==================================================================]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Panel ØVERST-TIL-VENSTRE, rett under "⚡ Upgrades"-knappen (som er ~12..60).
-- Vokser nedover med antall linjer (AutomaticSize). Halvgjennomsiktig og oppe i
-- hjørnet så den holder seg UNNA selve spill-vinduet (midten av skjermen).
local panel = Instance.new("Frame")
panel.Name = "Feed"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.new(0, 8, 0, 66)
panel.Size = UDim2.new(0, 300, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Active = false            -- ikke fang trykk (viktig på mobil / ikke blokker spill)
panel.Parent = gui

local sizeC = Instance.new("UISizeConstraint")
sizeC.MaxSize = Vector2.new(300, 132)   -- tak på både bredde og høyde
sizeC.MinSize = Vector2.new(190, 0)
sizeC.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 78, 100)
stroke.Thickness = 1
stroke.Transparency = 0.35
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
header.Size = UDim2.new(1, 0, 0, 15)
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
placeholder.TextSize = 13
placeholder.TextColor3 = Color3.fromRGB(150, 156, 170)
placeholder.TextXAlignment = Enum.TextXAlignment.Left
placeholder.TextTruncate = Enum.TextTruncate.AtEnd
placeholder.Text = "Chat appears here…"
placeholder.Parent = panel

--==========================  LINJER  ============================--
local lines = {}       -- rullerende liste av melding-etiketter (eldst først)
local nextOrder = 2    -- LayoutOrder-teller (0 = header, 1 = placeholder)

local function addLine(text)
	if placeholder then
		placeholder:Destroy()
		placeholder = nil
	end

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
		local dead = table.remove(lines, 1)
		if dead then dead:Destroy() end
	end
end

-- Bygg "Name: message" (eller bare meldingen om avsender mangler) og legg til.
local function pushMessage(nameStr, body)
	if type(body) ~= "string" or body == "" then return end
	local text = (type(nameStr) == "string" and nameStr ~= "")
		and (nameStr .. ": " .. body) or body
	addLine(text)
end

--==================  MODERNE TextChatService  ===================--
-- MessageReceived fyrer på klienten for ALLE meldinger man mottar (inkl. egne).
-- message.Text = filtrert tekst; message.TextSource = avsender (nil for system).
pcall(function()
	TextChatService.MessageReceived:Connect(function(message)
		local nm
		local src = message.TextSource
		if src then
			local plr = Players:GetPlayerByUserId(src.UserId)
			nm = plr and plr.DisplayName or nil
		end
		pushMessage(nm, message.Text)
	end)
end)

--====================  LEGACY-CHAT (fallback)  ==================--
-- Bruker opplevelsen fortsatt det gamle chat-systemet, kommer meldingene via
-- ReplicatedStorage.DefaultChatSystemChatEvents.OnMessageDoneFiltering (RemoteEvent)
-- med { FromSpeaker = navn, Message = tekst }. Finnes ikke på moderne oppsett → hopp.
task.spawn(function()
	local ok, events = pcall(function()
		return ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 8)
	end)
	if not ok or not events then return end
	local onFiltered = events:FindFirstChild("OnMessageDoneFiltering")
	if onFiltered and onFiltered:IsA("RemoteEvent") then
		onFiltered.OnClientEvent:Connect(function(data)
			if type(data) == "table" then
				pushMessage(data.FromSpeaker, data.Message)
			end
		end)
	end
end)
