-- FACILITY: Endless Nightmare — THE DIFFICULTY CURVE OF THE BUILT GAME. A measurement, not a gate.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       cd ../facility-nightmare && luau tests/curve.luau
--
-- DESIGN.md's survival numbers (M4/M5) came from design-measure/sim.luau: a model explorer walking
-- a model of the rules. Nothing checked that the GAME, as built, plays anything like that model.
-- This boots the real server, and for each run joins a fresh perk-less player (runs = 1, so the
-- first-run hold does not apply, as in M4) who plays through tests/Bot.luau at a given speed until
-- the dark takes them or sublevel CAP is powered. It prints P(powered sublevel k) and the median,
-- to put beside M4's line for the same speed.
--
-- The bot is NOT the model explorer. Both are blind, remember every room, use the flashlight only
-- in the dark and never sprint. The bot differs in three ways that cost it time: it walks to every
-- item it can reach before opening another door (the model charges a flat 0.9 s pickup detour), it
-- walks centre -> doorway -> centre and back out of item corners, and it waits for the server to
-- open each door (the model charges 0.5 s). So its numbers are a check on the ORDER of the model's,
-- not a replacement for them; §15 item 1 (people) is still the real answer.
--
-- Seeds are engine entropy: every run of this file walks different floors.

local Harness = require("../../robloxemu/emu/harness")
local Bot = require("./Bot")

local RUNS = 200
local CAP = 12
local SPEEDS = { { name = "v16 (perfect)", scale = 1 }, { name = "v10.4 (slow)", scale = 0.65 } }

local h = Harness.new({
	bundle = require("../../robloxemu/build/facility-nightmare"),
	name = "facility-nightmare-curve",
	viewport = { 1280, 720 },
	touch = false,
})
assert(h:tryRun("server/Main.server"))
h:advance(1)
local hub = h.workspace:FindFirstChild("Hub")
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
local remotes = h.ReplicatedStorage:FindFirstChild("FacilityRemotes")

local function pct(list, p)
	local t = table.clone(list)
	table.sort(t)
	if #t == 0 then return 0 end
	return t[math.clamp(math.floor(p * (#t - 1) + 1.5), 1, #t)]
end

local uid = 400000
local function oneRun(scale)
	uid += 1
	store:SetAsync("u_" .. uid, { data = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 0, runs = 1, extractions = 0,
		perks = { deepCell = 0, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } } })
	remotes.State:clearSent()
	remotes.Notice:clearSent()
	local plr = h:join("Curve" .. uid, uid)
	h:advance(0.5)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	local bot = Bot.new(h, plr, { maxSeconds = 900 })
	local out = { cleared = 0, died = false, seconds = 0, anomaly = nil, darkSeconds = 0 }
	local ok, err = pcall(function()
		assert(bot:board(hub), "could not board")
		assert(bot:waitPhase("floor", 6), "never reached sublevel 1")
		bot.speedScale = scale
		local t0 = bot.stats.seconds
		for k = 1, CAP do
			if k > 1 then
				bot:fire("Choose", "descend")
				assert(bot:waitPhase("ride", 1) and bot:waitPhase("floor", 6), "descend to " .. k .. " failed")
			end
			local n0 = #bot.notices
			local r = bot:clearFloor()
			for i = n0 + 1, #bot.notices do
				local n = bot.notices[i]
				if n.kind == "choice" and n.data.k == k then out.cleared = k end
			end
			if r ~= "powered" then
				if r == "dead" or bot:phase() == "dying" then
					out.died = true
				else
					out.anomaly = "floor " .. k .. " ended " .. tostring(r)
				end
				break
			end
		end
		out.seconds = bot.stats.seconds - t0
		out.darkSeconds = bot.stats.darkSeconds
	end)
	if not ok then out.anomaly = tostring(err) end
	h:leave(plr)
	h:advance(3)
	return out
end

for _, sp in SPEEDS do
	local reach, depths, secs, deaths, anomalies = {}, {}, {}, 0, {}
	for k = 0, CAP do reach[k] = 0 end
	for _ = 1, RUNS do
		local r = oneRun(sp.scale)
		if r.anomaly then table.insert(anomalies, r.anomaly) end
		for k = 0, r.cleared do reach[k] += 1 end
		table.insert(depths, r.cleared)
		table.insert(secs, r.seconds)
		if r.died then deaths += 1 end
	end
	local line = string.format("%-14s runs %d | powered p10/p50/p90 %d/%d/%d | died %d, reached cap %d | run s p50 %.0f | P(powered k): ",
		sp.name, RUNS, pct(depths, 0.1), pct(depths, 0.5), pct(depths, 0.9), deaths, reach[CAP], pct(secs, 0.5))
	for _, k in { 1, 2, 3, 4, 5, 6, 8, 10, 12 } do
		line ..= string.format("%d:%.2f ", k, reach[k] / RUNS)
	end
	print(line)
	if #anomalies > 0 then
		print("   anomalies (" .. #anomalies .. "): " .. table.concat(anomalies, " | "))
	end
end
print(string.format("scheduler errors %d, warnings %d", #h:errors(), #h.warnings))
for _, e in h:errors() do print("   error: " .. e) end
for _, w in h.warnings do print("   warning: " .. w) end
