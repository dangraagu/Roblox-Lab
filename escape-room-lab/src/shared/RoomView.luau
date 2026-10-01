--!strict
-- RoomView.luau — builds the RoomState payload, the ONLY thing about a room that leaves the server.
-- Pure; no Roblox. It needs the sentences in Text.luau; shared modules take dependencies as arguments,
-- so the server and the tests hand Text over once through RoomView.setText.
--
-- The rule (DESIGN.md §12.2-12.4): answers live only in the server's memory. From a room's state this
-- copies exactly what a player may see — lamp states, the shelf's current order and its clue sentences,
-- the door's LIT lines, which feeder lights each dark line, lockout seconds — and nothing else. Every
-- key it can emit is in RoomView.KEYS; tests/RoomView.spec.luau walks the payload against that list and
-- check_escaperoomlab_leak does the same on the real server's wire.

local RoomView = {}

local Text: any = nil

-- Shared modules take their dependencies as arguments (a string require is invalid in Roblox).
function RoomView.setText(t: any)
	Text = t
end

-- Every key a payload may carry, at any depth.
RoomView.KEYS = {
	-- top level
	"where", "roomId", "slot", "wing", "room", "wingName", "origin", "members", "pair", "state",
	"stations", "door", "solved", "total", "you",
	-- a feeder station
	"id", "kind", "size", "lamps", "flasks", "clues", "lockedFor",
	-- the door
	"L", "alphabet", "lines", "enterable", "lastWrong",
	-- a door line
	"guess", "text", "dark", "by",
	-- you
	"wrong", "hinted", "handsOn",
}

local function copy(t: { any }): { any }
	return table.clone(t)
end

local function lockLeft(until_: number?, now: number): number
	if type(until_) ~= "number" then return 0 end
	return math.max(0, math.ceil(until_ - now - 1e-9))
end

function RoomView.outside(where: string): any
	return { where = where }
end

-- room: the server's room table; you: { wrong, hinted, handsOn } for the receiving player.
function RoomView.build(room: any, you: any, now: number): any
	assert(Text ~= nil, "RoomView.setText(Text) must be called first")
	local stations = {}
	local solved = 0
	for _, s in room.feeders do
		local v: any = { id = s.id, kind = s.kind, solved = s.solved == true, lockedFor = lockLeft(s.lockUntil, now) }
		if s.kind == "lamp" then
			v.size = s.n
			v.lamps = copy(s.grid)
		else
			v.size = s.N
			v.flasks = copy(s.order)
			local clues = {}
			for i, c in s.clues do clues[i] = Text.shelfClue(c) end
			v.clues = clues
		end
		if s.solved then solved += 1 end
		table.insert(stations, v)
	end
	local d = room.door
	local hiddenSet: { [number]: boolean } = {}
	for _, i in d.hidden do hiddenSet[i] = true end
	local lines = {}
	local allLit = true
	for i, ln in d.lines do
		if hiddenSet[i] and not d.lit[i] then
			allLit = false
			lines[i] = { dark = true, by = d.feederOf[i] }
		else
			lines[i] = { guess = Text.codeGuess(ln.guess), text = Text.codeSentence(ln.a, ln.b) }
		end
	end
	local locked = lockLeft(d.lockUntil, now)
	if d.solved then solved += 1 end
	return {
		where = "room",
		roomId = room.roomId,
		slot = room.slot,
		wing = room.wing,
		room = room.room,
		wingName = room.wingName,
		origin = copy(room.origin),
		members = copy(room.members),
		pair = room.pair == true,
		state = room.state,
		stations = stations,
		door = {
			id = "Door",
			L = d.L,
			alphabet = copy(d.alphabet),
			lines = lines,
			enterable = allLit and not d.solved,
			lockedFor = locked,
			lastWrong = if locked > 0 and d.lastWrong then Text.codeGuess(d.lastWrong) else nil,
			solved = d.solved == true,
		},
		solved = solved,
		total = #room.feeders + 1,
		you = { wrong = you.wrong == true, hinted = you.hinted == true, handsOn = you.handsOn == true },
	}
end

return RoomView
