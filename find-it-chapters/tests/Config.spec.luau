-- Spec for the design-critical numbers in Config (DESIGN.md §3-§9, §11, §12, §18). Run: luau tests/Config.spec.luau 2>&1
-- A retune of any of these changes what the game IS; each line says why it is pinned. The clocks are pinned by
-- tests/Pacing.spec.luau (derived from the normal profile on the real layout), not here.
local Config = require("../src/shared/Config")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local EnvBands = require("../src/shared/EnvBands")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

--============================================================ the book
eq(#Config.Chapters, 15, "Book One has 15 chapters")
local items = 0
for ch, c in Config.Chapters do
	items += c.n
	truthy(c.S >= c.n * c.k, "chapter " .. ch .. ": S >= n * k")
	truthy(c.W <= Config.Room.ShellW and c.D <= Config.Room.ShellD, "chapter " .. ch .. " fits the lane shell")
	for f in c.forms do truthy(Config.Forms[f] ~= nil, "chapter " .. ch .. " form " .. f .. " exists") end
end
eq(items, 93, "BOOK ONE SOLVED: you found all 93 things (the sum of n)")
eq(Config.Search.LooksSlack, 2, "looks = n * k + 2: careful play never runs out, tapping everything does [DESIGN §3.5]")
eq(Config.Search.Seconds, 1.0, "a search takes 1.0 s, hit or miss [DESIGN §3.4]")
eq(Config.Search.Reach, 10, "reach 10 studs [DESIGN §3.4]")
eq(Config.Search.ReachSlack, 2, "the server allows 2 studs of slack")
eq(Config.Search.SwiftFraction, 2 / 3, "Swift: the first two thirds of the clock")
eq(Config.Search.SharpSlips, 1, "Sharp Eye allows one slip (phones mis-tap)")
eq(Config.Pause.ResumeMinSeconds, 3, "a Resume lands no sooner than 3 s after the Pause [DESIGN §9]")
-- REVIEW-1 round 2, C2: an unbounded Pause carried a Daily's start-day credit across midnight; a room closes after
-- 10 minutes of break in total (the hub is where a long break belongs: nothing there runs a clock)
eq(Config.Pause.MaxBreakSeconds, 600, "a room closes after 600 s of break in total (C2)")
eq(Config.Limits.Hub, 1.0, "Hub has its own bucket, never shared with Next/Retry (D4: a refused Next swallowed a Hub tap)")
-- REVIEW-1 round 2, C3: a load that finds the old server's lock still held retries within seconds, not at the 20 s tick
truthy(Config.Save.QuickRetrySeconds >= 2 and Config.Save.QuickRetrySeconds <= 5, "a locked or failed first load is retried after 2-5 s (C3)")
truthy(Config.Save.QuickRetries >= 3, "... at least 3 times before the 20 s autosave tick takes over")
eq(Config.Daily.OpensAfter, 3, "the Daily opens after chapter 3")
eq(Config.Daily.FirstDay, 20733, "Case #1 is 2026-10-07 (dayIndex 20733)")

--============================================================ hazards: the reviewed indoor config [DESIGN §8]
local ok, err = Hazards.validate(Config.Hazards)
eq(ok, true, "Hazards.validate accepts the config (" .. tostring(err) .. ")")
-- REVIEW-1 round 2, D5: the game's hazard clock runs only on a legal spot (the room shrunk by LegalInset, off the door
-- mat); with that rule in FinderModel, 100-140 s gave one near-miss per 3.13 min. 85-120 s is re-measured by Pacing.spec.
eq(Config.Hazards.IntervalMin, 85, "85-120 s of exposed time (Pacing.spec, legal-spot exposure: one near-miss per 2-3 min)")
eq(Config.Hazards.IntervalMax, 120, "...")
eq(Config.Hazards.PitchDegrees, 85, "ctx.pitch = rad(85): a drop from the ceiling, never through a wall")
for name, k in Config.Hazards.Kinds do
	eq(k.commit, k.telegraph, name .. ": commit = telegraph, the ring never moves (escape-room-lab REVIEW-1 B1)")
	eq(k.pitch, 85, name .. ": pitch 85")
	truthy(k.speed * k.telegraph < Config.Room.Height, name .. ": the drop starts under the ceiling (speed x telegraph < 16)")
	eq(k.hitRadius + Config.Hazards.PlayerRadius, 3.5, name .. ": the ring's radius is 3.5 (a 7-stud ring)")
end
eq(Config.Hazards.KnockLift, 0, "a stumble, never a launch")
truthy(Config.World.LegalInset >= Config.Hazards.Kinds.pinecone.hitRadius + Config.Hazards.PlayerRadius,
	"a legal spot keeps the whole ring on the floor of the room")

--============================================================ rest [DESIGN §9]
local okR, errR = Rest.validate(Config.Rest)
eq(okR, true, "Rest.validate accepts the config (" .. tostring(errR) .. ")")
eq(Config.Rest.IdleSeconds, 0, "no idle rest: standing still is how a room is read")
eq(Config.Rest.WakeOnMove, true, "a move wakes")
eq(Config.Rest.BlockWhileThreat, true, "never with a drop on its way")
truthy(Config.Rest.PendingSeconds >= 3.6, "a queued pause outlives the longest drop")

--============================================================ bands [DESIGN §7]
eq(EnvBands.validate(Config.Env.Bands), true, "EnvBands.validate accepts the bands")
eq(Config.Env.HalfLife, 0.8, "the light glides at a 0.8 s half-life")
eq(Config.Env.LightingHz, 10, "Lighting is written at most 10 times a second")

--============================================================ budgets [DESIGN §18]
eq(Config.Budget.LocalParts, 280, "280 local parts in a room")
eq(Config.Budget.Lights, 4, "4 lights")
eq(Config.Budget.Emitters, 4, "4 emitters: 2 weather, the found burst, the hint glint")
eq(Config.Budget.WeatherEmitters, 2, "2 weather emitters")
eq(Config.Budget.MaxEmitterRate, 60, "60 particles/s")
truthy(Config.Budget.HazardParts >= 3, "a reserve for the hazard model and its ring")

--============================================================ saving and the board [DESIGN §11, §12]
eq(Config.Save.Store, "FindIt_Players_v1", "the profile store")
eq(Config.Board.Store, "FindIt_Solved_v1", "the ordered board store")
truthy(Config.Save.AutosaveSeconds < Config.Save.SessionLockSeconds, "autosave (20 s) inside the lock (45 s)")
eq(Config.Save.MinWriteGap, 6, "writes to one key stay 6 s apart")
eq(Config.World.MaxPlayers, Config.World.Lanes, "one lane per player")
eq(Config.Studio.ShotSeed, nil, "the Studio shot room is OFF in the shipped config")

print(string.format("Config: %d passed, %d failed", passed, failed))
if failed > 0 then error("Config spec failed", 0) end
