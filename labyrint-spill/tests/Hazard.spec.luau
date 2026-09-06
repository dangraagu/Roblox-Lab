-- Rene logikk-tester for Hazard (pulsende feller). Kjør med luau CLI:
--   luau tests/Hazard.spec.luau
-- (Ingen Roblox-API brukt.)
--
-- Den VIKTIGE testen her er "aldri evig dødelig": det var nettopp en felle som
-- sto permanent på den eneste ruta som gjorde nivåene umulige (F1).

local Hazard = require("../src/shared/Hazard")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(v, msg) eq(v and true or false, true, msg) end

-- Samme verdier som CONFIG.Traps i src/server/MazeGame.server.luau.
local CFG = { Pulse = true, OffTime = 3.0, WarnTime = 0.8, OnTime = 2.2, MinSafeSeconds = 1.5 }

-- Syklus + trygt vindu
eq(Hazard.cycle(CFG), 5.2, "cycle = OffTime + OnTime")
eq(Hazard.safeSeconds(CFG), 3.0, "safe window = OffTime (safe + warn)")

-- Faser gjennom ett omløp
eq(Hazard.phaseAt(0, CFG), "safe", "t=0 -> safe")
eq(Hazard.phaseAt(2.1, CFG), "safe", "just before warn -> safe")
eq(Hazard.phaseAt(2.2, CFG), "warn", "OffTime-WarnTime -> warn")
eq(Hazard.phaseAt(2.9, CFG), "warn", "late in warn -> warn")
eq(Hazard.phaseAt(3.0, CFG), "deadly", "OffTime -> deadly")
eq(Hazard.phaseAt(5.1, CFG), "deadly", "late in deadly -> deadly")
eq(Hazard.phaseAt(5.2, CFG), "safe", "wraps to next cycle -> safe")
eq(Hazard.phaseAt(5.2 * 100 + 1.0, CFG), "safe", "stable after many cycles")
eq(Hazard.phaseAt(-1.0, CFG), "deadly", "negative t still lands in the cycle")

-- isDeadly speiler phaseAt
eq(Hazard.isDeadly(1.0, CFG), false, "safe -> not deadly")
eq(Hazard.isDeadly(2.5, CFG), false, "warn is a TELEGRAPH, not lethal")
eq(Hazard.isDeadly(4.0, CFG), true, "deadly -> deadly")

-- Rollback-bryteren: Pulse = false gir eksakt gammel oppførsel (alltid dødelig)
local OFF = { Pulse = false, OffTime = 3.0, WarnTime = 0.8, OnTime = 2.2 }
eq(Hazard.phaseAt(0, OFF), "deadly", "Pulse=false -> always deadly")
eq(Hazard.phaseAt(1.0, OFF), "deadly", "Pulse=false -> always deadly (t=1)")
eq(Hazard.canCross(OFF, 0.1), false, "Pulse=false -> no crossing window at all")

-- ALDRI EVIG DØDELIG: i ethvert vindu på én syklus finnes et trygt øyeblikk.
-- (Dette er selve F1-invarianten — en felle kan aldri sperre ruta for godt.)
do
	local cycle = Hazard.cycle(CFG)
	local worst = 0
	for start = 0, 200 do
		local t = start * 0.037
		local run = 0
		-- hvor lenge på rad er den dødelig fra dette tidspunktet?
		while Hazard.isDeadly(t + run, CFG) and run <= cycle + 1 do run += 0.01 end
		if run > worst then worst = run end
	end
	truthy(worst < CFG.OnTime + 0.05, "longest unbroken deadly stretch <= OnTime")
	truthy(worst < cycle, "deadly stretch is always shorter than a full cycle")
end

-- Krysse-vinduet må være stort nok for den EKTE banen (CellSize 9, gangfart 16).
do
	local cross = Hazard.crossSeconds(9, 16)
	truthy(cross > 0, "crossSeconds positive")
	eq(math.floor(cross * 1000 + 0.5), 1563, "cross = (7 + 18) / 16 = 1.5625s")
	truthy(Hazard.canCross(CFG, cross), "shipped config leaves room to walk across")
	truthy(Hazard.canCross(CFG, Hazard.crossSeconds(9, 16 + 3)), "also with the speed perk")
end

-- sanitize: en fremtidig CONFIG-redigering kan ikke gjenskape den umulige banen
do
	local ok, fixes = Hazard.sanitize(CFG, Hazard.crossSeconds(9, 16))
	eq(#fixes, 0, "shipped config needs no fixing")
	eq(ok.OffTime, 3.0, "shipped OffTime untouched")
	eq(ok.Pulse, true, "shipped Pulse untouched")

	-- for kort trygt vindu -> løftes til gulvet
	local bad = { Pulse = true, OffTime = 0.2, WarnTime = 0.1, OnTime = 5 }
	local fixed, f2 = Hazard.sanitize(bad, 1.5)
	truthy(#f2 > 0, "too-short safe window is reported")
	truthy(fixed.OffTime >= 1.5, "OffTime raised to the floor")
	truthy(Hazard.canCross(fixed, 1.5), "sanitized config is crossable")

	-- WarnTime som sluker hele det trygge vinduet -> halveres
	local warny = { Pulse = true, OffTime = 3.0, WarnTime = 9.0, OnTime = 2.0 }
	local fixed2, f3 = Hazard.sanitize(warny, 1.5)
	truthy(#f3 > 0, "WarnTime >= OffTime is reported")
	truthy(fixed2.WarnTime < fixed2.OffTime, "WarnTime forced below OffTime")
	eq(Hazard.phaseAt(0, fixed2), "safe", "there is still a fully-safe stretch")

	-- OnTime <= 0 -> settes til noe fornuftig (fella må fortsatt være farlig iblant)
	local dead = { Pulse = true, OffTime = 3.0, WarnTime = 0.5, OnTime = 0 }
	local fixed3, f4 = Hazard.sanitize(dead, 1.5)
	truthy(#f4 > 0, "OnTime <= 0 is reported")
	truthy(fixed3.OnTime > 0, "OnTime raised above zero")

	-- rollback-bryteren respekteres av sanitize (den er et bevisst valg)
	local off, f5 = Hazard.sanitize({ Pulse = false, OffTime = 0, WarnTime = 0, OnTime = 0 }, 1.5)
	eq(off.Pulse, false, "sanitize never flips the rollback switch back on")
	eq(#f5, 0, "Pulse=false is left completely alone")
end

print(string.format("Hazard: %d passed, %d failed", passed, failed))
assert(failed == 0, "Hazard tests failed")
