-- Nightwatch Manor — the hazards, through the REAL server and the REAL client.
-- Run: luau check_nightwatchmanor_hazards.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- The rules are unit-tested (Hazards.spec, Nightfall.spec) and their rarity and effect on the chase are
-- measured (Pacing.spec). What only the glue can get wrong, checked here with the hazard interval cut to
-- 6-8 s IN MEMORY (so a check does not need hours of night) on a night-12 player (the Thunderstorm):
--   1. never in the safehouse: a minute of day launches nothing;
--   2. at night a hazard launches on the band's kinds only, one at a time, telegraphed at least 3 s;
--   3. the ring is the danger zone, drawn where the player stands; a player who stays in it is knocked
--      DOWN (PlatformStand) sideways and slower than walking, never up; the knock wears off;
--   4. stepping out of the ring as the warning says, in any of 8 directions, is never a hit;
--   5. the Nightwatcher seeing you calls the hazard off at once (no hit, warning gone) and ends a knock;
--      no hazard launches for QuietAfterSpottedSeconds after it last saw you; but the clock RAN through the
--      chase (review 4: it is held, not frozen), so the hazard that fell due during it comes as soon as the
--      quiet window closes, not a whole remainder later (a frozen clock made hazards come more often per
--      minute in the manor the better a player hid);
--   6. the hazard clock is frozen in the day: a night ended just after a launch resumes, next night,
--      with the remainder of the interval, not with a hazard on the first frame;
--   7. rest is not available at night; the client fires no remote.

local Kit = require("./check_nightwatchmanor_kit")

local ctx = Kit.boot({
	name = "nwm-hazards",
	profile = { night = 12, stash = 0, best = 11, levels = {} },
	beforeClient = function(c)
		c.Config.Hazards.IntervalMin = 6
		c.Config.Hazards.IntervalMax = 8
	end,
})
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local Hz = Config.Hazards
local function mod(name) return h:_require(ctx.RS:FindFirstChild(name)) end
local Nightfall = mod("Nightfall")
local Manor = mod("Manor")
local Rng = mod("Rng")
local bands = Config.Env.Bands
local band = bands[Nightfall.bandIndex(bands, 12)]
truthy(#band.hazards > 0, "CONTROL: night 12's band has hazards (" .. band.id .. ")")

-- what the client shows, polled per frame
local function hazardShown(): (string?, number)
	local kind, n = nil, 0
	local kinds = {}
	for _, d in ctx.folder:GetChildren() do
		local k = string.match(tostring(d.Name), "^Hazard_(%a+)_")
		if k then kinds[k] = true end
	end
	for k in kinds do kind = k; n += 1 end
	return kind, n
end
local function ring(): Instance?
	return ctx.folder:FindFirstChild("HazardZone")
end

local maxAtOnce = 0
local launches = {} -- { kind, at, warnedAt, endedAt, hit }
local cur = nil
local lastWarn = false
ctx.onFrame = function()
	local kind, n = hazardShown()
	maxAtOnce = math.max(maxAtOnce, n)
	if kind and cur == nil then
		cur = { kind = kind, at = ctx.time, warnedAt = if ctx.warning.Visible then ctx.time else nil, hit = false }
		table.insert(launches, cur)
	end
	if cur and cur.warnedAt == nil and ctx.warning.Visible then cur.warnedAt = ctx.time end
	if cur and ctx.hum.PlatformStand == true and not cur.hit then
		cur.hit = true
		cur.hitAt = ctx.time
		cur.vel = ctx.hrp.AssemblyLinearVelocity
	end
	if cur and kind == nil then
		cur.endedAt = ctx.time
		cur = nil
	end
	-- there is no physics here: a knocked character keeps the velocity the client gave it forever unless
	-- something stops it. Roblox's friction does; this stands in for it once the knock has worn off.
	if ctx.hum.PlatformStand ~= true and ctx.hum.MoveDirection.Magnitude < 1e-3 then
		ctx.hrp.AssemblyLinearVelocity = Vector3.zero
	end
	lastWarn = ctx.warning.Visible
	ctx.checkBudget("hazards")
end

--================================================================ 1. never in the safehouse

ctx.seconds(60, 0.1)
eq(#launches, 0, "a minute in the safehouse launches no hazard")
truthy(not ctx.warning.Visible, "and shows no warning")

--================================================================ enter the night; stand where the patrol is not

local plan = Manor.plan(Rng.new(Manor.seedFor(Config, 12)), Config, 12)
ctx.pressDoor()
ctx.seconds(0.3, 0.1)
local manor = ctx.manor()
truthy(manor ~= nil, "night 12 began")
local size = Config.Manor.RoomSize
local cells = {}
local patrolAt = {}
for _, f in manor:GetChildren() do
	local id, kind = string.match(tostring(f.Name), "^Room(%d+)_(.+)$")
	local floor = f:FindFirstChild("Floor")
	if id and floor then
		table.insert(cells, { id = tonumber(id), kind = kind, centre = floor.Position })
		for _, pid in plan.patrol do
			if pid == tonumber(id) then table.insert(patrolAt, floor.Position) end
		end
	end
end
local far, fd = nil, -1
for _, c in cells do
	local d = math.huge
	for _, pp in patrolAt do
		d = math.min(d, (Vector3.new(pp.X, 0, pp.Z) - Vector3.new(c.centre.X, 0, c.centre.Z)).Magnitude)
	end
	if d > fd then far, fd = c, d end
end
print(string.format("  standing in the %s, %.0f studs from the nearest patrol room", far.kind, fd))
local spot = far.centre + Vector3.new(0, 4, 0)
ctx.hrp.CFrame = CFrame.new(spot)

--================================================================ 2 + 3. launch, telegraph, stand still and be hit

local t0 = ctx.time
while #launches == 0 and ctx.time - t0 < 30 do ctx.frame(1 / 30) end
truthy(#launches >= 1, "a hazard launched at night (after " .. string.format("%.1f", ctx.time - t0) .. " s)")
local first = launches[1]
if first then
	local ok = false
	for _, k in band.hazards do if k == first.kind then ok = true end end
	truthy(ok, "it is one of the band's kinds (" .. tostring(first.kind) .. ")")
	truthy(first.warnedAt ~= nil and first.warnedAt - first.at < 0.05, "its warning shows from the frame it launches")
	-- the ring: centred where the player stands (standing still: no lead), as wide as the zone
	local r = ring()
	truthy(r ~= nil and r.Parent ~= nil, "the ring is drawn")
	if r then
		local k = Hz.Kinds[first.kind]
		local want = 2 * (k.hitRadius + Hz.PlayerRadius)
		local off = Vector3.new(r.Position.X - ctx.hrp.Position.X, 0, r.Position.Z - ctx.hrp.Position.Z).Magnitude
		truthy(off < 0.05, string.format("the ring is centred where the player stands (%.3f studs off)", off))
		truthy(math.abs(r.Size.Y - want) < 0.01 and math.abs(r.Size.Z - want) < 0.01, string.format(
			"and exactly as wide as the hit rule (%.2f vs %.2f)", r.Size.Y, want))
		truthy(r.Position.Y < ctx.hrp.Position.Y - 2, "and lies on the floor")
	end
	-- stay put: it must hit
	while cur ~= nil and not first.hit and ctx.time - first.at < 12 do ctx.frame(1 / 30) end
	truthy(first.hit, "a player who stays in the ring is knocked down")
	if first.hit then
		truthy(first.hitAt - first.warnedAt >= Hz.MinTelegraphSeconds - 0.05, string.format(
			"...after at least %.0f s of warning (%.2f s)", Hz.MinTelegraphSeconds, first.hitAt - first.warnedAt))
		local v = first.vel or Vector3.zero
		local hs = Vector3.new(v.X, 0, v.Z).Magnitude
		truthy(hs > 1 and hs < Config.Player.WalkSpeed, string.format(
			"...pushed sideways, and slower than walking (%.1f vs WalkSpeed %d): a knock is never a speed boost", hs, Config.Player.WalkSpeed))
		truthy(math.abs(v.Y) <= 1e-6, "...and never lifted")
		ctx.seconds(Hz.KnockSeconds + 0.2)
		eq(ctx.hum.PlatformStand, false, "the knock wears off after KnockSeconds")
	end
end

--================================================================ 4. step out of the ring: never hit

do
	local dodged, tried = 0, 0
	for dir = 0, 7 do
		ctx.hrp.CFrame = CFrame.new(spot)
		local before = #launches
		local t1 = ctx.time
		while #launches == before and ctx.time - t1 < 30 do ctx.frame(1 / 30) end
		local l = launches[#launches]
		if l and #launches > before then
			tried += 1
			-- wait for the lock (the warning says DODGE), then walk out of the ring at walking speed
			while cur == l and not string.find(ctx.warning.Text, "DODGE", 1, true) and ctx.time - l.at < 6 do ctx.frame(1 / 30) end
			local k = Hz.Kinds[l.kind]
			local need = k.hitRadius + Hz.PlayerRadius + 0.6
			local a = dir * math.pi / 4
			local stepV = Vector3.new(math.cos(a), 0, math.sin(a)) * Config.Player.WalkSpeed
			ctx.hum.MoveDirection = stepV.Unit
			local walked = 0
			while walked < need and cur == l do
				local dt = 1 / 30
				ctx.hrp.CFrame = ctx.hrp.CFrame + stepV * dt
				ctx.hrp.AssemblyLinearVelocity = stepV
				walked += Config.Player.WalkSpeed * dt
				ctx.frame(dt)
			end
			ctx.hum.MoveDirection = Vector3.zero
			ctx.hrp.AssemblyLinearVelocity = Vector3.zero
			while cur == l and ctx.time - l.at < 12 do ctx.frame(1 / 30) end
			if not l.hit then dodged += 1 end
		end
	end
	print(string.format("  dodging: %d of %d hazards dodged by walking out of the ring, one per compass direction", dodged, tried))
	truthy(tried >= 6, "hazards kept coming for the dodge test (" .. tried .. ")")
	eq(dodged, tried, "walking out of the ring in any direction is never a hit")
end
eq(maxAtOnce, 1, "never two hazards at once")

--================================================================ 5. the Nightwatcher sees you: called off

-- A spot the Nightwatcher can see: in front of it, inside ITS room (so walls play no part), as far from it
-- as the room allows (so it sees you well before it can reach its 7-stud catch radius).
local function inItsSight(): CFrame?
	local m = ctx.manor()
	local w = m and m:FindFirstChild("Nightwatcher")
	if not w then return nil end
	local wp = w:GetPivot()
	local roomC = nil
	for _, f in m:GetChildren() do
		local floor = f:FindFirstChild("Floor")
		if floor and math.abs(floor.Position.X - wp.Position.X) <= size / 2 and math.abs(floor.Position.Z - wp.Position.Z) <= size / 2 then
			roomC = floor.Position
		end
	end
	if not roomC then return nil end
	local look = Vector3.new(wp.LookVector.X, 0, wp.LookVector.Z)
	if look.Magnitude < 1e-3 then look = Vector3.new(0, 0, -1) end
	look = look.Unit
	for d = 18, 9, -1 do
		local p = wp.Position + look * d
		if math.abs(p.X - roomC.X) <= size / 2 - 3 and math.abs(p.Z - roomC.Z) <= size / 2 - 3 then
			return CFrame.new(Vector3.new(p.X, spot.Y, p.Z))
		end
	end
	return nil
end

do
	ctx.hrp.CFrame = CFrame.new(spot)
	local before = #launches
	local t1 = ctx.time
	while #launches == before and ctx.time - t1 < 30 do ctx.frame(1 / 30) end
	local l = launches[#launches]
	truthy(l ~= nil and #launches > before and cur == l, "a hazard is in flight")
	-- step in front of the Nightwatcher, in its room, inside its sight cone
	local seenAt = nil
	local t2 = ctx.time
	while seenAt == nil and ctx.time - t2 < 3 do
		local cf = inItsSight()
		if cf then ctx.hrp.CFrame = cf end
		ctx.frame(1 / 30)
		local s = ctx.lastState()
		if s and s.spotted then seenAt = ctx.time end
	end
	truthy(seenAt ~= nil, "CONTROL: the Nightwatcher saw the player (the server pushed spotted)")
	ctx.frame(1 / 30)
	local kind = hazardShown()
	eq(kind, nil, "the moment it sees you, the hazard is called off (its model is gone)")
	eq(ctx.warning.Visible, false, "...and its warning")
	eq(l and l.hit, false, "...and it never hit")
	-- get away: back to the far room, out of its sight
	ctx.hrp.CFrame = CFrame.new(spot)
	local lostAt = nil
	local t3 = ctx.time
	while lostAt == nil and ctx.time - t3 < 5 do
		ctx.frame(1 / 30)
		local s = ctx.lastState()
		if s and not s.spotted then lostAt = ctx.time end
	end
	truthy(lostAt ~= nil, "CONTROL: the player got out of its sight")
	local nextLaunch = nil
	local n0 = #launches
	local t4 = ctx.time
	while nextLaunch == nil and ctx.time - t4 < 40 and ctx.manor() ~= nil do
		ctx.frame(1 / 30)
		if #launches > n0 then nextLaunch = ctx.time end
	end
	truthy(nextLaunch ~= nil, "hazards resume after the chase")
	if nextLaunch and seenAt then
		local since = nextLaunch - (lostAt or seenAt)
		print(string.format("  after the chase: the next hazard came %.2f s after the Nightwatcher lost sight of the player (quiet window %d s)",
			since, Hz.QuietAfterSpottedSeconds))
		truthy(since >= Hz.QuietAfterSpottedSeconds - 0.2, string.format(
			"...but not for QuietAfterSpottedSeconds (%d s) after it last saw you (%.1f s)", Hz.QuietAfterSpottedSeconds, since))
		-- the called-off hazard launched at l.at, so the next one fell due at most IntervalMax (8 s) later, inside the
		-- chase + quiet window. A HELD clock launches it the moment the window closes; a FROZEN one (the rule before
		-- review 4) would still owe the rest of its interval, at least 3 s more.
		local dueBy = (lostAt or seenAt) + Hz.QuietAfterSpottedSeconds - (l and l.at or 0)
		truthy(dueBy >= Hz.IntervalMax, string.format(
			"CONTROL: the next hazard was already due when the quiet window closed (%.1f s after the last launch; interval %d-%d s)",
			dueBy, Hz.IntervalMin, Hz.IntervalMax))
		truthy(since <= Hz.QuietAfterSpottedSeconds + 1.0, string.format(
			"...and then it came at once (%.1f s after it lost you): the clock ran through the chase, held, not frozen", since))
	end
	-- and a knock ends the moment it sees you: stand in the ring, get hit, then be seen. Up to three tries:
	-- the case needs the sighting to land inside the 0.8 s knock.
	local verdict = nil
	for _ = 1, 3 do
		if verdict ~= nil then break end
		local n2 = #launches
		local t6 = ctx.time
		ctx.hrp.CFrame = CFrame.new(spot)
		while #launches == n2 and ctx.time - t6 < 40 and ctx.manor() ~= nil do ctx.frame(1 / 30) end
		local l2 = launches[#launches]
		while l2 and cur == l2 and not l2.hit and ctx.time - l2.at < 12 do ctx.frame(1 / 30) end
		if l2 and l2.hit and ctx.hum.PlatformStand == true then
			local hitAt = ctx.time
			local t5 = ctx.time
			while ctx.time - t5 < 1.5 and verdict == nil do
				local cf = inItsSight()
				if cf then ctx.hrp.CFrame = cf end
				ctx.frame(1 / 30)
				local s = ctx.lastState()
				if s and s.spotted then
					if ctx.time - hitAt < Hz.KnockSeconds - 0.1 then
						-- the push has just arrived; the client's next frame is the first that can act on it
						ctx.frame(1 / 30)
						verdict = ctx.hum.PlatformStand == false and ctx.time - hitAt < Hz.KnockSeconds
					else
						break -- seen only after the knock had worn off anyway: inconclusive, try again
					end
				end
			end
			ctx.hrp.CFrame = CFrame.new(spot)
			ctx.seconds(Hz.QuietAfterSpottedSeconds + 1)
		end
	end
	truthy(verdict ~= nil, "the knock-ends-on-sight case arose in three tries")
	truthy(verdict == true, "a knocked-down player is back on their feet the first frame after it sees them (before KnockSeconds is up)")
end

--================================================================ 6. the clock is frozen in the day

do
	-- end a night 4 s after a launch; the next night's first hazard must wait out the remainder (2-4 s with a
	-- 6-8 s interval). A clock that ran through the day would fire at once (0 s); one that was reset would
	-- wait a whole new interval (6-8 s). The three answers do not overlap.
	ctx.hrp.CFrame = CFrame.new(spot)
	local n0 = #launches
	local t1 = ctx.time
	while #launches == n0 and ctx.time - t1 < 40 and ctx.manor() ~= nil do ctx.frame(1 / 30) end
	truthy(#launches > n0, "a hazard launched before the night was ended")
	ctx.seconds(4)
	ctx.pressExit()
	ctx.seconds(Config.BeatSeconds + 0.5)
	eq((ctx.lastState() or {}).phase, "DAY", "back in the safehouse")
	-- a long rest by the fire
	ctx.restBtn.Activated:Fire()
	ctx.frames(2)
	eq(ctx.hum.Sit, true, "resting in the safehouse sits you down")
	ctx.seconds(90, 0.1)
	local n1 = #launches
	eq(n1, n0 + 1, "ninety seconds of day launched nothing")
	ctx.hrp.CFrame = CFrame.new(ctx.house().Floor.Position + Vector3.new(0, 4, 0))
	ctx.pressDoor()
	-- the server built the night and placed the player in the foyer synchronously; move them to the room
	-- the patrol reaches least BEFORE its first tick, so the watcher's sight plays no part in this timing
	local m2 = ctx.manor()
	if m2 then
		local nightNo = (ctx.lastState() or {}).night or 13
		local plan2 = Manor.plan(Rng.new(Manor.seedFor(Config, nightNo)), Config, nightNo)
		local pat = {}
		local cs = {}
		for _, f in m2:GetChildren() do
			local id = tonumber(string.match(tostring(f.Name), "^Room(%d+)_"))
			local floor = f:FindFirstChild("Floor")
			if id and floor then
				table.insert(cs, floor.Position)
				for _, pid in plan2.patrol do if pid == id then table.insert(pat, floor.Position) end end
			end
		end
		local best, bd = nil, -1
		for _, c in cs do
			local d = math.huge
			for _, pp in pat do d = math.min(d, (Vector3.new(pp.X, 0, pp.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude) end
			if d > bd then best, bd = c, d end
		end
		ctx.hrp.CFrame = CFrame.new(best + Vector3.new(0, 4, 0))
	end
	local start = ctx.time
	-- night time, as the client's clock counts it (review 4: it runs through a chase and only holds the launch;
	-- the day and the beat after a night freeze it). The player stands where the patrol reaches least.
	local open = 0
	local prev = ctx.onFrame
	ctx.onFrame = function(dt)
		prev(dt)
		local s = ctx.lastState() or {}
		if s.phase == "NIGHT" then
			open += dt
		end
	end
	while #launches == n1 and ctx.time - start < 40 do ctx.frame(1 / 30) end
	ctx.onFrame = prev
	local wait = open
	print(string.format("  first hazard of the next night came after %.1f s of night (%.1f s in all; the previous night ended 4 s after a launch; interval %d-%d s)",
		wait, ctx.time - start, Hz.IntervalMin, Hz.IntervalMax))
	truthy(#launches > n1, "the next night has hazards again")
	truthy(wait >= Hz.IntervalMin - 4 - 0.2 and wait <= Hz.IntervalMax - 4 + 0.2, string.format(
		"...after the REMAINDER of the interval (%.1f s): the day froze the clock, it did not run it (0 s) or reset it (%d-%d s)",
		wait, Hz.IntervalMin, Hz.IntervalMax))
end

--================================================================ 7. no rest at night; no remotes

do
	eq(ctx.restBtn.Visible, false, "the rest button is hidden at night")
	ctx.restBtn.Activated:Fire()
	ctx.frames(3)
	eq(ctx.hum.Sit, false, "pressing it anyway sits nobody down inside the manor")
	truthy(string.find(ctx.chip.Text, "Resting", 1, true) == nil, "and the chip never says resting at night")
end

eq(ctx.budgetFails, 0, "every frame stayed inside Config.Budget (" .. tostring(ctx.budgetExample) .. ")")
eq(ctx.serverCalls, 0, "the client never fired a remote")
print(string.format("  %d hazards launched in %.0f s of simulated play", #launches, ctx.time))
ctx.finish("nightwatchmanor hazards")
