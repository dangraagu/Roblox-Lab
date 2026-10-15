-- Scrapline Tycoon — THE PLAYER'S PATH, walked in the built world, printed in numbers.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       cd ../scrapline-tycoon && luau tests/walk.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green tests are not a working game (this repo once shipped 166 green tests with an unreachable core loop). This
-- file is somebody playing on a PHONE (800 x 360, touch), through the HUD only:
--   * it joins, lands on its pad, reads the hint, and taps the one-tap 🔧 Build Shredder button;
--   * every 20 s (the model's `normal` player) it taps 🏭 Line, which opens the panel on the ★'s page, finds the row
--     whose name starts with "★ " (turning the page with the column's ▼ when it has to), and taps that row's GOLD
--     button (the HUD's "affordable and starred" colour) while it stays gold; a tap counts as a HUD purchase only when
--     the server's own station state moved;
--   * when a machine sputters it notices after 4 s, walks there at 85 % of WalkSpeed to the open floor beside it,
--     and holds the Fix prompt the HUD put on that machine (0.5 s);
--   * when ♻ shows its ★ it taps it, reads the confirmation, and taps ✓ Recycle!
--   * it stands STILL between those (no steering input: a tycoon is played standing and tapping the HUD), so the
--     crane's drops it gets are the ones a real player gets (REVIEW-1 B3: an earlier walk held the stick all game
--     and hid an idle rest that froze the hazards for anyone who stood still).
-- It plays loop 1 (join -> the free Shredder -> the first purchase -> the Foundry ... -> the first Rocket's lift-off,
-- the brag moment -> the first recycle and its Gold Bolt), on into loop 2 (the free Shredder already standing, the
-- first bands again, faster), then leaves, rejoins with a fresh HUD and plays one more purchase. Every step prints
-- what happened, in numbers. It asserts only what a player would notice was broken.

-- MODE (REVIEW-2 R3): "star" (the default) taps the ★ row's gold button; "green" (`luau tests/walk.luau green`) is a
-- player who ignores the ★ and taps, at random, ANY button the panel paints gold or green, on any page, every 20 s
-- (the pacing model's `green` profile, walked through the real HUD).
local MODE = (...) or "star"
assert(MODE == "star" or MODE == "green", "walk mode: star or green")

local Harness = require("../../robloxemu/emu/harness")
local h = Harness.new({ bundle = require("../../robloxemu/build/scrapline-tycoon"), name = "scrapline-tycoon-walk",
	viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("ScraplineRemotes")
local State, Toast, FxR, Announce = remotes.State, remotes.Toast, remotes.Fx, remotes.Announce
local Config = h:_require(RS:FindFirstChild("Config"))
local PlotGeom = h:_require(RS:FindFirstChild("PlotGeom"))
local Economy = h:_require(RS:FindFirstChild("Economy"))
local Line = h:_require(RS:FindFirstChild("Line"))
local UID = 31415
local NAMES = Config.Stations.Names
local IDS = Config.Stations.Order

local plr, hrp, hum, plot, k, t0
local function join(first)
	h.game:GetService("RunService"):setIsServer(false)
	plr = h:join("Walker", UID)
	local char = h.Players:simulateSpawn(plr, h.workspace)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Concrete
	hum.MoveDirection = Vector3.new(0, 0, 0) -- standing; the stick moves only while walking to a fix
	plot = plr.RespawnLocation.Parent
	k = tonumber(string.match(plot.Name, "%d+"))
	-- every join runs the HUD again, as a new Roblox client does (Yard.client once: it builds client-only parts)
	assert(h:tryRun("client/Hud.client"))
	if first then
		assert(h:tryRun("client/Yard.client"))
		t0 = h.scheduler:now()
	end
end
local function now() return h.scheduler:now() - t0 end
local function mins(s) return string.format("%.1f min", s / 60) end
local function st()
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local function gui(path)
	local node = plr.PlayerGui
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
local function hint()
	local p = gui("ScraplineHud.Root.HintPanel")
	return if p and p.Visible then p.HintText.Text else "(none)"
end
local function chip()
	local c = gui("ScraplineYard.Root.BandChip.ChipText")
	return c and c.Text or "?"
end
local function flat(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) end
local function isColour(c, r, g, b)
	return math.abs(c.R * 255 - r) < 0.5 and math.abs(c.G * 255 - g) < 0.5 and math.abs(c.B * 255 - b) < 0.5
end
local function world(lx, lz)
	local x, z = PlotGeom.toWorld(Config, k, lx, lz)
	return Vector3.new(x, Config.World.FloorTopY + 3, z)
end

-- what the walker notices
-- wiped: a sputter still live when the walker recycled; the recycle builds new machines and clears it (Jams.
-- clearForRecycle), so it is neither saved nor jammed (REVIEW-2 R6: about 1 walk in 45 counted it as unsaved)
local counts = { buys = 0, hudBuys = 0, sputters = 0, saved = 0, fixed = 0, jammed = 0, lifts = 0, recycles = 0, wiped = 0 }
local tierAt = {} -- ["run:tier"] = seconds
local run = 1
local liftAt, liftCard, recycleAt = nil, nil, nil
FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "sputter" then counts.sputters += 1
	elseif ev.kind == "saved" then counts.saved += 1
	elseif ev.kind == "fixed" then counts.fixed += 1
	elseif ev.kind == "jammed" then counts.jammed += 1
	elseif ev.kind == "tier" then tierAt[run .. ":" .. ev.tier] = tierAt[run .. ":" .. ev.tier] or now()
	elseif ev.kind == "recycled" then counts.recycles += 1
	end
end)
Announce.OnClientEvent:Connect(function(ev)
	if type(ev) == "table" and ev.kind == "liftoff" then
		counts.lifts += 1
		liftAt = liftAt or now()
	end
end)

--============================================================================ the panel's colours (REVIEW-2 R3)
-- Every time the panel is open, every visible buy button must wear the colour the game's own rule gives it, worked
-- out here from the State: grey when unaffordable, GOLD for the ★, GREEN only for what Economy.worth calls worth it
-- (never while the ★ saves for the next station), and the muted "affordable, not now" colour for the rest.
local paint = { checked = 0, wrong = 0, greenWhileSaving = 0, first = nil }
local function colourName(c)
	local function is(r, g, b) return math.abs(c.R * 255 - r) < 0.5 and math.abs(c.G * 255 - g) < 0.5 and math.abs(c.B * 255 - b) < 0.5 end
	if is(200, 150, 40) then return "gold" end
	if is(60, 150, 90) then return "green" end
	if is(80, 80, 96) then return "grey" end
	return "muted"
end
local function auditPaint()
	local s = st()
	local panel = gui("ScraplineHud.Root.LinePanel")
	if s == nil or panel == nil or not panel.Visible then return end
	local S = {}
	for t = 1, 6 do
		local r = s.stations[t]
		S[t] = { n = r.n, L = r.L, jam = { r.jamA or 0, r.jamB or 0 } }
	end
	local w = Economy.worth(Config, Line, S, s.cash, s.mult)
	for i = 1, 6 do
		local row = panel:FindFirstChild("Row_" .. i)
		if row and row.Visible then
			local name = row.NameText.Text
			local t = nil
			for tt = 1, 6 do
				if string.find(name, NAMES[tt], 1, true) then t = tt end
			end
			if t then
				local r = s.stations[t]
				for bi, b in { row.Btn1, row.Btn2 } do
					if b.Visible and b.Text ~= "MAX" then
						local kind = if bi == 1 then "twin" elseif r.n == 0 then "build" else "up"
						local price = r.prices[kind]
						if price ~= nil then
							local want
							if s.cash < price then want = "grey"
							elseif s.star and s.star.kind == kind and s.star.t == t then want = "gold"
							elseif w[kind .. ":" .. t] then want = "green"
							else want = "muted" end
							local got = colourName(b.BackgroundColor3)
							paint.checked += 1
							if got ~= want then
								paint.wrong += 1
								paint.first = paint.first or string.format("%.1f s: %s %s $%s painted %s, want %s", now(), kind, NAMES[t], tostring(price), got, want)
							end
							if got == "green" and s.star and s.star.saving then paint.greenWhileSaving += 1 end
						end
					end
				end
			end
		end
	end
end
-- a curious player opens the panel now and then without buying (every 60 s), so the colours are seen while the ★
-- saves for the next station too, not only when it is affordable
local lastPeek = -math.huge
local function peekPanel()
	local root = gui("ScraplineHud.Root")
	local lineBtn = root.LineSlot.LineButton
	if lineBtn.Text == "🔧 Build Shredder" or root.LinePanel.Visible then return end
	lineBtn.Activated:Fire()
	h:advance(0.2)
	local pager = root.RecycleSlot
	for _ = 1, 3 do
		auditPaint()
		if not (pager.Visible and string.find(pager.RecycleButton.Text, "Page", 1, true)) then break end
		pager.RecycleButton.Activated:Fire()
		h:advance(0.1)
	end
	if root.LinePanel.Visible then lineBtn.Activated:Fire() end
	h:advance(0.1)
end

--============================================================================ the walker's habits
local lastShop = -math.huge
local SHOP_EVERY = 20 -- the model's normal player
local log = {}

-- green mode: open the panel, tap a random gold-or-green button on the page, look through every page, close
local pickState = 7
local function pick(n)
	pickState = (pickState * 1103515245 + 12345) % 2147483648
	return 1 + math.floor(pickState / 2147483648 * n)
end
local function tapCounted(btn)
	local before = st()
	local snapBefore = {}
	for t = 1, 6 do snapBefore[t] = before.stations[t].n * 1000 + before.stations[t].L end
	btn.Activated:Fire()
	h:advance(0.3) -- a person taps about three times a second
	local after = st()
	counts.buys += 1
	local moved = 0
	for t = 1, 6 do
		if after.stations[t].n * 1000 + after.stations[t].L ~= snapBefore[t] then moved += 1 end
	end
	if moved == 1 then counts.hudBuys += 1 end
end
local function greenShop(root)
	root.LineSlot.LineButton.Activated:Fire()
	h:advance(0.3)
	local panel, pager = root.LinePanel, root.RecycleSlot
	local guard, emptyPages = 0, 0
	while panel.Visible and guard < 80 do
		guard += 1
		auditPaint()
		local cands = {}
		for i = 1, 6 do
			local r = panel:FindFirstChild("Row_" .. i)
			if r and r.Visible then
				for _, b in { r.Btn1, r.Btn2 } do
					if b.Visible and (isColour(b.BackgroundColor3, 200, 150, 40) or isColour(b.BackgroundColor3, 60, 150, 90)) then
						table.insert(cands, b)
					end
				end
			end
		end
		if #cands > 0 then
			emptyPages = 0
			tapCounted(cands[pick(#cands)])
		else
			local pages = tonumber(string.match(pager.RecycleButton.Text, "/(%d+)")) or 1
			if pager.Visible and pages > 1 and emptyPages < pages - 1 then
				pager.RecycleButton.Activated:Fire()
				h:advance(0.2)
				emptyPages += 1
			else
				break
			end
		end
	end
	if panel.Visible then root.LineSlot.LineButton.Activated:Fire() end
end

-- tap 🏭 Line, find the ★ row (paging with ▼), tap its gold button while it stays gold, close
local function hudShop()
	local root = gui("ScraplineHud.Root")
	local lineBtn = root.LineSlot.LineButton
	if lineBtn.Text == "🔧 Build Shredder" then
		local before = st().stations[1].n
		lineBtn.Activated:Fire()
		h:advance(0.3)
		counts.buys += 1
		if st().stations[1].n == before + 1 then counts.hudBuys += 1 end
		return
	end
	if MODE == "green" then return greenShop(root) end
	if string.find(lineBtn.Text, "★", 1, true) == nil then return end
	lineBtn.Activated:Fire()
	h:advance(0.3)
	local panel = root.LinePanel
	local guard = 0
	local pagesTurned = 0
	while panel.Visible and guard < 40 do
		guard += 1
		local row, btn = nil, nil
		for i = 1, 6 do
			local r = panel:FindFirstChild("Row_" .. i)
			if r and r.Visible and string.sub(r.NameText.Text, 1, #"★ ") == "★ " then
				row = r
				for _, b in { r.Btn1, r.Btn2 } do
					if b.Visible and isColour(b.BackgroundColor3, 200, 150, 40) then btn = b end
				end
			end
		end
		auditPaint()
		if row == nil then
			-- the ★ moved to another page: turn it (at most once round)
			local pager = root.RecycleSlot
			if pager.Visible and pagesTurned < 6 then
				pager.RecycleButton.Activated:Fire()
				h:advance(0.2)
				pagesTurned += 1
				continue
			end
			break
		end
		if btn == nil then break end
		local before = st()
		local snapBefore = {}
		for t = 1, 6 do snapBefore[t] = before.stations[t].n * 1000 + before.stations[t].L end
		btn.Activated:Fire()
		h:advance(0.3) -- a person taps about three times a second
		local after = st()
		counts.buys += 1
		local moved = 0
		for t = 1, 6 do
			if after.stations[t].n * 1000 + after.stations[t].L ~= snapBefore[t] then moved += 1 end
		end
		if moved == 1 then counts.hudBuys += 1 end
	end
	if panel.Visible then root.LineSlot.LineButton.Activated:Fire() end -- close the panel again
end

-- a sputter: notice it after 4 s, walk there at 85 % of WalkSpeed, hold Fix (0.5 s)
local fixJob = nil
local saveTimes = {}
local function stepFix()
	local s = st()
	if fixJob == nil then
		local target = nil
		if s.sputter then target = { t = s.sputter.t, m = s.sputter.m, seen = now() } end
		if target == nil then
			for t = 1, 6 do
				local row = s.stations[t]
				if row.n >= 1 and row.jamA ~= 0 then target = { t = t, m = 1, seen = now() } break end
				if row.n >= 2 and row.jamB ~= 0 then target = { t = t, m = 2, seen = now() } break end
			end
		end
		fixJob = target
		return
	end
	if now() - fixJob.seen < 4 then return end -- noticing
	local mx, mz = PlotGeom.machinePos(Config, fixJob.t, fixJob.m)
	local goal = world(if fixJob.t <= 3 then -9.5 else 9.5, mz)
	local d = flat(hrp.Position, goal)
	if d > 0.5 then
		local step = math.min(d, 16 * 0.85 * 0.1)
		local p = hrp.Position
		hum.MoveDirection = Vector3.new((goal.X - p.X) / d * 0.85, 0, (goal.Z - p.Z) / d * 0.85)
		hrp.CFrame = CFrame.new(p.X + (goal.X - p.X) / d * step, goal.Y, p.Z + (goal.Z - p.Z) / d * step)
		return
	end
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local folder = plot:FindFirstChild("Station_" .. string.gsub(NAMES[fixJob.t], " ", ""))
	local mdl = folder and folder:FindFirstChild("Machine_" .. string.gsub(NAMES[fixJob.t], " ", "") .. "_" .. (if fixJob.m == 1 then "a" else "b"))
	local prompt = mdl and mdl.Body:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		h:advance(prompt.HoldDuration) -- hold it
		prompt.Triggered:Fire(plr)
		table.insert(saveTimes, now() - fixJob.seen + 0.5)
	end
	fixJob = nil
	hrp.CFrame = CFrame.new(world(0, -2)) -- back to the middle of the U
end

-- REVIEW-2 R4: the hint and the ★ must never disagree. Every 0.1 s of the walk: when the hint names a station's ★
-- ("Save for a Furnace ★", "Saving for the Press ★"), the HUD's ★ points at that station.
local hintClash, hintClashFirst = 0, nil
local function auditHint()
	local s = st()
	local text = hint()
	if s == nil or text == "(none)" then return end
	for t, name in NAMES do
		if string.find(text, name .. " ★", 1, true) and not (s.star and s.star.t == t) then
			hintClash += 1
			hintClashFirst = hintClashFirst or string.format("%.1f s: hint \"%s\" while the ★ is %s", now(), text,
				if s.star then s.star.kind .. " " .. NAMES[s.star.t] else "none")
		end
	end
end

local function step()
	local s = st()
	auditHint()
	if s and s.loaded then
		stepFix()
		-- the hint says "Tap Build Shredder": a person does it the moment the button shows, not on a shop round
		local lineBtn = gui("ScraplineHud.Root.LineSlot.LineButton")
		if lineBtn and lineBtn.Text == "🔧 Build Shredder" then
			hudShop()
		elseif fixJob == nil and now() - lastShop >= SHOP_EVERY then
			lastShop = now()
			hudShop()
		elseif fixJob == nil and now() - lastPeek >= 60 then
			lastPeek = now()
			peekPanel()
		end
	end
	h.game:GetService("RunService").RenderStepped:Fire(0.1)
	h:advance(0.1)
end

local function recycleThroughHud(): boolean
	local root = gui("ScraplineHud.Root")
	local btn = root.RecycleSlot.RecycleButton
	if not root.RecycleSlot.Visible or string.find(btn.Text, "★", 1, true) == nil then return false end
	btn.Activated:Fire()
	h:advance(0.3)
	local card = root.ConfirmCard
	local asked = card.Visible and string.find(card.Text, "Recycle your factory?", 1, true) ~= nil
	table.insert(log, string.format("  %s  ♻ tapped: the HUD asks again (%s): %s", mins(now()), tostring(asked), string.sub(card.Text, 1, 70)))
	if root.LineSlot.LineButton.Text ~= "✓ Recycle!" then return false end
	root.LineSlot.LineButton.Activated:Fire()
	h:advance(0.5)
	return true
end

--============================================================================ join
join(true)
for _ = 1, 6 do -- the first frames: the HUD gets its first State (pushed at most every 0.5 s)
	h.game:GetService("RunService").RenderStepped:Fire(0.1)
	h:advance(0.1)
end
print("== join (mode: " .. MODE .. ")")
print(string.format("  landed %.1f studs from the own arrival pad; hint: %s", flat(hrp.Position, plr.RespawnLocation.Position), hint()))
print("  band chip: " .. chip())
truthy(flat(hrp.Position, plr.RespawnLocation.Position) <= 4, "the walker lands on its own pad")
truthy(string.find(hint(), "Shredder", 1, true) ~= nil, "the first hint names the core action")

--============================================================================ loop 1
print("== loop 1: the free Shredder -> purchases -> the bands -> the first Rocket -> the first recycle")
local coreAt, firstBuyAt = nil, nil
local function yardProbe() return gui("ScraplineYard.YardProbe"):Invoke() end
local hzFoundry, hzLift, restFrames, frames1 = nil, nil, 0, 0
local marks = { 60, 300, 600, 1200, 1800 }
local nextMark = 1
hrp.CFrame = CFrame.new(world(0, -2))
local buys0 = 0
while counts.recycles == 0 and now() < 70 * 60 do
	step()
	if liftAt == nil then
		frames1 += 1
		if yardProbe().resting then restFrames += 1 end
	end
	if hzFoundry == nil and tierAt["1:2"] then hzFoundry = { t = tierAt["1:2"], n = yardProbe().hazardsSpawned } end
	if hzLift == nil and liftAt then hzLift = { t = liftAt, n = yardProbe().hazardsSpawned } end
	if coreAt == nil and st() and st().stations[1].n == 1 then
		coreAt = now()
		print(string.format("  %5.1f s  the free Shredder is built (one tap); income $%.1f/s; hint: %s", coreAt, st().income, hint()))
		buys0 = counts.buys
	end
	if firstBuyAt == nil and coreAt and counts.buys > buys0 then
		firstBuyAt = now()
		print(string.format("  %5.1f s  the first purchase, a tap on %s", firstBuyAt,
			if MODE == "green" then "a gold or green button" else "the ★ row's gold button"))
	end
	if nextMark <= #marks and now() >= marks[nextMark] then
		local s = st()
		local line = {}
		for t = 1, 6 do
			if s.stations[t].n > 0 then table.insert(line, string.format("%s L%d%s", string.sub(NAMES[t], 1, 4), s.stations[t].L, if s.stations[t].n == 2 then "x2" else "")) end
		end
		print(string.format("  %s  income $%s/s; %s; chip: %s", mins(now()), tostring(math.floor(s.income)), table.concat(line, ", "), chip()))
		nextMark += 1
	end
	if liftAt and liftCard == nil then
		h:advance(0.2)
		local card = gui("ScraplineHud.Root.BragCard")
		liftCard = if card and card.Visible then card.Text else "(no card)"
		local tt = gui("ScraplineHud.Root.ToastPanel.ToastText")
		print(string.format("  %s  THE FIRST ROCKET lifts off: the card reads \"%s\"; the toast: \"%s\"; chip: %s", mins(liftAt), liftCard,
			tt and tt.Text or "?", chip()))
	end
	local liveAtRecycle = st() and st().sputter ~= nil
	if liftAt and st().recycleReady and recycleThroughHud() then
		recycleAt = now()
		if liveAtRecycle then
			counts.wiped += 1
			fixJob = nil -- that machine is gone
		end
		run = 2
		for _ = 1, 5 do step() end -- a few frames: the yard follows the server's State
	end
end
for _, line in log do print(line) end
table.clear(log)
local s1 = st()
local enters = {}
for tier = 2, 6 do table.insert(enters, string.format("%s %s", Config.Env.Bands[tier].name, if tierAt["1:" .. tier] then mins(tierAt["1:" .. tier]) else "never")) end
print("  bands entered (run 1): " .. table.concat(enters, ", "))
print(string.format("  sputters %d: saved %d, fixed after jamming %d, jammed %d, wiped by the recycle %d; time from sputter to fix: %s",
	counts.sputters, counts.saved, counts.fixed, counts.jammed, counts.wiped, (function()
		local lo, hi = math.huge, 0
		for _, t in saveTimes do lo = math.min(lo, t); hi = math.max(hi, t) end
		return if #saveTimes > 0 then string.format("%.1f-%.1f s", lo, hi) else "-"
	end)()))
print(string.format("  purchases %d, %d of them taps on the HUD's own buttons", counts.buys, counts.hudBuys))
local hzN = if hzFoundry and hzLift then hzLift.n - hzFoundry.n else 0
local hzGap = if hzN > 0 then (hzLift.t - hzFoundry.t) / 60 / hzN else math.huge
print(string.format("  standing still between taps: %d crane drops from the Foundry (%s) to the first Rocket (%s), one every %.2f min; resting in %d of %d frames",
	hzN, mins(hzFoundry and hzFoundry.t or -60), mins(hzLift and hzLift.t or -60), hzGap, restFrames, frames1))
print(string.format("  %s  recycled: Gold Bolt #%d, everything ships x%s; chip: %s", mins(recycleAt or -60), s1.bolts, tostring(s1.mult), chip()))
truthy(coreAt ~= nil and coreAt <= 5, string.format("the core action happens within 5 s of joining (%.1f s)", coreAt or -1))
truthy(firstBuyAt ~= nil and firstBuyAt <= 45, string.format("the first purchase comes inside 45 s (%.1f s)", firstBuyAt or -1))
truthy(liftAt ~= nil and liftAt >= 30 * 60 and liftAt <= 45 * 60, string.format("the first Rocket lifts off between 30 and 45 min (%s)", mins(liftAt or -60)))
truthy(liftCard ~= nil and string.find(liftCard, "LIFT-OFF", 1, true) ~= nil, "the HUD shows the lift-off card")
truthy(counts.sputters > 0 and counts.saved + counts.wiped == counts.sputters and counts.wiped <= 1,
	string.format("every sputter was saved inside its 15 s (%d of %d; %d still live at the recycle)", counts.saved, counts.sputters, counts.wiped))
truthy(counts.buys > 0 and counts.hudBuys == counts.buys, string.format("every purchase was a tap on the HUD's own buttons (%d of %d)", counts.hudBuys, counts.buys))
truthy(hzGap >= 1.5 and hzGap <= 3.5, string.format("a player standing at the HUD gets about one crane drop per 2-3 min (one per %.2f min)", hzGap))
truthy(restFrames == 0, string.format("standing still at the HUD is never a rest (resting in %d frames)", restFrames))
print(string.format("  the hint named a ★ the HUD did not star in %d frames%s", hintClash, if hintClashFirst then " (first at " .. hintClashFirst .. ")" else ""))
truthy(hintClash == 0, string.format("REVIEW-2 R4: the hint never names a ★ the HUD does not star (%d frames)", hintClash))
print(string.format("  the panel's colours: %d buttons checked, %d wrong%s; green while the ★ saved for the next station: %d",
	paint.checked, paint.wrong, if paint.first then " (first: " .. paint.first .. ")" else "", paint.greenWhileSaving))
truthy(paint.checked >= 200, string.format("set-up: the panel's colours were checked on many buttons (%d)", paint.checked))
truthy(paint.wrong == 0, string.format("REVIEW-2 R3: every buy button wears the colour the game's rule gives it (%d wrong)", paint.wrong))
truthy(paint.greenWhileSaving == 0, "REVIEW-2 R3: nothing is green while the ★ saves for the next station")
truthy(recycleAt ~= nil and s1.bolts == 1, "the walker recycled through ♻ and its confirmation, for a Gold Bolt")
truthy(s1.tier <= 1 and string.find(chip(), "Junkyard", 1, true) ~= nil, "after the recycle the yard is a Junkyard again: " .. chip())
do
	local wall = plot.FactoryWall.Color
	truthy(math.abs(wall.R * 255 - 230) < 1 and math.abs(wall.G * 255 - 190) < 1, "the factory is repainted (1 bolt: safety yellow)")
end

--============================================================================ loop 2
print("== loop 2: the free Shredder is already there; the bands again, faster")
local loop2Start = now()
local s2a = st()
truthy(s2a.stations[1].n == 1 and s2a.stations[2].n == 0, "the new run starts with the free Shredder standing")
while tierAt["2:3"] == nil and now() - loop2Start < 15 * 60 do
	step()
end
local f1 = (tierAt["1:2"] or 0)
local f2 = (tierAt["2:2"] or math.huge) - loop2Start
local p1 = (tierAt["1:3"] or 0) - f1
local p2 = (tierAt["2:3"] or math.huge) - (tierAt["2:2"] or 0)
print(string.format("  run 2: the Foundry %.1f min after the recycle (run 1: %.1f min after the join); Press Works %.1f min later (run 1: %.1f)",
	f2 / 60, f1 / 60, p2 / 60, p1 / 60))
truthy(f2 < f1, "the Junkyard is shorter in run 2: the Gold Bolt pays")
truthy(p2 < p1, "and so is the Foundry")

--============================================================================ leave, rejoin, one more purchase
print("== leave and rejoin")
local before = st()
h:leave(plr)
h:advance(2)
join(false)
h:advance(0.6)
local after = st()
local same = true
for t = 1, 6 do
	if after.stations[t].n ~= before.stations[t].n or after.stations[t].L ~= before.stations[t].L then same = false end
end
print(string.format("  saved and restored: bolts %d -> %d, tier %d -> %d, cash %s -> %s; every station %s",
	before.bolts, after.bolts, before.tier, after.tier, tostring(math.floor(before.cash)), tostring(math.floor(after.cash)), if same then "the same" else "DIFFERENT"))
truthy(after.bolts == before.bolts and after.tier == before.tier and same, "the rejoin restores the bolts, the tier and every station")
local wallet = gui("ScraplineHud.Root.WalletPanel.CashText")
truthy(wallet ~= nil and string.sub(wallet.Text, 1, 1) == "$", "the rejoined player's own HUD shows the cash (" .. (wallet and wallet.Text or "no HUD") .. ")")
local buysR = counts.buys
local rStart = now()
lastShop = -math.huge
while counts.buys == buysR and now() - rStart < 120 do
	step()
end
print(string.format("  the second session's first purchase came %.1f s after the rejoin", now() - rStart))
truthy(counts.buys > buysR, "the loop runs again after a rejoin")

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	failed += 1
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
