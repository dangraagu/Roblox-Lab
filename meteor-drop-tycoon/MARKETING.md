# Meteor Drop Tycoon — clips and marketing

Nothing here has been filmed or posted. The game is not published and has no universe yet. Filming, publishing
and marketing belong to the night shift (`docs/complete-game-standard.md` §5), in this order: the Studio check of
`EYECANDY.md` §8, thumbnails (`EYECANDY.md` §9), these clips, the universe, publishing, and only then marketing.

## Clips (7 scenarios, vertical 1080 x 1920, 7-15 s, for `tools/film_game.py`)

`tools/film_game.py` records the real Studio viewport and may stage only where the character starts, the camera,
and codes the game itself offers every player. **It never edits the game's numbers and never fakes progress the HUD
then displays.** Meteor Drop Tycoon has no codes, so a clip that needs progress (a Beacon level, a Collector) needs
a profile that really got there. The column "progress" says which clips can be filmed from a fresh profile and
which need a played-up one: play up a test account in Studio with API Services ON against a test place (never the
live one), or film those during a real session. Do not use the place-only Config edits from the thumbnail recipe for
a clip.

| # | clip | s | progress | how to stage it | what the viewer sees |
|---|---|---|---|---|---|
| 1 | **First catch** | 8 | fresh profile | Join; the camera behind the avatar on the arrival pad, facing the Smelter. Record from the join. | The first meteor streaks in and glows 10 studs ahead, lands (at 2.0 s in the model), the avatar walks 5 studs, the rock zips into the Smelter, the hopper bar fills, the hint changes to "Meteors melt into Stardust". |
| 2 | **The Falling Star** | 15 | Beacon 21 and at least 1 538 Stardust (the price of 22) | Stand 10 studs from the arrival pad, the camera 3/4 behind the avatar with the pad in frame. Open ⬆ Upgrades, tap BUY on the Beacon. | The Starfall title card, the sky gliding to the comet, the gold beam at the showcase spot, the star descending for 4 s, the walk to it, the white flash, FOV punch and shake, "YOU CAUGHT A FALLING STAR!", the gold crown on the Beacon. |
| 3 | **Sky change** | 12 | Beacon 9 and at least 369 Stardust (levels 10, 11, 12 cost 96, 121, 152) | The camera low behind the avatar, pitched 25° up. Buy three Beacon levels, 2 s apart. | Twilight gliding into the Aurora: the aurora curtains fading in, stars thickening, snow starting, the Beacon beam going from lavender to teal (the Aurora's weight goes 0, 0.26, 0.74, 1). |
| 4 | **Dodge** | 10 | Beacon 5 or more (any hazard band) | Walk the plot; wait for "⚠️ ... INCOMING". The camera 12 studs back, 30° down, so the ring and the object overhead are both in frame. | The ring at the avatar's feet, the object hanging overhead with its pillar, "MOVE!", one step out of the ring, the impact a stud away, no knock. Needs patience: one hazard per 120-180 s. |
| 5 | **Collector at work** | 10 | Collector 8 at the Galactic Core (Beacon 44+) | Stand at the plot's rim, the camera high over the Smelter looking down 50°. | The big dish swallowing half the rain with no walking while the avatar sprints for a gold Star Core outside it. |
| 6 | **Stargaze** | 10 | the Galactic Core (Beacon 44+) | Stand still on the plot; tap ☕ Stargaze. | The avatar sits, the camera tilts slowly up to the galaxy disc and its arms, the chip reads "☕ Stargazing: the sky leaves you alone". |
| 7 | **Star Chart** | 8 | at least Beacon 1 (to be on the board) | Walk from the arrival pad to the board beside it; use its prompt twice. | The board by the spawn: the public top 10 with band emoji, then Friends ("Loading friends… 3 / 12" filling in), then back. |

## Where and when (after the new version is live)

Per the owner's standard: marketing starts only after the version is published and live, spread over a day and the
next, one game at a time, only in communities whose rules allow self-promotion, and every post says it is
AI-assisted (the repo's Reddit rule 6 note). Lead with clip 2 (the brag moment) or clip 1 (the core action in two
seconds); the store text is in `README.md`.

Honest claims only: the minutes ("about 35 minutes to your first Falling Star") are the pacing model's, not
telemetry, and must be said as "about". Nothing is sold, so no post may imply a reward for likes, favourites or
follows.
