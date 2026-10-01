-- Prints the thumbnail shot list (marketing/ShotList.luau, the only copy) as a markdown table.
-- Run from anomaly-observatory/:  luau marketing/print_shotlist.luau
print(require("./ShotList").render())
