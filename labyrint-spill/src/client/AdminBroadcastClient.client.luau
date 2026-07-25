--[[==================================================================
	LABYRINT-SPILL  -  ADMIN-KRINGKASTING (klient)
	Laget for Marius & onkel :)

	Et GJENNOMSIKTIG felt øverst-i-midten som viser admin-kringkastinger.
	Admin (spillets eier ELLER Mio) skriver "/bc <tekst>" i chatten, og teksten
	dukker opp her hos ALLE spillere en liten stund.

	To biter:
	  1) Fanger "/bc"-kommandoen (TextChatCommand serveren lager) og sender resten
	     til serveren, som verifiserer admin + filtrerer + kringkaster.
	  2) Viser kringkastinger serveren sender via HudRemotes/Broadcast.
	Ikke-admin som skriver /bc gjør ingenting (serveren avviser). Tekst er engelsk.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("AdminBroadcast")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AdminBroadcast"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20            -- over alt annet: en kringkasting skal ses
gui.Parent = playerGui

-- Gjennomsiktig banner øverst-i-midten (rett under "Level"-feltet). Bare tekst
-- med svart kant, ingen boks — "gjennomsiktig felt øverst på skjermen".
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 72)
banner.Size = UDim2.new(0.8, 0, 0, 44)
banner.BackgroundTransparency = 1        -- gjennomsiktig
banner.Font = Enum.Font.GothamBold
banner.TextScaled = true
banner.TextColor3 = Color3.fromRGB(255, 236, 150)
banner.TextXAlignment = Enum.TextXAlignment.Center
banner.TextWrapped = true
banner.Text = ""
banner.Visible = false
banner.Parent = gui

local sizeC = Instance.new("UISizeConstraint")
sizeC.MaxSize = Vector2.new(720, 44)
sizeC.Parent = banner

local tsc = Instance.new("UITextSizeConstraint")
tsc.MaxTextSize = 22
tsc.MinTextSize = 12
tsc.Parent = banner

-- Svart kant så gul tekst er lesbar over hva som helst.
local bstroke = Instance.new("UIStroke")
bstroke.Color = Color3.fromRGB(0, 0, 0)
bstroke.Thickness = 2
bstroke.Parent = banner

--==========================  VISNING  ===========================--
local showToken = 0
local function showBroadcast(fromName, text)
	if type(text) ~= "string" or text == "" then return end
	local nm = (type(fromName) == "string" and fromName ~= "") and fromName or "Admin"
	banner.Text = "📢 " .. nm .. ": " .. text
	banner.Visible = true
	showToken += 1
	local mine = showToken
	task.delay(9, function()
		if mine == showToken then banner.Visible = false end
	end)
end

--==================  KOBLE TIL SERVEREN  ========================--
local broadcastEvent

task.spawn(function()
	local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
	if hud then
		broadcastEvent = hud:WaitForChild("Broadcast", 15)
		if broadcastEvent then
			broadcastEvent.OnClientEvent:Connect(function(fromName, text)
				pcall(showBroadcast, fromName, text)
			end)
		end
	end

	-- "/bc"-kommandoen: serveren lager TextChatCommand "BroadcastCommand".
	-- Triggered fyrer hos den som skrev den; vi sender resten til serveren.
	local cmd = TextChatService:WaitForChild("BroadcastCommand", 20)
	if cmd then
		cmd.Triggered:Connect(function(_source, unfilteredText)
			if not broadcastEvent then return end
			local msg = string.gsub(unfilteredText or "", "^%s*/bc%s*", "")
			if msg ~= "" then
				broadcastEvent:FireServer(msg)
			end
		end)
	end
end)
