-- DISASTER ROUNDS - the Longest Streaks board on the Lookout (client, display only). Lives in StarterPlayerScripts.
--
-- The server builds the board (workspace.Lookout.StreakBoard) and its ProximityPrompt, owns every number on it and
-- sends this player THEIR view over DRRemotes.Board: { viewer, mode = "public"|"friends", rows = { { rank, userId,
-- name, tier, you? } }, note? } (`tier` is the template's name for the metric: here the best streak). Each player can
-- look at Public or Friends, so the board is drawn here, locally: a SurfaceGui this LocalScript puts under the board
-- part exists on this client only. Not in PlayerGui (DESIGN.md §7 said PlayerGui + Adornee): robloxemu's HUD fit
-- check measures everything in PlayerGui as screen panels, and +1 Jump's board, which this copies, does the same.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("DRRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BC = Config.Board

local lookout = workspace:WaitForChild("Lookout", 60)
local part = lookout and lookout:WaitForChild("StreakBoard", 60)
if not part then
	warn("[DisasterRounds] the streak board never arrived; the board stays blank for this player")
	return
end

local GOLD = Color3.fromRGB(255, 215, 90)
local TEXT = Color3.fromRGB(225, 230, 245)
local DIM = Color3.fromRGB(150, 158, 185)
local PPS = 40 -- 12 x 8 studs at 40 px per stud = 480 x 320 px

local gui = Instance.new("SurfaceGui")
gui.Name = "StreakBoardGui"
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = PPS
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
	l.Position = UDim2.new(0, 16, 0, y)
	l.Size = UDim2.new(1, -32, 0, h)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = frame
	return l
end

local title = label("Title", 6, 30, 24, GOLD, Enum.Font.GothamBlack)
title.Text = "🏆 " .. BC.Text.Title
local modeLabel = label("Mode", 34, 20, 16, TEXT, Enum.Font.GothamBold)
local ROW_H = 21
local rows = {}
for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
	rows[i] = label("Row" .. i, 56 + (i - 1) * ROW_H, ROW_H, 16, TEXT)
	rows[i].Visible = false
end
local note = label("Note", 56, 60, 16, DIM)
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Visible = false
local hint = label("Hint", 296, 20, 13, DIM)
hint.Text = "Walk up and press E (or tap): " .. BC.Text.Prompt

local function render(view)
	local friends = view.mode == "friends"
	-- the board counts a streak up to Config.Board.StreakCap (REVIEW-1 F5), and says so
	local metric = "best streak, up to " .. tostring(BC.StreakCap)
	modeLabel.Text = if friends then "👥 FRIENDS · " .. metric else "🌍 PUBLIC · " .. metric
	modeLabel.TextColor3 = if friends then Color3.fromRGB(150, 220, 255) else GOLD
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, l in rows do
		local r = list[i]
		if r then
			local you = r.you or r.userId == player.UserId
			local rank = tonumber(r.rank) or i
			l.Text = string.format("%s. %s%s   🔥 %d", if rank > 0 then tostring(rank) else "–", tostring(r.name or "?"),
				if you then " (you)" else "", tonumber(r.tier) or 0)
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
		note.Position = UDim2.new(0, 16, 0, 58 + #list * ROW_H)
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
