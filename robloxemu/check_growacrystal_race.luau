-- Grow a Crystal — the cavern must not depend on winning a race for the join push.
-- Run: luau check_growacrystal_race.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- Roblox queues a RemoteEvent fired at a client before any listener exists and flushes the queue to the
-- FIRST connection only. Hud.client and Grotto.client both need State, and which LocalScript connects
-- first is not defined. Since review round 1 (2026-09-24) they share ONE connection (src/shared/StateFeed.luau,
-- check_growacrystal_queue*.luau), so neither loses the join push to the other. This check stays as the
-- belt: a push that is late or never arrives. The only other push comes when the player plants, harvests
-- or buys; a player with the Heart of the Geode who stands and watches must not sit in the first band's
-- look until then.
--
-- What must hold instead, with the client receiving NO State push at all:
--   * the cavern reads the chambers from the player's own sockets in the world (6 per chamber) and gets
--     to the Heart of the Geode's look by itself;
--   * a batch of sockets that replicates in two parts (a split of a few frames) produces ONE quiet card
--     naming where the player is, never a card for the half-built count followed by a fanfare;
--   * the first harvest push this client ever sees (counter 1) still bursts: the counter is per session,
--     so any counter above what the client has seen is a harvest it has not drawn yet.

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
local ME = 9191
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
store:SetAsync("u_" .. ME, {
	data = {
		dust = 100, seeds = { [1] = 3 }, chambers = 8, luckLevel = 0, growthLevel = 0,
		plants = {}, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 1000, passes = {},
	},
})

local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local bands = Config.Env.Bands
local Lighting = h.Lighting

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Watcher", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

-- sockets 13..48 have not replicated yet when the client starts
local plotFolder = h.workspace:FindFirstChild("Socket_" .. ME .. "_1", true).Parent
local late = {}
for id = 13, 48 do
	local s = plotFolder:FindFirstChild("Socket_" .. ME .. "_" .. id)
	if s then
		table.insert(late, s)
		s.Parent = nil
	end
end
eq(#late, 36, "36 sockets held back to arrive late")

assert(h:tryRun("client/Grotto.client"))
local root = plr.PlayerGui.CrystalGrotto.Root
local card, cardSub, chip = root.BandCard, root.BandCardSub, root.BandChip
local folder = h.workspace:FindFirstChild("CrystalLocalGrotto")

local RunService = h.game:GetService("RunService")
local cards, lastCard, flashes = {}, "", 0
local function run(seconds, dt)
	for _ = 1, math.floor(seconds / dt + 0.5) do
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
end

run(0.3, 1 / 30)
for _, s in late do s.Parent = plotFolder end -- the rest of the batch arrives a few frames later
run(14, 1 / 30)

local target = EnvBands.sample(bands, 8, "lighting")
near(Lighting.Brightness, target.Brightness, 0.02, "with no State push at all, the cavern reached the Heart of the Geode's look from its sockets")
near(Lighting.FogEnd, target.FogEnd, 0.5, "(fog too)")
truthy(string.find(chip.Text, bands[#bands].name, 1, true) ~= nil, "the chip names the Heart of the Geode (" .. chip.Text .. ")")
eq(#cards, 1, "exactly one title card (" .. table.concat(cards, " || ") .. ")")
truthy(cards[1] ~= nil and string.find(cards[1], "HEART OF THE GEODE", 1, true) ~= nil, "and it names where the player is")
eq(flashes, 0, "quietly: no fanfare for a half-replicated count catching up")
local prisms = 0
for _, d in folder:GetChildren() do
	if string.match(d.Name, "^Prism_") then prisms += 1 end
end
eq(prisms, Config.Env.Layout.GeodePrisms, "every geode prism is up")

-- the first push this client ever sees is a harvest (counter 1): it bursts
local State = RS:FindFirstChild("CrystalRemotes"):FindFirstChild("State")
local s = table.clone(State:sentTo(plr)[#State:sentTo(plr)].args[1])
s.lastHarvest = { n = 1, socket = 4, seed = 1, tier = 2 }
State.OnClientEvent:Fire(s)
run(0.2, 1 / 30)
local shards = 0
for _, d in folder:GetChildren() do
	if d.Name == "Shard" then shards += 1 end
end
truthy(shards > 0, "the first harvest push this client sees still bursts (" .. shards .. " shards)")
eq(flashes, 0, "a Quartz harvest does not flash")
-- and a State that disagrees with the world downward is not believed over the sockets
local s2 = table.clone(s)
s2.chambers = 1
State.OnClientEvent:Fire(s2)
run(3, 1 / 30)
truthy(string.find(chip.Text, bands[#bands].name, 1, true) ~= nil, "a stale push naming fewer chambers does not shrink the cavern")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no warnings")
print(string.format("growacrystal race: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal race check failed", 0) end
