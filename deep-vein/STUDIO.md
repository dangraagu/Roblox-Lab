
## Eye-candy, first look (night shift, 2026-10-09)

The place was built from `src/` and played solo, with quality pinned to Level21. The console showed the two
expected datastore warnings and the load line, and no errors. Screenshots are in
`marketing/studio-2026-10-09/`.

- **Real defect, fixed: empty boxes in the HUD** (`01`). Three emoji draw as an empty rectangle:
  - 🛗 U+1F6D7, on the SURFACE button and in the hint;
  - 🪨 U+1FAA8, the Grey Stone band's emoji, shown in the band chip as the next band;
  - 🪙 U+1FAA9, coins, in labyrint-spill and stormgrow.

  A grid of all 95 emoji the games use was rendered in the running game (`02`); the other 92 draw. These three
  are now in `tools/check_glyphs.py` and replaced: ⬆ for SURFACE (⬇ for "Down to"), 🧱 for stone, 💰 for coins.
- **Real defect, fixed: the HUD's 🏆 DEEPEST panel was an empty box.** It now says "Nobody yet. Be the first!"
  (`Board.hudNote`; `Board.spec` 78/0, red first, mutation KILLED). It was seen fixed in Studio (`03`).
- All 12 deep-vein specs are green, run inside Studio.
- Not measured tonight: the EYECANDY needs-Studio list (strata, the fall vs the part streamer).
