# Grow a Crystal 💎 (Cavern Idle)

A cozy idle-grow sim: **plant seed-crystals in your cavern, watch them grow and refract
into rarer gems — even while you're offline.** Harvest for Gem Dust, buy rarer seeds +
new chambers + luck/growth boosters, crack a weekly Geode, and complete your Gem Codex.
Game-Radar #2 concept (2026-09-05); reuses the procedural-gen + DataStore + single-server
stack from the maze / +1 Jump games.

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — HUD (`Hud.client.luau`)
- `src/shared/` → `ReplicatedStorage` — pure, unit-tested modules:
  - `Config.luau` — every tunable (tiers, refraction odds, growth times, economy, geode, codes)
  - `Rng.luau` — deterministic LCG (same in Studio + luau-CLI)
  - `Rarity.luau` — refraction gacha (climb-a-tier rolls, luck-boosted)
  - `Growth.luau` — offline growth math (stateless timestamp diff)
  - `Economy.luau` — harvest value + shop purchases (mutate-on-success)
  - `Geode.luau` — weekly event (week bucketing + rotation)
  - `Codex.luau` — discovered-rarity tracking
  - `Codes.luau` — one-time code redemption

## Core loop
Plant (consumes a seed) → grows over real time (offline counts) → harvest a mature
crystal → **refraction roll** may upgrade its tier → Gem Dust → buy rarer seeds / chambers
/ boosters → auto-expand the cavern → weekly Geode + codes + Codex chase.

## Run in Studio
1. `rojo serve` + connect from the Studio plugin, or `rojo build -o GrowCrystal.rbxlx`.
2. Press **Play**. Output: `[Crystal] Grow a Crystal lastet.`
3. DataStore needs a published place or Studio → Game Settings → Security → *Enable Studio
   Access to API Services*.
4. You spawn on your private plot. Select a seed (left panel), click an empty socket to
   plant, click a glowing crystal to harvest.

## Tests (pure logic, no Roblox) — 166 pass
```
luau tests/Rng.spec.luau
luau tests/Rarity.spec.luau
luau tests/Growth.spec.luau
luau tests/Economy.spec.luau
luau tests/Geode.spec.luau
luau tests/Codex.spec.luau
luau tests/Codes.spec.luau
```

## Codes (edit in `Config.Codes`)
`WELCOME` +100 dust · `CRYSTAL` +500 dust · `GEODE` free Amethyst seed · `MYTHIC` +5000 dust.

## Deploy
No Roblox experience yet. To ship: create an experience → get its place id → add a
git-ignored `publish_*.bat` with an Open Cloud key (mirror `labyrint-spill/publish_live.bat`),
then run the content-maturity Questionnaire (all 17 = No for this sim) before going Public.
Gamepasses are OFF until real IDs fill `Config.Passes` + `Enabled = true`.
