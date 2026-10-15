--!strict
-- Strikes.luau - the rings every disaster aims at each player, scaled by Heat (DESIGN.md §2.4). Pure.
--
-- Per player per round: the first ring comes FirstAfterSeconds + U(0, interval) after the name (or a practice
-- landing), the next ones every interval +-Jitter. A ring's centre is the target's server-seen root at the moment
-- the ring appears and never moves; it lands TelegraphSeconds later and is gone PassSeconds after that. A ring that
-- could not land before the disaster ends is never shown. Two rules keep a crowd of rings fair:
--   * ExitStuds: a ring is placed only if every player it covers can stand outside all red (with a 0.8-stud margin)
--     within ExitStuds, and no player near it who already stands in red loses a way out it had; otherwise it waits
--     RetrySeconds and tries again;
--   * MaxCoverage: live rings never cover more than this share of the walkable area, and never number more than
--     Config.Budget.Rings.
-- The server owns the clock and the positions; this module only answers "when" and "may it". It requires nothing:
-- the exit search (Zones.exitDistance) is passed in, because a string require works only in the luau CLI.

local Strikes = {}

function Strikes.heatOf(cfg: any, streak: number): number
	return math.clamp(math.floor((tonumber(streak) or 0) / cfg.Heat.StreakPerHeat), 0, cfg.Heat.Max)
end

function Strikes.interval(cfg: any, kind: string, heat: number): number
	local row = if kind == "meteor" then cfg.Strikes.Intervals.meteor else cfg.Strikes.Intervals.other
	local h = math.clamp(math.floor(tonumber(heat) or 0), 0, #row - 1)
	return row[h + 1]
end

-- The ring schedule for one player who is on the island from `startT` (the name, or a practice landing).
function Strikes.newPlayer(cfg: any, kind: string, heat: number, startT: number, rand: () -> number): any
	local base = Strikes.interval(cfg, kind, heat)
	return { kind = kind, heat = heat, base = base, nextAt = startT + cfg.Strikes.FirstAfterSeconds + rand() * base, count = 0 }
end

-- Is a ring due now? A ring that would land after `disasterEnd` is never shown, and the player's schedule ends.
function Strikes.due(cfg: any, ps: any, now: number, disasterEnd: number): boolean
	if now < ps.nextAt - 1e-9 then return false end
	if now + cfg.Strikes.TelegraphSeconds > disasterEnd + 1e-9 then
		ps.nextAt = math.huge
		return false
	end
	return true
end

function Strikes.placed(cfg: any, ps: any, now: number, rand: () -> number)
	local j = cfg.Strikes.Jitter
	ps.nextAt = now + ps.base * (1 + (rand() * 2 - 1) * j)
	ps.count += 1
end

function Strikes.deferred(cfg: any, ps: any, now: number)
	ps.nextAt = now + cfg.Strikes.RetrySeconds
end

-- How many rings may be live at once on `area` square studs of walkable ground (at least one).
function Strikes.ringRadius(cfg: any): number
	return cfg.Strikes.HitRadius + cfg.Hits.PlayerRadius
end

-- The coverage rule alone: live rings never cover more than MaxCoverage of the walkable area (at least one ring).
function Strikes.coverageCap(cfg: any, area: number): number
	local r = Strikes.ringRadius(cfg)
	return math.max(1, math.floor(cfg.Strikes.MaxCoverage * area / (math.pi * r * r)))
end

-- ... and never more than Config.Budget.Rings at once: the rings are the only server Parts that grow with players and
-- Heat, so the server's Part budget is capped in code here (REVIEW-1 F11).
function Strikes.maxLive(cfg: any, area: number): number
	return math.min(Strikes.coverageCap(cfg, area), cfg.Budget.Rings)
end

-- May a ring centred at `ring` ({ x, z }) be placed now? live = { { x, z, r } } (the rings still on the ground),
-- players = { { x, z } } (everyone on the island, server-seen), walkable(x, z) = solid ground the player could stand
-- on, area = the walkable area in square studs, exitDistance = Zones.exitDistance. -> ok, reason ("cap" | "exit").
function Strikes.canPlace(cfg: any, ring: any, live: { any }, players: { any }, walkable: (number, number) -> boolean,
	area: number, exitDistance: any): (boolean, string?)
	if #live + 1 > Strikes.maxLive(cfg, area) then return false, "cap" end
	local r = Strikes.ringRadius(cfg)
	local disks = table.clone(live)
	table.insert(disks, { x = ring.x, z = ring.z, r = r })
	local coverR = r + cfg.Hits.PlayerRadius
	local exitStuds = cfg.Strikes.ExitStuds
	local reach = coverR + exitStuds
	for _, p in players do
		local dx, dz = p.x - ring.x, p.z - ring.z
		local d2 = dx * dx + dz * dz
		if d2 < coverR * coverR then
			-- a player the ring covers keeps a way out of ALL the red within ExitStuds
			if exitDistance(p.x, p.z, disks, walkable, 0.8, 30) > exitStuds + 1e-9 then
				return false, "exit"
			end
		elseif d2 < reach * reach then
			-- a player near it, already standing in red (a ring, a crack, rising water), must not lose their way out:
			-- their exit stays within ExitStuds, or the new ring does not lengthen it (a long flood escape stays as long)
			local with = exitDistance(p.x, p.z, disks, walkable, 0.8, 30)
			if with > exitStuds + 1e-9 then
				local without = exitDistance(p.x, p.z, live, walkable, 0.8, 30)
				if with > without + 0.5 then return false, "exit" end
			end
		end
	end
	return true, nil
end

return Strikes
