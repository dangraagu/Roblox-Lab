-- STEAL A CRYPTID - the Top Lairs boards (client, display only). Lives in StarterPlayerScripts.
--
-- The server builds a TopLairsBoard and its ProximityPrompt on every plot's front fence, owns every number on it and
-- sends this player THEIR view over CryptidRemotes.Board: { viewer, mode = "public"|"friends", rows = { { rank,
-- userId, name, tier, you? } }, note? }. `tier` is the template's name for the metric: here the best lair income a
-- player has ever had, in Essence/s. Each player looks at Public or Friends, so the boards are drawn here, locally:
-- a SurfaceGui this LocalScript creates under a board part exists on this client only. Every plot's board shows this
-- player's view, so the road never shows a blank one. Nothing goes in PlayerGui (the HUD gates measure everything
-- there as screen panels).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("CryptidRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local BC = Config.Board

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local GOLD = rgb(Config.Hud.Gold)
local TEXT = Color3.fromRGB(225, 230, 240)
local DIM = Color3.fromRGB(150, 158, 175)
local FRIEND = Color3.fromRGB(150, 220, 255)

-- 12 x 8 studs at 40 px per stud = 480 x 320 px
local PPS = 40
local ROW_Y, ROW_H = 68, 22

-- 4050 -> "4,050"
local function grouped(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return out
end

local current: any = { mode = "public", rows = {}, note = BC.Text.Loading }
local boards: { any } = {}

local function label(parent: Instance, name: string, x: number, y: number, w: number, hgt: number, size: number,
	color: Color3, font: Enum.Font, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, x, 0, y)
	l.Size = UDim2.new(0, w, 0, hgt)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = align
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = parent
	return l
end

local function build(part: BasePart): any
	local w, hgt = part.Size.X * PPS, part.Size.Y * PPS
	local gui = Instance.new("SurfaceGui")
	gui.Name = "TopLairsGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(Config.Hud.Panel)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local b: any = { rows = {} }
	b.title = label(frame, "Title", 20, 8, w - 40, 34, 30, GOLD, Enum.Font.GothamBlack, Enum.TextXAlignment.Left)
	b.title.Text = BC.Text.Title
	b.mode = label(frame, "Mode", 20, 42, w - 40, 22, 18, TEXT, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
		local y = ROW_Y + (i - 1) * ROW_H
		b.rows[i] = {
			name = label(frame, "Row" .. i .. "Name", 20, y, w - 160, ROW_H - 1, 18, TEXT, Enum.Font.GothamMedium, Enum.TextXAlignment.Left),
			value = label(frame, "Row" .. i .. "Value", w - 140, y, 120, ROW_H - 1, 18, TEXT, Enum.Font.GothamBold, Enum.TextXAlignment.Right),
		}
	end
	b.note = label(frame, "Note", 20, ROW_Y, w - 40, 80, 18, DIM, Enum.Font.GothamMedium, Enum.TextXAlignment.Left)
	b.note.TextWrapped = true
	b.note.TextTruncate = Enum.TextTruncate.None
	b.note.TextYAlignment = Enum.TextYAlignment.Top
	b.hint = label(frame, "Hint", 20, hgt - 26, w - 40, 20, 14, DIM, Enum.Font.GothamMedium, Enum.TextXAlignment.Left)
	b.hint.Text = BC.Text.Hint
	gui.Parent = part
	return b
end

local function render(b: any)
	local view = current
	local friends = view.mode == "friends"
	b.mode.Text = if friends then "FRIENDS - best lair income" else "PUBLIC - best lair income"
	b.mode.TextColor3 = if friends then FRIEND else GOLD
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, row in b.rows do
		local r = list[i]
		if r then
			local you = r.you or r.userId == player.UserId
			row.name.Text = string.format("%d. %s%s", tonumber(r.rank) or i, tostring(r.name or "?"), if you then " (you)" else "")
			row.value.Text = grouped(tonumber(r.tier) or 0) .. BC.Text.Unit
			local color = if you then GOLD else TEXT
			row.name.TextColor3 = color
			row.value.TextColor3 = color
			row.name.Visible = true
			row.value.Visible = true
		else
			row.name.Text = ""
			row.value.Text = ""
			row.name.Visible = false
			row.value.Visible = false
		end
	end
	if type(view.note) == "string" and view.note ~= "" then
		b.note.Text = view.note
		b.note.Position = UDim2.new(0, 20, 0, ROW_Y + #list * ROW_H + 4)
		b.note.Visible = true
	else
		b.note.Text = ""
		b.note.Visible = false
	end
end

BoardEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then return end
	-- In Roblox FireClient reaches only this player; a view for someone else is never drawn here.
	if view.viewer ~= nil and view.viewer ~= player.UserId then return end
	current = view
	for _, b in boards do render(b) end
end)

-- The boards are built with the plots at server start, but a LocalScript can run before the workspace reaches it
-- (CLAUDE.md Traps 22): take the ones that are there, and every one that arrives later.
local lairs = workspace:WaitForChild("Lairs", 60)
if not lairs then
	warn("[Cryptid] workspace.Lairs never arrived; the Top Lairs boards stay blank for this player")
	return
end
local seen: { [Instance]: boolean } = {}
local function consider(d: Instance)
	if d.Name == "TopLairsBoard" and d:IsA("BasePart") and not seen[d] then
		seen[d] = true
		local b = build(d :: BasePart)
		table.insert(boards, b)
		render(b)
	end
end
for _, d in lairs:GetDescendants() do consider(d) end
lairs.DescendantAdded:Connect(consider)
