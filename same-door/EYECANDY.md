# The Same Door — the halls change as you carry Seals

Eye candy for The Same Door, built into v1 from the first build (`docs/complete-game-standard.md` §2).
Model document: `plus1-jump/EYECANDY.md`. Every number below is measured by a named gate, or it is a
design choice marked [C]. Nothing here has been seen rendered: the emulator runs the code, it does not
draw it. What only Studio can settle is in §7.

## 1. What is built

| part | where | from the template? |
|---|---|---|
| band blending, glide, weather cap | `src/shared/EnvBands.luau` | **verbatim** from `plus1-jump/src/shared` (md5 `c6fc63a1...`), with its spec (124 assertions) |
| rest state machine | `src/shared/Rest.luau` | **verbatim** from `plus1-jump/src/shared` (md5 `19226cb6...`), with its spec (55) |
| hazards | `src/shared/DoorHazards.luau` | **adapted from labyrint-spill `CellHazards`**, not +1 Jump's `Hazards.luau`; why in §3 |
| the five bands' rules | `src/shared/Bands.luau` + `Config.Env.Bands` | new: progress, reserved colours, decor placement |
| where rest is allowed | `src/shared/Pause.luau` | new: rest only in the hub, between runs |
| the client glue | `src/client/Dungeon.client.luau` (bands, decor, critters, weather, hazards, budgets), `src/client/Hud.client.luau` (rest, pause sheet, banner, brag fanfare) | new |
| part factories | `src/shared/DungeonArt.luau` | new: walls, veils, seals, the Door, hazard fixtures and rings, decor, critters, weather hosts |
| hub daylight | `Fx.applyLighting(Fx.Presets.Temple)` on the server | `Fx.luau`/`FxClient.luau` verbatim from siblings |

## 2. The bands follow your own run

**Trigger: the number of Seals you carry, from the server's `Run` payload, never time.** Progress is
`seals` (0..3), and 4 once the Door has opened. Every run passes all five, and a band lasts about one leg
between seals. The hub is not a band: it keeps the server's Temple daylight, and leaving a run glides back
to it.

| # | band | when | light | walls, decor | critters | weather |
|---|---|---|---|---|---|---|
| 1 | Cold Cellar | 0 Seals | cool blue-grey ambient (70, 80, 100), fog 10-90 | grey stone; cobwebs, chains, drip stubs | 3 bats | dust, 18/s |
| 2 | Moss Halls | 1 Seal | green ambient, soft bloom | green stone; moss, ferns, glowing mushrooms | 6 fireflies | spores rising, 20/s |
| 3 | Crystal Seams | 2 Seals | violet ambient | violet stone; glowing crystals, geodes | 5 crystal moths | glitter, 24/s |
| 4 | Ember Vault | 3 Seals: the Door wakes | warm amber ambient, the Door's glow plate lit | warm stone; braziers, bronze trim | 4 fire sprites | embers rising straight up, 26/s |
| 5 | Dawn Sanctum | the Door opened | open sky at ClockTime 6.3, pink light, fog 60-900 | pale stone; columns, flower beds | 5 birds | petals, 16/s |

**The glide** is `EnvBands.approachTable` with a 0.8 s half-life [C]. Measured on the walk in
`check_samedoor_eyecandy.luau` (Ambient, the sum of RGB distance to the target): **8 % of each change after
0.15 s and 87.5 % after 2.4 s**, for all five changes (hub -> Cellar on entering, three seals, the Door). So
a seal reads as a wave of light, not a cut. Lighting is written at most **10 times a second** [R]
(`plus1-jump` `Config.Env.LightingHz`); the same check counted 356 writes in 35.6 s (10.00 per second).

**Rules that keep decoration from becoming information** (a ranked maze on a shared layout):

* **Decor never encodes the layout.** `Bands.decorFor(wall key, face, band, cfg, hash01)` takes no cell
  content; `Bands.spec` pins its arity at 5, so adding a content argument fails a spec. About half the
  wall faces carry a piece [C] (measured 1/3 first: at most 4 pieces within 24 studs read bare).
* **Nothing but a Seal is seal-gold, nothing but a ring is hazard-red.** `Bands.validate` rejects any
  wall, decor, critter, weather, torch or Door colour within 75 RGB of either (`Bands.spec`: 6 mutated colours
  refused), and the eye-candy check scans every client part on the walk: 0 decor or critter near
  either colour, 0 gold parts outside a Seal, 0 red parts that are not a ring.
* Decor sits at most **1.2 studs** out of a face, only on revealed walls within **24 studs** [C]; critters
  stay in your current and adjacent revealed cells above head height, and outside the grid (the
  antechamber, the Dawn Sanctum) they circle you. REVIEW-1: the first build homed them on the entrance
  cell there, so the Sanctum's 5 birds flew ~150 studs away inside the closed grid; the eye-candy check
  now requires every band's critters within 16 studs of the player and the Sanctum's 5 within 12.
  Everything but a wall is
  CanCollide/CanQuery/CanTouch false. Weather drifts straight up or down (`Bands.weatherVelocity`).

## 3. Hazards: part of the day, not the player

**Why not +1 Jump's `Hazards.luau`:** it launches a lane at the player from wherever the camera looks, on a
random clock. On a ranked, shared layout that puts luck into the time. `DoorHazards.luau` is
labyrint-spill's `CellHazards` (the family's reviewed version for a timed maze) with four changes:

1. **Where** comes from the day record (`Dungeon.pickHazards`, server-only) and reaches a client only in a
   revealed cell's payload. A hash of a public number would let a client compute them.
2. **Forks only** (3+ open sides): a fork is visibly a fork once revealed, so a hazard tells nobody where
   the best route goes. `Dungeon.spec`: 3 fork hazards on every one of 300 mints, never on a seal or the
   Door, pairwise >= 4 steps, >= 3 steps from the entrance.
3. **Staggered slots on the run clock:** slot k impacts at `6 + 4 (k - 1) + 12 n` s after the line; a
   3.0 s warning + 0.8 s of debris fits in the 4 s slot, so never two at once (`DoorHazards.spec` sweeps
   120 s at 10 ms: max 1 active; the eye-candy check: never more than one ring on screen).
4. **The ring is red and IS the hit zone:** 2.5 strike + 1.5 player = a 4-stud radius. `DoorHazards.spec`
   sweeps the circle: 3.9 studs hits, 4.1 does not, all the way round; the built ring measures 8 studs
   across (the check, and mutation M7 kills a 20 % wider ring).

A hit knocks you down for **0.8 s** with a 5 studs/s push away from the impact, never up (at most 4
studs): about a second, never the run. A jump is no dodge (hit up to 12 studs over the floor). The
knock is applied by your own client to your own character; the server trusts none of it.

**Measured rarity** (`tests/Pacing.spec.luau`, the game's own generator and schedule, an impact within
12 studs of the root that does not hit): **normal 0.350 near-misses per running minute (one per 2.9 min)**,
fast 0.315 (3.2 min), slow 0.369 (2.7 min). The standard asks for about one per 2-3 minutes. A runner who
ignores every warning would be hit 0.116 times a minute (normal).

## 4. Rest: what "pause" means here

The run clock never stops: it is the medal and the record, and `Rest.luau`'s own header says rest only
pauses things that exist to bother you. So rest lives **between runs, in the hub** (`Pause.mayRest`, which
fails closed; labyrint-spill's BreakRoom precedent).

* **The campfire** (right of the spawn): a client-made "Rest by the fire" prompt, and a Rest button
  top-centre while you are in the hub. You sit (`Humanoid.Sit`), the view softens (a local BlurEffect),
  and any move wakes you after 0.4 s [R]. Config: `IdleSeconds 0` (the hub has nothing to be safe from),
  `WakeOnMove`, `BlockWhileThreat`, `PendingSeconds 2` (a default jump lasts 0.54 s).
* **The pause button in a run** (top-right) opens a sheet: "The clock never stops. Leave this run and rest
  by the fire?" with Leave run / Keep running. Measured: the display clock advanced **1.00 s of 1 s** under
  the open sheet. Leave run ends the run (nothing posted, not a failure) and you arrive resting at the fire.
* **Never an exploit:** nothing pauses, hazards exist only inside a run on the run clock, and a rest sends
  no remote (measured: 0 server events during a rest) and earns nothing. A rest requested inside a run is
  refused with "You can rest by the fire in the hub, between runs."

## 5. Client and server

| what | where | why it is safe |
|---|---|---|
| the day, the generator, the reveal, the clock, seals, the Door, voids, saves, the board | server | authoritative |
| walls, veils, seals, the Door, hazard fixtures and rings, decor, critters, weather, lighting, the knock, rest, the HUD | client, inside `workspace.SameDoorLocal` | cosmetic or own-character only; built only from cells the server already sent |
| the torch (a PointLight on your root, coloured by rank) | server | others see your rank |

Walls are built by the client: a character's physics is simulated by its own client, so a noclip ignores
server walls just as easily; the server polices movement against the cell graph instead (`RunCheck`).

## 6. Budgets (enforced in code, measured)

| budget | cap | measured max on the eye-candy walk (the pinned day, the perfect line) |
|---|---|---|
| client parts (`SameDoorLocal`) | 220 | 104 |
| decor pieces | 30 | 7 |
| critters | 8 | 6 |
| weather emitters | 2 at <= 60 particles/s (`EnvBands.capRates`) | 1 at 26/s |
| client lights | 3 (+ the server torch = 4); only the nearest 3 are enabled | 1 |
| particle emitters | 4 (2 weather + the nearest seal sparkles) | 2 |

The walk's worst case is not the design worst case: DESIGN §17 counts 201 parts if every wall and veil
peaked at once. The decor cap is computed each refresh from what walls, veils, contents and critters leave
under 220.

## 7. Needs Studio (only a real engine, network or device can settle these)

1. **Honest movement statistics** on desktop and on a phone over Wi-Fi and 4G: the largest 0.5 s and 3 s
   displacement and the time against the taut line; set `Config.Check` so under 1 % of honest runs void.
   Also confirm a humanoid on flat ground never exceeds its WalkSpeed.
2. `Random:NextInteger(0, 4294967295)` and `bit32.bxor` on values >= 2^31 (fork-tower REVIEW-4 §8.1).
3. The OrderedDataStore stores and returns an encoded value near 1.8e15 exactly.
4. `GetFriendsAsync` paging on a real account with many friends; the friends board's fill time under the
   real request budget (the emulator has no `GetFriendsAsync`; `check_samedoor.luau` stubs the page shape).
5. Client-built walls: collision with the local character; the camera in 14-stud halls with a ceiling on a
   phone (does it clip into the ceiling?).
6. **Veils:** do the black boxes in unrevealed cells read as darkness or as black walls?
7. Band lighting **indoors** under a ceiling (Ambient, ColorCorrection, Bloom; the hub's Atmosphere stays
   on inside the lanes); readability at a low graphics level; whether a 0.8 s glide reads as a wave.
8. The seal glow and the awake Door readable from 2 cells away.
9. The red ring on a dark floor; can a phone player pass beside it in the 1.5-stud lane; how the 0.8 s
   `PlatformStand` knock feels and whether it releases cleanly (headless: a run that ends, voids or
   finishes mid-knock now stands the player up at once; REVIEW-1).
10. Reveal latency: no pop-in in front of a player at 16 studs/s on a 300 ms connection.
11. The display timer against the official time at the finish (both start on the player's own crossing;
    they should differ by jitter only; headless they matched to the hundredth).
12. Hub: the board's SurfaceGui legible from the spawn (REVIEW-1 relaid it: rank / name / time / medal
    columns, names truncate with "...", every other label shrinks to fit under a cap, a SEALED plate, an
    8-stud plaque; `design/measure/boardtext.py` estimates the sizes with Montserrat standing in for
    GothamBold: the empty-friends message on 3 lines at 22 px, the sub-line at 20-22 px, a 13-character
    name whole); the board prompt's toggle; the campfire sit
    (`Humanoid.Sit` without a seat, as plus1 EYECANDY §8.11); **a client-made ProximityPrompt fires
    `Triggered` on that client**.
13. The Dawn Sanctum's look and the THE DOOR IS SEALED fanfare (white-gold flash + a 10-degree FOV punch).
14. Frame time on a low-end phone at 220 local parts, 4 lights and 4 emitters.
15. Place settings: MaxPlayers 12; the avatar type (the height check assumes the root about 3 studs up).
16. The Studio fallback door with API access off (for thumbnails and clips).
17. The midnight rollover in a live server (`check_samedoor_days.luau` covers the logic with `os.time`
    driven by the virtual clock). Since REVIEW-1 the day's validate recomputes the tight P: 30 ms mean,
    177 ms worst on the build PC (`timing.luau`); does it show as a hitch on a live server?
18. The top HUD row under a phone notch or safe area.
19. **The pivot race:** right after the server's `PivotTo` into the antechamber, a client-owned character
    may report its hub position for a frame or two; the run ignores out-of-lane samples before the line
    for exactly that reason, and (REVIEW-1 finding 1) the only way back in is the antechamber: a
    re-entry anywhere else voids. Confirm the stale position is the hub's (outside every lane), for a
    frame or two, not seconds.
20. **Remote events fired before a client script connects** (DayInfo, the first board rows at join):
    Roblox queues them; the emulator does not, so the day facts are also attributes on
    `ReplicatedStorage.SameDoorRemotes`. Confirm the board shows rows at join without waiting 60 s.
21. The finish card's text on a 640x300 phone (the fit gate measures frames, not wrapped text).
22. **The Dawn Sanctum's glass parapet** (4 server parts, 12 high, Glass at 0.8 transparency): does it read
    as glass and keep the sunrise in view, and does the camera behave against it? It exists because the
    balcony stands over nothing and every finish lands there (`check_samedoor.luau` casts 32 rays from its
    centre, at root height and at a jump's apex, and none may leave the floor).

23. **The tight line's clearance.** P and the whole-run check both keep a root 2 studs off a jamb (wall
    half-thickness 1 + half a 2-wide root) and let it graze each 4-stud pickup circle (REVIEW-1). Can an
    R15 and an R6 character really walk that close? If the real clearance is larger, raise
    `Config.Check.TautMargin`: P follows it, so the medals stay fair and the check stays a lower bound.
24. **A replication stall over a seal.** A 0.4 s stall never voids (REVIEW-1 raised the window slacks), but
    one that straddles a pickup can make the server's chord miss the seal (3 of 42 spots on the spec's
    day): the seal stays lit and the player steps back into it. How often on real networks?
25. **Critters around the player outside the grid** (antechamber, Dawn Sanctum): they circle 4 studs out,
    9.5-11.5 studs up; under the antechamber's 14-stud ceiling, do they read as bats or as clutter?
26. **The save and lock messages** on a phone: "Saving failed just now. This run is kept and saved at the
    next try (within 20 s).", the "still open in another server" card line, and the toasts when a kept run
    lands and when a waiting session takes its profile over (`check_samedoor_save.luau`).
27. **The lane pool** with MaxPlayers 12 = 12 lanes: a lane frees when its player is back in the hub; with
    more players than lanes the next one waits with a toast that says so (`check_samedoor_lanes.luau`).

## 8. Thumbnail shot list (1920 x 1080; the Studio door unless noted)

Coordinates are the Studio door's (seed 20260930), lane 1 (grid corner at world `(0, 0, 1000)`), from
`MARKETING.md`'s table. Hide Roblox's UI and the HUD unless the HUD is the point.

| # | shot | camera (world) | in frame | how to stage |
|---|---|---|---|---|
| 1 | **The Door at the end of a torchlit hall** | (56, 6, 1116) looking at (56, 5.5, 1136), FOV 60 | the Door in cell (3, 8) head-on, sockets lit, glow plate on; Ember Vault embers; braziers on the side walls | Walk the line to the third seal (21.34 s after the line), then on to cell (3, 7) and stop facing north. |
| 2 | **The sealed Door at sunrise** | (72, 7, 1166) looking at (72, 6, 1196), FOV 55 | the Dawn Sanctum: marble columns, flower beds, the open Door glowing, pink dawn sky, petals | Finish any run; the server moves you to the Sanctum; step aside out of frame. |
| 3 | **A fork with the red ring and the falling stalactite** | (56, 7, 1074) looking at (56, 2, 1088), FOV 50 | hazard slot 2's cell (3, 5): the ring bright red on the dark floor, the stalactite a stud above the floor, the runner half out of the ring | Walk the line to (3, 4) (5.53 s), step to the ring's edge, capture at run-clock 9.9 s (impact 10.0 s). |
| 4 | **The hub board with medal plates** | (6, 7, 6) looking at (14, 7, 16), FOV 50 | the board (Door #, 10 rows, SEALED plates), the arch glowing behind, the campfire | **API-access-ON test place** with finished runs from a few accounts (the Studio door has no board). |
| 5 | **Into the dark** (the first view) | (72, 5, 990) looking at (72, 5, 1012), FOV 70 | the antechamber, the start line glowing, the entrance hall in Cold Cellar blue, black veils beyond | Enter through the arch; stand at the antechamber's south wall. |

## 9. Gates (how every number above was measured)

`CLAUDE.md` lists every command. The eye-candy ones: `tests/Bands.spec.luau`, `tests/DoorHazards.spec.luau`,
`tests/Pause.spec.luau`, `tests/EnvBands.spec.luau`, `tests/Rest.spec.luau`, `tests/Pacing.spec.luau`
(hazard rarity), `robloxemu/check_samedoor_eyecandy.luau` (bands, glide, budgets, colours, hazards through
the real remotes, rest), `robloxemu/check_samedoor_hud.luau` (the HUD in six modes, overlap on).
