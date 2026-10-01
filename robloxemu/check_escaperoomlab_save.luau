-- Escape Room Lab — saving, the session lock, and the Star Board's writes (DESIGN.md §11, §12.1).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_save.luau 2>&1
--
--   * a profile saves with string room keys, the stars kept per room (best only), and a rejoin gets them
--     back, with Continue at the frontier;
--   * the board is written only after the profile write carrying the new total has landed, only when
--     the total improves, and never lowered (the transform keeps max(old, new));
--   * the tie-break: equal stars rank by who reached them first;
--   * every write carries this session's token: a record another server has taken is never written,
--     canSave goes false and the player is told;
--   * a lock held elsewhere: the player is told, plays, and the load is retried; the progress made
--     meanwhile is merged when the lock frees;
--   * the transforms survive UpdateAsync running them more than once (retry injection);
--   * a store that fails: the player plays with defaults and is told; the board says it is unavailable;
--   * a load that fails ONCE (a throttle, a 5xx) is retried on the autosave tick and the progress made
--     meanwhile is merged (review 2026-10-01: one failed call used to cost the whole session);
--   (a save in flight while the player leaves: check_escaperoomlab_release.luau, which needs its own world)

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local NOW = os.time()
local w = Lib.boot({ name = "escape-room-lab-save", preload = {
	-- a lock held by another server, still valid for 100 s
	[5302] = { best = { ["1"] = 3 }, starsAt = NOW - 1000, escapedAt = 0, boarded = 3, rooms = 1 },
	-- a veteran whose first load call fails once
	[5304] = { best = { ["1"] = 2, ["2"] = 3, ["3"] = 3, ["4"] = 2 }, starsAt = NOW - 5000, escapedAt = 0, boarded = 10, rooms = 4 },
} })
local h, ws = w.h, w.ws
local DSS = h.services.DataStoreService
local store = DSS:GetDataStore("EscapeRoomLab_v1")
local boardStore = DSS:GetOrderedDataStore("EscapeRoomLab_Stars_v1")
local Board, Config = w.mod("Board"), w.Config
store.__retryCount = 2 -- every UpdateAsync transform runs three times; only the last counts
do
	local rec = store.__data["u_5302"]
	rec.lock = { session = "someone-else", ["until"] = NOW + 100 }
end
local function step() h:advance(0.1) end
local LOAD_RETRY = (Config.Save.Text or {}).LoadRetry or "<Config.Save.Text.LoadRetry is missing>"
local function playRooms(p, n)
	for _ = 1, n do
		Lib.solveRoom(w, p, step)
		h:advance(0.5)
		Lib.next(w, p)
		h:advance(Config.Lift.RideSeconds + 0.5)
	end
end

--============================================================ 1. a fresh player: save, board, rejoin
local a = Lib.player(w, "Ada", 5301)
h:advance(1)
local prof = Lib.last(w, "Profile", a.plr)
eq(prof.canSave, true, "a fresh profile can save (the lock is ours)")
Lib.intoSoloLift(w, a)
h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
playRooms(a, 2)
h:advance(Config.Save.CoalesceSeconds + 1)
local rec = store.__data["u_5301"]
truthy(rec and rec.data and rec.data.best["1"] == 3 and rec.data.best["2"] == 3, "rooms 1 and 2 saved with 3 stars each, under STRING keys")
eq(rec.data.best[1], nil, "no integer keys in the stored record")
local boardValue = boardStore.__data[Board.key(5301)]
eq(Board.metricOf(boardValue), 6, "the board holds Ada's 6 stars")
local _, reachedAt = Board.decode(boardValue)
eq(reachedAt, rec.data.starsAt, "stamped with the time the profile says the total was reached")
eq(rec.data.boarded, 6, "and the profile remembers what it boarded (after the next write)")
-- a worse replay changes nothing on the board: the lift's Continue is room 3, so replay via a new
-- profile state is not possible here; instead the transform itself is fed a lower total
do
	local old = boardStore.__data[Board.key(5301)]
	boardStore:UpdateAsync(Board.key(5301), function(o) return Board.keepHigher(o, Board.encode(4, NOW + 50, Config.Board)) end)
	eq(boardStore.__data[Board.key(5301)], old, "a lower total never replaces a higher one (keep max)")
	boardStore:UpdateAsync(Board.key(5301), function(o) return Board.keepHigher(o, Board.encode(6, NOW + 50, Config.Board)) end)
	eq(boardStore.__data[Board.key(5301)], old, "the same total reached later never replaces the first reach")
end
-- a stale board write never lowers a rank: the board already holds MORE for Ada (another server got
-- there first); her next escape writes through the real server path and must keep the higher value
do
	local higher = Board.encode(30, NOW - 10, Config.Board)
	boardStore.__data[Board.key(5301)] = higher
	playRooms(a, 1)
	h:advance(Config.Save.CoalesceSeconds + 1)
	eq(store.__data["u_5301"].data.best["3"], 3, "room 3 saved")
	eq(boardStore.__data[Board.key(5301)], higher, "the server's board write kept max(old, new): 30 stars stay 30")
	boardStore.__data[Board.key(5301)] = Board.encode(9, NOW, Config.Board)
end
-- rejoin
h:leave(a.plr)
h:advance(0.5)
local released = store.__data["u_5301"]
eq(released.lock["until"], 0, "leaving releases the lock (until = 0)")
local a2 = Lib.player(w, "Ada", 5301)
h:advance(1)
local prof2 = Lib.last(w, "Profile", a2.plr)
eq(prof2.stars, 9, "a rejoin gets the 9 stars back")
eq(prof2.frontier, 4, "and the frontier: room 4")
eq(prof2.continue, 4, "Continue walks on to room 4")
eq(a2.plr.leaderstats.Stars.Value, 9, "leaderstats shows 9")

--============================================================ 2. a record another server takes over
store.__data["u_5301"].lock.session = "another-server"
store.__data["u_5301"].lock["until"] = os.time() + 1000
local n0 = #w.R.Notice:sentTo(a2.plr)
h:advance(Config.Save.AutosaveSeconds + 1)
local told = false
for _, pl in Lib.noticesSince(w, a2.plr, n0) do
	if string.find(tostring(pl.text), "another server", 1, true) then told = true end
end
truthy(told, "the autosave finds another server's token: the player is told")
eq(Lib.last(w, "Profile", a2.plr).canSave, false, "and canSave is now false")
eq(store.__data["u_5301"].lock.session, "another-server", "the other server's record was not written over")

--============================================================ 3. a lock held elsewhere, retried, merged
local b = Lib.player(w, "Bea", 5302)
h:advance(1)
local toldB = false
for _, pl in w.R.Notice:sentTo(b.plr) do
	if type(pl.args[1]) == "table" and string.find(tostring(pl.args[1].text), "open on another server", 1, true) then toldB = true end
end
truthy(toldB, "a lock held elsewhere: the player is told, in words")
local pb = Lib.last(w, "Profile", b.plr)
eq(pb.canSave, false, "and cannot save meanwhile")
eq(pb.loaded, true, "but plays (the HUD is not stuck loading)")
Lib.intoSoloLift(w, b)
h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
eq(Lib.last(w, "RoomState", b.plr).slot, 1, "with defaults, Continue is room 1")
playRooms(b, 1)
-- the other server lets go
store.__data["u_5302"].lock["until"] = 0
h:advance(Config.Save.AutosaveSeconds + 1)
local pb2 = Lib.last(w, "Profile", b.plr)
eq(pb2.canSave, true, "the retried load takes the freed lock")
eq(pb2.stars, 3, "the stored room 1 and the room played meanwhile merge (best per room): 3 stars")
h:advance(Config.Save.AutosaveSeconds + 1)
local recB = store.__data["u_5302"]
truthy(recB.data.rooms >= 2, "rooms escaped counts both (" .. tostring(recB.data.rooms) .. ")")

--============================================================ 4. the tie-break on the public board
do
	boardStore.__data[Board.key(9001)] = Board.encode(9, NOW - 500, Config.Board) -- 9 stars, earlier than Ada
	boardStore.__data[Board.key(9002)] = Board.encode(9, NOW + 5000, Config.Board) -- 9 stars, later
	boardStore.__data[Board.key(9003)] = Board.encode(10, NOW + 9000, Config.Board) -- more stars, latest
	h:advance(Config.Board.PublicCacheSeconds + 1)
	local face = ws.Atrium.StarBoard.BoardFace
	local rows = {}
	for i = 1, 5 do table.insert(rows, Lib.labelText(face, "Row_" .. i) or "") end
	local function rowOf(needle)
		for i, r in rows do if string.find(r, needle, 1, true) then return i end end
		return nil
	end
	print("  public board: " .. table.concat(rows, " | "))
	eq(rowOf("9003"), 1, "10 stars ranks first, reached last")
	truthy(rowOf("9001") and rowOf("Ada") and rowOf("9001") < rowOf("Ada"), "9 stars reached earlier ranks above Ada's 9")
	truthy(rowOf("Ada") and rowOf("9002") and rowOf("Ada") < rowOf("9002"), "Ada's 9 ranks above 9 reached later")
end

--============================================================ 5. a failing store
store.__failAll = true
boardStore.__failAll = true
local c = Lib.player(w, "Cid", 5303)
h:advance(1)
local toldC = false
for _, pl in w.R.Notice:sentTo(c.plr) do
	if type(pl.args[1]) == "table" and pl.args[1].text == LOAD_RETRY then toldC = true end
end
truthy(toldC, "a failing store: the player is told the load is being retried")
local pc = Lib.last(w, "Profile", c.plr)
eq(pc.canSave, false, "canSave false")
eq(pc.loaded, true, "and the player plays with defaults")
h:advance(Config.Board.PublicCacheSeconds + 1)
eq(Lib.labelText(ws.Atrium.StarBoard.BoardFace, "Note"), Config.Board.Text.Unavailable, "the board says it is unavailable")
eq(Lib.labelText(ws.Atrium.StarBoard.BoardFace, "Row_1"), "", "and shows no stale rows")
store.__failAll = false
boardStore.__failAll = false
h:advance(Config.Save.AutosaveSeconds + 1)
eq(Lib.last(w, "Profile", c.plr).canSave, true, "once the store answers again, the next autosave tick loads Cid and saving resumes")

--============================================================ 6. a load that fails once
do
	local d = nil
	store.__failNext = true -- the join's UpdateAsync raises once (a throttle, a 5xx)
	d = Lib.player(w, "Dee", 5304)
	h:advance(1)
	local p = Lib.last(w, "Profile", d.plr)
	eq(p.canSave, false, "after one failed load, nothing is written over the stored 10 stars")
	local told = false
	for _, pl in w.R.Notice:sentTo(d.plr) do
		if type(pl.args[1]) == "table" and pl.args[1].text == LOAD_RETRY then told = true end
	end
	truthy(told, "Dee is told the load is being retried")
	Lib.intoSoloLift(w, d)
	h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
	Lib.solveRoom(w, d, step) -- room 1, 3 stars: better than the stored 2, earned while unloaded
	-- the next autosave tick retries the load
	local loadedAt = nil
	for _ = 1, math.ceil((Config.Save.AutosaveSeconds + 2) / 0.1) do
		h:advance(0.1)
		if Lib.last(w, "Profile", d.plr).canSave then loadedAt = h.scheduler:now() break end
	end
	truthy(loadedAt ~= nil, "the next autosave tick retried the load and took the lock")
	p = Lib.last(w, "Profile", d.plr)
	eq(p.stars, 11, "the HUD shows the stored stars merged with the room played meanwhile (2 -> 3 in room 1: 11)")
	-- the merged progress is written on the next coalesced write, long before the next autosave tick
	h:advance(Config.Save.CoalesceSeconds + 1)
	local rec = store.__data["u_5304"]
	eq(rec and rec.data and rec.data.best["1"], 3, "room 1's 3 stars reached the store within CoalesceSeconds of the load")
	local tot = 0
	for _, v in (rec and rec.data and rec.data.best or {}) do tot += v end
	eq(tot, 11, "the store holds 11")
	eq(rec and rec.lock and rec.lock.session ~= nil and rec.lock.session ~= "", true, "under Dee's session lock")
	print(string.format("  one failed load: retried and loaded; HUD %d stars, canSave %s, store %d stars", p.stars, tostring(p.canSave), tot))
end

t.finish("escape-room-lab save", h)
