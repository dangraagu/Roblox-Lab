-- Deep Vein — the title cards and the brag, through the real server and the real client.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_cave_join.luau
--
-- A new stratum gets a title card when the miner first STANDS in it this session. A stratum deeper than
-- the miner's best EVER (the leaderboard's number) gets the fanfare — "🔥 YOU REACHED THE MAGMA!", a
-- flash — exactly once. That needs the player's saved best, so the first card waits until the profile
-- has loaded (leaderstats), however long the DataStore takes, and says only where the miner is.
--
-- The path is a real one: a rebirth-2 miner whose best is layer 36 (the bottom of their rebirth-1
-- shaft) and who has dug this run's centre column down to 36 joins, rides DESCEND, breaks the next
-- four blocks with real swings on the server's ClickDetectors, and drops into layer 40: the magma.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 1280, 720 },
	touch = false,
})

local UID = 4545
local BEST = 36
do
	local Config = require("../deep-vein/src/shared/Config")
	local Mine = require("../deep-vein/src/shared/Mine")
	local w = Mine.world(Config, 2)
	local c = Mine.center(Config)
	local dug = {}
	for y = 1, BEST do dug[Mine.key(c, y, c)] = true end
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	store:SetAsync("u_" .. UID, { data = {
		cash = 0, totalCash = 90000, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 4,
		rebirths = 2, depthLayer = BEST, bestLayer = BEST,
		openedBits = Mine.packOpened(Config, w, dug),
	} })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Mine = mod("Mine")
local Strata = mod("Strata")
local EnvBands = mod("EnvBands")
local S = Config.Mine.CellSize
local remotes = RS:FindFirstChild("VeinRemotes")

local plr = h:join("Digger", UID)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(2)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate

-- A SLOW PROFILE: hide leaderstats (what the client waits on) for 20 s, as a DataStore queue would.
local stats = plr:FindFirstChild("leaderstats")
truthy(stats ~= nil, "set-up: the server made leaderstats")
stats.Parent = nil

h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okCave, errCave = h:tryRun("client/Cave.client")
truthy(okCave, "Cave.client loads (" .. tostring(errCave) .. ")")
local gui = plr.PlayerGui:FindFirstChild("DeepVeinCave")
local card = gui.Root:FindFirstChild("BandCard")
local chip = gui.Root:FindFirstChild("BandChip")

local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local announced = {}
local lastCard = ""
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(announced, card.Text)
	end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			table.insert(announced, "<flash>")
		end
	end
end
local function run(seconds, each)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		frame(1 / 30)
		if each and each() == false then return end
	end
end

--======================================================================= the first card waits for the profile

run(5)
truthy(string.find(chip.Text, "Topsoil", 1, true) ~= nil, "the chip already works: the sky follows the miner from the first frame (" .. chip.Text .. ")")
run(15)
eq(#announced, 0, "while the profile is still loading (20 s), no card at all (the best depth is not known yet)")
stats.Parent = plr
run(3)
eq(announced[1], "🌱 TOPSOIL & ROOTS", "once it loads, one quiet card says where the miner is")
eq(#announced, 1, "and nothing else")

--======================================================================= DESCEND: a known stratum, quietly

remotes.Elevator:simulateFireServer(plr, "down")
run(4)
local layer = Strata.layerAt(Config, Mine, hrp.Position.Y)
eq(layer, BEST, "set-up: DESCEND put the miner at the bottom of this run's dig (layer " .. layer .. ")")
local grotto = Config.Env.Bands[EnvBands.indexAt(Config.Env.Bands, BEST)]
eq(announced[#announced], grotto.emoji .. " " .. string.upper(grotto.name), "standing in a stratum they have seen before: a quiet card")
for _, t in announced do
	truthy(t ~= "<flash>", "no fanfare for a stratum above their best (" .. t .. ")")
end

--======================================================================= dig into the magma: the fanfare, once

local shaft = nil
for _, f in h.workspace.Shafts:GetChildren() do
	if f:FindFirstChild("SellPad_" .. UID, true) then shaft = f end
end
local c = Mine.center(Config)
local function blockAt(key)
	for _, d in shaft:GetChildren() do
		if d:GetAttribute("CellKey") == key then return d end
	end
	return nil
end
local swings = 0
for y = BEST + 1, 40 do
	local b = blockAt(Mine.key(c, y, c))
	truthy(b ~= nil, "the block under the miner at layer " .. y .. " is built")
	if b then
		local cd = b:FindFirstChildOfClass("ClickDetector")
		for _ = 1, 12 do
			if b.Parent == nil then break end
			cd.MouseClick:Fire(plr)
			swings += 1
			run(0.35)
		end
		truthy(b.Parent == nil, "…and a Singularity Bore breaks it")
		-- the miner drops into the hole they just dug
		local lp = Mine.localPos(Config, c, y, c)
		local origin = shaft:FindFirstChild("DepthWall_" .. UID).Position
		hrp.CFrame = CFrame.new(origin.X + lp.x, Mine.floorY(Config, y) + Config.Env.RootAboveFloor, origin.Z + lp.z)
		run(1)
	end
end
local magma = Config.Env.Bands[EnvBands.indexOf(Config.Env.Bands, "magma")]
local sawFanfare, flashAfter = false, false
for _, t in announced do
	if t == magma.emoji .. " YOU REACHED " .. magma.reached .. "!" then sawFanfare = true end
	if sawFanfare and t == "<flash>" then flashAfter = true end
end
truthy(sawFanfare, "digging into layer 40 for the first time ever: \"" .. magma.emoji .. " YOU REACHED " .. magma.reached .. "!\" ("
	.. table.concat(announced, " | ") .. ")")
truthy(flashAfter, "…with the flash")
eq(plr.leaderstats.Depth.Value, 40 * S, "and the server credits the new best (the leaderboard's number)")

-- up and back down: the same session never celebrates twice
local before = #announced
remotes.Elevator:simulateFireServer(plr, "up")
run(4)
remotes.Elevator:simulateFireServer(plr, "down")
run(4)
local again = false
for i = before + 1, #announced do
	if announced[i] == "<flash>" or string.find(announced[i], "YOU REACHED", 1, true) then again = true end
end
eq(again, false, "riding up and back down does not play the fanfare again")

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print("  cards: " .. table.concat(announced, " | "))
print(string.format("deep vein cave join: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein cave join check failed", 0)
end
