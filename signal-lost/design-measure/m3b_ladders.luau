--!nocheck
-- M3b: does the price ladder move the brag? Three ladders, the same ladder for both upgrades.
local S = require("./station")
local M = require("./m3_campaign")
for _, L in { { 100, 250, 500, 900 }, { 120, 300, 600, 1000 }, { 150, 350, 700, 1200 } } do
	local econ = table.clone(S.ECON)
	econ.prices = { tank = L, boots = table.clone(L) }
	M.measure(300, 61, 240, "M3b ladder " .. table.concat(L, "/"), nil, econ, nil, { "medium", "slow" })
end
