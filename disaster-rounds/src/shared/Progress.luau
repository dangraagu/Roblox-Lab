--!strict
-- Progress.luau - streak, Heat, survivals, the Codex and the saved profile (DESIGN.md §2.6, §8.1). Pure.
--
--   * a counted survival: survived +1, streak +1, best = max(best, streak) (bestAt = when it was first reached),
--     the disaster's Codex row filled up to the Heat it was survived at;
--   * an elimination (hit, reset, guard, or leaving during a round): streak 0. survived, best and the Codex never
--     go down. Leaving is remembered once (lastEnd) so the rejoin can say what happened;
--   * Heat = min(5, floor(streak / 2));
--   * the profile has string keys only (a DataStore's JSON turns sparse integer keys into strings), and normalise()
--     accepts whatever a DataStore hands back and says what it had to fix.

local Progress = {}

Progress.KINDS = { "meteor", "flood", "tornado", "quake" }

function Progress.default(): any
	return {
		v = 1,
		survived = 0,
		played = 0,
		streak = 0,
		best = 0,
		bestAt = 0,
		codex = { meteor = -1, flood = -1, tornado = -1, quake = -1 },
		lastEnd = nil,
		boardBest = 0, -- the board metric last written to the board (written only when it rises)
		capAt = 0, -- when best first reached Config.Board.StreakCap (the board's tie-break at the cap)
		maxHeat = false, -- MAX HEAT has been told (once per profile)
	}
end

function Progress.heat(cfg: any, streak: number): number
	return math.clamp(math.floor((tonumber(streak) or 0) / cfg.Heat.StreakPerHeat), 0, cfg.Heat.Max)
end

local function bragFrom(cfg: any): number
	for _, b in cfg.Env.Bands do
		if b.id == cfg.Brag.BandId then return b.from end
	end
	return math.huge
end
Progress.bragFrom = bragFrom

-- A counted survival at `heat`, judged at server time `now` (unix seconds for bestAt).
-- -> { newBest, brag, maxHeat }
function Progress.survive(p: any, cfg: any, kind: string, heat: number, now: number): any
	local before = p.survived
	p.survived += 1
	p.streak += 1
	p.played += 1
	local newBest = p.streak > p.best
	if newBest then
		p.best = p.streak
		p.bestAt = now
		if p.best == cfg.Board.StreakCap and (p.capAt or 0) <= 0 then p.capAt = now end
	end
	if p.codex[kind] ~= nil then
		p.codex[kind] = math.max(p.codex[kind], math.clamp(math.floor(heat), 0, cfg.Heat.Max))
	end
	local from = bragFrom(cfg)
	local brag = before < from and p.survived >= from
	local maxHeat = false
	if p.streak >= cfg.Brag.MaxHeatStreak and not p.maxHeat then
		p.maxHeat = true
		maxHeat = true
	end
	return { newBest = newBest, brag = brag, maxHeat = maxHeat }
end

-- An elimination. reason: a disaster kind, "guard", "reset" or "left".
function Progress.eliminate(p: any, reason: string)
	local ended = p.streak
	p.streak = 0
	p.played += 1
	if reason == "left" then
		p.lastEnd = { reason = reason, streak = ended }
	end
end

-- What the board ranks (REVIEW-1 F5): the best streak up to Config.Board.StreakCap, and when it was reached. Past the
-- cap the time is when the cap was first reached, so going on never moves a player down a tie.
-- -> metric, reachedAtUnix
function Progress.boardEntry(p: any, cfg: any): (number, number)
	local cap = cfg.Board.StreakCap or math.huge
	if p.best <= cap then return p.best, p.bestAt end
	return cap, if (p.capAt or 0) > 0 then p.capAt else p.bestAt
end

function Progress.takeLastEnd(p: any): any
	local e = p.lastEnd
	p.lastEnd = nil
	return e
end

function Progress.codexString(p: any): string
	local parts = {}
	for _, k in Progress.KINDS do table.insert(parts, tostring(p.codex[k] or -1)) end
	return table.concat(parts, ",")
end

-- Filled entries of the 24 (4 disasters x Heat 0..5).
function Progress.codexCount(p: any): number
	local n = 0
	for _, k in Progress.KINDS do n += (p.codex[k] or -1) + 1 end
	return n
end

-- What a DataStore gets: string keys only.
function Progress.toSave(p: any): any
	local codex = {}
	for _, k in Progress.KINDS do codex[k] = p.codex[k] end
	return {
		v = p.v or 1,
		survived = p.survived,
		played = p.played,
		streak = p.streak,
		best = p.best,
		bestAt = p.bestAt,
		codex = codex,
		lastEnd = if p.lastEnd then { reason = tostring(p.lastEnd.reason), streak = p.lastEnd.streak } else nil,
		boardBest = p.boardBest,
		capAt = p.capAt or 0,
		maxHeat = p.maxHeat == true,
	}
end

-- (profile, warnings, newer). Whatever comes back from a DataStore, made safe to use.
function Progress.normalise(raw: any, cfg: any): (any, { string }, boolean)
	local p = Progress.default()
	local warnings = {}
	if type(raw) ~= "table" then
		return p, warnings, false
	end
	local newer = type(raw.v) == "number" and raw.v > cfg.Version
	local function count(name: string): number
		local v = raw[name]
		if v == nil then return 0 end
		local n = tonumber(v)
		if n == nil or n ~= n then
			table.insert(warnings, name .. " was not a number")
			return 0
		end
		if n < 0 then
			table.insert(warnings, name .. " was negative")
			return 0
		end
		if n % 1 ~= 0 then
			table.insert(warnings, name .. " was not whole")
			n = math.floor(n)
		end
		return n
	end
	p.survived = count("survived")
	p.played = count("played")
	p.streak = count("streak")
	p.best = count("best")
	p.bestAt = count("bestAt")
	p.boardBest = count("boardBest")
	p.capAt = count("capAt")
	if p.best < p.streak then
		table.insert(warnings, "best was below streak")
		p.best = p.streak
	end
	p.maxHeat = raw.maxHeat == true
	local known = {}
	for _, k in Progress.KINDS do known[k] = true end
	if type(raw.codex) == "table" then
		for k, v in raw.codex do
			if not known[k] then
				table.insert(warnings, "codex key " .. tostring(k) .. " dropped")
			end
		end
		for _, k in Progress.KINDS do
			local v = raw.codex[k]
			if v ~= nil then
				local n = tonumber(v)
				if n == nil or n ~= n then
					table.insert(warnings, "codex." .. k .. " was not a number")
				else
					local fixed = math.clamp(math.floor(n), -1, cfg.Heat.Max)
					if fixed ~= n then table.insert(warnings, "codex." .. k .. " was out of range") end
					p.codex[k] = fixed
				end
			end
		end
	elseif raw.codex ~= nil then
		table.insert(warnings, "codex was not a table")
	end
	local le = raw.lastEnd
	if type(le) == "table" and type(le.reason) == "string" and type(le.streak) == "number" then
		p.lastEnd = { reason = le.reason, streak = math.max(0, math.floor(le.streak)) }
	end
	return p, warnings, newer
end

return Progress
