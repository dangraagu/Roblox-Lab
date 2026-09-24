-- +1 Jump Every Step — the sky stays alive and never cuts. Run: luau check_plus1jump_life.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Resume-session probe sweep (2026-09-17, after the pause): three promises in EYECANDY.md survived a
-- mutation that broke them, so no suite held them:
--   R13 "critters are pooled per kind ... recycled when they leave range": with recycling switched off
--       the birds fly away once and the sky goes empty, and every suite stayed green;
--   R8  "a jump in altitude (the fall rescue, a rebirth back to the pad, joining at tier 90) also glides":
--       with the band weights snapping, the temple island vanished and the Earth appeared in ONE frame,
--       and every suite stayed green (check_plus1_sky only measured the Lighting glide);
--   R11 "a soft suit light on the character once the sky goes dark": never lit, every suite green.
-- This file holds all three through the real server and the real client scripts.
--
-- Headless limits: nothing renders. "Alive" = critter parts parented and within the range SkyArt keeps
-- them in; "glides" = the parts' Transparency written frame by frame.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local Progression = mod("Progression")
local Tower = Config.Tower
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001 -- no hazards: this file is about the sky

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0) -- climbing input: never idles into rest
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds, dt)
	dt = dt or 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do frame(dt) end
end
local function standAt(p)
	hrp.CFrame = CFrame.new(0, Progression.yAtProgress(p, Tower) + 3.5, 0)
end

--======================================================================= R13: critters keep coming back

-- Parented critter parts named `partName` within the range SkyArt keeps a critter of `kind` alive in.
local function critterCount(kind, partName)
	local spec = Config.Env.Critters[kind]
	local c = cam.CFrame.Position
	local n = 0
	for _, p in folder:GetChildren() do
		if p.Name == partName and p:IsA("BasePart") then
			local d = p.Position - c
			local horizontal = Vector3.new(d.X, 0, d.Z).Magnitude
			if horizontal <= spec.rMax * 1.35 and d.Y >= spec.yMin - 250 and d.Y <= spec.yMax + 250 then
				n += 1
			end
		end
	end
	return n
end

do
	-- treetops: birds (count 10) fly 16-26 studs/s across a ring of 70-260 studs; any one of them is out of
	-- range within ~20 s, so after 90 s a sky that does not recycle has none left near the climber
	standAt(9)
	run(30)
	local lowest, total, samples = math.huge, 0, 0
	for _ = 1, 60 do
		run(1)
		local n = critterCount("bird", "WingL")
		lowest = math.min(lowest, n)
		total += n
		samples += 1
	end
	print(string.format("  treetops, 30-90 s: birds in range lowest %d, average %.1f (band asks for %d)", lowest,
		total / samples, Config.Env.Bands[2].ambient[1].count))
	truthy(lowest >= 1, "birds never disappear from around a climber who stays in the treetops for 90 s (lowest " .. lowest .. ")")
	truthy(total / samples >= 6, string.format("and there are about as many as the band asks for (average %.1f)", total / samples))
end

do
	-- cloud sea: climb 10 tiers (~2 600 studs) in one go; the balloons left below must be recycled up here
	standAt(17)
	run(20)
	local before = critterCount("balloon", "Envelope")
	truthy(before >= 2, "set-up: hot-air balloons around the climber at tier 17 (" .. before .. ")")
	standAt(27)
	run(1)
	local recovered = nil
	for i = 1, 60 do
		run(0.1)
		if critterCount("balloon", "Envelope") >= 2 then recovered = 1 + i * 0.1; break end
	end
	print(string.format("  cloud sea, climbed 17 -> 27 tiers: balloons back around the climber after %s s", tostring(recovered)))
	truthy(recovered ~= nil and recovered <= 5, "after a big climb the balloons are back around the climber within 5 s (" .. tostring(recovered) .. ")")
end

--======================================================================= R8: scenery glides on a teleport

local function findPart(name, size)
	for _, p in folder:GetChildren() do
		if p.Name == name and p:IsA("BasePart") and (size == nil or math.abs(p.Size.X - size) < 1) then return p end
	end
	return nil
end
-- Transparency as the player sees it: an unparented part is invisible (1)
local function seen(name, size)
	local p = findPart(name, size)
	if p == nil then return 1 end
	return p.Transparency
end

local function glide(fromP, toP, arriving, arrivingSize, leaving, leavingSize, label)
	standAt(fromP)
	run(8, 1 / 30)
	truthy(seen(leaving, leavingSize) <= 0.02 and seen(arriving, arrivingSize) >= 0.99,
		label .. ": set-up: " .. leaving .. " fully shown, " .. arriving .. " not")
	standAt(toP)
	local prevA, prevL = seen(arriving, arrivingSize), seen(leaving, leavingSize)
	local worstStep, firstA, firstL = 0, nil, nil
	for i = 1, 6 * 30 do
		frame(1 / 30)
		local a, l = seen(arriving, arrivingSize), seen(leaving, leavingSize)
		if i == 1 then firstA, firstL = a, l end
		worstStep = math.max(worstStep, math.abs(a - prevA), math.abs(l - prevL))
		prevA, prevL = a, l
	end
	print(string.format("  %-34s first frame: %s %.3f, %s %.3f; largest change in one frame %.3f; after 6 s: %.3f / %.3f",
		label, arriving, firstA, leaving, firstL, worstStep, prevA, prevL))
	truthy(firstA >= 0.85, label .. ": the frame after the jump, " .. arriving .. " has only begun to fade in (" .. string.format("%.3f", firstA) .. ")")
	truthy(firstL <= 0.15, label .. ": and " .. leaving .. " is still there, fading out (" .. string.format("%.3f", firstL) .. ")")
	truthy(worstStep <= 0.1, label .. ": no scenery changes by more than 0.1 transparency in one frame: a glide, not a cut ("
		.. string.format("%.3f", worstStep) .. ")")
	truthy(prevA <= 0.02 and prevL >= 0.99, label .. ": after 6 s the new band's scenery is fully in and the old one gone")
end

-- joining at / climbing into space in one jump of altitude, and a rebirth back to the pad
glide(1, 100, "Planet", 2048, "IslandGrass", nil, "temple -> orbit (join / teleport)")
glide(100, 1, "IslandGrass", nil, "Planet", 2048, "orbit -> temple (rebirth to the pad)")

--======================================================================= R11: the suit light

do
	local function light()
		return hrp:FindFirstChild("Plus1SuitLight")
	end
	standAt(1)
	run(6)
	local l = light()
	truthy(l ~= nil and l.ClassName == "PointLight", "the client gives its own character a suit light")
	truthy(l ~= nil and l.Brightness <= 0.05, "in the afternoon temple sky it is off (" .. tostring(l and l.Brightness) .. ")")
	standAt(45)
	run(6)
	truthy(light() ~= nil and light().Brightness <= 0.05, "still off at sunset in the storm (" .. tostring(light() and light().Brightness) .. ")")
	standAt(100)
	run(6)
	truthy(light() ~= nil and light().Brightness >= 1, "in space it lights the climber so the tower still reads at night ("
		.. tostring(light() and light().Brightness) .. ")")
	truthy(light() ~= nil and light().Shadows == false, "without shadows (cheap on a phone)")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump life: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump life check failed", 0)
end
