-- StormGrow — THE PLAYER'S PATH, walked through the real server and all three client scripts.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       cd ../stormgrow && luau tests/walk.luau
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green unit tests are not a working game (this repo once shipped 166 green tests with an unreachable core
-- loop). This file plays: join -> plant -> harvest -> unlock -> hold ripe crops for the forecast -> the
-- storm marks them -> the Almanac -> sell marked crops -> buy a field -> leave -> stay away 5 minutes ->
-- rejoin to a farm that kept growing -> a second loop. It prints what happened, in numbers.
--
-- The player is a "normal" player (Config.Pacing.Profiles.normal, the same one the pacing model uses): a
-- sweep every 15 s, holding ripe crops while the HUD's hint line carries the hold cue, buying the cheapest
-- upgrade it can afford, stepping out of every hazard ring when the banner says MOVE. It acts ONLY through
-- what a player has: mouse clicks on the SCREEN (it walks to a field's working spot, puts the camera behind the
-- character, finds a point of the tile it can see and clicks there; REVIEW-1 B1: until then this file fired the
-- tile it meant straight into the server and could not see a click land on another tile), the buttons of the
-- HUD, and the hazard ring and banner it can see. Nothing is set by hand, the odds are the real ones (Config
-- untouched), and the weather is the real clock's.

local Harness = require("../../robloxemu/emu/harness")
local Aim = require("./Aim")
local Economy = require("../src/shared/Economy")
local Weather = require("../src/shared/Weather")
local Config = require("../src/shared/Config")
local Farm = require("../src/shared/Farm")

local h = Harness.new({ bundle = require("../../robloxemu/build/stormgrow"), name = "stormgrow-walk", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local W, M = Config.Weather, Config.Marks
local UID = 8080

local plr, char, hrp, hum
local root
local t0 = h.scheduler:now()
local function minute() return (h.scheduler:now() - t0) / 60 end
local events = {}
local function log(fmt, ...)
	local line = string.format("%6.2f min  " .. fmt, minute(), ...)
	table.insert(events, line)
end

local clientsLoaded = false
local function join()
	plr = h:join("Walker", UID)
	char = h.Players:simulateSpawn(plr, h.workspace)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Grass
	h.Players.LocalPlayer = plr
	if clientsLoaded then
		-- A rejoin is a NEW client: the old one's frame loop, remote listeners and client-only world are gone
		-- with it in Roblox. The emulator keeps one process, so they are torn down here by hand.
		RunService.RenderStepped:DisconnectAll()
		local uis = h.game:GetService("UserInputService") -- the old client's tap handlers (REVIEW-1)
		uis.TouchTap:DisconnectAll()
		uis.InputBegan:DisconnectAll()
		uis.InputEnded:DisconnectAll()
		local rem = h.ReplicatedStorage.StormRemotes
		rem.Toast.OnClientEvent:DisconnectAll()
		rem.Board.OnClientEvent:DisconnectAll()
		for _, name in { "StormLocalSky", "StormCrops", "StormStrikes" } do
			local f = h.workspace:FindFirstChild(name)
			if f then f:Destroy() end
		end
		local oldBoard = h.workspace.Valley.AlmanacBoard:FindFirstChild("BoardView")
		if oldBoard then oldBoard:Destroy() end
	end
	for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
		local ok, err = h:tryRun(key)
		truthy(ok, key .. " loads (" .. tostring(err) .. ")")
	end
	clientsLoaded = true
	root = plr.PlayerGui.StormHud.Root
end

local dodges, hits = 0, 0
-- the hazard rate a farmer actually sees (REVIEW-1 B2): hazards that STARTED (the banner coming up) and the share of
-- played frames spent in rest, which freezes the hazard clock
local hazardStarts, bannerWas, restFrames, playFrames = 0, false, 0, 0
local function frames(s, dt)
	dt = dt or 0.25
	for _ = 1, math.floor(s / dt + 0.5) do
		cam.CFrame = CFrame.lookAt(hrp.Position + Vector3.new(0, 12, -18), hrp.Position)
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
		local v = hrp.AssemblyLinearVelocity
		if v and v.Magnitude > 1 then
			hits += 1
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
		-- a hazard: when the banner says MOVE, walk out of the red ring
		local ring = h.workspace.StormLocalSky.ValleyArt.Hazard:FindFirstChild("HazardRing")
		local banner = root.HazardBanner
		if banner.Visible and not bannerWas then hazardStarts += 1 end
		bannerWas = banner.Visible
		playFrames += 1
		local rs = plr:GetAttribute("RestState")
		if rs == "idle" or rs == "resting" then restFrames += 1 end
		if ring and ring.Transparency < 1 and banner.Visible and string.find(banner.Text, "MOVE", 1, true) then
			local r = ring.Size.Y / 2
			local away = Vector3.new(hrp.Position.X - ring.Position.X, 0, hrp.Position.Z - ring.Position.Z)
			local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
			if away.Magnitude < r + 0.5 then
				hum.MoveDirection = dir
				hrp.CFrame = CFrame.new(Vector3.new(ring.Position.X, hrp.Position.Y, ring.Position.Z) + dir * (r + 1.5))
				dodges += 1
			end
		else
			hum.MoveDirection = Vector3.new(0, 0, 0)
		end
	end
end

local function myTiles()
	return h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles
end

-- A click the way a player makes it: walk to the field's working spot (field 1: the pad; the others: in front of
-- them), put the camera behind the character and click a point of the tile that is visible there (the crop
-- first, else its soil). The tile that answers (the Tap the client's pick sends) must be the tile aimed at.
local aim = Aim.new(h, { touch = false })
local answered = {}
h.ReplicatedStorage.StormRemotes.Tap.OnServerEvent:Connect(function(_p, slot, key)
	table.insert(answered, { slot = slot, key = key })
end)
local taps, landed, landedElsewhere, unseen, steeper, walkedIn = 0, 0, 0, 0, 0, 0
local wrongTaps = {}
local function tap(hb)
	local slot, key, field = hb:GetAttribute("Farm"), hb:GetAttribute("Key"), hb:GetAttribute("Field")
	local pos, facing = aim:standFor(Farm, Config.Farm, slot, field)
	if (hrp.Position - pos).Magnitude > 1 then
		-- a farmer who just stepped out of a ring waits for the hazard to pass before walking back into it
		local waited = 0
		while root.HazardBanner.Visible and waited < 8 do
			frames(0.25)
			waited += 0.25
		end
		hrp.CFrame = CFrame.new(pos) -- walk there
		frames(0.25)
	end
	table.clear(answered)
	local ok, tried, moved = aim:tapTile(slot, key, hrp.Position, facing, "click", function(pos)
		hrp.CFrame = CFrame.new(pos) -- into the field: the tile is hidden behind taller crops from the working spot
		frames(0.25)
	end)
	if moved then walkedIn += 1 end
	taps += 1
	if not ok then
		unseen += 1
		-- say why, so a failure here can be read: each tried pose, each point of the tile, and what hid it
		local why = {}
		local visible = Aim.within(aim:parts("visible"), hrp.Position, 100)
		for _, pose in { { 35, 12.5 }, { 55, 12.5 }, { 72, 16 } } do
			aim:pose(hrp.Position, facing, pose[1], pose[2])
			local camPos = cam.CFrame.Position
			for i, pt in aim:targetsFor(slot, key) do
				local x, y, onScreen = aim:screenOf(pt)
				local hit = aim:firstVisible(camPos, pt, visible)
				table.insert(why, string.format("pitch %d point %d: %s, first seen %s", pose[1], i,
					if onScreen then "on screen" else string.format("off screen (%.0f, %.0f)", x or -1, y or -1),
					hit and hit:GetFullName() or "nothing"))
			end
		end
		print(string.format("UNSEEN %s (field %d, %s, marks %s) at %.2f min from %s: %s", key, field, tostring(hb:GetAttribute("Crop")),
			tostring(hb:GetAttribute("Marks")), minute(), tostring(hrp.Position), table.concat(why, "; ")))
	else
		if tried > 1 then steeper += 1 end
		local a = answered[1]
		if #answered == 1 and a.slot == slot and a.key == key then
			landed += 1
		else
			landedElsewhere += 1
			if #wrongTaps < 5 then table.insert(wrongTaps, key .. " -> " .. tostring(a and a.key)) end
		end
	end
	frames(0.25) -- ~1 s per tap with the walking and aiming: the normal profile's `tap`
	frames(0.75)
end

local stats = { firstPlant = nil, firstHarvest = nil, firstMark = nil, firstEntry = nil, marksSold = 0, markedValue = 0, purchases = {} }

local function sweep()
	local now = h.workspace:GetAttribute("ServerNow")
	local holdCue = string.find(root.Hint.Text, "can turn", 1, true) ~= nil and root.Hint.Visible
	local running = Weather.at(now, W)
	local tiles = myTiles()
	local fields = plr:GetAttribute("Fields")
	local keys = {}
	for f = 1, fields do
		for t = 1, 9 do table.insert(keys, f .. "_" .. t) end
	end
	for _, key in keys do
		local hb = tiles["Tile_" .. key]
		local crop = hb:GetAttribute("Crop")
		local ripe = crop ~= "" and now >= hb:GetAttribute("PlantedAt") + hb:GetAttribute("Grow") + 0.3
		if crop == "" then
			tap(hb)
			stats.firstPlant = stats.firstPlant or minute()
		elseif ripe then
			local marks = hb:GetAttribute("Marks")
			-- the HUD's rule: hold ripe crops while the hint carries the hold cue, except crops that already
			-- carry the running event's mark (the hint says "Already ...: tap to harvest them now")
			local hasRunning = running ~= "clear" and bit32.band(marks, M[running].bit) ~= 0
			if not holdCue or hasRunning then
				local before = plr:GetAttribute("Coins")
				tap(hb)
				local got = plr:GetAttribute("Coins") - before
				stats.firstHarvest = stats.firstHarvest or minute()
				if marks ~= 0 then
					stats.marksSold += 1
					stats.markedValue += got
				end
			end
		end
	end
	-- buy the cheapest affordable upgrade (the Seeds panel's buttons)
	for _ = 1, 4 do
		local coins = plr:GetAttribute("Coins")
		local p = { fields = plr:GetAttribute("Fields"), unlocked = plr:GetAttribute("Unlocked"), harvested = plr:GetAttribute("Harvested") }
		local fieldPrice = Economy.nextFieldPrice(p, Config)
		local nextCrop = Economy.nextCrop(p, Config)
		local cropPrice = if nextCrop and p.harvested >= (nextCrop.needHarvested or 0) then nextCrop.unlock else nil
		if cropPrice and coins >= cropPrice and (fieldPrice == nil or cropPrice <= fieldPrice) then
			root.Seeds.SeedList["Seed_" .. nextCrop.id].Activated:Fire()
			frames(0.25)
			if plr:GetAttribute("Unlocked") > p.unlocked then
				table.insert(stats.purchases, string.format("%s %.1f", nextCrop.name, minute()))
				log("unlocked %s (%s coins)", nextCrop.name, tostring(cropPrice))
			end
		elseif fieldPrice and coins >= fieldPrice then
			root.Seeds.FieldButton.Activated:Fire()
			frames(0.25)
			if plr:GetAttribute("Fields") > p.fields then
				table.insert(stats.purchases, string.format("field %d %.1f", p.fields + 1, minute()))
				log("bought field %d (%s coins)", p.fields + 1, tostring(fieldPrice))
			end
		else
			break
		end
	end
end

local lastCount, lastBand = 0, ""
local idleFrames = 0
local function watch()
	local count = plr:GetAttribute("AlmanacCount") or 0
	if count > lastCount then
		if lastCount == 0 then stats.firstEntry = stats.firstEntry or minute() end
		log("Almanac %d -> %d", lastCount, count)
		lastCount = count
	end
	for _, hb in myTiles():GetChildren() do
		if (hb:GetAttribute("Marks") or 0) ~= 0 and stats.firstMark == nil then
			stats.firstMark = minute()
			log("first mark: %s on a %s", Config.Variants[hb:GetAttribute("Marks")], hb:GetAttribute("Crop"))
		end
	end
	-- the band the sky is in (the chip shows the rest state instead while resting, so read the attribute)
	local harvested = plr:GetAttribute("Harvested") or 0
	local name = ""
	for _, b in Config.Env.Bands do
		if harvested >= b.from then name = b.emoji .. " " .. b.name end
	end
	if name ~= lastBand then
		log("band: %s (%d harvested)", name, harvested)
		lastBand = name
	end
	if plr:GetAttribute("RestState") == "idle" then idleFrames += 1 end
end

local function play(minutes)
	local untilT = h.scheduler:now() + minutes * 60
	while h.scheduler:now() < untilT do
		sweep()
		watch()
		frames(15) -- the normal profile's check interval
		watch()
	end
end

--============================================================ loop 1

join()
frames(0.5)
log("joined: slot %d, %d coins, hint \"%s\"", plr:GetAttribute("Slot"), plr:GetAttribute("Coins"), root.Hint.Text)
play(12)
local c1 = {
	coins = plr:GetAttribute("Coins"), harvested = plr:GetAttribute("Harvested"), count = plr:GetAttribute("AlmanacCount"),
	fields = plr:GetAttribute("Fields"), unlocked = plr:GetAttribute("Unlocked"), harvests = plr:GetAttribute("Harvests"),
	bits = plr:GetAttribute("AlmanacBits"),
}
log("end of loop 1: %d coins, %d harvested, %d harvests, %d fields, %d crops, Almanac %d", c1.coins, c1.harvested, c1.harvests, c1.fields, c1.unlocked, c1.count)

truthy(stats.firstPlant ~= nil and stats.firstPlant * 60 <= 5, "planted within 5 s of joining")
truthy(c1.unlocked >= 3, "unlocked the Carrot and the Corn in 12 minutes (" .. c1.unlocked .. " crops)")
truthy(c1.fields >= 2, "bought field 2 (" .. c1.fields .. " fields)")
truthy(c1.count >= 1, "found at least one Almanac entry through the real weather and the real odds")
truthy(stats.marksSold >= 1, "sold a marked crop")

-- leave, stay away five minutes, come back
local tiles = myTiles()
local planted = {}
for _, hb in tiles:GetChildren() do
	if hb:GetAttribute("Key") and hb:GetAttribute("Crop") ~= "" then
		planted[hb:GetAttribute("Key")] = { crop = hb:GetAttribute("Crop"), at = hb:GetAttribute("PlantedAt"), marks = hb:GetAttribute("Marks") }
	end
end
h:leave(plr)
h:advance(0.5)
log("left the game")
do
	-- what the leave wrote is exactly the farm as it stood
	local doc = h.services.DataStoreService:GetDataStore("StormGrow_v1"):GetAsync("u_" .. UID)
	local same, n0 = 0, 0
	for key, was in planted do
		n0 += 1
		local t = doc and doc.tiles and doc.tiles[key]
		if t and t.c == was.crop and t.at == was.at and t.m == was.marks then same += 1 end
	end
	eq(same, n0, "the leave saved every planted tile exactly (crop, planting time, marks)")
	eq(doc and doc.session and doc.session.lockUntil, 0, "and released the lock")
end
h:advance(300)
join()
frames(1)
log("rejoined after 5 minutes away: slot %d, %d coins, Almanac %d", plr:GetAttribute("Slot"), plr:GetAttribute("Coins"), plr:GetAttribute("AlmanacCount"))
eq(plr:GetAttribute("Coins"), c1.coins, "the coins came back")
eq(plr:GetAttribute("Harvested"), c1.harvested, "the lifetime harvest came back")
do
	-- Every entry saved is still there. The count may only RISE: a rejoin that lands in a live event can see a strike
	-- grant a new entry in its first second (a 60-phase sweep, 2026-10-01: boot at :13:01 rejoins in the :30 storm,
	-- 2 -> 3), exactly as the marks below may gain a bit. Losing an entry is the defect this guards.
	local bits, kept, had = plr:GetAttribute("AlmanacBits") or "", 0, 0
	for i = 1, #c1.bits do
		if string.sub(c1.bits, i, i) == "1" then
			had += 1
			if string.sub(bits, i, i) == "1" then kept += 1 end
		end
	end
	eq(kept, had, "every Almanac entry came back")
	truthy(plr:GetAttribute("AlmanacCount") >= c1.count, string.format("and the count did not fall (%d -> %d)", c1.count, plr:GetAttribute("AlmanacCount")))
end
local kept, ripeOnReturn, marksKept = 0, 0, 0
local now = h.workspace:GetAttribute("ServerNow")
for key, was in planted do
	local hb = myTiles()["Tile_" .. key]
	if hb:GetAttribute("Crop") == was.crop and hb:GetAttribute("PlantedAt") == was.at then kept += 1 end
	-- marks only ever GAIN bits: if the rejoin lands in a live event, a strike in the first second may add one
	-- (a phase sweep of this file found exactly that at two of ten join phases)
	local now_m = hb:GetAttribute("Marks")
	if bit32.band(now_m, was.marks) == was.marks then marksKept += 1 end
	if now >= hb:GetAttribute("PlantedAt") + hb:GetAttribute("Grow") then ripeOnReturn += 1 end
end
local n = 0
for _ in planted do n += 1 end
eq(kept, n, "every planted tile came back as it was")
eq(marksKept, n, "with its marks (every saved mark still there)")
log("%d of %d crops are ripe on return: they kept growing while the farmer was away", ripeOnReturn, n)
truthy(ripeOnReturn >= n * 0.5, "crops kept growing offline")

--============================================================ loop 2

local coins2 = plr:GetAttribute("Coins")
play(6)
log("end of loop 2: %d coins (+%d), %d harvested, Almanac %d", plr:GetAttribute("Coins"), plr:GetAttribute("Coins") - coins2,
	plr:GetAttribute("Harvested"), plr:GetAttribute("AlmanacCount"))
truthy(plr:GetAttribute("Harvested") > c1.harvested, "the second loop earned more")
-- The standard: about one hazard per 2-3 minutes of normal play. A farmer stands still between sweeps, so an idle
-- rule that rests them after a short wait freezes the hazard clock for much of a normal session (REVIEW-1 B2: 48-55%
-- of samples at IdleSeconds 20, one hazard per ~5.3 min).
local restShare = restFrames / math.max(playFrames, 1)
-- (sweeps of this file over 30 and 60 boot phases, 2026-10-01: 0-18% in rest, 4-6 hazards; the 20 s rule: 44%, 3
-- hazards. The rest share is the discriminator; the hazard count is only a floor, because hazards are drawn 120-180 s
-- apart and the rejoin restarts the clock, so 18 minutes hold 4 to 6 of them either way)
truthy(restShare <= 0.25, string.format("a normal farmer is in rest for %.0f%% of the frames they play (<= 25%%)", restShare * 100))
truthy(hazardStarts >= 3, string.format("and sees %d hazards in 18 minutes of play (>= 3)", hazardStarts))
eq(landedElsewhere, 0, "every click landed on the tile aimed at (" .. table.concat(wrongTaps, ", ") .. ")")
eq(unseen, 0, "every tile the farmer meant to tap was visible and clickable (from its field's working spot, or a step into the field)")
truthy(landed == taps and taps >= 60, string.format("all %d taps were clicks on the screen that landed", taps))

print("")
print("== the walk (normal player, real odds, real clock)")
for _, l in events do print("  " .. l) end
print("")
print(string.format("  first plant %.2f min · first harvest %.2f min · first mark %s · first Almanac entry %s",
	stats.firstPlant or -1, stats.firstHarvest or -1,
	if stats.firstMark then string.format("%.2f min", stats.firstMark) else "none", if stats.firstEntry then string.format("%.2f min", stats.firstEntry) else "none"))
print(string.format("  %d taps · %d marked crops sold for %d coins · %d hazard rings stepped out of, %d hits",
	taps, stats.marksSold, stats.markedValue, dodges, hits))
print(string.format("  clicks on the screen: %d landed on the tile aimed at, %d on another, %d found nothing to click; %d needed a steeper camera, %d a walk into the field",
	landed, landedElsewhere, unseen, steeper, walkedIn))
print("  purchases (minute): " .. table.concat(stats.purchases, " · "))
print(string.format("  sweeps that found the farmer in idle rest: %d; frames in rest %d of %d (%.0f%%); hazards started %d",
	idleFrames, restFrames, playFrames, restFrames / math.max(playFrames, 1) * 100, hazardStarts))

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	if string.find(w, "frame error", 1, true) then failed += 1 end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow walk failed", 0) end
