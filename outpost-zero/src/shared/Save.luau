--!strict
-- Save.luau — the persisted profile: defaults, the normaliser for whatever the DataStore hands back, and exactly
-- what gets written. PURE.
--
-- DataStore `OutpostZero_v1`, key u_<userId>, record { session, jobId, lockUntil, data = <this> }. The session
-- lock and the owner token live in Main.server.luau; this file only shapes `data`. Everything not listed here
-- is derived (zones and positions from City.layout(seed); settlers, jobs, population from the lots; districts and
-- the band from the population), so nothing can disagree. No integer keys anywhere: lot keys are "d_i" strings.
-- `credits` and `savedAt` are always written together (one UpdateAsync of the whole document), so an absence is
-- never paid twice. Spec: tests/Save.spec.luau.

local Save = {}

Save.VERSION = 1

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Save.defaults(cfg: any): any
	return {
		v = Save.VERSION,
		seed = 0, -- 0 = not drawn yet; the server draws 1..SeedMax with its own Random.new()
		credits = cfg.Economy.StartCredits,
		lifetime = 0, -- every credit ever earned (the footer of your own Census row)
		lots = {}, -- ["d_i"] = storeys 1..MaxStoreys; absent = 0
		savedAt = 0, -- os.time() of the write
		ordersUntil = 0, -- os.time() when the workers' Orders run out
		popAt = 0, -- os.time() when the current population was first reached (the board's tie-break)
		airshipSeen = false, -- cosmetic: the Grand Airship's arrival was watched to the end
		tutorial = 0, -- the first-minutes hint step, 0..3
	}
end

local function int(v: any, default: number): number
	if not finite(v) then return default end
	return math.floor(math.max(0, v))
end

-- Any loaded value -> (a safe profile, info). info.fresh: there was no record; info.reseed: the seed must be
-- (re)drawn; info.future: a record newer than this version, which must never be written.
function Save.normalise(cfg: any, raw: any): (any, any)
	local out = Save.defaults(cfg)
	local info = { fresh = false, reseed = false, future = false }
	if type(raw) ~= "table" then
		info.fresh = true
		info.reseed = true
		return out, info
	end
	if finite(raw.v) and raw.v > Save.VERSION then info.future = true end
	local seed = raw.seed
	if finite(seed) and seed == math.floor(seed) and seed >= 1 and seed <= cfg.Save.SeedMax then
		out.seed = seed
	else
		info.reseed = true
	end
	if finite(raw.credits) then out.credits = math.max(0, raw.credits) end
	if finite(raw.lifetime) then out.lifetime = math.max(0, raw.lifetime) end
	out.lifetime = math.max(out.lifetime, out.credits)
	out.savedAt = int(raw.savedAt, 0)
	out.ordersUntil = int(raw.ordersUntil, 0)
	out.popAt = int(raw.popAt, 0)
	out.airshipSeen = raw.airshipSeen == true
	out.tutorial = math.min(int(raw.tutorial, 0), 3)
	local maxS = cfg.Economy.MaxStoreys
	local nd = #cfg.Districts
	if type(raw.lots) == "table" then
		for k, v in raw.lots do
			if type(k) == "string" and finite(v) then
				local d, i = string.match(k, "^(%d)_(%d)$")
				local dn, inum = tonumber(d), tonumber(i)
				if dn and inum and dn >= 1 and dn <= nd and inum >= 1 and inum <= 6 then
					local s = math.clamp(math.floor(v), 0, maxS)
					if s > 0 then out.lots[k] = s end
				end
			end
		end
	end
	return out, info
end

-- What is written: exactly the documented fields, as a copy (string lot keys only).
function Save.pack(d: any): any
	local lots = {}
	for k, s in d.lots do
		if type(k) == "string" and type(s) == "number" and s > 0 then lots[k] = s end
	end
	return {
		v = Save.VERSION,
		seed = d.seed,
		credits = d.credits,
		lifetime = d.lifetime,
		lots = lots,
		savedAt = d.savedAt,
		ordersUntil = d.ordersUntil,
		popAt = d.popAt,
		airshipSeen = d.airshipSeen == true,
		tutorial = d.tutorial,
	}
end

return Save
