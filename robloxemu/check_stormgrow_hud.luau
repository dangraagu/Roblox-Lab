-- StormGrow — the HUD fits a phone: every viewport, in every mode, with the panel-overlap rule ON.
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_hud.luau 2>&1
--
-- emu/hudcheck measures: nothing off screen, tap targets >= 44 screen px on touch, nothing tappable under the
-- thumbstick or the jump button, panels covering <= 50 % of a phone, and (overlap = true) no two visible
-- panels on top of each other (rule 4b). A sweep that only sees the idle HUD scores every other mode as a
-- pass because its panels are invisible, so each viewport is measured four times, with the HUD put into the
-- mode the way a player does it (pressing its own buttons):
--   idle      - everything closed (on a wide screen the Seeds column is always open), a long toast up
--   seeds     - the 🌱 Seeds drawer open (a phone); on a wide screen the same as idle
--   timeline  - the forecast chip tapped: the 30-minute timeline open
--   almanac   - 📖 tapped: the Almanac modal open (it hides Seeds and the timeline)
-- All three client scripts run, so everything that draws on the screen is measured.

local HudCheck = require("./emu/hudcheck")

local LONG_TOAST = "📖 3 NEW in the Almanac: ⚡❄️ Stormglass Watermelon, ⚡🌈 Radiant Watermelon, ❄️🌈 Aurora Pumpkin"

local function root(player)
	return player.PlayerGui.StormHud.Root
end

local function press(button)
	button.Activated:Fire()
end

local function closeAll(h, player)
	local r = root(player)
	if r.Almanac.Visible then press(r.Almanac.AlmanacClose) end
	if r.Timeline.Visible then press(r.TopBar.Forecast) end
	if r.Toggles.SeedsButton.Visible and r.Seeds.Visible then press(r.Toggles.SeedsButton) end
	h:advance(0.05)
end

local function toast(h, player)
	local remotes = h.ReplicatedStorage.StormRemotes
	remotes.Toast:FireClient(player, LONG_TOAST, "good")
	h:advance(0.05)
end

local modes = {
	{ "idle", function(h, player)
		closeAll(h, player)
		toast(h, player)
	end },
	{ "seeds", function(h, player)
		closeAll(h, player)
		local r = root(player)
		if r.Toggles.SeedsButton.Visible then press(r.Toggles.SeedsButton) end
		h:advance(0.05)
		assert(r.Seeds.Visible, "seeds mode: the Seeds panel did not open")
		toast(h, player)
	end },
	{ "timeline", function(h, player)
		closeAll(h, player)
		local r = root(player)
		press(r.TopBar.Forecast)
		h:advance(0.05)
		assert(r.Timeline.Visible, "timeline mode: the timeline did not open")
		toast(h, player)
	end },
	{ "almanac", function(h, player)
		closeAll(h, player)
		local r = root(player)
		press(r.Toggles.AlmanacButton)
		h:advance(0.05)
		assert(r.Almanac.Visible and not r.Seeds.Visible and not r.Timeline.Visible,
			"almanac mode: the Almanac must be open and hide Seeds and the timeline")
		toast(h, player)
	end },
}

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	for _, mode in modes do
		table.insert(viewports, { name = v.name .. ", " .. mode[1], w = v.w, h = v.h, touch = v.touch, before = mode[2] })
	end
end

HudCheck.run({
	game = "stormgrow",
	bundle = require("./build/stormgrow"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Farm.client", "client/Sky.client" },
	viewports = viewports,
	overlap = true,
	warmup = function(h, player)
		-- the client scripts' RenderStepped work (labels, the seed rows' text) runs once so every label has
		-- its real, longest text before anything is measured
		local rs = h.game:GetService("RunService")
		h.game:GetService("RunService"):setIsServer(false)
		for _ = 1, 5 do
			rs.RenderStepped:Fire(0.1)
			h:advance(0.1)
		end
		print(string.format("   warmup %-28s loaded=%s coins=%s", "5 frames,", tostring(player:GetAttribute("Loaded")), tostring(player:GetAttribute("Coins"))))
	end,
})
