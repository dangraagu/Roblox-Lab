-- Gnome Garden Defense: the brag is announced for a WIN only (REVIEW-1, reach finding 2), played for real.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_brag.luau
--
-- REVIEW-1: the garden's progress counted bugs that reached the patch as "gone", so losing to the Slug Queen put
-- progress on 30 and the client played the HARVEST MOON (chip, card, flash) for a LOSS, and the announcer was
-- spent for the real win. Here the real server and the real client scripts (Hud, Garden, View) play autumn: a
-- scripted gardener reaches wave 30, sells every gnome once only the Queen is left, and loses. Nothing of the
-- moon may show. Then TRY AGAIN, and the same gardener plays autumn out (no sale) until the Queen falls: the moon
-- card shows THEN, and the garden view looks up at the moon for the brag.

local Harness = require("./emu/harness")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local Wire = require("../gnome-garden-defense/src/shared/Wire")
local Cfg = require("../gnome-garden-defense/src/shared/Config")
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-brag", viewport = { 844, 390 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 9401
h.game:GetService("DataStoreService"):GetDataStore("GnomeGarden_v1"):SetAsync("u_" .. UID,
	{ data = { chapter = 3, bestWave = 20, bestAt = 1700000000, published = 0, tutorialDone = true } })
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
local me = h:join("Harvester", UID)
h:advance(0.5)
local char = h.Players:simulateSpawn(me, h.workspace)
RunService:setIsServer(false)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.WoodPlanks
hum.MoveDirection = Vector3.new(0, 0, 0)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Garden.client"))
assert(h:tryRun("client/View.client"))

local R = h.ReplicatedStorage.GardenRemotes
local function fire(name, ...)
	h.Players.LocalPlayer = me
	R[name]:FireServer(...)
end
local garden
for _, g in h.workspace.Gardens:GetChildren() do
	if g:GetAttribute("Owner") == UID then garden = g end
end
assert(garden, "the garden")
local function attr(n) return garden:GetAttribute(n) end
local state = me.PlayerGui:FindFirstChild("GardenClientState")
local sky = me.PlayerGui.GardenSky.Root

-- what the player saw: every title card, every chip text, every band the client named, the view's modes
local cards, moonSeen, skyModes = {}, {}, {}
local lastCard = ""
-- the golden celebration flashes (Garden.client's 255,236,170; a hazard hit flashes white) and the frames the brag's
-- own line was on screen (REVIEW-2: the band card replaced it after one frame, and the brag flashed twice)
local golden, pendingFlash, queenLineFrames = 0, {}, 0
me.PlayerGui.ChildAdded:Connect(function(c) if c.Name == "FxFlash" then table.insert(pendingFlash, c) end end)
local bugsOnPath = -1
R.GardenTick.OnClientEvent:Connect(function(t)
	if type(t) == "table" and t.o == UID then bugsOnPath = #Wire.unpackBugs(Cfg, t.b) end
end)
local clock = 0
local function frames(seconds)
	local dt = 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
		clock += dt
		for _, gui in pendingFlash do
			local f = gui:FindFirstChildOfClass("Frame")
			local c = f and f.BackgroundColor3
			if c and math.floor(c.R * 255 + 0.5) == 255 and math.floor(c.G * 255 + 0.5) == 236 and math.floor(c.B * 255 + 0.5) == 170 then
				golden += 1
			end
		end
		table.clear(pendingFlash)
		if sky.BandCard.Visible and sky.BandCard.TextTransparency < 0.5 and string.find(sky.BandCardSub.Text, "The Slug Queen falls!", 1, true) then
			queenLineFrames += 1
		end
		if sky.BandCard.Visible and sky.BandCard.Text ~= lastCard then
			lastCard = sky.BandCard.Text
			table.insert(cards, { text = lastCard, at = clock, phase = attr("Phase"), progress = attr("Progress") })
		end
		if string.find(sky.BandChip.Text, "HARVEST MOON", 1, true) == 1 or state:GetAttribute("Band") == "moon" then
			table.insert(moonSeen, { at = clock, phase = attr("Phase"), progress = attr("Progress") })
		end
		if state:GetAttribute("ViewMode") == "sky" then table.insert(skyModes, clock) end
	end
end

-- a gardener that plays autumn well enough to reach the Queen: fourteen gnomes on the pads that see the most path
local PLAN = { "lantern", "mushroom", "sprinkler", "lantern", "mushroom", "pebble", "lantern", "mushroom", "sprinkler",
	"lantern", "mushroom", "pebble", "lantern", "mushroom" }
local function ranked(range)
	local p = PathGen.fromText(Cfg, attr("PathCells"))
	local out = {}
	for id, pd in PathGen.pads(Cfg, p) do
		local _, cover = PathGen.rangeMask(p, pd.cx, pd.cz, range)
		table.insert(out, { id = id, cover = cover })
	end
	table.sort(out, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	return out
end
local function standing()
	local out = {}
	for _, m in garden.Bed.Gnomes:GetChildren() do out[m:GetAttribute("Pad")] = m end
	return out
end
-- REVIEW-2: before each of the bot's plants the pads that glow must be the three best free pads for the gnome the
-- sheet stars, worked out here independently: the unlocked gnome furthest below its share of 4 : 1.5 : 2 : 1.5
-- (autumn unlocks all four), ranked by path studs within its level-1 range (14, 12, 13, 18), ties to the lower pad.
-- Autumn's stars move between all four gnomes, so most beds rank them differently from a Pebble somewhere (the
-- sweep's M59c: a client that lit the Pebble's pads survived the spring-only reach check).
local SHARE = { pebble = 4, sprinkler = 1.5, mushroom = 2, lantern = 1.5 }
local RANGE = { pebble = 14, sprinkler = 12, mushroom = 13, lantern = 18 }
local ORDER = { "pebble", "sprinkler", "mushroom", "lantern" }
local glowChecks, glowWrong, glowDiscriminating = 0, 0, 0
local function glowing()
	local out = {}
	for _, d in garden.Bed:GetChildren() do
		local id = d:GetAttribute("PadId")
		if id and d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			local c = d.Color
			if c.G > c.R and c.G > c.B then table.insert(out, id) end
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end
local function bestFree(kind, have)
	local out = {}
	for _, r in ranked(RANGE[kind]) do
		if not have[r.id] and #out < 3 then table.insert(out, r.id) end
	end
	table.sort(out)
	return table.concat(out, ",")
end
local lastSet, lastSetAt = "", -math.huge
local function checkGlow(have)
	local counts, n = {}, 0
	local key = {}
	for pad, m in have do
		local k = m:GetAttribute("Kind")
		counts[k] = (counts[k] or 0) + 1
		n += 1
		table.insert(key, k .. pad)
	end
	table.sort(key)
	local set = tostring(attr("Attempt")) .. ":" .. table.concat(key, ",")
	if set ~= lastSet then
		lastSet, lastSetAt = set, clock -- the client looks again within half a second (it rescans the bed's pads)
		return
	end
	if clock - lastSetAt < 0.6 or n >= 14 then return end
	local star, gap = nil, -math.huge
	for _, k in ORDER do
		local g = SHARE[k] / 9 * (n + 1) - (counts[k] or 0)
		if g > gap + 1e-9 then star, gap = k, g end
	end
	local want = bestFree(star, have)
	glowChecks += 1
	if glowing() ~= want then glowWrong += 1 end
	if want ~= bestFree("pebble", have) then glowDiscriminating += 1 end
end
local function botTurn()
	local seeds = attr("Seeds") or 0
	local have = standing()
	local ph = attr("Phase")
	if ph == "reveal" or ph == "build" or ph == "wave" or ph == "held" then checkGlow(have) end
	local n = 0
	for _ in have do n += 1 end
	if n < #PLAN then
		local kind = PLAN[n + 1]
		if seeds >= Cfg.Gnomes[kind].levels[1].cost then
			for _, r in ranked(Cfg.Gnomes[kind].levels[1].range) do
				if not have[r.id] then fire("Plant", r.id, kind) return end
			end
		end
		if n >= 6 then -- keep a few seeds working: upgrade while saving for the next gnome
		else return end
	end
	local pick, lvl = nil, 99
	for pad, m in have do
		local l = m:GetAttribute("Level") or 3
		if l < lvl then pick, lvl = pad, l end
	end
	if pick and lvl < 3 then
		local cost = Cfg.Gnomes[have[pick]:GetAttribute("Kind")].levels[lvl + 1].cost
		if seeds >= cost then fire("Upgrade", pick) end
	end
end

-- play until `stop()` says so; READY whenever a build phase is on
local function play(stop, limit)
	local t0 = clock
	while clock - t0 < limit do
		local ph = attr("Phase")
		if stop(ph) then return true end
		if ph == "reveal" or ph == "build" or ph == "held" then
			botTurn()
			if ph ~= "reveal" or (attr("Gnomes") or 0) >= 6 then fire("Ready") end
		elseif ph == "wave" then
			botTurn()
		end
		frames(0.5)
	end
	return false
end

--============================================================ 0. the glow follows the starred gnome (REVIEW-2)
-- A garden where the star is the LANTERN (two Pebbles, a Sprinkler and a Mushroom standing: the Lantern is furthest
-- below its 1.5 share) and where a Lantern's three best free pads (18 studs) are not a Pebble's (14): the four
-- gnomes go on four of the ten best Pebble pads, the first four the test finds that tell the two apart (over 200
-- beds every one had such a four). The pads that glow must be the Lantern's. Then everything is sold again: on the
-- reveal a sale gives everything back, and the brag below starts from 800 seeds as before.
do
	frames(1)
	local r14 = ranked(14)
	local cand = {}
	for k = 1, math.min(10, #r14) do cand[k] = r14[k].id end
	local function top3(range, taken)
		local out = {}
		for _, r in ranked(range) do
			if not taken[r.id] and #out < 3 then table.insert(out, r.id) end
		end
		table.sort(out)
		return table.concat(out, ",")
	end
	local pick = nil
	for a = 1, #cand do for b = a + 1, #cand do for c = b + 1, #cand do for d = c + 1, #cand do
		if pick == nil then
			local t = { [cand[a]] = true, [cand[b]] = true, [cand[c]] = true, [cand[d]] = true }
			if top3(18, t) ~= top3(14, t) then pick = { cand[a], cand[b], cand[c], cand[d] } end
		end
	end end end end
	truthy(pick ~= nil, "(four of the ten best Pebble pads tell a Lantern's best pads from a Pebble's)")
	if pick then
		local kinds = { "pebble", "pebble", "sprinkler", "mushroom" }
		for i, pad in pick do fire("Plant", pad, kinds[i]) end
		frames(1.5)
		eq(#garden.Bed.Gnomes:GetChildren(), 4, "(two Pebbles, a Sprinkler and a Mushroom planted)")
		local taken = {}
		for _, pad in pick do taken[pad] = true end
		local lit = {}
		for _, d in garden.Bed:GetChildren() do
			local id = d:GetAttribute("PadId")
			if id and d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Color.G > d.Color.R and d.Color.G > d.Color.B then
				table.insert(lit, id)
			end
		end
		table.sort(lit)
		print(string.format("  the Lantern starred: glowing %s; a Lantern's best free pads %s, a Pebble's %s", table.concat(lit, ","), top3(18, taken), top3(14, taken)))
		eq(table.concat(lit, ","), top3(18, taken), "with the Lantern starred, the pads that glow are a Lantern's best free ones, not a Pebble's")
		for _, pad in pick do fire("Sell", pad) end
		frames(1)
		eq(attr("Seeds"), 800, "(sold again on the reveal: 800 seeds)")
	end
end

--============================================================ 1. lose to the Slug Queen
local cardsBefore = 0
local sold = false
local reached = play(function(ph)
	if not sold and attr("Wave") == 30 and ph == "wave" and (attr("BossFrac") or -1) >= 0 and bugsOnPath == 1 then
		sold = true
		cardsBefore = #cards
		print(string.format("  wave 30, only the Slug Queen left (%.0f%% health), progress %s: selling every gnome",
			(attr("BossFrac") or 0) * 100, tostring(attr("Progress"))))
		for pad in standing() do fire("Sell", pad) end
	end
	if ph == "lost" and attr("Wave") ~= 30 then
		fire("Restart") -- an earlier wave lost: autumn again
	end
	return sold and ph == "lost"
end, 120 * 60)
truthy(reached, "the scripted gardener reached the Slug Queen and lost to her (" .. string.format("%.1f min", clock / 60) .. ")")
frames(3)
local lostAt = clock
local p = attr("Progress") or 0
print(string.format("  lost at wave 30: Progress %.3f, band %s, chip '%s'", p, tostring(state:GetAttribute("Band")), sky.BandChip.Text))
truthy(p < 30, "losing to the Queen leaves progress below 30 (" .. p .. ")")
local moonCard = false
for i = cardsBefore + 1, #cards do
	if string.find(cards[i].text, "HARVEST MOON", 1, true) then moonCard = true end
end
truthy(not moonCard, "no HARVEST MOON card is shown for a loss")
truthy(string.find(sky.BandChip.Text, "HARVEST MOON", 1, true) ~= 1, "the band chip does not name the moon (" .. sky.BandChip.Text .. ")")
truthy(state:GetAttribute("Band") ~= "moon", "the client is not in the moon band")
truthy(#skyModes == 0, "and the view did not look up at the moon")
eq(me.PlayerGui.GardenHud.Root.ResultPanel.ResultTitle.Text, "The bugs ate your carrots!", "the result panel says it was a loss")

--============================================================ 2. TRY AGAIN, and win: the moon shows then
fire("Restart")
frames(1)
local goldenBefore, queenBefore = golden, queenLineFrames
local won = play(function(ph)
	if ph == "lost" then fire("Restart") end
	return ph == "won" or attr("Chapter") ~= 3
end, 240 * 60)
truthy(won, string.format("the scripted gardener then beats the Slug Queen (%.1f min after the loss)", (clock - lostAt) / 60))
frames(6)
local winCard = false
for i = cardsBefore + 1, #cards do
	if string.find(cards[i].text, "HARVEST MOON", 1, true) then winCard = true end
end
truthy(winCard, "the HARVEST MOON card shows for the win (the announcer was not spent by the loss)")
truthy(#skyModes > 0, "and the garden view looks up at the moon for the brag")
print(string.format("  the view looked at the sky for %.1f s", #skyModes * 0.1))
print(string.format("  golden flashes for the win: %d; the line 'The Slug Queen falls!' on screen %.1f s", golden - goldenBefore,
	(queenLineFrames - queenBefore) * 0.1))
eq(golden - goldenBefore, 1, "the brag flashes once, not once per card")
truthy(queenLineFrames - queenBefore >= 40, string.format("and its line 'The Slug Queen falls!' stays readable 4 s or more (%.1f s)",
	(queenLineFrames - queenBefore) * 0.1))

print(string.format("  the glow checked %d times before the bot acted: %d wrong; %d of them where the starred gnome's best pads were not a Pebble's",
	glowChecks, glowWrong, glowDiscriminating))
truthy(glowChecks >= 20, "(the glow was checked " .. glowChecks .. " times)")
eq(glowWrong, 0, "the pads that glow are always the three best free pads for the starred gnome")

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(("gnome garden brag: %d passed, %d failed"):format(passed, failed))
