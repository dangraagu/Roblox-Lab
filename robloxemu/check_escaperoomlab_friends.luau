-- Escape Room Lab — the Star Board's FRIENDS view under load (review 2026-10-01).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_friends.luau 2>&1
--
-- The emulator has no Players:GetFriendsAsync; this check stubs one (pages of 50, 0.3 s per call, 0.2 s
-- per page) and gives the board store's GetAsync a 0.25 s latency, then counts every call.
--   * a player who spams the board prompt (41 presses, 0.05 s apart) costs ONE GetFriendsAsync and at
--     most one GetAsync per friend: the fetch is single-flight per player and never restarted by a
--     toggle (before the fix: 11 friend-list calls, 1005 reads, 6 reads in flight at once);
--   * friend-score reads go one at a time across the whole server, so the request-budget check before
--     each read is exact (Board.readStep is the rule, unit-tested in Board.spec; the emulator's budget is
--     a constant 1000, so this world cannot drain it);
--   * an honest player pressing once while the spammer's fetch runs still gets a complete view, ranked;
--   * friend lists (10 min) and scores (5 min) are cached: public and back to friends costs no call at all;
--   * a player with no friends is told something useful.

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local sched
local friendCalls = {}
local reads, perKey, inflight, maxInflight = 0, {}, 0, 0
local SCORED = { [800005] = 30, [800050] = 12, [800199] = 7 } -- three of the honest player's friends have stars
local w = Lib.boot({ name = "escape-room-lab-friends", beforeServer = function(h)
	sched = h.scheduler
	local Board = h:_require(h.ReplicatedStorage:FindFirstChild("Board"))
	local bs = h.services.DataStoreService:GetOrderedDataStore("EscapeRoomLab_Stars_v1")
	for id, stars in SCORED do bs.__data[Board.key(id)] = Board.encode(stars, 1790000000 + id % 1000, { MaxMetric = 45 }) end
	h.Players.GetFriendsAsync = function(_self, userId)
		friendCalls[userId] = (friendCalls[userId] or 0) + 1
		sched:wait(0.3)
		local list = {}
		local n = if userId == 4244 then 0 else 200
		local base = if userId == 4243 then 800000 else 700000
		for i = 1, n do table.insert(list, base + i) end
		local pageNo = 1
		local pages = { IsFinished = #list <= 50 }
		function pages:GetCurrentPage()
			local out = {}
			for i = (pageNo - 1) * 50 + 1, math.min(pageNo * 50, #list) do table.insert(out, { Id = list[i] }) end
			return out
		end
		function pages:AdvanceToNextPageAsync()
			sched:wait(0.2)
			pageNo += 1
			self.IsFinished = pageNo * 50 >= #list
		end
		return pages
	end
	local orig = bs.GetAsync
	bs.GetAsync = function(self, key)
		reads += 1
		perKey[key] = (perKey[key] or 0) + 1
		inflight += 1
		if inflight > maxInflight then maxInflight = inflight end
		sched:wait(0.25)
		inflight -= 1
		return orig(self, key)
	end
end })
local h, Config = w.h, w.Config
local prompt = w.ws.Atrium.StarBoard.BoardPrompt

local spam = Lib.player(w, "Spammer", 4242)
local hon = Lib.player(w, "Honest", 4243)
local lone = Lib.player(w, "Lone", 4244)
h:advance(2)

for _ = 1, 41 do -- an odd number of presses: the spammer ends on the friends view
	prompt.Triggered:Fire(spam.plr)
	h:advance(0.05)
end
local tPress = sched:now()
prompt.Triggered:Fire(hon.plr)
prompt.Triggered:Fire(lone.plr)
local doneAt = nil
for _ = 1, 400 do
	h:advance(0.5)
	local lb = Lib.last(w, "Board", hon.plr)
	if doneAt == nil and lb and lb.mode == "friends" and lb.loading ~= true then doneAt = sched:now() end
	if doneAt and Lib.last(w, "Board", spam.plr).loading ~= true then break end
end
local twice = 0
for _, n in perKey do if n > 1 then twice += 1 end end
print(string.format("  41 presses + 1 press: GetFriendsAsync calls spammer %d / honest %d / lone %d; GetAsync reads %d (any key twice: %d), max in flight %d; honest view done %.1f s after the press",
	friendCalls[4242] or 0, friendCalls[4243] or 0, friendCalls[4244] or 0, reads, twice, maxInflight, (doneAt or math.huge) - tPress))
eq(friendCalls[4242], 1, "41 presses fetch the spammer's friend list ONCE")
eq(twice, 0, "no friend's score is read twice")
truthy(reads <= 400, "at most one read per friend for the two players (" .. reads .. " reads)")
eq(maxInflight, 1, "friend-score reads go one at a time across the server")
truthy(doneAt ~= nil and doneAt - tPress <= 2 * 200 * 0.25 + 15,
	string.format("the honest player's view completes while the spammer's runs (%.1f s; bound %d s)", (doneAt or math.huge) - tPress, 2 * 200 * 0.25 + 15))

local lb = Lib.last(w, "Board", hon.plr)
local stars = {}
for _, r in (lb and lb.rows or {}) do table.insert(stars, r.stars) end
eq(table.concat(stars, ","), "30,12,7", "the honest player's friends rank by stars (30, 12, 7)")
eq(lb and lb.message, nil, "a complete view with scored friends needs no note")
local sl = Lib.last(w, "Board", spam.plr)
eq(sl and sl.mode, "friends", "the spammer ends on the friends view")
eq(sl and sl.loading, false, "and it finished")
eq(sl and sl.message, string.format(Config.Board.Text.FriendsNoScores, 200), "none of the spammer's 200 friends has a star, and the board says so")

local ll = Lib.last(w, "Board", lone.plr)
eq(ll and ll.message, Config.Board.Text.NoFriends, "a player with no friends gets the no-friends note")
truthy(ll and ll.message and string.find(ll.message, "friends on Roblox", 1, true) ~= nil, "and it says how to get some on the board: " .. tostring(ll and ll.message))

-- cached lists and scores: public, then friends again
local calls0, reads0 = friendCalls[4243], reads
prompt.Triggered:Fire(hon.plr)
h:advance(0.2)
eq(Lib.last(w, "Board", hon.plr).mode, "public", "a press flips back to public")
prompt.Triggered:Fire(hon.plr)
h:advance(1)
eq(friendCalls[4243], calls0, "back to friends: no new friend-list call (the list is cached)")
eq(reads, reads0, "and no new reads (the scores are cached)")
local again = Lib.last(w, "Board", hon.plr)
eq(again and #again.rows, 3, "the view is rebuilt from the caches within a second")

t.finish("escape-room-lab friends", h)
