--!strict
-- RoomArt.luau: what a room is built from, as plain data (DESIGN.md §3.1, §7, §8, §18). Pure: sizes and
-- offsets in studs, colours as {r, g, b}, no Roblox. Room.client turns these into Parts; tests count them
-- (the budget) and Bands.validate checks every colour (nothing red but the ring, nothing gold but a find).
--
-- Room-local coordinates as in Dressing: the door mat's centre is (0, 0, 0), the room is x in [-W/2, W/2],
-- z in [0, D], y up from the floor. A prop's parts are relative to its base centre (y = 0 is its bottom).

local RoomArt = {}

--============================================================================ the 8 prop silhouettes
-- role "body" takes the prop's clue colour; "trim" a neutral dark wood. Silhouettes differ in OUTLINE: a cube,
-- a woven bowl with a handle, a lidded cylinder, a ball with a narrow neck, a tapered pot, a flat pillow, a
-- tied sack, a round-lidded trunk. Part counts per kind: 1/3/2/2/2/1/2/2 (the design model's).
RoomArt.Trim = { 92, 66, 46 }
RoomArt.Kinds = {
	box = { { shape = "Block", size = { 1.8, 1.8, 1.8 }, offset = { 0, 0.9, 0 }, role = "body" } },
	basket = {
		{ shape = "Cylinder", size = { 1.0, 2.2, 2.2 }, offset = { 0, 0.5, 0 }, role = "body", upright = true },
		{ shape = "Block", size = { 0.25, 1.4, 0.25 }, offset = { -0.9, 1.6, 0 }, role = "body" },
		{ shape = "Block", size = { 0.25, 1.4, 0.25 }, offset = { 0.9, 1.6, 0 }, role = "body" },
	},
	jar = {
		{ shape = "Cylinder", size = { 1.8, 1.3, 1.3 }, offset = { 0, 0.9, 0 }, role = "body", upright = true },
		{ shape = "Cylinder", size = { 0.3, 1.45, 1.45 }, offset = { 0, 1.95, 0 }, role = "trim", upright = true },
	},
	vase = {
		{ shape = "Ball", size = { 1.7, 1.7, 1.7 }, offset = { 0, 0.85, 0 }, role = "body" },
		{ shape = "Cylinder", size = { 1.1, 0.6, 0.6 }, offset = { 0, 2.1, 0 }, role = "body", upright = true },
	},
	pot = {
		{ shape = "Cylinder", size = { 0.8, 1.2, 1.2 }, offset = { 0, 0.4, 0 }, role = "body", upright = true },
		{ shape = "Cylinder", size = { 0.9, 2.0, 2.0 }, offset = { 0, 1.25, 0 }, role = "body", upright = true },
	},
	cushion = { { shape = "Block", size = { 2.0, 0.7, 2.0 }, offset = { 0, 0.35, 0 }, role = "body" } },
	bag = {
		{ shape = "Ball", size = { 1.8, 1.6, 1.8 }, offset = { 0, 0.8, 0 }, role = "body" },
		{ shape = "Ball", size = { 0.6, 0.6, 0.6 }, offset = { 0, 1.75, 0 }, role = "trim" },
	},
	chest = {
		{ shape = "Block", size = { 2.2, 1.2, 1.4 }, offset = { 0, 0.6, 0 }, role = "body" },
		{ shape = "Cylinder", size = { 2.2, 1.4, 1.4 }, offset = { 0, 1.2, 0 }, role = "body" },
	},
}

-- The pick box of a prop (its base centre + this box), the HUD's tap target in 3D. Generous on purpose.
function RoomArt.pickBox(kind: string): (number, number, number)
	local hx, hy, hz = 0, 0, 0
	for _, p in RoomArt.Kinds[kind] or {} do
		local sx, sy, sz = p.size[1], p.size[2], p.size[3]
		if p.upright then sx, sy = sy, sx end
		hx = math.max(hx, math.abs(p.offset[1]) + sx / 2)
		hy = math.max(hy, p.offset[2] + sy / 2)
		hz = math.max(hz, math.abs(p.offset[3]) + sz / 2)
	end
	return hx + 0.2, hy + 0.2, hz + 0.2
end

--============================================================================ furniture
RoomArt.TableParts = 2 -- a top and one leg block
RoomArt.ShelfParts = 3 -- a plank and two brackets

--============================================================================ items (shown once found)
-- An item exists in the room only after the server said "found", so a gold-ish coin is still gold for a find.
RoomArt.Items = {
	key = { shape = "Block", size = { 0.25, 0.25, 0.9 }, color = { 205, 175, 90 } },
	duck = { shape = "Ball", size = { 0.8, 0.7, 0.8 }, color = { 250, 225, 80 } },
	teacup = { shape = "Cylinder", size = { 0.5, 0.7, 0.7 }, color = { 240, 240, 250 } },
	coin = { shape = "Cylinder", size = { 0.12, 0.7, 0.7 }, color = { 232, 196, 70 } },
	gem = { shape = "Ball", size = { 0.6, 0.6, 0.6 }, color = { 120, 220, 255 } },
	toycar = { shape = "Block", size = { 0.9, 0.4, 0.5 }, color = { 80, 140, 240 } },
	button = { shape = "Cylinder", size = { 0.12, 0.5, 0.5 }, color = { 200, 120, 220 } },
	marble = { shape = "Ball", size = { 0.45, 0.45, 0.45 }, color = { 140, 230, 200 } },
	whistle = { shape = "Block", size = { 0.7, 0.25, 0.25 }, color = { 190, 200, 210 } },
	thimble = { shape = "Cylinder", size = { 0.4, 0.35, 0.35 }, color = { 200, 205, 215 } },
	watch = { shape = "Cylinder", size = { 0.15, 0.7, 0.7 }, color = { 215, 190, 120 } },
	bell = { shape = "Ball", size = { 0.6, 0.6, 0.6 }, color = { 225, 200, 110 } },
	wool = { shape = "Ball", size = { 0.8, 0.8, 0.8 }, color = { 200, 150, 230 } },
	teddy = { shape = "Ball", size = { 0.9, 1.0, 0.8 }, color = { 170, 120, 80 } },
	cookie = { shape = "Cylinder", size = { 0.15, 0.7, 0.7 }, color = { 200, 150, 90 } },
	quill = { shape = "Block", size = { 0.12, 1.0, 0.25 }, color = { 245, 245, 240 } },
	glasses = { shape = "Block", size = { 0.9, 0.3, 0.12 }, color = { 60, 60, 70 } },
	bookmark = { shape = "Block", size = { 0.3, 0.9, 0.05 }, color = { 120, 80, 200 } },
	seeds = { shape = "Block", size = { 0.6, 0.8, 0.1 }, color = { 150, 200, 120 } },
	shell = { shape = "Ball", size = { 0.6, 0.6, 0.6 }, color = { 230, 200, 170 } },
	gnome = { shape = "Cylinder", size = { 0.9, 0.5, 0.5 }, color = { 90, 130, 230 } },
	compass = { shape = "Cylinder", size = { 0.2, 0.7, 0.7 }, color = { 190, 160, 100 } },
	spyglass = { shape = "Cylinder", size = { 1.2, 0.3, 0.3 }, color = { 180, 150, 90 } },
	bottle = { shape = "Cylinder", size = { 1.0, 0.4, 0.4 }, color = { 140, 210, 170 } },
	starmap = { shape = "Block", size = { 0.9, 0.05, 0.7 }, color = { 60, 70, 140 } },
	moonrock = { shape = "Ball", size = { 0.6, 0.5, 0.6 }, color = { 180, 180, 190 } },
	planet = { shape = "Ball", size = { 0.7, 0.7, 0.7 }, color = { 120, 170, 250 } },
}

--============================================================================ decor per band (never searchable)
-- Every piece sits outside the props' height bands: high on a wall (bottom at y >= DECOR_HIGH, above the
-- shelf props), flat on the floor (a rug, thinner than DECOR_FLAT), or in a floor corner (within
-- DECOR_CORNER of two walls, where no prop is ever placed). None uses a prop kind's silhouette or a reserved
-- colour (Bands.validate). Sizes follow the room: pieces are placed from W and D, never near a candidate.
RoomArt.DECOR_HIGH = 10.5
RoomArt.DECOR_FLAT = 0.2
RoomArt.DECOR_CORNER = 3.6 -- = Config.Room.CornerClear: no prop or table ever enters a corner square

-- orient "up": a cylinder whose axis is vertical (a rug, a barrel); otherwise a cylinder's axis is x (a disc on
-- an east or west wall).
local function piece(id: string, size: { number }, pos: { number }, color: { number }, material: string?, shape: string?, transparency: number?, orient: string?): any
	return { id = id, size = size, pos = pos, color = color, material = material or "SmoothPlastic", shape = shape or "Block", transparency = transparency or 0, orient = orient }
end

-- The axis-aligned box a decor piece occupies: (sx, sy, sz).
function RoomArt.extent(p: any): (number, number, number)
	if p.shape == "Cylinder" and p.orient == "up" then return p.size[2], p.size[1], p.size[3] end
	return p.size[1], p.size[2], p.size[3]
end

local DECOR = {}

DECOR.curtains = function(W: number, D: number)
	return {
		piece("window", { 6, 3.5, 0.2 }, { 0, 12.5, D - 0.15 }, { 196, 226, 246 }, "Glass", "Block", 0.3),
		piece("curtainL", { 1.6, 4.2, 0.3 }, { -3.6, 12.6, D - 0.3 }, { 244, 206, 214 }, "Fabric"),
		piece("curtainR", { 1.6, 4.2, 0.3 }, { 3.6, 12.6, D - 0.3 }, { 244, 206, 214 }, "Fabric"),
		piece("sill", { 6.6, 0.3, 0.8 }, { 0, 10.7, D - 0.4 }, { 220, 200, 170 }, "Wood"),
	}
end
DECOR.rug = function(W: number, D: number)
	return { piece("rug", { 0.12, 7, 9 }, { 0, 0.06, D * 0.45 }, { 172, 120, 156 }, "Fabric", "Cylinder", 0, "up") }
end
DECOR.herbs = function(W: number, D: number)
	return {
		piece("herb1", { 0.7, 1.0, 0.7 }, { -2.2, 11.2, D - 0.45 }, { 112, 134, 72 }, "Grass"),
		piece("herb2", { 0.7, 1.2, 0.7 }, { 2.2, 11.3, D - 0.45 }, { 104, 128, 66 }, "Grass"),
	}
end
DECOR.clock = function(W: number, D: number)
	return {
		piece("clockCase", { 0.5, 2.6, 1.8 }, { W / 2 - 0.3, 12.8, D * 0.5 }, { 120, 84, 54 }, "Wood"),
		piece("clockFace", { 0.1, 1.2, 1.2 }, { W / 2 - 0.6, 13.2, D * 0.5 }, { 236, 228, 210 }, "SmoothPlastic", "Cylinder"),
	}
end
DECOR.bookcase = function(W: number, D: number)
	local out = {}
	local cols = { { 112, 44, 56 }, { 44, 84, 56 }, { 46, 56, 96 } }
	for i = 1, 3 do
		table.insert(out, piece("spines" .. i, { W * 0.28, 1.4, 0.6 }, { -W / 2 + W * 0.18 + (i - 1) * W * 0.32, 11.4 + (i % 2) * 1.8, D - 0.35 }, cols[i], "Wood"))
	end
	table.insert(out, piece("spinesE", { 0.6, 1.4, D * 0.5 }, { W / 2 - 0.35, 12.2, D * 0.5 }, { 96, 52, 40 }, "Wood"))
	table.insert(out, piece("spinesW", { 0.6, 1.4, D * 0.5 }, { -W / 2 + 0.35, 12.2, D * 0.5 }, { 52, 70, 92 }, "Wood"))
	return out
end
DECOR.ladder = function(W: number, D: number)
	return {
		piece("railL", { 0.3, 5, 0.3 }, { -W / 2 + 1.0, 13.2, D - 1.4 }, { 120, 86, 56 }, "Wood"),
		piece("railR", { 0.3, 5, 0.3 }, { -W / 2 + 2.6, 13.2, D - 1.4 }, { 120, 86, 56 }, "Wood"),
		piece("rung", { 1.9, 0.2, 0.2 }, { -W / 2 + 1.8, 12.8, D - 1.4 }, { 132, 96, 62 }, "Wood"),
	}
end
DECOR.globe = function(W: number, D: number)
	return {
		piece("globeStand", { 1.0, 2.4, 1.0 }, { W / 2 - 1.0, 1.2, D - 1.0 }, { 86, 62, 42 }, "Wood"),
		piece("globe", { 1.6, 1.6, 1.6 }, { W / 2 - 1.0, 3.0, D - 1.0 }, { 96, 140, 150 }, "SmoothPlastic", "Ball"),
	}
end
DECOR.books = function(W: number, D: number)
	return {
		piece("stack1", { 1.4, 0.5, 1.0 }, { -W / 2 + 1.0, 0.25, 1.0 }, { 70, 90, 120 }, "SmoothPlastic"),
		piece("stack2", { 1.2, 0.5, 0.9 }, { -W / 2 + 1.0, 0.75, 1.0 }, { 120, 70, 90 }, "SmoothPlastic"),
	}
end
DECOR.ferns = function(W: number, D: number)
	return {
		piece("fern1", { 1.6, 2.2, 1.6 }, { -W / 2 + 1.0, 1.1, D - 1.0 }, { 104, 150, 70 }, "Grass", "Ball"),
		piece("fern2", { 1.6, 2.0, 1.6 }, { W / 2 - 1.0, 1.0, D - 1.0 }, { 96, 140, 64 }, "Grass", "Ball"),
		piece("fern3", { 1.6, 1.8, 1.6 }, { -W / 2 + 1.0, 0.9, 1.0 }, { 110, 156, 76 }, "Grass", "Ball"),
	}
end
DECOR.vines = function(W: number, D: number)
	local out = {}
	for i = 1, 4 do
		table.insert(out, piece("vine" .. i, { 0.3, 4.5, 0.3 }, { -W / 2 + W * i / 5, 13.6, D - 0.3 }, { 84, 128, 70 }, "Grass"))
	end
	table.insert(out, piece("vineE", { 0.3, 4.5, 0.3 }, { W / 2 - 0.3, 13.6, D * 0.4 }, { 90, 134, 74 }, "Grass"))
	return out
end
DECOR.cans = function(W: number, D: number)
	return {
		piece("can", { 1.0, 1.2, 1.0 }, { W / 2 - 1.0, 0.6, 1.0 }, { 150, 160, 170 }, "Metal"),
		piece("spout", { 0.2, 0.2, 1.0 }, { W / 2 - 1.0, 1.0, 1.6 }, { 150, 160, 170 }, "Metal"),
	}
end
DECOR.pots = function(W: number, D: number)
	-- glass roof frames (not flowerpots: a pot is a searchable kind's silhouette)
	local out = {}
	for i = 1, 3 do
		table.insert(out, piece("frame" .. i, { W, 0.3, 0.3 }, { 0, 15.5, D * i / 4 }, { 220, 230, 220 }, "Metal"))
	end
	return out
end
DECOR.ropes = function(W: number, D: number)
	return {
		piece("rope1", { 0.4, 2.4, 2.4 }, { -W / 2 + 0.3, 12.5, D * 0.3 }, { 190, 170, 120 }, "Fabric", "Cylinder"),
		piece("rope2", { 0.4, 2.0, 2.0 }, { W / 2 - 0.3, 12.0, D * 0.7 }, { 186, 166, 116 }, "Fabric", "Cylinder"),
		piece("ropeLine", { W * 0.8, 0.2, 0.2 }, { 0, 15.2, D * 0.5 }, { 180, 160, 110 }, "Fabric"),
	}
end
DECOR.barrels = function(W: number, D: number)
	return {
		piece("barrel1", { 3.4, 2.6, 2.6 }, { W / 2 - 1.4, 1.7, D - 1.4 }, { 96, 66, 44 }, "Wood", "Cylinder", 0, "up"),
		piece("hoop1", { 0.3, 2.75, 2.75 }, { W / 2 - 1.4, 2.6, D - 1.4 }, { 70, 72, 78 }, "Metal", "Cylinder", 0, "up"),
		piece("barrel2", { 3.4, 2.6, 2.6 }, { -W / 2 + 1.4, 1.7, D - 1.4 }, { 92, 62, 40 }, "Wood", "Cylinder", 0, "up"),
	}
end
DECOR.hammock = function(W: number, D: number)
	return {
		piece("hammock", { W * 0.35, 0.4, 2.2 }, { -W / 2 + W * 0.2, 11.2, D - 2.0 }, { 200, 186, 150 }, "Fabric"),
		piece("hammockRope", { W * 0.4, 0.15, 0.15 }, { -W / 2 + W * 0.2, 11.8, D - 2.0 }, { 180, 160, 110 }, "Fabric"),
	}
end
-- A porthole is a shallow window box on the room's side of the wall (REVIEW-1 round 2 D2: a room is a closed box, so
-- anything beyond its wall is never seen): at the back the view out (`port..`, the night sea, where the lightning
-- flashes), in front of it see-through glass (`glass..`), a brass rim around. The fish swim and the rain runs in the
-- 0.3-stud gap between the view and the glass (RoomArt.critterPos "porthole", RoomArt.weatherSpots).
RoomArt.PORT_Y = 12.4
RoomArt.PORT_R = 1.2
RoomArt.PORT_Z = { 0.3, 0.7 }
RoomArt.PORT_VIEW = 0.1 -- the view disc's centre, this far in from the wall (0.2 thick: its face is 0.2 in)
RoomArt.PORT_GAP = 0.33 -- the fish and the rain, this far in
RoomArt.PORT_GLASS = 0.5 -- the glass, this far in (0.1 thick)
DECOR.portholes = function(W: number, D: number)
	local out = {}
	local y, d = RoomArt.PORT_Y, 2 * RoomArt.PORT_R
	for i, zf in RoomArt.PORT_Z do
		for _, side in { { "E", 1 }, { "W", -1 } } do
			local s = side[2]
			table.insert(out, piece("port" .. side[1] .. i, { 0.2, d, d }, { s * (W / 2 - RoomArt.PORT_VIEW), y, D * zf }, { 28, 40, 72 }, "SmoothPlastic", "Cylinder"))
			table.insert(out, piece("glass" .. side[1] .. i, { 0.1, d, d }, { s * (W / 2 - RoomArt.PORT_GLASS), y, D * zf }, { 176, 204, 232 }, "Glass", "Cylinder", 0.6))
			table.insert(out, piece("rim" .. side[1] .. i, { 0.15, d + 0.4, d + 0.4 }, { s * (W / 2 - 0.1), y, D * zf }, { 150, 122, 70 }, "Metal", "Cylinder"))
		end
	end
	return out
end
DECOR.telescope = function(W: number, D: number)
	return {
		piece("scopeStand", { 1.2, 3.0, 1.2 }, { W / 2 - 1.0, 1.5, D - 1.0 }, { 60, 60, 80 }, "Metal"),
		piece("scope", { 1.0, 1.0, 6.0 }, { W / 2 - 2.5, 13.0, D - 3.0 }, { 150, 150, 190 }, "Metal", "Cylinder"),
	}
end
DECOR.charts = function(W: number, D: number)
	return {
		piece("chartN", { W * 0.4, 3.2, 0.2 }, { -W * 0.2, 12.8, D - 0.15 }, { 34, 38, 82 }, "SmoothPlastic"),
		piece("chartE", { 0.2, 3.2, D * 0.35 }, { W / 2 - 0.15, 12.8, D * 0.35 }, { 38, 34, 86 }, "SmoothPlastic"),
		piece("chartW", { 0.2, 3.2, D * 0.35 }, { -W / 2 + 0.15, 12.8, D * 0.6 }, { 36, 36, 84 }, "SmoothPlastic"),
	}
end
DECOR.orrery = function(W: number, D: number)
	return {
		piece("sun", { 1.4, 1.4, 1.4 }, { 0, 14.2, D * 0.5 }, { 250, 236, 200 }, "Neon", "Ball"),
		piece("planetA", { 0.7, 0.7, 0.7 }, { 2.6, 13.8, D * 0.5 }, { 120, 150, 230 }, "SmoothPlastic", "Ball"),
		piece("planetB", { 0.5, 0.5, 0.5 }, { -1.8, 13.6, D * 0.5 + 2 }, { 170, 220, 210 }, "SmoothPlastic", "Ball"),
		piece("arm", { 5.4, 0.12, 0.12 }, { 0.4, 14.0, D * 0.5 }, { 180, 180, 200 }, "Metal"),
	}
end
DECOR.dome = function(W: number, D: number)
	return {
		piece("domeRing", { 0.6, W * 0.7, W * 0.7 }, { 0, 15.6, D * 0.5 }, { 74, 66, 120 }, "Metal", "Cylinder", 0, "up"),
		-- REVIEW-1 round 2 D3: the slit is a shutter hanging UNDER the opaque disc (inside it, the brag's "the dome opens"
		-- could never be seen); behind it a strip of night sky glows, shown only when BOOK ONE SOLVED opens the slit
		piece("domeSky", { 2.0, 0.04, D * 0.6 - 0.4 }, { 0, 15.27, D * 0.5 }, { 54, 48, 140 }, "Neon"),
		piece("domeSlit", { 2.4, 0.2, D * 0.6 }, { 0, 15.1, D * 0.5 }, { 20, 18, 46 }, "SmoothPlastic"),
	}
end
RoomArt.Decor = DECOR

-- Every decor part of a band for a W x D room.
function RoomArt.decorParts(decorIds: { string }, W: number, D: number, decorTable: any?): { any }
	local out = {}
	for _, id in decorIds do
		local f = (decorTable or DECOR)[id]
		if f then
			for _, p in f(W, D) do
				p.set = id
				table.insert(out, p)
			end
		end
	end
	return out
end

--============================================================================ critters (above head height, inside the room)
-- motion: "still" (breathing), "loop" (a slow ellipse near the ceiling), "lamp" (circling the nearest lamp),
-- "porthole" (swimming to and fro in a porthole's window box, between the view and the glass). Non-collidable,
-- never pickable. REVIEW-1 round 2 D2: the fish used to pass OUTSIDE the east wall, where a closed room shows nothing.
RoomArt.Critters = {
	cat = { motion = "still", anchor = "ledge", parts = {
		{ size = { 1.6, 1.0, 1.0 }, offset = { 0, 0, 0 }, color = { 206, 150, 100 }, shape = "Ball" },
		{ size = { 0.8, 0.8, 0.8 }, offset = { 0.9, 0.2, 0 }, color = { 210, 156, 106 }, shape = "Ball" },
		{ size = { 1.2, 0.2, 0.2 }, offset = { -1.0, -0.2, 0.3 }, color = { 190, 140, 92 }, shape = "Block" },
	} },
	butterfly = { motion = "loop", parts = {
		{ size = { 0.7, 0.05, 0.5 }, offset = { -0.35, 0, 0 }, color = { 232, 156, 232 }, shape = "Block" },
		{ size = { 0.7, 0.05, 0.5 }, offset = { 0.35, 0, 0 }, color = { 232, 156, 232 }, shape = "Block" },
	} },
	moth = { motion = "lamp", parts = {
		{ size = { 0.5, 0.05, 0.35 }, offset = { 0, 0, 0 }, color = { 206, 196, 176 }, shape = "Block" },
	} },
	frog = { motion = "still", anchor = "ledge", parts = {
		{ size = { 0.9, 0.6, 0.9 }, offset = { 0, 0, 0 }, color = { 64, 150, 132 }, shape = "Ball" },
		{ size = { 0.3, 0.3, 0.3 }, offset = { 0.3, 0.35, 0.3 }, color = { 230, 230, 200 }, shape = "Ball" },
	} },
	parrot = { motion = "still", anchor = "ledge", parts = {
		{ size = { 0.8, 1.2, 0.8 }, offset = { 0, 0, 0 }, color = { 44, 182, 204 }, shape = "Ball" },
		{ size = { 0.3, 0.3, 0.4 }, offset = { 0, 0.5, 0.4 }, color = { 240, 220, 140 }, shape = "Block" },
		{ size = { 0.2, 0.9, 0.2 }, offset = { 0, -0.9, -0.2 }, color = { 40, 140, 170 }, shape = "Block" },
	} },
	fish = { motion = "porthole", parts = {
		{ size = { 0.2, 0.4, 0.7 }, offset = { 0, 0, 0 }, color = { 122, 202, 232 }, shape = "Ball" },
	} },
	starmote = { motion = "loop", parts = {
		{ size = { 0.35, 0.35, 0.35 }, offset = { 0, 0, 0 }, color = { 204, 194, 255 }, shape = "Ball", material = "Neon" },
	} },
}

-- A critter's position (room-local) at time t: deterministic from (kind, index, t) and the room size, never
-- from a prop. Loops stay between y 12 and 14.5 (above head height and the shelf props).
function RoomArt.critterPos(kind: string, i: number, t: number, W: number, D: number): { number }
	local spec = RoomArt.Critters[kind]
	local motion = spec and spec.motion or "loop"
	if motion == "still" then
		local corners = { { -W / 2 + 1.2, D - 1.2 }, { W / 2 - 1.2, D - 1.2 }, { -W / 2 + 1.2, 1.4 } }
		local c = corners[((i - 1) % #corners) + 1]
		return { c[1], 11.0 + 0.05 * math.sin(t * 1.5 + i), c[2] }
	elseif motion == "porthole" then
		-- fish i swims in porthole E1, W2, E2, W1, ... to and fro across its window box, never past the rim
		local zf = RoomArt.PORT_Z[((i - 1) // 2) % 2 + 1]
		local side = if i % 2 == 1 then 1 else -1
		if (i - 1) // 2 % 2 == 1 then side = -side end
		local a = t * 0.6 + i * 1.7
		return { side * (W / 2 - RoomArt.PORT_GAP), RoomArt.PORT_Y + 0.25 * math.sin(a * 1.3), D * zf + 0.7 * math.sin(a) }
	elseif motion == "lamp" then
		local a = t * 1.7 + i * 2.1
		return { (i % 2 == 0 and 1 or -1) * W * 0.25 + 1.4 * math.cos(a), 13.2 + 0.4 * math.sin(a * 1.3), D * 0.5 + 1.4 * math.sin(a) }
	end
	local a = t * 0.35 + i * 1.9
	return { (W * 0.32) * math.cos(a), 13.2 + 0.9 * math.sin(a * 2.1 + i), D * 0.5 + (D * 0.32) * math.sin(a) }
end

--============================================================================ weather (2 emitters, capped)
RoomArt.Weather = {
	motes = { color = { 255, 242, 214 }, size = 0.14, speed = { 0.1, 0.4 }, life = { 6, 10 }, accel = { 0, -0.1, 0 }, light = 0.5, alpha = 0.45 },
	dust = { color = { 232, 214, 176 }, size = 0.16, speed = { 0.2, 0.5 }, life = { 6, 10 }, accel = { 0, -0.2, 0 }, light = 0.4, alpha = 0.5 },
	mist = { color = { 222, 236, 224 }, size = 3.0, speed = { 0.2, 0.5 }, life = { 6, 9 }, accel = { 0, -0.05, 0 }, light = 0.1, alpha = 0.85 },
	-- rain and drizzle RUN DOWN GLASS (RoomArt.WeatherOnGlass): slow, short-lived streaks that never fall far
	drizzle = { color = { 182, 212, 240 }, size = 0.1, speed = { 0.6, 1.0 }, life = { 0.6, 0.9 }, accel = { 0, -0.5, 0 }, light = 0.2, alpha = 0.35 },
	rain = { color = { 172, 192, 232 }, size = 0.12, speed = { 1.2, 1.6 }, life = { 0.3, 0.4 }, accel = { 0, -2, 0 }, light = 0.3, alpha = 0.25 },
	twinkle = { color = { 232, 232, 255 }, size = 0.2, speed = { 0, 0.2 }, life = { 1, 2 }, accel = { 0, 0, 0 }, light = 1, alpha = 0.2 },
}
-- REVIEW-1 round 2 D2: a room is a closed box, so weather beyond its walls is never seen (the ship's rain and the
-- greenhouse drizzle used to fall beyond the east wall). Rain runs down the ship's portholes, in the window box
-- behind the glass; drizzle runs down the inside of the greenhouse's north glass, high up. Every spot is inside the
-- room, on a wall, and no streak falls into the props' height band (Bands.spec), so none ever crosses a prop.
RoomArt.WeatherOnGlass = { rain = "portholes", drizzle = "glass" }

-- Where each weather kind's emitters stand in a W x D room: { pos, size, porthole? } (room-local, studs). A kind
-- that does not fall (motes, dust, mist, twinkle) drifts from one host under the ceiling, as before.
function RoomArt.weatherSpots(kind: string, W: number, D: number, cfg: any): { any }
	local on = RoomArt.WeatherOnGlass[kind]
	if on == "portholes" then
		local out = {}
		for _, p in { { "E", 1, 1 }, { "W", -1, 2 } } do
			local zf = RoomArt.PORT_Z[p[3]]
			table.insert(out, { pos = { p[2] * (W / 2 - RoomArt.PORT_GAP), RoomArt.PORT_Y + 0.4, D * zf }, size = { 0.1, 0.8, 1.4 }, porthole = p[1] .. p[3] })
		end
		return out
	elseif on == "glass" then
		return { { pos = { 0, 13, D - 0.3 }, size = { W - 8, 2, 0.1 } } }
	end
	return { { pos = { 0, cfg.Room.Height - 1.5, D / 2 }, size = { 30, 0.4, 30 } } }
end

-- the ship's storm: now and then the view in every porthole flashes (never a Lighting property: a clue colour never
-- changes under it); Bands.validate keeps the flash away from the ring red and the find gold
RoomArt.Lightning = { color = { 210, 222, 255 }, every = { 6, 11 }, seconds = 0.12 }

--============================================================================ hazards (ceiling drops)
RoomArt.Hazards = {
	pinecone = { { size = { 1.0, 1.4, 1.0 }, offset = { 0, 0, 0 }, color = { 112, 80, 50 }, shape = "Ball", material = "Wood" } },
	book = {
		{ size = { 1.6, 0.4, 1.2 }, offset = { 0, 0, 0 }, color = { 52, 62, 122 }, shape = "Block" },
		{ size = { 1.5, 0.3, 1.1 }, offset = { 0.05, 0, 0 }, color = { 240, 236, 222 }, shape = "Block" },
	},
	flowerpot = {
		{ size = { 1.0, 1.2, 1.2 }, offset = { 0, 0, 0 }, color = { 178, 104, 72 }, shape = "Cylinder" },
		{ size = { 0.4, 0.8, 0.4 }, offset = { 0, 0.8, 0 }, color = { 90, 140, 70 }, shape = "Block" },
	},
	crate = { { size = { 1.4, 1.4, 1.4 }, offset = { 0, 0, 0 }, color = { 152, 112, 62 }, shape = "Block", material = "WoodPlanks" } },
	pebble = {
		{ size = { 1.0, 0.8, 1.0 }, offset = { 0, 0, 0 }, color = { 82, 82, 92 }, shape = "Ball", material = "Slate" },
		{ size = { 0.5, 0.5, 0.5 }, offset = { 0, 0.2, 0 }, color = { 182, 122, 255 }, shape = "Ball", material = "Neon" },
	},
}
RoomArt.HazardTrail = { pinecone = "dust", book = "dust", flowerpot = "mist", crate = "dust", pebble = "twinkle" }

--============================================================================ lamps (<= Budget.Lights)
function RoomArt.lampSpots(W: number, D: number): { { number } }
	return { { -W * 0.25, 14.6, D * 0.3 }, { W * 0.25, 14.6, D * 0.3 }, { -W * 0.25, 14.6, D * 0.72 }, { W * 0.25, 14.6, D * 0.72 } }
end

--============================================================================ counting (the budget)
function RoomArt.propParts(kind: string): number
	return #(RoomArt.Kinds[kind] or {})
end

-- Local parts a room needs at most, before the hazard reserve: props, tables, shelves, screens, decor, critters
-- (at the band's counts), found items, lamps.
function RoomArt.roomParts(payload: any, band: any, cfg: any): (number, any)
	local props = 0
	for _, p in payload.props do props += RoomArt.propParts(p.kind) end
	local tables = #payload.tables * RoomArt.TableParts
	local shelves = #payload.shelves * RoomArt.ShelfParts
	local screens = 0
	if payload.W < cfg.Room.ShellW then screens += 2 end
	if payload.D < cfg.Room.ShellD then screens += 1 end
	local decor = math.min(#RoomArt.decorParts(band.decor, payload.W, payload.D), cfg.Budget.DecorParts)
	local critters = 0
	local shown = 0
	for _, c in band.critters do
		local n = math.min(c.count, cfg.Budget.Critters - shown)
		shown += n
		critters += n * #RoomArt.Critters[c.kind].parts
	end
	local items = math.min(#payload.clues, cfg.Budget.ItemsShown)
	local lamps = math.min(#RoomArt.lampSpots(payload.W, payload.D), cfg.Budget.Lights)
	local total = props + tables + shelves + screens + decor + critters + items + lamps
	return total, { props = props, tables = tables, shelves = shelves, screens = screens, decor = decor, critters = critters, items = items, lamps = lamps }
end

return RoomArt
