# Night-shift queue — progress ledger

Newest night first. Each job: done / in progress (with exact resume point) / blocked (why).

## Night of 2026-10-11 (run started 00:17, stopped at 00:35 on purpose: weekly budget)

Clock: Bash `date` and PowerShell `Get-Date` both read 00:17 at start. FPL gate: open (next deadline
17.10 12:00 is after the weekly reset 14.10 17:00).

**Why the night stopped early:** `get_usage` reported the plan's weekly window ("Weekly · all models")
at **99 % used**, reset 2026-10-14 17:00. A Studio session (screen captures, play traces) would spend
the last percent and the daily `roblox-daily-shorts` task (11:30, every day until the reset) would die
on the limit, three days of Shorts lost. The only unblocked work tonight was Studio work, so nothing
was worth that trade. Nothing was published, no game folder was touched.

- **luau CLI: still missing.** Searched PATH, `%LOCALAPPDATA%\Temp\claude`, the whole user profile
  (depth 6), D:\ (depth 5), `~/.rokit/bin`, `~/.aftman/bin` and WSL. No `luau*.exe` anywhere. rojo is
  present (`~/.cargo/bin/rojo`). Every robloxemu gate is therefore still un-runnable, and the publish
  gate is not met for any game. **The Redeem server freeze is still LIVE on +1 Jump and Grow a Crystal.**
- Untracked daytime-run folders (disaster-rounds, find-it-chapters, gnome-garden-defense, outpost-zero,
  scrapline-tycoon, 64 robloxemu checks) are unchanged since 2026-10-07 and were left untouched.
- Shorts plan: 12 unpublished posts per day on 2026-10-12 .. 2026-10-19 (8 days ahead), no extension.
- G (Reddit): not attempted (budget).

**Owner, please (unchanged from 2026-10-09):**
1. Restore `luau.exe`, or approve its download (github.com/luau-lang/luau releases). Then the next night
   can run every emu check and publish the Redeem fix.
2. Decide whether fliers may top the Vault Runners board.

**Next night (resume order unchanged):** 1. emu checks; 2. publish plus1-jump and grow-a-crystal;
3. fix the HIGHs (labyrint delayed teleport, nightwatch teleport out and back); 4. deep-vein elevator
cooldown; 5. lock leaks. If the weekly window is still above about 95 % at start, stop again and say so.

## Night of 2026-10-09 (run started 00:17)

Clock: Bash `date` and PowerShell `Get-Date` both read 00:17 at start. Skip rule (7.-8.10) no longer applies.
Untracked daytime-run folders (disaster-rounds, find-it-chapters, gnome-garden-defense, outpost-zero,
scrapline-tycoon + 64 robloxemu checks, last written 2026-10-07 23:46) were left untouched.

**No luau CLI on the machine** (searched Temp, D:\Claude, PATH; downloading needs the owner's go). Pure specs
were run INSIDE Studio with the new `tools/studio_spec.py`; the robloxemu checks could not run at all. So the
publish gate is NOT met for any game: **nothing was published tonight.** Owner: put `luau.exe` back (or approve
the download) and the next night can run the emu gates and publish.

### H. Eye-candy: the 4 live games, steps 1-2 DONE, steps 3-4 BLOCKED
- **plus1-jump** (e442405, d35112e, 47233d0): Studio check (STUDIO.md). Fixed: Treetops/Cloud Sea washed white
  (lighting cap in EnvConfig.spec), blank HUD board (`Board.hudNote`), Redeem freeze, tofu glyphs. Second review
  of 42bc0a6: 1 MEDIUM (guard bound = ideal jump, a fly script climbs ~8x faster), 6 LOW, none fixed.
- **anomaly-observatory** (4fcced1): Studio check; no code change. Review: 2 MEDIUM (client can read the
  hidden spares; no Studio gate on live stores), 4 LOW. Weak visuals: aurora planks, black storm, caption over
  The Other Sky.
- **grow-a-crystal** (237a671, d35112e): blank HUD board fixed; **Redeem server freeze CONFIRMED and fixed**
  (30 000 spaces = 3.1 s of server time; same in plus1-jump). Review: 1 MEDIUM left (no Studio gate), LOWs.
- **labyrint-spill** (47233d0): close-button tofu fixed (✕ U+2715 is not in Gotham; new `tools/check_glyphs.py`,
  also fixed in fork-tower, meteor-drop-tycoon, stormgrow). Review: **1 HIGH** (walk guard is only a time
  floor; wait, then teleport to the exit = an unbeatable record and a board climb), 2 MEDIUM, LOWs.
- Step 3 (thumbnails) blocked: the Studio viewport captures at 1920 x 795, not 16:9. Working screenshots are in
  each game's `marketing/studio-2026-10-09/`. Resume: resize Studio to a 16:9 viewport first.
- Step 4 (publish) blocked: no robloxemu gates; and for labyrint/anomaly the review asks for fixes first.
- **Cross-game, not fixed:** no `RunService:IsStudio()` gate on DataStores in any of the 4 (a Studio session
  with API access on writes to the live boards). A fix is server code that only the emu checks can gate.

### Later the same night (01:20-02:00)
- **Redeem server freeze in FIVE games** (plus1-jump, grow-a-crystal, fork-tower: real exposure; anomaly,
  lost-found: defence in depth): quadratic trim on the raw remote string, 30 000 spaces = 3.1 s of server time.
  Fixed (`Codes.MaxInput = 64`), measured through the real remote: 200 000 chars now 0.08 s. **Live games are
  still exposed until the next publish.**
- **Studio store gate in all 11 games** (`AllowStudio = false` in src; spec asserts it; each verified in real
  Studio by its console line).
- **Tofu glyphs**: `tools/check_glyphs.py` (✕ ☰ ✔ ✖ 🛗 🪙 🪨, measured in Studio from a grid of every symbol and
  emoji the games use); 0 left in the 16 committed games.
- **Blank HUD top-10 panel** fixed in plus1-jump, grow-a-crystal, fork-tower, deep-vein.
- Second reviews done for ALL 11 games (EYECANDY files). Open HIGHs, none fixed: labyrint (delayed teleport to
  the exit), nightwatch (teleport out, wait, back in: completion commit BLOCK), vault-runners (fliers top the
  board, owner call). MEDIUMs open: plus1 guard bound, anomaly readable spares, deep-vein elevator cooldown,
  lock leaks in deep-vein / vault-runners / nightwatch.
- Resume: (1) get a luau CLI and run every robloxemu check; (2) fix the HIGHs; (3) 16:9 thumbnails;
  (4) publish the 4 live games (the Redeem fix is the urgent part).

### F. Playtest rig: DONE (02:10)
The "one press in three" is explained by measurement (tools/playtest.py docstring): anomaly's misses were wrong
calls at Day 1 (counter stays 1), and labyrint's 0.20 s hold prompts need a hold longer than 200 ms. Input
probe added, holds 400 ms, checks accept a move or a Death. 3 consecutive clean runs 7/7 after the last change
(24/24 presses delivered and resolved across 8 runs); a no-op mutant goes 4/7 red. Gate for anomaly.

### End of night status (02:25; stopped early: everything left needs a luau CLI or the owner)
- **H, all 11 games:**
  - Step 1 (Studio): done as a first look. A full look was done for the 4 live games, plus fork-tower and
    deep-vein; every game has a STUDIO.md.
  - Step 2 (second review): done for all 11 and recorded in each EYECANDY.md.
  - Step 3 (thumbnails): +1 Jump and Anomaly candidates were shot at a true 1920x1080
    (`tools/studio_window.py`, docs/thumbnails.md). The Anomaly candidates are too weak to upload; Crystal and
    Labyrinth were not shot.
  - Step 4 (publish): **BLOCKED.** There is no luau CLI, so no robloxemu gate ran.
- **Owner, please:**
  1. Restore `luau.exe`, or approve its download. Then the next night can run every emu check and publish.
     **The Redeem server freeze is LIVE on +1 Jump and Grow a Crystal until then.**
  2. Decide whether fliers may top the Vault Runners board.
- **Next night, in this order:**
  1. Run the emu checks.
  2. Publish plus1-jump and grow-a-crystal (the Redeem fix).
  3. Fix the HIGHs: labyrint (delayed teleport), nightwatch (teleport out and back).
  4. Fix the deep-vein elevator cooldown. walk.luau:827-833 fires down and up in one frame, so adapt that
     check with it.
  5. Fix the lock leaks.
- **Cross-game, seen in every game:** Roblox's chat notice covers the top-left HUD panel for its first seconds
  after join.

### G (Reddit): blocked again
The Chrome extension refuses old.reddit.com ("not allowed due to safety restrictions"). No post.

### Shorts plan
schedule.json has 12 null posts on each of 10-09..10-12 (3 days ahead): no extension needed tonight.

## Daytime run 2026-09-30 / 2026-10-01 (not a night; recorded here so the next night starts right)

Every game was finished against `docs/complete-game-standard.md` and committed (all gates re-run green
before each commit). The night shift was paused by the owner from 2026-10-01 until 2026-10-07 18:00.

- **Done, skip at night:** job A (Anomaly Field Guide board, 3c67595), job E (Vault Runners review,
  REVIEW-5.md, 3c45502), job I (Fork Tower teleport-to-exit, d6ff323), and the plus1-jump night review's
  LOW findings 1-3 (42bc0a6). The plus1-jump branch from 2026-09-27 is merged (810376f).
- **Owner decisions:** taken as "recommended" in every game and recorded in each EYECANDY.md.
- **Completion commits (review these in job H step 2 together with the eye-candy commit):**
  plus1-jump 42bc0a6, labyrint-spill abe3216, grow-a-crystal ad8a823, anomaly-observatory 3c67595,
  fork-tower d6ff323, nightwatch-manor 95ca6c5, deep-vein 6c96b11, vault-runners 3c45502,
  lost-found-depot b30625d, steal-a-cryptid f181968, facility-nightmare 607b079.
- **New games (wave 1), not in Studio, no universe yet:** same-door 54923f2, signal-lost 6db0da4,
  meteor-drop-tycoon 6f91998, stormgrow b3a1d08, escape-room-lab fd4bfa2. `tools/studio_open.ps1` knows them.
- **Still open for job C:** `tools/film_game.py` has scenarios only for plus1, crystal and laby. Each
  game's `MARKETING.md` now lists 5-10 clips with staging; add a scenario table per game before filming.
- **Still open after publishing:** `docs/marketing/store-text.json` holds the old store texts; the new
  ones are in each README ("Store description"), to be pushed with `tools/store_text.py`.
- **Owner's go needed:** downloading luau-analyze / luau-compile (no binary on the machine).

## Night of 2026-10-01 (run started 00:18, stopped at about 00:55, nothing done)

Clock: Bash `date` and PowerShell `Get-Date` both read 00:18 at start.

**Why nothing was done:** `git status --short` showed uncommitted changes I did not make in EVERY game
folder (all 11 existing games plus same-door, signal-lost, meteor-drop-tycoon, stormgrow, escape-room-lab)
and 142 files under `robloxemu/`. Files were still being written at 00:49, so the daytime run from
2026-09-30 (docs/complete-game-standard.md) was active. Per section 3c every game was skipped:
"skipped: daytime run in progress". That covers H, I, A, B, C, D, E. F needs a Studio session on a game
(and could collide with the daytime run's Studio/MCP use), so it was skipped too.

- G (Reddit): blocked. The Chrome extension refused old.reddit.com ("This site is not allowed due to
  safety restrictions"), so the visibility gate for `t3_1wcafbz` could not be checked. No post.
- Shorts plan: schedule.json has 12 posts with `youtube: null` every day 2026-10-01 .. 2026-10-12, so no
  extension needed.
- The plus1-jump resume point from 2026-09-27 (below) still stands, but check first whether the daytime run
  already did the second-review fixes / Studio items for plus1-jump.

## Night of 2026-09-27 (run started 00:17, stopped early)

**Why it stopped early:** mid-run both clocks (Bash `date` and PowerShell `Get-Date`) jumped from about
00:55 to 22:55 on 2026-09-27. The PC most likely slept for about 22 hours while Studio was restarting. 22:55 is
outside the 00:00-06:00 window, so the run stopped at once: no gates re-run, nothing published, nothing
merged to main. The work below is on branch `night/2026-09-27-plus1-sitdrop`, NOT on main.

### H. Eye-candy — plus1-jump: IN PROGRESS

Done:
- Studio opened with `tools/studio_open.ps1 plus1-jump`; MCP attached. Play works; DataStores are
  unavailable in the unpublished place, so nothing was saved (console: "progress will NOT be saved").
- Console on join: only the two expected datastore warnings and the load line. No errors.
- **Real bug found and fixed (test first): the ☕ Rest button did not rest.** In real Studio, pressing Rest
  set `Humanoid.Sit = true` and 20 ms later the rest ended. Heartbeat trace: a Humanoid sat without a seat
  drops onto the floor (root vy -3 .. -26, bounce +9, settled in ~0.3 s), and `Sky.client` counted
  "seated and |vy| >= 2" as falling, so the first frame of the drop woke the rest.
  - Failing check first: `robloxemu/check_plus1jump_sitdrop.luau` replays the measured trace. It failed
    3/6 on the old build, exactly as in Studio.
  - Fix: `Sky.client.luau` treats the first `SIT_SETTLE_SECONDS = 1.0` after the sit as supported
    (`satAt`). A sustained fall while seated still ends the rest (asserted).
  - Now 9/0. Mutations: settle 0 KILLED (6 fails), settle 5.0 KILLED (1 fail), comparison `< -1` KILLED;
    control (comment edit) survived. All proved in the rebuilt bundle.
  - Verified in real Studio after the fix: Sit stays true, the chip says Resting, DoF on, the server sees
    Sit=true (it replicates). Holding W wakes the rest (MoveDirection works while seated).
- Idle rest seen working in Studio: after standing still the chip says `💤 Idle`, and the button offers
  `▶ Climb`; pressing it ends idle rest.
- Second review (step 2) DONE: one independent read-only reviewer on 09c76b6 + 20212cf. It could not
  refute any round-2 fix (ring = zone, slow-load settle, capRates, first-only rebirth highlight). No
  high/medium findings. Four LOW findings, **not fixed yet**:
  1. The ring and banner hide at `arriveAt`, but `checkHit` runs until `duration`; 6-22 of 400 players who
     stepped to a random point inside the ring per kind were hit 0.02-0.15 s after it vanished (they never
     left the ring). Fix: keep the ring drawn until the hazard is out of reach.
  2. A returning climber who rebirthed in an earlier session gets "YOU REACHED SPACE!" again, because the
     announcer is seeded from leaderstats Tier (frontier), not bestTier (Sky.client ~683/692).
  3. Docs: EYECANDY.md still says "default = every rebirth lit" in the header, §1 rows, §2 and §8 item 19,
     contradicting `HighlightFirstRebirths = 1` since 20212cf.
  4. Duplicate FxAtmosphere/FxBloom if the client runs before they replicate; a second DoF next to the
     server's. **Not reproduced in Studio:** Lighting had exactly one of each, and no FxDoF on the client.
- Seen in Studio, not a game bug: with the camera zoomed right in, a seated avatar's camera can end inside
  the translucent tile `P_1_1` (Roblox's camera ignores translucent parts), which tints the top of the screen.

Resume point (next night, in this order):
1. Merge branch `night/2026-09-27-plus1-sitdrop` after running ALL plus1-jump gates (11 specs, every
   `robloxemu/check_plus1*`), with the new `check_plus1jump_sitdrop` added to the list in EYECANDY §7.
2. Fix reviewer findings 1-3 test first (4 only if seen).
3. Studio: the rest of the needs-Studio list in `plus1-jump/EYECANDY.md` §8. Config for shot session A
   (StreamAhead 260, hazard interval 100000) goes into the place only, via the Edit datamodel, never `src/`.
   Bands 2-8, hazards (session B), phone viewport HUD, then write the "Eye-candy" section in
   `plus1-jump/STUDIO.md` with screenshots.
4. Thumbnails (EYECANDY §9), upload per docs/thumbnails.md, then publish (verify versionNumber).

### I, A, B, C, D, E, F, G: not started this night.
