# SIGNAL LOST: Derelict Station — clip list

Seven short gameplay moments for `tools/film_game.py` (docs/complete-game-standard.md §4). Every clip is **vertical
1080x1920, 30 fps, 7-15 s**, filmed from the real Studio viewport (the real renderer, HUD and lighting; never the
emulator). Each clip's staging goes into `marketing/clips/manifest.json`.

**Nothing here has been filmed.** The game has never been opened in Studio, so every clip is new: `tools/` belongs to
the tools owner, and each needs a `SIGNAL` scenario added to `tools/film_game.py`. Filming is the night shift's job
(Studio 00:00-06:00, standard §5), after the needs-Studio list (EYECANDY.md §8) has been walked. A clip of a look that
Studio shows to be wrong is not filmed until it is fixed.

## Rules for staging

`film_game.py` may place the camera, script the camera path and use what the game offers every player. It never edits
the game's numbers in a way the HUD then shows, and never fakes progress. For SIGNAL LOST that means:

- **The place.** `rojo build default.project.json -o Signal-shots.rbxlx` (git-ignored: `*.rbxlx`), opened from disk,
  never published. With *Studio Access to API Services* OFF the server cannot open its DataStore: the join toast says
  "Saving is unavailable on this server", the lifeboat hint says saving is off, every Play is a fresh profile (relay 0),
  and **purchases are refused** (the fabricator says why). Sectors play normally, and progress accumulates in memory
  for the session.
- **Teleporting the character does nothing useful.** The server trusts only its own copy of your position, which moves
  at most 1.35 x your speed and only through hatches it opened (DESIGN.md §14). A `PivotTo` into another module builds
  nothing and picks nothing up. Walk.
- **Deep sectors are played, not configured, when anything that states progress is in frame** (the SECTOR line, the
  RELAYS count, the ride banner, the brag card). Measured pace (`tests/Pacing.spec.luau`, the medium model player, with
  upgrades): sector 10 at minute 6.5, sector 23 at 22.9, relay 30 at 36.9. A storeless session cannot buy upgrades, so
  allow more. The one allowed shortcut, for a clip with every progress-stating element out of frame, is a shots-place-only
  edit of `ServerScriptService.Main`, in `tryStartSector`: `local k = sess.profile.best + 1` -> `local k = <sector>`.
  The manifest then says "sector <n> started directly for filming", and no caption names a sector number or a time.
- **Hazards** come every 55-85 s of eligible time (REVIEW-1; about one per 2.5 minutes of play) (a vacuum module, a band with hazards, at least 6 s into the sector,
  AIR at least 10 s, not resting), the first after 30 s, and a due hazard waits up to 15 s for you to stand still. For
  clip 2 the shots place may set `Config.Hazards.FirstIntervalSeconds = 3`, `IntervalMin = 8`, `IntervalMax = 10`
  (`Hazards.validateStation` accepts them). **This shortens the wait for filming only; the manifest must say so**, and
  no caption may say how often hazards come.
- **The board.** Never film the Friends view with a real account's friends list visible (it shows Roblox usernames).
  Use a Studio test player with no friends: the board then says "No Roblox friends yet."

Where things are (`Config.Hub`, `Config.Station`): the lifeboat is 60 x 40 x 16 studs at the origin. `HubSpawn` at
(4, 0.5, 0) faces +X; the LIFT pad is 12 studs ahead at (16, 0.2, 0) under a lit LIFT sign, with a glowing guide strip on
the floor; the RELAYS RESTORED board is on the east wall at (29.4, 7, 9) facing the spawn; the fabricator is on the south
wall at (20, 2.5, -18.4); the two benches are at x = -8 and -18 on the south wall, facing the planet window on the north
wall (38 studs wide, 4 to 12 studs up). The first player's zone is `workspace.Station.Zone_1` at (400, 0, 0); modules are
32-stud cubes with an 18-stud ceiling and 8 x 10 hatches; the transit pod is 140 studs south of the zone's centre.

## The clips

| # | clip | length | what the viewer sees |
|---|---|---|---|
| 1 | `red_light` | 10-12 s | a red VACUUM lamp over a hatch with a full AIR gauge; through it, gravity drops, a hop to a floating amber salvage piece while the gauge ticks; back through a green AIR hatch with a few seconds left, and the refill |
| 2 | `near_miss` | 8-10 s | standing still in a vacuum module, LOOSE CRATE — STEP OUT OF THE RING, a red ring at the feet, one step out, YOU ARE CLEAR, the crate tumbles through where you stood |
| 3 | `splice` | 9-11 s | the SIGNAL meter at 4 bars, a green hatch, the relay room with its red mast, SPLICING…, RELAY n ONLINE, the sector's lights coming on module by module |
| 4 | `blackout` | 9-11 s | AIR at 0, NO AIR — the edge of the screen closing in, a green lamp two modules away, the card SIGNAL LOST — you blacked out. Kept x of y carried salvage. |
| 5 | `main_array` | 12-15 s | relay 30's control room under a glass ceiling: the splice, SIGNAL SENT, the dish, the beam, the beacons, "…something answered." |
| 6 | `band_reveal` | 8-10 s | the floor hatch, the 3 s transit ride, the banner SECTOR 23 — ARRAY SPINE, the grade gliding from reactor orange to blue-violet |
| 7 | `board_toggle` | 7-9 s | the lifeboat: the RELAYS RESTORED board, E pressed, PUBLIC turns to FRIENDS |

### Staging, clip by clip

1. **`red_light`.** Honest, any sector 3-9 (sector 1 also works: every module next to the dock is vacuum and the first
   salvage floats in one of them). HUD on. Third-person camera behind the character, slightly high, so the lamp over the
   hatch and the AIR gauge (top right) are both in the strip. Walk into the red-lit doorway (the hatch slides open as you
   come within 8 studs), jump once toward the salvage (in vacuum the jump rises about 9 studs and drifts: DESIGN.md §8.1,
   a Studio item), take it (`+n salvage — banked when you splice the relay.`), and walk back through a green AIR doorway.
   Cut 1 s after the gauge refills (2 s from empty to full).
2. **`near_miss`.** Cargo Spine, sectors 10-15. Honest route: play there (about 6.5 minutes at the medium pace). With the
   filming interval (rules above) stand still in a vacuum module at least 6 s after arriving in the sector, with AIR at
   least 10 s (enter vacuum with a full tank: you then have 10 s of eligible air). When the banner and the red ring
   appear, wait about a second, then take one step (4 studs) in any direction: the ring is exactly where a hit can land,
   so any direction out of it dodges. A hit is a shove that costs nothing: retake freely. Third-person camera at about
   12 studs, so ring, character and the incoming crate share the strip.
3. **`splice`.** Honest, any sector. HUD on. Start the take when the SIGNAL meter shows 4 bars (one module from the relay),
   walk through the green doorway into the relay room, to the red mast in its centre. The splice starts within 6 studs
   of the mast and takes 2 s; every built module's light then comes on in doorway order (0.12 s per doorway step). Turn
   the camera toward a doorway at the payoff so the ripple shows.
4. **`blackout`.** Honest: in a sector with long vacuum stretches (the Deep, 31+, or any vacuum module if you simply wait),
   stand in vacuum until AIR reaches 0. The edge vignette closes in over the 5 s grace while the hint says OUT OF AIR — get
   to a green hatch light!; turn toward a green lamp you cannot reach in time. The card holds 2.5 s, then you wake in a
   newly generated sector. Carry salvage first, so the card's "Kept x of y" is not "0 of 0".
5. **`main_array`.** Honest route only if a filming account has really reached sector 30 (Studio on the published place
   with API access, after the publish). Otherwise the shots-place shortcut (`local k = 30`) with the HUD hidden
   (`PlayerGui.SignalHud.Enabled = false`; the brag card lives in `SignalOverlay` and stays), the manifest note, and in that
   shots place `Config.Air.TankBase = 40` so the 6 x 6 sector can be crossed for the take (the AIR gauge is hidden with the
   HUD). Camera: inside the control room looking up through its glass ceiling toward the dish, then the splice. The brag
   plays 6 s (dish swing, beam, beacons), the subtitle changes at 3 s. **Studio item EYECANDY.md §8 #9 must pass first.**
6. **`band_reveal`.** Honest only (the banner names the sector): a real sector 22 spliced, the floor hatch, the ride into
   23. The grade glides on a 0.6 s half-life, five half-lives inside the 3 s ride. Camera: whatever the ride shows (the
   pod is a closed lit capsule), then the first look around the new dock.
7. **`board_toggle`.** Studio Local Server, one test player (no friends). In the lifeboat walk to the east wall's board
   until the prompt shows (10 studs) and press E. Camera over the shoulder at about 12 studs, the board filling the upper
   two thirds. With API access off the public board says "No relays restored yet. Relay 1 takes about half a minute — be
   the first." and FRIENDS says "No Roblox friends yet. Friends you add show up here, ranked against you." Film the real
   public board only on a published place's Studio session with API access on.

### Captions that stay honest

- There is no monster and no Entity. The danger is the vacuum, and rare drifting debris that always shows its ring.
- No co-op: players share the lifeboat; each plays their own sector.
- The brag is relay 30, the Main Array. The model player reached it after a median of 36.9 minutes (28.4 fast, 49.2
  slow); those are models, not telemetry, so say "within your first hour" at most.
- Nothing costs Robux. A hazard costs a shove, never air or salvage. The board ranks relays restored, measured by the
  server, earliest first on a tie.
