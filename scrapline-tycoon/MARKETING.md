# Scrapline Tycoon — clips and marketing

Nothing here has been filmed or posted. The game is not published and has no universe yet. Filming, publishing and
marketing belong to the night shift (`docs/complete-game-standard.md` §5), in this order: the Studio check of
`EYECANDY.md` §8, thumbnails (`EYECANDY.md` §9), these clips, the universe, publishing, and only then marketing.

## Clips (8 scenarios, vertical 1080 x 1920, 7-15 s, for `tools/film_game.py`)

`tools/film_game.py` records the real Studio viewport and may stage only where the character starts and the camera.
**It never edits the game's numbers and never fakes progress the HUD then displays.** Scrapline Tycoon has no codes,
so a clip that needs progress (a station, a tier, a ready line) needs a profile that really got there. The column
"progress" says which clips can be filmed from a fresh profile and which need a played-up one: play up a test account
in Studio with API Services ON against a test place (never the live one), or film during a real session. Clip 5 is
the one exception allowed by the thumbnail recipe: the hazard rate in a place-only Config copy, said in the post.

| # | clip | s | progress | how to stage it | what the viewer sees |
|---|---|---|---|---|---|
| 1 | **First build** | 8 | fresh profile | Join; the camera behind the avatar on the arrival pad, looking up the U. Tap 🔧 Build Shredder at 2 s. | Junk trickling out of the chute and riding the belt, the tap, the Shredder dropping onto the belt with a puff, grey scrap chips leaving it, the wallet ticking from $0.5/s to $2/s, the hint changing. |
| 2 | **Bottleneck** | 10 | a line whose ★ is a twin (the 🐢 on its row) and the cash for it | Open 🏭 Line; the camera over the shoulder so the panel and the station are both in frame. Tap the gold ＋Twin. | The twin appears beside the machine, the row's load bar drops under 100 %, the 🐢 moves on, income ticks up. |
| 3 | **Sky change** | 12 | Press Works (tier 3) with 130 000 cash | Build the Cutter from its console; camera low behind the avatar, pitched 25° up. | The first gears ride the belt, the late-afternoon Press Works glides into the Machine Shop's sunset over 1.5 s half-lives, giant gears fade in on the far towers, the title card "⚙️ THE MACHINE SHOP". |
| 4 | **Saved it!** | 10 | any line past 4 minutes of play | Wait for "⚠ … sputtering: Fix 0:15" on the alert line; run along the U to the sparking machine; hold Fix. | Amber sparks, the ⚠ FIX pointer, the run, the 0.5 s hold, "Saved it!", the sparks stop. |
| 5 | **Dodge** | 10 | the Foundry or later; hazards every 8-9 s in a place-only Config copy (say so in the post) | Walk the U; wait for "⚠️ CRANE DROP"; camera 12 studs back, 30° down. | The trolley rolling overhead, the ring at the avatar's feet turning red, "MOVE!", one step out, the bale thudding a stud away, no knock. |
| 6 | **Lift-off** (the brag moment) | 15 | the Assembler running and 9.5M cash | Build the Rocket Bay; camera at the launch pad (plot-local (30, -36)), looking up past it. | The first rockets ride to the dock, one rises off the pad on flame and smoke into the night, the shake, "🚀 LIFT-OFF! Your factory builds rockets!", the server-wide toast, the Launch Site's stars. |
| 7 | **Recycle** | 12 | a line shipping 1 500+ rockets/s (♻ shows its ★) | Tap ♻ Recycle ★, read the question, tap ✓ Recycle!; the camera wide on the plot. | The confirmation, the white flash, the machines crumbling into dust, the night snapping back to midday, the factory repainted safety yellow, "♻ RECYCLED! Gold Bolt #1". |
| 8 | **Coffee break** | 10 | Robot Works (tier 5) | Stand still in the yard; tap ☕ Break. | The avatar sits, the camera drifts along the neon-lit line in the rain, the chip "☕ On break: the crane leaves you alone. Your line keeps running, and machines can still jam." |

## Where and when (after the new version is live)

Per the owner's standard: marketing starts only after the version is published and live, spread over a day and the
next, one game at a time, only in communities whose rules allow self-promotion, and every post says it is
AI-assisted. Lead with clip 6 (the brag moment) or clip 1 (the core action in two seconds); the store text is in
`README.md`.

Honest claims only: the minutes ("about 34 minutes to your first rocket") are the pacing model's and the scripted
walker's, not telemetry, and must be said as "about". Nothing is sold, so no post may imply a reward for likes,
favourites or follows.
