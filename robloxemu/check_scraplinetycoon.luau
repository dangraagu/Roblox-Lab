-- Scrapline Tycoon — THE REAL PLAYER PATH, through the real server, headless.
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon.luau 2>&1
-- ALWAYS rebuild the bundle first: this file reads build/scrapline-tycoon.luau, not src/.
--
-- Why this exists: this repo once shipped 166 green unit tests with an unreachable core loop (a Part that was
-- built, sized and wired and never parented). Nothing here trusts a unit test. It asks the workspace, spawns
-- characters the way the ENGINE does (robloxemu/SPAWN-ORDER.md: CharacterAdded first, placement one frame later on
-- a SpawnLocation), runs the real HUD for the first player (the prompts it creates on its own plot, the board it
-- draws), walks a character to a sputtering machine at WalkSpeed, and reads back only what a client could see
-- (the workspace, the State / Toast remotes, leaderstats, the player's own PlayerGui) plus the
-- ServerStorage.PlotInfo debug folder. Positions are worked out by hand from DESIGN.md section 3 (a ring of 150,
-- 60 degrees apart, each plot's -Z facing the origin), never with the game's own PlotGeom.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end

local A, B, FULL1, FULL2, FULL3, FULL4 = 5150, 6161, 7001, 7002, 7003, 7004
local T = os.time()
local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
local boardStore = h.services.DataStoreService:GetOrderedDataStore("ScraplineTycoon_Board_v1")
-- four returning players with complete lines (every station twinned): the worst case for the server part budget
local full = {}
for _, id in { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" } do full[id] = { n = 2, L = 30, j = 0 } end
for _, uid in { FULL1, FULL2, FULL3, FULL4 } do
	store:SetAsync("u_" .. uid, { data = { v = 1, cash = 10, stations = full, jamIn = 200, tier = 6, bolts = 2, boltsAt = T - 500, tutorial = 4 } })
end
-- the board has somebody on it already, so the owner's rows can render
boardStore:SetAsync("u_1", 3 * 2e9 + (2e9 - (T - 1000)))
boardStore:SetAsync("u_2", 1 * 2e9 + (2e9 - (T - 900)))

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server script loads (" .. tostring(errServer) .. ")")
if not okServer then
	print(string.format("scraplinetycoon: %d passed, %d failed", passed, failed))
	error("scraplinetycoon check failed", 0)
end
h:advance(1)

local RS = h.ReplicatedStorage
local SS = h.game:GetService("ServerStorage")
local RunService = h.game:GetService("RunService")

--============================================================================ 1. the world is BUILT and PARENTED
local RING, TOP, FLOOR = 150, 1, 0.2
local function centre(k)
	local a = (k - 1) * math.pi / 3
	return math.sin(a) * RING, math.cos(a) * RING, math.sin(a), math.cos(a)
end
-- plot-local (lx, lz) -> world (x, z), by hand: local +Z is outward, local +X is (uz, -ux)
local function world(k, lx, lz)
	local cx, cz, ux, uz = centre(k)
	return cx + uz * lx + ux * lz, cz - ux * lx + uz * lz
end
local plots = h.workspace:FindFirstChild("Plots")
truthy(plots ~= nil and plots.Parent == h.workspace, "workspace.Plots exists and is parented")
local STATION_NAMES = { "Shredder", "Furnace", "Press", "Cutter", "Assembler", "RocketBay" }
local IDS = { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" }
do
	local spawns = 0
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" then spawns += 1 end
	end
	eq(spawns, 6, "exactly 6 SpawnLocations in the world: one per plot, none anywhere else")
	for k = 1, 6 do
		local plot = plots:FindFirstChild("Plot_" .. k)
		truthy(plot ~= nil and plot.Parent == plots, "Plot_" .. k .. " is built and parented")
		local pad = plot and plot:FindFirstChild("Arrival")
		truthy(pad ~= nil and pad.ClassName == "SpawnLocation", "Plot_" .. k .. " has its Arrival SpawnLocation")
		if pad then
			eq(pad.Enabled, true, "Plot_" .. k .. "'s arrival is enabled")
			eq(pad.Duration, 0, "...with no force-field bubble")
			eq(pad.Anchored, true, "...anchored")
			near(pad.Position.Y + pad.Size.Y / 2, TOP, 1e-6, "...with its top at y = 1")
			local wx, wz = world(k, 0, -30)
			near(math.sqrt((pad.Position.X - wx) ^ 2 + (pad.Position.Z - wz) ^ 2), 0, 1e-6, "...at plot-local (0, -30)")
			near(math.sqrt(pad.Position.X ^ 2 + pad.Position.Z ^ 2), 120, 1e-6, "...120 studs from the Scrap Market")
		end
		for _, name in { "Floor", "BeltLeft", "BeltRight", "ChuteBody", "Dock", "LaunchPad", "FactoryWall", "ScraplineSign" } do
			local part = plot and plot:FindFirstChild(name)
			truthy(part ~= nil and part:IsA("BasePart"), "Plot_" .. k .. " has its " .. name)
		end
		for i = 1, 6 do
			truthy(plot and plot:FindFirstChild("BeltTurn_" .. i) ~= nil, "Plot_" .. k .. " has U-turn piece " .. i)
		end
		-- the belt legs: x = -14 / +14, from z = -25 to 19 (DESIGN 3), top at y = 1
		local left = plot and plot:FindFirstChild("BeltLeft")
		if left then
			local wx, wz = world(k, -14, -3)
			near(math.sqrt((left.Position.X - wx) ^ 2 + (left.Position.Z - wz) ^ 2), 0, 1e-6, "Plot_" .. k .. "'s left belt leg runs at x = -14")
			near(left.Position.Y + left.Size.Y / 2, 1, 1e-6, "...its top at y = 1")
			near(left.Size.Z, 44, 1e-6, "...44 studs long")
		end
		for t = 1, 6 do
			local console = plot and plot:FindFirstChild("Console_" .. IDS[t])
			truthy(console ~= nil, "Plot_" .. k .. " has the " .. STATION_NAMES[t] .. " console")
			local st = plot and plot:FindFirstChild("Station_" .. STATION_NAMES[t])
			truthy(st ~= nil and st.Parent == plot, "Plot_" .. k .. " has its " .. STATION_NAMES[t] .. " station model")
		end
		local board = plot and plot:FindFirstChild("Board")
		local face = board and board:FindFirstChild("BoardFace")
		truthy(face ~= nil, "Plot_" .. k .. " has its Top Recyclers board")
		if face and pad then
			local d = math.sqrt((face.Position.X - pad.Position.X) ^ 2 + (face.Position.Z - pad.Position.Z) ^ 2)
			near(d, 11.4, 0.05, "Plot_" .. k .. ": the board stands 11.4 studs from the arrival (DESIGN 3, REVIEW-2 R1)")
		end
		-- the SCRAPLINE sign's text is on the face that looks INTO the yard, not the one pressed against the wall
		-- (REVIEW-1 B4). NormalId.Front is the part's -Z (its LookVector), Back is +Z.
		local sign = plot and plot:FindFirstChild("ScraplineSign")
		local sg = sign and sign:FindFirstChild("SignText")
		truthy(sg ~= nil and sg.ClassName == "SurfaceGui", "Plot_" .. k .. "'s sign carries its SurfaceGui")
		if sg then
			local cf = sign.CFrame
			local normals = {
				[Enum.NormalId.Front] = cf.LookVector, [Enum.NormalId.Back] = -cf.LookVector,
				[Enum.NormalId.Right] = cf.RightVector, [Enum.NormalId.Left] = -cf.RightVector,
				[Enum.NormalId.Top] = cf.UpVector, [Enum.NormalId.Bottom] = -cf.UpVector,
			}
			local n = normals[sg.Face]
			local cx, cz = centre(k)
			local tx, tz = cx - sign.Position.X, cz - sign.Position.Z
			local len = math.sqrt(tx * tx + tz * tz)
			local dot = if n then (n.X * tx + n.Z * tz) / len else -2
			truthy(dot > 0.9, string.format("Plot_%d: the sign's text faces the yard (face normal . direction to the plot centre = %.3f)", k, dot))
		end
	end
	truthy(h.workspace:FindFirstChild("Baseplate") ~= nil, "the continuous ground plate exists")
	-- nothing can fall off the world (REVIEW-2 R7): behind plots 1 and 4 the 400-stud plate ended 12 studs past the
	-- plot, with no wall. Every edge of the plate must be closed by a collidable, anchored wall that spans the whole
	-- edge and stands at least 40 studs tall (a jump is 7.2, a knock lifts at most 15/s), and no plot may be crowded
	-- by it.
	local plate = h.workspace:FindFirstChild("Baseplate")
	if plate then
		local half = plate.Size.X / 2
		local groundTop = plate.Position.Y + plate.Size.Y / 2
		local closed = {}
		for _, d in h.workspace:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.Anchored and d ~= plate then
				local p, sz = d.Position, d.Size
				local top = p.Y + sz.Y / 2
				local bottom = p.Y - sz.Y / 2
				if top >= groundTop + 40 and bottom <= groundTop then
					-- a wall along X (closing the +Z or -Z edge) or along Z (closing +X or -X)
					if p.X - sz.X / 2 <= -half and p.X + sz.X / 2 >= half then
						if p.Z - sz.Z / 2 <= half and p.Z + sz.Z / 2 >= half then closed["+Z"] = true end
						if p.Z - sz.Z / 2 <= -half and p.Z + sz.Z / 2 >= -half then closed["-Z"] = true end
					end
					if p.Z - sz.Z / 2 <= -half and p.Z + sz.Z / 2 >= half then
						if p.X - sz.X / 2 <= half and p.X + sz.X / 2 >= half then closed["+X"] = true end
						if p.X - sz.X / 2 <= -half and p.X + sz.X / 2 >= -half then closed["-X"] = true end
					end
				end
			end
		end
		for _, edge in { "+X", "-X", "+Z", "-Z" } do
			truthy(closed[edge] == true, "REVIEW-2 R7: the plate's " .. edge .. " edge is closed by a collidable wall at least 40 studs tall")
		end
		-- the closest any plot's floor comes to the edge of the world
		local closest = math.huge
		for k = 1, 6 do
			for _, c in { { -32, -38 }, { 32, -38 }, { -32, 38 }, { 32, 38 } } do
				local wx, wz = world(k, c[1], c[2])
				closest = math.min(closest, half - math.abs(wx), half - math.abs(wz))
			end
		end
		print(string.format("  the closest plot corner is %.1f studs from the edge of the world", closest))
		truthy(closest >= 10, string.format("every plot keeps at least 10 studs of ground before the wall (%.1f)", closest))
	end
	local market = h.workspace:FindFirstChild("ScrapMarket")
	local mparts = 0
	if market then for _, d in market:GetDescendants() do if d:IsA("BasePart") then mparts += 1 end end end
	truthy(market ~= nil and mparts >= 5 and mparts <= 20, "the Scrap Market landmark stands at the origin (" .. mparts .. " parts, at most 20)")
end

--============================================================================ 2. budgets and the wire inventory
local function countServer()
	local parts, lights = 0, 0
	for _, d in h.workspace:GetDescendants() do
		local inChar, inLocal = false, false
		local a = d.Parent
		while a ~= nil do
			if a:FindFirstChildOfClass("Humanoid") then inChar = true break end
			if a.Name == "ScraplineLocalYard" then inLocal = true break end
			a = a.Parent
		end
		if not inChar and not inLocal then
			if d:IsA("BasePart") then parts += 1 end
			if (d.ClassName == "PointLight" or d.ClassName == "SpotLight" or d.ClassName == "SurfaceLight") and d.Enabled ~= false then lights += 1 end
		end
	end
	return parts, lights
end
local function attributeInventory()
	local found = {}
	for _, root in { h.workspace, RS } do
		for _, d in root:GetDescendants() do
			for name in d:GetAttributes() do
				table.insert(found, d:GetFullName() .. "." .. name)
			end
		end
	end
	return found
end
local function isReddish(c)
	return c.R * 255 >= 180 and c.G * 255 <= 110 and c.B * 255 <= 110
end
-- every red BasePart in the workspace except a character's and the crane telegraph of the client this check runs:
-- its ring (Workspace.ScraplineLocalYard.HazardZone, the zone) and, at the lock, its light pillar above the ring
-- (HazardPillar, red by design: DESIGN 7). REVIEW-2 X4: a crane drop telegraphed at the moment of the scan used to
-- fail "still nothing red" in about 1 run in 5. Anything else red, server or client, still fails.
local function redParts()
	local bad = {}
	for _, d in h.workspace:GetDescendants() do
		local ring = (d.Name == "HazardZone" or d.Name == "HazardPillar") and d.Parent ~= nil and d.Parent.Name == "ScraplineLocalYard"
			and d.Parent.Parent == h.workspace
		if d:IsA("BasePart") and not ring and d.Color and isReddish(d.Color) and d.Parent and not d.Parent:FindFirstChildOfClass("Humanoid") then
			table.insert(bad, d:GetFullName())
		end
	end
	return bad
end
do
	local parts, lights = countServer()
	print(string.format("  idle world: %d server parts, %d lights", parts, lights))
	truthy(parts <= 640, "the idle world is within the 640-part server budget (" .. parts .. ")")
	truthy(lights <= 12, "and the 12-light budget (" .. lights .. ")")
end
eq(#attributeInventory(), 0, "no attribute on any Instance under workspace or ReplicatedStorage (the empty wire inventory)")
eq(#redParts(), 0, "no server part is red: red is the hazard ring's alone")

--============================================================================ 3. join, LAND, and the HUD the player gets
local remotes = RS:FindFirstChild("ScraplineRemotes")
truthy(remotes ~= nil, "ReplicatedStorage.ScraplineRemotes exists")
local State, Toast, Buy, Fix, Recycle, BoardView = remotes.State, remotes.Toast, remotes.Buy, remotes.Fix, remotes.Recycle, remotes.BoardView
local function stateOf(plr)
	local sent = State:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1] or nil
end
local function toastsOf(plr)
	local out = {}
	for _, rec in Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function lastToast(plr)
	local t = toastsOf(plr)
	return t[#t] or ""
end
local function flat(p, q) return math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2) end

RunService:setIsServer(false)
local joinedAt = h.scheduler:now()
local pa = h:join("Nova", A)
local padA = pa.RespawnLocation
truthy(padA ~= nil and padA.ClassName == "SpawnLocation" and padA.Name == "Arrival",
	"PlayerAdded points RespawnLocation at the player's own arrival pad synchronously, before any yield")
local plotA = padA and padA.Parent
local kA = tonumber(string.match(plotA.Name, "%d+"))
local ca = h.Players:simulateSpawn(pa, h.workspace)
h:advance(0.2)
local hrpA = ca:FindFirstChild("HumanoidRootPart")
local humA = ca:FindFirstChildOfClass("Humanoid")
humA.FloorMaterial = Enum.Material.Concrete
humA.MoveDirection = Vector3.new(0.01, 0, 1) -- steering input: this player never idles into a rest here
truthy(flat(hrpA.Position, padA.Position) <= 4, string.format("the joining character LANDS on its own pad (%.2f studs)", flat(hrpA.Position, padA.Position)))
truthy(hrpA.Position.Y > TOP, "above the pad, not in it")
local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okYard, errYard = h:tryRun("client/Yard.client")
truthy(okYard, "Yard.client loads (" .. tostring(errYard) .. ")")
local function frames(seconds)
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
	end
end
frames(0.6)
local hud = pa.PlayerGui:FindFirstChild("ScraplineHud").Root
local hint = hud.HintPanel
truthy(hint.Visible and string.find(hint.HintText.Text, "Shredder", 1, true) ~= nil, "the first hint names the core action: " .. hint.HintText.Text)
eq(hud.LineSlot.LineButton.Text, "🔧 Build Shredder", "slot 1 is the one-tap Build button")

-- every prompt is created by the owner's client on its own plot, and every one is reachable from the floor
do
	local consolePrompts = 0
	for t = 1, 6 do
		local console = plotA:FindFirstChild("Console_" .. IDS[t])
		local prompt = console and console:FindFirstChildOfClass("ProximityPrompt")
		truthy(prompt ~= nil and prompt.Enabled ~= false, "the " .. STATION_NAMES[t] .. " console carries a prompt")
		if prompt and console then
			consolePrompts += 1
			-- stand on the open floor inside the U, 3 studs further in than the console
			local lx = if t <= 3 then -6 else 6
			local lz = ({ -16, -2, 12, 12, -2, -16 })[t]
			local sx, sz = world(kA, lx, lz)
			local stand = Vector3.new(sx, FLOOR + 3, sz)
			truthy((stand - console.Position).Magnitude <= prompt.MaxActivationDistance,
				string.format("...reachable from the floor beside it (%.1f <= %d)", (stand - console.Position).Magnitude, prompt.MaxActivationDistance))
		end
	end
	eq(consolePrompts, 6, "six station prompts")
	local face = plotA.Board.BoardFace
	local bp = face:FindFirstChildOfClass("ProximityPrompt")
	truthy(bp ~= nil, "the owner's board carries the Public / Friends prompt")
	if bp then
		local stand = Vector3.new(padA.Position.X, TOP + 3, padA.Position.Z)
		truthy((stand - face.Position).Magnitude <= bp.MaxActivationDistance,
			string.format("...reachable from the arrival pad itself (%.1f <= %d)", (stand - face.Position).Magnitude, bp.MaxActivationDistance))
	end
	-- nobody else's plot has prompts (the HUD runs for Nova only; the server creates none)
	local foreign = 0
	for _, d in plots:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d:IsDescendantOf(plotA) then foreign += 1 end
	end
	eq(foreign, 0, "no prompt exists on any other plot")
end

--============================================================================ 4. the core loop
local stA = stateOf(pa)
truthy(stA and stA.loaded, "the owner receives a loaded State")
do
	-- the State carries only the PRESENT: no field anywhere in it names the time or target of the next sputter
	local leaks = {}
	local function scan(v, path)
		if type(v) ~= "table" then return end
		for k2, x in v do
			local name = string.lower(tostring(k2))
			if string.find(name, "jamin", 1, true) or string.find(name, "next", 1, true) or string.find(name, "seed", 1, true) then
				table.insert(leaks, path .. "." .. tostring(k2))
			end
			scan(x, path .. "." .. tostring(k2))
		end
	end
	for _, rec in State:sentTo(pa) do scan(rec.args[1], "State") end
	eq(#leaks, 0, "no State payload carries the jam clock or anything about the next sputter (" .. table.concat(leaks, ", ") .. ")")
end
near(stA and stA.income or -1, 0.5, 1e-9, "before the Shredder, the chute trickles: $0.5/s")
local cash0 = stA.cash
frames(4)
near(stateOf(pa).cash - cash0, 2, 0.3, "and the dock sells it: about $2 in 4 s")
-- THE CORE ACTION: one tap on the HUD's own button
hud.LineSlot.LineButton.Activated:Fire()
frames(0.6)
local shredderAt = h.scheduler:now()
local s1 = stateOf(pa)
eq(s1.stations[1].n, 1, "one tap builds the free Shredder")
print(string.format("  the core action (the free Shredder) happened %.1f s after the join", shredderAt - joinedAt))
truthy(shredderAt - joinedAt <= 8, "the core action is reachable within seconds of joining")
local mA = plotA.Station_Shredder:FindFirstChild("Machine_Shredder_a")
truthy(mA ~= nil and mA.Parent ~= nil, "the Shredder's machine model is built and parented on Nova's plot")
if mA then
	local bx, bz = world(kA, -14, -19.5)
	near(flat(mA.Body.Position, Vector3.new(bx, 0, bz)), 0, 1e-6, "...on the belt at plot-local (-14, -19.5), 3.5 studs upstream of its station")
	eq(mA.Body.LevelPlate.LevelText.Text, "Lv 1", "...wearing its level plate")
end
near(s1.income, 2, 1e-9, "junk becomes scrap: $2/s")
do
	-- a purchase Nova cannot afford yet is refused, and the toast says by how much
	local n0 = #toastsOf(pa)
	Buy:simulateFireServer(pa, "build", "furnace")
	h:advance(0.1)
	truthy(#toastsOf(pa) > n0 and string.find(lastToast(pa), "Need 650, you have", 1, true) ~= nil,
		"an unaffordable Furnace is refused with both numbers: " .. lastToast(pa))
	eq(stateOf(pa).stations[2].n, 0, "...and nothing was built")
end
eq(s1.tutorial, 1, "the hint moves on (tutorial 0 -> 1)")
frames(5)
truthy(string.find(pa.leaderstats.Cash.Value, "$", 1, true) ~= nil, "leaderstats shows the cash: " .. pa.leaderstats.Cash.Value)

-- play like the ★ says, through the Buy remote, until the line has a Furnace and a twin
local bought = { build = 0, twin = 0, up = 0 }
local function play(seconds, untilFn)
	local tEnd = h.scheduler:now() + seconds
	local lastShop = -math.huge
	while h.scheduler:now() < tEnd do
		local st = stateOf(pa)
		if st and st.star and h.scheduler:now() - lastShop >= 5 then
			lastShop = h.scheduler:now()
			for _ = 1, 20 do
				st = stateOf(pa)
				if st.star == nil or st.cash < st.star.price then break end
				Buy:simulateFireServer(pa, st.star.kind, st.star.id)
				bought[st.star.kind] += 1
				h:advance(0.05)
			end
		end
		frames(0.5)
		if untilFn and untilFn() then return true end
	end
	return false
end
play(240, function()
	local st = stateOf(pa)
	return st.stations[2].n >= 1 and (st.stations[1].n == 2 or st.stations[2].n == 2)
end)
local s2 = stateOf(pa)
truthy(s2.stations[2].n >= 1, "following the ★ builds the Furnace")
truthy(s2.stations[1].n == 2 or s2.stations[2].n == 2, "and a twin")
truthy(plotA.Station_Furnace:FindFirstChild("Machine_Furnace_a") ~= nil, "the Furnace's machine model stands on the belt")
local twinModel = plotA.Station_Shredder:FindFirstChild("Machine_Shredder_b") or plotA.Station_Furnace:FindFirstChild("Machine_Furnace_b")
truthy(twinModel ~= nil, "the twin's machine model stands beside it")
truthy(s2.stations[1].L > 1, "the Shredder was upgraded (Lv " .. s2.stations[1].L .. ")")
local plate = plotA.Station_Shredder.Machine_Shredder_a.Body.LevelPlate.LevelText.Text
eq(plate, "Lv " .. s2.stations[1].L, "its level plate shows it")
print(string.format("  by %.0f s: %d upgrades, %d builds, %d twins; income $%.1f/s", h.scheduler:now() - shredderAt, bought.up, bought.build, bought.twin, s2.income))
frames(5)
local s3 = stateOf(pa)
eq(s3.tier, 2, "the first Ingot ships: tier 2 (the Foundry)")
do
	local sign = plotA.ScraplineSign
	local c = sign.Color
	eq(string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)), "255,150,50",
		"the SCRAPLINE sign wears the Foundry's accent, where everyone can see it")
	local chip = pa.PlayerGui.ScraplineYard.Root.BandChip.ChipText.Text
	truthy(string.find(chip, "Foundry", 1, true) ~= nil, "the band chip says Foundry: " .. chip)
end

--============================================================================ 5. the board renders on the owner's own board
do
	frames(31) -- the board's first send went out at load, before this HUD listened; it re-sends every 30 s
	local sg = pa.PlayerGui:FindFirstChild("BoardGuis") and pa.PlayerGui.BoardGuis:FindFirstChild("TopRecyclers")
	truthy(sg ~= nil, "the Top Recyclers SurfaceGui lives in the owner's PlayerGui (BoardGuis)")
	eq(sg and sg.Adornee, plotA.Board.BoardFace, "...adorned to their OWN board face")
	local rows = {}
	if sg then
		for i = 1, 10 do
			local r = sg.Background.Rows:FindFirstChild("Row_" .. i)
			if r then table.insert(rows, r.Text) end
		end
	end
	print("  public rows: " .. table.concat(rows, " | "))
	truthy(#rows >= 2 and string.find(rows[1], "3", 1, true) ~= nil, "the board renders the public rows, best first")
	local inWorld = 0
	for _, d in h.workspace:GetDescendants() do if d.Name == "TopRecyclers" then inWorld += 1 end end
	eq(inWorld, 0, "and nothing named TopRecyclers is in the workspace: other players cannot see the rows")
end

--============================================================================ 6. jams: the first sputter, walking there, the fix
local sputterAt, sp = nil, nil
local fixedAt = nil -- when the first sputter was saved: the jam clock is stopped while a sputter is live
local tWait = h.scheduler:now()
while h.scheduler:now() - tWait < 300 do
	play(1)
	local st = stateOf(pa)
	if st.sputter then
		sp = st.sputter
		sputterAt = h.scheduler:now()
		break
	end
end
truthy(sp ~= nil, "a machine starts to sputter")
if sp then
	print(string.format("  the first sputter came %.1f s after the Shredder was built (DESIGN: 240 s of line time)", sputterAt - shredderAt))
	near(sputterAt - shredderAt, 240, 1.2, "240 s of line time after the first machine was built")
	local body = (plotA:FindFirstChild("Station_" .. STATION_NAMES[sp.t]) :: any)["Machine_" .. STATION_NAMES[sp.t] .. "_" .. (if sp.m == 1 then "a" else "b")].Body
	eq(body.Sparks.Enabled, true, "it throws sparks")
	truthy(hud.AlertPanel.Visible and string.find(hud.AlertPanel.AlertText.Text, "sputtering", 1, true) ~= nil,
		"the HUD's alert line says so: " .. hud.AlertPanel.AlertText.Text)
	local fixPrompt = body:FindFirstChildOfClass("ProximityPrompt")
	truthy(fixPrompt ~= nil and fixPrompt.ActionText == "Fix", "the owner's client puts a Fix prompt on that machine")
	near(fixPrompt and fixPrompt.HoldDuration or -1, 0.5, 1e-9, "...a 0.5 s hold, not a brush-past")
	-- a Fix fired from the arrival pad is refused: Fix reads the TRUSTED position
	hrpA.CFrame = CFrame.new(padA.Position + Vector3.new(0, 3, 0))
	frames(0.5)
	local n0 = #toastsOf(pa)
	Fix:simulateFireServer(pa, IDS[sp.t], if sp.m == 1 then "a" else "b")
	h:advance(0.1)
	truthy(#toastsOf(pa) > n0 and string.find(lastToast(pa), "Get closer", 1, true) ~= nil, "a Fix from the arrival pad is refused with a toast: " .. lastToast(pa))
	do
		-- a TELEPORT buys nothing: drain the trusted position's banked burst by teleporting back and forth by the pad,
		-- then put the root right beside the sputtering machine and fire Fix at once. The claim is in reach; the
		-- trusted position (moving at 21.6 studs/s) is not, so the Fix is refused.
		local p1 = Vector3.new(padA.Position.X, TOP + 3, padA.Position.Z)
		local rx, rz = world(kA, 20, -30)
		local p2 = Vector3.new(rx, TOP + 3, rz)
		for i = 1, 30 do
			hrpA.CFrame = CFrame.new(if i % 2 == 0 then p1 else p2)
			h:advance(0.1)
		end
		local mz0 = ({ -16, -2, 12, 12, -2, -16 })[sp.t] + (if sp.t <= 3 then (if sp.m == 1 then -3.5 else 3.5) else (if sp.m == 1 then 3.5 else -3.5))
		local tx, tz = world(kA, if sp.t <= 3 then -9.5 else 9.5, mz0)
		hrpA.CFrame = CFrame.new(tx, FLOOR + 3, tz)
		h:advance(0.1)
		local n1 = #toastsOf(pa)
		Fix:simulateFireServer(pa, IDS[sp.t], if sp.m == 1 then "a" else "b")
		h:advance(0.05)
		truthy(#toastsOf(pa) > n1 and string.find(lastToast(pa), "Get closer", 1, true) ~= nil,
			"a teleport beside the machine does not fix it: Fix reads the TRUSTED position (" .. lastToast(pa) .. ")")
		eq(stateOf(pa).sputter ~= nil, true, "...the machine is still sputtering")
		hrpA.CFrame = CFrame.new(p1)
		frames(0.3)
	end
	-- walk there at WalkSpeed, the way a player would: to the open floor beside the machine, inside the U
	local mz = ({ -16, -2, 12, 12, -2, -16 })[sp.t] + (if sp.t <= 3 then (if sp.m == 1 then -3.5 else 3.5) else (if sp.m == 1 then 3.5 else -3.5))
	local gx, gz = world(kA, if sp.t <= 3 then -9.5 else 9.5, mz)
	local goal = Vector3.new(gx, FLOOR + 3, gz)
	local walked = 0
	for _ = 1, 400 do
		local p = hrpA.Position
		local d = flat(p, goal)
		if d < 0.5 then break end
		local step = math.min(d, 16 * 0.1)
		hrpA.CFrame = CFrame.new(p.X + (goal.X - p.X) / d * step, FLOOR + 3, p.Z + (goal.Z - p.Z) / d * step)
		walked += step
		frames(0.1)
	end
	truthy((hrpA.Position - body.Position).Magnitude <= fixPrompt.MaxActivationDistance,
		string.format("standing beside it, the Fix prompt is in reach (%.1f <= %d)", (hrpA.Position - body.Position).Magnitude, fixPrompt.MaxActivationDistance))
	local took = h.scheduler:now() - sputterAt
	print(string.format("  walked %.1f studs to the sputtering %s in %.1f s of its 15", walked, STATION_NAMES[sp.t], took))
	fixPrompt.Triggered:Fire(pa)
	fixedAt = h.scheduler:now()
	h:advance(0.2)
	truthy(string.find(lastToast(pa), "Saved it", 1, true) ~= nil, "holding Fix in time saves it: " .. lastToast(pa))
	frames(0.5)
	eq(body.Sparks.Enabled, false, "the sparks stop")
	eq(stateOf(pa).sputter, nil, "no sputter is live")
	eq(stateOf(pa).tutorial, 4, "the tutorial ends after the first fix")
	eq(body:FindFirstChildOfClass("ProximityPrompt"), nil, "the Fix prompt is gone again")
end

-- a second sputter, left alone, becomes a jam after exactly 15 s, and items ride past it
do
	local sp2, at2 = nil, nil
	local t0 = h.scheduler:now()
	while h.scheduler:now() - t0 < 260 do
		frames(0.5)
		local st = stateOf(pa)
		if st.sputter then sp2 = st.sputter; at2 = h.scheduler:now(); break end
	end
	-- REVIEW-2 X4: the gap is line time with no sputter live, so it is measured from the FIX of the first one (from
	-- its start it also held the 5-12 s the first one was live, and a draw near 210 s went over the bound)
	print(string.format("  the second sputter came %.1f s after the first was saved (%.1f s after the first began)", (at2 or 0) - (fixedAt or 0), (at2 or 0) - (sputterAt or 0)))
	truthy(sp2 ~= nil, "a second sputter comes " .. string.format("%.1f s", (at2 or 0) - (fixedAt or 0)) .. " after the first was saved (150-210 s of line time)")
	truthy(at2 ~= nil and fixedAt ~= nil and at2 - fixedAt >= 149 and at2 - fixedAt <= 212,
		string.format("inside the 150-210 s gap (%.1f s after the fix, %.1f s after the first sputter began)", (at2 or 0) - (fixedAt or 0), (at2 or 0) - (sputterAt or 0)))
	if sp2 then
		local incomeBefore = stateOf(pa).income
		local jammedAt = nil
		local t1 = h.scheduler:now()
		while h.scheduler:now() - t1 < 20 do
			frames(0.1)
			local st = stateOf(pa)
			if st.sputter == nil and (st.jammed[sp2.t] or 0) > 0 then jammedAt = h.scheduler:now(); break end
		end
		truthy(jammedAt ~= nil, "left alone, the sputtering machine jams")
		near((jammedAt or 0) - at2, 15, 0.6, "after 15 s")
		local body = (plotA:FindFirstChild("Station_" .. STATION_NAMES[sp2.t]) :: any)["Machine_" .. STATION_NAMES[sp2.t] .. "_" .. (if sp2.m == 1 then "a" else "b")].Body
		eq(body.JamSign.Enabled, true, "it wears the ⚠ JAMMED sign")
		eq(body.Smoke.Enabled, true, "and smokes")
		local incomeJammed = stateOf(pa).income
		print(string.format("  a jammed %s: income $%.1f/s -> $%.1f/s", STATION_NAMES[sp2.t], incomeBefore, incomeJammed))
		truthy(incomeJammed < incomeBefore, "items ride past it unchanged: the line earns less")
		-- fix it (walk there first)
		local mz = ({ -16, -2, 12, 12, -2, -16 })[sp2.t] + (if sp2.t <= 3 then (if sp2.m == 1 then -3.5 else 3.5) else (if sp2.m == 1 then 3.5 else -3.5))
		local gx, gz = world(kA, if sp2.t <= 3 then -9.5 else 9.5, mz)
		for _ = 1, 400 do
			local p = hrpA.Position
			local d = flat(p, Vector3.new(gx, 0, gz))
			if d < 0.5 then break end
			local step = math.min(d, 1.6)
			hrpA.CFrame = CFrame.new(p.X + (gx - p.X) / d * step, FLOOR + 3, p.Z + (gz - p.Z) / d * step)
			frames(0.1)
		end
		local prompt = body:FindFirstChildOfClass("ProximityPrompt")
		truthy(prompt ~= nil, "a jammed machine carries the Fix prompt too")
		if prompt then prompt.Triggered:Fire(pa) end
		h:advance(0.2)
		truthy(string.find(lastToast(pa), "Fixed", 1, true) ~= nil, "fixing a jam: " .. lastToast(pa))
		frames(1)
		truthy(stateOf(pa).income >= incomeJammed, "and the line earns again")
	end
end

--============================================================================ 7. refusals always speak
do
	local function refused(fire, needle, msg)
		local n0 = #toastsOf(pa)
		fire()
		h:advance(0.1)
		truthy(#toastsOf(pa) > n0 and string.find(lastToast(pa), needle, 1, true) ~= nil, msg .. ": " .. lastToast(pa))
		h:advance(0.15) -- stay under the 8/s limit
	end
	refused(function() Buy:simulateFireServer(pa, "teleporter", "shredder") end, "isn't a machine", "an unknown kind is refused with a toast")
	refused(function() Buy:simulateFireServer(pa, "up", "spaceship") end, "isn't a machine", "an unknown station")
	-- the first unbuilt station u: building the one after it is out of order; u itself costs more than Nova has
	local st = stateOf(pa)
	local u = nil
	for t = 1, 6 do if st.stations[t].n == 0 then u = t break end end
	truthy(u ~= nil and u < 6, "set-up: the line is still being built (first unbuilt: " .. tostring(u) .. ")")
	if u and u < 6 then
		refused(function() Buy:simulateFireServer(pa, "build", IDS[u + 1]) end, "Build a " .. ({ "Shredder", "Furnace", "Press", "Cutter", "Assembler" })[u] .. " first",
			"a station out of order")
	end
	refused(function() Buy:simulateFireServer(pa, "build", "furnace") end, "already built", "a station built twice")
	if st.stations[1].n == 2 then
		refused(function() Buy:simulateFireServer(pa, "twin", "shredder") end, "already has its twin", "a third machine")
	end
	refused(function() Fix:simulateFireServer(pa, "shredder", "a") end, "running fine", "fixing a machine that runs fine")
	refused(function() Fix:simulateFireServer(pa, "rocketbay", "a") end, "isn't a machine", "fixing a machine that does not exist")
	refused(function() Fix:simulateFireServer(pa, "shredder", "c") end, "isn't a machine", "a machine that is neither a nor b")
	refused(function() Recycle:simulateFireServer(pa) end, "rockets a second", "a recycle without the rocket rate")
	refused(function() BoardView:simulateFireServer(pa, "everyone!") end, "board view", "a board view that does not exist")
	-- a flood is cut at 8/s
	h:advance(1.1)
	local n2 = #toastsOf(pa)
	for _ = 1, 30 do Buy:simulateFireServer(pa, "build", "furnace") end
	h:advance(0.1)
	local slow = 0
	for _, t in toastsOf(pa) do if string.find(t, "Slow down", 1, true) then slow += 1 end end
	truthy(slow >= 1, "a flood of 30 Buy calls in one frame is cut at 8/s, with a 'Slow down' toast")
	truthy(#toastsOf(pa) - n2 <= 9, string.format("and the flood gets at most 8 refusals + 1 slow-down toast (%d)", #toastsOf(pa) - n2))
end

--============================================================================ 8. a second player: their own pad, their own plot
local pb = h:join("Orion", B)
local padB = pb.RespawnLocation
local cb = h.Players:simulateSpawn(pb, h.workspace)
h:advance(0.3)
truthy(padB ~= nil and padB ~= padA, "a second player gets a different plot")
truthy(flat(cb.HumanoidRootPart.Position, padB.Position) <= 4, "the second character lands on ITS OWN pad")
truthy(flat(cb.HumanoidRootPart.Position, padA.Position) > 20, "and not on the first player's")
do
	local c2 = h.Players:simulateSpawn(pb, h.workspace)
	h:advance(0.3)
	truthy(flat(c2.HumanoidRootPart.Position, padB.Position) <= 4, "a respawn lands on the player's own pad again")
	pb.RespawnLocation = nil
	local c3 = h.Players:simulateSpawn(pb, h.workspace)
	h:advance(0.5)
	local p = c3.HumanoidRootPart.Position
	truthy(flat(p, padB.Position) <= 4, string.format("with RespawnLocation cleared, the handler still moves the character to its own pad (%.1f studs)", flat(p, padB.Position)))
	cb = c3
end
do
	-- Orion stands beside Nova's Shredder and fires Fix: it can only ever act on Orion's own (unbuilt) station
	local gx, gz = world(kA, -9.5, -19.5)
	cb.HumanoidRootPart.CFrame = CFrame.new(gx, FLOOR + 3, gz)
	h:advance(4)
	local n0 = #toastsOf(pb)
	Fix:simulateFireServer(pb, "shredder", "a")
	h:advance(0.1)
	truthy(#toastsOf(pb) > n0 and string.find(lastToast(pb), "isn't a machine", 1, true) ~= nil,
		"a visitor's Fix acts on their OWN plot, never on someone else's: " .. lastToast(pb))
	cb.HumanoidRootPart.CFrame = CFrame.new(padB.Position + Vector3.new(0, 3, 0))
end

--============================================================================ 9. budgets with six plots, four of them full lines
local fillers = {}
for i, uid in { FULL1, FULL2, FULL3, FULL4 } do
	local p = h:join("Full" .. i, uid)
	h.Players:simulateSpawn(p, h.workspace)
	table.insert(fillers, p)
end
h:advance(2)
do
	local st = stateOf(fillers[1])
	eq(st and st.stations[6].n, 2, "set-up: a returning player's complete line loads (every station twinned)")
	local parts, lights = countServer()
	print(string.format("  busy world (6 players, 4 complete lines): %d server parts, %d lights", parts, lights))
	truthy(parts <= 640, "still within the 640-part budget (" .. parts .. ")")
	truthy(lights <= 12, "and 12 lights (" .. lights .. ")")
	eq(#attributeInventory(), 0, "and still no attributes under workspace or ReplicatedStorage")
	eq(#redParts(), 0, "and still nothing red")
	local info = SS:FindFirstChild("PlotInfo") and SS.PlotInfo:FindFirstChild(tostring(A))
	truthy(info ~= nil and type(info:GetAttribute("JamIn")) == "number", "the jam clock is written down only in ServerStorage.PlotInfo (never replicated)")
	-- the grade paint: two bolts paint a factory Steel, and everyone sees it
	local wall = fillers[1].RespawnLocation.Parent.FactoryWall
	local c = wall.Color
	eq(string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)), "170,180,190",
		"a factory with 2 Gold Bolts is painted Steel")
end

--============================================================================ 10. six plots, and a seventh player
do
	local seventh = h:join("Seventh", 9999)
	h:advance(0.2)
	truthy(rawget(seventh, "__kicked") ~= nil, "a seventh player is kicked with a reason, never left without a plot")
	eq(seventh.RespawnLocation, nil, "and was never given a pad")
	truthy(string.find(tostring(rawget(seventh, "__kicked")), "6 factories", 1, true) ~= nil, "the reason says why: " .. tostring(rawget(seventh, "__kicked")))
	h:leave(fillers[4])
	h:advance(0.5)
	local next = h:join("Next", 10000)
	h:advance(0.3)
	truthy(next.RespawnLocation ~= nil and rawget(next, "__kicked") == nil, "the plot a leaver freed goes to the next joiner")
	eq(#next.RespawnLocation.Parent.Station_Shredder:GetChildren(), 0, "...and it is a bare yard again (the leaver's machines are gone)")
	h:leave(next)
	h:advance(0.5)
end

--============================================================================ 11. a rejoin restores every saved field; a sputter at leave comes back as a jam
do
	-- wait for Nova's next sputter and leave while it is live
	local live = nil
	local t0 = h.scheduler:now()
	while h.scheduler:now() - t0 < 260 do
		h:advance(0.5)
		local st = stateOf(pa)
		if st.sputter then live = st.sputter break end
	end
	truthy(live ~= nil, "set-up: a sputter is live")
	local st = stateOf(pa)
	local jamInBefore = SS.PlotInfo[tostring(A)]:GetAttribute("JamIn")
	h:leave(pa)
	h:advance(1)
	local saved = store:GetAsync("u_" .. A)
	truthy(saved and saved.data and saved.lockUntil == 0, "leaving writes the profile and RELEASES the lock")
	local sid = IDS[live.t]
	eq(saved.data.stations[sid].j, 1, "the sputter live at leave is saved as a jam")
	local pa2 = h:join("Nova", A)
	h.Players:simulateSpawn(pa2, h.workspace)
	h:advance(0.6)
	local st2 = stateOf(pa2)
	truthy(st2 and st2.loaded, "the rejoin loads")
	for t = 1, 6 do
		eq(st2.stations[t].n, st.stations[t].n, "rejoin restores " .. IDS[t] .. "'s machines")
		eq(st2.stations[t].L, st.stations[t].L, "rejoin restores " .. IDS[t] .. "'s level")
	end
	eq(st2.tier, st.tier, "rejoin restores the tier (no lift-off or title card replays)")
	eq(st2.bolts, st.bolts, "rejoin restores the bolts")
	eq(st2.tutorial, st.tutorial, "rejoin restores the tutorial step (resumes, never repeats)")
	truthy(st2.cash >= st.cash - 1e-6 and st2.cash - st.cash <= math.max(5, st.cash * 0.02),
		string.format("rejoin restores the cash (%.1f vs %.1f)", st2.cash, st.cash))
	eq(st2.jammed[live.t], 1, "and the machine that was sputtering comes back JAMMED: a rejoin never clears a jam")
	eq(st2.sputter, nil, "(as a jam, not a fresh sputter)")
	local jamInAfter = SS.PlotInfo[tostring(A)]:GetAttribute("JamIn")
	truthy(math.abs(jamInAfter - jamInBefore) <= 1.5, string.format("the jam clock carries on from where it was (%.1f -> %.1f)", jamInBefore, jamInAfter))
	eq(plotA.Station_Shredder:FindFirstChild("Machine_Shredder_a") ~= nil or pa2.RespawnLocation.Parent.Station_Shredder:FindFirstChild("Machine_Shredder_a") ~= nil,
		true, "the rebuilt plot stands again")
end

print("")
local stray = {}
for _, w in h.warnings do
	if not string.find(w, "a seventh player arrived", 1, true) then table.insert(stray, w) end
end
eq(#stray, 0, "the server warned about nothing else (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("scraplinetycoon: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon check failed", 0) end
