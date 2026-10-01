# Anomaly: Night Shift at the Observatory 🔭

A spot-the-difference **anomaly horror** game. You're the lone night caretaker of a looping
observatory concourse. Each pass, a procedural roll either leaves the hall **normal** or
injects exactly **one anomaly** (a moved telescope, an extra door, a figure that shouldn't
be there…). At the hall's end you decide:

- **ADVANCE** (key **E**) if it looked normal
- **TURN BACK** (key **Q**) if you spotted something wrong

Correct call → your **Day** counter ticks up and the hall loops. Wrong call → the night
resets to **Day 1**. There is **no chase / pathfinding AI** — the tension is pure observation.
Game-Radar #1 concept (2026-09-06); reuses the procedural-gen + DataStore + single-server
stack from the maze / +1 Jump / Grow a Crystal games.

## Store description (Roblox listing, 923 characters of the 1000 allowed)

```
You are the night caretaker of an observatory hall that loops. Walk it and look closely. Each time round, the hall is either exactly as it should be, or exactly ONE thing is wrong: a figure at the end of the hall, a missing telescope, a clock that reads the wrong time, a light that flickers.

At the end of the hall, ADVANCE if everything looked normal, or TURN BACK if you spotted something wrong. A right call adds a Day. One wrong call and the night starts over at Day 1.

- 24 anomalies to catch for your Field Guide
- A board at the start compares Field Guides with everyone, or just your friends
- The sky outside the doorway changes as your Day grows: meteor showers, aurora and snow, a great comet, a storm, deep sky and stranger things
- Take a break at the telescope any time (B)
- Your Day and your hall are saved if you have to leave

Nothing chases you. It is just you, the hall, and whatever does not belong.
```

## Layout (Rojo)
- `src/server/` → `ServerScriptService` — authoritative (`Main.server.luau`)
- `src/client/` → `StarterPlayerScripts` — HUD (`Hud.client.luau`)
- `src/shared/` → `ReplicatedStorage` — pure, unit-tested modules:
  - `Config.luau` — every tunable (anomaly catalog, chance curve, codes, save, milestones)
  - `Rng.luau` — deterministic LCG (same in Studio + luau-CLI)
  - `Anomaly.luau` — the clean/anomaly roll (deterministic per pass)
  - `Progression.luau` — Day/streak rules (correct → Day+1, wrong → reset)
  - `Codex.luau` — the "Field Guide" of caught anomalies (string-keyed set)
  - `Codes.luau` — one-time code redemption
  - `Highscore.luau` — the Field Guide board's value (types caught, then who got there first)

## Core loop
Rebuild hall CLEAN → roll (`Anomaly.rollPass`) → if anomalous apply exactly ONE spottable
mutation → player walks to the end → ADVANCE / TURN BACK (in-world ProximityPrompts) →
`Progression.resolve` → correct loops to Day+1, wrong resets to Day 1. A **hint** (key **H**
at the start pad) spends a token to reveal whether the current hall is clean.

## Run in Studio
1. `rojo build -o Anomaly.rbxlx` (or `rojo serve` + Studio plugin).
2. Press **Play**. Output: `[Anomaly] Night Shift at the Observatory loaded.`
3. DataStore needs a published place or Studio → Game Settings → Security → *Enable Studio
   Access to API Services* (without it the game still runs, saves are skipped).
4. You spawn on your private concourse. Walk to the end, read the hall, ADVANCE or TURN BACK.

## Tests
Every gate, and how to run it, is in `CLAUDE.md` ("Gates"). In short: every `tests/*.spec.luau` with the
luau CLI, and every `robloxemu/check_anomaly*.luau` after rebuilding the bundle
(`py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau`).
`check_anomaly_attrs` identifies the clean hall from the world alone and answers each pass by reading the
hall, which is the game's deepest invariant: the hall differs from clean exactly when the server scores the
pass as anomalous. `check_anomaly_names` holds the line that no anomaly changes the hall's instance TREE
(names, classes, parents), only what is drawn.

## Saved run, Field Guide board (2026-09-30)
* **Your run is saved** (owner decision 2026-09-30): the Day and the live hall are saved while the session
  holds the save lock and restored on a rejoin, so an idle kick or a phone switching apps no longer costs
  the streak. Leaving is never a re-roll (the same hall comes back), and a wrong call is written at once,
  so leaving during the death beat does not undo it (`robloxemu/check_anomaly_rejoin.luau`).
* **The Field Guide board**: a sign on the right-hand wall just behind the start pad ranks everyone on
  anomaly types caught (0-24), ties broken by who got there first; **L** (or tap) switches to your friends.
  Its own OrderedDataStore (`Config.Save.GuideStore`); Best Day and its board are unchanged.

## The night sky outside (2026-09-23) — see `EYECANDY.md`
The sky beyond the hall's open entrance progresses with your **Day**: a crescent moon that waxes
with your streak, then a meteor shower (Day 4), aurora (9), the Great Comet (15), a storm front with
silent lightning and rain (22), Deep Sky nebulae (31, the headline: ~34 min for a normal player),
the planetary Alignment (40) and The Other Sky (50). A wrong call's reset glides it back to the first
night. **The hall itself never changes**: everything lives beyond the entrance (behind the spawn and
behind the capture rig's camera), casts no light, reads nothing about the pass and uses no red.
**🔭 Break (B)** is the rest: the camera fades out to the telescope, looking up and away from every
hall; move or press again to come back. Nothing is paused because nothing needs pausing; the server
is never told. The break never calls your Day "safe". Roblox disconnects a player idle for ~20
minutes; once Roblox reports you idle the break says so, and says the Day and the hall are saved only
when this session saves the run (otherwise that saving is off). On a
phone nothing is written over the hall during a pass (it would sit on the wall you are reading): news
of a new sky waits for your next break, and the button turns a steady blue meanwhile.

Client-only: `src/client/Sky.client.luau`, `src/shared/SkyArt.luau`; pure + tested:
`src/shared/NightSky.luau`, `EnvBands.luau`, `Rest.luau` (the last two copied from +1 Jump), numbers
in `Config.Sky`.

```
luau tests/EnvBands.spec.luau      luau tests/NightSky.spec.luau     luau tests/SkyConfig.spec.luau
luau tests/Rest.spec.luau          luau tests/Pacing.spec.luau
(robloxemu)  luau check_anomalyobservatory_sky.luau     the sky follows the real Day; the hall never changes
             luau check_anomalyobservatory_rest.luau    the break changes nothing and never looks at a hall
             luau check_anomalyobservatory_hud.luau     HUD + break button fit every viewport
             luau check_anomalyobservatory_events.luau  every frame: meteors, lightning, turning stars stay out; event rates
             luau check_anomalyobservatory_cap.luau     the particle budget is enforced in code (made to bind)
             luau check_anomalyobservatory_occlusion.luau  the sky's GUI never sits on the hall during a pass
             luau check_anomalyobservatory_shots.luau   the thumbnail shot list, played against the real sky
             luau check_anomalyobservatory_news.luau    on a phone, news for the break is never lost
             luau check_anomalyobservatory_critters.luau  the critters fly exactly their schedule, out of the hall
             luau check_anomaly_walk.luau               the whole player path, every refusal answered
             luau check_anomalyobservatory_weather.luau  each band's own weather and its light on the break
```
**Every band has its own weather and its own light** (2026-10-01, standard §2): thistledown drifting on the
breeze (Clear Night), snow under the aurora, glittering frost for the Comet, the storm's rain, dry leaves blowing
past the Alignment and pale motes rising in The Other Sky, all of it falling (or rising) out in front of the
entrance; the Meteor Shower and Deep Sky are clear skies, and their bands say why. A band's light is the
telescope break's colour grade (cool moonlight, a green cast under the aurora, dim and grey in the storm, warm
for the Alignment): the hall itself is never lit differently, so the break is the only place a band's light can
show (`check_anomalyobservatory_weather`).

There are no hazards (nothing chases you is the premise). The harmless rare events are the **critters**
(2026-10-01): every band has its own (fireflies, bats, geese, an owl, wisps; none in the storm), and about
once every 2.5 minutes a flight crosses the night beyond the entrance. Measured budgets, gate counts, the
mutation sweeps, the Studio list and the **thumbnail shot list** are in `EYECANDY.md`.

## Marketing
`marketing/pairs/` holds matched clean/anomaly stills and the spot-the-difference shorts cut
from them. `py -3 tools/film_anomaly.py` makes more; see `marketing/pairs/README.md`.

## Codes (edit in `Config.Codes`)
`WELCOME` +3 hints · `OBSERVE` +5 hints · `MIDNIGHT` +10 hints · `ECLIPSE` gold flashlight tint.

## Deploy
Live: https://www.roblox.com/games/123669267191209 (universe `10544008743`), Public. Publish with the
git-ignored `publish_anomaly.bat` (Open Cloud). `git push` does not update the live game; publishing is the
night shift's job. Milestone Badges are OFF until real Badge asset ids fill `Config.Milestones` wiring
(`awardMilestone`). The clip list for marketing is `MARKETING.md`; the thumbnail shot list is
`marketing/ShotList.luau` (print it with `luau marketing/print_shotlist.luau`).
