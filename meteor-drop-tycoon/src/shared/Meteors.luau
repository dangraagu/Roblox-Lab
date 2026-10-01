--!strict
-- Meteors.luau — when and where meteors fall, what happens to each one, and the Collector's sleep. PURE.
--
-- Randomness is INJECTED: `rand(): number in [0, 1)`. The server passes one server-lifetime
-- Random.new() (never a seed derived from anything public, fork-tower REVIEW-4), and specs pass a
-- deterministic LCG. There is no seeded generation anywhere in this game, so there is nothing a client
-- could re-run: the next meteor does not exist until the server draws it.
-- Requires nothing; takes the game's Config as `cfg`. Spec: tests/Meteors.spec.luau.

local Meteors = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Seconds to the next meteor: the Beacon's interval x U(1 - jitter, 1 + jitter). The jitter makes the
-- rhythm feel random while the mean rate stays exact.
function Meteors.gap(cfg: any, interval: number, rand: () -> number): number
	local j = cfg.Meteors.SpawnJitter
	return interval * (1 - j + 2 * j * rand())
end

-- A landing point, plot-local, uniform BY AREA in the ring LandInner <= r <= LandOuter.
function Meteors.landingPoint(cfg: any, rand: () -> number): (number, number)
	local ri, ro = cfg.Plot.LandInner, cfg.Plot.LandOuter
	local r = math.sqrt(rand() * (ro * ro - ri * ri) + ri * ri)
	local a = rand() * math.pi * 2
	return r * math.cos(a), r * math.sin(a)
end

-- A session's first meteor lands 10 studs in front of the arrival pad: the first pickup needs a 5-stud walk.
function Meteors.firstPoint(cfg: any): (number, number)
	return cfg.Plot.FirstMeteor.x, cfg.Plot.FirstMeteor.z
end

-- A rarity from the band's mix (per mille). One rand().
function Meteors.rollRarity(cfg: any, band: number, rand: () -> number): string
	local mix = cfg.Env.Bands[band].mix
	local x = rand() * 1000
	local acc = 0
	for _, r in cfg.Rarities.Order do
		acc += mix[r] or 0
		if x < acc then return r end
	end
	return cfg.Rarities.Order[1]
end

-- The meteor's fate, decided the moment it is announced:
--   "dish": inside an awake Collector and not a legendary. It never lies on the ground, so the pile cap
--           never blocks it (the design's first flaw: a cap that also refused dish catches left an AFK
--           player 0.6% of an active one's income).
--   "lie":  anything else, while fewer than MaxLying meteors lie on the plot. The Falling Star always lies.
--   "burn": the plot is full; it burns up high in the sky (a visible fizzle, no landing).
-- m = { x, z (plot-local), rarity, dishRadius, awake, lying, star? }
function Meteors.fate(cfg: any, m: any): string
	if m.star then return "lie" end
	local r = math.sqrt(m.x * m.x + m.z * m.z)
	if m.awake and m.rarity ~= "legendary" and m.dishRadius > 0 and r < m.dishRadius then
		return "dish"
	end
	if m.lying >= cfg.Meteors.MaxLying then
		return "burn"
	end
	return "lie"
end

-- The Collector catches only while its owner has picked a meteor up BY HAND in the last IdleSeconds.
-- A new player's session starts awake; a returning one carries the awake time its last save held (Save's
-- `awake`, REVIEW-1: a rejoin used to re-arm a sleeping dish). Rest does not freeze this clock.
function Meteors.awake(cfg: any, now: number, lastHand: number): boolean
	return now - lastHand < cfg.Collector.IdleSeconds
end

function Meteors.awakeLeft(cfg: any, now: number, lastHand: number): number
	return math.max(0, cfg.Collector.IdleSeconds - (now - lastHand))
end

-- "8:12"
function Meteors.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Is a landed meteor at (mx, mz) within PickupRadius (horizontal) of the trusted position (px, pz)?
function Meteors.inPickup(cfg: any, px: number, pz: number, mx: number, mz: number): boolean
	if not (finite(px) and finite(pz) and finite(mx) and finite(mz)) then return false end
	local dx, dz = px - mx, pz - mz
	local r = cfg.Meteors.PickupRadius
	return dx * dx + dz * dz <= r * r + 1e-9
end

return Meteors
