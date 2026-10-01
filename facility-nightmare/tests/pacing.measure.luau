-- FACILITY: Endless Nightmare — HOW LONG UNTIL THE BRAG AND THE LONG-TERM GOAL. A measurement, not a gate.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       cd ../facility-nightmare && luau tests/pacing.measure.luau
--
-- docs/complete-game-standard.md asks for a brag moment within about 30-45 minutes of normal play and a long-term
-- goal beyond it, measured with a pacing model in tests/. Review 2 (finding 2) measured THE VOID, then both the brag
-- and the goal, at a median of about 71 minutes for a medium player and practically never for a slow one. The brag is
-- now the band marked `brag` in Config.Env.Bands (the overgrown bio-lab) and the goal the last band (the void); each
-- counts as reached when the SAVED record first reaches its first sublevel (a powered lift there), which is when the
-- HUD's fanfare plays and the DEPTH RECORD board names it.
--
-- The model: the real server, one fresh player at a time (a new file: no perks, no Essence), played by
-- tests/Bot.luau at DESIGN.md §0's speed proxies. Between runs it buys every perk it can afford, cheapest need
-- first (Deep Cell, Second Wind, Night Eyes, Marathon, Soul Anchor); in a run it always DESCENDs, and EXTRACTs once
-- the goal's first sublevel is powered. The clock is everything since the player joined: walks in the break room,
-- rides, deaths, purchases. The bot is not a person (it detours for every item it sees, never hesitates, never
-- stops to look), so this checks the order of the minutes, not the minutes: CLAUDE.md's difficulty section.
--
-- Seeds are engine entropy and the emulator's Random is unseeded: every run of this file differs.

local Harness = require("../../robloxemu/emu/harness")
local Bot = require("./Bot")

-- DESIGN.md §0's proxies for human inefficiency: 16 "perfect", 12.8 "medium" (normal play), 10.4 "slow".
local SPEEDS = {
	{ name = "v12.8 (medium, normal play)", scale = 0.8, players = 30 },
	{ name = "v10.4 (slow)", scale = 0.65, players = 20 },
	{ name = "v16 (perfect)", scale = 1, players = 10 },
}
local CAP_MIN = 150 -- a player who has reached neither by then counts as "later than 150 min"
local ORDER = { "deepCell", "secondWind", "nightEyes", "marathon", "soulAnchor" }

local h = Harness.new({
	bundle = require("../../robloxemu/build/facility-nightmare"),
	name = "facility-nightmare-pacing",
	viewport = { 1280, 720 },
	touch = false,
})
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local bands = Config.Env.Bands
local bragK, bragName
for _, b in bands do
	if b.brag == true then bragK, bragName = math.max(1, b.from), b.name end
end
assert(bragK, "no band is marked brag")
local goalK, goalName = math.max(1, bands[#bands].from), bands[#bands].name

assert(h:tryRun("server/Main.server"))
h:advance(1)
local hub = h.workspace:FindFirstChild("Hub")

local function pct(list, p)
	local t = table.clone(list)
	table.sort(t)
	if #t == 0 then return 0 end
	return t[math.clamp(math.floor(p * (#t - 1) + 1.5), 1, #t)]
end
local function fmt(m) return if m >= math.huge then "later" else string.format("%.1f", m) end

print(string.format("the brag: %s (first sublevel %d); the long-term goal: %s (%d). Minutes from join to the first powering there.",
	bragName, bragK, goalName, goalK))
local uid = 600000
for _, sp in SPEEDS do
	local brag, goal, runsTo = {}, {}, {}
	local bragBands = {}
	for n = 1, sp.players do
		uid += 1
		local plr = h:join("Pace" .. n, uid)
		h:advance(0.5)
		h.Players:simulateSpawn(plr, h.workspace)
		h:advance(1)
		local t0 = h.scheduler:now()
		local function mins() return (h.scheduler:now() - t0) / 60 end
		local bot = Bot.new(h, plr, { maxSeconds = 100000 })
		bot.speedScale = sp.scale
		local tBrag, tGoal, runs = math.huge, math.huge, 0
		while mins() < CAP_MIN and tGoal == math.huge do
			for _ = 1, 20 do
				local st = bot:state()
				local bought = false
				for _, id in ORDER do
					local price
					for _, r in st.perkRows or {} do if r.id == id then price = r.price end end
					if price and (st.essence or 0) >= price then
						bot:fire("BuyPerk", id)
						bot:waitSeconds(0.5)
						bought = true
						break
					end
				end
				if not bought then break end
			end
			assert(bot:board(hub), "board")
			assert(bot:waitPhase("floor", 8), "arrive")
			runs += 1
			while true do
				local k = bot:state().run.k
				local r = bot:clearFloor()
				if r ~= "powered" then break end
				if k >= bragK and tBrag == math.huge then tBrag = mins(); table.insert(runsTo, runs) end
				if k >= goalK then
					tGoal = mins()
					bot:fire("Choose", "extract")
					break
				end
				bot:fire("Choose", "descend")
				if not (bot:waitPhase("ride", 3) and bot:waitPhase("floor", 8)) then break end
			end
			bot:waitPhase("hub", 30)
		end
		table.insert(brag, tBrag)
		table.insert(goal, tGoal)
		h:leave(plr)
		h:advance(1)
	end
	local function within(list, m)
		local c = 0
		for _, v in list do if v <= m then c += 1 end end
		return c
	end
	print(string.format("%s, %d players:", sp.name, sp.players))
	print(string.format("   the brag (%s): p10 %s / p50 %s / p90 %s min; within 30 min %d of %d, within 45 min %d of %d; in run p50 %s",
		bragName, fmt(pct(brag, 0.1)), fmt(pct(brag, 0.5)), fmt(pct(brag, 0.9)), within(brag, 30), #brag, within(brag, 45), #brag,
		if #runsTo > 0 then tostring(pct(runsTo, 0.5)) else "-"))
	print(string.format("   the goal (%s): p10 %s / p50 %s / p90 %s min; within 45 min %d of %d, within %d min %d of %d",
		goalName, fmt(pct(goal, 0.1)), fmt(pct(goal, 0.5)), fmt(pct(goal, 0.9)), within(goal, 45), #goal, CAP_MIN, within(goal, CAP_MIN), #goal))
end
print(string.format("scheduler errors: %d", #h:errors()))
for _, e in h:errors() do print("   " .. e) end
