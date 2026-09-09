-- Fork Tower — the doors have to be IN THE WORLD, and reading the inscription has to WORK.
-- Run: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--      luau check_forktower.luau
--
-- Fork.spec proves the pure claim over forty thousand forks: a player who reads the inscription
-- never eats a trap. That proof is about a table of numbers. This file is about a built world,
-- and it exists because the gap between the two is where this repo keeps losing games.
--
-- Grow a Crystal shipped `makeSocket` that built the socket Part, sized it, positioned it, glowed
-- it, named it, gave it its attributes, parented a ClickDetector TO it — and never assigned
-- `part.Parent`. The whole core loop of a published game was unreachable and all 166 unit tests
-- stayed green, because none of them could see the workspace. An unparented Instance is the
-- quietest bug in Roblox: nothing raises, nothing warns, the function returns a perfectly good
-- Part. The only thing that catches it is asking the workspace. So this file asks the workspace,
-- and then plays the game.
--
-- What it plays, specifically:
--   * a READER walks all ten floors following the inscription, and must finish with zero penalty
--     sections built — the end-to-end form of the fairness promise;
--   * a NAIVE climber follows the sign but ignores the "the warden lies" line, and must be
--     punished on exactly the inverted floors and nowhere else;
--   * their sections are compared platform for platform, so "the trap is longer, never steeper"
--     is measured in the world rather than trusted from the module.
--
-- Run seed 4 is chosen on purpose: its inscription lies on floors 4, 6 and 8, which is what makes
-- the reader/naive split observable at all. A seed with no inverted floors would let a broken
-- liar mechanic pass this file completely.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/fork-tower"),
	name = "fork-tower",
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

-- From fork-tower/src/shared/Config.luau. Spelled out rather than required, so that a config
-- change that moves the tower has to be looked at here too.
local FLOORS = 10 -- Config.Tower.Floors
local PENALTY_EXTRA = 4 -- Config.Tower.PenaltyExtraPlatforms
local RUN_SEED = 4 -- inscriptions lie on floors 4, 6 and 8
local LIAR_FLOORS = { [4] = true, [6] = true, [8] = true }

local READER, NAIVE, LATE = 5150, 6161, 7171
local HAZARD_COOLDOWN = 1 -- Config.Limits.HazardCooldown
local Config_SaveMinInterval = 6 -- Config.Limits.SaveMinInterval

--============================================================================ seeded profiles

-- The server reads its profile out of `.data` under "u_<uid>". Written the way loadProfile
-- actually reads it — a mismatch here would silently fall back to defaultProfile() and every
-- assertion below would really be testing run seed 1.
local store = h.services.DataStoreService:GetDataStore("ForkTower_v1")
local function seedProfile(uid)
	store:SetAsync("u_" .. uid, {
		data = {
			runSeed = RUN_SEED, level = 1, stage = "fork",
			picks = {}, slots = {},
			skips = 0, rebirths = 0, bestScore = 0, bestTitle = "",
			redeemed = {}, passes = {},
		},
	})
end
seedProfile(READER)
seedProfile(NAIVE)

assert(h:tryRun("server/Main.server"))
h:advance(1)

--============================================================================ world helpers

local towers = h.workspace:FindFirstChild("Towers")

local function laneOf(plr)
	if towers == nil then return nil end
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end

local function partsIn(node)
	local n = 0
	local function walk(x)
		for _, c in x:GetChildren() do
			if c:IsA("BasePart") then n += 1 end
			walk(c)
		end
	end
	walk(node)
	return n
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

local function exitOf(section)
	for _, c in section:GetChildren() do
		if c:GetAttribute("Exit") == true then return c end
	end
	return nil
end

-- Read a fork exactly the way a player standing on the pad reads it: which door carries the
-- sign the inscription names, and whether the inscription says that marks the trap or the safe
-- door. Nothing hidden is consulted — no attribute here is anything but what is carved in front
-- of the player, which is the whole point.
local function readFork(lane, level)
	local pad = padOf(lane, level)
	local d1, d2 = doorOf(lane, level, 1), doorOf(lane, level, 2)
	if pad == nil or d1 == nil or d2 == nil then return nil end
	local m1 = d1:GetAttribute("Marked") == true
	local m2 = d2:GetAttribute("Marked") == true
	if m1 == m2 then return nil end -- both or neither marked: the fork is unreadable
	local marked = if m1 then 1 else 2
	local inverted = pad:GetAttribute("RuleInverted") == true
	return {
		marked = marked,
		inverted = inverted,
		trap = if inverted then 3 - marked else marked,
	}
end

local function choose(plr, lane, level, slot)
	local door = doorOf(lane, level, slot)
	if door == nil then return false end
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then return false end
	prompt.Triggered:Fire(plr)
	h:advance(0.5)
	return true
end

local function climb(plr, lane, level)
	local section = sectionOf(lane, level)
	if section == nil then return false end
	local exit = exitOf(section)
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if exit == nil or hrp == nil then return false end
	exit.Touched:Fire(hrp)
	h:advance(0.5)
	return true
end

--============================================================================ the doors exist

local reader = h:join("Reader", READER)
h:advance(1)
h.Players:simulateSpawn(reader, h.workspace)
h:advance(1)

truthy(towers ~= nil, "workspace.Towers exists (control: the builder ran at all)")
local readerLane = laneOf(reader)
truthy(readerLane ~= nil, "the joining player got their own lane folder")

if readerLane == nil then
	print("no lane; nothing below can run")
	error("fork tower check failed", 0)
end

truthy(readerLane:FindFirstChild("LobbyPad") ~= nil, "the lobby pad is parented into the world")
truthy(forkOf(readerLane, 1) ~= nil, "floor 1's fork is built on join")
truthy(padOf(readerLane, 1) ~= nil, "...with its inscription pad")

do
	local built = partsIn(readerLane)
	print(string.format("  Lane on join: %d BaseParts", built))
	-- 1 lobby + 1 spawn marker + 1 fork pad + 1 invisible dust host + 2 doors + 4 sign nubs.
	-- Spelled out rather than folded into a constant: if a door, a sign or the dust volume ever
	-- stops parenting, this number is the thing that notices, and the breakdown says which.
	eq(built, 10,
		"a fresh lane holds the lobby, the spawn marker, the pad, its dust volume, two doors and four signs")
end

do
	local lights = 0
	local function walk(x)
		for _, c in x:GetChildren() do
			if c.ClassName == "PointLight" then lights += 1 end
			walk(c)
		end
	end
	walk(readerLane)
	-- The preset runs at ClockTime 17.6 with heavy fog; if the door and sign lights do not
	-- parent, the two doors are silhouettes and the signs are unreadable, which is the entire
	-- game. Counting them is the only thing that catches that.
	print(string.format("  Lane on join: %d PointLights", lights))
	eq(lights, 7, "the pad, both doors and all four signs carry their light")
end

do
	local d1, d2 = doorOf(readerLane, 1, 1), doorOf(readerLane, 1, 2)
	truthy(d1:FindFirstChildOfClass("ProximityPrompt") ~= nil, "door 1 carries a ProximityPrompt")
	truthy(d2:FindFirstChildOfClass("ProximityPrompt") ~= nil, "door 2 carries a ProximityPrompt")
	truthy(d1:FindFirstChildOfClass("BillboardGui") ~= nil, "door 1 names its trait")
	local signs1 = tostring(d1:GetAttribute("Signs"))
	local signs2 = tostring(d2:GetAttribute("Signs"))
	truthy(signs1 ~= "" and signs2 ~= "", "both doors carry their signs")
	truthy(signs1 ~= signs2, "the two doors never show the same pair of signs")
	local fork = readFork(readerLane, 1)
	truthy(fork ~= nil, "floor 1's fork is READABLE: exactly one door bears the named sign")
end

--============================================================================ a door is not public

-- Done HERE, with both climbers standing at their own floor 1, and that placement is the whole
-- point. An earlier version ran this at the end of the file, by which time the reader had
-- summited — so the server refused on "you are already at the top" and the assertion passed for
-- a reason that had nothing to do with ownership. A mutation sweep deleted the guard it was
-- supposed to be testing and the check stayed green.
--
-- The defect that hid behind it was real: onDoorChosen looked up the PULLER's lane, so a prompt
-- fired in somebody else's tower answered the puller's own fork at that floor. Only reachable
-- past MaxActivationDistance, which is exactly the sort of "cannot really happen" that ships.
local naive = h:join("Naive", NAIVE)
h:advance(1)
h.Players:simulateSpawn(naive, h.workspace)
h:advance(1)

local naiveLane = laneOf(naive)
truthy(naiveLane ~= nil, "the second player got their OWN lane, not the first player's")
truthy(naiveLane ~= readerLane, "...a different folder entirely")

do
	local mineBefore = partsIn(readerLane)
	local theirsBefore = naiveLane and partsIn(naiveLane) or 0
	local d = doorOf(readerLane, 1, 1)
	local prompt = d and d:FindFirstChildOfClass("ProximityPrompt")
	truthy(prompt ~= nil and prompt.Enabled ~= false, "floor 1's door is live before anyone answers it")
	if prompt then
		prompt.Triggered:Fire(naive) -- somebody else's door, pulled by the wrong player
		h:advance(0.5)
	end
	eq(partsIn(readerLane), mineBefore, "pulling MY door builds nothing in my tower")
	if naiveLane then
		eq(partsIn(naiveLane), theirsBefore, "...and nothing in the puller's tower either")
		eq(sectionOf(naiveLane, 1), nil, "...the puller's own floor 1 is still unanswered")
	end
	eq(sectionOf(readerLane, 1), nil, "...and so is mine")
end

--============================================================================ the reader run

-- Ten floors, always the door the inscription says is safe. Zero traps, or the game's promise is
-- a lie in the built world however green the pure spec is.
local readerOk = true
for level = 1, FLOORS do
	local fork = readFork(readerLane, level)
	if fork == nil then
		failed += 1
		print("FAIL: floor " .. level .. " could not be read from the world")
		readerOk = false
		break
	end
	if not choose(reader, readerLane, level, 3 - fork.trap) then
		failed += 1
		print("FAIL: floor " .. level .. " could not be answered")
		readerOk = false
		break
	end
	if not climb(reader, readerLane, level) then
		failed += 1
		print("FAIL: floor " .. level .. "'s section could not be climbed")
		readerOk = false
		break
	end
end
truthy(readerOk, "a reader walked all ten floors")

do
	local penalties = {}
	for level = 1, FLOORS do
		local sec = sectionOf(readerLane, level)
		if sec == nil then
			failed += 1
			print("FAIL: floor " .. level .. " built no section at all")
		elseif sec:GetAttribute("Penalty") == true then
			penalties[#penalties + 1] = level
		end
	end
	eq(#penalties, 0,
		"FAIRNESS: a player who reads the inscription hits ZERO traps in the built world (hit: "
			.. table.concat(penalties, ",") .. ")")

	local ls = reader:FindFirstChild("leaderstats")
	local floorVal = ls and ls:FindFirstChild("Floor")
	eq(floorVal and floorVal.Value, FLOORS, "the reader is standing at the top floor")
	truthy(readerLane:FindFirstChild("Summit") ~= nil, "the summit is built and parented")
end

do
	-- The card actually reached the player, and it is a card and not an empty table.
	local reveal = h.ReplicatedStorage:FindFirstChild("ForkRemotes"):FindFirstChild("Reveal")
	local sent = reveal:sentTo(reader)
	truthy(#sent > 0, "the Build Reveal was fired at the player who summited")
	local card = sent[#sent] and sent[#sent].args[1]
	truthy(type(card) == "table" and type(card.title) == "string" and card.title ~= "",
		"the card carries a title")
	truthy(card and #card.traits == FLOORS, "the card lists one trait per floor climbed")
	truthy(card and card.score > 0, "the card is worth something")
	if card then
		print(string.format("  reveal: %s (%s, %d)", tostring(card.title), tostring(card.rarityName), card.score))
	end

	local ls = reader:FindFirstChild("leaderstats")
	local best = ls and ls:FindFirstChild("Best")
	truthy(best and best.Value > 0, "the score was banked to leaderstats")
end

--============================================================================ the naive run

-- Same seed, same tower, one difference: this climber trusts the sign and ignores the line that
-- says the warden is lying. They must be punished on exactly floors 4, 6 and 8.
if naiveLane ~= nil then
	for level = 1, FLOORS do
		local fork = readFork(naiveLane, level)
		if fork == nil then break end
		-- Believes the marked door is always the trap.
		choose(naive, naiveLane, level, 3 - fork.marked)
		climb(naive, naiveLane, level)
	end

	local hit, expected = {}, {}
	for level = 1, FLOORS do
		local sec = sectionOf(naiveLane, level)
		if sec and sec:GetAttribute("Penalty") == true then hit[#hit + 1] = level end
		if LIAR_FLOORS[level] then expected[#expected + 1] = level end
	end
	eq(table.concat(hit, ","), table.concat(expected, ","),
		"a climber who ignores the liar line is punished on exactly the inverted floors")
	truthy(#hit > 0, "...and the chosen seed really does contain inverted floors (this is not vacuous)")

	-- The shape of the punishment, measured in the world: same seed, same floor, same curve —
	-- the trapped section is exactly PenaltyExtraPlatforms longer, and no platform is higher.
	local level = 4
	local safe = sectionOf(readerLane, level)
	local trapped = sectionOf(naiveLane, level)
	if safe and trapped then
		eq(platformsIn(trapped), platformsIn(safe) + PENALTY_EXTRA,
			"the trapped section is exactly " .. PENALTY_EXTRA .. " platforms longer than the safe one")

		local function rises(section, lvl)
			local ys = {}
			for i = 1, platformsIn(section) do
				local p = section:FindFirstChild("Plat_" .. lvl .. "_" .. i)
				if p then ys[i] = p.Position.Y end
			end
			local worst = 0
			for i = 2, #ys do worst = math.max(worst, ys[i] - ys[i - 1]) end
			return worst
		end
		local safeRise, trapRise = rises(safe, level), rises(trapped, level)
		truthy(math.abs(trapRise - safeRise) < 1e-6,
			string.format("...and not one stud steeper (%.3f vs %.3f)", trapRise, safeRise))
	else
		failed += 1
		print("FAIL: floor 4 sections missing on one of the two players")
	end
end

--============================================================================ an answered fork

do
	-- A fork you have already walked through must not be answerable again — with the prompt
	-- disabled, and again with it forced back on, because a client that can re-arm a prompt is
	-- exactly the client this guard exists for.
	local before = partsIn(readerLane)
	local d = doorOf(readerLane, 1, 1)
	local prompt = d and d:FindFirstChildOfClass("ProximityPrompt")
	truthy(prompt ~= nil and prompt.Enabled == false, "an answered fork's prompts are disabled")
	if prompt then
		prompt.Triggered:Fire(reader)
		h:advance(0.5)
		prompt.Enabled = true
		prompt.Triggered:Fire(reader)
		h:advance(0.5)
	end
	eq(partsIn(readerLane), before, "re-triggering an answered door builds nothing, re-armed or not")
end

--============================================================================ hazards bite

do
	-- A hazard that does not send you back is a decoration, and the penalty section's whole
	-- purpose is that it is busier. Floors 2 and up carry them.
	local hazard, level = nil, nil
	for l = 2, FLOORS do
		local sec = sectionOf(readerLane, l)
		if sec then
			for _, c in sec:GetChildren() do
				if c:GetAttribute("Hazard") ~= nil and hazard == nil then
					hazard, level = c, l
				end
			end
		end
	end
	truthy(hazard ~= nil, "the tower actually contains hazards")

	local hrp = reader.Character and reader.Character:FindFirstChild("HumanoidRootPart")
	if hazard and hrp then
		hrp.CFrame = CFrame.new(0, -500, 0)
		h:advance(0.1)
		hazard.Touched:Fire(hrp)
		h:advance(0.2)
		truthy(hrp.Position.Y > -400,
			string.format("touching a hazard on floor %d returns the player to their checkpoint", level))
	end
end

--============================================================================ rebirth rerolls

do
	local before = readerLane
	local rebirth = h.ReplicatedStorage:FindFirstChild("ForkRemotes"):FindFirstChild("Rebirth")
	rebirth:simulateFireServer(reader)
	h:advance(1)

	local after = laneOf(reader)
	truthy(after ~= nil, "rebirth left the player with a lane")
	truthy(after ~= before, "...a freshly built one")
	truthy(before.Parent == nil, "...and the old tower was destroyed, not leaked")
	if after then
		eq(sectionOf(after, 1), nil, "the new run has climbed nothing yet")
		truthy(forkOf(after, 1) ~= nil, "...and floor 1's fork is waiting")
		truthy(readFork(after, 1) ~= nil, "...and it is readable")
	end
	local ls = reader:FindFirstChild("leaderstats")
	local floorVal = ls and ls:FindFirstChild("Floor")
	local best = ls and ls:FindFirstChild("Best")
	eq(floorVal and floorVal.Value, 1, "the floor counter is back to 1")
	truthy(best and best.Value > 0, "the banked best score survived the rebirth")
end

--============================================================================ CONTROL

do
	-- The change the check must NOT notice. A third player joining takes a lane of their own and
	-- must not add, remove or move a single part in somebody else's tower. Without this, any
	-- shared-state bug between lanes would read as "the world changed" and be hunted in the
	-- geometry instead of in the ownership.
	local mine = laneOf(reader)
	local before = partsIn(mine)
	local late = h:join("Latecomer", LATE)
	h:advance(1)
	h.Players:simulateSpawn(late, h.workspace)
	h:advance(1)

	eq(partsIn(mine), before, "CONTROL: a third player joining changes nothing in my tower")
	local lateLane = laneOf(late)
	truthy(lateLane ~= nil and lateLane ~= mine,
		"CONTROL: ...and they really did get a tower of their own (the control is not a no-op)")

	-- Leaving takes the whole lane, and the freed index comes back. A server that hands out a
	-- fresh index per join walks its towers out along +X until they are kilometres from spawn.
	local lateName = lateLane and lateLane.Name
	local count = #towers:GetChildren()
	h:leave(late)
	h:advance(1)
	eq(#towers:GetChildren(), count - 1, "leaving destroyed the whole lane, not just its doors")

	local reuser = h:join("Reuser", 8181)
	h:advance(1)
	local reuserLane = laneOf(reuser)
	eq(reuserLane and reuserLane.Name, lateName, "the next player REUSES the freed lane index")
	h:leave(reuser)
	h:advance(1)
end

--============================================================================ REVIEW FINDING 1
-- A tower has to stay inside its own lane.
--
-- Each section's exit X became the next floor's fork origin, so ten floors of left/right steps
-- accumulated with nothing bounding them. Measured in this world: two players on run seed 39, one
-- playing safe and one taking every trap, ended with `Lane_0 SummitPad <-> Lane_1 Plat_8_4`
-- intersecting — 47 studs of overlap between two strangers' towers. Chaining the generator over
-- 500 floors reached 2942 studs of drift against a 220-stud lane.
--
-- Measured here from the LOBBY PAD's X rather than from a lane-index formula, so the assertion
-- survives any change to how lanes are laid out.

local DRIFT_A, DRIFT_B = 3901, 3902
local LANE_SPACING = 220 -- Config.World.LaneSpacing

local function seedProfileAt(uid, runSeed)
	store:SetAsync("u_" .. uid, {
		data = {
			runSeed = runSeed, level = 1, stage = "fork", picks = {}, slots = {},
			skips = 0, rebirths = 0, bestScore = 0, bestTitle = "", redeemed = {}, passes = {},
		},
	})
end

local function bounds(node)
	local minx, maxx, miny = math.huge, -math.huge, math.huge
	local function walk(x)
		for _, c in x:GetChildren() do
			if c:IsA("BasePart") then
				local p, s = c.Position, c.Size
				minx = math.min(minx, p.X - s.X / 2)
				maxx = math.max(maxx, p.X + s.X / 2)
				miny = math.min(miny, p.Y)
			end
			walk(c)
		end
	end
	walk(node)
	return minx, maxx, miny
end

do
	seedProfileAt(DRIFT_A, 39)
	seedProfileAt(DRIFT_B, 39)
	local safe = h:join("DriftSafe", DRIFT_A)
	h:advance(1)
	h.Players:simulateSpawn(safe, h.workspace)
	local greedy = h:join("DriftTrap", DRIFT_B)
	h:advance(1)
	h.Players:simulateSpawn(greedy, h.workspace)
	h:advance(1)

	local safeLane, greedyLane = laneOf(safe), laneOf(greedy)
	truthy(safeLane ~= nil and greedyLane ~= nil, "both drift players got a lane")

	-- Same seed, opposite strategies: the two ways a run's X can walk.
	for level = 1, FLOORS do
		local f1 = readFork(safeLane, level)
		if f1 then choose(safe, safeLane, level, 3 - f1.trap); climb(safe, safeLane, level) end
		local f2 = readFork(greedyLane, level)
		if f2 then choose(greedy, greedyLane, level, f2.trap); climb(greedy, greedyLane, level) end
	end
	truthy(safeLane:FindFirstChild("Summit") ~= nil, "the safe drift player summited")
	truthy(greedyLane:FindFirstChild("Summit") ~= nil, "the trap-taking drift player summited")

	-- Every part of every lane in the world, against its own lane's centre line.
	local worst, worstLane = 0, ""
	for _, lane in towers:GetChildren() do
		local lobby = lane:FindFirstChild("LobbyPad")
		if lobby then
			local centre = lobby.Position.X
			local lo, hi = bounds(lane)
			local off = math.max(math.abs(lo - centre), math.abs(hi - centre))
			if off > worst then worst, worstLane = off, tostring(lane.Name) end
		end
	end
	truthy(worst <= LANE_SPACING / 2, string.format(
		"no tower reaches outside its own %d-stud lane slot (worst %.1f studs, %s)",
		LANE_SPACING, worst, worstLane))

	-- And the consequence, stated directly: no two towers share any X at all.
	local spans = {}
	for _, lane in towers:GetChildren() do
		local lo, hi = bounds(lane)
		if lo < math.huge then spans[#spans + 1] = { lo = lo, hi = hi, name = tostring(lane.Name) } end
	end
	local overlaps = {}
	for i = 1, #spans do
		for j = i + 1, #spans do
			local a, b = spans[i], spans[j]
			if a.lo < b.hi and b.lo < a.hi then
				overlaps[#overlaps + 1] = a.name .. "/" .. b.name
			end
		end
	end
	eq(#overlaps, 0, "no two towers overlap in X (" .. table.concat(overlaps, " ") .. ")")
end

--============================================================================ REVIEW FINDING 3
-- The checkpoint a hazard hands you must not be inside that hazard.

do
	local CHAR_HALF = 2 -- Config.World.CharacterHalfWidth; a Roblox character is 4 studs wide
	local lane = laneOf(h.Players:GetPlayerByUserId(DRIFT_B))
	local plr = h.Players:GetPlayerByUserId(DRIFT_B)
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	local notice = h.ReplicatedStorage:FindFirstChild("ForkRemotes"):FindFirstChild("Notice")

	local measured, pinned, worstGap = 0, 0, math.huge
	for level = 2, FLOORS do
		local sec = sectionOf(lane, level)
		if sec and hrp then
			for _, hz in sec:GetChildren() do
				local platIndex = hz:GetAttribute("Platform")
				local plat = platIndex and sec:FindFirstChild("Plat_" .. level .. "_" .. platIndex)
				if plat then
					-- Land on the platform the hazard stands on: that is the checkpoint it will
					-- hand back. Then touch the hazard, exactly as a player does.
					plat.Touched:Fire(hrp)
					h:advance(0.1)
					hz.Touched:Fire(hrp)
					h:advance(0.1)
					measured += 1
					local gx = math.abs(hrp.Position.X - hz.Position.X) - (hz.Size.X / 2 + CHAR_HALF)
					local gz = math.abs(hrp.Position.Z - hz.Position.Z) - (hz.Size.Z / 2 + CHAR_HALF)
					local gap = math.max(gx, gz)
					if gap < worstGap then worstGap = gap end
					if gap < 0 then pinned += 1 end
					h:advance(HAZARD_COOLDOWN)
				end
			end
		end
	end
	truthy(measured > 0, "there were hazards to walk into (the check is not vacuous)")
	eq(pinned, 0, string.format(
		"touching a hazard never returns the player INTO it (%d of %d, worst clearance %.2f studs)",
		pinned, measured, worstGap))

	-- Touched fires many times per contact. Without a cooldown every one of them is another
	-- teleport mid-teleport and another Notice down the wire.
	if hrp then
		local sec = sectionOf(lane, 3) or sectionOf(lane, 2)
		local hz = nil
		for _, c in sec:GetChildren() do
			if c:GetAttribute("Hazard") ~= nil and hz == nil then hz = c end
		end
		if hz then
			h:advance(HAZARD_COOLDOWN)
			local before = #notice:sentTo(plr)
			for _ = 1, 40 do
				hz.Touched:Fire(hrp)
			end
			h:advance(0.1)
			local sent = #notice:sentTo(plr) - before
			truthy(sent <= 2, string.format(
				"forty Touched fires in one contact cost the client %d notices, not forty", sent))
		end
	end
end

--============================================================================ REVIEW FINDING 5
-- Answering a fork with no character must not spend the floor and strand the run.

do
	local GHOST = 3903
	seedProfileAt(GHOST, 4)
	local ghost = h:join("Ghost", GHOST)
	h:advance(1)
	-- Deliberately NOT spawned: exactly the state between a Reset and the next CharacterAdded.
	local lane = laneOf(ghost)
	truthy(lane ~= nil, "a character-less player still gets a lane")
	truthy(ghost.Character == nil, "...and really has no character (the check is not vacuous)")

	local fork = readFork(lane, 1)
	choose(ghost, lane, 1, 3 - fork.trap)
	local sec = sectionOf(lane, 1)
	truthy(sec ~= nil, "the fork was answered")

	h.Players:simulateSpawn(ghost, h.workspace)
	h:advance(1)
	local hrp = ghost.Character:FindFirstChild("HumanoidRootPart")
	local first = sec and sec:FindFirstChild("Plat_1_1")
	local pad = padOf(lane, 1)
	if hrp and first and pad then
		local dPlat = math.sqrt((hrp.Position.X - first.Position.X) ^ 2 + (hrp.Position.Z - first.Position.Z) ^ 2)
		local dPad = math.sqrt((hrp.Position.X - pad.Position.X) ^ 2 + (hrp.Position.Z - pad.Position.Z) ^ 2)
		truthy(dPlat < 1, string.format(
			"a player who spawns AFTER answering a fork stands on their new section (%.1f studs from platform 1)", dPlat))
		truthy(dPad > dPlat, string.format(
			"...and not stranded on the spent fork pad (%.1f studs away from it)", dPad))
	else
		failed += 1
		print("FAIL: the ghost run built nothing to stand on")
	end
	h:leave(ghost)
	h:advance(1)
end

--============================================================================ REVIEW FINDING 4
-- Rebirth is a button. It must not be a DataStore drain.

do
	local plr = h.Players:GetPlayerByUserId(DRIFT_A)
	local rebirth = h.ReplicatedStorage:FindFirstChild("ForkRemotes"):FindFirstChild("Rebirth")
	local ls = plr:FindFirstChild("leaderstats")
	local rb = ls and ls:FindFirstChild("Rebirths")

	local notice = h.ReplicatedStorage:FindFirstChild("ForkRemotes"):FindFirstChild("Notice")
	local callsBefore = store.__calls
	local noticesBefore = #notice:sentTo(plr)
	local rbBefore = rb and rb.Value or 0
	for _ = 1, 200 do
		rebirth:simulateFireServer(plr)
	end
	h:advance(0.1)
	local refusals = #notice:sentTo(plr) - noticesBefore
	local calls = store.__calls - callsBefore
	local granted = (rb and rb.Value or 0) - rbBefore

	truthy(granted <= 2, string.format(
		"200 Rebirth fires in one frame granted %d rebirths, not 200", granted))
	truthy(calls <= 4, string.format(
		"...and cost %d DataStore calls, not 200 (the whole server's minute budget)", calls))
	-- And the REFUSAL must not become the amplifier. Answering every fire with a Notice would
	-- send 199 remotes back at exactly the rate they arrived.
	truthy(refusals <= 4, string.format(
		"...and answered them with %d messages, not one refusal per fire", refusals))

	local myLanes = 0
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then myLanes += 1 end
	end
	eq(myLanes, 1, "...and left the player exactly one tower")

	-- The button still works when it is not being held down.
	h:advance(10)
	rebirth:simulateFireServer(plr)
	h:advance(0.1)
	eq((rb and rb.Value or 0), rbBefore + granted + 1,
		"CONTROL: a rebirth after the cooldown is still granted (the throttle is not a wall)")
end

--============================================================================ REVIEW FINDING 4, second half
-- The Rebirth cooldown above caps ONE remote. The budget it protects is spent by every write
-- path, so the throttle that matters is on the write itself: a DataStore write comes out of a
-- per-SERVER allowance of 60 + 10 per player per minute, and one player's ordinary ten-floor run
-- used to spend twenty of them — one per door answered, one per floor cleared. Fill a server with
-- climbers and the autosaves and the 45-second session-lock refreshes start losing the race, which
-- silently flips other players to read-only.

do
	local SAVER = 3904
	seedProfileAt(SAVER, 4)
	local plr = h:join("Saver", SAVER)
	h:advance(1)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(1)
	local lane = laneOf(plr)

	local before = store.__calls
	for level = 1, FLOORS do
		local f = readFork(lane, level)
		if f then
			choose(plr, lane, level, 3 - f.trap)
			climb(plr, lane, level)
		end
	end
	local calls = store.__calls - before
	truthy(lane:FindFirstChild("Summit") ~= nil, "the saver summited (the measurement is not vacuous)")
	truthy(calls <= 8, string.format(
		"a whole ten-floor run cost %d DataStore writes, not one per door plus one per floor", calls))

	-- The ordered leaderboard is a SECOND store and a second budget, and bestScore only moves once
	-- per summit — so re-publishing it on every save was another write per save buying nothing.
	local lb = h.services.DataStoreService:GetOrderedDataStore("ForkTower_LB_v1")
	local summited = 0
	for _, other in h.Players:GetPlayers() do
		local ols = other:FindFirstChild("leaderstats")
		local best = ols and ols:FindFirstChild("Best")
		if best and best.Value > 0 then summited += 1 end
	end
	local lbBefore = lb.__calls
	h:advance(21) -- one autosave round for everybody in the server
	local lbCalls = lb.__calls - lbBefore
	truthy(summited >= 3, string.format(
		"%d players in this server have a banked score (the measurement is not vacuous)", summited))
	truthy(lbCalls < summited, string.format(
		"one autosave round cost %d leaderboard calls, fewer than the %d players holding a score",
		lbCalls, summited))

	-- And coalescing must not EAT the run. Leaving forces the write through; rejoining reads it
	-- back. Without this, the assertion above could be satisfied by a server that simply stopped
	-- saving, which is a far worse bug than the one it was fixing.
	h:leave(plr)
	h:advance(1)
	local back = h:join("SaverAgain", SAVER)
	h:advance(1)
	local ls = back:FindFirstChild("leaderstats")
	local floorVal = ls and ls:FindFirstChild("Floor")
	eq(floorVal and floorVal.Value, FLOORS,
		"...and the coalesced run came back whole after leaving and rejoining")
	h:leave(back)
	h:advance(1)
end

--============================================================================ normal play warned nothing

print("")
for _, w in h.warnings do
	print("server warned: " .. w)
end
eq(#h.warnings, 0, "the server built every tower without a single warning")

--============================================================================ REVIEW FINDING 2
-- More players than lanes must not mean two players in one tower.
--
-- claimLane returned 0 when every lane was taken, without signalling failure, so the 25th player
-- got a tower at player 1's exact coordinates. Measured before the fix: 27 joins produced
-- `Lane_0 x4` — four complete towers at identical coordinates, zero server errors, nothing warned.
-- teardownLane then freed that index when the overflow player left, even though the original
-- owner was still standing in it, so the collision spread.

do
	local crowd = {}
	for i = 1, 30 do
		crowd[i] = h:join("Crowd" .. i, 41000 + i)
		h:advance(0.2)
	end
	h:advance(1)

	local seen, dupes = {}, {}
	for _, f in towers:GetChildren() do
		local n = tostring(f.Name)
		if seen[n] then dupes[#dupes + 1] = n end
		seen[n] = true
	end
	eq(#dupes, 0, "no two towers share a lane index (" .. table.concat(dupes, ",") .. ")")

	local spots, stacked = {}, {}
	for _, f in towers:GetChildren() do
		local lobby = f:FindFirstChild("LobbyPad")
		if lobby then
			local at = string.format("%.1f", lobby.Position.X)
			if spots[at] then stacked[#stacked + 1] = at end
			spots[at] = true
		end
	end
	eq(#stacked, 0, "no two towers stand at the same world position (" .. table.concat(stacked, ",") .. ")")

	-- One owner per lane, and one lane per owner.
	local owners, twoLanes = {}, 0
	for _, f in towers:GetChildren() do
		local o = f:GetAttribute("Owner")
		if o ~= nil then
			if owners[o] then twoLanes += 1 end
			owners[o] = true
		end
	end
	eq(twoLanes, 0, "nobody owns two towers")

	-- The freed-index cascade: an overflow player leaving must not hand their index to somebody
	-- who is standing in it.
	local victimLane = nil
	for _, f in towers:GetChildren() do
		if victimLane == nil and f:FindFirstChild("LobbyPad") then victimLane = f end
	end
	local victimName = victimLane and tostring(victimLane.Name)
	h:leave(crowd[30])
	h:advance(1)
	h:leave(crowd[29])
	h:advance(1)
	local newcomer = h:join("Newcomer", 41999)
	h:advance(1)
	local stillThere = 0
	for _, f in towers:GetChildren() do
		if tostring(f.Name) == victimName then stillThere += 1 end
	end
	eq(stillThere, 1, "the lane an occupied player is standing in was not handed to anybody else")
	truthy(newcomer ~= nil, "...and the newcomer still joined")

	local seen2, dupes2 = {}, {}
	for _, f in towers:GetChildren() do
		local n = tostring(f.Name)
		if seen2[n] then dupes2[#dupes2 + 1] = n end
		seen2[n] = true
	end
	eq(#dupes2, 0, "...and still no two towers share an index after the churn")

	-- Anyone the server could not seat has to be TOLD, not dropped into the void.
	local notice = h.ReplicatedStorage:FindFirstChild("ForkRemotes"):FindFirstChild("Notice")
	local seated, unseated, told = 0, 0, 0
	for _, plr in h.Players:GetPlayers() do
		if laneOf(plr) ~= nil then
			seated += 1
		else
			unseated += 1
			local wasTold = false
			for _, msg in notice:sentTo(plr) do
				local a = msg.args and msg.args[1]
				if type(a) == "table" and a.kind == "full" then wasTold = true end
			end
			if wasTold then told += 1 end
		end
	end
	print(string.format("  crowd: %d players seated, %d unseated", seated, unseated))
	eq(told, unseated, "every player the server had no lane for was told so")
	truthy(seated > 0, "...and the ones it did have room for are playing")

	-- A player without a lane must still be told, at a moment their HUD is listening, and must
	-- still land on something solid.
	local orphan = nil
	for _, plr in h.Players:GetPlayers() do
		if orphan == nil and laneOf(plr) == nil then orphan = plr end
	end
	if orphan then
		local said = #notice:sentTo(orphan)
		h.Players:simulateSpawn(orphan, h.workspace)
		h:advance(1)
		truthy(#notice:sentTo(orphan) > said,
			"an unseated player is told AGAIN once their character exists, because the first "
				.. "message went out before their HUD could have connected")
	end

	-- HOUSE RULE, learned in this repo hours ago: a world whose only spawn points are disabled
	-- makes Roblox drop the character wherever it likes — the roof of a sealed shell, or in this
	-- game the empty air at the world origin. Every LANE spawn here is Enabled = false on purpose
	-- (the server places you on your checkpoint itself), so exactly one real one has to exist
	-- outside them, standing on something.
	local enabled = {}
	local function scan(x)
		for _, c in x:GetChildren() do
			if c.ClassName == "SpawnLocation" and c.Enabled == true then enabled[#enabled + 1] = c end
			scan(c)
		end
	end
	scan(h.workspace)
	truthy(#enabled >= 1, string.format("the place has a real, ENABLED SpawnLocation (found %d)", #enabled))
	local wait = h.workspace:FindFirstChild("Waiting")
	local pad = wait and wait:FindFirstChild("WaitingPad")
	truthy(pad ~= nil, "...and a waiting pad outside every lane to put it on")
	if pad and enabled[1] then
		local sp = enabled[1]
		local onPad = math.abs(sp.Position.X - pad.Position.X) <= pad.Size.X / 2
			and math.abs(sp.Position.Z - pad.Position.Z) <= pad.Size.Z / 2
			and sp.Position.Y > pad.Position.Y
		truthy(onPad, "...and the spawn really stands on that pad rather than beside it")
	end
end

--============================================================================ done

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("fork tower: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower check failed", 0)
end
