-- +1 Jump Every Step — a climber who reached space in an earlier session, then rebirthed, is not told
-- "YOU REACHED SPACE!" again when they climb back up.
-- Run: luau check_plus1jump_bestseed.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Second review, night of 2026-09-27 (LOW finding 2, docs/night-queue.md "H. Eye-candy - plus1-jump"): the
-- first title card of a session seeds the band announcer, so bands a player has already reached are not
-- announced again. It was seeded from leaderstats Tier, which is the FRONTIER (where they stand now, reset to
-- 0 by a rebirth), not the best tier ever. A space climber who rebirthed and came back got the full-screen
-- flash, the FOV punch and "YOU REACHED SPACE!" a second time. Inside one session that never happened: the
-- announcer remembers. The seed now also counts the best tier the server has saved (Player attribute
-- BestTier, public: it is on the HUD and the top-10 board already).
--
-- Same set-up as check_plus1jump_slowload: the real server with a real (emulated) DataStore save, the real
-- client scripts, one player per scenario.

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
	-- reached tier 90 (space) earlier, rebirthed, now back on tier 3
	[731] = { frontierTier = 3, frontierIdx = 2, jumpPower = 14, rebirths = 1, bestTier = 90 },
	-- the same, with a 16 s profile load
	[732] = { frontierTier = 3, frontierIdx = 2, jumpPower = 14, rebirths = 1, bestTier = 90 },
	-- the control: rebirthed at the edge of space (best 84), never reached it
	[733] = { frontierTier = 3, frontierIdx = 2, jumpPower = 14, rebirths = 1, bestTier = 84 },
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
local spaceFrom = bands[EnvBands.indexOf(bands, Config.Env.SpaceBandId)].from
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local previous = nil
local function join(uid, seconds, climbAfter)
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
	local climbed = false
	local watch = climbAfter + 8
	for i = 1, math.floor(watch * 30 + 0.5) do
		if not climbed and i / 30 >= climbAfter then
			climbed = true
			-- they climb back up and land on the first platform of the space tier
			hrp.CFrame = CFrame.new(hrp.Position.X, Progression.yAtProgress(spaceFrom - 1 + 1 / Config.Tower.TilesPerTier, Config.Tower) + 3.5, hrp.Position.Z)
		end
		cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
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
	return { cards = cards, flashes = flashes, hrp = hrp }
end

local function has(list, text)
	for _, t in list do
		if string.find(t, text, 1, true) then return true end
	end
	return false
end

for _, case in { { 731, 0.1, "space climber who rebirthed, fast load" }, { 732, 16.0, "space climber who rebirthed, 16 s load" } } do
	local uid, seconds, label = case[1], case[2], case[3]
	local r = join(uid, seconds, seconds + 5)
	print(string.format("  %-44s cards: %s; flashes %d", label, table.concat(r.cards, " | "), r.flashes))
	truthy(r.hrp.Position.Y > Progression.yAtProgress(spaceFrom - 1, Config.Tower), label .. ": set-up: they climbed back into space")
	truthy(has(r.cards, "TEMPLE"), label .. ": the first card says where they are now (the temple, tier 3)")
	eq(has(r.cards, "YOU REACHED SPACE"), false, label .. ": no second 'YOU REACHED SPACE!' for a climb finished in an earlier session")
	eq(r.flashes, 0, label .. ": no celebration flash")
end

do
	local r = join(733, 0.1, 5)
	local label = "rebirthed at tier 84, never reached space"
	print(string.format("  %-44s cards: %s; flashes %d", label, table.concat(r.cards, " | "), r.flashes))
	truthy(has(r.cards, "YOU REACHED SPACE"), label .. ": reaching space for the first time IS celebrated")
	eq(r.flashes, 1, label .. ": one flash")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump bestseed: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump bestseed check failed", 0)
end
