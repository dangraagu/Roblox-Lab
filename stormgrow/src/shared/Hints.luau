--!strict
-- Hints.luau — the one-line hint under the farm, from state alone (DESIGN.md §11). Pure.
-- Dependencies come in as arguments (a bare string require is invalid in Roblox): cfg = Config, Weather.
--
-- s = { now, harvests, planted, owned, ripe, ripeValue, coins, unlocked, fields, heldMarked }
--   planted/owned: planted tiles / tiles on owned fields; ripe: ripe crops the running or next event can
--   still mark; ripeValue: what one of them sells for now; heldMarked: ripe crops that already carry the
--   running event's mark (nothing more to gain from it: tap them).
-- No tutorial flag: a returning player with a planted farm is past every tutorial condition.

local Hints = {}

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local TUTORIAL_HARVESTS = 30 -- after this many harvests nobody is taught how to plant again

function Hints.pick(s: any, cfg: any, Weather: any): string?
	local W, M = cfg.Weather, cfg.Marks
	-- the first minute
	if s.harvests == 0 and s.planted == 0 then
		return "Tap a glowing tile to plant a " .. cfg.Crops[1].name .. " (free)"
	end
	if s.harvests == 0 and s.planted < s.owned then
		return "Plant the rest: tap each glowing tile"
	end
	-- the forecast's hold cue: the core decision, every event
	local kind = Weather.at(s.now, W)
	if kind ~= "clear" then
		local mark = M[kind]
		if s.ripe > 0 then
			return string.format("%s %s NOW: ripe crops left in the ground can turn %s %s (x%d)",
				W.Emoji[kind], string.upper(W.Names[kind]), mark.emoji, mark.name, mark.mult)
		end
		if s.heldMarked > 0 then
			return string.format("%s Already %s: tap to harvest them now", mark.emoji, mark.name)
		end
	else
		local nk, ns = Weather.nextEvent(s.now, W)
		if ns - s.now <= W.CueSeconds and s.ripe > 0 then
			local mark = M[nk]
			return string.format("%s %s in %s: ripe crops left in the ground can turn %s %s (x%d)",
				W.Emoji[nk], W.Names[nk], clock(ns - s.now), mark.emoji, mark.name, mark.mult)
		end
	end
	-- the rest of the first minutes
	if s.harvests < TUTORIAL_HARVESTS and s.ripe > 0 then
		return string.format("Ripe! Tap to harvest: it sells and replants (+%d)", s.ripeValue)
	end
	if s.unlocked == 1 and s.coins >= cfg.Crops[2].unlock then
		return string.format("Unlock the %s in 🌱 Seeds: %d", cfg.Crops[2].name, cfg.Crops[2].unlock)
	end
	return nil
end

return Hints
