-- hudcheck.luau — boot a game's server, then its client scripts, and check the HUD fits.
--
-- This is the check no unit test could do. A player reported that the Grow a Crystal HUD
-- "covers the entire screen and it's impossible to move or do anything" on mobile, and every
-- panel size in that file passed every test we had — because nothing we had ever ran the file.
--
-- Used from a per-game runner. It takes a config table rather than command-line arguments
-- because the luau CLI has none: every extra argument is treated as another file to execute.
--
--     local HudCheck = require("./emu/hudcheck")
--     HudCheck.run({
--         game = "grow-a-crystal",
--         bundle = require("./build/grow-a-crystal"),
--         server = "server/Main.server",
--         clients = { "client/Hud.client" },
--     })
--
-- One game per process: the harness installs globals into the calling thread and refuses a
-- second install.

local Harness = require("./harness")

local HudCheck = {}

-- Viewports worth caring about. The phone ones are why this file exists; the desktop ones are
-- the regression guard, because the fix must not move anything on a monitor.
HudCheck.VIEWPORTS = {
	{ name = "phone landscape", w = 800, h = 360, touch = true },
	{ name = "small phone", w = 640, h = 300, touch = true },
	{ name = "phone portrait", w = 414, h = 800, touch = true },
	{ name = "tablet", w = 1024, h = 768, touch = true },
	{ name = "laptop", w = 1366, h = 768, touch = false },
	{ name = "desktop", w = 1920, h = 1080, touch = false },
}

-- Roblox's own touch controls. The movement thumbstick owns the bottom-left, the jump button
-- the bottom-right; a button we draw inside either never receives a tap. These fractions are
-- deliberately generous — being wrong in this direction only costs us screen space.
local THUMBSTICK_FRACTION = 0.35
local JUMP_FRACTION = 0.25
local MAX_CONTROL_PAD = 150

-- Roblox's own guidance and both mobile platform guidelines put the minimum comfortable tap
-- target at ~44 px. A UIScale below 1 shrinks every control on exactly the device that needs
-- them biggest, so this has to be checked in SCREEN px after scaling, and a HUD can be perfectly
-- laid out and still be unusable — which is the same complaint the whole change started from.
local MIN_TAP = 44

local INTERACTIVE = {
	TextButton = true,
	ImageButton = true,
	TextBox = true,
}

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh): boolean
	return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

function HudCheck.run(cfg)
	assert(type(cfg) == "table", "HudCheck.run expects a config table")
	assert(type(cfg.game) == "string", "config.game must be the game's name")
	assert(type(cfg.bundle) == "table", "config.bundle must be the required build/<game>.luau")

	local serverKey = cfg.server or "server/Main.server"
	local clientKeys = cfg.clients or { "client/Hud.client" }
	local viewports = cfg.viewports or HudCheck.VIEWPORTS

	local failures = {}
	local function fail(where: string, msg: string)
		table.insert(failures, "[" .. where .. "] " .. msg)
	end

	-- A ScrollingFrame's canvas must cover its content or the last rows are unreachable.
	-- CanvasSize is design px, AbsoluteContentSize is screen px; mixing the two silently costs a
	-- phone player the bottom of the list while a 1080p monitor looks perfect. Position plays no
	-- part, so this is checked on hidden panels too.
	local function checkCanvas(r, viewportName: string)
		local content = 0
		for _, child in r.obj:GetChildren() do
			if child.ClassName == "UIListLayout" or child.ClassName == "UIGridLayout" then
				local acs = child.AbsoluteContentSize
				if acs ~= nil and acs.Y > content then
					content = acs.Y
				end
			end
		end
		if content <= 0 then
			return
		end
		local canvas = r.obj.CanvasSize
		local canvasScreen = 0
		if canvas ~= nil then
			canvasScreen = canvas.Y.Offset * r.scale + canvas.Y.Scale * r.sh
		end
		if canvasScreen + 2 < content then
			fail(
				viewportName,
				string.format(
					"%s cannot scroll to its last %.0f px: canvas %.0f px of %.0f px of content",
					r.name, content - canvasScreen, canvasScreen, content
				)
			)
		end
	end

	local h = Harness.new({
		bundle = cfg.bundle,
		name = cfg.game,
		viewport = { viewports[1].w, viewports[1].h },
		touch = viewports[1].touch,
	})

	print("== " .. cfg.game)

	local okServer, errServer = h:tryRun(serverKey)
	print(string.format("   server %-28s %s", serverKey, okServer and "loaded" or "FAILED"))
	if not okServer then
		print("   " .. tostring(errServer))
		error("server did not load; nothing else can be checked", 0)
	end

	local player = h:join("PhoneTester", 5551212)
	h:advance(1)

	for _, key in clientKeys do
		local ok, err = h:tryRun(key)
		print(string.format("   client %-28s %s", key, ok and "loaded" or "FAILED"))
		if not ok then
			fail("load", key .. ": " .. tostring(err))
		end
	end

	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui == nil or #playerGui:GetChildren() == 0 then
		error("the client scripts produced no PlayerGui content", 0)
	end

	----------------------------------------------------------------- geometry, per viewport

	for _, v in viewports do
		h:setViewport(v.w, v.h)
		h:setTouch(v.touch)
		-- The HUD re-lays-out when Camera.ViewportSize changes; give its handlers a beat.
		h:advance(0.1)

		local controlPad = 0
		if v.touch then
			controlPad = math.min(MAX_CONTROL_PAD, math.floor(v.h * 0.35))
		end
		local bandY = v.h - controlPad
		local leftBandW = v.w * THUMBSTICK_FRACTION
		local rightBandX = v.w * (1 - JUMP_FRACTION)

		local shownArea, worst, hidden = 0, nil, 0

		-- Fill in every layout's real content size before measuring. Without this the shim
		-- reports zero, every CanvasSize computed from it comes out as just the padding, and a
		-- canvas that is short by the UIScale factor is invisible to this check — which is
		-- exactly how three files shipped a shop whose bottom rows a phone could not reach.
		for _, gui in playerGui:GetChildren() do
			h:settleLayouts(gui, v.w, v.h)
		end
		h:advance(0.05) -- let the games' AbsoluteContentSize handlers run

		for _, gui in playerGui:GetChildren() do
			for _, r in h:guiRects(gui, v.w, v.h) do
				-- POSITION checks apply to visible panels only, and that limit is real: on a
				-- phone the drawers start closed, so those runs measure the toggles and little
				-- else. Checking hidden panels too was tried and is wrong — a closed drawer is
				-- legitimately parked off the edge, and where it sits closed says nothing about
				-- where it opens. The count of what went unmeasured is printed instead of being
				-- quietly dropped. The canvas check below does not depend on position, so it
				-- runs on everything.
				if r.class == "ScrollingFrame" then
					checkCanvas(r, v.name)
				end
				if not r.shown then
					if r.depth == 2 and (r.class == "Frame" or r.class == "ScrollingFrame") then
						hidden += 1
					end
					continue
				end
				local where = v.name

				-- 1. nothing may hang off the screen. A pixel of rounding is not a bug.
				local slack = 1
				if r.sx < -slack or r.sy < -slack or r.sx + r.sw > v.w + slack or r.sy + r.sh > v.h + slack then
					fail(
						where,
						string.format(
							"%s (%s) is off screen: x %.0f..%.0f, y %.0f..%.0f in %dx%d",
							r.name, r.class, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh, v.w, v.h
						)
					)
				end

				-- 2. nothing tappable may be too small to hit with a thumb
				if controlPad > 0 and INTERACTIVE[r.class] then
					local small = math.min(r.sw, r.sh)
					if small > 0 and small < MIN_TAP then
						fail(
							where,
							string.format(
								"%s (%s) is %.0fx%.0f screen px, under the %d px tap target",
								r.name, r.class, r.sw, r.sh, MIN_TAP
							)
						)
					end
				end

				-- 3. nothing tappable may sit under Roblox's own touch controls
				if controlPad > 0 and INTERACTIVE[r.class] then
					local inLeft = overlaps(r.sx, r.sy, r.sw, r.sh, 0, bandY, leftBandW, controlPad)
					local inRight =
						overlaps(r.sx, r.sy, r.sw, r.sh, rightBandX, bandY, v.w - rightBandX, controlPad)
					if inLeft or inRight then
						fail(
							where,
							string.format(
								"%s (%s) sits under the %s control: x %.0f..%.0f, y %.0f..%.0f",
								r.name, r.class, inLeft and "movement" or "jump",
								r.sx, r.sx + r.sw, r.sy, r.sy + r.sh
							)
						)
					end
				end

				-- 4. how much of the screen the panels cover between them. Only the panels
				-- themselves (depth 2, the children of the scaling root) count: adding their
				-- rows and labels on top would count the same pixels several times over.
				if r.shown and (r.class == "Frame" or r.class == "ScrollingFrame") and r.depth == 2 then
					local area = r.sw * r.sh
					-- Skip a full-screen container: a second scaling root is not furniture.
					if area > 0 and area < v.w * v.h * 0.98 then
						shownArea += area
						if worst == nil or area > worst.area then
							worst = { name = r.name, area = area }
						end
					end
				end
			end
		end

		local coverage = shownArea / (v.w * v.h)
		print(string.format(
			"   %-16s %4dx%-4d  panels cover %5.1f%%   biggest: %-14s %s",
			v.name, v.w, v.h, coverage * 100, worst and worst.name or "-",
			if hidden > 0 then string.format("(%d closed, position unmeasured)", hidden) else ""
		))

		-- 5. the original complaint, as a number: on a phone the HUD must not own the screen.
		if v.touch and coverage > 0.5 then
			fail(v.name, string.format("panels cover %.0f%% of the screen", coverage * 100))
		end
	end

	------------------------------------------------------------------------------------ done

	for _, e in h:errors() do
		table.insert(failures, "[scheduler] " .. e)
	end

	print("")
	if #failures == 0 then
		print("PASS — " .. cfg.game .. " fits every viewport checked.")
		return true
	end

	print("FAIL — " .. tostring(#failures) .. " problem(s):")
	for _, f in failures do
		print("   " .. f)
	end
	error(cfg.game .. " HUD check failed", 0)
end

return HudCheck
