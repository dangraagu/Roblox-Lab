# StormGrow: Mutation Farm — REVIEW-1 (2026-10-01)

Two adversarial reviewers (exploit/save, reach/geometry) reported 11 findings on v1. Every one reproduced; none was
rejected. Each got a failing test first, then a fix in the game, then a mutant that the new assertion kills. Five
more defects turned up while measuring and were handled the same way. Nothing was committed, published or opened in
Studio. All numbers below were measured headless (luau CLI + robloxemu) on the final source unless marked "before".

## Findings

| # | finding (reviewer) | reproduced (before) | failing test written first | fix | after |
|---|---|---|---|---|---|
| B1 | critical: 6-stud invisible ClickDetector hitboxes block each other; from in front of a field only the near row answers | the reviewer's ray probe: from the pad at pitch 30, tiles 4-9 answered as 1-3; at pitch 20 all nine hit the Sign. New `check_stormgrow_aim` (taps the SCREEN, grades with its own oracle, models Roblox's ClickDetector delivery): 1,575 aimed taps, 625 answered by the tile under the thumb, 944 by another, 6 by none | `check_stormgrow_aim` part 1; `tests/Pick.spec` | taps are no longer ClickDetectors. `Farm.client` turns a tap/click into a camera ray and picks the first DRAWN thing (crop parts, the soil plate) with `Pick.luau`; sends `Tap(slot, key)`; the server checks owner, distance, rate, ripeness as before. Tile parts are the soil plate's 0.6-stud, unqueryable twin | 1,599 of 1,599 aimed taps on the tile seen, 0 doubled; the walk now clicks on the screen: 7,503 clicks over 60 boot phases, 0 elsewhere; long walks to the brag 33.0-39.3 min (the reviewer measured 57-67 or none with the hitboxes) |
| B2 | medium: idle rest freezes the hazard clock about half of normal play | walk: 44% of frames in rest, 3 hazards in 18 min; long walks at `IdleSeconds` 20: 48-51% in rest, one hazard per 299-338 s | walk: rest share <= 25%, hazards >= 3 | `Config.Rest.IdleSeconds` 90 (measured 20/60/90/120: 48-51 / 23-28 / 5-7 / 0-1% in rest). Rest still freezes only the hazard clock | walk 0-13% in rest at 60 phases; 8 long walks: 10-14 hazards per session, one per 159-213 s (median 173 s) |
| B3 | medium: taps beyond 32 studs do nothing and say nothing | aim part 2, field 2 from the pad (25-46 studs): 1 planted, 6 answered by another tile, 2 silent | `check_stormgrow_aim` part 2 | no client reach cap (the pick goes to 600 studs); the server's 40-stud check answers "Walk closer to tap this crop" | 7 planted, 2 told to walk closer, 0 silent |
| B4 | medium: StreamingEnabled not pinned; Farm.client reads tiles once | `check_stormgrow_stream`: a farm streamed in after the client started drew 0 of 9 crops, its tap reached nothing; `project_check.py` 3/2 | `check_stormgrow_stream`, `tests/project_check.py` | `default.project.json` pins `Workspace.StreamingEnabled = false`; `Farm.client` registers tiles on `DescendantAdded` and drops tiles that stream out (with their crops) | stream 11/0, project 5/0 |
| B5 | low: the porch board is too small to read | board part 6: porch rows 5.6 pt at its 12-stud prompt on a 360-pt phone, market 10.3 pt at 16 studs; porch board 36.0 studs from the pad | `check_stormgrow_board` part 6 | porch board 10 x 6.6 studs at farm-local (15, 4), turned to the spawn camera, top 5 in rows twice as tall; both prompts reach 12 studs | porch 13.0 pt, market 13.7 pt; 15 studs from the pad (farm-local (15, 4) vs (0, 5); the check's limit is 18); hides no field-1 tile at 4 spawn poses; faces the spawn camera |
| A1 | medium: a dead server's lock makes the whole next session read-only, even after it expires | the reviewer's probe: CanSave false at +32 s and at +132 s (lock expired); 20 min later 18,580 coins in memory, 5,000 saved | `check_stormgrow_save` parts 8, 9 | a read-only session polls every 10 s; once the lock has run out with the record untouched (same token, same lockUntil) it takes the lock and saves what it played. A lock that was renewed or released is never taken | probe: CanSave true at +132 s, saved coins 16,340 = in memory; part 9: a renewed lock and a late release are left alone |
| A2 | medium: one transient DataStore error gives a blank read-only farm for the session | probe: 1 call, then Coins 20, CanSave false; 30 min later still false, 0 further calls | `check_stormgrow_save` part 10 (and part 4 now uses an outage) | 3 retries (1, 2, 4 s); then a fresh farm that never saves, and the load retried every 10 s; when it lands the real farm replaces it | a blip: the first farm shown is the real one (250,000 coins), no "couldn't load" toast; an outage: the real farm loads when the store answers, nothing of the fresh farm written |
| A3 | low: a farm is freed only after the leave's writes; a farmless player never gets one | probe: 0.3 s writes, join 0.1 s after a leave: Slot 0 at join and 30 s later; 6 s write, join after 3 s: the same | `check_stormgrow_slots` (new) | the slot is cleared before the leave's writes, and a freed farm is handed to whoever has waited longest (pad, spawn, sign, tiles, moved onto it) | probe: Slot 1 at join in both cases; a 7th player gets the first farm that frees up; slots 12/0 |
| A4 | low: a v1 load rewrites a newer version's record | probe: after one v1 join, v=1, unlocked 8, almanac {corn:1}, tile 1_1 gone, rebirths nil, CanSave true | `Profile.spec`, `check_stormgrow_save` part 11 | `Profile.isNewer`: a record with a higher `v` is shown read-only and never written (load and recovery) | probe: stored v=2, unlocked 9, 3 entries, tiles and rebirths kept, CanSave false; board not written |
| A5 | low: the board runs up to 60 s ahead of the save | probe: entry on the board 0.0 s after the strike, in the profile 40.0 s later | `check_stormgrow_board` parts 3, 8 | the board writes only `savedValue` (what a save landed); a new entry asks for a save within 6 s, retried if it fails | probe gap 0.0 s; with the profile store down the entry never reaches the board, and does once a save lands |
| A6 | low: the board prompt has no rate limit; a failed name is looked up on every fire | 200 fires in 1 s: 200 payloads, 200 toasts, 200 lookups of the failing name | `check_stormgrow_board` part 7 | one switch a second per player (a press inside it says so, once per 2 s); a failed name waits 60 s | 1 payload, 2 toasts, 0 lookups of the failing name (its failure was cached when the board first rendered); five presses at a human pace: 0 further lookups |

**Found during REVIEW-1** (same discipline: failing test first, then fix, then a mutant):

| # | defect | before | test | fix | after |
|---|---|---|---|---|---|
| F1 | every replant left an empty `Crop_<slot>_<key>` folder behind (one per harvest, all session) | 3 folders for one tile after 3 replants | stream part 5 | `CropArt.destroy` destroys the view's folder | 1 |
| F2 | an autosave still queued when the farmer leaves lands after the release: re-locks the record 180 s and writes an older copy | lockUntil re-set, the last tile missing, the next join not saving | save part 12 | a non-release save that runs after the leave began is dropped | lockUntil 0, the tile kept, the next join saves at once |
| F3 | the red hazard ring was drawn 0.05-0.25 studs over the ground, i.e. inside the porch, pads and soil plates: invisible where farmers stand | hazards part G: 0 of 16 points on its face seen on the pad, the porch, a plate | hazards part G, `EnvConfig.spec` | `HazardGlue.surfaceY/ringY`: the ring lies on the highest floor top under it (the floor map checked against the server's parts at 3,577 points) | 16/16 on pad, porch, plate, bed, grass |
| F4 | the owner sign (4.5-7.5 studs up, right behind the pad) hid field 1 from the spawn camera | aim part 4: 175 of 378 field-1 soil points and 41 of 112 pad points hidden at pitches 10-45 | aim part 4 | a 12 x 1.2 name plate on the porch's front edge, no post | 0 and 0 |
| F5 | gate flakes (test-side): the hazards check adopted an in-flight hazard when its `force` hook queued (~2%, also before REVIEW-1: 2 of 96) and could miss a kind (3 of 96 before); the walk's rejoin kept the old client's input handlers; a back-row tile hidden behind tall crops | as stated | the checks themselves | `nextHazard` lets an in-flight hazard land first; extra trials go to a band with a missing kind; the rejoin disconnects UserInputService handlers; the walker steps into the field | hazards 96 of 96 green; walk 60 of 60 |

Rejected: none. One reviewer assumption (Roblox's click ray stops at the first queryable part) no longer matters:
nothing invisible is a click target now.

## Mutation sweep (final run, `py -3 tests/_mutate.py`, 32 gates)

57 mutants: **56 killed, M14 equivalent**; CONTROL (the market square's material) GREEN on 32 of 32 gates, BASELINE
GREEN on 32 of 32. The 62 source, test and check files hashed identical (sha256) before and after the sweep; every
patch was confirmed in its mutant's bundle (`build/stormgrow.luau` of the copy; M34 patches the project file). Each
mutant ran in its own copy; `src/` was never patched.

| id | new rule it removes | killed by |
|---|---|---|
| M26 | the pick ignores drawn crops | `_aim` 21/1 |
| M27 | tile part a 6-stud invisible column again | `_aim` 18/4 |
| M28 | "Walk closer" refusal silent | `_aim` 20/2 |
| M29 | client drops taps beyond 32 studs | `_aim` 18/4 |
| M30 | a HUD-processed tap is a farm tap | `_aim` 20/2 |
| M31 | idle rest after 20 s | walk 25/1 |
| M32 / M33 | late tiles not drawn / streamed-out tiles keep crops | `_stream` 6/5, 8/3 |
| M34 | the place streams | `project_check.py` 4/1 |
| M35 | empty crop folder per replant | `_stream` 7/4 |
| M36 / M37 | dead lock never taken / moved-on lock taken | `_save` 70/5, 70/5 |
| M38 / M39 | no load retries / no outage recovery | `_save` 72/3, 72/3 |
| M40 | newer record rewritten | `Profile.spec` 51/2 |
| M41 / M42 | slot freed after the writes / no handover | `_slots` 11/1, 4/8 |
| M43 / M44 / M45 | board writes live count / no soon-save / failed soon-save not retried | `_board` 46/1, no summary, 45/2 |
| M46 / M47 | no prompt cooldown / failed names not cached | `_board` 44/3, 46/1 |
| M48-M52 | porch board far / prompts 16 studs / ten small rows / in front of field 1 / back to the camera | `_board` 46/1, 45/2, 46/1, 46/1, 46/1 |
| M53 | server acts on another tile than tapped | `check_stormgrow` 151/13 |
| M54 | a save in flight re-locks after the leave | `_save` 72/3 |
| M55 / M56 | ring at ground height / glue forgets pads | `_hazards` 111/3, `EnvConfig.spec` 127/2 |
| M57 | owner sign back up behind the pad | `_aim` 20/2 |
| M1-M25 | the earlier rules | all killed (table in `CLAUDE.md`) |
| M14 | read-only session writes the board | EQUIVALENT: since A5 the board writes only `savedValue`, which a read-only session never raises, so the `canSave` guard it removes is a second lock on the same door |

Two new assertions let a mutant survive in a first sweep and were strengthened, then killed: M38 (the background
recovery could load inside the old 8 s window: the check now asserts the FIRST farm shown is the real one) and M47
(the cooldown alone kept the flood's lookups at one: the check now presses at a human pace). One sweep's CONTROL went
red on the hazards check's kind coverage (F5); the run was voided, the check fixed, the sweep repeated.

## Gates (final source, bundle sha256 58d974f5d02d)

Specs, 17 files, 1,007 passed, 0 failed (Board 53, ClientClock 4, Economy 78, EnvBands 124, EnvConfig 129, Farm 54,
Growth 13, Hazards 111, Hints 14, Mutation 116, Pacing 10, Pick 29, Profile 53, Rest 55, Text 20, Weather 74,
responsive 70). `tests/project_check.py` 5/0. `tests/walk.luau` 26/0. Headless: `check_stormgrow` 164/0, `_compile`
75/0 (25 sources), `_env` 104/0, `_hazards` 114/0, `_rest` 32/0, `_hud` PASS, `_save` 75/0, `_wire` 20/0, `_board`
47/0, `_firstmin` 24/0, `_aim` 22/0, `_slots` 12/0, `_stream` 11/0. The walk at 60 boot phases: 60 green (medians
Carrot 0.8, Corn 4.7, field 2 7.4, Tomato 10.2 min; 60 of 60 crops ripe after 5 min away; 303 dodges, 0 hits).
The hazards check 96 of 96 green after F5.

## The standard (`docs/complete-game-standard.md`)

- **§1 works and honest: MET.** The walk plays join, plant, harvest, unlock, mark, sell, buy, leave, rejoin, a second
  loop, now with every tap a click on the screen. Spawn per SPAWN-ORDER. Server-authoritative: `Tap` carries only a
  tile id and is fully re-checked; 14 kinds of junk change nothing (`_wire`). DataStore: pcall, session token on every
  write, read-only when locked, plus retries, expired-lock takeover, newer-version guard, no late re-lock. No silent
  no-ops: a far tap says "Walk closer", a too-fast prompt says so.
- **§2 looks good: MET.** Seven bands. Hazards rare and telegraphed, the ring now visible where farmers stand and still
  exactly the zone; one per 159-213 s on a normal farmer's path (median 173 s, at the upper edge of "2-3 minutes").
  Rest freezes only the hazard clock. Budgets capped and measured. Brag at 33.0-39.3 min on the real path (model
  36.6). Phone-first HUD (`_hud` PASS); taps land where the thumb is; nothing hides field 1 from the spawn camera.
- **§3 compare: MET.** Public + friends board, upward-only, never ahead of the saved profile, readable on a phone at
  the market and on a porch board 15 studs from the spawn. No Robux, gambling or pay-to-win.
- **§4 ship and market: MET.** Store text unchanged (997 characters, ASCII; no claim it makes changed). EYECANDY.md:
  19 needs-Studio items, 4 thumbnails. MARKETING.md: 7 clips. CLAUDE.md: every gate and 24 traps. Mutation-tested
  with a control.
- **§5 night shift: NOT DONE by design** (Studio, thumbnails, clips, universe, publishing).

## Still open

- Nothing has been rendered, opened in Studio or played by a person (`EYECANDY.md` §8, 19 items). The new ones that
  matter most: item 6, the tap path in a real client (TouchTap and `ScreenPointToRay` in the same GUI-inset space,
  `gameProcessed` for the HUD and the thumbstick, a drag never a tap, the desktop hover); Roblox's real starting
  camera pitch at spawn; item 19, the DataStore paths that need a live service (a crashed server's lock, an outage).
- The pick looks through things that are not tiles (a fence, a board, the name plate): a tap on them lands on the tile
  behind. Deliberate; how it feels is a Studio question.
- Hazards on a normal farmer's path average about 2.9 min, the top of the standard's 2-3 minutes; shortening the
  template's 120-180 s interval was not done.
- A gamepad cannot farm (it could not with the ClickDetectors either). No sound in v1. HUD glyph sizes are checked
  only as box sizes; the boards' row sizes are arithmetic, not rendered.
- `MaxPlayers` = 6 is a publish setting; a 7th player now waits for a farm instead of never getting one.
