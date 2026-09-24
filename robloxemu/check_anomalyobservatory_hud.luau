-- anomaly-observatory — the HUD still fits, with the night sky's break button and caption added.
-- Run: luau check_anomalyobservatory_hud.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- robloxemu/check_anomaly.luau is the HUD gate for Hud.client alone and is left as it is. This file
-- runs the same gate (emu/hudcheck.luau: on screen, 44 px tap targets, nothing under the touch
-- controls, no two panels overlapping) with BOTH client scripts, over the standard ten viewports and
-- again with a break in progress. On top of that, on every viewport:
--   * the break button and the sky caption do not overlap anything the HUD shows (its instruction
--     line, hint pill, toggles, panels, toasts);
--   * on a phone, while one of the HUD's drawers is open, the break button steps aside (an open
--     drawer on the right would otherwise sit on it).

local HudCheck = require("./emu/hudcheck")

local extra = 0
local extraFail = {}
local frames = 0

local function drive(h, seconds: number)
	local RunService = h.game:GetService("RunService")
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		frames += 1
	end
end

local function rectsOf(h, gui, v)
	local out = {}
	if gui == nil then return out end
	for _, r in h:guiRects(gui, v.w, v.h) do
		if r.shown and r.depth >= 2 and r.sw > 0 and r.sh > 0 then
			table.insert(out, r)
		end
	end
	return out
end

local function overlapPx(a, b): (number, number)
	local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
	local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
	return ox, oy
end

-- My controls vs everything the HUD shows.
local function checkNoOverlap(h, player, v, mode: string)
	local sky = player.PlayerGui:FindFirstChild("ObservatorySky")
	local hud = player.PlayerGui:FindFirstChild("AnomalyHud")
	local mine = {}
	for _, r in rectsOf(h, sky, v) do
		if r.name == "BreakButton" or (r.name == "SkyCaption" and r.obj.Text ~= "") then
			table.insert(mine, r)
		end
	end
	local sawButton = false
	for _, r in mine do
		if r.name == "BreakButton" then sawButton = true end
	end
	if not sawButton then
		table.insert(extraFail, string.format("[%s %s] the break button is not shown", v.name, mode))
	end
	local theirs = rectsOf(h, hud, v)
	for _, a in mine do
		for _, b in theirs do
			-- only the HUD's own furniture: its scaling root is depth 1 and never compared
			local ox, oy = overlapPx(a, b)
			if ox > 1 and oy > 1 then
				-- a panel's children are inside the panel; report the panel once
				table.insert(extraFail, string.format("[%s %s] %s overlaps the HUD's %s (%s) by %.0fx%.0f px",
					v.name, mode, a.name, b.name, b.class, ox, oy))
			end
		end
	end
	extra += 1
end

local function breakButton(player)
	local sky = player.PlayerGui:FindFirstChild("ObservatorySky")
	return sky and sky.Root:FindFirstChild("BreakButton")
end

local base = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(base, v)
end

local viewports = {}
for _, v in base do
	table.insert(viewports, {
		name = v.name, w = v.w, h = v.h, touch = v.touch,
		before = function(h, player)
			drive(h, 0.5)
			checkNoOverlap(h, player, v, "hall")
			-- on a phone, open the MENU drawer: the break button must step aside, then close it again
			local hud = player.PlayerGui:FindFirstChild("AnomalyHud")
			local menu = hud and hud.Root:FindFirstChild("MenuToggle")
			if menu and menu.Visible then
				menu.Activated:Fire()
				drive(h, 0.2)
				local b = breakButton(player)
				if b and b.Visible then
					table.insert(extraFail, string.format("[%s] the break button stays on screen under an open HUD drawer", v.name))
				end
				extra += 1
				menu.Activated:Fire()
				drive(h, 0.2)
			end
		end,
	})
end
-- the same ten again, during a break
for i, v in base do
	table.insert(viewports, {
		name = v.name .. " (break)", w = v.w, h = v.h, touch = v.touch,
		before = function(h, player)
			if i == 1 then
				local b = breakButton(player)
				assert(b ~= nil, "no break button")
				b.Activated:Fire()
			end
			drive(h, 1.2)
			local b = breakButton(player)
			if not (b and string.find(b.Text, "Back", 1, true)) then
				table.insert(extraFail, string.format("[%s] not in a break (button reads %s)", v.name, tostring(b and b.Text)))
			end
			checkNoOverlap(h, player, v, "break")
		end,
	})
end

HudCheck.run({
	overlap = true,
	game = "anomaly-observatory (HUD + night sky)",
	bundle = require("./build/anomaly-observatory"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Sky.client" },
	viewports = viewports,
	-- The HUD's tint swatches are built from a State push (see check_anomaly.luau): replay the server's
	-- own join payload. Then run the sky's frame loop so it has built its sky and laid out its row.
	warmup = function(h, player)
		local state = h.ReplicatedStorage:FindFirstChild("AnomalyRemotes"):FindFirstChild("State")
		local sent = state:getSent()
		assert(#sent > 0, "the server never pushed State at join")
		state:FireClient(player, sent[#sent].args[1])
		drive(h, 2)
		assert(h.workspace:FindFirstChild("ObservatorySky") ~= nil, "the sky client built no sky")
	end,
})

print(string.format("   break row: %d extra viewport checks over %d driven frames", extra, frames))
if #extraFail > 0 then
	for _, f in extraFail do print("FAIL: " .. f) end
	error(string.format("check_anomalyobservatory_hud: %d problem(s) with the break row", #extraFail), 0)
end
print(string.format("check_anomalyobservatory_hud: %d passed, 0 failed (+ the HUD gate above)", extra))
