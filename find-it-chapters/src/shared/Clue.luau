--!strict
-- Clue.luau: the three traits of a prop and the clues that name them (DESIGN.md §3.1-3.2). Pure; `cfg` is
-- Config (passed in, never required: a bare string require works in the luau CLI and fails in Roblox).
--
-- A prop has exactly three traits: kind (8), colour (4, never red or gold) and height (floor, table, high).
-- A clue names one or two of them in a FORM: K ("a BASKET"), CK ("a BLUE BOX"), CH ("something YELLOW up
-- HIGH"), KH ("a JAR on the FLOOR"). A prop fits a clue when it has every trait the form names.

local Clue = {}

local function has(list: { string }, v: any): boolean
	for _, x in list do
		if x == v then return true end
	end
	return false
end

function Clue.attrs(form: string, cfg: any): { string }
	return cfg.Forms[form]
end

function Clue.matches(prop: any, clue: any, cfg: any): boolean
	local attrs = cfg.Forms[clue.form]
	if attrs == nil then return false end
	for _, a in attrs do
		if prop[a] ~= clue[a] then return false end
	end
	return true
end

-- Every prop that fits b also fits a (a's named traits are a subset of b's, with equal values).
function Clue.subsumes(a: any, b: any, cfg: any): boolean
	local attrs = cfg.Forms[a.form]
	local battrs = cfg.Forms[b.form]
	if attrs == nil or battrs == nil then return false end
	for _, x in attrs do
		if not has(battrs, x) or a[x] ~= b[x] then return false end
	end
	return true
end

-- One clue contains the other: their candidate sets can never be disjoint, so the generator rejects the pair.
function Clue.overlaps(a: any, b: any, cfg: any): boolean
	return Clue.subsumes(a, b, cfg) or Clue.subsumes(b, a, cfg)
end

local function word(v: string, cfg: any): string
	return cfg.Traits.Words[v] or string.upper(v)
end

local HEIGHT_PHRASE = { floor = "on the FLOOR", table = "on a TABLE", high = "up HIGH" }

function Clue.words(clue: any, cfg: any): string
	local f = clue.form
	if f == "K" then return "a " .. word(clue.kind, cfg) end
	if f == "CK" then return "a " .. word(clue.colour, cfg) .. " " .. word(clue.kind, cfg) end
	if f == "CH" then return "something " .. word(clue.colour, cfg) .. " " .. (HEIGHT_PHRASE[clue.height] or word(clue.height, cfg)) end
	if f == "KH" then return "a " .. word(clue.kind, cfg) .. " " .. (HEIGHT_PHRASE[clue.height] or word(clue.height, cfg)) end
	return "?"
end

-- "BLUE BOX" (colour + kind): how a prop is named in a refusal.
function Clue.name(prop: any, cfg: any): string
	return word(prop.colour, cfg) .. " " .. word(prop.kind, cfg)
end

-- "BLUE BOX · HIGH": the selected prop's chip names every trait, so colour is never the only cue.
function Clue.label(prop: any, cfg: any): string
	return Clue.name(prop, cfg) .. " \u{00B7} " .. word(prop.height, cfg)
end

-- The HUD's glyphs for a clue, in reading order: colour swatch (with its initial), kind silhouette, height arrow.
function Clue.glyphs(clue: any, cfg: any): { any }
	local out = {}
	local attrs = cfg.Forms[clue.form] or {}
	for _, trait in { "colour", "kind", "height" } do
		if has(attrs, trait) then
			local v = clue[trait]
			table.insert(out, { trait = trait, value = v, letter = string.sub(word(v, cfg), 1, 1), word = word(v, cfg) })
		end
	end
	return out
end

function Clue.validProp(prop: any, cfg: any): boolean
	if type(prop) ~= "table" then return false end
	local T = cfg.Traits
	return has(T.Kinds, prop.kind) and has(T.Colours, prop.colour) and has(T.Heights, prop.height)
end

function Clue.validClue(clue: any, cfg: any): boolean
	if type(clue) ~= "table" then return false end
	local attrs = cfg.Forms[clue.form]
	if attrs == nil then return false end
	local T = cfg.Traits
	local domain = { kind = T.Kinds, colour = T.Colours, height = T.Heights }
	for _, a in attrs do
		if not has(domain[a], clue[a]) then return false end
	end
	return true
end

-- Does the prop fit any clue in `clues` whose index is in `need` (a set of item indices still unfound)?
function Clue.fitsAny(prop: any, clues: { any }, need: { [number]: boolean }, cfg: any): number?
	for i, c in clues do
		if need[i] and Clue.matches(prop, c, cfg) then return i end
	end
	return nil
end

return Clue
