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
--         warmup = function(harness, player) --[[ optional, see below ]] end,
--     })
--
-- `warmup` is optional and exists because a HUD control that is BUILT BY A REMOTE HANDLER does
-- not exist yet when the client script finishes loading. This harness never fires a remote on
-- its own, so such a control is silently absent for the whole run and every rule below scores
-- it as a pass — which is how the anomaly tint swatches, the headline example of the tap-target
-- change, shipped at 16x16 with a green gate. A runner that has controls in that shape supplies
-- a function; it is handed the harness and the joined player after the client scripts load and
-- before the first viewport is measured, and is expected to push whatever state those controls
-- are built from. Runners without such controls omit it and nothing changes for them.
--
-- One game per process: the harness installs globals into the calling thread and refuses a
-- second install.

local Harness = require("./harness")

local HudCheck = {}

-- Viewports worth caring about. The phone ones are why this file exists; the desktop ones are
-- the regression guard, because the fix must not move anything on a monitor.
-- The list is ORDERED, and two adjacent entries deliberately share a pixel size while flipping
-- the touch flag. That pair is not decoration: a HUD that only re-lays-out on
-- Camera.ViewportSize never re-runs when the size does not change, so it carries the previous
-- entry's sizing into a viewport where the tap-target rules differ. Every viewport used to have a
-- distinct size, which meant ViewportSize always re-fired and masked a missing TouchEnabled
-- listener in three of four games. Mouse comes FIRST in the pair, so the stale state under test
-- is the small mouse sizing being measured against the touch rules — the direction that fails.
-- Do not reorder or dedupe these.
HudCheck.VIEWPORTS = {
	{ name = "phone landscape", w = 800, h = 360, touch = true },
	{ name = "small phone", w = 640, h = 300, touch = true },
	{ name = "phone portrait", w = 414, h = 800, touch = true },
	-- a mouse window below the 900px compact threshold: takes the compact branch with no touch
	-- growth, which nothing else in this list exercises
	{ name = "small mouse window", w = 800, h = 600, touch = false },
	{ name = "tablet", w = 1024, h = 768, touch = true },
	{ name = "laptop", w = 1366, h = 768, touch = false },
	-- the flag-flip pair: same 1366x768, mouse then touch (a Windows touch laptop is a real
	-- device, and this is the pair that catches a missing TouchEnabled listener)
	{ name = "laptop, touch", w = 1366, h = 768, touch = true },
	{ name = "desktop", w = 1920, h = 1080, touch = false },
	-- and the same flip at phone size, where the consequences are worst
	{ name = "phone landscape, mouse", w = 800, h = 360, touch = false },
	{ name = "phone landscape, touch again", w = 800, h = 360, touch = true },
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
	-- Things the gate deliberately does NOT claim to have checked. Printed at the end, because a
	-- silent skip reads as a pass and that is how two defects reached a live game.
	local unverified = {}
	local function fail(where: string, msg: string)
		table.insert(failures, "[" .. where .. "] " .. msg)
	end

	-- A ScrollingFrame's canvas must cover its content or the last rows are unreachable.
	-- CanvasSize is design px, AbsoluteContentSize is screen px; mixing the two silently costs a
	-- phone player the bottom of the list while a 1080p monitor looks perfect. Position plays no
	-- part, so this is checked on hidden panels too.
	local function checkCanvas(r, viewportName: string)
		-- A frame using AutomaticCanvasSize has its CanvasSize written by the shim, not by the
		-- game. Comparing that back against the same content figure grades the shim against
		-- itself and passes no matter what the game does, so it is reported as unverified
		-- rather than counted as a pass.
		if r.obj:GetAttribute("__emuAutoCanvas") then
			table.insert(unverified, string.format("%s (AutomaticCanvasSize, %s)", r.name, viewportName))
			return
		end
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

	-- Optional per-game warmup: build the controls that only a remote push creates, before
	-- anything is measured. A failure here is fatal rather than a recorded failure, because a
	-- warmup that did not run means the rest of the run is measuring less than it reports.
	if cfg.warmup ~= nil then
		assert(type(cfg.warmup) == "function", "config.warmup must be a function(harness, player)")
		local okWarm, warmErr = pcall(cfg.warmup, h, player)
		if not okWarm then
			error("config.warmup failed, so the HUD was never fully populated: " .. tostring(warmErr), 0)
		end
		h:advance(0.1)
		print(string.format("   warmup %-28s ran", "config.warmup"))
	end

	----------------------------------------------------------------- geometry, per viewport

	for _, v in viewports do
		-- Touch FIRST, then the viewport. A HUD re-lays-out when Camera.ViewportSize changes and
		-- reads UserInputService.TouchEnabled while doing it, so setting the viewport first laid
		-- the page out against the PREVIOUS iteration's touch flag — the mouse-driven laptop run
		-- was measured with the tablet's touch still on. Two agents hit the resulting
		-- disagreement between the checker and the HUD independently before it was found here.
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		-- Give the HUD's handlers a beat to run.
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
	if #unverified > 0 then
		local seen, uniq = {}, {}
		for _, u in unverified do
			local key = string.match(u, "^[^(]+") or u
			if not seen[key] then
				seen[key] = true
				table.insert(uniq, key)
			end
		end
		print("NOT VERIFIED by this gate (" .. tostring(#uniq) .. "): " .. table.concat(uniq, ", "))
		print("")
	end
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
