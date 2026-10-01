# Meteor Drop Tycoon — the sky over your plot

The owner's standard (`docs/complete-game-standard.md` §2) asks for eye candy from the first build: at least five
environment bands that follow the game's own logic, rare telegraphed hazards whose red ring is exactly the hit
zone, a rest that is never an exploit, measured budgets, and a brag moment in about 30-45 minutes. This file is
how Meteor Drop Tycoon does each, what was measured, and what only Studio can settle.

Every number below was printed by a gate in this repo on 2026-10-01 (named next to it) or is copied from
`DESIGN.md` with its tag. Nothing here has been seen rendered: **the game has never been opened in Studio.**

## 1. What there is

| piece | where | what it does |
|---|---|---|
| 6 bands | `Config.Env.Bands`, `src/client/Sky.client.luau`, `src/shared/SkyArt.luau` | light, colour, scenery, critters and weather per band, blended by the owner's Beacon level |
| streaks | `Sky.client.luau` | a falling streak for every meteor announced on your OWN plot (the server shows only the landing glow) |
| hazards | `src/shared/Hazards.luau` (template + deep-vein's vertical kinds) | 5 kinds of space junk, one per 120-180 s of play on your own plot, from band 2 on |
| Stargaze | `src/shared/Rest.luau` (plus1-jump, verbatim) | sit down, the camera tilts up to your band's sky; hazards pause |
| brag moment | `Main.server.luau` | the guaranteed Falling Star at Beacon 22, then the gold crown on your Beacon |
| budgets | `Config.Budget`, capped in `SkyArt` / `EnvBands.capRates` | measured every frame headless |

## 2. The bands, and what triggers them

**Trigger: the owner's Beacon level, never time.** The Beacon is how far into space your plot listens, so the sky
over the plot is the region you have tuned into. The level reaches the client in the owner's own `State` payload
and in `leaderstats.Beacon`, and only the server raises it (a validated purchase). The integer level names the band
(chip, title card, which hazards fly, the meteor mix all use the same `EnvBands.indexAt`), each band fades in over
its `fade` levels before its `from`, and every written value glides with a **1.5 s half-life**
(`Config.Env.HalfLife`; +1 Jump used 0.6 s for teleports, a purchase is a step the player should watch happen).

Minutes are the pacing model's normal follower, **measured from the rules that ship** (`tests/Pacing.spec.luau`,
which runs `tests/PlotModel.luau` against the game's own `Economy` and `Meteors`; median of 20 seeds; re-measured
after REVIEW-1's star change).

| # | band | from (fade) | entered, normal | light | scenery | critters | weather | hazards | Beacon beam |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🌅 Dusk Meadow | 0 | 0 min | golden hour, ClockTime 17.8 | rolling hills ring, birches, low sun | swallows (flock of 5), 3 butterflies | fluff 5/s | none | amber |
| 2 | 🌆 Twilight | 5 (2) | 4.3 min | blue hour 19.0, 800 stars | hills, crescent moon, lighthouse sweep | 4 bats, 8 fireflies | mist 4/s | dead satellite | lavender |
| 3 | 🌌 Aurora | 12 (3) | 15.4 min | night 22.0, 2 500 stars, teal grade | aurora (3 Beams), snowy peaks, moon | 2 owls, 6 wisps | snow 20/s | satellite, ice chunk | teal |
| 4 | 🌠 **Starfall** | **22** (4) | **35.4 min** | 23.0, 3 500 stars, gold-violet | the great comet, peaks | 3 shooting stars | embers 12/s | bolide | gold, + the **Falling Star** |
| 5 | 🪐 Nebula | 32 (4) | 72.6 min | 23.5, 4 500 stars | nebula clouds (6 spheres), ringed planet | 3 star jellies | stardust 6/s | plasma blob, bolide | violet |
| 6 | ✨ Galactic Core | 44 (6) | 137.6 min | 23.9, 5 000 stars, no haze | galaxy core + 4 arm Beams, nebula | 2 comets | gold dust 8/s | neutron shard, bolide | white-gold |

- **The brag moment**: catching the Falling Star, **35.5 min** median for the normal follower (p10 34.2, p90 38.2),
  slow 37.1, fast 35.0 (`Pacing.spec`, after REVIEW-1; it was 35.6 / 36.9 / 35.0). The long-term goal, the Galactic
  Core, comes at 137.6 min = 3.87x later (was 128.6). The built-world walk caught it at 35.9 min (median of 40).
- **The shortest band** of any normal seed is Dusk, **3.7 min** (`Pacing.spec`; the standard's floor is 2).
- `ClockTime` only rises (17.8 → 23.9) and never wraps past midnight (a linear blend of 23.5 into 0.0 would sweep
  the sky backwards through a whole day); `EnvConfig.spec` asserts it.
- The server's starting light is `Fx.Presets.Dusk`, the one edit to the copied `Fx.luau`; it equals band 1 on every
  field band 1 defines (`check_meteordroptycoon_sky`, asserted field by field).
- **Everything but the Beacon beam is client-only**: built locally, non-collidable, non-queryable, non-touchable, and
  it replicates nothing. Your sky follows *your* Beacon, so a neighbour's plot is seen under your sky. The one
  server-side change per band is the colour of your Beacon's beam, which everyone sees (the band is public anyway).
- A title card plays when a purchase takes you into a band you have not seen this session. A player who joins
  already in a band gets the quiet chip ("🌌 Aurora · 🌠 Starfall in 7 levels"), no card.

Measured through the real remote (`check_meteordroptycoon_sky`): at Beacon 4 the sky settles half-way into Twilight
(ClockTime 18.400, smoothstep 0.5); one purchase to Beacon 5 moves ClockTime **+0.028 in its first 0.35 s** and
**+0.600 after 8 s**: it glides, then arrives. Every band's pieces, critters and weather are up at its middle, the
previous band's own pieces are gone, and ClockTime reaches the band's value within 0.03.

## 3. Hazards: rare space junk

The template is plus1-jump's `Hazards.luau` as of 2026-09-30 (with its 2026-09-27 `threatLive` rule) plus
deep-vein's marked **DEEP VEIN ADAPTATION** section (vertical kinds, `ctx.canDodge`, a fallback knock direction),
merged with nothing else. **Why the adaptation:** on a flat plot plus1's sideways lanes start inside the camera's
pitch window, which on a third-person camera looking down about 25 degrees puts a lane's start 8.9 studs *below*
the player: underground (DESIGN.md §6). Every kind here falls from above; its telegraph is the ring at your feet,
on screen wherever the camera looks. The merged spec (`tests/Hazards.spec.luau`, 153 passed) is plus1's spec plus
deep-vein's vertical section plus a new check that the vertical kinds keep their ring up exactly while they can hit.

| kind | bands | height | fall s | warning s | locks before | hit radius (ring radius) | knock studs/s |
|---|---|---|---|---|---|---|---|
| dead satellite | Twilight, Aurora | 60 | 0.8 | 3.2 | 1.6 | 2.4 (3.9) | 36 |
| ice chunk | Aurora | 60 | 0.7 | 3.2 | 1.6 | 2.2 (3.7) | 34 |
| bolide | Starfall, Nebula, Core | 80 | 0.9 | 3.6 | 1.8 | 3.0 (4.5) | 42 |
| plasma blob | Nebula | 60 | 1.0 | 3.4 | 1.7 | 2.6 (4.1) | 34 |
| neutron shard | Core | 70 | 0.6 | 3.2 | 1.6 | 2.2 (3.7) | 44 |

- **The ring is exactly the hit zone** (`Hazards.zone`: `hitRadius + PlayerRadius`, centred where you stood when the
  lane last aimed). It is red from the first frame and turns solid at the lock, when the light pillar turns red too.
  A hit needs you inside the ring AND the object passing within reach, so **stepping out of the ring in any
  direction always dodges.** Headless (`check_meteordroptycoon_hazards`): the drawn ring's radius equals the kind's
  zone to 1e-6, it is centred on the player, it is the one red thing in the game; a player who stays in it is
  knocked (the control), and stepping out at WalkSpeed from the moment of the lock dodged in **8 of 8 directions**.
- **Drawn on top of what you stand on** (REVIEW-1). The zone was a flat disc at the plot's ground, so on the 1-stud
  arrival pad 57-81% of it lay under the pad and a player standing there saw four red slivers. It is now a
  translucent column from the ground up to the highest low surface it overlaps (`PlotGeom.zoneFloor`: the pad, the
  Smelter's base, the Beacon's base; never the Smelter's body or the board) plus 0.2 studs. The hit rule is
  horizontal, so the column is the zone exactly, at every height. Headless: a hazard that locks onto a player on the
  pad draws y 0.22 to 1.22 over a pad top of 1.00, radius still the kind's zone; the floors it assumes are measured
  on the built parts (`check_meteordroptycoon_hazards` §6b).
- **Rare:** one hazard per 120-180 s of non-rest time on your own plot; 13 in a normal player's first 36 minutes
  (DESIGN [M9]); never more than one at a time (measured: at most 1 model at once).
- **When they may launch** (all asserted through the client in `check_meteordroptycoon_hazards`): not in the first
  band (40 s at an 8-9 s test interval: 0 launched); only on your own plot (off it: 0 in 30 s, and the clock does not
  run); only when grounded (in the air: 0 in 25 s, then one as soon as they land, asserted within 2 s); never while resting (0 in 40 s,
  clock frozen, resumes from the same value); never between the Falling Star's grant and its catch (0 in 40 s, then
  hazards resume).
- **A hit costs about 1.9 s and nothing else:** a 34-44 studs/s shove with an 8 studs/s lift for 0.9 s. The ground is
  one continuous plate, so nothing can knock you off anything, and the lift can never carry you onto anything.
- **Client-only, and why** (+1 Jump's split): the schedule, telegraph, hit test and knock run on the owner's client.
  A hazard harms only the local player, whose physics that client already owns, and it grants and removes nothing,
  so the server needs to know nothing. An exploiter who deletes hazards avoids a 1.9 s stumble and gains nothing.

## 4. Stargaze: what "pause" means here

plus1-jump's `Rest.luau` and its spec, **verbatim** (55 passed). Deep Vein's additions (`SettleSeconds`,
`MinAwakeSeconds`) are not copied: they exist because a miner earns by clicking while standing still, and here every
hand pickup needs walking, and walking wakes you.

- **☕ Stargaze** (right edge, under ⬆ Upgrades): you sit, the camera takes over and tilts slowly up and out to your
  band's sky; the chip says "☕ Stargazing: the sky leaves you alone. Collector awake 8:12". Move, or press
  "▶ Carry on", to get up; the camera is handed back. Standing still 20 s also rests you (idle rest, no camera
  change), and pressing Stargaze during an idle rest turns it into a stargaze instead of ending it (found by the sky
  check: the button used to toggle the idle rest off).
- **Why it is never an exploit:** it pauses only hazards, whose clock *freezes* and is never reset; you cannot pick
  anything up while resting (pickups need walking); the Collector's 10-minute timer does **not** freeze during rest,
  so resting never extends idle income; a rest cannot start with a hazard inbound (the template's queue,
  `PendingSeconds` 7 > the longest flight 4.6 s + 2); there is no round and no timer to race.

## 5. Client vs server

| server (everyone sees) | client only (you see) |
|---|---|
| plots, Smelter, hopper gauge, dish, Beacon tower and beam colour, crown, meteors (glow → rock), the Falling Star, the Star Chart's title plate, owner signs | the lighting blend, all band scenery, critters, weather, meteor streaks, zips and puffs, hazards and their telegraph, Stargaze, the ⭐ over your own plot, the Star Chart's rows (a SurfaceGui in your own PlayerGui) |

Sky.client **fires no remote and writes nothing the server built**: `check_meteordroptycoon_sky` counts every
client → server event in the run (only the check's own purchases), and runs 300 client frames with the server parked
and finds 0 changed server parts. Every client part lives in `workspace.MeteorLocalSky`, with no attributes.

## 6. Budgets (capped in code, measured every frame)

`Config.Budget`: 200 local parts, 4 emitters, 60 particles/s, 2 weather emitters, 8 beams, 8 trails, 3 lights, 1 hazard.

Worst frame over every band's middle and every purchase in between (`check_meteordroptycoon_sky`): **52 parts,
2 emitters, 4 beams, 3 trails, 1 light, 2 weather emitters at 19.8/s**. With hazards in the air
(`check_meteordroptycoon_hazards`): 64 parts, 1 light, 1 hazard. Meteor streaks: at most 2 with trails at once.

Server (`check_meteordroptycoon`): 151 parts idle (8 plots of 18 + the observatory's 6 + the plate), 185-195 in a
busy 3-player world; 16 lights (one on each dish rim, one on each Beacon); cap 450 and 16. A plot never holds more
than 20 landed meteors (measured: the fullest plot held 20).

## 7. Gates

See `CLAUDE.md` for the commands, the exact counts of the last run (20 of 20 gates green) and the first build's
mutation sweep (25 of 26 mutants killed, the survivor an equivalent mutant; both controls survived), and
`REVIEW-1.md` for the review pass's own sweep.

## 8. Needs Studio (only real rendering, a real device or a live server can judge)

1. **Every band's look:** exposure, ambient and bloom per band; whether the plot and Neon meteors read at night; the
   gold Starfall grade; the teal aurora against the snow.
2. **Stars at ClockTime 19.0** (Twilight): do 800 stars show at blue hour, or only after about 20?
3. **Atmosphere vs fog:** Roblox ignores fog while an Atmosphere exists; check the Core at density 0.
4. **Distant pieces on a phone:** the sun, moon, comet, nebula spheres, ringed planet and galaxy (900-2 400 studs
   out) may be culled at low graphics quality. If so: closer and smaller.
5. **Beams:** the aurora curtains, the galaxy arms and the lighthouse sweep almost certainly need hand tuning.
6. **The falling streak** against the server's reveal of the landed meteor under real replication delay (100-200 ms):
   does a rock ever pop in before its streak arrives?
7. **The landing glow** readable 1.5 s early on a phone at 30 studs; the five rarity colours distinguishable
   (colour-blind check on the green / blue / violet trio).
8. **Walk-over pickup at radius 5** with a thumbstick: generous or sloppy?
9. **The knock:** does PlatformStand plus AssemblyLinearVelocity push a humanoid on flat ground, and release cleanly?
10. **The hazard telegraph from above:** is the ring enough when the object hangs out of view; does the pillar read
    in Twilight?
11. **Stargaze:** Humanoid.Sit with no seat, from the client; the Scriptable-camera tilt and its release on the first
    move (plus1-jump measured a 0.3 s drop on a seatless sit; the 1.0 s settle is copied).
12. **The top-centre HUD on a notched phone:** safe area, emoji in TextScaled labels, the band chip's length.
13. **The Star Chart:** a SurfaceGui parented under a Folder in PlayerGui with Adornee set is expected to render
    (standard Roblox), legible from 14 studs, and seen only by the owner. Also the title plate behind it (ZOffset 1).
14. **Frame time** on a mid/low phone with 8 busy plots at the floor rate, 6.7 meteors/s server-wide.
15. **Game Settings:** Players.MaxPlayers = 8 (the server kicks a ninth with a reason, `check_meteordroptycoon` §11);
    SpawnLocation.Duration = 0 really removes the force field.
16. **Other players see a knock with nothing hitting** (client-only hazards): does it look like a glitch?
17. **Live server only:** the friends board against real GetFriendsAsync pages and DataStore throttling;
    GetSortedAsync caching across servers; a real UpdateAsync failure during the Falling Star's grant.
18. **The Falling Star fanfare** (white flash, FOV punch, shake, the server-wide toast): celebratory, not annoying.
19. **The Falling Star lands 4 studs in front of the arrival pad, inside the 5-stud pickup radius:** a player who is
    standing on the pad when it lands catches it without a step (seen headless in `check_meteordroptycoon_save`, which
    now moves the player away first). Decide in Studio whether the showcase spot should move further out.
20. Optional, if assets are chosen: an impact thud, a Smelter hum, a Falling Star chime (library audio ids only).
21. The thumbnails (§9) and clips (`MARKETING.md`), filmed in the night session.
22. **The hazard zone as a column (REVIEW-1):** on the arrival pad it is a 1-stud translucent red column (0.5, solid
    0.15 at the lock) from the ground to just above the pad; on the Beacon's base, 2 studs. Does it read as "the ring
    is here" from the default camera, or do its walls look like a red block? If it looks wrong, keep the column but
    lower the walls' opacity (a second, thinner part on top), never move the circle.
23. **Live server only (REVIEW-1):** the join's lock wait (re-read every 5 s for up to 15 s, "⏳ Your save is open on
    another server") and the 15 s re-check against real UpdateAsync latency and the per-key write limit (Roblox
    throttles a key written more often than about every 6 s: the Falling Star's catch write lands about 4 s after
    its grant write when the player is on the pad; it now runs in its own thread, so it can wait without stalling
    anyone).

## 9. Thumbnail shot list (for the night Studio session)

Every shot is **1920 x 1080**; keep the subject inside the middle 1280 px (a phone carousel's crop).

**Staging, without touching real saves** (this recipe has not been tried in Studio; verify step 1 first):
1. `rojo build -o MeteorDrop-shots.rbxlx` in this directory and open that file (`*.rbxlx` is git-ignored).
2. *Game Settings → Security → Enable Studio Access to API Services* **OFF**: the server then says the session is not
   saved, and nothing reaches the live DataStore or the Star Chart.
3. Progress for a picture is staged by editing `ReplicatedStorage.Config` **in this place only, never in `src/`**:
   `Beacon.Price0 = 0` and `Beacon.PriceGrowth = 1` make every Beacon level free, so the Upgrades panel's BUY walks the
   sky to any band in a few taps; `Hazards.IntervalMin/Max = 100000/100001` keeps junk out of frame (shot 4 uses
   8/10 instead) and `Rest.IdleSeconds = 0` keeps idle rest from freezing the hazard clock. Thumbnails may stage
   progress this way; the clips in `MARKETING.md` may not.
4. Clean frames (command bar, Client): hide `MeteorHud` and `MeteorSky` and the CoreGui.

| # | shot | band / setup | camera | in frame |
|---|---|---|---|---|
| 1 | **"The sky is falling on your plot"** | Starfall (Beacon 24) | low behind the avatar on its plot, looking up 35° toward the comet | the great comet and shooting stars, three meteors mid-streak toward three glowing landing spots, the Smelter's sparks |
| 2 | **"The Falling Star"** | buy Beacon 21 → 22; shoot during the 4 s descent | 3/4 view from the plot's side, the arrival pad in the lower third | the gold beam, the star 20 studs above the showcase spot, the avatar reaching toward it, the Beacon's gold beam behind |
| 3 | **"Nebula night"** | Nebula (Beacon 36) on 4 plots (4 test clients, each at a different Beacon) | high wide shot from above the observatory, 60° down | four plots under the nebula clouds and the ringed planet, each Beacon beam a different colour, the observatory in the middle |
| 4 | **"Close call"** | Starfall, hazards at 8-10 s | low, 8 studs from the avatar, the ring filling the lower half | a bolide one frame before impact, the solid red ring on the grass, the avatar one step outside it |

## 10. Not done / open

- Never rendered, never played by a person, never opened in Studio (above).
- The pacing profiles are assumptions (`Config.Pacing.Profiles`); replace `normal` with telemetry first.
- No audio (cut in v1; §8 item 20).
- The Collector dish is a flat glowing ring; a real dish model needs a mesh (cut: code-only Parts in v1).
