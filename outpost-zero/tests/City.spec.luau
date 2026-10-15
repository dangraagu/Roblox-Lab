-- City — a city's layout from its seed (slot order, lot templates, mirrors, facades) and the shelf geometry.
-- Pure; run: luau tests/City.spec.luau
--
-- What it pins (DESIGN 3.2-3.3 and 16): over 1 000 seeds every lot is inside r <= 73 and outside the plaza;
-- lots of one district are >= 4 studs apart and lots of different districts >= 6; every two sign posts are
-- >= 14 studs apart; every district has 3 Homes and 3 Workshops; district 1 always takes slot 0; keys are strings;
-- a seed always gives the same layout; the pad and the board stand on open plaza.

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local City = require("../src/shared/City")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end

--============================================================================ exact geometry helpers (the spec's own)
local function corners(l)
	local h = Config.Lots.Size / 2
	local out = {}
	for _, c in { { -h, -h }, { h, -h }, { h, h }, { -h, h } } do
		local x, z = City.slotXZ(l.slot, l.u + c[1], l.v + c[2])
		table.insert(out, { x, z })
	end
	return out
end
local function segDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
	local qx, qz = ax + dx * t, az + dz * t
	return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
end
local function inside(px, pz, poly)
	local sign = 0
	for i = 1, 4 do
		local a, b = poly[i], poly[i % 4 + 1]
		local cross = (b[1] - a[1]) * (pz - a[2]) - (b[2] - a[2]) * (px - a[1])
		local s = if cross > 0 then 1 elseif cross < 0 then -1 else 0
		if s ~= 0 then
			if sign == 0 then sign = s elseif s ~= sign then return false end
		end
	end
	return true
end
local function polyDist(A, B)
	for _, p in A do if inside(p[1], p[2], B) then return 0 end end
	for _, p in B do if inside(p[1], p[2], A) then return 0 end end
	local best = math.huge
	for _, p in A do
		for i = 1, 4 do best = math.min(best, segDist(p[1], p[2], B[i][1], B[i][2], B[i % 4 + 1][1], B[i % 4 + 1][2])) end
	end
	for _, p in B do
		for i = 1, 4 do best = math.min(best, segDist(p[1], p[2], A[i][1], A[i][2], A[i % 4 + 1][1], A[i % 4 + 1][2])) end
	end
	return best
end
local function originDist(poly)
	if inside(0, 0, poly) then return 0 end
	local best = math.huge
	for i = 1, 4 do best = math.min(best, segDist(0, 0, poly[i][1], poly[i][2], poly[i % 4 + 1][1], poly[i % 4 + 1][2])) end
	return best
end

--============================================================================ 1. one layout
do
	local L = City.layout(Config, 12345, Rng)
	eq(#L.lots, 36, "36 lots: 6 districts x 6")
	eq(L.slotOf[1], 0, "district 1 takes slot 0, in front of the arrival pad")
	local slotsUsed = {}
	for d = 1, 6 do
		local s = L.slotOf[d]
		truthy(type(s) == "number" and s >= 0 and s <= 5, "district " .. d .. " has a slot 0..5")
		truthy(not slotsUsed[s], "district " .. d .. "'s slot is its own")
		slotsUsed[s] = true
	end
	for _, l in L.lots do
		truthy(type(l.key) == "string" and string.match(l.key, "^%d_%d$") ~= nil, "lot key " .. tostring(l.key) .. " is a string d_i")
		eq(L.byKey[l.key], l, "byKey finds " .. l.key)
		truthy(l.zone == "H" or l.zone == "W", l.key .. " is a Home or a Workshop")
		truthy(l.facade >= 1 and l.facade <= 3 and l.facade % 1 == 0, l.key .. " has a facade 1..3")
		eq(l.slot, L.slotOf[l.d], l.key .. " lies in its district's slot")
	end
	local again = City.layout(Config, 12345, Rng)
	local same = true
	for i, l in L.lots do
		local m = again.lots[i]
		if l.key ~= m.key or l.x ~= m.x or l.z ~= m.z or l.zone ~= m.zone or l.facade ~= m.facade then same = false end
	end
	truthy(same, "the same seed always gives the same layout")
end

--============================================================================ 2. 1 000 seeds
do
	local worstCorner, minInner, worstIn, worstAcross, worstPost = 0, math.huge, math.huge, math.huge, math.huge
	local balanced, slot0, distinct = true, true, {}
	local postOutside = true
	local padClear = true
	local P = Config.Shelf
	for seed = 1, 1000 do
		local L = City.layout(Config, seed, Rng)
		local sig = {}
		for d = 1, 6 do table.insert(sig, L.slotOf[d] .. L.template[d] .. tostring(L.mirror[d])) end
		distinct[table.concat(sig, "|")] = true
		if L.slotOf[1] ~= 0 then slot0 = false end
		local count = {}
		local polys, posts = {}, {}
		for idx, l in L.lots do
			count[l.d] = count[l.d] or { H = 0, W = 0 }
			count[l.d][l.zone] += 1
			local poly = corners(l)
			polys[idx] = poly
			for _, c in poly do worstCorner = math.max(worstCorner, math.sqrt(c[1] ^ 2 + c[2] ^ 2)) end
			minInner = math.min(minInner, originDist(poly))
			local px, pz = City.postXZ(Config, l)
			posts[idx] = { px, pz }
			-- the post stands outside its own plate, toward the shelf centre
			if inside(px, pz, poly) then postOutside = false end
			-- the pad (6 x 6 at (0, -16)) and the board (at (-10, -16)) are never on a lot
			local pad = { { P.Arrival.x - 3, P.Arrival.z - 3 }, { P.Arrival.x + 3, P.Arrival.z - 3 }, { P.Arrival.x + 3, P.Arrival.z + 3 }, { P.Arrival.x - 3, P.Arrival.z + 3 } }
			if polyDist(pad, poly) < 4 or inside(P.Board.x, P.Board.z, poly) then padClear = false end
		end
		for d = 1, 6 do
			if count[d].H ~= 3 or count[d].W ~= 3 then balanced = false end
		end
		for i = 1, #L.lots do
			for j = i + 1, #L.lots do
				local a, b = L.lots[i], L.lots[j]
				local dc = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				if a.d == b.d then
					worstIn = math.min(worstIn, polyDist(polys[i], polys[j]))
				elseif dc < 40 then
					worstAcross = math.min(worstAcross, polyDist(polys[i], polys[j]))
				end
				local pd = math.sqrt((posts[i][1] - posts[j][1]) ^ 2 + (posts[i][2] - posts[j][2]) ^ 2)
				worstPost = math.min(worstPost, pd)
				-- a post never stands inside another lot
				if inside(posts[i][1], posts[i][2], polys[j]) or inside(posts[j][1], posts[j][2], polys[i]) then postOutside = false end
			end
		end
	end
	local n = 0
	for _ in distinct do n += 1 end
	print(string.format("  1000 seeds: furthest corner %.2f, nearest edge to the centre %.2f, gap in a district %.2f, across %.2f, posts %.2f; %d distinct slot/template/mirror layouts",
		worstCorner, minInner, worstIn, worstAcross, worstPost, n))
	truthy(worstCorner <= Config.Shelf.LotCornerMax, string.format("every lot corner within %d of the centre (%.2f; DESIGN 72.01)", Config.Shelf.LotCornerMax, worstCorner))
	truthy(minInner > Config.Shelf.PlazaRadius, string.format("no lot reaches into the plaza (nearest %.2f > %d)", minInner, Config.Shelf.PlazaRadius))
	truthy(worstIn >= Config.Lots.MinGap - 1e-9, string.format("lots of one district are >= %d studs apart (%.2f)", Config.Lots.MinGap, worstIn))
	truthy(worstAcross >= 6, string.format("lots of different districts are >= 6 studs apart (%.2f; the model sampled 6.09)", worstAcross))
	truthy(worstPost >= 14 - 1e-9, string.format("every two sign posts are >= 14 studs apart (%.2f)", worstPost))
	truthy(balanced, "every district of every seed has 3 Homes and 3 Workshops")
	truthy(slot0, "district 1 takes slot 0 for every seed")
	truthy(postOutside, "every post stands outside every plate")
	truthy(padClear, "the arrival pad (with a 4-stud margin) and the board are never on a lot")
	truthy(n >= 900, "1 000 seeds give at least 900 different slot/template/mirror layouts (" .. n .. ")")
end

--============================================================================ 3. shelves in the world
do
	local W = Config.World
	for k = 1, W.Shelves do
		local cx, cz = City.shelfCentre(Config, k)
		near(math.sqrt(cx * cx + cz * cz), W.RingRadius, 1e-9, "shelf " .. k .. " sits on the 220-stud ring")
		local nx, nz = City.shelfCentre(Config, k % W.Shelves + 1)
		near(math.sqrt((cx - nx) ^ 2 + (cz - nz) ^ 2) - 2 * W.ShelfRadius, 60, 1e-9, "shelf " .. k .. "'s rim is 60 studs from the next")
		-- round trip, and local -Z points at the ring's centre
		local wx, wz = City.toWorld(Config, k, 3, -7)
		local lx, lz = City.toLocal(Config, k, wx, wz)
		near(lx, 3, 1e-9, "toLocal(toWorld) x, shelf " .. k)
		near(lz, -7, 1e-9, "toLocal(toWorld) z, shelf " .. k)
		local fx, fz = City.toWorld(Config, k, 0, -10)
		near(math.sqrt(fx * fx + fz * fz), W.RingRadius - 10, 1e-9, "shelf " .. k .. "'s local -Z faces the ring's centre")
		eq(City.shelfAt(Config, cx + 5, cz - 5), k, "a point on shelf " .. k .. " is on shelf " .. k)
	end
	eq(City.shelfAt(Config, 0, 0), nil, "the ring's centre is open sky")
	local jump = 16 * 2 * math.sqrt(2 * 7.2 / 196.2)
	truthy(jump < 60, string.format("a jump carries %.1f studs, under the 60-stud gap between rims", jump))
end

--============================================================================ 4. locked signs, posts, validate
do
	local L = City.layout(Config, 777, Rng)
	for d = 2, 6 do
		local sx, sz = City.signXZ(Config, L.slotOf[d])
		local r = math.sqrt(sx * sx + sz * sz)
		near(r, Config.Shelf.SignU, 1e-9, "district " .. d .. "'s sign stands on its slot's axis, 45 out")
	end
	local l = L.lots[1]
	local px, pz = City.postXZ(Config, l)
	near(math.sqrt((px - l.x) ^ 2 + (pz - l.z) ^ 2), Config.Lots.PostInset, 1e-9, "the post is 5.5 studs from its lot's centre")
	truthy(math.sqrt(px * px + pz * pz) < math.sqrt(l.x * l.x + l.z * l.z), "on the shelf-centre (street) side")
	local ok, err = City.validate(Config, L)
	truthy(ok, "a generated layout validates (" .. tostring(err) .. ")")
	local broken = City.layout(Config, 777, Rng)
	broken.lots[2].x = broken.lots[1].x
	broken.lots[2].z = broken.lots[1].z
	truthy(not City.validate(Config, broken), "CONTROL: two lots on top of each other do not validate")
	-- a seed outside 1..SeedMax is refused (the caller redraws)
	truthy(not pcall(City.layout, Config, 0, Rng), "seed 0 is refused")
	truthy(not pcall(City.layout, Config, Config.Save.SeedMax + 1, Rng), "a seed over SeedMax is refused")
	-- seed overflow: the largest seed still gives exact integers in the LCG
	local big = City.layout(Config, Config.Save.SeedMax, Rng)
	eq(#big.lots, 36, "the largest seed lays out a full city")
end

print(string.format("City: %d passed, %d failed", passed, failed))
if failed > 0 then error("City spec failed", 0) end
