# CLAUDE.md — Grow a Crystal (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/` and `plus1-jump/`;
same stack (CONFIG-driven, deterministic Rng, DataStore w/ canSave + soft session-lock,
pure logic tested with the luau CLI). Built from Game-Radar #2 (2026-09-05).

## What it is
Cozy idle-grow sim. Plant seed-crystals in a per-player cavern (grid of socket Parts) →
they grow over REAL time (offline counts) → harvest a mature crystal → a **refraction
roll** may climb its rarity tier (Shard→Quartz→Amethyst→Prism→Legendary→Mythic) → Gem
Dust → buy rarer seeds / chambers / luck+growth boosters → weekly Geode + codes + Gem
Codex. Single shared server, per-player plots.

## State — v1 built + tested + DEPLOYED PUBLIC (2026-09-05); NOT runtime-tested
- **166 luau-CLI tests pass** (Rng 56, Rarity 12, Growth 20, Economy 36, Geode 22,
  Codex 8, Codes 12). Server/client: luau-compile clean, luau-analyze clean (only Roblox
  type/global noise).
- **Live:** universe `10543994765`, place `106123351742435` — https://www.roblox.com/games/106123351742435
  Audience **Public**, genre Simulation, maturity Minimal / None (no region blocks).
  Published via `publish_crystal.bat` (Open Cloud, git-ignored), version 4.
- **Reach tier:** still "limited to 16+ users and trusted friends" — separate gate, needs
  25 engaged players/60d OR 1000 Robux spend. Same as +1 Jump; lifts with real traffic.
- **NOT runtime-tested:** never run in Studio/Player (Studio access denied, Player not
  installed). Unit tests + adversarial review only — first real play could surface
  DataStore / ClickDetector / plot-claim bugs. Marketing gates on a play-through (see
  `MARKETING.md`).

## Core model / important invariants
- **Growth is stateless**: a plant = `{tier, at=os.time()}`; maturity/progress derived on
  demand from `plantedAt` vs now (Growth module). Offline growth is therefore automatic.
- **Server-authoritative**: plant/harvest/buy/geode/redeem all validate + mutate server-side;
  ClickDetector checks the clicker owns the plot; harvest re-checks maturity.
- **Refraction** = the gacha: `Rarity.roll` climbs one tier at a time while a luck-boosted
  roll succeeds. Fresh Rng per harvest. Odds/tiers in `Config.Refraction`.
- **DataStore**: soft session-lock (load real data always; canSave = we hold the lock; short
  TTL renewed by autosave), atomic flush after redeem + geode so a crash can't dupe/lose them.
  **Integer-key trap**: `plants`/`seeds`/`codex` use integer keys; DataStore JSON round-trips
  sparse integer keys to STRINGS — load normalizes them back to numbers (see loadProfile).
- **Leaderboard**: OrderedDataStore by `totalDust` (cumulative earned, monotonic, integer).

## Files
Server `src/server/Main.server.luau`; client `src/client/Hud.client.luau`; shared
`Config/Rng/Rarity/Growth/Economy/Geode/Codex/Codes.luau`; tests `tests/*.spec.luau`.

## Next
1. In-game test in Studio (plant → grow → harvest → refraction; shop; geode; rejoin keeps
   plants/seeds/dust — verify the integer-key normalization holds across save/load).
2. Create the experience, upload, run questionnaire, go Public.
3. Real gamepass IDs (`Config.Passes`): AutoHarvest, DoubleDust, LuckyAura + ProcessReceipt.
4. Optional: trading, more biomes/rarity-tables, SurfaceGui codex board, mobile UI polish.
