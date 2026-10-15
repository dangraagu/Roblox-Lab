# Scrapline Tycoon — the yard around your line

Everything that makes the factory look alive and change as it grows: the environment bands, the rare crane drops,
☕ Break, the belt items, the moving machines, the lift-off and the recycle, with their budgets and the gates that
measure them. Modelled on `plus1-jump/EYECANDY.md` and `meteor-drop-tycoon/EYECANDY.md`. Nothing here has been seen
on a real screen: §8 lists what only Studio can settle, §9 the thumbnails to shoot there.

## 1. What there is

| piece | where | template |
|---|---|---|
| 6 environment bands (light, atmosphere, stars, post-fx, scenery, critters, weather) | `src/client/Yard.client.luau`, `src/shared/YardArt.luau`, `Config.Env` | `EnvBands.luau` from plus1-jump, **verbatim** (md5 c6fc63a1, = plus1-jump's and meteor-drop-tycoon's) |
| rare crane drops with a red ring that IS the hit zone | `Yard.client.luau`, `YardArt.luau`, `Config.Hazards` | `Hazards.luau` from meteor-drop-tycoon, **verbatim** (md5 3a13bed4): plus1-jump's template + deep-vein's marked vertical kinds |
| ☕ Break (rest) | `Yard.client.luau`, `Config.Rest` | `Rest.luau` from plus1-jump, **verbatim** (md5 19226cb6); `IdleSeconds = 0` (no idle rest, §4, REVIEW-1 B3) |
| belt items, machine animation, the lift-off, the recycle's crumble and flash | `Yard.client.luau`, `YardArt.luau` | this game |
| the server's starting light | `Fx.Presets.Junkyard` (the only edit to plus1-jump's `Fx.luau`) | equals band 1, asserted |

Why the hazard template is meteor-drop-tycoon's merge and not plus1-jump's file: the yard is flat and open, so a
sideways lane that starts inside the camera's pitch window starts underground (meteor-drop-tycoon DESIGN §6 works the
numbers); and the theme gives the drop a natural source straight overhead, the gantry crane. That merge is plus1-jump's
2026-09-30 template plus deep-vein's marked DEEP VEIN ADAPTATION (vertical kinds, `drop = "above"`, `ctx.canDodge`),
nothing else. `Trace.luau` is meteor-drop-tycoon's copy too (byte-identical, `cmp`); its spec needed four config
names renamed, marked `SCRAPLINE` in `tests/Trace.spec.luau`.

## 2. The bands, and what triggers them

**The trigger is the highest product the line has shipped this run** (`tier`, 0-6, server-measured: a product counts
once one whole item of it has been sold), never time. Every band has `fade = 0` (a new product is a discrete
achievement), and every written value glides to the new band with a **1.5 s half-life**; Lighting is written at most
10×/s and only on change. A title card greets the first entry into a band in a run; a player who joins already in a
band gets a quiet chip. After a Recycle the tier DROPS, and the sky **snaps** back to the Junkyard in one write,
behind the recycle's white flash: ClockTime only ever rises within a run, so the one backwards jump is hidden.

Minutes are `tests/Pacing.spec.luau`'s (the normal player, 20 seeds, first run):

| # | band | tier | entered (median) | lasts min / median / max | ClockTime | scenery | critters | weather | hazards |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 🏚️ Junkyard | 0-1 | 0.1 min | 2.3 / 2.4 / 2.6 | 13.0 | junk mounds, tyre stacks, car hulks | 5 crows | dust 6/s | none |
| 2 | 🔥 Foundry | 2 | 2.5 | 3.7 / 4.0 / 4.0 | 15.5 | brick chimneys (one smoking), junk mounds | 4 pigeons | embers 10/s | scrap bale |
| 3 | 🏗️ Press Works | 3 | 6.4 | 5.7 / 5.7 / 6.3 | 17.0 | girder frames, a water tower | 5 swallows | steam 5/s | scrap bale, pipe |
| 4 | ⚙️ Machine Shop | 4 | 12.2 | 8.0 / 8.7 / 9.3 | 18.3 | giant gears turning on far towers, girders | 3 drones | gold sparks 8/s | pipe, big gear |
| 5 | 🤖 Robot Works | 5 | 21.0 | 12.7 / 13.0 / 13.7 | 20.5 (1 500 stars) | neon signs, holo boards, searchlights | 4 blinking delivery drones | rain 25/s | bolt bucket, dropped parcel |
| 6 | 🚀 Launch Site | 6 | 34.0 | until the recycle (43.6 min) | 22.5 (4 000 stars) | a launch gantry, a big moon, sweeping lights | 2 satellites, far rocket trails | stardust 6/s | booster cap, big gear |

The SCRAPLINE sign's neon is the band's accent, set by the server so everyone sees how far a line has come. Your sky
follows your own tier, so other plots are seen under your sky. The board and each plot's paint show the factory
grade (Rusty, Painted, Steel, Chrome, Gold by Gold Bolts).

## 3. Hazards: the crane drops something

| kind | bands | hangs at | fall s | warning s | locks s before | ring radius | knock |
|---|---|---|---|---|---|---|---|
| scrap bale | Foundry, Press Works | 25 | 0.8 | 3.2 | 1.6 | 3.9 | 36 |
| pipe | Press Works, Machine Shop | 25 | 0.7 | 3.2 | 1.6 | 3.7 | 34 |
| big gear | Machine Shop, Launch Site | 25 | 0.9 | 3.6 | 1.8 | 4.5 | 42 |
| bolt bucket | Robot Works | 25 | 1.0 | 3.4 | 1.7 | 4.1 | 34 |
| dropped parcel | Robot Works | 25 | 0.6 | 3.2 | 1.6 | 3.7 | 44 |
| booster cap | Launch Site | 80 | 0.9 | 3.6 | 1.8 | 4.5 | 42 |

* **The red ring is the zone, exactly**: radius `hitRadius + PlayerRadius`, centred where you stood when the lane last
  aimed. Every ring can be left from its centre in ≤ 0.28 s at WalkSpeed, against ≥ 1.6 s between the lock and the
  impact (`EnvConfig.spec`). Headless: a player who stays is knocked (CONTROL), one who steps out at the lock in any
  of 8 directions is never hit (8 of 8, `check_scraplinetycoon_hazards` §6).
* **Rare**: one per 120-180 s of play on your own plot, none in the Junkyard. Measured: one every **2.42 min**
  (median) once they start, before the first Rocket (`Pacing.spec`); the walk, standing still between HUD taps, got
  one every 2.43-2.64 min over 4 walks after REVIEW-1's round 2, and 2.45-2.90 in its green mode (REVIEW-1 B3: before
  that fix the idle rest froze them, one per 31.6 min).
* **One thing at a time** (`ctx.canDodge = false` holds a due hazard): never while a machine on your line
  **sputters** (its 15 s clock sends you walking), while your first Rocket lifts off, or while the recycle sequence
  plays. **A standing jam does not hold the crane (REVIEW-2 R5)**: a jam has no clock, and holding for it froze the
  crane for good for anyone who left one jammed twin or rejoined with a saved jam (the reviewer's probe: 1 drop in 10
  min, the hold on in 3626 of 6000 frames; after the fix 3 drops, the hold on in 0). Measured
  (`check_scraplinetycoon_hazards` §7, a hazard due every 8-9 s): none during the 15 s sputter, the held one launches
  within 2 s of the sputter turning into a jam, and 7 more come in the next 60 s with the jam still standing; none
  during the lift-off or the recycle.
* Only on your own plot, only grounded, never during ☕ Break (the clock freezes; it is never reset), and never at a
  player standing ON a machine, the crate or a wall: a root more than `StandAboveFloorMax` (5) studs over the highest
  low surface under it gets no aim, so nothing launches or tracks there (REVIEW-1 B5: the ring would be drawn on the
  floor below, mostly hidden inside the machine).
* The telegraph: the crane's trolley rides over you, a light pillar comes down to the ring (yellow while it tracks
  you, red when it locks), and the banner says "⚠️ CRANE DROP: … Step out of the red ring", then "MOVE!". The zone is
  drawn up to the highest low surface it overlaps (arrival pad, belt, consoles, dock, launch pad: `PlotGeom.zoneFloor`,
  meteor-drop-tycoon's REVIEW-1 lesson); the hazards check measures those surfaces on the built parts.
* A hit costs a stumble (PlatformStand 0.9 s, a shove of 34-44 studs/s, lift 8); the ground is continuous.

## 4. ☕ Break: what "pause" means here

The ☕ Break button (column slot 2) sits you down and the camera drifts slowly along your line, chute to dock and back
(14 s each way, written by the yard script's frame only while the break lasts: REVIEW-1 B2 replaced an endless tween
that kept writing the camera after the break). Press again (▶ Carry on), or move, to carry on.

**No idle rest (ADAPTATION, REVIEW-1 B3).** The template rests a player who stands still for 20 s. +1 Jump is played
moving, so standing still there means away; a tycoon is played standing still and tapping the HUD, and the idle rest
froze the crane for exactly those players (the walk: one drop per 31.6 min, and the band chip read "💤 Resting" most of
the game). `Config.Rest.IdleSeconds = 0` (the template's own switch); only ☕ Break rests. An AFK player gets the crane
like anyone else: a stumble, nothing lost.

Why it is never an exploit: rest pauses only hazards (their clock freezes, never resets; plus1-jump measured 142 /
142 / 142 hazards over 6 h for never-rests / toggles / rests 40 s of every 150). The line earns exactly the same
resting or not (income is the line's flow), and the **jam clock does not freeze**: a line left on break winds down
like one left alone (`Pacing.spec`: an untended 35-minute line earns ×0.73-0.82 of a tended one after 5 min,
×0.12-0.52 after 10 and ×0.000 after 30). The chip on break says so ("Your line keeps running, and machines can still
jam") and so does the store text (REVIEW-1 B6). A rest cannot start with a hazard inbound (it queues). Nothing races a
clock.

## 5. Client vs server

Server (everyone sees it): the plots, machines, level plates, sparks and smoke on a machine in trouble, the ⚠ JAMMED
sign, the SCRAPLINE sign's band accent, the factory grade paint, the next station's glowing console. Client only
(never replicated, never a remote): lighting, scenery, critters, weather, belt items, machine animation, the hazard,
☕ Break, the lift-off rocket (every client animates it from the server's `Announce`), the recycle's flash and crumble,
every ProximityPrompt (created by the owner's client on its own plot). `check_scraplinetycoon_yard` proves the client
fires no remote and changes no server-built part in 300 frames.

## 6. Budgets (capped in code, measured every frame)

| budget | cap | measured worst |
|---|---|---|
| local parts | 200 | 62 (yard check, every band and seam, 14 belt items); 93 with hazards in the air |
| belt items, own line / each other line | 33 / 8 | 14 at a level-1 line (2.5 items/s × 13.2 s = 33 at full speed, capped in `YardArt:updateBelts`) |
| emitters / weather emitters / summed rate | 4 / 2 / 60 per s | 3 / 2 / 25 per s |
| beams / trails / lights | 8 / 8 / 3 | 5 / 2 / 1 |
| hazards at once | 1 | 1 |
| server parts | 640 | 266 idle, 422 with six players and four complete lines (`check_scraplinetycoon`; +4 since REVIEW-2 R7: the invisible walls on the world's edge); six complete lines would be 482 by the same count |
| server lights | 12 | 12 idle (one per chute, one on each plot's next console), 8 when four lines are complete |

## 7. Gates

`check_scraplinetycoon_yard` (bands entered by shipping, every seam, the glide, the lift-off, the recycle snap, ☕
Break, belt items, budgets every frame, the client writes nothing), `check_scraplinetycoon_hazards` (when, where, the
ring, 8 directions, rest, the holds), `check_scraplinetycoon_hud` (hudcheck, 30 viewports in three modes, overlap =
true), `tests/EnvConfig.spec.luau` (the bands' shape and colours, the hazard rules), plus the verbatim template specs.
Counts are in `CLAUDE.md`.

## 8. Needs Studio (only real rendering, a real device or a live server can judge)

1. **Every band's look**: exposure, ambient and bloom per band; whether the line and the belt items read at night
   (Robot Works, Launch Site); the dusty Junkyard haze (Atmosphere 0.35) not washing out the line.
2. **Stars at ClockTime 20.5** (Robot Works): do 1 500 stars show, or only later?
3. **Atmosphere vs fog**: Roblox ignores fog while an Atmosphere exists; the Launch Site's density 0.08.
4. **Distant scenery on a phone**: chimneys, girders, far gears (210-320 studs out), the gantry and the moon may be
   culled at low graphics quality. If so: closer and smaller.
5. **Beams**: the Cutter's laser, the searchlights and the sweep lights almost certainly need hand tuning.
6. **Belt items**: does a client-drawn stream (one Part per item, moved every frame at 10 studs/s) look continuous,
   and does the share of items that ride past an overloaded station read as "this station is too slow"?
7. **Machine silhouettes**: three Parts per machine (body, a Neon working part, a cap). Can a player tell the six
   apart at 20-45 studs on a phone, and the twin from the first machine? The belt runs through the machine bodies.
8. **The sputter**: 15 s with amber sparks, the HUD's amber alert line and an always-on-top "⚠ FIX" pointer: enough
   to notice while the line panel is open?
9. **Client-created ProximityPrompts** (station consoles, Fix, the board): do they show, hold and trigger on touch
   exactly as server ones do, and does the 0.5 s Fix hold feel right? Since REVIEW-1 B1 Fix is on **F / ButtonY** with
   `Exclusivity = AlwaysShow`, and a station's console prompt is disabled while one of its machines is in trouble:
   check on a phone that the Fix bubble shows and is tappable beside the console and the board (Roblox does not
   document how OnePerButton treats touch; `check_scraplinetycoon_prompts` assumes the worst case), and what F does
   with two adjacent broken machines in range (both are Fix prompts, so either is a useful answer).
10. **The knock**: PlatformStand plus AssemblyLinearVelocity on flat ground (deep-vein, +1 Jump and meteor-drop-tycoon
    share this open item).
11. **The crane telegraph**: the trolley over you plus the ring, in the bright Junkyard as well as at night.
12. **☕ Break's sit and camera drift**: `Humanoid.Sit` with no seat (+1 Jump's item 11), a Scriptable camera moved
    every frame chute to dock and back (14 s each way); release on the first move, and the default camera takes over
    with no jump.
13. **Top-centre HUD on a notched phone**: safe area, emoji in TextScaled labels, the band chip's length ("🤖 Robot
    Works · next: 🚀 ship a Rocket").
14. **The paged line panel**: on a 640 × 300 phone it shows ONE station row per page (tall rows, the column's ▼ turns
    the page); on 800 × 360 three. The panel opens on the ★'s page. Is that comfortable, or should the panel get
    wider than `Responsive.sideWidth` allows?
15. **The board's SurfaceGui** in PlayerGui with Adornee: only the owner sees their rows; it sits over the public title
    plate (ZOffset 1). **REVIEW-2 R1** found it probably unreadable (rows 0.229 studs, 3.3 px on a phone at the default
    camera) and it is now 10 × 10 on the dock side of the arrival, 11 rows of 0.686 studs: by geometry (a pinhole
    camera, FOV 70, `check_scraplinetycoon_boardview`) a row is 10.1 px on an 800 × 360 phone read from 5 studs at the
    default camera (the HUD's own hint text is 9.6), 15.4 px in first person from the pad, 7.8 px with the default
    camera from the pad. In Studio: is it readable on a real phone, does the default camera really sit 12.5 studs back,
    and do long names (TextScaled shrinks them to the row's width) stay legible? The viewer's own row is drawn under
    the top 10 when it is not in it (REVIEW-2 R2).
16. **Frame time** on a mid/low phone with six full lines (33 + 5 × 8 belt items) and the Robot Works rain.
17. **The lift-off** (a 5-part rocket with a trail and smoke rising 320 studs over 6 s, the card, the shake, the
    server toast): celebratory, not annoying; seen from other plots.
18. **The recycle**: the white flash hiding the sky's jump back to midday, the 12 dust puffs where the machines
    stood, the repaint. (The DESIGN's crane sweep is not animated: see §10.)
19. **Game Settings**: `Players.MaxPlayers = 6`; `SpawnLocation.Duration = 0` really removes the force field.
    `Workspace.StreamingEnabled = false` is pinned in `default.project.json` (`tests/project_spec.py`; robloxemu does
    not model streaming): confirm the published place really has it off.
20. **Other players see a knock with nothing hitting** (client-only hazards): does it look like a glitch?
21. **The SCRAPLINE sign's text**: settled headless in REVIEW-1 B4. It was on the Back face, pressed flat against the
    factory wall (gap 0.000 studs); it is on the Front face now, whose normal points into the yard on every plot
    (`check_scraplinetycoon` §1: dot = 1.000). The level plates were measured the same way and face into the U
    (dot 0.58-0.99 toward the plot centre). In Studio, only confirm the text reads from the yard.
22. **Materials**: CorrugatedPlate (Rusty), Foil (Gold), ForceField (the holo boards), Cardboard (the parcel).
23. **Live server only**: the friends board against real GetFriendsAsync pages and DataStore throttling;
    GetSortedAsync caching across servers; a recycle against a real UpdateAsync failure and the per-key write rate
    (a recycle write can follow a flush write by under 6 s).
24. **Optional, if assets are chosen**: a shredder crunch, a furnace roar, a sputter alarm, a lift-off rumble
    (library audio ids only).
25. **The big board's place (REVIEW-2 R1)**: 10 × 10 studs, top 10.7 studs up, in the mouth of the U on the dock side.
    From the spawn camera it hides part of the U's right half (and may hide the right end of the SCRAPLINE sign); it
    hides neither the chute nor the Shredder. Does it look like a scoreboard or like a wall? If it is too much: a lower,
    wider board, or tilt it back so the camera sees it more squarely.
26. **The world's edge (REVIEW-2 R7)**: four fully transparent, collidable walls, 60 tall, on the plate's edges. Confirm
    the camera ignores them (Roblox's popper skips nearly transparent parts) and that bumping into nothing at the edge
    reads as the edge of the world, not as a bug. Optional: a fence or junk wall there for the eye.
27. **The panel's colours (REVIEW-2 R3)**: gold (the ★), green (worth buying), muted blue-grey (affordable, not worth it
    now), grey (not affordable). Are green and the muted blue-grey told apart on a phone in sunlight, and by a
    colour-blind player? If not, a text cue ("✓") on green.
28. **Crane drops while you walk to a jam (REVIEW-2 R5)**: a jam no longer holds the crane, so a player crossing the
    yard to fix one can get a drop. Fine (a jam has no clock), but watch whether it feels unfair.
29. **Live server only (REVIEW-2 X2)**: whether a client can replicate a root CFrame that is not a finite number at all
    (the server now ignores such a claim either way), and fling-griefing between players (player collisions are on: a
    flinger could knock an honest player away from a sputtering machine).

## 9. Thumbnail shot list (for the night Studio session)

1920 × 1080. Stage each through a COPY of Config in the place only (never `src/`), the way +1 Jump's shot list does:
seed a profile with the line and tier the shot needs, or set `Config.Hazards.IntervalMin/Max` to 8/9 for shot 4.

1. **"Lift-off"** (Launch Site, ClockTime 22.5): camera low at the front-right corner of a plot (plot-local (30, -36),
   2 studs up), looking at the launch pad (26, -28) and up; the rocket a few studs above the pad on its flame and
   smoke, the avatar beside the dock looking up, the whole U line lit under the stars, the gantry behind.
2. **"The line"** (Robot Works, 20.5): high three-quarter view (plot-local (-30, 45, -40) looking at (0, 0, 5)): a
   full U with six twinned stations, items of every product on the belt, neon signs, the crane bridge, rain streaks.
3. **"Jam!"** (Machine Shop, 18.3): close on a smoking Assembler with its ⚠ JAMMED sign (plot-local (14, -2)), the
   avatar running to it from the middle of the U, gears passing the jammed machine on the belt.
4. **"Close call"** (Foundry, 15.5): a scrap bale one frame before impact under the crane's trolley, the red ring on
   the floor, the avatar one step outside it; camera 12 studs back, 30° down.
5. **"Six factories"** (Launch Site, for the camera player's night sky): a wide shot from 120 studs above the Scrap
   Market, six plots at different stages: lines of different lengths (stage the profiles from a Shredder alone to all
   six stations twinned), the SCRAPLINE signs in different band accents, the grade paint from Rusty to one Gold. **The
   sky is the camera player's own band** (REVIEW-2 R8: an earlier version asked for "six plots in different bands",
   which the game cannot show, since each client lights the world by its own tier).

## 10. Not done / open

* The recycle's **crane sweep** (DESIGN 9.2) is not animated; the sequence is the flash, a shake, 12 dust puffs and
  the repaint.
* **"+$" pops at the dock** (DESIGN 16) are not drawn.
* The line panel's header shows the line's income, not the per-product flow summary DESIGN 16 describes (the rows
  show each station's rate and load).
* No audio (needs asset ids: §8 item 24).
* The far rocket trails rise every few seconds rather than "every 20 s" (one `farRocket` critter respawns as soon as
  it leaves the sky).
