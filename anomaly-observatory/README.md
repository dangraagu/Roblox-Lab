# Anomaly: Night Shift at the Observatory 🔭

A spot-the-difference **anomaly horror** game. You're the lone night caretaker of a looping
observatory concourse. Each pass, a procedural roll either leaves the hall **normal** or
injects exactly **one anomaly** (a moved telescope, an extra door, a figure that shouldn't
be there…). At the hall's end you decide:

- **ADVANCE** (key **E**) if it looked normal
- **TURN BACK** (key **Q**) if you spotted something wrong

Correct call → your **Day** counter ticks up and the hall loops. Wrong call → the night
resets to **Day 1**. There is **no chase / pathfinding AI** — the tension is pure observation.
Game-Radar #1 concept (2026-09-06); reuses the procedural-gen + DataStore + single-server
stack from the maze / +1 Jump / Grow a Crystal games.

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — HUD (`Hud.client.luau`)
- `src/shared/` → `ReplicatedStorage` — pure, unit-tested modules:
  - `Config.luau` — every tunable (anomaly catalog, chance curve, codes, save, milestones)
  - `Rng.luau` — deterministic LCG (same in Studio + luau-CLI)
  - `Anomaly.luau` — the clean/anomaly roll (deterministic per pass)
  - `Progression.luau` — Day/streak rules (correct → Day+1, wrong → reset)
  - `Codex.luau` — the "Field Guide" of caught anomalies (string-keyed set)
  - `Codes.luau` — one-time code redemption

## Core loop
Rebuild hall CLEAN → roll (`Anomaly.rollPass`) → if anomalous apply exactly ONE spottable
mutation → player walks to the end → ADVANCE / TURN BACK (in-world ProximityPrompts) →
`Progression.resolve` → correct loops to Day+1, wrong resets to Day 1. A **hint** (key **H**
at the start pad) spends a token to reveal whether the current hall is clean.

## Run in Studio
1. `rojo build -o Anomaly.rbxlx` (or `rojo serve` + Studio plugin).
2. Press **Play**. Output: `[Anomaly] Night Shift at the Observatory loaded.`
3. DataStore needs a published place or Studio → Game Settings → Security → *Enable Studio
   Access to API Services* (without it the game still runs, saves are skipped).
4. You spawn on your private concourse. Walk to the end, read the hall, ADVANCE or TURN BACK.

## Tests (pure logic, no Roblox) — 73 pass
```
luau tests/Rng.spec.luau
luau tests/Anomaly.spec.luau
luau tests/Progression.spec.luau
luau tests/Codex.spec.luau
luau tests/Codes.spec.luau
```

## Codes (edit in `Config.Codes`)
`WELCOME` +3 hints · `OBSERVE` +5 hints · `MIDNIGHT` +10 hints · `ECLIPSE` gold flashlight tint.

## Deploy
No Roblox experience yet. To ship: create an experience → get its place id → add a
git-ignored `publish_*.bat` with an Open Cloud key (mirror `labyrint-spill/publish_live.bat`),
then run the content-maturity Questionnaire before going Public. Milestone Badges are OFF
until real Badge asset ids fill `Config.Milestones` wiring (`awardMilestone`).
