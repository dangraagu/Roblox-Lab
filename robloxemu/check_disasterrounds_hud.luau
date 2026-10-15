-- Disaster Rounds - headless HUD fit check, panel overlap rule ON. Run: luau check_disasterrounds_hud.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- docs/complete-game-standard.md §2 "Phone first": a root Frame with a UIScale, nothing tappable under the thumbstick
-- or the jump button, tap targets of 44 screen px or more, and rule 4b (no two visible panels overlap) asserted with
-- `overlap = true`. DESIGN.md §12.1: the warmup shows each card, the Jump-in button, the threat banner and the Codex in
-- turn, because a control that only a remote or a mode makes visible is otherwise measured as absent. So every
-- viewport is measured in five HUD modes: idle, a card + a toast up, a round in progress with Jump-in shown and the
-- threat banner up, and the Codex open (which hides every other panel).
local HudCheck = require("./emu/hudcheck")

local base = table.clone(HudCheck.VIEWPORTS)
for _, v in {
	{ name = "iPhone SE landscape", w = 568, h = 320, touch = true },
	{ name = "iPhone 8 landscape", w = 667, h = 375, touch = true },
	{ name = "Android 740x360", w = 740, h = 360, touch = true },
	{ name = "iPhone 12 landscape", w = 844, h = 390, touch = true },
	{ name = "iPhone 8 portrait", w = 375, h = 667, touch = true },
	{ name = "Android portrait", w = 360, h = 800, touch = true },
} do
	table.insert(base, v)
end

local function hud(player)
	return player.PlayerGui:FindFirstChild("DRHud")
end
local function root(player)
	return hud(player):FindFirstChild("Root")
end
local function closeCodex(h, player)
	local codex = root(player):FindFirstChild("CodexPanel")
	if codex.Visible then
		root(player):FindFirstChild("CodexPanel"):FindFirstChild("CodexClose").Activated:Fire()
		h:advance(0.05)
	end
end

local MODES = {
	{
		suffix = "idle",
		before = function(h, player)
			closeCodex(h, player)
			h:advance(3) -- cards and toasts time out
			h.game:GetService("RunService").RenderStepped:Fire(0.05)
		end,
	},
	{
		suffix = "card + toast",
		before = function(h, player)
			closeCodex(h, player)
			local remotes = h.ReplicatedStorage:FindFirstChild("DRRemotes")
			remotes.Card:FireClient(player, "survived", { streak = 12, best = 12, newBest = true, heat = 5 })
			remotes.Toast:FireClient(player, "☄️ SomebodyWithALongName has survived 21 disasters. Their sky is falling.")
			h:advance(0.1)
			assert(root(player).CardPanel.Visible, "the card is up for this measurement")
			assert(root(player).ToastPanel.Visible, "the toast is up for this measurement")
		end,
	},
	{
		suffix = "in a round: Jump-in + banner",
		before = function(h, player)
			closeCodex(h, player)
			-- a disaster in progress the player is not in: Jump-in shows; a ring under them: the banner shows
			local rf = h.workspace:FindFirstChild("Round")
			local now = h.scheduler:now()
			rf:SetAttribute("Phase", "disaster")
			rf:SetAttribute("Kind", "meteor")
			rf:SetAttribute("NameAt", now - 5)
			rf:SetAttribute("PhaseEnds", now + 55)
			rf:SetAttribute("RoundId", 99)
			h.workspace:SetAttribute("ServerNow", now)
			player:SetAttribute("InRound", "")
			player:SetAttribute("SweptRound", nil)
			player:SetAttribute("Resting", false)
			h.game:GetService("RunService").RenderStepped:Fire(0.05)
			assert(root(player).JumpInButton.Visible, "Jump-in is up for this measurement")
			-- the banner: put the player in the round, with a ring at their feet
			player:SetAttribute("InRound", "practice")
			local char = player.Character
			local p = char and char:FindFirstChild("HumanoidRootPart").Position or Vector3.new(0, 0, 0)
			local ring = Instance.new("Part")
			ring.Name = "Ring"
			ring.Position = p
			ring:SetAttribute("ImpactAt", now + 2)
			ring:SetAttribute("Radius", 4.5)
			ring.Parent = rf:FindFirstChild("Rings")
			h.game:GetService("RunService").RenderStepped:Fire(0.05)
			assert(root(player).BannerPanel.Visible, "the banner is up for this measurement")
			-- and Jump-in shown at the same time as the banner: the worst case for the top-centre stack (the HUD never
			-- shows both, since Jump-in is for players off the island; measured anyway)
			root(player).JumpInButton.Visible = true
			root(player).BannerPanel.Visible = true
		end,
	},
	{
		suffix = "Codex open",
		before = function(h, player)
			local r = root(player)
			r:FindFirstChild("ButtonsPanel"):FindFirstChild("CodexButton").Activated:Fire()
			h:advance(0.05)
			assert(r.CodexPanel.Visible, "the Codex is open for this measurement")
		end,
	},
}

local viewports = {}
for _, mode in MODES do
	for _, v in base do
		local e = table.clone(v)
		e.name = v.name .. " [" .. mode.suffix .. "]"
		e.before = mode.before
		table.insert(viewports, e)
	end
end

HudCheck.run({
	viewports = viewports,
	overlap = true,
	game = "disaster-rounds",
	bundle = require("./build/disaster-rounds"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Board.client", "client/Sky.client", "client/World.client" },
	warmup = function(h, player)
		h.Players:simulateSpawn(player, h.workspace)
		h:advance(0.5)
	end,
})
