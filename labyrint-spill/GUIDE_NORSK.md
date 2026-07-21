# Labyrint-spill — kom i gang

En enkel oppskrift for å få spillet til å kjøre i Roblox Studio, og hvordan
dere skrur på vanskelighetsgraden selv. Skrevet så Marius kan følge med.

## 1. Få det til å kjøre (5 minutter)

1. Åpne **Roblox Studio** og lag et nytt sted: **New → Baseplate**.
2. Finn **Explorer**-vinduet (View → Explorer hvis det er skjult).
3. Hold musa over **ServerScriptService**, trykk **+**, og velg **Script**.
4. Slett det som står i skriptet fra før.
5. Åpne `MazeGame.server.luau` (fila dere fikk), marker alt, kopier, og lim inn
   i skriptet i Studio.
6. Trykk den store **Play**-knappen.

Du havner inne i en liten labyrint. Gå til den **grønne** ruta du står på — det
er start. Finn den **røde/grønne** ruta i motsatt hjørne — det er utgangen.
På level 1 er det ingen monstre og ingen feller, bare finn veien ut og plukk
noen mynter. Kommer du deg ut, bygges neste (litt vanskeligere) nivå.

Ser du meldingen `[Labyrint] Lastet...` nede i **Output**-vinduet, funker alt.

## 2. Slik spiller man

- **Kom deg ut.** Utgangen er låst til du har samlet alle myntene i banen
  (skiltet over utgangen viser hvor mange som gjenstår). Da blir den grønn.
- **Mynter** (gule) er vanlige. **Edelstener** (lilla) er sjeldne. Begge lagres
  og skal brukes i hver sin butikk senere (v2).
- **Pokaler** får du hver gang du kommer deg ut — det er hiscore/bragging.
- **Skjulte knapper** (turkise): trykk på dem (gå inn i dem), så glir en vegg
  til side og åpner en snarvei.
- **Feller** (oransje gulv) og **monstre** (røde) dreper deg — du havner tilbake
  på start. Monstre er alltid litt tregere enn deg, så du kan løpe fra dem.

## 3. Skru på vanskelighetsgrad (CONFIG)

Helt øverst i skriptet er det en `CONFIG`-blokk. Endre tall der, trykk Play på
nytt. De viktigste:

- `UnlockExitBy` — hva som må samles for å åpne utgangen: `"coins"` (standard),
  `"gems"`, eller `"none"` (åpen med en gang).
- `Darkness` — sett `false` for å skru av mørket helt (hvis dere vil se alt).
- `TorchRange` — hvor stor lyskula rundt spilleren er.
- `MultipleLevels` — `false` gir bare samme størrelse om og om igjen.
- `WorldSeed` — «frøet» som bestemmer hvordan alle banene ser ut. Samme frø gir
  samme baner for alle spillere, hver gang (level 4 er lik for deg og for Marius).
  Vil dere ha helt nye labyrinter? Bytt tallet, så trekkes alle nivåene om — og
  de blir like for alle igjen. (Monstrene vandrer fortsatt tilfeldig; det er med vilje.)

### Progresjonskurven
Under `Curve` bestemmer dere hvordan spillet blir vanskeligere fra level 1 mot
500. Tenk på den slik: **hvert tak nås omtrent på level 500.**

- `StartSize` = hvor stor labyrinten er på level 1 (6 = 6x6, veldig lite).
- `MaxSize` = største labyrint (30x30).
- `FirstMonsterLevel` = første nivå med monstre (4). Sett høyere for en snillere
  start, eller `1` for monstre med en gang.
- `FirstTrapLevel` = første nivå med feller (3).
- `MonsterSpeedMax` = 15. La den stå under 16 (spillerens fart), ellers blir
  monstrene umulige å løpe fra.

Vil dere teste et vanskelig nivå uten å spille dere dit? Sett midlertidig
`StartSize` høyt og `FirstMonsterLevel = 1`, og se hvordan level 1 blir.

## 4. Hvis noe krangler

- **Monstrene står stille eller oppfører seg rart:** det er den vanskeligste
  biten. Sett `FirstMonsterLevel` høyt (f.eks. `999`) for å spille uten dem
  mens dere feilsøker resten. Sjekk også at gulvet er stort nok til at
  pathfinding finner vei (øk `CellSize`).
- **Spilleren sitter fast i gangene:** øk `CellSize` (f.eks. til `11`).
- **Mynter/pokaler nullstilles hver gang dere logger av:** lagring (DataStore)
  virker bare i publiserte spill, eller i Studio hvis dere skrur på
  **Game Settings → Security → Enable Studio Access to API Services**. Ellers
  sett `SaveData = false` så slipper dere feilmeldinger.
- **Alt for mørkt:** øk `MinSight` og `StartSight` i `Curve`, eller sett
  `Darkness = false`.

## 5. Hva som kommer i v2

De to butikkene. **Mynt-butikken** selger perks som forbedrer spillet (lengre
fakkel, litt fart, ekstra liv, tregere monstre, minikart). **Edelsten-butikken**
selger kosmetikk (skins, farger, spor bak deg). Valutaen lagres allerede, så
det som gjenstår er butikk-vinduet og kjøpslogikken. Se `CLAUDE.md` for planen.
