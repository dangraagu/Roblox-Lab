-- Spec for Grotto: Grow a Crystal's own pure rules for the cavern's eye candy.
-- Run: luau tests/Grotto.spec.luau
--
-- EnvBands, Rest and Visitors are game-agnostic. Grotto is the part that knows this game:
--   * the PROGRESS value is the number of chambers the player owns (the server pushes it in the
--     State event; it is the number the HUD's chamber button and the rubble caps already show);
--   * what a harvest looks like, by the refraction tier it rolled (a beam of light only for
--     Legendary and Mythic, as the owner's brief asks);
--   * the slow "geode pulse" breathing curve;
--   * WHERE every client-built piece of scenery goes, as plain tables in plot-local coordinates
--     (the same contract as Cavern.build: the client adds the plot origin and nothing else).
--     The geometry invariants are the point: nothing the client builds may stand in the socket
--     zone (the plates, the crystals on them and the player's view of them), nothing may leave the
--     sealed shell, the glow-worms hang from real ceiling and not from the light-shaft hole, water
--     pieces stay inside the pool, and the visitors' flight routes stay above everyone's head.
local Grotto = require("../src/shared/Grotto")
local Cavern = require("../src/shared/Cavern")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local C = Cavern.Const
local MAXC = Config.Economy.MaxChambers

--=========================================================================== progress
do
	eq(Grotto.progress(1, MAXC), 1, "one chamber is progress 1")
	eq(Grotto.progress(5, MAXC), 5, "five chambers is progress 5")
	eq(Grotto.progress(MAXC, MAXC), MAXC, "all chambers")
	eq(Grotto.progress(0, MAXC), 1, "below one clamps to 1 (the server never pushes it; a default must not go dark)")
	eq(Grotto.progress(99, MAXC), MAXC, "above the maximum clamps")
	eq(Grotto.progress(3.7, MAXC), 3, "a fraction floors (chambers are whole)")
	eq(Grotto.progress(0 / 0, MAXC), 1, "NaN is progress 1")
	eq(Grotto.progress(nil, MAXC), 1, "nil (no state yet) is progress 1")
	eq(Grotto.progress("7", MAXC), 1, "a string is not trusted as a number")
	eq(Grotto.progress(math.huge, MAXC), MAXC, "infinity clamps")
end

--=========================================================================== chambers from the world
-- The State push is not the only source: Roblox flushes a RemoteEvent that fired before any listener to
-- the FIRST connection only, and the HUD and the cavern both listen, so the cavern can miss the join push.
-- The sockets the server builds are the chambers themselves (6 per chamber, Socket_<uid>_<id>), and they
-- are in the world whatever the order scripts run in.
do
	local function world(ids)
		local set = {}
		for _, id in ids do set[id] = true end
		return function(id) return set[id] == true end
	end
	local function range(a, b) local t = {} for i = a, b do table.insert(t, i) end return t end
	eq(Grotto.chambersFromSockets(world({}), 6, MAXC), 0, "no sockets yet: nothing known (the plot is still being built)")
	eq(Grotto.chambersFromSockets(world(range(1, 6)), 6, MAXC), 1, "six sockets: one chamber")
	eq(Grotto.chambersFromSockets(world(range(1, 5)), 6, MAXC), 0, "a chamber counts only once its last socket is there (replication can split a batch)")
	eq(Grotto.chambersFromSockets(world(range(1, 48)), 6, MAXC), 8, "all 48: eight chambers")
	eq(Grotto.chambersFromSockets(world(range(1, 30)), 6, MAXC), 5, "30 sockets: five chambers")
	eq(Grotto.chambersFromSockets(world({ 6, 12, 18, 30 }), 6, MAXC), 3, "chambers count from 1 without a gap")
	eq(Grotto.chambersFromSockets(world(range(1, 60)), 6, MAXC), MAXC, "never more than the maximum")
end

--=========================================================================== chip text
do
	local bands = Config.Env.Bands
	local t1 = Grotto.chipText(bands, 1)
	truthy(string.find(t1, bands[1].name, 1, true) ~= nil, "chamber 1's chip names the first band (" .. t1 .. ")")
	truthy(string.find(t1, "Chamber " .. bands[2].from, 1, true) ~= nil, "and says which chamber opens the next one")
	local last = Grotto.chipText(bands, MAXC)
	truthy(string.find(last, bands[#bands].name, 1, true) ~= nil, "all chambers name the last band (" .. last .. ")")
	truthy(string.find(last, "Chamber", 1, true) == nil, "and promise no further chamber")
	-- every chamber count names the band EnvBands would name
	for c = 1, MAXC do
		local idx = 1
		for i, b in bands do if c >= b.from then idx = i end end
		truthy(string.find(Grotto.chipText(bands, c), bands[idx].name, 1, true) ~= nil,
			"chamber " .. c .. " names band " .. bands[idx].id)
	end
end

--=========================================================================== harvest bursts
do
	local rules = Config.Env.Harvest
	local prev = nil
	for t = 1, Config.MaxTier do
		local b = Grotto.burst(t, rules)
		truthy(type(b.shards) == "number" and b.shards >= 1, "tier " .. t .. " throws at least one shard")
		truthy(b.shards <= Config.Budget.MaxShards, "tier " .. t .. " stays inside the shard pool")
		eq(b.beam, t >= 5, "tier " .. t .. (t >= 5 and " gets" or " does not get") .. " the beam of light (Legendary and Mythic only)")
		if prev then
			truthy(b.shards >= prev.shards, "tier " .. t .. " throws no fewer shards than tier " .. (t - 1))
			truthy((b.ring and 1 or 0) >= (prev.ring and 1 or 0), "a ring, once earned, stays for higher tiers")
			truthy((b.flash and 1 or 0) >= (prev.flash and 1 or 0), "a flash, once earned, stays for higher tiers")
			truthy((b.shake or 0) >= (prev.shake or 0), "the shake never shrinks with the tier")
		end
		prev = b
	end
	eq(Grotto.burst(0, rules).shards, Grotto.burst(1, rules).shards, "a tier below 1 is treated as tier 1")
	eq(Grotto.burst(99, rules).beam, true, "a tier above Mythic is treated as Mythic")
	eq(Grotto.burst(0 / 0, rules).beam, false, "NaN is treated as tier 1")
	local b = Grotto.burst(6, rules)
	b.shards = 999
	eq(Grotto.burst(6, rules).shards ~= 999, true, "burst returns a copy: a caller cannot corrupt Config")
end

--=========================================================================== the full-screen flash, rate-limited
-- A Legendary seed always refracts to Legendary or Mythic, so a row of them harvested at a click rate
-- flashed on every click and stacked into a wash (review 2026-09-24, finding 3). The flash (and the Mythic
-- shake) waits out a cooldown; the burst, beam and card never do.
do
	eq(Grotto.flashDue(nil, 0, 2), true, "the first flash of the session is due")
	eq(Grotto.flashDue(nil, 12345, 2), true, "(whenever it comes)")
	eq(Grotto.flashDue(10, 10, 2), false, "not again in the same instant")
	eq(Grotto.flashDue(10, 10.25, 2), false, "not a click (0.25 s) later")
	eq(Grotto.flashDue(10, 11.99, 2), false, "not just inside the cooldown")
	eq(Grotto.flashDue(10, 12, 2), true, "due again once the cooldown has passed, exactly")
	eq(Grotto.flashDue(10, 60, 2), true, "and any time after")
	-- a row of six at 4 clicks/s, then a seventh after the cooldown
	local last, flashes = nil, 0
	for i = 0, 5 do
		local now = 100 + i * 0.25
		if Grotto.flashDue(last, now, 2) then flashes += 1; last = now end
	end
	eq(flashes, 1, "six harvests at 4 clicks/s: one flash")
	if Grotto.flashDue(last, 102.1, 2) then flashes += 1 end
	eq(flashes, 2, "the next harvest after the cooldown flashes again")
	-- one click per second for a minute: one flash per 2 s, so a flash is never on screen twice
	last, flashes = nil, 0
	for i = 0, 59 do
		if Grotto.flashDue(last, i, 2) then flashes += 1; last = i end
	end
	eq(flashes, 30, "a click a second for a minute: a flash every 2 s (30)")
	eq(Grotto.flashDue(10, 10, 0), true, "a cooldown of 0 is the old behaviour: every harvest flashes")
	eq(Grotto.flashDue(10, 10, 0 / 0), true, "a NaN cooldown does not silence the flash for good")
	eq(Grotto.flashDue(0 / 0, 10, 2), true, "a NaN last time does not silence it either")
	eq(Grotto.flashDue(10, 9, 2), false, "a clock that went backwards does not flash early")
end

--=========================================================================== pulse
do
	approx(Grotto.pulse(0, 8), 0, "the pulse starts at rest")
	approx(Grotto.pulse(4, 8), 1, "peaks at half the period")
	approx(Grotto.pulse(8, 8), 0, "and is back at rest after one period")
	local worst, lo, hi = 0, 1, 0
	local last = Grotto.pulse(0, 8)
	for i = 1, 8000 do
		local v = Grotto.pulse(i * 0.01, 8)
		worst = math.max(worst, math.abs(v - last))
		lo, hi = math.min(lo, v), math.max(hi, v)
		last = v
	end
	truthy(lo >= 0 and hi <= 1, "the pulse stays in 0..1")
	truthy(worst < 0.005, "and never jumps (largest step per 0.01 s: " .. string.format("%.5f", worst) .. ")")
	eq(Grotto.pulse(3, 0), 0, "a zero period is flat, not a division by zero")
	eq(Grotto.pulse(0 / 0, 8), 0, "a NaN time is flat")
end

--=========================================================================== layout
local L = Grotto.layout(Config, Rng, Cavern)
local L2 = Grotto.layout(Config, Rng, Cavern)

-- the rotated half extents of an element (same Rx*Ry*Rz as Cavern)
local RAD = math.pi / 180
local function half(e)
	local o = e.orientation or { x = 0, y = 0, z = 0 }
	local cx, sx = math.cos(o.x * RAD), math.sin(o.x * RAD)
	local cy, sy = math.cos(o.y * RAD), math.sin(o.y * RAD)
	local cz, sz = math.cos(o.z * RAD), math.sin(o.z * RAD)
	local r = {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
	local s = e.size
	local h = { s.x / 2, s.y / 2, s.z / 2 }
	if e.shape == "Ball" then
		local d = math.min(s.x, s.y, s.z) / 2
		return d, d, d
	end
	local out = {}
	for i = 1, 3 do
		out[i] = math.abs(r[i][1]) * h[1] + math.abs(r[i][2]) * h[2] + math.abs(r[i][3]) * h[3]
	end
	return out[1], out[2], out[3]
end

local function groundAt(z)
	if z < 0 then return 0 end
	if z >= C.PITCH * C.G then return 21 end
	local c = math.floor(z / C.PITCH)
	if c >= C.G - 1 then return C.RISE * c end -- the top terrace has no treads (Deck_7 is flat to the shelf)
	local r = z - C.PITCH * c
	if r >= 11 then return C.RISE * c + 3 end
	if r >= 9 then return C.RISE * c + 1.5 end
	return C.RISE * c
end

do
	truthy(type(L.pieces) == "table", "layout returns pieces")
	local want = { "poolShimmer", "glowworms", "shrooms", "waterfall", "geodeHeart", "seams" }
	for _, id in want do
		truthy(L.pieces[id] ~= nil and #L.pieces[id] > 0, "piece " .. id .. " has elements")
	end
	-- every band's pieces exist in the layout
	for _, b in Config.Env.Bands do
		for _, id in b.pieces or {} do
			truthy(L.pieces[id] ~= nil, "band " .. b.id .. " names a piece the layout builds: " .. id)
		end
	end

	-- deterministic: same config, same cavern (a rejoin sees the same glow-worms)
	local same = true
	for id, list in L.pieces do
		for i, e in list do
			local f = L2.pieces[id][i]
			if f == nil or f.position.x ~= e.position.x or f.position.y ~= e.position.y or f.position.z ~= e.position.z
				or f.size.x ~= e.size.x then
				same = false
			end
		end
	end
	truthy(same, "the layout is deterministic")

	local total, worstZone, worstShell, worstWater = 0, nil, nil, nil
	local SOCKET_X = 24.5 -- the outermost plate edge is |x| = 23.75
	for id, list in L.pieces do
		for _, e in list do
			total += 1
			local hx, hy, hz = half(e)
			local p = e.position
			-- inside the sealed shell (a piece may be buried into rock up to the wall thickness)
			local out = p.x - hx < -(C.HALF_W + C.WALL_T) or p.x + hx > C.HALF_W + C.WALL_T
				or p.z - hz < -14 - C.WALL_T or p.z + hz > 134 + C.WALL_T
				or p.y + hy > C.CEIL_TOP or p.y - hy < -3
			if out and worstShell == nil then worstShell = id .. " " .. tostring(e.name) end
			-- centre inside the interior
			if (math.abs(p.x) > C.HALF_W or p.z < -14 or p.z > 134 or p.y > C.CEIL_UNDER + 0.5) and worstShell == nil then
				worstShell = id .. " " .. tostring(e.name) .. " (centre outside the interior)"
			end
			if e.water then
				-- water pieces may be waded through, but only inside the pool
				if p.x - hx < -28.5 or p.x + hx > 28.5 or p.z - hz < 107.5 or p.z + hz > 130.5 then
					worstWater = id .. " " .. tostring(e.name)
				end
			else
				-- the socket zone: every plate, every crystal on it and the stand in front of it,
				-- from the entrance apron to the top terrace
				local x0, x1 = p.x - hx, p.x + hx
				local z0, z1 = p.z - hz, p.z + hz
				if x1 > -SOCKET_X and x0 < SOCKET_X and z1 > -14 and z0 < 104 then
					-- sample the ground under the piece's footprint; the zone reaches 9 studs up
					local zoneTop = 0
					local z = math.max(z0, -14)
					while z <= math.min(z1, 104) do
						zoneTop = math.max(zoneTop, groundAt(z) + 9)
						z += 0.5
					end
					if p.y - hy < zoneTop and worstZone == nil then
						worstZone = string.format("%s %s bottom y %.2f under zone top %.2f", id, tostring(e.name), p.y - hy, zoneTop)
					end
				end
				-- and the pool ring you walk around (shelf tops at y 21)
				if z1 > 104 and z0 < 134 and p.y - hy < 30 and worstZone == nil then
					worstZone = string.format("%s %s stands on the pool ring (bottom y %.2f)", id, tostring(e.name), p.y - hy)
				end
			end
		end
	end
	eq(worstShell, nil, "every piece is inside the sealed shell")
	eq(worstZone, nil, "no piece stands in the socket zone or on the walkway (nothing to walk through, nothing in front of a crystal)")
	eq(worstWater, nil, "water pieces stay inside the pool")
	print(string.format("  layout: %d elements across %d pieces", total, (function() local n = 0 for _ in L.pieces do n += 1 end return n end)()))
	truthy(total <= Config.Budget.MaxScenery, "the scenery fits its part budget (" .. total .. " <= " .. Config.Budget.MaxScenery .. ")")

	-- glow-worms hang from real ceiling, never from the light-shaft hole
	local inHole = 0
	for _, e in L.pieces.glowworms do
		local p = e.position
		if math.abs(p.x) < 14.5 and p.z > 111.5 and p.z < 126.5 then inHole += 1 end
	end
	eq(inHole, 0, "no glow-worm hangs in the light-shaft hole")

	-- a half-weight piece shows HALF of its elements, spread through the cavern, not bunched: the first half
	-- of the glow-worms has beads in every quarter of the cavern's length (-10..132). The mutation sweep
	-- found the first version of this (front AND back of z 52) passed with the natural order, because one
	-- strand of the first half happened to sit just past z 52.
	local worms = L.pieces.glowworms
	local n = #worms
	local firstHalf = math.ceil(n / 2)
	local quarters = { 0, 0, 0, 0 }
	for i = 1, firstHalf do
		local e = worms[i]
		if e.shape == "Ball" then
			local q = math.clamp(math.floor((e.position.z + 10) / (142 / 4)) + 1, 1, 4)
			quarters[q] += 1
		end
	end
	truthy(quarters[1] >= 1 and quarters[2] >= 1 and quarters[3] >= 1 and quarters[4] >= 1,
		string.format("the first half of the glow-worms reaches every quarter of the cavern (%d/%d/%d/%d beads)",
			quarters[1], quarters[2], quarters[3], quarters[4]))

	-- every element knows its display order, 1..n
	for id, list in L.pieces do
		local ok = true
		for i, e in list do
			if e.order ~= i then ok = false end
		end
		truthy(ok, "piece " .. id .. " elements are numbered in display order")
	end
end

--=========================================================================== emitters and zones
do
	for _, b in Config.Env.Bands do
		for _, w in b.weather or {} do
			truthy(L.emitters[w.kind] ~= nil, "band " .. b.id .. " weather " .. w.kind .. " has an emitter volume")
		end
	end
	for kind, z in L.zones do
		truthy(z.min.x >= -C.HALF_W and z.max.x <= C.HALF_W and z.min.z >= -14 and z.max.z <= 134 and z.max.y <= 48,
			"critter zone " .. kind .. " is inside the cavern")
		truthy(z.min.y >= 30 or kind == "wisp", "critter zone " .. kind .. " is above everybody's head (min y " .. z.min.y .. ")")
	end
	truthy(L.zones.wisp ~= nil, "wisps have a zone (they rise out of the pool up the light shaft)")
end

--=========================================================================== visitor routes
do
	for kind in Config.Visitors.Kinds do
		local route = L.routes[kind]
		truthy(route ~= nil and #route >= 4, "visitor " .. kind .. " has a flight route")
		if route then
			local worst, where = math.huge, nil
			local outside = nil
			for i = 0, 400 do
				local u = i / 400
				local p = Grotto.routePoint(route, u)
				local clear = p.y - (groundAt(p.z) + 5) -- the top of a standing avatar's head
				if clear < worst then worst, where = clear, p end
				local inHole = math.abs(p.x) < 14 and p.z > 112 and p.z < 126
				if math.abs(p.x) > C.HALF_W - 1 or p.z < -13 or p.z > 133 or (p.y > C.CEIL_UNDER - 0.5 and not inHole) then
					outside = outside or string.format("(%.1f, %.1f, %.1f) at u=%.3f", p.x, p.y, p.z, u)
				end
			end
			eq(outside, nil, "visitor " .. kind .. " flies inside the cavern (or up the light-shaft hole)")
			truthy(worst >= 4, string.format("visitor %s passes at least 4 studs over a standing head (closest %.1f at z %.0f)", kind, worst, where and where.z or 0))
			-- it arrives and leaves through the shaft hole, so nothing pops into existence mid-air
			local a, z = Grotto.routePoint(route, 0), Grotto.routePoint(route, 1)
			truthy(a.y > C.CEIL_UNDER and math.abs(a.x) < 14 and a.z > 112 and a.z < 126, "visitor " .. kind .. " enters down the light shaft")
			truthy(z.y > C.CEIL_UNDER and math.abs(z.x) < 14 and z.z > 112 and z.z < 126, "visitor " .. kind .. " leaves up the light shaft")
			-- smooth: no single step of 1/400 of the route jumps more than the route's own speed allows
			local maxStep = 0
			local prev = Grotto.routePoint(route, 0)
			for i = 1, 400 do
				local p = Grotto.routePoint(route, i / 400)
				local d = math.sqrt((p.x - prev.x) ^ 2 + (p.y - prev.y) ^ 2 + (p.z - prev.z) ^ 2)
				maxStep = math.max(maxStep, d)
				prev = p
			end
			truthy(maxStep < 3, string.format("visitor %s moves smoothly (largest step %.2f studs per 1/400 of the route)", kind, maxStep))
		end
	end
	local p = Grotto.routePoint({ { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 } }, 0.5)
	approx(p.x, 5, "a two-point route is a straight line")
	local q = Grotto.routePoint({ { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 } }, 7)
	approx(q.x, 10, "u past 1 clamps to the end")
end

print(string.format("Grotto: %d passed, %d failed", passed, failed))
if failed > 0 then error("Grotto spec failed", 0) end
