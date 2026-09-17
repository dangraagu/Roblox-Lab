-- Steal a Cryptid - headless HUD fit check, every viewport in three states.
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_hud.luau 2>&1
--
-- The HUD has three modes worth measuring, and a sweep that only sees the idle one scores the
-- other two as a pass because their controls are simply invisible (vault-runners' collapse timer
-- sat on its wallet on every portrait phone, green, for exactly that reason). So every viewport is
-- run three times:
--   hunt panel  - at home, the Hunt Board panel open (the longest panel; it must scroll on a phone)
--   build sheet - build mode on, a yard cell picked (the action sheet open)
--   raiding     - a raid in progress: the raid chip, the Leave camp toggle, the carrying hint
-- Each state is reached the way the game reaches it: by firing the server's own remotes to the
-- client, with the payload the REAL server pushed at join, altered only where the mode differs.

local HudCheck = require("./emu/hudcheck")

--============================================================ text a phone can read
--
-- emu/hudcheck measures boxes, not the text in them, and REVIEW-1 found the text was the problem:
-- on an 844x390 phone the Toast was a 360 x 13 screen-px box holding a 112-character line with
-- TextScaled on and wrapping off, and the not-saving banner a 276 x 10.8 box holding 99 characters.
-- Both fit. Neither could be read.
--
-- So every mode below also puts the LONGEST text the game allows on screen (a toast of
-- ToastMaxChars, a banner of BannerMaxChars; the server's own checks assert nothing it sends is
-- longer) and estimates the size each shown TextLabel/TextButton renders at, in SCREEN px:
--   TextScaled, wrapping:  the largest s <= MaxTextSize x UIScale with
--                          (sum over lines of ceil(chars x ADVANCE x s / width)) x LINE x s <= height
--   TextScaled, no wrap:   min(MaxTextSize x UIScale, height / (lines x LINE), width / (longest x ADVANCE x s))
-- ADVANCE (0.55 em per character) and LINE (1.2 em per line) are ASSUMPTIONS about GothamBold, not
-- measurements: nothing headless renders a glyph.
--
-- THE RULE, and why it is not a flat minimum. docs/mobile-ui-brief.md scales the whole HUD down on
-- a phone on purpose ("text still has to shrink to fit"): at Responsive.MIN_SCALE 0.6 a label
-- designed at 16 px draws at 9.6 screen px in every game in this repo. A flat 11 px floor would fail
-- that shared pattern everywhere, which is a design question, not this defect. The defect is text
-- SQUEEZED far below the size it was designed at because its box is too small for the string. So a
-- shown text passes when it renders at >= LEGIBLE_PX (11, Apple's minimum legible size), OR at
-- >= FLOOR_PX (8, what the smallest design size in this HUD, 14 px, draws at on the 0.6 scale) AND
-- at >= SQUEEZE of its own cap (MaxTextSize x UIScale). Both thresholds are judgement, stated here;
-- a Studio photograph at phone size is what settles legibility (CLAUDE.md, Needs Studio).
local ADVANCE, LINE = 0.55, 1.2
local LEGIBLE_PX, FLOOR_PX, SQUEEZE = 11, 8, 0.85
local MIN_TEXT_PX = LEGIBLE_PX
local ToastMaxChars, BannerMaxChars = 100, 90
local LONG_TOAST = string.sub("Your steal could not be saved, so the Jersey Devil went back and your permit was refunded to you now", 1, ToastMaxChars)
local LONG_BANNER = string.sub("Your save could not be loaded, so nothing is saved this session. Rejoin to try again now.", 1, BannerMaxChars)
local legibilityFailures = 0

local function estimateTextPx(r)
	local obj = r.obj
	local text = tostring(obj.Text or "")
	if text == "" or not obj.TextScaled then
		return nil
	end
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

local function checkLegibility(h, player, modeName)
	local cam = h.workspace.CurrentCamera
	local gui = player:FindFirstChild("PlayerGui"):FindFirstChild("CryptidHud")
	local rects = h:guiRects(gui, cam.ViewportSize.X, cam.ViewportSize.Y)
	local worst, worstName = math.huge, "-"
	for _, r in rects do
		if r.shown and (r.class == "TextLabel" or r.class == "TextButton") then
			local px = estimateTextPx(r)
			if px then
				if px < worst then worst, worstName = px, r.name end
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
	print(string.format("   text      %-34s smallest ~%.1f screen px (%s)", modeName, worst, worstName))
end

local function remotesOf(h)
	local r = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
	assert(r ~= nil, "the server created no CryptidRemotes")
	return r
end

local function lastState(h, player)
	local sent = remotesOf(h).State:getSent()
	for i = #sent, 1, -1 do
		local rec = sent[i]
		if rec.player == player and type(rec.args[1]) == "table" then
			return table.clone(rec.args[1])
		end
	end
	error("the server never pushed State to the test player")
end

-- The server pushes a fresh State once a second (the income tick, on whole seconds of its clock).
-- A crafted payload fired just before one of those would be replaced before the gate measures it,
-- and the mode would silently not be measured. So every hook first steps the clock to just past a
-- whole second, then fires, then PROVES the mode is on screen: the gate measures 0.15 s later,
-- well inside the 0.99 s before the next push.
local function alignToIncomeTick(h)
	local now = h.scheduler:now()
	h:advance(math.ceil(now + 1e-9) - now + 0.01)
end

local function rootOf(player)
	local gui = player:FindFirstChild("PlayerGui"):FindFirstChild("CryptidHud")
	assert(gui ~= nil, "the client built no CryptidHud")
	return gui:FindFirstChild("Root")
end

local function hunt(h, player)
	alignToIncomeTick(h)
	local r = remotesOf(h)
	local s = lastState(h, player)
	s.raid = nil
	s.buildMode = false
	s.tutorial = 2
	s.canSave = false
	s.saveBanner = LONG_BANNER
	r.State:FireClient(player, s)
	r.Fx:FireClient(player, "openHunt")
	r.Toast:FireClient(player, LONG_TOAST)
	assert(rootOf(player).HuntPanel.Visible, "hunt mode: the Hunt panel did not open")
	checkLegibility(h, player, "hunt panel")
end

local function sheet(h, player)
	alignToIncomeTick(h)
	local r = remotesOf(h)
	local s = lastState(h, player)
	s.raid = nil
	s.buildMode = true
	s.tutorial = 4
	r.State:FireClient(player, s)
	r.Fx:FireClient(player, "buildCell", { col = 3, row = 4, trap = "snare" })
	r.Toast:FireClient(player, LONG_TOAST)
	assert(rootOf(player).BuildSheet.Visible, "sheet mode: the build sheet did not open")
	checkLegibility(h, player, "build sheet")
end

local function raiding(h, player)
	alignToIncomeTick(h)
	local r = remotesOf(h)
	local s = lastState(h, player)
	s.buildMode = false
	s.tutorial = 3
	s.raid = { tier = 4, campName = "Crooked Maggie's Camp", timeLeft = 148, carrying = "Jersey Devil" }
	s.canSave = false
	s.saveBanner = LONG_BANNER
	r.State:FireClient(player, s)
	r.Toast:FireClient(player, LONG_TOAST)
	local root = rootOf(player)
	assert(root.RaidChip.Visible and root.Toggles.LeaveToggle.Visible and root.SaveBanner.Visible,
		"raid mode: the chip, the Leave camp toggle and the banner are not all showing")
	assert(not root.HuntPanel.Visible and not root.BuildSheet.Visible, "raid mode: a centre panel is still open")
	checkLegibility(h, player, "raiding")
	-- the longest hint the HUD writes is the in-camp one (tutorial 3, not carrying, on touch)
	local walking = table.clone(s)
	walking.raid = { tier = 4, campName = "Crooked Maggie's Camp", timeLeft = 148, carrying = nil }
	r.State:FireClient(player, walking)
	checkLegibility(h, player, "raiding, walking in")
	r.State:FireClient(player, s)
end

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	for _, mode in { { "hunt panel", hunt }, { "build sheet", sheet }, { "raiding", raiding } } do
		table.insert(viewports, { name = v.name .. ", " .. mode[1], w = v.w, h = v.h, touch = v.touch, before = mode[2] })
	end
end

local okGate, gateErr = pcall(HudCheck.run, {
	game = "steal-a-cryptid",
	bundle = require("./build/steal-a-cryptid"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
	viewports = viewports,
	overlap = true,
	warmup = function(h, player)
		-- the State the server pushed at join arrived before the client existed; replay it so the
		-- panel rows are built from a real payload
		local s = lastState(h, player)
		remotesOf(h).State:FireClient(player, s)
		print(string.format("   warmup %-28s essence %d, %d camps", "State replayed,", s.essence, #s.camps))
	end,
})

print("")
if legibilityFailures > 0 then
	print(string.format("FAIL — %d text element(s) squeezed below the legibility rule (see LEGIBILITY lines)", legibilityFailures))
else
	print(string.format("PASS — every shown HUD text is legible by the rule (>= %d px, or >= %d px and >= %d%% of its cap) with a %d-char toast and a %d-char banner", LEGIBLE_PX, FLOOR_PX, SQUEEZE * 100, ToastMaxChars, BannerMaxChars))
end
if not okGate then error(gateErr, 0) end
if legibilityFailures > 0 then error("steal-a-cryptid HUD text legibility failed", 0) end
