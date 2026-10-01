-- Nightwatch Manor — the client's budgets are CAPS in code, not just numbers a check compares against.
-- Run: luau check_nightwatchmanor_caps.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- The second reviewer (2026-09-30, LOW; docs/complete-game-standard.md §2 "budgets measured and capped in code"):
-- Config.Budget.MaxParts, MaxLights and MaxHazards were read by no file in src/. Only the windows, the portraits and
-- the emitter rates were capped; the 118-part peak stayed under 160 only because of how the scene happens to be
-- built. With MaxParts = 50 and MaxLights = 1 in memory, the client still parented 73+ parts.
--
-- This boots the real server and client with a budget far below what the scene wants, IN MEMORY:
-- MaxParts = 50, MaxLights = 1; every upgrade maxed (the cosiest safehouse); every band flies all four hazard kinds
-- back to back and asks for lightning every 0.3-0.5 s with a bolt. Night 33 (a Blood Moon manor with three Portrait
-- Halls, the richest in EYECANDY.md §7): the safehouse by day, then every room the Nightwatcher is not near. Every
-- frame: parts, lights and hazards within the caps. And the cap never costs a warning: whenever a hazard's banner
-- is up, its model and its ring are drawn.

local Kit = require("./check_nightwatchmanor_kit")

local CAP_PARTS, CAP_LIGHTS = 50, 1
local ctx = Kit.boot({
	name = "nwm-caps",
	-- night 33's PUBLIC manor is the one EYECANDY.md §7 measured (three Portrait Halls), so the server plans from the
	-- public seed here (its ServerStorage switch; the game itself salts every manor: check_nightwatchmanor_guard.luau)
	publicLayouts = true,
	profile = { night = 33, stash = 0, best = 32, levels = { lanterns = 5, wardstones = 5, beartraps = 5, relicvault = 5, alarmbell = 3, lockbox = 3, floodlights = 4 } },
	beforeClient = function(c)
		c.Config.Budget.MaxParts = CAP_PARTS
		c.Config.Budget.MaxLights = CAP_LIGHTS
		local Hz = c.Config.Hazards
		Hz.IntervalMin, Hz.IntervalMax = 1, 1
		local all = {}
		for k in Hz.Kinds do table.insert(all, k) end
		table.sort(all)
		for _, b in c.Config.Env.Bands do
			b.hazards = all
			b.lightning = { everyMin = 0.3, everyMax = 0.5, bolt = true }
		end
	end,
})
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local B = Config.Budget
local size = Config.Manor.RoomSize
eq(B.MaxParts, CAP_PARTS, "CONTROL: the budget really is cut in memory")

local frames, over, overExample = 0, 0, nil
local peak = { parts = 0, lights = 0, hazards = 0, windows = 0, portraits = 0, props = 0 }
local warnFrames, warnUndrawn, warnUndrawnWhere = 0, 0, nil
local where = "boot"
ctx.onFrame = function()
	frames += 1
	local c = { parts = 0, lights = 0, windows = 0, portraits = 0, props = 0 }
	local kinds, ringOn, hazardParts = {}, false, 0
	for _, d in ctx.folder:GetDescendants() do
		if d:IsA("BasePart") then
			c.parts += 1
			if d.Name == "WinSky" then c.windows += 1 end
			if d.Name == "PortraitCanvas" then c.portraits += 1 end
			if d.Name == "Chimney" or d.Name == "CatBody" or d.Name == "Bookshelf" then c.props += 1 end
			if d.Name == "HazardZone" then ringOn = true end
			local k = string.match(tostring(d.Name), "^Hazard_(%a+)_")
			if k then
				kinds[k] = true
				hazardParts += 1
			end
		elseif d.ClassName == "PointLight" and d.Enabled then
			c.lights += 1
		end
	end
	c.hazards = 0
	for _ in kinds do c.hazards += 1 end
	for k, v in c do peak[k] = math.max(peak[k] or 0, v) end
	if c.parts > B.MaxParts or c.lights > B.MaxLights or c.hazards > B.MaxHazards then
		over += 1
		overExample = overExample or string.format("%s: %d parts, %d lights, %d hazards", where, c.parts, c.lights, c.hazards)
	end
	if ctx.warning.Visible then
		warnFrames += 1
		if not ringOn or hazardParts == 0 then
			warnUndrawn += 1
			warnUndrawnWhere = warnUndrawnWhere or where
		end
	end
end

-- the safehouse by day, at its cosiest, in a storm of lightning
where = "DAY"
ctx.hrp.CFrame = CFrame.new(ctx.house().Floor.Position + Vector3.new(0, 4, -20))
ctx.seconds(4, 1 / 30)
local dayPeak = peak.parts
truthy(peak.props >= 1, "CONTROL: the safehouse props stand by day (" .. peak.props .. " of the three landmark props seen)")

-- the manor by night: every room the Nightwatcher is not near
ctx.pressDoor()
where = "NIGHT"
ctx.seconds(0.3, 1 / 30)
local function watcherPos(): Vector3?
	local m = ctx.manor()
	local w = m and m:FindFirstChild("Nightwatcher")
	return w and w:GetPivot().Position
end
local visited = 0
local m = ctx.manor()
if m then
	for _, f in m:GetChildren() do
		local floor = string.match(tostring(f.Name), "^Room%d+_") and f:FindFirstChild("Floor")
		if floor and ctx.manor() ~= nil then
			local w = watcherPos()
			if w == nil or (Vector3.new(w.X, 0, w.Z) - Vector3.new(floor.Position.X, 0, floor.Position.Z)).Magnitude > size * 1.6 then
				ctx.hrp.CFrame = CFrame.new(floor.Position + Vector3.new(0, 4, 0))
				ctx.seconds(1, 1 / 30)
				visited += 1
			end
		end
	end
end
if ctx.manor() ~= nil then ctx.pressExit() end
ctx.seconds(Config.BeatSeconds + 0.6, 0.1)

print(string.format("  caps %d parts / %d lights: %d frames (%d rooms toured); peaks %d parts (day %d), %d lights, %d hazards, %d windows, %d portraits; a warning up on %d frames",
	CAP_PARTS, CAP_LIGHTS, frames, visited, peak.parts, dayPeak, peak.lights, peak.hazards, peak.windows, peak.portraits, warnFrames))
truthy(visited >= 4, "CONTROL: the tour visited the manor (" .. visited .. " rooms)")
truthy(peak.windows >= 1 and peak.portraits >= 1, string.format(
	"CONTROL: the tour stood near windows and portraits, so the scene wanted more than the cap (%d windows, %d portraits)", peak.windows, peak.portraits))
truthy(warnFrames > 60, "CONTROL: hazards kept coming (a warning up on " .. warnFrames .. " frames)")
eq(over, 0, "every frame stayed inside the cut budget: parts, lights and hazards are capped by the client itself (" .. tostring(overExample) .. ")")
eq(warnUndrawn, 0, "the cap never costs a warning: whenever a banner is up, the hazard and its ring are drawn (first miss: " .. tostring(warnUndrawnWhere) .. ")")
truthy(peak.parts >= CAP_PARTS - 16, string.format("the cap is spent, not hoarded: the scene still fills the budget (peak %d of %d)", peak.parts, CAP_PARTS))
eq(ctx.serverCalls, 0, "the client never fired a remote")
ctx.finish("nightwatchmanor caps")
