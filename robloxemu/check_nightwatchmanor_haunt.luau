-- Nightwatch Manor — the nights escalate, through the REAL server and the REAL client.
-- Run: luau check_nightwatchmanor_haunt.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- The pure rules are unit-tested in nightwatch-manor/tests (Nightfall, EnvBands, Hazards, Rest, EnvConfig,
-- Pacing). This file checks the GLUE no unit test can see:
--   §1 the server's lighting IS band 1, so the client's takeover is seamless;
--   §2 the client writes NOTHING in the server's manor and safehouse except the room lights' Brightness, and
--      that only within the flicker floor; the Nightwatcher, the exit, the relics are untouched. In Lighting
--      (review 4: the docs said "only room lights", which was wrong) it writes only the bands' own keys on the
--      Lighting service and on the server's FxAtmosphere / FxBloom / FxColorCorrection, never FxDoF or any
--      other key, and adds exactly one effect of its own (the rest focus);
--   §3 windows stand only on OUTER walls, never on the exit's wall, and always in front of a solid,
--      opaque server wall (closed picture-boxes: nothing is ever seen through them);
--   §4 the portraits' eyes follow the PLAYER, and nothing the Nightwatcher does moves them;
--   §5 everything the client builds is inert (anchored, no collide / query / touch / shadow);
--   §6 the bands advance with SURVIVED NIGHTS only (39 real extractions, a real capture that does not
--      advance), the lighting glides, the chip and the cards follow, and every budget holds every frame;
--   §7 dread escalates the manor within a night (flicker deepens), and never past the floor;
--   §8 the safehouse grows cosier as upgrades are bought on the real pads;
--   §9 the client never fires a remote and the server's remote surface is unchanged.

local Kit = require("./check_nightwatchmanor_kit")

local snapshotDay = nil
local lightingSnap = nil
local ctx = Kit.boot({
	name = "nwm-haunt",
	profile = { night = 1, stash = 40000, best = 0, levels = {} },
	beforeClient = function(c)
		-- a short night so dread can be driven to the top in a few seconds of simulated time (§7);
		-- the server reads Config.Night at the start of every night, so this is a real server night
		c.Config.Night.DreadSeconds = 40
		c.Config.Night.DreadMin = 30
		c.Config.Night.DreadPerNight = 0
		snapshotDay = true
		-- §2 (review 4): Lighting as the server left it, before any client script runs. Every property the emulator
		-- holds, on the service and on each child the server made.
		local L = c.h.Lighting
		lightingSnap = { props = table.clone(L.__emu.props), children = {} }
		for _, ch in L:GetChildren() do
			lightingSnap.children[ch] = { name = ch.Name, props = table.clone(ch.__emu.props) }
		end
	end,
})
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local bands = Config.Env.Bands
local function mod(name) return h:_require(ctx.RS:FindFirstChild(name)) end
local Nightfall = mod("Nightfall")
local Manor = mod("Manor")
local Rng = mod("Rng")

local function rgb255(c: Color3): { number }
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end
local function colorNear(c: Color3, want: { number }, tol: number): boolean
	local r = rgb255(c)
	return math.abs(r[1] - want[1]) <= tol and math.abs(r[2] - want[2]) <= tol and math.abs(r[3] - want[3]) <= tol
end

truthy(snapshotDay, "the check's beforeClient hook ran")
truthy(ctx.folder ~= nil, "the client made its local folder")
truthy(ctx.chip ~= nil and ctx.restBtn ~= nil and ctx.warning ~= nil and ctx.card ~= nil, "chip, rest button, warning and card exist")

--================================================================ §1 band 1 IS the server's preset

do
	local b = bands[1]
	truthy(colorNear(ctx.serverLighting.Ambient, b.lighting.Ambient, 1), "server Ambient == band 1 Ambient")
	truthy(colorNear(ctx.serverLighting.OutdoorAmbient, b.lighting.OutdoorAmbient, 1), "server OutdoorAmbient == band 1")
	eq(ctx.serverLighting.ExposureCompensation, b.lighting.ExposureCompensation, "server ExposureCompensation == band 1")
	eq(ctx.serverLighting.Brightness, b.lighting.Brightness, "server Brightness == band 1")
	local a = ctx.serverAtmosphere
	truthy(a ~= nil, "the server made the atmosphere the client takes over")
	if a then
		eq(a.Density, b.atmosphere.Density, "server atmosphere Density == band 1 (the fog the chase was tuned in)")
		eq(a.Haze, b.atmosphere.Haze, "server Haze == band 1")
		eq(a.Offset, b.atmosphere.Offset, "server Offset == band 1")
		eq(a.Glare, b.atmosphere.Glare, "server Glare == band 1")
		truthy(colorNear(a.Color, b.atmosphere.Color, 1) and colorNear(a.Decay, b.atmosphere.Decay, 1), "server atmosphere colours == band 1")
	end
	local cc = ctx.serverCC
	if cc then
		eq(cc.Brightness, b.colorCorrection.Brightness, "server grade Brightness == band 1")
		eq(cc.Contrast, b.colorCorrection.Contrast, "server Contrast == band 1")
		eq(cc.Saturation, b.colorCorrection.Saturation, "server Saturation == band 1")
		truthy(colorNear(cc.TintColor, b.colorCorrection.TintColor, 1), "server TintColor == band 1")
	end
	local bl = ctx.serverBloom
	if bl then
		eq(bl.Intensity, b.bloom.Intensity, "server bloom Intensity == band 1")
		eq(bl.Size, b.bloom.Size, "server bloom Size == band 1")
		eq(bl.Threshold, b.bloom.Threshold, "server bloom Threshold == band 1")
	end
end

-- budgets, every frame, for the whole run
ctx.onFrame = function()
	local phase = (ctx.lastState() or {}).phase or "?"
	ctx.checkBudget(phase .. " n" .. tostring((ctx.lastState() or {}).night))
end

ctx.seconds(2)
truthy(ctx.chip.Visible, "the chip shows once the profile has loaded")
truthy(string.find(ctx.chip.Text, "Quiet Night", 1, true) ~= nil and string.find(ctx.chip.Text, "Night 1", 1, true) ~= nil,
	"night 1: the chip names the Quiet Night (" .. ctx.chip.Text .. ")")
truthy(ctx.cards[1] ~= nil and string.find(ctx.cards[1], "QUIET NIGHT", 1, true) ~= nil,
	"the first card of the session says where you are, quietly (" .. tostring(ctx.cards[1]) .. ")")

-- The window sky: stars and the eclipse corona, as the band sets them (outside.stars, outside.eclipse). Read off
-- the parts the client parented (the safehouse's two windows by day, the manor's at night).
local function windowSky(): (number, number, number, number, Color3?)
	local stars, opacity, lit, corona, coronaColour = 0, 0, 0, 1, nil
	for _, d in ctx.folder:GetChildren() do
		if d.Name == "WinStar" then
			stars += 1
			opacity += 1 - d.Transparency
			if d.Transparency < 0.99 then lit += 1 end
		elseif d.Name == "WinCorona" then
			corona = math.min(corona, d.Transparency)
			coronaColour = d.Color
		end
	end
	return stars, if stars > 0 then opacity / stars else 0, lit, corona, coronaColour
end
local function checkSky(b: any, where: string)
	local stars, opacity, lit, corona, coronaColour = windowSky()
	truthy(stars > 0, where .. ": the windows have stars to show (" .. stars .. " star parts)")
	-- a star twinkles between 80 % and 100 % of the band's `stars` (transparency 1 - stars * 0.8..1)
	local want = b.outside.stars
	truthy(opacity >= 0.8 * want - 0.03 and opacity <= want + 0.03, string.format(
		"%s: the stars shine as bright as the band says (mean opacity %.2f for stars %.2f)", where, opacity, want))
	if want <= 0 then
		eq(lit, 0, string.format("%s: stars 0 -> not one shows (%d of %d)", where, lit, stars))
	end
	if b.outside.eclipse >= 1 then
		truthy(corona <= 0.3, string.format("%s: the eclipsed moon wears its corona (transparency %.2f)", where, corona))
		truthy(coronaColour ~= nil and colorNear(coronaColour, b.glow.corona, 3), where .. ": in the band's corona colour")
		-- and the moon in front of it is a SOLID disc: a cloud veil would let the pale corona through and turn
		-- the eclipse back into a pale moon (the band is cloudy: outside.cloud 0.8)
		local moonT = 0
		for _, d in ctx.folder:GetChildren() do
			if d.Name == "WinMoon" then moonT = math.max(moonT, d.Transparency) end
		end
		truthy(moonT <= 0.02, string.format("%s: the eclipsed moon is solid, clouds or not (transparency %.2f)", where, moonT))
	else
		truthy(corona >= 0.99, string.format("%s: no corona before the eclipse (transparency %.2f)", where, corona))
	end
end
checkSky(bands[1], "quiet/DAY")

--================================================================ §2-§5 inside the manor

-- A snapshot of everything the server built in this zone, taken before the client has run a frame of night.
local function snapshot(root: Instance)
	local snap = {}
	for _, d in root:GetDescendants() do
		local rec = { cls = d.ClassName, parent = d.Parent, name = d.Name, attrs = {} }
		for k, v in d:GetAttributes() do rec.attrs[k] = v end
		if d:IsA("BasePart") then
			rec.size = d.Size
			rec.cf = d.CFrame
			rec.tr = d.Transparency
			rec.cc = d.CanCollide
			rec.cq = d.CanQuery
			rec.ct = d.CanTouch
			rec.col = d.Color
			rec.mat = d.Material
		elseif d.ClassName == "PointLight" then
			rec.bright = d.Brightness
			rec.col = d.Color
			rec.range = d.Range
			rec.en = d.Enabled
		end
		snap[d] = rec
	end
	return snap
end

ctx.pressDoor()
h:advance(0.2) -- the server builds the night; no client frame has run yet
local manor = ctx.manor()
truthy(manor ~= nil, "the manor door built a manor")
local snap = snapshot(ctx.zone())
local watcher = manor:FindFirstChild("Nightwatcher")
truthy(watcher ~= nil, "the Nightwatcher stands in the manor")

-- the fairness rule is pinned to the monster it protects: its lights are exactly the signature
do
	local head = watcher:FindFirstChild("Head")
	local lamp = watcher:FindFirstChild("Lamp")
	local hl = head and head:FindFirstChild("PL")
	local ll = lamp and lamp:FindFirstChild("PL")
	truthy(hl ~= nil and ll ~= nil, "the Nightwatcher has its two lights")
	local sig = Config.Env.WatcherSignature
	truthy(hl and colorNear(hl.Color, sig[1], 1), "Config.Env.WatcherSignature[1] IS the built head light's colour")
	truthy(ll and colorNear(ll.Color, sig[2], 1), "Config.Env.WatcherSignature[2] IS the built lamp's colour")
end

-- review 4: the way out is protected by the same rule, pinned the same way to what the server builds
do
	local exitSig = Config.Env.ExitSignature
	truthy(type(exitSig) == "table" and exitSig[1] ~= nil, "Config.Env.ExitSignature is set")
	local door = manor:FindFirstChild("ExitDoor")
	local dl = door and door:FindFirstChild("PL")
	local lamp = nil
	for _, d in manor:GetDescendants() do
		if d.Name == "ExitLamp" then lamp = d end
	end
	local ll = lamp and lamp:FindFirstChild("PL")
	local want = exitSig and exitSig[1] or { -999, -999, -999 }
	truthy(dl ~= nil and colorNear(dl.Color, want, 1), "Config.Env.ExitSignature[1] IS the built exit door's light")
	truthy(lamp ~= nil and colorNear(lamp.Color, want, 1), "...and the built ExitLamp's glow")
	truthy(ll ~= nil and colorNear(ll.Color, want, 1), "...and the ExitLamp's light")
end

-- the rooms, as the server built them (floor cells), and the patrol the check may know
local plan = Manor.plan(Rng.new(Manor.seedFor(Config, 1)), Config, 1)
local size = Config.Manor.RoomSize
local cells, byKey = {}, {}
for _, f in manor:GetChildren() do
	local kind = string.match(tostring(f.Name), "^Room%d+_(.+)$")
	local floor = kind and f:FindFirstChild("Floor")
	if floor then
		local c = { gx = math.floor(floor.Position.X / size + 0.5), gz = math.floor(floor.Position.Z / size + 0.5), centre = floor.Position, kind = kind, folder = f }
		table.insert(cells, c)
		byKey[c.gx .. "," .. c.gz] = c
	end
end
truthy(#cells >= 6, "the manor has its rooms (" .. #cells .. ")")

-- walk the player through every room (teleport + a few frames each), recording every window shown
local windowsSeen = {}
local maxShown = 0
local lightRatio = { lo = math.huge, hi = -math.huge }
local flickered = {}
local function scanFrame()
	local shown = 0
	for _, d in ctx.folder:GetChildren() do
		if d.Name == "WinSky" then
			shown += 1
			windowsSeen[tostring(math.round(d.Position.X)) .. "," .. tostring(math.round(d.Position.Z))] = d
		end
	end
	maxShown = math.max(maxShown, shown)
	for inst, rec in snap do
		if inst.ClassName == "PointLight" and inst.Parent ~= nil and rec.bright and rec.bright > 0 then
			local r = inst.Brightness / rec.bright
			if math.abs(r - 1) > 1e-6 then
				flickered[inst] = true
				lightRatio.lo = math.min(lightRatio.lo, r)
				lightRatio.hi = math.max(lightRatio.hi, r)
			end
		end
	end
end
-- the watcher must not catch the tour: stay out of its room and the rooms next to it
local function safeFrom(c: any): boolean
	local wx, wz = watcher:GetPivot().Position.X, watcher:GetPivot().Position.Z
	return (Vector3.new(wx, 0, wz) - Vector3.new(c.centre.X, 0, c.centre.Z)).Magnitude > size * 1.6
end
local toured = 0
for _, c in cells do
	if safeFrom(c) and ctx.manor() ~= nil then
		ctx.hrp.CFrame = CFrame.new(c.centre + Vector3.new(0, 4, 0))
		for _ = 1, 12 do
			ctx.frame(1 / 30)
			scanFrame()
		end
		toured += 1
	end
end
truthy(toured >= 3, "the tour visited rooms (" .. toured .. ")")
truthy(ctx.manor() ~= nil, "CONTROL: the tour ended with the night still running (nobody was caught)")

-- The player's tour skips the rooms near the Nightwatcher, and on night 1 it STARTS in the Servants' Exit, so the
-- exit's own walls were never in view (a window built on the exit's wall survived every gate this way). Windows are
-- chosen by distance to the CAMERA, and the Nightwatcher only reacts to the character, so the camera alone now
-- visits every room while the player stays where the tour left them.
local exitCellKey = nil
do
	local door = manor:FindFirstChild("ExitDoor")
	if door then
		local best, bd = nil, nil
		for _, c in cells do
			local d = (c.centre - door.Position).Magnitude
			if bd == nil or d < bd then best, bd = c, d end
		end
		exitCellKey = best and (best.gx .. "," .. best.gz)
	end
	local keepPlace = ctx.placeCamera
	local camVisits, exitVisited = 0, false
	for _, c in cells do
		if ctx.manor() == nil then break end
		ctx.placeCamera = function()
			ctx.cam.CFrame = CFrame.lookAt(c.centre + Vector3.new(0, 6, 0), c.centre + Vector3.new(1, 6, 0))
		end
		for _ = 1, 10 do
			ctx.frame(1 / 30)
			scanFrame()
		end
		camVisits += 1
		if (c.gx .. "," .. c.gz) == exitCellKey then exitVisited = true end
	end
	ctx.placeCamera = keepPlace
	eq(camVisits, #cells, "the camera visited every room of the manor")
	truthy(exitVisited, "CONTROL: including the Servants' Exit (" .. tostring(exitCellKey) .. ")")
	truthy(ctx.manor() ~= nil, "CONTROL: and the night is still running")
end

-- §3 windows
do
	local nWin, outer, notExit, solid = 0, 0, 0, 0
	local exitDoor = manor:FindFirstChild("ExitDoor")
	local exitFaceKey = nil
	if exitDoor then
		local best, bd
		for _, c in cells do
			local d = (c.centre - exitDoor.Position).Magnitude
			if bd == nil or d < bd then best, bd = c, d end
		end
		local off = exitDoor.Position - best.centre
		local dx = if math.abs(off.X) > math.abs(off.Z) then (if off.X > 0 then 1 else -1) else 0
		local dz = if dx == 0 then (if off.Z > 0 then 1 else -1) else 0
		exitFaceKey = best.gx .. "," .. best.gz .. "," .. dx .. "," .. dz
	end
	for _, sky in windowsSeen do
		nWin += 1
		local p = sky.Position
		local c = byKey[math.floor(p.X / size + 0.5) .. "," .. math.floor(p.Z / size + 0.5)]
		if c then
			local off = p - c.centre
			local dx = if math.abs(off.X) > math.abs(off.Z) then (if off.X > 0 then 1 else -1) else 0
			local dz = if dx == 0 then (if off.Z > 0 then 1 else -1) else 0
			if byKey[(c.gx + dx) .. "," .. (c.gz + dz)] == nil then outer += 1 end
			if (c.gx .. "," .. c.gz .. "," .. dx .. "," .. dz) ~= exitFaceKey then notExit += 1 end
			-- a solid, opaque, colliding server wall covers the point just behind the window
			local behind = p + Vector3.new(dx, 0, dz) * 0.6
			for _, d in c.folder:GetDescendants() do
				if d:IsA("BasePart") and string.match(tostring(d.Name), "^Wall") then
					local o = behind - d.Position
					if math.abs(o.X) <= d.Size.X / 2 + 0.01 and math.abs(o.Y) <= d.Size.Y / 2 + 0.01 and math.abs(o.Z) <= d.Size.Z / 2 + 0.01
						and d.Transparency == 0 and d.CanCollide == true then
						solid += 1
						break
					end
				end
			end
		end
	end
	print(string.format("  windows: %d distinct windows seen on the tour; at most %d parented at once", nWin, maxShown))
	truthy(nWin >= 3, "the tour saw windows (" .. nWin .. ")")
	eq(outer, nWin, "every window is on an OUTER wall (no room behind it)")
	eq(notExit, nWin, "no window is on the Servants' Exit's wall")
	eq(solid, nWin, "every window is a closed box in front of a solid, opaque server wall: nothing is seen through it")
	truthy(maxShown <= Config.Budget.MaxWindowsShown, string.format("at most MaxWindowsShown windows at once (%d <= %d)", maxShown, Config.Budget.MaxWindowsShown))
	-- the manor's windows carry the same sky: stand in front of one and read its stars
	local any = nil
	for _, sky in windowsSeen do any = sky break end
	if any then
		local c = byKey[math.floor(any.Position.X / size + 0.5) .. "," .. math.floor(any.Position.Z / size + 0.5)]
		if c and safeFrom(c) then
			ctx.hrp.CFrame = CFrame.new(Vector3.new(c.centre.X, c.centre.Y + 4, c.centre.Z))
			ctx.frames(12)
			checkSky(bands[1], "quiet/NIGHT (a manor window)")
		end
	end
end

-- §4 portraits follow YOU, and nothing the Nightwatcher does moves them
do
	local hall = nil
	for _, c in cells do
		if c.kind == "hall" then hall = c end
	end
	if hall == nil then
		print("  (no Portrait Hall on night 1's manor; portraits are checked on a later night below)")
	else
		ctx.hrp.CFrame = CFrame.new(hall.centre + Vector3.new(0, 4, 8))
		ctx.frames(12)
		-- THIS hall's pupils only: another Portrait Hall next door can be in range too, and its portraits are
		-- 40 studs up the axis the player walks along here, where a pupil barely moves
		local pupils = {}
		for _, d in ctx.folder:GetChildren() do
			if d.Name == "PortraitPupil" and math.abs(d.Position.X - hall.centre.X) <= size / 2 + 1
				and math.abs(d.Position.Z - hall.centre.Z) <= size / 2 + 1 then
				table.insert(pupils, d)
			end
		end
		truthy(#pupils >= 2, "the hall's portraits have eyes (" .. #pupils .. " pupils)")
		if #pupils > 0 then
			local p0 = pupils[1].Position
			ctx.hrp.CFrame = CFrame.new(hall.centre + Vector3.new(0, 4, 16))
			ctx.frames(3)
			local pA = pupils[1].Position
			ctx.hrp.CFrame = CFrame.new(hall.centre + Vector3.new(0, 4, -16))
			ctx.frames(3)
			local pB = pupils[1].Position
			truthy(pA.Z > pB.Z + 0.05, string.format("a pupil slides toward the player: +Z when you stand at +Z (%.3f vs %.3f)", pA.Z, pB.Z))
			local _ = p0
			-- the Nightwatcher walks; the player does not: the pupils stay exactly where they are
			local before = {}
			for i, pu in pupils do before[i] = pu.Position end
			local w0 = watcher:GetPivot().Position
			ctx.frames(20)
			local w1 = watcher:GetPivot().Position
			local still = true
			for i, pu in pupils do
				if (pu.Position - before[i]).Magnitude > 1e-6 then still = false end
			end
			truthy((w1 - w0).Magnitude > 0.5, "CONTROL: the Nightwatcher moved meanwhile")
			truthy(still, "...and no pupil moved: the eyes follow you, never it")
		end
	end
end

-- §2 the server's world is untouched, apart from room-light Brightness inside the floor
do
	local changed, lightOnly, example = 0, 0, nil
	local FLICKERABLE = { Fixture = true, FoyerFlame = true, Candelabra = true }
	for inst, rec in snap do
		local diffs = {}
		if inst.Parent ~= rec.parent then table.insert(diffs, "Parent") end
		if inst.Name ~= rec.name then table.insert(diffs, "Name") end
		for k, v in rec.attrs do
			if inst:GetAttribute(k) ~= v then table.insert(diffs, "attr " .. k) end
		end
		for k in inst:GetAttributes() do
			if rec.attrs[k] == nil then table.insert(diffs, "new attr " .. k) end
		end
		if rec.size then
			local isWatcher = inst:IsDescendantOf(watcher)
			if inst.Size ~= rec.size then table.insert(diffs, "Size") end
			if inst.CFrame ~= rec.cf and not isWatcher then table.insert(diffs, "CFrame") end
			if inst.Transparency ~= rec.tr then table.insert(diffs, "Transparency") end
			if inst.CanCollide ~= rec.cc or inst.CanQuery ~= rec.cq or inst.CanTouch ~= rec.ct then table.insert(diffs, "Can*") end
			if inst.Color ~= rec.col then table.insert(diffs, "Color") end
			if inst.Material ~= rec.mat then table.insert(diffs, "Material") end
		elseif rec.bright then
			if inst.Color ~= rec.col or inst.Range ~= rec.range or inst.Enabled ~= rec.en then table.insert(diffs, "light colour/range/enabled") end
			if inst.Brightness ~= rec.bright then
				local host = inst.Parent
				if host and FLICKERABLE[host.Name] and not inst:IsDescendantOf(watcher) then
					lightOnly += 1
				else
					table.insert(diffs, "Brightness of " .. (host and host.Name or "?"))
				end
			end
		end
		if #diffs > 0 then
			changed += 1
			example = example or (inst:GetFullName() .. ": " .. table.concat(diffs, ", "))
		end
	end
	print(string.format("  server-built instances: %d snapshotted, %d changed by the client (%s); %d room lights flickered",
		(function() local n = 0 for _ in snap do n += 1 end return n end)(), changed, tostring(example), lightOnly))
	eq(changed, 0, "the client changed NOTHING the server built except room-light Brightness (" .. tostring(example) .. ")")
	truthy(lightOnly > 0, "CONTROL: room lights really do flicker")
	truthy(lightRatio.lo >= Nightfall.HARD.FlickerMin - 1e-6 and lightRatio.lo >= 1 - Config.Env.FlickerAmp - 1e-6, string.format(
		"no flickering light ever dropped below the floor (lowest %.3f of what the server built)", lightRatio.lo))
	truthy(lightRatio.hi <= 1 + Config.Env.FlickerAmp + 1e-6, string.format("nor flared past 1 + FlickerAmp (highest %.3f)", lightRatio.hi))
	for inst in flickered do
		local host = inst.Parent
		truthy(host ~= nil and FLICKERABLE[host.Name] == true, "only room lights flicker (" .. tostring(host and host.Name) .. ")")
		break
	end
end

-- §5 everything the client built is inert
do
	local bad, total, example = 0, 0, nil
	for _, d in ctx.folder:GetDescendants() do
		if d:IsA("BasePart") then
			total += 1
			if not (d.Anchored and d.CanCollide == false and d.CanQuery == false and d.CanTouch == false and d.CastShadow == false) then
				bad += 1
				example = example or d.Name
			end
		end
	end
	truthy(total > 0, "CONTROL: the client built parts (" .. total .. ")")
	eq(bad, 0, "every client part is anchored and cannot collide, be queried, be touched or cast a shadow (" .. tostring(example) .. ")")
	local stray = 0
	for _, d in h.workspace:GetChildren() do
		if d.Name ~= "NightwatchLocal" and d.Name ~= "NightwatchOrigin" and not string.match(tostring(d.Name), "^Zone_")
			and d.ClassName ~= "Camera" and d.ClassName ~= "Terrain" and d ~= ctx.char then
			stray += 1
			print("  stray workspace child: " .. d:GetFullName())
		end
	end
	eq(stray, 0, "the client put nothing in the workspace outside its own folder")
end

--================================================================ §7 dread escalates the manor

do
	-- stand in the room furthest from the patrol (the check may know the plan), and let the short night run up
	local patrolAt = {}
	for _, id in plan.patrol do
		for _, f in manor:GetChildren() do
			if string.match(tostring(f.Name), "^Room" .. id .. "_") and f:FindFirstChild("Floor") then
				table.insert(patrolAt, f.Floor.Position)
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
	local function range(seconds: number)
		local lo, hi = math.huge, -math.huge
		local n = math.floor(seconds * 30)
		for _ = 1, n do
			ctx.frame(1 / 30)
			for inst, rec in snap do
				if inst.ClassName == "PointLight" and inst.Parent ~= nil and inst.Parent.Name == "Fixture" and rec.bright then
					local r = inst.Brightness / rec.bright
					lo, hi = math.min(lo, r), math.max(hi, r)
				end
			end
		end
		return hi - lo, (ctx.lastState() or {}).dread or -1
	end
	print(string.format("  dread run: standing in %s, %.0f studs from the nearest patrol room", far.kind, fd))
	ctx.hrp.CFrame = CFrame.new(far.centre + Vector3.new(0, 4, 0))
	local early, d0 = range(3)
	-- run the night up to high dread
	local waited = 0
	while ctx.manor() ~= nil and ((ctx.lastState() or {}).dread or 0) < 0.8 and waited < 60 do
		ctx.frame(0.1)
		waited += 0.1
	end
	local late, d1 = range(3)
	print(string.format("  flicker range: %.3f at dread %.2f, %.3f at dread %.2f", early, d0, late, d1))
	if ctx.manor() ~= nil and d1 > d0 + 0.4 then
		truthy(late > early + 0.02, string.format("as the manor wakes (dread %.2f -> %.2f) its lights flicker harder (%.3f -> %.3f)", d0, d1, early, late))
	else
		truthy(false, "the dread run reached high dread without the night ending (got dread " .. tostring(d1) .. ")")
	end
	-- let the night end on its own (evicted at dread 1) or leave
	ctx.pressExit()
	ctx.seconds(Config.BeatSeconds + 0.6)
end
-- give back the normal night length for the band run (the server reads it at the next night's start)
Config.Night.DreadSeconds = 210
Config.Night.DreadMin = 110
Config.Night.DreadPerNight = -3

--================================================================ §6 the bands advance with survived nights

do
	local st = ctx.lastState()
	truthy(st and st.phase == "DAY", "back in the safehouse after the night")
	local night0 = st and st.night or 1

	-- a capture does not advance the night, and so does not advance the band
	ctx.pressDoor()
	ctx.seconds(0.4)
	local w = ctx.manor() and ctx.manor():FindFirstChild("Nightwatcher")
	if w then
		ctx.hrp.CFrame = CFrame.new(w:GetPivot().Position + Vector3.new(0, 1, 0))
		ctx.seconds(0.5)
	end
	ctx.seconds(Config.BeatSeconds + 0.6)
	local after = ctx.lastState()
	eq(after and after.night, night0, "CAUGHT: the night did not advance")
	eq(after and after.phase, "DAY", "...and the player is back in the safehouse")

	-- the cards and chip for every band, through real extractions only
	local lastBandIdx = 1
	local tintDuring = {}
	local maxTintStep, maxDensityStep = 0, 0
	local prevTint, prevDensity = nil, nil
	local cc = h.Lighting:FindFirstChild("FxColorCorrection")
	local atm = h.Lighting:FindFirstChild("FxAtmosphere")
	local skyByBand = {}
	local chipOk, chipTotal = 0, 0
	local perBand = {}
	local prevOnFrame = ctx.onFrame
	ctx.onFrame = function(dt)
		prevOnFrame(dt)
		local s = ctx.lastState() or {}
		local idx = Nightfall.bandIndex(bands, s.night or 1)
		local c = ctx.count()
		local key = bands[idx].id .. "/" .. tostring(s.phase)
		local pb = perBand[key] or { parts = 0, emitters = 0, rate = 0, lights = 0 }
		for k in pb do pb[k] = math.max(pb[k], c[k]) end
		perBand[key] = pb
		local t = rgb255(cc.TintColor)
		if prevTint then
			maxTintStep = math.max(maxTintStep, math.abs(t[1] - prevTint[1]), math.abs(t[2] - prevTint[2]), math.abs(t[3] - prevTint[3]))
			maxDensityStep = math.max(maxDensityStep, math.abs(atm.Density - prevDensity))
		end
		prevTint, prevDensity = t, atm.Density
	end
	local nights = 0
	while (ctx.lastState() or {}).night < 40 and nights < 60 do
		ctx.surviveNights(1, 0.1)
		nights += 1
		local s = ctx.lastState()
		local idx = Nightfall.bandIndex(bands, s.night)
		chipTotal += 1
		ctx.seconds(1.4, 0.1) -- the day: long enough for the card to wait out the server's toast
		if string.find(ctx.chip.Text, bands[idx].name, 1, true) and string.find(ctx.chip.Text, "Night " .. s.night, 1, true) then
			chipOk += 1
		else
			print(string.format("  chip mismatch after night %s: %q (phase %s)", tostring(s.night), ctx.chip.Text, tostring(s.phase)))
		end
		if idx ~= lastBandIdx then
			-- let the grade and the windows glide in
			ctx.seconds(4, 0.1)
			local want = bands[idx].colorCorrection.TintColor
			tintDuring[bands[idx].id] = rgb255(cc.TintColor)
			truthy(colorNear(cc.TintColor, want, 3), string.format("%s: the grade glides to the band's tint (%s vs %d,%d,%d)",
				bands[idx].id, table.concat(rgb255(cc.TintColor), ","), want[1], want[2], want[3]))
			-- read the sky BETWEEN lightning flashes (a flash turns the glass the flash colour for 0.06 s, at
			-- random moments in the storm bands); a frame with a bolt in the glass is not the band's sky
			local waitedFlash = 0
			while (ctx.folder:FindFirstChild("Bolt1") or ctx.folder:FindFirstChild("FlashHost")) and waitedFlash < 30 do
				ctx.frame(1 / 30)
				waitedFlash += 1
			end
			local sky = nil
			for _, d in ctx.folder:GetChildren() do
				if d.Name == "WinSky" then sky = d end
			end
			local wantSky = bands[idx].glow.sky
			truthy(sky ~= nil and colorNear(sky.Color, wantSky, 3), string.format("%s: the safehouse windows show the band's sky (%s vs %d,%d,%d)",
				bands[idx].id, sky and table.concat(rgb255(sky.Color), ",") or "none", wantSky[1], wantSky[2], wantSky[3]))
			skyByBand[bands[idx].id] = sky and rgb255(sky.Color)
			checkSky(bands[idx], bands[idx].id .. "/DAY")
			lastBandIdx = idx
		end
	end
	eq((ctx.lastState() or {}).night, 40, string.format("%d survived nights later the player is on night 40", nights))
	eq(chipOk, chipTotal, string.format("the chip named the right band and night after every one of %d nights", chipTotal))
	print("  cards shown: " .. table.concat(ctx.cards, " | "))
	local want = { "QUIET NIGHT", "THE MIST RISES", "RAIN ON THE GLASS", "THUNDERSTORM", "THE BLOOD MOON RISES", "THE WITCHING HOUR" }
	local found = 0
	local cardsJoined = table.concat(ctx.cards, "|")
	for _, w2 in want do
		if string.find(cardsJoined, w2, 1, true) then found += 1 else print("  missing card: " .. w2) end
	end
	eq(found, #want, "a card for every band, each shown once, in order of first arrival")
	local bloodCount = 0
	for _, c in ctx.cards do
		if string.find(c, "BLOOD MOON", 1, true) then bloodCount += 1 end
	end
	eq(bloodCount, 1, "the Blood Moon is celebrated exactly once")
	print(string.format("  lighting glide: largest single-frame tint step %d/255, density step %.4f", maxTintStep, maxDensityStep))
	truthy(maxTintStep <= 4, "the grade never jumps: no single frame moves a tint channel more than 4/255 (" .. maxTintStep .. ")")
	truthy(maxDensityStep <= 0.004, string.format("nor the fog density more than 0.004 (%.4f)", maxDensityStep))

	print("  per band, peak client parts / emitters (rate) / lights:")
	local keys = {}
	for k in perBand do table.insert(keys, k) end
	table.sort(keys)
	for _, k in keys do
		local pb = perBand[k]
		print(string.format("    %-22s %3d parts  %d emitters (%3.0f/s)  %d lights", k, pb.parts, pb.emitters, pb.rate, pb.lights))
	end
	ctx.onFrame = prevOnFrame
end

--================================================================ portraits on a night that has a hall

do
	-- night 40's manor, walked by the same tour: every hall portrait seen gets eyes
	ctx.pressDoor()
	ctx.seconds(0.4, 0.1)
	local m = ctx.manor()
	local halls, eyes = 0, 0
	if m then
		local w = m:FindFirstChild("Nightwatcher")
		for _, f in m:GetChildren() do
			if string.match(tostring(f.Name), "_hall$") and ctx.manor() ~= nil then
				local floor = f:FindFirstChild("Floor")
				local wp = w and w:GetPivot().Position
				if floor and (wp == nil or (Vector3.new(wp.X, 0, wp.Z) - Vector3.new(floor.Position.X, 0, floor.Position.Z)).Magnitude > 60) then
					halls += 1
					ctx.hrp.CFrame = CFrame.new(floor.Position + Vector3.new(0, 4, 0))
					ctx.frames(10)
					for _, d in ctx.folder:GetChildren() do
						if d.Name == "PortraitPupil" then eyes += 1 end
					end
				end
			end
		end
	end
	print(string.format("  night 40: %d Portrait Halls visited, %d pupils seen in all", halls, eyes))
	truthy(halls == 0 or eyes >= 2 * halls, "every Portrait Hall visited had watching eyes")
	ctx.pressExit()
	ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
end

--================================================================ §8 the safehouse grows cosier

do
	local function has(name: string): boolean
		for _, d in ctx.folder:GetChildren() do
			if d.Name == name then return true end
		end
		return false
	end
	local house = ctx.house()
	local pads = {}
	for _, d in house:GetChildren() do
		local id = d:GetAttribute("UpgradeId")
		if id then pads[id] = d end
	end
	local order = { "lanterns", "wardstones", "beartraps", "relicvault", "lanterns", "alarmbell", "lockbox", "floodlights",
		"lanterns", "wardstones", "beartraps", "relicvault", "lanterns", "wardstones", "beartraps", "relicvault",
		"lanterns", "wardstones", "beartraps", "relicvault" }
	local seen = { [1] = has("Chimney") and not has("Fire") }
	local bought = 0
	local tierAt = {}
	for i, id in order do
		pads[id]:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(ctx.me)
		ctx.frames(4, 0.1)
		bought = (ctx.lastState() or {}).hubLevel or bought
		local tier = Nightfall.cosyTier(Config.Env.Cosy, bought)
		if tierAt[tier] == nil then
			tierAt[tier] = { fire = has("Fire"), chair = has("ChairSeat"), cat = has("CatBody"), plant = has("Plant"), level = bought }
		end
		local _ = i
	end
	-- every prop of the cosiest safehouse stands clear of what the player uses: the upgrade pads (their
	-- hardware stacks on them), the spawn pad, and the manor door with the 6 studs in front of it
	do
		local keep = {}
		for _, d in house:GetChildren() do
			if d:IsA("BasePart") and (string.match(tostring(d.Name), "^Pad_") or d.Name == "SpawnPad") then
				table.insert(keep, { name = d.Name, x = d.Position.X, z = d.Position.Z, hx = d.Size.X / 2, hz = d.Size.Z / 2 })
			elseif d.Name == "ManorDoor" then
				table.insert(keep, { name = "ManorDoor", x = d.Position.X, z = d.Position.Z + 3, hx = d.Size.X / 2, hz = 3.5 })
			end
		end
		local PROPS = { Chimney = true, Firebox = true, Mantel = true, Hearth = true, Fire = true, Rug = true, ChairSeat = true,
			ChairBack = true, ChairArm = true, Bookshelf = true, Books = true, Candle = true, CatBody = true, CatHaunch = true,
			CatHead = true, CatTail = true, Garland = true, PaintingFrame = true, Painting = true, Pot = true, Plant = true }
		local props, clash = 0, nil
		for _, d in ctx.folder:GetChildren() do
			if PROPS[d.Name] then
				props += 1
				-- the prop's world-axis box (its rotated extents), half a stud of margin
				local cf, s = d.CFrame, d.Size
				local R, U, B = cf.RightVector, cf.UpVector, cf.LookVector
				local ex = math.abs(R.X) * s.X / 2 + math.abs(U.X) * s.Y / 2 + math.abs(B.X) * s.Z / 2
				local ez = math.abs(R.Z) * s.X / 2 + math.abs(U.Z) * s.Y / 2 + math.abs(B.Z) * s.Z / 2
				for _, k in keep do
					if math.abs(d.Position.X - k.x) < ex + k.hx + 0.5 and math.abs(d.Position.Z - k.z) < ez + k.hz + 0.5 then
						clash = clash or (d.Name .. " over " .. k.name)
					end
				end
			end
		end
		truthy(#keep >= 9, "CONTROL: found the 7 upgrade pads, the spawn pad and the door (" .. #keep .. ")")
		truthy(props >= 30, "CONTROL: the cosiest safehouse's props are all out (" .. props .. ")")
		eq(clash, nil, "no safehouse prop stands on an upgrade pad, the spawn pad or the way to the manor door")
	end
	truthy(seen[1], "hub level 0: a cold hearth and no fire")
	eq(tierAt[2] and tierAt[2].fire, true, "hub level 2: the hearth is kindled")
	eq(tierAt[2] and tierAt[2].chair, false, "...and not yet furnished")
	eq(tierAt[3] and tierAt[3].chair, true, "hub level 6: an armchair by the fire")
	eq(tierAt[4] and tierAt[4].cat, true, "hub level 12: the cat has moved in")
	eq(tierAt[5] and tierAt[5].plant, true, "hub level 20: the whole haven")
	local fire = nil
	for _, d in ctx.folder:GetChildren() do
		if d.Name == "Fire" then fire = d end
	end
	local fl = fire and fire:FindFirstChild("FireLight")
	truthy(fl ~= nil and fl.Enabled, "the fire gives light")
	ctx.pressDoor()
	ctx.seconds(1, 0.1)
	truthy(not has("Fire") and not has("Chimney"), "at night the safehouse's props are unparented (no draw calls 400 studs away)")
	ctx.pressExit()
	ctx.seconds(Config.BeatSeconds + 0.6, 0.1)
	truthy(has("Fire") and has("CatBody"), "...and back when the night is over")
end

--================================================================ budgets + remotes

print(string.format("  budget peaks over the whole run: %d parts (%s), %d emitters, %.0f particles/s, %d lights",
	ctx.peak.parts, tostring(ctx.peak.partsAt), ctx.peak.emitters, ctx.peak.rate, ctx.peak.lights))
eq(ctx.budgetFails, 0, "every frame of the run stayed inside Config.Budget (" .. tostring(ctx.budgetExample) .. ")")
eq(ctx.serverCalls, 0, "the client never fired a remote at the server")

-- §2, Lighting (review 4). After a whole session of every band, what differs from the server's Lighting is only what
-- the bands drive: their own keys, on the service and on the three effects the server made for the Horror preset.
-- A future server-side Lighting change (a catch effect, say) would be overwritten by the client; this is the list a
-- future editor must extend deliberately, not discover.
do
	local L = h.Lighting
	local groupOf = { lighting = "Lighting", atmosphere = "FxAtmosphere", bloom = "FxBloom", colorCorrection = "FxColorCorrection" }
	local allowed = { Lighting = {}, FxAtmosphere = {}, FxBloom = {}, FxColorCorrection = {} }
	for _, b in bands do
		for g, name in groupOf do
			for k in b[g] do allowed[name][k] = true end
		end
	end
	local function changedKeys(before: any, after: any): { string }
		local out = {}
		for k, v in after do
			if before[k] ~= v then table.insert(out, tostring(k)) end
		end
		for k in before do
			if after[k] == nil then table.insert(out, tostring(k)) end
		end
		table.sort(out)
		return out
	end
	local bad, wrote = {}, 0
	truthy(lightingSnap ~= nil, "CONTROL: Lighting was snapshotted before the client ran")
	if lightingSnap then
		for _, k in changedKeys(lightingSnap.props, L.__emu.props) do
			wrote += 1
			if not allowed.Lighting[k] then table.insert(bad, "Lighting." .. k) end
		end
		local serverKids = 0
		for ch, rec in lightingSnap.children do
			serverKids += 1
			if ch.Parent ~= L then
				table.insert(bad, rec.name .. " was removed")
			else
				local allow = allowed[rec.name] or {}
				for _, k in changedKeys(rec.props, ch.__emu.props) do
					wrote += 1
					if not allow[k] then table.insert(bad, rec.name .. "." .. k) end
				end
			end
		end
		local added = {}
		for _, ch in L:GetChildren() do
			if lightingSnap.children[ch] == nil then table.insert(added, ch.Name) end
		end
		table.sort(added)
		print(string.format("  Lighting: %d server-made children; %d keys changed by the session, %d of them outside the bands (%s); added: %s",
			serverKids, wrote, #bad, table.concat(bad, ", "), table.concat(added, ", ")))
		truthy(lightingSnap.children[L:FindFirstChild("FxDoF") or false] ~= nil, "CONTROL: the server's own DepthOfField (FxDoF) is among them")
		truthy(wrote >= 4, "CONTROL: the bands really did write Lighting (" .. wrote .. " keys)")
		eq(#bad, 0, "the client wrote only the bands' own keys of Lighting and of FxAtmosphere / FxBloom / FxColorCorrection; nothing else (" .. table.concat(bad, ", ") .. ")")
		eq(table.concat(added, ","), "NightwatchRestFocus", "and added exactly one effect of its own to Lighting, the rest focus")
	end
end
do
	local names = {}
	for _, r in ctx.remotes:GetChildren() do table.insert(names, r.Name) end
	table.sort(names)
	eq(table.concat(names, ","), table.concat(ctx.remoteNames, ","), "the remote surface is exactly the server's (" .. table.concat(names, ",") .. ")")
end

ctx.finish("nightwatchmanor haunt")
