-- FACILITY: Endless Nightmare — headless HUD fit check. Run: luau check_facilitynightmare_hud.luau
-- Regenerate the bundle first:
--   py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--
-- The HUD has three modes that lay out differently, and a sweep that only measures the idle one
-- scores every other control as a pass because it is simply invisible (hudcheck.luau's `before`
-- note: Vault Runners' timer covered its wallet on every portrait phone behind a green gate). So
-- the ten standard viewports are measured THREE times, and each mode is reached by PLAYING, not by
-- a hand-made payload: tests/Bot.luau walks the real server into it.
--   1. down on sublevel 1       — status, battery, LIGHT and SPRINT on the right edge
--   2. the elevator powered      — the EXTRACT / DESCEND modal
--   3. back in the break room    — the perk panel, opened through the terminal's real prompt
-- Every string the HUD drew in each mode is swept against the glyphs Studio has rendered.

local HudCheck = require("./emu/hudcheck")
local Bot = require("../facility-nightmare/tests/Bot")

local SEEN = {
	[0x2014] = true, [0x2026] = true, [0x2605] = true, [0x2744] = true, [0xFE0F] = true,
	[0x1F30C] = true, [0x1F441] = true, [0x1F451] = true, [0x1F4A8] = true, [0x1F500] = true,
	[0x1F512] = true, [0x1F525] = true, [0x1F5FF] = true, [0x1F34C] = true, [0x1F0CF] = true, [0x1F6AA] = true,
}

local bot
local function glyphSweep(player, mode)
	local unseen, n = {}, 0
	for _, d in player:FindFirstChild("PlayerGui"):GetDescendants() do
		if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then
			n += 1
			for _, cp in utf8.codes(tostring(d.Text)) do
				if cp >= 0x2000 and not SEEN[cp] then table.insert(unseen, string.format("U+%X in %s", cp, d:GetFullName())) end
			end
		end
	end
	if #unseen > 0 then
		error("[" .. mode .. "] unphotographed glyphs: " .. table.concat(unseen, "; "), 0)
	end
	print(string.format("   glyphs %-28s %d strings, all photographed", mode, n))
end

local function visible(player, name)
	local root = player.PlayerGui.FacilityHud.Root
	local f = root:FindFirstChild(name)
	return f ~= nil and f.Visible == true
end

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(viewports, { name = v.name .. " [floor]", w = v.w, h = v.h, touch = v.touch })
end
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [choice]", w = v.w, h = v.h, touch = v.touch }
	if i == 1 then
		e.before = function(h, player)
			local r = bot:clearFloor()
			assert(r == "powered", "the bot did not power the elevator: " .. tostring(r))
			bot:waitSeconds(0.3)
			assert(visible(player, "Choice"), "the elevator powered but the Choice modal is not visible")
			assert(not visible(player, "LightButton"), "LIGHT still shows under the choice modal")
			glyphSweep(player, "choice")
		end
	end
	table.insert(viewports, e)
end
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [perks]", w = v.w, h = v.h, touch = v.touch }
	if i == 1 then
		e.before = function(h, player)
			bot:fire("Choose", "extract")
			assert(bot:waitPhase("hub", 6), "EXTRACT did not bring the player back to the hub")
			local prompt = h.workspace.Hub.PerkTerminal:FindFirstChildOfClass("ProximityPrompt")
			prompt.Triggered:Fire(player)
			bot:waitSeconds(0.3)
			assert(visible(player, "Perks"), "the terminal's prompt did not open the perk panel")
			local list = player.PlayerGui.FacilityHud.Root.Perks.List
			local rows = 0
			for _, c in list:GetChildren() do if string.match(c.Name, "^Row_") then rows += 1 end end
			assert(rows == 5, "the perk list has " .. rows .. " rows, want 5")
			glyphSweep(player, "perks")
		end
	end
	table.insert(viewports, e)
end

HudCheck.run({
	game = "facility-nightmare",
	bundle = require("./build/facility-nightmare"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
	overlap = true,
	viewports = viewports,
	warmup = function(h, player)
		h.Players:simulateSpawn(player, h.workspace)
		h:advance(0.5)
		bot = Bot.new(h, player)
		assert(bot:board(h.workspace.Hub), "the HUD tester could not board the hub car")
		assert(bot:waitPhase("floor", 6), "the HUD tester never reached sublevel 1")
		bot:waitSeconds(0.5)
		assert(visible(player, "LightButton") and visible(player, "SprintButton"), "LIGHT/SPRINT are not visible on the floor")
		assert(visible(player, "Power"), "the battery panel is not visible on the floor")
		print(string.format("   warmup %-28s phase %s, sublevel %d", "played to the floor,", bot:phase(), bot:state().run.k))
		glyphSweep(player, "floor")
	end,
})
