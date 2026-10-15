--!strict
-- Save.luau — the persisted profile: defaults, the normaliser for whatever the DataStore hands back, and what
-- exactly gets written. PURE.
--
-- DataStore `ScraplineTycoon_v1`, key u_<userId>, record { session, jobId, lockUntil, data = <packed> }. The
-- session lock and the owner token live in Main.server.luau; this file only shapes `data` (DESIGN.md 11.1):
--   data = { v, cash, stations = { [stationId] = { n, L, j } }, jamIn, tier, bolts, boltsAt, tutorial }
-- In memory a station is { n, L, jam = { a, b } } (0 running, 1 sputtering, 2 jammed) and the jam scheduler is
-- d.jams = { jamIn, sputter } (Jams.luau); neither the sputter nor anything else in d ever replicates.
-- No integer keys anywhere (JSON turns sparse integer keys into strings): stations are keyed by their string id.
-- Spec: tests/Save.spec.luau.

local Save = {}

Save.VERSION = 1

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function int(x: any, lo: number, hi: number, default: number): number
	if not finite(x) then return default end
	return math.clamp(math.floor(x), lo, hi)
end

function Save.defaults(cfg: any): any
	local stations = {}
	for _, id in cfg.Stations.Order do
		stations[id] = { n = 0, L = 1, jam = { 0, 0 } }
	end
	return {
		v = Save.VERSION,
		cash = 0,
		stations = stations,
		jams = { jamIn = cfg.Jams.FirstJamIn, sputter = nil },
		tier = 0,
		bolts = 0,
		boltsAt = 0,
		tutorial = 0,
	}
end

-- Any loaded value -> a safe in-memory profile. Unknown fields are dropped.
function Save.normalise(cfg: any, raw: any): any
	local d = Save.defaults(cfg)
	if type(raw) ~= "table" then return d end
	if finite(raw.cash) then d.cash = math.max(0, raw.cash) end
	d.tier = int(raw.tier, 0, 6, 0)
	d.bolts = int(raw.bolts, 0, math.huge, 0)
	d.boltsAt = int(raw.boltsAt, 0, math.huge, 0)
	d.tutorial = int(raw.tutorial, 0, 4, 0)
	-- the jam clock: a new profile's first sputter is FirstJamIn away, which is longer than JamMax, so the clamp
	-- keeps whichever is larger (a profile saved inside its first 240 s keeps its clock)
	local J = cfg.Jams
	if finite(raw.jamIn) then
		d.jams.jamIn = math.clamp(raw.jamIn, 0, math.max(J.JamMax, J.FirstJamIn))
	end
	local rs = if type(raw.stations) == "table" then raw.stations else {}
	local prevBuilt = true
	for t, id in cfg.Stations.Order do
		local r = rs[id]
		local st = d.stations[id]
		if type(r) == "table" and prevBuilt then
			st.n = int(r.n, 0, 2, 0)
			st.L = int(r.L, 1, cfg.Stations.MaxLevel, 1)
			local j = int(r.j, 0, st.n, 0)
			st.jam = { if j >= 1 then 2 else 0, if j >= 2 then 2 else 0 }
		end
		-- the unlock rule holds for any record: nothing after an unbuilt station is built
		if st.n == 0 then
			st.jam = { 0, 0 }
			prevBuilt = false
		end
	end
	return d
end

-- What is written: exactly the documented fields, as a copy. A live sputter is written as a jam.
function Save.pack(cfg: any, d: any): any
	local stations = {}
	for _, id in cfg.Stations.Order do
		local st = d.stations[id]
		local j = 0
		for m = 1, math.min(st.n, 2) do
			if st.jam[m] ~= 0 then j += 1 end
		end
		stations[id] = { n = st.n, L = st.L, j = j }
	end
	return {
		v = Save.VERSION,
		cash = d.cash,
		stations = stations,
		jamIn = d.jams.jamIn,
		tier = d.tier,
		bolts = d.bolts,
		boltsAt = d.boltsAt,
		tutorial = d.tutorial,
	}
end

return Save
