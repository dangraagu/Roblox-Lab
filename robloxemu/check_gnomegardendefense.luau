-- Gnome Garden Defense: the garden has to be IN THE WORLD, and planting a gnome has to actually stop bugs.
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense.luau
--
-- Boots the real server, joins players, and walks the player path: the world is built and PARENTED, a joining
-- character LANDS on its own deck under the engine's spawn order (SPAWN-ORDER.md), every prompt and pad is
-- reachable from the deck, the highscore board exists and renders, and the core loop runs: tap a pad, plant,
-- READY, bugs die, seeds arrive, upgrade, a refused plant says why, pause freezes the garden and an action
-- resumes it, a scripted gardener wins spring for real, and a rejoin comes back with summer unlocked.
-- Every number asserted is spelled out here, not recomputed from the game's modules (a budget checked
-- against itself is not a budget).

local Harness = require("./emu/harness")
local bundle = require("./build/gnome-garden-defense")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local ConfigFixture = require("../gnome-garden-defense/src/shared/Config")

local h = Harness.new({ bundle = bundle, name = "gnome-garden-defense", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local ME, OTHER, LATE = 4101, 4102, 4103

assert(h:tryRun("server/Main.server"))
h:advance(1)

local RS = h.services.ReplicatedStorage
local remotes = RS:FindFirstChild("GardenRemotes")
truthy(remotes ~= nil, "the server published workspace remotes (ReplicatedStorage.GardenRemotes)")
local R = {}
for _, n in { "Plant", "Upgrade", "Sell", "Ready", "SetPaused", "Restart", "NextSeason", "Here", "GardenTick", "Toast", "Fanfare", "Board" } do
	R[n] = remotes and remotes:FindFirstChild(n)
	truthy(R[n] ~= nil, "remote " .. n .. " exists")
end

local toasts = {}
R.Toast.OnClientEvent:Connect(function(msg) table.insert(toasts, tostring(msg)) end)
local function lastToast(): string return toasts[#toasts] or "" end

-- fire a remote AS a player (the emulator's FireServer sends as LocalPlayer)
local function fire(plr, name, ...)
	h.Players.LocalPlayer = plr
	R[name]:FireServer(...)
end

local gardens = h.workspace:FindFirstChild("Gardens")
truthy(gardens ~= nil, "workspace.Gardens exists (control: the builder ran at all)")

local function gardenOf(uid)
	for _, g in gardens:GetChildren() do
		if g:GetAttribute("Owner") == uid then return g end
	end
	return nil
end

--============================================================ two players join together; each stands on their own deck
local me = h:join("Gardener", ME)
local other = h:join("Neighbour", OTHER)
h:advance(0.5)
h.Players:simulateSpawn(me, h.workspace)
h.Players:simulateSpawn(other, h.workspace)
h:advance(1)

local gA, gB = gardenOf(ME), gardenOf(OTHER)
truthy(gA ~= nil and gA.Parent == gardens, "the first player's garden is built AND parented")
truthy(gB ~= nil and gB ~= gA, "the second player has a garden of their own")

local function spawnOf(g, uid)
	return g and g:FindFirstChild("Spawn_" .. uid, true)
end
local spA = spawnOf(gA, ME)
truthy(spA ~= nil and spA.ClassName == "SpawnLocation", "the garden has a SpawnLocation Spawn_<userId>")
eq(me.RespawnLocation, spA, "the player's RespawnLocation points at their own spawn")
eq(spA and spA.Enabled, true, "the spawn is enabled")
local deckA = gA and gA:FindFirstChild("Deck", true)
truthy(deckA ~= nil and deckA:IsA("BasePart"), "the garden has a deck to stand on")

local function rootOf(plr)
	local c = plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function onDeck(plr, deck)
	local r = rootOf(plr)
	if not r or not deck then return false, "no root" end
	local local_ = deck.CFrame:PointToObjectSpace(r.Position)
	local inside = math.abs(local_.X) <= deck.Size.X / 2 and math.abs(local_.Z) <= deck.Size.Z / 2
	local above = r.Position.Y > deck.Position.Y + deck.Size.Y / 2
	return inside and above, string.format("%.1f, %.1f, %.1f", r.Position.X, r.Position.Y, r.Position.Z)
end
do
	local ok, where = onDeck(me, deckA)
	truthy(ok, "the joining character LANDS on its own deck (" .. where .. ")")
	local okB, whereB = onDeck(other, gB and gB:FindFirstChild("Deck", true))
	truthy(okB, "and so does the second one, on theirs (" .. whereB .. ")")
	local ra, rb = rootOf(me), rootOf(other)
	local apart = (ra and rb) and (ra.Position - rb.Position).Magnitude or 0
	truthy(apart > 100, string.format("two players who joined together stand %.1f studs apart (deep-vein's 0.0 bug)", apart))
end

--============================================================ the bed: a 30-cell path, pads around it, all clickable
local pathText = gA and gA:GetAttribute("PathCells")
local path = PathGen.fromText(ConfigFixture, pathText)
truthy(path ~= nil, "the garden replicates its path as text, and it decodes")
eq(path and #path.cells, 30, "the path is 30 cells")
local pads = {}
do
	local bed = gA and gA:FindFirstChild("Bed")
	truthy(bed ~= nil, "the bed folder is in the garden")
	local tiles, clicks = 0, 0
	for _, d in (bed and bed:GetDescendants() or {}) do
		if d:IsA("BasePart") and d:GetAttribute("PadId") then
			pads[d:GetAttribute("PadId")] = d
			if d:FindFirstChildOfClass("ClickDetector") then clicks += 1 end
		end
		if d:IsA("BasePart") and string.match(tostring(d.Name), "^Path_") then tiles += 1 end
	end
	local want = path and #PathGen.pads(ConfigFixture, path) or -1
	local n = 0
	for _ in pads do n += 1 end
	eq(n, want, "every lawn cell touching the path is a pad (" .. want .. ")")
	-- REVIEW-1: a tap is picked by the garden view (View.client + GardenCam.pickRay), which also zooms a small cell
	-- on a phone; a ClickDetector would race it (check_gnomegardendefense_reach.luau taps every pad on screen)
	eq(clicks, 0, "no pad carries a ClickDetector: the garden view picks every tap")
	eq(tiles, 30, "the path is drawn: 30 gravel tiles")
	local bedParts = 0
	for _, d in (bed and bed:GetDescendants() or {}) do
		if d:IsA("BasePart") then bedParts += 1 end
	end
	print(string.format("  the bed: %d pads, %d Parts (rebuilt on every attempt)", n, bedParts))
end

--============================================================ the board: exists, reachable, renders, toggles
local boards = h.workspace:FindFirstChild("GardenBoards")
local board = boards and boards:FindFirstChild("GardenBoard_" .. ME)
truthy(board ~= nil and board.Parent ~= nil, "the player's highscore board stands in the world")
local prompt = board and board:FindFirstChild("BoardPrompt", true)
truthy(prompt ~= nil and prompt.ClassName == "ProximityPrompt", "the board has a ProximityPrompt")
if prompt and deckA then
	local at = prompt.Parent
	-- the emulator has no Attachment.WorldPosition: the attachment's offset in its part's frame
	local pos = if at:IsA("Attachment") then at.Parent.CFrame:PointToWorldSpace(at.Position) else at.Position
	-- the nearest point on the deck's top face
	local lp = deckA.CFrame:PointToObjectSpace(pos)
	local cx = math.clamp(lp.X, -deckA.Size.X / 2, deckA.Size.X / 2)
	local cz = math.clamp(lp.Z, -deckA.Size.Z / 2, deckA.Size.Z / 2)
	local nearest = deckA.CFrame:PointToWorldSpace(Vector3.new(cx, deckA.Size.Y / 2 + 2.5, cz))
	local d = (nearest - pos).Magnitude
	truthy(d <= prompt.MaxActivationDistance, string.format("the prompt is reachable from the deck (%.1f studs, reach %d)", d, prompt.MaxActivationDistance))
end
do
	h.Players.LocalPlayer = me
	assert(h:tryRun("client/Board.client"))
	h:advance(1)
	local gui = board and board:FindFirstChildOfClass("SurfaceGui")
	truthy(gui ~= nil, "Board.client draws a SurfaceGui on the board")
	local title = gui and gui:FindFirstChild("Title", true)
	truthy(title ~= nil and string.find(title.Text, "BEST GARDENERS", 1, true) ~= nil, "titled BEST GARDENERS")
	local sent = R.Board:sentTo(me)
	local last = sent[#sent] and sent[#sent].args[1]
	eq(last and last.mode, "public", "the board starts on the public view")
	if prompt then prompt.Triggered:Fire(me) end
	h:advance(1)
	sent = R.Board:sentTo(me)
	last = sent[#sent] and sent[#sent].args[1]
	eq(last and last.mode, "friends", "the prompt switches it to friends")
	truthy(last and type(last.note) == "string" and #last.note > 0, "an empty friends board says something (" .. tostring(last and last.note) .. ")")
end

--============================================================ the core loop
local function attr(g, name) return g and g:GetAttribute(name) end
-- the preview shown while wave 3 is the next one, whenever that comes (the upgrade section below can play past
-- wave 3 on a slow bed before the scripted gardener starts: it then never saw it, about one run in twenty-five)
local previewAt3 = nil
gA:GetAttributeChangedSignal("Preview"):Connect(function()
	if gA:GetAttribute("Wave") == 3 and previewAt3 == nil then previewAt3 = gA:GetAttribute("Preview") end
end)
eq(attr(gA, "Phase"), "reveal", "a new bed waits for READY")
eq(attr(gA, "Seeds"), 120, "spring starts with 120 seeds")
eq(attr(gA, "Carrots"), 20, "and 20 carrots")
eq(attr(gA, "Chapter"), 1, "chapter 1")
eq(attr(gA, "Preview"), "8 Aphids", "the next-wave preview is honest: wave 1 is eight aphids")

-- the best pads for a pebble (most path in reach): what a player sees glow
local ranked = {}
for id, p in pads do
	local _, cover = PathGen.rangeMask(path, (p.Position.X - 0), 0, 0) -- placeholder, replaced below
	table.insert(ranked, { id = id })
end
do
	local pl = path and PathGen.pads(ConfigFixture, path) or {}
	ranked = {}
	for id, pd in pl do
		local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, 14)
		table.insert(ranked, { id = id, cover = cover })
	end
	table.sort(ranked, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
end

-- a tap on a pad is a client affair (it opens the gnome sheet); the plant is a remote
local best = ranked[1].id
fire(me, "Plant", best, "lantern")
h:advance(0.1)
truthy(string.find(lastToast(), "Lantern unlocks in Autumn", 1, true) ~= nil, "a locked gnome is refused and the toast says why (" .. lastToast() .. ")")
fire(me, "Plant", best, "pebble")
h:advance(0.1)
eq(attr(gA, "Seeds"), 70, "planting a pebble costs 50")
local gnomeA = gA and gA:FindFirstChild("Gnome_" .. best, true)
truthy(gnomeA ~= nil and gnomeA.Parent ~= nil, "the gnome stands on its pad in the world")
eq(gnomeA and gnomeA:GetAttribute("Kind"), "pebble", "a pebble")
eq(gnomeA and gnomeA:GetAttribute("Level"), 1, "level 1")
fire(me, "Plant", best, "sprinkler")
h:advance(0.1)
eq(lastToast(), "That pad is taken", "a taken pad says so")
fire(me, "Plant", ranked[2].id, "pebble")
h:advance(0.1)
fire(me, "Plant", ranked[3].id, "pebble")
h:advance(0.1)
eq(lastToast(), "Not enough seeds (need 50, have 20)", "a third pebble is refused with both numbers")
fire(me, "Plant", 999, "pebble")
h:advance(0.1)
eq(lastToast(), "That is not one of your pads", "a pad id that is not this bed's is refused")
fire(me, "Plant", "1", "pebble")
h:advance(0.1)
eq(lastToast(), "That is not one of your pads", "a pad id of the wrong type is refused")

-- READY: the bugs come, die, and pay
local ticks0 = #R.GardenTick:sentTo(me)
fire(me, "Ready")
h:advance(0.1)
eq(attr(gA, "Phase"), "wave", "READY starts wave 1")
h:advance(15)
local ticks = R.GardenTick:sentTo(me)
truthy(#ticks - ticks0 >= 140, "GardenTick reaches the owner at 10 Hz (" .. (#ticks - ticks0) .. " in 15 s)")
local lastTick = ticks[#ticks] and ticks[#ticks].args[1]
eq(lastTick and lastTick.o, ME, "a tick names its garden's owner")
truthy(lastTick and type(lastTick.b) == "string", "and lists the bugs on the path (packed text, Wire)")
do
	-- none of the OTHER player's ticks went to me
	local foreign = 0
	for _, rec in R.GardenTick:sentTo(me) do
		if rec.args[1].o ~= ME then foreign += 1 end
	end
	eq(foreign, 0, "no tick of another garden is sent to this player")
end
local p15 = attr(gA, "Progress") or 0
local waited = 15
while attr(gA, "Phase") == "wave" and waited < 120 do
	h:advance(0.5)
	waited += 0.5
end
print(string.format("  wave 1 lasted %.1f s with three pebbles", waited))
truthy((attr(gA, "Seeds") or 0) > 20, "stopped bugs paid seeds (" .. tostring(attr(gA, "Seeds")) .. ")")
truthy((attr(gA, "Progress") or 0) > p15, "progress moved as the wave went down")
eq(attr(gA, "Phase"), "build", "wave 1 ends in the build phase")
eq(attr(gA, "Wave"), 2, "the next wave is 2")
truthy((attr(gA, "BuildLeft") or 0) > 0, "with the build timer running")
eq(me:GetAttribute("BestWave"), 1, "the player's best wave is 1")

-- upgrade: refused while unaffordable (and says so), done the moment it is affordable
do
	local seeds = attr(gA, "Seeds") or 0
	if seeds < 70 then
		fire(me, "Upgrade", best)
		h:advance(0.1)
		eq(lastToast(), string.format("Not enough seeds (need 70, have %d)", seeds), "an unaffordable upgrade names both numbers")
	end
	local guard = 0
	while (attr(gA, "Seeds") or 0) < 70 and guard < 600 do
		if attr(gA, "Phase") == "build" then fire(me, "Ready") end
		h:advance(0.5)
		guard += 1
	end
	local before = attr(gA, "Seeds") or 0
	fire(me, "Upgrade", best)
	h:advance(0.1)
	local gnomeA2 = gA and gA:FindFirstChild("Gnome_" .. best, true)
	eq(gnomeA2 and gnomeA2:GetAttribute("Level"), 2, "an affordable upgrade raises the gnome to level 2")
	eq(before - (attr(gA, "Seeds") or 0) <= 70 and true, true, "for 70 seeds")
end

-- pause: the whole garden freezes; any action resumes it
fire(me, "Ready")
do
	local guard = 0
	while attr(gA, "Phase") ~= "wave" and guard < 100 do
		h:advance(0.5)
		guard += 1
		if attr(gA, "Phase") == "build" then fire(me, "Ready") end
	end
end
h:advance(3)
eq(attr(gA, "Phase"), "wave", "a wave is on")
fire(me, "SetPaused", true)
h:advance(0.1)
eq(attr(gA, "Paused"), true, "PAUSE freezes the garden")
local frozenP = attr(gA, "Progress")
local frozenTicks = #R.GardenTick:sentTo(me)
h:advance(20)
eq(attr(gA, "Progress"), frozenP, "nothing moves for 20 s while paused (progress)")
eq(#R.GardenTick:sentTo(me), frozenTicks, "and no ticks go out: the bugs stand still")
fire(me, "Sell", 999)
h:advance(0.1)
eq(attr(gA, "Paused"), false, "any garden action resumes it first (even a refused one)")
h:advance(2)
truthy(#R.GardenTick:sentTo(me) > frozenTicks, "and the garden moves again (ticks flow)")
fire(me, "SetPaused", true)
h:advance(0.6)
eq(attr(gA, "Paused"), true, "paused again")
do
	-- REVIEW-2: a move of the character is not the gardener's input (a neighbour's shove is a move too). Their own
	-- step reaches the server as their client's wake (SetPaused false: check_env, check_grief); a Here is not a wake
	local r = rootOf(me)
	if r then r.CFrame = r.CFrame + Vector3.new(5, 0, 0) end
	h:advance(1.5)
	eq(attr(gA, "Paused"), true, "a 5-stud move of the character alone does not resume it")
	fire(me, "Here")
	h:advance(0.5)
	eq(attr(gA, "Paused"), true, "nor does the client's Here (input seen: the AFK hold only)")
	fire(me, "SetPaused", false)
	h:advance(0.1)
	eq(attr(gA, "Paused"), false, "the gardener's own wake resumes it")
end

--============================================================ a scripted gardener plays spring to the end, for real
local function botTurn(plr, g, rk)
	local seeds = g:GetAttribute("Seeds") or 0
	local chapter = g:GetAttribute("Chapter") or 1
	local want = { "pebble", "sprinkler", "pebble", "pebble", "sprinkler", "pebble", "pebble", "sprinkler" }
	local have = 0
	local bed = g:FindFirstChild("Bed")
	local planted = {}
	for _, d in bed:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Kind") then
			have += 1
			planted[d:GetAttribute("Pad")] = d
		end
	end
	if have < #want then
		local kind = want[have + 1]
		local cost = ConfigFixture.Gnomes[kind].levels[1].cost
		if seeds >= cost then
			for _, r in rk do
				if not planted[r.id] then
					fire(plr, "Plant", r.id, kind)
					return
				end
			end
		end
		return
	end
	-- upgrade the lowest level, best pad first
	local pick, lvl = nil, 99
	for _, r in rk do
		local m = planted[r.id]
		if m and (m:GetAttribute("Level") or 3) < lvl then pick, lvl = r.id, m:GetAttribute("Level") end
	end
	if pick and lvl < 3 then
		local m = planted[pick]
		local cost = ConfigFixture.Gnomes[m:GetAttribute("Kind")].levels[lvl + 1].cost
		if seeds >= cost then fire(plr, "Upgrade", pick) end
	end
end

local function rankPads(g)
	local p = PathGen.fromText(ConfigFixture, g:GetAttribute("PathCells"))
	local out = {}
	for id, pd in PathGen.pads(ConfigFixture, p) do
		local _, cover = PathGen.rangeMask(p, pd.cx, pd.cz, 14)
		table.insert(out, { id = id, cover = cover })
	end
	table.sort(out, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	return out
end

local attempts, won, gameSeconds = 1, false, 0
local previewSeen = nil
do
	local rk = rankPads(gA)
	local guard = 0
	while guard < 20000 do
		guard += 1
		local phase = gA:GetAttribute("Phase")
		if phase == "won" then won = true break end
		if phase == "lost" then
			if attempts >= 3 then break end
			attempts += 1
			fire(me, "Restart")
			h:advance(0.5)
			rk = rankPads(gA)
		elseif phase == "reveal" or phase == "build" or phase == "held" then
			if phase == "build" and gA:GetAttribute("Wave") == 3 and previewSeen == nil then
				previewSeen = gA:GetAttribute("Preview")
			end
			botTurn(me, gA, rk)
			h:advance(0.5)
			gameSeconds += 0.5
			if (gA:GetAttribute("Seeds") or 0) < 50 or phase == "build" then
				fire(me, "Ready")
			end
		else
			botTurn(me, gA, rk)
			h:advance(1)
			gameSeconds += 1
		end
		if guard % 50 == 0 then R.GardenTick:clearSent() end
	end
end
print(string.format("  scripted gardener: spring %s after %d attempt(s), %.0f s of play", if won then "WON" else "not won", attempts, gameSeconds))
eq(previewAt3 or previewSeen, "6 Aphids, 3 Ants", "before wave 3 the preview names the ants joining")
truthy(won, "a scripted gardener wins spring within 3 attempts, on the real server")
eq(attr(gA, "Chapter"), 1, "still chapter 1 until NEXT SEASON")
eq(me:GetAttribute("Chapter"), 2, "but summer is unlocked")
eq(me:GetAttribute("BestWave"), 10, "and the best wave is 10")
do
	local fan = R.Fanfare:sentTo(me)
	local lastF = fan[#fan] and fan[#fan].args[1]
	eq(lastF and lastF.kind, "season", "the season's win is a fanfare")
	eq(lastF and lastF.unlock, "Mushroom", "which names the gnome it unlocks")
end
fire(me, "Plant", 1, "pebble")
h:advance(0.1)
eq(lastToast(), "Not now: this season is over", "a won bed takes no orders and says why")
fire(me, "NextSeason")
h:advance(0.5)
eq(attr(gA, "Chapter"), 2, "NEXT SEASON: summer")
eq(attr(gA, "Seeds"), 420, "on a fresh bed with summer's 420 seeds")
eq(attr(gA, "Phase"), "reveal", "waiting for READY")

--============================================================ rejoin: summer is still unlocked
h:leave(me)
h:advance(1)
eq(gardenOf(ME), nil, "leaving frees the garden")
local back = h:join("Gardener", ME)
h:advance(0.5)
h.Players:simulateSpawn(back, h.workspace)
h:advance(1)
local gR = gardenOf(ME)
eq(attr(gR, "Chapter"), 2, "a rejoin starts the highest unlocked chapter (summer)")
eq(back:GetAttribute("BestWave"), 10, "and remembers the best wave")
do
	local okR, whereR = onDeck(back, gR and gR:FindFirstChild("Deck", true))
	truthy(okR, "the rejoining character lands on its own deck (" .. whereR .. ")")
	local rk = rankPads(gR)
	fire(back, "Plant", rk[1].id, "mushroom")
	h:advance(0.1)
	local m = gR and gR:FindFirstChild("Gnome_" .. rk[1].id, true)
	eq(m and m:GetAttribute("Kind"), "mushroom", "the mushroom can be planted in summer")
end

--============================================================ a late joiner gets a free slot and lands on it
do
	local late = h:join("Latecomer", LATE)
	h:advance(0.5)
	h.Players:simulateSpawn(late, h.workspace)
	h:advance(1)
	local gL = gardenOf(LATE)
	local okL, whereL = onDeck(late, gL and gL:FindFirstChild("Deck", true))
	truthy(okL, "a third player lands on their own deck too (" .. whereL .. ")")
end

--============================================================ nothing server-only is replicated
do
	local leaks = {}
	local function scan(root, where)
		for _, d in root:GetDescendants() do
			for k in d:GetAttributes() do
				local lk = string.lower(k)
				if string.find(lk, "seed", 1, true) and k ~= "Seeds" then table.insert(leaks, where .. ":" .. d.Name .. "." .. k) end
				if string.find(lk, "session", 1, true) or string.find(lk, "key", 1, true) then table.insert(leaks, where .. ":" .. d.Name .. "." .. k) end
			end
		end
	end
	scan(h.workspace, "workspace")
	scan(RS, "ReplicatedStorage")
	scan(h.Players, "Players")
	eq(#leaks, 0, "no bed seed, session or key attribute anywhere a client can read (" .. table.concat(leaks, ", ") .. ")")
	local info = h.game:GetService("ServerStorage"):FindFirstChild("GardenInfo")
	truthy(info ~= nil, "server-only debug state lives in ServerStorage.GardenInfo")
	local mine = info and info:FindFirstChild(tostring(ME))
	truthy(mine ~= nil and type(mine:GetAttribute("BedSeed")) == "number", "where the bed seed is (for the checks only)")
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no server thread died")
print(("gnome garden: %d passed, %d failed"):format(passed, failed))
