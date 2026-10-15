-- Gnome Garden Defense: headless HUD fit check, Hud.client + Garden.client together, panel-overlap rule ON.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_hud.luau
--
-- The HUD has MODES, and a sweep that only sees the idle one scores every other mode as a pass (hudcheck.luau's
-- `before` hook exists for exactly this). So every viewport is measured three times over: the idle reveal (top
-- bar, the band chip + PAUSE row, READY), the gnome sheet open (a pad tapped), and the result panel up (a lost
-- attempt, as the server's attributes would say it). Phones from deep-vein's list are added: the row under the
-- top bar is tightest there.

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

local function myGarden(h, player)
	for _, g in h.workspace.Gardens:GetChildren() do
		if g:GetAttribute("Owner") == player.UserId then return g end
	end
	error("the player has no garden")
end

local function tapPad(h, player)
	local g = myGarden(h, player)
	g:SetAttribute("Phase", "reveal")
	-- a tap on the garden is picked by View.client and handed to the HUD through GardenClientState (REVIEW-1:
	-- pads have no ClickDetector); the HUD's side of it is these two attributes
	local state = player.PlayerGui:FindFirstChild("GardenClientState")
	assert(state, "the HUD's client state exists")
	state:SetAttribute("PickPad", 1)
	state:SetAttribute("PickSeq", (state:GetAttribute("PickSeq") or 0) + 1)
end

local function lost(h, player)
	local g = myGarden(h, player)
	g:SetAttribute("Phase", "lost")
	h.ReplicatedStorage.GardenRemotes.Fanfare:FireClient(player, { kind = "lost", o = player.UserId, wave = 7, season = "Spring" })
end

local function idle(h, player)
	local g = myGarden(h, player)
	g:SetAttribute("Phase", "reveal")
	local close = player.PlayerGui.GardenHud.Root.GnomeSheet.CloseButton
	close.Activated:Fire()
end

local viewports = {}
for _, v in base do
	table.insert(viewports, { name = v.name, w = v.w, h = v.h, touch = v.touch, before = idle })
end
for _, v in base do
	table.insert(viewports, { name = v.name .. " + sheet", w = v.w, h = v.h, touch = v.touch, before = tapPad })
end
for _, v in base do
	table.insert(viewports, { name = v.name .. " + result", w = v.w, h = v.h, touch = v.touch, before = lost })
end

HudCheck.run({
	viewports = viewports,
	overlap = true,
	game = "gnome-garden-defense",
	bundle = require("./build/gnome-garden-defense"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Garden.client" },
	warmup = function(h, player)
		h.Players:simulateSpawn(player, h.workspace)
	end,
})
