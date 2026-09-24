-- SortModel.luau — a sorter walking a real bay, for measuring how often hazards come close. TEST-SIDE ONLY.
--
-- The sorter is design/model.luau's `regular` at stage 3 (Config.Pacing.Sorter): stands at the pick point
-- reading and picking `carry` items, walks each to a bin stand (Layout.binStand, a uniformly random bin),
-- presses Drop, walks back. The camera sits behind them: facing the TRAY (+Z) while reading at the pick
-- point, the way they walk while walking, the crate at a bin. The shift clock runs the whole time (the
-- model is RUNNING time only).
--
-- The hazard side is the game's own code: Hazards.step with the game's Config.Hazards, lanes fitted to
-- the floor and clear of the fixtures with Wings.obstacles / room / mayLaunch / groundLane / clipLane /
-- lockNear / zoneLive / endAtWall, exactly as src/client/Wings.client.luau calls them, and Wings.checkHit
-- for hits (the ring rule, and only after MinReactSeconds inside the red ring and MinWarnSeconds of warning;
-- `spared` counts the passes the plain ring rule would have knocked, which that turned into near-misses).
--
-- Three sorters:
--   "ignores": does the job and never reacts to a warning (walks into hazards, too);
--   "reacts": a human, `Sorter.reactSeconds` late at EVERYTHING: that long after they find themselves inside
--     a RED ring (locked, and live by Wings.zoneLive) they step out (sideways first, radius + 1 stud from the
--     ring's centre, never into a fixture), wait while the ring is still live, walk back and carry on. A red
--     ring ahead, or the hazard itself inside its reach, stops their walk only once it has been in their way
--     for reactSeconds (until REVIEW-2 those two rules had no delay, which made the sorter unhittable);
--   "stands": never moves. Every 30 s they stand somewhere else (the pick point, or a bin stand), facing
--     the pick point. It isolates the geometry: how long a player who stays put gets between the warning,
--     the ring turning red and the knock.
-- A hit costs the stumble (KnockSeconds), a second to get up, and the walk back.
--
-- Plain {x, y, z} tables and a seeded LCG: deterministic, CLI-only.

local SortModel = {}

function SortModel.run(o)
	local cfg, Hz, W, L = o.Config, o.Hazards, o.Wings, o.Layout
	local HzCfg = cfg.Hazards
	local S = cfg.Pacing.Sorter
	local seed = o.seed or 1
	local function rand(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local rect = W.bayRect(cfg, 0)
	local boxes = W.obstacles(cfg, L, 0, HzCfg.ObstacleMargin)
	local ROOT_Y = 3
	local dt = o.dt or (1 / 30)
	local pitch = math.rad(S.cameraPitchDegrees)
	local speed = S.walkSpeed
	local kinds = o.kinds
	local PR = HzCfg.PlayerRadius
	local react = if o.mode == "reacts" then (S.reactSeconds or 0) else 0

	local pos = { x = 0, y = ROOT_Y, z = 0 }
	local yaw = math.pi
	local queue = {}
	local function trip()
		table.insert(queue, { kind = "stand", left = S.carry * (S.decode + S.press), yaw = 0 })
		for _ = 1, S.carry do
			local arc = 1 + math.floor(rand() * 6)
			local sx, sz = L.binStand(cfg, arc)
			local bx, bz = L.binCentre(cfg, arc)
			table.insert(queue, { kind = "walk", to = { x = sx, z = sz } })
			table.insert(queue, { kind = "stand", left = S.press, yaw = math.atan2(bx - sx, bz - sz) })
		end
		table.insert(queue, { kind = "walk", to = { x = 0, z = 0 } })
	end
	-- the "stands" sorter's spots: the pick point facing the arc, each bin stand facing the pick point
	local spots = { { x = 0, z = 0, yaw = math.pi } }
	for arc = 1, 6 do
		local sx, sz = L.binStand(cfg, arc)
		table.insert(spots, { x = sx, z = sz, yaw = math.atan2(-sx, -sz) })
	end
	local spotIdx, spotFor = 1, 0

	local function live(p)
		return W.zoneLive(p, Hz.zone(p, PR), PR)
	end

	local sch = Hz.newScheduler(HzCfg, rand)
	local st = {
		seconds = 0, hazards = 0, hits = 0, near = 0, dodges = 0, lostSeconds = 0, deferredSeconds = 0,
		minLane = math.huge, maxLane = 0, badStarts = 0, shortWarnings = 0, twoAtOnce = 0, closest = {},
	}
	local limit = o.minutes * 60
	while st.seconds < limit do
		st.seconds += dt
		local moving = false
		if o.mode == "stands" then
			spotFor += dt
			if spotFor >= 30 and sch.active == nil then
				spotFor = 0
				spotIdx = spotIdx % #spots + 1
			end
			local sp = spots[spotIdx]
			pos = { x = sp.x, y = ROOT_Y, z = sp.z }
			yaw = sp.yaw
		else
			if #queue == 0 then trip() end
			local a = queue[1]
			if a.kind == "stand" then
				yaw = a.yaw or yaw
				a.left -= dt
				if a.lost then st.lostSeconds += dt end
				if a.left <= 0 then table.remove(queue, 1) end
			elseif a.kind == "wait" then
				if a.lost then st.lostSeconds += dt end
				-- the ring stays red (and drawn) while the hazard can still cross it (Wings.zoneLive)
				if sch.active ~= a.plan or not live(a.plan) then
					table.remove(queue, 1)
				end
			else
				local dx, dz = a.to.x - pos.x, a.to.z - pos.z
				local d = math.sqrt(dx * dx + dz * dz)
				local step = speed * dt
				if a.lost then st.lostSeconds += dt end
				local nextPos = if d <= step then { x = a.to.x, y = ROOT_Y, z = a.to.z }
					else { x = pos.x + dx / d * step, y = ROOT_Y, z = pos.z + dz / d * step }
				local p = sch.active
				local blocked = false
				if o.mode == "reacts" and p ~= nil and not p.hit and a.dodge == nil then
					-- A human reacts to EVERYTHING `react` seconds late (REVIEW-2 finding 1: an earlier model let two
					-- of these rules fire with no delay at all, and so never walked into anything). Each condition
					-- stops them only once it has held for `react` seconds:
					--   a red ring they can see ahead: they do not step into it;
					--   the hazard itself: they do not step toward it inside its reach plus a stud.
					local cRing = p.locked and live(p) and not Hz.inZone(p, pos, PR) and Hz.inZone(p, nextPos, PR)
					local hp = Hz.positionAt(p, p.t)
					local reach = p.hitRadius + PR + 1
					local dNow = math.sqrt((hp.x - pos.x) ^ 2 + (hp.z - pos.z) ^ 2)
					local dNext = math.sqrt((hp.x - nextPos.x) ^ 2 + (hp.z - nextPos.z) ^ 2)
					local cBody = dNext < reach and dNext < dNow
					if cRing then p.ringSince = p.ringSince or st.seconds else p.ringSince = nil end
					if cBody then p.bodySince = p.bodySince or st.seconds else p.bodySince = nil end
					blocked = (cRing and st.seconds - p.ringSince >= react - 1e-9)
						or (cBody and st.seconds - p.bodySince >= react - 1e-9)
				end
				if blocked then
					-- waiting at the ring's edge (the time is counted above when it is lost time)
				elseif d <= step then
					pos = nextPos
					table.remove(queue, 1)
				else
					pos = nextPos
					yaw = math.atan2(dx, dz)
					moving = true
				end
			end
		end

		-- hazards, as the client runs them
		-- the room check only matters on the frame a hazard is due (the client does the same)
		local due = sch.active == nil and sch.clock + dt >= sch.nextAt
		local roomy = not due or W.room(rect, pos, yaw, HzCfg.SpreadDegrees, HzCfg.FloorMargin, boxes) >= HzCfg.MinLaneStuds
		if not roomy then
			st.deferredSeconds += dt
		end
		-- the model sorter plays on a screen nothing covers (a phone drawer holds a launch: Wings.mayLaunch)
		local launchOk = W.mayLaunch({ onFloor = true, roomy = roomy, covered = false })
		local before = if sch.active then sch.active.t else nil
		local ev = Hz.step(sch, HzCfg, dt, {
			resting = false, grounded = launchOk, kinds = kinds,
			aim = { x = pos.x, y = ROOT_Y, z = pos.z }, yaw = yaw, pitch = pitch,
		}, rand)
		if ev and ev.type == "spawn" then
			local plan = ev.plan
			if HzCfg.Kinds[plan.kind].ground then W.groundLane(plan) end
			local len = W.clipLane(plan, rect, HzCfg.FloorMargin, boxes)
			if len < HzCfg.MinLaneStuds then
				W.withdraw(sch)
				st.withdrawn = (st.withdrawn or 0) + 1
				ev = nil
			end
		end
		if ev and ev.type == "spawn" then
			local plan = ev.plan
			local len = Hz.distance(plan.start, plan.target)
			st.hazards += 1
			st.minLane = math.min(st.minLane, len)
			st.maxLane = math.max(st.maxLane, len)
			if not W.inRect(rect, plan.start, HzCfg.FloorMargin - 1e-6) then st.badStarts += 1 end
			if plan.arriveAt < HzCfg.Kinds[plan.kind].telegraph - 1e-9 then st.shortWarnings += 1 end
			plan.minDist = math.huge
			before = nil
		end
		local plan = sch.active
		if plan then
			W.lockNear(plan, pos, PR, HzCfg.LockExtraStuds, HzCfg.MinReactSeconds)
			W.noteLock(plan)
			W.endAtWall(plan, rect, boxes)
			local hp = Hz.positionAt(plan, math.min(plan.t, plan.duration))
			local dx, dy, dz = hp.x - pos.x, hp.y - pos.y, hp.z - pos.z
			plan.minDist = math.min(plan.minDist or math.huge, math.sqrt(dx * dx + dy * dy + dz * dz))
			-- would the plain ring rule have knocked them here? (measured: a pass the promise turned into a near-miss)
			if not plan.hit and not plan.plainWould and Hz.checkHit(plan, before or 0, plan.t, pos, PR) then
				plan.plainWould = true
			end
			if W.checkHit(Hz, plan, before or 0, plan.t, pos, PR, HzCfg.MinWarnSeconds, HzCfg.MinReactSeconds) then
				plan.hit = true
				st.hits += 1
				-- how long the player had: from the first warning (launch), and from the ring turning red
				st.minWarnToHit = math.min(st.minWarnToHit or math.huge, plan.t)
				st.minLockToHit = math.min(st.minLockToHit or math.huge, plan.t - (plan.lockedAt or plan.t))
				if o.mode ~= "stands" then
					local kv = Hz.knockVelocity(HzCfg, plan, pos)
					local back = { x = pos.x, z = pos.z }
					local slide = HzCfg.KnockSeconds * 0.5
					pos = {
						x = math.clamp(pos.x + kv.x * slide, rect.minX + 1.5, rect.maxX - 1.5),
						y = ROOT_Y,
						z = math.clamp(pos.z + kv.z * slide, rect.minZ + 1.5, rect.maxZ - 1.5),
					}
					table.insert(queue, 1, { kind = "walk", to = back, lost = true })
					table.insert(queue, 1, { kind = "stand", left = HzCfg.KnockSeconds + 1.0, lost = true })
				else
					st.lostSeconds += HzCfg.KnockSeconds + 1.0
				end
			end
			local dodging = queue[1] ~= nil and queue[1].dodge == plan
			if o.mode == "reacts" and plan.locked and live(plan) and not plan.hit and not dodging
				and Hz.inZone(plan, pos, PR) then
				-- they notice the red ring under them, and react `react` seconds later
				plan.sawRedAt = plan.sawRedAt or st.seconds
				if st.seconds - plan.sawRedAt >= react - 1e-9 then
					local z = Hz.zone(plan, PR)
					local vx, vz = plan.velocity.x, plan.velocity.z
					local vl = math.sqrt(vx * vx + vz * vz)
					local ux, uz = if vl > 1e-6 then vx / vl else 0, if vl > 1e-6 then vz / vl else 1
					local out = z.radius + 1.0
					local target, best = nil, -1
					-- sideways either way, or back along the lane: whichever clear spot ends farthest from the hazard
					local hp2 = Hz.positionAt(plan, plan.t)
					for _, dir in { { -uz, ux }, { uz, -ux }, { ux, uz } } do
						local c = { x = z.x + dir[1] * out, y = ROOT_Y, z = z.z + dir[2] * out }
						local clear = W.inRect(rect, c, 1.5)
						for _, b in boxes do
							if clear and W.inObstacle(b, c.x, c.z) then clear = false end
						end
						local away = math.sqrt((c.x - hp2.x) ^ 2 + (c.z - hp2.z) ^ 2)
						if clear and away > best then target, best = c, away end
					end
					if target then
						local back = { x = pos.x, z = pos.z }
						st.dodges += 1
						table.insert(queue, 1, { kind = "walk", to = back, lost = true })
						table.insert(queue, 1, { kind = "wait", plan = plan, lost = true })
						table.insert(queue, 1, { kind = "walk", to = { x = target.x, z = target.z }, lost = true, dodge = plan })
					else
						st.cornered = (st.cornered or 0) + 1
					end
				end
			end
		end
		if ev and ev.type == "done" then
			local p = ev.plan
			if p.plainWould and not p.hit then
				st.spared = (st.spared or 0) + 1
			end
			if p.hit or (p.minDist or math.huge) <= HzCfg.NearMissStuds then
				st.near += 1
			end
			table.insert(st.closest, p.minDist or math.huge)
		end
	end
	st.minutes = st.seconds / 60
	return st
end

return SortModel
