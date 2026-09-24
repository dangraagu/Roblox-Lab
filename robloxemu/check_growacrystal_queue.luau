-- Grow a Crystal — the join push must reach EVERY client script, whichever one connects first.
-- Run: luau check_growacrystal_queue.luau 2>&1   (check_growacrystal_queue_hudfirst.luau is the other order)
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- Roblox queues a RemoteEvent fired at a client before any listener exists and hands the queue to the
-- FIRST connection only. The server pushes a player's whole profile (State) at join, usually before the
-- client's LocalScripts have started, and pushes again only on a plant, harvest, buy, geode or code. Before
-- the living cavern, Hud.client was the only listener on State, so it always got that push. Grotto.client
-- listens too, and LocalScripts start in an order Roblox does not define: when the cavern script connected
-- first, the HUD of a returning player read "💎 0", "Codex 0/6", no seed counts and no prices (a wiped save,
-- to the eye) until the player's first click (adversarial review 2026-09-24, finding 1).
--
-- The emulator drops a push that nobody listens to, so this file models Roblox's queue itself: the pushes
-- the server sent before any client script ran are handed, once, to the FIRST connection anybody makes to
-- State.OnClientEvent (deferred, as Roblox's deferred signals do). Here the cavern script starts FIRST;
-- check_growacrystal_queue_hudfirst.luau starts the HUD first.
--
-- What must hold:
--   * the HUD shows the pushed profile (dust, codex, seed counts, prices, levels) with no click at all;
--   * the cavern shows it too;
--   * State has exactly ONE connection on the client, whatever the order: with one listener the queue
--     rule cannot pick a loser (src/shared/StateFeed.luau);
--   * later pushes still reach both scripts: a purchase updates the HUD, a harvest bursts once.

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
local ME = 4242
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
store:SetAsync("u_" .. ME, {
	data = {
		dust = 523456, seeds = { [1] = 9, [2] = 4, [3] = 2 }, chambers = 8, luckLevel = 3, growthLevel = 2,
		plants = {}, codex = { [1] = true, [2] = true, [3] = true }, redeemed = {}, lastGeodeWeek = -1,
		totalDust = 900000, passes = {},
	},
})

local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local bands = Config.Env.Bands
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Returner", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)

local remotes = RS:FindFirstChild("CrystalRemotes")
local State = remotes:FindFirstChild("State")

-- Roblox's queue: everything sent to this player before any client listener existed
local queued = table.clone(State:sentTo(plr))
truthy(#queued >= 1, "the server pushed the profile before any client script ran (" .. #queued .. " push(es))")
local join = queued[#queued].args[1]
eq(join.dust, 523456, "the join push carries the saved dust")
eq(join.chambers, 8, "and the saved 8 chambers")

local sig = State.OnClientEvent
local realConnect = sig.Connect
local flushedTo = 0
sig.Connect = function(self, fn)
	local conn = realConnect(self, fn)
	if queued ~= nil then
		local q = queued
		queued = nil
		flushedTo += 1
		task.defer(function()
			for _, rec in q do
				fn(table.unpack(rec.args, 1, rec.args.n))
			end
		end)
	end
	return conn
end

-- the cavern script starts first, and the queue is flushed to it before the HUD even starts (the reported case)
local okG, errG = h:tryRun("client/Grotto.client")
truthy(okG, "Grotto.client loads (" .. tostring(errG) .. ")")
h:advance(0.1)
local okH, errH = h:tryRun("client/Hud.client")
truthy(okH, "Hud.client loads (" .. tostring(errH) .. ")")
eq(flushedTo, 1, "the queue was handed to exactly one connection (the first)")
eq(sig:GetConnectionCount(), 1, "State has exactly ONE client connection, shared by the HUD and the cavern")

local RunService = h.game:GetService("RunService")
local function run(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end
run(3) -- standing still: no click, no second push

local function hudTexts(): { [string]: boolean }
	local out = {}
	for _, d in plr.PlayerGui.CrystalHud:GetDescendants() do
		if d.ClassName == "TextLabel" or d.ClassName == "TextButton" then out[d.Text] = true end
	end
	return out
end
local texts = hudTexts()
local function shows(text: string, what: string)
	truthy(texts[text] == true, "the HUD shows " .. what .. " from the join push: '" .. text .. "'")
end
shows("💎 " .. tostring(join.dust), "the saved dust")
shows("📖 Codex: " .. tostring(join.codexCount) .. "/" .. tostring(Config.MaxTier), "the codex")
shows(Config.Tiers[1] .. " (9)", "the Shard seeds owned")
shows(Config.Tiers[2] .. " (4)", "the Quartz seeds owned")
shows("Chambers MAX", "that every chamber is bought")
shows("Luck Lv3 → 💎" .. tostring(join.luckCost), "the luck level and its price")
shows("Growth Lv2 → 💎" .. tostring(join.growthCost), "the growth level and its price")
truthy(texts["💎 0"] == nil, "and not the empty '💎 0' of a HUD that never got the push")

local chip = plr.PlayerGui.CrystalGrotto.Root.BandChip
truthy(string.find(chip.Text, bands[#bands].name, 1, true) ~= nil, "the cavern names the Heart of the Geode (" .. chip.Text .. ")")

-- later pushes reach both scripts through the same single connection
local Buy = remotes:FindFirstChild("Buy")
Buy:simulateFireServer(plr, "seed", 1)
run(0.5)
texts = hudTexts()
shows("💎 " .. tostring(join.dust - Config.Economy.SeedCost[1]), "the dust after buying a Shard seed (a live push)")
shows(Config.Tiers[1] .. " (10)", "the Shard seed count after buying one")
eq(sig:GetConnectionCount(), 1, "still one connection after live pushes")

local folder = h.workspace:FindFirstChild("CrystalLocalGrotto")
local function shards(): number
	local n = 0
	for _, d in folder:GetChildren() do
		if d.Name == "Shard" then n += 1 end
	end
	return n
end
local s = table.clone(State:sentTo(plr)[#State:sentTo(plr)].args[1])
s.lastHarvest = { n = 1, socket = 4, seed = 1, tier = 2 }
State.OnClientEvent:Fire(s)
run(0.2)
truthy(shards() > 0, "a harvest push still bursts in the cavern (" .. shards() .. " shards)")
run(2)
State.OnClientEvent:Fire(s)
run(0.2)
eq(shards(), 0, "and the same harvest pushed again does not burst twice")

-- the listener surface: the shared module that owns the connection fires nothing at the server
local src = require("./build/grow-a-crystal")
truthy(src["shared/StateFeed"] ~= nil, "src/shared/StateFeed.luau is in the bundle")
if src["shared/StateFeed"] then
	for _, call in { "FireServer", "InvokeServer", "SetAttribute", "FireAllClients" } do
		truthy(string.find(src["shared/StateFeed"].source, call, 1, true) == nil, "shared/StateFeed never calls " .. call)
	end
end

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("  warning: " .. w) end
print(string.format("growacrystal queue (cavern first): %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal queue check failed", 0) end
