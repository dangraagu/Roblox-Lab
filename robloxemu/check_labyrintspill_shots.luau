-- Labyrinth Mariozo — the thumbnail shot list's helper snippet, proved headless before the night session.
-- Run: luau check_labyrintspill_shots.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- labyrint-spill/EYECANDY.md §9 tells the Studio operator to paste SHOT_HELPER (below, verbatim) into the
-- command bar in CLIENT context. It finds the nearest falling-hazard cell of the level being played, with
-- the same pure rule Biome.client uses, and stands the avatar in the open passage beside it, so the ring,
-- the shadow and the object overhead are in frame within one 14 s cycle and the avatar is never knocked.
--
-- Why this needs a check: the emulator's Random is not Roblox's, so no maze coordinate measured here is
-- valid in Studio. The helper therefore reads everything from the live maze (walls, traps, floor), and this
-- file proves that on whatever maze it gets, it lands the avatar next to a cell the REAL client then
-- draws, at every hazard biome of the shot list, and that standing there is safe through an impact.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill shots")
local truthy, eq = T.truthy, T.eq

-- VERBATIM in EYECANDY.md §9. Edit both or neither. `LEVEL` is the only line the operator changes.
local SHOT_HELPER = [==[
local LEVEL, TARGET = 38, "hazard" -- TARGET: "hazard" (the level's falling hazard) or "trap" (a lava trap)
local RS, P = game:GetService("ReplicatedStorage"), game:GetService("Players").LocalPlayer
local B, CH, E = require(RS.Biomes), require(RS.CellHazards), require(RS.EnvBands)
assert(TARGET == "trap" or B.hazardKindAt(E, LEVEL), "no falling hazard on this level (the dungeon and the jungle have none)")
local f = workspace:FindFirstChild(P:GetAttribute("MazeFolder") or "")
local fl = f and f:FindFirstChild("Floor")
assert(fl, "start the level first (no maze for this player)")
local S, o = B.Hazards.CellSize, fl.Position
local gC, gR = math.floor(fl.Size.X / S + 0.5), math.floor(fl.Size.Z / S + 0.5)
local function fine(p) return math.floor((p.X - o.X) / S + (gC - 1) / 2 + 0.5), math.floor((p.Z - o.Z) / S + (gR - 1) / 2 + 0.5) end
local function world(x, y) return Vector3.new(o.X + (x - (gC - 1) / 2) * S, o.Y + fl.Size.Y / 2 + 3, o.Z + (y - (gR - 1) / 2) * S) end
local walls, traps = {}, {}
for _, d in f:GetChildren() do
	if d.Name == "Wall" or d.Name == "SecretWall" then local x, y = fine(d.Position); walls[x .. "," .. y] = true end
	if d.Name == "Trap" then local x, y = fine(d.Position); traps[((x - 1) // 2) .. "," .. ((y - 1) // 2)] = true end
end
local cells = {}
if TARGET == "trap" then
	for k in traps do local x, y = string.match(k, "(-?%d+),(-?%d+)"); table.insert(cells, { cx = tonumber(x), cy = tonumber(y) }) end
else
	cells = CH.pick(LEVEL, (gC - 1) // 2, (gR - 1) // 2, traps, B.Seed, B.Hazards)
end
local root = P.Character.HumanoidRootPart
local best, bestD
for _, h in cells do
	local d = (world(2 * h.cx + 1, 2 * h.cy + 1) - root.Position).Magnitude
	if bestD == nil or d < bestD then best, bestD = h, d end
end
assert(best, "nothing to stand beside on this maze")
local cx, cy = 2 * best.cx + 1, 2 * best.cy + 1
for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
	if not walls[(cx + d[1]) .. "," .. (cy + d[2])] then
		P.Character:PivotTo(CFrame.lookAt(world(cx + d[1], cy + d[2]), world(cx, cy)))
		print("[shot] beside " .. TARGET .. " cell " .. best.cx .. "," .. best.cy .. (if TARGET == "trap" then " - it pulses every 5.2 s" else " - its ring lights within 14 s"))
		break
	end
end
]==]

-- VERBATIM in EYECANDY.md §9 too: hide every on-screen and in-world label for a clean frame (client only).
local CLEAN_FRAME = [==[
local P = game:GetService("Players").LocalPlayer
for _, g in P.PlayerGui:GetChildren() do if g:IsA("ScreenGui") then g.Enabled = false end end
for _, root in { workspace:FindFirstChild(P:GetAttribute("MazeFolder") or ""), workspace:FindFirstChild("LabyrintBreakRoom") } do
	for _, b in root:GetDescendants() do if b:IsA("BillboardGui") then b.Enabled = false end end
end
pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
]==]

local ctx = Lib.boot({ accepted = 480, clients = Lib.CLIENTS_NO_SOUND })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local RS = h.ReplicatedStorage
local Biomes = h:_require(RS:FindFirstChild("Biomes"))
local CellHazards = h:_require(RS:FindFirstChild("CellHazards"))
local HZ = Biomes.Hazards
local LOCAL = h.workspace:FindFirstChild("LabyrintBiomeLocal")

local function runHelper(level, target)
	local src = string.gsub(SHOT_HELPER, 'local LEVEL, TARGET = 38, "hazard"', 'local LEVEL, TARGET = ' .. level .. ', "' .. (target or "hazard") .. '"', 1)
	assert(src ~= SHOT_HELPER or (level == 38 and target == nil), "the LEVEL line was not found")
	local ok, err = pcall(function()
		h:_exec({ source = src, path = "shot-helper" }, "client/ShotHelper")
	end)
	return ok, err
end

-- every hazard shot of the shot list (EYECANDY.md §9): ice 38, forge 76, crystal 131, crypt 201, sky 296, astral 401
for _, L in { 38, 76, 131, 201, 296, 401 } do
	ctx.startRun(L)
	ctx.run(1.0)
	local g = Lib.grid(ctx.folder())
	local before = ctx.hrp.Position
	local ok, err = runHelper(L)
	truthy(ok, "L" .. L .. ": the helper runs in client context (" .. tostring(err) .. ")")
	local pos = ctx.hrp.Position
	truthy((pos - before).Magnitude > 0.5, "L" .. L .. ": it moved the avatar")
	-- where it stands: an open fine cell one step from a hazard cell the pure rule names
	local fx, fy = g.fine(pos)
	eq(g.walls[fx .. "," .. fy], nil, "L" .. L .. ": the avatar stands in an open cell, not in a wall")
	local list = CellHazards.pick(L, g.cols, g.rows, g.traps, Biomes.Seed, HZ)
	local target = nil
	for _, hz in list do
		local hx, hy = 2 * hz.cx + 1, 2 * hz.cy + 1
		if math.abs(hx - fx) + math.abs(hy - fy) == 1 then target = hz end
	end
	truthy(target ~= nil, "L" .. L .. ": right beside one of the level's hazard cells")
	local floor = ctx.folder():FindFirstChild("Floor")
	truthy(math.abs(pos.Y - (floor.Position.Y + floor.Size.Y / 2 + 3)) < 0.01, "L" .. L .. ": standing height (root 3 studs over the floor)")
	-- within one cycle the real client draws a ring on that cell, and standing here is safe through the impact
	local ringSeen, knocked = false, false
	if target then
		local c = g.world(2 * target.cx + 1, 2 * target.cy + 1)
		for _ = 1, math.ceil((HZ.Period + HZ.WarnSeconds + 1) * 30) do
			ctx.frame(1 / 30)
			for _, d in LOCAL:GetChildren() do
				if d.Name == "HazardRing" and math.abs(d.Position.X - c.X) < 0.25 and math.abs(d.Position.Z - c.Z) < 0.25 then ringSeen = true end
			end
			if ctx.hum.PlatformStand == true then knocked = true end
		end
	end
	truthy(ringSeen, "L" .. L .. ": the real client draws that cell's ring within one cycle (" .. HZ.Period .. " s)")
	eq(knocked, false, "L" .. L .. ": standing in the passage beside it, the avatar is never knocked")
end

-- TARGET = "trap": beside the nearest lava trap, in the passage, never on it and never killed by it
do
	local L = 76
	ctx.startRun(L)
	ctx.run(1.0)
	local g = Lib.grid(ctx.folder())
	local ok, err = runHelper(L, "trap")
	truthy(ok, "trap mode runs (" .. tostring(err) .. ")")
	local fx, fy = g.fine(ctx.hrp.Position)
	eq(g.walls[fx .. "," .. fy], nil, "trap mode: the avatar stands in an open cell")
	local onTrapCell = fx % 2 == 1 and fy % 2 == 1 and g.traps[((fx - 1) // 2) .. "," .. ((fy - 1) // 2)] == true
	eq(onTrapCell, false, "not on a trap cell")
	local beside = false
	for k in g.traps do
		local x, y = string.match(k, "(-?%d+),(-?%d+)")
		if math.abs(2 * tonumber(x) + 1 - fx) + math.abs(2 * tonumber(y) + 1 - fy) == 1 then beside = true end
	end
	truthy(beside, "right beside a trap cell of the real maze")
	ctx.run(12)
	truthy(ctx.hum.Health > 0, "and still alive after two full trap cycles")
end

-- the clean-frame snippet: no ScreenGui and no label in the maze or the break room stays on
do
	local ok, err = pcall(function() h:_exec({ source = CLEAN_FRAME, path = "clean-frame" }, "client/CleanFrame") end)
	truthy(ok, "the clean-frame snippet runs in client context (" .. tostring(err) .. ")")
	local on = {}
	for _, g in ctx.plr.PlayerGui:GetChildren() do
		if g.ClassName == "ScreenGui" and g.Enabled ~= false then table.insert(on, g.Name) end
	end
	for _, root in { ctx.folder(), h.workspace:FindFirstChild("LabyrintBreakRoom") } do
		for _, b in root:GetDescendants() do
			if b.ClassName == "BillboardGui" and b.Enabled ~= false then table.insert(on, b:GetFullName()) end
		end
	end
	eq(#on, 0, "after the clean-frame snippet nothing labelled is on (" .. table.concat(on, ", ") .. ")")
	ctx.run(1)
	local back = {}
	for _, g in ctx.plr.PlayerGui:GetChildren() do
		if g.ClassName == "ScreenGui" and g.Enabled ~= false then table.insert(back, g.Name) end
	end
	eq(#back, 0, "and no client script turns a ScreenGui back on a second later (" .. table.concat(back, ", ") .. ")")
end

-- the dungeon has no hazard: the helper says so instead of moving anyone
ctx.startRun(6)
ctx.run(1.0)
local before = ctx.hrp.Position
local ok, err = runHelper(6)
eq(ok, false, "in the dungeon the helper stops with a message")
truthy(err and string.find(err, "no falling hazard", 1, true) ~= nil, "naming why: " .. tostring(err))
truthy((ctx.hrp.Position - before).Magnitude < 1e-6, "and moves nobody")

T.finish(h)
