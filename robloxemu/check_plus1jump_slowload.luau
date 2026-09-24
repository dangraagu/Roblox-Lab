-- +1 Jump Every Step — a VERY slow profile load, or a placement that arrives very late, never shows a
-- returning space climber a TEMPLE card followed by a repeat "YOU REACHED SPACE!".
-- Run: luau check_plus1jump_slowload.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17, round 2 (finding 3, low): Sky.client's first title card waits for the profile to load
-- (leaderstats) and for the server's placement, with a 15 s timeout. The timeout counted from the moment the
-- character appeared, whether or not the profile had loaded. Measured: a 14 s load gave one quiet
-- "SPACE · LOW ORBIT" card; a 16 s load gave "TEMPLE GROUNDS", then a full-screen flash, an FOV punch and
-- "YOU REACHED SPACE!" for a climb finished in an earlier session. check_plus1jump_join only went to 6 s.
-- DataStore UpdateAsync has no upper bound on how long it queues when throttled.
--
-- Same set-up as check_plus1jump_join: UpdateAsync itself yields, the character spawns on the pad
-- meanwhile, the server places it when the load returns. One Harness per process, so the scenarios join
-- different players in turn, each with a fresh copy of the client scripts.

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

local SAVES = {
	[711] = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90 },
	[712] = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90 },
	[713] = { frontierTier = 84, frontierIdx = 6, jumpPower = 504, rebirths = 0, bestTier = 84 },
	[714] = { frontierTier = 90, frontierIdx = 3, jumpPower = 540, rebirths = 0, bestTier = 90 },
}
for uid, d in SAVES do
	d.redeemed, d.passes = {}, {}
	store:SetAsync("u_" .. uid, { data = d })
end

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

local previous = nil
local function join(uid, seconds, watch, afterPlaced, beforeFrame)
	if previous then
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
		if beforeFrame then beforeFrame(hrp, 1 / 30) end
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

-- (1) returning space climbers, loads longer than the old 15 s timeout
for _, case in { { 711, 16.0 }, { 712, 40.0 } } do
	local uid, seconds = case[1], case[2]
	local r = join(uid, seconds, seconds + 6)
	local label = string.format("space climber, profile load %.0f s", seconds)
	print(string.format("  %-40s placed after %s s; cards: %s; flashes %d", label, tostring(r.placedAt),
		table.concat(r.cards, " | "), r.flashes))
	truthy(r.placedAt ~= nil and r.placedAt >= seconds - 0.1, label .. ": set-up: the server placed them only after the load")
	eq(has(r.cards, "TEMPLE"), false, label .. ": no TEMPLE GROUNDS card while they wait on the pad")
	eq(has(r.cards, "YOU REACHED SPACE"), false, label .. ": no 'YOU REACHED SPACE!' for a climb finished in an earlier session")
	eq(r.flashes, 0, label .. ": no celebration flash")
	eq(#r.cards, 1, label .. ": exactly one card")
	truthy(has(r.cards, string.upper(orbit.name)), label .. ": and it says where they are (" .. orbit.name .. ")")
end

-- (2) the profile loads at once but the placement reaches this client 20 s late (past the 15 s timeout):
-- every frame the client draws, for 20 s after the server placed them, the character still stands on the
-- pad (the server's own rescue teleports included), then the placement arrives
do
	local placedCF, held, released = nil, 0, false
	local r = join(714, 0.1, 30, function(hrp)
		placedCF = hrp.CFrame
	end, function(hrp, dt)
		if placedCF == nil or released then return end
		held += dt
		if held < 20 then
			hrp.CFrame = CFrame.new(0, Config.Tower.BaseY + 4, 0)
		else
			released = true
			hrp.CFrame = placedCF
		end
	end)
	print(string.format("  %-40s cards: %s; flashes %d", "space climber, placement 20 s late", table.concat(r.cards, " | "), r.flashes))
	truthy(r.hrp.Position.Y > Progression.yAtProgress(89, Config.Tower), "placement 20 s late: set-up: they did end up on their platform")
	eq(has(r.cards, "YOU REACHED SPACE"), false, "placement 20 s late: no 'YOU REACHED SPACE!' when the late placement arrives")
	eq(r.flashes, 0, "placement 20 s late: no celebration flash")
end

-- (3) the fix must not cost a climber the fanfare they have NOT had: an edge-of-space climber with a
-- 16 s load who climbs into space after being placed is celebrated
do
	local r = join(713, 16.0, 24, function(hrp)
		task.delay(3.5, function()
			hrp.CFrame = CFrame.new(hrp.Position.X, Progression.yAtProgress(84 + 1 / Config.Tower.TilesPerTier, Config.Tower) + 3.5, hrp.Position.Z)
		end)
	end)
	print(string.format("  %-40s placed after %s s; cards: %s; flashes %d", "edge climber, load 16 s, climbs on",
		tostring(r.placedAt), table.concat(r.cards, " | "), r.flashes))
	eq(has(r.cards, "TEMPLE"), false, "edge climber, load 16 s: no TEMPLE card while waiting on the pad")
	truthy(has(r.cards, "EDGE OF SPACE"), "edge climber, load 16 s: a quiet card says where they are")
	truthy(has(r.cards, "YOU REACHED SPACE"), "edge climber, load 16 s: climbing into space during play IS celebrated")
	eq(r.flashes, 1, "edge climber, load 16 s: one flash")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump slowload: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump slowload check failed", 0)
end
