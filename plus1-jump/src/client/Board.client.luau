-- +1 JUMP EVERY STEP — the Top Climbers board by the spawn (client, display only). Havner i StarterPlayerScripts.
--
-- The server builds the board (workspace.TopClimbersBoard) and its ProximityPrompt, owns every number on it and
-- sends this player THEIR view over Plus1Remotes.Board: { viewer, mode = "public"|"friends", rows = { { rank,
-- userId, name, tier, you? } }, note? }. Each player can look at Public or Friends, so the board is drawn here,
-- locally: a SurfaceGui created by this LocalScript under the board part exists on this client only.
-- It is NOT put in PlayerGui: robloxemu's HUD fit check measures everything in PlayerGui as screen panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Plus1Remotes")
local BoardEvent = remotes:WaitForChild("Board")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local BC = Config.Board

-- the sky band a tier belongs to, as on the HUD's top list: "85 🚀" is the brag
local function bandEmoji(tier: number): string
	local bands = Config.Env and Config.Env.Bands
	if type(bands) ~= "table" or type(tier) ~= "number" then return "" end
	return bands[EnvBands.indexAt(bands, tier)].emoji or ""
end

local part = workspace:WaitForChild("TopClimbersBoard", 60)
if not part then
	warn("[Plus1] the Top Climbers board never arrived; the board stays blank for this player")
	return
end

local GOLD = Color3.fromRGB(255, 215, 90)
local TEXT = Color3.fromRGB(225, 230, 245)
local DIM = Color3.fromRGB(150, 158, 185)

-- 16 x 11 studs at 40 px per stud = 640 x 440 px
local gui = Instance.new("SurfaceGui")
gui.Name = "TopClimbersGui"
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 40
gui.LightInfluence = 0
gui.ClipsDescendants = true
gui.Parent = part

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(18, 22, 38)
frame.BorderSizePixel = 0
frame.Parent = gui

local function label(name: string, y: number, h: number, size: number, color: Color3, font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 24, 0, y)
	l.Size = UDim2.new(1, -48, 0, h)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = frame
	return l
end

local title = label("Title", 10, 40, 32, GOLD, Enum.Font.GothamBlack)
title.Text = "🏆 " .. BC.Text.Title
local modeLabel = label("Mode", 50, 28, 22, TEXT, Enum.Font.GothamBold)
local rows = {}
for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
	rows[i] = label("Row" .. i, 80 + (i - 1) * 30, 28, 22, TEXT)
	rows[i].Visible = false
end
local note = label("Note", 80, 90, 22, DIM)
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Visible = false
local hint = label("Hint", 404, 28, 18, DIM)
hint.Text = "Walk up and press E (or tap): " .. BC.Text.Prompt

local function render(view)
	local friends = view.mode == "friends"
	modeLabel.Text = if friends then "👥 FRIENDS" else "🌍 PUBLIC"
	modeLabel.TextColor3 = if friends then Color3.fromRGB(150, 220, 255) else GOLD
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, l in rows do
		local r = list[i]
		if r then
			local you = r.you or r.userId == player.UserId
			l.Text = string.format("%d. %s%s   %d %s", r.rank or i, tostring(r.name or "?"), if you then " (you)" else "",
				tonumber(r.tier) or 0, bandEmoji(tonumber(r.tier) or 0))
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
		note.Position = UDim2.new(0, 24, 0, 84 + #list * 30)
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
