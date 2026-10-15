-- BandMinutes: when does each season band arrive? A report, not a test (EYECANDY.md quotes it).
-- Run: luau tests/BandMinutes.luau
--
-- For each profile, 40 campaigns (the seeds tests/Pacing.spec.luau uses), then the endless Moonlit Bed on a
-- fresh bed for those who cleared wave 40. Prints the median minutes of play (resting excluded) at which the
-- garden's progress first reaches each band's `from` (= that wave survived), and how many runs got there.

local G = require("./GardenModel")
local cfg = G.Config
local bands = cfg.Env.Bands

local SAMPLES = 40
local function median(t)
	if #t == 0 then return nil end
	local s = table.clone(t)
	table.sort(s)
	return s[math.floor(#s / 2) + 1]
end

for _, profName in { "weak", "normal", "strong" } do
	local prof = cfg.Pacing.Profiles[profName]
	local at = {}
	for _, b in bands do at[b.id] = {} end
	for s = 1, SAMPLES do
		local c = G.campaign(cfg, prof, 90000 + s, {})
		local minuteAt = table.clone(c.minuteAtWave)
		if c.minuteAtWave[40] then
			-- the endless chapter on a fresh bed, clocked the way campaign() clocks a chapter
			local rand = G.newRng(123456 + s)
			local path = G.genPath(cfg, rand)
			local r = G.playChapter(cfg, #cfg.Chapters, path, prof, rand, { maxWave = 60 })
			local clock = c.minutes * 60 + r.intro
			for i, pw in r.perWave do
				if i > 1 then clock += math.min(prof.buildSeconds, cfg.BuildSeconds) end
				clock += pw.seconds
				if not pw.lost and minuteAt[pw.wave] == nil then minuteAt[pw.wave] = clock / 60 end
			end
		end
		for _, b in bands do
			local m = if b.from == 0 then 0 else minuteAt[b.from]
			if m then table.insert(at[b.id], m) end
		end
	end
	print(("profile %s (%d runs): median minute each band is FULL (its `from` wave survived), runs that got there"):format(profName, SAMPLES))
	for _, b in bands do
		local m = median(at[b.id])
		print(("  %-9s from %2d  %s  %2d/%d"):format(b.id, b.from, if m then string.format("%5.1f min", m) else "    -    ", #at[b.id], SAMPLES))
	end
end
