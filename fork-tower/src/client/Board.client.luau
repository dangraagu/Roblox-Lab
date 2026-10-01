-- FORK TOWER — the toplist board at the back of YOUR tower's lobby (client, display only). Lands in
-- StarterPlayerScripts. Built on +1 Jump's Board.client (the template the board's rules come from).
--
-- The server builds a board in every tower (Lane_n.TopBoard, with its ProximityPrompt), owns every number on it
-- and sends this player THEIR view over ForkRemotes.Board: { viewer, mode = "public"|"friends", rows = { { rank,
-- userId, name, tier, you? } }, note? } (`tier` is the template's name for the metric: here, the best Build
-- Reveal score). Each player can look at Public or Friends, so the board is drawn here, locally: a SurfaceGui
-- this LocalScript creates under the player's OWN tower's board exists on this client only. It is NOT put in
-- PlayerGui: robloxemu's HUD fit check measures everything in PlayerGui as screen panels.
--
-- The tower is rebuilt on every rebirth (a new Lane folder, a new board), so this follows it: a few times a
-- second it looks for the board in the lane whose Owner attribute is this player (the way Ambience finds the
-- lane), and draws the last view again on a new board.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("ForkRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Build = require(ReplicatedStorage:WaitForChild("Build"))
local BC = Config.Board

local GOLD = Color3.fromRGB(255, 215, 90)
local TEXT = Color3.fromRGB(225, 230, 245)
local DIM = Color3.fromRGB(150, 158, 185)
local FRIENDS = Color3.fromRGB(150, 220, 255)

local function rarityOf(score: number): string
	local r = Config.Build.Rarities[Build.rarityFor(Config, score)]
	return if r then r.name else ""
end

local lastView: any = { mode = "public", rows = {}, note = BC.Text.Loading }
local board: BasePart? = nil
local gui: SurfaceGui? = nil
local modeLabel: TextLabel? = nil
local note: TextLabel? = nil
local rows: { TextLabel } = {}

local function render(view)
	if gui == nil or modeLabel == nil or note == nil then
		return
	end
	local friends = view.mode == "friends"
	modeLabel.Text = if friends then "👥 VENNER" else "🌍 OFFENTLIG"
	modeLabel.TextColor3 = if friends then FRIENDS else GOLD
	local list = if type(view.rows) == "table" then view.rows else {}
	for i, l in rows do
		local r = list[i]
		if r then
			local you = r.you or r.userId == player.UserId
			local score = tonumber(r.tier) or 0
			l.Text = string.format("%d. %s%s   %d  %s", r.rank or i, tostring(r.name or "?"), if you then " (deg)" else "",
				score, rarityOf(score))
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

-- 14 x 11 studs at 40 px per stud = 560 x 440 px
local function drawOn(part: BasePart)
	if gui then
		(gui :: SurfaceGui):Destroy()
	end
	table.clear(rows)
	local g = Instance.new("SurfaceGui")
	g.Name = "TopBoardGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.ClipsDescendants = true

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 18, 34)
	frame.BorderSizePixel = 0
	frame.Parent = g

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

	local title = label("Title", 10, 40, 30, GOLD, Enum.Font.GothamBlack)
	title.Text = "🏆 " .. BC.Text.Title
	modeLabel = label("Mode", 50, 28, 22, TEXT, Enum.Font.GothamBold)
	for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
		rows[i] = label("Row" .. i, 80 + (i - 1) * 30, 28, 22, TEXT)
		rows[i].Visible = false
	end
	local n = label("Note", 80, 90, 22, DIM)
	n.TextWrapped = true
	n.TextYAlignment = Enum.TextYAlignment.Top
	n.Visible = false
	note = n
	local hint = label("Hint", 404, 28, 18, DIM)
	hint.Text = "Gå bort og trykk E (eller trykk på knappen): " .. BC.Text.Prompt

	g.Parent = part
	gui = g
	board = part
	render(lastView)
end

local function myBoard(): BasePart?
	local towers = workspace:FindFirstChild("Towers")
	if towers == nil then
		return nil
	end
	for _, c in towers:GetChildren() do
		if c:GetAttribute("Owner") == player.UserId then
			local b = c:FindFirstChild("TopBoard")
			return if b and b:IsA("BasePart") then b :: BasePart else nil
		end
	end
	return nil
end

local function follow()
	local b = myBoard()
	if b ~= nil and (b ~= board or gui == nil or (gui :: SurfaceGui).Parent ~= b) then
		drawOn(b)
	end
end

BoardEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then
		return
	end
	-- In Roblox FireClient reaches only this player; a view for someone else is never drawn here.
	if view.viewer ~= nil and view.viewer ~= player.UserId then
		return
	end
	lastView = view
	follow()
	render(view)
end)

task.spawn(function()
	while true do
		follow()
		task.wait(0.5)
	end
end)
