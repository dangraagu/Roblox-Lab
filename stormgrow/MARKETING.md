# StormGrow: Mutation Farm — marketing plan and clip list

**State: not published, no universe, never opened in Studio, no screenshot or clip exists.** Everything media-heavy
waits for the night shift (the standard §5): Studio check of `EYECANDY.md` §8, thumbnails (`EYECANDY.md` §9), the
clips below, the universe, publishing. Marketing starts only after the game is live, spread over a day and the
next, one game at a time, in communities whose rules allow self-promotion, labelled as AI-assisted.

## Positioning

- **One line:** *The weather runs on the real clock, the same in every server: leave your ripe crops out in the
  storm and they mutate.*
- **The hook players can repeat:** "storm on the tens, frost on the fives, rainbow at :00 and :30". Everyone can
  plan for the same :30 rainbow, in any server.
- **Genre anchors:** grow-and-sell farming sims with mutations (the radar's #4), cozy idle growers.
- **Honest limits to keep in every post:** nothing costs Robux; the odds are printed in the game (1 in 2 per storm
  or frost, 1 in 2.9 per rainbow, for a crop ripe for the whole event); mutations never happen offline (crops do
  keep growing).

## Clip list (7-15 s, vertical 1080 x 1920, for `tools/film_game.py`)

`tools/film_game.py` stages only where the character starts, the camera, and in-game codes; it never edits the
game's numbers. StormGrow has no codes. So each clip below says what it needs:
- **gameplay**: filmed at the real time of the event (the schedule is the real clock; a storm starts at every
  :x0, a rainbow at :01:30 and :31:30). Only a farm that has actually reached the band can show the band.
- **shots place**: needs `Weather.ClockOffsetSeconds` (moves the real schedule to now; what a player sees at :00)
  in a place built for filming, with Studio API access off. Honest as gameplay.
- **promo**: needs a changed number (`Weather.Chance` = 1, or a `Harvested` attribute set from the command bar).
  Captioned as promotional in the manifest, like `tools/shoot_game.py`'s `promo/`.

| # | clip | length | what happens | camera | staging | label |
|---|---|---|---|---|---|---|
| 1 | The storm breaks | 12 s | clear sky, the forecast chip counts down "⛈️ Storm 0:05", the light drops, rain, and the first bolts turn nine ripe Pumpkins blue (Charged) | behind the avatar on the porch, field 1 in front | a farm with nine ripe Pumpkins at :x9:50 (plant them at :x3:50, grow 6 min); start recording at :x9:55 | gameplay |
| 2 | Cashing a Charged field | 10 s | tap nine Charged crops, "+12K" pops rising, the coin counter jumping | over the shoulder, close (each tap lands on the crop under the finger: 1,599 of 1,599 aimed taps headless since REVIEW-1 B1; tap the crops themselves, not the gaps) | right after clip 1, the same farm | gameplay |
| 3 | Dodging ball lightning | 8 s | the banner "⚠️ BALL LIGHTNING INCOMING ▲", the red ring at your feet, one step out, the ball rolls through the crops | behind, pitch about -20 degrees (the model is on screen at launch there: 12/12 headless) | a farm in band 4+; wait in play (one hazard per ~3 min on a normal farmer's path: 159-213 s, median 173 s over 8 long walks, REVIEW-1) | gameplay |
| 4 | Rainbow after the storm | 12 s | the :00 storm fades, the seven-colour arc rises, halos appear on ripe crops (Prismatic) | wide, from the porch toward the valley | real time :01:25-:01:40, ripe crops left out through the storm | gameplay |
| 5 | TEMPEST | 10 s | the :05 frost ices a Radiant Pumpkin (Charged + Prismatic), it becomes a Tempest: spark, ice shell and halo at once, the flash, the server toast | close on one Pumpkin | at real odds a Pumpkin ripe through the golden sequence becomes a Tempest 8.75 % of the time; either film a lucky real one, or stage with `Weather.Chance` = 1 | gameplay if real, **promo** if staged |
| 6 | Into the Eye | 12 s | one harvest crosses 300,000, the card "🌀 YOUR FARM IS IN THE EYE OF THE STORM", the storm wall rising around the valley, the sunbeam | aerial over your farm, then down | a save at 290,000+ harvested and a ripe Watermelon field; or `Harvested` set from the command bar | gameplay with a real save, else **promo** |
| 7 | Frost on the fields | 8 s | band 5, the :x5 frost: snow, your soil icing over, ice rings bursting on the crops that take Frosted | low, across the field | a farm in band 5 at :x4:55 real time, or a shots-place offset | gameplay / shots place |

Every clip's staging goes into `stormgrow/marketing/clips/manifest.json` when it is filmed (the tool writes it).

## Post drafts (hold until the game is live and the clips exist)

**r/robloxgamedev (feedback, text + clip 1):**
> Title: I made a farming game where the weather runs on the real clock, the same in every server (AI-assisted)
>
> Storms hit at every :x0, frost at :x5, and a rainbow follows the :00 and :30 storms. Only ripe crops catch the
> weather, so the whole game is one decision: harvest now, or leave your crops out for the storm the forecast
> promises. Marks multiply (x5, x5, x8, up to x200 for a crop that catches all three). The leaderboard counts
> discoveries in a 56-entry Almanac, not coins: only the server's weather grants an entry, on the same clock in
> every server, so a clicker script can't out-climb a careful player. Nothing costs Robux.
> Built with an AI assistant; feedback on the first 5 minutes especially welcome.

## Channel status

| channel | status | needs |
|---|---|---|
| Roblox store listing | text ready (`README.md`, 997 characters) | a universe (night shift) |
| thumbnails | shot list ready (`EYECANDY.md` §9) | Studio |
| clips 1-7 | staged above | Studio, a filming session |
| Reddit / forums | draft above | the game live, clips, the owner's go per post |
