-- Move.client.luau — low gravity in vacuum modules (DESIGN.md §8.1). Presentation of physics this client owns.
--
-- The server owns the numbers: it sets WalkSpeed (16 in air, 12 + Mag-Boots in vacuum) and JumpHeight (7.2 in air,
-- 1.8 in vacuum) on every module change, and every rule reads its own trusted position. The client owns its
-- character's physics, so the drift is here: in a vacuum module a VectorForce lifts VacGravityFactor's complement
-- of the character's weight (80 %), so a 1.8-stud jump rises to a 9-stud apex and drifts 16 studs. A client that
-- switches this off only jumps lower; the server's air arithmetic and speed cap do not care.
-- It fires no remote and sets no attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("SignalRemotes")
local StateEvent = remotes:WaitForChild("State")

local player = Players.LocalPlayer
local LIFT = 1 - Config.Move.VacGravityFactor

local vacuum = false
StateEvent.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	if s.uid ~= nil and s.uid ~= player.UserId then return end
	vacuum = s.phase == "sector" and s.moduleType == "vacuum"
end)

-- The character's mass: the engine's assembly mass, or (headless, where parts have none) a typical R15 avatar's.
local function massOf(root: BasePart): number
	local ok, m = pcall(function()
		return (root :: any).AssemblyMass
	end)
	if ok and type(m) == "number" and m > 0 then return m end
	return 13.5
end

local function forceOn(root: BasePart): VectorForce
	local vf = root:FindFirstChild("LowGravity")
	if vf and vf:IsA("VectorForce") then return vf end
	local at = root:FindFirstChild("LowGravityAt")
	if not at then
		at = Instance.new("Attachment")
		at.Name = "LowGravityAt"
		at.Parent = root
	end
	local f = Instance.new("VectorForce")
	f.Name = "LowGravity"
	f.Attachment0 = at :: Attachment
	f.RelativeTo = Enum.ActuatorRelativeTo.World
	f.ApplyAtCenterOfMass = true
	f.Enabled = false
	f.Parent = root
	return f
end

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local f = forceOn(root)
	local g = tonumber(workspace.Gravity) or 196.2
	local want = if vacuum then Vector3.new(0, massOf(root) * g * LIFT, 0) else Vector3.new(0, 0, 0)
	if f.Enabled ~= vacuum then f.Enabled = vacuum end
	if f.Force ~= want then f.Force = want end
end)
