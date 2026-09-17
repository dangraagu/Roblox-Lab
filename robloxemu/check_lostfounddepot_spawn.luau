-- Lost & Found Depot — where a joining character LANDS, under the engine's real spawn order.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_spawn.luau
--
-- SPAWN-ORDER.md is the governing document: CharacterAdded fires while the character is
-- UNPARENTED at the origin, and one frame later the engine parents it AND drops it on a
-- SpawnLocation, discarding any CFrame written in between. With no enabled SpawnLocation it lands
-- on the highest ground over the origin — on a sealed shell, the roof.
--
-- The game uses both real patterns at once (DESIGN.md §9): `plr.RespawnLocation = <own BayPad>`
-- set synchronously at the head of PlayerAdded, AND a bounded wait for `char.Parent` followed by a
-- re-place if the root part is not inside the bay. The two halves are REDUNDANT by design, so a
-- mutation removing either one alone is expected to stay green here; only removing both must go
-- red. The sweep that proves that runs against copies of the source, not from inside this file.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-spawn" })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- A player who is ALREADY in the server with a character when the script starts: CharacterAdded
-- will not fire for that character again, so PlayerAdded's own `if plr.Character` branch has to
-- place it (the plus1-jump shape no check exercised).
local early = h:join("Early", 7001)
h.Players:simulateSpawn(early, h.workspace)

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot spawn: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))

local function enabledSpawns()
	local out = {}
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled ~= false then table.insert(out, d) end
	end
	return out
end

-- Where is this root part, in which bay's interior (by the pad the bay was built around)?
local function bayContaining(pos)
	local bays = h.workspace:FindFirstChild("Bays")
	for _, bay in bays:GetChildren() do
		local pad = bay:FindFirstChild("BayPad")
		local ox = pad.Position.X
		local x, z = pos.X - ox, pos.Z
		if x >= Config.Bay.MinX and x <= Config.Bay.MaxX and z >= Config.Bay.MinZ and z <= Config.Bay.MaxZ
			and pos.Y > 0 and pos.Y < Config.Bay.WallHeight then
			return bay
		end
	end
	return nil
end

local function ownBay(plr)
	local pad = plr.RespawnLocation
	return pad and pad.Parent
end

local function hrp(plr)
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

local function landed(plr, label)
	local root = hrp(plr)
	local inBay = root and bayContaining(root.Position)
	truthy(inBay ~= nil and inBay == ownBay(plr), string.format("%s lands inside their own bay (root at %s, in %s, own %s)",
		label, root and tostring(root.Position) or "nil", inBay and inBay.Name or "no bay",
		ownBay(plr) and ownBay(plr).Name or "none"))
	if root and inBay then
		local pad = inBay:FindFirstChild("BayPad")
		local dx = math.abs(root.Position.X - pad.Position.X)
		local dz = math.abs(root.Position.Z - pad.Position.Z)
		truthy(dx <= pad.Size.X / 2 and dz <= pad.Size.Z / 2, string.format("... on their pad (off by %.2f, %.2f)", dx, dz))
		truthy(root.Position.Y > pad.Position.Y + pad.Size.Y / 2 and root.Position.Y < pad.Position.Y + 6,
			string.format("... standing on it, not in it or above the walls (y %.2f)", root.Position.Y))
	end
end

--============================================================ before any new join

do
	-- `early` holds one bay; every other pad must be off.
	local list = enabledSpawns()
	local names = {}
	for _, s in list do table.insert(names, s:GetFullName()) end
	table.sort(names)
	eq(#list, 2, "with one player seated: the Break Room spawn and that player's pad are the only enabled spawns")
	truthy(table.find(names, "Workspace.BreakRoom.StaffEntrance") ~= nil, "the Break Room spawn is always enabled")
	landed(early, "a player already present when the server script started")
end

--============================================================ an ordinary join

local a = h:join("Alpha", 7002)
eq(ownBay(a) ~= nil and ownBay(a):FindFirstChild("BayPad").Enabled, true,
	"RespawnLocation is set and its pad enabled BEFORE the character exists")
h.Players:simulateSpawn(a, h.workspace)
h:advance(0.5)
landed(a, "a fresh join")
h.Players:simulateSpawn(a, h.workspace)
h:advance(0.5)
landed(a, "the same player after a second spawn (a reset)")

--============================================================ two in one frame

local b = h:join("Bravo", 7003)
local c = h:join("Charlie", 7004)
truthy(ownBay(b) ~= nil and ownBay(c) ~= nil and ownBay(b) ~= ownBay(c), "two players joining in one frame claim different bays")
h.Players:simulateSpawn(b, h.workspace)
h.Players:simulateSpawn(c, h.workspace)
h:advance(0.5)
landed(b, "the first of a same-frame pair")
landed(c, "the second of a same-frame pair")
do
	local rb, rc = hrp(b), hrp(c)
	truthy(rb and rc and (rb.Position - rc.Position).Magnitude > 60, "... and they stand in different bays, not on one pad")
end

--============================================================ leave and rejoin recycles

do
	local bayB = ownBay(b)
	h:leave(b)
	h:advance(0.5)
	eq(bayB:FindFirstChild("BayPad").Enabled, false, "a freed bay's pad is disabled while it is free")
	local d = h:join("Delta", 7005)
	eq(ownBay(d), bayB, "the next join recycles the freed bay (lowest free index)")
	h.Players:simulateSpawn(d, h.workspace)
	h:advance(0.5)
	landed(d, "a player in a recycled bay")
end

--============================================================ a character that arrives late

do
	-- The engine's placement happens inside simulateSpawn. A game that only relied on writing the
	-- CFrame inside CharacterAdded would lose here; one that waits for char.Parent wins.
	local e = h:join("Echo", 7006)
	-- Point the RespawnLocation somewhere wrong on purpose, as if the engine's first spawn had won
	-- the race against PlayerAdded: the bounded wait + re-place has to bring them home.
	local own = ownBay(e)
	e.RespawnLocation = h.workspace:FindFirstChild("BreakRoom"):FindFirstChild("StaffEntrance")
	h.Players:simulateSpawn(e, h.workspace)
	h:advance(0.5)
	local root = hrp(e)
	local inBay = root and bayContaining(root.Position)
	eq(inBay, own, "a character the engine dropped in the Break Room is walked home to its own bay by the re-place")
	e.RespawnLocation = own:FindFirstChild("BayPad")
end

--============================================================ nobody on a roof

do
	local roofs = 0
	for _, plr in h.Players:GetPlayers() do
		local root = hrp(plr)
		if root and root.Position.Y > Config.Bay.WallHeight then roofs += 1 end
	end
	eq(roofs, 0, "no character is above any wall")
	eq(#h:errors(), 0, "no spawn handler thread died")
	for _, err in h:errors() do print("scheduler error: " .. err) end
end

print(string.format("lost-found-depot spawn: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot spawn check failed", 0) end
