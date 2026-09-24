-- +1 Jump Every Step — when the HUD lights REBIRTH. Run: luau check_plus1jump_rebirth.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review round 1 (finding 2): the HUD lit the REBIRTH button up (purple) every time a rebirth was possible.
-- Rebirth sends the climber back to the pad and, with the jump capped at 60 and every tier reachable
-- without it, never makes the climb faster. A normal player who pressed the lit button reached space after
-- 46 min (at 10 and 18), 57 min (10, 18, 26), 227 min (every one), against the owner's 30-45. Round 1
-- answered by dimming every rebirth after the first.
-- Review round 2 (finding 2): dimming changed the HUD of an existing mechanic (rebirth at 10/18/26) without
-- the owner, so round 2 put back the HUD before the sky (every rebirth lit).
-- OWNER DECISION 2026-09-24: first only (Config.Rebirth.HighlightFirstRebirths = 1, about 38 min to space
-- for a player who presses every lit button). That is the default checked here. The old every-lit HUD
-- (= math.huge) is checked too, in memory for this run. Both are driven by the REAL server (earning
-- platforms by touching them, rebirthing through the remote), and a quiet button still works.

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
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 100000, 100001
local Tower = Config.Tower

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))
local btn = plr.PlayerGui:FindFirstChild("Plus1Hud"):FindFirstChild("RebirthButton", true)
truthy(btn ~= nil, "the HUD has its rebirth button")
local towerFolder = h.workspace:FindFirstChild("Tower")
local stats = plr:FindFirstChild("leaderstats")

local LOUD = { 180, 90, 220 }
local function isLoud()
	local c = btn.BackgroundColor3
	return math.abs(c.R * 255 - LOUD[1]) < 1 and math.abs(c.G * 255 - LOUD[2]) < 1 and math.abs(c.B * 255 - LOUD[3]) < 1
end
local function climbTo(tier)
	-- touch every platform from the start up to P_<tier>_1, the way a climber earns them
	for t = 1, tier do
		for i = 1, (if t == tier then 1 else Tower.TilesPerTier) do
			local part = towerFolder:FindFirstChild("P_" .. t .. "_" .. i)
			assert(part, "the server built P_" .. t .. "_" .. i)
			part.Touched:Fire(hrp)
		end
	end
	h:advance(0.1)
end
local function rebirthPressed()
	btn.Activated:Fire()
	h:advance(0.1)
end

-- the first rebirth: advertised
climbTo(9)
eq(isLoud(), false, "tier 9: no rebirth yet, the button is not lit")
truthy(string.find(btn.Text, "10", 1, true) ~= nil, "and says what to reach (" .. btn.Text .. ")")
climbTo(10)
eq(stats.Tier.Value, 10, "set-up: the server credited tier 10")
eq(isLoud(), true, "tier 10: the FIRST rebirth is lit, so every player learns it exists (" .. btn.Text .. ")")
rebirthPressed()
eq(stats.Rebirths.Value, 1, "pressing it rebirths (server)")

-- the second: possible at tier 18 and, by default (owner 2026-09-24: first only), NOT lit
eq(Config.Rebirth.HighlightFirstRebirths, 1, "owner decision 2026-09-24: the shipped Config lights only the first rebirth")
climbTo(18)
eq(stats.Tier.Value, 18, "set-up: back up to tier 18 after the rebirth")
eq(isLoud(), false, "default HUD: tier 18, rebirth #2 is possible but NOT lit (" .. btn.Text .. ")")
truthy(string.find(btn.Text, "5x", 1, true) ~= nil, "the quiet button still names the multiplier rebirth #2 really gives (" .. btn.Text .. ")")
climbTo(26)
eq(isLoud(), false, "default HUD: still quiet at tier 26")
rebirthPressed()
eq(stats.Rebirths.Value, 2, "and a quiet button still works: pressing it rebirths (server)")

-- the old HUD (every rebirth lit, as before the sky), kept as a one-line option
local defaultFirst = Config.Rebirth.HighlightFirstRebirths
Config.Rebirth.HighlightFirstRebirths = math.huge
climbTo(26)
eq(stats.Tier.Value, 26, "set-up: back up to tier 26 after rebirth #2")
eq(isLoud(), true, "every-lit option: tier 26, rebirth #3 is lit (" .. btn.Text .. ")")
truthy(string.find(string.upper(btn.Text), "REBIRTH", 1, true) ~= nil, "and offers it (" .. btn.Text .. ")")
climbTo(40)
eq(isLoud(), true, "every-lit option: still lit at tier 40")
rebirthPressed()
eq(stats.Rebirths.Value, 3, "pressing it rebirths (server)")
Config.Rebirth.HighlightFirstRebirths = defaultFirst

-- a climber whose best tier is past the last sky band: lit again (default, first only)
do
	local again = Config.Rebirth.HighlightAgainAtBestTier
	truthy(type(again) == "number", "Config.Rebirth.HighlightAgainAtBestTier is set (" .. tostring(again) .. ")")
	again = again or Config.Env.Bands[#Config.Env.Bands].from
	local state = RS:FindFirstChild("Plus1Remotes"):FindFirstChild("State")
	state:FireClient(plr, { jumpPower = 30, jumpHeight = 25, tier = 34, bestTier = again, rebirths = 3, multiplier = 10,
		nextRebirthTier = 34, canRebirth = true })
	h:advance(0.1)
	eq(isLoud(), true, "best tier " .. again .. " (beyond the galaxy): rebirths are lit again (" .. btn.Text .. ")")
	state:FireClient(plr, { jumpPower = 30, jumpHeight = 25, tier = 20, bestTier = again, rebirths = 3, multiplier = 10,
		nextRebirthTier = 34, canRebirth = false })
	h:advance(0.1)
	eq(isLoud(), false, "and never when a rebirth is not possible")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump rebirth: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump rebirth check failed", 0)
end
