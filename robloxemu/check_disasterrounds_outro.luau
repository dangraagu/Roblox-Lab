-- Disaster Rounds - the round's end and the leave's write, through the real server. Run: luau check_disasterrounds_outro.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- REVIEW-1 F1 and F3 (disaster-rounds/REVIEW-1.md). DESIGN.md §2.6: leaving or resetting DURING a round is an
-- elimination, so that quitting under a red ring cannot save a streak. The first build also counted the 4 s outro as
-- "during a round": a player who saw SURVIVED! and closed the game, reset, or fell through a quake hole lost the streak
-- the server had just awarded. And a leave while one of the player's writes was in flight lost the leave's own write
-- (the release and the elimination): a 300 s stale lock, and a mid-round leave that cost nothing.
--   A. leaving 1 s into the outro keeps the streak, records no "left during a round", and releases the lock;
--   B-D. a respawn, a death or a fall during the outro is not a reset: no swept card, the streak stays, the round
--      counts once, and a fallen body is put back on the Lookout;
--   E. a leave while the round-end write is in flight: the release still lands, and the rejoin is not locked out;
--   F. a leave MID-DISASTER while a lock-renewal write is in flight: the elimination and the release still land;
--   G. a shutdown (BindToClose) with a write in flight returns only after the release has landed.
-- Aimed rings are switched off and the disaster is a Meteor Shower, so every counted player survives every round.

local SEED = 515151
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
local ws = h.workspace
local store = h.services.DataStoreService:GetDataStore("DisasterRounds_v1")
-- a real UpdateAsync takes time; the emulator's is instant. `slow` is how long each one takes here.
local slow = 0
local inFlight = 0
local releasedAt: { [string]: number } = {}
do
	local orig = store.UpdateAsync
	store.UpdateAsync = function(self, k, f)
		inFlight += 1
		if slow > 0 then h.scheduler:wait(slow) end
		local ok, a, b = pcall(orig, self, k, f)
		inFlight -= 1
		local rec = store.__data[k]
		if rec and type(rec.session) == "table" and rec.session.expires == 0 then
			releasedAt[k] = releasedAt[k] or h.scheduler:now()
		end
		if not ok then error(a, 0) end
		return a, b
	end
end
local function seedRec(uid: number, streak: number)
	store:SetAsync("u_" .. uid, { v = 1, data = { survived = streak, played = streak, streak = streak, best = streak,
		bestAt = 1780000000 }, session = { token = "old", expires = 0 } })
end
seedRec(7001, 5)

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local IC, LC = Config.Island, Config.Lookout
Config.Strikes.FirstAfterSeconds = 1e6 -- no aimed rings
Config.Shots.ForceKind = "meteor" -- so no threat at all: every counted player survives
local rf = ws:FindFirstChild("Round")
local remotes = RS:FindFirstChild("DRRemotes")
local card = remotes:FindFirstChild("Card")
local toastR = remotes:FindFirstChild("Toast")
h.game:GetService("RunService"):setIsServer(false)

local function rec(uid: number) return store.__data["u_" .. uid] end
local function now(): number return h.scheduler:now() end
local function untilPhase(ph: string, lim: number): boolean
	local n = 0
	while rf:GetAttribute("Phase") ~= ph and n < lim / 0.1 do
		h:advance(0.1)
		n += 1
	end
	return rf:GetAttribute("Phase") == ph
end
local function cards(plr, kind: string): number
	local n = 0
	for _, r in card:sentTo(plr) do
		if r.args[1] == kind then n += 1 end
	end
	return n
end
local function toasted(plr, needle: string): boolean
	for _, r in toastR:sentTo(plr) do
		if string.find(tostring(r.args[1]), needle, 1, true) then return true end
	end
	return false
end
local function root(plr) return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") end
local function onDeck(plr): boolean
	local r = root(plr)
	if not r then return false end
	local p = r.Position
	return p.X >= LC.MinX and p.X <= LC.MaxX and p.Z >= LC.MinZ and p.Z <= LC.MaxZ and p.Y > LC.FloorY
end

-- Quinn keeps the rounds running while Pia comes and goes
local Q = h:join("Quinn", 7099)
h.Players:simulateSpawn(Q, ws)
local P = h:join("Pia", 7001)
h.Players:simulateSpawn(P, ws)
h:advance(2)
eq(P:GetAttribute("Streak"), 5, "Pia loads with a streak of 5")

--======================================================================= A. leaving 1 s into the outro

print("A. leave in the outro")
truthy(untilPhase("outro", 200), "a round ends")
eq(cards(P, "survived"), 1, "Pia gets the SURVIVED card")
eq(P:GetAttribute("Streak"), 6, "streak 6")
h:advance(1.0)
eq(rf:GetAttribute("Phase"), "outro", "1 s later the outro is still on")
eq(rec(7001).data.streak, 6, "the round-end write has landed: 6 stored")
h:leave(P)
h:advance(1)
eq(rec(7001).data.streak, 6, "leaving 1 s into the outro keeps the streak the server just awarded")
eq(rec(7001).data.lastEnd, nil, "and records no 'left during a round'")
eq(rec(7001).session.expires, 0, "the leave releases the lock")
local P2 = h:join("Pia", 7001)
h.Players:simulateSpawn(P2, ws)
h:advance(2)
eq(P2:GetAttribute("Streak"), 6, "the rejoin has streak 6")
eq(toasted(P2, "You left during a round"), false, "and is not told it left during a round")

--======================================================================= B-D. a respawn, a death, a fall in the outro

local function outroCase(label: string, act: () -> ())
	untilPhase("intermission", 20)
	card:clearSent()
	truthy(untilPhase("outro", 200), label .. ": a round ends")
	eq(cards(P2, "survived"), 1, label .. ": SURVIVED")
	local streak, played, survived = P2:GetAttribute("Streak"), P2:GetAttribute("Played"), P2:GetAttribute("Survived")
	h:advance(1.0)
	act()
	h:advance(1.5)
	eq(cards(P2, "swept"), 0, label .. " 1 s into the outro: no swept card")
	eq(P2:GetAttribute("Streak"), streak, label .. ": the streak stays " .. tostring(streak))
	eq(P2:GetAttribute("Played"), played, label .. ": the round counts once (Played " .. tostring(played) .. ")")
	eq(P2:GetAttribute("Survived"), survived, label .. ": and as a survival")
	return streak
end
print("B. respawn in the outro")
outroCase("a respawn", function()
	h.Players:simulateSpawn(P2, ws)
end)
print("C. death in the outro")
outroCase("a death", function()
	P2.Character:FindFirstChildOfClass("Humanoid"):TakeDamage(1000)
end)
untilPhase("intermission", 10)
h.Players:simulateSpawn(P2, ws) -- a fresh body for the next round
h:advance(0.5)
print("D. a fall in the outro")
local fellStreak = outroCase("a fall", function()
	local r = root(P2)
	r.CFrame = CFrame.new(r.Position.X, IC.FallOutY - 20, r.Position.Z) -- through a hole, below the sea
end)
truthy(onDeck(P2), "a body that fell during the outro is put back on the Lookout")
eq(rec(7001).data.streak, fellStreak, "and the stored streak is the one it earned")

--======================================================================= E. a leave while the round-end write is in flight

print("E. leave while the round-end write is in flight")
untilPhase("intermission", 20)
slow = 0.5
truthy(untilPhase("outro", 200), "a round ends")
local streakE = P2:GetAttribute("Streak")
truthy(inFlight > 0 and P2:GetAttribute("Saving") == true, string.format("the round-end write is in flight (%d)", inFlight))
releasedAt["u_7001"] = nil
h:leave(P2)
h:advance(3)
eq(rec(7001).data.streak, streakE, "the stored streak is the one just earned (" .. tostring(streakE) .. ")")
eq(rec(7001).session.expires, 0, "the leave's release still lands after the write that was in flight")
local P3 = h:join("Pia", 7001)
h.Players:simulateSpawn(P3, ws)
h:advance(3)
eq(toasted(P3, "open in another server"), false, "so the rejoin is not locked out (no 'open in another server')")
eq(P3:GetAttribute("Streak"), streakE, "and has its streak")

--======================================================================= F. a mid-disaster leave while a write is in flight

-- Pia sits one round out on a break, so her lock-renewal write (120 s after the last one) falls inside the next
-- disaster; a client that watches its own replicated Saving attribute leaves exactly then
print("F. leave mid-disaster while a renewal write is in flight")
untilPhase("intermission", 20)
remotes.SetRest:simulateFireServer(P3, true)
untilPhase("disaster", 40)
eq(P3:GetAttribute("InRound"), "", "Pia sits this round out")
untilPhase("intermission", 100)
h:advance(1.1)
remotes.SetRest:simulateFireServer(P3, false)
truthy(untilPhase("disaster", 40), "the next round")
eq(P3:GetAttribute("InRound"), "counted", "Pia is in it")
local streakF = P3:GetAttribute("Streak")
truthy(streakF > 0, "with a streak to lose (" .. tostring(streakF) .. ")")
local leftAt = nil
local n = 0
while rf:GetAttribute("Phase") == "disaster" and n < 700 do
	h:advance(0.1)
	n += 1
	if P3:GetAttribute("Saving") == true and P3:GetAttribute("InRound") == "counted" then
		leftAt = now() - (rf:GetAttribute("NameAt") or now())
		h:leave(P3)
		break
	end
end
truthy(leftAt ~= nil, string.format("a write came while she was on the island; she left %.1f s into the disaster", leftAt or -1))
print(string.format("  F: left %.1f s into the disaster while Saving was true", leftAt or -1))
h:advance(3)
eq(rec(7001).data.streak, 0, "leaving mid-disaster is still an elimination, written after the write that was in flight")
eq(rec(7001).data.lastEnd and rec(7001).data.lastEnd.reason, "left", "and remembered for the rejoin")
eq(rec(7001).session.expires, 0, "and the lock is released")

--======================================================================= G. a shutdown with a write in flight

print("G. shutdown with a write in flight")
local P4 = h:join("Pia", 7001)
h.Players:simulateSpawn(P4, ws)
h:advance(3)
truthy(toasted(P4, "You left during a round"), "the rejoin says why the streak ended")
untilPhase("intermission", 100)
truthy(untilPhase("outro", 200), "a round ends")
truthy(inFlight > 0, "with its round-end writes in flight")
releasedAt["u_7001"] = nil
local closedAt = nil
h.scheduler:spawn(function()
	h.game:runBindToClose()
	closedAt = now()
end)
h:advance(3)
truthy(closedAt ~= nil, "BindToClose returns")
truthy(releasedAt["u_7001"] ~= nil, "the release is written")
print(string.format("  G: BindToClose returned %.2f s after the release landed", (closedAt or 0) - (releasedAt["u_7001"] or 0)))
truthy(closedAt ~= nil and releasedAt["u_7001"] ~= nil and closedAt >= releasedAt["u_7001"],
	string.format("and BindToClose waits for it (returned at %.2f, released at %.2f): the server is not shut down under a pending release",
		closedAt or -1, releasedAt["u_7001"] or -1))

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("disasterrounds outro: %d passed, %d failed", passed, failed))
