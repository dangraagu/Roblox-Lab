# design/model.py -- Outpost Zero: Sky City Tycoon, the design-time pacing model.
#
# NOT game code. Nothing here ships. It exists so every derived number in DESIGN.md is a number this file
# printed, not a guess. Run from outpost-zero/:   py -3 design/model.py > design/model.out.txt
# (one part only: py -3 design/model.py 3,4). Every part prints a block headed "[M n]"; DESIGN.md cites
# them as [M n]. Deterministic: its own LCG (the repo's constants), no other randomness.
#
# Why Python and not luau: the luau CLI under the session scratchpad was deleted at 17:43 on 2026-10-07,
# mid-task, and did not come back in a 5-minute wait. This file is written so it ports line by line to
# tests/CityModel.luau (meteor-drop-tycoon/tests/PlotModel.luau is the pattern), which is the builder's
# first job: Pacing.spec must run the game's own Economy/City modules, not this copy of them.
#
# What it models: the rules in DESIGN.md sections 3-6 (shelf geometry, lots, prices, capacities, wage,
# districts, the Orders timer, the HUD star) and a player who follows the star. Walking is a straight
# line at WalkSpeed x the profile's efficiency; a hazard hit is a fixed time cost. The player profiles are
# ASSUMPTIONS (DESIGN.md "How to read the numbers"): the first real sessions replace them.
import math, sys, copy

P = {}
WalkSpeed = 16
Shelf = dict(Radius=80, RailRadius=79, LotCornerMax=73, PlazaRadius=26, Pad=(0, -16), HallHalf=7, PromptReach=6)
LotSize, LotMinGap = 10, 4
Templates = {
    "rows": [(44, -14, "H"), (44, 0, "W"), (44, 14, "H"), (58, -14, "W"), (58, 0, "H"), (58, 14, "W")],
    "column": [(38, -7, "H"), (38, 7, "W"), (52, -7, "W"), (52, 7, "H"), (66, -7, "H"), (66, 7, "W")],
    "arc": [(45.7, -14, "H"), (48, 0, "W"), (45.7, 14, "H"), (62.3, -14, "W"), (64, 0, "H"), (62.3, 14, "W")],
}
TemplateOrder = ["rows", "column", "arc"]

E = dict(
    Wage=0.25, StartCredits=30, MaxStoreys=22,
    Cap=[4, 20, 100, 500, 2500, 12500],
    Base=[15, 90, 540, 3240, 19440, 116640],
    Growth=1.35,
    Open=[0, 80, 900, 6400, 35000, 185000],
    OrdersSeconds=600,
)
Hz = dict(IntervalMin=120, IntervalMax=180, FirstBand=2, HitCost=1.9)
Profiles = {
    "fast": dict(react=0.4, eff=0.95, notice=1.0, buy=0.6, hit=0.10),
    "normal": dict(react=1.0, eff=0.85, notice=3.0, buy=1.0, hit=0.25),
    "slow": dict(react=2.0, eff=0.70, notice=8.0, buy=1.5, hit=0.40),
    "walker": dict(react=0, eff=1.0, notice=0, buy=0.125, hit=0),
    "teleport": dict(react=0, eff=math.inf, notice=0, buy=0.125, hit=0),
}
ProfileOrder = ["fast", "normal", "slow", "walker", "teleport"]


def rng(seed):
    s = [math.floor(seed) % 4294967296]
    def r():
        s[0] = (1664525 * s[0] + 1013904223) % 4294967296
        return s[0] / 4294967296
    return r


def below(rand, n):
    return min(n - 1, math.floor(rand() * n))


def fmt(x, d=1):
    return ("%." + str(d) + "f") % x


def median(t):
    c = sorted(t); n = len(c)
    if n == 0: return float("nan")
    if n % 2 == 1: return c[(n + 1) // 2 - 1]
    return (c[n // 2 - 1] + c[n // 2]) / 2


def pct(t, p):
    c = sorted(t)
    idx = min(max(math.floor(p * (len(c) - 1) + 0.5) + 1, 1), len(c))
    return c[idx - 1]


def compact(x):
    if x >= 1e9: return fmt(x / 1e9, 2) + "B"
    if x >= 1e6: return fmt(x / 1e6, 2) + "M"
    if x >= 1e3: return fmt(x / 1e3, 2) + "K"
    return fmt(x, 1)


def cap(d): return E["Cap"][d - 1]
def price(d, s): return E["Base"][d - 1] * E["Growth"] ** (s - 1)


def districtsOpen(pop):
    n = 1
    for d in range(2, len(E["Open"]) + 1):
        if pop >= E["Open"][d - 1]: n = d
    return n


def slotAngle(k): return math.radians(180 + 60 * k)


def toWorld(k, u, v):
    a = slotAngle(k)
    return u * math.sin(a) + v * math.cos(a), u * math.cos(a) - v * math.sin(a)


def layout(seed):
    rand = rng(seed * 7919 + 17)
    slots = [1, 2, 3, 4, 5]
    for i in range(len(slots), 1, -1):
        j = 1 + below(rand, i)
        slots[i - 1], slots[j - 1] = slots[j - 1], slots[i - 1]
    slotOf = [None, 0] + slots  # 1-based districts
    lots, templ = [], {}
    for d in range(1, 7):
        name = TemplateOrder[below(rand, len(TemplateOrder))]
        mirror = rand() < 0.5
        templ[d] = name + ("*" if mirror else "")
        for i, l in enumerate(Templates[name]):
            zone = l[2]
            if mirror: zone = "W" if zone == "H" else "H"
            x, z = toWorld(slotOf[d], l[0], l[1])
            lots.append(dict(d=d, k=slotOf[d], u=l[0], v=l[1], x=x, z=z, zone=zone, s=0, id="%d_%d" % (d, i + 1)))
    return lots, slotOf, templ


def dist(ax, az, bx, bz): return math.sqrt((ax - bx) ** 2 + (az - bz) ** 2)


def lotSamples(l):
    out = []; h = LotSize / 2
    for i in range(11):
        f = -h + LotSize * i / 10
        for uv in ((l["u"] - h, l["v"] + f), (l["u"] + h, l["v"] + f), (l["u"] + f, l["v"] - h), (l["u"] + f, l["v"] + h)):
            out.append(toWorld(l["k"], uv[0], uv[1]))
    return out


def star(st, px, pz):
    # The deficit side first (both when balanced). Among it, the action that pays for itself soonest,
    # counting the wait: (time until affordable) + (price of the pair / income the pair adds).
    # Only actions affordable before the Orders run out; ties to the nearer lot.
    open_ = districtsOpen(st["pop"])
    side = None
    if st["R"] < st["J"]: side = "H"
    elif st["J"] < st["R"]: side = "W"
    budget = st["credits"] + st["income"] * E["OrdersSeconds"]
    best, bestScore, bestD = None, math.inf, math.inf
    cheapest, cheapestP = None, math.inf
    for l in st["lots"]:
        if l["d"] <= open_ and l["s"] < E["MaxStoreys"] and (side is None or l["zone"] == side):
            p = price(l["d"], l["s"] + 1)
            if p < cheapestP: cheapest, cheapestP = l, p
            if p <= budget:
                if st["credits"] >= p: wait = 0.0
                elif st["income"] > 0: wait = (p - st["credits"]) / st["income"]
                else: continue
                score = wait + 2 * p / (E["Wage"] * cap(l["d"]))
                dd = dist(px, pz, l["x"], l["z"])
                if score < bestScore * (1 - 1e-9) or (abs(score - bestScore) <= bestScore * 1e-9 and dd < bestD):
                    best, bestScore, bestD = l, score, dd
    return best or cheapest


def buy(st, l):
    p = price(l["d"], l["s"] + 1)
    st["credits"] -= p
    l["s"] += 1
    if l["zone"] == "H": st["R"] += cap(l["d"])
    else: st["J"] += cap(l["d"])
    st["pop"] = min(st["R"], st["J"])
    st["income"] = E["Wage"] * st["pop"]
    st["buys"] += 1
    return p


def newState(seed):
    lots, slotOf, templ = layout(seed)
    return dict(lots=lots, slotOf=slotOf, templ=templ, credits=E["StartCredits"], R=0, J=0, pop=0, income=0, buys=0)


def simulate(profName, seed, minutes, opts=None):
    opts = opts or {}
    prof = Profiles[profName]
    rand = rng(seed * 104729 + 3)
    st = newState(seed)
    S = dict(t=0.0, hazardClock=0.0, hazards=0, hits=0)
    px, pz = Shelf["Pad"]
    S["ordersUntil"] = E["OrdersSeconds"]
    bandAt = {1: 0}
    lastBuy, maxGap, lapses = 0, 0, 0
    S["nextHaz"] = Hz["IntervalMin"] + (Hz["IntervalMax"] - Hz["IntervalMin"]) * rand()
    first = []
    spans, span = [], 0.0
    T = minutes * 60
    log = opts.get("log")

    def advance(dt):
        if dt <= 0: return
        t = S["t"]
        working = max(0, min(t + dt, S["ordersUntil"]) - t)
        st["credits"] += st["income"] * working
        S["hazardClock"] += dt
        while S["hazardClock"] >= S["nextHaz"]:
            band = districtsOpen(st["pop"])
            if band >= Hz["FirstBand"]:
                S["hazards"] += 1
                if rand() < prof["hit"]:
                    S["hits"] += 1
                    S["t"] += Hz["HitCost"]
                    w2 = max(0, min(S["t"], S["ordersUntil"]) - (S["t"] - Hz["HitCost"]))
                    st["credits"] += st["income"] * w2
            S["nextHaz"] += Hz["IntervalMin"] + (Hz["IntervalMax"] - Hz["IntervalMin"]) * rand()
        S["t"] += dt

    while S["t"] < T:
        l = star(st, px, pz)
        if l is None: break
        t0 = S["t"]; advance(prof["react"]); span += S["t"] - t0
        d = dist(px, pz, l["x"], l["z"])
        walk = max(0, d - Shelf["PromptReach"])
        if prof["eff"] != math.inf and walk > 0:
            spans.append(span); span = 0.0
            advance(walk / (WalkSpeed * prof["eff"]))
            f = (d - Shelf["PromptReach"]) / d
            px, pz = px + (l["x"] - px) * f, pz + (l["z"] - pz) * f
        p = price(l["d"], l["s"] + 1)
        if st["credits"] < p:
            if st["income"] <= 0: break
            need = (p - st["credits"]) / st["income"]
            if S["t"] + need > S["ordersUntil"]:
                lapses += 1
                break
            t1 = S["t"]; advance(need); advance(prof["notice"] * rand()); span += S["t"] - t1
        t2 = S["t"]; advance(prof["buy"]); span += S["t"] - t2
        if st["credits"] < p - 1e-6: st["credits"] = p
        before = districtsOpen(st["pop"])
        buy(st, l)
        S["ordersUntil"] = S["t"] + E["OrdersSeconds"]
        maxGap = max(maxGap, S["t"] - lastBuy)
        lastBuy = S["t"]
        if len(first) < 8:
            first.append(dict(t=S["t"], what=("Home" if l["zone"] == "H" else "Workshop") + " d%d storey %d" % (l["d"], l["s"]), pop=st["pop"]))
        after = districtsOpen(st["pop"])
        for b in range(before + 1, after + 1): bandAt[b] = S["t"]
        if log: log(S["t"], st, l)
        if opts.get("stopAtBand") and after >= opts["stopAtBand"]: break
    return dict(st=st, t=S["t"], bandAt=bandAt, maxGap=maxGap, lapses=lapses, hazards=S["hazards"], hits=S["hits"],
                first=first, px=px, pz=pz, ordersUntil=S["ordersUntil"], spans=spans)


SEEDS = 40
PROFILE_MINUTES = 240
import os
PARTS = set(sys.argv[1].split(",")) if len(sys.argv) > 1 else None
if os.environ.get("OZ_IMPORT"): PARTS = set()
def want(n): return PARTS is None or n in PARTS

if want("1"):
    print("[M1] geometry: lots inside the shelf, gaps between lots, walks from the pad")
    worstCorner, worstGapIn, worstGapAcross, minInner = 0, math.inf, math.inf, math.inf
    walks, d1walk = [], math.inf
    for seed in range(1, 201):
        lots = layout(seed)[0]
        for i, a in enumerate(lots):
            for s in lotSamples(a):
                r = math.sqrt(s[0] ** 2 + s[1] ** 2)
                worstCorner = max(worstCorner, r); minInner = min(minInner, r)
            for b in lots[i + 1:]:
                if a["d"] == b["d"]:
                    worstGapIn = min(worstGapIn, max(abs(a["u"] - b["u"]), abs(a["v"] - b["v"])) - LotSize)
                elif dist(a["x"], a["z"], b["x"], b["z"]) < 40:
                    sa, sb = lotSamples(a), lotSamples(b)
                    for p in sa:
                        for q in sb:
                            worstGapAcross = min(worstGapAcross, dist(p[0], p[1], q[0], q[1]))
            w = max(0, dist(Shelf["Pad"][0], Shelf["Pad"][1], a["x"], a["z"]) - Shelf["PromptReach"])
            walks.append(w)
            if a["d"] == 1: d1walk = min(d1walk, w)
    print("  furthest lot corner from the centre: %s (limit %d, rail %d)" % (fmt(worstCorner, 2), Shelf["LotCornerMax"], Shelf["RailRadius"]))
    print("  nearest lot corner to the centre: %s (plaza radius %d)" % (fmt(minInner, 2), Shelf["PlazaRadius"]))
    print("  smallest gap between two lots of one district: %s studs (rule >= %d)" % (fmt(worstGapIn, 2), LotMinGap))
    print("  smallest gap between lots of neighbouring districts: %s studs" % fmt(worstGapAcross, 2))
    print("  walk from the pad to a lot (to prompt reach): median %s, max %s studs" % (fmt(median(walks)), fmt(max(walks))))
    print("  nearest district-1 lot from the pad: %s studs = %s s at the normal walk" % (fmt(d1walk), fmt(d1walk / (WalkSpeed * 0.85), 2)))
    print("  across the shelf (pad to the furthest lot): %s s at the normal walk" % fmt(max(walks) / (WalkSpeed * 0.85), 2))
    # sign posts: 5.5 studs from each lot centre toward the shelf centre (DESIGN.md 3.3), 1000 seeds
    worstPost = math.inf
    for seed in range(1, 1001):
        posts = [toWorld(l["k"], l["u"] - 5.5, l["v"]) for l in layout(seed)[0]]
        for i in range(len(posts)):
            for j in range(i + 1, len(posts)):
                worstPost = min(worstPost, dist(posts[i][0], posts[i][1], posts[j][0], posts[j][1]))
    print("  closest two sign posts over 1000 seeds: %s studs" % fmt(worstPost, 2))

if want("2"):
    print("\n[M2] economy per district: capacity per storey, prices, value, and the full city")
    maxPop = 0
    for d in range(1, 7):
        maxPop += 3 * E["MaxStoreys"] * cap(d)
        S = E["MaxStoreys"]
        print("  d%d: cap %6d  storey1 %8s  storey10 %9s  storey%d %10s  cap/credit at storey 1 %.4f  opens at pop %s" % (
            d, cap(d), compact(price(d, 1)), compact(price(d, 10)), S, compact(price(d, S)), cap(d) / price(d, 1), compact(E["Open"][d - 1])))
    print("  full city (36 lots x %d storeys): population %d, income %s/s" % (E["MaxStoreys"], maxPop, compact(maxPop * E["Wage"])))
    print("  board encoding pop*2e9 + (2e9 - at): max value %.4e vs 2^53 = %.4e" % (maxPop * 2e9 + 2e9, 2 ** 53))
    lastP = price(6, E["MaxStoreys"]); almostPop = maxPop - cap(6)
    print("  dearest storey (d6 storey %d) %s = %s s of the income of a city one storey short of complete" % (E["MaxStoreys"], compact(lastP), fmt(lastP / (almostPop * E["Wage"]))))
    worstEnd = lastP / (E["Wage"] * (maxPop - 3 * cap(6)))
    print("  ... and %s s when all three d6 Homes (or Workshops) are one storey short; rule: <= half the Orders (%d s)" % (fmt(worstEnd), E["OrdersSeconds"] // 2))
    print("  starting city: 2 builds (%s) -> population %d, income %s/s" % (compact(2 * price(1, 1)), cap(1), fmt(cap(1) * E["Wage"], 2)))

runs = {}
if want("3") or want("4") or want("5") or want("6"):
    print("\n[M3] minutes to ENTER each band (district), %d seeds each, %d min sessions" % (SEEDS, PROFILE_MINUTES))
    for name in ProfileOrder:
        runs[name] = {}
        cols = {b: [] for b in range(2, 7)}
        lapses, gaps = 0, []
        for seed in range(1, SEEDS + 1):
            r = simulate(name, seed, PROFILE_MINUTES)
            runs[name][seed] = r
            for b in range(2, 7): cols[b].append(r["bandAt"].get(b, math.inf) / 60)
            lapses += r["lapses"]; gaps.append(r["maxGap"])
        line = "  %-8s" % name
        for b in range(2, 7):
            line += "  b%d %6s (p10 %6s p90 %6s)" % (b, fmt(median(cols[b])), fmt(pct(cols[b], 0.1)), fmt(pct(cols[b], 0.9)))
        print(line)
        print("  %-8s  orders lapses %d; longest gap between purchases: median %s s, max %s s" % ("", lapses, fmt(median(gaps)), fmt(max(gaps))))

if want("4"):
    print("\n[M4] how long each band lasts (normal profile, minutes)")
    for b in range(1, 6):
        d = []
        for seed in range(1, SEEDS + 1):
            r = runs["normal"][seed]
            a = r["bandAt"].get(b, 0); z = r["bandAt"].get(b + 1)
            if z is not None: d.append((z - a) / 60)
        print("  band %d: median %s, min %s" % (b, fmt(median(d), 2), fmt(min(d), 2)))
    pops = [runs["normal"][s]["st"]["pop"] for s in range(1, SEEDS + 1)]
    print("  population after %d min: median %s" % (PROFILE_MINUTES, compact(median(pops))))

if want("5"):
    print("\n[M5] the first purchases of a normal player (seed 1..5)")
    for seed in range(1, 6):
        r = runs["normal"][seed]
        parts = ["%ss %s (pop %d)" % (fmt(f["t"]), f["what"], f["pop"]) for f in r["first"][:6]]
        print("  seed %d: %s" % (seed, "; ".join(parts)))
    n60 = [simulate("normal", seed, 1)["st"]["buys"] for seed in range(1, SEEDS + 1)]
    print("  purchases in the first 60 s: median %s, min %s" % (fmt(median(n60), 0), fmt(min(n60), 0)))

if want("6"):
    print("\n[M6] hazards for a normal player (none in band 1)")
    before, firstAt = [], []
    for seed in range(1, SEEDS + 1):
        brag = runs["normal"][seed]["bandAt"][4]
        r = simulate("normal", seed, brag / 60 + 1e-6)
        before.append(r["hazards"])
        firstAt.append(runs["normal"][seed]["bandAt"].get(2, 0) / 60)
    print("  hazards launched before the brag: median %s (min %s, max %s)" % (fmt(median(before), 0), fmt(min(before), 0), fmt(max(before), 0)))
    print("  hazard-free start (band 1) lasts: median %s min" % fmt(median(firstAt), 2))


def cloneState(st):
    c = dict(st); c["lots"] = [dict(l) for l in st["lots"]]; return c


def cheapestPrice(st):
    open_ = districtsOpen(st["pop"])
    return min((price(x["d"], x["s"] + 1) for x in st["lots"] if x["d"] <= open_ and x["s"] < E["MaxStoreys"]), default=math.inf)


NET = dict(engaged=0, checked=0)  # the safety net: the city also works while no storey is affordable


def macroOneLot(st0, li, hours):
    st = cloneState(st0); l = st["lots"][li]
    if l["d"] > districtsOpen(st["pop"]): return 0, 0, 0
    t, ordersUntil, T = 0.0, E["OrdersSeconds"], hours * 3600
    pop0, earned = st["pop"], 0
    while t < T and l["s"] < E["MaxStoreys"]:
        p = price(l["d"], l["s"] + 1)
        if st["credits"] < p:
            if st["income"] <= 0: break
            need = (p - st["credits"]) / st["income"]
            if t + need > ordersUntil:
                earned += st["income"] * max(0, ordersUntil - t)
                st["credits"] += st["income"] * max(0, ordersUntil - t)
                NET["checked"] += 1
                if st["credits"] < cheapestPrice(st): NET["engaged"] += 1
                break
            t += need; earned += st["income"] * need; st["credits"] = p
        t += 0.125; buy(st, l); ordersUntil = t + E["OrdersSeconds"]
    return st["pop"] - pop0, l["s"], earned


def macroTwoLots(st0, hi, wi, hours):
    st = cloneState(st0); h, w = st["lots"][hi], st["lots"][wi]
    walk = max(0, dist(h["x"], h["z"], w["x"], w["z"]) - 2 * Shelf["PromptReach"]) / WalkSpeed
    t, ordersUntil, T = 0.0, E["OrdersSeconds"], hours * 3600
    pop0 = st["pop"]
    turn = h if st["R"] <= st["J"] else w
    while t < T:
        if turn["s"] >= E["MaxStoreys"] or turn["d"] > districtsOpen(st["pop"]): break
        p = price(turn["d"], turn["s"] + 1)
        if st["credits"] < p:
            if st["income"] <= 0: break
            need = (p - st["credits"]) / st["income"]
            if t + need > ordersUntil:
                st["credits"] += st["income"] * max(0, ordersUntil - t)
                NET["checked"] += 1
                if st["credits"] < cheapestPrice(st): NET["engaged"] += 1
                break
            t += need; st["credits"] = p
        t += 0.125; buy(st, turn); ordersUntil = t + E["OrdersSeconds"]
        turn = w if turn is h else h
        t += walk
    return st["pop"] - pop0


if want("7"):
    print("\n[M7] AFK and macros, starting from the normal player's state when the brag band opens (seed 1..10)")
    afk, one, oneSt, two, human = [], [], [], [], []
    for seed in range(1, 11):
        r = simulate("normal", seed, PROFILE_MINUTES, dict(stopAtBand=4))
        st = r["st"]
        left = max(0, r["ordersUntil"] - r["t"])
        afk.append(left / 60)
        NET["checked"] += 1
        if st["credits"] + st["income"] * left < cheapestPrice(st): NET["engaged"] += 1
        bestPop, bestS = 0, 0
        for i in range(len(st["lots"])):
            dp, s, _ = macroOneLot(st, i, 8)
            if dp > bestPop or (dp == bestPop and s > bestS): bestPop, bestS = dp, s
        one.append(bestPop / max(1, st["pop"])); oneSt.append(bestS)
        bestTwo = 0
        for i, a in enumerate(st["lots"]):
            if a["zone"] == "H":
                for j, b in enumerate(st["lots"]):
                    if b["zone"] == "W":
                        bestTwo = max(bestTwo, macroTwoLots(st, i, j, 8))
        two.append(bestTwo / max(1, st["pop"]))
        r8 = simulate("normal", seed, r["t"] / 60 + 480)
        human.append((r8["st"]["pop"] - st["pop"]) / max(1, st["pop"]))
        if seed == 1:
            print("  seed 1 state: population %d, income %s/s, credits %s" % (st["pop"], compact(st["income"]), compact(st["credits"])))
    print("  idle (AFK or an anti-AFK jiggle): the city earns at most %s more minutes of income, then stops; population +0" % fmt(max(afk), 2))
    print("  one-lot prompt macro, best lot, 8 h: population x%s (median x%s), that lot ends at storey %s" % (fmt(1 + max(one), 3), fmt(1 + median(one), 3), fmt(median(oneSt), 0)))
    print("  two-lot route macro, best pair, 8 h: population x%s (median x%s)" % (fmt(1 + max(two), 3), fmt(1 + median(two), 3)))
    print("  the normal human, 8 more hours:      population x%s .. x%s" % (fmt(1 + min(human), 3), fmt(1 + max(human), 3)))
    print("  safety net (the city also works while no storey is affordable): engaged %d of %d stalls" % (NET["engaged"], NET["checked"]))

if want("8"):
    print("\n[M8] sensitivity (normal profile, median of %d seeds): brag (band 4) and long goal (band 6) minutes" % SEEDS)
    saved = E["Growth"]
    for g in (1.30, 1.33, 1.35, 1.37, 1.40):
        E["Growth"] = g
        b4, b6 = [], []
        for seed in range(1, SEEDS + 1):
            r = simulate("normal", seed, PROFILE_MINUTES)
            b4.append(r["bandAt"].get(4, math.inf) / 60); b6.append(r["bandAt"].get(6, math.inf) / 60)
        print("  Growth %.2f: brag %s, long goal %s" % (g, fmt(median(b4)), fmt(median(b6))))
    E["Growth"] = saved

if want("9"):
    print("\n[M9] dead-end check: walker macro (perfect play) for 48 h, seeds 1..5")
    for seed in range(1, 6):
        box = dict(worst=0, done=None)
        def log(t, st, l, box=box):
            open_ = districtsOpen(st["pop"])
            cheapest = math.inf
            for x in st["lots"]:
                if x["d"] <= open_ and x["s"] < E["MaxStoreys"]: cheapest = min(cheapest, price(x["d"], x["s"] + 1))
            if cheapest < math.inf:
                box["worst"] = max(box["worst"], (cheapest - st["credits"]) / max(st["income"], 1e-9))
            elif box["done"] is None:
                box["done"] = t
        r = simulate("walker", seed, 48 * 60, dict(log=log))
        print("  seed %d: worst wait for the cheapest storey %s s (Orders %d s); lapses %d; city complete at %s h; pop %s" % (
            seed, fmt(box["worst"]), E["OrdersSeconds"], r["lapses"], fmt(box["done"] / 3600, 2) if box["done"] else "not yet", compact(r["st"]["pop"])))

if want("10"):
    print("\n[M10] share of a normal player's first 60 min spent in idle rest, by IdleSeconds (stormgrow REVIEW-1 B2)")
    for idle in (20, 45, 60, 90):
        shares = []
        for seed in range(1, SEEDS + 1):
            r = simulate("normal", seed, 60)
            rested = sum(max(0, sp - idle) for sp in r["spans"])
            shares.append(rested / r["t"])
        print("  IdleSeconds %3d: median %s%%, max %s%%" % (idle, fmt(100 * median(shares)), fmt(100 * max(shares))))
    longest = [max(simulate("normal", seed, 60)["spans"]) for seed in range(1, SEEDS + 1)]
    print("  longest standing span in the first hour: median %s s, max %s s" % (fmt(median(longest)), fmt(max(longest))))

if want("11"):
    print("\n[M11] skyline: average and highest storey per open district when a band opens (normal, seeds 1..10)")
    for band in (4, 6):
        per = {d: [] for d in range(1, 7)}
        for seed in range(1, 11):
            r = simulate("normal", seed, PROFILE_MINUTES, dict(stopAtBand=band))
            for l in r["st"]["lots"]:
                per[l["d"]].append(l["s"])
        parts = []
        for d in range(1, band):
            parts.append("d%d avg %s max %d" % (d, fmt(sum(per[d]) / len(per[d])), max(per[d])))
        print("  band %d opens: %s" % (band, "; ".join(parts)))
    done = []
    for seed in range(1, 6):
        box = dict(done=None)
        def log2(t, st, l, box=box):
            if all(x["s"] >= E["MaxStoreys"] for x in st["lots"]) and box["done"] is None: box["done"] = t
        simulate("normal", seed, 12 * 60, dict(log=log2))
        done.append(box["done"] / 3600 if box["done"] else math.inf)
    print("  normal player completes the city (every lot at %d storeys): median %s h (seeds 1..5: %s)" % (E["MaxStoreys"], fmt(median(done), 2), ", ".join(fmt(x, 2) for x in done)))

