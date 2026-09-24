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
  - **Code uploaded 2026-09-05 (versionNumber 2)** via `publish_plus1.bat` (git-ignored,
    mirrors `labyrint-spill/publish_live.bat`; `rojo build -o Plus1.rbxl` + Open Cloud POST).
    Re-publish anytime by double-clicking `publish_plus1.bat` (or PowerShell: `Set-Location
    <this dir>; & '.\publish_plus1.bat'`). It has a couple of harmless "'M' is not recognized"
    stray lines from the copied validation block — build+publish still succeed.
  - Open Cloud key: the existing "labmario" key's scope was extended to cover BOTH universes
    (maze + this one) with `universe-places:write`, restricted to those two experiences.
- **Still PRIVATE** — set Audience = Public only after: (1) in-game test that it plays, and
  (2) the content-maturity Questionnaire (all 17 = No for this obby — see maze memory note),
  so it isn't region-blocked.
- Pure logic: **594 luau-CLI assertions pass across 11 specs** (2026-09-17, after review round 2; per-spec counts
  in EYECANDY.md §7). Before the sky it was 111 in 4 specs (Rng 56, Progression 28, TowerGen 15, Codes 12).
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
Server `src/server/Main.server.luau`; client `src/client/Hud.client.luau` + `Sky.client.luau`; shared
`Config/Rng/Progression/TowerGen/Codes.luau`, template modules `EnvBands/Hazards/Rest.luau`, client art
`SkyArt.luau`, kit `Fx/FxClient/Responsive.luau`; tests `tests/*.spec.luau` + `tests/ClimbModel.luau`.

## The sky (added 2026-09-17) — read EYECANDY.md first
Altitude-driven environment bands (temple -> treetops -> cloud sea -> storm -> edge of space ->
SPACE at tier 85 -> deep space -> beyond the galaxy at tier 240), rare telegraphed hazards, and a
rest state. All CLIENT-side (`src/client/Sky.client.luau` + `src/shared/SkyArt.luau`); the server
knows nothing about it and nothing about it touches progress. Game-agnostic template modules:
`src/shared/EnvBands.luau`, `Hazards.luau`, `Rest.luau` (specs in `tests/`). +1 Jump's numbers live
in `Config.Env / Config.Hazards / Config.Rest / Config.Pacing / Config.Budget`. Pacing is measured
by `tests/Pacing.spec.luau` + `tests/ClimbModel.luau`; if you retune `Config.Tower`/`Config.Jump`,
that spec tells you whether space still lands at 30-45 min. Headless glue checks:
`robloxemu/check_plus1_sky.luau` and `check_plus1_sky_rejoin.luau`, `check_plus1jump_life.luau` (resume
session, EYECANDY.md §13: critters keep recycling, scenery cross-fades on a teleport, suit light in space),
plus the seven `robloxemu/check_plus1jump_*.luau` files from adversarial review round 1 (EYECANDY.md §12): hazards start
on screen at any camera pitch, a queued rest survives a walked dodge, a slow profile load never shows a
TEMPLE card or a repeat space fanfare, the sky names bands by the HUD's tier number, cloud decks keep 40
studs off the climb and the temple island sits below any rescue, and when the HUD lights REBIRTH.
Review round 2 (EYECANDY.md §14) added `check_plus1jump_dodge` (the red ring IS the hit zone: leaving it in any
direction dodges; `Hazards.zone`), `check_plus1jump_slowload` (16-40 s profile loads, a placement 20 s late) and
`check_plus1jump_budget` (weather emitters capped at 2 by `EnvBands.capRates` under fast teleports).
**OWNER DECISION TAKEN 2026-09-24 (EYECANDY.md §11):** `Config.Rebirth.HighlightFirstRebirths = 1`. The HUD
lights only the first rebirth, then again past tier 240, so a player who presses every lit button reaches space in
about 38 min. The old HUD (every rebirth lit, `math.huge`) would take that player 227 min. Round 1 had switched
first-only on without the owner and round 2 restored every-lit; the owner then chose first-only ("ca 38 min er bra").
`Progression.spec`, `Pacing.spec` and `check_plus1jump_rebirth` pin the default and measure both settings.

## Tests / tooling
luau CLI binaries live in this session's scratch (`.../scratchpad/luau/`). Run pure
specs with `luau tests/X.spec.luau` (require paths are relative to `tests/`). Roblox
runtime tested only in Studio (no headless runtime here).

## Next
1. ~~Create the Roblox experience~~ DONE (universe 10543598100 / place 120040655253410).
2. ~~Upload the code~~ DONE (versionNumber 2, via `publish_plus1.bat`).
3. **In-game test** (Private): join/Edit-in-Studio and confirm it plays — stepping tiles
   grants +1 jump, tower streams, rebirth/codes/leaderboard work. Never runtime-tested yet.
4. ~~Content-maturity Questionnaire~~ DONE 2026-09-05 (all 17 = No → Label **Minimal**,
   Descriptors None, Non-Compliant Regions None). NOTE gotcha: a green check = "answered",
   not "No" — the Preview page is the source of truth; an accidental Yes on Alcohol/
   Paid-Random surfaced there and was corrected before Submit.
5. ~~Set Audience = Public~~ DONE 2026-09-05 — experience is now **PUBLIC**.
   URL: https://www.roblox.com/games/120040655253410/ (reach still gated: "limited to 16+
   users and trusted friends" until 25 engaged players/60d OR 1,000 Robux — same reach-tier
   as the maze; unrelated to the now-clean maturity/region status).
   STILL PENDING: an actual in-game runtime test (built + unit-tested only).
5. Fill real gamepass IDs into `Config.Passes`, set `Enabled = true`, add ProcessReceipt.
6. Optional: lethal-hazard toggle, per-player trails (Sky Trails pass), SurfaceGui
   leaderboard board, a SpawnLocation in default.project.json (currently spawns are placed
   by the server on CharacterAdded).
