# CLAUDE.md — Lost & Found Depot (Roblox)

Context so a fresh session can continue. Sibling of `deep-vein/`, `fork-tower/`, `grow-a-crystal/`
and the rest; same stack (one Config, pure logic in `src/shared` tested from the luau CLI, an
authoritative server, a phone-first HUD, `robloxemu` headless gates). Built from `DESIGN.md` (read it
first: every number in it carries its source). Build pass 1: 2026-09-16. REVIEW-1 findings fixed in
build pass 2: 2026-09-17. The second review round's nine findings (E1-E3, U1-U6) fixed in pass 3 the same
day: **`REVIEW-1.md`** has each finding, its before/after numbers, the mutation table and what is open.
**The wings (owner's brief 2026-09-17, built 2026-09-23/24): `EYECANDY.md`** — six wings driven by the
career, rare client-side hazards on the sorting floor, a BREAK between shifts, budgets, the gates, the
Studio list and the thumbnail shot list. Read it before touching anything under "wings" below. The wings'
adversarial review (REVIEW-2, six findings, all fixed test first the same day) is `EYECANDY.md` §13.

## What it is
A solo sorting job. A private bay per player: a tray of 8 tagged lost items, six bins on an arc.
Tap an item, read its tag (`T · 3 · RED`) against the Depot Manual (RED route -> CLAIMS, condition
5 -> REPAIR, otherwise the letter picks the bin), walk it to the bin, press E (tap Drop on a phone). 30 items against a
330 s clock that starts at the first pickup; a wrong bin costs 8 s. Torn tags (and the catalog that
resolves a torn letter) from career shift 2, a rule-bending memo from shift 3. Cash buys cart (carry
2-5) and shoes (walk 16-22) at the locker. 500 first-try sorts open the Back Room. Nothing costs Robux.

## State — every headless gate green; NEVER OPENED IN STUDIO; NOT published; NOT committed
Last run of every gate, on the final source (2026-09-24, after the wings and the REVIEW-2 fixes). `luau` is the luau CLI; it
writes to stderr, so ALWAYS append `2>&1`. The wings' own gates are listed after the original ones.

| gate | command | result |
|---|---|---|
| Codes | `luau tests/Codes.spec.luau` | 16 passed, 0 failed |
| Economy | `luau tests/Economy.spec.luau` | 157 passed, 0 failed |
| Layout | `luau tests/Layout.spec.luau` | 32 passed, 0 failed |
| Rng | `luau tests/Rng.spec.luau` (verbatim copy of fork-tower's; `Rng.luau` is byte-identical) | 32 passed, 0 failed |
| Rules | `luau tests/Rules.spec.luau` | 95 passed, 0 failed |
| Seed | `luau tests/Seed.spec.luau` | 24 passed, 0 failed |
| Shift | `luau tests/Shift.spec.luau` | 79 passed, 0 failed |
| responsive | `luau tests/responsive.spec.luau` (copied verbatim) | 70 passed, 0 failed |
| the walk | `luau tests/walk.luau` | 48 passed, 0 failed |
| world + play | `cd ../robloxemu && luau check_lostfounddepot.luau` | 238 passed, 0 failed |
| spawn order | `cd ../robloxemu && luau check_lostfounddepot_spawn.luau` | 29 passed, 0 failed |
| saving with a slow store, and client spam | `cd ../robloxemu && luau check_lostfounddepot_save.luau` | 111 passed, 0 failed |
| HUD flows on a phone | `cd ../robloxemu && luau check_lostfounddepot_hudflow.luau` | 44 passed, 0 failed |
| taps and sightlines | `cd ../robloxemu && luau check_lostfounddepot_view.luau` | 17 passed, 0 failed |
| HUD fit | `cd ../robloxemu && luau check_lostfounddepot_hud.luau` | PASS, 60 viewport x mode measurements |
| what a client can predict | `cd ../robloxemu && luau check_lostfounddepot_rng.luau` | 24 passed, 0 failed |
| the first minute, and what E drops | `cd ../robloxemu && luau check_lostfounddepot_firstmin.luau` | 67 passed, 0 failed |
| the wings' pure rules | `luau tests/Wings.spec.luau` | 256 passed, 0 failed |
| the wings' config | `luau tests/EnvConfig.spec.luau` | 268 passed, 0 failed |
| minutes to each wing, hazard rarity | `luau tests/Pacing.spec.luau` | 115 passed, 0 failed |
| the HUD -> wings hand-off | `luau tests/StateCache.spec.luau` | 10 passed, 0 failed |
| template (verbatim from +1 Jump) | `luau tests/EnvBands.spec.luau`, `Hazards.spec.luau`, `Rest.spec.luau` | 124 / 102 / 55 passed, 0 failed |
| the wings through the real client | `cd ../robloxemu && luau check_lostfounddepot_wings.luau` | 217 passed, 0 failed |
| taps and sightlines with every wing built | `cd ../robloxemu && luau check_lostfounddepot_wingview.luau` | 66 passed, 0 failed |
| HUD + wings on every viewport | `cd ../robloxemu && luau check_lostfounddepot_hud_wings.luau` | PASS (hudcheck, 10 modes) + PASS (the HUD's text rows, the title card on 10 viewports, no launch under a phone drawer or a card) |
| syntax | `cd ../robloxemu && luau check_lostfounddepot_compile.luau` (loadstring over every bundled source; no `require` by string) | 21 sources, 42 passed, 0 failed |
| analysis | `luau-analyze` | **NOT RUN on the wings**: luau-compile.exe and luau-analyze.exe were wiped from this machine on 2026-09-23 (luau.exe survived). The 2026-09-17 run was 14 clean. |

**Rebuild the bundle before every headless run**, or you are testing the last build, not the source:
`cd ../robloxemu && py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau`.
The walk and all twelve `check_lostfounddepot*` files read `robloxemu/build/lost-found-depot.luau`.

### What the walk showed (numbers from the last run)
A new player on an 800x360 touch viewport, the real HUD running, every tap on the item's own
ClickDetector:
- lands 0.00 studs (xz) from their own pad centre at y 3.51 (the engine's placement via RespawnLocation);
- taps the Teddy Bear from the pad, 6.41 studs away, then the Phone too, 6.41 studs away, no step;
  the Teddy (picked first) stays selected and the hint follows it: `T means TOYS. Walk to the TOYS bin
  and tap Drop.`; the TOYS Drop prompt reads `Drop Teddy Bear`;
- walks 34.0 studs to TOYS, Drop: +11, 0 misfiles; the hint moves to the Phone (`Read the TAG, not the
  phone: K means KEYS & WALLETS. Walk to that bin and tap Drop.`); walks 23.0 studs to KEYS & WALLETS:
  +12, 0 misfiles, toast `Tags beat looks. The rest is up to you - every rule is in MANUAL.`;
- loop 1 (stage 1, carry 2): 30/30, 0 misfiles, Perfect, 70.3 s from first pick to summary, 15 trips,
  30 picks, 1036 studs; pay 655 (555 + 100), matching the pay rule over the real deposit sequence;
- buys the cart at the locker (655 -> 405, carry 3); UPGRADES shows `carry 3 -> 4 for 800`;
- loop 2 (stage 2): the MANUAL drawer opens itself with 9 lines marked NEW (4 torn-tag lines, the
  CATALOG heading, 4 catalog lines); 3 torn tags on the opening tray; 30/30 with 1 deliberate misfile
  (toast `-8 s. Keyring: K goes to KEYS & WALLETS.`), 29 first tries + 1 re-sort, Perfect, 63.7 s, 11
  trips, 31 picks, carried at most 3, 980 studs;
- ends with cash 1045, backlog 59 / 500, 2 shifts, 2 Perfects, best 63 s, 2037 studs walked.

Durations are LOWER BOUNDS on a human's: zero reading time, instant presses, straight-line walking at
exactly WalkSpeed (routed round the tray's ends). Not the model's player-profile numbers.

## How the checks derive answers (why green means something here)
There is no server-side answer table for a test to read (DESIGN.md §8.2). The checks and the walk
read the RENDERED tag text, the RENDERED memo board and the RENDERED bin signs, run the public
`Rules.resolve`, walk to the bin whose sign names the answer, and press E. 30/30 with zero misfiles
therefore proves the visible information is sufficient.

## REVIEW-1: what it found, what changed, what proves it
REVIEW-1 (two reviewers, scratch repros only, no file in the repo) found the defects below. Every one
was reproduced against the build-1 source before anything was changed, turned into a failing assertion,
watched fail, then fixed. The reviewers' own repro scripts were re-run on the fixed bundle and agree.

| finding | defect (measured on build 1) | fix | proven by |
|---|---|---|---|
| R1-1 | an autosave that fired during the leave-time release re-locked the record: 12 of 12 leavers came back read-only | `leaving` set before any yield; a write re-checks it inside its transform; one write per session at a time (the release waits) | `_save` R1-1 (3 scenarios) |
| R1-2 | the bay was freed only after the release save returned; a newcomer in that window got no bay, forever | the bay is freed synchronously at the head of PlayerRemoving | `_save` R1-2 |
| R1-3 | one load error dropped a veteran (1000 cash, 7 shifts) into the tutorial with 0 cash, read-only | the load is tried 3 times (1 s, 2 s apart); a session that still fails plays read-only and merges later | `_save` R1-3 |
| R2-6 | a session that did not get the lock at join (a crashed server's lock, a rejoin during the first load) stayed read-only all session; nothing it earned was written | every autosave tries to take the lock; a session that did not hold it writes its OWN DELTA on top of the record (`Economy.merge`) | `_save` R2-6, `Economy.spec` merge |
| R1-4 | 100 door presses = 100 DataStore writes + 100 note payloads | the ending is written once, when first seen; the note re-sends at most once per 3 s; a press inside the cooldown gets a toast | `_save` R1-4, main check ending |
| R1-5 | 10,000 Select events = 9,999 State payloads (14.4 MB) | the selection applies at once; its State push is rate-limited to one per 0.1 s with a trailing push | `_save` R1-5 (sent 1 in the reviewer's repro) |
| timeup | a deposit 0.01 s after zero (before the 0.25 s poll) paid +11 | every handler's `admit` ends a shift whose clock has passed zero | `_save` deposit after zero |
| shift end | a shift that timed out 0.6 s after the player left was saved as played | freeing the bay at the head of PlayerRemoving discards it | `_save` shift after leaving |
| R2-2 | tapping the Teddy then the Phone left the Phone selected while the hint said TOYS: the tutorial's own instruction was a misfile | the tutorial step FOLLOWS THE SELECTION: `sort` names only the selected item, `select` asks for a hotbar tap first | main check invariant over every shift-1 payload, `_hudflow`, the walk |
| R2-4 | the note set the camera Scriptable; closing it any way but CLOSE (a toggle, a shift summary) left it stuck into the next shift | whatever replaces the note gives the camera back and cancels the tween | `_hudflow` R2-4 |
| R2-5 | on a phone an open MANUAL drawer hid every toast (refusals and misfile explanations were invisible); the self-opened drawer kept the hotbar hidden into the shift | the toast keeps its own row above the drawer; the drawer the HUD opened closes at the first pickup | `_hudflow` R2-5 |
| R2-7 | the manual said "see the catalog" and no catalog existed anywhere | layer 2 of the manual carries a CATALOG, built from `Config.Catalog` (board and drawer) | `Rules.spec`, main check stage-2 board |
| 6 | invisible 3.5 x 3 x 2.5 slot hitboxes stood above the other row: a tap on a visible item reached it 28.0% (back row from the bins), 0.0% (front row from the pad); the tutorial Phone 2.4% from the bin side | the item's own pieces are the tap target (ClickDetector on the item Model) plus a 2 x 0.1 x 2 tile on the tray surface | `_view`: 100.0 / 100.0 / 99.4 / 100.0% (re-measured on the final source: 3169 of 3187), Phone 100% both sides |
| 8, 13 | the opaque memo board and each bin's sign board blocked tags, signs and the door from behind: 3288 blocked sightlines | boards are ONE-SIDED: an invisible Part whose SurfaceGui draws an opaque background on its face | `_view`: 0 of 7224 |

### REVIEW-1 pass 3 (second review round) — full detail, numbers and mutations in `REVIEW-1.md`

| finding | defect (measured on pass 2) | fix | proven by |
|---|---|---|---|
| E1 | 10,000 pick + put-back pairs in one frame = 20,000 State payloads (17.89 MB), 80,000 Instance.new; 10,000 refusals = 10,000 toasts | per-player action bucket (`Config.Remotes.ActionBurst` 10, `ActionsPerSecond` 5) spent right before each state change; refusal/info toasts deduped (same text within 0.05 s) and bucketed (6, 3/s) | `_save` E1: 10 payloads, 40 Instances, 2 toasts |
| E2 | a server hop: the stale read-only session bought on cash already spent; the merge floored cash at 0 and kept the upgrades (2100 worth for 1050) | a session that is not saving cannot buy; `Economy.merge` re-prices purchases at the level they land on and undoes what the store cannot cover; a merge adopted live re-applies walk speed | `_save` E2, `Economy.spec` E2 |
| E3 | the tray pins the 32-bit seed (18 s brute force); that seed predicted the 22-item cart, and its salt every later shift | a fresh salt per SHIFT; the cart from two more server keys (`Seed.cartSeeds`, per-item streams in `Shift.generate`) | `_rng`: 0 of 66 cart items, 0 of 2 next seeds |
| U1 | a misfiled/put-back tutorial Phone went to the cart: no TAP HERE, and a lookalike Phone on the tray (32% of first shifts) | a returned item always goes on the tray (bumping the newest roll-in); career shift 1 draws no Teddy Bear or Phone but the tutorial's | `_firstmin` A1/A2b/B, `Shift.spec` U1 |
| U2 | nothing said which item E drops; a first-picked-first player misfiled 36% at carry 2 | a pick keeps the selection (the first hotbar slot); Drop and Put back prompts name the item and its tag; the misfile toast names the item | `_firstmin` A3/B |
| U3 | "a misfile goes back to the tray" was false with a full tray (8 of 24) | U1's placement rule | `_firstmin` A2: 0 of 21 |
| U4 | a phone was told "press E" / "PRESS E HERE" | touch wording from `layout.controlPad`: "tap Drop" / "DROP HERE" | `_firstmin` B, walk, `_hudflow` |
| U5 | tray tags covered ~42% of the memo board; the board also hid the name sign (140 camera checks) | memo board on the right wall, facing the arc | `_view`: 0.0% worst, 0 blocked |
| U6 | no deposit stamp, bin light pulse or MANUAL pulse | "FILED" stamp, client-side bin light tween, MANUAL stroke pulse on the `tutorial` toast | `_firstmin` B |

Also found and fixed in pass 2 by writing the tests above (not in REVIEW-1): the first version of
the new write path snapshotted the profile before the request left, so an older snapshot that landed
last put old data back: an autosave in flight when a shift ended wrote 1011 over another server's
5011. The snapshot is now taken inside the transform (`_save` out-of-order writes).

## Traps — this game's, and the repo's that bit here
- **robloxemu models only `src/shared` as ModuleScripts.** `src/server/Secret.luau` becomes a
  ModuleScript in ServerScriptService under Rojo; every check and the walk register server modules
  into the harness before running the server. Do not "fix" this by moving Secret to `src/shared`:
  that is mutation M8, and it leaks the ending.
- **The emulator fires PlayerAdded / PlayerRemoving INLINE; Roblox runs them on their own threads.**
  The load and the release retry with `task.wait`, which is correct in Roblox. A harness script that
  calls `h:join` / `h:leave` from the main thread while a DataStore failure is injected dies with
  `thread yielded unexpectedly`. Spawn them: `h.scheduler:spawn(function() h:join(...) end)`, as
  `check_lostfounddepot_save.luau` does.
- **robloxemu's DataStore answers instantly and raises BEFORE writing.** Every save defect REVIEW-1
  found lives in the time a request is in flight. `check_lostfounddepot_save.luau` wraps UpdateAsync
  with per-request latency and a "landed, then raised" mode; new persistence code needs a scenario
  there, not in the main check.
- **Lock expiry uses real `os.time`.** Tests expire a lock by rewriting `expires` in the store.
- **The per-SHIFT salt and the cart keys make every run a different depot.** The checks and the walk
  pin them by wrapping the global `Random` BEFORE the server runs. Seeded `Random.new(n)` passes
  through. Each shift calls `Random.new()` twice (salt; cart keys): a wrapper that hands every unseeded
  call the SAME seed (the walk's `31337`, the exploit reviewer's `rev_rng.luau`) makes consecutive
  salts identical and the next shift predictable, which Roblox's own seeding does not. A check about
  predictability must pin each call differently (`_rng` does).
- **Luau resolves `Instance.new`, `print` and other global paths ONCE, when a script loads.** A test
  wrapper installed after `tryRun` is never called; install counters before the server boots.
- **robloxemu hands a FireClient payload to EVERY client handler**, whoever it was addressed to. A HUD
  assertion needs a server where the HUD's player is the only one acting (`_firstmin` Part B).
- **The action bucket refuses bursts.** A test bot that fires more than 10 picks/put-backs/deposits/
  purchases in one frame, or loops refused actions without advancing the clock, gets "Slow down" and
  can spin forever (the reviewer's `rev_tele.luau` did). Advance at least a frame per attempt.
- **SPAWN ORDER** (`robloxemu/SPAWN-ORDER.md`): `plr.RespawnLocation = <own BayPad>` is the FIRST
  thing in PlayerAdded; CharacterAdded waits (bounded, 300 frames) for `char.Parent`, re-reads the
  bay, and re-places the root part if it is not inside the bay. Every pad starts disabled; the Break
  Room's `StaffEntrance` is the one always-enabled spawn. The re-place alone is load-bearing for a
  player present before the script runs (Studio play-solo); `_spawn` covers it.
- **Tutorial items are found by the slot the payload names, never by name.** A random item on the
  same tray can also be a Phone or a Teddy Bear; a check that picked "the first Phone" was wrong in
  pass 2 and was fixed.
- **A misfile, a put-back or a reset ALWAYS puts the item on the tray** (REVIEW-1 pass 3, U1/U3): the
  first free slot, else the slot of the newest roll-in from the cart, which goes back to the front of
  the cart. Tutorial items are never bumped; an item that itself came back is bumped last. (Until pass
  3 a full tray sent the returned item to the front of the cart.)
- **Selection: a pick does NOT move it** (pass 3, U2). E drops `carried[selected]`, which is 1 unless the
  player taps another hotbar slot; a deposit or a put-back resets it to 1. DESIGN.md §5.1 says a pick
  selects the new item; that is superseded. Every Drop prompt and Put back name that item and tag.
- **Refill is 0.3 s after a pick (`Config.Shift.RefillSeconds`)**, so a double click cannot carry an
  item AND its replacement (M10). A second click of the same tap within 0.05 s is answered by the first
  and gets no refusal toast (N21): a tap can reach both the item's and the tile's ClickDetector.
- **Attribute allowlist: EMPTY. State payload: a key-path allowlist** in the main check. Adding a
  field to `stateFor` means adding it to that list, saying why it is public (pass 2 added
  `shift.tutorial.hotbar`).
- **Nothing decorative collides.** Every collidable Part in a bay is a named shell Part or fixture,
  and no fixture top is above 6 studs (walls 16, jump 7.2).
- **Boards are one-sided and invisible Parts.** A new board goes through `board()`; the view check
  asserts every read board faces its reader, so a flipped `Face` fails (N20).
- **Glyphs:** ASCII, Latin-1 (`·` U+00B7), and only U+2014, U+2026, U+2605, U+1F512, U+FE0F.
- **The HUD reads `layout.controlPad`, not the device.** hudcheck's overlap rule only compares
  depth-2 Frames, so a TextLabel (the toast) covered by a drawer is invisible to it:
  `check_lostfounddepot_hudflow.luau` measures that one directly.
- `require("./X")` appears only in `tests/` (CLI). Roblox sources use
  `require(ReplicatedStorage:WaitForChild("X"))`; shared modules take dependencies as arguments.

### Traps — the wings (EYECANDY.md)
- **The HUD is the ONLY listener on the State remote.** Roblox hands an event queued before any client
  listener to the FIRST connection, and the loaded profile is pushed at join, usually before a phone runs
  its LocalScripts. `Hud.client` passes every payload to `StateCache.set`; `Wings.client` polls
  `StateCache.get` each frame. Never add a second `OnClientEvent` on State; `_wings` asserts it.
- **The wings are client-only and the server never hears of them.** No remote, no attribute, nothing in a
  bay; everything under `workspace.DepotWings`, the `DepotWings` ScreenGui, and `DepotSky` /
  `DepotBreakFocus` in Lighting (the server's `Fx*` effects are taken over by name). `_wings` §9 checks a
  creation log of every Instance the wings made, and a source scan.
- **The knock is `Wings.checkHit`, never `Hazards.checkHit`** (REVIEW-2 finding 1): a hit needs the player a full
  `MinReactSeconds` inside the red ring (from red, or from stepping in) and `MinWarnSeconds` of warning, by
  construction. Call it every frame while a hazard flies: it tracks the time in the ring on the plan. The
  promise (1 s, 2 s) is pinned as LITERALS in `Pacing.spec`, `_wings` and `EnvConfig.spec` (finding 6): never
  compare a measurement against Config's own value.
- **A due hazard waits while the screen is covered** (`Wings.mayLaunch`): a phone's HUD drawer or card, or the
  wing's title card. It stays due; the clock is not touched. A hazard already flying when a drawer opens keeps
  its warning, placed below the drawer (finding 2).
- **A ray from inside a fixture's margin** stops where it would enter the fixture (`rayToObstacle`, finding 3);
  boxes carry their margin (`m`). Do not go back to "a ray that starts inside a box ignores it".
- **Every frame step of `Wings.client` has its own guard, the stumble's release FIRST** (finding 4). A new step
  goes in its own `guard(...)`; set `knockUntil` before anything that can fail after a knock.
- **Tried and rejected for finding 1, measured** (EYECANDY §13): launching only at a player standing still
  (a still sorter faces the tray or a crate: 0 hazards), and locking by closing speed (near-hits fell to one
  per 4.2 min). Do not re-try them without new data.
- **Nothing may ever pause the shift clock.** The BREAK starts only while the clock is NOT running, books
  itself when pressed mid-shift, and ends at the first pickup; idle pauses hazards only. Hazards run on the
  RUNNING clock only and `Wings.endWithShift` removes one still flying when the clock stops.
- **Overhead scenery must sit at or above `Config.Env.OverheadFade.Gone` (16).** The roof fades with the
  camera's height; a part below Gone could be seen from below by a camera looking down at a tag. `_wings`
  §5 measures the lowest overhead part (16.2 today, the train shed's feet on the walls).
- **Budgets assume at most two wings blend at once** (`Wings.keepStrongest`): keep it, or a flurry of career
  jumps stacks 3+ wings of scenery (223 parts before it existed).
- **The headless checks must fire `RunService.RenderStepped` themselves**: the harness never does, and the
  wings draw from it. hudcheck does not either; `_hud_wings` runs a second of frames in every mode.
- **Hazard settings in the checks are overridden IN MEMORY** (6-7 s, 1-2 s, 40-41 s intervals), before the
  client loads, because the scheduler rolls its first interval at load.
- **Some sources have CRLF line endings, some LF** (CRLF: `Wings.client`, `Config`, `Wings`, `WingArt`,
  `Wings.spec`, `EnvConfig.spec`). A textual patch or mutation must match the file's own line endings (the
  sweep normalises them); a Python rewrite that reads text mode and writes `newline='
'` silently turns a
  CRLF file into LF (it happened in REVIEW-2's fixes and was put back).

## Corrections to DESIGN.md found while building (DESIGN.md itself was not edited)
1. §4.1 "the farthest any bin stand point gets from any tray slot is 31.5": over every pair it is
   **32.93**; `Layout.spec` asserts it. The conclusion (under MaxDistance 40) holds.
2. §9 "each half of the spawn pattern alone survives": the re-place alone is load-bearing for a
   player present before the script runs.
3. §6.2 "Parts per bay ≤ 120, counted 108": measured **65** in an empty bay and **98** in the keeper's
   bay with a full tray, the shelf and the key.
4. §4 "slot hitbox (3.5, 3, 2.5)": wrong in play (REVIEW-1 finding 6). Taps land on the item's pieces
   plus a 2 x 0.1 x 2 tile; `Config.Bay.SlotSize` is gone.
5. §4/§13 boards: opaque board Parts hid the tray and the arc from behind; boards are one-sided.
6. §3.3 "see the catalog": the catalog is now in the manual (layer 2).
7. SUPERSEDED by correction 10 below - on the final code a pick does NOT always become the selected one; the TUTORIAL HINT follows the selection.
8. §8.1 "canSave is true only while we hold the lock": a session without the lock now takes it when
   it frees, writing its own delta on top of the record (`Economy.merge`).
9. §7.1 "salt is one value per player session ... what makes the next shift unpredictable": a salt kept
   for the session is recoverable from one tray and predicted every later shift (pass 3, E3). The salt
   is per shift, and the cart has its own keys (`Seed.cartSeeds`). §8.2/§10.1 "never gets the seed" is
   not true of the CURRENT shift's seed, which the visible tray pins down; it now decides only what is
   already visible.
10. §5.1 "Pick: this item becomes the selected one" (see Traps: selection) and §1/§5.1 "back to the
    tray, or to the front of the cart" (always the tray now).
11. §12 "The memo board above the tray": it now hangs on the right wall (pass 3, U5).

## Deviations from DESIGN.md, deliberate
- `Config.Shift.RefillSeconds = 0.3`; `Config.Bay.SamePickSeconds = 0.05`.
- `Config.Bay.SceneCooldownSeconds = 3`, `Config.Remotes.SelectPushSeconds = 0.1`,
  `Config.Save.Attempts = 3`, `Config.Save.CloseWaitSeconds = 25`.
- Tutorial: floating `TAP HERE` / `PRESS E HERE` BillboardGuis in PlayerGui (only the owner sees
  them) instead of pulsing the bin's PointLight; a `select` hint step.
- The Back Room note card is paged by paragraph (4 pages) instead of one scrolling card.
- `src/shared/Layout.luau` (bay geometry) is an extra pure module.
- The MANUAL drawer the HUD opens for a new layer closes at the first pickup.
- A misfiled item's tag line reads `MISFILED - goes to <BIN>`.
- Pass 3: `Config.Remotes.ActionBurst = 10`, `ActionsPerSecond = 5`, `NoticeRepeatSeconds = 0.05`,
  `NoticeBurst = 6`, `NoticesPerSecond = 3`.
- Pass 3: the misfile toast leads with the item's name (`-8 s. Phone: K goes to KEYS & WALLETS.`); the
  tutorial's closing toast has kind `tutorial`.
- Pass 3: the deposit stamp reads `FILED` / `RE-FILED`, not "SORTED": SORTED is the launch code's name,
  and the leak sweep refuses it in replicated client source.
- Pass 3: the tutorial highlights BOTH ways (the DROP/PRESS E HERE marker AND the bin light pulse).
- Pass 3: career shift 1 excludes the tutorial's archetypes from every draw (14 archetypes).
- Pass 3: the MemoBoard is at bay-local (MaxX - 0.2, 8, -4), Face Left.

## Mutation sweep (REVIEW-2 fixes, 2026-09-24)
Scratch copies only, each mutation proved to reach the bundle, all 28 suites per mutation, sources restored and
md5-checked: see `EYECANDY.md` §13 for the table (25 mutations of the fixes, 3 controls).

## Mutation sweep (the wings, 2026-09-24)
Scratch copies only, each mutation proved to reach the bundle, all 28 suites per mutation, sources restored
and md5-checked: **26 of 27 KILLED**; the survivor (W1, the weather cap skipped) is equivalent with this config
and `EnvConfig.spec` asserts its premise; the harness control and 2 controls survived. Table in
`EYECANDY.md` §7.

## Mutation sweep (pass 3)
In place, one mutation at a time, each proven to reach `build/lost-found-depot.luau`, all 17 suites per
mutation, sources restored and sha256-verified after each: **29 of 29 KILLED** (E2e only after a
scenario was added for it), 3 controls survived (C0 a no-op harness control, C1 the stamp's tilt, C2
NoticesPerSecond). Table in `REVIEW-1.md`. The pass-2 sweep below was NOT re-run on the pass-3 source.

## Mutation sweep (pass 2, final source; scratch tool outside the repo)
Each mutation in its own scratch tree (a copy of the game and of robloxemu's `emu/`, `wrap.py` and all
six checks, so nothing under `D:\Claude\Roblox` is written); one textual patch that must match exactly
once, sha256 of each patched file before and after; every suite (8 specs, the walk, 6 checks). A
harness control with no patch reported all 15 suites green. Real tree hashes unchanged across the
sweep (35 files).

**54 mutations: 50 KILLED, 4 SURVIVED (all four expected, reasons below), 0 NOT APPLIED.**

| id | mutation | result, first killer |
|---|---|---|
| N1 | the in-transform `leaving` re-check removed, alone | SURVIVED: redundant with one-write-at-a-time (the release waits); expected KILLED when the sweep started, reclassified after N29 |
| N29 | N1 AND one-write-at-a-time removed together | KILLED: `_save` autosave in flight re-locks |
| N2 | bay freed only after the release | KILLED: `_save` R1-2 |
| N3 | one load attempt | KILLED: `_save` |
| N4 | no merge (whole profile written without the lock) | KILLED: `_save` 11 instead of 1011 |
| N5 | autosave only for sessions holding the lock | KILLED: `_save` R2-6 |
| N6 | no note cooldown | KILLED: main check + `_save` |
| N7 | every door press writes | KILLED: `_save` (killed only after pass 2 added "the re-send writes nothing"; it SURVIVED the first sweep) |
| N8 | every Select pushes State | KILLED: `_save` 9999 sent |
| N9 | no clock check in admit | KILLED: `_save` +11 after zero |
| N10 | server tutorial ignores the selection | KILLED: main check invariant, `_hudflow` |
| N11 | no `select` hint in the HUD | KILLED: `_hudflow` |
| N12 | camera not given back | KILLED: `_hudflow` |
| N13 | toast hidden under a drawer | KILLED: `_hudflow` |
| N14 | self-opened manual stays open | KILLED: `_hudflow` |
| N15 | catalog lines removed | KILLED: Rules.spec, walk, main check |
| N16 | item pieces not queryable | KILLED: main check, `_view` 25.2% |
| N17 | item ClickDetector not connected | KILLED: walk, main check |
| N18 | tile 0.4 tall | KILLED: `_view` 90.8% |
| N19 | boards opaque again | KILLED: `_view` 3288 blocked |
| N20 | bin signs face away | KILLED: `_view` facing |
| N21 | same-tap guard removed | KILLED: main check toast |
| N22 | failed load keeps its token | KILLED: `_save` |
| N23 | failed merge keeps its token | KILLED: `_save` |
| N24 | live profile does not adopt a merge | KILLED: `_save` |
| N25 | release not retried | KILLED: `_save` |
| N26 | snapshot before the request (one-write kept) | KILLED: `_save` shifts 7 not 8 |
| N27 | one-write-at-a-time removed, alone | SURVIVED, expected: the interleaving it guards (a transform re-run before another write's continuation folded a merge back) cannot be produced by robloxemu, which runs a transform at commit and the caller's continuation right after |
| N28 | N26 + N27 (the regression as first written) | KILLED: `_save` 1011 not 5011 |
| M1 | answer as an attribute | KILLED: attribute sweep (16) |
| M2 | tag colour by answer | KILLED: 3 tag records, want 1 |
| M3 | reach check removed | KILLED |
| M4 | owner check removed | KILLED |
| M5 | RespawnLocation not set AND re-place removed | KILLED: spawn, main, walk and 4 more |
| M6 | backlog counts re-sorts | KILLED: walk, main |
| M7 | torn value kept | KILLED: Shift.spec |
| M8 | Secret in src/shared | KILLED |
| M9 | free pads enabled | KILLED: 13 enabled, want 1 |
| M10 | same-frame refill | KILLED: double trigger carries 2 |
| M11 | no misfile penalty | KILLED |
| M12 | code granted when its write fails | KILLED |
| M15 | Drop prompts always enabled | KILLED |
| M16 | note to every client | KILLED |
| M17 | session lock ignored | KILLED |
| M19 | boards collidable | KILLED: 120 bad parts |
| M23 | carried entry names its answer | KILLED: payload allowlist |
| M25 | timed-out shift not counted | KILLED |
| M27 | door opens at 499 | KILLED |
| M28 | leaving keeps the lock | KILLED |
| M29 | salt not in the seed | KILLED |
| M30 | carried items not returned on death/reset | KILLED |
| M31 | BindToClose releases nothing | KILLED |
| C1 | CONTROL: bin light Brightness doubled | SURVIVED (must) |
| C2 | CONTROL: dust rate 6 -> 9 | SURVIVED (must) |

## Things the gates are known NOT to see
- **Nothing renders.** Legibility, colour, lighting, item recognisability, camera, Fx: none verified.
  The view check is a MODEL (rays against part boxes, a follow camera, one-sided SurfaceGuis, the
  ClickDetector-in-a-Model rule), stated at the top of the file, not a renderer.
- **No physics.** Walking is teleport + clock advance; "nobody climbs out" rests on geometry.
- **ClickDetector / ProximityPrompt activation is not engine-checked.** The server's reach checks are.
- **A merge write whose answer is lost is applied twice** once the stale lock expires (the store gains
  the session's delta twice). The check asserts only that it is never overwritten by the un-merged
  profile. Rare: it needs a session without the lock AND a lost DataStore answer.
- ~~A read-only session's purchase past level 3 after a merge is clamped and its price is not
  refunded.~~ Fixed in pass 3: `Economy.merge` re-prices and refunds. A purchase undone by a merge is
  undone silently (no toast).
- **What real players take to a bin first.** With a pick that keeps the selection, a bot that takes the
  LAST picked item first and reads neither the prompt nor the hotbar misfiles 20 / 33 / 37 at carry
  2 / 3 / 5 (`_firstmin` A3); the first-picked bot and the prompt reader misfile 0.
- **Predictability.** The current shift's tray, bins and memo come from a recoverable 32-bit seed (all
  visible anyway). The cart's keyed streams were not cryptanalysed. The fix assumes each Roblox
  `Random.new()` is seeded independently.
- **FxClient is a no-op headless**; ScrollingFrame clipping is not modelled.

## Needs Studio (none of this is claimed anywhere)
The wings add 18 more items: `EYECANDY.md` §8. The thumbnail shot list is `EYECANDY.md` §9.
1. First-spawn order on join (trace HRP per Heartbeat), and the play-solo "character before script" case.
2. Spawn facing (-Z) and whether the first frame shows tray, bins and the Back Room door.
3. Taps: that a ClickDetector on the item Model fires for its pieces; whether one tap fires BOTH the
   item's and the tile's detector (the server tolerates either); where Roblox measures
   ClickDetector distance from; tapping a flat Phone or ID Badge on a phone screen.
4. One-sided boards: that a Transparency 1 Part's SurfaceGui with an opaque background reads as a
   board from the front, draws nothing from behind, and hides nothing behind it.
5. Legibility on a phone under Temple bloom: tags at 5-12 studs, bin signs at 23-28, the memo board,
   the 16-line stage-3 manual board (TextScaled on 12 x 8 studs is probably too small), RichText route
   words. Use GDI window grabs; MCP screen_capture does not render BillboardGuis.
6. Whether the 16 Part-built items read as what they are.
7. Prompts: one Drop prompt at a time across the 2.49-stud gap; PutBack (R) beside Drop (E); both
   locker prompts; all as tap buttons.
8. Feel: walk 16-22, the tray-to-bin leg, 2 items on shift 1, the 8 s penalty, the 0.3 s refill.
9. The welded massless crate: camera, prompts, movement.
10. Climbing: jump along every wall from bins, tray step and locker.
11. Render cost of 12 bays (about 96 PointLights, 12 dust emitters).
12. Fx: sparkle, FOV punch, flashes, the 3 s Back Room camera tween and its cancel when something
    replaces the note.
13. The HUD on a real phone: hotbar in the centre band, top-edge toggles, the toast row above an open
    drawer, the paged note, tutorial markers and the `select` hint.
14. The four allowlisted glyphs in these fonts (GothamBlack, GothamBold, GothamMedium, RobotoMono, Merriweather).
15. Audio: none in v1; choose and verify ids first.
16. Live server only: profile load time, mobile lag vs ReachSlack 2, the session lock across a real
    shutdown and a real server hop (the merge path), UpdateAsync retry timing, the content-maturity
    questionnaire.
17. Pass 3: the engine's real trigger rate for ClickDetectors and prompts, and whether ActionBurst 10 /
    5 per second ever refuses a fast honest phone player; whether a Part created and destroyed in one
    frame replicates at all.
18. Pass 3: that `Random.new()` without a seed gives independent streams in a live server (E3).
19. Pass 3: "Drop Teddy Bear" over a tag line on a phone's prompt button (fit, legibility); which item
    players take to a bin first (a playtest).
20. Pass 3: the memo board read from the pick point at ~36 studs on the right wall.
21. Pass 3: the FILED stamp, the bin light pulse (a looping Brightness tween) and the MANUAL pulse on
    screen. robloxemu's tween jumps to its goal instead of easing.
22. Gamepad: the hint says "press E"; Cart and Shoes share one Part and neither sets GamepadKeyCode.

## Files
Server `src/server/Main.server.luau`, `src/server/Secret.luau`; client `src/client/Hud.client.luau`,
`src/client/Wings.client.luau`; shared `Config / Rules / Shift / Seed / Economy / Codes / Layout` plus
`Rng / Fx / FxClient / Responsive` (verbatim copies), `EnvBands / Hazards / Rest` (verbatim from +1 Jump),
`Wings / WingArt / StateCache` (the wings); tests `tests/*.spec.luau`, `tests/walk.luau`,
`tests/SortModel.luau` (test-side); headless gates `../robloxemu/check_lostfounddepot.luau`, `_spawn`,
`_save`, `_hudflow`, `_view`, `_hud`, `_rng`, `_firstmin`, `_wings`, `_wingview`, `_hud_wings`, `_compile`;
design `DESIGN.md`, `design/model.luau`; reviews `REVIEW-1.md` (pass 3); the wings `EYECANDY.md`.

## Next
1. **Open it in Studio** (00:00-06:00 window) and work the Needs Studio list, starting with 1, 3, 4, 5, 13,
   then `EYECANDY.md` §8 and the thumbnail shots in §9 (build a fresh place: `LostFoundDepot.rbxlx` on disk
   predates the wings).
2. An independent review of pass 3 (the action bucket, the merge re-pricing, the per-shift salt and
   cart keys, the return-to-tray rule, the selection change) AND of the wings (`EYECANDY.md` §11-§12);
   only their authors' tests and sweeps have looked at them.
3. Commit (nothing is committed), then create the experience, publish script (git-ignored), the
   maturity questionnaire, Public.
