-- StormGrow — nothing secret replicates (the standard §1; DESIGN.md §8.2-8.3).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_wire.luau 2>&1
--
-- StormGrow has no hidden answer; its only secrets are (a) each session's lock token and (b) the strike
-- RNG, which is unseeded and lives in the server script. This file plays a real session (joins, plants,
-- a storm with strikes, the board, a leave), then sweeps EVERYTHING that replicates: every attribute and
-- every string property of every Instance under workspace, ReplicatedStorage and Players, and every
-- RemoteEvent payload the server sent. It fails if a session token appears anywhere, if any attribute or
-- instance is named like a seed, salt, token or RNG, or if a Random object is reachable. It also pins the
-- remote surface: two server->client remotes, three client->server ones, and exactly ONE client
-- connection to each server->client remote (grow-a-crystal review finding 1).

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-wire", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- REVIEW-1: a tile is tapped by the client's pick (Farm.client + Pick.luau), which sends Tap(slot, key). Where this
-- check exercises the SERVER's rules it sends exactly that; check_stormgrow_aim and tests/walk.luau tap the screen.
local function tapTile(plr, hb)
	h.ReplicatedStorage.StormRemotes.Tap:simulateFireServer(plr, hb:GetAttribute("Farm"), hb:GetAttribute("Key"))
end

local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
Config.Weather.Chance.storm = 1 -- strikes for sure, so the sweep sees marks and LastStrike (this process only)

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local players = {}
for i = 1, 3 do
	local plr = h:join("Wire" .. i, 900 + i)
	h:advance(0.3)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.2)
	players[i] = plr
end
h.Players.LocalPlayer = players[1]
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	assert(h:tryRun(key))
end
local RunService = h.game:GetService("RunService")
local function frames(s) for _ = 1, math.floor(s / 0.1) do RunService.RenderStepped:Fire(0.1); h:advance(0.1) end end
for _, plr in players do
	local tiles = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles
	for t = 1, 9 do
		tapTile(plr, tiles["Tile_1_" .. t])
		h:advance(0.15)
	end
end
-- run to the end of the next storm (ripe radishes get struck), with the clients drawing it
local Weather = h:_require(RS:FindFirstChild("Weather"))
local now = h.workspace:GetAttribute("ServerNow")
local k, s = Weather.nextEvent(now, Config.Weather)
-- the first storm that starts after the Radishes (30 s) are ripe: booting at :29:45 the :30 storm is 15 s away and
-- would end this run before any strike (a 35-phase sweep of this file, 2026-10-01, failed at :29:45 and :29:50)
while k ~= "storm" or s - now < 35 do k, s = Weather.nextEvent(s, Config.Weather) end
h:advance(s - now - 2)
frames(20)
h.workspace.Valley.AlmanacBoard.BoardPrompt.Triggered:Fire(players[1])
frames(1)
truthy((players[1]:GetAttribute("AlmanacCount") or 0) >= 1, "set-up: the session found an Almanac entry (strikes happened)")

-- the secrets
local store = h.services.DataStoreService:GetDataStore("StormGrow_v1")
local tokens = {}
for _, plr in players do
	local doc = store:GetAsync("u_" .. plr.UserId)
	if doc and doc.session and type(doc.session.token) == "string" then table.insert(tokens, doc.session.token) end
end
eq(#tokens, 3, "set-up: three session tokens exist (in the DataStore, where they belong)")

--============================================================ the sweep

-- Attribute names may not even SOUND like a secret. Instance names get the same list minus "seed" (this is
-- a farm: the 🌱 Seeds panel and its rows are crop seeds, a gameplay word) and minus "rng" (checked by
-- the Random sweep below and by there being no Rng module at all: StormGrow's only RNG is the server's).
local BAD_ATTR = { "seed", "salt", "token", "secret", "rng", "random", "nextstrike", "session" }
local BAD_INST = { "salt", "token", "secret", "random", "nextstrike", "session" }
local function badIn(list, n: string): string?
	local lower = string.lower(n)
	for _, b in list do
		if string.find(lower, b, 1, true) then return b end
	end
	return nil
end
local function badName(n: string): string? return badIn(BAD_ATTR, n) end
local function badInstName(n: string): string? return badIn(BAD_INST, n) end
local function containsToken(v): boolean
	if type(v) ~= "string" then return false end
	for _, t in tokens do
		if string.find(v, t, 1, true) then return true end
	end
	return false
end

local swept, attrs, leaks, names, tables, randoms = 0, 0, {}, {}, {}, 0
local STRING_PROPS = { "Name", "Text", "Value", "ActionText", "ObjectText" }
local function sweep(root)
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, inst in list do
		swept += 1
		for name, v in inst:GetAttributes() do
			attrs += 1
			if containsToken(v) then table.insert(leaks, inst:GetFullName() .. "@" .. name) end
			local b = badName(name)
			if b then table.insert(names, inst:GetFullName() .. "@" .. name .. " (" .. b .. ")") end
			if type(v) == "table" then table.insert(tables, inst:GetFullName() .. "@" .. name) end
		end
		for _, prop in STRING_PROPS do
			local ok, v = pcall(function() return (inst :: any)[prop] end)
			if ok and containsToken(v) then table.insert(leaks, inst:GetFullName() .. "." .. prop) end
		end
		local b = badInstName(tostring(inst.Name))
		if b then
			table.insert(names, inst:GetFullName() .. " (" .. b .. ")")
		end
		local ok, v = pcall(function() return (inst :: any).Value end)
		if ok and typeof and type(v) == "table" and tostring(v) == "Random" then randoms += 1 end
	end
end
sweep(h.workspace)
sweep(RS)
sweep(h.Players)
print(string.format("  swept %d instances and %d attributes under workspace, ReplicatedStorage and Players", swept, attrs))
eq(#leaks, 0, "no session token anywhere that replicates (" .. table.concat(leaks, ", ") .. ")")
eq(#names, 0, "nothing named like a seed, salt, token or RNG (" .. table.concat(names, ", ") .. ")")
eq(#tables, 0, "no attribute holds a table (Roblox rejects them; the emulator does not) (" .. table.concat(tables, ", ") .. ")")
eq(randoms, 0, "no Random object is reachable")
eq(#h.game:GetService("ServerStorage"):GetChildren(), 0, "ServerStorage holds nothing (no server-only Instance is planned)")
eq(RS:FindFirstChild("Rng"), nil, "no seeded RNG module ships at all (the strike RNG is the server's unseeded Random)")

--============================================================ remote payloads

local remotes = RS.StormRemotes
local sent, payloadLeaks = 0, 0
local sentBy, strikeToasts = {}, 0
local function scan(v, depth)
	if depth > 6 then return end
	if containsToken(v) then payloadLeaks += 1 end
	if type(v) == "table" then
		for kk, vv in v do
			scan(kk, depth + 1)
			scan(vv, depth + 1)
		end
	end
end
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" and r.getSent then
		for _, rec in r:getSent() do
			sent += 1
			sentBy[r.Name] = (sentBy[r.Name] or 0) + 1
			if r.Name == "Toast" and string.find(tostring(rec.args[1]), "NEW in the Almanac", 1, true) then strikeToasts += 1 end
			for _, a in rec.args do scan(a, 0) end
		end
	end
end
-- What the scan must have seen to mean anything: every player's board payload (sent on load) and the toast a
-- strike sends. A bare count (it was "> 10") depends on the boot phase: booting at :29:26 the storm comes 34 s
-- later and the run sends 8 (a CONTROL run of the mutation sweep went red on it, 2026-10-01).
truthy((sentBy.Board or 0) >= 3, string.format("set-up: a board payload for each of the 3 players (%d)", sentBy.Board or 0))
truthy(strikeToasts >= 1, string.format("set-up: and a strike's Almanac toast (%d; %d payloads in all)", strikeToasts, sent))
eq(payloadLeaks, 0, "no remote payload carries a session token")

--============================================================ the remote surface

do
	local names2 = {}
	for _, r in remotes:GetChildren() do table.insert(names2, r.Name) end
	table.sort(names2)
	eq(table.concat(names2, ","), "Board,BuyField,Select,Tap,Toast,Unlock", "exactly six remotes: Toast and Board out, Tap, Select, Unlock, BuyField in")
	eq(remotes.Toast.OnClientEvent:GetConnectionCount(), 1, "exactly one client connection to Toast")
	eq(remotes.Board.OnClientEvent:GetConnectionCount(), 1, "exactly one client connection to Board")
	-- no remote accepts a mark, an entry or a count: fire the client->server ones with junk
	local p = players[2]
	local before = { p:GetAttribute("AlmanacCount"), p:GetAttribute("Coins"), p:GetAttribute("Harvested") }
	remotes.Select:simulateFireServer(p, { marks = 7 })
	h:advance(0.2)
	remotes.Select:simulateFireServer(p, "stormfruit")
	h:advance(0.2)
	remotes.Unlock:simulateFireServer(p, 99999, "tempest")
	h:advance(0.2)
	remotes.BuyField:simulateFireServer(p, -5)
	h:advance(0.2)
	-- Tap(slot, key) is the only way a tile is touched (REVIEW-1): junk of every shape, another farm's tile, a tile
	-- that does not exist. None of it may plant, harvest, grant anything or raise on the server.
	local coins0 = p:GetAttribute("Coins")
	local crops0 = {}
	for _, hb in h.workspace.Farms["Farm_" .. p:GetAttribute("Slot")].Tiles:GetChildren() do
		if hb:GetAttribute("Key") then crops0[hb] = hb:GetAttribute("Crop") end
	end
	local junk = { { nil, nil }, { 0 / 0, "1_1" }, { 1e308, "1_1" }, { -1, "1_1" }, { 1.5, "1_1" }, { 7, "1_1" },
		{ { 1 }, "1_1" }, { p:GetAttribute("Slot"), string.rep("x", 10000) }, { p:GetAttribute("Slot"), "9_9" },
		{ p:GetAttribute("Slot"), "1_0" }, { p:GetAttribute("Slot"), { "1_1" } }, { "1", "1_1" }, { Vector3.new(1, 2, 3), "1_1" },
		{ p:GetAttribute("Slot"), 1 } }
	for _, j in junk do
		remotes.Tap:simulateFireServer(p, j[1], j[2])
		h:advance(0.2)
	end
	local changed = 0
	for hb, c in crops0 do
		if hb:GetAttribute("Crop") ~= c then changed += 1 end
	end
	eq(changed, 0, string.format("%d junk Tap calls change no tile on the sender's farm", #junk))
	eq(p:GetAttribute("Coins"), coins0, "and no coins")
	eq(p:GetAttribute("AlmanacCount"), before[1], "junk sent to the remotes grants no Almanac entry")
	eq(p:GetAttribute("Harvested"), before[3], "and no harvest")
	eq(p:GetAttribute("Selected") ~= "stormfruit", true, "and cannot select a locked seed")
	-- a client writing its own attributes changes nothing on the server (they do not replicate up; the
	-- server never reads its own values back from Instances): the next server write overwrites them
	p:SetAttribute("Coins", 1e9)
	local tiles = h.workspace.Farms["Farm_" .. p:GetAttribute("Slot")].Tiles
	tapTile(p, tiles.Tile_1_1)
	h:advance(0.2)
	truthy(p:GetAttribute("Coins") < 1e6, "a forged Coins attribute is overwritten by the server's own value on the next action")
end

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow wire: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow wire check failed", 0) end
