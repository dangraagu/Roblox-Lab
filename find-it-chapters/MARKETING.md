# Find It! Chapters: clip list

Eight short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (the real renderer, HUD and physics;
never the emulator). Filming is the night shift's job (Studio 00:00-06:00). `tools/` belongs to its owner: every
clip below is **new** and needs a scenario (a `FINDIT` table next to the others in `film_game.py`). Nothing has
been filmed, and the game has never been opened in Studio.

## Rules for staging

A clip never fakes a find, a clock or a count the HUD shows. Staging happens only in the **Studio shot room**:
when `RunService:IsStudio()` is true and saving is off (API access off), `Config.Studio.ShotSeed` makes the
dressing and the secret repeatable (so a take can be framed twice) and `Config.Studio.Cleared` unlocks chapters
(so later bands can be filmed). Neither is honoured in a live server (`check_finditchapters` asserts both), and
nothing is saved or ranked in the shot room. A scenario may place the character with a server-side move, script
the camera and tap props through the real HUD (the player taps; the server answers). With a fixed ShotSeed the
filmer knows where things are by searching once off camera, then re-runs the take.

Never film the Friends view with a real account's friends list visible: it shows their names. Use a Studio test
player (no friends: the board says "None of your friends has solved a case yet. Invite one: ...") or blur it.

Room-local coordinates as in `EYECANDY.md` §9: the door mat's centre is (0, 0, 0), the room runs +z, lane 1's origin
is (-385, 0, -240). A chapter's room size is in `Config.Chapters`.

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `four_seconds_left` | 9 s | the clock at 0:06, the last chip, a walk, two taps, the 1-second wait, the gold burst, `CHAPTER CLEARED!` with three stars and the FOV punch |
| 2 | `read_the_clue` | 12 s | a chip tapped: the callout `Tiny Planet hides in something YELLOW up HIGH`; the camera pans along the shelves; two taps on a yellow jar up high; found |
| 3 | `wrong_one` | 10 s | the chip `a BLUE BOX`; a tap on a BLUE BASKET: a grey tick and `That BLUE BASKET doesn't fit any clue you still need`; then the right box, gold |
| 4 | `step_out` | 8 s | in the library a book wobbles under the ceiling, the red ring at the feet, the banner `STEP OUT OF THE RING`; a sidestep; the book lands in the empty ring; `BOOK - CLEAR` |
| 5 | `pause` | 10 s | the Pause button: the room dims, the card says the clock is stopped and things get moved; Resume: every prop in a new place, the looks unchanged |
| 6 | `book_one_solved` | 12 s | the observatory's last find: `BOOK ONE SOLVED - You found all 93 things`, the dome slit opening, gold shooting stars, the flash |
| 7 | `daily_case` | 10 s | the hub: the Daily door with `Case #N`, opened; a fast room; then the board, its prompt flipping Public to Friends |
| 8 | `ship_storm` | 9 s | the Ship's Cabin at night: rain running down a porthole, a fish crossing it, a lightning flash lighting the porthole white; the camera pulls back to the lantern-lit cabin and a crate wobbling under the ceiling |

### Staging, clip by clip

1. **`four_seconds_left`**: ShotSeed set, chapter 2 (`Cleared` 1). Find all but one item off camera, keeping the
   last one's prop 6 studs from the player; wait until the clock shows 0:06; record the walk, the two taps and the
   clear card. Camera over the shoulder at (3, 7, -4) relative to the player, looking at the prop. In the shot
   room the first clear shows "Cases Solved: N" for the session only (nothing is saved there).
2. **`read_the_clue`**: `Cleared` 12, chapter 13 (a CH clue is likely; with ShotSeed set, pick a seed whose list
   has a "something YELLOW up HIGH" chip). Tap the chip (the callout), then pan the camera along the east wall's
   shelves at y 8 and tap the yellow prop twice. Portrait framing keeps the callout legible.
3. **`wrong_one`**: chapter 3 or later (`CK` clues and partial-match decoys: about 30% of the fillers). A seed with
   a "a BLUE BOX" chip and a blue basket nearby; tap the basket twice first (the off-clue answer), then a blue box.
4. **`step_out`**: `Cleared` 3, chapter 4 (the library). Stand on a legal spot (the room's centre, more than 4 studs
   from the door mat) and wait: a drop comes 90-125 s after arrival (`EYECANDY.md` §3). Camera at (6, 9, 8) from
   the player, looking at the feet and the ceiling. Step 4 studs out within 2 s of the banner.
5. **`pause`**: any chapter after its intro; press Pause from the HUD (top right), hold 4 s on the card, press
   Resume (it lands 3 s after the Pause at the earliest). Camera fixed and wide, so the props moving is visible.
6. **`book_one_solved`**: `Cleared` 14, chapter 15 with ShotSeed set; find all but one item off camera, then film
   the last find. The server notice and the gold name tag appear too (the profile is not saved in the shot room).
7. **`daily_case`**: `Cleared` 3 (the Daily opens after chapter 3). Film the door's sign, the prompt, a short
   solved room (cut), then walk to the board and press its prompt twice (Friends, then Public).
8. **`ship_storm`**: `Cleared` 9, chapter 10 (the Ship's Cabin, 48 x 38). Camera close on the east porthole nearest
   the door: at room-local (21, 12.4, 11.4) looking +x, held until a flash (one every 6-11 s, 0.12 s long:
   take the longest run of the recording that contains one), then a slow pull back to (0, 7, 4) looking at the room.
   The rain and the fish live between the porthole's view and its glass (`RoomArt` portholes): whether they read on
   camera is `EYECANDY.md` §8 item 26; if they do not, cut the clip rather than fake it.

## Where to post (after the game is live)

Marketing starts only after the night shift has checked §8 of `EYECANDY.md`, published, and set the experience
public: spread over a day and the next, one game at a time, in communities whose rules allow self-promotion,
labelled as AI-assisted (docs/complete-game-standard.md §5).
