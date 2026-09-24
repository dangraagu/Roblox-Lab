--!strict
-- Nightfall.luau — Nightwatch Manor's own rules for how the night LOOKS. Pure, no Roblox, no require.
--
-- The template modules (EnvBands, Hazards, Rest) are game-agnostic. This one holds what is particular
-- to a haunted manor with a hunter in it, and every rule is pinned in tests/Nightfall.spec.luau:
--
--   * PROGRESS is the night number the server credits (State.night), nudged forward by DREAD while a
--     night runs, so the manor visibly wakes up as the clock runs down. Never time. Only surviving a
--     night moves you a whole step; being caught or evicted puts you back where the night started.
--   * WINDOWS go on OUTER walls only (a face with no room behind it), never on the Servants' Exit's
--     wall, never over a room's own feature. They are closed picture-boxes on the inside of a solid
--     wall: nothing is ever seen THROUGH them, so they cannot show a player another room.
--   * FAIRNESS. The chase was tuned under the server's Horror preset, and the eye candy must not hide
--     the Nightwatcher, reveal it, or change the chase. So every band's visibility fields stay inside
--     a hard envelope around that preset (fog, haze, exposure, ambient, grade), no band tints the
--     whole screen red (the watcher's eyes are red), no cosmetic light uses the watcher's two light
--     colours (a decoy), flicker never dims a room below FLICKER_FLOOR, and a lightning flash is
--     capped. A config may make the envelope STRICTER, never looser: the hard numbers live here.
--   * HAZARDS run only at night, never while the Nightwatcher sees you, and not for a quiet window
--     after (it is still hunting). The client calls a hazard off the moment it sees you.
--   * REST is between rounds: the safehouse. A config that allows rest during the night is rejected;
--     the night is a timed round and the server's clock and hunter never pause.

local Nightfall = {}

-- The hard envelope. Numbers are the server's tuned Horror preset (Fx.Presets.Horror) plus a small
-- margin; see EYECANDY.md. Config.Env.Fairness may only tighten these.
Nightfall.HARD = {
	AtmosphereDensityMax = 0.45, -- preset 0.42
	HazeMax = 2.0, -- preset 1.6
	ExposureMin = -0.25, -- preset -0.15
	AmbientLumaMin = 18, -- preset (20, 22, 30) has luma 21.8
	CCBrightnessMin = -0.05, -- preset -0.02
	ContrastMax = 0.3, -- preset 0.18
	TintRedOverGreenMax = 1.12, -- preset (200, 210, 235): 0.95
	TintChannelMin = 170, -- no channel crushed
	FlickerMin = 0.75, -- a flickering light never drops below 75% of what the server built
	FlashBoostMax = 0.15, -- colour-grade brightness a lightning flash may add
	FlashGapMin = 4, -- REAL seconds between two lightning flashes, whatever the band or the dread asks (review 4)
	BlinkHzMax = 2, -- a warning light or marker blinks at most twice a second (WCAG: no more than 3 flashes/s)
	SignatureDistanceMin = 60, -- RGB distance every cosmetic glow keeps from the watcher's lights AND the exit's
	KnockSpeedFractionMax = 0.8, -- a knock is always slower than walking
	KnockLiftMax = 2, -- nothing to fall off in a manor
	TelegraphMin = 3, -- seconds of warning, at least
}

local function isNaN(x: number): boolean
	return x ~= x
end

local function num(x: any, default: number): number
	local n = tonumber(x)
	if n == nil or isNaN(n) then
		return default
	end
	return n
end

--============================================================================ progress + bands

-- Continuous progress for BLENDS: the night number, plus dread x lookahead while a night runs.
-- Lookahead is capped below 1, so dread alone never reaches the next night's value.
function Nightfall.progress(env: any, phase: string?, night: any, dread: any): number
	local n = num(night, 1)
	if phase ~= "NIGHT" then
		return n
	end
	local look = math.clamp(num(env and env.DreadLookahead, 0), 0, 0.99)
	return n + math.clamp(num(dread, 0), 0, 1) * look
end

-- The NAMED band (chip, title card, which hazards fly) goes by the whole night number the HUD shows.
function Nightfall.bandIndex(bands: { any }, night: any): number
	local n = math.floor(num(night, 1))
	local idx = 1
	for i = 2, #bands do
		if n >= bands[i].from then
			idx = i
		else
			break
		end
	end
	return idx
end

-- "🌫️ The Mist · Night 4 · ⛈️ in 6"
function Nightfall.chipText(bands: { any }, night: any): string
	local n = math.floor(num(night, 1))
	local i = Nightfall.bandIndex(bands, n)
	local b = bands[i]
	local text = string.format("%s %s · Night %d", tostring(b.emoji), tostring(b.name), n)
	local nb = bands[i + 1]
	if nb then
		text ..= string.format(" · %s in %d", tostring(nb.emoji), math.max(1, nb.from - n))
	end
	return text
end

--============================================================================ windows

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Faces of the manor with no room behind them, in a fixed order (cells as given, then +X -X +Z -Z).
--   cells: { { gx, gz, kind? } }; exitFace: { gx, gz, dx, dz }? (excluded);
--   skip: { [kind] = { { dx, dz } } }? (a kind's own feature walls, excluded)
function Nightfall.outerFaces(cells: { any }, exitFace: any?, skip: { [string]: any }?): { any }
	local occupied: { [string]: boolean } = {}
	for _, c in cells do
		occupied[c.gx .. "," .. c.gz] = true
	end
	local sorted = table.clone(cells)
	table.sort(sorted, function(a: any, b: any): boolean
		if a.gx ~= b.gx then return a.gx < b.gx end
		return a.gz < b.gz
	end)
	local out = {}
	for _, c in sorted do
		for _, d in DIRS do
			local dx, dz = d[1], d[2]
			if not occupied[(c.gx + dx) .. "," .. (c.gz + dz)] then
				local excluded = exitFace ~= nil and exitFace.gx == c.gx and exitFace.gz == c.gz
					and exitFace.dx == dx and exitFace.dz == dz
				local list = skip and c.kind and skip[c.kind]
				if list then
					for _, s in list do
						if s[1] == dx and s[2] == dz then excluded = true end
					end
				end
				if not excluded then
					table.insert(out, { gx = c.gx, gz = c.gz, dx = dx, dz = dz, kind = c.kind })
				end
			end
		end
	end
	return out
end

-- Where a window sits on a face, relative to its room's centre, and which way it faces (into the room).
--   win = { Along, CentreY, Inset }: slid Along studs along the wall, CentreY up, Inset in from the plane.
function Nightfall.windowPlacement(roomSize: number, win: any, face: any): any
	local half = roomSize / 2
	local depth = half - (win.Inset or 0.55)
	local along = win.Along or 0
	local x, z
	if face.dx ~= 0 then
		x, z = face.dx * depth, along
	else
		x, z = along, face.dz * depth
	end
	return { x = x, y = win.CentreY or 7.5, z = z, nx = -face.dx, nz = -face.dz }
end

--============================================================================ flicker

-- A smooth, bounded, per-light flicker factor. The sum of three sines averages to 1; the clamp keeps it
-- in [lo, hi], and lo is additionally held at FLICKER_FLOOR or above.
function Nightfall.flicker(t: number, seed: number, amp: number, lo: number, hi: number): number
	if amp <= 0 then
		return 1
	end
	local s = num(seed, 0)
	local a1 = 2.1 + (s % 7) * 0.13
	local a2 = 5.3 + (s % 5) * 0.21
	local a3 = 11.7 + (s % 3) * 0.37
	local p1, p2, p3 = (s * 1.618) % 6.2832, (s * 2.718) % 6.2832, (s * 3.1416) % 6.2832
	local noise = 0.5 * math.sin(a1 * t + p1) + 0.3 * math.sin(a2 * t + p2) + 0.2 * math.sin(a3 * t + p3)
	return math.clamp(1 + amp * noise, math.max(lo, Nightfall.HARD.FlickerMin), hi)
end

--============================================================================ lightning + blinking

-- Real seconds until the next lightning flash. The band's own gap (everyMin..everyMax at roll u), shortened as the
-- night's dread rises (1 + dread times as often), and never under HARD.FlashGapMin whatever the band or dread asks.
-- Review 4: the client used to run its countdown at (1 + dread) x real time, so a band that said "at least 5 s"
-- flashed every 2.7 s late in a Witching Hour night, and the only rule checked the config's numbers.
function Nightfall.boltGap(spec: any, dread: any, u: any): number
	local lo = math.max(num(spec and spec.everyMin, 0), 0)
	local hi = math.max(num(spec and spec.everyMax, lo), lo)
	local roll = math.clamp(num(u, 0), 0, 1)
	local d = math.clamp(num(dread, 0), 0, 1)
	return math.max(Nightfall.HARD.FlashGapMin, (lo + (hi - lo) * roll) / (1 + d))
end

-- Is a blinking warning ON at time `now`? At most HARD.BlinkHzMax on-flashes a second, whatever `hz` asks for.
function Nightfall.blink(now: number, hz: any): boolean
	local f = math.clamp(num(hz, Nightfall.HARD.BlinkHzMax), 0, Nightfall.HARD.BlinkHzMax)
	if f <= 0 then
		return true
	end
	return math.floor(num(now, 0) * 2 * f) % 2 == 0
end

--============================================================================ fairness

function Nightfall.colorDistance(a: { number }, b: { number }): number
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dr * dr + dg * dg + db * db)
end

local function luma(c: { number }): number
	return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
end

-- The effective limits: the config's, but never looser than HARD. A looser config value is an error.
local function limits(fair: any): (any?, string?)
	fair = fair or {}
	local H = Nightfall.HARD
	local out = {}
	-- "max" limits: a config may lower them; "min" limits: a config may raise them
	local maxes = { "AtmosphereDensityMax", "HazeMax", "ContrastMax", "TintRedOverGreenMax", "FlashBoostMax" }
	local mins = { "ExposureMin", "AmbientLumaMin", "CCBrightnessMin", "TintChannelMin", "FlickerMin", "SignatureDistanceMin" }
	for _, k in maxes do
		local v = fair[k]
		if v ~= nil and (type(v) ~= "number" or v > H[k]) then
			return nil, "Fairness." .. k .. " loosens the hard envelope (" .. tostring(v) .. " > " .. H[k] .. ")"
		end
		out[k] = if type(v) == "number" then v else H[k]
	end
	for _, k in mins do
		local v = fair[k]
		if v ~= nil and (type(v) ~= "number" or v < H[k]) then
			return nil, "Fairness." .. k .. " loosens the hard envelope (" .. tostring(v) .. " < " .. H[k] .. ")"
		end
		out[k] = if type(v) == "number" then v else H[k]
	end
	return out, nil
end

local function isColor(c: any): boolean
	return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

-- (ok, err). err names the band and the field, or the glow key.
function Nightfall.fairness(cfg: any): (boolean, string?)
	local env = cfg and cfg.Env
	if type(env) ~= "table" or type(env.Bands) ~= "table" then
		return false, "no Env.Bands"
	end
	local L, lerr = limits(env.Fairness)
	if not L then
		return false, lerr
	end
	local sig = env.WatcherSignature
	if type(sig) ~= "table" or #sig == 0 then
		return false, "no Env.WatcherSignature: the fairness check needs the Nightwatcher's own light colours"
	end
	-- review 4: the Servants' Exit's green light is the one cue a player hunts for; a glow in its colour is a decoy for
	-- the way out, as a glow in the watcher's colours is a decoy for the hunter
	local exitSig = env.ExitSignature
	if type(exitSig) ~= "table" or #exitSig == 0 then
		return false, "no Env.ExitSignature: the fairness check needs the Servants' Exit's light colour"
	end

	local amp = num(env.FlickerAmp, 0)
	if amp < 0 or 1 - amp < L.FlickerMin - 1e-9 then
		return false, string.format("FlickerAmp %.2f can dim a room to %.2f, below the flicker floor %.2f", amp, 1 - amp, L.FlickerMin)
	end
	local flash = num(env.FlashBoost, 0)
	if flash < 0 or flash > L.FlashBoostMax + 1e-9 then
		return false, string.format("FlashBoost %.2f is over the lightning cap %.2f", flash, L.FlashBoostMax)
	end

	local function glowOk(where: string, key: string, c: any): (boolean, string?)
		if not isColor(c) then
			return false, where .. " glow '" .. key .. "' is not an {r, g, b} colour"
		end
		for _, s in sig do
			local d = Nightfall.colorDistance(c, s)
			if d < L.SignatureDistanceMin then
				return false, string.format("%s glow '%s' (%d,%d,%d) is %.0f from the Nightwatcher's light (%d,%d,%d); keep it %d away",
					where, key, c[1], c[2], c[3], d, s[1], s[2], s[3], L.SignatureDistanceMin)
			end
		end
		for _, s in exitSig do
			local d = Nightfall.colorDistance(c, s)
			if d < L.SignatureDistanceMin then
				return false, string.format("%s glow '%s' (%d,%d,%d) is %.0f from the Servants' Exit's light (%d,%d,%d); keep it %d away",
					where, key, c[1], c[2], c[3], d, s[1], s[2], s[3], L.SignatureDistanceMin)
			end
		end
		return true, nil
	end

	for key, c in env.Glow or {} do
		local ok, err = glowOk("Env", tostring(key), c)
		if not ok then return false, err end
	end

	for i, b in env.Bands do
		local name = "band " .. tostring(b.id or i)
		local lt, at, cc = b.lighting, b.atmosphere, b.colorCorrection
		if type(lt) ~= "table" or type(at) ~= "table" or type(cc) ~= "table" then
			return false, name .. " must define lighting, atmosphere and colorCorrection (a missing group keeps the last band's)"
		end
		local d = at.Density
		if type(d) ~= "number" then return false, name .. ": atmosphere.Density is unset" end
		if d > L.AtmosphereDensityMax + 1e-9 then
			return false, string.format("%s: atmosphere.Density %.2f is over %.2f (the fog would hide the Nightwatcher)", name, d, L.AtmosphereDensityMax)
		end
		local hz = at.Haze
		if type(hz) ~= "number" then return false, name .. ": atmosphere.Haze is unset" end
		if hz > L.HazeMax + 1e-9 then
			return false, string.format("%s: atmosphere.Haze %.2f is over %.2f", name, hz, L.HazeMax)
		end
		local ex = lt.ExposureCompensation
		if type(ex) ~= "number" then return false, name .. ": lighting.ExposureCompensation is unset" end
		if ex < L.ExposureMin - 1e-9 then
			return false, string.format("%s: lighting.ExposureCompensation %.2f is under %.2f", name, ex, L.ExposureMin)
		end
		if not isColor(lt.Ambient) then return false, name .. ": lighting.Ambient is unset" end
		if luma(lt.Ambient) < L.AmbientLumaMin - 1e-9 then
			return false, string.format("%s: lighting.Ambient luma %.1f is under %.1f", name, luma(lt.Ambient), L.AmbientLumaMin)
		end
		local br = cc.Brightness
		if type(br) ~= "number" then return false, name .. ": colorCorrection.Brightness is unset" end
		if br < L.CCBrightnessMin - 1e-9 then
			return false, string.format("%s: colorCorrection.Brightness %.2f is under %.2f", name, br, L.CCBrightnessMin)
		end
		local ct = cc.Contrast
		if type(ct) ~= "number" then return false, name .. ": colorCorrection.Contrast is unset" end
		if ct > L.ContrastMax + 1e-9 then
			return false, string.format("%s: colorCorrection.Contrast %.2f is over %.2f", name, ct, L.ContrastMax)
		end
		local tint = cc.TintColor
		if not isColor(tint) then return false, name .. ": colorCorrection.TintColor is unset" end
		if tint[1] / math.max(tint[2], 1) > L.TintRedOverGreenMax + 1e-9 then
			return false, string.format("%s: colorCorrection.TintColor (%d,%d,%d) tints the whole screen red (red/green %.2f > %.2f)",
				name, tint[1], tint[2], tint[3], tint[1] / math.max(tint[2], 1), L.TintRedOverGreenMax)
		end
		if math.min(tint[1], tint[2], tint[3]) < L.TintChannelMin then
			return false, string.format("%s: colorCorrection.TintColor (%d,%d,%d) crushes a channel below %d",
				name, tint[1], tint[2], tint[3], L.TintChannelMin)
		end
		for key, c in b.glow or {} do
			local ok, err = glowOk(name, tostring(key), c)
			if not ok then return false, err end
		end
	end
	return true, nil
end

--============================================================================ hazards

-- What the hazard clock does now. ctx = { phase, spotted, sinceSpotted }.
--   "freeze": outside the night (the day, the beat after a night ends, before the profile loads): the clock stops
--             and nothing launches. Resting in the safehouse can therefore neither thin nor bunch hazards.
--   "hold":   at night while the Nightwatcher sees you and for QuietAfterSpottedSeconds after (it is still hunting):
--             the clock RUNS, but nothing launches (Hazards ctx.held). Review 4: a frozen clock made hazards come
--             more often per minute in the manor the better a player hid; a held one keeps the rate per minute of
--             night for everyone, and still never fires into a chase.
--   "run":    at night, unhunted: the clock runs and a due hazard may launch.
function Nightfall.hazardClock(hz: any, ctx: any): string
	if ctx.phase ~= "NIGHT" then
		return "freeze"
	end
	if ctx.spotted then
		return "hold"
	end
	if num(ctx.sinceSpotted, math.huge) < num(hz and hz.QuietAfterSpottedSeconds, 0) then
		return "hold"
	end
	return "run"
end

-- May a hazard launch right now? (Exactly hazardClock == "run".)
function Nightfall.hazardGate(hz: any, ctx: any): boolean
	return Nightfall.hazardClock(hz, ctx) == "run"
end

-- The hazard rules that exist because of the chase. (ok, err).
function Nightfall.validateHazards(cfg: any): (boolean, string?)
	local H = Nightfall.HARD
	local hz = cfg and cfg.Hazards
	if type(hz) ~= "table" then return false, "no Hazards config" end
	local walk = num(cfg.Player and cfg.Player.WalkSpeed, 0)
	local hunt = num(cfg.Watcher and cfg.Watcher.HuntSeconds, math.huge)
	local frac = num(hz.KnockSpeedFractionMax, H.KnockSpeedFractionMax)
	if frac > H.KnockSpeedFractionMax then
		return false, "KnockSpeedFractionMax loosens the hard cap " .. H.KnockSpeedFractionMax
	end
	if num(hz.QuietAfterSpottedSeconds, 0) < hunt + 1 then
		return false, string.format("QuietAfterSpottedSeconds (%s) must outlast the Nightwatcher's hunt (%s s) by 1 s: "
			.. "a hazard must never fire into a live chase", tostring(hz.QuietAfterSpottedSeconds), tostring(hunt))
	end
	if num(hz.KnockLift, 0) > H.KnockLiftMax then
		return false, "KnockLift " .. tostring(hz.KnockLift) .. " is over " .. H.KnockLiftMax .. ": there is nothing to fall off in a manor"
	end
	if num(hz.MinTelegraphSeconds, 0) < H.TelegraphMin then
		return false, "MinTelegraphSeconds under " .. H.TelegraphMin .. " s: a hazard must be easy to see coming"
	end
	for name, k in hz.Kinds or {} do
		if num(k.knock, math.huge) > walk * frac + 1e-9 then
			return false, string.format("hazard kind %s: knock %.1f is over %.0f%% of WalkSpeed (%.1f): a knock must never be a speed boost",
				tostring(name), num(k.knock, 0), frac * 100, walk * frac)
		end
		if num(k.telegraph, 0) < H.TelegraphMin then
			return false, "hazard kind " .. tostring(name) .. ": telegraph under " .. H.TelegraphMin .. " s"
		end
		-- the hit lands when the hazard's reach (hitRadius + PlayerRadius) touches the player, reach/speed
		-- seconds before its centre arrives; the warning must cover the EARLIEST hit, not the arrival
		local speed = num(k.speed, 0)
		if speed > 0 then
			local earliest = num(k.telegraph, 0) - (num(k.hitRadius, 0) + num(hz.PlayerRadius, 0)) / speed
			if earliest < H.TelegraphMin - 1e-9 then
				return false, string.format("hazard kind %s: its earliest hit comes %.2f s after the warning (under %d s); "
					.. "raise telegraph to at least %.2f", tostring(name), earliest, H.TelegraphMin,
					H.TelegraphMin + (num(k.hitRadius, 0) + num(hz.PlayerRadius, 0)) / speed)
			end
		end
	end
	return true, nil
end

-- Where to aim a hazard at a walking player: where they will be when it arrives, at most `leadSeconds`
-- ahead, on the ground plane. `maxSpeed` (optional) clamps a velocity that is not walking (a knock).
function Nightfall.leadAim(pos: any, vel: any, remaining: number, leadSeconds: number, maxSpeed: number?): any
	local lead = math.clamp(num(remaining, 0), 0, math.max(num(leadSeconds, 0), 0))
	local vx, vz = num(vel.x, 0), num(vel.z, 0)
	local sp = math.sqrt(vx * vx + vz * vz)
	if maxSpeed and sp > maxSpeed and sp > 0 then
		vx, vz = vx / sp * maxSpeed, vz / sp * maxSpeed
	end
	return { x = pos.x + vx * lead, y = pos.y, z = pos.z + vz * lead }
end

--============================================================================ rest

function Nightfall.validateRest(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" or type(cfg.Phases) ~= "table" then
		return false, "Rest.Phases must list where resting is allowed"
	end
	if cfg.Phases.NIGHT then
		return false, "Rest.Phases.NIGHT must be off: the night is a timed round, and resting inside it would pause "
			.. "nothing the server runs (dread and the Nightwatcher keep going) while promising safety"
	end
	return true, nil
end

function Nightfall.restAllowed(cfg: any, phase: string?): boolean
	return phase ~= nil and type(cfg) == "table" and type(cfg.Phases) == "table" and cfg.Phases[phase] == true
end

--============================================================================ the safehouse

function Nightfall.cosyTier(tiers: { any }, hubLevel: any): number
	local lv = num(hubLevel, 0)
	local idx = 1
	for i, t in tiers do
		if lv >= t.minLevel then idx = i end
	end
	return idx
end

--============================================================================ portraits

-- The pupil's offset in the canvas plane, toward `target`: up to maxShift, scaled by how far off-axis
-- the target is. Plain {x,y,z}; `normal` is the canvas's unit normal.
function Nightfall.pupil(home: any, normal: any, target: any, maxShift: number): any
	local dx, dy, dz = target.x - home.x, target.y - home.y, target.z - home.z
	local along = dx * normal.x + dy * normal.y + dz * normal.z
	local px, py, pz = dx - normal.x * along, dy - normal.y * along, dz - normal.z * along
	local planar = math.sqrt(px * px + py * py + pz * pz)
	local full = math.sqrt(dx * dx + dy * dy + dz * dz)
	if planar < 1e-6 or full < 1e-6 then
		return { x = 0, y = 0, z = 0 }
	end
	local s = maxShift * math.min(1, planar / full * 1.5) / planar
	return { x = px * s, y = py * s, z = pz * s }
end

return Nightfall
