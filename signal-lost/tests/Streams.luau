--!nocheck
-- Streams.luau — TEST-ONLY adapters. Production draws every stream from `Random.new()` with no seed (engine
-- entropy, one object per stream per attempt; DESIGN.md §12). The luau CLI has no `Random`, so specs and
-- the pacing model drive the real Station module through this adapter over the verbatim Rng: the same two
-- methods Roblox's Random answers, `NextInteger(lo, hi)` (inclusive) and `NextNumber()` in [0, 1).
-- Rng.NextInteger goes through Rng.below (high bits), so NextInteger(1, n) == the rig's `below(n)`, and
-- NextNumber == the rig's `next()`: the real module reproduces design-measure/station.luau draw for draw.
local Rng = require("../src/shared/Rng")

local Streams = {}

function Streams.adapter(seed)
	local r = Rng.new(seed)
	local s = { calls = 0 }
	function s:NextInteger(lo, hi)
		self.calls += 1
		return r:NextInteger(lo, hi)
	end
	function s:NextNumber()
		self.calls += 1
		return r:next()
	end
	return s
end

-- The rig's seed scheme (design-measure/station.luau S.seedsFor), so a spec can compare plan for plan.
function Streams.seedsFor(i, salt)
	salt = salt or 0
	return {
		layout = 1000003 * i + 17 + salt,
		air = 7919 * i + 104729 + salt * 3,
		loot = 15485863 * i + 32452843 + salt * 5,
		relay = 49979687 * i + 86028121 + salt * 7,
	}
end

function Streams.fromSeeds(seeds)
	return {
		layout = Streams.adapter(seeds.layout),
		air = Streams.adapter(seeds.air),
		loot = Streams.adapter(seeds.loot),
		relay = Streams.adapter(seeds.relay),
	}
end

-- A stream that records every method called on it (spec 7: only NextInteger / NextNumber).
function Streams.spy(seed, log)
	local inner = Streams.adapter(seed)
	return setmetatable({}, {
		__index = function(_, key)
			table.insert(log, key)
			local f = inner[key]
			if type(f) ~= "function" then return f end
			return function(_self, ...) return f(inner, ...) end
		end,
	})
end

return Streams
