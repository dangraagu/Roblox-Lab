--!strict
-- Waves.luau: what wave n sends, and what it pays (DESIGN.md §3.4-§3.5). Pure, no Roblox globals.
--
-- Wave n has 8 + floor((n - 1) x 0.5) bugs, split among the kinds that have joined by their mix weights
-- (largest remainder) and interleaved deterministically (smooth weighted round robin). A boss wave (every
-- tenth) sends half the count, then its boss 2 s after the last of them. There is NO randomness here: the
-- HUD previews the next wave honestly, and the path is the only procedural part of a bed.
-- The same code as tests/GardenModel.luau's waves; tests/Waves.spec.luau pins thirteen of them.

local Waves = {}

function Waves.hpMult(cfg: any, n: number): number
	return cfg.HpGrowth ^ (n - 1)
end

function Waves.chapterOf(cfg: any, n: number): number
	return math.min(#cfg.Chapters, math.floor((n - 1) / cfg.WavesPerChapter) + 1)
end

function Waves.chapterFirstWave(cfg: any, chapter: number): number
	return (chapter - 1) * cfg.WavesPerChapter + 1
end

-- 1..WavesPerChapter: wave 30 is the tenth of chapter 3; the endless chapter keeps counting in tens too
function Waves.waveInChapter(cfg: any, n: number): number
	return (n - 1) % cfg.WavesPerChapter + 1
end

function Waves.isBoss(cfg: any, n: number): boolean
	return n % cfg.WavesPerChapter == 0
end

function Waves.bossOf(cfg: any, n: number): string?
	if not Waves.isBoss(cfg, n) then return nil end
	local cyc = cfg.BossCycle
	return cyc[((n / cfg.WavesPerChapter) - 1) % #cyc + 1]
end

-- { bugs = { { kind, at, hp } } in spawn order, boss, totalHp, count }
function Waves.wave(cfg: any, n: number): any
	local count = cfg.WaveCount.base + math.floor((n - 1) * cfg.WaveCount.perWave)
	local mult = Waves.hpMult(cfg, n)
	local kinds = {}
	for name, b in cfg.Bugs do
		if not b.boss and n >= b.firstWave then
			table.insert(kinds, { name = name, w = b.weight })
		end
	end
	table.sort(kinds, function(a, b) return a.name < b.name end)
	-- Summed in name order, AFTER the sort: a float sum taken in table order depends on the order the table
	-- happens to iterate in, and its last bit decides ties in the round robin below (seen: wave 6's last two
	-- bugs swapped between two runs on a runtime whose string hashes are seeded per process).
	local wsum = 0
	for _, k in kinds do wsum += k.w end
	local boss = Waves.isBoss(cfg, n)
	local regular = if boss then math.ceil(count / 2) else count
	-- largest-remainder split, then interleave (smooth weighted round robin: deterministic, mixed)
	local quota, rem = {}, {}
	local given = 0
	for _, k in kinds do
		local q = regular * k.w / wsum
		quota[k.name] = math.floor(q)
		rem[k.name] = q - math.floor(q)
		given += quota[k.name]
	end
	while given < regular do
		local best, bestR = nil, -1
		for _, k in kinds do
			if rem[k.name] > bestR then best, bestR = k.name, rem[k.name] end
		end
		quota[best] += 1
		rem[best] = -1
		given += 1
	end
	local order = {}
	local credit = {}
	for _, k in kinds do credit[k.name] = 0 end
	for _ = 1, regular do
		local best, bestC = nil, -math.huge
		for _, k in kinds do
			if quota[k.name] > 0 then
				credit[k.name] += k.w
				if credit[k.name] > bestC then best, bestC = k.name, credit[k.name] end
			end
		end
		credit[best] -= wsum
		quota[best] -= 1
		table.insert(order, best)
	end
	local bugs, total = {}, 0
	for i, name in order do
		local hp = cfg.Bugs[name].hp * mult
		table.insert(bugs, { kind = name, at = (i - 1) * cfg.SpawnGap, hp = hp })
		total += hp
	end
	if boss then
		local name = Waves.bossOf(cfg, n) :: string
		local hp = cfg.Bugs[name].hp * mult
		table.insert(bugs, { kind = name, at = regular * cfg.SpawnGap + 2, hp = hp })
		total += hp
	end
	return { bugs = bugs, boss = boss, totalHp = total, count = #bugs }
end

-- Seeds for stopping a bug of `kind` in wave n: the kind's base x hpMult^BountyExp, rounded.
function Waves.bounty(cfg: any, kind: string, n: number): number
	return math.floor(cfg.Bugs[kind].bounty * Waves.hpMult(cfg, n) ^ cfg.BountyExp + 0.5)
end

-- Seeds for surviving wave n: 15 + 3 x its number inside the chapter (18 after wave 1, 45 after a boss).
function Waves.clearBonus(cfg: any, n: number): number
	return cfg.ClearBonus + cfg.ClearBonusPerWave * Waves.waveInChapter(cfg, n)
end

-- "6 Aphids, 3 Ants" (+ " + Stag Beetle" on a boss wave): what the HUD shows for the next wave.
function Waves.preview(cfg: any, n: number): string
	local w = Waves.wave(cfg, n)
	local counts, bossName = {}, nil
	for _, b in w.bugs do
		local def = cfg.Bugs[b.kind]
		if def.boss then
			bossName = def.name
		else
			counts[b.kind] = (counts[b.kind] or 0) + 1
		end
	end
	local list = {}
	for kind, c in counts do table.insert(list, { kind = kind, c = c }) end
	table.sort(list, function(a, b)
		if a.c ~= b.c then return a.c > b.c end
		local fa, fb = cfg.Bugs[a.kind].firstWave, cfg.Bugs[b.kind].firstWave
		if fa ~= fb then return fa < fb end
		return a.kind < b.kind
	end)
	local parts = {}
	for _, e in list do
		local name = cfg.Bugs[e.kind].name
		table.insert(parts, e.c .. " " .. name .. (if e.c == 1 then "" else "s"))
	end
	local text = table.concat(parts, ", ")
	if bossName then text ..= " + " .. bossName end
	return text
end

return Waves
