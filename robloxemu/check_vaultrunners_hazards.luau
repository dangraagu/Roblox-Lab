-- Vault Runners — the ceiling drops, driven through the REAL client script against the real server.
-- Run (from robloxemu): luau check_vaultrunners_hazards.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- vault-runners/tests/Hazards.spec.luau pins the rule and tests/Pacing.spec.luau measures it on a
-- model of a player. This file checks what only the glue can get wrong:
--   §1  a runner who stands still in the ring is knocked down: the ring is drawn exactly as wide as
--       the rule, centred under their feet; the banner says "keep moving", then "MOVE!"; the knock is
--       PlatformStand + a horizontal push + a capped hop, and it wears off;
--   §2  stepping out of the ring after the lock dodges, in all eight directions, and a runner who
--       never stops is never under a drop when it lands;
--   §3  WHERE a drop may start, through the client: never in the climb shaft, never on a pad, never
--       in a run's first seconds, never in the last seconds before the seal, never with the collapse
--       close — and a drop that came due there is HELD and lands on the first eligible moment;
--   §4  one at a time, only the stratum's own kind, and a run's end takes a drop out of the air;
--   §5  RARITY with the shipped numbers: minutes of real run time, counted.
--   §7  the chunk HANGS from the ceiling and LANDS on the floor, for every kind (it used to come to
--       rest at the height of the runner's root: a slab hovering at chest height for 1.6 s);
--   §6  the client BUDGETS (Config.Budget) on every frame of this file, most of them with a drop in
--       the air: check_vaultrunners_env.luau measures the strata with drops switched off, so the
--       drop's own parts, its trickle emitter and its blinking light are only ever counted here.
--
-- Headless limits: no physics. The knock is observed as the PlatformStand and velocity the client
-- writes; how far a Roblox humanoid actually slides is on EYECANDY.md's Studio list.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and b ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({
	bundle = require("./build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local ME = 4242
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
store:SetAsync("u_" .. ME, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
	floors = { [1] = 1, [2] = 1, [3] = 1 }, escapes = 0, wipes = 0 } })

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local VaultEnv = mod("VaultEnv")
local Progression = mod("Progression")
local VaultFloor = mod("VaultFloor")
local MazeGen = mod("MazeGen")
local Rng = mod("Rng")
local Trace = mod("Trace")
local Hz = Config.Hazards
local bands = Config.Env.Bands
local SHIPPED = { IntervalMin = Hz.IntervalMin, IntervalMax = Hz.IntervalMax }

local remotes = RS:FindFirstChild("VaultRemotes")
local EnterRemote = remotes:FindFirstChild("Enter")

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
-- Mechanics first, with drops every 20-25 s of run time so each one can be watched; the shipped
-- 120-180 s are put back for §5, which counts them.
Hz.IntervalMin = 20
Hz.IntervalMax = 25

local plr = h:join("Runner", ME)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
local function ground()
	hum.FloorMaterial = Enum.Material.Plastic
	hum.MoveDirection = Vector3.new(0, 0, 0)
end
ground()

assert(h:tryRun("client/Hud.client"))
local okVault, errVault = h:tryRun("client/Vault.client")
truthy(okVault, "Vault.client loads (" .. tostring(errVault) .. ")")
local fx = h.workspace:FindFirstChild("VaultRunnersFx")
local gui = plr.PlayerGui:FindFirstChild("VaultFx")
local warning = gui.Root:FindFirstChild("HazardWarning")
local warningText = warning:FindFirstChild("Text")
local vaults = h.workspace:FindFirstChild("Vaults")
local cam = h.workspace.CurrentCamera

--============================================================================ the clock and what it sees

local simT = 0
local spawns = {}          -- { t, kind, where = {runT, storey, fx, fy, onFloor}, ... }
local active = nil         -- the drop in the air, as observed from its parts
local maxAtOnce = 0
local hits = 0
local lastPlatform = false
local runStartedAt = nil
local watch = nil          -- optional per-frame hook

local function ringPart() return fx:FindFirstChild("HazardRing") end

-- The world Y span (lowest, highest) of the drop's own parts, rotation included.
local function extentOf(parts)
	local lo, hi = math.huge, -math.huge
	for _, d in parts do
		local cf, sz = d.CFrame, d.Size
		local half = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
		lo = math.min(lo, cf.Position.Y - half)
		hi = math.max(hi, cf.Position.Y + half)
	end
	return lo, hi
end
local function chunkParts()
	local out = {}
	for _, d in fx:GetChildren() do
		if string.match(d.Name, "^Hazard_[%a]+_") then table.insert(out, d) end
	end
	return out
end

-- §6: every frame, what the client has built, and the peak of each over the whole file
local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0 }
local peakInFlight = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0 }
local framesInFlight, framesMeasured = 0, 0
local function measure(inFlight)
	local m = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0 }
	for _, d in fx:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			m.parts += 1
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate or 0
		elseif cls == "PointLight" and (d.Brightness or 0) > 0 and d.Enabled ~= false then
			m.lights += 1
		elseif cls == "Beam" and d.Enabled ~= false then
			m.beams += 1
		end
	end
	framesMeasured += 1
	if inFlight then framesInFlight += 1 end
	for k, v in m do
		if v > peak[k] then peak[k] = v end
		if inFlight and v > peakInFlight[k] then peakInFlight[k] = v end
	end
end
local function modelsUp()
	local kinds = {}
	for _, d in fx:GetChildren() do
		local k = string.match(d.Name, "^Hazard_([%a]+)_")
		if k then kinds[k] = true end
	end
	return kinds
end

local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simT += dt
	local ring = ringPart()
	local up = modelsUp()
	local n = 0
	for _ in up do n += 1 end
	maxAtOnce = math.max(maxAtOnce, n)
	if ring and not active then
		local k = next(up)
		active = { t = simT, kind = k, ringAt = ring.Position, ringD = ring.Size.Y, root = hrp.Position, runT = runStartedAt and (simT - runStartedAt) or -1 }
		table.insert(spawns, active)
	elseif not ring and active then
		active = nil
	end
	if hum.PlatformStand and not lastPlatform then hits += 1 end
	lastPlatform = hum.PlatformStand
	measure(ring ~= nil)
	if watch then watch() end
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each and each(i) == false then return end
	end
end

--============================================================================ runs

local function myVault() return vaults:FindFirstChild("Vault_" .. ME) end
local function respawn()
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.1)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	ground()
	lastPlatform = false
end
local function modelFor(tier, floor)
	local spec = Progression.difficulty(Config, tier, floor)
	spec.seed = Progression.seedFor(Config, tier, floor)
	return VaultFloor.build(Config, spec, MazeGen, Rng), spec
end

local WALK_H, WALK_UP = Trace.speeds(Config)
WALK_H = WALK_H / Config.Run.TrustedSpeedFactor
WALK_UP = WALK_UP / Config.Run.TrustedClimbFactor
local function walkTo(target)
	for _ = 1, 4000 do
		local cur = hrp.Position
		local dx, dz, dy = target.X - cur.X, target.Z - cur.Z, target.Y - cur.Y
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat < 0.5 and math.abs(dy) < 0.5 then break end
		local mh = math.min(flat, WALK_H * 0.1)
		local nx = if flat > 1e-6 then cur.X + dx / flat * mh else cur.X
		local nz = if flat > 1e-6 then cur.Z + dz / flat * mh else cur.Z
		local ny = cur.Y + (if dy > 0 then math.min(dy, WALK_UP * 0.1) else dy)
		hrp.CFrame = CFrame.new(nx, ny, nz)
		frame(0.1)
	end
end

local cur = nil -- { model, spec, origin, tier }
local function enter(tier)
	if myVault() then respawn() end
	EnterRemote:simulateFireServer(plr, tier)
	h:advance(0.05)
	runStartedAt = simT
	local v = myVault()
	local model, spec = modelFor(tier, 1)
	cur = { model = model, spec = spec, tier = tier, origin = v:FindFirstChild("Floor_0").Position + Vector3.new(0, 1, 0) }
	return cur
end
local function worldAt(s, fx_, fy_)
	local m = cur.model
	return cur.origin + Vector3.new((fx_ - (m.gCols - 1) / 2) * m.cellSize, s * m.storeyHeight + Config.Run.RunnerRootHeight,
		(fy_ - (m.gRows - 1) / 2) * m.cellSize)
end
local function locateMe()
	local lp = hrp.Position - cur.origin
	return VaultEnv.locate(Config, cur.model, { x = lp.X, y = lp.Y, z = lp.Z })
end
-- an open fine cell on storey s where a drop may land, as far from the shaft and the hole as possible
local function eligibleCell(s)
	local m = cur.model
	local best, bestD = nil, -1
	for fy = 1, m.gRows - 2 do
		for fx_ = 1, m.gCols - 2 do
			if m.grids[s + 1][fy][fx_] == false then
				local p = worldAt(s, fx_, fy) - cur.origin
				if VaultEnv.hazardEligible(Config, m, { x = p.X, y = p.Y, z = p.Z }, { elapsed = 60, timeLeft = 100, danger = 0 }) then
					local ex, en = m.exitCells[s + 1], m.entryCells[s + 1]
					local d = math.min(math.max(math.abs(fx_ - (2 * ex.cx + 1)), math.abs(fy - (2 * ex.cy + 1))),
						math.max(math.abs(fx_ - (2 * en.cx + 1)), math.abs(fy - (2 * en.cy + 1))))
					if d > bestD then best, bestD = { fx = fx_, fy = fy }, d end
				end
			end
		end
	end
	return best
end

-- wait for the next drop to appear (or `limit` seconds)
local function nextDrop(limit, dt)
	local before = #spawns
	run(limit, dt or 1 / 30, function() if #spawns > before then return false end end)
	return if #spawns > before then spawns[#spawns] else nil
end

--============================================================================ §1 stand still: knocked down

local volcanoKind = bands[EnvBands.indexAt(bands, VaultEnv.depth(Config, 3, 1))].hazards[1]
do
	enter(3) -- Gold floor 1 is the volcano temple
	local top = cur.model.storeys - 1
	local cell = eligibleCell(top)
	truthy(cell ~= nil, "§1 (the top storey has somewhere a drop may land)")
	walkTo(worldAt(top, cell.fx, cell.fy))
	ground()
	local d = nextDrop(40)
	truthy(d ~= nil, "§1 a drop comes to a runner standing in the open")
	if d then
		eq(d.kind, volcanoKind, "§1 it is the stratum's own kind (" .. tostring(volcanoKind) .. ")")
		local k = Hz.Kinds[volcanoKind]
		near(d.ringD, 2 * (k.hitRadius + Hz.PlayerRadius), 1e-6, "§1 the ring is drawn exactly as wide as the rule (hitRadius + PlayerRadius)")
		local feet = hrp.Position - Vector3.new(0, Config.Run.RunnerRootHeight, 0)
		near((Vector3.new(d.ringAt.X, 0, d.ringAt.Z) - Vector3.new(feet.X, 0, feet.Z)).Magnitude, 0, 0.05, "§1 centred under the runner")
		-- the storey's real floor, not "root minus RunnerRootHeight": walkTo leaves the root up to half a
		-- stud off that, as a real avatar whose root is not at the model's 3 studs would
		local storeyFloor = cur.origin.Y + top * cur.model.storeyHeight
		near(d.ringAt.Y, storeyFloor + 0.08, 0.05, string.format("§1 on the floor of the storey they stand on (root %.2f studs over it)",
			hrp.Position.Y - storeyFloor))
		truthy(warning.Visible and string.find(warningText.Text, "keep moving", 1, true) ~= nil,
			"§1 the banner says keep moving (" .. warningText.Text .. ")")
		local sawMove, sawHit, vel, lift = false, false, nil, nil
		-- §7 through the glue: where the chunk is while it hangs, and once it is down
		local floorY = cur.origin.Y + top * cur.model.storeyHeight
		local ceilingY = floorY + cur.model.wallHeight
		local hangTop, hangLow, restLow = nil, nil, nil
		do
			local lo, hi = extentOf(chunkParts())
			hangTop, hangLow = hi, lo
		end
		local flightT = 0
		run(k.telegraph + 0.5, 1 / 30, function()
			flightT += 1 / 30
			if flightT > k.telegraph + 0.1 and restLow == nil and #chunkParts() > 0 then
				restLow = extentOf(chunkParts())
			end
			if warning.Visible and string.find(warningText.Text, "MOVE!", 1, true) then sawMove = true end
			if hum.PlatformStand and not sawHit then
				sawHit = true
				local v = hrp.AssemblyLinearVelocity
				vel = Vector3.new(v.X, 0, v.Z).Magnitude
				lift = v.Y
			end
		end)
		truthy(sawMove, "§1 then MOVE! once the ring locks")
		near(hangTop, ceilingY, 0.3, string.format("§7 the %s hangs from the ceiling: its top at the ceiling's underside (%.2f studs over the floor, ceiling %.2f)",
			tostring(volcanoKind), (hangTop or 0) - floorY, ceilingY - floorY))
		near(restLow, floorY, 0.25, string.format("§7 and once it lands it lies ON the floor (its lowest point %.2f studs over the floor)",
			(restLow or 0) - floorY))
		truthy(sawHit, "§1 a runner who stood in the ring is knocked down (PlatformStand)")
		near(vel, k.knock, 1e-6, "§1 pushed sideways at the kind's knock")
		near(lift, Hz.KnockLift, 1e-6, "§1 with a small hop, never a launch")
		run(Hz.KnockSeconds + 0.2, 1 / 30)
		eq(hum.PlatformStand, false, "§1 and back on their feet after KnockSeconds")
		run(k.pass + 0.5, 1 / 30)
		eq(ringPart(), nil, "§1 the ring is gone once the drop is done")
		eq(next(modelsUp()), nil, "§1 and so is the chunk")
	end
end

--============================================================================ §2 step out: dodged

do
	local dirs = {}
	for i = 0, 7 do table.insert(dirs, math.rad(i * 45)) end
	local dodged, tried = 0, 0
	local k = Hz.Kinds[volcanoKind]
	for _, a in dirs do
		if myVault() == nil then enter(3); local top = cur.model.storeys - 1; local c = eligibleCell(top); walkTo(worldAt(top, c.fx, c.fy)); ground() end
		local home = hrp.Position
		local d = nextDrop(40)
		if d then
			tried += 1
			local hitsBefore = hits
			local lockedAt = nil
			run(k.telegraph + 0.3, 1 / 30, function()
				if lockedAt == nil and warning.Visible and string.find(warningText.Text, "MOVE!", 1, true) then lockedAt = simT end
				if lockedAt then
					-- walk out at WalkSpeed, straight, in direction a
					local w = math.min(simT - lockedAt, 0.5) * Config.Movement.WalkSpeed
					hrp.CFrame = CFrame.new(home + Vector3.new(math.cos(a) * w, 0, math.sin(a) * w))
				end
			end)
			if hits == hitsBefore then dodged += 1 end
			run(k.pass + 0.5, 1 / 30)
			hrp.CFrame = CFrame.new(home)
			run(0.2, 1 / 30)
		end
	end
	eq(tried, 8, "§2 (eight drops, one per direction)")
	-- every one of those rings was centred under the runner (where they stood, not the jittered landing)
	local offCentre = 0
	for i = #spawns - tried + 1, #spawns do
		local sp = spawns[i]
		local feet = sp.root - Vector3.new(0, Config.Run.RunnerRootHeight, 0)
		offCentre = math.max(offCentre, (Vector3.new(sp.ringAt.X, 0, sp.ringAt.Z) - Vector3.new(feet.X, 0, feet.Z)).Magnitude)
	end
	near(offCentre, 0, 0.05, "§2 every ring was centred under the runner who stood there")
	eq(dodged, tried, string.format("§2 stepping out of the ring after the lock dodges in every direction (%d of %d)", dodged, tried))

	-- a runner who never stops: back and forth across the open storey at 20 studs/s (a fresh run, so
	-- the whole minute and a half is run time)
	respawn()
	enter(3)
	do local top = cur.model.storeys - 1; local c = eligibleCell(top); walkTo(worldAt(top, c.fx, c.fy)); ground() end
	local home = hrp.Position
	local hitsBefore, seen = hits, #spawns
	local phase = 0
	run(90, 1 / 30, function()
		-- round and round a 20-stud circle at 20 studs/s: always moving on, never doubling back
		phase += 1 / 30
		local a = phase * 20 / 20
		hrp.CFrame = CFrame.new(home + Vector3.new(math.cos(a) * 20 - 20, 0, math.sin(a) * 20))
		hum.MoveDirection = Vector3.new(-math.sin(a), 0, math.cos(a))
		if myVault() == nil then return false end
	end)
	ground()
	truthy(#spawns > seen, "§2 (drops came while the runner kept moving: " .. (#spawns - seen) .. ")")
	eq(hits, hitsBefore, "§2 a runner who never stops is never under a drop when it lands")
end

--============================================================================ §3 where a drop may start

do
	respawn()
	local e = enter(3)
	local m = e.model
	-- grace: nothing in the first GraceSeconds even though drops are overdue by now
	local s0 = #spawns
	local firstAt = nil
	watch = function() if #spawns > s0 and firstAt == nil then firstAt = simT - runStartedAt end end
	local cell0 = eligibleCell(0)
	hrp.CFrame = CFrame.new(worldAt(0, cell0.fx, cell0.fy))
	run(Hz.GraceSeconds + 30, 1 / 30)
	watch = nil
	truthy(firstAt ~= nil and firstAt >= Hz.GraceSeconds - 1e-6,
		string.format("§3 no drop in the first %d s of a run (first at %.1f s)", Hz.GraceSeconds, firstAt or -1))
	run(8, 1 / 30) -- let it land
	respawn()

	-- the shaft of storey 3 (high enough that the collapse stays well below for the whole test):
	-- stand in the stairwell cell for 45 s, then on one of its pads for 10 s
	e = enter(3)
	local S3 = 3
	local ex = e.model.exitCells[S3 + 1]
	local shaftAt = worldAt(S3, 2 * ex.cx + 1, 2 * ex.cy + 1)
	walkTo(shaftAt)
	ground()
	local before = #spawns
	run(45, 1 / 30)
	eq(#spawns, before, "§3 45 s standing in the climb shaft: no drop")
	local pad = e.model.shafts[S3 + 1].pads[2]
	hrp.CFrame = CFrame.new(e.origin + Vector3.new(pad.x, pad.y + Config.Run.RunnerRootHeight, pad.z))
	run(10, 1 / 30)
	eq(#spawns, before, "§3 nor standing on a pad of it")
	-- 55 s of run time with drops every 20-25 s: one is overdue. The moment the runner steps back
	-- into the open, the HELD drop comes (not re-rolled into the future, not dropped)
	local open = eligibleCell(S3)
	local steppedAt = simT
	hrp.CFrame = CFrame.new(worldAt(S3, open.fx, open.fy))
	local d = nextDrop(3)
	truthy(d ~= nil and d.t - steppedAt <= 0.1, string.format("§3 the drop that came due in the shaft was held, and starts the moment the runner is in the open (%.2f s later)",
		if d then d.t - steppedAt else -1))
	run(8, 1 / 30)
	respawn()
	local _ = m
end

do
	-- the collapse close behind: stand on storey 0 until it catches you; note the danger at each drop
	local e = enter(3)
	local c = eligibleCell(0)
	hrp.CFrame = CFrame.new(worldAt(0, c.fx, c.fy))
	local worst = -1
	local before = #spawns
	run(200, 1 / 30, function()
		if myVault() == nil then return false end
		if #spawns > before then
			before = #spawns
			local plane = myVault():FindFirstChild("Collapse")
			local lp = hrp.Position - e.origin
			local dgr = VaultEnv.danger(Config, e.model, plane.Position.Y - e.origin.Y, lp.Y)
			worst = math.max(worst, dgr)
		end
	end)
	eq(myVault(), nil, "§3 (the collapse caught the runner who stood on storey 0)")
	truthy(worst <= Hz.MaxDanger + 0.02, string.format("§3 no drop started with the collapse close behind (worst danger at a start: %.2f, limit %.2f)", worst, Hz.MaxDanger))
end

do
	-- the seal: stand at the top until the vault seals; the last drop starts QuietBeforeSealSeconds out
	local e = enter(2) -- Silver 1: a shorter countdown
	local top = e.model.storeys - 1
	local c = eligibleCell(top)
	walkTo(worldAt(top, c.fx, c.fy))
	ground()
	local startInfo = nil
	local sent = remotes:FindFirstChild("Run"):getSent()
	for i = #sent, 1, -1 do if sent[i].args[1] == "start" then startInfo = sent[i].args[2]; break end end
	local before = #spawns
	local lastStart = -1
	run(400, 1 / 15, function()
		if myVault() == nil then return false end
		if #spawns > before then
			before = #spawns
			lastStart = simT - runStartedAt
		end
	end)
	eq(myVault(), nil, "§3 (the vault sealed)")
	truthy(lastStart >= 0, "§3 (drops came during the run)")
	truthy(startInfo ~= nil and lastStart <= startInfo.collapseSeconds - Hz.QuietBeforeSealSeconds + 0.2,
		string.format("§3 the last drop started %.1f s before the seal (limit %d)", (startInfo and startInfo.collapseSeconds or 0) - lastStart, Hz.QuietBeforeSealSeconds))
end

--============================================================================ §4 one at a time, the stratum's kind, and the end of a run

do
	eq(maxAtOnce <= 1, true, "§4 never more than one drop in the air (" .. maxAtOnce .. ")")
	local kinds = {}
	for _, s in spawns do if s.kind then kinds[s.kind] = (kinds[s.kind] or 0) + 1 end end
	local names = {}
	for k2, n in kinds do table.insert(names, k2 .. " x" .. n) end
	print("  drops seen so far: " .. table.concat(names, ", "))
	-- Bronze 1 is the bank: marble only
	respawn()
	local e = enter(1)
	local c = eligibleCell(e.model.storeys - 1) or eligibleCell(0)
	local s = if eligibleCell(e.model.storeys - 1) then e.model.storeys - 1 else 0
	walkTo(worldAt(s, c.fx, c.fy))
	ground()
	local d = nextDrop(40)
	eq(d and d.kind, bands[1].hazards[1], "§4 in the bank vault the ceiling drops marble")
	-- a run ending mid-warning takes the drop out of the air at once
	respawn()
	run(0.1, 1 / 30)
	eq(ringPart(), nil, "§4 a run's end takes a drop out of the air (no ring left in the hub)")
	eq(next(modelsUp()), nil, "§4 and no chunk")
	eq(warning.Visible, false, "§4 and no banner")
end

--============================================================================ §5 rarity, with the shipped numbers

do
	Hz.IntervalMin = SHIPPED.IntervalMin
	Hz.IntervalMax = SHIPPED.IntervalMax
	-- let the drop that was rolled on the short test interval come and go first
	local e = enter(3)
	local top = e.model.storeys - 1
	local c = eligibleCell(top)
	walkTo(worldAt(top, c.fx, c.fy))
	ground()
	nextDrop(60, 0.1)
	run(10, 0.1)
	local startCount, runSeconds, eligibleSeconds = #spawns, 0, 0
	local gaps, lastT = {}, nil
	local startIdx = #spawns
	local runs = 0
	while runSeconds < 30 * 60 do
		if myVault() == nil then
			e = enter(3)
			runs += 1
			top = e.model.storeys - 1
			c = eligibleCell(top)
			walkTo(worldAt(top, c.fx, c.fy))
			ground()
		end
		frame(0.1)
		runSeconds += 0.1
	end
	local n = #spawns - startCount
	for i = startIdx + 2, #spawns do table.insert(gaps, spawns[i].t - spawns[i - 1].t) end
	local perMin = n / (runSeconds / 60)
	print(string.format("  §5 %d drops in %.0f minutes of run time over %d runs = one per %.2f min (shipped interval %d-%d s)",
		n, runSeconds / 60, runs, 1 / math.max(perMin, 1e-9), SHIPPED.IntervalMin, SHIPPED.IntervalMax))
	truthy(n >= math.floor(runSeconds / SHIPPED.IntervalMax) - 3 and n <= math.ceil(runSeconds / SHIPPED.IntervalMin) + 1,
		string.format("§5 about one drop per 2-3 minutes of run time (%d in %.0f min)", n, runSeconds / 60))
	local minGap = math.huge
	for _, g in gaps do minGap = math.min(minGap, g) end
	truthy(#gaps == 0 or minGap >= SHIPPED.IntervalMin - 0.5, string.format("§5 never two within %d s of run time (closest %.1f s)", SHIPPED.IntervalMin, minGap))
	eq(maxAtOnce <= 1, true, "§5 still never more than one at a time")
end

--============================================================================ §7 every kind hangs from the ceiling and lands on the floor

do
	-- VaultArt on its own, in a folder of this file's: a floor at y = 100, a ceiling wallHeight above,
	-- for every kind the config has, hanging (fall 0), half way (0.5) and down (1)
	local VaultArt = mod("VaultArt")
	local folder = Instance.new("Folder")
	folder.Name = "ArtProbe"
	folder.Parent = h.workspace
	local art = VaultArt.new(folder, function() return 0.5 end, Config, EnvBands, VaultEnv)
	local floorY, wallH = 100, Config.Vault.StoreyHeight - Config.Vault.FloorThickness
	local names = {}
	for kind in Hz.Kinds do table.insert(names, kind) end
	table.sort(names)
	local worstHang, worstRest, midOk = 0, 0, true
	for _, kind in names do
		local zone = { centre = Vector3.new(0, floorY, 0), radius = 3 }
		local pos = Vector3.new(0.4, floorY + Config.Run.RunnerRootHeight, -0.3)
		local function span(fall)
			art:showHazard(kind, pos, zone, floorY + wallH, false, fall >= 1, 0, fall)
			local ps = {}
			for _, d in folder:GetChildren() do
				if string.match(d.Name, "^Hazard_" .. kind .. "_") then table.insert(ps, d) end
			end
			return extentOf(ps)
		end
		local hangLo, hangHi = span(0)
		local midLo, midHi = span(0.5)
		local restLo, restHi = span(1)
		worstHang = math.max(worstHang, math.abs(hangHi - (floorY + wallH)))
		worstRest = math.max(worstRest, math.abs(restLo - floorY))
		if not (midLo > restLo and midHi < hangHi) then midOk = false end
		print(string.format("  §7 %-9s hangs %.2f..%.2f, lies %.2f..%.2f (floor %.0f, ceiling %.0f)", kind, hangLo, hangHi, restLo, restHi, floorY, floorY + wallH))
		art:hideHazard(nil)
	end
	truthy(worstHang <= 0.3, string.format("§7 every kind hangs from the ceiling: its top at the ceiling's underside (worst %.2f studs off)", worstHang))
	truthy(worstRest <= 0.25, string.format("§7 every kind lands ON the floor (worst %.2f studs off)", worstRest))
	truthy(midOk, "§7 and half way down it is between the two")
	folder:Destroy()
end

--============================================================================ §6 budgets, with drops in the air

do
	local B = Config.Budget
	print(string.format("  §6 %d frames measured, %d with a drop in the air; peaks (all / in flight): parts %d / %d, emitters %d / %d, %.1f / %.1f particles/s, lights %d / %d, beams %d / %d",
		framesMeasured, framesInFlight, peak.parts, peakInFlight.parts, peak.emitters, peakInFlight.emitters, peak.rate, peakInFlight.rate,
		peak.lights, peakInFlight.lights, peak.beams, peakInFlight.beams))
	truthy(framesInFlight >= 300, "§6 (a drop was in the air on " .. framesInFlight .. " measured frames)")
	truthy(peakInFlight.lights >= 1, "§6 (the drop's blink light was seen lit, so lights are being counted)")
	truthy(peak.parts <= B.MaxLocalParts, string.format("§6 local parts never above %d with drops in the air (peak %d)", B.MaxLocalParts, peak.parts))
	truthy(peak.emitters <= B.MaxEmitters, string.format("§6 emitters never above %d (peak %d)", B.MaxEmitters, peak.emitters))
	truthy(peak.rate <= B.MaxEmitterRate, string.format("§6 particles/s never above %d (peak %.1f)", B.MaxEmitterRate, peak.rate))
	truthy(peak.lights <= B.MaxLights, string.format("§6 lights never above %d (peak %d)", B.MaxLights, peak.lights))
	truthy(peak.beams <= B.MaxBeams, string.format("§6 beams never above %d (peak %d)", B.MaxBeams, peak.beams))
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. tostring(e))
end
local warns = 0
for _, w in h.warnings do
	if string.find(w, "[VaultFx]", 1, true) then warns += 1; print("  warning: " .. w) end
end
eq(warns, 0, "the client never warned")
print(string.format("  drops seen: %d; knock-downs: %d", #spawns, hits))
print(string.format("vault-runners hazards: %d passed, %d failed", passed, failed))
