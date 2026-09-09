-- nightwatch-manor — headless HUD fit check. Run: luau check_nightwatch_hud.luau
-- Regenerate the bundle first:
--   py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
require("./emu/hudcheck").run({
	game = "nightwatch-manor",
	bundle = require("./build/nightwatch-manor"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
	-- The upgrade rows inside the safehouse ScrollingFrame are created by the client's State
	-- handler and by nothing else. With no State push the list stays empty, its content size is
	-- zero, and the canvas rule measures nothing — a PASS that means far less than it reads as.
	--
	-- The payload is not written here. The server already pushed one at join, before the client
	-- script existed to hear it, and the remote shim recorded it, so the fixture is the real
	-- server's own state for a fresh player rather than a hand-made table that can drift.
	warmup = function(h, player)
		local remotes = h.ReplicatedStorage:FindFirstChild("ManorRemotes")
		assert(remotes ~= nil, "the server created no ManorRemotes folder")
		local state = remotes:FindFirstChild("State")
		assert(state ~= nil, "ManorRemotes has no State remote")
		local sent = state:getSent()
		assert(#sent > 0, "the server never pushed State at join; there is no payload to replay")
		local payload = sent[#sent].args[1]
		assert(type(payload) == "table" and payload.upgrades ~= nil, "the recorded State payload carries no upgrades")
		state:FireClient(player, payload)
		print(string.format("   warmup %-28s %d upgrade rows built", "State replayed,", #payload.upgrades))

		-- OPEN BOTH PHONE DRAWERS. Without this every touch viewport in the list reports
		-- "(2 closed, position unmeasured)" and passes trivially: a drawer parked shut says
		-- nothing about where it opens, which is exactly where a phone HUD goes wrong. Firing
		-- the toggles flips the client's own state, so the rest of the run measures the panels
		-- as a player who opened them would see them.
		local gui = player:FindFirstChild("PlayerGui"):FindFirstChild("NightwatchHud")
		assert(gui ~= nil, "the client built no NightwatchHud")
		local root = gui:FindFirstChild("Root")
		assert(root ~= nil, "the HUD has no scaling Root frame")
		local opened = 0
		for _, name in { "StatusToggle", "SafehouseToggle" } do
			local b = root:FindFirstChild(name)
			assert(b ~= nil, "the HUD has no " .. name)
			b.Activated:Fire()
			opened += 1
		end
		print(string.format("   warmup %-28s %d drawers opened", "toggles fired,", opened))
	end,
})
