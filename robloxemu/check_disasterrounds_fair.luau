-- Disaster Rounds - THE FAIRNESS FLOOR, through the real server. Run: luau check_disasterrounds_fair.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- DESIGN.md §4.1: "If the bot is ever hit, the disaster is unfair." Eight scripted players at Heat 5 (the hottest the
-- game gets) play every disaster on fresh islands through the real Main.server.luau. Each reads only what a client
-- can see and reacts 0.6 s after a red thing appears (check_disasterrounds_bot.luau). A ninth player stands still:
-- an idle player must be swept out in every round, within 23 s of the name (first ring by 20 s + 3 s telegraph),
-- so AFK and jiggle-bots farm nothing (DESIGN.md §10).
--
-- Headless limits: no physics, no latency. The bots move their root parts at 16 studs/s.

-- Every unseeded Random.new() the game makes (the map's, the disaster's, each round's) gets the next number of a
-- fixed sequence, and the server takes its random draws in a stable player order, so a failing round replays
-- exactly with the same SEED. The game itself never seeds its Randoms; this changes only where entropy comes from.
local SEED = 20261007
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

local ROUNDS_PER_KIND = 50 -- islands per disaster; each is a fresh island and a fresh disaster stream

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
local rf = h.workspace:FindFirstChild("Round")
local card = RS:FindFirstChild("DRRemotes"):FindFirstChild("Card")

Config.Shots.ForceHeat = 5

local bots, players = {}, {}
for k = 1, 8 do
	local p = h:join("Bot" .. k, 7000 + k)
	h.Players:simulateSpawn(p, h.workspace)
	table.insert(players, p)
	table.insert(bots, Bot.new(h, p, { react = 0.6 }))
end
local idle = h:join("Idle", 7999)
h.Players:simulateSpawn(idle, h.workspace)
local idleBot = Bot.new(h, idle, { idle = true })

local DT = 0.1
local function tick()
	for _, b in bots do Bot.step(b, DT) end
	Bot.step(idleBot, DT)
	h:advance(DT)
end
-- every landing, checked the tick it happens: a finite, level facing (a NaN rotation breaks a body in Roblox)
local landings, centreLandings, badFacing = 0, 0, 0
local function checkLandings()
	local all = table.clone(players)
	table.insert(all, idle)
	for _, p in all do
		if p:GetAttribute("InRound") == "counted" then
			local cf = p.Character.HumanoidRootPart.CFrame
			local lv = cf.LookVector
			local pos = cf.Position
			landings += 1
			if math.abs(pos.X) < 4 and math.abs(pos.Z) < 4 then centreLandings += 1 end
			if lv.X ~= lv.X or lv.Z ~= lv.Z or math.abs(lv.Magnitude - 1) > 1e-6 or math.abs(lv.Y) > 1e-6 then
				badFacing += 1
			end
		end
	end
end
local function untilPhase(phase: string, limit: number)
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / DT do
		tick()
		n += 1
	end
	if phase == "drop" and rf:GetAttribute("Phase") == "drop" then checkLandings() end
end

local results = {}
local idleWorst, idleMissed, idleNotIn = 0, 0, 0
local ringsSeen, dodges = 0, 0
for _, kind in Config.Disasters.Kinds do
	Config.Shots.ForceKind = kind
	local hits, rounds, botRounds = 0, 0, 0
	for _ = 1, ROUNDS_PER_KIND do
		untilPhase("drop", 200)
		untilPhase("disaster", 10)
		local nameAt = h.scheduler:now()
		local idleOutAt = nil
		if idle:GetAttribute("InRound") ~= "counted" then idleNotIn += 1 end
		local seenRings = {}
		card:clearSent()
		while rf:GetAttribute("Phase") == "disaster" do
			tick()
			for _, r in rf.Rings:GetChildren() do seenRings[r] = true end
			if idleOutAt == nil and (idle:GetAttribute("InRound") or "") == "" then idleOutAt = h.scheduler:now() - nameAt end
		end
		for _ in seenRings do ringsSeen += 1 end
		rounds += 1
		for _, p in players do
			botRounds += 1
			local hit = false
			for _, rec in card:sentTo(p) do
				if rec.args[1] == "swept" then hit = true end
			end
			if hit then
				hits += 1
				print(string.format("  HIT: %s in a %s round", p.Name, kind))
			end
		end
		if idleOutAt == nil then
			idleMissed += 1
			print(string.format("  the idle player was never swept out in a %s round (InRound %s)", kind, tostring(idle:GetAttribute("InRound"))))
		else
			idleWorst = math.max(idleWorst, idleOutAt)
		end
		untilPhase("intermission", 10)
	end
	results[kind] = { hits = hits, botRounds = botRounds, rounds = rounds }
	eq(hits, 0, string.format("%s at Heat 5: 8 bots x %d islands, no bot is ever hit", kind, rounds))
end
for _, b in bots do dodges += b.dodges end
eq(idleMissed, 0, "the player who stands still is swept out in every round at Heat 5")
-- and at Heat 0, the gentlest the game gets, where the rings are 15 s apart outside a Meteor Shower
Config.Shots.ForceHeat = 0
local idle0Worst, idle0Missed, heat0Hits = 0, 0, 0
for _, kind in Config.Disasters.Kinds do
	Config.Shots.ForceKind = kind
	for _ = 1, 10 do
		untilPhase("drop", 200)
		untilPhase("disaster", 10)
		local nameAt = h.scheduler:now()
		local outAt = nil
		if idle:GetAttribute("InRound") ~= "counted" then idleNotIn += 1 end
		card:clearSent()
		while rf:GetAttribute("Phase") == "disaster" do
			tick()
			if outAt == nil and (idle:GetAttribute("InRound") or "") == "" then outAt = h.scheduler:now() - nameAt end
		end
		if outAt == nil then idle0Missed += 1 else idle0Worst = math.max(idle0Worst, outAt) end
		for _, p in players do
			for _, rec in card:sentTo(p) do
				if rec.args[1] == "swept" then
					heat0Hits += 1
					print(string.format("  HIT at Heat 0: %s in a %s round (%s)", p.Name, kind, tostring(rec.args[2].text)))
				end
			end
		end
		untilPhase("intermission", 10)
	end
end
eq(idle0Missed, 0, "the player who stands still is swept out in every round at Heat 0 too (40 rounds)")
eq(idleNotIn, 0, "and was on the island at the name of every one of the 240 rounds (no round passed vacuously)")
eq(badFacing, 0, string.format("every one of %d landings faces level and finite (%d on the centre cell, where the island's centre is underfoot)",
	landings, centreLandings))
truthy(centreLandings > 0, "the centre-cell landing was exercised")
truthy(idle0Worst <= 23 + 0.2, string.format("within 23 s of the name (latest %.1f s; first ring by 20 s + 3 s warning)", idle0Worst))
eq(heat0Hits, 0, "and at Heat 0 no bot is hit either (8 bots x 40 rounds)")
truthy(ringsSeen > 0, "rings fell (" .. ringsSeen .. ")")

local parts = {}
for _, kind in Config.Disasters.Kinds do
	local r = results[kind]
	table.insert(parts, string.format("%s %d/%d", kind, r.hits, r.botRounds))
end
print(string.format("  bot-rounds lost at Heat 5: %s; %d rings fell, the bots stepped out %d times; idle player out by %.1f s at the latest (Heat 0: %.1f s)",
	table.concat(parts, ", "), ringsSeen, dodges, idleWorst, idle0Worst))
for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end

print(string.format("disasterrounds fair: %d passed, %d failed", passed, failed))
