# Fork Tower — clip list

What to film for the shorts, and how to stage it honestly (docs/complete-game-standard.md §4). Written 2026-10-01
(pass 2). Nothing here has been filmed: filming is the night shift's job (Studio 00:00-06:00, §5 of the standard),
and the game has no experience yet. The thumbnail shot list is `EYECANDY.md` §11; the store text is in `README.md`.

## Clip list

Eight short gameplay moments for `tools/film_game.py`. Every clip is **vertical 1080x1920, 30 fps, 7-15 s**,
filmed from the real Studio viewport (`--source capture`: the real renderer, HUD and physics; never the emulator).
`film_game.py` records the vertical strip and encodes it at 1080x1920; each clip's staging goes into
`marketing/clips/manifest.json`.

`tools/` belongs to the tools owner, and `film_game.py` has **no Fork Tower entry yet** (its `GAMES` holds plus1,
crystal and laby; `tools/studio_open.ps1` has no `fork-tower` key either, CLAUDE.md "Commands"). So every clip
below is **new**: it needs a `FORK = {...}` scenario table and a `"fork": FORK` line in `GAMES`, written to the
staging here. `tests/docs_check.py` holds the marks to the file: a clip marked `exists` must be a scenario there.

| # | clip | status | length | what the viewer sees |
|---|---|---|---|---|
| 1 | `which_door` | new | 9-12 s | two identical doors, the locked inscription, a 1.1 s read, the answer, a walk through the safe door |
| 2 | `liar_floor` | new | 9-12 s | a read on floor 4 or higher that says the warden LIES, and the climber taking the unmarked door |
| 3 | `trap_taken` | new | 10-13 s | a read, then the TRAP door on purpose for the trait behind it, and the longer, busier section it builds |
| 4 | `hazard_dodge` | new | 8-12 s | the clockwork's warning, the red lane and ring, one step out, the cog rolling through the empty ring |
| 5 | `storm_lightning` | new | 9-11 s | a hop between storm platforms while lightning lights the deck |
| 6 | `summit_reveal` | new | 10-13 s | the last exit, the summit, the Build Reveal card, the crown of stars circling the climber |
| 7 | `board_toggle` | new | 7-9 s | the toplist board behind the spawn, E pressed, OFFENTLIG turning into VENNER |
| 8 | `rest_break` | new | 7-9 s | a climber sits down with ☕ Hvil on a section platform, the view softens, the garden goes on around them |

### Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera, and redeem the public codes.
It never edits the game's numbers and never fakes progress the HUD then shows.

**The exit rule (2026-09-30, CLAUDE.md invariant 16) decides what a teleport can show.** A floor clears only when
the server sees the character standing on the section's exit AND the section's least climbing time
(`Section.minClimbSeconds`, 1.3-3.3 s a floor) has passed since the door. A teleport onto an exit after waiting that
long does clear the floor, which is exactly what a script can do and exactly the progress the rules forbid faking.
So: **climb for real** (hop the platforms, as `film_game.py`'s `hop` does for +1 Jump: about 4.5 minutes for ten
floors at a normal pace), or **hide `ForkHud`** for a shot whose floor was reached any other way, and never caption
a floor number the climber did not climb. Session A / B below are `EYECANDY.md` §11's two Studio sessions.

Positions are for `WorldSeed 20260909`, lane 0, a fresh profile taking the safe door every floor (measured headless,
`EYECANDY.md` §11; a section's geometry does not depend on the floor's secret, so the safe path is the same tower in
every session). Fork pad tops: `ForkPad_1` (0, 0, 14), `ForkPad_4` (-34.5, 57.8, 215.8), `ForkPad_7` (2.5, 142,
424.5), summit pad top (-9.2, 309, 882). The doors of fork *n* stand 8 studs past its pad's centre (+Z), 6.5 either
side. The board (`Lane_0.TopBoard`) stands at the back of the lobby, centre about (-6, 5.5, -15), facing the spawn.

Never film the Friends view with a real account's friends list on it: it shows their Roblox usernames. Use a Studio
Local Server test player (no friends: the board then says what an empty friends board says) or blur it.

### Staging, clip by clip

1. **`which_door`** (new). Fresh Play, session A, the character on `ForkPad_1` facing the doors (+Z), the fork
   unread. Camera behind and a little above, 16 studs, both doors and the inscription billboard in frame. Hold E on
   the inscription prompt (the 1.1 s fill is the point; the server times it, so a scripted fire is not faster),
   then walk through the safe door. Do not read floor 1 before recording.
2. **`liar_floor`** (new). Needs a save that really stands on floor 4 or higher: climb floors 1-3 for real in the
   same Play session (about a minute at a normal pace, `Pacing.spec`). A floor from 4 up lies only sometimes
   (`Config.Fork.LiarChance`): read each floor from 4 on, keep recording, and cut the take where the inscription
   says `VOKTEREN LYVER`. HUD shown (its counter is real). Camera as clip 1.
3. **`trap_taken`** (new). Floor 2 or 3 of a real climb. Read the fork, then walk through the TRAP door on purpose
   (the caption: "I wanted that trait"). Cut on the section building: four more platforms and two more hazards
   than the safe door's (`Config.Tower.PenaltyExtraPlatforms`, `PenaltyExtraHazards`); a high camera, 40 studs up
   and back, shows the length. Never caption a trap as a death: it is a longer climb, nothing else.
4. **`hazard_dodge`** (new). Session B (`EYECANDY.md` §11 shot 3): a real climb to floor 6, the clockwork. For the
   take only, `Config.Hazards.IntervalMin = 8`, `IntervalMax = 10`, `Rest.IdleSeconds = 0` in the running game, **and
   say so in the manifest's staging list**: a normal climber meets one hazard every 2-3 min (`Pacing.spec`). Stand
   still on a section platform, the normal camera looking along +Z; when `⚠️ TANNHJUL KOMMER` and the red lane
   show, walk sideways out of the ring and keep the take where the cog rolls through the empty ring.
5. **`storm_lightning`** (new). Session A, a real climb to floor 7. A hop between two section 7 platforms (around
   `Plat_7_5`, top (-10, 165, 466.5)), camera across the tower from about (-70, 176, 444). Lightning comes every
   6-12 s: record 15 s and cut the 10 s around a bolt with the hop in it.
6. **`summit_reveal`** (new). The end of a real ten-floor run (session A: about 4.5 min). Start recording on the
   last section, land on its exit, and keep going until the Build Reveal card is up and the crown of stars circles
   the climber on the summit pad. HUD shown: the card is the point. A save with 5 or more summits shows a rarer
   crown (`Config.Env.CrownTiers`); film the one the save really has.
7. **`board_toggle`** (new). Studio Local Server, 1 test player with no friends list. Fresh Play: walk from
   `ForkPad_1` back across the lobby to the board (about 28 studs toward -Z) until the `Offentlig / Venner` prompt
   shows, press E once. Camera over the shoulder at 12 studs, the board filling the upper two thirds. A fresh place
   has an empty public board ("Ingen på lista ennå ..."): film that, or film the published place in Studio with API
   access on so the real top 10 shows. Then the Friends view's message.
8. **`rest_break`** (new). Session A, a real climb to floor 3 or 4 (the overgrown garden). Stand still on a section
   platform with no hazard inbound, press ☕ Hvil: the character sits, the view softens, the chip says
   `☕ Hviler — farene lar deg være`; butterflies and pollen go on. Camera side-on at 20 studs. Cut before `▶ Klatre`.

### Captions that stay honest

The read costs 1.1 seconds, timed by the server. A trap is a longer, busier climb, never a death or a lost run. A
hazard hit knocks the climber down for under a second. Rest pauses the hazards and earns nothing. The board ranks the
best Build Reveal score, earliest first on a tie, measured by the server: a teleport does not put anyone on it. The
game's text is Norwegian; say so if a caption quotes it. Nothing costs Robux.
