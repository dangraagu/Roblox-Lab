--!strict
-- Stars.luau: the three stars of a chapter (DESIGN.md §3.7). Pure.
--   Found      every item found before the clock and the looks ran out
--   Swift      Found, the last item found inside the first SwiftFraction (2/3) of the clock
--   Sharp Eye  Found, at most SharpSlips (1) searches of a prop that fit no clue still needed, and no hint
-- A star once earned in a chapter is kept (merge). Profile keys are the strings "c1".."c15".

local Stars = {}

function Stars.compute(found: boolean, finishClock: number, limit: number, off: number, hinted: boolean, cfg: any): any
	local f = found == true
	return {
		f = f,
		w = f and finishClock <= cfg.Search.SwiftFraction * limit + 1e-9,
		s = f and off <= cfg.Search.SharpSlips and not hinted,
	}
end

function Stars.merge(old: any, new: any): any
	old = if type(old) == "table" then old else {}
	new = if type(new) == "table" then new else {}
	return { f = old.f == true or new.f == true, w = old.w == true or new.w == true, s = old.s == true or new.s == true }
end

function Stars.key(chapter: number): string
	return "c" .. tostring(chapter)
end

-- Total stars in a profile's book.stars table.
function Stars.count(stars: any): number
	local n = 0
	if type(stars) ~= "table" then return 0 end
	for _, s in stars do
		if type(s) == "table" then
			if s.f == true then n += 1 end
			if s.w == true then n += 1 end
			if s.s == true then n += 1 end
		end
	end
	return n
end

function Stars.of(stars: any, chapter: number): number
	if type(stars) ~= "table" then return 0 end
	return Stars.count({ stars[Stars.key(chapter)] })
end

return Stars
