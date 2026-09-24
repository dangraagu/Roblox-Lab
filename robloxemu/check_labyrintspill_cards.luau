-- Labyrinth Mariozo — biome title cards, through the REAL clients (Biome.client + HudClient).
-- Run: luau check_labyrintspill_cards.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- A player who has cleared level 25 walks into level 26, the first level of the Ice Cellar:
--   * the "YOU REACHED THE ICE CELLAR!" card plays, with a flash — but only after HudClient's own
--     level-complete card has gone (on a phone it is tall enough to reach this slot), and it names the
--     new hazard and how to dodge it;
--   * it plays ONCE per biome per session: coming back to the ice cellar later is a quiet card;
--   * staying in a biome, or retrying its level, shows no card at all;
--   * a card fades out after a few seconds;
--   * (resume session) a hazard banner, like a card, never shows over the level-complete card.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill cards")
local truthy, eq = T.truthy, T.eq

local ctx = Lib.boot({ accepted = 25, clients = Lib.CLIENTS_NO_SOUND })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local RS = h.ReplicatedStorage
local Biomes = h:_require(RS:FindFirstChild("Biomes"))
local root = ctx.plr.PlayerGui.LabyrintBiome.Root
local card, sub = root.BandCard, root.BandCardSub
local summary = ctx.plr.PlayerGui.MedaljeHud.Root.OppsummeringsKort

-- flashes are counted as FxClient creates them (each one destroys itself after its fade)
local flashCount = 0
ctx.plr.PlayerGui.ChildAdded:Connect(function(c)
	if c.Name == "FxFlash" then flashCount += 1 end
end)
local function flashes() return flashCount end
-- every card text shown, recorded on every frame the harness draws (ctx.onFrame)
local shown = {}
local lastText = ""
ctx.onFrame = function()
	if card.Visible and card.Text ~= lastText then
		lastText = card.Text
		table.insert(shown, card.Text)
	end
	if not card.Visible then lastText = "" end
end
local function watch(seconds)
	ctx.run(seconds)
end

--================================================================ the dungeon -> jungle is quiet (already reached)

ctx.startRun(25)
watch(1)
eq(#shown, 1, "entering a run shows the biome's card")
truthy(shown[1] and string.find(shown[1], "Jungle Ruins", 1, true) ~= nil and string.find(shown[1], "REACHED", 1, true) == nil,
	"level 25 (still the jungle, already reached): a quiet card — " .. tostring(shown[1]))
watch(4)
eq(card.Visible, false, "the card fades out after a few seconds")

--================================================================ finishing 25 -> the ice cellar fanfare, after the summary card

shown = {}
local flashesBefore = flashes()
local summarySeen, cardWhileSummary = false, 0
local firstCardAt, summaryGoneAt, subText = nil, nil, nil
local t0 = ctx.clock
ctx.finishLevel()
ctx.run(9, 1 / 30, function()
	if summary.Visible then
		summarySeen = true
		if card.Visible then cardWhileSummary += 1 end
	elseif summarySeen and summaryGoneAt == nil then
		summaryGoneAt = ctx.clock - t0
	end
	if card.Visible and firstCardAt == nil then
		firstCardAt = ctx.clock - t0
		subText = sub.Text
	end
end)
shown[2] = subText
truthy(summarySeen, "HudClient showed its level-complete card")
eq(cardWhileSummary, 0, "the biome card never shows while the level-complete card is up")
truthy(firstCardAt ~= nil and summaryGoneAt ~= nil and firstCardAt >= summaryGoneAt - 1e-6,
	string.format("it comes right after (summary gone at %.2f s, card at %.2f s)", summaryGoneAt or -1, firstCardAt or -1))
truthy(shown[1] and string.find(shown[1], "YOU REACHED THE ICE CELLAR", 1, true) ~= nil, "the fanfare card: " .. tostring(shown[1]))
truthy(shown[2] and string.find(shown[2], Biomes.hazardIntro("icicle"), 1, true) ~= nil,
	"and it introduces the new hazard and how to dodge it: " .. tostring(shown[2]))
truthy(flashes() > flashesBefore, "with a flash")

--================================================================ once per biome per session

shown = {}
ctx.startRun(20) -- back to the jungle
watch(1)
truthy(shown[1] and string.find(shown[1], "Jungle Ruins", 1, true) ~= nil, "the jungle again: its card")
shown = {}
local f0 = flashes()
ctx.startRun(26) -- the ice cellar again, still not cleared (accepted is 25)
watch(1)
truthy(shown[1] and string.find(shown[1], "Ice Cellar", 1, true) ~= nil and string.find(shown[1], "REACHED", 1, true) == nil,
	"the ice cellar a second time this session: a quiet card — " .. tostring(shown[1]))
watch(3)
eq(flashes(), f0, "no second fanfare flash")
shown = {}
ctx.startRun(26) -- retry the same level
watch(2)
eq(#shown, 0, "retrying a level of the same biome shows no card")

--================================================================ (resume session) the hazard banner waits too
-- A hazard whose first warning starts while the level-complete card is still up (it stays 4.5 s after a
-- finish; a warning can start 1 s into a level) must not put its banner over that card. Finish level after
-- level until the next one has such a hazard, stand in the passage beside it, and watch every frame.
do
	local CellHazards = h:_require(RS:FindFirstChild("CellHazards"))
	local HZ = Biomes.Hazards
	local banner = root.HazardBanner
	local exposed, overlap, bannerAfter = 0, 0, false
	local tries = 0
	-- the level each maze payload starts, as the server sends it
	local levelNow = 0
	RS.HudRemotes.LevelInfo.OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.inLobby == false then levelNow = p.level end
	end)
	while exposed == 0 and tries < 8 do
		tries += 1
		local t0 = ctx.clock
		ctx.finishLevel()
		local f = ctx.folder()
		local g = Lib.grid(f)
		-- the level just started is the one the summary card sits on top of (from the server's payload)
		local best = nil
		for _, hz in CellHazards.pick(levelNow, g.cols, g.rows, g.traps, Biomes.Seed, HZ) do
			if best == nil or hz.phase < best.phase then best = hz end
		end
		if best and CellHazards.firstImpact(best, HZ) - HZ.WarnSeconds < 4.0 then
			local cx, cy = 2 * best.cx + 1, 2 * best.cy + 1
			local spot = nil
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				if g.walls[(cx + d[1]) .. "," .. (cy + d[2])] == nil then spot = g.world(cx + d[1], cy + d[2]); break end
			end
			local c = g.world(cx, cy)
			for _ = 1, 9 * 30 do
				ctx.moveTo(spot)
				ctx.frame(1 / 30)
				local st = CellHazards.stateAt(best, ctx.clock - t0, HZ)
				local dx, dz = c.X - spot.X, c.Z - spot.Z
				local wouldShow = st == "warn" and math.sqrt(dx * dx + dz * dz) <= HZ.NearRadius + 8
				if summary.Visible and wouldShow then exposed += 1 end
				if summary.Visible and banner.Visible then overlap += 1 end
				if not summary.Visible and not card.Visible and banner.Visible then bannerAfter = true end
			end
		end
	end
	truthy(exposed > 0, string.format("a hazard warned beside the player while the level-complete card was up (%d frames, %d tries)", exposed, tries))
	eq(overlap, 0, "the hazard banner never shows while the level-complete card is up")
	truthy(bannerAfter, "and it does show once the card (and any biome card) has gone")
end

T.finish(h)
