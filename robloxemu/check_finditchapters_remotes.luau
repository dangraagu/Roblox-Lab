-- Find It! Chapters: what a player may ask, and how often (REVIEW-1 B1, A6, A4), through the REAL server and the
-- REAL HUD and Room clients.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_remotes.luau 2>&1
--
--   * B1: a returning player presses the Case Book prompt and taps a menu row a moment later (0.3 s, 0.6 s): the
--     chapter opens. The prompt that only opens the menu must not eat the Open the menu sends;
--   * A6: refusals are answered in words, but a flood is not: 1000 refused Searches (hub, out of reach) and 1000
--     Resumes in one frame cost a handful of sends, and a second later a single refusal is answered again;
--   * A4: Pause/Resume is not a free re-roll of the room. Right after a re-dress the next Pause is refused with
--     words (the client does not rest, the server's clock keeps running); over 40 attempted cycles every re-dress
--     after the first costs at least Pause.EverySeconds of the clock.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-remotes", viewport = { 800, 360 }, touch = true })
local dt = h.instance.datatypes
local CFrame, Enum, Vector3 = dt.CFrame, dt.Enum, dt.Vector3
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("FindIt_Players_v1")
local NOW = os.time()
do
	local stars = {}
	for ch = 1, 14 do stars["c" .. ch] = { f = true, w = false, s = false } end
	store:SetAsync("u_520", { data = { v = 1, book = { cleared = 14, stars = stars }, daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
		solved = 14, solvedAt = NOW - 86400, boarded = 14, seenIntro = true, firstJoin = NOW - 86400 }, lock = { session = "", ["until"] = 0 } })
end
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local T = Config.Text
local RunService = h.game:GetService("RunService")
local remotes = RS:FindFirstChild("FindItRemotes")
local Bus = mod("ClientBus")
local function frame(d)
	RunService.Heartbeat:Fire(d)
	RunService.RenderStepped:Fire(d)
	h:advance(d)
end
local function run(s)
	local t = 0
	while t < s - 1e-9 do
		local d = math.min(1 / 20, s - t)
		frame(d)
		t += d
	end
end
local function last(name) local s = remotes:FindFirstChild(name):sentTo(h.Players:GetPlayers()[1]); return s[#s] and s[#s].args[1] end
local function count(name) return #remotes:FindFirstChild(name):sentTo(h.Players:GetPlayers()[1]) end

local plr = h:join("Rae", 520)
h:advance(1)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Room.client"))
run(2.5)
local hud = plr.PlayerGui:FindFirstChild("FindItHud"):FindFirstChild("Root")
local book = ws.FindItWorld.Hub.CaseBook
local function stats()
	local s = {}
	Bus.fire("__stats", s)
	return s
end

--============================================================ B1: the prompt opens the menu; a tap right after opens the chapter
for _, case in { { delay = 0.3, row = "Continue", want = 15 }, { delay = 0.6, row = "Chapter_9", want = 9 }, { delay = 0.3, row = "Daily", want = "daily" } } do
	hrp.CFrame = CFrame.new(book.Position.X, 3, book.Position.Z + 4)
	run(0.2)
	book:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	run(case.delay)
	truthy(hud.Menu.Visible, string.format("B1: the prompt opened the Case Book menu (%s)", case.row))
	local toasts0 = count("Toast")
	hud.Menu.List:FindFirstChild(case.row).Activated:Fire()
	run(0.3)
	local st = last("State")
	eq(st.where, "room", string.format("B1: tapping %s %.1f s after the prompt opens a room", case.row, case.delay))
	if case.want == "daily" then
		eq(st.kind, "daily", "B1: ... the Daily Case")
	else
		eq(st.chapter, case.want, "B1: ... chapter " .. case.want)
	end
	eq(count("Toast") - toasts0, 0, "B1: with no refusal")
	remotes.Hub:simulateFireServer(plr)
	run(1.2)
	eq(last("State").where, "hub", "B1: back in the hub")
end

--============================================================ A6: a flood of refused calls costs a handful of answers
do
	run(2)
	local t0, burst = count("Toast"), Config.Limits.RefusalBurst or 4 -- (or 4: the bound the review asked for, also on a build without the field)
	for _ = 1, 1000 do remotes.Search:simulateFireServer(plr, 5) end
	h:advance(0.05)
	local n = count("Toast") - t0
	truthy(n >= 1 and n <= burst, string.format("A6: 1000 Search calls from the hub, one frame: %d answers (1..%d)", n, burst))
	eq(last("Toast").text, T.NotInRoom, "A6: ... the first is answered in words")
	run(1.1)
	t0 = count("Toast")
	remotes.Search:simulateFireServer(plr, 5)
	h:advance(0.05)
	eq(count("Toast") - t0, 1, "A6: a second later, one refused Search is answered again")
	-- in a room: the farthest prop, out of reach from the door mat
	remotes.Open:simulateFireServer(plr, 1)
	run(3.6)
	local pl = last("Room")
	local far, fd = nil, 0
	for _, q in pl.props do local d = q.x * q.x + q.z * q.z if d > fd then far, fd = q, d end end
	hrp.CFrame = CFrame.new(pl.origin[1], 3, pl.origin[3] + 1.5)
	run(1.2)
	local looks0 = last("State").looks
	t0 = count("Toast")
	local s0 = count("State")
	for _ = 1, 1000 do remotes.Search:simulateFireServer(plr, far.id) end
	h:advance(0.05)
	n = count("Toast") - t0
	truthy(n >= 1 and n <= burst, string.format("A6: 1000 out-of-reach Searches in a room, one frame: %d answers (1..%d)", n, burst))
	eq(last("Toast").text, T.WalkCloser, "A6: ... 'Walk closer'")
	eq(last("State").looks, looks0, "A6: ... and no look spent")
	s0 = count("State")
	for _ = 1, 1000 do remotes.Resume:simulateFireServer(plr) end
	h:advance(0.05)
	n = count("State") - s0
	truthy(n <= 1, string.format("A6: 1000 Resume calls while live, one frame: %d State sends (<= 1)", n))
	remotes.Hub:simulateFireServer(plr)
	run(1.2)
end

--============================================================ A4: Pause/Resume is not a free re-roll
do
	remotes.Open:simulateFireServer(plr, 15)
	run(3.6)
	eq(last("State").state, "live", "A4: chapter 15 is live")
	local pl = last("Room")
	hrp.CFrame = CFrame.new(pl.origin[1], 3, pl.origin[3] + pl.D / 2)
	run(0.3)
	-- the HUD path: the first pause is free; right after its re-dress the button is refused in words
	hud.PauseButton.Activated:Fire()
	run(0.2)
	eq(last("State").state, "paused", "A4: the first Pause of the attempt is accepted")
	hum.MoveDirection = Vector3.new(0, 0, 1)
	run(0.3)
	hum.MoveDirection = Vector3.new(0, 0, 0)
	run(3.5)
	eq(last("State").state, "live", "A4: a move resumed it (the room was re-dealt)")
	local clockA = last("State").clock
	local toasts0 = count("Toast")
	hud.PauseButton.Activated:Fire()
	run(0.3)
	eq(last("State").state, "live", "A4: a Pause right after the re-dress is not taken")
	truthy(not stats().rest.resting, "A4: ... the client does not rest")
	local said = Bus.last("toast")
	truthy(type(said) == "string" and string.find(said, "pause again", 1, true) ~= nil,
		"A4: ... and the player is told when they can pause again (" .. tostring(said) .. ")")
	-- a script asking the server directly is refused in words too
	remotes.Pause:simulateFireServer(plr)
	h:advance(0.05)
	eq(last("State").state, "live", "A4: a Pause fired at the server right after the re-dress is refused")
	truthy(count("Toast") > toasts0 and string.find(last("Toast").text, "pause again", 1, true) ~= nil, "A4: ... with words")
	run(1)
	truthy(last("State").clock > clockA + 1, "A4: the clock kept running")

	-- the reviewer's measure: 40 Pause/Resume cycles with a 0.1 s glance, straight at the server
	local redress, rooms0 = 0, count("Room")
	local clock0 = last("State").clock
	for _ = 1, 40 do
		run(0.6) -- past the Pause rate limit
		remotes.Pause:simulateFireServer(plr)
		h:advance(0.02)
		frame(0.02)
		if last("State").state == "paused" then
			remotes.Resume:simulateFireServer(plr)
			local w = 0
			while last("State").state ~= "live" and w < 6 do frame(0.05); w += 0.05 end
		end
		frame(0.1)
	end
	redress = count("Room") - rooms0
	local spent = last("State").clock - clock0
	local every = Config.Pause.EverySeconds or 30
	local cap = math.floor(spent / every) + 1
	print(string.format("  A4: 40 attempted Pause/Resume cycles: %d re-dresses over %.1f s of clock (at most %d allowed)", redress, spent, cap))
	truthy(redress <= cap, string.format("A4: re-dresses %d <= 1 + clock/%d = %d", redress, every, cap))
	truthy(redress < 40, "A4: the 40 cycles did not re-deal the room 40 times")
	remotes.Hub:simulateFireServer(plr)
	run(1.2)
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it remotes: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_remotes failed", 0) end
