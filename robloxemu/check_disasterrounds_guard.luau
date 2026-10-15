-- Disaster Rounds - the movement guard, through the real server. Run: luau check_disasterrounds_guard.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- DESIGN.md §2.7 and §10: a counted player whose server-seen root moves more than Guard.MaxStuds (28) in any trailing
-- 1.0 s, or leaves the island box by more than Guard.BoxMargin (4), is swept out with "Movement check failed". It is
-- what stops a teleport or speed hack from escaping the red, and so what keeps the board's streaks honest. The pure
-- rule is in tests/Guard.spec.luau; this file asks the running server:
--   1. a 27-stud jump inside one second is allowed; a 29-stud jump is not (the threshold, both sides);
--   2. walking at 16 studs/s for a whole round never trips it, and neither do the server's own teleports (drops);
--   3. walking out of the island box is caught;
--   4. a practice player is never guarded (a practice round counts for nothing, so there is nothing to protect).
-- Aimed rings are switched off (Config.Strikes.FirstAfterSeconds), so every sweep here is the guard's.

local SEED = 880088
local Datatypes = require("./emu/datatypes")
do
	local realNew = Datatypes.Random.new
	local n = SEED
	Datatypes.Random.new = function(seed)
		if seed == nil then
			n += 1
			return realNew(n * 7919)
		end
		return realNew(seed)
	end
end
local CFrame = Datatypes.CFrame
local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local MapGen = h:_require(RS:FindFirstChild("MapGen"))
local IC = Config.Island
local rf = h.workspace:FindFirstChild("Round")
local remotes = RS:FindFirstChild("DRRemotes")
local card = remotes:FindFirstChild("Card")
local HALF = MapGen.halfSize(IC)
local GUARD_TEXT = "Movement check failed: you moved faster than walking. Round lost."

Config.Strikes.FirstAfterSeconds = 1e6 -- no aimed rings: every sweep in this file is the guard's
Config.Shots.ForceKind = "meteor" -- with no rings, a Meteor Shower has no threat at all

local A = h:join("Hopper", 5101)
h.Players:simulateSpawn(A, h.workspace)
local W = h:join("Walker", 5102)
h.Players:simulateSpawn(W, h.workspace)
local P = h:join("Visitor", 5103)
h.Players:simulateSpawn(P, h.workspace)

local function root(p) return p.Character:FindFirstChild("HumanoidRootPart") end
local function now(): number return h.scheduler:now() end
local function cellY(x: number, z: number): number
	local i, j = MapGen.cellAt(IC, x, z)
	local island = rf:FindFirstChild("Island")
	local c = i and island and island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
	return MapGen.topY(IC, if c then c:GetAttribute("Level") else 0) + 3
end
local function put(p, x: number, z: number)
	root(p).CFrame = CFrame.new(x, cellY(x, z), z)
end
local function swept(p): { string }
	local out = {}
	for _, rec in card:sentTo(p) do
		if rec.args[1] == "swept" then table.insert(out, tostring(rec.args[2] and rec.args[2].text)) end
	end
	return out
end
-- the walker paces a 16-stud line at exactly 16 studs/s around the spot it landed on, all round
local walkFrom, walkDir, walkS = nil, 1, 0
local walked = 0
local function stepWalker(dt: number)
	if (W:GetAttribute("InRound") or "") == "" then
		walkFrom = nil
		return
	end
	local p = root(W).Position
	if walkFrom == nil then
		walkFrom = { x = p.X, z = p.Z }
		walkDir = if p.X > 0 then -1 else 1 -- toward the centre: stays on the island
		walkS = 0
	end
	walkS += 16 * dt
	walked += 16 * dt
	local along = walkS % 32
	local off = if along <= 16 then along else 32 - along
	put(W, walkFrom.x + walkDir * off, walkFrom.z)
end
local function tick(dt: number)
	stepWalker(dt)
	h:advance(dt)
end
local function untilPhase(phase: string, limit: number): boolean
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / 0.1 do
		tick(0.1)
		n += 1
	end
	return rf:GetAttribute("Phase") == phase
end
local function rel(): number return now() - (rf:GetAttribute("NameAt") or now()) end

--======================================================================= 1. the threshold

remotes.SetRest:simulateFireServer(P, true) -- the visitor sits the first round out and jumps in later
card:clearSent()
truthy(untilPhase("disaster", 40), "a round starts")
eq(A:GetAttribute("InRound"), "counted", "Hopper is in it")
eq(W:GetAttribute("InRound"), "counted", "Walker is in it")
while rel() < 2 do tick(0.1) end
-- a 27-stud jump toward the centre: under MaxStuds in the window, allowed
local a = root(A).Position
local d = math.sqrt(a.X * a.X + a.Z * a.Z)
local ux, uz = if d > 1 then -a.X / d else 1, if d > 1 then -a.Z / d else 0
put(A, a.X + ux * 27, a.Z + uz * 27)
for _ = 1, 12 do tick(0.1) end
eq(#swept(A), 0, "a 27-stud jump inside one second is allowed (Guard.MaxStuds 28)")
eq(A:GetAttribute("InRound"), "counted", "Hopper is still in the round")
-- 1.2 s later the window has forgotten it: a 29-stud jump back is caught
local b = root(A).Position
put(A, b.X - ux * 29, b.Z - uz * 29)
local caughtIn = nil
local t0 = now()
for _ = 1, 5 do
	tick(0.1)
	if caughtIn == nil and #swept(A) > 0 then caughtIn = now() - t0 end
end
eq(swept(A)[1], GUARD_TEXT, "a 29-stud jump inside one second sweeps Hopper out, and says why")
truthy(caughtIn ~= nil and caughtIn <= 0.2, string.format("at the next server sample (%.1f s)", caughtIn or -1))
eq(A:GetAttribute("Streak"), 0, "his streak is 0")

--======================================================================= 2. walking, and the server's own teleports

-- the visitor jumps in for practice (a server teleport) and is NOT guarded: a 40-stud jump does nothing
remotes.SetRest:simulateFireServer(P, false)
tick(0.1)
remotes.JumpIn:simulateFireServer(P)
tick(0.1)
eq(P:GetAttribute("InRound"), "practice", "the visitor jumps in for practice")
-- past the guard's quiet second after the landing (a teleport the server made itself), so this jump would count
for _ = 1, 15 do tick(0.1) end
local pp = root(P).Position
local pd = math.sqrt(pp.X * pp.X + pp.Z * pp.Z)
local px, pz = if pd > 1 then -pp.X / pd else 1, if pd > 1 then -pp.Z / pd else 0
put(P, pp.X + px * 40, pp.Z + pz * 40)
for _ = 1, 15 do tick(0.1) end
eq(#swept(P), 0, "a practice player is never guarded: a 40-stud jump is ignored")
eq(P:GetAttribute("InRound"), "practice", "and the visitor is still on the island")
untilPhase("outro", 70)
eq(#swept(W), 0, "16 studs/s for the whole round, and the drop's teleport: never caught")
local survivedCard = false
for _, rec in card:sentTo(W) do
	if rec.args[1] == "survived" then survivedCard = true end
end
truthy(survivedCard, "the walker survives the round")

--======================================================================= 3. the island box

card:clearSent()
truthy(untilPhase("disaster", 40), "the next round starts")
eq(A:GetAttribute("InRound"), "counted", "Hopper is in it")
eq(#swept(W), 0, "a second drop (another teleport) does not trip the walker")
-- Hopper walks straight out along +X at 15 studs/s, past the island's edge
local outAt, outX = nil, nil
local n = 0
while outAt == nil and n < 200 do
	local p = root(A).Position
	root(A).CFrame = CFrame.new(p.X + 1.5, p.Y, p.Z)
	tick(0.1)
	n += 1
	if #swept(A) > 0 then outAt, outX = n, p.X + 1.5 end
end
eq(swept(A)[1], GUARD_TEXT, "walking out of the island is caught by the guard")
truthy(outX ~= nil and outX > HALF + Config.Guard.BoxMargin and outX <= HALF + Config.Guard.BoxMargin + 1.5 + 1e-6,
	string.format("as soon as the root is more than %d studs past the edge (x = %.1f, the edge at %d)", Config.Guard.BoxMargin, outX or -1, HALF))
untilPhase("intermission", 70)
eq(#swept(W), 0, "the walker again survives a whole round")

--======================================================================= 4. one stale position right after the drop (REVIEW-1 F10)

-- The drop is a server PivotTo of a client-owned character. If the server sees the OLD spot (the deck) for one sample
-- shortly after it, that is replication lag, not the player: five laggers, each seen once on the deck 0.05 to 0.8 s
-- after the drop, are all still in the round 2 s later
local lags = { 0.05, 0.15, 0.3, 0.5, 0.8 }
local laggers = {}
for k, lag in lags do
	local p = h:join("Lag" .. k, 5200 + k)
	h.Players:simulateSpawn(p, h.workspace)
	table.insert(laggers, { p = p, lag = lag })
end
untilPhase("intermission", 100)
card:clearSent()
do
	local n = 0
	while rf:GetAttribute("Phase") ~= "drop" and n < 3000 do h:advance(0.01); n += 1 end
end
local dropAt = now()
for _, L in laggers do L.island = root(L.p).CFrame end
local deckCF = CFrame.new(-74, 31.5, 0)
while now() - dropAt < 3 do
	local t = now() - dropAt
	for _, L in laggers do
		if t >= L.lag - 1e-9 and t < L.lag + 0.1 - 1e-9 then
			root(L.p).CFrame = deckCF -- the server sees the old spot for one 0.1 s sample
		else
			root(L.p).CFrame = L.island
		end
	end
	h:advance(0.05)
end
for _, L in laggers do
	eq(L.p:GetAttribute("InRound"), "counted", string.format("seen once on the deck %.2f s after the drop: still in the round", L.lag))
	eq(#swept(L.p), 0, string.format("(lag %.2f s) and no movement-check card", L.lag))
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("  Hopper: a 27-stud jump allowed, a 29-stud jump caught in %.1f s, walking out caught at x = %.1f; the walker paced %.0f studs over two rounds uncaught",
	caughtIn or -1, outX or -1, walked))
print(string.format("disasterrounds guard: %d passed, %d failed", passed, failed))
