-- Labyrinth Mariozo — rest: the lobby break room and the free-break sign, through the REAL clients.
-- Run: luau check_labyrintspill_rest.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- What "rest" means in this game (labyrint-spill/src/shared/BreakRoom.luau): never a pause inside a
-- timed run — the run clock is the medal, and traps and monsters live on the server — but a break room
-- between runs, and a free walk-out at the start of every level. This file checks:
--   §1 the campfire corner is in the lobby, inert, lit only while you are in the lobby;
--   §2 "Rest by the fire" sits you down, softens the view, says nothing is running; any move or jump
--      gets you up; resting sends nothing to the server;
--   §3 no rest inside a run (the prompt is off; triggering it anyway does nothing);
--   §4 the door sign: on THIS run's Lobby door, only for the free window, then gone for good;
--   §5 END TO END against the server's own counter: the sign never promises a free walk-out the server
--      would count as a failed attempt. The server times runs with os.clock() (real time even here),
--      so this section burns real seconds on purpose;
--   §6 the biome board lists what you reached, and what is next;
--   §7 (review fix) once a "Hjelp meg" guide is bought for the run, the sign stays down: walking out would
--      lose the guide, so it is no longer "free, nothing is lost" (burns real seconds too).

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill rest")
local truthy, eq, near = T.truthy, T.eq, T.near

local ctx = Lib.boot({ accepted = 40, coins = 5000, clients = Lib.CLIENTS_NO_SOUND }) -- coins: §7 buys a guide
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local EnvBands = mod("EnvBands")
local Biomes = mod("Biomes")
local BreakRoom = mod("BreakRoom")
local CFG = Biomes.Rest

local room = h.workspace:FindFirstChild("LabyrintBreakRoom")
truthy(room ~= nil, "the break room folder exists")
local fire = room and room:FindFirstChild("Fire")
local prompt = fire and fire:FindFirstChild("RestPrompt")
truthy(prompt ~= nil, "the campfire has its Rest prompt")
local toast = ctx.plr.PlayerGui:FindFirstChild("LabyrintBreak").Root.RestToast

-- server-side remote traffic
local calls = 0
for _, d in RS:GetDescendants() do
	if d.ClassName == "RemoteEvent" then d.OnServerEvent:Connect(function() calls += 1 end) end
end

-- the player's AssistState as the server sends it (fails = the server's own failed-attempt counter)
local lastAssist = nil
RS.AssistRemotes.AssistState.OnClientEvent:Connect(function(p) lastAssist = p end)

--================================================================ §1 the campfire corner

ctx.run(1)
do
	local lobbyFloor = h.workspace.Lobby.LobbyFloor
	local fp = fire.Position
	truthy(math.abs(fp.X - lobbyFloor.Position.X) <= lobbyFloor.Size.X / 2 - 4 and math.abs(fp.Z - lobbyFloor.Position.Z) <= lobbyFloor.Size.Z / 2 - 4,
		"the campfire stands on the lobby floor")
	-- clear of the doors (z = -22) and the boards (x = +-20, z = 16) and the spawn pad (origin)
	for _, n in { "SoloDoor", "GroupDoor", "FriendsDoor", "LobbySpawn", "ContributorsPole", "DailyRewardPole", "Pedestal" } do
		local p = h.workspace.Lobby:FindFirstChild(n)
		if p then
			local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(fp.X, 0, fp.Z)).Magnitude
			truthy(d >= 10, "the campfire corner keeps clear of " .. n .. " (" .. math.floor(d) .. " studs)")
		end
	end
	local c = Lib.census(h, { "LabyrintBreakRoom" })
	eq(c.lights, 1, "one light in the lobby (the fire)")
	eq(c.emitters, 2, "flames and smoke")
	print(string.format("== break room: %d parts, %d emitters (%.0f/s), %d light", c.parts, c.emitters, c.rate, c.lights))
	eq(prompt.Enabled, true, "the prompt is on in the lobby")
	eq(prompt.HoldDuration, 0, "one tap to rest")
end

--================================================================ §2 rest by the fire

do
	ctx.moveTo(fire.Position + Vector3.new(4, 3, 0))
	local before = calls
	prompt.Triggered:Fire()
	ctx.run(0.2)
	eq(ctx.hum.Sit, true, "Rest sits the player down")
	local cam = h.workspace.CurrentCamera
	truthy(cam:FindFirstChild("RestDoF") ~= nil, "the view softens (a depth-of-field on the local camera)")
	eq(toast.Visible, true, "the toast says nothing is running")
	truthy(string.find(toast.Text, "nothing is running", 1, true) ~= nil, "in so many words")
	ctx.run(5)
	eq(ctx.hum.Sit, true, "sitting still, you stay resting")
	ctx.hum.MoveDirection = Vector3.new(1, 0, 0)
	ctx.run(0.6)
	eq(ctx.hum.Sit, false, "moving gets you up")
	eq(cam:FindFirstChild("RestDoF"), nil, "the view sharpens again")
	eq(toast.Visible, false, "the toast goes")
	ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
	-- jump wakes too
	prompt.Triggered:Fire()
	ctx.run(0.6)
	eq(ctx.hum.Sit, true, "resting again")
	ctx.hum.Jump = true
	ctx.run(0.3)
	ctx.hum.Jump = false
	eq(ctx.hum.Sit, false, "a jump gets you up")
	eq(calls - before, 0, "resting sends nothing to the server")
end

--================================================================ §3 no rest inside a run

local levelT0 = 0
local function start(level)
	if ctx.folder() ~= nil then ctx.toLobby() end
	levelT0 = ctx.clock
	RS.LobbyRemotes.StartRun:simulateFireServer(ctx.plr, level, "solo")
end

do
	start(41)
	ctx.run(0.3)
	eq(prompt.Enabled, false, "the Rest prompt is off inside a run")
	prompt.Triggered:Fire()
	-- (resume session) before any frame runs: the frame loop would also stand a seated player up inside a
	-- run, which hid a missing in-lobby guard (mutation R2) behind a one-frame sit
	eq(ctx.hum.Sit == true, false, "triggering it inside a run does not sit you down, not even for a frame")
	eq(toast.Visible, false, "and says nothing about resting")
	ctx.run(0.3)
	eq(ctx.hum.Sit == true, false, "triggering it anyway inside a run does not sit you down")
	eq(Lib.census(h, { "LabyrintBreakRoom" }).lights, 0, "and the lobby fire is out while you are in a maze")
end

--================================================================ §4 the door sign

local function sign()
	return room:FindFirstChild("BreakSign")
end
do
	-- still in the run started above (0.6 s in)
	local s = sign()
	truthy(s ~= nil, "the free-break sign is up at the start of the run")
	local door = ctx.folder():FindFirstChild("LobbyDoor")
	eq(s and s.Adornee, door, "on THIS run's Lobby door")
	eq(s and s.Parent, room, "built in the local folder, never parented under the server's door")
	local label = s and s:FindFirstChild("Text")
	truthy(label and label.TextTransparency < 0.01, "fully readable at first")
	truthy(label and string.find(label.Text, "free", 1, true) ~= nil and string.find(label.Text, "nothing is lost", 1, true) ~= nil,
		"it says the walk-out is free and nothing is lost")
	-- run to the end of the window, sampling
	local lastSeen = 0
	while ctx.clock - levelT0 < CFG.FreeBreakSeconds + 3 do
		ctx.frame(1 / 30)
		local ss = sign()
		if ss then lastSeen = ctx.clock - levelT0 end
	end
	truthy(lastSeen < CFG.FreeBreakSeconds + 1e-6, string.format("the sign is gone by the end of the free window (last seen at %.2f s, window %d s)", lastSeen, CFG.FreeBreakSeconds))
	truthy(lastSeen > CFG.FreeBreakSeconds - 0.2, "and stays up until then (fading)")
	eq(sign(), nil, "gone for good in this run")
	-- the next level (advance) opens a fresh free window: a new level start is a new break chance
	ctx.finishLevel()
	levelT0 = ctx.clock
	ctx.run(0.3)
	truthy(sign() ~= nil, "every new level starts with a fresh sign")
	eq(sign() and sign().Adornee, ctx.folder():FindFirstChild("LobbyDoor"), "on the new level's door")
end

--================================================================ §5 end to end: the sign never lies

-- Burn REAL seconds: the server's run clock is os.clock(), which the emulator does not virtualise.
local function burnReal(seconds)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
do
	-- A: the client stalls (no frames) for 6.3 real seconds, as a hitched or minimised client would.
	-- Its frame clock is still near zero, but its wall clock is past the window: the sign must be gone,
	-- and the walk-out, at ~6.3 s of server time, is still free.
	start(42)
	ctx.run(0.1)
	truthy(sign() ~= nil, "(A) the sign is up at the start")
	burnReal(CFG.FreeBreakSeconds + 0.3)
	ctx.frame(1 / 30)
	eq(sign(), nil, "(A) after a 6.3 s stall the sign is gone although only a frame was drawn (wall clock)")
	lastAssist = nil
	ctx.toLobby()
	truthy(lastAssist ~= nil, "(A) the server answered the walk-out with the player's assist state")
	eq(lastAssist and lastAssist.fails, 0, "(A) a walk-out at ~6.3 s is not counted as a failed attempt")

	-- B: past the server's rule (8 s of server time). The sign has been gone since 6 s; the server now
	-- counts the walk-out — exactly the case the sign must never cover.
	start(42)
	ctx.run(0.1)
	burnReal(CFG.ServerMinRunSeconds + 0.3)
	ctx.frame(1 / 30)
	eq(sign(), nil, "(B) no sign past the window")
	lastAssist = nil
	ctx.toLobby()
	eq(lastAssist and lastAssist.fails, 1, "(B) a walk-out after 8 s IS counted by the server — and no sign promised otherwise")

	-- C: a quick walk-out while the sign is up costs nothing
	start(42)
	ctx.run(2)
	truthy(sign() ~= nil, "(C) the sign is up 2 s into the run")
	lastAssist = nil
	ctx.toLobby()
	eq(lastAssist and lastAssist.fails, 1, "(C) walking out under the sign added no failed attempt (still the 1 from B)")
	near(BreakRoom.signAlpha(0, CFG), 1, 1e-9, "(pure rule, for the record) the sign starts fully shown")
end

--================================================================ §7 (review fix) a paid guide: the sign stays down

-- The "Hjelp meg" guide is bought for ONE run; walking out loses it with no refund (the server tears the run's
-- instance down, and the next attempt starts without it). The adversarial review reproduced exactly that
-- under the sign's "nothing is lost". So once a guide is active the sign must not show. END TO END: the real
-- server counts the failed attempts, offers the guide, takes the coins; the real RestClient hears AssistState.
do
	-- two more counted walk-outs at L42 (B above left one): the server offers the guide after three
	for k = 1, 2 do
		start(42)
		ctx.run(0.1)
		burnReal(CFG.ServerMinRunSeconds + 0.3)
		ctx.frame(1 / 30)
		ctx.toLobby()
	end
	eq(lastAssist and lastAssist.fails, 3, "(D) three counted walk-outs at L42")
	start(42)
	ctx.run(0.5)
	eq(lastAssist and lastAssist.offered, true, "(D) the server offers the guide on this attempt")
	eq(lastAssist and lastAssist.active, false, "(D) not bought yet")
	truthy(sign() ~= nil, "(D) before buying, the sign is up (the walk-out is still free)")
	local r = RS.AssistRemotes.BuyAssist:simulateInvokeServer(ctx.plr)
	eq(r and r.ok, true, "(D) the guide is bought (" .. tostring(r and r.reason) .. ")")
	eq(lastAssist and lastAssist.active, true, "(D) the server tells the client the guide is active")
	ctx.frame(1 / 30)
	eq(sign(), nil, "(D) with a paid guide active the sign is gone at once (walking out now would lose it)")
	local reappeared = false
	ctx.run(1.0, 1 / 30, function() if sign() ~= nil then reappeared = true end end)
	eq(reappeared, false, "(D) and it does not come back during the free window")
	local coinsPaid = r and r.coins
	ctx.toLobby()
	eq(lastAssist and lastAssist.fails, 3, "(D) the quick walk-out itself still adds no failed attempt")
	start(42)
	ctx.run(0.3)
	eq(lastAssist and lastAssist.active, false, "(D) the guide did not survive the walk-out (server rule, unchanged: that is what the sign must not hide)")
	eq(lastAssist and lastAssist.coins, coinsPaid, "(D) and was not refunded")
	truthy(sign() ~= nil, "(D) a run without a guide shows the sign again")
	ctx.toLobby()
end

--================================================================ §6 the biome board

do
	local board = room.BiomeBoardPost.BiomeBoard
	local frame = board:FindFirstChildOfClass("Frame")
	local rows = {}
	for _, l in frame:GetChildren() do
		if l:IsA("TextLabel") then rows[l.LayoutOrder] = l.Text end
	end
	local B = Biomes.Bands
	eq(#rows, #B + 1, "a header and one row per biome")
	-- accepted 40 -> next level 41: dungeon, jungle and ice are reached; the forge (51) is next
	truthy(string.find(rows[2], B[1].name, 1, true) ~= nil and string.find(rows[2], "✓", 1, true) ~= nil, "the dungeon is ticked")
	truthy(string.find(rows[4], B[3].name, 1, true) ~= nil and string.find(rows[4], "✓", 1, true) ~= nil, "the ice cellar is ticked (level 41 is in it)")
	truthy(string.find(rows[5], B[4].name, 1, true) ~= nil and string.find(rows[5], "next at Level " .. B[4].from, 1, true) ~= nil,
		"the forge is shown as next, with its level")
	truthy(string.find(rows[6], "🔒", 1, true) ~= nil and string.find(rows[6], B[5].name, 1, true) == nil, "later biomes stay a secret")
end

T.finish(h)
