-- FACILITY: Endless Nightmare — EVERY CLICK AND KEY, pressed through the real HUD.
--
-- Run:  py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       luau check_facilitynightmare_input.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- check_facilitynightmare.luau fires the remotes directly, and the HUD check only measures where
-- the buttons are. Neither ever pressed one. A button whose handler sends the wrong thing, or
-- sends nothing, passed both. This file boots the real server AND the real client HUD in one
-- harness and plays through the HUD the way a player does: `Activated:Fire()` on the button that
-- is on screen, `UserInputService.InputBegan` for a key. Every assertion is about what the SERVER
-- did as a result (the Humanoid's WalkSpeed, the SpotLight, the store, the phase), never about the
-- client's own idea of it.
--
-- The last section enumerates every TextButton the HUD built and fails if one was never pressed,
-- so a button added later without a test here goes red.
--
-- Movement between rooms is tests/Bot.luau (it knows only what a client could know); everything
-- the player chooses is a HUD press.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")

local h = Harness.new({
	bundle = require("./build/facility-nightmare"),
	name = "facility-nightmare-input",
	viewport = { 800, 360 },
	touch = true, -- a phone: LIGHT and SPRINT are taps
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local UID = 8101
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
-- runs 0: a first-ever run, so the front is HELD on sublevel 1 while the controls are tried out
-- standing in the entry. 60 Essence buys two rank-1 perks.
store:SetAsync("u_" .. UID, { data = { v = 1, essence = 60, essenceEarned = 60, bestSublevel = 0, runs = 0, extractions = 0,
	perks = { deepCell = 0, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } } })
local function stored()
	local rec = store:GetAsync("u_" .. UID)
	return rec and rec.data
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local hub = h.workspace:FindFirstChild("Hub")

-- A spy on the camera juice, installed BEFORE the client requires FxClient (the harness caches a
-- module's value, so the HUD gets this same table).
local FxClient = h:_require(h.ReplicatedStorage:FindFirstChild("FxClient"))
local shakes = {}
do
	local realShake = FxClient.shake
	FxClient.shake = function(...)
		table.insert(shakes, h.scheduler:now())
		return realShake(...)
	end
end

local plr = h:join("Thumbs", UID)
h:advance(0.5)
local okClient, clientErr = h:tryRun("client/Hud.client")
truthy(okClient, "client/Hud.client loads (" .. tostring(clientErr) .. ")")
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)

local bot = Bot.new(h, plr)
local remotes = h.ReplicatedStorage:FindFirstChild("FacilityRemotes")
local NoticeR = remotes:FindFirstChild("Notice")
local UIS = h.game:GetService("UserInputService")
local hudRoot = plr.PlayerGui.FacilityHud.Root

local function hum()
	return plr.Character:FindFirstChildOfClass("Humanoid")
end
local function spot()
	local c = plr.Character
	local host = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
	return host and host:FindFirstChild("Flashlight")
end
local function lightIsOn()
	local s = spot()
	return s ~= nil and s.Enabled == true
end
local function noticesSince(n0)
	local out = {}
	local sent = NoticeR:getSent()
	for i = n0 + 1, #sent do
		if sent[i].player == plr then table.insert(out, sent[i]) end
	end
	return out
end

-- On screen = it and every GuiObject above it Visible, up to an Enabled ScreenGui.
local function shown(obj)
	local o = obj
	while o ~= nil and o.ClassName ~= "ScreenGui" do
		if o.Visible == false then return false end
		o = o.Parent
	end
	return o ~= nil and o.Enabled ~= false
end
local pressedSet = {}
local function press(btn, why)
	truthy(btn ~= nil, why .. ": the button exists")
	if btn == nil then return end
	truthy(shown(btn), why .. ": " .. btn:GetFullName() .. " is on screen when pressed")
	pressedSet[btn] = true
	btn.Activated:Fire()
end
local function key(kc, down)
	local input = { KeyCode = kc, UserInputType = Enum.UserInputType.Keyboard,
		UserInputState = if down then Enum.UserInputState.Begin else Enum.UserInputState.End }
	if down then UIS.InputBegan:Fire(input, false) else UIS.InputEnded:Fire(input, false) end
end
local function tap(kc)
	key(kc, true)
	key(kc, false)
end

--=========================================================================== A. the break room
section("A. break room: PERKS, every BUY, CLOSE")
do
	local perksButton = hudRoot:FindFirstChild("PerksButton")
	local panel = hudRoot:FindFirstChild("Perks")
	eq(shown(panel), false, "the perk panel starts closed")
	press(perksButton, "PERKS")
	h:advance(0.1)
	eq(shown(panel), true, "PERKS opens the perk panel")

	-- Every BUY answers: a purchase or a refusal toast, one notice each, never silence.
	local expect = {
		{ "deepCell", true }, -- 60 -> 35
		{ "nightEyes", true }, -- 35 -> 10
		{ "marathon", false }, -- 10 < 25
		{ "soulAnchor", false },
		{ "secondWind", false }, -- 150
	}
	for _, e in expect do
		local id, buys = e[1], e[2]
		local row = panel.List:FindFirstChild("Row_" .. id)
		local n0 = #NoticeR:getSent()
		local before = stored().perks[id]
		press(row and row:FindFirstChild("BuyButton"), "BUY " .. id)
		h:advance(0.3)
		local answers = noticesSince(n0)
		local kinds = {}
		for _, rec in answers do table.insert(kinds, tostring(rec.args[1])) end
		eq(#answers, 1, "BUY " .. id .. " is answered with exactly one notice (" .. table.concat(kinds, ",") .. ")")
		if buys then
			eq(kinds[1], "purchased", "BUY " .. id .. " buys it")
			eq(stored().perks[id], before + 1, "…and the rank is on disk")
		else
			eq(kinds[1], "toast", "BUY " .. id .. " is refused with a toast")
			eq(stored().perks[id], before, "…and nothing is granted")
		end
	end
	eq(stored().essence, 10, "two rank-1 perks cost 25 + 25 of the 60")

	press(panel:FindFirstChild("CloseButton"), "CLOSE")
	h:advance(0.1)
	eq(shown(panel), false, "CLOSE shuts the perk panel")
	eq(shown(perksButton), true, "…and PERKS is back")
end

--=========================================================================== B. down on the floor
section("B. sublevel 1: LIGHT, F, ButtonY, Shift, SPRINT, L3")
truthy(bot:board(hub) and bot:waitPhase("floor", 6), "walking into the car reaches sublevel 1")
h:advance(0.5)
do
	local lightButton = hudRoot:FindFirstChild("LightButton")
	local sprintButton = hudRoot:FindFirstChild("SprintButton")
	eq(bot:state().run.batteryCap, 55, "control: the Deep Cell bought through the HUD is in the run")

	press(lightButton, "LIGHT on")
	h:advance(0.3)
	eq(lightIsOn(), true, "LIGHT turns the SERVER's flashlight on")
	press(lightButton, "LIGHT off")
	h:advance(0.3)
	eq(lightIsOn(), false, "…and a second tap turns it off")

	tap(Enum.KeyCode.F)
	h:advance(0.3)
	eq(lightIsOn(), true, "F turns it on")
	tap(Enum.KeyCode.F)
	h:advance(0.3)
	eq(lightIsOn(), false, "…and off")
	tap(Enum.KeyCode.ButtonY)
	h:advance(0.3)
	eq(lightIsOn(), true, "gamepad Y turns it on")
	tap(Enum.KeyCode.ButtonY)
	h:advance(0.3)
	eq(lightIsOn(), false, "…and off")

	key(Enum.KeyCode.LeftShift, true)
	h:advance(0.3)
	eq(hum().WalkSpeed, 24, "holding Shift sprints (server WalkSpeed 24)")
	key(Enum.KeyCode.LeftShift, false)
	h:advance(0.3)
	eq(hum().WalkSpeed, 16, "…and letting go walks")
	h:advance(9) -- refill

	press(sprintButton, "SPRINT on")
	h:advance(0.3)
	eq(hum().WalkSpeed, 24, "SPRINT tap sprints")
	h:advance(5)
	eq(hum().WalkSpeed, 16, "…until the stamina runs out")
	h:advance(9) -- the bar refills while the player walks
	eq(bot:state().run.stamina, bot:state().run.staminaCap, "control: stamina is full again")
	-- A phone player does not know the server marked the bar exhausted. One tap must sprint.
	press(sprintButton, "SPRINT after exhaustion")
	h:advance(0.3)
	eq(hum().WalkSpeed, 24, "after running out, ONE tap on SPRINT sprints again")
	press(sprintButton, "SPRINT off")
	h:advance(0.3)
	eq(hum().WalkSpeed, 16, "…and the next tap stops")
	h:advance(9)

	tap(Enum.KeyCode.ButtonL3)
	h:advance(0.3)
	eq(hum().WalkSpeed, 24, "gamepad L3 toggles sprint on")
	tap(Enum.KeyCode.ButtonL3)
	h:advance(0.3)
	eq(hum().WalkSpeed, 16, "…and off")
	h:advance(9)
end

--=========================================================================== C. the choice
section("C. the elevator: DESCEND, then EXTRACT, both pressed")
do
	local r = bot:clearFloor()
	eq(r, "powered", "control: the bot powers sublevel 1")
	h:advance(0.3)
	local choice = hudRoot:FindFirstChild("Choice")
	eq(shown(choice), true, "the choice modal is on screen")
	eq(shown(hudRoot:FindFirstChild("SprintButton")), false, "control: SPRINT is hidden under the modal")
	-- a phone has no E or Q: its labels and hint name none (the desktop check asserts the other side)
	eq(choice:FindFirstChild("ExtractButton").Text, "EXTRACT", "on a phone EXTRACT names no key")
	eq(choice:FindFirstChild("DescendButton").Text, "DESCEND", "…nor does DESCEND")
	eq(hudRoot.Hint.Text, "EXTRACT to bank it, or DESCEND for more.", "…nor the hint")

	-- A sprint toggled on at the exit must not carry into the next floor's lit entry room.
	bot:fire("Sprint", true)
	h:advance(0.3)
	eq(hum().WalkSpeed, 24, "control: sprinting when DESCEND is chosen")
	local essence0 = stored().essence
	press(choice:FindFirstChild("DescendButton"), "DESCEND")
	h:advance(0.3)
	eq(bot:phase(), "ride", "DESCEND starts the ride down")
	eq(shown(choice), false, "…and closes the modal")
	truthy(bot:waitPhase("floor", 6), "…to sublevel 2")
	h:advance(0.3)
	eq(bot:state().run.k, 2, "control: on sublevel 2")
	eq(hum().WalkSpeed, 16, "a sprint request from the last floor does not carry into the new entry room")
	local st0 = bot:state().run.stamina
	h:advance(1)
	eq(bot:state().run.sprinting, false, "…the server is not sprinting a second later")
	truthy(bot:state().run.stamina > st0, string.format("…and the stamina refills there instead of burning (%.2f -> %.2f)", st0, bot:state().run.stamina))

	local r2 = bot:clearFloor()
	eq(r2, "powered", "control: the bot powers sublevel 2")
	h:advance(0.3)
	eq(shown(choice), true, "the choice modal is back")

	-- REVIEW-1 B2. A phone player who powers the lift and steps back out (the game tells them a full
	-- battery leaves a cell "for later") used to keep the modal, which cannot be closed and hid LIGHT
	-- and SPRINT: in the next dark room the dark took them in 2.9-3.1 s on 3 of 3 floors. Walked here
	-- by hand, with no bot ticks, so nothing but a HUD press can turn the flashlight on.
	local CF, V3 = h.instance.datatypes.CFrame, h.instance.datatypes.Vector3
	local function walkByHand(to)
		local hrp = bot:hrp()
		for _ = 1, 600 do
			local p = hrp.Position
			local flat = V3.new(to.X - p.X, 0, to.Z - p.Z)
			if flat.Magnitude < 0.05 then return end
			local stepLen = math.min(flat.Magnitude, 1.6)
			hrp.CFrame = CF.new(V3.new(p.X + flat.X / flat.Magnitude * stepLen, 3, p.Z + flat.Z / flat.Magnitude * stepLen))
			h:advance(0.1)
		end
	end
	local rooms, doors = bot:rooms(), bot:doors()
	local exitRoom = bot:exitRoom(rooms)
	-- wait in the lit lift for an opened neighbour to go dark
	local target
	for _ = 1, 4000 do
		rooms, doors = bot:rooms(), bot:doors()
		for _, d in doors do
			local other = if d.lo == exitRoom then d.hi elseif d.hi == exitRoom then d.lo else nil
			if d.open and other and rooms[other] and rooms[other].light and rooms[other].light.Enabled == false then target = other end
		end
		if target then break end
		h:advance(0.1)
	end
	truthy(target ~= nil, "control: a room next to the powered lift has gone dark")
	if target then
		local lightButton = hudRoot:FindFirstChild("LightButton")
		eq(lightIsOn(), false, "control: the flashlight is off in the lit lift")
		walkByHand((rooms[exitRoom].center + rooms[target].center) / 2)
		walkByHand(rooms[target].center)
		h:advance(0.3) -- one State push
		eq(bot:phase(), "floor", "control: walked into the dark room alive")
		eq(shown(choice), false, "out of the lift, the choice modal gets out of the way")
		eq(shown(lightButton), true, "…LIGHT is on screen")
		eq(shown(hudRoot:FindFirstChild("SprintButton")), true, "…and so is SPRINT")
		eq(hudRoot.Hint.Text, "Your room is dark — turn on your flashlight (F / LIGHT).", "…and the hint says the room is dark, ahead of anything about the lift")
		press(lightButton, "LIGHT in the dark room next to the powered lift")
		local alive = true
		for _ = 1, 60 do
			h:advance(0.1)
			if bot:phase() ~= "floor" then alive = false; break end
		end
		eq(lightIsOn(), true, "…which turns the SERVER's flashlight on")
		truthy(alive, "…and 6 s in the dark room (grace 4 s) the player is still alive")
		eq(hudRoot.Hint.Text, "Back to the freight elevator to EXTRACT or DESCEND.", "the hint points back to the lift")
		walkByHand((rooms[exitRoom].center + rooms[target].center) / 2)
		walkByHand(rooms[exitRoom].center)
		h:advance(0.3)
		eq(shown(choice), true, "back in the lift, the choice is on screen again")
		eq(shown(lightButton), false, "…over LIGHT")
	end
	press(choice:FindFirstChild("ExtractButton"), "EXTRACT")
	h:advance(0.3)
	eq(stored().essence, essence0 + 10 + 15, "EXTRACT banks sublevels 1 and 2: 25")
	truthy(bot:waitPhase("hub", 6), "…and rides back up to the break room")
end

--=========================================================================== D. the dark, felt
section("D. the player's own room going dark shakes the camera (DESIGN.md §11.4)")
do
	truthy(bot:board(hub) and bot:waitPhase("floor", 6), "a second run (runs = 1: the front is not held)")
	local zone
	for _, z in h.workspace.Facility:GetChildren() do
		if z:FindFirstChild("Floor") then zone = z end
	end
	local room = zone and zone.Floor.Rooms:GetChildren()[1]
	local light = room and room:FindFirstChild("Fixture") and room.Fixture:FindFirstChild("RoomLight")
	truthy(light ~= nil, "control: the entry room's light")
	-- The light goes ON once the room starts to flicker (2 s before it dies), so exposure never rises
	-- and the exposure shake cannot stand in for this one. Waiting for the flicker, not a fixed
	-- time: the entry dies at 2 x step, and a sublevel-1 step is floor-dependent (the first sweep
	-- of this file timed out on 4 of 39 floors with a 30 s bound).
	local lit = light.Brightness
	local flickered = false
	for _ = 1, 2400 do
		h:advance(0.05)
		if light.Enabled == false or light.Brightness ~= lit then flickered = true; break end
	end
	truthy(flickered, "control: the entry room starts to flicker")
	press(hudRoot:FindFirstChild("LightButton"), "LIGHT before the dark")
	local tDark
	for _ = 1, 80 do
		if light.Enabled == false then tDark = h.scheduler:now(); break end
		h:advance(0.05)
	end
	truthy(tDark ~= nil, "control: the entry room goes dark")
	h:advance(0.6)
	eq(bot:state().run.exposure, 0, "control: with the light on, no exposure (so no exposure shake)")
	local n = 0
	for _, t in shakes do
		if tDark and t >= tDark - 0.05 and t <= tDark + 0.6 then n += 1 end
	end
	truthy(n >= 1, "the camera shakes when the room around the player dies (" .. n .. " shakes within 0.6 s)")

	press(hudRoot:FindFirstChild("LightButton"), "LIGHT off in the dark")
	local died = false
	for _ = 1, 80 do
		h:advance(0.1)
		if bot:phase() == "dying" then died = true; break end
	end
	truthy(died, "control: with the light off the dark takes the player")
	h:advance(0.2)
	eq(plr.PlayerGui.FacilityOverlay.DeathCard.Visible, true, "the death card covers the screen")
	truthy(bot:waitPhase("hub", 5), "…then the break room")
	h:advance(1)
	eq(plr.PlayerGui.FacilityOverlay.DeathCard.Visible, false, "…and the card is gone")
end

--=========================================================================== E. nothing unpressed
section("E. every button the HUD built was pressed")
do
	local all, missed = 0, {}
	for _, d in plr.PlayerGui:GetDescendants() do
		if d.ClassName == "TextButton" or d.ClassName == "ImageButton" then
			all += 1
			if not pressedSet[d] then table.insert(missed, d:GetFullName()) end
		end
	end
	eq(all, 11, "the HUD builds 11 buttons: PERKS, CLOSE, 5 x BUY, LIGHT, SPRINT, EXTRACT, DESCEND")
	eq(#missed, 0, "every one was pressed here (" .. table.concat(missed, ", ") .. ")")
end

local errs = h:errors()
eq(#errs, 0, "no scheduler errors (" .. table.concat(errs, " | ") .. ")")
eq(#h.warnings, 0, "no warnings (" .. table.concat(h.warnings, " | ") .. ")")
print(string.format("check_facilitynightmare_input: %d passed, %d failed", passed, failed))
