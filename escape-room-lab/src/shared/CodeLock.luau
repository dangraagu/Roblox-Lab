--!strict
-- CodeLock.luau — the exit door: a code of L DISTINCT digits and a MINIMAL set of clue lines.
-- Pure; no Roblox. Randomness is injected as `rand(): number in [0, 1)`; the server passes a closure
-- over a fresh per-room `Random.new()` (DESIGN.md §14.1: there is no seed), tests pass the repo's LCG.
--
-- Rules (tests/CodeLock.spec.luau pins each, over thousands of generated doors):
--   * exactly one code fits all the lines, and every line is necessary;
--   * f lines are HIDDEN (one per feeder station), and the visible lines alone fit two or more codes,
--     so the door cannot be read before its feeders are solved, even by perfect logic;
--   * at least one line is visible at the start (m >= f + 1), at most `maxLines` in all.
-- `solve` works from lines only: it is the rules, which any player can also write down, and it is how
-- the headless walk plays from what is rendered. The secret never leaves the server's memory.

local CodeLock = {}

type Code = { number }
type Line = { guess: Code, a: number, b: number }

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

local spaces: { [string]: { Code } } = {}

-- Every code of L distinct digits from `alphabet`, built once per (L, alphabet) and cached. Callers
-- must not mutate the entries: everything handed OUT of this module is a copy.
function CodeLock.space(L: number, alphabet: { number }): { Code }
	local key = tostring(L) .. ":" .. table.concat(alphabet, ",")
	local cached = spaces[key]
	if cached then return cached end
	local out: { Code } = {}
	local cur: Code = {}
	local used: { [number]: boolean } = {}
	local function rec(pos: number)
		if pos > L then
			table.insert(out, table.clone(cur))
			return
		end
		for _, d in alphabet do
			if not used[d] then
				used[d] = true
				cur[pos] = d
				rec(pos + 1)
				used[d] = false
			end
		end
	end
	rec(1)
	spaces[key] = out
	return out
end

-- (A, B): A digits right and in place, B right but in the wrong place.
function CodeLock.feedback(guess: Code, code: Code): (number, number)
	local a, common = 0, 0
	local L = #guess
	for i = 1, L do
		local g = guess[i]
		if g == code[i] then a += 1 end
		for j = 1, L do
			if g == code[j] then
				common += 1
				break
			end
		end
	end
	return a, common - a
end

function CodeLock.equal(x: Code, y: Code): boolean
	if #x ~= #y then return false end
	for i = 1, #x do
		if x[i] ~= y[i] then return false end
	end
	return true
end

function CodeLock.fits(code: Code, lines: { Line }): boolean
	for _, ln in lines do
		local a, b = CodeLock.feedback(ln.guess, code)
		if a ~= ln.a or b ~= ln.b then return false end
	end
	return true
end

-- How many codes fit every line; stops counting at `cap` when given.
function CodeLock.count(lines: { Line }, L: number, alphabet: { number }, cap: number?): number
	local n = 0
	for _, code in CodeLock.space(L, alphabet) do
		if CodeLock.fits(code, lines) then
			n += 1
			if cap and n >= cap then return n end
		end
	end
	return n
end

-- Every code that fits the lines (copies).
function CodeLock.solve(lines: { Line }, L: number, alphabet: { number }): { Code }
	local out: { Code } = {}
	for _, code in CodeLock.space(L, alphabet) do
		if CodeLock.fits(code, lines) then table.insert(out, table.clone(code)) end
	end
	return out
end

-- Is `code` something the keypad could legally send: a plain array of exactly L distinct integers
-- from the alphabet, and nothing else? The server's Act handler drops anything that is not.
function CodeLock.valid(code: any, L: number, alphabet: { number }): boolean
	if type(code) ~= "table" then return false end
	local keys = 0
	for _ in code do keys += 1 end
	if keys ~= L or #code ~= L then return false end
	local allowed: { [number]: boolean } = {}
	for _, d in alphabet do allowed[d] = true end
	local seen: { [number]: boolean } = {}
	for i = 1, L do
		local d = code[i]
		if type(d) ~= "number" or d ~= d or math.floor(d) ~= d then return false end
		if not allowed[d] or seen[d] then return false end
		seen[d] = true
	end
	return true
end

-- One attempt: draw the secret, add random lines that each remove a candidate until one code is
-- left, then drop lines (in random order) while the code stays unique. Returns nil when the draw
-- budget runs out before one code is left.
local function attempt(space: { Code }, rand: () -> number, maxDraws: number): (Code?, { Line }?)
	local secret = space[below(rand, #space)]
	local cands = space
	local lines: { Line } = {}
	local draws = 0
	while #cands > 1 and draws < maxDraws do
		draws += 1
		local guess = space[below(rand, #space)]
		if guess ~= secret then
			local a, b = CodeLock.feedback(guess, secret)
			local nextC = {}
			for _, c in cands do
				local ca, cb = CodeLock.feedback(guess, c)
				if ca == a and cb == b then table.insert(nextC, c) end
			end
			if #nextC < #cands then
				table.insert(lines, { guess = guess, a = a, b = b })
				cands = nextC
			end
		end
	end
	if #cands ~= 1 then return nil, nil end
	local order = {}
	for i = 1, #lines do order[i] = i end
	shuffle(rand, order)
	local keep: { boolean } = {}
	for i = 1, #lines do keep[i] = true end
	for _, i in order do
		keep[i] = false
		local trial = {}
		for j = 1, #lines do
			if keep[j] then table.insert(trial, lines[j]) end
		end
		local n = 0
		for _, code in space do
			if CodeLock.fits(code, trial) then
				n += 1
				if n >= 2 then break end
			end
		end
		if n ~= 1 then keep[i] = true end
	end
	local out: { Line } = {}
	for j = 1, #lines do
		if keep[j] then
			table.insert(out, { guess = table.clone(lines[j].guess), a = lines[j].a, b = lines[j].b })
		end
	end
	shuffle(rand, out)
	return table.clone(secret), out
end

-- spec = { L, alphabet, feeders, maxLines, minLines? (default feeders + 1), maxGenerations? (50) }
-- -> { secret, lines, hidden = { line indices, one per feeder }, generations } or nil.
function CodeLock.generate(spec: any, rand: () -> number): any
	local space = CodeLock.space(spec.L, spec.alphabet)
	local f = spec.feeders or 0
	local minLines = spec.minLines or (f + 1)
	local maxGen = spec.maxGenerations or 50
	for gen = 1, maxGen do
		local secret, lines = nil, nil
		for _ = 0, 20 do
			secret, lines = attempt(space, rand, 200)
			if secret then break end
		end
		if secret and lines and #lines >= minLines and #lines <= spec.maxLines then
			local idx = {}
			for i = 1, #lines do idx[i] = i end
			shuffle(rand, idx)
			local hidden = {}
			for i = 1, f do hidden[i] = idx[i] end
			table.sort(hidden)
			return { secret = secret, lines = lines, hidden = hidden, generations = gen }
		end
	end
	return nil
end

function CodeLock.hintCap(L: number): number
	return L - 1
end

-- A position the player has not been told, and its digit; nil once L - 1 are told.
function CodeLock.hint(secret: Code, told: { [number]: boolean }, rand: () -> number): (number?, number?)
	local n = 0
	local open = {}
	for i = 1, #secret do
		if told[i] then n += 1 else table.insert(open, i) end
	end
	if n >= CodeLock.hintCap(#secret) or #open == 0 then return nil, nil end
	local pos = open[below(rand, #open)]
	return pos, secret[pos]
end

return CodeLock
