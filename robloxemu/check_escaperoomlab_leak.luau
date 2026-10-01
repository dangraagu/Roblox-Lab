-- Escape Room Lab — nothing an answer is made of replicates before its solve reveals it (DESIGN.md §12).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_leak.luau 2>&1
--
-- The server keeps every answer in its script's memory. This asks everything a client could read —
-- every Instance under Workspace, ReplicatedStorage and Players (names, texts, prompt texts, values,
-- attributes, disabled or not, visible or not) AND every payload any remote handed any client — at
-- the moments that matter, and searches it for the answer the NEXT solve reveals:
--   * the attribute allowlist is EMPTY: no Instance anywhere carries an attribute (fork-tower REVIEW-3:
--     an exact list, so a leak moved onto a new name or a BillboardGui still fails);
--   * every payload's keys are on its allowlist (RoomState: RoomView.KEYS; the others, listed below);
--   * a feeder's hidden door line (its guess, e.g. "0 2 6") appears nowhere before that feeder is solved;
--   * the door code appears nowhere (as "4 8 1" or as [4,8,1]) before it is entered;
--   * the shelf's answer order appears nowhere before it is arranged.
-- A control: the same search FINDS each answer right after its reveal, so a search that finds nothing
-- because it looks nowhere cannot pass.

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local w = Lib.boot({ name = "escape-room-lab-leak" })
local h, ws, RS = w.h, w.ws, w.RS
local Text, RoomView = w.mod("Text"), w.mod("RoomView")
local p = Lib.player(w, "Snoop", 6601)
local players = h.Players

local function serial(v, depth)
	depth = depth or 0
	if type(v) == "table" then
		if depth > 8 then return "{...}" end
		local isArray = #v > 0
		local parts = {}
		if isArray then
			for _, x in ipairs(v) do table.insert(parts, serial(x, depth + 1)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in v do table.insert(keys, tostring(k)) end
		table.sort(keys)
		for _, k in keys do table.insert(parts, k .. "=" .. serial(v[k] == nil and v[tonumber(k)] or v[k], depth + 1)) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end

-- Payloads are searched from the moment the current room began: an EARLIER room's door line can be the
-- same three digits as a later room's code by pure chance (every room draws from a fresh engine-seeded
-- Random). The first sweep's CONTROL caught exactly that false positive (a "5 4 3" line in an earlier
-- room), so the history is scoped per room. The world itself only ever holds the current room.
local marks = {}
local attrSeen = {}
local function snapshot(): string
	local out = {}
	local function add(s) if type(s) == "string" and s ~= "" then table.insert(out, s) end end
	for _, root in { ws, RS, players } do
		for _, d in root:GetDescendants() do
			add(d.Name)
			for _, prop in { "Text", "ActionText", "ObjectText", "Value" } do
				local ok, v = pcall(function() return d[prop] end)
				if ok and v ~= nil then add(tostring(v)) end
			end
			local attrs = d:GetAttributes()
			for k, v in attrs do
				attrSeen[d:GetFullName() .. "@" .. tostring(k)] = true
				add(tostring(k) .. "=" .. tostring(v))
			end
		end
	end
	for _, r in RS.LabRemotes:GetChildren() do
		if r:IsA("RemoteEvent") then
			local sent = r:getSent()
			for i = (marks[r] or 0) + 1, #sent do add(serial(sent[i].args)) end
		end
	end
	return table.concat(out, "\n")
end
local function has(snap, needle) return string.find(snap, needle, 1, true) ~= nil end

local function step() h:advance(0.1) end
local rooms, lineChecks, doorChecks, shelfChecks, controls = 0, 0, 0, 0, 0

-- play rooms 1-8 (Reception, the Archive, into the Greenhouse): every kind of feeder, 1 and 2 feeders
Lib.intoSoloLift(w, p)
h:advance(w.Config.Lift.BoardSeconds + w.Config.Lift.RideSeconds + 1)
for _ = 1, 8 do
	local rs = Lib.last(w, "RoomState", p.plr)
	-- the room began with the first RoomState of its roomId: search from there on
	for _, r in RS.LabRemotes:GetChildren() do
		if r:IsA("RemoteEvent") then
			local sent = r:getSent()
			local from = #sent
			if r.Name == "RoomState" then
				for i = #sent, 1, -1 do
					local a = sent[i].args[1]
					if type(a) == "table" and a.roomId == rs.roomId then from = i - 1 else break end
				end
			end
			marks[r] = from
		end
	end
	rooms += 1
	local board = Lib.zone(w, p.plr):FindFirstChild("DoorBoard", true)
	local function rowGuesses()
		local g = {}
		for i = 1, 6 do g[i] = Lib.labelText(board, "RowGuess_" .. i) end
		return g
	end
	for _, st in rs.stations do
		local before = snapshot()
		local rowsBefore = rowGuesses()
		local shelfAnswer = nil
		if st.kind == "shelf" then
			local order, clues = Lib.readShelf(w, p, st.id)
			local target = w.mod("Shelf").solve(order, clues)[1]
			shelfAnswer = target
		end
		Lib.solveStation(w, p, st, step)
		step()
		local after = snapshot()
		-- the line this feeder lit: the row whose guess changed from "? ? ?"
		local rowsAfter = rowGuesses()
		local revealed = nil
		for i = 1, 6 do
			if rowsBefore[i] ~= rowsAfter[i] and rowsAfter[i] and not string.find(rowsAfter[i], "?", 1, true) then revealed = rowsAfter[i] end
		end
		truthy(revealed ~= nil, string.format("room %d: solving %s lit a door line", rs.slot, st.id))
		if revealed then
			lineChecks += 1
			truthy(not has(before, revealed), string.format("room %d: the hidden line %q appeared nowhere before %s was solved", rs.slot, revealed, st.id))
			if has(after, revealed) then controls += 1 end
		end
		if shelfAnswer then
			shelfChecks += 1
			local letters = {}
			for i, c in shelfAnswer do letters[i] = Text.FlaskLetters[c] end
			truthy(not has(before, serial(shelfAnswer)), string.format("room %d: the shelf's answer %s was nowhere before it was arranged",
				rs.slot, table.concat(letters)))
			if has(after, serial(shelfAnswer)) then controls += 1 end
		end
	end
	local lines = Lib.readDoor(w, p)
	local codes = w.mod("CodeLock").solve(lines, rs.door.L, rs.door.alphabet)
	local before = snapshot()
	local spaced = Text.codeGuess(codes[1])
	doorChecks += 1
	-- The code's ARRAY form is not searched inside a shelf's public `flasks` field: colours are 1-5, so a 3-flask
	-- order such as [1,4,3] can equal a 3-digit code by pure chance (review-1 sweep: one false positive in
	-- about 140 runs, room 2, code 1 4 3). Everything else, and the code's text form everywhere, is searched.
	local beforeNoFlasks = string.gsub(before, "flasks=%[[%d,]*%]", "flasks=[]")
	truthy(not has(before, spaced) and not has(beforeNoFlasks, serial(codes[1])),
		string.format("room %d: the door code %s appeared nowhere before it was entered", rs.slot, spaced))
	Lib.standNear(w, p, "Door")
	w.R.Act:simulateFireServer(p.plr, "Door", "enter", codes[1])
	step()
	-- the door code has no reveal: the server only ever judges it, never shows it. The search that looked
	-- for it is the same one the line and shelf controls prove can see (and the S5 mutant, the code as an
	-- attribute, is caught by exactly this assertion: EYECANDY.md §7).
	eq(Lib.last(w, "RoomState", p.plr).state, "escaped", string.format("room %d: the code read off the board opened the door", rs.slot))
	Lib.next(w, p)
	h:advance(w.Config.Lift.RideSeconds + 0.5)
end

--============================================================ the attribute allowlist is empty
snapshot()
local attrs = {}
for k in attrSeen do table.insert(attrs, k) end
eq(#attrs, 0, "no Instance under Workspace, ReplicatedStorage or Players carries an attribute (" .. table.concat(attrs, ", ") .. ")")

--============================================================ payload key allowlists, on the real wire
local ALLOW = {
	RoomState = RoomView.KEYS,
	-- "lift" (review-1 A2): which Atrium lift is leaving, "solo" or "pair", so the rider's client shuts its own doors
	Notice = { "kind", "text", "slot", "wing", "room", "wingName", "stars", "reasons", "roof", "first", "lift" },
	Profile = { "stars", "best", "frontier", "continue", "escaped", "canSave", "loaded" },
	Hint = { "station", "text", "lamp" },
	Open = { "station" },
	Board = { "mode", "rows", "message", "loading", "rank", "name", "stars", "you" },
}
local keyBad, payloads = {}, 0
for name, keys in ALLOW do
	local ok = {}
	for _, k in keys do ok[k] = true end
	local function walk(v, path, isBest)
		if type(v) ~= "table" then return end
		for k, x in v do
			if type(k) ~= "number" and not ok[k] and not isBest then table.insert(keyBad, name .. path .. "." .. tostring(k)) end
			walk(x, path .. "." .. tostring(k), k == "best")
		end
	end
	for _, rec in RS.LabRemotes:FindFirstChild(name):getSent() do
		payloads += 1
		walk(rec.args[1], "", false)
	end
end
eq(#keyBad, 0, "every payload key is on its allowlist (" .. table.concat(keyBad, ", ") .. ")")

print(string.format("  %d rooms, %d payloads walked; %d hidden lines, %d door codes, %d shelf orders searched for; %d controls found their answer after the reveal",
	rooms, payloads, lineChecks, doorChecks, shelfChecks, controls))
truthy(lineChecks >= 10 and doorChecks == 8 and shelfChecks >= 4, "the search covered every kind of answer")
truthy(controls >= lineChecks + shelfChecks, "CONTROL: after each reveal the same search finds the answer (it is not blind)")
t.finish("escape-room-lab leak", h)
