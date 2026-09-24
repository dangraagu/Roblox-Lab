-- Grow a Crystal — a row of Legendary harvests must not wash the screen out.
-- Run: luau check_growacrystal_flash.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- A Legendary or Mythic harvest plays a full-screen flash in the tier's colour (plus a camera shake for
-- Mythic), with its burst, beam and card. A Legendary seed always refracts to Legendary or Mythic, so a
-- late-game player who plants Legendary seeds gets that flash on EVERY harvest: clicking a terrace of them
-- at 4 clicks/s stacked three flashes at once, up to 73 % opaque, over the crystals they were aiming at
-- (adversarial review 2026-09-24, finding 3).
--
-- What must hold, through the real Grotto.client with the server's State pushes replayed exactly as
-- Main.server sends them (lastHarvest = { n, socket, seed, tier }):
--   * six Mythic harvests at 4 clicks/s: ONE flash and ONE shake; never two flashes on screen; the combined
--     flash never more opaque than a single flash (Config.Env.HarvestFlash.alpha);
--   * every one of the six still gets its own burst at its own socket and the card (only the full-screen
--     part waits);
--   * the celebration is rate-limited, not removed: a Legendary after the cooldown flashes again, one inside
--     it does not.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})
local ME = 6262
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
store:SetAsync("u_" .. ME, {
	data = {
		dust = 100000, seeds = { [5] = 50 }, chambers = 8, luckLevel = 0, growthLevel = 0,
		plants = {}, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {},
	},
})

local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Harvester", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

-- count the full-screen effects the cavern asks for (the module table is shared with Grotto.client)
local FxClient = h:_require(RS:FindFirstChild("FxClient"))
local flashCalls, shakeCalls = 0, 0
local realFlash, realShake = FxClient.flash, FxClient.shake
FxClient.flash = function(...)
	flashCalls += 1
	return realFlash(...)
end
FxClient.shake = function(...)
	shakeCalls += 1
	return realShake(...)
end

assert(h:tryRun("client/Grotto.client"))
local State = RS:FindFirstChild("CrystalRemotes"):FindFirstChild("State")
local base = table.clone(State:sentTo(plr)[#State:sentTo(plr)].args[1])
State.OnClientEvent:Fire(base)

local RunService = h.game:GetService("RunService")
local peakGuis, peakAlpha = 0, 0
local function frame()
	RunService.RenderStepped:Fire(1 / 30)
	h:advance(1 / 30)
	local guis, keep = 0, 1
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" then
			guis += 1
			local f = g:FindFirstChildOfClass("Frame")
			if f then keep *= f.BackgroundTransparency end
		end
	end
	peakGuis = math.max(peakGuis, guis)
	peakAlpha = math.max(peakAlpha, 1 - keep)
end
local function run(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do frame() end
end
run(14) -- settle: the quiet first card (no flash) and the Heart of the Geode's look
eq(flashCalls, 0, "a returning player's join is quiet: no flash")
peakGuis, peakAlpha = 0, 0

local folder = h.workspace:FindFirstChild("CrystalLocalGrotto")
local card = plr.PlayerGui.CrystalGrotto.Root.BandCard
local n = 0
local function harvest(socket: number, seed: number, tier: number)
	n += 1
	local s = table.clone(base)
	s.lastHarvest = { n = n, socket = socket, seed = seed, tier = tier }
	State.OnClientEvent:Fire(s)
end
local function ringAtSocket(socket: number): boolean
	frame()
	local ring = folder:FindFirstChild("HarvestRing")
	local sk = h.workspace:FindFirstChild("Socket_" .. ME .. "_" .. socket, true)
	if ring == nil or sk == nil then return false end
	local p, q = ring.CFrame.Position, sk.Position
	return math.abs(p.X - q.X) < 0.01 and math.abs(p.Z - q.Z) < 0.01
end

-- six Mythic harvests (Legendary seeds that refracted), one click every 0.25 s
local bursts = 0
for socket = 1, 6 do
	harvest(socket, 5, 6)
	if ringAtSocket(socket) then bursts += 1 end
	truthy(card.Visible and string.find(card.Text, "MYTHIC", 1, true) ~= nil, "harvest " .. socket .. " shows the MYTHIC card")
	run(0.25 - 1 / 30)
end
eq(bursts, 6, "every harvest of the row burst at its own socket")
eq(flashCalls, 1, "six Mythic harvests in 1.5 s flash the screen ONCE")
eq(shakeCalls, 1, "... and shake it once")
run(1.5)
local alpha = Config.Env.HarvestFlash and Config.Env.HarvestFlash.alpha or 0.35
eq(peakGuis, 1, "never two flashes on screen at once")
truthy(peakAlpha <= alpha + 1e-6, string.format("the screen was never more than one flash opaque (peak %.2f, one flash %.2f)", peakAlpha, alpha))

-- rate-limited, not removed
local cooldown = Config.Env.HarvestFlash and Config.Env.HarvestFlash.cooldown or 0
run(math.max(0, cooldown - 1.5) + 0.2)
harvest(7, 5, 5)
truthy(ringAtSocket(7), "a Legendary after the cooldown bursts")
eq(flashCalls, 2, "... and flashes again")
eq(shakeCalls, 1, "(a Legendary never shakes)")
run(1)
harvest(8, 5, 5)
truthy(ringAtSocket(8), "a Legendary 1 s later still bursts")
eq(flashCalls, 2, "... but does not flash inside the cooldown")
run(3)

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("  warning: " .. w) end
print(string.format("  measured: %d flash call(s), %d shake(s), peak %d flash gui(s) at once, peak opacity %.2f", flashCalls, shakeCalls, peakGuis, peakAlpha))
print(string.format("growacrystal flash: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal flash check failed", 0) end
