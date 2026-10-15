-- Round: the 88 s phase clock, the roster rule, the early end and the practice drop-in window (DESIGN.md §2.1).
-- Run: luau tests/Round.spec.luau
local Round = require("../src/shared/Round")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RC = Config.Round
eq(Round.cycleSeconds(RC), 88, "a cycle is 20 + 4 + 60 + 4 = 88 s")
eq(Round.duration(RC, "intermission"), 20, "intermission 20 s")
eq(Round.duration(RC, "drop"), 4, "drop 4 s")
eq(Round.duration(RC, "disaster"), 60, "disaster 60 s")
eq(Round.duration(RC, "outro"), 4, "outro 4 s")

--======================================================================= a full cycle

do
	local s = Round.new(RC, 100)
	eq(s.phase, "intermission", "a server starts in the intermission")
	eq(s.ends, 120, "which ends 20 s later")
	eq(Round.step(s, RC, 119.9, { eligible = 1, onIsland = 0 }), nil, "nothing happens before it ends")
	local ev = Round.step(s, RC, 120, { eligible = 1, onIsland = 0 })
	eq(ev, "drop", "at 20 s with a player ready: the drop")
	eq(s.phase, "drop", "phase drop")
	eq(s.roundId, 1, "round 1")
	eq(s.ends, 124, "the drop lasts 4 s")
	eq(Round.step(s, RC, 124, { eligible = 1, onIsland = 1 }), "name", "after the drop the disaster is named")
	eq(s.phase, "disaster", "phase disaster")
	eq(s.ends, 184, "and runs 60 s")
	eq(Round.disasterElapsed(s, 154), 30, "30 s into the disaster")
	eq(Round.step(s, RC, 183.9, { eligible = 1, onIsland = 1 }), nil, "still running at 59.9 s")
	eq(Round.step(s, RC, 184, { eligible = 1, onIsland = 1 }), "survive", "at 60 s whoever is still there survived")
	eq(s.phase, "outro", "phase outro")
	eq(Round.step(s, RC, 188, { eligible = 1, onIsland = 1 }), "return", "after the outro everyone returns")
	eq(s.phase, "intermission", "and a new intermission begins")
	eq(s.ends, 208, "20 s long")
	eq(s.started, 188, "starting at the return")
end

--======================================================================= nobody ready: the intermission repeats

do
	local s = Round.new(RC, 0)
	eq(Round.step(s, RC, 20, { eligible = 0, onIsland = 0 }), "idle", "an empty roster repeats the intermission")
	eq(s.phase, "intermission", "still intermission")
	eq(s.ends, 40, "for another 20 s")
	eq(s.roundId, 0, "and no round was used up")
end

--======================================================================= the early end

do
	local s = Round.new(RC, 0)
	Round.step(s, RC, 20, { eligible = 2, onIsland = 0 })
	Round.step(s, RC, 24, { eligible = 2, onIsland = 2 })
	eq(Round.step(s, RC, 34, { eligible = 2, onIsland = 0 }), "empty", "the disaster ends the moment nobody is left on the island")
	eq(s.phase, "intermission", "straight to the intermission")
	eq(s.ends, 54, "which starts now")
	-- the drop itself never ends early: players are still landing
	local s2 = Round.new(RC, 0)
	Round.step(s2, RC, 20, { eligible = 1, onIsland = 0 })
	eq(Round.step(s2, RC, 22, { eligible = 1, onIsland = 0 }), nil, "an empty island during the drop is not an early end")
end

--======================================================================= the practice drop-in window

do
	local s = Round.new(RC, 0)
	local who = { inRound = "", swept = false, resting = false }
	local ok, code = Round.jumpInCheck(RC, s, 10, who)
	eq(ok, false, "no jump-in during the intermission")
	eq(code, "next", "because you are in the next round anyway")
	Round.step(s, RC, 20, { eligible = 1, onIsland = 0 })
	eq((Round.jumpInCheck(RC, s, 20, who)), true, "jump-in opens with the drop")
	Round.step(s, RC, 24, { eligible = 1, onIsland = 1 })
	eq((Round.jumpInCheck(RC, s, 24 + 49.9, who)), true, "and stays open until 50 s into the disaster")
	local ok2, code2 = Round.jumpInCheck(RC, s, 24 + 50, who)
	eq(ok2, false, "at 50 s it is too late")
	eq(code2, "late", "with the late reason")
	local _, c3 = Round.jumpInCheck(RC, s, 30, { inRound = "counted", swept = false, resting = false })
	eq(c3, "island", "a roster player is already on the island")
	local _, c4 = Round.jumpInCheck(RC, s, 30, { inRound = "practice", swept = false, resting = false })
	eq(c4, "island", "a practice player too (once a round)")
	local _, c5 = Round.jumpInCheck(RC, s, 30, { inRound = "", swept = true, resting = false })
	eq(c5, "swept", "a swept-out player waits for the next round")
	local _, c6 = Round.jumpInCheck(RC, s, 30, { inRound = "", swept = false, resting = true })
	eq(c6, "resting", "a resting player is told to come back first")
	Round.step(s, RC, 84, { eligible = 1, onIsland = 1 })
	local _, c7 = Round.jumpInCheck(RC, s, 85, who)
	eq(c7, "late", "the outro is too late")
end

--======================================================================= the countdown to the next drop

do
	local s = Round.new(RC, 0)
	eq(Round.secondsToNextDrop(RC, s, 6), 14, "6 s into the intermission: the drop in 14 s")
	Round.step(s, RC, 20, { eligible = 1, onIsland = 0 })
	Round.step(s, RC, 24, { eligible = 1, onIsland = 1 })
	eq(Round.secondsToNextDrop(RC, s, 34), 50 + 4 + 20, "10 s into the disaster: 50 + 4 + 20 s to the next drop")
	eq(Round.clock(23), "0:23", "a clock reads m:ss")
	eq(Round.clock(83.2), "1:24", "and rounds up a partial second")
	eq(Round.clock(-3), "0:00", "and never goes negative")
end

--======================================================================= every refusal says why

do
	local seen = {}
	for _, code in { "next", "late", "island", "swept", "resting", "rate", "nospot" } do
		local text = Round.refusalText(code, 23)
		truthy(type(text) == "string" and #text > 8, "refusal '" .. code .. "' has a text (" .. tostring(text) .. ")")
		truthy(not seen[text], "and it is its own text")
		seen[text] = true
	end
	truthy(string.find(Round.refusalText("swept", 23), "0:23", 1, true) ~= nil, "a swept-out refusal says when the next round is")
	truthy(string.find(Round.refusalText("late", 23), "0:23", 1, true) ~= nil, "so does a late one")
end

--======================================================================= the next disaster owes nothing to the last one

-- REVIEW-1 F4: the first build never repeated a disaster, so after a flood the next round was surely not a flood. The
-- last disaster is public (Kind replicates during the round), and a break pressed in the intermission picks which rounds
-- you play: a player who sat out every round except the one after a flood never met a flood (0 of 60 rounds in the
-- review's probe). The pick is now a fresh, even draw every round, so nothing a client has seen says anything about it.
do
	local kinds = Config.Disasters.Kinds
	local s = 99
	local function rand()
		s = (1103515245 * s + 12345) % 2147483648
		return s / 2147483648
	end
	local last, repeats, counts = nil, 0, {}
	local after = {} -- after[last][next] = count
	for _ = 1, 8000 do
		local k = Round.pickKind(kinds, rand, nil)
		if k == last then repeats += 1 end
		counts[k] = (counts[k] or 0) + 1
		if last then
			after[last] = after[last] or {}
			after[last][k] = (after[last][k] or 0) + 1
		end
		last = k
	end
	for _, k in kinds do
		truthy(math.abs((counts[k] or 0) / 8000 - 0.25) < 0.02, k .. " comes up a quarter of the time (" .. tostring(counts[k]) .. " of 8000)")
	end
	truthy(math.abs(repeats / 7999 - 0.25) < 0.02, string.format("the same disaster again: %.1f %% of rounds, as often as any other (25 %%)", 100 * repeats / 7999))
	-- the evidence a resting player would use: given the last disaster, the next one is still an even draw
	local worst = 0
	for _, a in kinds do
		local row, n = after[a] or {}, 0
		for _, b in kinds do n += row[b] or 0 end
		for _, b in kinds do worst = math.max(worst, math.abs((row[b] or 0) / math.max(1, n) - 0.25)) end
	end
	truthy(worst < 0.03, string.format("after any disaster, every disaster comes next 25 %% of the time (worst off by %.1f points)", 100 * worst))
	eq(Round.pickKind(kinds, rand, "flood"), "flood", "a shots place may force a kind")
	local forced = Round.pickKind(kinds, rand, "bogus")
	truthy(forced ~= "bogus" and table.find(kinds, forced) ~= nil, "a forced kind that does not exist is ignored (" .. tostring(forced) .. ")")
end

print(string.format("Round: %d passed, %d failed", passed, failed))
assert(failed == 0, "Round tests failed")
