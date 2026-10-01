-- Labyrinth Mariozo — critters, through the REAL client (Biome.client + BiomeArt).
-- Run: luau check_labyrintspill_critters.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- docs/complete-game-standard.md §2: every band has its own light, colour, scenery, critters and weather. Before
-- 2026-10-01 this game's bands had decor and air and no living thing. Now each biome has its own (Biomes.Critters):
-- rats, butterflies, bats, salamanders, beetles, spiders, swallows, star jellies. What this check holds, in a real
-- maze of every biome, with the player standing in the middle of it:
--   * the band's own critters are there, no more than Budget.MaxCritters, and the decor cap counts them;
--   * every critter part is inert (no collide, touch or query, no shadow), never Neon, and inside an OPEN cell of the
--     maze, never in a wall, never on a trap, within the torch's reach of the player;
--   * they move;
--   * they go when the player walks out to the lobby.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill critters")
local truthy, eq = T.truthy, T.eq

local ctx = Lib.boot({ accepted = 480, clients = { "LightingClient", "Biome" } })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local RS = h.ReplicatedStorage
local Biomes = h:_require(RS:FindFirstChild("Biomes"))
local EnvBands = h:_require(RS:FindFirstChild("EnvBands"))
local B = Biomes.Budget
local LOCAL = h.workspace:FindFirstChild("LabyrintBiomeLocal")
truthy(LOCAL ~= nil, "the client's local folder exists")

local function critterParts()
	local out = {}
	for _, d in LOCAL:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 8) == "Critter_" then table.insert(out, d) end
	end
	return out
end
local function slotsOf(parts)
	local slots, kinds = {}, {}
	for _, p in parts do
		local s = p:GetAttribute("CritterSlot")
		if s ~= nil and slots[s] == nil then
			slots[s] = p
			local kind = string.sub(p.Name, 9)
			kinds[kind] = (kinds[kind] or 0) + 1
		end
	end
	local n = 0
	for _ in slots do n += 1 end
	return n, kinds, slots
end
-- decor PIECES on show (parts / the piece's prim count), the way check_labyrintspill_budget counts them
local function decorPieces()
	local byId = {}
	for _, d in LOCAL:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "Decor_" then
			local id = string.sub(d.Name, 7)
			byId[id] = (byId[id] or 0) + 1
		end
	end
	local n = 0
	for id, parts in byId do n += parts / #Biomes.Pieces[id].prims end
	return n
end

local LEVELS = { 5, 18, 38, 75, 131, 200, 300, 400 } -- one level deep inside each biome
local sawKinds = {}
for _, L in LEVELS do
	local band = Biomes.band(EnvBands, L)
	ctx.startRun(L)
	local g = Lib.grid(ctx.folder())
	local mid = g.world(2 * (g.cols // 2) + 1, 2 * (g.rows // 2) + 1)
	ctx.moveTo(mid)
	ctx.run(2)
	local parts = critterParts()
	local n, kinds, slots = slotsOf(parts)
	local want = Biomes.crittersAt(EnvBands, L)
	local wantN = 0
	for _, k in want do wantN += k end
	do
		local names = {}
		for kind, count in kinds do table.insert(names, count .. " " .. kind) end
		table.sort(names)
		print(string.format("  %-17s L%-3d %d critters (%s), %d decor pieces", band.name, L, n, table.concat(names, ", "), decorPieces()))
	end
	truthy(n >= 1, string.format("%s L%d: critters are there (%d)", band.name, L, n))
	truthy(n <= B.MaxCritters, string.format("%s L%d: no more than MaxCritters (%d <= %d)", band.name, L, n, B.MaxCritters))
	local wrong = nil
	for kind, count in kinds do
		sawKinds[kind] = true
		if (want[kind] or 0) < count then wrong = wrong or kind end
	end
	truthy(wrong == nil, string.format("%s L%d: only this biome's critters (%s)", band.name, L, tostring(wrong)))
	-- every part: inert, not Neon, inside an open cell, not on a trap, near the player
	local bad = nil
	local hrpPos = ctx.hrp.Position
	for _, p in parts do
		if p.CanCollide or p.CanTouch or p.CanQuery or p.CastShadow then bad = bad or (p.Name .. " is not inert") end
		if p.Material == Enum.Material.Neon then bad = bad or (p.Name .. " glows") end
		local fx, fy = g.fine(p.Position)
		if g.walls[fx .. "," .. fy] then bad = bad or string.format("%s is inside a wall (%d,%d)", p.Name, fx, fy) end
		local cx, cy = (fx - 1) // 2, (fy - 1) // 2
		if fx % 2 == 1 and fy % 2 == 1 and g.traps[cx .. "," .. cy] then bad = bad or (p.Name .. " sits on a trap") end
		local dx, dz = p.Position.X - hrpPos.X, p.Position.Z - hrpPos.Z
		if math.sqrt(dx * dx + dz * dz) > B.DecorRadius + g.S then bad = bad or (p.Name .. " is beyond the torch") end
		if p.Position.Y < g.origin.Y or p.Position.Y > g.origin.Y + 24.5 then bad = bad or (p.Name .. " is under the floor or over the walls") end
	end
	truthy(bad == nil, string.format("%s L%d: every critter part is inert, unlit, in an open cell, off the traps, near the player%s",
		band.name, L, if bad then " -- " .. bad else ""))
	truthy(n + decorPieces() <= B.MaxDecorPieces, string.format("%s L%d: decor + critters within the decor cap (%d + %d <= %d)",
		band.name, L, decorPieces(), n, B.MaxDecorPieces))
	-- they move
	local before = {}
	for s, p in slots do before[s] = p.Position end
	ctx.run(1)
	local moved = 0
	for s, p in slots do
		if p.Parent and before[s] and (p.Position - before[s]).Magnitude > 0.05 then moved += 1 end
	end
	truthy(moved >= 1, string.format("%s L%d: they move (%d of %d in a second)", band.name, L, moved, n))
	ctx.toLobby()
end
local distinct = 0
for _ in sawKinds do distinct += 1 end
truthy(distinct >= 7, "seen across the eight biomes: " .. distinct .. " kinds of critter")

-- in the lobby: none
ctx.run(1)
local lobbyN = slotsOf(critterParts())
eq(lobbyN, 0, "back in the lobby, no critter is left behind")

-- the decor cap binds critters too: force a tiny cap in memory (the client reads Biomes.Budget live)
do
	local saved = B.MaxDecorPieces
	B.MaxDecorPieces = 2
	ctx.startRun(18)
	local g = Lib.grid(ctx.folder())
	ctx.moveTo(g.world(2 * (g.cols // 2) + 1, 2 * (g.rows // 2) + 1))
	ctx.run(2)
	local n = slotsOf(critterParts())
	truthy(n + decorPieces() <= 2, string.format("with the decor cap forced to 2, decor + critters stay within it (%d + %d)", decorPieces(), n))
	B.MaxDecorPieces = saved
	ctx.toLobby()
end

T.finish(h)
