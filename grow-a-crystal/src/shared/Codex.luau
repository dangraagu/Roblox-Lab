--!strict
-- Ren Gem Codex-logikk: hvilke rarity-tiers spilleren har oppdaget + fullførings-grad.
-- flags = { [tier]=true }.

local Codex = {}

-- Registrer at en tier er oppdaget. Returnerer true hvis den var NY.
function Codex.discover(flags: { [number]: boolean }, tier: number): boolean
	if flags[tier] then return false end
	flags[tier] = true
	return true
end

function Codex.has(flags: { [number]: boolean }, tier: number): boolean
	return flags[tier] == true
end

-- Antall oppdagede tiers i 1..maxTier.
function Codex.count(flags: { [number]: boolean }, maxTier: number): number
	local n = 0
	for t = 1, maxTier do
		if flags[t] then n += 1 end
	end
	return n
end

-- Fullføring 0..1.
function Codex.completion(flags: { [number]: boolean }, maxTier: number): number
	return Codex.count(flags, maxTier) / maxTier
end

return Codex
