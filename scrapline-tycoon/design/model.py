#!/usr/bin/env python3
# Scrapline Tycoon -- DESIGN-TIME MEASUREMENT MODEL. Not game code; nothing here ships.
#
# Every pacing, economy and anti-farm number DESIGN.md tags [M n] is printed by Part n of this
# file. Re-run it after changing any constant below and re-read the numbers before touching the
# spec:
#
#   py -3 design/model.py > design/model.out.txt
#
# Written in Python because the luau CLI was not on the machine when the spec was written
# (2026-10-07; the scratchpad's luau directory was empty). The build ports `flow`, `star`,
# `simulate` and the constants to tests/LineModel.luau, reading Config, and tests/Pacing.spec.luau
# asserts the same targets. If the two ever disagree, Pacing.spec (which reads Config) is the
# authority and this file is stale. ASCII only: a Windows code page cannot corrupt it.
#
# What this is NOT: a physics model. The line is the steady-state flow of DESIGN.md section 4 (a
# new machine produces at once; items in transit are ignored, which is at most one belt transit
# late); walking to a jammed machine is a straight line at WalkSpeed x the profile's efficiency
# from the middle of the U; a hazard is counted, not walked. The player profiles are
# ASSUMPTIONS. The first real play session replaces them.

import math
import random
import statistics
import sys

# ============================================================================ constants
C = {
    "WalkSpeed": 16,
    "TrustedSpeedFactor": 1.35,  # vault-runners' Trace cap, as meteor-drop-tycoon uses it
    # products: state 0..6
    "Names": ["Junk", "Scrap", "Ingot", "Plate", "Gear", "Robot", "Rocket"],
    "Values": [1, 2, 5, 12, 30, 75, 200],
    # stations 1..6: station t turns state t-1 into state t
    "Stations": ["Shredder", "Furnace", "Press", "Cutter", "Assembler", "Rocket Bay"],
    "BuildPrice": [0, 650, 13000, 130000, 1100000, 9500000],  # station 1 is free (one tap)
    "BaseSpeed": [1.0, 1.6, 2.6, 4.1, 6.6, 10.5],  # items/s per machine at level 1 (x1.6 per station)
    "SpeedGrowth": 1.25,  # x per station level
    # level 1 -> 2 costs UpgradeBase = 8 x BaseSpeed x (value the station adds per item), rounded:
    # every station's first upgrade pays for itself in the same 8 / (1.25 - 1) = 32 s
    "UpgradeBase": [8, 38, 146, 590, 2380, 10500],
    "UpgradeGrowth": 1.5,  # x per level
    "TwinPrice": 30,  # the twin costs TwinPrice x the station's first upgrade
    "MaxLevel": 100,
    "SaveWindow": 60,  # the star saves for the next station once it is this many seconds of income away
    # the chute: before the first Shredder exists it trickles ChuteTrickle junk/s onto the belt; after,
    # it feeds the Shredder exactly as fast as the Shredder can take it (junk never runs out)
    "ChuteTrickle": 0.5,
    # prestige ("Recycle"): recycle number k (k = bolts + 1) unlocks once the line ships rockets at
    # RecycleRate0 x RecycleRateGrowth^(k-1) per second; it pays exactly one Gold Bolt
    "BoltValue": 0.5,  # value multiplier = 1 + BoltValue x bolts
    "RecycleRate0": 1500,
    "RecycleRateGrowth": 1.35,
    # jams
    "FirstJamIn": 240,  # seconds of line time before a brand-new profile's first sputter
    "JamMin": 150,
    "JamMax": 210,
    "SputterSeconds": 15,
    "FixHold": 0.5,
    # client hazards: one per 120-180 s of non-rest time on your own plot, none in band 1
    "HazardMin": 120,
    "HazardMax": 180,
    "Dt": 0.5,
}

BANDS = ["junkyard", "foundry", "pressworks", "machineshop", "robotworks", "launchsite"]

# Station centres (plot-local studs, DESIGN.md section 3): a machine and its twin sit on the belt,
# 3.5 studs either side of the centre.
STATION_POS = [(-14, -16), (-14, -2), (-14, 12), (14, 12), (14, -2), (14, -16)]
WORK_SPOT = (0, -2)  # where an active player stands between jobs: the middle of the U

PROFILES = {
    # shop: opens the panel every N s. buy: s per purchase. notice: s to notice a sputter.
    # eff: walk efficiency. policy: "star" follows the star; "cheapest" buys the cheapest purchase that
    # adds income; "random" buys a random affordable purchase that adds income; "saver" follows the
    # star without its rule 0 (it does not build or save for the next station first).
    "fast": dict(shop=10, buy=0.8, notice=2, eff=0.95, policy="star", fixes=True, speed=None),
    "normal": dict(shop=20, buy=1.2, notice=4, eff=0.85, policy="star", fixes=True, speed=None),
    "slow": dict(shop=45, buy=2.0, notice=10, eff=0.70, policy="star", fixes=True, speed=None),
    "cheapest": dict(shop=20, buy=1.2, notice=4, eff=0.85, policy="cheapest", fixes=True, speed=None),
    "random": dict(shop=20, buy=1.2, notice=4, eff=0.85, policy="random", fixes=True, speed=None),
    "saver": dict(shop=20, buy=1.2, notice=4, eff=0.85, policy="saver", fixes=True, speed=None),
    # follows the star 3 times in 4, otherwise buys a random affordable purchase that adds income
    "mixed": dict(shop=20, buy=1.2, notice=4, eff=0.85, policy="mixed", fixes=True, speed=None),
    "bot": dict(shop=0.5, buy=0.0, notice=0.0, eff=1.0, policy="star", fixes=True, speed=16 * 1.35),
    "afkmacro": dict(shop=0.5, buy=0.0, notice=0.0, eff=1.0, policy="star", fixes=False, speed=None),
    # an anti-AFK jiggle and nothing else: never buys, never fixes
    "jiggle": dict(shop=10 ** 9, buy=0.0, notice=0.0, eff=1.0, policy="star", fixes=False, speed=None),
}


# ============================================================================ economy (pure)
def speed(t, L):
    return C["BaseSpeed"][t - 1] * C["SpeedGrowth"] ** (L - 1)


def build_price(t):
    return C["BuildPrice"][t - 1]


def twin_price(t):
    return round(C["TwinPrice"] * C["UpgradeBase"][t - 1])


def up_price(t, L):
    return round(C["UpgradeBase"][t - 1] * C["UpgradeGrowth"] ** (L - 1))


def mult(bolts):
    return 1 + C["BoltValue"] * bolts


def recycle_rate(bolts):
    """Rockets per second the line must ship to unlock the next recycle."""
    return C["RecycleRate0"] * C["RecycleRateGrowth"] ** bolts


def new_station():
    # n: machines built (0, 1, 2); jam: per machine 0 ok / 1 sputtering / 2 jammed
    return dict(n=0, L=1, jam=[0, 0])


def capacity(st_t, t, ignore_jams=False):
    working = sum(1 for i in range(st_t["n"]) if ignore_jams or st_t["jam"][i] != 2)
    return working * speed(t, st_t["L"])


def intake(stations, ignore_jams=False):
    """Junk per second the chute puts on the belt: the Shredder station's capacity (its jammed
    machines excluded, unless ignore_jams), never below the trickle."""
    s = stations[0]
    if s["n"] == 0:
        return C["ChuteTrickle"]
    return max(C["ChuteTrickle"], capacity(s, 1, ignore_jams))


def flow(stations, ignore_jams=False):
    """Steady state: items/s leaving the dock in each state."""
    r = [0.0] * 7
    r[0] = intake(stations, ignore_jams)
    for t in range(1, 7):
        cap = capacity(stations[t - 1], t, ignore_jams)
        moved = min(r[t - 1], cap)
        r[t - 1] -= moved
        r[t] += moved
    return r


def income(stations, M, ignore_jams=False):
    r = flow(stations, ignore_jams)
    return sum(r[s] * C["Values"][s] for s in range(7)) * M, r


def bottleneck(stations):
    """The built station whose capacity is lowest against what reaches it (ties: the earliest)."""
    r = intake(stations, True)
    worst, worst_ratio = None, math.inf
    for t in range(1, 7):
        s = stations[t - 1]
        if s["n"] == 0:
            break
        cap = capacity(s, t, True)
        ratio = cap / max(r, 1e-9)
        if ratio < worst_ratio - 1e-12:
            worst, worst_ratio = t, ratio
        r = min(r, cap)
    return worst, worst_ratio


# ---------------------------------------------------------------------------- actions
def candidates(st):
    """Every purchase the HUD lists (affordable or not). Each: dict(kind, t, price)."""
    out = []
    S = st["stations"]
    for t in range(1, 7):
        s = S[t - 1]
        if s["n"] == 0:
            if t == 1 or S[t - 2]["n"] > 0:
                out.append(dict(kind="build", t=t, price=build_price(t)))
            continue
        if s["n"] == 1:
            out.append(dict(kind="twin", t=t, price=twin_price(t)))
        if s["L"] < C["MaxLevel"]:
            out.append(dict(kind="up", t=t, price=up_price(t, s["L"])))
    return out


def clone(stations):
    return [dict(n=s["n"], L=s["L"], jam=[0, 0]) for s in stations]


def preview(st, a):
    """Income after action a, jams ignored (the star plans for a working line)."""
    S = clone(st["stations"])
    if a["kind"] in ("build", "twin"):
        S[a["t"] - 1]["n"] += 1
    elif a["kind"] == "up":
        S[a["t"] - 1]["L"] += 1
    return income(S, st["M"], True)[0]


def star(st):
    """The HUD's star, three rules:
    0. the next station: the moment it is affordable, and from SaveWindow seconds of income
       before that (save for it: a new station opens a fresh set of 32-second upgrades; M2's
       "saver" profile and M8's SaveWindow rows measure this rule against the alternatives);
    1. otherwise the TARGET is the purchase that has paid for itself soonest, counting the wait
       to afford it: score = max(0, price - cash) / income + price / gain (ties: the cheaper);
    2. while the target is unaffordable, the star goes to the affordable purchase with the shortest
       payback, if that payback is shorter than the wait for the target (buying it brings the
       target closer, never further). Otherwise the star stays on the target: save up."""
    now = income(st["stations"], st["M"], True)[0]
    for a in candidates(st):
        if a["kind"] == "build":
            if a["price"] <= st["cash"]:
                return a
            if (a["price"] - st["cash"]) / max(now, 1e-9) <= C["SaveWindow"]:
                return a  # within SaveWindow seconds of income: save for it, buy nothing else
    return star_payback(st)


def star_payback(st):
    now = income(st["stations"], st["M"], True)[0]
    best, best_score, scored = None, math.inf, []
    for a in candidates(st):
        d = preview(st, a) - now
        if d <= 1e-12:
            continue
        payback = a["price"] / d
        wait = max(0.0, a["price"] - st["cash"]) / max(now, 1e-9)
        scored.append((a, payback))
        score = wait + payback
        if score < best_score - 1e-9 or (abs(score - best_score) <= 1e-9 and a["price"] < best["price"]):
            best, best_score = a, score
    if best is None:
        return min(candidates(st), key=lambda a: a["price"])
    if best["price"] > st["cash"]:
        wait = (best["price"] - st["cash"]) / max(now, 1e-9)
        filler = [(a, pb) for a, pb in scored if a["price"] <= st["cash"] and pb < wait]
        if filler:
            return min(filler, key=lambda x: (x[1], x[0]["price"]))[0]
    return best


def cheapest(st):
    now = income(st["stations"], st["M"], True)[0]
    cs = [a for a in candidates(st) if preview(st, a) > now + 1e-9 or a["kind"] == "build"]
    return min(cs, key=lambda a: a["price"]) if cs else None


def random_useful(st, rng):
    now = income(st["stations"], st["M"], True)[0]
    cs = [a for a in candidates(st) if a["price"] <= st["cash"] and (a["kind"] == "build" or preview(st, a) > now + 1e-9)]
    if not cs:
        return cheapest(st)
    return cs[min(len(cs) - 1, int(rng.random() * len(cs)))]


def apply(st, a):
    st["cash"] -= a["price"]
    if a["kind"] in ("build", "twin"):
        st["stations"][a["t"] - 1]["n"] += 1
    elif a["kind"] == "up":
        st["stations"][a["t"] - 1]["L"] += 1
    st["purchases"] += 1


def new_run(st):
    st["cash"] = 0.0
    st["runEarned"] = 0.0
    st["stations"] = [new_station() for _ in range(6)]
    st["shipped"] = [0.0] * 7
    st["tier"] = 0
    st["rocketsRun"] = 0.0
    st["M"] = mult(st["bolts"])


def recycle_ready(st):
    """The line ships rockets (jams counted) at least as fast as the next recycle asks."""
    return flow(st["stations"])[6] >= recycle_rate(st["bolts"]) - 1e-9


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


# ============================================================================ simulation
SNAPS = (30, 60, 120, 300, 600, 1200, 1800, 2100, 2400, 3600, 5400, 7200, 10800, 14400, 21600, 28800)


def simulate(pname, seed, seconds, recycle=True, first_place_at=3.0, log_purchases=False, until_rocket=False,
             switch_at=None):
    """switch_at = (seconds, profile): from then on the player behaves as that profile."""
    p = PROFILES[pname]
    rng = random.Random(seed)
    st = dict(bolts=0, recycles=0, purchases=0)
    new_run(st)
    out = dict(tierAt={}, runs=[], firstRocket=None, jams=0, jamDown=0.0, saved=0, hazards=0,
               hazardsToRocket=None, lostIncome=0.0, idealIncome=0.0, earned=0.0, incAt={}, buildAt={},
               boltsAt={}, cashAt={}, purchases=[], firstBuyAt=None, firstBuy=None)
    placed = False
    jam_in = C["FirstJamIn"]
    sputter = None  # dict(t=station, i=machine index, left=, fixAt=, start=)
    haz_clock, haz_next = 0.0, rng.uniform(C["HazardMin"], C["HazardMax"])
    shop_next = rng.uniform(0, p["shop"])
    buy_busy = 0.0
    run_start = 0.0
    walk_speed = p["speed"] or C["WalkSpeed"] * p["eff"]
    dt = C["Dt"]
    t = 0.0
    while t < seconds:
        if switch_at is not None and t >= switch_at[0] and "boltsAtSwitch" not in out:
            p = PROFILES[switch_at[1]]
            walk_speed = p["speed"] or C["WalkSpeed"] * p["eff"]
            if sputter is not None and not p["fixes"]:
                sputter["fixAt"] = None
            out["boltsAtSwitch"] = st["bolts"]
        S = st["stations"]
        # first placement: the free Shredder, one tap
        if not placed and t >= first_place_at:
            S[0]["n"] = 1
            placed = True
        # ---- jams (server): one sputter at a time; the clock runs only while none is live
        if placed:
            if sputter is None:
                jam_in -= dt
                if jam_in <= 0:
                    ok = [(ti, i) for ti in range(1, 7) for i in range(S[ti - 1]["n"]) if S[ti - 1]["jam"][i] == 0]
                    if ok:
                        ti, i = ok[min(len(ok) - 1, int(rng.random() * len(ok)))]
                        S[ti - 1]["jam"][i] = 1
                        fix_at = None
                        if p["fixes"]:
                            fix_at = t + p["notice"] + dist(WORK_SPOT, STATION_POS[ti - 1]) / walk_speed + C["FixHold"]
                        sputter = dict(t=ti, i=i, left=C["SputterSeconds"], fixAt=fix_at, start=t)
                        out["jams"] += 1
                    jam_in = rng.uniform(C["JamMin"], C["JamMax"])
            else:
                s = S[sputter["t"] - 1]
                state = s["jam"][sputter["i"]] if sputter["i"] < s["n"] else 0
                if state == 0:
                    sputter = None  # recycled away
                elif sputter["fixAt"] is not None and t >= sputter["fixAt"]:
                    if state == 1:
                        out["saved"] += 1
                    else:
                        out["jamDown"] += t - (sputter["start"] + C["SputterSeconds"])
                    s["jam"][sputter["i"]] = 0
                    sputter = None
                else:
                    if state == 1:
                        sputter["left"] -= dt
                        if sputter["left"] <= 0:
                            s["jam"][sputter["i"]] = 2
                            state = 2
                    if state == 2 and sputter["fixAt"] is None:
                        sputter = None  # nobody is coming: the next sputter's clock starts
        # ---- hazards (client): quiet in band 1; a due hazard is held while the line has a live
        #      sputter or a jam (one thing at a time)
        trouble = sputter is not None or any(x == 2 for s in S for x in s["jam"])
        if p["fixes"]:
            haz_clock += dt
            if haz_clock >= haz_next:
                if st["tier"] <= 1:
                    haz_next = haz_clock + rng.uniform(C["HazardMin"], C["HazardMax"])
                elif not trouble:
                    out["hazards"] += 1
                    haz_next = haz_clock + rng.uniform(C["HazardMin"], C["HazardMax"])
        # ---- production
        inc, r = income(S, st["M"])
        ideal = income(S, st["M"], True)[0]
        out["lostIncome"] += (ideal - inc) * dt
        out["idealIncome"] += ideal * dt
        st["cash"] += inc * dt
        st["runEarned"] += inc * dt
        out["earned"] += inc * dt
        for s_ in range(7):
            st["shipped"][s_] += r[s_] * dt
            if st["shipped"][s_] >= 1 and s_ > st["tier"]:
                st["tier"] = s_
                out["tierAt"][(st["recycles"], s_)] = t
        st["rocketsRun"] = st["shipped"][6]
        if st["rocketsRun"] >= 1 and out["firstRocket"] is None:
            out["firstRocket"] = t
            out["hazardsToRocket"] = out["hazards"]
            out["buildAtRocket"] = summary(st)
            if until_rocket:
                break
        # ---- shopping
        if buy_busy > 0:
            buy_busy -= dt
        elif placed and t >= shop_next:
            shop_next = t + p["shop"]
            if recycle and recycle_ready(st):
                gain = 1
                out["runs"].append(dict(start=run_start, end=t, bolts=gain, rockets=st["rocketsRun"], M=st["M"]))
                st["bolts"] += gain
                st["recycles"] += 1
                new_run(st)
                st["stations"][0]["n"] = 1
                sputter = None
                run_start = t
                buy_busy = 3.0  # the recycle animation
            else:
                n = 0
                while n < 60:
                    if p["policy"] == "star":
                        a = star(st)
                    elif p["policy"] == "random":
                        a = random_useful(st, rng)
                    elif p["policy"] == "saver":
                        a = star_payback(st)
                    elif p["policy"] == "mixed":
                        a = star(st) if rng.random() < 0.75 else random_useful(st, rng)
                    else:
                        a = cheapest(st)
                    if a is None or a["price"] > st["cash"]:
                        break
                    if out["firstBuyAt"] is None:
                        out["firstBuyAt"], out["firstBuy"] = t, (a["kind"], a.get("t"))
                    if log_purchases:
                        out["purchases"].append((round(t, 1), a["kind"], a.get("t"), a["price"]))
                    apply(st, a)
                    n += 1
                buy_busy = n * p["buy"]
        # ---- snapshots
        for mark in SNAPS:
            if t < mark <= t + dt:
                out["incAt"][mark] = inc
                out["cashAt"][mark] = st["cash"]
                out["buildAt"][mark] = summary(st)
                out["boltsAt"][mark] = st["bolts"]
        t += dt
    out["final"] = st
    return out


def summary(st):
    S = st["stations"]
    return dict(stations=["%s L%d%s" % (C["Stations"][t][:4], S[t]["L"], "x2" if S[t]["n"] == 2 else "") for t in range(6) if S[t]["n"] > 0],
                tier=st["tier"], bolts=st["bolts"], recycles=st["recycles"])


# ============================================================================ helpers
def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def fmt_min(s):
    return "never" if s is None or s == math.inf else "%.1f" % (s / 60)


SEEDS = list(range(1, 21))


def part(n, title):
    print()
    print("== M%d %s ==" % (n, title))


def run_profile(pname, seconds, recycle, seeds=SEEDS, **kw):
    return [simulate(pname, sd, seconds, recycle=recycle, **kw) for sd in seeds]


def gaps_of(o):
    times = [0.0] + [x[0] for x in o["purchases"]]
    return [b - a for a, b in zip(times, times[1:])]


# ============================================================================ parts
def m1_tables():
    part(1, "economy tables")
    for t in range(1, 7):
        dv = C["Values"][t] - C["Values"][t - 1]
        print("%-10s %-5s(%3d) -> %-6s(%3d)  build %8d  twin %7d  speed L1 %5.1f/s  first upgrade %6d pays back in %.0f s  upgrade 10->11 %10d  20->21 %13d  30->31 %15d" % (
            C["Stations"][t - 1], C["Names"][t - 1], C["Values"][t - 1], C["Names"][t], C["Values"][t],
            build_price(t), twin_price(t), speed(t, 1), up_price(t, 1),
            up_price(t, 1) / (speed(t, 1) * (C["SpeedGrowth"] - 1) * dv),
            up_price(t, 10), up_price(t, 20), up_price(t, 30)))
    print("payback of an upgrade at level L, relative to level 1: x(%.2f / %.2f)^(L-1) = x%.3f per level" % (
        C["UpgradeGrowth"], C["SpeedGrowth"], C["UpgradeGrowth"] / C["SpeedGrowth"]))
    print("a twin doubles a station; that equals log(2)/log(%.2f) = %.2f levels of upgrades" % (
        C["SpeedGrowth"], math.log(2) / math.log(C["SpeedGrowth"])))


def m2_pacing():
    part(2, "first-run pacing (20 seeds, to the first Rocket, no recycle)")
    for pname in ("fast", "normal", "slow", "mixed", "cheapest", "random", "saver", "bot"):
        os_ = run_profile(pname, 5400, False, log_purchases=True, until_rocket=True)
        print("-- %s" % pname)
        for s_ in range(1, 7):
            xs = [o["tierAt"].get((0, s_), math.inf) for o in os_]
            print("  band %d %-12s entered (first %-6s shipped) at min: p10 %s  median %s  p90 %s" % (
                s_, BANDS[s_ - 1], C["Names"][s_], fmt_min(pct(xs, 0.1)), fmt_min(pct(xs, 0.5)), fmt_min(pct(xs, 0.9))))
        rk = [o["firstRocket"] if o["firstRocket"] is not None else math.inf for o in os_]
        print("  FIRST ROCKET at min: p10 %s  median %s  p90 %s" % (fmt_min(pct(rk, 0.1)), fmt_min(pct(rk, 0.5)), fmt_min(pct(rk, 0.9))))
        gm = [max(gaps_of(o)) for o in os_]
        np_ = [len(o["purchases"]) for o in os_]
        print("  purchases to the rocket: median %d; longest wait between purchases: median %.0f s, max %.0f s" % (
            statistics.median(np_), statistics.median(gm), max(gm)))
        print("  sputters to the rocket (median) %d, saved in the warning %d, machine-seconds jammed %.1f, income lost to jams %.4f" % (
            statistics.median([o["jams"] for o in os_]), statistics.median([o["saved"] for o in os_]),
            statistics.median([o["jamDown"] for o in os_]),
            statistics.median([o["lostIncome"] / max(1e-9, o["idealIncome"]) for o in os_])))
        hz = [o["hazardsToRocket"] if o["hazardsToRocket"] is not None else o["hazards"] for o in os_]
        print("  hazards before the first rocket: median %d (p10 %d, p90 %d)" % (statistics.median(hz), pct(hz, 0.1), pct(hz, 0.9)))
        if pname == "normal":
            o = os_[0]
            print("  seed 1 build at the first rocket:", o.get("buildAtRocket")["stations"])
            for mark in (60, 300, 600, 1200, 1800):
                if mark in o["buildAt"]:
                    print("  seed 1 at %4d s: income %.1f/s  %s" % (mark, o["incAt"][mark], o["buildAt"][mark]["stations"]))


def m3_bands():
    part(3, "band durations, normal profile (20 seeds)")
    os_ = run_profile("normal", 5400, False, until_rocket=True)
    for s_ in range(1, 6):
        d = [o["tierAt"][(0, s_ + 1)] - o["tierAt"][(0, s_)] for o in os_]
        print("band %d %-12s lasts min: min %.1f  median %.1f  max %.1f" % (
            s_, BANDS[s_ - 1], min(d) / 60, statistics.median(d) / 60, max(d) / 60))


def m4_longterm():
    part(4, "recycles over 6 h (20 seeds)")
    for pname in ("fast", "normal", "slow"):
        os_ = run_profile(pname, 6 * 3600, True)
        print("-- %s" % pname)
        for i in range(14):
            rs = [o["runs"][i] for o in os_ if len(o["runs"]) > i]
            if not rs:
                break
            print("  recycle %2d (n=%2d): at min median %6.1f  run %5.1f min  bolts +%d  rockets %d  multiplier before x%.2f" % (
                i + 1, len(rs), statistics.median([r["end"] for r in rs]) / 60,
                statistics.median([r["end"] - r["start"] for r in rs]) / 60,
                statistics.median([r["bolts"] for r in rs]), statistics.median([r["rockets"] for r in rs]),
                statistics.median([r["M"] for r in rs])))
        for mark in (1800, 2400, 3600, 5400, 7200, 10800, 14400, 21600):
            xs = [o["boltsAt"].get(mark, 0) for o in os_]
            print("  lifetime bolts at %4.0f min: p10 %d  median %d  p90 %d" % (mark / 60, pct(xs, 0.1), pct(xs, 0.5), pct(xs, 0.9)))
        for k in (1, 2, 4):
            durs = []
            for s_ in range(1, 7):
                d = []
                for o in os_:
                    if len(o["runs"]) > k:
                        start = o["runs"][k - 1]["end"]
                        a = o["tierAt"].get((k, s_))
                        b = o["tierAt"].get((k, s_ + 1)) if s_ < 6 else o["runs"][k]["end"]
                        if a is not None and b is not None:
                            d.append((b - a) / 60)
                durs.append("%s %.1f" % (BANDS[s_ - 1], statistics.median(d)) if d else "%s -" % BANDS[s_ - 1])
            print("  run %d band durations, median min: %s" % (k + 1, ", ".join(durs)))


def m5_afk():
    part(5, "AFK, macros and bots over 8 h from join (10 seeds)")
    for pname in ("normal", "bot", "afkmacro"):
        os_ = run_profile(pname, 8 * 3600, True, seeds=SEEDS[:10])
        b = [o["final"]["bolts"] for o in os_]
        rk = [o["firstRocket"] if o["firstRocket"] is not None else math.inf for o in os_]
        print("  %-9s lifetime bolts after 8 h: p10 %d  median %d  p90 %d   first rocket at min %s" % (
            pname, pct(b, 0.1), pct(b, 0.5), pct(b, 0.9), fmt_min(statistics.median(rk))))
        if pname in ("normal", "bot"):
            top = [max(s["L"] for s in o["final"]["stations"]) for o in os_]
            print("  %-9s highest station level after 8 h: median %d, max %d (the cap is %d)" % (
                pname, statistics.median(top), max(top), C["MaxLevel"]))
        if pname == "afkmacro":
            o = os_[0]
            print("  afkmacro seed 1 after 8 h: highest product %s, line %s" % (
                C["Names"][o["final"]["tier"]], summary(o["final"])["stations"]))
    for after in (35, 130):
        for pname in ("normal", "bot", "afkmacro", "jiggle"):
            os_ = [simulate("normal", sd, after * 60 + 8 * 3600, True, switch_at=(after * 60, pname)) for sd in SEEDS[:10]]
            gain = [o["final"]["bolts"] - o.get("boltsAtSwitch", 0) for o in os_]
            print("  the normal player hands over at %3d min to %-9s: bolts gained in the next 8 h: p10 %d  median %d  p90 %d" % (
                after, pname, pct(gain, 0.1), pct(gain, 0.5), pct(gain, 0.9)))


def m6_first_minute():
    part(6, "the first 60 seconds (20 seeds)")
    for pname in ("fast", "normal", "slow"):
        os_ = run_profile(pname, 61, False, log_purchases=True)
        fb = [o["firstBuyAt"] for o in os_]
        n60 = [len(o["purchases"]) for o in os_]
        inc30 = [o["incAt"][30] for o in os_]
        inc60 = [o["incAt"][60] for o in os_]
        first = [o["purchases"][0][1:3] for o in os_]
        print("  %-6s free Shredder at 3.0 s; first purchase at s: median %.1f (p10 %.1f, p90 %.1f), most often %s; purchases by 60 s: median %d; income at 30 s %.2f/s, at 60 s %.2f/s" % (
            pname, statistics.median(fb), pct(fb, 0.1), pct(fb, 0.9), statistics.mode(first),
            statistics.median(n60), statistics.median(inc30), statistics.median(inc60)))


def m7_jams():
    part(7, "what jams cost: the normal player's 35-minute line, left alone")
    o = run_profile("normal", 35 * 60, False, seeds=SEEDS[:1])[0]
    st0 = o["final"]
    S0 = clone(st0["stations"])
    ideal = income(S0, st0["M"], True)[0]
    print("  line at 35 min: %s, income %.0f/s tended" % (summary(st0)["stations"], ideal))
    for seed in (1, 2, 3):
        rng = random.Random(seed)
        S = clone(S0)
        machines = [(t, i) for t in range(1, 7) for i in range(S[t - 1]["n"])]
        jam_in, earned, marks = rng.uniform(C["JamMin"], C["JamMax"]), 0.0, {}
        for sec in range(0, 3 * 3600 + 1):
            jam_in -= 1
            if jam_in <= 0:
                ok = [(ti, i) for ti, i in machines if S[ti - 1]["jam"][i] == 0]
                if ok:
                    ti, i = ok[int(rng.random() * len(ok))]
                    S[ti - 1]["jam"][i] = 2  # nobody comes: the sputter is a jam 15 s later
                jam_in = rng.uniform(C["JamMin"], C["JamMax"]) + C["SputterSeconds"]
            inc = income(S, st0["M"])[0]
            earned += inc
            if sec in (300, 600, 900, 1800, 3600, 10800):
                marks[sec] = (inc / ideal, earned / (ideal * sec))
        print("  seed %d: " % seed + "; ".join("%d min: now x%.3f, so far x%.3f" % (m / 60, v[0], v[1]) for m, v in sorted(marks.items())))


def m8_sensitivity():
    part(8, "sensitivity of the first rocket (normal, 20 seeds)")
    keep = {k: (list(v) if isinstance(v, list) else v) for k, v in C.items()}

    def first_rocket():
        os_ = run_profile("normal", 5400, False, until_rocket=True)
        return statistics.median([o["firstRocket"] or math.inf for o in os_])

    for label, patch in (
        ("as specified", {}),
        ("UpgradeGrowth 1.45", {"UpgradeGrowth": 1.45}),
        ("UpgradeGrowth 1.55", {"UpgradeGrowth": 1.55}),
        ("SpeedGrowth 1.22", {"SpeedGrowth": 1.22}),
        ("SpeedGrowth 1.28", {"SpeedGrowth": 1.28}),
        ("BuildPrice x0.8", {"BuildPrice": [round(x * 0.8) for x in keep["BuildPrice"]]}),
        ("BuildPrice x1.25", {"BuildPrice": [round(x * 1.25) for x in keep["BuildPrice"]]}),
        ("SaveWindow 0", {"SaveWindow": 0}),
        ("SaveWindow 120", {"SaveWindow": 120}),
        ("no twins", {"TwinPrice": 10 ** 12}),
    ):
        C.clear()
        C.update({k: (list(v) if isinstance(v, list) else v) for k, v in keep.items()})
        C.update(patch)
        print("  %-20s first rocket median %.1f min" % (label, first_rocket() / 60))
    C.clear()
    C.update(keep)


PARTS = {"1": m1_tables, "2": m2_pacing, "3": m3_bands, "4": m4_longterm, "5": m5_afk,
         "6": m6_first_minute, "7": m7_jams, "8": m8_sensitivity}

if __name__ == "__main__":
    for k in (sys.argv[1:] or sorted(PARTS)):
        PARTS[k]()
