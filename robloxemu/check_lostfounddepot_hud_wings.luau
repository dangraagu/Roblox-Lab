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

-- REVIEW-3 finding 3: the wing panel, the warning and the title card sat on the HUD's rows on phone sizes the
-- ten hudcheck viewports do not have (568x320: the panel and the warning on the memo, hint and toast rows, the
-- card on them too; 667x375, the common iPhone SE 2/3 and 6-8: the space card on the BREAK panel). The wings'
-- own placements are therefore swept over these twelve more touch viewports as well (the reviewer's list),
-- after the ten standard ones. hudcheck's full run (the HUD's own rules, every mode) stays on the standard ten
-- here; check_lostfounddepot_hud runs it on 568x320 and 667x375 as well since pass 2 of the complete-game standard
-- (2026-10-01), when the HUD's OWN five-slot hotbar stopped sitting on its clock at 568x320 (EYECANDY.md §15). The
-- sweep below also measures the hotbar against the HUD's own text rows on all 22, which hudcheck cannot see.
local EXTRA_VIEWPORTS = {
	{ name = "iphone se1", w = 568, h = 320, touch = true },
	{ name = "iphone 8", w = 667, h = 375, touch = true },
	{ name = "iphone 8 plus", w = 736, h = 414, touch = true },
	{ name = "galaxy s8", w = 740, h = 360, touch = true },
	{ name = "android 780", w = 780, h = 360, touch = true },
	{ name = "iphone 13", w = 844, h = 390, touch = true },
	{ name = "iphone 11", w = 896, h = 414, touch = true },
	{ name = "android 915", w = 915, h = 412, touch = true },
	{ name = "iphone 15 pm", w = 932, h = 430, touch = true },
	{ name = "portrait 375", w = 375, h = 667, touch = true },
	{ name = "portrait 390", w = 390, h = 844, touch = true },
	{ name = "portrait 360", w = 360, h = 800, touch = true },
}
local ALL_VIEWPORTS = table.clone(HudCheck.VIEWPORTS)
for _, v in EXTRA_VIEWPORTS do table.insert(ALL_VIEWPORTS, v) end

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
local holds = { phoneDrawer = 0, phoneLaunched = 0, phoneAfter = 0, desktop = 0, capCame = 0, capWarned = 0, capMin = math.huge, capMax = 0 }
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
		-- REVIEW-3 finding 2: held for good, a drawer kept open was a total shield (0 hazards in 991 s of running
		-- clock). On a phone the held hazard now comes at most 15 s (a literal, the promise) after it fell due,
		-- with the drawer still open and its warning up beside the drawer. It fell due at most 2 s after the
		-- drawer opened (hazards every 1-2 s here), so it comes 15-17 s after opening, never sooner than 15.
		if phone then
			local cameAt = nil
			for f = 1, 30 * 10 do
				step()
				local now = hazardFlying(h)
				if now and not was then
					cameAt = 10 + f / 30
					break
				end
				was = now
			end
			if cameAt then
				holds.capCame += 1
				holds.capMin = math.min(holds.capMin, cameAt)
				holds.capMax = math.max(holds.capMax, cameAt)
				settle(h, player, 1 / 30)
				if warn.Visible then holds.capWarned += 1 end
			end
			-- let it pass before the drawer closes
			for _ = 1, 30 * 12 do
				if not hazardFlying(h) then break end
				step()
			end
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
		-- In memory, from here on: the live shift lasts 10 hours of harness time. The modes below re-send its
		-- RUNNING payload every frame, but the server's own shift used to run out somewhere in the long drawer
		-- runs and its summary card replaced an open drawer in the HUD (the drawer toggle then CLOSED it).
		h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Shift.Seconds = 36000
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
		local cardClashes, cardShown, subShown, extraShown = {}, 0, 0, 0
		for vi, v in ALL_VIEWPORTS do
			h:setTouch(v.touch)
			h:setViewport(v.w, v.h)
			settle(h, player, 2 / 30)
			local hudR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotHud"), v.w, v.h)
			local wingR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotWings"), v.w, v.h)
			local standard = vi <= #HudCheck.VIEWPORTS
			if wingR.WingCard then
				if standard then cardShown += 1 else extraShown += 1 end
			end
			if wingR.WingCardSub and standard then subShown += 1 end
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
		print(string.format("   the title card was up on %d of %d viewports (its sub line on %d) and on %d of %d more phone sizes, %d clash(es)",
			cardShown, #HudCheck.VIEWPORTS, subShown, extraShown, #EXTRA_VIEWPORTS, #cardClashes))
		assert(cardShown == #HudCheck.VIEWPORTS, "the title card must be SHOWN on every viewport to be measured")
		assert(extraShown == #EXTRA_VIEWPORTS, "and on every one of the twelve more phone sizes (" .. extraShown .. ")")
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

		-- REVIEW-3 finding 3: the wing panel and a hazard's warning, on all 22 viewports, against the HUD's rows
		-- and panels (and, on touch, the BREAK button clear of the thumbstick and jump button and >= 44 px).
		-- Each viewport is measured while a hazard is flying, so the warning is really up.
		local sweepClashes, panelShown, warnShown, hotbarShown = {}, 0, 0, 0
		local wr = wings(player)
		local warnP = wr:FindFirstChild("WarningPanel")
		for _, v in ALL_VIEWPORTS do
			h:setTouch(v.touch)
			h:setViewport(v.w, v.h)
			local came = false
			for _ = 1, 30 * 12 do
				tick()
				if warnP.Visible and hazardFlying(h) then came = true; break end
			end
			assert(came, string.format("%dx%d: no hazard warning within 12 s (hazards due every 1-2 s)", v.w, v.h))
			local hudRoot = hud(player)
			hudRoot:FindFirstChild("Memo").Text = "MEMO: every T goes to REPAIR today"
			hudRoot:FindFirstChild("Hint").Text = "Read the TAG: walk it to the bin the tag names."
			hudRoot:FindFirstChild("Toast").Text = "-8 s. Keyring: K goes to KEYS & WALLETS."
			local hudR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotHud"), v.w, v.h)
			local wingR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotWings"), v.w, v.h)
			if wingR.WingPanel then panelShown += 1 end
			if wingR.WarningPanel then warnShown += 1 end
			-- the HUD against ITSELF, text rows included (hudcheck's overlap rule sees Frames only): a full cart's
			-- hotbar keeps off the memo, hint, toast, stamp, cash, clock and toggles on all 22 (pass 2, 2026-10-01: on
			-- 568x320 the two-row hotbar sat on the clock, 120x38 px)
			local bar = hudR.Hotbar
			if bar then
				hotbarShown += 1
				for _, hn in { "Memo", "Hint", "Toast", "Stamp", "CashPanel", "ClockPanel", "Toggles" } do
					local o = hudR[hn]
					if o then
						local ox = math.min(bar.sx + bar.sw, o.sx + o.sw) - math.max(bar.sx, o.sx)
						local oy = math.min(bar.sy + bar.sh, o.sy + o.sh) - math.max(bar.sy, o.sy)
						if ox > 1 and oy > 1 then
							table.insert(sweepClashes, string.format("[%s %dx%d] the HUD's own Hotbar covers its %s by %.0fx%.0f px",
								v.name, v.w, v.h, hn, ox, oy))
						end
					end
				end
			end
			for _, wn in { "WingPanel", "WarningPanel" } do
				local a = wingR[wn]
				if a then
					local others = {}
					for _, hn in { "Memo", "Hint", "Toast", "Stamp", "CashPanel", "ClockPanel", "Toggles", "Hotbar" } do
						if hudR[hn] then others[hn] = hudR[hn] end
					end
					if wn == "WarningPanel" and wingR.WingPanel then others.WingPanel = wingR.WingPanel end
					for on, b in others do
						local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
						local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
						if ox > 1 and oy > 1 then
							table.insert(sweepClashes, string.format("[%s %dx%d] %s covers %s by %.0fx%.0f px", v.name, v.w, v.h, wn, on, ox, oy))
						end
					end
					if a.sx < -1 or a.sy < -1 or a.sx + a.sw > v.w + 1 or a.sy + a.sh > v.h + 1 then
						table.insert(sweepClashes, string.format("[%s %dx%d] %s is off screen", v.name, v.w, v.h, wn))
					end
				end
			end
			local b = wingR.BreakButton
			if b and v.touch then
				local pad = math.min(150, math.floor(v.h * 0.35))
				local function hits(x0, y0, x1, y1)
					return b.sx < x1 and x0 < b.sx + b.sw and b.sy < y1 and y0 < b.sy + b.sh
				end
				if hits(0, v.h - pad, v.w * 0.35, v.h) or hits(v.w * 0.75, v.h - pad, v.w, v.h) then
					table.insert(sweepClashes, string.format("[%s %dx%d] BREAK sits under a touch control", v.name, v.w, v.h))
				end
				if b.sw < 44 - 0.5 or b.sh < 44 - 0.5 then
					table.insert(sweepClashes, string.format("[%s %dx%d] BREAK is %.0fx%.0f px, under 44", v.name, v.w, v.h, b.sw, b.sh))
				end
			end
		end
		for _, c in sweepClashes do print("   " .. c) end
		print(string.format("   the wing panel and a flying hazard's warning on all %d viewports: panel shown on %d, warning on %d, the HUD's full hotbar on %d, %d clash(es)",
			#ALL_VIEWPORTS, panelShown, warnShown, hotbarShown, #sweepClashes))
		assert(panelShown == #ALL_VIEWPORTS and warnShown == #ALL_VIEWPORTS, "the panel and the warning must be SHOWN on every viewport to be measured")
		assert(hotbarShown == #ALL_VIEWPORTS, "the HUD's hotbar must be SHOWN on every viewport to be measured")
		assert(#sweepClashes == 0, "FAIL - the wing panel, the warning or the HUD's own hotbar covers the HUD on some phone size")
		-- ... and in a session that is not saving, the HUD's red "not saving" line under the cash panel is up: on
		-- 568x320 the panel's pocket starts below it, and the panel is not shown where the pocket is then too short
		do
			h:setTouch(true)
			h:setViewport(568, 320)
			local ro = table.clone(livePayload)
			ro.canSave = false
			for _ = 1, 3 do
				state:FireClient(player, ro)
				settle(h, player, 1 / 30)
			end
			local hudR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotHud"), 568, 320)
			local wingR = rectsByName(h, player:FindFirstChild("PlayerGui"):FindFirstChild("DepotWings"), 568, 320)
			assert(hudR.SaveWarn ~= nil, "CONTROL: the HUD shows its not-saving line on a read-only payload")
			local a, b = wingR.WingPanel, hudR.SaveWarn
			local clear = a == nil or math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx) <= 1
				or math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy) <= 1
			print(string.format("   568x320, not saving: the wing panel %s the HUD's not-saving line",
				if a == nil then "steps away (no pocket) from" elseif clear then "keeps clear of" else "COVERS"))
			assert(clear, "the wing panel never covers the HUD's not-saving line")
			state:FireClient(player, livePayload)
			settle(h, player, 2 / 30)
		end
		-- REVIEW-3 finding 2: a drawer's wait (15 s at most) runs on the RUNNING clock only. A phone player who reads
		-- the MANUAL between shifts must not use it up there and meet the hazard the instant the next shift starts.
		-- 4 s of running clock with the drawer open (a hazard due within 2 s of opening), then 20 s with the clock
		-- stopped (an armed tray), then running again with the drawer still open: at least 15 - 4 = 11 s of the wait
		-- are left, so nothing comes for 10 s (a literal), and the held hazard does come after that.
		do
			h:setTouch(true)
			h:setViewport(800, 360)
			local hudRoot = hud(player)
			closeAll(hudRoot)
			local armedP = table.clone(livePayload)
			armedP.shift = table.clone(livePayload.shift)
			armedP.shift.state = "ARMED"
			armedP.shift.carried = {}
			local frames = 0
			local function stepWith(payload)
				frames += 1
				state:FireClient(player, payload)
				hum.MoveDirection = if frames % 120 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
				settle(h, player, 1 / 30)
			end
			for _ = 1, 30 * 12 do
				if not hazardFlying(h) then break end
				stepWith(livePayload)
			end
			local manualToggle = hudRoot:FindFirstChild("Toggles"):FindFirstChild("Toggle_manual")
			manualToggle.Activated:Fire()
			assert(hudRoot:FindFirstChild("ManualDrawer").Visible, "CONTROL: the MANUAL drawer opened")
			local early = false
			for _ = 1, 30 * 4 do
				stepWith(livePayload)
				if hazardFlying(h) then early = true end
			end
			for _ = 1, 30 * 20 do stepWith(armedP) end
			local cameAfter = nil
			for f = 1, 30 * 16 do
				stepWith(livePayload)
				if hazardFlying(h) then cameAfter = f / 30; break end
			end
			print(string.format("   the drawer's wait runs on the running clock only: 4 s running + 20 s stopped + running again: the held hazard came %s s after the clock restarted",
				tostring(cameAfter and string.format("%.1f", cameAfter))))
			assert(not early, "CONTROL: no hazard in the first 4 s under the drawer")
			assert(cameAfter ~= nil and cameAfter >= 10, "a stopped clock does not use up the drawer's wait (" .. tostring(cameAfter) .. ")")
			manualToggle.Activated:Fire()
			settle(h, player, 2 / 30)
		end
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
assert(holds.phoneLaunched == 0, "no hazard launches in the first 10 s a phone's drawer covers the screen (" .. holds.phoneLaunched .. ")")
print(string.format("   kept open: the held hazard came under the open drawer in %d of %d phone runs, %.1f-%.1f s after it opened, its warning up in %d",
	holds.capCame, holds.phoneDrawer, holds.capMin, holds.capMax, holds.capWarned))
assert(holds.capCame == holds.phoneDrawer, "a drawer kept open is not a shield: the held hazard comes in every phone run (" .. holds.capCame .. ")")
assert(holds.capMin >= 15 - 1e-6, "and never sooner than 15 s after the drawer opened (" .. holds.capMin .. ")")
assert(holds.capMax <= 17 + 2 / 30 + 1e-6, "and at most 15 s after it fell due (<= 17 s after opening: " .. holds.capMax .. ")")
assert(holds.capWarned == holds.capCame, "with its warning up beside the drawer every time (" .. holds.capWarned .. ")")
assert(holds.desktop >= 3, "CONTROL: where a drawer does not cover the screen hazards launch with it open (" .. holds.desktop .. ")")
if #clashes > 0 then
	error(string.format("FAIL — the wings sit on the HUD's rows %d time(s)", #clashes), 0)
end
print(string.format("PASS — the wing panel and the hazard warning keep off the HUD's memo, hint, toast, stamp, cash, clock, toggles and hotbar on all %d viewports x 5 modes and on all %d with a hazard in flight; the title card keeps off them and the hotbar on all %d",
	#HudCheck.VIEWPORTS, #ALL_VIEWPORTS, #ALL_VIEWPORTS))
