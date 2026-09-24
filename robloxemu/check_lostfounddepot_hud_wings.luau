-- Lost & Found Depot — headless HUD fit check with BOTH client ScreenGuis: the HUD and the wings.
-- Run: luau check_lostfounddepot_hud_wings.luau 2>&1
-- Regenerate the bundle first:
--   py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--
-- check_lostfounddepot_hud.luau measures the HUD alone. src/client/Wings.client.luau adds its own ScreenGui:
-- the wing panel (wing name, next wing, the BREAK button) bottom-left above the hotbar, the hazard warning
-- above the hotbar, and a title card. hudcheck measures every ScreenGui in PlayerGui together, so this runs
-- the same six HUD modes as _hud (idle mid-shift with a full hotbar, MANUAL, UPGRADES, CODES, the summary
-- card, the Back Room note) plus a seventh with a hazard warning up, on every viewport, with the overlap
-- rule on: nothing off screen, every button >= 44 px on touch and clear of the thumbstick and jump button,
-- panels under half a phone screen, and no two panels on top of each other.
--
-- The wings draw from RenderStepped, which hudcheck never fires, so every mode here ends by running a
-- second of client frames (`settle`). The wing panel must be SHOWN in the idle and warning modes (a check
-- that measures a hidden panel proves nothing); on a phone it steps aside while a drawer or card is up.
-- The warmup is _hud's, verbatim; the tester is on 4 career shifts, so the AIRPORT wing (hazards on).
--
-- REVIEW-2 findings 2 and 5, measured here too:
--   * three more modes: a hazard in flight, THEN a drawer opened (MANUAL, UPGRADES, CODES). The warning must
--     stay SHOWN on every viewport (on a phone it used to be hidden for the whole flight) and, with the
--     overlap rule, clear of the drawer and every HUD row. And on a phone a due hazard waits while a drawer is
--     open (its marker would be behind the drawer): no launch in 10 s with hazards due every 1-2 s, and one
--     soon after it closes;
--   * the wing's TITLE CARD (a TextLabel, so the overlap rule cannot see it) against the HUD's rows, the
--     hotbar and the wing panel, on all ten viewports: it sat on the hotbar on 800x360, 844x390 and 640x300.

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")

local TESTER = 5551212

local hzConfig = nil
local realTryRun = Harness.tryRun
Harness.tryRun = function(self, key)
	if key == "server/Main.server" then
		local realRandom = Random
		Random = {
			new = function(seed)
				return realRandom.new(seed or 5551212)
			end,
		}
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
		self.services.DataStoreService:GetDataStore("LostFoundDepot_v1"):SetAsync("u_" .. TESTER, {
			data = { v = 1, cash = 1234, cartLevel = 3, shoesLevel = 3, shifts = 4, perfects = 2, backlog = 312,
				bestPerfectSeconds = 97, endingSeen = false, redeemed = {} },
		})
	end
	if key == "client/Wings.client" then
		-- in memory, this run only: a hazard every 1-2 s of running clock, for the warning mode
		hzConfig = self:_require(self.ReplicatedStorage:FindFirstChild("Config")).Hazards
		hzConfig.IntervalMin = 1
		hzConfig.IntervalMax = 2
		self.game:GetService("RunService"):setIsServer(false)
	end
	return realTryRun(self, key)
end

local DRAWER = { manual = "ManualDrawer", upgrades = "UpgradesDrawer", codes = "CodesDrawer" }

local function hud(player)
	local g = player:FindFirstChild("PlayerGui"):FindFirstChild("DepotHud")
	assert(g ~= nil, "the client built no DepotHud")
	local root = g:FindFirstChild("Root")
	assert(root ~= nil, "the HUD has no scaling Root frame")
	return root
end
local function wings(player)
	local g = player:FindFirstChild("PlayerGui"):FindFirstChild("DepotWings")
	assert(g ~= nil, "the wings built no ScreenGui")
	return g:FindFirstChild("Root")
end

local function settle(h, player, seconds)
	local RunService = h.game:GetService("RunService")
	local cam = h.workspace.CurrentCamera
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for _ = 1, math.floor((seconds or 1) * 30 + 0.5) do
		if hrp then cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position) end
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end

local function closeAll(root)
	for key, name in DRAWER do
		if root:FindFirstChild(name).Visible then
			root:FindFirstChild("Toggles"):FindFirstChild("Toggle_" .. key).Activated:Fire()
		end
	end
	local card = root:FindFirstChild("SummaryCard")
	if card.Visible then
		card:FindFirstChild("OkButton").Activated:Fire()
	end
	local note = root:FindFirstChild("NoteCard")
	for _ = 1, 10 do
		if not note.Visible then break end
		note:FindFirstChild("CloseButton").Activated:Fire()
	end
	for _, name in { "ManualDrawer", "UpgradesDrawer", "CodesDrawer", "SummaryCard", "NoteCard" } do
		assert(not root:FindFirstChild(name).Visible, name .. " did not close")
	end
end

local summaryPayload, livePayload = nil, nil
local function toLive(h, player)
	h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("State"):FireClient(player, livePayload)
end

local function open(key)
	return function(h, player)
		local root = hud(player)
		closeAll(root)
		toLive(h, player)
		root:FindFirstChild("Toggles"):FindFirstChild("Toggle_" .. key).Activated:Fire()
		assert(root:FindFirstChild(DRAWER[key]).Visible, key .. " drawer did not open")
		settle(h, player, 0.2)
	end
end

-- hudcheck's overlap rule compares PANELS (Frames) only. The HUD's memo, hint and toast rows are TextLabels
-- 90% of the screen wide, and the toast is how a misfile explains itself; the wings must not sit on them.
-- Measured on screen, with the rows' full label boxes (conservative: the text is centred and shorter).
local clashes = {}
local function rectsByName(h, gui, vw, vh)
	local out = {}
	for _, r in h:guiRects(gui, vw, vh) do
		if r.shown then out[r.name] = r end
	end
	return out
end
local function checkRows(h, player, where)
	local cam = h.workspace.CurrentCamera
	local vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	local pg = player:FindFirstChild("PlayerGui")
	local hudR = rectsByName(h, pg:FindFirstChild("DepotHud"), vw, vh)
	local wingR = rectsByName(h, pg:FindFirstChild("DepotWings"), vw, vh)
	for _, wn in { "WingPanel", "WarningPanel" } do
		local a = wingR[wn]
		if a then
			for _, hn in { "Memo", "Hint", "Toast", "Stamp", "CashPanel", "ClockPanel", "Toggles", "Hotbar" } do
				local b = hudR[hn]
				if b then
					local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
					local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
					if ox > 1 and oy > 1 then
						table.insert(clashes, string.format("[%s %dx%d] %s covers the HUD's %s by %.0fx%.0f px", where, vw, vh, wn, hn, ox, oy))
					end
				end
			end
		end
	end
end

local shown = { idle = 0, warning = 0 }
local function idle(h, player)
	local root = hud(player)
	closeAll(root)
	toLive(h, player)
	settle(h, player, 0.3)
	assert(root:FindFirstChild("Hotbar").Visible, "the hotbar is not showing mid-shift")
	local panel = wings(player):FindFirstChild("WingPanel")
	assert(panel.Visible, "the wing panel is not showing mid-shift with nothing open")
	-- the HUD's rows carry text in play: fill them the way a shift does, then measure
	root:FindFirstChild("Memo").Text = "MEMO: every T goes to REPAIR today"
	root:FindFirstChild("Hint").Text = "Read the TAG: walk it to the bin the tag names."
	root:FindFirstChild("Toast").Text = "-8 s. Keyring: K goes to KEYS & WALLETS."
	checkRows(h, player, "idle")
	shown.idle += 1
end

local function summary(h, player)
	local root = hud(player)
	closeAll(root)
	local state = h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("State")
	state:FireClient(player, livePayload)
	state:FireClient(player, summaryPayload)
	assert(root:FindFirstChild("SummaryCard").Visible, "the summary card did not show")
	settle(h, player, 0.2)
end

local function note(h, player)
	local root = hud(player)
	closeAll(root)
	toLive(h, player)
	local Secret = h:_require(h.services.ServerScriptService:FindFirstChild("Secret"))
	h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("Scene"):FireClient(player, {
		lines = Secret.Note, camFrom = { 100, 7, -24 }, camTo = { 100, 5, -47 },
	})
	assert(root:FindFirstChild("NoteCard").Visible, "the note card did not show")
	settle(h, player, 0.2)
end

local function warning(h, player)
	local root = hud(player)
	closeAll(root)
	toLive(h, player)
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
	local w = wings(player)
	local warn = w:FindFirstChild("WarningPanel")
	for _ = 1, 30 * 12 do
		if warn.Visible then break end
		settle(h, player, 1 / 30)
	end
	assert(warn.Visible, "no hazard warning came up in 12 s of running clock (interval 1-2 s)")
	assert(w:FindFirstChild("WingPanel").Visible, "the wing panel is not showing with the warning up")
	checkRows(h, player, "warning")
	shown.warning += 1
end

-- A hazard is already flying, then a drawer is opened. On a phone the drawer owns the middle of the screen: the
-- warning must stay up (below the drawer, or beside it). And no NEW hazard launches while a phone's drawer is
-- open. `holds` / `aside` count what was seen, per viewport.
local holds = { phoneDrawer = 0, phoneLaunched = 0, phoneAfter = 0, desktop = 0 }
local aside = { shown = 0, measured = 0 }
local function hazardFlying(h)
	local folder = h.workspace:FindFirstChild("DepotWings")
	if folder == nil then return false end
	for _, c in folder:GetChildren() do
		if string.sub(c.Name, 1, 7) == "Hazard_" then return true end
	end
	return false
end
local function drawerWithHazard(key)
	return function(h, player)
		local root = hud(player)
		closeAll(root)
		toLive(h, player)
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		hum.FloorMaterial = Enum.Material.Plastic
		local w = wings(player)
		local warn = w:FindFirstChild("WarningPanel")
		local toggle = root:FindFirstChild("Toggles"):FindFirstChild("Toggle_" .. key)
		-- one frame, with a small step every 4 s: standing still 20 s would be idle rest, which (rightly) pauses hazards.
		-- The live payload is re-sent every frame (as _wings pins its payloads): the server's own shift, started in
		-- the warmup, runs out during this long run, and its SUMMARY push would stop the clock hazards run on.
		local frames = 0
		local function step()
			frames += 1
			toLive(h, player)
			hum.MoveDirection = if frames % 120 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
			settle(h, player, 1 / 30)
		end
		-- 1. with the sky clear, open the drawer: on a phone no hazard launches while it is open
		for _ = 1, 30 * 12 do
			if not hazardFlying(h) then break end
			step()
		end
		toggle.Activated:Fire()
		assert(root:FindFirstChild(DRAWER[key]).Visible, key .. " drawer did not open")
		local phone = not root:FindFirstChild("Hotbar").Visible -- the HUD hides the hotbar when a drawer crowds a phone
		local launched = 0
		local was = hazardFlying(h)
		for _ = 1, 30 * 10 do
			step()
			local now = hazardFlying(h)
			if now and not was then launched += 1 end
			was = now
		end
		if phone then
			holds.phoneDrawer += 1
			holds.phoneLaunched += launched
		elseif launched > 0 then
			holds.desktop += 1
		end
		toggle.Activated:Fire()
		-- 2. closed again: the held hazard comes (it stayed due). A NEW launch is waited for (any hazard still
		-- flying from before lands first), so the warning below is a fresh one: 2 s from any knock, 3 from arrival.
		for _ = 1, 30 * 12 do
			if not hazardFlying(h) then break end
			step()
		end
		local came = false
		for _ = 1, 30 * 6 do
			step()
			if hazardFlying(h) and warn.Visible then came = true; break end
		end
		assert(came, "no hazard came within 6 s of closing the " .. key .. " drawer (interval 1-2 s)")
		if phone then holds.phoneAfter += 1 end
		-- 3. a hazard is flying and its warning is up: NOW the drawer opens
		toggle.Activated:Fire()
		assert(root:FindFirstChild(DRAWER[key]).Visible, key .. " drawer did not open")
		settle(h, player, 0.1)
		aside.measured += 1
		if hazardFlying(h) then
			assert(warn.Visible, "a hazard is flying and the " .. key .. " drawer is open: the warning is hidden")
			aside.shown += 1
			-- on a touch screen it is not under the player's thumbs: clear of the thumbstick and the jump button
			local cam = h.workspace.CurrentCamera
			local vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
			if h.game:GetService("UserInputService").TouchEnabled then
				local pad = math.min(150, math.floor(vh * 0.35))
				local r = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotWings"), vw, vh).WarningPanel
				assert(r ~= nil, "the warning has no rect")
				local function hits(x0, y0, x1, y1)
					return r.sx < x1 and x0 < r.sx + r.sw and r.sy < y1 and y0 < r.sy + r.sh
				end
				assert(not hits(0, vh - pad, vw * 0.35, vh) and not hits(vw * 0.75, vh - pad, vw, vh),
					string.format("%dx%d, %s open: the hazard warning sits under a touch control (x %.0f..%.0f, y %.0f..%.0f)",
						vw, vh, key, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh))
				aside.clearOfThumbs = (aside.clearOfThumbs or 0) + 1
			end
		end
		checkRows(h, player, key .. " + hazard")
	end
end

local modes = {
	{ tag = "", before = idle },
	{ tag = ", manual", before = open("manual") },
	{ tag = ", upgrades", before = open("upgrades") },
	{ tag = ", codes", before = open("codes") },
	{ tag = ", summary", before = summary },
	{ tag = ", note", before = note },
	{ tag = ", hazard warning", before = warning },
	{ tag = ", hazard then manual", before = drawerWithHazard("manual") },
	{ tag = ", hazard then upgrades", before = drawerWithHazard("upgrades") },
	{ tag = ", hazard then codes", before = drawerWithHazard("codes") },
}
local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	for _, m in modes do
		table.insert(viewports, { name = v.name .. m.tag, w = v.w, h = v.h, touch = v.touch, before = m.before })
	end
end

local okRun, errRun = pcall(HudCheck.run, {
	game = "lost-found-depot",
	bundle = require("./build/lost-found-depot"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Wings.client" },
	overlap = true,
	viewports = viewports,
	warmup = function(h, player)
		local state = h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("State")
		local function last()
			local sent = state:sentTo(player)
			return sent[#sent].args[1]
		end
		h.Players:simulateSpawn(player, h.workspace)
		h:advance(0.5)
		assert(last().carry == 5, "the preloaded tester does not carry 5")
		local bay = player.RespawnLocation.Parent
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		hrp.CFrame = CFrame.new(bay:FindFirstChild("BayPad").Position.X, 3, 0)
		bay:FindFirstChild("Slot_1"):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(player)
		h:advance(331)
		summaryPayload = last()
		assert(summaryPayload.shift.state == "SUMMARY", "no SUMMARY payload was produced")
		h:advance(5)
		assert(last().shift.state == "ARMED", "the bay did not re-arm")
		for s = 1, 5 do
			bay:FindFirstChild("Slot_" .. s):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(player)
		end
		h:advance(0.5)
		livePayload = last()
		assert(#livePayload.shift.carried == 5, "the warmup could not carry five items")
		settle(h, player, 1)
		local panel = wings(player):FindFirstChild("WingPanel")
		assert(panel.Visible, "the wing panel did not show after the warmup")
		assert(panel:FindFirstChild("WingName").Text == "AIRPORT LOST & FOUND",
			"the tester (5 shifts done) is in the AIRPORT wing, got " .. panel:FindFirstChild("WingName").Text)
		print(string.format("   warmup %-28s wing panel up (%s), hazards every 1-2 s", "server driven,", panel:FindFirstChild("WingName").Text))

		-- THE TITLE CARD on every viewport. The server's own payload with only `shifts` raised to the SPACE
		-- STATION's (the fields EYECANDY.md says drive the wings) makes the client announce it: "YOU MADE IT TO
		-- SPACE!", the longest card. It stays up 4.5 s; the ten viewports are measured in that time, each after
		-- two frames of layout. The card and its sub line must not touch the HUD's rows, the hotbar or the wing
		-- panel, and must be SHOWN (a hidden card proves nothing).
		local armed = table.clone(last())
		armed.shifts = 13
		state:FireClient(player, armed)
		local card = wings(player):FindFirstChild("WingCard")
		local sub = wings(player):FindFirstChild("WingCardSub")
		for _ = 1, 30 do
			if card.Visible and card.Text == "YOU MADE IT TO SPACE!" then break end
			settle(h, player, 1 / 30)
		end
		assert(card.Visible and card.Text == "YOU MADE IT TO SPACE!", "the space card did not come up (" .. tostring(card.Text) .. ")")
		local cardClashes, cardShown, subShown = {}, 0, 0
		for _, v in HudCheck.VIEWPORTS do
			h:setTouch(v.touch)
			h:setViewport(v.w, v.h)
			settle(h, player, 2 / 30)
			local hudR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotHud"), v.w, v.h)
			local wingR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotWings"), v.w, v.h)
			if wingR.WingCard then cardShown += 1 end
			if wingR.WingCardSub then subShown += 1 end
			for _, cn in { "WingCard", "WingCardSub" } do
				local a = wingR[cn]
				if a then
					local others = {}
					for _, hn in { "Memo", "Hint", "Toast", "Stamp", "CashPanel", "ClockPanel", "Toggles", "Hotbar" } do
						if hudR[hn] then others[hn] = hudR[hn] end
					end
					if wingR.WingPanel then others.WingPanel = wingR.WingPanel end
					for on, b in others do
						local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
						local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
						if ox > 1 and oy > 1 then
							table.insert(cardClashes, string.format("[%s %dx%d] %s covers %s by %.0fx%.0f px", v.name, v.w, v.h, cn, on, ox, oy))
						end
					end
					if a.sx < -1 or a.sy < -1 or a.sx + a.sw > v.w + 1 or a.sy + a.sh > v.h + 1 then
						table.insert(cardClashes, string.format("[%s %dx%d] %s is off screen", v.name, v.w, v.h, cn))
					end
				end
			end
		end
		for _, c in cardClashes do print("   " .. c) end
		print(string.format("   the title card was up on %d of %d viewports (its sub line on %d), %d clash(es)",
			cardShown, #HudCheck.VIEWPORTS, subShown, #cardClashes))
		assert(cardShown == #HudCheck.VIEWPORTS, "the title card must be SHOWN on every viewport to be measured")
		assert(#cardClashes == 0, "FAIL - the title card covers the HUD")
		-- its sub line too, wherever there is room for it (all but the two 800x360 touch runs, whose free band
		-- takes the title alone): a card shown on one viewport re-decides its lines on the next
		assert(subShown >= #HudCheck.VIEWPORTS - 2, "the card's sub line shows wherever it fits (" .. subShown .. ")")
		-- and while a card is up no hazard launches (it would put its warning beside the card on a short phone):
		-- this is a RUNNING payload in the SPACE STATION with hazards due every 1-2 s
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		hum.FloorMaterial = Enum.Material.Plastic
		local ticks = 0
		local function tick() -- one frame; a small step every 4 s (standing still 20 s is idle rest, which pauses hazards)
			ticks += 1
			hum.MoveDirection = if ticks % 120 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
			settle(h, player, 1 / 30)
		end
		local launchedUnderCard, wasFlying, cardFrames = 0, hazardFlying(h), 0
		while card.Visible and cardFrames < 30 * 8 do
			tick()
			cardFrames += 1
			local f = hazardFlying(h)
			if f and not wasFlying and card.Visible then launchedUnderCard += 1 end
			wasFlying = f
		end
		assert(not card.Visible, "CONTROL: the card went away within 8 s")
		local cameAfter = false
		for _ = 1, 30 * 12 do
			if hazardFlying(h) and not wasFlying then cameAfter = true; break end
			wasFlying = hazardFlying(h)
			tick()
		end
		print(string.format("   while the card was up (%.1f s more, hazards due every 1-2 s): %d launches; one came after it: %s",
			cardFrames / 30, launchedUnderCard, tostring(cameAfter)))
		assert(launchedUnderCard == 0, "no hazard launches while the title card is up")
		assert(cameAfter, "CONTROL: the held hazard came once the card had gone")
		-- back to the tester's own career, the card gone, before hudcheck measures
		h:setTouch(HudCheck.VIEWPORTS[1].touch)
		h:setViewport(HudCheck.VIEWPORTS[1].w, HudCheck.VIEWPORTS[1].h)
		state:FireClient(player, livePayload)
		settle(h, player, 1)
	end,
})
for _, c in clashes do print("   " .. c) end
if not okRun then error(errRun, 0) end
print(string.format("   the wing panel was measured shown in %d idle and %d warning viewports", shown.idle, shown.warning))
assert(shown.idle == #HudCheck.VIEWPORTS and shown.warning == #HudCheck.VIEWPORTS, "every viewport measured the wing panel shown")
print(string.format("   a hazard in flight when a drawer opened: its warning stayed up in %d of %d viewport x drawer runs (clear of the touch controls in all %d touch runs)",
	aside.shown, aside.measured, aside.clearOfThumbs or 0))
assert((aside.clearOfThumbs or 0) >= 15, "CONTROL: the touch runs were measured against the thumbstick and jump button")
assert(aside.measured == 3 * #HudCheck.VIEWPORTS and aside.shown >= aside.measured - 3,
	"a hazard's warning stays on screen when a drawer opens during its flight (" .. aside.shown .. " of " .. aside.measured .. ")")
print(string.format("   a phone drawer open 10 s with hazards due every 1-2 s: %d launches over %d runs (and a hazard came within 6 s of closing it every time); %d non-phone runs launched with it open",
	holds.phoneLaunched, holds.phoneDrawer, holds.desktop))
assert(holds.phoneDrawer >= 9, "CONTROL: the phone drawer runs happened (" .. holds.phoneDrawer .. ")")
assert(holds.phoneLaunched == 0, "no hazard launches while a phone's drawer covers the screen (" .. holds.phoneLaunched .. ")")
assert(holds.desktop >= 3, "CONTROL: where a drawer does not cover the screen hazards launch with it open (" .. holds.desktop .. ")")
if #clashes > 0 then
	error(string.format("FAIL — the wings sit on the HUD's rows %d time(s)", #clashes), 0)
end
print(string.format("PASS — the wing panel and the hazard warning keep off the HUD's memo, hint, toast, stamp, cash, clock, toggles and hotbar on all %d viewports x 5 modes; the title card keeps off them and the hotbar on all %d",
	#HudCheck.VIEWPORTS, #HudCheck.VIEWPORTS))
