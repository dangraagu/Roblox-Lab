--!nocheck
-- M3: whole campaigns through the schedule and economy in station.luau. Minutes are p50 over runs.
local M = require("./m3_campaign")
M.measure(400, 61, 240, "M3 campaign, greedy buyer (cheapest affordable rank after each splice)")
