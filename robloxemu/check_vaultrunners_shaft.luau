-- Vault Runners — THE SHAFT STAYS READABLE, driven through the REAL client script against the real
-- server. Run (from robloxemu): luau check_vaultrunners_shaft.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- The owner's brief for this game: "crumbling pads must stay readable". EYECANDY.md promises four
-- things for the climb shaft, and before this file no test held any of them:
--   §1  the weather thins to Config.Env.ShaftWeatherScale of its open-floor rate in the stairwell
--       cell and on its pads, and so does the collapse's ceiling dust — but neither vanishes;
--   §2  the collapse's rumble (a camera shake) never fires in the shaft, and does on the open floor;
--   §3  a ceiling drop that was already in the air when the runner stepped into the shaft lands
--       without shaking the camera of a runner on the pads — and the same landing seen from the
--       open floor does shake it (so this file can see a landing shake at all);
--   §4  nothing in the shaft is drawn over the pads: no drop ring, no drop, no ceiling dust host
--       below the ceiling.
--
-- Headless limits: nothing renders, there is no physics. A shake is counted as a call to
-- FxClient.shake (the only camera shake the client has). Whether the shaft LOOKS clear is on
-- EYECANDY.md's Studio list.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local ME = 5151
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
store:SetAsync("u_" .. ME, { data = { gems = 0, totalBanked = 100000, pets = {}, equipped = nil,
	floors = { [1] = 1, [2] = 1, [3] = 1 }, escapes = 0, wipes = 0 } })

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local VaultEnv = mod("VaultEnv")
local Progression = mod("Progression")
local VaultFloor = mod("VaultFloor")
local MazeGen = mod("MazeGen")
local Rng = mod("Rng")
local Trace = mod("Trace")
local FxClient = mod("FxClient")
local Hz = Config.Hazards
local Env = Config.Env

-- Every camera shake the client asks for, with the moment it asked.
local shakes = {}
do
	local real = FxClient.shake
	FxClient.shake = function(...)
		table.insert(shakes, h.scheduler:now())
		return real(...)
	end
end

local remotes = RS:FindFirstChild("VaultRemotes")
local EnterRemote = remotes:FindFirstChild("Enter")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
-- Drops every 20-25 s of run time, set before the client loads (its scheduler rolls the first
-- interval at load). §1 and §2 stand only where a drop may not start (the stairwell, the pads, and
-- storey 0's entry cell), or for less than the run's grace, so no landing shake is counted as a
-- rumble; §3 is where they land.
Hz.IntervalMin = 20
Hz.IntervalMax = 25

local plr = h:join("Climber", ME)
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
local vaults = h.workspace:FindFirstChild("Vaults")
local cam = h.workspace.CurrentCamera

--============================================================================ plumbing

local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each and each(i) == false then return end
	end
end

local function myVault() return vaults:FindFirstChild("Vault_" .. ME) end
local function respawn()
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.1)
	hrp = char:FindFirstChild("HumanoidRootPart")
	hum = char:FindFirstChildOfClass("Humanoid")
	ground()
end

local cur = nil
local function enter(tier)
	if myVault() then respawn() end
	EnterRemote:simulateFireServer(plr, tier)
	h:advance(0.05)
	local v = myVault()
	local spec = Progression.difficulty(Config, tier, 1)
	spec.seed = Progression.seedFor(Config, tier, 1)
	cur = { model = VaultFloor.build(Config, spec, MazeGen, Rng), tier = tier,
		origin = v:FindFirstChild("Floor_0").Position + Vector3.new(0, 1, 0) }
	return cur
end
local function worldAt(s, fx_, fy_)
	local m = cur.model
	return cur.origin + Vector3.new((fx_ - (m.gCols - 1) / 2) * m.cellSize, s * m.storeyHeight + Config.Run.RunnerRootHeight,
		(fy_ - (m.gRows - 1) / 2) * m.cellSize)
end
local function localOf(p)
	local lp = p - cur.origin
	return { x = lp.X, y = lp.Y, z = lp.Z }
end

local WALK_H, WALK_UP = Trace.speeds(Config)
WALK_H = WALK_H / Config.Run.TrustedSpeedFactor
WALK_UP = WALK_UP / Config.Run.TrustedClimbFactor
local function walkTo(target)
	for _ = 1, 4000 do
		local p = hrp.Position
		local dx, dz, dy = target.X - p.X, target.Z - p.Z, target.Y - p.Y
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat < 0.5 and math.abs(dy) < 0.5 then break end
		local mh = math.min(flat, WALK_H * 0.1)
		local nx = if flat > 1e-6 then p.X + dx / flat * mh else p.X
		local nz = if flat > 1e-6 then p.Z + dz / flat * mh else p.Z
		local ny = p.Y + (if dy > 0 then math.min(dy, WALK_UP * 0.1) else dy)
		hrp.CFrame = CFrame.new(nx, ny, nz)
		frame(0.1)
	end
end

-- The stairwell cell of storey s, and the open maze cell beside it that a runner walks in from
-- (through the stairwell's open side, so the walk is one a player could make).
local function shaftAndApproach(s)
	local m = cur.model
	local ex = m.exitCells[s + 1]
	local sx, sy = 2 * ex.cx + 1, 2 * ex.cy + 1
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local cx, cy = sx + d[1], sy + d[2]
		local ax, ay = sx + 2 * d[1], sy + 2 * d[2]
		if m.grids[s + 1][cy] and m.grids[s + 1][cy][cx] == false and m.grids[s + 1][ay] and m.grids[s + 1][ay][ax] == false then
			return { fx = sx, fy = sy }, { fx = ax, fy = ay }
		end
	end
	return { fx = sx, fy = sy }, nil
end

local function weatherRate()
	local r = 0
	for _, d in fx:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled and string.sub(d.Name, 1, 8) == "Weather_" then r += d.Rate end
	end
	return r
end
local function dustRate()
	local host = fx:FindFirstChild("CeilingDust")
	local pe = host and host:FindFirstChild("Dust")
	return if pe and pe.Enabled then pe.Rate else 0
end

--============================================================================ §1 weather and dust thin in the shaft

do
	local e = enter(3) -- Gold floor 1: the volcano temple, embers
	local S = 2 -- storey 2: the collapse stays far below for the whole section
	local shaft, approach = shaftAndApproach(S)
	truthy(approach ~= nil, "§1 (storey 2's stairwell has an open side to walk in from)")
	walkTo(worldAt(S, approach.fx, approach.fy))
	ground()
	run(1, 1 / 30)
	local wOpen, dOpen = weatherRate(), dustRate()
	truthy(not VaultEnv.inShaft(Config, e.model, localOf(hrp.Position)), "§1 (the runner stands in the open, beside the stairwell)")
	truthy(wOpen > 0 and dOpen > 0, string.format("§1 in the open the volcano's weather and the ceiling dust are up (%.2f/s, %.2f/s)", wOpen, dOpen))
	walkTo(worldAt(S, shaft.fx, shaft.fy))
	ground()
	run(0.5, 1 / 30)
	truthy(VaultEnv.inShaft(Config, e.model, localOf(hrp.Position)), "§1 (now in the stairwell cell)")
	local wCell, dCell = weatherRate(), dustRate()
	truthy(wCell <= Env.ShaftWeatherScale * wOpen + 1e-6 and wCell > 0,
		string.format("§1 in the stairwell the weather thins to %.0f%% (%.2f -> %.2f/s), and does not vanish", 100 * Env.ShaftWeatherScale, wOpen, wCell))
	truthy(dCell <= Env.ShaftWeatherScale * dOpen + 1e-6 and dCell > 0,
		string.format("§1 and so does the ceiling dust (%.2f -> %.2f/s)", dOpen, dCell))
	-- up onto pad 3 of this storey's shaft
	local pad = e.model.shafts[S + 1].pads[3]
	hrp.CFrame = CFrame.new(e.origin + Vector3.new(pad.x, pad.y + Config.Run.RunnerRootHeight, pad.z))
	run(0.3, 1 / 30)
	local wPad, dPad = weatherRate(), dustRate()
	truthy(wPad <= Env.ShaftWeatherScale * wOpen + 1e-6, string.format("§1 on a pad the weather stays thin (%.2f/s)", wPad))
	truthy(dPad <= Env.ShaftWeatherScale * dOpen + 1e-6, string.format("§1 and the dust (%.2f/s)", dPad))
	print(string.format("  §1 volcano weather %.2f/s in the open -> %.2f in the stairwell -> %.2f on pad 3; ceiling dust %.2f -> %.2f -> %.2f",
		wOpen, wCell, wPad, dOpen, dCell, dPad))
	-- §4: nothing hangs below the ceiling over the pads
	local host = fx:FindFirstChild("CeilingDust")
	local ceilingY = e.origin.Y + S * e.model.storeyHeight + e.model.wallHeight
	truthy(host == nil or host.Position.Y >= ceilingY - 0.5,
		string.format("§4 the dust host hangs at the ceiling, not over the pads (%.1f vs ceiling %.1f)", host and host.Position.Y or -1, ceilingY))
	-- and back out: the open-floor rate returns
	walkTo(worldAt(S, approach.fx, approach.fy))
	ground()
	run(0.3, 1 / 30)
	truthy(math.abs(weatherRate() - wOpen) <= 1e-6, "§1 stepping back out restores the full weather")
	respawn()
	run(0.5, 1 / 30)
end

--============================================================================ §2 the rumble never shakes the shaft

local function rumbleWhile(where)
	-- Bronze floor 1: the shortest countdown, so the collapse reaches storey 0 inside a minute
	local e = enter(1)
	local shaft = shaftAndApproach(0)
	local spot = if where == "shaft" then worldAt(0, shaft.fx, shaft.fy) else worldAt(0, 2 * e.model.entryCells[1].cx + 1, 2 * e.model.entryCells[1].cy + 1)
	hrp.CFrame = CFrame.new(spot)
	ground()
	local n0 = #shakes
	-- counted only while the run is alive: the HUD shakes the camera when the collapse takes you,
	-- and that death shake is the HUD's business, not the rumble's
	local alive = n0
	local peak = 0
	local inShaftAll = true
	run(120, 1 / 15, function()
		if myVault() == nil then return false end
		alive = #shakes
		local plane = myVault():FindFirstChild("Collapse")
		local lp = localOf(hrp.Position)
		peak = math.max(peak, VaultEnv.danger(Config, e.model, plane.Position.Y - e.origin.Y, lp.y))
		if not VaultEnv.inShaft(Config, e.model, lp) then inShaftAll = false end
	end)
	return alive - n0, peak, inShaftAll
end

do
	local nOpen, peakOpen = rumbleWhile("open")
	truthy(peakOpen > 0.9, string.format("§2 (on the open floor the collapse closed in: danger %.2f)", peakOpen))
	truthy(nOpen >= 1, string.format("§2 on the open floor the collapse rumbles as it closes in (%d shakes)", nOpen))
	local nShaft, peakShaft, allIn = rumbleWhile("shaft")
	truthy(allIn, "§2 (the runner stood in the stairwell the whole time)")
	truthy(peakShaft > 0.9, string.format("§2 (in the shaft the collapse closed in just the same: danger %.2f)", peakShaft))
	eq(nShaft, 0, "§2 but in the shaft it never shakes the camera")
	print(string.format("  §2 rumble as the collapse closes in: %d shakes on the open floor (peak danger %.2f), %d in the stairwell (peak %.2f)",
		nOpen, peakOpen, nShaft, peakShaft))
	respawn()
	run(0.5, 1 / 30)
end

--============================================================================ §3 a drop landing while you climb

local function ring() return fx:FindFirstChild("HazardRing") end

-- Stand beside the stairwell of storey 3 until a drop starts over you, then either step into the
-- stairwell ("shaft") or step half a ring aside in the open ("open"). Returns the shakes counted from
-- the drop's start until after it landed, and whether it landed at all.
local function dropThen(action)
	local e = enter(3)
	local S = 3
	local shaft, approach = shaftAndApproach(S)
	walkTo(worldAt(S, approach.fx, approach.fy))
	ground()
	-- wait for the drop (grace + one interval at most)
	local started = false
	run(Hz.GraceSeconds + Hz.IntervalMax + 5, 1 / 30, function()
		if ring() then started = true; return false end
	end)
	if not started then return -1, false, nil, nil end
	local n0 = #shakes
	local kind = nil
	for _, d in fx:GetChildren() do
		local k = string.match(d.Name, "^Hazard_([%a]+)_")
		if k then kind = k end
	end
	local k = Hz.Kinds[kind]
	if action == "shaft" then
		walkTo(worldAt(S, shaft.fx, shaft.fy))
	else
		-- wait for the lock, then step aside out of the ring (still in the open)
		run(k.telegraph - k.commit + 0.1, 1 / 30)
		hrp.CFrame = hrp.CFrame + (hrp.CFrame.RightVector * (k.hitRadius + Hz.PlayerRadius + 1.5))
	end
	ground()
	local landedAt = nil
	local inShaftAtLanding = nil
	local stood = false
	run(k.telegraph + k.pass + 1, 1 / 30, function()
		-- the landing is the frame the chunk reaches the floor: the ring goes see-through then
		local r = ring()
		if landedAt == nil and r and r.Transparency >= 0.99 then
			landedAt = h.scheduler:now()
			inShaftAtLanding = VaultEnv.inShaft(Config, e.model, localOf(hrp.Position))
		end
		if hum.PlatformStand then stood = true end
	end)
	local n = #shakes - n0
	respawn()
	run(0.5, 1 / 30)
	return n, landedAt ~= nil, inShaftAtLanding, stood
end

do
	local nOpen, landedOpen, _, knockedOpen = dropThen("open")
	truthy(landedOpen, "§3 (a drop landed beside a runner who stepped out of its ring in the open)")
	eq(knockedOpen, false, "§3 (and missed them)")
	truthy(nOpen >= 1, string.format("§3 in the open the landing shakes the camera (%d shakes): this file can see one", nOpen))
	local nShaft, landedShaft, inShaft, knockedShaft = dropThen("shaft")
	truthy(landedShaft, "§3 (a drop that started beside the stairwell landed)")
	eq(inShaft, true, "§3 (the runner was in the shaft when it landed)")
	eq(knockedShaft, false, "§3 (and was not knocked down)")
	eq(nShaft, 0, "§3 a runner in the shaft feels no landing shake: the pads stay steady")
	print(string.format("  §3 a drop's landing: %d camera shake(s) for a runner who stepped aside in the open, %d for one in the shaft", nOpen, nShaft))
end

--============================================================================ §4 nothing drawn over the pads

do
	-- a drop can only be drawn where one may start; stand in the shaft of storey 3 for a minute with
	-- drops every 20-25 s and nothing appears
	local e = enter(3)
	local shaft = shaftAndApproach(3)
	hrp.CFrame = CFrame.new(worldAt(3, shaft.fx, shaft.fy))
	ground()
	local seen = false
	run(Hz.GraceSeconds + 50, 1 / 30, function()
		if ring() then seen = true end
	end)
	eq(seen, false, "§4 a minute in the shaft with drops due: no ring and no chunk over the pads")
	local _ = e
	respawn()
end

--============================================================================ §5 the crack holds until the SERVER drops the pad
--
-- Adversarial review, 2026-09-24: the crack used to run on this client's own clock from its own
-- landing and vanish CrumbleSeconds later, while the server (whose timer starts when its TRUSTED
-- position reaches the pad, ticks every Run.TickSeconds, and replicates the drop back) removed the
-- pad 0.07-0.25 s after that here, where there is no network at all. In between, the pad read WHOLE,
-- or flashed white as if just restored: "safe", at the last moment a jump would still have saved the
-- runner. A pad landed on within 0.45 s of coming back also ended its crack in the "it's back" flash.
--
-- Every frame from the first crack to the server's drop must read as cracking: the crack lines are
-- up and the pad is tinted toward the crack colour, never its whole colour and never the flash. When
-- the pad goes the runner falls (moved to the stairwell floor, as gravity would: nobody can stand
-- where a pad has gone), the pad comes back and flashes, and a runner who lands on it straight away
-- sees a crack again, not the flash.

local EnvBands = mod("EnvBands")
local function crackCount()
	local n = 0
	for _, d in fx:GetChildren() do if d.Name == "PadCrack" then n += 1 end end
	return n
end

local function crackRun(tier, hop)
	local e = enter(tier)
	local pal = VaultEnv.palette(Config, EnvBands, VaultEnv.depth(Config, tier, 1))
	local padC = { pal.pad[1] / 255, pal.pad[2] / 255, pal.pad[3] / 255 }
	local shaft = shaftAndApproach(0)
	local floorSpot = worldAt(0, shaft.fx, shaft.fy)
	walkTo(floorSpot)
	ground()
	run(0.5, 1 / 60)
	local pad = e.model.shafts[1].pads[1]
	local part = myVault():FindFirstChild("Step_0_1")
	local onPad = e.origin + Vector3.new(pad.x, pad.y + Config.Run.RunnerRootHeight, pad.z)
	-- a hop up onto pad 1 at `hop` studs/s, the way the reviewer's probe climbed
	local function hopOn()
		for _ = 1, 600 do
			local p = hrp.Position
			local dx, dz, dy = onPad.X - p.X, onPad.Z - p.Z, onPad.Y - p.Y
			local flat = math.sqrt(dx * dx + dz * dz)
			if flat < 0.05 and math.abs(dy) < 0.05 then break end
			local mh = math.min(flat, 24 / 60)
			hrp.CFrame = CFrame.new(p.X + (if flat > 1e-6 then dx / flat * mh else 0), p.Y + math.clamp(dy, -hop / 60, hop / 60),
				p.Z + (if flat > 1e-6 then dz / flat * mh else 0))
			frame(1 / 60)
		end
	end
	local function look()
		if part.Transparency > 0.5 then return "gone" end
		local c = part.Color
		local lighter = c.G > padC[2] + 2 / 255 or c.B > padC[3] + 2 / 255
		if lighter then return "flash" end
		local whole = math.abs(c.R - padC[1]) <= 1.5 / 255 and math.abs(c.G - padC[2]) <= 1.5 / 255 and math.abs(c.B - padC[3]) <= 1.5 / 255
		if crackCount() > 0 and not whole then return "cracking" end
		if whole then return if crackCount() > 0 then "cracklines on a whole pad" else "whole" end
		return "tinted without cracks"
	end
	-- one landing, until the server drops the pad: every frame after the first crack must be "cracking"
	local function landing()
		local firstCrack, goneAt, bad, badLook, frames, flashes = nil, nil, 0, nil, 0, 0
		local t = 0
		for _ = 1, 60 * 4 do
			frame(1 / 60)
			t += 1 / 60
			local l = look()
			if l == "gone" then goneAt = t; break end
			if l == "cracking" and firstCrack == nil then firstCrack = t end
			if firstCrack then
				frames += 1
				if l ~= "cracking" then bad += 1; badLook = badLook or string.format("%s at %.3f s", l, t) end
				if l == "flash" then flashes += 1 end
			end
		end
		return firstCrack, goneAt, bad, badLook, frames, flashes
	end
	hopOn()
	local c1, g1, bad1, look1, n1 = landing()
	-- it went: the runner falls to the stairwell floor
	hrp.CFrame = CFrame.new(floorSpot)
	ground()
	local sawFlash, backAt = false, nil
	local t = 0
	for _ = 1, 60 * (Config.Ascent.RespawnSeconds + 1) do
		frame(1 / 60)
		t += 1 / 60
		if part.Transparency < 0.5 then
			-- the server brought it back inside this frame's advance, after the client had run: the
			-- client paints it on the next frame
			backAt = backAt or t
			frame(1 / 60)
			if look() == "flash" then sawFlash = true end
			break
		end
	end
	-- straight back up while it is still flashing (the reviewer's second case)
	hopOn()
	local c2, g2, bad2, look2, n2, flashes2 = landing()
	hrp.CFrame = CFrame.new(floorSpot)
	ground()
	run(0.3, 1 / 60)
	return {
		first = { crack = c1, gone = g1, bad = bad1, look = look1, frames = n1 },
		back = backAt ~= nil, flash = sawFlash,
		second = { crack = c2, gone = g2, bad = bad2, look = look2, frames = n2, flashes = flashes2 },
	}
end

do
	for _, case in { { 1, 12 }, { 1, 50 }, { 3, 12 }, { 3, 50 } } do
		local tier, hop = case[1], case[2]
		local label = string.format("§5 %s floor 1, hopping on at %d studs/s", Config.Tiers[tier].name, hop)
		local r = crackRun(tier, hop)
		truthy(r.first.crack ~= nil and r.first.gone ~= nil, label .. ": (the pad cracked, and the SERVER dropped it)")
		eq(r.first.bad, 0, label .. ": from the first crack to the server's drop the pad reads as cracking on every frame ("
			.. r.first.frames .. " frames; first other look: " .. tostring(r.first.look) .. ")")
		truthy(r.back, label .. ": (it came back)")
		truthy(r.flash, label .. ": and flashes as it returns, seen from the floor below")
		truthy(r.second.crack ~= nil and r.second.gone ~= nil, label .. ": (landed on again straight away; the server dropped it again)")
		eq(r.second.bad, 0, label .. ": a pad landed on while it still flashed reads as cracking until it goes ("
			.. r.second.frames .. " frames; first other look: " .. tostring(r.second.look) .. ")")
		eq(r.second.flashes, 0, label .. ": and never shows the 'it's back' flash while it cracks")
		print(string.format("  %s: crack %.3f -> gone %.3f s (%d frames cracking); again: crack %.3f -> gone %.3f s",
			label, r.first.crack or -1, r.first.gone or -1, r.first.frames, r.second.crack or -1, r.second.gone or -1))
		respawn()
		run(0.3, 1 / 30)
	end
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
print(string.format("vault-runners shaft: %d passed, %d failed", passed, failed))
