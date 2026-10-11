# CLAUDE.md — Labyrint-spill (Roblox)

Kontekst for Claude Code slik at en ny økt kan fortsette der vi slapp.

## Hva dette er
Et Roblox-labyrintspill som lages av en onkel og nevøen hans (Marius, barn som
lærer). Målet er å komme seg ut av en labyrint mens feller og monstre prøver å
stoppe deg, samle ting på veien, og finne skjulte knapper som åpner snarveier.
Planlagt omfang: **500 nivåer** med en progresjonskurve, og senere **to butikker**.

Tone i koden: norske kommentarer, alt styrt fra en `CONFIG`-blokk, hver funksjon
kan skrus av med `true/false` så et system som krangler ikke velter resten.

## Nåværende tilstand (v1 — ferdig)
Alt ligger i ett server-skript: `src/server/MazeGame.server.luau`
(havner i `ServerScriptService` som en `Script`).

Implementert:
- Prosedyre-generert labyrint (recursive backtracker), deterministisk pr nivå
  (samme `WorldSeed` + samme level = nøyaktig samme bane for alle — se under).
- Kom-deg-ut-mål: utgang som låses opp når kravet er nådd (`CONFIG.UnlockExitBy`
  = "coins" | "gems" | "none"). Skilt over utgangen viser hvor mye som gjenstår.
- Feller (drepende gulv-plater).
- Monstre som jager med `PathfindingService` innenfor `MonsterDetectRange`,
  ellers vandrer tilfeldig. Dreper ved berøring. Enkel 1-parts Humanoid-rigg.
- Mynter (vanlige) og edelstener (sjeldne) — samles, teller opp, lagres.
- Pokaler — gis for hver gang du kommer deg ut (hiscore/bragging).
- Skjulte knapper som tweener en bestemt "SecretWall" ned i gulvet (snarvei).
- Timer + beste tid pr spiller.
- Mørke + fakkel: `Lighting`-tåke + `PointLight` på spilleren. Sikten strammes
  litt pr nivå.
- Flere nivåer med progresjonskurve (se under).
- DataStore-lagring av mynter/edelstener/pokaler/beste tid (`CONFIG.SaveData`).
  Krever publisert spill, eller Studio med "Enable Studio Access to API Services".

## Progresjonskurven (`CONFIG.Curve`, `getDifficulty(L)`)
Tanken: level 1 er bitteliten og ufarlig, vanskeligheten introduseres gradvis,
og alle tak nås omtrent ved level 500. Spillet fortsetter uendelig etter det
(kurven platår).
- Størrelse: 6x6 → 30x30 (+1 hver 20. level).
- Feller: ingen før level 3, så +1 hver 17. level (tak 30).
- Monstre: ingen før level 4, +1 hver 50. level (tak 10).
- Monsterfart: 7 → 15. Spilleren går 16, så man kan alltid rømme ved å løpe.
- Mynter: ~10% av gangene (skalerer med størrelsen).
- Sikt (mørke): 60 → 35.
Endre kurven ett sted (`CONFIG.Curve`) — ikke spre magiske tall utover koden.

## Deterministiske nivåer (WorldSeed)
`CONFIG.WorldSeed` (nå `20260721`) gjør nivåene forutsigbare. Frøet til hvert
nivå = `WorldSeed` + level-nummeret, og det bestemmer alt i banen: selve
labyrinten og hvor mynter, edelstener, feller, skjulte knapper og utgangen havner.
Derfor er «level 4» helt lik for alle spillere, hver eneste gang (før dette fikk
hver runde en ny tilfeldig bane).

Vil du trekke om alle nivåene på én gang? Endre `WorldSeed` til et annet tall —
da får du et helt nytt sett baner, og de er igjen identiske for alle etterpå.

Unntak med vilje: monstrenes vandring er fortsatt tilfeldig. Det er levende
oppførsel i sanntid, ikke en del av selve bane-oppsettet, så den styres ikke av frøet.

## Tema-butikk (vegg-temaer) — BYGGET
Kosmetisk butikk der spilleren kjøper vegg-temaer med in-game-valuta.
- **17 temaer** (`src/shared/Themes.luau`, ren data): `classic` (gratis, eid fra
  start) + 16 kjøpbare (Tyggegummi, LEGO, Isgrotte, Synthwave, Jul, Halloween,
  Gulltempel osv.). Hvert tema = wall/secret/floor-farge + pris i BEGGE valutaer.
- **Kjøp med Mynter ELLER Edelstener** — hvert tema har `coinPrice` og `gemPrice`.
- **Ren kjøpslogikk** i `src/shared/ShopService.luau` (server-autoritativ,
  muterer bare ved suksess). Testet med luau-CLI (24/24) — se `docs/` / scratch.
- **Per-spiller utseende**: `src/client/ShopClient.client.luau` farger om
  Wall/SecretWall/Floor LOKALT til spillerens valgte tema (klient-endring
  replikeres ikke), så alle ser sitt eget tema på den delte labyrinten.
  `classic` = ingen omfarging (serverens originalfarger).
- **Eierskap + valgt tema lagres** i samme DataStore-tabell (`owned`, `theme`).
- **Robux -> edelstener**: `MarketplaceService.ProcessReceipt`-stub i serveren,
  idempotent via `receipts`. AV som standard (`RobuxConfig.EnableRobux = false`).
  Skru på senere: lag Developer Products på Roblox, fyll inn `RobuxGemProducts`,
  sett `EnableRobux = true`. GJENNOMGÅ før ekte penger skrus på.
- Remotes: `ReplicatedStorage/ShopRemotes` (BuyTheme/SelectTheme RemoteFunctions,
  ShopData RemoteEvent).

## HUD, medaljer og rekorder — BYGGET
TrackMania-inspirert nivå-HUD + oppsummering.
- **HUD** (`src/client/HudClient.client.luau`, øverst på skjermen): "Nivå N", global
  rekord for nivået (tid + navn), og din beste tid på nivået. Oppdateres via
  `HudRemotes/LevelInfo` (server sender ved hver bygging + spawn).
- **Nivå-fullført-kort** (samme fil): medalje-badge (farge/navn), din tid, din beste
  (med "Ny personlig rekord!" hvis slått), rekorden (med "NY REKORD!" hvis slått),
  og en rad med medalje-mål-tidene. Vises via `HudRemotes/LevelComplete` (kun til den
  som kom seg ut). Auto-lukkes etter ~4.5s.
- **Medaljer** = Bronse/Sølv/Gull/Diamant. "Optimal tid" (par) regnes AUTOMATISK pr
  nivå i `src/shared/Medals.luau` (ren logikk, 21/21 luau-tester): grådig BFS-rute
  som samler alt utgangen krever og så når utgangen -> par = steg×CellSize/gangfart.
  Medaljene = par × { Diamant 1.3, Gull 1.8, Sølv 2.5, Bronse 4.0 } (juster i
  `Medals.mult`). Deterministisk => medalje-tidene er like for alle. Par er lange på
  høye nivåer fordi man må samle ALLE mynter i store labyrinter — meningen er å
  speedrunne nivåer man kan (levels er deterministiske).
- **Rekorder**: personlig beste pr nivå lagres i spillerens DataStore-tabell
  (`bestByLevel`, nøkkel = `tostring(level)` fordi DataStore gjør heltalls-nøkler om
  til tekst). Global rekord pr nivå i egen DataStore `LabyrintRekord_v1` (atomisk
  `UpdateAsync`, cachet, oppdatering skjer async så nivå-bygging ikke bremses).
- **Kjent begrensning**: Roblox har klient-styrt bevegelse. Siden 01.10 har serveren et tidsgulv
  (gå-vakta) og siden 11.10 sti-bevis (sti-vakta), se "Komplett-standarden" under: en teleport til
  utgangen teller ikke lenger, heller ikke etter å ha ventet. Det som IKKE er stoppet: et skript som
  følger den ekte ruta (i hopp eller til fots) og dermed kan sette en tid ned mot tidsgulvet.

## Perk-butikk + polish + lyd + mobil + gaver — BYGGET
- **Perk-butikk** (mynter): `src/shared/PerkDefs.luau` (torch/shield/speed/minimap) +
  `src/shared/PerkService.luau` (ren kjøpslogikk, 14/14 tester), server-autoritativ.
  Klient `src/client/PerkClient.client.luau` ("⚡ Oppgraderinger" oppe til venstre).
  Effekter pr spiller: fart+fakkel i `applyPerks` (spawn + rett etter kjøp), skjold i
  `killTouch` (1s uskadelig-vindu så ett treff = én bruk), minikart klient-side.
  Remotes `ReplicatedStorage/PerkRemotes` (BuyPerk/PerkData); eide perks lagres.
- **Minikart**: `src/client/MinimapClient.client.luau` — kun synlig hvis minikart-perk
  eies; vegger/utgang/start + live spillerprikk fra `workspace.MazeGame` (cap 2200 dots).
- **Engangs-gaver** (`GIFTS` i serveren): navngitte spillere får startkapital første
  gang de blir med (MioSpille = 999999 mynter + edelstener), gis ÉN gang og lagres.
  Match på brukernavn (eller sett `userId`).
- **Data-vern**: `d.canSave` (load-success sentinel) — serveren nekter å lagre hvis
  DataStore-lasten feilet, så ekte data aldri overskrives med default.
- **Gudemodus** (`src/shared/GodUsers.luau` allow-list, kun MioSpille): fly + gå
  gjennom vegger + udødelig. `GodRemotes/SetGodMode`; serveren gir udødelighet KUN
  til GodUsers (verifisert på brukernavn). Klient `GodModeClient.client.luau` — fly
  via `humanoid.MoveDirection` (mobil-joystick) + ▲/▼-knapper, noclip via CanCollide.
  Gudemodus-runder setter IKKE global rekord (beskytter tavla).
- **Lyd**: `src/shared/Sounds.luau` (innebygd ping, byttbar) + `SoundClient.client.luau`
  (pickup/død/medalje/rekord via Fx-event + LevelComplete). Musikk opt-in.
- **Polish**: monstre = server-network-owner (jevnere); feller har høy usynlig trigger.
- **Mobil**: shop/HUD/kort skalert for telefon (44px-knapper, TextScaled, MaxSize).

## Pulsende feller + "Hjelp meg"-guiden — BYGGET (etter spiller-tilbakemelding)
En ekte spiller (u/popovitsj på r/RobloxDevelopers) testet spillet og meldte to
ting. Begge er nå adressert.

### 1. "Kom meg ikke forbi lava-dammen" — det var en EKTE blokkering
Diagnose (ikke en gjetning): labyrinten er et **perfekt tre** (recursive
backtracker), så det finnes nøyaktig ÉN rute fra start til utgang. Feller ble
trukket fra `pool` = alle passasjeceller unntatt start- og utgangs-cella — altså
**uten å ekskludere ruta**. En felle fyller korridoren (`CellSize - 2` = 7 av 9
studs) og har en 10 studs høy `TrapTrigger`, så den kan verken gås rundt (1 stud
klaring pr side) eller hoppes over (hopp når ~6,4 studs). Treff = `Health = 0`.
Eneste motmiddel var skjold-perken til 600 mynter — på level 6 har en ny spiller
~15-25 mynter. Simulering (20 000 baner pr nivå, samme plasserings-rekkefølge som
koden): level 6 = **52,7 %** sjanse for felle på den eneste ruta, **23,6 %** helt
uløselig selv om alle hemmelige dører sto åpne; level 100: 92,7 % / 84,6 %;
level 300+: ~98 % / ~95 %. Level 6 er nøyaktig første nivå med felle — det
stemmer med "level 5 eller 6".

**Fiks:** fellene PULSERER nå — TRYGG → FORVARSEL (gul) → DØDELIG → TRYGG. De er
like dødelige, men det finnes alltid et vindu å gå gjennom i. Alle feller i samme
labyrint går i takt (lett å lese). Står du oppå fella når den tenner, dør du
(`GetTouchingParts` ved tenning) — man kan ikke bare stå stille på lavaen.
- Ren logikk: `src/shared/Hazard.luau` (fase-regning + `sanitize`), 36/36 tester.
- `Hazard.sanitize` kjøres ved oppstart mot `CONFIG.Traps`: er det trygge vinduet
  for kort til å gå over ei felle, klampes det opp og det varsles i Output. Slik
  kan ingen fremtidig CONFIG-redigering gjenskape den umulige tilstanden.
- `CONFIG.Traps.Pulse = false` gir eksakt gammel oppførsel (rollback).

### 2. Vanskelighets-veggen — "Hjelp meg"-guiden
Serveren teller mislykkede forsøk pr spiller pr nivå (`stuckState`). Etter
`CONFIG.Assist.OfferAfterFails` (3) ekte forsøk dukker det opp et kort: kjøp en
**lysende rute til utgangen for mynter**, for ÉN kjøring.
- Ren logikk: `src/shared/Assist.luau` (pris, gating, rute-uthenting, tynning),
  70/70 tester. `Medals.dist` sendes INN som argument — delte moduler krever
  aldri hverandre via sti (`require("./X")` er ugyldig i Roblox).
- Klient: `src/client/AssistClient.client.luau` (kort nederst; kjøp-knapp inne i
  labyrinten, hint i lobbyen). Klienten sender et ønske UTEN argumenter.
- **Kan ikke utnyttes:** prisen regnes på serveren; forsøk telles kun ved ekte
  død/retur (og en frivillig retur under `MinRunSeconds` teller ikke, så man kan
  ikke gå inn og ut av døra for å låse opp); guiden gjelder bare nøyaktig det
  nivået forsøkene gjelder; én guide pr kjøring; ingen hopp — `accepted` krever
  fortsatt nøyaktig `accepted+1` uten gud. En guide-kjøring gir **ingen tidsrekord
  og ingen personlig bestetid** (`Progression.recordEligible`), så rekordtavla kan
  ikke kjøpes for mynter.
- `CONFIG.Assist.Enabled = false` slår hele mekanikken av. Kun lobby-modus.

## Biomer, fallende farer og hvilerom — BYGGET (23.-24.09.2026, IKKE sett i Studio)
Eierens brief (Gustav 17.09): rikere, aldri monotont, miljøet skifter etter hvert som man kommer
lenger; sjeldne, varslede farer; en måte å hvile på som ikke kan utnyttes; en thumbnail-liste.
**Alt står i `EYECANDY.md`** (biomer, målt sjeldenhet, hvile, budsjetter, porter, Studio-liste, shot-liste).
- **8 biomer etter NIVÅ** (`src/shared/Biomes.luau`): Stone Dungeon (L1) → Jungle Ruins (L11) → Ice Cellar
  (L26) → Lava Forge (L51) → Crystal Caverns (L101) → Haunted Crypt (L161) → Sky Ruins (L241) → Astral
  Labyrinth (L351). Fargetone, partikler og veggpynt; glir over nivåene før en grense.
- **Mørket er mekanikken:** en biome skriver KUN fargetone på samme luma som live-verdien. Siktfeltene
  (Ambient, tåke-avstand, lysstyrke, atmosfære-tetthet, fakkel-rekkevidde) er låst. Biome 1 = live-spillet.
- **Vegger farges aldri** (tema-butikken selger det); pynten avhenger aldri av om veggen er en hemmelig dør.
  Når en hemmelig dør synker, synker pynten med den mens den tones ut, og slippes når døra er under gulvet
  (`Biomes.wallState`: posisjonen avgjør, aldri navnet).
- **Fallende farer** (`src/shared/CellHazards.luau`) fra Ice Cellar: faste celler + fast syklus på
  NIVÅ-klokka, like for alle (medaljetider forblir rettferdige). 3 s varsel, sonen passer inni cella (gangen
  ved siden av er alltid trygg), treff = slått ned 0,8 s, aldri død. Målt: ett nesten-treff per 2,6 min.
  Varselringen er **blå**, aldri fellas gule: gult lys på gulvet betyr "dette gulvet dreper deg straks".
- **Hvile** = mellom runder: bål i lobbyen ("Rest by the fire") + gratis walk-out de første 6 s av hvert
  nivå (serverens egen `Assist.MinRunSeconds`-regel). Aldri pause inne i en løype — klokka ER medaljen.
  Skiltet vises ikke når en "Hjelp meg"-guide er aktiv.
- Alt er klient (`Biome.client`, `RestClient`, `BiomeArt`). Serveren var uendret fram til 30.09 (se under).
- Tester: `tests/Biomes|CellHazards|BreakRoom|Pacing|EnvBands|Rest.spec.luau` + `robloxemu/check_labyrintspill_*.luau`.
- **Adversarial review 24.09:** seks funn, alle lukket med test først og mutasjonstest (`EYECANDY.md` §12).
  Thumbnail-stedet (`Labyrint-shots.rbxlx`, §9) må **aldri** publiseres.
- **Andre review + eierbeslutninger 30.09** (`EYECANDY.md` §13; eieren: "take the recommended option for all"):
  * Friends-vert som går ut under "gratis pause"-skiltet kommer tilbake til vennene sine (`findFriendsInstance` i
    serveren: egen kjøring først, så en venns; Roblox regner deg aldri som din egen venn).
  * Ringen holdes minst CIE delta E 25 unna alt man skal tråkke på (knapper, guide-prikker, mynt, edelsten, exit),
    gjennom hver biome-gradering (`Biomes.StepOnColors`, speilet fra serveren og lest tilbake av `_biomes` §0).
  * Biome-kortet venter også på daglig-belønning-popupen; ingen pynt på Lobby-dørens vegg (`Biomes.reservedFace`);
    del-/emitter-/lys-budsjettet håndheves i `Biomes.validate` (`Biomes.partBound()`).
  * **Guiden beholdes** til nivået er klart (død/retur mister den ikke; lagres som `guideLevel`; aldri på et annet
    nivå; `Assist.keptFor/afterClear`, `applyKeptGuide` i serveren).
  * Et fall-treff er en **stagger** (ingen PlatformStand) når et monster er innen 24 studs; ellers knockdown
    (`CellHazards.hitMode`, `MonsterSafeRadius`). Ringen forblir blå; ingen tema-felle-skins; biomene står der de står
    (`Pacing.spec` holder brag-vinduet 30-45 min og de to siste over 10 t).
- **Pass 1 kjørt på nytt 01.10** (`EYECANDY.md` §14): de fem funnene målt på nytt på dagens tre. Fire reproduserer
  ikke (lukket 30.09, fortsatt lukket). Funn 4 kom tilbake i ny form: smådyrene (pass 2, 01.10, ikke dokumentert
  ennå) kunne bo i start-cella, og en edderkopp klatret rett gjennom døra og pause-skiltet. Nå er start-cella aldri
  et hjem for smådyr (`Biomes.critterHomeFree`, `check_labyrintspill_biomes` §8). Ingen åpne eierbeslutninger.
- **Feller å kjenne til:** headless står monstrene stille, så en sjekk som tester knockdown må parkere dem
  (`check_labyrintspill_hazards` gjør det i `start`). Emulatorens `IsFriendsWith` svarer alltid false;
  `check_labyrintspill_friends` definerer Player-klassen på nytt i selve sjekken (aldri i `robloxemu/emu`).

## Komplett-standarden — pass 2 (01.10.2026, IKKE sett i Studio)
Eierens finish-linje er `docs/complete-game-standard.md` ("lag komplette spill ... inkludert alt vi har diskutert").
Pass 2 bygde det som manglet (01.10 00:09-00:50, kuttet før dokumentasjonen) og ble fullført samme morgen. Alt står i
`EYECANDY.md` §15, med en tabell over hvert punkt i standarden og hvor det holdes.
- **Topplista, offentlig + venner** (`src/shared/Board.luau` = +1 Jumps mal, `BoardConfig.luau`, `BoardClient`):
  rangert på `accepted` (høyeste nivå klart i rekkefølge, målt av serveren), uavgjort til den som nådde det FØRST,
  `LabyrintTopp_v3` med nøkkel `u_<userId>`, skrevet bare når nivået stiger. Offentlig topp 10 hentes høyst hvert
  60. sekund; venner (`GetFriendsAsync`, tak 200) bare når spilleren ber om det, cachet og strupet. En fysisk tavle
  ved spawn ("TOP MAZE RUNNERS", lobbyen (-15, 5, 2)) med en ProximityPrompt som bytter Public/Friends. Navn slås opp
  og huskes i minnet, aldri lagret. Den gamle HUD-tavla virker som før, og den gamle `LabyrintTopp_v2` bæres over.
  Er lageret nede, sier tavla det (ikke "Loading..." for alltid), og en tapt skriving prøves igjen ved autolagring.
- **Gå-vakta** (`Progression.minClearSeconds`, `CONFIG.WalkGuard`): et TIDSGULV. En utgang nådd raskere enn noen
  kan gå dit teller ikke, og spilleren får vite hvorfor. Den sjekker bare NÅR, ikke HVORDAN: alene stoppet den ikke
  et skript som ventet ut gulvet på starten og så teleporterte (andre review 09.10, HIGH).
- **Sti-vakta** (11.10, `src/shared/PathGuard.luau`, `CONFIG.PathGuard`, `seedPath`/`samplePath` i serveren): serveren
  tar prøver av rot-posisjonen 4 ganger i sekundet og holder én GODKJENT posisjon per løper. En prøve flytter den bare
  dit en som går kunne ha kommet gjennom labyrinten (alle planlagte hemmelige dører åpne), betalt fra en konto som
  fylles i 19 studs/s * 1,3 og har tak på 4 s. Venting kjøper altså aldri mer enn 4 s gange; et lagg-hull betaler seg
  selv (tålt: 5,0 s i toppfart med perk, 6,0 s i vanlig fart, målt). Utgangen teller bare når den godkjente cella står
  ved utgangen; ellers får spilleren beskjed og ingenting endres. Mister serveren sporet (alle prøver nektet i 1,5 s)
  får spilleren beskjed MED EN GANG, og igjen når sporet er funnet. Etter et lagg-hull lengre enn kontoen hjelper det
  ikke å gå videre: man må gå TILBAKE til innen én konto fra der hullet begynte (eller ut Lobby-døra og inn igjen). Hver gang SERVEREN
  flytter en løper (`placeInInstance`, `advanceInstance`) må `seedPath` kalles. Gude-runder er utenfor som før.
  Sjekker IKKE: at ruta ble gått av et menneske. Et skript som hopper langs den ekte ruta slipper gjennom og holdes
  bare av tidsgulvet (ca. 0,6 av raskeste ærlige tid, `tests/PathGuard.spec` §4). Alt målt: `EYECANDY.md`, siste seksjon.
- **Økt-lås + eier-token** (`loadPlayer`/`savePlayer`, mønsteret fra fork-tower): lasten og hver lagring er én
  `UpdateAsync`; en annen levende server sin lås gjør økta read-only (og spilleren får beskjed); en utløpt lås tas
  over; å gå slipper låsen; engangs-gaver gis inne i én skriving (`grantOnce`) eller ikke i det hele tatt.
- **`plr.RespawnLocation`** peker på lobby-platen (`pointRespawn`, `robloxemu/SPAWN-ORDER.md` regel 1).
- **Smådyr i hver biome** (`Biomes.Critters`: rotter, sommerfugler, flaggermus, salamandere, biller, edderkopper,
  svaler, stjernemaneter), 2-3 rundt spilleren, i åpne celler, aldri i start-cella, og de deler dekor-taket.
- **Én fallende fare om gangen** (`CellHazards.validate`): to fare-celler står alltid lenger fra hverandre enn to
  ganger tegne-radiusen, så ingen plass i labyrinten har to farer nær seg samtidig.
- **HUD-regel 4b** holdes av `check_labyrintspill_overlap` (med begrunnelsen for hvorfor ikke i selve hudcheck-en);
  den fant og rettet at rekord-panelet la seg over et kjøpt minikart på nettbrett.
- **Klar for butikk og markedsføring:** butikk-teksten i `README.md`, klipp-lista i `MARKETING.md`, Studio-lista og
  thumbnail-lista (1920x1080) i `EYECANDY.md` §8-9, alt holdt av `tests/docs_check.py`.
- **Hele spillerveien gått headless** (`check_labyrintspill_journey`): join, dør, nivå, utgang, tjene, bruke, rejoin.
- Ikke committet, pushet eller publisert. Studio ikke åpnet (natt-skiftet: `EYECANDY.md` §8-9, `MARKETING.md`).

## v2 — resten (ikke bygget ennå)
Bevisst parkert for å få v1 til å funke først. Lagringen er allerede på plass,
så saldoen finnes når butikkene bygges.
1. **Mynt-butikk = perks** (forbedrer spillopplevelsen): lengre fakkel, litt mer
   fart, ekstra liv, tregere monstre, avslør minikart. Disse kobler seg rett på
   CONFIG-verdier (`TorchRange`, WalkSpeed, `MonsterSpeedX`, osv.) — perk = en
   lagret verdi som overstyrer CONFIG pr spiller.
2. **Edelsten-butikk = kosmetikk**: skins/farger på spilleren, spor (trail),
   hatt/effekt. Ren pynt, ingen gameplay-effekt.
3. Butikkene trenger: `ReplicatedStorage`-modul med vare-definisjoner + priser,
   en `RemoteFunction`/`RemoteEvent` for kjøp (server validerer og trekker
   valuta), og en klient-`ScreenGui` (i `src/client`) for UI. Lagre eide perks/
   kosmetikk i samme DataStore-tabellen som valutaene.
4. ~~Global pokal-toppliste (OrderedDataStore) på en `SurfaceGui`-tavle.~~ BYGGET 01.10 (se under: komplett-standarden).

## Arkitektur / hvor ting skal
- `src/server/` → `ServerScriptService` (spill-logikk, autoritativt).
- `src/client/` → `StarterPlayerScripts` (UI, butikk-vinduer — v2).
- `src/shared/` → `ReplicatedStorage` (delte moduler: vare-definisjoner,
  konstantar — v2).
Splitt `MazeGame.server.luau` i moduler når det vokser (MazeGen, Monsters,
Economy, Shop). Foreløpig holdt samlet med vilje for enkel innliming i Studio.

## Kjøre / teste
Roblox har ingen headless-runtime her — testing skjer i Studio.
1. `rojo serve` (se README) og koble til fra Rojo-pluginen i Studio, ELLER
   `rojo build -o Labyrint.rbxlx` og åpne den fila.
2. Trykk **Play**. Se `Output`-vinduet for `[Labyrint] Lastet...`.

Ren logikk testes med luau-CLI (ikke Roblox-avhengige biter):
`luau tests/<Navn>.spec.luau` for hver fil i `tests/` — alle skal si
`N passed, 0 failed`. Dekker nå Progression, Contributors, Hazard og Assist.
MERK: `luau-analyze` melder pre-eksisterende TypeErrors i `MazeGen.luau` og
`Medals.luau` (utypede tabeller) og en ubrukt `LOBBY_FOG` — de er ikke nye.

Headless-sjekkene i `robloxemu/` og alle andre porter: tabellen under.

### Alle porter (01.10, pass 2: komplett-standarden)
Bygg bunten først, hver gang en kilde er endret:
`cd ../robloxemu && py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau`.
Kjør så hver port med `luau <fil> 2>&1`: spec-ene fra spillmappa, sjekkene fra `robloxemu/`. Hver skal ende på
`N passed, 0 failed` eller `PASS`. Tallene står i `EYECANDY.md` §15 (og eldre i §7 og §14).

| port | hvor | hva den holder |
|---|---|---|
| `tests/Assist.spec.luau` | spillmappa | "Hjelp meg"-guiden: pris, gating, beholdt til nivået er klart |
| `tests/Biomes.spec.luau` | spillmappa | biomene, mørke-låsen, pynt, smådyr (`critter`), budsjetter (`validate`) |
| `tests/Board.spec.luau` | spillmappa | topplista: koding, uavgjort til den første, keepHigher, venne-visning, cache, struping |
| `tests/BreakRoom.spec.luau` | spillmappa | hvile: bålet, gratis walk-out-skiltet |
| `tests/CellHazards.spec.luau` | spillmappa | fallende farer: plassering, klokke, sone, knock; én fare om gangen |
| `tests/Contributors.spec.luau` | spillmappa | bidragsyter-lista og engangsbelønningen |
| `tests/EnvBands.spec.luau` | spillmappa | +1 Jump-malen, ordrett |
| `tests/Hazard.spec.luau` | spillmappa | lava-pulsen |
| `tests/Pacing.spec.luau` | spillmappa | minutter til hver biome (brag-vinduet 30-45 min), sjeldenhet, medalje-rettferd |
| `tests/PathGuard.spec.luau` | spillmappa | sti-vakta: vent-og-teleporter nektes, vegg-hopp nektes, en ærlig løper (toppfart, hjørnekutt, hemmelige dører, lagg-hull, etter død) nektes aldri; marginene og det som IKKE er lukket skrives ut |
| `tests/Progression.spec.luau` | spillmappa | `accepted`, rekord-rett, gå-vakta (`minClearSeconds`) |
| `tests/Rest.spec.luau` | spillmappa | +1 Jump-malen, ordrett |
| `tests/lightingpresets.spec.luau`, `tests/mazeref.spec.luau`, `tests/responsive.spec.luau`, `tests/touchtarget.spec.luau` | spillmappa | lys, labyrint-peker, mobil-skalering, 44 px trykkflater |
| `tests/docs_check.py` | spillmappa: `py -3 tests/docs_check.py` (sett `LUAU=<sti til luau.exe>` om luau ikke er på PATH) | butikk-teksten i README (maks 1000 tegn, ingen fargede firkanter, hvert tall mot kilden), klipp-lista i MARKETING, 1920x1080 og Studio-lista i EYECANDY, og at denne tabellen nevner hver port |
| `check_labyrint` | `robloxemu/` | HUD-passform, de 11 opprinnelige klientene |
| `check_labyrint_spawn` | `robloxemu/` | hvor figuren FAKTISK havner; `RespawnLocation` |
| `check_labyrint_pathguard` | `robloxemu/` | sti-vakta gjennom ekte server: vent 120 s + teleporter til utgangen = nektet og ingenting skrevet i `LabyrintRekord_v1`/`LabyrintTopp_v3`; gått ærlig = godkjent; neste nivå, etter død, lagg-hull og gjennom en åpnet hemmelig dør |
| `check_labyrintspill_biomes` | `robloxemu/` | biomene gjennom ekte server og klienter, sømmene, siktlåsen, start-cella |
| `check_labyrintspill_board` | `robloxemu/` | topplista i verden: tavla ved spawn, prompten, Public/Friends, 60 s cache, 200-taket, navn aldri lagret |
| `check_labyrintspill_boarddown` | `robloxemu/` | tavla når lageret er nede: sier det (ikke "Loading..." for alltid), og en tapt skriving prøves igjen |
| `check_labyrintspill_budget` | `robloxemu/` | deler/emittere/lys, målt i hver celle; dekor-taket teller smådyr |
| `check_labyrintspill_cards` | `robloxemu/` | biome-kort, nivå-kort og fare-banner holdes fra hverandre |
| `check_labyrintspill_compile` | `robloxemu/` | hver kilde kompilerer |
| `check_labyrintspill_critters` | `robloxemu/` | smådyrene: riktig art, inerte, i åpne celler, beveger seg, borte i lobbyen |
| `check_labyrintspill_friends` | `robloxemu/` | Friends-døra: verten kommer tilbake til egen kjøring |
| `check_labyrintspill_guide` | `robloxemu/` | den beholdte guiden |
| `check_labyrintspill_hazards` | `robloxemu/` | fallende farer gjennom ekte klient: ring, knock, stagger nær monster |
| `check_labyrintspill_hud` | `robloxemu/` | HUD-passform med alle klientene (regel 4b: se `_overlap`) |
| `check_labyrintspill_journey` | `robloxemu/` | hele spillerveien: join, dør, nivå gått, utgang, tjene, gå-vakta, lobby, bruke, rejoin |
| `check_labyrintspill_layout` | `robloxemu/` | tekst-etiketter på hver viewport |
| `check_labyrintspill_overlap` | `robloxemu/` | HUD-regel 4b (ingen paneler oppå hverandre), med begge gate-artefaktene rettet |
| `check_labyrintspill_popups` | `robloxemu/` | biome-kortet venter på daglig-belønning-popupen |
| `check_labyrintspill_rest` | `robloxemu/` | bålet og walk-out-skiltet |
| `check_labyrintspill_save` | `robloxemu/` | økt-lås, eier-token, lås sluppet/utløpt, engangs-gaver i én skriving, feilet last |
| `check_labyrintspill_shots` | `robloxemu/` | thumbnail-hjelperne i `EYECANDY.md` §9 |
| `check_lighting`, `check_secretdoors`, `check_themes` | `robloxemu/` | mørket, hemmelige dører, tema-butikken |

(`check_labyrintspill_lib.luau` er felles oppstart, ikke en port.)

### Feller å kjenne til (komplett-standarden, 01.10)
- **Frøet har ingen salt, med vilje.** Standarden (§1) vil ha et server-salt på et frø en spiller kan pugge. Her er
  nivåene deterministiske etter eierens design (samme `WorldSeed` + nivå = samme labyrint for alle), fordi
  medaljetidene og rekordene bare betyr noe når alle løper den samme banen. Banen er dessuten synlig geometri: å
  pugge den er å lære en speedrun-rute, ikke å jukse, og topplista rangerer på hvor langt du har klart nivåene i
  rekkefølge, ikke på flaks. Et salt ville brutt rettferdigheten og ikke stoppet noen.
- **Gå-vakta, sti-vakta og filming:** en utgang teller bare når den er nådd tidligst etter tidsgulvet
  (`Progression.minClearSeconds`, `CONFIG.WalkGuard`) OG serveren har sett figuren gå dit (`PathGuard`,
  `CONFIG.PathGuard`). Et klipp eller en sjekk som teleporterer til utgangen får "Too fast..." eller "That exit only
  counts when you walk the maze to it..." og ingen nivå-kort, uansett hvor lenge den venter først. Gå hele veien fra
  starten (`Lib.walk` + `Lib.exitRoute` i `check_labyrintspill_lib`, `check_labyrintspill_journey`, `MARKETING.md`
  "Clip list" for Studio). Et verktøy som flytter figuren på serveren uten `placeInInstance` blir IKKE seedet: flytt
  den tilbake til start-cella og gå derfra.
- **Hemmelige dører i vaktenes rutenett:** knappe-løkka i `buildInstance` tømmer `plannedDoors`; vaktene må lese
  kopien `allPlannedDoors` (før 11.10 sto de ekte dørene som vegger i gå-vaktas rutenett, så gulvet var for høyt
  for en ærlig snarvei). `check_labyrint_pathguard` §5 holder det.
- **Studio uten API-tilgang:** feiler DataStore-kallene, er økta read-only (banneret: "could not be loaded ... will
  not be saved") og tavla sier "Couldn't load the board right now"; kan lageret ikke åpnes i det hele tatt, lagres
  ingenting og tavla sier "No one on the board yet". Begge er riktig oppførsel, ikke en feil (`EYECANDY.md` §8, 20/22).
- **Topplista** er `LabyrintTopp_v3` (nøkkel `u_<userId>`, verdi nivå * 2e9 + (2e9 - nåddUnix)). Den gamle
  `LabyrintTopp_v2` leses bare for å bære over topp 10. Bytt aldri navn på v3 uten en migrering.
- **Emulatoren kjører én harness per prosess:** en sjekk som trenger en annen server-start (f.eks. et lager som er
  nede fra start) må være sin egen fil (`_boarddown`).
- **`MazeGame.server.luau` har CRLF-linjeslutt, bunten har LF:** en mutasjon eller et skript som erstatter tekst
  over flere linjer i serveren må bruke én linje (eller `\r\n`), og kan da ikke bevises i bunten.
- **Film aldri Friends-visningen** med en ekte konto: den viser Roblox-brukernavn.


### ALDRI skriv en CFrame inne i `CharacterAdded`
Målt i Studio 10.09.2026 (`fork-tower/STUDIO.md`, `robloxemu/SPAWN-ORDER.md`):
`Player.CharacterAdded` fyrer mens modellen ennå er **uforelder**, med rot-delen i
verdens origo. **Én frame senere** forelder motoren modellen OG plasserer den på den
aktiverte `SpawnLocation` — og kaster stille alt spillet skrev i mellomtiden. Ingen
feilmelding; tilordningen lyktes og ble forkastet. `char:WaitForChild("HumanoidRootPart")`
redder deg ikke: på serveren finnes barnet allerede, så kallet venter ikke.

Målt i dette spillet med en midlertidig naiv skriving lagt inn i `onCharacterAdded`:
handleren skrev `4321, 654, 4321` mens `char.Parent == nil`, og figuren endte likevel
på `0.00, 3.51, 0.00` — lobby-platen. Motoren vant.

Labyrint gjør det riktige i dag og skal fortsette med det:
- `onCharacterAdded` rører **ikke** posisjon (bare fakkel, perks, HUD, lobby-state).
- Alle spawn skjer på **`Workspace.Lobby.LobbySpawn`**, den ENESTE `SpawnLocation` i
  verden. `buildInstance` merker labyrint-starten med en **vanlig Part** (`MazeSpawn`,
  `CanCollide = false`) nettopp derfor — en ekte `SpawnLocation` til ville gjort at
  Roblox respawner døde spillere tilfeldig inne i en fremmed labyrint 6000 studs unna.
- Flyttinger som ikke er spawn (`placeInInstance`, `returnToLobby`, `endInstance`,
  `advanceInstance`) skjer på prompt/remote lenge etter spawn, og er trygge.
Trenger du noen gang å plassere en figur ved spawn: vent på `char.Parent ~= nil` først
(bundet løkke), eller sett `plr.RespawnLocation` til en ekte `SpawnLocation`.

## Kjente grovheter å polere
- Monster-riggen er én del med Humanoid; kan skli/rykke. Vurder ordentlig
  R15-rigg eller AlignPosition hvis det ser rart ut.
- Pathfinding regnes pr monster i en løkke; mange monstre = mer CPU. Vurder å
  dele én sti-beregning eller sjeldnere oppdatering.
- Alt drepende bruker `Touched`; raske bevegelser kan gå gjennom tynne feller.
