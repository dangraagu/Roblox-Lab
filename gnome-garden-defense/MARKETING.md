# Gnome Garden Defense: clip list

Eight short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real
renderer, HUD and physics; never the emulator). Filming is the night shift's job (Studio 00:00-06:00). This file
says what to film and how to stage it. `tools/` belongs to the tools owner: every scenario below is **new** and
needs adding to `tools/film_game.py` as a `GNOME` game entry (none exists yet).

## Rules for staging

`film_game.py` may place the character (a server-side teleport onto the player's own deck), script the camera,
and press the HUD's own buttons. It never edits the game's numbers and never fakes progress the HUD then shows.

**The camera belongs to the game's garden view** (`src/client/View.client.luau`, REVIEW-1): it frames the whole
garden, zooms where a pad is tapped, zooms on the gardener during a hazard and looks up at the moon for the brag.
A clip that scripts its own camera must first set the camera attribute `ExternalCamera = true` (the view then
stands down until it is cleared; check_gnomegardendefense_reach section 9), or the view takes the camera back
every frame. Clips 1, 3 and 4 are best filmed THROUGH the garden view, as a player sees them.

**Progress that a clip shows must have been earned under the real rules.** Two honest ways to get a garden to a
late wave: (1) a long human session, or (2) a scripted gardener that plays THROUGH THE REAL REMOTES (Plant,
Upgrade, Ready), like `robloxemu/check_gnomegardendefense.luau`'s bot or the strong profile in
`tests/GardenModel.luau`: the server's simulation still decides every wave. Measured times to reach a wave for a
strong player (tests/BandMinutes.luau): wave 10 at 7.2 min, wave 30 at 26.6 min, wave 50 at 50.5 min of play.
Never set `Progress`, `Wave`, `Seeds` or the saved chapter by hand for a clip.

Never film the Friends view with a real account's friends visible (it shows usernames). Use a Studio Local Server
test player (no friends: the board then says "No Roblox friends yet...") or blur it.

## The clips

| # | clip | length | what is in frame | how to stage it |
|---|---|---|---|---|
| 1 | **First gnome pops up** | 8 s | a fresh bed at spring dawn (dandelion fluff drifting), three pads pulsing, a tap, the view zooming in on that pad, a second tap turning it gold, the gnome sheet with ★ Pebble, the soil puff, seeds 120 -> 70 | `fresh`, a new profile. Camera: the garden view as it is (no ExternalCamera). Record from the join; tap a glowing pad 2 s in, tap it again in the zoom (REVIEW-2: on a phone the first tap only zooms; the core action lands at 4.0 s in tests/walk.luau), then Slot1 |
| 2 | **The Stag Beetle stopped on the last tile** | 12 s | wave 10, boss bar in the top bar, the Stag a few tiles from the carrots, pebbles firing (tools flash), the boss falls, "SPRING WON", the season turning to summer | scripted gardener plays spring (about 7-9 min); start recording when the BossFrac attribute drops below 0.35. Camera low over the carrot patch, looking back up the path |
| 3 | **The Slug Queen falls under the Harvest Moon** (the brag) | 15 s | the moon rising through her fight, lanterns lit, her health bar emptying, the flash, "HARVEST MOON / The Slug Queen falls!", golden burst, the view tilting up to the moon | scripted gardener (strong profile) to wave 30 (~27 min). Start recording at BossFrac 0.5. Camera: the garden view as it is (it looks up at the moon by itself for 4.5 s) |
| 4 | **An acorn, dodged** | 8 s | the red ring at the gardener's feet, the ACORN banner, the gardener steps out after the ring turns red, the acorn lands in the empty ring | any garden in Blossom Morning or High Summer during a build phase; wait for a hazard (one per 100-150 s of garden time). Camera: the garden view as it is (it zooms on the gardener while the hazard is live). Walk 5 studs sideways 1.8 s after the warning |
| 5 | **Sprinkler + mushroom combo** | 10 s | a wasp swarm (wave 12+) slowed by a level-3 sprinkler into a level-3 mushroom's splash, three wasps popping at once with green sparkles | a summer garden with a sprinkler and a mushroom on neighbouring pads beside a bend; camera 12 studs above the bend looking down |
| 6 | **READY under the aurora** | 10 s | wave 49 on the Moonlit Bed, aurora beams, snowdrifts, a full 14-gnome bed, READY pressed, the wave pours through the hedge gap | strong scripted gardener to wave 49 on the day's endless bed (~49 min); record the press. Camera: thumbnail shot 4's angle |
| 7 | **The season turns during a boss fight** | 12 s | wave 20, the Snail Baron losing ground while the light turns from summer shower to harvest gold, falling leaves arriving | scripted gardener to wave 20 (~17 min); record from BossFrac 0.8 to his fall. Camera: wide from the south hedge |
| 8 | **Who's the best gardener?** | 8 s | the board on the deck's west end at dusk, the prompt, PUBLIC -> FRIENDS, the empty-friends message | any garden in the Snowfall band; walk the character to the board (the garden view turns to read it within 12 studs), press E |

Hashtag/caption guidance for each post: name what is on screen ("the Slug Queen falls"), say the game is free
and has no pay-to-win, and label it AI-assisted where the community's rules ask for that (docs/reddit).
