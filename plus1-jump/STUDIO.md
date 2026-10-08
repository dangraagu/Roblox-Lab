# +1 Jump in real Studio

## Eye-candy (night shift, 2026-10-09)

The place was built from `src/` (`tools/studio_open.ps1 plus1-jump`) and played in Studio. DataStores are not
available in the unpublished place, so nothing was saved and no board was written. The shot configuration from
EYECANDY §9 was set in the open place only, never in `src/`: session A had StreamAhead 260 and no hazards;
session B had hazards every 8-10 s and idle rest off. The avatar was moved between bands with `PivotTo`. The
camera was a scripted camera bound after the game's own camera. Screenshots are in
`marketing/studio-2026-10-09/`. They are 1920 x 795 because that is the Studio viewport, so they are working
pictures, not thumbnails.

### Console

On join there are only the two expected "datastore unavailable" warnings and the load line. No errors were
logged across 6 Play sessions.

### What was measured, per EYECANDY §8

| §8 item | Result |
|---|---|
| 1, 3, 5, 7: band looks | **Two real defects, fixed.** In Treetops and Cloud Sea, the white cloud puffs and the tiles washed out into a flat white sheet. The deck read as nothing, and the player was a speck in a glare (`04-treetops-before`, `06-cloudsea-before`). The lighting was Brightness 3.2-3.4 at Exposure +0.2/+0.25, with bloom Threshold 0.85-0.9 at Intensity 1.0-1.2. In the running session, lowering this to Brightness 2.6, Exposure -0.1/-0.15 and bloom Threshold 1.0 at Intensity 0.8 brought the puffs back as shaded balls in front of the sunset haze (`05-treetops-after`, `07-cloudsea-after`). The fix was checked again with the committed Config: the Lighting read back exp -0.15, bright 2.60, thr 1.00, int 0.80, and the picture matches. Temple, Storm, Orbit and Galaxy were left as they are: they read, and the temple values must equal `Fx.Presets.Temple`. |
| 2: stars | **Not seen in any capture** in Orbit (StarCount 3500, ClockTime 23) or Galaxy (5000). The capture may lose faint stars. This needs a check by eye. |
| 4, 6: distant giants, beams | The Earth (Orbit) and the galaxy core and arms (Galaxy) render on desktop at max quality. The nebula discs read as flat, opaque, low-poly blobs, not as glow (`10-galaxy`). Mobile culling was not tested. |
| Storm | Reads as a flat magenta-pink haze, with the moon and a balloon visible (`08-storm`). It does not look stormy. No lightning bolt was caught in a single capture. Left as is (taste). |
| 11: rest's sit | Verified on 2026-09-27 (`EYECANDY` §15); not re-done. |
| 20 / 9: hazard telegraph and knock | Session B at `P_160_1`: an asteroid hazard launched within 1 s, and the banner read "⚠️ MOVE! ASTEROID ▲". The avatar was knocked off. The fall rescue then put it **on the spawn pad, not on `P_160_1`**, because since the climb guard (§16) a teleport touches nothing. The §9 recipe for shot 5 ("the rescue puts it back on `P_160_1`") is therefore stale, and shot 5 cannot be shot with a teleport any more. |
| 24: the board | The gold Neon trim blows out under bloom into a white blob when seen from the tower side (`02-temple-pad-board-bloom`). From the spawn it reads as a glowing yellow frame. The text reads from the spawn. |
| 25: spawn facing | **Measured:** the spawned root faces -Z (LookVector 0,0,-1), toward the board, so the tower is behind a new player (`01-spawn-player-view`). The HUD band chip (`Temple Grounds · Space in 85` + Rest) also covers the board's "TOP CLIMBERS" title from the spawn view. No owner decision was taken; see §18. |
| HUD | **Real defect, fixed.** With no climbers stored, the right-hand 🏆 TOP CLIMBERS panel was an empty dark box, while the pad board said "No climbers on the board yet". The live store `Plus1Jump_LB_v2` starts empty too. The panel now says "No climbers yet. Be the first!" (`Board.hudNote`). This was seen in Studio after the fix (`EmptyNote` visible, 184x44 px). |
| 26: climb guard on a real client | Partial. A temporary `warn` was put in both refusal branches of the place's Main script only (never in `src/`). A client bot drove the real Humanoid with `MoveTo` and `Jump`. All 6 tiles of tier 1 were credited one each (Jumps 0 -> 6), with **0 refusals**. Tier 2 was not reached: the bot's steering bumped the underside of the next tile and fell, and the rescue worked each time. No network-simulator run was done. This is not enough to close reviewer finding 2 (§18). |
| 12, 13, 14, 17, 18, 21, 22, 23, 27 | Not measured tonight. |

### Verdict

Playable, and visibly better after tonight's two fixes. It is still **not ready to publish**:

- The robloxemu gates could not be run (no luau CLI on the machine, §18).
- No 16:9 thumbnails exist.
- The §8 items above that need a phone or a real network were not measured.
