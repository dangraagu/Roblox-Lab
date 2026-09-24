--!strict
-- Wings.luau — Lost & Found Depot's side of the environment template (EnvBands, Hazards, Rest).
-- Pure, no Roblox. Dependencies arrive as arguments (a bare require("./X") is invalid in Roblox).
--
-- Three things the depot needs that +1 Jump did not:
--
--   PROGRESS. The depot's real progress is the career: shifts completed, plus the share of the RUNNING
--   shift already cleared. Both come from the server's State payload, so the client can only show a
--   wing the server has credited. A wing fades in while the player sorts the last items of the shift
--   before it; the wing is NAMED by whole completed shifts (the "SHIFT n" the HUD shows is n - 1 of them).
--
--   LANES ON A WALLED FLOOR. The template starts a hazard `speed x telegraph` studs away, which in a
--   72 x 56 bay is often behind a wall. clipLane pulls the start in along the lane and slows the hazard
--   so its ARRIVAL TIME (the warning) never shortens; endAtWall ends a flight where it meets a wall.
--
--   A BREAK, NOT A PAUSE. The 5:30 shift clock is the game and lives on the server, which cannot and
--   must not pause it for one player. A break may only START while the clock is not running (the tray is
--   armed, or the summary is up). Pressed mid-shift it is BOOKED for the end of the shift; the first
--   pickup (the server's clock RUNNING again) ends a break in the same frame. Hazards run only while the
--   clock runs, and anything that stops them FREEZES the hazard clock, never resets it. Idle rest (stand
--   still 20 s) is kept from the template for AFK safety: mid-shift it pauses hazards only, the clock is
--   the server's and keeps running. Nothing here talks to the server.

local Wings = {}

local function num(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return x
end

-- Continuous progress from a State payload: completed shifts + share of the running shift cleared.
function Wings.progress(st: any): number
	if type(st) ~= "table" or st.loaded ~= true then
		return 0
	end
	local shifts = math.max(0, num(st.shifts))
	local sh = st.shift
	if type(sh) == "table" and sh.state == "RUNNING" then
		local total = num(sh.total)
		if total > 0 then
			shifts += math.clamp(num(sh.cleared) / total, 0, 1)
		end
	end
	return shifts
end

-- Whole completed shifts: what NAMES the wing (chip, title card, which hazards fly).
function Wings.completedShifts(st: any): number
	if type(st) ~= "table" or st.loaded ~= true then
		return 0
	end
	return math.floor(math.max(0, num(st.shifts)))
end

-- The sorting floor of the bay whose origin is at world x = ox, in world studs (the Back Room corridor
-- behind the door is not part of it).
function Wings.bayRect(cfg: any, ox: number): { minX: number, maxX: number, minZ: number, maxZ: number }
	local B = cfg.Bay
	return { minX = ox + B.MinX, maxX = ox + B.MaxX, minZ = B.MinZ, maxZ = B.MaxZ }
end

function Wings.inRect(rect: any, p: any, margin: number): boolean
	local x, z = p.x, p.z
	if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
		return false
	end
	return x >= rect.minX + margin and x <= rect.maxX - margin and z >= rect.minZ + margin and z <= rect.maxZ - margin
end

-- Distance from `from` along the horizontal unit direction (dx, dz) to the rect shrunk by `margin`.
local function rayToEdge(rect: any, from: any, dx: number, dz: number, margin: number): number
	local best = math.huge
	local lo = { rect.minX + margin, rect.minZ + margin }
	local hi = { rect.maxX - margin, rect.maxZ - margin }
	local o = { from.x, from.z }
	local d = { dx, dz }
	for i = 1, 2 do
		if d[i] > 1e-12 then
			best = math.min(best, (hi[i] - o[i]) / d[i])
		elseif d[i] < -1e-12 then
			best = math.min(best, (lo[i] - o[i]) / d[i])
		end
	end
	return math.max(0, best)
end

-- The bay's collidable fixtures as oriented boxes in world studs, grown by `margin`: the tray, the six
-- crates (each faces the pick point: its width runs across the arc, its depth toward P) and the locker.
-- The spawn pad is left out: it is 1 stud tall and a hazard at root height passes over it.
-- Box = { cx, cz, ax, az (unit width axis), hw, hd, m (the margin it was grown by) }; the depth axis is (-az, ax).
function Wings.obstacles(cfg: any, Layout: any, ox: number, margin: number): { any }
	local B = cfg.Bay
	local out = {}
	table.insert(out, { cx = ox + B.TrayCentre[1], cz = B.TrayCentre[3], ax = 1, az = 0,
		hw = B.TraySize[1] / 2 + margin, hd = B.TraySize[3] / 2 + margin, m = margin })
	for arc = 1, 6 do
		local cx, cz = Layout.binCentre(cfg, arc)
		local len = math.sqrt(cx * cx + cz * cz)
		local ux, uz = -cx / len, -cz / len -- toward P
		-- width axis (uz, -ux), as Layout.binCorners; the depth axis (-az, ax) is then u
		table.insert(out, { cx = ox + cx, cz = cz, ax = uz, az = -ux,
			hw = B.BinSize[1] / 2 + margin, hd = B.BinSize[3] / 2 + margin, m = margin })
	end
	table.insert(out, { cx = ox + B.LockerCentre[1], cz = B.LockerCentre[3], ax = 1, az = 0,
		hw = B.LockerSize[1] / 2 + margin, hd = B.LockerSize[3] / 2 + margin, m = margin })
	return out
end

function Wings.inObstacle(b: any, x: number, z: number): boolean
	local dx, dz = x - b.cx, z - b.cz
	local along = dx * b.ax + dz * b.az
	local across = -dx * b.az + dz * b.ax
	return math.abs(along) <= b.hw and math.abs(across) <= b.hd
end

-- The distance at which a ray (origin o, direction d, both in the box's own frame) enters the box of
-- half-sizes h: 0 when it starts inside, math.huge when it misses.
local function slab(o: { number }, d: { number }, h: { number }): number
	local tmin, tmax = 0, math.huge
	for i = 1, 2 do
		if math.abs(d[i]) < 1e-12 then
			if math.abs(o[i]) > h[i] then return math.huge end
		else
			local t1 = (-h[i] - o[i]) / d[i]
			local t2 = (h[i] - o[i]) / d[i]
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return math.huge end
		end
	end
	return tmin
end

-- Distance along the horizontal unit direction (dx, dz) from `from` to box b (grown by b.m), or math.huge
-- when the ray misses it. A ray that STARTS inside the grown box (a player up against the tray reading its
-- tags, pressed against a crate, or standing on a fixture) is stopped at once (0) when it would enter the
-- fixture itself, and free only where it leads away from it. (Until REVIEW-2 finding 3 such a ray ignored
-- the box altogether, and lanes rolled straight through the tray and its items.)
local function rayToObstacle(b: any, from: any, dx: number, dz: number): number
	local ox, oz = from.x - b.cx, from.z - b.cz
	local o = { ox * b.ax + oz * b.az, -ox * b.az + oz * b.ax }
	local d = { dx * b.ax + dz * b.az, -dx * b.az + dz * b.ax }
	local h = { b.hw, b.hd }
	if math.abs(o[1]) <= h[1] and math.abs(o[2]) <= h[2] then
		local m = b.m or 0
		local core = { math.max(0, b.hw - m), math.max(0, b.hd - m) }
		return if slab(o, d, core) < math.huge then 0 else math.huge
	end
	return slab(o, d, h)
end

local function reachAlong(rect: any, from: any, dx: number, dz: number, margin: number, obstacles: { any }?): number
	local r = rayToEdge(rect, from, dx, dz, margin)
	for _, b in obstacles or {} do
		r = math.min(r, rayToObstacle(b, from, dx, dz))
	end
	return r
end

-- The LEAST lane length any heading in the camera's window allows: yaw is the camera's heading (forward =
-- (sin yaw, 0, cos yaw), as in Hazards.plan) and the window is ± spreadDeg around it. Walls (less
-- `margin`) and obstacles both stop a lane. 0 off the floor.
function Wings.room(rect: any, from: any, yaw: number, spreadDeg: number, margin: number, obstacles: { any }?): number
	if not Wings.inRect(rect, from, margin) then
		return 0
	end
	local least = math.huge
	local steps = math.max(1, math.ceil((2 * spreadDeg) / 5))
	for k = 0, steps do
		local h = yaw + math.rad(-spreadDeg + 2 * spreadDeg * k / steps)
		least = math.min(least, reachAlong(rect, from, math.sin(h), math.cos(h), margin, obstacles))
	end
	return least
end

-- Pull a planned lane's start in along the lane until the whole lane is on the floor (inside the rect
-- shrunk by `margin`) and clear of every obstacle, keeping the arrival time: velocity = (target - start)
-- / arriveAt. Returns the lane length. A lane that is already clear is left alone.
function Wings.clipLane(plan: any, rect: any, margin: number, obstacles: { any }?): number
	local s, t = plan.start, plan.target
	local lx, ly, lz = s.x - t.x, s.y - t.y, s.z - t.z
	local len = math.sqrt(lx * lx + ly * ly + lz * lz)
	local hlen = math.sqrt(lx * lx + lz * lz)
	if len <= 0 or hlen <= 1e-9 then
		return len
	end
	local reach = reachAlong(rect, t, lx / hlen, lz / hlen, margin, obstacles)
	if reach >= hlen then
		return len
	end
	local k = math.clamp(reach / hlen, 0, 1)
	plan.start = { x = t.x + lx * k, y = t.y + ly * k, z = t.z + lz * k }
	local arrive = plan.arriveAt
	plan.velocity = { x = (t.x - plan.start.x) / arrive, y = (t.y - plan.start.y) / arrive, z = (t.z - plan.start.z) / arrive }
	plan.t = 0
	return len * k
end

-- May a DUE hazard launch this frame? Only at a player on their own floor (onFloor), with room for a lane in
-- view (roomy: Wings.room), and while nothing covers the middle of the screen (covered: on a phone an open
-- HUD drawer or card sits exactly where the warning banner and the hazard's marker would be; REVIEW-2
-- finding 2). The caller passes the answer to Hazards.step as `grounded`, which keeps a held hazard DUE with
-- its clock running: a launch is delayed, never skipped. (Holding launches until the player stands still
-- was tried for finding 1 and rejected, measured: a still sorter faces the tray or a crate, so no lane ever
-- has room there, and hazards stopped altogether. Wings.checkHit is what keeps a walker safe.)
function Wings.mayLaunch(ctx: any): boolean
	return ctx.onFloor == true and ctx.roomy == true and ctx.covered ~= true
end

-- Withdraw the hazard just launched (its fitted lane was too short), before anything is drawn. It stays
-- DUE: not skipped and not counted, so withdrawing never thins hazards out. True when it withdrew one.
function Wings.withdraw(sch: any): boolean
	if sch.active == nil then
		return false
	end
	sch.active = nil
	sch.spawned -= 1
	sch.nextAt = sch.clock
	return true
end

-- Lock a lane that has come within its reach + max(extra, speed x react) of the player (true when it
-- locked now). On a small floor a homing hazard can otherwise reach a player before its planned lock, and a
-- fitted lane is slow, so it touches a player standing in the ring well before it "arrives": with `react`
-- a player who stands still always gets that many seconds of RED ring before the knock. Locked, the ring
-- stays where the player stood, so a hit always needs the player to stay inside a red ring
-- (Wings.checkHit). react = nil keeps the plain reach + extra rule.
-- (Locking by the CLOSING speed, so a player walking toward the hazard saw red sooner, was tried for REVIEW-2
-- finding 1 and rejected, measured: the lane stopped following walkers so early that near-hits fell from one
-- per 2.7 minutes to one per 4.2, under the brief. Wings.checkHit is what keeps a walker safe.)
function Wings.lockNear(plan: any, playerPos: any, playerRadius: number, extra: number, react: number?): boolean
	if plan.locked then
		return false
	end
	local p = {
		x = plan.start.x + plan.velocity.x * plan.t,
		y = plan.start.y + plan.velocity.y * plan.t,
		z = plan.start.z + plan.velocity.z * plan.t,
	}
	local v = plan.velocity
	local speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	local margin = math.max(extra, speed * (react or 0))
	local dx, dy, dz = p.x - playerPos.x, p.y - playerPos.y, p.z - playerPos.z
	if math.sqrt(dx * dx + dy * dy + dz * dz) > plan.hitRadius + playerRadius + margin then
		return false
	end
	plan.locked = true
	return true
end

-- When the ring turned red: recorded the first time the lane is seen locked (by lockNear, or by the
-- template's own commit time in Hazards.retarget). Returns it, or nil while the lane still follows.
function Wings.noteLock(plan: any): number?
	if plan.locked and plan.lockedAt == nil then
		plan.lockedAt = plan.t
	end
	return plan.lockedAt
end

-- THE HIT (REVIEW-2 finding 1). A lane starts ahead of the camera, which for a walking sorter is where they
-- are heading, so a walker could meet a hazard well inside a second of the ring turning red (0.13 s,
-- measured), or of the warning appearing (0.40 s). The knock is therefore Hazards.checkHit's ring rule (the
-- player inside the ring AND the hazard passing within reach) under two more conditions, true by
-- construction whatever the player does:
--   * the player has been INSIDE THE RED RING for at least minReact seconds without leaving it: counted from
--     the later of the ring turning red and the player stepping into it (or back into it), so walking into
--     a ring that is already red also leaves a full second to walk out again;
--   * the warning has been up for at least minWarn seconds (the lane launched at plan.t = 0).
-- Only the part of the frame [t0, t1] from that moment on counts: a hazard that passed through a player
-- before then is a near-miss, not a late knock. Call it every frame while the hazard flies (it keeps track
-- of the player's time in the ring on the plan). Hazards is passed in (a bare require is invalid in Roblox).
function Wings.checkHit(Hazards: any, plan: any, t0: number, t1: number, playerPos: any, playerRadius: number, minWarn: number, minReact: number): boolean
	if plan.hit then
		return false
	end
	if Wings.noteLock(plan) == nil or not Hazards.inZone(plan, playerPos, playerRadius) then
		plan.inRedSince = nil
		return false
	end
	plan.inRedSince = plan.inRedSince or t1
	local from = math.max(minWarn, plan.inRedSince + minReact)
	if t1 < from then
		return false
	end
	return Hazards.checkHit(plan, math.max(t0, from), t1, playerPos, playerRadius)
end

-- Is the RING still a danger? A lane fitted to a small floor is slow, so after it arrives the hazard can
-- still cross its ring. True before arrival; after it, while the hazard is within ring radius + hitRadius +
-- playerRadius of the ring's centre (horizontally). Past that it can never touch anyone inside the ring
-- again: after arrival it moves along a straight line away from where it was aimed, so its distance from
-- the ring's centre only grows once it has passed its closest approach, and at arrival it is already inside
-- this bound (the aim jitter is smaller than the ring). The client draws the ring (and the warning) exactly
-- this long, and a sorter who respects the ring waits this long; checkHit needs the player inside it.
function Wings.zoneLive(plan: any, zone: any, playerRadius: number): boolean
	if plan.t <= plan.arriveAt then
		return true
	end
	local px = plan.start.x + plan.velocity.x * plan.t
	local pz = plan.start.z + plan.velocity.z * plan.t
	local dx, dz = px - zone.x, pz - zone.z
	local reach = zone.radius + plan.hitRadius + playerRadius
	return dx * dx + dz * dz <= reach * reach
end

-- A kind that rolls on the floor keeps its lane level: the camera's view window may have bent its start
-- up or down (Hazards.plan clamps the pitch into view). The start moves to the target's height and the
-- arrival time is kept. The client draws the model on the floor.
function Wings.groundLane(plan: any)
	local s, t = plan.start, plan.target
	plan.start = { x = s.x, y = t.y, z = s.z }
	local arrive = plan.arriveAt
	plan.velocity = { x = (t.x - s.x) / arrive, y = 0, z = (t.z - s.z) / arrive }
	plan.t = 0
end

-- After arrival, a hazard whose position has left the floor, or entered a fixture, ends its flight now (Hazards.step then returns
-- "done" on the next frame). True when it ended.
function Wings.endAtWall(plan: any, rect: any, obstacles: { any }?): boolean
	if plan.t <= plan.arriveAt then
		return false
	end
	local p = {
		x = plan.start.x + plan.velocity.x * plan.t,
		y = plan.start.y + plan.velocity.y * plan.t,
		z = plan.start.z + plan.velocity.z * plan.t,
	}
	local blocked = not Wings.inRect(rect, p, 0)
	for _, b in obstacles or {} do
		if blocked then break end
		blocked = Wings.inObstacle(b, p.x, p.z)
	end
	if not blocked then
		return false
	end
	plan.duration = plan.t
	return true
end

-- When the shift clock is not running, a hazard still in the air is taken away (returned so the caller
-- can hide it); nil otherwise. It stays counted and the next one keeps its due time, so ending a shift
-- never changes the rarity. While the clock runs nothing is taken away.
function Wings.endWithShift(sch: any, shiftState: any): any
	if Wings.clockRunning(shiftState) or sch.active == nil then
		return nil
	end
	local plan = sch.active
	sch.active = nil
	return plan
end

--================================================================ scenery: at most two wings

-- A copy of the band weights keeping only the `n` strongest non-zero ones (ties: the lower index wins).
-- Normal play blends two wings at most; this caps what a flurry of career jumps can stack.
function Wings.keepStrongest(weights: { number }, n: number): { number }
	local order = {}
	for i, w in weights do
		if w > 0 then table.insert(order, i) end
	end
	table.sort(order, function(a, b)
		if weights[a] ~= weights[b] then return weights[a] > weights[b] end
		return a < b
	end)
	local out = {}
	for i, w in weights do out[i] = 0 end
	for k = 1, math.min(n, #order) do
		out[order[k]] = weights[order[k]]
	end
	return out
end

--================================================================ the roof never hides the job

-- How much of the OVERHEAD pieces (roofs, lamps, string lights: all above the 16-stud wall tops) to show
-- for a camera at height camY: 1 at or below spec.Full, 0 at or above spec.Gone, smoothstep between. A
-- camera below the walls looks up at the roof; one zoomed out above them would look down THROUGH it at
-- the tags (a CanCollide = false part never pulls the camera in), so there the roof is gone. With every
-- overhead part at or above Gone, no camera that shows the roof can look down at a tag through it.
-- Fails safe: a NaN height or a reversed spec shows nothing overhead.
local DEFAULT_FADE = { Full = 13, Gone = 16 }
function Wings.overheadFade(camY: number, spec: any?): number
	local s = spec or DEFAULT_FADE
	local full, gone = num(s.Full), num(s.Gone)
	if type(camY) ~= "number" or camY ~= camY or gone <= full then
		return 0
	end
	if camY <= full then
		return 1
	end
	if camY >= gone then
		return 0
	end
	local x = (camY - full) / (gone - full)
	return 1 - x * x * (3 - 2 * x)
end

--================================================================ the break

function Wings.clockRunning(shiftState: any): boolean
	return shiftState == "RUNNING"
end

function Wings.newBreak(): { afterShift: boolean }
	return { afterShift = false }
end

-- The BREAK button. Returns "resting" | "queued" | "after_shift" | "stopped" | "cancelled".
function Wings.pressBreak(b: any, rest: any, Rest: any, cfg: any, shiftState: any, ctx: any): string
	if Rest.isResting(rest) or rest.pending then
		return Rest.stop(rest)
	end
	if b.afterShift then
		b.afterShift = false
		return "cancelled"
	end
	if Wings.clockRunning(shiftState) then
		-- the clock is the game: never start a break against it, book it for the end of the shift
		b.afterShift = true
		return "after_shift"
	end
	return Rest.request(rest, cfg, ctx)
end

-- Every frame. Returns nil or "started" | "queued" | "woke" | "dropped" | "expired" | "clock".
function Wings.updateBreak(b: any, rest: any, Rest: any, cfg: any, dt: number, shiftState: any, ctx: any): string?
	if Wings.clockRunning(shiftState) then
		-- a pickup started the clock: a manual break or a pending request ends here, standing still or not
		if (Rest.isResting(rest) and rest.source == "manual") or rest.pending then
			Rest.stop(rest)
			return "clock"
		end
		return Rest.update(rest, cfg, dt, ctx)
	end
	if b.afterShift then
		b.afterShift = false
		if Rest.isResting(rest) then
			Rest.stop(rest) -- an idle rest becomes the booked, manual break
		end
		local r = Rest.request(rest, cfg, ctx)
		return if r == "resting" then "started" else "queued"
	end
	return Rest.update(rest, cfg, dt, ctx)
end

-- Hazards run only while the shift clock runs and the player is not resting.
function Wings.hazardsMayRun(rest: any, Rest: any, shiftState: any): boolean
	return Wings.clockRunning(shiftState) and Rest.hazardsMayRun(rest)
end

return Wings
