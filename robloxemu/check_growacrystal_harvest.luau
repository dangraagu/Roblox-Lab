-- Grow a Crystal — the harvest result reaches the harvesting player, and nothing else changes.
-- Run: luau check_growacrystal_harvest.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The client draws a harvest burst (and a beam of light for Legendary and Mythic) in the colour of the
-- tier the refraction roll produced. Only the server knows that tier, so its existing State push now
-- carries `lastHarvest = { n, socket, seed, tier }`: n counts this session's harvests (the client plays
-- a burst when it grows), socket is where, seed is what was planted, tier is what it refracted into.
--
-- What must NOT change, and is checked here: no new remote (the State event already goes to exactly one
-- player), no field that describes anything but this player's own finished harvest (never a future roll,
-- never another player), the reward itself (dust, codex) exactly as before, and the socket emptied.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local ME = 5150
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
-- Socket 2 holds a LEGENDARY seed planted in 1970 (mature), sockets 3..18 Shards (mature). A tier-5 seed
-- refracts to 5 or 6, never lower, so the first harvest is guaranteed a beam on the client.
store:SetAsync("u_" .. ME, {
	data = {
		dust = 100, seeds = { [1] = 3 }, chambers = 3, luckLevel = 0, growthLevel = 0,
		plants = { [2] = { tier = 5, at = 1 }, [3] = { tier = 1, at = 1 }, [4] = { tier = 1, at = 1 }, [5] = { tier = 1, at = 1 },
			[6] = { tier = 1, at = 1 }, [7] = { tier = 1, at = 1 }, [8] = { tier = 1, at = 1 }, [9] = { tier = 1, at = 1 },
			[10] = { tier = 1, at = 1 }, [11] = { tier = 1, at = 1 }, [12] = { tier = 1, at = 1 }, [13] = { tier = 1, at = 1 },
			[14] = { tier = 1, at = 1 }, [15] = { tier = 1, at = 1 }, [16] = { tier = 1, at = 1 }, [17] = { tier = 1, at = 1 },
			[18] = { tier = 1, at = 1 } },
		codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {},
	},
})

assert(h:tryRun("server/Main.server"))
h:advance(1)
local remotes = h.ReplicatedStorage:FindFirstChild("CrystalRemotes")
local before = {}
for _, r in remotes:GetChildren() do table.insert(before, r.Name) end
table.sort(before)

local me = h:join("Harvester", ME)
h:advance(1)
h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

local State = remotes:FindFirstChild("State")
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local function lastState()
	local sent = State:sentTo(me)
	local rec = sent[#sent]
	return rec and rec.args[1]
end

local s0 = lastState()
truthy(s0 ~= nil, "the joining player got a State push")
local n0 = s0 and s0.lastHarvest and s0.lastHarvest.n or 0
eq(n0, 0, "before any harvest this session the harvest counter is 0 (a rejoin plays no burst)")

local function socketPart(id)
	return h.workspace:FindFirstChild("Socket_" .. ME .. "_" .. id, true)
end
local function click(id)
	local s = socketPart(id)
	local c = s and s:FindFirstChild("Crystal")
	local cd = c and c:FindFirstChildOfClass("ClickDetector")
	if cd then cd.MouseClick:Fire(me) end
	h:advance(0.5)
	return cd ~= nil
end

local dustValue = me.leaderstats.Dust
local dust0 = dustValue.Value
truthy(click(2), "the legendary crystal on socket 2 is clickable")
local s1 = lastState()
local lh = s1 and s1.lastHarvest
truthy(type(lh) == "table", "after a harvest the State push carries lastHarvest")
if type(lh) == "table" then
	eq(lh.n, 1, "the first harvest is number 1")
	eq(lh.socket, 2, "on socket 2")
	eq(lh.seed, 5, "from the Legendary seed")
	truthy(lh.tier == 5 or lh.tier == 6, "refracted to Legendary or Mythic (" .. tostring(lh.tier) .. ")")
	-- the reported tier is the one that was paid and recorded, not a second roll
	local paid = dustValue.Value - dust0
	eq(paid, (lh.tier == 5 and 300 or 1500), "the dust paid matches the reported tier")
	eq(s1.codex[lh.tier], true, "and the codex recorded that same tier")
	local keys = {}
	for k in lh do table.insert(keys, k) end
	table.sort(keys)
	eq(table.concat(keys, ","), "n,seed,socket,tier", "lastHarvest carries exactly n, seed, socket, tier: nothing about a future roll")
end
eq(socketPart(2) and socketPart(2):FindFirstChild("Crystal"), nil, "the harvested socket is empty again")

truthy(click(3), "the shard on socket 3 is clickable")
local s2 = lastState()
eq(s2 and s2.lastHarvest and s2.lastHarvest.n, 2, "the second harvest is number 2")
eq(s2 and s2.lastHarvest and s2.lastHarvest.socket, 3, "on socket 3")

-- an unrelated push (buying a seed) repeats the same record, so the client can tell it is not new
local Buy = remotes:FindFirstChild("Buy")
Buy:simulateFireServer(me, "seed", 1)
h:advance(0.5)
local s3 = lastState()
eq(s3 and s3.lastHarvest and s3.lastHarvest.n, 2, "a push that is not a harvest repeats the last record (n unchanged)")

-- The reported tier is the ROLLED one, every time. With a Legendary seed it equals the seed tier 95 % of
-- the time, so a server reporting the seed would usually pass the block above. Shards refract half the
-- time: over the 15 mature Shards on sockets 4..18 the chance that none refracts is 0.5^15 (3e-5), so the
-- dust each one pays tells the rolled tier from the planted one.
do
	local refracted, mismatched, harvested = 0, 0, 0
	for id = 4, 18 do
		local before = dustValue.Value
		if click(id) then
			harvested += 1
			local rec = lastState() and lastState().lastHarvest
			local paid = dustValue.Value - before
			if rec == nil or rec.socket ~= id or Config.Economy.DustValue[rec.tier] ~= paid then
				mismatched += 1
			end
			if rec and rec.tier > rec.seed then refracted += 1 end
		end
	end
	eq(harvested, 15, "all 15 mature Shards on sockets 4..18 were harvested")
	eq(mismatched, 0, "every reported tier is the tier that was paid for")
	truthy(refracted >= 1, "and at least one of them refracted above its seed (" .. refracted .. " of 15)")
end

-- a second player's harvest counts for them, not for me
local other = h:join("Neighbour", 6161)
h:advance(1)
local sentOther = State:sentTo(other)
local so = sentOther[#sentOther] and sentOther[#sentOther].args[1]
eq(so and so.lastHarvest and so.lastHarvest.n or 0, 0, "another player's counter starts at 0")

local after = {}
for _, r in remotes:GetChildren() do table.insert(after, r.Name) end
table.sort(after)
eq(table.concat(after, ","), table.concat(before, ","), "no remote was added")

-- leaving and rejoining starts a new session: no burst replays for an old harvest
h:leave(me)
h:advance(1)
local again = h:join("Harvester", ME)
h:advance(1)
local sentAgain = State:sentTo(again)
local sa = sentAgain[#sentAgain] and sentAgain[#sentAgain].args[1]
eq(sa and sa.lastHarvest and sa.lastHarvest.n or 0, 0, "a rejoin starts the counter again at 0")

eq(#h.warnings, 0, "no server warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal harvest: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal harvest check failed", 0) end
