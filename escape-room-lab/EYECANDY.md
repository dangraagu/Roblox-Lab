# Escape Room Lab — the Lab you see, the rare hazards, the Break

Built with the game (2026-09-30/10-01), from `DESIGN.md` §7-9, to `docs/complete-game-standard.md`. The
+1 Jump templates (`EnvBands.luau`, `Hazards.luau`, `Rest.luau` and their specs) are copied verbatim; every
adaptation lives in this game's config and glue and is stated in §10. Nothing here has been rendered:
every number below is a headless measurement or arithmetic, and what only Studio can judge is §8.

## 0. The owner's standard, item by item

| standard | status | how, and which gate proves it |
|---|---|---|
| §1 core loop reachable from join | met | `tests/walk.luau`: spawn, Solo Lift (the rider's own doors), room 1 and room 2 through the real HUD (37-38/0); `check_escaperoomlab_env`: all 15 rooms to the Roof; rejoin in `check_escaperoomlab_save` and `_release`; both ways up to the Roof in `_lifts` |
| §1 spawn per SPAWN-ORDER.md | met | one enabled SpawnLocation (AtriumSpawn), RespawnLocation first in PlayerAdded, no CFrame in CharacterAdded; `check_escaperoomlab` (landing, respawn), mutants S1/S2 |
| §1 server-authoritative, nothing secret replicates | met | answers in server script memory only; empty attribute allowlist; payload key allowlists; `check_escaperoomlab_leak` (45/0), `RoomView.spec`, mutants S5/S6/U8 |
| §1 a seed a player could memorise | n/a, stronger | no seed exists: a fresh engine-seeded `Random.new()` per room (DESIGN.md §14.1) |
| §1 DataStore discipline | met | pcall everywhere, session token on every write, canSave only with the lock, string keys, no one-time grants in v1; a failed load retried; the release final; a session that left with its load in flight takes no lock; `check_escaperoomlab_save` (41/0), `_release` (22/0), mutants S8/S9, M1-M3, M18, R9-R11 |
| §1 no silent no-ops | met | every honest refusal answered in words; malformed payloads dropped silently by design; `check_escaperoomlab_act` (25/0) |
| §2 Fx preset + signature particles | met | `Fx.Presets.Lab` first thing on the server (= band 1, compared field by field in `check_escaperoomlab_env`); Atrium dust volume; a sparkle on every solve; neon rims on stations |
| §2 bands: >= 5, own light/colour/scenery/critters/weather, glided | met | 6 bands (§2 below); `EnvConfig.spec` (200/0), `check_escaperoomlab_env` (114/0: seep-in, glide, decor, creatures, weather over 15 rooms) |
| §2 hazards: rare, telegraphed, ring = hit zone, one at a time, cost little | met | §3; the ring stands still from its first frame and stepping out of it at any time before the hit dodges (REVIEW-1 B1); nothing is held at the door or the grace (B4); `EnvConfig.spec` (203/0), `check_escaperoomlab_hazards` (64/0) through the real client; 9-11 per full run, median gaps 170-206 s of play |
| §2 rest / pause, never an exploit | met | §4; freezes the hazard clock, queued with a hazard inbound, ended by opening a station; `check_escaperoomlab_hazards` |
| §2 budgets measured and capped in code | met | §6; `capRates` for weather, a hard cap in `localPart` with a hazard reserve; `check_escaperoomlab_budget` (5/0), `check_escaperoomlab_env` every frame |
| §2 brag moment in 30-45 min, long-term goal | met (model) | the Roof at p50 39.1 min for the normal profile, p90 41.2; 45 stars at p50 69.5 min (`tests/Pacing.spec.luau`; human times are assumptions) |
| §2 phone first, overlap = true | met | root Frame + UIScale, 44 px taps, middle-column overlay on landscape phones; `check_escaperoomlab_hud` PASS at 60 viewport x mode measurements + 712 controls contained |
| §3 public + friends board, un-inflatable metric, first-reach ties | met | stars 0-45, OrderedDataStore `u_<userId>`, `stars*2e9+(2e9-reachedAt)`, keep-max; public top 10 cached 60 s; friends on demand, capped 200, single-flight per player, one budget-checked read at a time per server, lists and scores cached; `Board.spec` (68/0), `check_escaperoomlab_save` (tie-break), `check_escaperoomlab` (renders, prompt, failure path), `check_escaperoomlab_friends` (16/0: 41 presses = 1 list call, 1 read in flight, ranked view, no-friends note). Known and not changed: the public top 10 freezes once ten players reach 45 (REVIEW-1 B5), which the prescribed first-reach tie-break on a capped metric implies; an owner decision |
| §3 no Robux, no gambling | met | nothing sold, no codes in v1 |
| §4 README store text <= 1000 chars | met | 933 characters, ASCII (`README.md`) |
| §4 EYECANDY.md: needs-Studio list + thumbnail shot list | met | §8, §9 |
| §4 clip list | met | `MARKETING.md`, 8 clips |
| §4 CLAUDE.md: every gate + traps | met | `CLAUDE.md` |
| §4 every gate green, TDD, mutation-tested with a control | met | 31 gates green, 6 runs in a row (186 of 186); 40 build mutants + 19 review mutants + 24 review-1 mutants killed, the controls survived all 31 (§7); `luau-analyze` not available here |
| §5 night shift (Studio, publish, marketing) | not done, by rule | Studio only 00:00-06:00; §8 is its list |

---

## 1. What is where

| file | what |
|---|---|
| `src/shared/EnvBands.luau`, `Hazards.luau`, `Rest.luau` | **templates, verbatim** from `plus1-jump/src/shared` (md5 c6fc63a1, f36a9ac2, 19226cb6), specs verbatim (e2a9d464, 2f42278c, 4c38d41f) |
| `src/shared/Config.luau` | `Config.Env` (6 bands), `Config.Hazards` (the pitch-85 adaptation), `Config.Rest` (IdleSeconds 0), `Config.Budget` |
| `src/shared/Decor.luau` | per-band decor pieces and indoor creature paths (the adaptation of the template's open-sky spawn ring) |
| `src/client/Lab.client.luau` | the glue: progress -> bands, lighting glide, decor, creatures, weather, hazards, the Break, title cards |
| `src/client/Hud.client.luau` | draws the Break button, the hazard banner and the cards Lab.client posts on `ClientBus` |
| `src/server/Main.server.luau` | builds each room's shell and props in its wing's palette; the lock glow; the Atrium dust |

## 2. The bands and what triggers them

Progress is the game's own logic, never time: `p = (wing - 1) + (room - 1 + solved / stations) / 3`, from
the room's `RoomState` (0 in the Atrium, 5 on the Roof). Every band after the first fades in over the 1/3
before its start, which is exactly the last room of the wing before, so **the next wing seeps into the last
room of each wing as its stations are solved, and is fully there when that room's door opens**. The band's
NAME (title card, which hazard flies) follows the room's whole wing number. Every written value glides at a
0.6 s half-life; Lighting is written at most 10 times a second, only when a value changed.

| # | band | light and grade | decor (client) + props (server) | creatures | weather | hazard |
|---|---|---|---|---|---|---|
| 1 | Reception (0) | warm afternoon, ClockTime 16.8, cream walls, teal carpet | blinds, sun shafts, clock, sign, ceiling panels; desk, ferns, cooler | 2 flies | dust 4/s | none (onboarding) |
| 2 | Archive (1) | amber lamplight, sepia, exposure -0.15 | cobwebs, dust cloths, beams, book ledges; shelves, ladder, boxes, banker's lamp | 4 moths | dust 3/s + paper 3/s | spider |
| 3 | Greenhouse (2) | bright humid green, bloom 1.2 | glass panes, vines, leaves, mist pipe; palm, planters | 5 butterflies | mist 6/s + drips 2/s | seed pod |
| 4 | Cold Storage (3) | cold blue-white, contrast 0.25, saturation -0.35 | icicles, frost bands, vents; racks, frozen crates | 3 drones | snow 20/s | ice drone |
| 5 | Reactor (4) | dark teal/violet neon, bloom 1.6 | pipes, neon strips, hazard stripes, orbs; glass core, pipes | 4 spark-bugs | steam 6/s + sparks 4/s | crane claw |
| 6 | Roof (5) | night, ClockTime 0.5, 3000 stars | a city skyline of 24 towers 260-480 studs out (8 lit); dome, telescope | 3 bats | leaves 4/s | none (the brag is peaceful) |

Measured over all 15 rooms through the real client (`check_escaperoomlab_env`, 2493 frames):
- the server's boot lighting equals band 1 field for field, and one second of client later it still does;
- each wing's first room shows only that wing's decor; creatures and weather as in the table (5 butterflies,
  snow at 20/s on one emitter, steam and sparks on both);
- the seep-in peak with the feeders solved and the door shut: **0.45 / 0.45 / 0.69 / 0.70** of the next
  band's decor opacity in wings 1-4 (one feeder = half the room's stations, two = two thirds); after the door
  opens it is fully in and the old wing's decor is gone;
- a jump (the Roof -> the Atrium) glides: 0.2 s later the light is still between the two, 6 s later settled;
- every wing's title card fired exactly once (WING 2-5), none for Reception; 15 escape cards on screen;
- every decor piece at its authored place in the room, above 9 studs, off every station face, on every frame.

## 3. Hazards and their measured rarity

The template, verbatim; the adaptation is config and glue: every kind comes from `pitch = 85` (the
template's `MAX_ELEVATION`) and the glue passes `ctx.pitch = math.rad(85)`, so the template plans a
near-vertical lane from the ceiling straight down onto the player. What that gives up: a lane that STARTS on
screen. The telegraph is the ring, the banner and the thing entering the frame as it lowers (§8 item 4).

Probe (`EnvConfig.spec`, the template against this config): a lane starts at y <= **14.954** under a
16-stud ceiling (root at 3), at most **1.046** studs sideways of its target; the ring is **7** studs wide;
standing still is hit **36 of 36**; the lane LOCKS on its first frame (`commit = telegraph`, REVIEW-1 B1), so
the ring never moves and stepping 3.9 studs out at any time **0.0-1.8 s** after it shows is hit **0 of 684**
(before: 540 of 684, the ring followed the player for 1.5 s and the hit came at 2.13 s); a player who stands
still is hit at **2.133 s**; over 20 h of exposed time **714** hazards, **one per 100.8 s** (interval 80-120 s);
a hit is **(19.4, 0.0, -4.8)** studs/s: 20 sideways, no lift.

Exposed time (REVIEW-1 B4) is a legal spot (1 stud off the walls, 5 from both doorways) past the 8 s arrival
grace, in a band with a hazard. Everywhere else the glue passes `resting = true` and the clock is FROZEN. It
used to run at the door station and in the grace with the hazard held (`grounded = false`), so a hazard that
came due at the keypad fired the moment the next room's grace ended: 15 of 40 at exactly 8.0 s after arrival in
the reviewer's four full runs. Since the door, where a room's longest think happens, no longer counts, the
interval is 80-120 s instead of the template's 120-180: four full headless paths at shipped settings (the
reviewer's `rev3_path`, eight runs) met 9-11 hazards on the way to the Roof, median gaps 170-206 s of play, none
at the end of a grace (the earliest of 77 came 9 s after arrival), never two at once, and every step-out 1.0 s
after the ring showed dodged (36 of 36).

Through the real client (`check_escaperoomlab_hazards`, intervals set to 8-9 s in memory for the run):
- 30 s in the Atrium, 75 s in Reception's three rooms, 30 s in an entry cab: **no hazard**; after the cab the
  next hazard still took the rest of its interval (the clock was frozen, not running);
- in the Archive: not before the 8 s arrival grace; the spider's model starts under the ceiling, within 1.85
  studs of straight overhead; the ring is exactly 7 studs across, centred on the player, at the feet;
- standing still: hit, a 20 studs/s sideways stumble, PlatformStand wears off after 0.6 s, the room unchanged;
  stepping out: 3 of 3 dodged, the banner turns to CLEAR; stepping out 0.3 s after the ring shows: 3 of 3
  dodged, the ring moved 0.000 studs (before REVIEW-1: 0 of 3, the ring moved 4.000 studs with the player);
- 30 s at the door station, then a legal spot: the next hazard still took the rest of its interval (before:
  0.1 s, the held hazard); room 5 straight after a hazard: the first came 12.20-13.25 s after arrival over six runs (before: 8.00 s);
- an open station overlay folds to its title bar while a hazard is live and reopens when it has passed.

The pacing model counts **10.2** hazards on a normal player's way to the Roof (exposed = feeder time past the
grace; the first hazard wing starts at minute 3.9). Hazards are client-side, as in +1 Jump: a partner sees you stumble with nothing hitting you (§8).

## 4. The Break (what "pause" means here)

`Rest.luau` verbatim. `IdleSeconds = 0` is the one adaptation: standing still is how a puzzle is thought
through, and the template's 20-s idle rest would switch hazards off at every station. The Break button (top
right, >= 44 screen px) sits the avatar and dims the view (a depth-of-field); moving ends it. On top of the
template: opening a station ends the Break, and starting a Break closes the overlay. Why it is never an
exploit: nothing runs on time (no clock, no time in the metric); nothing can be solved while resting; it is
queued, not granted, with a hazard inbound; toggling it freezes the hazard clock and never resets it.
Measured (`check_escaperoomlab_hazards`, intervals 8-9 s): 40 s of Break, no hazard; after moving, the next came
2.90-3.75 s later over six runs after REVIEW-1 (the frozen clock resumed where it stopped, it was not reset); a Break pressed
with a hazard inbound was queued and started once the sky was clear; opening a station ended it.

## 5. Client vs server

The server builds each room's shell and props in its wing's palette and colour (public geometry) and the
lock glow. Everything else here is client-side and cosmetic, or harms only the local character, whose
physics the client owns: the band blend, decor, creatures, weather, hazards, the Break. The server never
hears of a hazard or a Break; Lab.client fires no remote. Stars come only from the server's verdicts.

## 6. Budgets (measured, capped in code)

| budget | cap (`Config.Budget`) | measured max over 15 rooms + the Roof | how it is capped |
|---|---|---|---|
| local parts | 120 (8 reserved for the hazard) | 53 | `localPart` refuses past the cap; cosmetics cannot use the hazard's 8 |
| emitters on | 3 (2 weather + 1 hazard) | 2 | weather via `EnvBands.capRates(rates, 2, 60, 0.5)` on two hosts |
| beams / trails / local lights | 4 / 2 / 2 | 0 / 0 / 0 | none are built |
| server parts per room | 160 | 52-75 | counted per room headless |
| decor pieces per band | 30 | 24 (the Roof) | `Decor.spec` |

`check_escaperoomlab_budget` lowers the cap to 20 in memory: the client never exceeded 20 (max 16), still
drew a hazard's ring, and warned nothing. That check found the one defect in this area: with the budget full
the ring was skipped. The hazard now draws on the reserve.

## 7. Gates and the mutation sweep

Every gate and its count is in `CLAUDE.md`. The sweep (scratch copies, 2026-10-01): **40 of 40 KILLED**, and
the **control survived all 27 gates**.

| # | mutation | killed by |
|---|---|---|
| S1 | a second enabled spawn (on the Roof) | check_escaperoomlab: exactly one enabled SpawnLocation |
| S2 | AtriumSpawn disabled | check_escaperoomlab |
| S3 | the door gate removed | check_escaperoomlab: no lockout may start while a line is dark |
| S4 | a hint to everyone | pair: Ben receives no hint |
| S5 | the door code as an attribute | leak: the code appeared before it was entered |
| S6 | dark door rows show their guess | leak |
| S7 | the hands-on rule dropped (server) | pair: Ann 2 stars, want 0 |
| S8 | the board written without keep-max | save: 30 stars stay 30 |
| S9 | saves ignore the session token | save |
| S10 | lockout per player, not per station | pair |
| S11 | a reset keeps the player in the room | pair |
| S12 | the Act reach check off | act |
| C1 | the camera's pitch instead of 85 degrees | hazards: 11.6 studs sideways |
| C2 | the ring drawn at hitRadius only | hazards: 4.00 studs across |
| C3 | no arrival grace | hazards: 2.8 s after arrival |
| C4 | the Break does not freeze hazards | hazards |
| C5 | opening a station keeps the Break | hazards |
| C6 | the cabs do not freeze the clock | hazards (added after the first sweep) |
| C7 | the lighting snaps | env: 0 from Reception after 0.2 s |
| C8 | decor follows the camera | env (added after the first sweep) |
| C9 | a title card on every frame | env (added after the first sweep) |
| C10 | the weather cap wired to 1 emitter | env |
| H1 | tap targets of 40 screen px | hud: 206 problems |
| H2 | the overlay uncapped on tall phones | hud: 4 |
| H3 | the keypad always 3 columns | hud: 3 |
| H4 | the overlay ignores the thumbstick column | hud: 35 |
| H5 | the HUD does not say Hello | walk: the HUD starts blank |
| B1 | no local part cap in code | budget |
| B2 | the ring not in the hazard reserve | budget |
| U1-U12 | CodeLock keeps extra lines; Shelf may start solved; Lamps keeps any set; a Text sentence; keepHigher always writes; sanitize keeps 7; Lab.stars ignores hands-on; RoomView leaks the press set; no fade; idle rest back on; decor in front of station A; room 15's table | their specs (U9, U11 also env) |
| control | the Atrium directory's title text | **survived all 27** |

**The review sweep** (after the adversarial review's fixes, 2026-10-01): **19 of 19 KILLED**, and the same
control **survived all 31 gates**. Each new gate was red on the unfixed build first: lifts 8 failed, save 6,
release 8, friends 7, Board.spec 4 (and a crash), hint 2.

| # | mutation of the fixed code | killed by |
|---|---|---|
| M1 | the release keeps its token AND the transform skips `releasing` | release (case 3: leave after the tick, slow save) |
| M2 | autosave does not retry a failed load | save |
| M3 | a failed load call ends saving (the old "nostore") | save |
| M4 | two in the Solo Lift block each other | lifts |
| M5 | the Solo Lift's doors never shut | lifts |
| M6 | ATRIUM is a plain tap | lifts |
| M7 | room 15's lift takes the party apart member by member | lifts |
| M8 | the Roof door skips the arrival | lifts |
| M9 | the friends fetch is not single-flight | friends |
| M10 | friend reads run concurrently | friends |
| M11 | `encode` does not clamp the reach time | Board.spec |
| M12 | `encode` gives 0 stars a time part | Board.spec |
| M13 | the HUD keeps a lamp hint after its press | hint |
| M14 | a partial friends view says "Loading" | Board.spec |
| M15 | a friend read waits for budget forever | Board.spec |
| M16 | friend lists not cached | friends |
| M17 | friend scores not cached | friends |
| M18 | merged progress waits for the next autosave | save |
| M19 | the old no-friends text | Board.spec, friends |
| control | the Atrium directory's title text | **survived all 31** |

**The review-1 sweep** (after the second review's fixes, `REVIEW-1.md`, 2026-10-01): **24 of 24 KILLED** (22 of the
fixes, and the first sweep's leak mutants S5/S6 re-run as L1/L2 after the leak gate's array search was scoped
past the public `flasks` field, where a flask order once equalled a door code by chance); two controls
**survived all 31 gates**. Scratch copies only (`scratchpad/erlc1/mut/<id>`); each mutant's text was
found in the bundle the gates ran (`mutate_r1.py`). Red on the unfixed build first: lifts 12 failed + a crash
(its §9 could not start), pair 10, release 8, hazards 4, EnvConfig 2, walk 2; then Pacing 1 (6.8 hazards at
120-180 with the corrected model) for the interval.

| # | mutation of the fixed code | killed by |
|---|---|---|
| R1 | any player standing on my pad blocks GO (the old rule) | lifts, pair |
| R2 | the partner may stand on the same pad | pair |
| R3 | a server door shut in the Solo Lift doorway for every ride | lifts (1054 of 1200 frames blocked), walk |
| R4 | the rider's client never shuts its own doors | walk |
| R5 | a Solo rider is aboard wherever they stand | lifts |
| R6 | a pair member is aboard wherever they stand | lifts |
| R7 | NEXT stays lit during the ride | lifts |
| R8 | a NEXT press during the ride falls through to "The door is still shut." | lifts |
| R9 | the load transform ignores `gone` | release (the "late" case, fallback write 5 s) |
| R10 | no release after a load that landed for a gone session | release (the "early" case) |
| R11 | leaving does not mark the session gone | release |
| R12 | a wrong try marks only the one who made it | pair |
| R13 | a hint marks only its taker | pair |
| R14 | the pair's reason text is the solo one | pair |
| R15 | after a hint only the taker gets the new room state | pair |
| R16 | the lane follows the player for 1.5 s (spider commit 1.5) | EnvConfig (540 of 684 hit), hazards |
| R17 | the old clock: running at the door and in the grace, the hazard held | hazards (0.1 s; 8.00 s after arrival) |
| R18 | the interval back to 120-180 s | EnvConfig, Pacing (6.8 hazards) |
| R19 | a GO from the departing pair is told "full" | lifts |
| R20 | the rider's doors stay until the timeout | walk |
| R21 | the rider's doors do not collide | walk |
| R22 | a rider left behind is not told why | lifts |
| L1 | the door code as an attribute (S5 again) | leak, compile |
| L2 | dark door rows show their guess (S6 again) | leak |
| CTL1 | the Atrium directory's title text | **survived all 31** |
| CTL2 | the colour of the rider's door | **survived all 31** |

## 8. Needs Studio (only real rendering, input or a live server can settle these)

1. Every band's indoor lighting: Ambient, exposure and bloom per wing; band 1 matching `Fx.Presets.Lab` on
   screen; the seep-in in each wing's last room reading as a change, not a glitch.
2. Overlay legibility on a real phone: clue sentences at the smallest size, the Clues/123 toggle, the scroll.
3. ProximityPrompts on touch at wall stations with an 8-stud reach; the prompt button not under a thumb.
4. The vertical hazard: a model lowering at 4 studs/s reads as coming for you; the ring on every floor
   material; the banner seen in time although the lane starts above the frame.
5. The knock: 20 studs/s with 0.6 s PlatformStand pushes without flinging, releases cleanly; the overlay
   fold and reopen feels fair.
6. Break: `Humanoid.Sit` from the client sits, replicates, and wakes on stick input.
7. Generation on a live server: up to 19.40 ms per 4-digit door in the CLI (DESIGN.md [M 1b]); a hitch?
8. Friends board: `GetFriendsAsync` paging, `GetRequestBudgetForRequestType`, name lookups (needs a universe);
   the local FriendsFace (ZOffset 1) drawn over the public face.
9. The ordered store's `UpdateAsync` with keep-max on a live store.
10. Two real clients in a pair; a partner's local-only knock reading as odd or fine.
11. Tap targets and the safe area on real phones (notch, home indicator); the 46% overlay cap on tall phones.
12. Frame time on a mid or low phone in the densest Reactor room (75 server parts, up to 53 local, 2 emitters).
13. Creature and decor models: orientation (a creature looks along its path), scale; icicles and vines not
    reading as blocking the way; server props not in the way of a real walk to each station.
14. The Roof: stars under the band's Atmosphere (Density 0.15), the skyline at 260-480 studs, fireworks.
15. The door slide (the leaf simply rises 7.8 studs and turns invisible), sparkle, flash and FOV punch.
16. The lift illusion: teleport between cabs with the entry door opening 0.6 s later; camera snap?
17. `Config.Studio.StartSlot` works in Studio (API access off) and is inert when published.
18. Glyphs in Gotham: ★ ☆ ☕ ⚠ ▶ ⌫ ● ○ · (Fork Tower saw U+1FAA8 draw as an empty box).
19. Colour-blind check: flask letters and lamp lit/unlit (● bright vs ○ dark) in greyscale.
20. Real human times to replace every pacing assumption, then retune (profiles first, then the table).
21. Game settings: Max Players 8 (the zone count follows it); `Workspace.StreamingEnabled = false` arrives
    through `default.project.json` (check it after `rojo build`).
22. The Solo Lift's doors are now the RIDER's own local part (REVIEW-1 A2): does a client-side `CanCollide`
    part stop the local character walking out (it should: the client simulates its own character), with no
    rubber-banding on the server's view? Does nobody else see or bump into it? They appear and vanish (no
    slide): does the shut cab read as a lift leaving? A rider standing exactly in the doorway: pushed in or out?
23. The rooms' ATRIUM buttons with a 0.5 s hold on touch: the hold ring reads, and nobody leaves by accident.
24. The friends board with real latency: one reader per server; how long a 200-friend view takes with several
    players asking at once (headless: 99 s for two 200-friend views at 0.25 s per read).
25. (review-1, reviewer B) Roblox's default prompt `Exclusivity` (OnePerButton) may show only one of NEXT and
    ATRIUM, 4 studs apart in the exit cab: both must be reachable on touch and keyboard.
26. (review-1, reviewer B) The Roof's rails are 3.5 studs, under the default 7.2-stud jump: a player can jump
    them and fall ~130 studs onto the Atrium's roof or into the void (then a respawn on AtriumSpawn). Acceptable,
    or an invisible guard?
27. (review-1, reviewer B) BackDown is 8.02 studs from the Roof arrival point with an 8-stud reach, behind the
    player: does a new escapee find the way down?
28. The hazard ring now stands still from its first frame (REVIEW-1 B1): does the drop still read as coming for
    you, and is the 2.1 s from ring to hit enough on a phone?
29. A pair's shared Clean/Unaided stars (REVIEW-1 A4): does the escape card's "a wrong try in your pair" read as
    fair to the partner who made none?

## 9. Thumbnail shot list (1920 x 1080)

Staging: a Studio copy built with `rojo build`, Studio API access OFF (nothing saves), `Config.Studio.StartSlot`
set in the copy to pick the room. Room-local coordinates: add the room's origin (zone 1 is (300, 0, 0); the
`RoomState` payload carries it). No game number is edited except where a shot says so, in the unsaved copy.

1. **"Crack the code"** (Archive, StartSlot 5): the avatar at (-8, 0, -11) facing the door board at
   (-10, 8, -15.75); camera at (4, 7, -2) looking at (-9, 7, -15). In frame: the board with its lit lines and
   one dark `? ? ?` row, the amber fixture, moths circling it at y 13, paper drifting, the banker's lamp.
2. **"Step out of the ring"** (Cold Storage, StartSlot 10; this copy only: `Hazards.IntervalMin/Max = 8/10`):
   the avatar mid-step out of the red ring, the ice drone 4 studs above, snow; camera low at (0, 3, 6)
   looking up at (-2, 7, -2).
3. **"Two heads"** (Greenhouse, StartSlot 8, two Studio clients through the Pair Lift): both avatars at the
   west Flask Shelf (room 8's feeder A), one pointing; butterflies, glass panes; camera at (-4, 6, 6)
   looking at (-13, 5, 0).
4. **"The Reactor opens"** (StartSlot 13): the door just risen, teal and violet neon, steam and sparks; camera
   at (0, 5, 4) looking at (0, 6, -16).
5. **"You escaped the Lab"** (the Roof, after room 15): the avatar at the north railing (0, 150, -20); camera
   behind and above at (0, 158, 8) looking at (0, 140, -300): the lit towers, 3000 stars, a firework burst.
6. **Icon** (512 x 512): the keypad close up at (7, 5, -15.75) showing `? ? ?`, one lit lock lamp above the door.

## 10. The templates, and every adaptation (with its reason)

- **Verbatim**: `EnvBands.luau`, `Hazards.luau`, `Rest.luau`, `Responsive.luau`, `FxClient.luau` and their
  specs; `Rng.luau` is fork-tower's (with `below`).
- **Hazards**: config + glue only. `pitch = 85`, `pitchSpread = 0`, `SpreadDegrees = 0`, `KnockLift = 0`, and
  `ctx.pitch = rad(85)` in the glue (why: indoors, a lane cannot start on screen at a distance; §3).
  `commit = telegraph` (REVIEW-1 B1: a 4 studs/s ceiling drop touches the zone 0.875 s before arrival, so the
  template's 1.5 s of tracking left no dodge window before 1.45 s; the lane now locks on its first frame).
  The exposed-time rule is the glue's: `resting` everywhere a hazard may not be released, i.e. outside a room's
  interior (Atrium, cabs, Roof), off a legal spot (5 studs from both doorways, 1 from the walls) and in the 8 s
  arrival grace (REVIEW-1 B4: `grounded = false` there held a due hazard and released it at the grace's end).
  `IntervalMin/Max = 80/120` instead of the template's 120/180: that exposed time is about two thirds of what it
  was, and 80-120 keeps one per 2-3 minutes of play (§3).
- **Rest**: `IdleSeconds = 0` (§4); opening a station ends a Break (a game rule on top of the template).
- **Ambient life**: the template's `ambientSpawn` ring (70-900 studs) cannot place life in a 32-stud room, so
  `Decor.critterPos` flies bounded loops; `EnvBands.luau` itself is untouched.
- **Fx**: anomaly-observatory's `Fx.luau` plus one preset, `Lab`, equal to band 1.
- **The Break button and the hazard banner live in Hud.client** (not in the glue, as in +1 Jump), so one
  layout places every 2D control and the HUD check measures them all.

## 11. Open

- REVIEW-1 B5, not changed: the public top 10 freezes once ten players reach 45. Measured with the shipped
  `Board`: ten 45-star entries at launch, then one an hour later and one a year later: neither later player is
  on the board. It follows from the owner's standard (an un-inflatable metric, ties to the FIRST to reach it) on
  a metric capped at 45; a seasonal board or another metric is the owner's call. The friends view still compares.
- Everything in §8. Nothing has been seen rendered.
- The solver-bot residual, measured: a script on a hostile client reached 45 stars 62 s after joining. With
  ties to the first, a bot that reaches 45 before ten real players have keeps a top-10 public row for good.
  The friends board is unaffected; removing a row would be a manual `RemoveAsync` on the ordered store.
- The hazard telegraph without a lane on screen (§3) is the biggest feel risk; if it reads badly, the first
  lever is a longer telegraph (the lane must still start under the ceiling: `speed x telegraph <= 12`).
