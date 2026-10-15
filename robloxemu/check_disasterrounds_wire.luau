-- Disaster Rounds - what replicates, swept every tick. Run: luau check_disasterrounds_wire.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- DESIGN.md §8.3: the game has no hidden answer to leak, because everything that will hurt you is shown before it does.
-- The one rule is that nothing is shown EARLIER than its telegraph. Over several rounds of every disaster, every tick,
-- this fails on:
--   * the disaster's name (Round.Kind) before the name;
--   * the next island in the workspace before the roster froze (it lives in ServerStorage until the drop);
--   * a cell's CrackAt more than 3.0 s before its drop;
--   * a tornado path point more than 4.25 s ahead on the funnel's own clock (touchdown, or now once it is down);
--   * a flood rise published more than 9 s before it starts, or more than one rise at a time;
--   * a ring that appears less than 3.0 s before it lands;
--   * a session token anywhere a client can see: any attribute in the workspace, ReplicatedStorage or on a player,
--     or any remote payload.

local SEED = 8080
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

local ROUNDS_PER_KIND = 3

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local SS = h.game:GetService("ServerStorage")
local store = h.services.DataStoreService:GetDataStore("DisasterRounds_v1")
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Tornado = h:_require(RS:FindFirstChild("Tornado"))
local rf = h.workspace:FindFirstChild("Round")
h.game:GetService("RunService"):setIsServer(false)

local bots, players = {}, {}
for k = 1, 3 do
	local p = h:join("Wire" .. k, 4400 + k)
	h.Players:simulateSpawn(p, h.workspace)
	table.insert(players, p)
	table.insert(bots, Bot.new(h, p, { react = 0.6 }))
end
h:advance(0.5)
local tokens = {}
for _, p in players do
	local r = store.__data["u_" .. p.UserId]
	if r and r.session and type(r.session.token) == "string" then table.insert(tokens, r.session.token) end
end
eq(#tokens, 3, "three players, three session tokens in the store")

local problems = {}
local function problem(msg: string)
	if #problems < 20 then table.insert(problems, msg) end
end
local function containsToken(v: any, depth: number): boolean
	if depth > 6 then return false end
	if type(v) == "string" then
		for _, t in tokens do
			if string.find(v, t, 1, true) then return true end
		end
	elseif type(v) == "table" then
		for k, x in v do
			if containsToken(k, depth + 1) or containsToken(x, depth + 1) then return true end
		end
	end
	return false
end
local function scanAttributes(inst): boolean
	for _, v in inst:GetAttributes() do
		if containsToken(v, 0) then return true end
	end
	return false
end
local function scanTokens()
	for _, root in { h.workspace, RS } do
		if scanAttributes(root) then problem("a session token in " .. root.Name .. "'s attributes") end
		for _, d in root:GetDescendants() do
			if scanAttributes(d) then problem("a session token in the attributes of " .. d.Name) end
		end
	end
	for _, p in h.Players:GetPlayers() do
		if scanAttributes(p) then problem("a session token in " .. p.Name .. "'s attributes") end
	end
	for _, r in RS:FindFirstChild("DRRemotes"):GetChildren() do
		for _, rec in r:getSent() do
			if containsToken(rec.args, 0) then problem("a session token in a " .. r.Name .. " payload") end
		end
	end
end

local crackSeen, ringSeen, riseSeen = {}, {}, {}
local stats = { cracks = 0, rings = 0, rises = 0, paths = 0, kindsBefore = 0, islandsBeforeDrop = 0, drops = 0 }
local pending: { [any]: boolean } = {}
local lastPhase = rf:GetAttribute("Phase")
local DT = 0.1
local scans = 0

local function sweep()
	local now = h.scheduler:now()
	local phase = rf:GetAttribute("Phase")
	-- the name
	if (phase == "intermission" or phase == "drop") and rf:GetAttribute("Kind") ~= nil then
		stats.kindsBefore += 1
		problem(string.format("Kind %s visible during the %s", tostring(rf:GetAttribute("Kind")), phase))
	end
	-- the island
	if h.workspace:FindFirstChild("NextIsland", true) then problem("an island named NextIsland in the workspace") end
	local hidden = SS:FindFirstChild("NextIsland")
	if hidden and hidden:IsDescendantOf(h.workspace) then problem("the hidden island is in the workspace") end
	-- every island seen hidden in ServerStorage must stay out of the workspace until the drop that uses it
	if hidden then pending[hidden] = true end
	if phase == "drop" and lastPhase ~= "drop" then
		stats.drops += 1
		local island = rf:FindFirstChild("Island")
		if island == nil or not pending[island] then
			problem("the island dropped onto is not one that was hidden in ServerStorage")
		end
		if island then pending[island] = nil end
	end
	for obj in pending do
		if obj:IsDescendantOf(h.workspace) and phase ~= "drop" then
			stats.islandsBeforeDrop += 1
			problem("a hidden island became visible during the " .. tostring(phase))
			pending[obj] = nil
		end
	end
	lastPhase = phase
	-- cracks
	local island = rf:FindFirstChild("Island")
	if island then
		for _, c in island.Cells:GetChildren() do
			local ca = c:GetAttribute("CrackAt")
			if ca ~= nil and not crackSeen[c] then
				crackSeen[c] = true
				stats.cracks += 1
				local da = c:GetAttribute("DropAt")
				if type(da) ~= "number" or da - now > Config.Quake.CrackSeconds + 1e-6 then
					problem(string.format("a crack shown %.2f s before its drop", (da or 0) - now))
				end
			end
		end
	end
	-- rings
	for _, r in rf.Rings:GetChildren() do
		if not ringSeen[r] then
			ringSeen[r] = true
			stats.rings += 1
			local ia = r:GetAttribute("ImpactAt")
			if type(ia) ~= "number" or ia - now < Config.Strikes.TelegraphSeconds - DT - 1e-6 then
				problem(string.format("a ring shown only %.2f s before it lands", (ia or 0) - now))
			end
		end
	end
	-- the tornado's path
	-- the horizon runs on the funnel's own clock: from the name the first 4 s of its motion (touchdown at 3 s to 7 s),
	-- after touchdown never more than 4 s (+ one 0.25 s step) past now
	local t0, pts = Tornado.decode(rf:GetAttribute("Path"))
	local nameAt = rf:GetAttribute("NameAt")
	if t0 and pts and type(nameAt) == "number" then
		stats.paths += 1
		local last = t0 + (#pts - 1) * Config.Tornado.StepSeconds
		local horizon = math.max(now, nameAt + Config.Tornado.TouchdownAt) + Config.Tornado.HorizonSeconds
		if last > horizon + Config.Tornado.StepSeconds + 1e-6 then
			problem(string.format("a path point %.2f s past the funnel's 4 s horizon", last - horizon))
		end
	end
	-- the flood
	local riseAt = rf:GetAttribute("RiseAt")
	if type(riseAt) == "number" and not riseSeen[riseAt] then
		riseSeen[riseAt] = true
		stats.rises += 1
		if riseAt - now > Config.Flood.WarnSeconds + 1e-6 then
			problem(string.format("a rise published %.2f s before it starts", riseAt - now))
		end
	end
	scans += 1
	if scans % 10 == 0 then scanTokens() end
end

for _, kind in Config.Disasters.Kinds do
	Config.Shots.ForceKind = kind
	for _ = 1, ROUNDS_PER_KIND do
		local n = 0
		repeat
			for _, b in bots do Bot.step(b, DT) end
			h:advance(DT)
			sweep()
			n += 1
		until (rf:GetAttribute("Phase") == "outro" and rf:GetAttribute("Kind") == kind) or n > 2000
		repeat
			for _, b in bots do Bot.step(b, DT) end
			h:advance(DT)
			sweep()
		until rf:GetAttribute("Phase") == "intermission"
	end
end
scanTokens()

eq(#problems, 0, "nothing replicated ahead of its telegraph, and no token anywhere a client sees")
for _, p in problems do print("   " .. p) end
truthy(stats.cracks > 0 and stats.rings > 0 and stats.rises > 0 and stats.paths > 0 and stats.drops >= 12,
	"the sweep saw every kind of red")
print(string.format("  swept %d ticks: %d drops, %d rings, %d cracks, %d flood rises, %d published paths; %d token scans",
	scans, stats.drops, stats.rings, stats.cracks, stats.rises, stats.paths, math.floor(scans / 10) + 1))
for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("disasterrounds wire: %d passed, %d failed", passed, failed))
