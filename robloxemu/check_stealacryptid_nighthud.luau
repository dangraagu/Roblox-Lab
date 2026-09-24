-- Steal a Cryptid - HUD fit and legibility with the NIGHT on screen: both client scripts, every viewport,
-- every state the night adds to the HUD.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_nighthud.luau 2>&1
--
-- check_stealacryptid_hud.luau (unchanged) proves the HUD alone. This file loads Hud.client AND
-- Night.client and measures, in all ten viewports:
--   hunt panel  - the Hunt panel open, the new Rest toggle in the top-right row reading "Resting";
--   resting     - the chip carrying the rest line (Night's "Resting - poachers still come");
--   hazard      - the chip carrying the LONGEST hazard warning Night can write, the button "Rest...";
--   raiding     - the raid chip, Leave camp, and no Rest toggle;
--   title card  - Night's own card with the longest band name and subtitle, over a hazard warning.
-- The night's lines reach the HUD through its NightBus (client-local values); each hook writes them the
-- way Night.client does. The text rule is check_stealacryptid_hud.luau's, copied: >= 11 screen px, or
-- >= 8 px and >= 85 % of the text's own cap (0.55 em per character, 1.2 em per line: assumptions).

local HudCheck = require("./emu/hudcheck")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Night = require("../steal-a-cryptid/src/shared/Night")

local ADVANCE, LINE = 0.55, 1.2
local LEGIBLE_PX, FLOOR_PX, SQUEEZE = 11, 8, 0.85
local legibilityFailures, measured = 0, 0
local T = Config.Night.Text

-- the longest strings the night can put on screen
local longestAlert, longestTitle, longestSub = "", "", ""
for kind in Config.Night.Hazards.Kinds do
	for _, b in { "left", "right", "ahead", "behind" } do
		for _, locked in { false, true } do
			local s = Night.alertText(Config, kind, b, locked)
			if #s > #longestAlert then longestAlert = s end
		end
	end
end
for _, band in Config.Night.Home do
	if #band.name > #longestTitle then longestTitle = string.upper(band.name) end
	if #band.sub > #longestSub then longestSub = band.sub end
end
local longestRestLine = T.Resting
for _, s in { T.Idle, T.Queued } do if #s > #longestRestLine then longestRestLine = s end end
local longestLabel = T.RestingButton
for _, s in { T.RestButton, T.QueuedButton } do if #s > #longestLabel then longestLabel = s end end

local function estimateTextPx(r)
	local obj = r.obj
	local text = tostring(obj.Text or "")
	if text == "" or not obj.TextScaled then return nil end
	local cap = 100
	local c = obj:FindFirstChildOfClass("UITextSizeConstraint")
	if c then cap = c.MaxTextSize end
	cap *= r.scale
	r.capPx = cap
	local lines = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do table.insert(lines, #line) end
	local longest = 0
	for _, n in lines do longest = math.max(longest, n) end
	if r.sw <= 0 or r.sh <= 0 then return 0 end
	if obj.TextWrapped then
		local best = 0
		for s = 1, math.floor(cap) do
			local total = 0
			for _, n in lines do total += math.max(1, math.ceil(n * ADVANCE * s / r.sw)) end
			if total * LINE * s <= r.sh then best = s end
		end
		return best
	end
	return math.min(cap, r.sh / (#lines * LINE), r.sw / (math.max(1, longest) * ADVANCE))
end

-- The emulator does not lay out a UIListLayout's children, so a Toggles frame sized for three buttons
-- while four show would pass every rule above. The row's own width must hold every visible button.
local rowFailures = 0
local function checkToggleRow(player, modeName)
	local toggles = player.PlayerGui.CryptidHud.Root.Toggles
	local list = toggles:FindFirstChildOfClass("UIListLayout")
	local gap = if list and list.Padding then list.Padding.Offset else 0
	local sum, n = 0, 0
	for _, b in toggles:GetChildren() do
		if b.ClassName == "TextButton" and b.Visible then
			sum += b.Size.X.Offset
			n += 1
		end
	end
	sum += gap * math.max(0, n - 1)
	if sum > toggles.Size.X.Offset + 0.5 then
		rowFailures += 1
		print(string.format("   ROW %s: %d visible toggles need %d design px, the row is %d", modeName, n, sum, toggles.Size.X.Offset))
	end
end

local function checkLegibility(h, player, modeName, must)
	checkToggleRow(player, modeName)
	local cam = h.workspace.CurrentCamera
	local seen = {}
	for _, guiName in { "CryptidHud", "CryptidNight" } do
		local gui = player:FindFirstChild("PlayerGui"):FindFirstChild(guiName)
		for _, r in h:guiRects(gui, cam.ViewportSize.X, cam.ViewportSize.Y) do
			if r.shown and (r.class == "TextLabel" or r.class == "TextButton") then
				local px = estimateTextPx(r)
				if px then
					seen[tostring(r.obj.Text)] = true
					measured += 1
					local ok = px >= LEGIBLE_PX or (px >= FLOOR_PX and px >= SQUEEZE * r.capPx)
					if not ok then
						legibilityFailures += 1
						print(string.format("   LEGIBILITY %s %dx%d: %s renders ~%.1f screen px, %.0f%% of its %.1f px cap (box %.0f x %.0f, %d chars): %s",
							modeName, cam.ViewportSize.X, cam.ViewportSize.Y, r.name, px, 100 * px / r.capPx, r.capPx, r.sw, r.sh,
							#tostring(r.obj.Text), string.sub(tostring(r.obj.Text), 1, 60)))
					end
				end
			end
		end
	end
	-- the mode really is on screen: the strings it is about were measured
	for _, s in must or {} do
		assert(seen[s], modeName .. ": '" .. s .. "' was not on screen to be measured")
	end
end

local function remotesOf(h) return h.ReplicatedStorage:FindFirstChild("CryptidRemotes") end
local function lastState(h, player)
	local sent = remotesOf(h).State:getSent()
	for i = #sent, 1, -1 do
		local rec = sent[i]
		if rec.player == player and type(rec.args[1]) == "table" then return table.clone(rec.args[1]) end
	end
	error("the server never pushed State to the test player")
end
local function alignToIncomeTick(h)
	local now = h.scheduler:now()
	h:advance(math.ceil(now + 1e-9) - now + 0.01)
end
local function hudRoot(player) return player.PlayerGui.CryptidHud.Root end
local function bus(player) return player.PlayerGui.CryptidHud.NightBus end
local function nightSays(player, label, status, kind)
	local b = bus(player)
	b.RestLabel.Value = label
	b.Status.Value = status
	b.StatusKind.Value = kind
end
local function home(h, player, over)
	alignToIncomeTick(h)
	local s = lastState(h, player)
	s.raid = nil
	s.buildMode = false
	s.poacher = nil
	s.tutorial = 4
	for k, v in over or {} do s[k] = v end
	remotesOf(h).State:FireClient(player, s)
	-- each home mode starts with the Hunt panel closed (the previous viewport may have opened it)
	local panel = hudRoot(player).HuntPanel
	if panel.Visible then panel.CloseRow.Go.Activated:Fire() end
end

local function huntMode(h, player)
	home(h, player)
	nightSays(player, longestLabel, "", "")
	remotesOf(h).Fx:FireClient(player, "openHunt")
	local r = hudRoot(player)
	assert(r.HuntPanel.Visible, "hunt: the Hunt panel did not open")
	assert(r.Toggles.RestToggle.Visible, "hunt: no Rest toggle at home")
	checkLegibility(h, player, "hunt panel + Rest", { longestLabel })
end
local function restingMode(h, player)
	home(h, player)
	nightSays(player, T.RestingButton, longestRestLine, "calm")
	local r = hudRoot(player)
	assert(r.RaidChip.Visible and r.RaidChip.Text.Text == longestRestLine, "resting: the chip does not carry the rest line")
	checkLegibility(h, player, "resting", { longestRestLine })
end
local function hazardMode(h, player)
	home(h, player)
	nightSays(player, T.QueuedButton, longestAlert, "danger")
	local r = hudRoot(player)
	assert(r.RaidChip.Visible and r.RaidChip.Text.Text == longestAlert, "hazard: the chip does not carry the warning")
	checkLegibility(h, player, "hazard warning", { longestAlert, T.QueuedButton })
end
local function raidMode(h, player)
	alignToIncomeTick(h)
	local s = lastState(h, player)
	s.buildMode = false
	s.tutorial = 4
	s.raid = { tier = 4, campName = "Crooked Maggie's Camp", timeLeft = 148, carrying = "Jersey Devil" }
	nightSays(player, T.RestButton, "", "")
	remotesOf(h).State:FireClient(player, s)
	local r = hudRoot(player)
	assert(r.RaidChip.Visible and r.Toggles.LeaveToggle.Visible, "raid: no raid chip / Leave camp")
	assert(not r.Toggles.RestToggle.Visible, "raid: the Rest toggle is showing in a camp")
	checkLegibility(h, player, "raiding")
end
local function cardMode(h, player)
	home(h, player)
	nightSays(player, T.RestButton, longestAlert, "danger")
	local root = player.PlayerGui.CryptidNight.Root
	root.Card.Text = longestTitle
	root.CardSub.Text = longestSub
	root.Card.Visible = true
	root.CardSub.Visible = true
	checkLegibility(h, player, "title card", { longestTitle, longestSub, longestAlert })
	root.Card.Visible = false
	root.CardSub.Visible = false
end

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	for _, mode in { { "hunt+rest", huntMode }, { "resting", restingMode }, { "hazard", hazardMode }, { "raiding", raidMode }, { "card", cardMode } } do
		table.insert(viewports, { name = v.name .. ", " .. mode[1], w = v.w, h = v.h, touch = v.touch, before = mode[2] })
	end
end

print(string.format("   longest night strings: alert %d chars, rest line %d, card '%s' / '%s'", #longestAlert, #longestRestLine, longestTitle, longestSub))
local okGate, gateErr = pcall(HudCheck.run, {
	game = "steal-a-cryptid (with the night)",
	bundle = require("./build/steal-a-cryptid"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Night.client" },
	viewports = viewports,
	overlap = true,
	warmup = function(h, player)
		remotesOf(h).State:FireClient(player, lastState(h, player))
		assert(player.PlayerGui:FindFirstChild("CryptidNight"), "Night.client built no ScreenGui")
		assert(player.PlayerGui.CryptidHud:FindFirstChild("NightBus"), "the HUD built no NightBus")
	end,
})

print("")
print(string.format("   %d text elements measured across the five night modes", measured))
if legibilityFailures > 0 then
	print(string.format("FAIL - %d text element(s) squeezed below the legibility rule (see LEGIBILITY lines)", legibilityFailures))
else
	print(string.format("PASS - every shown text, HUD and night, is legible by the rule (>= %d px, or >= %d px and >= %d%% of its cap)", LEGIBLE_PX, FLOOR_PX, SQUEEZE * 100))
end
if rowFailures > 0 then
	print(string.format("FAIL - %d time(s) the top-right row was narrower than its visible toggles (see ROW lines)", rowFailures))
else
	print("PASS - the top-right row holds every visible toggle (Rest, Hunt, Build; Leave camp) in every mode")
end
if not okGate then error(gateErr, 0) end
if legibilityFailures > 0 then error("steal-a-cryptid night HUD legibility failed", 0) end
if rowFailures > 0 then error("steal-a-cryptid toggle row too narrow", 0) end
