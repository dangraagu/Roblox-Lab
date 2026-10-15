--!strict
-- Recycle.luau — the prestige: its requirement, the checks in order, the new run (all or nothing), grades. PURE.
--
-- DESIGN.md section 9.2. Recycle k (k = bolts + 1) unlocks once the line ships Rate0 x RateGrowth^(k-1) rockets
-- per second, jams counted (the server's own flow, which reads only server state: price-checked purchases and
-- jam fixes checked against the trusted position). It pays exactly one Gold Bolt. The checks, in order:
-- the profile has loaded; the session is saving (a recycle needs its save: a bolt that vanished at the next
-- join would wipe a run for nothing); no recycle or write of this session is in flight; the rate.
-- nextRun() builds the new run as a NEW table and touches nothing: the server writes it in ONE owner-checked
-- UpdateAsync and swaps it in only when that write lands, so a failed write changes nothing.
-- The functions that need the flow take the Line module as an argument (a bare require is invalid in Roblox).
-- Spec: tests/Recycle.spec.luau.

local Recycle = {}

function Recycle.requirement(cfg: any, bolts: number): number
	return cfg.Recycle.Rate0 * cfg.Recycle.RateGrowth ^ math.max(0, bolts)
end

-- Rockets per second the line ships right now, jams counted.
function Recycle.rocketRate(cfg: any, Line: any, S: { any }): number
	return Line.flow(cfg, S)[7]
end

-- (ok, why, rate, need). ctx = { loaded, saving, busy }. why: loading | notsaving | busy | rate | ok.
function Recycle.check(cfg: any, Line: any, d: any, ctx: any): (boolean, string, number, number)
	local need = Recycle.requirement(cfg, d.bolts)
	if not ctx.loaded then return false, "loading", 0, need end
	if not ctx.saving then return false, "notsaving", 0, need end
	if ctx.busy then return false, "busy", 0, need end
	local rate = Recycle.rocketRate(cfg, Line, Line.ordered(cfg, d.stations))
	if rate < need - 1e-9 then return false, "rate", rate, need end
	return true, "ok", rate, need
end

-- The new run, as a fresh table. The current profile `d` is not modified.
function Recycle.nextRun(cfg: any, d: any, now: number): any
	local stations = {}
	for t, id in cfg.Stations.Order do
		stations[id] = { n = if t == 1 then 1 else 0, L = 1, jam = { 0, 0 } }
	end
	return {
		v = d.v,
		cash = 0,
		stations = stations,
		jams = { jamIn = d.jams.jamIn, sputter = nil },
		tier = 0,
		bolts = d.bolts + 1,
		boltsAt = now,
		tutorial = d.tutorial,
	}
end

-- Index into cfg.Grades for a bolt count (0 -> Rusty ... GoldenBolts and more -> Gold).
function Recycle.grade(cfg: any, bolts: number): number
	local b = if type(bolts) == "number" and bolts == bolts then math.floor(bolts) else 0
	return math.clamp(b + 1, 1, #cfg.Grades)
end

function Recycle.golden(cfg: any, bolts: number): boolean
	return bolts >= cfg.Recycle.GoldenBolts
end

function Recycle.text(cfg: any, why: string, rate: number?, need: number?): string
	local function short(n: number): string
		if n < 1000 then return tostring(math.floor(n)) end
		local suffix = { "K", "M", "B", "T", "Qa", "Qi" }
		local i, v = 0, n
		while v >= 1000 and i < #suffix do
			v /= 1000
			i += 1
		end
		if v < 100 then return string.format("%.1f%s", math.floor(v * 10) / 10, suffix[i]) end
		return string.format("%d%s", math.floor(v), suffix[i])
	end
	if why == "rate" then
		return string.format("Ship %s rockets a second to recycle (now %s/s)", short(need or 0), short(math.max(0, rate or 0)))
	elseif why == "notsaving" then
		return "Recycling needs your save, and it is not being saved this session. Rejoin to recycle."
	elseif why == "busy" then
		return "Recycling… one moment"
	elseif why == "loading" then
		return "Loading your factory…"
	elseif why == "retry" then
		-- REVIEW-2 X3: the hold after a failed write; `rate` carries the seconds left
		return string.format("The save is having trouble. Nothing changed: try again in %d s.", math.max(1, math.ceil(rate or 0)))
	end
	return "The recycle didn't save. Nothing changed. Try again in a moment."
end

return Recycle
