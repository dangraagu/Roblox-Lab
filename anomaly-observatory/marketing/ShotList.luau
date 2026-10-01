-- ShotList.luau — the thumbnail shot list for the night Studio session. THE ONLY COPY.
--
-- (review 2026-09-30, finding 6) The list used to live twice: as prose in EYECANDY.md §9, which the night
-- shift reads, and as data in robloxemu/check_anomalyobservatory_shots.luau, which the gate plays. The
-- luau CLI cannot read a markdown file, so the gate only ever checked its own copy: swapping every
-- left/right in the prose (the review round's first finding, re-applied) left it green. Now:
--   * this file is the list. The gate plays it against the real sky (`require`s it), and the night
--     shift prints it: from anomaly-observatory/, `luau marketing/print_shotlist.luau` (luau.exe is under
--     C:/Users/BAHS_A~1/AppData/Local/Temp/claude/); or read the table below, it is plain words;
--   * a SIDE of the frame (left, right, upper, lower, top, bottom, centre, middle) may enter the prose
--     only through a callout's `where`, which the gate measures, or through the moon's lit side, which
--     it also measures. The gate fails if any other text here names a side;
--   * every `at = { sx, sy }` is a measurement the gate repeats (within 0.05): sx -1 is the frame's
--     left edge, +1 its right; sy -1 the bottom, +1 the top.
-- Roblox's camera frame, looking OUT of the entrance (+Z): its RightVector is -X, so a positive azimuth
-- in Config.Sky (toward +X) lands on the photograph's left.
--
-- where: "upper" / "lower" (halves), "top" / "bottom" (thirds up), "left" / "right" (halves),
-- "left third" / "right third", "centre" (the middle third across), combined with spaces.
-- A callout is a sky part's name, a pattern ("^Ridge%d": the group's centre, `min` members in frame) or a
-- beam pattern ("beam:^Aurora%d": beams with both ends in frame, their centre).
-- weather (2026-10-01, pass 2): the band's own weather falling at the shot (a Config.Sky.Weather kind, "rain", or
-- "clear"); the gate measures it, and the note must say it, so the night shift is not surprised by a flake.

local ShotList = {}

ShotList.version = "2026-10-01 (one copy; review 2026-09-30 finding 6; each shot's weather)"
-- EYECANDY.md §9 step 5: seconds to wait after setting the Day (the gate proves the sky has settled)
ShotList.waitSeconds = 45
-- EYECANDY.md §9 step 6: 20 s into a break the view has turned toward this side (things drift the other way)
ShotList.pan = { toward = "left", seconds = 20, mercuryFrom = 0.74, mercuryTo = 0.90 }

ShotList.shots = {
	{ n = 1, title = "The caretaker at the door (hero)", day = 10, moonWords = "waxing gibbous", weather = "snow",
		cam = { kind = "custom", from = { 2, 5.5, -2 }, at = { -12, 21, 96 } },
		camNote = "inside the hall, 12 studs back from the entrance; the caretaker parked (step 8)",
		avatar = { at = { -5.5, 3.5, 8.5 }, lookAt = { -90, 3.5, 700 }, where = "lower right third", sxy = { 0.44, -0.54 },
			say = "the caretaker standing in the doorway, whole, looking out (about 40% of the frame's height)" },
		rim = "the whole doorway (both walls, the floor edge and the ceiling edge) framing the night",
		must = {
			{ "Moon", "upper right", at = { 0.21, 0.49 }, say = "the MOON" },
			{ "beam:^Aurora%d", "centre", min = 2, say = "two aurora curtains over the ridge line" },
			{ "^Ridge%d", "bottom", min = 3, say = "the ridge line" },
			{ "^ValleyLight%d", "lower", min = 3, say = "the valley lights" },
		},
		note = "Only the hall's last 12 studs are in frame and no anomaly lives there (the nearest objects, Fixture1, the StartPad and the Plant, are behind the lens), so any pass will do. Light snow falls beyond the doorway (the Aurora's weather): take a frame where no flake crosses the caretaker." },
	{ n = 2, title = "The Great Comet", day = 17, moonWords = "waning gibbous", cam = { kind = "break" }, weather = "frost",
		note = "Frost glitters round the camera (the Comet's weather: diamond dust); a few sparks near the lens are welcome, a spark on the comet's head is not.",
		must = {
			{ "CometHead", "upper left", at = { -0.28, 0.44 }, say = "the comet's head and coma" },
			{ "beam:^CometTail$", "upper left", min = 1, say = "its tail, sweeping away from the head" },
			{ "Moon", "upper right", at = { 0.36, 0.35 }, say = "the MOON" },
			{ "^Ridge%d", "bottom", min = 3, say = "ridge silhouettes" },
		} },
	{ n = 3, title = "Storm Front", day = 25, cam = { kind = "custom", from = { 6, 4, 16 }, at = { -20, 11, 112 } },
		camNote = "just outside the entrance",
		bolt = { flashes = 13 }, rain = true, weather = "rain",
		must = {
			{ "^StormCloud%d", "centre", min = 9, at = { 0.02, -0.05 }, say = "the dark cloud bank (all nine clouds)" },
		},
		note = "Rain streaks fall through the foreground (the rain falls 14-74 studs in front of this camera), and a lightning bolt flashes inside the bank. A flash lasts 0.14 s, so record a minute and take the frame from the clip; the headless minute's flashes are counted below, every one wholly in frame." },
	{ n = 4, title = "Deep Sky (the headline, ~34 min in)", day = 33, moonWords = "waxing crescent", cam = { kind = "break" }, weather = "clear",
		must = {
			{ "^Nebula%d", "upper left", min = 5, at = { -0.37, 0.56 }, say = "the nebula clouds" },
			{ "MilkyWay", "top", at = { 0.13, 0.85 }, say = "the Milky Way band, tilted" },
			{ "Galaxy", "upper right", at = { 0.49, 0.87 }, say = "the distant galaxy" },
			{ "Moon", "upper right", at = { 0.36, 0.35 }, say = "the MOON" },
			{ "^Ridge%d", "bottom", min = 3, say = "the ridge line" },
		},
		note = "A full star field behind it all. A clear sky: nothing falls in Deep Sky (its band says why)." },
	{ n = 5, title = "The Alignment", day = 44, moonWords = "full", cam = { kind = "break" }, weather = "leaves",
		must = {
			{ "Mercury", "lower right", at = { 0.74, -0.07 }, say = "Mercury, the first of five planets on one diagonal" },
			{ "Venus", "right", say = "Venus" },
			{ "Mars", "centre", say = "Mars" },
			{ "Jupiter", "centre", say = "Jupiter" },
			{ "Saturn", "upper left", at = { -0.45, 0.41 }, say = "ringed Saturn, the last" },
		},
		moonAbove = "Venus",
		note = "Faint nebulae behind. A few dry leaves blow past the lens (the Alignment's weather): take a frame where none crosses a planet." },
	{ n = 6, title = "The Other Sky", day = 52, moonWords = "waning crescent", weather = "motes",
		cam = { kind = "custom", from = { 0, 10, 20 }, at = { 0, 84, 87 } },
		camNote = "straight out, 48 degrees up",
		must = {
			{ "^RingArc%d", "upper", min = 18, say = "the vast pale ring (all 18 segments)" },
			{ "Moon2", "left", at = { -0.29, -0.10 }, say = "the pale-green second moon" },
			{ "^Turning%d", "right", min = 12, say = "the turning spiral of stars" },
			{ "Moon", "lower right", at = { 0.34, -0.47 }, say = "the MOON" },
		},
		note = "No ridge, no hall. Eerie on purpose: pale motes rise slowly past the lens (its weather), and nothing else moves near." },
}

-- Words that name a side of the frame. Only `where` fields and the derived lit side may carry them.
ShotList.SIDE_WORDS = { "left", "right", "upper", "lower", "top", "bottom", "centre", "center", "middle" }

-- Every free-text field of the list (for the gate's side-word scan).
function ShotList.freeText(list: any): { string }
	local out = {}
	local function add(s)
		if type(s) == "string" then table.insert(out, s) end
	end
	for _, shot in list.shots do
		add(shot.title); add(shot.camNote); add(shot.rim); add(shot.note)
		if shot.avatar then add(shot.avatar.say) end
		for _, c in shot.must do add(c.say) end
	end
	return out
end

local function signed(v: number): string
	return string.format("%+.2f", v)
end

-- The moon's lit side on screen, from its phase words (the gate measures it).
function ShotList.litSide(moonWords: string?): string?
	if moonWords == nil or string.find(moonWords, "full", 1, true) then return nil end
	return if string.find(moonWords, "waxing", 1, true) then "right" else "left"
end

-- One callout as prose: "{say}, {where} (sx .., sy ..)", with the moon's phase and lit side filled in.
function ShotList.calloutText(shot: any, c: any): string
	local say = c.say or c[1]
	if string.find(say, "MOON", 1, true) then
		local words = shot.moonWords or "moon"
		say = string.gsub(say, "MOON", words .. " moon")
		local lit = ShotList.litSide(shot.moonWords)
		if lit then
			say = say .. " (lit on its " .. lit .. ")"
		end
	end
	local where = if c[2] ~= "" then c[2] else nil
	local at = if c.at then string.format("sx %s, sy %s", signed(c.at[1]), signed(c.at[2])) else nil
	local t = "**" .. say .. "**"
	if where then t ..= ", " .. where end
	if at then t ..= " (" .. at .. ")" end
	return t
end

-- The table the night shift works from (markdown).
function ShotList.render(list: any?): string
	local L = list or ShotList
	local rows = {
		"Shot list " .. L.version .. ". Set each Day, then wait " .. L.waitSeconds .. " s. sx -1 = left edge .. +1 = right edge; sy -1 = bottom .. +1 = top.",
		"",
		"| # | shot | Day | camera | must be in frame |",
		"|---|---|---|---|---|",
	}
	for _, s in L.shots do
		local cam
		if s.cam.kind == "break" then
			cam = "break view (B), capture about 1 s in"
		else
			cam = string.format("custom, FROM `%s` AT `%s`", table.concat(s.cam.from, ", "), table.concat(s.cam.at, ", "))
			if s.camNote then cam ..= " (" .. s.camNote .. ")" end
		end
		local parts = {}
		if s.rim then table.insert(parts, s.rim) end
		if s.avatar then
			table.insert(parts, string.format("**%s**, %s (centre sx %s, sy %s)", s.avatar.say, s.avatar.where,
				signed(s.avatar.sxy[1]), signed(s.avatar.sxy[2])))
		end
		for _, c in s.must do
			table.insert(parts, ShotList.calloutText(s, c))
		end
		if s.moonAbove then
			table.insert(parts, "the " .. (s.moonWords or "") .. " moon directly above " .. s.moonAbove)
		end
		if s.bolt then
			table.insert(parts, string.format("lightning: %d flashes in the headless minute", s.bolt.flashes))
		end
		local text = table.concat(parts, "; ")
		if s.note then text ..= ". " .. s.note end
		table.insert(rows, string.format("| %d | %s | %d | %s | %s |", s.n, s.title, s.day, cam, text))
	end
	local p = L.pan
	local away = if p.toward == "left" then "right" else "left"
	table.insert(rows, "")
	table.insert(rows, string.format("Break-view pan: a capture %d s into a break shows the view turned toward the %s (and a little higher), "
		.. "so everything drifts %s and down (Mercury from sx %s to %s).", p.seconds, p.toward, away, signed(p.mercuryFrom), signed(p.mercuryTo)))
	return table.concat(rows, "\n")
end

return ShotList
