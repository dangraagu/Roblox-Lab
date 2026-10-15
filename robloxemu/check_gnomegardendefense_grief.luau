-- Gnome Garden Defense: what ANOTHER player (or a hacked client of theirs) can do to your garden (REVIEW-2).
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_grief.luau
--
-- REVIEW-2, exploit reviewer:
--   1. the server took ANY 4-stud move of a gardener's character between two polls as the gardener being
--      there: a neighbour who walked into a paused gardener (or flung them) resumed the garden, and one shove
--      ended an absent gardener's AFK hold, so the waves came while they were away. Now only the gardener's own
--      input counts: their client's wake (SetPaused false), a garden action, or the client's "Here" (their own
--      thumbstick, keys or taps, never a displacement). And characters do not collide with each other at all;
--   3. the board's ProximityPrompt answered every trigger with a payload (2000 triggers, 2001 payloads). Now a
--      toggle is answered at most once per Config.Board.ToggleSeconds; the rest are refused out loud, at most
--      once a second.
-- The victim runs the real client scripts (Hud, Garden, View); the absent gardener and the griefer are server
-- traffic only. Headless limits: no physics, so a shove is a CFrame move (what the server's poll saw), and the
-- collision group is checked as configured (EYECANDY.md needs-Studio: characters pass through each other).

local Harness = require("./emu/harness")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local Cfg = require("../gnome-garden-defense/src/shared/Config")
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-grief", viewport = { 844, 390 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- robloxemu has no PhysicsService: a stand-in that records what the server asks of the real one
local groups, collide = {}, {}
rawget(h.game, "__registry").PhysicsService = {
	RegisterCollisionGroup = function(_, name) groups[name] = true end,
	CollisionGroupSetCollidable = function(_, a, b, on)
		collide[a .. "|" .. b] = on
		collide[b .. "|" .. a] = on
	end,
}

-- the griefer's 200 friends, all on the board, so a friends view is the expensive one
local friendIds = {}
for i = 1, 200 do friendIds[i] = 20000 + i end
h.Players.GetFriendsAsync = function(self, uid)
	local page = {}
	for _, id in friendIds do table.insert(page, { Id = id, Username = "F" .. id }) end
	return { IsFinished = true, GetCurrentPage = function() return page end, AdvanceToNextPageAsync = function() end }
end
local lb = h.game:GetService("DataStoreService"):GetOrderedDataStore("GnomeGarden_LB_v1")
for _, id in friendIds do lb:SetAsync("u_" .. id, 10 * 2e9 + (2e9 - 1700000000)) end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RunService = h.game:GetService("RunService")
local R = h.ReplicatedStorage.GardenRemotes
local V, AFK, G = 7101, 7102, 7103
local victim = h:join("Victim", V)
local afk = h:join("Away", AFK)
local griefer = h:join("Griefer", G)
h:advance(1)
local vChar = h.Players:simulateSpawn(victim, h.workspace)
local aChar = h.Players:simulateSpawn(afk, h.workspace)
h.Players:simulateSpawn(griefer, h.workspace)
h:advance(1)
local vRoot = vChar:FindFirstChild("HumanoidRootPart")
local vHum = vChar:FindFirstChildOfClass("Humanoid")
vHum.FloorMaterial = Enum.Material.WoodPlanks
vHum.MoveDirection = Vector3.new(0, 0, 0)

-- the victim's own client (and LocalPlayer stays the victim between our other players' requests)
h.Players.LocalPlayer = victim
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Garden.client"))
assert(h:tryRun("client/View.client"))
local function fire(plr, name, ...)
	h.Players.LocalPlayer = plr
	R[name]:FireServer(...)
	h.Players.LocalPlayer = victim
end
local function frames(seconds)
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
	end
end
local function gardenOf(uid)
	for _, g in h.workspace.Gardens:GetChildren() do
		if g:GetAttribute("Owner") == uid then return g end
	end
	return nil
end
local function best2(g)
	local path = PathGen.fromText(Cfg, g:GetAttribute("PathCells"))
	local ranked = {}
	for id, pd in PathGen.pads(Cfg, path) do
		local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, 14)
		table.insert(ranked, { id = id, cover = cover })
	end
	table.sort(ranked, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	return ranked[1].id, ranked[2].id
end
-- the Here pings each player's client sent (the victim's is the only client running here)
local heres = {}
if R:FindFirstChild("Here") then
	R.Here.OnServerEvent:Connect(function(plr) heres[plr] = (heres[plr] or 0) + 1 end)
end
local toastsTo = function(plr)
	local out = {}
	for _, rec in R.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end

--============================================================ characters do not collide with each other
do
	truthy(groups.GardenPlayers == true, "the server registers a collision group for the gardeners")
	eq(collide["GardenPlayers|GardenPlayers"], false, "and gardeners never collide with each other (no shoving, no fling)")
	local outside = 0
	for _, plr in { victim, afk, griefer } do
		for _, d in plr.Character:GetDescendants() do
			if d:IsA("BasePart") and d.CollisionGroup ~= "GardenPlayers" then outside += 1 end
		end
	end
	eq(outside, 0, "every part of every character is in it")
	local hat = Instance.new("Part")
	hat.Name = "HatHandle"
	hat.Parent = aChar
	h:advance(0.1)
	eq(hat.CollisionGroup, "GardenPlayers", "and so is a part that joins a character later (an accessory)")
end

--============================================================ a paused garden stays paused when SOMEONE ELSE moves you
local gV = gardenOf(V)
do
	local a, b = best2(gV)
	h.Players.LocalPlayer = victim
	R.Plant:FireServer(a, "pebble")
	R.Plant:FireServer(b, "pebble")
	frames(0.3)
	R.Ready:FireServer()
	frames(3)
	eq(gV:GetAttribute("Phase"), "wave", "(the victim's wave 1 is on)")
	local pauseBtn = victim.PlayerGui.GardenSky.Root.PauseButton
	pauseBtn.Activated:Fire()
	frames(1)
	eq(gV:GetAttribute("Paused"), true, "the victim pauses with the button")
	local ticks0 = #R.GardenTick:sentTo(victim)
	local everOn = true
	-- a griefer walks into them again and again (a CFrame move is what the server's once-a-second poll sees)
	local home = vRoot.CFrame
	for _, d in { 1, 2, 3, 3.9, 4, 4.2, 6, 8, 10, 12 } do
		vRoot.CFrame = home + Vector3.new(d, 0, 0)
		frames(1.3)
		if gV:GetAttribute("Paused") ~= true then everOn = false end
		vRoot.CFrame = home
		frames(1.3)
		if gV:GetAttribute("Paused") ~= true then everOn = false end
	end
	truthy(everOn, "ten shoves of 1-12 studs, with no input from the victim, never resume the paused garden")
	eq(#R.GardenTick:sentTo(victim) - ticks0, 0, "and not one bug moved meanwhile (no GardenTick)")
	eq(heres[victim] or 0, 0, "the shoves made the victim's client report no input (no Here)")
	-- the victim's OWN step still wakes it (their client asks), and is reported as input
	vHum.MoveDirection = Vector3.new(1, 0, 0)
	frames(1)
	vHum.MoveDirection = Vector3.new(0, 0, 0)
	frames(0.5)
	eq(gV:GetAttribute("Paused"), false, "the victim's own step (the thumbstick) resumes it")
	truthy((heres[victim] or 0) >= 1, "and their client reports it as input (Here: " .. tostring(heres[victim] or 0) .. ")")
end

--============================================================ an absent gardener's AFK hold survives a shove
local gA = gardenOf(AFK)
local victimHeres = heres[victim] or 0
do
	local a, b = best2(gA)
	fire(afk, "Plant", a, "pebble")
	fire(afk, "Plant", b, "pebble")
	fire(afk, "Ready")
	local t = 0
	while t < 900 and gA:GetAttribute("Phase") ~= "held" and gA:GetAttribute("Phase") ~= "lost" do
		frames(1)
		t += 1
	end
	eq(gA:GetAttribute("Phase"), "held", "an absent gardener is held (" .. t .. " s after the last action)")
	local w0 = gA:GetAttribute("Wave")
	local aRoot = aChar:FindFirstChild("HumanoidRootPart")
	local home = aRoot.CFrame
	local everHeld = true
	for _, d in { 4.2, 6, 10, 4.2, 8 } do
		aRoot.CFrame = home + Vector3.new(0, 0, d)
		frames(1.5)
		if gA:GetAttribute("Phase") ~= "held" then everHeld = false end
		aRoot.CFrame = home
		frames(10)
		if gA:GetAttribute("Phase") ~= "held" then everHeld = false end
	end
	truthy(everHeld, "five shoves of 4.2-10 studs over a minute never end the AFK hold")
	eq((heres[victim] or 0) - victimHeres, 0, "and the victim's client, its player touching nothing all that while, sent no Here")
	eq(gA:GetAttribute("Wave"), w0, "and no wave came while they were away")
	-- their own input (their client's Here) brings them back
	local here = R:FindFirstChild("Here")
	truthy(here ~= nil, "the client has a Here remote for the gardener's own input")
	if here then
		fire(afk, "Here")
		frames(0.5)
		eq(gA:GetAttribute("Phase"), "build", "the gardener's own input (Here) brings the build timer back")
		-- a flood of Here is never echoed, and never costs a garden action's token
		local before = #toastsTo(afk)
		for _ = 1, 1000 do fire(afk, "Here") end
		frames(0.2)
		eq(#toastsTo(afk) - before, 0, "1000 Here pings are answered with nothing (no toast echo)")
		local seeds = gA:GetAttribute("Seeds")
		local free = nil
		local path = PathGen.fromText(Cfg, gA:GetAttribute("PathCells"))
		for id in PathGen.pads(Cfg, path) do
			if gA.Bed.Gnomes:FindFirstChild("Gnome_" .. id) == nil then free = id break end
		end
		fire(afk, "Plant", free, "pebble")
		frames(0.2)
		eq(gA:GetAttribute("Seeds"), seeds - 50, "and a garden action right after them is still served")
	end
end

--============================================================ the board's prompt cannot be made to echo
do
	local board = h.workspace.GardenBoards:FindFirstChild("GardenBoard_" .. G)
	local prompt = board:FindFirstChild("BoardPrompt", true)
	local function modes()
		local out = {}
		for _, rec in R.Board:sentTo(griefer) do
			local p = rec.args[1]
			if type(p) == "table" then table.insert(out, p.mode) end
		end
		return out
	end
	local function switches(list, from)
		local n, last = 0, list[from - 1]
		for i = from, #list do
			if list[i] ~= last then n += 1 end
			last = list[i]
		end
		return n
	end
	frames(1)
	-- a human: two taps a second apart are both answered
	local m0 = #modes()
	prompt.Triggered:Fire(griefer)
	frames(1)
	prompt.Triggered:Fire(griefer)
	frames(1)
	local list = modes()
	eq(switches(list, m0 + 1), 2, "two taps on the prompt a second apart are both answered (public -> friends -> public)")
	frames(2)
	local sent0 = #R.Board:sentTo(griefer)
	local toast0 = #toastsTo(griefer)
	for _ = 1, 2000 do prompt.Triggered:Fire(griefer) end
	frames(0.1)
	local burst = #R.Board:sentTo(griefer) - sent0
	print(string.format("  2000 prompt triggers in one instant -> %d Board payloads", burst))
	truthy(burst <= 2, "2000 triggers in one instant are answered at most once (" .. burst .. " payloads)")
	frames(30)
	local sent1, from = #R.Board:sentTo(griefer), #modes() + 1
	for _ = 1, 600 do
		for _ = 1, 50 do prompt.Triggered:Fire(griefer) end
		frames(0.1)
	end
	local stream = #R.Board:sentTo(griefer) - sent1
	local toggles = switches(modes(), from)
	print(string.format("  60 s of 500 triggers a second -> %d Board payloads, %d answered toggles, %d toasts", stream, toggles,
		#toastsTo(griefer) - toast0))
	truthy(toggles <= 61 * 2, "60 s of 500 triggers a second: at most two answered toggles a second (" .. toggles .. ")")
	truthy(stream <= 600, "and a bounded stream of payloads (" .. stream .. ", the reviewer measured 30061)")
	truthy(#toastsTo(griefer) - toast0 <= 62, "the refusals are said at most once a second (" .. (#toastsTo(griefer) - toast0) .. ")")
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(("gnome garden grief: %d passed, %d failed"):format(passed, failed))
