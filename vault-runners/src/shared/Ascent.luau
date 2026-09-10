--!strict
-- Ascent.luau — KLATREN SOM SMULDRER. REN logikk.
--
-- The vault's one vertical challenge. VaultFloor builds the shaft — six 3x3 pads spiralling the
-- corners of the stairwell cell, five studs of open air between them — and this file decides
-- which of those pads are THERE at any given moment.
--
-- The rule is one sentence: a pad holds for Config.Ascent.CrumbleSeconds after the runner first
-- stands on it, then falls away for Config.Ascent.RespawnSeconds, then comes back. Keep moving
-- and you never see it. Stop to line the jump up and the floor goes.
--
-- WHAT A MISS COSTS IS SECONDS. There is no death rule in here, no lost gems, no teleport: the
-- runner falls onto the storey they came from and climbs again while the collapse keeps rising.
-- That is deliberate — the vault already has exactly one way to lose (the plane, and the seal),
-- and an obby that invented a second one would be two games sharing a countdown. It also means
-- the obby cannot make a vault unwinnable on its own, which is the property
-- tests/Collapse.spec.luau depends on.
--
-- EVERY PAD COMES BACK. A crumbling platform that stays crumbled is a shaft that eats its own
-- route, and a vault with no route out is not a hard vault, it is a broken one.
--
-- Pure by construction: cfg + plain tables + a number for `now`, which the server's run loop
-- accumulates (virtual time under the emulator, wall time in Roblox). No Roblox global, no clock,
-- no geometry of its own — `model` is exactly what VaultFloor.build returned. And, like every
-- other module in src/shared, it requires NOTHING: a bare `require("./X")` resolves in the luau
-- CLI and is INVALID in Roblox.

local Ascent = {}

local function key(storey: number, index: number): string
	return storey .. ":" .. index
end

-- One shaft state per RUN. `model` is taken so the state knows how many pads there are without
-- the caller having to tell it twice; nothing else about the vault is copied in, so a state
-- cannot drift away from the vault it was made for.
function Ascent.new(_cfg: any, model: any): any
	local pads = {}
	for s = 0, model.storeys - 2 do
		local sh: any = model.shafts[s + 1]
		if sh ~= nil then
			for _, p in ipairs(sh.pads :: { any }) do pads[#pads + 1] = { storey = s, index = p.index } end
		end
	end
	return {
		-- [storey:index] = the moment the runner first stood on it in the CURRENT cycle
		touchedAt = {},
		-- ...and what the server was last told to draw, so update() reports only what changed
		shown = {},
		pads = pads,
	}
end

-- Is the pad there right now? Untouched pads are always there. A touched one is there for
-- CrumbleSeconds, gone for RespawnSeconds, and then there again.
--
-- BOTH BOUNDARIES ARE INCLUSIVE OF THE LATER STATE — gone AT t0 + Crumble, back AT
-- t0 + Crumble + Respawn. This file follows RunState's `now >= sealAt`: a boundary that resolves
-- in the player's favour is a boundary they learn to sit on.
function Ascent.solid(cfg: any, state: any, storey: number, index: number, now: number): boolean
	local t0 = state.touchedAt[key(storey, index)]
	if t0 == nil then return true end
	local A = cfg.Ascent
	local age = now - t0
	if age < A.CrumbleSeconds then return true end
	return age >= A.CrumbleSeconds + A.RespawnSeconds
end

-- The runner is standing on this pad. Recording the FIRST touch of a cycle and ignoring the rest
-- is what stops a player holding a pad up by standing on it — the difference between a crumbling
-- platform and a rug. A pad that has come back is a fresh pad and starts a fresh cycle.
--
-- THE CYCLE IS CLOSED HERE, not by whoever happens to call update(). The first cut left expiry to
-- update() alone, which reads fine — the run loop calls it every tick — and meant a pad that had
-- respawned was never touchable again unless something else had swept it first. The spec caught
-- it: the second landing on a returned pad did nothing and the pad never crumbled again.
function Ascent.touch(cfg: any, state: any, storey: number, index: number, now: number)
	local k = key(storey, index)
	local t0 = state.touchedAt[k]
	local span = cfg.Ascent.CrumbleSeconds + cfg.Ascent.RespawnSeconds
	if t0 == nil or now < t0 or now - t0 >= span then state.touchedAt[k] = now end
end

-- Drop the record of a cycle that is entirely behind us. Purely housekeeping — touch() and
-- solid() are both correct without it — so that a long run does not carry a growing table of
-- pads nobody has been near for four minutes.
local function expire(cfg: any, state: any, now: number)
	local A = cfg.Ascent
	local span = A.CrumbleSeconds + A.RespawnSeconds
	for k, t0 in pairs(state.touchedAt) do
		if now - t0 >= span then state.touchedAt[k] = nil end
	end
end

-- WHICH PAD IS UNDER THE RUNNER, or nil. `pos` is vault-local, and in the live game it is the
-- TRUSTED position from src/shared/Trace.luau — never the client's claim. Every rule in the run
-- loop reads the trusted one, and a crumble triggered by a claim would let a client dissolve the
-- shaft under somebody else's feet by lying about where it is.
--
-- Horizontal is measured to the pad's centre and is generous by half a pad (StandRadius), because
-- a runner on the lip of a 3-stud pad is on it.
--
-- VERTICAL IS MEASURED FROM THE RUNNER'S FEET, NOT THEIR ROOT, and that is not a detail. Pad 1's
-- top sits exactly StepRise above the storey floor, and a standing runner's ROOT sits
-- Run.RunnerRootHeight above whatever they are standing on — so a runner merely walking across
-- the stairwell cell has their root at the same height as pad 1's surface. Measured from the
-- root, that reads as standing on pad 1: the pad starts crumbling while they are still walking up
-- to it and is gone by the time they jump. Feet: on the pad is 0, on the floor below it is
-- -StepRise, and the two cannot be confused.
--
-- The window is a half-pad-rise of slack downward — the trusted position climbs at a rate and
-- lags a real landing by a tick or two — and StandHeight upward, so sailing over a pad without
-- landing is not standing on it and neither is walking under the shaft.
--
-- Passing `state` and `now` makes a pad that has already fallen away un-standable, which is what
-- stops the server registering a touch on thin air.
function Ascent.padUnder(cfg: any, model: any, pos: any, state: any?, now: number?): (number?, number?)
	local A = cfg.Ascent
	for s = 0, model.storeys - 2 do
		local sh: any = model.shafts[s + 1]
		if sh ~= nil then
			for _, pad in ipairs(sh.pads :: { any }) do
				local dy = (pos.y - cfg.Run.RunnerRootHeight) - pad.y
				if dy >= -model.stepRise / 2 and dy <= A.StandHeight then
					local dx, dz = pos.x - pad.x, pos.z - pad.z
					if math.abs(dx) <= A.StandRadius and math.abs(dz) <= A.StandRadius then
						if state == nil or now == nil or Ascent.solid(cfg, state, s, pad.index, now) then
							return s, pad.index
						end
						return nil, nil
					end
				end
			end
		end
	end
	return nil, nil
end

-- WHAT CHANGED SINCE THE LAST CALL. The server turns each entry into one CanCollide/Transparency
-- write; reporting only the flips is what keeps a five-storey vault from replicating 24 property
-- writes every tick for no reason.
function Ascent.update(cfg: any, state: any, now: number): any
	local changes = {}
	for _, pad in ipairs(state.pads :: { any }) do
		local k = key(pad.storey, pad.index)
		local is = Ascent.solid(cfg, state, pad.storey, pad.index, now)
		local was = state.shown[k]
		if was == nil then was = true end
		if is ~= was then
			state.shown[k] = is
			changes[#changes + 1] = { storey = pad.storey, index = pad.index, solid = is }
		end
	end
	expire(cfg, state, now)
	return changes
end

return Ascent
