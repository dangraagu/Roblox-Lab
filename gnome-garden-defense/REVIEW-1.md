# REVIEW-1: Gnome Garden Defense, adversarial reviews closed

Two rounds. **Round 2** (2026-10-08, this section) closed two more adversarial reviews of the build as round 1
left it. **Round 1** (2026-10-07, further down, kept as it was) closed the first two reviews and the build's own
pass past the brag. The gate counts, the standard and "still open" in round 2 are the current ones.

**Every number was measured on the LuaJIT shim** (`scratchpad/ggd/luaushim`, CLAUDE.md "State"), not real Luau.
Nothing was opened in Studio, published or committed; no git command was run.

## Round 2 (2026-10-08): 11 findings, 10 closed in code, 1 closed by a publish setting, none rejected

Code comments and CLAUDE.md call this round REVIEW-2. Reviewer E (exploit, 3 findings) and reviewer P (reach, 8
findings). Every finding was **reproduced first**: the
reviewers' own probes (`check_x_shove`, `check_x_fish`, `check_x_prompt`, `probe_pick`, `probe_band`,
`probe_restore`, `probe_board`, `probe_pausewalk`; P3 from the reviewer's own pacing numbers) were re-run against a
snapshot of the tree as it was (`scratchpad/ggd3/orig`). Then a failing test, then the fix in the game. "Red on the
original" is the new test run against that snapshot (`scratchpad/ggd3/red`, 12 of 27 gates red).

| # | finding | reproduced (before) | fix | test (red on the original) | after |
|---|---|---|---|---|---|
| E1 | Another player undoes your PAUSE and your AFK hold by pushing your character 4 studs | check_x_shove: paused at 1.0-3.9 studs, resumed at 4.0 within 1.2 s and 50 GardenTicks in the next 5 s; an absent gardener held at 238 s went back to `build` after one 4.2-stud shove and its wave started 25 s later | The server no longer polls the character. A pause ends only by the gardener's own input: their client's wake (Rest, their own thumbstick), the button, or a garden action. The AFK hold's "here" is a garden action, PAUSE, or the client's new `Here` remote, sent at most every 5 s while the gardener's own MoveDirection, a key, a tap or a click is seen (a shove or a hazard's knock moves the character but is no input). `Here` resumes nothing, is never answered and costs no token. Gardeners do not collide (collision group `GardenPlayers`, pcall'd: robloxemu has no PhysicsService) | new `check_gnomegardendefense_grief` (on the original: 12 failed, incl. "ten shoves... never resume" and "five shoves... never end the AFK hold"); the main check's "a 5-stud step resumes it" is now "a 5-stud move alone does not resume it" (red on the original) | ten shoves of 1-12 studs: paused throughout, 0 GardenTicks; five shoves of 4.2-10 studs over a minute: still held, wave unchanged; the victim's client sent 0 `Here` during the shoves and 1+ for its own step; every character part in the group, a part added later too |
| E2 | During a daily-store outage every TRY AGAIN a minute apart drew a new endless bed (bed fishing onto the shared board) | check_x_fish: 7 distinct beds in 7 restarts, the shared bed never played (on my run the 7th bed's wave 41 was lost; the reviewer's survived and wrote board value 82208592450) | `dailySeed`: ONE bed of this server's own per UTC day, drawn once; it is also what this server writes if it is the day's first writer. The store is still asked again every 60 s (REVIEW-1's D4 stays) | `check_gnomegardendefense_daily`, new section (on the original: 4 different beds in 3 restarts) | 3 TRY AGAINs a minute apart during the outage: 1 bed; the store was asked again meanwhile; when it answers, the shared bed as before |
| E3 | The board's ProximityPrompt answered every trigger with a payload | check_x_prompt: 2000 triggers in an instant gave 2001 payloads; 500/s for 60 s gave 30061 | one toggle per `Config.Board.ToggleSeconds` (0.5 s) per player; more is refused with "Slow down a little" at most once a second (`sayOnce`); a stranger's triggers on your board likewise | grief, prompt section (on the original: 2001 payloads, 30000 answered toggles) | 2000 triggers: 2 payloads; 60 s of 500/s: 120 answered toggles, 180 payloads, 61 toasts; two taps a second apart both answered (8 of 8 runs) |
| P1 (high) | A phone tap on a 12-17 px pad opened the sheet for a neighbour, and nothing showed which pad was selected | probe_pick: 9 px off centre picked another pad 11/184 (6%), 12 px off 78/184 (42%); the world unchanged (208 instances, rim 0.55) | On a touch screen, in the whole-garden view, a tap on a cell under 44 px PICKS NOTHING: the view zooms on it (6 s, then back) and the HUD says "Tap the pad you want"; the pick is the next tap, in the zoom. The zoom is 52 px (was 48), so its neighbours are 45.4 px or more. The picked pad is drawn neon GOLD while its sheet is open. The walk and the reach check now decide to tap again by the gold pad, not the hidden SelectedPad attribute | reach section 10 (on the original: 180 first taps of 180 opened a sheet; the pick never gold), GardenCam.spec "its eight neighbours are 44 px or more" (48 px gave 42.4), walk "that pad is drawn gold" | 8 runs, 1440 tries (12 px off centre, 4 directions, every pad not right behind a gnome): 0 sheets from the first tap, 0 wrong pads and 0 misses from the second; the gold on the picked pad only; reach section 2: every pad in 2 taps, the deciding cell 50.9 px or more; the walk's gnomes all confirmed on 50.2 px or more |
| P2 | The whole-garden view drew tappable pads under Roblox's thumbstick | probe_band: 8 of 356 pads (8 beds) in the HUD's thumbstick corner, 72 in the DynamicThumbstick frame as the reviewer recalled it (left 40%, lower 2/3); reach on the original: 10 over four phones | `GardenCam.fitClear`: the same framing moved sideways (shrunk only when that is not enough) until no pad's cell (4 px margin) overlaps the thumbstick's frame or the jump button's corner. The thumbstick's frame is the reviewer's wider 40% x lower 2/3 (`Config.Hud.StickW/StickH`), which holds the HUD's 35% band corner on every phone; Studio must confirm it (EYECANDY.md §7, 20) | GardenCam.spec fitClear (40 beds x 5 phones: 2644 cell overlaps with the plain fit), reach section 11 (spelled-out zones; on the original: 10 pads) | 0 pads under either on 844x390, 568x320, 640x300, 926x428 (8 of 8 runs); 0 of 2644 in the spec with 93-100% of the cell size kept; the overview's smallest cell 15.3-16.1 px on 844x390 (was 16.1). The garden now sits right of centre on a phone |
| P3 | The 30-45 min brag assumed a player who always plants on one of the 3 best pads for each gnome, which the game never showed | the reviewer's runs: padTop 3 -> median 33.6, 6 -> 45.5, 10 -> 60.8, random -> no wave 30; the glow stopped at the first gnome, and as a rim mostly hidden under the pad. A first fix that lit the 3 best pads for a Pebble only was measured too weak: median 35.4, worst 80.1, autumn first try 57% (the old profile's 8 of 486 plants went elsewhere) | The game now shows what the model's normal player knows: the gnome sheet STARS a gnome (`Garden.suggestKind`: the unlocked kind furthest below its share of `Config.Suggest` = the normal mix 4 : 1.5 : 2 : 1.5), and the 3 best FREE pads for that gnome GLOW neon green all game while there is room (`PathGen.bestPads`, both behind one rule, `PathGen.glow`, used by Garden.client, Hud.client and the model). The normal profile plants exactly the starred gnome on a glowing pad | Pacing.spec "the normal player plants only on pads the game shows glowing, and only the gnome the sheet stars" (on the code before the profile change: 8 of 486 plants elsewhere), PathGen.spec glow + bestPads, Garden.spec suggestKind, reach section 14, check_brag section 0 (a Lantern starred on a bed where its best pads are not a Pebble's), check_env (a steady glow after the first gnome) | normal profile: 486 plants, 0 off the glow, 0 off the star; every Pacing number unchanged (brag median 33.6 min, p10 30.3, p90 53.3, worst 61.8; first try 98/95/78/57%; hazard every 2.58 min). A player who ignores the glow is slower, as the reviewer measured |
| P4 | B1 was still reachable: a Frost gardener whose first profile read fails got the HARVEST MOON brag replayed | probe_restore: start on Spring (Progress 0), restored to chapter 4 two seconds later (Progress 30): 1 golden flash, 46 sky frames (4.6 s), the card 53 frames (5.3 s) | the first progress of EVERY attempt (every new bed) is named quietly, not only the session's first: a new bed is never a reach. The server publishes `Attempt` before `Progress` | new `check_gnomegardendefense_restore` (on the original: 1 flash, 46 sky frames, 5.3 s) | 0 flashes, 0 sky frames, a quiet card; "Your saved garden is back: Frost." said (8 of 8 runs) |
| P5 | A tap on the board in the board view opened the gnome sheet for a pad hidden behind it | probe_board: 5 of 35 taps on the board's face (6 of 35 in reach on the original) | in the board view (as in the sky, free and external views) a tap picks nothing; the board's own prompt is the action there | reach section 12 | 0 of 35 taps open a sheet; PickSeq unchanged |
| P6 | The brag's line was overwritten after one frame, and the brag flashed twice | check_brag on the original: 2 golden flashes; "The Slug Queen falls!" on screen 0.1 s. The same overwrite hid every season card (SPRING WON under HIGH SUMMER) | the season's card and the band it reaches share ONE card and ONE flash: within 2 s the second joins the first (the band added to the season's line when it is another name: "FROST WON / Moonlit Snow") | check_brag (2 flashes, 0.1 s on the original), walk "the season's own card stays readable 3 s" | 1 flash, the line readable 5.4 s (8 of 8); SPRING WON readable 5.3 s; check_frost now records a changed line under the same title |
| P7 | PAUSE pressed while walking answered "Slow down a little" and let go within a second | probe_pausewalk: 5 of 5 tries toasted "Slow down a little", paused 0.4-1.0 s | while the gardener walks, PAUSE says "Stand still, then press PAUSE" (in the PAUSED overlay's place, 2 s) and does not pause (with a hazard inbound it still queues, as before). The server's 0.5 s cooldown holds back pausing only: a resume always lands (needed now that the server no longer polls) | reach section 13 (on the original: 5 flickers, 0 told, and a pause followed by a step was resumed 0 of 5 times with 3 "Slow down") | 0 flickers, "stand still" 5 of 5, no "Slow down"; a pause then a step 0.1 s later resumes 5 of 5 |
| P8 | No gamepad path to pick a pad | code read: View.client picks only TouchTap and MouseButton1; pads have no ClickDetector | **publish setting, not code:** Playable Devices = Computer, Phone, Tablet, **Console OFF** (EYECANDY.md §7 item 16, README). A gamepad cursor stays a later pass | none possible headless (a publish setting) | open as a v1 limit: a console player cannot plant, so Console must not be offered |

### Tests changed on purpose (each because the rule changed, said here)
- `check_gnomegardendefense.luau`: "a 5-stud step on the deck resumes it" became "a 5-stud move alone does not
  resume it", "nor does Here", "the gardener's own wake resumes it" (E1); `Here` is in its list of remotes.
- `check_gnomegardendefense_env.luau`: the rims "settle once the first gnome is planted" became "stop pulsing, and
  three keep a steady glow" (P3: the glow is now all game).
- `check_gnomegardendefense_frost.luau`: its card recorder also logs a changed line under the same title, and a band
  counts once per card that newly names it (P6: Moonlit Snow is named in FROST WON's line).
- `check_gnomegardendefense_reach.luau`: on a phone it taps twice (the first only zooms), decides by the gold pad;
  section 1 reads the HUD's row bottom off the GUI itself (the sweep's M35, WorldTop = 0, survived a check that took
  the HUD's published WorldTop for it); section 10 PAUSES the garden first (ten minutes of taps lost the wave
  section 4 started, and a lost garden picks nothing) and leaves out the pads right behind a gnome (a finger below
  such a pad's centre is on the gnome, and a tap on a gnome picks the gnome: before, 1 tap in 152-200 picked it, in 2 of 3 runs).
- `tests/walk.luau`: plants the starred gnome on a glowing pad (the lowest-numbered: a visible choice), decides to
  tap again by the gold pad; it no longer uses the profile's mix (now `Config.Suggest`).

### Order of work, honestly
- Test first and watched red on the tree as it was: grief (E1, E3), daily (E2), restore (P4), check_brag's flash and
  line (P6), GardenCam.spec fitClear (P2), PathGen.spec bestPads and glow, Garden.spec suggestKind, Pacing.spec's
  glow-plant check (P3), reach sections 10-12 and 14 (P1, P2, P5, P3). The wider thumbstick frame (40% x lower 2/3)
  came after the first sweep: its assertions were written first (GardenCam.spec red: no StickW yet; a probe on the
  tree as it then was put 2-6 pads of each bed in that frame).
- Written after their fix, then proven red on the original snapshot: reach section 13 (P7; the client and server
  fix came first).
- Written after their fix and proven only by a mutant: GardenCam.spec's zoom-neighbour check (MinTapPx 52; M54) and
  check_brag section 0 (the Lantern star; M59c). Section 0 exists because the first sweep's M59c (the client lighting
  a Pebble's pads whatever the star) survived the spring-only reach check: only 38 of 200 generated beds have a state
  with one Pebble standing where a Sprinkler's best pads differ from a Pebble's, so spring cannot tell them apart;
  with a Lantern starred, all 200 can. Likewise reach section 1 now reads the HUD's rows off the GUI because M35
  survived the first sweep.

### Mutation sweep (round 2)
`scratchpad/ggd3/mutate3.py`: three isolated copies of the final tree (`ggd3/m5_0..2`, each checked byte-identical to
the live tree before the sweep). For each mutant: the source's sha256 must be the pristine one; exactly one
replacement (the file's own line ending); the bundle rebuilt and the mutated text found in
`build/gnome-garden-defense.luau` ("reached"; the project file and the test model are not in the bundle); the gates
named for it run first ("first"), and if none fails, ALL 27 ("all"); then the file restored and its sha256 checked.
The CONTROL always runs all 27. M1-M41 are round 1's still on the current code (M10, M14, M20, M29, M38 changed
targets: M10b, M20b, M29b, M38b re-express them; M14's code, the PAUSE re-base, no longer exists because E1 removed
the poll it guarded, and M42 puts the poll back). M42-M67 are round 2's.

| # | mutant | reached the bundle | gates run | killed by (first failing line) | restored |
|---|---|---|---|---|---|
| M1 | B progress: a leaked bug counts as gone (the false brag) | yes | first | Garden: 132 passed, 2 failed FAIL: it is the bugs actually stopped that count -> got 29.999, want 29.916666666666668 | yes (sha256) |
| M2 | C reveal refund back to 70% in the sim | yes | first | Garden: crashed: runtime.lua:597: in function <runtime.lua:588> | yes (sha256) |
| M3 | C the HUD's SELL label ignores the reveal refund | yes | first | check_reach: 70 passed, 1 failed FAIL: on the reveal the SELL button offers everything back (+50) -> got SELL | yes (sha256) |
| M4 | A1 a read-only/failed session never retries | yes | first | check_store: 32 passed, 10 failed FAIL: once the lock is gone the session takes the record and starts saving -> got false, want true | yes (sha256) |
| M5 | A1 a late lock takes the stored best, dropping what was played | yes | first | check_store: 40 passed, 2 failed FAIL: and what was played while read-only is saved (best wave 1) -> got 0, want 1 | yes (sha256) |
| M6 | A2 a lock taken by a player who left during the load is kept | yes | first | check_store: 41 passed, 1 failed FAIL: a player who left during the load leaves no lock (lockUntil-now = 45) | yes (sha256) |
| M7 | A4 a bed drawn for a player who left is still built | yes | first | check_store: 38 passed, 4 failed FAIL: a gardener who left while the bed was drawn leaves no board behind -> got 1, want 0 | yes (sha256) |
| M8 | A5 the season win is saved on the simulation thread | yes | first | check_store: 41 passed, 1 failed FAIL: at least one other garden was mid-wave through the win's save (precondition) | yes (sha256) |
| M9 | A5 saves are not serialised (a late win save re-locks) | yes | first | check_store: 41 passed, 1 failed FAIL: and the lock is released: the slow win save did not re-lock it after the leave -> got 1791411939, want 0 | yes (sha256) |
| M11 | A3 the day's bed is asked once | yes | first | check_daily: 6 passed, 7 failed FAIL: after asking the store 3 times -> got 1, want 3 | yes (sha256) |
| M12 | A6 every refused call is echoed | yes | first | check_save, check_store: 37 passed, 1 failed FAIL: and the rest are refused out loud: told once to slow down, not 40 times -> got 40, want 1 | yes (sha256) |
| M13 | A6 a tap in the load window is dropped silently | yes | first | check_store: 41 passed, 1 failed FAIL: a tap in the load window is answered (nil) | yes (sha256) |
| M15 | G no meadow under the hedge gap | yes | first | check_reach: 70 passed, 1 failed FAIL: there is ground through the hedge gap and outside every hedge (gap x-16.5 gap x-18 gap x-20 gap x-30 gap x-60 -25,-25 136,-25 -2... | yes (sha256) |
| M16 | H the board back at the lawn west of the deck (53 studs) | yes | first | check_reach: 70 passed, 1 failed FAIL: and near the spawn (53.2 studs, at most 45) | yes (sha256) |
| M17 | I the dawn band without weather | yes | first | EnvConfig, check_env: 55 passed, 1 failed FAIL: every band has its weather, the dawn too (sprouts) -> got 1, want 0 | yes (sha256) |
| M18 | D StreamingEnabled not pinned off | n/a (project file) | first | project: 5 passed, 1 failed FAIL: Workspace.StreamingEnabled is pinned to false | yes (sha256) |
| M19 | D the glowing pads are looked up once per attempt | yes | first | check_env, check_reach: 112 passed, 3 failed FAIL: on a new bed exactly three pads pulse () -> got 0, want 3 | yes (sha256) |
| M21 | E a tap beside a pad does not snap to it | yes | first | GardenCam, check_reach: 33 passed, 2 failed FAIL: a tap on the path just below a pad snaps to it -> got nil, want 6 | yes (sha256) |
| M22 | E a tap on a gnome's body is not its pad | yes | first | GardenCam: 33 passed, 2 failed FAIL: a tap through a gnome's body picks the gnome's pad -> got 6, want 18 | yes (sha256) |
| M23 | E the overview reaches under the HUD's top rows | yes | first | check_reach: 68 passed, 1 failed FAIL: and none is under the HUD's top rows -> got 23, want 0 | yes (sha256) |
| M24 | E a live hazard does not zoom on the gardener | yes | first | check_reach: 68 passed, 3 failed FAIL: a live hazard zooms the view onto the gardener -> got overview, want hazard | yes (sha256) |
| M25 | E the Garden client never reports a live hazard | yes | first | check_reach: 66 passed, 2 failed FAIL: a hazard came within 260 s of garden time | yes (sha256) |
| M26 | B/E a celebrated band does not look up at its sky | yes | first | check_brag: 18 passed, 1 failed FAIL: and the garden view looks up at the moon for the brag | yes (sha256) |
| M27 | E out of the garden the view keeps the camera | yes | first | check_reach: 69 passed, 2 failed FAIL: out of the garden the garden view lets go -> got overview, want free | yes (sha256) |
| M28 | H next to the board the camera does not read it | yes | first | check_reach: 68 passed, 3 failed FAIL: next to your board the camera turns to read it -> got overview, want board | yes (sha256) |
| M30 | E fit lets points out of the region (y) | yes | first | GardenCam: 34 passed, 1 failed FAIL: fit puts every point inside the region (x 8.0..836.0, y 27.3..475.8) | yes (sha256) |
| M31 | E zoomOn searches the wrong way | yes | first | GardenCam: 33 passed, 2 failed FAIL: and no closer than that needs (2209.8 px) | yes (sha256) |
| M32 | C the reveal refund set to 70% in Config | yes | first | Economy, Garden: 64 passed, 1 failed FAIL: before it, a sale gives everything back: nothing has been fought, nothing is gained -> got 0.7, want 1 | yes (sha256) |
| M33 | E a capture rig's camera is fought every frame | yes | first | check_reach: 69 passed, 2 failed FAIL: a camera marked ExternalCamera is left to its owner -> got overview, want external | yes (sha256) |
| M34 | E pads carry a ClickDetector again (racing the view's pick) | yes | first | check: 95 passed, 1 failed FAIL: no pad carries a ClickDetector: the garden view picks every tap -> got 57, want 0 | yes (sha256) |
| M35 | E the HUD tells the view the world starts at the screen's top | yes | all | check_reach: 69 passed, 2 failed FAIL: and none is under the HUD's top rows -> got 14, want 0 | yes (sha256) |
| M36 | A1 the merge never raises the chapter | yes | first | walk, check: 26 passed, 1 failed FAIL: after a rejoin the garden starts summer -> got 1, want 2 | yes (sha256) |
| M37 | A1 a restored chapter is not dug on the reveal | yes | first | check_store: 41 passed, 1 failed FAIL: the veteran's garden is the Moonlit Bed again, not Spring -> got 1, want 5 | yes (sha256) |
| M39 | B1 the client names a band before the bed is dug (the load window primes band 1) | yes | all | **SURVIVED** all 27 gates | yes (sha256) |
| M40 | B2 an unfinished wave may reach its boundary (Config cap 1) | yes | first | Garden: 132 passed, 2 failed FAIL: a Queen with a sliver of health keeps progress at 29.999 or less (30.000000) | yes (sha256) |
| M41 | B2 Garden.progress ignores the in-wave cap | yes | first | Garden: 132 passed, 2 failed FAIL: a Queen with a sliver of health keeps progress at 29.999 or less (30.000000) | yes (sha256) |
| M10b | E2/D4 a failed day's-bed read is cached for the day (the fallback becomes the day's bed) | yes | first | check_daily: 6 passed, 7 failed FAIL: (the store was asked again meanwhile: 3 calls) | yes (sha256) |
| M20b | P1/R1 a small cell is not zoomed on (the first tap does nothing) | yes | first | walk, check_reach: 8 passed, 19 failed FAIL: tapping a pad opens the gnome sheet | yes (sha256) |
| M29b | R1 a mouse click is taken for a finger (it zooms and picks nothing) | yes | first | check_reach: 68 passed, 3 failed FAIL: a mouse click picks the pad under it -> got 0, want 5 | yes (sha256) |
| M38b | B1 the first sight of a garden celebrates its band (a Frost join plays the HARVEST MOON) | yes | first | check_frost, check_restore: 33 passed, 4 failed FAIL: but nothing is celebrated on a join: no golden flash -> got 1, want 0 | yes (sha256) |
| M42 | E1 the server's 4-stud poll is back (a shove resumes a pause, ends the AFK hold) | yes | first | check, check_grief: 94 passed, 2 failed FAIL: a 5-stud move of the character alone does not resume it -> got false, want true | yes (sha256) |
| M43 | E1 gardeners collide with each other again | yes | first | check_grief: 24 passed, 1 failed FAIL: and gardeners never collide with each other (no shoving, no fling) -> got true, want false | yes (sha256) |
| M44 | E1 characters are never put in the gardeners' group | yes | first | check_grief: 23 passed, 2 failed FAIL: every part of every character is in it -> got 3, want 0 | yes (sha256) |
| M45 | E1 a Here (input seen) also resumes a pause | yes | first | check: 95 passed, 1 failed FAIL: nor does the client's Here (input seen: the AFK hold only) -> got false, want true | yes (sha256) |
| M46 | E1 the client reports Here with no input from its player | yes | first | check_grief: 23 passed, 2 failed FAIL: the shoves made the victim's client report no input (no Here) -> got 6, want 0 | yes (sha256) |
| M47 | E1 the client never reports its player's own step (Here) | yes | first | check_grief: 24 passed, 1 failed FAIL: and their client reports it as input (Here: 0) | yes (sha256) |
| M48 | E2 every ask during an outage draws a new fallback bed (bed fishing) | yes | first | check_daily: 12 passed, 1 failed FAIL: while the store stays down, three TRY AGAINs a minute apart all get this server's one fallback bed -> got 4, want 1 | yes (sha256) |
| M49 | E3 the board's prompt answers every trigger | yes | first | check_grief: 22 passed, 3 failed FAIL: 2000 triggers in one instant are answered at most once (2001 payloads) | yes (sha256) |
| M50 | P1 a phone tap on a small cell picks at once (no zoom first) | yes | first | check_reach: 68 passed, 3 failed FAIL: on a phone the first tap on a small cell opens no sheet (it zooms) -> got 216, want 0 | yes (sha256) |
| M51 | P1 the picked pad is not drawn gold | yes | first | walk, check_reach: 26 passed, 1 failed FAIL: and that pad is drawn gold -> got nil, want 14 | yes (sha256) |
| M52 | P1 a zoom nobody follows up never eases back | yes | first | check_reach: 65 passed, 6 failed FAIL: a zoom without a pick goes back to the whole garden by itself -> got zoom, want overview | yes (sha256) |
| M53 | P1 no hint after a tap that only zoomed | yes | first | check_reach: 70 passed, 1 failed FAIL: and the HUD says what comes next () | yes (sha256) |
| M54 | P1 the zoom makes cells 48 px again (its neighbours 42 px) | yes | first | GardenCam: 34 passed, 1 failed FAIL: and its eight neighbours are tap targets of 44 px or more too | yes (sha256) |
| M55 | P2 the overview ignores the touch controls (plain fit) | yes | first | check_reach: 70 passed, 1 failed FAIL: nor in the DynamicThumbstick's wider frame (the left 40% of the lower two thirds) -> got 41, want 0 | yes (sha256) |
| M56 | P2 fitClear returns the plain fit whatever lies under the controls | yes | first | GardenCam, check_reach: 34 passed, 1 failed FAIL: and with it no pad's cell overlaps the thumbstick's or the jump button's zone -> got 2644, want 0 | yes (sha256) |
| M57 | P2 the garden view's thumbstick frame narrower (30% of the width) | yes | first | check_reach: 69 passed, 2 failed FAIL: on four phone sizes no pad of the whole-garden view lies under the thumbstick or the jump button -> got 15, want 0 | yes (sha256) |
| M57b | P2 the garden view's thumbstick frame only the bottom third | yes | all | GardenCam, check_reach: 30 passed, 5 failed FAIL: (the frame holds the HUD's thumbstick corner on 844x390) | yes (sha256) |
| M58 | P3 the glow stops once the first gnome stands (REVIEW-1's rule) | yes | first | check_env, check_reach: 114 passed, 1 failed FAIL: three (the best free pads for the next gnome) keep a steady glow -> got 0, want 3 | yes (sha256) |
| M59 | P3 the glow ranks for a Pebble whatever gnome is starred (PathGen.glow) | yes | first | PathGen: 63 passed, 1 failed FAIL: and the pads that glow are the Sprinkler's best free ones (seed 4), not the Pebble's (15,14,20) -> got 15,14,20, want 15,14,17 | yes (sha256) |
| M59c | P3 the client lights the pads for a Pebble whatever the sheet stars (its call to PathGen.glow) | yes | first | check_brag, check_reach: 18 passed, 1 failed FAIL: with the Lantern starred, the pads that glow are a Lantern's best free ones, not a Pebble's -> got 4,20,46, want 17,35,36 | yes (sha256) |
| M60 | P3 the sheet always stars the Pebble | yes | first | check_reach: 69 passed, 2 failed FAIL: the sheet stars that gnome (Sprinkler | yes (sha256) |
| M61 | P3 the normal profile plants a Pebble whatever the star says | n/a (test model) | first | Pacing: 23 passed, 6 failed FAIL: chapter 3 (the brag) is a real fight for a normal player: 50-99% first try (15.0%) | yes (sha256) |
| M62 | P4 a new bed's first progress is a reach (a late restore plays the brag) | yes | first | check_restore: 7 passed, 3 failed FAIL: but the restore celebrates nothing: no golden flash -> got 1, want 0 | yes (sha256) |
| M63 | P5 a tap on the board in the board view picks a pad behind it | yes | first | check_reach: 69 passed, 2 failed FAIL: 35 taps on the board's face open no gnome sheet -> got 6, want 0 | yes (sha256) |
| M64 | P6 the band's card replaces the season's (the brag line lasts a frame) | yes | first | walk, check_brag: 26 passed, 1 failed FAIL: the season's own card stays readable 3 s or more, not replaced by the band's (0.1 s) | yes (sha256) |
| M65 | P6 every card flashes (the brag flashes twice) | yes | first | check_brag: 18 passed, 1 failed FAIL: the brag flashes once, not once per card -> got 2, want 1 | yes (sha256) |
| M66 | P7 PAUSE while walking pauses anyway (and flickers) | yes | first | check_reach: 69 passed, 2 failed FAIL: PAUSE pressed while walking does not flicker the garden paused (5 tries) -> got 5, want 0 | yes (sha256) |
| M67 | P7 the cooldown refuses a resume again | yes | first | check_reach: 69 passed, 2 failed FAIL: a pause, then a step 0.1 s later: the step resumes the garden every time (5 tries) -> got 0, want 5 | yes (sha256) |
| CTRL | CONTROL: the selected pad's gold one unit greener (every test reads gold as a range) | yes | all | **SURVIVED all 27 gates**, as a control must | yes (sha256) |

**67 of 68 mutants killed; the control survived all 27 gates, as it must; after the sweep every copy's 52 files were
byte-identical to the pristine snapshot (sha256), and the live tree was unchanged.**

The one survivor, **M39** (the client names a band before the bed is dug), is now an equivalent mutant: P4's fix
names the first progress of every attempt quietly, and the load window has no attempt yet, so priming band 1 there
changes nothing a player sees (a Spring joiner gets no card either way; a Frost joiner the same quiet card). Round 1
killed it with check_frost; its defence is now doubled. M57b is killed deterministically by GardenCam.spec and only
sometimes by reach section 11 (it depends on the bed).

### Final gates (round 2, the final tree, bundle rebuilt first, LuaJIT shim)

| gate | count |
|---|---|
| 14 specs | 1013 assertions: Board 66, Economy 65, EnvBands 124, EnvConfig 56, Garden 134, GardenCam 35, Hazards 152, Pacing 29, PathGen 64, Responsive 70, Rest 55, Rng 32, Waves 118, Wire 13 |
| `tests/project_spec.py` | 6 |
| `tests/walk.luau` | 27 |
| robloxemu, 11 checks | check 96, brag 19, daily 13, env 115, frost 37, grief 25, hud PASS (16 viewports x 3 modes, overlap = true), reach 71, restore 10, save 38, store 42 |
| all 50 Luau files (src, tests, checks) | transpile and compile on the shim (`luaurun.py --check`): 50, 0 bad |
| `luau-analyze src/`, `luau-compile` | NOT RUN: no binary on this machine |

27 of 27 green. Every server-random gate then ran 8 more times (`scratchpad/ggd3/repeat.py`): walk, check, brag,
daily, env, frost, grief, hud, reach, restore, save and store were each **8/8 green** (96 runs). What they measured:
- the walk: the first gnome planted 4.0 s after landing (8/8; one tap more than round 1, the zoom), READY at 8.3 s,
  spring won in one attempt at 6.4-9.8 min with 11 plants and 6-7 upgrades; 19-20 taps, 18-19 of them on a cell
  under 44 px (15.3-16.9 px, so zoomed first), every gnome confirmed on 50.2 px or more; SPRING WON readable 5.3 s;
- reach: 1440 off-centre tries, 0 wrong; 0 pads under a touch control on 4 phones; the red ring 60-62 px in the
  hazard zoom; the board 72% of the screen's height up close;
- brag: the loss to the Queen at Progress 29.917 with no moon (8/8), the win with 1 golden flash and its line 5.4 s;
- frost: the Mantis fell 9.9-12.4 min after the join in 7 runs and at 21.3 min in one that needed more attempts;
  Moonlit Snow named in FROST WON's line; wave 41 saved;
- grief: 2 payloads for 2000 triggers, 180 for a minute of 500/s (8/8).
- Pacing.spec (deterministic): brag median 33.6 min (p10 30.3, p90 53.3, worst 61.8), normal first try
  98/95/78/57%, a hazard every 2.58 min, the Aurora reached by 17 of 40 normal players.

### The complete-game standard (docs/complete-game-standard.md), after round 2

**§1. It works, and it is honest:** met.
- Core loop from join through screen taps: the walk, 27/27 in 8 of 8 runs; past the brag, check_frost (8/8).
- Spawn order unchanged: RespawnLocation before any yield; the new CharacterAdded hook writes no CFrame and never
  yields.
- No secrets replicate: the new `Here` remote carries nothing; the leak scan is unchanged.
- DataStore: unchanged from round 1, plus one fallback bed per day during an outage (E2).
- No silent no-ops: PAUSE while walking now says why (P7); a refused board toggle says "Slow down" once a second.
  (A tap in the board, sky or free view picks nothing by design: it is not an action.)

**§2. It looks good:** met.
- Bands, weather, budgets as round 1 (the pad looks recolour existing pads: no new part).
- Hazards: unchanged; a hit no longer counts as the gardener being "here".
- Rest/PAUSE: never an exploit, and now nobody else can end it (E1); clear when refused (P7).
- Brag: median 33.6 min for a player who follows what the game SHOWS (the star and the glow, P3); shown for a win
  only, never on a join or a late restore (P4), with its own line readable and one flash (P6).
- Phone first: HUD check PASS, overlap = true; world taps: a pick happens on 44 px or more on a phone (the first
  tap on a small cell only zooms, P1), the pick is visible (gold), and no pad lies under the thumbstick or the
  jump button (P2). Written reason kept: the whole garden cannot be 44 px a cell on a 390 px phone (15-16 px).

**§3. Players can compare themselves:** met; the prompt can no longer be made to echo (E3), and fallback-bed
fishing is closed (E2).

**§4. Ready to ship and to market:**
- Met: README store text unchanged (815 ASCII characters; its claims still true), EYECANDY.md (23 needs-Studio
  items, 4 thumbnail shots), MARKETING.md (8 clips; clip 1 restaged for the two-tap pick), CLAUDE.md (11 checks,
  the new traps).
- Gates green, TDD as stated above, new assertions mutation-tested with a control (67 of 68; the survivor
  equivalent). Still on the shim only.

**§5. Night shift:** not done, by rule.

### Still open (round 2)
1. **Real Luau.** Re-run every gate with `luau` and run `luau-analyze src/` (needs a binary and the owner's
   permission to fetch one).
2. **EYECANDY.md §7, 23 needs-Studio items.** New: 19 gardeners pass through each other; 20 the real thumbstick
   frame (the garden view assumes 40% x lower 2/3; resize `Config.Hud.StickW/StickH` to what Studio shows); 21 the
   gold and green pads and the star readable in every band; 22 `Here` from the real thumbstick and taps, and an idle
   gardener held despite hazard knocks; 23 the "stand still" notice and a quick pause-then-walk.
3. **Publish settings:** Max Players 8 and **Console OFF** (P8: no gamepad path; a gamepad cursor is a later pass).
4. **tools/film_game.py (read-only for me):** a GNOME entry that sets `ExternalCamera = true`, and the 8 clips.
5. **Shipping steps:** nothing committed (no git by rule), no universe, no thumbnails, no publish.

---

## Round 1 (2026-10-07): two adversarial reviews closed, as written then

Kept as it was closed. Its gate counts, its standard status and its "still open" list are superseded by round 2
above; its findings, tests and mutants still hold (round 2's sweep re-ran M1-M41 on the current code).


Two reviewers read the v1 build: one on data and the server (5 findings), one on what a player can reach (10
findings). One finding appears in both (the read-only session). Every finding below was **reproduced first** on
the build as it was, with the reviewers' own probes re-run in a copy of the original tree. Then a failing test,
then the fix in the game. 14 of the 14 distinct game findings are closed. The tooling finding (no real Luau, no
`luau-analyze`) is still open: no binary exists on the machine, and fetching one needs the owner's permission.

**Every number here was measured on the LuaJIT shim** (`scratchpad/ggd/luaushim`, see CLAUDE.md "State"), not
on real Luau. Nothing was opened in Studio, published or committed.

### The findings

Reviewer 1 is data and the server (D1-D5). Reviewer 2 is reach (R1-R10). "Before" is the original build; "after"
is the fixed build. The tests are named by file.

| # | finding | before (reproduced) | fix | test (failed first) | after |
|---|---|---|---|---|---|
| D1 = R5 | A read-only session never recovers: another server's lock, a crash lock, or one failed read lost the whole session's progress | probe B: the lock was released, but 60 s later Saving was still false; best wave 11 in memory, 10 stored after the leave. Probe E: one failed read put a wave-52 veteran in Spring with BestWave 0, and 120 s later nothing had changed. Probe lock: a rejoin had chapter 1, best wave 0 | `Main.server`: the load is `tryLoad` (it always reads, and takes the lock only if it is free; a locked record is read without being written). It is retried 2, 4, 8, 10, 10 ... s apart. When it gets the lock it merges (the higher chapter and best wave; at an equal wave the earlier time stands), saves at once and toasts "saved again". A garden still on its reveal moves to the restored chapter, and TRY AGAIN / NEXT SEASON use the higher chapter. A failed read writes nothing | `check_gnomegardendefense_store` 1-2 (on the original: Saving false 60 s after the release; chapter 1, want 5) | read-only -> saving 1.5 s after the old lock was freed; the best wave played while read-only is saved; the veteran is back in chapter 5 with 52, and the record was never overwritten during a 30 s outage |
| D2 | A player who leaves during the load keeps the lock for 45 s | probe A2: the record kept this jobId and a token, with lockUntil-now = 45 | a lock taken by a load that returns after the leave is given straight back (`releaseLock`, guarded by token and jobId) | store 3 (lockUntil-now = 45 on the original) | no lock left |
| D3 | The season-win save runs on the simulation thread, so every garden freezes for its round trips | probe C: B's ticks stopped for 2.0 s, and the largest gap was 2.10 s at 1.0 s latency | the win save is `task.spawn`ed. Saves are serialised per player (`p.saving`), and nothing writes after the leave has released the lock | store 5: three endless gardens mid-wave through a 2.5 s win save (on the original: a 2.60 s tick gap, and a late win save re-locked the record after the leave) | the largest tick gap is 0.10 s through the win save; the record ends released (lockUntil 0) |
| D4 | One failed read of the day's endless bed is cached for the whole UTC day | probe D: after one blip, this server kept 1118950353 and every other server had 123456789; the store was not asked again | `dailySeed`: up to 3 tries (1 s, then 2 s apart). If the store is down, this server's own bed is used for 60 s, then the store is asked again (and every new attempt asks) | `check_gnomegardendefense_daily` (on the original: 4 passed, 7 failed) | 11/11: after an outage plus one blip, the next joiner, the later ones and the first gardener's TRY AGAIN all play 123456789 |
| D5 | A gardener who leaves while the day's bed is drawn leaves a board behind (it stacks on the next one), and the sim indexes a nil garden | probe A1: GardenBoard_7001 left behind, two boards at (-5, 6, 84), the stale prompt refused the new owner, and "garden step failed" twice | `newAttempt` draws first, then builds nothing if the player has left. `onPlayerAdded` returns at once. Leaving frees the seat FIRST and saves after. The sim loop and the activity poll skip a garden with no bed yet | store 4, run before anything draws the day's bed (on the original: 1 board left, 7 step failures, 2 boards for the next joiner) | 0 boards, 0 step failures, exactly one board for the next joiner, and its prompt answers its owner |
| D6 | Refusals are echoed 1:1, and taps in the join's load window get no answer | probe B2: 2000 calls gave 1999 toasts. Probe A2: 2 requests in the load window gave 0 toasts | "Slow down" and the new "Your garden is still being dug" are said at most once a second (`sayOnce`). SetPaused takes its bucket token before the type check | store 3 and 6; the save check's 60-call burst now expects 1 "slow down", not 40 | 2000 calls give 21 toasts (20 served plus 1); a tap in the load window is answered |
| R1 | From the spawn, at Roblox's default camera, every pad was under 44 px on a phone | probe cam: 897 of 897 pads over 20 beds were under 44 px; the glowing ones were a median 3.8 px tall | the **garden view** (`View.client` + the pure `GardenCam`): a Scriptable camera frames the whole garden under the HUD. A tap is picked from the PathCells attribute (a gnome's body, else the 8-stud cell under the finger, else the nearest pad within one cell); pads have no ClickDetector. On touch, a cell under 48 px zooms the view until it is 48 px or more, above the open sheet. A live hazard zooms on the gardener; a celebrated band looks up at its sky piece; next to the board the view reads it; outside the garden Roblox's camera follows the player; a camera marked `ExternalCamera` is left alone | `tests/GardenCam.spec.luau` (24), `check_gnomegardendefense_reach` 1-2 and 6-9, the walk now taps the SCREEN (`tests/Tap.luau`) | a full bed cannot be on screen at 44 px a cell on a 390 px phone (GardenCam.spec: 16.8 px at the best framing; reach: 16.1 px). So, measured: EVERY pad of a bed is selected in at most two taps (a finger 9 px off the centre first; 3-6 of 42-48 pads needed the second, over 6 runs), the deciding tap lands on a cell of 45.2 px or more, and the zoom gives 48.0 px or more on all 108 cells. The walk: first gnome at 3.7-4.0 s, 0-4 second taps out of 18-19, every gnome confirmed on 45.4 px or more. Desktop overview: 33.6 px at worst (mouse, no zoom). The ring is 55-57 px during the hazard zoom |
| R2 | Losing a boss wave announces the next season (the Queen's loss played the HARVEST MOON) | probe falsebrag: Progress 30, band moon, card "HARVEST MOON / wave 31", panel "The bugs ate your carrots!". Also seen in 3 of 20 natural runs | `Garden.progress` counts bugs STOPPED (killed, plus a live boss's lost health), not bugs that reached the patch. A lost wave stays below its boundary | `Garden.spec` (a lost Queen wave, an undefended wave); `check_gnomegardendefense_brag` plays autumn for real: it loses to the Queen, then wins | lost at Progress 29.917 (4 of 4 runs): no moon card, chip, band or sky look. The real win then shows the card and looks up at the moon for 4.6 s |
| R3 | A spring bed can sell itself into a dead end on the reveal | probe softlock: 0 gnomes and 45 seeds; plant, READY and Restart were all refused; 10 min later it was unchanged | `Config.RevealRefund = 1`: before the bed's first wave a sale gives everything back (`Garden.refundShare`). After it, 70% as before. The HUD's SELL label shows the share | `Garden.spec` (the reviewer's 5 cycles; 3000 random orders keep seeds + planted = 120), `Economy.spec`, reach 3 through the HUD | six plant-and-sell tries leave 120 seeds; "SELL +50" on the reveal; a gnome is always affordable |
| R4 | Pads are bound once per attempt, and StreamingEnabled is not pinned off | probe stream: 49 pads held back, and no tap ever opened the sheet (30 s later still not) | `default.project.json` pins `Workspace.StreamingEnabled = false`. Taps need no pad Instance (picked from PathCells). The HUD rebinds when the Bed or its Gnomes folder arrives. The glowing pads are looked up again until found | `tests/project_spec.py` (2 failed on the original), reach 0 (the bed detached before the scripts start) | 6/6; with no bed streamed in, a tap opens the sheet for pad 1; once the bed arrives, its best pads glow |
| R6 | PAUSE is silently undone within a second after a short walk | probe pause: 3 of 10 pauses undone within 2 s | SetPaused(true) re-bases the activity poll's position on the character | reach 4: 10 tries with the press at 0.30-0.93 s after a 6-stud walk (and, after T1 below, 10 more at ten phases of the poll) | 0 of 10 undone (0 of 20 after T1) |
| R7 | The hedge gap the bugs come through leads into the void | probe void: nothing at x = -16.5 ... -30 through the gap; no baseplate | a Meadow part (864 x 704 studs, 0.2 below the lawns) under every slot, reaching 120 studs past the outer hedges | reach 5: ground through the gap and outside every hedge (11 points) | no hole |
| R8 | The board is 53 studs from the spawn and outside the first view | probe board: 53.3 studs; 77 degrees to the left of the default camera | the board stands ON the deck's west end, facing the garden view's camera. The overview fits its top. Within 12 studs the view turns to read it | reach 1 and 6 | in the first view, 40.3 studs from the spawn; up close it fills 72% of the screen's height |
| R9 | Band 1 has no weather | `Config`: Spring Sprouts `weather = {}` | dandelion fluff at 4/s. Moonlit Snow (which shared Snowfall's snow) got frost glitter, so no two neighbours share their weather | `EnvConfig.spec` (every band has weather; no two neighbours share it), `check_env` (weather falling in every band, 11 new assertions) | 11 of 11 bands have weather; the worst seam is still 2 weather emitters at 40 particles/s |
| R10 | No gate ever ran on real Luau, and there was no `luau-analyze` pass | `which luau` finds nothing; the scratchpad luau/ folder is empty | not closable here: CLAUDE.md now lists `luau-analyze src/` as a gate marked NOT RUN | - | **open** |

Reviewer 1's "not reproduced" items:
- **Another garden's pads blocked by an exploiter standing on them:** moot now. A tap is picked by math on the
  ground plane and the gnome columns, and characters are not in it.
- **The daze is client-only:** a hacked client can skip it, but `Pacing.spec` measures that with every hazard
  hitting, 0 of 160 chapter outcomes change, so skipping it gains nothing measurable.
- **MaxPlayers 8 is only in a comment:** it is now a publish setting on EYECANDY.md's needs-Studio list (§7, 16).

### Found while closing them

- **The walk's camera measurement.** A gnome was confirmed while a hazard had the camera (25.8-40.5 px in 3 of
  24 walks). This is not a game defect: the camera was on the gardener, and the sheet stays usable. These are
  now counted apart. A pad tapped during a hazard comes back zoomed afterwards (reach 4).
- **Gnome taps hid the pad behind.** A whole-cell gnome column hid the centre of the pad behind it from a
  50-degree ray. The column is now the gnome's width, 1.5 studs either side (GardenCam.spec, with a control).
- **Four flaky gates from the build, now fixed:**
  - `check_env`'s hazard spacing added the first hazard's 3.8 s flight on top of the 5 s watched during it. It
    failed when the interval was over about 146.7 s. It is now timed seen-to-seen on the clock.
  - `check_env`'s "one hit" was an absolute count. A hazard that fell during the band sweep made it 2. It is now
    counted from before the acorn.
  - The main check missed the wave-3 preview when its upgrade section had already played past wave 3. It now
    listens for it.
  - `check_save`'s AFK gardener planted on pads 1 and 2 and lost an unlucky bed before the 180 s hold. It now
    plants on the two best pads.
  - My own `check_store` gave its winner 600 s; 1 run in 64 needed more. It now has 2400 s.
- **One gap in my own test, exposed by the mutation sweep.** In the dry run M7 (a bed built for a player who has
  left) SURVIVED: store scenario 4 ran after the day's bed was cached, so nothing yielded. It now runs first and
  asserts the store was really asked. M7 is killed.

After these, every server-random gate ran 64 times in parallel: walk, check, brag, daily, env, hud, reach and save
were 64/64 green. Store was 63/64 before its time limit was raised, then 48/48.

### After the reviews: the build's own pass (the same evening)

The first run of the final sweep was cut off after M16, and in it **M14 (PAUSE not re-based) SURVIVED**. Then the
build walked the player past the brag (Frost, the Mantis, the endless bed), which no gate did, and found two
defects. Each was reproduced on the tree as it was, a failing test came first, then the fix.

| # | finding | before (reproduced) | fix | test (failed first) | after |
|---|---|---|---|---|---|
| T1 | reach section 4 could not see a pause that is not re-based: its tries met the server's once-a-second poll at lucky phases (walk 0.6 s, press 0.30-0.93 s later), so a poll usually fell between the walk and the press and hid the defect | M14 killed in the dry run, SURVIVED all 24 gates in the final run | a second series in reach section 4: 6.4 studs at Roblox's default 16 studs/s, PAUSE 0.0-0.2 s after stopping, each try exactly 3.7 s long, so its ten tries meet the poll at ten different phases | with M14 applied: 4 of 4 runs red (PAUSE taken in 2-5 of 10 tries, 1-3 undone); the game unchanged: 8 of 8 green | M14 killed in the final sweep below |
| B1 | a gardener whose save is at Frost had the HARVEST MOON brag replayed on EVERY join: Frost's bed starts at Progress 30, inside the moon's band, and the band announcer's first sight of it celebrated (golden flash, the 4.5 s card, the garden view looking up at the moon) | probe: card "HARVEST MOON", 46 frames (4.6 s) of the sky look on join, a golden flash | `Garden.client`: the first PUBLISHED progress of the session primes the announcer quietly (a 3 s card naming the band, no flash, no sky look); before the bed is dug (the profile load) nothing is named | `check_gnomegardendefense_frost` section 1, the client starting during a 2 s profile load: on the original 4 failed (1 golden flash, 46 sky frames, the card 5.3 s); the two ways back (M38 no quiet first sight, M39 naming before the bed is dug) each fail it the same way | 0 flashes, 0 sky frames, a 3 s card; the brag check is unchanged (the real win still flashes and looks up) |
| B2 | a boss with a sliver of health named the NEXT band while it still walked: the server publishes Progress in 3 decimals, so a Mantis at 1% rounded up onto 40; one run then LOST that wave with Moonlit Snow already named. A Slug Queen sliver would play the HARVEST MOON before she falls, or for a loss (R2 again, by rounding) | instrumented Frost runs: Moonlit Snow named during wave 40 with the Mantis at 0-1% in 4 of 6 runs; in 1 of 7 runs the wave was then lost | `Garden.progress`: an unfinished wave stops at (wave - 1) + `Config.ProgressInWaveMax` (0.999); the boundary is reached only when the wave is survived | `Garden.spec` (a Queen at 50 ... 0.001 HP: raw 30.000000 and published 30.000 on the original, 2 failed); `check_frost`'s "no band before its wave was survived": 5 of 6 runs red on the original | 29.999 at most; check_frost 8 of 8 green, every Frost band named at or after its wave's end; Pacing.spec unchanged (27 passed, brag median 33.6 min) |

Also: README's store heading said 812 characters; the text measures 815 (now stated).

### Mutation sweep

`scratchpad/ggd2/mutate.py` works in an isolated copy (`ggd2/m4`) of the final game and checks. Its sha256 was
confirmed equal to the real tree before the sweep (`diff -rq`, `cmp`). For each mutant it checks that the file's
sha256 is the pristine one, applies exactly one replacement, rebuilds the bundle, and proves the mutated text is
in `build/gnome-garden-defense.luau` ("reached"; M18 changes the project file, which the bundle does not
contain). It then runs ALL 25 gates in parallel (14 specs, the project spec, the walk, 9 checks; a run with no
summary line counts as killed), restores the file and checks its sha256 again. M1-M37 are REVIEW-1's, M38-M41 the
build's own (B1, B2 above); the control changes the meadow's colour by one unit, which nothing reads.

| # | finding | mutant | reached the bundle | killed by (first failing line) | restored |
|---|---|---|---|---|---|
| M1 | R2 | progress: a leaked bug counts as gone (the false brag) | yes | Garden: 125 passed, 2 failed FAIL: it is the bugs actually stopped that count -> got 29.999, want 29.916666666666668 | yes (sha256) |
| M2 | R3 | reveal refund back to 70% in the sim | yes | Garden, check_reach: crashed: 	runtime.lua:597: in function <runtime.lua:588> | yes (sha256) |
| M3 | R3 | the HUD's SELL label ignores the reveal refund | yes | check_reach: 44 passed, 1 failed FAIL: on the reveal the SELL button offers everything back (+50) -> got SELL | yes (sha256) |
| M4 | D1 | a read-only/failed session never retries | yes | check_store: 32 passed, 10 failed FAIL: once the lock is gone the session takes the record and starts saving -> got false, want true | yes (sha256) |
| M5 | D1 | a late lock takes the stored best, dropping what was played | yes | check_store: 40 passed, 2 failed FAIL: and what was played while read-only is saved (best wave 1) -> got 0, want 1 | yes (sha256) |
| M6 | D2 | a lock taken by a player who left during the load is kept | yes | check_store: 41 passed, 1 failed FAIL: a player who left during the load leaves no lock (lockUntil-now = 45) | yes (sha256) |
| M7 | D5 | a bed drawn for a player who left is still built | yes | check_store: 38 passed, 4 failed FAIL: a gardener who left while the bed was drawn leaves no board behind -> got 1, want 0 | yes (sha256) |
| M8 | D3 | the season win is saved on the simulation thread | yes | check_store: 41 passed, 1 failed FAIL: at least one other garden was mid-wave through the win's save (precondition) | yes (sha256) |
| M9 | D3 | saves are not serialised (a late win save re-locks) | yes | check_store: 41 passed, 1 failed FAIL: and the lock is released: the slow win save did not re-lock it after the leave -> got 17914061 | yes (sha256) |
| M10 | D4 | a failed day's-bed read is cached for the day | yes | check_daily: 5 passed, 6 failed FAIL: one failed read is retried: the next endless gardener plays the day's shared bed -> got 4374092 | yes (sha256) |
| M11 | D4 | the day's bed is asked once | yes | check_daily: 4 passed, 7 failed FAIL: after asking the store 3 times -> got 1, want 3 | yes (sha256) |
| M12 | D6 | every refused call is echoed | yes | check_save, check_store: 37 passed, 1 failed FAIL: and the rest are refused out loud: told once to slow down, not 40 times -> got 40, want 1 | yes (sha256) |
| M13 | D6 | a tap in the load window is dropped silently | yes | check_store: 41 passed, 1 failed FAIL: a tap in the load window is answered (nil) | yes (sha256) |
| M14 | R6 | PAUSE does not re-base the step poll | yes | check_reach: 42 passed, 3 failed FAIL: 6 studs at 10 studs/s: PAUSE takes in every try -> got 9, want 10 | yes (sha256) |
| M15 | R7 | no meadow under the hedge gap | yes | check_reach: 44 passed, 1 failed FAIL: there is ground through the hedge gap and outside every hedge (gap x-16.5 gap x-18 gap x-20 ga | yes (sha256) |
| M16 | R8 | the board back at the lawn west of the deck (53 studs) | yes | check_reach: 44 passed, 1 failed FAIL: and near the spawn (53.2 studs, at most 45) | yes (sha256) |
| M17 | R9 | the dawn band without weather | yes | EnvConfig, check_env: 55 passed, 1 failed FAIL: every band has its weather, the dawn too (sprouts) -> got 1, want 0 | yes (sha256) |
| M18 | R4 | StreamingEnabled not pinned off | n/a (project file) | project: 5 passed, 1 failed FAIL: Workspace.StreamingEnabled is pinned to false | yes (sha256) |
| M19 | R4 | the glowing pads are looked up once per attempt | yes | check_env, check_reach: 112 passed, 2 failed FAIL: on a new bed exactly three pads pulse () -> got 0, want 3 | yes (sha256) |
| M20 | R1 | a small cell is not zoomed on | yes | walk, check_reach: 21 passed, 1 failed FAIL: every gnome was planted or upgraded with its pad 44 px or more on screen (smallest 16.9) | yes (sha256) |
| M21 | R1 | a tap beside a pad does not snap to it | yes | GardenCam, check_reach: 22 passed, 2 failed FAIL: a tap on the path just below a pad snaps to it -> got nil, want 6 | yes (sha256) |
| M22 | R1 | a tap on a gnome's body is not its pad | yes | GardenCam: 22 passed, 2 failed FAIL: a tap through a gnome's body picks the gnome's pad -> got 6, want 18 | yes (sha256) |
| M23 | R1 | the overview reaches under the HUD's top rows | yes | check_reach: 44 passed, 1 failed FAIL: and none is under the HUD's top rows -> got 19, want 0 | yes (sha256) |
| M24 | R1 | a live hazard does not zoom on the gardener | yes | check_reach: 43 passed, 2 failed FAIL: a live hazard zooms the view onto the gardener -> got overview, want hazard | yes (sha256) |
| M25 | R1 | the Garden client never reports a live hazard | yes | check_reach: 40 passed, 2 failed FAIL: a hazard came within 260 s of garden time | yes (sha256) |
| M26 | R2/R1 | a celebrated band does not look up at its sky | yes | check_brag: 10 passed, 1 failed FAIL: and the garden view looks up at the moon for the brag | yes (sha256) |
| M27 | R1 | out of the garden the view keeps the camera | yes | check_reach: 43 passed, 2 failed FAIL: out of the garden the garden view lets go -> got overview, want free | yes (sha256) |
| M28 | R8 | next to the board the camera does not read it | yes | check_reach: 43 passed, 2 failed FAIL: next to your board the camera turns to read it -> got overview, want board | yes (sha256) |
| M29 | R1 | a mouse click zooms like a finger | yes | check_reach: 43 passed, 2 failed FAIL: without zooming (a mouse is not a finger) -> got zoom, want overview | yes (sha256) |
| M30 | R1 | fit lets points out of the region (y) | yes | GardenCam, walk, check_reach: 23 passed, 1 failed FAIL: fit puts every point inside the region (x 8.0..836.0, y 27.3..475.8) | yes (sha256) |
| M31 | R1 | zoomOn searches the wrong way | yes | GardenCam, walk, check_reach: 23 passed, 1 failed FAIL: and no closer than that needs (2209.8 px) | yes (sha256) |
| M32 | R3 | the reveal refund set to 70% in Config | yes | Economy, Garden, check_reach: 64 passed, 1 failed FAIL: before it, a sale gives everything back: nothing has been fought, nothing is gained -> got 0.7 | yes (sha256) |
| M33 | R1 | a capture rig's camera is fought every frame | yes | check_reach: 43 passed, 2 failed FAIL: a camera marked ExternalCamera is left to its owner -> got overview, want external | yes (sha256) |
| M34 | R1 | pads carry a ClickDetector again (racing the view's pick) | yes | check: 92 passed, 1 failed FAIL: no pad carries a ClickDetector: the garden view picks every tap -> got 42, want 0 | yes (sha256) |
| M35 | R1 | the HUD tells the view the world starts at the screen's top | yes | walk: 21 passed, 1 failed FAIL: every gnome was planted or upgraded with its pad 44 px or more on screen (smallest 30.0) | yes (sha256) |
| M36 | D1 | the merge never raises the chapter | yes | walk, check, check_brag, check_daily, check_frost, check_save, check_store: 21 passed, 1 failed FAIL: after a rejoin the garden starts summer -> got 1, want 2 | yes (sha256) |
| M37 | D1 | a restored chapter is not dug on the reveal | yes | check_store: 41 passed, 1 failed FAIL: the veteran's garden is the Moonlit Bed again, not Spring -> got 1, want 5 | yes (sha256) |
| M38 | B1 | the first sight of a garden celebrates its band (a Frost join plays the HARVEST MOON) | yes | check_frost: 33 passed, 4 failed FAIL: but nothing is celebrated on a join: no golden flash -> got 1, want 0 | yes (sha256) |
| M39 | B1 | the client names a band before the bed is dug (the load window primes band 1) | yes | check_frost: 33 passed, 4 failed FAIL: but nothing is celebrated on a join: no golden flash -> got 1, want 0 | yes (sha256) |
| M40 | B2 | an unfinished wave may reach its boundary (Config cap 1) | yes | Garden: 125 passed, 2 failed FAIL: a Queen with a sliver of health keeps progress at 29.999 or less (30.000000) | yes (sha256) |
| M41 | B2 | Garden.progress ignores the in-wave cap | yes | Garden: 125 passed, 2 failed FAIL: a Queen with a sliver of health keeps progress at 29.999 or less (30.000000) | yes (sha256) |
| CTRL | CONTROL | the meadow's colour, one unit greener (nothing reads it) | yes | **SURVIVED all 25 gates**, as a control must | yes (sha256) |

41 of 41 mutants killed, 0 survived; the control survived every gate, as it must; after the sweep all 50 files of the copy are byte-identical to the pristine snapshot (sha256): yes.

### Final gates

Run 2026-10-07 on the final tree (the swept copy is byte-identical to it), bundle rebuilt first, on the LuaJIT
shim (CLAUDE.md "State"); every line "0 failed":

| gate | count |
|---|---|
| 14 specs | 983 assertions: Board 66, Economy 65, EnvBands 124, EnvConfig 56, Garden 127, GardenCam 24, Hazards 152, Pacing 27, PathGen 54, Responsive 70, Rest 55, Rng 32, Waves 118, Wire 13 |
| `tests/project_spec.py` | 6 |
| `tests/walk.luau` | 22 |
| robloxemu, 9 checks | check 93, brag 11, daily 11, env 114, frost 37, hud PASS (16 viewports x 3 modes, overlap = true), reach 45, save 38, store 42 |
| all 48 Luau files (src, tests, checks) | transpile and compile on the shim (`luaurun.py --check`): 48, 0 bad |
| `luau-analyze src/`, `luau-compile` | NOT RUN: no binary on this machine |

Every server-random gate then ran 8 more times in parallel (`scratchpad/ggd2/repeat.py`): walk, check, brag, daily,
env, frost, hud, reach, save and store were each 8/8 green. What they measured:
- the walk (16 runs over two batches): the first gnome 3.7-4.0 s after landing, READY 8.0-9.3 s, spring won in one
  attempt at 6.6-10.5 min, summer played to wave 13, a rejoin keeps chapter 2 and best wave 12; 18-19 taps (the
  whole-garden cells 16.9-18.5 px), 0-4 needing a second tap, every gnome confirmed on a cell of 45.4 px or more;
- brag: the loss to the Queen at Progress 29.917 with no moon (8/8), the win's sky look 4.6 s (8/8);
- frost: the Frost Mantis fell 9.9-11.3 min after the join on the first attempt (7 runs) and after 41.1 min in one
  run that needed more attempts; then the endless bed's wave 41 survived and saved (8/8).
- Reports: `tests/BandMinutes.luau` and `tests/WaveTable.luau -a normal` run; Pacing.spec prints the brag median
  33.6 min (p10 30.3, p90 53.3, worst 61.8), first-try win rates normal 98/95/78/57%, a hazard every 2.58 min.

How strong the probabilistic kills are, measured apart from the sweep: check_frost's "no band before its wave was
survived" catches M40 in 7 of 8 runs (6 early namings, 1 named in the same frame as the win); in the sweep's single
runs of M40 and M41 it happened to pass, and Garden.spec (deterministic) killed both. Reach section 4 series b
caught M14 in 4 of 4 runs.

### The complete-game standard (docs/complete-game-standard.md)

**§1. It works, and it is honest:** met.
- Core loop from join, through screen taps: the walk, 22/22 in 16 of 16 runs, spring won at 6.6-10.5 min, summer
  to wave 13, rejoin. Past the brag: check_frost plays Frost to the Mantis and the endless bed (8/8).
- Spawn order: unchanged and met.
- No secrets replicate: the leak scan is unchanged.
- DataStore: pcall everywhere and a session token on every write. A session now recovers from a lock or a
  failed read, never writes before reading, serialises its writes and releases on leave.
- No silent no-ops: the load window is answered now, and a flood is told once a second.

**§2. It looks good:** met.
- Fx and signature particles: unchanged.
- 11 bands, each with its own light, scenery, critters and weather (the dawn now too).
- Hazards: the ring is the zone, one at a time, and on a phone the view zooms on the gardener while one is live.
- PAUSE freezes the hazard clock and the garden, earns nothing, and a walk just before no longer undoes it.
- Budgets measured: 52 parts, 2 weather emitters, 40 particles/s, 1 light, 4 beams.
- Brag: median 33.6 min. It is shown for a win only, never on a join (B1) and never before the Queen falls (B2),
  and the view looks up at the moon.
- Phone first: the HUD check PASSes with overlap = true. World taps: every pad is reachable in two taps, and the
  deciding tap is 44 px or more. The whole-garden view's cells are 16-17 px on an 844x390 phone. Written
  reason: nine rows in about 270 free px cannot be 44 px each. The zoom is the answer, and Studio must confirm
  the first tap's feel (EYECANDY.md §7, 1).

**§3. Players can compare themselves:** met.
- An OrderedDataStore board, public and friends, as before.
- The board now stands in the first view, 40.3 studs from the spawn, and the camera reads it up close.

**§4. Ready to ship and to market:**
- Met: README store text (815 ASCII characters), EYECANDY.md (needs-Studio 18, 4 thumbnail shots), MARKETING.md
  (8 clips, plus the camera rule for film_game.py) and CLAUDE.md (gates and traps).
- Gates are green (25 of 25; the random ones 8/8 more each) with a mutation control (41 of 41 killed), but on
  the shim only.
- Test order, honestly:
  - written test-first and watched fail: the pure parts (`Garden.spec`, `Economy.spec`, `GardenCam.spec`,
    `EnvConfig.spec`, the project spec) and the server's store fixes (`check_store` failed 22 times on the
    original before any fix);
  - written after the fix, then proven against the original tree or a mutant: `check_daily` (4/7 on the
    original), `check_brag` (M1) and the client glue (View.client, the HUD's pick and view publishing, and
    Garden.client's hazard and sky signals, all checked by `check_reach` and the walk). Every one of these
    assertions is killed by a mutant in the table above, with one change since B2: check_brag's "no moon for a
    loss" is now guarded twice (R2's stopped-bug count and B2's cap), so no single mutant fails it; M1 and M41
    are each killed by Garden.spec, and check_brag killed M1 in the sweep before B2 (37 of 37 killed then);
  - the build's own pass (T1, B1, B2): every test written first and watched fail on the tree as it was.

**§5. Night shift:** not done, by rule.

### Still open

1. **Real Luau.** Re-run every gate with `luau` and run `luau-analyze src/`. This needs a binary and the owner's
   permission to fetch one.
2. **EYECANDY.md §7, the 18 needs-Studio items.** New ones:
   - the garden view's feel on a phone, and whether a 17 px first tap is aimed near enough;
   - TouchTap's `gameProcessedEvent` and `ScreenPointToRay` conventions;
   - movement under a Scriptable camera;
   - the render-step order with FxClient.shake;
   - the sky look framing the moon and the aurora;
   - the meadow's edges.
3. **tools/film_game.py (read-only for me).** A GNOME entry must set the camera attribute `ExternalCamera = true`
   before it scripts a camera, and all 8 clip scenarios still need adding.
4. **Shipping steps.** Nothing is committed (no git commands, by rule), and there is no universe, no thumbnail
   and no publish.
