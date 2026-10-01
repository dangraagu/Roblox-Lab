# Steal a Cryptid: clip list

Ten short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is
**vertical 1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (`--source capture`: the real renderer,
HUD and physics; never the emulator). `film_game.py` records the vertical strip, encodes it at 1080x1920 and writes
each clip's staging into `marketing/clips/manifest.json`.

Filming is the night shift's job (Studio 00:00-06:00, complete-game-standard §5). **Nothing here has been filmed, and
Steal a Cryptid has never been opened in Studio** (CLAUDE.md "Needs Studio", EYECANDY.md §9). `tools/` belongs to the
tools owner: every clip below is **new** and needs a `CRYPTID` scenario table added to `tools/film_game.py`, built
from the helpers it already has (`teleport`, `camera_behind`, `zoom`, `keys`, `orbit`, `restart_play`). The store text
is in `README.md`; the thumbnails are `EYECANDY.md` §10.

## Rules for staging

`film_game.py` may place the character (a server-side teleport), script the camera and pin its distance. It never
edits the game's numbers and never fakes progress the HUD then shows.

* **A fresh Play is a fresh player.** The place is not published, so Studio has no DataStore (with *Enable Studio
  Access to API Services* off): the server warns, plays a fresh profile that is never written, and shows the "Not
  saving this session" banner. Clips 1, 2, 3 and 10 use that, unedited; hide only the banner if it covers the shot
  (`PlayerGui.CryptidHud.Root.SaveBanner.Visible = false`), never a number.
* **Late-game clips use the shots place**, exactly as `EYECANDY.md` §10 steps 1-3 build it: `rojo build -o
  StealACryptid-shots.rbxlx` (git-ignored), then in THAT place's `ReplicatedStorage.Config` only:
  `Economy.StartEssence = 50000000`, `Economy.StartCages = 9`, `Poacher.FirstAfterSeconds = 100000`, and for the
  clips without a hazard `Night.Hazards.IntervalMin = 100000`, `IntervalMax = 100001`. That Essence is not a real
  player's, so **hide the HUD** in those clips (`PlayerGui.CryptidHud.Enabled = false`) unless the clip says why it is
  shown, and say "shots place" in the manifest's staging list. Never edit `src/`.
* **Hazard timing** (clip 6 only): in the shots place, `Night.Hazards.IntervalMin = 8`, `IntervalMax = 10`, and
  `Night.Rest.IdleSeconds = 0` (`Rest.validate` accepts 0; without it the night rests after 20 s of standing still and
  the hazard never comes). A normal player meets one hazard every 2-3 minutes of home time (EYECANDY.md §3). Say so.
* **Poacher timing** (clip 4 only): in the shots place, `Poacher.FirstAfterSeconds = 20`. A normal player meets the
  first poacher 5 minutes in, then every 3-4 minutes. Say so.
* **Never film the Friends view with a real account's friends list on it**: it shows their Roblox usernames. Use a
  Studio Local Server test player (no friends: the board then shows its "No Roblox friends yet" note).
* **Coordinates** are `Plot_0`'s (the first player in the server; EYECANDY.md §10 step 5): plot-local (x, z) is world
  (x - 36, y, z + 16), facing +Z from the road. Arrival marker (0, 3, 24); P1 (-10, 24), P2 (-20, 24), P3 (-30, 24);
  the Collect Pad (12, 24); the Hunt Board (26, 24); the Top Lairs board (16, 5, 31.6), its face toward the road; the
  cage row z 104-112, cage 5 at x 0. The first raid of a server uses pocket 0: camp-local (x, z) is world
  (4000 + x, y, z), the gate at (4036, 0, 20).

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `first_cryptid` | 8-10 s | a fresh player steps to the glowing pedestal, presses E: a Jackalope trots from its pedestal into its cage |
| 2 | `the_grab` | 10-14 s | at a rival camp's cage: hold E, the cryptid comes up on your back, carry it out through a net that just went dark, "You stole a ...!" |
| 3 | `caught` | 7-9 s | a step into a net that turns red: the flash, "Caught by a laser net", home with nothing |
| 4 | `poacher_in_the_net` | 10-14 s | the poacher's warning, the poacher sneaking toward the fullest jar, caught in your net, the bounty |
| 5 | `mythic_night` | 10-14 s | the brag moment: the Bigfoot bought at P3, the sky glides into Mythic Night, the gold aurora, the card |
| 6 | `close_call` | 8-12 s | a meteorite's red ring, "Move! Leave the red ring", one step sideways, it strikes the empty ring |
| 7 | `loch_shore` | 10-15 s | the Legendary camp from its gate: Nessie gliding past a castle's lit window, moths, the nets ahead |
| 8 | `the_gathering` | 10-14 s | the long goal's sky: a third Bigfoot, the crimson moon rises, the legends of Pine Hollow appear on the far rim |
| 9 | `top_lairs` | 7-9 s | the Top Lairs board behind the Collect Pad, E pressed, PUBLIC turns to FRIENDS |
| 10 | `rest_by_the_fire` | 7-9 s | Rest tapped: the avatar sits, a campfire lights, the critters drift away |

### Staging, clip by clip

1. **`first_cryptid`**. Fresh Play. The character lands on the arrival marker at (0, 3, 24) facing P1 (-X). Walk one
   step west to P1's front (-10, 3, 21) and press E: the Jackalope (30 Essence, exactly the starting Essence) walks
   from the pedestal to cage 5 at (0, 0, 108) in 2 s, the toast says "+1 Essence/s". Camera behind and above, 16
   studs, pitched so the pedestal and the cage row share the frame. HUD on: every number on it is this session's.
2. **`the_grab`**. Fresh Play: buy the Jackalope (clip 1), step on the Collect Pad, open the Hunt Board and start
   Camp 1 (free) off camera. Walk to a cage (each cage's GRAB anchor glows; the far one is the prize) along a route
   whose net is OFF. Start recording at the anchor: hold E for the 1.0 s grab, then walk back to the gate at (4036,
   3, 20), waiting in front of the net for it to go dark (amber is the warning, red is on). The server sends you home
   with the cryptid, which walks into its cage, and toasts "You stole a ...!". Camera behind, 18 studs. HUD on. If
   the take is caught, it is clip 3.
3. **`caught`**. Same set-up as clip 2. In the camp, stand in front of the net at the first fence line, wait until
   it turns amber, and walk in as it turns red. The flash, "Caught by a laser net - the permit is gone", and the walk
   from the arrival marker. Camera behind, 14 studs, so the net fills the frame. HUD on.
4. **`poacher_in_the_net`**. Shots place with the poacher timing above, HUD on (the warning chip is the point; the
   numbers are the shots place's: say so). Buy two cryptids (a poacher needs two), press Build and force BOTH fence
   lines: on each, snares in two of its three gaps and a laser net in the third (4 snares, 2 nets; a snare only
   steers the poacher, a burning net catches it). Stand on the apron at (12, 3, 20). Record from the chip's "A
   poacher arrives in 10 s" through the poacher walking in from the gate. With both lines forced it is caught 62.9 %
   of the time (`Poacher.spec`): keep the take where it is ("Your laser net caught the poacher! +... Essence bounty").
5. **`mythic_night`**. Shots place, session A edits, HUD hidden. Rank up as in EYECANDY.md §10 step 4 to a Legendary
   (Strange Lights). Stand at P3's front (-30, 3, 21), camera facing +Z and pitched up about 25 degrees so the aurora
   band is in frame. Record from the press of E at P3 (the Bigfoot) through the glide: in about 3 s the green aurora
   turns gold, the UFOs and Bigfoot come in over the ridge, and the card says MYTHIC NIGHT / Bigfoot walks Pine
   Hollow. `tests/Pacing.spec.luau` puts this moment at a median 36 minutes of normal play.
6. **`close_call`**. `EYECANDY.md` §10 shot 3 as a clip: shots place, session B (the hazard timing above), rank 4
   (Mythic Night: meteorites). Buy, step on the Collect Pad, start a hunt and leave the camp (the tutorial must be
   done). At home, stand still on the apron with the camera level or a little up. A meteorite comes every 8-10 s;
   when the ring turns red and the chip says "Move! Leave the red ring", walk out of it sideways and keep the take
   where it strikes the empty ring. HUD on (the chip is the point; say "shots place").
7. **`loch_shore`**. Shots place, session A, HUD hidden, rank 4 (a hunt needs a free cage: release one first). Hunt
   Board, Camp 3: the camera behind the gate at about (4036, 22, -25) looking at (4080, 8, 320). Wait until
   `workspace.CryptidNight.NessieHead` is between x 3990 and 4060 and record her glide past the castle tower (its lit
   window at about (4210, 44, 417)), moths flitting, then the raider walking in. Leave the camp after.
8. **`the_gathering`**. Shots place, session A, HUD hidden. From Mythic Night (clip 5), buy two more Bigfoots at P3
   (2.5 s apart; the second one takes the best lair income past 1 350/s, `Config.Night.GatheringRate`). The character
   stays at P3's front; the scripted camera sits behind the cage row at about (0, 30, 118). Start facing +Z and a
   little up: at the second purchase the crimson moon rises low over the ridge on the right of the frame (it rides
   with the camera, like the auroras), embers begin to drift and the card says THE GATHERING. Then pan slowly left
   (+X is screen-left facing +Z) across the back fence and the ravine onto this side's legends of Pine Hollow, a
   Mothman and a Dogman 30 studs tall on the far floor, eyes glowing. With MaxPlayers 8 they stand near (96, -1, 184)
   and (256, -1, 184); print them with `for _, d in workspace.CryptidNight:GetChildren() do if d.Name == "Legend_Body"
   then print(d.Position) end end`. `tests/Pacing.spec.luau` puts this band at a median 97 minutes of normal play.
9. **`top_lairs`**. Film it AFTER the experience exists (§5 creates it) with *Enable Studio Access to API Services*
   ON, so the public view has the filming account's own row; without a DataStore the board says "No lairs on the
   board yet". A Studio Local Server test player (no friends list). Stand on the Collect Pad at (12, 3, 24): the board
   is in front, its prompt in reach. Record E pressed twice: PUBLIC to FRIENDS ("No Roblox friends yet...") and back.
   Camera behind, 12 studs, the board filling the upper half.
10. **`rest_by_the_fire`**. Fresh Play, HUD on. Stand on the apron facing the road (-Z) and tap Rest: the avatar sits,
    the campfire lights 4 studs ahead, the chip says "Resting - poachers still come". Camera low, 10 studs, from the
    side. Tap Rest again at the end: the fire goes out and the avatar stands.

## Where the clips go

Posting follows complete-game-standard §5: only after the new version is live, spread over a day and the next, one
game at a time, in communities whose rules allow self-promotion, every post labelled as AI-assisted.
