-- Spec for RoomView: the ONLY builder of the RoomState payload (DESIGN.md §12.3, §12.4).
-- Run: luau tests/RoomView.spec.luau 2>&1
--
-- The server keeps each room's answers in script memory. What leaves it is built here, from a key
-- ALLOWLIST: a dark line carries only which feeder lights it, a lamp grid only its lamps, a shelf its
-- current order and its clue sentences, the door its lit lines. No secret, press set, hidden index or
-- random state is ever copied, and every key of the payload is on the list (a leak renamed onto a new
-- key still fails, per fork-tower REVIEW-3).
local RoomView = require("../src/shared/RoomView")
local CodeLock = require("../src/shared/CodeLock")
local Shelf = require("../src/shared/Shelf")
local Lamps = require("../src/shared/Lamps")
local Text = require("../src/shared/Text")
local Rng = require("../src/shared/Rng")
RoomView.setText(Text)

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local r = Rng.new(99)
local function rand() return r:next() end

-- a Reactor room built the way the server builds one
local function makeRoom()
	local lampG = Lamps.generate({ n = 4, k = 5 }, rand)
	local sh = Shelf.generate({ N = 5, maxClues = 7 }, rand)
	local door = CodeLock.generate({ L = 4, alphabet = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, feeders = 2, maxLines = 6 }, rand)
	return {
		roomId = 7, slot = 13, wing = 5, room = 1, wingName = "Reactor", origin = { 1500, 0, 0 },
		members = { "Ada" }, pair = false, state = "playing",
		feeders = {
			{ id = "A", kind = "lamp", n = 4, k = 5, grid = lampG.grid, set = lampG.set, solved = false, lockUntil = 0 },
			{ id = "B", kind = "shelf", N = 5, colors = sh.colors, secret = sh.secret, clues = sh.clues, order = sh.start,
				solved = false, lockUntil = 0 },
		},
		door = { id = "Door", kind = "door", L = 4, alphabet = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, secret = door.secret,
			lines = door.lines, hidden = door.hidden, feederOf = { [door.hidden[1]] = "A", [door.hidden[2]] = "B" },
			lit = {}, solved = false, lockUntil = 0, lastWrong = nil },
	}, door
end

local function walkKeys(v, path, bad, allow)
	if type(v) ~= "table" then return end
	for k, x in v do
		local kind = if type(k) == "number" then "#" else tostring(k)
		local here = path .. "." .. kind
		if type(k) ~= "number" and not allow[kind] then table.insert(bad, here) end
		walkKeys(x, here, bad, allow)
	end
end

local ALLOW = {}
for _, k in RoomView.KEYS do ALLOW[k] = true end

local room, door = makeRoom()
local now = 100
local v = RoomView.build(room, { wrong = false, hinted = true, handsOn = false }, now)
do
	local bad = {}
	walkKeys(v, "payload", bad, ALLOW)
	eq(#bad, 0, "every key of the payload is on RoomView.KEYS (" .. table.concat(bad, ", ") .. ")")
	for _, forbidden in { "secret", "set", "hidden", "feederOf", "lit", "rand", "colors", "lockUntil", "k" } do
		truthy(not ALLOW[forbidden], "'" .. forbidden .. "' is not an allowed key")
	end
end
eq(v.where, "room", "a room payload")
eq(#v.stations, 2, "two feeders")
eq(v.stations[1].kind, "lamp", "feeder A is the lamp grid")
eq(#v.stations[1].lamps, 16, "16 lamp states")
eq(v.stations[2].kind, "shelf", "feeder B is the shelf")
eq(#v.stations[2].flasks, 5, "5 flasks, in the current order")
eq(#v.stations[2].clues, #room.feeders[2].clues, "every clue sentence")
eq(v.stations[2].clues[1], Text.shelfClue(room.feeders[2].clues[1]), "clues are sentences")
eq(v.solved, 0, "nothing solved")
eq(v.total, 3, "three stations")
eq(v.door.enterable, false, "the keypad is dark while lines are dark")
eq(v.you.hinted, true, "your own hint flag")
do
	local dark, lit = 0, 0
	for i, ln in v.door.lines do
		if ln.dark then
			dark += 1
			eq(ln.guess, nil, "a dark line carries no guess")
			eq(ln.text, nil, "a dark line carries no sentence")
			truthy(ln.by == "A" or ln.by == "B", "a dark line names its feeder")
		else
			lit += 1
			eq(ln.guess, Text.codeGuess(door.lines[i].guess), "a lit line shows its guess")
			eq(ln.text, Text.codeSentence(door.lines[i].a, door.lines[i].b), "and its sentence")
		end
	end
	eq(dark, 2, "two dark lines (one per feeder)")
	eq(lit, #door.lines - 2, "the rest lit")
end
do
	-- nothing in the payload spells the secret code
	local secret = Text.codeGuess(door.secret)
	local found = false
	local function scan(x)
		if type(x) == "string" and string.find(x, secret, 1, true) then found = true end
		if type(x) == "table" then for _, y in x do scan(y) end end
	end
	scan(v)
	truthy(not found, "the secret code string appears nowhere in the payload")
end
-- the payload is a copy: mutating it never touches the room
v.stations[1].lamps[1] = not v.stations[1].lamps[1]
v.stations[2].flasks[1] = 99
truthy(room.feeders[1].grid[1] ~= v.stations[1].lamps[1], "lamps are copied")
truthy(room.feeders[2].order[1] ~= 99, "flasks are copied")

-- a solved feeder lights its line; all lit wakes the keypad; lockout shows remaining seconds
room.feeders[1].solved = true
room.door.lit[door.hidden[1]] = true
local v2 = RoomView.build(room, { wrong = false, hinted = false, handsOn = true }, now)
eq(v2.solved, 1, "one solved")
eq(v2.door.lines[door.hidden[1]].dark, nil, "the solved feeder's line is lit")
eq(v2.door.lines[door.hidden[1]].guess, Text.codeGuess(door.lines[door.hidden[1]].guess), "and shows its guess")
eq(v2.door.enterable, false, "still one dark line")
room.feeders[2].solved = true
room.door.lit[door.hidden[2]] = true
room.door.lockUntil = now + 6
room.door.lastWrong = { 1, 2, 3, 4 }
local v3 = RoomView.build(room, { wrong = true, hinted = false, handsOn = true }, now + 1)
eq(v3.door.enterable, true, "every line lit: the keypad wakes")
eq(v3.door.lockedFor, 5, "locked for the remaining 5 s")
eq(v3.door.lastWrong, "1 2 3 4", "the player's own wrong code shows while locked")
local v4 = RoomView.build(room, { wrong = true, hinted = false, handsOn = true }, now + 7)
eq(v4.door.lockedFor, 0, "the lockout ends")
eq(v4.door.lastWrong, nil, "and the wrong code clears")

-- outside a room
local a = RoomView.outside("atrium")
eq(a.where, "atrium", "an atrium payload")
local count = 0
for _ in a do count += 1 end
eq(count, 1, "and nothing else")

print(string.format("RoomView: %d passed, %d failed", passed, failed))
if failed > 0 then error("RoomView spec failed", 0) end
