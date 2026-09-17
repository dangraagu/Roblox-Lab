-- Steal a Cryptid - THE PLAYER'S PATH, walked in the built world, from join into a second loop.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       cd ../steal-a-cryptid && luau tests/walk.luau 2>&1
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green unit tests are not a working game: this repo shipped a game with 166 green tests whose core
-- loop was unreachable. So this file is a PLAYER, held to what a player can actually do:
--   * it runs the REAL HUD client and presses its buttons (Hunt panel "Enter", "Build", the build
--     sheet's "Snare" and "Laser"); the only remote it fires itself is none;
--   * it presses an in-world prompt only when its root is inside that prompt's
--     MaxActivationDistance, and clicks a build tile only inside its ClickDetector's reach. A press
--     out of reach is a FAIL, not a press;
--   * it walks at 16 studs/s, one 0.1 s step at a time, and every step on the apron is checked
--     against the collidable Parts in the WORKSPACE for a 2 x 2-stud body. A blocked step is a FAIL;
--   * in a camp it follows the solver's padded route through the camp the server actually built,
--     and every sampled position is checked the same way.
-- The game's modules are used to PLAN (a route, a cell to trap), never to predict an outcome: every
-- outcome printed is read back from the server's State, its toasts, and the workspace.
--
-- What this cannot tell you: whether any of it FEELS right, whether a person times a net like the
-- padded route does (it is a well-timed player, not a new one), physics, rendering, touch input.

local Harness = require("../../robloxemu/emu/harness")
local Datatypes = require("../../robloxemu/emu/datatypes")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Layout = require("../src/shared/Layout")
local Heist = require("../src/shared/Heist")
local Economy = require("../src/shared/Economy")

local h = Harness.new({
	bundle = require("../../robloxemu/build/steal-a-cryptid"),
	name = "steal-a-cryptid-walk",
	viewport = { 1280, 720 },
	touch = false,
})
local inst = h.instance
local sched = h.scheduler
local V3, CF = Datatypes.Vector3, Datatypes.CFrame
local ServerStorage = h.game:GetService("ServerStorage")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function le(a, b, msg)
	if type(a) == "number" and a <= b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want <= " .. tostring(b))
	end
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local R = {}
for _, n in { "State", "Toast", "Fx" } do R[n] = remotes:FindFirstChild(n) end

local WALKER = 31337
local plr = h:join("Walker", WALKER)
local okHud, hudErr = h:tryRun("client/Hud.client")
truthy(okHud, "the real HUD client loads: " .. tostring(hudErr))
local joinedAt = sched:now()
local function T() return sched:now() - joinedAt end
local function st()
	local sent = R.State:sentTo(plr)
	return sent[#sent].args[1]
end
local toastSeen = 0
local function newToasts()
	local out = {}
	local sent = R.Toast:sentTo(plr)
	for i = toastSeen + 1, #sent do table.insert(out, tostring(sent[i].args[1])) end
	toastSeen = #sent
	return out
end
local function say(fmt, ...) print(string.format("[t=%6.1f] " .. fmt, T(), ...)) end
local function sayToasts()
	for _, t in newToasts() do print("           toast: " .. t) end
end
local function hud() return plr.PlayerGui.CryptidHud.Root end
local function descendants(root)
	local out = {}
	local function walk(node)
		for _, c in inst.stateOf(node).children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(root)
	return out
end

local lairs = h.workspace:FindFirstChild("Lairs")
local function myPlot()
	for _, plot in lairs:GetChildren() do
		local lair = plot:FindFirstChild("Lair")
		if lair and string.find(tostring(plot.Sign.Label.Text.Text), plr.Name, 1, true) then return plot, lair end
	end
end
local function frameOf(plot) return plot.Floor.CFrame * CF.new(-36, 0.5, -48) end
local function hrp() return plr.Character.HumanoidRootPart end
local RH = Config.World.RootHeight

--============================================================================ moving like a body

-- A 2 x 2-stud body with its root at RootHeight: blocked by any CanCollide Part that overlaps its
-- footprint between 0.6 studs above the floor (a step it can take) and 5.5 (its head).
local function collidersIn(roots, floorY)
	local out = {}
	for _, root in roots do
		for _, d in descendants(root) do
			if d:IsA("BasePart") and d.CanCollide ~= false then
				local top, bottom = d.Position.Y + d.Size.Y / 2, d.Position.Y - d.Size.Y / 2
				if top > floorY + 0.6 and bottom < floorY + 5.5 then table.insert(out, d) end
			end
		end
	end
	return out
end
local function blockedAt(colliders, pos)
	for _, d in colliders do
		local lp = d.CFrame:PointToObjectSpace(V3.new(pos.X, d.Position.Y, pos.Z))
		if math.abs(lp.X) < d.Size.X / 2 + 1 and math.abs(lp.Z) < d.Size.Z / 2 + 1 then return d end
	end
	return nil
end

local blockedSteps = {}
local walked = 0
local function walkTo(target, colliders)
	local from = hrp().Position
	local goal = V3.new(target.X, from.Y, target.Z)
	local d = (goal - from).Magnitude
	local steps = math.max(1, math.ceil(d / (Config.Raid.WalkSpeed * 0.1)))
	for i = 1, steps do
		local p = from:Lerp(goal, i / steps)
		local b = colliders and blockedAt(colliders, p)
		if b then table.insert(blockedSteps, string.format("(%.1f, %.1f) inside %s", p.X, p.Z, b:GetFullName())) end
		hrp().CFrame = CF.new(p)
		h:advance(0.1)
	end
	walked += d
	return d
end

-- Everything on the apron stands on z 6..10 (pedestals, board); z 3 in front of it is a clear lane.
local plot, lair, frame, apronColliders
local function apron(x, z) return frame:PointToWorldSpace(V3.new(x, RH, z)) end
local function walkApron(x, z)
	local lp = frame:PointToObjectSpace(hrp().Position)
	local d = 0
	if math.abs(lp.Z - 3) > 0.05 then d += walkTo(apron(lp.X, 3), apronColliders) end
	d += walkTo(apron(x, 3), apronColliders)
	d += walkTo(apron(x, z), apronColliders)
	return d
end

local presses = 0
local function inReach(prompt)
	local d = (hrp().Position - prompt.Parent.Position).Magnitude
	return d <= prompt.MaxActivationDistance, d
end
local function press(prompt, what)
	local ok, d = inReach(prompt)
	truthy(ok, string.format("%s: the %s prompt is in reach when pressed (%.2f of %.2f studs)", what, prompt.Name, d, prompt.MaxActivationDistance))
	if not ok then return false end
	presses += 1
	prompt.Triggered:Fire(plr)
	return true
end
local function pressButton(button, what)
	truthy(button ~= nil and button.Visible ~= false, what .. ": the " .. tostring(button and button.Name) .. " button is on screen")
	if button then button.Activated:Fire() end
end

--============================================================================ spawn

h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.2)
plot, lair = myPlot()
frame = frameOf(plot)
apronColliders = collidersIn({ plot, h.workspace.Road }, frame.Position.Y)
local landedAt = T()
do
	local lp = frame:PointToObjectSpace(hrp().Position)
	say("spawned on %s; the root landed at plot-local (%.2f, %.2f), %.2f studs from the arrival marker (36, 8)", plot.Name, lp.X, lp.Z,
		math.sqrt((lp.X - 36) ^ 2 + (lp.Z - 8) ^ 2))
	truthy(math.abs(lp.X - 36) < 1 and math.abs(lp.Z - 8) < 1, "the walker lands on its own arrival marker")
	-- The HUD script starts after the server's join-time State push. Roblox queues a remote event
	-- until the client connects; the emulator does not, so here the HUD fills on the next once-a-
	-- second push. Measured, not assumed away:
	while hud().Hint.Text == "" and T() < 2 do h:advance(0.1) end
	local s = st()
	say("HUD hint (first State the HUD saw): '%s'", hud().Hint.Text)
	truthy(string.find(hud().Hint.Text, "Buy your first cryptid", 1, true) ~= nil, "the HUD names the first action")
	say("Essence %d, rate %d/s, Journal %d/%d; P1 %s %d, P2 %s %d, P3 %s %d", s.essence, s.rate, s.journal, s.journalMax,
		s.offers[1].name, s.offers[1].price, s.offers[2].name, s.offers[2].price, s.offers[3].name, s.offers[3].price)
end

--============================================================================ LOOP 1: buy, collect, raid

print("\n== LOOP 1")
local d = walkApron(Config.World.Apron.P1.x, 4.5)
press(lair.Pedestals.Pedestal_1.Buy, "first purchase")
h:advance(0.05)
local boughtAt = T()
do
	local s = st()
	say("walked %.1f studs to P1 and pressed Buy: Essence %d, rate %d/s, Journal %d/8, P3 now %s (%s) at %d", d, s.essence, s.rate,
		s.journal, s.offers[3].name, if s.offers[3].tier == 2 then "Rare" else "tier " .. s.offers[3].tier, s.offers[3].price)
	sayToasts()
	eq(s.cages[5].sp, "jackalope", "loop 1: the first purchase is the Jackalope in the centre cage")
	le(boughtAt - landedAt, 5, "loop 1: the core action happens within 5 s of landing (checklist section 4)")
end

while not st().collectHint and T() < 60 do h:advance(0.5) end
say("the Collect Pad hint shows: '%s' (centre jar %.1f)", hud().Hint.Text, st().cages[5].jar)
truthy(st().collectHint, "loop 1: the collect hint appears")

d = walkApron(Config.World.Apron.Pad.x, Config.World.Apron.Pad.z)
local e0 = st().essence
lair.CollectPad.Touched:Fire(hrp())
h:advance(0.05)
do
	local s = st()
	say("walked %.1f studs onto the pad: Essence %d -> %d; hint now '%s'", d, e0, s.essence, hud().Hint.Text)
	sayToasts()
	truthy(s.essence > e0, "loop 1: stepping on the pad pays")
end

local function raidInfo() return ServerStorage.RaidInfo:FindFirstChild(tostring(WALKER)) end
local function routeAt(route, t)
	if t <= route[1].t then return route[1].x, route[1].z end
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		if t <= b.t then
			local f = if b.t > a.t then (t - a.t) / (b.t - a.t) else 1
			return a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
		end
	end
	return route[#route].x, route[#route].z
end

-- Walk to the board, open it with its prompt, press the camp's Enter on the HUD panel, follow a
-- padded route through the camp the server built, hold the grab prompt on the grab cell.
local function raid(tier, label)
	local walkedTo = walkApron(Config.World.Apron.Board.x, 4.5)
	press(lair.HuntBoard.Hunt, label)
	h:advance(0.1)
	truthy(hud().HuntPanel.Visible, label .. ": the board's prompt opens the HUD's Hunt panel")
	local row = hud().HuntPanel:FindFirstChild("Camp_" .. tier)
	say("%s: walked %.1f studs to the board; panel row reads '%s' [%s]", label, walkedTo, row.Label.Text, row.Go.Text)
	local before = st()
	pressButton(row.Go, label)
	local info = raidInfo()
	if not info then
		say("%s: the hunt did not start", label)
		sayToasts()
		return nil
	end
	local start = sched:now()
	local camp = Layout.generateCamp(Config, Rng, info:GetAttribute("Seed"), tier)
	local pocket = h.workspace.Pockets:FindFirstChild("Pocket_" .. info:GetAttribute("Pocket"))
	local pframe = pocket.Floor.CFrame * CF.new(-36, 0.5, -56)
	local pocketColliders = collidersIn({ pocket }, pframe.Position.Y)
	local prize, prizeSp
	for _, c in camp.cages do if c.prize then prize, prizeSp = c.col, c.sp end end
	local plan = Heist.solveRaid(Config, Layout, camp, { pad = Config.Raid.HumanPad })
	say("%s: in %s (permit %d, Essence %d -> %d); %d nets, %d snares, %d rocks; prize %s in column %d",
		label, (string.gsub(tostring(pocket.CampSign.Label.Text.Text), "\n", " / ")), Economy.permit(Config, tier),
		before.essence, st().essence, Layout.count(camp, "laser"), Layout.count(camp, "snare"), #camp.rocks, prizeSp, prize)
	say("%s: padded route %.2f s (in %.2f s, grab hold %.1f s, %d timed net crossings); HUD hint '%s'", label, plan.total, plan.inTime,
		Config.Camps[tier].hold, #plan.crossings, hud().Hint.Text)
	sayToasts()
	local anchor = pocket.Cages:FindFirstChild("GrabAnchor_" .. prize)
	local hold = Config.Camps[tier].hold
	local began, fired, grabbedAt, blocked = false, false, nil, 0
	while sched:now() - start < plan.total + 3 do
		local tNext = sched:now() - start + Config.Raid.TickSeconds
		local x, z = routeAt(plan.route, tNext)
		local pos = pframe:PointToWorldSpace(V3.new(x, RH, z))
		if blockedAt(pocketColliders, pos) then blocked += 1 end
		hrp().CFrame = CF.new(pos)
		if not began and tNext >= plan.inTime then
			local ok, dist = inReach(anchor.Grab)
			truthy(ok, string.format("%s: the Grab prompt is in reach when the hold begins (%.2f of %.2f studs)", label, dist, anchor.Grab.MaxActivationDistance))
			anchor.Grab.PromptButtonHoldBegan:Fire(plr)
			began = true
		end
		h:advance(Config.Raid.TickSeconds)
		if began and not fired and sched:now() - start >= plan.inTime + hold + Config.Raid.TickSeconds then
			anchor.Grab.Triggered:Fire(plr)
			fired = true
		end
		local s = st()
		if not grabbedAt and s.raid and s.raid.carrying then grabbedAt = sched:now() - start end
		if not raidInfo() then break end
	end
	h:advance(0.1)
	local after = st()
	local took = sched:now() - start
	eq(blocked, 0, label .. ": every sampled position on the route is standable")
	local lp = frame:PointToObjectSpace(hrp().Position)
	say("%s: raid over after %.1f s (grabbed at %.1f s); Essence %d, rate %d/s -> %d/s, Journal %d -> %d, steals %d; home at (%.2f, %.2f)",
		label, took, grabbedAt or -1, after.essence, before.rate, after.rate, before.journal, after.journal, after.stats.steals, lp.X, lp.Z)
	sayToasts()
	return { stole = after.stats.steals > before.stats.steals, sp = prizeSp, took = took, plan = plan.total, home = math.abs(lp.X - 36) < 1 and math.abs(lp.Z - 8) < 1 }
end

local r1 = raid(1, "raid 1")
truthy(r1 and r1.stole, "loop 1: the first raid steals the prize")
truthy(r1 and r1.home, "loop 1: the raider is sent home")
truthy(lair.Cages:FindFirstChild("Cryptid_4") ~= nil, "loop 1: the stolen cryptid stands in cage 4")
local loop1 = T()
do
	local s = st()
	say("end of loop 1: %d cryptids, %d Essence/s, Journal %d/8, Camp 1 %s", Economy.cryptidCount(Config, { cages = s.cages }), s.rate,
		s.journal, if s.camps[1].heatLeft > 0 then "on alert " .. s.camps[1].heatLeft .. " s" else "open")
end
while T() < 60 do h:advance(0.5) end
do
	local s = st()
	say("ONE MINUTE after joining: Essence %d, rate %d/s, Journal %d/8, P3 %s at %d, Camp 2 permit %d",
		s.essence, s.rate, s.journal, s.offers[3].name, s.offers[3].price, s.camps[2].permit)
end

--============================================================================ LOOP 2: collect, defend, a poacher, a Rare raid

print("\n== LOOP 2")
local function collectUntil(untilEssence, capT, every)
	walkApron(Config.World.Apron.Pad.x, Config.World.Apron.Pad.z)
	local n = 0
	while st().essence < untilEssence and T() < capT do
		h:advance(every)
		lair.CollectPad.Touched:Fire(hrp())
		n += 1
	end
	newToasts()
	return n
end
local c = collectUntil(Config.Traps.SnarePrice * 2 + Config.Traps.LaserPrice, 280, 10)
say("stood on the Collect Pad, stepping on it every 10 s (%d collects): Essence %d at %d/s", c, st().essence, st().rate)

-- force the first fence line: snares in two gaps, a net in the third, through the HUD's Build
-- button, a click on each tile, and the build sheet's buttons
walkApron(Config.World.Apron.Arrival.x, Config.World.Apron.Arrival.z)
pressButton(hud().Toggles.BuildToggle, "build")
h:advance(0.2)
truthy(lair:FindFirstChild("BuildTiles") ~= nil, "loop 2: the Build button puts tiles on the yard")
local L = Layout.generateLair(Config, Rng, Layout.lairSeed(Config, WALKER))
local line = L.lines[1]
local function clickTile(col, row)
	local tile = lair.BuildTiles:FindFirstChild("Tile_" .. col .. "_" .. row)
	if not tile then return false end
	local dist = (hrp().Position - tile.Position).Magnitude
	truthy(dist <= tile.Click.MaxActivationDistance, string.format("tile (%d,%d) is in click reach (%.1f of %d studs)", col, row, dist, tile.Click.MaxActivationDistance))
	tile.Click.MouseClick:Fire(plr)
	h:advance(0.05)
	return hud().BuildSheet.Visible
end
local placed = nil
for _, laserCol in line.cols do
	if placed then break end
	local ok = true
	local snared = {}
	for _, col in line.cols do
		if col ~= laserCol and ok then
			if clickTile(col, line.row) then
				pressButton(hud().BuildSheet.Snare, "snare")
				h:advance(0.2)
			end
			if lair.Traps:FindFirstChild("Snare_" .. col .. "_" .. line.row) then table.insert(snared, col) else ok = false end
		end
	end
	if ok and clickTile(laserCol, line.row) then
		pressButton(hud().BuildSheet.Laser, "laser")
		h:advance(0.2)
		if lair.Traps:FindFirstChild("Laser_" .. laserCol .. "_" .. line.row) then placed = { snares = snared, laser = laserCol } end
	end
	if not placed then
		for _, col in snared do
			if clickTile(col, line.row) then pressButton(hud().BuildSheet.Clear, "clear"); h:advance(0.2) end
		end
	end
end
pressButton(hud().Toggles.BuildToggle, "build off")
h:advance(0.2)
do
	local s = st()
	say("built on fence row %d from the arrival marker: snares in gaps %s, a net in gap %s; Essence %d; %d net(s), %d snare(s)",
		line.row, table.concat(placed and placed.snares or {}, ","), tostring(placed and placed.laser), s.essence, s.lasers, s.snares)
	sayToasts()
	truthy(placed ~= nil, "loop 2: the first fence line is forced through a laser net, via the HUD")
end

-- the first poacher: 300 s into the session, once the lair holds two cryptids
walkApron(Config.World.Apron.Pad.x, Config.World.Apron.Pad.z)
local warnedAt, appearedAt, outcome, jarsAtWarning, essenceAtWarning = nil, nil, nil, 0, 0
while T() < 440 and outcome == nil do
	h:advance(0.5)
	local s = st()
	if not warnedAt and s.poacher and s.poacher.warningLeft then
		warnedAt = T()
		essenceAtWarning = s.essence
		for _, cg in s.cages do jarsAtWarning += cg.jar end
		say("POACHER WARNING: the HUD chip reads '%s'; the lair's jars hold %.0f Essence", hud().RaidChip.Text.Text, jarsAtWarning)
	end
	if warnedAt and not appearedAt and h.workspace.Poachers:FindFirstChild("Poacher_" .. string.match(plot.Name, "%d+")) then
		appearedAt = T()
		say("the poacher model appears on the gate approach %.1f s after the warning", appearedAt - warnedAt)
	end
	for _, t in newToasts() do
		print("           toast: " .. t)
		if string.find(t, "caught the poacher", 1, true) then outcome = "caught" end
		if string.find(t, "got away", 1, true) or string.find(t, "left empty-handed", 1, true) then outcome = "escaped" end
	end
end
do
	local s = st()
	say("poacher outcome: %s, %.1f s after the warning (first warning %.1f s into the session); Essence %d -> %d; poachers caught %d",
		tostring(outcome), T() - (warnedAt or T()), warnedAt or -1, essenceAtWarning, s.essence, s.stats.poachersCaught)
	truthy(warnedAt ~= nil and warnedAt >= Config.Poacher.FirstAfterSeconds, "loop 2: the first poacher warning comes no earlier than 300 s")
	truthy(appearedAt ~= nil and appearedAt - warnedAt >= Config.Poacher.WarningSeconds - 0.5, "loop 2: it appears after the full warning")
	truthy(outcome ~= nil, "loop 2: the visit resolves, caught or not")
end

-- a Rare camp: permit 360
c = collectUntil(Economy.permit(Config, 2) + 40, T() + 240, 10)
say("collected for the tier-2 permit (%d collects): Essence %d at %d/s", c, st().essence, st().rate)
local r2 = raid(2, "raid 2")
truthy(r2 ~= nil, "loop 2: the tier-2 hunt starts from the HUD")
local rares = 0
for _, cg in st().cages do if Economy.tierOf(Config, cg.sp) == 2 then rares += 1 end end
truthy(r2 and r2.stole, "loop 2: the padded route steals the tier-2 prize")
truthy(r2 and r2.home, "loop 2: the raider is sent home")
if r2 and r2.stole then eq(rares, 1, "loop 2: the stolen Rare is in a cage") end
say("after raid 2: %d Rare(s) in the lair, rate %d/s, Journal %d/8; P3 now offers %s at %d", rares, st().rate, st().journal,
	st().offers[3].name, st().offers[3].price)
eq(#blockedSteps, 0, "every apron step walked a 2 x 2 body through open space: " .. table.concat(blockedSteps, "; "))
do
	-- REVIEW-1.md B1's backstop pulls a character back only when its trusted position cannot follow;
	-- an honest walk must never meet it
	local pulled = 0
	for _, rec in R.Toast:sentTo(plr) do
		if string.find(tostring(rec.args[1]), "pulled back", 1, true) then pulled += 1 end
	end
	eq(pulled, 0, "an honest walk through two raids is never pulled back")
end

--============================================================================ leave and come back

print("\n== REJOIN")
h:advance(Config.Save.FlushTickSeconds + 1)
local final = st()
h:leave(plr)
h:advance(1)
plr = h:join("Walker", WALKER)
toastSeen = 0
h:advance(0.5)
h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local back = st()
plot, lair = myPlot()
frame = frameOf(plot)
local lp = frame:PointToObjectSpace(hrp().Position)
say("rejoined on %s, landed at (%.2f, %.2f): Essence %d (was %d), rate %d/s (was %d), Journal %d (was %d), steals %d, nets %d + snares %d",
	plot.Name, lp.X, lp.Z, back.essence, final.essence, back.rate, final.rate, back.journal, final.journal, back.stats.steals, back.lasers, back.snares)
eq(back.rate, final.rate, "rejoin: every cryptid is still caged")
eq(back.journal, final.journal, "rejoin: the Journal is kept")
eq(back.stats.steals, final.stats.steals, "rejoin: steals are kept")
eq(back.lasers + back.snares, final.lasers + final.snares, "rejoin: the traps are kept")
truthy(back.essence >= final.essence - 1, "rejoin: the Essence is kept")
truthy(math.abs(lp.X - 36) < 1 and math.abs(lp.Z - 8) < 1, "rejoin: the character lands on the arrival marker again")

print("")
print(string.format("SUMMARY  first purchase %.1f s after landing; loop 1 ended at %.1f s; raid 1 %.1f s (plan %.2f); poacher %s; raid 2 %s; walked %.0f studs; %d prompt presses, all in reach; final %d Essence, %d/s, Journal %d/8, steals %d, caught %d, poachers caught %d",
	boughtAt - landedAt, loop1, r1 and r1.took or -1, r1 and r1.plan or -1, tostring(outcome),
	if r2 then string.format("%.1f s (plan %.2f)", r2.took, r2.plan) else "not started", walked, presses,
	final.essence, final.rate, final.journal, final.stats.steals, final.stats.caught, final.stats.poachersCaught))

for _, w in h.warnings do print("  [warn] " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("steal a cryptid WALK: %d passed, %d failed", passed, failed))
if failed > 0 then error("walk failed", 0) end
