--!strict
-- Bands.luau: which band a room is in, and the colour rules every band keeps (DESIGN.md §7, §8, §18). Pure;
-- Config, RoomArt and EnvBands are passed in.
--
-- The trigger is the chapter you are in (progress = chapter, the bands start at 0, 4, 7, 10, 13 with fade 0).
-- A Daily Case uses its theme band's first progress. Clearing a band's last chapter moves progress to the next
-- band's start, so the room you stand in glides toward it as the reward.

local Bands = {}

function Bands.distance(a: { number }, b: { number }): number
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dr * dr + dg * dg + db * db)
end

function Bands.tinted(rgb: { number }, tint: { number }): { number }
	return { rgb[1] * tint[1] / 255, rgb[2] * tint[2] / 255, rgb[3] * tint[3] / 255 }
end

local function indexAt(bands: { any }, p: number): number
	local idx = 1
	for i = 2, #bands do
		if p >= bands[i].from then idx = i else break end
	end
	return idx
end

function Bands.forChapter(ch: number, cfg: any): number
	return indexAt(cfg.Env.Bands, ch)
end

function Bands.progressAfterClear(ch: number, cfg: any): number
	local bands = cfg.Env.Bands
	local i = indexAt(bands, ch)
	local nb = bands[i + 1]
	if nb and ch + 1 >= nb.from then return nb.from end
	return ch
end

function Bands.progressForDaily(day: number, cfg: any): number
	local nb = #cfg.Env.Bands
	local i = ((day - cfg.Daily.FirstDay) % nb) + 1
	return cfg.Env.Bands[i].from
end

-- Every colour the world shows that is not a prop's clue colour, with where it comes from.
function Bands.colours(cfg: any, art: any): { any }
	local out = {}
	local function add(rgb: any, where: string)
		if type(rgb) == "table" and #rgb == 3 then table.insert(out, { rgb = rgb, where = where }) end
	end
	for _, b in cfg.Env.Bands do
		for k, v in b.palette do add(v, b.id .. ".palette." .. k) end
		add(b.lamp.color, b.id .. ".lamp")
		for _, p in art.decorParts(b.decor, 48, 38, art.Decor) do add(p.color, b.id .. ".decor." .. p.id) end
	end
	for kind, c in art.Critters do
		for i, p in c.parts do add(p.color, "critter." .. kind .. "." .. i) end
	end
	for kind, w in art.Weather do add(w.color, "weather." .. kind) end
	if art.Lightning then add(art.Lightning.color, "lightning") end -- REVIEW-1 round 2 D2: the ship's porthole flashes
	for kind, parts in art.Hazards do
		for i, p in parts do add(p.color, "hazard." .. kind .. "." .. i) end
	end
	add(art.Trim, "prop trim")
	-- items are shown only once FOUND, so gold is theirs to use; they must still never be red
	return out
end

local function itemColours(art: any): { any }
	local out = {}
	for id, it in art.Items do table.insert(out, { rgb = it.color, where = "item." .. id }) end
	return out
end

-- (ok, why) for one band's decor in a W x D room: every part high on a wall, flat on the floor, or in a corner.
function Bands.decorPlacement(decorIds: { string }, W: number, D: number, art: any, cfg: any): (boolean, string?)
	for _, p in art.decorParts(decorIds, W, D, art.Decor) do
		local sx, sy, sz = art.extent(p)
		local x0, x1 = p.pos[1] - sx / 2, p.pos[1] + sx / 2
		local y0, y1 = p.pos[2] - sy / 2, p.pos[2] + sy / 2
		local z0, z1 = p.pos[3] - sz / 2, p.pos[3] + sz / 2
		if x0 < -W / 2 - 0.01 or x1 > W / 2 + 0.01 or z0 < -0.01 or z1 > D + 0.01 or y1 > cfg.Room.Height + 0.01 then
			return false, p.id .. " is outside the room"
		end
		local high = y0 >= art.DECOR_HIGH - 1e-9
		local flat = y1 <= art.DECOR_FLAT + 1e-9
		local c = art.DECOR_CORNER
		local corner = (x0 >= W / 2 - c - 1e-9 or x1 <= -W / 2 + c + 1e-9) and (z1 <= c + 1e-9 or z0 >= D - c - 1e-9)
		if not (high or flat or corner) then return false, p.id .. " stands in the props' bands" end
	end
	return true, nil
end

function Bands.validate(cfg: any, art: any, EnvBands: any): (boolean, string?)
	local bands = cfg.Env.Bands
	local ok, err = EnvBands.validate(bands)
	if not ok then return false, err end
	if #bands ~= 5 then return false, "there must be five bands" end
	local wantFrom = { 0, 4, 7, 10, 13 }
	for i, b in bands do
		if b.from ~= wantFrom[i] then return false, b.id .. " must start at progress " .. wantFrom[i] end
		if (b.fade or 0) ~= 0 then return false, b.id .. " fades: the light must never change during a search" end
		if type(b.tint) ~= "table" then return false, b.id .. " has no tint" end
		if type(b.hazards) ~= "table" or #b.hazards ~= 1 or cfg.Hazards.Kinds[b.hazards[1]] == nil then
			return false, b.id .. " needs exactly one configured hazard kind"
		end
		for _, id in b.decor do
			if table.find(cfg.Traits.Kinds, id) then return false, b.id .. " decor '" .. id .. "' is a prop kind" end
			if art.Decor[id] == nil then return false, b.id .. " decor '" .. id .. "' has no art" end
		end
		for _, c in b.critters do
			if art.Critters[c.kind] == nil then return false, b.id .. " critter '" .. c.kind .. "' has no art" end
		end
		for _, w in b.weather do
			if art.Weather[w.kind] == nil then return false, b.id .. " weather '" .. w.kind .. "' has no art" end
		end
		for _, size in { { 32, 24 }, { 40, 30 }, { 44, 34 }, { 48, 38 } } do
			local okP, why = Bands.decorPlacement(b.decor, size[1], size[2], art, cfg)
			if not okP then return false, b.id .. ": " .. tostring(why) end
		end
	end
	local R = cfg.Reserved
	for _, c in Bands.colours(cfg, art) do
		if Bands.distance(c.rgb, R.Ring) < R.MinDistance then return false, c.where .. " is too close to the hazard ring's red" end
		if Bands.distance(c.rgb, R.Gold) < R.MinDistance then return false, c.where .. " is too close to the find gold" end
	end
	for _, c in itemColours(art) do
		if Bands.distance(c.rgb, R.Ring) < R.MinDistance then return false, c.where .. " is too close to the hazard ring's red" end
	end
	local T = cfg.Traits
	for _, col in T.Colours do
		local rgb = T.RGB[col]
		if Bands.distance(rgb, R.Ring) < R.MinDistance or Bands.distance(rgb, R.Gold) < R.MinDistance then
			return false, "clue colour " .. col .. " is too close to a reserved colour"
		end
	end
	for _, b in bands do
		for i = 1, #T.Colours do
			for j = i + 1, #T.Colours do
				local d = Bands.distance(Bands.tinted(T.RGB[T.Colours[i]], b.tint), Bands.tinted(T.RGB[T.Colours[j]], b.tint))
				if d < R.ClueMinDistance then
					return false, b.id .. " light makes " .. T.Colours[i] .. " and " .. T.Colours[j] .. " too close"
				end
			end
		end
	end
	return true, nil
end

return Bands
