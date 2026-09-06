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
- **Kjent begrensning**: Roblox har klient-styrt bevegelse, så en juksemaker kan
  teleportere til utgangen for falsk tid/rekord. Plattform-begrensning (ingen
  server-side bevegelses-validering her) — greit for et lite venne-spill.

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
4. Global pokal-toppliste (OrderedDataStore) på en `SurfaceGui`-tavle.

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

## Kjente grovheter å polere
- Monster-riggen er én del med Humanoid; kan skli/rykke. Vurder ordentlig
  R15-rigg eller AlignPosition hvis det ser rart ut.
- Pathfinding regnes pr monster i en løkke; mange monstre = mer CPU. Vurder å
  dele én sti-beregning eller sjeldnere oppdatering.
- Alt drepende bruker `Touched`; raske bevegelser kan gå gjennom tynne feller.
