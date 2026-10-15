# Disaster Rounds: clip list

Eight short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is **vertical
1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer, HUD and
physics; never the emulator). `film_game.py` writes each clip's staging into `marketing/clips/manifest.json`.

Filming is the night shift's job (Studio 00:00-06:00, complete-game-standard §5). **Nothing here has been filmed, and
Disaster Rounds has never been opened in Studio** (`EYECANDY.md` §8). `tools/` belongs to the tools owner: every clip
needs a `DISASTER` scenario table added to `tools/film_game.py`, built from the helpers it already has (`teleport`,
`camera_behind`, `zoom`, `keys`, `orbit`, `restart_play`). The store text is in `README.md`; thumbnails are
`EYECANDY.md` §9.

## Rules for staging

`film_game.py` may place the character (a server-side teleport before recording), script the camera and pin its
distance. It never edits the game's numbers and never fakes progress the HUD then shows. So:

* **Every clip is the normal game.** No `Config.Shots`, no edited Config. A clip that needs a given disaster waits for
  it: each round is an even draw from the four kinds (REVIEW-1 F4), so a given kind comes within 3 rounds (4.4 min)
  with probability 0.58 (1 - (3/4)^3) and within 6 rounds with 0.82. Start recording at the stated second
  after the name (the HUD's phase chip counts the disaster down from 1:00).
* **A fresh Play is a fresh player.** The place is not published, so the DataStore is unavailable and every Play
  starts at 0 survivals, streak 0, Heat 0, band 1 (Calm Cove). The HUD is true in every clip below; keep it on.
* **Rings come for you.** Heat 0 aims a ring at you 5-11 s after the name and then every 6 s (Meteor Shower) or
  15 s (the others), +-20 %. A clip that wants rings starts after the first one.
* **Do not teleport during a round.** The movement guard sweeps out a counted player who moves more than 28 studs in a
  second ("Movement check failed"). Teleports are for the Lookout, between rounds.
* **Never film the Friends view with a real account's friends list**: it shows their Roblox usernames.
* Coordinates: the island is centred on the origin, 104 x 104 studs, cell tops at y = 0, 4, 8, 12, 16. The Lookout
  deck spans x -82..-62, z -18..18, floor at y = 28; `LookoutSpawn` is at (-74, 28.5, 0), facing +X (the island).

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `two_rings` | 12 s | Meteor Shower: two red rings land at the avatar's feet; two sidesteps; each meteor hits where it stood |
| 2 | `waters_rising` | 12 s | Flood: the first red line appears, the beach turns red, the avatar runs up two terraces, the water swallows the beach |
| 3 | `it_turned` | 10 s | Tornado: the red path bends toward the avatar; a sidestep at the last second; the funnel passes |
| 4 | `ground_gave_way` | 9 s | Earthquake: the avatar's cell cracks red; it steps to the next cell as the old one drops in chunks into the sea |
| 5 | `jump_in` | 10 s | back from a break mid-round: tap ▶ Jump in, land on the island, the first ring arrives |
| 6 | `survived` | 8 s | the last 5 s of a round, then SURVIVED! with confetti, the flash and the streak |
| 7 | `swept_away` | 7 s | stand still in a ring: the hit, the flash, the avatar back on the Lookout, "Streak lost" |
| 8 | `sky_changes` | 12 s | a fresh profile's second survival: the card, and the sky gliding from Calm Cove to Windy Point |

### Staging, clip by clip

1. **`two_rings`**. Fresh Play; wait for a Meteor Shower. Start recording at second 5 after the name (the first ring is
   due 5-11 s in, then every 6 s +-20 %, so 12 s holds two). On each ring, take one or two steps out of the red (it is
   9 studs across; one step of 4.5 studs from its centre always escapes). Camera behind and above at 14 studs, pitched
   down so the ring and the falling meteor share the frame. HUD on.
2. **`waters_rising`**. Fresh Play; wait for a Flood. Before the name, walk to a beach cell (level 0, sand or pebble at
   the shore). Record from second 2: the red line and the red beach appear at second 3, the water starts at second 12
   and covers the beach at 14. Walk up two terraces (level 0 -> 2; each is a 4-stud jump) and turn the camera so the
   water rising over the red beach is behind the avatar. Camera 18 studs behind, a little above.
3. **`it_turned`**. Fresh Play, solo; wait for a Tornado. Stand in the open on a level-1 or level-2 cell. Half the
   funnel's targets are a player, and solo that is you: record from the moment the red path turns toward you, step
   sideways off the red when its edge is about one stud away, and keep recording as the funnel passes. Camera 2 studs
   up, 12 behind, facing the funnel. If the path does not turn toward you this round, try the next tornado.
4. **`ground_gave_way`**. Fresh Play; wait for an Earthquake. Record from second 2: at second 3 the first batch
   cracks; with one player there is a 60 % chance it includes your own cell. When your cell turns red, step to an
   intact neighbour (every red cell has one, at most one level away) and turn to watch the old one drop at second 6.
   If your cell is not in the first batch, the next comes at second 9.
5. **`jump_in`**. Fresh Play. In the intermission tap ☕ (a break: you are not dropped). When the island appears, tap
   ☕ again ("Back in!"), then ▶ **Jump in (practice)** under the phase chip. Record from the tap: you land in about a
   second and the first ring arrives 5-11 s after landing (Meteor Shower) or 5-20 s (the others). Say "back from a
   break" in the manifest, not "joined mid-round". The card says the practice round won't count; that is true.
6. **`survived`**. Any round you are still in at 0:05: record the last 5 s, the SURVIVED! card ("🔥 streak 1"), the
   gold, white and teal confetti and the white flash. Camera 14 studs behind, slightly above.
7. **`swept_away`**. Fresh Play; a Meteor Shower. Stand still when the first ring lands under you: the meteor hits,
   the blue flash, the card "💥 Hit by a meteor", and you are on the Lookout deck facing the island. Record 2 s before
   the impact. The streak was 0 on a fresh profile, so the card reads "Streak lost" on a streak of nothing: film it
   after `survived` in the same Play if you want a streak to lose.
8. **`sky_changes`**. Fresh Play: survive two rounds (about 3 minutes, `tests/Pacing.spec`: 3.3 min median for a normal
   player). Record the end of the second: SURVIVED! and, in the 4 s outro on the island, the "🌬️ WINDY POINT" card
   and the light gliding from morning to midday over 2-3 s; then the move back to the deck. Camera high behind the
   avatar, looking out over the island and the sea.

## Not clips (until real play reaches them)

MAX HEAT (a streak of 10, 28.4 min median for a normal player) and the Falling Sky (21 survivals, 35.1 min) need real
survivals: they are thumbnails (`EYECANDY.md` §9, staged with a hand-set band and the HUD hidden), not clips, until the
night shift's own play gets there. A clip of either must never use a hand-set `Survived`.
