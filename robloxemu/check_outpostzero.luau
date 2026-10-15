-- Outpost Zero: Sky City Tycoon — THE REAL PLAYER PATH, through the real server, headless.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero.luau 2>&1
-- ALWAYS rebuild the bundle first: this file reads build/outpost-zero.luau, not src/.
--
-- Why this exists: this repo once shipped 166 green unit tests with an unreachable core loop. Nothing here trusts a
-- unit test. It asks the workspace, spawns characters the way the ENGINE does (robloxemu/SPAWN-ORDER.md), walks a
-- character to the ★ lot's sign post at WalkSpeed, presses the post's ProximityPrompt only from within its reach,
-- and reads back only what a client could see (the workspace, the State / Toast remotes, leaderstats) plus the
-- ServerStorage.CityInfo debug folder. Positions are written out by hand from DESIGN.md (ring 220, pad at
-- shelf-local (0, -16), board 10 studs from it), never recomputed with the game's modules.

local Harness = require("./emu/harness")

local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

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

local A, B, BIG, AWAY = 5150, 6161, 7272, 7373
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
-- a returning player with every lot of every district at 22 storeys: the full city (the part budget's worst case)
do
	local lots = {}
	for d = 1, 6 do for i = 1, 6 do lots[d .. "_" .. i] = 22 end end
	store:SetAsync("u_" .. BIG, { data = { v = 1, seed = 99, credits = 5e6, lifetime = 9e9, lots = lots, savedAt = os.time(),
		ordersUntil = os.time() + 300, popAt = 1790000000, airshipSeen = true, tutorial = 3 } })
end

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server script loads (" .. tostring(errServer) .. ")")
if not okServer then
	print(string.format("outpostzero: %d passed, %d failed", passed, failed))
	error("outpostzero check failed", 0)
end
h:advance(1)

local RS = h.ReplicatedStorage
local SS = h.game:GetService("ServerStorage")
local RING, PAD_R, TOP = 220, 204, 1 -- shelf ring; the pad is 16 studs in from a shelf's centre; its top face

local function flat(p, q) return math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2) end
-- Sizes Roblox draws as written (round 2, finding B1): a Ball is forced uniform, a Cylinder round (Y = Z), and every
-- axis is clamped to 2048 studs. robloxemu keeps any size, so this is asserted on every part shown
-- (anomaly-observatory EYECANDY "Sizes the engine draws as written"). Returns nil, or why not.
local function engineDraws(d)
	local s = d.Size
	local shape = if d.ClassName == "Part" then d.Shape else nil
	if shape == Enum.PartType.Ball and (math.abs(s.X - s.Y) > 1e-6 or math.abs(s.Y - s.Z) > 1e-6) then return "a non-uniform Ball" end
	if shape == Enum.PartType.Cylinder and math.abs(s.Y - s.Z) > 1e-6 then return "an oval Cylinder" end
	if s.X > 2048 or s.Y > 2048 or s.Z > 2048 then return "an axis over 2048" end
	return nil
end
local engineBad, engineBadN = {}, 0
local function engineScan(root, where)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local why = engineDraws(d)
			if why and engineBad[d.Name] == nil then
				engineBad[d.Name] = string.format("%s is %s (%.1f x %.1f x %.1f, %s)", d.Name, why, d.Size.X, d.Size.Y, d.Size.Z, where)
				engineBadN += 1
			end
		end
	end
end
local function engineReport()
	local list = {}
	for _, v in engineBad do table.insert(list, v) end
	table.sort(list)
	return list
end

local function centreOf(k)
	local a = math.rad((k - 1) * 60)
	return Vector3.new(math.sin(a) * RING, 0, math.cos(a) * RING)
end

--============================================================================ 1. the world is BUILT and PARENTED
local shelves = h.workspace:FindFirstChild("Shelves")
truthy(shelves ~= nil and shelves.Parent == h.workspace, "workspace.Shelves exists and is parented")
local function shelfModel(k) return shelves and shelves:FindFirstChild("Shelf_" .. k) end
do
	local spawns = 0
	for _, d in h.workspace:GetDescendants() do
		if d.ClassName == "SpawnLocation" then spawns += 1 end
	end
	eq(spawns, 6, "exactly 6 SpawnLocations in the world: one per shelf, none anywhere else")
	for k = 1, 6 do
		local shelf = shelfModel(k)
		truthy(shelf ~= nil and shelf.Parent == shelves, "Shelf_" .. k .. " is built and parented")
		local pad = shelf and shelf:FindFirstChild("Arrival")
		truthy(pad ~= nil and pad.ClassName == "SpawnLocation", "Shelf_" .. k .. " has its Arrival SpawnLocation")
		if pad then
			eq(pad.Enabled, true, "Shelf_" .. k .. "'s arrival is enabled")
			eq(pad.Duration, 0, "...with no force-field bubble")
			eq(pad.Anchored, true, "...anchored")
			near(pad.Position.Y + pad.Size.Y / 2, TOP, 1e-6, "...with its top at y = 1")
			near(math.sqrt(pad.Position.X ^ 2 + pad.Position.Z ^ 2), PAD_R, 1e-6, "...16 studs in from the shelf's centre, toward the ring's centre")
			near(flat(pad.Position, centreOf(k)), 16, 1e-6, "...16 studs from Shelf_" .. k .. "'s centre")
		end
		local rock = shelf and shelf:FindFirstChild("Rock")
		truthy(rock ~= nil and rock.CanCollide, "Shelf_" .. k .. " stands on collidable rock")
		local hall = shelf and shelf:FindFirstChild("TownHall")
		truthy(hall ~= nil and hall:FindFirstChild("HallBody") ~= nil, "Shelf_" .. k .. " has its Town Hall")
		local parapet = shelf and shelf:FindFirstChild("Parapet")
		local glass, wall = 0, 0
		if parapet then
			for _, c in parapet:GetChildren() do
				if string.sub(c.Name, 1, 5) == "Glass" and c.CanCollide and c.Size.Y >= 12 then glass += 1 end
				if string.sub(c.Name, 1, 4) == "Wall" then wall += 1 end
			end
		end
		eq(glass, 16, "Shelf_" .. k .. ": 16 collidable glass panes, 12 studs tall")
		eq(wall, 16, "Shelf_" .. k .. ": 16 wall segments")
		local board = shelf and shelf:FindFirstChild("Board")
		local face = board and board:FindFirstChild("BoardFace")
		local prompt = face and face:FindFirstChildOfClass("ProximityPrompt")
		truthy(prompt ~= nil and prompt.Enabled, "Shelf_" .. k .. "'s Census board has an enabled ProximityPrompt")
		if prompt and face and pad then
			near(flat(face.Position, pad.Position), 10, 0.6, "Shelf_" .. k .. ": the board stands 10 studs from the pad (DESIGN 9.4)")
			-- reachable from anywhere on the pad: its far corners are 13.3 from the board
			local far = 0
			for _, c in { { -3, -3 }, { 3, -3 }, { 3, 3 }, { -3, 3 } } do
				-- the pad's own corners (the shelves are turned to face the ring's centre)
				local corner = (pad.CFrame * CFrame.new(c[1], 0, c[2])).Position
				local p = Vector3.new(corner.X, 3.5, corner.Z)
				far = math.max(far, (p - face.Position).Magnitude)
			end
			truthy(far <= prompt.MaxActivationDistance, string.format("Shelf_%d: the board's prompt reaches every corner of the pad (%.1f <= %d)", k, far, prompt.MaxActivationDistance))
		end
		local lots = shelf and shelf:FindFirstChild("Lots")
		truthy(lots ~= nil and #lots:GetChildren() == 0, "Shelf_" .. k .. " shows the Town Hall alone until an owner's city loads")
	end
	-- no shelf can be reached from another: the rims are 60 studs apart
	local c1, c2 = centreOf(1), centreOf(2)
	near((c1 - c2).Magnitude - 160, 60, 1e-6, "neighbouring rims are 60 studs apart, beyond any jump")
end

--============================================================================ 2. budgets and the wire inventory
local function countServer()
	local parts, lights = 0, 0
	for _, d in h.workspace:GetDescendants() do
		local inChar = false
		local a = d.Parent
		while a ~= nil do
			if a:FindFirstChildOfClass("Humanoid") then inChar = true break end
			a = a.Parent
		end
		if not inChar then
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
				table.insert(found, d.Name .. "." .. name)
			end
		end
	end
	return found
end
local function isReddish(c)
	return c.R * 255 >= 180 and c.G * 255 <= 110 and c.B * 255 <= 110
end
local function redParts()
	local bad = {}
	for _, d in h.workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Color and isReddish(d.Color) and d.Parent and not d.Parent:FindFirstChildOfClass("Humanoid") then
			table.insert(bad, d:GetFullName())
		end
	end
	return bad
end
do
	local parts, lights = countServer()
	print(string.format("  idle world: %d server parts, %d lights", parts, lights))
	truthy(parts <= 1500, "the idle world is within the 1 500-part server budget (" .. parts .. ")")
	truthy(lights <= 12, "and the 12-light budget (" .. lights .. ")")
end
eq(#attributeInventory(), 0, "no attribute on any Instance under workspace or ReplicatedStorage (the empty wire inventory)")
eq(#redParts(), 0, "no server part is red: red is the hazard ring's alone")
do
	-- there is no client -> server remote at all: every action is a ProximityPrompt
	local remotes = RS:FindFirstChild("CityRemotes")
	truthy(remotes ~= nil, "ReplicatedStorage.CityRemotes exists")
	local listened = {}
	for _, r in (remotes and remotes:GetChildren() or {}) do
		if r.ClassName == "RemoteEvent" or r.ClassName == "RemoteFunction" then
			table.insert(listened, r.Name)
		end
	end
	table.sort(listened)
	eq(table.concat(listened, ","), "Announce,Board,Fx,State,Toast", "five server -> client remotes, nothing else")
	local fnCount = 0
	for _, d in RS:GetDescendants() do
		if d.ClassName == "RemoteFunction" then fnCount += 1 end
	end
	eq(fnCount, 0, "no RemoteFunction anywhere")
end

--============================================================================ 3. join and LAND, under the engine's spawn order
local remotes = RS:FindFirstChild("CityRemotes")
local State, Toast = remotes:FindFirstChild("State"), remotes:FindFirstChild("Toast")
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
local function infoOf(userId)
	local root = SS:FindFirstChild("CityInfo")
	return root and root:FindFirstChild(tostring(userId))
end

local pa = h:join("Nova", A)
local padA = pa.RespawnLocation
truthy(padA ~= nil and padA.ClassName == "SpawnLocation" and padA.Name == "Arrival",
	"PlayerAdded points RespawnLocation at the player's own arrival pad synchronously, before any yield")
local shelfA = padA and padA.Parent
local ca = h.Players:simulateSpawn(pa, h.workspace)
h:advance(0.2)
local hrpA = ca:FindFirstChild("HumanoidRootPart")
truthy(flat(hrpA.Position, padA.Position) <= 4, string.format("the joining character LANDS on its own pad (%.2f studs)", flat(hrpA.Position, padA.Position)))
truthy(hrpA.Position.Y > TOP, "above the pad, not in it")

local pb = h:join("Orion", B)
local cb = h.Players:simulateSpawn(pb, h.workspace)
h:advance(0.2)
local padB = pb.RespawnLocation
truthy(padB ~= nil and padB ~= padA, "a second player gets a different shelf")
local hrpB = cb:FindFirstChild("HumanoidRootPart")
truthy(flat(hrpB.Position, padB.Position) <= 4, "the second character lands on ITS OWN pad")
truthy(flat(hrpB.Position, padA.Position) > 60, "and not on the first player's")
do
	local c2 = h.Players:simulateSpawn(pb, h.workspace)
	h:advance(0.2)
	truthy(flat(c2:FindFirstChild("HumanoidRootPart").Position, padB.Position) <= 4, "a respawn lands on the player's own pad again")
	cb = c2
	hrpB = c2:FindFirstChild("HumanoidRootPart")
end
do
	pb.RespawnLocation = nil
	local c3 = h.Players:simulateSpawn(pb, h.workspace)
	h:advance(0.5)
	local p = c3:FindFirstChild("HumanoidRootPart").Position
	truthy(flat(p, padB.Position) <= 4, string.format("with RespawnLocation cleared, the handler still moves the character to its own pad (%.1f studs)", flat(p, padB.Position)))
	eq(pb.RespawnLocation, padB, "and points RespawnLocation back at it")
	cb = c3
	hrpB = c3:FindFirstChild("HumanoidRootPart")
end

--============================================================================ 4. the city loads; the first build
h:advance(1)
local st0 = stateOf(pa)
truthy(st0 ~= nil and st0.loaded, "the owner receives State, loaded")
near(st0 and st0.credits or -1, 30, 0.01, "a new city starts with 30 credits")
eq(st0 and st0.population, 0, "and population 0")
local lotsA = shelfA:FindFirstChild("Lots")
local signsA = shelfA:FindFirstChild("Signs")
eq(#lotsA:GetChildren(), 6, "the Landing Field's six lots appear when the city loads")
eq(signsA and #signsA:GetChildren() or 0, 5, "and five signs stand in the locked districts' slots")
do
	local named = 0
	for _, s in signsA:GetChildren() do
		local gui = s:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label and string.find(label.Text, "opens at population", 1, true) then named += 1 end
	end
	eq(named, 5, "each sign says which district opens there, and at what population")
end
local info = infoOf(A)
truthy(info ~= nil and type(info:GetAttribute("Seed")) == "number", "ServerStorage.CityInfo.<userId> holds the seed (never replicated)")
local seedA = info and info:GetAttribute("Seed")
truthy(seedA ~= nil and seedA >= 1 and seedA <= 2147483646, "a seed 1..2147483646 was drawn for the new city")

-- every lot's post has a reachable prompt, on the street side of its plate
local function postOf(shelf, key)
	local lot = shelf:FindFirstChild("Lots"):FindFirstChild("Lot_" .. key)
	local post = lot and lot:FindFirstChild("Post")
	return post, post and post:FindFirstChild("BuildPrompt"), lot
end
local function checkReach(shelf, label)
	local centre = shelf:FindFirstChild("Rock").Position
	local ok, n = true, 0
	for _, lot in shelf:FindFirstChild("Lots"):GetChildren() do
		n += 1
		local post = lot:FindFirstChild("Post")
		local prompt = post and post:FindFirstChild("BuildPrompt")
		local plate = lot:FindFirstChild("Plate")
		if not (post and prompt and plate) then ok = false continue end
		-- stand 2 studs from the post on the street side (toward the shelf centre), on the rock
		local dir = Vector3.new(centre.X - post.Position.X, 0, centre.Z - post.Position.Z).Unit
		local stand = Vector3.new(post.Position.X + dir.X * 2, 3.5, post.Position.Z + dir.Z * 2)
		local fromCentre = flat(stand, centre)
		local onPlate = flat(stand, plate.Position) <= 5 * math.sqrt(2)
		if (stand - post.Position).Magnitude > prompt.MaxActivationDistance or fromCentre > 78 or prompt.RequiresLineOfSight then ok = false end
		if prompt.HoldDuration ~= 0 then ok = false end
	end
	truthy(ok and n > 0, string.format("%s: every one of %d lot prompts is reachable from the street side (8 studs, no hold, no line of sight)", label, n))
end
checkReach(shelfA, "Nova's Landing Field")

-- the ★: the HUD names a lot; walk there at WalkSpeed and press its prompt
local tJoin = h.scheduler:now()
local function walkTo(hrp, target, speed)
	speed = speed or 16
	for _ = 1, 600 do
		local p = hrp.Position
		local dx, dz = target.X - p.X, target.Z - p.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 0.5 then return true end
		local step = math.min(d, speed * 0.1)
		hrp.CFrame = CFrame.new(p.X + dx / d * step, p.Y, p.Z + dz / d * step)
		h:advance(0.1)
	end
	return false
end
local function standBy(shelf, post)
	local centre = shelf:FindFirstChild("Rock").Position
	local dir = Vector3.new(centre.X - post.Position.X, 0, centre.Z - post.Position.Z).Unit
	return Vector3.new(post.Position.X + dir.X * 2, 3.5, post.Position.Z + dir.Z * 2)
end
-- press a lot's prompt the way a player can: only from within its reach
local function press(plr, hrp, shelf, key)
	local post, prompt = postOf(shelf, key)
	if not (post and prompt) then return false, "no prompt" end
	if (hrp.Position - post.Position).Magnitude > prompt.MaxActivationDistance then return false, "out of reach" end
	if not prompt.Enabled then return false, "disabled" end
	prompt.Triggered:Fire(plr)
	return true
end
local star = st0 and st0.star
truthy(star ~= nil and type(star.key) == "string", "the State names a ★ lot from the start")
local firstBuildAt = nil
if star then
	local post = postOf(shelfA, star.key)
	truthy(post ~= nil, "the ★ lot exists in the workspace (Lot_" .. tostring(star.key) .. ")")
	h:advance(1.0) -- a normal player reads the hint for a second
	walkTo(hrpA, standBy(shelfA, post))
	local ok, why = press(pa, hrpA, shelfA, star.key)
	truthy(ok, "the ★ lot's prompt is in reach after the walk (" .. tostring(why) .. ")")
	firstBuildAt = h.scheduler:now() - tJoin
	h:advance(0.5)
	local _, _, lot = postOf(shelfA, star.key)
	local body = lot and lot:FindFirstChild("Body")
	truthy(body ~= nil, "pressing BUILD raises a building on the lot")
	near(body and body.Size.Y or -1, 4, 1e-6, "one storey: 4 studs tall")
	print(string.format("  first build %.1f s after the city loaded (DESIGN 14: 3.3-3.9 s)", firstBuildAt))
	truthy(firstBuildAt <= 5, "the core action comes within 5 s of a loaded join (checklist §4)")
	local st1 = stateOf(pa)
	near(st1.credits, 15, 0.05, "the first build cost 15 credits")
	eq(st1.population, 0, "one side alone makes no citizens")
	truthy(st1.ordersLeft > 590, "a build sets the Orders to 10 minutes (" .. tostring(st1.ordersLeft) .. " s)")
	eq(st1.tutorial, 1, "the hint moves on (tutorial 0 -> 1)")
	truthy(st1.star and st1.star.zone ~= star.zone, "the ★ moves to the other side (" .. tostring(star.zone) .. " -> " .. tostring(st1.star and st1.star.zone) .. ")")
end

-- play like the HUD says: walk to the ★, press it when affordable
local bought = 0
local function play(plr, hrp, shelf, seconds, untilFn)
	local tEnd = h.scheduler:now() + seconds
	while h.scheduler:now() < tEnd do
		local st = stateOf(plr)
		if st and st.loaded and st.star then
			local post = postOf(shelf, st.star.key)
			if post then
				local stand = standBy(shelf, post)
				if flat(hrp.Position, stand) > 0.6 then
					local p = hrp.Position
					local dx, dz = stand.X - p.X, stand.Z - p.Z
					local d = math.sqrt(dx * dx + dz * dz)
					local step = math.min(d, 16 * 0.85 * 0.1)
					hrp.CFrame = CFrame.new(p.X + dx / d * step, p.Y, p.Z + dz / d * step)
				elseif st.credits >= st.star.price then
					if press(plr, hrp, shelf, st.star.key) then bought += 1 end
				end
			end
		end
		h:advance(0.1)
		if untilFn and untilFn() then return true end
	end
	return false
end
play(pa, hrpA, shelfA, 30, function()
	local st = stateOf(pa)
	return st and st.population >= 4
end)
local st2 = stateOf(pa)
eq(st2.population, 4, "the second build makes 4 citizens")
near(st2.income, 1, 1e-9, "earning 1 credit a second (+60/min)")
do
	local c0 = stateOf(pa).credits
	h:advance(5)
	local c1 = stateOf(pa).credits
	near(c1 - c0, 5, 0.3, string.format("credits rise while the Orders run (%.2f -> %.2f in 5 s)", c0, c1))
end
local lead = pa:FindFirstChild("leaderstats")
eq(lead and lead:FindFirstChild("Population") and lead.Population.Value, 4, "leaderstats.Population shows it")

--============================================================================ 5. a storey on a built lot
do
	local st = stateOf(pa)
	local builtKey = nil
	for _, lot in lotsA:GetChildren() do
		if lot:FindFirstChild("Body") then builtKey = string.sub(lot.Name, 5) break end
	end
	truthy(builtKey ~= nil, "set-up: a built lot")
	local post, prompt, lot = postOf(shelfA, builtKey)
	eq(prompt and prompt.ActionText, "Add storey", "a built lot's prompt says Add storey")
	truthy(prompt and string.find(prompt.ObjectText, "1/22", 1, true) ~= nil, "and names its storeys: " .. tostring(prompt and prompt.ObjectText))
	-- wait for 15 x 1.35 = 20.25 credits, walk over, add the storey
	for _ = 1, 400 do
		if stateOf(pa).credits >= 20.25 then break end
		h:advance(0.1)
	end
	walkTo(hrpA, standBy(shelfA, post))
	local ok = press(pa, hrpA, shelfA, builtKey)
	truthy(ok, "the built lot's prompt is in reach")
	h:advance(0.5)
	local body = lot:FindFirstChild("Body")
	near(body and body.Size.Y or -1, 8, 1e-6, "Add storey makes the building 8 studs tall")
	truthy(string.find(prompt.ObjectText, "2/22", 1, true) ~= nil, "and the prompt says 2/22: " .. prompt.ObjectText)
end

--============================================================================ 6. refusals always speak
do
	-- an unaffordable lot
	local st = stateOf(pa)
	local dearKey, dearPrice = nil, 0
	for _, lot in lotsA:GetChildren() do
		local key = string.sub(lot.Name, 5)
		if not lot:FindFirstChild("Body") then dearKey = key end
	end
	-- spend down first: wait until the next purchase is unaffordable is not guaranteed; use a built lot's next storey
	local n0 = #toastsOf(pa)
	local post = postOf(shelfA, dearKey or "1_1")
	walkTo(hrpA, standBy(shelfA, post))
	-- make it unaffordable: buy until credits are short, then press once more
	for _ = 1, 20 do
		press(pa, hrpA, shelfA, dearKey or "1_1")
		h:advance(0.13)
	end
	local found = false
	for i = n0 + 1, #toastsOf(pa) do
		if string.find(toastsOf(pa)[i], "Need", 1, true) and string.find(toastsOf(pa)[i], "credits, you have", 1, true) then found = true end
	end
	truthy(found, "an unaffordable press is refused with a toast naming the price and the balance: " .. lastToast(pa))
	-- someone else's lot (only reachable by an exploit: the shelves are 60 studs apart)
	local n1 = #toastsOf(pb)
	local key = string.sub(lotsA:GetChildren()[1].Name, 5)
	local _, prompt = postOf(shelfA, key)
	prompt.Triggered:Fire(pb)
	h:advance(0.1)
	truthy(#toastsOf(pb) > n1 and string.find(lastToast(pb), "This is Nova's city", 1, true) ~= nil,
		"a press on someone else's lot is refused and says whose city it is: " .. lastToast(pb))
	-- a flood is cut at 8/s with one 'Slow down'
	local n2 = #toastsOf(pa)
	local credits0 = stateOf(pa).credits
	for _ = 1, 40 do prompt.Triggered:Fire(pa) end
	h:advance(0.1)
	local slow = 0
	for i = n2 + 1, #toastsOf(pa) do if string.find(toastsOf(pa)[i], "Slow down", 1, true) then slow += 1 end end
	eq(slow, 1, "40 presses in one frame are cut at 8/s with exactly one 'Slow down' toast")
	truthy(#toastsOf(pa) - n2 <= 9, string.format("and at most 8 answers + the slow-down (%d)", #toastsOf(pa) - n2))
end

--============================================================================ 7. population 80: Market Row opens where its sign stood
do
	local sign2 = signsA:FindFirstChild("Sign_2")
	truthy(sign2 ~= nil, "set-up: Market Row's sign stands in its slot")
	local signPos = sign2 and sign2.Position
	local tStart = h.scheduler:now()
	local reached = play(pa, hrpA, shelfA, 12 * 60, function()
		local st = stateOf(pa)
		return st and st.population >= 80
	end)
	truthy(reached, "following the ★, the city reaches population 80")
	local mins = (h.scheduler:now() - tStart) / 60
	print(string.format("  population 80 after %.2f min of play (DESIGN 3.4 min from join)", mins + 0.1))
	h:advance(0.5)
	truthy(signsA:FindFirstChild("Sign_2") == nil, "Market Row's sign is gone")
	local d2 = 0
	local worst = 0
	for _, lot in lotsA:GetChildren() do
		if string.sub(lot.Name, 1, 6) == "Lot_2_" then
			d2 += 1
			if signPos then
				worst = math.max(worst, flat(lot:FindFirstChild("Plate").Position, signPos))
			end
		end
	end
	eq(d2, 6, "Market Row's six lots appear")
	truthy(worst <= 30, string.format("in the slot its sign stood in (every lot within %.1f studs of the sign, <= 30)", worst))
	checkReach(shelfA, "Nova's two districts")
	local hall = shelfA:FindFirstChild("TownHall")
	truthy(hall:FindFirstChild("Clock") ~= nil, "the Town Hall gains Market Row's clock face (public)")
	eq(stateOf(pa).districts, 2, "the State says two districts are open")
end

--============================================================================ 8. the Orders run out; a purchase restarts them
do
	-- stand still by the pad for 10 minutes and 10 seconds
	hrpA.CFrame = CFrame.new(padA.Position + Vector3.new(0, 3.5, 0))
	for _ = 1, 61 do h:advance(10) end
	local st = stateOf(pa)
	eq(st.ordersLeft, 0, "10 minutes after the last build the Orders have run out")
	local c0 = st.credits
	h:advance(30)
	local c1 = stateOf(pa).credits
	local cheapest = stateOf(pa).cheapest or math.huge
	if c0 >= cheapest then
		near(c1, c0, 1e-6, "with the Orders out (and a storey affordable) the city earns nothing")
	else
		truthy(c1 <= cheapest + 1e-6, "with nothing affordable the safety net pays only up to the cheapest storey")
	end
	eq(stateOf(pa).working, false, "the State says the workers are idle")
	-- a purchase restarts them
	local starNow = stateOf(pa).star
	local post = postOf(shelfA, starNow.key)
	walkTo(hrpA, standBy(shelfA, post))
	for _ = 1, 600 do
		if stateOf(pa).credits >= stateOf(pa).star.price then break end
		h:advance(1)
	end
	truthy(press(pa, hrpA, shelfA, stateOf(pa).star.key), "set-up: the ★ is pressed")
	h:advance(1)
	local st2b = stateOf(pa)
	truthy(st2b.ordersLeft > 590, "a purchase puts the workers back to work for 10 minutes")
	local c2 = st2b.credits
	h:advance(5)
	truthy(stateOf(pa).credits > c2 + 1, "and the credits rise again")
end

--============================================================================ 9. the fall rescue
do
	local n0 = #toastsOf(pb)
	hrpB.CFrame = CFrame.new(padB.Position.X + 90, -40, padB.Position.Z)
	h:advance(0.3)
	truthy(flat(hrpB.Position, padB.Position) <= 4 and hrpB.Position.Y > 0, "a character below y = -30 is put back on its own pad")
	truthy(#toastsOf(pb) > n0 and string.find(lastToast(pb), "updraft", 1, true) ~= nil, "with a toast: " .. lastToast(pb))
end

--============================================================================ 10. the full city: budgets, every prompt, the inventory
do
	local pc = h:join("Builder", BIG)
	local cc = h.Players:simulateSpawn(pc, h.workspace)
	h:advance(2)
	local shelfC = pc.RespawnLocation.Parent
	local st = stateOf(pc)
	truthy(st and st.loaded, "a full city loads")
	eq(st and st.population, 1031184, "every lot at 22 storeys: population 1 031 184")
	eq(#shelfC:FindFirstChild("Lots"):GetChildren(), 36, "all 36 lots are built")
	eq(#shelfC:FindFirstChild("Signs"):GetChildren(), 0, "and no locked-district sign is left")
	local topped, disabled = 0, 0
	for _, lot in shelfC:FindFirstChild("Lots"):GetChildren() do
		local body = lot:FindFirstChild("Body")
		if body and math.abs(body.Size.Y - 88) < 1e-6 then topped += 1 end
		local prompt = lot:FindFirstChild("Post") and lot.Post:FindFirstChild("BuildPrompt")
		if prompt and prompt.Enabled == false then disabled += 1 end
	end
	eq(topped, 36, "every building stands 88 studs (22 x 4)")
	eq(disabled, 36, "a topped-out lot has no prompt to press")
	eq(st and st.star, nil, "a complete city has no ★")
	local airship = shelfC:FindFirstChild("Airship")
	truthy(airship ~= nil, "the Grand Airship is moored over a city that saw it arrive")
	if airship then
		local lowest = math.huge
		for _, p in airship:GetDescendants() do
			if p:IsA("BasePart") then lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2) end
		end
		truthy(lowest >= 119.9, string.format("its lowest point (%.1f) is at the hull line, y = 120", lowest))
	end
	engineScan(h.workspace, "the full city")
	do
		local list = engineReport()
		for _, line in list do print("  engine: " .. line) end
		eq(#list, 0, "every server part of the world with a full city and its moored airship has a size Roblox draws as written")
	end
	local hall = shelfC:FindFirstChild("TownHall")
	for _, piece in { "Clock", "Canopy", "MooringMast", "Halo", "Spire" } do
		truthy(hall:FindFirstChild(piece) ~= nil, "the full city's Town Hall has its " .. piece)
	end
	local parts, lights = countServer()
	print(string.format("  busy world (3 players, one full city): %d server parts, %d lights", parts, lights))
	local shelfParts = 0
	for _, d in shelfC:GetDescendants() do if d:IsA("BasePart") then shelfParts += 1 end end
	print(string.format("  the full shelf: %d parts (DESIGN 15: <= 244)", shelfParts))
	truthy(shelfParts <= 244, "a full shelf stays within its 244 parts (" .. shelfParts .. ")")
	truthy(parts <= 1500, "the world stays within 1 500 parts (" .. parts .. ")")
	truthy(lights <= 12, "and 12 lights (" .. lights .. ")")
	eq(#attributeInventory(), 0, "and still no attributes under workspace or ReplicatedStorage")
	eq(#redParts(), 0, "and still nothing red")
	-- the full city's own prompts: none to press (all topped), but none is unreachable either
end

--============================================================================ 11. rejoin restores every saved field and pays the offline earnings once
do
	local st = stateOf(pa)
	local want = { population = st.population, tutorial = st.tutorial, districts = st.districts }
	h:leave(pa)
	h:advance(1)
	eq(#lotsA:GetChildren(), 0, "leaving clears the city off the shelf")
	local saved = store:GetAsync("u_" .. A)
	truthy(saved and saved.data and saved.lockUntil == 0, "leaving writes the profile and RELEASES the lock")
	truthy(saved and type(saved.data.lots) == "table", "with the lots")
	local intKeys = 0
	for k in (saved and saved.data.lots or {}) do if type(k) ~= "string" then intKeys += 1 end end
	eq(intKeys, 0, "every saved lot key is a string")
	-- pretend the player was away 5 minutes with 2 minutes of Orders left when they left
	local credits0 = saved.data.credits
	saved.data.savedAt = os.time() - 300
	saved.data.ordersUntil = os.time() - 180
	store:SetAsync("u_" .. A, saved)
	local pa2 = h:join("Nova", A)
	h.Players:simulateSpawn(pa2, h.workspace)
	h:advance(1)
	local st2 = stateOf(pa2)
	truthy(st2 and st2.loaded, "the rejoin loads")
	for field, v in want do eq(st2[field], v, "rejoin restores " .. field) end
	local income = st2.income
	-- 120 s of Orders were left; after them the safety net only tops up to the cheapest storey
	local paid = st2.credits - credits0
	truthy(paid >= income * 120 - 1 and paid <= income * 120 + 2 + (st2.cheapest or 0), string.format(
		"the workers finished their Orders offline: +%.1f (%.1f/s x 120 s = %.1f)", paid, income, income * 120))
	local offlineToast = false
	for _, t in toastsOf(pa2) do if string.find(t, "while you were away", 1, true) then offlineToast = true end end
	truthy(offlineToast, "and a toast says so")
	-- leave and rejoin at once: nothing more is paid (credits and savedAt travel together)
	local c2 = stateOf(pa2).credits
	h:leave(pa2)
	h:advance(1)
	local pa3 = h:join("Nova", A)
	h.Players:simulateSpawn(pa3, h.workspace)
	h:advance(1)
	local c3 = stateOf(pa3).credits
	truthy(c3 - c2 <= stateOf(pa3).income * 3 + 0.01, string.format("an immediate rejoin pays nothing twice (%.1f -> %.1f)", c2, c3))
	eq(pa3:FindFirstChild("leaderstats").Population.Value, want.population, "and leaderstats")
	pa = pa3
end

--============================================================================ 12. six shelves, and a seventh player
do
	local joined = {}
	for i = 1, 3 do
		table.insert(joined, h:join("Filler" .. i, 9000 + i))
	end
	h:advance(0.5)
	local owners, n = {}, 0
	for _, p in h.Players:GetPlayers() do
		local pad = p.RespawnLocation
		if pad then
			owners[pad] = (owners[pad] or 0) + 1
			n += 1
		end
	end
	local used, shared = 0, 0
	for _, c in owners do
		used += 1
		if c > 1 then shared += 1 end
	end
	eq(used, 6, "six players hold all six shelves")
	eq(shared, 0, "no two players share a shelf")
	local seventh = h:join("Seventh", 9999)
	h:advance(0.2)
	truthy(rawget(seventh, "__kicked") ~= nil, "a seventh player is kicked with a reason, never left without a shelf")
	eq(seventh.RespawnLocation, nil, "and was never given a pad")
	truthy(string.find(tostring(rawget(seventh, "__kicked")), "6 shelves", 1, true) ~= nil, "the reason says why: " .. tostring(rawget(seventh, "__kicked")))
	h:leave(joined[1])
	h:advance(0.5)
	local eighth = h:join("Eighth", 10000)
	h:advance(0.2)
	truthy(eighth.RespawnLocation ~= nil and rawget(eighth, "__kicked") == nil, "the shelf a leaver freed goes to the next joiner")
end

--============================================================================ 13. the Census board renders on the owner's own board
-- (one player left in the server: robloxemu fires OnClientEvent for every connection whatever the target, so a HUD is
-- run only once every other player has gone; check_outpostzero_board covers the board in depth)
do
	for _, p in h.Players:GetPlayers() do
		if p ~= pa then h:leave(p) end
	end
	h:advance(1)
	h.Players.LocalPlayer = pa
	local okHud, errHud = h:tryRun("client/Hud.client")
	truthy(okHud, "the HUD loads (" .. tostring(errHud) .. ")")
	h:advance(31) -- the server re-sends every owner's board every 30 s
	local folder = pa.PlayerGui:FindFirstChild("BoardGuis")
	local sg = folder and folder:FindFirstChild("Census")
	local myShelf = pa.RespawnLocation.Parent
	truthy(sg ~= nil, "the Census renders: a SurfaceGui in the owner's PlayerGui")
	eq(sg and sg.Adornee, myShelf.Board.BoardFace, "adorned to the owner's own board face, 10 studs from their pad")
	local texts = {}
	local mine = nil
	for i = 1, 10 do
		local r = sg and sg.Background.Rows:FindFirstChild("Row_" .. i)
		if r then
			table.insert(texts, r.Text)
			if string.find(r.Text, "Nova", 1, true) then mine = r.Text end
		end
	end
	print("  the rendered Census: " .. table.concat(texts, " | "))
	truthy(#texts >= 2, "public rows render (" .. #texts .. ")")
	truthy(mine ~= nil, "with the owner's own row on it: " .. tostring(mine))
	truthy(texts[1] and string.find(texts[1], "1 031 184", 1, true) ~= nil, "ranked: the full city (1 031 184, saved by its leave) on top: " .. tostring(texts[1]))
	local title = myShelf.Board.BoardFrame:FindFirstChild("TitlePlate")
	truthy(title and string.find(title.Title.Text, "Nova's CENSUS", 1, true) ~= nil, "and the board's public title plate names its owner")
end

print("")
local stray = {}
for _, w in h.warnings do
	if not string.find(w, "a seventh player", 1, true) then table.insert(stray, w) end
end
eq(#stray, 0, "the server warned about nothing else (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero check failed", 0) end
