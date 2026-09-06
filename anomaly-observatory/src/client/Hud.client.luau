-- Hud.client.luau — HUD for "Anomaly: Night Shift at the Observatory".
-- The ADVANCE / TURN BACK / USE HINT actions are in-world ProximityPrompts (keys E / Q / H),
-- so this is display + the code-redeem box + the tint picker only. All state is pushed by
-- the server via the State remote; the client trusts nothing it computes itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local Remotes = ReplicatedStorage:WaitForChild("AnomalyRemotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent
local RevealRemote = Remotes:WaitForChild("Reveal") :: RemoteEvent
local DeathRemote = Remotes:WaitForChild("Death") :: RemoteEvent
local RedeemRemote = Remotes:WaitForChild("Redeem") :: RemoteEvent
local TintRemote = Remotes:WaitForChild("SetTint") :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "AnomalyHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = plr:WaitForChild("PlayerGui")

local DARK = Color3.fromRGB(18, 20, 30)
local ACCENT = Color3.fromRGB(120, 180, 255)
local WARN = Color3.fromRGB(230, 90, 80)
local GOOD = Color3.fromRGB(90, 200, 130)

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, ts: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.fromRGB(235, 235, 245)
	l.TextScaled = false
	l.TextSize = ts
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- top-left status panel
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(230, 96)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Parent = gui
-- visual polish: rounded + cold stroke so the HUD reads as part of the horror theme
FxClient.theme(panel, { corner = 10, stroke = Color3.fromRGB(90, 120, 170), strokeThickness = 1.5, strokeTransparency = 0.35 })

local dayLbl = label(panel, "DAY 1", UDim2.fromOffset(200, 34), UDim2.fromOffset(14, 8), 28)
dayLbl.Font = Enum.Font.GothamBold
dayLbl.TextColor3 = ACCENT
local bestLbl = label(panel, "Best: Day 0", UDim2.fromOffset(200, 20), UDim2.fromOffset(14, 44), 15)
local codexLbl = label(panel, "Field Guide: 0/0", UDim2.fromOffset(200, 20), UDim2.fromOffset(14, 66), 15)

-- instructions (top-center)
local help = label(gui, "Walk the hall. Something wrong? TURN BACK (Q). Looks normal? ADVANCE (E). Wrong call = back to Day 1.",
	UDim2.fromOffset(680, 24), UDim2.new(0.5, -340, 0, 20), 15)
help.TextXAlignment = Enum.TextXAlignment.Center
help.TextColor3 = Color3.fromRGB(200, 205, 220)

-- hint pill (top-right)
local hintLbl = label(gui, "Hints: 0  (H at start pad)", UDim2.fromOffset(240, 22), UDim2.new(1, -256, 0, 18), 15)
hintLbl.TextXAlignment = Enum.TextXAlignment.Right

-- transient toast (center)
local toast = label(gui, "", UDim2.fromOffset(600, 40), UDim2.new(0.5, -300, 0.5, -120), 26)
toast.Font = Enum.Font.GothamBold
toast.TextXAlignment = Enum.TextXAlignment.Center
local function showToast(text: string, color: Color3)
	toast.Text = text
	toast.TextColor3 = color
	toast.TextTransparency = 0
	task.spawn(function()
		local myText = text
		for i = 1, 30 do
			if toast.Text ~= myText then return end
			toast.TextTransparency = i / 30
			task.wait(0.06)
		end
		if toast.Text == myText then toast.Text = "" end
	end)
end

-- bottom-left: code redeem
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.fromOffset(150, 30)
codeBox.Position = UDim2.new(0, 16, 1, -46)
codeBox.BackgroundColor3 = DARK
codeBox.BackgroundTransparency = 0.15
codeBox.BorderSizePixel = 0
codeBox.Font = Enum.Font.Gotham
codeBox.TextColor3 = Color3.fromRGB(235, 235, 245)
codeBox.PlaceholderText = "enter code"
codeBox.TextSize = 15
codeBox.Text = ""
codeBox.ClearTextOnFocus = false
codeBox.Parent = gui
Instance.new("UICorner", codeBox).CornerRadius = UDim.new(0, 8)

local redeemBtn = Instance.new("TextButton")
redeemBtn.Size = UDim2.fromOffset(90, 30)
redeemBtn.Position = UDim2.new(0, 172, 1, -46)
redeemBtn.BackgroundColor3 = ACCENT
redeemBtn.BorderSizePixel = 0
redeemBtn.Font = Enum.Font.GothamBold
redeemBtn.TextColor3 = DARK
redeemBtn.TextSize = 15
redeemBtn.Text = "REDEEM"
redeemBtn.Parent = gui
Instance.new("UICorner", redeemBtn).CornerRadius = UDim.new(0, 8)
redeemBtn.Activated:Connect(function()
	local t = codeBox.Text
	if #t > 0 then
		RedeemRemote:FireServer(t)
		codeBox.Text = ""
	end
end)

-- bottom-right: tint picker (populated from State)
local tintRow = Instance.new("Frame")
tintRow.Size = UDim2.fromOffset(300, 30)
tintRow.Position = UDim2.new(1, -316, 1, -46)
tintRow.BackgroundTransparency = 1
tintRow.Parent = gui
local tintLayout = Instance.new("UIListLayout")
tintLayout.FillDirection = Enum.FillDirection.Horizontal
tintLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
tintLayout.Padding = UDim.new(0, 6)
tintLayout.Parent = tintRow

local TINT_RGB: { [string]: Color3 } = {
	white = Color3.fromRGB(235, 235, 245),
	amber = Color3.fromRGB(240, 180, 90),
	gold = Color3.fromRGB(245, 205, 70),
	cyan = Color3.fromRGB(90, 220, 235),
	crimson = Color3.fromRGB(225, 70, 80),
}
local builtTints = false
local function buildTints(tints: { string })
	if builtTints then return end
	builtTints = true
	for _, name in tints do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(26, 26)
		b.Text = ""
		b.BackgroundColor3 = TINT_RGB[name] or Color3.fromRGB(200, 200, 200)
		b.BorderSizePixel = 0
		b.Parent = tintRow
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		b.Activated:Connect(function()
			TintRemote:FireServer(name)
		end)
	end
end

-- ---------------------------------------------------------------- remote wiring
StateRemote.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	dayLbl.Text = "DAY " .. tostring(s.day)
	bestLbl.Text = "Best: Day " .. tostring(s.best)
	codexLbl.Text = "Field Guide: " .. tostring(s.codexCount) .. "/" .. tostring(s.codexTotal)
	hintLbl.Text = "Hints: " .. tostring(s.hintTokens) .. "  (H at start pad)"
	if s.tints then buildTints(s.tints) end
end)

RevealRemote.OnClientEvent:Connect(function(r)
	if typeof(r) ~= "table" then return end
	if r.redeem ~= nil then
		if r.redeem == "ok" then
			showToast("Code redeemed!", GOOD)
		elseif r.redeem == "already" then
			showToast("Code already used", WARN)
		elseif r.redeem == "unknown" then
			showToast("Unknown code", WARN)
		elseif r.redeem == "empty" then
			showToast("Enter a code", WARN)
		elseif r.redeem == "unavailable" or r.redeem == "retry" then
			-- saving is down / another session holds the lock: nothing was granted, so say so
			-- instead of silently doing nothing (server refuses to grant what it can't persist)
			showToast(r.message or "Saving unavailable — try again in a moment", WARN)
		end
		return
	end
	-- hint reveal
	if r.ok == false then
		showToast("No hints left", WARN)
	elseif r.ok == true then
		if r.clean then
			showToast("HINT: the hall looks clean", GOOD)
		else
			showToast("HINT: something is WRONG", WARN)
		end
	end
end)

DeathRemote.OnClientEvent:Connect(function(d)
	if typeof(d) ~= "table" then return end
	-- the jumpscare beat: red vignette flash + camera shake + a short FOV punch
	FxClient.flash(Color3.fromRGB(180, 20, 20), 0.6, 0.7)
	FxClient.shake(0.5, 1.6)
	FxClient.fovPunch(12, 0.08, 0.4)
	local msg
	if d.wasClean then
		msg = "You turned back on a CLEAN hall — Night reset (reached Day " .. tostring(d.reached) .. ")"
	else
		msg = "You MISSED an anomaly — Night reset (reached Day " .. tostring(d.reached) .. ")"
	end
	showToast(msg, WARN)
end)

print("[Anomaly] HUD ready.")
