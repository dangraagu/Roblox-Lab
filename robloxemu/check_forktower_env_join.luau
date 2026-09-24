-- Fork Tower — the environment's first title card at a JOIN, including a slow profile load.
-- Run: luau check_forktower_env_join.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- Ambience.client says where the player is with one quiet title card once their profile has LOADED
-- (leaderstats) and their lane exists, and then a card for each new band reached. Before the lane
-- exists the client cannot know the floor, so a card shown then names floor 1's band (the dungeon):
-- a returning floor-7 climber would be told "FANGEHULLET" and then, when the load lands, "STORMEN".
-- +1 Jump shipped exactly that shape of defect past a 15 s timeout (review 2026-09-17 round 2,
-- check_plus1jump_slowload.luau). DataStore UpdateAsync has no upper bound on how long it queues.
--
-- check_forktower_env joins a FRESH player whose load is instant, so it cannot tell a card that waits
-- for the profile from one that does not. This file can: the saves are made by really playing (each
-- climber reads and takes the safe door up six floors, then leaves, and the server's own releasing
-- write is what the rejoin loads), then the server's UpdateAsync is made to yield on the rejoin.
--
-- Headless: frames are driven by firing RunService.RenderStepped. One Harness per process, so the
-- scenarios join players in turn, each with fresh copies of the client scripts; a card lives in that
-- player's own PlayerGui, so each scenario only looks at its own.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001 -- in memory: nothing flies here
local bands = Config.Env.Bands
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)

-- the rejoin's load yields this long (the first UpdateAsync on that key after it is armed)
local armed = {}
local realUpdate = store.UpdateAsync
store.UpdateAsync = function(self, key, fn)
	local wait = armed[key]
	if wait then
		armed[key] = nil
		h.scheduler:wait(wait)
	end
	return realUpdate(self, key, fn)
end

local RETURN_FLOOR = 7
local stormBand = bands[EnvBands.indexAt(bands, RETURN_FLOOR - 1)]
local firstBand = bands[1]
truthy(stormBand ~= firstBand, "set-up: floor " .. RETURN_FLOOR .. " is not in the first band (" .. stormBand.id .. ")")

local function laneOf(plr)
	for _, f in h.workspace:FindFirstChild("Towers"):GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end

--======================================================================= 1. real saves at floor 7

-- Server only: no client script runs for these climbers.
local function climbTo(uid, floor)
	local plr = h:join("Saver" .. uid, uid)
	h:advance(1)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local lane = laneOf(plr)
	for level = 1, floor - 1 do
		local fork = lane:FindFirstChild("Fork_" .. level)
		local pad = fork:FindFirstChild("ForkPad_" .. level)
		hrp.CFrame = CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0))
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		prompt.PromptButtonHoldBegan:Fire(plr)
		h:advance(Config.Fork.ReadSeconds + 0.05)
		prompt.Triggered:Fire(plr)
		h:advance(0.2)
		local d1 = fork:FindFirstChild("Door_" .. level .. "_1")
		local marked = if d1:GetAttribute("Marked") == true then 1 else 2
		local trap = if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
		fork:FindFirstChild("Door_" .. level .. "_" .. (3 - trap)):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
		h:advance(0.3)
		local sec = lane:FindFirstChild("Section_" .. level)
		for _, c in sec:GetChildren() do
			if c:GetAttribute("Exit") == true then
				hrp.CFrame = CFrame.new(c.Position + Vector3.new(0, c.Size.Y / 2 + 3, 0))
				c.Touched:Fire(hrp)
			end
		end
		h:advance(0.3)
	end
	local reached = plr.leaderstats.Floor.Value
	h:leave(plr) -- the server's releasing write: what the rejoin loads
	char:Destroy()
	h:advance(1)
	return reached
end

local SAVED = { 7101, 7102, 7103 }
for _, uid in SAVED do
	eq(climbTo(uid, RETURN_FLOOR), RETURN_FLOOR, "set-up: climber " .. uid .. " reached floor " .. RETURN_FLOOR .. " before leaving")
	local rec = store:GetAsync("u_" .. uid)
	eq(rec and rec.data and rec.data.level, RETURN_FLOOR, "set-up: their saved record is at floor " .. RETURN_FLOOR)
end

--======================================================================= 2. the rejoins

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local function rejoin(uid, loadSeconds, watch)
	armed["u_" .. uid] = loadSeconds
	h.scheduler:spawn(function()
		h.Players:simulateJoin("P" .. uid, uid)
	end)
	local plr = h.Players:FindFirstChild("P" .. uid)
	local pg = h.instance.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = plr
	h.Players.LocalPlayer = plr
	assert(h:tryRun("client/Hud.client"))
	local ok, err = h:tryRun("client/Ambience.client")
	truthy(ok, "Ambience.client loads for P" .. uid .. " (" .. tostring(err) .. ")")
	local char = h.Players:simulateSpawn(plr, h.workspace)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
	hum.MoveDirection = Vector3.new(1, 0, 0) -- never idles into rest
	local cam = h.workspace.CurrentCamera
	local row = plr.PlayerGui:FindFirstChild("ForkHud"):FindFirstChild("Root"):FindFirstChild("AmbienceRow")
	-- the card and its line sit in the HUD's card slot under the row (review 2026-09-24), hence recursive
	local card, sub, chip = row:FindFirstChild("BandCard", true), row:FindFirstChild("BandCardSub", true), row.ChipSlot:FindFirstChild("BandChip")
	local cards, last = {}, ""
	local loadedAt = nil
	for i = 1, math.floor(watch * 30 + 0.5) do
		cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 9, -22), hrp.Position)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		if loadedAt == nil and plr:FindFirstChild("leaderstats") then loadedAt = i / 30 end
		if card.Visible then
			local text = card.Text .. " / " .. sub.Text
			if text ~= last then
				last = text
				table.insert(cards, { text = text, at = i / 30 })
			end
		end
	end
	local floorNow = plr:FindFirstChild("leaderstats") and plr.leaderstats.Floor.Value
	local r = { cards = cards, loadedAt = loadedAt, floor = floorNow, chip = chip.Text }
	h:leave(plr)
	char:Destroy()
	h:advance(0.5)
	return r
end

local function texts(r)
	local out = {}
	for _, c in r.cards do out[#out + 1] = string.format("%s @%.1fs", c.text, c.at) end
	return table.concat(out, " | ")
end
local function any(r, needle)
	for _, c in r.cards do
		if string.find(c.text, needle, 1, true) then return true end
	end
	return false
end

-- (a) returning floor-7 climbers: a slow load, a very slow load, and an ordinary one
for i, seconds in { 16, 40, 0.1 } do
	local uid = SAVED[i]
	local r = rejoin(uid, seconds, seconds + 6)
	local label = string.format("floor-%d climber, profile load %.1f s", RETURN_FLOOR, seconds)
	print(string.format("  %-36s loaded after %s s; cards: %s", label, tostring(r.loadedAt), texts(r)))
	truthy(r.loadedAt ~= nil and r.loadedAt >= seconds - 0.05, label .. ": set-up: the profile loaded only after the wait")
	eq(r.floor, RETURN_FLOOR, label .. ": set-up: the server put them back on floor " .. RETURN_FLOOR)
	eq(any(r, string.upper(firstBand.name)), false, label .. ": no " .. string.upper(firstBand.name) .. " card while the profile loads")
	eq(#r.cards, 1, label .. ": exactly one card")
	truthy(any(r, string.upper(stormBand.name)) and any(r, "etasje " .. RETURN_FLOOR),
		label .. ": and it says where they are (" .. stormBand.name .. ", etasje " .. RETURN_FLOOR .. ")")
	truthy(r.cards[1] == nil or r.cards[1].at >= r.loadedAt, label .. ": the card came after the load, not before it")
	truthy(string.find(r.chip, stormBand.name, 1, true) ~= nil, label .. ": the chip names " .. stormBand.name .. " (" .. r.chip .. ")")
end

-- (b) a new player with a slow load still gets their card: the wait is for the load, not for a floor
do
	local r = rejoin(7104, 16, 22)
	local label = "new player, profile load 16 s"
	print(string.format("  %-36s loaded after %s s; cards: %s", label, tostring(r.loadedAt), texts(r)))
	eq(r.floor, 1, label .. ": set-up: floor 1")
	eq(#r.cards, 1, label .. ": exactly one card")
	truthy(any(r, string.upper(firstBand.name)) and any(r, "etasje 1"), label .. ": it says " .. firstBand.name .. ", etasje 1")
	truthy(r.cards[1] ~= nil and r.cards[1].at >= r.loadedAt, label .. ": after the load")
end

eq(#h:errors(), 0, "no script errors (" .. table.concat(h:errors(), " | ") .. ")")
print(string.format("fork tower env join: %d passed, %d failed", passed, failed))
if failed > 0 then error("fork tower env join check failed", 0) end
