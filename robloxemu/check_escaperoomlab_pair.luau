-- Escape Room Lab — the Pair Lift: two players, one room (DESIGN.md §4.3, §4.4).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_pair.luau 2>&1
--
--   * it leaves only when two players on the two pads BOTH press GO within 10 s, after a 3 s countdown;
--     one press is told it needs a partner; a third player is told it is full;
--   * both play one room: a lamp press by one shows in the other's state;
--   * the lockout belongs to the station: one player's wrong code locks the keypad for both;
--   * the hands-on rule: a player who completed no station earns no stars (the escape still advances
--     them); a hint goes to its taker only and never into the world;
--   * NEXT waits for every member in the exit cab; leaving is one prompt and the other carries on solo,
--     from then on without the hands-on rule; a reset mid-room lands on AtriumSpawn and leaves the room;
--   * review-1 A4: a wrong try or a hint costs the Clean or Unaided star of EVERYONE in the room (the hint
--     text still goes to its taker only), and the mark stays with whoever carries on: one partner can no
--     longer absorb them and hand the other a clean code for 3 stars.

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local w = Lib.boot({ name = "escape-room-lab-pair" })
local h, ws = w.h, w.ws
local Config, W = w.Config, w.Config.World
local a = Lib.player(w, "Ann", 7101)
local b = Lib.player(w, "Ben", 7102)
local c = Lib.player(w, "Cal", 7103)
local go = ws.Atrium.PairGo:FindFirstChildOfClass("ProximityPrompt")
local function step() h:advance(0.1) end
local function toastSince(plr, n, needle)
	for _, pl in Lib.noticesSince(w, plr, n) do
		if string.find(tostring(pl.text), needle, 1, true) then return true end
	end
	return false
end
local function padPos(i) return Vector3.new(W.PairCab[1] + (if i == 1 then -W.PairPadDX else W.PairPadDX), 3.5, W.PairCab[2]) end

--============================================================ the Pair Lift
a.hrp.CFrame = CFrame.new(padPos(1))
local n = #w.R.Notice:sentTo(a.plr)
go.Triggered:Fire(a.plr)
step()
truthy(toastSince(a.plr, n, "needs two players"), "one GO: told the Pair Lift needs two players who both press GO")
b.hrp.CFrame = CFrame.new(padPos(1) + Vector3.new(0.5, 0, 0))
n = #w.R.Notice:sentTo(b.plr)
go.Triggered:Fire(b.plr)
step()
-- review-1 A1: "full" is for a third player while a ride counts down; a player on the same pad as a GO is
-- sent to the other pad (an idle player on a pad must never block anyone: check_escaperoomlab_lifts §6)
truthy(toastSince(b.plr, n, "other pad"), "a second player on the SAME pad is sent to the other pad")
truthy(not toastSince(b.plr, n, "full"), "and is not told the Pair Lift is full")
b.hrp.CFrame = CFrame.new(padPos(2))
c.hrp.CFrame = CFrame.new(W.PairCab[1], 3.5, W.PairCab[2] + 2.5)
n = #w.R.Notice:sentTo(c.plr)
go.Triggered:Fire(c.plr)
step()
truthy(toastSince(c.plr, n, "Stand on a pad"), "GO off the pads says where to stand")
go.Triggered:Fire(b.plr)
step()
h:advance(Config.Lift.PairCountdownSeconds + Config.Lift.RideSeconds + 1)
local ra, rb = Lib.last(w, "RoomState", a.plr), Lib.last(w, "RoomState", b.plr)
truthy(ra and rb and ra.where == "room" and rb.where == "room", "both GO presses inside 10 s: the Pair Lift leaves with both")
eq(ra and ra.roomId, rb and rb.roomId, "one room for both")
eq(ra and ra.pair, true, "a pair room")
eq(ra and #ra.members, 2, "two members")
eq(Lib.last(w, "RoomState", c.plr) and Lib.last(w, "RoomState", c.plr).where or "atrium", "atrium", "the third player stayed")

--============================================================ shared state, shared lockout, the hands-on rule
local st = ra.stations[1]
eq(st.kind, "lamp", "room 1's feeder is the lamp grid")
local grid, size = Lib.readLamps(w, a, st.id)
local presses = w.mod("Lamps").solve(grid, size)
Lib.standNear(w, a, st.id)
Lib.standNear(w, b, st.id)
w.R.Act:simulateFireServer(a.plr, st.id, "press", presses[1])
step()
local lampsB = Lib.last(w, "RoomState", b.plr).stations[1].lamps
local lampsA = Lib.last(w, "RoomState", a.plr).stations[1].lamps
eq(table.concat((function() local s = {} for i, v in lampsB do s[i] = tostring(v) end return s end)(), ","),
	table.concat((function() local s = {} for i, v in lampsA do s[i] = tostring(v) end return s end)(), ","),
	"Ann's press shows in Ben's room state too")
-- Ben finishes the grid: Ben is hands-on, Ann's press did not complete it
for i = 2, #presses do
	w.R.Act:simulateFireServer(b.plr, st.id, "press", presses[i])
	step()
end
truthy(Lib.last(w, "RoomState", a.plr).stations[1].solved, "the grid is solved")
-- Ann enters a wrong code: the keypad locks for BOTH
local lines = Lib.readDoor(w, a)
local rsA = Lib.last(w, "RoomState", a.plr)
local codes = w.mod("CodeLock").solve(lines, rsA.door.L, rsA.door.alphabet)
local wrong = nil
for _, code in w.mod("CodeLock").space(rsA.door.L, rsA.door.alphabet) do
	if not w.mod("CodeLock").equal(code, codes[1]) then wrong = table.clone(code); break end
end
Lib.standNear(w, a, "Door")
Lib.standNear(w, b, "Door")
w.R.Act:simulateFireServer(a.plr, "Door", "enter", wrong)
step()
eq(Lib.last(w, "RoomState", b.plr).door.lockedFor, 3, "Ann's wrong code locks the keypad for Ben too: 3 s")
n = #w.R.Notice:sentTo(b.plr)
w.R.Act:simulateFireServer(b.plr, "Door", "enter", codes[1])
step()
truthy(toastSince(b.plr, n, "Locked for"), "Ben's code during the lockout is refused, in words")
eq(Lib.last(w, "RoomState", b.plr).door.solved, false, "and does not open the door")
h:advance(3)
local na, nb = #w.R.Notice:sentTo(a.plr), #w.R.Notice:sentTo(b.plr)
w.R.Act:simulateFireServer(b.plr, "Door", "enter", codes[1])
step()
local escA = Lib.noticesSince(w, a.plr, na, "escape")[1]
local escB = Lib.noticesSince(w, b.plr, nb, "escape")[1]
-- review-1 A4: a wrong try or a hint costs the Clean or Unaided star of everyone in the room, or one
-- partner could absorb them and hand the other a clean code (carrying)
eq(escB and escB.stars, 2, "Ben (hands-on, unaided; Ann's wrong code cost the pair's Clean star): 2 stars")
truthy(escB and escB.reasons and string.find(table.concat(escB.reasons, " "), "wrong try in your pair", 1, true) ~= nil,
	"Ben is told why: " .. tostring(escB and escB.reasons and table.concat(escB.reasons, " ")))
eq(escA and escA.stars, 0, "Ann (completed no station): 0 stars, the hands-on rule")
truthy(escA and escA.reasons and string.find(escA.reasons[1] or "", "complete a station", 1, true) ~= nil,
	"Ann is told why: " .. tostring(escA and escA.reasons and escA.reasons[1]))
eq(Lib.last(w, "Profile", a.plr).frontier, 2, "Ann's escape still advances her frontier to room 2")
eq(a.plr.leaderstats.Stars.Value, 0, "Ann's leaderstats: 0")
eq(b.plr.leaderstats.Stars.Value, 2, "Ben's leaderstats: 2")

--============================================================ NEXT waits for everyone
local o = Lib.origin(w, a.plr)
a.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3.5, -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)))
b.hrp.CFrame = CFrame.new(o + Vector3.new(0, 3, 0))
n = #w.R.Notice:sentTo(a.plr)
Lib.zone(w, a.plr):FindFirstChild("NextPanel", true):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.plr)
step()
truthy(toastSince(a.plr, n, "Waiting for Ben"), "NEXT with Ben outside the cab: Waiting for Ben.")
b.hrp.CFrame = CFrame.new(o + Vector3.new(1.5, 3.5, -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)))
Lib.zone(w, a.plr):FindFirstChild("NextPanel", true):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.plr)
h:advance(Config.Lift.RideSeconds + 1)
local r2a, r2b = Lib.last(w, "RoomState", a.plr), Lib.last(w, "RoomState", b.plr)
eq(r2a.slot, 2, "both frontiers are room 2 (Ann's carried escape still counts): the pair rides on to room 2")
eq(r2a.roomId, r2b.roomId, "together")

--============================================================ a hint goes to its taker only
local shelf = r2a.stations[1]
eq(shelf.kind, "shelf", "room 2's feeder is the flask shelf")
Lib.standNear(w, a, shelf.id)
Lib.standNear(w, b, shelf.id)
local hintsB = #w.R.Hint:sentTo(b.plr)
w.R.Act:simulateFireServer(a.plr, shelf.id, "hint")
step()
local hint = Lib.last(w, "Hint", a.plr)
truthy(hint and type(hint.text) == "string" and string.find(hint.text, "goes in slot", 1, true) ~= nil, "Ann's hint: " .. tostring(hint and hint.text))
eq(#w.R.Hint:sentTo(b.plr), hintsB, "Ben receives no hint")
local inWorld = false
for _, d in ws:GetDescendants() do
	local ok, txt = pcall(function() return d.Text end)
	if ok and txt == (hint and hint.text) then inWorld = true end
end
eq(inWorld, false, "the hint is nowhere in the world")
eq(Lib.last(w, "RoomState", a.plr).you.hinted, true, "Ann's Unaided star is gone")
eq(Lib.last(w, "RoomState", b.plr).you.hinted, true, "and so is Ben's (review-1 A4: the pair shares the Unaided star; the hint text still went to Ann only)")

--============================================================ one leaves, the other carries on solo
local leave = Lib.zone(w, b.plr):FindFirstChild("LeaveEntry", true):FindFirstChildOfClass("ProximityPrompt")
b.hrp.CFrame = CFrame.new(Lib.origin(w, b.plr) + Vector3.new(0, 3.5, W.RoomHalf + W.Wall + W.CabHalf))
n = #w.R.Notice:sentTo(a.plr)
leave.Triggered:Fire(b.plr)
step()
eq(Lib.last(w, "RoomState", b.plr).where, "atrium", "ATRIUM takes Ben home")
truthy(toastSince(a.plr, n, "Carry on solo"), "Ann is told she carries on solo")
eq(Lib.last(w, "RoomState", a.plr).pair, false, "her room is solo now: the hands-on rule no longer applies")
na = #w.R.Notice:sentTo(a.plr)
Lib.solveRoom(w, a, step)
local esc2 = Lib.noticesSince(w, a.plr, na, "escape")[1]
eq(esc2 and esc2.stars, 2, "Ann escapes room 2 alone: 2 stars (she took a hint)")

--============================================================ a reset mid-room
-- a fresh pair: Ann (frontier 3) and Cal (frontier 1) ride to the LOWER Continue, room 1
Lib.next(w, a) -- Ann rides on alone first, then goes home to pair up
h:advance(Config.Lift.RideSeconds + 1)
local leave3 = Lib.zone(w, a.plr):FindFirstChild("LeaveEntry", true):FindFirstChildOfClass("ProximityPrompt")
a.hrp.CFrame = CFrame.new(Lib.origin(w, a.plr) + Vector3.new(0, 3.5, W.RoomHalf + W.Wall + W.CabHalf))
leave3.Triggered:Fire(a.plr)
step()
a.hrp.CFrame = CFrame.new(padPos(1))
c.hrp.CFrame = CFrame.new(padPos(2))
go.Triggered:Fire(a.plr)
go.Triggered:Fire(c.plr)
h:advance(Config.Lift.PairCountdownSeconds + Config.Lift.RideSeconds + 1)
local rc = Lib.last(w, "RoomState", c.plr)
eq(rc.where, "room", "Ann and Cal are in a room")
eq(rc.slot, 1, "the lower Continue: Cal's room 1")
local nc = #w.R.Notice:sentTo(a.plr)
local char2 = h.Players:simulateSpawn(a.plr, ws)
step()
local hrp2 = char2:FindFirstChild("HumanoidRootPart")
local sp = ws.Atrium.AtriumSpawn
truthy(math.abs(hrp2.Position.X - sp.Position.X) < 0.01 and math.abs(hrp2.Position.Z - sp.Position.Z) < 0.01,
	"Ann's reset lands on AtriumSpawn")
eq(Lib.last(w, "RoomState", a.plr).where, "atrium", "and takes her out of the room")
truthy(toastSince(a.plr, nc, "Your stars are safe"), "told: You left the room. Your stars are safe.")
local rc2 = Lib.last(w, "RoomState", c.plr)
eq(rc2.where, "room", "Cal's room keeps running")
eq(rc2.pair, false, "Cal carries on solo")
eq(#rc2.members, 1, "one member left")

--============================================================ carrying is closed (review-1 A4)
-- Before: stars were per player for Clean and Unaided too, so one partner could take every hint and every
-- wrong try and the other, with ONE action (entering the code worked out for them), got all 3 stars (the
-- reviewer's probe: 9 stars in 3 rooms for 3 Act calls). Now a wrong try or a hint marks everyone in the
-- room, and the mark stays with the one who carries on if the other leaves.
local d = Lib.player(w, "Dee", 7104)
local e = Lib.player(w, "Eli", 7105)
h:advance(1)
d.hrp.CFrame = CFrame.new(padPos(1))
e.hrp.CFrame = CFrame.new(padPos(2))
go.Triggered:Fire(d.plr)
go.Triggered:Fire(e.plr)
h:advance(Config.Lift.PairCountdownSeconds + Config.Lift.RideSeconds + 1)
local rd = Lib.last(w, "RoomState", d.plr)
eq(rd and rd.where, "room", "Dee and Eli are in a pair room")
eq(rd and rd.slot, 1, "room 1")
local eliActs = 0
do
	-- Dee: the station, a hint at the door, a wrong code
	for _, s in rd.stations do Lib.solveStation(w, d, s, step) end
	Lib.standNear(w, d, "Door")
	Lib.standNear(w, e, "Door")
	w.R.Act:simulateFireServer(d.plr, "Door", "hint")
	step()
	local rsD = Lib.last(w, "RoomState", d.plr)
	local codesD = w.mod("CodeLock").solve(Lib.readDoor(w, d), rsD.door.L, rsD.door.alphabet)
	local wrongD = nil
	for _, code in w.mod("CodeLock").space(rsD.door.L, rsD.door.alphabet) do
		if not w.mod("CodeLock").equal(code, codesD[1]) then wrongD = table.clone(code); break end
	end
	w.R.Act:simulateFireServer(d.plr, "Door", "enter", wrongD)
	step()
	h:advance(Config.Stars.Lockout[1] + 0.2)
	-- Eli: one action, the code Dee worked out
	local nd, ne = #w.R.Notice:sentTo(d.plr), #w.R.Notice:sentTo(e.plr)
	eliActs += 1
	w.R.Act:simulateFireServer(e.plr, "Door", "enter", codesD[1])
	step()
	local escD = Lib.noticesSince(w, d.plr, nd, "escape")[1]
	local escE = Lib.noticesSince(w, e.plr, ne, "escape")[1]
	print(string.format("  carrying: Eli made %d Act call -> %s stars; Dee (the station, the hint, the wrong code) -> %s stars",
		eliActs, tostring(escE and escE.stars), tostring(escD and escD.stars)))
	eq(escE and escE.stars, 1, "Eli, who only entered the code Dee worked out after her hint and wrong try: 1 star (Escaped)")
	eq(escD and escD.stars, 1, "Dee: 1 star (Escaped)")
end
-- the mark stays when the partner who earned it leaves
do
	local o = Lib.origin(w, d.plr)
	local zc = -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)
	d.hrp.CFrame = CFrame.new(o + Vector3.new(-1.5, 3.5, zc))
	e.hrp.CFrame = CFrame.new(o + Vector3.new(1.5, 3.5, zc))
	Lib.zone(w, d.plr):FindFirstChild("NextPanel", true):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(d.plr)
	h:advance(Config.Lift.RideSeconds + 1)
	local r2 = Lib.last(w, "RoomState", e.plr)
	eq(r2 and r2.slot, 2, "the pair rides on to room 2")
	local shelf2 = r2.stations[1]
	Lib.standNear(w, d, shelf2.id)
	h:advance(Config.Hints.CooldownSeconds + 0.5)
	w.R.Act:simulateFireServer(d.plr, shelf2.id, "hint")
	step()
	local nd = #w.R.Notice:sentTo(d.plr)
	w.R.Act:simulateFireServer(d.plr, shelf2.id, "test")
	step()
	truthy(toastSince(d.plr, nd, "Not that order"), "Dee tests a wrong order")
	eq(Lib.last(w, "RoomState", e.plr).you.wrong, true, "Eli's Clean star is gone with Dee's wrong try")
	eq(Lib.last(w, "RoomState", e.plr).you.hinted, true, "and his Unaided star with Dee's hint")
	-- Dee leaves; Eli finishes alone
	local leaveD = Lib.zone(w, d.plr):FindFirstChild("LeaveEntry", true):FindFirstChildOfClass("ProximityPrompt")
	d.hrp.CFrame = CFrame.new(Lib.origin(w, d.plr) + Vector3.new(0, 3.5, W.RoomHalf + W.Wall + W.CabHalf))
	leaveD.Triggered:Fire(d.plr)
	step()
	eq(Lib.last(w, "RoomState", e.plr).pair, false, "Dee left: Eli carries on solo")
	h:advance(Config.Stars.Lockout[1] + 0.2)
	local ne = #w.R.Notice:sentTo(e.plr)
	Lib.solveRoom(w, e, step)
	local esc = Lib.noticesSince(w, e.plr, ne, "escape")[1]
	eq(esc and esc.stars, 1, "Eli escapes room 2 alone after Dee's hint and wrong try: 1 star, the marks stayed")
end

t.finish("escape-room-lab pair", h)
