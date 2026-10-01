-- VAULT RUNNERS — the DEEPEST ESCAPES board by the hub spawn (client, display only). StarterPlayerScripts.
--
-- The server builds the sign (workspace.Hub.DeepestBoard) and its ProximityPrompt, owns every number on it,
-- and sends this player THEIR view over VaultRemotes.Board: { viewer, mode = "public"|"friends",
-- rows = { { rank, userId, name, depth, you? } }, note? }. Each player can look at Public or Friends, so the
-- board is drawn here, locally: a SurfaceGui this LocalScript puts under the sign exists on this client only.
-- It is NOT put in PlayerGui: the HUD fit check (check_vaulthud) measures everything in PlayerGui as screen
-- panels. This script fires no remote and writes nothing on the sign itself.
-- Shaped after plus1-jump's Board.client (the template game); the metric here is a DEPTH, and each row
-- carries the stratum that depth is in, so the brag (❄️ the Frozen Vault) reads on the board.
--
-- STREAMING-SAFE: if the place streams, the sign can leave this client while the runner is up in a vault
-- and come back as a new part. The drawing is mounted on whichever DeepestBoard is in the hub, again
-- whenever one arrives, and redrawn from the last view the server sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("VaultRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local BC = Config.Board

-- the stratum a depth is in, as the band chip names it: "29 ❄️" is the brag
local function stratumEmoji(depth: number): string
	local bands = Config.Env and Config.Env.Bands
	if type(bands) ~= "table" or type(depth) ~= "number" then return "" end
	return bands[EnvBands.indexAt(bands, depth)].emoji or ""
end

local GOLD = Color3.fromRGB(Config.Hud.AccentColor.r, Config.Hud.AccentColor.g, Config.Hud.AccentColor.b)
local TEXT = Color3.fromRGB(228, 226, 240)
local DIM = Color3.fromRGB(160, 156, 182)
local ICE = Color3.fromRGB(150, 220, 255)

local lastView = { mode = "public", rows = {}, note = BC.Text.Loading }
local ui = nil   -- { part, modeLabel, rows, note } of the drawing that is mounted now

local function label(frame: Frame, name: string, y: number, h: number, size: number, color: Color3, font: Enum.Font?): TextLabel
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

local function render(view)
	lastView = view
	if not ui then return end
	local friends = view.mode == "friends"
	ui.modeLabel.Text = if friends then "👥 FRIENDS" else "🌍 PUBLIC"
	ui.modeLabel.TextColor3 = if friends then ICE else GOLD
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, l in ui.rows do
		local r = list[i]
		if r then
			local you = r.you or r.userId == player.UserId
			local depth = tonumber(r.depth) or 0
			l.Text = string.format("%d. %s%s   depth %d %s", tonumber(r.rank) or i, tostring(r.name or "?"),
				if you then " (you)" else "", depth, stratumEmoji(depth))
			l.TextColor3 = if you then GOLD else TEXT
			l.Font = if you then Enum.Font.GothamBold else Enum.Font.GothamMedium
			l.Visible = true
		else
			l.Text = ""
			l.Visible = false
		end
	end
	if type(view.note) == "string" and view.note ~= "" then
		ui.note.Text = view.note
		ui.note.Position = UDim2.new(0, 24, 0, 84 + #list * 30)
		ui.note.Visible = true
	else
		ui.note.Text = ""
		ui.note.Visible = false
	end
end

-- Config.Board.Size (16 x 11 studs) at 40 px per stud = 640 x 440 px
local function mount(part: BasePart)
	if ui and ui.part == part and ui.gui.Parent == part then return end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DeepestGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.ClipsDescendants = true

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local title = label(frame, "Title", 10, 40, 32, GOLD, Enum.Font.GothamBlack)
	title.Text = "💎 " .. BC.Text.Title
	local rows = {}
	for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
		rows[i] = label(frame, "Row" .. i, 80 + (i - 1) * 30, 28, 22, TEXT)
		rows[i].Visible = false
	end
	local note = label(frame, "Note", 80, 90, 22, DIM)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.Visible = false
	local hint = label(frame, "Hint", 404, 28, 18, DIM)
	hint.Text = "Walk up and press E (or tap): " .. BC.Text.Prompt

	ui = { part = part, gui = gui, modeLabel = label(frame, "Mode", 50, 28, 22, TEXT, Enum.Font.GothamBold),
		rows = rows, note = note }
	gui.Parent = part
	render(lastView)
end

BoardEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then return end
	-- In Roblox FireClient reaches only this player; a view for someone else is never drawn here.
	if view.viewer ~= nil and view.viewer ~= player.UserId then return end
	render(view)
end)

local hub = workspace:WaitForChild("Hub", 60)
if not hub then
	warn("[Vault] the hub never arrived; the Deepest Escapes board stays blank for this player")
	return
end
hub.ChildAdded:Connect(function(child)
	if child.Name == "DeepestBoard" and child:IsA("BasePart") then mount(child) end
end)
local part = hub:WaitForChild("DeepestBoard", 60)
if part and part:IsA("BasePart") then
	mount(part)
else
	warn("[Vault] the Deepest Escapes board never arrived; the board stays blank for this player")
end
