-- Board.client.luau — the RELAYS RESTORED board in the lifeboat (client, display only).
--
-- The server builds the board (workspace.Lifeboat.RelayBoard) and its ProximityPrompt, owns every number on it,
-- and sends THIS player their view over SignalRemotes.Board: { viewer, mode = "public" | "friends",
-- rows = { { rank, userId, name, tier, you?, star? } }, note? }. Each player can look at Public or Friends, so
-- the board is drawn here, locally: a SurfaceGui created by this LocalScript under the board part exists on this
-- client only. Not in PlayerGui: robloxemu's HUD fit check measures everything there as screen panels.
-- Adapted from plus1-jump/src/client/Board.client.luau. Glyphs: only the star, photographed rendering in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("SignalRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BC = Config.Board

local lifeboat = workspace:WaitForChild("Lifeboat", 60)
local part = lifeboat and lifeboat:WaitForChild("RelayBoard", 60)
if not part then
	warn("[SignalLost] the board never arrived; it stays blank for this player")
	return
end

local ACCENT = Color3.fromRGB(Config.Hud.Accent.r, Config.Hud.Accent.g, Config.Hud.Accent.b)
local GOLD = Color3.fromRGB(255, 215, 110)
local TEXT = Color3.fromRGB(225, 232, 245)
local DIM = Color3.fromRGB(150, 160, 185)

-- 14 x 9 studs at 40 px per stud = 560 x 360 px
local gui = Instance.new("SurfaceGui")
gui.Name = "RelayBoardGui"
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 40
gui.LightInfluence = 0
gui.ClipsDescendants = true
gui.Parent = part

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(12, 18, 30)
frame.BorderSizePixel = 0
frame.Parent = gui

local function label(name: string, y: number, h: number, size: number, color: Color3, font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 20, 0, y)
	l.Size = UDim2.new(1, -40, 0, h)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = frame
	return l
end

local title = label("Title", 8, 34, 28, ACCENT, Enum.Font.GothamBlack)
title.Text = BC.Text.Title
local modeLabel = label("Mode", 42, 24, 18, TEXT, Enum.Font.GothamBold)
local rows = {}
for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
	rows[i] = label("Row" .. i, 68 + (i - 1) * 24, 22, 17, TEXT)
	rows[i].Visible = false
end
local note = label("Note", 68, 90, 17, DIM)
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Visible = false
local hint = label("Hint", 330, 22, 14, DIM)
hint.Text = "Walk up and press E (or tap): " .. BC.Text.Prompt

local function render(view)
	local friends = view.mode == "friends"
	modeLabel.Text = if friends then "FRIENDS" else "PUBLIC"
	modeLabel.TextColor3 = if friends then Color3.fromRGB(150, 220, 255) else GOLD
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, l in rows do
		local r = list[i]
		if r then
			local you = r.you or r.userId == player.UserId
			l.Text = string.format("%d. %s%s%s   %d relays", r.rank or i, if r.star then BC.Star .. " " else "",
				tostring(r.name or "?"), if you then " (you)" else "", tonumber(r.tier) or 0)
			l.TextColor3 = if you then GOLD else TEXT
			l.Font = if you then Enum.Font.GothamBold else Enum.Font.GothamMedium
			l.Visible = true
		else
			l.Text = ""
			l.Visible = false
		end
	end
	if type(view.note) == "string" and view.note ~= "" then
		note.Text = view.note
		note.Position = UDim2.new(0, 20, 0, 72 + #list * 24)
		note.Visible = true
	else
		note.Text = ""
		note.Visible = false
	end
end

render({ mode = "public", rows = {}, note = BC.Text.Loading })

BoardEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then return end
	-- In Roblox FireClient reaches only this player; a view for someone else is never drawn here.
	if view.viewer ~= nil and view.viewer ~= player.UserId then return end
	render(view)
end)
