-- +1 Jump Every Step — a returning climber who is ALREADY in space joins a server.
-- Run: luau check_plus1_sky_rejoin.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- What a real join looks like to Sky.client.luau: PlayerScripts start before the character exists;
-- the character is then created on the start pad and, a frame later, the server moves it to the
-- platform the player last earned (robloxemu/SPAWN-ORDER.md). So for a frame or two the client sees
-- a space climber standing at the temple. Three things must hold:
--   * no "TEMPLE GROUNDS" card flashes up for a player who is not at the temple;
--   * no "YOU REACHED SPACE!" fanfare (flash + FOV punch) for a climb finished in an earlier session —
--     just a quiet card saying where they are;
--   * the sky glides from the server's daytime preset to night in space, it does not cut.

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
	bundle = require("./build/plus1-jump"),
	name = "plus1-jump",
	viewport = { 1280, 720 },
	touch = false,
})

local TIER, IDX = 90, 3
local store = h.services.DataStoreService:GetDataStore("Plus1Jump_v1")
store:SetAsync("u_777", {
	data = { frontierTier = TIER, frontierIdx = IDX, jumpPower = 540, rebirths = 0,
		bestTier = TIER, redeemed = {}, passes = {} },
})

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local bands = Config.Env.Bands
local orbit = bands[EnvBands.indexOf(bands, Config.Env.SpaceBandId)]
local Lighting = h.Lighting
local startClock = Lighting.ClockTime

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false) -- from here on the scripts under test are client scripts (FxClient acts)

local plr = h:join("Spacer", 777)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads before the character exists (" .. tostring(errSky) .. ")")

local cam = h.workspace.CurrentCamera
local skyGui = plr.PlayerGui:FindFirstChild("Plus1Sky")
local card = skyGui:FindFirstChild("Root"):FindFirstChild("BandCard")
local cards = {}
local lastCard = ""
local flashes = 0
local hrp = nil
local function frame(dt)
	if hrp then cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position) end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			flashes += 1
		end
	end
end

-- a second of frames with no character yet: nothing breaks, nothing is announced
for _ = 1, 30 do frame(1 / 30) end
eq(#cards, 0, "no card before there is a character")

local char = h.Players:simulateSpawn(plr, h.workspace)
hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)

local platform = h.workspace:FindFirstChild("Tower"):FindFirstChild("P_" .. TIER .. "_" .. IDX)
truthy(platform ~= nil, "the server built the climber's platform")
local placed = hrp.Position
near(placed.Y, platform.Position.Y + 4, 0.5, "the server placed the climber on their own platform (spawn order intact)")

-- the frames a client can see before that placement: the climber on the start pad
hrp.CFrame = CFrame.new(0, Config.Tower.BaseY + 4, 0)
for _ = 1, 3 do frame(1 / 30) end
hrp.CFrame = CFrame.new(placed)

local prev, worst = Lighting.ClockTime, 0
for _ = 1, 8 * 30 do
	frame(1 / 30)
	local v = Lighting.ClockTime
	if math.abs(v - prev) > worst then worst = math.abs(v - prev) end
	prev = v
end

print("  cards shown: " .. (if #cards > 0 then table.concat(cards, " | ") else "(none)"))
local templeCard, fanfare, quiet = false, false, false
for _, t in cards do
	if string.find(t, "TEMPLE", 1, true) then templeCard = true end
	if string.find(t, "YOU REACHED SPACE", 1, true) then fanfare = true end
	if string.find(t, string.upper(orbit.name), 1, true) then quiet = true end
end
eq(templeCard, false, "no TEMPLE GROUNDS card for a climber who is in space")
eq(fanfare, false, "no 'YOU REACHED SPACE!' fanfare for a climb finished in an earlier session")
eq(flashes, 0, "and no celebration flash")
truthy(quiet, "a quiet card says where they are (" .. orbit.name .. ")")
eq(#cards, 1, "exactly one card")

local total = math.abs(orbit.lighting.ClockTime - startClock)
print(string.format("  join glide: ClockTime %.2f -> %.2f, largest single write %.3f (%.0f%%)", startClock, Lighting.ClockTime, worst, worst / total * 100))
truthy(worst <= total * 0.15, "the sky glides from day to space on join (no write over 15% of the change)")
near(Lighting.ClockTime, orbit.lighting.ClockTime, 0.05, "and arrives at night in space")

-- climbing on up into the next band during play DOES announce, and a new crossing into space would
-- celebrate: prove the fanfare path is alive by respawning low and climbing back into space
local deep = bands[EnvBands.indexOf(bands, "deep")]
hrp.CFrame = CFrame.new(placed.X, h:_require(RS:FindFirstChild("Progression")).yAtProgress(deep.from + 5, Config.Tower) + 3.5, placed.Z)
for _ = 1, 4 * 30 do frame(1 / 30) end
truthy(string.find(cards[#cards] or "", string.upper(deep.name), 1, true) ~= nil,
	"climbing into the next band during play announces it (" .. tostring(cards[#cards]) .. ")")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1 sky rejoin: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1 sky rejoin check failed", 0)
end
