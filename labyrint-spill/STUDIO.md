# Labyrint in real Studio

## Eye-candy (night shift, 2026-10-09)

**Setup.**
- The place was built from `src/` (`tools/studio_open.ps1 labyrint-spill`) and played solo.
- Render quality was pinned to Level21.
- The console showed only `[Labyrint] Lobby-modus lastet.`, with no errors.
- Screenshots are in `marketing/studio-2026-10-09/` at 1920 x 795 (the Studio viewport), so none of them is a
  thumbnail.

### Measured

| Item | Result |
|---|---|
| Solo door | Holding E at `SoloDoor` opens the **Solo Climb** picker (`02`). The two MCP shortcuts failed: `character_navigation` found no route, and a scripted `ProximityPrompt:InputHoldBegin` did nothing. Only a real E hold worked. |
| **Close buttons** | **Real defect, fixed.** The picker's close button showed an **empty rectangle** (`02`). Its text is `✕` (U+2715), which Gotham and SourceSans cannot draw. A side-by-side test in the running game (`03`) showed which symbols draw: `✕` (U+2715) and `☰` (U+2630) are tofu; `✔` (U+2714) and `✖` (U+2716) render as near-black emoji, invisible on the dark panels; every other symbol the games use draws. The new `tools/check_glyphs.py` fails on those four. It found 21 uses in 5 games, all replaced: `X` for close, `≡` for menu, `✓` for the check mark. This includes +1 Jump's menu and top toggles and its multiplier icon, which was blank in its Studio view; it is now `✨`. The picker was seen again after the fix with a clear **X** (`04`). |
| Level 1 start | `StartRun(1, "Solo")` (the remote the picker's button fires) put the avatar into level 1. At the start, the player faced the back wall with the red start panel, and no corridor was in view (`05`). This is one sample; rotating the spawn toward the open side would be a server change (not done). |
| HUD | The top-centre "Your best — / Accepted: 0" lines are thin, dim text on a transparent box and are barely readable (`01`, `05`). From the spawn, the HUD's Records panel and Shop button cover the world's "BIOMES YOU REACHED" sign (`01`). The minimap and the Records panel share the top-right column, but `LeaderboardClient` moves Records below the map when the perk is owned (checked in code, not seen: the perk was not owned). |
| Biomes, hazards, rest (EYECANDY §8) | Not measured tonight: these need levels 26+, a walk through a maze, and the break room. |

### Verdict

The lobby and the start of a run work. The close-button tofu is fixed. **Not published**, because:

- the robloxemu gates cannot run (no luau CLI on the machine);
- the second review found a HIGH (EYECANDY);
- there are no 16:9 thumbnails yet.
