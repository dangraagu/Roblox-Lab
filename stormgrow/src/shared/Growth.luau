--!strict
-- Growth.luau — ripeness on the server clock (DESIGN.md §2.5, §8.1). Pure, no requires.
--
-- Stateless on purpose: a crop planted at `at` with grow time `grow` is ripe from at + grow on, so it keeps
-- growing while its owner is offline with no code at all. The server's rule is strict (isRipe); the client
-- shows "ripe" `lead` seconds later (shownRipe), so a tap it offers is always one the server accepts.

local Growth = {}

function Growth.isRipe(now: number, at: number, grow: number): boolean
	return now >= at + grow
end

function Growth.shownRipe(now: number, at: number, grow: number, lead: number): boolean
	return now >= at + grow + lead
end

-- 0 at planting, 1 when ripe
function Growth.stage(now: number, at: number, grow: number): number
	if grow <= 0 then return 1 end
	return math.clamp((now - at) / grow, 0, 1)
end

function Growth.remaining(now: number, at: number, grow: number): number
	return math.max(0, at + grow - now)
end

return Growth
