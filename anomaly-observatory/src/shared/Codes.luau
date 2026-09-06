--!strict
-- Codes.luau — one-time redeemable code check. Pure + read-only: it validates a code
-- against Config and the player's already-redeemed set and returns the reward, but does
-- NOT mutate anything. The server applies the reward and marks the code redeemed inside a
-- single atomic DataStore flush so a crash can't dupe or lose a reward.

local Codes = {}

export type RedeemedSet = { [string]: boolean }
export type Reward = { hintTokens: number?, tint: string? }
export type Result = { ok: boolean, reason: string?, reward: Reward? }

-- Uppercase + trim surrounding whitespace so "  welcome " matches "WELCOME".
function Codes.normalize(code: string): string
	return (string.upper(code):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Validate a code. reasons: "empty" | "unknown" | "already".
function Codes.redeem(code: string, redeemed: RedeemedSet, cfg: any): Result
	local key = Codes.normalize(code)
	if key == "" then
		return { ok = false, reason = "empty" }
	end
	local reward = cfg.Codes[key]
	if not reward then
		return { ok = false, reason = "unknown" }
	end
	if redeemed[key] then
		return { ok = false, reason = "already" }
	end
	-- Return a shallow copy so callers can't accidentally mutate Config.
	return { ok = true, reward = { hintTokens = reward.hintTokens, tint = reward.tint } }
end

return Codes
