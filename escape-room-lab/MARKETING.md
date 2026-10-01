# Escape Room Lab — clip list

Eight short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real
renderer, HUD and physics; never the emulator). Filming is the night shift's job (Studio 00:00-06:00).
`tools/` belongs to its owner: every clip below is **new** and needs a scenario (an `ESCAPE` table next to
`PLUS1` in `film_game.py`). Nothing has been filmed.

## Rules for staging

A scenario may place the character (a server-side teleport), script the camera, and pick the room with
`Config.Studio.StartSlot` in the unsaved Studio copy (honoured only in Studio with API access off, so it can
never touch a real profile). It never edits a game number for a clip and never fakes progress the HUD shows.
The hazard clip (2) waits for a natural hazard: one comes within 120 s of time spent standing on a legal spot
from the Archive on (one per 100.8 s on average; never at the door keypad, within 5 studs of a doorway or in a
room's first 8 s: `EYECANDY.md` §3); film a long take and cut.

Never film the Friends view with a real account's friends list visible: it shows their usernames. Use a
Studio test player (no friends: the board then says "Couldn't load your friends list..." or, on a live
server with no friends, "Add friends on Roblox to compare stars here...") or blur it.

Room-local coordinates as in `EYECANDY.md` §9: add the room's origin (zone 1 is (300, 0, 0)).

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `last_digit` | 8 s | the keypad, the final digit, ENTER: the door rises, `ESCAPED ★★★`, a white flash and the FOV punch |
| 2 | `spider_drop` | 7 s | the banner `⚠ SPIDER - STEP OUT OF THE RING`, the red ring at the feet, a step out, `CLEAR`, the spider lowering into the empty ring |
| 3 | `three_taps` | 10 s | a 3x3 lamp grid solved in three taps, the lamps glow, `LAMP GRID A solved! Door line N is lit.` |
| 4 | `which_order` | 12 s | four clue sentences on screen for 4 s, two swaps, TEST, the shelf turns green |
| 5 | `wing_changes` | 12 s | the last Archive room: the shelf solved, greenhouse light seeping in, the door opens as the Greenhouse arrives |
| 6 | `pair_up` | 12 s | two players on the Pair Lift pads, both press GO, the countdown; in the room one reads, the other taps |
| 7 | `roof` | 10 s | the lift from room 15 opens on the Roof at night: `YOU ESCAPED THE LAB`, three fireworks, the lit city |
| 8 | `crack_this` | 15 s | a still door board with four lit lines for 8 s (a caption asks the viewer), then the code is entered |

### Staging, clip by clip

1. **`last_digit`**: any room with its feeders solved (StartSlot 1 is quickest: solve the 3x3 grid off
   camera). Character at (0, 0, -12) facing the door; camera over the shoulder at (3, 6, -6) looking at
   (0, 5, -16), so the overlay's keypad and the rising door share the frame. Record from the third digit.
2. **`spider_drop`**: StartSlot 4 (the Archive). Stand at the room's centre (0, 0, 0) with no overlay open and
   wait; camera at (6, 6, 8) looking at (0, 3, 0), so the ring on the floor and the ceiling are both in view.
   When the banner appears, wait about 1 s so the spider is in frame, then walk 4 studs out of the ring (it
   stands still from its first frame since REVIEW-1; the spider reaches head height 2.1 s after it appears).
3. **`three_taps`**: StartSlot 3 (Reception room 3: a 3x3 grid needing exactly 3 presses). Character at
   (-12, 0, 0), overlay open; camera behind the character looking at the west wall so the world's lamps and
   the overlay's lamps light together.
4. **`which_order`**: StartSlot 4 (Archive room 1: a 4-flask shelf, feeder A on the west wall). Character at
   (-12, 0, 0), overlay open on the Flask Shelf; hold on the clue list for 4 s, then the swaps. Portrait framing keeps the clue list legible.
5. **`wing_changes`**: StartSlot 6 (the Archive's last room). Solve the shelf on camera, then the door: the
   greenhouse light and decor fade in with the shelf solve (about half way, `EYECANDY.md` §2) and are fully
   there when the door opens. Camera fixed at (0, 7, 10) looking at (0, 8, -10), wide.
6. **`pair_up`**: two Studio clients (Local Server, 2 players). Both on the pads at (5, 0, -3) and (11, 0, -3),
   both press GO; film the countdown from (8, 6, 6), then cut to the room: one at the door board, one at the
   station. Needs the Studio two-client check first (`EYECANDY.md` §8 item 10).
7. **`roof`**: StartSlot 15. Solve room 15 off camera, step into the exit lift, press "Up to the Roof", and
   record from the lift doors: the arrival at (0, 153.5, 8) facing -Z, the card, the fireworks at
   (-10..10, 184, -40). Camera behind and above the character.
8. **`crack_this`**: any 3-digit door after its feeders are solved, with 4 lines on the board (reroll the room
   with ATRIUM and the Solo Lift until one has 4). Frame the board alone for 8 s with a caption
   ("Can you crack it? 3 digits, none repeat"), then show the code entered.
