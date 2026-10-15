# CLAUDE.md: Gnome Garden Defense (Roblox)

Context so a fresh session can continue. Built 2026-10-07 from `DESIGN.md` (the design stage's spec, every
number measured with the balance model), to `docs/complete-game-standard.md`. Layout copies `deep-vein/`.

## What it is
A one-bed-per-player tower defence. Each of 8 players owns a garden slot; a procedurally drawn 30-cell path
runs from the hedge gap to the carrot patch; waves of insects walk it. The camera is the game's own garden view
(the whole garden; on a phone it zooms where a pad is tapped). Tap a glowing pad, plant a gnome
(Pebble, Sprinkler, Mushroom, Lantern), gnomes fire on their own, stopped bugs pay seeds, seeds plant or
upgrade. Ten waves make a season; the tenth brings a boss that eats all 20 carrots if it gets through. A loss
retries the season on a fresh bed; a win unlocks the next gnome. Spring, Summer, Autumn (the Slug Queen under
the HARVEST MOON: the brag, normal median 33.6 min), Frost (the Frost Mantis, 57.4 min), then the endless
Moonlit Bed, the same bed for everyone each UTC day, ranked by the highest wave survived. Nothing costs Robux.

## State
- v1 built 2026-10-07; REVIEW-1 (two adversarial reviews, 15 findings) closed the same day: see `REVIEW-1.md`
  for every finding, the mutation table and the final gate counts. NOT published, no universe, never opened in
  Studio. Everything Studio must settle is in EYECANDY.md section 7 (23 items since REVIEW-2).
- Later the same evening the build's own pass (REVIEW-1.md "After the reviews") closed two more defects found by
  walking past the brag (B1: a Frost gardener's join replayed the HARVEST MOON brag; B2: a boss with a sliver of
  health named the next band while it still walked) with `check_gnomegardendefense_frost` and a Garden.spec case,
  and made reach section 4 meet the server's once-a-second poll at ten phases (its PAUSE mutant had survived).
- REVIEW-2 (two more adversarial reviews, 11 findings: 3 exploit, 8 reach) closed on 2026-10-08: "Round 2" at the
  top of `REVIEW-1.md` (code comments say REVIEW-2): no server poll of the character (a shove resumed a pause and ended the AFK hold; "here" is now the
  gardener's own input, the client's `Here`), gardeners do not collide, one fallback endless bed per day, the
  board prompt's toggle cooldown, on a phone the first tap zooms and the pick is drawn gold, no pad under the
  thumbstick's frame or the jump button (`GardenCam.fitClear`), the starred gnome and its three best pads glow all game (the
  pacing model's normal player is exactly that player), a late restore celebrates nothing, the season's card and
  the band's share one card and one flash, PAUSE while walking says "stand still". Console must be OFF at publish
  (no gamepad path). EYECANDY.md §7 now has 23 needs-Studio items.
- The luau CLI is still MISSING on this machine (its scratchpad folder is empty; fetching a binary needs the
  owner's permission). Every gate ran on `scratchpad/ggd/luaushim/`: a Luau-to-Lua 5.1 transpiler on OBS's
  LuaJIT 2.1 (`lua51.dll`), validated by reproducing other games' suites. **First job when the real CLI is back:
  re-run every gate below with `luau`, and run `luau-analyze` over src/ (never done).** Known differences:
  LuaJIT seeds its string hashes per process (a table iterated by string key changes order between runs), and
  its `pow` may differ in the last bit.

## Files
- Server `src/server/Main.server.luau`: slots, the bed, the 0.1 s sim loop, requests, saves, the board.
- Client `src/client/Hud.client.luau` (top bar, READY, gnome sheet, result panel, hints, toasts; it publishes the
  screen left free for the world in GardenClientState), `src/client/Garden.client.luau` (bands, bugs, hazards,
  PAUSE, the chip row), `src/client/View.client.luau` (the garden view: the camera, a tap -> a pad, the zoom, the
  hazard zoom, the sky look, the board view; REVIEW-1), `src/client/Board.client.luau`.
- Shared pure modules (tested): `Config` (every number), `Garden` (the sim; `suggestKind`: the starred gnome),
  `PathGen` (beds; `bestPads`: the pads that glow), `Waves`,
  `Wire` (packed bug snapshots), `GardenCam` (the view's projection, fit, zoom and tap pick; REVIEW-1); templates `EnvBands`, `Rest`, `Board`, `Responsive`, `Fx`, `FxClient` (+1 Jump,
  verbatim), `Rng` (fork-tower, verbatim), `Hazards` (Deep Vein's + +1 Jump's `threatLive`); art `GardenArt`.
- `tests/GardenModel.luau`: the player profiles (weak/normal/strong) playing the REAL `Garden`/`PathGen`/`Waves`.
  `tests/Pacing.spec.luau` gates the balance; `WaveTable.luau` and `BandMinutes.luau` are reports.
- `tests/Tap.luau`: a finger on the screen for the walk and the checks (the current camera, an independent
  projection, a TouchTap). `tests/project_spec.py`: the project file pins StreamingEnabled = false.
- `DESIGN.md` (the spec), `EYECANDY.md`, `MARKETING.md`, `README.md` (store text), `REVIEW-1.md`.

## Gates (rebuild the bundle first, every time)
```
cd robloxemu && py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
# specs, from gnome-garden-defense/ (14 files): Board Economy EnvBands EnvConfig Garden GardenCam Hazards Pacing
luau tests/<X>.spec.luau            # PathGen Responsive Rest Rng Waves Wire: all "N passed, 0 failed"
py -3 tests/project_spec.py         # the project file: "project: 6 passed, 0 failed"
luau tests/walk.luau                # the player's path, finger taps through the garden view: "WALK: 22 passed"
luau tests/WaveTable.luau -a normal # report (DESIGN.md §5.2); tests/BandMinutes.luau: report (EYECANDY.md §2)
# headless, from robloxemu/ (11 checks; counts in REVIEW-1.md):
luau check_gnomegardendefense.luau        # world, spawn, pads, board, core loop, a real spring win, rejoin
luau check_gnomegardendefense_save.luau   # session lock, board store, day's bed, AFK hold, rate limit
luau check_gnomegardendefense_store.luau  # REVIEW-1's store findings on YIELDING stores (retry, leave mid-load,
                                          # leave mid-draw, the win saved off the sim thread, the toast flood)
luau check_gnomegardendefense_daily.luau  # the day's endless bed when its store blips or is down
luau check_gnomegardendefense_env.luau    # bands, budgets, bugs cap, hazards + ring, PAUSE, daze
luau check_gnomegardendefense_hud.luau    # PASS: 16 viewports x 3 modes, overlap = true
luau check_gnomegardendefense_reach.luau  # the garden view on a phone: every pad in two taps, late bed, PAUSE
                                          # after a walk, the meadow, the board view, the hazard zoom, desktop
luau check_gnomegardendefense_brag.luau   # autumn played for real: a loss to the Queen shows no moon, the win does
luau check_gnomegardendefense_frost.luau  # a Frost join (2 s load) celebrates nothing; Frost played for real to the
                                          # Mantis; NEXT to the endless bed (the day's bed); wave 41 saved + on the board
luau check_gnomegardendefense_grief.luau  # REVIEW-2: shoves resume no pause and end no AFK hold, gardeners do not
                                          # collide, Here is the gardener's own input, the board prompt cannot echo
luau check_gnomegardendefense_restore.luau # REVIEW-2: a save restored late (first read failed) celebrates nothing
luau-analyze src/                         # NOT RUN: no binary on this machine (docs/new-game-checklist.md §5)
```
Until the CLI is back, `luau` = `py -3 <scratchpad>/ggd/luaushim/luaurun.py` (args after `-a`).
Most checks play server-random beds: run them several times (REVIEW-1 ran each randomized gate 16 times).

## Traps this game has
- **A move of the character is not the gardener's input** (REVIEW-2). The server never polls positions: a
  neighbour's shove, a fling or a hazard's knock moved the character and resumed a pause or ended the AFK hold.
  "Here" is the client's report of its own thumbstick, keys and taps (`Here`, at most every 5 s), a pause ends by
  the client's wake, the button or a garden action, and SetPaused's cooldown never refuses a resume.
- **On a phone the first tap on a small cell only zooms** (REVIEW-2). A test or a clip taps twice, and decides
  to tap again by the pad drawn GOLD (what a player sees), never the hidden SelectedPad attribute. A check that
  taps for minutes PAUSES the garden first, or the wave it started is lost meanwhile and the HUD stops picking.
- **The glow and the star ARE the pacing model's normal player** (REVIEW-2): `Garden.suggestKind` with
  `Config.Suggest`, `PathGen.bestPads` with `Config.Glow`. Change either and re-run Pacing.spec: its brag minutes
  assume a player who plants the starred gnome on a glowing pad.
- **A new bed is never a reach** (REVIEW-2): the first progress of EVERY attempt is named quietly (a save restored
  late re-digs the bed at Frost's 30). The server publishes `Attempt` before `Progress`.
- **A season's win and the band it reaches arrive together**: one card (the band joins the season's line), one
  flash. A check that records cards must record a changed line under the same title too (check_frost).
- **The whole-garden view keeps pads out of the touch controls** (`GardenCam.fitClear`, 4 px margin): the
  thumbstick's frame as REVIEW-2 recalled Roblox's DynamicThumbstick (`Config.Hud.StickW/StickH`: left 40% of the
  lower 2/3, unverified: EYECANDY.md §7, 20) and the jump button's corner of the band (`JumpShare`); the deck and
  the board may lie there. So the garden sits right of centre on a phone.
- **While the day's store is down a server has ONE bed of its own for the day** (a new one per ask was a reroll).
- **The first sight of the garden's progress is not a reach.** Frost's bed starts at Progress 30, the HARVEST
  MOON's band: the band announcer must be primed QUIETLY on the first published Progress (a quiet card, no flash,
  no sky look), and not before the bed is dug (the profile load leaves the garden without Progress for seconds).
- **An unfinished wave never reaches its boundary** (`Config.ProgressInWaveMax` = 0.999 in `Garden.progress`).
  The server publishes 3 decimals: a boss at 1% health rounded up onto the boundary and named the next band (the
  moon for a Queen sliver) while it still walked, and one Frost run then lost that wave.
- **A test of a once-a-second poll must meet the poll at every phase**: reach section 4's series b lasts 3.7 s a
  try, so ten tries are ten phases. Its first version passed the PAUSE mutant whenever the phase was lucky.
- **A shared module never `require`s by string.** `Garden.new(cfg, chapter, path, deps)` takes
  `{ Waves, PathGen }` and the garden keeps them; `GardenArt.new(folder, rand, deps)` likewise.
- **GardenArt must load in the CLI** (EnvConfig.spec requires it): nothing Roblox-only at module load; colours
  are `{r,g,b}` and shapes/materials are looked up inside functions.
- **Sum floats in a fixed order.** `Waves.wave` summed the mix weights in table order; on a runtime whose
  string hashes are seeded per process, wave 6's last two bugs swapped between runs. It sums in name order now.
- **The NAMED band goes by the server's exact Progress; only the LOOK is smoothed.** An `approach` never
  arrives, so a smoothed 29.985 was never "in" the Harvest Moon and the brag card never showed.
- **The client cannot see whose tick it is.** In the emulator (and in any test) `FireClient` reaches every
  listener: every GardenTick/Fanfare/Board payload carries the owner (`o` / `viewer`) and the attempt (`a`),
  and the clients drop anything else.
- **Time is `tick()` on the server**, not `os.clock()` (CPU time barely moves headless: the rate limit and the
  AFK hold could not be tested).
- **Spawn order** (robloxemu/SPAWN-ORDER.md): `plr.RespawnLocation = spawn` is set before the load yields;
  `CharacterAdded` writes no CFrame. Leaving destroys the seat (slot folder, spawn, info) FIRST, then saves.
- **Every yield in onPlayerAdded can outlive the player** (the profile load, the endless chapter's day's-bed
  draw): after each one, check the player is still seated, give back a lock taken meanwhile, build nothing.
- **A session that could not take the record keeps trying** (2, 4, 8, 10, 10 ... s) and never writes before it
  has READ the real record; when it gets the lock it merges (the higher chapter and best wave) and saves.
- **Saves are serialised per player** (`p.saving`), and nothing writes after the leave released the lock. The
  season's win save runs on its own thread: a DataStore call inside the 0.1 s sim loop froze every garden.
- **robloxemu fires PlayerRemoving on the caller's thread:** a check whose stores yield must call `h:leave` from
  a thread of its own (check_gnomegardendefense_store's `leave`), or the save's yield errors.
- **The camera is the game's:** `View.client` sets CameraType Scriptable and writes the CFrame every frame. A
  capture rig or cutscene sets the camera attribute `ExternalCamera = true` to get it (film_game.py must).
- **Pads have no ClickDetector:** a tap is picked from the PathCells attribute (no pad Instance needed) and handed
  to the HUD as GardenClientState.PickPad/PickSeq. A test taps through `tests/Tap.luau`, never MouseClick.
- **Progress counts bugs STOPPED, not bugs gone:** a leaked boss put a lost season on the next band's boundary
  and played the HARVEST MOON for a loss.
- **Line endings are mixed** (git core.autocrlf=true; the builder's verbatim copies are CRLF): match a file's own
  line ending when patching it from a script.
- **A step resumes a pause, counted from the press.** The server polls the character every second; SetPaused(true)
  re-bases the poll's position, or a walk that ended just before the tap undid the pause (REVIEW-1: 3 of 10).
- **Hazards run on garden time only**: phases build/wave, not paused, not resting, and a band with hazard kinds
  (band 1 has none). The clock is frozen, never reset, so the first hazard after a band sweep comes early.
- **Short phones**: when the rows under the top bar leave no room above Roblox's touch controls, READY and the
  gnome sheet move into the bottom band's middle and READY steps aside while the sheet is open
  (check_gnomegardendefense_hud: 568x320 and 640x300).
- **Boss hit points are the most sensitive numbers** (DESIGN.md §5.3): +-10% on the Slug Queen moves the normal
  first-try win rate between 95% and 43%. Retune them first from live data; re-run Pacing.spec after.
