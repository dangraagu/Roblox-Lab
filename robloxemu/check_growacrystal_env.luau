-- Grow a Crystal — the living cavern, driven through the REAL server, HUD and Grotto client.
-- Run: luau check_growacrystal_env.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The pure modules (EnvBands, Rest, Visitors, Grotto) are unit-tested in grow-a-crystal/tests. This
-- checks the GLUE no unit test can see: that src/client/Grotto.client.luau takes over the server's
-- lighting without a jump, follows the chambers the SERVER says the player owns (bought through the
-- real Buy remote), fills the cavern in as they are bought, glides instead of cutting, plays the harvest
-- burst and the Legendary/Mythic beam from the server's own result, flies rare harmless visitors, lets a
-- relaxing player alone, never touches the character, never fires a remote, and stays inside the mobile
-- budget. It also MEASURES the budgets and the visitor rarity that EYECANDY.md reports.
--
-- Headless limits, stated: nothing renders and there is no physics. Frames are driven by firing
-- RunService.RenderStepped; the character does not move unless this file moves it. Whether any of it
-- LOOKS right is on the Studio list (EYECANDY.md §8).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and b ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})

local ME = 7777
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
-- Rich enough to buy all eight chambers. Sockets 2 and 3 hold mature LEGENDARY seeds (planted in 1970):
-- one is harvested at chamber 1, the other at chamber 8 while a visitor is in flight (the budget's peak).
store:SetAsync("u_" .. ME, {
	data = {
		dust = 500000, seeds = { [1] = 3 }, chambers = 1, luckLevel = 0, growthLevel = 0,
		plants = { [2] = { tier = 5, at = 1 }, [3] = { tier = 5, at = 1 } },
		codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {},
	},
})

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end

assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local Grotto = mod("Grotto")
local Cavern = mod("Cavern")
local Rng = mod("Rng")
local bands = Config.Env.Bands
local Budget = Config.Budget

-- the server's lighting BEFORE any client runs (Fx.applyLighting(Cozy))
local Lighting = h.Lighting
local serverL = {
	ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd,
	Ambient = Lighting.Ambient, FogColor = Lighting.FogColor,
}
local serverAtmos = Lighting:FindFirstChild("FxAtmosphere")
local serverBloom = Lighting:FindFirstChild("FxBloom")
local serverDoF = Lighting:FindFirstChild("FxDoF")
local serverDensity = serverAtmos and serverAtmos.Density
local serverBloomI = serverBloom and serverBloom.Intensity
local serverFar = serverDoF and serverDoF.FarIntensity

-- the server's replicated surface, recorded before the client exists; every call the CLIENT makes counts
local remotes = RS:FindFirstChild("CrystalRemotes")
local remoteNames = {}
for _, r in remotes:GetChildren() do table.insert(remoteNames, r.Name) end
table.sort(remoteNames)
local serverCalls, ours = 0, 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end
do
	local redeem = remotes:FindFirstChild("Redeem")
	local inner = redeem.OnServerInvoke
	redeem.OnServerInvoke = function(...)
		serverCalls += 1
		return inner(...)
	end
end

h.game:GetService("RunService"):setIsServer(false) -- from here on the scripts run are client scripts

local plr = h:join("Gardener", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
truthy(hrp ~= nil and hum ~= nil, "the gardener has a root part and a humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)
-- sentinels: the client must never write these (no knock-down hazards in this game)
local SENTINEL_V = Vector3.new(0, 0, 0)
hrp.AssemblyLinearVelocity = SENTINEL_V
hum.PlatformStand = false

-- the plot origin, from the server's own socket (what the client must find by itself)
local sock1 = h.workspace:FindFirstChild("Socket_" .. ME .. "_1", true)
local lp1 = Cavern.socketPos(Config, 1, Rng)
local ORIGIN = sock1.Position - Vector3.new(lp1.x, lp1.y, lp1.z)

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okG, errG = h:tryRun("client/Grotto.client")
truthy(okG, "Grotto.client loads (" .. tostring(errG) .. ")")

local folder = h.workspace:FindFirstChild("CrystalLocalGrotto")
truthy(folder ~= nil, "the client made its local folder in the workspace (not in the plot)")
local g = plr.PlayerGui:FindFirstChild("CrystalGrotto")
local root = g and g:FindFirstChild("Root")
local chip = root and root:FindFirstChild("BandChip")
local relaxBtn = root and root:FindFirstChild("RelaxButton")
local card = root and root:FindFirstChild("BandCard")
local cardSub = root and root:FindFirstChild("BandCardSub")
truthy(chip and relaxBtn and card and cardSub, "chip, relax button and title card exist")

-- The State push that carried the player's profile was sent before the client connected (as in Roblox,
-- where a join's first push can beat the client script). The HUD shows nothing until the next push,
-- and so does the cavern: re-send the current state the way the next pushState would.
local State = remotes:FindFirstChild("State")
local function resend()
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	if rec then State.OnClientEvent:Fire(table.unpack(rec.args, 1, rec.args.n)) end
end

local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local simTime = 0
local cards = {}
local lastCard = ""
local flashes = 0
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 9, -14), hrp.Position + Vector3.new(0, 4, 20))
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text .. " | " .. cardSub.Text)
	end
	for _, gg in plr.PlayerGui:GetChildren() do
		if gg.Name == "FxFlash" and not gg:GetAttribute("__counted") then
			gg:SetAttribute("__counted", true)
			flashes += 1
		end
	end
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each and each(i) == false then return end
	end
end

-- budget sampling over the whole run
local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, where = "" }
local function measure(where)
	local parts, emitters, rate, lights = 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 end
		if d.ClassName == "ParticleEmitter" and d.Enabled ~= false then
			emitters += 1
			rate += d.Rate or 0
		end
		if d.ClassName == "PointLight" and (d.Brightness or 0) > 0 then lights += 1 end
	end
	if parts > peak.parts then peak.parts = parts; peak.where = where end
	peak.emitters = math.max(peak.emitters, emitters)
	peak.rate = math.max(peak.rate, rate)
	peak.lights = math.max(peak.lights, lights)
	return parts, emitters, rate, lights
end

local function color3(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local function colorNear(c, t, tol)
	return c ~= nil and math.abs(c.R * 255 - t[1]) <= tol and math.abs(c.G * 255 - t[2]) <= tol and math.abs(c.B * 255 - t[3]) <= tol
end

--=============================================================== 1. takeover from the server, no jump
resend()
run(0.5, 1 / 30)
near(Lighting.ClockTime, serverL.ClockTime, 1e-6, "ClockTime is the server's (0: no sun underground)")
near(Lighting.Brightness, serverL.Brightness, 0.02, "Brightness starts at the server's Cozy value")
near(Lighting.FogEnd, serverL.FogEnd, 0.5, "FogEnd starts at the server's Cozy value")
truthy(Lighting.Ambient == serverL.Ambient or (math.abs(Lighting.Ambient.R - serverL.Ambient.R) < 0.01
	and math.abs(Lighting.Ambient.G - serverL.Ambient.G) < 0.01 and math.abs(Lighting.Ambient.B - serverL.Ambient.B) < 0.01),
	"Ambient starts at the server's Cozy value")
local atmos = Lighting:FindFirstChild("FxAtmosphere")
eq(atmos, serverAtmos, "the client reuses the server's Atmosphere (no second one stacked on it)")
near(atmos.Density, serverDensity, 0.005, "Atmosphere density starts at the server's")
near(Lighting:FindFirstChild("FxBloom").Intensity, serverBloomI, 0.02, "Bloom starts at the server's (the geode pulse adds at most 1 % here)")
near(Lighting:FindFirstChild("FxDoF").FarIntensity, serverFar, 0.005, "depth of field starts at the server's")
local nAtmos = 0
for _, c in Lighting:GetChildren() do if c.ClassName == "Atmosphere" then nAtmos += 1 end end
eq(nAtmos, 1, "exactly one Atmosphere")

--=============================================================== 2. the first card is quiet
run(1, 1 / 30)
truthy(#cards >= 1 and string.find(cards[1], "SUNKEN GROTTO", 1, true) ~= nil, "a new player is told where they are (" .. tostring(cards[1]) .. ")")
eq(flashes, 0, "without a fanfare")
truthy(string.find(chip.Text, bands[1].name, 1, true) ~= nil, "the chip names the first band (" .. chip.Text .. ")")
truthy(string.find(chip.Text, "Chamber " .. bands[2].from, 1, true) ~= nil, "and the chamber that opens the next")

--=============================================================== 3. harvest burst + Legendary beam
local sent0 = #State:sentTo(plr)
local function socketPart(id) return h.workspace:FindFirstChild("Socket_" .. ME .. "_" .. id, true) end
local function harvest(id)
	local s = socketPart(id)
	local c = s and s:FindFirstChild("Crystal")
	local cd = c and c:FindFirstChildOfClass("ClickDetector")
	if cd then cd.MouseClick:Fire(plr) end
	return cd ~= nil
end
local flashesBefore = flashes
truthy(harvest(2), "the Legendary crystal on socket 2 can be harvested")
truthy(#State:sentTo(plr) > sent0, "the harvest pushed a new State")
local lh = State:sentTo(plr)[#State:sentTo(plr)].args[1].lastHarvest
local tierColor = color3(Config.TierColor[lh.tier])
run(0.1, 1 / 30)
local shards, ring, core, halo, light = 0, nil, nil, nil, nil
for _, d in folder:GetChildren() do
	if d.Name == "Shard" then shards += 1 end
	if d.Name == "HarvestRing" then ring = d end
	if d.Name == "BeamCore" then core = d end
	if d.Name == "BeamHalo" then halo = d end
end
local rule = Grotto.burst(lh.tier, Config.Env.Harvest)
eq(shards, rule.shards, "the burst throws the tier's shards (" .. Config.Tiers[lh.tier] .. ")")
truthy(ring ~= nil, "and a ring")
truthy(core ~= nil and halo ~= nil, "and a beam of light (Legendary and Mythic only)")
if halo then truthy(colorNear(halo.Color, Config.TierColor[lh.tier], 2), "the beam is the tier's colour") end
if core then
	light = core:FindFirstChild("BeamLight")
	truthy(light ~= nil and light.Brightness > 0, "the beam lights the cavern while it lasts")
	local top = ORIGIN.Y + Cavern.Const.CEIL_UNDER
	near(core.Position.Y + core.Size.X / 2, top, 0.6, "the beam reaches the ceiling")
	local sp = socketPart(2).Position
	near(core.Position.X, sp.X, 0.01, "the beam stands on the harvested socket (x)")
	near(core.Position.Z, sp.Z, 0.01, "the beam stands on the harvested socket (z)")
end
truthy(flashes > flashesBefore, "a Legendary harvest flashes the screen")
truthy(string.find(lastCard, rule.card, 1, true) ~= nil, "and names what it is (" .. lastCard .. ")")
measure("chamber 1, harvest burst")
run(3, 1 / 30)
local left = 0
for _, d in folder:GetChildren() do
	if d.Name == "Shard" or d.Name == "HarvestRing" or d.Name == "BeamCore" or d.Name == "BeamHalo" then left += 1 end
end
eq(left, 0, "3 s later the burst and the beam are gone (pooled, not left behind)")
if light then eq(light.Brightness, 0, "and the beam's light is off") end

-- chamber 1, settled (the first row of EYECANDY.md §6)
do
	local parts, emitters, rate, lights = measure("chamber 1")
	print(string.format("  chamber 1  %-20s parts %3d  emitters %d (%4.1f/s)  lights %d", bands[1].name, parts, emitters, rate, lights))
end

--=============================================================== 4. no visitors in the first band
local launches = 0
local inFlight, maxInFlight = 0, 0
local function countVisitorsNow()
	local bats, moths = 0, 0
	for _, d in folder:GetChildren() do
		if d.Name == "Bat_Body" then bats += 1 end
		if d.Name == "Moth" then moths += 1 end
	end
	return bats, moths
end
local critterMoths = 0
run(300, 0.1, function()
	local _, moths = countVisitorsNow()
	critterMoths = math.max(critterMoths, moths)
end)
local _, mothsNow = countVisitorsNow()
truthy(critterMoths <= 2, "5 minutes in the first band: only its 2 ambient moths, no moth swirl (" .. critterMoths .. ")")

--=============================================================== 5. every chamber, bought through the real server
local Buy = remotes:FindFirstChild("Buy")
local rows = {}
local function pieceCounts()
	local counts = {}
	for _, d in folder:GetChildren() do
		local id = nil
		if string.match(d.Name, "^Worm_") then id = "glowworms"
		elseif string.match(d.Name, "^Giant_") then id = "shrooms"
		elseif string.match(d.Name, "^Fall_") then id = "waterfall"
		elseif string.match(d.Name, "^Prism_") then id = "geodeHeart"
		elseif string.match(d.Name, "^Seam_") then id = "seams"
		elseif string.match(d.Name, "^Shimmer_") then id = "poolShimmer" end
		if id then counts[id] = (counts[id] or 0) + 1 end
	end
	return counts
end
local layout = Grotto.layout(Config, Rng, Cavern)
local function expectedCounts(c)
	local w = EnvBands.weights(bands, c)
	local pw = {}
	for i, b in bands do
		for _, id in b.pieces do pw[id] = math.min(1, (pw[id] or 0) + (w[i] or 0)) end
	end
	local out = {}
	for id, list in layout.pieces do
		local n = #list
		local k = 0
		for i = 1, n do
			if math.clamp((pw[id] or 0) * n - (i - 1), 0, 1) > 0.001 then k += 1 end
		end
		out[id] = k
	end
	return out
end

-- A purchase must GLIDE. Measured on the continuous values (Brightness, FogEnd): no single frame may
-- move more than 10 % of the whole change. A hard cut would be 100 %; a 1.2 s half-life written at most
-- 10 times a second moves 7.4 % of what is left per write at 30 fps (every 4th frame, 0.133 s). Colours
-- are written as whole 0-255 steps, so Ambient is held to the same 10 % or one colour step.
local glide = { worst = 0, worstAmbient = 0, what = "" }
for c = 2, Config.Economy.MaxChambers do
	local b0 = { Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd }
	local last = { Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd }
	local maxStep = { Brightness = 0, FogEnd = 0 }
	local ambBefore, lastA, maxA = Lighting.Ambient, Lighting.Ambient, 0
	local sentBefore = serverCalls
	Buy:simulateFireServer(plr, "chamber", nil)
	ours += serverCalls - sentBefore
	h:advance(0.05)
	-- 12 s: ten half-lives, so the look has settled to within 0.1 % of the new one
	run(12, 1 / 30, function()
		for k in maxStep do
			maxStep[k] = math.max(maxStep[k], math.abs(Lighting[k] - last[k]))
			last[k] = Lighting[k]
		end
		local a = Lighting.Ambient
		maxA = math.max(maxA, math.abs(a.R - lastA.R), math.abs(a.G - lastA.G), math.abs(a.B - lastA.B))
		lastA = a
		measure("seam into chamber " .. c)
	end)
	for k in maxStep do
		local total = math.abs(Lighting[k] - b0[k])
		if total > 1e-3 and maxStep[k] / total > glide.worst then
			glide.worst = maxStep[k] / total
			glide.what = k .. " on chamber " .. c
		end
	end
	local a1 = Lighting.Ambient
	local totalA = math.max(math.abs(a1.R - ambBefore.R), math.abs(a1.G - ambBefore.G), math.abs(a1.B - ambBefore.B))
	truthy(maxA <= math.max(0.10 * totalA, 1.01 / 255), string.format("chamber %d: Ambient glides (largest frame step %.1f of a %.1f colour-step change)", c, maxA * 255, totalA * 255))
	-- the look matches the band blend the server's chamber count asks for
	local want = EnvBands.sample(bands, c, "lighting")
	near(Lighting.Brightness, want.Brightness, 0.01, "chamber " .. c .. ": Brightness is the band blend")
	truthy(colorNear(Lighting.Ambient, want.Ambient, 1.5), "chamber " .. c .. ": Ambient is the band blend")
	near(Lighting.FogEnd, want.FogEnd, 0.5, "chamber " .. c .. ": FogEnd is the band blend")
	local idx = EnvBands.indexAt(bands, c)
	truthy(string.find(chip.Text, bands[idx].name, 1, true) ~= nil, "chamber " .. c .. ": the chip names " .. bands[idx].name .. " (" .. chip.Text .. ")")
	local got, exp = pieceCounts(), expectedCounts(c)
	for id, n in exp do
		eq(got[id] or 0, n, "chamber " .. c .. ": " .. id .. " shows " .. n .. " elements")
	end
	local parts, emitters, rate, lights = measure("chamber " .. c)
	table.insert(rows, string.format("  chamber %d  %-20s parts %3d  emitters %d (%4.1f/s)  lights %d", c, bands[idx].name, parts, emitters, rate, lights))
end
for _, r in rows do print(r) end
print(string.format("  worst single-frame step on a purchase: %.1f %% of the change (%s)", glide.worst * 100, glide.what))
truthy(glide.worst > 0 and glide.worst <= 0.10, "every purchase GLIDES: no frame moves Brightness or FogEnd more than 10 % of the change")

-- the cards that came with the purchases
local all = table.concat(cards, " || ")
truthy(string.find(all, "Glow-worms are waking up", 1, true) ~= nil, "chamber 2 teases the glow-worms")
truthy(string.find(all, "GLOW-WORM HOLLOW", 1, true) ~= nil, "chamber 3 names Glow-worm Hollow")
truthy(string.find(all, "MUSHROOM TERRACES", 1, true) ~= nil, "chamber 5 names Mushroom Terraces")
truthy(string.find(all, "WATERFALL CHAMBER", 1, true) ~= nil, "chamber 7 names the Waterfall Chamber")
truthy(string.find(all, "HEART OF THE GEODE", 1, true) ~= nil, "chamber 8 names the Heart of the Geode")
truthy(flashes >= 2, "the last band arrives with a fanfare (flashes " .. flashes .. ")")
truthy(string.find(chip.Text, "every chamber open", 1, true) ~= nil, "with every chamber open the chip says so (" .. chip.Text .. ")")

--=============================================================== 6. visitors: rare, harmless, above every head
local function groundAt(z)
	local C = Cavern.Const
	if z < 0 then return 0 end
	if z >= C.PITCH * C.G then return 21 end
	local cc = math.floor(z / C.PITCH)
	if cc >= C.G - 1 then return C.RISE * cc end -- the top terrace has no treads
	local r = z - C.PITCH * cc
	if r >= 11 then return C.RISE * cc + 3 end
	if r >= 9 then return C.RISE * cc + 1.5 end
	return C.RISE * cc
end
local visitorLow = math.huge
local visitorOutside = nil
local wasBats, wasMoths = 0, 0
local launchTimes = {}
local burstDuringVisitor = false
local VISIT_MINUTES = 20
run(VISIT_MINUTES * 60, 0.1, function()
	local bats, moths = countVisitorsNow()
	-- a flock appears as 6 bats at once, or a swirl as 10 moths on top of the ambient ones
	local batFlock = bats >= 6 and wasBats < 6
	local mothFlock = moths >= 10 and wasMoths < 10
	if batFlock or mothFlock then
		launches += 1
		table.insert(launchTimes, simTime)
		if not burstDuringVisitor then
			-- the budget's peak: a Legendary burst while a flock flies in the richest band
			burstDuringVisitor = harvest(3)
		end
	end
	if (bats >= 6 and moths >= 10) then maxInFlight = 2 end
	wasBats, wasMoths = bats, moths
	for _, d in folder:GetChildren() do
		if d.Name == "Bat_Body" or d.Name == "Moth" then
			local lp = d.Position - ORIGIN
			local head = groundAt(lp.Z) + 5
			visitorLow = math.min(visitorLow, lp.Y - head)
			local inHole = math.abs(lp.X) < 14 and lp.Z > 112 and lp.Z < 126
			if math.abs(lp.X) > 32 or lp.Z < -14 or lp.Z > 134 or (lp.Y > 44 and not inHole) then
				visitorOutside = visitorOutside or string.format("%s at (%.1f, %.1f, %.1f)", d.Name, lp.X, lp.Y, lp.Z)
			end
		end
	end
	measure("chamber 8, flock + burst")
end)
local perMin = launches / VISIT_MINUTES
print(string.format("  visitors: %d in %d simulated minutes (%.2f/min, one per %.0f s)", launches, VISIT_MINUTES, perMin, VISIT_MINUTES * 60 / math.max(1, launches)))
truthy(launches >= 6 and launches <= 11, "about one visitor every 2-3 minutes through the real client (" .. launches .. " in 20 min)")
eq(maxInFlight, 0, "never a bat swoop and a moth swirl at the same time")
truthy(burstDuringVisitor, "a harvest during a flight still bursts (the peak was measured)")
eq(visitorOutside, nil, "every visitor and critter stays inside the cavern (or goes up the light shaft)")
print(string.format("  lowest moth or bat over a standing head: %.1f studs", visitorLow))
truthy(visitorLow >= 3.5, string.format("nothing flies lower than 3.5 studs above a standing head (lowest %.1f)", visitorLow))
local gapsOk = true
for i = 2, #launchTimes do
	local gap = launchTimes[i] - launchTimes[i - 1]
	if gap < Config.Visitors.IntervalMin - 1 or gap > Config.Visitors.IntervalMax + 1 then gapsOk = false end
end
truthy(gapsOk, "launch-to-launch gaps stay inside IntervalMin..IntervalMax")

--=============================================================== 7. relax
local restLaunches = 0
local restFar = nil
hum.MoveDirection = Vector3.new(0, 0, 0)
relaxBtn.Activated:Fire()
run(0.5, 1 / 30)
eq(hum.Sit, true, "Relax sits the character down")
truthy(string.find(chip.Text, "Relaxing", 1, true) ~= nil, "the chip says the player is relaxing (" .. chip.Text .. ")")
truthy(string.find(relaxBtn.Text, "Back", 1, true) ~= nil, "the button offers the way back")
local restStart = simTime
wasBats, wasMoths = 0, 0
local startBats, startMoths = countVisitorsNow()
wasBats, wasMoths = startBats, startMoths
run(10 * 60, 0.1, function()
	local bats, moths = countVisitorsNow()
	if (bats >= 6 and wasBats < 6) or (moths >= 10 and wasMoths < 10) then restLaunches += 1 end
	wasBats, wasMoths = bats, moths
end)
restFar = Lighting:FindFirstChild("FxDoF").FarIntensity
eq(restLaunches, 0, "10 minutes of relaxing: no visitor comes")
near(restFar, 0.35, 0.02, "the view is softened (depth of field)")
eq(hum.Sit, true, "still sitting")
-- any movement wakes
hum.MoveDirection = Vector3.new(1, 0, 0)
run(1, 1 / 30)
eq(hum.Sit, false, "moving ends the rest and stands the character up")
truthy(string.find(chip.Text, "Relaxing", 1, true) == nil, "the chip is back to the cavern")
hum.MoveDirection = Vector3.new(0, 0, 0)
run(4, 1 / 30)
near(Lighting:FindFirstChild("FxDoF").FarIntensity, bands[#bands].depthOfField.FarIntensity, 0.02, "and the view sharpens again")
-- the visitor clock was frozen, not reset: the next launch comes within one interval of play
local nextLaunch = nil
local playT = 0
wasBats, wasMoths = countVisitorsNow()
run(Config.Visitors.IntervalMax + 5, 0.1, function()
	playT += 0.1
	local bats, moths = countVisitorsNow()
	if (bats >= 6 and wasBats < 6) or (moths >= 10 and wasMoths < 10) then
		nextLaunch = playT
		return false
	end
	wasBats, wasMoths = bats, moths
end)
truthy(nextLaunch ~= nil and nextLaunch <= Config.Visitors.IntervalMax,
	"after a 10-minute rest the next visitor comes within one interval of PLAY (" .. tostring(nextLaunch) .. " s)")

-- pressed mid-air: queued, taken on landing
hum.FloorMaterial = Enum.Material.Air
relaxBtn.Activated:Fire()
run(0.2, 1 / 30)
truthy(hum.Sit ~= true, "Relax does not sit a player in mid-air")
truthy(string.find(relaxBtn.Text, "…", 1, true) ~= nil, "it is queued (" .. relaxBtn.Text .. ")")
hum.FloorMaterial = Enum.Material.Slate
run(0.5, 1 / 30)
eq(hum.Sit, true, "and taken on landing")
relaxBtn.Activated:Fire()
run(0.3, 1 / 30)
eq(hum.Sit, false, "pressing again stands up")

--=============================================================== 8. budgets
print(string.format("  PEAK local parts %d (%s), emitters %d, particles/s %.1f, lights %d",
	peak.parts, peak.where, peak.emitters, peak.rate, peak.lights))
truthy(peak.parts <= Budget.MaxLocalParts, "local parts within budget (" .. peak.parts .. " <= " .. Budget.MaxLocalParts .. ")")
truthy(peak.emitters <= Budget.MaxWeatherEmitters, "at most MaxWeatherEmitters emitters on (" .. peak.emitters .. ")")
truthy(peak.rate <= Budget.MaxEmitterRate + 1e-6, "particles per second within budget (" .. peak.rate .. ")")
truthy(peak.lights <= Budget.MaxLights, "lights within budget (" .. peak.lights .. ")")

--=============================================================== 9. what the client must never do
eq(serverCalls - ours, 0, "the client fired no remote and invoked nothing")
local after = {}
for _, r in remotes:GetChildren() do table.insert(after, r.Name) end
table.sort(after)
eq(table.concat(after, ","), table.concat(remoteNames, ","), "the client added no remote")
eq(hrp.AssemblyLinearVelocity, SENTINEL_V, "the client never wrote the character's velocity (no knock-downs)")
eq(hum.PlatformStand, false, "and never tripped it")
local bad = nil
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") then
		if d.CanCollide ~= false or d.CanQuery ~= false or d.CanTouch ~= false or d.Anchored ~= true then
			bad = bad or d.Name
		end
	end
end
eq(bad, nil, "every client part is anchored and non-collidable, non-queryable, non-touchable")
local leaked = nil
local ART = { "^Worm_", "^Giant_", "^Fall_", "^Prism_", "^Seam_", "^Shimmer_", "^Bat_", "^Moth$", "^Wisp$", "^Shard$",
	"^HarvestRing$", "^Beam", "^Weather_" }
for _, d in h.workspace:FindFirstChild("Plots"):GetDescendants() do
	for _, pat in ART do
		if string.match(d.Name, pat) then leaked = leaked or d:GetFullName() end
	end
end
eq(leaked, nil, "nothing the client built went into the server's plot folders")
local src = require("./build/grow-a-crystal")
for _, key in { "client/Grotto.client", "shared/CavernArt" } do
	local s = src[key].source
	for _, call in { "FireServer", "InvokeServer", "SetAttribute", "FireAllClients" } do
		truthy(string.find(s, call, 1, true) == nil, key .. " never calls " .. call)
	end
end
-- everything is inside our own plot
local outside = nil
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") and d.Parent ~= nil then
		local lp = d.Position - ORIGIN
		if math.abs(lp.X) > 40 or lp.Z < -20 or lp.Z > 140 or lp.Y < -4 or lp.Y > 52 then
			outside = outside or string.format("%s at (%.1f, %.1f, %.1f)", d.Name, lp.X, lp.Y, lp.Z)
		end
	end
end
eq(outside, nil, "every client part is inside the player's own cavern")

--=========================================================================================== done
print("")
eq(#h.warnings, 0, "no warnings (a frame error would warn and stop the visuals)")
for _, w in h.warnings do print("  warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal env: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal env check failed", 0) end
