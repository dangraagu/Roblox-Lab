# Labyrint-spill

Et Roblox-labyrintspill. To måter å jobbe med det:

- **Rett i Studio (enklest, for å leke og lære):** følg `GUIDE_NORSK.md`.
  Lim skriptet inn i `ServerScriptService`, trykk Play. Ingen verktøy trengs.
- **Som prosjekt med Claude Code / editor + git (for større arbeid):** bruk
  Rojo til å synke `src/` inn i Studio. Fortsett med `CLAUDE.md` som kontekst.

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
