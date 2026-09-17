-- Lost & Found Depot — headless HUD fit check. Run: luau check_lostfounddepot_hud.luau
-- Regenerate the bundle first:
--   py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--
-- hudcheck boots the real server and the real Hud.client and measures every shown panel across
-- phone, tablet and desktop viewports: nothing off screen, every tappable thing >= 44 screen px on
-- touch, nothing tappable under Roblox's thumbstick (bottom-left 35%) or jump button (bottom-right
-- 25%), panels under half a phone screen, no two panels on top of each other (overlap = true), and
-- a scroll canvas that reaches its last row.
--
-- The HUD has MODES, and a sweep that only measures the idle one scores every other mode as a pass
-- because the controls are invisible. So every viewport is measured SIX times: mid-shift with a
-- full five-slot hotbar, with each of MANUAL, UPGRADES and CODES open, with the summary card up, and
-- with the Back Room note card up.
--
-- Nothing measured here is a hand-written payload. The tester's save is preloaded (cart level 3,
-- so the hotbar really has five slots; stage 3, so the manual really has all three layers), and
-- the warmup drives the real server: a shift that runs out of time produces the SUMMARY payload,
-- five real picks produce the full hotbar. The note card is filled by replaying the note from the
-- server's own Secret module through the real Scene remote, because reaching the door for real
-- needs a correct sort this file has no business computing.
--
-- One harness gap is bridged here and nowhere else: the harness models src/shared as ModuleScripts
-- but not src/server/Secret.luau, which Rojo also puts in ServerScriptService. The wrapper below
-- registers it just before the server runs, exactly as check_lostfounddepot.luau does.

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")

local TESTER = 5551212 -- the user id hudcheck joins with

local realTryRun = Harness.tryRun
Harness.tryRun = function(self, key)
	if key == "server/Main.server" then
		-- pin the per-session salt: the same depot every run
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
	-- the note pages with NEXT and closes on its last page, so press it the way a player reads it
	local note = root:FindFirstChild("NoteCard")
	for _ = 1, 10 do
		if not note.Visible then break end
		note:FindFirstChild("CloseButton").Activated:Fire()
	end
	for _, name in { "ManualDrawer", "UpgradesDrawer", "CodesDrawer", "SummaryCard", "NoteCard" } do
		assert(not root:FindFirstChild(name).Visible, name .. " did not close")
	end
end

local function open(key)
	return function(_h, player)
		local root = hud(player)
		closeAll(root)
		root:FindFirstChild("Toggles"):FindFirstChild("Toggle_" .. key).Activated:Fire()
		assert(root:FindFirstChild(DRAWER[key]).Visible, key .. " drawer did not open")
	end
end

local function idle(_h, player)
	local root = hud(player)
	closeAll(root)
	assert(root:FindFirstChild("Hotbar").Visible, "the hotbar is not showing mid-shift")
end

local summaryPayload, livePayload = nil, nil
local function summary(h, player)
	local root = hud(player)
	closeAll(root)
	local state = h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("State")
	-- The card appears on the TRANSITION into SUMMARY, as in play: the live payload, then the
	-- SUMMARY payload the server produced in the warmup.
	state:FireClient(player, livePayload)
	state:FireClient(player, summaryPayload)
	assert(root:FindFirstChild("SummaryCard").Visible, "the summary card did not show")
end

local notePrinted = false
local function note(h, player)
	local root = hud(player)
	closeAll(root)
	local Secret = h:_require(h.services.ServerScriptService:FindFirstChild("Secret"))
	h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("Scene"):FireClient(player, {
		lines = Secret.Note, camFrom = { 100, 7, -24 }, camTo = { 100, 5, -47 },
	})
	local card = root:FindFirstChild("NoteCard")
	assert(card.Visible, "the note card did not show")
	-- The pages have to add up to the whole note, in order, and end on CLOSE.
	local pageText = card:FindFirstChild("NotePage").Text
	local total = tonumber(string.match(pageText, "^1 / (%d+)$"))
	assert(total ~= nil and total >= 2, "the note is paged (got " .. pageText .. ")")
	local seen = {}
	for page = 1, total do
		table.insert(seen, card:FindFirstChild("NoteText").Text)
		assert(card:FindFirstChild("CloseButton").Text == (if page < total then "NEXT" else "CLOSE"),
			"page " .. page .. " button reads " .. card:FindFirstChild("CloseButton").Text)
		if page < total then card:FindFirstChild("CloseButton").Activated:Fire() end
	end
	local joined = table.concat(seen, " ")
	for _, line in Secret.Note do
		assert(line == "" or string.find(joined, line, 1, true), "the pages lost a line: " .. line)
	end
	-- back to page 1 for the measurement: re-send the scene, as pressing E at the door does
	h.ReplicatedStorage:FindFirstChild("DepotRemotes"):FindFirstChild("Scene"):FireClient(player, {
		lines = Secret.Note, camFrom = { 100, 7, -24 }, camTo = { 100, 5, -47 },
	})
	assert(card:FindFirstChild("NotePage").Text == "1 / " .. total, "re-sending the note starts at page 1")
	if not notePrinted then
		notePrinted = true
		print(string.format("   note   %-28s %d pages, every line present, NEXT x%d then CLOSE", "paged,", total, total - 1))
	end
end

local modes = {
	{ tag = "", before = idle },
	{ tag = ", manual", before = open("manual") },
	{ tag = ", upgrades", before = open("upgrades") },
	{ tag = ", codes", before = open("codes") },
	{ tag = ", summary", before = summary },
	{ tag = ", note", before = note },
}
local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	for _, m in modes do
		table.insert(viewports, { name = v.name .. m.tag, w = v.w, h = v.h, touch = v.touch, before = m.before })
	end
end

HudCheck.run({
	game = "lost-found-depot",
	bundle = require("./build/lost-found-depot"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
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
		assert(last().stage == 3, "the preloaded tester is not on stage 3")
		local bay = player.RespawnLocation.Parent
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		hrp.CFrame = CFrame.new(bay:FindFirstChild("BayPad").Position.X, 3, 0)

		-- a real SUMMARY: start the clock, let it run out
		bay:FindFirstChild("Slot_1"):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(player)
		h:advance(331)
		summaryPayload = last()
		assert(summaryPayload.shift.state == "SUMMARY", "no SUMMARY payload was produced")
		h:advance(5)
		assert(last().shift.state == "ARMED", "the bay did not re-arm")

		-- a real full hotbar: five picks from the pick point
		for s = 1, 5 do
			bay:FindFirstChild("Slot_" .. s):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(player)
		end
		h:advance(0.5)
		livePayload = last()
		assert(#livePayload.shift.carried == 5, "the warmup could not carry five items")
		local root = hud(player)
		local shown = 0
		for k = 1, 5 do
			if root:FindFirstChild("Hotbar"):FindFirstChild("Slot_" .. k).Visible then shown += 1 end
		end
		assert(shown == 5, "the hotbar did not grow to 5 slots")
		local manualLines = 0
		for _, c in root:FindFirstChild("ManualDrawer"):GetChildren() do
			if c.ClassName == "TextLabel" then manualLines += 1 end
		end
		print(string.format("   warmup %-28s %d hotbar slots, %d manual lines, summary captured", "server driven,",
			shown, manualLines))
	end,
})
