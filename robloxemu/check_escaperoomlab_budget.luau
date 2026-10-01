-- Escape Room Lab — the local part budget is CAPPED IN CODE, not only kept small by the config.
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_budget.luau 2>&1
--
-- check_escaperoomlab_env measures the shipped config over all 15 rooms (a maximum of 53 local parts
-- against a cap of 120). That proves the config is small; it does not prove the cap. So here the cap
-- is lowered IN MEMORY to 20 (12 for everything cosmetic + the 8-part hazard reserve), below what a
-- Greenhouse room with a hazard wants (2 weather hosts, the
-- guide arrow, 14 decor pieces, 5 butterflies of 2 parts, up to 5 hazard parts), and the real client
-- must never exceed it on any frame, must keep running without an error, and must still draw the
-- things a player needs: the red ring of a hazard.

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local best = {}
for s = 1, 6 do best[tostring(s)] = 3 end
local w = Lib.boot({ name = "escape-room-lab-budget", preload = { [4401] = { best = best, starsAt = 1790800000, boarded = 18, rooms = 6 } } })
local h, ws = w.h, w.ws
local Config = w.Config
Config.Budget.LocalParts = 20 -- in memory, this run only
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 9, 10
local p = Lib.player(w, "Tight", 4401)
h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Lab.client"))
local RunService = h.game:GetService("RunService")
local cam = ws.CurrentCamera
local env = ws.LabLocalEnv
local maxParts, frames, ringSeen = 0, 0, false
local function frame(dt)
	cam.CFrame = CFrame.new(p.hrp.Position + Vector3.new(0, 4, 10), p.hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	frames += 1
	local n = 0
	for _, d in env:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	maxParts = math.max(maxParts, n)
	if env:FindFirstChild("HazardRing") then ringSeen = true end
	p.hrp.AssemblyLinearVelocity = Vector3.zero
end
local function run(sec) for _ = 1, math.floor(sec * 10 + 0.5) do frame(0.1) end end

Lib.intoSoloLift(w, p)
run(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
local rs = Lib.last(w, "RoomState", p.plr)
eq(rs and rs.slot, 7, "the frontier took the player to room 7, the Greenhouse")
p.hrp.CFrame = CFrame.new(Lib.origin(w, p.plr) + Vector3.new(0, 3, 0))
run(40)
print(string.format("  %d frames in the Greenhouse with the cap at 20: at most %d local parts", frames, maxParts))
truthy(maxParts <= 20, "never more local parts than the cap, on any frame")
truthy(maxParts >= 12, "and the budget was actually under pressure (" .. maxParts .. " parts)")
truthy(ringSeen, "a hazard still drew its ring inside the budget")
eq(#h.warnings, 0, "no frame error was warned")
t.finish("escape-room-lab budget", h)
