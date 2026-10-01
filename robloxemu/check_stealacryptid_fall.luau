-- Steal a Cryptid - walking off the world at home costs nothing: the server catches the fall. Real server.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_fall.luau 2>&1
--
-- Owner decision (d), DECIDED 2026-09-30 (owner: take recommended): EYECANDY.md section 11 left "a server-side
-- world boundary" open. Invisible walls round the Ground were rejected (a collidable wall between a zoomed-out
-- camera and a cage can hide the cage's prompt; only Studio could settle it). A player who walked off the bluff
-- into the ravine fell to the engine's kill height and waited out a respawn: nothing lost, but a death. Now the
-- server's 10 Hz lair loop catches a character at home whose root is Config.World.FallRescueStuds below the
-- Ground's top and puts it back on its own arrival marker, still, with a toast. Never in a raid (a camp pocket
-- is the raid's: a fall there still ends the raid as a respawn always did).
--   F1 a player 20 studs down past the back edge, falling, is on their arrival marker within 0.25 s, at rest,
--      and told why;
--   F2 the same past every other side of the Ground, and just below the threshold;
--   F3 never above it: 10 s of standing, walking and jumping on the apron, a root 1 stud above the threshold:
--      no rescue, no toast;
--   F4 never in a raid: a raider dropped below the floor of a camp pocket is left to the raid.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-fall", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local W = Config.World
local DEPTH = W.FallRescueStuds
truthy(type(DEPTH) == "number" and DEPTH >= 8 and DEPTH <= 30, "Config.World.FallRescueStuds is 8..30 studs (" .. tostring(DEPTH) .. ")")
DEPTH = DEPTH or 12

assert(h:tryRun("server/Main.server"))
h:advance(1)
local R = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local plr = h:join("Faller", 7171)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
h:advance(1.5)
local ground = h.workspace.Road.Ground
local TOP = ground.Position.Y + ground.Size.Y / 2
local X0, X1 = ground.Position.X - ground.Size.X / 2, ground.Position.X + ground.Size.X / 2
local Z0, Z1 = ground.Position.Z - ground.Size.Z / 2, ground.Position.Z + ground.Size.Z / 2
local home = hrp.Position
print(string.format("  the Ground: x %.0f..%.0f, z %.0f..%.0f, top %.2f; home (arrival) %.1f, %.1f, %.1f; rescue below y %.2f",
	X0, X1, Z0, Z1, TOP, home.X, home.Y, home.Z, TOP - (DEPTH or 0)))
local function toasts()
	local out = {}
	for _, rec in R.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local T = W.FallRescueText

local function drop(p, label)
	local t0 = #toasts()
	hrp.CFrame = CFrame.new(p)
	hrp.AssemblyLinearVelocity = Vector3.new(3, -70, 5)
	h:advance(0.25)
	local d = (hrp.Position - home).Magnitude
	local ts = toasts()
	local told = #ts > t0 and (T == nil or ts[#ts] == T)
	return d < 0.05, hrp.AssemblyLinearVelocity.Magnitude < 1e-6, told, d
end

-- F1: the reviewer's ravine, behind the back edge
do
	local back, still, told, d = drop(Vector3.new(home.X, TOP - 20, Z1 + 10), "back edge")
	truthy(back, string.format("F1: 20 studs down past the back edge, back on the arrival marker within 0.25 s (%.2f studs off)", d))
	truthy(still, "F1: at rest (the fall's speed is gone)")
	truthy(told, "F1: and told why (a toast)")
	truthy(type(T) == "string" and #T <= 100, "F1: the rescue toast is Config.World.FallRescueText, at most 100 characters")
end

-- F2: every other side, and just past the threshold
do
	local spots = {
		{ Vector3.new(home.X, TOP - 20, Z0 - 10), "front edge" },
		{ Vector3.new(X0 - 10, TOP - 20, 0), "-x end" },
		{ Vector3.new(X1 - 10, TOP - 60, Z1 + 30), "+x corner, 60 down" },
		{ Vector3.new(home.X + 5, TOP - DEPTH - 0.05, Z1 + 3), "just past the threshold" },
	}
	for _, s in spots do
		local back, still, told = drop(s[1], s[2])
		truthy(back and still and told, "F2: " .. s[2] .. ": back home, at rest, told")
	end
end

-- F3: never above the threshold
do
	local t0 = #toasts()
	local moved = 0
	local pts = {
		home + Vector3.new(0, 7, 0), -- a jump
		home + Vector3.new(6, 0, 4),
		Vector3.new(home.X, TOP - DEPTH + 1, Z1 + 3), -- 1 stud above the threshold
		Vector3.new(home.X + 20, TOP + 3, home.Z + 30),
	}
	for i = 1, 100 do
		local p = pts[(i - 1) % #pts + 1]
		hrp.CFrame = CFrame.new(p)
		h:advance(0.1)
		if (hrp.Position - p).Magnitude > 1e-6 then moved += 1 end
	end
	eq(moved, 0, "F3: 10 s standing, walking, jumping and hanging 1 stud above the threshold: never moved")
	eq(#toasts(), t0, "F3: and no toast")
	hrp.CFrame = CFrame.new(home)
end

-- F4: never in a raid
do
	local st = R.State:sentTo(plr)
	local s = st[#st].args[1]
	-- the tutorial's first hunt is free: stand by the board and start one
	local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. s.plot)
	local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
	hrp.CFrame = CFrame.new(frameCF:PointToWorldSpace(Vector3.new(W.Apron.Board.x, W.RootHeight, W.Apron.Board.z - 4)))
	h:advance(0.2)
	R.Hunt:simulateFireServer(plr, 1)
	h:advance(0.1)
	local inPocket = hrp.Position.X > 3000
	truthy(inPocket, "F4: a hunt put the raider in a camp pocket (x " .. string.format("%.0f", hrp.Position.X) .. ")")
	if inPocket then
		local p = Vector3.new(hrp.Position.X, TOP - 20, hrp.Position.Z)
		hrp.CFrame = CFrame.new(p)
		h:advance(0.25)
		truthy(hrp.Position.X > 3000, "F4: below a camp's floor the rescue leaves the raider to the raid (not sent home)")
	end
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
print(string.format("\nsteal a cryptid fall: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid fall check failed", 0) end
