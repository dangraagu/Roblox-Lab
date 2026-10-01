# FACILITY: Endless Nightmare — clip list

Eight short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is **vertical
1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer, HUD and
lighting; never the emulator). `film_game.py` records the vertical strip of the viewport and encodes it at 1080x1920;
each clip's staging goes into `marketing/clips/manifest.json`.

**Nothing here has been filmed.** The game has never been opened in Studio (CLAUDE.md), so every clip is **new**:
`tools/` belongs to the tools owner, and each needs a `FACILITY` scenario added to `tools/film_game.py`. Filming is the
night shift's job (Studio 00:00-06:00, standard §5), after the needs-Studio list (EYECANDY.md §8) has been walked. A
clip of a look that Studio shows to be wrong is not filmed until it is fixed.

## Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera, and use what the game offers
every player. It never edits the game's numbers and never fakes progress the HUD then shows. For FACILITY that means:

- **The place.** Build it as EYECANDY.md §9 steps 1-2 say: `rojo build default.project.json -o Facility-shots.rbxlx`
  (git-ignored), open it from disk, check the break room's hint says saving is off. Never publish that file.
- **A first run is held.** With saving off every Play is a fresh profile (runs 0), so sublevel 1 stays lit until the
  first fuse is picked up (DESIGN.md: the first run's dark waits for the first fuse). That is real game behaviour and
  what makes staging possible: walk to where the shot is, then pick up a fuse to start the dark.
- **First person on a floor.** Floors are `LockFirstPerson`. The vertical strip is the centre of the view, which is
  where the flashlight points. For a side-on shot, use a scripted camera and hide the HUD
  (`PlayerGui.FacilityHud.Enabled = false`) so no HUD number is filmed from a pose the player cannot take.
- **Deep bands are played, not configured, when the HUD is in frame.** The ride's banner says `SUBLEVEL n — BAND`. A
  clip that shows it must show a real sublevel reached by playing (a medium-pace bot first reached sublevel 5 a median
  of 4.3 minutes into a run, EYECANDY.md §2). The
  `SHOT_BAND` snippet of EYECANDY.md §9 (a band put on sublevel 1, in the shots place's Config only) is allowed ONLY
  with the HUD hidden, and the manifest's staging list must say "band shown on sublevel 1 for filming".
- **Hazards** come every 90-140 s of lit time (the owner's decision, EYECANDY.md §10). For clip 5 the shots place may
  set `Config.Hazards.IntervalMin = 8` and `IntervalMax = 10`, as EYECANDY.md §9 shot 4 does. **This shortens the wait
  for filming only; the manifest must say so**, and no caption may say how often hazards come.
- **The board.** Never film the Friends view with a real account's friends list visible (it shows their Roblox
  usernames). Use a Studio test player with no friends: the board then says what an empty friends board says.

Where things are (CLAUDE.md, Config.Hub): the break room is 60 x 40 studs at the origin, the spawn at (-24, 0.5, 0),
the service elevator's car at x = -8 (16 studs ahead of the spawn), the TOP DIVERS board on the north wall at
(-19, 5.5, 19.8) facing the room, the DEPTH RECORD board on the south wall at (-19, 5.5, -19.85), the benches at x = 6
and 18 on the south wall. The first player's zone is `workspace.Facility.Zone_1`, 400 studs out along +X; rooms are
28-stud cells, the entry room is where the ride car's doors open.

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `going_down` | 10-12 s | spawn in the warm break room, walk into the service elevator, "Going down…", the ride, the doors open on a cold entry room: THE POWER IS FAILING — STAY IN THE LIGHT |
| 2 | `dark_front` | 10-13 s | from a lit room, the next room's lights flicker for two seconds and die; the flashlight comes on and points into the black doorway |
| 3 | `fuse_in_the_dark` | 8-11 s | a dark room swept by the flashlight cone until a fuse's amber glow shows; the player walks to it and the HUD's FUSES count goes up |
| 4 | `lift_powers` | 11-14 s | the last fuse carried into the freight elevator: ELEVATOR POWERED, EXTRACT or DESCEND; DESCEND pressed, the ride down to SUBLEVEL 2 |
| 5 | `hazard_dodge` | 8-12 s | a lit lab: CHEMICAL LEAK — STEP OUT OF THE RING, a step sideways, YOU ARE CLEAR, the violet splash lands where the player stood |
| 6 | `band_arrival` | 9-12 s | the ride down into a new band: the banner SUBLEVEL 5 — SERVER VAULT, the grade gliding from cyan to cold blue, a rack pair blinking in the entry room |
| 7 | `dark_takes_you` | 8-10 s | light off in a dark room: the vignette closes in over four seconds, THE DARK TOOK YOU — kept 2 of 10 Essence |
| 8 | `board_toggle` | 7-9 s | back in the break room: the TOP DIVERS board, E pressed, PUBLIC turns to FRIENDS |

### Staging, clip by clip

1. **`going_down`.** Fresh Play in the shots place. HUD on. Camera: the default third-person camera behind the
   character (the break room is not first person), then the game's own switch to first person for the ride. Walk
   straight along +X from the spawn into the car (16 studs; the amber guide strip on the floor leads there). Keep the
   take from the first step to 2 s after the ride ends: the banner THE POWER IS FAILING — STAY IN THE LIGHT and the hint
   "Find 3 fuses" are the hook. No fuse is picked up.
2. **`dark_front`.** Same place, a first run. Open doors until three rooms are built in a row (walk up to a door and
   it opens). Stand in the middle room, facing the first room's doorway. Pick up a fuse first if the entry has one;
   otherwise walk to the nearest fuse and back: the dark starts from the entry room one ring at a time, and each room
   flickers for 2 s before it dies. Light OFF until the flicker starts, then F (LIGHT) as it dies. HUD on (the hint
   "Your room is going dark" only shows if it is YOUR room: stand in the next one out). Record 15 s, cut to the flicker.
3. **`fuse_in_the_dark`.** Continue from 2 once the rooms near the entry are dark. Walk into a dark room with a fuse
   in it (its amber glow is the item's own; nothing else in the dressing glows amber, EYECANDY.md §2). Flashlight on,
   turn slowly until the glow is in the cone, walk to it. The FUSES counter on the HUD goes up. Real play, no staging.
4. **`lift_powers`.** A first run played properly: collect every fuse and walk into the freight elevator's room. The
   lift powers when you arrive with them all (ELEVATOR POWERED). On a keyboard press Q (DESCEND). Keep the ride's first
   3 s. Phone framing: the modal and the text rows below it fit in the vertical strip (hudcheck [choice]); check that in
   Studio before filming.
5. **`hazard_dodge`.** A lit room of the labs band. Honest route: play to sublevel 3 (the labs; about 2 minutes at a
   medium pace) and wait in a lit room, off the car pad and away from the light fixture, 6.5 studs from the centre.
   Filming route: in the shots place, `SHOT_BAND = 2` (HUD must then stay hidden, see the rules) plus the 8/10 s interval
   (manifest note). When the ring appears step 4 studs sideways; the burst lands 3 s after the warning. For the HUD
   variant (the banner is the telegraph in first person) use the honest route only. A hit is a shove and costs nothing:
   retake freely.
6. **`band_arrival`.** Honest only (the banner is in frame): a run DESCENDed from sublevel 4 to 5. The labs' cyan grade
   glides to the server vault's cold blue over the 4 s ride (five half-lives). Camera: first person, looking at the car
   doors; when they open, turn toward a corner with a rack pair if the entry room has one (Dressing kits are random per
   room; retake on another run if not).
7. **`dark_takes_you`.** Power sublevel 1 (10 Essence in the run), DESCEND, and on sublevel 2 turn the light off and
   stand in a room the dark has taken. The exposure vignette closes in over the grace (4 s without Night Eyes) and the
   death card says THE DARK TOOK YOU — kept 2 of 10 Essence (a quarter, floored: the game's own arithmetic). HUD on.
   Nothing is staged.
8. **`board_toggle`.** Studio Local Server, 1 test player (no friends list). After a run, in the break room, walk to the
   north wall's TOP DIVERS board until the prompt shows (10 studs), press E once. Camera over the shoulder at about 12
   studs, the board filling the upper two thirds. In a place with no API access the board says it cannot be reached:
   film only on a published place's Studio session with API access on (the real public board), or skip this clip.

### Captions that stay honest

- There is no monster. The threat is the dark on a schedule; the silent figure that sometimes stands in a dark room
  changes no rule. Do not call it a stalker or a hunter (DESIGN.md §17).
- No co-op: players share the break room, and each plays their own facility.
- The brag is reaching the overgrown bio-lab (sublevel 11). The pacing model's medium-speed bot got there after a median
  of 26.9-37.0 minutes over six samples of 30 (EYECANDY.md §2; 30.5 in the latest, 2026-10-01); that is a bot, not telemetry, so say "within your first
  hour" at most.
- The critters are scenery: they never hurt, never block and never point at anything. Do not caption one as a threat.
- Nothing costs Robux. Hazards cost nothing but a shove. The board ranks the deepest sublevel whose lift you powered,
  earliest first on a tie, measured by the server.
