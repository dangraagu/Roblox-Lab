-- Outpost Zero — THE PLAYER'S PATH, walked in the built world, printed in numbers.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       cd ../outpost-zero && luau tests/walk.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green tests are not a working game (this repo once shipped 166 green tests with an unreachable core loop). This
-- file is somebody playing, on a phone-sized touch screen, through what the HUD shows: it lands on its pad, reads
-- the hint, finds the ★ (the HUD's own ★ marker over a lot's sign post), walks there at 85% of WalkSpeed after a 1 s
-- look (the model's `normal` profile), and presses the post's prompt only from within its reach and only when the
-- HUD's ★ line says "ready now" (after a moment to notice). When a hazard's warning says MOVE it steps out of the
-- red ring three times in four (a normal player's 25% hit share). It plays
--   loop 1: join -> the first Home and Workshop -> citizens and credits -> the next builds -> Market Row,
-- and on, district by district, to the Skyport and the Grand Airship docking (the brag moment); then it leaves,
-- comes back 5 minutes later (offline earnings) with a fresh HUD, and plays
--   loop 2: the saved city, the next builds on it, the Orders renewed.
-- Every step prints what happened, in numbers. It asserts only what a player would notice was broken.

local Harness = require("../../robloxemu/emu/harness")
local h = Harness.new({ bundle = require("../../robloxemu/build/outpost-zero"), name = "outpost-zero-walk",
	viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("CityRemotes")
local State, FxR, Toast, Announce = remotes.State, remotes.Fx, remotes.Toast, remotes.Announce
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
local UID = 27182
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local rng = Random.new(20261007)

local plr, hrp, hum, shelf, t0
local function join(first)
	RunService:setIsServer(false)
	plr = h:join("Walker", UID)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hrp.Size = Vector3.new(2, 2, 1)
	hum.HipHeight = 2
	hum.FloorMaterial = Enum.Material.Rock
	hum.MoveDirection = Vector3.new(0, 0, 0)
	shelf = plr.RespawnLocation.Parent
	-- every join runs the HUD again, as a new Roblox client does (Sky.client once: it builds client-only sky parts)
	assert(h:tryRun("client/Hud.client"))
	if first then assert(h:tryRun("client/Sky.client")) end
	t0 = h.scheduler:now()
end
local function now() return h.scheduler:now() - t0 end
local function st()
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local function gui(path)
	local node = plr.PlayerGui
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
local function hint()
	local p = gui("OutpostHud.Root.HintPanel")
	return if p and p.Visible then p.HintText.Text else "(none)"
end
local function starLine()
	local t = gui("OutpostHud.Root.StarPanel.StarText")
	return t and t.Text or ""
end
local function starPost()
	local m = gui("HudLocal.StarMarker")
	return if m and m.Enabled then m.Adornee else nil
end
local function chip()
	local c = gui("OutpostSky.Root.BandChip.ChipText")
	return c and c.Text or "?"
end
local function flat(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) end
local function standBy(post)
	local centre = shelf.Rock.Position
	local dir = Vector3.new(centre.X - post.Position.X, 0, centre.Z - post.Position.Z).Unit
	return Vector3.new(post.Position.X + dir.X * 2, hrp.Position.Y, post.Position.Z + dir.Z * 2)
end

-- what the walker saw
local counts = { buys = 0, refusals = 0, hazards = 0, hits = 0, dodges = 0, toasts = 0 }
local toastLog = {}
Toast.OnClientEvent:Connect(function(text)
	counts.toasts += 1
	if #toastLog < 40 then table.insert(toastLog, string.format("%.1fs %s", now(), tostring(text))) end
	if string.find(tostring(text), "Need", 1, true) then counts.refusals += 1 end
end)
local docked, flights = nil, 0
FxR.OnClientEvent:Connect(function(ev)
	if type(ev) == "table" and ev.kind == "moored" then docked = docked or now() end
end)
Announce.OnClientEvent:Connect(function(ev)
	if type(ev) == "table" and ev.kind == "airship" then flights += 1 end
end)

-- the normal player, 0.1 s at a time
local P = { react = 1.0, eff = 0.85, notice = 3.0, buy = 1.0, hit = 0.25 }
local mode, wakeAt, targetPost = "look", 0, nil
local waited = false
local firstBuildAt, buysAt60 = nil, nil
local bandAt, lastChipBand = {}, nil
local lapses, wasWorking = 0, true
local stillSince, longestStill = 0, 0
local dodgeUntil, dodgeDir, dodgeDecided = 0, nil, false
local hintsSeen = {}
local sideClash = 0
local popAt = {}
local function step(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 18), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local s = st()
	if s == nil or not s.loaded then return end
	local hnt = hint()
	if hnt ~= "(none)" and hintsSeen[hnt] == nil then hintsSeen[hnt] = now() end
	-- the balance line and the ★ line never disagree about which side to build (a player would notice)
	local bal = gui("OutpostHud.Root.BalancePanel.BalanceText")
	local line = starLine()
	if bal then
		if string.find(bal.Text, "build a Workshop", 1, true) and string.sub(line, 1, #"★ Home") == "★ Home" then sideClash += 1 end
		if string.find(bal.Text, "build a Home", 1, true) and string.sub(line, 1, #"★ Workshop") == "★ Workshop" then sideClash += 1 end
	end
	-- band entries, as the chip names them
	local band = string.match(chip(), "^%S+ ([%a ]-) ·")
	if band and band ~= lastChipBand then
		lastChipBand = band
		if bandAt[band] == nil then bandAt[band] = now() end
	end
	-- an Orders lapse while playing (the workers idle with no ★ affordable soon) is a pacing failure
	local working = s.working or s.complete
	if wasWorking and not working and s.population > 0 then lapses += 1 end
	wasWorking = working
	-- hazards: step out of the red ring three times in four
	local warn = gui("OutpostSky.Root.WarningPanel")
	if warn and warn.Visible and string.find(warn.WarningText.Text, "MOVE", 1, true) then
		if not dodgeDecided then
			dodgeDecided = true
			counts.hazards += 1
			if rng:NextNumber() >= P.hit then
				local a = rng:NextNumber() * math.pi * 2
				dodgeDir = Vector3.new(math.cos(a), 0, math.sin(a))
				dodgeUntil = now() + 0.6
			end
		end
	elseif not (warn and warn.Visible) then
		dodgeDecided = false
	end
	if hum.PlatformStand then
		if counts.lastHit == nil or now() - counts.lastHit > 2 then
			counts.hits += 1
			counts.lastHit = now()
		end
	end
	local moving = false
	if now() < dodgeUntil and dodgeDir then
		local p = hrp.Position
		hrp.CFrame = CFrame.new(p + dodgeDir * 16 * dt)
		moving = true
		if now() + dt >= dodgeUntil then
			counts.dodges += 1
			mode = "evade" -- stay out of the ring until it clears, then walk back to the post
		end
	elseif mode == "evade" then
		local w = gui("OutpostSky.Root.WarningPanel")
		local ring = h.workspace:FindFirstChild("OutpostLocalSky") and h.workspace.OutpostLocalSky:FindFirstChild("HazardZone")
		if not (w and w.Visible) and ring == nil then mode = "walk" end
	elseif not hum.PlatformStand then
		local post = starPost()
		if post ~= targetPost then
			targetPost = post
			mode, wakeAt = "look", now() + P.react
		end
		if post and mode == "look" and now() >= wakeAt then mode = "walk" end
		if post and mode == "walk" then
			local stand = standBy(post)
			local d = flat(hrp.Position, stand)
			if d > 0.3 then
				local stepLen = math.min(d, 16 * P.eff * dt)
				local p = hrp.Position
				hrp.CFrame = CFrame.new(p.X + (stand.X - p.X) / d * stepLen, p.Y, p.Z + (stand.Z - p.Z) / d * stepLen)
				moving = true
			else
				-- arrived: affordable already, press (the model's `buy`); otherwise wait, then notice it is ready
				mode = "wait"
				waited = not string.find(starLine(), "ready now", 1, true)
			end
		end
		if post and mode == "wait" then
			if string.find(starLine(), "ready now", 1, true) then
				mode, wakeAt = "press", now() + (if waited then P.notice * rng:NextNumber() else 0) + P.buy
			end
		end
		if post and mode == "press" and now() >= wakeAt then
			local prompt = post:FindFirstChild("BuildPrompt")
			local reach = (hrp.Position - post.Position).Magnitude
			truthy(reach <= prompt.MaxActivationDistance, string.format("the ★ post is in reach when pressed (%.1f studs)", reach))
			local s0 = s.settlers + s.jobs
			prompt.Triggered:Fire(plr)
			h:advance(0.05)
			local s1 = st()
			if s1.settlers + s1.jobs > s0 then
				counts.buys += 1
				firstBuildAt = firstBuildAt or now()
			end
			mode, wakeAt = "look", now() + P.react
		end
	end
	hum.MoveDirection = if moving then Vector3.new(0, 0, 1) else Vector3.new(0, 0, 0)
	if moving then
		stillSince = now()
	else
		longestStill = math.max(longestStill, now() - stillSince)
	end
	if buysAt60 == nil and now() >= 60 then buysAt60 = counts.buys end
	for _, m in { 1, 5, 10, 20, 30 } do
		if popAt[m] == nil and now() >= m * 60 then popAt[m] = s.population end
	end
end

--============================================================================ loop 1: from the join to the brag
join(true)
local landed = flat(hrp.Position, plr.RespawnLocation.Position)
for _ = 1, 3 do step(0.1) end
print("== loop 1: join")
local s0 = st()
print(string.format("  landed %.2f studs from its own pad; %s credits; hint: %s", landed, tostring(s0 and s0.credits), hint()))
truthy(landed <= 4, "the walker lands on its own pad")
truthy(s0 and s0.loaded and s0.star ~= nil, "the city loads with a ★ to walk to")
truthy(hint() == "Walk to the ★ lot and tap BUILD", "the first hint names the core action: " .. hint())
truthy(starPost() ~= nil, "the HUD puts the ★ over a lot's sign post")

local LIMIT = 50 * 60
while now() < LIMIT and docked == nil do
	step(0.1)
end
local s1 = st()
print(string.format("  first build %.1f s after the join; %d purchases in the first minute", firstBuildAt or -1, buysAt60 or -1))
print(string.format("  population after 1 / 5 / 10 / 20 / 30 min: %s / %s / %s / %s / %s",
	tostring(popAt[1]), tostring(popAt[5]), tostring(popAt[10]), tostring(popAt[20]), tostring(popAt[30])))
local order = { "Clear Morning", "Trade Winds", "Lantern Dusk" }
local parts = {}
for _, b in order do table.insert(parts, string.format("%s %.1f min", b, (bandAt[b] or -60) / 60)) end
print("  bands entered: " .. table.concat(parts, ", "))
print(string.format("  the Grand Airship docked at %.1f min (%d flight%s announced); population %d, %d purchases",
	(docked or -60) / 60, flights, if flights == 1 then "" else "s", s1.population, counts.buys))
print(string.format("  hazards: %d locked on, %d stepped out of, %d hits; refusals heard: %d; longest stand still %.0f s; Orders lapses %d",
	counts.hazards, counts.dodges, counts.hits, counts.refusals, longestStill, lapses))
local hs = {}
for text, at in hintsSeen do table.insert(hs, { at = at, text = text }) end
table.sort(hs, function(a, b) return a.at < b.at end)
for _, x in hs do print(string.format("  hint at %.1f s: %s", x.at, x.text)) end
truthy(firstBuildAt ~= nil and firstBuildAt <= 6, string.format("the first build comes within about 5 s (%.1f s)", firstBuildAt or -1))
truthy((buysAt60 or 0) >= 5, string.format("the first minute is busy: %d purchases", buysAt60 or 0))
truthy(docked ~= nil, "the walker reaches the Skyport and the Grand Airship docks")
truthy(docked and docked / 60 >= 30 and docked / 60 <= 45, string.format("the brag comes at %.1f min, inside 30-45", (docked or -60) / 60))
truthy(shelf:FindFirstChild("Airship") ~= nil, "the airship is moored over the walker's Town Hall")
truthy(lapses == 0, "the workers never ran out of Orders while the walker played (" .. lapses .. ")")
truthy(sideClash == 0, "the HUD's balance line and its ★ line never named different sides (" .. sideClash .. " frames)")
truthy(counts.hazards >= 5, "hazards came while the walker played (" .. counts.hazards .. ")")

--============================================================================ leave, 5 minutes away, rejoin
local before = st()
local wantPop = before.population
local credits0 = before.credits
h:leave(plr)
h:advance(1)
local rec = store:GetAsync("u_" .. UID)
truthy(rec and rec.lockUntil == 0, "leaving saves the city and releases the lock")
rec.data.savedAt -= 300
rec.data.ordersUntil -= 300
store:SetAsync("u_" .. UID, rec)
join(false)
-- a new client: the walker's own timers start again with the new clock
mode, wakeAt, targetPost, dodgeUntil, dodgeDecided, stillSince = "look", 0, nil, 0, false, 0
for _ = 1, 20 do step(0.1) end
local back = st()
local offlineToast = nil
for _, line in toastLog do
	if string.find(line, "while you were away", 1, true) then offlineToast = line end
end
print("== the rejoin, 5 minutes later")
print(string.format("  population %d (was %d); credits %.0f (left with %.0f); %s", back.population, wantPop, back.credits, credits0, tostring(offlineToast)))
truthy(back.population == wantPop, "the rejoin restores the city")
truthy(offlineToast ~= nil, "and says what the workers earned while away")
truthy(shelf:FindFirstChild("Airship") ~= nil, "the airship is moored from the start (no second flight)")

--============================================================================ loop 2: the saved city, the next builds
local buys0 = counts.buys
local loop2Start = now()
while now() - loop2Start < 180 do step(0.1) end
local s2 = st()
print("== loop 2: three more minutes")
print(string.format("  %d purchases; population %d -> %d; Orders %s left", counts.buys - buys0, wantPop, s2.population,
	tostring(math.floor(s2.ordersLeft or 0)) .. " s"))
truthy(counts.buys - buys0 >= 3, "the saved city keeps growing in the second loop")
truthy(s2.population > wantPop, "the population rises again")
truthy((s2.ordersLeft or 0) > 300, "the Orders are renewed by the new builds")

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
truthy(#stray == 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
