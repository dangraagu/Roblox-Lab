-- Gnome Garden Defense: THE PLAYER'S PATH, walked in the built world, through the HUD's own buttons.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       cd ../gnome-garden-defense && luau tests/walk.luau
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- A new player joins, sees the hint, taps a glowing pad, plants from the gnome sheet, presses READY, and plays
-- spring the way tests/GardenModel.luau's NORMAL profile does (a decision every 2.5 s, five gnomes in spring at
-- 4 : 1.5 pebbles to sprinklers, then upgrades, READY 14 s into a build phase), every action through a tap on a
-- pad, a gnome or a HUD button. A loss is retried from the result panel; the win goes to the next season from
-- it; then the second loop (summer) is played a few waves in, and the player rejoins. Everything it saw is
-- printed in numbers. The game's modules are used only to ADDRESS things (which pads see the most path).
--
-- REVIEW-1: a tap is a FINGER ON THE SCREEN (tests/Tap.luau: the current camera, an independent projection, a
-- UserInputService.TouchTap), with View.client running. A finger is not a pixel: where a pad's cell is under 44
-- px on screen the tap lands 9 px off its centre, and when the garden view then shows a neighbour selected, the
-- walker taps again on the now-zoomed pad. Every gnome planted or upgraded is measured on screen as the walker
-- saw it when it pressed the sheet's button.
-- REVIEW-2: the walker uses only what the screen shows. It decides to tap again by the pad drawn GOLD (not the
-- hidden SelectedPad attribute); it plants the gnome the sheet stars (★), on a pad that glows (the lowest-numbered
-- of the glowing ones, an arbitrary visible choice), as the pacing model's normal player does; on a phone the
-- first tap on a small cell only zooms. And the season's own card ("SPRING WON") must stay readable.

local Harness = require("../../robloxemu/emu/harness")
local Config = require("../src/shared/Config")
local PathGen = require("../src/shared/PathGen")

local Tap = require("./Tap")

local h = Harness.new({ bundle = require("../../robloxemu/build/gnome-garden-defense"), name = "gnome-garden-walk", viewport = { 844, 390 }, touch = true })
local tap = Tap.bind(h, { Vector2 = Vector2, Vector3 = Vector3 })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
local UID = 8080
local me = h:join("Sprout", UID)
h:advance(0.2)
local char = h.Players:simulateSpawn(me, h.workspace)
RunService:setIsServer(false)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.WoodPlanks
hum.MoveDirection = Vector3.new(0, 0, 0)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Garden.client"))
assert(h:tryRun("client/Board.client"))
assert(h:tryRun("client/View.client"))

local clock = 0 -- seconds of play since the character landed
local springCardFrames = 0 -- frames the "SPRING WON" card was on screen, readable (REVIEW-2)
local function frames(seconds)
	local dt = 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
		clock += dt
		local sky = me.PlayerGui:FindFirstChild("GardenSky")
		local card = sky and sky.Root.BandCard
		if card and card.Visible and card.TextTransparency < 0.5 and string.find(card.Text, "SPRING WON", 1, true) then
			springCardFrames += 1
		end
	end
end
frames(0.5)

local function myGarden()
	for _, g in h.workspace.Gardens:GetChildren() do
		if g:GetAttribute("Owner") == UID then return g end
	end
	return nil
end
local function hud() return me.PlayerGui.GardenHud.Root end
local function attr(name) local g = myGarden(); return g and g:GetAttribute(name) end

-- the pads a player would pick: the ones that see the most path for this gnome's range
local function rankedPads(range)
	local g = myGarden()
	local path = PathGen.fromText(Config, g:GetAttribute("PathCells"))
	local out = {}
	for id, pd in PathGen.pads(Config, path) do
		local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, range)
		table.insert(out, { id = id, cover = cover })
	end
	table.sort(out, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	return out
end
local function gnomes()
	local out = {}
	for _, m in myGarden().Bed.Gnomes:GetChildren() do table.insert(out, m) end
	return out
end
local function press(btn) btn.Activated:Fire() frames(0.1) end
local function state() return me.PlayerGui:FindFirstChild("GardenClientState") end
-- what the walker SEES of the pads: neon gold = the pad its sheet is for; neon green = the pads that glow
local function padsLooking(how)
	local out = {}
	local bed = myGarden():FindFirstChild("Bed")
	for _, d in (if bed then bed:GetChildren() else {}) do
		local id = d:GetAttribute("PadId")
		if id and d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			local c = d.Color
			local gold = c.R >= 0.9 and c.G >= 0.55 and c.G <= 0.88 and c.B <= 0.4
			if (how == "gold" and gold) or (how == "glow" and not gold and c.G > c.R and c.G > c.B) then table.insert(out, id) end
		end
	end
	table.sort(out)
	return out
end
local function goldPad()
	local g = padsLooking("gold")
	return if #g == 1 then g[1] else nil
end

-- a finger: on the screen, through the camera the player sees now. A pad off the screen (the view is zoomed
-- elsewhere) is waited for: the view eases back to the whole garden once the sheet is shut.
local taps = { total = 0, retaps = 0, offCentre = 0, smallestSeen = math.huge, smallestUsed = math.huge, duringHazard = 0 }
local NUDGE = { { 9, 0 }, { 0, 9 }, { -9, 0 }, { 0, -9 } }
local function tapAt(world, wantPad)
	local g = myGarden()
	local waited = 0
	while not tap.onScreen(world) and waited < 6 do
		frames(0.5)
		waited += 0.5
	end
	local w, hgt = tap.cellPx(g, wantPad)
	taps.smallestSeen = math.min(taps.smallestSeen, w, hgt)
	local sx, sy = tap.project(world)
	taps.total += 1
	if math.min(w, hgt) < 44 then
		local n = NUDGE[taps.total % #NUDGE + 1]
		sx, sy = sx + n[1], sy + n[2]
		taps.offCentre += 1
	end
	tap.at(sx, sy)
	frames(0.6) -- the view zooms in on a small cell (on a phone that tap picks nothing: REVIEW-2)
	if goldPad() ~= wantPad then
		-- no pad, or a neighbour, is gold: tap the right one, now big on screen
		taps.retaps += 1
		tap.world(world)
		frames(0.3)
	end
end
local function tapPad(id) tapAt(tap.padCentre(myGarden(), id), id) end
local function tapGnome(m)
	local body = m:FindFirstChild("Body")
	tapAt(body.Position, m:GetAttribute("Pad"))
end
-- what the finger had on screen when it pressed the sheet: the selected pad's cell. While a hazard is live the
-- camera is on the gardener (the red ring big enough to step out of), not on the pad: counted apart
local function measureSelected()
	local sel = state():GetAttribute("SelectedPad")
	if state():GetAttribute("ViewMode") == "hazard" then
		taps.duringHazard += 1
	elseif type(sel) == "number" and sel > 0 then
		local w, hgt = tap.cellPx(myGarden(), sel)
		taps.smallestUsed = math.min(taps.smallestUsed, w, hgt)
	end
end

--============================================================================ the first seconds
local landedAt = clock
local hint = hud().Hint
truthy(hint.Visible and string.find(hint.Text, "Tap a glowing pad", 1, true) ~= nil, "on join the hint says what to do (" .. hint.Text .. ")")
eq(hud().TopBar.SeedsLabel.Text, "🌱 120", "the top bar shows the 120 free seeds")
frames(2) -- a new player looks for two seconds
local glowing = padsLooking("glow")
eq(#glowing, 3, "three pads glow on the fresh bed")
local firstPad = glowing[1]
tapPad(firstPad)
local sheet = hud().GnomeSheet
truthy(sheet.Visible, "tapping a pad opens the gnome sheet")
truthy(string.find(sheet.Slot1.Text, "Pebble", 1, true) ~= nil and string.find(sheet.Slot1.Text, "50", 1, true) ~= nil, "with Pebble 50 first (" .. sheet.Slot1.Text .. ")")
truthy(string.find(sheet.Slot3.Text, "Summer", 1, true) ~= nil, "and the Mushroom shown locked until summer (" .. sheet.Slot3.Text .. ")")
eq(state():GetAttribute("SelectedPad"), firstPad, "the sheet is for the pad the finger meant")
eq(goldPad(), firstPad, "and that pad is drawn gold")
truthy(string.sub(sheet.Slot1.Text, 1, 3) == "★", "the sheet stars the Pebble (" .. sheet.Slot1.Text .. ")")
measureSelected()
frames(1)
press(sheet.Slot1)
local firstPlantAt = clock - landedAt
eq(#gnomes(), 1, "the first gnome stands on the pad")
eq(attr("Seeds"), 70, "seeds 120 -> 70")
truthy(string.find(hint.Text, "One more", 1, true) ~= nil, "the hint moves on (" .. hint.Text .. ")")
print(string.format("  FIRST SECONDS: the core action (a gnome planted) at %.1f s after landing", firstPlantAt))
truthy(firstPlantAt <= 5, "the core action is reachable within 5 seconds")

--============================================================================ the normal profile, by hand
local profile = Config.Pacing.Profiles.normal
-- the gnome the sheet starred the last time the walker looked (a player remembers it, and its price, between two
-- looks; it is read again on every sheet the walker opens)
local starKind = "pebble"
local function readStar(sheetFrame)
	for kind, slot in { pebble = 1, sprinkler = 2, mushroom = 3, lantern = 4 } do
		local b = sheetFrame["Slot" .. slot]
		if b.Visible and string.sub(b.Text, 1, 3) == "★" then return kind end
	end
	return nil
end
local SLOT_OF = { pebble = 1, sprinkler = 2, mushroom = 3, lantern = 4 }

-- one decision: plant (through a pad and the sheet) or upgrade (through a gnome and the sheet)
local actions = { plants = 0, upgrades = 0, refused = 0, noStar = 0 }
local function decide()
	local g = myGarden()
	local chapter = g:GetAttribute("Chapter")
	local seeds = g:GetAttribute("Seeds") or 0
	local want = profile.grow[chapter] or profile.grow[#profile.grow]
	local list = gnomes()
	if #list < want then
		if seeds < Config.Gnomes[starKind].levels[1].cost then return false end
		local lit = padsLooking("glow")
		if #lit == 0 then return false end
		tapPad(lit[1])
		measureSelected()
		local sheetFrame = hud().GnomeSheet
		local kind = readStar(sheetFrame)
		if kind == nil then
			actions.noStar += 1
			press(sheetFrame.CloseButton)
			return false
		end
		starKind = kind
		if seeds < Config.Gnomes[kind].levels[1].cost then
			press(sheetFrame.CloseButton) -- the star moved on to a dearer gnome: wait for the seeds
			return false
		end
		press(sheetFrame["Slot" .. SLOT_OF[kind]])
		actions.plants += 1
		return true
	end
	-- upgrade the lowest-level gnome
	local pick = nil
	for _, m in list do
		local lvl = m:GetAttribute("Level")
		if lvl < 3 and (pick == nil or lvl < pick:GetAttribute("Level")) then pick = m end
	end
	if pick then
		local nxt = Config.Gnomes[pick:GetAttribute("Kind")].levels[pick:GetAttribute("Level") + 1]
		if seeds >= nxt.cost then
			tapGnome(pick)
			measureSelected()
			press(hud().GnomeSheet.Slot1)
			press(hud().GnomeSheet.CloseButton)
			actions.upgrades += 1
			return true
		end
	end
	return false
end

-- the second pebble, then READY
frames(1.5)
decide()
eq(#gnomes(), 2, "a second gnome")
frames(2)
local readyBtn = hud().ReadyButton
truthy(readyBtn.Visible, "READY is on screen")
press(readyBtn)
eq(attr("Phase"), "wave", "READY sends wave 1")
local readyAt = clock - landedAt
print(string.format("  FIRST SECONDS: READY pressed at %.1f s with %d gnomes", readyAt, #gnomes()))

-- play: decisions every 2.5 s, READY 14 s into a build phase, the result panel when a season ends
local log = {}
local attempts = { 1 }
local waveStart, buildSince, revealSince = clock, nil, nil
local lastWave, lastPhase = attr("Wave"), attr("Phase")
local seasonsWon = {}
local secondLoopWaves = 0
local function play(untilFn, limitSeconds)
	local think = 0
	local stopAt = clock + limitSeconds
	while clock < stopAt do
		frames(0.5)
		think += 0.5
		local phase, wave = attr("Phase"), attr("Wave")
		if phase ~= lastPhase or wave ~= lastWave then
			if lastPhase == "wave" and phase ~= "wave" then
				table.insert(log, { chapter = attr("Chapter"), wave = lastWave, seconds = clock - waveStart,
					carrots = attr("Carrots"), seeds = attr("Seeds"), gnomes = #gnomes(), result = phase })
			end
			if phase == "wave" then waveStart = clock end
			if phase == "build" then buildSince = clock end
			if phase == "reveal" then revealSince = clock end
			lastPhase, lastWave = phase, wave
		end
		if untilFn() then return true end
		if phase == "won" or phase == "lost" then
			local result = hud().ResultPanel
			if result.Visible then
				if phase == "won" then table.insert(seasonsWon, { chapter = attr("Chapter"), at = clock - landedAt }) end
				if phase == "lost" then attempts[#attempts] += 1 end
				frames(profile.retrySeconds)
				press(result.ResultButton)
				if phase == "won" then table.insert(attempts, 1) end
				lastPhase = nil
			end
		elseif think >= profile.think then
			think = 0
			local acted = decide()
			if phase == "build" and buildSince and clock - buildSince >= profile.buildSeconds then
				press(hud().ReadyButton)
			end
			-- a new bed: plant until the next plan is unaffordable, at least introSeconds, then READY (the model's intro)
			if phase == "reveal" and not acted and #gnomes() > 0 and revealSince and clock - revealSince >= profile.introSeconds then
				press(hud().ReadyButton)
			end
		end
	end
	return false
end

local wonSpring = play(function() return attr("Chapter") == 2 end, 3600)
truthy(wonSpring, "the normal-profile walker wins spring and reaches summer")
eq(attr("Phase"), "reveal", "summer starts on a fresh bed, waiting for READY")
eq(attr("Seeds"), 420, "with 420 seeds")
eq(me:GetAttribute("Chapter"), 2, "summer is unlocked on the player")
local springAt = seasonsWon[1] and seasonsWon[1].at or -1
print(string.format("  the SPRING WON card was readable for %.1f s", springCardFrames * 0.1))
truthy(springCardFrames >= 30, string.format("the season's own card stays readable 3 s or more, not replaced by the band's (%.1f s)", springCardFrames * 0.1))
eq(actions.noStar, 0, "every plant sheet the walker opened starred a gnome")

-- the second loop: summer, a few waves in
local reached12 = play(function() return (attr("Wave") or 0) >= 13 and attr("Phase") == "wave" end, 900)
truthy(reached12, "the second loop runs: summer reaches wave 13")

-- rejoin
h:leave(me)
h:advance(1)
local back = h:join("Sprout", UID)
h:advance(0.5)
h.Players:simulateSpawn(back, h.workspace)
h:advance(1)
local gBack = myGarden()
eq(gBack and gBack:GetAttribute("Chapter"), 2, "after a rejoin the garden starts summer")
eq(back:GetAttribute("BestWave") >= 12, true, "and the board metric survived the rejoin (best wave " .. tostring(back:GetAttribute("BestWave")) .. ")")

--============================================================================ what happened, in numbers
print("")
print(string.format("  WALK: spring won at %.1f min after landing, in %d attempt(s); %d plants, %d upgrades",
	springAt / 60, attempts[1], actions.plants, actions.upgrades))
print("  WAVE  chapter  seconds  carrots  seeds  gnomes  ->")
for _, r in log do
	print(string.format("  %4d  %7d  %7.1f  %7d  %5d  %6d  %s", r.wave, r.chapter, r.seconds, r.carrots, r.seeds, r.gnomes, r.result))
end
print(string.format("  TAPS: %d taps, %d of them 9 px off centre (a cell under 44 px), %d needed a second tap; the smallest cell"
	.. " tapped at was %.1f px, the smallest cell a gnome was planted or upgraded on was %.1f px (%d more confirmed while a"
	.. " hazard had the camera)", taps.total, taps.offCentre, taps.retaps, taps.smallestSeen, taps.smallestUsed, taps.duringHazard))
local boardSent = h.ReplicatedStorage.GardenRemotes.Board:sentTo(me)
print(string.format("  BOARD: %d board views sent; best wave on the player: %s", #boardSent, tostring(me:GetAttribute("BestWave"))))
print("")
truthy(taps.smallestUsed >= 44, string.format("every gnome was planted or upgraded with its pad 44 px or more on screen (smallest %.1f)", taps.smallestUsed))
for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(string.format("gnome garden WALK: %d passed, %d failed", passed, failed))
