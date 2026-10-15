-- Gnome Garden Defense: the long-term goal past the brag, played for real, and no brag replayed on a join.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_frost.luau
--
-- The real server and the real client scripts (Hud, Garden, View) on an 844x390 touch phone:
--   1. A gardener whose save is at Frost joins. Frost's bed starts at Progress 30, which is the HARVEST MOON band
--      (the brag's band). The client names where they are, quietly: no flash, no 4.5 s card, no look up at the
--      moon for a win from an earlier session. (Found by the build on 2026-10-07: the first sight of Progress 30
--      celebrated the moon, with the sky look, on every join of a Frost gardener.)
--   2. A scripted gardener plays Frost through the real remotes until the Frost Mantis falls (a lost bed is
--      retried with the result panel's TRY AGAIN), then presses the result panel's NEXT: MOONLIT BED.
--   3. The endless Moonlit Bed: chapter 5, wave 41, 2600 seeds, the day's shared bed (another server drew it
--      today), the band Moonlit Snow. READY, and wave 41 survived: best wave 41 on the player, and after the
--      leave in the saved profile (chapter 5) and on the board's store.
-- Every number asserted is spelled out here, not read from Config (a rule checked against itself is not a rule).

local Harness = require("./emu/harness")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local Rng = require("../gnome-garden-defense/src/shared/Rng")
local Cfg = require("../gnome-garden-defense/src/shared/Config")
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-frost", viewport = { 844, 390 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 9701
local DSS = h.game:GetService("DataStoreService")
local store = DSS:GetDataStore("GnomeGarden_v1")
local daily = DSS:GetDataStore("GnomeGarden_Daily_v1")
local lb = DSS:GetOrderedDataStore("GnomeGarden_LB_v1")
local SHARED = 424242421 -- the endless bed another server drew today
daily:SetAsync("d_" .. math.floor(os.time() / 86400), SHARED)
store:SetAsync("u_" .. UID, { data = { chapter = 4, bestWave = 30, bestAt = 1700000000, published = 30, tutorialDone = true } })

-- The profile load takes 2 s (a DataStore round trip), and the client scripts start during it, as they do on
-- Roblox: the garden folder (its Owner set before the load) is there, but not dug yet (no Progress).
local LOAD_SECONDS = 2
do
	local orig, slowOnce = store.UpdateAsync, true
	store.UpdateAsync = function(self, k, f)
		if slowOnce then
			slowOnce = false
			task.wait(LOAD_SECONDS)
		end
		return orig(self, k, f)
	end
end
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
-- PlayerAdded runs on the caller's thread in robloxemu, and its load yields: join from a thread of its own
task.spawn(function() h:join("Frosty", UID) end)
local me = h.Players:FindFirstChild("Frosty")
assert(me, "the player joined")
if me:FindFirstChild("PlayerGui") == nil then -- Harness.join adds it only once PlayerAdded returns
	local pg = h.instance.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = me
end
h.Players.LocalPlayer = me
local char = h.Players:simulateSpawn(me, h.workspace)
RunService:setIsServer(false)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.WoodPlanks
hum.MoveDirection = Vector3.new(0, 0, 0)
-- what the player saw: every celebration flash (Garden.client's golden 255,236,170 one; a hazard hit flashes white),
-- every title card and how long it stayed, the view's modes
local flashes, pendingFlash = 0, {}
me.PlayerGui.ChildAdded:Connect(function(c) if c.Name == "FxFlash" then table.insert(pendingFlash, c) end end)
local function countFlashes()
	for _, gui in pendingFlash do
		local f = gui:FindFirstChildOfClass("Frame")
		local c = f and f.BackgroundColor3
		if c and math.floor(c.R * 255 + 0.5) == 255 and math.floor(c.G * 255 + 0.5) == 236 and math.floor(c.B * 255 + 0.5) == 170 then
			flashes += 1
		end
	end
	table.clear(pendingFlash)
end
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
local result = me.PlayerGui.GardenHud.Root.ResultPanel

local cards, skyFrames, cardFrames = {}, 0, 0
local lastCard = ""
local clock = 0
local function frames(seconds)
	local dt = 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
		clock += dt
		countFlashes()
		if sky.BandCard.Visible then
			cardFrames += 1
			-- a new title, or a new line under it (REVIEW-2: a band reached with the season's win joins that card's
			-- line instead of replacing the card)
			if sky.BandCard.Text .. "|" .. sky.BandCardSub.Text ~= lastCard then
				lastCard = sky.BandCard.Text .. "|" .. sky.BandCardSub.Text
				table.insert(cards, { text = sky.BandCard.Text, sub = sky.BandCardSub.Text, at = clock, phase = attr("Phase"), wave = attr("Wave") })
			end
		end
		if state:GetAttribute("ViewMode") == "sky" then skyFrames += 1 end
	end
end

--============================================================ 1. a Frost gardener joins: where they are, quietly
frames(0.5)
eq(attr("Progress"), nil, "(precondition) half a second in, the load is still out and the client sees an undug garden")
frames(8)
eq(me:GetAttribute("Chapter"), 4, "the load returned: the player is at Frost")
eq(attr("Chapter"), 4, "the save is at Frost: the garden starts chapter 4")
eq(attr("Progress"), 30, "on Progress 30 (the brag's band starts here)")
eq(state:GetAttribute("Band"), "moon", "the client is in the HARVEST MOON band")
local joinCard = cards[1]
truthy(joinCard ~= nil and string.find(joinCard.text, "HARVEST MOON", 1, true) ~= nil,
	"the first card names where the gardener is (" .. tostring(joinCard and joinCard.text) .. ")")
eq(flashes, 0, "but nothing is celebrated on a join: no golden flash")
eq(skyFrames, 0, "and the view does not look up at the moon")
truthy(cardFrames <= 39, string.format("and the card stays a quiet card's time, 3.8 s at most (%.1f s)", cardFrames * 0.1))

--============================================================ 2. Frost played for real, to the Frost Mantis
-- a gardener with fourteen gnomes on the pads that see the most path (the brag check's plan)
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
local function botTurn()
	local seeds = attr("Seeds") or 0
	local have = standing()
	local n = 0
	for _ in have do n += 1 end
	if n < #PLAN then
		local kind = PLAN[n + 1]
		if seeds >= Cfg.Gnomes[kind].levels[1].cost then
			for _, r in ranked(Cfg.Gnomes[kind].levels[1].range) do
				if not have[r.id] then fire("Plant", r.id, kind) return end
			end
		end
		if n < 6 then return end
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

local attempts, flashesBefore = 1, flashes
local won = false
local t0 = clock
while clock - t0 < 240 * 60 do
	local ph = attr("Phase")
	if ph == "won" then won = true break end
	if ph == "lost" then
		if result.Visible then
			attempts += 1
			result.ResultButton.Activated:Fire() -- TRY AGAIN
		end
	elseif ph == "reveal" or ph == "build" or ph == "held" then
		botTurn()
		if ph ~= "reveal" or (attr("Gnomes") or 0) >= 6 then fire("Ready") end
	elseif ph == "wave" then
		botTurn()
	end
	frames(0.5)
end
truthy(won, string.format("the scripted gardener beats the Frost Mantis (%.1f min, %d attempt(s))", (clock - t0) / 60, attempts))
frames(2)
eq(attr("Wave"), 40, "the Mantis was wave 40")
eq(me:GetAttribute("BestWave"), 40, "the best wave is 40")
eq(me:GetAttribute("Chapter"), 5, "and the Moonlit Bed is unlocked on the player")
eq(result.Visible, true, "the result panel is up")
eq(result.ResultTitle.Text, "FROST WON!", "it says FROST WON!")
eq(result.ResultButton.Text, "NEXT: MOONLIT BED", "and offers the Moonlit Bed")
eq(state:GetAttribute("Band"), "moonlit", "the season turned: the client is in the Moonlit Snow band")
local wonCard = false
for _, c in cards do if string.find(c.text, "FROST WON", 1, true) then wonCard = true end end
truthy(wonCard, "the season's win shows its card (FROST WON)")
eq(flashes - flashesBefore, 1, "and that win is the one celebration of Frost (one golden flash): Moonlit Snow itself is not celebrated")
eq(skyFrames, 0, "and no band of Frost looked up at the sky")
-- a band is named once its `from` wave is SURVIVED, never while that wave still runs (a Mantis with a sliver of
-- health left rounded up onto 40 and named Moonlit Snow while it walked: 4 of 6 runs before the fix)
local FROM = { ["FIRST FROST"] = 31, ["SNOWFALL"] = 35, ["MOONLIT SNOW"] = 40 }
local early, named = {}, 0
local prevText = ""
for _, c in cards do
	local text = string.upper(c.text .. " " .. (c.sub or ""))
	for name, from in FROM do
		-- a name counts when a card shows it that the card before did not (a line added under the same title is
		-- the same naming)
		if string.find(text, name, 1, true) and not string.find(prevText, name, 1, true) then
			named += 1
			if c.phase == "wave" and (c.wave or 0) <= from then
				table.insert(early, string.format("%s during wave %s", name, tostring(c.wave)))
			end
		end
	end
	prevText = text
end
eq(named, 3, "Frost's three bands were each named once (First Frost, Snowfall, Moonlit Snow)")
eq(#early, 0, "and none before its wave was survived (" .. table.concat(early, ", ") .. ")")
local seen = {}
for _, c in cards do table.insert(seen, string.format("%s (%s) at %.1f min", c.text, c.sub, c.at / 60)) end
print("  cards: " .. table.concat(seen, "; "))

--============================================================ 3. the endless Moonlit Bed: the day's shared bed
result.ResultButton.Activated:Fire() -- NEXT: MOONLIT BED
frames(3)
eq(attr("Chapter"), 5, "NEXT: the endless chapter")
eq(attr("Season"), "Moonlit Bed", "named the Moonlit Bed")
eq(attr("Endless"), true, "and endless")
eq(attr("Phase"), "reveal", "on a fresh bed, waiting for READY")
eq(attr("Wave"), 41, "at wave 41")
eq(attr("Seeds"), 2600, "with 2600 seeds")
eq(attr("Progress"), 40, "Progress 40")
local info = h.game:GetService("ServerStorage").GardenInfo:FindFirstChild(tostring(UID))
eq(info and info:GetAttribute("BedSeed"), SHARED, "the bed is the day's shared bed (the seed another server drew today)")
eq(attr("PathCells"), PathGen.encodeCells(PathGen.genPath(Cfg, Rng.new(SHARED)).cells), "and the path the player sees is that bed's")
local beforeEndless = attr("Wave")
local survived = false
local t1 = clock
while clock - t1 < 15 * 60 do
	local ph = attr("Phase")
	if (attr("Wave") or 0) >= 42 and (ph == "build" or ph == "held") then survived = true break end
	if ph == "lost" then break end
	if ph == "reveal" or ph == "build" then
		botTurn()
		if ph ~= "reveal" or (attr("Gnomes") or 0) >= 10 then fire("Ready") end
	elseif ph == "wave" then
		botTurn()
	end
	frames(0.5)
end
truthy(survived, "the endless bed's first wave (41) is survived (from wave " .. tostring(beforeEndless) .. ")")
eq(me:GetAttribute("BestWave"), 41, "best wave 41 on the player")

-- the leave saves: chapter 5 and best wave 41, and the board's store ranks wave 41
h:leave(me)
h:advance(2)
local rec = store:GetAsync("u_" .. UID)
eq(rec and rec.data and rec.data.chapter, 5, "the saved profile is at the Moonlit Bed")
eq(rec and rec.data and rec.data.bestWave, 41, "with best wave 41")
local v = lb:GetAsync("u_" .. UID)
eq(type(v) == "number" and math.floor(v / 2e9), 41, "the board's store ranks wave 41 (value " .. tostring(v) .. ")")

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(("gnome garden frost: %d passed, %d failed"):format(passed, failed))
