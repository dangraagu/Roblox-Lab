-- The Studio door (DESIGN §3.5): where everything is, and when a walker on its perfect line reaches it.
-- MARKETING.md's staging table and EYECANDY.md's thumbnail shots are copied from this output.
-- Run (from this folder): luau studiodoor.luau
-- Lane 1's grid corner is world (0, 0, 1000) (Config.World), cells 16 studs, lane-local +x east, +z north.
local root = "../../"
local Dungeon = require(root .. "src/server/Dungeon")
local Config = require(root .. "src/shared/Config")
local Rng = require(root .. "src/shared/Rng")
local DoorHazards = require(root .. "src/shared/DoorHazards")

local rec = Dungeon.studioDoor(Config, Rng, 20726, 0)
assert(rec, "no Studio door")
local w = Dungeon.fromRecord(Config, rec)
local W, C = w.W, Config.Grid.Cell
local OX, OZ = 0, Config.World.LaneZ
local function cellXY(i) return i % W, i // W end
local function worldCentre(i)
	local x, y = cellXY(i)
	return OX + (x + 0.5) * C, OZ + (y + 0.5) * C
end
local SIDES = { { 1, "N" }, { 2, "E" }, { 4, "S" }, { 8, "W" } }
local function sides(i)
	local p = Dungeon.cellPayload(w, i)
	local out = {}
	for _, s in SIDES do if bit32.band(p.sides, s[1]) ~= 0 then table.insert(out, s[2]) end end
	return table.concat(out, ", ")
end

local Medals = require(root .. "src/shared/Medals")
local len, pts = Dungeon.perfectPath(Config, w)
print(string.format("Studio door: P = %.2f s (%.1f studs); Sealer <= %.2f, Gold <= %.2f, Silver <= %.2f", rec.perfectMs / 1000, len,
	Medals.thresholdMs(rec.perfectMs, "Sealer", Config) / 1000, Medals.thresholdMs(rec.perfectMs, "Gold", Config) / 1000,
	Medals.thresholdMs(rec.perfectMs, "Silver", Config) / 1000))
for k, s in w.seals do
	local x, y = cellXY(s)
	local wx, wz = worldCentre(s)
	print(string.format("seal %d: cell (%d, %d), world (%d, %d)", k, x, y, wx, wz))
end
do
	local x, y = cellXY(w.door)
	local wx, wz = worldCentre(w.door)
	print(string.format("door: cell (%d, %d), world (%d, %d), open %s", x, y, wx, wz, sides(w.door)))
end
for _, h in w.hazards do
	local x, y = cellXY(h.cell)
	local wx, wz = worldCentre(h.cell)
	local t = {}
	for n = 0, 2 do table.insert(t, string.format("%g", DoorHazards.impactTime(h.slot, n, Config.Hazards))) end
	print(string.format("hazard slot %d: cell (%d, %d), world (%d, %d), open %s; impacts at %s ... s", h.slot, x, y, wx, wz, sides(h.cell),
		table.concat(t, ", ")))
end

-- walk the line at WalkSpeed in 0.05-stud steps; when does it come within the pickup radius of each
-- seal and of the Door, and when is it inside each hazard cell
local R = Config.Pickup.Radius
local taken, t, dist = {}, 0, 0
local inCell = {}
local hazardCell = {}
for _, h in w.hazards do hazardCell[h.cell] = h.slot end
local doorAt = nil
local firstIn, order = {}, {}
local step = 0.05
for k = 2, #pts do
	local a, b = pts[k - 1], pts[k]
	local seg = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	local n = math.max(1, math.ceil(seg / step))
	for j = 1, n do
		local x = a.x + (b.x - a.x) * j / n
		local z = a.z + (b.z - a.z) * j / n
		dist += seg / n
		t = dist / Config.Walk.Speed
		for s, cell in w.seals do
			if not taken[s] then
				local cx, cz = (cell % W + 0.5) * C, (cell // W + 0.5) * C
				if (x - cx) ^ 2 + (z - cz) ^ 2 <= R * R then taken[s] = t; print(string.format("  seal %d taken at %.2f s after the line", s, t)) end
			end
		end
		local cx, cy = math.floor(x / C), math.floor(z / C)
		local i = cy * W + cx
		if cy >= 0 and firstIn[i] == nil then firstIn[i] = t; table.insert(order, i) end
		if hazardCell[i] then
			local e = inCell[i] or { from = t, to = t }
			e.to = t
			inCell[i] = e
		end
		if doorAt == nil and taken[1] and taken[2] and taken[3] then
			local dx, dz = (w.door % W + 0.5) * C, (w.door // W + 0.5) * C
			if (x - dx) ^ 2 + (z - dz) ^ 2 <= R * R then doorAt = t; print(string.format("  the Door at %.2f s after the line", t)) end
		end
	end
end
for i, e in inCell do
	local x, y = cellXY(i)
	print(string.format("  the line is inside hazard slot %d's cell (%d, %d) from %.2f to %.2f s", hazardCell[i], x, y, e.from, e.to))
end
local parts = {}
for _, i in order do
	local x, y = cellXY(i)
	table.insert(parts, string.format("(%d,%d) %.2f", x, y, firstIn[i]))
end
print("  the line enters each cell at (s after the line): " .. table.concat(parts, "; "))
