-- world.check.luau — Fork Tower in a BUILT WORLD, for everything REVIEW-2 left open.
--
-- Run:
--   cd D:/Claude/Roblox/robloxemu && py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--   cd D:/Claude/Roblox/fork-tower && luau tests/world.check.luau
--
-- WHY THIS FILE EXISTS AND IS NOT PART OF robloxemu/check_forktower.luau.
-- check_forktower.luau is the older harness run and it lives in robloxemu/, which this pass may
-- only READ. Two of REVIEW-2's open findings are defects in ITS assertions (M5 below), and the
-- new mechanics need world-level coverage of their own, so both live here, inside the game's own
-- repo, where the game owns them. check_forktower.luau still passes unchanged (85/0) and is still
-- the reader/naive/liar end-to-end run; this file is the rest.
--
-- What it covers, one section each:
--   A  an unread fork shows NOTHING — no trait, no stars, no theme colour, nothing on the wire
--   B  reading costs Config.Fork.ReadSeconds of real clock, measured, and cannot be rushed
--   C  a read is per floor and it SURVIVES a rejoin (you do not pay for the same fork twice)
--   D  a skip spent on a floor stays spent — REVIEW-2's pre-existing refund bug
--   E  MaxLanes is a FLOOR: MaxPlayers above it RAISES the pool (REVIEW-2's surviving M5)
--   F  a lane that frees up is handed to a player who was waiting for one
--   G  the hazard debounce is per HAZARD, not per lane
--   H  every checkpoint sits in the middle of its clear band, measured in the built world

local Harness = require("../../robloxemu/emu/harness")
local Config = require("../src/shared/Config")

--============================================================================ setup

-- SET BEFORE THE SERVER RUNS. `laneCount` is computed once, at load, from
-- max(Config.World.MaxLanes, Players.MaxPlayers) — so the only way to measure the FLOOR claim is
-- to boot a server whose slider is set above the config. 40 > 24; the emulator's own default is
-- 12, which is BELOW MaxLanes and therefore cannot tell max from min.
local MAX_PLAYERS = 40
local MAX_LANES = Config.World.MaxLanes -- 24
local READ_SECONDS = Config.Fork.ReadSeconds
local FLOORS = Config.Tower.Floors

local h = Harness.new({
	bundle = require("../../robloxemu/build/fork-tower"),
	name = "fork-tower-world",
	viewport = { 1280, 720 },
	touch = false,
})
h.Players.MaxPlayers = MAX_PLAYERS

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local store = h.services.DataStoreService:GetDataStore("ForkTower_v1")
local function seedProfile(uid, opts)
	opts = opts or {}
	store:SetAsync("u_" .. uid, {
		data = {
			runSeed = opts.runSeed or 4, level = opts.level or 1, stage = "fork",
			picks = {}, slots = {}, readFloors = {}, skipped = {},
			skips = opts.skips or 0, rebirths = 0, bestScore = 0, bestTitle = "",
			redeemed = {}, passes = {},
		},
	})
end

assert(h:tryRun("server/Main.server"))
h:advance(1)

local towers = h.workspace:FindFirstChild("Towers")
local remotes = h.ReplicatedStorage:FindFirstChild("ForkRemotes")
local StateEvent = remotes:FindFirstChild("State")
local NoticeEvent = remotes:FindFirstChild("Notice")

local function laneOf(plr)
	if towers == nil then return nil end
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end
local function forkOf(lane, level) return lane:FindFirstChild("Fork_" .. level) end
local function padOf(lane, level)
	local f = forkOf(lane, level)
	return f and f:FindFirstChild("ForkPad_" .. level)
end
local function doorOf(lane, level, slot)
	local f = forkOf(lane, level)
	return f and f:FindFirstChild("Door_" .. level .. "_" .. slot)
end
local function sectionOf(lane, level) return lane:FindFirstChild("Section_" .. level) end
local function platformsIn(section)
	local n = 0
	for _, c in section:GetChildren() do
		if string.match(tostring(c.Name), "^Plat_") then n += 1 end
	end
	return n
end

-- What the billboard on a part actually says.
local function labelOf(part, bbName)
	local bb = part and part:FindFirstChild(bbName)
	local t = bb and bb:FindFirstChild("Text")
	return t and tostring(t.Text) or nil
end

-- The last State payload the server pushed at this player.
local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	return sent[#sent] and sent[#sent].args[1] or nil
end
local function noticesOf(plr, kind)
	local n = 0
	for _, msg in NoticeEvent:sentTo(plr) do
		local a = msg.args and msg.args[1]
		if type(a) == "table" and (kind == nil or a.kind == kind) then n += 1 end
	end
	return n
end

-- Which door is the trap, read off the pad's own carving and the doors' own signs — the way a
-- player reads one AFTER paying. These attributes replicate, which is exactly why dressFork is
-- now the only thing that writes them: on an unread fork they do not exist at all, and this
-- function returns nil. Call readFork first. robloxemu/check_forktower.luau enumerates the whole
-- subtree and proves the point; here it is just a precondition.
local function trapSideOf(lane, level)
	local pad = padOf(lane, level)
	local d1, d2 = doorOf(lane, level, 1), doorOf(lane, level, 2)
	if pad == nil or d1 == nil or d2 == nil then return nil end
	local m1 = d1:GetAttribute("Marked") == true
	local m2 = d2:GetAttribute("Marked") == true
	if m1 == m2 then return nil end
	local marked = if m1 then 1 else 2
	return if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
end

local function readPromptOf(lane, level)
	local pad = padOf(lane, level)
	return pad and pad:FindFirstChildOfClass("ProximityPrompt")
end

-- The whole read, the honest way: begin the hold, wait it out, release.
local function readFork(plr, lane, level)
	local prompt = readPromptOf(lane, level)
	if prompt == nil then return false end
	prompt.PromptButtonHoldBegan:Fire(plr)
	h:advance(READ_SECONDS)
	prompt.Triggered:Fire(plr)
	h:advance(0.1)
	return true
end

local function choose(plr, lane, level, slot)
	local door = doorOf(lane, level, slot)
	local prompt = door and door:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then return false end
	prompt.Triggered:Fire(plr)
	h:advance(0.5)
	return true
end
local function climb(plr, lane, level)
	local section = sectionOf(lane, level)
	if section == nil then return false end
	local exit = nil
	for _, c in section:GetChildren() do
		if c:GetAttribute("Exit") == true then exit = c end
	end
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if exit == nil or hrp == nil then return false end
	exit.Touched:Fire(hrp)
	h:advance(0.5)
	return true
end

--============================================================================ A. an unread fork is dark

-- REVIEW-2's headline: "THE CORE LOOP IS DOMINATED — the optimal way to play Fork Tower is to
-- never read an inscription." The star count was printed on every door, on a billboard LARGER than
-- the inscription that was supposed to dominate it, so "take the door with more stars" beat "read
-- and dodge the trap" on 95.1% of 3000 seeds. The fix is that a door says nothing at all.

local A = 9101
seedProfile(A)
local alice = h:join("Alice", A)
h:advance(1)
h.Players:simulateSpawn(alice, h.workspace)
h:advance(1)

local aliceLane = laneOf(alice)
truthy(aliceLane ~= nil, "the joining player got a lane (control: the world was built at all)")
if aliceLane == nil then
	print("no lane; nothing below can run")
	error("fork tower world check failed", 0)
end

do
	local fork = forkOf(aliceLane, 1)
	eq(fork:GetAttribute("Read"), false, "a fresh fork is marked unread")

	for slot = 1, 2 do
		local door = doorOf(aliceLane, 1, slot)
		local text = labelOf(door, "TraitLabel")
		eq(text, Config.Fork.UnreadDoor, "door " .. slot .. " shows only that it is a door")
		falsy(string.find(text or "", "★", 1, true), "...no star count on door " .. slot)
		local prompt = door:FindFirstChildOfClass("ProximityPrompt")
		eq(prompt and prompt.ObjectText, Config.Fork.UnreadDoor,
			"...and the prompt's own ObjectText does not name the trait either")
		-- The theme colour is most of the leak on its own: it narrows twelve traits to two, and
		-- gold/void are the strong pair.
		local c = door.Color
		truthy(c ~= nil and math.abs(c.R * 255 - Config.Fork.UnreadColor[1]) < 1.5
			and math.abs(c.G * 255 - Config.Fork.UnreadColor[2]) < 1.5
			and math.abs(c.B * 255 - Config.Fork.UnreadColor[3]) < 1.5,
			"...and door " .. slot .. " is not painted in its trait's theme colour")
	end

	-- The signs stay visible. They are exchangeable by construction (Fork.luau draws the pair of
	-- sets before anything consults the trap), so they leak nothing on their own — and they are the
	-- vocabulary the inscription is about to use.
	local d1 = doorOf(aliceLane, 1, 1)
	truthy(tostring(d1:GetAttribute("Signs")) ~= "", "the door's signs are still on it")
	local nubs = 0
	for _, c in d1:GetChildren() do
		if c:GetAttribute("Sign") ~= nil then nubs += 1 end
	end
	eq(nubs, Config.Fork.SignsPerDoor, "...and still rendered, one nub per sign")

	-- The pad shows that there IS an inscription, and not what it says.
	local inscription = labelOf(padOf(aliceLane, 1), "Inscription")
	local floorData = nil -- what the pad would say if it were read
	truthy(string.find(inscription or "", Config.Fork.UnreadInscription, 1, true) ~= nil,
		"an unread pad says the inscription is unread")
	falsy(string.find(inscription or "", "MERKER", 1, true), "...and does not carry the rule text")
	local _ = floorData

	-- And nothing goes down the wire either. The HUD's rule panel carries the tell, the liar line
	-- AND both doors' labels; sending it on every state push would hand the player the answer the
	-- pad is supposed to sell them.
	local s = stateOf(alice)
	truthy(s ~= nil, "the server pushed state at all")
	eq(s and s.rule, nil, "the client is sent no rule for a fork it has not read")
	eq(s and s.read, false, "...and is told outright that it is unread")
	eq(s and s.atFork, true, "...and that it is standing at a fork, not on the summit")
end

--============================================================================ B. reading costs time

do
	local prompt = readPromptOf(aliceLane, 1)
	truthy(prompt ~= nil, "the fork pad carries a LES prompt")
	eq(prompt and prompt.HoldDuration, READ_SECONDS,
		"...whose hold is Config.Fork.ReadSeconds, so the client's own bar matches the charge")

	-- THE EXPLOIT PATH FIRST: a client that fires the prompt directly, with no hold at all
	-- (`fireproximityprompt`). It must not read anything early.
	local t0 = h.scheduler:now()
	prompt.Triggered:Fire(alice)
	h:advance(READ_SECONDS * 0.5)
	eq(forkOf(aliceLane, 1):GetAttribute("Read"), false, string.format(
		"%.2f s into a %.2f s read, the fork is still dark", READ_SECONDS * 0.5, READ_SECONDS))
	eq(labelOf(doorOf(aliceLane, 1, 1), "TraitLabel"), Config.Fork.UnreadDoor,
		"...the doors are still blank")
	eq(stateOf(alice).rule, nil, "...and the client still has nothing")

	-- Spamming it must not queue timers or shorten anything.
	local noticesBefore = noticesOf(alice, "read")
	for _ = 1, 50 do
		prompt.Triggered:Fire(alice)
	end
	h:advance(READ_SECONDS * 0.4)
	eq(forkOf(aliceLane, 1):GetAttribute("Read"), false,
		"fifty fires in one frame did not buy a shorter read")
	truthy(noticesOf(alice, "read") - noticesBefore <= 1, string.format(
		"...and cost the client %d messages, not fifty", noticesOf(alice, "read") - noticesBefore))

	h:advance(READ_SECONDS * 0.2)
	local spent = h.scheduler:now() - t0
	eq(forkOf(aliceLane, 1):GetAttribute("Read"), true, string.format(
		"the read completed after %.2f s on the SERVER's clock", spent))
	truthy(spent >= READ_SECONDS - 1e-9, string.format(
		"...and it cost at least the %.2f s it is supposed to (%.2f s)", READ_SECONDS, spent))
end

do
	-- WHAT A READ BUYS. Both halves at once: which door carries which trait, and which one is the
	-- trap. Nothing else in the world says either.
	local trap = trapSideOf(aliceLane, 1)
	truthy(trap ~= nil, "floor 1 is readable (exactly one door bears the named sign)")

	for slot = 1, 2 do
		local text = labelOf(doorOf(aliceLane, 1, slot), "TraitLabel") or ""
		truthy(text ~= Config.Fork.UnreadDoor, "door " .. slot .. " now names its trait")
		truthy(string.find(text, "★", 1, true) ~= nil, "...with its star count")
	end
	local inscription = labelOf(padOf(aliceLane, 1), "Inscription") or ""
	truthy(string.find(inscription, "MERKER", 1, true) ~= nil,
		"the pad now carries the rule the player paid for")

	local s = stateOf(alice)
	truthy(s.rule ~= nil, "the HUD is finally sent the rule")
	eq(s.read, true, "...and told the floor is read")
	truthy(s.rule and s.rule.doors[1].label ~= "" and s.rule.doors[2].label ~= "",
		"...with both doors' traits on it")
	truthy(noticesOf(alice, "read") > 0, "the player was told what the inscription said")

	-- The prompt is spent: a floor is read once.
	eq(readPromptOf(aliceLane, 1).Enabled, false, "a read fork's LES prompt is switched off")
end

--============================================================================ C. a read survives a rejoin

do
	h:leave(alice)
	h:advance(1)
	local back = h:join("AliceAgain", A)
	h:advance(1)
	h.Players:simulateSpawn(back, h.workspace)
	h:advance(1)
	local lane = laneOf(back)
	truthy(lane ~= nil, "the rejoining player got a lane")
	eq(forkOf(lane, 1):GetAttribute("Read"), true,
		"a floor already paid for comes back READ — you do not buy the same fork twice")
	truthy(labelOf(doorOf(lane, 1, 1), "TraitLabel") ~= Config.Fork.UnreadDoor,
		"...and its doors are dressed again without a second read")
	eq(stateOf(back).read, true, "...and the HUD is handed the rule straight away")
	h:leave(back)
	h:advance(1)
end

--============================================================================ D. a spent skip stays spent

-- REVIEW-2, pre-existing and missed by both earlier passes: onDoorChosen decremented p.skips and
-- built a normal section, but nothing recorded THAT THE SKIP WAS SPENT ON THAT FLOOR. buildLane
-- then recomputed `Fork.isTrap` on rejoin and rebuilt the penalty section — the player lost the
-- skip AND got the trap. Because Section.build mixes PENALTY_MIX into its seed, the section was a
-- different walk entirely, so the world moved under a player mid-climb.

do
	local S = 9202
	seedProfile(S, { skips = 3 })
	local sam = h:join("Sam", S)
	h:advance(1)
	h.Players:simulateSpawn(sam, h.workspace)
	h:advance(1)
	local lane = laneOf(sam)
	eq(trapSideOf(lane, 1), nil, "an UNREAD fork does not say which door is the trap, even to a script")

	local arm = remotes:FindFirstChild("ArmSkip")
	arm:simulateFireServer(sam, true)
	h:advance(0.5)
	readFork(sam, lane, 1)
	local trap = trapSideOf(lane, 1)
	truthy(trap ~= nil, "...and says so once the read is paid for")
	choose(sam, lane, 1, trap) -- straight into the trap, with a skip armed

	local sec = sectionOf(lane, 1)
	truthy(sec ~= nil, "the trapped door built a section")
	eq(sec:GetAttribute("Penalty"), false, "the armed skip turned the trap into a normal section")
	local platsBefore = platformsIn(sec)
	local plansBefore = {}
	for _, c in sec:GetChildren() do
		if string.match(tostring(c.Name), "^Plat_") then
			plansBefore[tostring(c.Name)] = string.format("%.2f,%.2f,%.2f",
				c.Position.X, c.Position.Y, c.Position.Z)
		end
	end

	h:leave(sam)
	h:advance(1)
	local samBack = h:join("SamAgain", S)
	h:advance(1)
	h.Players:simulateSpawn(samBack, h.workspace)
	h:advance(1)
	local lane2 = laneOf(samBack)
	local sec2 = sectionOf(lane2, 1)
	truthy(sec2 ~= nil, "the rejoin rebuilt floor 1's section")
	eq(sec2 and sec2:GetAttribute("Penalty"), false,
		"a skip spent on a floor is STILL spent after a rejoin — the trap does not come back")
	eq(sec2 and platformsIn(sec2), platsBefore, string.format(
		"...and the section is the same length it was (%d platforms)", platsBefore))
	local moved = 0
	if sec2 then
		for _, c in sec2:GetChildren() do
			local was = plansBefore[tostring(c.Name)]
			if was ~= nil and was ~= string.format("%.2f,%.2f,%.2f", c.Position.X, c.Position.Y, c.Position.Z) then
				moved += 1
			end
		end
	end
	eq(moved, 0, "...and platform for platform it is the same walk, not a reseeded one")

	local s = stateOf(samBack)
	eq(s and s.skips, 2, "the skip really was spent (3 armed, 2 left) and did not come back either")
	h:leave(samBack)
	h:advance(1)
end

--============================================================================ G. one debounce per hazard

-- Ordered before the crowd, because the crowd fills the server.
--
-- REVIEW-2, broken BY the earlier fix: a single `lane.hazardReadyAt` meant ONE hit made every
-- hazard in the whole tower inert for a full second. At WalkSpeed 16-22 that second covers 16-22
-- studs, and adjacent platforms are 11.0-15.5 studs apart, so a player who ate one hazard walked
-- through the next one or two for free — and "more hazards" is half of what a penalty section IS.

do
	local G = 9303
	seedProfile(G)
	local gil = h:join("Gil", G)
	h:advance(1)
	h.Players:simulateSpawn(gil, h.workspace)
	h:advance(1)
	local lane = laneOf(gil)

	-- Take every trap, so the sections are the busy ones.
	for level = 1, FLOORS do
		readFork(gil, lane, level)
		local trap = trapSideOf(lane, level)
		if trap == nil then break end
		choose(gil, lane, level, trap)
		climb(gil, lane, level)
	end
	truthy(lane:FindFirstChild("Summit") ~= nil, "the trap-taker summited (the setup is not vacuous)")

	-- A section with two hazards on it, which is what the per-lane debounce could hide.
	local pair, atLevel = nil, nil
	for level = FLOORS, 2, -1 do
		local sec = sectionOf(lane, level)
		if sec then
			local hz = {}
			for _, c in sec:GetChildren() do
				if c:GetAttribute("Hazard") ~= nil then hz[#hz + 1] = c end
			end
			if #hz >= 2 and pair == nil then
				pair, atLevel = hz, level
			end
		end
	end
	truthy(pair ~= nil, "the tower contains a section carrying at least two hazards")

	local hrp = gil.Character and gil.Character:FindFirstChild("HumanoidRootPart")
	if pair and hrp then
		h:advance(Config.Limits.HazardCooldown + 0.1)
		local before = noticesOf(gil, "hazard")
		pair[1].Touched:Fire(hrp)
		h:advance(0.05) -- well inside the cooldown
		pair[2].Touched:Fire(hrp)
		h:advance(0.05)
		local bites = noticesOf(gil, "hazard") - before
		eq(bites, 2, string.format(
			"two DIFFERENT hazards on floor %d both bite inside one cooldown window (%d did)",
			atLevel, bites))

		-- ...and the same hazard twice still does not.
		local before2 = noticesOf(gil, "hazard")
		for _ = 1, 40 do
			pair[1].Touched:Fire(hrp)
		end
		h:advance(0.05)
		local repeats = noticesOf(gil, "hazard") - before2
		eq(repeats, 0, string.format(
			"...while forty more fires from the SAME hazard cost %d, because its own debounce is live",
			repeats))
	end

	--======================================================================== H. the clear band, in the world

	-- REVIEW-2, broken BY the earlier fix: the respawn point was at the far END of the clear band —
	-- 2.00 studs from the hazard and 0.00 studs from the drop, sitting exactly on Section.check's
	-- own boundary, with the player dropped onto it from RespawnLift studs up. Measured here on the
	-- real Parts rather than on the module's numbers.
	local ch = Config.World.CharacterHalfWidth
	local measured, worstClear, worstEdge = 0, math.huge, math.huge
	for level = 2, FLOORS do
		local sec = sectionOf(lane, level)
		if sec and hrp then
			for _, hz in sec:GetChildren() do
				local idx = hz:GetAttribute("Platform")
				local plat = idx and sec:FindFirstChild("Plat_" .. level .. "_" .. idx)
				if plat then
					h:advance(Config.Limits.HazardCooldown + 0.05)
					plat.Touched:Fire(hrp) -- land on it: that is the checkpoint it hands back
					h:advance(0.05)
					hz.Touched:Fire(hrp)
					h:advance(0.05)
					measured += 1
					local clear = math.max(
						math.abs(hrp.Position.X - hz.Position.X) - (hz.Size.X / 2 + ch),
						math.abs(hrp.Position.Z - hz.Position.Z) - (hz.Size.Z / 2 + ch))
					local edge = math.min(
						plat.Size.X / 2 - (math.abs(hrp.Position.X - plat.Position.X) + ch),
						plat.Size.Z / 2 - (math.abs(hrp.Position.Z - plat.Position.Z) + ch))
					worstClear = math.min(worstClear, clear)
					worstEdge = math.min(worstEdge, edge)
				end
			end
		end
	end
	truthy(measured > 0, "there were hazards to walk into (the measurement is not vacuous)")
	truthy(worstClear >= 1 - 1e-6, string.format(
		"every checkpoint keeps the character clear of its hazard (worst %.2f studs of %d)",
		worstClear, measured))
	truthy(worstEdge >= 1 - 1e-6, string.format(
		"...and off the platform's edge by as much again (worst %.2f studs)", worstEdge))
	print(string.format("  built world: %d hazards, worst clearance %.2f, worst edge margin %.2f",
		measured, worstClear, worstEdge))

	h:leave(gil)
	h:advance(1)
end

--============================================================================ E. MaxLanes is a FLOOR

-- REVIEW-2's SURVIVING MUTATION M5. The claim the first pass made was that
-- `math.max(Config.World.MaxLanes, Players.MaxPlayers)` means a Studio slider can no longer put
-- more players in a server than there are towers. Flipping that max to min left every suite and
-- the headless check green, because the only assertion anywhere was `seated > 0` — the seated
-- COUNT was never compared to the pool. It printed "12 players seated, 21 unseated" instead of
-- "24 seated, 9 unseated" and passed.
--
-- The expected pool is computed HERE, from the two inputs, and never read back out of the server.

local POOL = math.max(MAX_LANES, MAX_PLAYERS)

do
	-- Three more than the pool, so there are players left over for section F to seat. Under M5
	-- (max flipped to min) the pool would be MaxLanes = 24 and nineteen of these would be stranded.
	local crowd = {}
	for i = 1, POOL + 3 do
		crowd[i] = h:join("Crowd" .. i, 42000 + i)
		h:advance(0.1)
	end
	h:advance(1)

	local seated, unseated = 0, 0
	for _, plr in h.Players:GetPlayers() do
		if laneOf(plr) ~= nil then seated += 1 else unseated += 1 end
	end
	local present = seated + unseated
	print(string.format("  crowd: %d players present, %d seated, %d unseated (pool should be %d)",
		present, seated, unseated, POOL))
	eq(seated, math.min(present, POOL), string.format(
		"the lane pool is max(MaxLanes %d, MaxPlayers %d) = %d, so %d of %d players are seated",
		MAX_LANES, MAX_PLAYERS, POOL, math.min(present, POOL), present))
	truthy(POOL >= MAX_PLAYERS,
		"...which is the whole claim: the pool is never smaller than the place's max-player count")
	truthy(MAX_PLAYERS > MAX_LANES,
		"...and this run really exercises the FLOOR (MaxPlayers is above MaxLanes, or min would pass)")

	local seen, dupes = {}, {}
	for _, f in towers:GetChildren() do
		local n = tostring(f.Name)
		if seen[n] then dupes[#dupes + 1] = n end
		seen[n] = true
	end
	eq(#dupes, 0, "no two towers share a lane index (" .. table.concat(dupes, ",") .. ")")

	--======================================================================== F. a freed lane finds a waiter

	-- REVIEW-2, broken BY the earlier fix: claimLane was only ever called from buildLane, and
	-- buildLane only from PlayerAdded and Rebirth, so nothing re-ran it when teardownLane freed an
	-- index. A player the server could not seat waited forever — under a sign that promised them a
	-- tower — and the only escape was to leave and rejoin the server themselves. Before the
	-- overflow fix they got a (broken, overlapping) tower; after it, a permanent dead state.
	local waiter, occupant = nil, nil
	for _, plr in h.Players:GetPlayers() do
		if waiter == nil and laneOf(plr) == nil then waiter = plr end
		if occupant == nil and laneOf(plr) ~= nil then occupant = plr end
	end
	truthy(waiter ~= nil, "somebody is waiting for a tower (the check is not vacuous)")
	truthy(occupant ~= nil, "...and somebody is standing in one")

	if waiter and occupant then
		truthy(noticesOf(waiter, "full") > 0, "the waiting player was told the server is full")
		h.Players:simulateSpawn(waiter, h.workspace)
		h:advance(1)
		eq(laneOf(waiter), nil, "...and still has no tower while every lane is taken")

		local freed = tostring(laneOf(occupant).Name)
		h:leave(occupant)
		h:advance(1)
		local got = laneOf(waiter)
		truthy(got ~= nil, "a SEATED player leaving hands their freed lane to the player who was waiting")
		eq(got and tostring(got.Name), freed, "...the very lane that was freed")

		local hrp = waiter.Character and waiter.Character:FindFirstChild("HumanoidRootPart")
		truthy(hrp ~= nil and got ~= nil
			and math.abs(hrp.Position.X - got:FindFirstChild("LobbyPad").Position.X) < 40,
			"...and the player was actually moved into it, not left on the waiting pad")
		-- `got ~= nil and` is not decoration: without it this line RAISES when the seating sweep
		-- is missing, and the run ends with a stack trace instead of a count. A check that crashes
		-- where it means to fail reports "CRASH" for every defect alike and tells you nothing about
		-- which one you have.
		truthy(got ~= nil and forkOf(got, 1) ~= nil, "...with floor 1's fork built and waiting")

		local seen2, dupes2 = {}, {}
		for _, f in towers:GetChildren() do
			local n = tostring(f.Name)
			if seen2[n] then dupes2[#dupes2 + 1] = n end
			seen2[n] = true
		end
		eq(#dupes2, 0, "...and still no two towers share an index afterwards")
	end
end

--============================================================================ done

print("")
for _, w in h.warnings do
	print("server warned: " .. w)
end
for _, e in h:errors() do
	failed += 1
	print("SERVER ERROR: " .. tostring(e))
end

print(string.format("fork tower world: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower world check failed", 0)
end
