-- Find It! Chapters: headless HUD fit check, panel-overlap rule ON (docs/complete-game-standard.md §2), at a
-- 58 px topbar inset. The sweep is check_finditchapters_hudlib.luau; check_finditchapters_hud.luau runs
-- it at 36 px.
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_hud58.luau 2>&1
require("./check_finditchapters_hudlib")(58)
