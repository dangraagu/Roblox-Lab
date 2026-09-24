-- EnvConfig: the SHIPPED Config.Env / Hazards / Rest / Budget, checked as data. Run: luau tests/EnvConfig.spec.luau
--
-- The pure modules are tested with their own small configs. This file asks whether the numbers the game
-- actually ships obey every rule those modules and the brief lay down: the bands blend, stay fair to the
-- chase, name hazards that exist; the hazards validate, start on screen and can be stepped out of; rest
-- never reaches into the night; the budgets are coherent.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Nightfall = require("../src/shared/Nightfall")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Env, Hz = Config.Env, Config.Hazards
local bands = Env.Bands

--================================================================ the bands

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "Config.Env.Bands validates (" .. tostring(err) .. ")")
	truthy(#bands >= 5, "at least five bands, so a long session keeps changing (" .. #bands .. ")")
	for i, b in bands do
		truthy(type(b.from) == "number" and b.from == math.floor(b.from), b.id .. ": `from` is a whole night")
		if i > 1 then
			truthy(type(b.fade) == "number" and b.fade > 0 and b.fade <= 1, string.format(
				"%s: fades in over at most the one night before it (fade %s), so dread foreshadows it", b.id, tostring(b.fade)))
			truthy(b.fade <= Env.DreadLookahead + 1e-9, b.id .. ": ...and within what a full-dread night can reach")
		end
		truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string", b.id .. ": has a name and an emoji for the chip")
		-- every band names every glow and every outside value, so a blend between two bands always has both
		-- ends (EnvBands.lerp with a nil side SNAPS to the other side: a key only one band had would cut, not glide)
		for _, key in { "sky", "moon", "corona", "eyes", "flash", "dust" } do
			local c = b.glow and b.glow[key]
			truthy(type(c) == "table" and #c == 3, b.id .. ": glow." .. key .. " is an {r, g, b}")
		end
		for _, key in { "moonSize", "mist", "rain", "stars", "cloud", "eclipse" } do
			truthy(type(b.outside and b.outside[key]) == "number", b.id .. ": outside." .. key .. " is set (a number, so it blends)")
		end
		for _, key in { "mist", "stars", "cloud", "eclipse" } do
			local x = b.outside and b.outside[key]
			truthy(type(x) == "number" and x >= 0 and x <= 1, b.id .. ": outside." .. key .. " is a fraction 0..1")
		end
		for _, key in { "dust", "flicker", "sway", "eyes" } do
			truthy(type(b.inside and b.inside[key]) == "number", b.id .. ": inside." .. key .. " is set")
		end
		truthy(b.inside.flicker >= 0 and b.inside.flicker <= 1, b.id .. ": inside.flicker is a fraction of FlickerAmp")
		if b.lightning then
			truthy(b.lightning.everyMin > 0 and b.lightning.everyMax >= b.lightning.everyMin, b.id .. ": lightning interval is ordered")
			truthy(b.lightning.everyMin >= Nightfall.HARD.FlashGapMin, b.id .. ": no strobe: the band itself asks for at least the hard floor between flashes")
			-- what a player really gets (review 4: the config said 5-11 s, the client gave 2.7 s): the real gap at the
			-- quietest and the most dreadful moment of a night, as the client computes it
			local lo0, hi0 = Nightfall.boltGap(b.lightning, 0, 0), Nightfall.boltGap(b.lightning, 0, 1)
			local lo1, hi1 = Nightfall.boltGap(b.lightning, 1, 0), Nightfall.boltGap(b.lightning, 1, 1)
			print(string.format("  %-9s lightning: every %.1f-%.1f s at dread 0, %.1f-%.1f s at full dread", b.id, lo0, hi0, lo1, hi1))
			truthy(lo1 >= Nightfall.HARD.FlashGapMin, b.id .. ": even at full dread the gap is at least the floor (" .. lo1 .. " s)")
		end
	end
	eq(#(bands[1].hazards or {}), 0, "the first band (nights 1-2) has no hazards: a new player learns the manor first")
	-- the windows change with the nights: a starry first night, starless storms, the eclipse at the end
	truthy(bands[1].outside.stars >= 0.8, "the Quiet Night's windows are full of stars")
	local storm = bands[EnvBands.indexOf(bands, "storm") or 1]
	eq(storm.outside.stars, 0, "the Thunderstorm has no stars (cloud cover)")
	eq(bands[#bands].outside.eclipse, 1, "the last band's moon is eclipsed")
	for i = 1, #bands - 1 do
		eq(bands[i].outside.eclipse, 0, bands[i].id .. ": no eclipse before the last band")
	end
	truthy(EnvBands.indexOf(bands, Env.FlagshipBandId) ~= nil, "the flagship band id names a real band")
	for i = 2, #bands do
		truthy(bands[i].from > bands[i - 1].from, "bands are in night order")
	end
end

-- every band defines the same fields in every lighting group, or a blend would keep a stale value
do
	for _, g in { "lighting", "atmosphere", "bloom", "colorCorrection" } do
		local keys = {}
		for k in bands[1][g] do keys[k] = true end
		local same = true
		local why = ""
		for _, b in bands do
			for k in keys do
				if b[g][k] == nil then same, why = false, b.id .. " lacks " .. g .. "." .. k end
			end
			for k in b[g] do
				if not keys[k] then same, why = false, b.id .. " adds " .. g .. "." .. k end
			end
		end
		truthy(same, "every band defines the same " .. g .. " fields (" .. why .. ")")
	end
end

--================================================================ fair to the chase

do
	local ok, err = Nightfall.fairness(Config)
	truthy(ok, "the shipped bands are fair to the chase: " .. tostring(err))
	-- the rule has teeth on the shipped data, not just on the spec's own table
	local hostile = table.clone(Config)
	local env = table.clone(Env)
	local b5 = table.clone(bands[5])
	b5.colorCorrection = table.clone(b5.colorCorrection)
	b5.colorCorrection.TintColor = { 255, 170, 170 }
	env.Bands = table.clone(bands)
	env.Bands[5] = b5
	hostile.Env = env
	eq((Nightfall.fairness(hostile)), false, "CONTROL: the shipped config with the Blood Moon tinting the screen red is rejected")
	local sig = Env.WatcherSignature
	eq(#sig, 2, "the watcher's signature is its two lights (the headless check pins them to the built model)")
	-- review 4: the way out is protected the same way (the headless check pins it to the built ExitLamp and lights)
	eq(type(Env.ExitSignature) == "table" and #Env.ExitSignature or 0, 1, "the exit's signature is its one green light colour")
	-- the ghosts' colours live in Config, so the static rule above sees them (they were hard-coded, 35 from the exit)
	for _, key in { "ghost", "ghostHalo" } do
		local c = Env.Glow[key]
		truthy(type(c) == "table" and #c == 3, "Env.Glow." .. key .. " is an {r, g, b} the fairness rule checks")
		if type(c) == "table" and #c == 3 then
			for _, s in Env.ExitSignature or {} do
				truthy(Nightfall.colorDistance(c, s) >= Nightfall.HARD.SignatureDistanceMin, string.format(
					"%s (%d,%d,%d) is %.0f from the exit's green: a ghost never reads as the way out", key, c[1], c[2], c[3], Nightfall.colorDistance(c, s)))
			end
		end
	end
end

--================================================================ hazards

do
	local ok, err = Hazards.validate(Hz)
	truthy(ok, "Config.Hazards validates (" .. tostring(err) .. ")")
	local ok2, err2 = Nightfall.validateHazards(Config)
	truthy(ok2, "and obeys the chase rules (" .. tostring(err2) .. ")")
	for _, b in bands do
		for _, k in b.hazards or {} do
			truthy(Hz.Kinds[k] ~= nil, b.id .. " names hazard kind " .. tostring(k) .. ", which exists")
		end
	end
	for name, k in Hz.Kinds do
		local dist = k.speed * k.telegraph
		truthy(dist >= 30 and dist <= 100, string.format(
			"%s starts %.0f studs out: far enough to see coming, near enough to read (30-100)", name, dist))
		local r = k.hitRadius + Hz.PlayerRadius
		truthy(r <= 4.5, string.format("%s: the ring is %.1f studs across; stepping out of it is a step, not a run (radius <= 4.5)", name, 2 * r))
		local walkOut = (r + 0.1) / Config.Player.WalkSpeed
		truthy(walkOut < k.commit, string.format("%s: walking out of the ring (%.2f s) takes less than the locked warning (%.1f s)",
			name, walkOut, k.commit))
		truthy(k.knock < Config.Player.WalkSpeed, name .. ": a knock is slower than walking")
	end
	truthy(Hz.QuietAfterSpottedSeconds > Config.Watcher.HuntSeconds, "the quiet window outlasts the Nightwatcher's hunt")
end

-- every lane starts on screen, from a camera behind the player at the pitches a manor camera actually uses
do
	local function lcg(seed)
		local st = seed % 4294967296
		return function()
			st = (1664525 * st + 1013904223) % 4294967296
			return st / 4294967296
		end
	end
	local function onScreen(camPos, look, p, aspect, margin)
		local fx, fy, fz = look.x, look.y, look.z
		local rx, rz = fz, -fx
		local rl = math.sqrt(rx * rx + rz * rz)
		rx, rz = rx / rl, rz / rl
		local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
		local dx, dy, dz = p.x - camPos.x, p.y - camPos.y, p.z - camPos.z
		local depth = dx * fx + dy * fy + dz * fz
		if depth <= 0 then return false end
		local tv = math.tan(math.rad(35 - margin))
		local th = math.tan(math.rad(math.deg(math.atan(math.tan(math.rad(35)) * aspect)) - margin))
		return math.abs((dx * rx + dz * rz) / depth) <= th and math.abs((dx * ux + dy * uy + dz * uz) / depth) <= tv
	end
	local r = lcg(9090)
	local total, bad, example = 0, 0, nil
	local offAtSteep, steepTotal = 0, 0
	for _, b in ipairs(bands) do
		if #(b.hazards or {}) > 0 then
			for _, camPitch in { -60, -40, -30, -20, -10, 0, 10, 20 } do
				for _, aspect in { 16 / 9, 4 / 3 } do
					for _ = 1, 40 do
						local yaw = r() * math.pi * 2
						local cp = math.rad(camPitch)
						local look = { x = math.sin(yaw) * math.cos(cp), y = math.sin(cp), z = math.cos(yaw) * math.cos(cp) }
						local head = { x = 0, y = 104.5, z = 0 }
						local aim = { x = 0, y = 103, z = 0 }
						local camPos = { x = head.x - look.x * 12.5, y = head.y - look.y * 12.5, z = head.z - look.z * 12.5 }
						local s = Hazards.newScheduler(Hz, r)
						s.clock = s.nextAt
						local ctx = { resting = false, paused = false, grounded = true, kinds = b.hazards, aim = aim, yaw = yaw, pitch = cp }
						local ev = Hazards.step(s, Hz, 0.05, ctx, r)
						local plan = ev and ev.plan
						local ok = plan ~= nil
						while ok and plan.t < plan.commitAt do
							if not onScreen(camPos, look, Hazards.positionAt(plan, plan.t), aspect, 4) then ok = false end
							Hazards.step(s, Hz, 0.05, ctx, r)
						end
						if camPitch < -30 then
							steepTotal += 1
							if not ok then offAtSteep += 1 end
						else
							total += 1
							if not ok then
								bad += 1
								example = string.format("%s:%s at pitch %d", b.id, plan and plan.kind or "?", camPitch)
							end
						end
					end
				end
			end
		end
	end
	print(string.format("  on screen: %d of %d launches at camera pitch -30..20 stayed on screen until the lane locked; "
		.. "looking steeply down (-40, -60) %d of %d did not (the lane is held in the room's height band; the ring and banner still show)",
		total - bad, total, offAtSteep, steepTotal))
	eq(bad, 0, "every hazard starts on screen and stays there until it locks, for camera pitch -30..20 degrees"
		.. (if example then " (e.g. " .. example .. ")" else ""))
end

--================================================================ rest

do
	local ok, err = Rest.validate(Config.Rest)
	truthy(ok, "Config.Rest passes the template's rules (" .. tostring(err) .. ")")
	local ok2, err2 = Nightfall.validateRest(Config.Rest)
	truthy(ok2, "and rest is between rounds only (" .. tostring(err2) .. ")")
	eq(Nightfall.restAllowed(Config.Rest, "NIGHT"), false, "no rest inside the manor")
	eq(Nightfall.restAllowed(Config.Rest, "DAY"), true, "rest in the safehouse")
end

--================================================================ the safehouse, budgets

do
	local tiers = Env.Cosy
	eq(tiers[1].minLevel, 0, "the first cosiness tier starts at hub level 0")
	local maxHub = 0
	for _, e in Config.Upgrades.Catalog do maxHub += e.max end
	for i = 2, #tiers do
		truthy(tiers[i].minLevel > tiers[i - 1].minLevel, "cosiness tiers climb")
	end
	truthy(tiers[#tiers].minLevel <= maxHub, string.format("the last tier is reachable (%d <= %d)", tiers[#tiers].minLevel, maxHub))

	local B = Config.Budget
	for _, k in { "MaxParts", "MaxEmitters", "MaxWeatherEmitters", "MaxEmitterRate", "MaxLights", "MaxHazards", "MaxWindowsShown", "MaxPortraitsShown" } do
		truthy(type(B[k]) == "number" and B[k] > 0, "Budget." .. k .. " is set")
	end
	truthy(B.MaxWeatherEmitters <= B.MaxEmitters, "the weather's emitters fit inside the emitter budget")
	eq(B.MaxHazards, 1, "one hazard at a time")
	local peakRain = 0
	for _, b in bands do peakRain = math.max(peakRain, b.outside.rain + b.inside.dust) end
	truthy(peakRain <= B.MaxEmitterRate, string.format("the heaviest band's rain + dust (%d/s) fits the emitter-rate budget (%d/s)", peakRain, B.MaxEmitterRate))
	local win = Env.Window
	truthy(win.CentreY - win.Height / 2 >= 3, "windows start above the waist: a window never reads as a doorway")
	truthy(win.CentreY + win.Height / 2 <= Config.Manor.WallHeight - 1, "and end below the ceiling")
	truthy(math.abs(win.Along) + win.Width / 2 <= Config.Manor.RoomSize / 2 - 2, "and sit on their wall, clear of the corners")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("EnvConfig spec failed", 0)
end
