-- Grow a Crystal — where a spawning player ACTUALLY ends up, and WHICH WAY THEY FACE.
-- Run: luau check_crystal_spawn.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- ---------------------------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
-- Measured in Roblox Studio on 2026-09-10 (fork-tower/STUDIO.md, quoted in robloxemu/SPAWN-ORDER.md):
--
--     [0.0000] f01 parent=nil        hrp=0.00,0.00,0.00     <- CharacterAdded fires HERE
--     [0.0051] f02 parent=Workspace  hrp=0.00,3.51,-160.00  <- one frame later: parent AND place
--
-- Player.CharacterAdded fires while the character Model is still UNPARENTED with its
-- HumanoidRootPart at the world origin. ONE FRAME LATER the engine parents it and places it on
-- the spawn — discarding, silently, whatever CFrame the handler wrote in between.
--
-- Grow a Crystal's spawn handler wrote the CFrame and then wrote it AGAIN from a `task.defer`,
-- with the comment "the engine finishes placing a spawning character after this handler returns,
-- and whichever write lands last wins; doing it twice makes that us." That reasoning is wrong
-- about the engine, in the direction that looks safe: `task.defer` resumes at the END OF THE
-- CURRENT RESUMPTION CYCLE — still inside f01 — and the engine's step is f02, strictly after it.
-- So the deferred write is discarded exactly like the first one.
--
-- ---------------------------------------------------------------------------------------------
-- WHY THIS FILE REPLAYS THE ORDER BY HAND INSTEAD OF JUST CALLING simulateSpawn
--
-- `Players:simulateSpawn` now models the parent/place ORDER correctly, but it drains the
-- deferred queue INSIDE `sched:advance`, which it calls AFTER its engine step — so a deferred
-- write survives there and is discarded in Roblox. Measured, on this game, on the same build:
--
--     simulateSpawn      -> pos (0.00, 4.00, -6.00)   look (0.00, 0.00,  1.00)   <- game won
--     recorded order     -> pos (80.00, 3.01, -6.00)  look (0.00, 0.00, -1.00)   <- engine won
--
-- Same code, same bundle, opposite answers. So a check that only calls simulateSpawn cannot see
-- a task.defer-based placement fail, and this file replays the recorded order itself — the same
-- thing check_forktower.luau does for its STUDIO FINDING block. Both paths are asserted below:
-- a correct fix has to survive the engine's order, and must not regress the ordinary one.

local Harness = require("./emu/harness")
local Datatypes = require("./emu/datatypes")

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})

local inst = h.instance
local sched = h.scheduler

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end
local function near(a, b, tol, msg)
	if math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %.3f, want %.3f (+/- %.3f)", msg, a, b, tol))
	end
end
local function fmtV(v) return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z) end

-- The one placement constant the emulator fits from the single recorded Studio sample: the root
-- part lands this far above the spawn brick's TOP FACE. Repeated here (rather than reached into
-- emu/) so this file states the number it is asserting against.
local ENGINE_STAND_OFFSET = 2.51

local function descendants(root, out)
	out = out or {}
	for _, c in inst.stateOf(root).children do
		table.insert(out, c)
		descendants(c, out)
	end
	return out
end

local function padOf(plr)
	local want = "Spawn_" .. tostring(plr.UserId)
	for _, d in descendants(h.workspace) do
		if d.ClassName == "SpawnLocation" and d.Name == want then return d end
	end
	return nil
end

-- The nearest planting socket belonging to this player: what "facing into the cavern" MEANS.
local function nearestSocket(plr, from)
	local prefix = "Socket_" .. tostring(plr.UserId) .. "_"
	local best, bestD = nil, math.huge
	for _, d in descendants(h.workspace) do
		if string.sub(tostring(d.Name), 1, #prefix) == prefix then
			local dist = (d.Position - from).Magnitude
			if dist < bestD then best, bestD = d, dist end
		end
	end
	return best, bestD
end

local function hrpOf(plr)
	local char = plr.Character
	if char == nil then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

-- Every placement assertion, in one place, so both spawn paths are held to the same bar.
local function assertLandedInCavern(tag, plr)
	local pad = padOf(plr)
	local hrp = hrpOf(plr)
	truthy(pad ~= nil, tag .. ": the player has a SpawnLocation of their own")
	truthy(hrp ~= nil, tag .. ": the character has a HumanoidRootPart")
	if pad == nil or hrp == nil then return end

	local cf = hrp.CFrame
	local pos, look = cf.Position, cf.LookVector
	print(string.format("  %s: pos=(%s) look=(%s)", tag, fmtV(pos), fmtV(look)))

	-- The game's own contract, from Main.server.luau: `spawnPad.Position = at - (0, 4, 0)`,
	-- "the pad is under the feet, not at the root". So the root belongs 4 studs above the pad.
	near(pos.X, pad.Position.X, 0.05, tag .. ": stands on the X of their own pad")
	near(pos.Z, pad.Position.Z, 0.05, tag .. ": stands on the Z of their own pad")
	near(pos.Y, pad.Position.Y + 4, 0.05, tag .. ": stands 4 studs above their own pad")

	-- Facing. The identity frame looks down -Z, which in this cavern is the entrance wall six
	-- studs behind you with the whole plot at your back. Asserted against the sockets' real
	-- positions rather than against a hard-coded axis, so it stays true if the cavern is rotated.
	local socket, dist = nearestSocket(plr, pos)
	truthy(socket ~= nil, tag .. ": the plot has sockets to face")
	if socket ~= nil then
		local to = (socket.Position - pos)
		local flat = Datatypes.Vector3.new(to.X, 0, to.Z)
		local dot = look.X * flat.Unit.X + look.Z * flat.Unit.Z
		print(string.format("    nearest socket %.1f studs away, facing dot = %.2f", dist, dot))
		truthy(dot > 0.5, tag .. ": faces INTO the cavern, not at the entrance wall")
	end
end

assert(h:tryRun("server/Main.server"))
h:advance(1)

--=================================================================== 1. the engine's recorded order
-- A respawn: the character loads with the handler already connected, so this is the racing path
-- every death takes and every join whose character arrives after onPlayerAdded has finished.
print("1. CharacterAdded -> task.defer -> engine parents and places (the recorded Studio order)")
do
	local plr = h:join("Racer", 9101)
	h:advance(1)

	-- f01: the model is built UNPARENTED with the root at the world origin, Player.Character is
	-- set, and CharacterAdded fires — one fresh thread per connection, as Roblox does.
	local char = inst.Instance.new("Model")
	char.Name = "Racer"
	local hrp = inst.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Parent = char
	local hum = inst.Instance.new("Humanoid")
	hum.Parent = char
	char.PrimaryPart = hrp
	hrp.CFrame = Datatypes.CFrame.new(0, 0, 0)
	plr.Character = char

	local sig = inst.stateOf(plr).signals["CharacterAdded"]
	truthy(sig ~= nil, "the server connected something to CharacterAdded")
	if sig ~= nil then
		sig:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, char)
	end

	-- end of f01's resumption cycle: this is where task.defer callbacks run, and they run while
	-- the model is STILL UNPARENTED.
	sched:advance(0)
	truthy(char.Parent == nil, "the character is still unparented when the deferred queue drains")

	-- f02: the engine parents the model AND places it on the player's RespawnLocation.
	local pad = padOf(plr)
	char.Parent = h.workspace
	if pad ~= nil then
		local top = pad.Position.Y + pad.Size.Y / 2
		hrp.CFrame = Datatypes.CFrame.new(pad.Position.X, top + ENGINE_STAND_OFFSET, pad.Position.Z)
	end

	-- f03 onwards: anything the game scheduled for after the engine step gets to run.
	h:advance(1)
	assertLandedInCavern("engine order", plr)
end

--============================================================ 2. the ordinary emulator spawn path
print("2. the same player state through Players:simulateSpawn")
do
	local plr = h:join("Ordinary", 9102)
	h:advance(1)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(1)
	assertLandedInCavern("simulateSpawn", plr)
end

--=================================================== 3. the pad itself, and why it is load-bearing
print("3. the SpawnLocation the engine is steered to")
do
	local plr = h:join("Padded", 9103)
	h:advance(1)
	local pad = padOf(plr)
	truthy(pad ~= nil, "onPlayerAdded builds a SpawnLocation for the joining player")
	if pad ~= nil then
		truthy(pad.Enabled ~= false, "the pad is enabled, so the engine will actually use it")
		truthy(plr.RespawnLocation == pad, "the pad is this player's RespawnLocation")
		truthy(pad:IsDescendantOf(h.workspace), "the pad is in the workspace, not an orphan")
	end

	-- Load-bearing, not decorative. With no eligible SpawnLocation the engine drops the character
	-- above the HIGHEST ground over the origin — which on this sealed 48-stud shell is the ROOF.
	-- That is the bug this pad was added to fix; this asserts the fall-back is still the roof, so
	-- deleting the pad can never look harmless.
	--
	-- Measured on a player the server has never heard of (no PlayerAdded, so no placement handler
	-- of the game's own), because the point is what the ENGINE does when nothing steers it.
	local ceilY = nil
	for _, d in descendants(h.workspace) do
		if d:IsA("BasePart") and string.match(tostring(d.Name), "^Ceil") then
			local top = d.Position.Y + d.Size.Y / 2
			if ceilY == nil or top > ceilY then ceilY = top end
		end
	end
	truthy(ceilY ~= nil, "the cavern has a roof")

	for _, d in descendants(h.workspace) do
		if d.ClassName == "SpawnLocation" then d.Enabled = false end
	end
	local naked = inst.Instance.new("Player")
	naked.Name = "Unsteered"
	naked.UserId = 9104
	naked.Parent = h.Players
	h.Players:simulateSpawn(naked, h.workspace)
	h:advance(1)
	local nhrp = hrpOf(naked)
	if nhrp ~= nil and ceilY ~= nil then
		print(string.format("  with every spawn disabled the engine lands them at y=%.2f (roof top y=%.2f)",
			nhrp.CFrame.Position.Y, ceilY))
		truthy(nhrp.CFrame.Position.Y > ceilY,
			"with no spawn the engine puts them ON THE ROOF — the pad is what prevents that")
	end
end

--============================================ 4. the OTHER path: the character loaded first
-- onPlayerAdded yields on the DataStore before it connects anything, so on a real join the
-- character usually already exists by the time the server catches up — hence
-- `if plr.Character then place(plr.Character) end`. That call runs on onPlayerAdded's own thread,
-- so a placement fix that waits must not park it: the character here is ALREADY in the world.
print("4. the character that loaded before onPlayerAdded caught up")
do
	local plr = inst.Instance.new("Player")
	plr.Name = "Early"
	plr.UserId = 9105
	plr.Parent = h.Players
	local pg = inst.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = plr

	local char = inst.Instance.new("Model")
	char.Name = "Early"
	local hrp = inst.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Parent = char
	local hum = inst.Instance.new("Humanoid")
	hum.Parent = char
	char.PrimaryPart = hrp
	char.Parent = h.workspace -- the engine has already finished with it
	hrp.CFrame = Datatypes.CFrame.new(0, 50.51, 0) -- ...on the roof, where an unsteered spawn lands

	plr.Character = char
	local before = sched:now()
	inst.fireIfExists(h.Players, "PlayerAdded", plr)
	local cost = sched:now() - before
	print(string.format("  onPlayerAdded returned after %.4f s of virtual clock", cost))
	truthy(cost < 0.5, "onPlayerAdded does not park waiting for a character that is already here")
	h:advance(1)
	assertLandedInCavern("direct call", plr)
end

print(string.format("crystal spawn: %d passed, %d failed", passed, failed))
for _, e in h:errors() do print("  scheduler error: " .. e) end
