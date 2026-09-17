--!strict
-- Economy.luau - prices, jars, cages, heat, permits, bounties and the saved profile's shape.
--
-- Pure: cfg in, numbers and plain tables out. No Roblox global, no clock of its own (callers
-- pass os.time() in), and it requires NOTHING - a bare `require("./X")` resolves in the luau CLI
-- and is INVALID in Roblox.
--
-- Two rules this file exists to keep true (DESIGN.md sections 4 and 8):
--   * a price is rate x payback, so no species can be priced out of line with its own income;
--   * the saved profile has NO integer keys anywhere (JSON round-trips sparse integer keys to
--     strings): `cages` is always nine dense entries, heat is t1..t4, the lists are dense.

local Economy = {}

local function speciesById(cfg: any): { [string]: any }
	local cache = cfg.__speciesById
	if cache then return cache end
	cache = {}
	for _, s in cfg.Species do
		cache[s.id] = s
	end
	-- cached on the config table itself: Config is a module singleton, and a spec that builds a
	-- shadow config gets its own cache
	cfg.__speciesById = cache
	return cache
end

function Economy.species(cfg: any, id: any): any
	if type(id) ~= "string" then return nil end
	return speciesById(cfg)[id]
end

function Economy.tierOf(cfg: any, id: any): number?
	local s = Economy.species(cfg, id)
	return s and s.tier or nil
end

function Economy.price(cfg: any, id: any): number?
	local s = Economy.species(cfg, id)
	if not s then return nil end
	return s.rate * cfg.Economy.Payback[s.tier]
end

function Economy.rate(cfg: any, id: any): number
	local s = Economy.species(cfg, id)
	return s and s.rate or 0
end

function Economy.speciesOfTier(cfg: any, tier: number): { string }
	local out = {}
	for _, s in cfg.Species do
		if s.tier == tier then table.insert(out, s.id) end
	end
	return out
end

--============================================================================ jars

function Economy.jarCap(cfg: any, id: any): number
	return Economy.rate(cfg, id) * cfg.Economy.JarHours * 3600
end

-- `seconds` of income into a jar, capped. Never negative time, never past the cap.
function Economy.accrue(cfg: any, id: any, jar: number, seconds: number): number
	local rate = Economy.rate(cfg, id)
	if rate <= 0 then return 0 end
	local dt = if type(seconds) == "number" and seconds > 0 then seconds else 0
	return math.min(Economy.jarCap(cfg, id), math.max(0, jar) + rate * dt)
end

-- Offline growth from the server clock only: clamp(now - savedAt, 0, JarHours). A negative or
-- huge delta (clock skew between servers) mints at most one full jar.
function Economy.offlineJar(cfg: any, id: any, jar: number, savedAt: any, now: number): number
	if type(savedAt) ~= "number" or type(now) ~= "number" then
		return math.min(Economy.jarCap(cfg, id), math.max(0, jar))
	end
	local dt = math.clamp(now - savedAt, 0, cfg.Economy.JarHours * 3600)
	return Economy.accrue(cfg, id, jar, dt)
end

--============================================================================ selling, cages

function Economy.sellValue(cfg: any, id: any): number
	local price = Economy.price(cfg, id)
	if not price then return 0 end
	return math.floor(price * cfg.Economy.SellFraction)
end

-- Price of unlocking cage number (unlocked + 1), or nil at the maximum.
function Economy.expansionPrice(cfg: any, unlocked: number): number?
	if unlocked >= cfg.Economy.MaxCages then return nil end
	return cfg.Economy.ExpansionPrice[unlocked + 1]
end

function Economy.isUnlockedCage(cfg: any, profile: any, col: number): boolean
	for i = 1, math.min(profile.cagesUnlocked, #cfg.World.CageOrder) do
		if cfg.World.CageOrder[i] == col then return true end
	end
	return false
end

-- The column of the first empty unlocked cage, in centre-out order, or nil.
function Economy.firstEmptyCage(cfg: any, profile: any): number?
	for i = 1, math.min(profile.cagesUnlocked, #cfg.World.CageOrder) do
		local col = cfg.World.CageOrder[i]
		if profile.cages[col].sp == "" then return col end
	end
	return nil
end

function Economy.cryptidCount(_cfg: any, profile: any): number
	local n = 0
	for i = 1, 9 do
		if profile.cages[i].sp ~= "" then n += 1 end
	end
	return n
end

function Economy.lairRate(cfg: any, profile: any): number
	local r = 0
	for i = 1, 9 do
		r += Economy.rate(cfg, profile.cages[i].sp)
	end
	return r
end

-- Empties every jar and returns what was in them.
function Economy.collect(_cfg: any, profile: any): number
	local total = 0
	for i = 1, 9 do
		total += profile.cages[i].jar
		profile.cages[i].jar = 0
	end
	return total
end

-- Column of the fullest occupied jar (ties to the lower column), or nil with no cryptids.
function Economy.fullestCage(_cfg: any, profile: any): number?
	local best, bestJar = nil, -1
	for col = 1, 9 do
		local c = profile.cages[col]
		if c.sp ~= "" and c.jar > bestJar then
			best, bestJar = col, c.jar
		end
	end
	return best
end

--============================================================================ raids

function Economy.heatSeconds(cfg: any, tier: number): number
	return cfg.Economy.Payback[tier]
end

-- 10 % of the cheapest species of the camp's tier; tier 1 is the free tutorial raid.
function Economy.permit(cfg: any, tier: number): number
	if tier <= 1 then return 0 end
	local cheapest = math.huge
	for _, id in Economy.speciesOfTier(cfg, tier) do
		cheapest = math.min(cheapest, Economy.price(cfg, id) :: number)
	end
	return math.floor(cheapest * cfg.Raid.PermitFraction)
end

-- Highest tier ever owned (the Journal), 0 before the first cryptid.
function Economy.rank(cfg: any, journal: { string }): number
	local r = 0
	for _, id in journal do
		local t = Economy.tierOf(cfg, id)
		if t and t > r then r = t end
	end
	return r
end

-- Camp k needs a tier k-1 species in the Journal. The Journal is ever-owned, so releasing a
-- cryptid can never re-lock a camp.
function Economy.campUnlocked(cfg: any, tier: any, journal: { string }): boolean
	if type(tier) ~= "number" or tier % 1 ~= 0 or tier < 1 or tier > #cfg.Camps then return false end
	if tier == 1 then return true end
	for _, id in journal do
		if Economy.tierOf(cfg, id) == tier - 1 then return true end
	end
	return false
end

--============================================================================ poachers

function Economy.bounty(cfg: any, lairRate: number): number
	return math.max(cfg.Poacher.BountyMin, math.floor(cfg.Poacher.BountySeconds * lairRate))
end

function Economy.theft(cfg: any, jar: number): number
	return math.max(0, jar) * cfg.Poacher.TheftFraction
end

--============================================================================ the profile

function Economy.defaultProfile(cfg: any): any
	local cages = {}
	for i = 1, 9 do
		cages[i] = { sp = "", jar = 0 }
	end
	return {
		v = 1,
		essence = cfg.Economy.StartEssence,
		savedAt = 0,
		cagesUnlocked = cfg.Economy.StartCages,
		cages = cages,
		traps = {},
		heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 },
		journal = {},
		tutorial = 0,
		stats = { steals = 0, caught = 0, poachersCaught = 0 },
	}
end

local function num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
	return default
end

-- Whatever the store returned (JSON-shaped, possibly garbage) -> a well-formed profile, with the
-- offline jar growth applied from `savedAt` to `now`. Trap strings are checked for FORMAT here;
-- whether each trap is still legal on the current layout is Layout.reconcile's job.
function Economy.normalizeProfile(cfg: any, raw: any, now: number): any
	local p = Economy.defaultProfile(cfg)
	if type(raw) ~= "table" then return p end

	p.essence = math.max(0, num(raw.essence, cfg.Economy.StartEssence))
	p.cagesUnlocked = math.clamp(math.floor(num(raw.cagesUnlocked, cfg.Economy.StartCages)), cfg.Economy.StartCages, cfg.Economy.MaxCages)
	p.tutorial = math.clamp(math.floor(num(raw.tutorial, 0)), 0, 4)
	local savedAt = raw.savedAt
	if type(savedAt) ~= "number" then savedAt = nil end
	p.savedAt = savedAt or 0

	if type(raw.cages) == "table" then
		for i = 1, 9 do
			local c = raw.cages[i]
			if type(c) == "table" and Economy.species(cfg, c.sp) then
				local jar = math.max(0, num(c.jar, 0))
				if Economy.isUnlockedCage(cfg, p, i) then
					p.cages[i] = { sp = c.sp, jar = Economy.offlineJar(cfg, c.sp, jar, savedAt, now) }
				else
					-- A cryptid in a cage the profile has not unlocked cannot come from this game.
					-- It is released for half its price rather than silently deleted.
					p.essence += Economy.sellValue(cfg, c.sp)
				end
			end
		end
	end

	if type(raw.traps) == "table" then
		for _, t in raw.traps do
			if type(t) == "string" and string.match(t, "^[LS]:%d:%d$") then
				table.insert(p.traps, t)
			end
		end
	end

	if type(raw.heat) == "table" then
		for tier = 1, 4 do
			local k = "t" .. tier
			p.heat[k] = math.floor(math.max(0, num(raw.heat[k], 0)))
		end
	end

	if type(raw.journal) == "table" then
		local seen = {}
		for _, id in raw.journal do
			if Economy.species(cfg, id) and not seen[id] then
				seen[id] = true
				table.insert(p.journal, id)
			end
		end
	end

	if type(raw.stats) == "table" then
		for _, k in { "steals", "caught", "poachersCaught" } do
			p.stats[k] = math.floor(math.max(0, num(raw.stats[k], 0)))
		end
	end

	return p
end

function Economy.journalHas(journal: { string }, id: string): boolean
	for _, j in journal do
		if j == id then return true end
	end
	return false
end

return Economy
