-- Lost & Found Depot — the depot has to be IN THE WORLD, and a player standing where a player
-- stands has to be able to sort it.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot.luau
--
-- ALWAYS re-run wrap.py first. This file reads the bundle, not the game's src/.
--
-- WHY THIS FILE EXISTS. Grow a Crystal shipped with a Part that was built, sized, given its
-- ClickDetector and never parented: the core loop of a published game was unreachable while 166
-- unit tests stayed green. Nothing but the workspace can answer "is it there". So this file asks
-- the workspace — and then derives every answer the way a player does: it reads the rendered TAG
-- text and the rendered MEMO board, runs the public manual (Rules.resolve) against them, walks to
-- the bin whose rendered SIGN names the answer, and presses E there. There is no server-side
-- answer table anywhere for it to peek at (DESIGN.md §8.2), which is the point: a green run here
-- proves the visible information is sufficient.
--
-- The harness models only src/shared as ModuleScripts. Rojo also turns src/server/Secret.luau into
-- a ModuleScript in ServerScriptService; `registerServerModules` below does exactly that, and
-- nothing more.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot", viewport = { 1280, 720 }, touch = false })

local function registerServerModules(harness)
	local sss = harness.services.ServerScriptService
	for key, entry in harness.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and harness.modules[key] == nil then
			local holder = harness.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			harness.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
registerServerModules(h)

-- THE SALT, PINNED. The server takes one unseeded Random per player session for its salt, which is
-- correct and makes every run of this file a different depot. Pinned here (before the server runs,
-- so its global lookup sees the wrapper) so a failure can be replayed. Seeded Randoms pass through.
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(20260916 + unseeded * 7919)
		end
		return realRandom.new(seed)
	end,
}

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s +- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local store = h.services.DataStoreService:GetDataStore("LostFoundDepot_v1")

-- Preloaded saves, written before the server boots.
local P1, P2 = 5001, 5002
local ENDER, LOCKED, FAILER, MAXED, SWEEPER = 6001, 6002, 6003, 6004, 6005
store:SetAsync("u_" .. ENDER, { data = { v = 1, cash = 0, cartLevel = 0, shoesLevel = 0, shifts = 5, perfects = 0,
	backlog = 499, bestPerfectSeconds = 0, endingSeen = false, redeemed = {} } })
store:SetAsync("u_" .. LOCKED, { data = { v = 1, cash = 777, shifts = 3, backlog = 10, redeemed = {} },
	lock = { token = "ANOTHER-SERVER-SESSION", expires = os.time() + 3600 } })
store:SetAsync("u_" .. MAXED, { data = { v = 1, cash = 5000, cartLevel = 3, shoesLevel = 3, shifts = 9, redeemed = {} } })

--============================================================================ boot

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Rules = h:_require(h.ReplicatedStorage:FindFirstChild("Rules"))
local Economy = h:_require(h.ReplicatedStorage:FindFirstChild("Economy"))
local Secret = h:_require(h.services.ServerScriptService:FindFirstChild("Secret"))

local remotes = h.ReplicatedStorage:FindFirstChild("DepotRemotes")
truthy(remotes ~= nil, "the server published DepotRemotes")
local StateEvent = remotes:FindFirstChild("State")
local NoticeEvent = remotes:FindFirstChild("Notice")
local SceneEvent = remotes:FindFirstChild("Scene")
local SelectEvent = remotes:FindFirstChild("Select")
local RedeemEvent = remotes:FindFirstChild("Redeem")
for _, n in { "State", "Notice", "Scene", "Select", "Redeem" } do
	truthy(remotes:FindFirstChild(n) ~= nil, "remote " .. n .. " exists")
end
do
	local names = {}
	for _, c in remotes:GetChildren() do table.insert(names, c.Name) end
	table.sort(names)
	eq(table.concat(names, ","), "Notice,Redeem,Scene,Select,State",
		"exactly five remotes: nothing takes a bin, an item, a result or a price")
end

--============================================================================ helpers

local function argsTo(remote, plr)
	local out = {}
	for _, r in remote:sentTo(plr) do table.insert(out, r.args[1]) end
	return out
end
local function state(plr)
	local s = StateEvent:sentTo(plr)
	return s[#s] and s[#s].args[1] or nil
end
local function noticeMark(plr) return #NoticeEvent:sentTo(plr) end
local function noticesSince(plr, mark)
	local all = argsTo(NoticeEvent, plr)
	local out = {}
	for i = mark + 1, #all do table.insert(out, all[i]) end
	return out
end
local function lastNoticeSince(plr, mark)
	local n = noticesSince(plr, mark)
	return n[#n]
end

local function bayOf(plr)
	local pad = plr.RespawnLocation
	return pad and pad.Parent or nil
end
local function originX(bay) return bay:FindFirstChild("BayPad").Position.X end
local function W(bay, x, y, z) return Vector3.new(originX(bay) + x, y, z) end
local function hrpOf(plr) return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") end
local function humOf(plr) return plr.Character and plr.Character:FindFirstChildOfClass("Humanoid") end
local function standAt(plr, pos) hrpOf(plr).CFrame = CFrame.new(pos) end
local totalWalked = 0
local function walkTo(plr, pos)
	local hrp = hrpOf(plr)
	local d = (hrp.Position - pos).Magnitude
	hrp.CFrame = CFrame.new(pos)
	h:advance(d / humOf(plr).WalkSpeed)
	totalWalked += d
	return d
end

local BIN_OF_NAME = {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
local LETTER_OF_NAME = {}
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end

local function plain(text) return (string.gsub(text or "", "<[^>]*>", "")) end

-- The tray as a player sees it.
local function readTray(bay)
	local out = {}
	for slot = 1, 8 do
		local part = bay:FindFirstChild("Slot_" .. slot)
		local tag = part and part:FindFirstChild("Tag")
		if part and tag and tag.Enabled then
			local line = plain(tag:FindFirstChild("TagLine").Text)
			local name = tag:FindFirstChild("ItemName").Text
			table.insert(out, { slot = slot, part = part, click = part:FindFirstChildOfClass("ClickDetector"),
				line = line, name = name, tag = Rules.parseTag(Config, line) })
		end
	end
	return out
end

local function memoText(bay)
	return bay:FindFirstChild("MemoBoard"):FindFirstChild("SignGui"):FindFirstChild("Label").Text
end
local function manualText(bay)
	return bay:FindFirstChild("ManualBoard"):FindFirstChild("SignGui"):FindFirstChild("Label").Text
end

-- The rules today, from the memo board's rendered text.
local function readRules(bay)
	local text = memoText(bay)
	for _, memo in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, memo), 1, true) then
			return Rules.withMemo(Config, memo)
		end
	end
	return Rules.base(Config)
end

local function readBins(bay)
	local out = {}
	for k = 1, 6 do
		local m = bay:FindFirstChild("Bin_" .. k)
		local label = m and m:FindFirstChild("Sign") and m.Sign:FindFirstChild("SignGui")
			and m.Sign.SignGui:FindFirstChild("Label")
		local id = label and BIN_OF_NAME[label.Text]
		if id then
			out[id] = { model = m, base = m:FindFirstChild("Base"), prompt = m.Base:FindFirstChild("Drop"), arc = k }
		end
	end
	return out
end

local function binStand(bay, base)
	local P = W(bay, 0, 3, 0)
	local flat = Vector3.new(base.Position.X, 3, base.Position.Z)
	local dir = (P - flat).Unit
	return flat + dir * 5
end

-- What a carried item's hotbar entry says the answer is.
local function answerOf(entry, rules)
	local misfiled = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
	if misfiled then return BIN_OF_NAME[misfiled] end
	local tag = Rules.parseTag(Config, entry.tag)
	local own = LETTER_OF_NAME[entry.name]
	return (Rules.resolve(Config, tag, own, rules))
end

local function otherBin(binId)
	for _, b in Config.Rules.Bins do
		if b ~= binId then return b end
	end
	return binId
end

-- Play until the shift reaches SUMMARY, the way a careful player does: carry as many as the cart
-- allows from the tray, deliver each to the bin its tag names. `misfiles` deliberately sends that
-- many first attempts to a wrong bin.
local function playShift(plr, misfiles)
	misfiles = misfiles or 0
	local bay = bayOf(plr)
	local P = W(bay, 0, 3, 0)
	local stats = { trips = 0, deposits = 0, walked = 0 }
	for _ = 1, 600 do
		local st = state(plr)
		if st.shift.state == "SUMMARY" then break end
		if #st.shift.carried == 0 then
			stats.walked += walkTo(plr, P)
			local tray = readTray(bay)
			if #tray == 0 then
				h:advance(0.5)
			else
				local n = 0
				for _, t in tray do
					if n >= st.carry then break end
					t.click.MouseClick:Fire(plr)
					n += 1
				end
				stats.trips += 1
				h:advance(0.35)
			end
		else
			local entry = st.shift.carried[1]
			local binId = answerOf(entry, readRules(bay))
			if misfiles > 0 and not string.find(entry.tag, "MISFILED", 1, true) then
				binId = otherBin(binId)
				misfiles -= 1
			end
			local b = readBins(bay)[binId]
			stats.walked += walkTo(plr, binStand(bay, b.base))
			SelectEvent:simulateFireServer(plr, 1)
			b.prompt.Triggered:Fire(plr)
			stats.deposits += 1
		end
	end
	return stats
end

local function waitForArmed(plr)
	for _ = 1, 40 do
		if state(plr).shift.state == "ARMED" then return true end
		h:advance(0.5)
	end
	return false
end

--============================================================================ the world, before anyone joins

local bays = h.workspace:FindFirstChild("Bays")
truthy(bays ~= nil, "workspace.Bays exists (control: the builder ran at all)")
local expectedBays = math.max(Config.Bay.Count, h.Players.MaxPlayers)
eq(#bays:GetChildren(), expectedBays, "one bay per seat: max(Bay.Count, Players.MaxPlayers)")

do
	local enabled = {}
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then table.insert(enabled, d:GetFullName()) end
	end
	eq(#enabled, 1, "before anyone joins, exactly one SpawnLocation is enabled")
	eq(enabled[1], "Workspace.BreakRoom.StaffEntrance", "... and it is the Break Room's, not a roof")
end

eq(h.Lighting.ClockTime, 15.5, "the Temple lighting preset is applied (ClockTime 15.5)")
truthy(h.Lighting:FindFirstChild("FxSunRays") ~= nil, "Temple's sun rays exist")
eq(h.Lighting:FindFirstChild("FxDoF"), nil, "no depth of field: this game is read at 5-30 studs")

local SHELL = { Floor = true, WallLeft = true, WallRight = true, WallFront = true, WallBackL = true,
	WallBackR = true, Lintel = true, Door = true, BackRoomWallL = true, BackRoomWallR = true, BackRoomWallBack = true }
local FIXTURE = { Tray = true, TrayStep = true, Base = true, SideFront = true, SideBack = true, SideLeft = true,
	SideRight = true, Locker = true, BayPad = true }

local function partCount(folder)
	local n = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

do
	local missing, orphanParts, badClimb, highFixture, collidingDecor = {}, 0, 0, 0, 0
	local maxParts = 0
	local roofOk = 0
	for k = 1, expectedBays do
		local bay = bays:FindFirstChild("Bay_" .. k)
		if bay == nil then
			table.insert(missing, "Bay_" .. k)
			continue
		end
		local function need(path, cond)
			if not cond then table.insert(missing, bay.Name .. "." .. path) end
		end
		for s = 1, 8 do
			local slot = bay:FindFirstChild("Slot_" .. s)
			need("Slot_" .. s, slot ~= nil and slot:IsDescendantOf(h.workspace))
			local cd = slot and slot:FindFirstChildOfClass("ClickDetector")
			need("Slot_" .. s .. ".ClickDetector", cd ~= nil and cd.MaxActivationDistance == 12)
			need("Slot_" .. s .. ".Tag", slot ~= nil and slot:FindFirstChild("Tag") ~= nil)
		end
		for b = 1, 6 do
			local bin = bay:FindFirstChild("Bin_" .. b)
			local base = bin and bin:FindFirstChild("Base")
			local drop = base and base:FindFirstChild("Drop")
			need("Bin_" .. b .. ".Base.Drop", drop ~= nil and drop.ClassName == "ProximityPrompt"
				and drop.MaxActivationDistance == 6 and drop.KeyboardKeyCode == Enum.KeyCode.E
				and drop.RequiresLineOfSight == false)
			need("Bin_" .. b .. ".Sign", bin ~= nil and bin:FindFirstChild("Sign") ~= nil)
			need("Bin_" .. b .. ".Base.BinLight", base ~= nil and base:FindFirstChildOfClass("PointLight") ~= nil)
		end
		local tray = bay:FindFirstChild("Tray")
		local put = tray and tray:FindFirstChild("PutBack")
		need("Tray.PutBack", put ~= nil and put.KeyboardKeyCode == Enum.KeyCode.R and put.MaxActivationDistance == 8)
		local locker = bay:FindFirstChild("Locker")
		need("Locker.Cart", locker ~= nil and locker:FindFirstChild("Cart") ~= nil and locker.Cart.KeyboardKeyCode == Enum.KeyCode.E)
		need("Locker.Shoes", locker ~= nil and locker:FindFirstChild("Shoes") ~= nil and locker.Shoes.KeyboardKeyCode == Enum.KeyCode.R)
		local door = bay:FindFirstChild("Door")
		need("Door.Open", door ~= nil and door:FindFirstChild("Open") ~= nil)
		local pad = bay:FindFirstChild("BayPad")
		need("BayPad", pad ~= nil and pad.ClassName == "SpawnLocation" and pad.Enabled == false and pad.Duration == 0)
		for _, n in { "MemoBoard", "ManualBoard", "BacklogSign", "NameSign", "TrayStep", "FxDustVolume" } do
			need(n, bay:FindFirstChild(n) ~= nil)
		end

		maxParts = math.max(maxParts, partCount(bay))
		for _, d in bay:GetDescendants() do
			if d:IsA("BasePart") then
				if not d:IsDescendantOf(h.workspace) then orphanParts += 1 end
				if d.CanCollide then
					if not (SHELL[d.Name] or FIXTURE[d.Name]) then
						badClimb += 1
						print("  collidable non-shell, non-fixture part: " .. d:GetFullName())
					end
					if FIXTURE[d.Name] and d.Position.Y + d.Size.Y / 2 > Config.Bay.MaxStandableTop + 1e-6 then
						highFixture += 1
						print("  fixture top above 6: " .. d:GetFullName())
					end
				elseif SHELL[d.Name] or FIXTURE[d.Name] then
					-- fine: nothing forces a shell part to collide except the door, checked below
				end
				if d.Name == "BackRoomRoof" and d.CanCollide == false then roofOk += 1 end
				if not (SHELL[d.Name] or FIXTURE[d.Name]) and d.CanCollide then collidingDecor += 1 end
			end
		end
		for _, n in { "WallLeft", "WallRight", "WallFront", "WallBackL", "WallBackR" } do
			local wall = bay:FindFirstChild(n)
			need(n .. " is 16 tall and collides", wall ~= nil and wall.CanCollide and math.abs(wall.Size.Y - 16) < 1e-6
				and math.abs(wall.Position.Y + wall.Size.Y / 2 - 16) < 1e-6)
		end
	end
	eq(#missing, 0, "every bay has 8 slots with ClickDetectors, 6 bins with Drop prompts, PutBack, two locker prompts, a door prompt and a disabled pad"
		.. (if #missing > 0 then " (missing: " .. table.concat(missing, ", ", 1, math.min(#missing, 6)) .. ")" else ""))
	eq(orphanParts, 0, "every Part in every bay is parented into the workspace")
	eq(badClimb, 0, "every collidable Part is a named shell Part or fixture")
	eq(highFixture, 0, "no collidable fixture has a top face above 6 studs")
	eq(collidingDecor, 0, "every decorative Part is CanCollide = false")
	eq(roofOk, expectedBays, "every Back Room roof is CanCollide = false")
	print(string.format("  world: %d bays, the largest empty bay holds %d Parts", expectedBays, maxParts))
	truthy(maxParts <= Config.Bay.MaxPartsPerBay, "an empty bay holds " .. maxParts .. " Parts (<= 120)")
	local last = bays:FindFirstChild("Bay_" .. expectedBays)
	near(last and last:FindFirstChild("BayPad").Position.X or -1, 980, 1e-6, "the last bay is centred at x = 980")
end

--============================================================================ join, and landing

local p1 = h:join("Sorter", P1)
h:advance(0.1)
local bay1 = bayOf(p1)
truthy(bay1 ~= nil, "a joining player's RespawnLocation is their own bay's pad, set before any yield")
eq(bay1 and bay1:FindFirstChild("BayPad").Enabled, true, "... and that pad is enabled")
h.Players:simulateSpawn(p1, h.workspace)
h:advance(0.5)

do
	local hrp = hrpOf(p1)
	local pad = bay1:FindFirstChild("BayPad")
	local dx = math.abs(hrp.Position.X - pad.Position.X)
	local dz = math.abs(hrp.Position.Z - pad.Position.Z)
	truthy(dx <= 3 and dz <= 3, string.format("the character lands on its own pad (off by %.2f, %.2f)", dx, dz))
	truthy(hrp.Position.Y > pad.Position.Y + 0.5 and hrp.Position.Y < pad.Position.Y + 5,
		string.format("... standing on it, not inside it or on a roof (y = %.2f)", hrp.Position.Y))
	eq(humOf(p1).WalkSpeed, 16, "walk speed is set explicitly to 16")
end

do
	local st = state(p1)
	truthy(st ~= nil and st.loaded == true, "the profile loaded and the HUD was told")
	eq(st.shift.state, "ARMED", "shift 1 is ARMED, not running")
	eq(st.shift.secondsLeft, 330, "the clock shows 330 s and is not running")
	eq(st.shift.cleared, 0, "CLEARED 0")
	eq(st.shift.total, 30, "... of 30")
	eq(st.cash, 0, "CASH 0")
	eq(st.carry, 2, "carry 2 on shift 1")
	eq(st.stage, 1, "stage 1")
	eq(#readTray(bay1), 8, "the tray holds 8 tagged items")
	eq(memoText(bay1), "", "no memo on shift 1")
	truthy(string.find(manualText(bay1), "DEPOT MANUAL", 1, true) ~= nil, "the manual board shows the manual")
	truthy(string.find(manualText(bay1), "TORN", 1, true) == nil, "... without the torn-tag layer on shift 1")
	eq(bay1:FindFirstChild("NameSign"):FindFirstChild("SignGui"):FindFirstChild("Label").Text, "SORTER'S BAY",
		"the name sign reads SORTER'S BAY")
	eq(st.shift.tutorial and st.shift.tutorial.item, "Teddy Bear", "the tutorial points at the Teddy Bear")
end

--============================================================================ shift 1 from the spawn pad

local shift1Start = h.scheduler:now()
do
	local tray = readTray(bay1)
	local teddy = nil
	for _, t in tray do
		if t.line == "T \u{B7} 2 \u{B7} GREEN" and t.name == "Teddy Bear" then teddy = t end
	end
	truthy(teddy ~= nil, "a tray tag reads T . 2 . GREEN / Teddy Bear")
	-- A tap lands on the item's own pieces (REVIEW-1 finding 6), so every item on the tray carries a
	-- ClickDetector at ItemReach, and the Teddy is picked through ITS OWN detector, not the tile's.
	local itemsWired, itemsOnTray = 0, 0
	for s = 1, 8 do
		local item = bay1:FindFirstChild("Slot_" .. s):FindFirstChild("Item")
		if item then
			itemsOnTray += 1
			local cd = item:FindFirstChildOfClass("ClickDetector")
			local queryable = 0
			for _, piece in item:GetChildren() do
				if piece:IsA("BasePart") and piece.CanQuery then queryable += 1 end
			end
			if cd and cd.MaxActivationDistance == Config.Bay.ItemReach and queryable > 0 then itemsWired += 1 end
		end
	end
	eq(itemsWired, itemsOnTray, "every tray item carries a ClickDetector at ItemReach, on queryable pieces")
	-- Fired from exactly where the engine put the character: no step.
	teddy.part:FindFirstChild("Item"):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(p1)
	h:advance(0.35)
	local st = state(p1)
	eq(#st.shift.carried, 1, "the teddy was picked up from the spawn pad, without a step")
	eq(st.shift.state, "RUNNING", "the first pickup starts the clock")
	eq(st.shift.carried[1].name, "Teddy Bear", "the hotbar holds the Teddy Bear")
	eq(st.shift.tutorial and st.shift.tutorial.bin, "TOYS", "the tutorial now points at TOYS")

	local b = readBins(bay1).TOYS
	truthy(b ~= nil, "a bin sign reads TOYS")
	eq(b.prompt.Enabled, true, "the Drop prompt is enabled while carrying")
	walkTo(p1, binStand(bay1, b.base))
	b.prompt.Triggered:Fire(p1)
	st = state(p1)
	eq(st.cash, 11, "the teddy paid +11")
	eq(st.shift.cleared, 1, "CLEARED 1/30")
	eq(st.backlog, 1, "the backlog moved to 1")
	eq(st.shift.tutorial and st.shift.tutorial.item, "Phone", "the tutorial moves on to the Phone")
	eq(st.shift.tutorial and st.shift.tutorial.bin, "KEYS & WALLETS", "... whose tag says KEYS & WALLETS")
	eq(b.prompt.Enabled, false, "the Drop prompts switch off when the hands are empty")
end

local s1stats = playShift(p1, 0)
do
	local st = state(p1)
	eq(st.shift.state, "SUMMARY", "shift 1 reached SUMMARY")
	eq(st.shift.cleared, 30, "30/30 sorted, every answer read off the rendered world")
	eq(st.shift.misfiles, 0, "zero misfiles")
	eq(st.shift.summary and st.shift.summary.perfect, true, "a Perfect Shift")
	eq(st.cash, 655, "cash is 555 from sorts + 100 Perfect bonus")
	eq(st.backlog, 30, "backlog 30")
	eq(st.shifts, 1, "one shift on the career")
	eq(st.perfects, 1, "one Perfect")
	local secs = h.scheduler:now() - shift1Start
	truthy(secs < 330, string.format("the shift took %.1f s of clock", secs))
	print(string.format("  shift 1: %.1f s, %d trips, %d deposits, %.0f studs walked", secs, s1stats.trips,
		s1stats.deposits, s1stats.walked))
end
do
	local found = false
	for _, n in argsTo(NoticeEvent, p1) do
		if n.text == "Tags beat looks. The rest is up to you - every rule is in MANUAL." then found = true end
	end
	truthy(found, "the tutorial closed with its toast")

	-- REVIEW-1 R2-2. The hint says "T means TOYS. Walk to the TOYS bin and press E", and E deposits
	-- the SELECTED item. A new player with two hands who tapped the Teddy and then the Phone held the
	-- Phone selected while the hint named the Teddy: the tutorial's own instruction was a misfile.
	-- Invariant over every shift-1 payload: whenever the tutorial says "sort", the item it names IS
	-- the selected one, so doing what the hint says deposits what the hint is about.
	local sortHints, mismatched = 0, 0
	for _, rec in StateEvent:sentTo(p1) do
		local st = rec.args[1]
		local t = st and st.shift and st.shift.tutorial
		if t and t.step == "sort" then
			sortHints += 1
			local sel = st.shift.carried[st.shift.selected]
			if sel == nil or sel.name ~= t.item then
				mismatched += 1
			end
		end
	end
	truthy(sortHints > 0, "CONTROL: shift 1 sent tutorial sort hints (" .. sortHints .. ")")
	eq(mismatched, 0, "every tutorial 'sort' hint names the SELECTED carried item, so E does what the hint says")
end

--============================================================================ shift 2: stages, reach, double trigger, misfile

truthy(waitForArmed(p1), "the bay re-arms after the intermission")
do
	local st = state(p1)
	eq(st.stage, 2, "shift 2 is stage 2")
	eq(st.shift.tutorial, nil, "no tutorial on shift 2")
	eq(st.newLayer, 2, "the HUD is told a new layer unlocked (the MANUAL drawer opens itself)")
	eq(memoText(bay1), "", "still no memo at stage 2")
	truthy(string.find(manualText(bay1), "TORN TAGS", 1, true) ~= nil, "the manual board adds TORN TAGS")
	-- REVIEW-1 R2-7: "see the catalog" has to point at a catalog a player can read in the bay.
	local board = manualText(bay1)
	local unlisted = {}
	for _, item in Config.Catalog do
		local onItsLine = false
		for line in string.gmatch(board, "[^\n]+") do
			if string.sub(line, 1, 3) == item.letter .. ": " and string.find(line, item.name, 1, true) then
				onItsLine = true
			end
		end
		if not onItsLine then table.insert(unlisted, item.name) end
	end
	eq(#unlisted, 0, "the stage-2 manual board lists every item on its own letter's catalog line"
		.. (if #unlisted > 0 then " (missing: " .. table.concat(unlisted, ", ") .. ")" else ""))
end

local P = W(bay1, 0, 3, 0)
do
	-- REACH: a pick from across the bay is refused, with a reason.
	standAt(p1, W(bay1, -30, 3, -24))
	local mark = noticeMark(p1)
	local t = readTray(bay1)[1]
	t.click.MouseClick:Fire(p1)
	eq(#state(p1).shift.carried, 0, "a pick from ~38 studs away is refused")
	eq(state(p1).shift.state, "ARMED", "... and does not start the clock")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).text, "Too far - walk up to the tray.", "... with a toast")

	-- DOUBLE TRIGGER: two clicks on one item in the same frame carry one item.
	standAt(p1, P)
	local markDouble = noticeMark(p1)
	t.click.MouseClick:Fire(p1)
	t.click.MouseClick:Fire(p1)
	eq(#state(p1).shift.carried, 1, "two MouseClicks on one item in the same frame produce ONE carried item")
	-- ...and ONE answer. A tap can reach two ClickDetectors (the item's own and its slot tile's),
	-- and a double tap is one intent: neither may earn a "cart is still rolling" refusal.
	eq(#noticesSince(p1, markDouble), 0, "... and the second click of the same tap sends no refusal toast")
	local item = t.part:FindFirstChild("Item")
	eq(item, nil, "CONTROL: the picked item left the slot")
	h:advance(0.35)

	-- A deposit fired from the tray is refused.
	mark = noticeMark(p1)
	local anyBin = readBins(bay1).CLAIMS
	anyBin.prompt.Triggered:Fire(p1)
	eq(#state(p1).shift.carried, 1, "a deposit fired from the tray is refused")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).text, "Too far - walk up to the bin.", "... with a toast")

	-- SELECT garbage is dropped: no error, no change, no toast.
	mark = noticeMark(p1)
	local before = state(p1).shift.selected
	for _, junk in { 0 / 0, 1e9, 0, -1, 1.5, "1", {}, true } do
		SelectEvent:simulateFireServer(p1, junk)
	end
	eq(state(p1).shift.selected, before, "malformed Select payloads change nothing")
	eq(#noticesSince(p1, mark), 0, "... and send no toast to a client that no honest HUD could be")

	-- A stranger's bay prompts are not theirs.
	local p2 = h:join("Stranger", P2)
	h:advance(0.1)
	h.Players:simulateSpawn(p2, h.workspace)
	h:advance(0.5)
	truthy(bayOf(p2) ~= bay1, "the second player got a different bay")
	standAt(p2, P) -- standing in MY bay, at my pick point
	mark = noticeMark(p2)
	readTray(bay1)[2].click.MouseClick:Fire(p2)
	eq(#state(p2).shift.carried, 0, "a stranger cannot pick from my tray")
	eq(lastNoticeSince(p2, mark) and lastNoticeSince(p2, mark).text, "That's someone else's bay.", "... and is told so")
	h:leave(p2)
	h:advance(0.5)
end

do
	-- THE MISFILE. Carrying one item now; send it to a wrong bin.
	local st = state(p1)
	local entry = st.shift.carried[1]
	local right = answerOf(entry, readRules(bay1))
	local wrong = otherBin(right)
	local b = readBins(bay1)[wrong]
	walkTo(p1, binStand(bay1, b.base))
	local endsBefore = state(p1).shift.endsAt
	local cashBefore, backlogBefore = state(p1).cash, state(p1).backlog
	local mark = noticeMark(p1)
	SelectEvent:simulateFireServer(p1, 1)
	b.prompt.Triggered:Fire(p1)
	st = state(p1)
	eq(st.shift.endsAt, endsBefore - 8, "a misfile takes exactly 8 s off the clock")
	eq(st.shift.misfiles, 1, "the misfile is counted")
	eq(#st.shift.carried, 0, "the item left the hands")
	eq(st.cash, cashBefore, "a misfile pays nothing")
	local n = lastNoticeSince(p1, mark)
	eq(n and n.kind, "misfile", "a misfile notice")
	truthy(n ~= nil and string.sub(n.text, 1, 6) == "-8 s. " and string.find(n.text, Config.Rules.BinNames[right], 1, true) ~= nil,
		"the toast explains the deciding rule: " .. tostring(n and n.text))

	local misLine = "MISFILED - goes to " .. Config.Rules.BinNames[right]
	local function findBack()
		for _, t in readTray(bay1) do
			if t.line == misLine then return t end
		end
		return nil
	end
	h:advance(0.35)
	-- "back to a free tray slot, or to the front of the cart" (DESIGN.md §5.1). With the tray full
	-- it goes to the front of the cart: take one item off the tray and it must roll in next.
	local back = findBack()
	local wentToCart = back == nil
	walkTo(p1, P)
	if wentToCart then
		readTray(bay1)[1].click.MouseClick:Fire(p1)
		h:advance(0.35)
		back = findBack()
	end
	truthy(back ~= nil, "the item is back on the tray" .. (if wentToCart then " (via the front of the cart)" else "")
		.. ", its tag now reading its answer")

	back.click.MouseClick:Fire(p1)
	h:advance(0.35)
	local rb = readBins(bay1)[right]
	walkTo(p1, binStand(bay1, rb.base))
	local idx = nil
	for i, e in state(p1).shift.carried do
		if e.tag == misLine then idx = i end
	end
	truthy(idx ~= nil, "the hotbar shows the misfiled item with its answer")
	SelectEvent:simulateFireServer(p1, idx)
	eq(state(p1).shift.selected, idx, "Select picks the misfiled item")
	cashBefore = state(p1).cash
	rb.prompt.Triggered:Fire(p1)
	st = state(p1)
	eq(st.cash - cashBefore, 5, "the re-sort pays 5")
	eq(st.backlog, backlogBefore, "... and adds no backlog")
	eq(st.shift.combo, 0, "... and does not grow the combo")
end

do
	-- Stage 2 tags: at least one torn part somewhere in the shift (the salt is pinned, so this is
	-- a fixed depot, not a 1-in-5,600 flake).
	local sawTorn = false
	for _, t in readTray(bay1) do
		if string.find(t.line, "?", 1, true) then sawTorn = true end
	end
	-- let the clock run out; a timed-out shift still counts toward the career
	local guard = 0
	while state(p1).shift.state == "RUNNING" and guard < 2000 do
		for _, t in readTray(bay1) do
			if string.find(t.line, "?", 1, true) then sawTorn = true end
		end
		h:advance(1)
		guard += 1
	end
	truthy(sawTorn, "stage 2 shows torn tags on the tray")
	local st = state(p1)
	eq(st.shift.state, "SUMMARY", "the clock ran out")
	eq(st.shift.summary and st.shift.summary.timedOut, true, "... and the summary says so")
	eq(st.shifts, 2, "a timed-out shift still counts")
end

truthy(waitForArmed(p1), "shift 3 arms")
do
	local st = state(p1)
	eq(st.stage, 3, "shift 3 is stage 3")
	truthy(st.shift.memo ~= nil and st.shift.memo ~= "", "the HUD has the memo line")
	truthy(string.find(memoText(bay1), "TODAY'S MEMO", 1, true) ~= nil, "the memo board shows TODAY'S MEMO")
	truthy(string.find(memoText(bay1), st.shift.memo, 1, true) ~= nil, "... with the same line")
	truthy(string.find(manualText(bay1), "TODAY'S MEMO: " .. st.shift.memo, 1, true) ~= nil, "the manual board adds the memo box")
	eq(st.newLayer, 3, "the HUD is told layer 3 unlocked")
end

--============================================================================ play shift 3 with the memo

do
	local stats = playShift(p1, 2)
	local st = state(p1)
	eq(st.shift.cleared, 30, "shift 3: 30/30 sorted under a memo, read off the memo board")
	eq(st.shift.misfiles, 2, "... with exactly the 2 deliberate misfiles")
	eq(st.shift.summary and st.shift.summary.perfect, true, "2 misfiles is still Perfect")
	print(string.format("  shift 3 (memo %q): %d deposits, %.0f studs", st.shift.memo or "", stats.deposits, stats.walked))
end

--============================================================================ upgrades at the locker

truthy(waitForArmed(p1), "shift 4 arms")
do
	local locker = bay1:FindFirstChild("Locker")
	walkTo(p1, W(bay1, 12, 3, 13))
	local st = state(p1)
	local cash = st.cash
	local mark = noticeMark(p1)
	locker.Cart.Triggered:Fire(p1)
	st = state(p1)
	eq(st.carry, 3, "the Cart upgrade raises carry to 3")
	eq(st.cash, cash - 250, "... for 250")
	locker.Shoes.Triggered:Fire(p1)
	st = state(p1)
	eq(humOf(p1).WalkSpeed, 18, "the Shoes upgrade sets WalkSpeed 18 on the live Humanoid")
	eq(st.cash, cash - 500, "... for another 250")
	-- spend down to below 800, then refuse
	local left = st.cash
	if left >= 800 then
		locker.Cart.Triggered:Fire(p1) -- carry 4 for 800
		left = state(p1).cash
	end
	mark = noticeMark(p1)
	locker.Cart.Triggered:Fire(p1)
	local n = lastNoticeSince(p1, mark)
	local st2 = state(p1)
	local want = if st2.cartLevel == 1 then "Cart (carry 4) costs 800. You have " .. left .. "."
		else "Cart (carry 5) costs 2000. You have " .. left .. "."
	eq(n and n.text, want, "an unaffordable upgrade is refused with its price and your cash")
	eq(st2.cash, left, "... and costs nothing")

	-- from across the bay
	walkTo(p1, P)
	mark = noticeMark(p1)
	locker.Shoes.Triggered:Fire(p1)
	eq(state(p1).shoesLevel, 1, "the locker cannot be used from the pick point")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).text, "Too far - walk up to the locker.", "... with a toast")

	local maxed = h:join("Maxed", MAXED)
	h:advance(0.1)
	h.Players:simulateSpawn(maxed, h.workspace)
	h:advance(0.5)
	local mb = bayOf(maxed)
	walkTo(maxed, W(mb, 12, 3, 13))
	mark = noticeMark(maxed)
	mb.Locker.Cart.Triggered:Fire(maxed)
	eq(lastNoticeSince(maxed, mark) and lastNoticeSince(maxed, mark).text, "Your cart is fully upgraded.", "a maxed cart says so")
	mb.Locker.Shoes.Triggered:Fire(maxed)
	eq(lastNoticeSince(maxed, mark) and lastNoticeSince(maxed, mark).text, "Your shoes are fully upgraded.", "maxed shoes say so")
	eq(state(maxed).cash, 5000, "... and neither costs anything")
	eq(humOf(maxed).WalkSpeed, 22, "a loaded shoes level 3 walks at 22")
	eq(state(maxed).carry, 5, "a loaded cart level 3 carries 5")
	h:leave(maxed)
	h:advance(0.5)
end

--============================================================================ codes

do
	local cash = state(p1).cash
	local mark = noticeMark(p1)
	RedeemEvent:simulateFireServer(p1, "  sorted ")
	h:advance(0.1)
	eq(state(p1).cash, cash + 250, "SORTED grants 250")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).kind, "ok", "... with an ok toast")
	local rec = store:GetAsync("u_" .. P1)
	eq(rec and rec.data and rec.data.redeemed and rec.data.redeemed.SORTED, true, "the redemption is in the store")
	eq(rec and rec.data and rec.data.cash, cash + 250, "... in the same write as the cash")

	mark = noticeMark(p1)
	RedeemEvent:simulateFireServer(p1, "SORTED")
	eq(state(p1).cash, cash + 250, "a second attempt inside the cooldown grants nothing")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).text, "One code at a time - try again in a moment.", "... and says why")
	h:advance(2.1)
	RedeemEvent:simulateFireServer(p1, "SORTED")
	eq(state(p1).cash, cash + 250, "SORTED cannot be redeemed twice")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).text, "You already redeemed SORTED.", "... and says so")
	h:advance(2.1)
	RedeemEvent:simulateFireServer(p1, "NOPE")
	eq(lastNoticeSince(p1, mark) and lastNoticeSince(p1, mark).text, "That code does not exist.", "an unknown code says so")

	local callsBefore = store.__calls
	h:advance(2.1)
	RedeemEvent:simulateFireServer(p1, string.rep("A", 5000))
	RedeemEvent:simulateFireServer(p1, { "SORTED" })
	eq(store.__calls, callsBefore, "an oversized or non-string code never reaches the DataStore")

	-- the atomic flush refuses the grant when it cannot persist
	local failer = h:join("Failer", FAILER)
	h:advance(0.1)
	local fcash = state(failer).cash
	store.__failNext = true
	mark = noticeMark(failer)
	RedeemEvent:simulateFireServer(failer, "SORTED")
	eq(state(failer).cash, fcash, "a code whose write fails grants nothing")
	eq(lastNoticeSince(failer, mark) and lastNoticeSince(failer, mark).text,
		"That code could not be saved right now, so nothing was granted. Try again.", "... and says so")
	local frec = store:GetAsync("u_" .. FAILER)
	truthy(frec == nil or frec.data == nil or frec.data.redeemed == nil or frec.data.redeemed.SORTED == nil,
		"... and nothing was marked redeemed")
	h:advance(2.1)
	RedeemEvent:simulateFireServer(failer, "SORTED")
	eq(state(failer).cash, fcash + 250, "a retry after the failure succeeds (the in-flight flag was released)")
	h:leave(failer)
	h:advance(0.5)
end

--============================================================================ wire sweep over 20 shifts

local partRecords, tagRecords, hitboxRecords = {}, {}, {}
local nameLeaks = 0
local function fmtV(v) return string.format("%.3f,%.3f,%.3f", v.X, v.Y, v.Z) end
local function fmtC(c) return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)) end
local function sampleTray(bay)
	for s = 1, 8 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		local tag = slot:FindFirstChild("Tag")
		local item = slot:FindFirstChild("Item")
		hitboxRecords[table.concat({ fmtV(slot.Size), tostring(slot.Transparency), tostring(slot.CanCollide),
			tostring(slot.CanQuery), fmtC(slot.Color), tostring(slot.Material),
			tostring(slot:FindFirstChildOfClass("ClickDetector").MaxActivationDistance) }, "|")] = true
		if item and tag and tag.Enabled then
			local name = tag:FindFirstChild("ItemName").Text
			if item.ClassName ~= "Model" or item.Name ~= "Item" then nameLeaks += 1 end
			local parts = {}
			for _, p in item:GetDescendants() do
				if p:IsA("BasePart") then
					if p.Name ~= "Piece" then nameLeaks += 1 end
					table.insert(parts, table.concat({ fmtV(p.Size), fmtC(p.Color), tostring(p.Material),
						tostring(p.Transparency), fmtV(p.Position - slot.Position) }, "/"))
				end
			end
			table.sort(parts)
			partRecords[name] = partRecords[name] or {}
			partRecords[name][table.concat(parts, ";")] = true
			local tl, nl = tag:FindFirstChild("TagLine"), tag:FindFirstChild("ItemName")
			tagRecords[table.concat({ tostring(tag.Size), tostring(tag.StudsOffset), tostring(tag.MaxDistance),
				tostring(tag.AlwaysOnTop), tostring(tag.LightInfluence), fmtC(tl.TextColor3), tostring(tl.BackgroundTransparency),
				fmtC(tl.BackgroundColor3), tostring(tl.Font), tostring(tl.RichText), tostring(tl.Size), fmtC(nl.TextColor3),
				tostring(nl.Font), tostring(nl.Size), tostring(tag.Enabled) }, "|")] = true
		end
	end
end

do
	for i = 1, 20 do
		if state(p1).shift.state ~= "ARMED" then waitForArmed(p1) end
		sampleTray(bay1)
		walkTo(p1, P)
		readTray(bay1)[1].click.MouseClick:Fire(p1) -- start the clock
		h:advance(0.35)
		sampleTray(bay1) -- the refilled slot
		h:advance(Config.Shift.Seconds + 1)
		truthy(i < 20 or state(p1).shift.state == "SUMMARY", "shift ran out")
	end
	local worst, groups, over = 0, 0, {}
	for name, recs in partRecords do
		groups += 1
		local n = 0
		for _ in recs do n += 1 end
		worst = math.max(worst, n)
		if n > 2 then table.insert(over, name .. "=" .. n) end
	end
	local tagN, hitN = 0, 0
	for _ in tagRecords do tagN += 1 end
	for _ in hitboxRecords do hitN += 1 end
	print(string.format("  wire: %d item names seen, at most %d distinct looks each; %d tag record(s); %d hitbox record(s)",
		groups, worst, tagN, hitN))
	truthy(groups >= 12, "the sweep saw most of the catalog (" .. groups .. " of 16)")
	eq(#over, 0, "every item's rendered Parts are a function of (archetype, variant): at most 2 looks per item"
		.. (if #over > 0 then " (" .. table.concat(over, ", ") .. ")" else ""))
	eq(tagN, 1, "every tag renders with identical non-text properties, whatever its answer")
	eq(hitN, 1, "every slot hitbox is identical")
	eq(nameLeaks, 0, "every item model is named Item and every piece Piece")
end

--============================================================================ the ending

local ender = h:join("Keeper", ENDER)
h:advance(0.1)
h.Players:simulateSpawn(ender, h.workspace)
h:advance(0.5)
local bayE = bayOf(ender)
do
	local st = state(ender)
	eq(st.backlog, 499, "the preloaded keeper has 499 of the backlog")
	eq(st.stage, 3, "... and is on stage 3")
	local door = bayE:FindFirstChild("Door")
	walkTo(ender, W(bayE, 0, 3, -32))
	local mark = noticeMark(ender)
	door.Open.Triggered:Fire(ender)
	eq(lastNoticeSince(ender, mark) and lastNoticeSince(ender, mark).text, "Locked. Backlog: 499 / 500.", "the door refuses at 499")
	eq(door.CanCollide, true, "... and stays shut")
	eq(#argsTo(SceneEvent, ender), 0, "... and sends no scene")

	-- one correct first-try sort, read off the world
	walkTo(ender, W(bayE, 0, 3, 0))
	local t = readTray(bayE)[1]
	t.click.MouseClick:Fire(ender)
	h:advance(0.35)
	local entry = state(ender).shift.carried[1]
	local b = readBins(bayE)[answerOf(entry, readRules(bayE))]
	walkTo(ender, binStand(bayE, b.base))
	SelectEvent:simulateFireServer(ender, 1)
	b.prompt.Triggered:Fire(ender)
	eq(state(ender).backlog, 500, "one correct first-try sort clears the backlog")
	truthy(string.find(bayE.BacklogSign.SignGui.Label.Text, "500 / 500", 1, true) ~= nil, "the backlog sign reads 500 / 500")

	local otherDoor = bay1:FindFirstChild("Door")
	local otherBefore = { otherDoor.CanCollide, otherDoor.Transparency }
	walkTo(ender, W(bayE, 0, 3, -32))
	door.Open.Triggered:Fire(ender)
	eq(door.CanCollide, false, "the door opens: CanCollide false")
	eq(door.Transparency, 1, "... and Transparency 1")
	eq(otherDoor.CanCollide, otherBefore[1], "no other bay's door opened")
	eq(otherDoor.Transparency, otherBefore[2], "... at all")
	local scenes = argsTo(SceneEvent, ender)
	eq(#scenes, 1, "the keeper got one Scene")
	eq(scenes[1] and table.concat(scenes[1].lines, "\n"), table.concat(Secret.Note, "\n"), "... carrying the note, verbatim")
	eq(state(ender).endingSeen, true, "endingSeen is set")
	local props = bayE:FindFirstChild("BackRoomProps")
	truthy(props ~= nil and partCount(props) == 2, "the shelf and the key were built")
	local textInProps = 0
	for _, d in (props and props:GetDescendants() or {}) do
		if d:IsA("GuiObject") or d.ClassName == "BillboardGui" or d.ClassName == "SurfaceGui" then textInProps += 1 end
	end
	eq(textInProps, 0, "... and carry no text")
	eq(#argsTo(SceneEvent, p1), 0, "no other player received a Scene")

	-- REVIEW-1 R1-4: every press used to re-send the note AND write the DataStore. A press inside
	-- the cooldown is answered with a toast; a press after it re-sends the note.
	local markDoor = noticeMark(ender)
	door.Open.Triggered:Fire(ender)
	eq(#argsTo(SceneEvent, ender), 1, "a second press inside the cooldown does not re-send the note")
	truthy(#noticesSince(ender, markDoor) > 0, "... and is answered, not silent")
	h:advance(Config.Bay.SceneCooldownSeconds + 0.1)
	door.Open.Triggered:Fire(ender)
	eq(#argsTo(SceneEvent, ender), 2, "pressing E at the open door after the cooldown re-sends the note to its owner")
	print(string.format("  ending: the keeper's bay holds %d Parts with a full tray, the shelf and the key", partCount(bayE)))
	truthy(partCount(bayE) <= Config.Bay.MaxPartsPerBay, "the bay after the ending holds " .. partCount(bayE) .. " Parts (<= 120)")

	h:leave(ender)
	h:advance(0.5)
	local rec = store:GetAsync("u_" .. ENDER)
	eq(rec and rec.data and rec.data.endingSeen, true, "endingSeen is in the store")
	local again = h:join("Keeper", ENDER)
	h:advance(0.1)
	eq(state(again).endingSeen, true, "endingSeen persists across a rejoin")
	h:leave(again)
	h:advance(0.5)
end

--============================================================================ the session lock

do
	local locked = h:join("Elsewhere", LOCKED)
	h:advance(0.1)
	h.Players:simulateSpawn(locked, h.workspace)
	h:advance(0.5)
	local st = state(locked)
	eq(st.canSave, false, "a player whose record is locked by another live session is read-only")
	eq(st.cash, 777, "... but still plays with their real data")
	local told = false
	for _, n in argsTo(NoticeEvent, locked) do
		if n.text == "Progress will not save this session." then told = true end
	end
	truthy(told, "... and is told progress will not save")
	-- earn something, then leave
	local bayL = bayOf(locked)
	walkTo(locked, W(bayL, 0, 3, 0))
	readTray(bayL)[1].click.MouseClick:Fire(locked)
	h:advance(0.35)
	local entry = state(locked).shift.carried[1]
	local b = readBins(bayL)[answerOf(entry, readRules(bayL))]
	walkTo(locked, binStand(bayL, b.base))
	SelectEvent:simulateFireServer(locked, 1)
	b.prompt.Triggered:Fire(locked)
	truthy(state(locked).cash > 777, "the read-only player earned in memory")
	h:advance(Config.Save.AutosaveSeconds + 1)
	h:leave(locked)
	h:advance(0.5)
	local rec = store:GetAsync("u_" .. LOCKED)
	eq(rec.data.cash, 777, "the lock holder's saved cash was not clobbered")
	eq(rec.lock and rec.lock.token, "ANOTHER-SERVER-SESSION", "... nor its lock")
end

--============================================================================ persistence across a rejoin

do
	local before = state(p1)
	-- the tray this session dealt for the next career shift, as a player sees it
	if before.shift.state ~= "ARMED" then waitForArmed(p1) end
	before = state(p1)
	local trayBefore = {}
	for _, t in readTray(bay1) do table.insert(trayBefore, t.line .. "/" .. t.name) end
	h:leave(p1)
	h:advance(0.5)
	local rec = store:GetAsync("u_" .. P1)
	local nonString = 0
	local function walk(t)
		for k, v in t do
			if type(k) ~= "string" then nonString += 1 end
			if type(v) == "table" then walk(v) end
		end
	end
	walk(rec)
	eq(nonString, 0, "every key in the saved record is a string")
	eq(rec.lock, nil, "leaving released the lock")
	truthy(bay1:FindFirstChild("BayPad").Enabled == false, "the freed bay's pad is disabled")
	eq(#readTray(bay1), 0, "the freed bay's tray is empty")

	local back = h:join("Sorter", P1)
	h:advance(0.1)
	local st = state(back)
	eq(st.cash, before.cash, "cash survived the rejoin (" .. tostring(before.cash) .. ")")
	eq(st.cartLevel, before.cartLevel, "cart level survived")
	eq(st.shoesLevel, before.shoesLevel, "shoes level survived")
	-- the shift in progress at leave time is discarded and does not count
	eq(st.shifts, before.shifts, "shifts survived (" .. tostring(before.shifts) .. ")")
	eq(st.backlog, before.backlog, "backlog survived (" .. tostring(before.backlog) .. ")")
	eq(bayOf(back), bay1, "the freed bay was recycled for the rejoin")
	-- REPLAYABLE RNG (checklist): the seed mixes in a per-session salt, so leaving and rejoining on
	-- the SAME career shift deals a different depot. Without the salt it would be the same tray,
	-- memorisable and farmable.
	eq(state(back).shifts, before.shifts, "CONTROL: the rejoin is on the same career shift")
	local trayAfter = {}
	for _, t in readTray(bay1) do table.insert(trayAfter, t.line .. "/" .. t.name) end
	truthy(#trayBefore == 8 and #trayAfter == 8, "CONTROL: both trays were dealt")
	truthy(table.concat(trayBefore, ";") ~= table.concat(trayAfter, ";"),
		"a rejoin on the same career shift deals a different tray (the salt is in the seed)")
	p1 = back
end

--============================================================================ nothing secret on the wire

do
	-- 1. Secret is not in ReplicatedStorage, and no shared source contains its strings.
	eq(h.ReplicatedStorage:FindFirstChild("Secret"), nil, "Secret is not a ReplicatedStorage module")
	local needles = {}
	for _, line in Secret.Note do
		if #line >= 12 then table.insert(needles, line) end
	end
	local codeNeedles = {}
	for code in Secret.Codes do table.insert(codeNeedles, code) end
	local sharedHits = 0
	for key, entry in bundle do
		if string.match(key, "^shared/") or string.match(key, "^client/") then
			for _, n in needles do
				if string.find(entry.source, n, 1, true) then sharedHits += 1 end
			end
			for _, c in codeNeedles do
				if string.find(entry.source, '"' .. c .. '"', 1, true) or string.find(entry.source, c .. " =", 1, true) then
					sharedHits += 1
				end
			end
		end
	end
	eq(sharedHits, 0, "no replicated source (shared or client) contains a note line or a code")

	-- 2. Nothing in the replicated tree renders or names them.
	local worldHits = 0
	local attrs = 0
	local function scan(root)
		for _, d in root:GetDescendants() do
			for name in d:GetAttributes() do
				attrs += 1
				print("  attribute: " .. d:GetFullName() .. " :: " .. name)
			end
			local texts = { d.Name }
			local cls = d.ClassName
			if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then table.insert(texts, d.Text) end
			if cls == "ProximityPrompt" then
				table.insert(texts, d.ActionText)
				table.insert(texts, d.ObjectText)
			end
			if cls == "StringValue" then table.insert(texts, d.Value) end
			for _, t in texts do
				if type(t) == "string" then
					for _, n in needles do
						if string.find(t, n, 1, true) then worldHits += 1 end
					end
					for _, c in codeNeedles do
						if string.find(t, c, 1, true) then worldHits += 1 end
					end
				end
			end
		end
	end
	scan(h.workspace)
	scan(h.ReplicatedStorage)
	eq(attrs, 0, "no attribute on any Instance under Workspace or ReplicatedStorage")
	eq(worldHits, 0, "no note line or code appears anywhere in the replicated world")

	-- 3. No remote payload to anyone but the keeper carries a note line; no payload to a player who
	-- never typed a code carries its name.
	local function deepFind(v, needle)
		if type(v) == "string" then return string.find(v, needle, 1, true) ~= nil end
		if type(v) == "table" then
			for k, x in v do
				if deepFind(k, needle) or deepFind(x, needle) then return true end
			end
		end
		return false
	end
	local payloadHits = 0
	for _, remote in remotes:GetChildren() do
		if remote.ClassName == "RemoteEvent" then
			for _, rec in remote:getSent() do
				local to = rec.player
				local uid = to and to.UserId
				for _, n in needles do
					if uid ~= ENDER and deepFind(rec.args, n) then
						payloadHits += 1
						print("  note line sent to " .. tostring(uid) .. " via " .. remote.Name)
					end
				end
				if rec.all then
					for _, c in codeNeedles do
						if deepFind(rec.args, c) then payloadHits += 1 end
					end
				elseif uid ~= P1 and uid ~= FAILER then
					for _, c in codeNeedles do
						if deepFind(rec.args, c) then
							payloadHits += 1
							print("  code sent to " .. tostring(uid) .. " via " .. remote.Name)
						end
					end
				end
			end
		end
	end
	eq(payloadHits, 0, "the note reached only its keeper, and code names only the players who typed them")

	-- 4. THE STATE PAYLOAD'S SHAPE IS AN ALLOWLIST, like the attribute list. Every key path the
	-- server ever sent is listed here and nothing else may appear: an `answer`, a `bin`, a `seed`
	-- or the cart queue added to any level is a failure, whatever it is called. Array indices are
	-- folded to `#`. Each entry below is public: the owner's own progress, the tag text of items
	-- in their own hands, the memo line on the board, and on career shift 1 the tutorial's fixed
	-- target.
	local ALLOWED_PATHS = {}
	for _, p in {
		"loaded", "bayName", "cash", "cartLevel", "shoesLevel", "carry", "walkSpeed", "prices", "prices.cart",
		"prices.shoes", "nextCarry", "nextSpeed", "stage", "newLayer", "manual", "manual.#", "manual.#.layer",
		"manual.#.lines", "manual.#.lines.#", "shifts", "perfects", "best", "backlog", "backlogSize",
		"endingSeen", "canSave", "shift", "shift.state", "shift.careerShift", "shift.endsAt", "shift.serverNow",
		"shift.secondsLeft", "shift.cleared", "shift.total", "shift.combo", "shift.misfiles", "shift.memo",
		"shift.carried", "shift.carried.#", "shift.carried.#.tag", "shift.carried.#.rich", "shift.carried.#.name",
		"shift.carried.#.misfiled", "shift.selected", "shift.tutorial", "shift.tutorial.index",
		"shift.tutorial.step", "shift.tutorial.item", "shift.tutorial.letter", "shift.tutorial.bin",
		"shift.tutorial.slot",
		-- which of the player's OWN hotbar slots holds the tutorial item, for "select it first"
		-- (REVIEW-1 R2-2); an index into their own hands, which the payload already lists
		"shift.tutorial.hotbar",
		"shift.summary", "shift.summary.sorted", "shift.summary.total",
		"shift.summary.misfiles", "shift.summary.pay", "shift.summary.bonus", "shift.summary.perfect",
		"shift.summary.timedOut", "shift.summary.backlogGained", "shift.summary.seconds", "shift.summary.best",
	} do
		ALLOWED_PATHS[p] = true
	end
	local unknownPaths, tutorialAfterOne, payloads = {}, 0, 0
	local function walkPayload(v, path)
		if type(v) ~= "table" then return end
		for k, x in v do
			local seg = if type(k) == "number" then "#" else tostring(k)
			local p = if path == "" then seg else path .. "." .. seg
			if not ALLOWED_PATHS[p] then unknownPaths[p] = true end
			walkPayload(x, p)
		end
	end
	for _, rec in StateEvent:getSent() do
		payloads += 1
		local st = rec.args[1]
		walkPayload(st, "")
		if type(st) == "table" and st.shift and st.shift.tutorial and st.shift.careerShift ~= 1 then
			tutorialAfterOne += 1
		end
	end
	local list = {}
	for p in unknownPaths do table.insert(list, p) end
	table.sort(list)
	eq(#list, 0, "every key path in all " .. payloads .. " State payloads is on the public allowlist"
		.. (if #list > 0 then " (unlisted: " .. table.concat(list, ", ") .. ")" else ""))
	eq(tutorialAfterOne, 0, "a tutorial target is only ever sent on career shift 1")

	-- 5. A carried item's entry never names its answer before a misfile has paid for it.
	local early = 0
	for _, rec in StateEvent:getSent() do
		local st = rec.args[1]
		for _, e in (type(st) == "table" and st.shift and st.shift.carried or {}) do
			if not e.misfiled then
				for _, binName in Config.Rules.BinNames do
					if string.find(e.tag, binName, 1, true) or string.find(e.rich, binName, 1, true) then early += 1 end
				end
			end
		end
	end
	eq(early, 0, "no un-misfiled carried item's entry contains a bin name")
end

--============================================================================ every prompt is reachable

do
	local bay = bayOf(p1)
	h.Players:simulateSpawn(p1, h.workspace)
	h:advance(0.5)
	local collid = {}
	for _, d in bay:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then table.insert(collid, d) end
	end
	local function insideSolid(pos)
		for _, part in collid do
			local rel = pos - part.Position
			local hs = part.Size / 2
			-- axis-aligned only (walls and fixtures here are axis-aligned except bin sides, which are
			-- checked against the bin's own standing ring instead)
			if part.Name ~= "SideFront" and part.Name ~= "SideBack" and part.Name ~= "SideLeft" and part.Name ~= "SideRight"
				and part.Name ~= "Base"
				and math.abs(rel.X) < hs.X and math.abs(rel.Y) < hs.Y and math.abs(rel.Z) < hs.Z then
				return part.Name
			end
		end
		return nil
	end
	local unreachable = {}
	local function check(label, stand, target, maxDist)
		local blocked = insideSolid(stand)
		local d = (stand - target.Position).Magnitude
		if blocked or d > maxDist then
			table.insert(unreachable, string.format("%s (%.2f studs, blocked by %s)", label, d, tostring(blocked)))
		end
	end
	local P0 = W(bay, 0, 3, 0)
	local pad = bay:FindFirstChild("BayPad")
	local padStand = pad.Position + Vector3.new(0, 3, 0)
	for s = 1, 8 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		check("Slot_" .. s .. " from P", P0, slot, slot:FindFirstChildOfClass("ClickDetector").MaxActivationDistance)
		check("Slot_" .. s .. " from the pad", padStand, slot, slot:FindFirstChildOfClass("ClickDetector").MaxActivationDistance)
	end
	local nearestOther = math.huge
	for k = 1, 6 do
		local base = bay:FindFirstChild("Bin_" .. k).Base
		local stand = binStand(bay, base)
		check("Bin_" .. k .. ".Drop", stand, base, base.Drop.MaxActivationDistance)
		for j = 1, 6 do
			if j ~= k then
				nearestOther = math.min(nearestOther, (stand - bay:FindFirstChild("Bin_" .. j).Base.Position).Magnitude)
			end
		end
	end
	truthy(nearestOther > 6, string.format("from any bin's stand point, no OTHER bin's Drop prompt is in range (nearest %.2f)", nearestOther))
	check("Tray.PutBack", P0, bay.Tray, bay.Tray.PutBack.MaxActivationDistance)
	check("Locker.Cart", W(bay, 12, 3, 13), bay.Locker, bay.Locker.Cart.MaxActivationDistance)
	check("Locker.Shoes", W(bay, 12, 3, 13), bay.Locker, bay.Locker.Shoes.MaxActivationDistance)
	check("Door.Open", W(bay, 0, 3, -32), bay.Door, bay.Door.Open.MaxActivationDistance)
	eq(#unreachable, 0, "every prompt and click has a standable point inside its activation distance"
		.. (if #unreachable > 0 then ": " .. table.concat(unreachable, "; ") else ""))
	local lockerFromPad = (padStand - bay.Locker.Position).Magnitude
	truthy(lockerFromPad > bay.Locker.Cart.MaxActivationDistance,
		string.format("the locker's prompts are out of range from the pad (%.2f), so the tray is the only thing in reach at spawn", lockerFromPad))

	-- and the server agrees from those points (the play above already used every one of them)
	local drops, enabledWhileEmpty = 0, 0
	for k = 1, 6 do
		drops += 1
		if bay:FindFirstChild("Bin_" .. k).Base.Drop.Enabled then enabledWhileEmpty += 1 end
	end
	eq(enabledWhileEmpty, 0, "with empty hands, all " .. drops .. " Drop prompts are disabled")
	eq(bay.Tray.PutBack.Enabled, false, "... and so is PutBack")

	-- PutBack from the pick point
	h:advance(1)
	if state(p1).shift.state ~= "ARMED" and state(p1).shift.state ~= "RUNNING" then waitForArmed(p1) end
	walkTo(p1, P0)
	readTray(bay)[1].click.MouseClick:Fire(p1)
	h:advance(0.35)
	eq(bay.Tray.PutBack.Enabled, true, "PutBack switches on while carrying")
	local carriedBefore = #state(p1).shift.carried
	bay.Tray.PutBack.Triggered:Fire(p1)
	h:advance(0.35)
	eq(#state(p1).shift.carried, carriedBefore - 1, "PutBack from the pick point returns the item")
	eq(#readTray(bay), 8, "... to the tray")
end

--============================================================================ dying mid-shift, and a shutdown

do
	local bay = bayOf(p1)
	local P0 = W(bay, 0, 3, 0)
	walkTo(p1, P0)
	local tray = readTray(bay)
	tray[1].click.MouseClick:Fire(p1)
	h:advance(0.35)
	local st = state(p1)
	eq(st.shift.state, "RUNNING", "CONTROL: a shift is running")
	eq(#st.shift.carried, 1, "CONTROL: one item in hand")
	local endsAt = st.shift.endsAt
	local carriedTag = st.shift.carried[1].tag .. "/" .. st.shift.carried[1].name

	-- a reset: the Humanoid dies and a new character arrives
	humOf(p1).Health = 0
	humOf(p1).Died:Fire()
	h.Players:simulateSpawn(p1, h.workspace)
	h:advance(0.5)
	st = state(p1)
	eq(#st.shift.carried, 0, "after a death the hands are empty")
	eq(st.shift.state, "RUNNING", "the clock keeps running through a death")
	eq(st.shift.endsAt, endsAt, "... unchanged")
	do
		local r = hrpOf(p1)
		truthy(math.abs(r.Position.X - bay.BayPad.Position.X) <= 3 and math.abs(r.Position.Z - bay.BayPad.Position.Z) <= 3,
			"the respawn is on the player's own pad")
	end
	local function onTray()
		for _, t in readTray(bay) do
			if t.line .. "/" .. t.name == carriedTag then return true end
		end
		return false
	end
	-- The slot it came from had already refilled, so a full tray sends it to the front of the
	-- cart: take one item off and it has to be the next one to roll in.
	local viaCart = not onTray()
	if viaCart then
		walkTo(p1, P0)
		readTray(bay)[1].click.MouseClick:Fire(p1)
		h:advance(0.35)
	end
	truthy(onTray(), "... and the carried item is back on the tray" .. (if viaCart then " (via the front of the cart)" else ""))
	if viaCart then
		bay.Tray.PutBack.Triggered:Fire(p1)
		h:advance(0.35)
	end

	-- a shutdown saves everyone and releases their locks
	walkTo(p1, P0)
	readTray(bay)[1].click.MouseClick:Fire(p1)
	h:advance(0.35)
	local entry = state(p1).shift.carried[1]
	local b = readBins(bay)[answerOf(entry, readRules(bay))]
	walkTo(p1, binStand(bay, b.base))
	SelectEvent:simulateFireServer(p1, 1)
	b.prompt.Triggered:Fire(p1)
	local cashNow = state(p1).cash
	local stored = store:GetAsync("u_" .. P1)
	truthy(stored.data.cash ~= cashNow, "CONTROL: the store is behind the live cash before the shutdown")
	h.services.runBindToClose()
	stored = store:GetAsync("u_" .. P1)
	eq(stored.data.cash, cashNow, "BindToClose wrote the live cash")
	eq(stored.lock, nil, "... and released the lock")
end

--============================================================================ glyphs

do
	local ALLOWED = { [0x2014] = true, [0x2026] = true, [0x2605] = true, [0x1F512] = true, [0xFE0F] = true }
	local unseen, sample = {}, {}
	local function inspect(s, where)
		if type(s) ~= "string" or s == "" then return end
		local ok = pcall(function()
			for _, cp in utf8.codes(s) do
				if cp >= 0x2000 and not ALLOWED[cp] then
					unseen[cp] = (unseen[cp] or 0) + 1
					sample[cp] = sample[cp] or where
				end
			end
		end)
		if not ok then
			unseen[-1] = (unseen[-1] or 0) + 1
			sample[-1] = where .. " (not valid UTF-8)"
		end
	end
	for _, d in h.workspace:GetDescendants() do
		local cls = d.ClassName
		if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then inspect(d.Text, d:GetFullName()) end
		if cls == "ProximityPrompt" then
			inspect(d.ActionText, d:GetFullName())
			inspect(d.ObjectText, d:GetFullName())
		end
	end
	for _, remote in remotes:GetChildren() do
		for _, rec in (if remote.ClassName == "RemoteEvent" then remote:getSent() else {}) do
			local function walk(v, where)
				if type(v) == "string" then inspect(v, where) elseif type(v) == "table" then
					for k, x in v do walk(x, where .. "." .. tostring(k)) end
				end
			end
			walk(rec.args, remote.Name)
		end
	end
	local n = 0
	for cp, count in unseen do
		n += 1
		print(string.format("  UNSEEN GLYPH U+%04X, %d time(s), first at %s", cp, count, sample[cp]))
	end
	eq(n, 0, "every glyph in the world and in every payload is ASCII, Latin-1 or one of the four photographed glyphs")
end

--============================================================================ nothing went wrong quietly

for _, e in h:errors() do
	print("scheduler error: " .. e)
end
eq(#h:errors(), 0, "no server thread died")
local unexpectedWarn = 0
for _, w in h.warnings do
	print("server warned: " .. w)
	if not string.find(w, "READ-ONLY", 1, true) and not string.find(w, "load failed", 1, true)
		and not string.find(w, "save failed", 1, true) and not string.find(w, "redeem write failed", 1, true) then
		unexpectedWarn += 1
	end
end
eq(unexpectedWarn, 0, "the server warned about nothing but the injected lock and store failures")
print(string.format("  total walked by the check: %.0f studs", totalWalked))

print(string.format("lost-found-depot: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot check failed", 0) end
