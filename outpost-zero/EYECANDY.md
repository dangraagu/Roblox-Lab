# Outpost Zero — the sky over your city

Status 2026-10-07: built and green in every headless gate (`CLAUDE.md`), never rendered, never opened in Studio. Every
number below was printed by a gate or by the pacing model; the command is named. The needs-Studio list (§8) is what
only real rendering, a real device or a live server can settle, and the thumbnail shots (§9) are night-shift work.
The model document was `plus1-jump/EYECANDY.md`; the structure follows `meteor-drop-tycoon/EYECANDY.md`.

## 1. What there is

| piece | file | runs on |
|---|---|---|
| six environment bands (light, atmosphere, stars, post-fx, scenery, critters, weather), blended by population | `Config.Env`, `EnvBands` (plus1-jump, verbatim), `SkyArt`, `Sky.client` | client |
| Storm Front's silent lightning, at most one distant flash per 3 s | `Sky.client`, `SkyArt:flashLightning` | client |
| the Grand Airship's flight (each client flies its own copy) | `SkyArt:startFlight`, `Sky.client` | client |
| the moored Grand Airship (12 parts, a gold lamp) and the Town Hall's six pieces | `Main.server` | server, public |
| rare hazards with a telegraph and a red ring that is exactly the hit zone | `Hazards` (meteor-drop-tycoon's merge, verbatim), `SkyArt`, `Sky.client` | client |
| ☕ Break and the 60 s idle rest | `Rest` (plus1-jump, verbatim), `Sky.client` | client |
| a new storey grows (0.35 s tween) with a construction puff (`Fx.sparkle`) | `Main.server` | server |
| the ★ marker and its glow over the starred lot's post, ★ Show me (a 4 s beam) | `Hud.client` | client |
| the server's starting light, `Fx.Presets.Dawn` (= band 1) | `Fx` (one added preset) | server |

## 2. The bands, and what triggers them

The trigger is the owner's **population** (the State payload's integer, the same number as `leaderstats.Population`
and the Census), never time. Each band opens with the district that opens at the same population, so the district
sign, the chip and the sky always agree. A band fades in over `fade` population before its `from` (EnvBands'
smoothstep), and every written value glides with a 1.5 s half-life; Lighting is written at most 10 times a second and
only on change. A purchase into a new band shows a title card; a player who joins already in a band gets the chip
quietly.

Minutes are the pacing model's normal player (`tests/Pacing.spec.luau`, [M3]/[M4], 40 seeds; profiles are
assumptions). The walk (`tests/walk.luau`, the last printed run, 2026-10-07) entered them at 3.4 / 12.4 / 37.4 min.

| # | band | from (fade) | enters | lasts | light | scenery | critters | weather | hazards |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌫️ Fogbound Dawn | 0 | 0 | 3.42 min | ClockTime 6.4, haze 0.45 | fog banks round the camera, 5 bare rock spires far out | 3 gulls | fog wisps 4/s | none |
| 2 | ☀️ Clear Morning | 80 (30) | 3.4 min | 8.81 min | 9.0, fresh blue | the cloud sea at y = -80, 5 far shelves with tents | 5 swifts | dandelion seeds 5/s | crate |
| 3 | 🎈 Trade Winds | 900 (300) | 12.2 min | 24.88 min | 13.0, bright | + pennants over your plaza (4 Beams), a far sky-rail line | 3 hot-air balloons | leaves 8/s | crate, sandbag |
| 4 | 🏮 Lantern Dusk (the brag) | 6 400 (2 000) | 37.1 min | 39.01 min | 17.9, gold-pink, bloom 1.5 | the far shelves' windows light up | 12 sky lanterns rising out of the cloud sea | sparks 10/s | crate, spent lantern |
| 5 | ⛈️ Storm Front | 35 000 (10 000) | 76.1 min | 57.74 min | 20.5, violet-blue | a storm wall on the horizon, lightning inside the cloud sea | 3 storm petrels | rain 40/s | lightning, hail |
| 6 | 🌌 Aurora Crown | 185 000 (50 000) | 133.9 min | open | 23.0, 3 000 stars | aurora curtains (4 Beams) | 2 sky whales | glitter 15/s | ice shard, lightning |

Measured by `robloxemu/check_outpostzero_sky.luau` (86 passed, 0 failed): every band's pieces, critters and weather are
up at its middle and the previous band's own pieces have faded; ClockTime reaches each band's value; at population 64
the sky sits part-way into Clear Morning exactly as the smoothstep says, and the purchase across 80 glides (ClockTime
moved +0.361 in the first 1.04 s and +1.429 of +1.440 after 10 s); the title card shows and is gone 10 s later; at rest
under the aurora Lighting took 28 writes in 1 s (cap 400). `Fx.Presets.Dawn` equals band 1 on every field band 1 sets,
and the server applies it before any client runs. `tests/EnvConfig.spec.luau` (189 passed) pins the table above: the
`from` values equal the district thresholds, every fade fits before its band, ClockTime only rises (6.4 to 23.0, under
24), the DESIGN 5.2 lighting values, each band its own weather, and no colour but the ring is reddish.

Storm Front's lightning (`_sky`): 16 flashes in the 74 s spent in the storm band, the closest two 3.10 s apart (the rule
is at least 3 s). Each flash is one Neon cloud 160 studs wide, 6 studs below the cloud sea and 380 studs out, lit for
0.15 s: never the whole screen.

## 3. Hazards: things fall off the frontier

Vertical kinds only (meteor-drop-tycoon's `Hazards.luau`, verbatim: plus1-jump's template with the `threatLive` rule
plus deep-vein's marked vertical section). A shelf is flat open ground, so a sideways lane would start underground;
a vertical kind hangs over the player, tracking them, then falls straight at the spot. The red ring is the zone,
radius `hitRadius + PlayerRadius`, centred where the player stood when the lane last aimed, drawn on what the player
stands on (rock, a plate or a roof). Stepping out of it in any direction always dodges.

| kind | bands | height | fall s | warning s | locks s before | ring radius | knock |
|---|---|---|---|---|---|---|---|
| crate | 2, 3, 4 | 60 | 0.8 | 3.2 | 1.6 | 3.9 | 36 |
| sandbag | 3 | 55 | 0.7 | 3.2 | 1.6 | 3.5 | 32 |
| spent lantern | 4 | 45 | 1.4 | 3.4 | 1.7 | 3.5 | 28 |
| lightning | 5, 6 | 90 | 0.3 | 3.6 | 1.8 | 4.1 | 40 |
| hailstone | 5 | 70 | 0.7 | 3.2 | 1.6 | 3.7 | 34 |
| ice shard | 6 | 70 | 0.6 | 3.2 | 1.6 | 3.7 | 36 |

One every 120-180 s of play on your own shelf, never in band 1, never two at once. The pacing model counts 13 before
the brag for a normal player (min 13, max 14 over 40 seeds); the walk's last printed run met 14, stepped out of 11 and
was hit once (it dodges three times in four by design). A hit is a 0.9 s stumble (PlatformStand and a shove, lift capped at 15 studs/s)
and costs nothing else: no credits, storeys or Orders.

Measured by `robloxemu/check_outpostzero_hazards.luau` (39 passed, 0 failed, with the interval set to 8-9 s in memory):
nothing in 40 s of band 1; nothing off your own shelf (and the clock does not run there); nothing in the air; nothing
during a 40 s break, with the clock frozen and resuming where it stopped; toggling the break every 6 s for 72 s still
gave 8 hazards (the play-time rate is 6-9); the ring's radius equals the zone exactly, is centred on the player, lies
at their feet and is the one red; a player who stays in it is knocked (the control); stepping out at the lock dodged
in 8 of 8 directions; on a 52.4-stud roof the ring was drawn at 52.52; no hazard launched during the Grand Airship's
arrival (the flight and 3 s after the mooring), and they resumed after it.

A title card and a hazard never share the screen (REVIEW-1 F7). On a landscape phone the card sits below the HUD
stack, over the lower middle of the screen, where the avatar's feet and the ring are (800 x 360: card y 216-249, the
screen's centre 180). So a card holds a due hazard until it has gone, and a card that arrives while a hazard is up
waits for it to pass. The same check, now 47 passed, 0 failed: a hazard due under Storm Front's card came 0.05 s after
the card had gone (it had been held 3.7 s); Aurora Crown's card, due during a hazard, came the frame the hazard passed
(4.65 s); no frame had both.

## 4. ☕ Break: what "pause" means here

plus1-jump's `Rest.luau`, verbatim. **☕ Break** (right edge): the avatar sits where it stands, the camera tilts slowly
up to the sky, and the chip says "☕ On a break: nothing falls on you. Orders 8:12". Moving, pressing Break again, or
pressing a lot's BUILD ends it. Standing still for 60 s also rests you (no camera change): 0.5 % of a normal player's
first hour (max 1.2 %; 20 s would be 16.6 %) [M10, `Pacing.spec`].

Why it is never an exploit, each asserted: it pauses only hazards (the clock freezes, never resets: `_hazards` §5); it
earns nothing standing still does not, because income depends only on population and the Orders, and the Orders kept
counting down through a 10 s break (`_sky`); it cannot start with a hazard inbound: the request is queued and the chip
says "☕ Break queued: step out of the red ring first" (`_sky`); and there is no clock to race. A break asked for in
mid-air is queued too and says "☕ Break queued: it starts when you land" (there is no ring to step out of: REVIEW-1
round 2, B4), and it starts on landing (`_sky`).

## 5. Client vs server

Everything in §2-4 except the moored airship, the Town Hall's pieces and the growing storeys is built by the client,
non-collidable, non-queryable and non-touchable, and replicates nothing. Your sky follows your population, so you see
your neighbours' cities under your own sky. There is no client -> server remote in the game at all; `_sky` counted 0
client -> server events in a whole run and confirmed that 300 client frames change no server-built part. The airship's
flight is a client copy on every client (Announce to all), and the server places the moored one after 12 s.

**The hand-over** (REVIEW-1 round 2, B2; `check_outpostzero_handover`, 60 frames a second): the moored airship keeps
its pose (nose along the shelf's +X, broadside to the plaza's view toward district 1, as thumbnail 1 frames it), and
the server sends that nose's direction with the arrival. The copy starts 1 500 studs back along the nose's line,
60 studs higher, and flies straight in, nose first, with one fixed heading, the gondola as the pivot on both sides
(`GondolaY`). It then holds its last pose until the moored model is on that shelf (at most `HandOverSeconds` = 3 s,
for a mooring that never comes) and goes the same frame. Measured: 0 frames without an airship, 0.000 studs and
0.00° between the copy's last pose and the moored model's 12 parts, 0.00° of turn between any two frames of the
flight, and the moored nose square to the shelf's line to the ring's centre. Before the fix: 4 blank frames, a
1.5-stud drop, a 150° snap in the last 0.1 s and a 60° turn at the hand-over.

**Sizes the engine draws as written** (REVIEW-1 round 2, B1). Roblox forces a `Ball` uniform, draws a `Cylinder`
round (Y = Z) and clamps every axis at 2 048 studs; robloxemu keeps any size. So a stretched sphere (the fog banks,
the cloud puffs, the storm wall, the cloud flash, the balloons, the sky whales, the sandbag hazard and the airship's
envelope, client and server alike) is a Block whose Sphere `SpecialMesh` fills the box: `SkyArt`'s and `Main`'s part
helpers do it for any non-uniform Ball, so it cannot come back. The Reactor Quarter dome is a uniform 7-stud sphere
sunk into the roof, so a 3-stud cap shows over a 6.9-stud circle and the collision is the cap you see. `_sky` (every
band and seam), `_hazards` (every hazard kind met) and `check_outpostzero` (the full city with its moored airship)
assert every part shown against all three rules; before the fix they listed 10 stretched Balls.

## 6. Budgets (capped in code, measured every frame)

`Config.Budget`: client parts 200, emitters 4, emitter rate 60/s, weather emitters 2 (`EnvBands.capRates`), beams 8,
trails 8, lights 3, hazards 1; server parts 1 500, server lights 12.

| measured | where | value |
|---|---|---|
| worst client frame over every band and seam, the airship's flight and Storm Front | `_sky` | 51 parts, 2 emitters, 4 beams, 0 trails, 2-3 lights (the cap is 3; the hazards' rolls vary between runs, and the round-1 build printed 3 as well), 2 weather emitters at 39.9/s |
| with hazards in the air | `_hazards` | 52 local parts, 1 light |
| the idle world (6 empty shelves) | `check_outpostzero` | 252 server parts, 6 lights |
| a complete city (36 lots at 22 storeys, the airship moored) | `check_outpostzero` | 239 parts on that shelf (budget 244) |
| three players, one full city | `check_outpostzero` | 516 server parts, 7 lights |

## 7. Gates

`tools/gates.sh` runs all 26 (13 specs, the project check, 11 headless checks, the walk); the counts are in
`CLAUDE.md`. The ones for this file: `EnvBands.spec` 124, `EnvConfig.spec` 189, `Hazards.spec` 153, `Rest.spec` 55,
`HudLayout.spec` 968, `check_outpostzero_sky` 93, `check_outpostzero_hazards` 48, `check_outpostzero_airship` 37,
`check_outpostzero_handover` 15, `check_outpostzero_hud` PASS at 20 viewports with overlap = true.

## 8. Needs Studio (only real rendering, a real device or a live server can judge)

1. **Every band's look**: exposure, ambient and bloom per band; whether the shelf reads in the dawn haze (Atmosphere
   density 0.45) and at night (OutdoorAmbient floor, the night light on the player); the Neon window strips under bloom;
   the gold-pink Lantern Dusk grade.
2. **Atmosphere vs fog**: Roblox ignores the Fog properties while an Atmosphere exists, so the fog is Atmosphere plus
   the client's fog banks (8 translucent ovals round the camera, Blocks with a Sphere mesh). Do they read as fog, or
   as a grey screen?
3. **The cloud sea** (a 2048 x 2048 slab at y = -80 that follows the camera, 6 puffs) and the far shelves at 650-1 250
   studs: culled at low graphics quality on a phone? If so, closer and smaller.
4. **The aurora's 4 Beams, the rising lanterns, the sky whales**: almost certainly need hand tuning.
5. **The Grand Airship**: a 12 s client flight from 1 500 studs out, then the server's mooring. Headless, the hand-over
   is now seamless at 60 fps (§5); under real replication the copy waits up to 3 s for the moored model: does it
   still look like one airship? It now comes in along the moored nose's line (across the ring, past a neighbour's
   shelf about 110 studs off, high over its towers) instead of from straight outside: a good arrival from the plaza?
   Does a 12-part model at y = 120 read on a phone? Is the mooring mast (a 111-stud pole from the Town Hall) a good
   look?
6. **Frame time** on a mid or low phone with 6 cities of up to 36 towers (1 464 server parts) and the full weather.
7. **The lot prompt** at MaxActivationDistance 8 on a sign post: easy to hit with a thumbstick? Does Roblox's
   nearest-prompt choice ever pick the neighbouring lot when you stand between two posts (14 studs apart at least)?
8. **The 0.35 s storey tween**: smooth under real replication, or stepped? (Headless, a tween lands at its end time.)
9. **The knock**: does PlatformStand plus AssemblyLinearVelocity push a humanoid on flat ground and release cleanly?
10. **The ring among towers**: visible when a tower stands between the camera and the player? The light pillar
    readable at midday in Trade Winds?
11. **The break's sit and camera tilt**: Humanoid.Sit with no seat from the client; does the tilt feel good and
    release on the first move?
12. **The top-centre HUD on a notched phone**: safe area, emoji in TextScaled labels, the population chip at its longest
    ("🌌 Aurora Crown · population 1 031 184").
13. **The Census SurfaceGui** in PlayerGui with Adornee: legible from the pad (10 studs); only the owner sees the rows.
14. **The ★ marker** (a BillboardGui, AlwaysOnTop) and its PointLight parented on the client to the server's post:
    readable, not too loud at night?
15. **Players.MaxPlayers = 6** in Game Settings, and SpawnLocation.Duration = 0 really removing the force field.
16. **Climbing**: can players climb stepped towers and jump over the glass from a roof? The rescue below y = -30 makes
    it harmless; keep it, or raise the glass?
17. **Other players see a knock with nothing hitting** (client-only hazards). Does it look like a glitch?
18. **Live server only**: the friends board against real GetFriendsAsync pages and DataStore throttling, GetSortedAsync
    caching, offline earnings across two servers' os.time() (skew of a few seconds is expected and harmless).
19. **Photosensitivity**: Storm Front's lightning at one flash per 3 s at most, never full-screen. Confirm on a screen.
20. **Optional audio** (a construction thump, wind at dawn, an airship horn): library audio ids only.
21. **The roofs**: one part each (pitched wedge, awning slab, sawtooth wedge, radio mast, dome, gold spire). Do the six
    district styles read as different places from the plaza? The dome is a 7-stud sphere sunk into the roof (a 3-stud
    cap): does it read as a dome, and can a player stand on it or do they slide to the roof's corners?
22. **The HUD stack over the avatar on a landscape phone** (REVIEW-1 F7). Measured with `HudLayout.compute`, touch,
    36 px inset, screen px: on 800 x 360 (centre y 180) the warning is at y 153-171, the toast 175-192, the hint
    195-212, the title card 216-249; 640 x 300 (centre 150) has the same y values; 844 x 390 too (centre 195). The
    card can no longer show during a hazard (EYECANDY §3). Still to judge on a real phone with the default camera:
    does the red warning panel, a toast or a hint (the hint row can hold a whole-session "not saving" line) hide the
    ring at the feet? If it does, put the transient rows in a side column on short screens (`HudLayout`, both
    client scripts follow it).
23. **Workspace.StreamingEnabled = false** is pinned in `default.project.json` (REVIEW-1 F8, `tests/project_check.py`).
    Confirm the built place really has it off, then that the ★ marker, ★ Show me and the Census rows work on a phone.
24. **Real DataStore latency on a leave** (REVIEW-1 F2): the shelf is now freed before the leaver's save lands, so a
    newcomer may start building on it while that save is in flight. `check_outpostzero_latency` shows none of the
    leaver's city appears; check on a live server with two accounts that the shelf looks clean. Also (round 2, A1): a
    hop to another server and a quick rejoin to the same one both get the city the player left with
    (`_latency` E, F); confirm once with two servers under real latency.
25. **Stretched spheres** (round 2, B1): the fog banks, cloud puffs, storm wall, cloud flash, balloons, sky whales, the
    sandbag and the airship's envelope are Blocks with a Sphere `SpecialMesh`. Do they read as the ovals they were
    designed as, with the part's Transparency and Material (Fabric, Neon on the cloud flash)? Which axis Roblox would
    have kept for a Ball no longer matters.

## 9. Thumbnail shot list (for the night Studio session, 1920 x 1080)

Set up each shot through a copy of `Config` **in the place only**, never `src/` (the way +1 Jump's list does), or with a
played-up test profile; then revert the place. The profiles below are what the shot needs, not a fake of what the HUD
then shows: hide the HUD (`OutpostHud`, `OutpostSky` ScreenGuis) for every thumbnail.

| # | name | camera | place | in frame |
|---|---|---|---|---|
| 1 | **Lantern Dusk skyline** (the brag) | low on the plaza, 2 studs up, 20° up past the Town Hall toward district 1 | a city at population 6 400-8 000 (districts 1-3 at 17-18 storeys, as [M11] measures at the brag), the airship moored | towers with lit Neon window strips on both sides, sky lanterns rising, the Grand Airship overhead with its gold lamp, the Lantern Dusk grade |
| 2 | **Build it** | over the shoulder of an avatar at a starred post, 3/4 behind, 8 studs back | Clear Morning (population 80-200) | a building mid-grow with the construction puff, the ★ marker over the post, the cloud sea and the far shelves behind |
| 3 | **Six cities under the aurora** | high above the ring, 300 studs up, 35° down | six cities at different heights (five test profiles, or place-only lot storeys), Aurora Crown | the ring of shelves, the aurora curtains, a sky whale crossing |
| 4 | **Close call** | 12 studs back, 30° down, the ring and the object both in frame | Trade Winds, the hazard interval at 8-10 s in the place's Config copy | a loose crate one frame before impact, the red ring on the paving, the avatar a step outside it |

## 10. Not done / open

- Nothing here was rendered. §8 is the list; the night shift runs it (`docs/complete-game-standard.md` §5).
- The gates ran on `tools/luaujs`, not the native luau CLI (gone from the machine on 2026-10-07; downloading it needs
  the owner's go). luaujs reproduced meteor-drop-tycoon's 20 recorded gate counts exactly (its 12 specs again after
  the round-2 table fix), but "compiles" in
  `check_outpostzero_compile` means luaujs's parser accepted it. Re-run `tools/gates.sh` with `LUAU=` set to the native
  CLI when it is back.
- No audio, no custom assets (v1 is code-only Parts, by design).
