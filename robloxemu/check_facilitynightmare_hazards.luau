-- FACILITY: Endless Nightmare — the environmental HAZARDS (EYECANDY.md §3), through the real server and
-- the real client (Env.client + the HUD), driven by tests/Bot.luau.
--
-- Run:  py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       luau check_facilitynightmare_hazards.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- tests/Hazards.spec.luau proves the scheduler's rules on its own config. This proves them where they
-- matter: through the real client, on the real first floor (a first-ever run, so the front is held and
-- the room stays lit for as long as the check needs), with RenderStepped fired once per bot tick.
-- The offices are quiet by design, so for most of this file the offices' hazard list is set IN MEMORY
-- to the laboratories' kind (nothing on disk changes); the quiet offices are checked first, as shipped.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")
local bundle = require("./build/facility-nightmare")

local h = Harness.new({ bundle = bundle, name = "facility-nightmare-hazards", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local EnvBus = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBus"))
local FxClient = h:_require(h.ReplicatedStorage:FindFirstChild("FxClient"))
local bands = Config.Env.Bands
local Kinds = Config.Hazards.Kinds

-- Written out, not read from Config: a number checked against itself is not a check.
local MIN_GAP, MAX_GAP = 120, 180
local LEAK_RING = 2 * (2.0 + 1.5) -- chemLeak: hitRadius 2 + PlayerRadius 1.5
local LEAK_WARN, LEAK_KNOCK = 3.0, 18
-- The longest banner the HUD showed before the environment existed ("THE POWER IS FAILING — STAY IN THE
-- LIGHT"). A hazard banner may not be longer: nothing headless can measure how a phone wraps it.
local LONGEST_OLD_BANNER = 40

local shakes = 0
do
	local real = FxClient.shake
	FxClient.shake = function(...)
		shakes += 1
		return real(...)
	end
end

local UID = 9401
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 0, runs = 0, extractions = 0,
	perks = { deepCell = 3, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } } })

assert(h:tryRun("server/Main.server"))
h:advance(1)
local plr = h:join("Hazards", UID)
h:advance(0.5)
truthy((h:tryRun("client/Hud.client")), "client/Hud.client loads")
truthy((h:tryRun("client/Env.client")), "client/Env.client loads")
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)

local RS = h.game:GetService("RunService")
local envFolder = h.workspace:FindFirstChild("FacilityEnvLocal")
local hazardFolder = envFolder:FindFirstChild("Hazard")
local hudRoot = plr.PlayerGui.FacilityHud.Root

local log = {}
EnvBus.on(function(kind, data)
	if kind == "hazard" then table.insert(log, { phase = data.phase, name = data.name, at = h.scheduler:now() }) end
end)
local function countPhase(phase, since)
	local n = 0
	for _, m in log do if m.phase == phase and m.at >= (since or 0) then n += 1 end end
	return n
end

local maxModels, maxParts, overlapFrames = 0, 0, 0
-- review finding 5 (EYECANDY.md §11): a particle that is not self-lit is lit by the scene (LightInfluence 1; Roblox's
-- default is 0, unlit, and it reads nil here when never written); a self-lit one says so (0).
local influence = { glow = 0, plain = 0, wrong = 0 }
local function inspect(pe)
	if (pe.LightEmission or 0) > 0 then
		influence.glow += 1
		if pe.LightInfluence ~= 0 then influence.wrong += 1 end
	else
		influence.plain += 1
		if pe.LightInfluence ~= 1 then influence.wrong += 1 end
	end
end
-- the emitter budget while a hazard is live (section C sets the cap to 1 in memory)
local capWatch, maxEmittersWithHazard, roomEmitterIdle = false, 0, 0
local function frame(dt)
	RS.RenderStepped:Fire(dt)
	if capWatch then
		local on, roomOn = 0, 0
		for _, d in envFolder:GetDescendants() do
			if d.ClassName == "ParticleEmitter" then inspect(d) end
			if d.ClassName == "ParticleEmitter" and d.Enabled then
				on += 1
				if not d:IsDescendantOf(hazardFolder) then roomOn += 1 end
			end
		end
		if #hazardFolder:GetChildren() > 0 then
			maxEmittersWithHazard = math.max(maxEmittersWithHazard, on)
		elseif roomOn > 0 then
			roomEmitterIdle += 1
		end
	end
	local models, parts = 0, 0
	for _, m in hazardFolder:GetChildren() do
		models += 1
		for _, d in m:GetDescendants() do
			if d.ClassName == "ParticleEmitter" then inspect(d) end
			if d:IsA("BasePart") then
				parts += 1
				if d.CanCollide ~= false or d.CanQuery ~= false or d.CanTouch ~= false then overlapFrames += 1 end
			end
		end
	end
	maxModels = math.max(maxModels, models)
	maxParts = math.max(maxParts, parts)
end
local bot = Bot.new(h, plr, { onTick = function() frame(0.1) end, maxSeconds = 900 })

--=========================================================================== A. the break room
section("A. no hazard in the break room, whatever the band says")

bands[1].hazards = { "chemLeak" }
bot:waitSeconds(360)
eq(#log, 0, "6 minutes standing in the break room with the offices given a hazard kind: nothing")
bands[1].hazards = {}

--=========================================================================== B. the quiet offices
section("B. sublevel 1 as shipped: the offices are quiet")

-- In memory, the offices wear the flooded kit: its dripping pipe hangs in every room, so the entry room has
-- an emitter for the budget test in C (the offices' own kit has none).
bands[1].kit = "flooded"
truthy(bot:board(h.workspace.Hub), "boarded")
truthy(bot:waitPhase("floor", 8), "arrived on sublevel 1 (first-ever run: the front is held)")
local rooms = bot:rooms()
local entry = bot:roomAt(rooms, bot:pos())
local c = rooms[entry].center
local roomFolder = rooms[entry].folder
local light = roomFolder.Fixture.RoomLight
-- a legal spot: 6.5 studs off the centre, off the car's pad (5.5) and inside the interior (7)
local spot = Vector3.new(c.X + 6.5, 3, c.Z)
bot:walkTo(spot, "floor")
bot:waitSeconds(600, "floor")
eq(#log, 0, "10 minutes standing still in a lit office: no hazard (the band has none)")
eq(light.Enabled, true, "control: the room stayed lit all along")

--=========================================================================== C. the rarity, through the client
section("C. hazards on the real floor: rare, telegraphed, the ring is what hits, a step out dodges")

bands[1].hazards = { "chemLeak" }
local emitterCap = Config.Budget.MaxEmitters
Config.Budget.MaxEmitters = 1 -- in memory: the room's drip and a hazard's warning cannot both run
capWatch = true
local enabledAt = h.scheduler:now()
local warns = {}
local hits, dodged, stoodHit = 0, 0, 0
local ringOk, bannerOk, warnOk, knockOk, shakeOk = 0, 0, 0, 0, 0
local shortOk, stillInOk, clearOk, burstShownOk = 0, 0, 0, 0
local lastWarn = nil
local gaps = {}
local n = 0
while n < 18 do
	local before = #log
	local waited = 0
	while countPhase("warn", (lastWarn or enabledAt) + 0.01) == 0 do
		bot:tick()
		waited += 0.1
		if waited > 400 then break end
	end
	if waited > 400 then
		truthy(false, "a hazard came within 400 s")
		break
	end
	n += 1
	local w = log[#log]
	for i = before + 1, #log do if log[i].phase == "warn" then w = log[i] end end
	if lastWarn then table.insert(gaps, w.at - lastWarn) else table.insert(gaps, w.at - enabledAt) end
	lastWarn = w.at
	table.insert(warns, w.at)
	-- the telegraph, the frame it starts
	local model = hazardFolder:FindFirstChildOfClass("Folder")
	local ring = model and model:FindFirstChild("Ring")
	local p = bot:pos()
	if ring and math.abs(ring.Position.X - p.X) < 0.05 and math.abs(ring.Position.Z - p.Z) < 0.05
		and math.abs(ring.Size.Y - LEAK_RING) < 0.01 and math.abs(ring.Size.Z - LEAK_RING) < 0.01 then
		ringOk += 1
	end
	if hudRoot.Banner.Visible and string.find(hudRoot.Banner.Text, "CHEMICAL LEAK — STEP OUT OF THE RING", 1, true) then bannerOk += 1 end
	if (utf8.len(hudRoot.Banner.Text) or 999) <= LONGEST_OLD_BANNER then shortOk += 1 end
	local shakesBefore = shakes
	local hitsBefore = countPhase("hit")
	if n % 2 == 0 then
		-- react: a second to notice, then step out of the ring (4.5 studs, alternating sides)
		bot:waitSeconds(1.0, "floor")
		local side = if n % 4 == 0 then 1 else -1
		bot:walkTo(Vector3.new(spot.X, 3, spot.Z + side * 4.5), "floor")
		-- first person cannot see a ring at its own feet: the banner is what says the step worked
		if countPhase("burst", w.at) == 0 and hudRoot.Banner.Visible and string.find(hudRoot.Banner.Text, "CHEMICAL LEAK — YOU ARE CLEAR", 1, true) then
			clearOk += 1
		end
		bot:waitSeconds(4, "floor")
		if countPhase("hit") == hitsBefore then dodged += 1 end
		bot:walkTo(spot, "floor")
	else
		-- stand still and take it
		local burstAt = nil
		local t0 = h.scheduler:now()
		while countPhase("hit") == hitsBefore and h.scheduler:now() - t0 < 6 do
			bot:tick()
			if not burstAt and countPhase("burst", t0) > 0 then
				burstAt = h.scheduler:now()
				-- the burst itself is drawn, where the ring is, the frame it comes down
				local m = hazardFolder:FindFirstChildOfClass("Folder")
				local bp, rg = m and m:FindFirstChild("Burst"), m and m:FindFirstChild("Ring")
				if bp and rg and bp.Transparency < 1 and math.abs(bp.Position.X - rg.Position.X) < 0.01
					and math.abs(bp.Position.Z - rg.Position.Z) < 0.01 and bp.Position.Y > rg.Position.Y then
					burstShownOk += 1
				end
			end
			if not burstAt and h.scheduler:now() - w.at >= LEAK_WARN - 0.25 and h.scheduler:now() - w.at < LEAK_WARN - 0.15 then
				if hudRoot.Banner.Visible and string.find(hudRoot.Banner.Text, "STEP OUT OF THE RING", 1, true) then stillInOk += 1 end
			end
		end
		if countPhase("hit") > hitsBefore then
			stoodHit += 1
			if burstAt and burstAt - w.at >= LEAK_WARN - 0.11 then warnOk += 1 end
			local v = plr.Character.HumanoidRootPart.AssemblyLinearVelocity
			local horiz = v and math.sqrt(v.X * v.X + v.Z * v.Z) or 0
			if math.abs(horiz - LEAK_KNOCK) < 0.01 then knockOk += 1 end
			if shakes > shakesBefore then shakeOk += 1 end
		end
		bot:waitSeconds(2, "floor")
	end
	hits = countPhase("hit")
end
local stood, reacted = math.ceil(n / 2), math.floor(n / 2)
local lo, hi, sum = math.huge, 0, 0
for _, g in gaps do lo = math.min(lo, g); hi = math.max(hi, g); sum += g end
print(string.format("    %d hazards in %.1f min on the floor: one per %.1f s (gaps %.1f-%.1f s, the first %.1f s after the kind was switched on)",
	n, (lastWarn - enabledAt) / 60, sum / #gaps, lo, hi, gaps[1]))
print(string.format("    stood still: %d of %d hit; stepped out: %d of %d dodged; %d hits in all", stoodHit, stood, dodged, reacted, hits))
truthy(gaps[1] >= MIN_GAP - 0.2 and gaps[1] <= MAX_GAP + 0.2,
	"the first came 120-180 s after the kind was switched on: the break room and the quiet offices never ran the clock (" .. gaps[1] .. ")")
truthy(lo >= MIN_GAP - 0.2 and hi <= MAX_GAP + 0.2, "every gap within 120-180 s")
eq(ringOk, n, "every warning drew the ring where the player stood, as wide as the zone")
eq(bannerOk, n, "…and the HUD named it on the banner")
eq(shortOk, n, "…in no more characters than the longest banner the HUD already showed (" .. LONGEST_OLD_BANNER .. ")")
eq(stillInOk, stood, "…still up and still saying STEP OUT a quarter second before the burst, for a player who stays in the ring")
eq(clearOk, reacted, "…and saying YOU ARE CLEAR the moment a player steps out, before the burst")
eq(stoodHit, stood, "a player who stays put is hit")
eq(warnOk, stood, "…never earlier than the 3 s telegraph")
eq(burstShownOk, stood, "…the burst drawn over the ring the frame it comes down")
eq(knockOk, stood, "…shoved at the kind's knock speed, horizontally")
eq(shakeOk, stood, "…with a camera shake")
eq(dodged, reacted, "a player who steps out of the ring a second after the warning is never hit")
eq(maxModels, 1, "never two hazards at once")
capWatch = false
Config.Budget.MaxEmitters = emitterCap
truthy(roomEmitterIdle > 0, "control: between hazards the entry room's dripping pipe runs (" .. roomEmitterIdle .. " frames)")
eq(maxEmittersWithHazard, 1, "with the cap at 1, a live hazard's warning takes the room's emitter: never both at once")
truthy(maxParts <= Config.Budget.MaxHazardParts, "hazard parts within budget (" .. maxParts .. ")")
eq(overlapFrames, 0, "no hazard part collides, is queryable or touchable")
eq(#hazardFolder:GetChildren(), 0, "nothing is left parented between hazards")
truthy(influence.glow > 0 and influence.plain > 0,
	"control: self-lit (the leak's warning) and plain (the room's drips) particles were inspected (" .. influence.glow .. ", " .. influence.plain .. ")")
eq(influence.wrong, 0, "every particle is lit by the scene unless it is self-lit (LightInfluence 1, or 0 with LightEmission > 0)")

--=========================================================================== D. a dark room freezes the clock
section("D. the dark freezes the clock (and the dark's warning calls a hazard off)")

do
	local prev = lastWarn
	-- what the server does when a room dies: its light goes off (the first run's front is held, so the
	-- server leaves the forced state alone)
	light.Enabled = false
	bot:waitSeconds(600, "floor")
	eq(countPhase("warn", prev + 0.01), 0, "10 minutes in a dark room: no hazard")
	light.Enabled = true
	local waited = 0
	while countPhase("warn", prev + 0.01) == 0 and waited < 400 do bot:tick(); waited += 0.1 end
	local nextWarn = log[#log].at
	local exposed = nextWarn - prev - 600
	print(string.format("    the next hazard: %.1f s of lit time after the one before (plus 600 s dark)", exposed))
	truthy(exposed >= MIN_GAP - 0.3 and exposed <= MAX_GAP + 0.3, "the dark froze the clock rather than resetting or running it (" .. exposed .. " s lit)")

	-- this one: the room starts to flicker a second into the warning
	bot:waitSeconds(1, "floor")
	truthy(hudRoot.Banner.Visible and string.find(hudRoot.Banner.Text, "STEP OUT OF THE RING", 1, true) ~= nil,
		"control: a second into the warning the banner still names the hazard")
	local t0 = h.scheduler:now()
	light.Brightness = Config.Facility.FlickerLowBrightness
	bot:tick()
	truthy(countPhase("clear", t0) >= 1, "the room's flicker calls the hazard off at once")
	eq(#hazardFolder:GetChildren(), 0, "…and its ring and source are gone")
	-- the dark's warning outranks everything: the HUD must not go on telling the player to step out of a
	-- ring that is gone while their room goes dark (the banner used to stay up for the rest of its 3 s)
	truthy(not (hudRoot.Banner.Visible and string.find(hudRoot.Banner.Text, "STEP OUT OF THE RING", 1, true) ~= nil),
		"…and so is its banner (" .. tostring(hudRoot.Banner.Visible) .. ": " .. hudRoot.Banner.Text .. ")")
	light.Brightness = Config.Facility.RoomLightBrightness
	bot:waitSeconds(6, "floor")
	eq(countPhase("burst", t0), 0, "…it never bursts")
	eq(countPhase("hit", t0), 0, "…and never hits, though the player never moved")
end

--=========================================================================== E. pads and arrivals
section("E. never on the car or lift pad; a hazard due at the choice never lands on the next arrival's warning")

-- Written out: on arrival the server sends "arrive" (a 6 s hint) and "powerFailing" (the 3 s banner THE POWER IS
-- FAILING — STAY IN THE LIGHT, the dark's own warning); a hazard waits for both.
local ARRIVAL_GRACE = 6
do
	-- 1. the car pad: the entry room's centre (the car stands there; its roof would be in the way). 4 studs
	-- out: on the 10 x 10 pad, but clear of the light fixture's own keep-out (2.5), so only the PAD rule can
	-- keep a hazard off this spot (the resume sweep's H4 survived a first draft that stood under the fixture)
	local t0 = h.scheduler:now()
	bot:walkTo(Vector3.new(c.X + 4, 3, c.Z), "floor")
	bot:waitSeconds(200, "floor")
	eq(countPhase("warn", t0), 0, "200 s on the entry car's pad in a lit hazard room (a hazard long due): nothing")
	local t1 = h.scheduler:now()
	bot:walkTo(spot, "floor")
	bot:waitSeconds(0.5, "floor")
	eq(countPhase("warn", t1), 1, "…a step off the pad and the waiting hazard comes at once (it waited; it did not pile up)")
	bot:waitSeconds(5, "floor")

	-- 2. the powered freight elevator: the one place a run can stop (the choice has no timer, DESIGN.md §2.2)
	local attempts, measured = 0, false
	local liftQuiet, arrivalDelay, bannerKept = nil, nil, nil
	while not measured and attempts < 3 do
		attempts += 1
		local r = bot:clearFloor()
		assert(r == "powered", "E: the bot could not power sublevel " .. tostring(bot:state().run.k) .. " (" .. tostring(r) .. ")")
		local rooms2 = bot:rooms()
		local exitC = rooms2[bot:exitRoom(rooms2)].center
		bot:walkTo(Vector3.new(exitC.X + 4, 3, exitC.Z), "floor") -- on the lift's pad, clear of the fixture
		local tl = h.scheduler:now()
		bot:waitSeconds(200, "floor")
		liftQuiet = (liftQuiet ~= false) and countPhase("warn", tl) == 0
		-- DESCEND with that hazard long due, and time the first warning on the new sublevel
		bot:fire("Choose", "descend")
		assert(bot:waitPhase("ride", 3) and bot:waitPhase("floor", 8), "E: the ride down")
		local arrived = h.scheduler:now()
		local k = bot:state().run.k
		local rooms3 = bot:rooms()
		local c3 = rooms3[bot:roomAt(rooms3, bot:pos())].center
		bot:walkTo(Vector3.new(c3.X + 6.5, 3, c3.Z), "floor")
		local flickered, warnAt = false, nil
		while h.scheduler:now() - arrived < ARRIVAL_GRACE + 6 do
			bot:tick()
			local st = bot:state()
			if st.run and (st.run.flicker or st.run.dark) then flickered = true end
			if math.abs(h.scheduler:now() - arrived - 2.05) < 0.051 then
				bannerKept = hudRoot.Banner.Visible and string.find(hudRoot.Banner.Text, "THE POWER IS FAILING", 1, true) == 1
			end
			if countPhase("warn", arrived) > 0 then warnAt = h.scheduler:now(); break end
		end
		if warnAt and not flickered then
			arrivalDelay = warnAt - arrived
			measured = true
			print(string.format("    sublevel %d: the hazard due since the lift came %.1f s after arrival", k, arrivalDelay))
		else
			print(string.format("    sublevel %d: inconclusive (entry room flickered %s, warning %s); again", k, tostring(flickered), tostring(warnAt)))
		end
	end
	truthy(liftQuiet == true, "200 s standing in the powered lift at the choice (lit, a hazard long due): never a hazard")
	truthy(measured, "a clean arrival was measured within 3 descents")
	truthy(arrivalDelay ~= nil and arrivalDelay >= ARRIVAL_GRACE - 0.15 and arrivalDelay <= ARRIVAL_GRACE + 1,
		"…and the hazard waited out the arrival: " .. tostring(arrivalDelay) .. " s (the grace is " .. ARRIVAL_GRACE .. " s)")
	truthy(bannerKept == true, "…so THE POWER IS FAILING, the dark's own warning, kept the banner for its 3 s")
end

eq(#h:errors(), 0, "no scheduler errors")
local envWarnings = 0
for _, w in h.warnings do
	if string.find(w, "FacilityEnv", 1, true) then envWarnings += 1; print("   warn: " .. w) end
end
eq(envWarnings, 0, "Env.client never warned")
print(string.format("check_facilitynightmare_hazards: %d passed, %d failed", passed, failed))
