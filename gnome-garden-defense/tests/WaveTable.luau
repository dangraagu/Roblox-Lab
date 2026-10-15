-- WaveTable: every wave, measured. Run: luau tests/WaveTable.luau [weak|normal|strong]
-- A report, not a test (no assertions): DESIGN.md §5 quotes its output for the normal profile.
-- For each chapter 1-5 it plays SAMPLES beds (the same seeds as Pacing.spec's win rates) and prints,
-- per wave: bugs, total hit points, the median wave length in seconds, the median and worst carrots
-- left after it, how many beds LOST on it, and the median gnome count and summed gnome levels.

local G = require("./GardenModel")
local cfg = G.Config
local profName = (... :: any) or "normal"
local prof = cfg.Pacing.Profiles[profName]
assert(prof, "unknown profile " .. tostring(profName))

local SAMPLES = 40
local rows = {}
for ch = 1, #cfg.Chapters do
	for s = 1, SAMPLES do
		local rand = G.newRng(50000 + s * 7 + ch)
		local path = G.genPath(cfg, rand)
		local r = G.playChapter(cfg, ch, path, prof, rand, { maxWave = 70 })
		for _, pw in r.perWave do
			rows[pw.wave] = rows[pw.wave] or {}
			table.insert(rows[pw.wave], pw)
		end
	end
end

local function median(t: { number }): number
	local s = table.clone(t)
	table.sort(s)
	return s[math.floor(#s / 2) + 1]
end

print(("profile %s, %d beds per chapter"):format(profName, SAMPLES))
print("wave  bugs   totalHP  sec  carrots(med/min)  lost  gnomes levels  played")
local waves = {}
for n in rows do table.insert(waves, n) end
table.sort(waves)
for _, n in waves do
	local w = G.wave(cfg, n)
	local r = rows[n]
	local secs, carrots, gnomes, levels, lost, worst = {}, {}, {}, {}, 0, math.huge
	for _, pw in r do
		table.insert(secs, pw.seconds)
		table.insert(carrots, pw.carrots)
		table.insert(gnomes, pw.gnomes)
		table.insert(levels, pw.levels)
		if pw.lost then lost += 1 end
		worst = math.min(worst, pw.carrots)
	end
	print(("%4d %5d %9d %4d  %6d / %3d  %5d  %6d %6d  %6d"):format(n, w.count, math.round(w.totalHp), math.round(median(secs)),
		median(carrots), worst, lost, median(gnomes), median(levels), #r))
end
