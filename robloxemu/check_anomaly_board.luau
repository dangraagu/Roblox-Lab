-- anomaly-observatory — the Field Guide highscore board (queued job A; owner design 2026-09-16).
-- Run: luau check_anomaly_board.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- The design, as approved: rank on Field Guide completion (anomaly TYPES caught, 0..24), ties broken by
-- the EARLIEST time the player reached that count. A new OrderedDataStore (not the Best-Day store), key
-- u_<userId>, value caught * 2e9 + (2e9 - reachedAtUnix), written only when the count goes up, reachedAt
-- kept in the profile. The public board is GetSortedAsync(false, 10) cached ~60 s on the server; the
-- friends board is Players:GetFriendsAsync then GetAsync per friend, only when the player asks, cached
-- per player, capped at 200, all pcall'd. A physical sign at the start pad with a ProximityPrompt
-- toggles the two. Names come from GetNameFromUserIdAsync, cached in memory, never stored.
--
-- Played through the real server, with the stores seeded and Players:GetFriendsAsync stubbed (robloxemu
-- has no friends API). Asserted:
--   1. the sign: a part near the start pad, facing into the hall, with a prompt; out of the capture rig's
--      frame and out of the hero thumbnail's frame (the board changes, and neither photo may);
--   2. the public board: order (more types first, then who got there first), names, "n/24", at most 10
--      rows; a fabricated value above 24 and a foreign key never appear;
--   3. the prompt toggles to FRIENDS and back; the friends board lists the player's friends with scores,
--      sorted the same way, and the player too once they have caught something;
--   4. an empty friends board says something useful (friends but no scores; no friends; Roblox down); a
--      friend's fabricated value above 24 shows at most 24 there too (2026-10-01: GetAsync has no window);
--   5. at most 200 friends are looked up, however many there are; the public list is fetched at most
--      once a minute however often the sign is used; the friends list once per player per cache window;
--   6. the store is written only when the count goes UP, with reachedAt recorded in the profile; a
--      profile carrying ids the catalog does not know can never publish more than 24;
--   7. no name is ever stored: the board store holds numbers only, and no friend's name is in any record.

local Harness = require("./emu/harness")
local Highscore = require("../anomaly-observatory/src/shared/Highscore")

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { 1920, 1080 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local DSS = h.game:GetService("DataStoreService")
-- the game's own Config (the module instance the server requires)
local ConfigHolder = h.ReplicatedStorage:FindFirstChild("Config")
local Config = h:_require(ConfigHolder)
truthy(type(Config.Save.GuideStore) == "string" and Config.Save.GuideStore ~= Config.Save.LeaderStore,
	"the board has its OWN ordered store (" .. tostring(Config.Save.GuideStore) .. "), not the Best-Day one")
local guide = DSS:GetOrderedDataStore(Config.Save.GuideStore or "?")
local profiles = DSS:GetDataStore(Config.Save.Store)
local CAP = #Config.Anomaly.Catalog
local T0 = 1790000000

-- count the calls the server makes on the board store
local calls = { sorted = 0, get = 0, set = 0, attempt = 0 }
do
	local g, s, u, srt = guide.GetAsync, guide.SetAsync, guide.UpdateAsync, guide.GetSortedAsync
	rawset(guide, "GetAsync", function(self, ...) calls.get += 1; return g(self, ...) end)
	-- a write is a SetAsync or an UpdateAsync that commits
	rawset(guide, "SetAsync", function(self, ...) calls.set += 1; return s(self, ...) end)
	rawset(guide, "UpdateAsync", function(self, ...)
		calls.attempt += 1 -- a request spent, committed or not
		local out = u(self, ...)
		if out ~= nil then calls.set += 1 end
		return out
	end)
	rawset(guide, "GetSortedAsync", function(self, ...) calls.sorted += 1; return srt(self, ...) end)
end

-- seed the public board
local function put(uid, caught, at) guide.__data[Highscore.key(uid)] = Highscore.encode(caught, at, CAP) end
put(7001, 20, T0 + 100)
put(7002, 20, T0 + 5) -- same count, reached earlier: ranks above 7001
put(7003, 24, T0 + 900)
guide.__data["u_7004"] = 99 * Highscore.SCALE + 12345 -- fabricated: above the cap
guide.__data["x_5"] = 21 * Highscore.SCALE -- a foreign key
put(7005, 3, T0)
for i = 1, 10 do put(7100 + i, 1, T0 + i) end

-- friends, per player (robloxemu has no friends API; the server calls Players:GetFriendsAsync)
local FRIENDS: { [number]: any } = {}
local friendsCalls = 0
local function pagesOf(list)
	local size = 50
	local pages = {}
	for i = 1, #list, size do
		local page = {}
		for j = i, math.min(i + size - 1, #list) do
			table.insert(page, { Id = list[j], Username = "Friend" .. list[j], DisplayName = "F" .. list[j], IsOnline = false })
		end
		table.insert(pages, page)
	end
	if #pages == 0 then table.insert(pages, {}) end
	local p = { __i = 1, IsFinished = #pages <= 1 }
	function p.GetCurrentPage(self) return pages[self.__i] end
	function p.AdvanceToNextPageAsync(self)
		self.__i += 1
		self.IsFinished = self.__i >= #pages
	end
	return p
end
h.Players.GetFriendsAsync = function(_, userId)
	friendsCalls += 1
	local f = FRIENDS[userId]
	if f == "error" then error("HTTP 503 (Service Unavailable)", 0) end
	return pagesOf(f or {})
end

assert(h:tryRun("server/Main.server"))

local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function boardOf(plr)
	local m = h.workspace:FindFirstChild("GuideBoard_" .. plr.UserId)
	return m and m:FindFirstChild("Board")
end
local function guiOf(plr)
	local b = boardOf(plr)
	return b and b:FindFirstChildOfClass("SurfaceGui")
end
local function textOf(plr, name: string): string
	local g = guiOf(plr)
	local d = g and g:FindFirstChild(name, true)
	return d and d.Text or "(no " .. name .. ")"
end
local function rows(plr): { string }
	local out = {}
	for i = 1, 10 do
		local t = textOf(plr, "Row" .. i)
		if t ~= "" and string.sub(t, 1, 4) ~= "(no " then table.insert(out, t) end
	end
	return out
end
local function toggle(plr)
	local prompt = boardOf(plr):FindFirstChildOfClass("ProximityPrompt")
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
	h:advance(0.6)
end

--============================================================ 1. the sign
FRIENDS[5001] = { 7002, 7005, 8000 } -- 8000 has no score
local p = h:join("Sam", 5001)
h:advance(0.5)
local zone = h.workspace:FindFirstChild("Concourse_" .. p.UserId)
local pad = zone:FindFirstChild("StartPad")
local O = pad.Position - Vector3.new(0, 1, -4) -- the pad sits at origin + (0, 1, -4)
local board = boardOf(p)
truthy(board ~= nil and board:IsA("BasePart"), "the player has a Field Guide sign (GuideBoard_<userId>.Board)")
local prompt = board and board:FindFirstChildOfClass("ProximityPrompt")
truthy(prompt ~= nil, "the sign carries a ProximityPrompt")
if board then
	local spawnRoot = O + Vector3.new(0, 4, -4)
	local dist = (board.Position - spawnRoot).Magnitude
	truthy(prompt ~= nil and dist <= prompt.MaxActivationDistance,
		string.format("the prompt reaches the spawn point (%.1f studs, reach %s)", dist, tostring(prompt and prompt.MaxActivationDistance)))
	truthy(board.Parent ~= nil and not board:IsDescendantOf(zone), "the sign is not part of the hall that is rebuilt every pass")
	local g = guiOf(p)
	-- On the part, not in PlayerGui: robloxemu's HUD gate walks every child of PlayerGui as a SCREEN
	-- panel, and Roblox's own pattern for a physical board is a SurfaceGui on the part.
	truthy(g ~= nil and g:IsA("SurfaceGui"), "the sign carries a SurfaceGui")
	eq(g and g.Face, Enum.NormalId.Left, "facing into the hall (the sign's -X face; the sign hangs on the right-hand wall)")
	truthy(board.Position.X - O.X > 8.5 and board.Position.X - O.X < 9.5, "on the right-hand wall's inner face")

	-- out of the two photographs: every corner outside the frame
	local function outOfFrame(from: Vector3, at: Vector3, fov: number, aspect: number): (boolean, string)
		local cf = CFrame.lookAt(from, at)
		local tv = math.tan(math.rad(fov) / 2)
		local s = board.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = board.CFrame:PointToWorldSpace(Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
					local q = cf:PointToObjectSpace(w)
					if q.Z < 0 then
						local nx, ny = (q.X / -q.Z) / (tv * aspect), (q.Y / -q.Z) / tv
						if math.abs(nx) <= 1 and math.abs(ny) <= 1 then
							return false, string.format("corner in frame at sx %+.2f sy %+.2f", nx, ny)
						end
					end
				end
			end
		end
		return true, ""
	end
	-- tools/film_anomaly.py camera_for(): origin + (0, 7.5, 4) looking at origin + (0, 7.5, -86); its
	-- captures run as wide as 1920x798 (2.41:1), Studio's default 70 degrees
	local ok1, why1 = outOfFrame(O + Vector3.new(0, 7.5, 4), O + Vector3.new(0, 7.5, -86), 70, 2.41)
	truthy(ok1, "the sign is out of the capture rig's frame (the pairs must not differ by a scoreboard) " .. why1)
	-- EYECANDY.md §9 shot 1 (marketing/ShotList.luau): FROM (2, 5.5, -2) AT (-12, 21, 96), 1920x1080
	local ok2, why2 = outOfFrame(O + Vector3.new(2, 5.5, -2), O + Vector3.new(-12, 21, 96), 70, 16 / 9)
	truthy(ok2, "and out of the hero thumbnail's frame (no player names in a thumbnail) " .. why2)
end

--============================================================ 2. the public board
local r = rows(p)
print("   public: " .. table.concat(r, " | "))
truthy(string.find(textOf(p, "Mode"), "PUBLIC", 1, true) ~= nil, "the sign starts on the PUBLIC board: " .. textOf(p, "Mode"))
-- GetSortedAsync(false, 10) as designed: ten entries come back, and the foreign key "x_5" (seeded inside
-- the window, at 21) is one of them and is skipped, so this seed shows nine
eq(#r, 9, "ten entries fetched, the foreign key skipped: nine rows")
truthy(r[1] ~= nil and string.find(r[1], "User_7003", 1, true) ~= nil and string.find(r[1], "24/" .. CAP, 1, true) ~= nil,
	"first: the player with all " .. CAP .. " types (" .. tostring(r[1]) .. ")")
truthy(r[2] ~= nil and string.find(r[2], "User_7002", 1, true) ~= nil and r[3] ~= nil and string.find(r[3], "User_7001", 1, true) ~= nil,
	"then, at 20 each, the one who reached 20 FIRST (" .. tostring(r[2]) .. " / " .. tostring(r[3]) .. ")")
truthy(r[4] ~= nil and string.find(r[4], "3/" .. CAP, 1, true) ~= nil, "then 3 types (" .. tostring(r[4]) .. ")")
local shown = table.concat(r, "\n")
truthy(string.find(shown, "7004", 1, true) == nil, "a fabricated value above " .. CAP .. " is never shown")
truthy(string.find(shown, "x_5", 1, true) == nil and string.find(shown, "21/", 1, true) == nil, "nor a foreign key's value")
local over = false
for _, line in r do
	local n = tonumber(string.match(line, "(%d+)/%d+%s*$"))
	if n == nil or n > CAP then over = true end
end
truthy(not over, "no row shows more than " .. CAP .. " types")
eq(calls.sorted, 1, "the public list was fetched once")

--============================================================ 3. friends and back
toggle(p)
local fr = rows(p)
print("   friends: " .. table.concat(fr, " | ") .. " / status: " .. textOf(p, "Status"))
truthy(string.find(textOf(p, "Mode"), "FRIENDS", 1, true) ~= nil, "the prompt switches the sign to FRIENDS: " .. textOf(p, "Mode"))
eq(#fr, 2, "two friends have caught something")
truthy(fr[1] ~= nil and string.find(fr[1], "User_7002", 1, true) ~= nil and fr[2] ~= nil and string.find(fr[2], "User_7005", 1, true) ~= nil,
	"sorted like the public board: " .. table.concat(fr, " | "))
truthy(string.find(prompt.ActionText, "ublic", 1, true) ~= nil, "the prompt now offers the public board: " .. prompt.ActionText)
toggle(p)
truthy(string.find(textOf(p, "Mode"), "PUBLIC", 1, true) ~= nil, "and back to PUBLIC")
eq(#rows(p), 9, "with its rows")
for _ = 1, 6 do toggle(p) end
eq(calls.sorted, 1, "used eight times within the minute, the public list is still fetched only once")
eq(friendsCalls, 1, "and the friends list once (cached for this player)")
-- the cache window is wall-clock (os.clock); shortened to 1 s in memory, this run only
local keep = Config.Guide.PublicCacheSeconds
Config.Guide.PublicCacheSeconds = 1
realWait(1.2)
toggle(p) -- friends
toggle(p) -- public, after the window
eq(calls.sorted, 2, "once the window has passed the public list is fetched again")
Config.Guide.PublicCacheSeconds = keep

--============================================================ 4. empty friends boards say something useful
FRIENDS[5002] = { 8001, 8002 } -- friends, none with a score
local q1 = h:join("Quiet", 5002)
h:advance(0.5)
toggle(q1)
eq(#rows(q1), 0, "no friend has caught anything: no rows")
local st1 = textOf(q1, "Status")
truthy(string.find(st1, "None of your friends", 1, true) ~= nil and string.find(st1, tostring(CAP), 1, true) ~= nil,
	"and the sign says so, and what there is to find: " .. st1)
FRIENDS[5003] = {}
local q2 = h:join("Lonely", 5003)
h:advance(0.5)
toggle(q2)
local st2 = textOf(q2, "Status")
truthy(string.find(st2, "Add friends", 1, true) ~= nil, "no friends at all: it says how to fill it: " .. st2)
FRIENDS[5004] = "error"
local q3 = h:join("Offline", 5004)
h:advance(0.5)
toggle(q3)
local st3 = textOf(q3, "Status")
truthy(string.find(string.lower(st3), "try again", 1, true) ~= nil, "Roblox's friends service down: it says so and to try again: " .. st3)
truthy(not h:hadErrors(), "a failing friends call errors nothing")
-- (2026-10-01) The 24 cap on the FRIENDS board. The public board never fetches a value above the cap (its
-- query window), but the friends board reads each friend with GetAsync, outside any window, so the cap has to
-- hold in the decode. 7004 is the fabricated value seeded above (99 types; only a tampered store holds that).
FRIENDS[5008] = { 7004 }
local q5 = h:join("Trusting", 5008)
h:advance(0.5)
toggle(q5)
local fr5 = rows(q5)
print("   a fabricated friend: " .. table.concat(fr5, " | "))
local overF = #fr5 == 0
for _, r in fr5 do
	local n = tonumber(string.match(r, "(%d+)/%d+$"))
	if n == nil or n > CAP then overF = true end
end
truthy(not overF, "a friend's fabricated value is never shown above " .. CAP .. " types on the friends board: " .. table.concat(fr5, " | "))

--============================================================ 5. at most 200 friends are looked up
local many = {}
for i = 1, 300 do table.insert(many, 90000 + i) end
FRIENDS[5005] = many
local q4 = h:join("Popular", 5005)
h:advance(0.5)
local before = calls.get
toggle(q4)
h:advance(2)
eq(calls.get - before, 200, "300 friends: exactly the first 200 are looked up")

--============================================================ 6. writes: only when the count goes up
local A = Config.Anomaly
local orig = {}
for k, v in A do orig[k] = v end
-- Force the next roll to `id` WITHOUT shrinking the catalog (the board counts known ids and caps at the
-- catalog's size): move it to the front and make the day's pool one entry long, chance 1.
local function force(id: string)
	local list = {}
	for _, e in orig.Catalog do
		if e.id == id then table.insert(list, 1, e) else table.insert(list, e) end
	end
	A.Catalog = list
	A.StartPool, A.PoolPerDay, A.BaseChance, A.ChancePerDay, A.MaxChance = 1, 0, 1, 0, 1
end
force("door_extra") -- before the join, so the very first pass is the one to catch
local w = h:join("Watcher", 5006)
h:advance(0.5)
local function catchIt(plr)
	local z = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
	local pr = z:FindFirstChild("BackPad"):FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8)
	local co = coroutine.create(function() pr.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
	h:advance(0.2)
end
local function storedCount(uid): (number?, number?)
	local v = guide.__data[Highscore.key(uid)]
	if v == nil then return nil, nil end
	return Highscore.decode(v, CAP)
end
eq(storedCount(5006), nil, "a player who has caught nothing is not on the board")
local tBefore = os.time()
local setBefore = calls.set
catchIt(w) -- door_extra caught
local c1, at1 = storedCount(5006)
eq(c1, 1, "catching a NEW type writes the board at once")
h:advance(Config.Save.AutosaveSeconds + 1) -- the profile itself is written by the autosave
local rec = profiles.__data["u_5006"]
truthy(rec ~= nil and type(rec.guide) == "table" and rec.guide.at == at1 and at1 >= tBefore,
	"and the time it was reached is recorded in the profile (" .. tostring(rec and rec.guide and rec.guide.at) .. " = " .. tostring(at1) .. ")")
local setsAfterNew = calls.set
catchIt(w) -- door_extra again
eq(calls.set, setsAfterNew, "catching a type already in the Field Guide writes nothing")
eq((storedCount(5006)), c1, "and the count stays")
local attemptsBefore = calls.attempt
h:advance(Config.Save.AutosaveSeconds + 1)
eq(calls.attempt, attemptsBefore, "and the autosave after it spends no request on the board store (nothing new to write)")
force("scope_gone")
catchIt(w) -- the pass already live was rolled before the switch: door_extra, known, writes nothing
eq(calls.set, setsAfterNew, "(the pass rolled before the switch is door_extra again: no write)")
catchIt(w) -- scope_gone: a second type (the throttle may defer the write to the autosave)
h:advance(Config.Save.AutosaveSeconds + 1)
local c2, at2 = storedCount(5006)
eq(c2, c1 + 1, "a second new type raises the board by one")
truthy(at2 ~= nil and at2 >= at1, "with its own (later or equal) reachedAt")
eq(calls.set - setBefore, 2, "one write per increase (two increases, two writes)")
for k, v in orig do A[k] = v end

-- a profile carrying 30 ids, 6 of them unknown to this catalog, publishes exactly the catalog's size
do
	local caught = {}
	for _, e in orig.Catalog do caught[e.id] = true end
	for i = 1, 6 do caught["retired_anomaly_" .. i] = true end
	profiles.__data["u_5007"] = { bestDay = 3, caught = caught, hintTokens = 1, redeemed = {}, tint = "white", ownedTints = { white = true } }
	local x = h:join("Veteran", 5007)
	h:advance(0.5)
	h:advance(Config.Save.AutosaveSeconds + 1)
	local cx = storedCount(5007)
	eq(cx, CAP, "a profile with 30 ids (6 retired) publishes " .. CAP .. ", never more")
	local raw = guide.__data["u_5007"]
	truthy(raw ~= nil and raw <= select(2, Highscore.range(CAP)), "and the raw value is inside the board's window")
	h:leave(x)
end

--============================================================ 7. names are never stored
do
	local numbersOnly = true
	for k, v in guide.__data do
		if type(v) ~= "number" then numbersOnly = false end
	end
	truthy(numbersOnly, "the board store holds numbers only")
	local leaked = {}
	local function scan(t, path)
		for k, v in t do
			if type(v) == "table" then scan(v, path .. "." .. tostring(k))
			elseif type(v) == "string" and (string.find(v, "User_", 1, true) or string.find(v, "Friend", 1, true)) then
				table.insert(leaked, path .. "." .. tostring(k) .. " = " .. v)
			end
		end
	end
	scan(profiles.__data, "profiles")
	eq(#leaked, 0, "no name is stored in any profile: " .. table.concat(leaked, "; "))
	local best = DSS:GetOrderedDataStore(Config.Save.LeaderStore)
	local bestOk = true
	for _, v in best.__data do
		if type(v) ~= "number" or v > Config.Progression.MaxDay then bestOk = false end
	end
	truthy(bestOk, "the Best-Day store still holds Best Days (unchanged)")
end

truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomaly_board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly board check failed", 0)
end
