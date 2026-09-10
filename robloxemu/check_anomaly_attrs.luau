-- anomaly-observatory — the zone must SAY what the roll was, and be telling the truth.
-- Run: luau check_anomaly_attrs.luau
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- WHY THIS EXISTS. `beginPass` decides each pass in a table local to the server script
-- (`passState[plr].clean` / `.anomalyId`). Nothing outside that script could read it, so anything
-- that needed to know which hall was on screen — the marketing capture rig, which has to shoot
-- the SAME hall clean and anomalous as a matched pair — was reduced to guessing from pixels.
-- `beginPass` now publishes the roll on the zone model as attributes `Clean`, `AnomalyId` and
-- `Serial`. That is only useful if the attributes are true, and an attribute that quietly lies
-- fails in the worst possible way: the rig ships a "spot the difference" pair whose two halves
-- are the same hall, or whose anomaly is labelled as the wrong one, and nothing errors.
--
-- WHAT IS ASSERTED, and how it avoids grading its own homework. The attributes are never
-- checked against the server's own state — that would only prove a variable equals itself.
-- They are checked against the WORLD: a fingerprint of every BasePart in the zone (name,
-- position, full rotation, size, colour, transparency, reflectance, material). The clean hall is
-- identified without reference to any attribute, as the fingerprint that recurs most often
-- across many independent first passes — the roll is ~50% clean and spreads the rest over eight
-- day-1 anomalies, so the mode is the clean hall by a wide margin, and the margin is printed
-- rather than assumed.
--
--   1. `Clean == true`  exactly when the hall matches that reference fingerprint.
--   2. `AnomalyId` is present exactly when `Clean == false`, and names a real catalog entry.
--   3. Across consecutive passes on one player the attributes TRACK the hall — the failure this
--      catches is a stale attribute describing the previous pass, which a single-pass check
--      cannot see.
--   4. `Serial` increases by one per pass, so a capture can tell two passes apart.
--
-- Phase 2 answers each pass from the FINGERPRINT rather than from the attribute, and asserts the
-- day counter went up every time. That is the deeper claim underneath the whole game: the hall
-- differs from clean exactly when the server scores it as anomalous. If an applier ever mutated
-- nothing, the day counter would stop climbing here.

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
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

local CATALOG = {}
for _, entry in Config.Anomaly.Catalog do
	CATALOG[entry.id] = entry.name
end

-- A hall, reduced to a string. Everything an applier can touch is in here: adding or removing a
-- part changes the row set, moving or rotating one changes the CFrame components (rotation
-- matters — `floor_tilt` and `scope_tilt` turn a part about its own centre and leave the
-- position identical), and recolouring, resizing or unlighting one changes the rest.
--
-- Positions are recorded RELATIVE TO THE ZONE ORIGIN. Each player's concourse is built at
-- `index * 1000` studs on X so the halls never overlap, so absolute coordinates make every
-- player's hall unique and the first version of this check duly reported 60 distinct halls out
-- of 60 samples — a "difference" that was nothing but the address it was built at.
local function fingerprint(zone): string
	local origin = (tonumber(zone:GetAttribute("Index")) or 0) * 1000
	local rows = {}
	for _, d in zone:GetDescendants() do
		if d:IsA("BasePart") then
			local c = d.Color
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			x -= origin
			table.insert(rows, string.format(
				"%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d,%d,%d|%.2f|%.2f|%s",
				tostring(d.Name), x, y, z,
				r00, r01, r02, r10, r11, r12, r20, r21, r22,
				d.Size.X, d.Size.Y, d.Size.Z,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
				d.Transparency, d.Reflectance, tostring(d.Material)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function zoneOf(plr)
	return h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
end

local function attrsOf(zone)
	return zone:GetAttribute("Clean"), zone:GetAttribute("AnomalyId"), zone:GetAttribute("Serial")
end

assert(h:tryRun("server/Main.server"))

--============================================================ phase 1: what does a pass look like
-- Independent first passes: one per player, each with its own server-side salt, so this samples
-- the roll rather than one lucky draw. Nothing is driven through the game loop here, so it costs
-- no wall-clock time.
local SAMPLES = 60
local samples = {} -- { zone, fp, clean, id, serial }
local counts = {}
for i = 1, SAMPLES do
	local plr = h:join("Shooter" .. i, 900000 + i)
	h:advance(0.05)
	local zone = zoneOf(plr)
	assert(zone ~= nil, "player " .. i .. " got no concourse")
	local clean, id, serial = attrsOf(zone)
	local fp = fingerprint(zone)
	counts[fp] = (counts[fp] or 0) + 1
	table.insert(samples, { zone = zone, fp = fp, clean = clean, id = id, serial = serial })
end

-- The clean hall is the fingerprint that recurs most. No attribute was consulted to find it.
local refFp, refCount = nil, 0
for fp, n in counts do
	if n > refCount then refFp, refCount = fp, n end
end
local distinct = 0
for _ in counts do distinct += 1 end
print(string.format("phase 1: %d first passes, %d distinct halls, the commonest occurred %d times (%.0f%%)",
	SAMPLES, distinct, refCount, refCount / SAMPLES * 100))

-- Stated rather than assumed: if the modal hall is not a clear plurality the identification is
-- not safe and every assertion below it is worthless, so say so instead of passing quietly.
truthy(refCount >= SAMPLES / 3,
	string.format("the commonest hall is a clear plurality (%d of %d) so it is the clean one", refCount, SAMPLES))
truthy(distinct > 1, "the sample contains more than one distinct hall (the roll is not stuck)")

-- Does this hall differ from the clean one at ANY moment in a short window?
--
-- One instant is not enough, and finding that out mattered for more than this check.
-- `flicker_hall` is a light strobing on an irregular cycle: for roughly half of every cycle the
-- hall is bit-for-bit the clean hall. A single sample therefore called an honestly-anomalous
-- pass "identical to clean" and failed the run. The anomaly is real, it is just TEMPORAL — and
-- the same fact says something the capture rig has to respect: a still photograph of
-- `flicker_hall` may show nothing at all, so it is not a usable spot-the-difference pair.
local WINDOW_STEPS, WINDOW_STEP = 8, 0.05
local function hallDiffers(zone): boolean
	if fingerprint(zone) ~= refFp then return true end
	for _ = 1, WINDOW_STEPS do
		h:advance(WINDOW_STEP)
		if fingerprint(zone) ~= refFp then return true end
	end
	return false
end

local seenIds, cleanSeen, anomalousSeen, temporal = {}, 0, 0, {}
for i, s in samples do
	-- `s.fp` was taken the instant the pass began; `hallDiffers` re-reads the same still-live
	-- zone over a window. An anomaly that shows up only in the second is a temporal one.
	local differs = hallDiffers(s.zone)
	local matchesClean = not differs
	if differs and s.fp == refFp and s.id ~= nil then
		temporal[s.id] = true
	end
	eq(type(s.clean), "boolean", string.format("sample %d publishes a boolean Clean attribute", i))
	eq(s.clean, matchesClean, string.format(
		"sample %d: Clean=%s agrees with the hall (%s the reference hall)",
		i, tostring(s.clean), matchesClean and "identical to" or "different from"))
	eq(s.serial, 1, string.format("sample %d is serial 1 (a player's first pass)", i))
	if s.clean then
		cleanSeen += 1
		eq(s.id, nil, string.format("sample %d is clean, so it names no anomaly", i))
	else
		anomalousSeen += 1
		truthy(s.id ~= nil, string.format("sample %d is anomalous, so it names one", i))
		if s.id ~= nil then
			truthy(CATALOG[s.id] ~= nil, string.format("sample %d names a real catalog id (%s)", i, tostring(s.id)))
			seenIds[s.id] = (seenIds[s.id] or 0) + 1
		end
	end
end
local idList = {}
for id, n in seenIds do table.insert(idList, string.format("%s x%d", id, n)) end
table.sort(idList)
print(string.format("   %d clean, %d anomalous: %s", cleanSeen, anomalousSeen, table.concat(idList, ", ")))
local temporalList = {}
for id in temporal do table.insert(temporalList, id) end
table.sort(temporalList)
if #temporalList > 0 then
	print("   TEMPORAL (looked identical to clean at the instant the pass began, so a single "
		.. "still may show nothing): " .. table.concat(temporalList, ", "))
end
truthy(cleanSeen > 0, "at least one clean pass was sampled")
truthy(anomalousSeen > 0, "at least one anomalous pass was sampled")

--============================================================ phase 2: do they track, pass to pass
-- One player, played properly: read the hall, answer from what is IN it, and require the day to
-- climb every time. A stale attribute — set before the roll, or never cleared when a pass comes
-- up clean — is invisible in a single pass and obvious here.
local PASSES = 12

-- The decision gate is real wall-clock (`MIN_PASS_SECONDS`, an anti-bot rate limit measured with
-- os.clock), and the harness clock is virtual, so this is the one place the check has to spend
-- real seconds. ~0.8s per pass.
local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end

-- No character is spawned, here or above. The only thing the server does with one is teleport it
-- to the start pad, which changes nothing this check looks at; and `simulateSpawn` fires
-- CharacterAdded on the main thread, where `onCharacter`'s `task.wait(0.2)` has nothing to yield
-- to and takes the run down. The hall, the roll and the prompts are all built without it.
local me = h:join("Walker", 424242)
h:advance(0.2)
local zone = zoneOf(me)
assert(zone ~= nil, "the walker got no concourse")

local function day()
	local ls = me:FindFirstChild("leaderstats")
	local d = ls and ls:FindFirstChild("Day")
	return d and d.Value or nil
end

local lastSerial, tracked = 0, {}
for p = 1, PASSES do
	local clean, id, serial = attrsOf(zone)
	local matchesClean = not hallDiffers(zone) -- a window, not an instant; see above

	eq(clean, matchesClean, string.format(
		"pass %d: Clean=%s still agrees with the hall standing in the workspace", p, tostring(clean)))
	if clean then
		eq(id, nil, string.format("pass %d: a clean pass carries no leftover AnomalyId", p))
	else
		truthy(id ~= nil and CATALOG[id] ~= nil,
			string.format("pass %d: names a real anomaly (%s)", p, tostring(id)))
	end
	eq(serial, lastSerial + 1, string.format("pass %d: Serial advanced to %d", p, lastSerial + 1))
	lastSerial = serial
	table.insert(tracked, clean and "clean" or tostring(id))

	-- Answer from the WORLD, not from the attribute, and demand the day move. The hall is what
	-- the player sees; if the two ever disagree this stops climbing.
	local before = day()
	local padName = matchesClean and "AdvancePad" or "BackPad"
	local pad = zone:FindFirstChild(padName)
	assert(pad ~= nil, "pass " .. p .. " built no " .. padName)
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	assert(prompt ~= nil, "the " .. padName .. " carries no prompt")
	realWait(0.8)
	-- Fired from a coroutine, not from the main thread. A WRONG call runs a 2.5s death beat
	-- (`task.wait`) inside the handler, and the harness scheduler can only yield a real
	-- coroutine — firing straight from the main thread kills the run with "thread yielded
	-- unexpectedly" the first time an assertion below would have been interesting.
	local co = coroutine.create(function() prompt.Triggered:Fire(me) end)
	local fired, ferr = coroutine.resume(co)
	assert(fired, "pass " .. p .. ": the prompt handler errored: " .. tostring(ferr))
	h:advance(3.5) -- long enough to cover the death beat if this pass was called wrong
	eq(day(), (before or 0) + 1, string.format(
		"pass %d: reading the hall as %s was scored CORRECT (day %s -> %s)",
		p, matchesClean and "clean" or "anomalous", tostring(before), tostring(day())))
	zone = zoneOf(me) -- the same model is rebuilt in place, but never assume it
	assert(zone ~= nil, "the concourse vanished after pass " .. p)
end
print("phase 2: " .. table.concat(tracked, " -> "))

truthy(not h:hadErrors(), "no script errors during the run")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomaly_attrs: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly attribute check failed", 0)
end
