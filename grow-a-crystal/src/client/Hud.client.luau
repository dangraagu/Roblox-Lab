-- GROW A CRYSTAL 💎 — klient-HUD. Havner i StarterPlayerScripts.
-- Ren visning + valg. Server eier all økonomi/vekst. Plant/høst = klikk soklene i
-- verden (server ClickDetector). Denne setter valgt seed + viser butikk/Codex/koder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("CrystalRemotes")
local StateEvent = remotes:WaitForChild("State")
local BuyEvent = remotes:WaitForChild("Buy")
local SelectEvent = remotes:WaitForChild("Select")
local GeodeEvent = remotes:WaitForChild("Geode")
local RedeemFunc = remotes:WaitForChild("Redeem")
local LeaderboardEvent = remotes:WaitForChild("Leaderboard")

local TIERS = Config.Tiers
local MAXT = Config.MaxTier
local unlockByChamber = Config.Economy.SeedShopUnlockedByChamber

local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = i end
local function pad(i, px) local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px); p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px); p.PaddingBottom = UDim.new(0, px); p.Parent = i end
local function tierColor(t) local c = Config.TierColor[t]; return Color3.fromRGB(c[1], c[2], c[3]) end

local gui = Instance.new("ScreenGui")
gui.Name = "CrystalHud"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- ── Top: Dust ─────────────────────────────────────────────────────────────
local top = Instance.new("Frame")
top.AnchorPoint = Vector2.new(0.5, 0); top.Position = UDim2.new(0.5, 0, 0, 10)
top.Size = UDim2.new(0, 300, 0, 56); top.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
top.BackgroundTransparency = 0.1; top.Parent = gui; corner(top, 12)
local dustLabel = Instance.new("TextLabel")
dustLabel.BackgroundTransparency = 1; dustLabel.Size = UDim2.new(1, 0, 1, 0)
dustLabel.Font = Enum.Font.GothamBlack; dustLabel.TextScaled = true
dustLabel.TextColor3 = Color3.fromRGB(150, 230, 255); dustLabel.Text = "💎 0"
dustLabel.Parent = top
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 30; cc.Parent = dustLabel end

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0); hint.Position = UDim2.new(0.5, 0, 0, 70)
hint.Size = UDim2.new(0, 460, 0, 22); hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium; hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(210, 214, 230)
hint.Text = "Select a seed, click an empty socket to plant · click a glowing crystal to harvest"
hint.Parent = gui
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = hint end

-- ── Left: Seeds + shop ──────────────────────────────────────────────────────
local left = Instance.new("Frame")
left.AnchorPoint = Vector2.new(0, 0.5); left.Position = UDim2.new(0, 12, 0.5, 0)
left.Size = UDim2.new(0, 250, 0, 470); left.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
left.BackgroundTransparency = 0.12; left.Parent = gui; corner(left, 12); pad(left, 8)
local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = left

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, 0, 0, 22); title.LayoutOrder = 0
title.Font = Enum.Font.GothamBlack; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(150, 230, 255)
title.Text = "🌱 SEEDS"; title.Parent = left
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 16; cc.Parent = title end

-- One row per tier: select (plant this) + owned count + buy
local seedRows = {}
for t = 1, MAXT do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34); row.BackgroundColor3 = Color3.fromRGB(34, 38, 56)
	row.LayoutOrder = t; row.Parent = left; corner(row, 6)
	local sel = Instance.new("TextButton")
	sel.Size = UDim2.new(0, 120, 1, -4); sel.Position = UDim2.new(0, 2, 0, 2)
	sel.Font = Enum.Font.GothamBold; sel.TextScaled = true; sel.TextColor3 = Color3.fromRGB(20, 22, 34)
	sel.BackgroundColor3 = tierColor(t); sel.Text = TIERS[t]; sel.Parent = row; corner(sel, 6)
	do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = sel end
	sel.Activated:Connect(function() SelectEvent:FireServer(t) end)
	local buy = Instance.new("TextButton")
	buy.Size = UDim2.new(0, 118, 1, -4); buy.Position = UDim2.new(0, 128, 0, 2)
	buy.Font = Enum.Font.GothamMedium; buy.TextScaled = true; buy.TextColor3 = Color3.fromRGB(255, 255, 255)
	buy.BackgroundColor3 = Color3.fromRGB(70, 150, 90); buy.Text = "Buy"; buy.Parent = row; corner(buy, 6)
	do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 12; cc.Parent = buy end
	buy.Activated:Connect(function() BuyEvent:FireServer("seed", t) end)
	seedRows[t] = { row = row, sel = sel, buy = buy }
end

local function shopBtn(order, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 32); b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold; b.TextScaled = true; b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundColor3 = color; b.Text = text; b.Parent = left; corner(b, 6)
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = b
	b.Activated:Connect(cb)
	return b
end
local chamberBtn = shopBtn(20, "Buy Chamber", Color3.fromRGB(90, 110, 200), function() BuyEvent:FireServer("chamber") end)
local luckBtn = shopBtn(21, "Luck", Color3.fromRGB(200, 150, 60), function() BuyEvent:FireServer("booster", "Luck") end)
local growthBtn = shopBtn(22, "Growth", Color3.fromRGB(60, 170, 120), function() BuyEvent:FireServer("booster", "Growth") end)
local geodeBtn = shopBtn(23, "Crack Geode", Color3.fromRGB(180, 90, 220), function() GeodeEvent:FireServer() end)
local codexLabel = Instance.new("TextLabel")
codexLabel.BackgroundTransparency = 1; codexLabel.Size = UDim2.new(1, 0, 0, 22); codexLabel.LayoutOrder = 24
codexLabel.Font = Enum.Font.GothamMedium; codexLabel.TextScaled = true
codexLabel.TextColor3 = Color3.fromRGB(230, 234, 245); codexLabel.Text = "📖 Codex: 0/" .. MAXT; codexLabel.Parent = left
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = codexLabel end

-- ── Codes (bottom-left) ──────────────────────────────────────────────────────
local codeFrame = Instance.new("Frame")
codeFrame.AnchorPoint = Vector2.new(0, 1); codeFrame.Position = UDim2.new(0, 12, 1, -12)
codeFrame.Size = UDim2.new(0, 250, 0, 68); codeFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
codeFrame.BackgroundTransparency = 0.12; codeFrame.Parent = gui; corner(codeFrame, 10); pad(codeFrame, 6)
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, 0, 0, 28); codeBox.Font = Enum.Font.GothamMedium; codeBox.TextScaled = true
codeBox.PlaceholderText = "Enter code..."; codeBox.Text = ""; codeBox.ClearTextOnFocus = false
codeBox.TextColor3 = Color3.fromRGB(20, 22, 34); codeBox.BackgroundColor3 = Color3.fromRGB(235, 238, 248)
codeBox.Parent = codeFrame; corner(codeBox, 6)
local codeBtn = Instance.new("TextButton")
codeBtn.Position = UDim2.new(0, 0, 0, 32); codeBtn.Size = UDim2.new(1, 0, 0, 24)
codeBtn.Font = Enum.Font.GothamBold; codeBtn.TextScaled = true; codeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
codeBtn.BackgroundColor3 = Color3.fromRGB(70, 150, 90); codeBtn.Text = "Redeem"; codeBtn.Parent = codeFrame; corner(codeBtn, 6)
codeBtn.Activated:Connect(function()
	local input = codeBox.Text
	if input == "" then return end
	local ok, res = pcall(function() return RedeemFunc:InvokeServer(input) end)
	if ok and type(res) == "table" then
		if res.ok then codeBox.Text = ""; codeBtn.Text = "✅ Redeemed!"
		elseif res.reason == "already" then codeBtn.Text = "Already used"
		elseif res.reason == "unknown" then codeBtn.Text = "Invalid code"
		else codeBtn.Text = "Try again" end
		task.delay(2, function() codeBtn.Text = "Redeem" end)
	end
end)

-- ── Leaderboard (right) ──────────────────────────────────────────────────────
local lb = Instance.new("Frame")
lb.AnchorPoint = Vector2.new(1, 0.5); lb.Position = UDim2.new(1, -12, 0.5, 0)
lb.Size = UDim2.new(0, 200, 0, 300); lb.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
lb.BackgroundTransparency = 0.2; lb.Parent = gui; corner(lb, 12); pad(lb, 8)
local lbTitle = Instance.new("TextLabel")
lbTitle.BackgroundTransparency = 1; lbTitle.Size = UDim2.new(1, 0, 0, 24)
lbTitle.Font = Enum.Font.GothamBlack; lbTitle.TextScaled = true
lbTitle.TextColor3 = Color3.fromRGB(255, 215, 90); lbTitle.Text = "🏆 TOP MINERS"; lbTitle.Parent = lb
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 17; cc.Parent = lbTitle end
local lbList = Instance.new("Frame")
lbList.BackgroundTransparency = 1; lbList.Position = UDim2.new(0, 0, 0, 28); lbList.Size = UDim2.new(1, 0, 1, -28)
lbList.Parent = lb
local lbLayout = Instance.new("UIListLayout"); lbLayout.Padding = UDim.new(0, 3); lbLayout.Parent = lbList

LeaderboardEvent.OnClientEvent:Connect(function(top)
	for _, c in ipairs(lbList:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	for i, e in ipairs(top) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.Size = UDim2.new(1, 0, 0, 22); l.LayoutOrder = i
		l.Font = Enum.Font.GothamMedium; l.TextScaled = true; l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(225, 230, 245)
		local name = "Player"
		local okn, res = pcall(function() return Players:GetNameFromUserIdAsync(e.userId) end)
		if okn then name = res end
		l.Text = string.format("%d. %s — 💎%d", i, name, e.dust); l.Parent = lbList
		local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = l
	end
end)

-- ── State render ───────────────────────────────────────────────────────────
StateEvent.OnClientEvent:Connect(function(s)
	dustLabel.Text = "💎 " .. tostring(s.dust)
	for t = 1, MAXT do
		local r = seedRows[t]
		local owned = (s.seeds and s.seeds[t]) or 0
		r.sel.Text = TIERS[t] .. " (" .. owned .. ")"
		local unlocked = s.chambers >= (unlockByChamber[t] or 999)
		if unlocked then
			r.buy.Text = "Buy 💎" .. tostring(Config.Economy.SeedCost[t])
			r.buy.BackgroundColor3 = Color3.fromRGB(70, 150, 90); r.buy.Active = true
		else
			r.buy.Text = "🔒 Ch." .. tostring(unlockByChamber[t])
			r.buy.BackgroundColor3 = Color3.fromRGB(80, 84, 100); r.buy.Active = false
		end
	end
	chamberBtn.Text = (s.chambers >= Config.Economy.MaxChambers) and "Chambers MAX"
		or ("Buy Chamber 💎" .. tostring(s.chamberCost) .. " (" .. s.chambers .. ")")
	luckBtn.Text = "Luck Lv" .. s.luckLevel .. " → 💎" .. tostring(s.luckCost)
	growthBtn.Text = "Growth Lv" .. s.growthLevel .. " → 💎" .. tostring(s.growthCost)
	if s.geodeCanCrack then
		geodeBtn.Text = "Crack Geode 💎" .. s.geodeCost .. " → " .. TIERS[s.geodeExclusive]
		geodeBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 220)
	else
		geodeBtn.Text = "Geode used (back next week)"
		geodeBtn.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	end
	codexLabel.Text = "📖 Codex: " .. tostring(s.codexCount) .. "/" .. MAXT
end)
