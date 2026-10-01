# Anomaly: Night Shift at the Observatory — clip list

Nine short gameplay moments for `tools/film_game.py` (`docs/complete-game-standard.md` §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real
renderer, HUD and physics; never the emulator). Filming is the night shift's job (Studio 00:00-06:00, standard
§5). This file says what to film and how to stage it.

Live: https://www.roblox.com/games/123669267191209 (universe `10544008743`).

## What exists already, and what is new

* **Spot-the-difference stills and shorts** exist: `tools/film_anomaly.py` shoots matched clean/anomalous pairs
  into `marketing/pairs/`, and 11 shorts cut from them are in `marketing/tiktok/` (see its README). Those are
  stills with a reveal, not gameplay.
* **`tools/film_game.py` has no Anomaly scenarios yet.** Every clip below is **new**: it needs a scenario in
  `tools/film_game.py`, which belongs to the tools owner. The staging notes are written for that.

## Rules for staging (what a scenario may and may not do)

`film_game.py` may teleport the character, script the camera, redeem the public codes and read the server's
roll (`ServerStorage.PassInfo.<userId>`, attributes `Clean`, `AnomalyId`, `Serial`; server datamodel only,
exactly as `film_anomaly.py` does). It never edits the game's numbers and never fakes progress the HUD then shows:

* **Days are earned.** Answer passes for real (walk, then ADVANCE on a clean pass, TURN BACK on an anomalous
  one; `PassInfo` says which). The HUD's Day comes from the server's own state, so setting
  `leaderstats.Day` by hand moves only the sky and the player list: allowed ONLY for sky clips with every
  ScreenGui hidden (the capture rig's `HUD_OFF`) and Roblox's UI off, as in `EYECANDY.md` §9 step 5.
* **To film a particular anomaly**, keep answering until `PassInfo.AnomalyId` is the one you want (the day-1
  pool is the first 8 of `Config.Anomaly.Catalog`; later ones need a higher Day). Do not force it.
* **The run is saved now** (owner decision 2026-09-30). A fresh test account starts at Day 1; an account that
  has played before starts on its saved Day and hall. For clips that must start at Day 1, answer one pass
  wrong first (on camera or off).
* Hide the HUD for sky and board clips (`HUD_OFF`) unless the HUD is the point of the clip.

## The clips

| # | clip | length | staging |
|---|---|---|---|
| 1 | **Normal. Advance.** A clean hall, walked end to end, ADVANCE: Day +1 and the hall loops. | 12 s | Wait for `Clean = true`. Camera: default, behind the character. Walk the hall at normal speed (`nav` to the AdvancePad), press **E**. Keep the HUD: the Day ticking up is the payoff. |
| 2 | **Something is wrong.** An anomalous hall; the player stops, turns back: Day +1. | 12 s | Wait for `figure_end` (The Watcher, day-1 pool). Walk slowly, stop 20 studs from the end, then TURN BACK (**Q**) at the BackPad. The figure is at the end of the hall: it must be in frame for 2 s before the call. |
| 3 | **The Flicker.** A light strobing that shouldn't. A still cannot show it (`check_anomaly_attrs`: it is temporal). | 10 s | Wait for `flicker_hall` (needs Day 7+: pool index 11). Stand under fixture 3 (hall-local z = -38), camera looking up the hall at it for 4 s, then walk to the BackPad and TURN BACK. |
| 4 | **Wrong call.** ADVANCE past an anomaly: red flash, the shake, back to Day 1, the toast naming what was missed. | 9 s | Reach Day 5 or more first (so the reset is visible). Wait for an obvious anomaly (`scope_gone` or `door_extra`), walk past it without looking, press **E**. Keep the HUD: the Day falling to 1 and the toast are the clip. |
| 5 | **Take a break.** B: the screen fades, the camera steps out to the telescope, the aurora sways over the ridge and light snow falls round the camera (the Aurora's weather, 2026-10-01; the break's green-cast light is the band's own). | 12 s | Reach Day 9+ (Aurora) by answering. Stand still on the floor, press **B**, keep hands off WASD for 10 s, press **B** to come back. HUD hidden except the sky's own caption. |
| 6 | **The storm rolls in.** On a break, the sky glides from the comet into the Storm Front: clouds, rain, silent lightning. | 15 s | Sky clip: HUD and Roblox UI off. Server command bar `leaderstats.Day.Value = 21`, wait 45 s, press **B**, then set `Day.Value = 22` and record 14 s (the glide takes about 11 s). |
| 7 | **Deep Sky.** The headline sky (a normal player's ~34 minutes): nebulae, the Milky Way, a distant galaxy. | 10 s | Sky clip: Day 33 by the command bar, wait 45 s, press **B**, record from 1 s in (the pan is centred, see `luau marketing/print_shotlist.luau`). |
| 8 | **The Field Guide board.** Turn round at the start, read the top 10, press **L**: your friends' Field Guides. | 10 s | A test account with a few types caught. Turn the character to face the sign on the right-hand wall behind the start pad (hall-local x 9.3, z 2), walk up, press **L**, hold 3 s, press **L** again. The board shows real player names: film only with accounts that agreed to be shown, or blur the names. |
| 9 | **Something flies past.** On a break, a few bats flap past high up, near the moon (the Meteor Shower's critters; 2026-10-01). | 12 s | Sky clip: HUD and Roblox UI off. Day 6 by the command bar, wait 45 s, press **B** and keep recording until a flight comes (one every ~2.5 minutes on average; a bat flight lasts 5 s and fades in and out). Cut 3 s before and 4 s after it. Fireflies over the valley (Day 1-3, 12 s flights) work the same way. Never on Days 22-28: nothing flies in the storm. |

Order for one session (fewest restarts): 4 (it resets you to Day 1), 1, 2, 3 (climb to Day 7 while waiting for
the flicker), 5 (continue to Day 9), 8, then the sky clips 9, 6 and 7 (command-bar Days, no more answering after).

## Checks before posting a clip

* The HUD's Day in the frame is one the account really reached (clips 1, 2, 4).
* No player name except the test accounts' (clip 8).
* Every anomaly in a clip is the one `PassInfo` named for that pass (the toast in clip 4 names it too).
