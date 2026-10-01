-- Trust.spec — DESIGN.md §14: the trusted position. Copied from facility-nightmare/tests/Trust.spec.luau (md5
-- e8ab9695...) and moved to this game's geometry: 32-stud modules, 8-stud hatches, and the server's speed
-- following the module type (16 in air, 12 + Mag-Boots in vacuum) instead of walk / sprint. Every property the
-- original checked is still checked; the height clamp (§14 "a claimed height") is new.
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

local N = 5 -- 5x5: module 13 is centred on (0, 0), 14 on (32, 0), 15 on (64, 0), 18 on (0, 32)
local AIR, VAC = Config.Move.AirWalkSpeed, Config.Move.VacWalkSpeed
local F = Config.Server.TrustedSpeedFactor
local BURST = Config.Server.TrustedBurstSeconds
local S = Config.Station.CellSize
local HALF = S / 2
local BAND = Config.Station.HatchWidth / 2 -- a doorway's half-width

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
		x += AIR * 0.1 * 0.28 -- 22 studs over 5 s along a diagonal inside the module
		z += AIR * 0.1 * 0.28
		Trust.step(Config, t, x, z, 0.1, AIR, NONE)
	end
	near(t.x, x, 1e-6, "an honest walker's trusted x equals the claim")
	near(t.z, z, 1e-6, "…and z")
	eq(t.throttled, 0, "…and the throttle never engaged")
end

do -- a teleport is walked, at the server's speed x the factor
	local t = Trust.new(Config, N, 13, 0, 0)
	Trust.step(Config, t, 10, 0, 0.1, AIR, NONE)
	near(t.x, AIR * F * 0.1, 1e-9, "a 10-stud jump in one tick moves 16 x 1.35 x 0.1 = 2.16 studs")
	eq(t.throttled, 1, "…and counts as throttled")
end

do -- unused allowance banks, up to TrustedBurstSeconds
	local t = Trust.new(Config, N, 13, 0, 0)
	for _ = 1, 20 do Trust.step(Config, t, 0, 0, 0.1, AIR, NONE) end
	near(t.budget, AIR * F * 2, 1e-9, "2 s standing still banks 2 s of allowance")
	for _ = 1, 100 do Trust.step(Config, t, 0, 0, 0.1, AIR, NONE) end
	near(t.budget, AIR * F * BURST, 1e-9, "…capped at " .. BURST .. " s")
	Trust.step(Config, t, 12, 0, 0.1, AIR, NONE)
	near(t.x, 12, 1e-9, "a banked burst covers a 12-stud jitter in one tick")
end

do -- the cap follows the SERVER's speed for the module type, not the claim
	local vacT = Trust.new(Config, N, 13, -13, 0)
	local airT = Trust.new(Config, N, 13, -13, 0)
	local x = -13
	for _ = 1, 10 do
		x += AIR * F * 0.1 -- a client claiming 21.6 studs/s
		Trust.step(Config, vacT, x, 0, 0.1, VAC, NONE)
		Trust.step(Config, airT, x, 0, 0.1, AIR, NONE)
	end
	near(airT.x, x, 1e-6, "in air (16) the trusted position keeps up with 16 x 1.35")
	truthy(vacT.x < x - 1, "in vacuum (12) the same claim falls behind (" .. string.format("%.2f", vacT.x) .. " vs " .. x .. ")")
	near(vacT.x, -13 + VAC * F * 1, 1e-6, "…by exactly the 12 x 1.35 bound")
	-- the hatch crossing: an honest walker still at 16 for a ping after the server lowered them to 12
	local cross = Trust.new(Config, N, 13, 0, 0)
	local cx = 0
	for _ = 1, 5 do
		cx += AIR * 0.1
		Trust.step(Config, cross, cx, 0, 0.1, VAC, NONE)
	end
	eq(cross.throttled, 0, "an honest 16 studs/s walker is not throttled at the vacuum cap (12 x 1.35 = 16.2)")
end

--============================================================ 2. modules, hatches, walls

local function walkTo(t, x, z, seconds, speed, isOpen)
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		Trust.step(Config, t, x, z, 0.1, speed or AIR, isOpen)
	end
end

do -- through an open hatch
	local t = Trust.new(Config, N, 13, 0, 0)
	walkTo(t, S, 0, 3, AIR, doors({ { 13, 14 } }))
	eq(t.cell, 14, "an open hatch: the trusted module moves to the neighbour")
	near(t.x, S, 1e-6, "…and the trusted position arrives")
end

do -- the same claim with the hatch shut
	local t = Trust.new(Config, N, 13, 0, 0)
	walkTo(t, S, 0, 3, AIR, NONE)
	eq(t.cell, 13, "a closed hatch: the trusted module stays")
	near(t.x, HALF, 1e-6, "…and the trusted position is clamped at the module's edge")
end

do -- a claim on the far side of a WALL, 8 studs beside an open doorway, is reached THROUGH the doorway
	local t = Trust.new(Config, N, 13, 0, 8)
	local open = doors({ { 13, 14 } })
	local crossedAt, ticks, arrived = nil, 0, nil
	for _ = 1, 40 do
		local bz, bc = t.z, t.cell
		Trust.step(Config, t, S, 8, 0.1, AIR, open)
		ticks += 1
		if bc == 13 and t.cell == 14 then crossedAt = { bz, t.z } end
		if arrived == nil and math.abs(t.x - S) < 1e-6 and math.abs(t.z - 8) < 1e-6 then arrived = ticks end
	end
	eq(t.cell, 14, "a claim through the wall beside an open doorway ends in the claimed module")
	truthy(crossedAt ~= nil and math.abs(crossedAt[1]) <= BAND + AIR * F * 0.1 and math.abs(crossedAt[2]) <= BAND + AIR * F * 0.1,
		"…having crossed at the doorway, within one tick's walk of its 8-stud band (z "
			.. (crossedAt and string.format("%.2f -> %.2f", crossedAt[1], crossedAt[2]) or "never") .. ")")
	truthy(arrived ~= nil and arrived * 0.1 * AIR * F >= 2 * math.sqrt(HALF * HALF + (8 - BAND) ^ 2) - 1e-6,
		"…no sooner than the doorway route allows (" .. tostring(arrived) .. " ticks)")
end

do -- a banked burst reaches a routed claim in the tick it pays for it (squared up inside the band)
	local open = doors({ { 13, 14 } })
	local t = Trust.new(Config, N, 13, 10, -12)
	walkTo(t, 10, -12, 3, AIR, open)
	Trust.step(Config, t, 26, -12, 0.1, AIR, open)
	eq(t.cell, 14, "one tick with a full burst: into 14 through the doorway")
	truthy(math.abs(t.x - 26) < 1e-6 and math.abs(t.z + 12) < 1e-6,
		string.format("…and all the way to the claim, nothing wasted on the wall (%.3f, %.3f)", t.x, t.z))
	eq(t.throttled, 0, "…unthrottled")
end

do -- the same claim with every hatch of 13 shut: clamped at the wall, not dragged sideways
	local t = Trust.new(Config, N, 13, 0, 8)
	walkTo(t, S, 8, 3, AIR, NONE)
	eq(t.cell, 13, "a claim through a wall with no open doorway to that module does not change the module")
	near(t.x, HALF, 1e-6, "…clamped at the wall")
	near(t.z, 8, 1e-6, "…without being dragged sideways")
end

do -- a claim freeze while stepping through the 13->14 doorway and turning along 14's south wall
	local open = doors({ { 13, 14 } })
	local pts = {}
	local function seg(ax, az, bx, bz)
		local d = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local k = math.ceil(d / (AIR * 0.1))
		for i = 1, k do table.insert(pts, { ax + (bx - ax) * i / k, az + (bz - az) * i / k }) end
	end
	seg(10, -12, 18, -1)
	seg(18, -1, 26, -12)
	for _, freezeTicks in { 5, 8, 12, 15 } do
		local t = Trust.new(Config, N, 13, 10, -12)
		walkTo(t, 10, -12, 3, AIR, open)
		for i = 1, #pts + 40 do
			local seen = if i <= freezeTicks then { 10, -12 } else pts[math.min(i, #pts)]
			Trust.step(Config, t, seen[1], seen[2], 0.1, AIR, open)
		end
		eq(t.cell, 14, string.format("claims frozen %.1f s on the way through: the trusted module follows into 14", freezeTicks * 0.1))
		truthy(math.abs(t.x - 26) < 1e-6 and math.abs(t.z + 12) < 1e-6,
			string.format("…and the trusted position arrives (%.2f, %.2f)", t.x, t.z))
	end
end

do -- the doorway's own width is the limit (the claim is behind a SHUT 14->15 hatch: no route, the line decides)
	local inside = Trust.new(Config, N, 13, 0, BAND - 0.1)
	walkTo(inside, 2 * S, BAND - 0.1, 6, AIR, doors({ { 13, 14 } }))
	eq(inside.cell, 14, "0.1 studs inside the doorway's edge is still inside it")
	near(inside.x, S + HALF, 1e-6, "…and the line stops at 14's shut far hatch")
	local outside = Trust.new(Config, N, 13, 0, BAND + 0.1)
	walkTo(outside, 2 * S, BAND + 0.1, 6, AIR, doors({ { 13, 14 } }))
	eq(outside.cell, 13, "0.1 studs outside it is the wall")
	near(outside.x, HALF, 1e-6, "…clamped at it")
	local routed = Trust.new(Config, N, 13, 0, BAND + 0.1)
	local crossed
	for _ = 1, 40 do
		local bz, bc = routed.z, routed.cell
		Trust.step(Config, routed, S, BAND + 0.1, 0.1, AIR, doors({ { 13, 14 } }))
		if bc == 13 and routed.cell == 14 then crossed = { bz, routed.z } end
	end
	eq(routed.cell, 14, "a claim just outside the band in the open neighbour is reached")
	truthy(crossed ~= nil and math.abs(crossed[1]) <= BAND and math.abs(crossed[2]) <= BAND + AIR * F * 0.1,
		"…by stepping inside the band to cross (z " .. (crossed and string.format("%.2f -> %.2f", crossed[1], crossed[2]) or "never") .. ")")
end

do -- a teleport two modules away is walked, one adjacent module at a time
	local open = doors({ { 13, 14 }, { 14, 15 } })
	local t = Trust.new(Config, N, 13, 0, 0)
	local visited = { 13 }
	for _ = 1, 60 do
		Trust.step(Config, t, 2 * S, 0, 0.1, AIR, open)
		if visited[#visited] ~= t.cell then table.insert(visited, t.cell) end
	end
	eq(table.concat(visited, ">"), "13>14>15", "a claim two modules over is reached through 14, never jumped")
	local t2 = Trust.new(Config, N, 13, 0, 0)
	Trust.step(Config, t2, 2 * S, 0, 0.1, AIR, open)
	eq(t2.cell, 13, "…and one tick after the claim the trusted module has not moved")
end

do -- a banked burst crossing two hatches in one tick still passes through each
	local t = Trust.new(Config, N, 13, 10, 0)
	for _ = 1, 30 do Trust.step(Config, t, 10, 0, 0.1, AIR, doors({ { 13, 14 } })) end
	Trust.step(Config, t, 60, 0, 0.1, AIR, doors({ { 13, 14 } }))
	eq(t.cell, 14, "a burst toward 15 stops in 14 when 14->15 is closed")
	near(t.x, S + HALF, 1e-6, "…clamped at 14's far edge")
end

do -- no diagonal jumps through a corner
	local t = Trust.new(Config, N, 13, 10, 10)
	local visited = { 13 }
	for _ = 1, 40 do
		Trust.step(Config, t, 22, 22, 0.1, AIR, doors({ { 13, 14 }, { 13, 18 }, { 14, 19 }, { 18, 19 } }))
		if visited[#visited] ~= t.cell then table.insert(visited, t.cell) end
	end
	local seq = table.concat(visited, ">")
	truthy(seq == "13>14>19" or seq == "13>18>19", "a claim in the diagonal module is reached through 14 or 18, never through the corner (" .. seq .. ")")
	local shut = Trust.new(Config, N, 13, 10, 10)
	walkTo(shut, 22, 22, 3, AIR, doors({ { 13, 14 }, { 13, 18 } }))
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

do -- HONEST WALKERS WITH LAG: hull-safe crossings (2 studs either side of a doorway's centre), claims that
	-- now and then freeze for 0.1-1.5 s; after each crossing the walker stands 4 s. The trusted module and
	-- position must then be the walker's.
	local rand = rngOf(20260930)
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
			Trust.step(Config, t, lastX, lastZ, 0.1, AIR, isOpen)
		end
		local function walk(tx, tz)
			local d = math.sqrt((tx - px) ^ 2 + (tz - pz) ^ 2)
			local k = math.max(1, math.ceil(d / (AIR * 0.1)))
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
			local ex = ax + dx * (HALF - 3) + (if dx == 0 then lat else 0)
			local ez = az + dz * (HALF - 3) + (if dz == 0 then lat else 0)
			walk(ex, ez)
			walk(ex + dx * 6, ez + dz * 6)
			walk(bx + (rand() * 2 - 1) * 13, bz + (rand() * 2 - 1) * 13)
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

do -- ADVERSARIAL CLAIMS: random points anywhere, through walls and shut hatches, burst cut to one tick
	local cfg = table.clone(Config)
	cfg.Server = table.clone(Config.Server)
	cfg.Server.TrustedBurstSeconds = 0.1
	local bound = AIR * F * 0.1
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
				tx, tz = (rand() * 2 - 1) * 100, (rand() * 2 - 1) * 100
			end
			local bx, bz, bc = t.x, t.z, t.cell
			Trust.step(cfg, t, tx, tz, 0.1, AIR, isOpen)
			ticks += 1
			local moved = math.sqrt((t.x - bx) ^ 2 + (t.z - bz) ^ 2)
			local ccx, ccz = centerOf(t.cell)
			local why = nil
			if moved > bound + 1e-6 then
				why = string.format("moved %.3f in a tick (bound %.3f)", moved, bound)
			elseif math.abs(t.x - ccx) > HALF + 1e-6 or math.abs(t.z - ccz) > HALF + 1e-6 then
				why = "trusted position outside its own module"
			elseif t.cell ~= bc then
				crossings += 1
				local ax, az = centerOf(bc)
				local dx, dz = (ccx - ax) / S, (ccz - az) / S
				if math.abs(dx) + math.abs(dz) ~= 1 then
					why = string.format("jumped %d -> %d, not neighbours", bc, t.cell)
				elseif not isOpen(bc, t.cell) then
					why = string.format("crossed %d -> %d through a SHUT hatch", bc, t.cell)
				else
					local lb = if dx ~= 0 then bz - az else bx - ax
					local la = if dx ~= 0 then t.z - az else t.x - ax
					if math.abs(lb) > BAND + bound + 1e-6 or math.abs(la) > BAND + bound + 1e-6 then
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
	eq(bad, 0, "never faster than the bound, never outside its module, never through a wall or a shut hatch (" .. table.concat(examples, "; ") .. ")")
end

do -- the grid edge is a wall too
	local t = Trust.new(Config, N, 15, 2 * S, 0)
	walkTo(t, 300, 0, 5, AIR, doors({}))
	eq(t.cell, 15, "walking off the grid's edge does not leave the module")
	near(t.x, 2 * S + HALF, 1e-6, "…clamped at the grid edge")
end

do -- bad dt and NaN claims change nothing
	local t = Trust.new(Config, N, 13, 1, 2)
	for _, dt in { 0 / 0, -1, 0, "x", math.huge } do
		Trust.step(Config, t, 20, 0, dt, AIR, NONE)
	end
	eq(t.x .. "," .. t.z .. "," .. t.budget, "1,2,0", "bad dt: no movement, no banked allowance")
	Trust.step(Config, t, 0 / 0, 0, 0.1, AIR, NONE)
	eq(t.x .. "," .. t.z, "1,2", "a NaN claim moves nothing")
end

do -- reset puts the trust where the SERVER placed the player, with an empty bank
	local t = Trust.new(Config, N, 13, 0, 0)
	walkTo(t, 0, 0, 5, AIR, NONE)
	Trust.reset(t, 7, -S, -S)
	eq(t.cell .. "," .. t.x .. "," .. t.z .. "," .. t.budget, "7," .. -S .. "," .. -S .. ",0", "reset: new module, new position, no banked burst")
end

--============================================================ 4. a claimed height (§14): never above one hop

do
	local St = Config.Station
	local vacTop = St.StandHeight + Config.Move.VacJumpHeight / Config.Move.VacGravityFactor
	local airTop = St.StandHeight + Config.Move.AirJumpHeight
	near(Trust.clampHeight(Config, 500, true), vacTop + 0.5, 1e-9, "in vacuum a claimed height is capped at one hop's apex (+0.5)")
	near(Trust.clampHeight(Config, 500, false), airTop + 0.5, 1e-9, "in air, at one jump's apex (+0.5)")
	near(Trust.clampHeight(Config, 3, true), 3, 1e-9, "an honest height is kept")
	near(Trust.clampHeight(Config, -40, true), 0, 1e-9, "never below the floor")
	near(Trust.clampHeight(Config, 0 / 0, false), St.StandHeight, 1e-9, "a NaN height reads as standing")
	-- the highest salvage is still within the pickup window of a real hop
	truthy(St.SalvageHeightMax - Trust.clampHeight(Config, 500, true) <= St.PickupHeightWindow,
		"the highest salvage is reachable at the vacuum cap")
end

--============================================================ 5. how far the trusted position went through vacuum
-- REVIEW-1 finding 1: AIR was charged only by the module a tick ENDED in, so a banked burst crossed a whole vacuum
-- module between two server ticks for free. The server now also charges the vacuum DISTANCE the trusted path
-- covered (Air.vacuumCharge), and Trust reports it: t.vacStuds, from the substeps it actually walked, per tick.

do
	local vacSet = { [14] = true }
	local function isVac(c) return vacSet[c] == true end
	local open = doors({ { 13, 14 }, { 14, 15 } })
	local t = Trust.new(Config, N, 13, 0, 0)
	for _ = 1, 40 do Trust.step(Config, t, 0, 0, 0.1, AIR, open, isVac) end -- bank the burst, standing in air
	eq(t.vacStuds, 0, "standing still in an air module walks no vacuum")
	Trust.step(Config, t, 2 * S, 0, 0.1, AIR, open, isVac) -- one claim: 15's centre, through vacuum module 14
	eq(t.cell, 15, "a banked burst crosses the vacuum module between two ticks")
	near(t.vacStuds, S, Config.Server.TrustSubstepStuds / 2, "…and reports the 32 studs it walked through vacuum")
	Trust.step(Config, t, 2 * S, 0, 0.1, AIR, open, isVac)
	eq(t.vacStuds, 0, "the next tick, standing in air: none")
	Trust.step(Config, t, S, 0, 0.1, AIR, open) -- the template's call, without isVac
	eq(t.vacStuds, 0, "without isVac (the template's call) it reports none")
end

do -- an honest walk through a vacuum module reports exactly its own steps
	local vacSet = { [14] = true }
	local function isVac(c) return vacSet[c] == true end
	local t = Trust.new(Config, N, 14, S - 10, 0)
	local x, sum = S - 10, 0
	for _ = 1, 10 do
		x += VAC * 0.1
		Trust.step(Config, t, x, 0, 0.1, VAC, NONE, isVac)
		near(t.vacStuds, VAC * 0.1, 1e-9, "an honest vacuum tick reports 1.2 studs")
		sum += t.vacStuds or 0
	end
	near(sum, VAC, 1e-9, "one second of honest vacuum walking reports 12 studs")
	Trust.step(Config, t, 0 / 0, 0, 0.1, VAC, NONE, isVac)
	eq(t.vacStuds, 0, "a NaN claim reports none")
end

do -- a claim just over a doorway's edge is walked to, not 0.5 past the edge and back (that detour was charged)
	local function isVac(_c) return true end
	local open = doors({ { 13, 14 } })
	local t = Trust.new(Config, N, 13, HALF - 0.8, 0)
	for _ = 1, 10 do Trust.step(Config, t, HALF - 0.8, 0, 0.1, VAC, open, isVac) end
	Trust.step(Config, t, HALF + 0.2, 0, 0.1, VAC, open, isVac)
	eq(t.cell, 14, "a claim 0.2 past the edge crosses")
	near(t.x, HALF + 0.2, 1e-9, "…and lands on the claim")
	near(t.vacStuds, 1.0, 1e-9, "…having walked exactly the 1.0 stud between, no detour")
end

do -- the way back over an opened route: 64 studs in one tick, half of them vacuum (the reviewer's B -> V -> dock)
	local vacSet = { [14] = true }
	local function isVac(c) return vacSet[c] == true end
	local open = doors({ { 13, 14 }, { 14, 15 } })
	local t = Trust.new(Config, N, 15, 2 * S, 0)
	for _ = 1, 40 do Trust.step(Config, t, 2 * S, 0, 0.1, AIR, open, isVac) end
	Trust.step(Config, t, 0, 0, 0.1, AIR, open, isVac)
	eq(t.cell, 13, "the explored corridor is crossed in one tick")
	near(t.vacStuds, S, Config.Server.TrustSubstepStuds / 2, "…and its 32 vacuum studs are reported")
end

print(string.format("Trust: %d passed, %d failed", passed, failed))
assert(failed == 0, "Trust tests failed")
