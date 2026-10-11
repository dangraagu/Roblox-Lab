-- Deep Vein — THE CAVE IS A SECRET. Review 2026-09-30, finding 1.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_secret.luau
--
-- src/shared replicates, so Mine (the generator) and Config.WorldSeed are on every client, and the State
-- payload carries the rebirth count. The cave used to be a function of those two and nothing else: a probe
-- built from ReplicatedStorage alone predicted 462 of 462 hidden ore cells, an ore x-ray and one
-- memorisable map per rebirth for everybody. The server now draws a KEY per player per rebirth, saves it
-- with the profile and never replicates it (Mine.lua's `legacyKey` names the old public cave).
--
-- This file drives the REAL server and asserts, on what it really builds:
--   1. a client's prediction from ReplicatedStorage finds hidden ore at chance, not 100%;
--   2. the key is saved, and two players at the same rebirth dig different caves;
--   3. no replicated instance, attribute, value or remote payload carries the key;
--   4. a rejoin restores the SAME cave (a revealed face keeps its ore), so a relog is not a re-roll;
--   5. a rebirth draws and saves a new key; a rebirth whose save fails puts the old key back;
--   6. a read-only session (the record locked by another server) digs a throwaway cave, never the saved one.
-- The server's own truth is read where a test may read it: the emulated DataStore record.

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

local A, B, RO, FAILER = 4141, 4242, 4343, 4545
local R = 3 -- every fixture starts at rebirth 3 (wall at layer 60)
local SAVED_KEY = { a = 123456789, b = 987654321 } -- the key already in RO's and FAILER's records

local Config = require("../deep-vein/src/shared/Config")
local MineCli = require("../deep-vein/src/shared/Mine")
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local function profileData(extra)
	local d = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 0,
		rebirths = R, depthLayer = 0, bestLayer = 0, runEarned = 0,
	}
	for k, v in extra or {} do d[k] = v end
	return d
end
-- A and B: identical saves, written before caves had keys (no caveKey at all), kitted to dig fast.
store:SetAsync("u_" .. A, { data = profileData({ runEarned = 1e12 }) })
store:SetAsync("u_" .. B, { data = profileData() })
-- RO: a saved cave key, and the record held by ANOTHER live server.
store:SetAsync("u_" .. RO, { data = profileData({ caveKey = SAVED_KEY }), jobId = "OTHER-SERVER",
	session = "OTHER-SESSION", lockUntil = os.time() + 3600 })
-- FAILER: rich enough to rebirth, with a saved key.
store:SetAsync("u_" .. FAILER, { data = profileData({ caveKey = SAVED_KEY, runEarned = 1e12 }) })

assert(h:tryRun("server/Main.server"))
h:advance(1)

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
-- CLIENT-VISIBLE ONLY: the ReplicatedStorage copies of the modules, and what the server sends.
local Mine, Ore = mod("Mine"), mod("Ore")
local remotes = RS:FindFirstChild("VeinRemotes")
local StateEvent = remotes:FindFirstChild("State")
local RebirthEvent = remotes:FindFirstChild("Rebirth")
local function stateOf(plr)
	local sent = StateEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function record(uid)
	return store:GetAsync("u_" .. uid)
end
local function keyOf(uid)
	local rec = record(uid)
	return rec and rec.data and rec.data.caveKey or nil
end
local function sameKey(x, y)
	return type(x) == "table" and type(y) == "table" and x.a == y.a and x.b == y.b
end

local function shaftOf(uid)
	for _, f in h.workspace.Shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. uid, true) ~= nil then return f end
	end
	return nil
end
local function cellsOf(uid)
	local out = {}
	local f = shaftOf(uid)
	if f == nil then return out end
	for _, d in f:GetChildren() do
		local k = d:GetAttribute("CellKey")
		if k then out[k] = d:GetAttribute("Ore") end
	end
	return out
end
local C = Mine.center(Config)
local function digColumn(plr, uid, toLayer)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local f = shaftOf(uid)
	for y = 1, toLayer do
		local key = C .. ":" .. y .. ":" .. C
		local b = f:FindFirstChild("Rock_" .. uid .. "_" .. key) or f:FindFirstChild("Ore_" .. uid .. "_" .. key)
		if b then
			hrp.CFrame = CFrame.new(b.Position + Vector3.new(0, 6, 0))
			for _ = 1, 8 do
				if b.Parent == nil then break end
				b:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
				h:advance(0.35)
			end
		end
		h:advance(0.2)
	end
end

--======================================================================= 1. the public prediction is at chance
local plrA = h:join("Leaky", A)
h:advance(1)
h.Players:simulateSpawn(plrA, h.workspace)
h:advance(2)
local sA = stateOf(plrA)
eq(sA and sA.rebirths, R, "the client is told its rebirth count (that is not the secret)")
local presentAtJoin = cellsOf(A)
local seen = {}
do
	local f = shaftOf(A)
	for k, ore in presentAtJoin do seen[k] = ore end
	f.ChildAdded:Connect(function(d)
		local k = d:GetAttribute("CellKey")
		if k and seen[k] == nil then seen[k] = d:GetAttribute("Ore") end
	end)
end
local wPublic = Mine.world(Config, sA.rebirths, Mine.legacyKey(Config, sA.rebirths))
digColumn(plrA, A, wPublic.maxLayer)
local hiddenOre, hiddenOreMatch, hidden, hiddenMatch = 0, 0, 0, 0
for k, ore in seen do
	if presentAtJoin[k] == nil then
		local x, y, z = Mine.parseKey(k)
		local p = Mine.cell(Config, Ore, wPublic, x :: number, y :: number, z :: number)
		hidden += 1
		if p.ore == ore then hiddenMatch += 1 end
		if ore > 0 then
			hiddenOre += 1
			if p.ore == ore then hiddenOreMatch += 1 end
		end
	end
end
print(string.format("  revealed by digging to the wall: %d cells hidden at join (public prediction right on %d), %d of them ore (right on %d)",
	hidden, hiddenMatch, hiddenOre, hiddenOreMatch))
truthy(hiddenOre >= 100, "set-up: the dig revealed plenty of hidden ore (" .. hiddenOre .. ")")
truthy(hiddenOreMatch / math.max(1, hiddenOre) < 0.5, string.format(
	"a client's prediction from ReplicatedStorage finds the hidden ore at chance, not all of it (%d of %d)", hiddenOreMatch, hiddenOre))
-- CONTROL: the same comparison against the server's REAL key (from the record) is exact, so the test can see a match.
h:advance(Config.Save.AutosaveSeconds + 1)
local keyA = keyOf(A)
truthy(MineCli.validKey(keyA), "the drawn key is in the saved record")
truthy(not sameKey(keyA, Mine.legacyKey(Config, R)), "…and it is not the old public cave's")
do
	local wReal = MineCli.world(Config, R, keyA)
	local right, n = 0, 0
	for k, ore in seen do
		local x, y, z = Mine.parseKey(k)
		n += 1
		if MineCli.cell(Config, Ore, wReal, x :: number, y :: number, z :: number).ore == ore then right += 1 end
	end
	eq(right, n, "CONTROL: the record's key predicts every cell the server built (" .. n .. ")")
end

--======================================================================= 2. every player has their own cave
local plrB = h:join("Other", B)
h:advance(1)
h.Players:simulateSpawn(plrB, h.workspace)
h:advance(2)
h:advance(Config.Save.AutosaveSeconds + 1)
local keyB = keyOf(B)
truthy(MineCli.validKey(keyB), "the second player's key is saved too")
truthy(not sameKey(keyA, keyB), "two players at the same rebirth hold different keys")
do
	-- a brand-new player (no record at all) gets a drawn key too, saved with their first write
	local FRESH = 4646
	local plrN = h:join("Newcomer", FRESH)
	h:advance(1)
	h.Players:simulateSpawn(plrN, h.workspace)
	h:advance(Config.Save.AutosaveSeconds + 1)
	local keyN = keyOf(FRESH)
	truthy(MineCli.validKey(keyN) and not sameKey(keyN, keyA) and not sameKey(keyN, keyB)
		and not sameKey(keyN, Mine.legacyKey(Config, 0)), "a brand-new player's first save holds a drawn key of their own")
end
do
	local ca, cb = presentAtJoin, cellsOf(B) -- A is at the bottom now; its mouth as it stood at join
	local same, n = 0, 0
	for y = 1, 1 do
		for x = 2, Config.Mine.GridW - 1 do
			for z = 2, Config.Mine.GridW - 1 do
				local k = Mine.key(x, y, z)
				if cb[k] ~= nil and ca[k] ~= nil then
					n += 1
					if ca[k] == cb[k] then same += 1 end
				end
			end
		end
	end
	print(string.format("  mouth floors of two rebirth-%d miners: %d of %d cells hold the same ore", R, same, n))
	truthy(n >= 20 and same < n, "…and their mouth floors differ (" .. same .. " of " .. n .. " the same)")
end

--======================================================================= 3. nothing replicated carries the key
do
	local needles = { keyA.a, keyA.b, keyB.a, keyB.b }
	local hits = {}
	local function check(where, v)
		if type(v) == "number" then
			for _, n in needles do
				if v == n then table.insert(hits, where .. " = " .. tostring(v)) end
			end
		elseif type(v) == "string" then
			for _, n in needles do
				if string.find(v, tostring(n), 1, true) or string.find(string.upper(v), string.format("%08X", n), 1, true) then
					table.insert(hits, where .. " contains " .. tostring(n))
				end
			end
		elseif type(v) == "table" then
			for k, x in v do
				check(where .. "." .. tostring(k), x)
			end
		end
	end
	local scanned = 0
	for _, svc in { h.workspace, RS, h.Players, h.Lighting } do
		for _, d in svc:GetDescendants() do
			scanned += 1
			check(d:GetFullName(), d.Name)
			for k, v in d:GetAttributes() do check(d:GetFullName() .. "@" .. k, v) end
			if d:IsA("ValueBase") then check(d:GetFullName() .. ".Value", (d :: any).Value) end
		end
	end
	local payloads = 0
	for _, r in remotes:GetChildren() do
		if r.ClassName == "RemoteEvent" then
			for _, rec in r:getSent() do
				payloads += 1
				check(r.Name .. " payload", rec.args)
			end
		end
	end
	print(string.format("  scanned %d replicated instances and %d remote payloads for the two keys: %d hits", scanned, payloads, #hits))
	truthy(scanned > 500 and payloads > 10, "set-up: the scan covered the world and the remotes")
	eq(#hits, 0, "no replicated instance, attribute, value or payload carries a cave key" .. (hits[1] and (" (" .. hits[1] .. ")") or ""))
end

--======================================================================= 4. a rejoin restores the same cave
do
	-- back to the surface first, so the faces around the mouth are the ones standing (the shaft streams)
	remotes:FindFirstChild("Elevator"):simulateFireServer(plrA, "up")
	h:advance(3)
	local before = cellsOf(A)
	h:leave(plrA)
	h:advance(2)
	truthy(sameKey(keyOf(A), keyA), "leaving saves the same key")
	plrA = h:join("Leaky", A)
	h:advance(1)
	h.Players:simulateSpawn(plrA, h.workspace)
	h:advance(3)
	local after = cellsOf(A)
	local n, same = 0, 0
	for k, ore in after do
		if before[k] ~= nil then
			n += 1
			if before[k] == ore then same += 1 end
		end
	end
	print(string.format("  after a rejoin: %d faces standing both times, %d with the same ore", n, same))
	truthy(n >= 40, "set-up: the rejoin rebuilt faces seen before (" .. n .. ")")
	eq(same, n, "a rejoin restores the same cave: every face keeps its ore (a relog is not a re-roll)")
	truthy(sameKey(keyOf(A), keyA), "…and the record still holds the same key")
end

--======================================================================= 5. a rebirth draws a new key
do
	local before = cellsOf(A)
	RebirthEvent:simulateFireServer(plrA)
	h:advance(2)
	eq(stateOf(plrA).rebirths, R + 1, "the rebirth went through")
	local keyA2 = keyOf(A)
	truthy(MineCli.validKey(keyA2) and not sameKey(keyA2, keyA), "the rebirth saved a NEW key with it")
	eq(record(A).data.rebirths, R + 1, "…in the same write as the new rebirth count")
	local after = cellsOf(A)
	local n, same = 0, 0
	for k, ore in after do
		local _, y = Mine.parseKey(k)
		if y == 1 and before[k] ~= nil then
			n += 1
			if before[k] == ore then same += 1 end
		end
	end
	truthy(n >= 20 and same < n, "…and it is a different cave (" .. same .. " of " .. n .. " mouth cells the same)")
end
do
	local plrF = h:join("Unlucky", FAILER)
	h:advance(1)
	h.Players:simulateSpawn(plrF, h.workspace)
	h:advance(2)
	store.__failNext = true -- the rebirth's own atomic flush is the next DataStore call
	RebirthEvent:simulateFireServer(plrF)
	h:advance(1)
	eq(stateOf(plrF).rebirths, R, "a rebirth whose save failed is rolled back")
	h:advance(Config.Save.AutosaveSeconds + 1)
	truthy(sameKey(keyOf(FAILER), SAVED_KEY), "…and the key rolls back with it: the next save writes the cave the player is in")
	eq(record(FAILER).data.rebirths, R, "…at the old rebirth count")
end

--======================================================================= 6. a read-only session digs a throwaway cave
do
	local plrRO = h:join("Locked", RO)
	-- a locked load is retried before it settles for read-only (Config.Save.LoadRetries, 2026-10-11)
	h:advance(1 + (Config.Save.LoadRetries or 0) * (Config.Save.LoadRetrySeconds or 0))
	h.Players:simulateSpawn(plrRO, h.workspace)
	h:advance(2)
	eq(stateOf(plrRO).canSave, false, "set-up: the record is held by another server, so this session is read-only")
	local wSaved = MineCli.world(Config, R, SAVED_KEY)
	local present = {}
	for k, ore in cellsOf(RO) do present[k] = ore end
	local f = shaftOf(RO)
	f.ChildAdded:Connect(function(d)
		local k = d:GetAttribute("CellKey")
		if k and present[k] == nil then present[k] = d:GetAttribute("Ore") end
	end)
	digColumn(plrRO, RO, 20)
	local ore, match = 0, 0
	for k, o in present do
		local x, y, z = Mine.parseKey(k)
		if o > 0 then
			ore += 1
			if MineCli.cell(Config, Ore, wSaved, x :: number, y :: number, z :: number).ore == o then match += 1 end
		end
	end
	print(string.format("  read-only session: %d ore cells seen, %d where the SAVED cave has that ore", ore, match))
	truthy(ore >= 40, "set-up: the read-only miner saw plenty of ore (" .. ore .. ")")
	truthy(match / math.max(1, ore) < 0.5, string.format(
		"a read-only session does not dig the saved cave (%d of %d ore cells match it): scouting it there is worthless", match, ore))
	local rec = record(RO)
	truthy(sameKey(rec.data.caveKey, SAVED_KEY) and rec.jobId == "OTHER-SERVER", "…and the record it could not lock is untouched")
end

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein secret: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein secret check failed", 0)
end
