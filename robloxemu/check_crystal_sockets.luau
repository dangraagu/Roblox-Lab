-- Grow a Crystal — the sockets have to be IN THE WORLD, and clicking one has to plant.
-- Run: luau check_crystal_sockets.luau   (regenerate the bundle first, see check_crystal.luau)
--
-- makeSocket built the socket Part, sized it, positioned it, glowed it, named it, gave it its
-- attributes, and parented a ClickDetector TO it - and never assigned `part.Parent`. So every
-- socket existed only as a value in the `socketParts` Lua table: not in the workspace, never
-- replicated, and its ClickDetector could not fire because the detector was inside an orphan.
-- refreshSocketVisual then parented the crystal to that same orphan, so growing plants were
-- invisible too.
--
-- That is the entire core loop of a published game. Plant, watch it grow, harvest, refract -
-- none of it was reachable. A player on Reddit reported "i cant even place a seed" and the fix
-- that shipped was free starter seeds, which addressed a cause that was not the binding one.
--
-- An unparented Instance is the quietest bug in Roblox. Nothing raises, nothing warns, the
-- function returns a perfectly good Part, and any test that checks the returned value or the
-- server's own bookkeeping table passes. The only thing that catches it is asking the workspace.
-- So this file asks the workspace, and then clicks.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local ME = 5150
local START_CHAMBERS, PER_CHAMBER = 1, 6 -- Config.Economy.StartChambers / SocketsPerChamber

-- The server stores under "u_<uid>" and reads the profile out of `.data`; this file used to
-- write "p_<uid>" with the profile at the top level, so the seed silently never loaded and every
-- run below was really testing defaultProfile(). Written the way loadProfile actually reads it,
-- with enough Dust to afford the second chamber (chamberCost(1) = 500).
local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
-- Socket 4 starts with a crystal planted long ago, so it is already mature when the plot builds
-- and the HARVEST half of the loop can be exercised. `at = 1` is 1970; every growth stage is
-- long done. The integer key goes through the emulator's real JSON round-trip on write, so
-- loadProfile's numKeys normalisation is exercised rather than assumed.
local PLANTED = 4
store:SetAsync("u_" .. ME, {
	data = {
		dust = 5000, seeds = { [1] = 3 }, chambers = START_CHAMBERS,
		luckLevel = 0, growthLevel = 0,
		plants = { [PLANTED] = { tier = 1, at = 1 } },
		codex = {}, redeemed = {},
		lastGeodeWeek = -1, totalDust = 0, passes = {},
	},
})

assert(h:tryRun("server/Main.server"))
h:advance(1)

local me = h:join("Planter", ME)
h:advance(1)
h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

--======================================================== the sockets are actually in the world

local sockets = {}
local function walk(node)
	for _, c in node:GetChildren() do
		if string.match(tostring(c.Name), "^Socket_") then table.insert(sockets, c) end
		walk(c)
	end
end
walk(h.workspace)

print(string.format("  sockets reachable from workspace: %d", #sockets))
truthy(#sockets > 0, "the sockets are parented into the workspace at all")
eq(#sockets, START_CHAMBERS * PER_CHAMBER,
	"a new player gets exactly one chamber's worth of sockets")

-- Named for THIS player: with several plots in one server, a socket has to belong to somebody.
local mine = 0
for _, s in sockets do
	if string.match(tostring(s.Name), "^Socket_" .. ME .. "_") then mine += 1 end
	truthy(s:GetAttribute("SocketId") ~= nil, "socket " .. tostring(s.Name) .. " carries its id")
end
eq(mine, #sockets, "every socket in the world is tagged with its owner")

-- CONTROL. The flat 48x1x60 pad is gone (the cavern replaces it), so the control is now the
-- plot folder: if THAT is missing too, the failure is "nothing was built", not "the sockets were
-- orphaned", and the diagnosis differs. The pad must also be provably gone, or a half-applied
-- change would leave players standing on a slab inside the rock.
local plots = h.workspace:FindFirstChild("Plots")
truthy(plots ~= nil, "workspace.Plots exists (control: the builder ran at all)")
local plot0 = plots and plots:FindFirstChild("Plot_0")
truthy(plot0 ~= nil, "the joining player got workspace.Plots.Plot_0")

local pads = 0
local function findPads(node)
	for _, c in node:GetChildren() do
		if string.match(tostring(c.Name), "^Pad_") then pads += 1 end
		findPads(c)
	end
end
findPads(h.workspace)
eq(pads, 0, "the old flat pad is gone")

-- Part and light budget for a 1-chamber player: 125 always-present + 21 lock caps + 2 dust
-- hosts + 6 sockets = 154 BaseParts, and TEN PointLights. The preset sets ClockTime = 0, so
-- there is no sun and no fill: if the lamps do not parent, the cavern is pitch black and
-- completely silent about it. Counting them is the only thing that catches that.
if plot0 ~= nil then
	local baseParts, lights = 0, 0
	for _, d in plot0:GetDescendants() do
		if d:IsA("BasePart") then baseParts += 1 end
		if d.ClassName == "PointLight" then lights += 1 end
	end
	print(string.format("  Plot_0: %d BaseParts, %d PointLights", baseParts, lights))
	-- 154 is the empty-plot figure. This player joins with one crystal already grown on socket
	-- 4 (that is what makes the harvest test below possible), and the plot also holds an
	-- invisible SpawnLocation, so the expected count is 156. Spelled out rather than folded into
	-- the constant: if the pre-planted crystal ever stops rendering, this is what notices.
	eq(baseParts, 156, "a 1-chamber player with one crystal growing holds exactly 156 BaseParts")
	eq(lights, 10, "a 1-chamber player's plot holds exactly 10 PointLights")
end

--=========================================================== the spawn point is INSIDE the cavern

-- A live play session found the player standing at y=51 on the cavern's own CeilFront - on the
-- ROOF of a sealed shell, 55 studs from the nearest socket against a 32-stud click range. With no
-- SpawnLocation anywhere, Roblox drops the character above the highest ground at the origin, and
-- setting the root part's CFrame afterwards lost a race with the engine's own placement.
--
-- The emulator has no gravity and no spawn behaviour, so it cannot reproduce that. What it CAN
-- check is the thing that made the fix work: a SpawnLocation exists, and it is under the ceiling
-- rather than on top of it.
if plot0 ~= nil then
	local spawns = {}
	local ceilingY = nil
	for _, d in plot0:GetDescendants() do
		if d.ClassName == "SpawnLocation" then table.insert(spawns, d) end
		if d:IsA("BasePart") and string.match(tostring(d.Name), "^Ceil") then
			local underside = d.Position.Y - d.Size.Y / 2
			if ceilingY == nil or underside < ceilingY then ceilingY = underside end
		end
	end
	eq(#spawns, 1, "the plot carries exactly one SpawnLocation")
	truthy(ceilingY ~= nil, "the cavern has a ceiling to be under")
	if spawns[1] ~= nil and ceilingY ~= nil then
		print(string.format("  spawn y=%.1f   ceiling underside y=%.1f", spawns[1].Position.Y, ceilingY))
		truthy(spawns[1].Position.Y < ceilingY,
			"the spawn point is UNDER the ceiling, not on top of the cavern")
		truthy(spawns[1].Parent == plot0 or spawns[1]:IsDescendantOf(plot0),
			"the spawn point lives in the plot folder, so teardown takes it with everything else")
	end
end

--=============================================================== and clicking one actually plants

local byId = {}
for _, s in sockets do byId[s:GetAttribute("SocketId")] = s end

local first = byId[1]
if first == nil then
	failed += 1
	print("FAIL: no socket to click, so the plant path cannot be exercised")
else
	local cd = first:FindFirstChildOfClass("ClickDetector")
	truthy(cd ~= nil, "the socket carries a ClickDetector")

	local before = first:FindFirstChild("Crystal")
	eq(before, nil, "nothing is growing there yet")

	if cd ~= nil then
		cd.MouseClick:Fire(me)
		h:advance(1)
		local after = first:FindFirstChild("Crystal")
		truthy(after ~= nil, "clicking an empty socket planted a seed that is visible in the world")
	end

	-- Someone else's click must do nothing. The server checks `clicker ~= plr`, and this is the
	-- assertion that keeps that check honest.
	local other = h:join("Stranger", 6161)
	h:advance(0.5)
	local second = byId[2]
	if second ~= nil then
		local cd2 = second:FindFirstChildOfClass("ClickDetector")
		if cd2 ~= nil then
			cd2.MouseClick:Fire(other)
			h:advance(1)
			eq(second:FindFirstChild("Crystal"), nil,
				"a stranger clicking my socket plants nothing")
		end
	end
end

--=============================================================== and harvesting one actually pays

-- The OTHER half of the core loop, and it had no coverage at all. A review mutation removed the
-- grown crystal's own ClickDetector - the same defect class as the unparented sockets, applied
-- to harvesting - and the entire suite stayed green. A crystal you cannot click is a crystal you
-- cannot sell, which is the whole economy.
local grown = byId[PLANTED]
if grown == nil then
	failed += 1
	print("FAIL: socket " .. PLANTED .. " is missing, so harvest cannot be exercised")
else
	local crystal = grown:FindFirstChild("Crystal")
	truthy(crystal ~= nil, "the crystal planted before this session is standing in the world")
	if crystal ~= nil then
		local cd = crystal:FindFirstChildOfClass("ClickDetector")
		truthy(cd ~= nil, "the grown crystal carries its OWN ClickDetector, not just the plate")

		local ls = me:FindFirstChild("leaderstats")
		local dustValue = ls and ls:FindFirstChild("Dust")
		truthy(dustValue ~= nil, "the player has a Dust readout to check against")

		if cd ~= nil and dustValue ~= nil then
			local before = dustValue.Value
			cd.MouseClick:Fire(me)
			h:advance(1)
			truthy(dustValue.Value > before,
				string.format("harvesting paid out (%d -> %d dust)", before, dustValue.Value))
			eq(grown:FindFirstChild("Crystal"), nil, "the harvested crystal is gone from the world")
		end
	end
end

--================================================ buying a chamber opens it, and the rubble goes

-- A locked chamber is covered by three non-colliding rubble slabs tagged with its index. Buying
-- the chamber must both add its six sockets AND take that cap away; the cap is never a wall, so
-- the worst a missed sweep can do is leave a rock over working sockets.
if plot0 ~= nil then
	local function capsFor(c)
		local n = 0
		for _, d in plot0:GetDescendants() do
			if d:GetAttribute("Chamber") == c then n += 1 end
		end
		return n
	end
	eq(capsFor(1), 3, "chamber 1 is capped with rubble before it is bought")

	local buy = h.services.ReplicatedStorage:FindFirstChild("CrystalRemotes"):FindFirstChild("Buy")
	buy:simulateFireServer(me, "chamber", nil)
	h:advance(1)

	eq(capsFor(1), 0, "buying chamber 1 removed its rubble cap")
	local now = 0
	local function count(node)
		for _, c in node:GetChildren() do
			if string.match(tostring(c.Name), "^Socket_" .. ME .. "_") then now += 1 end
			count(c)
		end
	end
	count(h.workspace)
	eq(now, 2 * PER_CHAMBER, "buying a chamber added its six sockets")
end

--================================================================ leaving takes the whole plot

-- Teardown is one :Destroy() on the plot folder. Before this it walked a Lua table of sockets
-- plus a pad by name, so every cavern part would have leaked, every join, forever.
local before = #plots:GetChildren()
local ghost = h:join("Passerby", 7171)
h:advance(1)
eq(#plots:GetChildren(), before + 1, "a third player got their own plot folder")

-- Which index did they get? A freed index has to come back, or a server slowly walks its plots
-- out along +X until they are kilometres from the spawn. The teardown assertion below counts
-- FOLDERS, which a leaked index satisfies perfectly well, so the index is checked by name.
local ghostPlot = nil
for _, f in plots:GetChildren() do
	if f:FindFirstChild("Socket_7171_1", true) ~= nil then ghostPlot = f.Name end
end
truthy(ghostPlot ~= nil, "the third player's plot folder is identifiable by their sockets")

h:leave(ghost)
h:advance(1)
eq(#plots:GetChildren(), before, "leaving destroyed the whole plot, not just the sockets")

local reuser = h:join("Reuser", 8181)
h:advance(1)
local reuserPlot = nil
for _, f in plots:GetChildren() do
	if f:FindFirstChild("Socket_8181_1", true) ~= nil then reuserPlot = f.Name end
end
eq(reuserPlot, ghostPlot, "the next player REUSES the freed plot index instead of taking a new one")
h:leave(reuser)
h:advance(1)
eq(#plots:GetChildren(), before, "and that plot goes away too")

--=========================================================================================== done

print("")
eq(#h.warnings, 0, "the server built the plot without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("crystal sockets: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("crystal socket check failed", 0)
end
