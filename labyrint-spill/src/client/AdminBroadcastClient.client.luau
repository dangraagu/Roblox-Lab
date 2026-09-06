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
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Delt skjermstørrelse-modul (ren data — se src/shared/Responsive.luau).
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("AdminBroadcast")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AdminBroadcast"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20            -- over alt annet: en kringkasting skal ses
gui.Parent = playerGui

--====================  ROT-RAMME MED UISCALE  ====================--
-- En UIScale gjør INGENTING når den henger rett på en ScreenGui, så vi trenger en
-- gjennomsiktig rot-ramme som eier skaleringen, og banneret henger under den.
-- Active = false: spilleren holder finger på skjermen nesten hele tiden i en
-- hinderløype, og en gjennomsiktig ramme som sluker trykk ville låst bevegelsen.
-- (Selve banneret er en TextLabel, og de tar aldri imot input.)
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- Gjennomsiktig banner øverst-i-midten, rett UNDER "Level"-feltet i HUD-et (som
-- går fra y=6 til y=84). Bare tekst med svart kant, ingen boks — "gjennomsiktig
-- felt øverst på skjermen".
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 88)
banner.Size = UDim2.new(0.8, 0, 0, 44)
banner.BackgroundTransparency = 1        -- gjennomsiktig
banner.Font = Enum.Font.GothamBold
banner.TextScaled = true
banner.TextColor3 = Color3.fromRGB(255, 236, 150)
banner.TextXAlignment = Enum.TextXAlignment.Center
banner.TextWrapped = true
banner.Text = ""
banner.Visible = false
banner.Parent = root

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

--====================  SKJERM-TILPASNING  =======================--
-- Banneret er allerede skala-basert med et tak (UISizeConstraint), så det eneste
-- som må skje her er rot-skaleringen: da krymper teksten i takt med resten av
-- HUD-et i stedet for å ta over en telefonskjerm.
local function applyLayout()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(0, 0)
	local layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale

	-- Rot-rammen må vokse med 1/skala så rot × skala lander nøyaktig på skjermkanten.
	-- Uten dette krymper banneret inn i øvre venstre hjørne på telefon, mens det ser
	-- helt riktig ut på desktop der skalaen er 1 og feilen er usynlig.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
end

-- workspace.CurrentCamera er nil et bilde eller to ved oppstart, og Roblox bytter
-- den ut ved enkelte respawn, så vi kobler lytteren på nytt når kameraet byttes.
local viewportConn
local function watchViewport()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

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
