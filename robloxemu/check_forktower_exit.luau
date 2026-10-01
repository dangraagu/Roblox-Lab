-- Fork Tower — the exit cannot be teleported to. Run: luau check_forktower_exit.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- QUEUED JOB I (found 2026-09-24 by the plan-secret attacker; REVIEW-4.md §9.8 item 5). The exit
-- platform's Touched handler checked only WHO touched it and the profile's floor and stage. A client
-- owns its character's physics, so a script could choose a door and teleport onto the exit at once
-- (or fire the exit's Touched from anywhere): to a script a trap cost nothing whatever it predicted,
-- and the read-versus-guess economy (tests/readcost.measure.luau) priced only honest players.
--
-- The server now clears a floor only when BOTH hold, on its own clock and its own view of the body:
--   * the root part stands on the exit platform (Config.Exit: the footprint grown by the character's
--     half-width and a margin, from a little below the top to a jump above it), so a Touched fired
--     from anywhere else clears nothing;
--   * at least Section.minClimbSeconds has passed since the door dropped the player on the section:
--     the straight line on the ground from the entry to the exit's reach, at the player's own
--     WalkSpeed * Config.Exit.SpeedSlack. Nobody moves sideways faster than their WalkSpeed, and
--     tests/Pacing.spec.luau measures that no honest climber in the climb model is ever refused.
-- A refused touch tells the player why, once per section. The server also looks for a body standing on
-- the exit every Config.Exit.PollSeconds, so an honest player whose landing Touched came too early or
-- from a limb is never left standing on a spent exit.
--
-- Headless limits: no physics. Bodies are moved by writing the root part's CFrame, which is exactly
-- what a teleporting client does.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower-exit", viewport = { 1280, 720 }, touch = false })
local store = h.services.DataStoreService:GetDataStore("ForkTower_v1")
local function seedProfile(uid)
	store:SetAsync("u_" .. uid, {
		data = {
			runSeed = 4, level = 1, stage = "fork", picks = {}, slots = {}, readFloors = {}, skipped = {},
			skips = 0, rebirths = 0, bestScore = 0, bestTitle = "", redeemed = {}, passes = {},
		},
	})
end
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Section = h:_require(RS:FindFirstChild("Section"))
local towers = h.workspace:FindFirstChild("Towers")
local NoticeEvent = RS:FindFirstChild("ForkRemotes"):FindFirstChild("Notice")
truthy(type(Config.Exit) == "table", "set-up: Config.Exit exists")

local function laneOf(plr)
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end
local function blockedNotices(plr)
	local n = 0
	for _, msg in NoticeEvent:sentTo(plr) do
		local a = msg.args and msg.args[1]
		if type(a) == "table" and a.kind == "blocked" then n += 1 end
	end
	return n
end
local function floorOf(plr) return plr.leaderstats.Floor.Value end
local function now() return h.scheduler:now() end

local U = 7301
seedProfile(U)
local plr = h:join("Climber", U)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
local lane = laneOf(plr)
truthy(lane ~= nil and hrp ~= nil, "set-up: the climber has a lane and a body")

local function readAndChooseSafe(level)
	local fork = lane:FindFirstChild("Fork_" .. level)
	local pad = fork:FindFirstChild("ForkPad_" .. level)
	hrp.CFrame = CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0))
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	prompt.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Fork.ReadSeconds + 0.05)
	prompt.Triggered:Fire(plr)
	h:advance(0.1)
	local m1 = fork:FindFirstChild("Door_" .. level .. "_1"):GetAttribute("Marked") == true
	local marked = if m1 then 1 else 2
	local trap = if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
	local chosenAt = now()
	fork:FindFirstChild("Door_" .. level .. "_" .. (3 - trap)):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	h:advance(0.05)
	return chosenAt
end
-- the section as the server built it, re-derived from the same pure module and the lane's own geometry
local function sectionOf(level)
	local folder = lane:FindFirstChild("Section_" .. level)
	local plats, exit = {}, nil
	for _, c in folder:GetChildren() do
		local i = tonumber(string.match(c.Name, "^Plat_%d+_(%d+)$"))
		if i then plats[i] = c end
		if c:GetAttribute("Exit") == true then exit = c end
	end
	return folder, plats, exit
end
local function standOn(part)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
end
-- the server's own bound for this floor, rebuilt from Section (same seed, level, theme, penalty, origin)
local function needFor(level)
	local folder = lane:FindFirstChild("Section_" .. level)
	local fork = lane:FindFirstChild("Fork_" .. level)
	local pad = fork:FindFirstChild("ForkPad_" .. level)
	local originX = pad.Position.X - lane:FindFirstChild("LobbyPad").Position.X
	local sec = Section.build(Config, 4, level, folder:GetAttribute("Theme"), folder:GetAttribute("Penalty"), h:_require(RS:FindFirstChild("Rng")), originX)
	return Section.minClimbSeconds(Config, sec, hum.WalkSpeed), sec
end

-- A scenario that errors (a mutant that leaves a floor uncleared makes the next one's fork missing) is a
-- failure with its message, and the rest still runs, so the file always ends with its summary.
local function scenario(name, fn)
	local ok, err = pcall(fn)
	truthy(ok, "scenario " .. name .. " ran to its end (" .. tostring(err) .. ")")
end

--======================================================================= 1. a teleport to the exit clears nothing

scenario("1", function()
	local chosenAt = readAndChooseSafe(1)
	local _, plats, exit = sectionOf(1)
	local need = needFor(1)
	truthy(need >= 0.5, string.format("set-up: floor 1's section takes a real time to cross (%.2f s)", need))
	-- the door dropped the player on platform 1
	local p1 = plats[1]
	truthy(p1 ~= nil and (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(p1.Position.X, 0, p1.Position.Z)).Magnitude <= p1.Size.X / 2,
		"set-up: the door dropped the player on platform 1")
	local before = blockedNotices(plr)
	standOn(exit)
	exit.Touched:Fire(hrp)
	h:advance(0.05)
	eq(floorOf(plr), 1, "a teleport onto the exit the moment the door is chosen clears nothing")
	eq(blockedNotices(plr), before + 1, "and the player is told why (one notice)")
	-- held there, touching it again and again, until just before the section could have been climbed
	local fires = 0
	while now() - chosenAt < need - Config.Exit.PollSeconds - 0.1 do
		exit.Touched:Fire(hrp)
		fires += 1
		h:advance(0.1)
	end
	eq(floorOf(plr), 1, string.format("standing on the exit and touching it %d times, still nothing before the climb's least time (%.2f s)", fires, need))
	eq(blockedNotices(plr), before + 1, "the refusal is said once per section, not once per touch")
	-- then it clears, by the server's own look at the body, without another Touched
	local clearedAt = nil
	for _ = 1, 40 do
		h:advance(0.05)
		if floorOf(plr) == 2 then clearedAt = now(); break end
	end
	truthy(clearedAt ~= nil, "a body standing on the exit is seen by the server once the least time has passed (no Touched needed)")
	if clearedAt then
		local t = clearedAt - chosenAt
		truthy(t >= need - 1e-6 and t <= need + Config.Exit.PollSeconds + 0.1,
			string.format("it cleared between the least time and one poll after it (%.2f s, least %.2f)", t, need))
	end
end)

--======================================================================= 2. a Touched from elsewhere clears nothing

scenario("2", function()
	local chosenAt = readAndChooseSafe(2)
	local _, plats, exit = sectionOf(2)
	local need = needFor(2)
	h:advance(need + 1)
	-- the body is still on platform 1; the exit's Touched is fired from there (firetouchinterest)
	exit.Touched:Fire(hrp)
	h:advance(1)
	eq(floorOf(plr), 2, "an exit Touched fired while the body stands on platform 1 clears nothing, however late")
	-- the honest way up: platform by platform, then the exit
	for i = 2, #plats - 1 do
		standOn(plats[i])
		plats[i].Touched:Fire(hrp)
		h:advance(0.3)
	end
	standOn(exit)
	exit.Touched:Fire(hrp)
	h:advance(0.05)
	eq(floorOf(plr), 3, string.format("the same exit, touched by a body standing on it after the climb (%.1f s), clears the floor at once", now() - chosenAt))
end)

--======================================================================= 3. the bound is a physical one

-- A body moving in a straight line from the entry to the exit at exactly its WalkSpeed is the fastest
-- anything honest can do; it arrives at D / WalkSpeed. The server asks for D / (WalkSpeed * slack).
scenario("3a", function()
	local chosenAt = readAndChooseSafe(3)
	local _, _, exit = sectionOf(3)
	local need = needFor(3)
	local start = hrp.Position
	local speed = hum.WalkSpeed
	local d = need * speed * Config.Exit.SpeedSlack -- the straight-line distance the bound was built from
	local arrive = d / speed -- at exactly WalkSpeed
	h:advance(math.max(0, arrive - (now() - chosenAt)))
	standOn(exit)
	exit.Touched:Fire(hrp)
	h:advance(0.02)
	eq(floorOf(plr), 4, string.format("a body that crossed in a straight line at its full WalkSpeed (%.2f s, least %.2f s) clears the floor", arrive, need))
	truthy(start ~= nil, "set-up: the crossing started from the entry")
end)
scenario("3b", function()
	local chosenAt = readAndChooseSafe(4)
	local _, _, exit = sectionOf(4)
	local need = needFor(4)
	local speed = hum.WalkSpeed
	local arrive = (need * speed * Config.Exit.SpeedSlack) / (speed * 1.5) -- half again faster than WalkSpeed
	h:advance(math.max(0, arrive - (now() - chosenAt)))
	standOn(exit)
	exit.Touched:Fire(hrp)
	h:advance(0.02)
	eq(floorOf(plr), 4, string.format("a body that got there faster than its WalkSpeed allows (%.2f s, least %.2f s) is refused", arrive, need))
end)

--======================================================================= 4. a rejoin mid-climb starts the section's clock again

scenario("4", function()
	-- floor 4's door is chosen and the player is mid-climb: leave (the server's releasing write) and come back
	eq(floorOf(plr), 4, "set-up: mid-climb on floor 4")
	h:leave(plr)
	char:Destroy()
	h:advance(2)
	local restoredAt = now() -- the rejoin rebuilds the lane and puts the player at the section's bottom
	plr = h:join("Climber", U)
	h:advance(0.05)
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.05)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	lane = laneOf(plr)
	eq(floorOf(plr), 4, "set-up: the rejoin restored floor 4")
	local _, _, exit = sectionOf(4)
	truthy(exit ~= nil, "set-up: floor 4's section was rebuilt")
	local need = needFor(4)
	standOn(exit)
	exit.Touched:Fire(hrp)
	h:advance(0.02)
	truthy(now() - restoredAt < need, string.format("set-up: the teleport came %.2f s after the rejoin, inside the section's least time (%.2f s)", now() - restoredAt, need))
	eq(floorOf(plr), 4, "straight after a rejoin, a teleport onto the exit clears nothing (the rejoin puts the player back at the entry)")
	h:advance(need + Config.Exit.PollSeconds + 0.2 - (now() - restoredAt))
	eq(floorOf(plr), 5, "and standing there, it clears once the section could have been climbed")
end)

--======================================================================= 5. an honest climb after a rejoin clears at once

-- The rejoin puts the player back at the bottom of their section, and that is where the section's clock
-- starts: a player who climbs it honestly from there reaches an exit that counts on the first touch, with
-- nothing to wait for and nothing said.
scenario("5", function()
	readAndChooseSafe(5)
	eq(floorOf(plr), 5, "set-up: mid-climb on floor 5")
	h:leave(plr)
	char:Destroy()
	h:advance(2)
	plr = h:join("Climber", U)
	h:advance(0.05)
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.05)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	lane = laneOf(plr)
	local need = needFor(5)
	h:advance(need + 0.3) -- the climb, from the entry the rejoin put them on
	local _, _, exit = sectionOf(5)
	local told = blockedNotices(plr)
	standOn(exit)
	exit.Touched:Fire(hrp)
	h:advance(0.02)
	eq(floorOf(plr), 6, "after a rejoin, a climb as long as the section's least time clears on the first touch of the exit")
	eq(blockedNotices(plr), told, "and nothing is refused or said")
end)

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("fork tower exit: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower exit check failed", 0)
end
