--!strict
-- Codes.luau — normalise a typed code and decide whether it redeems. Pure and read-only.
--
-- The code table is an ARGUMENT. It lives in src/server/Secret.luau, which never replicates:
-- anything under src/shared becomes ReplicatedStorage, where every client can read it, and a code
-- table there is datamined before its article goes up (DESIGN.md §8.2).
--
-- This decides; it grants nothing. The server applies the cash and marks the code redeemed in ONE
-- atomic UpdateAsync, and refuses the grant if that write cannot persist (checklist: one-time
-- rewards).

local Codes = {}

export type Result = { ok: boolean, reason: string?, code: string?, cash: number? }

function Codes.normalize(code: string): string
	return (string.upper(code):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- reasons: "empty" | "long" | "unknown" | "already"
function Codes.redeem(cfg: any, raw: any, redeemed: { [string]: boolean }, codeTable: { [string]: any }): Result
	if type(raw) ~= "string" then
		return { ok = false, reason = "empty" }
	end
	if #raw > cfg.Codes.MaxLength then
		return { ok = false, reason = "long" }
	end
	local code = Codes.normalize(raw)
	if code == "" then
		return { ok = false, reason = "empty" }
	end
	local entry = codeTable[code]
	if entry == nil then
		return { ok = false, reason = "unknown" }
	end
	if redeemed[code] then
		return { ok = false, reason = "already", code = code }
	end
	return { ok = true, code = code, cash = entry.cash }
end

return Codes
