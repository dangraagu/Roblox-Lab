# Anomaly Observatory in real Studio

## Eye-candy (night shift, 2026-10-09)

The place was built from `src/` (`tools/studio_open.ps1 anomaly-observatory`). Render quality was pinned to
Level21 before Play, as `tools/film_anomaly.py` does. The game was played solo; hall index 1 sat at
O = (1000, 100, 0). DataStores are off in the unpublished place: the console says "running without saves", and
the Field Guide sign says "The board can't reach Roblox right now...". The Day was set on the server for the
sky only, and no pass was answered. Screenshots are in `marketing/studio-2026-10-09/`. They are 1920 x 795 (the
Studio viewport), so none of them is a thumbnail.

### Console

The console shows only `DataStore unavailable`, `loaded`, `night sky ready` and `HUD ready`. No errors.

### Measured, per EYECANDY §8

| §8 item | Result |
|---|---|
| 1: the sky from the doorway | **Visible.** At Day 1 the crescent moon, the ridges against a lighter haze, a few stars and the lantern path read from just inside the doorway (`02`). The ridges are one repeated zig-zag crown shape, which reads as man-made. |
| 15: no second moon | Only one moon in every frame (Days 1, 12, 25, 55). |
| 10: the break | **Works.** B fades to the sky view. The caption explains the break ("your hall is waiting, exactly as you left it"), and B again returns to the hall (`03`). The guard is honest: while another script held the camera as Scriptable, B said "Not right now: the camera is busy". Capture-rig note: the MCP `execute_luau` restores the camera type it found when it started, so a `CameraType = Custom` set inside a call is undone. Use `task.delay` to set it. |
| 5: aurora (Day 12) | **Reads as flat, hard-edged planks**, not curtains (`04`). The beams have a constant width and a sharp edge. This needs art: a transparency fade along and across the beam (a texture), and more curve. Not fixed tonight. |
| 6: storm (Day 25) | **Almost black.** The cloud bank is dark blobs over a dark sky, and the moon is a flat grey disc (`05`). No lightning flash was caught in one still. It reads as "nothing out there" more than as a storm. |
| 8: The Other Sky (Day 55) | The 18 segments read as one ring (`06`). **But the ring and its stars run behind the top-centre caption and hint text**, which has no backing panel, so the text is hard to read there. The comet tail is a flat translucent plank. |
| 20: Field Guide sign | Readable from the start pad, with its prompt text ("press L or tap for friends") visible (`01`). No real friends list was available (unpublished place). |
| HUD | In the first second after join, Roblox's own chat notice ("Chat '/?' or '/help'...") prints over the DAY panel's "Best" line (`01`). It then fades. The top-centre instruction line sits over the hall's bright ceiling lights, so its middle words wash out when the player looks down the hall. |
| 2, 3, 4, 7, 9, 11-14, 16-19, 21-35 | Not measured tonight. |

### Verdict

The game is playable, and the sky works as a reward on the break. It still has visual weak spots: the aurora
planks, the near-black storm, and the caption over The Other Sky. **It is not published**, because:

- the robloxemu gates cannot run on this machine (no luau CLI);
- the second review asks for two fixes first (EYECANDY §0i);
- there are no 16:9 thumbnails yet.
