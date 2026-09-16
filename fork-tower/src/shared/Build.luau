-- Build.luau — the summit card, as a PURE function of the choices a player made.
--
-- Fork Tower's run does not end with a score, it ends with an IDENTITY: a title, a rarity and the
-- list of traits that earned them, screenshot-ready. That card is the reason a run has an ending
-- rather than a stopping point, and the reason a rebirth is worth doing.
--
-- Pure and Roblox-free. Takes cfg and a list of trait ids; returns plain tables. The list is read
-- only, and every trait row on the card is a COPY — a HUD that sorted the card's traits in place
-- would otherwise reorder Config.Traits for the whole server, for every player, until restart.

local Build = {}

-- Which rarity a score lands in. Thresholds ascend; the last one cleared wins. Written as its own
-- function because Build.spec walks it across a range of scores to assert the ladder never goes
-- down — a rarity that is assigned any other way (a lookup, a bucket count) can, and a player who
-- climbed further and got a worse card would be right to be annoyed.
function Build.rarityFor(cfg, score: number): number
	local idx = 1
	for i, r in ipairs(cfg.Build.Rarities) do
		if score >= r.threshold then
			idx = i
		end
	end
	return idx
end

-- Build.reveal(cfg, picks) -> card
--
-- card = {
--   title, score, unknown, synergies, dominantTheme,
--   traits = { { id, label, theme, power, color }, ... },   -- copies, in pick order
--   themeCounts = { theme = n },
--   rarityIndex, rarityName, rarityColor,
-- }
function Build.reveal(cfg, picks)
	local byId = {}
	for _, t in ipairs(cfg.Traits) do
		byId[t.id] = t
	end

	local traits, themeCounts, themeFirst = {}, {}, {}
	local score, unknown = 0, 0
	local peak, peakPower = nil, -math.huge

	for order, id in ipairs(picks) do
		local t = byId[id]
		if t == nil then
			-- A save file from an older trait table, or a tampered payload. Skipped and COUNTED:
			-- a card that silently drops half a run looks exactly like a card for a short run.
			unknown += 1
		else
			traits[#traits + 1] = {
				id = t.id, label = t.label, theme = t.theme, power = t.power,
				color = { t.color[1], t.color[2], t.color[3] },
			}
			score += t.power
			themeCounts[t.theme] = (themeCounts[t.theme] or 0) + 1
			if themeFirst[t.theme] == nil then
				themeFirst[t.theme] = order
			end
			-- Strictly greater, so a tie on power goes to the trait picked EARLIER.
			if t.power > peakPower then
				peak, peakPower = t, t.power
			end
		end
	end

	-- Leaning into one theme is the thing the game wants to reward, since it is the only way a
	-- run reads as a deliberate build rather than a list of whatever was behind the safe door.
	local synergies = 0
	for _, n in pairs(themeCounts) do
		if n >= cfg.Build.SynergyMin then
			synergies += 1
		end
	end
	score += synergies * cfg.Build.SynergyBonus

	-- Most-picked theme; a tie goes to whichever showed up first, so the title depends on the run
	-- and not on the order Config happens to list its traits in.
	local dominant, bestCount, bestFirst = nil, 0, math.huge
	for theme, n in pairs(themeCounts) do
		local first = themeFirst[theme]
		if n > bestCount or (n == bestCount and first < bestFirst) then
			dominant, bestCount, bestFirst = theme, n, first
		end
	end

	local title = cfg.Build.EmptyTitle
	if dominant ~= nil and peak ~= nil then
		-- Adjective from the theme you leaned into, noun from your strongest single pick: the
		-- title then names both halves of the run.
		title = cfg.Build.Adjectives[dominant] .. " " .. cfg.Build.Nouns[peak.theme]
	end

	local idx = Build.rarityFor(cfg, score)
	local rarity = cfg.Build.Rarities[idx]

	return {
		title = title,
		score = score,
		unknown = unknown,
		synergies = synergies,
		traits = traits,
		themeCounts = themeCounts,
		dominantTheme = dominant,
		peakTraitId = peak and peak.id or nil,
		rarityIndex = idx,
		rarityName = rarity.name,
		rarityColor = { rarity.color[1], rarity.color[2], rarity.color[3] },
	}
end

return Build
