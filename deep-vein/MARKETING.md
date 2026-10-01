# Deep Vein: clip list

Nine short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer,
HUD and physics; never the emulator). `film_game.py` records the vertical strip and encodes it at 1080x1920, and
writes each clip's staging into `marketing/clips/manifest.json`.

Filming is the night shift's job (Studio 00:00-06:00, complete-game-standard §5). Nothing here has been filmed, and
Deep Vein has never been opened in Studio (`EYECANDY.md` §9). `tools/` belongs to the tools owner: every clip below
is **new** and needs a `DEEP` scenario table added to `tools/film_game.py`, built from the helpers that file already
has (`teleport`, `camera_behind`, `zoom`, `keys`, `orbit`, `restart_play`). The store text is in `README.md`.

## Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera and pin its distance. It never
edits the game's numbers and never fakes progress the HUD then shows.

* **A fresh Play is a fresh miner.** Deep Vein was never published, so Studio has no DataStore: the server warns
  `datastore unavailable` and every Play starts from `defaultProfile()` (rebirth 0, $0, the Rusty Pick) in a cave
  drawn from a fresh key. Clips 1, 2, 8 and 9 use that, unedited.
* **Deep clips use the shots place**, exactly as `EYECANDY.md` §10 steps 1-4 build it: `rojo build -o
  DeepVein-shots.rbxlx` (git-ignored), then in THAT place only `drawKey()` returns `Mine.legacyKey(Config, 12)` and
  `defaultProfile()` starts at `pickTier = 5, backpackLevel = 12, lampLevel = 8, rebirths = 12` plus the clip's
  `depthLayer` / `bestLayer`. That is a deep profile, so **hide the HUD** in those clips (`DeepVeinHud.Enabled =
  false`; the cash, the rebirth count and the best depth would be the edited profile's) unless the clip says why it
  is shown, and say "shots place" in the manifest's staging list. Never edit `src/`.
* **Hazard timing** (clip 5 only): in the shots place's `ReplicatedStorage.Config`, `Hazards.IntervalMin = 8`,
  `Hazards.IntervalMax = 10`, `Rest.IdleSeconds = 0`. This shortens the wait for filming; a normal miner meets one
  hazard every 2.5-2.8 min (`check_deepvein_rarity`). Say so in the manifest.
* **Never film the Friends view with a real account's friends list on it**: it shows their Roblox usernames. Use a
  Studio Local Server test player (no friends: the board then says what an empty friends board says).
* Coordinates are shaft 0's (the first player in the server; its mouth is centred on the origin). Layer `L`'s floor
  is at `y = -6L`; the mouth floor is `y = 0`; the walls' inner faces are at x, z = +-21.

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `first_swing` | 8-10 s | a fresh miner at the mouth swings at the floor; the block shrinks, breaks, copper drops in the bag |
| 2 | `bag_to_cash` | 9-12 s | a full bag, SURFACE + SELL: back at the mouth, the haul sold, the cash counter jumps; a pickaxe bought |
| 3 | `cave_breakthrough` | 8-11 s | one swing breaks into a hidden cave and the whole void opens at once |
| 4 | `magma_fanfare` | 9-12 s | the first stand in layer 40: "YOU REACHED THE MAGMA!", the orange flash, the FOV punch |
| 5 | `hazard_dodge` | 8-12 s | the ring at your feet, MOVE!, one step into the next cell, the crystal drops into the empty ring |
| 6 | `strata_ride` | 10-14 s | DESCEND from the surface: the light and the rock glide through the strata on the way down |
| 7 | `core_orbit` | 10-12 s | a slow orbit over the glowing, cracked core floor at the bottom of the shaft |
| 8 | `board_toggle` | 7-9 s | the Deepest Miners board on the mouth's south wall, E pressed, PUBLIC turns to FRIENDS |
| 9 | `rest_lantern` | 7-9 s | Rest tapped: the miner sits, a lantern lights beside them, the cave goes quiet |

### Staging, clip by clip

1. **`first_swing`**. Fresh Play. The character spawns at (0, 4, -18) facing south (the board is on the far wall).
   Walk two cells south, past the green SELL pad, and click the floor block centred at (0, -3, -6) until it breaks
   (the Rusty Pick takes a few swings, and the block visibly shrinks with each). Camera behind
   and above, distance pinned at 16, pitched down so the block is mid-frame. HUD on (a fresh profile's HUD is true).
   If the first block holds no ore, take the next one; copper is common in layer 1.
2. **`bag_to_cash`**. Fresh Play, then dig the mouth floor and the layer below by hand until the HUD's bag bar is
   red (full), off camera. Start recording with the miner in their hole: press SURFACE + SELL (the miner lands at
   the mouth, the "Sold your haul" toast, the cash counter moves), open the shop, buy the Steel Pick ("Upgraded!").
   HUD on: every number on it was earned in this session. Camera behind, 18 studs.
3. **`cave_breakthrough`**. Shots place, `depthLayer = 35, bestLayer = 35`, HUD hidden. DESCEND lands at
   (0, -206, 0). Dig straight down at x = z = 0: breaking layer 36 opens a natural cave around the miner (72 cells,
   layers 34-40; checked on the generator for `EYECANDY.md` §10 shot 4). Record from the swing before it. Camera
   pinned at 14 studs, behind and level, so the void opens past the miner.
4. **`magma_fanfare`**. Same place and profile as clip 3, but **HUD ON**: the card lives in `DeepVeinCave`, and the
   flash is the point (the HUD's numbers are the shots place's; say so in the manifest). Continue down the column
   through 37, 38, 39 and 40. The first moment the miner STANDS in layer 40 plays the card, the flash and the FOV
   punch, once per session: record the first try. Run clip 3 and this clip in one take if possible.
5. **`hazard_dodge`**. `EYECANDY.md` §10 shot 5, verbatim: shots place, `depthLayer = 54, bestLayer = 54`, the hazard
   timing above, the two-layer room dug at (0, -315, 6) and (0, -315, 12), the miner at (0, -320, 12) facing south.
   HUD on (the warning banner is the point; the HUD's numbers are the shots place's, say so). When the rim turns
   red and the banner says MOVE!, walk one cell south to (0, -320, 18). Keep the take where the crystal drops into
   the empty ring.
6. **`strata_ride`**. Shots place, `depthLayer = 46, bestLayer = 46`, HUD hidden. From the mouth, press DESCEND
   (from the command bar: `game.ReplicatedStorage.VeinRemotes.Elevator:FireServer("down")`, or unhide the HUD for
   the press and hide it again). The ride lands at (0, -272, 0); the client glides the light and air through
   topsoil, stone, iron, river, grotto and magma on the way. Camera: pinned at 12 studs, looking down past the
   miner. Record from just before the press to two seconds after landing.
7. **`core_orbit`**. `EYECANDY.md` §10 shot 6: shots place, `depthLayer = 168, bestLayer = 168`, HUD hidden, DESCEND
   to the bedrock floor (y -1008), dig the plus around the column. Scripted orbit (`orbit` in `film_game.py`)
   centred on (0, -1004, 0), radius 10, from y -996 to -1000, about 10 s, looking at the miner on the orange floor.
8. **`board_toggle`**. Fresh Play as a Local Server test player (no friends). Walk from the spawn to the mouth's
   south row (0, 4, 12): the prompt "Public / Friends" appears at the foot of the board (16-stud reach). Press E.
   The board turns from PUBLIC ("Nobody is on the board yet...", Studio has no store) to FRIENDS ("No Roblox friends
   yet..."). Camera behind the miner, 14 studs, so the whole board (22 x 12 studs) is in frame. This clip shows the
   empty states, and the manifest must say so; a populated board needs the published game.
9. **`rest_lantern`**. Any Play (fresh is fine), HUD on. Stand still in a dug cell, tap the Rest button: the miner
   sits and the lantern lights beside them. Camera behind, 12 studs.

## Not clips

* **Rebirth.** A rebirth has to be earned (the gate is this run's earnings, 7-15 minutes of normal digging at rebirth 0
  over eight caves, `tests/Pacing.spec.luau`), and a shots-place profile that starts with the earnings would be faked
  progress. Film it only at the end of a real session that earned it.
* **Thumbnails** are stills, 1920x1080, and their own list: `EYECANDY.md` §10.
