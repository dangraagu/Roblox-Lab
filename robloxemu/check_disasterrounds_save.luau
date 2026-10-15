-- Disaster Rounds - saving, through the real server and the emulator's DataStore. Run: luau check_disasterrounds_save.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- docs/complete-game-standard.md §1 and DESIGN.md §8.4: pcall everything; a write only while holding the session lock;
-- an owner token on EVERY write, the release on leave included; a lock held elsewhere is waited for, then read-only,
-- and taken over once it expires; a failed load never writes a default over real data; a record from a newer
-- version is never written; leaving mid-round is saved as an elimination; a shutdown voids the round.

local SEED = 99
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
local Harness = require("./emu/harness")
local Bot = require("./check_disasterrounds_bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local store = h.services.DataStoreService:GetDataStore("DisasterRounds_v1")
local now0 = os.time()
-- records the test starts from
store:SetAsync("u_302", { v = 1, data = { survived = 40, played = 50, streak = 4, best = 9, bestAt = 1780000000,
	codex = { meteor = 3, flood = 2, tornado = 1, quake = 0 } }, session = { token = "their-token", expires = now0 + 20 } })
store:SetAsync("u_303", { v = 2, data = { survived = 7, best = 3 }, session = { token = "old", expires = 0 } })
store:SetAsync("u_304", { v = 1, data = { survived = 12, streak = 5, best = 5, bestAt = 1780000000 }, session = { token = "x", expires = 0 } })

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local rf = h.workspace:FindFirstChild("Round")
local toastR = RS:FindFirstChild("DRRemotes"):FindFirstChild("Toast")
h.game:GetService("RunService"):setIsServer(false)
local function rec(uid: number) return store.__data["u_" .. uid] end
local function toasted(plr, needle: string): boolean
	for _, r in toastR:sentTo(plr) do
		if string.find(tostring(r.args[1]), needle, 1, true) then return true end
	end
	return false
end
local DT = 0.1
local bots = {}
local function tick()
	for _, b in bots do Bot.step(b, DT) end
	h:advance(DT)
end
local function untilPhase(phase: string, limit: number)
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / DT do tick() n += 1 end
end
Config.Shots.ForceKind = "meteor"

--======================================================================= the lock, and a round's result

local A = h:join("Ava", 301)
h.Players:simulateSpawn(A, h.workspace)
table.insert(bots, Bot.new(h, A, { react = 0.6 }))
h:advance(0.5)
do
	local r = rec(301)
	truthy(r ~= nil and type(r.session) == "table" and type(r.session.token) == "string" and #r.session.token > 8,
		"the load takes the lock with a session token")
	truthy(r and r.session.expires >= now0 + Config.Save.LockSeconds - 5, "for LockSeconds (300 s)")
	eq(r and r.data, nil, "a brand-new player's record holds no data until the first locked save")
	eq(A:GetAttribute("Loaded"), true, "the profile is loaded")
end
local token = rec(301).session.token
untilPhase("outro", 120)
untilPhase("intermission", 10)
h:advance(0.5)
do
	local r = rec(301)
	eq(r.data and r.data.survived, 1, "the round's survival is saved at the round's end")
	eq(r.data and r.data.streak, 1, "with the streak")
	eq(r.data and r.data.best, 1, "and best")
	eq(r.session.token, token, "under the same token")
	local stringKeys = true
	for k in r.data.codex do if type(k) ~= "string" then stringKeys = false end end
	truthy(stringKeys, "the Codex is saved with string keys")
end

--======================================================================= another server takes the record: this one stops writing

do
	local r = rec(301)
	r.session = { token = "someone-else", expires = os.time() + 300 }
	local before = r.data.survived
	toastR:clearSent()
	untilPhase("outro", 120)
	untilPhase("intermission", 10)
	h:advance(0.5)
	eq(rec(301).data.survived, before, "after another session took the record, a round's result writes nothing")
	eq(rec(301).session.token, "someone-else", "and leaves their lock alone")
	truthy(toasted(A, "won't save"), "the player is told progress here won't save")
	h:leave(A)
	h:advance(0.5)
	eq(rec(301).session.token, "someone-else", "the release on leave carries the token too: it never unlocks their record")
	truthy((rec(301).session.expires or 0) > os.time(), "their lock still holds")
end
bots = {}

--======================================================================= a lock held elsewhere: wait, read-only, take over

local P = h:join("Pia", 302)
h.Players:simulateSpawn(P, h.workspace)
h:advance(0.5)
truthy(toasted(P, "open in another server"), "a record locked by another session: \"Waiting for it…\"")
h:advance(Config.Save.LockWaitSeconds + 1)
truthy(toasted(P, "won't save"), "after 30 s of waiting: read-only, and the player is told")
eq(P:GetAttribute("Survived"), 40, "the read-only profile still shows her real progress")
eq(rec(302).session.token, "their-token", "nothing was written")
-- their server stops renewing and the lock lapses (os.time is real time here, the virtual clock is not, so the lapse
-- is written into the record by hand): the next re-check takes it over
rec(302).session.expires = os.time() - 1
h:advance(Config.Save.ReadOnlyRecheckSeconds + 1)
truthy(rec(302).session.token ~= "their-token", "an expired lock on an untouched record is taken over")
truthy(toasted(P, "saves again"), "and the player is told progress saves again")
eq(rec(302).data.survived, 40, "the takeover keeps the stored data")
h:leave(P)
h:advance(0.5)
eq(rec(302).session.expires, 0, "leaving releases the lock (expires 0) with the owner token")

--======================================================================= a newer version is never written

local N = h:join("Neo", 303)
h.Players:simulateSpawn(N, h.workspace)
table.insert(bots, Bot.new(h, N, { react = 0.6 }))
h:advance(0.5)
truthy(toasted(N, "newer version"), "a record written by a newer version: read-only, said so")
untilPhase("outro", 120)
untilPhase("intermission", 10)
eq(rec(303).v, 2, "after a round, the record is still version 2")
eq(rec(303).data.survived, 7, "and its data untouched")
h:leave(N)
h:advance(0.5)
eq(rec(303).session.token, "old", "leaving does not touch it either")
bots = {}

--======================================================================= a failed load writes nothing; a retry loads the real data

do
	store.__failAll = true
	local F = h:join("Fay", 304)
	h.Players:simulateSpawn(F, h.workspace)
	h:advance(Config.Save.LoadBackoff[1] + Config.Save.LoadBackoff[2] + 1)
	truthy(toasted(F, "Couldn't load your profile"), "three failed loads: the player is told nothing will be saved")
	eq(F:GetAttribute("Survived"), 0, "a fresh, unsaved profile meanwhile")
	eq(rec(304).data.survived, 12, "and the stored record is untouched")
	store.__failAll = false
	h:advance(Config.Save.LoadRetrySeconds + 1)
	eq(F:GetAttribute("Survived"), 12, "the retry loads the real profile")
	truthy(toasted(F, "Your profile loaded"), "and says so")
	h:leave(F)
	h:advance(0.5)
end

--======================================================================= leaving mid-round is an elimination, saved in the leave's write

do
	local L = h:join("Lou", 305)
	h.Players:simulateSpawn(L, h.workspace)
	local b = Bot.new(h, L, { react = 0.6 })
	bots = { b }
	untilPhase("outro", 120)
	untilPhase("intermission", 10)
	untilPhase("outro", 120)
	untilPhase("intermission", 10)
	eq(L:GetAttribute("Streak"), 2, "Lou survives two rounds in a row")
	untilPhase("disaster", 30)
	h:advance(2)
	eq(L:GetAttribute("InRound"), "counted", "Lou is in the third")
	h:leave(L)
	h:advance(0.5)
	eq(rec(305).data.streak, 0, "leaving mid-round: the leave's write saves streak 0")
	eq(rec(305).data.best, 2, "best kept")
	eq(rec(305).data.lastEnd and rec(305).data.lastEnd.reason, "left", "and remembers why, for the rejoin")
	eq(rec(305).session.expires, 0, "and releases the lock")
	bots = {}
end

--======================================================================= a shutdown voids the round

do
	local S = h:join("Sam", 306)
	h.Players:simulateSpawn(S, h.workspace)
	bots = { Bot.new(h, S, { react = 0.6 }) }
	untilPhase("outro", 120)
	untilPhase("intermission", 10)
	untilPhase("disaster", 30)
	h:advance(2)
	eq(S:GetAttribute("Streak"), 1, "Sam has a streak of 1")
	eq(S:GetAttribute("InRound"), "counted", "and is in a round")
	h.game:runBindToClose()
	eq(rec(306).data.streak, 1, "the server shuts down: the round is void, the streak is not lost")
	eq(rec(306).session.expires, 0, "and the lock is released")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("disasterrounds save: %d passed, %d failed", passed, failed))
