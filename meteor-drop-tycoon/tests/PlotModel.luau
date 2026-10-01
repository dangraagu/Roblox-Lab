--!nonstrict
-- PlotModel.luau — the pacing model, as a module the specs run. NOT game code; nothing here ships.
--
-- It is design/model.luau's simulate(), rewired to read the game's own Config and to call the game's own
-- pure rules (Economy for prices, rates, the hopper, melting and the HUD's star; Meteors for landing
-- points, rarities, fates and the Collector's sleep). So the minutes it measures are the minutes of the
-- rules that ship, not of a copy of them. tests/Pacing.spec.luau asserts on it.
--
-- What this is NOT: a physics model. Walking is a straight line at WalkSpeed x the profile's efficiency,
-- the server's pickup poll is treated as instant, and a hazard is a fixed time cost. The player profiles
-- (Config.Pacing.Profiles) are ASSUMPTIONS; replace `normal` with telemetry after the first real sessions.

local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Meteors = require("../src/shared/Meteors")

local C = Config
local M = {}

--============================================================================ rng (the repo's LCG, high bits)
function M.rng(seed: number)
	local s = math.floor(seed) % 4294967296
	return function(): number
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

local BRAG_BAND = 0
for i, b in C.Env.Bands do
	if b.id == C.Env.BragBandId then BRAG_BAND = i end
end
M.BRAG_BAND = BRAG_BAND
M.BANDS = #C.Env.Bands

-- opts: { profile, seed, minutes, afk, afkBuyEvery, startState, freezeBuilds, pokeEvery, snapAt, dt, stopWhen }
function M.simulate(opts)
	local prof = opts.profile
	local rand = M.rng(opts.seed)
	local dt = opts.dt or 0.1
	local st = opts.startState
	local S = {
		t = 0,
		lv = { beacon = st and st.L or 0, collector = st and st.c or 0, smelter = st and st.s or 0,
			stardust = st and st.dust or 0, hopper = 0, lifetime = 0 },
		meteors = {},
		nextSpawn = C.Meteors.FirstMeteorAt,
		firstPending = true,
		px = C.Plot.Arrival.x, pz = C.Plot.Arrival.z,
		target = nil, waitUntil = 0, busyUntil = 0, lastShop = 0,
		nextHaz = C.Hazards.IntervalMin + (C.Hazards.IntervalMax - C.Hazards.IntervalMin) * rand(),
		bandAt = { 0 },
		bragAt = nil,
		starGranted = st and st.starGranted or false,
		ore = { spawned = 0, dish = 0, hand = 0, burned = 0, bounced = 0, legendHand = 0 },
		minted = 0, hazards = 0, hits = 0, buys = 0,
		-- REVIEW-1: from join to the catch of the Falling Star, how often the hopper is full and what the dish loses
		preBrag = { ticks = 0, full = 0, dish = 0, bounced = 0 },
		fullEma = 0, -- the server's measured full-share (Economy.fullEma), which the star listens to
		lastHand = 0,
		firstOf = {},
		snapshots = {},
	}
	local lv = S.lv
	for b = 2, M.BANDS do
		if lv.beacon >= C.Env.Bands[b].from then S.bandAt[b] = 0 end
	end
	local total = (opts.minutes or 240) * 60
	local snapAt = opts.snapAt or {}
	local snapIdx = 1

	local function lyingCount(): number
		local n = 0
		for _, m in S.meteors do
			if m.fate ~= "dish" then n += 1 end
		end
		return n
	end
	local function hopperFull(): boolean
		return lv.hopper >= Economy.hopperCap(C, lv.smelter)
	end
	local function spawnMeteor(x, z, rarity, fall, star)
		local ore = Economy.oreOf(C, lv.beacon, rarity)
		S.ore.spawned += ore
		local fate = Meteors.fate(C, { x = x, z = z, rarity = rarity, star = star,
			dishRadius = Economy.dishRadius(C, lv.collector), awake = Meteors.awake(C, S.t, S.lastHand), lying = lyingCount() })
		if fate == "burn" then
			S.ore.burned += ore
			return
		end
		table.insert(S.meteors, { x = x, z = z, rarity = rarity, ore = ore, landAt = S.t + fall, landed = false,
			fate = fate, star = star })
	end
	local function buyOne(): boolean
		-- as the server's bestOf: the measured fullness counts once a first machine is bought
		local measured = if lv.beacon + lv.collector + lv.smelter > 0 then S.fullEma else nil
		local kind, price = Economy.bestNext(C, lv.beacon, lv.collector, lv.smelter, measured)
		if lv.stardust < price then return false end
		local ok = Economy.buy(C, lv, kind)
		if not ok then return false end
		if kind == "smelter" then S.fullEma = 0 end -- as the server does
		S.buys += 1
		if S.firstBuyAt == nil then S.firstBuyAt = S.t; S.firstBuyKind = kind end
		if S.firstOf[kind] == nil then S.firstOf[kind] = S.t end
		return true
	end

	while S.t < total do
		S.t += dt
		while snapIdx <= #snapAt and S.t >= snapAt[snapIdx] do
			S.snapshots[snapAt[snapIdx]] = { L = lv.beacon, c = lv.collector, s = lv.smelter, dust = lv.stardust, minted = S.minted }
			snapIdx += 1
		end

		local band = Economy.bandIndex(C, lv.beacon)
		for b = 2, band do
			if S.bandAt[b] == nil then S.bandAt[b] = S.t end
		end
		if band >= BRAG_BAND and not S.starGranted then
			S.starGranted = true
			spawnMeteor(C.Plot.Showcase.x, C.Plot.Showcase.z, "legendary", C.Meteors.StarFallSeconds, true)
		end
		if opts.stopWhen and opts.stopWhen(S) then break end

		-- spawner
		if S.t >= S.nextSpawn then
			if S.firstPending then
				S.firstPending = false
				local fx, fz = Meteors.firstPoint(C)
				spawnMeteor(fx, fz, "common", C.Meteors.FallSeconds, false)
			else
				local x, z = Meteors.landingPoint(C, rand)
				spawnMeteor(x, z, Meteors.rollRarity(C, band, rand), C.Meteors.FallSeconds, false)
			end
			S.nextSpawn = S.t + Meteors.gap(C, Economy.spawnInterval(C, lv.beacon), rand)
		end

		-- landing + dish
		for i = #S.meteors, 1, -1 do
			local m = S.meteors[i]
			if not m.landed and S.t >= m.landAt then
				m.landed = true
				if m.fate == "dish" then
					if Economy.dishCatch(C, lv, m.ore) == "hopper" then
						S.ore.dish += m.ore
						if S.bragAt == nil then S.preBrag.dish += m.ore end
					else
						S.ore.bounced += m.ore
						if S.bragAt == nil then S.preBrag.bounced += m.ore end
					end
					table.remove(S.meteors, i)
				end
			end
		end

		S.fullEma = Economy.fullEma(C, S.fullEma, hopperFull(), dt)
		if S.bragAt == nil then
			S.preBrag.ticks += 1
			if hopperFull() then S.preBrag.full += 1 end
		end

		-- smelter
		S.minted += Economy.melt(C, lv, dt)

		-- a minimal pathing bot: grabs one meteor every pokeEvery seconds and nothing else
		if opts.pokeEvery and S.t - S.lastHand >= opts.pokeEvery then
			for i, m in S.meteors do
				if m.landed and m.rarity ~= "legendary" and not hopperFull() then
					Economy.collect(C, lv, m.rarity, m.ore)
					S.ore.hand += m.ore
					S.lastHand = S.t
					table.remove(S.meteors, i)
					break
				end
			end
		end

		if opts.afk then
			if opts.afkBuyEvery and not opts.freezeBuilds and S.t - S.lastShop >= opts.afkBuyEvery then
				S.lastShop = S.t
				while buyOne() do end
			end
		else
			if band >= C.Hazards.FirstBand and S.t >= S.nextHaz then
				S.hazards += 1
				local hit = rand() < prof.hit
				if hit then S.hits += 1 end
				S.busyUntil = math.max(S.busyUntil, S.t) + (if hit then C.Pacing.HazardHitCost else C.Pacing.HazardDodgeCost)
				S.nextHaz = S.t + C.Hazards.IntervalMin + (C.Hazards.IntervalMax - C.Hazards.IntervalMin) * rand()
			end
			if not opts.freezeBuilds and S.t >= S.busyUntil and S.t - S.lastShop >= prof.shopEvery then
				S.lastShop = S.t
				local n = 0
				while buyOne() do n += 1 end
				S.busyUntil = S.t + n * prof.buyTime
			end
			if S.t >= S.busyUntil then
				if S.target and table.find(S.meteors, S.target) == nil then S.target = nil end
				if S.target == nil then
					local full = hopperFull()
					local best, bestD, bestPri = nil, math.huge, -1
					for _, m in S.meteors do
						if m.fate ~= "dish" and (not full or m.rarity == "legendary") then
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
				if S.target and S.t >= S.waitUntil then
					local m = S.target
					local dx, dz = m.x - S.px, m.z - S.pz
					local d = math.sqrt(dx * dx + dz * dz)
					if Meteors.inPickup(C, S.px, S.pz, m.x, m.z) then
						if m.landed then
							local res = Economy.collect(C, lv, m.rarity, m.ore)
							if res ~= "refused" then
								if res == "instant" then
									S.minted += m.ore
									S.ore.legendHand += m.ore
								end
								S.ore.hand += m.ore
								S.lastHand = S.t
								if S.firstPickupAt == nil then S.firstPickupAt = S.t end
								if m.star and S.bragAt == nil then S.bragAt = S.t end
								table.remove(S.meteors, table.find(S.meteors, m) :: number)
								S.target = nil
							end
						end
					else
						local step = math.min(d - C.Meteors.PickupRadius * 0.5, C.Trace.WalkSpeed * prof.eff * dt)
						S.px += dx / d * step
						S.pz += dz / d * step
					end
				end
			end
		end
	end
	return S
end

function M.pct(t, p)
	local s = table.clone(t)
	table.sort(s)
	if #s == 0 then return 0 end
	local i = math.clamp(math.floor(p * (#s - 1) + 0.5) + 1, 1, #s)
	return s[i]
end

return M
