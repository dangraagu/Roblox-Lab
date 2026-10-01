-- Labyrinth Mariozo — the biome card never shares the screen with the daily-reward popup (second review, 30.09).
-- Run: luau check_labyrintspill_popups.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- The server fires the daily reward 2.5 s after a player's first spawn of the day (MazeGame.server,
-- onCharacterAdded), and HudClient shows it as a big popup in the middle of the screen for about 6.3 s
-- (DisplayOrder 12). The biome title card (Biome.client, DisplayOrder 11) waited only for the level-complete
-- card. The review measured, with real clients at 800x360 on a touch screen and the Group door taken 1.6 s after
-- spawn: the "Ice Cellar" card and the popup both visible for 2.67 s, the card's rect under the popup's. A
-- returning player who walks straight into a new biome loses that biome's "YOU REACHED" fanfare.
--
-- This file replays exactly that, through the real server and every client except SoundClient (see the lib),
-- and holds the card to: never on screen together with the popup for more than the one frame in which the
-- popup appears; the whole card is shown once the popup has gone; the fanfare flash plays once, not twice.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill popups")
local truthy, eq = T.truthy, T.eq

-- accepted 25: the Group door starts level 26, the first level of the Ice Cellar (a frontier fanfare)
local ctx = Lib.boot({ accepted = 25, clients = Lib.CLIENTS_NO_SOUND, viewport = { 800, 360 }, touch = true })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local root = ctx.plr.PlayerGui.LabyrintBiome.Root
local card = root.BandCard
local hudRoot = ctx.plr.PlayerGui.MedaljeHud.Root
local popup = hudRoot:FindFirstChild("DagligBelonning")
truthy(popup ~= nil, "HudClient built the daily-reward popup")

local flashes = 0
ctx.plr.PlayerGui.ChildAdded:Connect(function(c)
	if c.Name == "FxFlash" then flashes += 1 end
end)

-- the boot spawned the player 1.0 s ago (0.5 s before the clients loaded, 0.5 s after); take the Group door at 1.6 s
ctx.run(0.6)
local doorPrompt = h.workspace.Lobby.GroupDoor:FindFirstChildOfClass("ProximityPrompt")
doorPrompt.Triggered:Fire(ctx.plr)

local dt = 1 / 30
local both, popupSeen, cardSeen = 0, 0, 0
local cardAfterPopup, popupGoneAt = 0, nil
local titles = {}
local lastTitle = ""
for _ = 1, math.floor(16 / dt) do
	ctx.frame(dt)
	local c, p = card.Visible, popup and popup.Visible
	if c then
		cardSeen += dt
		if card.Text ~= lastTitle then
			lastTitle = card.Text
			table.insert(titles, card.Text)
		end
	else
		lastTitle = ""
	end
	if p then popupSeen += dt end
	if c and p then both += dt end
	if popupSeen > 0 and not p and popupGoneAt == nil then popupGoneAt = ctx.clock end
	if popupGoneAt and c then cardAfterPopup += dt end
end

print(string.format("   popup %.2f s, card %.2f s, both at once %.2f s, card after the popup %.2f s, titles: %s",
	popupSeen, cardSeen, both, cardAfterPopup, table.concat(titles, " | ")))
truthy(ctx.folder() ~= nil, "the Group door put the player in a maze")
truthy(popupSeen > 5, string.format("the daily-reward popup did show (%.2f s): the case is really exercised", popupSeen))
truthy(titles[1] ~= nil and string.find(titles[1], "YOU REACHED THE ICE CELLAR", 1, true) ~= nil,
	"the Ice Cellar fanfare card was shown (" .. tostring(titles[1]) .. ")")
truthy(both <= dt + 1e-6, string.format("the card and the popup are never on screen together for more than one frame (%.2f s)", both))
truthy(cardAfterPopup >= 3, string.format("the card is shown in full once the popup has gone (%.2f s after it)", cardAfterPopup))
eq(flashes, 1, "the fanfare flash plays once, not again when the card comes back")
truthy(not card.Visible, "and then it fades out")

T.finish(h)
