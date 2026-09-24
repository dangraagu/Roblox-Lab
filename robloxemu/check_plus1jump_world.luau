-- +1 Jump Every Step — the sky's scenery never gets in the climber's way. Run: luau check_plus1jump_world.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17:
--   finding 4: the storm deck is world-fixed clouds tiled by a hash. For WorldSeed 20260905 one of them
--     (radius 121, Transparency 0.08, dark grey) sat on tier 42: the next platform P_42_5 was INSIDE it
--     and hidden from a camera below-behind a climber on P_42_4. Every climber jumped blind there.
--   finding 5: the temple island looked like ground but was non-collidable, with its grass top under
--     the rescue line but above where a falling player is when the rescue poll fires. 89% of players who
--     stepped off the pad sank through the grass before the teleport.
-- Both are measured here against what the REAL server builds and what the REAL client places.
--
-- Headless limits: no rendering, no physics. A fall is simulated by moving the root part under gravity
-- (196.2) each frame while the server's own rescue loop runs; the network allowance comes from Config.

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
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001 -- no hazards here
Tower.StreamAhead = 52 -- the server builds the tower through both cloud decks at join (in-memory only)

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local towerFolder = h.workspace:FindFirstChild("Tower")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local camAt = nil -- function() -> CFrame, or nil for the default follow camera
local function frame(dt)
	cam.CFrame = if camAt then camAt() else CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds, dt) for _ = 1, math.floor(seconds / dt + 0.5) do frame(dt) end end

--======================================================================= finding 5: the island is below any rescue

do
	run(2, 1 / 30) -- at the pad: the temple band builds the island
	local grass = nil
	for _, c in folder:GetChildren() do
		if c.Name == "IslandGrass" then grass = c end
	end
	truthy(grass ~= nil, "the temple island is shown at the start")
	-- the grass disc is a Cylinder stood upright: its height is Size.X
	local grassTop = grass and (grass.Position.Y + grass.Size.X / 2) or math.huge
	local g = Config.Pacing.Gravity
	local latency = Config.Pacing.RescueLatencySeconds or 0
	local worstFeet, worstPhase, rescues = math.huge, nil, 0
	for k = 0, 7 do
		-- stand on the pad, then walk off at a different phase of the server's 0.4 s rescue poll
		hrp.CFrame = CFrame.new(0, Tower.BaseY + 3, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		run(0.05 * k + 0.5, 1 / 60)
		local x0, y0 = 20, Tower.BaseY + 3
		local t, rescuedAt, prevY = 0, nil, y0
		for _ = 1, 60 * 5 do
			t += 1 / 60
			hrp.CFrame = CFrame.new(x0, y0 - 0.5 * g * t * t, 0)
			local before = hrp.Position.Y
			h:advance(1 / 60)
			if hrp.Position.Y > before + 1 then
				rescuedAt = t
				break
			end
			prevY = before
		end
		if rescuedAt then
			rescues += 1
			-- where the CLIENT's character is when the teleport reaches it: later by the network allowance
			local tc = rescuedAt + latency
			local feet = y0 - 0.5 * g * tc * tc - 3
			if feet < worstFeet then worstFeet, worstPhase = feet, k end
		end
	end
	eq(rescues, 8, "the server's rescue caught every walk-off (8 phases of its poll)")
	print(string.format("  walk-off: lowest feet when the teleport lands (with %.1f s network allowance) y = %.1f; island grass top y = %.1f",
		latency, worstFeet, grassTop))
	truthy(worstFeet > grassTop + 5, string.format("nobody sinks into the island: the lowest rescue (phase %s) is %.1f studs above the grass",
		tostring(worstPhase), worstFeet - grassTop))
	hrp.CFrame = CFrame.new(0, Tower.BaseY + 3, 0)
	run(1, 1 / 30)
end

--======================================================================= finding 4: decks keep off the tower

local function platform(t, i)
	return towerFolder:FindFirstChild("P_" .. t .. "_" .. i)
end
local function puffs(name)
	local out = {}
	for _, c in folder:GetChildren() do
		if c.Name == name and c:IsA("BasePart") and c.Transparency < 0.99 then table.insert(out, c) end
	end
	return out
end
local function segDist(a, b, p)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local s = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * s - p).Magnitude
end
-- does segment a->b pass inside ball (c, r)?
local function blocks(a, b, c, r)
	return segDist(a, b, c) < r
end

local clearance = Config.Env.SceneryClearance or 0
for _, deck in { { name = "CloudDeckPuff", from = 18, to = 26, label = "cloud deck (tier 22)" }, { name = "StormDeckPuff", from = 38, to = 46, label = "storm deck (tier 42)" } } do
	local checked, inside, blocked, tooClose, shownMin = 0, 0, 0, 0, math.huge
	local example = nil
	local worstGap = math.huge
	for t = deck.from, deck.to do
		for i = 1, Tower.TilesPerTier do
			local here = platform(t, i)
			local nt, ni = if i < Tower.TilesPerTier then t else t + 1, if i < Tower.TilesPerTier then i + 1 else 1
			local nextP = platform(nt, ni)
			if here and nextP then
				local root = here.Position + Vector3.new(0, 3.5, 0)
				local nextRoot = nextP.Position + Vector3.new(0, 3.5, 0)
				hrp.CFrame = CFrame.new(root)
				local flat = Vector3.new(nextRoot.X - root.X, 0, nextRoot.Z - root.Z)
				local back = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)
				-- three cameras a climber uses: below-behind looking up, level, above-behind
				for _, spec in { { 14, -6 }, { 20, 0 }, { 12, 8 } } do
					local camPos = root - back * spec[1] + Vector3.new(0, spec[2], 0)
					camAt = function() return CFrame.new(camPos, nextRoot) end
					run(0.4, 0.1)
					local shown = puffs(deck.name)
					if #shown < shownMin then shownMin = #shown end
					checked += 1
					for _, p in shown do
						local r = p.Size.X / 2
						local c = p.Position
						if (root - c).Magnitude < r or (nextRoot - c).Magnitude < r then
							inside += 1
							example = example or string.format("P_%d_%d: a %s ball (r %.0f) holds the climber or the next platform", t, i, deck.name, r)
						end
						if blocks(camPos, nextRoot, c, r) or blocks(camPos, root, c, r) then
							blocked += 1
							example = example or string.format("P_%d_%d: a %s ball (r %.0f) hides the next platform from the camera", t, i, deck.name, r)
						end
						local gap = math.min(segDist(root, nextRoot, c), (root - c).Magnitude) - r
						if gap < worstGap then worstGap = gap end
						if gap < clearance - 0.5 then tooClose += 1 end
					end
				end
			end
		end
	end
	camAt = nil
	print(string.format("  %-22s %d camera positions; closest cloud surface %.1f studs from the climb; fewest clouds shown %d",
		deck.label, checked, worstGap, shownMin))
	truthy(checked >= 50, deck.label .. ": the climb through it was measured (" .. checked .. " camera positions)")
	eq(inside, 0, deck.label .. ": no cloud ever holds the climber or the next platform" .. (if example then " (" .. example .. ")" else ""))
	eq(blocked, 0, deck.label .. ": no cloud ever hides the next platform or the climber from the camera")
	truthy(clearance >= 30 and tooClose == 0, string.format("%s: every cloud keeps %d+ studs off the climb (Config.Env.SceneryClearance; closest %.1f)",
		deck.label, clearance, worstGap))
	truthy(shownMin >= 15, deck.label .. ": and the deck is still there around the tower (fewest " .. shownMin .. " clouds)")
end

-- leaving the storm band and coming back must not bring back the clouds that were left out
do
	local here = platform(42, 4)
	local nextP = platform(42, 5)
	local root = here.Position + Vector3.new(0, 3.5, 0)
	local nextRoot = nextP.Position + Vector3.new(0, 3.5, 0)
	local camPos = root + Vector3.new(0, -6, -14)
	camAt = function() return CFrame.new(camPos, nextRoot) end
	hrp.CFrame = CFrame.new(root)
	run(3, 0.1)
	local before = #puffs("StormDeckPuff")
	camAt = nil
	hrp.CFrame = CFrame.new(root.X, Progression.yAtProgress(20, Tower) + 3.5, root.Z) -- down in the cloud sea
	run(6, 0.1)
	eq(#puffs("StormDeckPuff"), 0, "set-up: below the storm band its deck is gone")
	camAt = function() return CFrame.new(camPos, nextRoot) end
	hrp.CFrame = CFrame.new(root)
	run(6, 0.1)
	local after = puffs("StormDeckPuff")
	eq(#after, before, "back at P_42_4 the same clouds are shown as before (" .. before .. "): left-out clouds stay out")
	local bad = 0
	for _, p in after do
		local r = p.Size.X / 2
		if segDist(camPos, nextRoot, p.Position) < r or (root - p.Position).Magnitude < r then bad += 1 end
	end
	eq(bad, 0, "and none of them is in the climber's way")
	camAt = nil
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump world: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump world check failed", 0)
end
