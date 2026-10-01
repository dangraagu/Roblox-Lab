-- DEEP VEIN ⛏️ — the Deepest Miners board in your own mouth (client, display only). Havner i StarterPlayerScripts.
--
-- After +1 Jump's Board.client.luau. The server builds each miner's board (workspace.DeepBoards.DeepestBoard_<id>,
-- on the south wall of their mouth) and its ProximityPrompt, owns every number on it and sends this player THEIR
-- view over VeinRemotes.Board: { viewer, mode = "public"|"friends", rows = { { rank, userId, name, tier, you? } },
-- note? }. `tier` is the template's name for the metric: here the deepest LAYER, shown in m (x CellSize) with the
-- emoji of the stratum it reaches, as on the HUD. Each player can look at Public or Friends, so the board is drawn
-- here, locally: a SurfaceGui this LocalScript creates under the player's OWN board exists on this client only.
-- It is NOT put in PlayerGui: robloxemu's HUD fit check measures everything in PlayerGui as screen panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("VeinRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local BC = Config.Board

-- the stratum a layer belongs to, as on the HUD's top list: "300 m 🔥" is the brag
local function strataEmoji(layer: number): string
	local bands = Config.Env and Config.Env.Bands
	if type(bands) ~= "table" or #bands == 0 or type(layer) ~= "number" then return "" end
	local b = bands[EnvBands.indexAt(bands, layer)]
	return if b and b.emoji then " " .. b.emoji else ""
end

local folder = workspace:WaitForChild("DeepBoards", 60)
local part = folder and folder:WaitForChild("DeepestBoard_" .. player.UserId, 60)
if not part then
	warn("[DeepVein] this miner's board never arrived; it stays blank for this player")
	return
end

local GOLD = Color3.fromRGB(255, 205, 100)
local TEXT = Color3.fromRGB(228, 226, 236)
local DIM = Color3.fromRGB(160, 154, 176)

-- 22 x 12 studs at 40 px per stud = 880 x 480 px
local gui = Instance.new("SurfaceGui")
gui.Name = "DeepestMinersGui"
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 40
gui.LightInfluence = 0 -- the mine is dark; the board reads by its own light
gui.ClipsDescendants = true
gui.Parent = part

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
frame.BorderSizePixel = 0
frame.Parent = gui

local function label(name: string, y: number, h: number, size: number, color: Color3, font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 28, 0, y)
	l.Size = UDim2.new(1, -56, 0, h)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = frame
	return l
end

local ROW_Y, ROW_H = 98, 32
local title = label("Title", 10, 46, 36, GOLD, Enum.Font.GothamBlack)
title.Text = "⛏️ " .. BC.Text.Title
local modeLabel = label("Mode", 58, 32, 26, TEXT, Enum.Font.GothamBold)
local rows = {}
for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
	rows[i] = label("Row" .. i, ROW_Y + (i - 1) * ROW_H, ROW_H - 2, 25, TEXT)
	rows[i].Visible = false
end
local note = label("Note", ROW_Y, 96, 25, DIM)
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Visible = false
local hint = label("Hint", 442, 30, 21, DIM)
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
			local layer = tonumber(r.tier) or 0
			l.Text = string.format("%d. %s%s   %d m%s", r.rank or i, tostring(r.name or "?"), if you then " (you)" else "",
				layer * Config.Mine.CellSize, strataEmoji(layer))
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
		note.Position = UDim2.new(0, 28, 0, ROW_Y + 4 + #list * ROW_H)
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
