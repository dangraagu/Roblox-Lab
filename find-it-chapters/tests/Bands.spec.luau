-- Spec for Bands: the five environment bands and their colour rules (DESIGN.md §7, §8, §18).
-- Run: luau tests/Bands.spec.luau 2>&1
--
-- The rules: 5 bands that follow the Book (from = 0, 4, 7, 10, 13; fade 0), each with its own light, colour,
-- scenery, critters, weather and hazard; nothing but the hazard ring is red; nothing but a found or hinted thing
-- is gold; the four clue colours stay apart under every band's light; decor never uses a prop kind's silhouette
-- and never enters the props' height bands; budgets per band.
local Bands = require("../src/shared/Bands")
local EnvBands = require("../src/shared/EnvBands")
local RoomArt = require("../src/shared/RoomArt")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function deep(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in v do o[k] = deep(x) end
	return setmetatable(o, getmetatable(v))
end

--============================================================ the shipped config passes
local ok, err = Bands.validate(Config, RoomArt, EnvBands)
eq(ok, true, "the shipped bands pass Bands.validate (" .. tostring(err) .. ")")

--============================================================ the bands follow the Book
local B = Config.Env.Bands
eq(#B, 5, "five bands")
local froms = {}
for _, b in B do table.insert(froms, b.from) end
eq(table.concat(froms, ","), "0,4,7,10,13", "from = 0, 4, 7, 10, 13")
for ch = 1, 15 do
	eq(Bands.forChapter(ch, Config), math.floor((ch - 1) / 3) + 1, "chapter " .. ch .. " is in band " .. (math.floor((ch - 1) / 3) + 1))
end
eq(Bands.progressAfterClear(3, Config), 4, "clearing chapter 3 (a band's last) glides the room toward band 2")
eq(Bands.progressAfterClear(2, Config), 2, "clearing chapter 2 keeps band 1")
eq(Bands.progressAfterClear(15, Config), 15, "chapter 15 has no next band")
eq(Bands.forChapter(Bands.progressAfterClear(12, Config), Config), 5, "after chapter 12 the room glides to the observatory")
eq(Bands.progressForDaily(20733, Config), 0, "Case #1 uses band 1's progress")
eq(EnvBands.indexAt(B, Bands.progressForDaily(20736, Config)), 4, "Case #4 is in the ship band")

--============================================================ every band is complete
for i, b in B do
	for _, g in { "lighting", "atmosphere", "bloom", "colorCorrection", "sky" } do
		truthy(type(b[g]) == "table", b.id .. " has its " .. g)
	end
	truthy(type(b.tint) == "table" and #b.tint == 3, b.id .. " has a tint")
	truthy(#b.decor >= 3, b.id .. " has at least 3 kinds of scenery")
	truthy(#b.critters >= 1, b.id .. " has critters")
	truthy(#b.weather >= 1, b.id .. " has weather")
	eq(#b.hazards, 1, b.id .. " has exactly one hazard kind")
	truthy(Config.Hazards.Kinds[b.hazards[1]] ~= nil, b.id .. "'s hazard is a configured kind")
	eq(b.fade, 0, b.id .. " never fades during a search (fade 0)")
	local crit = 0
	for _, c in b.critters do crit += c.count end
	truthy(crit <= Config.Budget.Critters, b.id .. ": " .. crit .. " critters <= " .. Config.Budget.Critters)
	local parts = #RoomArt.decorParts(b.decor, 48, 38)
	truthy(parts <= Config.Budget.DecorParts, b.id .. ": " .. parts .. " decor parts <= " .. Config.Budget.DecorParts)
	local rates = {}
	for _, w in b.weather do rates[w.kind] = w.rate end
	local on = EnvBands.capRates(rates, Config.Budget.WeatherEmitters, Config.Budget.MaxEmitterRate, Config.Budget.MinWeatherRate)
	local n, sum = 0, 0
	for _, r in on do n += 1; sum += r end
	truthy(n <= Config.Budget.WeatherEmitters and sum <= Config.Budget.MaxEmitterRate + 1e-9,
		b.id .. ": weather capped to " .. n .. " emitters, " .. sum .. " particles/s")
end
do
	local hz = {}
	for _, b in B do hz[b.hazards[1]] = true end
	local n = 0
	for _ in hz do n += 1 end
	eq(n, 5, "five different hazard kinds, one per band")
end

--============================================================ the colour rules, measured
do
	local worstRing, worstGold, whereRing, whereGold = math.huge, math.huge, "", ""
	for _, c in Bands.colours(Config, RoomArt) do
		local dr = Bands.distance(c.rgb, Config.Reserved.Ring)
		local dg = Bands.distance(c.rgb, Config.Reserved.Gold)
		if dr < worstRing then worstRing, whereRing = dr, c.where end
		if dg < worstGold then worstGold, whereGold = dg, c.where end
	end
	print(string.format("  nearest colour to the ring red: %.0f (%s); to the find gold: %.0f (%s); rule %d",
		worstRing, whereRing, worstGold, whereGold, Config.Reserved.MinDistance))
	truthy(worstRing >= Config.Reserved.MinDistance, "nothing but the ring is red")
	truthy(worstGold >= Config.Reserved.MinDistance, "nothing but a find is gold")
	local worstClue, whereClue = math.huge, ""
	for _, b in B do
		local T = Config.Traits
		for i = 1, #T.Colours do
			for j = i + 1, #T.Colours do
				local a = Bands.tinted(T.RGB[T.Colours[i]], b.tint)
				local c = Bands.tinted(T.RGB[T.Colours[j]], b.tint)
				local d = Bands.distance(a, c)
				if d < worstClue then worstClue, whereClue = d, b.id .. " " .. T.Colours[i] .. "/" .. T.Colours[j] end
			end
		end
	end
	print(string.format("  closest two clue colours under any band's light: %.0f (%s); rule %d", worstClue, whereClue, Config.Reserved.ClueMinDistance))
	truthy(worstClue >= Config.Reserved.ClueMinDistance, "the four clue colours stay apart under every band's light")
	for _, c in Config.Traits.Colours do
		truthy(Bands.distance(Config.Traits.RGB[c], Config.Reserved.Gold) >= Config.Reserved.MinDistance, "clue colour " .. c .. " is not gold")
		truthy(Bands.distance(Config.Traits.RGB[c], Config.Reserved.Ring) >= Config.Reserved.MinDistance, "clue colour " .. c .. " is not red")
	end
end

--============================================================ decor: never a prop silhouette, never in the props' bands
do
	for _, b in B do
		for _, W in { 32, 40, 44, 48 } do
			local D = ({ [32] = 24, [40] = 30, [44] = 34, [48] = 38 })[W]
			local okPlace, why = Bands.decorPlacement(b.decor, W, D, RoomArt, Config)
			truthy(okPlace, b.id .. " decor stays out of the props' bands in a " .. W .. "x" .. D .. " room (" .. tostring(why) .. ")")
		end
		for _, id in b.decor do
			truthy(table.find(Config.Traits.Kinds, id) == nil, b.id .. ": decor '" .. id .. "' is not a prop kind")
		end
	end
end

--============================================================ REVIEW-1 round 2, D2/D3: what a band shows is visible from INSIDE the room
-- Every room is a closed box (the opaque lane shell and ceiling, the client's screens), so a critter or a drop
-- beyond a wall is never seen: round 2 found the ship's two fish and its rain, and the greenhouse drizzle, beyond
-- the east wall, and the observatory's dome slit inside the opaque dome disc. So: every critter stays inside the
-- room, above head height, at all times; weather that falls (RoomArt.WeatherOnGlass) runs down the glass on the
-- ROOM side, within 0.6 studs of a wall, and no drop reaches the props' height band (DECOR_HIGH: never over a prop);
-- the dome slit hangs UNDER the disc, over a night-sky strip that its opening reveals.
do
	local sizes = { { 32, 24 }, { 40, 30 }, { 44, 34 }, { 48, 38 } }
	for _, b in B do
		for _, sz in sizes do
			local W, D = sz[1], sz[2]
			local bad = nil
			for _, c in b.critters do
				for i = 1, c.count do
					for t = 0, 60, 0.25 do
						local p = RoomArt.critterPos(c.kind, i, t, W, D)
						if math.abs(p[1]) > W / 2 - 0.3 or p[3] < 0.3 or p[3] > D - 0.3 or p[2] < 10 or p[2] > Config.Room.Height - 0.2 then
							bad = bad or string.format("%s #%d at t %.2f: (%.1f, %.1f, %.1f)", c.kind, i, t, p[1], p[2], p[3])
						end
					end
				end
			end
			truthy(bad == nil, string.format("D2: %s's critters stay inside a %dx%d room, above head height (%s)", b.id, W, D, bad or "all inside"))
			for _, w in b.weather do
				local spots = RoomArt.weatherSpots(w.kind, W, D, Config)
				truthy(#spots >= 1, string.format("D2: %s weather %s has a place in a %dx%d room", b.id, w.kind, W, D))
				for si, s in spots do
					truthy(math.abs(s.pos[1]) <= W / 2 and s.pos[3] >= 0 and s.pos[3] <= D and s.pos[2] <= Config.Room.Height,
						string.format("D2: %s %s spot %d is centred inside the room (%.1f, %.1f, %.1f)", b.id, w.kind, si, s.pos[1], s.pos[2], s.pos[3]))
					if RoomArt.WeatherOnGlass[w.kind] then
						local x0, x1 = s.pos[1] - s.size[1] / 2, s.pos[1] + s.size[1] / 2
						local z0, z1 = s.pos[3] - s.size[3] / 2, s.pos[3] + s.size[3] / 2
						local inside = x0 >= -W / 2 and x1 <= W / 2 and z0 >= 0 and z1 <= D
						local onWall = x1 >= W / 2 - 0.6 or x0 <= -W / 2 + 0.6 or z1 >= D - 0.6
						local st = RoomArt.Weather[w.kind]
						local life = st.life[2]
						local fall = st.speed[2] * life + 0.5 * math.abs(st.accel[2]) * life * life
						local lowest = s.pos[2] - s.size[2] / 2 - fall
						truthy(inside and onWall, string.format("D2: %s %s spot %d runs down a wall on the room side (x %.2f..%.2f, z %.2f..%.2f in %dx%d)",
							b.id, w.kind, si, x0, x1, z0, z1, W, D))
						truthy(lowest >= RoomArt.DECOR_HIGH, string.format("D2: %s %s spot %d: no drop falls below y %.2f (lowest %.2f): never over a prop",
							b.id, w.kind, si, RoomArt.DECOR_HIGH, lowest))
					end
				end
			end
		end
	end
	-- the ship's storm is seen as lightning in its portholes (and rain on them); the flash is never red or gold
	local ship = B[4]
	eq(ship.lightning, true, "D2: the Ship's Cabin has lightning")
	truthy(table.find(ship.decor, "portholes") ~= nil, "D2: ... in its portholes")
	eq(RoomArt.weatherSpots("rain", 48, 38, Config)[1].porthole ~= nil, true, "D2: the ship's rain runs down a porthole")
	-- the dome
	for _, sz in sizes do
		local W, D = sz[1], sz[2]
		local parts = {}
		for _, p in RoomArt.decorParts({ "dome" }, W, D) do parts[p.id] = p end
		local ring, slit, sky = parts.domeRing, parts.domeSlit, parts.domeSky
		local _, ry = RoomArt.extent(ring)
		local ringBottom = ring.pos[2] - ry / 2
		local _, sy = RoomArt.extent(slit)
		truthy(slit.pos[2] + sy / 2 <= ringBottom + 1e-9, string.format("D3: in a %dx%d room the dome slit (top %.2f) hangs under the opaque disc (bottom %.2f)",
			W, D, slit.pos[2] + sy / 2, ringBottom))
		truthy(sky ~= nil and sky.material == "Neon", "D3: a night-sky strip (Neon) lies behind the slit")
		if sky then
			local kx, ky, kz = RoomArt.extent(sky)
			local lx, _, lz = RoomArt.extent(slit)
			truthy(sky.pos[2] - ky / 2 >= slit.pos[2] + sy / 2 - 1e-9 and sky.pos[2] + ky / 2 <= ringBottom + 1e-9,
				"D3: the sky strip lies between the slit and the disc")
			truthy(kx <= lx and kz <= lz and math.abs(sky.pos[1] - slit.pos[1]) < 1e-9 and math.abs(sky.pos[3] - slit.pos[3]) < 1e-9,
				"D3: the closed slit covers the whole strip (it shows only when the slit opens)")
		end
	end
end

--============================================================ the validator catches each broken rule (mutations of a copy)
local function broken(mutate, what)
	local cfg = deep(Config)
	local art = deep(RoomArt)
	mutate(cfg, art)
	local okB = Bands.validate(cfg, art, EnvBands)
	eq(okB, false, "validate rejects " .. what)
end
broken(function(cfg) cfg.Env.Bands[2].palette.wall = { 250, 50, 40 } end, "a red wall")
broken(function(cfg) cfg.Env.Bands[3].lamp.color = { 255, 170, 10 } end, "a gold lamp")
broken(function(_, art) art.Critters.cat.parts[1].color = { 250, 45, 45 } end, "a red critter")
broken(function(_, art) art.Weather.motes.color = { 255, 166, 4 } end, "gold weather")
broken(function(_, art) art.Lightning.color = { 255, 170, 5 } end, "gold lightning (REVIEW-1 round 2 D2)")
broken(function(_, art) art.Hazards.crate[1].color = { 254, 42, 40 } end, "a red hazard (only the ring is red)")
broken(function(cfg) cfg.Env.Bands[5].tint = { 255, 255, 30 } end, "a tint that merges yellow and white")
broken(function(cfg) cfg.Env.Bands[2].from = 5 end, "a band that does not start on its chapter")
broken(function(cfg) cfg.Env.Bands[4].fade = 2 end, "a fade (the light must not change during a search)")
broken(function(cfg) cfg.Env.Bands[1].hazards = { "meteor" } end, "an unknown hazard kind")
broken(function(cfg) table.insert(cfg.Env.Bands[1].decor, "box") end, "decor named after a prop kind")
broken(function(_, art) art.Decor.rug = function(W, D) return { { id = "rug", size = { 2, 1.5, 2 }, pos = { 0, 0.75, D * 0.5 }, color = { 172, 120, 156 }, shape = "Block" } } end end,
	"decor standing in the middle of the floor")

print(string.format("Bands: %d passed, %d failed", passed, failed))
if failed > 0 then error("Bands spec failed", 0) end
