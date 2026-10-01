# Lost & Found Depot — clip list

Eight short gameplay moments for `tools/film_game.py` (`docs/complete-game-standard.md` §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer,
HUD and physics; never the emulator). `film_game.py` records the vertical strip and encodes it at 1080x1920; each
clip's staging goes into `marketing/clips/manifest.json`.

Filming is the night shift's job (Studio 00:00-06:00, `docs/complete-game-standard.md` §5). This file says what to
film and how to stage it. `tools/` belongs to the tools owner: `film_game.py` has no scenarios for this game yet
(its `GAMES` are `plus1`, `crystal` and `laby`), so **every clip below is new** and needs a `DEPOT` scenario table
added there. Nothing here has been filmed, and the game has never been opened in Studio (`CLAUDE.md`).

## Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera, and redeem the public code
(`SORTED`). It never edits the game's numbers and never fakes progress the HUD then shows. For this game that means:

* **Clips with the HUD or the wing panel on screen need a save that really got there.** The wing you are in, the
  career shift, cash, carry and the board all come from the profile. A regular sorter reaches the airport after
  about 8.5 minutes of play, the train station after 16.6, the theme park after 24.6 and the space station after
  35.1 (`tests/Pacing.spec.luau`, a model, not telemetry). Play those shifts in an earlier session on the test
  account used for filming, as +1 Jump's `rebirth_prestige` clip does.
* **Scenery-only clips** (both `DepotHud` and `DepotWings` hidden, so nothing on screen claims any progress) may use
  the single-wing shots place from `EYECANDY.md` §9 steps 1-5 (a place built from the source, Config edited in that
  place only, API access OFF so no save is touched).
* **The hazard clip may shorten the wait** between hazards to 8-10 s of running clock (`EYECANDY.md` §9 step 3).
  That changes how often a hazard comes, nothing the player sees about one. **Say so in the manifest's staging list:**
  a normal sorter meets one every 2-3 minutes (`Pacing.spec`: one near-miss per 2.7 min).
* **Never film the board's Friends view with a real account's friends list:** it shows their Roblox usernames.
  Use a Studio Local Server test player (no friends: the board then says what an empty friends board says).
* **Never film the Back Room.** The note behind the door is the game's one secret (`src/server/Secret.luau` never
  replicates); a clip of it would publish it.

Bay_1 (play solo, or the first player of a Local Server) is centred at **x = 100**: floor top y = 0, back wall
z = -36, front wall z = 20, the spawn pad at (100, 0.5, 14), the tray at z 3.5-9.5, the pick point at (100, 3, 0),
the six bins on an arc of radius 28 toward -Z, the locker at (112, 3, 16), the Top Sorters board on the front wall at
(86, 6, 19.8) facing -Z. The bins are reshuffled around the arc every shift: find a bin by its sign
(`Bay_1.Bin_k.Sign.SignGui.Label.Text`), never by its number.

## The clips

| # | clip | length | what the viewer sees | needs |
|---|---|---|---|---|
| 1 | `depot_first_sort` | 9-12 s | a new sorter taps the Teddy Bear on the tray, walks it to TOYS, Drop: `+11`, the FILED stamp | a fresh career |
| 2 | `trust_the_tag` | 8-10 s | close on the tray: a teddy bear whose tag says `E` (ELECTRONICS); it goes in ELECTRONICS, not TOYS | any shift, HUD on |
| 3 | `wrong_bin` | 8-10 s | a deliberate wrong bin: `-8 s. <item>: <letter> goes to <BIN>.`, the item back on the tray marked MISFILED | any shift, HUD on |
| 4 | `space_arrival` | 9-12 s | the last sort of the 13th shift; the summary closes; `YOU MADE IT TO SPACE!`, the white flash, the Earth over the back wall | a save with 12 real shifts done |
| 5 | `runaway_trolley` | 8-12 s | the warning, the red ring and lane, one step out of the ring, the trolley rolling through where the sorter stood | a save with 3+ real shifts; the shortened wait |
| 6 | `last_train` | 10-12 s | the train station at golden hour: the iron-and-glass shed, the station clock over the bins, the train crossing the viaduct, steam, pigeons | scenery only |
| 7 | `board_toggle` | 7-9 s | at the spawn: the TOP SORTERS board, a few steps to it, E pressed, EVERYONE turns to FRIENDS | a Local Server test player |
| 8 | `break_at_the_park` | 8-10 s | a shift ends at the theme park at dusk; BREAK; the sorter sits, the depth blur comes in, bulbs and the ferris wheel turning | a save with 9+ real shifts |

### Staging, clip by clip

1. **`depot_first_sort`.** Studio API access OFF (the session plays read-only with a fresh career: shift 1, the
   tutorial). Fresh Play; the character lands on the pad facing -Z. Camera over the shoulder, 14 studs behind and
   8 up, pitched down about 20 degrees so the tray's tags and the TOYS sign are both in frame. Tap the Teddy Bear
   (the hint says which; `TAP HERE` floats over it), walk to the bin marked `DROP HERE`, tap Drop. Keep the take
   from the tap to the `+11` toast and the FILED stamp. Do not take the Phone too: one item reads better in 10 s.
2. **`trust_the_tag`.** The hook of the game. The tag's letter is drawn without looking at the item, so it
   disagrees with what the item looks like three times in four, so nearly every tray has one: pick an item whose
   look says one bin and whose tag says another (a Teddy Bear, Rubber Duck or Laptop reads best; read
   `Slot_k.Tag.TagLine.Text` against `Config.Catalog`), on a tag that is not torn and not RED or condition 5, so
   the letter alone decides. Career shift 1 is the tutorial (no Teddy Bear or Phone in its draw), so film from
   shift 2 on. Camera close and low over the tray, the tag and the item both readable in the vertical frame; pick it,
   walk to the bin the TAG names, Drop, `+` toast. Caption idea: "Trust the tag, not the item."
3. **`wrong_bin`.** Same set-up; take an item to the bin its LOOKS suggest when the tag says otherwise. In frame:
   the toast `-8 s. ...` naming the item and the right bin, the clock dropping 8 s, the item back on the tray with
   its tag reading `MISFILED - goes to <BIN>`. Nothing is staged: the penalty is the game's own.
4. **`space_arrival`.** Needs a save that really completed 12 shifts (the 13th is the one that names the space
   station; about 35 minutes of play for a regular, `Pacing.spec`). Play the 13th shift off camera to its last
   item, start recording, sort the last item, close the summary card: the card `YOU MADE IT TO SPACE!` with the
   flash and the FOV punch plays once, over the station's dome ribs and the Earth with its airglow. Camera low near
   the pad at (100, 6, 16) looking at (160, 70, -400), as thumbnail 1 in `EYECANDY.md` §9. The wing blends in over
   the last third of shift 13, so the dome is already fading in before the card.
5. **`runaway_trolley`.** A save with at least 3 real shifts (the airport, where hazards begin: owner decision (b),
   `EYECANDY.md` §14). In the session only: `Config.Hazards.IntervalMin = 8`, `IntervalMax = 10` (the shortened
   wait; write it in the manifest). Hazards run only on the RUNNING shift clock: pick an item up first. Camera
   side-on and low, about 15 studs to the sorter's side, HUD on (the warning banner and `MOVE!` are the point). When
   the ring and lane turn red, step sideways out of the ring with a thumbstick-length step; keep the take where the
   trolley rolls through the empty ring. If it touches the sorter, they only stumble: keep that take as a spare,
   it is honest too.
6. **`last_train`.** Scenery only: the single-wing shots place with TRAIN STATION at `from = 0, fade = 0`
   (`EYECANDY.md` §9 step 3), `DepotHud` and `DepotWings` hidden (step 5). Camera at the pick point, low, (110, 5,
   10), looking up at (95, 30, -60), a slow 6-degree pan right over 11 s. The train crosses every 30 s: start
   recording 3 s before it enters the frame. The station clock's minute hand really runs (a lap a minute).
7. **`board_toggle`.** Studio Local Server, one test player (no friends list). Fresh Play. The board hangs on the
   wall behind the spawn pad: turn round, it is on your right (the locker is on your left). Walk about 14 studs to
   stand a few studs in front of it (the prompt shows within 8 studs of it, never from the pad), press E once. Camera over the shoulder at 14 studs, the board filling the upper two
   thirds. In a fresh place the public board reads `No Perfect Shifts on the board yet...`; the friends view then
   says `No Roblox friends yet...`. Either film that honestly, or film in the published place's Studio session with
   API access on, where the real public top 10 shows (usernames of real players: check that this is acceptable
   before publishing the clip, or blur the rows).
8. **`break_at_the_park`.** A save with at least 9 real shifts (the theme park, about 25 minutes for a regular).
   Finish a shift off camera to its last item; start recording; sort the last item; press BREAK while the summary is
   up (between shifts the break starts at once; pressed mid-shift it is booked for the shift's end). The sorter sits
   on the bay floor, the far scenery blurs, the bulbs over the bay and the ferris wheel keep turning. Camera behind
   and above, 18 studs, the wheel over the back-left wall in frame. End the take on `BACK TO WORK` or the first step.

### Captions that stay honest

The space station is "about 35 minutes in" (the pacing model's 35.1 min for a regular sorter, not telemetry); the
galaxy beyond it is the long goal (94.2 min in the same model). A hazard only makes you stumble: nothing is lost,
dropped or recorded, and stepping out of the red ring always dodges. The board ranks Perfect Shifts (all 30 sorted,
at most 3 wrong bins, before the clock) that the server saw walked at the speed your shoes allow, earliest first on
a tie; a teleport or a speed hack does not put anyone on it. Nothing in the game costs Robux. `SORTED` is the one
public code (+250 cash).
