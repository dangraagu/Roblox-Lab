-- Lost & Found Depot — what the HUD DOES across a player's first two shifts, on a phone.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_hudflow.luau
--
-- check_lostfounddepot_hud.luau measures where panels SIT. This file drives the real server and the
-- real Hud.client through the flows REVIEW-1 found broken, and asserts what a player would see:
--   R2-2  the tutorial hint follows the SELECTED item (E deposits the selected item), including
--         "select it first" when a tutorial item is in the hands but another one is selected;
--   R2-5  on a phone, an open MANUAL drawer hid every toast: a refusal or a misfile explanation
--         arrived and was drawn invisible. The drawer that opens itself for a new layer also kept
--         the hotbar hidden into the running shift;
--   R2-4  the Back Room note sets the camera Scriptable. Closing the note any way but its own
--         CLOSE button (a top-edge toggle, the shift summary) left the camera stuck there, into
--         the next shift.
--
-- Roblox queues RemoteEvent traffic fired before a client connects; the emulator does not, so the
-- server's real payloads are replayed from the remote's own recording right after the HUD loads
-- (as tests/walk.luau does). The note for R2-4 is replayed from the server's own Secret module
-- through the real Scene remote (as check_lostfounddepot_hud.luau does): reaching the door for real
-- takes 500 sorts, and the camera is client behaviour.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local W_, H_ = 800, 360
local h = Harness.new({ bundle = bundle, name = "lost-found-depot-hudflow", viewport = { W_, H_ }, touch = true })
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
do
	local realRandom = Random
	Random = { new = function(seed) return realRandom.new(seed or 8086) end }
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot hudflow: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local Rules = h:_require(h.ReplicatedStorage:FindFirstChild("Rules"))
local Secret = h:_require(h.services.ServerScriptService:FindFirstChild("Secret"))
local remotes = h.ReplicatedStorage:FindFirstChild("DepotRemotes")
local StateEvent, NoticeEvent, SceneEvent, SelectEvent = remotes.State, remotes.Notice, remotes.Scene, remotes.Select

local me = h:join("Phone", 616161)
h:advance(0.1)
local okHud, hudErr = h:tryRun("client/Hud.client")
truthy(okHud, "the HUD loads" .. (if okHud then "" else ": " .. tostring(hudErr)))
for _, remote in { StateEvent, NoticeEvent } do
	for _, r in remote:sentTo(me) do remote:FireClient(me, table.unpack(r.args, 1, r.args.n)) end
end
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)

local root = me.PlayerGui.DepotHud.Root
local camera = h.workspace.CurrentCamera
local bay = me.RespawnLocation.Parent
local ox = bay.BayPad.Position.X
local P = Vector3.new(ox, 3, 0)
local function state() local s = StateEvent:sentTo(me) return s[#s].args[1] end
local function hrp() return me.Character.HumanoidRootPart end
local BIN_OF_NAME, LETTER_OF_NAME = {}, {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end
local function binNamed(name)
	for k = 1, 6 do
		local m = bay:FindFirstChild("Bin_" .. k)
		if m.Sign.SignGui.Label.Text == name then return m end
	end
end
local function standAt(m)
	local b = m.Base.Position
	local flat = Vector3.new(b.X, 3, b.Z)
	hrp().CFrame = CFrame.new(flat + (P - flat).Unit * 5)
end
-- The tutorial item the server is pointing at, by the slot its payload names (what the HUD's TAP
-- HERE marker uses). NOT "the first slot whose tag says Phone": a random item on the same tray can
-- be a Phone too, and picking that one is not the tutorial.
local function tutorialSlot(name)
	local t = state().shift.tutorial
	assert(t and t.item == name and t.step == "pick" and t.slot, "the tutorial is not pointing at " .. name .. " on the tray")
	return bay:FindFirstChild("Slot_" .. t.slot)
end
local function readRules()
	local text = bay.MemoBoard.SignGui.Label.Text
	for _, m in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, m), 1, true) then return Rules.withMemo(Config, m) end
	end
	return Rules.base(Config)
end
local function answerName(entry)
	local mis = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
	if mis then return mis end
	local id = Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], readRules())
	return Config.Rules.BinNames[id]
end
local function misfiles() return state().shift.misfiles end
local function rect(name)
	for _, r in h:guiRects(me.PlayerGui.DepotHud, W_, H_) do
		if r.name == name then return r end
	end
end

--============================================================================ R2-2: the tutorial follows the selection

-- REVIEW-1 pass 3 (U2) changed WHICH item is selected, not this rule: a pick no longer moves the
-- selection, so the tutorial item is "in the hands but not selected" when another item was picked
-- BEFORE it. The hint must then say to select it first, and on a phone say "tap Drop" (U4).
do
	eq(root.Hint.Text, "Tap the Teddy Bear on the tray.", "CONTROL: the first hint")
	-- a first pick that is NOT a tutorial item: the first front-row slot holding anything else
	local other
	for s = 1, 4 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		if slot.Tag.Enabled and slot.Tag.ItemName.Text ~= "Phone" and slot.Tag.ItemName.Text ~= "Teddy Bear" then
			other = slot
			break
		end
	end
	hrp().CFrame = CFrame.new(P)
	other.ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	hrp().CFrame = CFrame.new(ox, 3.51, 14) -- the pad
	tutorialSlot("Teddy Bear").ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	local st = state()
	eq(#st.shift.carried, 2, "CONTROL: carrying another item and the Teddy")
	eq(st.shift.carried[st.shift.selected].name ~= "Teddy Bear", true, "CONTROL: the other item is selected (picked first)")
	truthy(string.find(root.Hint.Text, "Teddy Bear", 1, true) ~= nil and string.find(root.Hint.Text, "hotbar", 1, true) ~= nil,
		"R2-2: with another item selected, the hint says to select the Teddy in the hotbar first: " .. root.Hint.Text)
	eq(me.PlayerGui.TutorialBinMarker.Enabled, false, "... and no bin marker points at a bin yet")
	-- tap the Teddy's hotbar slot, the real button
	local teddyIndex
	for i, e in st.shift.carried do
		if e.name == "Teddy Bear" then teddyIndex = i end
	end
	root.Hotbar["Slot_" .. teddyIndex].Activated:Fire()
	h:advance(0.2)
	eq(root.Hint.Text, "T means TOYS. Walk to the TOYS bin and tap Drop.", "after selecting it, the hint says where it goes")
	eq(me.PlayerGui.TutorialBinMarker.Adornee and me.PlayerGui.TutorialBinMarker.Adornee.Parent.Sign.SignGui.Label.Text, "TOYS",
		"... and the marker is over TOYS")
	local toys = binNamed("TOYS")
	standAt(toys)
	toys.Base.Drop.Triggered:Fire(me)
	eq(misfiles(), 0, "doing what the hint said sorted the Teddy")

	-- deliver the other item, then the same case for the Phone
	st = state()
	local m = binNamed(answerName(st.shift.carried[1]))
	standAt(m)
	SelectEvent:simulateFireServer(me, 1)
	m.Base.Drop.Triggered:Fire(me)
	eq(misfiles(), 0, "CONTROL: the other item sorted")
	h:advance(0.4)

	hrp().CFrame = CFrame.new(P)
	local phoneSlot = state().shift.tutorial.slot
	for s = 1, 8 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		if slot.Tag.Enabled and s ~= phoneSlot then
			slot.ClickDetector.MouseClick:Fire(me)
			break
		end
	end
	h:advance(0.35)
	tutorialSlot("Phone").ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	st = state()
	eq(#st.shift.carried, 2, "CONTROL: carrying one more item and the tutorial Phone")
	eq(st.shift.carried[2].name, "Phone", "CONTROL: the Phone was picked second")
	eq(st.shift.selected, 1, "CONTROL: the first pick is selected, not the Phone")
	-- a player who does NOT read the hint and presses E at KEYS & WALLETS deposits the selected item;
	-- the check here is on the HINT, which must not send them there without selecting first
	truthy(string.find(root.Hint.Text, "hotbar", 1, true) ~= nil, "R2-2: the Phone in hand but unselected: the hint says to select it: "
		.. root.Hint.Text)
	for i, e in st.shift.carried do
		if e.name == "Phone" then root.Hotbar["Slot_" .. i].Activated:Fire() end
	end
	h:advance(0.2)
	truthy(string.find(root.Hint.Text, "K means KEYS & WALLETS", 1, true) ~= nil, "after selecting the Phone the hint names KEYS & WALLETS: "
		.. root.Hint.Text)
	local keys = binNamed("KEYS & WALLETS")
	standAt(keys)
	keys.Base.Drop.Triggered:Fire(me)
	eq(misfiles(), 0, "R2-2: following every hint through the tutorial never misfiled")
end

--============================================================================ finish shift 1

do
	for _ = 1, 800 do
		local st = state()
		if st.shift.state == "SUMMARY" then break end
		if #st.shift.carried == 0 then
			hrp().CFrame = CFrame.new(P)
			local n = 0
			for s = 1, 8 do
				local slot = bay:FindFirstChild("Slot_" .. s)
				if slot.Tag.Enabled and n < st.carry then
					slot.ClickDetector.MouseClick:Fire(me)
					n += 1
				end
			end
			h:advance(0.35)
		else
			local m = binNamed(answerName(st.shift.carried[1]))
			standAt(m)
			SelectEvent:simulateFireServer(me, 1)
			m.Base.Drop.Triggered:Fire(me)
			h:advance(0.05)
		end
	end
	eq(state().shift.state, "SUMMARY", "CONTROL: shift 1 finished")
	eq(state().shift.summary.sorted, 30, "CONTROL: all 30 sorted")
end

--============================================================================ R2-5: toasts over an open drawer

do
	for _ = 1, 40 do
		if state().shift.state == "ARMED" then break end
		h:advance(0.5)
	end
	eq(state().stage, 2, "CONTROL: shift 2 is stage 2")
	eq(root.ManualDrawer.Visible, true, "CONTROL: the MANUAL drawer opened itself for the new layer")
	-- a refused pick from across the bay, with the drawer up
	hrp().CFrame = CFrame.new(ox + 30, 3, -24)
	bay.Slot_1.ClickDetector.MouseClick:Fire(me)
	eq(root.Toast.Text, "Too far - walk up to the tray.", "CONTROL: the HUD received the refusal")
	eq(root.Toast.Visible, true, "R2-5: with the MANUAL drawer open on a phone, the refusal toast is visible")
	local t, d = rect("Toast"), rect("ManualDrawer")
	truthy(t ~= nil and d ~= nil and t.shown and d.shown, "CONTROL: both the toast and the drawer are on screen")
	if t and d then
		local overlapY = math.min(t.sy + t.sh, d.sy + d.sh) - math.max(t.sy, d.sy)
		local overlapX = math.min(t.sx + t.sw, d.sx + d.sw) - math.max(t.sx, d.sx)
		truthy(not (overlapX > 1 and overlapY > 1), string.format(
			"... and the drawer does not cover it (toast y %.0f..%.0f, drawer y %.0f..%.0f)", t.sy, t.sy + t.sh, d.sy, d.sy + d.sh))
		truthy(t.sy >= 0 and t.sy + t.sh <= H_, "... and it is on screen")
	end

	-- the first pickup closes the drawer that opened itself, and the hotbar comes back
	hrp().CFrame = CFrame.new(P)
	bay.Slot_1.ClickDetector.MouseClick:Fire(me)
	h:advance(0.35)
	eq(state().shift.state, "RUNNING", "CONTROL: the first pickup started the clock")
	eq(root.ManualDrawer.Visible, false, "R2-5: the drawer that opened itself closes at the first pickup")
	eq(root.Hotbar.Visible, true, "... and the hotbar is back")

	-- a drawer the PLAYER opens stays open, and a misfile toast still shows over it
	root.Toggles.Toggle_manual.Activated:Fire()
	eq(root.ManualDrawer.Visible, true, "CONTROL: the player opened MANUAL mid-shift")
	local st = state()
	local right = answerName(st.shift.carried[1])
	local wrongName
	for _, n in Config.Rules.BinNames do
		if n ~= right then wrongName = n break end
	end
	local wrong = binNamed(wrongName)
	standAt(wrong)
	SelectEvent:simulateFireServer(me, 1)
	wrong.Base.Drop.Triggered:Fire(me)
	truthy(string.sub(root.Toast.Text, 1, 6) == "-8 s. ", "CONTROL: the misfile toast arrived: " .. root.Toast.Text)
	eq(root.Toast.Visible, true, "R2-5: a misfile explanation is visible over the open MANUAL drawer")
	eq(root.ManualDrawer.Visible, true, "... and the drawer the player opened stays open")
	root.Toggles.Toggle_manual.Activated:Fire()
end

--============================================================================ R2-4: the note camera

local function sendNote()
	SceneEvent:FireClient(me, { lines = Secret.Note, camFrom = { ox, 7, -24 }, camTo = { ox, 5, -47 } })
end
do
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Custom), "CONTROL: the camera starts Custom")
	sendNote()
	eq(root.NoteCard.Visible, true, "CONTROL: the note card is up")
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Scriptable), "CONTROL: the note flies the camera (Scriptable)")
	root.Toggles.Toggle_manual.Activated:Fire()
	eq(root.NoteCard.Visible, false, "CONTROL: tapping MANUAL replaced the note")
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Custom), "R2-4: closing the note with a top-edge toggle gives the camera back")
	root.Toggles.Toggle_manual.Activated:Fire()

	sendNote()
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Scriptable), "CONTROL: the note is up again mid-shift")
	h:advance(Config.Shift.Seconds + 1)
	eq(state().shift.state == "SUMMARY" or state().shift.state == "ARMED", true, "CONTROL: the clock ran out")
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Custom), "R2-4: a shift ending under the note gives the camera back")
	for _ = 1, 10 do
		if root.SummaryCard.Visible then root.SummaryCard.OkButton.Activated:Fire() end
	end
	h:advance(Config.Shift.IntermissionSeconds + 1)
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Custom), "... and it stays Custom into the next shift")

	sendNote()
	for _ = 1, 10 do
		if root.NoteCard.Visible then root.NoteCard.CloseButton.Activated:Fire() end
	end
	eq(tostring(camera.CameraType), tostring(Enum.CameraType.Custom), "CONTROL: reading the note to CLOSE gives the camera back")
end

for _, e in h:errors() do print("scheduler error: " .. e) end
eq(#h:errors(), 0, "no server or client thread died")
print(string.format("lost-found-depot hudflow: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot hudflow check failed", 0) end
