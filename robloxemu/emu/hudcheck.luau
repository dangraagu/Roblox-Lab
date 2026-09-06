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

		local shownArea, worst = 0, nil

		for _, gui in playerGui:GetChildren() do
			for _, r in h:guiRects(gui, v.w, v.h) do
				if not r.shown then
					continue
				end

				-- 1. nothing may hang off the screen. A pixel of rounding is not a bug.
				local slack = 1
				if r.sx < -slack or r.sy < -slack or r.sx + r.sw > v.w + slack or r.sy + r.sh > v.h + slack then
					fail(
						v.name,
						string.format(
							"%s (%s) is off screen: x %.0f..%.0f, y %.0f..%.0f in %dx%d",
							r.name, r.class, r.sx, r.sx + r.sw, r.sy, r.sy + r.sh, v.w, v.h
						)
					)
				end

				-- 2. nothing tappable may sit under Roblox's own touch controls
				if controlPad > 0 and INTERACTIVE[r.class] then
					local inLeft = overlaps(r.sx, r.sy, r.sw, r.sh, 0, bandY, leftBandW, controlPad)
					local inRight =
						overlaps(r.sx, r.sy, r.sw, r.sh, rightBandX, bandY, v.w - rightBandX, controlPad)
					if inLeft or inRight then
						fail(
							v.name,
							string.format(
								"%s (%s) sits under the %s control: x %.0f..%.0f, y %.0f..%.0f",
								r.name, r.class, inLeft and "movement" or "jump",
								r.sx, r.sx + r.sw, r.sy, r.sy + r.sh
							)
						)
					end
				end

				-- 3. how much of the screen the panels cover between them
				if r.class == "Frame" or r.class == "ScrollingFrame" then
					local area = r.sw * r.sh
					-- Skip a full-screen container: the scaling root is not furniture.
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
			"   %-16s %4dx%-4d  panels cover %5.1f%%   biggest: %s",
			v.name, v.w, v.h, coverage * 100, worst and worst.name or "-"
		))

		-- 4. the original complaint, as a number: on a phone the HUD must not own the screen.
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
