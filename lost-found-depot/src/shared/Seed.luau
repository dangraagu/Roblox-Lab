--!strict
-- Seed.luau — the per-shift seed (DESIGN.md §7.1).
--
--   seed = fmix(fmix(fmix(fmix(WorldSeed) xor (userId % 1000003)) xor shifts) xor salt)
--
-- Why hash at all: feeding the repo's LCG consecutive raw seeds repeats the first draw of a small
-- range on 99.8% of consecutive shifts; the hashed seed repeats it on 24.4%, against 25.0% for
-- independent draws [M 0].
--
-- Why `mul32` and not `a * b`: two 32-bit values multiply to 64 bits, and a double holds 53. The
-- product is silently rounded and the LOW bits — the only ones a mod 2^32 keeps — come back as
-- zeros. Splitting into 16-bit halves keeps every intermediate under 2^34 (Deep Vein's technique).
--
-- `userId % 1000003`: the bit32 functions take values below 2^32 and Roblox user ids exceed that.
-- Any reduction works, because the salt, not the user id, makes the seed unpredictable. The salt
-- is a fresh server-side Random value for EVERY SHIFT (it was one per session until REVIEW-1 pass 3:
-- a salt recovered from one visible tray predicted every later shift); it is never persisted and
-- never replicated. The seed decides only what the player can already see when the shift arms (the
-- tray, the bins, the memo); the cart has its own keys, `cartSeeds` below.
--
-- Pure, requires nothing.

local Seed = {}

local TWO32 = 4294967296

-- Exact (a * b) mod 2^32 for a, b in [0, 2^32). Largest intermediate: aH*bL + aL*bH, at most
-- 2 * 65535^2, about 8.6e9 — a factor of about a million under 2^53.
function Seed.mul32(a: number, b: number): number
	local aH, aL = a // 65536, a % 65536
	local bH, bL = b // 65536, b % 65536
	return ((aH * bL + aL * bH) % 65536 * 65536 + aL * bL) % TWO32
end

-- The murmur3 32-bit finalizer.
function Seed.fmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = Seed.mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = Seed.mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

-- The seed for one player's `shifts`-th shift (the persisted career count) under `salt`.
function Seed.forShift(cfg: any, userId: number, shifts: number, salt: number): number
	local uid = math.floor(tonumber(userId) or 0) % 1000003
	local sh = math.floor(tonumber(shifts) or 0) % TWO32
	local sa = math.floor(tonumber(salt) or 0) % TWO32
	local h = Seed.fmix(math.floor(cfg.WorldSeed) % TWO32)
	h = Seed.fmix(bit32.bxor(h, uid))
	h = Seed.fmix(bit32.bxor(h, sh))
	return Seed.fmix(bit32.bxor(h, sa))
end

-- The cart's own seeds: item n (TraySlots < n <= Items) gets fmix(fmix(k1 xor n) xor k2).
--
-- WHY THE CART HAS ITS OWN KEYS. The tray, the bins and the memo come from `forShift`'s one 32-bit
-- seed, and a client can read all of them: a brute force over the LCG's 2^32 states finds the seed
-- in 18 s, and fmix is invertible, so the salt falls out too. When the same seed also generated the
-- cart, that search predicted every one of the 22 items still to come (REVIEW-1 pass 3, exploit
-- finding 3). k1 and k2 are two server-side random values the tray never touches, so the tray says
-- nothing about the cart, and an item that has rolled in pins down only its own stream.
function Seed.cartSeeds(cfg: any, k1: number, k2: number): { [number]: number }
	local a = math.floor(tonumber(k1) or 0) % TWO32
	local b = math.floor(tonumber(k2) or 0) % TWO32
	local out = {}
	for n = cfg.Shift.TraySlots + 1, cfg.Shift.Items do
		out[n] = Seed.fmix(bit32.bxor(Seed.fmix(bit32.bxor(a, n)), b))
	end
	return out
end

return Seed
