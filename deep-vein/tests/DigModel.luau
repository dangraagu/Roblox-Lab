-- DigModel — a normal miner's first hours, played on the PURE modules (no engine, no emulator).
-- Used by tests/Pacing.spec.luau (docs/complete-game-standard.md §2: "measure the minutes with a pacing model in
-- tests/"). The end-to-end twin is ../robloxemu/check_deepvein_pace.luau: the same bot through the real server.
--
-- What the game demands is computed from the game's own rules: Mine (the cave, the reveal flood, hit points),
-- Ore, Economy (bag, sale, shop) and Prestige (the rebirth gate). The bot is check_deepvein_pace's policy, which
-- is tests/walk.luau's: the deepest block it can see first, ore breaking ties; SURFACE + SELL when the bag is
-- full, then one try at each of pickaxe, backpack and lamp; rebirth the moment it is offered. "Can see" is the
-- server's stream band: blocks within Config.Mine.StreamLayers of the layer the miner stands in, the band moving
-- once the miner is StreamHysteresis layers off its centre. The human costs are Config.Pacing (seconds per swing,
-- per new block, per surface trip).
--
-- Each rebirth digs its own cave, drawn from a key exactly as the server draws one; the model takes the keys as an
-- argument, so a spec can play several cave sequences.

local DigModel = {}

-- keys(run) -> the cave key { a, b } of rebirth `run` (0-based). M = { Mine, Ore, Economy, Prestige, EnvBands }. Plays
-- runs 0..lastRun, each until its rebirth is offered, and returns per-run counts and the first reach of each stratum.
function DigModel.play(cfg: any, M: any, keys: (number) -> any, lastRun: number): any
	local Mine, Ore, Economy, Prestige, EnvBands = M.Mine, M.Ore, M.Economy, M.Prestige, M.EnvBands
	local bands = cfg.Env.Bands
	local p = {
		cash = cfg.Economy.StartCash, totalCash = 0, runEarned = 0, inventory = {},
		pickTier = 1, backpackLevel = 0, lampLevel = 0, rebirths = 0, depthLayer = 0, bestLayer = 0,
	}
	local total = { swings = 0, blocks = 0, trips = 0 }
	local reached = { [1] = { swings = 0, blocks = 0, trips = 0 } }
	local runs = {}
	local K, H = cfg.Mine.StreamLayers, cfg.Mine.StreamHysteresis
	local c = Mine.center(cfg)

	for r = 0, lastRun do
		local w = Mine.world(cfg, r, keys(r))
		local opened: { [string]: boolean } = {}
		local faces: { any } = {} -- exposed, breakable solids, in the order the server would build them
		local isFace: { [string]: boolean } = {}
		local hpLeft: { [string]: number } = {}
		local deepestOpen = 0 -- where DESCEND lands: the deepest cell opened, by a swing or a void it broke into
		local function openCell(x, y, z)
			opened[Mine.key(x, y, z)] = true
			if y > deepestOpen then deepestOpen = y end
			local rv = Mine.reveal(cfg, Ore, w, opened, x, y, z)
			for _, a in rv.air do
				opened[a.key] = true
				if a.y > deepestOpen then deepestOpen = a.y end
			end
			for _, s in rv.solids do
				if s.kind ~= "bedrock" and not isFace[s.key] and not opened[s.key] then
					isFace[s.key] = true
					table.insert(faces, s)
				end
			end
		end
		openCell(c, 0, c)
		local miner = 0 -- the layer the miner stands in (the mouth)
		local centre = 0 -- the stream band's centre
		local run = { swings = 0, blocks = 0, trips = 0 }
		local function trip()
			Economy.sell(p, cfg, Ore, Prestige.multiplier(cfg, p.rebirths))
			Economy.buyPickaxe(p, cfg)
			Economy.buyBackpack(p, cfg)
			Economy.buyLamp(p, cfg)
			total.trips += 1
			run.trips += 1
		end
		local guard = 0
		while guard < 200000 do
			guard += 1
			if (Prestige.canRebirth(p, cfg, Ore)) then break end
			if Economy.carried(p) >= Economy.backpackCapacity(cfg, p.backpackLevel) then
				trip()
				miner = deepestOpen -- DESCEND: back to the deepest cell opened
				centre = miner
			end
			-- the stream band follows the miner
			if math.abs(miner - centre) >= H then centre = miner end
			local lo, hi = math.max(0, centre - K), centre + K
			local best, bestScore, bestI = nil, -1, 0
			for i, f in faces do
				if f.y >= lo and f.y <= hi then
					local score = f.y * 10 + (if f.ore > 0 then 5 else 0)
					if score > bestScore then best, bestScore, bestI = f, score, i end
				end
			end
			if best == nil then
				trip() -- everything in reach is mined: ride up, sell, and work down from the top
				miner, centre = 1, 1
				-- a band at the top that holds nothing either means the whole cave is dug: stop
				local any = false
				for _, f in faces do if f.y <= 1 + K then any = true end end
				if not any then break end
			else
				miner = best.y - 1 -- standing on the block
				if math.abs(miner - centre) >= H then centre = miner end
				-- one swing (the bot swings once, then looks again; the same block stays the deepest)
				total.swings += 1
				run.swings += 1
				local power = Economy.swingPower(cfg, p.pickTier)
				local refused = Ore.isOre(cfg, best.ore) and Economy.spaceLeft(p, cfg) <= 0
				if not refused then
					local left = (hpLeft[best.key] or best.hp) - power
					if left > 0 then
						hpLeft[best.key] = left
					else
						hpLeft[best.key] = nil
						local yield = Ore.yieldOf(cfg, best.ore)
						if yield > 0 then Economy.addOre(p, cfg, best.ore, yield) end
						table.remove(faces, bestI)
						isFace[best.key] = nil
						openCell(best.x, best.y, best.z)
						total.blocks += 1
						run.blocks += 1
						local L = best.y
						local bi = EnvBands.indexAt(bands, L)
						for i = 2, bi do
							if reached[i] == nil and L >= bands[i].from then
								reached[i] = { swings = total.swings, blocks = total.blocks, trips = total.trips }
							end
						end
					end
				end
			end
		end
		run.rebirthable = (Prestige.canRebirth(p, cfg, Ore))
		table.insert(runs, run)
		if not run.rebirthable then break end
		Prestige.apply(p, cfg, Ore)
	end
	return { runs = runs, reached = reached }
end

function DigModel.minutes(profile: any, at: any): number
	return (at.swings * profile.swing + at.blocks * profile.block + at.trips * profile.trip) / 60
end

return DigModel
