-- Lost & Found Depot — THE PLAYER'S PATH, walked in the built world, with the real HUD running.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       cd ../lost-found-depot && luau tests/walk.luau
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- What it does: a brand-new player joins on a phone-sized touch viewport, spawns, and plays one
-- full loop — the tutorial from the spawn pad, all 30 items of shift 1, the summary — then walks
-- to the locker, buys the cart upgrade, and plays the whole second loop (stage 2, torn tags) with
-- one deliberate misfile. Every answer is derived the way a player derives it: the rendered tag
-- text, the rendered memo board, the rendered bin signs, and the public manual. Every step the
-- HUD is read back: the hint line, the clock, the cleared counter, the toasts, the summary card.
-- It prints what happened in numbers.
--
-- Assertions here are the ones only a walk with the HUD can make (the hint says the right thing,
-- the summary card agrees with the server, no label shows "nil"); robloxemu/check_lostfounddepot
-- owns the rest.
--
-- One harness note: Roblox queues RemoteEvent traffic fired before a client connects, and the
-- server's first State push for a joining player can land before the HUD script has run. The
-- emulator does not queue, so the queue is replayed from the remote's own recording right after
-- the HUD loads — the server's real payloads, in order, nothing written by hand.

local Harness = require("../../robloxemu/emu/harness")
local bundle = require("../../robloxemu/build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-walk", viewport = { 800, 360 }, touch = true })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
-- Pin the per-session salt so a failing walk replays the same depot.
local realRandom = Random
Random = {
	new = function(seed)
		return realRandom.new(seed or 31337)
	end,
}

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(1)

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Rules = h:_require(h.ReplicatedStorage:FindFirstChild("Rules"))
local remotes = h.ReplicatedStorage:FindFirstChild("DepotRemotes")
local StateEvent, NoticeEvent = remotes.State, remotes.Notice
local SelectEvent = remotes.Select

local me = h:join("Walker", 424242)
h:advance(0.1)

-- the HUD, then the queued traffic it would have received
local okHud, hudErr = h:tryRun("client/Hud.client")
truthy(okHud, "the HUD loads" .. (if okHud then "" else ": " .. tostring(hudErr)))
for _, remote in { StateEvent, NoticeEvent } do
	for _, rec in remote:sentTo(me) do
		remote:FireClient(me, table.unpack(rec.args, 1, rec.args.n))
	end
end
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)

local root = me.PlayerGui.DepotHud.Root
local function hudText(path)
	local node = root
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node and node.Text or nil
end

--============================================================================ reading the world

local function state()
	local s = StateEvent:sentTo(me)
	return s[#s].args[1]
end
local notices = {}
NoticeEvent.OnClientEvent:Connect(function(n) table.insert(notices, n) end)

local bay = me.RespawnLocation.Parent
local ox = bay.BayPad.Position.X
local P = Vector3.new(ox, 3, 0)
local BIN_OF_NAME, LETTER_OF_NAME = {}, {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end

local function hrp() return me.Character.HumanoidRootPart end
local walked = 0
-- Straight lines at WalkSpeed, EXCEPT that nobody walks through the tray: a leg that crosses the
-- tray's footprint (x -8..8, z 3.5..9.5, grown by a 1.5-stud body radius) goes round its nearer
-- end. Still not physics — no acceleration, no collisions with crates — so every duration below is
-- a lower bound on a real player's.
local TRAY_X, TRAY_Z0, TRAY_Z1 = 8 + 1.5, 3.5 - 1.5, 9.5 + 1.5
local function crossesTray(a, b)
	for i = 0, 40 do
		local t = i / 40
		local x = a.X + (b.X - a.X) * t - ox
		local z = a.Z + (b.Z - a.Z) * t
		if math.abs(x) < TRAY_X and z > TRAY_Z0 and z < TRAY_Z1 then return true end
	end
	return false
end
local function walkTo(pos)
	local from = hrp().Position
	local d
	if crossesTray(from, pos) then
		local side = if (from.X + pos.X) / 2 - ox >= 0 then 1 else -1
		local nearZ = if from.Z > pos.Z then TRAY_Z1 else TRAY_Z0
		local farZ = if from.Z > pos.Z then TRAY_Z0 else TRAY_Z1
		local c1 = Vector3.new(ox + side * TRAY_X, 3, nearZ)
		local c2 = Vector3.new(ox + side * TRAY_X, 3, farZ)
		d = (c1 - from).Magnitude + (c2 - c1).Magnitude + (pos - c2).Magnitude
	else
		d = (from - pos).Magnitude
	end
	hrp().CFrame = CFrame.new(pos)
	h:advance(d / me.Character.Humanoid.WalkSpeed)
	walked += d
	return d
end
local function readTray()
	local out = {}
	for s = 1, 8 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		if slot.Tag.Enabled then
			-- the tap lands on the item itself, whose Model carries the ClickDetector (REVIEW-1 finding 6)
			table.insert(out, { slot = s, click = slot.Item.ClickDetector, line = (string.gsub(slot.Tag.TagLine.Text, "<[^>]*>", "")),
				name = slot.Tag.ItemName.Text })
		end
	end
	return out
end
local function readRules()
	local text = bay.MemoBoard.SignGui.Label.Text
	for _, memo in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, memo), 1, true) then return Rules.withMemo(Config, memo) end
	end
	return Rules.base(Config)
end
local function bins()
	local out = {}
	for k = 1, 6 do
		local m = bay:FindFirstChild("Bin_" .. k)
		out[BIN_OF_NAME[m.Sign.SignGui.Label.Text]] = m
	end
	return out
end
local function standFor(binModel)
	local base = binModel.Base.Position
	local flat = Vector3.new(base.X, 3, base.Z)
	return flat + (P - flat).Unit * 5
end
local function answerOf(entry)
	local mis = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
	if mis then return BIN_OF_NAME[mis] end
	return (Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], readRules()))
end

-- Pay as the design states it, written out here rather than asked of Economy: a first try pays
-- 10 + min(combo, 10), a re-sort pays 5, a misfile pays 0 and breaks the combo.
local function expectedPay(outcomes)
	local pay, combo = 0, 0
	for _, o in outcomes do
		if o == "first" then
			combo += 1
			pay += 10 + math.min(combo, 10)
		elseif o == "resort" then
			pay += 5
		else
			combo = 0
		end
	end
	return pay
end

local function playLoop(label, misfiles, startedAt)
	local outcomes = {}
	local trips, deposits, picks = 0, 0, 0
	local startWalked = walked
	local firstPickAt, endAt = startedAt, nil
	local maxCarried = 0
	local toastsSeen = {}
	local markNotices = #notices
	local misfiledSet = {}
	for _ = 1, 800 do
		local st = state()
		if st.shift.state == "SUMMARY" then
			endAt = h.scheduler:now()
			break
		end
		if #st.shift.carried == 0 then
			walkTo(P)
			local tray = readTray()
			local n = 0
			for _, t in tray do
				if n >= st.carry then break end
				t.click.MouseClick:Fire(me)
				n += 1
				picks += 1
				firstPickAt = firstPickAt or h.scheduler:now()
			end
			if n > 0 then trips += 1 end
			h:advance(0.35)
			maxCarried = math.max(maxCarried, #state().shift.carried)
		else
			local entry = st.shift.carried[1]
			local isMis = string.find(entry.tag, "MISFILED", 1, true) ~= nil
			local bin = answerOf(entry)
			local deliberate = false
			if misfiles > 0 and not isMis then
				for _, b in Config.Rules.Bins do
					if b ~= bin then bin = b break end
				end
				misfiles -= 1
				deliberate = true
			end
			walkTo(standFor(bins()[bin]))
			SelectEvent:simulateFireServer(me, 1)
			local before = state()
			bins()[bin].Base.Drop.Triggered:Fire(me)
			deposits += 1
			local after = state()
			local cleared = (after.shift and after.shift.cleared) or 0
			if after.shift.state == "SUMMARY" then cleared = after.shift.summary.sorted end
			if cleared > before.shift.cleared then
				table.insert(outcomes, if isMis then "resort" else "first")
			else
				table.insert(outcomes, "miss")
				truthy(deliberate, label .. ": only the deliberate deposit misfiled")
			end
		end
	end
	for i = markNotices + 1, #notices do table.insert(toastsSeen, notices[i]) end
	return {
		outcomes = outcomes, trips = trips, deposits = deposits, picks = picks, maxCarried = maxCarried,
		walked = walked - startWalked, seconds = (endAt or h.scheduler:now()) - (firstPickAt or 0), toasts = toastsSeen,
	}
end

--============================================================================ join -> first frame

local lines = {}
local function say(fmt, ...) table.insert(lines, string.format(fmt, ...)) print(string.format(fmt, ...)) end

do
	local st = state()
	local pad = bay.BayPad
	local r = hrp().Position
	-- No load time is printed: the emulator's DataStore never yields, so it would be a fiction.
	say("JOIN   bay %s, landed %.2f studs from the pad centre (xz) at y %.2f, on the pad (top y %.1f)",
		bay.Name, math.sqrt((r.X - pad.Position.X) ^ 2 + (r.Z - pad.Position.Z) ^ 2), r.Y, pad.Position.Y + pad.Size.Y / 2)
	eq(st.shift.state, "ARMED", "the first shift is armed")
	eq(hudText("ClockPanel.Clock"), "5:30", "the HUD clock reads 5:30")
	eq(hudText("ClockPanel.ClockSub"), "starts when you pick something up", "... and says it has not started")
	eq(hudText("Hint"), "Tap the Teddy Bear on the tray.", "the hint names the first action")
	eq(root.Loading.Visible, false, "the loading text is gone once the profile loaded")
end

--============================================================================ loop 1

local cashLog = {}
local loop1Start
do
	-- The tutorial items by the slots the server's payload names (a random item on the same tray
	-- can also be a Teddy Bear or a Phone).
	local function tutorialItem(name)
		local t = state().shift.tutorial
		assert(t and t.item == name and t.step == "pick" and t.slot, "the tutorial is not pointing at " .. name)
		for _, it in readTray() do
			if it.slot == t.slot then return it end
		end
	end
	local teddy = tutorialItem("Teddy Bear")
	local fromPad = (hrp().Position - bay:FindFirstChild("Slot_" .. teddy.slot).Position).Magnitude
	teddy.click.MouseClick:Fire(me)
	loop1Start = h.scheduler:now()
	h:advance(0.35)
	say("TAP    the Teddy Bear from the spawn pad, %.2f studs away (reach 12 + slack 2): carried %d", fromPad,
		#state().shift.carried)
	eq(#state().shift.carried, 1, "the tutorial item is picked without a step")
	-- a phone has no E key: the hint says how a phone deposits (REVIEW-1 pass 3, U4)
	eq(hudText("Hint"), "T means TOYS. Walk to the TOYS bin and tap Drop.", "the hint says where it goes, and how a phone drops it")
	eq(me.PlayerGui.TutorialBinMarker.Enabled, true, "a DROP HERE marker is over a bin")
	eq(me.PlayerGui.TutorialBinMarker.ResetOnSpawn, false, "... and survives a respawn (the HUD script runs once)")
	eq(me.PlayerGui.TutorialBinMarker.Adornee.Parent.Sign.SignGui.Label.Text, "TOYS", "... the TOYS bin")

	-- A new player has TWO hands and the Phone sits next to the Teddy: they take it too. A pick does
	-- not move the selection (REVIEW-1 pass 3, U2), so the Teddy stays selected, and the hint, which
	-- follows the selection (REVIEW-1 R2-2), keeps pointing at TOYS.
	-- (the Phone's slot is the fixed, public Config.Shift.Tutorial[2].slot)
	local phone
	for _, it in readTray() do
		if it.slot == Config.Shift.Tutorial[2].slot then phone = it end
	end
	eq(phone and phone.name, "Phone", "the tutorial Phone sits in its fixed slot")
	local phoneFromPad = (hrp().Position - bay:FindFirstChild("Slot_" .. phone.slot).Position).Magnitude
	phone.click.MouseClick:Fire(me)
	h:advance(0.35)
	local st = state()
	say("TAP    the Phone too, %.2f studs away, no step: carried %d, selected %s; hint %q", phoneFromPad, #st.shift.carried,
		st.shift.carried[st.shift.selected].name, hudText("Hint"))
	eq(#st.shift.carried, 2, "both tutorial items are in hand, picked from the pad")
	eq(hudText("Hint"), "T means TOYS. Walk to the TOYS bin and tap Drop.", "the hint stays with the selected Teddy")
	eq(me.PlayerGui.TutorialBinMarker.Adornee.Parent.Sign.SignGui.Label.Text, "TOYS", "... and so does the marker")
	eq(bins().TOYS.Base.Drop.ActionText, "Drop Teddy Bear", "the Drop prompt says what E drops")
	local d1 = walkTo(standFor(bins().TOYS))
	bins().TOYS.Base.Drop.Triggered:Fire(me)
	say("SORT   walked %.1f studs to TOYS as the hint said, pressed Drop: cash %d, misfiles %d, %s, toast %q", d1,
		state().cash, state().shift.misfiles, hudText("ClockPanel.Cleared"), hudText("Toast"))
	eq(state().shift.misfiles, 0, "following the hint filed the Teddy correctly")
	eq(hudText("Toast"), "+11", "the toast shows +11")
	eq(hudText("Hint"), "Read the TAG, not the phone: K means KEYS & WALLETS. Walk to that bin and tap Drop.",
		"the hint moves on to the Phone, now selected")
	eq(me.PlayerGui.TutorialBinMarker.Adornee.Parent.Sign.SignGui.Label.Text, "KEYS & WALLETS", "... and the marker moves to KEYS & WALLETS")
	local d2 = walkTo(standFor(bins().KEYS))
	bins().KEYS.Base.Drop.Triggered:Fire(me)
	say("SORT   walked %.1f studs to KEYS & WALLETS, pressed Drop: cash %d, misfiles %d, %s, toast %q", d2, state().cash,
		state().shift.misfiles, hudText("ClockPanel.Cleared"), hudText("Toast"))
	eq(hudText("ClockPanel.Cleared"), "CLEARED 2/30", "the HUD counts both tutorial sorts")
	eq(state().shift.misfiles, 0, "the tutorial ends with zero misfiles")
	eq(hudText("Toast"), "Tags beat looks. The rest is up to you - every rule is in MANUAL.", "the tutorial's closing toast shows")
	eq(hudText("Hint"), "", "the hint line clears after the tutorial")
end

local loop1 = playLoop("loop 1", 0, loop1Start)
do
	local st = state()
	local s = st.shift.summary
	-- trips, picks and studs include the tutorial trip (2 picks, 2 sorts) made before playLoop started counting
	say("LOOP 1 %d/%d sorted, %d misfiles, %s, %.1f s from the first pick to the summary, %d trips, %d picks, carried at most %d, %.0f studs walked",
		s.sorted, s.total, s.misfiles, if s.perfect then "PERFECT" else "not perfect", loop1.seconds, loop1.trips + 1,
		loop1.picks + 2, math.max(2, loop1.maxCarried), walked)
	say("       server's own shift time: %d s (the summary's best)", s.seconds)
	-- the two tutorial sorts (+11, +12) happened before playLoop started recording
	local outcomes = { "first", "first" }
	for _, o in loop1.outcomes do table.insert(outcomes, o) end
	local pay = expectedPay(outcomes)
	eq(s.pay, pay + (if s.perfect then 100 else 0), "the summary's pay matches the pay rule over the real deposit sequence")
	eq(st.cash, s.pay, "cash equals the shift's pay")
	eq(s.sorted, 30, "loop 1 sorts all 30")
	eq(root.SummaryCard.Visible, true, "the summary card is up")
	say("CARD   %q / %s", root.SummaryCard.Title.Text, (string.gsub(root.SummaryCard.Body.Text, "\n", " | ")))
	truthy(string.find(root.SummaryCard.Body.Text, "Sorted 30 / 30", 1, true) ~= nil, "the card says Sorted 30 / 30")
	table.insert(cashLog, st.cash)
end

--============================================================================ between loops: the locker

do
	local st = state()
	local cash = st.cash
	local d = walkTo(Vector3.new(ox + 12, 3, 13))
	bay.Locker.Cart.Triggered:Fire(me)
	local after = state()
	say("LOCKER walked %.1f studs, bought the cart: carry %d -> %d, cash %d -> %d, toast %q", d, st.carry, after.carry,
		cash, after.cash, hudText("Toast"))
	eq(after.carry, 3, "the cart upgrade took")
	-- the HUD's UPGRADES drawer shows the next price
	eq(root.Toggles.Toggle_upgrades.Text, "UPGRADES", "the drawer toggle reads UPGRADES")
	root.Toggles.Toggle_upgrades.Activated:Fire()
	say("DRAWER UPGRADES: %q / %q", hudText("UpgradesDrawer.CartRow"), hudText("UpgradesDrawer.ShoesRow"))
	eq(hudText("UpgradesDrawer.CartRow"), "CART   carry 3 -> 4 for 800", "the UPGRADES drawer shows the next cart price")
	root.Toggles.Toggle_upgrades.Activated:Fire()
end

--============================================================================ loop 2

do
	for _ = 1, 20 do
		if state().shift.state == "ARMED" then break end
		h:advance(0.5)
	end
	local st = state()
	eq(st.shift.state, "ARMED", "loop 2 arms")
	eq(st.stage, 2, "loop 2 is stage 2")
	eq(root.ManualDrawer.Visible, true, "the MANUAL drawer opened by itself for the new layer")
	local newLines = 0
	for _, c in root.ManualDrawer:GetChildren() do
		if c.ClassName == "TextLabel" and string.sub(c.Text, 1, 3) == "NEW" then newLines += 1 end
	end
	say("ARM    shift 2 (stage 2): the manual drawer opened itself with %d lines marked NEW", newLines)
	-- 4 torn-tag lines + the CATALOG heading + one catalog line per letter (REVIEW-1 R2-7)
	eq(newLines, 4 + 1 + #Config.Rules.Letters, "the torn-tag lines and the catalog are marked NEW")
	root.Toggles.Toggle_manual.Activated:Fire()
	eq(root.ManualDrawer.Visible, false, "tapping MANUAL closes it")
end

local tornSeen = 0
do
	-- count torn tags visible on the tray before starting
	for _, t in readTray() do
		if string.find(t.line, "?", 1, true) then tornSeen += 1 end
	end
end
local loop2 = playLoop("loop 2", 1)
do
	local st = state()
	local s = st.shift.summary
	say("LOOP 2 %d/%d sorted, %d misfile, %s, %.1f s from the first pick to the summary, %d trips, %d picks, carried at most %d, %.0f studs walked",
		s.sorted, s.total, s.misfiles, if s.perfect then "PERFECT" else "not perfect", loop2.seconds, loop2.trips,
		loop2.picks, loop2.maxCarried, loop2.walked)
	local firstTries, resorts, misses = 0, 0, 0
	for _, o in loop2.outcomes do
		if o == "first" then firstTries += 1 elseif o == "resort" then resorts += 1 else misses += 1 end
	end
	say("       deposits: %d first tries, %d re-sort, %d misfile; torn tags on the opening tray: %d", firstTries, resorts,
		misses, tornSeen)
	local mis
	for _, n in loop2.toasts do
		if n.kind == "misfile" then mis = n end
	end
	say("       misfile toast: %q", mis and mis.text or "none")
	truthy(mis ~= nil and string.sub(mis.text, 1, 6) == "-8 s. ", "the misfile toast leads with the penalty")
	eq(misses, 1, "exactly one misfile")
	eq(resorts, 1, "the misfiled item was re-sorted once")
	eq(s.pay, expectedPay(loop2.outcomes) + (if s.perfect then 100 else 0), "loop 2 pay matches the pay rule")
	eq(st.cash, cashLog[1] - 250 + s.pay, "cash = loop 1 pay - cart + loop 2 pay")
	eq(st.backlog, 30 + firstTries, "backlog counts first tries only")
	eq(loop2.maxCarried, 3, "the upgraded cart carried 3")
	table.insert(cashLog, st.cash)
	say("TOTAL  cash %d, backlog %d / %d, shifts %d, perfects %d, best Perfect %d s, %.0f studs walked in all",
		st.cash, st.backlog, st.backlogSize, st.shifts, st.perfects, st.best, walked)
end

--============================================================================ what the HUD showed, overall

do
	local nils, unseen = 0, 0
	local ALLOWED = { [0x2014] = true, [0x2026] = true, [0x2605] = true, [0x1F512] = true, [0xFE0F] = true }
	for _, d in me.PlayerGui:GetDescendants() do
		local cls = d.ClassName
		if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then
			if string.find(d.Text, "nil", 1, true) then
				nils += 1
				print("  'nil' on screen: " .. d:GetFullName() .. " = " .. d.Text)
			end
			for _, cp in utf8.codes(d.Text) do
				if cp >= 0x2000 and not ALLOWED[cp] then unseen += 1 end
			end
		end
	end
	eq(nils, 0, "no HUD label says nil")
	eq(unseen, 0, "every HUD glyph is ASCII, Latin-1 or one of the four photographed glyphs")
	eq(#h:errors(), 0, "no thread died on the server or the client")
	for _, e in h:errors() do print("scheduler error: " .. e) end
end

print(string.format("walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed") end
