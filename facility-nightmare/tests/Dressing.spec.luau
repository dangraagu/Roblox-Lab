-- Spec for Dressing: what each environment band adds to a room, and the rules that keep it fair.
-- Run: luau tests/Dressing.spec.luau
--
-- The owner's brief for FACILITY: richer, never monotonous, but visuals must NOT make the game easier
-- to see than designed and must NOT hide fuses unfairly. So every piece a band adds to a built room is
-- checked here against REAL rooms from the real generator (Facility.planForSublevel), with the items the
-- plan put in them, by rules re-derived in this file rather than read back from the module:
--   * nothing stands where an item can (items keep ItemWallClearance off every wall);
--   * from anywhere a player can stand outside the wall band, nothing comes between their eye and any
--     spot an item could occupy (so no item is ever hidden by dressing, wherever the plan put it);
--   * nothing below the door height stands in front of a doorway (every wall's middle, door or not, so
--     the dressing does not even say where the doors are);
--   * nothing overhead enters the centre column (the lift's and the car's roofs, the light fixture);
--   * no dressing intersects a server prop;
--   * no glowing piece is amber or green like a fuse or a battery cell, and no dull piece is a bright
--     fuse-amber or cell-green either;
--   * particles never reach the item volume;
--   * a room's dressing is a function of its band, its id, the sublevel and its props — never of items;
--   * at most MaxPartsPerRoom parts, one emitter, three screens per room.
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local MazeGen = require("../src/shared/MazeGen")
local Facility = require("../src/shared/Facility")
local EnvBands = require("../src/shared/EnvBands")
local Dressing = require("../src/shared/Dressing")

local passed, failed = 0, 0
local fails = 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Env, F = Config.Env, Config.Facility
local INNER = F.CellSize / 2 - F.WallThickness -- 13
local EYE = 4.5 -- a standing R15 eye, [STUDIO] on the Studio list

--================================================================ colour helpers (hand values)

do
	local h, s, v = Dressing.hsv({ 255, 0, 0 })
	eq(h, 0, "red hue 0")
	eq(s, 1, "red saturation 1")
	eq(v, 1, "red value 1")
	h = Dressing.hsv({ 0, 255, 0 })
	eq(h, 120, "green hue 120")
	h = Dressing.hsv({ 0, 0, 255 })
	eq(h, 240, "blue hue 240")
	local l = Dressing.luma({ 255, 255, 255 })
	truthy(math.abs(l - 255) < 1e-6, "white luma 255")
	truthy(math.abs(Dressing.luma({ 0, 255, 0 }) - 0.7152 * 255) < 1e-6, "Rec. 709 luma weights")
	local fuse = Env.Base.fuse
	eq(Dressing.distinct(fuse, fuse, true), false, "a glowing fuse-amber is not distinct from a fuse")
	eq(Dressing.distinct({ 255, 150, 40 }, fuse, true), false, "…nor a slightly redder amber")
	truthy(Dressing.distinct({ 90, 200, 255 }, fuse, true), "a glowing cyan is")
	truthy(Dressing.distinct({ 240, 240, 240 }, fuse, true), "a glowing white is (no hue to confuse)")
	truthy(Dressing.distinct({ 110, 70, 50 }, fuse, false), "a dull rust brown is (far darker than a lit fuse)")
	eq(Dressing.distinct({ 230, 160, 60 }, fuse, false), false, "a bright amber paint is not")
	eq(Dressing.distinct({ 90, 220, 110 }, Env.Base.cell, true), false, "a glowing green is not distinct from a battery cell")
	-- light, not gamma (review finding 1, EYECANDY.md §11): hand values of the sRGB transfer function
	eq(Dressing.linear(0), 0, "sRGB 0 is no light")
	truthy(math.abs(Dressing.linear(255) - 1) < 1e-12, "sRGB 255 is full light")
	truthy(math.abs(Dressing.linear(10) - 10 / 255 / 12.92) < 1e-12, "below the knee (0.04045) the curve is linear: 10 -> 0.003035")
	truthy(math.abs(Dressing.linear(128) - 0.2158605) < 1e-6, "sRGB 128 is 21.6 % of the light, not 50 %")
	truthy(math.abs(Dressing.returned({ 255, 255, 255 }) - 1) < 1e-12, "a white surface under white light returns all of it")
	truthy(math.abs(Dressing.returned({ 255, 255, 255 }, { 0, 255, 0 }) - 0.7152) < 1e-12, "…under a green light, green's share (Rec. 709)")
	truthy(math.abs(Dressing.returned({ 255, 0, 0 }, { 0, 255, 0 })) < 1e-12, "a red surface under a green light returns nothing (per channel)")
	truthy(math.abs(Dressing.returned({ 128, 128, 128 }, { 128, 128, 128 }) - 0.2158605 ^ 2) < 1e-9, "grey under grey: the product of the two")
end

--================================================================ the checker is not vacuous

local function part(p)
	local out = {
		name = "Probe", piece = "probe", shape = "Block", class = p.class or "wall",
		min = p.min, max = p.max, color = p.color or { 90, 90, 96 }, material = p.material or "SmoothPlastic",
		emissive = p.emissive == true, transparency = 0, solid = true, emitter = p.emitter, screen = p.screen,
	}
	return out
end
local noProps = {}
do
	local okParts = { part({ min = { 11.2, 0, 8 }, max = { 13, 4, 10 } }) }
	truthy((Dressing.check(Env, F, okParts, noProps)), "control: a cabinet in the wall band, off the door column, passes")
	local cases = {
		{ "a part where an item can stand", { part({ min = { 3, 0, 3 }, max = { 4, 2, 4 } }) } },
		{ "a wall piece in a doorway's column below the door height", { part({ min = { 11.5, 0, -2 }, max = { 13, 4, 2 } }) } },
		{ "a wall piece just inside the door keep-out", { part({ min = { 11.5, 0, 6.5 }, max = { 13, 4, 8 } }) } },
		{ "an overhead piece in the centre column", { part({ class = "overhead", min = { -1, 9, -1 }, max = { 1, 13, 1 } }) } },
		{ "an 'overhead' piece hanging to eye height in the interior", { part({ class = "overhead", min = { 8, 4, 8 }, max = { 9, 13, 9 } }) } },
		{ "a part outside the room", { part({ min = { 12, 0, 8 }, max = { 14, 4, 10 } }) } },
		{ "a glowing amber part", { part({ emissive = true, color = { 255, 170, 60 }, min = { 11.2, 0, 8 }, max = { 13, 4, 10 } }) } },
		{ "a glowing green part", { part({ emissive = true, color = { 80, 230, 110 }, min = { 11.2, 0, 8 }, max = { 13, 4, 10 } }) } },
		{ "a Neon or Glass material on a dull part", { part({ material = "Neon", min = { 11.2, 0, 8 }, max = { 13, 4, 10 } }) } },
		{ "a film thicker than FilmMaxTop", { part({ class = "film", min = { -13, 0, -13 }, max = { 13, 0.6, 13 } }) } },
		{ "an emitter whose particles reach the item volume", { part({ min = { 11.2, 0, 8 }, max = { 13, 4, 10 },
			emitter = { rate = 4, life = { 1, 3 }, speed = { 2, 4 }, spread = 60, dir = "up", accel = { 0, 0, 0 }, size = 1, color = { 200, 200, 200 }, lightEmission = 0 } }) } },
		{ "a screen on a part that is not a plain Block (its face would point the wrong way)", { (function()
			local p = part({ min = { 12.5, 3, 8 }, max = { 13, 5, 10 }, screen = { kind = "monitor" } })
			p.shape = "Cylinder"
			return p
		end)() } },
		{ "an emitter above the per-room rate", { part({ min = { 11.2, 0, 8 }, max = { 13, 4, 10 },
			emitter = { rate = 999, life = { 0.2, 0.3 }, speed = { 0, 0.1 }, spread = 0, dir = "up", accel = { 0, 0, 0 }, size = 0.1, color = { 200, 200, 200 }, lightEmission = 0 } }) } },
	}
	for _, c in cases do
		local ok, why = Dressing.check(Env, F, c[2], noProps)
		eq(ok, false, "check() rejects " .. c[1] .. " (" .. tostring(why) .. ")")
	end
	do
		-- The item-volume rule on its own. The case above is also too wide (spread 60 > 45), so it is rejected
		-- before this rule is ever asked; the resume session's mutation D5 (rule removed) survived every suite.
		local plume = { rate = 4, life = { 1, 3 }, speed = { 2, 4 }, spread = 40, dir = "up", accel = { 0, 0, 0 }, size = 1,
			color = { 200, 200, 200 }, lightEmission = 0 }
		local ok, why = Dressing.check(Env, F, { part({ min = { 11.2, 0, 8 }, max = { 13, 4, 10 }, emitter = plume }) }, noProps)
		eq(ok, false, "check() rejects an emitter, legal in every other way, whose particles reach the item volume")
		truthy(type(why) == "string" and string.find(why, "item volume", 1, true) ~= nil, "…for that reason (" .. tostring(why) .. ")")
		local tight = { rate = 4, life = { 0.5, 1 }, speed = { 0.2, 0.4 }, spread = 5, dir = "up", accel = { 0, 0, 0 }, size = 1,
			color = { 200, 200, 200 }, lightEmission = 0 }
		truthy((Dressing.check(Env, F, { part({ min = { 11.2, 0, 8 }, max = { 13, 4, 10 }, emitter = tight }) }, noProps)),
			"control: the same host with a tight, short plume passes")
	end
	do
		local desk = { name = "Desk", min = { 9.5, 0, 8 }, max = { 13, 3, 11 } }
		local ok = Dressing.check(Env, F, { part({ min = { 11.2, 0, 9 }, max = { 13, 4, 10 } }) }, { desk })
		eq(ok, false, "check() rejects a part inside a server prop")
		local onTop = Dressing.check(Env, F, { part({ min = { 11.5, 3, 9 }, max = { 12.5, 4.2, 10 } }) }, { desk })
		truthy(onTop, "…but not one standing ON it")
	end
	do
		local many = {}
		for i = 1, Env.MaxPartsPerRoom + 1 do
			local z = 7.2 + (i % 5)
			table.insert(many, part({ class = "overhead", min = { 12, 12, z }, max = { 12.5, 12.4, z + 0.3 } }))
		end
		eq((Dressing.check(Env, F, many, noProps)), false, "check() rejects more than MaxPartsPerRoom parts")
	end
end

--================================================================ real rooms, every kit

local kits = Dressing.kitNames()
truthy(#kits >= 7, "a kit per band (" .. #kits .. ")")
for _, b in Env.Bands do
	truthy(Dressing.KITS[b.kit] ~= nil, "band " .. b.id .. " has a kit (" .. tostring(b.kit) .. ")")
end

local function propsOf(plan, room)
	local out = {}
	for _, pr in plan.props[room] or {} do
		table.insert(out, { name = pr.name,
			min = { pr.x - pr.sx / 2, pr.y - pr.sy / 2, pr.z - pr.sz / 2 },
			max = { pr.x + pr.sx / 2, pr.y + pr.sy / 2, pr.z + pr.sz / 2 } })
	end
	return out
end
local function itemBox(plan, room)
	local it = plan.items[room]
	if not it then return nil end
	local s = if it.kind == "fuse" then { 0.8, 1.8, 0.8 } else { 1, 1.4, 1 }
	local y = if it.kind == "fuse" then 1.6 else 1.4
	return { min = { it.x - s[1] / 2, y - s[2] / 2, it.z - s[3] / 2 }, max = { it.x + s[1] / 2, y + s[2] / 2, it.z + s[3] / 2 },
		c = { it.x, y, it.z } }
end
local function overlap(a, b, pad)
	pad = pad or 0
	for i = 1, 3 do
		if a.min[i] >= b.max[i] + pad - 1e-6 or b.min[i] >= a.max[i] + pad - 1e-6 then return false end
	end
	return true
end
-- Does segment p->q pass through the open box (slab test)?
local function segHits(p, q, b)
	local t0, t1 = 0, 1
	for i = 1, 3 do
		local d = q[i] - p[i]
		local lo, hi = b.min[i] + 1e-6, b.max[i] - 1e-6
		if math.abs(d) < 1e-12 then
			if p[i] <= lo or p[i] >= hi then return false end
		else
			local a, c = (lo - p[i]) / d, (hi - p[i]) / d
			if a > c then a, c = c, a end
			t0, t1 = math.max(t0, a), math.min(t1, c)
			if t0 >= t1 then return false end
		end
	end
	return true
end
local function colourDistinct(c, ref, emissive)
	-- re-derived here: hue within 30 degrees of the item AND (glowing, or bright and saturated) = confusable
	local function hsv(col)
		local r, g, b = col[1] / 255, col[2] / 255, col[3] / 255
		local mx, mn = math.max(r, g, b), math.min(r, g, b)
		local d = mx - mn
		local h = 0
		if d > 0 then
			if mx == r then h = 60 * (((g - b) / d) % 6)
			elseif mx == g then h = 60 * ((b - r) / d + 2)
			else h = 60 * ((r - g) / d + 4) end
		end
		return h, if mx > 0 then d / mx else 0, mx
	end
	local h1, s1, v1 = hsv(c)
	local h2, _, v2 = hsv(ref)
	local dh = math.abs(h1 - h2) % 360
	dh = math.min(dh, 360 - dh)
	if dh >= 30 then return true end
	if emissive then return s1 <= 0.2 end
	return s1 <= 0.25 or v1 <= 0.6 * v2
end

local doorHalf = F.DoorWidth / 2 + Env.DoorKeepOut
local stats = { rooms = 0, parts = 0, byKit = {}, templates = {}, emitters = 0 }
local problems = {}
local function problem(msg)
	if #problems < 12 then table.insert(problems, msg) end
end

local roomsTested = 0
for _, kit in kits do
	stats.byKit[kit] = { rooms = 0, parts = 0, min = math.huge, max = 0, templates = {} }
	for i = 1, 60 do
		local k = 1 + (i % 14)
		local seeds = { layout = i * 2654435 + 17, loot = i * 40503 + 3, decor = i * 69069 + 11 }
		local plan = Facility.planForSublevel(Config, k, seeds, Rng, MazeGen)
		local room = 1 + (i * 7) % plan.n2
		local props = propsOf(plan, room)
		local parts = Dressing.build(Env, F, kit, room, k, props)
		roomsTested += 1
		local ok, why = Dressing.check(Env, F, parts, props)
		if not ok then problem(kit .. " room " .. room .. " k " .. k .. ": check() " .. tostring(why)) end
		local ks = stats.byKit[kit]
		ks.rooms += 1
		ks.parts += #parts
		ks.min = math.min(ks.min, #parts)
		ks.max = math.max(ks.max, #parts)
		local emitters, screens = 0, 0
		for _, p in parts do
			ks.templates[p.piece] = true
			if p.emitter then emitters += 1 end
			if p.screen then screens += 1 end
			-- a. nowhere an item can stand; nowhere near THIS room's real item
			local interior = { min = { -(INNER - F.ItemWallClearance) - 1, 0, -(INNER - F.ItemWallClearance) - 1 },
				max = { INNER - F.ItemWallClearance + 1, 3.5, INNER - F.ItemWallClearance + 1 } }
			if p.class ~= "film" and overlap(p, interior) then problem(kit .. ": " .. p.name .. " stands in the item volume") end
			local ib = itemBox(plan, room)
			if ib and p.class ~= "film" and overlap(p, ib, 1) then problem(kit .. ": " .. p.name .. " within a stud of the real item") end
			-- c. door columns
			if p.class ~= "film" and p.min[2] < F.DoorHeight + 0.5 then
				for _, w in { { 1, 3 }, { -1, 3 }, { 3, 1 }, { -3, 1 } } do
					local axis, sign = math.abs(w[1]), if w[1] > 0 then 1 else -1
					local along = w[2]
					local nearWall = if sign > 0 then p.max[axis] > INNER - Env.WallBand else p.min[axis] < -INNER + Env.WallBand
					if nearWall and p.max[along] > -doorHalf and p.min[along] < doorHalf then
						problem(kit .. ": " .. p.name .. " stands in front of a doorway below the door height")
					end
				end
			end
			-- d. overhead
			if p.class == "overhead" then
				if p.min[2] < Env.OverheadMinY - 1e-9 then problem(kit .. ": overhead " .. p.name .. " hangs below OverheadMinY") end
				local k2 = Env.OverheadPadKeepOut
				if p.max[1] > -k2 and p.min[1] < k2 and p.max[3] > -k2 and p.min[3] < k2 then
					problem(kit .. ": overhead " .. p.name .. " enters the centre column")
				end
			end
			if p.class == "film" and p.max[2] > Env.FilmMaxTop + 1e-9 then problem(kit .. ": film " .. p.name .. " too thick") end
			-- inside the room
			for ax = 1, 3, 2 do
				if p.min[ax] < -INNER - 1e-6 or p.max[ax] > INNER + 1e-6 then problem(kit .. ": " .. p.name .. " pokes through a wall") end
			end
			if p.min[2] < -1e-6 or p.max[2] > F.CeilingHeight + 1e-6 then problem(kit .. ": " .. p.name .. " pokes through the floor or ceiling") end
			-- e. props (a floor film lies under them, which is not intersecting anything)
			if p.class ~= "film" then
				for _, pr in props do
					if overlap(p, pr) then problem(kit .. ": " .. p.name .. " intersects prop " .. pr.name) end
				end
			end
			-- f. colours
			if not colourDistinct(p.color, Env.Base.fuse, p.emissive) or not colourDistinct(p.color, Env.Base.cell, p.emissive) then
				problem(kit .. ": " .. p.name .. " could pass for a fuse or a cell (" .. table.concat(p.color, ",") .. ")")
			end
			if p.emitter and p.emitter.lightEmission > 0 and (not colourDistinct(p.emitter.color, Env.Base.fuse, true)
				or not colourDistinct(p.emitter.color, Env.Base.cell, true)) then
				problem(kit .. ": glowing particles of " .. p.name .. " look like an item")
			end
			if not p.emissive and not Dressing.MATERIALS[p.material] then problem(kit .. ": material " .. tostring(p.material)) end
			if p.screen and p.shape ~= "Block" then problem(kit .. ": " .. p.name .. " carries a screen but is a " .. tostring(p.shape)) end
		end
		if #parts > Env.MaxPartsPerRoom then problem(kit .. ": " .. #parts .. " parts in one room") end
		if emitters > 1 then problem(kit .. ": " .. emitters .. " emitters in one room") end
		if screens > Env.MaxScreensPerRoom then problem(kit .. ": " .. screens .. " screens in one room") end
		stats.emitters += emitters
		-- b. the eye line: from every standing spot outside the wall band to every spot an item could be
		local blockers = {}
		for _, p in parts do
			if p.class ~= "film" and p.transparency < 0.95 then table.insert(blockers, p) end
		end
		for _, pr in props do table.insert(blockers, { min = pr.min, max = pr.max, prop = true }) end
		local lim = INNER - Env.WallBand
		local spot = INNER - F.ItemWallClearance
		for ex = -lim, lim, 3 do
			for ez = -lim, lim, 3 do
				local eye = { ex, EYE, ez }
				local standable = true
				for _, b in blockers do
					if b.min[1] - 1 < ex and ex < b.max[1] + 1 and b.min[3] - 1 < ez and ez < b.max[3] + 1 and b.min[2] < EYE then
						standable = false
					end
				end
				if standable then
					for _, sx in { -spot, 0, spot } do
						for _, sz in { -spot, 0, spot } do
							for _, sy in { 0.8, 1.6, 2.4 } do
								local target = { sx, sy, sz }
								for _, b in blockers do
									if not b.prop and segHits(eye, target, b) then
										problem(string.format("%s: %s is between an eye at (%g, %g) and an item spot (%g, %g, %g)",
											kit, b.name, ex, ez, sx, sy, sz))
									end
								end
							end
						end
					end
				end
			end
		end
		-- h. deterministic
		local again = Dressing.build(Env, F, kit, room, k, props)
		local same = #again == #parts
		for j = 1, math.min(#again, #parts) do
			local a, b = again[j], parts[j]
			for ax = 1, 3 do
				if a.min[ax] ~= b.min[ax] or a.max[ax] ~= b.max[ax] then same = false end
			end
			if a.piece ~= b.piece then same = false end
		end
		if not same then problem(kit .. ": the same room dressed twice came out different") end
		-- i. never a function of the items: another loot seed moves items, not dressing
		local plan2 = Facility.planForSublevel(Config, k, { layout = seeds.layout, loot = seeds.loot + 99991, decor = seeds.decor }, Rng, MazeGen)
		local parts2 = Dressing.build(Env, F, kit, room, k, propsOf(plan2, room))
		local same2 = #parts2 == #parts
		for j = 1, math.min(#parts2, #parts) do
			if parts2[j].piece ~= parts[j].piece or parts2[j].min[1] ~= parts[j].min[1] or parts2[j].min[3] ~= parts[j].min[3] then same2 = false end
		end
		-- props can differ when the item moved (a prop may not stand in the pickup circle), so compare only
		-- when this room's props are unchanged
		local propsSame = #propsOf(plan2, room) == #props
		if propsSame then
			for j, pr in propsOf(plan2, room) do
				if pr.min[1] ~= props[j].min[1] or pr.min[3] ~= props[j].min[3] then propsSame = false end
			end
		end
		if propsSame and not same2 then problem(kit .. ": another loot seed changed the dressing of a room whose props did not change") end
	end
end
for _, msg in problems do print("   " .. msg) end
eq(#problems, 0, string.format("%d real rooms x %d kits: every rule above holds", roomsTested // #kits, #kits))

for _, kit in kits do
	local ks = stats.byKit[kit]
	local n = 0
	for _ in ks.templates do n += 1 end
	print(string.format("    %-9s parts per room %2d..%2d, mean %4.1f, %2d pieces used", kit, ks.min, ks.max, ks.parts / ks.rooms, n))
	truthy(ks.parts / ks.rooms >= 6, kit .. ": a room is not bare (mean " .. ks.parts / ks.rooms .. " parts)")
	truthy(n >= 4, kit .. ": at least four different pieces across 60 rooms (" .. n .. ")")
end
truthy(stats.emitters > 0, "some rooms carry particles")

--================================================================ a rolled run finds a wall

do
	-- The flooded kit's dripping pipe has chance 1: "every flooded room drips". It used to try ONE random wall
	-- and give up if that wall was blocked, so 134 of 6 825 real rooms (13 of 300 entry rooms) had no emitter,
	-- and two checks that rely on it flaked. A rolled run now tries the other walls.
	local rooms, without, entries, entryWithout = 0, 0, 0, 0
	for seed = 1, 300 do
		local seeds = { layout = seed * 7919, loot = seed * 104729, decor = seed * 1299709 }
		local plan = Facility.planForSublevel(Config, 1 + seed % 12, seeds, Rng, MazeGen)
		for room = 1, plan.n2 do
			local parts = Dressing.build(Env, F, "flooded", room, 7, propsOf(plan, room))
			local e = false
			for _, p in parts do if p.emitter then e = true end end
			rooms += 1
			if not e then without += 1 end
			if room == plan.entry then
				entries += 1
				if not e then entryWithout += 1 end
			end
		end
	end
	eq(without, 0, "every one of " .. rooms .. " real flooded rooms has its dripping pipe (" .. entryWithout .. " of " .. entries .. " entry rooms without)")
end

--================================================================ which band dresses which room

do
	local bands = Env.Bands
	for i = 2, #bands do
		local b = bands[i]
		local seam = b.from - 1
		local takenAtSeam, takenBefore, takenAt = 0, 0, 0
		local N = 400
		for room = 1, N do
			if Dressing.roomBand(Env, EnvBands, seam, room) == i then takenAtSeam += 1 end
			if seam - 1 >= 1 and Dressing.roomBand(Env, EnvBands, seam - 1, room) == i then takenBefore += 1 end
			if Dressing.roomBand(Env, EnvBands, b.from, room) == i then takenAt += 1 end
		end
		local _, _, t = EnvBands.locate(bands, seam)
		local share = takenAtSeam / N
		truthy(math.abs(share - t) <= 0.08, string.format("%s at sublevel %d: %.2f of rooms foreshadow it (weight %.2f)", b.id, seam, share, t))
		eq(takenBefore, 0, b.id .. ": no room two sublevels early")
		eq(takenAt, N, b.id .. ": every room from sublevel " .. b.from)
	end
	eq(Dressing.roomBand(Env, EnvBands, 1, 5), 1, "sublevel 1 is the first band")
	eq(Dressing.roomBand(Env, EnvBands, 999, 5), #bands, "sublevel 999 is the last band")
end

print(string.format("Dressing: %d passed, %d failed", passed, failed))
