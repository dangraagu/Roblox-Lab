--!strict
-- Codes.luau — one-time redeemable code check. PURE and read-only: it validates a code against
-- cfg and the player's already-redeemed set and returns the reward, but mutates nothing. The
-- server applies the reward and marks the code redeemed inside a SINGLE atomic DataStore flush,
-- so a crash between the two can neither dupe the code nor lose the reward.
--
-- Fork Tower's reward is a SKIP: one free pass past a penalty section, keeping the trait. Which
-- makes the atomicity matter more than usual — a skip is spendable, so a code that half-redeems
-- is either free skips forever or a code the player paid attention for and never got.

local Codes = {}

export type RedeemedSet = { [string]: boolean }
export type Reward = { skips: number? }

-- Uppercase + trim surrounding whitespace, so "  fork " matches "FORK".
function Codes.normalize(code: string): string
	return (string.upper(code):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Validate. Returns (ok, reward, reason); reasons: "ok" | "empty" | "unknown" | "already".
function Codes.redeem(code: any, redeemed: RedeemedSet, codeTable: any): (boolean, Reward?, string)
	if type(code) ~= "string" then
		return false, nil, "empty"
	end
	local key = Codes.normalize(code)
	if key == "" then
		return false, nil, "empty"
	end
	local reward = codeTable[key]
	if not reward then
		return false, nil, "unknown"
	end
	if redeemed[key] then
		return false, nil, "already"
	end
	-- A copy, so a caller cannot reach through the reward and edit Config's own row.
	return true, { skips = reward.skips }, "ok"
end

return Codes
