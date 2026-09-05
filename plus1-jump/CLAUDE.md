# CLAUDE.md — +1 Jump Every Step (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/` (reuses the same
patterns: CONFIG-driven, deterministic WorldSeed gen, DataStore w/ `canSave` sentinel,
pure logic tested with the luau CLI).

## What it is
Incremental escape-obby. **Step on any NEW tile → +1 Jump Power** (server-authoritative).
Jump Power drives `Humanoid.JumpHeight`; bigger jumps clear taller procedural sky-temple
tiers. **REBIRTH** resets jump power but banks a permanent multiplier (2x/5x/10x…).
Single-server, shared tower streamed ahead of the highest player. Codes + gamepasses
(stubbed OFF) + OrderedDataStore top-10. Built from the #1 Game-Radar concept
(`../docs/game-radar/2026-09-04-roblox-game-radar.md`).

## State — v1 built + tested, NOT deployed
- No Roblox experience yet (no place id). Deploy = create experience → git-ignored
  publish script with Open Cloud key (mirror `labyrint-spill/publish_live.bat`).
- Pure logic: **111 luau-CLI tests pass** (Rng 56, Progression 28, TowerGen 15, Codes 12).
- Server/client verified with luau-compile (syntax) + luau-analyze (only Roblox
  type/global noise remains).

## Core model (important — the anti-cheat invariant)
- **Frontier** `(frontierTier, frontierIdx)` gates double-counting: a platform grants
  +1 only if BEYOND the frontier; stepping advances the frontier. So rejoining, falling,
  or re-walking old ground never re-grants. `jumpPower` = climb earnings + code bonuses.
- **Reachability invariant** (Progression.spec, t=1..2000): `stepHeight(t) <=
  Safety * jumpHeight(jumpPowerAtTierStart(t), mult=1)`. i.e. a fresh no-rebirth player
  can always clear every tier. If you retune `Config.Tower`/`Config.Jump`, re-run the
  test — it fails loudly if a tier becomes unjumpable.
- Hazards are currently **decorative (non-lethal)** to avoid frustrating resets; lethal
  hazards are a deliberate v2 toggle.
- Tower is shared and kept (not despawned) so low players keep their footing; memory is
  bounded by the highest tier reached in the session.

## Files
Server `src/server/Main.server.luau`; client `src/client/Hud.client.luau`; shared
`Config/Rng/Progression/TowerGen/Codes.luau`; tests `tests/*.spec.luau`.

## Tests / tooling
luau CLI binaries live in this session's scratch (`.../scratchpad/luau/`). Run pure
specs with `luau tests/X.spec.luau` (require paths are relative to `tests/`). Roblox
runtime tested only in Studio (no headless runtime here).

## Next
1. Create the Roblox experience; run the same content-maturity questionnaire as the maze
   game (answer all 17 = No for this obby — see the maze memory note) so it isn't region-
   blocked; publish.
2. Fill real gamepass IDs into `Config.Passes`, set `Enabled = true`, add ProcessReceipt.
3. Optional: lethal-hazard toggle, per-player trails (Sky Trails pass), SurfaceGui
   leaderboard board.
