-- Fork Tower — THE TRAP PLAN MUST NOT BE COMPUTABLE ON THE CLIENT.
-- Run: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--      luau check_forktower_plansecret.luau
--
-- THE DEFECT, measured 2026-09-17. src/shared/Fork.luau lives in ReplicatedStorage and derived
-- every floor from Config.WorldSeed (replicated) and the run seed, and the run seed is
-- `leaderstats.Rebirths + 1` (replicated). A probe that read 30 forks honestly over 3 runs and
-- compared them with `Fork.plan(Config, Rebirths.Value + 1, Rng).floors[level].trapDoor`, computed
-- from ReplicatedStorage modules only, matched 30 of 30. REVIEW-3's gating of TellKind,
-- RuleInverted and Marked stopped nothing: an exploiter never needed the attributes, they had the
-- generator. Every read an honest player paid Config.Fork.ReadSeconds for was free to a script.
--
-- WHAT THIS FILE ASSERTS, in the order it runs:
--
--   A  THE MEASUREMENT. Ten readers, eight runs, ten floors: 800 forks read HONESTLY (hold begun,
--      ReadSeconds on the server's clock, released), each confirmed against the world by walking
--      through door 1 and looking at the section it built. Three public predictors are scored
--      against them, and each must be no better than a coin:
--        P1  the replicated Fork module, fed nothing but Config and leaderstats — the probe,
--            verbatim, plus whatever else that module will compute without a server secret;
--        P2  the 2026-09-17 Fork.luau itself, byte-for-byte (fork-tower/tests/fixtures), so an
--            API change that merely stops P1 from running cannot hide the old derivation;
--        P3  another reader on the same public inputs, so ANY function of what two players share
--            — WorldSeed, run seed, floor — is caught, not just the one Fork.luau happens to use.
--   B  THE VISIBLE WORLD IS PUBLIC. What an unread fork shows is identical for every reader on the
--      same public inputs, and every section built is Section.build of public inputs plus the two
--      bits the player already revealed by walking through a door. That is the proof that nothing
--      visible before a read is derived from the secret — the brute-force trap in the brief.
--   C  NOTHING SECRET REPLICATES. The secrets are taken from the DataStore (server-only), proved
--      to be the secrets in play by re-deriving all 800 reads from them, and then searched for in
--      every property and attribute of every service a client receives (workspace,
--      ReplicatedStorage, Players with every player and everything under them, Lighting, the
--      Starter containers, ...), in every payload any RemoteEvent sent, and in the one
--      RemoteFunction's return. The sweep is shown a planted secret AFTER its "clean" verdict and
--      must find it, so a blind sweeper cannot report "clean".
--   D  A REJOIN REBUILDS THE SAME TOWER.
--   E  MIGRATION. A profile saved before the secret existed keeps everything its player has
--      already seen or paid for, and gets fresh secrets for everything they have not.
--   F  A SESSION THAT CANNOT PERSIST WHAT IT REVEALS IS NOT AN ORACLE. Written after the adversarial
--      pass on the fix above won 240 of 240 forks with no read paid: a READ-ONLY session (another
--      server still holds the lock) loaded the SAVED secrets, let the player walk through every door
--      and saved nothing, so the real session afterwards was the same run with every trap known.
--      F1 is that attack verbatim, F2 the same oracle after a crash (a writable session whose
--      writes never land; F2b the session that crashes is its own probe), F3 proves the fix reshuffles nothing the player has already seen, F4 is
--      a load whose own write failed after it had read a released record, and F5 closes the one
--      window in which a session released its lock and could still reveal. F6 (third pass) is a
--      releasing write that lands late, after a later session has loaded and revealed; F6c is its
--      control, a late release with nobody loaded in between, which must still land.
--
-- THE STATISTICAL THRESHOLD, and why it is this one. For a correct game each prediction is an
-- independent fair coin against the honest read, so the match count m over n forks is
-- Binomial(n, 1/2), mean n/2, standard deviation sqrt(n)/2. A predictor PASSES when
--     |m - n/2| <= Z * sqrt(n) / 2,   Z = 4.9
-- which a correct game violates with probability ~1e-6 per predictor (two-sided normal tail at
-- 4.9 sigma). Z is that large because the sample is DIFFERENT EVERY RUN: the server draws its
-- secrets from `Random.new()`, which the emulator seeds from os.time/os.clock, so a threshold that
-- flakes one run in a thousand would be a gate nobody trusts. Two-sided, because a predictor that
-- is reliably WRONG is exactly as good as one that is reliably right. At n = 800 the band is
-- 331..469: a predictor 58.7% accurate sits on its edge, one 62% accurate is outside it with near
-- certainty (4 sigma past the edge), and the leak this file was written for is 100%.

local Harness = require("./emu/harness")
local Legacy = require("../fork-tower/tests/fixtures/Fork_20260917")
local bundle = require("./build/fork-tower")

local h = Harness.new({
	bundle = bundle,
	name = "fork-tower-plansecret",
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

--============================================================================ the client's modules

-- WHAT A CLIENT HAS. ReplicatedStorage replicates the ModuleScripts, and a client that requires one
-- gets its OWN copy of the module table, built from the same source — never the server's table.
-- So the predictors below do not use `h:_require` (that would hand back the server's instance, and
-- anything the server stashed on it). They compile the very sources the bundle put in
-- ReplicatedStorage, fresh, on this side.
local function clientModule(name: string)
	local holder = h.ReplicatedStorage:FindFirstChild(name)
	assert(holder ~= nil and holder.ClassName == "ModuleScript",
		"ReplicatedStorage." .. name .. " is not a replicated ModuleScript")
	local entry = bundle["shared/" .. name]
	local chunk = assert(loadstring(entry.source, "@client/" .. name))
	return chunk()
end
local Config = clientModule("Config")
local Rng = clientModule("Rng")
local Fork = clientModule("Fork")
local Section = clientModule("Section")

local FLOORS = Config.Tower.Floors
local READ_SECONDS = Config.Fork.ReadSeconds
local Z = 4.9
local SECRET_FIELD = "floorSecrets" -- where the server saves the per-floor secrets in its profile
local UINT32 = 4294967296

local READERS = 10
local RUNS = 8

local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)

assert(h:tryRun("server/Main.server"))
h:advance(1)

local remotes = h.ReplicatedStorage:FindFirstChild("ForkRemotes")
local towers = h.workspace:FindFirstChild("Towers")

--============================================================================ world helpers

local function laneOf(plr)
	if towers == nil then return nil end
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end
local function forkOf(lane, level) return lane and lane:FindFirstChild("Fork_" .. level) end
local function padOf(lane, level)
	local f = forkOf(lane, level)
	return f and f:FindFirstChild("ForkPad_" .. level)
end
local function doorOf(lane, level, slot)
	local f = forkOf(lane, level)
	return f and f:FindFirstChild("Door_" .. level .. "_" .. slot)
end
local function sectionOf(lane, level) return lane and lane:FindFirstChild("Section_" .. level) end
local function readPromptOf(lane, level)
	local pad = padOf(lane, level)
	return pad and pad:FindFirstChildOfClass("ProximityPrompt")
end
local function stat(plr, name)
	local ls = plr:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value
end

-- The trap, the way a player reads it AFTER paying: which door bears the sign the inscription
-- names, and whether the inscription says that door is the trap or the safe one. Nil on a fork
-- that has not been read, because on an unread fork none of this exists.
local function trapFromWorld(lane, level)
	local pad = padOf(lane, level)
	local d1, d2 = doorOf(lane, level, 1), doorOf(lane, level, 2)
	if pad == nil or d1 == nil or d2 == nil then return nil end
	local m1 = d1:GetAttribute("Marked") == true
	local m2 = d2:GetAttribute("Marked") == true
	if m1 == m2 then return nil end
	local marked = if m1 then 1 else 2
	return if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
end

local function traitLabelOf(lane, level, slot)
	local d = doorOf(lane, level, slot)
	local bb = d and d:FindFirstChild("TraitLabel")
	local t = bb and bb:FindFirstChild("Text")
	return t and tostring(t.Text) or ""
end

local function readHonestly(plrs)
	local began = h.scheduler:now()
	for _, plr in plrs do
		local prompt = readPromptOf(laneOf(plr), stat(plr, "Floor"))
		if prompt then prompt.PromptButtonHoldBegan:Fire(plr) end
	end
	h:advance(READ_SECONDS)
	for _, plr in plrs do
		local prompt = readPromptOf(laneOf(plr), stat(plr, "Floor"))
		if prompt then prompt.Triggered:Fire(plr) end
	end
	h:advance(0.1)
	return h.scheduler:now() - began
end

local function choose(plr, level, slot)
	local d = doorOf(laneOf(plr), level, slot)
	local prompt = d and d:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Triggered:Fire(plr) end
end

local function climb(plr, level)
	local sec = sectionOf(laneOf(plr), level)
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if sec == nil or hrp == nil then return false end
	for _, c in sec:GetChildren() do
		if c:GetAttribute("Exit") == true then
			c.Touched:Fire(hrp)
			return true
		end
	end
	return false
end

local function savedData(uid)
	local rec = store:GetAsync("u_" .. uid)
	return rec and rec.data
end

local function isSecret(v): boolean
	return type(v) == "number" and v == math.floor(v) and v >= 0 and v < UINT32
end

local function savedSecrets(uid)
	local d = savedData(uid)
	local s = d and d[SECRET_FIELD]
	if type(s) ~= "table" then return nil end
	for level = 1, FLOORS do
		if not isSecret(s[level]) then return nil end
	end
	return s
end

--============================================================================ visible records

-- Every rendered field of a part and everything under it. Position and CFrame are left out on
-- purpose: two readers who took different doors on floor L legitimately stand at different X on
-- floor L+1, and that X is a function of what they already revealed (part B measures that half).
local RENDERED = {
	"Size", "Color", "Material", "Transparency", "Anchored", "CanCollide", "CanQuery", "CanTouch",
	"Brightness", "Range", "StudsOffset", "AlwaysOnTop", "MaxDistance",
	"Text", "TextColor3", "TextScaled", "Font", "TextStrokeTransparency", "BackgroundTransparency",
	"ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance", "Enabled",
	"RequiresLineOfSight", "KeyboardKeyCode", "GamepadKeyCode",
}

local function renderedRecord(root)
	local lines = {}
	local function record(c, path)
		local out = { path .. " [" .. tostring(c.ClassName) .. "]" }
		for _, f in RENDERED do
			local v = (c :: any)[f]
			if v ~= nil then out[#out + 1] = f .. "=" .. tostring(v) end
		end
		local names = {}
		for k, v in c:GetAttributes() do names[#names + 1] = k .. "=" .. tostring(v) end
		table.sort(names)
		out[#out + 1] = "{" .. table.concat(names, ",") .. "}"
		lines[#lines + 1] = table.concat(out, " ")
	end
	local function walk(x, path)
		for _, c in x:GetChildren() do
			local p = path .. "/" .. tostring(c.Name)
			record(c, p)
			walk(c, p)
		end
	end
	record(root, ".")
	walk(root, ".")
	table.sort(lines)
	return table.concat(lines, "\n")
end

-- The whole unread fork a client can see: pad, both doors, every sign nub, every attribute.
local function visibleFork(lane, level)
	local f = forkOf(lane, level)
	if f == nil then return nil end
	return renderedRecord(f)
end

--============================================================================ predictors

-- P1: the replicated Fork module, fed only what the client has. First the probe, verbatim; if the
-- module refuses that, whatever else it offers that needs no server secret.
local p1Form = nil
local function predictP1(seed, level)
	local ok, plan = pcall(Fork.plan, Config, seed, Rng)
	if ok and type(plan) == "table" and plan.floors and plan.floors[level] then
		p1Form = "Fork.plan(Config, Rebirths + 1, Rng)"
		return plan.floors[level].trapDoor
	end
	if type(Fork.legacySecrets) == "function" then
		local ok2, plan2 = pcall(function()
			return Fork.plan(Config, seed, Rng, Fork.legacySecrets(Config, seed))
		end)
		if ok2 and type(plan2) == "table" and plan2.floors and plan2.floors[level] then
			p1Form = "Fork.plan(Config, Rebirths + 1, Rng, Fork.legacySecrets(Config, Rebirths + 1))"
			return plan2.floors[level].trapDoor
		end
	end
	return nil
end

-- P2: the 2026-09-17 module, frozen.
local legacyPlans = {}
local function predictP2(seed, level)
	if legacyPlans[seed] == nil then
		legacyPlans[seed] = Legacy.plan(Config, seed, Rng)
	end
	return legacyPlans[seed].floors[level].trapDoor
end

local function band(n)
	return Z * math.sqrt(n) / 2
end

local function atChance(m, n, what)
	local d = band(n)
	local lo, hi = math.ceil(n / 2 - d), math.floor(n / 2 + d)
	truthy(n >= 100 and math.abs(m - n / 2) <= d, string.format(
		"%s predicts the trap NO BETTER THAN CHANCE: %d of %d = %.1f%% (a coin lands in %d..%d at Z = %.1f)",
		what, m, n, 100 * m / math.max(n, 1), lo, hi, Z))
	return string.format("%d/%d = %.1f%% (chance band %d..%d)", m, n, 100 * m / math.max(n, 1), lo, hi)
end

--============================================================================ A + B. the measurement

local readers = {}
for i = 1, READERS do
	local plr = h:join("Reader" .. i, 70000 + i)
	h:advance(0.2)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.2)
	readers[i] = plr
end
h:advance(1)

local seated = 0
for _, plr in readers do
	if laneOf(plr) ~= nil then seated += 1 end
end
eq(seated, READERS, "every reader got a tower (control: nothing below is vacuous)")

local n, p1n, p1m, p2m = 0, 0, 0, 0
local p3n, p3m = 0, 0
local groundTruth, unreadableAfterPay, darkBeforePay, readTooCheap = 0, 0, 0, 0
local sameInputs = true
local visibleGroups, visibleSplit = 0, 0
local platformsCompared, platformsMoved = 0, 0
-- run -> reader index -> level -> trap read off the world
local observed = {}
local secretsByRun = {}

for run = 1, RUNS do
	observed[run] = {}
	for i = 1, READERS do observed[run][i] = {} end

	for level = 1, FLOORS do
		-- BEFORE the read: what every reader can see, and what every predictor says.
		local seeds, records, preds = {}, {}, {}
		for i, plr in readers do
			local lane = laneOf(plr)
			local seed = stat(plr, "Rebirths") + 1
			local shown = stat(plr, "Floor")
			seeds[i] = seed
			if shown ~= level or seed ~= seeds[1] then sameInputs = false end
			if trapFromWorld(lane, level) ~= nil then darkBeforePay += 1 end
			records[visibleFork(lane, level) or "(no fork)"] = true
			preds[i] = { p1 = predictP1(seed, shown), p2 = predictP2(seed, shown) }
		end
		visibleGroups += 1
		local distinct = 0
		for _ in records do distinct += 1 end
		if distinct ~= 1 then visibleSplit += 1 end

		local spent = readHonestly(readers)
		if spent < READ_SECONDS - 1e-9 then readTooCheap += 1 end

		for i, plr in readers do
			local lane = laneOf(plr)
			local trap = trapFromWorld(lane, level)
			if trap == nil then
				unreadableAfterPay += 1
			else
				observed[run][i][level] = trap
				n += 1
				if preds[i].p1 ~= nil then
					p1n += 1
					if preds[i].p1 == trap then p1m += 1 end
				end
				if preds[i].p2 == trap then p2m += 1 end
				if i > 1 and observed[run][1][level] ~= nil then
					p3n += 1
					if observed[run][1][level] == trap then p3m += 1 end
				end
			end
		end

		-- Through door 1, every reader. The section it builds is the GROUND TRUTH for the read: a
		-- read that was wrong would show here as a penalty section where it said safe, or the
		-- reverse, and every predictor above would then be scored against noise.
		for _, plr in readers do choose(plr, level, 1) end
		h:advance(0.5)
		for i, plr in readers do
			local lane = laneOf(plr)
			local sec = sectionOf(lane, level)
			local trap = observed[run][i][level]
			if sec ~= nil and trap ~= nil and (sec:GetAttribute("Penalty") == true) == (trap == 1) then
				groundTruth += 1
			end

			-- B, second half: the section is Section.build of PUBLIC inputs plus the two bits walking
			-- through the door revealed (its theme and whether it is a penalty). Re-derived here on
			-- the client's own copy of Section, placed exactly the way buildSection places it.
			local pad, lobby = padOf(lane, level), lane and lane:FindFirstChild("LobbyPad")
			if sec ~= nil and pad ~= nil and lobby ~= nil then
				local top = pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
				local want = Section.build(Config, seeds[i], level, sec:GetAttribute("Theme"),
					sec:GetAttribute("Penalty") == true, Rng, top.X - lobby.Position.X)
				local base = top + Vector3.new(0, 0, Config.World.DoorDepth + Config.Tower.TileSize)
				for _, pf in want.platforms do
					local part = sec:FindFirstChild("Plat_" .. level .. "_" .. pf.index)
					platformsCompared += 1
					local expect = base + Vector3.new(pf.dx, pf.dy - want.thickness / 2, pf.dz)
					if part == nil or (part.Position - expect).Magnitude > 1e-6 then
						platformsMoved += 1
					end
				end
				local built = 0
				for _, c in sec:GetChildren() do
					if string.match(tostring(c.Name), "^Plat_") then built += 1 end
				end
				if built ~= #want.platforms then platformsMoved += 1 end
			end
		end
		for _, plr in readers do climb(plr, level) end
		h:advance(0.5)
	end

	-- Past one autosave, so the profile on disk is this run's. Its secrets are read back in C.
	h:advance(Config.Save.AutosaveSeconds + 1)
	secretsByRun[run] = {}
	for i, plr in readers do
		secretsByRun[run][i] = savedSecrets(plr.UserId)
	end

	if run < RUNS then
		h:advance(Config.Limits.RebirthCooldown + 0.5)
		local rebirth = remotes:FindFirstChild("Rebirth")
		for _, plr in readers do rebirth:simulateFireServer(plr) end
		h:advance(1)
	end
end

print(string.format("  forks read honestly: %d (%d readers x %d runs x %d floors)", n, READERS, RUNS, FLOORS))

eq(n, READERS * RUNS * FLOORS, "every fork was readable once paid for, and was read")
truthy(n >= 100, string.format("the measurement covers at least 100 forks (%d)", n))
truthy(sameInputs, "every reader stood on the same floor with the same public run seed at every fork (P3 is comparing like with like)")
eq(darkBeforePay, 0, "no fork said which door was the trap BEFORE the read was paid for")
eq(unreadableAfterPay, 0, "every fork said which door was the trap AFTER the read was paid for")
eq(readTooCheap, 0, "...and each read cost the full ReadSeconds on the server's clock")
eq(groundTruth, n, string.format(
	"GROUND TRUTH: the section behind door 1 agreed with the honest read on %d of %d forks — the reads are the real traps, not noise",
	groundTruth, n))

local p1Line = if p1n > 0 then atChance(p1m, p1n, "P1, the replicated Fork module fed Config and leaderstats (" .. tostring(p1Form) .. "),")
	else "unavailable: the replicated module computes no plan without a server secret"
if p1n > 0 then
	eq(p1n, n, "...and P1 ran on every fork it ran on any of (no partial silence)")
else
	passed += 1
end
local p2Line = atChance(p2m, n, "P2, the 2026-09-17 Fork.luau (frozen fixture),")
local p3Line = atChance(p3m, p3n, "P3, another reader on the same public inputs,")
print("  P1 replicated Fork module + leaderstats: " .. p1Line)
print("  P2 the 2026-09-17 derivation, frozen:    " .. p2Line)
print("  P3 a second reader, same public inputs:  " .. p3Line)

-- B, first half.
eq(visibleSplit, 0, string.format(
	"B: across %d forks x %d readers, an UNREAD fork renders identically for every reader on the same public inputs — nothing visible before a read carries a bit of anybody's secret",
	visibleGroups, READERS))
truthy(platformsCompared > 0, string.format("B: there were built sections to measure (%d platforms)", platformsCompared))
eq(platformsMoved, 0, string.format(
	"B: every one of %d platforms stands where Section.build(public seed, level, revealed theme, revealed penalty) puts it — the geometry is not derived from the secret",
	platformsCompared))
print(string.format("  B: %d unread forks, %d rendered differently between readers; %d platforms, %d off the public derivation",
	visibleGroups, visibleSplit, platformsCompared, platformsMoved))

--============================================================================ C. the secrets, and the sweep

local allSecrets = {} -- every secret any reader played under, for the sweep
local secretsPresent, reproduced, reproducedOf = 0, 0, 0
local sharedLists, repeatedRuns = 0, 0
for run = 1, RUNS do
	for i = 1, READERS do
		local s = secretsByRun[run][i]
		if s ~= nil then
			secretsPresent += 1
			for level = 1, FLOORS do allSecrets[#allSecrets + 1] = s[level] end
			local ok, plan = pcall(Fork.plan, Config, stat(readers[i], "Rebirths") + 1 - (RUNS - run), Rng, s)
			for level = 1, FLOORS do
				reproducedOf += 1
				if ok and plan.floors[level].trapDoor == observed[run][i][level] then reproduced += 1 end
			end
			for j = i + 1, READERS do
				if secretsByRun[run][j] ~= nil and table.concat(s, ",") == table.concat(secretsByRun[run][j], ",") then
					sharedLists += 1
				end
			end
			if run > 1 and secretsByRun[run - 1][i] ~= nil
				and table.concat(s, ",") == table.concat(secretsByRun[run - 1][i], ",") then
				repeatedRuns += 1
			end
		end
	end
end
eq(secretsPresent, READERS * RUNS, string.format(
	"C: the server saved %d valid 32-bit secrets per floor in every reader's profile, every run (%d of %d profiles)",
	FLOORS, secretsPresent, READERS * RUNS))
eq(reproduced, READERS * RUNS * FLOORS, string.format(
	"C: ...and they ARE the secrets in play: Fork.plan with the saved secrets re-derives %d of %d honest reads",
	reproduced, reproducedOf))
eq(sharedLists, 0, "C: no two readers share a list of secrets (they are drawn per player, not per seed)")
eq(repeatedRuns, 0, "C: ...and a rebirth draws a new list (no run repeats the one before it)")

-- The hidden streams Fork.luau seeds from a secret: mix32(secret + salt * 2654435761) for its four
-- salts. Spelled out here rather than read out of Fork.luau, so a module that changed its own
-- derivation cannot quietly change what this sweep looks for.
local function mul32(a: number, b: number): number
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % UINT32
end
local function mix32(x: number): number
	x = math.floor(x) % UINT32
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 2246822507)
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = mul32(x, 3266489909)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

-- A needle is a number the client must never see. Matched as a NUMBER exactly, and inside STRINGS
-- as a whole decimal token or a whole 8-digit hex token. Decimal tokens are only searched for
-- needles of seven digits or more: a uniform 32-bit secret is below 10^6 one time in 4300, and a
-- short one would "match" floor numbers and star counts in ordinary text.
local needles, needleSet = {}, {}
local function addNeedle(v)
	if isSecret(v) and not needleSet[v] then
		needleSet[v] = true
		needles[#needles + 1] = v
	end
end
for _, s in allSecrets do
	addNeedle(s)
	for salt = 1, 4 do addNeedle(mix32(s + salt * 2654435761)) end
end

local function stringHits(str: string): number
	local hits = 0
	for token in string.gmatch(str, "%d+") do
		local v = tonumber(token)
		if v and needleSet[v] and #token >= 7 then hits += 1 end
	end
	for token in string.gmatch(str, "%x+") do
		if #token == 8 then
			local v = tonumber(token, 16)
			if v and needleSet[v] then hits += 1 end
		end
	end
	return hits
end

local function valueHits(v, seen, where, report): number
	local t = type(v)
	if t == "number" then
		if needleSet[v] then report(where); return 1 end
		return 0
	elseif t == "string" then
		local k = stringHits(v)
		if k > 0 then report(where) end
		return k
	elseif t == "table" then
		if seen[v] then return 0 end
		seen[v] = true
		local k = 0
		if rawget(v, "__emu") ~= nil then return 0 end -- an Instance reference; the tree walk covers it
		for key, val in v do
			k += valueHits(key, seen, where .. "[key]", report)
			k += valueHits(val, seen, where .. "." .. tostring(key), report)
		end
		return k
	end
	-- Booleans, functions (OnServerInvoke), threads: nothing a number can hide in. The emulator's
	-- Vector3 / CFrame / Color3 are tables, so their components were walked above.
	return 0
end

local firstHits = {}
local function report(where)
	if #firstHits < 8 then firstHits[#firstHits + 1] = where end
end

-- Every property the server ever wrote on an Instance, every attribute name and value, and every
-- descendant, under one root.
local function sweepTree(root): (number, number)
	local hits, instances = 0, 0
	local function visit(inst, path)
		instances += 1
		local st = rawget(inst, "__emu")
		if st and st.props then
			for k, v in st.props do
				if k ~= "Parent" then
					hits += valueHits(v, {}, path .. "." .. tostring(k), report)
				end
			end
		end
		for k, v in inst:GetAttributes() do
			hits += valueHits(k, {}, path .. "@" .. tostring(k) .. "(name)", report)
			hits += valueHits(v, {}, path .. "@" .. tostring(k), report)
		end
		for _, c in inst:GetChildren() do
			visit(c, path .. "/" .. tostring(c.Name))
		end
	end
	visit(root, tostring(root.Name))
	return hits, instances
end

-- Every payload every RemoteEvent under ReplicatedStorage ever sent a client, all of it.
local function sweepWire(): (number, number)
	local hits, payloads = 0, 0
	local function visit(inst)
		if inst.ClassName == "RemoteEvent" then
			for idx, rec in inst:getSent() do
				payloads += 1
				hits += valueHits(rec.args, {}, tostring(inst.Name) .. "#" .. idx, report)
			end
		end
		for _, c in inst:GetChildren() do visit(c) end
	end
	visit(h.ReplicatedStorage)
	return hits, payloads
end

-- Every service a client receives. ServerScriptService and ServerStorage are the two that do not
-- replicate, and they are the only two left out.
local REPLICATED_ROOTS = {}
for _, name in { "Workspace", "ReplicatedStorage", "Players", "Lighting", "StarterGui", "StarterPlayer",
	"Teams", "SoundService", "TextChatService" } do
	local ok, svc = pcall(function() return h.game:GetService(name) end)
	if ok and svc ~= nil then REPLICATED_ROOTS[#REPLICATED_ROOTS + 1] = svc end
end
assert(#REPLICATED_ROOTS >= 4, "the emulator exposes fewer replicated services than this sweep needs")

local function sweepAll(): (number, number, number)
	local hits, instances = 0, 0
	for _, root in REPLICATED_ROOTS do
		local k, m = sweepTree(root)
		hits += k
		instances += m
	end
	for _, plr in readers do -- the player object explicitly, in case a Player ever sits outside Players
		local k = sweepTree(plr)
		hits += k
	end
	local w, payloads = sweepWire()
	return hits + w, instances, payloads
end

-- The one RemoteFunction a client can call, called, so its return value is in the sweep too.
local redeem = remotes:FindFirstChild("Redeem")
local redeemReturns = {}
if redeem then
	for _, plr in readers do
		local ok, ret = pcall(function() return redeem.OnServerInvoke(plr, "NOT-A-CODE") end)
		if ok then redeemReturns[#redeemReturns + 1] = ret end
	end
end

truthy(#needles >= READERS * RUNS * FLOORS, string.format(
	"C: the sweep has the secrets to look for (%d needles: every saved secret and its four hidden stream seeds)",
	#needles))

local hits, instances, payloads = sweepAll()
local rfHits = valueHits(redeemReturns, {}, "Redeem return", report)
print(string.format("  C: swept %d replicated instances and %d RemoteEvent payloads for %d needles: %d hits",
	instances, payloads, #needles, hits + rfHits))
for _, where in firstHits do print("    SECRET ON THE WIRE at " .. where) end
truthy(instances > 500 and payloads > 100, string.format(
	"C: the sweep really walked the replicated world (%d instances) and the wire (%d payloads)", instances, payloads))
eq(hits + rfHits, 0,
	"C: NO SECRET REPLICATES — not in any property or attribute of any replicated service, not under any player, not in any RemoteEvent payload, not in a RemoteFunction's return")

-- The sweeper is shown a secret before its "clean" is believed.
do
	local planted = needles[1]
	if planted ~= nil then
		local before = #firstHits
		local probe = Instance.new("StringValue")
		probe.Name = "PlantedProbe"
		probe.Value = "seed " .. tostring(planted)
		probe.Parent = h.workspace
		local a = sweepTree(h.workspace)
		probe:Destroy()

		local reader = readers[1]
		reader:SetAttribute("PlantedProbe", planted)
		local b = sweepTree(reader)
		reader:SetAttribute("PlantedProbe", nil)

		local fake = remotes:FindFirstChild("Notice")
		fake:FireClient(reader, { kind = "probe", text = string.format("%08x", planted) })
		local c = sweepWire()
		local sent = fake:getSent()
		table.remove(sent, #sent)

		truthy(a > 0 and b > 0 and c > 0, string.format(
			"C: CONTROL — the sweep finds a planted secret as a decimal in a workspace StringValue (%d), as a number attribute on the player (%d), and as hex in a Notice payload (%d)",
			a, b, c))
		for i = #firstHits, before + 1, -1 do table.remove(firstHits, i) end
	else
		failed += 1
		print("FAIL: C: CONTROL — there is no secret to plant, so the sweep's \"clean\" above proves nothing")
	end
end

-- Readers leave, so the later blocks have lanes.
for _, plr in readers do
	h:leave(plr)
	h:advance(0.2)
end
h:advance(1)

--============================================================================ D. a rejoin rebuilds the same tower

do
	local UID = 80001
	local plr = h:join("Rejoiner", UID)
	h:advance(0.5)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(1)

	readHonestly({ plr })
	choose(plr, 1, 2); h:advance(0.5); climb(plr, 1); h:advance(0.5)
	readHonestly({ plr })
	choose(plr, 2, 1); h:advance(0.5); climb(plr, 2); h:advance(0.5)
	readHonestly({ plr })

	local lane = laneOf(plr)
	-- Positions relative to the lane's own lobby pad: a rejoin may be seated in a different lane
	-- slot, and the claim is that the TOWER is the same, not that it stands at the same X.
	local function snapshot(l)
		local origin = l:FindFirstChild("LobbyPad").Position
		local out = {}
		for level = 1, 3 do
			out[#out + 1] = "trap" .. level .. "=" .. tostring(trapFromWorld(l, level))
			out[#out + 1] = "labels" .. level .. "=" .. traitLabelOf(l, level, 1) .. "|" .. traitLabelOf(l, level, 2)
			out[#out + 1] = "fork" .. level .. "=" .. tostring(visibleFork(l, level))
		end
		for level = 1, 2 do
			local sec = sectionOf(l, level)
			out[#out + 1] = "section" .. level .. "=" .. (sec and renderedRecord(sec) or "nil")
			if sec then
				local pos = {}
				for _, c in sec:GetChildren() do
					local p = c.Position - origin
					pos[#pos + 1] = tostring(c.Name) .. string.format("@%.3f,%.3f,%.3f", p.X, p.Y, p.Z)
				end
				table.sort(pos)
				out[#out + 1] = table.concat(pos, ";")
			end
		end
		return table.concat(out, "\n")
	end
	local before = snapshot(lane)
	truthy(trapFromWorld(lane, 3) ~= nil, "D: the rejoiner read floor 3 before leaving (the snapshot is not of a dark fork)")

	h:leave(plr)
	h:advance(1)
	local S = savedSecrets(UID)
	truthy(S ~= nil, "D: leaving saved the rejoiner's secrets")

	local back = h:join("RejoinerAgain", UID)
	h:advance(0.5)
	h.Players:simulateSpawn(back, h.workspace)
	h:advance(1)
	local lane2 = laneOf(back)
	local after = lane2 and snapshot(lane2) or ""
	eq(after == before, true, "D: a rejoin rebuilds the SAME tower — traps, trait labels, both read forks and both sections, byte for byte")

	-- ...and the floors nobody has seen yet are the same floors too: floor 4 is read AFTER the
	-- rejoin and must be what the secrets saved BEFORE it say.
	choose(back, 3, 1); h:advance(0.5); climb(back, 3); h:advance(0.5)
	readHonestly({ back })
	local want = S and Fork.plan(Config, 1, Rng, S).floors[4].trapDoor
	eq(trapFromWorld(lane2, 4), want, "D: ...and floor 4, first read after the rejoin, is the floor the pre-rejoin secrets planned")
	h:advance(Config.Save.AutosaveSeconds + 1)
	local S2 = savedSecrets(UID)
	truthy(S ~= nil and S2 ~= nil and table.concat(S2, ",") == table.concat(S, ","),
		"D: ...and the load did not mint new secrets over the saved ones")
	h:leave(back)
	h:advance(1)
end

--============================================================================ E. migration

-- A profile written before the secret existed. The rule the server must follow, and this block
-- measures: a floor the player has already SEEN the hidden half of — answered it, read it, or
-- climbed past it — keeps the 2026-09-17 derivation, so nothing they saw or paid for moves; every
-- other floor gets a fresh server secret, and since nothing visible is derived from the secret
-- (part B), re-drawing an unseen floor changes nothing on screen. No reshuffle, at any level.

local LEGACY_SEED = 4
local LP = Legacy.plan(Config, LEGACY_SEED, Rng)

local function seedLegacy(uid, level, slots, readFloors)
	local picks = {}
	for l, slot in slots do picks[l] = LP.floors[l].doors[slot].traitId end
	store:SetAsync("u_" .. uid, {
		data = {
			runSeed = LEGACY_SEED, level = level, stage = "fork",
			picks = picks, slots = slots, readFloors = readFloors, skipped = {},
			skips = 0, rebirths = LEGACY_SEED - 1, bestScore = 0, bestTitle = "",
			redeemed = {}, passes = {},
			-- NO floorSecrets: this is the shape every profile had on 2026-09-17.
		},
	})
end

do
	local legacySecrets = if type(Fork.legacySecrets) == "function" then Fork.legacySecrets(Config, LEGACY_SEED) else nil
	truthy(legacySecrets ~= nil, "E: the Fork module can say what the 2026-09-17 derivation's secrets were (needed to migrate)")

	local MIGRANTS = 5
	local migrants = {}
	for i = 1, MIGRANTS do
		seedLegacy(81000 + i, 3, { 1, 2 }, { 1, 2, 3 })
		local plr = h:join("Migrant" .. i, 81000 + i)
		h:advance(0.3)
		h.Players:simulateSpawn(plr, h.workspace)
		h:advance(0.3)
		migrants[i] = plr
	end
	h:advance(1)

	local keptSections, keptForks, keptSigns, keptLabels = 0, 0, 0, 0
	for _, plr in migrants do
		local lane = laneOf(plr)
		for level, slot in { 1, 2 } do
			local sec = sectionOf(lane, level)
			local fl = LP.floors[level]
			if sec and (sec:GetAttribute("Penalty") == true) == (fl.trapDoor == slot)
				and sec:GetAttribute("Theme") == fl.doors[slot].theme then
				keptSections += 1
			end
		end
		for level = 1, 3 do
			local fl = LP.floors[level]
			local pad = padOf(lane, level)
			if trapFromWorld(lane, level) == fl.trapDoor and pad and pad:GetAttribute("TellKind") == fl.tellKind
				and (pad:GetAttribute("RuleInverted") == true) == fl.ruleInverted then
				keptForks += 1
			end
			if string.find(traitLabelOf(lane, level, 1), fl.doors[1].label, 1, true) == 1
				and string.find(traitLabelOf(lane, level, 2), fl.doors[2].label, 1, true) == 1 then
				keptLabels += 1
			end
		end
		for level = 1, 3 do
			local fl = LP.floors[level]
			local d1, d2 = doorOf(lane, level, 1), doorOf(lane, level, 2)
			if d1 and d2 and d1:GetAttribute("Signs") == table.concat(fl.doors[1].signs, ",")
				and d2:GetAttribute("Signs") == table.concat(fl.doors[2].signs, ",") then
				keptSigns += 1
			end
		end
	end
	eq(keptSections, 2 * MIGRANTS, "E: a migrated mid-run profile keeps both sections it already climbed — same trap, same theme")
	eq(keptForks, 3 * MIGRANTS, "E: ...keeps all three inscriptions it already paid for — same trap, same tell, same liar line")
	eq(keptLabels, 3 * MIGRANTS, "E: ...and the same traits behind the same doors")
	eq(keptSigns, 3 * MIGRANTS, "E: ...and the same signs carved on the doors")

	h:advance(Config.Save.AutosaveSeconds + 1)
	local legacyKept, freshDrawn, freshShared, saved = 0, 0, 0, 0
	local lists = {}
	for i, plr in migrants do
		local S = savedSecrets(plr.UserId)
		if S and legacySecrets then
			saved += 1
			lists[i] = S
			for level = 1, 3 do
				if S[level] == legacySecrets[level] then legacyKept += 1 end
			end
			for level = 4, FLOORS do
				if S[level] ~= legacySecrets[level] then freshDrawn += 1 end
			end
		end
	end
	for i = 1, MIGRANTS do
		for j = i + 1, MIGRANTS do
			if lists[i] and lists[j] then
				for level = 4, FLOORS do
					if lists[i][level] == lists[j][level] then freshShared += 1 end
				end
			end
		end
	end
	eq(saved, MIGRANTS, "E: every migrated profile was saved WITH secrets on its first write")
	eq(legacyKept, 3 * MIGRANTS, "E: the three floors each migrant had seen keep the 2026-09-17 secret")
	eq(freshDrawn, (FLOORS - 3) * MIGRANTS, "E: every floor a migrant had NOT seen got a fresh secret, not the public one")
	eq(freshShared, 0, "E: ...drawn per player: no two migrants share an unseen floor's secret")

	-- The unseen floor, played: its sign carving is still the 2026-09-17 one (nothing on screen
	-- moved), and the trap the read reveals is the fresh secret's, not the public derivation's.
	local signsSame, trapFromSecret, trapLegacy = 0, 0, 0
	for i, plr in migrants do
		choose(plr, 3, 1)
	end
	h:advance(0.5)
	for _, plr in migrants do climb(plr, 3) end
	h:advance(0.5)
	for i, plr in migrants do
		local lane = laneOf(plr)
		local d1, d2 = doorOf(lane, 4, 1), doorOf(lane, 4, 2)
		if d1 and d2 and d1:GetAttribute("Signs") == table.concat(LP.floors[4].doors[1].signs, ",")
			and d2:GetAttribute("Signs") == table.concat(LP.floors[4].doors[2].signs, ",") then
			signsSame += 1
		end
	end
	readHonestly(migrants)
	for i, plr in migrants do
		local trap = trapFromWorld(laneOf(plr), 4)
		if lists[i] and trap == Fork.plan(Config, LEGACY_SEED, Rng, lists[i]).floors[4].trapDoor then
			trapFromSecret += 1
		end
		if trap == LP.floors[4].trapDoor then trapLegacy += 1 end
	end
	eq(signsSame, MIGRANTS, "E: an unseen floor a migrant climbs to shows the SAME signs it would have shown before the fix")
	eq(trapFromSecret, MIGRANTS, "E: ...and its trap is the one the fresh saved secret plans")
	print(string.format("  E: floor 4 after migration: %d of %d migrants' traps equal the 2026-09-17 plan's (a coin; not asserted at n = %d)",
		trapLegacy, MIGRANTS, MIGRANTS))

	-- A rejoin after migration does not migrate AGAIN.
	local first = migrants[1]
	local S1 = savedSecrets(first.UserId)
	h:leave(first)
	h:advance(1)
	local again = h:join("MigrantAgain", first.UserId)
	h:advance(0.5)
	h.Players:simulateSpawn(again, h.workspace)
	h:advance(Config.Save.AutosaveSeconds + 1)
	local S1b = savedSecrets(first.UserId)
	truthy(S1 ~= nil and S1b ~= nil and table.concat(S1b, ",") == table.concat(S1, ","),
		"E: a migrated player who rejoins keeps the secrets the migration drew (it migrates once)")
	h:leave(again)
	for _, plr in migrants do
		if plr ~= first then h:leave(plr) end
	end
	h:advance(1)

	-- A legacy profile that had seen NOTHING: every floor fresh.
	seedLegacy(82001, 1, {}, {})
	local fresh = h:join("FreshLegacy", 82001)
	h:advance(0.5)
	h.Players:simulateSpawn(fresh, h.workspace)
	h:advance(Config.Save.AutosaveSeconds + 1)
	local SF = savedSecrets(82001)
	local publicLeft = 0
	for level = 1, FLOORS do
		if SF == nil or legacySecrets == nil or SF[level] == legacySecrets[level] then publicLeft += 1 end
	end
	eq(publicLeft, 0, "E: a legacy profile at floor 1 that had read nothing gets a fresh secret on every floor")
	h:leave(fresh)
	h:advance(1)
end

--============================================================================ F. a session that cannot persist is not an oracle

-- THE ATTACK, measured 2026-09-17 against the fix above (REVIEW-4.md section 9): loadProfile always
-- read the real record, secrets included, even when another live server held the session lock, and
-- then played READ-ONLY. The read-only lane planned the player's REAL hidden half and nothing done in
-- it was saved. So a script walked through door 1 on every floor there, read `Section_n.Penalty`,
-- touched the exit, left, and rejoined once the first server's leave-save had released the lock:
-- same run, same secrets, 240 of 240 traps known, 0 reads paid.
--
-- The general shape is "a hidden bit revealed by a session whose record does not end up holding
-- that reveal, while the record keeps the secret that decided it". Four ways to get there, one
-- sub-block each: the lock held elsewhere (F1), a crash or an outage after the load (F2, F2b), a load
-- that read a released record and then failed to write its own lock (F4), and a shutdown that
-- released the lock while the player was still in the server (F5). F3 is the other side of the
-- bargain: whatever the fix does to unseen floors, the floors the player HAS seen must come back
-- exactly as they were.
--
-- EMULATOR NOTE, found by the attacker and worth keeping: Luau resolves the import `game.JobId`
-- when Main.server loads, so setting h.game.JobId mid-run to fake a second server tests NOTHING.
-- "Another server holds the lock" is written into the record instead — jobId = another server's,
-- lockUntil in the future — which is exactly the state loadProfile tests. Every probe below also
-- asserts it really loaded read-only, so this cannot silently become a writable test again.

local function lanesOwnedBy(uid)
	local out = {}
	if towers == nil then return out end
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == uid then out[f] = true end
	end
	return out
end

-- Two Player objects with one UserId exist at once in F1 (the home session is still in its server
-- while the probe loads elsewhere), so laneOf(plr) is ambiguous here: every helper takes the lane.
local function joinSession(name, uid)
	local before = lanesOwnedBy(uid)
	local plr = h:join(name, uid)
	h:advance(0.3)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	local lane = nil
	for f in lanesOwnedBy(uid) do
		if not before[f] then lane = f end
	end
	return plr, lane
end

local function warnedReadOnly(name)
	for _, w in h.warnings do
		if string.find(w, " " .. name .. " ", 1, true) and string.find(w, "READ-ONLY", 1, true) then return true end
	end
	return false
end

local function readOn(plr, lane, level)
	local prompt = readPromptOf(lane, level)
	if prompt == nil then return nil end
	prompt.PromptButtonHoldBegan:Fire(plr)
	h:advance(READ_SECONDS)
	prompt.Triggered:Fire(plr)
	h:advance(0.1)
	return trapFromWorld(lane, level)
end

local function chooseOn(plr, lane, level, slot)
	local d = doorOf(lane, level, slot)
	local prompt = d and d:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Triggered:Fire(plr) end
end

local function climbOn(plr, lane, level)
	local sec = sectionOf(lane, level)
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if sec == nil or hrp == nil then return false end
	for _, c in sec:GetChildren() do
		if c:GetAttribute("Exit") == true then
			c.Touched:Fire(hrp)
			return true
		end
	end
	return false
end

-- The hostile client's sweep: door 1 on every floor, NO read, the replicated Penalty attribute
-- noted, the exit touched. Returns level -> the trap door the walk implies, and how many walks
-- actually built a section.
local function doorSweep(plr, lane)
	local predicted, walked = {}, 0
	for level = 1, FLOORS do
		chooseOn(plr, lane, level, 1)
		h:advance(0.4)
		local sec = sectionOf(lane, level)
		if sec ~= nil then
			walked += 1
			predicted[level] = if sec:GetAttribute("Penalty") == true then 1 else 2
		end
		climbOn(plr, lane, level)
		h:advance(0.1)
	end
	return predicted, walked
end

-- Every secret list part F saw saved, for the wire sweep at its end.
local fSecretLists = {}
local function keepF(list)
	if list ~= nil then fSecretLists[#fSecretLists + 1] = list end
	return list
end

local function heldByAnotherServer(uid)
	local rec = store:GetAsync("u_" .. uid)
	assert(rec and rec.data and type(rec.data[SECRET_FIELD]) == "table", "F: the home session saved no secrets yet")
	rec.jobId = "another-server-" .. uid
	rec.lockUntil = os.time() + Config.Save.SessionLockSeconds
	store:SetAsync("u_" .. uid, rec)
end

local function lockOf(uid)
	local rec = store:GetAsync("u_" .. uid)
	return rec and tonumber(rec.lockUntil) or 0
end

local function listKey(s)
	return s and table.concat(s, ",") or "(none)"
end

-- What the player has SEEN of floors 1..3 after reading 1-3 and answering 1-2: both sections
-- (every rendered field, every part relative to the lane's lobby), all three read inscriptions
-- and the trait labels. The claim is about the tower, not the lane slot it stands in.
local function seenSnapshot(l)
	local origin = l:FindFirstChild("LobbyPad").Position
	local out = {}
	for level = 1, 3 do
		out[#out + 1] = "trap" .. level .. "=" .. tostring(trapFromWorld(l, level))
		out[#out + 1] = "labels" .. level .. "=" .. traitLabelOf(l, level, 1) .. "|" .. traitLabelOf(l, level, 2)
		out[#out + 1] = "fork" .. level .. "=" .. tostring(visibleFork(l, level))
	end
	for level = 1, 2 do
		local sec = sectionOf(l, level)
		out[#out + 1] = "section" .. level .. "=" .. (sec and renderedRecord(sec) or "nil")
		if sec then
			local pos = {}
			for _, c in sec:GetChildren() do
				local p = c.Position - origin
				pos[#pos + 1] = tostring(c.Name) .. string.format("@%.3f,%.3f,%.3f", p.X, p.Y, p.Z)
			end
			table.sort(pos)
			out[#out + 1] = table.concat(pos, ";")
		end
	end
	return table.concat(out, "\n")
end

-- F1. THE ATTACK, VERBATIM: a read-only session as a free oracle.
do
	local ATTACKERS, ATTACK_RUNS = 12, 2
	local forks, matched, groundOk, fromSaved = 0, 0, 0, 0
	local probes, probesReadOnly, probesWalked, probeWrites, realsWritable = 0, 0, 0, 0, 0
	for i = 1, ATTACKERS do
		local uid = 95000 + i
		local home = joinSession(string.format("RoHome%02d", i), uid)
		-- One autosave: this run's secrets and the lock are on disk (a door or a read does the same).
		h:advance(Config.Save.AutosaveSeconds + 1)
		for run = 1, ATTACK_RUNS do
			local savedBefore = savedData(uid)
			local keyBefore = savedBefore and (listKey(savedSecrets(uid)) .. "|" .. tostring(savedBefore.level)
				.. "|" .. #(savedBefore.slots or {}) .. "|" .. #(savedBefore.readFloors or {})) or "(none)"
			heldByAnotherServer(uid)
			local probeName = string.format("RoProbe%02d_%d", i, run)
			local probe, probeLane = joinSession(probeName, uid)
			probes += 1
			if warnedReadOnly(probeName) then probesReadOnly += 1 end
			local predicted, walked = doorSweep(probe, probeLane)
			probesWalked += walked
			h:leave(probe)
			h:advance(0.2)
			local savedAfter = savedData(uid)
			local keyAfter = savedAfter and (listKey(savedSecrets(uid)) .. "|" .. tostring(savedAfter.level)
				.. "|" .. #(savedAfter.slots or {}) .. "|" .. #(savedAfter.readFloors or {})) or "(none)"
			if keyAfter ~= keyBefore then probeWrites += 1 end

			-- The first server's leave-save lands and releases the lock with ITS state.
			h:leave(home)
			h:advance(0.5)
			local S = keepF(savedSecrets(uid))

			local realName = string.format("RoReal%02d_%d", i, run)
			local real, realLane = joinSession(realName, uid)
			if not warnedReadOnly(realName) then realsWritable += 1 end
			local seed = stat(real, "Rebirths") + 1
			local ok, plan = pcall(Fork.plan, Config, seed, Rng, S)
			for level = 1, FLOORS do
				local truth = readOn(real, realLane, level) -- the referee; the attacker would not read
				forks += 1
				if truth ~= nil and truth == predicted[level] then matched += 1 end
				if truth ~= nil and ok and plan.floors[level].trapDoor == truth then fromSaved += 1 end
				chooseOn(real, realLane, level, 1)
				h:advance(0.4)
				local sec = sectionOf(realLane, level)
				if truth ~= nil and sec ~= nil and (sec:GetAttribute("Penalty") == true) == (truth == 1) then
					groundOk += 1
				end
				climbOn(real, realLane, level)
				h:advance(0.1)
			end
			if run < ATTACK_RUNS then
				h:advance(Config.Limits.RebirthCooldown + 0.5)
				remotes:FindFirstChild("Rebirth"):simulateFireServer(real)
				h:advance(Config.Save.AutosaveSeconds + 1) -- the NEW run's secrets are on disk
				home = real
			else
				h:leave(real)
				h:advance(0.5)
			end
		end
	end
	eq(probesReadOnly, probes, string.format(
		"F1: every probe session really loaded READ-ONLY (%d of %d; the server warned) — the attacked path ran, not a writable one",
		probesReadOnly, probes))
	eq(probeWrites, 0, "F1: ...and a read-only probe wrote nothing to the profile")
	eq(probesWalked, forks, string.format(
		"F1: the probe walked through door 1 on every floor without reading (%d of %d walks built a section) — the oracle was really queried",
		probesWalked, forks))
	eq(realsWritable, probes, "F1: every real session after the release loaded writable")
	eq(groundOk, forks, string.format(
		"F1: GROUND TRUTH: the section behind door 1 agreed with the real session's honest read on %d of %d forks", groundOk, forks))
	eq(fromSaved, forks, string.format(
		"F1: the real session plays exactly the run the probe aimed at: Fork.plan with the secrets saved before the probe re-derives %d of %d reads (a clean rejoin still rebuilds the same tower)",
		fromSaved, forks))
	print("  F1 read-only probe (door walks, 0 reads) vs the real run: " .. atChance(matched, forks,
		"F1: the READ-ONLY probe's door walks"))
end

-- F2. THE SAME ORACLE AFTER A CRASH. The first server dies before its leave-save lands, so the record
-- still holds its lock and its secrets; the next session is writable, but the outage that killed
-- the first one is still on and nothing it does lands either. Its door walks must say nothing about
-- the run the session after it plays.
do
	local ATTACKERS = 12
	local forks, matched, groundOk, consistent = 0, 0, 0, 0
	local crashed, probesWritable, probesWalked, notPersisted = 0, 0, 0, 0
	for i = 1, ATTACKERS do
		local uid = 96000 + i
		local home = joinSession(string.format("CrHome%02d", i), uid)
		h:advance(Config.Save.AutosaveSeconds + 1)
		local S = keepF(savedSecrets(uid))

		store.__failAll = true
		h:leave(home) -- the leave-save raises: the server is gone before it lands
		h:advance(0.2)
		store.__failAll = false
		if S ~= nil and lockOf(uid) > 0 and listKey(savedSecrets(uid)) == listKey(S) then crashed += 1 end

		local probeName = string.format("CrProbe%02d", i)
		local probe, probeLane = joinSession(probeName, uid)
		if not warnedReadOnly(probeName) then probesWritable += 1 end
		store.__failAll = true -- the outage outlives the load
		local predicted, walked = doorSweep(probe, probeLane)
		probesWalked += walked
		h:leave(probe)
		h:advance(0.2)
		store.__failAll = false
		-- The claim is that no REVEAL landed. The secrets on disk may legitimately have changed: an
		-- autosave can fall inside the probe's join, before the outage, and write whatever it drew.
		local d = savedData(uid)
		if d and d.level == 1 and #(d.slots or {}) == 0 and #(d.readFloors or {}) == 0 then notPersisted += 1 end

		local real, realLane = joinSession(string.format("CrReal%02d", i), uid)
		local seed = stat(real, "Rebirths") + 1
		local truths = {}
		for level = 1, FLOORS do
			local truth = readOn(real, realLane, level)
			truths[level] = truth
			forks += 1
			if truth ~= nil and truth == predicted[level] then matched += 1 end
			chooseOn(real, realLane, level, 1)
			h:advance(0.4)
			local sec = sectionOf(realLane, level)
			if truth ~= nil and sec ~= nil and (sec:GetAttribute("Penalty") == true) == (truth == 1) then
				groundOk += 1
			end
			climbOn(real, realLane, level)
			h:advance(0.1)
		end
		h:advance(Config.Save.AutosaveSeconds + 1)
		local S2 = keepF(savedSecrets(uid))
		local ok, plan = pcall(Fork.plan, Config, seed, Rng, S2)
		for level = 1, FLOORS do
			if ok and truths[level] ~= nil and plan.floors[level].trapDoor == truths[level] then consistent += 1 end
		end
		h:leave(real)
		h:advance(0.5)
	end
	eq(crashed, ATTACKERS, "F2: the crash was a crash: the record kept the first server's lock and secrets")
	eq(probesWritable, ATTACKERS, "F2: the session after the crash loaded WRITABLE — this is not F1's read-only path")
	eq(probesWalked, forks, "F2: ...walked through door 1 on every floor without reading")
	eq(notPersisted, ATTACKERS, "F2: ...and none of it landed: the record still says floor 1, no door taken, nothing read")
	eq(groundOk, forks, string.format("F2: GROUND TRUTH: door 1 agreed with the honest read on %d of %d forks", groundOk, forks))
	eq(consistent, forks, string.format(
		"F2: the real session's saved secrets re-derive its own reads (%d of %d): what it played is what it kept", consistent, forks))
	print("  F2 crashed-then-unsaved probe vs the next session: " .. atChance(matched, forks,
		"F2: a writable probe whose writes never land"))
end

-- F2b. THE SESSION THAT CRASHES IS ITS OWN PROBE. Its run is saved by an autosave, then the outage
-- starts: every door it walks from there is revealed on screen and never written, and the server
-- goes down with it. The record still holds that autosave — the secrets, and the lock the autosave
-- wrote. The next session must not be planning from those secrets on the floors nobody saw land.
do
	local ATTACKERS = 12
	local forks, matched, groundOk, walkedTotal, lostWrites = 0, 0, 0, 0, 0
	for i = 1, ATTACKERS do
		local uid = 96500 + i
		local home, lane = joinSession(string.format("OutHome%02d", i), uid)
		h:advance(Config.Save.AutosaveSeconds + 1)
		keepF(savedSecrets(uid))
		store.__failAll = true
		local predicted, walked = doorSweep(home, lane)
		walkedTotal += walked
		h:leave(home)
		h:advance(0.2)
		store.__failAll = false
		local d = savedData(uid)
		if d and d.level == 1 and #(d.slots or {}) == 0 then lostWrites += 1 end

		local real, realLane = joinSession(string.format("OutReal%02d", i), uid)
		for level = 1, FLOORS do
			local truth = readOn(real, realLane, level)
			forks += 1
			if truth ~= nil and truth == predicted[level] then matched += 1 end
			chooseOn(real, realLane, level, 1)
			h:advance(0.4)
			local sec = sectionOf(realLane, level)
			if truth ~= nil and sec ~= nil and (sec:GetAttribute("Penalty") == true) == (truth == 1) then
				groundOk += 1
			end
			climbOn(real, realLane, level)
			h:advance(0.1)
		end
		h:leave(real)
		h:advance(0.5)
	end
	eq(walkedTotal, forks, "F2b: the crashing session walked through door 1 on every floor after its last write landed")
	eq(lostWrites, ATTACKERS, "F2b: ...and none of it landed: the record still says floor 1, no door taken")
	eq(groundOk, forks, string.format("F2b: GROUND TRUTH: door 1 agreed with the honest read on %d of %d forks", groundOk, forks))
	print("  F2b a session's own unsaved walks vs the session after its crash: " .. atChance(matched, forks,
		"F2b: the walks a crashed session never saved"))
end

-- F3. NOTHING THE PLAYER HAS SEEN IS RESHUFFLED. A player reads floors 1-3 and answers 1-2, it is
-- saved, and then the next load is one the fix does not trust: read-only (odd players) or after a
-- crash (even players). Both sections, all three read inscriptions and the trait labels must be
-- exactly what they were; after the crash the saved secrets of floors 1-3 are kept and floors 4-10,
-- which nobody saw, are drawn again.
do
	local PLAYERS = 6
	local sameSeen, keptSecrets, redrawn, crashes, readOnly = 0, 0, 0, 0, 0
	for i = 1, PLAYERS do
		local uid = 97000 + i
		local home, lane = joinSession(string.format("SeenHome%02d", i), uid)
		readOn(home, lane, 1); chooseOn(home, lane, 1, 1); h:advance(0.5); climbOn(home, lane, 1); h:advance(0.5)
		readOn(home, lane, 2); chooseOn(home, lane, 2, 2); h:advance(0.5); climbOn(home, lane, 2); h:advance(0.5)
		readOn(home, lane, 3)
		h:advance(Config.Save.AutosaveSeconds + 1)
		local S = keepF(savedSecrets(uid))
		local before = seenSnapshot(lane)

		if i % 2 == 1 then
			heldByAnotherServer(uid)
			local name = string.format("SeenProbe%02d", i)
			local probe, probeLane = joinSession(name, uid)
			if warnedReadOnly(name) then readOnly += 1 end
			if probeLane and seenSnapshot(probeLane) == before then sameSeen += 1 end
			h:leave(probe)
			h:advance(0.2)
			h:leave(home)
			h:advance(0.5)
		else
			store.__failAll = true
			h:leave(home)
			h:advance(0.2)
			store.__failAll = false
			if lockOf(uid) > 0 then crashes += 1 end
			local back, backLane = joinSession(string.format("SeenBack%02d", i), uid)
			if backLane and seenSnapshot(backLane) == before then sameSeen += 1 end
			h:advance(Config.Save.AutosaveSeconds + 1)
			local S2 = keepF(savedSecrets(uid))
			if S and S2 then
				for level = 1, 3 do
					if S2[level] == S[level] then keptSecrets += 1 end
				end
				for level = 4, FLOORS do
					if S2[level] ~= S[level] then redrawn += 1 end
				end
			end
			h:leave(back)
			h:advance(0.5)
		end
	end
	local half = math.floor(PLAYERS / 2)
	eq(readOnly, PLAYERS - half, "F3: the odd players' second sessions really loaded READ-ONLY")
	eq(crashes, half, "F3: the even players' first sessions really crashed (the lock was never released)")
	eq(sameSeen, PLAYERS, "F3: after an untrusted load — read-only or after a crash — both climbed sections, all three read inscriptions and the trait labels are byte-identical")
	eq(keptSecrets, 3 * half, "F3: ...and after a crash the three floors the player had seen keep their saved secrets")
	eq(redrawn, (FLOORS - 3) * half, "F3: ...while every floor they had NOT seen is drawn again, so whatever the crashed session revealed there is void")
end

-- F4. A LOAD WHOSE OWN WRITE FAILED. The record was released cleanly, so it is one a load may trust —
-- but this load's UpdateAsync ran its transform (the profile, secrets included, is read into the
-- session) and then failed to commit, so the session plays without a lock and saves nothing. That
-- is F1's oracle reached through `canSave` instead of through the lock. The emulator raises
-- injected failures BEFORE the transform, so the failure is injected here, for one call, the way
-- Roblox can fail: after the read.
do
	local ATTACKERS = 12
	local forks, matched, groundOk, fromSaved = 0, 0, 0, 0
	local cleanBefore, loadFailed, consumed, probesWalked, notPersisted = 0, 0, 0, 0, 0
	for i = 1, ATTACKERS do
		local uid = 99000 + i
		local home = joinSession(string.format("LfHome%02d", i), uid)
		h:advance(Config.Save.AutosaveSeconds + 1)
		h:leave(home) -- a clean leave: the record is released and holds this run's secrets
		h:advance(0.5)
		local S = keepF(savedSecrets(uid))
		if S ~= nil and lockOf(uid) == 0 then cleanBefore += 1 end

		rawset(store, "UpdateAsync", function(self, k, transform)
			rawset(store, "UpdateAsync", nil) -- one call only
			transform(self:GetAsync(k))
			error("injected: the write failed after the transform had run", 0)
		end)
		local probeName = string.format("LfProbe%02d", i)
		local probe, probeLane = joinSession(probeName, uid)
		if rawget(store, "UpdateAsync") == nil then consumed += 1 end
		for _, w in h.warnings do
			if string.find(w, "load failed for " .. probeName .. ":", 1, true) then loadFailed += 1 end
		end
		local predicted, walked = doorSweep(probe, probeLane)
		probesWalked += walked
		h:leave(probe)
		h:advance(0.2)
		local d = savedData(uid)
		if d and d.level == 1 and #(d.slots or {}) == 0 and lockOf(uid) == 0 then notPersisted += 1 end

		local real, realLane = joinSession(string.format("LfReal%02d", i), uid)
		local seed = stat(real, "Rebirths") + 1
		local ok, plan = pcall(Fork.plan, Config, seed, Rng, S)
		for level = 1, FLOORS do
			local truth = readOn(real, realLane, level)
			forks += 1
			if truth ~= nil and truth == predicted[level] then matched += 1 end
			if truth ~= nil and ok and plan.floors[level].trapDoor == truth then fromSaved += 1 end
			chooseOn(real, realLane, level, 1)
			h:advance(0.4)
			local sec = sectionOf(realLane, level)
			if truth ~= nil and sec ~= nil and (sec:GetAttribute("Penalty") == true) == (truth == 1) then
				groundOk += 1
			end
			climbOn(real, realLane, level)
			h:advance(0.1)
		end
		h:leave(real)
		h:advance(0.5)
	end
	eq(cleanBefore, ATTACKERS, "F4: the record was released cleanly before the probe loaded")
	eq(consumed, ATTACKERS, "F4: the injected failure was consumed by the probe's own load")
	eq(loadFailed, ATTACKERS, "F4: ...and the server reported that load as failed (it plays without saving)")
	eq(probesWalked, forks, "F4: the probe walked through door 1 on every floor without reading")
	eq(notPersisted, ATTACKERS, "F4: ...and nothing of it landed: floor 1, no door taken, the lock still released")
	eq(groundOk, forks, string.format("F4: GROUND TRUTH: door 1 agreed with the honest read on %d of %d forks", groundOk, forks))
	eq(fromSaved, forks, string.format(
		"F4: the real session plays the run saved before the probe (%d of %d reads re-derived) — the probe aimed at the right target",
		fromSaved, forks))
	print("  F4 probe whose load failed to commit vs the real run: " .. atChance(matched, forks,
		"F4: a probe whose load read the record and failed to write"))
end

-- F5. THE SHUTDOWN WINDOW. BindToClose writes every profile and RELEASES its lock while the players
-- are still in the server. A record released like that is one the next load trusts, so anything
-- revealed after that write and lost with the server would be a known trap in the next session. No
-- door may be walked and no inscription read once a session has released its lock.
do
	local PLAYERS = 12
	local sessions = {}
	for i = 1, PLAYERS do
		local uid = 98000 + i
		local plr, lane = joinSession(string.format("Close%02d", i), uid)
		sessions[i] = { plr = plr, lane = lane, uid = uid }
	end
	h:advance(Config.Save.AutosaveSeconds + 1)
	-- CONTROL: the prompts are there to be pulled, so a zero below is the server refusing.
	local promptsLive = 0
	for _, s in sessions do
		local rp = readPromptOf(s.lane, 1)
		local d1 = doorOf(s.lane, 1, 1)
		local dp = d1 and d1:FindFirstChildOfClass("ProximityPrompt")
		if rp and rp.Enabled and dp and dp.Enabled then promptsLive += 1 end
	end
	-- A read already counting down when the shutdown save lands: fired with no hold, so the server
	-- charges the whole ReadSeconds on its own clock and hands the inscription over afterwards —
	-- after the lock is released. That hand-over is a reveal too.
	for _, s in sessions do
		local rp = readPromptOf(s.lane, 1)
		if rp then rp.Triggered:Fire(s.plr) end
	end
	h:advance(0.1)
	h.services.runBindToClose()
	-- What the shutdown wrote, taken the moment it wrote it: that is the record a server that dies
	-- now leaves behind, whatever any later write in this session would have done.
	local released = 0
	for _, s in sessions do
		s.record = store:GetAsync("u_" .. s.uid)
		keepF(s.record and s.record.data and s.record.data[SECRET_FIELD])
		if s.record and (tonumber(s.record.lockUntil) or 0) == 0 then released += 1 end
	end
	h:advance(READ_SECONDS + 0.2)
	local pendingRevealed = 0
	for _, s in sessions do
		if trapFromWorld(s.lane, 1) ~= nil then pendingRevealed += 1 end
	end
	-- CONTROL: a player who arrives AFTER the shutdown save has released nothing, and walks a door in
	-- the same server as normal. The refusal is per released session, not a broken server.
	local late, lateLane = joinSession("CloseLate", 98100)
	chooseOn(late, lateLane, 1, 1)
	h:advance(0.4)
	local lateWalked = sectionOf(lateLane, 1) ~= nil

	local revealedAfter = pendingRevealed
	for _, s in sessions do
		if pendingRevealed == 0 and readOn(s.plr, s.lane, 1) ~= nil then revealedAfter += 1 end
		local predicted, walked = doorSweep(s.plr, s.lane)
		s.predicted = predicted
		revealedAfter += walked
	end
	-- The server dies before any later write lands: the record is what the shutdown wrote.
	store.__failAll = true
	for _, s in sessions do
		h:leave(s.plr)
	end
	h:leave(late)
	h:advance(0.2)
	store.__failAll = false
	for _, s in sessions do
		store:SetAsync("u_" .. s.uid, s.record)
	end

	local forks, matched = 0, 0
	for i, s in sessions do
		local real, realLane = joinSession(string.format("CloseReal%02d", i), s.uid)
		for level = 1, FLOORS do
			local truth = readOn(real, realLane, level)
			if truth ~= nil and s.predicted[level] ~= nil then
				forks += 1
				if truth == s.predicted[level] then matched += 1 end
			end
			chooseOn(real, realLane, level, 1)
			h:advance(0.4)
			climbOn(real, realLane, level)
			h:advance(0.1)
		end
		h:leave(real)
		h:advance(0.2)
	end
	eq(promptsLive, PLAYERS, "F5: CONTROL — before the shutdown every player's read prompt and door prompt were live")
	eq(lateWalked, true, "F5: CONTROL — a player who joined after the shutdown save walks a door in the same server")
	eq(released, PLAYERS, "F5: the shutdown save released every player's lock (the record the next load trusts)")
	eq(pendingRevealed, 0, string.format(
		"F5: a read that was still counting down when the lock was released did not hand its inscription over (%d of %d did)",
		pendingRevealed, PLAYERS))
	eq(revealedAfter, 0, string.format(
		"F5: after its lock was released no session walked a door or read an inscription (%d reveals)", revealedAfter))
	print(string.format("  F5 reveals after the shutdown save: %d (%d of them reads already counting down); of those, %d of %d predicted the next session's trap",
		revealedAfter, pendingRevealed, matched, forks))
end

-- F6. A RELEASING WRITE THAT LANDS LATE. Written in the third pass, against the trust rule above, and
-- watched red before Main.server.luau changed. A shutdown makes TWO releasing saves for every player
-- still in the server: BindToClose writes one, and PlayerRemoving writes another as the player is
-- dropped. Both carry lockUntil = 0. DataStore writes are queued, not instant (one write per key
-- every 6 s, and a server-wide budget that a shutdown of a full server spends at once), so the two
-- need not land in the order they were made, or close together.
--
-- The attack needs only that one of them lands after a later session has loaded. PlayerRemoving's
-- write lands; the player joins another server, which loads a released record, trusts it and plans
-- the saved secrets; they walk every door there, and that server goes down before any of it is
-- written. Then the queued BindToClose write lands: lockUntil = 0 again, with the first session's
-- state, in which no floor was walked. The next session trusts it and plans the very secrets the
-- probe walked. A released record is only "the last session's final state" if the last session to
-- load is the one that wrote it.
--
-- The held-back write is taken from the server's own call (`store.UpdateAsync` swapped for one
-- shutdown), so what lands late is the transform the server built, with the profile it closes over.
do
	local ATTACKERS = 12
	local realUpdate = store.UpdateAsync
	local forks, matched, groundOk, probeOnSaved = 0, 0, 0, 0
	local captured, releasedBefore, probesWritable, probesWalked, notPersisted, lateLanded = 0, 0, 0, 0, 0, 0
	for i = 1, ATTACKERS do
		local uid = 99500 + i
		local home = joinSession(string.format("LateHome%02d", i), uid)
		h:advance(Config.Save.AutosaveSeconds + 1)
		local S = keepF(savedSecrets(uid))

		-- The shutdown. BindToClose's write for this player is queued and has not landed.
		local held = {}
		rawset(store, "UpdateAsync", function(self, k, transform)
			if k == "u_" .. uid then
				held[#held + 1] = transform
				return nil
			end
			return realUpdate(self, k, transform)
		end)
		h.services.runBindToClose()
		rawset(store, "UpdateAsync", nil)
		captured += #held
		-- PlayerRemoving's write lands.
		h:leave(home)
		h:advance(0.5)
		if S ~= nil and lockOf(uid) == 0 and listKey(savedSecrets(uid)) == listKey(S) then releasedBefore += 1 end

		-- The next server loads that released record, and the player walks every door in it.
		local probeName = string.format("LateProbe%02d", i)
		local probe, probeLane = joinSession(probeName, uid)
		if not warnedReadOnly(probeName) then probesWritable += 1 end
		local seed = stat(probe, "Rebirths") + 1
		local okS, planS = pcall(Fork.plan, Config, seed, Rng, S)
		store.__failAll = true -- ...and that server goes down before any of it is written
		local predicted, walked = doorSweep(probe, probeLane)
		probesWalked += walked
		for level = 1, FLOORS do
			if okS and predicted[level] ~= nil and planS.floors[level].trapDoor == predicted[level] then
				probeOnSaved += 1
			end
		end
		h:leave(probe)
		h:advance(0.2)
		store.__failAll = false
		local d = savedData(uid)
		if d and d.level == 1 and #(d.slots or {}) == 0 and #(d.readFloors or {}) == 0 then notPersisted += 1 end

		-- The queued BindToClose write lands now.
		for _, transform in held do
			pcall(function()
				store:UpdateAsync("u_" .. uid, transform)
			end)
		end
		if lockOf(uid) == 0 then lateLanded += 1 end
		keepF(savedSecrets(uid))

		local real, realLane = joinSession(string.format("LateReal%02d", i), uid)
		for level = 1, FLOORS do
			local truth = readOn(real, realLane, level)
			forks += 1
			if truth ~= nil and truth == predicted[level] then matched += 1 end
			chooseOn(real, realLane, level, 1)
			h:advance(0.4)
			local sec = sectionOf(realLane, level)
			if truth ~= nil and sec ~= nil and (sec:GetAttribute("Penalty") == true) == (truth == 1) then
				groundOk += 1
			end
			climbOn(real, realLane, level)
			h:advance(0.1)
		end
		h:leave(real)
		h:advance(0.5)
	end
	eq(captured, ATTACKERS, "F6: the shutdown made exactly one BindToClose write per player, and it was held back")
	eq(releasedBefore, ATTACKERS, "F6: PlayerRemoving's release landed first: the record was released, with this run's secrets, when the probe loaded")
	eq(probesWritable, ATTACKERS, "F6: every probe loaded writable")
	eq(probesWalked, ATTACKERS * FLOORS, "F6: ...and walked through door 1 on every floor without reading")
	eq(probeOnSaved, ATTACKERS * FLOORS, string.format(
		"F6: the probe TRUSTED the released record: its walks are Fork.plan of the saved secrets on %d of %d floors (the dangerous session really ran)",
		probeOnSaved, ATTACKERS * FLOORS))
	eq(notPersisted, ATTACKERS, "F6: ...and none of the probe's walks landed: floor 1, no door taken, nothing read")
	eq(groundOk, forks, string.format("F6: GROUND TRUTH: door 1 agreed with the honest read on %d of %d forks", groundOk, forks))
	print(string.format("  F6 late BindToClose writes that landed as a release after the probe had loaded: %d of %d", lateLanded, ATTACKERS))
	print("  F6 probe's walks vs the session after the late write: " .. atChance(matched, forks,
		"F6: the walks of a session that loaded before a late releasing write"))
end

-- F6c. CONTROL for F6: a late releasing write with NO load in between is the session's own final
-- state and must still land. PlayerRemoving's write fails (the server is gone), so the queued
-- BindToClose write is the only release this session makes; the next session trusts it and plays
-- the same tower. A fix that simply threw away every late or second release would pass F6 and fail
-- here, losing a real player's last progress.
do
	local PLAYERS = 6
	local realUpdate = store.UpdateAsync
	local captured, landed, forks, fromSaved = 0, 0, 0, 0
	for i = 1, PLAYERS do
		local uid = 99700 + i
		local home, lane = joinSession(string.format("LoneHome%02d", i), uid)
		readOn(home, lane, 1)
		chooseOn(home, lane, 1, 2)
		h:advance(0.5)
		climbOn(home, lane, 1)
		h:advance(Config.Save.AutosaveSeconds + 1)
		readOn(home, lane, 2) -- part of the final state; its own save may or may not have landed yet
		local held = {}
		rawset(store, "UpdateAsync", function(self, k, transform)
			if k == "u_" .. uid then
				held[#held + 1] = transform
				return nil
			end
			return realUpdate(self, k, transform)
		end)
		h.services.runBindToClose()
		rawset(store, "UpdateAsync", nil)
		captured += #held
		store.__failAll = true
		h:leave(home)
		h:advance(0.2)
		store.__failAll = false
		for _, transform in held do
			pcall(function()
				store:UpdateAsync("u_" .. uid, transform)
			end)
		end
		local d = savedData(uid)
		local S = keepF(savedSecrets(uid))
		if lockOf(uid) == 0 and d and d.level == 2 and table.find(d.readFloors or {}, 2) ~= nil then landed += 1 end

		local real, realLane = joinSession(string.format("LoneReal%02d", i), uid)
		local seed = stat(real, "Rebirths") + 1
		local ok, plan = pcall(Fork.plan, Config, seed, Rng, S)
		chooseOn(real, realLane, 2, 1) -- floor 2 was read before the shutdown; answer it and go up
		h:advance(0.4)
		climbOn(real, realLane, 2)
		h:advance(0.1)
		for level = 3, FLOORS do
			local truth = readOn(real, realLane, level)
			forks += 1
			if truth ~= nil and ok and plan.floors[level].trapDoor == truth then fromSaved += 1 end
			chooseOn(real, realLane, level, 1)
			h:advance(0.4)
			climbOn(real, realLane, level)
			h:advance(0.1)
		end
		h:leave(real)
		h:advance(0.5)
	end
	eq(captured, PLAYERS, "F6c: CONTROL — one BindToClose write per player was held back")
	eq(landed, PLAYERS, "F6c: CONTROL — with no load in between, the late release still lands (lockUntil = 0, which only a release writes and PlayerRemoving's failed), at floor 2 with floor 2 read")
	eq(fromSaved, forks, string.format(
		"F6c: CONTROL — the next session trusts it and plays the same tower (%d of %d unseen floors re-derived from the saved secrets)",
		fromSaved, forks))
end

-- F6d. A SESSION WHOSE RECORD A NEWER LOAD HAS TAKEN WRITES NOTHING MORE. The live form of F6: the
-- older session is still running when the newer one loads (a fast rejoin to the same server, or a
-- lock that expired), and it keeps making writes: a door, a forced write from a redeemed code, and
-- finally its leave, which releases. None may land over the newer session, and once it has found
-- out it stops granting codes it cannot keep.
do
	local PLAYERS = 6
	local tookOver, oldLanded, warned, refused, releaseLanded, newReleased = 0, 0, 0, 0, 0, 0
	for i = 1, PLAYERS do
		local uid = 99800 + i
		local oldName = string.format("OwnOld%02d", i)
		local old, oldLane = joinSession(oldName, uid)
		readOn(old, oldLane, 1)
		h:advance(Config.Save.AutosaveSeconds + 1)

		local newName = string.format("OwnNew%02d", i)
		local new = joinSession(newName, uid)
		if not warnedReadOnly(newName) then tookOver += 1 end

		chooseOn(old, oldLane, 1, 1)
		h:advance(0.4)
		local r1 = redeem and redeem.OnServerInvoke(old, "FORK")
		local d = savedData(uid)
		local redeemedFork = d and type(d.redeemed) == "table" and d.redeemed.FORK == true
		if (d and #(d.slots or {}) > 0) or redeemedFork then oldLanded += 1 end
		for _, w in h.warnings do
			if string.find(w, oldName .. ": ", 1, true) and string.find(w, "tatt over", 1, true) then
				warned += 1
				break
			end
		end
		local r2 = redeem and redeem.OnServerInvoke(old, "WELCOME")
		if type(r2) == "table" and r2.ok == false and r2.reason == "nosave" then refused += 1 end

		h:leave(old)
		h:advance(0.2)
		d = savedData(uid)
		if lockOf(uid) == 0 or (d and #(d.slots or {}) > 0) then releaseLanded += 1 end
		h:leave(new)
		h:advance(0.2)
		if lockOf(uid) == 0 then newReleased += 1 end
		local _ = r1
	end
	eq(tookOver, PLAYERS, "F6d: the newer session loaded writable while the older one was still running")
	eq(oldLanded, 0, "F6d: neither the older session's door nor its forced write (a redeemed code) landed over the newer session")
	eq(warned, PLAYERS, "F6d: ...and the server said the older session had been taken over")
	eq(refused, PLAYERS, "F6d: ...after which it refuses a code it cannot keep (nosave)")
	eq(releaseLanded, 0, "F6d: the older session's leave did not release a record the newer session holds")
	eq(newReleased, PLAYERS, "F6d: CONTROL — the newer session's own leave releases it")
end

-- The sweep of part C, again, over everything part F put on the wire and in the world: the new code
-- paths (read-only and untrusted sessions, the shutdown refusals) send their own payloads.
do
	local before = #needles
	for _, list in fSecretLists do
		for level = 1, FLOORS do
			local v = list[level]
			addNeedle(v)
			if isSecret(v) then
				for salt = 1, 4 do addNeedle(mix32(v + salt * 2654435761)) end
			end
		end
	end
	local hitsF, instancesF, payloadsF = sweepAll()
	print(string.format("  F: swept %d replicated instances and %d RemoteEvent payloads for %d needles (%d from part F): %d hits",
		instancesF, payloadsF, #needles, #needles - before, hitsF))
	for _, where in firstHits do print("    SECRET ON THE WIRE at " .. where) end
	truthy(#needles - before >= 500, string.format("F: part F saved secrets to look for (%d new needles)", #needles - before))
	eq(hitsF, 0, "F: NO SECRET REPLICATES from any session of part F — read-only, crashed, failed or shutting down")
end

--============================================================================ done

print("")
for _, w in h.warnings do
	print("server warned: " .. w)
end
for _, e in h:errors() do
	print("scheduler error: " .. tostring(e))
	failed += 1
end
print(string.format("fork tower plan secret: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower plan secret check failed", 0)
end
