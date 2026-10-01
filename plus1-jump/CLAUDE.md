# CLAUDE.md — +1 Jump Every Step (Roblox)

Context so a fresh session can continue. Sibling of `labyrint-spill/` (reuses the same
patterns: CONFIG-driven, deterministic WorldSeed gen, DataStore w/ `canSave` sentinel,
pure logic tested with the luau CLI).

## What it is
Incremental escape-obby. **Step on any NEW tile → +1 Jump Power** (server-authoritative).
Jump Power drives `Humanoid.JumpHeight`; bigger jumps clear taller procedural sky-temple
tiers. **REBIRTH** resets jump power but banks a permanent multiplier (2x/5x/10x…).
Single-server, shared tower streamed ahead of the highest player. Codes + gamepasses
(OFF in v1, cosmetic only: never pay-to-win) + a Top Climbers board by the spawn (Public / Friends, best tier, earliest first on a tie). Built from the #1 Game-Radar concept
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
- Pure logic: **696 luau-CLI assertions pass across 12 specs**, and **645 in 21 headless checks plus the HUD fit**
  (2026-10-01, the re-run of pass 2; per-file counts in EYECANDY.md §17). Pass 2 itself ended at 696 and 639 in 20. After pass 1 it was 607 in 11 specs and 517 in 18. Before the sky it was 111 in 4 specs (Rng 56,
  Progression 28, TowerGen 15, Codes 12).
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
Server `src/server/Main.server.luau`; client `src/client/Hud.client.luau` + `Sky.client.luau` + `Board.client.luau`; shared
`Config/Rng/Progression/TowerGen/Codes/Board.luau`, template modules `EnvBands/Hazards/Rest.luau`, client art
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
The night of 2026-09-27 added `check_plus1jump_sitdrop` (found in Studio: the Rest button rests). Pass 1 of 2026-09-30
(EYECANDY.md §15) added `check_plus1jump_ringtime` (the ring and the MOVE! banner stay up while
`Hazards.threatLive` says the hazard can still hit someone in the ring, not just until its arrival time) and
`check_plus1jump_bestseed` (a space climber who rebirthed in an earlier session is not told "YOU REACHED SPACE!"
again: the first card seeds from the best tier, which the server publishes as the Player attribute `BestTier`).
**OWNER DECISION TAKEN 2026-09-24 (EYECANDY.md §11):** `Config.Rebirth.HighlightFirstRebirths = 1`. The HUD
lights only the first rebirth, then again past tier 240, so a player who presses every lit button reaches space in
about 38 min. The old HUD (every rebirth lit, `math.huge`) would take that player 227 min. Round 1 had switched
first-only on without the owner and round 2 restored every-lit; the owner then chose first-only ("ca 38 min er bra").
`Progression.spec`, `Pacing.spec` and `check_plus1jump_rebirth` pin the default and measure both settings.
**OWNER DECISION 2026-09-30 (EYECANDY.md §11 (b), "take the recommended option for all"):** rebirth stays exactly as
it is (a permanent multiplier on jump HEIGHT; with the 60-stud cap it never makes the climb faster, so it is
prestige, not a shortcut), and no text may promise a faster climb. README fixed; no game code changed for it.

## The board, the climb guard and the saves (pass 2, 2026-09-30) — read EYECANDY.md §16
`docs/complete-game-standard.md` was checked item by item. What was missing is now built, test-first:
- **Top Climbers board** (`src/shared/Board.luau`, `Config.Board`): a physical board on the pad's back edge
  (`workspace.TopClimbersBoard`, front face toward the spawn, never in the climb) with a ProximityPrompt that toggles
  Public / Friends per player. The OrderedDataStore is now `Plus1Jump_LB_v2`, value `Board.encode(bestTier,
  bestTierAt)` = `tier * 2e9 + (2e9 - reachedAtUnix)`, written only when the best tier passes `boardTier` and never
  lowered (`Board.keepHigher`). Public top 10: one GetSortedAsync per 60 s. Friends: fetched when asked, capped at 200,
  cached (list 300 s, scores 120 s), reads limited to 40 at once then 1/s and `BudgetReserve` left in Roblox's budget.
  Names are resolved and kept in server memory only. `Board.client.luau` draws the board on the part (not PlayerGui).
- **Climb guard** (`Config.Guard`, `Progression.allowRise/nearBox`): a platform is credited only when the root is
  within 12 studs of it and the rise since the last credit fits a bucket of 10 jumps refilled at sqrt(g*h/2) studs/s,
  the fastest any chain of jumps can rise. Modelled climbers: 0 refusals (Pacing.spec). A teleport script: space in
  4.5 min at the earliest instead of instantly (a normal player: 34.4).
- **Saves**: a per-session owner token (`old.session`); a save whose record another session has taken is dropped and
  the session goes read-only. A code is granted only if it can be saved, in one write with its reward, and rolled
  back if that write fails. A refused rebirth and an empty code box now say why.
- `MARKETING.md` (10 clips for `tools/film_game.py`), the store description in `README.md` (987 characters).
- **Re-run 2026-10-01 (EYECANDY.md §17):** every item re-checked against the build. Two gaps closed: the stubbed
  `DoubleJump` pass (2x jump power per tile, which `grantStep` paid to any save that claimed it) and `AutoWalk` are
  gone, passes are cosmetic only and off in v1 (`check_plus1jump_paywin`); `MARKETING.md`'s staging table under the
  guard named the wrong platforms and is now measured through the real server.

## Tests / tooling — every gate
The luau CLI lives in the session's scratch (`.../scratchpad/luau/luau.exe`; append `2>&1`).
1. Rebuild the bundle first, every time a source changes (the checks load the bundle, not `src/`):
   `cd robloxemu && py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau`
2. Specs: `luau tests/X.spec.luau` for all 12 in `tests/` (require paths are relative to the spec file).
3. Headless checks: from `robloxemu/`, `luau check_plus1*.luau` for all 22 files (`check_plus1` prints PASS, the
   others `N passed, 0 failed`). Several use the emulator's unseeded `Random`: run a new one 5+ times.
Real rendering, input and replication are Studio only (the night shift, 00:00-06:00; EYECANDY.md §8).

## Traps this game has (each one bit once)
- **Frontier vs best tier.** `leaderstats.Tier` is the FRONTIER, which a rebirth resets to 0. Anything that means
  "have they ever reached X" must read the best tier (Player attribute `BestTier`, the State remote's `bestTier`).
- **The red ring IS the hit zone** (`Hazards.zone`/`inZone`), and it stays drawn while `Hazards.threatLive` holds,
  not until `arriveAt`: `checkHit` runs until `duration`.
- **The first title card waits for the profile to LOAD** (leaderstats), then 1.5 s and the placement; both settle
  clocks start at the load, not the spawn (slow DataStore queues have no upper bound).
- **Spawn order** (`robloxemu/SPAWN-ORDER.md`): `plr.RespawnLocation = spawnPad` is the first line of
  `onPlayerAdded`; the server places a returning climber only after `char.Parent` is set.
- **Rebirth highlight** is the owner's decision (first only); retuning `Config.Tower/Jump` needs `Pacing.spec` to
  still put space at 30-45 min.
- **A seatless sit drops the root for ~0.3 s**: the Rest logic counts the first `SIT_SETTLE_SECONDS` as supported.
- **A check that credits a platform must climb honestly**: put the root on the platform, let a jump's time pass
  (`h:advance(1)`), then fire `Touched`. Firing `Touched` from wherever the character is, or many platforms in one
  instant, is what a script does, and the climb guard refuses it (`check_plus1jump_walk`). Staging that teleports a
  fresh profile high up shows a flat counter for the same reason (`MARKETING.md`); never switch the guard off to film.
- **The guard's baseline is reset by the server's own placements**: at join (the frontier platform) and at rebirth
  (the pad). A new teleport the server does for the player must reset it too, or the player's next credit is refused.
- **Saves carry an owner token.** Anything that writes the profile goes through `saveProfile` (it checks
  `old.session`). A one-time grant must use its return value and roll back when it is false (see Redeem).
- **The board is drawn by the client, per player.** Views go over `Plus1Remotes.Board` with `viewer`; a SurfaceGui
  in PlayerGui would be measured as screen by the HUD fit check. Names are never stored (memory cache only).
- **Passes are cosmetic only, and off in v1** (standard §3: no Robux cost in v1, never pay-to-win). `grantStep` pays
  +1 per new tile to everyone and never reads `p.passes`; `Config.Passes` may list only passes that change how a
  player looks. `check_plus1jump_paywin` fails on a non-cosmetic pass, on `Enabled = true`, or on a save whose
  passes earn more.
- **The guard refuses silently, on purpose.** The standard wants every refused action to say why; a refused credit
  does not, because no honest climb reaches it (0 refusals in `Pacing.spec`; a hazard's knock lifts at most 15 studs/s, `Hazards.MAX_KNOCK_LIFT`, under 0.6 studs) and the
  only players who see it are scripts. If Studio ever shows an honest refusal (EYECANDY.md §8 item 26), retune the
  guard rather than add a message.
- **The board store changed to `Plus1Jump_LB_v2`** (encoded values). v1 held raw tiers, which would sort below every
  encoded value; a returning player's saved best is written to v2 at their first save (stamped with that session).

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
5. Gamepasses: none in v1 (no Robux cost, standard §3). Later, only cosmetic ones (`SkyTrails`): fill the real ID,
   set `Enabled = true`, add the purchase check, and update `check_plus1jump_paywin`, which pins `Enabled = false`
   today. Never a pass that earns more, climbs for you or skips tiers.
6. Optional: lethal-hazard toggle, per-player trails (Sky Trails pass). (The SurfaceGui board was built in
   pass 2 of 2026-09-30, and the server has built a real `TempleSpawn` SpawnLocation since 2026-09-10.)
7. Night shift: EYECANDY.md §8 (needs Studio, now items 1-27), §9 (thumbnails), MARKETING.md (clips; seven new
   `film_game.py` scenarios for the tools owner), then publish, then the store text from README.md.
