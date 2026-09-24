# +1 Jump — the sky you climb into

Owner's brief (Gustav, 2026-09-17): richer, never monotonous; climb from the temple into the sky,
out into space and out of the galaxy; rare, telegraphed hazards that knock you down; space in about
30-45 minutes for a normal player; a way to rest that can never be exploited; a thumbnail shot list.

**State: built, unit-tested, headless-tested, mutation-tested, adversarially reviewed twice. Round 1 found 8
issues, all closed test-first (§12). Round 2 reviewed those fixes and found 4 more (1 high, 1 medium, 2 low),
all reproduced first and closed test-first (§14). NOT yet seen in Studio.** Nothing was committed, pushed or
published. The round-2 fixes have not had their own independent review.

**Resumed after the owner's 45-minute pause (§13).** The build was stopped while this file was being
written. The resume session re-read every file, rebuilt the bundle (byte-identical to the one on disk),
re-ran every gate (all green, counts in §7), and ran a probe sweep of 13 NEW mutations aimed at promises
in §2-§6 that round 1 never mutated. Three survived: critters that never recycle, scenery that cuts
instead of gliding on a teleport, and a suit light that never lights. All three are now held by
`robloxemu/check_plus1jump_life.luau`. It was watched failing on each mutant, and a control edit still
survives. The shot list (§9) got operational fixes that would otherwise have cost the night session its
hazard shot and its space fanfare. No game code changed in the resume session.

**Review round 2 (§14).** (1, high) Only a step at right angles to a hazard's lane dodged it: backing away,
or leaving the red ring along the lane, was still a hit. The red ring is now the rule: a hit needs you inside
it, so leaving it in any direction dodges. (2, medium) Round 1 had dimmed the REBIRTH button for every rebirth
after the first, changing an existing mechanic's HUD without the owner. The default is back to the HUD before
the sky (every rebirth lit), and the first-only rule is a one-line option for him, with both measured.
(3, low) A profile load slower than 15 s showed a returning space climber a TEMPLE card and a repeat
"YOU REACHED SPACE!"; the settle clocks now start when the profile has loaded. (4, low) The weather emitter
budget was not enforced in code (5 on at once after fast teleports); it is now capped at 2.

---

## 1. What changed

| file | what |
|---|---|
| `src/shared/EnvBands.luau` | **template** — progress value → band + eased blend, layers, frame-rate-independent smoothing, announcer, world tiling, ambient spawn ring, `pathDistance` / `keepClear` (scenery stays off the play path), `capRates` (the weather budget, review round 2). Pure. |
| `src/shared/Hazards.luau` | **template** — rare, telegraphed, tracking-then-locked, one-at-a-time hazard scheduler; lanes START ON SCREEN (`viewWindow`, `pickKind`); the danger ZONE (`zone`, `inZone`: the ring the client draws, review round 2); swept hit test that needs the player inside the zone; capped knock; bearing. Pure. |
| `src/shared/Rest.luau` | **template** — rest rules: manual + idle, queued when unsafe (a dodge keeps the request), wake on move, freezes (never resets) hazard clocks. Pure. |
| `src/shared/Progression.luau` | + `climbHeight`, `tierProgressAtY`, `yAtProgress` (altitude ↔ tiers climbed), `tierAtY` (the tier NUMBER the HUD shows), `rebirthHighlighted` (when the HUD lights REBIRTH). |
| `src/shared/TowerGen.luau` | + `platformCentres` (world positions of the tower, stacked the way the server builds it). |
| `src/shared/Config.luau` | + `Tower.BaseY`, `Env` (8 bands, 2 layers, critters, `FloorBelowRoot`, `IslandTopBelowPad`, `SceneryClearance`), `Hazards` (10 kinds, `SpreadDegrees`, `ViewPitchDegrees`, `KindFitDegrees`), `Rest`, `Pacing` (model assumptions, `RescueLatencySeconds`), `Budget` (+ `MaxWeatherEmitters`, round 2), `Rebirth.HighlightFirstRebirths` / `HighlightAgainAtBestTier` (round 2: default `math.huge` = every rebirth lit, as before the sky; `1` is the owner's option). |
| `src/shared/SkyArt.luau` | +1 Jump's scenery, critters, hazard models, weather, lightning — code-only, pooled, client-only. |
| `src/client/Sky.client.luau` | the glue: altitude → bands → Lighting/scenery/life/weather; hazards + knock; rest + UI; title cards. |
| `src/client/Hud.client.luau` | band emoji next to Best and on the top-10 board (`85 🚀`); REBIRTH lit when `rebirthHighlighted` says so (default: every rebirth the server allows, as before the sky); the next multiplier read from `Config.Rebirth.Multipliers` (the old text said `4x` where rebirth #2 gives `5x`). |
| `src/server/Main.server.luau` | ONE line: `BASE_POS` reads `Config.Tower.BaseY` (still 8). Nothing else on the server, in either round. |
| `tests/` | specs `EnvBands` `Hazards` `Rest` `Altitude` `EnvConfig` `Pacing` + `ClimbModel.luau` (test-side model); review round 1 extended `Progression` and `TowerGen` too. |
| `robloxemu/check_plus1_sky.luau`, `check_plus1_sky_rejoin.luau` | headless glue checks (round 0). `check_plus1.luau` also loads `Sky.client`. |
| `robloxemu/check_plus1jump_{hazards,rest,join,bands,world,leftout,rebirth}.luau` | headless glue checks for the review findings (§12). |
| `robloxemu/check_plus1jump_life.luau` | resume session (§13): critters keep recycling around the climber, scenery glides on a teleport, the suit light lights in space. |
| `robloxemu/check_plus1jump_{dodge,slowload,budget}.luau` | review round 2 (§14): leaving the drawn ring in any direction dodges; 16-40 s profile loads and a placement 20 s late; the budgets under 400 fast teleports. `check_plus1jump_rebirth.luau` was rewritten for the restored default, and `tests/ClimbModel.luau` gained `dodgeDegrees`. |

---

## 2. The bands and what triggers them

**Trigger: altitude, never time.** Every frame the client converts its own character's height into two
numbers, both the game's real progress (you cannot be at tier 85's height without having climbed there):

* **tiers climbed** (`Progression.tierProgressAtY`; standing on platform *i* of tier *t* reads
  `(t-1) + i/6`) drives every BLEND: lighting, atmosphere, scenery, critters, weather. Checked against
  every platform the real server builds (`check_plus1_sky` §1, worst error < 1e-6);
* the **tier number** (`Progression.tierAtY`, from the floor under the root part) NAMES the band: the
  chip, the title cards, which hazards fly. It is the number the server credits and the HUD and top-10
  board show, so "Tier 85", "⭐ Best: 85 🚀" and the sky always agree (review finding 7).

**Transitions never cut.** A band blends in over `fade` tiers *before* its `from`, eased with a
smoothstep (continuity measured: no band weight moves more than 0.01 per 0.01 tier). On top, every
written value glides with a 0.6 s half-life, so a *jump* in altitude — the fall rescue, a rebirth
back to the pad, joining at tier 90 — also glides: measured, a temple → space teleport moves
`ClockTime` 15.5 → 23.0 with no single write above 11 % of the change, and no overshoot. The scenery
glides the same way: teleported temple → orbit and back (a join at tier 90, a rebirth to the pad), the
island and the Earth cross-fade over about 3 s, and no part's transparency moves more than 0.04 in one
frame (`check_plus1jump_life`). Lighting is written at most 10×/s and only when a value changed.

Minutes = minutes of play to STAND on the first platform of the band's tier (rest excluded), measured by
`tests/Pacing.spec.luau`. "Option follower" = a normal player who presses REBIRTH every time it is lit with
the owner's first-only option (`Config.Rebirth.HighlightFirstRebirths = 1`): exactly one rebirth, at tier 10.
With the default HUD (every rebirth lit, as before the sky) the same player takes ten rebirths before space
and reaches it after 227.4 min (review round 2, below and §14).

| # | band | starts at Tier | y (first platform) | normal | option follower (= rebirth @10) | fast | slow | the sky | scenery | life | weather | hazards |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 🏛️ Temple Grounds | 0 | 8 | 0.0 min | 0.0 | 0.0 | 0.0 | bright afternoon (= server's Temple preset), sun rays | floating temple island 320 studs below the pad, carried up to the pad by a marble column: grass, 8 pillars, red gate, blossom trees, waterfall | a few birds | cherry petals | none |
| 2 | 🌳 Treetops | 7 (fade 3) | 433 | 2.1 | 5.8 | 1.1 | 4.1 | green-tinted daylight | forest canopy far below, under the island (tiled) + island | bird flocks | petals | bird |
| 3 | ☁️ Cloud Sea | 15 (fade 4) | 1 833 | 5.2 | 9.2 | 2.8 | 9.9 | warm, low golden sun, glare | **cloud deck at tier 22 (y ≈ 3 872) you climb THROUGH** (whiteout layer); the tower rises through a clear shaft, every cloud ≥ 40 studs off the climb | hot-air balloons, airliner with contrail, birds | mist | bird, plane |
| 4 | ⛈️ Storm Front | 35 (fade 6) | 7 084 | 13.5 | 17.5 | 7.6 | 25.3 | sunset orange/violet, high contrast | **dark storm deck at tier 42 (y ≈ 9 152)**, same 40-stud shaft + lightning bolts & flashes | jets with contrails, rising weather balloons | rain | jet, weather balloon |
| 5 | 🌠 Edge of Space | 60 (fade 8) | 13 684 | 24.0 | 28.0 | 13.6 | 44.6 | blue hour, first 1 500 stars | aurora ribbons, sunset glow disc far below | tumbling rocket stage, meteors | ice glints | weather balloon, rocket stage |
| 6 | 🚀 **SPACE · Low Orbit** | **85** (fade 8) | **20 284** | **34.4** | **38.4** | 19.7 | 63.8 | night, 3 500 stars, no haze | Earth + cloud shell + airglow below, space station (ring, panels), aurora | satellites, drifting astronaut, space junk | stardust | space junk, astronaut |
| 7 | 🪐 Deep Space | 140 (fade 12) | 34 804 | 57.4 | 61.4 | 32.9 | 106.2 | 5 000 stars, violet grade | ringed planet + moon, nebula clouds | asteroid field, spaceship fly-bys | stardust | asteroid, spaceship |
| 8 | 🌌 Beyond the Galaxy | 240 (fade 16) | 61 204 | 99.1 | 103.1 | 56.9 | 183.1 | deepest grade, strongest bloom | spiral galaxy below (discs, core, curved arms), nebulae | comets, asteroids | stardust | comet, asteroid |

**Rebirth and the space target (review round 1 finding 2, round 2 finding 2): an owner decision.** Rebirth
sends the climber back to the pad and, with the jump capped at 60 studs and every tier reachable without it
(the reachability invariant), it never makes the climb faster. Measured with the same model: rebirth at 10 →
space at 38.4 min; at 10 and 18 → 46.0; at 10, 18, 26 → 56.9; every rebirth offered before tier 85 (ten of
them) → 227.4. Before the sky, the HUD lit the button purple every time a rebirth was possible, so a normal
player who followed it missed the owner's window. Round 1 dimmed every rebirth after the first. Round 2 found
that this changed the HUD of an existing mechanic (rebirth at 10/18/26) without the owner, so **the default is
back to the HUD before the sky: every rebirth the server allows is lit** (`REBIRTH → 5x?`, purple; the
corrected multiplier text stays). The first-only rule is kept as a one-line option:
`Config.Rebirth.HighlightFirstRebirths = 1` lights only the first rebirth, then again once the best tier
reaches **Tier 240**, and a player who presses the button whenever it is lit then reaches space in 38.4 min
and the galaxy in 103.1. `Pacing.spec` measures both: the option follower inside 30-45 min, the default
follower outside it (227.4), so the choice put to the owner stays true (§11). `check_plus1jump_rebirth`
drives both through the real server and HUD. The deeper question (should the multiplier make re-climbing
faster at all?) is his too.

Also on screen: a band chip under the jump counter (`☁️ Cloud Sea · 🚀 Space in 62`, counted in tiers), a
title card on entering a new band (`🚀 YOU REACHED SPACE!` with a white flash and FOV punch when you LAND on
Tier 85 during play — flying past its height on a jump that misses says nothing; a returning space player
gets a quiet `🚀 SPACE · LOW ORBIT` instead, however slowly their profile loads — `check_plus1jump_join` up to
6 s, `check_plus1jump_slowload` at 16 and 40 s and with a placement 20 s late, review round 2),
a soft suit light on the character once the sky goes dark, and the band emoji next to every tier on the
top-10 board and next to Best — the brag.

### What "normal player" assumes

There is no telemetry yet, so time-to-altitude is a **model built from the game's own climb model**,
with the human part written down in `Config.Pacing.Profiles` instead of hidden in a number:

* the tower is the real one: `Progression.stepHeight/jumpHeight/climbHeight` from `Config.Tower/Jump`;
* airtime is ballistic Roblox physics for that tier's jump height and step (gravity 196.2);
* **normal** = 1.5 s lining up each jump, misses 20 % of jumps, 1.5 s to recover after the rescue; a
  miss costs the fall to the server's rescue line (60 studs under the tier) plus half its 0.4 s poll;
* hazard hits are included at the **measured** rate for a climber who ignores every warning (§3);
* no codes, rest time excluded; rebirths as stated per row;
* fast = 0.8 s / 8 % / 1.0 s; slow = 2.5 s / 35 % / 2.0 s — printed to show the sensitivity.

Asserted: normal reaches space in 30-45 min (34.4), still does with the first rebirth (38.4) and as a
follower of the lit button with the owner's first-only option (38.4), and sits within 5 min of the window's
centre, so a retune that drifts fails loudly; with the default HUD that follower misses the window (227.4,
asserted, so the owner decision in §11 stays true); the galaxy is at least twice the time to space but under
3 h, for the option follower too; every band lasts ≥ 2 min;
the last band starts below 100 000 studs. **When real session data exists, retune `Profiles.normal`
first, then the `from` numbers — the spec tells you where space lands.**

---

## 3. Hazards and their measured rarity

| kind | band(s) | speed | warning | lane locks | hitbox (model) | knock |
|---|---|---|---|---|---|---|
| bird | treetops, cloud sea | 34 | 3.0 s | 1.5 s before | 1.8 (2.5) | 38 |
| plane (prop) | cloud sea | 70 | 3.0 s | 1.5 s | 2.4 (9) | 50 |
| jet | storm | 120 | 3.2 s | 1.7 s | 2.4 (10) | 58 |
| weather balloon (rises from below) | storm, edge | 16 | 3.5 s | 2.0 s | 2.2 (5) | 30 |
| rocket stage (tumbling down) | edge | 42 | 3.0 s | 1.5 s | 2.4 (8) | 48 |
| space junk | orbit | 50 | 3.0 s | 1.5 s | 1.8 (3) | 42 |
| astronaut (drifting) | orbit | 14 | 3.6 s | 2.0 s | 2.2 (3) | 26 |
| asteroid | deep, galaxy | 36 | 3.2 s | 1.7 s | 2.4 (7) | 48 |
| spaceship | deep | 100 | 3.0 s | 1.5 s | 2.4 (8) | 55 |
| comet | galaxy | 80 | 3.0 s | 1.5 s | 2.4 (6) | 52 |

**Rules** (`Hazards.luau`, validated at load; an invalid config switches hazards OFF with a warning):

* one hazard every **120-180 s of climbing**, on a clock that only runs while you are not resting;
  never two at once; none in the temple band; a due hazard in a quiet band is re-rolled, so entering a
  hazard band never releases a backlog;
* it launches only while you stand on something (checked through the real client since review round 1);
* **it starts ON SCREEN** (review finding 1): within ±35° left/right of where the camera looks (a 4:3
  tablet shows ±43°) AND within ±20° above/below the camera's pitch (the screen shows ±35°). The camera
  sits behind the player, so a lane that starts on screen stays on screen all the way in. Each kind keeps
  its character where it can: a kind whose natural climb angle would have to be bent more than 25° to
  fit the view is swapped for one of the band's kinds that fits (looking up in the storm you get jets
  diving in, looking down you get weather balloons rising); when no kind fits, the lane is bent into
  view. Hard limits in `Hazards.validate`: `ViewPitchDegrees` ≤ 30, `SpreadDegrees` ≤ 40;
* **telegraph**: an always-on-top ⚠️ billboard on the hazard (visible through cloud), a blinking red
  light, a lane line from the hazard through you (yellow while it tracks you), a ring at your feet (the danger zone),
  and a HUD banner `⚠️ PLANE INCOMING ◀` with a direction arrow. While the warning runs the lane
  re-aims at you (it visibly comes *for* you); **1.5-2 s before arrival it LOCKS** — line and ring turn
  red, banner says `⚠️ MOVE! PLANE ◀`. The arrival time never moves, so the warning never shortens. A
  lane that would have to chase you faster than 1.5× its speed (a teleport, a fall) locks instead;
* hitboxes are smaller than the models. **The red ring is the danger zone** (review round 2): its radius is
  hitbox + player radius, it is centred where you stood when the lane locked, and a hit needs you INSIDE it
  as well as the hazard passing within reach. The radius is under half a tile, so **stepping out of the ring
  in any direction dodges every kind**: backing away, stepping aside, walking toward the hazard, or jumping on
  to the next platform (at least 8 studs away). Spec'd for every kind at every 10°, measured on the real
  tower in 8 directions, and through the real client in the 8 W/A/S/D directions. Before round 2 the hit test
  was the whole flight, a corridor along the lane, and only a step at right angles to it dodged;
* a hit: horizontal push away from the lane + 10 studs/s lift (0.25 studs of height — it can never
  carry you up onto a platform), `PlatformStand` for 0.9 s so the push actually carries, camera shake +
  white flash. You fall; **the server's existing fall rescue puts you back on the platform you last
  earned**. Nothing is lost.

**Measured:**

| measurement | where | result |
|---|---|---|
| raw scheduler, 20 h of climbing | `Hazards.spec` | 477 hazards = **one per 150.9 s** (0.398/min); gaps 120.5-180.0 s; max 1 in the air |
| on the real tower, normal rhythm, 6 h from tier 20, camera looking 20° up — climber who **stops and sidesteps half a tile at the lock** | `Pacing.spec` | 0.394 hazards/min, **0.394 near-hits/min (one per 2.5 min, ≤ 8 studs)**, **0 hits** |
| same, climber who **ignores every warning** and keeps climbing | `Pacing.spec` | 0.192 near-hits/min, 0.103 hits/min (**one hit per 10 min**), hit share 0.26 (unchanged by round 2) |
| same climber, walking half a tile at the lock in 8 directions measured from the lane's travel (0° = straight back), 3 h each | `Pacing.spec` | **0 hits of 71 in every direction** (before round 2: 0° 71, 45° 65, 90° 24, 135° 65, 180° 71, 225° 69, 270° 21, 315° 69) |
| walk out of the ring at WalkSpeed, every kind × 3 camera pitches × every 10° | `Hazards.spec` | **324 of 324 dodge**; 9 of 9 who stay put are hit (before round 2: 67 of 324 dodged) |
| through the real client: walk out of the DRAWN ring in the camera's 8 W/A/S/D directions, 7 hazard bands | `check_plus1jump_dodge` | **0 of 56 walkers hit**, 14 of 14 who stayed put hit; ring as wide as the zone and centred where they stood (before round 2: 41-42 of 56 hit, S and W 7 of 7; ring up to 1.17 studs off) |
| on screen: every band's kinds, camera pitch -60..60°, 16:9 and 4:3, 4° margin | `EnvConfig.spec`, `Hazards.spec` | 5 880 + 5 400 launches, **every one on screen from launch until its lane locks** (with the camera pitch ignored: 2 394 of 5 400 off screen; the reviewer measured balloons on screen 0 % of the time with a level or raised camera on the old rule) |
| on screen through the real client: storm, edge and galaxy × pitch -40/-20/0/+20/+40 (1280×720) and ±35 (1024×768), 8 hazards each | `check_plus1jump_hazards` | **every frame of every INCOMING warning on screen** (old build: up to 120 of 120 frames off screen, e.g. storm at +20°) |
| through the real client, 20 simulated minutes, standing in the lane | `check_plus1_sky` | 7-8 hazards per 20 min (the emulator's `Random` is unseeded; the resume session saw 7); never 2 at once; only the band's kinds; every hazard visible ≥ 3 s before it hit; knock ≥ 20 studs/s sideways, ≤ 15 up; rescued to the earned platform within 0.5 studs |
| rest-toggle exploit probe (6 h climbing) | `Hazards.spec` | never rests: 142 · toggles every 7 s: **142** · rests 40 s of every 150 s: **142** |

"About one near-hit per 2-3 minutes" therefore holds for a player who reacts to the warning (which
is what the warning is for); a player who ignores warnings gets a close pass about every 5 min and is
knocked off about every 10 min. Since round 2, reacting always helps: any step out of the ring dodges.

---

## 4. Rest — what "pause" means in +1 Jump

A Roblox server cannot stop the world for one player, so **rest is a state the player is in**:

* **☕ Rest button** (top centre, thumb-sized on touch): you sit down on your platform, the view softens
  (depth of field), the chip says `☕ Resting — the sky leaves you alone`. Press again (`▶ Climb`) or
  just move to carry on.
* **Idle rest**: stand still for 20 s and hazards leave you alone (`💤 Idle`) — AFK-safe. You are not
  sat down.
* While resting: no hazard launches, the hazard clock **freezes**, the sky, birds, balloons,
  satellites and weather keep going. Nothing is lost, nothing is earned.
* Roblox's own idle disconnect (about 20 minutes with no input) still applies to a resting player; the game
  cannot and does not stop it. Nothing is lost then either: the frontier is autosaved every 20 s and on
  leaving, and a rejoin puts the climber back on their platform (`check_plus1_rejoin`).

**Why it cannot be exploited**

1. **There is nothing to dodge.** +1 Jump has no round clock, no raid, no timed leaderboard (the board
   is *best tier*), no penalty. The only thing rest pauses is hazards, and a hazard takes nothing.
2. **You cannot climb while resting.** Earning is the server's platform `Touched` handler and needs
   movement; any movement (walk input, jump, leaving the ground) wakes you. `Rest.validate` rejects a
   config with `WakeOnMove = false`.
3. **Not a panic button.** Rest cannot *start* in the air or with a hazard inbound
   (`BlockWhileThreat` is mandatory in `Rest.validate`). Pressing it then *queues* the request (`☕ …`):
   the hazard still arrives; **walking out of its ring, as the warning says, keeps the request** and the rest
   begins the first moment the sky is clear and you stand still (review finding 6 — before, the first
   step cancelled it); if it hits you, the request is void; walking on under a clear sky for more than
   0.4 s drops it (you chose to climb on); it expires after 10 s, which outlives the longest hazard
   flight (7.6 s) by 2.4 s (`EnvConfig.spec`). Rest never removes a hazard already in flight.
4. **Toggling does not thin hazards.** Rest *freezes* the climbing clock, it never resets it —
   measured identical counts per climbing hour (142/142/142 above), and through the real client the
   next hazard after a **10-minute rest** came 120-180 *climbing* seconds after the previous one.
5. **A hazard due while you are airborne does not fire into your rest when you land** — it waits,
   frozen, and launches when you climb on (spec'd; the mutation that breaks it is killed).

---

## 5. Client vs server, and why

| what | where | why |
|---|---|---|
| bands, lighting, sky, scenery, critters, weather, lightning, title cards, band chip | **client** (`Sky.client` + `SkyArt`) | cosmetic and per-player (your sky follows *your* altitude); costs the server nothing, replicates nothing |
| hazards: schedule, telegraph, hit test, knock | **client** | harms only the local player, whose character physics the client already owns. The server trusts nothing from it: progress is still only the server's `Touched` on server platforms; the knock's lift is capped so it cannot lift anyone onto a platform; an exploiter who deletes hazards gains nothing a flying exploit didn't already give |
| rest | **client** | it only pauses client hazards |
| progress, rebirth, leaderboard, saves, **fall rescue** | **server** (unchanged) | authoritative, as before |
| band emoji on HUD/leaderboard, when REBIRTH is lit | client (`Hud.client`) | derived from tier numbers already on the board, in leaderstats and in the player's own state |

**Leak review.** The client reads its own character's position, its own camera, its own
`leaderstats.Tier` (to know its profile has loaded before the first title card) and `Config` (already
replicated), and computes the tower's path from `TowerGen` + `Config.WorldSeed` (the same public numbers
the server builds from). It fires no remote, adds no remote, sets no attribute on anything the server
built, and every part it creates is local and non-collidable, non-queryable, non-touchable (the camera
never pops in front of a cloud, nothing can be stood on). `check_plus1_sky` §9 asserts all of that.
Spawn order (`robloxemu/SPAWN-ORDER.md`) is untouched: the client never writes the character's CFrame
at spawn. `check_plus1_spawn` and `check_plus1_rejoin` are byte-identical to before this work and green.
`Main.server.luau` differs by exactly one line, `BASE_POS` reading `Config.Tower.BaseY` (still 8). Its
`onCharacter` wait-for-parent and its fall rescue are unchanged, and the rejoin checks confirm the server
still places a tier-90 climber on their own platform, fast or slow load. (An earlier draft of this
paragraph called `Main.server.luau` byte-identical. `git diff` says one line, as §1 does.)

**What other players see.** Hazards are local, so when you are knocked off, other players see you fall
with nothing hitting you. That is the price of keeping hazards off the server, and nothing is lost by it.
Whether it reads as odd in a busy server is on the Studio list (§8).

---

## 6. Budgets (measured, `check_plus1_sky`)

Client-built only; the server builds none of this. Measured after 8 s at the middle of every band and
at the midpoint of every seam (both bands live), plus every frame a hazard was in flight. Re-measured
after the review fixes: identical.

| where | parts | emitters (rate) | beams | trails | lights |
|---|---|---|---|---|---|
| temple | 32 | 1 (6/s) | 0 | 0 | 0 |
| temple › treetops | 76 | 1 (5/s) | 0 | 0 | 0 |
| treetops | 82 | 1 (4/s) | 0 | 0 | 0 |
| **treetops › cloud sea** | **130** | 2 (4/s) | 0 | 1 | 0 |
| cloud sea | 66 | 1 (4/s) | 0 | 1 | 0 |
| cloud sea › storm | 95 | 2 (22/s) | 0 | 1 | 0 |
| storm | 46 | 1 (**40/s**) | 0 | 1 | 0 |
| storm › edge | 48 | 2 (25/s) | 3 | 1 | 1 |
| edge | 10 | 1 (10/s) | 3 | 2 | 1 |
| edge › orbit | 34 | 2 (7/s) | 3 | 1 | 1 |
| orbit | 36 | 1 (5/s) | 3 | 0 | 1 |
| orbit › deep | 46 | 1 (5/s) | 3 | 1 | 1 |
| deep | 28 | 1 (6/s) | 0 | 1 | 1 |
| deep › galaxy | 24 | 1 (7/s) | 4 | 1 | 1 |
| galaxy | 18 | 1 (8/s) | 4 | 1 | 1 |

| metric | measured peak | budget (`Config.Budget`) |
|---|---|---|
| local parts | **134** (a bird in flight at the treetops › cloud-sea seam) | 220 |
| particle emitters | 2 | 4 |
| particles per second | **40** (storm rain) | 60 |
| beams | 4 (galaxy arms) | 8 |
| trails | 2 (3 with a hazard every 4 s, reviewer's probe) | 8 |
| point lights | 2 (suit light + hazard blink) | 3 |
| hazards at once | 1 | 1 |

The reviewer's finer sweep (p 0 → 262 in 0.1 steps), re-run on the fixed build: peak 130 parts (134
with a hazard every 4 s); teleports between far bands peak at 163-168 parts and 3 emitters; after 40
temple ↔ galaxy ↔ seam cycles the pools grew by 5 instances in total. All under budget.

**What is pooled / how it stays cheap:** scenery is built the first time a band needs it and
**unparented** when its weight reaches 0 (a band you are not in costs no draw calls — asserted per
band); the canopy and both cloud decks are world-fixed tiles that only reposition when the camera
crosses a cell, and deck clouds that would come within 40 studs of the climb are shrunk or left out
(unparented, and they stay out when the band returns — `check_plus1jump_world`); critters are pooled per
kind, faded in, recycled when they leave range, spawned at most one group per frame; one model per
hazard kind; one lane + one ring; one weather host with emitters created lazily (at most
`Budget.MaxWeatherEmitters` = 2 enabled, the strongest by rate, summed rate capped at `MaxEmitterRate` = 60/s,
enforced in code by `EnvBands.capRates` since review round 2; rate scaled by band weight); a 5-part lightning pool. Per frame: ≤ ~20 sky-piece and ≤ ~30 critter
CFrame writes; Lighting ≤ 10 writes/s, only on change. These are part/emitter counts, not FPS — frame
time on a real phone is on the Studio list.

The pool really does recycle, measured through the real client in `check_plus1jump_life`. A climber who
stays 90 s in the treetops keeps 8-10 of the band's 10 birds in range the whole time, and after a
2 600-stud climb through the cloud sea the balloons are back around them in 1.1 s. With recycling
switched off, birds in range drop to 0 and every other suite stays green.

**Under fast altitude changes (review round 2, `check_plus1jump_budget`).** The reviewer's stress run is now a
check that asserts the budgets on every frame: 400 cycles of random teleports between tiers 0 and 300 or 6 s
climbs, with a hazard every 6-7 s. Before the cap it switched 5 weather emitters on at once (cycle 95, a
teleport from 15 to 54 tiers climbed). After it: peak 2 emitters and 40 particles/s, 174-180 parts (budget
220), 7 beams (8), 3 trails (8), 1 light (3); 382 unique instances in total. Normal play crosses at most two
bands at a time, so a climber never had more than the pair; the cap matters for dev teleports and the shot
list's hops. Which hazard kind a band launches comes from the emulator's unseeded `Random`, so a kind can fly
for the first time late in the run; the check therefore does not assert "nothing new after cycle 200" (that
failed 1 run in 15 in the first draft) but that everything built after cycle 200 is the single model of a
hazard kind flying for the first time, and that each kind's model is built once (20 of 20 runs green).

---

## 7. Gates

| gate | before the sky | after round 0 | after review round 1 | resume session (re-run) | after review round 2 |
|---|---|---|---|---|---|
| `tests/Codes.spec` | 12 / 0 | 12 / 0 | 12 / 0 | 12 / 0 | 12 / 0 |
| `tests/Progression.spec` | 28 / 0 | 28 / 0 | **37 / 0** | 37 / 0 | **38 / 0** |
| `tests/Rng.spec` | 56 / 0 | 56 / 0 | 56 / 0 | 56 / 0 | 56 / 0 |
| `tests/TowerGen.spec` | 15 / 0 | 15 / 0 | **21 / 0** | 21 / 0 | 21 / 0 |
| `tests/responsive.spec` | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 | 70 / 0 |
| `tests/EnvBands.spec` | — | 99 / 0 | **110 / 0** | 110 / 0 | **124 / 0** |
| `tests/Hazards.spec` | — | 76 / 0 | **88 / 0** | 88 / 0 | **102 / 0** |
| `tests/Rest.spec` | — | 47 / 0 | **55 / 0** | 55 / 0 | 55 / 0 |
| `tests/Altitude.spec` | — | 16 / 0 | **21 / 0** | 21 / 0 | 21 / 0 |
| `tests/EnvConfig.spec` | — | 60 / 0 | **65 / 0** | 65 / 0 | **67 / 0** |
| `tests/Pacing.spec` | — | 21 / 0 | **26 / 0** | 26 / 0 | **28 / 0** |
| **spec total** | **181 / 0** | **500 / 0** | **561 / 0** | **561 / 0** | **594 / 0** |
| `robloxemu/check_plus1` (HUD fit, 10 viewports, overlap on) | PASS | PASS | PASS | PASS | PASS |
| `robloxemu/check_plus1_rejoin` | 8 / 0 | 8 / 0 | 8 / 0 | 8 / 0 | 8 / 0 |
| `robloxemu/check_plus1_spawn` | 25 / 0 | 25 / 0 | 25 / 0 | 25 / 0 | 25 / 0 |
| `robloxemu/check_plus1_sky` | — | 242 / 0 | 242 / 0 (file unchanged) | 242 / 0 | 242 / 0 (file unchanged) |
| `robloxemu/check_plus1_sky_rejoin` | — | 13 / 0 | 13 / 0 (file unchanged) | 13 / 0 | 13 / 0 (file unchanged) |
| `robloxemu/check_plus1jump_hazards` | — | — | **6 / 0** | 6 / 0 | 6 / 0 |
| `robloxemu/check_plus1jump_rest` | — | — | **16 / 0** | 16 / 0 | 16 / 0 |
| `robloxemu/check_plus1jump_join` | — | — | **33 / 0** | 33 / 0 | 33 / 0 |
| `robloxemu/check_plus1jump_bands` | — | — | **16 / 0** | 16 / 0 | 16 / 0 |
| `robloxemu/check_plus1jump_world` | — | — | **18 / 0** | 18 / 0 | 18 / 0 |
| `robloxemu/check_plus1jump_rebirth` | — | — | **15 / 0** | 15 / 0 | **20 / 0** (rewritten for the restored default) |
| `robloxemu/check_plus1jump_leftout` | — | — | **8 / 0** | 8 / 0 | 8 / 0 |
| `robloxemu/check_plus1jump_life` | — | — | — | **21 / 0** (new) | 21 / 0 |
| `robloxemu/check_plus1jump_dodge` | — | — | — | — | **16 / 0** (new) |
| `robloxemu/check_plus1jump_slowload` | — | — | — | — | **24 / 0** (new) |
| `robloxemu/check_plus1jump_budget` | — | — | — | — | **11 / 0** (new) |
| **headless check total** (every counted check, plus the PASS/FAIL HUD fit) | 33 / 0 + PASS | 288 / 0 + PASS | 400 / 0 + PASS | **421 / 0 + PASS** | **477 / 0 + PASS** |
| `luau-compile --binary` | — | 27 files clean | **34 files clean** (all sources, tests and the new checks) | **40 files clean**: 15 sources, 12 test files, all 13 `check_plus1*` | **43 files clean**: 15 sources, 12 test files, all 16 `check_plus1*` |
| `luau-analyze` (changed pure modules) | — | clean apart from Roblox noise | Hazards, Rest, EnvBands, Progression clean; TowerGen only its existing `script`/`require` noise | same. `SkyArt`, `Sky.client` and `Hud.client` show only unknown-global and unknown-type noise (`Vector3`, `Enum`, `warn` …) | same. (`capRates` first drew a sort-comparator type error in EnvBands; annotated, clean) |

The emulator's `Random` is unseeded. After round 1, `check_plus1_sky`, `check_plus1_sky_rejoin` and all seven
`check_plus1jump_*` checks were run 5 more times each after the final build, green every time. The resume
session repeated that: 5 runs of each, all green with identical counts. `check_plus1jump_life` got 8 runs,
all 21 / 0. Birds in range never dropped below 8, and balloons were back in 1.1 s every time.

**Mutation sweep, round 0** (the builder): 44 mutations, 44 KILLED, CONTROL survived.

**Mutation sweep, review round 1** (`scratchpad/fix_p1/mutsweep.py`, on a fresh scratch copy of the game and
the emulator; the real tree was never mutated). For each mutation: md5 of the target, exactly one
occurrence replaced, bundle rebuilt and **proved to contain the mutation** (the mutated bundle equals the
baseline bundle with the same single replacement), all suites run (11 specs + 11 checks at the time),
original bytes restored and md5 re-verified. After the sweep the sources were byte-identical, the rebuilt
bundle identical to the baseline, and every suite green again.

* **32 mutations of the round-1 code: 31 KILLED on the first sweep, 1 SURVIVED.** The survivor was
  `F4-e` (a deck cloud that was LEFT OUT near the tower comes back when the band is shown again): with the
  live clearance and seed no cloud is ever left out, only shrunk, so no check reached that branch. Closed
  with `check_plus1jump_leftout` (forces the branch with a 160-stud clearance in memory); re-run: **KILLED**.
* **CONTROL** (the waterfall one stud wider — a real change nothing should assert): **SURVIVED** both times,
  so the harness can report a survivor.
* The reviewer's two surviving mutants are now killed: `grounded = true` in Sky.client (by
  `check_plus1jump_hazards`) and `SETTLE_SECONDS` 1.5 → 0.15 (by `check_plus1jump_join`).

**Mutation probe, resume session** (`scratchpad/resume_p1/sweep_resume.py`). It reuses round 1's harness
on its own fresh scratch copy: one occurrence replaced, bundle proved to contain the mutation, every suite
run, bytes restored with the md5 checked. The 13 mutations target promises in §2-§6 that no earlier
mutation touched:

| mutation | first sweep | after `check_plus1jump_life` |
|---|---|---|
| R1 a hit no longer voids a queued or active rest | KILLED (check_plus1_sky) | KILLED |
| R2 rest does not freeze the client's hazards | KILLED (check_plus1_sky) | KILLED |
| R3 the knock never wears off (PlatformStand stuck) | KILLED (check_plus1_sky, _hazards) | KILLED |
| R4 knock without PlatformStand | KILLED (check_plus1_sky) | KILLED |
| R5 the Rest button does not sit the player | KILLED (check_plus1_sky) | KILLED |
| R6 a seated player is never "supported" (rest wakes at once) | KILLED (check_plus1_sky) | KILLED |
| R7 lighting snaps instead of gliding | KILLED (check_plus1_sky, _sky_rejoin) | KILLED |
| **R8 scenery band weights snap on a teleport** | **SURVIVED** | **KILLED** (6 assertions: the island vanishes and the Earth appears in one frame) |
| R9 the top-10 board drops the band emoji | KILLED (check_plus1_sky) | KILLED |
| R10 idle rest switched off | KILLED (check_plus1_sky) | KILLED |
| **R11 the suit light never lights** | **SURVIVED** | **KILLED** |
| R12 a band you left keeps its parts parented | KILLED (5 checks) | KILLED |
| **R13 critters never expire, so they are never recycled** | **SURVIVED** | **KILLED** (birds in range 0, balloons never come back) |
| CONTROL astronaut visor a shade redder | SURVIVED (as it must) | SURVIVED (as it must) |

Survivors were closed test-first in the only honest order a test gap allows. The new check was written
and passed on the unmutated build, which is correct because the behaviour was already right. It was then
watched FAILING on each surviving mutant, for the stated reason and not a crash. After the sweep the
sources were byte-identical and the bundle identical to its baseline.

---

## 8. Needs Studio (only real rendering and a real device can judge)

1. **Every band's look**: exposure/ambient/bloom per band; whether the tower still reads at night in
   space; the suit light's strength; the sunset grade in the storm; lightning flash strength.
2. **Stars**: `Sky.StarCount` with Atmosphere density 0 at `ClockTime` 23 — do they show; does
   creating the `Plus1Sky` Sky client-side cause a visible pop at join.
3. **Atmosphere vs fog**: fog values are blended but Roblox ignores them while an Atmosphere exists;
   whether density 0.55 at the cloud deck reads as "inside a cloud".
4. **Distant giants on mobile**: the Earth, nebulae, ringed planet and galaxy discs are 2 048-stud
   parts 1 500-4 000 studs away — lower graphics quality may cull them. If so: closer and smaller.
5. **Neon spheres at 0.9 transparency + bloom** (nebulae, airglow): glow or blown out.
6. **Beams**: aurora ribbons and galaxy arms (curve sizes, `FaceCamera = false`) almost certainly need
   hand tuning.
7. **Cloud puffs**: do stacked balls read as clouds; tile edges popping at ~600+ studs hidden by haze;
   **does the 40-stud clear shaft around the tower through both decks read as "the tower pierces the
   clouds" or as a hole** (review round 1).
8. **Critter/hazard model orientation**: bird wings flap axis, plane propeller axis, the WedgePart
   ship hull (rotated 180°), astronaut and booster tumbles, `lookAt` headings.
9. **The knock on a real client**: does `PlatformStand` + `AssemblyLinearVelocity` push the character
   off the platform (humanoid damping), does it tumble acceptably, does it release cleanly mid-air.
   The fall before the rescue can be up to ~320 studs at tier ≥ 17 (existing rescue line).
10. **Readability of the telegraph on a phone**: billboard through cloud, lane line at 300+ studs,
    the 1.5-2 s after the lock with a thumbstick. Is it truly easy to avoid. Is ±20° above/below the view
    comfortably visible under the phone's own top-bar and thumb controls; does "looking up in the storm =
    jets only" feel like less variety.
11. **Rest's sit**: `Humanoid.Sit = true` without a seat from the client — does it sit and replicate,
    does walk input produce `MoveDirection` while seated (wakes), does jump unsit.
    (`FloorMaterial = Air` while seated is already handled and checked.)
12. **Top-row UI on a real phone**: notch/safe area, emoji in `TextScaled` labels, chip text length.
13. **Float precision at 20 000-64 000 studs**: character/camera jitter, particles. (The tower was
    already unbounded; the galaxy band starts at 61 204.)
14. **Frame time** on a mid/low phone at the densest seam (treetops › cloud sea) with the tower.
15. **Sky pieces follow the camera** (skybox-like): does the lack of parallax read as "infinitely far"
    or as glued to the camera.
16. **The old decorative red hazard cubes** (`Hazard_spike/saw/pendulum`, server) now look out of place
    next to the new sky — consider hiding them (server change; not done here).
17. **The space fanfare** (flash + FOV punch): celebratory, not annoying.
18. **The temple island 320 studs below the pad** (review round 1): still the eye-catching start from the
    pad, or too far down; the marble column carrying the pad; the forest canopy now under the island;
    and whether a real walk-off (with real latency) is rescued before the grass (0.5 s network allowance
    assumed, `Config.Pacing.RescueLatencySeconds`).
19. **The muted REBIRTH button** (`Rebirth → 5x`, grey-violet): only shown if the owner picks the first-only
    option (§11); with the default HUD every rebirth is lit, as before the sky. If he picks it: readable as
    "available", not as "disabled".
20. **The dodge on a real tile** (resume session, rule changed in review round 2). The red ring is the danger
    zone: `2 × (hitRadius + PlayerRadius)` wide, 7.8 studs for the five big kinds on an 8-stud tile, centred where
    the player stood when the lane locked. Leaving it in any direction dodges, but from the tile's centre the
    root has to travel 3.9 studs, which along a tile axis ends 0.1 studs from the edge (diagonally there is
    room). Does a phone player walk out of the ring without walking off the tile, and does a Roblox humanoid
    still stand with its root that close to an edge? Jumping on to the next platform (8+ studs away) also
    dodges. If it feels unfair, the knob is `Config.Hazards.Kinds.*.hitRadius`: 2.0 gives a 7-stud ring and a
    3.5-stud walk. `EnvConfig.spec` still guards "under half a tile", `check_plus1jump_dodge` re-checks that
    the ring is drawn exactly as wide as the hit rule, and `Pacing.spec` re-measures the rarity.
21. **Other players see a knock with nothing hitting** (hazards are local, §5). Does it look like a glitch
    in a busy server?
22. **A dodge that the model flies through** (review round 2). A player who backs out of the ring along a low
    lane, or walks toward the hazard, is safe by the rule, but the hazard's model (a plane is 9 studs across)
    keeps its straight line and can pass through the avatar with no knock. Does that read as "I dodged it" or
    as a glitch? If it reads badly, the cheap fix is visual only: after arrival, lift the model's path
    (a pull-up) when the player is outside the ring.

---

## 9. Thumbnail shot list (for the night Studio session)

**Getting there without touching real saves.** *This recipe has not been tried in Studio. Verify step 1
before relying on the rest.* The resume session fixed four traps in the first draft:
(a) The draft set shot 5's 8-10 s hazard interval in the one place used for every shot, so hazards would
knock the avatar off its platform in the other shots too. (b) Idle rest was still on: a character left
standing while you frame a shot starts resting after 20 s, and then no hazard ever launches for shot 5.
(c) Shot 4's fanfare variant was listed after the main shot, but the card plays once per session, and
after touching `P_90_3` a move down to `P_84_6` triggers the server's fall rescue. (d) The draft did not
say that the place file on disk predates the sky.

1. **Build a place that has the sky.** In `plus1-jump/`, run `rojo build -o Plus1-shots.rbxlx` and open
   that file. `*.rbxlx` is git-ignored. Do not overwrite `Plus1.rbxlx`: it predates the sky, and its
   `.lock` shows a Studio session had it open. Keep Rojo disconnected while you edit the place.
2. **No saves.** *Game Settings → Security → Enable Studio Access to API Services* **OFF**. The server
   then warns in Output that the datastore is unavailable, or that the load failed. Either way `canSave`
   stays false and nothing reaches the live DataStore or the leaderboard.
3. **Edit `ReplicatedStorage.Config` in this place only**, never in `src/`. Nothing is published from
   Studio (`publish_plus1.bat` builds from `src/`). Use two Play sessions:
   * **Session A, shots 1-4 and 6:** `Tower.StreamAhead = 260` (the server builds tiers 1-260 at join),
     `Hazards.IntervalMin = 100000`, `Hazards.IntervalMax = 100001`. No hazard can knock the avatar out of
     a frame.
   * **Session B, shot 5:** `Tower.StreamAhead = 260`, `Hazards.IntervalMin = 8`,
     `Hazards.IntervalMax = 10`, and **`Rest.IdleSeconds = 0`**. `Rest.validate` accepts 0 and it turns
     idle rest off; without it the sky rests after 20 s of standing still and the hazard never comes.
4. **Move the avatar by platform name** (command bar, Server context), then let the sky glide in for
   about 4 s (half-life 0.6 s):
   `local c = game.Players:GetPlayers()[1].Character; c:PivotTo(workspace.Tower.P_23_4.CFrame + Vector3.new(0, 4, 0))`
5. **Shoot in the order below, going up.** The server's fall rescue sends the avatar back to the highest
   platform it has touched whenever it drops more than 60 studs below that tier. To go back down, stop
   and press Play again.
6. **Clean frames** (command bar, Client context):
   `local g = game.Players.LocalPlayer.PlayerGui; g.Plus1Hud.Enabled = false; g.Plus1Sky.Enabled = false; game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
   Freecam is Shift+P. It takes the movement keys and hides ScreenGuis while it is active, so use the
   normal camera for anything that needs the HUD or needs the avatar to move.

Tower positions are for `WorldSeed 20260905`, recomputed from TowerGen in the resume session. `P_t_i` is
platform *i* of tier *t* in `workspace.Tower`.

1. **"Where it starts" — the sky temple at golden hour** (temple band, tier 0-2).
   Character mid-jump between `P_1_2` and `P_1_3` (≈ (0, 20, 20)), trail visible. Camera low on the
   −Z/−X side, ≈ (−120, 10, −110), looking at ≈ (0, 25, 60), so the first tiers climb away into the
   sky. In frame: the avatar, the pad on its marble column, sun rays, falling petals. **Variant for the
   island** (it now sits 320 studs down, y ≈ −312): camera ≈ (−260, −120, −260) looking at ≈ (0, −200, 0),
   so the column carrying the pad drops to the island with its red gate (z ≈ +120), pillars, blossom trees
   and the waterfall off the −Z edge.
2. **"Breaking the cloud sea"** (cloud band, tier 23; deck top ≈ y 3 870).
   Character standing on `P_23_4` (≈ y 4 050: above the tallest puffs, which top out near y 4 010, and
   past the whiteout layer, which is fully gone above tiers-climbed 22.47; tier 22 starts at (2, 3 652, 956)).
   Camera ≈ 45 studs behind and 20 above the character, pitched ~20° down. In frame: the avatar
   silhouetted against the low gold sun, the tower rising out of the clear shaft through the cloud sea,
   the deck to the horizon, a hot-air balloon mid-ground (they drift; wait for one), sun glare.
3. **"Into the storm"** (storm band, tier 44; storm deck top ≈ y 9 150; tier 42 starts at (−39, 8 932, 1 832)).
   Character on `P_44_1` mid-jump. Camera level with the character, ~60 studs to the side, looking
   across the dark deck. In frame: the storm deck (the nearest clouds keep 40 studs off the tower),
   **a lightning bolt** (every 6-14 s — take a burst), the orange-violet sunset glow, a jet contrail,
   rain streaks.
4. **"YOU MADE IT TO SPACE"** (orbit band, tier 90; `P_90_1` at (−130, 21 604, 4 392)).
   **Variant first**, with the HUD on and the `🚀 YOU REACHED SPACE!` card. Move the avatar to `P_84_6`
   at (−18, 20 240, 4 126) and wait for the Edge of Space card to fade. Then move it to `P_85_1` at
   (−18, 20 284, 4 140). The card, a white flash and an FOV punch play on landing in Tier 85, once per
   session, so take a burst with the normal camera. **Then the main shot:** the avatar standing on
   `P_90_3` at (−144, 21 692, 4 406), looking up and out. Camera about 80 studs above and 60 to the side,
   pitched about 45° down so the **Earth and its blue airglow fill the lower half**. In frame: the avatar
   with its suit light, the tower's platforms dropping toward Earth, the space station (upper right, +X),
   aurora and stars; a drifting astronaut or satellite if one passes.
5. **"Close call"** (deep space, tier 160; `P_160_1` at (24, 40 084, 8 214); **session B**).
   An **asteroid** (or spaceship) passing within a few studs of the avatar. A hazard launches every
   8-10 s at a standing avatar and starts inside the *player's* camera view, so use the normal camera:
   right-drag it side-on and scroll out to about 40 studs. When the lane and ring turn red (`⚠️ MOVE!`),
   walk out of the red ring (any direction works since review round 2; stepping sideways keeps the model from
   flying through the avatar in frame), or jump on to the next platform, and screenshot as the hazard passes.
   Freecam would take the movement keys. In frame: the hazard with its ⚠️ marker, the red lane, the
   avatar clear of it (mid-air if jumping), the ringed planet and a nebula behind. A hit only knocks the
   avatar off, and the rescue puts it back on `P_160_1` for the next try.
6. **"Beyond the Galaxy"** (galaxy band, tier 250; `P_250_1` at (−60, 63 844, 13 338)).
   Character small on a platform; camera ~150 studs above and behind, looking down past them. In frame:
   the **spiral galaxy below** (bright core, curved arms), nebula glow at the edges, a comet trail, the
   platform line continuing down toward the galaxy.

---

## 10. Using this as the template for another game

* Copy `EnvBands.luau`, `Hazards.luau`, `Rest.luau` **and their specs** verbatim (the specs carry their
  own configs). They take dependencies as arguments; none of them `require`s anything.
  **Review round 1 changed the template API**: `Hazards` configs now need `ViewPitchDegrees` (≤ 30) and a
  `SpreadDegrees` ≤ 40, and `Hazards.step` wants `ctx.pitch` (the camera's pitch in radians) — a copy
  taken before 2026-09-17 evening lets hazards start off screen; take the new one. `Rest` keeps a queued
  request while the threat is live; size `PendingSeconds` to your longest hazard flight + 2 s.
  **Review round 2 changed it again**: `Hazards.checkHit` needs the player inside `Hazards.zone(plan,
  PlayerRadius)` (every planned hazard has the `target` and `jitter` it needs), and `SkyArt:showHazard` takes
  that zone as its last argument and draws the ring exactly there. A copy taken before round 2 has the
  corridor hit rule, where only a step at right angles to the lane dodges. Cap weather with
  `EnvBands.capRates`; a first title card's settle clocks start when the saved state has LOADED.
* Pick the game's **real progress value** (depth in a mine, night number, floor). Compute it on the
  client from local or server-pushed state. Never time. If the HUD or a leaderboard shows a whole number
  (a tier, a floor), NAME bands by that number and blend by the continuous value, or they will disagree.
* Put the numbers in the game's `Config`: `Env.Bands` (every band defines the same lighting fields —
  copy `tests/EnvConfig.spec.luau` to enforce it), `Env.Layers` if you have something to climb
  *through*, `Hazards` (interval, telegraph ≥ 3 s, commit, hitboxes whose ring, hitRadius + player radius,
  a half-step leaves on *your* floor size, view window), `Rest`, `Budget` (with `MaxWeatherEmitters`).
* Glue: copy the frame order from `Sky.client.luau` — band weights → lighting at 10 Hz → scenery →
  critters → weather → rest → hazards → UI. Art (`SkyArt`) is always game-specific. Scenery you walk
  *through* must keep off the play path (`EnvBands.keepClear`); non-collidable ground under a spawn must
  sit below where your rescue catches a falling player, network included.
* A first title card must wait for the player's saved state to have LOADED (and the server's placement
  to arrive), not for a fixed timer.
* **Timed-round games**: rest is between rounds. Never feed a round clock, raid timer or penalty
  through `Rest`; it only pauses things that exist to bother the player. `Rest.validate` refuses
  `WakeOnMove = false` and `BlockWhileThreat = false`.
* Measure budgets the way `check_plus1_sky.luau` §3/§10 does, at every band *and* every seam. Also check
  that the scene stays alive and never cuts, the way `check_plus1jump_life.luau` does: pooled life keeps
  coming back, and a teleport cross-fades the scenery. Neither is visible in a part count.
* Measure pacing with the game's own model, like `tests/ClimbModel.luau`, and write the human
  assumptions into Config. Model the player who does what your HUD tells them (`followHighlights`).

---

## 11. Not done / open

* The review-round-1 fixes (§12) were reviewed in round 2 (§14). The round-2 fixes have **not** had their own
  independent adversarial review.
* **Owner decisions surfaced, not taken for him:** (a) **which rebirths the HUD lights.** Default, restored in
  review round 2: every rebirth the server allows, as before the sky. A normal player who presses it every
  time it is lit takes ten rebirths before tier 85 and reaches space after 227.4 min instead of 34.4. The
  option `Config.Rebirth.HighlightFirstRebirths = 1` (one line) lights only the first rebirth and again past
  tier 240; that player then reaches space in 38.4 min. Both are measured in `Pacing.spec` and checked through
  the real HUD in `check_plus1jump_rebirth`. (b) **the underlying mechanic:** with the jump capped at 60 and
  every tier reachable without rebirth, the rebirth multiplier never speeds the climb, so rebirth is pure
  prestige that costs altitude. Making it genuinely "climb faster next run" (README's promise) is a
  server-side design change, not done. Deciding (b) may make (a) moot.
* The island depth assumes a 0.5 s network allowance for the rescue; a player on a very laggy connection
  can still reach the grass (Studio / real device).
* Not committed, not pushed, not published. Studio not opened.
* §8 in full.

---

## 12. Adversarial review round 1 (2026-09-17) — findings and what closed them

Each finding was first reproduced (the reviewer's probes re-run on an untouched copy), then a failing test
was written and watched fail on the pre-fix bundle, then the game was fixed. Headless checks are new
files (`robloxemu/check_plus1jump_*.luau`); no existing check was edited.

| # | finding (severity) | reproduced | failing test first | fix |
|---|---|---|---|---|
| 1 | hazards off screen: the ±50° rule was horizontal only (medium) | `probe_view`: weather balloon on screen 0 % with a level or raised camera; booster/comet 0 % looking down 30° | `Hazards.spec` view window + frustum property (2 394 of 5 400 off screen with the pitch ignored), `EnvConfig.spec` every band's kinds, `check_plus1jump_hazards` through the client (old build: up to 120 of 120 warning frames off screen) | `Hazards.viewWindow` / `pickKind`; lanes start within ±35° / ±20° of the camera's view; `Sky.client` passes the camera pitch; validate caps both |
| 2 | 30-45 min only if the player skips rebirths the HUD lights up (medium) | `probe_rebirth`: 34.6 / 38.6 / 46.1 / 57.0 / 226.5 min | `Progression.spec` rule, `Pacing.spec` HUD follower, `check_plus1jump_rebirth` via the real server (old build: 3 failures — rebirth #2 lit at tiers 18 and 40) | `Progression.rebirthHighlighted` + `Config.Rebirth.HighlightFirstRebirths/HighlightAgainAtBestTier`; HUD lights only those; button still works (§2). **Round 2 made this the owner's option and restored the old default (§14)** |
| 3 | returning space player: TEMPLE card + space fanfare when the load takes > 1.5 s (low) | `probe_rejoin_slow`: 1.6 / 2.0 / 4.0 s → TEMPLE + YOU REACHED SPACE + flash | `check_plus1jump_join`: a real slow `UpdateAsync` (6 s), a late placement (3 s), a Tier value replicating 1 s after its folder; old build: 15 of 33 assertions failed | first card waits for `leaderstats` (profile loaded), then 1.5 s, and until the character stands near its credited tier; 15 s timeout |
| 4 | storm-deck cloud (r 121, 92 % opaque) swallowed P_42_5 (low) | `probe_deck2`: P_42_5, P_42_6, P_43_1 inside; P_42_5 hidden from a camera 14 back / 6 below | `EnvBands.spec` `pathDistance`/`keepClear`, `TowerGen.spec` `platformCentres`, `check_plus1jump_world` against the server's parts at 162 camera positions per deck (old build: 6 failures — 12 holds, 12 hides, nearest surface −28 studs) | tiled decks shrink or leave out any cloud within `Config.Env.SceneryClearance` = 40 studs of the climb (path from `TowerGen`); left-out clouds stay out when the band returns |
| 5 | walk off the pad → sink through the island's grass before the rescue (low) | `probe_island`: 89.2 % of falls, deepest root −131 | `EnvConfig.spec` island depth vs poll + latency, `check_plus1jump_world` falling under gravity through the real server rescue at 8 poll phases (old build: feet 71 studs below the grass) | island top 320 studs below the pad (`Config.Env.IslandTopBelowPad`), column carrying the pad, canopy moved under the island; lowest rescued feet now 36.5 studs above the grass with a 0.5 s network allowance |
| 6 | walking off the lane cancelled a queued rest (low) | `probe_restqueue`: walked sidestep → Sit nil, button back to Rest | `Rest.spec` (4 new assertions failed), `check_plus1jump_rest` walking for real (old build: 3 failures) | `Rest.update` keeps the request while the threat is live; drops it only after 0.4 s of walking under a clear sky; `PendingSeconds` 8 → 10 |
| 7 | band emoji on Best/board disagreed with the player's own sky (low) | `probe_emoji`: P_85_1..5 board 🚀, sky 🌠 (also tiers 7, 15, 240) | `Altitude.spec` `tierAtY` for t ≤ 400, `check_plus1jump_bands` on every platform of 7 boundary tiers (old build: 35 of 49 platforms wrong, 4 failures) + fanfare on landing | the named band follows `Progression.tierAtY` (the HUD's tier); blends stay continuous; new bands are announced only when standing |
| 8 | `grounded = true` in Sky.client survived every suite (low) | reviewer's mutation | `check_plus1jump_hazards`: no launch while airborne for IntervalMax + 20 s, launch on landing | test gap closed (behaviour was already right) |

### Round-1 mutation results

| mutation | result | killed by |
|---|---|---|
| F6-a clearFor keeps counting under a threat | KILLED | Rest.spec |
| F6-b walking on never drops a queued rest | KILLED | Rest.spec, check_plus1jump_rest |
| F6-c movement under a threat drops the request (old rule) | KILLED | Rest.spec, check_plus1jump_rest |
| F6-d PendingSeconds back to 8 | KILLED | EnvConfig.spec |
| F1-a Sky.client drops the camera pitch | KILLED | check_plus1jump_hazards |
| F1-b plan does not clamp elevation into view | KILLED | EnvConfig.spec, Hazards.spec, check_plus1jump_hazards |
| F1-c pickKind ignores the view | KILLED | Hazards.spec |
| F1-d view window 60° | KILLED | EnvConfig.spec, Hazards.spec, check_plus1jump_hazards |
| F1-e spread limit 60 | KILLED | Hazards.spec |
| F1-f Config spread back to 50 | KILLED | EnvConfig.spec + every client check (hazards switch off with a warning) |
| F8 Sky.client launches at airborne players | KILLED | check_plus1jump_hazards |
| F3-a settle 1.5 → 0.15 s | KILLED | check_plus1jump_join |
| F3-b no placement check | KILLED | check_plus1jump_join |
| F3-c settle counts before the profile loads | KILLED | check_plus1jump_join |
| F3-d settle timeout 15 → 1 s | KILLED | check_plus1jump_join |
| F7-a band named by tiers climbed again | KILLED | check_plus1jump_bands, check_plus1jump_join |
| F7-b announce while airborne | KILLED | check_plus1jump_bands |
| F7-c tierAtY off by one | KILLED | Altitude.spec, check_plus1jump_bands, check_plus1jump_join |
| F7-d FloorBelowRoot 2 → 4 | KILLED | check_plus1jump_bands, check_plus1jump_join |
| F4-a storm deck without keepClear | KILLED | check_plus1jump_world |
| F4-b keepClear ignores the clearance | KILLED | EnvBands.spec, check_plus1jump_world |
| F4-c SceneryClearance 40 → 10 | KILLED | check_plus1jump_world |
| F4-d tower path built from y = 0 | KILLED | TowerGen.spec, check_plus1jump_world |
| F4-e left-out clouds come back when the band returns | SURVIVED → **KILLED** after adding the check | check_plus1jump_leftout |
| F4-f pathDistance measures to segment starts only | KILLED | EnvBands.spec, check_plus1jump_world |
| F5-a island back at 70 studs | KILLED | EnvConfig.spec, check_plus1jump_world |
| F5-b SkyArt ignores the configured depth | KILLED | check_plus1jump_world |
| F5-c network allowance 0.1 s | KILLED | EnvConfig.spec |
| F2-a HUD lights every possible rebirth | KILLED | check_plus1jump_rebirth |
| F2-b rule highlights everything | KILLED | Pacing.spec, Progression.spec, check_plus1jump_rebirth |
| F2-c first three rebirths highlighted | KILLED | Pacing.spec, Progression.spec, check_plus1jump_rebirth |
| F2-d lit again from space instead of the galaxy | KILLED | Pacing.spec, Progression.spec |
| CONTROL waterfall one stud wider | SURVIVED (as it must) | — |

---

## 13. Resume session (2026-09-17, after the owner's 45-minute pause)

The first build agent was stopped while it was writing this file. Nothing it left was trusted because it
existed:

| step | result |
|---|---|
| re-read every new and edited file (template modules, Config, Progression, TowerGen, SkyArt, Sky.client, Hud.client, Main.server, all specs, ClimbModel, all `check_plus1*` glue checks) | no half-written code, no TODOs. One wrong claim in this file: `Main.server.luau` was called byte-identical, but it has the one-line `BASE_POS` change §1 lists. Fixed in §5 |
| rebuilt `build/plus1-jump.luau` | byte-identical to the bundle on disk, so the checks had been testing the current sources |
| every gate (§7) | 11 specs 561 / 0; 12 counted headless checks 421 / 0 including the new `_life`; HUD fit PASS; `luau-compile` 40 / 40 files; `luau-analyze` Roblox noise only |
| unseeded checks, 5 runs each | identical counts every run |
| `check_plus1_sky` budget print-out against §6 | matches row for row (peak 134 parts, 2 emitters at 40/s, 4 beams, 2 trails, 2 lights) |
| `Pacing.spec` print-out against §2 | matches (normal 34.4 min to space, HUD follower 38.4, galaxy 99.1 / 103.1) |
| shot-list positions recomputed from TowerGen | all correct |
| probe sweep, 13 new mutations + a control (§7) | 10 killed, 3 survived: critter recycling, scenery glide on teleport, suit light. Closed by `robloxemu/check_plus1jump_life.luau` (21 assertions), which was watched failing on each survivor; the control survives |
| shot list (§9) | four traps fixed; see the list at the top of §9 |

Files written in the resume session: `robloxemu/check_plus1jump_life.luau` (new), `plus1-jump/EYECANDY.md`,
`plus1-jump/README.md`, `plus1-jump/CLAUDE.md`, `robloxemu/build/plus1-jump.luau` (rebuilt, unchanged). No
game source changed. `robloxemu/check_plus1.luau` keeps its `overlap = true` change from another task.
Scratch evidence: `scratchpad/resume_p1/` (`sweep_resume.py`, `sweep.log`, `sweep2.log`, `sweep_results*.json`).

---

## 14. Adversarial review round 2 (2026-09-17) — findings and what closed them

A separate reviewer took the round-1 fixes on its own clean scratch copy and reported 4 findings. Every one
was **reproduced first** on an untouched scratch copy with the reviewer's own probes, then a failing test was
written and watched failing on the unfixed build, then the game was fixed, then the reviewer's probes were run
again on the fixed build. None was rejected: all four reproduced.

| # | finding (severity) | reproduced before the fix | failing test first | fix | reviewer's probes after the fix |
|---|---|---|---|---|---|
| 1 | only a step at right angles to the lane dodged; backing away or leaving the red ring still got you hit (high) | `probe_rev_dodge` through the client, 60 hazards per mode at tiers 38 / 150: S key 100 % / 100 %, back along the lane 100 / 100, away from the ring's centre 57 / 57, A/D on the better side 12 / 17, at right angles 0 / 0. Climb model (3 h from tier 20): back 1.00, ring 0.58-0.73, strafe 0.20-0.23, at right angles 0.00, ignores warnings 0.28 | `Hazards.spec`: the zone API, 7 ring cases, walking out of the ring at every 10° (67 of 324 dodged); `Pacing.spec`: 8 directions × 71 hazards (only 90° and 270° partly dodged); `check_plus1jump_dodge` through the client in the camera's 8 directions (41-42 of 56 walkers hit, S and W 7 of 7; the ring centred up to 1.17 studs from where the player stood) | a hit needs the player INSIDE the zone, the circle the ring draws (`Hazards.zone`, `inZone`, `checkHit`); the zone is centred where the player stood when the lane last aimed at them, radius hitRadius + PlayerRadius; `SkyArt:showHazard` draws the ring exactly there; `Sky.client` passes the zone | 0 % in all five modes at both tiers; climb model 0 hits in all 4 modes × 3 camera pitches; ignores warnings still 0.28 |
| 2 | REBIRTH dimmed for rebirth #2 onward: an existing mechanic's HUD changed without the owner (medium) | `git diff HEAD`: before the sky every possible rebirth was purple `REBIRTH → Nx?`; after round 1 rebirth #2+ was a muted `Rebirth → 5x` until best tier 240 | `Progression.spec`: by default lit exactly when the server allows a rebirth (differed at tier 18 with 1 rebirth); `Pacing.spec`: the default follower misses the window (was 38.4); `check_plus1jump_rebirth`: lit at tiers 18 and 26 (2 failures) | `Config.Rebirth.HighlightFirstRebirths = math.huge`: every rebirth the server allows is lit, as before the sky. The first-only rule stays as the owner's one-line option (`= 1`), measured in `Pacing.spec` and driven through the real server and HUD in `check_plus1jump_rebirth`. The corrected multiplier text (`5x`, not `4x`) stays | the decision is in §11 with both numbers: default follower 227.4 min to space, option follower 38.4 |
| 3 | a profile load over 15 s gave a returning space climber a TEMPLE card and a repeat "YOU REACHED SPACE!" (low) | `probe_rev_slowload`: 14 s → one quiet `SPACE · LOW ORBIT`; 16 s → `TEMPLE GROUNDS`, `YOU REACHED SPACE!`, 1 flash | `check_plus1jump_slowload`: 16 s and 40 s loads, a placement arriving 20 s after the load, an edge-of-space climber with a 16 s load who climbs on (13 failures) | both settle clocks (the 1.5 s settle and the 15 s timeout) start when the profile has loaded (leaderstats); before that no card shows, the sky itself runs from the first frame. The first announcement also counts the band of the tier the server credits, so a placement that arrives after the timeout is not celebrated | 14 s and 16 s: one quiet `SPACE · LOW ORBIT`, 0 flashes |
| 4 | the emitter budget was not enforced in code: 5 weather emitters on at once (budget 4, docs said 2) (low) | `probe_rev_budget` (400 cycles of teleports and climbs, a hazard every 6-7 s): peak 5 emitters, 176 parts, 40/s, 7 beams, 3 trails; 382 unique instances | `EnvBands.spec` `capRates` (missing); `EnvConfig.spec` `Budget.MaxWeatherEmitters`; `check_plus1jump_budget`, the reviewer's run with the budgets asserted on every frame (peak 5 at cycle 95, a teleport from 15 to 54 tiers climbed) | `EnvBands.capRates` (template, pure): only the `MaxWeatherEmitters` = 2 strongest kinds on, equal rates broken by name, scaled together under `MaxEmitterRate` = 60/s; `SkyArt:updateWeather` switches on only what it returns | peak 2 emitters, 40/s, 174 parts |

### Why the ring rule, not a drawn corridor (finding 1)

The reviewer offered two fixes: count a hit only inside the drawn ring, or draw the whole lane as a strip. The
strip would have been honest but still hard to escape: the ▲ arrow says the hazard comes from ahead, so backing
away is the first reaction and it stays in the strip, and from the middle of an 8-stud tile only 29.8 % of the
directions to the edge get 3.9 studs off a level lane (the reviewer's geometry). Taking the ring as the rule
makes what the player sees exactly what hits, in every direction. It only removes hits (a hit still needs the
hazard to pass within reach), so nothing got harder, and nothing a hazard does touches progress, so a more
forgiving hazard is no exploit. Unchanged by it: hazards per minute (0.394), near-hits per minute (0.394 for a
climber who reacts, 0.192 for one who does not), the hit share of a climber who ignores every warning (0.26 on
the spec's seed), and so every pacing minute in §2. What it costs is on the Studio list (§8 items 20 and 22):
the ring nearly fills the tile, and a hazard can fly through an avatar that has dodged it by backing away.

The zone is centred where the player stood, not on the lane's jittered target, so a player who stays put is at
its centre and is hit every time (9 of 9 in the spec, 14 of 14 through the client), and the same walk of 3.9
studs leaves it in every direction.

### Round-2 mutation sweep

`scratchpad/fix2_p1/sweep_r2.py` reuses round 1's harness on a fresh scratch copy of the real tree (verified
identical to it: sources, tests, all 16 `check_plus1*` checks, bundle apart from path lines). For each mutation:
exactly one occurrence replaced, bundle rebuilt and proved to contain it, all 27 suites run (11 specs + 16
checks), original bytes restored and md5 re-checked. Baseline green; after the sweep the sources were
byte-identical, the bundle identical to its baseline, and all 27 suites green again. A first run of this sweep
was stopped when it showed that `check_plus1jump_budget`'s first draft could flake ("nothing new after cycle
200" failed 1 run in 15 when a hazard kind first flew late); the check was fixed (§6) and the sweep re-run in
full.

| mutation | result | killed by |
|---|---|---|
| N1-a `checkHit` ignores the zone (the old corridor rule) | KILLED | Hazards.spec, Pacing.spec, check_plus1jump_dodge |
| N1-b zone keeps the jitter on x (centred on the target) | KILLED | Hazards.spec, Pacing.spec, check_plus1jump_dodge |
| N1-c zone radius = hitRadius only (smaller than the ring) | KILLED | Hazards.spec, check_plus1jump_dodge |
| N1-d hit zone 1.5× the drawn ring | KILLED | Hazards.spec, Pacing.spec, check_plus1jump_dodge |
| N1-e ring drawn at the jittered target | KILLED | check_plus1jump_dodge |
| N1-f ring drawn at 1/4 size (the reviewer's surviving M6) | KILLED | check_plus1jump_dodge |
| N1-g ring drawn at 2× size | KILLED | check_plus1jump_dodge |
| N1-h `Sky.client` builds the zone without the player radius | KILLED | check_plus1jump_dodge |
| N2-a Config back to first-only highlighting | KILLED | Pacing.spec, Progression.spec, check_plus1jump_rebirth |
| N2-b HUD lights only the first rebirth, ignoring the rule | KILLED | check_plus1jump_rebirth |
| N2-c HUD ignores the owner's option (always lit) | KILLED | check_plus1jump_rebirth |
| N3-a settle timeout counts from the spawn again | KILLED | check_plus1jump_slowload |
| N3-b first announcement ignores the credited band | KILLED | check_plus1jump_slowload |
| N3-c no placement check | KILLED | check_plus1jump_join |
| N4-a `SkyArt` ignores the cap | KILLED | check_plus1jump_budget |
| N4-b `capRates` ignores maxOn | KILLED | EnvBands.spec, check_plus1jump_budget |
| N4-c `capRates` never scales to the total | KILLED | EnvBands.spec |
| N4-d `capRates` keeps the weakest | KILLED | EnvBands.spec |
| N4-e `MaxWeatherEmitters` 2 → 4 | KILLED | EnvConfig.spec |
| N4-f a hazard model is rebuilt every time it flies (no pool) | KILLED | check_plus1_sky, check_plus1jump_budget, _dodge, _hazards, _rest, all by the 300 s suite timeout: a new model every frame makes the client crawl (a run of the budget check alone was stopped after 15 min) |
| N4-g a hazard's model is forgotten when it lands (a new model every flight, a realistic leak) | KILLED | check_plus1jump_budget ("each hazard kind's model is built once"), in 21 s: the bounded-pool assertion catches a leak on its own, not by timeout |
| CONTROL-1 astronaut visor a shade redder | SURVIVED (as it must) | — |
| CONTROL-2 hazard ring a little more transparent (0.55 → 0.5) | SURVIVED (as it must) | — |

**22 mutations, 22 KILLED; both controls survived.** (N4-g was run separately after N4-f was seen to die only by timeouts, on its own fresh copy, same proof steps: `sweep_r2_n4g.log`.) The reviewer's other survivor, M7 (`KnockLift` 10 → 15),
was left alone as the reviewer judged: it is inside the validated maximum and changes nothing a player can
exploit.

### Stability

The new and rewritten checks use the emulator's unseeded `Random`. After the final build: `check_plus1jump_dodge`,
`_slowload` and `_rebirth` 5 runs each, identical counts; `check_plus1jump_budget` 20 runs, 11 / 0 each (unique
instances 373-382 by cycle 100, 382 by the end every time).

### Files written in review round 2

`plus1-jump/src/shared/Hazards.luau`, `EnvBands.luau`, `SkyArt.luau`, `Config.luau`,
`plus1-jump/src/client/Sky.client.luau`; `plus1-jump/tests/Hazards.spec.luau`, `EnvBands.spec.luau`,
`EnvConfig.spec.luau`, `Pacing.spec.luau`, `Progression.spec.luau`, `ClimbModel.luau`;
`robloxemu/check_plus1jump_dodge.luau`, `check_plus1jump_slowload.luau`, `check_plus1jump_budget.luau` (new),
`robloxemu/check_plus1jump_rebirth.luau` (rewritten for the restored default), `robloxemu/build/plus1-jump.luau`
(rebuilt); `plus1-jump/EYECANDY.md`, `README.md`, `CLAUDE.md`. `Main.server.luau` and `Hud.client.luau` did
not change in this round. Nothing committed, pushed or published; Studio not opened. Scratch evidence:
`scratchpad/fix2_p1/` (`sweep_r2.py`, `sweep_r2.log`, `sweep_r2_first_aborted.log`, `sweep_r2_results.json`,
`gates_*.txt`, `work/` with the reviewer's probes re-run on the fixed build).
