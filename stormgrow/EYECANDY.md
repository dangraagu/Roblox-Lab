# StormGrow — the sky over your farm, the weather's show, hazards and rest

Owner's standard §2 (2026-09-17 / 2026-09-30): the world changes as the player progresses, following the game's
own logic; rare telegraphed hazards whose red ring is exactly the hit zone; a pause that is never an exploit;
budgets measured and capped in code; a brag moment at 30-45 minutes. Built 2026-10-01 with the game, from
`DESIGN.md` §3-§6. **Nothing here has been rendered.** Every number is measured headless; how it LOOKS is the
needs-Studio list (§8).

## 1. What is in the build

| piece | where | template |
|---|---|---|
| bands on the lifetime harvest, blended and glided | `src/client/Sky.client.luau` + `Config.Env.Bands` | `EnvBands.luau` verbatim from plus1-jump (sha256 `42d148b6…`) |
| the global weather event as an overlay (storm, frost, rainbow) | `Sky.client` + `Config.Env.Overlays` | `EnvBands.overlay` |
| scenery, critters, weather particles, rainbow arc, storm wall, bolts, hazard models | `src/shared/ValleyArt.luau` (client-required only) | new; plus1-jump's `SkyArt` pattern |
| crops, marks, strikes, onboarding glow and arrow, "+N" pops | `src/client/Farm.client.luau` + `src/shared/CropArt.luau` | new |
| hazards | `Sky.client` + `Config.Hazards` | `Hazards.luau` verbatim (sha256 `bd470578…`, the working copy with `threatLive`) |
| the two flat-ground adaptations | `src/shared/HazardGlue.luau` | new, §3 says why |
| rest | `Sky.client` + `Config.Rest` | `Rest.luau` verbatim (sha256 `45044098…`) |
| Fx preset `Farm` = band 1, so the first frame is already the meadow | `src/shared/Fx.luau` | Fx verbatim + one preset (the only change) |

The copied specs ran unchanged: EnvBands.spec 124/0, Hazards.spec 111/0, Rest.spec 55/0, responsive.spec 70/0
(sha256 identical to plus1-jump's: `bd499cba…`, `cafb8067…`, `f13bceaf…`, `02c900b5…`).

## 2. The bands and what triggers them

**Trigger: `Harvested`**, lifetime coins earned from harvests. The server writes it (Player attribute), it only
goes up, spending never lowers it. The client blends every value by it with `EnvBands` (fades are a third of
each threshold, rounded as in DESIGN.md §3.2) and glides with a 0.6 s half-life, so a Tempest Pumpkin (+480,000
in one tap) or a rejoin deep in the ladder never cuts. Lighting is written at most 10 times a second and only
when a value changed. The valley floor takes the band's ground colour (a local change to the server's Ground part).

| # | band | from | reached (normal, median) | light | scenery (client) | critters | weather | hazards |
|---|---|---|---|---|---|---|---|---|
| 1 | 🌱 Sunny Meadow | 0 | 0 | ClockTime 9.5, fresh green | 16 hills, 10 oaks, a pond, a farmhouse | 8 butterflies | dandelion fluff | none |
| 2 | 🌾 Golden Fields | 150 | 2.9 min | 11.5, warm yellow | gold hills, 12 hay rolls, a turning windmill | 6 bees, 5 sparrows | pollen | hay bale |
| 3 | 🍂 Windy Orchard | 1,200 | 7.9 min | 15.5, amber | 14 orange/red orchard trees, a red barn, a scarecrow | 5 crows | falling leaves | hay bale, crow |
| 4 | ⛈️ Thunder Plains | 9,000 | 14.9 min | 16.8, violet-grey | a dark cloud bank on the horizon with silent bolts, a lightning rod | 7 geese | drizzle | crow, ball lightning |
| 5 | ❄️ Frost Highlands | 55,000 | 23.2 min | 17.6, blue-white | 10 snow-capped peaks, 14 pines, a frozen waterfall | 3 snow owls | snow | snowball, ball lightning |
| 6 | 🌀 **Eye of the Storm** | 300,000 | **36.6 min** | 17.2, golden hour, bloom 1.5 | **a turning storm wall around the valley (24 segments, rising with the band's weight), lightning veins, a sunbeam on your farm, 6 floating isles** | 10 storm sprites | sparks | ball lightning, dust devil |
| 7 | ✨ Starfall Summit | 11,000,000 | 120.8 min | 22.5, night, 3,000 stars | aurora ribbons, falling stars, 11 lanterns on your own fences | 14 fireflies | star glints | ball lightning, snowball, dust devil |

Minutes are `tests/Pacing.spec.luau` on the real modules (200 sessions). Every band lasts at least 2 minutes for
the normal player (asserted). Band 1 lasts 2.9 min and has no hazards: that is the learning time.

**Events on top of the band** (`Weather.weight` on the server clock: 0 -> 1 over 4 s after the start, back over
4 s before the end): a storm halves the light, violet fog, heavy rain, distant bolts every 3-6 s, and a bolt onto
every crop that takes a mark (nearest 6 at once); a frost tints the fog and grade blue-white, snows, ices your own
soil, and bursts an ice ring on each crop it marks; a rainbow brightens and saturates, draws a seven-colour arc
in front of your camera, and a prism column on each crop it marks. Measured in `check_stormgrow_env.luau`: a
storm in Windy Orchard takes Brightness from 2.9 to 1.45; the arc's 7 beams are up in every rainbow and in no
other event, in every band.

**The brag.** Crossing 300,000 during play: the card "🌀 YOUR FARM IS IN THE EYE OF THE STORM", a white flash
and an FOV punch, the storm wall rising to its full 300 studs as the band blends in, and a server-wide toast
"🌀 <name>'s farm entered the Eye of the Storm!". Stormfruit goes on sale (the unlock is gated on the same
threshold, one number in `Config`). A player who joins already past it gets a quiet card with the band's name
(the announcer is seeded when the profile has loaded). Measured: 1 card at join, one per new band on the way
up (5 by band 5), exactly one brag card, none on a second crossing; a farmer past the brag whose farm another
server holds for 12 s sees no card while the load waits, then exactly one quiet card ("🌀 EYE OF THE STORM").

**The skill brag.** The first Tempest (x200): flash + FOV punch on your screen, a server-wide toast "⚡❄️🌈 <name>
grew a TEMPEST Pumpkin!" (at most one per player per 30 s). The pacing model: the player who keeps marked crops
for the next event finds the first Tempest at 20.1 min median; one who harvests marked crops at once, never in
2.5 h. The golden sequence has to be learned.

## 3. Hazards and their measured rarity

StormGrow keeps real hazards although it is a grower (DESIGN.md §4): the loop is on foot between six fields, the
theme is weather, and a hit costs about 2 s and nothing else. Hazards are client-only; the server never sees them.

| kind | bands | speed | telegraph | ring radius | lane | knock |
|---|---|---|---|---|---|---|
| hay bale | 2, 3 | 16 | 3.5 s | 4.0 | 56 | 34 |
| crow | 3, 4 | 24 | 3.0 s | 3.3 | 72 | 30 |
| ball lightning | 4-7 | 18 | 3.5 s | 3.5 | 63 | 38 |
| snowball | 5, 7 | 20 | 3.2 s | 4.0 | 64 | 34 |
| dust devil | 6, 7 | 12 | 4.0 s | 4.5 | 48 | 30 |

**The two adaptations to flat ground (`HazardGlue.luau`), and why.** plus1-jump's climber stands over open air.
1. The camera pitch handed to `Hazards.step` is clamped to >= -25 degrees (`GroundPitchFloor`), equal to the view
   half-window, so the window's upper edge is never below level and no lane STARTS below the player's root.
   Measured over 2,160 lanes: lowest start 3.00 (the root height).
2. **A finding of this build:** DESIGN.md §4 promised "no lane point is ever below ground + 1 stud", and the true
   flight breaks it. A descending lane (crow 6 ± 4 degrees, ball lightning 4 ± 3) flies on past the player for
   `pass` seconds and reaches **3.21 studs below the ground** (`tests/EnvConfig.spec.luau`, first run). The fix is
   in the glue: the hazard is DRAWN no lower than ground + 1 (`drawnY`), and hits keep using the true flight,
   which is lower there, so the clamp can only make a hit less likely than it looks. Measured through the real
   client: lowest drawn centre 1.00.

**Measured through the real client (`check_stormgrow_hazards.luau`):**
- band 1: 0 hazards in 400 s of play;
- 24 hazards of all five kinds: every warning frame had the ring and the banner up; the ring's centre and radius
  matched `Hazards.zone` on every frame; 16 players who stepped out of the ring in 8 directions were never hit;
  8 of 8 who stayed were hit;
- a hit: PlatformStand, back up within 0.9 s, coins unchanged;
- rarity on the real clock, 20 min in Windy Orchard: 8 hazards, one per 150 s, gaps 133-175 s (a player who keeps
  moving);
- rarity on the REAL PLAYER PATH (REVIEW-1 B2): a normal farmer stands still between sweeps, and the template's 20 s
  idle rule rested them for 44-55% of a session with the hazard clock frozen: one hazard per ~5.3 min. With
  `Config.Rest.IdleSeconds` = 90, eight long walks to the brag (8 boot phases, `tests/walk.luau`'s player): 10-14
  hazards per session, one per 159-213 s (median 173 s), 3.8-14.6% of frames in rest; the walk at 60 boot phases:
  0-13% in rest, 4-6 hazards in its 18 minutes, 303 rings stepped out of, 0 hits;
- **the ring is drawn ON what the farmer stands on** (REVIEW-1, found while measuring): it was drawn 0.05-0.25 studs
  over the ground, inside the porch (top 0.4), the farm pad (top 1) and the soil plates (top 0.6), so wherever a
  farmer usually stands it was hidden (0 of 16 points on its face seen from the camera on the pad, the porch or a
  plate). `HazardGlue.ringY` now lays it on the highest top under its footprint: 16/16 on the pad, the porch, a soil
  plate, the bed and the grass (`check_stormgrow_hazards.luau` part G, which also checks the glue's floor map
  against the server's parts at 3,577 points);
- on screen (camera 14 studs behind, 70-degree FOV, 2-degree margin): the ring and the banner on EVERY warning
  frame at pitches -60, -40, -20, 0, +20 on 16:9 and 4:3. The hazard MODEL at the moment of launch:

  | camera pitch | -60 | -40 | -20 | 0 | +20 |
  |---|---|---|---|---|---|
  | model on screen at launch (16:9 and 4:3) | 0/12 | 7/12 | 12/12 | 12/12 | 12/12 |

  A player looking steeply down at their crops sees the ring and the banner first and the model when it comes
  into view; that boundary is the price of lanes that never start underground.

## 4. Rest — what "pause" means here

☕ in the top bar, or stand still for 90 s (no step, no tap: AFK; the template's 20 s rested a normal farmer half
the time, REVIEW-1 B2). You sit down (manual rest), the view softens (depth of field) and the
chip says "☕ Resting · the wind leaves you alone". **Rest freezes only the hazard clock**, frozen and never reset.
Growth and the weather cannot pause: the clock is global, and a player standing still gets exactly the same
growth and marks. So rest earns nothing that standing still does not.

Why it cannot be exploited (each measured in `check_stormgrow_rest.luau`, 32/0):
1. ☕ with a hazard inbound only queues (no sit); the hazard still arrives and a player who stays is hit;
2. while resting the hazard clock is frozen (30 s of rest: it moved < 0.3 s) and resumes from where it froze;
3. moving wakes you; **a server-accepted farm action wakes you** (the `ActionSeq` attribute), because a tap does
   not move the character and without that rest would be hazard-free farming;
4. **a farm action also counts as activity for the idle timer** (a finding of this build: `tests/walk.luau` showed a
   farmer tapping from the porch drifting into idle rest; taps every 45 s for 180 s never go idle at the 90 s rule,
   and the hazard clock runs the whole time);
5. toggling rest every 7 s over 120 s of play: the hazard clock counted exactly the play time (128.5 s = 120 s of
   walking + 8.5 s of stops), the same as plain play, so toggling does not thin hazards;
6. a Radish planted before resting is ripe on time and sells for 5.

## 5. Client vs server, and why

Everything in this file is client-side and cosmetic, or touches only the local character (a knock), whose physics
the client owns anyway. No client script fires a remote from this code, and the server reads nothing from it. The
server's part is the weather's substance: the strike loop marks ripe crops at its own ticks (`Mutation.strikeTick`,
unseeded `Random`), writes `Marks` and `LastStrike` on the tile parts, and the client turns a new `LastStrike`
into the show. The one client-local attribute (`RestState` on the local Player) never replicates.

## 6. Budgets (caps in code, measured by `check_stormgrow_env.luau`)

| what | cap | measured peak | where the cap lives |
|---|---|---|---|
| server Parts | 1,400 | 738 | `check_stormgrow.luau` counts the workspace |
| client crop Parts | 1,620 | 1,620 (six full farms, every tile a Tempest: 5 parts each) | `CropArt`: 2 + one per mark |
| client scenery Parts | 700 | 94 (the Eye; 94 at the frost->eye seam) | lazily built pieces, destroyed 2 s after weight 0 |
| critters | 60 | 14 (Starfall fireflies) | `ValleyArt.updateCritters` |
| PointLights on | 12 | 12 (the eye->starfall seam: sunbeam + 11 lanterns); the cap itself: lowered to 5 in memory, exactly the 5 nearest of 11 stay on | `ValleyArt.capLights`, nearest first |
| weather emitters on | 4 | 2 (a band's own + the event's) | `EnvBands.capRates` |
| mark emitters | 24 | 24 (324 marked crops on screen) | `Farm.client`, nearest within 90 studs |
| bolts at once | 6 | 6 (324 simultaneous strikes) | `Farm.client` |
| hazards at once | 1 (<= 30 parts) | 1 model + ring + lane, <= 5 parts | `Hazards` module rule |

Per band (clear sky, after the glide): meadow 41 scenery / 8 critters / 0 lights; golden 57 / 11 / 0; orchard
67 / 5 / 0; thunder 49 / 7 / 0; frost 65 / 3 / 0; eye 94 / 10 / 1; starfall 68 / 14 / 12. Every band, seam and
event (storm, rainbow, frost in all seven bands) stayed inside every cap.

## 7. Gates

`CLAUDE.md` lists every command. For this file: `tests/EnvBands.spec` 124, `tests/EnvConfig.spec` 129,
`tests/Hazards.spec` 111, `tests/Rest.spec` 55, `robloxemu/check_stormgrow_env.luau` 104, `_hazards` 114,
`_rest` 32, `_aim` 22 (taps and the spawn view), all 0 failed (2026-10-01, after REVIEW-1). Mutation sweep with a control: `CLAUDE.md` §Mutation sweep.

## 8. Needs Studio (only real rendering, real input and live services can settle these)

1. **Every band's look and every event overlay**: exposure, fog against Atmosphere, bloom 1.5 in the Eye, crop
   readability at night in Starfall, lantern strength, the valley floor's colour per band.
2. **The lightning bolt** (four neon segments, 0.25 s): does it read as lightning; flash strength; the camera
   shake within 20 studs.
3. **The rainbow arc**: seven curved Beams between two anchors 380 studs in front of the camera, `Attachment.Axis`
   = up and `CurveSize0/1` = ±(420 - 9i). The curve semantics are unverified; visible on a phone at distance; at
   night in Starfall.
4. **The storm wall** (24 parts, 95 x 300 x 40, at radius 330): culled at low graphics quality? If so, closer and
   smaller.
5. **Crop models**: 8 silhouettes (2 parts each) through their growth stages; Charged (a jumping neon spark),
   Frosted (an ice box) and Prismatic (a turning, colour-cycling halo) told apart at 30 studs on a phone, and by a
   colour-blind player.
6. **Tapping tiles on a phone** (REVIEW-1 B1 replaced the ClickDetector hitboxes): a tap is
   `UserInputService.TouchTap` (a mouse click: `InputBegan`/`InputEnded` of MouseButton1, within 0.6 s and 12 px),
   turned into a ray by the engine's `Camera:ScreenPointToRay` and picked against the drawn crop parts and soil
   plates (`Pick.luau`); the client sends `Tap(slot, key)`. Headless, the ray is `Pick.viewportRay` (robloxemu has
   no camera rays), and 1,599 aimed taps over 6 fields x 6 camera poses landed on the tile under the thumb, 1,599.
   The owner's name plate now sits low on the porch's front edge: on a post 4.5-7.5 studs up behind the pad it hid
   all of field 1 from a spawn camera at a 15-20 degree pitch (Roblox's real starting pitch is the Studio question).
   Studio must settle: TouchTap's positions are in the same GUI-inset space as `ScreenPointToRay` (the topbar);
   `gameProcessed` is true for a tap on a HUD button, the thumbstick and the jump button; a camera drag never
   arrives as a TouchTap; a click with shift-lock on picks the screen centre; the TileInfo hover (desktop) follows
   the pointer via `GetMouseLocation` + `ViewportPointToRay`. A gamepad cannot farm (it could not with the
   ClickDetectors either).
7. **The spawn**: does the engine keep FarmPad's yaw; does the post-parent CFrame write look like a snap.
8. **Hazards on flat ground**: lanes at a phone's camera (headless: the model is on screen at launch 0/12 at
   -60 degrees, 7/12 at -40); a hay bale rolling through crops and fences; the knock with PlatformStand on flat
   ground; how a knock looks to other players.
9. **Rest's sit** (Humanoid.Sit without a seat) replicates; a tap ends it.
10. **The top bar on a real phone**: notch and safe area, the forecast text's length, emoji in TextScaled labels,
    the Almanac grid's 39-px cells on a 414-px phone.
11. **Frame time** on a mid/low phone during a storm with six full farms (1,620 crop parts, 24 mark emitters,
    rain, up to 6 bolts).
12. **Live services**: GetFriendsAsync and OrderedDataStore with real friends and throttles; the session lock
    across a real fast server hop; the DataStore's number precision (planting times are stored to the
    millisecond because the emulator's JSON keeps 14 significant digits; Roblox's is undocumented).
13. **Two servers side by side** show the same weather to the second.
14. **Server-wide toasts** (Tempest, Eye) in a full server: exciting or spammy.
15. **The boards**: a SurfaceGui created by each client and parented to the board part (so two players see their own
    view), on the 18 x 11 market board (top 10) and on the 10 x 6.6 porch board 15 studs from the pad, turned to
    the spawn camera (top 5; REVIEW-1 B5 moved it from 36 studs and 0.26-stud rows). Headless arithmetic: a row is
    13.0 pt (porch) and 13.7 pt (market) on a 360-pt phone from the prompts' 12-stud reach, and the porch board
    hides no field-1 tile from the spawn camera at 4 poses. Does it render; is TextScaled at 40 px per stud crisp;
    it does hide some field-3 tiles from the SPAWN camera (field 3 is worked from its own spot, where it does not):
    acceptable on screen?
16. **The onboarding glow**: a SelectionBox on each empty tile you own; pleasant or noisy?
17. **Sound**: rain, thunder, frost chime, rainbow chime, harvest pop. v1 is silent until assets are picked.
18. **Publish settings**: MaxPlayers = 6 (a 7th player now waits and gets the first farm that frees up, REVIEW-1 A3,
    but six is still the design); Workspace.StreamingEnabled = false (pinned in `default.project.json`, checked by
    `tests/project_check.py`; confirm the published place kept it).
19. **The DataStore paths that only a live service shows** (REVIEW-1 A1, A2, A4): a crashed server's lock taken over
    after it runs out (headless: the session takes it 10-20 s after expiry and saves what it played); an outage's
    fresh farm replaced by the real one when the store answers; a record from a newer version shown read-only.
    None of these can be staged in Studio without a second server; watch for them in the first live week.

## 9. Thumbnail shot list (1920 x 1080, for the night shift)

Staging for all: a shots place from `rojo build`, Studio API access OFF so nothing reaches real saves.
`tools/shoot_game.py`'s rule applies: a shot that changes what a player would see goes in `promo/` and is
captioned as promotional. Setting `Weather.ClockOffsetSeconds` only moves the real schedule to "now" (a player
sees exactly this at :00): gameplay. Setting a band with `plr:SetAttribute("Harvested", n)` from the server
command bar, or `Weather.Chance` = 1, is staging: promo, unless a real save that reached that band is used.

| # | name | place and time | camera | in frame |
|---|---|---|---|---|
| 1 | The storm changes everything | band 4 (Thunder Plains), `ClockOffsetSeconds` so the storm starts 10 s in; a field of ripe Pumpkins | low, 3 studs up, 20 studs from a ripe Pumpkin, looking slightly up | a bolt landing on the Pumpkin, the violet sky, the avatar looking up; take a burst (one wave every 5 s) |
| 2 | Eye of the Storm | band 6 | aerial, 120 studs over the market, looking at your farm | the storm wall ringing the valley, the sunbeam on your fields, Stormfruit glowing |
| 3 | Rainbow harvest | band 3, the :01:30 rainbow | behind the avatar tapping a Prismatic Pumpkin | the arc across the valley, the "+N" pop |
| 4 | Tempest (promo) | `Weather.Chance` = 1 for all three events, offset to just before :00; nine ripe Pumpkins | close on one Pumpkin | all three marks (spark, ice, halo), the server toast; at real odds a golden sequence gives a Tempest on 9 Pumpkins 56 % of the time, so this one is staged |

## 10. Not done / open

- Nothing has been rendered or played by a person. The whole of §8 (19 items since REVIEW-1).
- No sound.
- The HUD's text legibility is checked for boxes and tap targets, not glyph sizes (no legibility estimate like
  steal-a-cryptid's was written).
