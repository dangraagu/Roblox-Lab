-- Deep Vein — the strata are IN THE ROCK the server builds.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_strata.luau
--
-- The environment bands (EYECANDY.md) change the rock itself as a miner goes down: topsoil, grey
-- stone, rust-streaked iron veins, wet blue river rock, mossy grotto, basalt with hot veins, the
-- violet geode, sandstone ruins, the black-red core. The server applies that to every stone cell it
-- builds (Strata.rockLook), because a Part's Color and Material are replicated with it anyway: the
-- strata cost nothing extra and every client sees the same rock. This file asks the workspace what
-- the server actually built, at the mouth, deep in a veteran's shaft, and after the streamer has
-- unloaded and rebuilt a cell — and that ore and bedrock did NOT change.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end

local NEW, VET = 2121, 2323
local OBS, OBS_LAYER = 2525, 142 -- a miner in the obsidian band, where the stone came closest to the bedrock (review 2026-09-24)
local VET_REBIRTHS = 12 -- wall at layer 168: the Core starts at 150

-- the veteran's saved cave: the centre column dug to the wall
do
	local Config = require("../deep-vein/src/shared/Config")
	local Mine = require("../deep-vein/src/shared/Mine")
	local w = Mine.world(Config, VET_REBIRTHS)
	local c = Mine.center(Config)
	local dug = {}
	for y = 1, w.maxLayer do dug[Mine.key(c, y, c)] = true end
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	store:SetAsync("u_" .. VET, { data = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 0,
		rebirths = VET_REBIRTHS, depthLayer = w.maxLayer, bestLayer = w.maxLayer,
		openedBits = Mine.packOpened(Config, w, dug),
	} })
	-- the obsidian miner: the same shaft, the column dug to layer OBS_LAYER
	local dugObs = {}
	for y = 1, OBS_LAYER do dugObs[Mine.key(c, y, c)] = true end
	store:SetAsync("u_" .. OBS, { data = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 0,
		rebirths = VET_REBIRTHS, depthLayer = OBS_LAYER, bestLayer = OBS_LAYER,
		openedBits = Mine.packOpened(Config, w, dugObs),
	} })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = mod("Config")
local Mine = mod("Mine")
local EnvBands = mod("EnvBands")
local Strata = mod("Strata")
truthy(Strata ~= nil and type(Strata.rockLook) == "function", "the bundle ships Strata")

local shafts = h.workspace:FindFirstChild("Shafts")
local function shaftOf(uid)
	for _, f in shafts:GetChildren() do
		if f:FindFirstChild("SellPad_" .. uid, true) ~= nil then return f end
	end
	return nil
end
local function cells(folder)
	local out = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("CellKey") ~= nil then table.insert(out, d) end
	end
	return out
end
local function rgb(c) return math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) end

-- Compares every cell Part in `folder` with what Strata says a cell at its coordinates looks like.
-- Returns (stone checked, stone wrong, ore checked, ore wrong, materials seen, layers seen).
local function audit(folder)
	local stone, stoneBad, ore, oreBad = 0, 0, 0, 0
	local materials, lo, hi = {}, math.huge, -math.huge
	local firstBad = nil
	for _, part in cells(folder) do
		local x, y, z = Mine.parseKey(part:GetAttribute("CellKey"))
		local tier = part:GetAttribute("Ore")
		lo, hi = math.min(lo, y), math.max(hi, y)
		if tier == 0 then
			stone += 1
			local want = Strata.rockLook(Config, EnvBands, y, Mine.unit(0, x, y, z, 91), Mine.unit(0, x, y, z, 92))
			local r, g, b = rgb(part.Color)
			local ok = r == want.color[1] and g == want.color[2] and b == want.color[3]
				and part.Material == Enum.Material[want.material]
			if not ok then
				stoneBad += 1
				firstBad = firstBad or string.format("%s at layer %d: %d,%d,%d %s, want %d,%d,%d %s", part.Name, y, r, g, b,
					tostring(part.Material), want.color[1], want.color[2], want.color[3], want.material)
			end
			if part.Material == Enum.Material[want.material] then materials[want.material] = true end
		else
			ore += 1
			local oc = Config.Ores.Color[tier]
			local r, g, b = rgb(part.Color)
			if part.Material ~= Enum.Material.Neon or r ~= oc[1] or g ~= oc[2] or b ~= oc[3] then oreBad += 1 end
		end
	end
	if firstBad then print("  first mismatch: " .. firstBad) end
	return stone, stoneBad, ore, oreBad, materials, lo, hi
end

--====================================================== a new miner at the mouth

local newbie = h:join("Newbie", NEW)
h:advance(1)
h.Players:simulateSpawn(newbie, h.workspace)
h:advance(2)
local nShaft = shaftOf(NEW)
truthy(nShaft ~= nil, "the new miner has a shaft")
do
	local stone, stoneBad, ore, oreBad, mats, lo, hi = audit(nShaft)
	print(string.format("  mouth: %d stone cells (layers %d..%d), %d ore", stone, lo, hi, ore))
	truthy(stone > 20, "set-up: the mouth has stone to look at (" .. stone .. ")")
	eq(stoneBad, 0, "every stone cell at the mouth has its stratum's colour and material")
	eq(oreBad, 0, "every ore cell keeps its own Neon colour")
	truthy(mats.Ground == true, "the topsoil really is Ground at the top of a new shaft")
end

--====================================================== a veteran deep in their shaft

local vet = h:join("Veteran", VET)
h:advance(1)
h.Players:simulateSpawn(vet, h.workspace)
h:advance(3)
local remotes = RS:FindFirstChild("VeinRemotes")
remotes:FindFirstChild("Elevator"):simulateFireServer(vet, "down")
h:advance(4)
local vShaft = shaftOf(VET)
truthy(vShaft ~= nil, "the veteran has a shaft")
local deepMats = {}
do
	local stone, stoneBad, ore, oreBad, mats, lo, hi = audit(vShaft)
	print(string.format("  veteran at the wall: %d stone cells (layers %d..%d), %d ore", stone, lo, hi, ore))
	truthy(lo >= 140 and hi >= 160, "set-up: DESCEND streamed the bottom of a rebirth-12 shaft (" .. lo .. ".." .. hi .. ")")
	eq(stoneBad, 0, "every stone cell at the bottom has its stratum's colour and material")
	eq(oreBad, 0, "…and every ore cell is still Neon in its ore colour")
	local coreMat = Config.Env.Bands[#Config.Env.Bands].rock.material
	truthy(mats[coreMat] == true, "the core's rock (" .. coreMat .. ") is there")
	deepMats = mats
end

--====================================================== the core looks different from the topsoil

do
	-- Plain rock only: accent cells (a molten vein in the core, darker soil up top) are their own colour
	-- by design. The first draft of this averaged accents in and measured 56 against a guessed 60 —
	-- the core's bright molten accents pull its average toward brown — so it now compares the rock itself,
	-- and the material, which is what "looks different" means for a wall of it.
	local function avg(folder, band)
		local n, r, g, b = 0, 0, 0, 0
		for _, part in cells(folder) do
			local x, y, z = Mine.parseKey(part:GetAttribute("CellKey"))
			local plain = not Strata.rockLook(Config, EnvBands, y, 0.5, Mine.unit(0, x, y, z, 92)).accent
			if plain and part:GetAttribute("Ore") == 0 and EnvBands.indexAt(Config.Env.Bands, y) == band then
				local pr, pg, pb = rgb(part.Color)
				n += 1; r += pr; g += pg; b += pb
			end
		end
		if n == 0 then return nil end
		return { r / n, g / n, b / n }
	end
	local top = avg(nShaft, 1)
	local core = avg(vShaft, #Config.Env.Bands)
	truthy(top ~= nil and core ~= nil, "set-up: stone from the first and the last stratum")
	if top and core then
		local d = Strata.contrast(top, core)
		truthy(d > 60, string.format("the core's rock is visibly not the topsoil's (average plain colours %.0f apart)", d))
	end
	local coreMat = Config.Env.Bands[#Config.Env.Bands].rock.material
	local topMat = Config.Env.Bands[1].rock.material
	truthy(coreMat ~= topMat and deepMats[coreMat] == true and deepMats[topMat] == nil,
		"…and it is a different material (" .. coreMat .. ", not " .. topMat .. ")")
end

--====================================================== unload and rebuild: the same rock comes back

do
	local keyed = {}
	for _, part in cells(vShaft) do
		keyed[part:GetAttribute("CellKey")] = { part.Color, part.Material }
	end
	remotes:FindFirstChild("Elevator"):simulateFireServer(vet, "up")
	h:advance(4)
	local stillThere = 0
	for _, part in cells(vShaft) do
		if keyed[part:GetAttribute("CellKey")] then stillThere += 1 end
	end
	eq(stillThere, 0, "set-up: SURFACE unloaded every deep cell (so what comes back is a rebuild)")
	remotes:FindFirstChild("Elevator"):simulateFireServer(vet, "down")
	h:advance(4)
	local back, same = 0, 0
	for _, part in cells(vShaft) do
		local was = keyed[part:GetAttribute("CellKey")]
		if was then
			back += 1
			if part.Color == was[1] and part.Material == was[2] then same += 1 end
		end
	end
	truthy(back > 20, "set-up: the streamer rebuilt the bottom after SURFACE and DESCEND (" .. back .. ")")
	eq(same, back, "every rebuilt cell looks exactly as it did before it was unloaded")
end

--====================================================== the box and the rest are untouched

do
	for _, folder in { nShaft, vShaft } do
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") and d:GetAttribute("Shell") ~= nil then
				eq(d.Material, Enum.Material.Basalt, d.Name .. " is still Basalt bedrock")
				local r, g, b = rgb(d.Color)
				truthy(r == 26 and g == 24 and b == 30, d.Name .. " keeps the bedrock colour")
			end
		end
	end
end

--====================================================== the bedrock still reads as the boundary
-- Review 2026-09-24, finding 2: the obsidian slate was built 4.5 RGB from the bedrock walls and the core and
-- magma were Basalt like them, so from rebirth 9 on the walls a player cannot mine (no ClickDetector,
-- REVIEW-4) looked like the rock beside them. Measured on the Parts the server really built, the bottom of
-- a rebirth-12 shaft (obsidian and the core) and the mouth, against the slabs it really built.

local obs = h:join("Obsidian", OBS)
h:advance(1)
h.Players:simulateSpawn(obs, h.workspace)
h:advance(3)
remotes:FindFirstChild("Elevator"):simulateFireServer(obs, "down")
h:advance(4)
local oShaft = shaftOf(OBS)
do
	local stone, stoneBad, _, oreBad, _, lo, hi = audit(oShaft)
	local obsBand = Config.Env.Bands[EnvBands.indexOf(Config.Env.Bands, "obsidian")]
	print(string.format("  obsidian miner at layer %d: %d stone cells (layers %d..%d)", OBS_LAYER, stone, lo, hi))
	truthy(lo >= obsBand.from and lo <= OBS_LAYER - 12 and hi >= OBS_LAYER, "set-up: DESCEND streamed the obsidian band"
		.. " around the miner, the reviewer's layer 142 included (" .. lo .. ".." .. hi .. ")")
	eq(stoneBad, 0, "every stone cell in the obsidian band has its stratum's colour and material")
	eq(oreBad, 0, "…and every ore cell there is Neon in its ore colour")
end

do
	local slab = nil
	for _, d in vShaft:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("Shell") == "wall" then slab = d end
	end
	truthy(slab ~= nil, "set-up: a bedrock wall slab to compare with")
	if slab then
		local br, bg, bb = rgb(slab.Color)
		local worst, worstAt, sameMat, n = math.huge, "", 0, 0
		for _, folder in { nShaft, vShaft, oShaft } do
			for _, part in cells(folder) do
				if part:GetAttribute("Ore") == 0 then
					n += 1
					if part.Material == slab.Material then sameMat += 1 end
					local r, g, b = rgb(part.Color)
					local d = Strata.contrast({ r, g, b }, { br, bg, bb })
					if d < worst then worst, worstAt = d, string.format("%s {%d,%d,%d} %s", tostring(part:GetAttribute("CellKey")), r, g, b, tostring(part.Material)) end
				end
			end
		end
		print(string.format("  bedrock vs the stone really built (%d cells: the mouth, the obsidian band, the core): closest %.1f RGB (%s), same material %d",
			n, worst, worstAt, sameMat))
		truthy(n > 100, "set-up: stone cells compared with the bedrock (" .. n .. ")")
		eq(sameMat, 0, "no stone Part is made of the bedrock's material")
		truthy(worst >= Config.Env.MinBedrockContrast, string.format(
			"every stone Part stays at least MinBedrockContrast (%d) from the bedrock walls (closest %.1f, %s)", Config.Env.MinBedrockContrast, worst, worstAt))
	end
end

print("")
eq(#h.warnings, 0, "the server built every shaft without warnings")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein strata: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein strata check failed", 0)
end
