-- Escape Room Lab's environment config, checked against the rules the generic modules and the
-- owner's standard set (DESIGN.md §7, §8, §9). Run: luau tests/EnvConfig.spec.luau 2>&1
--
-- The template modules (EnvBands, Hazards, Rest) validate SHAPE. This file checks this game's
-- specifics: six bands driven by progress, every band blending the same fields, a vertical hazard
-- lane that starts under a 16-stud ceiling, a ring that IS the hit zone, the rest adaptation
-- (IdleSeconds = 0) pinned with its reason, and the budgets present. The hazard part is
-- design/hazard_probe.luau turned into assertions, run through this game's own copies.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Lab = require("../src/shared/Lab")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local Env, Hz = Config.Env, Config.Hazards
local bands = Env.Bands

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "Config.Env.Bands validates (" .. tostring(err) .. ")")
	ok, err = Hazards.validate(Hz)
	truthy(ok, "Config.Hazards validates (" .. tostring(err) .. ")")
	ok, err = Rest.validate(Config.Rest)
	truthy(ok, "Config.Rest validates (" .. tostring(err) .. ")")
end

--============================================================ six bands, one per wing plus the Roof
local IDS = { "reception", "archive", "greenhouse", "coldstore", "reactor", "roof" }
eq(#bands, 6, "six bands")
for i, id in IDS do
	local b = bands[i]
	eq(b and b.id, id, "band " .. i .. " is " .. id)
	eq(b and b.from, i - 1, "band " .. i .. " starts at progress " .. (i - 1))
	if i > 1 then
		truthy(b and math.abs(b.fade - 1 / 3) < 1e-9, "band " .. i .. " fades in over 1/3: the last room of the wing before")
	end
	truthy(type(b.name) == "string" and #b.name > 2, id .. " has a name")
end
eq(bands[1].fade or 0, 0, "the first band does not fade")

-- the seep-in: in the last room of wing w (p from w - 1/3 to w) the next band grows from 0 to 1
do
	for w = 1, 5 do
		local spec = Lab.roomSpec(Config, Lab.slotOf(w, 3))
		local n = #spec.stations
		local pStart = Lab.progress(w, 3, 0, n)
		local pEnd = Lab.progress(w, 3, n, n)
		local _, jStart, tStart = EnvBands.locate(bands, pStart)
		local iEnd = EnvBands.indexAt(bands, pEnd)
		truthy(tStart < 1e-9 or jStart == w, "wing " .. w .. " room 3 begins with no next band showing")
		eq(iEnd, w + 1, "wing " .. w .. "'s last door open puts the player fully in band " .. (w + 1))
		if n > 1 then
			local _, jMid, tMid = EnvBands.locate(bands, Lab.progress(w, 3, 1, n))
			truthy(jMid == w + 1 and tMid > 0 and tMid < 1, "wing " .. w .. " room 3, one station solved: the next band is seeping in")
		end
		local n2 = #Lab.roomSpec(Config, Lab.slotOf(w, 2)).stations
		local pRoom2 = Lab.progress(w, 2, n2, n2)
		local _, j2, t2 = EnvBands.locate(bands, pRoom2 - 1e-6)
		truthy(t2 < 1e-6 or j2 == w, "wing " .. w .. " room 2 shows no next band")
	end
end

--============================================================ every band blends the same fields
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sky" }
for _, g in GROUPS do
	local keys = {}
	for k in bands[1][g] or {} do table.insert(keys, k) end
	table.sort(keys)
	truthy(#keys > 0, "band 1 defines " .. g)
	for i = 2, #bands do
		local other = {}
		for k in bands[i][g] or {} do table.insert(other, k) end
		table.sort(other)
		eq(table.concat(other, ","), table.concat(keys, ","), bands[i].id .. " defines the same " .. g .. " fields as band 1")
	end
end
for _, b in bands do
	for _, g in GROUPS do
		for k, v in b[g] or {} do
			if type(v) == "table" then
				truthy(#v == 3 and v[1] >= 0 and v[1] <= 255 and v[2] >= 0 and v[2] <= 255 and v[3] >= 0 and v[3] <= 255,
					b.id .. "." .. g .. "." .. k .. " is an {r, g, b} in 0..255")
			end
		end
	end
	truthy(type(b.palette) == "table" and type(b.palette.wall) == "table" and type(b.palette.floor) == "table",
		b.id .. " has a room palette (the server builds its shell in the wing's colours)")
	truthy(type(b.light) == "table" and type(b.light.color) == "table", b.id .. " has a ceiling light colour")
	truthy(#(b.critters or {}) >= 1, b.id .. " has creatures")
	truthy(#(b.weather or {}) >= 1, b.id .. " has weather")
end
do
	-- each band looks different from its neighbours
	for i = 2, #bands do
		local a, b = bands[i - 1].lighting.Ambient, bands[i].lighting.Ambient
		local d = math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])
		local ta, tb = bands[i - 1].colorCorrection.TintColor, bands[i].colorCorrection.TintColor
		d += math.abs(ta[1] - tb[1]) + math.abs(ta[2] - tb[2]) + math.abs(ta[3] - tb[3])
		truthy(d >= 30, bands[i].id .. " differs from " .. bands[i - 1].id .. " in light and grade (" .. d .. ")")
	end
end
eq(bands[6].sky.StarCount, 3000, "the Roof has 3000 stars")
truthy(bands[6].lighting.ClockTime <= 1 or bands[6].lighting.ClockTime >= 22, "the Roof is at night")
eq(Env.HalfLife, 0.6, "a lift ride glides over 0.6 s (+1 Jump's number)")
eq(Env.LightingHz, 10, "Lighting written at most 10 times a second")

--============================================================ hazards: one kind per hazard band, none in Reception or on the Roof
eq(#(bands[1].hazards or {}), 0, "Reception (the onboarding wing) has no hazard")
eq(#(bands[6].hazards or {}), 0, "the Roof (the brag) is peaceful")
do
	local want = { archive = "spider", greenhouse = "seedpod", coldstore = "icedrone", reactor = "claw" }
	for id, kind in want do
		local b = bands[EnvBands.indexOf(bands, id)]
		eq(#b.hazards, 1, id .. " has one hazard kind")
		eq(b.hazards[1], kind, id .. "'s hazard is the " .. kind)
		truthy(Hz.Kinds[kind] ~= nil, kind .. " is defined")
	end
	local n = 0
	for _ in Hz.Kinds do n += 1 end
	eq(n, 4, "four hazard kinds")
end
-- review-1 B4: exposed time is now only a legal spot past the arrival grace (the door station no longer counts),
-- so 80-120 s of it is one per 2-3 minutes of play (rev3_path x8: median gaps 170-206 s); 120-180 gave 241-302 s
eq(Hz.IntervalMin, 80, "one hazard per 80-120 s of exposed time: min")
eq(Hz.IntervalMax, 120, "max")
eq(Hz.KnockLift, 0, "a knock never lifts (a walled room: a stumble, not a launch)")
eq(Hz.PitchDegrees, 85, "the glue passes a pitch of 85 degrees")
for name, k in Hz.Kinds do
	eq(k.pitch, 85, name .. ": pitch 85 (the lane comes from the ceiling)")
	eq(k.pitchSpread or 0, 0, name .. ": no pitch spread")
	truthy(k.speed * k.telegraph <= Config.World.RoomHeight - 4,
		string.format("%s: the lane starts at most 12 studs out (speed %.1f x telegraph %.1f), under the ceiling",
			name, k.speed, k.telegraph))
	truthy(k.telegraph >= 3, name .. ": at least 3 s of warning")
end
do
	local longest = 0
	for _, k in Hz.Kinds do longest = math.max(longest, k.telegraph + k.pass) end
	truthy(Config.Rest.PendingSeconds >= longest + 2, string.format("a queued Break (%.1f s) outlives the longest flight (%.1f s) + 2 s",
		Config.Rest.PendingSeconds, longest))
end

--============================================================ the rest adaptation, pinned
eq(Config.Rest.IdleSeconds, 0,
	"IdleSeconds is 0 on purpose: standing still is how a puzzle is thought through (DESIGN.md §9)")
eq(Config.Rest.WakeOnMove, true, "WakeOnMove")
eq(Config.Rest.BlockWhileThreat, true, "BlockWhileThreat")

--============================================================ the probe: run the template against this config
local seed = 12345
local function rand()
	seed = (1664525 * seed + 1013904223) % 4294967296
	return seed / 4294967296
end
local PITCH = math.rad(Hz.PitchDegrees)
local ROOT_Y = 3 -- the root stands 3 studs over a floor at y 0
do
	local maxY, maxH = -math.huge, 0
	for _ = 1, 2000 do
		local p = Hazards.plan(Hz, "spider", { x = 0, y = ROOT_Y, z = 0 }, rand() * math.pi * 2, rand, PITCH)
		maxY = math.max(maxY, p.start.y)
		maxH = math.max(maxH, math.sqrt((p.start.x - p.target.x) ^ 2 + (p.start.z - p.target.z) ^ 2))
	end
	print(string.format("  lane start y <= %.3f under a %d-stud ceiling; <= %.3f studs sideways of the target",
		maxY, Config.World.RoomHeight, maxH))
	truthy(maxY <= Config.World.RoomHeight - 1, "every lane starts at least 1 stud under the ceiling (room for a 2-stud model)")
	truthy(maxH <= 1.1, "every lane starts within 1.1 studs sideways of its target: straight down")
	local z = Hazards.zone(Hazards.plan(Hz, "spider", { x = 0, y = ROOT_Y, z = 0 }, 0, rand, PITCH), Hz.PlayerRadius)
	eq(z.radius * 2, 7, "the ring is 7 studs wide")
end
local function trial(dirDeg, walk)
	local state = Hazards.newScheduler(Hz, rand)
	state.clock = state.nextAt
	local pos = { x = 0, y = ROOT_Y, z = 0 }
	local ctx = function(p) return { resting = false, grounded = true, kinds = { "spider" }, aim = p, yaw = 0, pitch = PITCH } end
	local ev = Hazards.step(state, Hz, 0, ctx(pos), rand)
	local plan = ev.plan
	local dt, t, walked, hit = 1 / 60, 0, 0, false
	while t < 6 do
		local t0 = plan.t
		if walk and plan.locked then
			local step = math.min(Config.World.WalkSpeed * dt, 3.9 - walked)
			if step > 0 then
				pos = { x = pos.x + math.cos(math.rad(dirDeg)) * step, y = ROOT_Y, z = pos.z + math.sin(math.rad(dirDeg)) * step }
				walked += step
			end
		end
		Hazards.step(state, Hz, dt, ctx(pos), rand)
		if state.active ~= plan then break end
		if Hazards.checkHit(plan, t0, plan.t, pos, Hz.PlayerRadius) then
			hit = true
			plan.hit = true
		end
		t += dt
	end
	return hit
end
do
	local stand, walked = 0, 0
	for d = 0, 350, 10 do
		if trial(d, false) then stand += 1 end
		if trial(d, true) then walked += 1 end
	end
	print(string.format("  stand still: %d of 36 hit; walk 3.9 studs out after the lock: %d of 36 hit", stand, walked))
	eq(stand, 36, "standing still is hit, every direction")
	eq(walked, 0, "stepping out of the ring after the lock dodges, every direction")
end
-- Review-1 finding B1: the ring must stand still from its FIRST frame, and stepping out of it at any moment
-- before the hit must dodge. Before the fix the lane re-aimed at the player for the first 1.5 s (commit), so
-- the ring followed whoever stepped out, and a slow ceiling drop (4 studs/s) touches a 3.5-stud zone 0.875 s
-- before its arrival time: the only window that dodged was 1.45-2.05 s after the ring showed (the reviewer's
-- sweep: 108 of 108 hit for reactions up to 1.40 s).
local function reactTrial(dirDeg: number, react: number): (boolean, number, number)
	local state = Hazards.newScheduler(Hz, rand)
	state.clock = state.nextAt
	local pos = { x = 0, y = ROOT_Y, z = 0 }
	local ctx = function(p) return { resting = false, grounded = true, kinds = { "spider" }, aim = p, yaw = 0, pitch = PITCH } end
	local plan = Hazards.step(state, Hz, 0, ctx(pos), rand).plan
	local z0 = Hazards.zone(plan, Hz.PlayerRadius)
	local dt, t, walked, hitAt, moved = 1 / 60, 0, 0, nil, 0
	while true do
		local t0 = plan.t
		if t >= react then
			local stepLen = math.min(Config.World.WalkSpeed * dt, 3.9 - walked)
			if stepLen > 0 then
				pos = { x = pos.x + math.cos(math.rad(dirDeg)) * stepLen, y = ROOT_Y, z = pos.z + math.sin(math.rad(dirDeg)) * stepLen }
				walked += stepLen
			end
		end
		Hazards.step(state, Hz, dt, ctx(pos), rand)
		if state.active ~= plan then break end
		local z = Hazards.zone(plan, Hz.PlayerRadius)
		moved = math.max(moved, math.sqrt((z.x - z0.x) ^ 2 + (z.z - z0.z) ^ 2))
		if hitAt == nil and Hazards.checkHit(plan, t0, plan.t, pos, Hz.PlayerRadius) then
			hitAt = plan.t
			plan.hit = true
		end
		t += dt
	end
	return hitAt ~= nil, moved, hitAt or -1
end
do
	local hits, trials, maxMoved = 0, 0, 0
	local firstHitReact = nil
	for ri = 0, 18 do
		local react = ri * 0.1
		for d = 0, 350, 10 do
			local hit, moved = reactTrial(d, react)
			trials += 1
			maxMoved = math.max(maxMoved, moved)
			if hit then
				hits += 1
				firstHitReact = firstHitReact or react
			end
		end
	end
	print(string.format("  step out 3.9 studs after 0.0-1.8 s, 36 directions: %d of %d hit; the ring moved at most %.3f studs",
		hits, trials, maxMoved))
	eq(hits, 0, "stepping out at ANY time in the first 1.8 s after the ring shows dodges, every direction")
	truthy(maxMoved < 1e-9, string.format("the ring never moves once it shows (moved %.3f studs)", maxMoved))
	local still, _, stillAt = reactTrial(0, math.huge)
	truthy(still and stillAt >= 2.0, string.format("a player who never moves is hit, no sooner than 2.0 s after the ring shows (%.3f s)", stillAt))
end
do
	local st = Hazards.newScheduler(Hz, rand)
	local n, t, T = 0, 0, 20 * 3600
	while t < T do
		local e = Hazards.step(st, Hz, 0.5, { resting = false, grounded = true, kinds = { "spider" }, aim = { x = 0, y = 3, z = 0 }, yaw = 0, pitch = PITCH }, rand)
		if e and e.type == "spawn" then n += 1 end
		t += 0.5
	end
	print(string.format("  20 h exposed: %d hazards = one per %.1f s", n, T / n))
	truthy(T / n >= 92 and T / n <= 108, "about one per 100 s of exposed time (one near-miss per 2-3 minutes of play: Pacing.spec)")
end
do
	local kv = Hazards.knockVelocity(Hz, Hazards.plan(Hz, "spider", { x = 0, y = 3, z = 0 }, 0, rand, PITCH), { x = 0.5, y = 3, z = 0.2 })
	local horiz = math.sqrt(kv.x * kv.x + kv.z * kv.z)
	print(string.format("  knock (%.1f, %.1f, %.1f)", kv.x, kv.y, kv.z))
	truthy(math.abs(horiz - 20) < 0.01 and kv.y == 0, "a hit is 20 studs/s sideways and no lift")
end

--============================================================ budgets exist and are sane
local B = Config.Budget
for _, k in { "LocalParts", "Emitters", "WeatherEmitters", "MaxEmitterRate", "Beams", "Trails", "LocalLights", "DecorPerBand", "HazardParts" } do
	truthy(type(B[k]) == "number" and B[k] > 0, "Config.Budget." .. k .. " is set")
end
eq(B.LocalParts, 120, "120 local parts")
eq(B.Emitters, 3, "3 emitters (2 weather + 1 hazard)")
eq(B.WeatherEmitters, 2, "2 weather emitters")
eq(Config.World.MaxRoomParts, 160, "160 server parts per room")

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
if failed > 0 then error("EnvConfig spec failed", 0) end
