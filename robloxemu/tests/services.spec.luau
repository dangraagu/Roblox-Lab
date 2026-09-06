-- Tests for emu/services.luau. Run: luau tests/services.spec.luau
--
-- The DataStore block is the point of this file: UpdateAsync's transform may run more than
-- once and returning nil aborts the write. Our session-lock bug class lives exactly there.
local InstanceLib = require("../emu/instance")
local ServicesLib = require("../emu/services")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg)
	end
end
local function raises(fn, msg)
	local ok = pcall(fn)
	if not ok then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> expected an error, got none")
	end
end

-- ---------------------------------------------------------------- fake datatypes (injected)
local V3 = {}
V3.__index = V3
function V3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
local CF = {}
CF.__index = CF
function CF.new(x, y, z)
	if type(x) == "table" then
		return setmetatable({ Position = x }, CF)
	end
	return setmetatable({ Position = V3.new(x, y, z) }, CF)
end
local fakeDatatypes = {
	Vector3 = V3,
	Vector2 = {
		new = function(x, y)
			return { X = x, Y = y }
		end,
	},
	CFrame = CF,
	Color3 = {
		fromRGB = function(r, g, b)
			return { R = r, G = g, B = b }
		end,
	},
	Enum = {
		Technology = { Future = "Enum.Technology.Future" },
		PlaybackState = { Completed = "Enum.PlaybackState.Completed", Cancelled = "Enum.PlaybackState.Cancelled" },
	},
}

local instApi = InstanceLib.new({ datatypes = fakeDatatypes })
local svc = ServicesLib.new({ datatypes = fakeDatatypes, instance = instApi })
local Instance = instApi.Instance
local game = svc.game
local Players = svc.Players

-- ---------------------------------------------------------------- getService
do
	eq(game:GetService("Players"), Players, "game:GetService('Players') returns the Players service")
	eq(game:GetService("Players"), game:GetService("Players"), "GetService is a singleton")
	eq(game.Players, Players, "game.Players indexes the service")
	eq(game.Workspace, svc.workspace, "game.Workspace indexes the Workspace service")
	eq(game:GetService("ReplicatedStorage"), svc.ReplicatedStorage, "ReplicatedStorage is a container")
	eq(svc.ReplicatedStorage.ClassName, "ReplicatedStorage", "ReplicatedStorage has the right ClassName")
	eq(svc.getService("Lighting"), svc.Lighting, "svc.getService matches game:GetService")
	-- a service we did not model still EXISTS (unknown methods on it still raise)
	local cs = game:GetService("CollectionService")
	truthy(cs ~= nil, "an unmodelled service is still returned")
	eq(cs.ClassName, "CollectionService", "an unmodelled service carries its own ClassName")
	raises(function()
		return (cs :: any):NoSuchMethod()
	end, "an unknown method on a stub service raises")

	-- BindToClose
	local closed = 0
	game:BindToClose(function()
		closed += 1
	end)
	game:BindToClose(function()
		closed += 10
	end)
	svc.runBindToClose()
	eq(closed, 11, "runBindToClose runs every registered callback")
end

-- ---------------------------------------------------------------- containers
do
	local remotes = Instance.new("Folder")
	remotes.Name = "AnomalyRemotes"
	remotes.Parent = svc.ReplicatedStorage
	local state = Instance.new("RemoteEvent")
	state.Name = "State"
	state.Parent = remotes
	eq(svc.ReplicatedStorage:WaitForChild("AnomalyRemotes"), remotes, "WaitForChild works on ReplicatedStorage")
	eq(svc.ReplicatedStorage:FindFirstChild("State", true), state, "remotes nest normally")

	local part = Instance.new("Part")
	part.Parent = svc.workspace
	eq(part.Parent, svc.workspace, "instances can be parented to workspace")
	truthy(svc.workspace.CurrentCamera ~= nil, "Workspace.CurrentCamera exists")
	eq(svc.workspace.CurrentCamera.ClassName, "Camera", "CurrentCamera is a Camera")
	eq(svc.workspace.CurrentCamera.FieldOfView, 70, "the camera stub carries a FieldOfView")
	part:Destroy()
end

-- ---------------------------------------------------------------- Players
do
	local added, removingParent, removed = nil, "unset", nil
	Players.PlayerAdded:Connect(function(p)
		added = p
	end)
	Players.PlayerRemoving:Connect(function(p)
		removed = p
		removingParent = p.Parent -- Roblox: still parented while PlayerRemoving runs
	end)

	eq(Players.LocalPlayer, nil, "LocalPlayer is nil on a server")
	eq(#Players:GetPlayers(), 0, "no players before anybody joins")

	local plr = Players:simulateJoin("Alice", 42)
	eq(added, plr, "PlayerAdded fires with the joining player")
	eq(plr.Name, "Alice", "the player carries its Name")
	eq(plr.UserId, 42, "the player carries its UserId")
	eq(plr.ClassName, "Player", "simulateJoin creates a Player")
	-- THE ghost-session guard our real server relies on: `plr.Parent ~= Players`
	eq(plr.Parent, Players, "a joined player's Parent IS the Players service")
	truthy(not (plr.Parent ~= Players), "the ghost-session guard sees a live player as live")
	eq(#Players:GetPlayers(), 1, "GetPlayers lists the joined player")
	eq(Players:GetPlayers()[1], plr, "GetPlayers returns the player object")
	eq(Players:GetPlayerByUserId(42), plr, "GetPlayerByUserId finds them")
	eq(Players:GetNameFromUserIdAsync(42), "Alice", "GetNameFromUserIdAsync resolves a live player")

	-- leaderstats through the ordinary hierarchy
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local day = Instance.new("IntValue", ls)
	day.Name = "Day"
	day.Value = 1
	local best = Instance.new("IntValue", ls)
	best.Name = "Best"
	best.Value = 9
	ls.Parent = plr
	eq(plr:FindFirstChild("leaderstats"), ls, "leaderstats is found on the Player")
	eq(plr:FindFirstChild("leaderstats"):FindFirstChild("Best").Value, 9, "leaderstats values read back")

	-- character
	local char = Players:simulateSpawn(plr, svc.workspace)
	eq(plr.Character, char, "simulateSpawn sets Character")
	truthy(char:FindFirstChild("HumanoidRootPart") ~= nil, "the character has a HumanoidRootPart")
	eq(Players:GetPlayerFromCharacter(char), plr, "GetPlayerFromCharacter maps back to the player")
	local charAdded = nil
	plr.CharacterAdded:Connect(function(c)
		charAdded = c
	end)
	local char2 = Players:simulateSpawn(plr, svc.workspace)
	eq(charAdded, char2, "CharacterAdded fires on respawn")

	-- a second player, then a leave
	local bob = Players:simulateJoin("Bob", 43)
	eq(#Players:GetPlayers(), 2, "two players in game")

	Players:simulateLeave(plr)
	eq(removed, plr, "PlayerRemoving fires with the leaving player")
	eq(removingParent, Players, "PlayerRemoving runs while the player is STILL parented (Roblox order)")
	eq(plr.Parent, nil, "after simulateLeave the player's Parent is nil")
	truthy(plr.Parent ~= Players, "the ghost-session guard sees a departed player as gone")
	eq(#Players:GetPlayers(), 1, "only Bob is left")
	eq(Players:GetPlayers()[1], bob, "the remaining player is Bob")
	Players:simulateLeave(bob)
	eq(#Players:GetPlayers(), 0, "everybody has left")

	-- auto-assigned user ids stay unique
	local c1 = Players:simulateJoin("Carol")
	local c2 = Players:simulateJoin("Dave")
	truthy(c1.UserId ~= c2.UserId, "auto-assigned UserIds are unique")
	Players:simulateLeave(c1)
	Players:simulateLeave(c2)
end

-- ---------------------------------------------------------------- DataStoreService basics
local DSS = svc.DataStoreService
do
	local a = DSS:GetDataStore("Profiles")
	eq(DSS:GetDataStore("Profiles"), a, "GetDataStore returns the same store for the same name")
	truthy(DSS:GetDataStore("Other") ~= a, "different names are different stores")
	truthy(DSS:GetOrderedDataStore("Profiles") ~= a, "an ordered store is not the plain store")

	eq(a:GetAsync("missing"), nil, "an unwritten key reads back nil")
	a:SetAsync("k", { bestDay = 3 })
	eq(a:GetAsync("k").bestDay, 3, "SetAsync / GetAsync round-trip")

	-- GetAsync must hand back a COPY: mutating it cannot corrupt the store
	local got = a:GetAsync("k")
	got.bestDay = 999
	eq(a:GetAsync("k").bestDay, 3, "GetAsync returns a copy of the stored value")

	eq(a:RemoveAsync("k").bestDay, 3, "RemoveAsync returns the old value")
	eq(a:GetAsync("k"), nil, "RemoveAsync deletes the key")

	eq(a:IncrementAsync("n", 5), 5, "IncrementAsync starts from 0")
	eq(a:IncrementAsync("n", 2), 7, "IncrementAsync accumulates")

	raises(function()
		a:GetAsync(42)
	end, "a non-string key raises")
	raises(function()
		a:GetAsync(string.rep("x", 51))
	end, "a key longer than 50 chars raises")

	-- Roblox persists JSON, so the integer-key trap is reproduced faithfully
	a:SetAsync("sparse", { [1] = "a", [3] = "b" })
	local back = a:GetAsync("sparse")
	eq(back["1"], "a", "sparse integer keys come back as STRING keys (JSON round-trip)")
	eq(back[1], nil, "...and the integer key itself is gone")
	a:SetAsync("dense", { "a", "b" })
	eq(a:GetAsync("dense")[2], "b", "a dense array survives as an array")
	raises(function()
		a:SetAsync("bad", { fn = print })
	end, "an unserialisable value is refused, as in Roblox")
end

-- ---------------------------------------------------------------- UpdateAsync semantics
do
	local store = DSS:GetDataStore("UpdateSemantics")

	-- 1. normal write
	local calls = 0
	local written = store:UpdateAsync("u_1", function(old)
		calls += 1
		eq(old, nil, "the transform sees nil for an unwritten key")
		return { bestDay = 5, caught = { figure_end = true } }
	end)
	eq(calls, 1, "the happy path invokes the transform exactly once")
	eq(written.bestDay, 5, "UpdateAsync returns the committed value")
	eq(store:GetAsync("u_1").bestDay, 5, "the value is stored")
	eq(store:GetAsync("u_1").caught.figure_end, true, "nested tables are stored")

	-- 2. returning nil ABORTS the write and leaves the stored value untouched
	local abortCalls = 0
	local result = store:UpdateAsync("u_1", function(old)
		abortCalls += 1
		eq(old.bestDay, 5, "the transform sees the CURRENT stored value")
		old.bestDay = 999 -- mutate, then abort anyway
		old.caught.new_id = true
		return nil
	end)
	eq(abortCalls, 1, "an aborting transform still runs once")
	eq(result, nil, "UpdateAsync returns nil when the transform aborts")
	eq(store:GetAsync("u_1").bestDay, 5, "a nil return leaves the stored value UNCHANGED")
	eq(store:GetAsync("u_1").caught.new_id, nil, "mutations made before the abort do not leak into the store")

	-- 3. THE contract: the transform MAY be invoked more than once
	store.__retryCount = 1 -- one EXTRA invocation
	local seen = {}
	local n = 0
	local committed = store:UpdateAsync("u_1", function(old)
		n += 1
		table.insert(seen, old.bestDay)
		old.bestDay += 1
		return old
	end)
	eq(n, 2, "__retryCount = 1 invokes the transform twice")
	eq(seen[1], 5, "attempt 1 sees the stored value")
	eq(seen[2], 5, "attempt 2 sees the SAME stored value — a discarded attempt never leaks")
	eq(committed.bestDay, 6, "only the last attempt is committed (not 7)")
	eq(store:GetAsync("u_1").bestDay, 6, "the store holds exactly one increment")

	-- 3b. our session-lock pattern: flags set inside the transform must be reset per attempt
	local wrote = false
	local attempts = 0
	store:UpdateAsync("u_2", function(old)
		attempts += 1
		old = old or {}
		wrote = false -- the line the bug class forgets
		old.token = "mine"
		wrote = true
		return old
	end)
	eq(attempts, 2, "the lock-claim transform ran twice")
	eq(wrote, true, "the last attempt committed, so `wrote` is true")
	eq(store:GetAsync("u_2").token, "mine", "the lock landed")

	-- 3c. an aborting transform under retry must leave the flag false AND the store untouched
	local applied = true
	local blocked = store:UpdateAsync("u_2", function(old)
		applied = false
		old.token = "stolen"
		return nil
	end)
	eq(blocked, nil, "the aborted claim returns nil")
	eq(applied, false, "the per-attempt flag reflects the LAST attempt")
	eq(store:GetAsync("u_2").token, "mine", "an aborted claim never overwrites the lock")

	-- 3d. three invocations, to prove the knob is a count and not a boolean
	store.__retryCount = 2
	local triple = 0
	store:UpdateAsync("u_3", function(old)
		triple += 1
		return { v = triple }
	end)
	eq(triple, 3, "__retryCount = 2 invokes the transform three times")
	eq(store:GetAsync("u_3").v, 3, "the last invocation's value is what lands")
	store.__retryCount = 0

	local once = 0
	store:UpdateAsync("u_3", function()
		once += 1
		return { v = 0 }
	end)
	eq(once, 1, "clearing __retryCount restores the single-invocation happy path")

	raises(function()
		(store :: any):UpdateAsync("u_1", "not a function")
	end, "UpdateAsync refuses a non-function transform")
end

-- ---------------------------------------------------------------- failure injection
do
	local store = DSS:GetDataStore("Failures")
	store:SetAsync("u_1", { bestDay = 4 })

	store.__failNext = true
	local ok = pcall(function()
		return store:GetAsync("u_1")
	end)
	eq(ok, false, "__failNext makes the next call raise")
	eq(store.__failNext, false, "__failNext clears itself")
	local ok2 = pcall(function()
		return store:GetAsync("u_1")
	end)
	eq(ok2, true, "__failNext is one-shot")

	-- the real path: a failed load must NOT be mistaken for "no data" (canSave stays false)
	store.__failNext = true
	local loadOk = pcall(function()
		return store:UpdateAsync("u_1", function(old)
			old = old or {}
			old.lock = { token = "mine" }
			return old
		end)
	end)
	eq(loadOk, false, "an injected failure surfaces as a failed pcall -> canSave = false")
	eq(store:GetAsync("u_1").lock, nil, "the failed call wrote nothing")
	eq(store:GetAsync("u_1").bestDay, 4, "the real data is untouched by a failed call")

	store.__failAll = true
	eq(
		pcall(function()
			return store:GetAsync("u_1")
		end),
		false,
		"__failAll keeps failing"
	)
	eq(
		pcall(function()
			return store:SetAsync("u_1", 1)
		end),
		false,
		"__failAll covers SetAsync too"
	)
	store.__failAll = false
	eq(
		pcall(function()
			return store:GetAsync("u_1")
		end),
		true,
		"clearing __failAll restores the store"
	)

	store.__failMessage = "outage"
	store.__failNext = true
	local _, err = pcall(function()
		return store:GetAsync("u_1")
	end)
	eq(err, "outage", "__failMessage controls the raised message")
	store.__failMessage = nil
end

-- ---------------------------------------------------------------- OrderedDataStore
do
	local board = DSS:GetOrderedDataStore("BestDay")
	board:SetAsync("u_1", 12)
	board:SetAsync("u_2", 40)
	board:SetAsync("u_3", 7)

	local pages = board:GetSortedAsync(false, 10)
	local page = pages:GetCurrentPage()
	eq(#page, 3, "GetCurrentPage returns every entry that fits")
	eq(page[1].key, "u_2", "descending: the highest value is first")
	eq(page[1].value, 40, "entries carry their value")
	eq(page[3].key, "u_3", "descending: the lowest value is last")
	eq(pages.IsFinished, true, "a single page is already finished")

	local asc = board:GetSortedAsync(true, 10):GetCurrentPage()
	eq(asc[1].key, "u_3", "ascending: the lowest value is first")
	eq(asc[3].key, "u_2", "ascending: the highest value is last")

	local paged = board:GetSortedAsync(false, 2)
	eq(#paged:GetCurrentPage(), 2, "pageSize caps the page")
	eq(paged.IsFinished, false, "there is another page")
	paged:AdvanceToNextPageAsync()
	eq(#paged:GetCurrentPage(), 1, "the second page holds the remainder")
	eq(paged.IsFinished, true, "the listing is finished")

	eq(board:GetAsync("u_2"), 40, "an ordered store still reads back by key")
	raises(function()
		board:SetAsync("u_4", 1.5)
	end, "an OrderedDataStore refuses a non-integer value")
end

-- ---------------------------------------------------------------- Lighting
do
	local Lighting = svc.Lighting
	eq(Lighting.ClassName, "Lighting", "Lighting exists")
	eq(Lighting.Brightness, 2, "Lighting has a default Brightness")
	truthy(Lighting.Ambient ~= nil, "Lighting has a default Ambient from the injected Color3")
	eq(Lighting.Technology, "Enum.Technology.Future", "Lighting.Technology comes from the injected Enum")

	Lighting.Ambient = fakeDatatypes.Color3.fromRGB(20, 22, 30)
	Lighting.Brightness = 1
	Lighting.ClockTime = 0.2
	Lighting.FogEnd = 120
	Lighting.ExposureCompensation = -0.15
	eq(Lighting.Ambient.R, 20, "Lighting holds an assigned Ambient")
	eq(Lighting.Brightness, 1, "Lighting holds an assigned Brightness")
	eq(Lighting.ClockTime, 0.2, "Lighting holds an assigned ClockTime")
	eq(Lighting.FogEnd, 120, "Lighting holds an assigned FogEnd")

	-- Fx parents post-processing children into Lighting
	local atmo = Instance.new("Atmosphere")
	atmo.Name = "FxAtmosphere"
	atmo.Density = 0.42
	atmo.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "FxBloom"
	bloom.Parent = Lighting
	eq(Lighting:FindFirstChild("FxAtmosphere"), atmo, "Lighting parents an Atmosphere")
	eq(Lighting:FindFirstChild("FxAtmosphere").Density, 0.42, "the Atmosphere holds its properties")
	eq(Lighting:FindFirstChild("FxBloom").ClassName, "BloomEffect", "Lighting parents post-fx")
	atmo:Destroy()
	eq(Lighting:FindFirstChild("FxAtmosphere"), nil, "Fx can remove a preset's children again")
	bloom:Destroy()
end

-- ---------------------------------------------------------------- RunService
do
	local rs = svc.RunService
	eq(rs:IsServer(), true, "RunService:IsServer() is true")
	eq(rs:IsClient(), false, "RunService:IsClient() is false")
	eq(rs:IsStudio(), false, "RunService:IsStudio() is false")
	eq(rs:IsRunning(), true, "RunService:IsRunning() is true")

	local beats = 0
	rs.Heartbeat:Connect(function(dt)
		beats += dt
	end)
	rs.Heartbeat:Fire(0.5)
	rs.Heartbeat:Fire(0.25)
	eq(beats, 0.75, "Heartbeat is a real signal a scheduler can drive")
	truthy(rs.RenderStepped ~= nil, "RenderStepped exists")

	local ok = pcall(function()
		rs:BindToRenderStep("x", 1, function() end)
		rs:UnbindFromRenderStep("x")
	end)
	truthy(ok, "BindToRenderStep / UnbindFromRenderStep are no-ops")

	rs:setIsServer(false)
	eq(rs:IsClient(), true, "setIsServer(false) flips the context for client scripts")
	rs:setIsServer(true)
	eq(rs:IsServer(), true, "the context flips back")
end

-- ---------------------------------------------------------------- TweenService
do
	local ts = svc.TweenService
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = "start"

	local completed = 0
	local completedState = nil
	local tween = ts:Create(frame, { Time = 0.4 }, { BackgroundTransparency = 0, Size = "goal" })
	tween.Completed:Connect(function(state)
		completed += 1
		completedState = state
	end)
	eq(frame.BackgroundTransparency, 1, "Create does not apply anything yet")
	tween:Play()
	eq(frame.BackgroundTransparency, 0, "Play applies the goal properties immediately")
	eq(frame.Size, "goal", "Play applies every goal property")
	eq(completed, 1, "Play fires Completed once")
	eq(completedState, "Enum.PlaybackState.Completed", "Completed carries the injected PlaybackState")
	eq(#ts:getCreated(), 1, "TweenService records the tweens it created")
end

-- ---------------------------------------------------------------- HttpService
do
	local http = svc.HttpService
	local g1 = http:GenerateGUID(false)
	local g2 = http:GenerateGUID(false)
	eq(type(g1), "string", "GenerateGUID returns a string")
	truthy(g1 ~= g2, "GenerateGUID never repeats")
	eq(#g1, 36, "a braceless GUID is 36 chars")
	eq(string.sub(http:GenerateGUID(), 1, 1), "{", "GenerateGUID() defaults to braces")
	eq(string.sub(http:GenerateGUID(true), 1, 1), "{", "GenerateGUID(true) uses braces")

	eq(http:JSONEncode({ a = 1 }), '{"a":1}', "JSONEncode writes an object")
	eq(http:JSONEncode({ 1, 2, 3 }), "[1,2,3]", "JSONEncode writes an array")
	eq(http:JSONEncode({}), "[]", "an empty table encodes as an array, like Roblox")
	eq(http:JSONEncode("a\"b"), '"a\\"b"', "JSONEncode escapes quotes")
	eq(http:JSONDecode('{"a":1,"b":[true,null,"x"]}').a, 1, "JSONDecode reads a number")
	eq(http:JSONDecode('{"a":1,"b":[true,null,"x"]}').b[1], true, "JSONDecode reads a boolean")
	local round = http:JSONDecode(http:JSONEncode({ day = 7, caught = { "a", "b" }, ok = false }))
	eq(round.day, 7, "JSON round-trips numbers")
	eq(round.caught[2], "b", "JSON round-trips arrays")
	eq(round.ok, false, "JSON round-trips false")
	eq(http:JSONDecode("[1.5,-2]")[1], 1.5, "JSONDecode reads floats")
	eq(http:JSONDecode("[1.5,-2]")[2], -2, "JSONDecode reads negatives")
	raises(function()
		return http:JSONDecode("{oops}")
	end, "JSONDecode raises on malformed input")
	raises(function()
		return http:GetAsync("https://example.com")
	end, "HttpService:GetAsync raises (no network headlessly)")
end

-- ---------------------------------------------------------------- inert stubs
do
	for _, name in
		{
			"TextChatService",
			"UserInputService",
			"TextService",
			"SoundService",
			"PathfindingService",
			"MarketplaceService",
			"BadgeService",
		}
	do
		local s = game:GetService(name)
		truthy(s ~= nil, name .. " exists")
		eq(s.ClassName, name, name .. " reports its ClassName")
	end

	-- the few stub methods our games actually call
	local sound = Instance.new("Sound")
	sound.Parent = game:GetService("SoundService")
	eq(sound.Parent, svc.services.SoundService, "SoundService accepts children")

	local cmd = Instance.new("Folder")
	cmd.Name = "BroadcastCommand"
	cmd.Parent = game:GetService("TextChatService")
	eq(game:GetService("TextChatService"):WaitForChild("BroadcastCommand", 20), cmd, "TextChatService holds children")

	local filtered = game:GetService("TextService"):FilterStringAsync("hei", 1)
	eq(filtered:GetNonChatStringForBroadcastAsync(), "hei", "TextService returns the text unchanged")

	local path = game:GetService("PathfindingService"):CreatePath({ AgentRadius = 2 })
	path:ComputeAsync()
	eq(#path:GetWaypoints(), 0, "the pathfinding stub yields no waypoints")

	eq(game:GetService("MarketplaceService"):UserOwnsGamePassAsync(1, 2), false, "nobody owns a gamepass")
	eq(game:GetService("BadgeService"):AwardBadge(1, 2), true, "AwardBadge succeeds inertly")
	eq(game:GetService("UserInputService"):IsKeyDown("E"), false, "no key is down headlessly")
end

-- ---------------------------------------------------------------- self-contained construction
do
	-- No `instance` in deps: services must build its own from ./instance, with its own
	-- private world (so two harness runs cannot bleed into each other).
	local solo = ServicesLib.new({ datatypes = fakeDatatypes })
	truthy(solo.game ~= nil, "services.new works without an injected instance module")
	truthy(solo.Players ~= Players, "a second services world has its own Players")
	local p = solo.Players:simulateJoin("Solo", 1)
	eq(p.Parent, solo.Players, "the second world parents its own players")
	eq(#Players:GetPlayers(), 0, "the first world is unaffected")

	local store = solo.DataStoreService:GetDataStore("Profiles")
	eq(store:GetAsync("k"), nil, "the second world's DataStore starts empty")
end

print(string.format("services: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("services tests failed")
end
