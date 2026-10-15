-- Outpost Zero — the brag moment: the Grand Airship, through the real server and client.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_airship.luau 2>&1
--
-- DESIGN 8: the purchase that takes the population to 6 400 opens the Skyport; the server adds the mooring mast and
-- tells every client (Announce), each client flies its own copy in over 12 s, the owner gets the title card, and
-- then the server places the moored airship for everyone and a public toast. The only flag is the cosmetic
-- airshipSeen, saved when the flight finishes; a player who leaves mid-flight sees it once more on the next join.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local OWNER, WATCHER, LEAVER = 3131, 3232, 3333
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
for _, id in { OWNER, LEAVER } do
	store:SetAsync("u_" .. id, { data = { v = 1, seed = id, credits = 1e12, lifetime = 1e12, lots = {}, savedAt = os.time(),
		ordersUntil = os.time() + 600, popAt = 0, airshipSeen = false, tutorial = 3 } })
end

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("CityRemotes")
local State, Fx, Announce, Toast = remotes.State, remotes.Fx, remotes.Announce, remotes.Toast

local function stateOf(plr)
	local sent = State:sentTo(plr)
	return sent[#sent].args[1]
end
local function announces(kind)
	local out = {}
	for _, rec in Announce:getSent() do
		local ev = rec.args[1]
		if type(ev) == "table" and ev.kind == kind then table.insert(out, ev) end
	end
	return out
end
local function fxOf(plr, kind)
	local n = 0
	for _, rec in Fx:sentTo(plr) do
		if type(rec.args[1]) == "table" and rec.args[1].kind == kind then n += 1 end
	end
	return n
end
local function buyTo(plr, hrp, shelf, target)
	for _ = 1, 5000 do
		local st = stateOf(plr)
		if st.population >= target or st.star == nil then break end
		local post = shelf.Lots:FindFirstChild("Lot_" .. st.star.key).Post
		hrp.CFrame = CFrame.new(post.Position + Vector3.new(0, 1.5, 0))
		post.BuildPrompt.Triggered:Fire(plr)
		h:advance(0.13)
	end
	return stateOf(plr).population
end

local owner = h:join("Captain", OWNER)
local co = h.Players:simulateSpawn(owner, h.workspace)
local watcher = h:join("Watcher", WATCHER)
h.Players:simulateSpawn(watcher, h.workspace)
h:advance(1)
local shelf = owner.RespawnLocation.Parent
local hrp = co:FindFirstChild("HumanoidRootPart")

--============================================================================ 1. below the Skyport: no airship
local p = buyTo(owner, hrp, shelf, 6000)
truthy(p < 6400 and p >= 900, "set-up: population " .. p .. ", the Sky-Rail Yard open, the Skyport not yet")
eq(#announces("airship"), 0, "no airship below 6 400")
eq(shelf.TownHall:FindFirstChild("MooringMast"), nil, "no mooring mast yet")
eq(shelf:FindFirstChild("Airship"), nil, "no airship moored")

--============================================================================ 2. the Skyport purchase
local before = #Announce:getSent()
p = buyTo(owner, hrp, shelf, 6400)
truthy(p >= 6400, "set-up: the purchase that opens the Skyport (" .. p .. ")")
local arrivals = announces("airship")
eq(#arrivals, 1, "it announces the Grand Airship to the whole server, once")
local ev = arrivals[1]
if ev then
	eq(ev.seconds, 12, "a 12-second flight")
	eq(ev.shelf, tonumber(string.match(shelf.Name, "%d+")), "to this shelf")
	local mast = Vector3.new(ev.mast[1], ev.mast[2], ev.mast[3])
	local hall = shelf.TownHall.HallBody.Position
	truthy(math.abs(mast.X - hall.X) < 1e-6 and math.abs(mast.Z - hall.Z) < 1e-6, "its mast stands over the Town Hall")
	truthy(mast.Y >= 120, string.format("at the hull line (y %.1f >= 120)", mast.Y))
	truthy(Announce:getSent()[before + 1] ~= nil and Announce:getSent()[before + 1].all, "sent with FireAllClients (everyone flies a copy)")
end
truthy(shelf.TownHall:FindFirstChild("MooringMast") ~= nil, "the Town Hall gains its mooring mast at once (public)")
eq(fxOf(owner, "airship"), 1, "the owner gets the title card's cue")
eq(fxOf(watcher, "airship"), 0, "the watcher does not (it is the owner's card)")
eq(stateOf(owner).airship, "flying", "the owner's State says flying")
eq(shelf:FindFirstChild("Airship"), nil, "nothing is moored during the flight")

--============================================================================ 3. the mooring, 12 s later
h:advance(11)
eq(shelf:FindFirstChild("Airship"), nil, "11 s in: still flying")
h:advance(1.5)
local ship = shelf:FindFirstChild("Airship")
truthy(ship ~= nil, "12 s in: the server places the moored Grand Airship")
if ship then
	local n = 0
	local lowest = math.huge
	for _, d in ship:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
			lowest = math.min(lowest, d.Position.Y - d.Size.Y / 2)
		end
	end
	eq(n, 12, "12 parts")
	truthy(math.abs(lowest - 120) < 0.05, string.format("its hull bottom at y = 120 (%.2f), 30 studs over the tallest roof", lowest))
	local lamp = ship:FindFirstChild("Lamp")
	truthy(lamp and lamp:FindFirstChildOfClass("PointLight") ~= nil, "with the gold glow on the gondola lamp")
end
local toasts = announces("text")
truthy(#toasts >= 1 and string.find(toasts[#toasts].text, "Captain's city welcomed the Grand Airship", 1, true) ~= nil,
	"the whole server is told: " .. tostring(toasts[#toasts] and toasts[#toasts].text))
eq(fxOf(owner, "moored"), 1, "the owner gets the docking flash")
eq(stateOf(owner).airship, "moored", "the State says moored")
-- the flag saves
h:advance(8)
local saved = store:GetAsync("u_" .. OWNER)
eq(saved and saved.data.airshipSeen, true, "airshipSeen is saved after the flight")
-- buying on never announces it again
local n0 = #announces("airship")
buyTo(owner, hrp, shelf, 9000)
eq(#announces("airship"), n0, "later purchases never fly it in again")

--============================================================================ 4. a rejoin after it docked: moored at once, no flight
h:leave(owner)
h:advance(1)
eq(shelf:FindFirstChild("Airship"), nil, "leaving clears the airship off the freed shelf")
local owner2 = h:join("Captain", OWNER)
h.Players:simulateSpawn(owner2, h.workspace)
h:advance(1)
local shelf2 = owner2.RespawnLocation.Parent
truthy(shelf2:FindFirstChild("Airship") ~= nil, "a returning Skyport city has its airship moored from the start")
h:advance(5)
eq(#announces("airship"), n0, "and it does not fly in again")

--============================================================================ 5. leaving mid-flight replays it once
do
	local leaver = h:join("Drifter", LEAVER)
	local cl = h.Players:simulateSpawn(leaver, h.workspace)
	h:advance(1)
	local sh = leaver.RespawnLocation.Parent
	buyTo(leaver, cl:FindFirstChild("HumanoidRootPart"), sh, 6400)
	local flights0 = #announces("airship")
	truthy(flights0 > n0, "set-up: Drifter's Skyport purchase announced its airship")
	h:advance(4)
	h:leave(leaver) -- 4 s into a 12 s flight
	h:advance(1)
	local rec = store:GetAsync("u_" .. LEAVER)
	eq(rec and rec.data.airshipSeen, false, "leaving mid-flight saves airshipSeen = false")
	local back = h:join("Drifter", LEAVER)
	h.Players:simulateSpawn(back, h.workspace)
	h:advance(1)
	local sh2 = back.RespawnLocation.Parent
	eq(sh2:FindFirstChild("Airship"), nil, "on the rejoin it is not moored yet")
	h:advance(3)
	eq(#announces("airship"), flights0 + 1, "the flight replays once, a moment after the join")
	h:advance(13)
	truthy(sh2:FindFirstChild("Airship") ~= nil, "and moors")
	h:advance(8)
	eq(store:GetAsync("u_" .. LEAVER).data.airshipSeen, true, "this time airshipSeen is saved")
	h:advance(20)
	eq(#announces("airship"), flights0 + 1, "and it never replays again")
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero airship: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero airship check failed", 0) end
