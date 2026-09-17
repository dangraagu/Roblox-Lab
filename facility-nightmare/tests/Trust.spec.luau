-- Trust.spec — DESIGN.md §14 Trust invariants, written before the module.
-- Run: luau tests/Trust.spec.luau
local Config = require("../src/shared/Config")
local Trust = require("../src/shared/Trust")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b) .. " +- " .. tol)
	end
end

local N = 5 -- 5x5: cell 13 is centred on (0, 0), 14 on (28, 0), 15 on (56, 0), 18 on (0, 28)
local WALK, SPRINT = Config.Movement.WalkSpeed, Config.Movement.SprintSpeed
local F = Config.Run.TrustedSpeedFactor
local BURST = Config.Run.TrustedBurstSeconds

local function doors(list)
	local set = {}
	for _, p in list do
		set[math.min(p[1], p[2]) .. "_" .. math.max(p[1], p[2])] = true
	end
	return function(a, b)
		return set[math.min(a, b) .. "_" .. math.max(a, b)] == true
	end
end
local NONE = doors({})

--============================================================ 1. the speed bound

do -- an honest walker is never throttled
	local t = Trust.new(Config, N, 13, -10, -10)
	local x, z = -10, -10
	for _ = 1, 50 do
		x += WALK * 0.1 * 0.28 -- 20 studs over 5 s along a diagonal inside the room
		z += WALK * 0.1 * 0.28
		Trust.step(Config, t, x, z, 0.1, WALK, NONE)
	end
	near(t.x, x, 1e-6, "an honest walker's trusted x equals the claim")
	near(t.z, z, 1e-6, "…and z")
	eq(t.throttled, 0, "…and the throttle never engaged")
end

do -- a teleport is walked, at the server's speed x the factor
	local t = Trust.new(Config, N, 13, 0, 0)
	Trust.step(Config, t, 10, 0, 0.1, WALK, NONE)
	near(t.x, WALK * F * 0.1, 1e-9, "a 10-stud jump in one tick moves 16 x 1.35 x 0.1 = 2.16 studs")
	eq(t.throttled, 1, "…and counts as throttled")
end

do -- unused allowance banks, up to TrustedBurstSeconds
	local t = Trust.new(Config, N, 13, 0, 0)
	for _ = 1, 20 do Trust.step(Config, t, 0, 0, 0.1, WALK, NONE) end
	near(t.budget, WALK * F * 2, 1e-9, "2 s standing still banks 2 s of allowance")
	for _ = 1, 100 do Trust.step(Config, t, 0, 0, 0.1, WALK, NONE) end
	near(t.budget, WALK * F * BURST, 1e-9, "…capped at " .. BURST .. " s")
	Trust.step(Config, t, 12, 0, 0.1, WALK, NONE)
	near(t.x, 12, 1e-9, "a banked burst covers a 12-stud jitter in one tick")
end

do -- 3. the cap follows the SERVER's speed, not the claim
	local walkT = Trust.new(Config, N, 13, -13, 0)
	local sprintT = Trust.new(Config, N, 13, -13, 0)
	local x = -13
	for _ = 1, 10 do
		x += SPRINT * 0.1
		Trust.step(Config, walkT, x, 0, 0.1, WALK, NONE)
		Trust.step(Config, sprintT, x, 0, 0.1, SPRINT, NONE)
	end
	near(sprintT.x, x, 1e-6, "a sprinter the server set to 24 keeps up with a 24 studs/s claim")
	truthy(walkT.x < x - 1, "a client claiming 24 studs/s while the server says 16 falls behind (" .. string.format("%.2f", walkT.x) .. " vs " .. x .. ")")
	near(walkT.x, -13 + WALK * F * 1, 1e-6, "…by exactly the 16 x 1.35 bound")
end

--============================================================ 2. cells, doors, walls

local function walkTo(t, x, z, seconds, speed, isOpen)
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		Trust.step(Config, t, x, z, 0.1, speed or WALK, isOpen)
	end
end

do -- through an open door
	local t = Trust.new(Config, N, 13, 0, 0)
	walkTo(t, 28, 0, 3, WALK, doors({ { 13, 14 } }))
	eq(t.cell, 14, "an open doorway: the trusted cell moves to the neighbour")
	near(t.x, 28, 1e-6, "…and the trusted position arrives")
end

do -- the same claim with the door shut
	local t = Trust.new(Config, N, 13, 0, 0)
	walkTo(t, 28, 0, 3, WALK, NONE)
	eq(t.cell, 13, "a closed door: the trusted cell stays")
	near(t.x, Config.Facility.CellSize / 2, 1e-6, "…and the trusted position is clamped at the room's edge")
end

do -- a claim on the far side of a WALL, 8 studs beside an open doorway, is reached THROUGH the
	-- doorway: never through the wall. (Until 2026-09-17 it was clamped at the wall instead. To the
	-- server that claim is indistinguishable from an honest player whose claims froze for 0.8 s
	-- while they stepped through the doorway and along the wall, and it pinned that player in the
	-- room behind them; see "a claim freeze" below.)
	local t = Trust.new(Config, N, 13, 0, 8)
	local open = doors({ { 13, 14 } })
	local crossedAt, ticks, arrived = nil, 0, nil
	for _ = 1, 30 do
		local bz, bc = t.z, t.cell
		Trust.step(Config, t, 28, 8, 0.1, WALK, open)
		ticks += 1
		if bc == 13 and t.cell == 14 then crossedAt = { bz, t.z } end
		if arrived == nil and math.abs(t.x - 28) < 1e-6 and math.abs(t.z - 8) < 1e-6 then arrived = ticks end
	end
	eq(t.cell, 14, "a claim through the wall beside an open doorway ends in the claimed room")
	truthy(crossedAt ~= nil and math.abs(crossedAt[1]) <= 3 + WALK * F * 0.1 and math.abs(crossedAt[2]) <= 3 + WALK * F * 0.1,
		"…having crossed at the doorway, within one tick's walk of its 6-stud band (z "
			.. (crossedAt and string.format("%.2f -> %.2f", crossedAt[1], crossedAt[2]) or "never") .. ")")
	-- through the doorway band's near edge the route from (0, 8) is at least 2 x sqrt(14^2 + 5^2)
	-- = 29.7 studs; the wall line is 28
	truthy(arrived ~= nil and arrived * 0.1 * WALK * F >= 2 * math.sqrt(14 * 14 + 5 * 5) - 1e-6,
		"…no sooner than the doorway route allows (" .. tostring(arrived) .. " ticks)")
end

do -- a banked burst reaches a routed claim in the tick it pays for it: the route squares up inside
	-- the doorway's band before it crosses, so none of the allowance is spent sliding along a wall
	-- (the 2026-09-17 sweep's N13 took the square-up out and nothing else noticed)
	local open = doors({ { 13, 14 } })
	local t = Trust.new(Config, N, 13, 10, -11)
	walkTo(t, 10, -11, 3, WALK, open)
	Trust.step(Config, t, 22, -11, 0.1, WALK, open)
	eq(t.cell, 14, "one tick with a full burst: into 14 through the doorway")
	truthy(math.abs(t.x - 22) < 1e-6 and math.abs(t.z + 11) < 1e-6,
		string.format("…and all the way to the claim, nothing wasted on the wall (%.3f, %.3f)", t.x, t.z))
	eq(t.throttled, 0, "…unthrottled")
end

do -- the same claim with every door of 13 shut: clamped at the wall, not dragged sideways
	local t = Trust.new(Config, N, 13, 0, 8)
	walkTo(t, 28, 8, 3, WALK, NONE)
	eq(t.cell, 13, "a claim through a wall with no open doorway to that room does not change the cell")
	near(t.x, 14, 1e-6, "…clamped at the wall")
	near(t.z, 8, 1e-6, "…without being dragged sideways")
end

do -- a claim freeze. An honest player steps through the 13->14 doorway and turns along 14's
	-- south wall, (10, -11) -> (14, -1) -> (22, -11) at 16 studs/s, while the server's copy of
	-- their position freezes. Measured before the fix: a freeze of 0.5 s was fine, and one of 0.8 s
	-- or longer left the trusted cell in 13 for good, pinned at (14, -11), so the rules ran in the
	-- room behind the player (its dark, its doors) while they stood in 14.
	local open = doors({ { 13, 14 } })
	local pts = {}
	local function seg(ax, az, bx, bz)
		local d = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local k = math.ceil(d / (WALK * 0.1))
		for i = 1, k do table.insert(pts, { ax + (bx - ax) * i / k, az + (bz - az) * i / k }) end
	end
	seg(10, -11, 14, -1)
	seg(14, -1, 22, -11)
	for _, freezeTicks in { 5, 8, 12, 15 } do
		local t = Trust.new(Config, N, 13, 10, -11)
		walkTo(t, 10, -11, 3, WALK, open) -- a full burst banked, as after any pause
		for i = 1, #pts + 40 do
			local seen = if i <= freezeTicks then { 10, -11 } else pts[math.min(i, #pts)]
			Trust.step(Config, t, seen[1], seen[2], 0.1, WALK, open)
		end
		eq(t.cell, 14, string.format("claims frozen %.1f s on the way through: the trusted cell follows into 14", freezeTicks * 0.1))
		truthy(math.abs(t.x - 22) < 1e-6 and math.abs(t.z + 11) < 1e-6,
			string.format("…and the trusted position arrives (%.2f, %.2f)", t.x, t.z))
	end
end

do -- the doorway's own width is the limit. The claim is in 15 behind a SHUT 14->15 door, so there
	-- is no route (rule 3) and the straight line decides: 2.9 studs off centre it passes the open
	-- 13->14 doorway and stops at 14's far wall; 3.1 studs off centre it is the wall.
	local inside = Trust.new(Config, N, 13, 0, 2.9)
	walkTo(inside, 56, 2.9, 5, WALK, doors({ { 13, 14 } }))
	eq(inside.cell, 14, "2.9 studs off the doorway's centre is still inside a 6-stud doorway")
	near(inside.x, 42, 1e-6, "…and the line stops at 14's shut far door")
	local outside = Trust.new(Config, N, 13, 0, 3.1)
	walkTo(outside, 56, 3.1, 5, WALK, doors({ { 13, 14 } }))
	eq(outside.cell, 13, "3.1 studs off centre is the wall")
	near(outside.x, 14, 1e-6, "…clamped at it")
	-- and a claim 3.1 studs off centre IN 14, with the doorway open, is routed into the band
	local routed = Trust.new(Config, N, 13, 0, 3.1)
	local crossed
	for _ = 1, 30 do
		local bz, bc = routed.z, routed.cell
		Trust.step(Config, routed, 28, 3.1, 0.1, WALK, doors({ { 13, 14 } }))
		if bc == 13 and routed.cell == 14 then crossed = { bz, routed.z } end
	end
	eq(routed.cell, 14, "a claim 3.1 studs off centre in the open neighbour is reached")
	truthy(crossed ~= nil and math.abs(crossed[1]) <= 3 and math.abs(crossed[2]) <= 3 + WALK * F * 0.1,
		"…by stepping inside the band to cross (z " .. (crossed and string.format("%.2f -> %.2f", crossed[1], crossed[2]) or "never") .. ")")
end

do -- a teleport three rooms away is walked, one adjacent room at a time
	local open = doors({ { 13, 14 }, { 14, 15 } })
	local t = Trust.new(Config, N, 13, 0, 0)
	local visited = { 13 }
	for _ = 1, 60 do
		Trust.step(Config, t, 56, 0, 0.1, WALK, open)
		if visited[#visited] ~= t.cell then table.insert(visited, t.cell) end
	end
	eq(table.concat(visited, ">"), "13>14>15", "a claim two rooms over is reached through 14, never jumped")
	local t2 = Trust.new(Config, N, 13, 0, 0)
	Trust.step(Config, t2, 56, 0, 0.1, WALK, open)
	eq(t2.cell, 13, "…and one tick after the claim the trusted cell has not moved")
end

do -- a banked burst crossing two open doors in one tick still passes through each
	local t = Trust.new(Config, N, 13, 10, 0)
	for _ = 1, 30 do Trust.step(Config, t, 10, 0, 0.1, SPRINT, doors({ { 13, 14 } })) end
	Trust.step(Config, t, 50, 0, 0.1, SPRINT, doors({ { 13, 14 } }))
	eq(t.cell, 14, "a burst toward 15 stops in 14 when 14->15 is closed")
	near(t.x, 42, 1e-6, "…clamped at 14's far edge")
end

do -- no diagonal jumps through a corner
	local t = Trust.new(Config, N, 13, 10, 10)
	local visited = { 13 }
	for _ = 1, 30 do
		Trust.step(Config, t, 20, 20, 0.1, WALK, doors({ { 13, 14 }, { 13, 18 }, { 14, 19 }, { 18, 19 } }))
		if visited[#visited] ~= t.cell then table.insert(visited, t.cell) end
	end
	local seq = table.concat(visited, ">")
	truthy(seq == "13>14>19" or seq == "13>18>19", "a claim in the diagonal room is reached through 14 or 18, never through the corner (" .. seq .. ")")
	local shut = Trust.new(Config, N, 13, 10, 10)
	walkTo(shut, 20, 20, 3, WALK, doors({ { 13, 14 }, { 13, 18 } }))
	eq(shut.cell, 13, "with 14->19 and 18->19 shut, the same claim cannot enter 19 at all")
end

--============================================================ 3. properties, over random mazes

local function rngOf(seed)
	local st = seed
	return function()
		st = (st * 1103515245 + 12345) % 2147483648
		return st / 2147483648
	end
end
local S = Config.Facility.CellSize
local function centerOf(c)
	local cx = (c - 1) % N
	local cy = (c - 1 - cx) / N
	return (cx - (N - 1) / 2) * S, (cy - (N - 1) / 2) * S
end
local function neighbours(c)
	local cx = (c - 1) % N
	local out = {}
	if cx < N - 1 then table.insert(out, c + 1) end
	if cx > 0 then table.insert(out, c - 1) end
	if c + N <= N * N then table.insert(out, c + N) end
	if c - N >= 1 then table.insert(out, c - N) end
	return out
end
local function randomDoors(rand)
	local list = {}
	for c = 1, N * N do
		for _, nb in neighbours(c) do
			if nb > c and rand() < 0.55 then table.insert(list, { c, nb }) end
		end
	end
	return doors(list)
end

do -- HONEST WALKERS WITH LAG. A walker crosses real doorways (hull-safe: at most 2 studs either
	-- side of a doorway's centre; room interiors within 12 studs of centre) at 16 studs/s, while the
	-- server's copy of the claim now and then freezes for 0.1-1.5 s and then jumps to where the
	-- walker is. After every crossing the walker stands still for 4 s. The trusted cell and
	-- position must then be the walker's.
	local rand = rngOf(20260917)
	local stops, wrong, frozenTicks, examples = 0, 0, 0, {}
	for _ = 1, 150 do
		local isOpen = randomDoors(rand)
		local cell = math.floor(rand() * N * N) + 1
		local px, pz = centerOf(cell)
		local t = Trust.new(Config, N, cell, px, pz)
		local freeze, lastX, lastZ = 0, px, pz
		local function tickTo(x, z)
			if freeze <= 0 and rand() < 0.04 then freeze = math.floor(1 + rand() * 15) end
			if freeze > 0 then
				freeze -= 1
				frozenTicks += 1
			else
				lastX, lastZ = x, z
			end
			Trust.step(Config, t, lastX, lastZ, 0.1, WALK, isOpen)
		end
		local function walk(tx, tz)
			local d = math.sqrt((tx - px) ^ 2 + (tz - pz) ^ 2)
			local k = math.max(1, math.ceil(d / (WALK * 0.1)))
			local ox, oz = px, pz
			for i = 1, k do
				px, pz = ox + (tx - ox) * i / k, oz + (tz - oz) * i / k
				tickTo(px, pz)
			end
		end
		for _ = 1, 25 do
			local opts = {}
			for _, nb in neighbours(cell) do
				if isOpen(cell, nb) then table.insert(opts, nb) end
			end
			if #opts == 0 then break end
			local nb = opts[math.floor(rand() * #opts) + 1]
			local ax, az = centerOf(cell)
			local bx, bz = centerOf(nb)
			local dx, dz = (bx - ax) / S, (bz - az) / S
			local lat = (rand() * 2 - 1) * 2
			-- approach 3 studs short of the doorway at the crossing's lateral offset, cross, then
			-- wander anywhere in the new room's interior
			local ex = ax + dx * 11 + (if dx == 0 then lat else 0)
			local ez = az + dz * 11 + (if dz == 0 then lat else 0)
			walk(ex, ez)
			walk(ex + dx * 6, ez + dz * 6)
			walk(bx + (rand() * 2 - 1) * 12, bz + (rand() * 2 - 1) * 12)
			cell = nb
			freeze = 0
			for _ = 1, 40 do tickTo(px, pz) end
			stops += 1
			if t.cell ~= cell or math.abs(t.x - px) > 1e-6 or math.abs(t.z - pz) > 1e-6 then
				wrong += 1
				if #examples < 3 then
					table.insert(examples, string.format("walker in %d at (%.1f, %.1f), trusted %d at (%.1f, %.1f)", cell, px, pz, t.cell, t.x, t.z))
				end
			end
		end
	end
	truthy(stops > 1000 and frozenTicks > 1000, "control: " .. stops .. " stops, " .. frozenTicks .. " frozen ticks")
	eq(wrong, 0, "an honest walker is where the rules think, 4 s after stopping, whatever the lag (" .. table.concat(examples, "; ") .. ")")
end

do -- ADVERSARIAL CLAIMS. The claim jumps now and then to a random point anywhere, inside or outside
	-- the grid, through walls and shut doors. With the burst cut to one tick, a tick's movement is
	-- small enough to locate every doorway crossing.
	local cfg = table.clone(Config)
	cfg.Run = table.clone(Config.Run)
	cfg.Run.TrustedBurstSeconds = 0.1
	local bound = WALK * F * 0.1
	local rand = rngOf(4242)
	local ticks, crossings, bad, examples = 0, 0, 0, {}
	for _ = 1, 300 do
		local isOpen = randomDoors(rand)
		local cell = math.floor(rand() * N * N) + 1
		local sx, sz = centerOf(cell)
		local t = Trust.new(cfg, N, cell, sx, sz)
		local tx, tz = sx, sz
		for _ = 1, 200 do
			if rand() < 0.1 then
				tx, tz = (rand() * 2 - 1) * 90, (rand() * 2 - 1) * 90
			end
			local bx, bz, bc = t.x, t.z, t.cell
			Trust.step(cfg, t, tx, tz, 0.1, WALK, isOpen)
			ticks += 1
			local moved = math.sqrt((t.x - bx) ^ 2 + (t.z - bz) ^ 2)
			local ccx, ccz = centerOf(t.cell)
			local why = nil
			if moved > bound + 1e-6 then
				why = string.format("moved %.3f in a tick (bound %.3f)", moved, bound)
			elseif math.abs(t.x - ccx) > S / 2 + 1e-6 or math.abs(t.z - ccz) > S / 2 + 1e-6 then
				why = "trusted position outside its own cell"
			elseif t.cell ~= bc then
				crossings += 1
				local ax, az = centerOf(bc)
				local dx, dz = (ccx - ax) / S, (ccz - az) / S
				if math.abs(dx) + math.abs(dz) ~= 1 then
					why = string.format("jumped %d -> %d, not neighbours", bc, t.cell)
				elseif not isOpen(bc, t.cell) then
					why = string.format("crossed %d -> %d through a SHUT door", bc, t.cell)
				else
					local lb = if dx ~= 0 then bz - az else bx - ax
					local la = if dx ~= 0 then t.z - az else t.x - ax
					if math.abs(lb) > 3 + bound + 1e-6 or math.abs(la) > 3 + bound + 1e-6 then
						why = string.format("crossed %d -> %d %.2f / %.2f studs off the doorway's centre: through the wall", bc, t.cell, lb, la)
					end
				end
			end
			if why then
				bad += 1
				if #examples < 3 then table.insert(examples, why) end
			end
		end
	end
	truthy(crossings > 500, "control: " .. ticks .. " adversarial ticks crossed " .. crossings .. " doorways")
	eq(bad, 0, "never faster than the bound, never outside its cell, never through a wall or a shut door (" .. table.concat(examples, "; ") .. ")")
end

do -- the grid edge is a wall too
	local t = Trust.new(Config, N, 15, 56, 0)
	walkTo(t, 200, 0, 5, WALK, doors({}))
	eq(t.cell, 15, "walking off the grid's edge does not leave the cell")
	near(t.x, 70, 1e-6, "…clamped at the grid edge")
end

do -- bad dt and NaN claims change nothing
	local t = Trust.new(Config, N, 13, 1, 2)
	for _, dt in { 0 / 0, -1, 0, "x", math.huge } do
		Trust.step(Config, t, 20, 0, dt, WALK, NONE)
	end
	eq(t.x .. "," .. t.z .. "," .. t.budget, "1,2,0", "bad dt: no movement, no banked allowance")
	Trust.step(Config, t, 0 / 0, 0, 0.1, WALK, NONE)
	eq(t.x .. "," .. t.z, "1,2", "a NaN claim moves nothing")
end

do -- reset puts the trust where the SERVER placed the player, with an empty bank
	local t = Trust.new(Config, N, 13, 0, 0)
	walkTo(t, 0, 0, 5, WALK, NONE)
	Trust.reset(t, 7, -28, -28)
	eq(t.cell .. "," .. t.x .. "," .. t.z .. "," .. t.budget, "7,-28,-28,0", "reset: new cell, new position, no banked burst")
end

print(string.format("Trust: %d passed, %d failed", passed, failed))
