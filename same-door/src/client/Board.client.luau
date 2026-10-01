-- The Same Door — the hub board and the yesterday plaque, rendered by YOUR client.
-- StarterPlayerScripts.
--
-- The board is a physical Part the server builds facing the spawn (workspace.Hub.DoorBoard). Its rows
-- are drawn here, in a SurfaceGui this client parents to that Part, so each player can flip their
-- own view between Public and Friends (the board's ProximityPrompt, handled by the server) without
-- changing anyone else's. Rows arrive on the Board remote: public rows to everyone, friends rows to
-- the one who asked. Names and times are public by design; nothing here is secret.
-- The SurfaceGui lives under the Part in the workspace, not in PlayerGui, so the HUD fit gate does not
-- count it as screen furniture.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("SameDoorRemotes")
local BoardEvent = remotes:WaitForChild("Board")
local player = Players.LocalPlayer

local hub = workspace:WaitForChild("Hub")
local boardPart = hub:WaitForChild("DoorBoard")
local plaquePart = hub:WaitForChild("YesterdayPlaque")
local prompt = boardPart:WaitForChild("TogglePrompt")

local INK = Color3.fromRGB(244, 238, 228)
local DIM = Color3.fromRGB(190, 184, 176)
local PLATE = Color3.fromRGB(255, 250, 225)

local function surface(part: BasePart, name: string, px: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = name
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = px
	g.LightInfluence = 0.2
	g.Parent = part
	return g
end

-- Every label stays on its Part (a SurfaceGui clips to its canvas), and every label whose text varies
-- shrinks to fit (TextScaled, capped at `size` by a UITextSizeConstraint) or, for names, truncates
-- with "..." (REVIEW-1, reviewer 2: the first build's footer straddled the board's bottom edge and the
-- sub-line and SEALED rows ran off the right edge; check_samedoor audits every box).
local function label(parent: Instance, name: string, t: string, size: number, color: Color3, x: number, y: number, w: number, h: number,
	align: Enum.TextXAlignment?, truncate: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = t
	l.TextColor3 = color
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Size = UDim2.fromOffset(w, h)
	l.Position = UDim2.fromOffset(x, y)
	if truncate then
		l.TextTruncate = Enum.TextTruncate.AtEnd -- a long name ends in "...", the time and medal stay
	else
		l.TextScaled = true
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = size
		cap.MinTextSize = 8
		cap.Parent = l
	end
	l.Parent = parent
	return l
end

--============================================================================ the board
-- 12 x 12 studs at 40 px per stud: a 480 x 480 canvas, 16 px margins
local board = surface(boardPart, "BoardView", 40)
local title = label(board, "Title", "Today's board", 36, INK, 16, 8, 448, 42)
local sub = label(board, "Sub", "Public", 22, DIM, 16, 52, 448, 28)
-- a row: rank | name (truncates) | time | medal (a SEALED plate for a Sealer)
local rows = {}
for k = 1, Config.Board.PublicSize do
	local y = 86 + (k - 1) * 30
	local f = Instance.new("Frame")
	f.Name = "Row" .. k
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromOffset(16, y)
	f.Size = UDim2.fromOffset(448, 28)
	f.Parent = board
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = PLATE
	plate.BorderSizePixel = 0
	plate.Position = UDim2.fromOffset(366, 2)
	plate.Size = UDim2.fromOffset(82, 24)
	plate.Visible = false
	plate.Parent = f
	rows[k] = {
		frame = f,
		plate = plate,
		rank = label(f, "Rank", "", 22, DIM, 0, 0, 40, 28, Enum.TextXAlignment.Right),
		who = label(f, "Who", "", 22, INK, 48, 0, 214, 28, nil, true),
		time = label(f, "Time", "", 22, INK, 266, 0, 92, 28, Enum.TextXAlignment.Right),
		medal = label(f, "Medal", "", 20, DIM, 366, 2, 82, 24, Enum.TextXAlignment.Center),
	}
end
local foot = label(board, "Foot", "", 22, DIM, 16, 392, 448, 80)
foot.TextWrapped = true
foot.TextYAlignment = Enum.TextYAlignment.Top

-- the yesterday plaque: 8 x 5 studs = a 320 x 200 canvas (6 studs wide in the first build, too
-- narrow for "1. " and a 13-character name next to a time)
local plaque = surface(plaquePart, "PlaqueView", 40)
label(plaque, "Title", "Yesterday's Keepers", 24, INK, 12, 8, 296, 32)
local prows = {}
for k = 1, Config.Board.YesterdaySize do
	local y = 48 + (k - 1) * 30
	prows[k] = {
		who = label(plaque, "Row" .. k, "", 20, DIM, 12, y, 196, 28, nil, true),
		time = label(plaque, "Time" .. k, "", 20, DIM, 212, y, 96, 28, Enum.TextXAlignment.Right),
	}
end

local mode = "public"
local last: { [string]: any } = {}

local function render()
	local data = last[mode]
	title.Text = if data and data.door then ("Today's board - Door #" .. tostring(data.door)) else "Today's board"
	sub.Text = if mode == "friends" then "Friends (the board's prompt flips it back)" else "Public (the board's prompt shows friends)"
	local list = data and data.rows or {}
	for k, row in rows do
		local r = list[k]
		if r then
			local mine = r.userId == player.UserId
			local ink = if mine then Color3.fromRGB(150, 255, 210) else INK
			row.rank.Text = tostring(r.rank) .. "."
			row.who.Text = tostring(r.name)
			row.who.TextColor3 = ink
			row.time.Text = tostring(r.time)
			row.time.TextColor3 = ink
			-- a Sealer row carries the SEALED plate (the board's own brag moment)
			row.medal.Text = if r.sealed then "SEALED" else tostring(r.medal or "")
			row.medal.TextColor3 = if r.sealed then Color3.fromRGB(40, 36, 48) else DIM
			row.plate.Visible = r.sealed == true
		else
			row.rank.Text, row.who.Text, row.time.Text, row.medal.Text = "", "", "", ""
			row.plate.Visible = false
		end
	end
	if data and data.loading then
		foot.Text = tostring(data.text or "Loading...")
	elseif #list == 0 then
		foot.Text = tostring(data and data.empty or "")
	elseif data and data.partial then
		foot.Text = "Some friends could not be read just now; the rest are shown."
	else
		foot.Text = "Ties go to whoever got there first."
	end
	prompt.ActionText = if mode == "friends" then "Show public" else "Show friends"
end

BoardEvent.OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" then return end
	if p.mode == "yesterday" then
		local list = p.rows or {}
		for k, row in prows do
			local r = list[k]
			row.who.Text = if r then string.format("%d. %s", r.rank, tostring(r.name)) else ""
			row.time.Text = if r then tostring(r.time) else ""
		end
		return
	end
	if p.mode == "public" or p.mode == "friends" then
		-- store both; show the one this player chose (public rows keep arriving for everyone)
		last[p.mode] = p
		render()
	end
end)

-- the server flips the view on the prompt; this client mirrors it on its own prompt text
prompt.Triggered:Connect(function(who)
	if who ~= player then return end
	mode = if mode == "friends" then "public" else "friends"
	render()
end)

render()
