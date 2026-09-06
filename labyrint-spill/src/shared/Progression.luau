--!strict
-- Ren progresjons-logikk for labyrint-spillet. Ingen Roblox-API, så den kan
-- testes med luau CLI (se tests/Progression.spec.luau).
--
-- "accepted" = høyeste nivå en spiller har fullført I SEKVENS (for å få N må du
-- allerede ha N-1) UTEN at gudemodus var på i runden. Dette er grunnlaget for
-- topplista og kan aldri hoppe eller blåses opp.
--
-- Gud-regel: ble gudemodus brukt på nivået (av HVEM som helst i instansen),
-- teller fullføringen for INGENTING (ingen accepted, ingen rekord, ingen
-- toppliste) — men "bestWithGod" (høyeste nådd med gud) kan fortsatt oppdateres.
--
-- Guide-regel ("Hjelp meg", se Assist): ble det kjøpt en rute-guide på nivået,
-- gir kjøringen INGEN tidsrekord og INGEN personlig bestetid — men accepted
-- teller fortsatt, for spilleren gikk faktisk ut selv. Guiden viser bare veien;
-- den hopper ikke over noe. Slik kan en som står fast komme videre uten at
-- rekordtavla kan kjøpes for mynter.

local Progression = {}

-- Skal denne kjøringen kunne sette tid/rekord? Én kilde til sannhet, brukt både
-- av resolveClear og av serveren når den avgjør "clean".
function Progression.recordEligible(hadGod: boolean?, usedAssist: boolean?): boolean
	return not (hadGod or usedAssist)
end

-- Seed accepted fra spillerens personlige rekorder ved migrering: høyeste N slik
-- at bestByLevel["1"] .. ["N"] alle finnes (lengste sammenhengende rekke fra 1).
-- DataStore lagrer heltalls-nøkler som tekst, derfor tostring().
function Progression.seedAccepted(bestByLevel: { [string]: number }): number
	local n = 0
	if type(bestByLevel) == "table" then
		while type(bestByLevel[tostring(n + 1)]) == "number" do
			n += 1
		end
	end
	return n
end

export type ClearArgs = {
	level: number,
	accepted: number,
	bestWithGod: number,
	hadGod: boolean,
	usedAssist: boolean?,  -- rute-guide kjøpt på nivået (se Assist)
	mode: string?,        -- "solo" | "group" | "friends" (ikke brukt i reglene ennå)
	isHostLevel: boolean?, -- reservert for friends-modus
}

export type ClearResult = {
	newAccepted: number,
	newBestWithGod: number,
	acceptedGained: boolean,
	recordEligible: boolean,
	leaderboardEligible: boolean,
}

-- Avgjør hva en fullføring gir. acceptedGained bare hvis INGEN gud OG nivået er
-- nøyaktig accepted+1 (sekvensielt — hindrer både carry og gud-til-500-jukset).
-- MERK: usedAssist rører BARE recordEligible. Den kan verken gi eller ta bort
-- accepted, så guiden kan aldri blåse opp det sekvensielle tallet.
function Progression.resolveClear(a: ClearArgs): ClearResult
	local hadGod = a.hadGod and true or false
	local usedAssist = a.usedAssist and true or false
	local accepted = a.accepted or 0
	local gained = (not hadGod) and (a.level == accepted + 1)
	return {
		newAccepted = gained and (accepted + 1) or accepted,
		newBestWithGod = math.max(a.bestWithGod or 0, a.level),
		acceptedGained = gained,
		recordEligible = Progression.recordEligible(hadGod, usedAssist),
		leaderboardEligible = not hadGod,
	}
end

return Progression
