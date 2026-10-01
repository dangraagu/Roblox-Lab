--!strict
-- FarmModel.luau — the pacing model, rebuilt on the REAL game modules (replaces design/pacing-model.luau).
--
-- Every number the game plays by comes from src/shared: the weather clock (Weather), the odds and marks
-- (Mutation, Config.Weather, Config.Marks), planting, harvesting, unlocking and fields (Economy), the start
-- profile (Profile) and the band thresholds (Config.Env.Bands). Only the PLAYER is modelled, and the player
-- is written down in Config.Pacing.Profiles instead of hidden:
--   * sweeps the farm every `checkEvery` s; one tap (harvest + replant, Economy.tap) costs `tap` s;
--   * follows the HUD's hold cue: while an event runs, or one starts within `holdHorizon` s, ripe crops
--     stay in the ground, except a crop that already has the running event's mark;
--   * `combo` also keeps a marked crop when the next event (within `comboHorizon` s) adds a mark it lacks;
--   * `hunt` plants the unlocked crop with the most Almanac entries still to find (the "📖 N to find" hint);
--   * buys the cheapest affordable upgrade (next field or next crop); a new crop becomes the selection;
--   * from band 2 on, pays `dodge` s per hazard (one per HazardEverySeconds of play);
--   * no offline growth, rest excluded: every modelled minute is a minute played.
-- Randomness: one math.random stream per run, seeded, standing in for the server's unseeded Random.

local Weather = require("../src/shared/Weather")
local Mutation = require("../src/shared/Mutation")
local Economy = require("../src/shared/Economy")
local Profile = require("../src/shared/Profile")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")

local W, M = Config.Weather, Config.Marks
local bands = Config.Env.Bands
local byId = {}
for _, c in Config.Crops do byId[c.id] = c end

local FarmModel = {}

FarmModel.JOIN0 = 1790000000 -- only its phase matters

local function tileKeys(fields: number): { string }
	local out = {}
	for f = 1, fields do
		for t = 1, Config.Farm.TilesPerField do
			table.insert(out, Economy.tileKey(f, t))
		end
	end
	return out
end

-- One session of `seconds` played, joining at Unix second `joinUnix`.
function FarmModel.run(profile: any, seed: number, joinUnix: number, seconds: number): any
	math.randomseed(seed)
	local rand = math.random
	local p = Profile.default(Config)
	local out = { bandAt = { [1] = 0 }, almanacAt = {}, firstMark = nil, firstTempest = nil, harvests = 0, boughtAt = {}, worthAt = {} }
	local nextCheck = 0
	local hazardClock = 0
	local lastBand = 1
	local keys = tileKeys(p.fields)

	local function ripe(tile: any, t: number): boolean
		return tile ~= nil and t >= tile.at + byId[tile.c].grow
	end
	local function comboWait(tile: any, t: number): boolean
		if not profile.combo or tile.m == 0 or tile.m == 7 then return false end
		local nk, ns = Weather.nextEvent(t, W)
		return bit32.band(tile.m, M[nk].bit) == 0 and ns - t <= profile.comboHorizon
	end
	local function held(tile: any, t: number): boolean
		if profile.neverHold then return false end
		local kind = Weather.at(t, W)
		if kind ~= "clear" then
			if bit32.band(tile.m, M[kind].bit) ~= 0 then return comboWait(tile, t) end
			return true
		end
		local _, ns = Weather.nextEvent(t, W)
		if ns - t <= profile.holdHorizon then return true end
		return comboWait(tile, t)
	end
	local function hunt()
		-- the crop with the most entries still to find, ties to the richer crop, affordable
		local best, bestN = p.unlocked, -1
		for i = p.unlocked, 1, -1 do
			local c = Config.Crops[i]
			local n = Mutation.missing(p.almanac, c.id)
			if n > bestN and p.coins >= c.seed then best, bestN = i, n end
		end
		p.selected = Config.Crops[best].id
	end
	local function buy(t: number)
		while true do
			local fieldPrice = Economy.nextFieldPrice(p, Config)
			local nextCrop = Economy.nextCrop(p, Config)
			local cropPrice = nil
			if nextCrop and p.harvested >= (nextCrop.needHarvested or 0) then cropPrice = nextCrop.unlock end
			local choice, price = nil, math.huge
			if fieldPrice and fieldPrice < price then choice, price = "field", fieldPrice end
			if cropPrice and cropPrice < price then choice, price = "crop", cropPrice end
			if choice == nil or p.coins < price then return end
			if choice == "field" then
				Economy.buyField(p, Config)
				out.boughtAt["field " .. p.fields] = t
				keys = tileKeys(p.fields)
			else
				local id = nextCrop.id
				Economy.unlock(p, Config)
				out.boughtAt[id] = t
			end
		end
	end

	for t = 0, seconds - 1 do
		local now = joinUnix + t
		if t % 60 == 0 then out.worthAt[t // 60] = p.harvested end
		local kind = Weather.isTick(now, W)
		if kind then
			for _, s in Mutation.strikeTick(p.tiles, kind, now, rand, W, M, byId) do
				out.firstMark = out.firstMark or t
				if s.marks == 7 then out.firstTempest = out.firstTempest or t end
				if Mutation.grant(p, s.crop, s.marks, t) then
					out.almanacAt[p.almanacCount] = t
				end
			end
		end
		if t >= nextCheck then
			buy(t)
			local elapsed = 0
			for _, key in keys do
				local tile = p.tiles[key]
				local clock = now + elapsed
				local tapIt = (tile == nil) or (ripe(tile, clock) and not held(tile, clock))
				if tapIt then
					if profile.hunt then hunt() end
					local r = Economy.tap(p, Config, key, clock + profile.tap)
					if r.harvest then out.harvests += 1 end
					elapsed += profile.tap
				end
			end
			buy(t)
			if EnvBands.indexAt(bands, p.harvested) >= 2 then
				hazardClock += elapsed + profile.checkEvery
				while hazardClock >= Config.Pacing.HazardEverySeconds do
					hazardClock -= Config.Pacing.HazardEverySeconds
					elapsed += profile.dodge
				end
			end
			nextCheck = t + math.max(1, math.floor(elapsed + profile.checkEvery + 0.5))
		end
		local b = EnvBands.indexAt(bands, p.harvested)
		while lastBand < b do
			lastBand += 1
			out.bandAt[lastBand] = t
		end
	end
	out.final = p
	return out
end

function FarmModel.pct(list: { number }, q: number): number
	if #list == 0 then return math.huge end
	table.sort(list)
	local i = math.clamp(math.floor(q * (#list - 1) + 0.5) + 1, 1, #list)
	return list[i]
end

-- `runs` sessions of `seconds` for a profile -> { band = { [b] = { seconds... } }, firstMark, firstTempest,
-- almanac = { [minute] = { counts... } }, all56 = { seconds... }, bought = { [what] = { seconds... } } }
function FarmModel.sample(name: string, runs: number, seconds: number, seedBase: number?): any
	local prof = Config.Pacing.Profiles[name]
	local res = { band = {}, firstMark = {}, firstTempest = {}, almanac = { [30] = {}, [60] = {}, [180] = {} }, all56 = {}, bought = {}, worth = {} }
	for b = 1, #bands do res.band[b] = {} end
	for r = 1, runs do
		local join = FarmModel.JOIN0 + ((r * 7919) % 1800)
		local o = FarmModel.run(prof, (seedBase or 1000) + r, join, seconds)
		for b = 1, #bands do table.insert(res.band[b], o.bandAt[b] or math.huge) end
		table.insert(res.firstMark, o.firstMark or math.huge)
		table.insert(res.firstTempest, o.firstTempest or math.huge)
		for m, list in res.almanac do
			local n = 0
			for _, at in o.almanacAt do
				if at <= m * 60 then n += 1 end
			end
			table.insert(list, n)
		end
		table.insert(res.all56, o.almanacAt[56] or math.huge)
		for k, at in o.boughtAt do
			res.bought[k] = res.bought[k] or {}
			table.insert(res.bought[k], at)
		end
		for m, w in o.worthAt do
			res.worth[m] = res.worth[m] or {}
			table.insert(res.worth[m], w)
		end
	end
	res.runs = runs
	return res
end

return FarmModel
