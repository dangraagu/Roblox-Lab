-- Lost & Found Depot — a new player's first minute, and what pressing E actually drops.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_firstmin.luau
--
-- WHY THIS FILE EXISTS (REVIEW-1 pass 3, the player-path reviewer). Every gate before it deposited
-- the way its author thinks: Select(1), then E. None dropped the tutorial Phone in the wrong bin, none
-- pressed Put back on the spawn pad, and none played without tapping the hotbar. What that hid:
--   U1  a misfiled or put-back item went to the FRONT OF THE CART whenever the tray was full (the
--       0.3 s refill keeps it full), so the tutorial Phone vanished; the hint kept asking for it with
--       no TAP HERE marker, and a random Phone on the same tray (32% of first shifts) was taken for it:
--       a second -8 s and "T goes to TOYS", against what the hint had just taught;
--   U2  a pick made the NEW item the selected one and a deposit made the FIRST one selected, and
--       nothing on screen said which item E drops: a player who took the item they picked first to
--       its bin misfiled 36% of deposits at carry 2 (136 s of penalties, 41% of the clock);
--   U3  DESIGN.md and the README promise a misfile goes back to the tray; with a full tray it did not;
--   U4  on a phone, the tutorial said "press E" and "PRESS E HERE";
--   U6  the design's deposit stamp, pulsing bin light and pulsing MANUAL button did not exist.
--
-- Part A runs server-only players (several bays at once). Part B is one player with the real HUD on
-- an 800 x 360 touch screen; it runs after every Part A player has left, because the emulator hands
-- a FireClient payload to every client handler whoever it was addressed to.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local W_, H_ = 800, 360
local h = Harness.new({ bundle = bundle, name = "lost-found-depot-firstmin", viewport = { W_, H_ }, touch = true })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
do -- every unseeded Random gets its own pinned seed, so a failure replays
	local realRandom = Random
	local unseeded = 0
	Random = {
		new = function(seed)
			if seed == nil then
				unseeded += 1
				return realRandom.new(5150 + unseeded * 6143)
			end
			return realRandom.new(seed)
		end,
	}
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("LostFoundDepot_v1")
local function veteran(uid, cartLevel)
	store:SetAsync("u_" .. uid, { data = { v = 1, cash = 0, cartLevel = cartLevel, shoesLevel = 3, shifts = 5, perfects = 0,
		backlog = 100, bestPerfectSeconds = 0, endingSeen = false, redeemed = {} } })
end
for i, level in { 0, 1, 3 } do veteran(7200 + i, level) end
veteran(7300, 2)

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot firstmin: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Rules = h:_require(h.ReplicatedStorage:FindFirstChild("Rules"))
local remotes = h.ReplicatedStorage:FindFirstChild("DepotRemotes")
local StateEvent, NoticeEvent, SelectEvent = remotes.State, remotes.Notice, remotes.Select

--============================================================================ helpers

local BIN_OF_NAME, LETTER_OF_NAME = {}, {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end

local function state(p) local s = StateEvent:sentTo(p) return s[#s] and s[#s].args[1] end
local function bayOf(p) return p.RespawnLocation.Parent end
local function hrp(p) return p.Character.HumanoidRootPart end
local function W(bay, x, y, z) return Vector3.new(bay.BayPad.Position.X + x, y, z) end
local function walkTo(p, pos)
	local d = (hrp(p).Position - pos).Magnitude
	hrp(p).CFrame = CFrame.new(pos)
	h:advance(d / p.Character.Humanoid.WalkSpeed)
end
local function strip(t) return (string.gsub(t, "<[^>]*>", "")) end
local function readTray(bay)
	local out = {}
	for s = 1, Config.Shift.TraySlots do
		local slot = bay:FindFirstChild("Slot_" .. s)
		if slot.Tag.Enabled and slot:FindFirstChild("Item") then
			table.insert(out, { slot = s, click = slot.Item.ClickDetector, line = strip(slot.Tag.TagLine.Text), name = slot.Tag.ItemName.Text })
		end
	end
	return out
end
local function onTray(bay, name, line)
	for _, it in readTray(bay) do
		if it.name == name and it.line == line then return it.slot end
	end
	return nil
end
local function readRules(bay)
	local text = bay.MemoBoard.SignGui.Label.Text
	for _, m in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, m), 1, true) then return Rules.withMemo(Config, m) end
	end
	return Rules.base(Config)
end
local function bins(bay)
	local out = {}
	for k = 1, 6 do
		local m = bay:FindFirstChild("Bin_" .. k)
		out[BIN_OF_NAME[m.Sign.SignGui.Label.Text]] = m
	end
	return out
end
local function standFor(bay, m)
	local b = m.Base.Position
	local flat = Vector3.new(b.X, 3, b.Z)
	local P = W(bay, 0, 3, 0)
	return flat + (P - flat).Unit * 5
end
local function answerOf(bay, entry)
	local mis = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
	if mis then return BIN_OF_NAME[mis] end
	return (Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], readRules(bay)))
end
local function joinSpawn(name, uid)
	local p = h:join(name, uid)
	h:advance(0.1)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	return p
end
local function waitArmed(p)
	for _ = 1, 40 do
		if state(p).shift and state(p).shift.state == "ARMED" then return true end
		h:advance(0.5)
	end
	return false
end
local MIS = "MISFILED - goes to "

--============================================================================ A1. U1: the tutorial Phone

-- Six new players. Each taps the Teddy and the Phone from the spawn pad, takes the PHONE to
-- ELECTRONICS because it looks like one (the mistake the tutorial exists to catch), then sorts the
-- Teddy. The reviewer measured: the Phone on neither tray nor hotbar in 6 of 6, the TAP HERE slot
-- nil in 6 of 6, another Phone on the tray in 4 of 6.
do
	local vanished, noSlot, extraPhones, misfileNamed = 0, 0, 0, 0
	local N = 6
	for i = 1, N do
		local p = joinSpawn("New" .. i, 7100 + i)
		local bay = bayOf(p)
		hrp(p).CFrame = CFrame.new(W(bay, 0, 3.51, 14))
		local t = state(p).shift.tutorial
		bay["Slot_" .. t.slot].Item.ClickDetector.MouseClick:Fire(p)
		h:advance(0.35)
		bay["Slot_" .. Config.Shift.Tutorial[2].slot].Item.ClickDetector.MouseClick:Fire(p)
		h:advance(0.35)
		local idx
		for k, e in state(p).shift.carried do
			if e.name == "Phone" then idx = k end
		end
		SelectEvent:simulateFireServer(p, idx)
		walkTo(p, standFor(bay, bins(bay).ELECTRONICS))
		local n0 = #NoticeEvent:sentTo(p)
		bins(bay).ELECTRONICS.Base.Drop.Triggered:Fire(p)
		local mis = NoticeEvent:sentTo(p)[n0 + 1]
		if mis and string.find(mis.args[1].text, "Phone", 1, true) then misfileNamed += 1 end
		if onTray(bay, "Phone", MIS .. "KEYS & WALLETS") == nil then vanished += 1 end
		h:advance(0.4)
		for _, it in readTray(bay) do
			if it.name == "Phone" and it.line ~= MIS .. "KEYS & WALLETS" then extraPhones += 1 end
		end
		walkTo(p, standFor(bay, bins(bay).TOYS))
		for k, e in state(p).shift.carried do
			if e.name == "Teddy Bear" then SelectEvent:simulateFireServer(p, k) end
		end
		bins(bay).TOYS.Base.Drop.Triggered:Fire(p)
		local tut = state(p).shift.tutorial
		if not (tut and tut.step == "pick" and tut.item == "Phone" and tut.slot ~= nil
			and strip(bay["Slot_" .. tut.slot].Tag.TagLine.Text) == MIS .. "KEYS & WALLETS") then
			noSlot += 1
		end
		h:leave(p)
		h:advance(0.5)
	end
	print(string.format("  U1 tutorial Phone misfiled by its look: vanished %d of %d, no TAP HERE slot %d of %d, other Phones on the tray %d",
		vanished, N, noSlot, N, extraPhones))
	eq(vanished, 0, "U1: a misfiled tutorial Phone is back on the tray at once, its tag reading its answer")
	eq(noSlot, 0, "U1: ... and the tutorial points at its tray slot (the TAP HERE marker's target) after the Teddy is sorted")
	eq(extraPhones, 0, "U1: ... and no other Phone on the tray can be taken for it")
	eq(misfileNamed, N, "U2: the misfile toast names the item that went in the wrong bin")
end

--============================================================================ A2. U3: a returned item is on the tray

-- A stage-3 veteran carrying 4 plays a whole shift, filing every third deposit into a wrong bin on
-- purpose and putting every fourth pick straight back. After each misfile and put-back: is that item
-- on the tray, right then?
do
	local p = joinSpawn("Returner", 7300)
	local bay = bayOf(p)
	local P = W(bay, 0, 3, 0)
	eq(state(p).stage, 3, "CONTROL: a stage-3 shift")
	local returns, toCart, deposits, picks = 0, 0, 0, 0
	for _ = 1, 600 do
		local st = state(p)
		if st.shift.state == "SUMMARY" then break end
		if #st.shift.carried == 0 then
			walkTo(p, P)
			for _, it in readTray(bay) do
				if #state(p).shift.carried >= st.carry then break end
				it.click.MouseClick:Fire(p)
				picks += 1
				if picks % 4 == 0 then
					local held = state(p).shift.carried[#state(p).shift.carried]
					SelectEvent:simulateFireServer(p, #state(p).shift.carried)
					bay.Tray.PutBack.Triggered:Fire(p)
					returns += 1
					if onTray(bay, held.name, held.tag) == nil then toCart += 1 end
				end
				h:advance(0.1)
			end
			h:advance(0.35)
		else
			local entry = st.shift.carried[1]
			local right = answerOf(bay, entry)
			local target = right
			deposits += 1
			local deliberate = deposits % 3 == 0 and not string.find(entry.tag, MIS, 1, true)
			if deliberate then
				for _, b in Config.Rules.Bins do
					if b ~= right then target = b break end
				end
			end
			walkTo(p, standFor(bay, bins(bay)[target]))
			SelectEvent:simulateFireServer(p, 1)
			bins(bay)[target].Base.Drop.Triggered:Fire(p)
			if deliberate then
				returns += 1
				if onTray(bay, entry.name, MIS .. Config.Rules.BinNames[right]) == nil then toCart += 1 end
			end
			h:advance(0.1)
		end
	end
	local s = state(p).shift
	print(string.format("  U3 %d misfiles and put-backs: %d went to the cart instead of the tray; shift %s, %d sorted",
		returns, toCart, s.state, s.summary and s.summary.sorted or -1))
	truthy(returns >= 15, "CONTROL: the bot returned " .. returns .. " items")
	eq(toCart, 0, "U3: every misfiled or put-back item is on the tray the moment it comes back")
	eq(s.summary and s.summary.sorted, 30, "U3: ... and nothing is lost: all 30 are sorted in the end")
	h:leave(p)
	h:advance(0.5)
end

--============================================================================ A2b. which tray item makes room

-- With the tray full, a returned item takes the slot of the item that rolled in most recently. Two
-- guards decide it, and each gets a scenario where it is the only thing that matters:
--   (1) an item that itself just came back is not bumped while anything else can be: five put-backs
--       in one frame, each landing after the last, must all stay on the tray;
--   (2) a tutorial item is never bumped: on career shift 1, with every other slot holding an item
--       that came back, one more put-back must not send the Teddy or the Phone to the cart.
do
	veteran(7310, 3)
	local p = joinSpawn("FivePut", 7310)
	local bay = bayOf(p)
	walkTo(p, W(bay, 0, 3, 2))
	local picked = {}
	for i, it in readTray(bay) do
		if i > 5 then break end
		it.click.MouseClick:Fire(p)
	end
	h:advance(0.5)
	for _, e in state(p).shift.carried do table.insert(picked, e) end
	eq(#picked, 5, "CONTROL: five in hand, and the tray refilled behind them")
	for _ = 1, 5 do bay.Tray.PutBack.Triggered:Fire(p) end
	local missing = 0
	for _, e in picked do
		if onTray(bay, e.name, e.tag) == nil then missing += 1 end
	end
	eq(#state(p).shift.carried, 0, "CONTROL: all five put back")
	eq(missing, 0, "U3: five put-backs in one frame all stay on the tray (a returned item is not bumped by the next one)")
	h:leave(p)
	h:advance(0.5)
end

do
	local p = joinSpawn("Crowder", 7320)
	local bay = bayOf(p)
	walkTo(p, W(bay, 0, 3, 2))
	local tutorialSlots = { [Config.Shift.Tutorial[1].slot] = true, [Config.Shift.Tutorial[2].slot] = true }
	-- each round: pick a slot's item A, pick what rolls in behind it, put A back, put the roll-in back
	for _, s in { 1, 2, 3, 4, 5, 8 } do
		bay["Slot_" .. s].Item.ClickDetector.MouseClick:Fire(p)
		h:advance(0.4)
		bay["Slot_" .. s].Item.ClickDetector.MouseClick:Fire(p)
		h:advance(0.4)
		bay.Tray.PutBack.Triggered:Fire(p)
		h:advance(0.4)
		bay.Tray.PutBack.Triggered:Fire(p)
		h:advance(0.6)
	end
	local tutorialOnTray = 0
	for s in tutorialSlots do
		local slot = bay["Slot_" .. s]
		if slot.Tag.Enabled and (slot.Tag.ItemName.Text == "Teddy Bear" or slot.Tag.ItemName.Text == "Phone") then
			tutorialOnTray += 1
		end
	end
	eq(#state(p).shift.carried, 0, "CONTROL: the crowding rounds ended empty-handed")
	eq(tutorialOnTray, 2, "U1: after six rounds of put-backs on a full tray, the Teddy and the Phone are still on the tray")
	local tut = state(p).shift.tutorial
	truthy(tut and tut.step == "pick" and tut.slot ~= nil, "U1: ... and the tutorial still points at a tray slot")
	h:leave(p)
	h:advance(0.5)
end

--============================================================================ A3. U2: which item E drops

-- Three players who never tap the hotbar, at carry 2, 3 and 5, on stage 3:
--   first  takes the item it picked FIRST to its bin and presses E;
--   last   takes the item it picked LAST to its bin and presses E;
--   prompt intends what `last` intends, but reads the Drop prompt at the bin, and when the prompt
--          names a different item it taps that item's hotbar slot first.
-- Every time any of them stands at a bin, the prompt must name the item E will drop.
local promptWrong, promptChecks = 0, 0
local function playStyle(p, style)
	local bay = bayOf(p)
	local P = W(bay, 0, 3, 0)
	local wrong, deposits, selects = 0, 0, 0
	for _ = 1, 900 do
		local st = state(p)
		if st.shift.state == "SUMMARY" then break end
		if #st.shift.carried == 0 then
			walkTo(p, P)
			local n = 0
			for _, it in readTray(bay) do
				if n >= st.carry then break end
				it.click.MouseClick:Fire(p)
				n += 1
				h:advance(0.25)
			end
			h:advance(0.35)
		else
			local carried = st.shift.carried
			local want = if style == "first" then 1 else #carried
			local entry = carried[want]
			local m = bins(bay)[answerOf(bay, entry)]
			walkTo(p, standFor(bay, m))
			local sel = state(p).shift.carried[state(p).shift.selected]
			promptChecks += 1
			if m.Base.Drop.ActionText ~= "Drop " .. sel.name or m.Base.Drop.ObjectText ~= sel.tag then
				promptWrong += 1
			end
			if style == "prompt" and (m.Base.Drop.ActionText ~= "Drop " .. entry.name or m.Base.Drop.ObjectText ~= entry.tag) then
				SelectEvent:simulateFireServer(p, want)
				selects += 1
			end
			local before = state(p).shift.misfiles
			m.Base.Drop.Triggered:Fire(p)
			deposits += 1
			if state(p).shift.state ~= "SUMMARY" and state(p).shift.misfiles > before then wrong += 1 end
			if state(p).shift.state == "SUMMARY" and state(p).shift.summary.misfiles > before then wrong += 1 end
			h:advance(0.1)
		end
	end
	return wrong, deposits, selects
end
local styleWrong = { first = 0, last = 0, prompt = 0 }
do
	for i, level in { 0, 1, 3 } do
		local p = joinSpawn("Style" .. i, 7200 + i)
		for k, style in { "first", "last", "prompt" } do
			if k > 1 then truthy(waitArmed(p), "CONTROL: the next shift arms") end
			local wrong, deposits, selects = playStyle(p, style)
			styleWrong[style] += wrong
			print(string.format("  U2 carry %d, %-6s: %d deposits, %d wrong bins, %d hotbar taps, shift %s", Config.Economy.Carry[level + 1],
				style, deposits, wrong, selects, state(p).shift.state))
			eq(state(p).shift.state, "SUMMARY", "CONTROL: carry " .. Config.Economy.Carry[level + 1] .. " " .. style .. " finished its shift")
		end
		h:leave(p)
		h:advance(0.5)
	end
	print(string.format("  U2 the Drop prompt read at %d deposits: %d did not name the item E drops", promptChecks, promptWrong))
	truthy(promptChecks > 100, "CONTROL: the Drop prompt was read at " .. promptChecks .. " deposits")
	eq(promptWrong, 0, "U2: at every deposit the Drop prompt names the item E will drop (its name, and its tag)")
	eq(styleWrong.first, 0, "U2: a player who takes the item they picked first to its bin never misfiles")
	eq(styleWrong.prompt, 0, "U2: a player who reads the Drop prompt never misfiles, whichever item they meant")
end

--============================================================================ B. the HUD on a phone

local me = h:join("Phone", 7777)
h:advance(0.1)
local okHud, hudErr = h:tryRun("client/Hud.client")
truthy(okHud, "the HUD loads" .. (if okHud then "" else ": " .. tostring(hudErr)))
for _, remote in { StateEvent, NoticeEvent } do
	for _, r in remote:sentTo(me) do remote:FireClient(me, table.unpack(r.args, 1, r.args.n)) end
end
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)
local root = me.PlayerGui.DepotHud.Root
local bay = bayOf(me)
local markerItem, markerBin = me.PlayerGui.TutorialItemMarker, me.PlayerGui.TutorialBinMarker
local function markerText(m)
	local l = m:FindFirstChild("Text")
	return l and l.Text
end

do
	-- U1, the reviewer's scenario 6: tap the Teddy from the pad, press R (Put back is in range there)
	eq(root.Hint.Text, "Tap the Teddy Bear on the tray.", "CONTROL: the first hint")
	hrp(me).CFrame = CFrame.new(W(bay, 0, 3.51, 14))
	local t = state(me).shift.tutorial
	bay["Slot_" .. t.slot].Item.ClickDetector.MouseClick:Fire(me)
	h:advance(1)
	eq(bay.Tray.PutBack.Enabled, true, "CONTROL: Put back is enabled while carrying")
	eq(bay.Tray.PutBack.ActionText, "Put back Teddy Bear", "U2: the Put back prompt names the item it puts back")
	bay.Tray.PutBack.Triggered:Fire(me)
	h:advance(0.1)
	eq(#state(me).shift.carried, 0, "CONTROL: R put the Teddy back")
	local tt = state(me).shift.tutorial
	truthy(tt and tt.step == "pick" and tt.slot ~= nil, "U1: a put-back tutorial Teddy is on the tray, and the tutorial says where")
	eq(markerItem.Enabled, true, "U1: ... the TAP HERE marker is up")
	eq(markerItem.Adornee and markerItem.Adornee.Name, tt and tt.slot and ("Slot_" .. tt.slot), "U1: ... over the Teddy's slot")
	h:advance(10)
	eq(markerItem.Enabled, true, "U1: ... and still up 10 s later")
end

do
	-- U4: the wording, on a phone and on a keyboard
	local t = state(me).shift.tutorial
	bay["Slot_" .. t.slot].Item.ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	bay["Slot_" .. Config.Shift.Tutorial[2].slot].Item.ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	eq(state(me).shift.carried[state(me).shift.selected].name, "Teddy Bear", "U2: after tapping the Teddy and then the Phone, E still drops the Teddy")
	eq(root.Hint.Text, "T means TOYS. Walk to the TOYS bin and tap Drop.", "U4: on a phone the hint says tap Drop, not press E")
	eq(markerText(markerBin), "DROP HERE", "U4: ... and the bin marker says DROP HERE")
	h:setTouch(false)
	h:advance(0.1)
	eq(root.Hint.Text, "T means TOYS. Walk to the TOYS bin and press E.", "U4: with a keyboard it says press E")
	eq(markerText(markerBin), "PRESS E HERE", "U4: ... and PRESS E HERE")
	h:setTouch(true)
	h:advance(0.1)
	eq(root.Hint.Text, "T means TOYS. Walk to the TOYS bin and tap Drop.", "CONTROL: back on a phone")

	-- U6: the TOYS bin's light pulses while the tutorial points at it
	local toys = bins(bay).TOYS
	local base = Config.Bay.BinLightBrightness
	local pulsing = false
	for _ = 1, 20 do
		h:advance(0.1)
		if math.abs(toys.Base.BinLight.Brightness - base) > 0.05 then pulsing = true end
	end
	truthy(pulsing, "U6: the TOYS bin's light pulses while the tutorial points at it")
	local others = 0
	for id, m in bins(bay) do
		if id ~= "TOYS" and math.abs(m.Base.BinLight.Brightness - base) > 0.05 then others += 1 end
	end
	eq(others, 0, "U6: ... and no other bin's light does")

	-- U1 on the HUD: the Phone by its look, into ELECTRONICS
	local phoneHot
	for k, e in state(me).shift.carried do
		if e.name == "Phone" then phoneHot = k end
	end
	root.Hotbar["Slot_" .. phoneHot].Activated:Fire()
	h:advance(0.2)
	eq(root.Hint.Text, "Read the TAG, not the phone: K means KEYS & WALLETS. Walk to that bin and tap Drop.",
		"U4: the Phone's hint on a phone")
	walkTo(me, standFor(bay, bins(bay).ELECTRONICS))
	eq(bins(bay).ELECTRONICS.Base.Drop.ActionText, "Drop Phone", "U2: at the bin, the prompt says it drops the Phone")
	bins(bay).ELECTRONICS.Base.Drop.Triggered:Fire(me)
	h:advance(0.1)
	truthy(string.find(root.Toast.Text, "Phone", 1, true) ~= nil and string.sub(root.Toast.Text, 1, 6) == "-8 s. ",
		"U2: the misfile toast names the Phone: " .. root.Toast.Text)
	truthy(onTray(bay, "Phone", MIS .. "KEYS & WALLETS") ~= nil, "U1: the Phone is on the tray, labelled with its answer")

	-- sort the Teddy: the stamp
	walkTo(me, standFor(bay, bins(bay).TOYS))
	bins(bay).TOYS.Base.Drop.Triggered:Fire(me)
	local stamp = root:FindFirstChild("Stamp")
	eq(stamp and stamp.Visible, true, "U6: a correct deposit shows the stamp")
	truthy(stamp ~= nil and stamp.Text ~= "", "U6: ... with text: " .. tostring(stamp and stamp.Text))
	h:advance(2)
	eq(stamp and stamp.Visible, false, "U6: ... briefly")
	eq(math.abs(toys.Base.BinLight.Brightness - base) <= 0.05, true, "U6: the TOYS light stops pulsing once the Teddy is sorted")

	-- the Phone again: the marker is over it
	local tut = state(me).shift.tutorial
	truthy(tut and tut.step == "pick" and tut.item == "Phone" and tut.slot ~= nil, "U1: the tutorial asks for the Phone on its slot")
	eq(markerItem.Enabled, true, "U1: the TAP HERE marker is up")
	eq(markerItem.Adornee and markerItem.Adornee.Name, tut and tut.slot and ("Slot_" .. tut.slot), "U1: ... over the misfiled Phone")
	walkTo(me, W(bay, 0, 3, 0))
	bay["Slot_" .. tut.slot].Item.ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	walkTo(me, standFor(bay, bins(bay).KEYS))
	bins(bay).KEYS.Base.Drop.Triggered:Fire(me)
	h:advance(0.1)
	eq(root.Toast.Text, "Tags beat looks. The rest is up to you - every rule is in MANUAL.", "CONTROL: the tutorial's closing toast")
	local pulse = root.Toggles.Toggle_manual:FindFirstChild("Pulse")
	eq(pulse and pulse.Enabled, true, "U6: the MANUAL button pulses when the tutorial hands over to it")
	h:advance(6)
	eq(pulse and pulse.Enabled, false, "U6: ... once")
	eq(markerItem.Enabled or markerBin.Enabled, false, "CONTROL: the tutorial markers are gone")
end

for _, e in h:errors() do print("scheduler error: " .. e) end
eq(#h:errors(), 0, "no server or client thread died")
print(string.format("lost-found-depot firstmin: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot firstmin check failed", 0) end
