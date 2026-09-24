-- FACILITY: Endless Nightmare — HOW RARE THE HAZARDS ARE IN REAL RUNS. A measurement, not a gate.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--       cd ../facility-nightmare && luau tests/hazards.measure.luau
--
-- tests/Hazards.spec.luau gives the rate per EXPOSED minute (a lit room of a band that has hazards), and
-- check_facilitynightmare_hazards proves the rules through the client on one held room. Neither says how
-- often a hazard comes for a player who is actually PLAYING: dark rooms, the quiet offices, the rides and
-- the break room all freeze the clock. This boots the real server and the real Env.client, and one
-- perk-less player (runs = 1, so no first-run hold) plays run after run through tests/Bot.luau until the
-- dark takes them or sublevel CAP is powered. RenderStepped is fired once per bot tick.
--
-- The bot IGNORES every warning (it never steps out of a ring), so its hits are the hit rate of a player
-- who ignores warnings; a player who steps out is never hit (check_facilitynightmare_hazards C). A
-- near-hit is a burst within 8 studs of the player. Every hazard is aimed at the spot the player stood on.
--
-- Seeds are engine entropy and the emulator's Random is unseeded: every run of this file differs.

local Harness = require("../../robloxemu/emu/harness")
local Bot = require("./Bot")

-- DESIGN.md §0's proxies for human inefficiency: 16 "perfect", 12.8 "medium", 10.4 "slow".
local SPEEDS = {
	{ name = "v12.8 (medium)", scale = 0.8, runs = 120, cap = 14 },
	{ name = "v10.4 (slow)", scale = 0.65, runs = 80, cap = 14 },
	{ name = "v16 (perfect)", scale = 1, runs = 40, cap = 14 },
}
local NEAR = 8

local h = Harness.new({
	bundle = require("../../robloxemu/build/facility-nightmare"),
	name = "facility-nightmare-hazard-rate",
	viewport = { 1280, 720 },
	touch = false,
})
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local EnvBands = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBands"))
local Dressing = h:_require(h.ReplicatedStorage:FindFirstChild("Dressing"))
local EnvBus = h:_require(h.ReplicatedStorage:FindFirstChild("EnvBus"))
local Env, F = Config.Env, Config.Facility
local bands = Env.Bands

assert(h:tryRun("server/Main.server"))
h:advance(1)
local hub = h.workspace:FindFirstChild("Hub")
local store = h.services.DataStoreService:GetDataStore("FacilityNightmare_v1")
local RS = h.game:GetService("RunService")

local function pct(list, p)
	local t = table.clone(list)
	table.sort(t)
	if #t == 0 then return 0 end
	return t[math.clamp(math.floor(p * (#t - 1) + 1.5), 1, #t)]
end

local UID = 500001
store:SetAsync("u_" .. UID, { data = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 0, runs = 1, extractions = 0,
	perks = { deepCell = 0, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } } })
local plr = h:join("Rate", UID)
h:advance(0.5)
assert(h:tryRun("client/Env.client"))
h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)
local envFolder = h.workspace:FindFirstChild("FacilityEnvLocal")
local hazardFolder = envFolder:FindFirstChild("Hazard")

-- one live record per hazard, from the bus
local cur = nil
local acc = nil -- the current speed's accumulators
local bot
EnvBus.on(function(kind, data)
	if kind ~= "hazard" or acc == nil then return end
	local p = bot and bot:pos()
	if data.phase == "warn" then
		local model = hazardFolder:FindFirstChildOfClass("Folder")
		local ring = model and model:FindFirstChild("Ring")
		cur = { centre = ring and ring.Position, burst = false, k = acc.k }
		acc.warns += 1
		acc.runWarns += 1
		acc.byBand[acc.band].warns += 1
	elseif data.phase == "burst" and cur then
		cur.burst = true
		acc.bursts += 1
		if p and cur.centre then
			local dx, dz = p.X - cur.centre.X, p.Z - cur.centre.Z
			if dx * dx + dz * dz <= NEAR * NEAR then acc.near += 1 end
		end
	elseif data.phase == "hit" then
		acc.hits += 1
	elseif data.phase == "clear" and cur then
		if not cur.burst then acc.cancels += 1 end
		cur = nil
	end
end)

local function onTick(b)
	RS.RenderStepped:Fire(0.1)
	if acc == nil then return end
	local st = b:state()
	if not st or st.phase ~= "floor" or not st.run then return end
	local k = st.run.k
	acc.k = k
	acc.band = EnvBands.indexAt(bands, k)
	acc.floorSeconds += 0.1
	acc.byBand[acc.band].seconds += 0.1
	local rooms = b:rooms()
	local id = b:roomAt(rooms, b:pos())
	local r = id and rooms[id]
	if r and r.light and r.light.Enabled and r.light.Brightness >= 0.5 * F.RoomLightBrightness and not st.run.flicker and not st.run.dark then
		acc.litSeconds += 0.1
		if #bands[Dressing.roomBand(Env, EnvBands, k, id)].hazards > 0 then acc.exposedSeconds += 0.1 end
	end
end

bot = Bot.new(h, plr, { onTick = onTick, maxSeconds = 100000 })

for _, sp in SPEEDS do
	acc = { k = 1, band = 1, warns = 0, bursts = 0, near = 0, hits = 0, cancels = 0, floorSeconds = 0, litSeconds = 0,
		exposedSeconds = 0, runWarns = 0, byBand = {} }
	for i = 1, #bands do acc.byBand[i] = { seconds = 0, warns = 0 } end
	local depths, perRun, arrive = {}, {}, {}
	for i = 1, #bands do arrive[i] = {} end
	local anomalies = {}
	for _ = 1, sp.runs do
		acc.runWarns = 0
		local cleared = 0
		local ok, err = pcall(function()
			if bot:phase() ~= "hub" then assert(bot:waitPhase("hub", 20), "not back in the hub") end
			bot:waitSeconds(1)
			assert(bot:board(hub), "could not board")
			assert(bot:waitPhase("floor", 8), "never reached sublevel 1")
			bot.speedScale = sp.scale
			local t0 = bot.stats.seconds
			local seenBand = {}
			for k = 1, sp.cap do
				if k > 1 then
					bot:fire("Choose", "descend")
					assert(bot:waitPhase("ride", 2) and bot:waitPhase("floor", 8), "descend to " .. k .. " failed")
				end
				local bi = EnvBands.indexAt(bands, k)
				if not seenBand[bi] then
					seenBand[bi] = true
					table.insert(arrive[bi], bot.stats.seconds - t0)
				end
				local n0 = #bot.notices
				local r = bot:clearFloor()
				for i = n0 + 1, #bot.notices do
					local n = bot.notices[i]
					if n.kind == "choice" and n.data.k == k then cleared = k end
				end
				if r ~= "powered" then break end
			end
			if bot:phase() == "floor" then
				bot:fire("Choose", "extract")
			end
		end)
		if not ok then table.insert(anomalies, tostring(err)) end
		bot.speedScale = 1
		table.insert(depths, cleared)
		table.insert(perRun, acc.runWarns)
		bot:waitPhase("hub", 30)
	end
	local fm, lm, em = acc.floorSeconds / 60, acc.litSeconds / 60, acc.exposedSeconds / 60
	print(string.format("%s: %d runs, powered p10/p50/p90 %d/%d/%d, %.1f min on floors (%.1f lit, %.1f exposed = lit in a band with hazards)",
		sp.name, sp.runs, pct(depths, 0.1), pct(depths, 0.5), pct(depths, 0.9), fm, lm, em))
	print(string.format("   hazards %d: one per %.1f floor-min, one per %.1f exposed min; bursts %d, near-hits %d (one per %.1f floor-min), hits %d (one per %.1f floor-min), called off by a flicker %d",
		acc.warns, fm / math.max(acc.warns, 1e-9), em / math.max(acc.warns, 1e-9), acc.bursts, acc.near, fm / math.max(acc.near, 1e-9),
		acc.hits, fm / math.max(acc.hits, 1e-9), acc.cancels))
	-- the review's finding 3 (EYECANDY.md §11): the bot never stops walking, so this is the near-hit share for a player
	-- who keeps moving; the ring is drawn where they stood when the warning started
	print(string.format("   near-hit share: %d of %d bursts (%.1f %%) landed within %d studs of the player",
		acc.near, acc.bursts, 100 * acc.near / math.max(acc.bursts, 1), NEAR))
	local hist = {}
	for _, n in perRun do hist[n] = (hist[n] or 0) + 1 end
	local line = "   hazards per run:"
	for n = 0, 20 do if hist[n] then line ..= string.format(" %d:%d", n, hist[n]) end end
	print(line)
	for i, b in bands do
		local bb = acc.byBand[i]
		if bb.seconds > 0 or #arrive[i] > 0 then
			print(string.format("   %-9s reached on %2d of %d runs, arrival p50 %5.1f min; %6.1f floor-min there, %3d hazards (one per %s floor-min)",
				b.id, #arrive[i], sp.runs, pct(arrive[i], 0.5) / 60, bb.seconds / 60, bb.warns,
				if bb.warns > 0 then string.format("%.1f", bb.seconds / 60 / bb.warns) else "-"))
		end
	end
	if #anomalies > 0 then print("   anomalies (" .. #anomalies .. "): " .. table.concat(anomalies, " | ")) end
end
print(string.format("scheduler errors %d, FacilityEnv warnings %d", #h:errors(), (function()
	local n = 0
	for _, w in h.warnings do if string.find(w, "FacilityEnv", 1, true) then n += 1 end end
	return n
end)()))
for _, e in h:errors() do print("   error: " .. e) end
