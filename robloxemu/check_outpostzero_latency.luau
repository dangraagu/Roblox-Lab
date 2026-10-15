-- Outpost Zero — the server when the DataStore takes time, as a real one always does (REVIEW-1 F1, F2).
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_latency.luau 2>&1
--
-- robloxemu's UpdateAsync never yields, so no other gate can see a purchase land INSIDE a profile write, or a player
-- arrive while a leaver's save is still in flight. Here every profile UpdateAsync and every Census SetAsync first
-- waits LAT seconds of virtual time, and os.time() follows the virtual clock, so `popAt` moves as play goes on.
-- A ledger records every (population, popAt) pair a profile write actually saved; the Census may only ever hold one
-- of those pairs (the reviewers' scratch checks check_ozx_race*, check_ozx_kick* are the origin of A-C).
--   A. a storey that raises the population, bought while a flush is in flight
--   B. two finished cities: the one that finished FIRST ranks first, even when the other finished during a write
--   C. a full server: a player arriving while a leaver's save is in flight gets the freed shelf, not a kick
--   D. a leaver whose Grand Airship is still flying never moors it on the next owner's shelf

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- os.time() on the virtual clock (set before the server runs, so the game reads this one)
local realOs = os
local BASE = realOs.time()
os = setmetatable({ time = function(t) if t then return realOs.time(t) end return BASE + math.floor(h.scheduler:now()) end }, { __index = realOs })

local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("OutpostZero_Census_v1")
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(n) return h:_require(RS:FindFirstChild(n)) end
local Config, Economy, City, Rng, Board = mod("Config"), mod("Economy"), mod("City"), mod("Rng"), mod("Board")
local remotes = RS:FindFirstChild("CityRemotes")
local function stateOf(plr)
	local sent = remotes.State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function popOf(data)
	local L = City.layout(Config, data.seed, Rng)
	local lots = {}
	for k, v in data.lots do lots[k] = v end
	return Economy.newState(Config, L, lots, data.credits).pop
end

-- the latency shim and the ledger
local LAT = 0.4
local latOf: { [string]: number } = {} -- per-key overrides
local inFlight: { [string]: number } = {}
local saved: { [string]: { [string]: boolean } } = {}
local boardWrites: { [string]: { number } } = {}
local boardWroteAt: { [string]: number } = {}
local origUA, origSet = store.UpdateAsync, board.SetAsync
store.UpdateAsync = function(self, k, f)
	inFlight[k] = (inFlight[k] or 0) + 1
	task.wait(latOf[k] or LAT)
	local r = table.pack(pcall(origUA, self, k, f))
	inFlight[k] -= 1
	if not r[1] then error(r[2], 0) end
	local rec = self.__data[k]
	if type(rec) == "table" and type(rec.data) == "table" and rec.data.seed then
		saved[k] = saved[k] or {}
		saved[k][popOf(rec.data) .. "@" .. tostring(rec.data.popAt)] = true
	end
	return table.unpack(r, 2, r.n)
end
board.SetAsync = function(self, k, v)
	task.wait(LAT)
	boardWrites[k] = boardWrites[k] or {}
	table.insert(boardWrites[k], v)
	boardWroteAt[k] = h.scheduler:now()
	return origSet(self, k, v)
end

local function join(name, uid)
	local plr = h:join(name, uid)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	return plr, char:FindFirstChild("HumanoidRootPart")
end
local function press(plr, hrp, key)
	local post = plr.RespawnLocation.Parent.Lots:FindFirstChild("Lot_" .. key).Post
	hrp.CFrame = CFrame.new(post.Position + Vector3.new(0, 1.5, 0))
	post.BuildPrompt.Triggered:Fire(plr)
end
-- every Census value ever written for this key is a pair a profile write saved
local function boardHonest(k)
	local bad, n = {}, 0
	for _, v in boardWrites[k] or {} do
		n += 1
		local p, at = Board.decode(Config, v)
		if not (saved[k] and saved[k][p .. "@" .. at]) then
			table.insert(bad, string.format("pop %d popAt %+d", p, at - BASE))
		end
	end
	return bad, n
end

--============================================================================ A. a population-raising storey bought inside a flush
local P_ID = 9001
local P, pHrp = join("Racer", P_ID)
h:advance(3)
eq(stateOf(P).loaded, true, "set-up: the player's city loaded (every DataStore call took " .. LAT .. " s)")
do
	-- play the ★ for 4 minutes, then stop for 75 s: the last flush lands, the Census catches up, its minute re-opens
	local t0 = h.scheduler:now()
	while h.scheduler:now() - t0 < 240 do
		local st = stateOf(P)
		if st.star and st.credits >= st.star.price then press(P, pHrp, st.star.key) end
		h:advance(0.5)
	end
	h:advance(75)
	-- two purchases: L on the long side (no population change; it makes a write pending), S on the short side
	local function sideLot(zone)
		local best, bp = nil, math.huge
		for _, m in P.RespawnLocation.Parent.Lots:GetChildren() do
			local pr = m.Post.BuildPrompt
			if pr.Enabled and string.find(pr.ObjectText, if zone == "H" then "^Home" else "^Workshop") then
				local s = tonumber(string.match(pr.ObjectText, "(%d+)/"))
				local key = string.sub(m.Name, 5)
				local p = Economy.price(Config, tonumber(string.sub(key, 1, 1)), s + 1)
				if p and p < bp then best, bp = key, p end
			end
		end
		return best, bp
	end
	local st = stateOf(P)
	if st.settlers == st.jobs then
		local k = sideLot("H")
		press(P, pHrp, k)
		h:advance(0.2)
		st = stateOf(P)
	end
	local short = if st.settlers < st.jobs then "H" else "W"
	local long = if short == "H" then "W" else "H"
	local kL, pL = sideLot(long)
	local kS, pS = sideLot(short)
	-- bounded: a broken economy must fail this check, not hang it
	local waited = 0
	while stateOf(P).credits < pL + pS and waited < 900 do h:advance(1); waited += 1 end
	truthy(stateOf(P).credits >= pL + pS, string.format("set-up: both storeys affordable within 15 min (%.0f of %.0f)", stateOf(P).credits, pL + pS))
	-- the Census's once-a-minute gate must be OPEN when the write lands (as it is for any player who builds
	-- something a minute after their last population rise)
	while h.scheduler:now() - (boardWroteAt["u_" .. P_ID] or -math.huge) < 62 do h:advance(1) end
	local pop0 = stateOf(P).population
	press(P, pHrp, kL)
	h:advance(0.05)
	eq(stateOf(P).population, pop0, "set-up: the long-side storey changes no population, and makes a write pending")
	local k = "u_" .. P_ID
	local guard = 0
	while (inFlight[k] or 0) == 0 and guard < 400 do h:advance(0.05); guard += 1 end
	truthy((inFlight[k] or 0) > 0, "set-up: a profile flush is in flight")
	h:advance(LAT / 3)
	press(P, pHrp, kS)
	local popS = stateOf(P).population
	truthy(popS > pop0, string.format("set-up: the short-side storey, bought INSIDE the write, raises the population %d -> %d", pop0, popS))
	h:advance(4)
	h:advance(70) -- the next flush lands (it holds popS) and the Census's minute re-opens
	local bad, n = boardHonest(k)
	print(string.format("  A: %d Census writes for the racer; pairs no save holds: %s", n, if #bad == 0 then "none" else table.concat(bad, ", ")))
	truthy(n >= 2, "set-up: the Census was written more than once")
	eq(#bad, 0, "the Census only ever holds a (population, popAt) pair a profile write saved together")
	local rec = store.__data[k].data
	local bp, bat = Board.decode(Config, board.__data[k])
	eq(bp, popOf(rec), "the Census ends at the saved population")
	eq(bat, rec.popAt, "...with the saved record's popAt (when that population was REACHED)")
end

--============================================================================ B. who finished first ranks first
local X_ID, Y_ID = 7001, 7002
local SEED_B = 4242
local lastKey
do
	local L = City.layout(Config, SEED_B, Rng)
	local lots = {}
	for _, l in L.lots do
		lots[l.key] = 22
		if l.d == 6 and l.zone == "H" and lastKey == nil then lastKey = l.key end
	end
	lots[lastKey] = 21 -- one storey short of the complete city
	local function profile(popAt)
		local T = os.time()
		return { lockUntil = 0, data = { v = 1, seed = SEED_B, credits = 1e8, lifetime = 1e9, lots = table.clone(lots), savedAt = T,
			ordersUntil = T + 600, popAt = popAt, airshipSeen = true, tutorial = 3 } }
	end
	origUA(store, "u_" .. X_ID, function() return profile(BASE - 900) end)
	origUA(store, "u_" .. Y_ID, function() return profile(BASE - 600) end)
end
local X, xHrp = join("Xenia", X_ID)
local Y, yHrp = join("Yusuf", Y_ID)
h:advance(3)
local tX, tY
do
	eq(stateOf(X).population, Config.Board.MaxPopulation - 12500, "set-up: X is one Crown Heights storey short")
	h:advance(27)
	local g = 0
	while (inFlight["u_" .. X_ID] or 0) > 0 and g < 400 do h:advance(0.05); g += 1 end
	tX = os.time()
	press(X, xHrp, lastKey)
	eq(stateOf(X).population, Config.Board.MaxPopulation, "X completes the city first, with no write in flight")
	h:advance(32)
	local guard = 0
	while (inFlight["u_" .. Y_ID] or 0) == 0 and guard < 2000 do h:advance(0.05); guard += 1 end
	truthy((inFlight["u_" .. Y_ID] or 0) > 0, "set-up: an autosave of Y's city is in flight")
	tY = os.time()
	press(Y, yHrp, lastKey)
	eq(stateOf(Y).population, Config.Board.MaxPopulation, "Y completes it later, during that write")
	h:advance(130)
	local rows = {}
	for _, uid in { X_ID, Y_ID } do
		local v = board.__data["u_" .. uid]
		local p, at = Board.decode(Config, v)
		local rec = store.__data["u_" .. uid].data
		print(string.format("  B: %s board pop %d popAt %+d | saved popAt %+d", if uid == X_ID then "X" else "Y", p, at - BASE, rec.popAt - BASE))
		eq(at, rec.popAt, string.format("%s's Census popAt is the saved one", if uid == X_ID then "X" else "Y"))
		table.insert(rows, { userId = uid, value = v })
	end
	local ranked = Board.rank(Config, rows)
	eq(ranked[1].userId, X_ID, string.format("the Census ranks X (finished at %+d) above Y (finished at %+d)", tX - BASE, tY - BASE))
	local bx = boardHonest("u_" .. X_ID)
	local by = boardHonest("u_" .. Y_ID)
	eq(#bx + #by, 0, "and neither ever held a pair no save holds")
end

--============================================================================ C. a full server: the freed shelf goes to the next player
local others = {}
do
	for i = 1, 3 do
		local plr = join("Filler" .. i, 8000 + i)
		others[i] = plr
	end
	h:advance(4)
	local n = 0
	for _, s in h.workspace.Shelves:GetChildren() do
		if s.TownHall.HallBody.OwnerSign.Text.Text ~= "Free shelf" then n += 1 end
	end
	eq(n, 6, "set-up: all 6 shelves are taken")
	-- the leaver builds, so a flush is pending; it leaves while that flush is in flight
	local L, lHrp = others[3], others[3].Character:FindFirstChild("HumanoidRootPart")
	local lk = "u_" .. L.UserId
	local st = stateOf(L)
	press(L, lHrp, st.star.key)
	h:advance(0.05)
	local guard = 0
	while (inFlight[lk] or 0) == 0 and guard < 400 do h:advance(0.05); guard += 1 end
	truthy((inFlight[lk] or 0) > 0, "set-up: the leaver's flush is in flight")
	local leaverShelf = L.RespawnLocation.Parent
	local lotsAtLeave = 0
	for _, m in leaverShelf.Lots:GetChildren() do
		if m:FindFirstChild("Body") then lotsAtLeave += 1 end
	end
	task.spawn(function() h:leave(L) end)
	h:advance(0.2)
	local N, nHrp = join("Newcomer", 8100)
	h:advance(0.1)
	eq(rawget(N, "__kicked"), nil, "a player arriving 0.2 s after a leave, with the leaver's save still in flight, is not kicked")
	eq(N.RespawnLocation and N.RespawnLocation.Parent, leaverShelf, "...and gets the freed shelf")
	h:advance(3)
	eq(stateOf(N).loaded, true, "the newcomer's city loads")
	h:advance(5) -- the leaver's writes land (one waits for the other)
	eq(leaverShelf.TownHall.HallBody.OwnerSign.Text.Text, "🏙️ Newcomer's city", "after the leaver's save lands, the shelf still names the newcomer")
	local built = 0
	for _, m in leaverShelf.Lots:GetChildren() do
		if m:FindFirstChild("Body") then built += 1 end
	end
	eq(built, 0, string.format("...and shows the newcomer's empty city, none of the leaver's %d buildings", lotsAtLeave))
	local rec = store.__data[lk]
	eq(rec.lockUntil, 0, "the leaver's save landed and released the lock")
	local storeys = 0
	for _, s in rec.data.lots do storeys += s end
	truthy(storeys > 0, "...with the leaver's city in it (" .. storeys .. " storeys)")
	local nst = stateOf(N)
	press(N, nHrp, nst.star.key)
	h:advance(0.5)
	truthy(stateOf(N).credits < 30, "the newcomer can build on the shelf")
	others[3] = N
end

--============================================================================ D. a leaver's airship in flight never moors on the next owner's shelf
do
	-- Z: districts 1-3, every Home topped, Workshops 9 storeys short: population 6 384. One Sky-Rail Workshop storey
	-- (+100) opens the Skyport at 6 484 and starts the Grand Airship's 12 s flight.
	local Z_ID, SEED_Z = 7100, 5151
	local L = City.layout(Config, SEED_Z, Rng)
	local lots, wLots = {}, {}
	for _, l in L.lots do
		if l.d <= 3 then
			lots[l.key] = 22
			if l.d == 3 and l.zone == "W" then table.insert(wLots, l.key) end
		end
	end
	lots[wLots[3]] = 4 -- 3 x 22 x 124 Homes = 8 184 settlers; Workshops 264 + 1 320 + 4 800 = 6 384 jobs
	origUA(store, "u_" .. Z_ID, function()
		local T = os.time()
		return { lockUntil = 0, data = { v = 1, seed = SEED_Z, credits = 1e9, lifetime = 1e9, lots = lots, savedAt = T,
			ordersUntil = T + 600, popAt = T - 60, airshipSeen = false, tutorial = 3 } }
	end)
	local F = others[2]
	task.spawn(function() h:leave(F) end) -- room for Z
	h:advance(3)
	local Z, zHrp = join("Zephyr", Z_ID)
	h:advance(3)
	eq(stateOf(Z).population, 6384, "set-up: Z's city holds 6 384")
	local zShelf = Z.RespawnLocation.Parent
	press(Z, zHrp, wLots[3])
	h:advance(0.1)
	eq(stateOf(Z).airship, "flying", "set-up: the Grand Airship is flying in to Z's city")
	latOf["u_" .. Z_ID] = 20 -- Z's save is slow (throttled): it is in flight longer than the 12 s flight
	task.spawn(function() h:leave(Z) end)
	h:advance(0.2)
	local N2 = join("Nadia", 8200)
	h:advance(0.1)
	eq(rawget(N2, "__kicked"), nil, "set-up: the next player is not kicked")
	eq(N2.RespawnLocation and N2.RespawnLocation.Parent, zShelf, "set-up: ...and takes Z's freed shelf")
	h:advance(16)
	eq(zShelf:FindFirstChild("Airship"), nil, "the flight's end does not moor Z's airship on the new owner's shelf")
	eq(zShelf.TownHall:FindFirstChild("MooringMast"), nil, "...nor leave Z's mooring mast there")
	local welcomed = 0
	for _, rec in remotes.Announce:sentTo(N2) do
		local ev = rec.args[1]
		if type(ev) == "table" and ev.kind == "text" and string.find(ev.text, "Zephyr", 1, true) then welcomed += 1 end
	end
	eq(welcomed, 0, "and nobody is told Z's city welcomed it")
	h:advance(30)
	local zrec = store.__data["u_" .. Z_ID]
	eq(zrec.lockUntil, 0, "Z's slow save lands")
	eq(zrec.data.lots[wLots[3]], 5, "...with the storey that opened the Skyport")
	eq(zrec.data.airshipSeen, false, "...and the flight unwatched, so it plays once more at Z's next join")
end

--============================================================================ shared by E and F: a city mid-play, a flush in flight
local function liveStoreys(plr)
	local n = 0
	for _, m in plr.RespawnLocation.Parent.Lots:GetChildren() do
		n += tonumber(string.match(m.Post.BuildPrompt.ObjectText, "(%d+)/")) or 0
	end
	return n
end
local function storeysIn(lots)
	local n = 0
	for _, v in lots do n += v end
	return n
end
-- play the ★ for `seconds`, wait for one more storey, buy it, wait until the flush it makes is in flight, then buy
-- up to 3 more storeys INSIDE that flush; returns how many were bought inside
local function playIntoFlush(plr, hrp, seconds)
	local k = "u_" .. plr.UserId
	local t0 = h.scheduler:now()
	while h.scheduler:now() - t0 < seconds do
		local st = stateOf(plr)
		if st.star and st.credits >= st.star.price then press(plr, hrp, st.star.key) end
		h:advance(0.5)
	end
	h:advance(20)
	local g = 0
	while stateOf(plr).credits < stateOf(plr).star.price and g < 600 do h:advance(0.5); g += 1 end
	press(plr, hrp, stateOf(plr).star.key)
	g = 0
	while (inFlight[k] or 0) == 0 and g < 400 do h:advance(0.05); g += 1 end
	truthy((inFlight[k] or 0) > 0, "set-up: " .. plr.Name .. "'s flush is in flight")
	local bought = 0
	for _ = 1, 6 do
		local s2 = stateOf(plr)
		if bought < 3 and s2.star and s2.credits >= s2.star.price then press(plr, hrp, s2.star.key); bought += 1 end
		h:advance(0.01)
	end
	return bought
end

--============================================================================ E. a hop to another server while a flush is in flight
-- (round 2, finding A1) The flush that is in flight when the player leaves must not release the lock: it carries the
-- city as it was before the last storeys, and a load on another server landing between it and the leave-write would
-- take that older city, and its new token would then cancel the leave-write. Server B is modelled by Main's own lock
-- rule (a live lock held by another JobId is not acquired) run against the store every 0.05 s, observing only.
do
	task.spawn(function() h:leave(others[1]) end) -- room for H
	h:advance(3)
	local H_ID = 7200
	local hk = "u_" .. H_ID
	latOf[hk] = 2.0 -- a slow DataStore (throttled): the window is about as long as one call
	local H, hHrp = join("Hopper", H_ID)
	h:advance(6)
	local bought = playIntoFlush(H, hHrp, 180)
	truthy(bought >= 1, "set-up: storeys bought inside the flush (" .. bought .. ")")
	local atLeave = liveStoreys(H)
	local tLeave = h.scheduler:now()
	task.spawn(function() h:leave(H) end)
	local firstAt, staleReads, reads = nil, 0, 0
	for _ = 1, 300 do
		h:advance(0.05)
		local got = nil
		origUA(store, hk, function(old)
			old = old or {}
			if (tonumber(old.lockUntil) or 0) > os.time() and old.jobId ~= "serverB" then return nil end
			got = old.data
			return nil -- observe only
		end)
		if got then
			reads += 1
			if firstAt == nil then firstAt = h.scheduler:now() - tLeave end
			if storeysIn(got.lots) < atLeave then staleReads += 1 end
		end
	end
	print(string.format("  E: %d storeys at the leave; server B could first load at leave+%s s; loads that would get an older city: %d of %d",
		atLeave, if firstAt then string.format("%.2f", firstAt) else "never", staleReads, reads))
	truthy(firstAt ~= nil, "server B can load the city once the leaver's save has landed")
	eq(staleReads, 0, "server B can never load an older city than the one the player left with")
	local rec = store.__data[hk]
	eq(storeysIn(rec.data.lots), atLeave, "the leave-write landed with every storey")
	eq(rec.lockUntil, 0, "...and released the lock")
end

--============================================================================ F. a rejoin to the SAME server while the leave-write is in flight
-- (round 2, finding A1, second path) The lock rule treats this server's own JobId as free, so a quick rejoin here
-- would load before the leave-write lands, take the lock with a new token, and cancel the leave-write.
do
	local R_ID = 7300
	local rk = "u_" .. R_ID
	local R, rHrp = join("Rejoiner", R_ID)
	h:advance(6)
	local bought = playIntoFlush(R, rHrp, 180)
	truthy(bought >= 1, "set-up: storeys bought inside the flush (" .. bought .. ")")
	local atLeave = liveStoreys(R)
	local popAtLeave = stateOf(R).population
	task.spawn(function() h:leave(R) end)
	h:advance(0.3)
	local R2 = join("Rejoiner", R_ID)
	h:advance(LAT * 6 + 5)
	local st2 = stateOf(R2)
	eq(st2.loaded, true, "the rejoined city loads")
	eq(st2.population, popAtLeave, "a rejoin 0.3 s after the leave gets the population the player left with")
	eq(liveStoreys(R2), atLeave, "...and every storey")
	eq(st2.saving, true, "...and this session saves")
	h:advance(70)
	eq(storeysIn(store.__data[rk].data.lots), atLeave, "the record holds every storey")
	others[1] = R2
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero latency: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero latency check failed", 0) end
