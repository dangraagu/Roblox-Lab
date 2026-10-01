-- Escape Room Lab — the lifts and the Roof: regressions from the adversarial review of 2026-10-01.
-- Run: py -3 wrap.py --game ../escape-room-lab --out build/escape-room-lab.luau
--      luau check_escaperoomlab_lifts.luau 2>&1
--
--   1. Two players in the Solo Lift each ride to their OWN room. Before the fix a second player standing
--      in the cab ("One at a time") held everyone in the Atrium: a griefer could block every solo ride.
--   2. The Solo Lift's doorway is never shut for anyone else (review-1 A2): three players riding on a loop
--      for 60 s never put anything collidable in it on the server. The doors are the RIDER's own (a local
--      part made by Lab.client for its own ride: tests/walk.luau).
--   3. The ATRIUM buttons in a room's two cabs need a short hold: on arrival the entry cab's ATRIUM
--      button is the only prompt in reach (3.8 studs), and a stray tap must not throw the room away.
--   4. A pair rides NEXT from room 15: both reach the Roof with the brag card, and nobody is told the
--      other "went back to the Atrium" (the party used to be taken apart one member at a time).
--   5. A solo escapee who takes ATRIUM from room 15's exit cab and then the Atrium's Roof door still gets
--      the brag moment: the card, and every other player hears about it. Once, never twice.
-- Review-1 (2026-10-01), each red on the build it closed:
--   6. An idle player standing on a Pair Lift pad never blocks a pair (A1); a GO from one of the departing
--      pair is told the lift is leaving, not that it is full.
--   7. A Solo rider who leaves the cab during the ride stays behind and is told why (A2).
--   8. A pair partner who walks away during the ride stays behind; the other rides on solo (B2).
--   9. NEXT goes dark as the lift leaves; a second press is never told "The door is still shut." (B3).

local Lib = require("./check_escaperoomlab_lib")
local t = Lib.counter()
local eq, truthy = t.eq, t.truthy

local best14 = {}
for s = 1, 14 do best14[tostring(s)] = 3 end
local function vet() return { v = 1, best = table.clone(best14), starsAt = 1790000000, escapedAt = 0, boarded = 0, rooms = 14 } end
local w = Lib.boot({ name = "escape-room-lab-lifts", preload = { [8101] = vet(), [8102] = vet(), [8103] = vet() } })
local h, ws, Config = w.h, w.ws, w.Config
local W = Config.World
local function step() h:advance(0.1) end
local function texts(plr, n)
	local out = {}
	for _, p in Lib.noticesSince(w, plr, n) do table.insert(out, tostring(p.text)) end
	return out
end
local function zoneOf(p)
	local rs = Lib.last(w, "RoomState", p.plr)
	if rs and rs.where == "room" and rs.origin then return Lib.zone(w, p.plr) end
	return nil
end
local function hasText(list, needle)
	for _, s in list do if string.find(s, needle, 1, true) then return true end end
	return false
end

--============================================================ 1. two in the Solo Lift
local v = Lib.player(w, "Victim", 6401)
local g = Lib.player(w, "Griefer", 6402)
h:advance(1)
local nv, ng = #w.R.Notice:sentTo(v.plr), #w.R.Notice:sentTo(g.plr)
g.hrp.CFrame = CFrame.new(W.SoloCab[1] + 2, 3.5, W.SoloCab[2])
Lib.intoSoloLift(w, v)
h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
local rv, rg = Lib.last(w, "RoomState", v.plr), Lib.last(w, "RoomState", g.plr)
eq(rv and rv.where, "room", "with a second player in the Solo Lift, the first still rides to a room")
eq(rg and rg.where, "room", "and so does the second")
truthy(rv and rg and rv.origin and rg.origin and rv.origin[1] ~= rg.origin[1], "each in a room of their own (a solo ride never makes a pair)")
truthy(hasText(texts(v.plr, nv), "PAIR LIFT"), "riders who came in together are told the PAIR LIFT is how to play together")
print(string.format("  two in the Solo Lift: Victim -> %s at x %s, Griefer -> %s at x %s",
	tostring(rv and rv.where), tostring(rv and rv.origin and rv.origin[1]), tostring(rg and rg.where), tostring(rg and rg.origin and rg.origin[1])))
-- staggered: the griefer walks in half-way through the victim's second, the victim still leaves on time
for _, p in { v, g } do
	local z = zoneOf(p)
	local leave = z and z:FindFirstChild("LeaveEntry", true)
	if leave then leave:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(p.plr) end
end
h:advance(1)
Lib.intoSoloLift(w, v)
h:advance(Config.Lift.BoardSeconds * 0.5)
g.hrp.CFrame = CFrame.new(W.SoloCab[1] - 2, 3.5, W.SoloCab[2])
h:advance(Config.Lift.BoardSeconds * 0.5 + Config.Lift.RideSeconds + 0.6)
eq((Lib.last(w, "RoomState", v.plr) or {}).where, "room", "a griefer who walks in during the victim's second cannot hold the victim back")

--============================================================ 2. the Solo Lift's doorway is never shut for anyone else
-- Review-1 finding A2: the shared server door of the first review's fix 9 could be held shut by riders on a
-- loop (2 clients: shut 99% of 120 s, longest open gap 0.00 s). The doors are now each RIDER's own (a local
-- part made by Lab.client, walked in tests/walk.luau), and the server never puts anything collidable in the
-- doorway. Three players loop through the cab for 60 s; at every 0.05 s the doorway must be clear on the
-- server (the emulator has no collision, so this measures what would stand in a walker's way).
local function doorwayBlockers()
	local sx, sz = W.SoloCab[1], W.SoloCab[2]
	local lo = Vector3.new(sx - 3.5, 0.5, sz + W.CabHalf - 0.3)
	local hi = Vector3.new(sx + 3.5, 9, sz + W.CabHalf + 0.6)
	local out = {}
	for _, d in ws:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d:FindFirstAncestorOfClass("Model") == nil then
			local p, s = d.Position, d.Size
			if p.X + s.X / 2 > lo.X and p.X - s.X / 2 < hi.X and p.Y + s.Y / 2 > lo.Y and p.Y - s.Y / 2 < hi.Y
				and p.Z + s.Z / 2 > lo.Z and p.Z - s.Z / 2 < hi.Z then
				table.insert(out, d.Name)
			end
		end
	end
	return out
end
for _, p in { v, g } do
	local z = zoneOf(p)
	local leave = z and z:FindFirstChild("LeaveEntry", true)
	if leave then leave:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(p.plr) end
end
h:advance(1)
eq(#doorwayBlockers(), 0, "nobody rides: the Solo Lift's doorway is open")
do
	local sched = h.scheduler
	local loopers = { Lib.player(w, "Loop1", 6411), Lib.player(w, "Loop2", 6412), Lib.player(w, "Loop3", 6413) }
	local nextEnter, leaveAt = {}, {}
	for i, lp in loopers do nextEnter[lp] = sched:now() + (i - 1) * 0.7 end
	local blocked, frames, rides, names = 0, 0, 0, {}
	for _ = 1, math.floor(60 / 0.05) do
		local tNow = sched:now()
		for _, lp in loopers do
			local rs = Lib.last(w, "RoomState", lp.plr)
			if rs and rs.where == "room" then
				-- ATRIUM as soon as the cab door opens (0.6 s) and the 0.5 s hold is done, straight back in
				if leaveAt[lp] == nil then leaveAt[lp] = tNow + 1.1 end
				if tNow >= leaveAt[lp] then
					local z = Lib.zone(w, lp.plr)
					local pp = z and z:FindFirstChild("LeaveEntry", true)
					pp = pp and pp:FindFirstChildOfClass("ProximityPrompt")
					if pp then pp.Triggered:Fire(lp.plr) end
					leaveAt[lp] = nil
					nextEnter[lp] = tNow
					rides += 1
				end
			elseif nextEnter[lp] and tNow >= nextEnter[lp] then
				Lib.intoSoloLift(w, lp)
				nextEnter[lp] = nil
			end
		end
		h:advance(0.05)
		frames += 1
		local b = doorwayBlockers()
		if #b > 0 then
			blocked += 1
			for _, n in b do names[n] = true end
		end
	end
	local nameList = {}
	for n in names do table.insert(nameList, n) end
	print(string.format("  three riders on a loop for 60 s: %d rides; doorway blocked on the server in %d of %d frames %s", rides,
		blocked, frames, table.concat(nameList, ",")))
	truthy(rides >= 20, string.format("the loop really rides (%d rides in 60 s)", rides))
	eq(blocked, 0, "three riders on a loop never put anything collidable in the Solo Lift's doorway on the server")
	for _, lp in loopers do sched:spawn(function() h:leave(lp.plr) end) end
	h:advance(2)
end
Lib.intoSoloLift(w, v)
h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
eq((Lib.last(w, "RoomState", v.plr) or {}).where, "room", "after the loopers, an honest rider rides")

--============================================================ 3. ATRIUM needs a hold
do
	local z = zoneOf(v)
	local n = 0
	for _, d in (if z then z:GetDescendants() else {}) do
		if d.ClassName == "ProximityPrompt" and d.Name == "LeavePrompt" then
			n += 1
			truthy((d.HoldDuration or 0) >= 0.5, "the " .. d.Parent.Name .. " ATRIUM button needs a hold of 0.5 s or more (got " .. tostring(d.HoldDuration) .. ")")
		end
	end
	eq(n, 2, "a room has two ATRIUM buttons (entry and exit cab)")
	for _, d in (if z then z:GetDescendants() else {}) do
		if d.ClassName == "ProximityPrompt" and d.Name ~= "LeavePrompt" then
			eq(d.HoldDuration or 0, 0, d.Name .. " stays a plain tap")
		end
	end
end

--============================================================ 4. a pair from room 15 to the Roof
local a = Lib.player(w, "Ann", 8101)
local b = Lib.player(w, "Ben", 8102)
local c = Lib.player(w, "Cal", 8103)
h:advance(1)
local go = ws.Atrium.PairGo:FindFirstChildOfClass("ProximityPrompt")
local function padPos(i) return Vector3.new(W.PairCab[1] + (if i == 1 then -W.PairPadDX else W.PairPadDX), 3.5, W.PairCab[2]) end
a.hrp.CFrame = CFrame.new(padPos(1))
b.hrp.CFrame = CFrame.new(padPos(2))
go.Triggered:Fire(a.plr)
go.Triggered:Fire(b.plr)
h:advance(Config.Lift.PairCountdownSeconds + Config.Lift.RideSeconds + 1)
local ra = Lib.last(w, "RoomState", a.plr)
eq(ra and ra.slot, 15, "the pair rides to room 15 (both have 1-14)")
if ra and ra.slot == 15 then
	Lib.solveStation(w, a, ra.stations[1], step)
	Lib.solveStation(w, b, ra.stations[2], step)
	Lib.solveStation(w, a, { kind = "door" }, step)
	h:advance(0.5)
	local o = Lib.origin(w, a.plr)
	local cabZ = -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)
	a.hrp.CFrame = CFrame.new(o + Vector3.new(-1.5, 3.5, cabZ))
	b.hrp.CFrame = CFrame.new(o + Vector3.new(1.5, 3.5, cabZ))
	local na, nb, nc = #w.R.Notice:sentTo(a.plr), #w.R.Notice:sentTo(b.plr), #w.R.Notice:sentTo(c.plr)
	Lib.zone(w, a.plr):FindFirstChild("NextPanel", true):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.plr)
	h:advance(Config.Lift.RideSeconds + 1)
	for _, p in { a, b } do
		eq((Lib.last(w, "RoomState", p.plr) or {}).where, "roof", p.plr.Name .. " is on the Roof")
		truthy(p.hrp.Position.Y > W.RoofY, p.plr.Name .. " stands on the deck (y " .. string.format("%.1f", p.hrp.Position.Y) .. ")")
		local roofCard = false
		for _, n in Lib.noticesSince(w, p.plr, if p == a then na else nb, "roof") do
			if n.first == true then roofCard = true end
		end
		truthy(roofCard, p.plr.Name .. " gets the brag card (first escape)")
	end
	local tb = texts(b.plr, nb)
	truthy(not hasText(tb, "went back to the Atrium"), "Ben is NOT told Ann went back to the Atrium (they rode up together): " .. table.concat(tb, " | "))
	truthy(not hasText(texts(a.plr, na), "went back to the Atrium"), "nor is Ann told Ben did")
	local bragsC = 0
	for _ in Lib.noticesSince(w, c.plr, nc, "brag") do bragsC += 1 end
	eq(bragsC, 2, "a third player hears about both escapes")
	print("  pair to the Roof, Ben's notices: " .. table.concat(tb, " | "))
end

--============================================================ 5. ATRIUM from room 15, then the Roof door
Lib.intoSoloLift(w, c)
h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
local rc = Lib.last(w, "RoomState", c.plr)
eq(rc and rc.slot, 15, "Cal's Solo Lift goes to room 15")
if rc and rc.slot == 15 then
	Lib.solveRoom(w, c, step)
	h:advance(0.5)
	local oc = Lib.origin(w, c.plr)
	local cabZ = -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)
	c.hrp.CFrame = CFrame.new(oc + Vector3.new(0, 3.5, cabZ))
	local leave = nil
	for _, d in Lib.zone(w, c.plr):GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.Name == "LeavePrompt" and d.Parent.Name == "LeaveExit" then leave = d end
	end
	local nc, na = #w.R.Notice:sentTo(c.plr), #w.R.Notice:sentTo(a.plr)
	leave.Triggered:Fire(c.plr)
	h:advance(1)
	local roofDoor = ws.Atrium.RoofAccess:FindFirstChildOfClass("ProximityPrompt")
	c.hrp.CFrame = CFrame.new(0, 3.5, -20)
	roofDoor.Triggered:Fire(c.plr)
	h:advance(2)
	eq((Lib.last(w, "RoomState", c.plr) or {}).where, "roof", "Cal reaches the Roof through the Atrium's Roof door")
	local first = 0
	for _, n in Lib.noticesSince(w, c.plr, nc, "roof") do if n.first == true then first += 1 end end
	eq(first, 1, "the brag card plays for Cal on this first arrival, even by the Atrium door")
	local heard = 0
	for _, n in Lib.noticesSince(w, a.plr, na, "brag") do if string.find(tostring(n.text), "Cal", 1, true) then heard += 1 end end
	eq(heard, 1, "and Ann hears that Cal escaped the Lab")
	-- a second trip up is just a trip: no second brag
	local back = ws.Roof:FindFirstChild("BackDown"):FindFirstChildOfClass("ProximityPrompt")
	back.Triggered:Fire(c.plr)
	h:advance(1)
	local nc2, na2 = #w.R.Notice:sentTo(c.plr), #w.R.Notice:sentTo(a.plr)
	c.hrp.CFrame = CFrame.new(0, 3.5, -20)
	roofDoor.Triggered:Fire(c.plr)
	h:advance(2)
	local again = 0
	for _, n in Lib.noticesSince(w, c.plr, nc2, "roof") do if n.first == true then again += 1 end end
	eq(again, 0, "the second visit plays no brag card")
	eq(#Lib.noticesSince(w, a.plr, na2, "brag"), 0, "and nobody is told twice")
end

--============================================================ 6. an idle player on a pad never blocks a pair (review-1 A1)
-- Before: any other free player standing on either pad made every GO answer "The Pair Lift is full.": one
-- AFK player or a griefer turned the only way to play together off for the whole server.
local a6, b6, g6 = Lib.player(w, "Ada6", 6501), Lib.player(w, "Bo6", 6502), Lib.player(w, "Gus6", 6503)
h:advance(1)
do
	g6.hrp.CFrame = CFrame.new(padPos(2) + Vector3.new(0, 0, -1.2)) -- idle on pad B, never presses anything
	a6.hrp.CFrame = CFrame.new(padPos(1))
	b6.hrp.CFrame = CFrame.new(padPos(2) + Vector3.new(0, 0, 1.2))
	local nb = #w.R.Notice:sentTo(b6.plr)
	go.Triggered:Fire(a6.plr)
	h:advance(0.2)
	go.Triggered:Fire(b6.plr)
	h:advance(0.5)
	-- a second GO from one of the pair during the countdown (the reviewer's probe: "The Pair Lift is full.",
	-- said to a player who is IN the departing pair)
	local na = #w.R.Notice:sentTo(a6.plr)
	go.Triggered:Fire(a6.plr)
	step()
	local ta = texts(a6.plr, na)
	truthy(not hasText(ta, "full"), "a GO from one of the departing pair is not told the lift is full: " .. table.concat(ta, " | "))
	truthy(hasText(ta, "leaves"), "it is told the Pair Lift is leaving")
	h:advance(Config.Lift.PairCountdownSeconds + Config.Lift.RideSeconds + 0.4)
	local ra6, rb6 = Lib.last(w, "RoomState", a6.plr) or {}, Lib.last(w, "RoomState", b6.plr) or {}
	eq(ra6.where, "room", "with an idle player standing on pad B, Ada and Bo still ride the Pair Lift")
	truthy(ra6.roomId ~= nil and ra6.roomId == rb6.roomId, "together, in one room")
	eq(ra6.pair, true, "as a pair")
	truthy(not hasText(texts(b6.plr, nb), "full"), "and Bo is never told the Pair Lift is full")
	eq((Lib.last(w, "RoomState", g6.plr) or {}).where or "atrium", "atrium", "the idle player, who pressed nothing, stays in the Atrium")
end

--============================================================ 7. a Solo rider who leaves the cab during the ride stays behind
-- The rider's own doors keep a walking player in (Lab.client); a client can still move its character out,
-- so the server checks at departure that the rider is still inside (review-1 A2/B2: the shared server door
-- used to be the only thing standing between "walked out" and "taken anyway").
do
	local n7 = #w.R.Notice:sentTo(g6.plr)
	Lib.intoSoloLift(w, g6)
	h:advance(Config.Lift.BoardSeconds + Config.Lift.PollSeconds + 0.2)
	truthy(#Lib.noticesSince(w, g6.plr, n7, "ride") >= 1, "Gus's Solo ride has started")
	g6.hrp.CFrame = CFrame.new(W.Arrival[1], 3.5, W.Arrival[2]) -- out of the cab, mid-ride
	h:advance(Config.Lift.RideSeconds + 1)
	eq((Lib.last(w, "RoomState", g6.plr) or {}).where or "atrium", "atrium", "a Solo rider who left the cab during the ride is not taken to a room")
	truthy(hasText(texts(g6.plr, n7), "stepped out"), "and is told why: " .. table.concat(texts(g6.plr, n7), " | "))
	Lib.intoSoloLift(w, g6)
	h:advance(Config.Lift.BoardSeconds + Config.Lift.RideSeconds + 1)
	eq((Lib.last(w, "RoomState", g6.plr) or {}).where, "room", "stepping back in, Gus rides")
end

--============================================================ 8. a pair partner who walks away during the ride stays behind (review-1 B2)
-- Before: after the 3 s countdown, a partner who walked off during the 2.5 s ride was still pulled into the
-- room from wherever they stood.
local function leaveRoom(p)
	local z = zoneOf(p)
	local leave = z and z:FindFirstChild("LeaveEntry", true)
	if leave then leave:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(p.plr) end
end
leaveRoom(a6)
leaveRoom(b6)
h:advance(1)
do
	a6.hrp.CFrame = CFrame.new(padPos(1))
	b6.hrp.CFrame = CFrame.new(padPos(2))
	local na, nb = #w.R.Notice:sentTo(a6.plr), #w.R.Notice:sentTo(b6.plr)
	go.Triggered:Fire(a6.plr)
	go.Triggered:Fire(b6.plr)
	h:advance(Config.Lift.PairCountdownSeconds + 0.1)
	truthy(#Lib.noticesSince(w, b6.plr, nb, "ride") >= 2, "the countdown is over and the Pair Lift is going up")
	b6.hrp.CFrame = CFrame.new(12, 3.5, 12) -- Bo walks off to the Star Board, 0.1 s into the ride
	h:advance(Config.Lift.RideSeconds + 1)
	local ra8, rb8 = Lib.last(w, "RoomState", a6.plr) or {}, Lib.last(w, "RoomState", b6.plr) or {}
	eq(rb8.where or "atrium", "atrium", "Bo, who walked away during the ride, is not pulled into the room")
	truthy(hasText(texts(b6.plr, nb), "stepped out"), "Bo is told he stepped out of the lift")
	eq(ra8.where, "room", "Ada, who stayed, rides")
	eq(ra8.pair, false, "on her own")
	eq(ra8.members and #ra8.members, 1, "one member")
	truthy(hasText(texts(a6.plr, na), "Carry on solo"), "and is told she carries on solo")
end

--============================================================ 9. the second NEXT press while the lift is already going up (review-1 B3)
-- Before: the partner who pressed NEXT a moment later was told "The door is still shut." as the lift left,
-- and NEXT stayed lit for the whole ride.
leaveRoom(a6)
h:advance(1)
do
	a6.hrp.CFrame = CFrame.new(padPos(1))
	b6.hrp.CFrame = CFrame.new(padPos(2))
	go.Triggered:Fire(a6.plr)
	go.Triggered:Fire(b6.plr)
	h:advance(Config.Lift.PairCountdownSeconds + Config.Lift.RideSeconds + 1)
	local r9 = Lib.last(w, "RoomState", a6.plr) or {}
	eq(r9.where, "room", "Ada and Bo are in a room again")
	Lib.solveRoom(w, a6, step)
	h:advance(0.5)
	local o9 = Lib.origin(w, a6.plr)
	local cabZ = -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)
	a6.hrp.CFrame = CFrame.new(o9 + Vector3.new(-1.5, 3.5, cabZ))
	b6.hrp.CFrame = CFrame.new(o9 + Vector3.new(1.5, 3.5, cabZ))
	local nextPP = Lib.zone(w, a6.plr):FindFirstChild("NextPanel", true):FindFirstChildOfClass("ProximityPrompt")
	eq(nextPP.Enabled, true, "NEXT is lit after the escape")
	local nb = #w.R.Notice:sentTo(b6.plr)
	nextPP.Triggered:Fire(a6.plr)
	h:advance(0.6)
	eq(nextPP.Enabled, false, "once the lift is going up, NEXT is off")
	nextPP.Triggered:Fire(b6.plr) -- a press already on its way
	step()
	local tb = texts(b6.plr, nb)
	truthy(not hasText(tb, "still shut"), "Bo's NEXT during the ride is not told the door is still shut: " .. table.concat(tb, " | "))
	h:advance(Config.Lift.RideSeconds + 1)
	local ra9, rb9 = Lib.last(w, "RoomState", a6.plr) or {}, Lib.last(w, "RoomState", b6.plr) or {}
	eq(ra9.slot, 2, "the pair rode on to room 2")
	eq(ra9.roomId, rb9.roomId, "together")
end

t.finish("escape-room-lab lifts", h)
