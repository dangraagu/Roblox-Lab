--!nonstrict
-- Meteor Drop Tycoon -- DESIGN-TIME MEASUREMENT MODEL. Not game code; nothing here ships.
--
-- Every pacing, economy, geometry and anti-farm number DESIGN.md tags [M n] is printed by Part n
-- of this file. Re-run it after changing any constant below and re-read the numbers before
-- touching the spec:
--
--   luau design/model.luau 2>&1
--
-- What this is NOT: a physics model. Walking is a straight line at WalkSpeed x the profile's
-- efficiency, the server's pickup poll is treated as instant, and a hazard is a fixed time cost.
-- The player profiles (PROFILES below) are ASSUMPTIONS; the model reports what follows from them,
-- and DESIGN.md says so wherever a number rests on one. The first real play session replaces them.
--
-- The constants in C are the ones DESIGN.md proposes for src/shared/Config.luau. If the two ever
-- disagree, the build's own tests/Pacing.spec.luau (which reads Config) is the authority and this
-- file is stale.

--============================================================================ constants
local C = {
	WalkSpeed = 16, -- Humanoid default; the server writes it and nothing in v1 changes it
	-- plot geometry, plot-local studs, origin = plot centre (the Smelter)
	PlotRadius = 36,
	LandInner = 8, -- nothing lands on the Smelter (footprint radius 6) or its 2-stud apron
	LandOuter = 32, -- nothing lands within 4 studs of the plot rim
	PickupRadius = 5, -- trusted root within 5 studs (XZ) of a landed meteor collects it
	ArrivalZ = -30, -- arrival marker, on the plot's hub side
	ShowcaseZ = -26, -- the guaranteed Falling Star lands 4 studs in front of the arrival marker, r = 26 (outside the biggest dish, 24)
	FallSeconds = 1.5, -- announce -> land (the landing glow shows for this long)
	StarFallSeconds = 4.0, -- the guaranteed Falling Star descends slowly (the brag moment)
	MaxLying = 20, -- a plot holds at most 20 landed meteors; while full, new ones burn up in the sky
	SpawnJitter = 0.25, -- each gap is SpawnInterval x U(1 - j, 1 + j)
	FirstMeteorAt = 0.5, -- a new session's first meteor is announced 0.5 s after the character is placed
	FirstMeteorZ = -20, -- ... and lands 10 studs in front of the arrival marker (onboarding)

	-- Beacon: range level L = 0, 1, 2, ... (unbounded). Drives spawn rate, ore per meteor and the band.
	SpawnInterval0 = 3.0,
	SpawnIntervalDecay = 0.97,
	SpawnIntervalMin = 1.2,
	OreGrowth = 1.14, -- base ore per meteor = OreGrowth ^ L
	BeaconPrice0 = 12,
	BeaconPriceGrowth = 1.26,

	-- Collector (the catcher dish around the Smelter): level c = 0..8
	CollectorMax = 8,
	CollectorPrice0 = 60,
	CollectorPriceGrowth = 2.2,
	-- radius(c) = 0 for c = 0, else CollectorRadius1 + CollectorRadiusStep * (c - 1)
	CollectorRadius1 = 10,
	CollectorRadiusStep = 2,

	-- Smelter: level s = 0, 1, 2, ... (unbounded)
	SmeltRate0 = 0.6, -- ore per second at s = 0
	SmeltRateGrowth = 1.28,
	HopperSeconds = 20, -- hopper holds 20 s of smelting; accepts while below cap (may overfill)
	SmelterPrice0 = 20,
	SmelterPriceGrowth = 1.38,

	-- rarities: ore multiplier
	Rarities = { "common", "uncommon", "rare", "epic", "legendary" },
	RarityMult = { common = 1, uncommon = 3, rare = 8, epic = 25, legendary = 100 },

	-- Trusted position (vault-runners' Trace): the server moves its own copy of the player toward
	-- the claimed root at no more than WalkSpeed x TrustedSpeedFactor.
	TrustedSpeedFactor = 1.35,
	HudHandRate = 0.4, -- meteors per second the HUD's income model assumes an active player walks to
	DishIdleSeconds = 600, -- the Collector sleeps 10 min after its owner's last hand pickup

	-- client hazards (copied from +1 Jump's measured rules): one per 120-180 s of non-rest time
	HazardIntervalMin = 120,
	HazardIntervalMax = 180,
	HazardHitCost = 1.9, -- KnockSeconds 0.9 + ~1 s to turn back and walk on
	HazardDodgeCost = 0.6, -- stepping out of the ring, then back on course
}

-- Bands (Beacon level where each starts) and their meteor mix, per mille.
local BANDS = {
	{ id = "dusk", from = 0, mix = { common = 880, uncommon = 110, rare = 10, epic = 0, legendary = 0 } },
	{ id = "twilight", from = 5, mix = { common = 800, uncommon = 160, rare = 36, epic = 4, legendary = 0 } },
	{ id = "aurora", from = 12, mix = { common = 720, uncommon = 200, rare = 65, epic = 14, legendary = 1 } },
	{ id = "starfall", from = 22, mix = { common = 640, uncommon = 230, rare = 95, epic = 30, legendary = 5 } },
	{ id = "nebula", from = 32, mix = { common = 560, uncommon = 260, rare = 125, epic = 45, legendary = 10 } },
	{ id = "core", from = 44, mix = { common = 480, uncommon = 280, rare = 160, epic = 60, legendary = 20 } },
}
local BRAG_BAND = 4
local HAZARD_FROM_BAND = 2

-- Player profiles. ALL ASSUMPTIONS [A].
--   react: seconds from a meteor becoming visible (announced) to starting to walk, when idle
--   retarget: seconds between picking one up and heading for the next
--   eff: fraction of WalkSpeed actually made good toward the target (thumbstick + camera wobble)
--   shopEvery: seconds between opening the upgrade panel; buyTime: seconds per purchase
--   hit: share of hazards that hit (the rest are dodged)
local PROFILES = {
	fast = { react = 0.4, retarget = 0.2, eff = 0.95, shopEvery = 10, buyTime = 0.8, hit = 0.1 },
	normal = { react = 0.8, retarget = 0.4, eff = 0.85, shopEvery = 20, buyTime = 1.2, hit = 0.25 },
	slow = { react = 1.5, retarget = 0.8, eff = 0.7, shopEvery = 45, buyTime = 2.0, hit = 0.4 },
	-- the script bound: no reaction, perfect line, buys the moment it can, never hit, and moving at
	-- the trusted-position cap (a teleporting client gets exactly this and no more)
	bot = { react = 0, retarget = 0, eff = C.TrustedSpeedFactor, shopEvery = 0.1, buyTime = 0, hit = 0 },
	-- sensitivity: the normal player who ignores the star and buys whatever lit thing is cheapest
	cheapest = { react = 0.8, retarget = 0.4, eff = 0.85, shopEvery = 20, buyTime = 1.2, hit = 0.25, policy = "cheapest" },
}

--============================================================================ rng (the repo's LCG, high bits)
local Rng = {}
Rng.__index = Rng
local MOD = 4294967296
function Rng.new(seed: number)
	return setmetatable({ s = math.floor(seed) % MOD }, Rng)
end
function Rng:next(): number
	self.s = (1664525 * self.s + 1013904223) % MOD
	return self.s / MOD
end

--============================================================================ economy (the pure rules)
local function bandOf(L: number): number
	local idx = 1
	for i = 2, #BANDS do
		if L >= BANDS[i].from then idx = i else break end
	end
	return idx
end
local function spawnInterval(L: number): number
	return math.max(C.SpawnIntervalMin, C.SpawnInterval0 * C.SpawnIntervalDecay ^ L)
end
local function baseOre(L: number): number
	return C.OreGrowth ^ L
end
local function beaconPrice(L: number): number
	return math.floor(C.BeaconPrice0 * C.BeaconPriceGrowth ^ L + 0.5)
end
local function collectorPrice(c: number): number?
	if c >= C.CollectorMax then return nil end
	return math.floor(C.CollectorPrice0 * C.CollectorPriceGrowth ^ c + 0.5)
end
local function smelterPrice(s: number): number
	return math.floor(C.SmelterPrice0 * C.SmelterPriceGrowth ^ s + 0.5)
end
local function dishRadius(c: number): number
	if c <= 0 then return 0 end
	return C.CollectorRadius1 + C.CollectorRadiusStep * (c - 1)
end
local function dishShare(c: number): number
	local r = dishRadius(c)
	if r <= C.LandInner then return 0 end
	return (r * r - C.LandInner ^ 2) / (C.LandOuter ^ 2 - C.LandInner ^ 2)
end
local function smeltRate(s: number): number
	return C.SmeltRate0 * C.SmeltRateGrowth ^ s
end
local function hopperCap(s: number): number
	return smeltRate(s) * C.HopperSeconds
end
local function avgMult(band: number): number
	local m = 0
	for _, r in C.Rarities do
		m += BANDS[band].mix[r] / 1000 * C.RarityMult[r]
	end
	return m
end
-- expected ore per second arriving on a plot (before dish/hand/burn split)
local function inflow(L: number): number
	return avgMult(bandOf(L)) * baseOre(L) / spawnInterval(L)
end

-- The HUD's steady-state income model (pure; the game's Economy.income will be this function).
-- An active player is assumed to walk to HudHandRate meteors per second (M1: a mean 29.9-stud
-- walk = 1.87 s, plus about 0.6 s to notice and turn = 2.5 s per meteor). Legendaries are ignored
-- here: they are 0.5-2 % of meteors and the star should not chase them.
local function steadyIncome(L: number, c: number, s: number): number
	local si = spawnInterval(L)
	local share = dishShare(c)
	local outsidePerSecond = (1 - share) / si
	local hand = math.min(outsidePerSecond, C.HudHandRate)
	local caught = share + hand * si
	return math.min(smeltRate(s), inflow(L) * caught)
end
-- (kind, price): the upgrade that adds the most steady income per Stardust. When nothing adds
-- income (the Smelter exactly matches what is caught), the cheaper of Beacon and Smelter, so the
-- star never goes dark.
local function bestNext(L: number, c: number, s: number): (string, number)
	local now = steadyIncome(L, c, s)
	local best, bestPrice, bestGain = nil, 0, -1
	local function consider(kind, price, after)
		if price == nil then return end
		local gain = (after - now) / price
		if gain > bestGain + 1e-12 or (math.abs(gain - bestGain) <= 1e-12 and price < bestPrice) then
			best, bestPrice, bestGain = kind, price, gain
		end
	end
	consider("beacon", beaconPrice(L), steadyIncome(L + 1, c, s))
	consider("smelter", smelterPrice(s), steadyIncome(L, c, s + 1))
	local cp = collectorPrice(c)
	if cp then consider("collector", cp, steadyIncome(L, c + 1, s)) end
	if bestGain <= 1e-12 then
		-- nothing adds income on its own: Beacon and Smelter move together
		if beaconPrice(L) <= smelterPrice(s) then return "beacon", beaconPrice(L) end
		return "smelter", smelterPrice(s)
	end
	return best, bestPrice
end

local function rollRarity(rng, band: number): string
	local x = rng:next() * 1000
	local acc = 0
	for _, r in C.Rarities do
		acc += BANDS[band].mix[r]
		if x < acc then return r end
	end
	return "common"
end

local function pointInAnnulus(rng): (number, number)
	local ri, ro = C.LandInner, C.LandOuter
	local r = math.sqrt(rng:next() * (ro * ro - ri * ri) + ri * ri)
	local a = rng:next() * math.pi * 2
	return r * math.cos(a), r * math.sin(a)
end

--============================================================================ the simulation
-- opts: { profile, seed, minutes, afk = bool, afkBuyEvery = seconds or nil, startState = table or nil,
--         freezeBuilds = bool, dt }
local function simulate(opts)
	local prof = opts.profile
	local rng = Rng.new(opts.seed)
	local dt = opts.dt or 0.1
	local st = opts.startState
	local S = {
		t = 0,
		L = st and st.L or 0,
		c = st and st.c or 0,
		s = st and st.s or 0,
		dust = st and st.dust or 0,
		hopper = 0,
		meteors = {},
		nextSpawn = 0,
		px = 0, pz = C.ArrivalZ,
		target = nil, waitUntil = 0, busyUntil = 0,
		lastShop = 0, hopperFullSeen = false,
		nextHaz = C.HazardIntervalMin + (C.HazardIntervalMax - C.HazardIntervalMin) * rng:next(),
		bandAt = {}, bragAt = nil, starGranted = st and st.starGranted or false,
		ore = { spawned = 0, dish = 0, hand = 0, burned = 0, bounced = 0, legendHand = 0 },
		smelted = 0, instant = 0, hazards = 0, hits = 0, buys = 0,
		lastHand = 0, -- a session starts awake
		asleepSeconds = 0,
		snapshots = {},
	}
	S.bandAt[1] = 0
	for b = 2, #BANDS do
		if S.L >= BANDS[b].from then S.bandAt[b] = 0 end
	end
	S.nextSpawn = C.FirstMeteorAt
	S.firstPending = true
	S.firstPickupAt = nil
	S.firstBuyAt = nil

	local total = (opts.minutes or 240) * 60
	local snapAt = opts.snapAt or {}
	local snapIdx = 1

	-- meteors on (or falling toward) the ground that nobody but the player will pick up
	local function lyingCount(): number
		local n = 0
		for _, m in S.meteors do
			if not m.dish then n += 1 end
		end
		return n
	end
	local function hopperFull(): boolean
		return S.hopper >= hopperCap(S.s)
	end
	local function spawnMeteor(x, z, rarity, fall)
		local band = bandOf(S.L)
		local ore = baseOre(S.L) * C.RarityMult[rarity]
		local m = { x = x, z = z, rarity = rarity, ore = ore, landAt = S.t + fall, landed = false,
			r = math.sqrt(x * x + z * z), star = false }
		-- decided when it is announced: inside the Collector's radius (and not a legendary) it is a
		-- dish catch and never lies; anything else lies where it lands, unless the plot is full
		local awake = S.t - S.lastHand < C.DishIdleSeconds
		m.dish = awake and m.r < dishRadius(S.c) and rarity ~= "legendary"
		S.ore.spawned += ore
		if not m.dish and lyingCount() >= C.MaxLying then
			S.ore.burned += ore
			return nil
		end
		table.insert(S.meteors, m)
		return m, band
	end
	local function removeMeteor(m)
		for i, x in S.meteors do
			if x == m then table.remove(S.meteors, i) return end
		end
	end
	local function buyOne(): boolean
		local pick = nil
		if (prof.policy or "star") == "star" then
			-- the HUD's star: the upgrade with the most steady-state income per Stardust
			local kind, price = bestNext(S.L, S.c, S.s)
			if kind and S.dust >= price then pick = { kind = kind, price = price } end
		else
			-- sensitivity: a player who ignores the star and buys the cheapest thing that is lit
			local options = { { kind = "beacon", price = beaconPrice(S.L) }, { kind = "smelter", price = smelterPrice(S.s) } }
			local cp = collectorPrice(S.c)
			if cp then table.insert(options, { kind = "collector", price = cp }) end
			table.sort(options, function(a, b) return a.price < b.price end)
			for _, o in options do
				if S.dust >= o.price then pick = o break end
			end
		end
		if pick == nil then return false end
		S.dust -= pick.price
		S.buys += 1
		if S.firstBuyAt == nil then S.firstBuyAt = S.t; S.firstBuyKind = pick.kind end
		S.firstOf = S.firstOf or {}
		if S.firstOf[pick.kind] == nil then S.firstOf[pick.kind] = S.t end
		if pick.kind == "beacon" then S.L += 1
		elseif pick.kind == "collector" then S.c += 1
		else S.s += 1 end
		return true
	end

	while S.t < total do
		S.t += dt
		-- snapshots
		while snapIdx <= #snapAt and S.t >= snapAt[snapIdx] do
			S.snapshots[snapAt[snapIdx]] = { L = S.L, c = S.c, s = S.s, dust = S.dust, smelted = S.smelted + S.instant,
				hand = S.ore.hand, dish = S.ore.dish, burned = S.ore.burned, spawned = S.ore.spawned,
				starGranted = S.starGranted }
			snapIdx += 1
		end

		-- band bookkeeping and the guaranteed Falling Star on first entering the brag band
		local band = bandOf(S.L)
		for b = 2, band do
			if S.bandAt[b] == nil then S.bandAt[b] = S.t end
		end
		if band >= BRAG_BAND and not S.starGranted then
			S.starGranted = true
			local m = { x = 0, z = C.ShowcaseZ, rarity = "legendary", ore = baseOre(S.L) * C.RarityMult.legendary,
				landAt = S.t + C.StarFallSeconds, landed = false, r = C.ShowcaseZ, star = true }
			S.ore.spawned += m.ore
			table.insert(S.meteors, m) -- the star is never refused by the pile cap
		end

		-- spawner
		if S.t >= S.nextSpawn then
			if S.firstPending then
				S.firstPending = false
				spawnMeteor(0, C.FirstMeteorZ, "common", C.FallSeconds)
			else
				local x, z = pointInAnnulus(rng)
				spawnMeteor(x, z, rollRarity(rng, bandOf(S.L)), C.FallSeconds)
			end
			S.nextSpawn = S.t + spawnInterval(S.L) * (1 - C.SpawnJitter + 2 * C.SpawnJitter * rng:next())
		end

		-- landing + dish
		local rd = dishRadius(S.c)
		for i = #S.meteors, 1, -1 do
			local m = S.meteors[i]
			if not m.landed and S.t >= m.landAt then
				m.landed = true
				if m.dish then
					-- the Collector takes it into the hopper, or it bounces off a full hopper and is lost
					if hopperFull() then
						S.ore.bounced += m.ore
					else
						S.hopper += m.ore
						S.ore.dish += m.ore
					end
					table.remove(S.meteors, i)
				end
			end
		end

		-- smelter
		if S.hopper > 0 then
			local take = math.min(S.hopper, smeltRate(S.s) * dt)
			S.hopper -= take
			S.dust += take
			S.smelted += take
		end
		if hopperFull() then S.hopperFullSeen = true end
		if S.t - S.lastHand >= C.DishIdleSeconds then S.asleepSeconds += dt end
		-- a minimal pathing bot: grabs one meteor every opts.pokeEvery seconds and nothing else
		if opts.pokeEvery and S.t - S.lastHand >= opts.pokeEvery then
			for i, m in S.meteors do
				if m.landed and not m.dish and m.rarity ~= "legendary" and not hopperFull() then
					S.hopper += m.ore; S.ore.hand += m.ore; S.lastHand = S.t
					table.remove(S.meteors, i)
					break
				end
			end
		end

		-- AFK macro buyer
		if opts.afk then
			if opts.afkBuyEvery and not opts.freezeBuilds and S.t - S.lastShop >= opts.afkBuyEvery then
				S.lastShop = S.t
				while buyOne() do end
			end
		else
			-- hazards (client-side; only a time cost here)
			if band >= HAZARD_FROM_BAND and S.t >= S.nextHaz then
				S.hazards += 1
				local hit = rng:next() < prof.hit
				if hit then S.hits += 1 end
				S.busyUntil = math.max(S.busyUntil, S.t) + (if hit then C.HazardHitCost else C.HazardDodgeCost)
				S.nextHaz = S.t + C.HazardIntervalMin + (C.HazardIntervalMax - C.HazardIntervalMin) * rng:next()
			end
			-- shopping
			if not opts.freezeBuilds and S.t >= S.busyUntil and S.t - S.lastShop >= prof.shopEvery then
				S.lastShop = S.t
				local n = 0
				while buyOne() do n += 1 end
				S.busyUntil = S.t + n * prof.buyTime
			end
			-- walking
			if S.t >= S.busyUntil then
				if S.target and table.find(S.meteors, S.target) == nil then S.target = nil end
				if S.target == nil then
					-- choose: the Falling Star, then epic/legendary, then nearest. Skip what the dish
					-- will take on its own; wait while the hopper is full (pickups would be refused).
					do
						local full = hopperFull()
						local best, bestD, bestPri = nil, math.huge, -1
						for _, m in S.meteors do
							if not m.dish and (not full or m.rarity == "legendary") then
								local pri = if m.star then 3 elseif (m.rarity == "legendary" or m.rarity == "epic") then 2 else 1
								local d = math.sqrt((m.x - S.px) ^ 2 + (m.z - S.pz) ^ 2)
								if pri > bestPri or (pri == bestPri and d < bestD) then
									best, bestD, bestPri = m, d, pri
								end
							end
						end
						if best then
							S.target = best
							S.waitUntil = S.t + (if S.idleSince then prof.react else prof.retarget)
							S.idleSince = nil
						elseif S.idleSince == nil then
							S.idleSince = S.t
						end
					end
				end
				if S.target and S.t >= S.waitUntil then
					local m = S.target
					local dx, dz = m.x - S.px, m.z - S.pz
					local d = math.sqrt(dx * dx + dz * dz)
					if d <= C.PickupRadius then
						-- a legendary (Star Core) never enters the hopper: it pays out the moment it is caught,
						-- so the brag meteor cannot clog the Smelter (M7), and it is never refused
						if m.landed and (m.rarity == "legendary" or not hopperFull()) then
							if m.rarity == "legendary" then
								S.dust += m.ore
								S.instant += m.ore
								S.ore.legendHand += m.ore
							else
								S.hopper += m.ore
							end
							S.ore.hand += m.ore
							S.lastHand = S.t
							if S.firstPickupAt == nil then S.firstPickupAt = S.t end
							if m.star and S.bragAt == nil then S.bragAt = S.t end
							removeMeteor(m)
							S.target = nil
						end
					else
						local step = math.min(d - C.PickupRadius * 0.5, C.WalkSpeed * prof.eff * dt)
						S.px += dx / d * step
						S.pz += dz / d * step
					end
				end
			end
		end
	end
	return S
end

--============================================================================ helpers
local function sorted(t)
	local c = table.clone(t)
	table.sort(c)
	return c
end
local function pct(t, p)
	local s = sorted(t)
	if #s == 0 then return 0 end
	local i = math.clamp(math.floor(p * (#s - 1) + 0.5) + 1, 1, #s)
	return s[i]
end
local function f1(x) return string.format("%.1f", x) end
local function f2(x) return string.format("%.2f", x) end
local function f3(x) return string.format("%.3f", x) end
local SEEDS = 20

--============================================================================ Part 1: geometry
print("== M1 geometry ==")
do
	-- mean straight-line distance between two uniform points of the landing annulus
	local rng = Rng.new(11)
	local sum, n = 0, 200000
	for _ = 1, n do
		local ax, az = pointInAnnulus(rng)
		local bx, bz = pointInAnnulus(rng)
		sum += math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end
	print("mean distance between two landing points: " .. f2(sum / n) .. " studs = " .. f2(sum / n / C.WalkSpeed) .. " s at WalkSpeed")
	local sumA = 0
	for _ = 1, n do
		local ax, az = pointInAnnulus(rng)
		sumA += math.sqrt((ax - 0) ^ 2 + (az - C.ArrivalZ) ^ 2)
	end
	print("mean distance arrival marker -> a landing point: " .. f2(sumA / n) .. " studs")
	print("arrival marker -> Falling Star showcase: " .. f1(math.abs(C.ShowcaseZ - C.ArrivalZ)) .. " studs")
	for c = 0, C.CollectorMax do
		print(string.format("collector %d: radius %d, share of landings %.3f, price to next %s", c, dishRadius(c),
			dishShare(c), tostring(collectorPrice(c))))
	end
end

--============================================================================ Part 2: the rules per band
print("\n== M2 per-band economy ==")
for b, band in BANDS do
	local L = band.from
	print(string.format("band %d %-9s from L%-3d avg mult %.3f  interval %.2f s  base ore %.2f  inflow %.2f ore/s  beacon price %d  legendary every %s meteors",
		b, band.id, L, avgMult(b), spawnInterval(L), baseOre(L), inflow(L), beaconPrice(L),
		if band.mix.legendary > 0 then f1(1000 / band.mix.legendary) else "never"))
end
print("spawn interval reaches its floor " .. C.SpawnIntervalMin .. " s at L" ..
	tostring(math.ceil(math.log(C.SpawnIntervalMin / C.SpawnInterval0) / math.log(C.SpawnIntervalDecay))))

--============================================================================ Part 3: pacing per profile
print("\n== M3 pacing (" .. SEEDS .. " seeds, 240 min, HUD follower) ==")
local normalRuns = {}
for _, pname in { "fast", "normal", "slow", "bot", "cheapest" } do
	local prof = PROFILES[pname]
	local bandT = {}
	for b = 1, #BANDS do bandT[b] = {} end
	local brag, at35, dishSh, burnSh, legSh, hz, hits, rate10, rate35, rate90 = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
	for seed = 1, SEEDS do
		local S = simulate({ profile = prof, seed = seed * 7919 + 17, minutes = 240, snapAt = { 600, 660, 2100, 2160, 5400, 5460, 7200 } })
		if pname == "normal" then table.insert(normalRuns, S) end
		for b = 1, #BANDS do table.insert(bandT[b], (S.bandAt[b] or math.huge) / 60) end
		table.insert(brag, (S.bragAt or math.huge) / 60)
		local s35 = S.snapshots[2100]
		table.insert(at35, s35)
		local tot = S.ore.hand + S.ore.dish
		table.insert(dishSh, S.ore.dish / tot)
		table.insert(burnSh, (S.ore.burned + S.ore.bounced) / S.ore.spawned)
		table.insert(legSh, S.ore.legendHand / tot)
		table.insert(hz, S.hazards)
		table.insert(hits, S.hits)
		local function rate(a, b) return (S.snapshots[b].smelted - S.snapshots[a].smelted) end -- per minute
		table.insert(rate10, rate(600, 660))
		table.insert(rate35, rate(2100, 2160))
		table.insert(rate90, rate(5400, 5460))
	end
	print("-- " .. pname)
	for b = 1, #BANDS do
		print(string.format("  band %d %-9s reached at min: p10 %s  median %s  p90 %s", b, BANDS[b].id,
			f1(pct(bandT[b], 0.1)), f1(pct(bandT[b], 0.5)), f1(pct(bandT[b], 0.9))))
	end
	print(string.format("  FALLING STAR caught at min: p10 %s  median %s  p90 %s", f1(pct(brag, 0.1)), f1(pct(brag, 0.5)), f1(pct(brag, 0.9))))
	local Ls, cs, ss = {}, {}, {}
	for _, s in at35 do table.insert(Ls, s.L); table.insert(cs, s.c); table.insert(ss, s.s) end
	print(string.format("  build at 35 min (median): beacon %d collector %d smelter %d", pct(Ls, 0.5), pct(cs, 0.5), pct(ss, 0.5)))
	print(string.format("  stardust per minute (median): at 10 min %s, at 35 min %s, at 90 min %s",
		f1(pct(rate10, 0.5)), f1(pct(rate35, 0.5)), f1(pct(rate90, 0.5))))
	print(string.format("  over 240 min (median): dish share of income %s, burned+bounced share of spawned ore %s, hand-caught legendaries %s of income",
		f3(pct(dishSh, 0.5)), f3(pct(burnSh, 0.5)), f3(pct(legSh, 0.5))))
	print(string.format("  hazards in 240 min (median) %d, hits %d", pct(hz, 0.5), pct(hits, 0.5)))
end

--============================================================================ Part 4: band durations (normal)
print("\n== M4 band durations, normal (median minutes) ==")
do
	for b = 1, #BANDS - 1 do
		local d = {}
		for _, S in normalRuns do
			if S.bandAt[b + 1] then table.insert(d, (S.bandAt[b + 1] - S.bandAt[b]) / 60) end
		end
		print(string.format("  %-9s lasts: min %s median %s", BANDS[b].id, f1(pct(d, 0)), f1(pct(d, 0.5))))
	end
end

--============================================================================ Part 5: the script bound
-- Same build, same meteors: what does the trusted-speed bot collect per minute against the normal
-- human? Builds frozen at the normal player's median build at 35 and at 90 minutes.
print("\n== M5 script bound: collection per minute at a FROZEN build (30 seeds x 30 min) ==")
do
	for _, snapT in { 2100, 5400 } do
		local Ls, cs, ss = {}, {}, {}
		for _, S in normalRuns do
			local sn = S.snapshots[snapT]
			table.insert(Ls, sn.L); table.insert(cs, sn.c); table.insert(ss, sn.s)
		end
		local start = { L = pct(Ls, 0.5), c = pct(cs, 0.5), s = pct(ss, 0.5), dust = 0, starGranted = true }
		local res = {}
		for _, pname in { "normal", "bot", "afk", "afk10" } do
			local tot = {}
			local mins = if pname == "afk10" then 10 else 30
			for seed = 1, SEEDS do
				local S = simulate({ profile = PROFILES[pname] or PROFILES.normal, seed = seed * 104729 + 3, minutes = mins,
					startState = start, freezeBuilds = true, afk = (pname == "afk" or pname == "afk10") })
				table.insert(tot, (S.smelted + S.instant) / mins)
			end
			res[pname] = pct(tot, 0.5)
		end
		print(string.format("  build L%d c%d s%d (normal's median at %d min): normal %s, bot %s stardust/min, bot/normal %s; AFK while the Collector is awake (first 10 min) %s/min = %s of normal; AFK over 30 min %s/min = %s of normal; smelter cap %s/min, inflow %s/min",
			start.L, start.c, start.s, snapT // 60, f1(res.normal), f1(res.bot), f3(res.bot / res.normal),
			f1(res.afk10), f3(res.afk10 / res.normal), f1(res.afk), f3(res.afk / res.normal),
			f1(smeltRate(start.s) * 60), f1(inflow(start.L) * 60)))
	end
end

--============================================================================ Part 6: AFK with a buying macro
-- The residual risk the board has to live with: a macro keeps a player in the server and buys
-- whatever is cheapest every minute. Start from the normal player's median state at 35 min.
print("\n== M6 AFK macros vs an active normal player, from the normal player's 35-minute state (the Collector sleeps " .. C.DishIdleSeconds .. " s after its owner's last hand pickup) ==")
do
	local Ls, cs, ss, ds = {}, {}, {}, {}
	for _, S in normalRuns do
		local sn = S.snapshots[2100]
		table.insert(Ls, sn.L); table.insert(cs, sn.c); table.insert(ss, sn.s); table.insert(ds, sn.dust)
	end
	local start = { L = pct(Ls, 0.5), c = pct(cs, 0.5), s = pct(ss, 0.5), dust = 0, starGranted = true }
	for _, hours in { 1, 8 } do
		local afkL, actL = {}, {}
		for seed = 1, 10 do
			local A = simulate({ profile = PROFILES.normal, seed = seed * 31337 + 1, minutes = hours * 60, startState = start,
				afk = true, afkBuyEvery = 60 })
			table.insert(afkL, A.L)
			local N = simulate({ profile = PROFILES.normal, seed = seed * 31337 + 1, minutes = hours * 60, startState = start })
			table.insert(actL, N.L)
		end
		local pokeL = {}
		for seed = 1, 10 do
			local B = simulate({ profile = PROFILES.normal, seed = seed * 31337 + 1, minutes = hours * 60, startState = start,
				afk = true, afkBuyEvery = 60, pokeEvery = 540 })
			table.insert(pokeL, B.L)
		end
		print(string.format("  +%d h: anti-AFK jiggle + buying macro reaches beacon %d (median); a bot that also grabs one meteor every 9 min %d; an active normal player %d; start beacon %d",
			hours, pct(afkL, 0.5), pct(pokeL, 0.5), pct(actL, 0.5), start.L))
	end
end

--============================================================================ Part 7: hopper and the biggest meteor
print("\n== M7 hopper headroom ==")
do
	-- the largest single meteor (a legendary at the start of each band) against the hopper of the
	-- normal player's median smelter when they reach that band
	for b, band in BANDS do
		-- the smallest Smelter level whose melt rate covers the band's inflow at its first level
		local L = band.from
		local s = 0
		while smeltRate(s) < inflow(L) do s += 1 end
		print(string.format("  band %d: largest hopper item (epic) %.1f ore; the smallest smelter that keeps up (s%d) holds %.1f ore -> %.2f hoppers (legendaries bypass the hopper)",
			b, baseOre(L) * 25, s, hopperCap(s), baseOre(L) * 25 / hopperCap(s)))
	end
end

--============================================================================ Part 8: the first 60 seconds
print("== M8 first 60 seconds (normal, 20 seeds) ==")
do
	local fp, fb, d60, n60, kinds = {}, {}, {}, {}, {}
	for seed = 1, SEEDS do
		local S = simulate({ profile = PROFILES.normal, seed = seed * 7919 + 17, minutes = 1, snapAt = { 60 } })
		table.insert(fp, S.firstPickupAt or math.huge)
		table.insert(fb, S.firstBuyAt or math.huge)
		kinds[S.firstBuyKind or "none"] = (kinds[S.firstBuyKind or "none"] or 0) + 1
		table.insert(d60, S.snapshots[60].smelted)
		table.insert(n60, S.buys)
	end
	print(string.format("  first pickup at s: p10 %s median %s p90 %s", f1(pct(fp, 0.1)), f1(pct(fp, 0.5)), f1(pct(fp, 0.9))))
	print(string.format("  first purchase at s: p10 %s median %s p90 %s", f1(pct(fb, 0.1)), f1(pct(fb, 0.5)), f1(pct(fb, 0.9))))
	local ks = {}
	for k, n in kinds do table.insert(ks, k .. " x" .. n) end
	print("  first purchase kind: " .. table.concat(ks, ", "))
	print(string.format("  Stardust smelted by 60 s: median %s; purchases by 60 s: median %d", f1(pct(d60, 0.5)), pct(n60, 0.5)))
end

--============================================================================ Part 9: hazards in the first 36 minutes
print("== M9 hazards ==")
do
	local n, h = {}, {}
	for seed = 1, SEEDS do
		local S = simulate({ profile = PROFILES.normal, seed = seed * 7919 + 17, minutes = 36 })
		table.insert(n, S.hazards); table.insert(h, S.hits)
	end
	print(string.format("  normal, first 36 min: hazards median %d (min %d, max %d), hits median %d", pct(n, 0.5), pct(n, 0), pct(n, 1), pct(h, 0.5)))
	print("  hazard-free until band 2 (Beacon " .. BANDS[HAZARD_FROM_BAND].from .. ")")
end

--============================================================================ Part 10: first purchase of each track
print("== M10 first purchase of each upgrade (normal, 20 seeds, median minutes) ==")
do
	local k = { beacon = {}, collector = {}, smelter = {} }
	for seed = 1, SEEDS do
		local S = simulate({ profile = PROFILES.normal, seed = seed * 7919 + 17, minutes = 30 })
		for kind, list in k do table.insert(list, ((S.firstOf or {})[kind] or math.huge) / 60) end
	end
	print(string.format("  beacon %s, smelter %s, collector %s", f2(pct(k.beacon, 0.5)), f2(pct(k.smelter, 0.5)), f2(pct(k.collector, 0.5))))
end

--============================================================================ Part 11: sensitivity of the two price growths
print("== M11 sensitivity: normal player's Falling Star / Galactic Core minute (8 seeds) ==")
do
	local baseB, baseS = C.BeaconPriceGrowth, C.SmelterPriceGrowth
	for _, pair in { { baseB, baseS }, { baseB - 0.01, baseS }, { baseB + 0.01, baseS }, { baseB, baseS - 0.02 }, { baseB, baseS + 0.02 }, { baseB, 1.45 } } do
		C.BeaconPriceGrowth, C.SmelterPriceGrowth = pair[1], pair[2]
		local star, core, lost = {}, {}, {}
		for seed = 1, 8 do
			local S = simulate({ profile = PROFILES.normal, seed = seed * 7919 + 17, minutes = 240 })
			table.insert(star, (S.bragAt or math.huge) / 60)
			table.insert(core, (S.bandAt[#BANDS] or math.huge) / 60)
			table.insert(lost, (S.ore.burned + S.ore.bounced) / S.ore.spawned)
		end
		print(string.format("  BeaconPriceGrowth %.2f SmelterPriceGrowth %.2f: star %s min, core %s min, burned+bounced %s",
			pair[1], pair[2], f1(pct(star, 0.5)), f1(pct(core, 0.5)), f3(pct(lost, 0.5))))
	end
	C.BeaconPriceGrowth, C.SmelterPriceGrowth = baseB, baseS
end
