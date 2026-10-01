-- StormGrow — the first minutes of a brand-new farmer, as they see them (DESIGN.md §11).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_firstmin.luau 2>&1
--
-- Real server, HUD, Farm and Sky clients. Nothing is set by hand except where the camera looks. The player
-- does only what the screen says: the hint line and the arrow. Every step prints the second it happened.
-- Tiles are tapped ON THE SCREEN (stormgrow/tests/Aim.luau: the camera behind the character on the pad, a thumb
-- on the visible tile, UserInputService.TouchTap), so the client's pick decides which tile it is (REVIEW-1 B1).
--
-- The standard's first-run rule: the core action within ~5 seconds, no hidden prerequisite, a hint naming
-- the exact action, never a silent failure.

local Harness = require("./emu/harness")
local Aim = require("../stormgrow/tests/Aim")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-firstmin", viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Weather = h:_require(RS:FindFirstChild("Weather"))

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local t0 = h.scheduler:now()
local plr = h:join("Newbie", 4321)
local char = h.Players:simulateSpawn(plr, h.workspace)
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	assert(h:tryRun(key))
end
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.WoodPlanks
local function frames(s)
	for _ = 1, math.floor(s / 0.1 + 0.5) do
		cam.CFrame = CFrame.lookAt(hrp.Position + hrp.CFrame.LookVector * -14 + Vector3.new(0, 10, 0), hrp.Position)
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
	end
end
local root = plr.PlayerGui.StormHud.Root
local aim = Aim.new(h, { touch = true })
local offScreen = 0
local function tapOnScreen(hb)
	local ok = aim:tapTile(hb:GetAttribute("Farm"), hb:GetAttribute("Key"), hrp.Position, hrp.CFrame.LookVector)
	if not ok then offScreen += 1 end
	h:advance(0.02)
end
local function hint() return if root.Hint.Visible then root.Hint.Text else "" end
local function at() return string.format("%5.1f s", h.scheduler:now() - t0) end
local log = {}
local function note(s) table.insert(log, at() .. "  " .. s) end

frames(0.5)
eq(plr:GetAttribute("Loaded"), true, "the farm loaded within half a second")
note("loaded; hint: " .. hint())
truthy(string.find(hint(), "Tap a glowing tile to plant a Radish (free)", 1, true) ~= nil, "the first hint names the exact action")
local arrow = h.workspace.StormStrikes:FindFirstChild("TapArrow")
truthy(arrow ~= nil and arrow.Enabled and arrow.Adornee ~= nil, "an arrow points at a tile")
local glows = 0
for _, d in h.workspace.StormStrikes:GetChildren() do
	if d.Name == "TileGlow" then glows += 1 end
end
eq(glows, 9, "the nine empty tiles you own glow (and only those: locked fields do not)")
truthy(string.find(root.TopBar.Forecast.Text, "Next", 1, true) ~= nil or string.find(root.TopBar.Forecast.Text, "left", 1, true) ~= nil,
	"the forecast chip is up from second 0 (" .. root.TopBar.Forecast.Text .. ")")

-- tap the tile the arrow points at
local target = arrow.Adornee
tapOnScreen(target)
frames(0.3)
eq(target:GetAttribute("Crop"), "radish", "the first tap planted a Radish")
local firstPlant = h.scheduler:now() - t0
note("first Radish planted")
truthy(firstPlant <= 5, string.format("the core action happened %.1f s after joining (<= 5)", firstPlant))
truthy(string.find(hint(), "Plant the rest", 1, true) ~= nil, "the hint moves on: plant the rest (" .. hint() .. ")")

-- plant the rest, following the arrow each time
for _ = 1, 8 do
	local a = h.workspace.StormStrikes.TapArrow
	tapOnScreen(a.Adornee)
	frames(0.2)
end
note("all nine planted; hint: " .. (if hint() == "" then "(none)" else hint()))
local planted = 0
for _, hb in h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles:GetChildren() do
	if hb:GetAttribute("Field") == 1 and hb:GetAttribute("Crop") == "radish" then planted += 1 end
end
eq(planted, 9, "following the arrow planted all nine tiles of field 1")
eq(h.workspace.StormStrikes.TapArrow.Enabled, false, "with nothing left to plant, the arrow goes")

-- wait for ripe (the hint says when)
local ripeAt = nil
for _ = 1, 400 do
	frames(0.1)
	if string.find(hint(), "Ripe! Tap to harvest", 1, true) or string.find(hint(), "can turn", 1, true) then
		ripeAt = h.scheduler:now() - t0
		break
	end
end
truthy(ripeAt ~= nil, "a hint says the crops are ripe")
note("hint: " .. hint())
local coins0 = plr:GetAttribute("Coins")
local tiles = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles
for t = 1, 9 do
	tapOnScreen(tiles["Tile_1_" .. t])
	frames(0.2)
end
note(string.format("harvested nine: %d -> %d coins", coins0, plr:GetAttribute("Coins")))
eq(plr:GetAttribute("Coins"), 65, "nine Radishes sold: 20 + 45 = 65 coins")
eq(offScreen, 0, "every tile of field 1 was on screen and tappable from the pad, on an 800 x 360 phone")
truthy(string.find(hint(), "Unlock the Carrot", 1, true) ~= nil or string.find(hint(), "can turn", 1, true) ~= nil,
	"the hint points at the Carrot (" .. hint() .. ")")
-- the Seeds panel: on a phone it opens from 🌱, and the Carrot row unlocks with one tap
root.Toggles.SeedsButton.Activated:Fire()
frames(0.3)
truthy(root.Seeds.Visible, "🌱 opens the Seeds drawer on a phone")
local carrotRow = root.Seeds.SeedList.Seed_carrot
truthy(string.find(carrotRow.Text, "Unlock", 1, true) ~= nil and string.find(carrotRow.Text, "tap to unlock", 1, true) ~= nil,
	"the Carrot row offers the unlock (" .. carrotRow.Text .. ")")
carrotRow.Activated:Fire()
frames(0.3)
eq(plr:GetAttribute("Unlocked"), 2, "one tap on the row unlocked the Carrot")
note("Carrot unlocked")
local radishRow = root.Seeds.SeedList.Seed_radish
truthy(string.find(radishRow.Text, "to find", 1, true) ~= nil, "each owned crop says how many Almanac entries it still has to find (" .. radishRow.Text .. ")")
truthy(string.find(radishRow.Text, "ripe for the", 1, true) ~= nil, "and which event a seed planted now will be ripe for")

-- A row two ahead of the next unlock refuses on the client (no remote) and must SAY why, readably: the line
-- has to still be up a second later, not flash for one 0.2 s HUD refresh. The server's "Carrot unlocked" toast
-- is let run out first, so this measures the client's own line and not the tail of that one.
frames(4)
truthy(not root.Toast.Visible, "set-up: the toast line is clear before the tap")
root.Seeds.SeedList.Seed_tomato.Activated:Fire()
frames(1)
truthy(root.Toast.Visible and string.find(root.Toast.Text, "Unlock 🌽 Corn first", 1, true) ~= nil,
	string.format("tapping the Tomato row before the Corn says so, still readable 1 s later (visible %s, \"%s\")",
		tostring(root.Toast.Visible), root.Toast.Text))
eq(plr:GetAttribute("Unlocked"), 2, "and unlocks nothing")
frames(3)
truthy(not root.Toast.Visible, "the line clears itself afterwards")
note("tapped the Tomato row early: \"" .. root.Toast.Text .. "\"")

-- the first weather event comes within 210 s of anything (the longest gap)
local eventAt = nil
for _ = 1, 2200 do
	frames(0.1)
	if Weather.at(h.workspace:GetAttribute("ServerNow"), Config.Weather) ~= "clear" then
		eventAt = h.scheduler:now() - t0
		break
	end
end
truthy(eventAt ~= nil and eventAt <= 210 + 60, string.format("the first weather event came %.0f s after joining", eventAt or -1))
note("first event: " .. root.TopBar.Forecast.Text)

print("")
for _, l in log do print("  " .. l) end
print("")
for _, w in h.warnings do
	print("warning: " .. w)
	if string.find(w, "frame error", 1, true) then failed += 1 end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow first minutes: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow firstmin check failed", 0) end
