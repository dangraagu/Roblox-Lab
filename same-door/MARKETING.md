# The Same Door — clip list

Eight short gameplay moments for `tools/film_game.py` (`docs/complete-game-standard.md` §4). Every clip is
**vertical 1080 x 1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (the real renderer, HUD and
physics; never the emulator). Filming is the night shift's job (Studio 00:00-06:00, standard §5). Nothing
here has been filmed. `tools/film_game.py` has **no Same Door scenario yet**; each row below says how to
stage one, for the tools owner.

## Rules for staging

* **Walk, never teleport, inside a run.** The server checks every Heartbeat sample; a teleport inside the
  dungeon voids the run and stops the reveal, by design (`CLAUDE.md`, trap 3). Move the character with
  `Humanoid:MoveTo` along the points of the day's perfect line, which the scenario may read from the
  server-only `ServerStorage.SameDoor.Day` (JSON) through `Dungeon.perfectPath` (server datamodel only,
  the way `film_anomaly.py` reads `PassInfo`). Teleporting in the HUB and to the arch is fine.
* **Two kinds of place.**
  * **The Studio door** (API access OFF): Studio falls back to a fixed door from
    `Config.StudioDoorSeed = 20260930` (`DESIGN.md` §3.5). Same layout every time, so a scenario can
    hard-code it. **Nothing is saved or ranked there**, so the HUD's chip reads "Studio door (unranked)",
    the board is empty, and the brag card (THE DOOR IS SEALED) can never appear: it needs a saved profile.
  * **A private test copy with API access ON**: a real day is minted into that place's DataStore. Needed for
    clips 4 and 5. Use a test account whose profile has no Sealer yet, so the first Sealer is the brag.
* **The Studio door's layout** (lane 1, grid south-west corner at world `(0, 0, 1000)`, cells 16 studs,
  lane-local `+x` east, `+z` north), measured from `Dungeon.studioDoor` with
  `design/measure/studiodoor.luau` (rerun it after any generator or perfect-line change):

| thing | cell | world centre (x, z) | open sides |
|---|---|---|---|
| entrance / start line | (4, 0) | (72, 1008); the line is z = 1000 | |
| seal 1 | (2, 2) | (40, 1040) | |
| seal 2 | (1, 6) | (24, 1104) | |
| seal 3 | (7, 8) | (120, 1136) | |
| the Door | (3, 8) | (56, 1136) | E, S, W (enter from the south cell (3, 7)) |
| hazard slot 1 | (6, 2) | (104, 1040) | N, E, S; impacts at 6, 18, 30 ... s after the line |
| hazard slot 2 | (3, 5) | (56, 1088) | N, S, W; impacts at 10, 22, 34 ... s |
| hazard slot 3 | (1, 7) | (24, 1120) | N, E, W; impacts at 14, 26, 38 ... s |
| Dawn Sanctum | | floor centre (72, 1184), open Door at (72, 1196) | |
| hub | | spawn (0, 6), arch (0, 20), board (14, 16), campfire (-14, 16) | |

  The Studio door's perfect line is P = 25.65 s (410.4 studs; REVIEW-1: P is now the tight line the
  server's check measures, 2 studs off the jambs, grazing each pickup circle). Sealer needs <= 30.27 s,
  Gold <= 34.12 s, Silver <= 43.86 s. Walking that line at WalkSpeed 16 (measured on the polyline, 0.05-stud
  steps, `design/measure/studiodoor.luau`): seal 1 at 3.61 s after the line, seal 2 at 8.52 s, seal 3 at
  21.34 s, the Door at 25.65 s; the line enters cell (3, 4) at 5.53 s and hazard 2's cell (3, 5) at 6.05 s,
  and passes that cell again on the way back from seal 2 (last out at 11.28 s).

## The clips

| # | clip | length | staging |
|---|---|---|---|
| 1 | **The line and the first seal.** The clock starts at the line; seal 1 lifts; the Cold Cellar's blue glides into Moss green and the toast reads "1/3 Seals. The moss wakes." | 12 s | Studio door. Start in the antechamber (the arch prompt). Camera: default, behind. Walk the perfect line from the antechamber; cut 2 s after seal 1 (3.61 s after the line). The glide takes 2.4 s to land 87.5 %: keep it in frame. |
| 2 | **The third seal, and the Door wakes.** The Ember Vault's warm light, embers rising, the Door's sockets lit and its glow plate on, one hall away. | 10 s | Studio door. Walk the line; start the clip 3 s before seal 3 (7, 8), which lands 21.34 s after the line; end looking west along row 8 toward the Door (3, 8). |
| 3 | **The red ring.** A fork, the fixture shakes, the red ring pulses, the player sidesteps out of it, the stalactite lands a stud from their shoulder. | 8 s | Studio door, hazard slot 2 at (3, 5). Walk the line to cell (3, 4) (5.53 s), step north to the ring's edge, 4.5 studs from the centre, keep still; the impact is at 10.0 s (or 22.0 s). Camera: third person, low, looking north across the ring. Take a second take standing inside the ring for the knock-down (0.8 s). |
| 4 | **THE DOOR IS SEALED.** The last hall, the Door opens, a white-gold flash and an FOV punch, the card, the Dawn Sanctum at sunrise. | 12 s | **API-access-ON test place**, a test account with no Sealer yet. Run 1 at a walk (any time), then Run again and walk the line at 16: <= 1.18 P is Sealer and, being the first, the brag. Start the clip 4 s before the Door. |
| 5 | **The board flips.** Public top 10 with medal names and SEALED plates, then the player presses E: Friends. | 8 s | API-access-ON test place with a few finished runs from 2-3 test accounts that are friends. Hub, camera 8 studs in front of the board. Needs the friends list of a real account (needs-Studio item 4). |
| 6 | **Run again, faster.** The same hall twice: a slow first look, then a cornering run that reaches the same spot with the timer visibly lower. | 14 s | Studio door. Two takes of the same 20-stud stretch (the hall into seal 2), one at 10 studs/s with a pause at the fork, one on the perfect line at 16; edit side by side or back to back. HUD on: the timer is the point. |
| 7 | **Rest by the fire.** Walk to the campfire, "Rest by the fire", the character sits, the view softens, the hub in daylight behind. | 8 s | Any place. Hub. Trigger the campfire prompt; hold still 5 s; one step wakes you (show it). |
| 8 | **Into the dawn.** Through the opened Door into the open-air Sanctum: from the halls' ember light to pink sunrise, petals falling. | 9 s | Studio door. Finish any run; the server moves you to the Sanctum. Start the clip on the last seal; the band change from Ember Vault to Dawn Sanctum glides in 2.4 s. |

## After the clips

Posting follows the standard: only after the version is live, spread over a day and the next, one game at
a time, in communities whose rules allow self-promotion, labelled as AI-assisted. The honest one-liner:
"One dungeon, the same for everyone, new every day. Find 3 Seals, open the Door, race the board."
