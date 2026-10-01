--[[==================================================================
	LABYRINT-SPILL  -  TOPPLISTA-TAVLA VED SPAWN (klient, bare tegning)

	Serveren bygger tavla (workspace.Lobby.TopBoard) og ProximityPrompten, eier hvert tall på den og sender
	DENNE spilleren SIN visning over HudRemotes.Board: { viewer, mode = "public"|"friends", rows = { { rank,
	userId, name, tier, you? } }, note? }. `tier` er nivået (accepted). Hver spiller kan se Public eller Friends,
	så tavla tegnes her, lokalt: en SurfaceGui laget av dette LocalScriptet under tavla finnes bare hos denne
	klienten. Den legges IKKE i PlayerGui: robloxemu sin HUD-sjekk måler alt der som skjerm-paneler.
	Etter +1 Jumps Board.client (malen for docs/complete-game-standard.md §3).
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local BC = require(ReplicatedStorage:WaitForChild("BoardConfig"))
local Biomes = require(ReplicatedStorage:WaitForChild("Biomes"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))

-- biomen et nivå hører til, som på biome-tavla ved bålet: "57 🔥" er skrytet
local function biomeEmoji(level: number): string
	if type(level) ~= "number" or level < 1 then return "" end
	local ok, band = pcall(Biomes.band, EnvBands, level)
	return (ok and band and band.emoji) or ""
end

local lobby = workspace:WaitForChild("Lobby", 60)
local part = lobby and lobby:WaitForChild("TopBoard", 60)
if not part then
	warn("[Labyrint] topplista-tavla kom aldri; den står tom for denne spilleren")
	return
end

local GOLD = Color3.fromRGB(255, 215, 90)
local TEXT = Color3.fromRGB(225, 230, 245)
local DIM = Color3.fromRGB(150, 158, 185)

-- 14 x 10 studs à 40 px per stud = 560 x 400 px
local gui = Instance.new("SurfaceGui")
gui.Name = "TopBoardGui"
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 40
gui.LightInfluence = 0
gui.ClipsDescendants = true
gui.Parent = part

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 34)
frame.BorderSizePixel = 0
frame.Parent = gui

local function label(name: string, y: number, h: number, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 22, 0, y)
	l.Size = UDim2.new(1, -44, 0, h)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = frame
	return l
end

local title = label("Title", 8, 38, 30, GOLD, Enum.Font.GothamBlack)
title.Text = "🏆 " .. BC.Text.Title
local modeLabel = label("Mode", 46, 26, 21, TEXT, Enum.Font.GothamBold)
local rows = {}
for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
	rows[i] = label("Row" .. i, 74 + (i - 1) * 28, 26, 20, TEXT)
	rows[i].Visible = false
end
local note = label("Note", 76, 90, 20, DIM)
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Visible = false
local hint = label("Hint", 366, 26, 17, DIM)
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
			local level = tonumber(r.tier) or 0
			l.Text = string.format("%d. %s%s   Level %d %s", r.rank or i, tostring(r.name or "?"), if you then " (you)" else "",
				level, biomeEmoji(level))
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
		note.Position = UDim2.new(0, 22, 0, 80 + #list * 28)
		note.Visible = true
		hint.Visible = 80 + #list * 28 + 26 <= 366 -- a note under a full list takes the hint's line
	else
		hint.Visible = true
		note.Text = ""
		note.Visible = false
	end
end

render({ mode = "public", rows = {}, note = BC.Text.Loading })

local remotes = ReplicatedStorage:WaitForChild("HudRemotes")
local BoardEvent = remotes:WaitForChild("Board")
BoardEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then return end
	-- I Roblox når FireClient bare denne spilleren; en visning for noen andre tegnes aldri her.
	if view.viewer ~= nil and view.viewer ~= player.UserId then return end
	render(view)
end)
