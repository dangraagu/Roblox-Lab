-- Waves.spec: what every wave sends (DESIGN.md §3.4-§3.5). Run: luau tests/Waves.spec.luau
--
-- Waves are a public function of the wave number: no randomness, so the HUD can preview the next wave
-- honestly. The golden rows below were RECORDED from tests/GardenModel.luau (the balance model) before
-- Waves.luau existed: the order string is the first two letters of each bug in spawn order.

local Waves = require("../src/shared/Waves")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local GOLDEN = {
	{ 1, 8, "192.000000", "apapapapapapapap", "6.30", 3, 3, 18, 1 },
	{ 3, 9, "214.946250", "apanapanapapanapap", "7.20", 3, 3, 24, 1 },
	{ 6, 10, "404.847470", "apanapbeapanapanbeap", "8.10", 3, 3, 33, 1 },
	{ 10, 7, "1111.998424", "apanapbeapanst", "7.40", 4, 156, 45, 1 },
	{ 12, 13, "828.637740", "apanwaapbeapanapwaanapbeap", "10.80", 4, 4, 21, 2 },
	{ 15, 15, "1398.241577", "apanwaapbesnapanapwaanapbeapan", "12.60", 4, 3, 30, 2 },
	{ 20, 10, "3706.497053", "apanwaapbesnapanapba", "10.10", 5, 277, 45, 2 },
	{ 29, 22, "6121.366181", "apanwaapbesnapanapwaanapbeapansnwaapbeapanap", "18.90", 7, 7, 42, 3 },
	{ 30, 12, "11287.784085", "apanwaapbesnapanapwaanqu", "11.90", 7, 509, 45, 3 },
	{ 40, 15, "19705.987489", "apanwaapbesnapanapwaanapbeapma", "14.60", 9, 803, 45, 4 },
	{ 41, 28, "19559.955043", "apanwaapbesnapanapwaanapbeapansnwaapbeapanapwaanapsnbeap", "24.30", 10, 10, 18, 5 },
	{ 50, 17, "36255.677992", "apanwaapbesnapanapwaanapbeapansnst", "16.40", 12, 495, 45, 5 },
	{ 57, 36, "75302.229227", "apanwaapbesnapanapwaanapbeapansnwaapbeapanapwaanapsnbeapanwaapanapbeapwa", "31.50", 15, 25, 36, 5 },
}
for _, g in GOLDEN do
	local n = g[1]
	local w = Waves.wave(Config, n)
	eq(w.count, g[2], "wave " .. n .. ": bug count")
	eq(string.format("%.6f", w.totalHp), g[3], "wave " .. n .. ": total hit points")
	local order = {}
	for _, b in w.bugs do table.insert(order, string.sub(b.kind, 1, 2)) end
	eq(table.concat(order, ""), g[4], "wave " .. n .. ": spawn order")
	eq(string.format("%.2f", w.bugs[#w.bugs].at), g[5], "wave " .. n .. ": the last bug's spawn time")
	eq(Waves.bounty(Config, "aphid", n), g[6], "wave " .. n .. ": an aphid's bounty")
	eq(Waves.bounty(Config, w.bugs[#w.bugs].kind, n), g[7], "wave " .. n .. ": the last bug's bounty")
	eq(Waves.clearBonus(Config, n), g[8], "wave " .. n .. ": clear bonus")
	eq(Waves.chapterOf(Config, n), g[9], "wave " .. n .. ": chapter")
end

--====================================================================== structure
do
	local okBoss, okCycle, okCount, okGrow = true, true, true, true
	for n = 1, 120 do
		local w = Waves.wave(Config, n)
		local isBoss = n % Config.WavesPerChapter == 0
		if w.boss ~= isBoss or Waves.isBoss(Config, n) ~= isBoss then okBoss = false end
		if isBoss then
			local want = Config.BossCycle[((n // 10) - 1) % #Config.BossCycle + 1]
			if w.bugs[#w.bugs].kind ~= want or Waves.bossOf(Config, n) ~= want then okCycle = false end
		elseif Waves.bossOf(Config, n) ~= nil then
			okCycle = false
		end
		local full = Config.WaveCount.base + math.floor((n - 1) * Config.WaveCount.perWave)
		local want = if isBoss then math.ceil(full / 2) + 1 else full
		if w.count ~= want or #w.bugs ~= want then okCount = false end
		if n > 1 and not isBoss and not Waves.isBoss(Config, n - 1) and w.totalHp < Waves.wave(Config, n - 1).totalHp * 0.95 then
			okGrow = false
		end
	end
	truthy(okBoss, "a boss on every tenth wave and only there")
	truthy(okCycle, "the bosses come in the cycle Stag, Baron, Queen, Mantis, then repeat")
	truthy(okCount, "a wave has 8 + floor((n-1)/2) bugs; a boss wave half of them plus the boss")
	truthy(okGrow, "a regular wave is never easier than the regular wave before it")
end
do
	eq(Waves.chapterFirstWave(Config, 1), 1, "chapter 1 starts at wave 1")
	eq(Waves.chapterFirstWave(Config, 4), 31, "chapter 4 starts at wave 31")
	eq(Waves.chapterFirstWave(Config, 5), 41, "the endless chapter starts at wave 41")
	eq(Waves.chapterOf(Config, 300), 5, "every wave past 40 is in the endless chapter")
	eq(Waves.waveInChapter(Config, 30), 10, "wave 30 is the tenth of its chapter")
	eq(Waves.waveInChapter(Config, 41), 1, "wave 41 is the first of the endless chapter")
end

--====================================================================== the honest preview
do
	eq(Waves.preview(Config, 1), "8 Aphids", "wave 1's preview")
	eq(Waves.preview(Config, 3), "6 Aphids, 3 Ants", "wave 3's preview, largest group first")
	eq(Waves.preview(Config, 10), "3 Aphids, 2 Ants, 1 Beetle + Stag Beetle", "a boss wave names its boss")
	local w = Waves.wave(Config, 12)
	local counted = 0
	for _, part in string.split(Waves.preview(Config, 12), ", ") do
		counted += tonumber(string.match(part, "^(%d+)")) or 0
	end
	eq(counted, w.count, "a preview counts every bug of the wave")
end

print(("Waves: %d passed, %d failed"):format(passed, failed))
