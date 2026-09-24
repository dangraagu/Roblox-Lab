-- Spec for Config.Night: this game's bands, hazards, rest and budgets, and the MEASURED rarity of
-- hazards. Run from the game directory: luau tests/NightConfig.spec.luau
--
-- The rules the eye candy must keep (EYECANDY.md), checked against the real numbers:
--   * the home sky is named by the Journal's rank and deepens with it (dusk -> 3 am); each camp tier
--     has its own place; every band clears the readability floor, and so does every blend of two;
--   * hazards are rare (one every IntervalMin..IntervalMax seconds of hazard time, never two at once),
--     telegraphed for at least MinTelegraphSeconds, and a player who steps out of the red ring when
--     it locks is never hit, from any direction; a player who stays put always is;
--   * rest freezes the hazard clock and never resets it, so toggling rest cannot thin hazards;
--   * the budgets leave room for everything the art can switch on at once.
local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Night = require("../src/shared/Night")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local N = Config.Night
local H = N.Hazards

--================================================================ the bands

do
	local ok, why = Night.validate(Config, EnvBands)
	truthy(ok, "Night.validate accepts Config.Night (" .. tostring(why) .. ")")
	truthy((EnvBands.validate(N.Home)), "Config.Night.Home is a valid EnvBands list")
	truthy((EnvBands.validate(N.Camp)), "Config.Night.Camp is a valid EnvBands list")
end

-- home: named by rank (0 = no cryptid yet, then Common .. Mythic)
local homeIds = {}
for rank = 0, #Config.Tiers do
	homeIds[rank] = N.Home[EnvBands.indexAt(N.Home, rank)].id
end
eq(homeIds[0], homeIds[1], "rank 0 (the first 2 s of a new player) and rank 1 (Common) share the first band")
eq(homeIds[1], "dusk", "rank 1 (Common): dusk")
eq(homeIds[2], "moonrise", "rank 2 (a Rare in the Journal): moonrise")
eq(homeIds[3], "strange", "rank 3 (a Legendary): strange lights")
eq(homeIds[4], "mythic", "rank 4 (the Mythic): mythic night")
eq(#N.Home, 4, "four home bands")
-- camps: one place per camp tier, progress = tier - 1
eq(#N.Camp, #Config.Camps, "one camp band per camp tier")
for tier = 1, #Config.Camps do
	eq(EnvBands.indexAt(N.Camp, tier - 1), tier, "camp tier " .. tier .. " is camp band " .. tier)
end

-- the night deepens with the Journal: every home band later than the last
for i = 2, #N.Home do
	truthy(N.Home[i].lighting.ClockTime > N.Home[i - 1].lighting.ClockTime,
		string.format("%s (%.2f) is later in the night than %s (%.2f)", N.Home[i].id, N.Home[i].lighting.ClockTime, N.Home[i - 1].id, N.Home[i - 1].lighting.ClockTime))
end

-- same fields everywhere (a band missing one would snap that property when it blends)
do
	local ref = N.Home[1]
	local function keys(t)
		local out = {}
		for k in t do table.insert(out, k) end
		table.sort(out)
		return table.concat(out, ",")
	end
	for _, list in { N.Home, N.Camp } do
		for _, b in list do
			for _, g in Night.GROUPS do
				eq(keys(b[g]), keys(ref[g]), b.id .. "." .. g .. " defines the same fields as " .. ref.id)
			end
		end
	end
	-- and the v1 take-over start point defines them too, so the first glide from the server's preset is total
	local base = Night.baseGroups(Config)
	for _, g in Night.GROUPS do
		eq(keys(base[g]), keys(ref[g]), "the v1 base " .. g .. " defines the same fields as the bands")
	end
end

-- every band, and every blend of two bands (what a glide writes), is readable
do
	local all = {}
	for _, b in N.Home do table.insert(all, b) end
	for _, b in N.Camp do table.insert(all, b) end
	table.insert(all, Night.baseGroups(Config))
	local blends, bad = 0, 0
	for _, a in all do
		for _, b in all do
			for _, t in { 0.1, 0.25, 0.5, 0.75, 0.9 } do
				local g = {}
				for _, grp in Night.GROUPS do g[grp] = EnvBands.lerp(a[grp], b[grp], t) end
				blends += 1
				local ok, why = Night.readable(Config, g)
				if not ok then
					bad += 1
					if bad <= 3 then print("  unreadable blend " .. tostring(a.id) .. " > " .. tostring(b.id) .. " @" .. t .. ": " .. tostring(why)) end
				end
				local c = Night.clockTime(g.lighting.ClockTime)
				if c > 6 and c < 17.5 then
					bad += 1
					if bad <= 3 then print("  daylight in blend " .. tostring(a.id) .. " > " .. tostring(b.id)) end
				end
			end
		end
	end
	eq(bad, 0, "all " .. blends .. " blends of two bands (and of v1's lighting) are readable night")
end

-- what each band shows is something the art can build (checked by name; the art is client-only)
for _, list in { N.Home, N.Camp } do
	for _, b in list do
		for _, a in b.ambient do
			truthy(N.Critters[a.kind] ~= nil, b.id .. ": critter " .. tostring(a.kind) .. " has a spec in Config.Night.Critters")
			truthy(type(a.count) == "number" and a.count >= 0, b.id .. ": critter count is a number")
		end
		if b.weather then
			truthy(type(b.weather.kind) == "string" and b.weather.rate > 0, b.id .. ": weather has a kind and a rate")
			truthy(b.weather.rate <= N.Budget.MaxWeatherRate, b.id .. ": weather rate within the weather budget")
		end
		truthy(#b.pieces >= 1, b.id .. ": shows at least one piece of scenery")
	end
end
for _, b in N.Home do
	truthy(#b.hazards >= 1, b.id .. ": has at least one hazard kind")
	for _, k in b.hazards do
		truthy(H.Kinds[k] ~= nil, b.id .. ": hazard " .. k .. " is defined")
	end
end
for _, b in N.Camp do
	eq(#b.hazards, 0, b.id .. ": NO hazards in a camp (a knock there would decide a raid)")
	if b.weather then
		eq(b.weather.at, "campBack", b.id .. ": camp weather is anchored behind the camp, never over the yard")
	end
end
-- camp nights are the camp's own place, not the player's rank: no band id is shared
do
	local seen = {}
	for _, b in N.Home do seen[b.id] = true end
	for _, b in N.Camp do truthy(not seen[b.id], "camp band " .. b.id .. " is not also a home band") end
end

--================================================================ hazards

do
	local ok, why = Hazards.validate(H)
	truthy(ok, "Config.Night.Hazards validates (" .. tostring(why) .. ")")
	truthy(H.IntervalMin >= 120 and H.IntervalMax <= 180, "one hazard every 2-3 minutes of hazard time (owner's brief)")
	truthy(H.MinTelegraphSeconds >= 3, "every hazard is telegraphed for at least 3 s")
	truthy(H.KnockLift <= Hazards.MAX_KNOCK_LIFT, "the knock's lift is capped")
	truthy(H.AfterTutorial >= 4, "no hazard before the tutorial is done")
	truthy(H.SettleSeconds >= 5, "hazards wait at least 5 s after the gate reopens (coming home from a raid)")
	truthy(H.EdgeMarginStuds >= 20, "no hazard within 20 studs of the ground's edge (a knock must never push anyone off the world)")
	-- ...and the margin is a real bound, not a guess: the hardest knock sliding for the whole stumble with NO
	-- friction at all (an upper bound; a real humanoid on grass stops far sooner), plus the player's radius
	do
		local hardest = 0
		for _, k in H.Kinds do hardest = math.max(hardest, k.knock) end
		local slide = hardest * H.KnockSeconds + H.PlayerRadius
		truthy(H.EdgeMarginStuds >= slide, string.format("the edge margin (%d studs) covers the hardest knock's frictionless slide (%d studs/s x %.1f s + %.1f = %.1f)",
			H.EdgeMarginStuds, hardest, H.KnockSeconds, H.PlayerRadius, slide))
	end
	-- the world's edge is a ravine, not a false floor (Night.farGroundRects; review 2026-09-24 finding 1):
	-- nobody can jump it, its cliff faces read as a drop, and the far floor still reaches the horizon.
	-- Jump reach: the game sets no JumpPower/JumpHeight or Gravity (grep src/), so Roblox's defaults apply:
	-- JumpPower 50, Gravity 196.2. Air time landing 1.1 studs lower (the far floor) at WalkSpeed.
	do
		local R = N.Ravine
		truthy(type(R) == "table", "Config.Night.Ravine exists")
		if type(R) == "table" then
			local v, g, drop = 50, 196.2, 1.1
			local air = (v + math.sqrt(v * v + 2 * g * drop)) / g
			local reach = Config.Raid.WalkSpeed * air
			truthy(R.Width >= 2 * reach, string.format("the ravine (%d studs) is at least twice a running jump (%.1f studs at %d studs/s)", R.Width, reach, Config.Raid.WalkSpeed))
			truthy(R.Depth >= 40, "its cliff faces drop at least 40 studs (a visible drop, not a step)")
			truthy(R.FarHalf >= 1000, "the far floor still reaches 1 000 studs from the road's centre (the horizon)")
			truthy(R.MinFar >= 100, "a long road keeps at least 100 studs of far floor beyond the ravine")
			truthy(R.PineMargin >= R.Width + 12 * 1.4 / 2, "far pines (up to 8.4 studs in radius) stand wholly beyond the ravine")
			-- the edge margin gates launches; a knock near the edge is cut (Night.limitKnock) - both need the keep band
			truthy(H.EdgeMarginStuds > H.PlayerRadius, "the launch margin is wider than the knock's keep band")
		end
	end
	-- the view kept clear at home (NightArt:occlude): the character (a 2 x 2 root, arms and a carried cryptid
	-- within about 3 studs) with room to spare, and narrow enough that a zoomed-out camera loses little horizon
	truthy(type(N.HomeViewRadius) == "number" and N.HomeViewRadius >= 3 and N.HomeViewRadius <= 8, "HomeViewRadius covers the character and stays narrow (3..8 studs)")
	for name, k in H.Kinds do
		truthy(type(k.label) == "string" and #k.label > 0, name .. " has a label for the chip")
		-- the warning before a HIT, not just before arrival: a hazard reaches a player who stays put
		-- (hitRadius + PlayerRadius) / speed before it reaches the spot it aims at
		local beforeHit = k.telegraph - (k.hitRadius + H.PlayerRadius) / k.speed
		truthy(beforeHit >= H.MinTelegraphSeconds, string.format("%s: %.2f s from launch to a hit on a player who stays put (>= %.1f)", name, beforeHit, H.MinTelegraphSeconds))
		-- leaving the ring from where you stand, at walk speed, after half a second to react, fits inside the lock
		local exit = (k.hitRadius + H.PlayerRadius) / Config.Raid.WalkSpeed + 0.5
		truthy(exit <= k.commit, string.format("%s: out of the ring in %.2f s (react 0.5 + walk), inside its %.2f s lock", name, exit, k.commit))
	end
end

--================================================================ lanes start on screen, never underground

-- The template centres the lane's start on the camera's pitch. +1 Jump climbs into open sky; here the
-- camera looks DOWN at a player standing on the ground, and a lane centred 22 degrees below the horizon
-- starts inside the ground. Night.hazardPitch keeps the window's top at or above the horizon and holds a
-- launch while the camera looks down more than MaxLookDownDegrees (it waits; the clock is not reset).
do
	for name, k in H.Kinds do
		truthy(k.pitch - (k.pitchSpread or 0) >= 0, name .. ": its natural lane never starts below the player's root height")
	end
	truthy(H.MaxLookDownDegrees >= 30 and H.MaxLookDownDegrees <= 45, "MaxLookDownDegrees is between 30 and 45")
	local s0 = 99
	local function r01()
		s0 = (1664525 * s0 + 1013904223) % 4294967296
		return s0 / 4294967296
	end
	local under, offH, offV, launches, held = 0, 0, 0, 0, 0
	local worstH, worstV = 0, 0
	for camDeg = -60, 60, 5 do
		local camPitch = math.rad(camDeg)
		local ok, usePitch = Night.hazardPitch(Config, camPitch)
		if camDeg < -H.MaxLookDownDegrees then
			eq(ok, false, "a camera pitched " .. camDeg .. " degrees holds the launch")
			held += 1
		else
			truthy(ok, "a camera pitched " .. camDeg .. " degrees may launch")
			for kind in H.Kinds do
				for _ = 1, 40 do
					local yaw = r01() * math.pi * 2
					local aim = { x = 0, y = 3, z = 0 }
					local plan = Hazards.plan(H, kind, aim, yaw, r01, usePitch)
					launches += 1
					if plan.start.y < aim.y - 1e-6 then under += 1 end
					-- the camera: 24 studs back from the player along its look, which is pitched camDeg
					local lx, ly, lz = math.sin(yaw) * math.cos(camPitch), math.sin(camPitch), math.cos(yaw) * math.cos(camPitch)
					local cx, cy, cz = aim.x - lx * 24, aim.y - ly * 24, aim.z - lz * 24
					local tx, ty, tz = plan.start.x - cx, plan.start.y - cy, plan.start.z - cz
					local tl = math.sqrt(tx * tx + ty * ty + tz * tz)
					tx, ty, tz = tx / tl, ty / tl, tz / tl
					local dy = math.abs(((math.atan2(tx, tz) - yaw + math.pi) % (2 * math.pi)) - math.pi)
					local dv = math.abs(math.asin(math.clamp(ty, -1, 1)) - camPitch)
					worstH, worstV = math.max(worstH, math.deg(dy)), math.max(worstV, math.deg(dv))
					if math.deg(dy) > 43 then offH += 1 end
					if math.deg(dv) > 35 then offV += 1 end
				end
			end
		end
	end
	print(string.format("  lane starts: %d launches from cameras pitched -%d..60: %d below the player, %d off screen sideways, %d off screen vertically (worst %.1f / %.1f degrees)",
		launches, H.MaxLookDownDegrees, under, offH, offV, worstH, worstV))
	eq(under, 0, "no lane starts below the player's root height (never out of the ground)")
	eq(offH, 0, "every lane starts within 43 degrees of the camera's heading (a 4:3 screen's half width)")
	eq(offV, 0, "and within 35 degrees of its pitch (the screen's half height)")
	truthy(held > 0, "a camera looking down more steeply than MaxLookDownDegrees holds the launch")
	-- the bug this rule fixes: the template's own window at a camera looking 30 degrees down
	local planRaw = Hazards.plan(H, "crow", { x = 0, y = 3, z = 0 }, 0, function() return 0.5 end, math.rad(-30))
	truthy(planRaw.start.y < 0, string.format("(control) the raw template window at -30 degrees starts a crow at y %.1f, under the ground", planRaw.start.y))
end

--================================================================ rest

do
	local ok, why = Rest.validate(N.Rest)
	truthy(ok, "Config.Night.Rest validates (" .. tostring(why) .. ")")
	local longest = 0
	for _, k in H.Kinds do longest = math.max(longest, k.telegraph + k.pass) end
	truthy(N.Rest.PendingSeconds >= longest + 2, string.format("a queued rest outlives the longest hazard flight (%.1f s) by 2 s (%.1f)", longest, N.Rest.PendingSeconds))
end

--================================================================ budgets

do
	local B = N.Budget
	truthy(B.MaxEmitters >= B.MaxWeatherEmitters + B.MaxHabitatEmitters + 1,
		"MaxEmitters covers weather + habitats + the campfire at once")
	truthy(B.MaxWeatherRate + B.MaxHabitatEmitters * N.Habitats.EmitterRate + N.Campfire.Rate <= B.MaxEmitterRate,
		"weather + the lit habitat + the campfire stay within MaxEmitterRate at once")
	truthy(B.MaxHazards == 1, "one hazard at a time")
	truthy(B.MaxLocalParts <= 220, "local parts budget stays at or under +1 Jump's 220 (mobile)")
	truthy(B.MaxLights <= 3, "at most 3 local lights")
	truthy(B.MaxEmitterRate <= 60, "at most 60 particles/s")
end

--================================================================ strings: ASCII only, no emoji

do
	local nonAscii = {}
	local function scan(v, path)
		if type(v) == "string" then
			if string.find(v, "[\128-\255]") then table.insert(nonAscii, path) end
		elseif type(v) == "table" then
			for k, x in v do scan(x, path .. "." .. tostring(k)) end
		end
	end
	scan(N, "Night")
	eq(#nonAscii, 0, "every string in Config.Night is ASCII (" .. table.concat(nonAscii, ", ") .. ")")
end

--================================================================ MEASURED: rarity

local function lcg(seed)
	local s = seed % 4294967296
	return function()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

-- 1. the raw scheduler, 20 hours of hazard time (home, gate open, not resting)
do
	local rand = lcg(20260923)
	local st = Hazards.newScheduler(H, rand)
	local dt = 1 / 10
	local kinds = N.Home[2].hazards
	local spawns, gaps, last, maxActive = 0, {}, nil, 0
	local total = 20 * 3600
	local t = 0
	while t < total do
		local ev = Hazards.step(st, H, dt, { resting = false, grounded = true, kinds = kinds, aim = { x = 0, y = 3, z = 0 }, yaw = 0, pitch = math.rad(-20) }, rand)
		t += dt
		if ev and ev.type == "spawn" then
			spawns += 1
			if last then table.insert(gaps, st.clock - last) end
			last = st.clock
		end
		if st.active then maxActive = math.max(maxActive, 1) end
	end
	local lo, hi, sum = math.huge, 0, 0
	for _, g in gaps do lo = math.min(lo, g); hi = math.max(hi, g); sum += g end
	local mean = sum / #gaps
	print(string.format("  scheduler, 20 h of hazard time: %d hazards = one per %.1f s (%.3f/min); gaps %.1f..%.1f s", spawns, mean, spawns / (total / 60), lo, hi))
	truthy(lo >= H.IntervalMin - 0.2 and hi <= H.IntervalMax + 0.2, "every gap between hazards is inside IntervalMin..IntervalMax")
	truthy(mean >= 140 and mean <= 160, "one hazard per 2.3-2.7 minutes of hazard time on average")
	eq(maxActive, 1, "never two hazards at once")
end

-- 2. a flight model: every kind, from every heading, for a player who stays put and for one who steps out
--    of the ring at walk speed after it locks (half a second to react, then a 5.6-stud step), in 8 directions
local function fly(kind, seed, dodgeDeg)
	local rand = lcg(seed)
	local pos = { x = 0, y = 3, z = 0 }
	local st = Hazards.newScheduler(H, rand)
	st.nextAt = 0
	local dt = 1 / 30
	local pitch = math.rad(-20 + 40 * rand())
	local ev = Hazards.step(st, H, dt, { resting = false, grounded = true, kinds = { kind }, aim = pos, yaw = rand() * math.pi * 2, pitch = pitch }, rand)
	assert(ev and ev.type == "spawn", "the forced hazard launched")
	local plan = st.active
	local hit, closest = false, math.huge
	local lockedAt = nil
	local moveDir = nil
	while st.active do
		local before = plan.t
		Hazards.step(st, H, dt, { resting = false, grounded = true, kinds = { kind }, aim = pos, yaw = 0, pitch = pitch }, rand)
		if plan.locked and lockedAt == nil then lockedAt = plan.t end
		-- half a second to react, then a short step (0.35 s at walk speed, 5.6 studs): out of the ring
		if dodgeDeg and lockedAt and plan.t - lockedAt >= 0.5 and plan.t - lockedAt < 0.5 + 0.35 then
			if moveDir == nil then
				-- measured from the hazard's travel direction, flattened (0 = straight back along the lane)
				local v = plan.velocity
				local a = math.atan2(v.x, v.z) + math.rad(dodgeDeg)
				moveDir = { x = math.sin(a), z = math.cos(a) }
			end
			pos = { x = pos.x + moveDir.x * Config.Raid.WalkSpeed * dt, y = pos.y, z = pos.z + moveDir.z * Config.Raid.WalkSpeed * dt }
		end
		if Hazards.checkHit(plan, before, plan.t, pos, H.PlayerRadius) then
			hit = true
			plan.hit = true
		end
		local hp = Hazards.positionAt(plan, plan.t)
		closest = math.min(closest, Hazards.distance(hp, pos))
	end
	return hit, closest
end

do
	local stayHits, stayN = 0, 0
	local dodgeHits, dodgeN, nearMiss = 0, 0, 0
	local perDir = {}
	local seed = 1
	for kind in H.Kinds do
		for _ = 1, 12 do
			seed += 1
			local hit = fly(kind, seed, nil)
			stayN += 1
			if hit then stayHits += 1 end
			for d = 0, 315, 45 do
				local h2, closest = fly(kind, seed, d)
				dodgeN += 1
				if h2 then
					dodgeHits += 1
					perDir[d] = (perDir[d] or 0) + 1
				end
				if closest <= H.NearMissStuds then nearMiss += 1 end
			end
		end
	end
	print(string.format("  flight model: stays put %d of %d hit; steps out of the ring at the lock %d of %d hit (8 directions); %d of %d dodges were near-hits (<= %d studs)",
		stayHits, stayN, dodgeHits, dodgeN, nearMiss, dodgeN, H.NearMissStuds))
	eq(stayHits, stayN, "a player who stays put is hit by every hazard (a near-hit by construction)")
	eq(dodgeHits, 0, "a player who steps out of the ring when it locks is never hit, in any of 8 directions")
	truthy(nearMiss >= dodgeN * 0.95, "and it is still a close call: the hazard passes within NearMissStuds")
end

-- 3. rest toggling cannot thin hazards: rest freezes the clock, never resets it
do
	local function hazardsPerHazardHour(pattern)
		local rand = lcg(7)
		local st = Hazards.newScheduler(H, rand)
		local dt = 1 / 10
		local climb, spawns, t = 0, 0, 0
		while climb < 6 * 3600 do
			local resting = pattern(t)
			local ev = Hazards.step(st, H, dt, { resting = resting, grounded = true, kinds = { "crow" }, aim = { x = 0, y = 3, z = 0 }, yaw = 0, pitch = 0 }, rand)
			if not resting then climb += dt end
			if ev and ev.type == "spawn" then spawns += 1 end
			t += dt
		end
		return spawns
	end
	local never = hazardsPerHazardHour(function() return false end)
	local toggles = hazardsPerHazardHour(function(t) return math.floor(t / 7) % 2 == 1 end)
	local long = hazardsPerHazardHour(function(t) return (t % 150) < 40 end)
	print(string.format("  rest probe, 6 h of hazard time: never rests %d, toggles every 7 s %d, rests 40 s of every 150 s %d", never, toggles, long))
	eq(toggles, never, "toggling rest every 7 s does not thin hazards per hour of hazard time")
	eq(long, never, "long rests do not thin hazards per hour of hazard time")
end

print(string.format("NightConfig: %d passed, %d failed", passed, failed))
if failed > 0 then error("NightConfig spec failed", 0) end
