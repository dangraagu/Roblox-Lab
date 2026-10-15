-- Economy — prices, capacities, districts, the Orders rule and its safety net, offline earnings, the HUD's ★
-- (bestNext), purchases and refusals. Pure; run: luau tests/Economy.spec.luau
--
-- Expected values are written out from DESIGN.md section 4 (and model.out.txt [M2]), never recomputed with
-- the module's own formulas.

local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end

-- A synthetic layout: 6 districts x 6 lots; odd lots are Homes, even lots Workshops; lot i of district d at
-- x = 10 * i, z = 20 * d (only distances matter to the ★'s tie-break).
local function fakeLayout()
	local lots, byKey = {}, {}
	for d = 1, 6 do
		for i = 1, 6 do
			local l = { key = d .. "_" .. i, d = d, i = i, zone = if i % 2 == 1 then "H" else "W", x = 10 * i, z = 20 * d }
			table.insert(lots, l)
			byKey[l.key] = l
		end
	end
	return { lots = lots, byKey = byKey }
end

--============================================================================ 1. prices, capacities, districts
do
	local caps = { 4, 20, 100, 500, 2500, 12500 }
	local base = { 15, 90, 540, 3240, 19440, 116640 }
	for d = 1, 6 do
		eq(Economy.cap(Config, d), caps[d], "Cap(" .. d .. ")")
		near(Economy.price(Config, d, 1), base[d], 1e-9, "Price(" .. d .. ", 1)")
	end
	near(Economy.price(Config, 1, 10), 223.4, 0.05, "Price(1, 10) = 223.4 [M2]")
	near(Economy.price(Config, 6, 22), 63.66e6, 0.01e6, "Price(6, 22) = 63.66M [M2]")
	near(Economy.price(Config, 2, 2) / Economy.price(Config, 2, 1), 1.35, 1e-12, "each storey costs 1.35 x the one below")
	eq(Economy.price(Config, 1, 23), nil, "no 23rd storey has a price")
	eq(Economy.price(Config, 1, 0), nil, "storey 0 has no price")
	eq(Economy.maxPopulation(Config), 1031184, "the full city holds 1 031 184 [M2]")
	near(Economy.maxPopulation(Config) * Config.Economy.Wage, 257796, 1, "and earns 257.80K credits/s [M2]")
	truthy(Economy.maxPopulation(Config) * 2e9 + 2e9 < 2 ^ 53, "the board's encoding stays exact at the full city")
	-- districts open at 80 / 900 / 6 400 / 35 000 / 185 000
	eq(Economy.districtsOpen(Config, 0), 1, "a new city has the Landing Field only")
	eq(Economy.districtsOpen(Config, 79), 1, "79 citizens: still one district")
	eq(Economy.districtsOpen(Config, 80), 2, "80: Market Row opens")
	eq(Economy.districtsOpen(Config, 899), 2, "899: two")
	eq(Economy.districtsOpen(Config, 900), 3, "900: Sky-Rail Yard")
	eq(Economy.districtsOpen(Config, 6400), 4, "6 400: the Skyport")
	eq(Economy.districtsOpen(Config, 35000), 5, "35 000: Reactor Quarter")
	eq(Economy.districtsOpen(Config, 184999), 5, "184 999: five")
	eq(Economy.districtsOpen(Config, 185000), 6, "185 000: Crown Heights")
	eq(Economy.districtsOpen(Config, 1e9), 6, "and never more than six")
	local nd, at = Economy.nextDistrict(Config, 100)
	eq(nd, 3, "at 100 the next district is the Sky-Rail Yard")
	eq(at, 900, "...at 900")
	eq((Economy.nextDistrict(Config, 185000)), nil, "after Crown Heights there is no next district")
end

--============================================================================ 2. the dead-end rule, from Config
do
	-- the worst end state: all three d6 Homes (or Workshops) one storey short; the dearest storey must cost at
	-- most half the Orders of that city's income (DESIGN 4.3)
	local full = Economy.maxPopulation(Config)
	local worst = full - 3 * Economy.cap(Config, 6)
	local secs = Economy.price(Config, 6, Config.Economy.MaxStoreys) / (Config.Economy.Wage * worst)
	near(secs, 256.3, 0.05, "the dearest storey is 256.3 s of the worst end state's income [M2]")
	truthy(secs <= Config.Economy.OrdersSeconds / 2, "under half the Orders (300 s)")
	-- and the first district stays cheap against the income at its opening (no long save)
	for d = 2, 6 do
		local opensAt = Config.Districts[d].open
		local waitS = Economy.price(Config, d, 1) / (Config.Economy.Wage * opensAt)
		truthy(waitS <= 5, string.format("district %d's first storey is %.1f s of the income at its opening", d, waitS))
	end
end

--============================================================================ 3. population, tallies
local layout = fakeLayout()
do
	local st = Economy.newState(Config, layout, {}, 30)
	eq(st.settlers, 0, "an empty city has no settlers")
	eq(st.jobs, 0, "and no jobs")
	eq(st.pop, 0, "and no citizens")
	eq(st.income, 0, "and no income")
	st = Economy.newState(Config, layout, { ["1_1"] = 3, ["1_2"] = 1, ["2_1"] = 2 }, 0)
	eq(st.settlers, 3 * 4 + 2 * 20, "settlers: Homes x storeys x Cap(d)")
	eq(st.jobs, 4, "jobs: Workshops x storeys x Cap(d)")
	eq(st.pop, 4, "population is the SMALLER of the two")
	near(st.income, 1, 1e-12, "income is 0.25 per citizen per second")
	-- garbage storey values are not trusted (Save.normalise cleans them; the tally ignores anything else)
	st = Economy.newState(Config, layout, { ["1_1"] = 2, ["9_9"] = 5, ["1_2"] = 2 }, 0)
	eq(st.pop, 8, "an unknown lot key is ignored")
end

--============================================================================ 4. earning: Orders, the safety net, offline
do
	-- while the Orders run, the city earns income x seconds
	local c, w, n = Economy.earn(Config, 100, 2, 0, 10, 600, 50)
	near(c, 120, 1e-9, "Orders running: 10 s at 2/s = +20")
	eq(w, 10, "all 10 s worked")
	eq(n, 0, "no safety net needed")
	-- Orders run out mid-window: only the part before ordersUntil pays (credits are above the cheapest storey)
	c, w, n = Economy.earn(Config, 100, 2, 595, 605, 600, 50)
	near(c, 110, 1e-9, "Orders end at 600: 5 of 10 s pay")
	eq(n, 0, "credits >= the cheapest storey: the safety net stays off")
	-- the safety net: after the Orders, the city works while no storey is affordable, until one is
	c, w, n = Economy.earn(Config, 10, 2, 600, 700, 600, 50)
	near(c, 50, 1e-9, "after the Orders the net pays exactly up to the cheapest storey (50)")
	near(n, 20, 1e-9, "for 20 s")
	c = Economy.earn(Config, 60, 2, 600, 700, 600, 50)
	near(c, 60, 1e-9, "a player who can afford a storey earns nothing after the Orders")
	c = Economy.earn(Config, 10, 2, 600, 700, 600, nil)
	near(c, 10, 1e-9, "a complete city (no storey left) gets no safety net")
	c = Economy.earn(Config, 10, 0, 0, 100, 600, 50)
	near(c, 10, 1e-9, "no citizens, no income")
	c = Economy.earn(Config, 10, 2, 100, 50, 600, 50)
	near(c, 10, 1e-9, "a negative clock difference counts as 0")
	-- offline: the same rule from savedAt to now
	local prof = { credits = 100, savedAt = 1000, ordersUntil = 1300 }
	local got, info = Economy.offline(Config, prof, 2, 1000 + 3600, 500)
	near(got, 100 + 2 * 300, 1e-9, "offline: the workers finish their Orders (300 s), then stop")
	near(info.worked, 300, 1e-9, "300 s worked")
	got = Economy.offline(Config, { credits = 10, savedAt = 1000, ordersUntil = 1000 }, 2, 1000 + 3600, 50)
	near(got, 50, 1e-9, "offline with Orders already out and nothing affordable: the net reaches the cheapest storey")
	got = Economy.offline(Config, prof, 2, 900, 500)
	near(got, 100, 1e-9, "offline with the clock going backwards: nothing")
	got = Economy.offline(Config, { credits = 100, savedAt = 0 / 0, ordersUntil = 1300 }, 2, 5000, 500)
	near(got, 100, 1e-9, "offline with a corrupt savedAt: nothing")
end

--============================================================================ 5. the ★: bestNext (DESIGN 4.5)
do
	-- a new city: both sides tie (0 = 0), every d1 lot scores the same (30 s), the nearest one wins
	local st = Economy.newState(Config, layout, {}, 30)
	local pick = Economy.bestNext(Config, st, 30, 20)
	truthy(pick ~= nil, "a new city has a ★")
	eq(pick and pick.key, "1_3", "the ★ is the nearest district-1 lot (x = 30)")
	near(pick and pick.score or -1, 30, 1e-9, "scored 0 s wait + 2 x 15 / (0.25 x 4) = 30 s payback")
	eq(pick and pick.storey, 1, "its first storey")
	-- after a Home: the city is short of jobs, so the ★ moves to a Workshop
	st = Economy.newState(Config, layout, { ["1_1"] = 1 }, 15)
	pick = Economy.bestNext(Config, st, 10, 20)
	eq(pick and pick.zone, "W", "settlers 4, jobs 0: the ★ is on a Workshop")
	eq(pick and pick.key, "1_2", "the nearest Workshop")
	-- after a Workshop: short of settlers
	st = Economy.newState(Config, layout, { ["1_2"] = 1 }, 15)
	pick = Economy.bestNext(Config, st, 10, 20)
	eq(pick and pick.zone, "H", "jobs 4, settlers 0: the ★ is on a Home")
	-- the short side wins even when a lot of the other side is nearer and just as cheap (the sweep's M22 survived
	-- the two cases above: there the nearest affordable lot happened to be on the short side anyway)
	st = Economy.newState(Config, layout, { ["1_1"] = 1 }, 15)
	pick = Economy.bestNext(Config, st, 30, 20) -- standing at the empty Home 1_3
	eq(pick and pick.zone, "W", "short of jobs, standing next to an empty Home: the ★ is still a Workshop")
	st = Economy.newState(Config, layout, { ["1_2"] = 1 }, 15)
	pick = Economy.bestNext(Config, st, 40, 20) -- standing at the empty Workshop 1_4
	eq(pick and pick.zone, "H", "short of settlers, standing next to an empty Workshop: the ★ is still a Home")
	st = Economy.newState(Config, layout, { ["1_1"] = 5, ["1_2"] = 3, ["1_4"] = 1 }, 1e6)
	-- settlers 20, jobs 16: the cheapest storey anywhere is a fresh Home (15); the ★ must be a Workshop
	pick = Economy.bestNext(Config, st, 30, 20)
	eq(pick and pick.zone, "W", "short of jobs with money to spare: the ★ never builds more Homes")
	-- payback beats the cheaper-looking new district: storey 2 of a d1 lot vs a fresh d2 lot when d2 is open
	st = Economy.newState(Config, layout, { ["1_1"] = 10, ["1_3"] = 10, ["1_5"] = 1, ["1_2"] = 10, ["1_4"] = 10, ["1_6"] = 1 }, 0)
	-- settlers = jobs = 84 (2 x 10 x 4 + 4), population 84: Market Row (80) is open
	eq(st.pop, 84, "a balanced city of 84")
	pick = Economy.bestNext(Config, st, 0, 0)
	truthy(pick ~= nil, "it has a ★")
	if pick then
		local p = pick.price
		local cap = Economy.cap(Config, pick.d)
		local wantScore = math.max(0, p - st.credits) / st.income + 2 * p / (Config.Economy.Wage * cap)
		near(pick.score, wantScore, 1e-9, "score = wait + payback")
		-- no other candidate in budget scores lower
		local best = math.huge
		for _, l in layout.lots do
			local s = st.lots[l.key] or 0
			if l.d <= 2 and s < 22 then
				local pr = Economy.price(Config, l.d, s + 1)
				if pr <= st.credits + st.income * 600 then
					local sc = math.max(0, pr - st.credits) / st.income + 2 * pr / (0.25 * Economy.cap(Config, l.d))
					best = math.min(best, sc)
				end
			end
		end
		near(pick.score, best, 1e-9, "the ★ is the lowest score of every candidate in budget")
		near(pick.wait, math.max(0, p - st.credits) / st.income, 1e-9, "and says how long until it is affordable")
	end
	-- out of budget: nothing affordable before the Orders run out -> the cheapest storey on the short side
	st = Economy.newState(Config, layout, { ["1_1"] = 1 }, 0)
	st.income = 0.0001 -- (a contrived trickle so nothing fits in 600 s)
	pick = Economy.bestNext(Config, st, 0, 0)
	eq(pick and pick.zone, "W", "with nothing in budget the ★ falls back to the short side's cheapest storey")
	eq(pick and pick.storey, 1, "a fresh Workshop (15 credits)")
	-- a locked district is never starred
	st = Economy.newState(Config, layout, {}, 1e9)
	pick = Economy.bestNext(Config, st, 0, 0)
	eq(pick and pick.d, 1, "the ★ never points into a locked district")
	-- topped lots are never starred
	local lots = {}
	for i = 1, 6 do lots["1_" .. i] = 22 end
	lots["1_1"] = 21
	st = Economy.newState(Config, layout, lots, 1e9)
	-- settlers 2*22*4 + 21*4 = 260, jobs 264: short of settlers; only 1_1 (21) and d2 Homes remain
	pick = Economy.bestNext(Config, st, 0, 0)
	truthy(pick ~= nil and pick.key ~= "1_3" and pick.key ~= "1_5", "a topped-out Home is never starred")
	-- a complete city has no ★
	lots = {}
	for d = 1, 6 do for i = 1, 6 do lots[d .. "_" .. i] = 22 end end
	st = Economy.newState(Config, layout, lots, 0)
	eq(Economy.bestNext(Config, st, 0, 0), nil, "a complete city has no ★")
	eq(Economy.cheapest(Config, st), nil, "and no cheapest storey")
end

--============================================================================ 6. buying and refusing
do
	local st = Economy.newState(Config, layout, {}, 30)
	local ok, why, price = Economy.canBuy(Config, st, "1_1")
	eq(ok, true, "30 credits buy the first Home")
	near(price, 15, 1e-9, "for 15")
	local paid = Economy.apply(Config, st, "1_1")
	near(paid, 15, 1e-9, "apply returns the price paid")
	near(st.credits, 15, 1e-9, "credits fall by the price")
	eq(st.lots["1_1"], 1, "the lot has one storey")
	eq(st.settlers, 4, "4 settlers")
	eq(st.pop, 0, "no jobs yet: population 0")
	Economy.apply(Config, st, "1_2")
	eq(st.pop, 4, "the Workshop makes 4 citizens")
	near(st.income, 1, 1e-12, "earning 1 credit a second (+60/min)")
	ok, why, price = Economy.canBuy(Config, st, "1_3")
	eq(ok, false, "0 credits cannot buy a 15-credit Home")
	eq(why, "credits", "...because of credits")
	ok, why = Economy.canBuy(Config, st, "2_1")
	eq(why, "locked", "a Market Row lot cannot be bought at population 4")
	ok, why = Economy.canBuy(Config, st, "nope")
	eq(why, "unknown", "an unknown lot is refused")
	st = Economy.newState(Config, layout, { ["1_1"] = 22 }, 1e12)
	ok, why = Economy.canBuy(Config, st, "1_1")
	eq(why, "topped", "a 22-storey building is topped out")
	-- the refusal speaks
	local text = Economy.refusalText(Config, "credits", 1200, 900, 15)
	eq(text, "Need 1.2K credits, you have 900 (ready in 0:20)", "the credits refusal names price, balance and the wait")
	eq(Economy.refusalText(Config, "credits", 1200, 900, 0), "Need 1.2K credits, you have 900", "with no income there is no wait to promise")
	truthy(#Economy.refusalText(Config, "locked", 0, 0, 0) > 0, "a locked refusal says something")
	truthy(#Economy.refusalText(Config, "topped", 0, 0, 0) > 0, "a topped refusal says something")
end

--============================================================================ 6b. a city with nobody in it can always get its first citizens
-- REVIEW-1 F5: a new player who pressed two Homes (or two Workshops) first had spent the 30 starting credits on one
-- side. With no citizens there is no income, the safety net needs income, and the city was dead for good (the save
-- kept it that way). canBuy now refuses the purchase that would strand the city, and startNeed is what a city with
-- nobody in it needs to get its first citizens.
do
	local st = Economy.newState(Config, layout, {}, 30)
	near(Economy.startNeed(Config, st), 30, 1e-9, "a new city needs 30: its first Home (15) and its first Workshop (15)")
	Economy.apply(Config, st, "1_1") -- a Home: 15 left
	near(Economy.startNeed(Config, st), 15, 1e-9, "with a Home and no Workshop, it needs the Workshop's 15")
	local ok, why, price = Economy.canBuy(Config, st, "1_3") -- a second Home
	eq(ok, false, "a second Home before any Workshop is refused: it would leave 0 for the Workshop")
	eq(why, "needjobs", "...because the settlers need jobs first")
	near(price or -1, 15, 1e-9, "...and it names the Workshop's price")
	eq((Economy.canBuy(Config, st, "1_1")), false, "a storey on that Home is refused too")
	eq((Economy.canBuy(Config, st, "1_2")), true, "the Workshop is allowed")
	eq(Economy.refusalText(Config, "needjobs", 15, 15, 0), Config.Tutorial.NeedJobs, "the refusal says: build the Workshop")
	eq(Economy.refusalText(Config, "needhomes", 15, 15, 0), Config.Tutorial.NeedHomes, "and on the other side: build the Home")
	-- Workshops first: the mirror
	st = Economy.newState(Config, layout, {}, 30)
	Economy.apply(Config, st, "1_2")
	ok, why = Economy.canBuy(Config, st, "1_4")
	eq(ok, false, "a second Workshop before any Home is refused")
	eq(why, "needhomes", "...because the jobs need settlers first")
	-- money to spare: a second Home that still leaves the Workshop's price is fine
	st = Economy.newState(Config, layout, { ["1_1"] = 1 }, 30)
	eq((Economy.canBuy(Config, st, "1_3")), true, "with 30 credits and one Home, a second Home (15) still leaves the Workshop's 15")
	-- once anyone lives here the rule is gone: population never falls, and the Orders and the net carry the city
	st = Economy.newState(Config, layout, { ["1_1"] = 1, ["1_2"] = 1 }, 15)
	eq(Economy.startNeed(Config, st), 0, "a city with citizens needs nothing to start")
	eq((Economy.canBuy(Config, st, "1_3")), true, "population 4: a third Home may take the last 15 credits")
	-- property: from a new city, ANY order of presses on any layout never reaches a dead city (no income, and no lot
	-- canBuy accepts). Real layouts, so the zones are wherever the seed put them.
	local City = require("../src/shared/City")
	local Rng = require("../src/shared/Rng")
	local dead, accepted, refusedStrand, worst = 0, 0, 0, ""
	for seed = 1, 300 do
		local L = City.layout(Config, seed, Rng)
		local s = Economy.newState(Config, L, {}, Config.Economy.StartCredits)
		local r = Rng.new(seed * 7919 + 1)
		for _ = 1, 40 do
			local l = L.lots[Rng.below(r, #L.lots)]
			local okB, whyB = Economy.canBuy(Config, s, l.key)
			if okB then
				Economy.apply(Config, s, l.key)
				accepted += 1
			elseif whyB == "needjobs" or whyB == "needhomes" then
				refusedStrand += 1
			end
			if s.income <= 0 then
				local any = false
				for _, l2 in L.lots do
					if (Economy.canBuy(Config, s, l2.key)) then any = true break end
				end
				if not any then
					dead += 1
					worst = string.format("seed %d: settlers %d jobs %d credits %.2f", seed, s.settlers, s.jobs, s.credits)
				end
			end
		end
	end
	print(string.format("  random presses on 300 layouts: %d bought, %d refused as stranding, %d dead states", accepted, refusedStrand, dead))
	eq(dead, 0, "no order of presses leaves a city with no income and nothing it may buy (" .. worst .. ")")
	truthy(refusedStrand > 0, "set-up: the random presses did try to strand a city")
end

--============================================================================ 7. texts
do
	eq(Economy.short(0), "0", "short 0")
	eq(Economy.short(900), "900", "short 900")
	eq(Economy.short(12.75), "12", "short floors a fraction under 1000")
	eq(Economy.short(1200), "1.2K", "short 1.2K")
	eq(Economy.short(3.4e6), "3.4M", "short 3.4M")
	eq(Economy.short(63.66e6), "63.7M", "short 63.7M")
	eq(Economy.short(2.5e9), "2.5B", "short 2.5B")
	eq(Economy.group(6400), "6 400", "group 6 400")
	eq(Economy.group(1031184), "1 031 184", "group 1 031 184")
	eq(Economy.group(80), "80", "group 80")
	eq(Economy.clock(492), "8:12", "clock 8:12")
	eq(Economy.clock(600), "10:00", "clock 10:00")
	eq(Economy.clock(0), "0:00", "clock 0:00")
	eq(Economy.clock(19.2), "0:20", "clock rounds a part second up (never promises too early)")
	local layout2 = fakeLayout()
	local st = Economy.newState(Config, layout2, { ["1_1"] = 6 }, 0)
	eq(Economy.actionText(Config, st, "1_1"), "Add storey", "a built lot's prompt adds a storey")
	eq(Economy.actionText(Config, st, "1_2"), "Build Workshop", "an empty Workshop lot builds one")
	eq(Economy.actionText(Config, st, "1_3"), "Build Home", "an empty Home lot builds one")
	-- round 2, B3: the prompt also says how many people the storey brings, so a player who compares prompts instead
	-- of following the ★ can see that a dearer storey in a newer district is the better buy (Pacing.spec [M12])
	eq(Economy.objectText(Config, st, "1_1"), "Home 6/22 · " .. Economy.short(Economy.price(Config, 1, 7)) .. " · +4 settlers",
		"the prompt names the lot, its storeys, the price and the settlers the storey brings")
	eq(Economy.objectText(Config, st, "2_2"), "Workshop 0/22 · 90 · +20 jobs", "a Market Row Workshop brings 20 jobs")
	eq(Economy.objectText(Config, st, "6_1"), "Home 0/22 · 116K · +12.5K settlers", "a Crown Heights Home brings 12.5K settlers")
	st = Economy.newState(Config, layout2, { ["1_1"] = 22 }, 0)
	eq(Economy.objectText(Config, st, "1_1"), "Home 22/22 · Topped out", "a topped lot says so (and brings nobody more)")
	eq(Economy.side(Economy.newState(Config, layout2, { ["1_1"] = 1 }, 0)), "W", "short of jobs -> W")
	eq(Economy.side(Economy.newState(Config, layout2, {}, 0)), nil, "balanced -> both")
	eq(Economy.balanceText(Economy.newState(Config, layout2, { ["1_1"] = 30 // 4 }, 0)), "Settlers 28 · Jobs 0: build a Workshop ★", "the balance line")
end

print(string.format("Economy: %d passed, %d failed", passed, failed))
if failed > 0 then error("Economy spec failed", 0) end
