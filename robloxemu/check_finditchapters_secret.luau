-- Find It! Chapters: the predictor check (DESIGN.md §3.3, §12, §19.3; after fork-tower REVIEW-4 part A).
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_secret.luau 2>&1
--
--   * over more than 1000 finds, every predictor built ONLY from what the client receives (the payload's order,
--     ids, positions, heights, yaws, variants) names the hidden prop no better than chance: |m - n/k| within
--     4.9 standard deviations of Binomial(n, 1/k);
--   * after a Pause and Resume, predictors built from the PRE-PAUSE room are at chance in the re-dressed room;
--   * nothing replicated (an attribute or a value anywhere under Workspace, ReplicatedStorage or Players) and no
--     remote payload other than the room's prop list carries a hidden id before its find or its hint;
--   * PLANTED-LEAK CONTROL: the hidden id written as a workspace attribute, as a player attribute and inside a
--     Toast payload must each be caught by the same scanner, or the scanner proves nothing.
-- The hidden ids are read from ServerStorage.FindIt.Attempts, the server-only rig, to SCORE the predictors.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-secret", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
do
	local stars = {}
	for ch = 1, 14 do stars["c" .. ch] = { f = true } end
	DSS:GetDataStore("FindIt_Players_v1"):SetAsync("u_4242", { data = { v = 1, book = { cleared = 14, stars = stars },
		daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 }, solved = 14, solvedAt = 1791000000, boarded = 14, seenIntro = true, firstJoin = 1791000000 } })
end
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Clue = mod("Config"), mod("Clue")
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local remotes = RS:FindFirstChild("FindItRemotes")

local plr = h:join("Sly", 4242)
h:advance(1)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic

local function frame(d)
	RunService.Heartbeat:Fire(d)
	h:advance(d)
end
local function run(seconds)
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(0.1, seconds - t)
		frame(d)
		t += d
	end
end
local function last(name)
	local s = remotes:FindFirstChild(name):sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function rig()
	local v = ServerStorage.FindIt.Attempts:FindFirstChild("4242")
	return v and HttpService:JSONDecode(v.Value)
end

--============================================================ the leak scanner
local SUSPECT = { "id", "prop", "hid", "target", "secret", "cand", "spot", "answer" }
-- keys whose value is known and public: the server's attempt counter (it numbers attempts, not props; a counter
-- of 10 is not prop 10). Listed by name, so a NEW key that carries an id is still flagged.
local SAFE_KEYS = { attemptId = true }
local function suspectKey(k)
	if SAFE_KEYS[k] then return false end
	local s = string.lower(tostring(k))
	for _, w in SUSPECT do
		if string.find(s, w, 1, true) then return true end
	end
	return false
end
local function scanValue(v, hidden, path, out, depth)
	depth = depth or 0
	if depth > 8 then return end
	if type(v) == "table" then
		for k, x in v do
			if (type(x) == "number" and hidden[x] and suspectKey(k)) then
				table.insert(out, path .. "." .. tostring(k) .. " = " .. tostring(x))
			elseif type(x) == "string" and suspectKey(k) then
				for id in hidden do
					if x == tostring(id) then table.insert(out, path .. "." .. tostring(k) .. " = '" .. x .. "'") end
				end
			else
				scanValue(x, hidden, path .. "." .. tostring(k), out, depth + 1)
			end
		end
	end
end
-- everything replicated: attributes and values under Workspace, ReplicatedStorage and Players
local function scanInstances(hidden, out)
	for _, rootInst in { ws, RS, h.Players } do
		local list = rootInst:GetDescendants()
		table.insert(list, rootInst)
		for _, d in list do
			local ok, attrs = pcall(function() return d:GetAttributes() end)
			if ok and type(attrs) == "table" then
				for k, x in attrs do
					if (type(x) == "number" and hidden[x]) or (type(x) == "string" and hidden[tonumber(x) or -1]) then
						table.insert(out, d:GetFullName() .. "@" .. k .. " = " .. tostring(x))
					end
				end
			end
			if d:IsA("ValueBase") and not (d.Name == "Solved" and d.Parent and d.Parent.Name == "leaderstats") then
				local x = d.Value
				if (type(x) == "number" and hidden[x]) or (type(x) == "string" and (hidden[tonumber(x) or -1] or string.find(x, "hidden", 1, true))) then
					table.insert(out, d:GetFullName() .. " = " .. tostring(x))
				end
			end
		end
	end
end
-- every payload sent to this player since `from`, except the room's prop list; a Result that FOUND its prop and a
-- Hint name exactly the prop the player earned, so they are allowed for that id only
local function scanPayloads(hidden, from, out)
	for _, r in remotes:GetChildren() do
		if r.Name ~= "Room" then
			local sent = r:sentTo(plr)
			for i = (from[r.Name] or 0) + 1, #sent do
				local p = sent[i].args[1]
				local allowed = {}
				if r.Name == "Result" and type(p) == "table" and p.hit then allowed[p.id] = true end
				if r.Name == "Hint" and type(p) == "table" then allowed[p.id] = true end
				local hid = {}
				for id in hidden do if not allowed[id] then hid[id] = true end end
				scanValue(p, hid, r.Name .. "#" .. i, out)
			end
		end
	end
end
local function marks()
	local m = {}
	for _, r in remotes:GetChildren() do m[r.Name] = #r:sentTo(plr) end
	return m
end

--============================================================ open a room, many times: predictors at chance
local function openFresh(ch)
	if last("State") and last("State").where == "room" then
		remotes.Hub:simulateFireServer(plr)
		h:advance(1.05)
	end
	remotes.Open:simulateFireServer(plr, ch)
	h:advance(1.05)
	return last("Room")
end

local PRED = {
	lowestId = function(c) table.sort(c, function(a, b) return a.id < b.id end) return c[1] end,
	highestId = function(c) table.sort(c, function(a, b) return a.id > b.id end) return c[1] end,
	nearestDoor = function(c) table.sort(c, function(a, b) return a.x * a.x + a.z * a.z < b.x * b.x + b.z * b.z end) return c[1] end,
	farthestDoor = function(c) table.sort(c, function(a, b) return a.x * a.x + a.z * a.z > b.x * b.x + b.z * b.z end) return c[1] end,
	westmost = function(c) table.sort(c, function(a, b) return a.x < b.x end) return c[1] end,
	highestUp = function(c) table.sort(c, function(a, b) if a.y ~= b.y then return a.y > b.y end return a.id < b.id end) return c[1] end,
	smallestYaw = function(c) table.sort(c, function(a, b) if a.yaw ~= b.yaw then return a.yaw < b.yaw end return a.id < b.id end) return c[1] end,
	variantOne = function(c) table.sort(c, function(a, b) if a.variant ~= b.variant then return a.variant < b.variant end return a.id < b.id end) return c[1] end,
}
local hits, finds, expectSum, varSum = {}, 0, 0, 0
for name in PRED do hits[name] = 0 end
local leaksBeforeFind = {}
local ATTEMPTS = 190
for i = 1, ATTEMPTS do
	local ch = ({ 5, 8, 12, 15 })[(i % 4) + 1]
	local from = marks()
	local pl = openFresh(ch)
	local secret = rig()
	local hidden = {}
	for _, id in secret.hidden do hidden[id] = true end
	-- predictors from the payload only
	for ci, clue in pl.clues do
		local cands = {}
		for _, p in pl.props do
			if Clue.matches(p, clue, Config) then table.insert(cands, p) end
		end
		local k = #cands
		finds += 1
		expectSum += 1 / k
		varSum += (1 / k) * (1 - 1 / k)
		for name, f in PRED do
			local guess = f(table.clone(cands))
			if guess and guess.id == secret.hidden[ci] then hits[name] += 1 end
		end
	end
	-- nothing carries a hidden id before a find
	local out = {}
	scanPayloads(hidden, from, out)
	scanInstances(hidden, out)
	for _, o in out do table.insert(leaksBeforeFind, o) end
end
print(string.format("  %d finds over %d rooms (chapters 5, 8, 12, 15); chance = %.1f hits (sd %.1f)", finds, ATTEMPTS, expectSum, math.sqrt(varSum)))
truthy(finds >= 1000, "more than 1000 finds")
for name, m in hits do
	local z = (m - expectSum) / math.sqrt(varSum)
	print(string.format("    predictor %-12s %4d hits (z %+.2f)", name, m, z))
	truthy(math.abs(z) <= 4.9, string.format("predictor %s names the hidden prop at chance (z %+.2f)", name, z))
end
eq(#leaksBeforeFind, 0, "no replicated value and no payload carried a hidden id before its find")
for i = 1, math.min(5, #leaksBeforeFind) do print("    leak: " .. leaksBeforeFind[i]) end

--============================================================ after a re-dress, the pre-pause room predicts nothing
do
	local pre = { nearestToOld = 0, sameKind = 0 }
	local expect, var, n = 0, 0, 0
	for i = 1, 120 do
		local pl = openFresh(8)
		run(3.2)
		remotes.Pause:simulateFireServer(plr)
		run(0.2)
		remotes.Resume:simulateFireServer(plr)
		run(3.2)
		local re = last("Room")
		truthy(re.redress == true, "re-dressed (" .. i .. ")")
		local secret = rig()
		for ci, clue in re.clues do
			local cands = {}
			for _, p in re.props do if Clue.matches(p, clue, Config) then table.insert(cands, p) end end
			local k = #cands
			n += 1
			expect += 1 / k
			var += (1 / k) * (1 - 1 / k)
			-- predictor 1: the new candidate standing nearest to where the OLD clue's lowest-id candidate stood
			local oldCands = {}
			for _, p in pl.props do if Clue.matches(p, pl.clues[ci], Config) then table.insert(oldCands, p) end end
			table.sort(oldCands, function(a, b) return a.id < b.id end)
			local anchor = oldCands[1]
			table.sort(cands, function(a, b)
				return (a.x - anchor.x) ^ 2 + (a.z - anchor.z) ^ 2 < (b.x - anchor.x) ^ 2 + (b.z - anchor.z) ^ 2
			end)
			if cands[1].id == secret.hidden[ci] then pre.nearestToOld += 1 end
			-- predictor 2: a new candidate of the old lowest-id candidate's kind, else the lowest id
			table.sort(cands, function(a, b)
				local ak, bk = a.kind == anchor.kind, b.kind == anchor.kind
				if ak ~= bk then return ak end
				return a.id < b.id
			end)
			if cands[1].id == secret.hidden[ci] then pre.sameKind += 1 end
		end
	end
	for name, m in pre do
		local z = (m - expect) / math.sqrt(var)
		print(string.format("    after a re-dress: predictor %-13s %d hits of %d finds, chance %.1f (z %+.2f)", name, m, n, expect, z))
		truthy(math.abs(z) <= 4.9, "after a re-dress, " .. name .. " is at chance")
	end
end

--============================================================ every payload's keys are on an allowlist
-- A leak under an innocent key ("next", "tip") would pass the name scan above, so every payload the server sends
-- is held to the exact set of keys the design allows (DESIGN.md §12.3). A new key fails here until it is
-- reviewed and added.
do
	local ALLOW = {
		State = { where = true, kind = true, chapter = true, day = true, case = true, band = true, progress = true, n = true, items = true,
			intro = true, introText = true, origin = true, result = true, attemptId = true, W = true, D = true, state = true, reason = true,
			clock = true, limit = true, looks = true, found = true, hintUsed = true, searching = true, pauseQueued = true,
			-- reviewed 2026-10-07 (REVIEW-1 A4): seconds of clock until the next Pause; a function of the clock and the
			-- last re-dress only, nothing about where anything is
			pauseIn = true,
			-- reviewed 2026-10-07 (REVIEW-1 round 2 C2): seconds of break left while paused; a function of the pause
			-- times only, nothing about where anything is
			breakLeft = true },
		["State.result"] = { reason = true, stars = true, saving = true, foundCount = true, n = true, progress = true, cantSave = true,
			note = true, first = true, credited = true, solved = true, bookSolved = true,
			-- reviewed 2026-10-07 (REVIEW-1 A2): the clear is queued for the next write; a flag about the save only
			pendingSave = true,
			-- reviewed 2026-10-07 (REVIEW-1 round 2 D6): this clear earned the 45th star; a fact about stars only
			goldBook = true },
		Result = { id = true, hit = true, item = true, offClue = true, attemptId = true },
		Hint = { item = true, id = true, attemptId = true },
		Toast = { text = true, kind = true },
		Notice = { kind = true, name = true, text = true },
		Board = { mode = true, rows = true, message = true, loading = true },
		Profile = { cleared = true, stars = true, solved = true, totalStars = true, continue = true, dailyOpen = true, dailySolvedToday = true,
			dailySolved = true, streak = true, bestStreak = true, title = true, caseNumber = true, bookSolved = true, canSave = true,
			loaded = true, state = true,
			-- reviewed 2026-10-07 (REVIEW-1 round 2 D6): all 45 stars, derived from the stars the profile already sends
			goldBook = true },
		Room = { v = true, kind = true, chapter = true, day = true, band = true, W = true, D = true, idBase = true, props = true, clues = true,
			tables = true, shelves = true, looks = true, clock = true, origin = true, attemptId = true, redress = true },
	}
	local bad = {}
	local seen = 0
	for _, r in remotes:GetChildren() do
		local allow = ALLOW[r.Name]
		if allow then
			for i, rec in r:sentTo(plr) do
				local p = rec.args[1]
				if type(p) == "table" then
					seen += 1
					for k in p do
						if not allow[k] then table.insert(bad, r.Name .. "#" .. i .. " key " .. tostring(k)) end
					end
					if r.Name == "State" and type(p.result) == "table" then
						for k in p.result do
							if not ALLOW["State.result"][k] then table.insert(bad, "State#" .. i .. ".result key " .. tostring(k)) end
						end
					end
				end
			end
		end
	end
	truthy(seen > 500, "the allowlist saw " .. seen .. " payloads")
	eq(#bad, 0, "every payload's keys are on its allowlist")
	for i = 1, math.min(5, #bad) do print("    unexpected: " .. bad[i]) end
end

--============================================================ planted-leak control: the scanner must catch each leak
do
	local pl = openFresh(8)
	local secret = rig()
	local hidden = {}
	for _, id in secret.hidden do hidden[id] = true end
	local clean = {}
	scanInstances(hidden, clean)
	eq(#clean, 0, "control baseline: nothing to find before planting")
	ws:SetAttribute("FindItLeak", secret.hidden[1])
	local a = {}
	scanInstances(hidden, a)
	truthy(#a >= 1, "planted: a workspace attribute holding the hidden id is caught")
	ws:SetAttribute("FindItLeak", nil)
	plr:SetAttribute("NextSpot", secret.hidden[2])
	local b = {}
	scanInstances(hidden, b)
	truthy(#b >= 1, "planted: a player attribute holding the hidden id is caught")
	plr:SetAttribute("NextSpot", nil)
	local from = marks()
	remotes.Toast:FireClient(plr, { text = "psst", id = secret.hidden[3] })
	local c = {}
	scanPayloads(hidden, from, c)
	truthy(#c >= 1, "planted: a Toast payload carrying the hidden id is caught")
	local sent = remotes.Toast:sentTo(plr)
	local planted = sent[#sent].args[1]
	local extra = nil
	for k in planted do if k ~= "text" and k ~= "kind" then extra = k end end
	eq(extra, "id", "planted: the same Toast fails the Toast allowlist (key 'id')")
	local v = Instance and nil
	local sv = h.instance.Instance.new("StringValue")
	sv.Name = "Debug"
	sv.Value = tostring(secret.hidden[1])
	sv.Parent = RS
	local d = {}
	scanInstances(hidden, d)
	truthy(#d >= 1, "planted: a StringValue in ReplicatedStorage holding the hidden id is caught")
	sv:Destroy()
end

--============================================================ where the secret lives
do
	local inRS = false
	for _, d in RS:GetDescendants() do
		if d.Name == "Attempts" or d.Name == "FindIt" then inRS = true end
	end
	eq(inRS, false, "the rig is not under ReplicatedStorage")
	truthy(ServerStorage:FindFirstChild("FindIt") ~= nil, "it is under ServerStorage, which never replicates")
	local server = {}
	for _, d in h.game:GetService("ServerScriptService"):GetDescendants() do table.insert(server, d.Name) end
	local leakedModules = {}
	for _, n in { "Dressing", "Attempt" } do
		local m = RS:FindFirstChild(n)
		if m then table.insert(leakedModules, n) end
	end
	-- Dressing and Attempt are shared ModuleScripts: their CODE is public by design (the harness can only require
	-- shared modules), and the code is not the secret: the draws are, and they happen in the server's memory.
	eq(#leakedModules, 2, "Dressing and Attempt are shared modules (their code is public; the draws are not)")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it secret: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_secret failed", 0) end
