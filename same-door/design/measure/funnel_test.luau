local M = require("./maze")
local m = { W = 3, H = 3 }
local C = function(x, y) return y * 3 + x end
local function show(name, cells, flip)
	local s = M.centre(m, cells[1], 16)
	local e = M.centre(m, cells[#cells], 16)
	print(name, flip, string.format("%.3f", M.funnel(m, cells, s, e, 16, 2.5, flip)))
end
for _, flip in { false, true } do
	show("straight 3", { C(0, 0), C(1, 0), C(2, 0) }, flip) -- expect 32
	show("L north-east", { C(0, 0), C(0, 1), C(1, 1) }, flip) -- expect 22.95
	show("L east-north", { C(0, 0), C(1, 0), C(1, 1) }, flip) -- expect 22.95
	show("staircase", { C(0, 0), C(1, 0), C(1, 1), C(2, 1), C(2, 2) }, flip) -- straight diagonal 45.25 if clear
	show("U-turn", { C(0, 0), C(1, 0), C(1, 1), C(0, 1) }, flip)
end
