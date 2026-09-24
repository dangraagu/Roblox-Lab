-- +1 Jump Every Step — joining while the profile loads slowly. Run: luau check_plus1jump_join.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17 (finding 3): Sky.client waited a FIXED 1.5 s after the character appeared before
-- its first title card. The server only moves a returning player to their platform after
-- loadProfile's DataStore UpdateAsync returns (Main.server.luau onPlayerAdded -> onCharacter). A slow or
-- throttled load leaves the character standing on the temple pad longer than 1.5 s, so a player who
-- reached space days ago got a TEMPLE GROUNDS card, then a full-screen flash and "YOU REACHED SPACE!".
--
-- This file makes the load slow the way it is slow in Roblox: UpdateAsync itself yields, the character
-- spawns on the pad meanwhile (CharacterAutoLoads), and the server places it when the load returns.
-- The emulator allows one Harness per process, so the scenarios share one server and join different
-- players in turn, each with its own load time and a fresh copy of the client scripts.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local store = h.services.DataStoreService:GetDataStore("Plus1Jump_v1")

-- players and their saves: two space climbers, one who has only reached the edge of space, one new
local SAVES = {
	[701] = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90 },
	[702] = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90 },
	[703] = { frontierTier = 84, frontierIdx = 6, jumpPower = 504, rebirths = 0, bestTier = 84 },
}
for uid, d in SAVES do
	d.redeemed, d.passes = {}, {}
	store:SetAsync("u_" .. uid, { data = d })
end

-- UpdateAsync yields for the load time of whichever player is loading (the first call per key only:
-- later calls are autosaves)
local loadSeconds = {}
local loadedOnce = {}
local realUpdate = store.UpdateAsync
store.UpdateAsync = function(self, key, fn)
	local wait = loadSeconds[key]
	if wait and not loadedOnce[key] then
		loadedOnce[key] = true
		h.scheduler:wait(wait)
	end
	return realUpdate(self, key, fn)
end

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local Progression = h:_require(RS:FindFirstChild("Progression"))
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001
local bands = Config.Env.Bands
local orbit = bands[EnvBands.indexOf(bands, Config.Env.SpaceBandId)]
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

-- A player joins; the load takes `seconds`; the client scripts start at join (PlayerScripts run before
-- the character exists) and the character spawns on the pad at once. Returns the cards and flashes the
-- player saw in the first `watch` seconds, with the player's root part.
-- Each join replaces the previous player's client (one LocalPlayer per process): the previous player
-- leaves first.
local previous = nil
local function join(uid, seconds, watch, afterPlaced)
	if previous then
		-- the previous player's client keeps its RenderStepped connection in this process; with its
		-- character gone it only blends lighting and announces nothing (it returns before the cards)
		local oldChar = previous.Character
		h:leave(previous)
		if oldChar then oldChar:Destroy() end
		h:advance(0.1)
	end
	loadSeconds["u_" .. uid] = seconds
	h.scheduler:spawn(function()
		h.Players:simulateJoin("P" .. uid, uid)
	end)
	local plr = h.Players:FindFirstChild("P" .. uid)
	local pg = h.instance.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = plr
	h.Players.LocalPlayer = plr
	previous = plr
	assert(h:tryRun("client/Hud.client"))
	local ok, err = h:tryRun("client/Sky.client")
	truthy(ok, "Sky.client loads for P" .. uid .. " (" .. tostring(err) .. ")")
	local char = h.Players:simulateSpawn(plr, h.workspace)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
	hum.MoveDirection = Vector3.new(1, 0, 0)
	local cam = h.workspace.CurrentCamera
	local card = plr.PlayerGui:FindFirstChild("Plus1Sky"):FindFirstChild("Root"):FindFirstChild("BandCard")
	local cards, flashes, last = {}, 0, ""
	local placedAt = nil
	local startY = hrp.Position.Y
	for i = 1, math.floor(watch * 30 + 0.5) do
		cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		if placedAt == nil and math.abs(hrp.Position.Y - startY) > 50 then
			placedAt = i / 30
			if afterPlaced then afterPlaced(hrp, hum) end
		end
		if card.Visible and card.Text ~= last then
			last = card.Text
			table.insert(cards, card.Text)
		end
		for _, g in plr.PlayerGui:GetChildren() do
			if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
				g:SetAttribute("__counted", true)
				flashes += 1
			end
		end
	end
	return { cards = cards, flashes = flashes, placedAt = placedAt, hrp = hrp }
end

local function has(list, text)
	for _, t in list do
		if string.find(t, text, 1, true) then return true end
	end
	return false
end

-- (1) returning space climbers, fast and slow loads
for _, case in { { 701, 0.2 }, { 702, 6.0 } } do
	local uid, seconds = case[1], case[2]
	local r = join(uid, seconds, seconds + 6)
	local label = string.format("space climber, profile load %.1f s", seconds)
	print(string.format("  %-36s placed after %s s; cards: %s; flashes %d", label, tostring(r.placedAt),
		table.concat(r.cards, " | "), r.flashes))
	truthy(r.placedAt ~= nil and r.placedAt >= seconds - 0.1, label .. ": set-up: the server placed them only after the load")
	eq(has(r.cards, "TEMPLE"), false, label .. ": no TEMPLE GROUNDS card while they wait on the pad")
	eq(has(r.cards, "YOU REACHED SPACE"), false, label .. ": no 'YOU REACHED SPACE!' for a climb finished in an earlier session")
	eq(r.flashes, 0, label .. ": no celebration flash")
	eq(#r.cards, 1, label .. ": exactly one card")
	truthy(has(r.cards, string.upper(orbit.name)), label .. ": and it says where they are (" .. orbit.name .. ")")
end

-- (2) a climber who has only reached P_84_6: a slow load must not cost them the fanfare they have not had
do
	local r = join(703, 4.0, 10, function(hrp, hum)
		-- they climb on as soon as they are placed: landing on tier 85
		task.delay(3.5, function()
			hrp.CFrame = CFrame.new(hrp.Position.X, Progression.yAtProgress(84 + 1 / Config.Tower.TilesPerTier, Config.Tower) + 3.5, hrp.Position.Z)
		end)
	end)
	print(string.format("  %-36s placed after %s s; cards: %s; flashes %d", "edge climber, load 4.0 s, climbs on",
		tostring(r.placedAt), table.concat(r.cards, " | "), r.flashes))
	eq(has(r.cards, "TEMPLE"), false, "edge climber: no TEMPLE card while waiting on the pad")
	truthy(has(r.cards, "EDGE OF SPACE"), "edge climber: a quiet card says where they are")
	truthy(has(r.cards, "YOU REACHED SPACE"), "edge climber: climbing into space during play IS celebrated")
	eq(r.flashes, 1, "edge climber: one flash")
end

-- (2b) the profile has loaded but the placement reaches this client late (a lagging connection): the
-- reviewer's probe held the character on the pad for N seconds after the server placed it
do
	store:SetAsync("u_705", { data = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90, redeemed = {}, passes = {} } })
	local held = 0
	local r = join(705, 0.1, 9, function(hrp)
		local placed = hrp.CFrame
		local conn
		conn = h.game:GetService("RunService").RenderStepped:Connect(function(dt)
			held += dt
			if held < 3 then
				hrp.CFrame = CFrame.new(0, Config.Tower.BaseY + 4, 0)
			else
				hrp.CFrame = placed
				conn:Disconnect()
			end
		end)
	end)
	print(string.format("  %-36s cards: %s; flashes %d", "space climber, placement 3 s late", table.concat(r.cards, " | "), r.flashes))
	eq(has(r.cards, "TEMPLE"), false, "placement 3 s late: no TEMPLE card")
	eq(r.flashes, 0, "placement 3 s late: no fanfare flash")
	eq(#r.cards, 1, "placement 3 s late: exactly one card")
	truthy(has(r.cards, string.upper(orbit.name)), "placement 3 s late: it says where they are")
end

-- (2c) replication order: the leaderstats folder reaches the client with Tier still 0, and the real value
-- and the placement follow a moment later
do
	store:SetAsync("u_706", { data = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90, redeemed = {}, passes = {} } })
	local r = join(706, 1.0, 9, function(hrp)
		local placed = hrp.CFrame
		local stats = h.Players:FindFirstChild("P706"):FindFirstChild("leaderstats")
		local tierValue = stats:FindFirstChild("Tier")
		local real = tierValue.Value
		local t = 0
		local conn
		conn = h.game:GetService("RunService").RenderStepped:Connect(function(dt)
			t += dt
			if t < 1.0 then
				tierValue.Value = 0
				hrp.CFrame = CFrame.new(0, Config.Tower.BaseY + 4, 0)
			else
				tierValue.Value = real
				hrp.CFrame = placed
				conn:Disconnect()
			end
		end)
	end)
	print(string.format("  %-36s cards: %s; flashes %d", "space climber, Tier replicates 1 s late", table.concat(r.cards, " | "), r.flashes))
	eq(has(r.cards, "TEMPLE"), false, "Tier value 1 s behind its folder: no TEMPLE card")
	eq(r.flashes, 0, "Tier value 1 s behind its folder: no fanfare flash")
	eq(#r.cards, 1, "Tier value 1 s behind its folder: exactly one card")
end

-- (3) a new player with a slow load still gets the temple card
do
	local r = join(704, 3.0, 8)
	print(string.format("  %-36s cards: %s; flashes %d", "new player, load 3.0 s", table.concat(r.cards, " | "), r.flashes))
	truthy(has(r.cards, "TEMPLE"), "a new player gets the TEMPLE GROUNDS card once their (empty) profile has loaded")
	eq(#r.cards, 1, "exactly one card")
	eq(r.flashes, 0, "no flash")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump join: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump join check failed", 0)
end
