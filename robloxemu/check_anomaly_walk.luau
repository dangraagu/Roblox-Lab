-- anomaly-observatory — the whole player path in ONE run: join -> spawn -> walk the hall -> answer -> earn
-- -> spend -> a wrong call -> leave -> rejoin, through the real server and the real HUD.
-- Run: luau check_anomaly_walk.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- docs/complete-game-standard.md §1: "The core loop is reachable from join. Walk the real player path
-- headless: spawn, first objective, one full loop, earn, spend, rejoin. Green unit tests are not a working
-- game." Every other check here starts from one step of the loop (the rejoin check restores a Day and a hall,
-- the board check seeds stores, the spawn check stops at the pad). Nothing walked it end to end, and nothing
-- proved that Best Day, the Field Guide, the hints, the redeemed codes and the tint survive a leave and a
-- rejoin (review 2026-09-30, the standard's §1 gap). This does, and everything a player sees is read off the
-- HUD the player sees, not off the server's tables.
--
-- In this game "earn" is a Day, a Field Guide entry (TURN BACK on an anomaly) and hints (a code); "spend" is
-- a hint (H at the start pad) and a tint (a code-unlocked flashlight colour). "Walking" moves the character's
-- root along the hall in 4-stud steps (robloxemu has no physics): every step is over the hall's own floor and
-- inside its walls, and a prompt is only pressed from inside its MaxActivationDistance.
--
-- Also here (standard §1, "no silent no-ops: a refused player action says why"), each written before its fix
-- and watched failing on the old build:
--   * a second code sent before the first one's cooldown ended was dropped without a word (the HUD had
--     already cleared the box): it must answer;
--   * a code longer than 64 characters was dropped without a word: it must answer "unknown";
--   * a second tint picked within the 0.5 s cooldown was dropped without a word: the last pick must win;
--   * pressing H twice on the same hall charged two hints for one answer: the second press re-shows the
--     answer the player already paid for, free.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
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

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Remotes = RS:FindFirstChild("AnomalyRemotes")
local StateR, RevealR = Remotes:FindFirstChild("State"), Remotes:FindFirstChild("Reveal")
local DSS = h.game:GetService("DataStoreService")
local store = DSS:GetDataStore(Config.Save.Store)
local guideStore = DSS:GetOrderedDataStore(Config.Save.GuideStore)
local RunService = h.game:GetService("RunService")
local TOTAL = #Config.Anomaly.Catalog
local UID = 5150
local KEY = "u_" .. UID

local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function zoneOf(plr) return h.workspace:FindFirstChild("Concourse_" .. plr.UserId) end
local function infoOf(plr) return h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId)) end
local function originOf(plr): Vector3
	return Vector3.new((tonumber(zoneOf(plr):GetAttribute("Index")) or 0) * 1000, 100, 0)
end
local function rootOf(plr) return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") end

-- The HUD, as the player reads it: the first TextLabel under AnomalyHud whose text starts with `prefix`
-- (labels only: the phone toggle is a button that copies the Day label's text).
local function hudText(plr, prefix: string): string?
	local hud = nil
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "AnomalyHud" then hud = g end
	end
	if hud == nil then return nil end
	for _, d in hud:GetDescendants() do
		if d:IsA("TextLabel") and string.sub(d.Text, 1, #prefix) == prefix then
			return d.Text
		end
	end
	return nil
end
-- "Best: Day N", with or without the brag emoji of the sky band N has reached (owner decision D3)
local function bestIs(plr, n: number): boolean
	local t = hudText(plr, "Best:")
	local want = "Best: Day " .. n
	return t ~= nil and (t == want or string.sub(t, 1, #want + 1) == want .. " ")
end
local function reveals(plr): { any }
	local out = {}
	for _, s in RevealR:sentTo(plr) do table.insert(out, s.args[1]) end
	return out
end
local function lastReveal(plr): any
	local r = reveals(plr)
	return r[#r]
end
local function lastState(plr): any
	local s = StateR:sentTo(plr)
	return s[#s] and s[#s].args[1]
end

-- Roblox queues a RemoteEvent fired before the client connected and delivers it on connect; the emulator
-- records it instead. Replaying the last recorded State is that delivery (check_anomaly.luau does the same).
local function deliverQueuedState(plr)
	local s = lastState(plr)
	if s then StateR:FireClient(plr, s) end
end

-- The Head the emulator does not build (check_anomaly_spawn.luau's note): the flashlight hangs on it.
local function attachHead(char)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Parent = char
end

local function joinAndSpawn(name: string)
	RunService:setIsServer(false)
	local plr = h:join(name, UID)
	h:advance(0.2)
	assert(h:tryRun("client/Hud.client"))
	plr.CharacterAdded:Connect(attachHead)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
	deliverQueuedState(plr)
	h:advance(0.1)
	return plr
end

-- Walk the root from where it stands to `to` (hall-local), 4 studs a step, every step over the floor.
local offFloor = {}
local function walkTo(plr, to: Vector3)
	local hrp = rootOf(plr)
	local o = originOf(plr)
	local floor = zoneOf(plr):FindFirstChild("Floor")
	local from = hrp.Position
	local dest = o + to
	local steps = math.max(1, math.ceil((dest - from).Magnitude / 4))
	for i = 1, steps do
		local p = from:Lerp(dest, i / steps)
		local rel = floor.CFrame:PointToObjectSpace(p)
		local half = floor.Size / 2
		if math.abs(rel.X) > half.X - 0.5 or math.abs(rel.Z) > half.Z or rel.Y < half.Y then
			table.insert(offFloor, string.format("(%.1f, %.1f, %.1f)", p.X - o.X, p.Y - o.Y, p.Z - o.Z))
		end
		hrp.CFrame = CFrame.new(p)
		h:advance(0.25)
	end
end

local function promptOn(plr, partName: string): any
	local part = zoneOf(plr):FindFirstChild(partName)
	return part and part:FindFirstChildOfClass("ProximityPrompt"), part
end
local function inReach(plr, partName: string): (boolean, number)
	local prompt, part = promptOn(plr, partName)
	local d = (rootOf(plr).Position - part.Position).Magnitude
	return d <= prompt.MaxActivationDistance, d
end
local function press(plr, partName: string)
	local prompt = promptOn(plr, partName)
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	local ok, err = coroutine.resume(co)
	assert(ok, "prompt handler errored: " .. tostring(err))
end

-- One pass the way a player plays it: walk to the far end, read the hall (PassInfo stands for the reading),
-- press E or Q. `right` = answer it correctly.
local passes, outOfReach = 0, {} -- every pass's pad was pressed from inside its prompt's reach (asserted at the end)
local caught: { [string]: boolean } = {} -- the anomaly types this player has spotted, as the test saw them
local function caughtCount(): number
	local n = 0
	for _ in caught do n += 1 end
	return n
end
local function playPass(plr, right: boolean)
	walkTo(plr, Vector3.new(0, 3.5, -78))
	local clean = infoOf(plr):GetAttribute("Clean") == true
	if right and not clean then caught[infoOf(plr):GetAttribute("AnomalyId")] = true end
	local pad = if clean == right then "AdvancePad" else "BackPad"
	local ok, d = inReach(plr, pad)
	passes += 1
	if not ok then table.insert(outOfReach, string.format("%s at %.1f studs", pad, d)) end
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	press(plr, pad)
	h:advance(0.2)
end

--============================================================ 1. a brand-new player joins and spawns
eq(store:GetAsync(KEY), nil, "a brand-new player: nothing saved")
local plr = joinAndSpawn("Walker")
local o = originOf(plr)
local pad = zoneOf(plr):FindFirstChild("StartPad")
local hrp = rootOf(plr)
truthy(hrp ~= nil and pad ~= nil and math.abs(hrp.Position.X - pad.Position.X) < 3 and math.abs(hrp.Position.Z - pad.Position.Z) < 3
	and hrp.Position.Y > pad.Position.Y, "the new player stands on their own start pad")
eq(hudText(plr, "DAY"), "DAY 1", "the HUD says DAY 1")
eq(hudText(plr, "Best:"), "Best: Day 0", "and Best: Day 0")
eq(hudText(plr, "Field Guide:"), string.format("Field Guide: 0/%d", TOTAL), "and an empty Field Guide")
eq(hudText(plr, "Hints:"), string.format("Hints: %d  (H at start pad)", Config.Hint.StartTokens), "and the starting hints")
eq(plr:GetAttribute("SavesRun"), true, "this session saves")

--============================================================ 2. the first objective is named and reachable
local help = hudText(plr, "Walk the hall")
truthy(help ~= nil and string.find(help, "ADVANCE (E)", 1, true) ~= nil and string.find(help, "TURN BACK (Q)", 1, true) ~= nil,
	"the HUD names the two actions and their keys: " .. tostring(help))
local adv, back = promptOn(plr, "AdvancePad"), promptOn(plr, "BackPad")
eq(adv and adv.KeyboardKeyCode, Enum.KeyCode.E, "ADVANCE is E")
eq(back and back.KeyboardKeyCode, Enum.KeyCode.Q, "TURN BACK is Q")
local reachFromSpawn = inReach(plr, "AdvancePad")
eq(reachFromSpawn, false, "the decision is at the far end: not pressable from the spawn")

--============================================================ 3. one full loop: walk, read, answer right
local serial1 = infoOf(plr):GetAttribute("Serial")
playPass(plr, true)
eq(plr.leaderstats.Day.Value, 2, "a right call: Day 2")
eq(hudText(plr, "DAY"), "DAY 2", "the HUD says DAY 2")
truthy(bestIs(plr, 2), "and Best: Day 2 (" .. tostring(hudText(plr, "Best:")) .. ")")
eq(infoOf(plr):GetAttribute("Serial"), serial1 + 1, "the hall loops: the next pass")
hrp = rootOf(plr)
truthy((hrp.Position - (o + Vector3.new(0, 4, -4))).Magnitude < 0.5, "and the player is back at the start of the hall")

--============================================================ 4. earn: a Field Guide entry, a better Best, hints from a code
local guard = 0
while infoOf(plr):GetAttribute("Clean") == true and guard < 30 do
	playPass(plr, true)
	guard += 1
end
local caughtId = infoOf(plr):GetAttribute("AnomalyId")
truthy(caughtId ~= nil, "an anomalous pass came up within 30 passes (" .. tostring(caughtId) .. ")")
playPass(plr, true) -- TURN BACK on the anomaly
local dayNow = plr.leaderstats.Day.Value
truthy(caught[caughtId] == true and caughtCount() >= 1, "the test counted the spotted anomaly")
eq(hudText(plr, "Field Guide:"), string.format("Field Guide: %d/%d", caughtCount(), TOTAL), "spotting an anomaly writes it into the Field Guide")
truthy(bestIs(plr, dayNow), "Best follows the streak: Day " .. dayNow .. " (" .. tostring(hudText(plr, "Best:")) .. ")")
local best = dayNow

local hud = plr.PlayerGui:FindFirstChild("AnomalyHud")
local codeBox = hud:FindFirstChild("CodeBox", true)
local redeemBtn = hud:FindFirstChild("RedeemButton", true)
local function redeem(code: string)
	codeBox.Text = code
	redeemBtn.Activated:Fire()
	h:advance(0.1)
end
realWait(2.1) -- the Redeem cooldown is wall-clock
redeem("welcome")
eq(lastReveal(plr) and lastReveal(plr).redeem, "ok", "WELCOME typed into the HUD's box redeems")
local hints = Config.Hint.StartTokens + Config.Codes.WELCOME.hintTokens
eq(hudText(plr, "Hints:"), string.format("Hints: %d  (H at start pad)", hints), "the HUD shows the new hints")
eq(hudText(plr, "Code redeemed"), "Code redeemed!", "and says so")

--============================================================ 5. spend: a hint at the start pad, a tint from a code
hrp = rootOf(plr)
local hintOk, hintD = inReach(plr, "StartPad")
truthy(hintOk, string.format("after a pass the player is at the start pad, in the hint's reach (%.1f studs)", hintD))
local n0 = #reveals(plr)
press(plr, "StartPad")
h:advance(0.1)
local r1 = lastReveal(plr)
eq(#reveals(plr), n0 + 1, "pressing H answers")
eq(r1 and r1.ok, true, "with a hint")
eq(r1 and r1.clean, infoOf(plr):GetAttribute("Clean"), "that tells the truth about this hall")
hints -= 1
eq(hudText(plr, "Hints:"), string.format("Hints: %d  (H at start pad)", hints), "and costs one hint")
truthy(hudText(plr, "HINT:") ~= nil, "the HUD shows the hint: " .. tostring(hudText(plr, "HINT:")))
-- the same hall again: the answer is already paid for
press(plr, "StartPad")
h:advance(0.1)
local r2 = lastReveal(plr)
eq(#reveals(plr), n0 + 2, "pressing H again on the same hall answers again")
eq(r2 and r2.ok, true, "with the same hint")
eq(r2 and r2.clean, r1 and r1.clean, "the same answer")
eq(hudText(plr, "Hints:"), string.format("Hints: %d  (H at start pad)", hints), "and does NOT charge a second hint for the same hall")
truthy(string.find(hudText(plr, "HINT:") or "", "no extra cost", 1, true) ~= nil,
	"and the HUD says so: " .. tostring(hudText(plr, "HINT:")))

realWait(2.1)
redeem("ECLIPSE")
eq(lastReveal(plr) and lastReveal(plr).redeem, "ok", "ECLIPSE redeems")
local gold = hud:FindFirstChild("Tint_gold", true)
local white = hud:FindFirstChild("Tint_white", true)
truthy(gold ~= nil and gold.Text == "", "the gold swatch is unlocked (no padlock)")
realWait(0.6) -- SetTint's cooldown is wall-clock
white.Activated:Fire()
h:advance(0.1)
eq(lastState(plr).tint, "white", "picking white selects it")
-- a second pick at once: the LAST pick must win, not vanish
gold.Activated:Fire()
h:advance(1)
eq(lastState(plr).tint, "gold", "a second pick within the cooldown is applied, not dropped (the last pick wins)")
local ring = gold:FindFirstChild("SelectionRing")
eq(ring and ring.Transparency, 0, "the HUD rings the gold swatch")
local head = plr.Character:FindFirstChild("Head")
local light = head and head:FindFirstChild("AnomalyTintLight")
local g = Config.TintRGB.gold
truthy(light ~= nil and math.abs(light.Color.R * 255 - g[1]) < 1 and math.abs(light.Color.G * 255 - g[2]) < 1,
	"the flashlight the player carries turns gold")
-- a pick that got through is never overridden by an OLDER one still waiting for the cooldown
realWait(0.6)
white.Activated:Fire() -- through
gold.Activated:Fire() -- waits
realWait(0.6)
white.Activated:Fire() -- through again, before the waiting gold is applied
h:advance(1)
eq(lastState(plr).tint, "white", "the newest pick wins over an older one still waiting (white, not gold)")

--============================================================ 6. a refused action says why
realWait(2.1)
local before = #reveals(plr)
redeem("observe")
redeem("midnight") -- at once: inside the first one's cooldown
eq(#reveals(plr), before + 2, "two codes back to back: BOTH get an answer (the HUD cleared the box for each)")
local second = lastReveal(plr)
truthy(second ~= nil and second.redeem ~= "ok" and type(second.message) == "string" and second.message ~= "",
	"the second is refused with a reason the HUD shows: " .. tostring(second and second.message))
eq(store.__data[KEY].redeemed.MIDNIGHT, nil, "and nothing was spent on it")
realWait(2.1)
redeem("midnight")
eq(lastReveal(plr) and lastReveal(plr).redeem, "ok", "sent again after the cooldown, it redeems")
hints += Config.Codes.OBSERVE.hintTokens + Config.Codes.MIDNIGHT.hintTokens
realWait(2.1)
before = #reveals(plr)
redeem(string.rep("X", 65))
eq(#reveals(plr), before + 1, "a pasted 65-character code gets an answer")
eq(lastReveal(plr) and lastReveal(plr).redeem, "unknown", "and the answer is 'Unknown code'")
eq(hudText(plr, "Unknown code"), "Unknown code", "which the HUD shows")

--============================================================ 7. a wrong call
playPass(plr, false)
eq(plr.leaderstats.Day.Value, 1, "a wrong call: back to Day 1")
truthy(bestIs(plr, best), "Best is kept: Day " .. best .. " (" .. tostring(hudText(plr, "Best:")) .. ")")
h:advance(3) -- the death beat
playPass(plr, true)
playPass(plr, true)
eq(plr.leaderstats.Day.Value, 3, "two right calls after it: Day 3")
-- a NEW hall's hint costs a hint again (the free repeat is for the hall it was bought for)
local hr = lastState(plr).hintTokens
press(plr, "StartPad")
h:advance(0.1)
eq(lastReveal(plr) and lastReveal(plr).again, nil, "on a new hall, H buys a new hint")
eq(lastState(plr).hintTokens, hr - 1, "and costs one")
hints -= 1
local fieldGuide = hudText(plr, "Field Guide:")
local hintsBefore = hudText(plr, "Hints:")

--============================================================ 8. leave, rejoin: everything the player earned is there
h:leave(plr)
h:advance(0.5)
local rec = store.__data[KEY]
truthy(rec ~= nil and rec.lock == nil, "leaving saved and released the lock")
truthy((guideStore.__data[KEY] or 0) > 0, "the Field Guide board holds the player's entry")
local p2 = joinAndSpawn("Walker")
eq(hudText(p2, "DAY"), "DAY 3", "the rejoin: DAY 3 (the saved run)")
truthy(bestIs(p2, best), "Best: Day " .. best .. " (" .. tostring(hudText(p2, "Best:")) .. ")")
eq(hudText(p2, "Field Guide:"), fieldGuide, "the Field Guide")
eq(hudText(p2, "Hints:"), hintsBefore, "the hints")
eq(hudText(p2, "Hints:"), string.format("Hints: %d  (H at start pad)", hints), "(every hint earned, less the two spent)")
eq(lastState(p2).tint, "white", "the tint the player picked last (white), not the one the code put on (gold)")
local hud2 = p2.PlayerGui:FindFirstChild("AnomalyHud")
local gold2 = hud2:FindFirstChild("Tint_gold", true)
eq(gold2 and gold2.Text, "", "the gold tint is still owned")
realWait(2.1)
codeBox = hud2:FindFirstChild("CodeBox", true)
redeemBtn = hud2:FindFirstChild("RedeemButton", true)
redeem("WELCOME")
eq(lastReveal(p2) and lastReveal(p2).redeem, "already", "a code redeemed last session stays redeemed")
eq(lastState(p2).hintTokens, hints, "and pays nothing twice")
h:leave(p2)

eq(#offFloor, 0, "every step of every walk was over the hall's floor: " .. table.concat(offFloor, ", "))
truthy(passes >= 5 and #outOfReach == 0, string.format("every one of the %d passes was answered from inside the pad's prompt reach, at the end of the hall: %s",
	passes, table.concat(outOfReach, ", ")))
truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomaly_walk: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly walk check failed", 0)
end
