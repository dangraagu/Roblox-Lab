-- FACILITY: Endless Nightmare — THE PLAYER'S PATH, walked in the built world, from join to a second run.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       cd ../facility-nightmare && luau tests/walk.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green tests are not a working game. This boots the real server script, joins one brand-new player
-- with no save file, and plays through tests/Bot.luau — which knows only what a client could know
-- and moves at the speed the server wrote onto the Humanoid — and prints what happened in numbers:
--
--   LOOP 1  spawn -> walk into the car -> sublevel 1 (first-ever run: the front waits for the first
--           fuse) -> DESCEND -> 2 -> DESCEND -> 3 -> EXTRACT -> back in the break room -> buy a perk
--   LOOP 2  the car again, walking at DESIGN.md §0's "slow" proxy (10.4 studs/s, 0.65 x WalkSpeed)
--           -> down until the dark takes the player or sublevel 8 is cleared, opening EVERY door on
--           sublevel 4 (the first 5x5 floor) so the Part budget is measured on a fully built zone
--           -> back in the break room
--
-- Loop 1 walks at the full 16 studs/s: the design's "perfect" explorer, who is measured to clear
-- sublevel 1 on every floor and barely meets the dark. Loop 2 is the pace the design's 5-10 minute
-- run length was measured for, and it is the loop that shows the dark doing its job.
--
-- Because the seeds are entropy, the assertion COUNT varies run to run: every cleared floor adds
-- its own Part-budget and pay assertions. A failure count above 0 is the only thing that matters.
--
-- Every Essence figure it asserts is recomputed from the rules in DESIGN.md §5.4 by hand here, never
-- read back from shared/Economy.luau: a payout checked against the module that computed it proves
-- nothing. The seeds are engine entropy, so every run walks different floors; the numbers printed
-- are one sample, not a distribution.

local Harness = require("../../robloxemu/emu/harness")
local Bot = require("./Bot")

local h = Harness.new({
	bundle = require("../../robloxemu/build/facility-nightmare"),
	name = "facility-nightmare-walk",
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
local function say(fmt, ...) print(string.format(fmt, ...)) end

local UID = 90210
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
local function stored()
	local rec = store:GetAsync("u_" .. UID)
	return rec and rec.data
end
-- DESIGN.md §5.4, written out: FloorPay(k) = 10 + 5 (k - 1); death keeps floor(keep% x run / 100).
local function floorPay(k) return 10 + 5 * (k - 1) end
local function kept(run, pct) return math.floor(run * pct / 100) end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local hub = h.workspace:FindFirstChild("Hub")

--============================================================================ watching the world

local apparitions = 0
local lastFig = nil
-- REVIEW-1 B4: the figure stood inside a desk, crate or cabinet on 73 of 707 apparitions. Every one
-- this walk meets is checked against the parts of the room it stands in, as the WORKSPACE has them.
local appInside = {}
local function box(part, swapXZ)
	local s, c = part.Size, part.Position
	local sx, sz = if swapXZ then s.Z else s.X, if swapXZ then s.X else s.Z
	return { c.X - sx / 2, c.X + sx / 2, c.Y - s.Y / 2, c.Y + s.Y / 2, c.Z - sz / 2, c.Z + sz / 2 }
end
local function overlaps(a, b)
	local e = 0.01
	return a[1] < b[2] - e and b[1] < a[2] - e and a[3] < b[4] - e and b[3] < a[4] - e and a[5] < b[6] - e and b[5] < a[6] - e
end
local function watch(bot)
	local fl = bot:floor()
	local fig = fl and fl:FindFirstChild("Apparition")
	if fig and fig ~= lastFig then
		apparitions += 1
		lastFig = fig
		local torso = fig:FindFirstChild("Torso")
		local legs = fig:FindFirstChild("LegL").Position - fig:FindFirstChild("LegR").Position
		local swap = math.abs(legs.Z) > math.abs(legs.X) -- the figure's width runs along Z
		for _, room in fl.Rooms:GetChildren() do
			local floorPart = room:FindFirstChild("Floor")
			if floorPart and math.abs(torso.Position.X - floorPart.Position.X) <= 14 and math.abs(torso.Position.Z - floorPart.Position.Z) <= 14 then
				for _, limb in fig:GetChildren() do
					if limb:IsA("BasePart") then
						local lb = box(limb, swap)
						for _, o in room:GetChildren() do
							if o:IsA("BasePart") and o.Name ~= "Floor" and (o.CanCollide ~= false or string.sub(o.Name, 1, 4) == "Prop"
								or o.Name == "Fuse" or o.Name == "Cell") and overlaps(lb, box(o, false)) then
								table.insert(appInside, room.Name .. ":" .. limb.Name .. " in " .. o.Name)
							end
						end
					end
				end
			end
		end
	end
end

local budget = { worstRoom = 0, worstLeaves = 0, worstZone = 0, roomsBuilt = 0, grid = 0 }
local function countBudget(bot, label)
	local zone = bot:zone()
	local fl = zone and zone:FindFirstChild("Floor")
	if not fl then return end
	local worstRoom, rooms = 0, 0
	for _, f in fl.Rooms:GetChildren() do
		rooms += 1
		local n = 0
		for _, d in f:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
		worstRoom = math.max(worstRoom, n)
	end
	local leaves = #fl.Doors:GetChildren()
	local total = 0
	for _, d in zone:GetDescendants() do if d:IsA("BasePart") then total += 1 end end
	budget.worstRoom = math.max(budget.worstRoom, worstRoom)
	budget.worstLeaves = math.max(budget.worstLeaves, leaves)
	if total > budget.worstZone then
		budget.worstZone = total
		budget.roomsBuilt = rooms
	end
	say("      parts: %d rooms built, worst room %d Parts, %d door leaves, %d Parts in the zone (%s)", rooms, worstRoom, leaves, total, label)
	truthy(worstRoom <= 20, label .. ": no room over 20 Parts")
	truthy(leaves <= 40, label .. ": no floor over 40 door leaves")
	truthy(total <= 600, label .. ": zone at most 600 Parts")
end

--============================================================================ join

say("== JOIN")
local plr = h:join("NewPlayer", UID)
h:advance(0.5)
h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local bot = Bot.new(h, plr, { onTick = watch, maxSeconds = 900 })
do
	local r = bot:hrp()
	local sp = hub.HubSpawn
	say("   landed at %.2f, %.2f, %.2f (HubSpawn at %.2f, %.2f, %.2f)", r.Position.X, r.Position.Y, r.Position.Z, sp.Position.X, sp.Position.Y, sp.Position.Z)
	truthy(math.abs(r.Position.X - sp.Position.X) < 0.01 and math.abs(r.Position.Z - sp.Position.Z) < 0.01, "the new player lands on HubSpawn")
	local st = bot:state()
	eq(st and st.phase, "hub", "…in the hub phase")
	eq(st and st.runs, 0, "…with no runs behind them")
end

local function playFloor(loopLabel, opts)
	local st = bot:state()
	local k = st.run.k
	local t0 = bot.stats.seconds
	local d0, l0, doors0 = bot.stats.darkSeconds, bot.stats.lightSeconds, bot.stats.doorsOpened
	local n0 = #bot.notices
	bot.stats.maxExposure = 0
	local apps0 = apparitions
	local batteryBefore = st.run.battery
	local result = bot:clearFloor(opts)
	local run = bot:state().run
	-- counted from the SERVER's notices: a fuse walked over on the way to something else is still a fuse
	local fuses, cells, winds = 0, 0, 0
	for i = n0 + 1, #bot.notices do
		local kind = bot.notices[i].kind
		if kind == "fuse" then fuses += 1 elseif kind == "cell" then cells += 1 elseif kind == "secondWind" then winds += 1 end
	end
	say("   %s sublevel %d: %s after %.1f s | %d doors | %d fuses, %d cells | %.1f s in dark rooms, light on %.1f s | battery %.1f -> %s | peak exposure %.0f%% | apparitions %d",
		loopLabel, k, result, bot.stats.seconds - t0, bot.stats.doorsOpened - doors0, fuses, cells,
		bot.stats.darkSeconds - d0, bot.stats.lightSeconds - l0, batteryBefore,
		run and string.format("%.1f/%d", run.battery, run.batteryCap) or "-", 100 * bot.stats.maxExposure, apparitions - apps0)
	-- counted while the floor still stands: a dead floor is only cleared after the death beat
	countBudget(bot, loopLabel .. " sublevel " .. k .. " (" .. tostring(result) .. ")")
	return result, k
end

--============================================================================ LOOP 1

say("== LOOP 1")
local tJoin = h.scheduler:now()
truthy(bot:board(hub), "walking into the car starts the first run")
say("   spawn -> ride: %.1f s", h.scheduler:now() - tJoin)
truthy(bot:waitPhase("floor", 6), "the ride arrives on sublevel 1")

local runEssence = 0
local result, k = playFloor("loop 1")
eq(result, "powered", "loop 1: sublevel 1 cleared")
runEssence += floorPay(1)
eq(bot:state().run.runEssence, runEssence, "loop 1: sublevel 1 paid " .. floorPay(1))
do
	local tFuse, tFail
	for _, n in bot.notices do
		if n.kind == "fuse" and not tFuse then tFuse = n.at end
		if n.kind == "powerFailing" and not tFail then tFail = n.at end
	end
	truthy(tFuse ~= nil and tFail ~= nil and math.abs(tFail - tFuse) < 0.01, "first-ever run: the power starts failing at the first fuse")
end

for _, target in { 2, 3 } do
	bot:fire("Choose", "descend")
	truthy(bot:waitPhase("ride", 1) and bot:waitPhase("floor", 6), "DESCEND to sublevel " .. target)
	result, k = playFloor("loop 1")
	if result ~= "powered" then break end
	runEssence += floorPay(target)
	eq(bot:state().run.runEssence, runEssence, "loop 1: run essence after sublevel " .. target)
end

local bankedLoop1 = 0
if result == "powered" then
	local before = stored() and stored().essence or 0
	bot:fire("Choose", "extract")
	h:advance(0.2)
	bankedLoop1 = stored().essence - before
	eq(bankedLoop1, runEssence, "EXTRACT banks the whole run: " .. runEssence)
	truthy(bot:waitPhase("hub", 6), "the ride goes back up")
	say("   EXTRACT: banked %d Essence (10 + 15 + 20)", bankedLoop1)
else
	truthy(false, "loop 1 was meant to clear three sublevels; the bot " .. tostring(result) .. " on sublevel " .. tostring(k))
end

-- the perk
do
	local st = bot:state()
	say("   break room: %d Essence, deepest %d, runs %d", st.essence, st.bestSublevel, st.runs)
	eq(st.bestSublevel, 3, "leaderstats/profile deepest = 3")
	eq(plr.leaderstats.Deepest.Value, 3, "leaderstats.Deepest = 3")
	local prompt = hub.PerkTerminal:FindFirstChildOfClass("ProximityPrompt")
	local term = hub.PerkTerminal.Position
	bot:walkTo(Vector3.new(term.X, 3, term.Z - 4))
	prompt.Triggered:Fire(plr)
	bot:waitSeconds(0.3)
	local opened = false
	for _, n in bot.notices do if n.kind == "perks" then opened = true end end
	truthy(opened, "the terminal opens the perk panel")
	bot:fire("BuyPerk", "deepCell")
	bot:waitSeconds(0.5)
	local after = bot:state()
	eq(after.essence, st.essence - 25, "Deep Cell rank 1 costs 25")
	eq(stored().perks.deepCell, 1, "…and is on disk")
	say("   bought Deep Cell rank 1: %d -> %d Essence", st.essence, after.essence)
end

--============================================================================ LOOP 2

say("== LOOP 2 (the design's 'slow' proxy: 10.4 studs/s)")
truthy(bot:board(hub), "the second run starts")
truthy(bot:waitPhase("floor", 6), "…on sublevel 1")
eq(bot:state().run.batteryCap, 55, "the perk is in the run: battery 55 s")
bot.speedScale = 0.65
local loop2Essence, lastCleared, death, diedOn = 0, 0, nil, nil
for target = 1, 8 do
	if target > 1 then
		bot:fire("Choose", "descend")
		if not (bot:waitPhase("ride", 1) and bot:waitPhase("floor", 6)) then break end
	end
	local n0 = #bot.notices
	local r = playFloor("loop 2", { exploreAll = target == 4 })
	-- Pay is counted from the SERVER's choice notice, not from how clearFloor returned: the elevator
	-- can power while the player only passes through its room, and the player can then die in the
	-- dark on the way back to it. That run carries the pay (a sweep control exposed the walk
	-- counting it as unpaid).
	local powered = false
	for i = n0 + 1, #bot.notices do
		if bot.notices[i].kind == "choice" and bot.notices[i].data.k == target then powered = true end
	end
	if powered then
		loop2Essence += floorPay(target)
		lastCleared = target
	end
	if r == "powered" then
		eq(bot:state().run.runEssence, loop2Essence, "loop 2: run essence after sublevel " .. target)
	else
		diedOn = target
		for _, n in bot.notices do if n.kind == "death" then death = n.data end end
		break
	end
end

local tail
if death then
	h:advance(0.3)
	say("   THE DARK TOOK YOU on sublevel %d: kept %d of %d", diedOn, death.kept, death.of)
	eq(death.of, loop2Essence, "the death card counts the run")
	eq(death.kept, kept(loop2Essence, 25), "death keeps floor(25% of the run)")
	eq(stored().essence, 20 + kept(loop2Essence, 25), "…and that is exactly what reached the store (20 after the perk + the share)")
	truthy(bot:waitPhase("hub", 4), "after the beat, back in the break room")
	tail = string.format("died on sublevel %d, kept %d of %d", diedOn, death.kept, death.of)
else
	local before = stored().essence
	bot:fire("Choose", "extract")
	h:advance(0.2)
	eq(stored().essence - before, loop2Essence, "loop 2 EXTRACT banks the run")
	truthy(bot:waitPhase("hub", 6), "back in the break room")
	tail = string.format("extracted after sublevel %d with %d", lastCleared, loop2Essence)
end

--============================================================================ summary

say("== SUMMARY")
local final = stored()
say("   loop 1: cleared 3, banked %d | loop 2: %s", bankedLoop1, tail)
say("   profile: essence %d, earned %d, runs %d, extractions %d, deepest %d, deepCell %d",
	final.essence, final.essenceEarned, final.runs, final.extractions, final.bestSublevel, final.perks.deepCell)
say("   Part budget, worst seen: room %d/20, door leaves %d/40, zone %d/600 (%d rooms built)",
	budget.worstRoom, budget.worstLeaves, budget.worstZone, budget.roomsBuilt)
say("   apparitions seen: %d | virtual time played: %.1f s", apparitions, bot.stats.seconds)
eq(#appInside, 0, string.format("no apparition limb stands inside a wall, prop or item (%d apparitions: %s)", apparitions, table.concat(appInside, "; ")))
eq(final.runs, 2, "two runs settled")
eq(final.openRun, nil, "no run left open")
eq(#h:errors(), 0, "no scheduler errors (" .. table.concat(h:errors(), " | ") .. ")")
eq(#h.warnings, 0, "no warnings (" .. table.concat(h.warnings, " | ") .. ")")
print(string.format("walk: %d passed, %d failed", passed, failed))
