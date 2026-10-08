# Grow a Crystal in real Studio

## Eye-candy (night shift, 2026-10-09)

The place was built from `src/` (`tools/studio_open.ps1 grow-a-crystal`), render quality was pinned to
Level21, and the game was played solo as a fresh player (1 chamber, 30 dust). DataStores are off in the
unpublished place ("progress will NOT be saved"). Screenshots are in `marketing/studio-2026-10-09/` at
1920 x 795, which is the Studio viewport, so they are not thumbnails.

### Console

The console shows only the two expected datastore warnings and the load line. No errors.

### Measured

| Item | Result |
|---|---|
| HUD board | **Real defect, fixed.** With nobody stored, the right-hand 🏆 TOP MINERS panel was an empty dark box (`01`); this is the same defect +1 Jump had. It now says "No miners yet. Be the first!" (`Board.hudNote`, `Config.Board.Text.EmptyHud`). Seen in Studio after the fix (`EmptyNote` visible, 184x44, `02`). |
| §8 item 1: band look (Sunken Grotto only) | The cavern reads as a dark cave with terraces up to the pool (`03`). The sockets are flat, bright blue plates with no glow, and they read as UI tiles laid on the floor more than as sockets in rock. Only band 1 was seen; the other bands need chambers 3-8. |
| §8 item 5: prisms | The bright cyan Neon bars on the walls are the server's `Plots/Vein_1..10`, not the client's geode prisms. Several hang in the air off the wall and **read as glowing sticks, not crystals**. |
| §8 item 4: the waterfall | From the spawn, the waterfall at the back reads as a glowing white doorway. It does not read as water. |
| HUD text | The top instruction line ("Click a glowing socket to PLANT...") runs over the waterfall's glow, which washes out its middle words. |
| 2, 3, 6-26 | Not measured tonight (they need later bands, a phone or a real server). |

### Verdict

Playable. The empty-board defect is fixed. **Not published**: the robloxemu gates cannot run (no luau CLI), the
second review is in EYECANDY, and there are no 16:9 thumbnails.
