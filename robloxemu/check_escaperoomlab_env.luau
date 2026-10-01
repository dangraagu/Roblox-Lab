-- Escape Room Lab — the eye candy through the REAL clients, over the whole Lab: 15 rooms to the Roof.
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_env.luau 2>&1
--
-- What it proves (DESIGN.md §7, docs/complete-game-standard.md §2):
--   * the server's boot lighting IS band 1 (Fx.Presets.Lab), so the client takes over with no jump;
--   * the band follows the game's own progress: each wing's rooms show that wing's decor, creatures and
--     weather; in the LAST room of a wing the next wing SEEPS IN as stations are solved, and is fully
--     there when that room's door opens; nothing depends on time;
--   * a jump in progress (the Roof -> the Atrium) GLIDES: one frame later the light has not snapped;
--   * every wing's title card plays once; the Roof shows 3000 stars, the skyline and fireworks;
--   * on EVERY frame: local parts <= 120, emitters on <= 3, beams <= 4, trails <= 2, lights <= 2; every
--     decor piece keeps off the play space (above 9 studs, off every station face, out of the doorways)
--     and every creature flies in the upper volume.
-- Every room is solved from what the world shows (lamp parts, flask letters, clue and door text) with
-- the game's pure solvers, through the real Act remote.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/escape-room-lab"), name = "escape-room-lab-env", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local RS, ws = h.ReplicatedStorage, h.workspace
local Lighting = h.Lighting
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Text, Lamps, Shelf, CodeLock = mod("Config"), mod("Text"), mod("Lamps"), mod("Shelf"), mod("CodeLock")
local W, bands = Config.World, Config.Env.Bands

--============================================================ 1. boot lighting == band 1
local function rgbOf(c) return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } end
-- exact (1 unit of colour, 1e-6) at the hand-over; `tol` for a glide that has settled (0.6 s half-life)
local function sameValue(a, want, tol)
	if type(want) == "table" then
		local got = rgbOf(a)
		local t = if tol then 2 else 1
		return math.abs(got[1] - want[1]) <= t and math.abs(got[2] - want[2]) <= t and math.abs(got[3] - want[3]) <= t
	end
	return type(a) == "number" and math.abs(a - want) <= (if tol then tol * math.max(1, math.abs(want)) else 1e-6)
end
local groupTarget = { lighting = function() return Lighting end,
	atmosphere = function() return Lighting:FindFirstChild("FxAtmosphere") end,
	bloom = function() return Lighting:FindFirstChild("FxBloom") end,
	colorCorrection = function() return Lighting:FindFirstChild("FxColorCorrection") end }
local function lightingMatches(bandIdx, label, tol)
	local bad = {}
	for g, get in groupTarget do
		local inst = get()
		if inst == nil then
			table.insert(bad, g .. " missing")
		else
			for k, v in bands[bandIdx][g] do
				if not sameValue(inst[k], v, tol) then table.insert(bad, g .. "." .. k) end
			end
		end
	end
	eq(#bad, 0, label .. " (" .. table.concat(bad, ", ") .. ")")
end
lightingMatches(1, "the server's boot lighting equals band 1, field for field")

--============================================================ the player and the clients
local plr = h:join("Envy", 8101)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, ws)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Lab.client"))
local RunService = h.game:GetService("RunService")
local cam = ws.CurrentCamera
local env = ws:FindFirstChild("LabLocalEnv")
truthy(env ~= nil, "Lab.client built workspace.LabLocalEnv")
local hudRoot = plr.PlayerGui.LabHud.Root
local R = {}
for _, n in { "Act", "RoomState", "Notice", "Profile" } do R[n] = RS.LabRemotes:FindFirstChild(n) end
local function last(remote)
	local s = remote:sentTo(plr)
	return s[#s] and s[#s].args[1]
end

-- station faces, the play space's walls (room-local): decor may not enter any of them
local FACES = {
	{ "Station_A", -16, -13, 2.5, 10.5, -5, 5 }, { "Station_B", 13, 16, 2.5, 10.5, -5, 5 },
	{ "door board", -16, -4, 4.5, 11.5, -16, -13 }, { "door + keypad", -3, 10, 0, 9, -16, -13 },
	{ "entry doorway", -3, 3, 0, 8, 13, 16 },
}
local maxima = { parts = 0, emitters = 0, beams = 0, trails = 0, lights = 0 }
-- every title card Lab.client FIRES (Hud may show one card over another; counting what is fired is exact)
local cardsFired = {}
local bus = mod("ClientBus")
bus.on("card", function(c) table.insert(cardsFired, c.title) end)
-- authored positions, to prove decor is anchored to the ROOM (not to the camera or the player)
local authored = {}
for _, b in bands do
	for _, piece in mod("Decor").pieces(b.id) do authored[b.id .. "_" .. piece.id] = piece.pos end
end
local unanchored = {}
local decorBad, critterBad, framesMeasured = {}, {}, 0
local cardsSeen = {}
local where, origin = "atrium", Vector3.zero

local function measure()
	framesMeasured += 1
	local parts, emitters, beams, trails, lights = 0, 0, 0, 0, 0
	for _, d in env:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 end
		if d.ClassName == "ParticleEmitter" and d.Enabled ~= false then emitters += 1 end
		if d.ClassName == "Beam" then beams += 1 end
		if d.ClassName == "Trail" then trails += 1 end
		if d.ClassName == "PointLight" or d.ClassName == "SpotLight" or d.ClassName == "SurfaceLight" then lights += 1 end
		if where == "room" and d:IsA("BasePart") then
			local l = d.Position - origin
			if string.match(d.Name, "^Decor_") and d.Transparency < 0.999 then
				local want = authored[string.sub(d.Name, 7)]
				if want and (math.abs(l.X - want[1]) > 0.01 or math.abs(l.Y - want[2]) > 0.01 or math.abs(l.Z - want[3]) > 0.01) then
					unanchored[d.Name] = string.format("(%.1f, %.1f, %.1f) not (%s)", l.X, l.Y, l.Z, table.concat(want, ", "))
				end
				local s = d.Size
				local x0, x1, y0, y1, z0, z1 = l.X - s.X / 2, l.X + s.X / 2, l.Y - s.Y / 2, l.Y + s.Y / 2, l.Z - s.Z / 2, l.Z + s.Z / 2
				if y0 < 9 - 1e-3 then decorBad[d.Name .. " below 9"] = true end
				for _, f in FACES do
					if x0 < f[3] and f[2] < x1 and y0 < f[5] and f[4] < y1 and z0 < f[7] and f[6] < z1 then
						decorBad[d.Name .. " in front of " .. f[1]] = true
					end
				end
			elseif string.match(d.Name, "^Critter_") then
				if l.Y < 7.5 or l.Y > 14.5 or math.abs(l.X) > 14.5 or math.abs(l.Z) > 14.5 then
					critterBad[d.Name] = string.format("(%.1f, %.1f, %.1f)", l.X, l.Y, l.Z)
				end
			end
		end
	end
	maxima.parts = math.max(maxima.parts, parts)
	maxima.emitters = math.max(maxima.emitters, emitters)
	maxima.beams = math.max(maxima.beams, beams)
	maxima.trails = math.max(maxima.trails, trails)
	maxima.lights = math.max(maxima.lights, lights)
	local c = hudRoot.Card
	if c.Visible and c.Text ~= "" and cardsSeen[#cardsSeen] ~= c.Text then table.insert(cardsSeen, c.Text) end
end

local function frame(dt)
	-- measure against the state the client rendered this frame with: the newest RoomState it has had
	local rs = last(R.RoomState)
	where = rs and rs.where or "atrium"
	if rs and rs.origin then origin = Vector3.new(rs.origin[1], rs.origin[2], rs.origin[3]) end
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 4, 10), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	measure()
	h:advance(dt)
end
local function run(seconds)
	for _ = 1, math.floor(seconds * 10 + 0.5) do frame(0.1) end
end

run(1)
lightingMatches(1, "one second of the client later, still band 1: no jump at the hand-over")

--============================================================ reading the world
local function zone()
	for _, z in ws.Zones:GetChildren() do
		if z:FindFirstChild("DoorBoard", true) then return z end
	end
end
local function labelText(root, name)
	local l = root and root:FindFirstChild(name, true)
	return l and l.Text or nil
end
local function standNear(id)
	local p = W.Stations[id]
	if id == "Door" then
		hrp.CFrame = CFrame.new(origin + Vector3.new(0, 3, -12))
	else
		hrp.CFrame = CFrame.new(origin + Vector3.new(p[1] * 0.78, 3, p[3]))
	end
end
local function solveLamp(st)
	local panel = zone():FindFirstChild("Station_" .. st.id, true)
	local grid, n = {}, 0
	for _, c in panel:GetChildren() do
		local i = tonumber(string.match(c.Name, "^Lamp_(%d+)$"))
		if i then
			grid[i] = c.Material == Enum.Material.Neon
			n += 1
		end
	end
	standNear(st.id)
	for _, i in Lamps.solve(grid, math.floor(math.sqrt(n) + 0.5)) do
		R.Act:simulateFireServer(plr, st.id, "press", i)
		frame(0.1)
	end
end
local function solveShelf(st)
	local panel = zone():FindFirstChild("Station_" .. st.id, true)
	local clueFace = panel:FindFirstChild("ClueFace")
	local clues = {}
	for i = 1, 9 do
		local t = labelText(clueFace, "Clue_" .. i)
		if t then table.insert(clues, Text.parseShelfClue(t)) end
	end
	local function order()
		local o = {}
		for s = 1, 5 do
			local f = panel:FindFirstChild("Flask_" .. s)
			if f then o[s] = table.find(Text.FlaskLetters, labelText(f, "Letter")) end
		end
		return o
	end
	local sols = Shelf.solve(order(), clues)
	eq(#sols, 1, "shelf " .. st.id .. ": the world's clue sentences fit one order")
	standNear(st.id)
	local target = sols[1]
	for i = 1, #target do
		local cur = order()
		if cur[i] ~= target[i] then
			R.Act:simulateFireServer(plr, st.id, "swap", i, table.find(cur, target[i]))
			frame(0.1)
		end
	end
	R.Act:simulateFireServer(plr, st.id, "test")
	frame(0.1)
end
local function solveDoor()
	local rs = last(R.RoomState)
	local board = zone():FindFirstChild("DoorBoard", true)
	local lines = {}
	for i = 1, 6 do
		local g, t = labelText(board, "RowGuess_" .. i), labelText(board, "RowText_" .. i)
		local guess = g and Text.parseCodeGuess(g)
		local a, b = nil, nil
		if t then a, b = Text.parseCodeSentence(t) end
		if guess and a then table.insert(lines, { guess = guess, a = a, b = b }) end
	end
	local codes = CodeLock.solve(lines, rs.door.L, rs.door.alphabet)
	eq(#codes, 1, "room " .. rs.slot .. ": the door board fits one code")
	standNear("Door")
	R.Act:simulateFireServer(plr, "Door", "enter", codes[1])
	frame(0.1)
end
local function decorBands()
	local out = {}
	for _, d in env:GetChildren() do
		local id = string.match(d.Name, "^Decor_([%a]+)_")
		if id and d.Transparency < 0.999 then out[id] = (out[id] or 0) + 1 end
	end
	return out
end
local function decorAlpha(bandId)
	-- the mean opacity of a band's decor relative to its authored opacity: 1 = fully in
	local sum, n = 0, 0
	local mod_ = mod("Decor")
	local base = {}
	for _, p in mod_.pieces(bandId) do base[p.id] = p.transparency end
	for _, d in env:GetChildren() do
		local id, pid = string.match(d.Name, "^Decor_([%a]+)_(.+)$")
		if id == bandId and base[pid] then
			sum += (1 - d.Transparency) / (1 - base[pid])
			n += 1
		end
	end
	return if n > 0 then sum / n else 0
end
local function critterCount(kind)
	local n = 0
	for _, d in env:GetChildren() do
		if string.match(d.Name, "^Critter_" .. kind .. "_%d+_1$") then n += 1 end
	end
	return n
end
local function weatherOn()
	local out = {}
	for _, d in env:GetChildren() do
		if string.match(d.Name, "^WeatherHost_") then
			local e = d:FindFirstChild("Weather")
			if e and e.Enabled then table.insert(out, e.Rate) end
		end
	end
	return out
end

--============================================================ 2. fifteen rooms
hrp.CFrame = CFrame.new(W.SoloCab[1], 3.5, W.SoloCab[2])
run(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
local wingDecor, seep, full = {}, {}, {}
local serverParts = {} -- per room: parts the SERVER built for it (cap Config.World.MaxRoomParts)
for slot = 1, 15 do
	local rs = last(R.RoomState)
	eq(rs and rs.slot, slot, "the lift brought the player to room " .. slot)
	if rs == nil or rs.slot ~= slot then break end
	local wing, room = rs.wing, rs.room
	run(4) -- the glide settles (0.6 s half-life)
	local np = 0
	for _, d in zone():GetDescendants() do if d:IsA("BasePart") then np += 1 end end
	serverParts[slot] = np
	local db = decorBands()
	if room == 1 then
		wingDecor[wing] = db
		truthy((db[bands[wing].id] or 0) >= 4, string.format("wing %d room 1 shows %s decor (%d pieces)", wing, bands[wing].id, db[bands[wing].id] or 0))
		local others = 0
		for id, n in db do if id ~= bands[wing].id then others += n end end
		eq(others, 0, string.format("wing %d room 1 shows no other band's decor", wing))
		local chip = hudRoot.StarChip.StarText.Text
		truthy(string.find(chip, Config.Lab.Wings[wing].name, 1, true) ~= nil, "the chip names the wing: " .. chip)
		if wing == 3 then eq(critterCount("butterfly"), 5, "the Greenhouse has 5 butterflies") end
		if wing == 4 then
			local on = weatherOn()
			truthy(#on == 1 and math.abs(on[1] - 20) < 0.5, "Cold Storage snows at 20/s (" .. #on .. " emitters)")
		end
		if wing == 5 then eq(#weatherOn(), 2, "the Reactor runs steam AND sparks: both weather emitters") end
	end
	for _, st in rs.stations do
		if st.kind == "lamp" then solveLamp(st) else solveShelf(st) end
		run(2)
		if room == 3 and wing < 5 then
			local a = decorAlpha(bands[wing + 1].id)
			seep[wing] = math.max(seep[wing] or 0, a)
		end
	end
	if room == 3 and wing < 5 then
		truthy((seep[wing] or 0) > 0.05 and (seep[wing] or 0) < 0.95,
			string.format("wing %d room 3: with its feeders solved, %s seeps in (%.2f of full)", wing, bands[wing + 1].id, seep[wing] or 0))
	end
	solveDoor()
	local rsDone = last(R.RoomState)
	eq(rsDone.state, "escaped", "room " .. slot .. " escaped")
	run(4)
	if room == 3 and wing < 5 then
		local a = decorAlpha(bands[wing + 1].id)
		full[wing] = a
		truthy(a > 0.97, string.format("wing %d room 3, door open: %s is fully in (%.2f)", wing, bands[wing + 1].id, a))
		eq(decorBands()[bands[wing].id], nil, string.format("and %s's decor is gone", bands[wing].id))
	end
	hrp.CFrame = CFrame.new(origin + Vector3.new(0, 3.5, -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)))
	local nextPart = zone():FindFirstChild("NextPanel", true)
	nextPart:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	run(Config.Lift.RideSeconds + 1)
end

--============================================================ 3. the Roof
local rsRoof = last(R.RoomState)
eq(rsRoof and rsRoof.where, "roof", "room 15's lift went UP, to the Roof")
local fireworks = 0
for _ = 1, 30 do
	frame(0.1)
	for _, d in env:GetChildren() do if d.Name == "Firework" then fireworks += 1 end end
end
run(4)
truthy(fireworks > 0, "fireworks burst over the Roof")
local sky = Lighting:FindFirstChild("LabSky")
truthy(sky and math.abs(sky.StarCount - 3000) < 30, "3000 stars over the Roof (" .. tostring(sky and sky.StarCount) .. ")")
truthy(math.abs(Lighting.ClockTime - bands[6].lighting.ClockTime) < 0.1, "night on the Roof (ClockTime " .. Lighting.ClockTime .. ")")
truthy((decorBands().roof or 0) >= 12, "the city skyline stands around the Roof")
eq(critterCount("bat"), 3, "three bats")
local escapedCard = false
for _, c in cardsSeen do if c == "YOU ESCAPED THE LAB" then escapedCard = true end end
truthy(escapedCard, "the brag card: YOU ESCAPED THE LAB")

--============================================================ 4. a jump in progress glides (the Roof -> the Atrium)
local back = ws.Roof:FindFirstChild("BackDown"):FindFirstChildOfClass("ProximityPrompt")
hrp.CFrame = CFrame.new(0, W.RoofY + 3, 14)
local roofAmbient = rgbOf(Lighting.Ambient)
back.Triggered:Fire(plr)
frame(0.1)
frame(0.1)
local mid = rgbOf(Lighting.Ambient)
local recep = bands[1].lighting.Ambient
local distMid = math.abs(mid[1] - recep[1]) + math.abs(mid[2] - recep[2]) + math.abs(mid[3] - recep[3])
local distRoof = math.abs(roofAmbient[1] - recep[1]) + math.abs(roofAmbient[2] - recep[2]) + math.abs(roofAmbient[3] - recep[3])
truthy(distMid > 20 and distMid < distRoof, string.format("0.2 s after the jump the light is still gliding (%d from Reception, the Roof was %d)", distMid, distRoof))
run(6)
lightingMatches(1, "6 s later the Atrium's light has settled on band 1 (within 0.5%)", 0.005)

--============================================================ 5. the title cards, once each
local wingCards = {}
for _, c in cardsFired do
	local n = tonumber(string.match(c, "^WING (%d) "))
	if n then wingCards[n] = (wingCards[n] or 0) + 1 end
end
local escapes = 0
for _, c in cardsSeen do if string.match(c, "^ESCAPED ") then escapes += 1 end end
eq(escapes, 15, "every room's escape card was on screen (no card was buried under another)")
local ua = {}
for k, v in unanchored do table.insert(ua, k .. " " .. v) end
eq(#ua, 0, "every decor piece sat at its authored place in the room, on every frame (" .. table.concat(ua, "; ") .. ")")
for w = 2, 5 do eq(wingCards[w], 1, "the WING " .. w .. " title card played exactly once") end
eq(wingCards[1], nil, "no card for the wing a new player starts in")

--============================================================ server parts per room
do
	local lo, hi = math.huge, 0
	for s = 1, 15 do
		if serverParts[s] then lo, hi = math.min(lo, serverParts[s]), math.max(hi, serverParts[s]) end
	end
	print(string.format("  server parts per room: %d-%d over the 15 rooms (cap %d)", lo, hi, W.MaxRoomParts))
	truthy(hi <= W.MaxRoomParts and lo > 40, "every room's server parts are within the cap")
end

--============================================================ 6. every frame
print(string.format("  %d frames measured: max %d local parts (cap %d), %d emitters on (cap %d), %d beams, %d trails, %d lights",
	framesMeasured, maxima.parts, Config.Budget.LocalParts, maxima.emitters, Config.Budget.Emitters, maxima.beams, maxima.trails, maxima.lights))
truthy(maxima.parts <= Config.Budget.LocalParts, "local parts within the cap on every frame")
truthy(maxima.emitters <= Config.Budget.Emitters, "emitters within the cap on every frame")
truthy(maxima.beams <= Config.Budget.Beams, "beams within the cap")
truthy(maxima.trails <= Config.Budget.Trails, "trails within the cap")
truthy(maxima.lights <= Config.Budget.LocalLights, "local lights within the cap")
local bad = {}
for k in decorBad do table.insert(bad, k) end
eq(#bad, 0, "decor kept off the play space on every frame (" .. table.concat(bad, "; ") .. ")")
local cb = {}
for k, v in critterBad do table.insert(cb, k .. " " .. v) end
eq(#cb, 0, "every creature flew in the upper volume on every frame (" .. table.concat(cb, "; ") .. ")")
print("  seep-in peak per wing (share of the next band's decor opacity, feeders solved, door shut): "
	.. string.format("%.2f / %.2f / %.2f / %.2f", seep[1] or -1, seep[2] or -1, seep[3] or -1, seep[4] or -1))
print("  cards: " .. table.concat(cardsSeen, " | "))

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do print("  [warn] " .. w) end
print(string.format("escape-room-lab env: %d passed, %d failed", passed, failed))
if failed > 0 then error("escape-room-lab env check failed", 0) end
