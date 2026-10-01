-- Fork Tower — the summit's crown grows rarer with summits reached. Run: luau check_forktower_crown.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- OWNER DECISION, 2026-09-30 ("take the recommended option for all"). EYECANDY.md §12 said the tower had
-- no progress across runs: every run walks the same six bands, and a long-term environment goal "would be
-- easy and safe (one more star in the summit's crown per rebirth, or a rarer crown at 5 / 10 / 25
-- rebirths), but it is a design decision for Gustav". Taken: a rarer crown at 5, 10 and 25, counted in
-- SUMMITS (Config.Env.CrownTiers), because Rebirth works from any floor every 3 s and a goal a button can
-- buy is not a goal. tests/Pacing.spec.luau measures the minutes (normal play: 23, 36, 113; the ice crown moved
-- from 10 to 8 summits in pass 2, 2026-10-01, to be the brag inside 30-45 min).
--
-- What this file holds, through the real server, HUD and Ambience client:
--   * the server counts a summit once per run, in the profile, saved, and shows it as the public
--     leaderstat "Topper" (a brag others can see);
--   * a rebirth, from the summit or from anywhere else, never counts, however often it is pressed;
--   * the count survives a rejoin;
--   * reaching a new crown says so (a notice), and the summit's crown of stars is that crown: its number
--     of stars and its colour, circling the climber.
-- Headless limits: no physics, no rendering. Frames are driven by firing RunService.RenderStepped.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower-crown", viewport = { 1280, 720 }, touch = false })
local store = h.services.DataStoreService:GetDataStore("ForkTower_v1")
local U = 7401
store:SetAsync("u_" .. U, {
	data = {
		runSeed = 4, level = 1, stage = "fork", picks = {}, slots = {}, readFloors = {}, skipped = {},
		skips = 0, rebirths = 3, bestScore = 0, bestTitle = "", redeemed = {}, passes = {}, summits = 4,
	},
})
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local tiers = Config.Env.CrownTiers
truthy(type(tiers) == "table" and #tiers >= 2, "set-up: Config.Env.CrownTiers exists")
local remotes = RS:FindFirstChild("ForkRemotes")
local NoticeEvent = remotes:FindFirstChild("Notice")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001 -- in memory: nothing flies here

local plr = h:join("Crowned", U)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
truthy(h:tryRun("client/Hud.client"), "Hud.client loads")
local okA, errA = h:tryRun("client/Ambience.client")
truthy(okA, "Ambience.client loads (" .. tostring(errA) .. ")")
local cam = h.workspace.CurrentCamera
local folder = h.workspace:FindFirstChild("ForkLocalEnv")

local function topper() local ls = plr:FindFirstChild("leaderstats"); local t = ls and ls:FindFirstChild("Topper"); return t and t.Value end
local function laneOf()
	for _, f in h.workspace:FindFirstChild("Towers"):GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end
local function frames(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 9, -22), hrp.Position)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end
local function standOn(part)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
end
local function notices(kind)
	local out = {}
	for _, msg in NoticeEvent:sentTo(plr) do
		local a = msg.args and msg.args[1]
		if type(a) == "table" and (kind == nil or a.kind == kind) then table.insert(out, a.text) end
	end
	return out
end
-- one honest run to the summit: read, the safe door, and the exit once the section could have been climbed
local function climbToSummit()
	local lane = laneOf()
	for level = 1, Config.Tower.Floors do
		local fork = lane:FindFirstChild("Fork_" .. level)
		local pad = fork:FindFirstChild("ForkPad_" .. level)
		standOn(pad)
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		prompt.PromptButtonHoldBegan:Fire(plr)
		h:advance(Config.Fork.ReadSeconds + 0.05)
		prompt.Triggered:Fire(plr)
		h:advance(0.1)
		local m1 = fork:FindFirstChild("Door_" .. level .. "_1"):GetAttribute("Marked") == true
		local marked = if m1 then 1 else 2
		local trap = if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
		fork:FindFirstChild("Door_" .. level .. "_" .. (3 - trap)):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
		h:advance(0.2)
		for _, c in lane:FindFirstChild("Section_" .. level):GetChildren() do
			if c:GetAttribute("Exit") == true then standOn(c) end
		end
		for _ = 1, 100 do
			if lane:FindFirstChild("Fork_" .. (level + 1)) ~= nil or lane:FindFirstChild("Summit") ~= nil then break end
			h:advance(0.1)
		end
	end
	return lane:FindFirstChild("Summit")
end

--======================================================================= 1. a summit counts, once

eq(topper(), 4, "the saved summit count is loaded and shown as the public leaderstat Topper")
local before = #notices()
local summit = climbToSummit()
truthy(summit ~= nil, "set-up: the climber reached the summit")
eq(topper(), 5, "reaching the summit counts one summit")
local crownNotes = {}
for i = before + 1, #notices() do
	local t = notices()[i]
	if string.find(t, tiers[2].name, 1, true) then table.insert(crownNotes, t) end
end
eq(#crownNotes, 1, "reaching the fifth summit says, once, that the next crown is won (" .. tiers[2].name .. ")")

--======================================================================= 2. the crown at the summit is that crown

do
	standOn(summit:FindFirstChild("SummitPad"))
	frames(8)
	local stars, farthest, colourOk = 0, 0, true
	local want = tiers[2].color
	for _, d in folder:GetChildren() do
		if d.Name == "CrownStar" and d.Transparency < 0.2 then
			stars += 1
			farthest = math.max(farthest, (d.Position - hrp.Position).Magnitude)
			local c = d.Color
			if math.abs(c.R * 255 - want[1]) > 1.5 or math.abs(c.G * 255 - want[2]) > 1.5 or math.abs(c.B * 255 - want[3]) > 1.5 then
				colourOk = false
			end
		end
	end
	eq(stars, tiers[2].stars, "with five summits the summit's crown has " .. tiers[2].name .. "'s stars")
	truthy(colourOk, "in " .. tiers[2].name .. "'s colour")
	truthy(farthest <= 6, string.format("circling the climber (farthest star %.1f studs from the root)", farthest))
end

--======================================================================= 3. a rebirth never counts

do
	remotes:FindFirstChild("Rebirth"):simulateFireServer(plr) -- from the summit
	h:advance(Config.Limits.RebirthCooldown + 0.5)
	eq(topper(), 5, "a rebirth from the summit does not count as a summit")
	for _ = 1, 4 do -- from floor 1, as fast as the server allows
		remotes:FindFirstChild("Rebirth"):simulateFireServer(plr)
		h:advance(Config.Limits.RebirthCooldown + 0.1)
	end
	eq(topper(), 5, "four more rebirths from floor 1 count nothing either")
end

--======================================================================= 4. it is saved

do
	h:leave(plr)
	char:Destroy()
	h:advance(2)
	local rec = store:GetAsync("u_" .. U)
	eq(rec and rec.data and rec.data.summits, 5, "the summit count is saved with the profile")
	-- no Robux in v1 (owner decision 2026-09-30, Codes.spec): the dead gamepass field is no longer saved
	truthy(rec and rec.data and rec.data.passes == nil, "the profile saves no gamepass field (no Robux cost in v1)")
	plr = h:join("Crowned", U)
	h:advance(1)
	eq(topper(), 5, "and a rejoin shows it again")
end

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("fork tower crown: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower crown check failed", 0)
end
