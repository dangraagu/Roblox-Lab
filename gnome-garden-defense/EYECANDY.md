# Gnome Garden Defense: the seasons, the hazards, PAUSE, the budgets

The owner's eye-candy rules (docs/complete-game-standard.md §2) applied to a tower defence. Model document:
`plus1-jump/EYECANDY.md`. Every number below was measured by a command named next to it; "Studio" marks what
only real rendering, input or a device can settle (§7).

## 1. What runs where

| piece | file | runs on | touches progress? |
|---|---|---|---|
| bands: light, sky, post-fx, scenery, critters, weather | `src/client/Garden.client.luau` + `src/shared/GardenArt.luau` | client, own garden only | no |
| bugs drawn from the 10 Hz GardenTick (interpolated) | same | client | no (the server owns every bug) |
| hazards (vertical drops), knock-down, 3 s daze | same + `src/shared/Hazards.luau` | client, local player only | no seeds, no garden state |
| PAUSE (Rest) | same + `src/shared/Rest.luau`; server `SetPaused` | client asks, server freezes the WHOLE garden | freezes both sides |
| gnome models, pads (rim glow), the bed, carrots, the sign, the board, the meadow | `src/server/Main.server.luau` | server (replicated) | the server's own state |
| the garden view: camera, tap -> pad, zoom (REVIEW-1) | `src/client/View.client.luau` + `src/shared/GardenCam.luau` | client, own garden only | no (it only names a pad to the HUD) |

Templates: `EnvBands.luau` and `Rest.luau` are +1 Jump's, byte for byte. `Hazards.luau` is Deep Vein's copy
(+1 Jump's plus VERTICAL kinds) with +1 Jump's later `Hazards.threatLive` added: a top-down camera over a flat
bed would start +1 Jump's sideways lanes underground, so the hazards fall from above or burst up from below, and
the ring stays drawn while the rest of the flight can still hit someone inside it (Hazards.spec, 152).

## 2. The bands

Progress `p` = waves survived + the share of this wave's bugs already STOPPED (a boss counts its lost health
while it walks), at most 0.999 of a wave until the wave is survived (`Config.ProgressInWaveMax`: a Frost Mantis
with 1% of its health left rounded up onto 40 in the server's 3 decimals and named Moonlit Snow while it walked, in
4 of 6 runs; check_gnomegardendefense_frost). A bug that reaches the patch is not progress (REVIEW-1: counting it put a lost boss wave on the
next band's boundary, and losing to the Slug Queen played the HARVEST MOON); a lost wave stays below its boundary
(29.917 after losing to the Queen in check_gnomegardendefense_brag). The server replicates it as the garden's `Progress` attribute; the client smooths the LOOK
(half-life 0.6 s, so a lost season's jump back GLIDES: measured on a 32 -> 20 jump, ClockTime 8.02 -> 8.02 in
the first frame and at the harvest light, 16.8 +- 0.4, five seconds later) and names the band from the exact value. Season bands start at their boss wave, so the
season turns as the boss gives ground and is full the instant it falls.

Minutes = median minutes of play when the band is FULL (its `from` wave survived), 40 campaigns each, measured
with `luau tests/BandMinutes.luau` on the game's own Garden/PathGen/Waves:

| # | band | from / fade | light (ClockTime) | scenery | critters | weather | hazards | normal | strong |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Spring Sprouts | 0 / 0 | dawn 6.6, pink fog | seedlings, dew | butterflies | dandelion fluff (4/s) | none | 0.0 | 0.0 |
| 2 | Blossom Morning | 3 / 1 | 9.5 | blossom trees | butterflies, bees | petals | acorn | 2.6 | 2.1 |
| 3 | High Summer | 10 / 2 | noon 13.0 | sunflowers, bunting | bees, dragonflies | pollen | acorn, sprinkler jet | 8.6 | 7.2 |
| 4 | Summer Shower | 15 / 1 | 15.0 grey-violet | puddles, rainbow (4 beams) | dragonflies | rain | sprinkler jet, acorn | 14.1 | 11.1 |
| 5 | Harvest Gold | 20 / 2 | 16.8 amber | pumpkins, hay bales | robins | leaves | apple, molehill | 20.3 | 16.7 |
| 6 | **HARVEST MOON** | 30 / 3 | night 21.5, moon 30 deg | paper lanterns, the moon (1 light) | fireflies, owl | fireflies | apple, pinecone | **33.6** | 26.6 |
| 7 | First Frost | 31 / 1 | morning 8.0 | frosted hedge, birdbath | robins | frost sparkle | icicle, molehill | 35.8 | 27.9 |
| 8 | Snowfall | 35 / 1 | dusk 17.5 | snow on the hedge, sledge | crows | snow | icicle, snow clump | 40.5 | 32.1 |
| 9 | Moonlit Snow | 40 / 2 | midnight 0.5 | snowdrifts, snowman | owl | frost glitter (8/s) | snow clump, icicle | 57.4 | 37.5 |
| 10 | Starfall | 45 / 2 | 23.0 | lamp posts, drifts | shooting stars | stardust | star shard, snow clump | 65.0 (23 of 40 runs) | 43.8 |
| 11 | **AURORA** | 50 / 3 | 1.5 | aurora (3 beams), drifts | snow hares | snow + stardust | star shard, snow clump | 65.9 (17 of 40) | 50.5 (40 of 40) |

The weak profile: 3.0 / 10.2 / 16.9 / 24.3 / 53.7 (moon) / 56.6 / 62.7, Moonlit Snow on 4 of 40 runs.
Night bands make the path gravel glow (Neon) instead of adding lights (check_gnomegardendefense_env).

**The brag (DESIGN.md §6):** wave 30, the Slug Queen falls under the Harvest Moon. Normal median 33.6 min (p10
30.3, p90 53.3, worst 61.8), asserted 30-45 by `tests/Pacing.spec.luau` (27 passed, byte-identical on 3 runs).
What the player sees: the moon band blending in through her fight (weight > 0 at progress 28-29.99, full at 30),
the card "HARVEST MOON / The Slug Queen falls!", a white flash and an FOV punch, a golden burst over the carrot
patch, the garden view looking UP at the moon for 4.5 s (it otherwise looks down at the bed; measured 4.6 s of
"sky" frames in check_gnomegardendefense_brag), the result panel "HARVEST MOON!", and the board entry. A LOSS to
the Queen shows none of it (same check: no moon card, chip, band or sky look; the real win afterwards shows them).
Nor does a JOIN: Frost's bed starts at Progress 30, inside the moon's band, so the first sight of a garden's
progress is told quietly (a 3 s card naming the band; no flash, no sky look), even when the client starts during
a 2 s profile load (check_gnomegardendefense_frost; before the fix every Frost join flashed and looked up at the
moon for 4.6 s). Long-term goals: the Frost Mantis (wave 40, normal
57.4 min), the Aurora (wave 50: strong 40 of 40 runs, normal 17 of 40), and the board (endless best wave: normal
40-53, strong 53-56 over 12 beds).

## 3. Hazards

| kind | drop | height / fall / telegraph / commit / pass | ring radius | bands |
|---|---|---|---|---|
| acorn | above | 22 / 0.6 / 3.2 / 1.6 / 0.6 | 1.6 + 1.4 = 3.0 | 2, 3, 4 |
| apple | above | 20 / 0.5 / 3.2 / 1.6 / 0.6 | 3.0 | 5, 6 |
| pinecone | above | 20 / 0.5 / 3.2 / 1.6 / 0.5 | 3.0 | 6 |
| icicle | above | 20 / 0.5 / 3.2 / 1.6 / 0.5 | 3.0 | 7, 8, 9 |
| snow clump | above | 18 / 0.7 / 3.4 / 1.7 / 0.8 | 3.0 | 8, 9, 10, 11 |
| star shard | above | 22 / 0.6 / 3.2 / 1.6 / 0.6 | 3.0 | 10, 11 |
| sprinkler jet | below | 7 / 0.35 / 3.4 / 1.8 / 1.2 | 3.0 | 3, 4 |
| molehill | below | 7 / 0.35 / 3.6 / 1.8 / 1.2 | 3.0 | 5, 7 |

- **Rare:** 100-150 s of garden time apart (phases build/wave, not paused, not resting, a band with kinds; band 1
  has none). Measured: one per 2.58 min of play for the normal profile (Pacing.spec); in the env check two
  consecutive hazards came 109.6-143.0 s of garden time apart over 6 runs (now timed seen-to-seen on the clock:
  the old estimate added 3.8 s and failed about one run in fifteen), none in 220 s of band 1, none in 400 s paused.
- **Seen on a phone:** while a hazard is live the garden view zooms on the gardener: the red ring measured 57 px
  across on an 844x390 phone (check_gnomegardendefense_reach), back to the whole garden after it.
- **Telegraphed, and the red ring IS the hit zone:** measured, the ring's diameter is 6.0 studs = 2 x (1.6 + 1.4)
  and it is centred on a gardener who stands still (0.0 studs off); the banner names the kind ("ACORN"). Standing
  in it: knocked down (PlatformStand) and dazed. Stepping 4.5 studs out after the lock: no hit. At walk speed 16
  the slowest escape from a ring takes 0.19 s, inside every kind's 1.5-1.8 s commit (EnvConfig.spec).
- **One at a time:** never more than one out over 3 x 150 s (env check).
- **A hit costs 3 s, never seeds:** the gnome sheet greys out and a tap answers "Seeing stars... 3" (env check).
  DESIGN.md §5.4: with EVERY hazard hitting, 0 of 160 chapter outcomes change (Pacing.spec).

## 4. PAUSE

`Config.Rest`: +1 Jump's template with idle rest OFF (`IdleSeconds = 0`: watching a wave without touching
anything is normal play); the AFK hold on the build timer is the AFK safety instead (180 s, measured in
check_gnomegardendefense_save: held 201 s after the last action, waits 120 s more with the wave count unchanged,
the next action brings the timer back and the wave comes 21 s later).

- The PAUSE button (Garden.client's row) asks the server; the server freezes the WHOLE garden: no step, no
  build timer, no ticks (measured: Progress and the tick count unchanged over 20 s paused).
- Any garden action resumes it FIRST (even a refused one), and so does the gardener's own step: their client's
  Rest wakes 0.4 s after the thumbstick moves and asks the server (a resume is never held back by the 0.5 s
  cooldown). A move of the character that is not the gardener's input (a neighbour walking into them, a fling)
  resumes nothing: REVIEW-2 found that the server's old 4-stud poll let another player unpause you, and the poll
  is gone (check_gnomegardendefense_grief: 10 shoves of 1-12 studs, the garden stayed paused, no tick sent).
  Gardeners do not collide with each other at all (the `GardenPlayers` collision group).
- PAUSE pressed while walking does not pause and flicker: the overlay says "Stand still, then press PAUSE"
  (REVIEW-2: the 0.4 s wake landed inside the server's cooldown and was answered "Slow down a little").
- The AFK hold counts only the gardener's own input as "here": a garden action, PAUSE, or the client's `Here`
  (sent at most every 5 s while the thumbstick, a key, a tap or a click is in use). A hazard's knock or a shove
  moves the character but is not input, so an absent gardener stays held (check_grief: 5 shoves over a minute).
- Pressed with a hazard on its way, PAUSE is queued ("⏸ ...") and starts the first still moment after it
  (measured: no pause at the press, paused after 6 s). Never a panic button.
- A respawn while paused leaves the garden paused and the hazard clock frozen (200 s, no hazard).
- Paused mid-wave, the bugs stay drawn where they stood (3 s without a tick: the same 103 bug parts).
- **Why it is not an exploit:** the board metric is a wave count, not a time, and a pause stops both sides;
  all it buys is thinking time, which a script already has unlimited of.

## 5. Budgets (measured, check_gnomegardendefense_env, at the middle of every band and every seam)

| budget | cap (Config.Budget) | worst measured |
|---|---|---|
| local scenery + critter + hazard parts | 200 | 52 (blossom-summer seam) |
| emitters switched on | 4 | 2 (+ the shared burst emitter when it fires) |
| weather emitters on at once | 2 | 2; asked for 4 kinds at once the art still switched on 2 at 42 particles/s |
| particles per second | 60 | 40 |
| lights | 3 | 1 (the moon) |
| beams | 8 | 4 (the rainbow) |
| hazards out | 1 | 1 |
| bugs drawn / bug parts | 40 / 120 | 45 sent: the 40 furthest drawn in 103 parts |

GardenTick: the bugs are packed text (`Wire`): 35 bugs = 594 bytes, 5.8 KB/s per player at 10 Hz (Wire.spec).
Whether a low phone holds all this is a Studio item.

## 6. Phone first

`check_gnomegardendefense_hud`: PASS at 16 viewports (hudcheck's ten plus six phones) x 3 modes (idle, the gnome
sheet open, the result panel up) with the overlap rule ON: nothing off screen, every tappable thing >= 44 px on
touch, nothing tappable under the thumbstick or the jump button, no two panels overlapping, panels at most 27.0%
of a phone screen (568x320 with the result panel up; 24.8% on 640x300 with the sheet open). On the shortest phones
READY and the sheet move into the bottom band's middle (between the thumbstick and the jump button).

**The garden view (REVIEW-1).** At Roblox's default camera from the deck every pad was under 44 px on an 844x390
phone (the three glowing ones a median 3.8 px tall). The whole bed cannot be on screen AND 44 px a cell on a
390 px tall phone: nine rows under the HUD leave about 17 px a row (GardenCam.spec: 16.8 px at the best
whole-garden framing, pitch 58, FOV 45). So `View.client` does what phone strategy games do:
- the camera (Scriptable) frames the whole garden under the HUD, the board and the gardener included: every pad
  on screen and none under the top rows (check_gnomegardendefense_reach, section 1);
- a tap picks the gnome whose body it hits, else the pad whose 8-stud cell is under the finger, else the nearest
  pad within one cell (GardenCam.pickRay, GardenCam.spec); pads have no ClickDetector;
- on a touch screen a tap on a cell under 44 px PICKS NOTHING: the view zooms in on it (52 px; its neighbours
  45.4 px or more, GardenCam.spec) and the HUD says "Tap the pad you want"; the pick is the next tap, on a big
  cell (REVIEW-2: picking at once from 16-17 px cells opened ANOTHER pad's sheet for 42% of fingers 12 px off
  centre). Measured (check_gnomegardendefense_reach section 10): a finger 12 px off centre in 4 directions on
  every pad, 0 sheets from the first tap, 0 wrong pads from the second. The picked pad is drawn GOLD (neon) in
  the world while its sheet is open, so a wrong pick shows;
- the view eases back to the whole garden 2.5 s after the sheet closes, 6 s after a zoom nobody followed up, and
  at once on a tap on nothing;
- no pad of the whole-garden view lies under Roblox's touch controls: on a touch screen the framing moves the
  garden sideways (and shrinks it a little when that is not enough) until no pad's cell (4 px margin) overlaps
  the thumbstick's frame or the jump button's corner (`GardenCam.fitClear`; REVIEW-2 found 8-11 pads a bed under
  the thumbstick). The thumbstick's frame is the WIDER one Roblox's DynamicThumbstick takes touches in as the
  reviewer recalled it, the left 40% of the lower two thirds (`Config.Hud.StickW/StickH`); it holds the HUD's own
  35% band corner on every phone. Measured: 0 pads in either on 844x390, 568x320, 640x300 and 926x428 (reach
  section 11); over 40 beds x 5 phones, 2644 cell overlaps with the plain fit, 0 now, at most 7% of a cell's size
  given up (GardenCam.spec: 93-100% kept). The garden sits right of the screen's centre on a phone;
- the pads that see the most path GLOW (neon green) all game while there is room for a gnome: the three best free
  pads for the gnome the sheet stars (★). The star is the gnome furthest below its share of Config.Suggest
  (4 : 1.5 : 2 : 1.5); it is exactly what the pacing model's normal player plants (REVIEW-2: the glow used to
  stop at the first gnome, and the brag's 33.6 min assumed a player who knew the best pads per gnome);
- in the board view a tap picks nothing (REVIEW-2: a tap on the board's face picked pads hidden behind it);
- a mouse on a 1280x720 desktop picks without the zoom: the whole-garden cells are 33.4 px and more there
  (GardenCam.spec: 33.6 px at worst; a mouse target needs 24, WCAG 2.2).

## 7. Needs Studio (only real rendering, input and network can settle these)

1. The garden view on a real phone: does the whole-garden framing read (pitch 58, FOV 45), does the zoom on a
   tap feel right (0.12 s half-life), and are 17 px cells good enough to aim the FIRST tap near the right pad?
2. Taps: `UserInputService.TouchTap` reaching the game with `gameProcessedEvent = false` on the 3D world, and
   `Camera:ScreenPointToRay` with TouchTap's positions (below the GUI inset) giving the same ray as
   GardenCam.ray headless; a mouse click through `InputBegan` on a desktop.
3. Movement under a Scriptable camera: the thumbstick moves the gardener relative to the north-facing view; the
   view keeps up on respawn; outside the garden Roblox's own camera takes over and gives it back.
4. `BindToRenderStep` at the camera's priority: FxClient.shake (bound one step later) still shakes, and an FOV
   punch plays out (the view writes FieldOfView only when its own target changes).
5. The sky look on HARVEST MOON and AURORA (4.5 s): the moon and the aurora actually in frame from the deck view.
6. Bugs drawn from 10 Hz snapshots: smooth at 35 bugs; ants at 10 studs/s; the boss models' scale.
7. Every band's look (the lighting tables start from +1 Jump's bands); the moon reaching full as the Queen falls;
   the night path glow (Neon gravel) readable and not garish; the dandelion fluff at dawn.
8. The red ring on grass, gravel and snow; an acorn falling seen in the hazard zoom; the knock-down; the daze.
9. PAUSE: the freeze reads as a freeze; the thumbstick wakes it; the PAUSED overlay on a phone.
10. The board on the deck's west end: readable in the board view (72% of the screen's height headless), its
    ProximityPrompt on touch; in the whole-garden view it is small (a landmark, not a read).
11. Gnome, bug and boss models built from Parts: silhouettes readable in the whole-garden view.
12. Bandwidth (GardenTick measured at 5.8 KB/s per player headless) and frame time with 8 players on a low phone;
    frame time at the densest seam (harvest to moon) with 35 bugs.
13. The bed is rebuilt on every attempt (144-150 Parts headless): whether the rebuild on TRY AGAIN hitches.
14. The engine's spawn placement on a non-collidable SpawnLocation flush with the deck.
15. The meadow (one 864 x 704 part under every slot, 0.2 below the lawns): no z-fighting at the lawn edges.
16. Publish settings: Max Players 8 (8 garden slots; a 9th player gets an overflow slot), the published
    place's Workspace.StreamingEnabled = false (pinned in default.project.json; tests/project_spec.py checks it),
    and **Playable Devices: Computer, Phone, Tablet, with Console OFF**: there is no gamepad path to pick a pad
    (REVIEW-2, finding P8; a gamepad cursor is a later pass).
17. DataStore under real latency: a reconnect within 45 s of a crash shows "not being saved" and then "saved
    again" within about 10 s of the old lock running out; the day's endless bed is the same on two servers.
18. Filming: tools/film_game.py scripts its own camera; a GNOME entry must set the camera attribute
    `ExternalCamera = true` first, or the garden view takes the camera back every frame (MARKETING.md).
19. Gardeners pass through each other (collision group `GardenPlayers`, not collidable with itself), and still
    stand on the deck, the lawn and the meadow and stop at the hedges (robloxemu has no PhysicsService: the
    configuration is checked, the physics is not).
20. Roblox's real thumbstick area. The HUD keeps clear the bottom band's left 35% (the repo's hudcheck rule); the
    garden view keeps its pads out of the left 40% of the lower two thirds, the DynamicThumbstick frame as REVIEW-2
    recalled it (`Config.Hud.StickW/StickH`). On a phone: where does a touch start the thumbstick, and does a tap
    there still reach `TouchTap` with gameProcessed false? If the frame is smaller, shrink StickW/StickH (the
    garden then sits nearer the centre); if larger, grow them (`fitClear` takes any zone).
21. The gold selected pad and the green glowing pads read clearly in every band (the night bands' neon path
    too), and the ★ in the gnome sheet is legible at 44 px.
22. `Here`: the client's MoveDirection, InputBegan and TouchTap see the real thumbstick, keys and taps; an idle
    gardener whose character a hazard knocks (28-36 studs/s sideways) is still held after 180 s.
23. The "Stand still, then press PAUSE" notice on a phone, and a quick tap-then-walk (the wake 0.4 s after a
    pause) feeling like a resume, not a glitch.

## 8. Thumbnail shots (1920 x 1080, subject inside the middle 1280 px)

1. **Harvest Moon over a full bed**: camera 30 studs above the deck's east end, looking north-west over the bed;
   in frame: the giant moon low over the north hedge, paper lanterns lit, the Slug Queen mid-path with her health
   bar, ~10 gnomes with lanterns glowing. Needs a save that really reached wave 30 (§ MARKETING.md rules).
2. **Low angle behind a Pebble**: camera 3 studs behind and 2 above a level-3 Pebble gnome on a pad beside the
   path, aphids filing past, Blossom Morning (petals falling, blossom trees on the hedge line).
3. **The board at dusk**: Snowfall band (dusk 17.5), the board on the deck's west end (it faces south), camera on
   the deck 10 studs south-east of it, the board filling the right half with a friends view showing two rows,
   the garden behind.
4. **Aurora over a snowed bed**: camera high over the south hedge looking north; aurora beams across the sky,
   snowdrifts, a full 14-gnome bed, a wave mid-path.

## 9. Gates and the mutation sweep

REVIEW-1 (two adversarial reviews) changed the gates and ran its own sweep: the current counts, the mutation
table and the control are in `REVIEW-1.md`. What follows is the build's first sweep, kept as it was.

Gates (bundle rebuilt first, the build's final run 2026-10-07): 13 specs, 938 assertions; check_gnomegardendefense 94, _save
38, _env 103, _hud PASS (48 viewport-modes); tests/walk.luau 20. All 0 failed. All 39 Luau files compile.
Run on the luaushim (CLAUDE.md "State"). The main check plays a server-random bed: 6 of 6 runs green, spring won
on the first attempt every time (201-372 s of play).

Mutation sweep (`scratchpad/ggd/mutate.py`): an isolated copy of the game and the checks; each mutant restored
from the real file, applied, its md5 verified changed, the bundle rebuilt, then every gate (13 specs, 4 checks,
the walk) until one fails; a run with no summary line counts as KILLED.

| # | mutant | killed by |
|---|---|---|
| M1 | the armour floor ignored | Garden.spec (a 2-damage pulse on armour 2) |
| M2 | slows stack | Garden.spec (two sprinklers: 0.22, want 0.40) |
| M3 | a boss through the patch does not lose | Garden.spec |
| M4 | a taken pad can be planted on | Garden.spec |
| M5 | the build timer ignores the AFK hold | Garden.spec |
| M6 | `RespawnLocation` not set | check (RespawnLocation, and the landing on the own deck) |
| M7 | a paused garden still steps | check (nothing moves for 20 s paused) |
| M8 | an action does not resume a pause | check |
| M9 | the bed seed copied to a garden attribute | check (the leak scan) |
| M10 | no rate limit | check_save (60 served, want 20) |
| M11 | the hazard clock ignores the server's pause | check_env, after a test was ADDED: it SURVIVED the first sweep (the local rest state hid it); a respawn while paused now kills it |
| M12 | the red ring 25% bigger than the zone | check_env (diameter 7.5, want 6.0) |
| M13 | the weather cap off | check_env, after a test was ADDED: it SURVIVED the first sweep (the config never asks for more than 2 kinds); asking for 4 now kills it |
| M14 | the gnome sheet over the thumbstick | check_hud |
| M15 | pads from a 4-neighbourhood | Garden.spec / PathGen goldens (40 pads, want 43) |
| M16 | a nearly dead bug sent as 0% | Wire.spec |
| M17 | the moon full a wave early | EnvConfig.spec |
| M18 | a dazed tap still plants | check_env |
| M19 | the named band from the smoothed progress | check_env (the chip still says Harvest Gold at 30) |
| M20 | a won season does not unlock the next | check (summer unlocked) |
| M21 | a stale session token still saves | check_save (the other session's record overwritten) |
| M22 | pads that cannot reach the deck | check (every pad tappable from the spawn) |
| CONTROL | the sign's separator `-` -> `/` (a real change nothing reads) | **SURVIVED all 19 gates**, as a control must |

22 of 22 killed, the control survived: the sweep can say SURVIVED, so the 22 KILLED are not a broken harness.

## 10. Differences from DESIGN.md, and why

- `Hazards.luau` also carries +1 Jump's `threatLive` (Deep Vein's copy predates it): the ring and the banner
  stay up while the rest of the flight can still hit someone inside the ring.
- `Waves.wave` sums the mix weights in name order (the model summed in table order; see CLAUDE.md traps).
  The rewired model reproduces the design's numbers exactly (33.6 / 30.3 / 53.3 / 61.8 and every win rate).
- The boss bar lives inside the top bar (it replaces the next-wave preview during a wave): a separate bar did not
  fit between the top rows and the touch controls on a 360 px phone without overlapping the sheet.
- GardenTick packs the bugs as text (Wire); the design estimated 2.6 KB/s, a table of doubles measured about 2.5x
  that, the packed text 5.8 KB/s.
- The model's `tests/mirror/` (the design stage's JS copy) was moved to the scratchpad after the Luau run
  confirmed it (the design asked for it to be deleted; it was moved, not deleted).
- REVIEW-1 changed six things the design did not have: the garden view (a Scriptable camera that frames the
  whole garden and zooms where a pad is tapped; the design assumed Roblox's camera from the deck), a sale on the
  reveal gives everything back (the design's 70% everywhere let a spring bed sell itself into a dead end),
  progress counts bugs stopped (not bugs gone), the board stands on the deck's west end facing the camera, a
  meadow under every slot, and weather in every band (the dawn's fluff; Moonlit Snow's frost glitter instead
  of Snowfall's snow). None of them changes a balance number: Pacing.spec is unchanged (27 passed, brag median
  33.6 min).
- REVIEW-2 changed these (REVIEW-1.md has each finding and its measurements):
  - DESIGN.md §9: the server no longer polls the character ("a 4-stud step resumes"). A pause ends only by the
    gardener's own input (their client's wake, the button, a garden action), and the AFK hold's "here" is a
    garden action, PAUSE or the client's `Here` (the gardener's own thumbstick, keys or taps). Gardeners do not
    collide with each other. SetPaused's cooldown holds back pausing only, never a resume.
  - DESIGN.md §10 point 6: while the day's store is down a server plays ONE bed of its own for the day (it was a
    new one every minute: an endless bed could be rerolled). The board's prompt answers one toggle per 0.5 s.
  - DESIGN.md §4 and §14: the normal profile's "one of the 3 best pads for that gnome" (padTop 3) is now what the
    screen shows: the sheet stars a gnome (`Garden.suggestKind`, weights `Config.Suggest` = the normal mix) and
    the 3 best free pads for it glow all game (`PathGen.bestPads`). The model plants exactly that; every number
    is unchanged (Pacing.spec 29 passed: brag median 33.6 min, p90 53.3, worst 61.8; normal first try
    98/95/78/57%).
  - DESIGN.md §15 / §17: on a phone the first tap on a small cell zooms and picks nothing; the pick is drawn gold;
    the whole-garden view keeps pads out of the thumbstick and jump corners; the zoom is 52 px (was 48).
  - A season's win and the band it reaches share one card and one flash (the band's card replaced the season's
    after one frame: "The Slug Queen falls!" was never readable).
