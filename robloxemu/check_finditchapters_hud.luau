-- Find It! Chapters: headless HUD fit check, panel-overlap rule ON (docs/complete-game-standard.md §2), at the
-- emulator's 36 px topbar inset. The sweep is check_finditchapters_hudlib.luau; check_finditchapters_hud58.luau runs
-- it at 58 px.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_hud.luau 2>&1
require("./check_finditchapters_hudlib")(36)
