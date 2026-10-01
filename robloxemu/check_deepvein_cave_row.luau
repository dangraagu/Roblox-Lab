-- Deep Vein — the strata row tells the truth and gives way to a warning. Review 2026-09-30, findings 5 and 8.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_cave_row.luau
--
-- Finding 8: the chip counted down to the next stratum even when that stratum starts below the bedrock
-- depth wall. A rebirth-0 miner at the wall read "🍄 in 24 m" while the HUD said "wall 144m": rock that is
-- unbreakable until a rebirth. The chip now says the next stratum comes after a rebirth.
--
-- Finding 5 (the title card): the BandCard sits over the hazard banner on landscape phones (at 800x360 the
-- card spans y 130-172 screen px, the banner 157-192), so a new-stratum card or the magma fanfare shown
-- during a warning was drawn over "MOVE!". A card now waits for the warning to end, and a warning that
-- starts while a card is up sends the card away until it is over. Neither is lost.
--
-- The path is real: a rebirth-2 miner (wall at layer 48) whose best is layer 36, on an 800x360 touch
-- phone, the real server and the real Hud and Cave clients.

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
	viewport = { 800, 360 },
	touch = true,
})

local UID = 5757
local REBIRTHS, BEST, DUG = 2, 36, 47
do
	local Config = require("../deep-vein/src/shared/Config")
	local Mine = require("../deep-vein/src/shared/Mine")
	local w = Mine.world(Config, REBIRTHS, Mine.legacyKey(Config, REBIRTHS))
	local c = Mine.center(Config)
	local dug = {}
	for y = 1, DUG do
		dug[Mine.key(c, y, c)] = true
		dug[Mine.key(c + 1, y, c)] = true -- an open cell beside the column everywhere: hazards can launch
	end
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	store:SetAsync("u_" .. UID, { data = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 4,
		rebirths = REBIRTHS, depthLayer = DUG, bestLayer = BEST,
		openedBits = Mine.packOpened(Config, w, dug),
		caveKey = Mine.legacyKey(Config, w.rebirths),
	} })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Mine = mod("Mine")
local EnvBands = mod("EnvBands")
local bands = Config.Env.Bands
local S = Config.Mine.CellSize

local plr = h:join("Phone", UID)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(2)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
local shaft = nil
for _, f in h.workspace.Shafts:GetChildren() do
	if f:FindFirstChild("SellPad_" .. UID, true) then shaft = f end
end
local origin = shaft:FindFirstChild("DepthWall_" .. UID).Position
local C = Mine.center(Config)
local function standAt(y)
	local lp = Mine.localPos(Config, C, y, C)
	hrp.CFrame = CFrame.new(origin.X + lp.x, Mine.floorY(Config, y) + Config.Env.RootAboveFloor, origin.Z + lp.z)
end

h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okCave, errCave = h:tryRun("client/Cave.client")
truthy(okCave, "Cave.client loads (" .. tostring(errCave) .. ")")
local root = plr.PlayerGui:FindFirstChild("DeepVeinCave").Root
local card, chip, warning = root:FindFirstChild("BandCard"), root:FindFirstChild("BandChip"), root:FindFirstChild("HazardWarning")

local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local UIS = h.game:GetService("UserInputService")
local together = 0 -- frames on which the title card and the hazard banner were both on screen
local cards = {}
local lastCard = ""
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and warning.Visible then together += 1 end
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
	if not card.Visible then lastCard = "" end
end
local clickAcc = 0
local function run(seconds, each)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		clickAcc += 1 / 30
		if clickAcc >= 1 then
			clickAcc = 0
			UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
		end
		frame(1 / 30)
		if hum.PlatformStand then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
		if each and each() == false then return end
	end
end

--======================================================================= finding 8: the chip and the depth wall
local wallLayer = Mine.maxLayer(Config, REBIRTHS)
standAt(30)
run(6) -- the first card of the session comes and goes
local grottoChip = chip.Text
local magma = bands[EnvBands.indexOf(bands, "magma")]
truthy(string.find(grottoChip, magma.emoji .. " in " .. ((magma.from - 30) * S) .. " m", 1, true) ~= nil,
	"in the grotto the chip counts down to the magma, which is above this run's wall (" .. grottoChip .. ")")
--======================================================================= finding 5: a card never covers the warning
-- The miner stands in the grotto, and a hazard is made due quickly (in memory, this run only). While its
-- warning runs, they drop into the magma for the first time this session: its title card is due NOW. (The
-- server credits the restored dig to layer 47 on join, so it is the quiet card here, not the fanfare; the
-- fanfare goes through the same showCard, check_deepvein_cave_join follows it.)
standAt(30)
run(6)
cards = {}
together = 0
local oldMin, oldMax = Config.Hazards.IntervalMin, Config.Hazards.IntervalMax
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 3, 4
local warned = false
run(400, function()
	if warning.Visible then warned = true return false end
end)
truthy(warned, "set-up: a hazard's warning is showing")
standAt(41) -- into the magma: its card is due NOW, mid-warning
local cardDuringWarning = false
run(10, function()
	if warning.Visible and card.Visible then cardDuringWarning = true end
	if not warning.Visible then return false end
end)
truthy(not warning.Visible, "set-up: the warning ran out")
eq(cardDuringWarning, false, "the magma's card is not drawn over the hazard warning")
local function isMagmaCard(text) return string.sub(text, 1, #magma.emoji) == magma.emoji end
local shown = false
run(2, function()
	if card.Visible and isMagmaCard(card.Text) then shown = true return false end
end)
truthy(shown, "…it comes as soon as the warning is over, not lost (cards: " .. table.concat(cards, " | ") .. ")")
-- …and the other order: the card is up, and a warning starts.
local warnedWhileCard = false
run(8, function()
	if warning.Visible then
		warnedWhileCard = true
		return false
	end
end)
truthy(warnedWhileCard, "set-up: a second hazard warned while the magma's card was still up")
run(10, function()
	if not warning.Visible then return false end
end)
local back = false
run(2, function()
	if card.Visible and isMagmaCard(card.Text) then back = true return false end
end)
truthy(back, "…the card steps aside for the warning and comes back after it")
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = oldMin, oldMax
print(string.format("  frames with the title card and the hazard banner both on screen: %d (cards: %s)", together, table.concat(cards, " | ")))
eq(together, 0, "never a frame with the title card over the hazard banner")

--======================================================================= finding 8, at the bottom of the run
standAt(46)
run(6)
local geode = bands[EnvBands.indexOf(bands, "geode")]
truthy(geode.from > wallLayer, "set-up: the stratum after the magma starts below this run's wall (" .. geode.from .. " > " .. wallLayer .. ")")
local wallChip = chip.Text
print("  at layer 46 of a rebirth-2 shaft (wall " .. wallLayer .. "): '" .. wallChip .. "'")
eq(string.find(wallChip, geode.emoji .. " in", 1, true), nil,
	"at the bottom of a run the chip does not count down to a stratum below the depth wall")
-- where the chip has room for its whole text (a desktop window), it says what comes next
h:setTouch(false)
h:setViewport(1280, 720)
run(1)
local wideChip = chip.Text
print("  the same miner on a 1280x720 window: '" .. wideChip .. "'")
eq(string.find(wideChip, geode.emoji .. " in", 1, true), nil, "…nor on a wide window")
truthy(string.find(wideChip, geode.emoji .. " after a ♻️ rebirth", 1, true) ~= nil,
	"…where it says the next stratum comes after a rebirth (" .. wideChip .. ")")

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein cave row: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein cave row check failed", 0)
end
