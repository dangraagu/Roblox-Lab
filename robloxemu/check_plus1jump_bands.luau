-- +1 Jump Every Step — the sky names the same band as the HUD and the top-10 board. Run: luau check_plus1jump_bands.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17 (finding 7): the board and "Best" name a band by TIER number (Tier 85 = 🚀), the
-- sky named it by tiers CLIMBED. Standing on P_85_1..5 (84.2-84.8 climbed) the HUD said "Best: 85 🚀"
-- while the band chip said "🌠 Edge of Space · 🚀 Space in 1". Same at tiers 7, 15 and 240.
-- Here the climber stands on every platform of those tiers, through the real client scripts, and the
-- chip must name the band the HUD shows for that tier. "YOU REACHED SPACE!" plays when the climber
-- LANDS on tier 85, not while flying past its height on a jump that may still miss.
--
-- Headless limits: no physics. Standing = root part 3.5 studs above the platform centre with the
-- Humanoid reporting a floor; flying = the same height with FloorMaterial = Air.

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
local EnvBands = mod("EnvBands")
local bands = Config.Env.Bands
local Tower = Config.Tower
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001 -- no hazards: this file is about names

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

local root = plr.PlayerGui:FindFirstChild("Plus1Sky"):FindFirstChild("Root")
local chip, card = root:FindFirstChild("BandChip"), root:FindFirstChild("BandCard")
local hudGui = plr.PlayerGui:FindFirstChild("Plus1Hud")
local stateEvent = RS:FindFirstChild("Plus1Remotes"):FindFirstChild("State")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

local cards, flashes, lastCard = {}, 0, ""
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(cards, card.Text)
	end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			flashes += 1
		end
	end
end
local function run(seconds) for _ = 1, math.floor(seconds * 30 + 0.5) do frame(1 / 30) end end
local function standOn(t, i)
	hrp.CFrame = CFrame.new(0, Progression.yAtProgress((t - 1) + i / Tower.TilesPerTier, Tower) + 3.5, 0)
end
local function bestLabel()
	for _, d in hudGui:GetDescendants() do
		if d.ClassName == "TextLabel" and string.find(d.Text or "", "Best", 1, true) then return d end
	end
	return nil
end

run(2)

--======================================================================= the space fanfare waits for the landing

do
	local function spaceCard()
		for _, t in cards do if string.find(t, "YOU REACHED SPACE", 1, true) then return true end end
		return false
	end
	standOn(84, Tower.TilesPerTier)
	run(2)
	eq(spaceCard(), false, "set-up: standing on P_84_6, no space card yet")
	-- the jump: in the air at and above P_85_1's standing height, not yet landed
	hum.FloorMaterial = Enum.Material.Air
	hrp.CFrame = CFrame.new(0, Progression.yAtProgress(84 + 1 / Tower.TilesPerTier, Tower) + 5.5, 0)
	run(0.3)
	eq(spaceCard(), false, "flying past tier 85's height on a jump that has not landed does not play the fanfare")
	eq(flashes, 0, "and no flash")
	hum.FloorMaterial = Enum.Material.Plastic
	standOn(85, 1)
	run(0.5)
	eq(spaceCard(), true, "landing on P_85_1 (Tier 85, which the board shows as 🚀) plays YOU REACHED SPACE!")
	eq(flashes, 1, "with its flash")
	standOn(84, Tower.TilesPerTier) -- a knock back down a tier
	run(1)
	standOn(85, 2)
	run(1)
	eq(flashes, 1, "falling back a tier and climbing on does not replay it")
end

--======================================================================= every platform of the boundary tiers

local mismatches, checked, example = 0, 0, nil
for _, t in { 7, 15, 35, 60, 85, 140, 240 } do
	local want = bands[EnvBands.indexAt(bands, t)]
	stateEvent:FireClient(plr, { jumpPower = t * 6, jumpHeight = 60, tier = t, bestTier = t, rebirths = 0, multiplier = 1,
		nextRebirthTier = 10, canRebirth = false })
	local best = bestLabel()
	truthy(best ~= nil and string.find(best.Text, want.emoji, 1, true) ~= nil,
		string.format("the HUD shows Best %d with %s (%s)", t, want.emoji, tostring(best and best.Text)))
	for i = 1, Tower.TilesPerTier do
		standOn(t, i)
		run(0.4)
		checked += 1
		if string.find(chip.Text, want.emoji .. " " .. want.name, 1, true) ~= 1 then
			mismatches += 1
			example = example or string.format("P_%d_%d: chip '%s', HUD/board say %s %s", t, i, chip.Text, want.emoji, want.name)
		end
	end
	-- and the platform just below the boundary still belongs to the tier below
	local below = bands[EnvBands.indexAt(bands, t - 1)]
	standOn(t - 1, Tower.TilesPerTier)
	run(0.4)
	checked += 1
	if string.find(chip.Text, below.emoji .. " " .. below.name, 1, true) ~= 1 then
		mismatches += 1
		example = example or string.format("P_%d_6: chip '%s', HUD/board say %s %s", t - 1, chip.Text, below.emoji, below.name)
	end
end
eq(mismatches, 0, "on every platform of every boundary tier the chip names the band the HUD and board show for that tier ("
	.. (checked - mismatches) .. "/" .. checked .. (if example then "; e.g. " .. example else "") .. ")")

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump bands: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump bands check failed", 0)
end
