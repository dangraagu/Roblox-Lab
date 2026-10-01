-- Spec for Decor: the client's per-band decor and indoor creature paths (DESIGN.md §7.2).
-- Run: luau tests/Decor.spec.luau 2>&1
--
-- Why this module exists at all: the template's ambient life spawns on a ring 70-900 studs out
-- (EnvBands.ambientSpawn), and a room is 32 studs across. Indoor creatures therefore fly bounded
-- loops computed here, and every sampled position must stay in the room's upper volume, above head
-- height and under the ceiling. Decor lives on the ceiling or flush on the walls above 9 studs, never
-- in front of a station's face (the face plus 3 studs) and never in a doorway.
local Decor = require("../src/shared/Decor")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local W = Config.World
local bands = Config.Env.Bands

-- the station faces, spelled out by hand from DESIGN.md §5 (not read from Config): x/z are the face
-- plane, the box is the face's size, and the exclusion is the face plus 3 studs into the room
local FACES = {
	{ name = "Station_A", x0 = -16, x1 = -13, y0 = 2.5, y1 = 10.5, z0 = -5, z1 = 5 },
	{ name = "Station_B", x0 = 13, x1 = 16, y0 = 2.5, y1 = 10.5, z0 = -5, z1 = 5 },
	{ name = "Door board", x0 = -16, x1 = -4, y0 = 4.5, y1 = 11.5, z0 = -16, z1 = -13 },
	{ name = "Door + keypad", x0 = -3, x1 = 10, y0 = 0, y1 = 9, z0 = -16, z1 = -13 },
	{ name = "entry doorway", x0 = -3, x1 = 3, y0 = 0, y1 = 8, z0 = 13, z1 = 16 },
}

local function boxOf(p)
	return p.pos[1] - p.size[1] / 2, p.pos[1] + p.size[1] / 2,
		p.pos[2] - p.size[2] / 2, p.pos[2] + p.size[2] / 2,
		p.pos[3] - p.size[3] / 2, p.pos[3] + p.size[3] / 2
end
local function intersects(p, f)
	local x0, x1, y0, y1, z0, z1 = boxOf(p)
	return x0 < f.x1 and f.x0 < x1 and y0 < f.y1 and f.y0 < y1 and z0 < f.z1 and f.z0 < z1
end

--============================================================ decor per indoor band
local maxPieces = 0
for _, b in bands do
	local pieces = Decor.pieces(b.id)
	truthy(type(pieces) == "table", b.id .. ": has a decor list")
	if b.id == "roof" then
		-- the Roof's decor is a skyline far out, not room decor
		local near, far = math.huge, 0
		for _, p in pieces do
			local d = math.sqrt(p.pos[1] ^ 2 + p.pos[3] ^ 2)
			near, far = math.min(near, d), math.max(far, d)
		end
		truthy(#pieces >= 12, "roof: a skyline of at least 12 blocks (" .. #pieces .. ")")
		truthy(near >= 250 and far <= 500, string.format("roof: the skyline stands 250-500 studs out (%.0f-%.0f)", near, far))
	else
		truthy(#pieces >= 4, b.id .. ": at least 4 decor pieces (" .. #pieces .. ")")
		local bad = {}
		for _, p in pieces do
			local x0, x1, y0, y1, z0, z1 = boxOf(p)
			if y0 < 9 - 1e-6 then table.insert(bad, p.id .. " starts below 9 studs") end
			if y1 > W.RoomHeight + 1e-6 then table.insert(bad, p.id .. " pokes through the ceiling") end
			if x0 < -W.RoomHalf - 1e-6 or x1 > W.RoomHalf + 1e-6 or z0 < -W.RoomHalf - 1e-6 or z1 > W.RoomHalf + 1e-6 then
				table.insert(bad, p.id .. " is outside the room")
			end
			for _, f in FACES do
				if intersects(p, f) then table.insert(bad, p.id .. " is in front of " .. f.name) end
			end
		end
		eq(#bad, 0, b.id .. ": every piece keeps off the play space" .. (if #bad > 0 then " (" .. table.concat(bad, "; ") .. ")" else ""))
	end
	maxPieces = math.max(maxPieces, #pieces)
end
truthy(maxPieces <= Config.Budget.DecorPerBand, "no band has more decor than Config.Budget.DecorPerBand (" .. maxPieces .. ")")

--============================================================ creatures: bounded loops in the upper volume
local kinds = {}
for _, b in bands do
	for _, c in b.critters or {} do kinds[c.kind] = math.max(kinds[c.kind] or 0, c.count) end
end
local nKinds = 0
for kind, count in kinds do
	nKinds += 1
	truthy(Decor.CritterParts[kind] ~= nil, kind .. ": has a model")
	local inside, samples = 0, 0
	local minY, maxY, maxR = math.huge, -math.huge, 0
	local moved = 0
	for i = 1, count do
		local last = nil
		for step = 0, 1200 do
			local t = step * 0.05
			local p = Decor.critterPos(kind, i, t)
			samples += 1
			local ok = math.abs(p.x) <= W.RoomHalf - 2 and math.abs(p.z) <= W.RoomHalf - 2 and p.y >= 8 and p.y <= 14
			if ok then inside += 1 end
			minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
			maxR = math.max(maxR, math.abs(p.x), math.abs(p.z))
			if last then moved += math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2 + (p.z - last.z) ^ 2) end
			last = p
		end
	end
	eq(inside, samples, string.format("%s: every sampled position stays in the upper volume (y %.1f-%.1f, |x|,|z| <= %.1f)",
		kind, minY, maxY, maxR))
	truthy(moved > 10 * count, kind .. ": it actually flies (" .. math.floor(moved) .. " studs in 60 s)")
	local a, b = Decor.critterPos(kind, 1, 3), Decor.critterPos(kind, 2, 3)
	if count > 1 then
		truthy(math.abs(a.x - b.x) + math.abs(a.z - b.z) + math.abs(a.y - b.y) > 0.5, kind .. ": two of them are not in the same place")
	end
end
truthy(nKinds >= 5, "at least 5 creature kinds across the bands (" .. nKinds .. ")")

-- a creature model is small and cheap
for kind, parts in Decor.CritterParts do
	truthy(#parts >= 1 and #parts <= 3, kind .. ": 1-3 parts")
end

--============================================================ the local part budget, worst case
do
	local worst = 0
	for i = 1, #bands do
		for j = i, math.min(#bands, i + 1) do
			local n = 0
			for _, k in { i, j } do
				n += #Decor.pieces(bands[k].id)
				for _, c in bands[k].critters or {} do n += c.count * #Decor.CritterParts[c.kind] end
			end
			if i == j then n = n / 2 end
			n += Config.Budget.WeatherEmitters + Config.Budget.HazardParts
			worst = math.max(worst, n)
		end
	end
	truthy(worst <= Config.Budget.LocalParts, string.format("two blended bands, a hazard and the weather hosts: %d local parts, cap %d",
		worst, Config.Budget.LocalParts))
end

print(string.format("Decor: %d passed, %d failed", passed, failed))
if failed > 0 then error("Decor spec failed", 0) end
