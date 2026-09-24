-- Grow a Crystal — a RETURNING player: quiet, correct, and never a replayed fanfare or burst.
-- Run: luau check_growacrystal_join.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- +1 Jump's review found a returning space climber shown TEMPLE GROUNDS and a repeat "YOU REACHED SPACE!"
-- when their profile loaded slowly. The same trap exists here: the client starts with the first band's
-- look (the server's Cozy preset) and learns the chamber count from its plot's sockets and the State push,
-- and a slow DataStore delays BOTH (Main.server builds the plot only after loadProfile returns). This
-- simulates a 10-second load by holding back every one of the player's sockets and every push, then checks
-- through the real server and client:
--   * while the profile loads: the first band's look, no title card at all;
--   * when the plot and the push arrive for a player with all eight chambers: ONE quiet card naming the
--     Heart of the Geode, no flash, no teaser, and the look GLIDES there from the Cozy preset (no cut);
--   * the join push's harvest counter (0) plays no burst, a repeated counter plays none, and the first
--     real harvest (counter 1) does.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and b ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})
local ME = 8888
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
store:SetAsync("u_" .. ME, {
	data = {
		dust = 100, seeds = { [1] = 3 }, chambers = 8, luckLevel = 3, growthLevel = 2,
		plants = {}, codex = { [1] = true, [2] = true, [5] = true }, redeemed = {}, lastGeodeWeek = -1,
		totalDust = 90000, passes = {},
	},
})

local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local bands = Config.Env.Bands
local Lighting = h.Lighting
local cozyBright, cozyFog = Lighting.Brightness, Lighting.FogEnd

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Returning", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

-- the profile is still loading: none of the player's sockets exist yet
local plotFolder = h.workspace:FindFirstChild("Socket_" .. ME .. "_1", true).Parent
local held = {}
for _, d in plotFolder:GetChildren() do
	if string.match(d.Name, "^Socket_" .. ME .. "_") then
		table.insert(held, d)
		d.Parent = nil
	end
end
eq(#held, 48, "all 48 sockets held back while the profile 'loads'")

assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Grotto.client"))
local root = plr.PlayerGui.CrystalGrotto.Root
local card, cardSub, chip = root.BandCard, root.BandCardSub, root.BandChip
local folder = h.workspace:FindFirstChild("CrystalLocalGrotto")

local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local cards, lastCard, flashes = {}, "", 0
local function frame(dt)
	cam.CFrame = CFrame.new(Vector3.new(0, 20, -20), Vector3.new(0, 10, 40))
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text .. " | " .. cardSub.Text)
	end
	for _, gg in plr.PlayerGui:GetChildren() do
		if gg.Name == "FxFlash" and not gg:GetAttribute("__counted") then
			gg:SetAttribute("__counted", true)
			flashes += 1
		end
	end
end
local function run(seconds, dt, each)
	for i = 1, math.floor(seconds / dt + 0.5) do
		frame(dt)
		if each then each(i) end
	end
end
local function burstParts()
	local n = 0
	for _, d in folder:GetChildren() do
		if d.Name == "Shard" or d.Name == "HarvestRing" or d.Name == "BeamCore" or d.Name == "BeamHalo" then n += 1 end
	end
	return n
end

--============================================================ 10 s before the profile's push arrives
run(10, 1 / 30)
eq(#cards, 0, "no title card before the server has said where the player is")
near(Lighting.Brightness, cozyBright, 0.03, "the first band's look (the server's Cozy preset) meanwhile")
near(Lighting.FogEnd, cozyFog, 0.5, "(fog too)")
truthy(string.find(chip.Text, bands[1].name, 1, true) ~= nil, "and the chip shows the default first band until then")

--============================================================ the load returns: the plot and the push arrive
for _, d in held do d.Parent = plotFolder end
local State = RS:FindFirstChild("CrystalRemotes"):FindFirstChild("State")
local rec = State:sentTo(plr)[#State:sentTo(plr)]
local s = table.clone(rec.args[1])
eq(s.chambers, 8, "the server pushed the saved 8 chambers")
eq(s.lastHarvest, nil, "and no harvest yet this session")
State.OnClientEvent:Fire(s)

local lastB, maxStep = Lighting.Brightness, 0
local target = EnvBands.sample(bands, 8, "lighting")
local startB = Lighting.Brightness
run(12, 1 / 30, function()
	maxStep = math.max(maxStep, math.abs(Lighting.Brightness - lastB))
	lastB = Lighting.Brightness
end)
eq(#cards, 1, "exactly one card")
truthy(cards[1] ~= nil and string.find(cards[1], "HEART OF THE GEODE", 1, true) ~= nil, "naming where the player is (" .. tostring(cards[1]) .. ")")
eq(flashes, 0, "quietly: no fanfare for chambers bought in an earlier session")
truthy(string.find(table.concat(cards, " "), "waking", 1, true) == nil, "and no teaser")
near(Lighting.Brightness, target.Brightness, 0.02, "the cavern arrived at the Heart of the Geode's look")
local total = math.abs(target.Brightness - startB)
truthy(total > 0.1 and maxStep <= 0.10 * total, string.format("and GLIDED there (largest frame step %.1f %% of the change)", 100 * maxStep / math.max(total, 1e-9)))
eq(burstParts(), 0, "the join push (no harvest yet) plays no burst")
truthy(string.find(chip.Text, bands[#bands].name, 1, true) ~= nil, "the chip names the last band (" .. chip.Text .. ")")

-- the same push again (any unrelated push repeats it): still nothing
State.OnClientEvent:Fire(s)
run(0.5, 1 / 30)
eq(burstParts(), 0, "a repeated push plays no burst")
-- the first REAL harvest does, once
local s2 = table.clone(s)
s2.lastHarvest = { n = 1, socket = 3, seed = 2, tier = 3 }
State.OnClientEvent:Fire(s2)
run(0.2, 1 / 30)
truthy(burstParts() > 0, "the first harvest (counter 1) bursts")
run(3, 1 / 30)
State.OnClientEvent:Fire(s2)
run(0.2, 1 / 30)
eq(burstParts(), 0, "the same counter pushed again does not replay it")

-- a malformed record costs that one burst, never the visuals: the next good one still plays
local bad = table.clone(s)
bad.lastHarvest = { n = 2, socket = "x", seed = 1, tier = 2.5 }
State.OnClientEvent:Fire(bad)
run(0.5, 1 / 30)
eq(burstParts(), 0, "a record with a nonsense socket draws nothing")
local good = table.clone(s)
good.lastHarvest = { n = 3, socket = 5, seed = 1, tier = 4 }
State.OnClientEvent:Fire(good)
run(0.2, 1 / 30)
truthy(burstParts() > 0, "and the next good record still bursts (the frame did not stop)")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no warnings")
print(string.format("growacrystal join: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal join check failed", 0) end
