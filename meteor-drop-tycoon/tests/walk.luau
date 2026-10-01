-- Meteor Drop Tycoon — THE PLAYER'S PATH, walked in the built world, printed in numbers.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       cd ../meteor-drop-tycoon && luau tests/walk.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green tests are not a working game (this repo once shipped 166 green tests with an unreachable core loop).
-- This file is somebody playing: it joins, lands on its pad, walks to meteors the way a normal player does
-- (it reacts 0.8 s after a meteor appears and walks at 85% of WalkSpeed, the model's `normal` profile),
-- reads the HUD's own labels, and every 20 s, when the Upgrades button shows its star, taps it open and taps the
-- starred row's BUY button while that button is gold (the HUD's own "affordable" colour). It plays
--   loop 1: join -> first meteor -> pickup -> melt -> first purchase (the Beacon),
--   loop 2: the faster rain -> more pickups -> the second purchase,
-- and on through the first Smelter and the first Collector until the dish makes a catch, then on to Beacon 22
-- and the Falling Star (the brag moment), which it catches; then it leaves, rejoins with a fresh HUD, and plays
-- one more loop on the saved profile. Every step prints what happened, in numbers.
-- It asserts only what a player would notice was broken.

local Harness = require("../../robloxemu/emu/harness")
local h = Harness.new({ bundle = require("../../robloxemu/build/meteor-drop-tycoon"), name = "meteor-drop-tycoon-walk",
	viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("MeteorRemotes")
local Buy, State, FxR, Toast = remotes.Buy, remotes.State, remotes.Fx, remotes.Toast
local UID = 31415

local plr, hrp, hum, plot, t0
local function join(first)
	h.game:GetService("RunService"):setIsServer(false)
	plr = h:join("Walker", UID)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Grass
	hum.MoveDirection = Vector3.new(0, 0, 1)
	plot = plr.RespawnLocation.Parent
	-- every join runs the HUD again, as a new Roblox client does (Sky.client once: it builds client-only sky parts)
	assert(h:tryRun("client/Hud.client"))
	if first then
		assert(h:tryRun("client/Sky.client"))
	end
	t0 = h.scheduler:now()
end
local function now() return h.scheduler:now() - t0 end
local function st()
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local function gui(path)
	local node = plr.PlayerGui
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
local function hint()
	local p = gui("MeteorHud.Root.HintPanel")
	return if p and p.Visible then p.HintText.Text else "(none)"
end
local function chip()
	local c = gui("MeteorSky.Root.BandChip.ChipText")
	return c and c.Text or "?"
end
local function flat(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) end

local counts = { hand = 0, dish = 0, burn = 0, bounce = 0, buys = 0, hudBuys = 0 }
local starFallAt, starCaughtAt, starFalls = nil, nil, 0
FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "zip" then counts.hand += 1
	elseif ev.kind == "dish" then counts.dish += 1
	elseif ev.kind == "burn" then counts.burn += 1
	elseif ev.kind == "bounce" then counts.bounce += 1
	elseif ev.kind == "starFalling" then
		starFalls += 1
		starFallAt = starFallAt or now()
	elseif ev.kind == "starCaught" then
		starCaughtAt = starCaughtAt or now()
	end
end)

-- REVIEW-1: from join to the star, how often the hopper is full, what the dish loses, and whether a "Hopper
-- full!" refusal ever sends the player to the Smelter while the HUD's star is on another machine
local preStar = { samples = 0, full = 0, fullToasts = 0, contradictions = 0, examples = {}, starMoves = 0, lastBest = nil }
Toast.OnClientEvent:Connect(function(text)
	if type(text) ~= "string" or string.find(text, "Hopper full", 1, true) == nil then return end
	local sent = State:sentTo(plr)
	local s = sent[#sent] and sent[#sent].args[1]
	if s == nil then return end
	preStar.fullToasts += 1
	local namesSmelter = string.find(text, "Smelter", 1, true) ~= nil
	if namesSmelter ~= (s.best == "smelter") then
		preStar.contradictions += 1
		if #preStar.examples < 2 then table.insert(preStar.examples, string.format("%q with the star on the %s", text, tostring(s.best))) end
	end
end)

-- the normal player, 0.1 s at a time
local target, seenAt, lastShop = nil, {}, -math.huge
local hintsSeen = {} -- every hint text the HUD showed, and when first
local firstBuyOf, log = {}, {}
local KINDS = { "beacon", "collector", "smelter" }
local function isColour(c, r, g, b)
	return math.abs(c.R * 255 - r) < 0.5 and math.abs(c.G * 255 - g) < 0.5 and math.abs(c.B * 255 - b) < 0.5
end
-- The shop, through the HUD only: the Upgrades button shows "★" when the starred machine is affordable; the
-- starred row's name starts with "★ " and its BUY button is gold (200, 150, 40) while the wallet covers it.
-- A tap counts as a HUD purchase when the server's own level for that machine moved by exactly one.
local function hudShop()
	local root = gui("MeteorHud.Root")
	local upBtn = root.UpgradeSlot.UpgradeButton
	if string.find(upBtn.Text, "★", 1, true) == nil then return end
	upBtn.Activated:Fire()
	h:advance(0.3)
	local panel = root.UpgradePanel
	local guard = 0
	while panel.Visible and guard < 20 do
		guard += 1
		local row, kind = nil, nil
		for _, k in KINDS do
			local r = panel:FindFirstChild("Row_" .. k)
			if r and string.sub(r.NameText.Text, 1, #"★ ") == "★ " then row, kind = r, k end
		end
		if row == nil or not isColour(row.BuyButton.BackgroundColor3, 200, 150, 40) then break end
		-- what the HUD's hint says at this tap: a star that moved to the Collector since the last step (or after
		-- this visit's previous tap) shows its hint now, and this purchase ends that tutorial step. REVIEW-1's sweep
		-- caught the walk sampling the hint only between shop visits (about once in 20 walks).
		local tapHint = hint()
		if hintsSeen[tapHint] == nil then hintsSeen[tapHint] = now() end
		local before = st()
		row.BuyButton.Activated:Fire()
		h:advance(0.3) -- a person taps about three times a second
		local after = st()
		counts.buys += 1
		if after[kind] == before[kind] + 1 then counts.hudBuys += 1 end
		if firstBuyOf[kind] == nil then
			firstBuyOf[kind] = now()
			table.insert(log, string.format("  %6.1f s  first %s bought with the HUD's BUY button (Stardust %.1f -> %.1f); hint: %s",
				now(), kind, before.stardust, after.stardust, hint()))
		end
	end
	if panel.Visible then upBtn.Activated:Fire() end -- close the panel again
end
local function step()
	local s = st()
	-- shop every 20 s, through the HUD
	if s and s.loaded and now() - lastShop >= 20 then
		lastShop = now()
		hudShop()
	end
	-- choose: the Falling Star, then a legendary or epic, then the nearest meteor lying on the plot
	local folder = plot.Meteors
	for _, m in folder:GetChildren() do
		if seenAt[m] == nil then seenAt[m] = now() end
	end
	if target == nil or target.Parent == nil then
		target = nil
		local best, bestScore = nil, math.huge
		for _, m in folder:GetChildren() do
			local name = m.Name
			if (string.sub(name, 1, 6) == "Meteor" or name == "FallingStar") and now() - seenAt[m] >= 0.8 then
				local pri = if name == "FallingStar" then -1000 elseif (name == "Meteor_Legendary" or name == "Meteor_Epic") then -40 else 0
				local d = flat(m.Position, hrp.Position) + pri
				if d < bestScore then best, bestScore = m, d end
			end
		end
		target = best
	end
	if target then
		local p = hrp.Position
		local dx, dz = target.Position.X - p.X, target.Position.Z - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 1 then
			local stepLen = math.min(d, 16 * 0.85 * 0.1)
			hrp.CFrame = CFrame.new(p.X + dx / d * stepLen, p.Y, p.Z + dz / d * stepLen)
		end
	end
	h.game:GetService("RunService").RenderStepped:Fire(0.1)
	h:advance(0.1)
	local s1 = st()
	if s1 and s1.loaded and starCaughtAt == nil then
		preStar.samples += 1
		if s1.hopperFull then preStar.full += 1 end
		if preStar.lastBest ~= nil and s1.best ~= preStar.lastBest then preStar.starMoves += 1 end
		preStar.lastBest = s1.best
	end
	local shownHint = hint()
	if hintsSeen[shownHint] == nil then hintsSeen[shownHint] = now() end
end

--============================================================================ join
join(true)
h:advance(0.3) -- the HUD's first State: the server pushes it at most every 0.25 s
print("== join")
print(string.format("  landed %.1f studs from the own arrival pad; hint: %s", flat(hrp.Position, plr.RespawnLocation.Position), hint()))
print("  band chip: " .. chip())
truthy(flat(hrp.Position, plr.RespawnLocation.Position) <= 4, "the walker lands on its own pad")
truthy(string.find(hint(), "walk over it", 1, true) ~= nil, "the first hint names the core action")

--============================================================================ loop 1: to the first purchase
print("== loop 1: join -> first pickup -> melt -> first purchase")
local firstPickupAt, firstStardustAt, affordableAt = nil, nil, nil
while firstBuyOf.beacon == nil and now() < 120 do
	step()
	if affordableAt == nil and st() and st().stardust >= st().prices.beacon then
		affordableAt = now()
		print(string.format("  %6.1f s  the first Beacon (%d Stardust) is affordable; the Upgrades button reads: %s", now(),
			st().prices.beacon, gui("MeteorHud.Root.UpgradeSlot.UpgradeButton").Text))
	end
	if firstPickupAt == nil and counts.hand > 0 then
		firstPickupAt = now()
		h:advance(0.3)
		print(string.format("  %6.1f s  first pickup (hopper %.2f of %.1f ore); hint now: %s", firstPickupAt, st().hopper, st().hopperCap, hint()))
	end
	if firstStardustAt == nil and st() and st().stardust >= 1 then
		firstStardustAt = now()
		print(string.format("  %6.1f s  the Smelter has melted the first whole Stardust", now()))
	end
end
for _, line in log do print(line) end
table.clear(log)
truthy(firstPickupAt ~= nil and firstPickupAt <= 5, string.format("the core action happens within 5 s of joining (%.1f s)", firstPickupAt or -1))
-- The walker opens the shop every 20 s (the model's normal player), so the purchase lands on the first visit
-- after the price is reached; DESIGN 14 puts the price in reach at about 30 s.
truthy(affordableAt ~= nil and affordableAt <= 45, string.format("the first Beacon is affordable inside 45 s (%.1f s)", affordableAt or -1))
truthy(firstBuyOf.beacon ~= nil and firstBuyOf.beacon <= (affordableAt or 0) + 20.5,
	string.format("and it is the first purchase, on the next shop visit (%.1f s)", firstBuyOf.beacon or -1))
print(string.format("  loop 1 closed at %.1f s: %d pickups, Beacon %d, Stardust %.1f; band chip: %s", now(), counts.hand, st().beacon, st().stardust, chip()))

--============================================================================ loop 2: the next purchase on the faster rain
print("== loop 2: the next purchase")
local buys1, hand1 = counts.buys, counts.hand
local loop2Start = now()
while counts.buys == buys1 and now() - loop2Start < 180 do
	step()
end
for _, line in log do print(line) end
table.clear(log)
local s2 = st()
print(string.format("  loop 2 closed after %.1f s: %d more pickups, now Beacon %d, Smelter %d, Collector %d, Stardust %.1f",
	now() - loop2Start, counts.hand - hand1, s2.beacon, s2.smelter, s2.collector, s2.stardust))
truthy(counts.buys > buys1, "a second purchase follows")

--============================================================================ on to the Collector and the dish
print("== on to the Collector")
local marks = { 120, 300, 600 }
local nextMark = 1
local dish0 = counts.dish
while (firstBuyOf.collector == nil or counts.dish == dish0) and now() < 25 * 60 do
	step()
	if nextMark <= #marks and now() >= marks[nextMark] then
		local s = st()
		print(string.format("  %6.1f s  Beacon %d, Smelter %d, Collector %d; Stardust %s, rate %.0f/min; hopper %.0f%%; hand %d, dish %d, burned %d; chip: %s",
			now(), s.beacon, s.smelter, s.collector, tostring(math.floor(s.stardust)), s.rate or 0, 100 * s.hopper / s.hopperCap, counts.hand, counts.dish, counts.burn, chip()))
		nextMark += 1
	end
end
for _, line in log do print(line) end
table.clear(log)
local s3 = st()
print(string.format("  %6.1f s  first dish catch; Beacon %d, Smelter %d, Collector %d, Stardust %.0f; hand %d, dish %d, burned %d, bounced %d",
	now(), s3.beacon, s3.smelter, s3.collector, s3.stardust, counts.hand, counts.dish, counts.burn, counts.bounce))
print(string.format("  first Beacon %.2f min, first Smelter %.2f min, first Collector %.2f min (DESIGN [M10]: 0.67, 2.34, 11.02)",
	(firstBuyOf.beacon or 0) / 60, (firstBuyOf.smelter or 0) / 60, (firstBuyOf.collector or 0) / 60))
truthy(firstBuyOf.smelter ~= nil, "the star sends the walker to the Smelter")
truthy(firstBuyOf.collector ~= nil, "and later to the Collector")
truthy(counts.dish > dish0, "and the dish catches with no walking")
local collectorHint = "The Collector catches meteors for you. It sleeps if you stop collecting."
print(string.format("  the Collector hint first showed at %.1f s (the Collector was bought at %.1f s)",
	hintsSeen[collectorHint] or -1, firstBuyOf.collector or -1))
truthy(hintsSeen[collectorHint] ~= nil and hintsSeen[collectorHint] <= (firstBuyOf.collector or 0),
	"the HUD explained the Collector before the walker bought it")
-- DESIGN [M3] says a normal follower loses 0.000 of its ORE (median over 240 min) to burning or bouncing. This
-- walker counts METEORS: while its hopper is full its pickups are refused and a few can pile up to the cap.
local fell = counts.hand + counts.dish + counts.burn + counts.bounce
print(string.format("  lost to a full plot or a full hopper: %d burned + %d bounced of %d meteors (%.1f%%)",
	counts.burn, counts.bounce, fell, 100 * (counts.burn + counts.bounce) / math.max(fell, 1)))
-- measured over 20 runs on 2026-10-01: nothing lost in 11, 0.6-1.9% in 7, 4.8% and 7.5% in the last two (CLAUDE.md,
-- "Things the suite does not see"); the bound is there to catch a broken loop, which loses far more
truthy((counts.burn + counts.bounce) / math.max(fell, 1) < 0.10, "a normal walker loses under 10% of the meteors that fall")

--============================================================================ the brag moment, played
print("== on to the Falling Star")
local starMarks = { 15 * 60, 20 * 60, 25 * 60, 30 * 60 }
local nextStarMark = 1
local starBeacon = nil
while starCaughtAt == nil and now() < 50 * 60 do
	step()
	if nextStarMark <= #starMarks and now() >= starMarks[nextStarMark] then
		local s = st()
		print(string.format("  %6.1f min  Beacon %d, Smelter %d, Collector %d; Stardust %s, rate %s/min; hand %d, dish %d; chip: %s",
			now() / 60, s.beacon, s.smelter, s.collector, tostring(math.floor(s.stardust)), tostring(math.floor(s.rate or 0)), counts.hand, counts.dish, chip()))
		nextStarMark += 1
	end
	if starFallAt ~= nil and starBeacon == nil then
		starBeacon = st().beacon
		local tt = gui("MeteorHud.Root.ToastPanel.ToastText")
		print(string.format("  %6.1f min  Beacon %d: the Falling Star falls (toast: %s)", starFallAt / 60, starBeacon, tt and tt.Text or "?"))
	end
end
for _, line in log do print(line) end
table.clear(log)
h:advance(0.3)
local card = gui("MeteorHud.Root.StarCard")
local crown = plot:FindFirstChild("Beacon") and plot.Beacon:FindFirstChild("Crown")
local sStar = st()
print(string.format("  %6.1f min  caught it %.1f s after it fell; Stardust %s; the card reads: %s; chip: %s; gold crown on the Beacon: %s",
	(starCaughtAt or -60) / 60, (starCaughtAt or 0) - (starFallAt or 0), tostring(math.floor(sStar.stardust)),
	card and card.Visible and card.Text or "(no card)", chip(), tostring(crown ~= nil)))
print(string.format("  purchases so far: %d, %d of them taps on the HUD's BUY button", counts.buys, counts.hudBuys))
truthy(starFalls == 1 and starBeacon == 22, string.format("the star falls once, at Beacon 22 (%d time(s), Beacon %s)", starFalls, tostring(starBeacon)))
truthy(card ~= nil and card.Visible and string.find(card.Text, "FALLING STAR", 1, true) ~= nil, "the HUD shows the brag card")
truthy(crown ~= nil, "the gold crown sits on the Beacon, where everyone can see it")
truthy(string.find(chip(), "Starfall", 1, true) ~= nil, "the sky over the plot is the Starfall band")
truthy(counts.buys > 0 and counts.hudBuys == counts.buys,
	string.format("every purchase was a tap on the HUD's own BUY button (%d of %d)", counts.hudBuys, counts.buys))
truthy(starCaughtAt ~= nil and starCaughtAt >= 30 * 60 and starCaughtAt <= 45 * 60,
	string.format("the walker catches the Falling Star between 30 and 45 min (%.1f min)", (starCaughtAt or -60) / 60))
local fullShare = preStar.full / math.max(1, preStar.samples)
local bounceShare = counts.bounce / math.max(1, counts.dish + counts.bounce)
print(string.format("  join to the star: hopper full %.1f%% of the time; the dish caught %d and bounced %d (%.1f%%); %d \"Hopper full\" refusals, %d naming the Smelter while the star was elsewhere or the reverse %s",
	100 * fullShare, counts.dish, counts.bounce, 100 * bounceShare, preStar.fullToasts, preStar.contradictions, table.concat(preStar.examples, "; ")))
print(string.format("  the HUD's star moved %d times on the way (%.2f a minute; a purchase moves it too)",
	preStar.starMoves, preStar.starMoves / math.max(1, preStar.samples * 0.1 / 60)))
-- The full and bounced shares are PRINTED, not asserted: one walk is one draw, and the ranges overlap. Measured
-- 2026-10-01: the shipped star before REVIEW-1, 9 walks, full 8.4-32.5% and bounced 14.7-45.1%; after it, 40 walks,
-- full up to 20.2% and bounced up to 31.8%. A bound loose enough never to fail on the fixed game could not tell the two
-- apart. tests/Pacing.spec.luau asserts them on 20 fixed seeds (full <= 8%, lost <= 8%, medians). What the walk
-- asserts is exact: no "Hopper full!" refusal contradicts the star (19-64 per walk did before REVIEW-1, 0 since).
truthy(preStar.contradictions == 0, string.format("no \"Hopper full!\" refusal contradicts the HUD's star (%d of %d)", preStar.contradictions, preStar.fullToasts))

--============================================================================ leave, rejoin, one more loop
print("== leave and rejoin")
local before = st()
local fallsBefore = starFalls -- BEFORE the leave: a star re-granted on the rejoin must be counted
h:leave(plr)
h:advance(2)
join(false)
h:advance(0.5)
local after = st()
print(string.format("  saved and restored: Beacon %d -> %d, Smelter %d -> %d, Collector %d -> %d, Stardust %.1f -> %.1f; hint: %s",
	before.beacon, after.beacon, before.smelter, after.smelter, before.collector, after.collector, before.stardust, after.stardust, hint()))
truthy(after.beacon == before.beacon and after.collector == before.collector and after.smelter == before.smelter, "the rejoin restores every machine")
local wallet = gui("MeteorHud.Root.WalletPanel.StardustText")
truthy(wallet ~= nil and wallet.Text == "⭐ " .. require("../src/shared/Economy").short(after.stardust),
	"the rejoined player's own HUD shows the restored Stardust (" .. (wallet and wallet.Text or "no HUD") .. ")")
local buysR, handR = counts.buys, counts.hand
local rStart = now()
lastShop = -math.huge
while (counts.buys == buysR or counts.hand == handR) and now() - rStart < 300 do
	step()
end
for _, line in log do print(line) end
print(string.format("  the second session's first loop: %d pickups and %d purchase(s) in %.1f s; Beacon %d",
	counts.hand - handR, counts.buys - buysR, now() - rStart, st().beacon))
truthy(counts.hand > handR and counts.buys > buysR, "the loop runs again after a rejoin")
truthy(starFalls == fallsBefore and st().star == 2, "a caught Falling Star never falls again after a rejoin")

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	failed += 1
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
