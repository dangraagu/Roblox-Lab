--!strict
-- Dressing.luau: builds a room from a chapter's numbers (DESIGN.md §3.3 steps 1-4) and re-dresses it on a
-- resume (§9). Pure: `rand()` in [0, 1) is injected (the server passes its life-xor-fresh draw, tests pass the
-- repo's Rng), `cfg` is Config. The SECRET (which candidate hides each item) is not drawn here: the server
-- draws it after the payload below has been built, so the payload cannot depend on it.
--
-- Room-local coordinates: the door mat's centre is (0, 0); the room is x in [-W/2, W/2], z in [0, D] (into the
-- room), y up from the floor. Heights are surfaces: FLOOR y = 0, TABLE y = Room.TableTop (on a table), HIGH
-- y = Room.ShelfY (on a wall shelf, above head height).
--
-- Why a prop's id and place say nothing about its role: every prop is built first (candidates, partial
-- matches, fillers), then the whole list is SHUFFLED, ids are dealt in the shuffled order, and each prop takes
-- the next slot of its height band from a slot list drawn at random. The one exception is public and still
-- role-free: chapter 1 puts clue 1's candidates on the slots of their band nearest the door, so the first find
-- is in view, and it does not say which of them.

local Dressing = {}

-- The two clue rules this generator needs. Clue.luau has the same rules for the HUD; they are written twice on
-- purpose (a shared module takes no string require), and Dressing.spec checks every room against Clue's.
local function matches(p: any, clue: any, cfg: any): boolean
	for _, a in cfg.Forms[clue.form] do
		if p[a] ~= clue[a] then return false end
	end
	return true
end
local function subsumes(a: any, b: any, cfg: any): boolean
	local battrs = cfg.Forms[b.form]
	for _, x in cfg.Forms[a.form] do
		if a[x] ~= b[x] or not table.find(battrs, x) then return false end
	end
	return true
end
local Clue = {
	matches = matches,
	overlaps = function(a: any, b: any, cfg: any): boolean return subsumes(a, b, cfg) or subsumes(b, a, cfg) end,
}

--============================================================================ helpers
local function pick(rand: () -> number, n: number): number
	local v = math.floor(rand() * n) + 1
	if v > n then v = n elseif v < 1 then v = 1 end
	return v
end

local function shuffle(list: { any }, rand: () -> number)
	for i = #list, 2, -1 do
		local j = pick(rand, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function weighted(forms: { [string]: number }, rand: () -> number): string
	local names = {}
	for f in forms do table.insert(names, f) end
	table.sort(names) -- a stable order, so the same draws give the same room
	local total = 0
	for _, f in names do total += forms[f] end
	local r = rand() * total
	for _, f in names do
		r -= forms[f]
		if r < 0 then return f end
	end
	return names[#names]
end

local function randomProp(cfg: any, rand: () -> number, fixed: { [string]: string }?): any
	local T = cfg.Traits
	local p = {
		kind = T.Kinds[pick(rand, #T.Kinds)],
		colour = T.Colours[pick(rand, #T.Colours)],
		height = T.Heights[pick(rand, #T.Heights)],
	}
	if fixed then
		for k, v in fixed do p[k] = v end
	end
	return p
end

local function fixedOf(clue: any, cfg: any): { [string]: string }
	local out = {}
	for _, a in cfg.Forms[clue.form] do out[a] = clue[a] end
	return out
end

local function fitsAnyOther(p: any, clues: { any }, skip: number?, active: { [number]: boolean }?, cfg: any): boolean
	for j, c in clues do
		if j ~= skip and (active == nil or active[j]) and Clue.matches(p, c, cfg) then return true end
	end
	return false
end

--============================================================================ the spec of a room
-- kind "book" with a chapter number, or "daily" with a dayIndex.
function Dressing.spec(kind: string, which: number, cfg: any): any
	local src = if kind == "daily" then cfg.Daily else cfg.Chapters[which]
	assert(src ~= nil, "Dressing.spec: no such " .. kind .. " " .. tostring(which))
	local s = {
		kind = kind,
		chapter = if kind == "book" then which else nil,
		day = if kind == "daily" then which else nil,
		n = src.n, k = src.k, S = src.S, rho = src.rho, forms = src.forms, W = src.W, D = src.D, clock = src.clock,
		looks = src.n * src.k + cfg.Search.LooksSlack,
		nearDoorFirst = kind == "book" and which == 1,
	}
	assert(s.S >= s.n * s.k, "Dressing.spec: S smaller than n * k")
	assert(s.W <= cfg.Room.ShellW and s.D <= cfg.Room.ShellD, "Dressing.spec: room larger than the lane shell")
	return s
end

--============================================================================ clues
local function makeClues(spec: any, n: number, rand: () -> number, cfg: any): { any }?
	local T = cfg.Traits
	local domain = { kind = T.Kinds, colour = T.Colours, height = T.Heights }
	local clues = {}
	local guard = 0
	while #clues < n do
		guard += 1
		if guard > 1000 then return nil end
		local form = weighted(spec.forms, rand)
		local c = { form = form }
		for _, a in cfg.Forms[form] do
			local d = domain[a]
			c[a] = d[pick(rand, #d)]
		end
		local clash = false
		for _, o in clues do
			if Clue.overlaps(c, o, cfg) then clash = true break end
		end
		if not clash then table.insert(clues, c) end
	end
	return clues
end

--============================================================================ props: candidates, partials, fillers
-- counts[i] candidates for clue i (0 = the item needs none). Returns props (with role/clue tags) or nil.
local function makeProps(spec: any, clues: { any }, counts: { number }, active: { [number]: boolean }, rand: () -> number, cfg: any): { any }?
	local props = {}
	for ci, c in clues do
		if active[ci] then
			for _ = 1, counts[ci] do
				local ok = false
				for _try = 1, 60 do
					local p = randomProp(cfg, rand, fixedOf(c, cfg))
					if not fitsAnyOther(p, clues, ci, active, cfg) then
						p.role, p.clue = "cand", ci
						table.insert(props, p)
						ok = true
						break
					end
				end
				if not ok then return nil end
			end
		end
	end
	local nCand = #props
	local nFill = spec.S - nCand
	if nFill < 0 then return nil end
	local two = {}
	for ci, c in clues do
		if active[ci] and #cfg.Forms[c.form] == 2 then table.insert(two, c) end
	end
	for _ = 1, nFill do
		local wantPartial = #two > 0 and rand() < spec.rho
		local ok = false
		for _try = 1, 200 do
			local p, role
			if wantPartial then
				local c = two[pick(rand, #two)]
				local attrs = cfg.Forms[c.form]
				local keepIdx = pick(rand, 2)
				local keep, change = attrs[keepIdx], attrs[3 - keepIdx]
				p = randomProp(cfg, rand, { [keep] = c[keep] })
				if p[change] == c[change] then continue end
				role = "partial"
			else
				p = randomProp(cfg, rand, nil)
				role = "filler"
			end
			if not fitsAnyOther(p, clues, nil, active, cfg) then
				p.role, p.clue = role, nil
				table.insert(props, p)
				ok = true
				break
			end
		end
		if not ok then return nil end
	end
	return props
end

--============================================================================ slots: shelves, tables, floor
local function shelvesOf(spec: any, cfg: any): { any }
	local R = cfg.Room
	local W, D = spec.W, spec.D
	local out = {}
	local function addShelf(wall: string, cx: number, cz: number)
		local slots = {}
		for _, off in R.ShelfSlots do
			if wall == "N" then table.insert(slots, { x = cx + off, z = D - R.ShelfOff })
			elseif wall == "S" then table.insert(slots, { x = cx + off, z = R.ShelfOff })
			elseif wall == "E" then table.insert(slots, { x = W / 2 - R.ShelfOff, z = cz + off })
			else table.insert(slots, { x = -W / 2 + R.ShelfOff, z = cz + off }) end
		end
		table.insert(out, { wall = wall, x = cx, z = cz, slots = slots })
	end
	local x = -W / 2 + 5
	while x <= W / 2 - 5 + 1e-9 do
		addShelf("N", x, D)
		if math.abs(x) >= R.ShelfDoorClear then addShelf("S", x, 0) end
		x += R.ShelfPitch
	end
	local z = 5
	while z <= D - 6 + 1e-9 do
		addShelf("E", W / 2, z)
		addShelf("W", -W / 2, z)
		z += R.ShelfPitch
	end
	return out
end
Dressing.shelvesOf = shelvesOf

local function placeTables(spec: any, count: number, rand: () -> number, cfg: any): { any }?
	local R = cfg.Room
	local W, D = spec.W, spec.D
	local tables = {}
	local xLo, xHi = -W / 2 + R.TableSize[1] / 2 + 2, W / 2 - R.TableSize[1] / 2 - 2
	local zLo, zHi = R.DoorClear + 2, D - R.TableSize[2] / 2 - 2.5
	if xHi < xLo or zHi < zLo then return if count == 0 then tables else nil end
	local tries = 0
	while #tables < count do
		tries += 1
		if tries > 400 then return nil end
		local tx = xLo + (xHi - xLo) * rand()
		local tz = zLo + (zHi - zLo) * rand()
		if math.sqrt(tx * tx + tz * tz) < R.DoorClear + 3 then continue end
		-- the floor corners belong to decor: a table's footprint stays out of every corner square
		local ax1 = math.abs(tx) + R.TableSize[1] / 2
		local z0, z1 = tz - R.TableSize[2] / 2, tz + R.TableSize[2] / 2
		if ax1 > W / 2 - R.CornerClear - 0.5 and (z0 < R.CornerClear + 0.5 or z1 > D - R.CornerClear - 0.5) then continue end
		local ok = true
		for _, t in tables do
			if math.abs(t.x - tx) < R.TableGapX and math.abs(t.z - tz) < R.TableGapZ then ok = false break end
		end
		if ok then table.insert(tables, { x = tx, z = tz }) end
	end
	return tables
end

local function placeFloor(spec: any, count: number, tables: { any }, rand: () -> number, cfg: any): { any }?
	local R = cfg.Room
	local W, D = spec.W, spec.D
	local pts = {}
	local hw, hd = R.TableSize[1] / 2 + R.TableClear, R.TableSize[2] / 2 + R.TableClear
	local tries = 0
	while #pts < count do
		tries += 1
		if tries > 20000 then return nil end
		local px = -W / 2 + R.Margin + (W - 2 * R.Margin) * rand()
		local pz = R.Margin + (D - 2 * R.Margin) * rand()
		if math.sqrt(px * px + pz * pz) < R.DoorClear then continue end
		local cc = R.CornerClear + 1
		if math.abs(px) > W / 2 - cc and (pz < cc or pz > D - cc) then continue end
		local ok = true
		for _, t in tables do
			if math.abs(px - t.x) <= hw and math.abs(pz - t.z) <= hd then ok = false break end
		end
		if ok then
			for _, q in pts do
				if (q.x - px) ^ 2 + (q.z - pz) ^ 2 < R.Spacing * R.Spacing then ok = false break end
			end
		end
		if ok then table.insert(pts, { x = px, z = pz }) end
	end
	return pts
end

local function yawFor(wall: string?): number
	if wall == "N" then return 180 end
	if wall == "S" then return 0 end
	if wall == "E" then return 270 end
	if wall == "W" then return 90 end
	return 0
end

-- Positions for every prop, by height band. Returns (tables, usedShelves) or nil when the room cannot hold them.
local function layout(spec: any, props: { any }, nearDoorClue: number?, rand: () -> number, cfg: any): (any, any)
	local R = cfg.Room
	local byBand = { floor = {}, table = {}, high = {} }
	for _, p in props do table.insert(byBand[p.height], p) end
	-- HIGH: whole shelves, packed, in a random order
	local shelves = shelvesOf(spec, cfg)
	local needShelves = math.ceil(#byBand.high / #R.ShelfSlots)
	if needShelves > #shelves then return nil, nil end
	shuffle(shelves, rand)
	local used = {}
	local highSlots = {}
	for i = 1, needShelves do
		local sh = shelves[i]
		table.insert(used, { wall = sh.wall, x = sh.x, z = sh.z })
		for _, s in sh.slots do table.insert(highSlots, { x = s.x, z = s.z, y = R.ShelfY, wall = sh.wall }) end
	end
	-- TABLE: 3 slots a table
	local needTables = math.ceil(#byBand.table / #R.TableSlots)
	local tables = placeTables(spec, needTables, rand, cfg)
	if tables == nil then return nil, nil end
	local tableSlots = {}
	for _, t in tables do
		for _, off in R.TableSlots do table.insert(tableSlots, { x = t.x + off, z = t.z, y = R.TableTop }) end
	end
	-- FLOOR: points
	local floorPts = placeFloor(spec, #byBand.floor, tables, rand, cfg)
	if floorPts == nil then return nil, nil end
	local floorSlots = {}
	for _, p in floorPts do table.insert(floorSlots, { x = p.x, z = p.z, y = 0 }) end
	local slots = { floor = floorSlots, table = tableSlots, high = highSlots }
	for _, list in slots do shuffle(list, rand) end
	-- chapter 1: clue 1's candidates take the slots of their band nearest the door
	if nearDoorClue then
		for band, list in slots do
			table.sort(list, function(a, b)
				return a.x * a.x + a.z * a.z < b.x * b.x + b.z * b.z
			end)
			local first, rest = {}, {}
			for _, p in byBand[band] do
				if p.role == "cand" and p.clue == nearDoorClue then table.insert(first, p) else table.insert(rest, p) end
			end
			local remaining = {}
			for i = #first + 1, #list do table.insert(remaining, list[i]) end
			shuffle(remaining, rand)
			for i = 1, #first do first[i].slot = list[i] end
			for i, p in rest do p.slot = remaining[i] end
		end
	else
		local cursor = { floor = 0, table = 0, high = 0 }
		for _, p in props do
			cursor[p.height] += 1
			p.slot = slots[p.height][cursor[p.height]]
		end
	end
	return tables, used
end

--============================================================================ build
local function finish(spec: any, clues: { any }, props: { any }, tables: { any }, shelves: { any }, idBase: number, rand: () -> number, cfg: any): any
	local room = {
		spec = spec, clues = clues, idBase = idBase, props = {}, tables = tables, shelves = shelves,
		cands = {}, role = {}, clueOf = {},
	}
	for ci = 1, #clues do room.cands[ci] = {} end
	for i, p in props do
		local id = idBase + i
		local s = p.slot
		local yaw = if p.height == "high" then yawFor(s.wall) else 15 * (pick(rand, 24) - 1)
		room.props[i] = {
			id = id, kind = p.kind, colour = p.colour, height = p.height,
			x = s.x, y = s.y, z = s.z, yaw = yaw, variant = pick(rand, 3),
		}
		room.role[id] = p.role
		if p.role == "cand" then
			room.clueOf[id] = p.clue
			table.insert(room.cands[p.clue], id)
		end
	end
	return room
end

-- (room, attempts). Retries the whole room when a step cannot be satisfied (measured: rare, Dressing.spec).
function Dressing.build(spec: any, rand: () -> number, cfg: any): (any, number)
	local counts = {}
	local active = {}
	for i = 1, spec.n do
		counts[i] = spec.k
		active[i] = true
	end
	for attempt = 1, cfg.Room.Attempts do
		local clues = makeClues(spec, spec.n, rand, cfg)
		if clues == nil then continue end
		local props = makeProps(spec, clues, counts, active, rand, cfg)
		if props == nil then continue end
		shuffle(props, rand)
		local tables, shelves = layout(spec, props, if spec.nearDoorFirst then 1 else nil, rand, cfg)
		if tables == nil then continue end
		return finish(spec, clues, props, tables, shelves, 0, rand, cfg), attempt
	end
	error("Dressing.build: no room after " .. cfg.Room.Attempts .. " attempts")
end

-- The re-dress on resume [DESIGN §9]: every prop moves, every item i with counts[i] > 0 gets a fresh clue that
-- fits EXACTLY counts[i] props, found items (count 0) keep their old clue for the list and need no candidate.
-- New ids continue after the old room's, so a stale id from before the pause can never be searched.
function Dressing.redress(old: any, counts: { number }, rand: () -> number, cfg: any): any
	local spec = old.spec
	local active = {}
	local nActive = 0
	for i = 1, spec.n do
		active[i] = (counts[i] or 0) > 0
		if active[i] then nActive += 1 end
	end
	local idBase = old.idBase + #old.props
	for _attempt = 1, cfg.Room.Attempts do
		local fresh = makeClues(spec, nActive, rand, cfg)
		if fresh == nil then continue end
		local clues = {}
		local j = 0
		for i = 1, spec.n do
			if active[i] then
				j += 1
				clues[i] = fresh[j]
			else
				clues[i] = old.clues[i]
			end
		end
		local props = makeProps(spec, clues, counts, active, rand, cfg)
		if props == nil then continue end
		shuffle(props, rand)
		local tables, shelves = layout(spec, props, nil, rand, cfg)
		if tables == nil then continue end
		return finish(spec, clues, props, tables, shelves, idBase, rand, cfg)
	end
	error("Dressing.redress: no room after " .. cfg.Room.Attempts .. " attempts")
end

--============================================================================ the payload (an allowlist)
-- What the owner's client receives to build the room. Built from public fields only, BEFORE the secret is drawn.
-- items[i] is the (cosmetic) item hidden for clue i; found[i] marks items already found (after a re-dress).
function Dressing.payload(room: any, items: { string }, band: number, cfg: any, found: { [number]: boolean }?): any
	local spec = room.spec
	local props = {}
	for i, p in room.props do
		props[i] = { id = p.id, kind = p.kind, colour = p.colour, height = p.height, x = p.x, y = p.y, z = p.z, yaw = p.yaw, variant = p.variant }
	end
	local clues = {}
	for i, c in room.clues do
		local out = { form = c.form, item = items[i], found = if found and found[i] then true else nil }
		for _, a in cfg.Forms[c.form] do out[a] = c[a] end
		clues[i] = out
	end
	local tables, shelves = {}, {}
	for i, t in room.tables do tables[i] = { x = t.x, z = t.z } end
	for i, s in room.shelves do shelves[i] = { x = s.x, z = s.z, wall = s.wall } end
	return {
		v = 1, kind = spec.kind, chapter = spec.chapter, day = spec.day, band = band, W = spec.W, D = spec.D,
		idBase = room.idBase, props = props, clues = clues, tables = tables, shelves = shelves,
		looks = spec.looks, clock = spec.clock,
	}
end

return Dressing
