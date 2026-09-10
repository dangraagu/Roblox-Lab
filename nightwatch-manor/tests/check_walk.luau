-- Nightwatch Manor — WALK THE GAME. Not "is it parented", not "does the arithmetic round":
-- can a player standing where the engine puts them physically get to the first objective and
-- back out again, through the world the server actually built?
--
-- Run from this directory:
--   py -3 ../../robloxemu/wrap.py --game .. --out build/nightwatch-manor.luau
--   luau check_walk.luau
--
-- This repo has shipped four games with thousands of green assertions that were unplayable,
-- because the core loop was unreachable in the built world: Grow a Crystal's sockets were never
-- parented; a sibling put every player on the ROOF of their own sealed cavern. Both suites were
-- green. So nothing here is read out of `Manor.plan` — the plan is what the server INTENDED. The
-- graph walked below is recovered from the parts in the workspace:
--
--   * a room is a `Room<n>_<kind>` folder, and its centre is its Floor part's position;
--   * two rooms one RoomSize apart are CONNECTED only if no `Wall*` part covers the middle of
--     their shared edge at head height — i.e. only if a player could really walk through;
--   * everything solid in the manor at torso height is an obstacle, furniture included: the
--     bookshelves, the dining table, the pedestals, the exit slab.
--
-- The character is then moved by hand, WalkSpeed * dt per tick, sliding along walls the way a
-- Roblox character does, and a ProximityPrompt is only ever fired when the character is inside
-- its own MaxActivationDistance. If the walk cannot reach a prompt, no prompt is pressed, and
-- the run fails — which is the whole point.

local Harness = require("../../robloxemu/emu/harness")

local h = Harness.new({
	bundle = require("./build/nightwatch-manor"),
	name = "nightwatch-manor-walk",
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

local ME = 4242
local store = h.services.DataStoreService:GetDataStore("NightwatchManor_v1")
store:SetAsync("u_" .. ME, { data = { night = 1, stash = 0, best = 0, levels = {} } })

assert(h:tryRun("server/Main.server"))
h:advance(1)

local Config = h.modules["shared/Config"].value
local WALK = Config.Player.WalkSpeed
local SIZE = Config.Manor.RoomSize
local DT = Config.TickSeconds
local RADIUS = 2 -- a Roblox character is about four studs across

local me = h:join("Nightwatchman", ME)
h:advance(1)
local char = h.Players:simulateSpawn(me, h.workspace)

-- NO advance here on purpose. CharacterAdded has fired and returned; the 0.2-second re-placement
-- fallback has NOT run, and 0.2 seconds is 0.2 seconds of falling. Without this line the walk
-- below happily passes with `placeCharacter()` deleted, because the fallback quietly fixes it.
local hrp = char:FindFirstChild("HumanoidRootPart")
truthy(hrp ~= nil, "the character has a root part to walk with")
truthy(hrp ~= nil and hrp.Position.Magnitude > 1000,
	"the character is moved into its own zone on the SAME frame it appears, not a fifth of a second later")
h:advance(1)

local hum = char:FindFirstChildOfClass("Humanoid")
eq(hum and hum.WalkSpeed, WALK, "and the server set the walk speed the whole chase is balanced against")

local remotes = h.ReplicatedStorage:FindFirstChild("ManorRemotes")
local stateRemote = remotes:FindFirstChild("State")
local noticeRemote = remotes:FindFirstChild("Notice")
local function lastState()
	local sent = stateRemote:sentTo(me)
	for i = #sent, 1, -1 do
		if type(sent[i].args[1]) == "table" then return sent[i].args[1] end
	end
	return nil
end
local function noticesOfKind(kind)
	local n = 0
	for _, s in noticeRemote:sentTo(me) do
		local p = s.args[1]
		if type(p) == "table" and p.kind == kind then n += 1 end
	end
	return n
end

--============================================================================ walking machinery

-- Every solid thing in a character's way, as an axis-aligned box, measured RELATIVE TO THE FLOOR
-- IT STANDS ON — every zone in this game sits at index * ZoneSpacing and roughly a hundred studs
-- up, so an absolute height band silently matches nothing and the walk below turns into the
-- wall-walking bot this whole exercise is about. (It did, first time: three control mutations,
-- including sealing every room, all passed.)
--
-- STEP is how far a Roblox Humanoid climbs without jumping: anything whose top is below it is
-- walked over, not into — the rugs, the runners, the puddle, the upgrade pads, the boot rack.
-- HEAD is the top of the band; a lintel at DoorHeight, the portraits and the ceiling fixtures are
-- above it and are not obstacles either. The Nightwatcher is excluded because it MOVES, and
-- because walking into it is the server's business rather than the collider's.
local STEP, HEAD = 2.5, 4.5
-- `pad` is the extra clearance PLANNING uses over what walking uses. Without it a route can be
-- laid exactly along an obstacle's surface, and then the half-stud of drift that walking a
-- polyline costs puts the character INSIDE the box, where every direction is blocked and it
-- stands there until the night runs out. (It did, on the corner of a dining chair.) This is the
-- ordinary planning-radius-vs-execution-radius margin.
local function collectObstacles(root, groundY, pad)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide ~= false then
			local anc, skip = d, false
			while anc ~= nil do
				if anc.Name == "Nightwatcher" then skip = true end
				anc = anc.Parent
			end
			if not skip then
				local p, s = d.Position, d.Size
				local lo, hi = p.Y - s.Y / 2 - groundY, p.Y + s.Y / 2 - groundY
				if hi > STEP and lo < HEAD then
					table.insert(out, {
						name = d.Name,
						x0 = p.X - s.X / 2 - RADIUS - pad, x1 = p.X + s.X / 2 + RADIUS + pad,
						z0 = p.Z - s.Z / 2 - RADIUS - pad, z1 = p.Z + s.Z / 2 + RADIUS + pad,
					})
				end
			end
		end
	end
	return out
end

local function makeBlocked(boxes)
	return function(x, z)
		for _, b in boxes do
			if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 then
				return true
			end
		end
		return false
	end
end

-- Move the character toward (tx, tz), at most `dist` studs, sliding on one axis when the other
-- is blocked. Returns the new position and whether it made any progress at all.
local function slide(blocked, px, pz, tx, tz, dist)
	local dx, dz = tx - px, tz - pz
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= 1e-9 then return px, pz, true end
	local ux, uz = dx / d, dz / d
	local want, moved = math.min(dist, d), 0
	local progress = false
	while moved < want - 1e-9 do
		local s = math.min(0.2, want - moved)
		if blocked(px, pz) then
			-- Already overlapping something (drift, or the server teleported us). A Roblox
			-- character is pushed out rather than frozen, so keep moving rather than reporting a
			-- stall the engine would not have.
			px, pz, progress = px + ux * s, pz + uz * s, true
		elseif not blocked(px + ux * s, pz + uz * s) then
			px, pz, progress = px + ux * s, pz + uz * s, true
		elseif not blocked(px + ux * s, pz) then
			px, progress = px + ux * s, true
		elseif not blocked(px, pz + uz * s) then
			pz, progress = pz + uz * s, true
		else
			break
		end
		moved += s
	end
	return px, pz, progress
end

-- A real route over the world as BUILT, not over the plan and not over room centres.
--
-- The first version of this walk aimed at the middle of each room in turn, and the middle of a
-- dining room is a 22-stud table. That is not a bug in the manor — you walk round a table — it is
-- a bug in a bot that only knows where rooms are. So: a 2-stud lattice over the manor's bounding
-- box, four-connected (no diagonals, so no corner can be cut), BFS from where the character is
-- standing to anything within `within` studs of the target, with `blocked` — the real parts, the
-- real furniture, the real doorways — deciding which nodes exist. If BFS finds nothing, there is
-- genuinely no way for a player to get there, and that is a finding rather than a bot artefact.
local GRID = 2
local function gridRoute(blocked, bounds, sx, sz, tx, tz, within)
	local cols = math.floor((bounds.x1 - bounds.x0) / GRID) + 1
	local rows = math.floor((bounds.z1 - bounds.z0) / GRID) + 1
	local function nodeAt(x, z)
		local i = math.floor((x - bounds.x0) / GRID + 0.5)
		local j = math.floor((z - bounds.z0) / GRID + 0.5)
		return math.max(0, math.min(cols - 1, i)), math.max(0, math.min(rows - 1, j))
	end
	local function pos(i, j) return bounds.x0 + i * GRID, bounds.z0 + j * GRID end
	local free = {}
	local function isFree(i, j)
		if i < 0 or j < 0 or i >= cols or j >= rows then return false end
		local id = j * cols + i
		local v = free[id]
		if v == nil then
			local x, z = pos(i, j)
			v = not blocked(x, z)
			free[id] = v
		end
		return v
	end

	local si, sj = nodeAt(sx, sz)
	if not isFree(si, sj) then
		-- The character can be standing inside an expanded box (right up against a wall); take
		-- the nearest node it could actually stand on.
		local best, bi, bj
		for di = -3, 3 do
			for dj = -3, 3 do
				if isFree(si + di, sj + dj) then
					local d = di * di + dj * dj
					if best == nil or d < best then best, bi, bj = d, si + di, sj + dj end
				end
			end
		end
		if best == nil then return nil end
		si, sj = bi, bj
	end

	local prev = {}
	local seen = { [sj * cols + si] = true }
	local q, head = { { si, sj } }, 1
	local goal = nil
	while head <= #q do
		local n = q[head]; head += 1
		local x, z = pos(n[1], n[2])
		if (x - tx) ^ 2 + (z - tz) ^ 2 <= within * within then
			goal = n
			break
		end
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local i, j = n[1] + d[1], n[2] + d[2]
			local id = j * cols + i
			if not seen[id] and isFree(i, j) then
				seen[id] = true
				prev[id] = n
				table.insert(q, { i, j })
			end
		end
	end
	if goal == nil then return nil end

	local nodes, cur = {}, goal
	while cur do
		table.insert(nodes, 1, cur)
		cur = prev[cur[2] * cols + cur[1]]
	end

	-- String-pull: keep a node only when the straight line from the last kept one to the next
	-- would clip something. A player does not walk a staircase of 2-stud steps.
	local function clear(ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local n = math.max(2, math.ceil(math.sqrt(dx * dx + dz * dz) / 0.5))
		for k = 0, n do
			if blocked(ax + dx * k / n, az + dz * k / n) then return false end
		end
		return true
	end
	local out = {}
	local ax, az = pos(nodes[1][1], nodes[1][2])
	local last = 1
	for i = 2, #nodes do
		local x, z = pos(nodes[i][1], nodes[i][2])
		if not clear(ax, az, x, z) then
			local px, pz = pos(nodes[i - 1][1], nodes[i - 1][2])
			table.insert(out, { px, pz })
			ax, az, last = px, pz, i - 1
		end
	end
	local ex, ez = pos(nodes[#nodes][1], nodes[#nodes][2])
	table.insert(out, { ex, ez })
	local _ = last
	return out
end

local walked, ticks = 0, 0
-- Set by the chase probe at the bottom: called once per server tick while the character walks, so
-- the Nightwatcher can be sampled DURING a real walk instead of while standing still.
local tickHook: any = nil

-- Walk to a point, one server tick at a time, until it is within `within` studs or the budget
-- runs out. Returns whether it arrived.
local function walkTo(blocked, tx, tz, within, budgetTicks)
	for _ = 1, budgetTicks do
		local at = hrp.Position
		if math.sqrt((at.X - tx) ^ 2 + (at.Z - tz) ^ 2) <= within then
			return true
		end
		local nx, nz = slide(blocked, at.X, at.Z, tx, tz, WALK * DT)
		walked += math.sqrt((nx - at.X) ^ 2 + (nz - at.Z) ^ 2)
		char:PivotTo(CFrame.new(nx, at.Y, nz))
		h:advance(DT)
		ticks += 1
		if tickHook then tickHook() end
		local s = lastState()
		if s and s.phase ~= "NIGHT" and s.phase ~= "DAY" then
			return false
		end
	end
	local at = hrp.Position
	return math.sqrt((at.X - tx) ^ 2 + (at.Z - tz) ^ 2) <= within
end

-- Press a prompt, but only from inside its own MaxActivationDistance, measured to the part it
-- hangs on — the same rule Roblox enforces on a real player.
local function press(part, why)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		failed += 1
		print("FAIL: " .. why .. " — that part carries no prompt")
		return false
	end
	local d = (hrp.Position - part.Position).Magnitude
	if d > prompt.MaxActivationDistance then
		failed += 1
		print(string.format("FAIL: %s — the walk got to %.1f studs, the prompt reaches %.1f",
			why, d, prompt.MaxActivationDistance))
		return false
	end
	passed += 1
	print(string.format("  pressed %s from %.1f studs (reach %.0f)", prompt.ActionText, d, prompt.MaxActivationDistance))
	prompt.Triggered:Fire(me)
	h:advance(0.2)
	return true
end

-- Walk to a point over the real geometry. Fails loudly when no route exists, and fails loudly
-- when a route exists but the character cannot follow it.
local function walkTarget(planBlocked, blocked, bounds, tx, tz, within, label)
	local at = hrp.Position
	local route = gridRoute(planBlocked, bounds, at.X, at.Z, tx, tz, within)
	if route == nil then
		failed += 1
		print(string.format("FAIL: %s — NO WALKABLE ROUTE exists in the built world from (%.0f,%.0f) to (%.0f,%.0f)",
			label, at.X, at.Z, tx, tz))
		return false
	end
	for _, wp in route do
		-- Tight. Every segment of this route was verified free from the PREVIOUS waypoint, so a
		-- character allowed to stop a stud or two short starts the next segment off the line that
		-- was checked and walks into a jamb. (It did: "a route existed but the walk stalled".)
		if not walkTo(blocked, wp[1], wp[2], 0.4, 300) then
			local now = hrp.Position
			failed += 1
			print(string.format("FAIL: %s — a route existed but the walk stalled at (%.0f,%.0f) heading for (%.0f,%.0f)",
				label, now.X, now.Z, wp[1], wp[2]))
			return false
		end
	end
	passed += 1
	print(string.format("  %s: %d waypoints", label, #route))
	return true
end

local function boundsOf(rs)
	local b = { x0 = math.huge, x1 = -math.huge, z0 = math.huge, z1 = -math.huge }
	for _, r in rs do
		b.x0 = math.min(b.x0, r.x - SIZE / 2 - 2)
		b.x1 = math.max(b.x1, r.x + SIZE / 2 + 2)
		b.z0 = math.min(b.z0, r.z - SIZE / 2 - 2)
		b.z1 = math.max(b.z1, r.z + SIZE / 2 + 2)
	end
	return b
end
--=================================================================== 1. spawn, and get your bearings

local zone
for _, c in h.workspace:GetChildren() do
	if string.match(tostring(c.Name), "^Zone_") then zone = c end
end
truthy(zone ~= nil, "the player has a zone")
local house = zone and zone:FindFirstChild("Safehouse")
truthy(house ~= nil, "...with a safehouse in it")
local spawnPad = house and house:FindFirstChild("SpawnPad")
truthy(spawnPad ~= nil, "...and a spawn pad")

do
	local at = hrp.Position
	local d = (at - spawnPad.Position).Magnitude
	print(string.format("  spawned %.1f studs from the spawn pad, at (%.0f, %.0f, %.0f)", d, at.X, at.Y, at.Z))
	truthy(d < 25, string.format("the character starts ON its own spawn pad, not somewhere else (%.1f studs)", d))
	local floor = house:FindFirstChild("Floor")
	truthy(floor ~= nil and math.abs(at.X - floor.Position.X) < Config.Hub.Size / 2
		and math.abs(at.Z - floor.Position.Z) < Config.Hub.Size / 2,
		"...and inside the safehouse walls rather than on the roof or outside them")
end

--=================================================================== 2. walk to the manor door

local hubFloor = house:FindFirstChild("Floor")
truthy(hubFloor ~= nil, "the safehouse has a floor to stand on")
local hubGroundY = hubFloor and (hubFloor.Position.Y + hubFloor.Size.Y / 2) or 0
local hubBlocked = makeBlocked(collectObstacles(house, hubGroundY, 0))
local hubPlan = makeBlocked(collectObstacles(house, hubGroundY, 0.6))
local manorDoor = house:FindFirstChild("ManorDoor")
truthy(manorDoor ~= nil, "the safehouse has a door into the manor")

local hubBounds = { x0 = hubFloor.Position.X - Config.Hub.Size / 2, x1 = hubFloor.Position.X + Config.Hub.Size / 2,
	z0 = hubFloor.Position.Z - Config.Hub.Size / 2, z1 = hubFloor.Position.Z + Config.Hub.Size / 2 }

do
	walkTarget(hubPlan, hubBlocked, hubBounds, manorDoor.Position.X, manorDoor.Position.Z, 8,
		"the spawn pad -> the manor door")
	press(manorDoor, "ENTER THE MANOR")
end

local manor = zone:FindFirstChild("Manor")
truthy(manor ~= nil, "pressing it built a manor")
local night = lastState()
eq(night and night.phase, "NIGHT", "and the run is in the night phase")

--=========================================== 3. recover the walkable graph FROM THE BUILT PARTS

local manorGroundY = 0
local rooms = {} -- [key] = { x, z, folder }
local function key(x, z) return string.format("%d,%d", math.floor(x / SIZE + 0.5), math.floor(z / SIZE + 0.5)) end
for _, c in manor:GetChildren() do
	if string.match(tostring(c.Name), "^Room%d+_") then
		local floor = c:FindFirstChild("Floor")
		if floor then
			manorGroundY = floor.Position.Y + floor.Size.Y / 2
			rooms[key(floor.Position.X, floor.Position.Z)] = { x = floor.Position.X, z = floor.Position.Z, folder = c }
		end
	end
end
local roomCount = 0
for _ in rooms do roomCount += 1 end
print(string.format("  the manor that got built: %d rooms", roomCount))
truthy(roomCount >= 6, "the manor has at least its base six rooms")
truthy(roomCount <= Config.Manor.MaxRooms, string.format(
	"...and no more than Config.Manor.MaxRooms (%d vs %d)", roomCount, Config.Manor.MaxRooms))

-- Walls only. A shared edge is walkable exactly when nothing named Wall* covers its middle at
-- head height, which is the geometric definition of "there is a doorway here".
local wallBoxes = {}
for _, d in manor:GetDescendants() do
	if d:IsA("BasePart") and string.match(tostring(d.Name), "^Wall") then
		table.insert(wallBoxes, { p = d.Position, s = d.Size })
	end
end
local function edgeOpen(ax, az, bx, bz)
	local mx, mz = (ax + bx) / 2, (az + bz) / 2
	local my = manorGroundY + 3 -- chest height above the floor of THIS manor, not of the world
	for _, b in wallBoxes do
		if math.abs(mx - b.p.X) <= b.s.X / 2 + 0.01
			and math.abs(my - b.p.Y) <= b.s.Y / 2 + 0.01
			and math.abs(mz - b.p.Z) <= b.s.Z / 2 + 0.01 then
			return false
		end
	end
	return true
end

local nbs = {}
local doorways = 0
for k, r in rooms do
	nbs[k] = {}
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local ox, oz = r.x + d[1] * SIZE, r.z + d[2] * SIZE
		local o = rooms[key(ox, oz)]
		if o and edgeOpen(r.x, r.z, o.x, o.z) then
			table.insert(nbs[k], key(ox, oz))
			doorways += 1
		end
	end
end
print(string.format("  ...with %d doorways you can actually walk through (%.2f per room)", doorways / 2, doorways / 2 / roomCount))
truthy(doorways > 0, "the rooms are connected by holes a player can walk through, not just by the plan")

local function pathKeys(fromK, toK)
	if fromK == toK then return { fromK } end
	local prev, seen = {}, { [fromK] = true }
	local q, head = { fromK }, 1
	while head <= #q do
		local k = q[head]; head += 1
		if k == toK then
			local out, cur = { toK }, toK
			while cur ~= fromK do cur = prev[cur]; table.insert(out, 1, cur) end
			return out
		end
		for _, nb in nbs[k] or {} do
			if not seen[nb] then seen[nb] = true; prev[nb] = k; table.insert(q, nb) end
		end
	end
	return nil
end

--=========================================== 4. walk to a relic and take it, then walk out

local manorBlocked = makeBlocked(collectObstacles(manor, manorGroundY, 0))
local manorPlan = makeBlocked(collectObstacles(manor, manorGroundY, 0.6))

local manorBounds = boundsOf(rooms)

local pedestals = {}
for _, c in manor:GetChildren() do
	if string.match(tostring(c.Name), "^Pedestal_") then table.insert(pedestals, c) end
end
local exitDoor = manor:FindFirstChild("ExitDoor")
truthy(exitDoor ~= nil, "the manor has a way out")
local exitDoorPos = exitDoor and exitDoor.Position or Vector3.new(0, 0, 0)
truthy(#pedestals > 0, "there are relics on pedestals to go and take")

local startK = key(hrp.Position.X, hrp.Position.Z)
truthy(rooms[startK] ~= nil, "the night dropped the player INSIDE a room of the manor, not outside it")

-- EVERY relic the plan counted has to be reachable, not just the nearest one. A relic behind a
-- wall is a relic the player is told about (relicsTotal is on the HUD) and can never collect,
-- which is the "core loop unreachable in the built world" defect wearing a smaller hat.
do
	local at = hrp.Position
	local unreachable, names = 0, {}
	for _, ped in pedestals do
		if gridRoute(manorPlan, manorBounds, at.X, at.Z, ped.Position.X, ped.Position.Z, 10) == nil then
			unreachable += 1
			table.insert(names, ped.Name)
		end
	end
	eq(unreachable, 0, string.format("every one of the %d relics is reachable on foot from where the night starts%s",
		#pedestals, (next(names) and (" — stranded: " .. table.concat(names, ", ")) or "")))
	eq(#pedestals, night and night.relicsTotal, "and there is one pedestal per relic the HUD promises")
	truthy(gridRoute(manorPlan, manorBounds, at.X, at.Z, exitDoorPos.X, exitDoorPos.Z, 10) ~= nil,
		"...and so is the Servants' Exit")
end

do
	-- The nearest relic, by walkable rooms, is the first objective a person would head for.
	local best, bestLen
	for _, ped in pedestals do
		local p = pathKeys(startK, key(ped.Position.X, ped.Position.Z))
		if p and (bestLen == nil or #p < bestLen) then best, bestLen = ped, #p end
	end
	truthy(best ~= nil, "at least one relic is reachable on foot from where the night starts")
	if best then
		-- 10 studs, not 0: the pedestal is a solid 3x4 block and the prompt reaches 12.
		walkTarget(manorPlan, manorBlocked, manorBounds, best.Position.X, best.Position.Z, 8, "the foyer -> the nearest relic")
		local before = lastState().carried
		press(best, "TAKE the relic")
		eq(lastState().carried, before + 1, "walking up to a pedestal and pressing it puts the relic in the bag")
		eq(best:FindFirstChild("Relic"), nil, "...and takes it out of the world")
		truthy(lastState().carriedWorth > 0, "...and the bag is worth something")
	end
end

do
	truthy(rooms[key(exitDoor.Position.X, exitDoor.Position.Z)] ~= nil, "the exit door is standing inside a real room")
	walkTarget(manorPlan, manorBlocked, manorBounds, exitDoor.Position.X, exitDoor.Position.Z, 8, "the relic -> the Servants' Exit")
	local s = lastState()
	print(string.format("  at the exit after %.1fs of night, dread %.2f, %d relic(s) carried",
		ticks * DT, s and s.dread or -1, s and s.carried or -1))
	local stashBefore, worth = s.stash, s.carriedWorth
	press(exitDoor, "ESCAPE")
	local after = lastState()
	eq(after.stash, stashBefore + worth, "escaping banked exactly what was in the bag")
	eq(after.night, 2, "...and moved the player on to night 2")
	eq(after.carried, 0, "...and the bag is empty again")
	eq(noticesOfKind("EXTRACTED"), 1, "...and the player was told they got out")
end

h:advance(4)
eq(zone:FindFirstChild("Manor"), nil, "the manor is cleared away once the night is over")
eq(lastState().phase, "DAY", "and the player is back in the safehouse")

print(string.format("  loop 1 took %d ticks (%.1f s of night) and %.0f studs of walking",
	ticks, ticks * DT, walked))

--=========================================== 5. a second night, walked as a FULL CLEAR

-- One relic and out is the shortest loop there is. The loop a player actually plays is "take
-- everything, then leave", which crosses the whole manor and gives the Nightwatcher time to do
-- something about it. This pass asserts REACHABILITY (every relic, then the exit) and reports
-- what happened to the run rather than demanding it survive: whether a greedy clear survives is
-- a balance question, and tests/Chase.spec.luau is where that is measured.
do
	walkTarget(hubPlan, hubBlocked, hubBounds, manorDoor.Position.X, manorDoor.Position.Z, 8,
		"the safehouse -> the manor door again")
	press(manorDoor, "ENTER THE MANOR (night 2)")
	local m2 = zone:FindFirstChild("Manor")
	truthy(m2 ~= nil, "night 2 built its own manor")
	if m2 then
		rooms = {}
		for _, c in m2:GetChildren() do
			if string.match(tostring(c.Name), "^Room%d+_") then
				local floor = c:FindFirstChild("Floor")
				if floor then
					manorGroundY = floor.Position.Y + floor.Size.Y / 2
					rooms[key(floor.Position.X, floor.Position.Z)] = { x = floor.Position.X, z = floor.Position.Z, folder = c }
				end
			end
		end
		wallBoxes = {}
		for _, d in m2:GetDescendants() do
			if d:IsA("BasePart") and string.match(tostring(d.Name), "^Wall") then
				table.insert(wallBoxes, { p = d.Position, s = d.Size })
			end
		end
		nbs = {}
		for k, r in rooms do
			nbs[k] = {}
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local o = rooms[key(r.x + d[1] * SIZE, r.z + d[2] * SIZE)]
				if o and edgeOpen(r.x, r.z, o.x, o.z) then table.insert(nbs[k], key(o.x, o.z)) end
			end
		end
		manorBlocked = makeBlocked(collectObstacles(m2, manorGroundY, 0))
		manorPlan = makeBlocked(collectObstacles(m2, manorGroundY, 0.6))

		local peds2 = {}
		for _, c in m2:GetChildren() do
			if string.match(tostring(c.Name), "^Pedestal_") then table.insert(peds2, c) end
		end
		local bounds2 = boundsOf(rooms)
		local at2 = hrp.Position
		local unreachable = 0
		for _, ped in peds2 do
			if gridRoute(manorPlan, bounds2, at2.X, at2.Z, ped.Position.X, ped.Position.Z, 10) == nil then unreachable += 1 end
		end
		local exit2 = m2:FindFirstChild("ExitDoor")
		eq(unreachable, 0, string.format("night 2: all %d relics reachable on foot as well", #peds2))
		truthy(exit2 ~= nil and gridRoute(manorPlan, bounds2, at2.X, at2.Z, exit2.Position.X, exit2.Position.Z, 10) ~= nil,
			"night 2: and so is the way out")

		-- Now actually go and get them, nearest first, and see what the night does to us.
		local extractedBefore = noticesOfKind("EXTRACTED")
		local caughtBefore = noticesOfKind("CAUGHT")
		local evictedBefore = noticesOfKind("EVICTED")
		local took, startTicks = 0, ticks
		local taken = {}
		for _ = 1, #peds2 do
			local s = lastState()
			if s == nil or s.phase ~= "NIGHT" then break end
			local here = hrp.Position
			local best, bestLen
			for i, ped in peds2 do
				if not taken[i] and ped:FindFirstChild("Relic") ~= nil then
					local p = gridRoute(manorPlan, bounds2, here.X, here.Z, ped.Position.X, ped.Position.Z, 10)
					if p and (bestLen == nil or #p < bestLen) then best, bestLen = i, #p end
				end
			end
			if best == nil then break end
			taken[best] = true
			local ped = peds2[best]
			if not walkTarget(manorPlan, manorBlocked, bounds2, ped.Position.X, ped.Position.Z, 8, string.format("night 2: -> relic %d", best)) then break end
			local prompt = ped:FindFirstChildOfClass("ProximityPrompt")
			if prompt and (hrp.Position - ped.Position).Magnitude <= prompt.MaxActivationDistance then
				prompt.Triggered:Fire(me)
				h:advance(0.2)
				took += 1
			end
		end

		-- The night's OUTCOME is what the player was told, not what the phase reads a tenth of a
		-- second later: resolveNight narrates immediately and only drops back to DAY after
		-- Config.BeatSeconds, so reading `phase` here says "still inside" about a night that
		-- ended cleanly.
		local s = lastState()
		if s and s.phase == "NIGHT" then
			walkTarget(manorPlan, manorBlocked, bounds2, exit2.Position.X, exit2.Position.Z, 8, "night 2: -> the Servants' Exit")
			local reach = (hrp.Position - exit2.Position).Magnitude
			truthy(reach <= 12, string.format("night 2: the walk reaches the exit prompt (%.1f studs)", reach))
			if reach <= 12 then
				exit2:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(me)
				h:advance(0.3)
			end
		end
		h:advance(4)
		s = lastState()
		local outcome = "still inside"
		if noticesOfKind("EXTRACTED") > extractedBefore then
			outcome = "OUT with the haul"
		elseif noticesOfKind("CAUGHT") > caughtBefore then
			outcome = "CAUGHT"
		elseif noticesOfKind("EVICTED") > evictedBefore then
			outcome = "EVICTED at full dread"
		end
		print(string.format("  FULL CLEAR on night 2: took %d of %d relics in %.1f s of night -> %s (dread %.2f)",
			took, #peds2, (ticks - startTicks) * DT, outcome, s and s.dread or -1))
		truthy(took > 0, "night 2: the walk collected relics rather than getting stuck on the furniture")
		truthy(outcome ~= "still inside", "night 2: the night reached a defined outcome rather than stalling")
	end
end

--=========================================== 6. and the thing chasing you uses the same doors

-- `Manor.chaseStep` is proved wall-safe in tests/Manor.spec.luau, but nothing proved the SERVER
-- calls it: putting the old "aim at the centre of the next room" back into stepNight survived
-- every assertion in the repo. It matters because the wall is a real part with a DoorWidth hole
-- in it: the player has to use the hole, and a hunter that cuts the corner diagonally is running
-- a shorter race on a different map. So here the Nightwatcher is provoked into a hunt and its
-- position is sampled every tick against the walls that were actually built.
do
	walkTarget(hubPlan, hubBlocked, hubBounds, manorDoor.Position.X, manorDoor.Position.Z, 8,
		"the safehouse -> the manor door, one more time")
	press(manorDoor, "ENTER THE MANOR (night 3)")
	local m3 = zone:FindFirstChild("Manor")
	truthy(m3 ~= nil, "night 3 built a manor to be chased through")
	local watcher = m3 and m3:FindFirstChild("Nightwatcher")
	truthy(watcher ~= nil and watcher.PrimaryPart ~= nil, "...with a Nightwatcher in it")

	if m3 and watcher and watcher.PrimaryPart then
		local floorY = 0
		for _, c in m3:GetChildren() do
			if string.match(tostring(c.Name), "^Room%d+_") then
				local f = c:FindFirstChild("Floor")
				if f then floorY = f.Position.Y + f.Size.Y / 2 end
			end
		end
		-- The walls, unexpanded: what is being asked is whether the watcher's own centre passes
		-- THROUGH a wall, not whether its shoulders brush one.
		local walls = {}
		for _, d in m3:GetDescendants() do
			if d:IsA("BasePart") and string.match(tostring(d.Name), "^Wall") then
				local p, sz = d.Position, d.Size
				if p.Y + sz.Y / 2 - floorY > 2.5 and p.Y - sz.Y / 2 - floorY < 4.5 then
					table.insert(walls, { x0 = p.X - sz.X / 2, x1 = p.X + sz.X / 2, z0 = p.Z - sz.Z / 2, z1 = p.Z + sz.Z / 2 })
				end
			end
		end
		truthy(#walls > 0, "CONTROL: there are walls to cross in the first place")
		local function inWall(x, z)
			for _, b in walls do
				if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 then return true end
			end
			return false
		end

		-- Standing still one room away is not enough: the server only recomputes a cross-room
		-- target while you are SPOTTED, and a watcher that is already in your room just walks
		-- straight at you. So: walk into its face to start the hunt, then keep walking the manor
		-- while it follows, sampling its position every tick. That way it crosses room boundaries
		-- from wherever it happens to be standing — which is the case "aim at the next room's
		-- centre" gets wrong, and the case it is never in from a tidy room centre.
		local hunted, crossings, samples, worst, boundaries = 0, 0, 0, nil, 0
		-- Set from inside the sampler, not from the walk loop: `spotted` flips back off as soon as
		-- you break line of sight, so a flag only read between walk legs misses whole hunts.
		local sawIt = false
		local prev = watcher.PrimaryPart.Position
		local prevRoom = nil
		local function sample()
			local s = lastState()
			if s and s.spotted then
				hunted += 1
				sawIt = true
			end
			local now = watcher.PrimaryPart.Position
			-- Sample the SEGMENT it moved along, not just the endpoints: at 13 studs/s a tick is
			-- 1.3 studs and a wall is 1 stud thick, so endpoint sampling alone would step over it.
			local steps = 8
			for k = 0, steps do
				local x = prev.X + (now.X - prev.X) * k / steps
				local z = prev.Z + (now.Z - prev.Z) * k / steps
				samples += 1
				if inWall(x, z) then
					crossings += 1
					worst = worst or string.format("(%.1f, %.1f)", x, z)
				end
			end
			local rk = key(now.X, now.Z)
			if prevRoom ~= nil and rk ~= prevRoom then boundaries += 1 end
			prevRoom = rk
			prev = now
		end

		local rooms3, bounds3 = {}, nil
		for _, c in m3:GetChildren() do
			if string.match(tostring(c.Name), "^Room%d+_") then
				local f = c:FindFirstChild("Floor")
				if f then rooms3[key(f.Position.X, f.Position.Z)] = { x = f.Position.X, z = f.Position.Z, folder = c } end
			end
		end
		bounds3 = boundsOf(rooms3)
		local plan3 = makeBlocked(collectObstacles(m3, floorY, 0.6))
		local walk3 = makeBlocked(collectObstacles(m3, floorY, 0))

		-- Into its face — and it is PATROLLING, so its position has to be re-read as we close on
		-- it rather than walked at once as a fixed point.
		tickHook = sample
		local wp = watcher.PrimaryPart.Position
		for _ = 1, 12 do
			local now = watcher.PrimaryPart.Position
			local route = gridRoute(plan3, bounds3, hrp.Position.X, hrp.Position.Z, now.X, now.Z, 9)
			if route == nil then break end
			for _, wpt in route do
				walkTo(walk3, wpt[1], wpt[2], 0.4, 40)
				if sawIt then break end
				-- it moved: re-plan rather than walking at where it used to be
				if (watcher.PrimaryPart.Position - now).Magnitude > 12 then break end
			end
			if sawIt then break end
			local s = lastState()
			if s == nil or s.phase ~= "NIGHT" then break end
		end
		-- No assertion here: closing on a PATROLLING watcher may or may not draw its eye before the
		-- legs below do. That a hunt happened at all is asserted afterwards, on `hunted`.

		-- ...and then run for the far end with it behind you, sampler still on.
		local far, bestD = nil, nil
		for _, r in rooms3 do
			local d = (r.x - wp.X) ^ 2 + (r.z - wp.Z) ^ 2
			if bestD == nil or d > bestD then bestD, far = d, r end
		end
		if far then
			walkTarget(plan3, walk3, bounds3, far.x, far.z, 6, "night 3: run for the far end with it behind you")
			local back = watcher.PrimaryPart.Position
			walkTarget(plan3, walk3, bounds3, back.X, back.Z, 25, "night 3: and back toward it again")
		end
		tickHook = nil
		local _ = wp

		print(string.format("  night 3: hunting on %d ticks, watcher crossed %d room boundaries; %d of %d sampled points were inside a wall",
			hunted, boundaries, crossings, samples))
		truthy(hunted > 0, "CONTROL: the chase happened at all")
		truthy(boundaries > 0, "CONTROL: and the Nightwatcher really did leave the room it started in")
		eq(crossings, 0, "the Nightwatcher never walks THROUGH a wall while hunting" .. (worst and (" — first at " .. worst) or ""))
	end
end

h:advance(5)
print(string.format("  all three nights: %d ticks (%.1f s of night) and %.0f studs of walking",
	ticks, ticks * DT, walked))

--=========================================================================================== done

print("")
for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "the server ran the whole loop without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("nightwatch walk: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("nightwatch walk check failed", 0)
end
