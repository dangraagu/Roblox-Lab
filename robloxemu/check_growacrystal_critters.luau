-- Grow a Crystal — ambient critters keep to their zone's HEIGHT BAND, even one born on its floor.
-- Run: luau check_growacrystal_critters.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- Grotto.layout gives every ambient critter a zone, and tests/Grotto.spec.luau pins each zone's floor
-- above every standing head (moths y >= 31, bats y >= 34; the top terrace's heads are at y 26). The
-- critters bob as they wander: a sine VELOCITY, so a moth born on its floor with the bob pointing down
-- would sink ~0.5 studs under it and a bat ~0.8, and only CavernArt's clamp stops that.
-- check_growacrystal_env cannot see it: the client's Random is unseeded, critters are born anywhere in
-- their zone, and it only asks for 3.5 studs over a head (the mutation sweep's survivor A2, removing the
-- clamp, passed all 24 suites).
--
-- So this drives the REAL CavernArt from the bundle with a scripted rand: critters born exactly on the
-- floor and on the ceiling of their zone, with the bob's phase stepped around the whole circle, and
-- every frame for 20 s it reads where each critter's part actually IS. Wisps (which rise out of the pool
-- up the light shaft and start again from the water) are held to their band too.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Grotto, Cavern, Rng = mod("Config"), mod("Grotto"), mod("Cavern"), mod("Rng")
local CavernArt = mod("CavernArt")
local layout = Grotto.layout(Config, Rng, Cavern)

-- Any plot. Not the origin, so a mix-up between plot-local and world heights cannot pass by accident.
local ORIGIN = Vector3.new(260, 0, 0)
local EPS = 1e-6
local DT = 1 / 30
local SECONDS = 20

-- _spawnCritter draws, in order: x, y, z, speed, heading, phase (phase = r * 100 radians). Values are
-- queued for a spawn; every other draw (the heading's drift while wandering) gets 0.5 = no drift.
local function probe(kind, n)
	local queue = {}
	local function rand()
		if #queue > 0 then return table.remove(queue, 1) end
		return 0.5
	end
	local folder = Instance.new("Folder")
	folder.Name = "Probe_" .. kind
	folder.Parent = h.workspace
	local art = CavernArt.new(folder, rand, Config, Grotto, layout, Cavern)
	art:setOrigin(ORIGIN)
	local zone = layout.zones[kind]
	local lo, hi = zone.min.y, zone.max.y
	local now = 0
	local want = { [kind] = 0 }
	-- born one per frame (CavernArt's own rule), alternately ON the floor and ON the ceiling, with the
	-- bob's phase stepped around the circle so some start by moving out of the band
	for j = 1, n do
		local onFloor = j % 2 == 1
		local phase = (j - 1) * (2 * math.pi / n)
		for _, v in { 0.5, if onFloor then 0 else 1 - 1e-9, 0.5, 0.5, 0.5, phase / 100 } do
			table.insert(queue, v)
		end
		want[kind] = j
		now += DT
		art:updateCritters(want, DT, now)
	end
	local partName = if kind == "bat" then "Bat_Body" elseif kind == "moth" then "Moth" else "Wisp"
	local seen, lowest, highest = 0, math.huge, -math.huge
	local escaped = nil
	for _ = 1, math.floor(SECONDS / DT) do
		now += DT
		art:updateCritters(want, DT, now)
		local count = 0
		for _, d in folder:GetChildren() do
			if d.Name == partName then
				count += 1
				local y = d.Position.Y - ORIGIN.Y
				lowest = math.min(lowest, y)
				highest = math.max(highest, y)
				if (y < lo - EPS or y > hi + EPS) and escaped == nil then
					escaped = string.format("%s at y %.3f (band %.1f..%.1f) after %.2f s", partName, y, lo, hi, now)
				end
			end
		end
		seen = math.max(seen, count)
	end
	folder:Destroy()
	return { seen = seen, lowest = lowest, highest = highest, escaped = escaped, lo = lo, hi = hi }
end

for _, kind in { "moth", "bat" } do
	local r = probe(kind, 8)
	print(string.format("  %-4s band %.1f..%.1f: lowest %.3f, highest %.3f over %d s", kind, r.lo, r.hi, r.lowest, r.highest, SECONDS))
	eq(r.seen, 8, kind .. ": all 8 probe critters are alive in the world")
	-- the probe is not vacuous: critters really were born on the band's floor and ceiling
	truthy(r.lowest <= r.lo + 0.05, kind .. string.format(": a critter reached the band's floor (lowest %.3f, floor %.1f)", r.lowest, r.lo))
	truthy(r.highest >= r.hi - 0.05, kind .. string.format(": and one its ceiling (highest %.3f, ceiling %.1f)", r.highest, r.hi))
	eq(r.escaped, nil, kind .. ": no critter ever leaves its zone's height band, whichever way its bob starts")
end

do
	local r = probe("wisp", 5)
	print(string.format("  wisp band %.1f..%.1f: lowest %.3f, highest %.3f over %d s", r.lo, r.hi, r.lowest, r.highest, SECONDS))
	eq(r.seen, 5, "wisp: all 5 probe wisps are alive in the world")
	eq(r.escaped, nil, "wisp: wisps rise inside their band and start again from the water")
	truthy(r.highest > r.hi - 1, string.format("wisp: they do rise the whole shaft (highest %.2f of %.1f)", r.highest, r.hi))
end

eq(#h.warnings, 0, "no warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal critters: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal critters check failed", 0) end
