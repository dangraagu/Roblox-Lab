-- Fork.luau — Fork Tower's whole game, as a PURE function.
--
-- Given a config, a run seed and a floor number: which of the two doors is the trap, what is
-- behind each of them, what signs do they carry, and what does the inscription say? Nothing here
-- touches a Roblox global, a service, or an engine datatype — it returns plain tables and the
-- server turns them into doors. That is what lets the fairness spec measure forty thousand forks
-- in the luau CLI with no engine present.
--
-- Dependencies are ARGUMENTS, never a relative require: a bare require("./Rng") resolves in the
-- luau CLI and is INVALID in Roblox, so `plan` takes the Rng module the caller already has.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THE TWO PROMISES, and how the code keeps them
--
-- 1. NO FLOOR IS UNWINNABLE. Both doors always grant their trait. Exactly one of them is the
--    trap, and being trapped means the section behind it is LONGER and busier — never a higher
--    step, never a lost trait, never a closed route. The geometry half of that promise lives in
--    Section.luau; this module's half is that a trap is a toll and not a wall.
--
-- 2. NO RUN IS A COIN FLIP. Every fork is readable to certainty. The fork platform carries an
--    inscription naming ONE sign; exactly one door bears that sign; and the inscription states
--    outright whether the sign marks the trap or (from Config.Fork.LiarFromFloor) the safe door.
--    Read it and you never eat a trap. Ignore it and you eat one half the time.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THREE THINGS THAT ARE EASY TO GET WRONG HERE, all of them found by the spec
--
-- a) DON'T SEED A FRESH LCG PER FLOOR. The first draft did `Rng.new(World*a + level*b)` and took
--    the first draw. Consecutive seeds differ by a constant, so an LCG's first output moves by a
--    constant too, and the trap side marched in a short repeating cycle — identical for every
--    player, on every seed. Both the 50/50 check and the streak check passed, because a cycle is
--    regular rather than streaky; only a transition table sees it. So every stream below is
--    seeded ONCE per run and consumed floor by floor.
--
-- b) THE SIGN SETS MUST BE EXCHANGEABLE. Both doors carry exactly SignsPerDoor signs, and the
--    pair of sets is drawn as an ordered pair of DISTINCT subsets, uniformly, before anything
--    knows which door is trapped. So no arrangement of signs — no count, no particular sign, no
--    combination — predicts the trap. The inscription is the only thing that resolves it. The
--    first draft built the marked door's set around the tell and the other door's from the
--    leftovers, which made a lone non-tell sign land on the safe door four times out of five.
--
-- c) THE PRIZE MUST NOT CORRELATE WITH THE TRAP. Traits are drawn from their own stream and
--    slotted by their own coin. If the trap door reliably held the better trait, "always take
--    the boring one" would solve the game without a single sign being read.

local Fork = {}

--============================================================================ seeding

-- Every intermediate stays far below 2^53: WorldSeed(~2e7) * 7919 ~ 1.6e11, the reduced run seed
-- (< 2^20) * 6151 ~ 6.4e9, the salt term ~1e10. Overflowing 2^53 silently zeroes the low bits and
-- collapses whole families of seeds onto one sequence.
local SEED_MIX = 7919
local RUN_MIX = 6151
local LEVEL_MIX = 3571
local RUN_SPAN = 1048576 -- 2^20; runSeed is a rebirth counter, not an identity

-- One salt per stream. Adding or removing a stream later must not shift another one's numbers.
local SALT = { side = 1, trait = 2, sign = 3, liar = 4 }
local SALT_MIX = 2654435761 -- Knuth's 32-bit golden ratio, odd

--============================================================================ the seed mixer
--
-- THIS IS THE PART THAT TOOK THREE RED RUNS TO GET RIGHT, so it is worth spelling out.
--
-- An LCG's output IS its state over 2^32, and two LCGs sharing a multiplier are never
-- independent: seed them at s and s+d and every later pair satisfies y_n - x_n = A^n*d, exactly.
-- Feed such a generator a seed that is an AFFINE function of (runSeed, level, salt) — which is
-- what the sibling games do, and what the first two drafts here did — and the whole tower becomes
-- one affine lattice. Two symptoms, both found by Fork.spec and neither visible to a 50/50 check:
--
--   * per-floor seeds `base + level*3571`: the first draw moves by a constant each floor, so the
--     trap side and the tell marched in a short repeating cycle, the same cycle for every player;
--   * per-stream seeds `base + salt` (41/43/47/53): four streams six apart are, for their first
--     several draws, the SAME sequence. The trap side and the sign draw were correlated, and one
--     arrangement of signs predicted the trap 57% of the time. Multiplying the salt out to a big
--     offset and burning six steps only cut that to 56%: the lattice is still a lattice.
--
-- The fix is to stop deriving seeds linearly. Every stream is seeded with an avalanche hash
-- (MurmurHash3's 32-bit finalizer) of its (run, level, salt) triple, so seeds one apart in any
-- input land nowhere near each other and the residual A^n*d relation between two streams carries
-- a different, unpredictable d on every floor of every run.
--
-- `bit32` exists both in Roblox and in the luau CLI, which is why it can be used here at all.

local UINT32 = 4294967296

-- 32x32 -> the low 32 bits, in halves, so no intermediate passes 2^53 and loses its low bits.
local function mul32(a: number, b: number): number
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % UINT32
end

local function mix32(x: number): number
	x = math.floor(x) % UINT32
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 2246822507) -- 0x85EBCA6B
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = mul32(x, 3266489909) -- 0xC2B2AE35
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

-- One stream per (floor, purpose). Fresh per floor is safe HERE, and only here, because the seed
-- is hashed rather than offset — the objection to per-floor seeding is the linear derivation, not
-- the freshness.
local function stream(cfg, runSeed: number, level: number, salt: number, Rng)
	local s = math.floor(runSeed)
	if s < 0 then s = -s end
	local raw = cfg.WorldSeed * SEED_MIX + (s % RUN_SPAN) * RUN_MIX + level * LEVEL_MIX + salt * SALT_MIX
	return Rng.new(mix32(raw))
end

--============================================================================ helpers

-- All size-k subsets of `list`, in a fixed order. With four signs and two per door that is six
-- subsets and thirty ordered distinct pairs — the entire space a player can be shown.
local function combinations(list, k)
	local out = {}
	local n = #list
	local idx = {}
	local function rec(start, depth)
		if depth > k then
			local combo = {}
			for i = 1, k do combo[i] = list[idx[i]] end
			out[#out + 1] = combo
			return
		end
		for i = start, n - (k - depth) do
			idx[depth] = i
			rec(i + 1, depth + 1)
		end
	end
	rec(1, 1)
	return out
end

local function setOf(list)
	local s = {}
	for _, v in ipairs(list) do s[v] = true end
	return s
end

--============================================================================ the trap sequence

-- The side the trap sits on, for every floor of the run: a plain fair coin, floor by floor,
-- from one stream.
--
-- It is deliberately NOT anti-streaked. The first draft capped identical sides at three in a row
-- because long streaks make a fair generator feel rigged — and the cap is itself a tell. After
-- three left-traps you know the fourth is on the right, for free, without reading anything, and
-- that is precisely the property this game promises not to have. Fork.spec measures it as a
-- lopsided transition table over three-floor histories. A streak of six is allowed to happen and
-- costs a reader nothing; a cap would have handed every player one free floor in eight.
local function trapSide(cfg, runSeed, level, Rng): number
	return if stream(cfg, runSeed, level, SALT.side, Rng):next() < 0.5 then 1 else 2
end

--============================================================================ the plan

-- Fork.plan(cfg, runSeed, Rng) -> { runSeed, floors = { Floor, ... } }
--
-- Floor = {
--   level, trapDoor (1|2), markedDoor (1|2), tellKind (string), ruleInverted (boolean),
--   ruleText (string), ruleSign (string, the emoji for tellKind),
--   doors = { { slot, traitId, theme, label, signs = {kind,...}, signSet = {kind=true} }, ... },
-- }
function Fork.plan(cfg, runSeed, Rng)
	local floors = cfg.Tower.Floors
	local subsets = combinations(cfg.Fork.Signs, cfg.Fork.SignsPerDoor)
	local nSubsets = #subsets
	assert(nSubsets >= 2, "Fork: need at least two possible sign sets per door")

	local out = {}
	for level = 1, floors do
		local traitRng = stream(cfg, runSeed, level, SALT.trait, Rng)
		local signRng = stream(cfg, runSeed, level, SALT.sign, Rng)
		local liarRng = stream(cfg, runSeed, level, SALT.liar, Rng)

		local trapDoor = trapSide(cfg, runSeed, level, Rng)

		-- The liar line. Gated so the first floors teach the vocabulary before the tower starts
		-- using it against the player. Drawn regardless of the gate so that raising or lowering
		-- LiarFromFloor does not reshuffle everything above it.
		local liarDraw = liarRng:next()
		local ruleInverted = (level >= cfg.Fork.LiarFromFloor) and (liarDraw < cfg.Fork.LiarChance)
		local markedDoor = if ruleInverted then 3 - trapDoor else trapDoor

		------------------------------------------------------------------ traits
		-- Two different traits with two different THEMES, so the two sections behind the doors
		-- never look alike and the choice reads as a choice.
		local a = traitRng:below(#cfg.Traits)
		local themeA = cfg.Traits[a].theme
		local candidates = {}
		for i, t in ipairs(cfg.Traits) do
			if t.theme ~= themeA then candidates[#candidates + 1] = i end
		end
		assert(#candidates > 0, "Fork: Config.Traits needs at least two themes")
		local b = candidates[traitRng:below(#candidates)]
		-- Which one is on the left is its own coin, from the trait stream — never from the side
		-- stream, or the prize would follow the trap.
		if traitRng:next() < 0.5 then
			a, b = b, a
		end

		------------------------------------------------------------------ signs
		-- An ordered pair of DISTINCT subsets, uniform over all n*(n-1) of them. Distinct because
		-- identical sets would leave the inscription with nothing to point at; ordered and drawn
		-- before the trap is consulted, so the arrangement itself says nothing.
		local i = signRng:below(nSubsets)
		local j = signRng:below(nSubsets - 1)
		if j >= i then j += 1 end
		local setLeft, setRight = subsets[i], subsets[j]

		local sets = { setLeft, setRight }
		local signSets = { setOf(setLeft), setOf(setRight) }

		-- The tell is one of the signs the MARKED door has and the other door does not. Both
		-- doors hold the same number of signs, so each has the same number of exclusives and this
		-- list is never empty.
		local exclusive = {}
		for _, k in ipairs(sets[markedDoor]) do
			if not signSets[3 - markedDoor][k] then exclusive[#exclusive + 1] = k end
		end
		assert(#exclusive > 0, "Fork: the marked door must hold a sign the other one does not")
		local tellKind = exclusive[signRng:below(#exclusive)]

		------------------------------------------------------------------ assemble
		local doors = {}
		for slot = 1, 2 do
			local trait = cfg.Traits[if slot == 1 then a else b]
			local signs = {}
			for n, k in ipairs(sets[slot]) do signs[n] = k end
			doors[slot] = {
				slot = slot,
				traitId = trait.id,
				theme = trait.theme,
				label = trait.label,
				signs = signs,
				signSet = setOf(signs),
			}
		end

		local name = cfg.Fork.SignNames[tellKind] or string.upper(tellKind)
		local ruleText
		if ruleInverted then
			ruleText = "VOKTEREN LYVER — " .. name .. " MERKER DEN TRYGGE DØRA"
		else
			ruleText = "STOL PÅ " .. name .. " — DEN MERKER FELLA"
		end

		out[level] = {
			level = level,
			trapDoor = trapDoor,
			markedDoor = markedDoor,
			tellKind = tellKind,
			ruleInverted = ruleInverted,
			ruleText = ruleText,
			ruleSign = (cfg.Fork.SignEmoji and cfg.Fork.SignEmoji[tellKind]) or "",
			doors = doors,
		}
	end

	return { runSeed = runSeed, floors = out }
end

-- One floor. The plan is rebuilt each call (ten floors of arithmetic), which keeps the module
-- stateless — no cache to invalidate when a player rebirths into a new seed.
function Fork.floor(cfg, runSeed, level, Rng)
	local plan = Fork.plan(cfg, runSeed, Rng)
	return plan.floors[level]
end

-- Apply the inscription honestly: what a player who reads the fork platform concludes. Takes
-- nothing hidden — markedDoor is which door visibly bears the tell, ruleInverted is what the
-- inscription says about itself — so exposing it to the client leaks nothing that is not
-- already carved on the doors.
function Fork.readTrap(floor): number
	if floor.ruleInverted then
		return 3 - floor.markedDoor
	end
	return floor.markedDoor
end

function Fork.isTrap(floor, slot): boolean
	return floor.trapDoor == slot
end

-- The door a player walked through, resolved to what the server has to build.
function Fork.outcome(floor, slot)
	local door = floor.doors[slot]
	return {
		slot = slot,
		traitId = door.traitId,
		theme = door.theme,
		trapped = floor.trapDoor == slot,
	}
end

return Fork
