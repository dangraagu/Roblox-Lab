# Labyrint-spill

Et Roblox-labyrintspill. To måter å jobbe med det:

- **Rett i Studio (enklest, for å leke og lære):** følg `GUIDE_NORSK.md`.
  Lim skriptet inn i `ServerScriptService`, trykk Play. Ingen verktøy trengs.
- **Som prosjekt med Claude Code / editor + git (for større arbeid):** bruk
  Rojo til å synke `src/` inn i Studio. Fortsett med `CLAUDE.md` som kontekst.

## Store description

The text for the experience page (English, as the live page is), written 2026-10-01 against the game:
984 characters (the dashboard allows 1000), plain ASCII, no emoji at all (Roblox rejected coloured-square emoji,
`docs/publishing.md`). Every number in it is held to the source by `tests/docs_check.py` (biome levels, trap and
hazard timings, speeds, prices, the daily reward, the board). "About 41 minutes" is the pacing model's lower bound
for a normal player (`tests/Pacing.spec.luau`: 40.6 min, no deaths), not telemetry. The live text
(`docs/marketing/store-text.json`) predates the biomes and the board; it is replaced with `tools/store_text.py`
after the new version is published, never before.

```
Dark maze, one torch, one way out. Same mazes for all, so medal times are fair.

Lava traps pulse: 3 s off, the last 0.8 flashing yellow, then 2.2 s that kill. Monsters: top speed is 15, you walk 16. Buttons sink the walls of their colour.

8 biomes: Stone Dungeon, Jungle Ruins at level 11, Ice Cellar at 26, Lava Forge at 51 (about 41 minutes in, our estimate), Crystal Caverns at 101, Haunted Crypt at 161, Sky Ruins at 241, Astral Labyrinth at 351. From the Ice Cellar on, rare hazards fall after a 3 s warning and a blue ring; step out to dodge. A hit knocks you down for 0.8 s at most, never kills.

Rest by the campfire in the lobby. Stuck after 3 tries? Buy a glowing path for coins.

Coin perks: torch 300, extra life 600, speed 500, minimap 800. 18 wall themes. Nothing costs Robux. Daily reward pays 150 coins, up to 1050 on day 7.

TOP MAZE RUNNERS at the spawn: top 10 of all servers, or your friends. Ties go to whoever got there first.

Made by an uncle and his nephew.
```

## Fortsette i Claude Code
1. Åpne denne mappa i Claude Code (`claude` i mappa, eller åpne i editoren din).
2. `CLAUDE.md` gir Claude Code full kontekst: hva som er bygget, kurven, og
   v2-planen (de to butikkene).
3. Kildekoden er `src/server/MazeGame.server.luau`.

## Rojo-oppsett (synk til Studio)
Rojo lar deg redigere filene på disk mens de dukker opp live i Studio.

1. Installer et toolchain-verktøy og Rojo. Med [Rokit](https://github.com/rojo-rbx/rokit):
   ```
   rokit add rojo-rbx/rojo
   rokit install
   ```
   (eller last ned Rojo fra https://github.com/rojo-rbx/rojo/releases)
2. Installer **Rojo**-pluginen inne i Roblox Studio.
3. I mappa: `rojo serve`
4. I Studio: åpne Rojo-pluginen → **Connect**. Nå ligger `MazeGame` i
   `ServerScriptService`.
5. Trykk **Play**.

Alternativt, bygg en ferdig place-fil du kan åpne direkte:
```
rojo build -o Labyrint.rbxlx
```
Dobbeltklikk `Labyrint.rbxlx` for å åpne i Studio med skriptet på plass.

## Mappestruktur
```
labyrint-spill/
  default.project.json     Rojo-oppsett (hva som havner hvor i Studio)
  src/
    server/                -> ServerScriptService (spill-logikken)
      MazeGame.server.luau
    client/                -> StarterPlayerScripts (butikk-UI, v2)
    shared/                -> ReplicatedStorage (delte moduler, v2)
  docs/
    maze_preview.png       Forhåndsvisning av et nivå ovenfra
  CLAUDE.md                Kontekst for Claude Code
  GUIDE_NORSK.md           Steg-for-steg + hvordan justere vanskelighet
```

## Status
v1 ferdig (labyrint, utgang, feller, monstre, mynter/edelstener/pokaler,
skjulte knapper, timer, mørke, 500-nivås kurve, lagring).
Nivåene er nå deterministiske (`CONFIG.WorldSeed`): samme level ser likt ut for
alle spillere hver gang. Bytt `WorldSeed` for å trekke om alle banene.
v2 = de to butikkene (perks + kosmetikk). Se `CLAUDE.md`.
Biomer (8 miljøer etter nivå), fallende farer og hvilerom i lobbyen: se `EYECANDY.md`
(bygget og testet headless, adversarial review lukket 24.09, ikke sett i Studio ennå).
Komplett-standarden (`docs/complete-game-standard.md`, 01.10): topplista (offentlig + venner) ved spawn, økt-lås,
gå-vakt, smådyr i hver biome, butikk-tekst (over), klipp-liste (`MARKETING.md`), Studio- og thumbnail-lister
(`EYECANDY.md` §8-9). Alle porter står i `CLAUDE.md`; ikke publisert, ikke sett i Studio.
