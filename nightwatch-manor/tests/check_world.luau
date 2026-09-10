-- Nightwatch Manor — the four guards that REVIEW-2 proved nothing was testing, plus the exit
-- door's new wall.
--
-- Run from this directory:
--   py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
--   luau check_world.luau
--
-- Every assertion here exists because a named mutation SURVIVED all 592 assertions in the repo:
--
--   M11  beginNight's `if not prof.loaded then` -> `if false then`.   Somebody really on night 14
--        walks into night 1's manor and the load rewrites the night under them mid-run.
--   M13  the upgrade pad's `if not p.loaded then` -> `if false then`. The assertion that looked
--        like it covered this passed for an unrelated reason: the default profile's stash is 0,
--        so `Upgrades.canBuy` already refused, and the server still emitted a DENIED and still
--        built nothing. Both outcomes were identical — EXCEPT in what the player is told, and
--        that is the difference this file asserts. With the gate, a player with 900 relics
--        banked is told the safehouse is still opening. Without it, they are told they cannot
--        afford 40 relics, which is a lie, on the shipped config, with nothing retuned.
--   M12  the OriginPlate moved to y = -4000 (the SpawnLocation kept).
--   M15  the OriginSpawn moved to y = -4000 (the plate kept).
--        The old check asserted only "ANY BasePart within 500 studs of the origin" and "ANY
--        SpawnLocation anywhere", so each object covered the other's absence and neither was
--        pinned. M15 in particular IS the free-fall-and-destroy this whole fix was about.
--   M16  `spawnPad.Enabled = true` -> `false`. A disabled SpawnLocation is not a legal
--        RespawnLocation — which is what the comment on that very line says — and Roblox falls
--        back to picking a random enabled neutral one, which in this game is somebody else's
--        safehouse pad 3000 studs away.

local Harness = require("../../robloxemu/emu/harness")

local h = Harness.new({
	bundle = require("./build/nightwatch-manor"),
	name = "nightwatch-manor-world",
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

local Config = nil -- filled in once the server has required it

assert(h:tryRun("server/Main.server"))
h:advance(1)
Config = h.modules["shared/Config"].value
truthy(Config ~= nil, "the harness evaluated shared/Config")

--=============================== the floor and the spawn point are IN THE SAME PLACE as each other

-- Not "something exists near the origin" and "a SpawnLocation exists somewhere": those two are
-- what let a plate at y = -4000 and a spawn at y = -4000 each pass on the other's presence. What
-- has to be true is that the engine's own default spawn point is standing ON something.
do
	local plate, spawn
	for _, d in h.workspace:GetDescendants() do
		if d.Name == "OriginPlate" then plate = d end
		if d.ClassName == "SpawnLocation" and d.Name == "OriginSpawn" then spawn = d end
	end
	truthy(plate ~= nil, "there is an OriginPlate before anybody joins")
	truthy(spawn ~= nil, "...and an OriginSpawn SpawnLocation")

	if plate and spawn then
		local p, s = plate.Position, spawn.Position
		truthy(math.abs(p.X) < 30 and math.abs(p.Y) < 30 and math.abs(p.Z) < 30,
			string.format("the plate is AT the world origin, not near it (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z))
		truthy(math.abs(s.X) < 30 and math.abs(s.Y) < 30 and math.abs(s.Z) < 30,
			string.format("the spawn point is AT the world origin (%.1f, %.1f, %.1f)", s.X, s.Y, s.Z))

		-- Horizontally inside the plate's footprint...
		truthy(math.abs(s.X - p.X) <= plate.Size.X / 2 and math.abs(s.Z - p.Z) <= plate.Size.Z / 2,
			"the spawn point stands inside the plate's footprint, not beside it")
		-- ...and resting on its top surface rather than hovering over it or sunk under it. This
		-- is the pair of numbers that fails for M12 AND for M15, which is the whole point.
		local plateTop = p.Y + plate.Size.Y / 2
		local spawnBottom = s.Y - spawn.Size.Y / 2
		truthy(spawnBottom >= plateTop - 1.01 and spawnBottom <= plateTop + 2.01, string.format(
			"the spawn point rests on the plate (spawn bottom %.2f vs plate top %.2f)", spawnBottom, plateTop))

		-- A disabled SpawnLocation is not one the engine will use.
		eq(spawn.Enabled, true, "the world-origin spawn point is ENABLED, so the engine will actually use it")
	end
end

--=========================== the world exists, and REFUSES TO SPEND, while the profile is in flight

do
	local g = h.scheduler:globals()
	local ME = 5150
	local store = h.services.DataStoreService:GetDataStore("NightwatchManor_v1")
	-- A real player, deep into the game: night 9, 900 relics banked. That is the person the two
	-- `prof.loaded` gates exist for.
	store:SetAsync("u_" .. ME, { data = { night = 9, stash = 900, best = 8, levels = {} } })

	local realUpdate = getmetatable(store).UpdateAsync
	local calls = 0
	store.UpdateAsync = function(self, key, fn)
		calls += 1
		g.task.wait(1.0)
		return realUpdate(self, key, fn)
	end

	g.task.spawn(function()
		h:join("Slowpoke", ME)
	end)
	h:advance(0.2) -- less than the round-trip: the server is still inside UpdateAsync

	truthy(calls > 0, "CONTROL: the join really is blocked inside a DataStore call")
	local me = h.Players:GetPlayerByUserId(ME)
	truthy(me ~= nil, "the player is in the game while their profile is still in flight")

	local remotes = h.ReplicatedStorage:FindFirstChild("ManorRemotes")
	local stateRemote = remotes and remotes:FindFirstChild("State")
	local noticeRemote = remotes and remotes:FindFirstChild("Notice")
	truthy(stateRemote ~= nil and noticeRemote ~= nil, "the remotes are up")

	local function lastState()
		local sent = stateRemote:sentTo(me)
		for i = #sent, 1, -1 do
			if type(sent[i].args[1]) == "table" then return sent[i].args[1] end
		end
		return nil
	end
	local function lastNoticeOf(kind)
		local sent = noticeRemote:sentTo(me)
		for i = #sent, 1, -1 do
			local p = sent[i].args[1]
			if type(p) == "table" and p.kind == kind then return p end
		end
		return nil
	end

	local zone = h.workspace:FindFirstChild("Zone_" .. ME)
	truthy(zone ~= nil, "their zone exists WHILE the profile call is still in flight")
	local house = zone and zone:FindFirstChild("Safehouse")
	truthy(house ~= nil, "...with the safehouse already built in it")

	----------------------------------------------------------------- M16: the pad the engine uses
	local pad = house and house:FindFirstChild("SpawnPad")
	truthy(pad ~= nil, "...and a spawn point standing on its floor")
	truthy(pad ~= nil and pad.ClassName == "SpawnLocation", "...which is a real SpawnLocation")
	eq(pad and pad.Enabled, true,
		"...and is ENABLED — Roblox will not respawn anyone at a disabled SpawnLocation, it picks a random one instead")
	eq(me and (me :: any).RespawnLocation, pad, "...and it is exactly this player's RespawnLocation")

	----------------------------------------------------------------- M13: buying is refused, and WHY
	local lantern
	if house then
		for _, d in house:GetChildren() do
			if d:GetAttribute("UpgradeId") == "lanterns" then lantern = d end
		end
	end
	truthy(lantern ~= nil, "their lantern pad is standing too")
	if lantern then
		local props = lantern:FindFirstChild("Props")
		lantern:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
		h:advance(0.1)
		eq(#props:GetChildren(), 0, "pressing a pad before the profile lands builds nothing")
		local denied = lastNoticeOf("DENIED")
		truthy(denied ~= nil, "...and says so rather than failing silently")
		-- THE assertion M13 needed. Without the gate the server falls through to Upgrades.buy
		-- against the DEFAULT profile — stash 0 — and tells a player with 900 relics banked that
		-- they cannot afford 40. Same silence, different lie.
		truthy(denied ~= nil and string.find(tostring(denied.text), "Still opening") ~= nil, string.format(
			"...and what it says is that the safehouse is still opening, not that you are poor (said: %q)",
			tostring(denied and denied.text)))
		truthy(denied == nil or string.find(tostring(denied.text), "You need") == nil,
			"...it must NOT quote a price at somebody whose relics have not loaded yet")
	end

	----------------------------------------------------------------- M11: the night is refused too
	local door = house and house:FindFirstChild("ManorDoor")
	truthy(door ~= nil, "the manor door is standing before the profile lands")
	if door then
		door:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
		h:advance(0.1)
		eq(zone:FindFirstChild("Manor"), nil,
			"pressing the manor door before the profile lands builds NO manor — you do not walk into night 1 on night 9")
		-- No State has been pushed at all yet: the server pushes for the first time only once the
		-- profile lands (Main.server.luau, the `pushState(plr)` at the end of onPlayerAdded), so
		-- there is nothing here to read a phase off. That is deliberate — showing a night-9 player
		-- "NIGHT 1, 0 relics" for a second would be the very confusion these gates exist to stop —
		-- and it is checked below, after the profile has landed.
		eq(lastState(), nil, "...and the HUD has not been told anything misleading in the meantime")
		local denied = lastNoticeOf("DENIED")
		truthy(denied ~= nil and string.find(tostring(denied.text), "Still opening") ~= nil,
			string.format("...and the player is told why (said: %q)", tostring(denied and denied.text)))
	end

	----------------------------------------------------------------- and then it lands
	h:advance(2)
	local s = lastState()
	eq(s and s.stash, 900, "the profile landed with the stash that was really in the DataStore")
	eq(s and s.night, 9, "...and the night they were really on")
	eq(s and s.phase, "DAY", "...and the refused night left the run in the day phase, not half-started")

	store.UpdateAsync = nil -- back to the metatable's own, so nothing below yields

	----------------------------------------------------------------- ...and NOW the door works
	if door then
		door:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
		h:advance(0.5)
		local manor = zone:FindFirstChild("Manor")
		truthy(manor ~= nil, "CONTROL: once the profile has landed the same press DOES build a manor")
		local s2 = lastState()
		eq(s2 and s2.phase, "NIGHT", "...and the run is in the night phase")
		eq(s2 and s2.night, 9, "...on night 9, the night they were really on")

		--------------------------------------------- the way out is not standing in the way in
		if manor then
			local rooms, roomCentres = 0, {}
			for _, c in manor:GetChildren() do
				if string.match(tostring(c.Name), "^Room%d+_") then
					rooms += 1
					local floor = c:FindFirstChild("Floor")
					if floor then table.insert(roomCentres, floor.Position) end
				end
			end
			truthy(rooms > 0, "the manor is made of rooms")
			truthy(rooms <= Config.Manor.MaxRooms, string.format(
				"the built manor is inside Config.Manor.MaxRooms (%d rooms vs %d)", rooms, Config.Manor.MaxRooms))

			local exitDoor = manor:FindFirstChild("ExitDoor")
			truthy(exitDoor ~= nil, "the manor has a way out")
			if exitDoor and #roomCentres > 0 then
				-- Which room is it in, and which way is it facing?
				local best, bestD
				for _, c in roomCentres do
					local d = (c - exitDoor.Position).Magnitude
					if bestD == nil or d < bestD then bestD, best = d, c end
				end
				local off = exitDoor.Position - best
				local fx = if math.abs(off.X) > math.abs(off.Z) then (if off.X > 0 then 1 else -1) else 0
				local fz = if fx == 0 then (if off.Z > 0 then 1 else -1) else 0
				local half = Config.Manor.RoomSize / 2

				-- The gap a doorway leaves is the MIDDLE of the shared edge, below DoorHeight.
				-- The exit door is 10 studs wide and sits 6 studs inside the face, so if that face
				-- has a doorway the slab is planted squarely in it: the only way into the room the
				-- player has to reach. Assert there is solid wall geometry at that exact point.
				local gap = best + Vector3.new(fx * half, Config.Manor.DoorHeight / 2, fz * half)
				local covered = false
				for _, d in manor:GetDescendants() do
					if d:IsA("BasePart") and string.match(tostring(d.Name), "^Wall") then
						local o = gap - d.Position
						if math.abs(o.X) <= d.Size.X / 2 + 0.01
							and math.abs(o.Y) <= d.Size.Y / 2 + 0.01
							and math.abs(o.Z) <= d.Size.Z / 2 + 0.01 then
							covered = true
						end
					end
				end
				truthy(covered, string.format(
					"the exit door has SOLID WALL behind it, not a doorway (face %d,%d)", fx, fz))
			end
		end
	end

	h:leave(me)
	h:advance(1)
	eq(h.workspace:FindFirstChild("Zone_" .. ME), nil, "and leaving took the zone with them")
end

--=========================================================================================== done

print("")
for _, w in h.warnings do
	print("warning: " .. w)
end
eq(#h.warnings, 0, "the server built all of that without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("nightwatch world: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("nightwatch world check failed", 0)
end
