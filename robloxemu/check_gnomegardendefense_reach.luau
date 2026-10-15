-- Gnome Garden Defense: what a player can REACH, on an 844x390 phone, through the real client scripts (REVIEW-1).
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_reach.luau
--
-- REVIEW-1's reach findings, each walked as a player would: a finger on the screen (tests/Tap.luau: the camera the
-- player sees, an independent projection, a UserInputService.TouchTap), the HUD's own buttons, the character's
-- own steps. Checked:
--   0. a bed that arrives after the scripts started (streaming) still takes taps, and its pads still glow;
--   1. the first view shows the whole garden under the HUD, and the highscore board, near the spawn;
--   2. EVERY pad is reached in at most two taps, the one that counts on a cell of 44 px or more (a finger 9 px
--      off the centre of a small cell first), and a tap on a gnome's body picks its pad;
--   3. a spring bed cannot sell itself into a dead end on the reveal (the SELL button shows the full refund);
--   4. a live hazard zooms the view onto the gardener, the red ring 44 px or more; PAUSE right after a short walk
--      is not undone by that walk;
--   5. there is ground through the hedge gap and outside every hedge;
--   6. next to the board the camera reads it; out of the garden the ordinary camera follows the player;
--   8. a mouse on a 1280x720 desktop picks without the zoom;
--   9. a capture rig that marks the camera ExternalCamera is never fought.
-- REVIEW-2 (reach reviewer), walked the same way:
--  10. on a phone a tap on a small cell zooms and picks nothing; the pick is the second tap, on a big cell, and
--      the picked pad is drawn gold in the world (a finger 12 px off centre opened ANOTHER pad's sheet 42% of the
--      time, and nothing showed which pad the sheet was for);
--  11. the whole-garden view puts no pad under Roblox's thumbstick or jump button, on four phone sizes;
--  12. a tap on the board in the board view opens no gnome sheet (it picked pads hidden behind the board);
--  13. PAUSE while walking says "stand still" instead of flickering, and a step right after a pause resumes it
--      (the wake was refused with "Slow down a little");
--  14. the pads that see the most path glow all game, not only before the first gnome (the brag's 33.6 min assumes
--      a player who plants on one of them).
-- Headless limits, stated: nothing renders, there is no physics and no finger; every claim about how it LOOKS
-- and FEELS is on EYECANDY.md's needs-Studio list.

local Harness = require("./emu/harness")
local Tap = require("../gnome-garden-defense/tests/Tap")
local PathGen = require("../gnome-garden-defense/src/shared/PathGen")
local Cfg = require("../gnome-garden-defense/src/shared/Config")

local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-reach", viewport = { 844, 390 }, touch = true })
local tap = Tap.bind(h, { Vector2 = Vector2, Vector3 = Vector3 })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 9501
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
local me = h:join("Sprout", UID)
h:advance(0.3)
local char = h.Players:simulateSpawn(me, h.workspace)
h:advance(0.3)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.WoodPlanks
hum.MoveDirection = Vector3.new(0, 0, 0)
local garden
for _, g in h.workspace.Gardens:GetChildren() do
	if g:GetAttribute("Owner") == UID then garden = g end
end
assert(garden, "the garden")
local function attr(n) return garden:GetAttribute(n) end
local origin = Vector3.new(attr("OriginX"), attr("OriginY"), attr("OriginZ"))
local path = PathGen.fromText(Cfg, attr("PathCells"))
local pads = PathGen.pads(Cfg, path)

--============================================================ 0. the bed arrives after the client scripts started
local bed = garden:FindFirstChild("Bed")
bed.Parent = nil -- streaming: the bed is not there yet when the scripts start
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Garden.client"))
assert(h:tryRun("client/Board.client"))
assert(h:tryRun("client/View.client"))
local clock = 0
local function frames(seconds)
	local dt = 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
		clock += dt
	end
end
local state = me.PlayerGui:FindFirstChild("GardenClientState")
local hud = me.PlayerGui.GardenHud.Root
-- what the player SEES of a selection: the pad drawn gold (neon, red over green, little blue); the pads that
-- glow are neon green. Spelled out here, not read from the game's config.
local function looks(d)
	if not (d:IsA("BasePart") and d:GetAttribute("PadId")) then return nil end
	if d.Material ~= Enum.Material.Neon then return "plain" end
	local c = d.Color
	if c.R >= 0.9 and c.G >= 0.55 and c.G <= 0.88 and c.B <= 0.4 then return "gold" end
	if c.G > c.R and c.G > c.B then return "glow" end
	return "other"
end
local function padsLooking(how)
	local out = {}
	local b = garden:FindFirstChild("Bed")
	for _, d in (if b then b:GetChildren() else {}) do
		if looks(d) == how then table.insert(out, d:GetAttribute("PadId")) end
	end
	table.sort(out)
	return out
end
local function goldPad()
	local g = padsLooking("gold")
	return if #g == 1 then g[1] else nil
end
local cam = h.workspace.CurrentCamera
local function inset() return state:GetAttribute("Inset") or 36 end
frames(1)
do
	tap.pad(garden, 1)
	frames(0.6)
	tap.pad(garden, 1) -- on a phone the first tap on a small cell zooms (REVIEW-2); the second picks
	frames(0.6)
	truthy(hud.GnomeSheet.Visible, "with no bed streamed in yet, a tap on pad 1 already opens the gnome sheet")
	eq(state:GetAttribute("SelectedPad"), 1, "(for pad 1)")
	hud.GnomeSheet.CloseButton.Activated:Fire()
	bed.Parent = garden -- the bed streams in
	frames(1.5)
	local pulsing = 0
	for _, d in bed:GetChildren() do
		local rim = d:GetAttribute("PadId") and d:FindFirstChild("Rim")
		if rim and rim.Transparency < 0.5 then pulsing += 1 end
	end
	truthy(pulsing >= 1, "once it arrives, its best pads glow (" .. pulsing .. " pulsing now)")
end
frames(Cfg.Camera.ZoomIdleSeconds + 1.5)

--============================================================ 1. the first view
do
	eq(cam.CameraType, Enum.CameraType.Scriptable, "the garden view has the camera")
	eq(state:GetAttribute("ViewMode"), "overview", "and shows the whole garden")
	-- the HUD's top rows end at the bottom of Garden.client's row (the band chip and PAUSE), read off the GUI
	-- itself (below the inset, as Tap reports), not off the WorldTop the HUD publishes for the view: the sweep's
	-- M35 (WorldTop 0) survived a check that took the HUD's word for it (REVIEW-2)
	local skyRoot = me.PlayerGui.GardenSky.Root
	local pb = skyRoot.PauseButton
	local top = (pb.Position.Y.Offset + pb.Size.Y.Offset) * skyRoot:FindFirstChildOfClass("UIScale").Scale
	local under, off = 0, 0
	for i in pads do
		local sx, sy = tap.project(tap.padCentre(garden, i))
		if not tap.onScreen(tap.padCentre(garden, i)) then off += 1 end
		if sy < top then under += 1 end
	end
	eq(off, 0, "every pad is on screen from the spawn")
	eq(under, 0, "and none is under the HUD's top rows")
	local smallest = math.huge
	for i in pads do
		local w, ht = tap.cellPx(garden, i)
		smallest = math.min(smallest, w, ht)
	end
	print(string.format("  the first view: %d pads, the smallest cell %.1f px (the zoom takes it from there)", #pads, smallest))
	truthy(tap.onScreen(hrp.Position), "the gardener is in the first view")
	local board = h.workspace.GardenBoards:FindFirstChild("GardenBoard_" .. UID)
	truthy(board ~= nil, "the board stands")
	if board then
		local face = board.Position
		local sx, sy = tap.project(face)
		truthy(tap.onScreen(face) and sy >= top, string.format("the highscore board is in the first view (at %.0f, %.0f)", sx, sy))
		local spawn = garden:FindFirstChild("Spawn_" .. UID)
		local d = ((board.Position - spawn.Position) * Vector3.new(1, 0, 1)).Magnitude
		print(string.format("  the board stands %.1f studs from the spawn", d))
		truthy(d <= 45, "and near the spawn (" .. string.format("%.1f", d) .. " studs, at most 45)")
	end
end

--============================================================ 2. every pad, in at most two taps
local NUDGE = { { 9, 0 }, { 0, 9 }, { -9, 0 }, { 0, -9 } }
local function waitOverview()
	if hud.GnomeSheet.Visible then hud.GnomeSheet.CloseButton.Activated:Fire() end
	local t = 0
	while state:GetAttribute("ViewMode") ~= "overview" and t < 8 do
		frames(0.5)
		t += 0.5
	end
	frames(1)
end
do
	local worstTaps, retaps, smallestUsed = 0, 0, math.huge
	local wrong = {}
	for i in pads do
		waitOverview()
		local sx, sy = tap.project(tap.padCentre(garden, i))
		local w0, h0 = tap.cellPx(garden, i)
		local n = NUDGE[i % #NUDGE + 1]
		if math.min(w0, h0) < 44 then sx, sy = sx + n[1], sy + n[2] end
		tap.at(sx, sy)
		frames(0.6)
		local taps = 1
		if goldPad() ~= i then -- the player sees which pad is gold (REVIEW-2: not the hidden SelectedPad)
			tap.pad(garden, i)
			frames(0.4)
			taps = 2
			retaps += 1
		end
		worstTaps = math.max(worstTaps, taps)
		if state:GetAttribute("SelectedPad") ~= i or goldPad() ~= i then table.insert(wrong, i) end
		local w, ht = tap.cellPx(garden, i)
		smallestUsed = math.min(smallestUsed, w, ht)
	end
	print(string.format("  every pad: %d of %d needed a second tap; the cell under the deciding tap was at least %.1f px", retaps, #pads, smallestUsed))
	eq(#wrong, 0, "every pad of the bed is selected in at most two taps (" .. table.concat(wrong, ",") .. ")")
	truthy(worstTaps <= 2, "(at most two)")
	truthy(smallestUsed >= 44, string.format("and the tap that selects it lands on a cell of 44 px or more (smallest %.1f)", smallestUsed))
	-- a tap on a gnome's body picks its pad
	waitOverview()
	tap.pad(garden, 3)
	frames(0.6)
	if goldPad() ~= 3 then tap.pad(garden, 3) frames(0.4) end
	hud.GnomeSheet.Slot1.Activated:Fire()
	frames(0.5)
	local gnome = bed.Gnomes:FindFirstChild("Gnome_3")
	truthy(gnome ~= nil, "a pebble planted from the sheet")
	waitOverview()
	if gnome then
		tap.world(gnome.Head.Position)
		frames(0.6)
		-- on a phone the first tap on a small cell only zooms (REVIEW-2); the head is tapped again, now big
		if goldPad() ~= 3 then tap.world(gnome.Head.Position) frames(0.4) end
		eq(state:GetAttribute("SelectedPad"), 3, "a tap on the gnome's head picks its pad")
		truthy(string.find(hud.GnomeSheet.Slot1.Text, "UPGRADE", 1, true) ~= nil, "and opens its upgrade sheet")
	end
	-- a tap on nothing (the sky above the garden) zooms back out at once
	tap.at(422, 5)
	frames(0.8)
	eq(state:GetAttribute("ViewMode"), "overview", "a tap on nothing goes back to the whole garden")
end

--============================================================ 3. no dead end on the reveal
do
	waitOverview()
	local g3 = bed.Gnomes:FindFirstChild("Gnome_3")
	tap.world(g3.Body.Position)
	frames(0.6)
	if goldPad() ~= 3 then tap.world(g3.Body.Position) frames(0.4) end
	eq(hud.GnomeSheet.Slot2.Text, "SELL\n+50", "on the reveal the SELL button offers everything back (+50)")
	hud.GnomeSheet.Slot2.Activated:Fire()
	frames(0.5)
	for _ = 1, 5 do
		waitOverview()
		tap.pad(garden, 7)
		frames(0.6)
		if goldPad() ~= 7 then tap.pad(garden, 7) frames(0.4) end
		hud.GnomeSheet.Slot1.Activated:Fire()
		frames(0.5)
		waitOverview()
		local m = bed.Gnomes:FindFirstChild("Gnome_7")
		if m == nil then break end -- nothing could be planted: the seeds ran out (asserted below)
		tap.world(m.Body.Position)
		frames(0.6)
		if goldPad() ~= 7 then tap.world(m.Body.Position) frames(0.4) end
		hud.GnomeSheet.Slot2.Activated:Fire()
		frames(0.5)
	end
	eq(attr("Seeds"), 120, "six plant-and-sell tries on the reveal leave the bed its 120 seeds")
	eq(#bed.Gnomes:GetChildren(), 0, "(no gnome standing)")
	-- and so a gnome is always affordable, and READY can follow
	waitOverview()
	tap.pad(garden, 7)
	frames(0.6)
	if goldPad() ~= 7 then tap.pad(garden, 7) frames(0.4) end
	hud.GnomeSheet.Slot1.Activated:Fire()
	frames(0.5)
	eq(#bed.Gnomes:GetChildren(), 1, "a gnome can always be planted again")
end

--============================================================ 14. the best pads glow all game, for the starred gnome (REVIEW-2)
-- The brag's 33.6 min is a NORMAL player's, who plants on one of the three pads that see the most path for the
-- gnome they plant; the game showed three pads only until the first gnome stood (as a rim mostly hidden under the
-- pad), and never which gnome. Now the sheet stars a gnome and the three best FREE pads for it glow neon green
-- while there is room for a gnome. Worked out here independently: the starred gnome is the unlocked one furthest
-- below its share of 4 : 1.5 : 2 : 1.5 (Pebble, Sprinkler, Mushroom, Lantern; spring unlocks the first two), and
-- a pad's worth is the path studs within that gnome's level-1 range (14, 12, 13, 18) of the pad's centre (0.5-stud
-- samples), ties to the lower pad number.
do
	waitOverview()
	local SHARE = { pebble = 4, sprinkler = 1.5, mushroom = 2, lantern = 1.5 }
	local RANGE = { pebble = 14, sprinkler = 12, mushroom = 13, lantern = 18 }
	local ORDER = { "pebble", "sprinkler" } -- spring
	local function starred()
		local have, n = {}, 0
		for _, m in bed.Gnomes:GetChildren() do
			local k = m:GetAttribute("Kind")
			have[k] = (have[k] or 0) + 1
			n += 1
		end
		local wsum = 0
		for _, k in ORDER do wsum += SHARE[k] end
		local best, gap = nil, -math.huge
		for _, k in ORDER do
			local g = SHARE[k] / wsum * (n + 1) - (have[k] or 0)
			if g > gap + 1e-9 then best, gap = k, g end
		end
		return best
	end
	local function ranked()
		local taken = {}
		for _, m in bed.Gnomes:GetChildren() do taken[m:GetAttribute("Pad")] = true end
		local r = RANGE[starred()]
		local out = {}
		for id, pd in pads do
			if not taken[id] then
				local cover = 0
				for k = 1, path.n + 1 do
					local dx, dz = path.px[k] - pd.cx, path.pz[k] - pd.cz
					if dx * dx + dz * dz <= r * r then cover += 0.5 end
				end
				table.insert(out, { id = id, cover = cover })
			end
		end
		table.sort(out, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
		return out
	end
	local function best3()
		local r = ranked()
		local out = {}
		for k = 1, math.min(3, #r) do table.insert(out, r[k].id) end
		table.sort(out)
		return table.concat(out, ",")
	end
	frames(0.6)
	print("  starred now: " .. starred() .. "; glowing " .. table.concat(padsLooking("glow"), ","))
	eq(table.concat(padsLooking("glow"), ","), best3(), "with a gnome standing, the three best free pads for the starred gnome still glow")
	-- the sheet stars that gnome
	local want = ranked()[1].id
	tap.pad(garden, want)
	frames(0.6)
	if goldPad() ~= want then tap.pad(garden, want) frames(0.4) end
	local slotOf = { pebble = 1, sprinkler = 2 }
	local starSlot = hud.GnomeSheet["Slot" .. slotOf[starred()]]
	truthy(string.sub(starSlot.Text, 1, 3) == "★", "the sheet stars that gnome (" .. starSlot.Text .. ")")
	local others = 0
	for i = 1, 4 do
		local b = hud.GnomeSheet["Slot" .. i]
		if b ~= starSlot and string.find(b.Text, "★", 1, true) then others += 1 end
	end
	eq(others, 0, "and only that one")
	-- plant it on the best pad, through the screen: the glow moves on
	local before3 = best3()
	starSlot.Activated:Fire()
	frames(0.8)
	truthy(bed.Gnomes:FindFirstChild("Gnome_" .. want) ~= nil, "(the starred gnome planted on the best pad)")
	eq(table.concat(padsLooking("glow"), ","), best3(), "the glow moves on to the next three best free pads for the next starred gnome")
	truthy(best3() ~= before3, "(they are another three now)")
end

--============================================================ 7. a live hazard zooms on the gardener
do
	waitOverview()
	-- garden time in a band with hazards, set as the server replicates it (the bed is on its reveal: the server
	-- has nothing new to publish meanwhile)
	garden:SetAttribute("Phase", "build")
	garden:SetAttribute("Progress", 15.5)
	local seen, ringPx, t = false, 0, 0
	while t < 260 and not seen do
		frames(0.5)
		t += 0.5
		if state:GetAttribute("HazardLive") == true then
			frames(0.6)
			if state:GetAttribute("HazardLive") == true then
				seen = true
				eq(state:GetAttribute("ViewMode"), "hazard", "a live hazard zooms the view onto the gardener")
				local ring = h.workspace.GardenLocal:FindFirstChild("HazardZone")
				if ring then
					local c = ring.Position
					local r = ring.Size.Y / 2 -- a Cylinder's diameter is its Y and Z size
					local x0 = tap.project(c - Vector3.new(r, 0, 0))
					local x1 = tap.project(c + Vector3.new(r, 0, 0))
					ringPx = math.abs(x1 - x0)
				end
			end
		end
	end
	truthy(seen, "a hazard came within 260 s of garden time")
	print(string.format("  the red ring during the zoom: %.0f px across", ringPx))
	truthy(ringPx >= 44, "the red ring is 44 px or more across while it is live")
	-- a pad tapped while the hazard has the camera (the nearest one, on screen in the hazard's view): the sheet
	-- stays open after the hazard, so the view must come back to that pad zoomed, not to the whole garden
	local near, nearPx = nil, 0
	if seen then
		for i in pads do
			local w, ht = tap.cellPx(garden, i)
			if tap.onScreen(tap.padCentre(garden, i)) and math.min(w, ht) > nearPx then near, nearPx = i, math.min(w, ht) end
		end
		print(string.format("  during the hazard, pad %s is the biggest on screen: %.1f px", tostring(near), nearPx))
		if near then tap.pad(garden, near) end
		frames(0.3)
	end
	local t2 = 0
	while state:GetAttribute("HazardLive") == true and t2 < 10 do frames(0.5) t2 += 0.5 end
	frames(1.5)
	if near then
		eq(state:GetAttribute("SelectedPad"), near, "a pad tapped during the hazard is selected")
		local w, ht = tap.cellPx(garden, near)
		truthy(math.min(w, ht) >= 44, string.format("and after the hazard the view shows it zoomed (%.1f px), the sheet still open", math.min(w, ht)))
		hud.GnomeSheet.CloseButton.Activated:Fire()
		frames(Cfg.Camera.ZoomIdleSeconds + 1.5)
	end
	eq(state:GetAttribute("ViewMode"), "overview", "and the view goes back to the whole garden after it")
	garden:SetAttribute("Phase", "reveal") -- back to what the server holds
	garden:SetAttribute("Progress", 0)
	frames(1)
end

--============================================================ 4. PAUSE right after a short walk
-- The server polls the character once a second (Config.Net.ActivityPollSeconds) and a 4-stud step resumes a paused
-- garden. Two series of 10 tries:
--   a. a walk of 6 studs at 10 studs/s, PAUSE 0.30-0.93 s after stopping (REVIEW-1's original probe);
--   b. a walk of 6.4 studs at Roblox's default WalkSpeed (16 studs/s), PAUSE 0.0-0.2 s after stopping. Every try
--      of series b lasts exactly 3.7 s, so its ten tries meet the once-a-second poll at ten DIFFERENT phases (0.7 s
--      apart, mod 1): a pause that is not re-based at the press is undone in every try whose last poll saw the
--      walk's first 1.6 studs or less. Series a alone let that defect survive when the poll's phase was lucky.
do
	hud.ReadyButton.Activated:Fire()
	frames(2)
	eq(attr("Phase"), "wave", "a wave is on")
	local pauseBtn = me.PlayerGui.GardenSky.Root.PauseButton
	local function series(name, steps, stride, waitOf, padTo)
		local undone, took = 0, 0
		for try = 0, 9 do
			local dir = if try % 2 == 0 then 1 else -1
			hum.MoveDirection = Vector3.new(dir, 0, 0)
			for _ = 1, steps do
				hrp.CFrame = hrp.CFrame + Vector3.new(stride * dir, 0, 0)
				frames(0.1)
			end
			hum.MoveDirection = Vector3.new(0, 0, 0)
			local w = waitOf(try)
			frames(w)
			pauseBtn.Activated:Fire()
			frames(0.3)
			local on = attr("Paused") == true
			if on then took += 1 end
			frames(2)
			if on and attr("Paused") ~= true then undone += 1 end
			-- unpause for the next try
			pauseBtn.Activated:Fire()
			frames(0.8 + padTo(w))
		end
		eq(took, 10, name .. ": PAUSE takes in every try")
		eq(undone, 0, name .. ": a pause pressed right after a short walk is never undone by that walk (10 tries)")
	end
	series("6 studs at 10 studs/s", 6, 1, function(try) return 0.3 + try * 0.07 end, function() return 0 end)
	series("6.4 studs at 16 studs/s", 4, 1.6, function(try) return 0.1 * (try % 3) end, function(w) return 0.2 - w end)
end

--============================================================ 5. ground through the gap and outside every hedge
local function groundAt(x, z): string?
	local p = Vector3.new(x, 0, z)
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			local l = d.CFrame:PointToObjectSpace(p)
			local top = d.Position.Y + d.Size.Y / 2
			if math.abs(l.X) <= d.Size.X / 2 and math.abs(l.Z) <= d.Size.Z / 2 and top <= 0.6 and top >= -1 then
				return d.Name
			end
		end
	end
	return nil
end
do
	local gz = (path.cells[1].y + 0.5) * Cfg.Tile
	local holes = {}
	for _, x in { -16.5, -18, -20, -30, -60 } do
		if not groundAt(origin.X + x, origin.Z + gz) then table.insert(holes, "gap x" .. x) end
	end
	local W = Cfg.World
	local x1 = Cfg.GridW * Cfg.Tile + W.PatchLength + W.HedgeMargin
	local z1 = Cfg.GridH * Cfg.Tile + W.DeckGap + W.DeckDepth + W.HedgeMargin
	for _, pt in { { -25, -25 }, { x1 + 8, -25 }, { -25, z1 + 8 }, { x1 + 8, z1 + 8 }, { 50, -40 }, { 50, z1 + 30 } } do
		if not groundAt(origin.X + pt[1], origin.Z + pt[2]) then table.insert(holes, pt[1] .. "," .. pt[2]) end
	end
	eq(#holes, 0, "there is ground through the hedge gap and outside every hedge (" .. table.concat(holes, " ") .. ")")
end

--============================================================ 6. the board up close; out of the garden
do
	waitOverview()
	local board = h.workspace.GardenBoards:FindFirstChild("GardenBoard_" .. UID)
	local home = hrp.CFrame
	hrp.CFrame = CFrame.new(board.Position + board.CFrame.LookVector * 6 - Vector3.new(0, board.Size.Y / 2 - 2.5, 0))
	frames(1.5)
	eq(state:GetAttribute("ViewMode"), "board", "next to your board the camera turns to read it")
	local _, yTop = tap.project(board.Position + Vector3.new(0, board.Size.Y / 2, 0))
	local _, yBot = tap.project(board.Position - Vector3.new(0, board.Size.Y / 2, 0))
	local share = (yBot - yTop) / cam.ViewportSize.Y
	print(string.format("  up close the board is %.0f%% of the screen's height", share * 100))
	truthy(share >= 0.4, "and fills at least 40% of the screen's height")
	-- out through the hedge gap, onto the meadow: the ordinary camera follows
	local gz = (path.cells[1].y + 0.5) * Cfg.Tile
	hrp.CFrame = CFrame.new(origin + Vector3.new(-40, 3, gz))
	frames(1)
	eq(state:GetAttribute("ViewMode"), "free", "out of the garden the garden view lets go")
	eq(cam.CameraType, Enum.CameraType.Custom, "and Roblox's own camera follows the player")
	hrp.CFrame = home
	frames(1.5)
	eq(cam.CameraType, Enum.CameraType.Scriptable, "back in the garden, the garden view again")
end

--============================================================ 13. PAUSE while walking; a step right after a pause (REVIEW-2)
do
	waitOverview()
	if attr("Phase") ~= "wave" then hud.ReadyButton.Activated:Fire() frames(2) end
	local pauseBtn = me.PlayerGui.GardenSky.Root.PauseButton
	local overlay = me.PlayerGui.GardenSky.Root.PausedOverlay
	local R = h.ReplicatedStorage.GardenRemotes
	local function toasts()
		local out = {}
		for _, rec in R.Toast:sentTo(me) do table.insert(out, tostring(rec.args[1])) end
		return out
	end
	local home = hrp.CFrame
	local everPaused, told, slowDown = 0, 0, 0
	for try = 1, 5 do
		local t0 = #toasts()
		local dir = if try % 2 == 0 then -1 else 1
		hum.MoveDirection = Vector3.new(dir, 0, 0)
		for _ = 1, 8 + try do -- walking at Roblox's default 16 studs/s
			hrp.CFrame = hrp.CFrame + Vector3.new(1.6 * dir, 0, 0)
			frames(0.1)
		end
		pauseBtn.Activated:Fire()
		local saw = false
		for _ = 1, 20 do
			hrp.CFrame = hrp.CFrame + Vector3.new(1.6 * dir, 0, 0)
			frames(0.1)
			if attr("Paused") == true then everPaused += 1 break end
			if overlay.Visible and string.find(string.lower(overlay.Text), "stand still", 1, true) then saw = true end
		end
		if saw then told += 1 end
		local all = toasts()
		for i = t0 + 1, #all do
			if string.find(all[i], "Slow down", 1, true) then slowDown += 1 end
		end
		hum.MoveDirection = Vector3.new(0, 0, 0)
		hrp.CFrame = home
		frames(1)
		if attr("Paused") == true then pauseBtn.Activated:Fire() frames(1) end
	end
	eq(everPaused, 0, "PAUSE pressed while walking does not flicker the garden paused (5 tries)")
	eq(told, 5, "it says what to do instead: stand still (5 of 5)")
	eq(slowDown, 0, "and nobody is told to slow down")
	-- a pause, then the thumbstick 0.1 s later: the wake comes 0.4 s after the pause, inside the server's 0.5 s
	-- cooldown, and must still land
	local resumed, refused = 0, 0
	for _ = 1, 5 do
		local t0 = #toasts()
		pauseBtn.Activated:Fire()
		frames(0.1)
		local paused = attr("Paused") == true
		hum.MoveDirection = Vector3.new(1, 0, 0)
		frames(1.2)
		hum.MoveDirection = Vector3.new(0, 0, 0)
		if paused and attr("Paused") == false then resumed += 1 end
		local all = toasts()
		for i = t0 + 1, #all do
			if string.find(all[i], "Slow down", 1, true) then refused += 1 end
		end
		frames(1)
	end
	eq(resumed, 5, "a pause, then a step 0.1 s later: the step resumes the garden every time (5 tries)")
	eq(refused, 0, "and the wake is never refused with 'Slow down'")
	hrp.CFrame = home
	frames(1)
end

--============================================================ 10. a phone tap: the zoom first, then the pick, drawn gold (REVIEW-2)
-- The reviewer's probe, as a player: from the whole-garden view a finger lands 12 px off a pad's centre (4
-- directions, every pad). REVIEW-2 measured that it opened ANOTHER pad's sheet 78 times in 184. Now that first tap
-- only zooms; the player then taps the pad they meant (again 12 px off its centre, now on a big cell).
do
	-- the wave section 4 started would play on (and be lost) through these ten minutes of taps: PAUSE first (a pad
	-- can be picked and its sheet opened while paused; nothing here plants)
	if attr("Paused") ~= true then
		me.PlayerGui.GardenSky.Root.PauseButton.Activated:Fire()
		frames(0.6)
	end
	eq(attr("Paused"), true, "(the garden is paused while the taps are measured)")
	waitOverview()
	local firstSheets, wrong, none, notGold, total = 0, 0, 0, 0, 0
	-- a pad with a gnome standing right in front of it (south, toward the camera) is left out: a finger below its
	-- centre is on that gnome's body, and a tap on a gnome picks the gnome (REVIEW-1)
	local front = {}
	for _, m in bed.Gnomes:GetChildren() do
		local g = pads[m:GetAttribute("Pad")]
		if g then front[g.x .. "," .. (g.y - 1)] = true end
	end
	local skipped = 0
	for i, pd in pads do
		if front[pd.x .. "," .. pd.y] then skipped += 1 continue end
		for _, d in { { 12, 0 }, { 0, 12 }, { -12, 0 }, { 0, -12 } } do
			local sx, sy = tap.project(tap.padCentre(garden, i))
			tap.at(sx + d[1], sy + d[2])
			frames(0.4)
			total += 1
			if hud.GnomeSheet.Visible then firstSheets += 1 end
			sx, sy = tap.project(tap.padCentre(garden, i))
			tap.at(sx + d[1], sy + d[2])
			frames(0.3)
			local sel = state:GetAttribute("SelectedPad")
			if not hud.GnomeSheet.Visible then none += 1 elseif sel ~= i then wrong += 1 end
			if hud.GnomeSheet.Visible and goldPad() ~= sel then notGold += 1 end
			waitOverview()
		end
	end
	print(string.format("  a finger 12 px off centre, %d tries (%d pads behind a gnome left out): %d first taps opened a sheet; then %d wrong pads, %d nothing",
		total, skipped, firstSheets, wrong, none))
	eq(firstSheets, 0, "on a phone the first tap on a small cell opens no sheet (it zooms)")
	eq(wrong, 0, "the second tap, 12 px off centre on the zoomed cell, picks the pad it meant")
	eq(none, 0, "(and always picks one)")
	eq(notGold, 0, "the picked pad, and only it, is drawn gold while its sheet is open")
	-- shut, the gold goes
	waitOverview()
	eq(#padsLooking("gold"), 0, "with the sheet shut no pad is gold")
	-- a zoom nobody follows up eases back to the whole garden
	local sx, sy = tap.project(tap.padCentre(garden, 1))
	tap.at(sx, sy)
	frames(0.5)
	eq(state:GetAttribute("ViewMode"), "zoom", "(the first tap zoomed)")
	truthy(hud.Hint.Visible and hud.Hint.Text == "Tap the pad you want", "and the HUD says what comes next (" .. hud.Hint.Text .. ")")
	frames(8)
	eq(state:GetAttribute("ViewMode"), "overview", "a zoom without a pick goes back to the whole garden by itself")
	truthy(not (hud.Hint.Visible and hud.Hint.Text == "Tap the pad you want"), "and the hint goes with it")
end

--============================================================ 11. no pad under the thumbstick or the jump button (REVIEW-2)
-- The zones as robloxemu/emu/hudcheck.luau draws Roblox's touch controls: the bottom band (min(150, 35% of the
-- height)), its left 35% (the thumbstick) and its right 25% (the jump button). And, wider, the frame Roblox's
-- DynamicThumbstick takes touches in as REVIEW-2 recalled it (the left 40% of the lower two thirds; Studio must
-- confirm it: EYECANDY.md §7). Spelled out here.
do
	local report = {}
	local under, inStick = 0, 0
	for _, vp in { { 844, 390 }, { 568, 320 }, { 640, 300 }, { 926, 428 } } do
		h:setViewport(vp[1], vp[2])
		frames(0.5)
		waitOverview()
		local W, H = vp[1], vp[2]
		local bandY = H - math.min(150, math.floor(H * 0.35))
		local n, small = 0, math.huge
		for i in pads do
			local c = tap.padCentre(garden, i)
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, dx in { -4, 4 } do
				for _, dz in { -4, 4 } do
					local px, py = tap.project(c + Vector3.new(dx, 0, dz))
					py += inset()
					x0, y0, x1, y1 = math.min(x0, px), math.min(y0, py), math.max(x1, px), math.max(y1, py)
				end
			end
			if y1 > bandY and (x0 < 0.35 * W or x1 > 0.75 * W) then n += 1 end
			if x0 < 0.4 * W and y1 > H / 3 then inStick += 1 end
			local w, ht = tap.cellPx(garden, i)
			small = math.min(small, w, ht)
		end
		under += n
		table.insert(report, string.format("%dx%d: %d under a control, smallest cell %.1f px", W, H, n, small))
	end
	print("  the whole-garden view: " .. table.concat(report, "; ") .. "; in the 40% x 2/3 thumbstick frame: " .. inStick)
	eq(under, 0, "on four phone sizes no pad of the whole-garden view lies under the thumbstick or the jump button")
	eq(inStick, 0, "nor in the DynamicThumbstick's wider frame (the left 40% of the lower two thirds)")
	h:setViewport(844, 390)
	frames(0.5)
	waitOverview()
end

--============================================================ 12. a tap on the board in the board view (REVIEW-2)
do
	local board = h.workspace.GardenBoards:FindFirstChild("GardenBoard_" .. UID)
	local home = hrp.CFrame
	hrp.CFrame = CFrame.new(board.Position.X, hrp.Position.Y, board.Position.Z + 2.5)
	frames(2)
	eq(state:GetAttribute("ViewMode"), "board", "(standing at the board, the camera reads it)")
	local seq0 = state:GetAttribute("PickSeq") or 0
	local sheets, taps = 0, 0
	for gx = -6, 6, 2 do
		for gy = -4, 4, 2 do
			tap.world(board.Position + Vector3.new(gx, gy, 0.3))
			frames(0.1)
			taps += 1
			if hud.GnomeSheet.Visible then
				sheets += 1
				hud.GnomeSheet.CloseButton.Activated:Fire()
				frames(0.1)
			end
		end
	end
	eq(sheets, 0, taps .. " taps on the board's face open no gnome sheet")
	eq(state:GetAttribute("PickSeq") or 0, seq0, "and pick no pad hidden behind it")
	hrp.CFrame = home
	frames(1.5)
end

--============================================================ 8. a mouse on a desktop picks without the zoom
do
	h:setTouch(false)
	h:setViewport(1280, 720)
	frames(1)
	waitOverview()
	-- a pad no gnome stands in front of (south of it, between it and the camera): a gnome would be what is clicked
	local target = nil
	for i, pd in pads do
		local blocked = false
		for _, m in bed.Gnomes:GetChildren() do
			local g = pads[m:GetAttribute("Pad")]
			if g and g.x == pd.x and (g.y == pd.y + 1 or g.y == pd.y) then blocked = true end
		end
		if not blocked and target == nil and i >= 5 then target = i end
	end
	local sx, sy = tap.project(tap.padCentre(garden, target))
	local w, ht = tap.cellPx(garden, target)
	print(string.format("  desktop 1280x720: pad %d's cell is %.1f x %.1f px in the whole-garden view", target, w, ht))
	local uis = h.game:GetService("UserInputService")
	uis.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(sx, sy, 0) }, false)
	frames(0.6)
	eq(state:GetAttribute("SelectedPad"), target, "a mouse click picks the pad under it")
	eq(state:GetAttribute("ViewMode"), "overview", "without zooming (a mouse is not a finger)")
end

--============================================================ 9. another camera owner (a capture rig) is never fought
do
	cam:SetAttribute("ExternalCamera", true)
	local rig = CFrame.new(origin + Vector3.new(0, 40, 140), origin + Vector3.new(48, 0, 36))
	cam.CFrame = rig
	frames(1)
	eq(state:GetAttribute("ViewMode"), "external", "a camera marked ExternalCamera is left to its owner")
	truthy((cam.CFrame.Position - rig.Position).Magnitude < 1e-6, "and the garden view does not move it")
	cam:SetAttribute("ExternalCamera", nil)
	frames(1.5)
	eq(state:GetAttribute("ViewMode"), "overview", "cleared, the garden view takes it back")
end

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(("gnome garden reach: %d passed, %d failed"):format(passed, failed))
