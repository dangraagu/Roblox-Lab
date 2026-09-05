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

## State — v1 built + tested, experience created, CODE NOT YET UPLOADED
- **Roblox experience created 2026-09-05** (repurposed the default empty place):
  - **Universe id: `10543598100`** · **Start place id: `120040655253410`**
  - Name "+1 Jump Every Step 🔼 Sky Temple Obby"; Genre Obby & Platformer / Tower Obby
    (genre locked until 2026-10-04); Audience = **Private** (make Public after code upload).
  - Future URL: https://www.roblox.com/games/120040655253410/...
  - The place still holds the default baseplate — the +1 Jump code is NOT uploaded yet.
- **To upload the code:** build with rojo (`rojo build -o Plus1.rbxlx` from this dir) then
  publish that place file to place id 120040655253410 — either via Studio (open the rbxlx →
  Publish to Roblox → this place) OR an Open Cloud publish script (git-ignored, mirror
  `labyrint-spill/publish_live.bat`; needs an API key scoped to universe 10543598100 with
  place-publish permission). After upload, run the content-maturity Questionnaire (all 17 =
  No) BEFORE going Public so it isn't region-blocked (see maze memory note).
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
1. ~~Create the Roblox experience~~ DONE (universe 10543598100 / place 120040655253410).
2. **Upload the code** to place 120040655253410 (rojo build → Studio publish or Open Cloud;
   see State section), then run the content-maturity Questionnaire (all 17 = No for this
   obby — see the maze memory note) BEFORE setting Audience = Public, so it isn't region-
   blocked.
3. Fill real gamepass IDs into `Config.Passes`, set `Enabled = true`, add ProcessReceipt.
4. Optional: lethal-hazard toggle, per-player trails (Sky Trails pass), SurfaceGui
   leaderboard board.
