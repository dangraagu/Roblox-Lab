-- FACILITY: Endless Nightmare — a MOUSE AND KEYBOARD player, through the real server and HUD.
--
-- Run:  py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       luau check_facilitynightmare_desktop.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Written for REVIEW-1. check_facilitynightmare_input.luau plays a PHONE (touch = true), where a tap
-- lands wherever it is aimed. A PC player is different in one way nothing headless can see: on the
-- floor the server holds them in Enum.CameraMode.LockFirstPerson, and Roblox's PlayerModule then
-- sets UserInputService.MouseBehavior = LockCenter. The cursor is pinned to the screen centre,
-- which on a 1280x720 screen falls in the 12 px gap between EXTRACT and DESCEND. The engine lets
-- the cursor go only while a VISIBLE GuiButton has Modal = true. Before this pass no button did and
-- no key chose, so a PC player who powered the elevator could not extract or descend at all
-- (finding B1, "critical").
--
-- The emulator does not model the cursor. What this file CAN assert is everything the fix is made
-- of, on the real HUD: the Modal flag is up exactly while a modal panel is on screen (and down while
-- exploring, or mouse-look would break), the E and Q keys choose, the labels name the keys, the
-- server's CameraMinZoomDistance puts the break-room camera past first person. Whether the engine
-- then frees the cursor is on the "needs Studio" list.
--
-- Section E is finding B3: a run that stalls in the unpowered elevator room now ends by itself.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")

local h = Harness.new({
	bundle = require("./build/facility-nightmare"),
	name = "facility-nightmare-desktop",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

-- Roblox PlayerModule BaseCamera: a subject distance below FIRST_PERSON_DISTANCE_THRESHOLD (1.0) is
-- first person. Written out, not read from Config.
local FIRST_PERSON_THRESHOLD = 1
local GRACE, RIDE = 4, 4

local UID = 8301
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
-- Deep Cell 3 (75 s of battery), as check_facilitynightmare.luau's VET and for the same reason: a
-- perk-less 16 studs/s bot dies on sublevel 1 on a few unlucky floors in ten thousand, and this file
-- needs sublevels 1 and 2 powered. Section E spends the battery before it waits, so its size is moot.
store:SetAsync("u_" .. UID, { data = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 0, runs = 1, extractions = 0,
	perks = { deepCell = 3, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } } })
local function stored()
	local rec = store:GetAsync("u_" .. UID)
	return rec and rec.data
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local hub = h.workspace:FindFirstChild("Hub")
local plr = h:join("Desk", UID)
h:advance(0.5)
local okClient, clientErr = h:tryRun("client/Hud.client")
truthy(okClient, "client/Hud.client loads (" .. tostring(clientErr) .. ")")
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)

local bot = Bot.new(h, plr)
local remotes = h.ReplicatedStorage:FindFirstChild("FacilityRemotes")
local chosen = {}
remotes:FindFirstChild("Choose").OnServerEvent:Connect(function(who, choice)
	if who == plr then table.insert(chosen, choice) end
end)
local UIS = h.game:GetService("UserInputService")
local hudRoot = plr.PlayerGui.FacilityHud.Root
local ServerStorage = h.game:GetService("ServerStorage")
local function debug()
	return ServerStorage.FacilityDebug:FindFirstChild("Run_" .. UID)
end

local function shown(obj)
	local o = obj
	while o ~= nil and o.ClassName ~= "ScreenGui" do
		if o.Visible == false then return false end
		o = o.Parent
	end
	return o ~= nil and o.Enabled ~= false
end
-- every GuiButton with Modal = true, and how many of them are on screen
local function modals()
	local all, onScreen = {}, 0
	for _, d in plr.PlayerGui:GetDescendants() do
		if (d.ClassName == "TextButton" or d.ClassName == "ImageButton") and d.Modal == true then
			table.insert(all, d.Name)
			if shown(d) then onScreen += 1 end
		end
	end
	return all, onScreen
end
local function key(kc)
	local down = { KeyCode = kc, UserInputType = Enum.UserInputType.Keyboard, UserInputState = Enum.UserInputState.Begin }
	local up = { KeyCode = kc, UserInputType = Enum.UserInputType.Keyboard, UserInputState = Enum.UserInputState.End }
	UIS.InputBegan:Fire(down, false)
	UIS.InputEnded:Fire(up, false)
end

--=========================================================================== A. the break room
section("A. break room: the camera is past first person, nothing holds the cursor")
do
	eq(plr.CameraMode, Enum.CameraMode.Classic, "Classic camera in the break room")
	local z = plr.CameraMinZoomDistance
	truthy(type(z) == "number" and z >= FIRST_PERSON_THRESHOLD,
		"the minimum zoom is past first person, so returning from LockFirstPerson leaves it (CameraMinZoomDistance " .. tostring(z) .. ")")
	local all = modals()
	eq(#all, 0, "no Modal button while nothing modal is open (" .. table.concat(all, ",") .. ")")
end

--=========================================================================== B. exploring
section("B. exploring in first person: E and Q do nothing, nothing frees the cursor")
truthy(bot:board(hub) and bot:waitPhase("floor", 6), "walking into the car reaches sublevel 1")
h:advance(0.5)
do
	eq(plr.CameraMode, Enum.CameraMode.LockFirstPerson, "control: LockFirstPerson on the floor (the case that pins the cursor)")
	local all = modals()
	eq(#all, 0, "no button is Modal while exploring: a Modal button would break mouse-look (" .. table.concat(all, ",") .. ")")
	key(Enum.KeyCode.E)
	key(Enum.KeyCode.Q)
	h:advance(0.3)
	eq(#chosen, 0, "E and Q send no choice while the choice is not on screen")
	eq(bot:phase(), "floor", "…and the run goes on")
end

--=========================================================================== C. the choice
section("C. the choice: the cursor is freed, Q descends, E extracts, the labels say so")
do
	eq(bot:clearFloor(), "powered", "control: the bot powers sublevel 1")
	h:advance(0.3)
	local choice = hudRoot:FindFirstChild("Choice")
	local extract, descend = choice:FindFirstChild("ExtractButton"), choice:FindFirstChild("DescendButton")
	eq(shown(choice), true, "the choice is on screen")
	eq(plr.CameraMode, Enum.CameraMode.LockFirstPerson, "control: still LockFirstPerson at the choice")
	local _, onScreen = modals()
	truthy(onScreen >= 1, "a Modal button is on screen while the choice is up, so the engine frees the cursor (" .. onScreen .. ")")
	truthy(string.find(extract.Text, "(E)", 1, true) ~= nil, "EXTRACT names its key: '" .. extract.Text .. "'")
	truthy(string.find(descend.Text, "(Q)", 1, true) ~= nil, "DESCEND names its key: '" .. descend.Text .. "'")
	eq(hudRoot.Hint.Text, "EXTRACT (E) to bank it, or DESCEND (Q) for more.", "…and so does the hint")
	key(Enum.KeyCode.Q)
	h:advance(0.3)
	eq(chosen[1], "descend", "Q chooses DESCEND")
	eq(bot:phase(), "ride", "…and the ride down starts")
	truthy(bot:waitPhase("floor", RIDE + 2), "…to sublevel 2")
	h:advance(0.3)
	local all = modals()
	eq(#all, 0, "the choice closed and nothing is Modal any more (" .. table.concat(all, ",") .. ")")

	-- B3's other half: a POWERED elevator never goes dark, so the choice keeps no timer. Stand in it
	-- well past the moment an unpowered one would fail. Sublevel 2 is 4x4, so maxD <= 15 and an
	-- unpowered exit is dark by hold + (2 + 15 + 1) x step.
	eq(bot:clearFloor(), "powered", "control: the bot powers sublevel 2")
	local dbg = debug()
	local step = dbg:GetAttribute("StepSeconds")
	local rooms = bot:rooms()
	local exitRoom = bot:exitRoom(rooms)
	local exitLight = exitRoom and rooms[exitRoom].light
	truthy(exitLight ~= nil, "control: the exit room's light")
	bot:fire("Flashlight", false)
	local limit = 18 * step + 3
	while dbg:GetAttribute("RunClock") < limit and bot:phase() == "floor" do
		h:advance(0.5)
	end
	truthy(dbg:GetAttribute("RunClock") >= limit, string.format("control: stood in the powered lift to run clock %.1f s (18 steps of %.2f s)", dbg:GetAttribute("RunClock"), step))
	eq(bot:phase(), "floor", "a POWERED elevator room never goes dark: still standing there")
	eq(exitLight and exitLight.Enabled, true, "…with its light on")
	eq(shown(choice), true, "…and the choice still up")
	local essence0 = stored().essence
	key(Enum.KeyCode.E)
	h:advance(0.3)
	eq(chosen[2], "extract", "E chooses EXTRACT")
	eq(stored().essence, essence0 + 10 + 15, "…which banks sublevels 1 and 2: 25")
	truthy(bot:waitPhase("hub", RIDE + 2), "…and rides back up")
	h:advance(0.3)
	eq(plr.CameraMode, Enum.CameraMode.Classic, "back in the break room the camera is Classic")
	local z = plr.CameraMinZoomDistance
	truthy(type(z) == "number" and z >= FIRST_PERSON_THRESHOLD, "…with the minimum zoom still past first person (" .. tostring(z) .. ")")
end

--=========================================================================== D. perks
section("D. the perk panel frees the cursor while it is open, and only then")
do
	local prompt = hub.PerkTerminal:FindFirstChildOfClass("ProximityPrompt")
	prompt.Triggered:Fire(plr)
	h:advance(0.3)
	local perks = hudRoot:FindFirstChild("Perks")
	eq(shown(perks), true, "the terminal's prompt (E at the terminal) opens the perk panel")
	local _, onScreen = modals()
	truthy(onScreen >= 1, "a Modal button is on screen while the perk panel is open (" .. onScreen .. ")")
	local close = perks:FindFirstChild("CloseButton")
	close.Activated:Fire()
	h:advance(0.2)
	eq(shown(perks), false, "CLOSE shuts it")
	local all = modals()
	eq(#all, 0, "…and nothing is Modal any more (" .. table.concat(all, ",") .. ")")
end

--=========================================================================== E. the stall
section("E. stalling in the unpowered elevator room ends the run by itself (REVIEW-1 B3)")
do
	-- The reviewer's scenario: reach the lift before holding every fuse, spend the battery, wait.
	-- ServerStorage.FacilityDebug steers the walk (an oracle for the test, never something a client
	-- knows): first to the nearest fuse room, so the player holds one and the hint has something to
	-- subtract, then to the exit. A walk that happens to collect every fuse powers the lift instead;
	-- that floor is extracted and another tried.
	local reached = false
	for attempt = 1, 10 do
		if bot:phase() ~= "hub" then bot:waitPhase("hub", 12) end
		if not (bot:board(hub) and bot:waitPhase("floor", RIDE + 2)) then break end
		local dbg = debug()
		local exit, n = dbg:GetAttribute("ExitCell"), dbg:GetAttribute("Grid")
		local function md(a, b)
			local ax, ay = (a - 1) % n, math.floor((a - 1) / n)
			local bx, by = (b - 1) % n, math.floor((b - 1) / n)
			return math.abs(ax - bx) + math.abs(ay - by)
		end
		-- open doors toward `goal` until its room is built, then walk into it
		local function steer(goal)
			while bot:phase() == "floor" do
				local rooms, doors = bot:rooms(), bot:doors()
				if rooms[goal] then
					local path = bot:route(rooms, doors, bot:roomAt(rooms, bot:pos()), goal)
					return path ~= nil and bot:followPath(path)
				end
				local here = bot:roomAt(rooms, bot:pos())
				local best, bestScore, bestFrom, bestPath
				for _, d in doors do
					if not d.open and (rooms[d.lo] == nil) ~= (rooms[d.hi] == nil) then
						local from = if rooms[d.lo] then d.lo else d.hi
						local to = if rooms[d.lo] then d.hi else d.lo
						local path = bot:route(rooms, doors, here, from)
						if path then
							local score = md(to, goal) * 100 + #path
							if not best or score < bestScore then best, bestScore, bestFrom, bestPath = d, score, from, path end
						end
					end
				end
				if not best then return false end
				if not bot:followPath(bestPath) or not bot:openThrough(bestFrom, best) then return false end
			end
			return false
		end
		local fuseRoom, fuseD
		local entry = dbg:GetAttribute("EntryCell")
		for c in string.gmatch(dbg:GetAttribute("FuseCells"), "%d+") do
			local id = tonumber(c)
			if not fuseD or md(entry, id) < fuseD then fuseRoom, fuseD = id, md(entry, id) end
		end
		local ok = steer(fuseRoom)
		if ok then
			local part = bot:rooms()[fuseRoom].folder:FindFirstChild("Fuse")
			if part then
				local p = part.Position
				ok = bot:walkTo(Vector3.new(p.X, 3, p.Z), "floor")
				bot:waitSeconds(0.3, "floor")
			end
		end
		ok = ok and steer(exit)
		if ok and bot:phase() == "floor" then
			bot:waitSeconds(0.3, "floor")
			local st = bot:state()
			if st and st.phase == "floor" and not st.run.powered and st.run.fuses + st.run.fusesIn >= 1 then
				reached = true
				break
			end
			if st and st.run and st.run.powered then
				key(Enum.KeyCode.E)
				bot:waitPhase("hub", RIDE + 3)
			end
		end
		if bot:phase() == "floor" then
			plr.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(1000)
			h:advance(0.5)
			h.Players:simulateSpawn(plr, h.workspace)
			h:advance(1)
		end
		bot:waitPhase("hub", 12)
	end
	truthy(reached, "control: reached the unpowered elevator room holding at least one fuse, with fuses still missing")
	if reached then
		local st = bot:state()
		local runs0 = stored().runs
		local have, needed = st.run.fuses + st.run.fusesIn, st.run.fusesNeeded
		local missing = needed - have
		local want = if have == 0
			then string.format("Find %d fuses. Bring them to the elevator.", needed)
			else string.format("Find %d more fuse%s. Bring them to the elevator.", missing, if missing == 1 then "" else "s")
		local rooms = bot:rooms()
		local exitRoom = bot:exitRoom(rooms)
		local exitLight = rooms[exitRoom].light
		print(string.format("  in the unpowered lift with %d/%d fuses, battery %.1f, run clock %.1f s, step %.2f s",
			have, needed, st.run.battery, debug():GetAttribute("RunClock"), debug():GetAttribute("StepSeconds")))
		-- spend the battery (F, the desktop key), then stand there with nothing
		key(Enum.KeyCode.F)
		local tArrive = h.scheduler:now()
		local samples, wrong, lastWrong = 0, 0, ""
		local diedAt, otherLitAtDeath, exitLitAtDeath = nil, -1, nil
		for _ = 1, 6600 do
			h:advance(0.1)
			local s = bot:state()
			if s.phase ~= "floor" then
				diedAt = h.scheduler:now()
				break
			end
			-- the standing hint, once every event hint has had time to lapse (6 s is the longest), and
			-- only while the lift is neither flickering nor dark. The State says so up to one push (0.2 s)
			-- late; the server dims the light in the very tick it sends "roomDying", so a dim light
			-- covers that gap (the flicker's first step is always the dim one)
			if h.scheduler:now() - tArrive > 7 and not s.run.flicker and not s.run.dark
				and exitLight.Enabled and exitLight.Brightness > 1 then
				samples += 1
				local hintText = hudRoot.Hint.Text
				if hintText ~= want then wrong += 1; lastWrong = hintText end
			end
			local lit = 0
			for id, r in bot:rooms() do
				if id ~= exitRoom and r.light and r.light.Enabled then lit += 1 end
			end
			otherLitAtDeath = lit
			exitLitAtDeath = exitLight.Enabled
		end
		truthy(samples >= 5, "control: " .. samples .. " hint samples taken in the lit lift")
		eq(wrong, 0, "the hint counts what is still missing: '" .. want .. "' (last wrong: '" .. lastWrong .. "')")
		truthy(diedAt ~= nil, "the run ends by itself: the dark takes a player who stays in the unpowered lift")
		if diedAt then
			print(string.format("  the dark took the player %.1f s after they reached the lift", diedAt - tArrive))
			eq(bot:phase(), "dying", "…as a dark death (the death beat)")
			eq(otherLitAtDeath, 0, "…after every other built room had gone dark")
			eq(exitLitAtDeath, false, "…and the lift's own light had failed")
			truthy(bot:waitPhase("hub", 5), "…then the break room")
			eq(stored().runs, runs0 + 1, "…and the run is settled once")
			eq(stored().openRun, nil, "…and closed")
		end
	end
end

local errs = h:errors()
eq(#errs, 0, "no scheduler errors (" .. table.concat(errs, " | ") .. ")")
eq(#h.warnings, 0, "no warnings (" .. table.concat(h.warnings, " | ") .. ")")
print(string.format("check_facilitynightmare_desktop: %d passed, %d failed", passed, failed))
