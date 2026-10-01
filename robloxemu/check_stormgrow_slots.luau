-- StormGrow — a farm that frees up goes to whoever is waiting for one (REVIEW-1 A3).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_slots.luau 2>&1
--
-- Six farms per server. Before REVIEW-1 a leaving farmer's farm was freed only AFTER the leave's DataStore writes
-- returned, and a player without a farm was never offered one that freed up later: a newcomer who joined inside
-- that window (0.1 s after the leave with 0.3 s writes; 3 s after with a 6 s queued write) farmed nothing for the
-- whole session next to a sign that said "Free farm". The same held for every 7th+ player if MaxPlayers is not 6.
-- Here the DataStore is given latency (each UpdateAsync waits before it runs, as a real round trip or a queued
-- same-key write does) and farmers leave while newcomers wait.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-slots", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("StormGrow_v1")
local ods = DSS:GetOrderedDataStore("StormGrowAlmanac_v1")
store:SetAsync("u_502", { v = 1, coins = 500, harvested = 900, fields = 1, unlocked = 2, selected = "carrot",
	tiles = { ["1_1"] = { c = "carrot", at = 1, m = 0 } }, almanac = {}, almanacCount = 0, almanacAt = 0, harvests = 40 })

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local farms = h.workspace.Farms
local remotes = RS.StormRemotes
local function toasts(plr)
	local out = {}
	for _, rec in remotes.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return table.concat(out, " | ")
end
local function owns(plr, k)
	local pad = farms["Farm_" .. k]["FarmPad_" .. k]
	return plr:GetAttribute("Slot") == k and plr.RespawnLocation == pad and pad.Enabled
		and string.find(farms["Farm_" .. k].Sign.SignGui.Owner.Text, plr.Name, 1, true) ~= nil
		and farms["Farm_" .. k].Tiles.Tile_1_1:GetAttribute("Owner") == plr.UserId
end

local farmers = {}
for i = 1, 6 do
	farmers[i] = h:join("Farmer" .. i, 500 + i)
	h:advance(0.2)
	h.Players:simulateSpawn(farmers[i], h.workspace)
	h:advance(0.1)
end
h:advance(1)

--============================================================ 1. a 7th player waits, and gets the first farm that frees

local seventh = h:join("Seventh", 777)
h:advance(0.5)
local char7 = h.Players:simulateSpawn(seventh, h.workspace)
h:advance(0.3)
eq(seventh:GetAttribute("Slot"), 0, "set-up: a 7th player has no farm")
truthy(string.find(toasts(seventh), "next", 1, true) ~= nil, "and is told it gets the next farm that frees up (" .. toasts(seventh) .. ")")
local k1 = farmers[1]:GetAttribute("Slot")
h:leave(farmers[1])
h:advance(1)
truthy(owns(seventh, k1), "when farmer 1 leaves, the waiting player gets that farm: slot, pad, spawn, sign and tiles")
truthy(string.find(toasts(seventh), "yours", 1, true) ~= nil, "and is told (" .. toasts(seventh) .. ")")
do
	local pad = farms["Farm_" .. k1]["FarmPad_" .. k1]
	local root = char7.HumanoidRootPart
	local d = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z).Magnitude
	truthy(d <= 3, string.format("and stands on its pad (%.1f studs off)", d))
end
-- the new owner can farm it
remotes.Tap:simulateFireServer(seventh, k1, "1_5")
h:advance(0.3)
eq(farms["Farm_" .. k1].Tiles.Tile_1_5:GetAttribute("Crop"), "radish", "and plants on it")

--============================================================ 2. a newcomer during the leave's save (writes take 0.3 s)

local latency = 0.3
for _, st in { store, ods } do
	local orig = st.UpdateAsync
	st.UpdateAsync = function(self, k, f)
		h.scheduler:wait(latency)
		return orig(self, k, f)
	end
end
do
	local leaver = farmers[2]
	local k = leaver:GetAttribute("Slot")
	h.scheduler:spawn(function() h:leave(leaver) end)
	h:advance(0.1)
	local newcomer = h:join("Newcomer", 801)
	h:advance(1.5)
	truthy(owns(newcomer, k), "a newcomer joining 0.1 s after a leave, while its 0.3 s save is in flight, gets that farm")
	h:advance(2)
	eq(store:GetAsync("u_502").session.lockUntil, 0, "and the leaver's save still landed (lock released)")
	eq(store:GetAsync("u_502").coins, 500, "with its data")
	eq(farms["Farm_" .. k].Tiles.Tile_1_1:GetAttribute("Owner"), newcomer.UserId, "and nothing of the leaver's is written onto the newcomer's farm")
end

--============================================================ 3. a queued 6 s write, a newcomer 3 s after the leave

latency = 6
do
	local leaver = farmers[3]
	local k = leaver:GetAttribute("Slot")
	h.scheduler:spawn(function() h:leave(leaver) end)
	h:advance(3)
	local late = h:join("Queued", 802)
	h:advance(0.2)
	eq(late:GetAttribute("Slot"), k, "at once: the farm was free the moment its farmer left, 3 s before the leave's save returns")
	h:advance(15)
	truthy(owns(late, k), "a newcomer 3 s into a 6 s queued save gets that farm, all of it")
end

print("")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow slots: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow slots check failed", 0) end
