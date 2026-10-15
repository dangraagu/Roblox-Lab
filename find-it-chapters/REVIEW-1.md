# REVIEW-1: Find It! Chapters, adversarial review

Round 1 (2026-10-07, findings A1-A6 and B1-B9) is summarised in `CLAUDE.md`; its fixes are mutation round 3 in
`EYECANDY.md` §7. This file is **round 2**: two more adversarial reviewers on the round-1 fixes (exploits and saves:
findings C1-C4; reachability, HUD and looks: D1-D7), closed 2026-10-07/08.

Method, for every finding: reproduce it first with the reviewer's own probe on a scratch copy of the unchanged
source (`.../scratchpad/fic_r2/`); write a failing test first and watch it fail (RED); fix the GAME; mutation-test
every new assertion (round 4 below). Every number here was measured. All runs used **luaujs** (a Node Luau runtime,
`CLAUDE.md` "The runtime"): the scratchpad luau CLI folder is still empty and no `luau*.exe` exists on C: or D:
(searched 2026-10-08). Nothing was opened in Studio, published or committed; no git command was run.

## The findings

| id | finding (severity) | reproduced (unchanged source) | fix in the game | failing test first | after |
|---|---|---|---|---|---|
| C1 | a clear carried by the leave/shutdown write never reaches the public board (medium) | yes. `rev_boardgap`: Ann clears Chapter 15 at boot+21.0 inside the write gap; 120 s after leave, and after shutdown, the store says 15 (bookSolvedAt set), the board 14 | `onPlayerRemoving` and `BindToClose` write the board after the release write lands (`Main.server`) | `check_finditchapters_release`: 2 FAIL (board 14, want 15) | probe: board 15 after leave and after shutdown; check 19/0 |
| C2 | the A5 day stamp lets a later finisher outrank an earlier one; an unbounded Pause carries a Daily across midnight (medium) | yes. `rev_a5`: B (18 at 22:00 by the Daily) ranks above A (18 at 01:00 by a chapter, same day). `rev_midnight`: Sly opens Case #13 at 23:58, pauses 9 h (clock held at 4.0), solves at 09:00 next day: credited, stamped day N 00:00, rank 1 above Ann (22 at day N 10:00); minutes later Case #14 too | (a) **every rise, chapter or Daily, is stamped with the start of the UTC day it happened on** (`Ledger` `rise`), never the attempt's start day; the Daily CREDIT still goes by the start day (the streak holds across midnight). (b) **a break is capped**: paused time summed over the attempt, at 600 s the room closes (`Attempt.breakLeft`/`closeBreak`, reason `break`, BREAK OVER card, the paused card counts down) | `Ledger.spec`: 6 FAIL; `Attempt.spec`: FAIL + error (no `breakLeft`); `Config.spec`: FAIL; `check_finditchapters_midnight`: 2 FAIL + error | `check_finditchapters_midnight` 35/0, board `1 Sly 23 / 2 Ann 22 / 2 Kim 22 / 4 Lee 22`: Kim (22 at 22:00) ties Ann (22 at 10:00), Sly's Case N solved at 00:00:30 is credited to day N (streak 3 -> 4) but ranks below both, Lee's room closed 600 s into his pause and credited nothing. `rev_midnight` on the fixed source: Sly's 9-hour pause ends in `break`, Ann ranks first |
| C3 | a server hop onto a still-held lock: empty Case Book, a "won't save" toast, a forced Chapter 1, for up to ~20 s (low) | yes. `rev_hop` at autosave phases 0/10/18 s: state `locked`, toast `This session won't save.`, the lectern 0.3 s after the lock was freed puts the player in Chapter 1; ready 17.5 / 7.5 / 19.5 s after the lock was freed | a locked or failed first load retries after 3 s, 4 times (`Save.QuickRetrySeconds`, `QuickRetries`), then the 20 s tick; the lectern's straight-into-Chapter-1 shortcut needs state `ready` or `nostore`; the HUD's Continue row reads `Loading your Case Book...` until the load lands and an open menu is rebuilt when it does; the locked toast and the card note say it is retrying ("won't save" was false: clears made meanwhile are merged, round 1 A3) | `check_finditchapters_hop`: every hopper assertion FAILED (a room opened, no menu, ready 16.5 / 18.0 s after the lock was freed, "won't save"); the HUD sweep's loading-menu mode and `Config.spec` were written with it | ready **1.0 s** after the lock was freed at phases 2.5 / 10.0 / 18.0 s; the prompt opens the menu; one toast, worded as a retry, also when the other server keeps the lock (`Stuck`); a loaded first-timer still goes straight in (control). `check_finditchapters_hop` 38/0 |
| C4 | a write that answers late rolls the session's profile back (low) | yes. `rev_race`, a 9 s late autosave answer: chapter 6 stored at boot+26.1, the session drops to 5 at boot+29, Next says `Clear Chapter 6 first`, chapter 7 opens on the 9th press at boot+41.2 (latency 0: first press) | every profile write takes a number when its transform runs (`nextSeq`); `settle` ignores an answer older than the last one applied (what it carried, the newer write carried too) | `check_finditchapters_race`: 3 FAIL (4 presses) | first press opens chapter 7 (probe: boot+30.8); check 8/0 |
| D1 | after any Resume the only exit (Pause -> Hub) waits ~30 s (medium) | yes. `probe_exit` (800x360 touch): after Pause/Resume the tappable controls are 3 chips and Pause; the hub is reached 31.6 s after first trying | a **Leave** button in the top row of a live room (left of Pause): the first tap arms it and says `Tap Leave again to go to the hub (this room's finds are not kept)`, a second tap within 3 s leaves (server `Hub`: the attempt is abandoned, earns nothing) | `check_finditchapters_exit`: FAIL + error (no Leave button); the HUD sweep's live-room mode | in the hub **1.5 s** after the arming tap; one tap alone never leaves; 48 px, no overlap, in both HUD gates |
| D2 | the Ship's Cabin has no visible weather, 2 of 3 critters invisible, the greenhouse drizzle invisible, while the store text promises a storm (medium) | yes. `probe_book`, chapters 10-12: critters inside parrot (3 parts), outside fish x2; rain 30/s at room-local x 26..32 (beyond the screen and the opaque shell); chapters 7-9 drizzle 8/s at x 24..30 | a porthole is a window box on the room side of the wall (a night-sea **view**, see-through **glass**, a brass **rim**); the fish swim and the rain runs between view and glass; the drizzle runs down the inside of the greenhouse's north glass (y 12-14); **lightning** flashes the four porthole views (Neon, 0.12 s, every 6-11 s) and never touches Lighting; no streak falls below y 10.5, the props' band (`RoomArt.weatherSpots`, `Room.client`) | `Bands.spec`: error (no `weatherSpots`). `check_finditchapters_env`'s first RED run stopped at my too-tight margin on the cottage cat's tail (0.2 studs from the wall), which I loosened to the walls themselves; so the fish and rain REDs are mutants M20-M22 (each reverts one fix: `Bands.spec` and `_env` both fail) | `probe_book`: fish x2 INSIDE, rain 15/s x 2 at x +-23.67 (inside), drizzle inside; `check_finditchapters_env` 361/0: every critter part and weather host inside the room, every streak's lowest point above 10.5 (read off the live emitter), 3-4 flashes in 30 s, the views lit on 10-16 of 900 frames, the Lighting identical on every frame. The store text's "storm" is now built; whether it READS on a phone is `EYECANDY.md` §8 item 26. The Sky's StarCount writes stay (harmless) and are documented as never visible |
| D3 | the BOOK ONE SOLVED dome slit can never be seen (low) | yes. `probe_dome`: slit y 15.70-15.90 inside the opaque disc y 15.30-15.90, radius 16.8: "slit inside the opaque disc = true" | the slit is a shutter hanging UNDER the disc (y 15.0-15.2) over a Neon strip of night sky (y 15.25-15.29) that shows when it fades; the shooting stars start under the disc (they started inside it) | `check_finditchapters_brag`: 4 FAIL (the eye's ray met the disc, 3 stars inside the disc, no sky); `Bands.spec` | `probe_dome`: false. `check_finditchapters_brag` 34/0: a ray from a player's eye to the slit meets the slit first; after the brag, the night sky; no star starts inside an opaque part |
| D4 | the Hub tap after a refused Next is swallowed; Next blocked while saving (low) | yes. `probe_cardlock`: writes at 0.50, 8.67, 20.00, 26.00; Next -> `Saving your case...`; Hub 0.4 s later: room, done, no card, no buttons; the card back at 5.3 s | Hub has its own rate bucket and a refused Hub has words; the HUD keeps the card until the server moves the player; a Next tapped while the clear saves is **remembered** and runs the moment the save lands (dropped if the player went to the hub or retried) | `check_finditchapters_exit` D4a/D4b, written before the fix with D1; its RED run stopped at D1, so D4's failing runs are mutants M17-M19 (each fix reverted: `_exit` fails) | `probe_cardlock`: in the hub 0.3 s after the tap. Exit check: the remembered Next opens chapter 4 **4.9 s** after the tap (the write gap), with no second tap; after a Hub it never pulls the player back. The save wait the pacing model leaves out is at most `MinWriteGap` (6 s) per chapter: at most 1.5 min over Book One, so BOOK ONE SOLVED stays inside [30, 45] even at worst |
| D5 | the hazard rarity claim uses an exposure rule the game does not use (low) | yes. `probe_hzlegal` (400 careers): legal share 0.859; near-miss per 2.71 min counting every second, 3.13 with the game's legal-spot rule; my `Pacing.spec` RED: 3.17 | `FinderModel.legal` (the test model) is the game's `legalSpot`; the GAME's interval moves from 100-140 s to **85-120 s** of exposed time (`Config.Hazards`) | `Pacing.spec`: FAIL (3.17, outside [2, 3]) | `Pacing.spec` 51/0: normal near-miss per **2.70 min** (1000 careers), legal share 0.862; headless 1200 s on a legal spot (`probe_hz`): 10 drops, one per 111 s of exposure, intervals 85.9-115.9 s, standing still hit 5 of 5, a 5-stud step 0 of 5, ring = hit zone 10 of 10 |
| D6 | the long-term goals beyond the brag are invisible: Gold Book, total stars, streak (low) | yes: `Hud.client` had no reference to `totalStars`, `streak` or `bestStreak`; no Gold Book surface existed | the Case Book title shows `THE CASE BOOK * n/45` (`THE GOLD BOOK` at 45); the Daily row shows `streak N (best M)`; the clear that earns the 45th star says `GOLD BOOK! Every chapter at three stars.` (`Ledger.goldBook`, `info.goldBook`, `res.goldBook`, `Profile.goldBook`) | `Ledger.spec`: error (no `goldBook`); `check_finditchapters_hud`: FAIL (title `THE CASE BOOK`); `check_finditchapters_release`: 3 FAIL | both HUD gates PASS with the menu and Gold Book card modes; `check_finditchapters_release`: Gil's perfect Chapter 15 replay earns the 45th star, the card is told, the profile says Gold Book. Gold Book p50 114.3 min (model) |
| D7 | "every gate green" cannot be confirmed under the real Luau CLI (low) | yes: the scratchpad `luau/` folder is empty; no `luau*.exe` on C: or D: | **not fixed**: getting the CLI is a download, which needs the owner's go | n/a | open: re-run all 33 gates under luau.exe when it is back |

Payload keys added and reviewed (`check_finditchapters_secret` allowlists): `State.breakLeft` (seconds of break
left, a function of the pause times only), `State.result.goldBook` and `Profile.goldBook` (stars only). None says
anything about where an item is.

Test-only adaptations, each because a fix changed the scenario, never the requirement:
`check_finditchapters_save` A3 now keeps the store failing while the chapter is cleared (with C3's 3-second retry a
single failed call no longer leaves the load retrying; one assertion added, none removed);
`Ledger.spec` round 1's A5 block is replaced by C2's (its "a solve at 00:00:20 and one at 18:00 tie" is kept);
`check_finditchapters_env`'s "rain wholly beyond the east wall" is replaced by "inside the room, on a wall, above the
props". Decision for the owner: the board's reach time is now the UTC **day** for every rise (same-day ties share a
rank); the standard's encoding takes a unix time and second resolution is one line in `Ledger` (`rise`), at the
price of a race at 00:00 UTC that round 1 (A5) asked to remove.

## Mutation round 4

`.../scratchpad/fic_mutate4.py`, three workers, each mutant on a pristine scratch copy (`fic_mut4_w<k>/`), never on
`D:/Claude/Roblox`; the file's sha256 recorded before and after; the bundle rebuilt from the copy and checked to
carry the mutated line (a removal: checked to no longer carry it); all 33 gates (`fic_gates4.sh`, Pacing only for
M28, 32 otherwise). A gate counts as a kill if it fails or dies before its summary. 32 behavioural mutants, **32
killed**; both controls **survived** every gate.

| # | mutation | result | killed by |
|---|---|---|---|
| M1 | C1: no board write after the release on leave | KILLED | `_release` |
| M2 | C1: no board write after the release in BindToClose | KILLED | `_release` |
| M3 | C2: a Daily stamped with its START day's 00:00 (round 1 A5) | KILLED | `Ledger.spec`, `_midnight` |
| M4 | C2: a chapter clear stamped with its second | KILLED | `Ledger.spec`, `_midnight` |
| M5 | C2: the server never closes a room for a long break | KILLED | `_midnight` |
| M6 | C2: a resumed pause does not count toward the break | KILLED | `Attempt.spec` |
| M7 | C2: the state carries no break left | KILLED | `_midnight` |
| M8 | C2: the HUD has no room-closed card | KILLED | `_hud`, `_hud58` |
| M9 | C3: the lectern throws a loading hopper into Chapter 1 | KILLED | `_hop` |
| M10 | C3: no quick retry of a locked first load | KILLED | `_hop` |
| M11 | C3: the locked toast says the session won't save | KILLED | `_hop` |
| M12 | C3: a loading Case Book offers Continue: Chapter 1 | KILLED | `_hud`, `_hud58` |
| M13 | C3: an open menu is not rebuilt when the profile lands | KILLED | `_hud`, `_hud58` |
| M14 | C4: a late write is applied over a newer one | KILLED | `_race` |
| M15 | D1: a live room has no Leave button | KILLED | `_hud`, `_hud58`, `_exit` |
| M16 | D1: one tap on Leave leaves | KILLED | `_exit` |
| M17 | D4: Hub shares Next's bucket and is dropped silently | KILLED | `_exit` |
| M18 | D4: a Next while saving is forgotten | KILLED | `_exit` |
| M19 | D4: a remembered Next pulls a player out of the hub | KILLED | `_exit` |
| M20 | D2: the fish swim outside the east wall again | KILLED | `Bands.spec`, `_env` |
| M21 | D2: the rain falls beyond the wall again | KILLED | `Bands.spec`, `_env` |
| M22 | D2: the rain falls fast and far again (over the props) | KILLED | `Bands.spec`, `_env` |
| M23 | D2: no lightning in the ship | KILLED | `Bands.spec`, `_env` |
| M24 | D2: a lightning flash brightens the Lighting | KILLED | `_env` |
| M25 | D3: the dome slit back inside the opaque disc | KILLED | `Bands.spec`, `_brag` |
| M26 | D3: no night sky behind the slit | KILLED | `Bands.spec`, `_brag` |
| M27 | D3: the shooting stars start inside the dome disc | KILLED | `_brag` |
| M28 | D5: the hazard interval back to 100-140 s | KILLED | `Config.spec`, `Pacing.spec` |
| M29 | D6: the menu title without the stars | KILLED | `_hud`, `_hud58` |
| M30 | D6: the Daily row without the streak | KILLED | `_hud`, `_hud58` |
| M31 | D6: the Gold Book is never reported | KILLED | `Ledger.spec`, `_release` |
| M32 | D6: the card does not celebrate the Gold Book | KILLED | `_hud`, `_hud58` |
| CONTROL1 | the hub sign reads THE FINDERS AGENCY (no gate reads it) | **SURVIVED** (32 of 32 gates green) | |
| CONTROL2 | the armed Leave button reads `Leave ?` (new code, no gate reads it) | **SURVIVED** (32 of 32 gates green) | |

Sources byte-identical after the sweep: the sha256 list of `src/`, `tests/`, `default.project.json` and every
`robloxemu/check_finditchapters*.luau` (58 files) was taken before the sweep and again after it, and the two lists
are identical (list sha256 `6070bfcd0f29...`). (The sweep script's own summary line mislabelled every mutant "died
before its summary" because it expected 33/34 gates instead of 32/33; the table above is recomputed from each
mutant's recorded gate count and failures, `fic_r2run/mutation4_all.json`.) After the sweep only comments changed
in `src/` and `tests/` (file headers), then every gate was re-run.

## Final gates (luaujs; 2026-10-08)

All 33 gates, twice in a row: **66 of 66 green** (`fic_r2run/final1.txt`, `final2.txt`). The random-dependent ones
(the walk, the main check, env, hazards, secret, cheat, board, remotes, save, brag, release, midnight, hop, race,
exit) three more times in a row: **45 of 45 green**.

| gate | passed / failed | gate | passed / failed |
|---|---|---|---|
| Attempt.spec | 120 / 0 | check_finditchapters | 137 / 0 |
| Bands.spec | 278 / 0 | _hud (36 px) | PASS: 140 measurements, 1860 controls, 0 spills, 30 menus >= 3 rows |
| Board.spec | 78 / 0 | _hud58 (58 px) | PASS: the same |
| Clue.spec | 49 / 0 | _env | 361 / 0 |
| Config.spec | 132 / 0 | _hazards | 51 / 0 |
| Dressing.spec | 262 / 0 | _secret | 143 / 0 |
| EnvBands.spec | 124 / 0 | _cheat | 42 / 0 |
| Hazards.spec | 111 / 0 | _board | 23 / 0 |
| Ledger.spec | 94 / 0 | _compile | 22 sources, 66 / 0 |
| Pacing.spec | 51 / 0 | _remotes | 33 / 0 |
| Pick.spec | 25 / 0 | _save | 49 / 0 |
| Rest.spec | 55 / 0 | _brag | 34 / 0 |
| Rng.spec | 32 / 0 | _release (new) | 19 / 0 |
| responsive.spec | 70 / 0 | _midnight (new) | 35 / 0 |
| project_check.py | 5 / 0 | _hop (new) | 38 / 0 |
| walk.luau | 54-58 / 0 (one assertion per tapped prop) | _race (new) | 8 / 0 |
| | | _exit (new) | 30 / 0 |

Pacing (model, normal profile, 1000 careers): BOOK ONE SOLVED p50 **34.1 min** (p10 31.2, p90 39.5); Gold Book p50
114.3 min; one near-miss per 2.70 min; the sweeper 20.6 min.

## The standard (`docs/complete-game-standard.md`), item by item

| item | status |
|---|---|
| §1 core loop reachable from join | met: the walk; `check_finditchapters`; `_brag`; now also out of a room any time (`_exit`) |
| §1 spawn per SPAWN-ORDER.md | met (unchanged) |
| §1 server-authoritative, nothing secret replicates, no seed | met: `_secret` 143/0 with the three new keys reviewed |
| §1 DataStore discipline | met: plus C1 (board after release), C3 (quick retry), C4 (ordered settles) |
| §1 no silent no-ops | met: a refused Hub now has words (D4) |
| §2 Fx preset + signature particles | met (unchanged) |
| §2 bands, own critters and weather, glided | met headless: every band's critters and weather are now inside the room where they can be seen (D2); the ship's storm (rain, lightning) and the greenhouse drizzle need a real screen (`EYECANDY.md` §8 item 26) |
| §2 hazards: rare, telegraphed, ring = hit zone, one at a time | met: 85-120 s, one near-miss per 2.70 min on the game's own exposure rule (D5) |
| §2 rest / pause never an exploit | met: the break is capped at 10 min (C2); the Leave button gives a way out without a Pause (D1) |
| §2 budgets measured and capped | met: worst room 170 local parts (chapter 11), 204 for the worst of 300 generated chapter-15 rooms (+8 reserve), cap 280; 4 lights, at most 4 emitters |
| §2 brag in 30-45 min + a long-term goal | met (model): 34.1 min; the dome opening is now visible (D3); the Gold Book, the stars and the streak are on show (D6) |
| §2 phone first, overlap = true | met: both HUD gates, 14 modes, the Leave button included |
| §3 public + friends board, un-inflatable metric, first-reach ties | met, with the C2 decision above (ties by UTC day) |
| §3 no Robux, no gambling | met |
| §4 README store text | met: 897 characters, unchanged; its "storm" is now built |
| §4 EYECANDY.md needs-Studio + thumbnail shot list | met: §8 now 30 items, §9 updated (porthole flash, the dome) |
| §4 MARKETING.md clip list | met: 8 clips (new: `ship_storm`) |
| §4 CLAUDE.md gates + traps | met: 33 gates, traps 25-30 added |
| §4 every gate green, TDD, mutation-tested with a control | met under luaujs; open under the real CLI (D7) |
| §5 night shift | not done, by rule |

## Still open

- **D7**: no gate has run under the real luau CLI, and `luau-analyze` / `luau-compile` are missing; a download
  needs the owner's go.
- **Needs Studio** (`EYECANDY.md` §8, 30 items; new or changed this round): 15 the dome slit opening onto the sky,
  seen from the floor; 21 the fish reading as "past a porthole"; 26 the porthole storm (rain and fish behind glass
  at Transparency 0.6, 12 studs up, lightning under bloom) and the greenhouse drizzle; 27 the Leave button on a
  notch phone; 28 how often a hop meets a still-held lock live; 29 the break countdown and the BREAK OVER card;
  30 the stars and streak legible in the menu. Also still: the topbar on a real phone (item 23).
- The board's tie resolution (UTC day vs second) is the owner's call (one line).
- The telescope "swinging up" on BOOK ONE SOLVED (DESIGN.md §10.2) is not built.
- A third adversarial review of these fixes has not been done.
- robloxemu (read-only for this game) still reports a scaled HUD up to `inset * (1 - scale)` px higher than Roblox
  draws it (round 1's note); `tools/film_game.py` still has no scenarios for this game.
