-- Runtime — the table semantics every gate leans on, checked on whatever runtime runs the gates.
-- Run: luau tests/Runtime.spec.luau   (or node tools/luaujs/luau.js tests/Runtime.spec.luau)
--
-- Why this exists (REVIEW-1 round 2, finding B5): every gate of this game ran on tools/luaujs, and luaujs lost a
-- table key after 32 deletions (its hash part compacted, then the new key was written into the stale map). In the
-- game's own harness the 34th player to join one server read sessions[plr] == nil. Real Luau has no such limit, so
-- on the native CLI every assertion here passes trivially; on a runtime with that defect it fails.
-- The shapes below are the game's: a table keyed by objects (sessions[plr], friendJobs[plr]) filled and emptied
-- over and over, string keys (friendCache, nameCache, toastAt), and number keys beyond the array part.

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do n += 1 end
	return n
end

--============================================================================ 1. object keys: join and leave 200 times
do
	local sessions = {}
	local lost, ghosts = 0, 0
	for i = 1, 200 do
		local plr = { UserId = i } -- a Player-like key
		sessions[plr] = { n = i }
		if sessions[plr] == nil or sessions[plr].n ~= i then lost += 1 end
		sessions[plr] = nil
		if count(sessions) ~= 0 then ghosts += 1 end
	end
	eq(lost, 0, "200 joins and leaves: every new key can be read back")
	eq(ghosts, 0, "...and a key set to nil never comes back in iteration")
end

--============================================================================ 2. object keys with residents that stay
do
	local t = {}
	local residents = {}
	for i = 1, 5 do
		local k = { id = -i }
		residents[i] = k
		t[k] = i
	end
	local bad = 0
	for i = 1, 300 do
		local k = { id = i }
		t[k] = i
		if t[k] ~= i or count(t) ~= 6 then bad += 1 end
		t[k] = nil
	end
	eq(bad, 0, "300 churns beside 5 residents: the new key reads back and the table holds exactly 6")
	local ok = 0
	for i, k in residents do
		if t[k] == i then ok += 1 end
	end
	eq(ok, 5, "the 5 residents survive the churn")
	eq(count(t), 5, "and nothing else is left")
end

--============================================================================ 3. string and number keys
do
	local t = {}
	local bad = 0
	for i = 1, 300 do
		local s = "u_" .. i
		t[s] = i
		t[1000 + i] = i
		if t[s] ~= i or t[1000 + i] ~= i then bad += 1 end
		t[s] = nil
		t[1000 + i] = nil
	end
	eq(bad, 0, "300 string and 300 sparse number keys read back")
	eq(count(t), 0, "and all are gone afterwards")
	eq(next(t), nil, "next() on the emptied table is nil")
end

--============================================================================ 4. many live keys, half deleted, then more inserts
do
	local t = {}
	for i = 1, 100 do t["k" .. i] = i end
	for i = 1, 100, 2 do t["k" .. i] = nil end
	for i = 101, 160 do t["k" .. i] = i end
	local bad = 0
	for i = 1, 160 do
		local want = if i <= 100 and i % 2 == 1 then nil else i
		if t["k" .. i] ~= want then bad += 1 end
	end
	eq(bad, 0, "after deleting half of 100 keys and adding 60 more, every key reads what was written")
	eq(count(t), 110, "and iteration sees exactly the 110 live keys")
end

print(string.format("Runtime: %d passed, %d failed", passed, failed))
if failed > 0 then error("Runtime spec failed", 0) end
