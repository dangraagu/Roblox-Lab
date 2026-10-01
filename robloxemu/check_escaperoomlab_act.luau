-- Escape Room Lab — the Act remote, the only way a client acts on a room (DESIGN.md §12.4, §14.2, §16).
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_act.luau 2>&1
--
-- The client can fire Act with anything. What the server must do with it:
--   * anything the honest HUD cannot produce (wrong types, NaN, huge numbers, tables, extra arguments,
--     unknown stations or verbs) is dropped WITHOUT a word and changes nothing;
--   * every refusal an honest player can hit is answered in words: out of reach, already solved, locked
--     out, the hint cooldown, the hint cap, too fast;
--   * reach is measured by the server's own view of the root (12 studs);
--   * at most 10 actions a second get through, with one "Slow down." per 5 s;
--   * wrong tries on one station lock it for 3, 6, 12, then 20 s, and cost the Clean star;
--   * outside a room nothing is accepted.

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local w = Lib.boot({ name = "escape-room-lab-act" })
local h = w.h
local Config = w.Config
local p = Lib.player(w, "Probe", 8801)
local Act = w.R.Act
local function step() h:advance(0.1) end
local function notices() return #w.R.Notice:sentTo(p.plr) end
local function toastSince(n, needle)
	for _, pl in Lib.noticesSince(w, p.plr, n) do
		if string.find(tostring(pl.text), needle, 1, true) then return true end
	end
	return false
end
local function lamps()
	local rs = Lib.last(w, "RoomState", p.plr)
	local s = {}
	for i, v in rs.stations[1].lamps do s[i] = if v then "1" else "0" end
	return table.concat(s)
end

--============================================================ outside a room nothing is accepted
local n0 = notices()
Act:simulateFireServer(p.plr, "A", "press", 1)
step()
eq(notices(), n0, "an Act from the Atrium changes nothing and says nothing (no room to act on)")

Lib.intoSoloLift(w, p)
h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
local rs = Lib.last(w, "RoomState", p.plr)
eq(rs.slot, 1, "in room 1")

--============================================================ malformed: silent and harmless
Lib.standNear(w, p, "A")
step()
local before, nB, stateSends = lamps(), notices(), #w.R.RoomState:sentTo(p.plr)
local junk = {
	{ 1, "press", 1 }, { "A", 7, 1 }, { "A", "press", 0 / 0 }, { "A", "press", 1e9 }, { "A", "press", 0 },
	{ "A", "press", 1.5 }, { "A", "press", "1" }, { "A", "press", { 1 } }, { "A", "press", 1, 2 },
	{ "A", "swap", 1, 2 }, { "A", "enter", { 1, 2, 3 } }, { "Z", "press", 1 }, { "A", "explode" },
	{ string.rep("A", 40), "press", 1 }, { "Door", "enter", { 1, 1, 2 } }, { "Door", "enter", { 1, 2 } },
	{ "Door", "enter", { 0, 7, 9 } }, { "Door", "enter", "123" }, { "Door", "enter", { 1, 2, 3 }, 4 },
	{ "A", "hint", 1 },
}
for i, args in junk do
	Act:simulateFireServer(p.plr, table.unpack(args))
	if i % 8 == 0 then h:advance(1) end -- stay under the rate limit: this is about shapes, not speed
end
step()
eq(lamps(), before, #junk .. " malformed Acts: the lamps are untouched")
eq(notices(), nB, "and not one of them got a toast (the honest HUD cannot produce them)")
eq(#w.R.RoomState:sentTo(p.plr), stateSends, "and no state was even re-sent")

--============================================================ reach, by the server's view of the root
h:advance(1.2)
p.hrp.CFrame = CFrame.new(Lib.origin(w, p.plr) + Vector3.new(10, 3, 0)) -- 25.8 studs from station A
local nR = notices()
Act:simulateFireServer(p.plr, "A", "press", 1)
step()
truthy(toastSince(nR, "Walk up to the station."), "out of reach: told to walk up")
eq(lamps(), before, "and nothing pressed")

--============================================================ the rate limit: 10 a second
Lib.standNear(w, p, "A")
h:advance(1.2)
local nS = notices()
local pressed0 = lamps()
for _ = 1, 31 do Act:simulateFireServer(p.plr, "A", "press", 5) end -- the centre, 31 times in one instant
step()
-- 31 presses of the same lamp flip it 31 times (odd); 10 get through (even): unchanged means 10 (or 0)
eq(lamps(), pressed0, "31 presses in one instant: an even number got through (the bucket holds 10)")
truthy(toastSince(nS, "Slow down."), "and the player is told to slow down")
local slowCount = 0
for _, pl in Lib.noticesSince(w, p.plr, nS) do if pl.text == "Slow down." then slowCount += 1 end end
eq(slowCount, 1, "once, not 21 times")
h:advance(2)
Act:simulateFireServer(p.plr, "A", "press", 5)
step()
truthy(lamps() ~= pressed0, "after a pause one press goes through again")
Act:simulateFireServer(p.plr, "A", "press", 5)
step()

--============================================================ hints: cooldown and cap, in words
local nH = notices()
Act:simulateFireServer(p.plr, "A", "hint")
step()
local hint = Lib.last(w, "Hint", p.plr)
truthy(hint and hint.lamp, "a lamp hint names a lamp: " .. tostring(hint and hint.text))
Act:simulateFireServer(p.plr, "A", "hint")
step()
truthy(toastSince(nH, "No more hints here"), "room 1's grid (k 2) allows 1 hint: the cap is said in words")
-- the cooldown is per player across stations: the door (cap 2) inside 20 s is told to wait
Lib.standNear(w, p, "Door")
local nH2 = notices()
Act:simulateFireServer(p.plr, "Door", "hint")
step()
truthy(toastSince(nH2, "Next hint in"), "a second hint inside 20 s: told how long to wait")
h:advance(Config.Hints.CooldownSeconds + 0.5)
Act:simulateFireServer(p.plr, "Door", "hint")
step()
local dh = Lib.last(w, "Hint", p.plr)
truthy(dh and dh.station == "Door" and string.match(dh.text, "^Digit %d is %d%.$") ~= nil, "after the cooldown the door hint names a digit: "
	.. tostring(dh and dh.text))
Lib.standNear(w, p, "A")

--============================================================ solve A, then "Already solved."
local grid, size = Lib.readLamps(w, p, "A")
for _, i in w.mod("Lamps").solve(grid, size) do
	Act:simulateFireServer(p.plr, "A", "press", i)
	step()
end
local nD = notices()
Act:simulateFireServer(p.plr, "A", "press", 1)
step()
truthy(toastSince(nD, "Already solved."), "a press on a solved grid: Already solved.")

--============================================================ the lockout ladder on the door
local lines = Lib.readDoor(w, p)
local L = Lib.last(w, "RoomState", p.plr).door
local CodeLock = w.mod("CodeLock")
local right = CodeLock.solve(lines, L.L, L.alphabet)[1]
local wrongs = {}
for _, code in CodeLock.space(L.L, L.alphabet) do
	if not CodeLock.equal(code, right) and #wrongs < 5 then table.insert(wrongs, table.clone(code)) end
end
Lib.standNear(w, p, "Door")
local ladder = {}
for i = 1, 5 do
	Act:simulateFireServer(p.plr, "Door", "enter", wrongs[i])
	step()
	local lf = Lib.last(w, "RoomState", p.plr).door.lockedFor
	table.insert(ladder, lf)
	local nL = notices()
	Act:simulateFireServer(p.plr, "Door", "enter", right)
	step()
	truthy(toastSince(nL, "Locked for"), "wrong try " .. i .. ": the right code during the lockout is refused, in words")
	h:advance(lf + 0.1)
end
eq(table.concat(ladder, ","), "3,6,12,20,20", "the lockout ladder: 3, 6, 12, 20, then 20 s")
eq(Lib.last(w, "RoomState", p.plr).you.wrong, true, "the wrong tries cost the Clean star")
local nE = notices()
Act:simulateFireServer(p.plr, "Door", "enter", right)
step()
local esc = Lib.noticesSince(w, p.plr, nE, "escape")[1]
eq(esc and esc.stars, 1, "escaped with 1 star: a wrong try and a hint")
truthy(esc and #esc.reasons == 2, "and told which two stars were missed and why")

t.finish("escape-room-lab act", h)
