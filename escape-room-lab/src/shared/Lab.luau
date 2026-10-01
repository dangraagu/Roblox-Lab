--!strict
-- Lab.luau — the rules of the Lab that are not a puzzle: which room is which, what a room pays,
-- where Continue goes, what a wrong try costs, and the progress value the bands follow.
-- Pure; no Roblox. `cfg` is the game's Config, passed in (shared modules take dependencies as
-- arguments; a bare string require would resolve in the luau CLI and fail in Roblox).

local Lab = {}

function Lab.rooms(cfg: any): number
	local n = 0
	for _, w in cfg.Lab.Wings do n += #w.rooms end
	return n
end

function Lab.slotOf(wing: number, room: number): number
	return (wing - 1) * 3 + room
end

function Lab.wingRoomOf(slot: number): (number, number)
	return math.floor((slot - 1) / 3) + 1, (slot - 1) % 3 + 1
end

local FEEDER_IDS = { "A", "B", "C" }

-- { slot, wing, room, wingId, wingName, door = { L, alphabet, maxLines }, feeders = { {id, kind, ...} },
--   stations = { "A", ..., "Door" } } or nil for a slot that does not exist.
function Lab.roomSpec(cfg: any, slot: number): any
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Lab.rooms(cfg) then return nil end
	local wing, room = Lab.wingRoomOf(slot)
	local w = cfg.Lab.Wings[wing]
	local feeders = {}
	local stations = {}
	for i, f in w.rooms[room] do
		local copy = table.clone(f)
		copy.id = FEEDER_IDS[i]
		table.insert(feeders, copy)
		table.insert(stations, copy.id)
	end
	table.insert(stations, "Door")
	local maxLines = if slot == 1 then cfg.Puzzles.FirstRoomMaxLines else cfg.Puzzles.MaxDoorLines
	return {
		slot = slot,
		wing = wing,
		room = room,
		wingId = w.id,
		wingName = w.name,
		door = { L = w.door.L, alphabet = table.clone(w.door.alphabet), maxLines = maxLines },
		feeders = feeders,
		stations = stations,
	}
end

-- Stars for one player's escape. res = { escaped, wrong, hinted, pair, handsOn }.
-- In a pair, a player who completed none of the room's stations gets nothing: a partner cannot carry
-- anyone to stars (the hands-on rule, DESIGN.md §4.3). Their escape still advances their frontier.
function Lab.stars(res: any): number
	if not res.escaped then return 0 end
	if res.pair and not res.handsOn then return 0 end
	local s = 1
	if not res.wrong then s += 1 end
	if not res.hinted then s += 1 end
	return s
end

-- best: { ["1"] = 0..3, ... }; a key present means that room was escaped.
function Lab.total(best: { [string]: number }): number
	local t = 0
	for _, v in best do
		if type(v) == "number" then t += v end
	end
	return t
end

-- The first room never escaped (1-15), or 16 once all are.
function Lab.frontier(best: { [string]: number }, rooms: number?): number
	local n = rooms or 15
	for s = 1, n do
		if best[tostring(s)] == nil then return s end
	end
	return n + 1
end

function Lab.continueSolo(best: { [string]: number }, lastPlayed: number?, rooms: number?): number
	local n = rooms or 15
	local f = Lab.frontier(best, n)
	if f <= n then return f end
	for s = 1, n do
		if (best[tostring(s)] or 0) < 3 then return s end
	end
	if type(lastPlayed) ~= "number" or lastPlayed < 1 or lastPlayed >= n then return 1 end
	return math.floor(lastPlayed) + 1
end

function Lab.continuePair(bestA: { [string]: number }, lastA: number?, bestB: { [string]: number }, lastB: number?): number
	return math.min(Lab.continueSolo(bestA, lastA), Lab.continueSolo(bestB, lastB))
end

function Lab.lockoutFor(cfg: any, wrongCount: number): number
	if wrongCount <= 0 then return 0 end
	local L = cfg.Stars.Lockout
	return L[math.min(wrongCount, #L)]
end

-- spec: { kind = "door", L } | { kind = "shelf", N } | { kind = "lamp", k }
function Lab.hintCap(spec: any): number
	if spec.kind == "door" then return spec.L - 1 end
	if spec.kind == "shelf" then return math.max(1, spec.N - 2) end
	return math.max(1, (spec.k or 1) - 1)
end

-- The progress value: the room you are in and how much of it is solved. Never time.
function Lab.progress(wing: number, room: number, solved: number, stations: number): number
	local frac = if stations > 0 then math.clamp(solved / stations, 0, 1) else 0
	return (wing - 1) + (room - 1 + frac) / 3
end

-- May a hazard land here? Room-local x, z: inside the interior shrunk by 1, and at least 5 studs from
-- both doorways, so a knock never pushes anyone into a cab.
function Lab.legalSpot(x: number, z: number, cfg: any): boolean
	local half = cfg.World.RoomHalf - 1
	if math.abs(x) > half or math.abs(z) > half then return false end
	for _, dz in { cfg.World.RoomHalf, -cfg.World.RoomHalf } do
		local d = math.sqrt(x * x + (z - dz) * (z - dz))
		if d < 5 then return false end
	end
	return true
end

return Lab
