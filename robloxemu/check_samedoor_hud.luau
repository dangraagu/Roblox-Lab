-- The Same Door — the HUD fit gate (emu/hudcheck) with the panel-overlap rule ON, in every mode.
-- Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--       luau check_samedoor_hud.luau 2>&1
--
-- The stock gate measures the HUD as it stands after loading, which for this game is the HUB: the
-- run timer, the pause button, the antechamber card, the finish card with its Run again / Hub
-- buttons, the pause sheet and the void card are all invisible there, and a gate that never sees a
-- control scores it as a pass (Vault Runners' collapse timer sat on its wallet on every portrait phone
-- behind exactly that). So the ten stock viewports are measured SIX times, once per HUD mode, each
-- entry's `before` hook putting the HUD into that mode through the real Run remote the server uses.
-- overlap = true: no two visible panels may sit on top of each other in any mode.

local HudCheck = require("./emu/hudcheck")
local Harness = require("./emu/harness")

-- src/server/*.luau (not .server) are ModuleScripts in ServerScriptService under Rojo; register them
-- just before the server runs, as check_lostfounddepot_hud.luau does.
local realTryRun = Harness.tryRun
Harness.tryRun = function(self, key)
	if key == "server/Main.server" then
		local sss = self.services.ServerScriptService
		for k, entry in self.bundle do
			local name = string.match(k, "^server/(.+)$")
			if name and not string.match(name, "%.server$") and self.modules[k] == nil then
				local holder = self.instance.Instance.new("ModuleScript")
				holder.Name = name
				holder.Parent = sss
				self.modules[k] = { holder = holder, key = k, entry = entry, state = "cold", value = nil }
			end
		end
	end
	return realTryRun(self, key)
end

local function runRemote(h)
	return h.services.ReplicatedStorage:FindFirstChild("SameDoorRemotes"):FindFirstChild("Run")
end
local function hudRoot(player)
	return player:FindFirstChild("PlayerGui"):FindFirstChild("SameDoorHud"):FindFirstChild("Root")
end

local READY = {
	run = "hud-1", state = "ready", seals = 0, door = 2, origin = { x = 0, y = 0, z = 1000 },
	perfectMs = 27340, silverMs = 46751, goldMs = 36362, sealerMs = 32261, studio = false, unranked = true,
	reason = "Your profile is still open in another server: saving starts when that lock runs out (under a minute). Runs meanwhile are kept.", hazards = 3,
}
local MODES = {
	{ name = "hub", set = function(h, player)
		runRemote(h):FireClient(player, { state = "hub" })
	end },
	{ name = "antechamber card", set = function(h, player)
		runRemote(h):FireClient(player, READY)
	end },
	{ name = "running", set = function(h, player)
		runRemote(h):FireClient(player, READY)
		runRemote(h):FireClient(player, { run = "hud-1", state = "running", seals = 2 })
		-- the antechamber card hides after ArrivalHintSeconds of running
		h:advance(7)
	end },
	{ name = "pause sheet", set = function(h, player)
		runRemote(h):FireClient(player, READY)
		runRemote(h):FireClient(player, { run = "hud-1", state = "running", seals = 1 })
		hudRoot(player).PauseBox.PauseButton.Activated:Fire()
	end },
	{ name = "finish card", set = function(h, player)
		runRemote(h):FireClient(player, READY)
		runRemote(h):FireClient(player, { run = "hud-1", state = "running", seals = 3 })
		runRemote(h):FireClient(player, {
			run = "hud-1", state = "finished", seals = 3, timeMs = 29870, medal = "Sealer", door = 2, bestMs = 29870,
			improved = true, streak = 12, rank = 3, rankLabel = "Sealer", rankUp = true, brag = true, unranked = true,
			reason = "Your profile is still open in another server: saving starts when that lock runs out (under a minute). Runs meanwhile are kept.", newDoor = 3, perfectMs = 27340,
		})
	end },
	{ name = "void card", set = function(h, player)
		runRemote(h):FireClient(player, READY)
		runRemote(h):FireClient(player, { run = "hud-1", state = "running", seals = 1 })
		runRemote(h):FireClient(player, { run = "hud-1", state = "void",
			reason = "Run not ranked: position jumped 20.0 studs in 0.02 s (connection hiccup?). Nothing was posted." })
	end },
}

local viewports = {}
for _, mode in MODES do
	for _, v in HudCheck.VIEWPORTS do
		table.insert(viewports, {
			name = v.name .. " / " .. mode.name, w = v.w, h = v.h, touch = v.touch,
			before = function(h, player)
				mode.set(h, player)
				-- a toast in every mode, so its slot is measured against the card too
				h.services.ReplicatedStorage.SameDoorRemotes.Toast:FireClient(player, "The Door needs 3 Seals (1/3)")
			end,
		})
	end
end

HudCheck.run({
	overlap = true,
	game = "same-door",
	bundle = require("./build/same-door"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Dungeon.client", "client/Board.client" },
	viewports = viewports,
})
