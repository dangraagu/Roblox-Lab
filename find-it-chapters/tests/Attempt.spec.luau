-- Spec for Attempt: one attempt's server-side state machine (DESIGN.md §3.4-3.7, §9, §12.2).
-- Run: luau tests/Attempt.spec.luau 2>&1
--
-- Looks (n*k + 2), the 1.0 s answer for hit and miss alike, a repeat search free, the off-clue count, one hint,
-- pause/resume with the re-dress (counts kept, looks never touched, Resume no sooner than 3 s), the clock
-- (only live, unpaused time), and the stars. Uniform hiding is measured too (chi-square), and the payload is
-- shown to be the same whatever the secret.
local Attempt = require("../src/shared/Attempt")
local Dressing = require("../src/shared/Dressing")
local Stars = require("../src/shared/Stars")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function randOf(seed)
	local g = Rng.new(seed)
	return function() return g:next() end
end

local function fresh(ch, seed, intro)
	local spec = Dressing.spec("book", ch, Config)
	local rand = randOf(seed)
	local room = Dressing.build(spec, rand, Config)
	local a = Attempt.new(room, spec, Config, { intro = intro or 3 })
	Attempt.hide(a, rand)
	return a, room, spec, rand
end

local function run(a, seconds, step)
	local events = {}
	local t = 0
	step = step or 0.05
	while t < seconds - 1e-9 do
		local dt = math.min(step, seconds - t)
		for _, e in Attempt.tick(a, dt) do table.insert(events, e) end
		t += dt
	end
	return events
end

local function findEvent(events, kind)
	for _, e in events do
		if e.type == kind then return e end
	end
	return nil
end

-- a prop that fits no clue still needed
local function offProp(a)
	for _, p in a.room.props do
		if Attempt.fitsNeeded(a, p) == nil then return p end
	end
	return nil
end

--============================================================ the intro, then the clock
do
	local a = fresh(4, 1)
	eq(a.state, "intro", "an attempt starts on its intro card")
	eq(a.looks, 5 * 4 + 2, "looks = n * k + 2 (22 in chapter 4)")
	local ok, why = Attempt.search(a, a.room.props[1].id)
	eq(ok, false, "no search before the clock starts")
	eq(why, "intro", "... refused as 'intro' (the HUD says Get ready...)")
	local ev = run(a, 3.0)
	truthy(findEvent(ev, "live") ~= nil, "the clock starts when the 3 s intro ends")
	eq(a.state, "live", "live")
	truthy(math.abs(a.clock) < 1e-9, "the clock did not run during the intro")
	run(a, 10)
	truthy(math.abs(a.clock - 10) < 1e-6, "the clock is live time (10 s)")
end

--============================================================ a search: 1.0 s, hit and miss alike
do
	local a = fresh(4, 2)
	run(a, 3)
	local hiddenId = a.hidden[1]
	local missId = nil
	for _, id in a.room.cands[1] do
		if id ~= hiddenId then missId = id break end
	end
	local looks0 = a.looks
	local ok = Attempt.search(a, missId)
	eq(ok, true, "a candidate search starts")
	eq(a.looks, looks0 - 1, "and spends one look")
	local ok2, why2 = Attempt.search(a, hiddenId)
	eq(ok2, false, "a second search while one is in flight is refused")
	eq(why2, "pending", "... as 'pending' (One search at a time)")
	eq(a.looks, looks0 - 1, "the refused search spends no look")
	local ev = run(a, 0.95)
	eq(findEvent(ev, "result"), nil, "no answer before 1.0 s")
	ev = run(a, 0.1)
	local r = findEvent(ev, "result")
	truthy(r ~= nil and r.hit == false, "a miss is answered at 1.0 s")
	eq(r and r.after, 1.0, "the miss took exactly Search.Seconds")
	Attempt.search(a, hiddenId)
	ev = run(a, 0.95)
	eq(findEvent(ev, "result"), nil, "no answer before 1.0 s for a hit either")
	ev = run(a, 0.1)
	r = findEvent(ev, "result")
	truthy(r ~= nil and r.hit == true and r.item == 1, "a hit is answered at 1.0 s with the item")
	eq(r and r.after, 1.0, "the hit took exactly Search.Seconds: the timing says nothing")
	truthy(a.found[1] == true, "item 1 found")
	local looks1 = a.looks
	local ok3, why3 = Attempt.search(a, missId)
	eq(ok3, false, "searching the same prop again is refused")
	eq(why3, "already", "... as 'already' (free)")
	eq(a.looks, looks1, "and costs no look")
	local ok4, why4 = Attempt.search(a, 99999)
	eq(ok4, false, "an id not in this room is refused")
	eq(why4, "unknown", "... as 'unknown'")
end

--============================================================ off-clue searches and Sharp Eye
do
	local a = fresh(6, 3)
	run(a, 3)
	local p = offProp(a)
	truthy(p ~= nil, "chapter 6 has a prop that fits no clue")
	Attempt.search(a, p.id)
	local r = findEvent(run(a, 1.0), "result")
	truthy(r and r.offClue == true, "a search of a prop that fits no clue still needed says so")
	eq(a.off, 1, "the off-clue count is 1")
	-- a candidate of a FOUND clue fits no clue still needed: it counts as off-clue too
	local hid = a.hidden[2]
	Attempt.search(a, hid)
	run(a, 1.0)
	local other = nil
	for _, id in a.room.cands[2] do
		if id ~= hid then other = id break end
	end
	Attempt.search(a, other)
	r = findEvent(run(a, 1.0), "result")
	truthy(r and r.offClue == true, "after item 2 is found, its other candidates fit no clue still needed")
	eq(a.off, 2, "off-clue count 2")
end

--============================================================ the hint: once, and it costs Sharp Eye
do
	local a = fresh(5, 4)
	local id0, why0 = Attempt.hint(a, 1)
	eq(id0, nil, "no hint during the intro")
	eq(why0, "intro", "... 'intro'")
	run(a, 3)
	local id, why = Attempt.hint(a, 0)
	eq(id, nil, "a hint needs an item on the list")
	eq(why, "pick", "... 'pick' (Tap a thing on your list first)")
	id = Attempt.hint(a, 2)
	eq(id, a.hidden[2], "the hint is item 2's hiding prop")
	local id2, why2 = Attempt.hint(a, 3)
	eq(id2, nil, "a second hint is refused")
	eq(why2, "used", "... 'used'")
	-- find everything; Sharp Eye is lost to the hint
	for i = 1, a.spec.n do
		Attempt.search(a, a.hidden[i])
		run(a, 1.0)
	end
	eq(a.state, "done", "every item found: done")
	eq(a.reason, "found", "reason: found")
	local s = Attempt.stars(a)
	eq(s.f, true, "Found")
	eq(s.s, false, "no Sharp Eye after a hint")
end

--============================================================ stars: Found, Swift, Sharp Eye
do
	local a = fresh(3, 5)
	run(a, 3)
	-- one off-clue slip is allowed
	local p = offProp(a)
	Attempt.search(a, p.id)
	run(a, 1)
	for i = 1, a.spec.n do
		Attempt.search(a, a.hidden[i])
		run(a, 1)
	end
	local s = Attempt.stars(a)
	eq(s.f, true, "found")
	eq(s.w, true, "Swift: done in 5 s of a 120 s clock")
	eq(s.s, true, "Sharp Eye with one slip (phones mis-tap)")
	local b = fresh(3, 5)
	run(b, 3)
	local slips = 0
	for _, q in b.room.props do
		if Attempt.fitsNeeded(b, q) == nil and slips < 2 then
			Attempt.search(b, q.id)
			run(b, 1)
			slips += 1
		end
	end
	run(b, 90) -- past two thirds of 120 s
	for i = 1, b.spec.n do
		Attempt.search(b, b.hidden[i])
		run(b, 1)
	end
	local s2 = Attempt.stars(b)
	eq(s2.f, true, "found")
	eq(s2.w, false, "not Swift past two thirds of the clock")
	eq(s2.s, false, "not Sharp with two slips")
	eq(Stars.count({ c1 = { f = true, w = true, s = false }, c2 = { f = true } }), 3, "Stars.count")
	local m = Stars.merge({ f = true, w = false, s = true }, { f = true, w = true, s = false })
	truthy(m.f and m.w and m.s, "a star once earned is kept (merge)")
end

--============================================================ time's up, and a find that lands too late
do
	local a = fresh(1, 6)
	run(a, 3)
	run(a, a.limit - 0.5)
	Attempt.search(a, a.hidden[1])
	local ev = run(a, 1.0)
	local e = findEvent(ev, "end")
	truthy(e and e.reason == "time", "a search still in flight when the clock runs out does not count: time's up")
	eq(a.found[1], nil, "nothing was found")
	local ok, why = Attempt.search(a, a.hidden[2])
	eq(ok, false, "no search after the end")
	eq(why, "time", "... 'time'")
end

--============================================================ out of looks
do
	local a = fresh(1, 7)
	run(a, 3)
	local n = 0
	-- tap everything that hides nothing, until the looks run out
	for _, p in a.room.props do
		local hides = false
		for i = 1, a.spec.n do if a.hidden[i] == p.id then hides = true end end
		if not hides and a.state == "live" then
			Attempt.search(a, p.id)
			run(a, 1)
			n += 1
		end
	end
	eq(a.state, "done", "out of looks ends the attempt")
	eq(a.reason, "looks", "reason: looks")
	eq(n, a.spec.looks, "after exactly n*k+2 searches (" .. a.spec.looks .. ")")
	local ok, why = Attempt.search(a, a.hidden[1])
	eq(ok, false, "no search after the looks ran out")
	eq(why, "looks", "... 'looks'")
end

--============================================================ careful play never runs out of looks
do
	local worstLooksLeft = math.huge
	for seed = 1, 400 do
		local a = fresh(15, 1000 + seed)
		run(a, 3)
		-- the unluckiest careful player: every candidate of a clue before its hiding one
		for i = 1, a.spec.n do
			for _, id in a.room.cands[i] do
				if id ~= a.hidden[i] then
					Attempt.search(a, id)
					run(a, 1)
				end
			end
			Attempt.search(a, a.hidden[i])
			run(a, 1)
		end
		if a.reason ~= "found" then worstLooksLeft = -1 break end
		worstLooksLeft = math.min(worstLooksLeft, a.looks)
	end
	eq(worstLooksLeft, 2, "the unluckiest careful player finishes chapter 15 with 2 looks left, every time (400 rooms)")
end

--============================================================ pause and resume: the re-dress
do
	local a, room, spec, rand = fresh(9, 8)
	run(a, 3)
	-- search two misses of clue 1 and find clue 2, then hint clue 3
	local misses = {}
	for _, id in a.room.cands[1] do
		if id ~= a.hidden[1] and #misses < 2 then table.insert(misses, id) end
	end
	for _, id in misses do
		Attempt.search(a, id)
		run(a, 1)
	end
	Attempt.search(a, a.hidden[2])
	run(a, 1)
	Attempt.hint(a, 3)
	local looksBefore = a.looks
	local clockBefore = a.clock
	local st = Attempt.pause(a, 100)
	eq(st, "paused", "pause")
	local ok, why = Attempt.search(a, a.hidden[1])
	eq(ok, false, "no search while paused")
	eq(why, "paused", "... 'paused'")
	local hid, hwhy = Attempt.hint(a, 4)
	eq(hid, nil, "no hint while paused")
	eq(hwhy, "paused", "... 'paused'")
	run(a, 30)
	truthy(math.abs(a.clock - clockBefore) < 1e-9, "the clock is stopped while paused")
	eq(Attempt.resume(a, 101.5), "wait", "a Resume 1.5 s after the Pause waits (no sooner than 3 s)")
	eq(a.state, "paused", "still paused")
	local res, counts = Attempt.resume(a, 103.0)
	eq(res, "redress", "a Resume at 3 s re-dresses")
	eq(counts[1], spec.k - 2, "item 1 keeps its unsearched-candidate count (k - 2 misses)")
	eq(counts[2], 0, "item 2 is found: count 0")
	eq(counts[3], 1, "the hinted item: count 1")
	eq(counts[4], spec.k, "an untouched item: k")
	local re = Dressing.redress(a.room, counts, rand, Config)
	Attempt.applyRedress(a, re, rand)
	eq(a.state, "live", "live again")
	eq(a.looks, looksBefore, "the looks are unchanged by a pause")
	eq(a.found[2], true, "found items stay found")
	eq(a.hintProp, a.hidden[3], "the hinted item's new prop is its only candidate, and it is the hint again")
	local inNew = false
	for _, id in re.cands[1] do if id == a.hidden[1] then inNew = true end end
	truthy(inNew, "item 1's new hiding prop is one of its new candidates")
	local okOld, whyOld = Attempt.search(a, misses[1])
	eq(okOld, false, "an id from before the pause is not in the room any more")
	eq(whyOld, "unknown", "... 'unknown'")
	-- REVIEW-1 A4: a re-dress is not a free re-roll. The next pause needs EverySeconds of CLOCK after it, so
	-- re-dealing the room costs at least that much of the clock (the first pause of an attempt is free).
	local every = Config.Pause.EverySeconds
	truthy(type(every) == "number" and every >= 20, "Config.Pause.EverySeconds is set (>= 20 s of clock)")
	truthy(math.abs(Attempt.public(a).pauseIn - every) < 1e-6, "right after a re-dress the next pause is EverySeconds of clock away")
	local clock0 = a.clock
	eq(Attempt.pause(a, 150), "soon", "a pause right after the re-dress is refused ('soon')")
	eq(a.state, "live", "... the attempt stays live")
	run(a, 2)
	truthy(math.abs(a.clock - clock0 - 2) < 1e-6, "... and its clock keeps running")
	truthy(math.abs(Attempt.public(a).pauseIn - (every - 2)) < 1e-6, "pauseIn counts down with the clock")
	Attempt.search(a, a.hidden[1])
	eq(Attempt.pause(a, 160), "soon", "during a search inside the window: refused too, not queued")
	run(a, 1)
	eq(a.state, "live", "no pause followed the answer")
	run(a, every - 3 - 0.2)
	eq(Attempt.pause(a, 170), "soon", "0.2 s of clock before the window ends: still refused")
	run(a, 0.25)
	eq(Attempt.public(a).pauseIn, 0, "the window is over")
	-- a pause while a search is in flight waits for its answer
	local spare = nil
	for i = 1, a.n do if not a.found[i] then spare = i end end
	local cand = nil
	for _, id in a.room.cands[spare] do if not a.searched[id] then cand = id end end
	Attempt.search(a, cand)
	eq(Attempt.pause(a, 200), "queued", "pausing during a search is queued until the answer")
	local ev = run(a, 1)
	truthy(findEvent(ev, "result") ~= nil and findEvent(ev, "paused") ~= nil, "the answer lands, then the pause")
	eq(a.state, "paused", "paused after the answer")
end

--============================================================ the first pause of an attempt is free (REVIEW-1 A4)
do
	local a = fresh(4, 21)
	run(a, 3.05)
	eq(a.state, "live", "live after the intro")
	eq(Attempt.public(a).pauseIn, 0, "no re-dress yet: a pause is open at once")
	eq(Attempt.pause(a, 10), "paused", "the first pause of an attempt is accepted at clock ~0")
end

--============================================================ C2 (REVIEW-1 round 2): a break is capped
-- An unbounded Pause let a Daily opened at 23:58 be solved the next morning and credited to its start day. The
-- break (paused time, summed over the attempt, on the server's own frame clock) is capped at MaxBreakSeconds; at
-- the cap the room closes: reason "break", nothing earned, nothing saved.
do
	local cap = Config.Pause.MaxBreakSeconds
	truthy(type(cap) == "number" and cap >= 300 and cap <= 900, "C2: Config.Pause.MaxBreakSeconds is set (5-15 min)")
	local a, _, _, rand = fresh(6, 31)
	run(a, 3.05)
	eq(Attempt.pause(a, 1000), "paused", "C2: paused at t = 1000")
	truthy(math.abs(Attempt.breakLeft(a, 1000) - cap) < 1e-6, "C2: a fresh attempt has the whole break left")
	truthy(math.abs(Attempt.breakLeft(a, 1100) - (cap - 100)) < 1e-6, "C2: the break counts down while paused")
	truthy(math.abs(Attempt.public(a, 1100).breakLeft - (cap - 100)) < 1e-6, "C2: the owner's HUD is told how much break is left")
	eq(#Attempt.closeBreak(a, 1000 + cap - 1), 0, "C2: 1 s before the cap the room stays open")
	eq(a.state, "paused", "C2: ... and paused")
	local res, counts = Attempt.resume(a, 1100)
	eq(res, "redress", "C2: a resume after 100 s of break")
	Attempt.applyRedress(a, Dressing.redress(a.room, counts, rand, Config), rand)
	truthy(math.abs(Attempt.breakLeft(a, 5000) - (cap - 100)) < 1e-6, "C2: while live the break left does not run (100 s used)")
	eq(Attempt.public(a, 5000).breakLeft, nil, "C2: and a live room's state carries no break count")
	run(a, Config.Pause.EverySeconds + 0.1)
	eq(Attempt.pause(a, 6000), "paused", "C2: a second pause")
	eq(#Attempt.closeBreak(a, 6000 + cap - 100 - 1), 0, "C2: the second pause may use the rest of the break")
	local ev = Attempt.closeBreak(a, 6000 + cap - 100 + 0.01)
	truthy(findEvent(ev, "end") ~= nil, "C2: the room closes when the TOTAL break reaches the cap")
	eq(a.state, "done", "C2: done")
	eq(a.reason, "break", "C2: reason 'break'")
	eq(Attempt.stars(a).f, false, "C2: a closed room earns nothing")
	local ok, why = Attempt.search(a, a.room.props[1].id)
	eq(ok, false, "C2: no search after the room closed")
	eq(why, "break", "C2: ... 'break'")
	eq(#Attempt.closeBreak(a, 99999), 0, "C2: a closed room is closed once")
	-- a live room is never closed by the break cap
	local b = fresh(3, 41)
	run(b, 3.05)
	eq(#Attempt.closeBreak(b, 1e9), 0, "C2: a live room never closes for a break")
end

--============================================================ uniform hiding (chi-square), payload independent of the secret
do
	local spec = Dressing.spec("book", 8, Config)
	local room = Dressing.build(spec, randOf(7), Config)
	local hrand = randOf(8)
	local counts = {}
	local N = 30000
	for _ = 1, N do
		local a = Attempt.new(room, spec, Config, { intro = 0 })
		Attempt.hide(a, hrand)
		for i, id in a.hidden do
			counts[id] = (counts[id] or 0) + 1
		end
	end
	local exp = N / spec.k
	local chi, worst = 0, 0
	for i = 1, spec.n do
		for _, id in room.cands[i] do
			local v = counts[id] or 0
			chi += (v - exp) ^ 2 / exp
			worst = math.max(worst, math.abs(v - exp) / exp)
		end
	end
	local dof = spec.n * (spec.k - 1)
	-- the 0.001 critical value for 24 dof is 51.2
	truthy(chi < 51.2, string.format("uniform hiding over %d draws: chi-square %.1f on %d dof (< 51.2, p = 0.001)", N, chi, dof))
	print(string.format("  hiding: chi-square %.1f on %d dof over %d draws of one chapter-8 room; worst cell %.2f%% off", chi, dof, N, 100 * worst))
	local items = {}
	for i = 1, spec.n do items[i] = "key" end
	local function serial(t, depth)
		depth = depth or 0
		if type(t) ~= "table" then return tostring(t) end
		local keys = {}
		for k in t do table.insert(keys, tostring(k)) end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			local v = t[k]
			if v == nil then v = t[tonumber(k)] end
			table.insert(parts, k .. "=" .. serial(v, depth + 1))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	local before = serial(Dressing.payload(room, items, 3, Config))
	local a1 = Attempt.new(room, spec, Config, { intro = 0 })
	Attempt.hide(a1, randOf(1))
	local a2 = Attempt.new(room, spec, Config, { intro = 0 })
	Attempt.hide(a2, randOf(2))
	local differ = false
	for i = 1, spec.n do if a1.hidden[i] ~= a2.hidden[i] then differ = true end end
	truthy(differ, "two secrets for the same room differ")
	eq(serial(Dressing.payload(room, items, 3, Config)), before, "the payload is byte-identical whatever the secret")
end

--============================================================ the server-only copy carries no surprises
do
	local a = fresh(2, 9)
	local snap = Attempt.snapshot(a)
	truthy(type(snap.hidden) == "table" and #snap.hidden == a.spec.n, "the snapshot (ServerStorage rig) carries the hidden ids")
	eq(snap.looks, a.looks, "and the looks")
end

print(string.format("Attempt: %d passed, %d failed", passed, failed))
if failed > 0 then error("Attempt spec failed", 0) end
