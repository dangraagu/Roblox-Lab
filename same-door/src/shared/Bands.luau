--!strict
-- Bands.luau — the five environment bands' rules (DESIGN §7). Pure; dependencies passed in.
--
-- The band data lives in Config.Env.Bands; EnvBands.luau (verbatim from +1 Jump) does the blending.
-- This module holds what is specific to a ranked, shared maze:
--   * progress is the number of seals carried (0..3), 4 once the Door has opened: never time;
--   * decor on a wall face is a pure function of (wall key, face, band). It takes no cell content,
--     so a piece can never point toward a seal or the Door (Bands.spec pins the arity);
--   * two colours are reserved: only a seal glows seal-gold, only a hazard ring is red. validate()
--     rejects any band, torch or door colour closer than MinColourDistance to either;
--   * weather drifts straight up or down (embers rise straight up), never sideways toward anything.

local Bands = {}

local SIDE_INDEX = { N = 1, E = 2, S = 3, W = 4 }
local DECOR_SEED = 7331
-- [C] half the wall faces carry a piece. Measured on the eye-candy walk at 1/3: at most 4 pieces within
-- 24 studs, which reads bare; the budget (30) is far away either way.
Bands.DECOR_SHARE = 0.5

function Bands.colourDistance(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

function Bands.progress(seals: number, doorOpen: boolean): number
	if doorOpen then return 4 end
	local n = math.floor(tonumber(seals) or 0)
	return math.clamp(n, 0, 3)
end

local function isColour(c: any): boolean
	return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

-- (ok, err)
function Bands.validate(cfg: any, EnvBands: any): (boolean, string?)
	local bands = cfg.Env.Bands
	local ok, err = EnvBands.validate(bands)
	if not ok then return false, err end
	if #bands ~= 5 then return false, "there must be exactly 5 bands" end
	local C = cfg.Colours
	local minD = C.MinColourDistance
	local function clear(c: any, what: string): string?
		if not isColour(c) then return what .. " is not a colour" end
		if Bands.colourDistance(c, C.SealGold) < minD then return what .. " is too close to seal-gold" end
		if Bands.colourDistance(c, C.HazardRed) < minD then return what .. " is too close to hazard-red" end
		return nil
	end
	for i, b in bands do
		if b.from ~= i - 1 then return false, "band " .. i .. " must start at " .. (i - 1) .. " seals" end
		if (b.fade or 0) ~= 0 then return false, "band " .. i .. " must not fade by progress (a seal is a step)" end
		if type(b.lighting) ~= "table" or type(b.colorCorrection) ~= "table" or type(b.bloom) ~= "table" then
			return false, "band " .. i .. " lacks a lighting group"
		end
		local e = clear(b.wall, b.name .. " wall") or clear(b.torch, b.name .. " torch")
			or clear(b.critter and b.critter.color, b.name .. " critter") or clear(b.weather and b.weather.color, b.name .. " weather")
		if e then return false, e end
		if type(b.decor) ~= "table" or #b.decor == 0 then return false, b.name .. " has no decor" end
		for _, d in b.decor do
			local e2 = clear(d.color, b.name .. " " .. tostring(d.kind))
			if e2 then return false, e2 end
		end
		if type(b.critter.count) ~= "number" or b.critter.count > cfg.Budget.MaxCritters then
			return false, b.name .. " has more critters than the budget"
		end
		if type(b.weather.rate) ~= "number" or b.weather.rate > cfg.Budget.MaxEmitterRate then
			return false, b.name .. " weather is over the emitter budget"
		end
	end
	local e3 = clear(C.DoorAwake, "the awake Door") or clear(C.DoorAsleep, "the sleeping Door") or clear(cfg.TorchDefault, "the default torch")
	if e3 then return false, e3 end
	for _, r in cfg.Ranks do
		local e4 = clear(r.torch, r.label .. " torch")
		if e4 then return false, e4 end
	end
	return true, nil
end

-- The decor piece on one wall FACE in one band, or nil. `key` is Grid.edgeKey, `face` the side of
-- the cell it is seen from. u: along the wall (-5..5 studs from its middle), h: height over the
-- floor (2..10), out: how far it stands off the face (<= DecorMaxOut).
function Bands.decorFor(key: string, face: string, band: number, cfg: any, hash01: any): any?
	local b = cfg.Env.Bands[band]
	if b == nil then return nil end
	local k, xs, ys = string.match(key, "^([EN]):(%-?%d+),(%-?%d+)$")
	if k == nil then return nil end
	local x, y = tonumber(xs) :: number, tonumber(ys) :: number
	local kc = if k == "E" then 1 else 2
	local a = kc * 1000 + x + 500
	local c = (SIDE_INDEX[face] or 0) * 10 + band
	if hash01(a, y + 500, c, DECOR_SEED) >= Bands.DECOR_SHARE then return nil end
	local pick = b.decor[1 + math.floor(hash01(a + 17, y + 511, c, DECOR_SEED) * #b.decor)] or b.decor[1]
	return {
		kind = pick.kind,
		color = pick.color,
		glow = pick.glow == true,
		u = -5 + 10 * hash01(a + 31, y + 523, c, DECOR_SEED),
		h = 2 + 8 * hash01(a + 47, y + 541, c, DECOR_SEED),
		out = 0.3 + (cfg.Env.DecorMaxOut - 0.3) * hash01(a + 59, y + 557, c, DECOR_SEED),
	}
end

-- Straight up or down; never sideways.
function Bands.weatherVelocity(band: number, cfg: any): { x: number, y: number, z: number }
	local b = cfg.Env.Bands[band]
	local kind = b and b.weather.kind or ""
	local y = -0.4
	if kind == "embers" then y = 3 elseif kind == "spores" then y = 0.6 elseif kind == "petals" then y = -1.5 end
	return { x = 0, y = y, z = 0 }
end

-- { [kind] = particles/s } blended by band weight, for EnvBands.capRates.
function Bands.weatherRates(bands: { any }, weights: { [number]: number }): { [string]: number }
	local out = {}
	for i, w in weights do
		local b = bands[i]
		if b and w > 0 then
			out[b.weather.kind] = (out[b.weather.kind] or 0) + b.weather.rate * w
		end
	end
	return out
end

return Bands
