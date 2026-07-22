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
Ingen automatiske Luau-tester ennå. Hvis vi legger til, bruk Lune eller
luau-CLI for ren logikk (maze-gen, kurve), ikke Roblox-avhengige biter.

## Kjente grovheter å polere
- Monster-riggen er én del med Humanoid; kan skli/rykke. Vurder ordentlig
  R15-rigg eller AlignPosition hvis det ser rart ut.
- Pathfinding regnes pr monster i en løkke; mange monstre = mer CPU. Vurder å
  dele én sti-beregning eller sjeldnere oppdatering.
- Alt drepende bruker `Touched`; raske bevegelser kan gå gjennom tynne feller.
