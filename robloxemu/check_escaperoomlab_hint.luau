-- Escape Room Lab — a Lamp Grid hint through the REAL HUD on a touch phone (review 2026-10-01).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_hint.luau 2>&1
--
-- A lamp hint names ONE lamp to press. Before the fix the ring around that lamp and the "Hint: ..."
-- banner stayed after the player pressed it, inviting a second press that undid the move. Now:
--   * the hint rings exactly the lamp the server named, and the banner reads it;
--   * pressing that lamp clears the ring and the banner goes back to the rule;
--   * pressing the hinted lamp is one step closer: the presses left drop by one;
--   * the hint is only on the taker's screen (no other overlay, nothing in the world).

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/escape-room-lab"), name = "escape-room-lab-hint", viewport = { 800, 360 }, touch = true })
local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b)) end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS, ws = h.ReplicatedStorage, h.workspace
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Lamps, Text = mod("Config"), mod("Lamps"), mod("Text")
local W = Config.World
local R = {}
for _, n in { "Act", "RoomState", "Notice", "Profile", "Open", "Hint" } do R[n] = RS.LabRemotes:FindFirstChild(n) end
local plr = h:join("Hinter", 4712)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Lab.client"))
local RunService = h.game:GetService("RunService")
local hud = plr.PlayerGui.LabHud.Root
local overlay = hud.Overlay
local banner = hud.Banner
local function frame(dt) RunService.RenderStepped:Fire(dt); h:advance(dt) end
local function wait(s) for _ = 1, math.ceil(s / 0.1) do frame(0.1) end end
local function last(r) local s = r:sentTo(plr); return s[#s] and s[#s].args[1] end

hrp.CFrame = CFrame.new(W.SoloCab[1], 3.5, W.SoloCab[2])
wait(5)
local rs = last(R.RoomState)
eq(rs and rs.slot, 1, "a new player's Solo Lift goes to room 1")
eq(rs and rs.stations[1].kind, "lamp", "room 1's feeder is a Lamp Grid")
local o = Vector3.new(rs.origin[1], rs.origin[2], rs.origin[3])
hrp.CFrame = CFrame.new(o + Vector3.new(W.Stations.A[1] * 0.78, 3, 0))
local zone = nil
for _, z in ws.Zones:GetChildren() do if z:FindFirstChild("DoorBoard", true) then zone = z end end
zone:FindFirstChild("Station_A", true):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
frame(0.1)
eq(overlay.Visible, true, "the Lamp Grid overlay opens")
local n = rs.stations[1].size
local function rings()
	local out = {}
	for i = 1, n * n do
		local b = overlay:FindFirstChild("Lamp_" .. i, true)
		if b and b:FindFirstChildOfClass("UIStroke") then table.insert(out, i) end
	end
	return out
end
local function pressesLeft()
	local g = {}
	for i, v in last(R.RoomState).stations[1].lamps do g[i] = v end
	return #Lamps.solve(g, n)
end
eq(#rings(), 0, "no ring before a hint")
local before = pressesLeft()
overlay:FindFirstChild("HintButton", true).Activated:Fire()
frame(0.1)
local hint = last(R.Hint)
truthy(hint and type(hint.lamp) == "number", "the server answers with one lamp")
local r1 = rings()
eq(#r1, 1, "one lamp is ringed")
eq(r1[1], hint and hint.lamp, "the ringed lamp is the one the server named")
eq(banner.Text, "Hint: " .. tostring(hint and hint.text), "the banner reads the hint")
print(string.format("  hint: %s (lamp %s); presses left %d", tostring(hint and hint.text), tostring(hint and hint.lamp), before))
overlay:FindFirstChild("Lamp_" .. tostring(hint and hint.lamp), true).Activated:Fire()
frame(0.2)
-- room 1's grid needs 2 presses (Config: lamp(3, 2)) and a hint names a press of a shortest solution
eq(before, 2, "room 1's grid needs 2 presses")
eq(last(R.RoomState).stations[1].solved, false, "one press in, the grid is not solved yet")
eq(#rings(), 0, "after pressing the hinted lamp, no ring is left to press again")
eq(banner.Text, Text.LampRule, "and the banner is back to the rule")
eq(pressesLeft(), before - 1, "the hinted press was one step closer")
-- the hint is the taker's only: nothing about it in the world
local leaked = false
for _, d in ws:GetDescendants() do
	if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and hint and d.Text == hint.text then leaked = true end
end
eq(leaked, false, "the hint text is nowhere in the world")
for _, e in h:errors() do failed += 1; print("FAIL: scheduler error: " .. e) end
print(string.format("escape-room-lab hint: %d passed, %d failed", passed, failed))
if failed > 0 then error("escape-room-lab hint failed", 0) end
