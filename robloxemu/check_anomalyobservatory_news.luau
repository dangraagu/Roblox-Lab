-- anomaly-observatory — on a phone, news for the break is never lost. Run: luau check_anomalyobservatory_news.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- (review 2026-09-30, finding 4) On a phone the sky writes nothing over the hall that the player did not
-- ask for (review 2026-09-24): its news waits for the next break, and the break button carries a steady
-- highlight meanwhile. The join tip ("the sky changes as your Day grows") is the only text that tells a
-- phone player the sky follows the Day. The fix round kept ONE piece of pending news: the first band
-- (Day 4, 0.9 min for a normal player) overwrote the join tip, and a wrong call before the first break
-- then cleared the band and with it the only invitation. The reviewer measured it on 640x300 touch: the
-- highlight off after the wrong call, and the first break's caption without the tip.
--
-- Played through the real server and both client scripts on that phone, one fresh join:
--   1. three right calls (a new band arrives: the tip AND the band are waiting), then a wrong call (the
--      band is gone again): the button is STILL highlighted, because the tip has not been seen;
--   2. three right calls (the band again): the first break carries the join tip; the button is still
--      highlighted afterwards, because the band has not been seen;
--   3. the next break names the band; after it nothing is pending and the button is back to normal;
--   4. the highlight never blinks (it changes colour only when news arrives or is seen).

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")
local Responsive = require("../anomaly-observatory/src/shared/Responsive")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local W, H = 640, 300
assert(Responsive.layout(W, H, true).compact, "640x300 touch is a compact (phone) layout")
local h = Harness.new({ bundle = require("./build/anomaly-observatory"), name = "anomaly-observatory", viewport = { W, H }, touch = true })
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("PhoneNews", 4040)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local o = NightSky.hallOrigin(Config.Sky.Hall, tonumber(zone:GetAttribute("Index")))
local cam = h.workspace.CurrentCamera
local walkCam = CFrame.lookAt(Vector3.new(o.x, o.y + 8, o.z + 6), Vector3.new(o.x, o.y + 6, o.z - 80))
local skyGui = plr.PlayerGui:FindFirstChild("ObservatorySky")
local breakBtn = skyGui.Root:FindFirstChild("BreakButton")
local caption = skyGui.Root:FindFirstChild("SkyCaption")
local NORMAL = Color3.fromRGB(18, 20, 30)

local DT = 1 / 30
local changes, last = 0, nil
local function frame()
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CFrame = walkCam end
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	local c = breakBtn.BackgroundColor3
	if last ~= nil and c ~= last then changes += 1 end
	last = c
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end
local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function answer(right: boolean)
	local info = h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId))
	local clean = info:GetAttribute("Clean") == true
	local pad = zone:FindFirstChild(if clean == right then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
end
local function highlighted(): boolean
	return breakBtn.BackgroundColor3 ~= NORMAL
end
local function day(): number
	return plr.leaderstats.Day.Value
end
local function takeBreak(): string
	breakBtn.Activated:Fire()
	run(1)
	local text = caption.Text
	breakBtn.Activated:Fire()
	run(1.5)
	return text
end

local intro = NightSky.introNews(true)
local bandName = Config.Sky.Bands[2].name -- Meteor Shower, full on Day 4

run(1)
truthy(highlighted(), "at join the button is highlighted: the join tip waits for the first break")
changes = 0

-- 1. the band arrives and is taken away again before any break
answer(true); run(0.5)
answer(true); run(0.5)
answer(true); run(1)
eq(day(), 4, "three right calls reach Day 4 (a new band)")
truthy(highlighted(), "after the band arrives the button is highlighted")
answer(false); run(3.5)
eq(day(), 1, "a wrong call is back on Day 1")
truthy(highlighted(), "after the wrong call the button is STILL highlighted: the join tip has not been seen yet")

-- 2. the band again: both pieces of news are waiting; the first break carries the tip
answer(true); run(0.5)
answer(true); run(0.5)
answer(true); run(1)
eq(day(), 4, "Day 4 again")
local first = takeBreak()
truthy(string.find(first, intro, 1, true) ~= nil, "the first break carries the join tip: " .. first)
truthy(highlighted(), "after the first break the button is still highlighted: the band has not been named yet")

-- 3. the next break names the band, and then nothing is waiting
local second = takeBreak()
truthy(string.find(second, bandName, 1, true) ~= nil, "the next break names the band: " .. second)
truthy(not highlighted(), "after it nothing is pending and the button is back to normal")
local third = takeBreak()
truthy(string.find(third, intro, 1, true) == nil and string.find(third, bandName, 1, true) == nil,
	"a break with nothing new says neither again: " .. third)

-- 5. (owner decision 2026-09-30, the optional brag) the HUD's Best line carries the emoji of the highest
-- sky band the Best Day has reached, from the server's own State push
do
	local state = h.ReplicatedStorage:FindFirstChild("AnomalyRemotes"):FindFirstChild("State")
	local sent = state:getSent()
	local payload = table.clone(sent[#sent].args[1])
	local function bestText(): string
		for _, d in plr.PlayerGui:FindFirstChild("AnomalyHud"):GetDescendants() do
			if d:IsA("TextLabel") and string.sub(d.Text, 1, 5) == "Best:" then return d.Text end
		end
		return "(no Best label)"
	end
	local deep = Config.Sky.Bands[6] -- Deep Sky, the headline
	payload.best = deep.from
	state:FireClient(plr, payload)
	run(0.2)
	truthy(string.find(bestText(), deep.emoji, 1, true) ~= nil and string.find(bestText(), "Day " .. deep.from, 1, true) ~= nil,
		"Best Day " .. deep.from .. " shows the " .. deep.name .. " emoji: " .. bestText())
	payload.best = 3
	state:FireClient(plr, payload)
	run(0.2)
	eq(bestText(), "Best: Day 3", "a Best Day still on the first night shows no emoji")
end

-- 4. steady, never a blink: at most one change per arrival or reading of news
print(string.format("   highlight changes over the run: %d", changes))
truthy(changes <= 6, string.format("the highlight changed colour %d times: only when news arrived or was seen", changes))

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomalyobservatory_news: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory news check failed", 0)
end
