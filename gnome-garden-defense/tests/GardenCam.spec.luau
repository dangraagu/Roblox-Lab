-- GardenCam.spec: the garden view's camera and the tap that picks a pad (REVIEW-1, reach finding 1).
-- Run: luau tests/GardenCam.spec.luau
--
-- From the spawn, at Roblox's default camera, every pad was under 44 px on an 844x390 phone (the three glowing
-- ones a median 3.8 px tall), so the first tap of the game was a lottery. GardenCam is the pure half of the fix:
-- poses (a camera position, a point it looks at, a vertical field of view), the projection Roblox uses for them,
-- a fit that frames points inside a screen region, a zoom that makes one cell at least N px, and the pick that
-- turns a tap's ray into a pad (a gnome's whole column, else the cell under the finger, else the nearest pad
-- within one cell). The projection is checked here against an independent pinhole written in this file.

local GardenCam = require("../src/shared/GardenCam")
local Config = require("../src/shared/Config")
local PathGen = require("../src/shared/PathGen")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function v(x, y, z) return { x = x, y = y, z = z } end

-- an independent pinhole: camera at c looking at t, world up +Y, vertical fov (degrees), w x h px
local function pin(c, t, fov, w, h, p)
	local fx, fy, fz = t.x - c.x, t.y - c.y, t.z - c.z
	local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / fl, fy / fl, fz / fl
	-- right = forward x up(0,1,0) = (-fz, 0, fx)
	local rx, ry, rz = -fz, 0, fx
	local rl = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rl, rz / rl
	-- camera up = right x forward
	local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
	local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
	local zc = dx * fx + dy * fy + dz * fz
	local xc = dx * rx + dy * ry + dz * rz
	local yc = dx * ux + dy * uy + dz * uz
	local f = (h / 2) / math.tan(math.rad(fov) / 2)
	return w / 2 + xc / zc * f, h / 2 - yc / zc * f, zc
end

local VIEW = { w = 844, h = 390 }

--====================================================================== projection = Roblox's pinhole
do
	local pose = { pos = v(48, 60, 130), look = v(48, 0, 40), fov = 50 }
	local worst = 0
	local r = Rng.new(31)
	for _ = 1, 200 do
		local p = v(Rng.next(r) * 112, Rng.next(r) * 8, Rng.next(r) * 92)
		local ax, ay = GardenCam.project(pose, VIEW, p)
		local bx, by = pin(pose.pos, pose.look, pose.fov, VIEW.w, VIEW.h, p)
		worst = math.max(worst, math.abs(ax - bx), math.abs(ay - by))
		-- and the ray back through that pixel passes through the point
		local o, d = GardenCam.ray(pose, VIEW, ax, ay)
		local t = (p.x - o.x) * d.x + (p.y - o.y) * d.y + (p.z - o.z) * d.z
		local miss = math.sqrt((o.x + d.x * t - p.x) ^ 2 + (o.y + d.y * t - p.y) ^ 2 + (o.z + d.z * t - p.z) ^ 2)
		worst = math.max(worst, miss)
	end
	truthy(worst < 1e-6, "project matches an independent pinhole, and ray() inverts it (worst error " .. worst .. ")")
	local cx, cy = GardenCam.project(pose, VIEW, pose.look)
	truthy(math.abs(cx - 422) < 1e-9 and math.abs(cy - 195) < 1e-9, "the point a pose looks at is the viewport's centre")
	local o = GardenCam.orbit(v(10, 0, 20), 60, 0, 50, 45)
	truthy(math.abs(o.pos.z - (20 + 25)) < 1e-9 and math.abs(o.pos.y - 50 * math.sin(math.rad(60))) < 1e-9,
		"orbit: yaw 0 looks north (-Z) from the south, pitched down 60 degrees, 50 studs out")
end

--====================================================================== fit: everything inside the region, as big as it goes
do
	local pts = {}
	for _, x in { 0, 112 } do
		for _, z in { 0, 92 } do table.insert(pts, v(x, 0.6, z)) end
	end
	local region = { x0 = 8, y0 = 121, x1 = 836, y1 = 382 }
	local pose = GardenCam.fit(pts, region, VIEW, 58, 0, 45)
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, p in pts do
		local x, y = pin(pose.pos, pose.look, pose.fov, VIEW.w, VIEW.h, p)
		minx, miny, maxx, maxy = math.min(minx, x), math.min(miny, y), math.max(maxx, x), math.max(maxy, y)
	end
	truthy(minx >= region.x0 - 0.5 and maxx <= region.x1 + 0.5 and miny >= region.y0 - 0.5 and maxy <= region.y1 + 0.5,
		string.format("fit puts every point inside the region (x %.1f..%.1f, y %.1f..%.1f)", minx, maxx, miny, maxy))
	local snugX = (maxx - minx) >= (region.x1 - region.x0) * 0.98
	local snugY = (maxy - miny) >= (region.y1 - region.y0) * 0.98
	truthy(snugX or snugY, "and as big as it goes (it touches the region on one axis)")
	truthy(math.abs((minx + maxx) / 2 - (region.x0 + region.x1) / 2) < 2 or math.abs((miny + maxy) / 2 - (region.y0 + region.y1) / 2) < 2,
		"centred in the region on the loose axis")
end

--====================================================================== zoom: one cell at least N px, as far out as that allows
do
	local region = { x0 = 0, y0 = 121, x1 = 844, y1 = 254 }
	local pose = GardenCam.zoomOn(v(52, 0.6, 20), 8, 48, region, VIEW, 58, 0, 45)
	local x, y = pin(pose.pos, pose.look, pose.fov, VIEW.w, VIEW.h, v(52, 0.6, 20))
	truthy(math.abs(x - 422) < 1 and math.abs(y - 187.5) < 1, string.format("the zoomed point sits at the region's centre (%.1f, %.1f)", x, y))
	local function cellPx(p, cx, cz)
		local xs, ys = {}, {}
		for _, dx in { -4, 4 } do
			for _, dz in { -4, 4 } do
				local px, py = pin(p.pos, p.look, p.fov, VIEW.w, VIEW.h, v(cx + dx, 0.6, cz + dz))
				table.insert(xs, px)
				table.insert(ys, py)
			end
		end
		return math.max(table.unpack(xs)) - math.min(table.unpack(xs)), math.max(table.unpack(ys)) - math.min(table.unpack(ys))
	end
	local w, h = cellPx(pose, 52, 20)
	truthy(w >= 48 - 0.5 and h >= 48 - 0.5, string.format("the cell there is at least 48 px (%.1f x %.1f)", w, h))
	truthy(math.min(w, h) < 48 * 1.03, "and no closer than that needs (" .. string.format("%.1f", math.min(w, h)) .. " px)")
	local w2, h2 = GardenCam.cellPx(pose, VIEW, 52, 20, 8, 0.6)
	truthy(math.abs(w2 - w) < 1e-6 and math.abs(h2 - h) < 1e-6, "cellPx measures the same")
end

--====================================================================== pick: a tap's ray -> a pad
do
	local cells = {}
	for x = 0, 11 do table.insert(cells, { x = x, y = 4 }) end -- a straight lane along row 4 (z 32..40)
	local path = PathGen.pathFromCells(Config, cells)
	local pads = PathGen.pads(Config, path) -- rows 3 and 5 of every column
	local function padAt(x, y)
		for i, p in pads do
			if p.x == x and p.y == y then return i end
		end
		error("no pad")
	end
	local T, TOP = Config.Tile, 0.6
	local function down(x, z) return GardenCam.pickRay(v(x, 50, z), v(0, -1, 0), pads, T, TOP, {}) end -- a tap from above
	eq(down(44, 28), padAt(5, 3), "a tap on a pad picks it")
	eq(down(41.5, 31.5), padAt(5, 3), "anywhere in its 8-stud cell, not only on the 7-stud pad")
	eq(down(44, 33), padAt(5, 3), "a tap on the path just below a pad snaps to it")
	eq(down(44, 38), padAt(5, 5), "and just above the next row, to that one")
	eq(down(44, 4), nil, "a tap far from every pad picks nothing")
	eq(GardenCam.pickRay(v(44, 50, 0), v(0, 1, 0), pads, T, TOP, {}), nil, "a ray into the sky picks nothing")
	-- a gnome on pad (5,5) stands 7 studs tall: a slanted tap through its body picks it, although the ground
	-- point behind it lies in the cell of pad (5,3)
	local cols = { [padAt(5, 5)] = 7 }
	local o = v(44, 9, 56)
	local d = v(0, -6.5, -20)
	local dl = math.sqrt(d.y * d.y + d.z * d.z)
	d = v(0, d.y / dl, d.z / dl)
	eq(GardenCam.pickRay(o, d, pads, T, TOP, {}), padAt(5, 3), "(without the gnome that ray lands on pad 5,3)")
	eq(GardenCam.pickRay(o, d, pads, T, TOP, cols, 1.5), padAt(5, 5), "a tap through a gnome's body picks the gnome's pad")
	-- the column is the gnome's width, not its cell's: a tap aimed at the centre of the pad BEHIND a gnome picks
	-- that pad from a ray pitched 50 degrees down (the overview's far rows), where a whole-cell column hid it
	local vcells = {}
	for y = 0, 8 do table.insert(vcells, { x = 4, y = y }) end -- a lane down column 4: pads stack in columns 3 and 5
	local vpads = PathGen.pads(Config, PathGen.pathFromCells(Config, vcells))
	local function vpad(x, y)
		for i, pd in vpads do
			if pd.x == x and pd.y == y then return i end
		end
		error("no pad")
	end
	local front = { [vpad(5, 4)] = 7 } -- a gnome on (5,4), between the camera (south) and pad (5,3)
	local slope = math.tan(math.rad(50))
	local o2 = v(44, TOP + 40, 28 + 40 / slope)
	local d2 = v(0, -40, -40 / slope)
	local l2 = math.sqrt(d2.y * d2.y + d2.z * d2.z)
	d2 = v(0, d2.y / l2, d2.z / l2)
	eq(GardenCam.pickRay(o2, d2, vpads, T, TOP, front, Config.Camera.GnomeHalfWidth), vpad(5, 3),
		"a tap on the centre of the pad behind a gnome picks that pad")
	eq(GardenCam.pickRay(o2, d2, vpads, T, TOP, front, T / 2), vpad(5, 4), "(control: a whole-cell column would have hidden it)")
end

--====================================================================== the garden on a phone and a desktop (measured, reported)
do
	local C = Config.Camera
	truthy(type(C) == "table" and type(C.Pitch) == "number" and type(C.Fov) == "number" and type(C.MinTapPx) == "number",
		"Config.Camera holds the garden view's numbers")
	local Tl = Config.Tile
	local bedPts = {}
	for _, x in { 0, Config.GridW * Tl + Config.World.PatchLength } do
		for _, z in { 0, Config.GridH * Tl + Config.World.DeckGap + Config.World.DeckDepth } do
			table.insert(bedPts, v(x, 0.6, z))
		end
	end
	local function minCell(pose, view, fromRow)
		local m = math.huge
		for row = fromRow or 0, Config.GridH - 1 do
			for col = 0, Config.GridW - 1 do
				local w, h = GardenCam.cellPx(pose, view, (col + 0.5) * Tl, (row + 0.5) * Tl, Tl, 0.6)
				m = math.min(m, w, h)
			end
		end
		return m
	end
	local phone = { w = 844, h = 390 }
	local over = GardenCam.fit(bedPts, { x0 = 8, y0 = 121, x1 = 836, y1 = 382 }, phone, C.Pitch, 0, C.Fov)
	local small = minCell(over, phone)
	print(string.format("  phone 844x390, the whole garden in view: the smallest cell is %.1f px", small))
	truthy(small < C.MinTapPx, "(on a phone the overview's cells are below a tap target: that is why the zoom exists)")
	local worstZoom = math.huge
	for row = 0, Config.GridH - 1 do
		for col = 0, Config.GridW - 1 do
			local cx, cz = (col + 0.5) * Tl, (row + 0.5) * Tl
			local z = GardenCam.zoomOn(v(cx, 0.6, cz), Tl, C.MinTapPx, { x0 = 0, y0 = 121, x1 = 844, y1 = 254 }, phone, C.Pitch, 0, C.Fov)
			local w, h = GardenCam.cellPx(z, phone, cx, cz, Tl, 0.6)
			worstZoom = math.min(worstZoom, w, h)
		end
	end
	print(string.format("  phone, zoomed on any of the 108 cells: that cell is at least %.1f px", worstZoom))
	truthy(worstZoom >= 44, "zoomed on any cell of the bed, that cell is a tap target of 44 px or more")
	-- REVIEW-2: in the zoom a tap picks (the whole-garden view's first tap only zooms), and a finger that was one
	-- cell off lands next to the zoomed cell: its eight neighbours must be tap targets too, once the view settles
	local worstNb = math.huge
	for row = 0, Config.GridH - 1 do
		for col = 0, Config.GridW - 1 do
			local cx, cz = (col + 0.5) * Tl, (row + 0.5) * Tl
			local z = GardenCam.zoomOn(v(cx, 0.6, cz), Tl, C.MinTapPx, { x0 = 0, y0 = 121, x1 = 844, y1 = 254 }, phone, C.Pitch, 0, C.Fov)
			for dr = -1, 1 do
				for dc = -1, 1 do
					if (dr ~= 0 or dc ~= 0) and row + dr >= 0 and row + dr < Config.GridH and col + dc >= 0 and col + dc < Config.GridW then
						local w, h = GardenCam.cellPx(z, phone, cx + dc * Tl, cz + dr * Tl, Tl, 0.6)
						worstNb = math.min(worstNb, w, h)
					end
				end
			end
		end
	end
	print(string.format("  phone, zoomed on any cell: its neighbours are at least %.1f px", worstNb))
	truthy(worstNb >= 44, "and its eight neighbours are tap targets of 44 px or more too")
	local desk = { w = 1280, h = 720 }
	local deskOver = GardenCam.fit(bedPts, { x0 = 12, y0 = 160, x1 = 1268, y1 = 708 }, desk, C.Pitch, 0, C.Fov)
	local deskSmall = minCell(deskOver, desk)
	print(string.format("  desktop 1280x720, the whole garden in view: the smallest cell is %.1f px", deskSmall))
	-- a mouse is not a finger: the zoom is for touch screens only; a mouse target needs 24 px (WCAG 2.2's minimum)
	truthy(deskSmall >= 24, "on a 1280x720 desktop every cell of the overview is a mouse target of 24 px or more")
end

--====================================================================== fitClear: no pad under Roblox's touch controls (REVIEW-2)
-- The whole-garden view ran to the screen's bottom edge, into the band the HUD leaves to Roblox's thumbstick
-- (bottom band, left 35%) and jump button (bottom band, right 25%): on an 844x390 phone 8-11 pads of a bed sat
-- under the thumbstick, where a first tap moves the gardener instead. fitClear frames the same points, moved
-- sideways (and, only when that is not enough, smaller) until no pad's 8-stud cell overlaps either zone. The
-- garden's top rows, the deck and the board may still use the band's middle and corners: they take no tap.
-- The screens below are the HUD's own numbers (check_gnomegardendefense_reach measures them in the real client):
-- WorldTop, WorldBand (viewport px), and the hudcheck's zones.
do
	local C, W, Tl = Config.Camera, Config.World, Config.Tile
	local BED_W, DECK_Z1 = Config.GridW * Tl, Config.GridH * Tl + W.DeckGap + W.DeckDepth
	local points = {
		v(-2, 0.6, -2), v(BED_W + W.PatchLength, 0.6, -2), v(-2, W.DeckY, DECK_Z1), v(BED_W + W.PatchLength, W.DeckY, DECK_Z1),
		v(W.BoardX - 7.3, W.DeckY + 10.2, DECK_Z1 - W.BoardBack), v(W.BoardX + 7.3, W.DeckY + 10.2, DECK_Z1 - W.BoardBack),
	}
	local screens = {
		{ w = 844, h = 390, top = 126, band = 246.8 },
		{ w = 812, h = 375, top = 126, band = 236.8 },
		{ w = 926, h = 428, top = 126, band = 271.8 },
		{ w = 568, h = 320, top = 126, band = 200.8 },
		{ w = 640, h = 300, top = 126, band = 187.8 },
	}
	local function cellsOf(pads)
		local out = {}
		for _, pd in pads do
			table.insert(out, { v(pd.cx - Tl / 2, 0.6, pd.cz - Tl / 2), v(pd.cx + Tl / 2, 0.6, pd.cz - Tl / 2),
				v(pd.cx - Tl / 2, 0.6, pd.cz + Tl / 2), v(pd.cx + Tl / 2, 0.6, pd.cz + Tl / 2) })
		end
		return out
	end
	local function boxOf(pose, view, quad)
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, p in quad do
			local x, y = pin(pose.pos, pose.look, pose.fov, view.w, view.h, p)
			x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
		end
		return x0, y0, x1, y1
	end
	local function smallest(pose, view, pads)
		local m = math.huge
		for _, pd in pads do
			local w, h = GardenCam.cellPx(pose, view, pd.cx, pd.cz, Tl, 0.6)
			m = math.min(m, w, h)
		end
		return m
	end
	-- no zones: exactly the plain fit
	local s1 = screens[1]
	local region1 = { x0 = C.Margin, y0 = s1.top + C.Margin, x1 = s1.w - C.Margin, y1 = s1.h - C.Margin }
	local plain = GardenCam.fit(points, region1, s1, C.Pitch, 0, C.Fov)
	local same = GardenCam.fitClear(points, region1, s1, C.Pitch, 0, C.Fov, {}, {})
	truthy(same ~= nil and math.abs(same.pos.x - plain.pos.x) + math.abs(same.pos.y - plain.pos.y) + math.abs(same.pos.z - plain.pos.z) < 1e-9,
		"fitClear with no zones is the plain fit")
	local beds, before, under, outside, failedFits = 0, 0, 0, 0, 0
	local shrink = {}
	for si, sc in screens do
		local region = { x0 = C.Margin, y0 = sc.top + C.Margin, x1 = sc.w - C.Margin, y1 = sc.h - C.Margin }
		-- the thumbstick's frame (the DynamicThumbstick's lower-left; it holds the HUD's own thumbstick corner on
		-- every phone, the band being at most 35% of the height) and the jump button's corner of the band
		local zones = {
			{ x0 = 0, y0 = sc.h * (1 - Config.Hud.StickH), x1 = sc.w * Config.Hud.StickW, y1 = sc.h },
			{ x0 = sc.w * (1 - Config.Hud.JumpShare), y0 = sc.band, x1 = sc.w, y1 = sc.h },
		}
		truthy(zones[1].y0 <= sc.band and zones[1].x1 >= sc.w * Config.Hud.ThumbShare, "(the frame holds the HUD's thumbstick corner on " .. sc.w .. "x" .. sc.h .. ")")
		local worst = math.huge
		for seed = 1, 40 do
			local path = PathGen.genPath(Config, Rng.new(7000 + seed))
			local pads = PathGen.pads(Config, path)
			local cells = cellsOf(pads)
			local base = GardenCam.fit(points, region, sc, C.Pitch, 0, C.Fov)
			local pose, ok = GardenCam.fitClear(points, region, sc, C.Pitch, 0, C.Fov, cells, zones)
			beds += 1
			if not ok then failedFits += 1 end
			for _, q in cells do
				local x0, y0, x1, y1 = boxOf(base, sc, q)
				for _, z in zones do
					if x1 > z.x0 and x0 < z.x1 and y1 > z.y0 and y0 < z.y1 then before += 1 end
				end
				x0, y0, x1, y1 = boxOf(pose, sc, q)
				for _, z in zones do
					if x1 > z.x0 and x0 < z.x1 and y1 > z.y0 and y0 < z.y1 then under += 1 end
				end
			end
			for _, p in points do
				local x, y = pin(pose.pos, pose.look, pose.fov, sc.w, sc.h, p)
				if x < region.x0 - 0.5 or x > region.x1 + 0.5 or y < region.y0 - 0.5 or y > region.y1 + 0.5 then outside += 1 end
			end
			worst = math.min(worst, smallest(pose, sc, pads) / smallest(base, sc, pads))
		end
		shrink[si] = string.format("%dx%d %.0f%%", sc.w, sc.h, worst * 100)
	end
	print(string.format("  fitClear, %d beds x %d phones: pad cells under a touch control %d with the plain fit, %d now; worst cell size kept: %s",
		40, #screens, before, under, table.concat(shrink, ", ")))
	truthy(before > 0, "(the plain fit puts pad cells under the thumbstick or jump button on these phones)")
	eq(failedFits, 0, "fitClear finds a clear framing for every bed on every phone")
	eq(under, 0, "and with it no pad's cell overlaps the thumbstick's or the jump button's zone")
	eq(outside, 0, "while the bed, the patch, the deck and the board all stay inside the region")
end

print(("GardenCam: %d passed, %d failed"):format(passed, failed))
