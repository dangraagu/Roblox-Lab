--!strict
-- Crossing.luau — the guard on the Servants' Exit. PURE: config and plan passed in (tests/Crossing.spec.luau).
--
-- Why it exists. The highscore board (Board.luau) ranks the best night the server credited you with surviving, and
-- the only way to survive a night is the Servants' Exit prompt. In Roblox a player's own client moves their
-- character, so a script can put the character next to the exit door a second into the night and press E, and climb
-- the board a night every few seconds. The server refuses that, measuring two things itself:
--   * REACH: the character's root is within the exit prompt's reach of the door (+ Config.Guard.ReachSlack, for
--     latency) AND inside the exit room. A trigger from across the manor is refused, and so is one through a wall: the
--     prompt needs no line of sight, and before pass 2 (2026-10-01) a player in the room next to the exit could press
--     ESCAPE through the wall (public night 9: 77 studs of walking saved; one salted night-45 manor: 0.13 s from
--     where the night starts).
--   * TIME: the night has run at least `minSeconds`: the shortest walk that can possibly get from where the night puts
--     you (`start`) to within reach of the door (`exitDoor`), through the doorways, at Config.Player.WalkSpeed, less
--     Config.Guard.ClockSlack. A script that teleports has to wait as long as a perfect runner, so it gains nothing a
--     person could not.
--
-- `minDistance` is a LOWER BOUND on every legal walk, never an estimate: a player walking the perfect line must never
-- be refused. A walk crosses a sequence of doorway gaps, each leg inside one room, and every leg is at least the
-- distance between the two gaps it joins; the last leg, inside the exit room, is at least the straight line to the
-- reach circle. Dijkstra over the gaps gives the smallest such sum.
-- Everything is in the manor's own studs, on the ground plane (a height difference only makes a real distance
-- longer). The spec checks it against the doorway midpoints, random points in every gap, and the best walk a search
-- over the gaps can find, on nights 1-150.

local Crossing = {}

-- The exit door stands this far inside its face (the slab is a wall's thickness off the face, as it always was).
local EXIT_INSET_FROM_FACE = 6
-- beginNight puts you this far into the entrance room from its centre (+Z), clear of the foyer's lamp.
local START_OFFSET_Z = 12

export type Seg = { a: number, b: number, x1: number, z1: number, x2: number, z2: number }

function Crossing.pointSeg(px: number, pz: number, s: any): number
	local vx, vz = s.x2 - s.x1, s.z2 - s.z1
	local len2 = vx * vx + vz * vz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((px - s.x1) * vx + (pz - s.z1) * vz) / len2, 0, 1)
	end
	local cx, cz = s.x1 + vx * t, s.z1 + vz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

local function cross(ax: number, az: number, bx: number, bz: number): number
	return ax * bz - az * bx
end

-- The shortest distance between two segments on the plane (0 when they touch or cross).
function Crossing.segSeg(s: any, t: any): number
	local rx, rz = s.x2 - s.x1, s.z2 - s.z1
	local qx, qz = t.x2 - t.x1, t.z2 - t.z1
	local d = cross(rx, rz, qx, qz)
	if d ~= 0 then
		local u = cross(t.x1 - s.x1, t.z1 - s.z1, qx, qz) / d
		local v = cross(t.x1 - s.x1, t.z1 - s.z1, rx, rz) / d
		if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
			return 0
		end
	end
	return math.min(
		Crossing.pointSeg(s.x1, s.z1, t), Crossing.pointSeg(s.x2, s.z2, t),
		Crossing.pointSeg(t.x1, t.z1, s), Crossing.pointSeg(t.x2, t.z2, s)
	)
end

-- One segment per doorway: DoorWidth long, centred where `Manor.doorwayBetween` puts the hole, running along the
-- shared wall.
function Crossing.doorways(cfg: any, plan: any): { Seg }
	local out: { Seg } = {}
	local half = cfg.Manor.DoorWidth / 2
	local byId: { [number]: any } = {}
	for _, r in plan.rooms do byId[r.id] = r end
	local size = cfg.Manor.RoomSize
	for _, l in plan.links do
		local ra, rb = byId[l.a], byId[l.b]
		if ra and rb and math.abs(ra.gx - rb.gx) + math.abs(ra.gz - rb.gz) == 1 then
			local mx, mz = (ra.gx + rb.gx) / 2 * size, (ra.gz + rb.gz) / 2 * size
			if ra.gx ~= rb.gx then
				table.insert(out, { a = l.a, b = l.b, x1 = mx, z1 = mz - half, x2 = mx, z2 = mz + half })
			else
				table.insert(out, { a = l.a, b = l.b, x1 = mx - half, z1 = mz, x2 = mx + half, z2 = mz })
			end
		end
	end
	return out
end

-- Where beginNight puts the character (manor studs).
function Crossing.start(cfg: any, plan: any): (number, number)
	for _, r in plan.rooms do
		if r.id == plan.entranceId then
			return r.gx * cfg.Manor.RoomSize, r.gz * cfg.Manor.RoomSize + START_OFFSET_Z
		end
	end
	return 0, START_OFFSET_Z
end

-- Where the ExitDoor slab stands (manor studs). `exitFace` is passed in so this module needs no require.
function Crossing.exitDoorAt(cfg: any, plan: any, fx: number, fz: number): (number, number)
	for _, r in plan.rooms do
		if r.id == plan.exitId then
			local inset = cfg.Manor.RoomSize / 2 - EXIT_INSET_FROM_FACE
			return r.gx * cfg.Manor.RoomSize + fx * inset, r.gz * cfg.Manor.RoomSize + fz * inset
		end
	end
	return 0, 0
end

-- `M` is the Manor module, passed in: shared modules take their dependencies as arguments (see Night.luau), so the
-- exit face is Manor.exitFace's, not a copy of it.
function Crossing.exitDoor(cfg: any, plan: any, M: any): (number, number)
	local fx, fz = M.exitFace(cfg, plan)
	return Crossing.exitDoorAt(cfg, plan, fx or 0, fz or 1)
end

-- The exit prompt's reach as the guard measures it.
function Crossing.reach(cfg: any): number
	return cfg.Guard.ExitPromptDistance + cfg.Guard.ReachSlack
end

-- Points per doorway gap, 0..GAP_STEPS: the gap is cut into GAP_STEPS pieces of h = DoorWidth / GAP_STEPS studs.
local GAP_STEPS = 10

-- A lower bound on the length of any walk from (sx, sz) to within `reach` of (dx, dz), through the doorways.
--
-- A real walk crosses a sequence of gaps at some points p1, p2, ...; consecutive crossings share a room (the one
-- walked between them), each leg is a straight line or longer, and the walk ENDS in the exit room (the server refuses
-- a press from anywhere else: verdictFor). Each crossing point lies within h/2 of one of the
-- gap's GAP_STEPS + 1 grid points, so a leg between two crossings is at least (grid distance - h), the first leg at
-- least (distance from the start - h/2) and the last at least (distance to the circle - h/2). Dijkstra over the grid
-- points with those shortened legs is therefore never longer than any real walk, and at most about h per gap short of
-- the best one. (A first version measured gap-to-gap as the distance between the two gaps; that is also a lower bound
-- but lets a walk slide along each gap for free, and was up to 29 studs loose on nights 1-150; now 7.)
function Crossing.minDistance(cfg: any, plan: any, sx: number, sz: number, dx: number, dz: number, reach: number): number
	local segs = Crossing.doorways(cfg, plan)
	local h = cfg.Manor.DoorWidth / GAP_STEPS
	local near: { [number]: boolean } = { [plan.exitId] = true } -- the only room a press is accepted from
	local best = math.huge
	if near[plan.entranceId] then
		best = math.max(0, math.sqrt((sx - dx) ^ 2 + (sz - dz) ^ 2) - reach)
	end
	-- grid points: node = (gap, k)
	local nx, nz, ngap = {}, {}, {}
	for i, sg in segs do
		for k = 0, GAP_STEPS do
			local t = k / GAP_STEPS
			table.insert(nx, sg.x1 + (sg.x2 - sg.x1) * t)
			table.insert(nz, sg.z1 + (sg.z2 - sg.z1) * t)
			table.insert(ngap, i)
		end
	end
	local n = #nx
	if n == 0 then return if best == math.huge then 0 else best end
	local dist = table.create(n, math.huge)
	local done = table.create(n, false)
	for v = 1, n do
		local sg = segs[ngap[v]]
		if sg.a == plan.entranceId or sg.b == plan.entranceId then
			dist[v] = math.max(0, math.sqrt((sx - nx[v]) ^ 2 + (sz - nz[v]) ^ 2) - h / 2)
		end
	end
	for _ = 1, n do
		local u, du = 0, math.huge
		for v = 1, n do
			if not done[v] and dist[v] < du then u, du = v, dist[v] end
		end
		if u == 0 or du >= best then break end
		done[u] = true
		local su = segs[ngap[u]]
		if near[su.a] or near[su.b] then
			best = math.min(best, du + math.max(0, math.sqrt((nx[u] - dx) ^ 2 + (nz[u] - dz) ^ 2) - reach - h / 2))
		end
		for v = 1, n do
			-- Two crossings in a row share a room (the one walked between them), and are through DIFFERENT gaps:
			-- stepping back through the same gap and on to the next is never shorter than going straight on (the
			-- triangle inequality), and letting a walk hop along one gap's grid points would slide it along the gap
			-- for free, h at a time (measured: 35 studs loose on night 83 before this rule).
			if not done[v] and ngap[v] ~= ngap[u] then
				local sv = segs[ngap[v]]
				if sv.a == su.a or sv.a == su.b or sv.b == su.a or sv.b == su.b then
					local alt = du + math.max(0, math.sqrt((nx[u] - nx[v]) ^ 2 + (nz[u] - nz[v]) ^ 2) - h)
					if alt < dist[v] then dist[v] = alt end
				end
			end
		end
	end
	-- nothing reaches the door (a broken plan): the guard must not lock the exit forever
	return if best == math.huge then 0 else best
end

-- The least time the night must have run before the exit may open.
function Crossing.minSeconds(cfg: any, plan: any, M: any): number
	local sx, sz = Crossing.start(cfg, plan)
	local dx, dz = Crossing.exitDoor(cfg, plan, M)
	local d = Crossing.minDistance(cfg, plan, sx, sz, dx, dz, Crossing.reach(cfg))
	return math.max(0, d / cfg.Player.WalkSpeed - cfg.Guard.ClockSlack)
end

-- -> ok, why ("far" | "fast" | nil), seconds still to wait (for "fast"). `need` is minSeconds for the night's plan
-- (the server works it out once, when it builds the manor); `dist` is the server's own measure of the character's
-- root to the door; `inExitRoom` is whether that root is in the exit room (Manor.roomAtWorld; the server always
-- passes it, and false is refused); `elapsed` is the night's clock. Reach is judged first: stand at the door, then wait.
function Crossing.verdictFor(cfg: any, need: number, elapsed: number, dist: number, inExitRoom: boolean?): (boolean, string?, number)
	if dist ~= dist or dist > Crossing.reach(cfg) or inExitRoom == false then
		return false, "far", 0
	end
	if elapsed < need then
		return false, "fast", need - elapsed
	end
	return true, nil, 0
end

function Crossing.verdict(cfg: any, plan: any, M: any, elapsed: number, dist: number, inExitRoom: boolean?): (boolean, string?, number)
	return Crossing.verdictFor(cfg, Crossing.minSeconds(cfg, plan, M), elapsed, dist, inExitRoom)
end

return Crossing
