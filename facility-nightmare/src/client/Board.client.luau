-- Board.client.luau — the TOP DIVERS board in the break room (client, display only). StarterPlayerScripts.
--
-- The server builds the board (workspace.Hub.TopDiversBoard) and its ProximityPrompt, owns every number on it, and
-- sends THIS player their view over FacilityRemotes.Board: { viewer, mode = "public" | "friends", rows = { { rank,
-- userId, name, tier, you? } }, note? } (docs/complete-game-standard.md §3). Each player may look at Public or
-- Friends, so the board is drawn here, locally: a SurfaceGui this LocalScript creates under the board part exists on
-- this client only. It is NOT in PlayerGui: robloxemu's HUD fit check measures everything there as screen panels.
--
-- A row gives the depth (the deepest sublevel whose lift that player powered) and its band's name, but only for a
-- band THIS player has reached; deeper bands stay ??? here, as on the DEPTH RECORD board (no spoilers).
-- It fires no remote and reads nothing but its own State and its own board view.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local remotes = ReplicatedStorage:WaitForChild("FacilityRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local StateEvent = remotes:WaitForChild("State")

local player = Players.LocalPlayer
local BC = Config.Board
local bands = Config.Env and Config.Env.Bands

local hub = workspace:WaitForChild("Hub", 60)
local part = hub and hub:WaitForChild("TopDiversBoard", 60)
if not part then
	warn("[FacilityBoard] the TOP DIVERS board never arrived; it stays blank for this player")
	return
end

local function rgb(t)
	return Color3.fromRGB(t.r, t.g, t.b)
end
local AMBER = rgb(Config.Hud.Accent)
local TEXT = Color3.fromRGB(226, 228, 232)
local DIM = Color3.fromRGB(140, 144, 152)
local FRIENDS = Color3.fromRGB(150, 210, 255)

-- 100 px per stud, the canvas in the face's proportions (trap 14: a fixed canvas is stretched onto its face)
local gui = Instance.new("SurfaceGui")
gui.Name = "TopDiversGui"
gui.Face = Enum.NormalId.Front
gui.CanvasSize = Vector2.new(math.floor((part :: BasePart).Size.X * 100 + 0.5), math.floor((part :: BasePart).Size.Y * 100 + 0.5))
gui.LightInfluence = 0
gui.ClipsDescendants = true
gui.Parent = part

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(16, 17, 21)
frame.BorderSizePixel = 0
frame.Parent = gui

local function label(name: string, y: number, h: number, size: number, color: Color3, font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 40, 0, y)
	l.Size = UDim2.new(1, -80, 0, h)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = frame
	return l
end

local title = label("Title", 18, 70, 60, AMBER, Enum.Font.GothamBlack)
title.Text = BC.Text.Title
local modeLabel = label("Mode", 92, 40, 32, TEXT, Enum.Font.GothamBold)
local ROW_Y, ROW_H = 140, 46
local rows = {}
for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
	rows[i] = label("Row" .. i, ROW_Y + (i - 1) * ROW_H, ROW_H - 4, 34, TEXT)
	rows[i].Visible = false
end
local note = label("Note", ROW_Y, 120, 32, DIM)
note.TextWrapped = true
note.TextYAlignment = Enum.TextYAlignment.Top
note.Visible = false
local hint = label("Hint", 650, 40, 26, DIM)
hint.Text = "Walk up and press E (or tap): " .. BC.Text.Prompt

-- The band a depth belongs to, named only if THIS player's own record has reached it.
local viewerBest = 0
local function bandLabel(tier: number): string
	if type(bands) ~= "table" or #bands == 0 then return "" end
	local b = bands[EnvBands.indexAt(bands, tier)]
	if not b then return "" end
	if viewerBest >= math.max(1, b.from) then return b.name end
	return "???"
end

local lastView: any = { mode = "public", rows = {}, note = BC.Text.Loading }
local function render(view)
	lastView = view
	local friends = view.mode == "friends"
	modeLabel.Text = if friends then "FRIENDS — deepest sublevel powered" else "PUBLIC — deepest sublevel powered"
	modeLabel.TextColor3 = if friends then FRIENDS else TEXT
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, l in rows do
		local r = list[i]
		if r then
			local you = r.you == true or r.userId == player.UserId
			local tier = tonumber(r.tier) or 0
			l.Text = string.format("%d. %s%s  —  %d  %s", tonumber(r.rank) or i, tostring(r.name or "?"),
				if you then " (you)" else "", tier, bandLabel(tier))
			l.TextColor3 = if you then AMBER else TEXT
			l.Font = if you then Enum.Font.GothamBold else Enum.Font.GothamMedium
			l.Visible = true
		else
			l.Text = ""
			l.Visible = false
		end
	end
	if type(view.note) == "string" and view.note ~= "" then
		local y = ROW_Y + #list * ROW_H + 4
		note.Text = view.note
		note.Position = UDim2.new(0, 40, 0, y)
		note.Size = UDim2.new(1, -80, 0, math.max(40, 646 - y)) -- down to the hint line, never over it
		note.Visible = true
	else
		note.Text = ""
		note.Visible = false
	end
end

render(lastView)

BoardEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then return end
	-- In Roblox FireClient reaches only this player; a view addressed to someone else is never drawn here.
	if view.viewer ~= nil and view.viewer ~= player.UserId then return end
	render(view)
end)

-- Own record from the State: when it rises, the band names this player has now reached appear.
StateEvent.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	local best = tonumber(s.bestSublevel) or 0
	if best ~= viewerBest then
		viewerBest = best
		render(lastView)
	end
end)
