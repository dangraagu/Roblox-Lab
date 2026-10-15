-- Gnome Garden Defense: the day's endless bed when its DataStore blips or is down (REVIEW-1).
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_daily.luau
--
-- Every endless gardener plays the same bed each UTC day: the first server to ask draws it and keeps it in the
-- DataStore, and the public board ranks everyone on it. REVIEW-1 found that ONE failed read cached a bed of this
-- server's own for the rest of the day. Now a failed read is retried, and when the store is down the server's own
-- bed is used for DailyFallbackSeconds only; after that the store is asked again (and a restart asks again).

local Harness = require("./emu/harness")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local Rng = require("../gnome-garden-defense/src/shared/Rng")
local Cfg = require("../gnome-garden-defense/src/shared/Config")
-- spelled out, not read from Config (a rule checked against itself is not a rule): 3 tries, a 60 s fallback
local TRIES, FALLBACK_SECONDS = 3, 60
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-daily", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local DSS = h.game:GetService("DataStoreService")
local store = DSS:GetDataStore("GnomeGarden_v1")
local daily = DSS:GetDataStore("GnomeGarden_Daily_v1")
local SHARED = 123456789 -- the bed another server drew today
local day = math.floor(os.time() / 86400)
daily:SetAsync("d_" .. day, SHARED)
local dailyCalls = 0
do
	local orig = daily.UpdateAsync
	daily.UpdateAsync = function(self, k, f)
		dailyCalls += 1
		return orig(self, k, f)
	end
end
local E1, E2, E3 = 9301, 9302, 9303
for _, uid in { E1, E2, E3 } do
	store:SetAsync("u_" .. uid, { data = { chapter = 5, bestWave = 41, bestAt = 1700000000, published = 41, tutorialDone = true } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local R = h.ReplicatedStorage.GardenRemotes
local info = h.game:GetService("ServerStorage"):FindFirstChild("GardenInfo")
local function fire(plr, name, ...)
	h.Players.LocalPlayer = plr
	R[name]:FireServer(...)
end
local function gardenOf(uid)
	for _, g in h.workspace.Gardens:GetChildren() do
		if g:GetAttribute("Owner") == uid then return g end
	end
	return nil
end
local function bedSeed(uid)
	local f = info:FindFirstChild(tostring(uid))
	return f and f:GetAttribute("BedSeed")
end
local function join(name, uid)
	local out
	task.spawn(function() out = h:join(name, uid) end)
	return function() return out end
end
local sharedCells = PathGen.encodeCells(PathGen.genPath(Cfg, Rng.new(SHARED)).cells)

--============================================================ the store is down: a bed of the server's own, for a while
daily.__failAll = true
local get1 = join("Endless1", E1)
h:advance(5) -- three tries, 1 s then 2 s apart
local e1 = get1()
local g1 = gardenOf(E1)
truthy(g1 ~= nil and g1:GetAttribute("Phase") == "reveal", "with the day's store down an endless gardener still gets a bed")
truthy(bedSeed(E1) ~= nil and bedSeed(E1) ~= SHARED, "(this server's own, for now: " .. tostring(bedSeed(E1)) .. ")")
eq(dailyCalls, TRIES, "after asking the store " .. TRIES .. " times")

--============================================================ still down: TRY AGAIN keeps that one bed (REVIEW-2)
-- The fallback is asked to the store again every 60 s, but while the store stays down the answer must be the SAME
-- bed: drawing a new one on each try let a gardener lose fast, wait out the minute and reroll until an easy bed
-- came up, then post its wave on the shared board (REVIEW-2: 7 different endless beds on 7 restarts).
do
	local fallback = bedSeed(E1)
	local distinct, seen = 1, { [fallback] = true }
	local lastDraw = h.scheduler:now()
	for _ = 1, 3 do
		fire(e1, "Plant", 1, "pebble")
		fire(e1, "Ready")
		local guard = 0
		while g1:GetAttribute("Phase") ~= "lost" and guard < 2000 do
			h:advance(1)
			guard += 1
			if g1:GetAttribute("Phase") == "build" then fire(e1, "Ready") end
		end
		h:advance(math.max(0, FALLBACK_SECONDS + 1 - (h.scheduler:now() - lastDraw)))
		task.spawn(fire, e1, "Restart") -- the draw yields on the store: off this thread
		h:advance(6) -- three more tries of the store, all failing
		lastDraw = h.scheduler:now()
		local s = bedSeed(E1)
		if s ~= nil and not seen[s] then
			seen[s] = true
			distinct += 1
		end
	end
	eq(distinct, 1, "while the store stays down, three TRY AGAINs a minute apart all get this server's one fallback bed")
	truthy(dailyCalls > TRIES, "(the store was asked again meanwhile: " .. dailyCalls .. " calls)")
end

--============================================================ it comes back; one more blip; the next joiner gets the day's bed
daily.__failAll = false
h:advance(FALLBACK_SECONDS + 1)
daily.__failNext = true
local callsBefore = dailyCalls
local get2 = join("Endless2", E2)
h:advance(3)
eq(bedSeed(E2), SHARED, "one failed read is retried: the next endless gardener plays the day's shared bed")
eq(gardenOf(E2) and gardenOf(E2):GetAttribute("PathCells"), sharedCells, "(its path is the shared bed's)")
eq(dailyCalls - callsBefore, 2, "(one failed read, one retry)")
local get3 = join("Endless3", E3)
h:advance(1)
eq(bedSeed(E3), SHARED, "and so does every later one on this server")

--============================================================ the first gardener's next attempt asks again
do
	fire(e1, "Plant", 1, "pebble")
	fire(e1, "Ready")
	local guard = 0
	while g1:GetAttribute("Phase") ~= "lost" and guard < 2000 do
		h:advance(1)
		guard += 1
		if g1:GetAttribute("Phase") == "build" then fire(e1, "Ready") end
	end
	eq(g1:GetAttribute("Phase"), "lost", "(one pebble loses the endless bed)")
	fire(e1, "Restart")
	h:advance(1)
	eq(bedSeed(E1), SHARED, "TRY AGAIN puts the gardener who started on a fallback onto the day's shared bed")
	eq(g1:GetAttribute("PathCells"), sharedCells, "(the shared path)")
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no server thread died")
print(("gnome garden daily: %d passed, %d failed"):format(passed, failed))
