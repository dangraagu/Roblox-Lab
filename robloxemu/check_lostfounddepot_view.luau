-- Lost & Found Depot — what a player can TAP and what a player can SEE, from where a player stands.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_view.luau
--
-- WHY THIS FILE EXISTS (REVIEW-1 findings 6, 8 and 13). robloxemu has no Raycast and renders nothing,
-- so three defects were invisible to every other gate:
--   * each tray slot's invisible 3-stud hitbox rose above the next row's items, so a tap on a flat
--     back-row item from the bin side picked the front-row item in the same column (the tutorial
--     Phone: about 1 tap in 70);
--   * the opaque memo board hung between the spawn pad and the back-row tags, the Back Room door
--     and the backlog sign;
--   * every bin's sign board hung between a low follow camera and the player at that bin.
--
-- THE MODEL, stated so it can be argued with (every part of it is on the Studio list):
--   * a tap is a ray from the camera through the point the finger is on; the ClickDetector that
--     fires is the one on the FIRST CanQuery part along it, whatever its Transparency, or, for a
--     part inside a Model, the ClickDetector parented to that Model (Roblox's documented rule for
--     a ClickDetector in a Model). A tap reaches a tray slot when that first part is the slot's own
--     tile, or a piece of the item resting in the slot whose Model carries a ClickDetector;
--   * a point is visible when the first part with Transparency < 1 on the camera ray is the thing
--     the point is on;
--   * the camera is the classic follow camera: focus 1.5 studs above the root part, `d` studs back
--     along the facing, pitched `p` degrees down, and pulled in 0.5 studs short of the first part
--     with CanCollide = true and Transparency < 0.25 between the focus and the camera (the rule the
--     PlayerModule's Popper applies, from memory: CanCollide false parts do NOT pull it in);
--   * every Part is its oriented box (a Ball or Cylinder counts as its box: conservative for
--     "blocks", and item points are sampled well inside the inscribed shape).
--   * a SurfaceGui is ONE-SIDED: it draws on its Face, seen from in front of that face, and not at
--     all from behind. So a Transparency = 1 part whose SurfaceGui has an opaque background blocks
--     a ray exactly when the ray crosses that face from its front side (conservatively, the whole
--     face). An opaque part blocks from every side, as before. Both halves are on the Studio list.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-view", viewport = { 1280, 720 }, touch = false })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
-- The salt, pinned: the same depots every run.
local realRandom = Random
local unseeded = 0
Random = {
	new = function(seed)
		if seed == nil then
			unseeded += 1
			return realRandom.new(3000 + unseeded * 17)
		end
		return realRandom.new(seed)
	end,
}

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- Four bays: a brand-new player (career shift 1, the tutorial tray) and three on stage 3.
local store = h.services.DataStoreService:GetDataStore("LostFoundDepot_v1")
local UIDS = { 840001, 840002, 840003, 840004 }
for i = 2, #UIDS do
	store:SetAsync("u_" .. UIDS[i], { data = { v = 1, shifts = 5 + i, redeemed = {} } })
end

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot view: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))

local players = {}
for i, uid in UIDS do
	local p = h:join("V" .. i, uid)
	h:advance(0.1)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	players[i] = p
end
h:advance(1)

--============================================================================ geometry

local V3 = Vector3.new

-- Entry parameter t in [0, 1] of segment p0 -> p1 into the part's oriented box, or nil.
local function segBox(p0, p1, part)
	local cf = part.CFrame
	local a = cf:PointToObjectSpace(p0)
	local b = cf:PointToObjectSpace(p1)
	local hx, hy, hz = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
	local tmin, tmax = 0, 1
	local A = { a.X, a.Y, a.Z }
	local D = { b.X - a.X, b.Y - a.Y, b.Z - a.Z }
	local H = { hx, hy, hz }
	for i = 1, 3 do
		if math.abs(D[i]) < 1e-9 then
			if A[i] < -H[i] or A[i] > H[i] then return nil end
		else
			local t1 = (-H[i] - A[i]) / D[i]
			local t2 = (H[i] - A[i]) / D[i]
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	return tmin
end

-- The face a part's opaque SurfaceGui draws on, or nil. Any GuiObject with a background that is
-- not fully transparent counts, conservatively, as covering the whole face.
local FACE_AXIS = { Right = { 1, 1 }, Left = { 1, -1 }, Top = { 2, 1 }, Bottom = { 2, -1 }, Back = { 3, 1 }, Front = { 3, -1 } }
local function faceName(face) return string.match(tostring(face), "(%a+)$") end
local function opaqueGuiFace(part)
	for _, c in part:GetChildren() do
		if c.ClassName == "SurfaceGui" and c.Enabled ~= false then
			for _, g in c:GetDescendants() do
				if (g.ClassName == "TextLabel" or g.ClassName == "Frame" or g.ClassName == "TextButton"
					or g.ClassName == "ImageLabel") and g.BackgroundTransparency < 1 then
					return faceName(c.Face)
				end
			end
		end
	end
	return nil
end
-- Is a world point in front of (on the drawn side of) a part's GUI face?
local function inFrontOfFace(part, face, point)
	local ax = FACE_AXIS[face]
	local o = part.CFrame:PointToObjectSpace(point)
	local c = { o.X, o.Y, o.Z }
	local half = { part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2 }
	return ax[2] * c[ax[1]] > half[ax[1]]
end
-- t in [0, 1] at which p0 -> p1 is stopped by `part`, or nil. See THE MODEL above.
local function occludeT(part, p0, p1)
	if part.Transparency < 1 then
		return segBox(p0, p1, part)
	end
	local face = opaqueGuiFace(part)
	if face == nil then return nil end
	local ax = FACE_AXIS[face]
	local a = part.CFrame:PointToObjectSpace(p0)
	local b = part.CFrame:PointToObjectSpace(p1)
	local A, B = { a.X, a.Y, a.Z }, { b.X, b.Y, b.Z }
	local H = { part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2 }
	local i, s = ax[1], ax[2]
	if s * A[i] <= H[i] then return nil end -- p0 is behind the drawn face: nothing is drawn toward it
	local d = B[i] - A[i]
	if math.abs(d) < 1e-9 then return nil end
	local t = (s * H[i] - A[i]) / d
	if t < 0 or t > 1 then return nil end
	for j = 1, 3 do
		if j ~= i and math.abs(A[j] + (B[j] - A[j]) * t) > H[j] then return nil end
	end
	return t
end

-- Does a tap that first meets `hit` reach `slot`? (THE MODEL, above.)
local function reachesSlot(hit, slot)
	if hit == nil then return false end
	if hit == slot then return slot:FindFirstChildOfClass("ClickDetector") ~= nil end
	local item = slot:FindFirstChild("Item")
	return item ~= nil and hit:IsDescendantOf(item) and item:FindFirstChildOfClass("ClickDetector") ~= nil
end

local function bayParts(bay)
	local out = {}
	for _, d in bay:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, { part = d, pos = d.Position, r = d.Size.Magnitude / 2 })
		end
	end
	return out
end

-- The first part along p0 -> p1 that passes `filter`, and its t.
local function first(parts, p0, p1, filter)
	local dir = p1 - p0
	local len = dir.Magnitude
	local best, bestT = nil, math.huge
	for _, e in parts do
		-- cheap reject: the part's bounding sphere is nowhere near the segment
		local w = e.pos - p0
		local s = if len > 0 then math.clamp(w:Dot(dir) / (len * len), 0, 1) else 0
		if (e.pos - (p0 + dir * s)).Magnitude <= e.r + 1e-6 and filter(e.part) then
			local t = segBox(p0, p1, e.part)
			if t and t < bestT then best, bestT = e.part, t end
		end
	end
	return best, bestT
end

-- The first thing that STOPS THE EYE along p0 -> p1 (occludeT), skipping `exclude`.
local function firstVisible(parts, p0, p1, exclude)
	local dir = p1 - p0
	local len = dir.Magnitude
	local best, bestT = nil, math.huge
	for _, e in parts do
		local w = e.pos - p0
		local s = if len > 0 then math.clamp(w:Dot(dir) / (len * len), 0, 1) else 0
		if (e.pos - (p0 + dir * s)).Magnitude <= e.r + 1e-6 and not (exclude and exclude(e.part)) then
			local t = occludeT(e.part, p0, p1)
			if t and t < bestT then best, bestT = e.part, t end
		end
	end
	return best, bestT
end

local function camera(parts, rootPos, lookFlat, d, pitchDeg)
	local focus = rootPos + V3(0, 1.5, 0)
	local p = math.rad(pitchDeg)
	local cam = focus - lookFlat * (d * math.cos(p)) + V3(0, d * math.sin(p), 0)
	local hit, t = first(parts, focus, cam, function(q) return q.CanCollide and q.Transparency < 0.25 end)
	if hit then
		local len = (cam - focus).Magnitude
		cam = focus + (cam - focus) * math.max(0, t - 0.5 / len)
	end
	return cam
end

local function flatDir(from, to)
	local v = V3(to.X - from.X, 0, to.Z - from.Z)
	if v.Magnitude < 1e-6 then return V3(0, 0, -1) end
	return v.Unit
end

local ROOT_Y = 3.51 -- where the engine stands a root part on a floor-level pad (SPAWN-ORDER.md §2)

--============================================================================ taps

-- Where a tray tap is made from: the three columns of the bin side and of the pad side, inside the
-- ClickDetector's reach of the slot.
local TAP_STANDS = {
	bin = { { -4, -1 }, { 0, 0 }, { 4, -1 }, { -6, 1.5 }, { 6, 1.5 } },
	pad = { { -4, 12 }, { 0, 14 }, { 4, 12 }, { -6, 11 }, { 6, 11 } },
}
local TAP_CAMS = { { 8, 10 }, { 8, 30 }, { 12.5, 15 }, { 12.5, 35 }, { 16, 20 }, { 16, 45 } }
local POINTS = { { 0, 0, 0 }, { 0, 0.3, 0 }, { 0.3, 0, 0 }, { -0.3, 0, 0 }, { 0, 0, 0.3 }, { 0, 0, -0.3 } }

local tapStats = {} -- ["front/bin"] = { tot, ok }
local tutorialPhone = { bin = { tot = 0, ok = 0 }, pad = { tot = 0, ok = 0 } }
local wrongBy = {}
for pi, plr in players do
	local bay = plr.RespawnLocation.Parent
	local ox = bay:FindFirstChild("BayPad").Position.X
	local parts = bayParts(bay)
	for s = 1, 8 do
		local slot = bay:FindFirstChild("Slot_" .. s)
		local item = slot:FindFirstChild("Item")
		if item then
			local row = if s <= 4 then "front" else "back"
			local isPhone = pi == 1 and s == Config.Shift.Tutorial[2].slot
			local pieces = {}
			for _, c in item:GetDescendants() do
				if c:IsA("BasePart") then pieces[c] = true end
			end
			for side, stands in TAP_STANDS do
				for _, st in stands do
					local root = V3(ox + st[1], ROOT_Y, st[2])
					if (root - slot.Position).Magnitude <= Config.Bay.ItemReach then
						for _, cm in TAP_CAMS do
							local cam = camera(parts, root, flatDir(root, slot.Position), cm[1], cm[2])
							for piece in pieces do
								for _, o in POINTS do
									local pt = (piece.CFrame * CFrame.new(o[1] * piece.Size.X, o[2] * piece.Size.Y, o[3] * piece.Size.Z)).Position
									local seg = pt - cam
									local past = cam + seg * (1 + 0.05 / math.max(seg.Magnitude, 1e-6))
									local vis, tv = firstVisible(parts, cam, past, nil)
									if vis and pieces[vis] then
										local key = row .. "/" .. side
										tapStats[key] = tapStats[key] or { tot = 0, ok = 0 }
										tapStats[key].tot += 1
										local hit = first(parts, cam, past, function(q) return q.CanQuery end)
										if reachesSlot(hit, slot) then
											tapStats[key].ok += 1
										else
											local wn = if hit then hit.Name else "nothing"
											wrongBy[wn] = (wrongBy[wn] or 0) + 1
										end
										if isPhone then
											tutorialPhone[side].tot += 1
											if reachesSlot(hit, slot) then tutorialPhone[side].ok += 1 end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

do
	local wrong = {}
	for n, c in wrongBy do table.insert(wrong, n .. "=" .. c) end
	table.sort(wrong)
	print("  taps that landed elsewhere, by what took them: " .. (if #wrong > 0 then table.concat(wrong, " ") else "none"))
	for _, key in { "front/bin", "back/bin", "front/pad", "back/pad" } do
		local st = tapStats[key]
		if st then
			print(string.format("  tap on a visible point of a %-10s item: %5.1f%% reach that item (%d of %d)", key, 100 * st.ok / st.tot, st.ok, st.tot))
		end
	end
	for _, side in { "bin", "pad" } do
		local t = tutorialPhone[side]
		print(string.format("  the tutorial Phone from the %s side: %.1f%% (%d of %d)", side, if t.tot > 0 then 100 * t.ok / t.tot else 0, t.ok, t.tot))
	end
	for _, key in { "front/bin", "back/bin", "front/pad", "back/pad" } do
		local st = tapStats[key]
		truthy(st ~= nil and st.tot > 0, "CONTROL: visible points were found for " .. key .. " items")
		if st and st.tot > 0 then
			truthy(st.ok / st.tot >= 0.97, string.format("a tap on a visible point of a %s item picks THAT item (%.1f%%, want >= 97%%)", key, 100 * st.ok / st.tot))
		end
	end
	for _, side in { "bin", "pad" } do
		local t = tutorialPhone[side]
		truthy(t.tot > 0 and t.ok / t.tot >= 0.97, string.format("the tutorial Phone is tappable from the %s side (%.1f%%, want >= 97%%)", side,
			if t.tot > 0 then 100 * t.ok / t.tot else 0))
	end
end

--============================================================================ sightlines

-- A read target is hidden when the first part with Transparency < 1 on the camera -> target segment
-- is not the target. Blockers that are DECORATION (CanCollide = false boards) are the defect: the
-- camera never pulls in front of them, so the view stays blocked until the player finds the one
-- pitch that clears it. Collidable fixtures in the way are reported, not failed.
local READ_CAMS = {}
for _, d in { 8, 12.5, 16 } do
	for _, p in { 5, 10, 15, 20, 25, 30, 45 } do
		table.insert(READ_CAMS, { d, p })
	end
end

local decorBlocks, fixtureBlocks, sightChecks = {}, {}, 0
local function note(tbl, key) tbl[key] = (tbl[key] or 0) + 1 end

local function tagPoint(bay, s)
	local slot = bay:FindFirstChild("Slot_" .. s)
	local tag = slot:FindFirstChild("Tag")
	local anchor = tag.Adornee or slot
	return anchor.Position + tag.StudsOffset, tag.Enabled
end

-- A board read from the wrong side shows nothing at all under the one-sided model, so every board
-- that is a read target must face its reader. Counted against the reader's eye, not the camera: a
-- camera can swing anywhere, the head is where the player stands to read.
local wrongSide, sideChecks = {}, 0
local function guiFaceOf(part)
	for _, c in part:GetChildren() do
		if c.ClassName == "SurfaceGui" then return faceName(c.Face) end
	end
	return nil
end

local function sight(parts, label, root, lookAt, target, targetPart, ignore)
	local face = targetPart and guiFaceOf(targetPart)
	if face then
		sideChecks += 1
		if not inFrontOfFace(targetPart, face, root + V3(0, 1.5, 0)) then
			wrongSide[label] = true
		end
	end
	for _, cm in READ_CAMS do
		local cam = camera(parts, root, flatDir(root, lookAt), cm[1], cm[2])
		sightChecks += 1
		local hit = firstVisible(parts, cam, target, function(q)
			return q == targetPart or (ignore ~= nil and ignore(q))
		end)
		if hit then
			local key = string.format("%s: %s (d %.1f p %d)", label, hit.Name, cm[1], cm[2])
			if hit.CanCollide then note(fixtureBlocks, label .. " by " .. hit.Name) else note(decorBlocks, key) end
		end
	end
end

for pi, plr in players do
	local bay = plr.RespawnLocation.Parent
	local ox = bay:FindFirstChild("BayPad").Position.X
	local parts = bayParts(bay)
	local function isItem(q)
		local node = q.Parent
		return node ~= nil and node.Name == "Item"
	end
	local P = V3(ox, ROOT_Y, 0)
	local door = bay:FindFirstChild("Door")
	local backlog = bay:FindFirstChild("BacklogSign")
	-- 1. the spawn pad and the pad side of the tray, facing the arc: tags, the door, the backlog sign
	for _, st in { { 0, 14 }, { -4, 12 }, { 4, 12 } } do
		local root = V3(ox + st[1], ROOT_Y, st[2])
		local ahead = V3(ox + st[1], ROOT_Y, -30)
		local where = string.format("pad side (%d,%d)", st[1], st[2])
		for s = 1, 8 do
			local pt, shown = tagPoint(bay, s)
			if shown then sight(parts, where .. " -> tag " .. s, root, ahead, pt, nil, isItem) end
		end
		sight(parts, where .. " -> door", root, ahead, door.Position, door, isItem)
		sight(parts, where .. " -> backlog sign", root, ahead, backlog.Position, backlog, isItem)
	end
	-- 2. every bin's stand point, facing back to the tray: the tags
	for k = 1, 6 do
		local base = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Base")
		local flat = V3(base.Position.X, ROOT_Y, base.Position.Z)
		local root = flat + (P - flat).Unit * 5
		for s = 1, 8 do
			local pt, shown = tagPoint(bay, s)
			if shown then sight(parts, "bin " .. k .. " stand -> tag " .. s, root, P, pt, nil, isItem) end
		end
	end
	-- 3. the pick point: every bin's sign, and the memo board
	for k = 1, 6 do
		local sign = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Sign")
		sight(parts, "P -> bin " .. k .. " sign", P, sign.Position, sign.Position, sign, isItem)
	end
	local memo = bay:FindFirstChild("MemoBoard")
	sight(parts, "P -> memo board", P, memo.Position, memo.Position, memo, isItem)
	-- the bay's name sign, from the pick point and every bin stand (REVIEW-1 pass 3, U5: the memo board
	-- hung in front of it)
	local nameSign = bay:FindFirstChild("NameSign")
	sight(parts, "P -> name sign", P, nameSign.Position, nameSign.Position, nameSign, isItem)
	for k = 1, 6 do
		local base = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Base")
		local flat = V3(base.Position.X, ROOT_Y, base.Position.Z)
		sight(parts, "bin " .. k .. " stand -> name sign", flat + (P - flat).Unit * 5, nameSign.Position, nameSign.Position, nameSign, isItem)
	end
	-- 4. the manual board, from the pick point
	local manual = bay:FindFirstChild("ManualBoard")
	sight(parts, "P -> manual board", P, manual.Position, manual.Position, manual, isItem)
end

do
	local list = {}
	for k in wrongSide do table.insert(list, k) end
	table.sort(list)
	truthy(sideChecks > 0, "CONTROL: board facings were checked (" .. sideChecks .. ")")
	eq(#list, 0, "every board that is read faces its reader" .. (if #list > 0 then " (" .. table.concat(list, "; ") .. ")" else ""))
end

do
	local list = {}
	local total = 0
	for k, c in decorBlocks do
		table.insert(list, k .. " x" .. c)
		total += c
	end
	table.sort(list)
	local byBoard = {}
	for k, c in decorBlocks do
		local board = string.match(k, ": ([%w_]+) %(")
		byBoard[board] = (byBoard[board] or 0) + c
	end
	local boards = {}
	for b, c in byBoard do table.insert(boards, b .. "=" .. c) end
	table.sort(boards)
	print(string.format("  sightlines: %d camera x target checks; %d hidden by decoration (%s)", sightChecks, total,
		if #boards > 0 then table.concat(boards, " ") else "none"))
	for i = 1, math.min(#list, 8) do print("    " .. list[i]) end
	local fx = {}
	for k, c in fixtureBlocks do table.insert(fx, k .. " x" .. c) end
	table.sort(fx)
	print(string.format("  (reported, not failed) hidden by a collidable fixture: %d kinds", #fx))
	for i = 1, math.min(#fx, 6) do print("    " .. fx[i]) end
	eq(total, 0, "no tray tag, door, backlog sign, bin sign or memo board is ever hidden by a decorative board")
end

--============================================================================ tags in front of the memo board

-- REVIEW-1 pass 3, player-path finding 5. The tray tags are camera-facing BillboardGuis 3.6 x 1.3
-- studs, and the memo board hung 0.8 studs behind the back row: from the pick point and every bin
-- stand the tags covered about 40% of its face, most of its lower half. A BillboardGui is not a Part,
-- so the sightline model above never saw it. Here each shown tag is a camera-facing rectangle of its
-- own size at its slot + StudsOffset (world space: StudsOffset is really camera-relative, which the
-- Studio list carries), and a grid of points on the board's drawn face is tested against it from the
-- READ_CAMS cameras at the pick point and every bin stand.
do
	local FACE_POINT = {
		Front = function(sz, u, v) return V3(u * sz.X, v * sz.Y, -sz.Z / 2) end,
		Back = function(sz, u, v) return V3(u * sz.X, v * sz.Y, sz.Z / 2) end,
		Left = function(sz, u, v) return V3(-sz.X / 2, v * sz.Y, u * sz.Z) end,
		Right = function(sz, u, v) return V3(sz.X / 2, v * sz.Y, u * sz.Z) end,
	}
	local worst, sum, n = 0, 0, 0
	for _, plr in players do
		local bay = plr.RespawnLocation.Parent
		local ox = bay:FindFirstChild("BayPad").Position.X
		local parts = bayParts(bay)
		local memo = bay:FindFirstChild("MemoBoard")
		local face = guiFaceOf(memo)
		local tags = {}
		for s = 1, 8 do
			local slot = bay:FindFirstChild("Slot_" .. s)
			local tag = slot:FindFirstChild("Tag")
			if tag and tag.Enabled then
				table.insert(tags, { c = slot.Position + tag.StudsOffset, w = tag.Size.X.Scale, h = tag.Size.Y.Scale })
			end
		end
		local pts = {}
		for i = 0, 28 do
			for j = 0, 8 do
				table.insert(pts, (memo.CFrame * CFrame.new(FACE_POINT[face](memo.Size, -0.5 + i / 28, -0.5 + j / 8))).Position)
			end
		end
		local P = V3(ox, ROOT_Y, 0)
		local readers = { P }
		for k = 1, 6 do
			local base = bay:FindFirstChild("Bin_" .. k):FindFirstChild("Base")
			local flat = V3(base.Position.X, ROOT_Y, base.Position.Z)
			table.insert(readers, flat + (P - flat).Unit * 5)
		end
		for _, root in readers do
			for _, cm in READ_CAMS do
				local cam = camera(parts, root, flatDir(root, memo.Position), cm[1], cm[2])
				local covered = 0
				for _, pt in pts do
					local dir = pt - cam
					for _, t in tags do
						local nrm = (cam - t.c).Unit
						local denom = dir:Dot(nrm)
						if math.abs(denom) > 1e-9 then
							local k = (t.c - cam):Dot(nrm) / denom
							if k > 0 and k < 1 then
								local right = V3(0, 1, 0):Cross(nrm).Unit
								local up = nrm:Cross(right)
								local d = cam + dir * k - t.c
								if math.abs(d:Dot(right)) <= t.w / 2 and math.abs(d:Dot(up)) <= t.h / 2 then
									covered += 1
									break
								end
							end
						end
					end
				end
				local c = covered / #pts
				worst = math.max(worst, c)
				sum += c
				n += 1
			end
		end
	end
	print(string.format("  tray tags in front of the memo board: mean %.1f%%, worst %.1f%% of its face, over %d cameras", 100 * sum / n,
		100 * worst, n))
	truthy(n > 0, "CONTROL: the memo board was looked at from " .. n .. " cameras")
	truthy(worst <= 0.02, string.format("U5: no reader's camera sees more than 2%% of the memo board behind a tray tag (worst %.1f%%)", 100 * worst))
end

eq(#h:errors(), 0, "no thread died")
for _, e in h:errors() do print("scheduler error: " .. e) end
print(string.format("lost-found-depot view: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot view check failed", 0) end
