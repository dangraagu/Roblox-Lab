--!strict
-- Guard.luau - the movement check (DESIGN.md §2.7, §10). Pure.
--
-- A counted player whose server-seen root moves more than MaxStuds in any trailing WindowSeconds, or leaves the
-- island box by more than BoxMargin, is swept out ("Movement check failed"). Walking is 16 studs/s; the margin
-- absorbs network bunching (tests/Guard.spec.luau walks 300 honest minutes through jitter and lag and never trips).
-- Every server teleport calls reset(): the guard forgets the old position and stays quiet for ResetSeconds, keeping
-- nothing it sees in that time (a late-replicated old position is not the player moving; REVIEW-1 F10).
-- The hit tests are 2-D or cell-decided, so flying gains nothing; this catches the rest: teleports and speed hacks.

local Guard = {}

function Guard.new(): any
	return { samples = {}, quietUntil = -math.huge, span = 0 }
end

function Guard.reset(g: any, cfg: any, now: number)
	table.clear(g.samples)
	g.quietUntil = now + cfg.Guard.ResetSeconds
	g.span = 0
end

-- The longest distance from the latest sample to any other sample in the window (for measurement).
function Guard.lastSpan(g: any): number
	return g.span
end

-- One server sample. box = the island's half size (nil when the player is not on the island).
-- -> "ok" | "speed" | "box"
function Guard.sample(g: any, cfg: any, now: number, x: number, z: number, box: number?): string
	local gc = cfg.Guard
	if now < g.quietUntil then
		-- quiet after a server teleport: a position seen now may be the OLD spot replicated late (REVIEW-1 F10: one
		-- stale deck sample swept every dropped player a second later), so nothing seen here is kept. The guard judges
		-- movement from the first sample after the quiet second. A teleport inside it only changes where you start,
		-- on the island (off it is the sea), 4 s before the disaster is named.
		table.clear(g.samples)
		g.span = 0
		return "ok"
	end
	local keep = {}
	for _, s in g.samples do
		if now - s.t <= gc.WindowSeconds + 1e-9 then table.insert(keep, s) end
	end
	g.samples = keep
	local span = 0
	for _, s in keep do
		local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
		if d > span then span = d end
	end
	g.span = span
	table.insert(g.samples, { t = now, x = x, z = z })
	if box ~= nil and (math.abs(x) > box + gc.BoxMargin or math.abs(z) > box + gc.BoxMargin) then return "box" end
	if span > gc.MaxStuds then return "speed" end
	return "ok"
end

return Guard
