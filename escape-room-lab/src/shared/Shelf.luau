--!strict
-- Shelf.luau — the Flask Shelf feeder: N flasks, a MINIMAL set of true clue sentences, one answer.
-- Pure; no Roblox. Randomness is injected as `rand(): number in [0, 1)`.
--
-- Colours are indices into Text.FlaskNames (1 Red .. 5 Purple). An ORDER is an array order[slot] =
-- colour. A clue is { t, a, b?, k? } over colours. Rules (tests/Shelf.spec.luau pins each):
--   * exactly one order of the shelf's colours fits all clues, and every clue is necessary;
--   * the start order is a random arrangement that is never the answer;
--   * at most `maxClues` clues (the overlay's list stays one short scroll, DESIGN.md §3.4).
-- `solve` works from colours and clues only, which is what a player sees.

local Shelf = {}

Shelf.Types = { "left", "adj", "notadj", "notslot", "atend", "notend" }

type Order = { number }

local function below(rand: () -> number, n: number): number
	local v = math.floor(rand() * n) + 1
	if v > n then v = n end
	if v < 1 then v = 1 end
	return v
end

local function shuffle(rand: () -> number, t: { any }): { any }
	for i = #t, 2, -1 do
		local j = below(rand, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local permCache: { [number]: { Order } } = {}

-- Every order of the local indices 1..N (order[slot] = index), cached per N. Do not mutate.
function Shelf.perms(N: number): { Order }
	local cached = permCache[N]
	if cached then return cached end
	local out: { Order } = {}
	local cur: Order = {}
	local used: { [number]: boolean } = {}
	local function rec(pos: number)
		if pos > N then
			table.insert(out, table.clone(cur))
			return
		end
		for c = 1, N do
			if not used[c] then
				used[c] = true
				cur[pos] = c
				rec(pos + 1)
				used[c] = false
			end
		end
	end
	rec(1)
	permCache[N] = out
	return out
end

-- pos[colour] = slot, for an order
function Shelf.posOf(order: Order): { [number]: number }
	local pos = {}
	for slot, c in order do pos[c] = slot end
	return pos
end

function Shelf.holds(clue: any, pos: { [number]: number }, N: number): boolean
	local t = clue.t
	local pa = pos[clue.a]
	if pa == nil then return false end
	if t == "left" then return pos[clue.b] ~= nil and pa < pos[clue.b] end
	if t == "adj" then return pos[clue.b] ~= nil and math.abs(pa - pos[clue.b]) == 1 end
	if t == "notadj" then return pos[clue.b] ~= nil and math.abs(pa - pos[clue.b]) > 1 end
	if t == "notslot" then return pa ~= clue.k end
	if t == "atend" then return pa == 1 or pa == N end
	if t == "notend" then return pa ~= 1 and pa ~= N end
	return false
end

function Shelf.fits(order: Order, clues: { any }): boolean
	local pos = Shelf.posOf(order)
	for _, cl in clues do
		if not Shelf.holds(cl, pos, #order) then return false end
	end
	return true
end

-- Every arrangement of `colors` that fits the clues.
function Shelf.solve(colors: { number }, clues: { any }): { Order }
	local N = #colors
	local out: { Order } = {}
	for _, p in Shelf.perms(N) do
		local order = {}
		for slot, i in p do order[slot] = colors[i] end
		if Shelf.fits(order, clues) then table.insert(out, order) end
	end
	return out
end

function Shelf.same(x: Order, y: Order): boolean
	if #x ~= #y then return false end
	for i = 1, #x do
		if x[i] ~= y[i] then return false end
	end
	return true
end

-- Is `order` a plain array holding each of `colors` exactly once?
function Shelf.isArrangement(order: any, colors: { number }): boolean
	if type(order) ~= "table" or #order ~= #colors then return false end
	local want: { [number]: boolean } = {}
	for _, c in colors do want[c] = true end
	local seen: { [number]: boolean } = {}
	for i = 1, #order do
		local c = order[i]
		if not want[c] or seen[c] then return false end
		seen[c] = true
	end
	return true
end

function Shelf.swap(order: Order, i: number, j: number)
	order[i], order[j] = order[j], order[i]
end

-- One attempt over the local indices 1..N; returns (secret order, clues) or nil.
local function attempt(N: number, rand: () -> number, maxDraws: number): (Order?, { any }?)
	local perms = Shelf.perms(N)
	local posOf = {}
	for i, p in perms do posOf[i] = Shelf.posOf(p) end
	local si = below(rand, #perms)
	local secretPos = posOf[si]
	local cands = posOf
	local clues = {}
	local draws = 0
	while #cands > 1 and draws < maxDraws do
		draws += 1
		local t = Shelf.Types[below(rand, #Shelf.Types)]
		local a = below(rand, N)
		local b = below(rand, N - 1)
		if b >= a then b += 1 end
		local clue = { t = t, a = a, b = b, k = below(rand, N) }
		if Shelf.holds(clue, secretPos, N) then
			local nextC = {}
			for _, p in cands do
				if Shelf.holds(clue, p, N) then table.insert(nextC, p) end
			end
			if #nextC < #cands then
				table.insert(clues, clue)
				cands = nextC
			end
		end
	end
	if #cands ~= 1 then return nil, nil end
	local order = {}
	for i = 1, #clues do order[i] = i end
	shuffle(rand, order)
	local keep = {}
	for i = 1, #clues do keep[i] = true end
	for _, i in order do
		keep[i] = false
		local trial = {}
		for j = 1, #clues do
			if keep[j] then table.insert(trial, clues[j]) end
		end
		local n = 0
		for _, p in posOf do
			local ok = true
			for _, cl in trial do
				if not Shelf.holds(cl, p, N) then
					ok = false
					break
				end
			end
			if ok then
				n += 1
				if n >= 2 then break end
			end
		end
		if n ~= 1 then keep[i] = true end
	end
	local out = {}
	for j = 1, #clues do
		if keep[j] then table.insert(out, clues[j]) end
	end
	shuffle(rand, out)
	return table.clone(perms[si]), out
end

-- spec = { N, maxClues, maxGenerations? (50) } -> { colors, secret, clues, start, generations } or nil.
-- colors: the N palette colours on this shelf, in a random order; secret/start: orders of those colours.
function Shelf.generate(spec: any, rand: () -> number): any
	local N = spec.N
	local maxGen = spec.maxGenerations or 50
	for gen = 1, maxGen do
		local secretLocal, clues = nil, nil
		for _ = 0, 20 do
			secretLocal, clues = attempt(N, rand, 400)
			if secretLocal then break end
		end
		if secretLocal and clues and #clues <= spec.maxClues then
			local palette = shuffle(rand, { 1, 2, 3, 4, 5 })
			local colors = {}
			for i = 1, N do colors[i] = palette[i] end
			local secret = {}
			for slot, i in secretLocal do secret[slot] = colors[i] end
			local mapped = {}
			for _, cl in clues do
				local c: any = { t = cl.t, a = colors[cl.a] }
				if cl.t == "left" or cl.t == "adj" or cl.t == "notadj" then c.b = colors[cl.b] end
				if cl.t == "notslot" then c.k = cl.k end
				table.insert(mapped, c)
			end
			local start
			repeat
				start = shuffle(rand, table.clone(colors))
			until not Shelf.same(start, secret)
			return { colors = colors, secret = secret, clues = mapped, start = start, generations = gen }
		end
	end
	return nil
end

function Shelf.hintCap(N: number): number
	return math.max(1, N - 2)
end

-- (colour, slot) of a flask the player has not been told; nil once N - 2 are told.
function Shelf.hint(secret: Order, told: { [number]: boolean }, rand: () -> number): (number?, number?)
	local n = 0
	for _ in told do n += 1 end
	if n >= Shelf.hintCap(#secret) then return nil, nil end
	local open = {}
	for slot, c in secret do
		if not told[c] then table.insert(open, slot) end
	end
	if #open == 0 then return nil, nil end
	local slot = open[below(rand, #open)]
	return secret[slot], slot
end

return Shelf
