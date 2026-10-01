# +1 Jump Every Step — clip list

Ten short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real
renderer, HUD and physics; never the emulator). `film_game.py` records the vertical strip and encodes it at
1080x1920; each clip's staging goes into `marketing/clips/manifest.json`.

Filming is the night shift's job (Studio 00:00-06:00, `docs/complete-game-standard.md` §5). This file says what
to film and how to stage it. `tools/` belongs to the tools owner: the clips marked **new** need a scenario added to
`PLUS1` in `tools/film_game.py`. The ones marked **exists** are there already and were recorded on 2026-09-17,
before the board, the climb guard and (on the live place) the sky.

## Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera, and redeem the public codes.
It never edits the game's numbers and never fakes progress the HUD then shows.

**The climb guard (2026-09-30) changes what a teleport can show.** The server now credits a platform only when a
jump could have got the character there (`Config.Guard`, `EYECANDY.md` §16). A teleport more than about ten jumps
above the last platform the profile really earned is not credited: the character climbs, but the jump counter and
the Tier on the HUD stay where they were. Measured for the existing scenarios through the real server
(2026-10-01, `film_game.py`'s own steps and sleeps: `plus1_codes_setup` redeems WELCOME and SKYHIGH, waits 1 s,
teleports onto the LAST tile of the tier below, 4 studs up, waits 0.8 s, then `plus1_climb` hops). The two codes
make the jump 28.2 studs, so the buffer is 282 studs above the last credited platform once it is full. A fresh
profile's buffer starts at 72 studs (ten jumps of 7.2 at join) and refills at about 53 studs a second, so it is
full about 4 s after the join.

| scenario | the setup teleports onto | above the pad | from a fresh profile | in the order below, one Play session |
|---|---|---|---|---|
| `climb_tier3` | `P_2_6`, y 83 | 75 studs | credited | credited, then all 6 hops |
| `saw_tier5` | `P_4_6`, y 218 | 210 studs | credited when the setup starts 2 s or more after the join; not at 0.5 s | credited, then all 5 hops |
| `pendulum_tier6` | `P_5_6`, y 308 | 300 studs | **never** credited (300 > 282), and no hop after it either | credited, then all 6 hops |

So run `climb_tier3 saw_tier5 pendulum_tier6` in that order in one session (only `climb_tier3` restarts Play).
For a clip high up the tower, either hide the HUD (clips 3, 4, 6, 10 below do) or film a save that really climbed
there. Do not switch the guard off to make a counter move: that would be exactly the faked progress the rules forbid.

Never film the Friends view with a real account's friends list visible: it shows their Roblox usernames. Use a
Studio Local Server test player (no friends: the board then says what an empty friends board says) or blur it.

## The clips

| # | clip | status | length | what the viewer sees |
|---|---|---|---|---|
| 1 | `climb_tier1` | exists | 9-11 s | a fresh player hops up tier 1; the counter goes +1 on every new tile |
| 2 | `code_launch` | exists | 9-11 s | a normal hop, the public code LAUNCH (+100), the same hop again to ~60 studs |
| 3 | `space_arrival` | **new** | 9-12 s | stepping into tier 85: "YOU REACHED SPACE!", a white flash, the FOV punch, Earth below |
| 4 | `cloud_break` | **new** | 10-12 s | climbing out of the whiteout of the cloud sea into low gold sun, the deck to the horizon |
| 5 | `hazard_dodge` | **new** | 8-12 s | the warning, the red ring, a step out of it, an asteroid passing through where the player stood |
| 6 | `storm_lightning` | **new** | 9-11 s | a jump between storm platforms while lightning lights the deck |
| 7 | `board_toggle` | **new** | 7-9 s | at the spawn: the Top Climbers board, E pressed, PUBLIC turns to FRIENDS |
| 8 | `rebirth_prestige` | **new** | 9-12 s | tier 10, REBIRTH pressed, back on the pad with the 2x multiplier on the HUD |
| 9 | `tower_path` | exists | 11 s | the camera flies up the tile path of tiers 1-6, hazards included |
| 10 | `galaxy_orbit` | **new** | 10-12 s | a slow orbit around a climber on tier 250 with the spiral galaxy below |

### Staging, clip by clip

Tower positions are for `WorldSeed 20260905` (`EYECANDY.md` §9 has more of them). `P_t_i` is platform *i* of
tier *t* in `workspace.Tower`.

1. **`climb_tier1`** (exists). Fresh Play, character on the base pad facing +Z, camera distance 20. Honest under
   the guard: every hop is a real jump from the pad up.
2. **`code_launch`** (exists). Fresh Play, pad, camera 26. The code goes through the game's own Redeem remote.
   With Studio's API access off there is no save, and the game grants a code for the session (it cannot be saved
   anyway); with a save that another session holds, the game refuses the code and says so, which is correct.
3. **`space_arrival`** (new). Build the tower that high first: in the shots place only, `Tower.StreamAhead = 260`
   (as `EYECANDY.md` §9 session A; this changes which tiers are built, not any number the player sees). Teleport to
   `P_84_6` at (-18, 20 240, 4 126), hide `Plus1Hud` (its counter would be a fresh profile's), keep `Plus1Sky`
   (the card lives there). Wait for the Edge of Space card to fade, then hop to `P_85_1` at (-18, 20 284, 4 140).
   The card, the flash and the FOV punch play once per session: record the first try. Camera behind, 22 studs.
4. **`cloud_break`** (new). Same shots-place build. Teleport into the whiteout at `P_22_6`, HUD hidden, hop up
   through `P_23_1` to `P_23_4` (about y 4 050, above the tallest puffs). Camera behind and 10 above, pitched down
   about 15 degrees so the deck fills the lower half. Hot-air balloons drift; start when one is in the frame.
5. **`hazard_dodge`** (new). `EYECANDY.md` §9 session B settings: `Hazards.IntervalMin = 8`,
   `Hazards.IntervalMax = 10`, `Rest.IdleSeconds = 0`. **This shortens the wait for filming only; say so in the
   manifest's staging list** (a normal climber meets one hazard every 2-3 min, `Pacing.spec`). Character on
   `P_160_1` at (24, 40 084, 8 214), HUD shown (the warning banner is the point), camera side-on at 40 studs. When
   the ring turns red and the banner says MOVE!, walk half a tile out of the ring, sideways. Keep the take where
   the asteroid passes through the empty ring.
6. **`storm_lightning`** (new). Shots-place build, character on `P_44_1`, HUD hidden, camera level with the
   character about 60 studs to the side. Lightning comes every 6-14 s: record 15 s and cut the 10 s around a bolt,
   with one hop to `P_44_2` in it.
7. **`board_toggle`** (new). Studio Local Server, 1 player (a test player with no friends list). Fresh Play, walk
   from the pad to the board (about 4 studs toward -Z until the prompt shows), press E once. Camera over the
   shoulder at 14 studs, the board filling the upper two thirds. What it shows: the public top 10 (empty in a fresh
   place: "No climbers on the board yet...", so seed nothing and film that, or film on the published place's
   Studio session with API access on so the real public board shows) and then the Friends view's message.
8. **`rebirth_prestige`** (new). Needs a save that really stands on tier 10 or above (climb it in an earlier
   session: about 4 minutes of play). HUD shown. Press REBIRTH (it is lit, purple): the character is put back on the
   pad, the HUD shows Rebirths 1 and Multiplier 2x. Camera behind at 26 studs. Do not claim a faster climb in any
   caption: rebirth multiplies jump height, which caps at 60 studs (owner decision 2026-09-30).
9. **`tower_path`** (exists). Scripted camera path, no character. Unaffected by the guard.
10. **`galaxy_orbit`** (new). Shots-place build, character teleported to `P_250_1` at (-60, 63 844, 13 338), HUD
    hidden, the `orbit` camera helper in `film_game.py` at radius 150 and up 60, sweeping about 120 degrees over
    11 s. The spiral galaxy must be below the character for the whole sweep.

### Captions that stay honest

Space is "about 35 minutes in" (the pacing model's 34.4 min for a normal player, not telemetry). A hazard hit
knocks you off; nobody dies. Rebirth is prestige, not a shortcut. The board ranks best tier, earliest first on a
tie, and is server-measured: a teleport does not put anyone on it.
