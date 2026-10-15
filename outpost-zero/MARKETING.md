# Outpost Zero — clips and marketing

Nothing here has been filmed or posted. The game is not published and has no universe yet. Filming, publishing and
marketing belong to the night shift (`docs/complete-game-standard.md` §5), in this order: the Studio check of
`EYECANDY.md` §8, the thumbnails (`EYECANDY.md` §9), these clips, the universe, publishing, and only then marketing.

## Clips (7 scenarios, vertical 1080 x 1920, 7-15 s, for `tools/film_game.py`)

`tools/film_game.py` records the real Studio viewport and may stage only where the character starts and the camera.
**It never edits the game's numbers and never fakes progress the HUD then displays.** Outpost Zero has no codes, so a
clip that needs progress (a population, credits) needs a profile that really got there: play up a test account in
Studio with API Services ON against a test place (never the live one), or film it during a real session. The pacing
model's numbers (`tests/Pacing.spec.luau`) say how long each takes for a normal player; they are assumptions, not
telemetry. Do not use the place-only Config edits from the thumbnail recipe for a clip.

| # | clip | s | progress | how to stage it | what the viewer sees |
|---|---|---|---|---|---|
| 1 | **First build** | 8 | a fresh profile | Join; the camera behind the avatar on the arrival pad, facing district 1. Record from the join; walk to the ★ and press BUILD, then the next ★. | The fog, the six lot outlines, the ★ over a post, the first Home rising with a puff (the walker built first at 4.0 s), the second build, "+60/min" and "📋 Orders 10:00" appearing. |
| 2 | **The Grand Airship** | 15 | a city just under 6 400 with the credits for its next pair of storeys (the brag: about 37 min of normal play) | The camera low on the plaza looking up past the Town Hall. Press the ★ until the population passes 6 400. Since REVIEW-1 round 2 the airship comes in along the line its moored nose points (square to the shelf's line to the ring's centre, from 1 500 studs out on one side), so frame across that line; check which side in Studio before rolling. | The title card "🏮 LANTERN DUSK · ⚓ SKYPORT OPEN!", the sky gliding to dusk, the airship flying in for 12 s, the mooring flash, FOV punch and shake, "THE GRAND AIRSHIP HAS DOCKED!", the server toast. |
| 3 | **The fog lifts** | 12 | a city at about population 48 with credits for several cheap storeys (about 3 min of play) | The camera 3/4 behind the avatar, pitched 15° down toward the parapet and the cloud sea beyond. Press ★ storeys across 50 → 80. | Fogbound Dawn gliding into Clear Morning in visible steps (the fade is 30 population wide): the fog banks thinning, the cloud sea and far shelves appearing, swifts, the "☀️ CLEAR MORNING" card. |
| 4 | **Dodge** | 10 | population 80 or more (any hazard band; Trade Winds has two kinds) | Play normally on your shelf; wait for "⚠️ ... INCOMING". The camera 12 studs back, 30° down. Patience: one hazard per 120-180 s of play. | The crate hanging overhead with its pillar, the red ring at the avatar's feet, "MOVE!", one step out, the impact a stud away, no knock. |
| 5 | **Tower climb** | 10 | credits for six storeys on one lot (any district) | Stand at the lot's post, the camera 20 studs out, looking up 20°. Press Add storey six times, a second apart. | The building climbing 4 studs a press with a puff each time, the prompt's count ("Home 6/22 · …") rising one storey a press. |
| 6 | **Coffee break** | 10 | Storm Front (population 35 000+, about 76 min of play) | Stand still on the plaza; tap ☕ Break. | The avatar sits, the camera tilts slowly up to the storm wall and the lightning in the cloud sea, the chip reads "☕ On a break: nothing falls on you". |
| 7 | **Census** | 8 | population 4 or more (to be on the board) | Walk from the pad to the board beside it (10 studs); use its prompt twice. | The public top 10 with band emoji, then Friends ("Loading friends… 3 / 12" filling in), then back to Everyone. |

## Where and when (after the new version is live)

Per the owner's standard: marketing starts only after the version is published and live, spread over a day and the
next, one game at a time, only in communities whose rules allow self-promotion, and every post says it is AI-assisted.
Lead with clip 2 (the brag moment) or clip 1 (the core action in four seconds); the store text is in `README.md`.

Honest claims only: the minutes ("about 37 minutes to the Grand Airship") are the pacing model's, not telemetry, and
must be said as "about". Nothing is sold, so no post may imply a reward for likes, favourites or follows.
