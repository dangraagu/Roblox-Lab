--!strict
-- Jams.luau — the jam scheduler: one sputter at a time, its target, sputter -> jam, the fix. PURE; rand injected.
--
-- DESIGN.md section 5. The scheduler state is { jamIn = line-seconds to the next sputter, sputter = nil |
-- { t, m, left } }. It lives in the server's copy of the profile and NEVER replicates: the time and target of
-- the next sputter are future information (the State payload carries only a live sputter). Machine states are
-- the station tables' `jam` arrays: 0 running, 1 sputtering (still working), 2 jammed (stopped).
--
--   * the clock counts down only while at least one machine is built and no sputter is live;
--   * at zero, one random WORKING machine (jam 0) starts to sputter for SputterSeconds, and the next gap is
--     drawn at once (JamMin..JamMax); with nothing working, the gap is simply drawn again;
--   * a sputter left alone jams; the clock then runs again (jams stay until fixed: an untended line degrades);
--   * Jams.fix saves a sputtering machine or fixes a jammed one; a running one is left alone (nil).
-- The game draws from the server's Random.new(); specs and tests/LineModel.luau pass their own LCG.
-- Spec: tests/Jams.spec.luau.

local Jams = {}

function Jams.new(cfg: any, jamIn: number?): any
	return { jamIn = jamIn or cfg.Jams.FirstJamIn, sputter = nil }
end

local function anyBuilt(S: { any }): boolean
	for t = 1, 6 do
		if S[t].n > 0 then return true end
	end
	return false
end

local function draw(cfg: any, rand: () -> number): number
	local J = cfg.Jams
	return J.JamMin + (J.JamMax - J.JamMin) * rand()
end

-- One step of `dt` line-seconds. Returns nil, or { kind = "sputter" | "jammed", t, m }.
function Jams.step(cfg: any, js: any, S: { any }, dt: number, rand: () -> number): any?
	local sp = js.sputter
	if sp ~= nil then
		local st = S[sp.t]
		if st == nil or sp.m > st.n or st.jam[sp.m] ~= 1 then
			js.sputter = nil -- fixed, or the machine is gone: nothing live any more
			return nil
		end
		sp.left -= dt
		if sp.left <= 1e-9 then
			st.jam[sp.m] = 2
			js.sputter = nil
			return { kind = "jammed", t = sp.t, m = sp.m }
		end
		return nil
	end
	if not anyBuilt(S) then return nil end
	js.jamIn -= dt
	if js.jamIn > 1e-9 then return nil end
	local working = {}
	for t = 1, 6 do
		local st = S[t]
		for m = 1, math.min(st.n, 2) do
			if st.jam[m] == 0 then table.insert(working, { t = t, m = m }) end
		end
	end
	js.jamIn = draw(cfg, rand)
	if #working == 0 then return nil end
	local pick = working[math.min(#working, 1 + math.floor(rand() * #working))]
	S[pick.t].jam[pick.m] = 1
	js.sputter = { t = pick.t, m = pick.m, left = cfg.Jams.SputterSeconds }
	return { kind = "sputter", t = pick.t, m = pick.m }
end

-- "saved" (it was sputtering), "fixed" (it was jammed), or nil (it runs fine or does not exist).
function Jams.fix(cfg: any, js: any, S: { any }, t: number, m: number): string?
	local st = S[t]
	if st == nil or type(m) ~= "number" or m < 1 or m > math.min(st.n, 2) then return nil end
	local state = st.jam[m]
	if state == 1 then
		st.jam[m] = 0
		if js.sputter and js.sputter.t == t and js.sputter.m == m then js.sputter = nil end
		return "saved"
	elseif state == 2 then
		st.jam[m] = 0
		return "fixed"
	end
	return nil
end

-- A sputter or a jam anywhere on the line. (The crane held for this until REVIEW-2 R5; it now holds only while a
-- sputter is live, because a jam has no clock and could hold it forever. Kept for the specs and tools.)
function Jams.trouble(js: any, S: { any }): boolean
	if js.sputter ~= nil then return true end
	for t = 1, 6 do
		local st = S[t]
		for m = 1, math.min(st.n, 2) do
			if st.jam[m] ~= 0 then return true end
		end
	end
	return false
end

-- A recycle: the machines are new, so every jam and the live sputter go; the clock keeps counting.
function Jams.clearForRecycle(js: any, S: { any })
	js.sputter = nil
	for t = 1, 6 do
		S[t].jam = { 0, 0 }
	end
end

-- Per station, the machines that are jammed OR sputtering (a live sputter saves as a jam).
function Jams.jammedCounts(S: { any }): { number }
	local out = {}
	for t = 1, 6 do
		local st = S[t]
		local c = 0
		for m = 1, math.min(st.n, 2) do
			if st.jam[m] ~= 0 then c += 1 end
		end
		out[t] = c
	end
	return out
end

-- A saved count back into a machine array: the first `count` machines of `n` load jammed.
function Jams.fromCount(n: number, count: number): { number }
	local c = math.clamp(math.floor(count), 0, math.min(n, 2))
	return { if c >= 1 then 2 else 0, if c >= 2 then 2 else 0 }
end

return Jams
