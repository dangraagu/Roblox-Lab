-- Find It! Chapters: the way out of a room, and the result card's buttons while a clear is saving (REVIEW-1 round 2,
-- D1 and D4), through the REAL server and the REAL HUD and Room clients on a phone (800x360, touch).
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_exit.luau 2>&1
--
-- D1: a live room's only exit was Pause -> Hub, and after a Resume the next Pause waits 30 s of clock (round 1, A4),
--     so a player who wanted out waited ~30 s with nothing to press. Now a live room has a Leave button (the top
--     row, two taps: the first arms it and says what leaving costs, the second leaves); one tap alone never leaves.
-- D4: Next, Retry and Hub shared one rate bucket, and Hub was refused without a word: a Hub tap 0.4 s after a refused
--     Next (the clear still saving) hid the card and left the player in a finished room for ~5 s. Now Hub has its own
--     bucket and the card stays until the server moves the player; a Next tapped while the clear is saving is
--     remembered and opens the next chapter the moment the save lands (no second tap, no dead wait).
-- Each scenario first proves it is real (the re-dress happened, the clear really was waiting for the write gap).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-exit", viewport = { 800, 360 }, touch = true })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS, ws = h.ReplicatedStorage, h.workspace
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Bus = mod("Config"), mod("ClientBus")
local RunService = h.game:GetService("RunService")
local HttpService = h.game:GetService("HttpService")
local ServerStorage = h.game:GetService("ServerStorage")
local DSS = h.services.DataStoreService
local remotes = RS:FindFirstChild("FindItRemotes")
local store = DSS:GetDataStore(Config.Save.Store)
local writes = {}
local orig = store.UpdateAsync
store.UpdateAsync = function(self, k, f)
	table.insert(writes, h.scheduler:now())
	return orig(self, k, f)
end
local function frame(d)
	RunService.Heartbeat:Fire(d)
	RunService.RenderStepped:Fire(d)
	h:advance(d)
end
local function run(seconds)
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(0.05, seconds - t)
		frame(d)
		t += d
	end
end
local plr = h:join("Kid", 4250)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Room.client"))
assert(h:tryRun("client/Board.client"))
run(1)
local hud = plr.PlayerGui:FindFirstChild("FindItHud").Root
local book = ws.FindItWorld.Hub.CaseBook
local function last(name)
	local s = remotes:FindFirstChild(name):sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function tappable()
	local out = {}
	for _, d in hud:GetDescendants() do
		if d.ClassName == "TextButton" and d.Visible then
			local p, ok = d.Parent, true
			while p and p ~= hud do if p.Visible == false then ok = false end p = p.Parent end
			if ok then out[d.Name] = d end
		end
	end
	return out
end
local function rig()
	local v = ServerStorage.FindIt.Attempts:FindFirstChild(tostring(plr.UserId))
	return v and HttpService:JSONDecode(v.Value)
end
local function standNear(id)
	local pl = last("Room")
	for _, q in pl.props do
		if q.id == id then
			local o = pl.origin
			hrp.CFrame = CFrame.new(o[1] + q.x * 0.8, 3, o[3] + q.z * 0.8 + pl.D * 0.1)
		end
	end
end
-- play a room through the client's own tap hook (select, then search); `holdLast` runs before the last search
local function playRoom(holdLast)
	while last("State").state == "intro" do run(0.1) end
	local r = rig()
	for i, id in r.hidden do
		if i == #r.hidden and holdLast then holdLast() end
		standNear(id)
		Bus.fire("tapProp", id)
		Bus.fire("tapProp", id)
		run(1.1)
	end
end
local function waitAutosave()
	local n0 = #writes
	local waited = 0
	while #writes == n0 and waited < 25 do run(0.05); waited += 0.05 end
end
local function openFromBook(row)
	hrp.CFrame = CFrame.new(book.Position.X, 3, book.Position.Z + 5)
	run(0.2)
	book:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	run(0.6)
	if row then
		local b = hud.Menu.List:FindFirstChild(row)
		assert(b, "no menu row " .. row)
		b.Activated:Fire()
		run(0.3)
	end
end

-- a new player: the Case Book takes them straight into Chapter 1; clear it, Next into Chapter 2
openFromBook(nil)
eq(last("State").chapter, 1, "a new player is in Chapter 1")
playRoom(nil)
run(0.5)
hud.Card.Buttons.NextButton.Activated:Fire()
run(0.3)
eq(last("State").chapter, 2, "Next opens Chapter 2")

--============================================================ D1: out of a live room after a Pause/Resume
do
	while last("State").state == "intro" do run(0.1) end
	local t = tappable()
	truthy(t.LeaveButton ~= nil, "D1: a live room shows a Leave button")
	hud.PauseButton.Activated:Fire()
	run(0.5)
	eq(last("State").state, "paused", "D1: paused")
	hud.Card.Buttons.ResumeButton.Activated:Fire()
	run(3.6)
	eq(last("State").state, "live", "D1: resumed")
	eq(last("Room").redress, true, "D1: the room was re-dealt (the scenario is real)")
	truthy((last("State").pauseIn or 0) > 25, string.format("D1: the next Pause is %.0f s of clock away", last("State").pauseIn or -1))
	t = tappable()
	truthy(t.LeaveButton ~= nil, "D1: after the re-dress the Leave button is there")
	t.LeaveButton.Activated:Fire()
	run(0.3)
	eq(last("State").where, "room", "D1: one tap does not leave (it arms)")
	local said = Bus.last("toast")
	truthy(type(said) == "string" and said == Config.Text.LeaveConfirm, "D1: ... and says what leaving costs: " .. tostring(said))
	run(3.5)
	local tArm = h.scheduler:now()
	tappable().LeaveButton.Activated:Fire()
	run(0.3)
	eq(last("State").where, "room", "D1: a tap 3.8 s after the first starts over (it arms again): still in the room")
	local leave = tappable().LeaveButton
	truthy(leave ~= nil, "D1: the armed Leave button is still there")
	leave.Activated:Fire()
	run(1.2)
	eq(last("State").where, "hub", "D1: the second tap leaves the room")
	local took = h.scheduler:now() - tArm
	truthy(took <= 2, string.format("D1: in the hub %.1f s after deciding to leave (it took ~30 s through Pause)", took))
	truthy((hrp.Position - ws.FindItWorld.Hub.HubSpawn.Position).Magnitude < 12, "D1: standing at the hub spawn")
end

--============================================================ D4: Hub after a refused Next while the clear is saving
do
	openFromBook("Continue")
	eq(last("State").chapter, 2, "D4: Continue reopens Chapter 2")
	playRoom(function()
		waitAutosave()
		print(string.format("  an autosave landed at t=%.2f; the last search goes now", writes[#writes]))
	end)
	local st = last("State")
	eq(st.result and st.result.reason, "found", "D4a: Chapter 2 found")
	eq(st.result and st.result.saving, true, "D4a: the clear is waiting for the write gap (the scenario is real)")
	hud.Card.Buttons.NextButton.Activated:Fire()
	run(0.4)
	eq(last("State").chapter, 2, "D4a: Next while saving does not open Chapter 3 yet")
	truthy(hud.Card.Visible, "D4a: the card stays")
	hud.Card.Buttons.HubButton.Activated:Fire()
	run(0.2)
	truthy(hud.Card.Visible or last("State").where == "hub", "D4a: a Hub tap never leaves a finished room with no card and no buttons")
	run(1.3)
	eq(last("State").where, "hub", "D4a: Hub 0.4 s after a refused Next takes the player to the hub")
	run(8)
	eq(last("State").where, "hub", "D4a: the remembered Next does not pull the player back once the save lands")
	eq(store:GetAsync("u_4250").data.book.cleared, 2, "D4a: Chapter 2 is saved")
end

--============================================================ D4: Next while saving opens the next chapter when the save lands
do
	openFromBook("Continue")
	eq(last("State").chapter, 3, "D4b: Continue opens Chapter 3")
	playRoom(function() waitAutosave() end)
	local st = last("State")
	eq(st.result and st.result.saving, true, "D4b: the clear is waiting for the write gap (the scenario is real)")
	local t0 = h.scheduler:now()
	hud.Card.Buttons.NextButton.Activated:Fire()
	run(0.3)
	local said = last("Toast")
	truthy(said and said.text == Config.Text.NextAfterSave, "D4b: Next says it opens once the case is saved: " .. tostring(said and said.text))
	local waited = 0
	while last("State").chapter ~= 4 and waited < 12 do run(0.1); waited += 0.1 end
	eq(last("State").chapter, 4, "D4b: Chapter 4 opens by itself once the save lands (one tap)")
	local took = h.scheduler:now() - t0
	truthy(took <= Config.Save.MinWriteGap + 1.5, string.format("D4b: %.1f s after the tap (the write gap is %d s)", took, Config.Save.MinWriteGap))
	eq(store:GetAsync("u_4250").data.book.cleared, 3, "D4b: Chapter 3 was saved first")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	failed += 1
	print("FAIL: a warning: " .. w)
end
print(string.format("find it exit: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_exit failed", 0) end
