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

## Spawn placement — the engine wins, so WAIT for it (2026-09-10)
`Player.CharacterAdded` fires while the character Model is still **unparented** with its root at
the world origin; **one frame later** the engine parents it AND places it on the spawn, discarding
whatever the handler wrote (measured in Studio, `robloxemu/SPAWN-ORDER.md`). `task.defer` does NOT
outlast that — it resumes at the end of the *current* resumption cycle, still before the engine's
step. `onPlayerAdded`'s `place()` used to write the CFrame twice, the second time from a
`task.defer`, and **both writes were thrown away**: the player landed at `0, 3.01, -6` facing
`0, 0, -1`, turned exactly around with all six sockets 11.9 studs behind their back. It now polls
`while char.Parent == nil` (bounded, 300 frames) and writes after. The `SpawnLocation` pad +
`plr.RespawnLocation` stay — they are what keeps an unsteered spawn off the roof (`y = 50.51`
against a roof top of `48.0`) — but they cannot fix *facing*, because the pad is not rotated.
Guarded by `robloxemu/check_crystal_spawn.luau`, which replays the recorded engine order by hand:
`simulateSpawn` alone cannot see this, because the emulator drains `task.defer` **after** its
engine step and Roblox drains it **before**.

## The living cavern (2026-09-23) — read `EYECANDY.md` first
Client-side bands keyed to **chambers owned** (read from the player's own sockets in the world AND the State push),
a geode pulse, harvest bursts + a Legendary/Mythic beam, rare harmless visitors, 🛋 Relax. **No knock-down hazards** (justified in
EYECANDY.md §3). Server change: +9 lines, `lastHarvest = { n, socket, seed, tier }` in the State push, sent after the
roll is paid. Also fixed: the phone code drawer's Redeem button sat under the thumbstick on 640×300.
Built, unit + headless + mutation tested (resumed 2026-09-24: sweep survivor closed with `check_growacrystal_critters`,
shot list rebuilt against the real geometry, EYECANDY.md §7 and §12). **Adversarial review round 1 (2026-09-24): 3
findings, all fixed with a failing test first (EYECANDY.md §13):** (1, high) the HUD could lose the join push to the
cavern script — Roblox flushes a queued RemoteEvent to the FIRST connection only — so State now has ONE client
connection, `src/shared/StateFeed.luau`, that both scripts subscribe to; **never add a second `State.OnClientEvent`
connection** (`check_growacrystal_queue` asserts one); (2) the phone code answer was ~6 px, now it takes the whole row;
(3) Legendary flashes stacked, now at most one per `Config.Env.HarvestFlash.cooldown`. **NOT seen in Studio.** Two
findings for the owner, not changed: (1) at luck 0 every seed returns less than it costs (Shard 78 %) — without codes a player never
buys chamber 2; (2) the refraction seed is `os.time()*1000 + socketId*977 + UserId`, predictable by a client.

## Files
Server `src/server/Main.server.luau`; clients `src/client/Hud.client.luau`, `src/client/Grotto.client.luau` (the
living cavern); shared `Config/Rng/Rarity/Growth/Economy/Geode/Codex/Codes/Cavern/Fx/FxClient/Responsive.luau`, plus
`EnvBands.luau` + `Rest.luau` (templates from plus1-jump, verbatim), `Visitors.luau`, `Grotto.luau` (pure),
`StateFeed.luau` (the one client State connection) and `CavernArt.luau` (client-only art); tests `tests/*.spec.luau` + `tests/IdleModel.luau` (pacing model, not shipped).
Headless (in `robloxemu/`): `check_crystal.luau` (HUD fit), `check_crystal_sockets.luau`
(sockets are in the world and clicking plants), `check_crystal_spawn.luau` (where a spawning
player ends up and which way they face), `check_growacrystal_harvest/env/hud/row/join/race/critters/queue/queue_hudfirst/redeem/flash.luau` (the living cavern).

## Next
1. In-game test in Studio (plant → grow → harvest → refraction; shop; geode; rejoin keeps
   plants/seeds/dust — verify the integer-key normalization holds across save/load).
2. Create the experience, upload, run questionnaire, go Public.
3. Real gamepass IDs (`Config.Passes`): AutoHarvest, DoubleDust, LuckyAura + ProcessReceipt.
4. Optional: trading, more biomes/rarity-tables, SurfaceGui codex board, mobile UI polish.
