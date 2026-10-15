--!strict
-- FinderModel.luau: the pacing model, ported from design/model.py Parts 2-3 and run on the REAL game rules.
-- Rooms come from Dressing.build (the real layout: shelves on the walls, tables, floor props), searching,
-- looks, the clock and the stars from Attempt (the server's state machine), so a number printed here is a
-- property of the game's code under the human assumptions below, not of a separate sketch.
--
-- The human assumptions are the design model's PROFILES, unchanged ([A] in DESIGN.md §0). What this is NOT:
-- a physics or perception model. Walking is a straight line times a detour factor at 16 studs/s times an
-- efficiency, stopping STAND_OFF short of the prop (reach is 10).

local Dressing = require("../src/shared/Dressing")
local Attempt = require("../src/shared/Attempt")
local Rng = require("../src/shared/Rng")

local M = {}

M.WALK_SPEED = 16
M.STAND_OFF = 5
M.GRACE = 5
M.SESSION_START = 4
M.HZ_DODGE = 2.0
M.HZ_KNOCK = 0.6

M.PROFILES = {
	fast = { read = 1.0, tau = 6.0, eff = 0.95, detour = 1.20, select = 0.3, slip = 0.03, hint_at = 0.00, p_hit = 0.05 },
	normal = { read = 1.5, tau = 10.0, eff = 0.85, detour = 1.25, select = 0.4, slip = 0.07, hint_at = 0.30, p_hit = 0.15 },
	slow = { read = 2.5, tau = 16.0, eff = 0.75, detour = 1.30, select = 0.6, slip = 0.12, hint_at = 0.40, p_hit = 0.30 },
}

--============================================================================ randomness
function M.rng(seed: number): any
	local g = Rng.new(seed)
	local r = {}
	function r.next(): number return g:next() end
	function r.below(n: number): number return g:below(n) end
	function r.uniform(a: number, b: number): number return a + (b - a) * g:next() end
	function r.expo(rate: number): number
		local u = g:next()
		if u <= 0 then u = 1e-12 end
		return -math.log(u) / rate
	end
	return r
end

--============================================================================ room pools
-- A pool of real rooms per spec; each attempt takes one at random and draws a FRESH secret, so the secret is
-- never correlated with the pool. (Building every room anew gives the same numbers, slower.)
function M.pool(spec: any, size: number, seed: number, cfg: any): { any }
	local r = M.rng(seed)
	local out = {}
	for i = 1, size do out[i] = Dressing.build(spec, r.next, cfg) end
	return out
end

local function hideInto(a: any, r: any)
	for i = 1, a.n do
		local c = a.room.cands[i]
		a.hidden[i] = c[r.below(#c)]
	end
end

--============================================================================ hazards (the template's clock)
function M.hazardClock(r: any, cfg: any): any
	local hz = cfg.Hazards
	return { exposed = 0, nextAt = r.uniform(hz.IntervalMin, hz.IntervalMax), count = 0, hits = 0, r = r, lo = hz.IntervalMin, hi = hz.IntervalMax }
end

local function expose(hz: any, dt: number, pHit: number): number
	local extra = 0
	hz.exposed += dt
	while hz.exposed >= hz.nextAt do
		hz.count += 1
		extra += M.HZ_DODGE
		if hz.r.next() < pHit then
			hz.hits += 1
			extra += M.HZ_KNOCK
		end
		hz.nextAt += hz.r.uniform(hz.lo, hz.hi)
	end
	return extra
end

--============================================================================ one attempt
-- opts = { clock = number?, looks = boolean (false: unlimited), hint = boolean, hz = clock?, pHit }
local function newRun(room: any, spec: any, cfg: any, opts: any, r: any): any
	local s = table.clone(spec)
	if opts.clock then s.clock = opts.clock end
	if opts.looks == false then s.looks = 1e9 end
	local a = Attempt.new(room, s, cfg, { intro = 0 })
	hideInto(a, r)
	return { a = a, t = 0, pos = { 0, 1 }, hz = opts.hz, pHit = opts.pHit or 0, hazards = 0, first = nil :: number? }
end

-- The game's hazard clock runs only while the player stands on a LEGAL spot: the room shrunk by World.LegalInset and
-- more than LegalInset from the door mat (Room.client.luau `legalSpot`, the same formula). REVIEW-1 round 2 D5: the
-- model had counted every second after the grace, so its near-miss rate was not the game's. The position is where
-- the player stands after the step (a walk is counted at its destination).
function M.legal(run: any): boolean
	local a = run.a
	local W, D = a.spec.W, a.spec.D
	local inset = a.cfg.World.LegalInset
	local lx, lz = run.pos[1], run.pos[2]
	if math.abs(lx) > W / 2 - inset or lz < inset or lz > D - inset then return false end
	local mz = a.cfg.Room.MatDepth / 2
	return math.sqrt(lx * lx + (lz - mz) ^ 2) > inset + mz
end

M.exposure = { all = 0, legal = 0 } -- seconds past the grace, and the share of them on a legal spot (printed by Pacing.spec)

local function spend(run: any, dt: number)
	local a = run.a
	local before = run.t
	Attempt.tick(a, dt)
	run.t += dt
	if run.hz then
		local exposed = math.max(0, run.t - math.max(before, M.GRACE))
		M.exposure.all += exposed
		if not M.legal(run) then exposed = 0 end
		M.exposure.legal += exposed
		if exposed > 0 then
			local n0 = run.hz.count
			local extra = expose(run.hz, exposed, run.pHit)
			if extra > 0 then
				Attempt.tick(a, extra)
				run.t += extra
			end
			run.hazards += run.hz.count - n0
		end
	end
end

local function over(run: any): boolean
	return run.a.state == "done"
end

local function propOf(run: any, id: number): any
	return run.a.byId[id]
end

local function walk(run: any, id: number, eff: number, detour: number)
	local p = propOf(run, id)
	local dx, dz = p.x - run.pos[1], p.z - run.pos[2]
	local d = math.sqrt(dx * dx + dz * dz)
	local travel = math.max(0, d - M.STAND_OFF)
	if d > 0 then
		local f = travel / d
		run.pos = { run.pos[1] + dx * f, run.pos[2] + dz * f }
	end
	if eff > 0 and travel > 0 then spend(run, travel * detour / (M.WALK_SPEED * eff)) end
end

local function search(run: any, id: number, select: number)
	local a = run.a
	if select > 0 then
		spend(run, select)
		if over(run) then return end
	end
	local ok = Attempt.search(a, id)
	if not ok then return end
	local found0 = Attempt.foundCount(a)
	spend(run, a.cfg.Search.Seconds)
	if run.first == nil and Attempt.foundCount(a) > found0 then run.first = run.t end
end

local function unfoundCands(a: any): { [number]: boolean }
	local out = {}
	for i = 1, a.n do
		if not a.found[i] then
			for _, id in a.room.cands[i] do out[id] = true end
		end
	end
	return out
end

local function result(run: any): any
	local a = run.a
	local done = a.state == "done" and a.reason == "found"
	local stars = Attempt.stars(a)
	return {
		found = done, outOfLooks = a.reason == "looks", t = run.t,
		spent = if a.state == "done" then (a.finishClock or a.clock) else a.clock,
		searches = a.searches, off = a.off, hint = a.hint ~= nil, first = run.first, hazards = run.hazards,
		stars = stars,
	}
end

-- One clue at a time, in list order. Notices the next of the clue's m unsearched candidates after Exp(tau'/m),
-- walks to it, taps it twice (select, search). With prob slip, first searches the nearest unsearched prop that
-- fits no unfound clue (a partial match of this clue if one is left). design/model.py play_human.
function M.playHuman(room: any, spec: any, prof: any, r: any, cfg: any, opts: any): any
	local run = newRun(room, spec, cfg, opts, r)
	local a = run.a
	local tau = prof.tau * math.sqrt(spec.S / 36)
	local useHint = opts.hint ~= false
	for ci = 1, a.n do
		if a.found[ci] then continue end
		spend(run, prof.read)
		if over(run) then return result(run) end
		local left = {}
		for _, id in a.room.cands[ci] do
			if not a.searched[id] then table.insert(left, id) end
		end
		while not a.found[ci] do
			if useHint and prof.hint_at > 0 and a.hint == nil and (a.limit - a.clock) < prof.hint_at * a.limit then
				local target = Attempt.hint(a, ci)
				if target then
					walk(run, target, prof.eff, prof.detour)
					if over(run) then return result(run) end
					search(run, target, prof.select)
					if over(run) then return result(run) end
					break
				end
			end
			spend(run, r.expo(#left / tau))
			if over(run) then return result(run) end
			local idx = r.below(#left)
			local sid = left[idx]
			if r.next() < prof.slip then
				local live = unfoundCands(a)
				local clue = a.room.clues[ci]
				local pool, part = {}, {}
				for _, p in a.room.props do
					if not a.searched[p.id] and not live[p.id] then
						table.insert(pool, p)
						if a.room.role[p.id] == "partial" then
							for _, at in cfg.Forms[clue.form] do
								if p[at] == clue[at] then table.insert(part, p) break end
							end
						end
					end
				end
				local list = if #part > 0 then part else pool
				if #list > 0 then
					local best, bd = nil, math.huge
					for _, p in list do
						local d = (p.x - run.pos[1]) ^ 2 + (p.z - run.pos[2]) ^ 2
						if d < bd then best, bd = p, d end
					end
					walk(run, best.id, prof.eff, prof.detour)
					if over(run) then return result(run) end
					search(run, best.id, prof.select)
					if over(run) then return result(run) end
				end
			end
			walk(run, sid, prof.eff, prof.detour)
			if over(run) then return result(run) end
			search(run, sid, prof.select)
			table.remove(left, idx)
			if over(run) then return result(run) end
		end
	end
	return result(run)
end

-- A script with the clue rules: no reading, no noticing, no select tap, never off-clue; nearest unsearched
-- candidate of any unfound clue next; walks straight at exactly WalkSpeed, or teleports.
function M.playBot(room: any, spec: any, r: any, cfg: any, teleport: boolean?): any
	local run = newRun(room, spec, cfg, { clock = 1e9, looks = true }, r)
	local a = run.a
	while a.state ~= "done" do
		local live = unfoundCands(a)
		local best, bd = nil, math.huge
		for id in live do
			if not a.searched[id] then
				local p = propOf(run, id)
				local d = (p.x - run.pos[1]) ^ 2 + (p.z - run.pos[2]) ^ 2
				if d < bd or (d == bd and id < best) then best, bd = id, d end
			end
		end
		if best == nil then break end
		if teleport then
			local p = propOf(run, best)
			run.pos = { p.x, p.z }
		else
			walk(run, best, 1, 1)
		end
		search(run, best, 0)
	end
	return result(run)
end

-- Ignores the clues and taps everything: nearest unsearched prop next, 0.5 s to pick it, normal walking.
function M.playBrute(room: any, spec: any, r: any, cfg: any, opts: any): any
	local run = newRun(room, spec, cfg, opts, r)
	local a = run.a
	local p = M.PROFILES.normal
	while a.state ~= "done" do
		local best, bd = nil, math.huge
		for _, q in a.room.props do
			if not a.searched[q.id] then
				local d = (q.x - run.pos[1]) ^ 2 + (q.z - run.pos[2]) ^ 2
				if d < bd then best, bd = q.id, d end
			end
		end
		if best == nil then break end
		spend(run, 0.5)
		if over(run) then break end
		walk(run, best, p.eff, p.detour)
		if over(run) then break end
		search(run, best, p.select)
	end
	return result(run)
end

-- A systematic human: walks to the nearest prop not yet glanced at, checks it against every unfound chip
-- (0.35 s + 0.1 s per unfound clue), and searches it only if it fits one (or, with prob slip, one that does not).
function M.playSweep(room: any, spec: any, r: any, cfg: any, opts: any, slip: number?): any
	local run = newRun(room, spec, cfg, opts, r)
	local a = run.a
	local p = M.PROFILES.normal
	spend(run, p.read * a.n)
	local seen = {}
	while a.state ~= "done" do
		local best, bd = nil, math.huge
		for _, q in a.room.props do
			if not seen[q.id] then
				local d = (q.x - run.pos[1]) ^ 2 + (q.z - run.pos[2]) ^ 2
				if d < bd then best, bd = q.id, d end
			end
		end
		if best == nil then break end
		seen[best] = true
		walk(run, best, p.eff, p.detour)
		if over(run) then break end
		spend(run, 0.35 + 0.1 * (a.n - Attempt.foundCount(a)))
		if over(run) then break end
		if unfoundCands(a)[best] or r.next() < (slip or 0.05) then search(run, best, p.select) end
	end
	return result(run)
end

--============================================================================ quantiles
function M.q(xs: { number }, p: number): number
	local s = table.clone(xs)
	table.sort(s)
	if #s == 0 then return 0 / 0 end
	local i = math.clamp(math.ceil(p * #s), 1, #s)
	return s[i]
end

function M.median(xs: { number }): number
	local s = table.clone(xs)
	table.sort(s)
	local n = #s
	if n == 0 then return 0 / 0 end
	if n % 2 == 1 then return s[(n + 1) / 2] end
	return (s[n / 2] + s[n / 2 + 1]) / 2
end

function M.mean(xs: { number }): number
	local t = 0
	for _, x in xs do t += x end
	return t / math.max(1, #xs)
end

function M.ceil5(x: number): number
	return 5 * math.ceil(x / 5 - 1e-9)
end

--============================================================================ a career: Book One from a fresh join
-- Returns the minute each chapter was first cleared, the Gold Book minute (or nil), the hazards met on the way
-- to BOOK ONE SOLVED, the first find, the chapter-1 clear and the attempts.
function M.career(pools: { { any } }, specs: { any }, prof: any, r: any, cfg: any, gold: boolean, capMinutes: number?, sweep: boolean?): any
	local C = cfg.Cards
	local hz = M.hazardClock(r, cfg)
	local t = M.SESSION_START
	local clearAt = {}
	local starGot = {}
	for ch = 1, #specs do starGot[ch] = { false, false, false } end
	local firstFind, ch1Clear, attempts = nil, nil, 0
	local function play(ch: number): any
		local pool = pools[ch]
		local room = pool[r.below(#pool)]
		local opts = { hz = hz, pHit = prof.p_hit, looks = true, hint = true }
		if sweep then return M.playSweep(room, specs[ch], r, cfg, opts) end
		return M.playHuman(room, specs[ch], prof, r, cfg, opts)
	end
	for ch = 1, #specs do
		local intro = C.IntroFirst
		while true do
			attempts += 1
			t += intro + C.Move
			intro = C.IntroRetry
			local res = play(ch)
			if firstFind == nil and res.first then firstFind = t + res.first end
			t += res.spent + C.Clear
			local s = res.stars
			starGot[ch] = { starGot[ch][1] or s.f, starGot[ch][2] or s.w, starGot[ch][3] or s.s }
			if res.found then
				clearAt[ch] = t / 60
				if ch == 1 then ch1Clear = t end
				break
			end
		end
	end
	local brag = { hazards = hz.count, hits = hz.hits, exposed = hz.exposed, t = t }
	local goldAt = nil
	if gold then
		local cap = capMinutes or 600
		while t / 60 < cap do
			local missing = {}
			for ch = 1, #specs do
				local g = starGot[ch]
				if not (g[1] and g[2] and g[3]) then table.insert(missing, ch) end
			end
			if #missing == 0 then
				goldAt = t / 60
				break
			end
			for _, ch in missing do
				t += C.IntroRetry + C.Move
				local res = play(ch)
				t += res.spent + C.Clear
				local s = res.stars
				starGot[ch] = { starGot[ch][1] or s.f, starGot[ch][2] or s.w, starGot[ch][3] or s.s }
			end
		end
	end
	return { clearAt = clearAt, goldAt = goldAt, hazards = brag.hazards, hits = brag.hits, exposed = brag.exposed,
		bragT = brag.t, firstFind = firstFind, ch1Clear = ch1Clear, attempts = attempts }
end

return M
