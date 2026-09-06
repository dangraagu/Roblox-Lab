--[[==================================================================
	LABYRINT-SPILL  -  "HJELP MEG"-GUIDEN (klient)
	Laget for Marius & onkel :)

	Serveren teller hvor mange ganger du har feilet SAMME nivå. Har du feilet nok
	ganger, sender den AssistRemotes/AssistState og dette kortet dukker opp — inne
	i labyrinten som en kjøp-knapp, i lobbyen som et hint om at hjelpen finnes.

	Klienten bestemmer INGENTING: den viser bare det serveren sier, og sender et
	ønske uten argumenter (ingen pris, intet nivå). All validering skjer på
	serveren (se "HJELP MEG"-GUIDEN i MazeGame.server.luau). All tekst er engelsk.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("AssistPanel")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AssistPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 13
gui.Enabled = false
gui.Parent = playerGui

local function corner(inst, r)
	local u = Instance.new("UICorner"); u.CornerRadius = UDim.new(0, r or 8); u.Parent = inst
end

-- Nederst i midten: der blikket er når man står fast og lurer på hva man skal gjøre.
local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 1, -14)
card.Size = UDim2.fromOffset(340, 116)
card.BackgroundColor3 = Color3.fromRGB(28, 31, 44)
card.BackgroundTransparency = 0.08
card.BorderSizePixel = 0
card.Parent = gui
corner(card, 12)

-- Skaler ned på små skjermer (telefon) i stedet for å flyte utenfor.
local scale = Instance.new("UIScale"); scale.Parent = card
local function fit()
	local vp = gui.AbsoluteSize
	if vp.X > 0 then scale.Scale = math.clamp((vp.X - 20) / 340, 0.6, 1) end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 24)
titleLbl.Position = UDim2.fromOffset(10, 8)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextScaled = true
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = Color3.fromRGB(255, 224, 130)
titleLbl.Text = "Stuck?"
titleLbl.Parent = card
local ttc = Instance.new("UITextSizeConstraint"); ttc.MaxTextSize = 19; ttc.Parent = titleLbl

local bodyLbl = Instance.new("TextLabel")
bodyLbl.Size = UDim2.new(1, -20, 0, 30)
bodyLbl.Position = UDim2.fromOffset(10, 32)
bodyLbl.BackgroundTransparency = 1
bodyLbl.Font = Enum.Font.Gotham
bodyLbl.TextScaled = true
bodyLbl.TextWrapped = true
bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
bodyLbl.TextColor3 = Color3.fromRGB(198, 204, 218)
bodyLbl.Text = ""
bodyLbl.Parent = card
local btc = Instance.new("UITextSizeConstraint"); btc.MaxTextSize = 13; btc.Parent = bodyLbl

-- 44px høy: stor nok til å treffe med tommelen på telefon.
local buyBtn = Instance.new("TextButton")
buyBtn.Size = UDim2.new(1, -60, 0, 44)
buyBtn.Position = UDim2.fromOffset(10, 66)
buyBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 190)
buyBtn.TextColor3 = Color3.new(1, 1, 1)
buyBtn.Font = Enum.Font.GothamBold
buyBtn.TextScaled = true
buyBtn.Text = "💡 Show me the way"
buyBtn.Parent = card
corner(buyBtn, 10)
local abtc = Instance.new("UITextSizeConstraint"); abtc.MaxTextSize = 17; abtc.Parent = buyBtn

local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.fromOffset(40, 44)
hideBtn.AnchorPoint = Vector2.new(1, 0)
hideBtn.Position = UDim2.new(1, -10, 0, 66)
hideBtn.BackgroundColor3 = Color3.fromRGB(64, 68, 86)
hideBtn.TextColor3 = Color3.new(1, 1, 1)
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextScaled = true
hideBtn.Text = "✕"
hideBtn.Parent = card
corner(hideBtn, 10)
local hbtc = Instance.new("UITextSizeConstraint"); hbtc.MaxTextSize = 18; hbtc.Parent = hideBtn

--=======================  TILSTAND  =============================--
local buyAssistFn                 -- RemoteFunction (fylles ut nedenfor)
local latest = nil                -- siste tilstand fra serveren
local dismissedKey = nil          -- "nivå:antall-forsøk" spilleren har lukket kortet på
local busy = false

-- Myntene leses rett fra leaderstats, som serveren allerede oppdaterer live —
-- da trenger vi ingen ekstra trafikk bare for å vise "har du råd?".
local function coins()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	return (c and c.Value) or (latest and latest.coins) or 0
end

local function keyFor(s)
	return tostring(s.level) .. ":" .. tostring(s.fails) .. ":" .. tostring(s.inMaze)
end

local function render()
	local s = latest
	if not s or not s.enabled then gui.Enabled = false; return end

	-- Guide kjøpt: kort kvittering, så forsvinner kortet av seg selv.
	if s.active then
		titleLbl.Text = "💡 Guide active"
		titleLbl.TextColor3 = Color3.fromRGB(120, 235, 255)
		bodyLbl.Text = "Follow the blue lights to the exit. This run counts for progress, but not for the time records."
		buyBtn.Visible = false
		hideBtn.Visible = true
		gui.Enabled = true
		fit()
		return
	end

	if not s.offered then gui.Enabled = false; return end
	if dismissedKey == keyFor(s) then gui.Enabled = false; return end

	local have = coins()
	titleLbl.TextColor3 = Color3.fromRGB(255, 224, 130)
	titleLbl.Text = "Stuck on Level " .. s.level .. "?"
	buyBtn.Visible = s.inMaze
	hideBtn.Visible = true

	if not s.inMaze then
		-- I lobbyen: si at hjelpen finnes, og hvor man får tak i den.
		bodyLbl.Text = ("You've tried it %d times. Go back in and buy a Guide for %d coins — it lights the whole way to the exit.")
			:format(s.fails, s.price)
	elseif have >= s.price then
		bodyLbl.Text = ("A Guide lights the whole way to the exit, for this run. Costs %d coins (you have %d)."):format(s.price, have)
		buyBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 190)
		buyBtn.Text = "💡 Show me the way — " .. s.price
	else
		bodyLbl.Text = ("A Guide costs %d coins and you have %d. Grab coins on the way, or claim the Daily Reward in the lobby."):format(s.price, have)
		buyBtn.BackgroundColor3 = Color3.fromRGB(78, 82, 100)
		buyBtn.Text = "Need " .. (s.price - have) .. " more coins"
	end
	gui.Enabled = true
	fit()
end

hideBtn.Activated:Connect(function()
	if latest then dismissedKey = keyFor(latest) end
	gui.Enabled = false
end)

buyBtn.Activated:Connect(function()
	if busy or not buyAssistFn or not latest or not latest.inMaze then return end
	if coins() < (latest.price or math.huge) then return end   -- serveren avviser uansett
	busy = true
	buyBtn.Text = "…"
	local ok, res = pcall(function() return buyAssistFn:InvokeServer() end)
	busy = false
	if ok and type(res) == "table" and res.ok then
		return   -- serveren sender ny AssistState; render() tar seg av resten
	end
	local reason = (ok and type(res) == "table" and res.reason) or "error"
	if reason == "insufficient" then
		bodyLbl.Text = "Not enough coins yet. Collect a few more, or claim the Daily Reward in the lobby."
	elseif reason == "notstuck" then
		bodyLbl.Text = "The Guide unlocks after a few tries on this level."
	elseif reason == "notinmaze" then
		bodyLbl.Text = "Go into the maze first, then buy the Guide."
	else
		bodyLbl.Text = "Couldn't buy the Guide right now. Try again in a moment."
	end
	buyBtn.Text = "💡 Show me the way"
end)

--==================  KOBLE TIL SERVEREN  ========================--
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("AssistRemotes", 30)
	if not folder then return end
	buyAssistFn = folder:WaitForChild("BuyAssist", 15)
	local stateEvent = folder:WaitForChild("AssistState", 15)
	if not stateEvent then return end
	stateEvent.OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then return end
		-- Nytt nivå (eller nytt forsøk) => kortet skal få vise seg igjen.
		if not latest or latest.level ~= s.level then dismissedKey = nil end
		latest = s
		pcall(render)
	end)
end)
