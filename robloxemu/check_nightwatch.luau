-- Nightwatch Manor — the world has to actually EXIST, and the loop has to be walkable.
-- Run: luau check_nightwatch.luau
-- Regenerate the bundle first:
--   py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- Modelled on check_crystal_sockets.luau, and for the same reason. Grow a Crystal shipped with
-- makeSocket never assigning `part.Parent`: the entire core loop was unreachable in a published
-- game and all 166 unit tests stayed green, because none of them could see the workspace. So
-- this file asks the workspace how many parts arrived, and then plays the game:
--   * the safehouse is built, with a pad per upgrade;
--   * pressing a pad's prompt buys a level AND builds a prop you can see;
--   * a stranger pressing MY pad buys nothing;
--   * the manor door builds a manor: rooms, relics on pedestals, an exit, a Nightwatcher;
--   * taking a relic removes it from the world and puts it in the bag;
--   * escaping banks the bag and advances the night;
--   * being caught costs the bag and does NOT advance the night;
--   * leaving frees the zone index for the next player.
--
-- The pure specs in nightwatch-manor/tests/ cover the arithmetic. Everything here is the part
-- they structurally cannot see: whether any of it is parented, prompted and reachable.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/nightwatch-manor"),
	name = "nightwatch-manor",
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
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local ME = 4242
local UPGRADES = 7 -- #Config.Upgrades.Catalog

-- The server reads the profile out of `.data` under "u_<uid>" and stamps a session lock beside
-- it. Written the way loadProfile actually reads it, with enough relics banked to afford the
-- cheapest upgrade twice (lanterns: 40 then 64).
local store = h.services.DataStoreService:GetDataStore("NightwatchManor_v1")
store:SetAsync("u_" .. ME, {
	data = { night = 1, stash = 500, best = 0, levels = {} },
})

assert(h:tryRun("server/Main.server"))
h:advance(1)

--=========================================== there is a floor before there is a player

-- Roblox spawns a character wherever it likes when the place contains no SpawnLocation, and this
-- game builds nothing at the world origin: every zone is at index * 3000 along +X. Measured on
-- the shipped build, the workspace held 0 BaseParts and 0 SpawnLocations before anyone joined,
-- so a joining character was dropped into empty air and fell — past FallenPartsDestroyHeight in
-- about 2.3 seconds, at which point it is destroyed and the player dies without seeing the game.
do
	local nearOrigin, spawns = 0, 0
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.Position
			if math.abs(p.X) < 500 and math.abs(p.Y) < 500 and math.abs(p.Z) < 500 then
				nearOrigin += 1
			end
		end
		if d.ClassName == "SpawnLocation" then spawns += 1 end
	end
	truthy(nearOrigin > 0, "before ANY player joins there is something solid at the world origin to land on")
	truthy(spawns > 0, "and a SpawnLocation, so the engine has somewhere to put a character it spawns itself")
end

local me = h:join("Nightwatchman", ME)
h:advance(1)

--============================ the character is placed on the frame it spawns, not a fifth of a second later

do
	local char = h.Players:simulateSpawn(me, h.workspace)
	-- NO h:advance here on purpose. CharacterAdded has fired and returned; a placement that
	-- waits `task.wait(0.2)` has not run, and 0.2 seconds is 0.2 seconds of falling.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	truthy(hrp ~= nil, "the character has a root part")
	local at = hrp and hrp.Position
	truthy(at ~= nil and at.Magnitude > 1000, "the joining character is moved to its own zone on the SAME frame it appears")

	-- ...and the engine is told where to put it as well, which is the half a CFrame write cannot
	-- do: a death mid-night respawns through RespawnLocation, not through our handler.
	local respawn = (me :: any).RespawnLocation
	truthy(respawn ~= nil, "the player has a RespawnLocation")
	truthy(respawn ~= nil and respawn.ClassName == "SpawnLocation", "...and it is a real SpawnLocation")
	local zoneOf = respawn
	while zoneOf ~= nil and not string.match(tostring(zoneOf.Name), "^Zone_") do
		zoneOf = zoneOf.Parent
	end
	truthy(zoneOf ~= nil, "...standing inside that player's own zone, so leaving takes it with them")

	-- The player's speed is the number the whole chase is balanced against; leaving it to the
	-- engine's default is what let a Nightwatcher that outran the player ship green.
	local hum = char:FindFirstChildOfClass("Humanoid")
	truthy(hum ~= nil, "the character has a Humanoid")
	local cfg = h.modules["shared/Config"].value
	eq(hum and hum.WalkSpeed, cfg.Player.WalkSpeed, "and the server set its WalkSpeed from Config.Player")
end
h:advance(1)

local remotes = h.ReplicatedStorage:FindFirstChild("ManorRemotes")
truthy(remotes ~= nil, "the server created its remotes folder")
local stateRemote = remotes and remotes:FindFirstChild("State")
local noticeRemote = remotes and remotes:FindFirstChild("Notice")
truthy(stateRemote ~= nil, "there is a State remote to drive the HUD")
truthy(noticeRemote ~= nil, "there is a Notice remote to narrate events")

-- The remote shim records FireClient as { player = ..., args = table.pack(payload) }, so the
-- payload is args[1]; `sentTo` filters to one player, which matters the moment a second player
-- joins and starts receiving their own State pushes.
local function lastState()
	local sent = stateRemote:sentTo(me)
	for i = #sent, 1, -1 do
		if type(sent[i].args[1]) == "table" then
			return sent[i].args[1]
		end
	end
	return nil
end
local function noticesOfKind(kind)
	local n = 0
	for _, s in noticeRemote:sentTo(me) do
		local payload = s.args[1]
		if type(payload) == "table" and payload.kind == kind then
			n += 1
		end
	end
	return n
end

--=================================================================== the safehouse is in the world

local zones = {}
for _, c in h.workspace:GetChildren() do
	if string.match(tostring(c.Name), "^Zone_") then
		table.insert(zones, c)
	end
end
eq(#zones, 1, "the joining player got exactly one zone in the workspace")

local zone = zones[1]
local house = zone and zone:FindFirstChild("Safehouse")
truthy(house ~= nil, "the zone holds a Safehouse (control: the builder ran at all)")

local baseParts, lights = 0, 0
if house then
	for _, d in house:GetDescendants() do
		if d:IsA("BasePart") then baseParts += 1 end
		if d.ClassName == "PointLight" then lights += 1 end
	end
end
print(string.format("  Safehouse: %d BaseParts, %d PointLights", baseParts, lights))
-- 6 shell parts (floor, ceiling, 3 walls, 2 south segments = 7) + spawn pad + manor door + 7
-- upgrade pads + 2 hub lamps. Spelled out rather than folded into one constant so that if the
-- number moves, the thing that moved is identifiable.
eq(baseParts, 7 + 1 + 1 + UPGRADES + 2, "the safehouse is exactly the shell, the pads and the lamps")
truthy(lights >= 3, "the safehouse is lit (the Horror preset sets ClockTime 0.2 — no sun to fall back on)")

local pads = {}
if house then
	for _, d in house:GetChildren() do
		if d:GetAttribute("UpgradeId") ~= nil then
			pads[d:GetAttribute("UpgradeId")] = d
		end
	end
end
local padCount = 0
for _ in pads do padCount += 1 end
eq(padCount, UPGRADES, "every upgrade in the catalog has a pad standing in the safehouse")
for id, pad in pads do
	truthy(pad:FindFirstChildOfClass("ProximityPrompt") ~= nil, "pad " .. tostring(id) .. " carries a prompt")
end

--============================================================================== buying an upgrade

local lanternPad = pads.lanterns
if lanternPad == nil then
	failed += 1
	print("FAIL: no lanterns pad, so the tycoon half cannot be exercised")
else
	local props = lanternPad:FindFirstChild("Props")
	truthy(props ~= nil, "the pad has a Props folder for its visible hardware")
	eq(#props:GetChildren(), 0, "nothing is built on it before it is bought")

	local before = lastState()
	truthy(before ~= nil, "the server pushed a State payload at join")
	eq(before and before.stash, 500, "the seeded stash loaded out of the DataStore")
	eq(before and before.phase, "DAY", "a joining player starts in the safehouse, not mid-night")

	local prompt = lanternPad:FindFirstChildOfClass("ProximityPrompt")
	prompt.Triggered:Fire(me)
	h:advance(0.5)

	local after = lastState()
	eq(after and after.stash, 460, "buying the first lantern level cost exactly 40 relics")
	truthy(#props:GetChildren() > 0, "and it built something you can actually see on the pad")
	eq(#props:GetChildren(), 1, "one level, one lantern")
	eq(after and after.hubLevel, 1, "the hub level went up")

	-- Buying again must charge the NEXT price, not the first one.
	prompt.Triggered:Fire(me)
	h:advance(0.5)
	local twice = lastState()
	eq(twice and twice.stash, 460 - 64, "the second level cost the escalated price")
	eq(#props:GetChildren(), 2, "and a second lantern appeared")

	-- Somebody else pressing MY pad must buy nothing. The server checks `who == plr`, and this
	-- is the assertion that keeps that check honest.
	local stranger = h:join("Stranger", 9191)
	h:advance(1)
	local mineBefore = lastState().stash
	prompt.Triggered:Fire(stranger)
	h:advance(0.5)
	eq(lastState().stash, mineBefore, "a stranger pressing my pad spends none of my relics")
	eq(#props:GetChildren(), 2, "and builds nothing on my pad")
	h:leave(stranger)
	h:advance(0.5)
end

-- A purchase nobody can afford has to SAY so rather than silently doing nothing. ("i cant even
-- place a seed" in a sibling game was exactly a silent return.)
do
	local floodPad = pads.floodlights
	if floodPad ~= nil then
		local deniedBefore = noticesOfKind("DENIED")
		-- 200 relics for the first level; the stash is down to 396 after the lanterns, so buy
		-- until it cannot be afforded, then check the refusal is announced.
		local prompt = floodPad:FindFirstChildOfClass("ProximityPrompt")
		for _ = 1, 4 do
			prompt.Triggered:Fire(me)
			h:advance(0.2)
		end
		truthy(noticesOfKind("DENIED") > deniedBefore, "a purchase that fails tells the player why")
	end
end

-- Buy a Relic Vault before going in. This is not padding: without a live relicValue multiplier,
-- a server that hands Night.resolve the WRONG effects table (an empty one, say) banks exactly the
-- same number as a correct one, and the escape assertion below cannot tell them apart. A verified
-- mutation — swapping run.effects for Upgrades.effects(Config, {}) in resolveNight — survived the
-- whole run until this purchase existed.
do
	local vaultPad = pads.relicvault
	truthy(vaultPad ~= nil, "there is a Relic Vault pad to buy")
	if vaultPad ~= nil then
		local before = lastState()
		vaultPad:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
		h:advance(0.3)
		local after = lastState()
		eq(after.stash, before.stash - 100, "the Relic Vault cost its 100 relics")
		eq(after.hubLevel, before.hubLevel + 1, "and counts toward the hub level")
	end
end

--============================================================================ into the manor

local door = house and house:FindFirstChild("ManorDoor")
truthy(door ~= nil, "the safehouse has a door into the manor")
local doorPrompt = door and door:FindFirstChildOfClass("ProximityPrompt")
truthy(doorPrompt ~= nil, "and the door carries a prompt")

eq(zone:FindFirstChild("Manor"), nil, "no manor exists while the player is in the safehouse")

doorPrompt.Triggered:Fire(me)
h:advance(0.5)

local manor = zone:FindFirstChild("Manor")
truthy(manor ~= nil, "pressing the door BUILT a manor in the workspace")

local nightState = lastState()
eq(nightState and nightState.phase, "NIGHT", "and the run moved into the night phase")

local roomFolders, pedestals, manorParts = 0, {}, 0
if manor then
	for _, c in manor:GetChildren() do
		if string.match(tostring(c.Name), "^Room%d+_") then roomFolders += 1 end
		if string.match(tostring(c.Name), "^Pedestal_") then table.insert(pedestals, c) end
	end
	for _, d in manor:GetDescendants() do
		if d:IsA("BasePart") then manorParts += 1 end
	end
end
print(string.format("  Manor: %d rooms, %d pedestals, %d BaseParts", roomFolders, #pedestals, manorParts))
-- Night 1 with hub level 1 (two lantern levels + whatever floodlights landed): Manor.roomCount
-- is BaseRooms + floor(hubLevel * 0.35), so it is at least the base 6.
truthy(roomFolders >= 6, "the manor has at least its base six rooms")
truthy(manorParts > 60, "the rooms are made of real parts, not empty folders")
eq(#pedestals, nightState and nightState.relicsTotal, "there is one pedestal per relic the plan placed")
truthy(#pedestals >= 4, "night 1 places at least the base four relics")

-- Every pedestal has to hold a relic AND a prompt, or a relic the plan counted cannot be taken
-- and a full clear of the manor is impossible.
local withRelic, withPrompt = 0, 0
for _, p in pedestals do
	if p:FindFirstChild("Relic") ~= nil then withRelic += 1 end
	if p:FindFirstChildOfClass("ProximityPrompt") ~= nil then withPrompt += 1 end
end
eq(withRelic, #pedestals, "every pedestal is holding a relic")
eq(withPrompt, #pedestals, "every pedestal can be pressed")

local exitDoor = manor and manor:FindFirstChild("ExitDoor")
truthy(exitDoor ~= nil, "the manor has a way out")
truthy(exitDoor and exitDoor:FindFirstChildOfClass("ProximityPrompt") ~= nil, "and the way out is pressable")

local watcher = manor and manor:FindFirstChild("Nightwatcher")
truthy(watcher ~= nil, "the Nightwatcher is in the world")
truthy(watcher and watcher.PrimaryPart ~= nil, "and it has a PrimaryPart, so it can be moved")

--=============================================== the lantern the player PAID for is on them

-- `lampRadius` is the whole mechanical payload of the Safehouse Lanterns upgrade. Two levels
-- were bought above, so the light the server hangs on the character has to be BASE + 2 levels.
-- Without this assertion the upgrade is a prop on a pad and a number in a table: it stacks
-- visibly, it costs relics, and nothing inside the manor changes — which from the player's side
-- is indistinguishable from the purchase silently failing.
do
	local char = me.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	truthy(hrp ~= nil, "the player has a HumanoidRootPart to carry a light on")
	local lamp = hrp and hrp:FindFirstChild("NightLantern")
	truthy(lamp ~= nil, "the player is carrying a lantern into the manor")
	-- LAMP_BASE_RANGE 18 + lanterns level 2 * per-level 6
	eq(lamp and lamp.Range, 18 + 2 * 6, "and its range is base plus the two levels that were bought")
end

--============================================================ the watcher actually walks its route

do
	local before = watcher and watcher.PrimaryPart.Position
	h:advance(3)
	local after = watcher and watcher.PrimaryPart.Position
	local moved = before ~= nil and after ~= nil and (after - before).Magnitude
	truthy(moved ~= nil and moved > 1, "three seconds of patrol moved the Nightwatcher (" .. tostring(moved) .. " studs)")
end

--================================================================================ taking relics

do
	local carriedBefore = lastState().carried
	eq(carriedBefore, 0, "you walk in empty-handed")

	local first = pedestals[1]
	local prompt = first:FindFirstChildOfClass("ProximityPrompt")
	prompt.Triggered:Fire(me)
	h:advance(0.3)

	eq(lastState().carried, 1, "pressing a pedestal put the relic in the bag")
	eq(first:FindFirstChild("Relic"), nil, "and took it out of the world")
	truthy(lastState().carriedWorth > 0, "the bag is worth something")

	-- Pressing the same empty pedestal again must not mint a second relic.
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	eq(lastState().carried, 1, "pressing an emptied pedestal a second time takes nothing")

	local second = pedestals[2]
	if second ~= nil then
		second:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
		h:advance(0.3)
		eq(lastState().carried, 2, "a second pedestal adds a second relic")
	end
end

--=================================================== the two prompts INSIDE the manor are mine

-- The upgrade-pad guard is covered above ("a stranger pressing my pad spends none of my relics").
-- These two were not, and a review removed both `who ~= plr` checks — anyone could empty your
-- pedestals or end your night — with all 390 spec assertions and all 84 headless ones still
-- green. Zones are 3000 studs apart and MaxActivationDistance is 12, so this is defence in
-- depth rather than a live exploit; the point is that nothing noticed it was gone.
do
	local intruder = h:join("Intruder", 3131)
	h:advance(1)

	local carriedBefore = lastState().carried
	local emptyPedestal
	for _, p in pedestals do
		if p:FindFirstChild("Relic") ~= nil then emptyPedestal = p break end
	end
	truthy(emptyPedestal ~= nil, "there is still a loaded pedestal to try")
	if emptyPedestal then
		emptyPedestal:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(intruder)
		h:advance(0.3)
		eq(lastState().carried, carriedBefore, "a STRANGER pressing my pedestal puts nothing in my bag")
		truthy(emptyPedestal:FindFirstChild("Relic") ~= nil, "...and does not take the relic out of my world")
	end

	local nightBefore = lastState().night
	exitDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(intruder)
	h:advance(0.3)
	eq(lastState().phase, "NIGHT", "a STRANGER pressing my exit door does NOT end my night")
	eq(lastState().night, nightBefore, "...and does not advance it")
	eq(noticesOfKind("EXTRACTED"), 0, "...and I am not told I got out")

	h:leave(intruder)
	h:advance(0.5)
end

--================================================================================== escaping

local stashBeforeEscape = lastState().stash
local worthCarried = lastState().carriedWorth

exitDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
h:advance(0.3)

do
	local s = lastState()
	-- `worthCarried` is the server's own payout figure, which includes the Relic Vault multiplier
	-- bought above. Equality here is therefore the assertion that resolveNight resolves with the
	-- PLAYER'S effects and not some other table.
	eq(s.stash, stashBeforeEscape + worthCarried, "escaping banked exactly what was in the bag")
	truthy(worthCarried > 0, "the bag was worth something to begin with")
	eq(s.night, 2, "and moved the player on to night 2")
	eq(s.best, 1, "night 1 is now the record")
	eq(s.carried, 0, "the bag is empty again")
	eq(noticesOfKind("EXTRACTED"), 1, "the player was told they got out")
end

-- ...and the manor is torn down after the beat, rather than left standing in the workspace.
h:advance(4)
eq(zone:FindFirstChild("Manor"), nil, "the manor is cleared away once you are back in the safehouse")
eq(lastState().phase, "DAY", "and the run is back in the day phase")
do
	local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	eq(hrp and hrp:FindFirstChild("NightLantern"), nil, "and the lantern is put out back home")
end

--=========================================================================== getting caught

do
	doorPrompt.Triggered:Fire(me)
	h:advance(0.5)
	local manor2 = zone:FindFirstChild("Manor")
	truthy(manor2 ~= nil, "night 2 built its own manor")

	local peds2 = {}
	for _, c in manor2:GetChildren() do
		if string.match(tostring(c.Name), "^Pedestal_") then table.insert(peds2, c) end
	end
	truthy(#peds2 > 0, "night 2 has relics in it")
	peds2[1]:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
	h:advance(0.3)
	truthy(lastState().carried > 0, "and the player picked one up")

	local stashBefore = lastState().stash
	local nightBefore = lastState().night

	-- Walk the character straight into the Nightwatcher. No Lockbox has been bought, so the
	-- whole bag is forfeit and the night must NOT advance.
	local w2 = manor2:FindFirstChild("Nightwatcher")
	truthy(w2 ~= nil, "night 2 has a Nightwatcher too")
	local char = me.Character
	char:PivotTo(CFrame.new(w2.PrimaryPart.Position))
	h:advance(0.5)

	local s = lastState()
	eq(s.stash, stashBefore, "being caught banked nothing")
	eq(s.night, nightBefore, "and did NOT advance the night — you retry it")
	eq(s.carried, 0, "the bag is gone")
	eq(noticesOfKind("CAUGHT"), 1, "the player was told what happened")

	h:advance(4)
	eq(zone:FindFirstChild("Manor"), nil, "and the manor is cleared after a death too")
end

--============================================================== CONTROL: renaming an upgrade
-- A change the run must NOT notice. The pad prompts and the HUD rows read `name`, which is copy;
-- the id is what everything is keyed on. If this block goes red, the check above is asserting on
-- flavour text and every copy edit becomes a broken build.
do
	-- The live Config table, straight out of the harness module registry. (`require` on the
	-- Instance is the ROBLOX way and is what the server does; from this runner thread the CLI's
	-- own string-only `require` is what is in scope, so the registry is the honest route.)
	local mod = h.modules["shared/Config"]
	truthy(mod ~= nil and mod.value ~= nil, "the harness evaluated shared/Config")
	local cfg = mod.value
	local entry
	for _, e in cfg.Upgrades.Catalog do
		if e.id == "beartraps" then entry = e end
	end
	local before = entry.name
	entry.name = "Rusted Jaws"
	local pad = pads.beartraps
	local stashBefore = lastState().stash
	pad:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
	h:advance(0.3)
	local ok = lastState().stash == stashBefore - 75 and #pad:FindFirstChild("Props"):GetChildren() == 1
	entry.name = before
	truthy(ok, "CONTROL: renaming an upgrade changes nothing it costs or builds")
end

--===================================================== leaving takes the zone, and frees the index

do
	local before = 0
	for _, c in h.workspace:GetChildren() do
		if string.match(tostring(c.Name), "^Zone_") then before += 1 end
	end

	local ghost = h:join("Passerby", 7171)
	h:advance(1)
	local ghostZone = h.workspace:FindFirstChild("Zone_7171")
	truthy(ghostZone ~= nil, "a second player got their own zone")
	local ghostIndex = ghostZone and ghostZone:GetAttribute("Index")
	truthy(ghostIndex ~= nil, "and it is tagged with a zone index")

	h:leave(ghost)
	h:advance(1)
	eq(h.workspace:FindFirstChild("Zone_7171"), nil, "leaving destroyed the whole zone, not just its contents")

	local reuser = h:join("Reuser", 8181)
	h:advance(1)
	local reuserZone = h.workspace:FindFirstChild("Zone_8181")
	truthy(reuserZone ~= nil, "the next player got a zone")
	eq(reuserZone and reuserZone:GetAttribute("Index"), ghostIndex,
		"and REUSES the freed index instead of marching further out along +X")
	h:leave(reuser)
	h:advance(1)

	local after = 0
	for _, c in h.workspace:GetChildren() do
		if string.match(tostring(c.Name), "^Zone_") then after += 1 end
	end
	eq(after, before, "no zone leaked")
end

--=========================== the world exists BEFORE the profile round-trip, not after it

-- The defect this covers: onPlayerAdded used to call claimProfile — a blocking UpdateAsync —
-- FIRST and build the zone afterwards, so for the entire round-trip the joining player had
-- nothing under them anywhere in the world. This harness could not see it, because its DataStore
-- is synchronous and never yields ("the harness cannot reproduce it" is exactly what the review
-- wrote). So: wrap the very store object the server is holding and make UpdateAsync take a
-- second, the way a cold server or a throttled request does.
do
	local g = h.scheduler:globals()
	local slowStore = h.services.DataStoreService:GetDataStore("NightwatchManor_v1")
	slowStore:SetAsync("u_5150", { data = { night = 9, stash = 123, best = 8, levels = {} } })
	local realUpdate = getmetatable(slowStore).UpdateAsync
	local calls = 0
	slowStore.UpdateAsync = function(self, key, fn)
		calls += 1
		g.task.wait(1.0)
		return realUpdate(self, key, fn)
	end

	-- The join runs on a scheduler thread: the emulator fires PlayerAdded synchronously on
	-- whoever called it, and yielding the runner's own thread would stop the clock that has to
	-- resume it.
	g.task.spawn(function()
		h:join("Slowpoke", 5150)
	end)
	h:advance(0.2) -- less than the round-trip: the server is still inside UpdateAsync

	truthy(calls > 0, "CONTROL: the join really is blocked inside a DataStore call")
	local slow = h.Players:GetPlayerByUserId(5150)
	truthy(slow ~= nil, "the player is in the game while their profile is still in flight")

	local zone = h.workspace:FindFirstChild("Zone_5150")
	truthy(zone ~= nil, "their zone exists WHILE the profile call is still in flight")
	local house = zone and zone:FindFirstChild("Safehouse")
	truthy(house ~= nil, "...with the safehouse already built in it")
	local pad = house and house:FindFirstChild("SpawnPad")
	truthy(pad ~= nil, "...and a spawn point standing on its floor")
	truthy(pad ~= nil and pad.ClassName == "SpawnLocation", "...which is a real SpawnLocation")
	truthy(slow ~= nil and (slow :: any).RespawnLocation ~= nil, "...and is already this player's RespawnLocation")

	-- What must NOT happen in that window is spending: the levels and the stash on screen are
	-- still the defaults, so a purchase would either refuse one the player can afford or grant
	-- one they cannot.
	local lantern
	if house then
		for _, d in house:GetChildren() do
			if d:GetAttribute("UpgradeId") == "lanterns" then lantern = d end
		end
	end
	truthy(lantern ~= nil, "their lantern pad is standing too")
	if lantern and slow then
		local props = lantern:FindFirstChild("Props")
		lantern:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(slow)
		h:advance(0.1)
		eq(#props:GetChildren(), 0, "pressing a pad before the profile lands builds nothing")
		local denied = 0
		for _, s in noticeRemote:sentTo(slow) do
			if type(s.args[1]) == "table" and s.args[1].kind == "DENIED" then denied += 1 end
		end
		truthy(denied > 0, "...and says so rather than failing silently")
	end

	-- ...and once it lands, the real profile is what is on screen.
	h:advance(2)
	local landed
	if slow then
		local sent = stateRemote:sentTo(slow)
		for i = #sent, 1, -1 do
			if type(sent[i].args[1]) == "table" then landed = sent[i].args[1]; break end
		end
	end
	truthy(landed ~= nil, "the profile landed and the HUD was told")
	eq(landed and landed.stash, 123, "...with the stash that was in the DataStore")
	eq(landed and landed.night, 9, "...and the night they were really on")

	slowStore.UpdateAsync = nil -- back to the metatable's own, so leaving does not yield
	if slow then
		h:leave(slow)
		h:advance(1)
	end
	eq(h.workspace:FindFirstChild("Zone_5150"), nil, "and leaving took the zone with them")
end

--=========================================================================================== done

print("")
for _, w in h.warnings do
	print("warning: " .. w)
end
eq(#h.warnings, 0, "the server built the world without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("nightwatch manor: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("nightwatch manor check failed", 0)
end
