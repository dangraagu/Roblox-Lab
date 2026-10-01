-- The Same Door — the eye-candy glue, measured in the built world (bands, hazards, rest, budgets).
-- Run:  py -3 wrap.py --game ../same-door --out build/same-door.luau
--       luau check_samedoor_eyecandy.luau 2>&1
--
-- The pure rules have specs (Bands, DoorHazards, Pause, EnvBands, Rest). This file checks the CLIENT
-- GLUE that applies them, because a correct module wired wrongly is still a broken game:
--   1. BANDS follow the run: walking the day's perfect line, the band goes 1 -> 2 -> 3 -> 4 on the
--      seals and 5 at the Door, never by time; the light glides (>= 87.5 % of a change landed 2.4 s
--      later, and not all of it in the first frame); Lighting is written <= 10 times a second;
--   2. BUDGETS hold every frame of that walk: local parts <= 220, decor <= 30, critters <= 8,
--      weather emitters <= 2 at <= 60 particles/s, client lights <= 3 (+ the server torch = 4),
--      emitters <= 4; and nothing but a Seal is seal-gold, nothing but a ring is hazard-red;
--   3. HAZARDS through the real Cell/Run remotes: the ring shows only while its hazard warns, never
--      two at once, a root inside the ring at the impact is knocked (0.8 s), one outside it is not and
--      counts a near-miss;
--   4. REST: the campfire prompt rests you (sit + soften), any move wakes you, a rest in a run is
--      refused with a reason, leaving a run lands you resting at the fire, a rest sends no remote,
--      and the run clock keeps running while the pause sheet is open.

local Harness = require("./emu/harness")
local bundle = require("./build/same-door")

local h = Harness.new({ bundle = bundle, name = "same-door-eyecandy", viewport = { 1280, 720 }, touch = false })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(20261001 + unseeded * 7919)
		end
		return realRandom.new(seed)
	end,
}

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local HB = h.services.RunService.Heartbeat
local FRAME = 1 / 60
local function step(dt)
	h:advance(dt)
	HB:Fire(dt)
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local ws = h.workspace
local RS = h.services.ReplicatedStorage
local Lighting = h.services.Lighting
local R = RS.SameDoorRemotes
local Config = h:_require(RS.Config)
local Dungeon = h:_require(h.services.ServerScriptService.Dungeon)

local ME = 8101
local me = h:join("Glow", ME)
h:advance(0.5)
for _, key in { "client/Hud.client", "client/Dungeon.client", "client/Board.client" } do
	local ok, err = h:tryRun(key)
	truthy(ok, key .. " loads (" .. tostring(err) .. ")")
end
local char = h.Players:simulateSpawn(me, ws)
h:advance(0.2)
local hrp = char.HumanoidRootPart
local hum = char:FindFirstChildOfClass("Humanoid")
local hud = me.PlayerGui.SameDoorHud.Root
local localRoot = ws:FindFirstChild("SameDoorLocal")
truthy(localRoot ~= nil, "the client's local world folder exists")

local serverFired = 0
for _, n in { "Leave", "RunAgain", "GoHub" } do
	R[n].OnServerEvent:Connect(function() serverFired += 1 end)
end
local runMsgs = {}
R.Run.OnClientEvent:Connect(function(p) table.insert(runMsgs, p) end)

local function dist3(c, rgb)
	return math.sqrt((c.R * 255 - rgb[1]) ^ 2 + (c.G * 255 - rgb[2]) ^ 2 + (c.B * 255 - rgb[3]) ^ 2)
end

--============================================================ 4a. rest in the hub
local camp = ws.Hub.Campfire
local restPrompt = camp.Fire:FindFirstChild("RestPrompt")
truthy(restPrompt ~= nil, "the client made the campfire's Rest prompt")
eq(restPrompt and restPrompt.ActionText, "Rest by the fire", "…labelled Rest by the fire")
hrp.CFrame = CFrame.new(camp.Fire.Position.X + 4.5, 3, camp.Fire.Position.Z - 2)
step(FRAME)
truthy((hrp.Position - camp.Fire.Position).Magnitude <= restPrompt.MaxActivationDistance, "the Rest prompt is reachable beside the fire")
local firedBefore = serverFired
restPrompt.Triggered:Fire(me)
step(FRAME)
eq(hum.Sit, true, "resting sits you down")
eq(Lighting.SameDoorRest.Enabled, true, "…and softens the view")
for _ = 1, 120 do step(FRAME) end
eq(hum.Sit, true, "two seconds later you are still resting (nothing wakes you but you)")
hum.MoveDirection = Vector3.new(1, 0, 0)
for _ = 1, 30 do step(FRAME) end
eq(hum.Sit, false, "moving wakes you")
eq(Lighting.SameDoorRest.Enabled, false, "…and the view clears")
hum.MoveDirection = Vector3.new(0, 0, 0)
eq(serverFired, firedBefore, "resting sent the server nothing")

--============================================================ 3. hazards through the real remotes
-- A fake run pushed to THIS client exactly as the server pushes one: three hazard cells, one per slot.
local O = Vector3.new(0, 0, 1000)
R.Run:FireClient(me, { run = "hz", state = "ready", seals = 0, door = 2, origin = { x = O.X, y = O.Y, z = O.Z },
	perfectMs = 27340, silverMs = 46751, goldMs = 36362, sealerMs = 32261 })
R.Cell:FireClient(me, { run = "hz", cells = {
	{ x = 2, y = 2, sides = 15, kind = "hazard", slot = 1 },
	{ x = 6, y = 2, sides = 15, kind = "hazard", slot = 2 },
	{ x = 4, y = 6, sides = 15, kind = "hazard", slot = 3 },
} })
step(FRAME)
local runFolder = localRoot:FindFirstChild("Run")
local rings = {}
for _, d in runFolder:GetDescendants() do
	if d.Name == "Ring" then rings[d.Parent:GetAttribute("Slot")] = d end
end
eq(#rings, 3, "three hazard rings were built")
eq(rings[1] and rings[1].Size.Y, 8, "a ring is 8 studs across: exactly the 4-stud hit zone")
truthy(rings[1] and dist3(rings[1].Color, Config.Colours.HazardRed) < 1, "…and it is hazard-red")
-- cross the line: the client clock starts
hrp.CFrame = CFrame.new(O.X + 72, 3, O.Z - 1)
step(FRAME)
hrp.CFrame = CFrame.new(O.X + 72, 3, O.Z + 0.2)
step(FRAME)
local c0 = me:GetAttribute("SameDoorClock")
truthy(type(c0) == "number" and c0 >= 0 and c0 < 0.05, "crossing the line starts the client clock (" .. tostring(c0) .. ")")
-- park INSIDE ring 1 (cell 2,2 centre = 40, 40) and let slot 1 impact at 6 s
hrp.CFrame = CFrame.new(O.X + 40 + 2, 3, O.Z + 40)
local maxVisible, idleShown, warnSeen = 0, 0, false
local knockAt = nil
local t = c0
while t < 7.5 do
	step(FRAME)
	t = me:GetAttribute("SameDoorClock")
	local visible = 0
	for _, r in rings do if r.Transparency < 1 then visible += 1 end end
	maxVisible = math.max(maxVisible, visible)
	local hz = h:_require(RS.DoorHazards)
	local s1 = hz.stateAt(1, t, Config.Hazards)
	if s1 == "warn" then warnSeen = true end
	if s1 == "idle" and rings[1].Transparency < 1 then idleShown += 1 end
	if knockAt == nil and hum.PlatformStand == true then knockAt = t end
end
truthy(warnSeen, "slot 1 warned before its impact")
eq(idleShown, 0, "the ring is hidden whenever its hazard is idle")
eq(maxVisible, 1, "never more than one ring shows at a time")
truthy(knockAt ~= nil and math.abs(knockAt - 6) < 0.05, string.format("standing in the ring at 6 s knocks you down (at %s s)", tostring(knockAt)))
eq(me:GetAttribute("SameDoorKnocks"), 1, "one knock counted")
truthy(hum.PlatformStand == false, "the knock is over 0.8 s later (a second lost, never the run)")
-- now stand OUTSIDE ring 1 (4.5 studs from the centre) for slot 1's next impact at 18 s
hrp.CFrame = CFrame.new(O.X + 40 + 4.5, 3, O.Z + 40)
local near0 = me:GetAttribute("SameDoorNear") or 0
while t < 18.3 do
	step(FRAME)
	t = me:GetAttribute("SameDoorClock")
end
eq(me:GetAttribute("SameDoorKnocks"), 1, "4.5 studs from the centre (outside the ring) is not hit")
truthy((me:GetAttribute("SameDoorNear") or 0) > near0, "…and counts as a near-miss")
R.Run:FireClient(me, { state = "hub" })
step(FRAME)
eq(localRoot:FindFirstChild("Run"), nil, "leaving the fake run clears its local world")

-- 3b. a knock never outlives its run (REVIEW-1, reviewer 2 finding 1): knocked at a ring, the player
-- taps pause and Leave inside the 0.8 s; the run ends (or voids, or finishes) and the character must
-- stand up, not stay PlatformStand at the fire and in every later run
for k, endState in { "ended", "void", "finished", "hub" } do
	local id = "knock" .. k
	R.Run:FireClient(me, { run = id, state = "ready", seals = 0, door = 2, origin = { x = O.X, y = O.Y, z = O.Z },
		perfectMs = 27340, silverMs = 46751, goldMs = 36362, sealerMs = 32261 })
	R.Cell:FireClient(me, { run = id, cells = { { x = 2, y = 2, sides = 15, kind = "hazard", slot = 1 } } })
	step(FRAME)
	hrp.CFrame = CFrame.new(O.X + 72, 3, O.Z - 1)
	step(FRAME)
	hrp.CFrame = CFrame.new(O.X + 72, 3, O.Z + 0.2)
	step(FRAME)
	hrp.CFrame = CFrame.new(O.X + 40 + 2, 3, O.Z + 40)
	local knocked = false
	for _ = 1, 60 * 8 do
		step(FRAME)
		if hum.PlatformStand == true then knocked = true; break end
	end
	truthy(knocked, string.format("(%s) standing in the ring knocks the player down", endState))
	for _ = 1, 18 do step(FRAME) end -- 0.3 s into the 0.8 s knock
	local payload = { run = id, state = endState, why = "leave", reason = "test" }
	if endState == "finished" then payload.timeMs = 30000; payload.medal = "Gold"; payload.seals = 3 end
	if endState == "hub" then payload.run = nil end
	R.Run:FireClient(me, payload)
	step(FRAME)
	eq(hum.PlatformStand, false, string.format("a run that becomes %q mid-knock stands the player back up at once", endState))
	R.Run:FireClient(me, { state = "hub" })
	step(FRAME)
end

--============================================================ 1 + 2. the real walk: bands, glide, budgets
local archPrompt = ws.Hub.Arch.Doorway.EnterPrompt
hrp.CFrame = CFrame.new(0, 3, 12)
step(FRAME)
archPrompt.Triggered:Fire(me)
h:advance(0.05)
local ready = runMsgs[#runMsgs]
eq(ready.state, "ready", "the arch starts a real run")
local origin = Vector3.new(ready.origin.x, ready.origin.y, ready.origin.z)
local rec = h.game:GetService("HttpService"):JSONDecode(h.game:GetService("ServerStorage").SameDoor.Day.Value)
local world = Dungeon.fromRecord(Config, rec)
local _, path = Dungeon.perfectPath(Config, world)

-- 4b. a rest in a run is refused, with a reason
restPrompt.Triggered:Fire(me)
step(FRAME)
eq(hum.Sit, false, "resting inside a run is refused")
truthy(string.find(hud.Toast.Text.Text, "between runs", 1, true) ~= nil, "…and the toast says why (" .. hud.Toast.Text.Text .. ")")

local writesStart = me:GetAttribute("SameDoorLightingWrites") or 0
local tStart = 0
local bandSeq = {}
local maxParts, maxDecor, maxCrit, maxWeather, maxRate, maxLights, maxEmit = 0, 0, 0, 0, 0, 0, 0
local colourBad, goldNotSeal, redNotRing = 0, 0, 0
local glides = {}
local pending = nil
local critNear = {} -- band -> the closest any of its critters came to the player
local function sample(tNow)
	local band = me:GetAttribute("SameDoorBand") or 0
	if bandSeq[#bandSeq] ~= band then
		table.insert(bandSeq, band)
		local b = Config.Env.Bands[band]
		if b and #bandSeq > 1 then
			pending = { at = tNow, band = band, from = Lighting.Ambient, target = b.lighting.Ambient, firstFrame = nil }
		end
	end
	if pending then
		local amb = Lighting.Ambient
		local function frac()
			local total = math.abs(pending.target[1] - pending.from.R * 255) + math.abs(pending.target[2] - pending.from.G * 255)
				+ math.abs(pending.target[3] - pending.from.B * 255)
			local left = math.abs(pending.target[1] - amb.R * 255) + math.abs(pending.target[2] - amb.G * 255) + math.abs(pending.target[3] - amb.B * 255)
			if total < 1e-6 then return 1 end
			return 1 - left / total
		end
		if pending.firstFrame == nil and tNow - pending.at >= 0.15 then pending.firstFrame = frac() end
		if tNow - pending.at >= 2.4 then
			table.insert(glides, { band = pending.band, early = pending.firstFrame, at24 = frac() })
			pending = nil
		end
	end
	local parts, decor, crit, lights, emit, weatherOn, rate = 0, 0, 0, 0, 0, 0, 0
	local nearestCrit = math.huge
	for _, d in localRoot:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Critter" then
			nearestCrit = math.min(nearestCrit, (d.Position - hrp.Position).Magnitude)
		end
	end
	if nearestCrit < math.huge then
		critNear[band] = math.min(critNear[band] or math.huge, nearestCrit)
	end
	for _, d in localRoot:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d.Name == "Decor" then decor += 1 end
			if d.Name == "Critter" then crit += 1 end
			if d.Name == "Decor" or d.Name == "Critter" then
				if dist3(d.Color, Config.Colours.SealGold) < Config.Colours.MinColourDistance
					or dist3(d.Color, Config.Colours.HazardRed) < Config.Colours.MinColourDistance then
					colourBad += 1
				end
			end
			if dist3(d.Color, Config.Colours.SealGold) < 1 and (d.Parent == nil or d.Parent.Name ~= "Seal") then goldNotSeal += 1 end
			if dist3(d.Color, Config.Colours.HazardRed) < 1 and d.Name ~= "Ring" then redNotRing += 1 end
		elseif d.ClassName == "PointLight" and d.Enabled ~= false then
			lights += 1
		elseif d.ClassName == "ParticleEmitter" and d.Enabled ~= false then
			emit += 1
			if d.Name == "Weather" then
				weatherOn += 1
				rate += d.Rate
			end
		end
	end
	maxParts = math.max(maxParts, parts)
	maxDecor = math.max(maxDecor, decor)
	maxCrit = math.max(maxCrit, crit)
	maxLights = math.max(maxLights, lights)
	maxEmit = math.max(maxEmit, emit)
	maxWeather = math.max(maxWeather, weatherOn)
	maxRate = math.max(maxRate, rate)
end

local pts = { { x = 72, z = -8 } }
for _, p in path do table.insert(pts, p) end
local seg, x, z, tWalk = 1, 72, -8, 0
local finished = false
while not finished and tWalk < 120 do
	if seg < #pts then
		local remaining = 16 * FRAME
		while remaining > 0 and seg < #pts do
			local b = pts[seg + 1]
			local dx, dz = b.x - x, b.z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
		end
		hrp.CFrame = CFrame.new(origin.X + x, origin.Y + 3, origin.Z + z)
	end
	step(FRAME)
	tWalk += FRAME
	sample(tWalk)
	for i = #runMsgs, math.max(1, #runMsgs - 3), -1 do
		if runMsgs[i].state == "finished" then finished = true end
	end
end
truthy(finished, "the walk reaches the Door")
-- let the Dawn Sanctum glide land
for _ = 1, 180 do
	step(FRAME)
	tWalk += FRAME
	sample(tWalk)
end
local writes = (me:GetAttribute("SameDoorLightingWrites") or 0) - writesStart
local rate = writes / (tWalk - tStart)
print(string.format("  Lighting writes: %d over %.1f s = %.2f per second", writes, tWalk - tStart, rate))
truthy(rate <= Config.Env.LightingHz + 0.5, string.format("Lighting written %.2f times a second (<= %d)", rate, Config.Env.LightingHz))

local seqText = table.concat(bandSeq, " -> ")
print("  bands seen: " .. seqText)
-- 0 is the hub look (not a band): entering the antechamber glides into the Cold Cellar
eq(seqText, "0 -> 1 -> 2 -> 3 -> 4 -> 5", "hub -> Cold Cellar on entering, then Moss -> Crystal -> Ember on the seals, Dawn at the Door")
for _, g in glides do
	print(string.format("  band %d glide: %.0f %% after 0.15 s, %.1f %% after 2.4 s", g.band, (g.early or 0) * 100, g.at24 * 100))
	truthy(g.at24 >= 0.875 - 0.01, string.format("band %d: >= 87.5 %% of the light change landed 2.4 s later (%.1f %%)", g.band, g.at24 * 100))
	truthy((g.early or 1) < 0.5, string.format("band %d: it GLIDES, not a cut (%.0f %% after 0.15 s)", g.band, (g.early or 1) * 100))
end
eq(#glides, 5, "five changes were measured (entering, three seals, the Door)")

-- every band shows ITS critters around the player (standard §2), the Dawn Sanctum's too: the first
-- build homed them on the entrance cell whenever the player stood outside the grid, so the five
-- birds of the brag-moment backdrop circled 150 studs away inside the closed grid (reviewer 2, 3)
for b = 1, #Config.Env.Bands do
	truthy((critNear[b] or math.huge) <= 16, string.format("band %d's critters came within 16 studs of the player (closest %.1f)", b,
		critNear[b] or math.huge))
end
do
	local n, far, kind = 0, 0, nil
	for _, d in localRoot:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Critter" then
			n += 1
			far = math.max(far, (d.Position - hrp.Position).Magnitude)
			kind = d:GetAttribute("Kind")
		end
	end
	print(string.format("  in the Dawn Sanctum: %d critters (%s), the farthest %.1f studs from the player", n, tostring(kind), far))
	eq(n, Config.Env.Bands[5].critter.count, "the Dawn Sanctum shows its 5 birds")
	truthy(n > 0 and far <= 12, string.format("…all within 12 studs of the player (farthest %.1f)", far))
end

print(string.format("  budgets over the walk: parts %d, decor %d, critters %d, weather emitters %d at %.1f/s, client lights %d, emitters %d",
	maxParts, maxDecor, maxCrit, maxWeather, maxRate, maxLights, maxEmit))
truthy(maxParts <= Config.Budget.MaxLocalParts, "local parts stayed <= 220 (" .. maxParts .. ")")
truthy(maxDecor <= Config.Budget.MaxDecor and maxDecor > 0, "decor stayed <= 30 and there was some (" .. maxDecor .. ")")
truthy(maxCrit <= Config.Budget.MaxCritters and maxCrit > 0, "critters stayed <= 8 and there were some (" .. maxCrit .. ")")
truthy(maxWeather <= Config.Budget.MaxWeatherEmitters and maxWeather > 0, "weather emitters stayed <= 2 (" .. maxWeather .. ")")
truthy(maxRate <= Config.Budget.MaxEmitterRate + 1e-6, string.format("weather stayed <= 60 particles/s (%.1f)", maxRate))
truthy(maxLights <= Config.Budget.MaxLights - 1, "client lights stayed <= 3 (+ the server torch = 4) (" .. maxLights .. ")")
truthy(maxEmit <= Config.Budget.MaxEmitters, "emitters stayed <= 4 (" .. maxEmit .. ")")
eq(colourBad, 0, "no decor or critter was near seal-gold or hazard-red")
eq(goldNotSeal, 0, "nothing but a Seal was seal-gold")
eq(redNotRing, 0, "nothing but a hazard ring was hazard-red")

--============================================================ 4c. the clock never stops; leaving lands you resting
h:advance(1.2)
R.RunAgain:simulateFireServer(me)
h:advance(0.1)
hrp.CFrame = CFrame.new(origin.X + 72, 3, origin.Z - 1)
step(FRAME)
hrp.CFrame = CFrame.new(origin.X + 72, 3, origin.Z + 0.5)
step(FRAME)
eq(hud.PauseBox.Visible, true, "in a run the pause button shows")
eq(hud.RestPanel.Visible, false, "…and the Rest button does not")
hud.PauseBox.PauseButton.Activated:Fire()
step(FRAME)
eq(hud.PauseSheet.Visible, true, "the pause button opens the sheet")
local cA = me:GetAttribute("SameDoorClock")
for _ = 1, 60 do step(FRAME) end
local cB = me:GetAttribute("SameDoorClock")
print(string.format("  display clock under the open pause sheet: +%.3f s in 1.000 s", cB - cA))
truthy(cB - cA > 0.95, string.format("the run clock keeps running under the pause sheet (%.2f s in 1 s)", cB - cA))
hud.PauseSheet.Buttons.LeaveButton.Activated:Fire()
h:advance(0.1)
for _ = 1, 20 do step(FRAME) end
local ended = nil
for _, m in runMsgs do if m.state == "ended" then ended = m end end
eq(ended and ended.why, "leave", "Leave run ends the run")
truthy((hrp.Position - camp.Fire.Position).Magnitude < 10, "…and brings you to the campfire")
eq(hum.Sit, true, "…where you arrive resting")

local errs = h:errors()
eq(#errs, 0, "no scheduler errors")
for _, e in errs do print("  scheduler: " .. e) end
print(string.format("check_samedoor_eyecandy: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_samedoor_eyecandy failed", 0) end
