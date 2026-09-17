-- Layout.spec — the bay's geometry, measured. Run: luau tests/Layout.spec.luau
--
-- DESIGN.md §4.1 quotes these distances from design/model.luau Part 2 ([M 2]) or works them out
-- inline ([R]). The server builds the bay from Layout, so asserting them here ties the numbers
-- the design was argued from to the positions the Parts are actually given.
local Layout = require("../src/shared/Layout")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s +- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local B = Config.Bay
local function d(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end

-- bay origins
eq(Layout.bayOriginX(Config, 1), 100, "bay 1 sits at x = 100")
eq(Layout.bayOriginX(Config, 2), 180, "bays are 80 apart")
eq(Layout.bayOriginX(Config, 12), 980, "the 12th bay is centred at x = 980")

-- bins on the arc, on the -Z side, facing P
do
	local worstRadius = 0
	for slot = 1, 6 do
		local x, z = Layout.binCentre(Config, slot)
		worstRadius = math.max(worstRadius, math.abs(d(0, 0, x, z) - B.ArcRadius))
		truthy(z < 0, "bin " .. slot .. " is on the -Z side")
	end
	near(worstRadius, 0, 1e-9, "every bin centre is ArcRadius from P")
	local x1, z1 = Layout.binCentre(Config, 1)
	local x2, z2 = Layout.binCentre(Config, 2)
	local chord = d(x1, z1, x2, z2)
	near(chord, 14.49, 0.005, "adjacent bin centres are 14.49 studs apart [M 2]")
	near(chord - 2 * B.BinPromptDistance, 2.49, 0.005, "two prompt radii leave a 2.49-stud gap [M 2]")
	-- the smallest whole-stud radius with a >= 2-stud gap
	local r27 = 2 * 27 * math.sin(math.rad(15)) - 2 * B.BinPromptDistance
	truthy(r27 < 2, "ArcRadius 27 would leave under 2 studs (" .. string.format("%.2f", r27) .. ")")
end

-- stand points
do
	local sx, sz = Layout.binStand(Config, 3)
	near(d(0, 0, sx, sz), 23, 1e-9, "P to any bin's stand point is 23.0 [M 2]")
	local ax, az = Layout.binStand(Config, 1)
	local bx, bz = Layout.binStand(Config, 2)
	near(d(ax, az, bx, bz), 11.91, 0.005, "adjacent stand points are 11.91 apart [M 2]")
end

-- tray slots
do
	local farP, farPad = 0, 0
	local px, _, pz = table.unpack(B.PadCentre)
	for slot = 1, Config.Shift.TraySlots do
		local x, z = Layout.slotXZ(Config, slot)
		farP = math.max(farP, d(0, 0, x, z))
		farPad = math.max(farPad, d(px, pz, x, z))
	end
	near(farP, 10.00, 0.005, "the farthest tray slot is 10.00 from P [M 2]")
	near(farPad, 10.82, 0.005, "... and 10.82 from the spawn pad's centre [M 2]")
	truthy(farPad < B.ItemReach, "every tray item is tappable from the spawn pad without a step")

	local nearest = math.huge
	local farStand = 0
	for bin = 1, 6 do
		local bx, bz = Layout.binCentre(Config, bin)
		local sx, sz = Layout.binStand(Config, bin)
		for slot = 1, Config.Shift.TraySlots do
			local x, z = Layout.slotXZ(Config, slot)
			nearest = math.min(nearest, d(bx, bz, x, z))
			farStand = math.max(farStand, d(sx, sz, x, z))
		end
	end
	near(nearest, 24.35, 0.005, "the nearest bin centre to any tray slot is 24.35 [M 2]")
	truthy(nearest - B.ItemReach - B.BinPromptDistance >= 6.35 - 0.005,
		"so every pick is followed by at least 6.35 studs of walking")
	-- DESIGN.md §4.1 says 31.5, worked for ONE pair (the 15-degree stand point to slot (-6, 8)).
	-- Measured over every pair it is 32.93: the 45-degree stand point to the same slot. The
	-- conclusion the design drew from it (under the tag's MaxDistance of 40) still holds.
	near(farStand, 32.93, 0.005, "the farthest a stand point gets from a tray slot is 32.93 (DESIGN.md said 31.5)")
	truthy(farStand < B.TagMaxDistance, "... under the tag's MaxDistance of 40")

	-- the tutorial slots, from the pad
	for _, t in Config.Shift.Tutorial do
		local x, z = Layout.slotXZ(Config, t.slot)
		near(d(px, pz, x, z), 6.32, 0.005, "tutorial slot " .. t.slot .. " is 6.32 from the pad [R]")
	end
	local x6, z6 = Layout.slotXZ(Config, 6)
	eq(x6, -2, "slot 6 is at x = -2")
	eq(z6, B.BackRowZ, "slot 6 is in the back row")
	eq(Layout.slotSurfaceY(Config, 6), 4.5, "the back row sits on the 1.5-stud step")
	eq(Layout.slotSurfaceY(Config, 2), 3, "the front row sits on the tray top")
end

-- crate footprints keep a walkway to every wall
do
	local maxX, minZ = 0, 0
	local hw, hd = B.BinSize[1] / 2, B.BinSize[3] / 2
	for bin = 1, 6 do
		for _, c in Layout.binCorners(Config, bin) do
			maxX = math.max(maxX, math.abs(c[1]))
			minZ = math.min(minZ, c[2])
		end
	end
	truthy(maxX <= 31.001, string.format("bins stay within |x| <= 31 (%.2f)", maxX))
	truthy(minZ >= -31.001, string.format("bins stay at z >= -31 (%.2f)", minZ))
	truthy(hw > 0 and hd > 0, "crate has a size")
	-- the Back Room path between bins 3 and 4
	local x3, z3 = Layout.binCentre(Config, 3)
	near(d(0, -31, x3, z3), 8.26, 0.005, "the path point (0, -31) is 8.26 from bin 3's centre [R]")
end

print(string.format("Layout: %d passed, %d failed", passed, failed))
if failed > 0 then error("Layout tests failed") end
