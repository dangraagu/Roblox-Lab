--!strict
-- EnvBands.luau — progress value -> environment band + blend. Game-agnostic, pure, no Roblox.
--
-- A game describes its world as an ordered list of BANDS, each starting at a progress value:
--
--     { id = "clouds", from = 15, fade = 4, lighting = { ClockTime = 16.6, FogColor = {r,g,b} }, ... }
--
-- and asks this module, every frame, "where am I and how much of the next band is showing?".
-- The payload is the game's business. This module only blends numbers and arrays of numbers
-- (colours are {r, g, b}, never Color3, so every function here runs in the luau CLI) and hands
-- back COPIES, so a caller writing to a sample can never corrupt its config.
--
-- Rules every copy of this module relies on (tests/EnvBands.spec.luau pins each one):
--   * total lookup: any number — negative, NaN, infinite — lands in some band;
--   * a band blends in over the `fade` progress units BEFORE its `from`, eased with a smoothstep,
--     so a transition is continuous and never a hard cut (fade 0 is the explicit exception);
--   * blending is driven by the progress value only. Time enters only through `approach`, which
--     smooths a value that JUMPED (a teleport, a respawn) and is frame-rate independent.
--
-- Copy it verbatim into another game; keep the game's band numbers in that game's Config.

local EnvBands = {}

local function isNaN(x: number): boolean
	return x ~= x
end

local function smoothstep(x: number): number
	if x <= 0 then return 0 end
	if x >= 1 then return 1 end
	return x * x * (3 - 2 * x)
end

local function copy(v: any): any
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

-- (ok, err). Rejects anything that would make a lookup ambiguous or a fade reach backwards.
function EnvBands.validate(bands: { any }): (boolean, string?)
	if type(bands) ~= "table" or #bands == 0 then
		return false, "no bands"
	end
	local ids = {}
	for i, b in ipairs(bands) do
		if type(b.from) ~= "number" or isNaN(b.from) then
			return false, "band " .. i .. " has no numeric `from`"
		end
		if b.id == nil then
			return false, "band " .. i .. " has no id"
		end
		if ids[b.id] then
			return false, "duplicate band id " .. tostring(b.id)
		end
		ids[b.id] = true
		local fade = b.fade or 0
		if type(fade) ~= "number" or isNaN(fade) or fade < 0 then
			return false, "band " .. tostring(b.id) .. " has a negative or non-numeric fade"
		end
		if i == 1 then
			if b.from ~= 0 then
				return false, "the first band must start at 0"
			end
		else
			local prev = bands[i - 1]
			if b.from <= prev.from then
				return false, "band " .. tostring(b.id) .. " does not start after " .. tostring(prev.id)
			end
			if fade > b.from - prev.from then
				return false, "band " .. tostring(b.id) .. " fades in before " .. tostring(prev.id) .. " starts"
			end
		end
	end
	return true, nil
end

-- Index of the band containing progress p (the last band whose `from` <= p).
function EnvBands.indexAt(bands: { any }, p: number): number
	if type(p) ~= "number" or isNaN(p) then return 1 end
	local idx = 1
	for i = 2, #bands do
		if p >= bands[i].from then
			idx = i
		else
			break
		end
	end
	return idx
end

-- (i, j, t): the band you are in, the band blending in (== i when none), and its eased weight.
function EnvBands.locate(bands: { any }, p: number): (number, number, number)
	local i = EnvBands.indexAt(bands, p)
	local nextBand = bands[i + 1]
	if nextBand == nil or type(p) ~= "number" or isNaN(p) then
		return i, i, 0
	end
	local fade = nextBand.fade or 0
	if fade <= 0 then
		return i, i, 0
	end
	local start = nextBand.from - fade
	if p < start then
		return i, i, 0
	end
	return i, i + 1, smoothstep((p - start) / fade)
end

-- { [bandIndex] = weight } with at most two non-zero entries, always summing to 1.
function EnvBands.weights(bands: { any }, p: number): { [number]: number }
	local i, j, t = EnvBands.locate(bands, p)
	local w = {}
	if j == i then
		w[i] = 1
	else
		w[i] = 1 - t
		w[j] = t
	end
	return w
end

-- Blend two values: numbers linearly, number arrays component-wise, anything else switches at
-- the halfway point. A nil on either side falls back to the other side.
function EnvBands.lerp(a: any, b: any, t: number): any
	if a == nil then return copy(b) end
	if b == nil then return copy(a) end
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * t
	end
	if type(a) == "table" and type(b) == "table" then
		local out = {}
		for k, av in a do
			out[k] = EnvBands.lerp(av, b[k], t)
		end
		for k, bv in b do
			if out[k] == nil then out[k] = copy(bv) end
		end
		return out
	end
	if t < 0.5 then return copy(a) end
	return copy(b)
end

-- The blended payload `bands[*][key]` at progress p. Always a fresh table.
function EnvBands.sample(bands: { any }, p: number, key: string): { [string]: any }
	local i, j, t = EnvBands.locate(bands, p)
	local a = bands[i][key]
	local b = bands[j][key]
	if a == nil and b == nil then return {} end
	if j == i then return copy(a) end
	return EnvBands.lerp(a, b, t)
end

-- Narrow override windows (a cloud deck you climb THROUGH): 1 within halfWidth of centre, eased
-- down to 0 across `feather`.
function EnvBands.layerWeight(layer: any, p: number): number
	if type(p) ~= "number" or isNaN(p) then return 0 end
	local d = math.abs(p - layer.center) - layer.halfWidth
	if d <= 0 then return 1 end
	local feather = layer.feather or 0
	if feather <= 0 then return 0 end
	return 1 - smoothstep(d / feather)
end

-- base with the fields named in `over` blended toward over by weight w. Fresh table.
function EnvBands.overlay(base: { [string]: any }, over: { [string]: any }?, w: number): { [string]: any }
	local out = copy(base)
	if over == nil or w <= 0 then return out end
	for k, v in over do
		out[k] = EnvBands.lerp(out[k], v, math.min(w, 1))
	end
	return out
end

-- Exponential approach: after `halfLife` seconds the gap to target has halved. Frame-rate
-- independent. halfLife <= 0 snaps.
function EnvBands.approach(current: any, target: any, dt: number, halfLife: number): any
	if halfLife <= 0 or current == nil then return copy(target) end
	local alpha = 1 - 0.5 ^ (math.max(dt, 0) / halfLife)
	if type(current) == "number" and type(target) == "number" then
		return current + (target - current) * alpha
	end
	if type(current) == "table" and type(target) == "table" then
		return EnvBands.lerp(current, target, alpha)
	end
	return copy(target)
end

-- approach over a flat property table. A field the current table lacks starts AT the target.
function EnvBands.approachTable(current: { [string]: any }?, target: { [string]: any }, dt: number, halfLife: number): { [string]: any }
	local out = {}
	for k, v in target do
		local c = if current then current[k] else nil
		if c == nil then
			out[k] = copy(v)
		else
			out[k] = EnvBands.approach(c, v, dt, halfLife)
		end
	end
	return out
end

-- (index, remaining) of the next band above p, or nil when p is in the last band.
function EnvBands.nextBand(bands: { any }, p: number): (number?, number?)
	local i = EnvBands.indexAt(bands, p)
	local nb = bands[i + 1]
	if nb == nil then return nil, nil end
	return i + 1, nb.from - p
end

function EnvBands.indexOf(bands: { any }, id: any): number?
	for i, b in ipairs(bands) do
		if b.id == id then return i end
	end
	return nil
end

-- The weather to switch on this frame, under a budget: of `rates` ({ [kind] = particles per second}, as
-- blended by band weight), only kinds above `minRate`, only the `maxOn` strongest (equal rates broken by
-- name, so the choice cannot flicker between frames), and scaled down together so they sum to at most
-- `maxTotal`. Returns a NEW table of the kinds to enable and their rates; the input is not modified.
-- Review 2026-09-17 round 2: band weights fade on a half-life, so a fast altitude change left the weather
-- of several bands switched on at once (5 emitters against a budget of 4). This is the cap, in code.
function EnvBands.capRates(rates: { [string]: number }, maxOn: number, maxTotal: number, minRate: number): { [string]: number }
	local list: { { kind: string, rate: number } } = {}
	for kind, rate in rates do
		if type(rate) == "number" and rate > minRate then
			table.insert(list, { kind = kind, rate = rate })
		end
	end
	table.sort(list, function(a: { kind: string, rate: number }, b: { kind: string, rate: number }): boolean
		if a.rate ~= b.rate then return a.rate > b.rate end
		return tostring(a.kind) < tostring(b.kind)
	end)
	local out, sum = {}, 0
	for i = 1, math.min(#list, math.max(0, math.floor(maxOn))) do
		out[list[i].kind] = list[i].rate
		sum += list[i].rate
	end
	if sum > maxTotal and sum > 0 then
		local k = maxTotal / sum
		for kind, rate in out do
			out[kind] = rate * k
		end
	end
	return out
end

-- "Welcome to <band>" once per new highest band. Going down and back up says nothing.
function EnvBands.newAnnouncer(): { highest: number }
	return { highest = 0 }
end

function EnvBands.announce(state: { highest: number }, index: number): boolean
	if index > state.highest then
		state.highest = index
		return true
	end
	return false
end

-- World-fixed tiling, so scenery that follows the camera never slides with it: content belongs
-- to a grid cell and is derived from the cell's coordinates.
function EnvBands.cellOf(v: number, cellSize: number): number
	return math.floor(v / cellSize)
end

function EnvBands.cellsAround(x: number, z: number, cellSize: number, radius: number): { { number } }
	local cx, cz = EnvBands.cellOf(x, cellSize), EnvBands.cellOf(z, cellSize)
	local out = {}
	for dx = -radius, radius do
		for dz = -radius, radius do
			out[#out + 1] = { cx + dx, cz + dz }
		end
	end
	return out
end

-- Shortest distance from point p to a polyline `path` (a list of {x,y,z}); math.huge for an empty path.
function EnvBands.pathDistance(p: any, path: { any }): number
	local best = math.huge
	local n = #path
	if n == 1 then
		local dx, dy, dz = p.x - path[1].x, p.y - path[1].y, p.z - path[1].z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	for i = 1, n - 1 do
		local a, b = path[i], path[i + 1]
		local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
		local len2 = abx * abx + aby * aby + abz * abz
		local s = 0
		if len2 > 0 then
			s = math.clamp(((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / len2, 0, 1)
		end
		local dx, dy, dz = a.x + abx * s - p.x, a.y + aby * s - p.y, a.z + abz * s - p.z
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d < best then best = d end
	end
	return best
end

-- Scenery must never sit in the player's way (a cloud swallowing the next platform). The radius a
-- ball of scenery centred at `centre` may keep so its surface stays `clearance` from `path`: its own
-- radius when that already fits, smaller when it does not, 0 (leave it out) below `minRadius`.
function EnvBands.keepClear(centre: any, radius: number, path: { any }, clearance: number, minRadius: number): number
	local d = EnvBands.pathDistance(centre, path)
	if d == math.huge then return radius end
	local allowed = d - clearance
	if radius <= allowed then return radius end
	if allowed < minRadius then return 0 end
	return allowed
end

-- Ambient life (birds, balloons, satellites): spawn somewhere on a ring around the camera, moving
-- ACROSS the view (roughly tangent to the ring), never at it. spec = { rMin, rMax, yMin, yMax,
-- speedMin, speedMax, rise? }. Plain {x,y,z} tables; rand() in [0, 1).
function EnvBands.ambientSpawn(centre: any, spec: any, rand: () -> number): any
	local a = rand() * math.pi * 2
	local r = spec.rMin + (spec.rMax - spec.rMin) * rand()
	local pos = {
		x = centre.x + math.sin(a) * r,
		y = centre.y + spec.yMin + (spec.yMax - spec.yMin) * rand(),
		z = centre.z + math.cos(a) * r,
	}
	local speed = spec.speedMin + (spec.speedMax - spec.speedMin) * rand()
	-- tangent to the ring, turned up to 35 degrees either way, either direction round
	local turn = math.rad((rand() * 2 - 1) * 35)
	local sign = if rand() < 0.5 then -1 else 1
	local tx, tz = math.cos(a) * sign, -math.sin(a) * sign
	local hx = tx * math.cos(turn) - tz * math.sin(turn)
	local hz = tx * math.sin(turn) + tz * math.cos(turn)
	if spec.rise then
		local h = speed * 0.4
		return { pos = pos, vel = { x = hx * h, y = math.sqrt(speed * speed - h * h), z = hz * h } }
	end
	return { pos = pos, vel = { x = hx * speed, y = 0, z = hz * speed } }
end

-- Out of range: horizontally past 1.35 x rMax, or far outside the height band (camera moved on).
function EnvBands.ambientExpired(pos: any, centre: any, spec: any): boolean
	local dx, dz = pos.x - centre.x, pos.z - centre.z
	if dx * dx + dz * dz > (spec.rMax * 1.35) ^ 2 then return true end
	local dy = pos.y - centre.y
	local slack = 250
	return dy < spec.yMin - slack or dy > spec.yMax + slack
end

-- Deterministic [0, 1) from integers. Integer arithmetic kept under 2^53 (checklist: seed overflow).
function EnvBands.hash01(a: number, b: number, c: number, seed: number): number
	local h = (seed % 2147483647 + 2147483647) % 2147483647
	for _, v in { a, b, c } do
		local x = (math.floor(v) % 2147483647 + 2147483647) % 2147483647
		h = (h * 31 + x + 7919) % 2147483647
		h = (h * 48271) % 2147483647
		h = (h * 16807 + 12345) % 2147483647
	end
	return h / 2147483647
end

return EnvBands
