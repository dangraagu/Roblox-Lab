-- EnvConfig — the environment's numbers in Config are internally consistent and keep the game
-- readable. Run: luau tests/EnvConfig.spec.luau
--
-- Config.Env / Config.Hazards / Config.Rest / Config.Budget are tuning, and tuning drifts. These are
-- the properties that must survive any retune:
--   * every band blends every field (a field one band lacks would freeze at a stale value);
--   * THE OBBY STAYS READABLE: at every depth the game can reach, including half-blended fade floors,
--     the pad colour the client paints stands out against the floor under it and the wall behind it,
--     and still does when it is cracked a moment before it goes;
--   * a ceiling drop fits the vault: it hangs at the ceiling, its ring fits a corridor, a standing
--     player can walk out of it after the lock, and it cannot reach the storey above or below;
--   * rest is valid as the template demands, and does nothing a run depends on.
local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local VaultEnv = require("../src/shared/VaultEnv")

local passed, failed = 0, 0
local function ok(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end

local Env = Config.Env
local bands = Env.Bands
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sky" }

--============================================================================ bands

do
	local valid, err = EnvBands.validate(bands)
	ok(valid, "Config.Env.Bands validates (" .. tostring(err) .. ")")
	ok(#bands == 5, "five strata: bank, tomb, reactor, frozen, volcano (" .. #bands .. ")")
	-- the hub and every band define exactly the same fields in every group
	for _, g in GROUPS do
		for k in Env.Hub[g] do
			for _, b in bands do
				ok(b[g] ~= nil and b[g][k] ~= nil, string.format("band %s defines %s.%s (the hub does)", b.id, g, k))
			end
		end
		for _, b in bands do
			for k in b[g] or {} do
				ok(Env.Hub[g][k] ~= nil, string.format("the hub defines %s.%s (band %s does)", g, k, b.id))
			end
		end
	end
	for _, b in bands do
		ok(type(b.name) == "string" and type(b.emoji) == "string" and type(b.blurb) == "string", "band " .. b.id .. " has a name, emoji and blurb")
		ok(b.palette and b.palette.wall and b.palette.floor and b.palette.pad and b.palette.accent and b.palette.glow and b.palette.crack,
			"band " .. b.id .. " has a full palette")
		ok(b.weather and b.weather.rate > 0 and b.weather.rate <= Config.Budget.MaxWeatherRate,
			string.format("band %s's weather (%s/s) fits the weather budget", b.id, tostring(b.weather and b.weather.rate)))
		ok(b.props and b.props.density > 0 and b.props.density <= 0.5, "band " .. b.id .. " hangs props in at most half its cells")
		ok(type(b.piece) == "string", "band " .. b.id .. " has a set piece")
		for _, h in b.hazards or {} do
			ok(Config.Hazards.Kinds[h] ~= nil, "band " .. b.id .. "'s hazard " .. h .. " exists")
		end
		ok(#(b.hazards or {}) >= 1, "band " .. b.id .. " has a hazard of its own")
	end
	ok(Env.HalfLife > 0 and Env.LightingHz > 0 and Env.LightingHz <= 15, "values glide and Lighting is written at most 15 times a second")
	ok(Env.DangerStuds > 0 and Env.MaxDangerBlend > 0 and Env.MaxDangerBlend <= 0.6,
		"the collapse grade is capped so it never swamps the vault (" .. Env.MaxDangerBlend .. ")")
	ok(Env.ShaftWeatherScale >= 0 and Env.ShaftWeatherScale <= 0.5, "weather thins to at most half in the shaft")
	for t = 2, #Env.TierDepth do
		ok(Env.TierDepth[t] > Env.TierDepth[t - 1], "tier " .. t .. " is buried deeper than tier " .. (t - 1))
	end
end

--============================================================================ the obby stays readable

do
	local worstPad, worstPadAt = math.huge, 0
	local worstWall, worstWallAt = math.huge, 0
	local worstCrack, worstCrackAt = math.huge, 0
	for i = 0, 100 * 8 do
		local depth = i / 8
		local pal = VaultEnv.palette(Config, EnvBands, depth)
		local cp = VaultEnv.contrast(pal.pad, pal.floor)
		if cp < worstPad then worstPad, worstPadAt = cp, depth end
		local cw = VaultEnv.contrast(pal.pad, pal.wall)
		if cw < worstWall then worstWall, worstWallAt = cw, depth end
		local cracked = VaultEnv.crackedPad(Config, pal, 1)
		local cc = VaultEnv.contrast(cracked, pal.floor)
		if cc < worstCrack then worstCrack, worstCrackAt = cc, depth end
	end
	print(string.format("  worst contrast over depths 0-100: pad/floor %.2f (depth %.2f), pad/wall %.2f (%.2f), cracked pad/floor %.2f (%.2f)",
		worstPad, worstPadAt, worstWall, worstWallAt, worstCrack, worstCrackAt))
	ok(worstPad >= 3, string.format("a pad always stands out against the floor under it (worst %.2f:1 at depth %.2f)", worstPad, worstPadAt))
	ok(worstWall >= 1.5, string.format("and against the wall behind it (worst %.2f:1 at depth %.2f)", worstWall, worstWallAt))
	ok(worstCrack >= 2, string.format("and a pad about to crumble is still visible (worst %.2f:1 at depth %.2f)", worstCrack, worstCrackAt))
	-- the crack must be visibly different from an intact pad
	local worstDiff = math.huge
	for i = 0, 100 * 4 do
		local pal = VaultEnv.palette(Config, EnvBands, i / 4)
		worstDiff = math.min(worstDiff, VaultEnv.contrast(VaultEnv.crackedPad(Config, pal, 1), pal.pad))
	end
	ok(worstDiff >= 1.5, string.format("a cracked pad looks different from a whole one (worst %.2f:1)", worstDiff))
	-- a pure band's pad is that band's own pad colour (the choice only steps in where bands blend)
	for _, b in bands do
		local pal = VaultEnv.palette(Config, EnvBands, b.from + 0.5)
		local same = pal.pad[1] == b.palette.pad[1] and pal.pad[2] == b.palette.pad[2] and pal.pad[3] == b.palette.pad[3]
		ok(same, "in the middle of " .. b.name .. " its pads are its own colour")
	end
end

--============================================================================ the crack is held until the server drops the pad

do
	-- The crack follows the SERVER's pad (VaultEnv.padLook). Once the runner has stepped off, it is
	-- held at full for CrackHoldSeconds past the crumble: long enough to cover the server's lag (its
	-- run loop's tick, its Trace catching up, one round trip), never as long as a pad stays away.
	local hold = Env.CrackHoldSeconds
	ok(type(hold) == "number" and hold >= 5 * Config.Run.TickSeconds,
		string.format("a crack is held at least five server ticks past the crumble (%s s)", tostring(hold)))
	ok(type(hold) == "number" and hold <= Config.Ascent.RespawnSeconds,
		"and never longer than a dropped pad stays away")
	ok(type(Env.PadFlashSeconds) == "number" and Env.PadFlashSeconds > 0 and Env.PadFlashSeconds <= 1,
		"a pad that comes back flashes, briefly (" .. tostring(Env.PadFlashSeconds) .. " s)")
end

--============================================================================ gems stay findable

do
	-- The client repaints walls and floors per stratum; a gem keeps its tier's colour only where that
	-- still reads, and wears the stratum's own gem colour where it would vanish (VaultEnv.gem). The
	-- floor bar is the pads' own; the wall bar is what a bright gem can reach on the tomb's sandstone.
	-- HEAD's gems on HEAD's tier walls read 2.9:1 and up; the eye candy took them to 1.04:1.
	ok(Env.MinGemContrast >= 3, "a gem must stand out at least 3:1 against the floor under it (" .. tostring(Env.MinGemContrast) .. ")")
	ok(Env.MinGemWallContrast >= 1.8, "and 1.8:1 against the walls behind it (" .. tostring(Env.MinGemWallContrast) .. ")")
	for _, b in bands do
		ok(type(b.palette.gem) == "table" and #b.palette.gem == 3, "band " .. b.id .. " has a gem colour of its own")
	end
	for t, tier in Config.Tiers do
		local own = { tier.gemColor.r, tier.gemColor.g, tier.gemColor.b }
		local worstF, worstFAt, worstW, worstWAt, recoloured, fallback = math.huge, 0, math.huge, 0, 0, 0
		for i = 0, 100 * 8 do
			local depth = i / 8
			local pal = VaultEnv.palette(Config, EnvBands, depth)
			local g = VaultEnv.gem(Config, pal, t)
			local cf, cw = VaultEnv.contrast(g, pal.floor), VaultEnv.contrast(g, pal.wall)
			if cf < worstF then worstF, worstFAt = cf, depth end
			if cw < worstW then worstW, worstWAt = cw, depth end
			local isOwn = g[1] == own[1] and g[2] == own[2] and g[3] == own[3]
			local isBand = false
			for _, id in { pal.band, pal.next } do
				local c = bands[id].palette.gem
				if g[1] == c[1] and g[2] == c[2] and g[3] == c[3] then isBand = true end
			end
			if not isOwn then recoloured += 1 end
			if not isOwn and not isBand then fallback += 1 end
		end
		print(string.format("  %s gems over depths 0-100: worst %.2f:1 against the floor (depth %.2f), %.2f:1 against the wall (%.2f); recoloured at %d of 801 depths",
			tier.name, worstF, worstFAt, worstW, worstWAt, recoloured))
		ok(worstF >= Env.MinGemContrast, string.format("%s: a gem always stands out against the floor (worst %.2f:1 at depth %.2f)", tier.name, worstF, worstFAt))
		ok(worstW >= Env.MinGemWallContrast, string.format("%s: and against the wall (worst %.2f:1 at depth %.2f)", tier.name, worstW, worstWAt))
		ok(fallback == 0, string.format("%s: the shipped strata never need the black-or-white fallback (%d depths did)", tier.name, fallback))
		ok(recoloured < 801, tier.name .. ": and somewhere its gems keep the tier's own colour")
	end
end

--============================================================================ the drop's ring stays visible

do
	-- The ring IS the danger zone, and it is the first ~2 s of the telegraph. It must read against
	-- every stratum's floor (the floor under a ring is always one band's own: VaultEnv.palette), both
	-- while it follows and once it locks, and the lock must look different from the follow.
	ok(Env.MinRingContrast >= 3, "the ring must stand out at least 3:1 against the floor (" .. tostring(Env.MinRingContrast) .. ")")
	for _, b in bands do
		local floor = b.palette.floor
		local f, l = VaultEnv.ring(Config, floor, false), VaultEnv.ring(Config, floor, true)
		local fo, lo = VaultEnv.ringOver(f.color, f.transparency, floor), VaultEnv.ringOver(l.color, l.transparency, floor)
		local cf, cl = VaultEnv.contrast(fo, floor), VaultEnv.contrast(lo, floor)
		local d = math.sqrt((fo[1] - lo[1]) ^ 2 + (fo[2] - lo[2]) ^ 2 + (fo[3] - lo[3]) ^ 2)
		print(string.format("  ring on the %s floor: following %.2f:1, locked %.2f:1, the two %.0f apart", b.id, cf, cl, d))
		ok(cf >= Env.MinRingContrast, string.format("the following ring reads on the %s floor (%.2f:1)", b.id, cf))
		ok(cl >= Env.MinRingContrast, string.format("so does the locked ring (%.2f:1)", cl))
		ok(d >= 60, string.format("and the lock looks different from the follow on the %s floor (%.0f apart in RGB)", b.id, d))
		ok(f.transparency >= 0 and f.transparency < 1 and l.transparency >= 0 and l.transparency < 1, "both rings are drawn (" .. b.id .. ")")
	end
end

--============================================================================ ceiling drops fit the vault

do
	local H = Config.Hazards
	local valid, err = Hazards.validate(H)
	ok(valid, "Config.Hazards validates (" .. tostring(err) .. ")")
	local V = Config.Vault
	local wallHeight = V.StoreyHeight - V.FloorThickness
	local jumpPeak = Config.Movement.JumpPower ^ 2 / (2 * Config.Movement.Gravity)
	for name, k in H.Kinds do
		ok(k.dropHeight + Config.Run.RunnerRootHeight <= wallHeight + 1e-9,
			string.format("%s hangs at or under the ceiling (%.1f of %.1f)", name, k.dropHeight + Config.Run.RunnerRootHeight, wallHeight))
		local ring = k.hitRadius + H.PlayerRadius
		ok(2 * ring <= 0.6 * V.CellSize, string.format("%s's ring (%.1f across) leaves room beside it in a %d-stud corridor", name, 2 * ring, V.CellSize))
		ok(k.commit >= (ring + H.PlayerRadius) / Config.Movement.WalkSpeed + 0.4,
			string.format("%s: after the lock a standing player can walk out of the ring with 0.4 s to react", name))
		ok(k.reach >= jumpPeak, string.format("%s still hits a player who jumps on the spot (reach %.1f, jump peak %.2f): the ring is the rule", name, k.reach, jumpPeak))
		ok(k.reach < V.StoreyHeight / 2, string.format("%s cannot reach the storey above or below (reach %.1f)", name, k.reach))
		ok(type(k.name) == "string", name .. " has a name for the warning banner")
		ok(k.telegraph >= 3, name .. " is on screen at least 3 s before it lands")
	end
	ok(H.IntervalMin >= 120 and H.IntervalMax <= 180, "one drop per 2-3 minutes of run time")
	ok(H.GraceSeconds >= 10, "no drop in the first 10 s of a run")
	ok(H.QuietBeforeSealSeconds >= Config.Run.SealWarnSeconds, "none once the HUD's seal warning could be showing")
	ok(H.KnockSeconds > 0 and H.KnockSeconds <= 1.5, "a knock-down lasts a moment, not a penalty")
	-- tests/VaultModel.luau charges a hit StunSeconds; a model that charged less than the game's own
	-- knock-down would under-price every hit tests/Pacing.spec.luau measures
	for name, prof in Config.Pacing.Profiles do
		ok(prof.StunSeconds >= H.KnockSeconds, string.format("the %s pacing profile charges a hit at least the game's knock-down (%.1f >= %.1f s)",
			name, prof.StunSeconds, H.KnockSeconds))
	end
end

--============================================================================ rest

do
	local valid, err = Rest.validate(Config.Rest)
	ok(valid, "Config.Rest validates (" .. tostring(err) .. ")")
	ok(Config.Rest.IdleSeconds == 0, "no idle rest: nothing in the hub to rest from, and nothing in a run may pause")
	ok(Config.Rest.PendingSeconds > 0, "a queued rest expires")
end

--============================================================================ budgets

do
	local B = Config.Budget
	ok(B.MaxWeatherEmitters <= B.MaxEmitters, "weather emitters are inside the emitter budget")
	ok(B.MaxWeatherRate <= B.MaxEmitterRate, "and so is their rate")
	ok(B.MaxHazards == 1, "one drop at a time")
	ok(B.MaxLocalParts <= 250, "the client never plans for more than 250 local parts on top of the vault")
	ok(Env.PropBottomAboveFloor >= 12 and Env.PropBottomAboveFloor < Config.Vault.StoreyHeight - Config.Vault.FloorThickness,
		"a hanging prop stays above a jumping head and below the ceiling")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
