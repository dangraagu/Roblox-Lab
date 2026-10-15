-- check_disasterrounds_bot.luau - a scripted Disaster Rounds player for the headless checks (a module, not a check).
--
-- It plays the way DESIGN.md §2.8's "bot" profile does: it reads ONLY what a client can see (workspace.Round's
-- attributes, the ring Parts in Round.Rings, the island cells' Level / CrackAt / Dropped attributes, the tornado's
-- Path attribute), notices each red thing `react` seconds after it first appears, and walks at 16 studs/s to the
-- nearest point outside all the red it has noticed, never walking through a ring as it lands. If THIS player is
-- ever hit, the disaster is unfair. No physics here: the bot moves its root part, as every check in this repo does,
-- and stands at the top of whatever cell is under it.
--
--   local Bot = require("./check_disasterrounds_bot")
--   local bot = Bot.new(h, plr, { react = 0.6 })
--   each tick:  Bot.step(bot, dt)   then h:advance(dt)
--
-- Options: react (seconds, default 0.6), idle (never move), margin (studs beyond the red, default 0.8).

local Datatypes = require("./emu/datatypes") -- a required module has its own globals: CFrame comes from here
local CFrame = Datatypes.CFrame
local Vector3 = Datatypes.Vector3

local Bot = {}

local WALK = 16

function Bot.new(h: any, plr: any, opts: any?): any
	opts = opts or {}
	local RS = h.ReplicatedStorage
	local Config = h:_require(RS:FindFirstChild("Config"))
	local MapGen = h:_require(RS:FindFirstChild("MapGen"))
	local Tornado = h:_require(RS:FindFirstChild("Tornado"))
	return {
		h = h, plr = plr, Config = Config, MapGen = MapGen, Tornado = Tornado,
		react = opts.react or 0.6, idle = opts.idle == true, margin = opts.margin or 0.8,
		seen = {}, target = nil, moved = 0, dodges = 0,
	}
end

local function serverNow(bot: any): number
	return bot.h.scheduler:now()
end

-- everything red the bot has noticed (seen for at least `react` seconds)
local function noticed(bot: any, t: number): any
	local rf = bot.h.workspace:FindFirstChild("Round")
	local out = { rings = {}, cells = {}, path = {}, holes = {}, drops = {} }
	local function notice(key: any): boolean
		local first = bot.seen[key]
		if first == nil then
			bot.seen[key] = t
			first = t
		end
		return t >= first + bot.react - 1e-9
	end
	local rings = rf:FindFirstChild("Rings")
	if rings then
		for _, r in rings:GetChildren() do
			local impact = r:GetAttribute("ImpactAt")
			local radius = r:GetAttribute("Radius")
			if type(impact) == "number" and type(radius) == "number" and t < impact + 0.35 and notice(r) then
				table.insert(out.rings, { x = r.Position.X, z = r.Position.Z, r = radius, impact = impact })
			end
		end
	end
	local island = rf:FindFirstChild("Island")
	local kind = rf:GetAttribute("Kind")
	if island then
		local warnLevel = rf:GetAttribute("WarnLevel")
		for _, cell in island.Cells:GetChildren() do
			local level = cell:GetAttribute("Level")
			local key = cell:GetAttribute("I") * 1000 + cell:GetAttribute("J")
			local red = cell:GetAttribute("Dropped") == true
			if red then out.holes[key] = true end
			local dropAt = cell:GetAttribute("DropAt")
			if not red and type(dropAt) == "number" then out.drops[key] = dropAt end
			if not red and cell:GetAttribute("CrackAt") ~= nil then red = notice(cell) end
			if not red and kind == "flood" and type(warnLevel) == "number" and type(level) == "number" and level <= warnLevel then
				red = notice("flood:" .. warnLevel)
			end
			if red then out.cells[key] = true end
		end
	end
	if kind == "tornado" then
		local t0, pts = bot.Tornado.decode(rf:GetAttribute("Path"))
		if t0 and pts then
			for k, p in pts do
				local pt = t0 + (k - 1) * 0.25
				local slot = math.floor(pt * 4 + 0.5)
				if notice("path:" .. slot) then table.insert(out.path, { x = p.x, z = p.z, t = pt }) end
			end
		end
	end
	return out
end

local function cellKey(bot: any, x: number, z: number): number?
	local i, j = bot.MapGen.cellAt(bot.Config.Island, x, z)
	if i == nil then return nil end
	return i * 1000 + j
end

local function unsafe(bot: any, red: any, x: number, z: number, t: number): boolean
	local half = bot.MapGen.halfSize(bot.Config.Island) - bot.Config.Hits.PlayerRadius -- the server's standing edge
	if math.abs(x) > half or math.abs(z) > half then return true end
	local k = cellKey(bot, x, z)
	if k == nil or red.cells[k] then return true end
	local m = bot.margin
	for _, r in red.rings do
		if t < r.impact + 0.3 then
			local rr = r.r + m
			if (x - r.x) ^ 2 + (z - r.z) ^ 2 < rr * rr then return true end
		end
	end
	local fr = bot.Config.Tornado.HitRadius + bot.Config.Hits.PlayerRadius + m + 0.5
	for _, p in red.path do
		if (x - p.x) ^ 2 + (z - p.z) ^ 2 < fr * fr then return true end
	end
	return false
end

-- would walking straight from (x0, z0) to (x1, z1) put the bot inside a ring around its impact?
local function crossesLanding(bot: any, red: any, x0: number, z0: number, x1: number, z1: number, t: number): boolean
	local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local T = L / WALK
	for _, r in red.rings do
		local lo, hi = r.impact - 0.15 - t, r.impact + 0.3 - t
		if hi >= 0 then
			local s = math.max(0, lo)
			while s <= hi do
				local f = if T > 0 then math.min(1, s / T) else 1
				local px, pz = x0 + (x1 - x0) * f, z0 + (z1 - z0) * f
				if (px - r.x) ^ 2 + (pz - r.z) ^ 2 < (r.r + 0.2) ^ 2 then return true end
				s += 0.05
			end
		end
	end
	return false
end

-- does the straight walk from (x0, z0) to (x1, z1) cross a hole, or a cracked cell that drops before the bot is off
-- it? (The open sea shows through a hole: walking into one is a readable mistake, and the bot does not make it.)
local function crossesHole(bot: any, red: any, x0: number, z0: number, x1: number, z1: number, t: number): boolean
	local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local n = math.max(1, math.ceil(L / 0.5))
	for k = 1, n do
		local f = k / n
		local px, pz = x0 + (x1 - x0) * f, z0 + (z1 - z0) * f
		local key = cellKey(bot, px, pz)
		if key == nil or red.holes[key] then return true end
		local dropAt = red.drops[key]
		if dropAt and dropAt <= t + (L * f) / WALK + 0.5 then return true end
	end
	return false
end

-- would walking straight from (x0, z0) to (x1, z1), and standing there a second, meet the funnel on its timed track?
local function crossesFunnel(bot: any, red: any, x0: number, z0: number, x1: number, z1: number, t: number): boolean
	local path = red.path
	if #path < 2 then return false end
	local L = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local T = L / WALK
	local fr = bot.Config.Tornado.HitRadius + bot.Config.Hits.PlayerRadius + 1.0
	local s = 0
	while s <= T + 1.0 do
		local when = t + s
		-- the funnel's position at `when`, from the path's timed points
		local fx, fz = nil, nil
		for k = 2, #path do
			local a, b = path[k - 1], path[k]
			if when >= a.t and when <= b.t then
				local f = (when - a.t) / math.max(1e-6, b.t - a.t)
				fx, fz = a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
				break
			end
		end
		if fx then
			local fw = if T > 0 then math.min(1, s / T) else 1
			local px, pz = x0 + (x1 - x0) * fw, z0 + (z1 - z0) * fw
			if (px - fx) ^ 2 + (pz - fz) ^ 2 < fr * fr then return true end
		end
		s += 0.05
	end
	return false
end

local function nearestSafe(bot: any, red: any, x: number, z: number, t: number): (number?, number?)
	local fallbackX, fallbackZ = nil, nil
	for k = 1, 60 do
		local d = 0.5 * k
		for a = 0, 31 do
			local ang = a * math.pi / 16
			local px, pz = x + math.cos(ang) * d, z + math.sin(ang) * d
			if not unsafe(bot, red, px, pz, t) and not crossesLanding(bot, red, x, z, px, pz, t) then
				if not crossesHole(bot, red, x, z, px, pz, t) and not crossesFunnel(bot, red, x, z, px, pz, t) then return px, pz end
				if fallbackX == nil then fallbackX, fallbackZ = px, pz end
			end
		end
	end
	return fallbackX, fallbackZ
end

-- one tick of play: notice, decide, walk at most WALK * dt
function Bot.step(bot: any, dt: number)
	local plr = bot.plr
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (plr:GetAttribute("InRound") or "") == "" then
		bot.target = nil
		return
	end
	local t = serverNow(bot)
	local red = noticed(bot, t)
	if bot.idle then
		-- robloxemu's PivotTo re-applies `cf * old:Inverse()`, which multiplies any rotation error about 4x per call:
		-- after ~25 server moves of one model its CFrame is NaN. In Roblox the Humanoid keeps a standing body upright,
		-- so the idle player re-squares its root the way the engine would (position kept, rotation reset).
		local pos = hrp.Position
		if pos.X == pos.X and pos.Y == pos.Y and pos.Z == pos.Z then hrp.CFrame = CFrame.new(pos.X, pos.Y, pos.Z) end
		return
	end
	local p = hrp.Position
	local tgt = bot.target
	if tgt and (unsafe(bot, red, tgt.x, tgt.z, t) or crossesLanding(bot, red, p.X, p.Z, tgt.x, tgt.z, t)
		or crossesHole(bot, red, p.X, p.Z, tgt.x, tgt.z, t) or crossesFunnel(bot, red, p.X, p.Z, tgt.x, tgt.z, t)) then
		tgt = nil
	end
	if tgt == nil and unsafe(bot, red, p.X, p.Z, t) then
		local nx, nz = nearestSafe(bot, red, p.X, p.Z, t)
		if nx then
			tgt = { x = nx, z = nz }
			bot.dodges += 1
		end
	end
	bot.target = tgt
	local hum = char:FindFirstChildOfClass("Humanoid")
	-- a player walking holds the stick: the client reads MoveDirection as input (Sky.client's AFK clock)
	if hum then hum.MoveDirection = if tgt then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 0) end
	if tgt == nil then return end
	local dx, dz = tgt.x - p.X, tgt.z - p.Z
	local d = math.sqrt(dx * dx + dz * dz)
	local stepLen = WALK * dt
	local nx, nz
	if d <= stepLen then
		nx, nz = tgt.x, tgt.z
		bot.target = nil
	else
		nx, nz = p.X + dx / d * stepLen, p.Z + dz / d * stepLen
	end
	bot.moved += math.min(d, stepLen)
	local i, j = bot.MapGen.cellAt(bot.Config.Island, nx, nz)
	local island = bot.h.workspace.Round:FindFirstChild("Island")
	local y = p.Y
	if i and island then
		local cell = island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
		if cell and cell:GetAttribute("Dropped") ~= true then
			y = bot.MapGen.topY(bot.Config.Island, cell:GetAttribute("Level")) + 3
		end
	end
	hrp.CFrame = CFrame.new(nx, y, nz)
end

return Bot
