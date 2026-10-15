-- FIND IT! CHAPTERS: the friends face of the Cases Solved board, for THIS player only (DESIGN.md §11).
-- The public face is server-built (workspace.FindItWorld.Hub.CasesBoard.PublicFace). When this player toggles to
-- Friends (the board's ProximityPrompt; the server answers on the Board remote), this script draws a LOCAL
-- SurfaceGui on the board part itself (never in PlayerGui, where the HUD fit check would measure it as screen),
-- hides the public face for this player, and renames the prompt to "Show public". Toggling back restores both.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("FindItRemotes")
local BoardEv = remotes:WaitForChild("Board") :: RemoteEvent

local world = workspace:WaitForChild("FindItWorld")
local board = world:WaitForChild("Hub"):WaitForChild("CasesBoard") :: BasePart
local publicFace = board:WaitForChild("PublicFace") :: SurfaceGui
local togglePrompt = board:WaitForChild("BoardToggle") :: ProximityPrompt
local BT = Config.Board.Text

local face: SurfaceGui? = nil

local function label(parent: Instance, name: string, text: string, y: number, h: number, color: Color3)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.06, y)
	l.Size = UDim2.fromScale(0.88, h)
	l.Text = text
	l.TextScaled = true
	l.TextWrapped = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.Parent = parent
	return l
end

local function showPublic()
	if face then
		face:Destroy()
		face = nil
	end
	publicFace.Enabled = true
	togglePrompt.ActionText = BT.ShowFriends
end

local function showFriends(view: any)
	publicFace.Enabled = false
	togglePrompt.ActionText = BT.ShowPublic
	if face == nil then
		local g = Instance.new("SurfaceGui")
		g.Name = "FriendsFace"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		g.LightInfluence = 0
		g.Parent = board
		face = g
	end
	local g = face :: SurfaceGui
	g:ClearAllChildren()
	label(g, "Title", BT.Title .. "  \u{00B7}  FRIENDS", 0.02, 0.1, Color3.fromRGB(150, 230, 255))
	local rows = view.rows or {}
	for i = 1, Config.Board.FriendsRows do
		local r = rows[i]
		local text = if r then string.format("%d.  %s%s   %d", r.rank, r.name, if r.you then " (you)" else "", r.solved or 0) else ""
		label(g, "Row_" .. i, text, 0.13 + (i - 1) * 0.074, 0.066, if r and r.you then Color3.fromRGB(255, 226, 150) else Color3.fromRGB(250, 244, 230))
	end
	label(g, "Note", view.message or "", 0.86, 0.12, Color3.fromRGB(230, 220, 200))
end

BoardEv.OnClientEvent:Connect(function(view: any)
	if type(view) ~= "table" then return end
	if view.mode == "friends" then showFriends(view) else showPublic() end
end)

togglePrompt.ActionText = BT.ShowFriends
