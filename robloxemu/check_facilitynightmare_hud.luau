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
--
-- 4. TEXT ON A MODAL (review 2, finding 1). hudcheck's overlap rule 4b counts Frames only, and the HUD's toast, hint
--    and banner are TextLabels. On a phone all three used to sit on the EXTRACT / DESCEND modal (the toast and the
--    hint on every powering, the hazard banner when one started in the powered lift's room), and the toast and the
--    hint on the perk panel on every screen. So in the choice and perk modes, on every viewport, this re-fires a
--    toast (a real refused request) and, at the choice, a hazard warning on the client-local bus exactly as
--    Env.client sends one, then asserts: no visible, non-empty text row lies on a visible modal; every text row is
--    fully on screen; and on a touch screen a row that reaches down into the band Roblox's thumbstick and jump
--    button own stays in the middle, between them (hudcheck's own fractions, 0.35 and 0.25 of the width).

local HudCheck = require("./emu/hudcheck")
local Bot = require("../facility-nightmare/tests/Bot")

-- Written out: hudcheck.luau's THUMBSTICK_FRACTION, JUMP_FRACTION and MAX_CONTROL_PAD.
local THUMB_FRACTION, JUMP_FRACTION, MAX_PAD = 0.35, 0.25, 150
local TEXT_ROWS = { Toast = true, Hint = true, Banner = true }
local MODALS = { Choice = true, Perks = true }
local textAudits, textFailures, textRowsSeen = 0, {}, {}
local function auditText(h, player, v, mode)
	h:advance(0.05)
	local rows, modals = {}, {}
	for _, gui in player.PlayerGui:GetChildren() do
		for _, r in h:guiRects(gui, v.w, v.h) do
			if r.depth == 2 and r.shown then
				if MODALS[r.name] then table.insert(modals, r) end
				if TEXT_ROWS[r.name] then
					local inst = player.PlayerGui.FacilityHud.Root:FindFirstChild(r.name)
					if inst and tostring(inst.Text) ~= "" then table.insert(rows, r) end
				end
			end
		end
	end
	textAudits += 1
	local where = v.name .. " [" .. mode .. "]"
	if #modals == 0 then table.insert(textFailures, where .. ": no modal on screen to audit against") end
	local pad = if v.touch then math.min(MAX_PAD, math.floor(v.h * 0.35)) else 0
	for _, r in rows do
		textRowsSeen[r.name] = (textRowsSeen[r.name] or 0) + 1
		for _, m in modals do
			local ox = math.min(r.sx + r.sw, m.sx + m.sw) - math.max(r.sx, m.sx)
			local oy = math.min(r.sy + r.sh, m.sy + m.sh) - math.max(r.sy, m.sy)
			if ox > 1 and oy > 1 then
				table.insert(textFailures, string.format("%s: %s (y %.0f..%.0f) lies on %s (y %.0f..%.0f) by %.0fx%.0f px", where,
					r.name, r.sy, r.sy + r.sh, m.name, m.sy, m.sy + m.sh, ox, oy))
			end
		end
		if r.sx < -1 or r.sy < -1 or r.sx + r.sw > v.w + 1 or r.sy + r.sh > v.h + 1 then
			table.insert(textFailures, string.format("%s: %s is not fully on screen (x %.0f..%.0f y %.0f..%.0f)", where, r.name,
				r.sx, r.sx + r.sw, r.sy, r.sy + r.sh))
		end
		if pad > 0 and r.sy + r.sh > v.h - pad + 1 and (r.sx < v.w * THUMB_FRACTION - 1 or r.sx + r.sw > v.w * (1 - JUMP_FRACTION) + 1) then
			table.insert(textFailures, string.format("%s: %s reaches into the touch band (y %.0f..%.0f, band from %d) outside the middle (x %.0f..%.0f)",
				where, r.name, r.sy, r.sy + r.sh, v.h - pad, r.sx, r.sx + r.sw))
		end
	end
end

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
local EnvBus -- the client-local bus Env.client talks to the HUD over (required in the choice mode's first hook)
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [choice]", w = v.w, h = v.h, touch = v.touch }
	e.before = function(h, player)
		if i == 1 then
			local r = bot:clearFloor()
			assert(r == "powered", "the bot did not power the elevator: " .. tostring(r))
			bot:waitSeconds(0.3)
			assert(visible(player, "Choice"), "the elevator powered but the Choice modal is not visible")
			assert(not visible(player, "LightButton"), "LIGHT still shows under the choice modal")
			glyphSweep(player, "choice")
			EnvBus = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBus"))
		end
		-- a refused request: the server answers with a toast (never a silent no-op), while the modal is up
		bot:fire("Choose", "neither")
		bot:waitSeconds(0.3)
		-- the warning Env.client sends when a hazard starts (the banner, 3 s)
		EnvBus.fire("hazard", { phase = "warn", name = "CHEMICAL LEAK", seconds = 3 })
		assert(visible(player, "Choice"), "the choice modal closed during the text audit")
		auditText(h, player, v, "choice")
	end
	table.insert(viewports, e)
end
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [perks]", w = v.w, h = v.h, touch = v.touch }
	e.before = function(h, player)
		if i == 1 then
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
		-- a purchase the server refuses (a perk that does not exist): its toast must be readable, not under the panel
		bot:fire("BuyPerk", "noSuchPerk")
		bot:waitSeconds(0.3)
		assert(visible(player, "Perks"), "the perk panel closed during the text audit")
		auditText(h, player, v, "perks")
	end
	table.insert(viewports, e)
end

-- 5. THE BREAK ROOM (pass 2): the perk panel closed, the hub row as a player sees it on arrival. PERKS was never measured
-- in any mode before (it hides on a floor and while its panel is open), and REST (press pause) sits beside it.
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [hub]", w = v.w, h = v.h, touch = v.touch }
	e.before = function(h, player)
		if i == 1 then
			local close = player.PlayerGui.FacilityHud.Root.Perks.CloseButton
			close.Activated:Fire()
			bot:waitSeconds(0.3)
			assert(not visible(player, "Perks"), "CLOSE did not shut the perk panel")
			assert(visible(player, "PerksButton"), "PERKS is not on screen in the break room")
			assert(visible(player, "RestButton"), "REST is not on screen in the break room")
			glyphSweep(player, "hub")
		end
	end
	table.insert(viewports, e)
end

HudCheck.run({
	game = "facility-nightmare",
	bundle = require("./build/facility-nightmare"),
	server = "server/Main.server",
	-- Env.client is not loaded, on purpose: it draws nothing in PlayerGui (its world art is local Parts and SurfaceGuis),
	-- and its only screen text (the hazard banner, the rest hint, a refused REST) goes over EnvBus into Hud.client, which
	-- section 4 fires exactly as Env.client does. Loaded, it would start real hazards at random moments of this sweep.
	clients = { "client/Hud.client" },
	overlap = true, -- rule 4b (docs/complete-game-standard.md §2); TextLabels on a modal are section 4's own audit
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

-- 4. text on a modal: HudCheck.run has printed its PASS; this rule is this game's own, so it has the last line
local seen = {}
for name, n in textRowsSeen do table.insert(seen, name .. " " .. n) end
table.sort(seen)
print(string.format("   text rows audited against the modals: %s (%d viewport-modes)", table.concat(seen, ", "), textAudits))
local controlsOk = textAudits == 2 * #HudCheck.VIEWPORTS and (textRowsSeen.Toast or 0) == textAudits
	and (textRowsSeen.Banner or 0) >= #HudCheck.VIEWPORTS
if not controlsOk then
	table.insert(textFailures, "control: every viewport-mode audited with a toast up, and the banner up at every choice (audits "
		.. textAudits .. ")")
end
if #textFailures > 0 then
	print("FAIL — " .. #textFailures .. " text-row problem(s):")
	for _, f in textFailures do print("   " .. f) end
	error("facility-nightmare: text rows lie on a modal", 0)
end
print("PASS — facility-nightmare fits every viewport checked, and no toast, hint or banner lies on a modal.")
