-- anomaly-observatory — headless HUD fit check. Run: luau check_anomaly.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
require("./emu/hudcheck").run({
	game = "anomaly-observatory",
	bundle = require("./build/anomaly-observatory"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
	-- The tint swatches are created by the client's State handler and by nothing else, so with
	-- no State push the swatch row stays empty, layoutTints returns at zero swatches, and the
	-- gate measures none of them. They are the smallest interactive control in this game and the
	-- reason the 44 px floor exists, so leaving them unbuilt made the run's PASS a weaker claim
	-- than it read as.
	--
	-- The payload is not written here. The server already pushed one at join, before the client
	-- script existed to hear it, and the remote shim recorded it — so the fixture is the real
	-- server's own state for a fresh player rather than a hand-made table that can drift out of
	-- step with pushState. Replaying it now populates the tint list, the owned set and the
	-- selected tint exactly as a live client would receive them.
	warmup = function(h, player)
		local remotes = h.ReplicatedStorage:FindFirstChild("AnomalyRemotes")
		assert(remotes ~= nil, "the server created no AnomalyRemotes folder")
		local state = remotes:FindFirstChild("State")
		assert(state ~= nil, "AnomalyRemotes has no State remote")
		local sent = state:getSent()
		assert(#sent > 0, "the server never pushed State at join; there is no payload to replay")
		local payload = sent[#sent].args[1]
		assert(type(payload) == "table" and payload.tints ~= nil, "the recorded State payload carries no tints")
		state:FireClient(player, payload)
		-- Say how many swatches now exist. The point of the whole hook is that a control which
		-- was never built reads exactly like a control that passed, so the count is printed
		-- rather than assumed.
		print(string.format("   warmup %-28s %d tint swatches built", "State replayed,", #payload.tints))
	end,
})
