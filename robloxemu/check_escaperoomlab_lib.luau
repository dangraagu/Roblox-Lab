-- Escape Room Lab — shared helpers for the check_escaperoomlab_* files. Not a check by itself.
--
-- Everything here plays the way a player does: it reads what the WORLD shows (lamp parts, flask letters,
-- the shelf's clue text, the door board's rows) and solves it with the game's own pure solvers, then acts
-- through the real Act remote from within reach. It never reads a server answer; none exist outside the
-- server script's memory.

local Harness = require("./emu/harness")

local Lib = {}

-- A required module gets its own globals table in the luau CLI, so the harness's fake Enum, CFrame and
-- Vector3 (installed into the CHECK's globals) are not visible here. Taken from the harness at boot.
local Enum, CFrame, Vector3 = nil, nil, nil

function Lib.counter()
	local c = { passed = 0, failed = 0 }
	function c.eq(a, b, msg)
		if a == b then c.passed += 1 else
			c.failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
		end
	end
	function c.truthy(v, msg)
		if v then c.passed += 1 else c.failed += 1; print("FAIL: " .. msg) end
	end
	function c.finish(name, h)
		for _, e in h:errors() do
			c.failed += 1
			print("FAIL: scheduler error: " .. e)
		end
		print(string.format("%s: %d passed, %d failed", name, c.passed, c.failed))
		if c.failed > 0 then error(name .. " failed", 0) end
	end
	return c
end

-- opts = { name, viewport?, touch?, preload = { [userId] = profileData }?, beforeServer = fn(h)? }
function Lib.boot(opts)
	local h = Harness.new({ bundle = require("./build/escape-room-lab"), name = opts.name, viewport = opts.viewport or { 1280, 720 },
		touch = opts.touch == true })
	if opts.preload then
		local store = h.services.DataStoreService:GetDataStore("EscapeRoomLab_v1")
		for uid, data in opts.preload do store:SetAsync("u_" .. uid, { data = data }) end
	end
	local dt = h.instance.datatypes
	Enum, CFrame, Vector3 = dt.Enum, dt.CFrame, dt.Vector3
	if opts.beforeServer then opts.beforeServer(h) end
	assert(h:tryRun("server/Main.server"))
	h:advance(0.5)
	local w = { h = h, RS = h.ReplicatedStorage, ws = h.workspace }
	function w.mod(name) return h:_require(w.RS:FindFirstChild(name)) end
	w.Config = w.mod("Config")
	w.R = {}
	for _, n in { "Act", "RoomState", "Notice", "Profile", "Open", "Hint", "Board", "Hello" } do
		w.R[n] = w.RS.LabRemotes:FindFirstChild(n)
	end
	return w
end

-- a player with a spawned character standing on something
function Lib.player(w, name, userId)
	local plr = w.h:join(name, userId)
	w.h:advance(0.5)
	local char = w.h.Players:simulateSpawn(plr, w.ws)
	local hum = char:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
	return { plr = plr, char = char, hrp = char:FindFirstChild("HumanoidRootPart"), hum = hum }
end

function Lib.last(w, remoteName, plr)
	local s = w.R[remoteName]:sentTo(plr)
	return s[#s] and s[#s].args[1]
end

function Lib.noticesSince(w, plr, n, kind)
	local out = {}
	local list = w.R.Notice:sentTo(plr)
	for i = n + 1, #list do
		local p = list[i].args[1]
		if type(p) == "table" and (kind == nil or p.kind == kind) then table.insert(out, p) end
	end
	return out
end

function Lib.origin(w, plr)
	local rs = Lib.last(w, "RoomState", plr)
	return Vector3.new(rs.origin[1], rs.origin[2], rs.origin[3])
end

-- the zone folder whose origin matches this player's room
function Lib.zone(w, plr)
	local o = Lib.origin(w, plr)
	for _, z in w.ws.Zones:GetChildren() do
		local d = z:FindFirstChild("Door", true)
		if d and math.abs(d.Position.X - o.X) < 20 then return z end
	end
	return nil
end

local function labelText(root, name)
	local l = root and root:FindFirstChild(name, true)
	return l and l.Text or nil
end
Lib.labelText = labelText

function Lib.standNear(w, p, id)
	local o = Lib.origin(w, p.plr)
	local s = w.Config.World.Stations[id]
	if id == "Door" then
		p.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3, -12))
	else
		p.hrp.CFrame = CFrame.new(o + Vector3.new(s[1] * 0.78, 3, s[3]))
	end
end

function Lib.readLamps(w, p, id)
	local panel = Lib.zone(w, p.plr):FindFirstChild("Station_" .. id, true)
	local grid, n = {}, 0
	for _, c in panel:GetChildren() do
		local i = tonumber(string.match(c.Name, "^Lamp_(%d+)$"))
		if i then
			grid[i] = c.Material == Enum.Material.Neon
			n += 1
		end
	end
	return grid, math.floor(math.sqrt(n) + 0.5)
end

function Lib.readShelf(w, p, id)
	local Text = w.mod("Text")
	local panel = Lib.zone(w, p.plr):FindFirstChild("Station_" .. id, true)
	local clues = {}
	for i = 1, 9 do
		local t = labelText(panel:FindFirstChild("ClueFace"), "Clue_" .. i)
		if t then table.insert(clues, Text.parseShelfClue(t)) end
	end
	local order = {}
	for s = 1, 5 do
		local f = panel:FindFirstChild("Flask_" .. s)
		if f then order[s] = table.find(Text.FlaskLetters, labelText(f, "Letter")) end
	end
	return order, clues
end

function Lib.readDoor(w, p)
	local Text = w.mod("Text")
	local board = Lib.zone(w, p.plr):FindFirstChild("DoorBoard", true)
	local lines = {}
	for i = 1, 6 do
		local g, t = labelText(board, "RowGuess_" .. i), labelText(board, "RowText_" .. i)
		local guess = g and Text.parseCodeGuess(g)
		local a, b = nil, nil
		if t then a, b = Text.parseCodeSentence(t) end
		if guess and a then table.insert(lines, { guess = guess, a = a, b = b }) end
	end
	return lines
end

-- solve a whole station from the world; `step` advances the world between actions
function Lib.solveStation(w, p, st, step)
	local Lamps, Shelf, CodeLock = w.mod("Lamps"), w.mod("Shelf"), w.mod("CodeLock")
	Lib.standNear(w, p, st.id or "Door")
	if st.kind == "lamp" then
		local grid, n = Lib.readLamps(w, p, st.id)
		for _, i in Lamps.solve(grid, n) do
			w.R.Act:simulateFireServer(p.plr, st.id, "press", i)
			step()
		end
	elseif st.kind == "shelf" then
		local order, clues = Lib.readShelf(w, p, st.id)
		local target = Shelf.solve(order, clues)[1]
		for i = 1, #target do
			local cur = (Lib.readShelf(w, p, st.id))
			if cur[i] ~= target[i] then
				w.R.Act:simulateFireServer(p.plr, st.id, "swap", i, table.find(cur, target[i]))
				step()
			end
		end
		w.R.Act:simulateFireServer(p.plr, st.id, "test")
		step()
	else
		local rs = Lib.last(w, "RoomState", p.plr)
		local codes = CodeLock.solve(Lib.readDoor(w, p), rs.door.L, rs.door.alphabet)
		w.R.Act:simulateFireServer(p.plr, "Door", "enter", codes[1])
		step()
		return codes
	end
end

function Lib.solveRoom(w, p, step)
	local rs = Lib.last(w, "RoomState", p.plr)
	for _, st in rs.stations do Lib.solveStation(w, p, st, step) end
	return Lib.solveStation(w, p, { kind = "door" }, step)
end

-- into the exit cab and NEXT
function Lib.next(w, p)
	local W = w.Config.World
	local o = Lib.origin(w, p.plr)
	p.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3.5, -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)))
	local panel = Lib.zone(w, p.plr):FindFirstChild("NextPanel", true)
	panel:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(p.plr)
end

function Lib.intoSoloLift(w, p)
	local W = w.Config.World
	p.hrp.CFrame = CFrame.new(W.SoloCab[1], 3.5, W.SoloCab[2])
end

return Lib
