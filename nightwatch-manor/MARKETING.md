# Nightwatch Manor — clip list

Eight short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is **vertical
1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer, HUD and
lighting; never the emulator). `film_game.py` records the vertical strip of the viewport and encodes it at 1080x1920;
each clip's staging goes into `marketing/clips/manifest.json`.

**Nothing here has been filmed.** The game has never been opened in Studio (CLAUDE.md), so every clip is new, and
`tools/film_game.py` has no Nightwatch scenarios yet (`GAMES` lists plus1, crystal and laby; `tools/` belongs to the
tools owner). Filming is the night shift's job (Studio 00:00-06:00, standard §5), after the needs-Studio list
(EYECANDY.md §11) has been walked. A clip of a look that Studio shows to be wrong is not filmed until it is fixed.

## Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera, and use what the game offers every
player. It never edits the game's numbers and never fakes progress the HUD then shows. For Nightwatch Manor:

- **The place.** `rojo build default.project.json -o NightwatchManor-shots.rbxlx` in `nightwatch-manor/`
  (`*.rbxlx` is git-ignored) and open it from disk with *Game Settings → Security → Enable Studio Access to API
  Services* **off**. The server then runs without saves: every Play is a fresh profile on night 1. Never publish that
  file.
- **Which manor.** Every manor is planned from a server-only salt (CLAUDE.md), so its rooms are different every
  session. For a clip that needs a known room, switch the server to the public layouts first, from the command bar in
  **Server** context: `game.ServerStorage.NightwatchSecrets:SetAttribute("PublicLayouts", true)`. That picks which
  layout is built (the public one of the same night, same size); it changes no number on screen. The manifest's
  staging list must say "public layout of night N".
- **Progress is played, not configured, whenever the HUD or the band chip is in frame.** The HUD and the chip show the
  night, the relics and the band (`🩸 Blood Moon · Night 26`). A clip that shows them shows a night reached by playing.
  The thumbnail recipe's Config edits (EYECANDY.md §12: `StartNight`, `StartStash`, `SightRange = 0`) are for stills
  with both UIs hidden, never for these clips.
- **Hazards** come every 90-130 s of night. For clip 5 only, the shots place may set `Config.Hazards.IntervalMin = 6`
  and `IntervalMax = 8` (in the place's `ReplicatedStorage.Config`, as EYECANDY.md §12 shot 6 does). **This shortens
  the wait for filming only; the manifest must say so**, and no caption may say how often hazards come.
- **Flashes.** Roblox's *Reduced Motion* and the in-game ⚡ toggle must be OFF for any clip with lightning in it.
- **The board.** Never film the Friends view with a real account's friends list (it shows their Roblox usernames).
  Use a Studio test player with no friends: the board then says what an empty friends board says. Without API access
  the public board says nobody has got out yet, which is what a fresh board says.

Where things are, for the first player (zone index 1; CLAUDE.md, `Config.Hub`): the safehouse floor is centred at
(3000, 100, 0), 60 x 60 studs; the spawn pad at (3000, 100, 20); the hearth on the north wall behind it; the manor
door in the south wall at z = -30; the NIGHTS SURVIVED board on the east wall at about (3029, 106.5, 23.4), facing
west into the room, 29 studs from the spawn pad, its prompt on F. The manor's foyer is at (3000, 100, -400).

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `into_the_manor` | 9-12 s | the warm safehouse, the walk to the manor door, ENTER THE MANOR, the cut to a dark foyer lit by one candle: the NIGHT 3 toast and how many relics are inside |
| 2 | `relic_grab` | 7-10 s | a relic glowing on its pedestal across a dark room, the walk to it, E: the relic is gone and the HUD's bag counts it |
| 3 | `it_sees_you` | 10-14 s | a red-eyed figure with a pale lamp walks into the next room, turns: IT SEES YOU; a run through a doorway, round a circuit, and it loses you |
| 4 | `servants_exit` | 8-11 s | the green lamp of the Servants' Exit through a doorway, the run to it, ESCAPE: YOU GOT OUT — night survived, relics banked |
| 5 | `ghost_through_wall` | 8-12 s | ⚠️ BATS INCOMING, a red ring at the player's feet, one step out of it, the bats sweeping through the wall and through the spot |
| 6 | `blood_moon_rises` | 9-12 s | back in the safehouse after night 25: THE BLOOD MOON RISES, the windows either side of the manor door turn to a huge red moon |
| 7 | `rest_by_the_fire` | 8-10 s | ☕ Rest pressed by the hearth: the avatar sits by the fire (and the sleeping cat, from hub level 12), the soft focus, the chip "Resting by the fire · the manor waits" |
| 8 | `nights_board` | 7-9 s | the NIGHTS SURVIVED board on the safehouse wall, F pressed, PUBLIC turns to FRIENDS |

### Staging, clip by clip

1. **`into_the_manor`.** Play two short nights first (in at the door, out at the Servants' Exit) so the HUD says
   night 3 honestly. Camera: the default third-person camera behind the character. Walk from the spawn pad straight
   south to the manor door (about 50 studs) and press E. Keep the take from the door's prompt to 3 s after the NIGHT
   toast. HUD on. No staging beyond the start position.
2. **`relic_grab`.** Any night. In the foyer, turn until a relic's glow shows through a doorway (relics glow; nothing
   else in the manor glows that colour), walk to it, press E once. HUD on: the bag count goes up. Real play.
3. **`it_sees_you`.** Public layout of night 12 (the switch above, before entering), played up to night 12 for the HUD.
   EYECANDY.md §12 shot 4's room (3000, 100, -360) is one room north of the foyer and off night 12's patrol: wait in
   its doorway until the Nightwatcher walks into a room you can see, step into its view. When IT SEES YOU shows, run
   back through the foyer and round: the Nightwatcher is never faster than the player (`Watcher.speed`, 0.65 of
   WalkSpeed), so a straight run gains ground. Retake if it catches you: the clip is the escape.
4. **`servants_exit`.** Any night, played from the foyer. The exit is always the deepest room, so this is a crossing;
   film the last two rooms: the green lamp through a doorway, the run, ESCAPE. The door opens only when you stand at
   it after a walk a person could have made (the crossing guard), which a played night always is. HUD on.
5. **`ghost_through_wall`.** Night 3, 4 or 5, played (the Quiet Night of nights 1-2 has no hazards; the Mist flies
   bats), with the interval note above (manifest). Stand still in a room the Nightwatcher is not in, away from its
   doorways: a hazard is held while it sees you. When the banner says ⚠️ BATS INCOMING, step 4 studs sideways out of the
   ring; the hit comes about 3 s after the warning, through the wall. A knock is a shove that costs nothing: retake
   freely. Flying crockery starts with the Thunderstorm (night 10) and the wraith with the Blood Moon (night 26): for
   those, the honest route is a session played that far (or the still, EYECANDY.md §12 shot 6).
6. **`blood_moon_rises`.** Honest only (the card and the chip are in frame): a session played to night 25, then the
   Servants' Exit. About 1.2 s into the day, after the server's YOU GOT OUT toast, the card THE BLOOD MOON RISES shows
   with a flash and an FOV punch. Camera from (3013, 109, 20) looking at (2988, 105, -28) (EYECANDY.md §12 shot 2): the
   two south windows either side of the manor door. The pacing model's first-time players reach night 26 after a
   median of 33.5 minutes of play (Pacing.spec, a bot): plan an evening, or skip this clip.
7. **`rest_by_the_fire`.** In the safehouse of a session that has bought a few upgrades (hub level 2 lights the hearth,
   6 adds an armchair, 12 the cat, 20 the whole haven; whatever the session earned). Stand on the spawn pad facing
   north, press ☕ Rest. Camera from (3000, 106.5, 7) looking at (3000, 104, 28). The chip changes to resting; keep it
   in frame. No lightning flashes while resting, so Reduced Motion does not matter here.
8. **`nights_board`.** Studio Local Server with 1 test player (no friends list), after at least one night survived.
   Walk to the east wall's NIGHTS SURVIVED board until the prompt shows (9 studs), press F once. Camera over the
   shoulder at about 12 studs, the board filling the upper two thirds. The friends view then says "No Roblox friends
   yet. Friends you add show up here, ranked against you." Film the public view only on a published place's Studio
   session with API access on (the real board), or leave it on the empty-board text.

### Captions that stay honest

- The Nightwatcher hunts you through the doorways, but it is **never faster than you**: say it costs you route and
  dread, not that it outruns you.
- There is **no audio** yet and no jumpscare model: no caption may promise sound or a scare beyond the red flash and
  shake when it catches you (CLAUDE.md, NOT built 3 and 4).
- The upgrades are visible props that change numbers (lantern reach, dread, the Nightwatcher's pace, the bell's
  warning, relic value, what you keep when caught). Traps do not fire in the manor: do not caption a bear trap
  catching anything.
- Every manor is laid out in secret and is the same size for everybody on that night; a retry is the same manor until
  the third failure, then it shifts. Do not say "infinite" or "hand-made" manors.
- The brag is the Blood Moon (night 26). The pacing model's first-time players got there after a median of 33.5
  minutes (a bot, not telemetry): say "within your first hour" at most.
- Ghosts never kill and never end a night: a hit is a stumble. Nothing costs Robux. The board ranks the best night
  the server saw you survive, earliest first on a tie.
