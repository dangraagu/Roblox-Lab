-- Deep Vein — how often a hazard REALLY comes in ordinary play, through the real server and the real client.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_rarity.luau
--
-- check_deepvein_cave.luau measures the hazard clock where it runs freely: a miner standing still beside
-- an open cell, 8 hazards in 20 minutes. Real digging is not that. A falling rock is only launched when
-- the miner has an open cell beside them to step into (Hazards ctx.canDodge, from the Parts the client
-- can see), and a miner tunnelling down a one-cell column has none; the surface has no hazards at all,
-- and a due hazard there is re-rolled. So this plays the game: check_deepvein_pace.luau's bot (the
-- deepest block it can see first, ore breaking ties; SURFACE + SELL + shop when the bag is full; rebirth
-- the moment it is offered) swings at the server's real ClickDetectors, while Hud.client and Cave.client
-- run frame by frame on the bot's MODELLED human time (Config.Pacing.Profiles.normal: seconds per swing,
-- per new block, per surface trip). Each swing is also a click on the world, as it is for a player, so
-- the client counts the miner as active. The bot never dodges and never rests: every hazard it meets is
-- a near-hit by construction (it is aimed at the miner), and every one it does not walk out of is a hit.
--
-- Resume session 2026-09-24 (EYECANDY.md §3). Headless limits: no physics (a knock is observed as the
-- PlatformStand the client sets; the bot's next swing puts the miner back on a block), nothing renders.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/deep-vein"), name = "deep-vein", viewport = { 1280, 720 }, touch = false })
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local Mine = mod("Mine")
local Strata = mod("Strata")
local bands = Config.Env.Bands
local CELL = Config.Mine.CellSize
local P = Config.Pacing.Profiles.normal
local remotes = RS:FindFirstChild("VeinRemotes")
local StateEvent = remotes:FindFirstChild("State")
local ElevatorEvent = remotes:FindFirstChild("Elevator")
local BuyEvent = remotes:FindFirstChild("Buy")
local RebirthEvent = remotes:FindFirstChild("Rebirth")
local shafts = h.workspace:FindFirstChild("Shafts")
local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local UID = 4002
local function shaftOf()
	for _, f in shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. UID, true) ~= nil then return f end
	end
	return nil
end

local plr = h:join("Rarity", UID)
h:advance(1)
h.Players:simulateSpawn(plr, h.workspace)
h:advance(2)
local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
local hum = plr.Character:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okCave, errCave = h:tryRun("client/Cave.client")
truthy(okCave, "Cave.client loads (" .. tostring(errCave) .. ")")
local folder = h.workspace:FindFirstChild("DeepVeinLocalCave")
local UIS = h.game:GetService("UserInputService")
local cam = h.workspace.CurrentCamera

-- ── the client's frames, on modelled time ─────────────────────────────────────
local DT = 1 / 15
local clock = 0 -- modelled seconds of play
local below = 0 -- …of them below the surface (in a stratum that has hazards)
local openTime = 0 -- …of those with an open cell beside the miner (a hazard may launch)
local openNow = false
local spawns, hits, maxAtOnce = 0, 0, 0
local atSurface = 0
local perBand = {}
local perRun = {}
local runIdx = 1
local gaps = {}
local lastSpawnAt = nil
local shownBefore, standBefore = false, false
local function hazardsShown(): (string?, number)
	local k, n = nil, 0
	local kinds = {}
	for _, d in folder:GetChildren() do
		local m = string.match(d.Name, "^Hazard_(%a+)$")
		if m and not kinds[m] then
			kinds[m] = true
			k = m
			n += 1
		end
	end
	return k, n
end
local function frame()
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	clock += DT
	local layer = Strata.layerAt(Config, Mine, hrp.Position.Y)
	local bi = EnvBands.indexAt(bands, layer)
	if #(bands[bi].hazards or {}) > 0 then
		below += DT
		if openNow then openTime += DT end
	end
	local k, n = hazardsShown()
	maxAtOnce = math.max(maxAtOnce, n)
	if k and not shownBefore then
		spawns += 1
		perRun[runIdx] = (perRun[runIdx] or 0) + 1
		perBand[bands[bi].id] = (perBand[bands[bi].id] or 0) + 1
		if #(bands[bi].hazards or {}) == 0 then atSurface += 1 end
		if lastSpawnAt then table.insert(gaps, clock - lastSpawnAt) end
		lastSpawnAt = clock
	end
	shownBefore = k ~= nil
	if hum.PlatformStand and not standBefore then hits += 1 end
	standBefore = hum.PlatformStand
end
local function play(seconds)
	local n = math.max(1, math.floor(seconds / DT + 0.5))
	for _ = 1, n do frame() end
end

-- Does the miner have an open cell beside them (the client's own rule: a horizontal neighbour inside the
-- ring with no built Part)? Recomputed once per bot action from the shaft the server built.
local function refreshOpen()
	local solid = {}
	local f = shaftOf()
	if f then
		for _, d in f:GetChildren() do
			local key = d:GetAttribute("CellKey")
			if type(key) == "string" then solid[key] = true end
		end
	end
	local origin = f and f:FindFirstChild("DepthWall_" .. UID)
	if origin == nil then openNow = false return end
	local rel = hrp.Position - Vector3.new(origin.Position.X, 0, origin.Position.Z)
	local cx, cz = Strata.cellXZ(Config, rel.X, rel.Z)
	local layer = Strata.layerAt(Config, Mine, hrp.Position.Y)
	openNow = #Strata.openSides(Config, Mine, function(k) return solid[k] == true end, cx, layer, cz) > 0
end

-- ── the bot (check_deepvein_pace's policy), on modelled time ───────────────────
local function trip()
	ElevatorEvent:simulateFireServer(plr, "up")
	openNow = false
	play(P.trip / 2)
	for _, kind in { "pickaxe", "backpack", "lamp" } do
		BuyEvent:simulateFireServer(plr, kind)
	end
	play(P.trip / 2)
end

local LAST_REBIRTH = 5 -- six runs, rebirth 0-5: the first ~2.3 hours of a normal player, river to fossils
local runMinutes = {}
for r = 0, LAST_REBIRTH do
	runIdx = r + 1
	local startClock = clock
	local guard = 0
	while guard < 60000 do
		guard += 1
		local s = stateOf(plr)
		if s.canRebirth then break end
		if s.carried >= s.capacity then
			trip()
			ElevatorEvent:simulateFireServer(plr, "down")
			play(0.4)
		end
		local best, bestScore = nil, -1
		for _, d in shaftOf():GetChildren() do
			if d:IsA("BasePart") and d:GetAttribute("CellKey") ~= nil and d:FindFirstChildOfClass("ClickDetector") then
				local layer = d:GetAttribute("Layer") or 0
				local score = layer * 10 + ((d:GetAttribute("Ore") or 0) > 0 and 5 or 0)
				if score > bestScore then best, bestScore = d, score end
			end
		end
		if best == nil then
			trip()
		else
			-- stand on the block, root settled 3 studs above its top like a real R15 (the block's top is the floor)
			hrp.CFrame = CFrame.new(best.Position + Vector3.new(0, CELL / 2 + 3, 0))
			refreshOpen()
			UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
			best:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
			play(P.swing)
			if best.Parent == nil then
				play(P.block)
			end
		end
	end
	local s = stateOf(plr)
	truthy(s.canRebirth, string.format("rebirth %d: the bot earned it by playing ($%d of $%d)", r, s.earned, s.rebirthCost))
	table.insert(runMinutes, (clock - startClock) / 60)
	RebirthEvent:simulateFireServer(plr)
	play(3)
	hrp = plr.Character:FindFirstChild("HumanoidRootPart")
	hum = plr.Character:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Slate
end

-- ── report ────────────────────────────────────────────────────────────────────
local minutes = clock / 60
local belowMin = below / 60
local perMin = spawns / minutes
local perBelow = if belowMin > 0 then spawns / belowMin else 0
table.sort(gaps)
local median = if #gaps > 0 then gaps[math.ceil(#gaps / 2)] else 0
print(string.format("  %.1f min of normal play (%.1f below the surface, an open cell beside the miner %.0f%% of that)",
	minutes, belowMin, 100 * openTime / math.max(below, 1e-9)))
for i, m in runMinutes do
	print(string.format("    run %d: %4.1f min, %d hazards", i - 1, m, perRun[i] or 0))
end
local byBand = {}
for id, n in perBand do table.insert(byBand, id .. " " .. n) end
table.sort(byBand)
print(string.format("  %d hazards = one per %.1f min of play (%.2f/min), one per %.1f min below the surface; median gap %.1f min, shortest %.1f min",
	spawns, 1 / math.max(perMin, 1e-9), perMin, 1 / math.max(perBelow, 1e-9), median / 60, (gaps[1] or 0) / 60))
print("  by stratum: " .. table.concat(byBand, ", "))
print(string.format("  a bot that ignores every warning: %d hits of %d (every launch is aimed at the miner)", hits, spawns))

truthy(spawns >= 3, "set-up: hazards do come in ordinary digging (" .. spawns .. ")")
eq(maxAtOnce <= 1, true, "never two hazards at once (" .. maxAtOnce .. ")")
eq(atSurface, 0, "none at the surface")
truthy(#gaps == 0 or gaps[1] >= Config.Hazards.IntervalMin - 1,
	string.format("no two hazards closer than IntervalMin of play (shortest %.0f s)", gaps[1] or 0))
truthy(perMin <= 1 / 2, string.format("RARE: in ordinary play no more than one hazard per 2 minutes on average (%.2f/min)", perMin))
-- …but not so rare that the pit rule (no launch without a way out) or a retune quietly switches them off:
-- the owner asked for about one near-hit per 2-3 minutes; ordinary digging measured 0.32-0.35/min.
truthy(perMin >= 1 / 4, string.format("…and they do come: at least one per 4 minutes of ordinary play (%.2f/min)", perMin))
truthy(perBelow <= 1 / 2, string.format("…and none more often than that below the surface either (%.2f/min)", perBelow))

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
for _, wn in h.warnings do print("  [warn] " .. wn) end
print(string.format("deep vein rarity: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein rarity check failed", 0)
end
