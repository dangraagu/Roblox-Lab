-- Spec for BreakRoom: what "rest" means in a timed maze. Run: luau tests/BreakRoom.spec.luau
--
-- A Roblox server cannot stop the world for one player, and in this game the run clock IS the
-- medal and the record, the traps pulse on the server and the monsters hunt on the server. So a
-- pause inside a run would either freeze nothing that matters (and lie to the player) or freeze the
-- clock (and hand out free medal time). Rest therefore lives BETWEEN runs:
--   * the lobby is the break room: bright, no monsters, no traps, no hazards, no clock running;
--     a campfire there lets you sit down (the template's Rest state: wake on any move);
--   * every level starts next to the 🚪 Lobby door. For the first seconds of a level walking out is
--     free (the server's own Assist rule: a voluntary return shorter than MinRunSeconds is not
--     counted as a failed attempt), and a sign on the door says so, only while it is true;
--   * rest is never available inside a run.
local BreakRoom = require("../src/shared/BreakRoom")
local Rest = require("../src/shared/Rest")
local Biomes = require("../src/shared/Biomes")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local CFG = Biomes.Rest

--================================================================ validate

do
	local ok, err = BreakRoom.validate(CFG, Rest)
	truthy(ok, "the shipped break-room config validates (" .. tostring(err) .. ")")
end
local function mutated(key, value)
	local c = table.clone(CFG)
	c[key] = value
	return (BreakRoom.validate(c, Rest))
end
eq(mutated("FreeBreakSeconds", 7.5), false, "a sign that promises 'free' after the server stops treating it as free is rejected")
eq(mutated("ServerMinRunSeconds", 0), false, "a missing server rule is rejected")
eq(mutated("LatencyMarginSeconds", 0.1), false, "a latency margin under one second is rejected")
eq(mutated("WakeOnMove", false), false, "rest that survives moving is rejected (Rest.validate)")
eq(mutated("BlockWhileThreat", false), false, "rest that can start under a threat is rejected (Rest.validate)")
truthy(CFG.FreeBreakSeconds + CFG.LatencyMarginSeconds <= CFG.ServerMinRunSeconds,
	"the sign's window ends at least LatencyMarginSeconds before the server's rule does")
eq(CFG.ServerMinRunSeconds, 8, "mirrors the server's CONFIG.Assist.MinRunSeconds (a headless check parses the server to confirm)")

--================================================================ the free-break sign

eq(BreakRoom.freeBreak(0, CFG), true, "a level that just started: walking out is free")
eq(BreakRoom.freeBreak(CFG.FreeBreakSeconds - 0.01, CFG), true, "free until the end of the window")
eq(BreakRoom.freeBreak(CFG.FreeBreakSeconds, CFG), false, "not after")
eq(BreakRoom.freeBreak(-1, CFG), false, "a negative clock (no payload yet) is not a promise")
eq(BreakRoom.freeBreak(0 / 0, CFG), false, "NaN is not a promise")
approx(BreakRoom.signAlpha(0, CFG), 1, 1e-9, "the sign is fully shown at the start")
approx(BreakRoom.signAlpha(CFG.FreeBreakSeconds - CFG.SignFadeSeconds, CFG), 1, 1e-9, "fully shown until it starts fading")
approx(BreakRoom.signAlpha(CFG.FreeBreakSeconds - CFG.SignFadeSeconds / 2, CFG), 0.5, 1e-6, "half faded halfway through the fade")
approx(BreakRoom.signAlpha(CFG.FreeBreakSeconds, CFG), 0, 1e-9, "gone exactly when the free window ends")
approx(BreakRoom.signAlpha(CFG.FreeBreakSeconds + 5, CFG), 0, 1e-9, "and stays gone")
do
	-- the sign is never visible while a walk-out would count
	local lied = 0
	for i = 0, 2000 do
		local t = i * 0.01
		if BreakRoom.signAlpha(t, CFG) > 0 and not BreakRoom.freeBreak(t, CFG) then lied += 1 end
		-- the client's clock starts when the payload ARRIVES, after the server's; with up to
		-- LatencyMarginSeconds of delay the server has counted t + margin
		if BreakRoom.signAlpha(t, CFG) > 0 and t + CFG.LatencyMarginSeconds >= CFG.ServerMinRunSeconds then lied += 1 end
	end
	eq(lied, 0, "the sign never shows while a walk-out would count as a failed attempt, even with network delay")
end

--================================================================ (review fix) a paid guide is lost on a walk-out
-- The "Hjelp meg" guide (Assist) is bought for ONE run and belongs to it: the server builds it into that
-- run's maze instance, and leaving the run tears the instance down with no refund. So while a guide is
-- active, walking out is NOT "free, nothing is lost", and the sign must not say so. (Found by the
-- adversarial review: a player who bought a 250-coin guide at level 42 walked out under the sign and lost it.)
do
	local guide = { guideActive = true }
	local none = { guideActive = false }
	eq(BreakRoom.freeBreak(0, CFG, guide), false, "with a paid guide active, walking out is not free (the guide is lost)")
	approx(BreakRoom.signAlpha(0, CFG, guide), 0, 1e-9, "so the sign does not show at the start of the run")
	approx(BreakRoom.signAlpha(CFG.FreeBreakSeconds - CFG.SignFadeSeconds / 2, CFG, guide), 0, 1e-9, "nor while it would be fading")
	eq(BreakRoom.freeBreak(0, CFG, none), true, "without a guide the walk-out is free, as before")
	approx(BreakRoom.signAlpha(0, CFG, none), 1, 1e-9, "and the sign shows, as before")
	approx(BreakRoom.signAlpha(0, CFG, nil), 1, 1e-9,
		"no run info = no guide (a guide can only be bought inside the run, and its state arrives when it is)")
	local lied = 0
	for i = 0, 800 do
		if BreakRoom.signAlpha(i * 0.01, CFG, guide) > 0 then lied += 1 end
		if BreakRoom.freeBreak(i * 0.01, CFG, guide) then lied += 1 end
	end
	eq(lied, 0, "the sign never promises 'nothing is lost' while a paid guide would be lost")
end

--================================================================ where rest is allowed

eq(BreakRoom.mayRest({ inLobby = true }), true, "rest in the lobby")
eq(BreakRoom.mayRest({ inLobby = false }), false, "never inside a run")
eq(BreakRoom.mayRest({}), false, "unknown whereabouts: no rest (fail closed)")
eq(BreakRoom.mayRest({ inLobby = true, dead = true }), false, "not while dead")

--================================================================ the campfire rest is the template's Rest

do
	local s = Rest.new()
	local lobby = { moving = false, grounded = true, threat = false }
	eq(Rest.request(s, CFG, lobby), "resting", "sitting by the fire starts at once (nothing threatens you in the lobby)")
	eq(Rest.update(s, CFG, 0.1, lobby), nil, "resting stays resting while you sit still")
	eq(Rest.update(s, CFG, 1.0, { moving = true, grounded = true, threat = false }), "woke", "any move wakes you")
	eq(Rest.isResting(s), false, "and you are up")
	local s2 = Rest.new()
	for _ = 1, 600 do Rest.update(s2, CFG, 1, lobby) end
	eq(Rest.isResting(s2), false, "idle rest is off: standing still in the lobby never sits you down by itself")
end

print(string.format("BreakRoom: %d passed, %d failed", passed, failed))
if failed > 0 then error("BreakRoom spec failed", 0) end
