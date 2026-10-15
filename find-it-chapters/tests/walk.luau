-- Find It! Chapters: THE PLAYER'S PATH, walked in the built world through the REAL client scripts.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--       cd ../find-it-chapters && luau tests/walk.luau 2>&1
--
-- One full loop from join into a second: spawn on HubSpawn, walk to the Case Book, press its prompt, Chapter 1's
-- room, read the clue chips, walk to props that fit, TAP them on the screen (a touch at the prop's projected
-- position: Room.client picks, selects, and on the second tap fires Search), clear the chapter, press Next on the
-- HUD card, Chapter 2, take a Pause from the HUD's button and Resume (the room is re-dressed), finish Chapter 2.
-- The player knows only what a player sees: the room payload and the chips. Nothing here reads the secret.
-- Walking is time: every move advances the clock by distance / 16 studs/s (the emulator has no physics).
-- It prints what happened, in numbers.

local Harness = require("../../robloxemu/emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("../../robloxemu/build/find-it-chapters"), name = "find-it-walk", viewport = { 1280, 720 }, touch = true })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS, ws = h.ReplicatedStorage, h.workspace
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Clue, Pick, RoomArt = mod("Config"), mod("Clue"), mod("Pick"), mod("RoomArt")
local RunService = h.game:GetService("RunService")
local UIS = h.game:GetService("UserInputService")
local remotes = RS:FindFirstChild("FindItRemotes")

local clockT = 0
local function frame(d)
	RunService.Heartbeat:Fire(d)
	RunService.RenderStepped:Fire(d)
	h:advance(d)
	clockT += d
end
local function run(seconds)
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(1 / 20, seconds - t)
		frame(d)
		t += d
	end
end
local function last(name, plr)
	local s = remotes:FindFirstChild(name):sentTo(plr)
	return s[#s] and s[#s].args[1]
end

-- join, spawn, the client scripts
local plr = h:join("Walker", 777)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Room.client"))
assert(h:tryRun("client/Board.client"))
clockT = 0
local joinedAt = 0
local hud = plr.PlayerGui:FindFirstChild("FindItHud").Root
local landing = hrp.Position
print(string.format("  joined: landed at (%.1f, %.1f, %.1f) on HubSpawn", landing.X, landing.Y, landing.Z))
truthy(math.abs(landing.Z - Config.World.HubSpawn[3]) < 3, "landed on HubSpawn")
run(1)
truthy(hud.Banner.Visible and string.find(hud.Banner.Text.Text, "Case Book", 1, true), "the first hint names the Case Book")

-- walking is time
local function walkTo(pos)
	local from = hrp.Position
	local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
	local steps = math.max(1, math.ceil(d / 16 / 0.1))
	for i = 1, steps do
		local p = from:Lerp(Vector3.new(pos.X, 3, pos.Z), i / steps)
		hrp.CFrame = CFrame.new(p)
		hum.MoveDirection = Vector3.new(1, 0, 0)
		frame(d / 16 / steps)
	end
	hum.MoveDirection = Vector3.new(0, 0, 0)
	return d
end

-- the Case Book: a 2-stud walk, then the prompt
local book = ws.FindItWorld.Hub.CaseBook
local toBook = Vector3.new(book.Position.X, 3, book.Position.Z + 5)
local walked = walkTo(toBook)
local pp = book:FindFirstChildOfClass("ProximityPrompt")
truthy((book.Position - hrp.Position).Magnitude <= pp.MaxActivationDistance, "the Case Book prompt is in range after the walk")
pp.Triggered:Fire(plr)
run(0.2)
local st = last("State", plr)
eq(st and st.chapter, 1, "the Case Book takes a new player straight into Chapter 1")
local coreAt = clockT
print(string.format("  core action: in Chapter 1's room %.1f s after join (walked %.1f studs)", coreAt, walked))
truthy(coreAt <= 5, "the core action within about 5 s of joining")

-- tap a prop the way a finger does: point the camera at it, touch its projected screen position
local cam = ws.CurrentCamera
local function tapProp(pl, prop)
	local o = pl.origin
	local target = Vector3.new(o[1] + prop.x, o[2] + prop.y + 1, o[3] + prop.z)
	-- the player turns the camera until the prop is in plain view: of a few third-person viewpoints around the
	-- player, the first from which the prop is the nearest thing on the line of sight (the same Pick the client
	-- uses, with every prop and table of the room). Then the finger goes where the prop is drawn.
	local props, occ = {}, {}
	for _, q in pl.props do table.insert(props, { id = q.id, kind = q.kind, x = o[1] + q.x, y = o[2] + q.y, z = o[3] + q.z }) end
	for _, t in pl.tables do
		table.insert(occ, { cx = o[1] + t.x, cy = o[2] + Config.Room.TableTop / 2, cz = o[3] + t.z, hx = Config.Room.TableSize[1] / 2,
			hy = Config.Room.TableTop / 2, hz = Config.Room.TableSize[2] / 2 })
	end
	local eye = nil
	local me = hrp.Position
	for _, cand in { { 0, 12, 0 }, { 0, 7, 0 }, { 3, 9, 0 }, { -3, 9, 0 }, { 0, 9, 3 }, { 0, 9, -3 }, { 0, 5, 0 } } do
		local e = Vector3.new(me.X + cand[1], o[2] + cand[2], me.Z + cand[3])
		local d = (target - e).Unit
		local hit = Pick.pick({ e.X, e.Y, e.Z }, { d.X, d.Y, d.Z }, props, occ, RoomArt.pickBox)
		if hit and hit.id == prop.id then
			eye = e
			break
		end
	end
	truthy(eye ~= nil, "prop " .. prop.id .. " can be seen from where the player stands")
	cam.CFrame = CFrame.lookAt(eye or Vector3.new(me.X, o[2] + 12, me.Z), target)
	local cf = cam.CFrame
	local vp = cam.ViewportSize
	local sx, sy = Pick.project({ pos = { cf.Position.X, cf.Position.Y, cf.Position.Z }, look = { cf.LookVector.X, cf.LookVector.Y, cf.LookVector.Z },
		right = { cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z }, up = { cf.UpVector.X, cf.UpVector.Y, cf.UpVector.Z } },
		cam.FieldOfView, vp.X, vp.Y, { target.X, target.Y, target.Z })
	local pos = Vector3.new(sx, sy - 36, 0) -- input positions are below the topbar inset
	local input = { UserInputType = Enum.UserInputType.Touch, Position = pos, KeyCode = Enum.KeyCode.Unknown }
	UIS.InputBegan:Fire(input, false)
	frame(0.1)
	UIS.InputEnded:Fire(input, false)
	frame(0.05)
end

-- play a room as a reader: for each chip, the props that fit its clue (public traits), nearest first
local function playRoom(label, opts)
	opts = opts or {}
	local pl = last("Room", plr)
	local started = clockT
	run(Config.Cards.IntroFirst + 0.2)
	local searches, misses, firstFind, pausedOnce = 0, 0, nil, false
	local i = 1
	while i <= #pl.clues do
		st = last("State", plr)
		if st.state == "done" then break end
		if st.found[i] then
			i += 1
			continue
		end
		local clue = pl.clues[i]
		local fits = {}
		for _, p in pl.props do
			if Clue.matches(p, clue, Config) and not p.__searched then table.insert(fits, p) end
		end
		table.sort(fits, function(a, b)
			local o = pl.origin
			local pa = Vector3.new(o[1] + a.x, 0, o[3] + a.z)
			local pb = Vector3.new(o[1] + b.x, 0, o[3] + b.z)
			local me = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
			return (pa - me).Magnitude < (pb - me).Magnitude
		end)
		local prop = fits[1]
		if prop == nil then break end
		local o = pl.origin
		local w = Vector3.new(o[1] + prop.x, 0, o[3] + prop.z)
		local centre = Vector3.new(o[1], 0, o[3] + pl.D / 2)
		walkTo(w + (centre - w).Unit * 3)
		local resultsBefore = #remotes.Result:sentTo(plr)
		tapProp(pl, prop) -- select
		tapProp(pl, prop) -- search
		run(1.1)
		prop.__searched = true
		local results = remotes.Result:sentTo(plr)
		if #results == resultsBefore then
			local t = last("Toast", plr)
			print(string.format("  note: a tap on prop %d sent no search (last toast: %s)", prop.id, tostring(t and t.text)))
		end
		if #results > resultsBefore then
			searches += 1
			local res = results[#results].args[1]
			if res.hit then
				firstFind = firstFind or clockT
			else
				misses += 1
			end
		end
		-- a pause from the HUD's button, once, in the middle of the room
		if opts.pause and not pausedOnce and searches >= 2 then
			pausedOnce = true
			local looksBefore = last("State", plr).looks
			local idBase0 = pl.idBase
			hud.PauseButton.Activated:Fire()
			run(0.3)
			eq(last("State", plr).state, "paused", "the Pause button pauses the attempt on the server")
			local clockP = last("State", plr).clock
			run(5)
			truthy(math.abs(last("State", plr).clock - clockP) < 1e-6, "the clock is stopped while paused")
			hud.Card.Buttons.ResumeButton.Activated:Fire()
			run(0.5)
			local pl2 = last("Room", plr)
			truthy(pl2.redress and pl2.idBase > idBase0, "Resume re-dresses the room (new ids)")
			eq(last("State", plr).looks, looksBefore, "the looks are unchanged by the pause")
			print(string.format("  pause: clock held at %.1f s for 5 s; Resume re-dressed %d props, looks %d -> %d", clockP, #pl2.props, looksBefore, last("State", plr).looks))
			pl = pl2
		end
	end
	run(0.3)
	st = last("State", plr)
	local took = clockT - started
	return { found = st.result and st.result.reason == "found", took = took, searches = searches, misses = misses,
		firstFind = firstFind, looks = st.looks, stars = st.result and st.result.stars, clock = st.clock }
end

local r1 = playRoom("Chapter 1")
truthy(r1.found, "Chapter 1 cleared by a reader's taps")
print(string.format("  Chapter 1: first find %.1f s after join; cleared %.1f s after join (%.1f s in the room, clock %.1f of %d s); %d searches, %d misses, %d looks left; stars %s%s%s",
	r1.firstFind or -1, clockT, r1.took, r1.clock or 0, Config.Chapters[1].clock, r1.searches, r1.misses, r1.looks or -1,
	r1.stars and r1.stars.f and "F" or "-", r1.stars and r1.stars.w and "S" or "-", r1.stars and r1.stars.s and "E" or "-"))
truthy(hud.Card.Visible, "the clear card shows")
run(7)
st = last("State", plr)
eq(st.result and st.result.first, true, "a first clear, saved")
eq(st.result and st.result.solved, 1, "Cases Solved 1")
eq(plr.leaderstats.Solved.Value, 1, "leaderstats.Solved 1")
truthy(hud.ListPanel:FindFirstChild("Chip_1") ~= nil, "the chips are still there under the card")

-- the second loop: Next from the HUD card
hud.Card.Buttons.NextButton.Activated:Fire()
run(0.3)
st = last("State", plr)
eq(st.chapter, 2, "Next on the HUD card opens Chapter 2")
local r2 = playRoom("Chapter 2", { pause = true })
truthy(r2.found, "Chapter 2 cleared, through a pause and a re-dress")
run(7)
st = last("State", plr)
print(string.format("  Chapter 2: cleared %.1f s after join (%.1f s in the room incl. the pause); %d searches, %d misses, %d looks left; Cases Solved %s",
	clockT, r2.took, r2.searches, r2.misses, r2.looks or -1, tostring(st.result and st.result.solved)))
eq(st.result and st.result.solved, 2, "Cases Solved 2")

-- what the client built: budgets in use
local stats = {}
mod("ClientBus").fire("__stats", stats)
print(string.format("  client: %d local parts (peak %d, cap %d), %d lights (cap %d), %d emitters (cap %d), %d Lighting writes; refused: %d parts, %d lights, %d emitters",
	stats.parts or -1, stats.peakParts or -1, Config.Budget.LocalParts, stats.lights or -1, Config.Budget.Lights, stats.emitters or -1, Config.Budget.Emitters,
	stats.lightingWrites or -1, stats.refusedParts or 0, stats.refusedLights or 0, stats.refusedEmitters or 0))
truthy((stats.peakParts or 999) <= Config.Budget.LocalParts, "local parts never above the cap")
eq((stats.refusedParts or 0) + (stats.refusedLights or 0) + (stats.refusedEmitters or 0), 0, "nothing was refused by a budget (the last room was torn down)")
do
	local screens, lamps = 0, 0
	for _, c in ws:FindFirstChild("FindItLocalRoom"):GetChildren() do
		if string.sub(c.Name, 1, 7) == "Screen_" then screens += 1 end
		if string.sub(c.Name, 1, 5) == "Lamp_" then lamps += 1 end
	end
	truthy(screens <= 3 and lamps <= Config.Budget.Lights, string.format("only the current room stands: %d screens, %d lamps", screens, lamps))
end
truthy((stats.lights or 99) <= Config.Budget.Lights and (stats.emitters or 99) <= Config.Budget.Emitters, "lights and emitters within their caps")

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	failed += 1
	print("FAIL: a warning: " .. w)
end
print(string.format("find it WALK: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
