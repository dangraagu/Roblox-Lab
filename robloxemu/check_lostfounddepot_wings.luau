-- Lost & Found Depot — the WINGS, hazards and the break, driven through the REAL client script.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_wings.luau 2>&1
--
-- The pure modules (EnvBands, Hazards, Rest, Wings) are unit-tested in lost-found-depot/tests. This file
-- checks the GLUE no unit test can see: that src/client/Wings.client.luau really takes the career from the
-- server's own State payload (shifts completed + the running shift's cleared share) and never from a
-- timer; that it glides the Lighting instead of cutting; that the wing's title card waits for the HUD's
-- summary card; that hazards fly only while the server's shift clock runs, only in a hazard wing, one at a
-- time, knock nobody sooner than 2 s after the warning, 1 s after the ring turns red and 1 s after they step
-- into it (a walker too), hit only a player who stays inside the red ring, never roll through the tray, and
-- are gone the moment the shift ends; that a broken cosmetic step never strands a knocked player; that the BREAK
-- never starts against a running clock and never moves the server's clock; that everything it builds is
-- local, non-collidable, non-queryable, out of the bay except where EYECANDY.md says, and inside the
-- budget at every wing and every seam, and under stress.
--
-- HOW PROGRESS IS DRIVEN. §1-§4 play the real server: a preloaded career (12 shifts), a real shift sorted
-- the way the main check sorts (reading the rendered tags, memo and bin signs), a real shift that runs
-- out. §5-§7 need progress values a test cannot wait for (36 shifts). There the check re-sends the
-- server's OWN last State payload through the real State remote with only `shifts` and `shift.state /
-- cleared / total` changed, the fields EYECANDY.md says drive the wings, once per frame so a real push in
-- between cannot undo it. Nothing else in the payload is invented.
--
-- Headless limits, stated: nothing renders and there is no physics. Frames are driven by firing
-- RunService.RenderStepped; the character moves only when this file moves it; a knock is observed as the
-- PlatformStand and velocity the client writes. How any of it LOOKS is on the Studio list.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-wings", viewport = { 1280, 720 }, touch = false })

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

-- The salt, pinned (as check_lostfounddepot.luau does): the same depot every run. Each unseeded call gets
-- its own seed, so consecutive shifts stay independent.
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(4242 + unseeded * 7919)
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
local function near(a, b, tol, msg)
	if type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s +- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local UID = 7101
h.services.DataStoreService:GetDataStore("LostFoundDepot_v1"):SetAsync("u_" .. UID, {
	data = { v = 1, cash = 900, cartLevel = 3, shoesLevel = 3, shifts = 12, perfects = 6, backlog = 350,
		bestPerfectSeconds = 80, endingSeen = false, redeemed = {} },
})

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot wings: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Rules = mod("Rules")
local EnvBands = mod("EnvBands")
local Hazards = mod("Hazards")
local Wings = mod("Wings")
local bands = Config.Env.Bands
local Hz = Config.Hazards
local Budget = Config.Budget
-- THE PROMISE (EYECANDY.md §3), as literals: a knock never comes sooner than 2 s after its warning appeared,
-- nor sooner than 1 s after the ring turned red (and after the player last stepped into it). Never read from
-- Config: every comparison below against Config's own MinReactSeconds let MinReactSeconds = 0 pass (REVIEW-2
-- finding 6).
local PROMISE_WARN, PROMISE_RED = 2.0, 1.0

-- the server's lighting BEFORE any client runs (Fx.applyLighting(Temple))
local Lighting = h.Lighting
local serverClock = Lighting.ClockTime
local serverAtmos = Lighting:FindFirstChild("FxAtmosphere")

-- every call any client makes to the server, from here on
local remotes = RS:FindFirstChild("DepotRemotes")
local serverCalls = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end
local StateEvent = remotes:FindFirstChild("State")
local SelectEvent = remotes:FindFirstChild("Select")

local plr = h:join("Winger", UID)
h:advance(0.2)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)

local function state()
	local s = StateEvent:sentTo(plr)
	return s[#s] and s[#s].args[1] or nil
end
local bay = plr.RespawnLocation.Parent
local OX = bay:FindFirstChild("BayPad").Position.X
local function W(x, y, z) return Vector3.new(OX + x, y, z) end

-- In memory, for this run only: a hazard every 6-7 s of RUNNING shift clock (the real 120-180 s is
-- measured in tests/Pacing.spec.luau). Set before the client loads, so its first roll uses it too.
Hz.IntervalMin = 6
Hz.IntervalMax = 7

-- Everything the WINGS client creates, recorded from its first line (Luau binds a global when a script
-- loads, so the wrapper has to be in place before Wings.client and WingArt compile). Hud.client loads
-- first, with the real Instance.
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local realInstance = Instance
local created = {}
Instance = {
	new = function(className, parent)
		local obj = realInstance.new(className, parent)
		table.insert(created, obj)
		return obj
	end,
}
local warnBefore = #h.warnings
local okWings, errWings = h:tryRun("client/Wings.client")
Instance = realInstance
truthy(okWings, "Wings.client loads (" .. tostring(errWings) .. ")")
local wingWarnings = {}
for i = warnBefore + 1, #h.warnings do
	if string.find(h.warnings[i], "DepotWings", 1, true) then table.insert(wingWarnings, h.warnings[i]) end
end
eq(#wingWarnings, 0, "Wings.client validates this game's Config without a warning (" .. table.concat(wingWarnings, " | ") .. ")")

local folder = h.workspace:FindFirstChild("DepotWings")
truthy(folder ~= nil and folder.ClassName == "Folder", "the client made its own workspace folder, DepotWings")
local gui = plr.PlayerGui:FindFirstChild("DepotWings")
local root = gui and gui:FindFirstChild("Root")
local panel = root and root:FindFirstChild("WingPanel")
local wingName = panel and panel:FindFirstChild("WingName")
local wingNext = panel and panel:FindFirstChild("WingNext")
local breakBtn = panel and panel:FindFirstChild("BreakButton")
local warnPanel = root and root:FindFirstChild("WarningPanel")
local warnText = warnPanel and warnPanel:FindFirstChild("WarningText")
local card = root and root:FindFirstChild("WingCard")
truthy(panel and wingName and wingNext and breakBtn and warnPanel and warnText and card,
	"the wing panel (name, next, BREAK), the hazard warning and the title card exist")
local hudRoot = plr.PlayerGui:FindFirstChild("DepotHud"):FindFirstChild("Root")
local summaryCard = hudRoot:FindFirstChild("SummaryCard")
local breakFocus = Lighting:FindFirstChild("DepotBreakFocus")
truthy(breakFocus ~= nil and breakFocus.Enabled == false, "the break's depth of field exists and is off")
do
	-- the wings never listen on State themselves (StateCache.luau): the HUD stays its only listener
	local code = {}
	for line in string.gmatch(bundle["client/Wings.client"].source .. "\n", "([^\n]*)\n") do
		table.insert(code, (string.gsub(line, "%-%-.*$", "")))
	end
	eq(string.find(table.concat(code, "\n"), "OnClientEvent", 1, true), nil,
		"Wings.client connects to no remote: the HUD keeps the queued join payload")
end

--============================================================================ the frame driver

local cam = h.workspace.CurrentCamera
local camMode = "bins" -- "bins": behind the player, looking at the arc (-Z); "tray": looking at the tray (+Z); "look": along camLook
local camLook = Vector3.new(0, 0, -1) -- camMode "look": a walker's camera, behind them along the way they walk
local camHeight, camBack = 8, 14
local pinned = nil -- a payload re-sent every frame (§5-§7)
local simTime = 0
local cards = {} -- every distinct title card shown, in order
local lastCard = ""
local flashes = 0
local lightingLog = {} -- { t, ClockTime } per frame
local frameHook = nil
local function frame(dt)
	local p = hrp.Position
	local look = if camMode == "look" then camLook elseif camMode == "bins" then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1)
	cam.CFrame = CFrame.new(p - look * camBack + Vector3.new(0, camHeight, 0), p)
	if pinned then StateEvent:FireClient(plr, pinned) end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
	if not card.Visible then lastCard = "" end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			flashes += 1
		end
	end
	table.insert(lightingLog, { t = simTime, clock = Lighting.ClockTime })
	if frameHook then frameHook(dt) end
end
local function run(seconds, dt)
	dt = dt or 1 / 30
	for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do frame(dt) end
end

local function bandValue(i, group, key) return bands[i][group][key] end
local function idx(id) return EnvBands.indexOf(bands, id) :: number end
local PARK, STATION, CITY, GALAXY = idx("park"), idx("station"), idx("city"), idx("galaxy")

--============================================================================ §1 join: the takeover glides

run(0.05)
near(Lighting.ClockTime, serverClock, 1e-3, "the first client frame keeps the server's ClockTime (no jump at join)")
eq(Lighting:FindFirstChild("FxAtmosphere"), serverAtmos, "the client took over the server's Atmosphere, not a second one")
do
	local atmos = 0
	for _, c in Lighting:GetChildren() do if c.ClassName == "Atmosphere" then atmos += 1 end end
	eq(atmos, 1, "exactly one Atmosphere in Lighting")
end
eq(panel.Visible, false, "before any State has arrived the wing panel stays hidden")
eq(#cards, 0, "and no title card is shown for a career the client has not been told")
-- The loaded profile was pushed while the player joined, before these scripts ran. Roblox queues it and
-- hands it to the first listener, the HUD; the emulator has no queue, so the server's own last payload is
-- delivered once here, the way that queue would. Only the HUD listens; the wings get it from StateCache.
StateEvent:FireClient(plr, state())
local mark = #lightingLog
-- A 12-shift veteran must never see the first wing's scenery at join: the scene fades in from nothing to
-- THEIR wing once the profile has loaded (the lighting glides from the server's preset, which is wing 1's).
local joinFrames, cityFrames, parkMax, parkFirst = 0, 0, 0, nil
frameHook = function()
	joinFrames += 1
	local city, park = 0, 0
	local opaque = 1
	for _, d in folder:GetChildren() do
		if d.Name == "CityRoof" or d.Name == "CitySkyline" then city += 1 end
		if d.Name == "ParkLights" or d.Name == "ParkRides" then
			park += 1
			opaque = math.min(opaque, d.Transparency)
		end
	end
	if city > 0 then cityFrames += 1 end
	if park > 0 and parkFirst == nil then parkFirst = opaque end
	parkMax = math.max(parkMax, park)
end
run(8)
frameHook = nil
eq(cityFrames, 0, "a returning 12-shift player never sees the CITY DEPOT's roof or skyline at join")
truthy(parkMax > 20, "CONTROL: the THEME PARK's scenery came (" .. parkMax .. " parts)")
truthy(parkFirst ~= nil and parkFirst > 0.8, string.format("and it faded in from nothing (first seen at transparency %.2f), no pop", parkFirst or -1))
near(Lighting.ClockTime, bandValue(PARK, "lighting", "ClockTime"), 0.05,
	"a returning 12-shift player's depot glides to the THEME PARK wing (ClockTime 18.1)")
do
	local total = bandValue(PARK, "lighting", "ClockTime") - serverClock
	local worst, over = 0, false
	for i = mark + 1, #lightingLog do
		local d = lightingLog[i].clock - lightingLog[i - 1].clock
		worst = math.max(worst, math.abs(d) / math.abs(total))
		if (lightingLog[i].clock - bandValue(PARK, "lighting", "ClockTime")) * math.sign(total) > 1e-6 then over = true end
	end
	truthy(worst <= 0.12, string.format("the join glide moves ClockTime at most 12%% of the way per write (worst %.1f%%)", worst * 100))
	eq(over, false, "and never overshoots")
end
eq(wingName.Text, "THEME PARK", "the wing panel names the wing (12 shifts done: THEME PARK)")
eq(wingNext.Text, "Next: SPACE STATION in 1 shift", "and counts shifts to the next wing")
truthy(panel.Visible, "the wing panel shows once the profile has loaded")
truthy(cards[1] == "THEME PARK", "a returning player gets a QUIET card for the wing they are in (" .. tostring(cards[1]) .. ")")
eq(flashes, 0, "... with no flash: nobody is congratulated twice")
eq(serverCalls, 0, "joining with the wings running called the server 0 times")

-- constant progress is constant: the wing never drifts with time
do
	run(20)
	near(Lighting.ClockTime, bandValue(PARK, "lighting", "ClockTime"), 0.01,
		"20 s later at the same career the lighting is still the THEME PARK's (progress, not time)")
	eq(wingName.Text, "THEME PARK", "and the wing has not moved on")
end

--============================================================================ §2 the break, between shifts

local function press() breakBtn.Activated:Fire() end
local function walkABit()
	hum.MoveDirection = Vector3.new(0.5, 0, 0)
	run(0.6)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	run(0.1)
end
do
	-- 28 s of standing still above: idle
	truthy(string.find(wingNext.Text, "Idle", 1, true) ~= nil, "standing still 20 s between shifts: idle (" .. wingNext.Text .. ")")
	eq(breakBtn.Text, "BACK TO WORK", "while idle the button offers to end it")
	walkABit()
	truthy(string.find(wingNext.Text, "Idle", 1, true) == nil, "moving ends idle")
	eq(state().shift.state, "ARMED", "CONTROL: the tray is armed, the clock not running")
	eq(breakBtn.Text, "TAKE A BREAK", "between shifts the button offers a break")
	press()
	run(0.2)
	eq(hum.Sit, true, "TAKE A BREAK sits the player down")
	eq(breakFocus.Enabled, true, "and softens the far view")
	eq(breakBtn.Text, "BACK TO WORK", "the button now offers to end it")
	truthy(string.find(wingNext.Text, "clock waits for your first pickup", 1, true) ~= nil,
		"the panel says the clock waits for the first pickup (" .. wingNext.Text .. ")")
	local st0 = state()
	run(30)
	eq(state().shift.state, "ARMED", "30 s on a break: the tray is still armed (a break never starts the clock)")
	eq(state().shift.endsAt, st0.shift.endsAt, "and the server's clock fields did not move")
	eq(hum.Sit, true, "still sitting")
	-- the first pickup starts the server's clock AND ends the break in the same frame
	local slot = bay:FindFirstChild("Slot_1")
	hrp.CFrame = CFrame.new(W(0, 3, 0))
	slot:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
	h:advance(0.05)
	eq(state().shift.state, "RUNNING", "CONTROL: the pickup started the server's clock")
	run(1 / 30)
	eq(hum.Sit, false, "the pickup ended the break in the next client frame (standing still)")
	eq(breakFocus.Enabled, false, "the focus is sharp again")
	eq(breakBtn.Text, "BREAK AFTER SHIFT", "mid-shift the button can only book a break")
	eq(serverCalls, 0, "the break called the server 0 times")
end

--============================================================================ §3 a real shift into SPACE

-- The main check's sorting bot (check_lostfounddepot.luau playShift), with every wait driven as client
-- frames so the wings see what a player's client would.
local BIN_OF_NAME = {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
local LETTER_OF_NAME = {}
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end
local function plain(text) return (string.gsub(text or "", "<[^>]*>", "")) end
local function readTray()
	local out = {}
	for s = 1, 8 do
		local part = bay:FindFirstChild("Slot_" .. s)
		local tag = part and part:FindFirstChild("Tag")
		if part and tag and tag.Enabled then
			table.insert(out, { slot = s, click = part:FindFirstChildOfClass("ClickDetector") })
		end
	end
	return out
end
local function readRules()
	local text = bay:FindFirstChild("MemoBoard"):FindFirstChild("SignGui"):FindFirstChild("Label").Text
	for _, memo in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, memo), 1, true) then return Rules.withMemo(Config, memo) end
	end
	return Rules.base(Config)
end
local function readBins()
	local out = {}
	for k = 1, 6 do
		local m = bay:FindFirstChild("Bin_" .. k)
		local label = m and m:FindFirstChild("Sign") and m.Sign:FindFirstChild("SignGui") and m.Sign.SignGui:FindFirstChild("Label")
		local id = label and BIN_OF_NAME[label.Text]
		if id then out[id] = { base = m:FindFirstChild("Base"), prompt = m.Base:FindFirstChild("Drop") } end
	end
	return out
end
local function binStand(base)
	local P = W(0, 3, 0)
	local flat = Vector3.new(base.Position.X, 3, base.Position.Z)
	return flat + (P - flat).Unit * 5
end
local function answerOf(entry, rules)
	local misfiled = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
	if misfiled then return BIN_OF_NAME[misfiled] end
	return (Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], rules))
end
local function walkTo(pos)
	local d = (hrp.Position - pos).Magnitude
	local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
	if flat.Magnitude > 1e-3 then hum.MoveDirection = flat.Unit end
	hrp.CFrame = CFrame.new(pos)
	run(math.max(1 / 30, d / hum.WalkSpeed))
	hum.MoveDirection = Vector3.new(0, 0, 0)
end
-- sorts until SUMMARY; `onDeposit(cleared)` after each deposit
local function playShift(onDeposit)
	local P = W(0, 3, 0)
	for _ = 1, 600 do
		local st = state()
		if st.shift.state == "SUMMARY" then return true end
		if #st.shift.carried == 0 then
			walkTo(P)
			camMode = "tray"
			local tray = readTray()
			if #tray == 0 then run(0.5) else
				local n = 0
				for _, t in tray do
					if n >= st.carry then break end
					t.click.MouseClick:Fire(plr)
					n += 1
				end
				run(0.4)
			end
			camMode = "bins"
		else
			local entry = st.shift.carried[1]
			local b = readBins()[answerOf(entry, readRules())]
			walkTo(binStand(b.base))
			SelectEvent:simulateFireServer(plr, 1)
			b.prompt.Triggered:Fire(plr)
			run(1 / 30)
			if onDeposit then onDeposit(state().shift.cleared) end
		end
	end
	return false
end

do
	local callsBefore = serverCalls
	local parkClock, stationClock = bandValue(PARK, "lighting", "ClockTime"), bandValue(STATION, "lighting", "ClockTime")
	local atCleared = {}
	local ok = playShift(function(cleared)
		run(3) -- let the glide settle on this career value
		atCleared[cleared] = Lighting.ClockTime
	end)
	truthy(ok, "the bot sorted the shift to its summary")
	serverCalls = callsBefore -- the bot's own Select presses are not the wings'
	local c15 = atCleared[15]
	near(c15, parkClock, 0.05, "15 of 30 sorted on shift 13 (career 12.5): still the THEME PARK light")
	local c19 = atCleared[19]
	near(c19, parkClock, 0.05, "19 of 30 (12.63): the space wing has not started to fade in")
	local c25 = atCleared[25]
	truthy(c25 and c25 > parkClock + 0.5 and c25 < stationClock - 0.5,
		string.format("25 of 30 (12.83): half way into the SPACE STATION light (ClockTime %s)", tostring(c25)))
	local c29 = atCleared[29]
	truthy(c29 and c29 > c25 and c29 > stationClock - 1.0,
		string.format("29 of 30 (12.97): nearly there (ClockTime %s), driven by the items sorted", tostring(c29)))
	local mono = true
	local lastC = -1
	for k = 1, 30 do
		if atCleared[k] then
			if atCleared[k] < lastC - 1e-6 then mono = false end
			lastC = atCleared[k]
		end
	end
	truthy(mono, "the light only ever moves toward space as items are sorted")
	eq(state().shifts, 13, "CONTROL: the server counted the shift (13 done)")
	run(0.5)
	truthy(summaryCard.Visible, "CONTROL: the HUD's summary card is up")
	eq(card.Visible and card.Text == "YOU MADE IT TO SPACE!", false,
		"the wing's title card waits while the summary card owns the screen")
	local flashBefore = flashes
	summaryCard:FindFirstChild("OkButton").Activated:Fire()
	run(0.2)
	eq(card.Visible and card.Text, "YOU MADE IT TO SPACE!", "the summary closed: YOU MADE IT TO SPACE!")
	eq(root:FindFirstChild("WingCardSub").Text, "SPACE STATION - Orbital lost property, deck 3", "with the wing's name under it")
	eq(flashes, flashBefore + 1, "and one celebratory flash")
	run(8)
	near(Lighting.ClockTime, stationClock, 0.05, "the SPACE STATION light has settled (ClockTime 23)")
	eq(wingName.Text, "SPACE STATION", "the panel names the new wing")
	eq(wingNext.Text, "Next: BEYOND THE GALAXY in 23 shifts", "and the long-term goal")
end

--============================================================================ §4 hazards and the break, mid-shift

-- (Hazards fly every 6-7 s of running clock in this run: Hz was set in memory before the client loaded.)
local function hazardPart()
	for _, c in folder:GetChildren() do
		if string.match(c.Name, "^Hazard_") then return c end
	end
	return nil
end
local function ringPart()
	return folder:FindFirstChild("Ring")
end

do
	-- back at the pick point, facing the bins, the next shift armed
	for _ = 1, 40 do
		if state().shift.state == "ARMED" then break end
		run(0.5)
	end
	eq(state().shift.state, "ARMED", "CONTROL: the next tray is armed")
	hrp.CFrame = CFrame.new(W(0, 3, 0))
	camMode = "bins"
	-- no hazard while the clock is not running: 20 s armed with hazards due every 6-7 s
	local seen = 0
	frameHook = function() if hazardPart() then seen += 1 end end
	run(20)
	eq(seen, 0, "no hazard flies while the tray is armed (the clock is not running): 20 s, interval 6-7 s")
	-- start the shift: one pickup
	bay:FindFirstChild("Slot_1"):FindFirstChildOfClass("ClickDetector").MouseClick:Fire(plr)
	run(0.2)
	eq(state().shift.state, "RUNNING", "CONTROL: the shift clock runs")
	local endsAt = state().shift.endsAt

	local hazards, hits, dodges, dodgeHits, standHits, twoAtOnce = 0, 0, 0, 0, 0, 0
	local shortWarn, offFloor, wrongKind, ringHidden = 0, 0, 0, 0
	local warnAt, active, mode, liftMax, sideMin, stumbleOk = nil, nil, "stand", 0, math.huge, 0
	local hitWhileOutside = 0
	local shortRed, minWarn, minRed = 0, math.huge, math.huge
	local backs, backHits, backAfterArrival = 0, 0, 0
	local rect = Wings.bayRect(Config, OX)
	-- Two places to be caught: the pick point (long lanes toward the arc, fast hazards) and a spot out on the
	-- floor where the room in view is only 10-12 studs, so the fitted lanes are SLOW (a slow hazard touches
	-- a player well before it arrives: the case Wings.lockNear's reaction time is for).
	local Layout = mod("Layout")
	local boxes = Wings.obstacles(Config, Layout, OX, Hz.ObstacleMargin)
	local shortSpot = nil
	for gz = -4, -30, -1 do
		for gx = -20, 20 do
			if shortSpot == nil then
				local sp = { x = OX + gx, y = 3, z = gz }
				local free = Wings.inRect(rect, sp, 3)
				for _, b in boxes do if free and Wings.inObstacle(b, sp.x, sp.z) then free = false end end
				local room = if free then Wings.room(rect, sp, math.pi, Hz.SpreadDegrees, Hz.FloorMargin, boxes) else 0
				if room >= 10.2 and room <= 12 then shortSpot = Vector3.new(sp.x, 3, sp.z) end
			end
		end
	end
	truthy(shortSpot ~= nil, "CONTROL: a spot with 10-12 studs of room in view exists on the floor")
	local home = W(0, 3, 0)
	local stationKinds = {}
	for _, k in bands[STATION].hazards do stationKinds["Hazard_" .. k] = true end
	local jiggle = 0
	local wasPS = false
	frameHook = function(dt)
		local n = 0
		local hp = nil
		for _, c in folder:GetChildren() do
			if string.match(c.Name, "^Hazard_") then
				n += 1
				hp = hp or c
			end
		end
		-- several parts per model: count MODELS by name
		local kinds = {}
		for _, c in folder:GetChildren() do
			local k = string.match(c.Name, "^(Hazard_%a+)$")
			if k then kinds[k] = true end
		end
		local models = 0
		for k in kinds do
			models += 1
			if not stationKinds[k] then wrongKind += 1 end
		end
		if models > 1 then twoAtOnce += 1 end
		if models == 1 and active == nil then
			hazards += 1
			active = { at = simTime, start = hp.Position, mode = mode }
			if not Wings.inRect(rect, { x = hp.Position.X, z = hp.Position.Z }, Hz.FloorMargin - 0.6) then offFloor += 1 end
		end
		if active and warnPanel.Visible and warnAt == nil then warnAt = simTime end
		if active and active.redAt == nil and string.find(warnText.Text, "MOVE!", 1, true) and warnPanel.Visible then
			active.redAt = simTime
		end
		if active and active.mode ~= "stand" and not active.dodged and string.find(warnText.Text, "MOVE!", 1, true) then
			-- the lane locked: walk out of the red ring, sideways
			local ring = ringPart()
			local c = ring.Position
			active.ringCentre = Vector3.new(c.X, 3, c.Z)
			hrp.CFrame = CFrame.new(Vector3.new(c.X + ring.Size.Y / 2 + 1.2, 3, c.Z))
			active.dodged = true
			active.dodgedAt = simTime
			dodges += 1
		end
		if active and active.mode == "back" and active.dodged and not active.back and warnAt and hp
			and simTime >= warnAt + (Hz.Kinds[string.sub(hp.Name, 8)] or { telegraph = 3 }).telegraph - 0.6 then
			-- the careless one: about 0.6 s before the hazard arrives they step back into the red ring, onto its
			-- FAR side (downstream along the lane, 2.6 studs past its centre), and stay. Stepping in starts their
			-- second in the ring again (Wings.checkHit), which runs out AFTER the hazard has "arrived" at the
			-- centre; it is still within reach of them then, which is why the ring stays up after arrival for as
			-- long as a hit inside it is possible (Wings.zoneLive).
			local c = active.ringCentre
			local d = Vector3.new(c.X - hp.Position.X, 0, c.Z - hp.Position.Z)
			local u = if d.Magnitude > 0.01 then d.Unit else Vector3.new(0, 0, 1)
			hrp.CFrame = CFrame.new(c + u * 2.6)
			active.back = true
			backs += 1
		end
		if active then
			local ring = ringPart()
			if ring == nil or ring.Parent ~= folder then
				-- the ring is gone: nothing may hit from here on (checked on the knock below)
				active.ringGone = true
			end
		end
		if hum.PlatformStand and not wasPS then
			hits += 1
			local v = hrp.AssemblyLinearVelocity
			liftMax = math.max(liftMax, v.Y)
			sideMin = math.min(sideMin, Vector3.new(v.X, 0, v.Z).Magnitude)
			if active then
				if warnAt == nil or simTime - warnAt < PROMISE_WARN - 1e-6 then shortWarn += 1 end
				if active.redAt == nil or simTime - active.redAt < PROMISE_RED - 2 / 30 - 1e-6 then shortRed += 1 end
				minWarn = math.min(minWarn, if warnAt then simTime - warnAt else -1)
				minRed = math.min(minRed, if active.redAt then simTime - active.redAt else -1)
				if active.mode == "dodge" then dodgeHits += 1 elseif active.mode == "back" then backHits += 1 else standHits += 1 end
				if active.mode == "back" and folder:FindFirstChild("Lane") == nil and ringPart() ~= nil and ringPart().Parent == folder then
					backAfterArrival += 1
				end
				if active.ringGone then ringHidden += 1 end
				local ring = ringPart()
				if ring and ring.Parent == folder then
					local d = Vector3.new(hrp.Position.X - ring.Position.X, 0, hrp.Position.Z - ring.Position.Z).Magnitude
					if d > ring.Size.Y / 2 + 1e-3 then hitWhileOutside += 1 end
				end
			end
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) -- no physics: the stumble is observed, not simulated
		end
		if wasPS and not hum.PlatformStand then stumbleOk += 1 end
		wasPS = hum.PlatformStand
		if models == 0 and active then
			active = nil
			warnAt = nil
			mode = if mode == "stand" then "dodge" elseif mode == "dodge" then "back" else "stand"
			hrp.CFrame = CFrame.new(home) -- back to work
		end
		-- keep idle rest from starting while this section wants hazards: a step every 8 s between hazards
		jiggle += dt
		if active == nil and jiggle >= 8 then
			jiggle = 0
			hum.MoveDirection = Vector3.new(1, 0, 0)
		else
			hum.MoveDirection = Vector3.new(0, 0, 0)
		end
	end
	hrp.CFrame = CFrame.new(home)
	run(60)
	home = shortSpot or home
	for _ = 1, 200 do
		if active == nil then break end
		run(0.1)
	end
	hrp.CFrame = CFrame.new(home)
	local hazardsBefore = hazards
	run(90)
	local shortHazards = hazards - hazardsBefore
	frameHook = nil
	print(string.format("  150 s of running clock (60 at the pick point, 90 on the short-lane spot), a hazard due every 6-7 s: %d hazards (%d on the short-lane spot), %d knocks (%d standing, %d after walking out, %d stepping back onto the ring's far side just before arrival, %d of them after it), %d dodges",
		hazards, shortHazards, hits, standHits, dodgeHits, backHits, backAfterArrival, dodges))
	print(string.format("  every knock came at least %.2f s after its warning appeared and %.2f s after MOVE! (the ring turning red)", minWarn, minRed))
	truthy(hazards >= 16, "set-up: hazards kept coming (" .. hazards .. ")")
	truthy(shortHazards >= 6, "set-up: hazards came on the short-lane spot too (" .. shortHazards .. ")")
	eq(twoAtOnce, 0, "never two hazards at once")
	eq(wrongKind, 0, "only the SPACE STATION's kinds fly there (crate, drone)")
	eq(offFloor, 0, "every hazard starts on the player's own sorting floor, off the walls")
	truthy(standHits >= 4, "a player who stays in the ring is knocked (" .. standHits .. ")")
	eq(dodgeHits, 0, "a player who walks out of the red ring is never knocked (" .. dodges .. " dodges)")
	truthy(backs >= 4 and backHits >= 1, string.format(
		"CONTROL: stepping back into the red ring and staying there is knocked (%d of %d)", backHits, backs))
	truthy(backAfterArrival >= 1, string.format(
		"CONTROL: ... %d of those AFTER the lane line went (the hazard had arrived), with the ring still up: it must stay that long (Wings.zoneLive)", backAfterArrival))
	eq(shortWarn, 0, string.format("every knock came at least %.1f s after its warning appeared", PROMISE_WARN))
	eq(shortRed, 0, string.format("and at least %.1f s (less a frame) after the ring turned red and the banner said MOVE!", PROMISE_RED))
	eq(hitWhileOutside, 0, "nobody is knocked while outside the drawn ring")
	eq(ringHidden, 0, "no knock after the ring was taken away")
	truthy(liftMax <= Hz.KnockLift + 1e-6, string.format("a knock lifts at most KnockLift (%.1f)", liftMax))
	truthy(sideMin >= 15, string.format("a knock is a real shove sideways (at least 15 studs/s, got %.1f)", sideMin))
	truthy(stumbleOk >= standHits, "every stumble wears off (PlatformStand back to false)")
	eq(state().shift.endsAt, endsAt, "hazards and knocks never moved the server's clock (endsAt unchanged)")
	eq(serverCalls, 0, "hazards called the server 0 times")

	-- IDLE mid-shift: hazards leave a still player alone, their clock FREEZES (never resets), and the
	-- server's shift clock keeps running. With a hazard every 6-7 s the sky is never clear for the 20 s idle
	-- needs (a rest never starts with a hazard in the air), so the next gap is stretched to 40-41 s: the
	-- next launch rolls its successor that far out.
	hrp.CFrame = CFrame.new(W(0, 3, 0))
	Hz.IntervalMin = 40
	Hz.IntervalMax = 41
	local function waitFor(cond, limit)
		local t = 0
		local ok = cond() -- evaluated once per step: a condition may watch for an edge
		while not ok and t < limit do
			hum.MoveDirection = if math.floor(simTime * 2) % 2 == 0 then Vector3.new(0.2, 0, 0) else Vector3.new(0, 0, 0)
			run(0.1)
			t += 0.1
			ok = cond()
		end
		hum.MoveDirection = Vector3.new(0, 0, 0)
		return ok
	end
	-- The next LAUNCH after the change rolls its successor 40-41 s out. A launch is the INCOMING warning
	-- coming up (a hazard can follow the last one in the same frame, so an empty sky is no marker).
	local function incoming() return warnPanel.Visible and string.find(warnText.Text, "INCOMING", 1, true) ~= nil end
	local wasIncoming = incoming()
	truthy(waitFor(function()
		local now = incoming()
		local rose = now and not wasIncoming
		wasIncoming = now
		return rose
	end, 20), "CONTROL: a hazard launched after the change (its successor is 40-41 s out)")
	local launchedAt = simTime
	truthy(waitFor(function() return hazardPart() == nil end, 20), "CONTROL: and it passed")
	hrp.CFrame = CFrame.new(W(0, 3, 0))
	local left0 = state().shift.endsAt - h.scheduler:now()
	run(21)
	truthy(string.find(wingNext.Text, "Idle", 1, true) ~= nil, "standing still 20 s mid-shift under a clear sky: idle (" .. wingNext.Text .. ")")
	eq(hum.Sit, false, "idle does not sit the player down")
	local during = 0
	frameHook = function() if hazardPart() then during += 1 end end
	run(25)
	frameHook = nil
	local climbed = simTime - launchedAt
	truthy(climbed > 41 + 2, string.format("CONTROL: %.0f s since the last launch, past the 40-41 s the next was due in", climbed))
	eq(during, 0, "idle: the due hazard did not launch (its clock is frozen while the player is still)")
	local left1 = state().shift.endsAt - h.scheduler:now()
	near(left0 - left1, 46, 0.2, "and the server's shift clock ran on the whole 46 s (idle never touches it)")
	Hz.IntervalMin = 6 -- its successor, rolled at the next launch, comes back to 6-7 s
	Hz.IntervalMax = 7
	walkABit()
	truthy(string.find(wingNext.Text, "Idle", 1, true) == nil, "moving ends idle")
	local woke = simTime
	truthy(waitFor(function() return hazardPart() ~= nil end, 30), "the frozen hazard comes after waking")
	local after = simTime - woke
	print(string.format("  idle mid-shift: %.0f s since the last launch when idle began, frozen for 25 s; the next hazard came %.1f s after waking",
		climbed - 25, after))
	truthy(after < 25, string.format("... %.1f s after waking: the idle time was frozen, not a fresh 40-41 s (a reset would thin hazards out)", after))
	waitFor(function() return hazardPart() == nil end, 20)

	-- BREAK mid-shift: booked, never started; the server's clock does not hear of it
	press()
	run(0.2)
	eq(breakBtn.Text, "BREAK BOOKED", "BREAK mid-shift books a break for the end of the shift")
	eq(hum.Sit, false, "... it does not sit the player down")
	eq(breakFocus.Enabled, false, "... or blur anything")
	local sawHazard = 0
	frameHook = function(dt)
		if hazardPart() then sawHazard += 1 end
		-- keep moving a little, so idle cannot be what stops hazards here
		hum.MoveDirection = if math.floor(simTime * 2) % 2 == 0 then Vector3.new(0.2, 0, 0) else Vector3.new(0, 0, 0)
	end
	run(30)
	frameHook = nil
	hum.MoveDirection = Vector3.new(0, 0, 0)
	truthy(sawHazard > 0, "a booked break does not stop hazards mid-shift (they kept flying)")
	eq(state().shift.endsAt, endsAt, "booking a break did not move the server's clock")
	eq(state().shift.state, "RUNNING", "the shift is still running")
	-- run the clock out (standing in the lanes: hazards keep coming until the last second); the booked
	-- break starts at the summary
	local inAirAtEnd = false
	for _ = 1, 400 * 30 do
		inAirAtEnd = hazardPart() ~= nil
		frame(1 / 30)
		if state().shift.state == "SUMMARY" then break end
	end
	eq(state().shift.state, "SUMMARY", "CONTROL: the shift ran out")
	run(1 / 30)
	eq(hazardPart(), nil, "the frame the clock stops, no hazard is left in the air"
		.. (if inAirAtEnd then " (one was flying when the clock ran out)" else ""))
	eq(folder:FindFirstChild("Ring"), nil, "... and no ring on the floor")
	eq(warnPanel.Visible, false, "... and no warning")
	eq(hum.Sit, true, "the shift ended: the booked break starts at once (sitting)")
	eq(breakBtn.Text, "BACK TO WORK", "... and the button ends it")
	eq(state().shifts, 14, "CONTROL: the timed-out shift counted (14)")
	serverCalls = 0
	local sawOnBreak = 0
	frameHook = function() if hazardPart() then sawOnBreak += 1 end end
	run(20)
	frameHook = nil
	eq(sawOnBreak, 0, "no hazard during the summary or on the break")
	eq(serverCalls, 0, "the break called the server 0 times")
	summaryCard:FindFirstChild("OkButton").Activated:Fire()
	run(0.2)
end

--============================================================================ §5 every wing and every seam: budgets

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in t do o[k] = copy(v) end
	return o
end
local base = copy(state())
local function payload(shifts, running, cleared)
	local p = copy(base)
	p.shifts = shifts
	p.shift = copy(base.shift)
	p.shift.state = if running then "RUNNING" else "ARMED"
	p.shift.cleared = cleared or 0
	p.shift.total = 30
	p.shift.carried = {}
	p.shift.summary = nil
	return p
end

local OVERHEAD = { CityRoof = true, AirportRoof = true, AirportRoofSign = true, TrainShed = true, ParkLights = true, StationDome = true }
local INSIDE_OK = { WingSignsSign = true, Lane = true, Ring = true, WeatherHost = true }
local peak = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0, hazards = 0 }
local where = {}
local rows = {}
local badPart, insideBay, lowOverhead, critterInBay = {}, {}, 0, 0
local lowestOverhead = math.huge
local function measure(label)
	local m = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0, hazards = 0 }
	local kinds = {}
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if d:IsA("BasePart") then
			m.parts += 1
			if d.CanCollide or d.CanQuery or d.CanTouch or not d.Anchored or d.CastShadow then
				badPart[d.Name] = true
			end
			local k = string.match(d.Name, "^Hazard_(%a+)$")
			if k then kinds[k] = true end
			local p = d.Position
			local inRect = p.X > OX - 36 and p.X < OX + 36 and p.Z > -36 and p.Z < 20
			if inRect and p.Y < 16 and not (INSIDE_OK[d.Name] or k) then insideBay[d.Name] = true end
			if OVERHEAD[d.Name] then
				-- the lowest point of its oriented box
				local cf, s = d.CFrame, d.Size
				local ext = math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
				local low = p.Y - ext
				lowestOverhead = math.min(lowestOverhead, low)
				if low < Config.Env.OverheadFade.Gone - 1e-3 then lowOverhead += 1 end
			end
			if (d.Name == "Pigeon" or d.Name == "Balloon" or d.Name == "Satellite" or d.Name == "Astronaut" or d.Name == "Comet"
				or d.Name == "Airliner") and inRect and p.Y < 18 then
				critterInBay += 1
			end
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate
		elseif cls == "Beam" and d.Enabled then
			m.beams += 1
		elseif cls == "Trail" and d.Enabled then
			m.trails += 1
		elseif cls == "PointLight" and d.Enabled then
			m.lights += 1
		end
	end
	for _ in kinds do m.hazards += 1 end
	for k, v in m do
		if v > peak[k] then
			peak[k] = v
			where[k] = label
		end
	end
	return m
end

Hz.IntervalMin = 6
Hz.IntervalMax = 7
camHeight, camBack = 8, 14
hrp.CFrame = CFrame.new(W(0, 3, 0))
hum.Sit = false
local worstHazardFrame = { parts = 0 }
local function settleAt(label, p)
	pinned = p
	-- 8 s to settle, then 8 s more measured every frame, a step now and then so idle rest stays off
	local t0 = simTime
	frameHook = function()
		hum.MoveDirection = if math.floor(simTime) % 7 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
		if simTime - t0 > 8 then
			local m = measure(label)
			if m.hazards > 0 and m.parts > worstHazardFrame.parts then worstHazardFrame = { parts = m.parts, label = label } end
		end
	end
	run(16)
	frameHook = nil
	hum.MoveDirection = Vector3.new(0, 0, 0)
	return measure(label)
end

print("  where                           parts  emitters (rate)  beams  trails  lights")
for i, b in bands do
	local m = settleAt(b.name, payload(b.from, true, 0))
	table.insert(rows, string.format("  %-30s %5d  %8d (%4.1f)  %5d  %6d  %6d", b.name, m.parts, m.emitters, m.rate, m.beams, m.trails, m.lights))
	eq(wingName.Text, b.name, "at " .. b.from .. " shifts the panel names " .. b.name)
	near(Lighting.ClockTime, b.lighting.ClockTime, 0.05, b.name .. " lighting settles on its own ClockTime")
	if i < #bands then
		local nb = bands[i + 1]
		local seamShifts = nb.from - 1
		local cleared = math.floor((1 - nb.fade / 2) * 30 + 0.5)
		local label = b.name .. " > " .. nb.name
		local s = settleAt(label, payload(seamShifts, true, cleared))
		table.insert(rows, string.format("  %-30s %5d  %8d (%4.1f)  %5d  %6d  %6d", label, s.parts, s.emitters, s.rate, s.beams, s.trails, s.lights))
		local lo = math.min(b.lighting.ClockTime, nb.lighting.ClockTime)
		local hi = math.max(b.lighting.ClockTime, nb.lighting.ClockTime)
		if seamShifts ~= b.from then
			-- the seam is past this wing's own from: the running wing is b only if seamShifts < nb.from
			truthy(Lighting.ClockTime > lo + 0.05 and Lighting.ClockTime < hi - 0.05,
				string.format("%s: mid-seam the light is between the two wings (%.2f in %.1f..%.1f)", label, Lighting.ClockTime, lo, hi))
		end
	end
end
for _, r in rows do print(r) end
print(string.format("  peaks: parts %d (%s), emitters %d (%s), particles/s %.1f (%s), beams %d, trails %d, lights %d, hazards at once %d; worst frame with a hazard in flight %d parts (%s)",
	peak.parts, where.parts, peak.emitters, where.emitters, peak.rate, where.rate, peak.beams, peak.trails, peak.lights, peak.hazards,
	worstHazardFrame.parts, tostring(worstHazardFrame.label)))
truthy(worstHazardFrame.parts > 0, "set-up: budgets were measured with a hazard in flight too")
truthy(peak.parts <= Budget.MaxLocalParts, "local parts within budget at every wing and seam (" .. peak.parts .. ")")
truthy(peak.emitters <= Budget.MaxEmitters, "emitters within budget (" .. peak.emitters .. ")")
truthy(peak.rate <= Budget.MaxEmitterRate + 1e-6, "particles per second within budget (" .. peak.rate .. ")")
truthy(peak.beams <= Budget.MaxBeams, "beams within budget (" .. peak.beams .. ")")
truthy(peak.trails <= Budget.MaxTrails, "trails within budget (" .. peak.trails .. ")")
truthy(peak.lights <= Budget.MaxLights, "lights within budget (" .. peak.lights .. ")")
truthy(peak.hazards <= Budget.MaxHazards, "one hazard at a time (" .. peak.hazards .. ")")

do
	local names = {}
	for n in badPart do table.insert(names, n) end
	table.sort(names)
	eq(#names, 0, "every client part is anchored, CanCollide/CanQuery/CanTouch off, no shadow (" .. table.concat(names, ",") .. ")")
	local inside = {}
	for n in insideBay do table.insert(inside, n) end
	table.sort(inside)
	eq(#inside, 0, "inside the bay's walls only the wing signs, the hazard, its lane and ring and the invisible weather host ("
		.. table.concat(inside, ",") .. ")")
	truthy(lowestOverhead < math.huge, "CONTROL: overhead parts were measured")
	eq(lowOverhead, 0, string.format(
		"every roof, lamp and string light is at or above OverheadFade.Gone (%.1f; lowest point %.2f): a camera that shows the roof is below all of it",
		Config.Env.OverheadFade.Gone, lowestOverhead))
	truthy(lowestOverhead >= Config.Bay.WallHeight, string.format("and above the wall tops (%.2f >= 16): nothing overhead reaches into the bay", lowestOverhead))
	eq(critterInBay, 0, "no critter ever flies inside the bay below 18 studs")
end

-- no wing in the first shifts brings hazards: CITY DEPOT, running clock, 60 s with hazards due every 6-7 s
do
	local seen = 0
	pinned = payload(1, false, 0)
	for _ = 1, 200 do
		if hazardPart() == nil then break end
		run(0.1) -- the hazard still flying from the last wing lands first
	end
	pinned = payload(1, true, 5)
	frameHook = function()
		if hazardPart() then seen += 1 end
		hum.MoveDirection = if math.floor(simTime) % 7 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
	end
	run(60)
	frameHook = nil
	eq(seen, 0, "CITY DEPOT (shifts 1-3): no hazard in 60 s of running clock")
	eq(wingName.Text, "CITY DEPOT", "CONTROL: the city wing")
end

-- No hazard outlives the shift, on purpose this time: a hazard is made to be in the air, then the shift ends.
do
	local function airborne() return hazardPart() ~= nil end
	pinned = payload(13, true, 10) -- SPACE STATION, the clock running
	local t = 0
	while not airborne() and t < 20 do
		hum.MoveDirection = if math.floor(simTime) % 7 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
		run(0.1)
		t += 0.1
	end
	hum.MoveDirection = Vector3.new(0, 0, 0)
	truthy(airborne() and folder:FindFirstChild("Ring") ~= nil, "CONTROL: a hazard is in the air, its ring on the floor")
	local done = payload(14, false, 0)
	done.shift.state = "SUMMARY" -- the shift just ended
	pinned = done
	run(1 / 30)
	eq(hazardPart(), nil, "the frame the shift ends, the hazard in the air is gone")
	eq(folder:FindFirstChild("Ring"), nil, "... with its ring")
	eq(warnPanel.Visible, false, "... and its warning")
end

-- A still player gets a full second of red ring even from a SLOW hazard: stand where the view has only
-- 12-13.5 studs of floor, so every fitted lane is short and slow (the repair drone then touches a player
-- well before it arrives), and never move. Every knock must come at least MinReactSeconds (less two frames
-- of sampling) after MOVE!.
do
	local Layout = mod("Layout")
	local rect = Wings.bayRect(Config, OX)
	local boxes = Wings.obstacles(Config, Layout, OX, Hz.ObstacleMargin)
	local spot = nil
	for gz = -4, -30, -1 do
		for gx = -20, 20 do
			if spot == nil then
				local sp = { x = OX + gx, y = 3, z = gz }
				local free = Wings.inRect(rect, sp, 3)
				for _, b in boxes do if free and Wings.inObstacle(b, sp.x, sp.z) then free = false end end
				local room = if free then Wings.room(rect, sp, math.pi, Hz.SpreadDegrees, Hz.FloorMargin, boxes) else 0
				if room >= 12 and room <= 13.5 then spot = Vector3.new(sp.x, 3, sp.z) end
			end
		end
	end
	truthy(spot ~= nil, "CONTROL: a spot with 12-13.5 studs of room in view exists")
	for _ = 1, 200 do
		if hazardPart() == nil then break end
		run(0.1)
	end
	hrp.CFrame = CFrame.new(spot or W(0, 3, 0))
	camMode = "bins"
	pinned = payload(13, true, 10)
	local redAt, wasPS, knocks, minRed, launches, wasInc = nil, false, 0, math.huge, 0, false
	frameHook = function()
		local inc = warnPanel.Visible and string.find(warnText.Text, "INCOMING", 1, true) ~= nil
		if inc and not wasInc then launches += 1; redAt = nil end
		wasInc = inc
		if redAt == nil and warnPanel.Visible and string.find(warnText.Text, "MOVE!", 1, true) then redAt = simTime end
		if hum.PlatformStand and not wasPS then
			knocks += 1
			minRed = math.min(minRed, if redAt then simTime - redAt else -1)
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			hrp.CFrame = CFrame.new(spot or W(0, 3, 0))
		end
		wasPS = hum.PlatformStand
	end
	run(100)
	frameHook = nil
	print(string.format("  standing still on a short-lane spot: %d hazards, %d knocks, each at least %.2f s after MOVE!", launches, knocks, minRed))
	truthy(knocks >= 6, "set-up: the still player was knocked again and again (" .. knocks .. ")")
	truthy(minRed >= PROMISE_RED - 2 / 30 - 1e-6, string.format("even a slow hazard gives a still player %.1f s of red ring (worst %.2f)", PROMISE_RED, minRed))
end

-- REVIEW-2 finding 1, through the real client: a sorter who WALKS. Lanes start ahead of the camera, which
-- for a walker is where they are going; with the plain ring rule a walker at 18 studs/s was knocked 0.40 s
-- after the warning and 0.13 s after MOVE! (31 knocks in 48 hazards). The sorter here walks the pick point
-- -> a bin stand -> the pick point -> the next stand at 18 studs/s, the camera behind them along the way they
-- walk, and stops 1.2 s at each stand (dropping) and 1.5 s at the pick point facing the arc: stops long
-- enough to be caught in a ring. THE PROMISE, as literals (EYECANDY.md §3; never read from Config, so a
-- retune cannot lower it and pass): every knock at least 2 s after its warning appeared, at least 1 s
-- after MOVE!, and at least 1 s after the player last stepped into the drawn ring.
do
	local Layout = mod("Layout")
	for _ = 1, 200 do
		if hazardPart() == nil then break end
		run(0.1)
	end
	local stops = {}
	for arc = 1, 6 do
		local sx, sz = Layout.binStand(Config, arc)
		table.insert(stops, { x = 0, z = 0, stay = 1.5, face = Vector3.new(0, 0, -1) })
		table.insert(stops, { x = sx, z = sz, stay = 1.2 })
	end
	local SPEED = 18
	local totals = { hazards = 0, knocks = 0, short = 0, minWarn = math.huge, minRed = math.huge, minIn = math.huge, outside = 0 }
	for _, wing in { { shifts = 9, name = "THEME PARK" }, { shifts = 13, name = "SPACE STATION" } } do
		pinned = payload(wing.shifts, true, 10)
		camMode = "look"
		local pos = { x = 0, z = 0 }
		hrp.CFrame = CFrame.new(W(0, 3, 0))
		local si, stayLeft = 1, nil
		local active, warnAt, redAt, enteredAt, wasPS, wasIn = false, nil, nil, nil, false, false
		frameHook = function(dt)
			-- the walk (the check moves the character; there is no physics)
			local goal = stops[si]
			if stayLeft then
				stayLeft -= dt
				hum.MoveDirection = Vector3.new(0, 0, 0)
				if goal.face then camLook = goal.face end
				if stayLeft <= 0 then
					stayLeft = nil
					si = si % #stops + 1
				end
			else
				local dx, dz = goal.x - pos.x, goal.z - pos.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 0.3 then
					stayLeft = goal.stay
				else
					local step = math.min(d, SPEED * dt)
					pos = { x = pos.x + dx / d * step, z = pos.z + dz / d * step }
					camLook = Vector3.new(dx / d, 0, dz / d)
					hum.MoveDirection = camLook
				end
			end
			hrp.CFrame = CFrame.new(W(pos.x, 3, pos.z))
			-- what the player was shown
			local hz = hazardPart() ~= nil
			if hz and not active then
				totals.hazards += 1
				warnAt, redAt, enteredAt, wasIn = nil, nil, nil, false
			end
			active = hz
			if hz and warnAt == nil and warnPanel.Visible then warnAt = simTime end
			if hz and redAt == nil and warnPanel.Visible and string.find(warnText.Text, "MOVE!", 1, true) then redAt = simTime end
			local ring = folder:FindFirstChild("Ring")
			local isIn = false
			if ring and redAt then
				local c = ring.Position
				isIn = Vector3.new(hrp.Position.X - c.X, 0, hrp.Position.Z - c.Z).Magnitude <= ring.Size.Y / 2 + 1e-3
			end
			if isIn and not wasIn then enteredAt = simTime end
			wasIn = isIn
			if hum.PlatformStand and not wasPS then
				totals.knocks += 1
				local w = if warnAt then simTime - warnAt else -1
				local r = if redAt then simTime - redAt else -1
				local e = if enteredAt then simTime - enteredAt else -1
				totals.minWarn, totals.minRed, totals.minIn = math.min(totals.minWarn, w), math.min(totals.minRed, r), math.min(totals.minIn, e)
				if w < PROMISE_WARN - 1e-6 or r < PROMISE_RED - 2 / 30 - 1e-6 or e < PROMISE_RED - 2 / 30 - 1e-6 then totals.short += 1 end
				if not isIn then totals.outside += 1 end
				hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) -- no physics: the stumble is observed, not simulated
			end
			wasPS = hum.PlatformStand
		end
		run(150)
		frameHook = nil
		hum.MoveDirection = Vector3.new(0, 0, 0)
		for _ = 1, 200 do
			if hazardPart() == nil and not hum.PlatformStand then break end
			run(0.1)
		end
	end
	camMode = "bins"
	print(string.format("  a sorter WALKING the bay at 18 studs/s (THEME PARK and SPACE STATION, 150 s each, hazards every 6-7 s): %d hazards, %d knocks; every knock at least %.2f s after the warning, %.2f s after MOVE!, %.2f s after stepping into the ring",
		totals.hazards, totals.knocks, totals.minWarn, totals.minRed, totals.minIn))
	truthy(totals.hazards >= 20, "set-up: hazards kept coming at the walking sorter (" .. totals.hazards .. ")")
	truthy(totals.knocks >= 1, "CONTROL: a sorter who stops inside a ring long enough is still knocked (" .. totals.knocks .. ")")
	eq(totals.short, 0, string.format("no knock sooner than %.0f s after the warning, %.0f s after MOVE! or %.0f s after stepping into the ring (less two frames of sampling)",
		PROMISE_WARN, PROMISE_RED, PROMISE_RED))
	eq(totals.outside, 0, "nobody is knocked outside the drawn ring")
	hrp.CFrame = CFrame.new(W(0, 3, 0))
end

-- REVIEW-2 finding 4: a broken COSMETIC step (a Roblox-only error the emulator cannot raise, say the first time
-- a wing's scenery is built mid-shift) must never strand a knocked player on the floor or stop hazards and the
-- break. The frame used to be one pcall with the stumble's release near its end: a throw in the weather left
-- PlatformStand true for good. Each cosmetic step is guarded on its own now and the release comes first.
do
	local WingArt = mod("WingArt")
	local spot = W(0, 3, 0) -- the pick point, facing the arc: a still player there is knocked again and again (§4)
	for _ = 1, 200 do
		if hazardPart() == nil and not hum.PlatformStand then break end
		run(0.1)
	end
	hrp.CFrame = CFrame.new(spot)
	camMode = "bins"
	pinned = payload(13, true, 10)
	local function waitKnock(limit)
		local t = 0
		while not hum.PlatformStand and t < limit do
			hrp.CFrame = CFrame.new(spot)
			run(1 / 30)
			t += 1 / 30
		end
		return hum.PlatformStand
	end
	local function releaseTime(limit)
		local t = 0
		while hum.PlatformStand and t < limit do
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			run(1 / 30)
			t += 1 / 30
		end
		return if hum.PlatformStand then math.huge else t
	end
	truthy(waitKnock(40), "CONTROL: a still player on a short-lane spot is knocked")
	near(releaseTime(5), Hz.KnockSeconds, 2 / 30, "CONTROL: without a fault the stumble wears off after KnockSeconds")
	local warnedBefore = #h.warnings
	for _, method in { "updateWeather", "updatePiece", "updateCritters", "showHazard" } do
		truthy(waitKnock(40), "knocked again, then WingArt:" .. method .. " starts throwing")
		local original = WingArt[method]
		WingArt[method] = function() error("simulated: a cosmetic Roblox call failed in " .. method) end
		local rel = releaseTime(5)
		truthy(rel <= Hz.KnockSeconds + 3 / 30, string.format("... the stumble still wears off (%.2f s, KnockSeconds %.1f)", rel, Hz.KnockSeconds))
		-- the break still answers mid-shift (it books), and a booking is cancelled again
		breakBtn.Activated:Fire()
		run(0.1)
		eq(breakBtn.Text, "BREAK BOOKED", "... the BREAK button still books a break with " .. method .. " broken")
		breakBtn.Activated:Fire()
		run(0.1)
		if method ~= "showHazard" then
			-- hazards keep coming (and keep being drawn and knocking) while the scenery is broken
			truthy(waitKnock(40), "... hazards still come and knock with " .. method .. " broken")
			truthy(releaseTime(5) <= Hz.KnockSeconds + 3 / 30, "... and that stumble wears off too")
		end
		WingArt[method] = original
		for _ = 1, 3 do run(1 / 30) end
	end
	-- the frame's first step itself failing (reading the career): nothing else can run that frame, but the
	-- stumble is released before it
	do
		local EnvBands2 = mod("EnvBands")
		truthy(waitKnock(40), "knocked again, then the frame's read step (EnvBands.weights) starts throwing")
		local original = EnvBands2.weights
		EnvBands2.weights = function() error("simulated: the career read failed") end
		local rel = releaseTime(5)
		truthy(rel <= Hz.KnockSeconds + 3 / 30, string.format("... the stumble still wears off (%.2f s)", rel))
		EnvBands2.weights = original
		for _ = 1, 3 do run(1 / 30) end
	end
	local faults = 0
	for i = warnedBefore + 1, #h.warnings do
		if string.find(h.warnings[i], "DepotWings", 1, true) then faults += 1 end
	end
	truthy(faults >= 1 and faults <= 5, "each broken step warned once, not every frame (" .. faults .. " warnings)")
	-- all restored: the scene and the hazards work again
	truthy(waitKnock(40) and releaseTime(5) <= Hz.KnockSeconds + 3 / 30, "restored: knocks and their stumbles as before")
end

-- REVIEW-2 finding 3, through the real client: a reader up against the tray (0.7 studs from its edge,
-- reading the small tags, camera looking over the tray from the bin side) used to have hazards roll straight
-- through the tray and its items at their face (18 of 18). A ray from inside a fixture's margin now stops
-- where it would enter the fixture: no lane comes from beyond the tray (nor, with the tray's edge in the
-- camera's +-35 degree window, along it). With their back to the tray, facing the floor, hazards still come
-- to the same spot, and none of them crosses the tray either.
do
	for _ = 1, 200 do
		if hazardPart() == nil and not hum.PlatformStand then break end
		run(0.1)
	end
	local B = Config.Bay
	local tx0, tx1 = OX + B.TrayCentre[1] - B.TraySize[1] / 2, OX + B.TrayCentre[1] + B.TraySize[1] / 2
	local tz0, tz1 = B.TrayCentre[3] - B.TraySize[3] / 2, B.TrayCentre[3] + B.TraySize[3] / 2
	pinned = payload(9, true, 10) -- THEME PARK: the 4.4-stud beach ball and the bumper car
	local reader = W(1, 3, 2.8)
	for _, view in { { look = Vector3.new(0, 0, 1), label = "over the tray" }, { look = Vector3.new(0, 0, -1), label = "toward the floor, back to the tray" } } do
		camMode = "look"
		camLook = view.look
		local hazards, inTray, wasHz, counted, endDepth = 0, 0, false, false, 0
		frameHook = function()
			hrp.CFrame = CFrame.new(reader)
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			local hz, any = false, false
			-- on the way in the lane line is drawn (until the hazard arrives at the reader)
			local wayIn = folder:FindFirstChild("Lane") ~= nil
			for _, c in folder:GetChildren() do
				if string.sub(c.Name, 1, 7) == "Hazard_" then
					hz = true
					local p = c.Position
					if p.X > tx0 and p.X < tx1 and p.Z > tz0 and p.Z < tz1 then
						if wayIn then
							any = true
						else
							-- after it arrived at the reader (aimed up to AimJitter past them) it ends at the tray's edge
							endDepth = math.max(endDepth, math.min(p.X - tx0, tx1 - p.X, p.Z - tz0, tz1 - p.Z))
						end
					end
				end
			end
			if hz and not wasHz then hazards += 1; counted = false end
			if any and not counted then inTray += 1; counted = true end
			wasHz = hz
			-- keep idle rest off: a tiny step now and then
			hum.MoveDirection = if math.floor(simTime) % 7 == 0 then Vector3.new(0.2, 0, 0) else Vector3.new(0, 0, 0)
		end
		run(90)
		frameHook = nil
		hum.MoveDirection = Vector3.new(0, 0, 0)
		print(string.format("  a reader 0.7 studs from the tray, camera %s: %d hazards, %d drawn inside the tray's footprint on the way in; after arriving, at most %.2f studs into its edge",
			view.label, hazards, inTray, endDepth))
		eq(inTray, 0, "camera " .. view.label .. ": no hazard rolls through the tray on its way in")
		truthy(endDepth <= Hz.AimJitter + 0.6, string.format("... and one that has arrived ends at the tray's edge (%.2f studs in, the aim jitter %.1f plus a frame)", endDepth, Hz.AimJitter))
		if view.label ~= "over the tray" then
			truthy(hazards >= 6, "CONTROL: at the same spot, facing the floor, hazards come (" .. hazards .. ")")
		end
		for _ = 1, 200 do
			if hazardPart() == nil and not hum.PlatformStand then break end
			run(0.1)
		end
	end
	camMode = "bins"
	hrp.CFrame = CFrame.new(W(0, 3, 0))
end

--============================================================================ §6 a jump in career glides

do
	pinned = payload(0, false)
	run(10)
	near(Lighting.ClockTime, bandValue(CITY, "lighting", "ClockTime"), 0.05, "CONTROL: settled in the CITY DEPOT")
	local last = {}
	for _, d in folder:GetDescendants() do if d:IsA("BasePart") then last[d] = d.Transparency end end
	local worstT = 0
	local startClock = Lighting.ClockTime
	local mark2 = #lightingLog
	pinned = payload(36, false)
	frameHook = function()
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and last[d] ~= nil and d.Parent ~= nil and not string.match(d.Name, "^Hazard_")
				and d.Name ~= "Lane" and d.Name ~= "Ring" and d.Name ~= "Pigeon" and d.Name ~= "Comet" and d.Name ~= "Satellite" then
				worstT = math.max(worstT, math.abs(d.Transparency - last[d]))
			end
			if d:IsA("BasePart") then last[d] = d.Transparency end
		end
	end
	run(10)
	frameHook = nil
	near(Lighting.ClockTime, bandValue(GALAXY, "lighting", "ClockTime"), 0.05, "a jump from 0 to 36 shifts ends in the galaxy light")
	local worst = 0
	local total = bandValue(GALAXY, "lighting", "ClockTime") - startClock
	for i = mark2 + 1, #lightingLog do
		worst = math.max(worst, math.abs(lightingLog[i].clock - lightingLog[i - 1].clock) / math.abs(total))
	end
	truthy(worst <= 0.12, string.format("... gliding: no Lighting write moves more than 12%% of the way (worst %.1f%%)", worst * 100))
	truthy(worstT <= 0.06, string.format("... and no scenery part changes its transparency by more than 0.06 in a frame (worst %.3f): a cross-fade, not a cut", worstT))
end

--============================================================================ §7 the roof never hides the job

do
	pinned = payload(6, false) -- TRAIN STATION: the shed and its clock hang over the bay
	camHeight, camBack = 8, 14
	run(8)
	local function overheadShown()
		local n = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and OVERHEAD[d.Name] and d.Parent ~= nil and d.Transparency < 0.99 then n += 1 end
		end
		return n
	end
	local low = overheadShown()
	truthy(low > 10, "a sorting camera (8 studs up) sees the train shed overhead (" .. low .. " parts)")
	camHeight, camBack = 30, 20
	run(3)
	eq(overheadShown(), 0, "a camera zoomed out to 33 studs up sees no roof between it and the tags")
	camHeight, camBack = 8, 14
	run(3)
	eq(overheadShown(), low, "back down, the roof is back")
end

--============================================================================ §8 stress: career jumps and hazards every frame

-- First the worst case on purpose: a flurry through all six wings, 0.3 s apart, twenty times round. Each
-- jump leaves the last wing fading out for seconds (the glide), so without a cap every wing would be on
-- screen at once. Normal play only ever blends two; the client keeps the two strongest.
do
	local FAMILY = {
		CityRoof = "city", CitySkyline = "city", AirportRoof = "airport", AirportRoofSign = "airport", Airfield = "airport",
		TrainShed = "train", Viaduct = "train", TrainCar = "train", ParkLights = "park", ParkRides = "park",
		WheelRim = "park", WheelSpoke = "park", Gondola = "park", EarthView = "station", GalaxyView = "galaxy",
	}
	local order = { 0, 9, 3, 13, 6, 36 }
	local worstFamilies, worstParts, frames = 0, 0, 0
	for lap = 1, 20 do
		for _, shifts in order do
			pinned = payload(shifts, false)
			for _ = 1, 9 do
				frame(1 / 30)
				frames += 1
				local fam, n = {}, 0
				local parts = 0
				for _, d in folder:GetDescendants() do
					if d:IsA("BasePart") then
						parts += 1
						local f = FAMILY[d.Name]
						if f and not fam[f] then
							fam[f] = true
							n += 1
						end
					end
				end
				worstFamilies = math.max(worstFamilies, n)
				worstParts = math.max(worstParts, parts)
			end
		end
	end
	print(string.format("  flurry through all six wings 0.3 s apart (%d frames): at most %d wings' scenery on screen, peak %d parts",
		frames, worstFamilies, worstParts))
	truthy(worstFamilies <= 2, "a flurry of career jumps never shows more than two wings' scenery at once (" .. worstFamilies .. ")")
	truthy(worstParts <= Budget.MaxLocalParts, "and stays inside the parts budget (" .. worstParts .. ")")
end

do
	local seed = 20260924
	local function rnd()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
	local over = {}
	local seen = {}
	local hazardsSeen, wasHz = 0, false
	for cycle = 1, 160 do
		local shifts = math.floor(rnd() * 40)
		local running = rnd() < 0.8
		pinned = payload(shifts, running, if running then math.floor(rnd() * 30) else 0)
		local stay = if rnd() < 0.5 then 0.2 else 4
		for _ = 1, math.floor(stay * 30 + 0.5) do
			hum.MoveDirection = if math.floor(simTime) % 7 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
			frame(1 / 30)
			local m = measure("stress")
			for _, d in folder:GetDescendants() do seen[d] = true end
			for k, lim in { parts = Budget.MaxLocalParts, emitters = Budget.MaxEmitters, rate = Budget.MaxEmitterRate,
				beams = Budget.MaxBeams, trails = Budget.MaxTrails, lights = Budget.MaxLights, hazards = Budget.MaxHazards } do
				if m[k] > lim and over[k] == nil then over[k] = string.format("%s = %s at cycle %d", k, tostring(m[k]), cycle) end
			end
			local hz = hazardPart() ~= nil
			if hz and not wasHz then hazardsSeen += 1 end
			wasHz = hz
		end
	end
	local unique = 0
	for _ in seen do unique += 1 end
	print(string.format("  stress: 160 random career jumps, %d hazards; peak parts %d; %d unique instances ever under the folder", hazardsSeen, peak.parts, unique))
	truthy(hazardsSeen >= 5, "set-up: hazards flew during the stress run (" .. hazardsSeen .. ")")
	for _, k in { "parts", "emitters", "rate", "beams", "trails", "lights", "hazards" } do
		eq(over[k], nil, "stress: the " .. k .. " budget held on every frame")
	end
	truthy(unique <= 2 * Budget.MaxLocalParts + 200, "stress: pooled, nothing piles up (" .. unique .. " unique instances)")
end

--============================================================================ §9 nothing leaks, nothing reaches the server

do
	-- what the Wings client created, and where it lives now
	-- in the game now: under DepotWings (or the folder itself), under PlayerGui, or a Lighting effect.
	-- Anything else it made is pooled, out of the DataModel.
	local outside = {}
	for _, obj in created do
		if obj:IsDescendantOf(h.game) then
			local ok = obj == folder or obj:IsDescendantOf(folder) or obj:IsDescendantOf(plr.PlayerGui) or obj.Parent == Lighting
			if not ok then table.insert(outside, obj.ClassName .. " " .. obj:GetFullName()) end
		end
	end
	eq(#outside, 0, "everything the wings created lives in DepotWings, its own ScreenGui or Lighting (" .. table.concat(outside, "; ", 1, math.min(#outside, 4)) .. ")")
	local lightingMade = {}
	for _, obj in created do
		if obj.Parent == Lighting then table.insert(lightingMade, obj.ClassName .. ":" .. obj.Name) end
	end
	table.sort(lightingMade)
	eq(table.concat(lightingMade, ","), "DepthOfFieldEffect:DepotBreakFocus,Sky:DepotSky",
		"in Lighting it made only the break's focus and its Sky (it took over the server's Atmosphere and effects)")
	truthy(#created > 50, "CONTROL: the creation log saw the wings being built (" .. #created .. " instances)")
	local inBays = 0
	for _, obj in created do
		if obj.Parent ~= nil and obj:IsDescendantOf(h.workspace:FindFirstChild("Bays")) then inBays += 1 end
	end
	eq(inBays, 0, "nothing the wings made is inside a bay (the server's world is untouched)")
	local attrs = 0
	for _, root2 in { h.workspace, RS, Lighting, plr.PlayerGui } do
		for _, d in root2:GetDescendants() do
			for n in d:GetAttributes() do
				if n ~= "__counted" then attrs += 1 end
			end
		end
	end
	eq(attrs, 0, "no attribute anywhere")
	-- the sources: no remote, no attribute, no reach into the server's world
	for _, key in { "client/Wings.client", "shared/Wings", "shared/WingArt" } do
		local src = bundle[key].source
		local code = {}
		for line in string.gmatch(src .. "\n", "([^\n]*)\n") do table.insert(code, (string.gsub(line, "%-%-.*$", ""))) end
		local c = table.concat(code, "\n")
		for _, bad in { "FireServer", "InvokeServer", "SetAttribute", "ServerScriptService", "ServerStorage" } do
			eq(string.find(c, bad, 1, true), nil, key .. " never calls or names " .. bad)
		end
	end
end

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("lost-found-depot wings: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lost-found-depot wings check failed", 0)
end
