-- Spec for Bands: the five environment bands and the rules that keep eye candy honest.
-- Run: luau tests/Bands.spec.luau
--
-- Bands follow the player's OWN run: progress = seals carried (0..3), 4 once the Door opens. From the
-- server's Run payload, never from time (DESIGN §7). The rules pinned here are the ones that stop
-- decoration from becoming information in a ranked, shared maze:
--   * decor placement is a pure function of (wall key, face, band): it never reads a cell's content,
--     so it cannot point toward a seal or the Door;
--   * nothing but a seal glows seal-gold and nothing but a hazard ring is red: every decor, critter,
--     weather, wall, torch and door colour keeps MinColourDistance from both;
--   * decor sits at most 1.2 studs out of a face; weather goes through EnvBands.capRates.
local Bands = require("../src/shared/Bands")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")
local Grid = require("../src/shared/Grid")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local cfg = Config
local bands = cfg.Env.Bands

--================================================================ the shipped bands validate
do
	local ok, err = Bands.validate(cfg, EnvBands)
	truthy(ok, "the shipped bands validate (" .. tostring(err) .. ")")
	eq(#bands, 5, "five bands")
	for i, b in bands do eq(b.from, i - 1, "band " .. i .. " starts at progress " .. (i - 1)) end
	eq(bands[1].name, "Cold Cellar", "band 1 is the Cold Cellar")
	eq(bands[5].name, "Dawn Sanctum", "band 5 is the Dawn Sanctum")
end

local function mutate(f)
	local c = table.clone(cfg)
	c.Env = table.clone(cfg.Env)
	c.Env.Bands = {}
	for i, b in cfg.Env.Bands do
		local nb = table.clone(b)
		nb.decor = {}
		for j, d in b.decor do nb.decor[j] = table.clone(d) end
		nb.critter = table.clone(b.critter)
		nb.weather = table.clone(b.weather)
		c.Env.Bands[i] = nb
	end
	c.Colours = table.clone(cfg.Colours)
	f(c)
	return (Bands.validate(c, EnvBands))
end
eq(mutate(function(c) c.Env.Bands[2].decor[1].color = { 250, 195, 80 } end), false, "a decor colour near seal-gold is rejected")
eq(mutate(function(c) c.Env.Bands[4].weather.color = { 225, 50, 45 } end), false, "an ember colour near hazard-red is rejected")
eq(mutate(function(c) c.Env.Bands[3].critter.color = { 255, 205, 75 } end), false, "a gold critter is rejected")
eq(mutate(function(c) c.Env.Bands[1].torch = { 240, 45, 40 } end), false, "a red torch is rejected")
eq(mutate(function(c) c.Env.Bands[5].wall = { 255, 200, 70 } end), false, "a seal-gold wall is rejected")
eq(mutate(function(c) c.Colours.DoorAwake = { 255, 200, 70 } end), false, "a seal-gold Door glow is rejected")
eq(mutate(function(c) c.Env.Bands[2].weather.rate = 90 end), false, "one weather emitter above the 60/s budget is rejected")
eq(mutate(function(c) c.Env.Bands[2].critter.count = 20 end), false, "more critters than the budget is rejected")
eq(mutate(function(c) table.remove(c.Env.Bands) end), false, "fewer than five bands is rejected")
eq(mutate(function(c) c.Env.Bands[3].from = 2.5 end), false, "a band that does not start on a whole seal count is rejected")

--================================================================ progress
eq(Bands.progress(0, false), 0, "no seals: Cold Cellar")
eq(Bands.progress(2, false), 2, "two seals: Crystal Seams")
eq(Bands.progress(3, false), 3, "three seals: the Door wakes (Ember Vault)")
eq(Bands.progress(3, true), 4, "the Door opened: Dawn Sanctum")
eq(Bands.progress(9, false), 3, "a junk count clamps to 3")
eq(Bands.progress(-1, false), 0, "a negative count clamps to 0")
eq(EnvBands.indexAt(bands, Bands.progress(1, false)), 2, "one seal is band 2 (Moss Halls)")

--================================================================ decor never encodes the layout
do
	-- the same wall, face and band give the same piece on every day, whatever the cells hold
	local same, total, placed, maxOut = 0, 0, 0, 0
	for y = 0, 8 do
		for x = 0, 8 do
			for _, side in { "N", "E", "S", "W" } do
				local key = Grid.edgeKey(x, y, side, cfg)
				for band = 1, 5 do
					local a = Bands.decorFor(key, side, band, cfg, EnvBands.hash01)
					local b = Bands.decorFor(key, side, band, cfg, EnvBands.hash01)
					total += 1
					if (a == nil and b == nil) or (a and b and a.kind == b.kind and a.u == b.u and a.h == b.h) then same += 1 end
					if a then
						placed += 1
						maxOut = math.max(maxOut, a.out)
					end
				end
			end
		end
	end
	eq(same, total, "decor is a pure function of (wall, face, band): " .. total .. " of " .. total .. " agree")
	truthy(maxOut <= cfg.Env.DecorMaxOut, string.format("no decor sits more than %.1f studs out of a face (max %.2f)", cfg.Env.DecorMaxOut, maxOut))
	local share = placed / total
	truthy(math.abs(share - Bands.DECOR_SHARE) < 0.06, string.format("about half the faces carry a piece (%.0f %%)", share * 100))
	-- the signature itself: decorFor(key, face, band, cfg, hash01) takes no cell content. Pinned by
	-- arity, so adding a content argument (the way a layout leak would get in) fails this spec.
	local arity = debug.info(Bands.decorFor, "a")
	eq(arity, 5, "decorFor takes exactly (wall key, face, band, cfg, hash01): no cell content")
end

do -- embers rise straight up; weather never drifts toward anything
	for i, b in bands do
		local v = Bands.weatherVelocity(i, cfg)
		eq(v.x, 0, b.name .. " weather has no sideways drift (x)")
		eq(v.z, 0, b.name .. " weather has no sideways drift (z)")
	end
	truthy(Bands.weatherVelocity(4, cfg).y > 0, "embers rise")
end

--================================================================ weather is budgeted
do
	local rates = Bands.weatherRates(bands, EnvBands.weights(bands, 2))
	local capped = EnvBands.capRates(rates, cfg.Budget.MaxWeatherEmitters, cfg.Budget.MaxEmitterRate, cfg.Budget.MinWeatherRate)
	local n, sum = 0, 0
	for _, r in capped do n += 1; sum += r end
	truthy(n <= 2, "at most 2 weather emitters")
	truthy(sum <= 60 + 1e-9, "at most 60 particles/s")
end

eq(Bands.colourDistance({ 0, 0, 0 }, { 3, 4, 0 }), 5, "colour distance is Euclidean RGB")

print(string.format("Bands: %d passed, %d failed", passed, failed))
if failed > 0 then error("Bands spec failed", 0) end
