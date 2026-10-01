-- Save — the profile's defaults, the normaliser for whatever the DataStore hands back, and the one-time
-- Falling Star's states. Run: luau tests/Save.spec.luau
--
-- A loaded record is untrusted input: an older version, a hand edit, a JSON round trip (which turns
-- sparse integer keys into strings), a NaN. normalise() makes any of it safe, and the star can only
-- ever move 0 -> 1 -> 2.

local Config = require("../src/shared/Config")
local Save = require("../src/shared/Save")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config

--============================================================================ defaults
do
	local d = Save.defaults()
	eq(d.v, 1, "version 1")
	eq(d.stardust, 0, "no Stardust")
	eq(d.lifetime, 0, "no lifetime")
	eq(d.beacon, 0, "Beacon 0")
	eq(d.collector, 0, "no Collector")
	eq(d.smelter, 0, "Smelter 0")
	eq(d.hopper, 0, "an empty hopper")
	eq(d.star, 0, "no Falling Star yet")
	eq(d.starCores, 0, "no Star Cores")
	eq(d.tutorial, 0, "the first hint")
	eq(d.beaconAt, 0, "never reached a level")
	local d2 = Save.defaults()
	d2.stardust = 5
	eq(Save.defaults().stardust, 0, "defaults() hands out a fresh table every time")
end

--============================================================================ normalise
do
	eq(Save.normalise(C, nil).beacon, 0, "nil loads as a new profile")
	eq(Save.normalise(C, "garbage" :: any).beacon, 0, "a string loads as a new profile")
	local n = Save.normalise(C, {
		stardust = -50, lifetime = 0 / 0, beacon = 12.7, beaconAt = 1790000000.4, collector = 11,
		smelter = "7", hopper = math.huge, star = 5, starCores = -1, tutorial = 9, junk = { 1, 2, 3 }, v = 99,
	})
	eq(n.stardust, 0, "negative Stardust loads as 0")
	eq(n.lifetime, 0, "NaN lifetime loads as the default")
	eq(n.beacon, 12, "a fractional level is floored")
	eq(n.beaconAt, 1790000000, "beaconAt is floored")
	eq(n.collector, 8, "the Collector is clamped to 8")
	eq(n.smelter, 0, "a string level is not a number: the default")
	eq(n.hopper, 0, "an infinite hopper loads as the default")
	eq(n.star, 0, "an unknown star state is 'not granted'")
	eq(n.starCores, 0, "negative Star Cores load as 0")
	eq(n.tutorial, 3, "the tutorial is clamped to 3")
	eq(n.junk, nil, "unknown fields are dropped")
	eq(n.v, 1, "the version is the current one")
	local ok = Save.normalise(C, { stardust = 1234.5, lifetime = 99999, beacon = 22, beaconAt = 1790000000, collector = 5,
		smelter = 15, hopper = 12.25, star = 2, starCores = 3, tutorial = 3 })
	eq(ok.stardust, 1234.5, "a sane record keeps its Stardust")
	eq(ok.hopper, 12.25, "and its hopper (melts again next session, never offline)")
	eq(ok.star, 2, "and its star state")
	eq(ok.collector, 5, "and its Collector")
	-- lifetime can never be below spendable Stardust
	eq(Save.normalise(C, { stardust = 500, lifetime = 20 }).lifetime, 500, "lifetime is at least the Stardust you hold")
end

--============================================================================ the one-time Falling Star
do
	local d = Save.defaults()
	eq(Save.grantStar(d), true, "0 -> 1: granted")
	eq(d.star, 1, "granted, not caught")
	eq(Save.grantStar(d), false, "it cannot be granted twice")
	eq(Save.catchStar(d), true, "1 -> 2: caught")
	eq(d.star, 2, "caught")
	eq(Save.catchStar(d), false, "it cannot be caught twice")
	eq(Save.grantStar(d), false, "and a caught star is never granted again")
	local fresh = Save.defaults()
	eq(Save.catchStar(fresh), false, "a star that was never granted cannot be caught")
	eq(fresh.star, 0, "and stays 0")
end

--============================================================================ pack: what is written
do
	local d = Save.normalise(C, { stardust = 7, beacon = 3, beaconAt = 1790000000 })
	local p = Save.pack(d)
	local numeric = 0
	local fields = 0
	for k in p do
		fields += 1
		if type(k) ~= "string" then numeric += 1 end
	end
	eq(numeric, 0, "no integer keys anywhere in a written profile (JSON would turn them into strings)")
	eq(fields, 12, "exactly the 12 documented fields are written (REVIEW-1 added `awake`)")
	eq(p.stardust, 7, "values carried over")
	p.stardust = 999
	eq(d.stardust, 7, "pack() writes a copy, not the live profile")
	local back = Save.normalise(C, p)
	eq(back.beacon, 3, "pack -> normalise is a round trip")
end

--============================================================================ the Collector's clock survives a rejoin (REVIEW-1)
do
	local idle = C.Collector.IdleSeconds
	eq(Save.normalise(C, { beacon = 3 }).awake, idle, "a record without the field (or a new player's first save) starts awake")
	eq(Save.normalise(C, nil).awake, 0, "no record at all: the defaults (the server keeps a new session awake itself)")
	eq(Save.normalise(C, { awake = 0 }).awake, 0, "a Collector saved asleep loads asleep: a rejoin does not re-arm it")
	eq(Save.normalise(C, { awake = 123.5 }).awake, 123.5, "the seconds left are kept, fractions too")
	eq(Save.normalise(C, { awake = idle * 5 }).awake, idle, "never more than IdleSeconds")
	eq(Save.normalise(C, { awake = -40 }).awake, 0, "never negative")
	eq(Save.normalise(C, { awake = 0 / 0 }).awake, idle, "NaN is treated as missing")
	eq(Save.normalise(C, { awake = "600" }).awake, idle, "a string is treated as missing")
	local d = Save.normalise(C, { awake = 42 })
	eq(Save.pack(d).awake, 42, "and it is written")
end

print(string.format("Save: %d passed, %d failed", passed, failed))
if failed > 0 then error("Save spec failed", 0) end
