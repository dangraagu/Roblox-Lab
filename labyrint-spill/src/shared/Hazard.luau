--!strict
-- Ren felle-puls-logikk (lava som slår seg av og på). INGEN Roblox-API og INGEN
-- `script` — testbar med luau CLI (se tests/Hazard.spec.luau).
--
-- HVORFOR: labyrinten er et PERFEKT tre (recursive backtracker) — det finnes
-- nøyaktig ÉN rute fra start til utgang. En felle fyller hele korridoren
-- (CellSize - 2 studs bred) med en 10 studs høy dødelig trigger, så den kan
-- verken gås rundt eller hoppes over. Sto fella på den eneste ruta, var nivået
-- umulig. Løsningen er ikke å fjerne fella, men å la den PULSERE, slik at det
-- alltid finnes et trygt vindu å gå gjennom i.
--
-- Syklusen (ett omløp = OffTime + OnTime):
--   [0 .. OffTime-WarnTime)          "safe"    mørk, ufarlig
--   [OffTime-WarnTime .. OffTime)    "warn"    gul, ufarlig — forvarsel
--   [OffTime .. OffTime+OnTime)      "deadly"  oransje, dreper
-- "safe" og "warn" er BEGGE ufarlige, så det trygge vinduet er hele OffTime.

local Hazard = {}

export type Config = {
	Pulse: boolean?,
	OffTime: number,
	WarnTime: number,
	OnTime: number,
	MinSafeSeconds: number?,
}

-- Ett fullt omløp i sekunder.
function Hazard.cycle(cfg: Config): number
	return cfg.OffTime + cfg.OnTime
end

-- Hvor lenge fella er ufarlig pr omløp (safe + warn).
function Hazard.safeSeconds(cfg: Config): number
	return cfg.OffTime
end

-- Hvilken fase er fella i `t` sekunder etter at pulsen startet?
function Hazard.phaseAt(t: number, cfg: Config): string
	if cfg.Pulse == false then return "deadly" end   -- puls av = gammel oppførsel
	local cycle = Hazard.cycle(cfg)
	if cycle <= 0 then return "deadly" end
	local p = t % cycle
	if p < 0 then p += cycle end                      -- negativ t skal ikke kunne bomme
	if p >= cfg.OffTime then return "deadly" end
	if p >= cfg.OffTime - cfg.WarnTime then return "warn" end
	return "safe"
end

function Hazard.isDeadly(t: number, cfg: Config): boolean
	return Hazard.phaseAt(t, cfg) == "deadly"
end

-- Rekker man over en felle i det trygge vinduet? `crossSeconds` = tiden det tar
-- å gå inn på fella og helt av den igjen.
function Hazard.canCross(cfg: Config, crossSeconds: number): boolean
	if cfg.Pulse == false then return false end
	return Hazard.safeSeconds(cfg) >= crossSeconds
end

-- Tiden det tar å krysse ei felle: fellas dybde + en hel celle på hver side
-- (innspurt + å komme helt av), delt på gangfarten.
function Hazard.crossSeconds(cellSize: number, walkSpeed: number): number
	if walkSpeed <= 0 then return math.huge end
	return ((cellSize - 2) + 2 * cellSize) / walkSpeed
end

-- VAKTPOSTEN: gjør en hvilken som helst CONFIG.Traps-blokk garantert passerbar.
-- Returnerer en RETTET kopi + en liste over hva som ble endret. Serveren kjører
-- denne ved oppstart, så en fremtidig CONFIG-redigering aldri kan gjenskape den
-- umulige tilstanden (felle som står evig på den eneste ruta).
-- `minSafe` = korteste trygge vindu vi godtar (typisk Hazard.crossSeconds(...)).
function Hazard.sanitize(cfg: Config, minSafe: number): (Config, { string })
	local fixes: { string } = {}
	local out: Config = {
		Pulse = cfg.Pulse ~= false,
		OffTime = tonumber(cfg.OffTime) or 0,
		WarnTime = tonumber(cfg.WarnTime) or 0,
		OnTime = tonumber(cfg.OnTime) or 0,
		MinSafeSeconds = cfg.MinSafeSeconds,
	}
	-- Puls AV er en bevisst rollback-bryter og røres ikke; alt annet rettes.
	if out.Pulse == false then return out, fixes end

	local floor = math.max(minSafe, tonumber(cfg.MinSafeSeconds) or 0)
	if out.OnTime <= 0 then
		out.OnTime = 1
		table.insert(fixes, "OnTime <= 0 -> 1")
	end
	if out.OffTime < floor then
		table.insert(fixes, string.format("OffTime %.2f -> %.2f (for kort trygt vindu)", out.OffTime, floor))
		out.OffTime = floor
	end
	if out.WarnTime < 0 then
		out.WarnTime = 0
		table.insert(fixes, "WarnTime < 0 -> 0")
	end
	if out.WarnTime >= out.OffTime then
		local w = out.OffTime / 2
		table.insert(fixes, string.format("WarnTime %.2f -> %.2f (måtte være < OffTime)", out.WarnTime, w))
		out.WarnTime = w
	end
	return out, fixes
end

return Hazard
