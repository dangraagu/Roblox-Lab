-- anomaly-observatory — the critters: every band's own wildlife, and the game's harmless RARE events.
-- Run: luau check_anomalyobservatory_critters.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- docs/complete-game-standard.md §2 (2026-10-01): each band has its own critters, and a genre with no place
-- for hazards gets harmless rare events instead. This game has no hazards (nothing chases you is the
-- premise), so the two are one thing: now and then something flies past beyond the entrance: fireflies
-- (Clear Night), bats across the moon (Meteor Shower), geese (Aurora), an owl (the Comet), nothing in the
-- Storm Front (animals shelter; the band says so), fireflies and the owl (Deep Sky), geese and bats (the
-- Alignment), wisps (The Other Sky). Measured through the REAL server and the real sky client, at Days
-- reached by answering real passes:
--
--   1. the client flies EXACTLY the flights the pure schedule says (NightSky.slotEvent + critterPick with the
--      Day's weights), slot by slot: the right kind, or none; so the rate per band is the schedule's
--      (tests/NightSky.spec.luau measures that over 20 000 slots: 0.4 a minute at full weight);
--   2. at most one flight at a time, and a flight lasts no longer than its kind's Duration;
--   3. on EVERY frame every visible critter has all eight corners beyond the hall's entrance plane +
--      Clearance, is not reddish, cannot be touched, collided with or hit by a ray; the sky owns no Light;
--   4. the Storm Front flies nothing; every other band flies only its own kinds;
--   5. the sky's parts stay within the part budget on every frame, flights included; the character is never
--      moved by any of it;
--   6. no flight pops: a critter never leaves the sky while still clearly visible, not even when its band's
--      folder is dropped mid-flight (found by the sky check's climb on the first build: fireflies vanished at
--      transparency 0.48-0.82 when the Day passed 40). Forced here: a firefly flight in the air, then the
--      Day jumps past the fireflies' bands, so their weight glides to nothing while the flight is still out.

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")
local EnvBands = require("../anomaly-observatory/src/shared/EnvBands")

local Sky = Config.Sky
local bands = Sky.Bands
local Cr = Sky.Critters

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

truthy(type(Cr) == "table" and type(NightSky.critterPick) == "function", "Config.Sky.Critters and NightSky's critter schedule exist")
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Birdwatcher", 27182)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
local hrp = char:FindFirstChild("HumanoidRootPart")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local origin = NightSky.hallOrigin(Sky.Hall, tonumber(zone:GetAttribute("Index")))
local cam = h.workspace.CurrentCamera
local hallCam = CFrame.lookAt(Vector3.new(origin.x, origin.y + 8, origin.z + 6), Vector3.new(origin.x, origin.y + 6, origin.z - 80))

local function infoOf()
	return h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId))
end
local function day(): number
	return plr.leaderstats.Day.Value
end
local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function answerRight()
	local clean = infoOf():GetAttribute("Clean") == true
	local pad = zone:FindFirstChild(if clean then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	local ok, err = coroutine.resume(co)
	assert(ok, "prompt handler errored: " .. tostring(err))
end

-- ------------------------------------------------------------------ the frame watcher
-- The sky's own clock is the sum of the frame times it was given (Sky.client: clock += clamp(dt, 0, 0.1)).
-- Every RenderStepped here is fired by this file, so summing the same DT the same way IS that clock.
local DT = 1 / 15
local skyClock = 0
local folder: any = nil
local frames = 0
local nearCount, near = 0, {}
local worstZ = math.huge
local badPart = {}
local maxKindsAtOnce = 0
local visibleSince: { [string]: number } = {} -- kind -> skyClock when its current flight became visible
local longest: { [string]: number } = {}
local seenInSlot: { [number]: { [string]: boolean } } = {}
local peakParts = 0
local lights = 0
local charMoved, tracking, hrp0 = 0, false, hrp.CFrame
local lastT: { [any]: number } = {} -- critter part -> transparency last frame, while visible
local pops = {}
local POP_BELOW = 0.85 -- a flight's own fade-out ends above this (bats: 0.5 s ramp at 15 fps -> >= 0.87)

local function critterKindOf(name: string): string?
	local k = string.match(name, "^Critter_(%a+)%d+$")
	return k
end

local function watch()
	frames += 1
	if tracking and hrp.CFrame ~= hrp0 then charMoved += 1 end
	if folder == nil then folder = h.workspace:FindFirstChild("ObservatorySky") end
	if folder == nil then return end
	local parts = 0
	local kindsNow: { [string]: boolean } = {}
	local slot = NightSky.slotOf(Cr, skyClock)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			local kind = critterKindOf(d.Name)
			if kind and d.Transparency < 1 and d:IsDescendantOf(h.workspace) then
				kindsNow[kind] = true
				local half = d.Size / 2
				local minZ = math.huge
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local w = d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
							if w.Z < minZ then minZ = w.Z end
						end
					end
				end
				local rel = minZ - origin.z
				if rel < worstZ then worstZ = rel end
				if rel <= Sky.Hall.Front + Sky.Clearance then
					nearCount += 1
					if #near < 5 then table.insert(near, string.format("%s z %.1f", d.Name, rel)) end
				end
				local c = d.Color
				if NightSky.isReddish({ c.R * 255, c.G * 255, c.B * 255 }) or d.CanCollide or d.CanTouch or d.CanQuery then
					if #badPart < 5 then table.insert(badPart, d.Name) end
				end
			end
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	if parts > peakParts then peakParts = parts end
	-- pops: a critter that was clearly visible last frame and is gone (or fully transparent) this frame
	local nowT: { [any]: number } = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and critterKindOf(d.Name) and d:IsDescendantOf(h.workspace) and d.Transparency < 1 then
			nowT[d] = d.Transparency
		end
	end
	for d, t in lastT do
		if nowT[d] == nil and t < POP_BELOW then
			if #pops < 6 then table.insert(pops, string.format("%s left at transparency %.2f (Day %d)", d.Name, t, day())) end
		end
	end
	lastT = nowT
	local n = 0
	for kind in kindsNow do
		n += 1
		seenInSlot[slot] = seenInSlot[slot] or {}
		seenInSlot[slot][kind] = true
		if visibleSince[kind] == nil then visibleSince[kind] = skyClock end
		local dur = skyClock - visibleSince[kind]
		if dur > (longest[kind] or 0) then longest[kind] = dur end
	end
	for kind in visibleSince do
		if not kindsNow[kind] then visibleSince[kind] = nil end
	end
	if n > maxKindsAtOnce then maxKindsAtOnce = n end
end

local function frame()
	cam.CFrame = hallCam
	RunService.RenderStepped:Fire(DT)
	skyClock += DT
	h:advance(DT)
	watch()
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end

local function goToDay(target: number)
	while day() < target do
		answerRight()
		run(0.3)
	end
	eq(day(), target, "reached Day " .. target .. " through the server's prompts")
end

-- Watch the settled sky of the current Day, slot by slot, until `want` flights were scheduled (or `capMin`
-- minutes passed); compare every whole slot with the pure schedule.
local report = {}
local function watchDay(label: string, want: number, capMin: number)
	run(20) -- the glide into this Day's sky arrives and settles
	local weights = NightSky.features(bands, EnvBands, day())
	hrp0 = hrp.CFrame
	tracking = true
	local firstSlot = NightSky.slotOf(Cr, skyClock) + 1
	run((firstSlot * Cr.SlotSeconds) - skyClock + 0.001) -- start on a slot boundary
	local slot = firstSlot
	local scheduled, flown, mismatch = 0, 0, {}
	local kinds = {}
	local t0 = skyClock
	while (scheduled < want) and (skyClock - t0) < capMin * 60 do
		run(Cr.SlotSeconds)
		local ev = NightSky.slotEvent(Cr, slot, Sky.Seed, EnvBands)
		local expect = NightSky.critterPick(Sky, weights, ev)
		local seen = seenInSlot[slot] or {}
		local seenList = {}
		for k in seen do table.insert(seenList, k) end
		table.sort(seenList)
		local got = table.concat(seenList, "+")
		if expect then scheduled += 1 end
		if got ~= "" then flown += 1; kinds[got] = (kinds[got] or 0) + 1 end
		if got ~= (expect or "") then
			table.insert(mismatch, string.format("slot %d: flew '%s', schedule '%s'", slot, got, tostring(expect)))
		end
		slot += 1
	end
	tracking = false
	local minutes = (skyClock - t0) / 60
	local kindList = {}
	for k, n in kinds do table.insert(kindList, k .. " x" .. n) end
	table.sort(kindList)
	print(string.format("   Day %2d  %-14s %5.1f min  %2d flights (%.2f a minute)  %s", day(), label, minutes, flown, flown / minutes,
		table.concat(kindList, ", ")))
	eq(#mismatch, 0, label .. ": the client flies exactly the scheduled flights, slot by slot: " .. table.concat(mismatch, "; "))
	report[label] = { flown = flown, kinds = kinds, minutes = minutes, weights = weights }
	return report[label]
end

-- the kinds a band may fly: those with weight
local function onlyOwn(r, label: string)
	local stray = {}
	for got in r.kinds do
		for kind in string.gmatch(got, "[^+]+") do
			if (r.weights[kind] or 0) <= 0 then table.insert(stray, kind) end
		end
	end
	eq(#stray, 0, label .. " flies only its own critters: " .. table.concat(stray, ", "))
end

local plan = {
	{ day = 1, label = "Clear Night" },
	{ day = 6, label = "Meteor Shower" },
	{ day = 12, label = "Aurora" },
	{ day = 18, label = "Great Comet" },
	{ day = 25, label = "Storm Front" },
	{ day = 34, label = "Deep Sky" },
	{ day = 44, label = "Alignment" },
	{ day = 55, label = "Other Sky" },
}
for _, step in plan do
	goToDay(step.day)
	if step.label == "Storm Front" then
		local r = watchDay(step.label, 1, 10)
		eq(r.flown, 0, "the Storm Front flies nothing (its band says why)")
		truthy(type(bands[EnvBands.indexAt(bands, day())].critterless) == "string", "and the band carries the reason")
	else
		local r = watchDay(step.label, 3, 30)
		truthy(r.flown >= 3, string.format("%s: its critters fly (%d flights in %.1f min)", step.label, r.flown, r.minutes))
		onlyOwn(r, step.label)
	end
end

-- ------------------------------------------------------------------ a band ends mid-flight
-- Back to Deep Sky (fireflies 0.5, owl 0.5) through the Day the sky reads, wait for a firefly flight to be
-- in the air, then jump past both their bands (The Alignment has neither): their weight glides from 0.5 to
-- nothing in about 9.6 s (GlideHalfLife 1.2), inside a 12 s flight.
do
	local dayValue = plr.leaderstats.Day
	dayValue.Value = 34
	run(20)
	local waited, flying = 0, false
	while waited < 30 * 60 and not flying do
		run(DT)
		waited += DT
		for d in lastT do
			if critterKindOf(d.Name) == "fireflies" then flying = true end
		end
	end
	truthy(flying, string.format("a firefly flight came up at Deep Sky (after %.0f s)", waited))
	local popsBefore = #pops
	dayValue.Value = 45
	run(20)
	local anyLeft = false
	for d in lastT do if critterKindOf(d.Name) == "fireflies" or critterKindOf(d.Name) == "owl" then anyLeft = true end end
	eq(anyLeft, false, "their band is gone and so are they")
	eq(#pops - popsBefore, 0, "and the flight faded with its band instead of vanishing mid-air")
end

-- ------------------------------------------------------------------ verdicts
print(string.format("   %d frames watched; nearest visible critter %.1f studs beyond the hall origin (entrance %d + clearance %d); peak sky parts %d",
	frames, worstZ, Sky.Hall.Front, Sky.Clearance, peakParts))
eq(nearCount, 0, "on EVERY frame every visible critter is beyond the entrance plane + Clearance: " .. table.concat(near, "; "))
eq(#badPart, 0, "no critter is reddish, collidable, touchable or ray-queryable: " .. table.concat(badPart, ", "))
eq(lights, 0, "the sky owns no Light")
eq(maxKindsAtOnce, 1, "one flight at a time (never two kinds in the sky at once)")
local tooLong = {}
for kind, d in longest do
	if d > Cr.Kinds[kind].Duration + DT + 1e-6 then
		table.insert(tooLong, string.format("%s %.2f s > %.2f", kind, d, Cr.Kinds[kind].Duration))
	end
end
eq(#tooLong, 0, "a flight lasts no longer than its kind's Duration: " .. table.concat(tooLong, "; "))
truthy(peakParts <= Sky.Budget.MaxParts, string.format("peak sky parts %d <= %d, flights included", peakParts, Sky.Budget.MaxParts))
eq(charMoved, 0, "nothing in the sky ever moves the player's character")
eq(#pops, 0, "no critter ever vanishes while still visible: " .. table.concat(pops, "; "))
truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomalyobservatory_critters: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory critters check failed", 0)
end
