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

local store = h.services.DataStoreService:GetDataStore("GrowCrystal_v1")
store:SetAsync("p_" .. ME, {
	dust = 500, seeds = { [1] = 3 }, chambers = START_CHAMBERS,
	luckLevel = 0, growthLevel = 0, plants = {}, codex = {}, redeemed = {},
	lastGeodeWeek = -1, totalDust = 0, passes = {},
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

-- The pad is the one thing that WAS parented, so it is the control: if the pad is missing too,
-- the failure is "nothing was built", not "the sockets were orphaned", and the diagnosis differs.
local pad = nil
local function findPad(node)
	for _, c in node:GetChildren() do
		if string.match(tostring(c.Name), "^Pad_") then pad = c; return end
		findPad(c)
	end
end
findPad(h.workspace)
truthy(pad ~= nil, "the plot pad is in the workspace (control: the builder ran at all)")

--=============================================================== and clicking one actually plants

local first = sockets[1]
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
	local second = sockets[2]
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
