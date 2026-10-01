-- SIGNAL LOST — headless HUD fit check. Run: luau check_signallost_hud.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--
-- The HUD lays out differently in three modes, and a sweep that measures only the idle one scores every other
-- control as a pass because it is invisible (hudcheck.luau's `before` note). So the ten standard viewports are
-- measured THREE times, each mode reached by PLAYING through the real server with tests/Bot.luau:
--   1. [lifeboat]  a fresh player in the hub: status, REST, the hint
--   2. [vacuum]    sector 1, standing in a vacuum module: status, AIR, the SIGNAL meter, REST, a hazard banner
--   3. [shop]      at the lifeboat's fabricator with the panel open and a refused purchase's toast up
-- overlap = true (hudcheck rule 4b: no two visible panels on top of each other). And, this game's own rule: in the
-- shop mode no visible text row (toast, hint, banner) lies on the shop panel, every text row is fully on screen,
-- and on a touch screen a text row that reaches the touch band keeps to the middle, between the thumbstick and the
-- jump button. The SIGNAL meter must end above the jump button's band on every viewport.

local HudCheck = require("./emu/hudcheck")
local Bot = require("../signal-lost/tests/Bot")

local THUMB_FRACTION, JUMP_FRACTION, MAX_PAD = 0.35, 0.25, 150
local TEXT_ROWS = { Toast = true, Hint = true, Banner = true }
local textAudits, textFailures, textRowsSeen, signalChecks = 0, {}, {}, 0

local bot
local EnvBus

local function rootOf(player) return player.PlayerGui.SignalHud.Root end

local function auditShop(h, player, v)
	h:advance(0.05)
	local rows, modal = {}, nil
	for _, gui in player.PlayerGui:GetChildren() do
		for _, r in h:guiRects(gui, v.w, v.h) do
			if r.depth == 2 and r.shown then
				if r.name == "Shop" then modal = r end
				if TEXT_ROWS[r.name] then
					local inst = rootOf(player):FindFirstChild(r.name)
					if inst and tostring(inst.Text) ~= "" then table.insert(rows, r) end
				end
			end
		end
	end
	textAudits += 1
	local where = v.name
	if not modal then table.insert(textFailures, where .. ": the shop is not on screen to audit against") return end
	local pad = if v.touch then math.min(MAX_PAD, math.floor(v.h * 0.35)) else 0
	for _, r in rows do
		textRowsSeen[r.name] = (textRowsSeen[r.name] or 0) + 1
		local ox = math.min(r.sx + r.sw, modal.sx + modal.sw) - math.max(r.sx, modal.sx)
		local oy = math.min(r.sy + r.sh, modal.sy + modal.sh) - math.max(r.sy, modal.sy)
		if ox > 1 and oy > 1 then
			table.insert(textFailures, string.format("%s: %s lies on the shop by %.0fx%.0f px", where, r.name, ox, oy))
		end
		if r.sx < -1 or r.sy < -1 or r.sx + r.sw > v.w + 1 or r.sy + r.sh > v.h + 1 then
			table.insert(textFailures, string.format("%s: %s is not fully on screen", where, r.name))
		end
		if pad > 0 and r.sy + r.sh > v.h - pad + 1 and (r.sx < v.w * THUMB_FRACTION - 1 or r.sx + r.sw > v.w * (1 - JUMP_FRACTION) + 1) then
			table.insert(textFailures, string.format("%s: %s reaches the touch band outside the middle", where, r.name))
		end
	end
end

-- The SIGNAL meter is display only, but it must never sit under the jump button (DESIGN.md §15).
local function auditSignal(h, player, v)
	for _, r in h:guiRects(player.PlayerGui.SignalHud, v.w, v.h) do
		if r.name == "Signal" and r.shown then
			signalChecks += 1
			local pad = if v.touch then math.min(MAX_PAD, math.floor(v.h * 0.35)) else 0
			if r.sy + r.sh > v.h - pad + 1 then
				table.insert(textFailures, string.format("%s: the SIGNAL meter reaches the jump band (bottom %.0f, band from %d)", v.name, r.sy + r.sh, v.h - pad))
			end
		end
	end
end

local SEEN = { [0x2014] = true, [0x2026] = true, [0x2605] = true }
local function glyphSweep(player, mode)
	local unseen, n = {}, 0
	for _, d in player.PlayerGui:GetDescendants() do
		if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then
			n += 1
			for _, cp in utf8.codes(tostring(d.Text)) do
				if cp >= 0x2000 and not SEEN[cp] then table.insert(unseen, string.format("U+%X in %s", cp, d:GetFullName())) end
			end
		end
	end
	if #unseen > 0 then error("[" .. mode .. "] unphotographed glyphs: " .. table.concat(unseen, "; "), 0) end
	print(string.format("   glyphs %-28s %d strings, all photographed", mode, n))
end

local function visible(player, name)
	local f = rootOf(player):FindFirstChild(name)
	return f ~= nil and f.Visible == true
end

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(viewports, { name = v.name .. " [lifeboat]", w = v.w, h = v.h, touch = v.touch })
end
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [vacuum]", w = v.w, h = v.h, touch = v.touch }
	e.before = function(h, player)
		if i == 1 then
			assert(bot:board(), "the HUD tester could not board the LIFT")
			assert(bot:waitPhase("sector", 6), "the HUD tester never reached sector 1")
			local mods = bot:modules()
			local here = bot:moduleAt(mods, bot:pos())
			local nb = nil
			for id, r in mods do
				if id == here then
					for n, lamp in r.lamps do if lamp == "VACUUM" then nb = n end end
				end
			end
			assert(nb, "sector 1's dock has no vacuum neighbour")
			assert(bot:cross(mods, here, nb, "sector"), "could not step into vacuum")
			bot:waitSeconds(0.3)
			assert(bot:state().moduleType == "vacuum", "not in vacuum")
			assert(visible(player, "Air") and visible(player, "Signal") and visible(player, "RestButton"), "AIR, SIGNAL and REST are not all visible in a sector")
			EnvBus = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBus"))
			glyphSweep(player, "vacuum")
		end
		-- the longest banner the HUD shows: a hazard's warning
		EnvBus.fire("hazard", { phase = "warn", name = "PANEL SHARD", seconds = 3 })
		h:advance(0.05)
		auditSignal(h, player, v)
	end
	table.insert(viewports, e)
end
for i, v in HudCheck.VIEWPORTS do
	local e = { name = v.name .. " [shop]", w = v.w, h = v.h, touch = v.touch }
	e.before = function(h, player)
		if i == 1 then
			-- back to the lifeboat through the dock's RETURN console
			local mods = bot:modules()
			local dockId
			for id, r in mods do if r.folder:FindFirstChild("ReturnConsole") then dockId = id end end
			local here = bot:moduleAt(mods, bot:pos())
			assert(bot:cross(mods, here, dockId, "sector"), "could not walk back to the dock")
			local console = mods[dockId].folder.ReturnConsole
			bot:walkTo(Vector3.new(console.Position.X * 0.6 + mods[dockId].center.X * 0.4, 0, console.Position.Z * 0.6 + mods[dockId].center.Z * 0.4), "sector")
			console:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
			assert(bot:waitPhase("hub", 6), "RETURN did not bring the tester home")
			local fab = h.workspace.Lifeboat.Fabricator
			bot:walkTo(Vector3.new(fab.Position.X, 0, fab.Position.Z + 3), "hub")
			bot:waitSeconds(0.4)
			assert(visible(player, "ShopButton"), "SHOP does not show at the fabricator")
			rootOf(player).ShopButton.Activated:Fire()
			bot:waitSeconds(0.3)
			assert(visible(player, "Shop"), "the SHOP button did not open the panel")
			local rows = 0
			for _, c in rootOf(player).Shop.List:GetChildren() do if string.match(c.Name, "^Row_") then rows += 1 end end
			assert(rows == 2, "the shop has " .. rows .. " rows, want 2")
			glyphSweep(player, "shop")
		end
		-- a purchase the server refuses (an empty wallet): its toast must be readable, not under the panel
		bot:fire("BuyUpgrade", "tank")
		bot:waitSeconds(0.6)
		assert(visible(player, "Shop"), "the shop closed during the text audit")
		auditShop(h, player, v)
	end
	table.insert(viewports, e)
end

HudCheck.run({
	game = "signal-lost",
	bundle = require("./build/signal-lost"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
	overlap = true,
	viewports = viewports,
	warmup = function(h, player)
		h.Players:simulateSpawn(player, h.workspace)
		h:advance(0.5)
		bot = Bot.new(h, player)
		bot:waitSeconds(0.6)
		assert(visible(player, "Status") and visible(player, "RestButton"), "the lifeboat HUD is not up")
		print(string.format("   warmup %-28s phase %s", "joined the lifeboat,", bot:phase()))
		glyphSweep(player, "lifeboat")
	end,
})

local seen = {}
for name, n in textRowsSeen do table.insert(seen, name .. " " .. n) end
table.sort(seen)
print(string.format("   text rows audited against the shop: %s (%d viewports); SIGNAL meter checked on %d", table.concat(seen, ", "), textAudits, signalChecks))
if textAudits ~= #HudCheck.VIEWPORTS or (textRowsSeen.Toast or 0) ~= textAudits or signalChecks ~= #HudCheck.VIEWPORTS then
	table.insert(textFailures, "control: every viewport audited with a toast up and the meter measured")
end
if #textFailures > 0 then
	print("FAIL — " .. #textFailures .. " problem(s):")
	for _, f in textFailures do print("   " .. f) end
	error("signal-lost: HUD text rows or the SIGNAL meter misplaced", 0)
end
print("PASS — signal-lost fits every viewport checked, no toast lies on the shop, and the SIGNAL meter stays above the jump band.")
