#!/usr/bin/env python3
"""
Find It! Chapters -- DESIGN-TIME MEASUREMENT MODEL. Not game code; nothing here ships, Rojo never maps it.

Every [M n] number in DESIGN.md is printed by Part n of this file. Re-run it after changing any constant
below and re-read the numbers before touching the spec:

    py -3 design/model.py            (from find-it-chapters/, about a minute, deterministic)
    py -3 design/model.py --part 4   (one part)

Why Python and not Luau: on 2026-10-07 the luau CLI directory named in the brief
(scratchpad/luau/) was empty and no luau.exe exists anywhere on this machine. Downloading one needs the
owner's go, so the design numbers come from this script. The build phase turns Part 1 into Dressing.spec and
Hide.spec and ports Parts 2-3 into tests/FinderModel.luau + tests/Pacing.spec.luau against the real Config.luau;
until then every number here is a property of this model, not of the game.

What this is NOT: a physics or perception model. Rooms are flat rectangles, spots are points, walking is
a straight line times a detour factor at 16 studs/s times an efficiency. How fast a person notices a
matching prop, how often they misread a clue and when they take the hint are ASSUMPTIONS (PROFILES
below); the model reports what follows from them. The first real play session replaces them.
"""
import argparse
import math
import random
import statistics

# ----------------------------------------------------------------------------------------------- the rules
KINDS = ["box", "basket", "jar", "vase", "pot", "cushion", "bag", "chest"]
COLOURS = ["white", "yellow", "blue", "green"]          # never red (hazard ring), never gold (found)
HEIGHTS = ["floor", "table", "high"]
VALUES = {"kind": KINDS, "colour": COLOURS, "height": HEIGHTS}
FORMS = {"K": ("kind",), "CK": ("colour", "kind"), "CH": ("colour", "height"), "KH": ("kind", "height")}

WALK_SPEED = 16.0        # Roblox default WalkSpeed
STAND_OFF = 5.0          # a player stops this far short of the spot they search (reach is 10, see DESIGN 6.3)
SEARCH_SECONDS = 1.0     # the rummage; the server answers at its end
GRACE = 5.0              # hazards never come in the first 5 s of an attempt
DOOR_CLEAR = 6.0         # no spot within 6 studs of the door mat

# Book One: 15 chapters in 5 bands of 3. ch, items N, candidates per clue k, spots S, share of fillers that are
# partial matches, allowed clue forms with weights, room interior W x D (studs).
CHAPTERS = [
    # ch  N  k  S   rho   forms                                    W   D
    (1,  3, 3, 16, 0.25, {"K": 2, "CK": 1},                       32, 24),
    (2,  4, 3, 20, 0.25, {"K": 1, "CK": 2},                       32, 24),
    (3,  4, 4, 26, 0.30, {"CK": 2, "CH": 1},                      40, 30),
    (4,  5, 4, 30, 0.30, {"CK": 1, "CH": 1},                      40, 30),
    (5,  5, 4, 34, 0.35, {"CK": 1, "CH": 1, "KH": 1},             44, 34),
    (6,  6, 4, 38, 0.35, {"CK": 1, "CH": 1, "KH": 1},             44, 34),
    (7,  6, 4, 42, 0.40, {"CK": 1, "CH": 1, "KH": 1},             44, 34),
    (8,  6, 5, 46, 0.40, {"CK": 1, "CH": 1, "KH": 1},             44, 34),
    (9,  7, 5, 50, 0.45, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
    (10, 7, 5, 52, 0.45, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
    (11, 7, 5, 54, 0.45, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
    (12, 8, 5, 56, 0.50, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
    (13, 8, 5, 58, 0.50, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
    (14, 8, 5, 60, 0.50, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
    (15, 9, 5, 64, 0.50, {"CK": 1, "CH": 1, "KH": 1},             48, 38),
]
BANDS = [(1, 3), (4, 6), (7, 9), (10, 12), (13, 15)]   # Cottage, Library, Greenhouse, Ship, Observatory
DAILY = (0, 6, 4, 44, 0.40, {"CK": 1, "CH": 1, "KH": 1}, 44, 34)

# Clocks (s). Chosen in Part 2 from the normal profile's uncapped clear time, hint OFF and no hazards:
# ch1-3 at its p97, ch4-15 at p90, rounded UP to 5 s. Part 2 prints the derivation and stops if this table
# differs from it.
CLOCK_TARGET = {1: 0.97, 2: 0.97, 3: 0.97}   # every other chapter: 0.90
CLOCKS = {1: 70, 2: 95, 3: 120, 4: 125, 5: 130, 6: 155, 7: 160, 8: 175, 9: 210, 10: 210, 11: 215, 12: 245, 13: 245,
          14: 250, 15: 275}
DAILY_CLOCK = 195        # the normal profile's p98 on DAILY, rounded up to 5 s (Part 5 stops if it differs)
SWIFT_FRACTION = 2 / 3   # Swift: all found within the first two thirds of the clock
SHARP_SLIPS = 1          # Sharp: at most this many searches that fit no unfound clue, and no hint
LOOKS_SLACK = 2          # Looks per attempt = N * k + LOOKS_SLACK. A player who only searches props that fit an
                         # unfound clue needs at most N * k, so careful play can never run out (Part 2 measures it)

# Overheads (s), [C]: card and move times the HUD design fixes (DESIGN 9).
SESSION_START = 4.0      # spawn to the Case Book prompt
INTRO_FIRST = 3.0        # chapter intro card the first time
INTRO_RETRY = 1.5        # the short card on a retry / replay
CLEAR_CARD = 4.0         # clear or time's-up card, then Next / Retry moves you at once
MOVE = 1.0               # the server PivotTo and the room build

# Hazards (DESIGN 8): one per IntervalMin..IntervalMax seconds of EXPOSED time (in a room, not resting,
# past GRACE). Costs are [A]: the dodge (step out, wait for the drop) and the stumble on a hit.
HZ_MIN, HZ_MAX = 100.0, 140.0
HZ_DODGE = 2.0
HZ_KNOCK = 0.6

# Profiles, ALL [A]. read: seconds to read one clue chip. tau: mean seconds to notice ONE specific matching
# prop in a 36-spot room (the next of m unnoticed candidates is noticed after Exp(tau/m) -- the last one is
# the hardest); scaled by sqrt(S/36) for clutter. eff/detour: walking. select: the first tap (outline and
# label) before the confirming tap. slip: chance a candidate search is preceded by a search of a prop that
# fits NO clue (a misread decoy). hint_at: takes the one hint when less than this share of the clock is left.
# p_hit: share of hazards that land.
PROFILES = {
    "fast":   dict(read=1.0, tau=6.0,  eff=0.95, detour=1.20, select=0.3, slip=0.03, hint_at=0.00, p_hit=0.05),
    "normal": dict(read=1.5, tau=10.0, eff=0.85, detour=1.25, select=0.4, slip=0.07, hint_at=0.30, p_hit=0.15),
    "slow":   dict(read=2.5, tau=16.0, eff=0.75, detour=1.30, select=0.6, slip=0.12, hint_at=0.40, p_hit=0.30),
}


# ----------------------------------------------------------------------------------------------- generator
def matches(spot, clue):
    return all(spot[a] == clue[a] for a in FORMS[clue["form"]])


def subsumes(a, b):
    """True if every spot that matches b also matches a (a's constraints are a subset of b's)."""
    return all(a[x] == b.get(x) for x in FORMS[a["form"]])


def make_clues(rng, n, forms):
    names = list(forms.keys())
    weights = [forms[f] for f in names]
    clues = []
    guard = 0
    while len(clues) < n:
        guard += 1
        if guard > 1000:
            return None
        form = rng.choices(names, weights)[0]
        c = {"form": form}
        for a in FORMS[form]:
            c[a] = rng.choice(VALUES[a])
        if any(subsumes(c, o) or subsumes(o, c) for o in clues):
            continue  # one clue's matches would all match the other: disjoint candidate sets impossible
        clues.append(c)
    return clues


def random_spot(rng, fixed=None):
    s = {a: rng.choice(VALUES[a]) for a in ("kind", "colour", "height")}
    if fixed:
        s.update(fixed)
    return s


def build_room(rng, chapter, near_door_first=False):
    """Returns (room, attempts). The dressing is built from the CLUES only; the hidden spot is drawn later,
    from another generator, uniformly among each clue's candidates."""
    ch, n, k, S, rho, forms, W, D = chapter
    for attempt in range(1, 201):
        clues = make_clues(rng, n, forms)
        if clues is None:
            continue
        spots = []
        ok = True
        # k candidates per clue, each matching that clue and no other
        for ci, c in enumerate(clues):
            for _ in range(k):
                for _try in range(60):
                    s = random_spot(rng, {a: c[a] for a in FORMS[c["form"]]})
                    if not any(matches(s, o) for j, o in enumerate(clues) if j != ci):
                        break
                else:
                    ok = False
                    break
                s["role"], s["clue"] = "cand", ci
                spots.append(s)
            if not ok:
                break
        if not ok:
            continue
        # fillers: a share rho are partial matches (one of a two-attribute clue's constraints, not the other)
        n_fill = S - n * k
        if n_fill < 0:
            raise ValueError("S too small")
        two = [c for c in clues if len(FORMS[c["form"]]) == 2]
        for f in range(n_fill):
            want_partial = two and rng.random() < rho
            for _try in range(200):
                if want_partial:
                    c = rng.choice(two)
                    keep, change = rng.sample(list(FORMS[c["form"]]), 2)
                    s = random_spot(rng, {keep: c[keep]})
                    if s[change] == c[change]:
                        continue
                    role = "partial"
                else:
                    s = random_spot(rng)
                    role = "filler"
                if not any(matches(s, o) for o in clues):
                    break
            else:
                ok = False
                break
            s["role"], s["clue"] = role, None
            spots.append(s)
        if not ok:
            continue
        # positions: drawn for the whole room, then dealt to the shuffled spots, so a role has no place
        pts = place_points(rng, S, W, D)
        if pts is None:
            continue
        rng.shuffle(spots)
        if near_door_first:
            # chapter 1: clue 1's candidates take the positions nearest the door (public, and still exchangeable)
            door = (W / 2, 0.0)
            pts.sort(key=lambda p: dist(p, door))
            first = [s for s in spots if s["role"] == "cand" and s["clue"] == 0]
            rest = [s for s in spots if not (s["role"] == "cand" and s["clue"] == 0)]
            spots = first + rest
        for s, p in zip(spots, pts):
            s["x"], s["z"] = p
        for i, s in enumerate(spots):
            s["id"] = i
        cands = [[s["id"] for s in spots if s["role"] == "cand" and s["clue"] == ci] for ci in range(n)]
        return {"ch": ch, "n": n, "k": k, "S": S, "W": W, "D": D, "clues": clues, "spots": spots,
                "cands": cands}, attempt
    raise RuntimeError("generator failed 200 times")


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def place_points(rng, n, W, D, margin=2.0, spacing=3.0):
    door = (W / 2, 0.0)
    pts = []
    tries = 0
    while len(pts) < n:
        tries += 1
        if tries > 20000:
            return None
        p = (rng.uniform(margin, W - margin), rng.uniform(margin, D - margin))
        if dist(p, door) < DOOR_CLEAR:
            continue
        if all(dist(p, q) >= spacing for q in pts):
            pts.append(p)
    return pts


def hide(rng, room):
    """The secret: one candidate per clue, uniformly, from a generator that never saw the dressing's draws."""
    return [rng.choice(c) for c in room["cands"]]


# ----------------------------------------------------------------------------------------------- hazards
class HazardClock:
    """The template's scheduler reduced to what pacing needs: one hazard per U(HZ_MIN, HZ_MAX) s of exposed
    time; the clock persists across chapters and freezes outside rooms (Hazards.step with ctx.resting)."""

    def __init__(self, rng):
        self.rng = rng
        self.exposed = 0.0
        self.next_at = rng.uniform(HZ_MIN, HZ_MAX)
        self.count = 0
        self.hits = 0

    def expose(self, dt, p_hit):
        """Advance by dt exposed seconds; returns the extra seconds the hazards that came cost."""
        extra = 0.0
        self.exposed += dt
        while self.exposed >= self.next_at:
            self.count += 1
            extra += HZ_DODGE
            if self.rng.random() < p_hit:
                self.hits += 1
                extra += HZ_KNOCK
            self.next_at += self.rng.uniform(HZ_MIN, HZ_MAX)
        return extra


# ----------------------------------------------------------------------------------------------- players
class Attempt:
    def __init__(self, room, hidden, clock, hz, p_hit):
        self.room, self.hidden, self.clock, self.hz, self.p_hit = room, hidden, clock, hz, p_hit
        self.t = 0.0
        self.pos = (room["W"] / 2, 1.0)
        self.searched = set()
        self.found = [False] * room["n"]
        self.searches = 0
        self.off = 0
        self.hint = False
        self.looks = room["n"] * room["k"] + LOOKS_SLACK
        self.out_of_looks = False
        self.first_find = None
        self.hazards = 0

    def spend(self, dt):
        before = self.t
        self.t += dt
        if self.hz is not None:
            exposed = max(0.0, self.t - max(before, GRACE))
            if exposed > 0:
                n0 = self.hz.count
                self.t += self.hz.expose(exposed, self.p_hit)
                self.hazards += self.hz.count - n0

    def over(self, cap):
        return self.out_of_looks or (cap and self.t > self.clock)

    def spot(self, sid):
        s = self.room["spots"][sid]
        return (s["x"], s["z"])

    def walk(self, sid, eff, detour):
        p = self.spot(sid)
        d = dist(self.pos, p)
        travel = max(0.0, d - STAND_OFF)
        if d > 0:
            f = travel / d
            self.pos = (self.pos[0] + (p[0] - self.pos[0]) * f, self.pos[1] + (p[1] - self.pos[1]) * f)
        if eff > 0:
            self.spend(travel * detour / (WALK_SPEED * eff))

    def unfound_cands(self):
        out = set()
        for ci, c in enumerate(self.room["cands"]):
            if not self.found[ci]:
                out.update(c)
        return out

    def search(self, sid, select):
        if self.looks <= 0:
            self.out_of_looks = True
            return False
        self.looks -= 1
        on_clue = sid in self.unfound_cands()
        self.spend(select + SEARCH_SECONDS)
        self.searches += 1
        if not on_clue:
            self.off += 1
        self.searched.add(sid)
        hit = False
        for ci, h in enumerate(self.hidden):
            if h == sid and not self.found[ci]:
                self.found[ci] = True
                if self.first_find is None:
                    self.first_find = self.t
                hit = True
        if self.looks <= 0 and not all(self.found):
            self.out_of_looks = True
        return hit

    def result(self):
        done = all(self.found)
        t = self.t if done else self.clock
        return {
            "found": done and self.t <= self.clock and not self.out_of_looks,
            "out_of_looks": self.out_of_looks and not done,
            "t": self.t,
            "spent": min(self.t, self.clock) if not done or self.t > self.clock else self.t,
            "searches": self.searches,
            "off": self.off,
            "hint": self.hint,
            "items": sum(self.found),
            "first": self.first_find,
            "hazards": self.hazards,
        }


def play_human(room, hidden, prof, rng, clock, hz=None, cap=True, use_hint=True, looks=True):
    """One clue at a time, in list order. Notices the next of the clue's m unsearched candidates after
    Exp(tau'/m), walks to it, taps it twice (select, search). With prob slip, first searches the nearest
    unsearched prop that fits no unfound clue (a partial match of this clue if one is left)."""
    a = Attempt(room, hidden, clock, hz, prof["p_hit"])
    if not looks:
        a.looks = 10 ** 9
    tau = prof["tau"] * math.sqrt(room["S"] / 36.0)
    spots = room["spots"]
    for ci in range(room["n"]):
        if a.found[ci]:
            continue
        a.spend(prof["read"])
        if a.over(cap):
            return a.result()
        left = [s for s in room["cands"][ci] if s not in a.searched]
        while not a.found[ci]:
            if use_hint and prof["hint_at"] > 0 and not a.hint and (a.clock - a.t) < prof["hint_at"] * a.clock:
                a.hint = True
                target = hidden[ci]
                a.walk(target, prof["eff"], prof["detour"])
                a.search(target, prof["select"])
                break
            a.spend(rng.expovariate(len(left) / tau))
            if a.over(cap):
                return a.result()
            sid = rng.choice(left)
            if rng.random() < prof["slip"]:
                live = a.unfound_cands()
                pool = [s for s in spots if s["id"] not in a.searched and s["id"] not in live]
                part = [s for s in pool if s["role"] == "partial"
                        and any(s[x] == room["clues"][ci].get(x) for x in FORMS[room["clues"][ci]["form"]])]
                pool = part or pool
                if pool:
                    d = min(pool, key=lambda s: dist(a.pos, (s["x"], s["z"])))
                    a.walk(d["id"], prof["eff"], prof["detour"])
                    a.search(d["id"], prof["select"])
                    if a.over(cap):
                        return a.result()
            a.walk(sid, prof["eff"], prof["detour"])
            a.search(sid, prof["select"])
            left.remove(sid)
            if a.over(cap):
                return a.result()
    return a.result()


def play_bot(room, hidden, teleport=False):
    """A script with the clue rules: no reading, no noticing, no select tap, never off-clue; nearest unsearched
    candidate of any unfound clue next; walks straight at exactly WalkSpeed (or teleports)."""
    a = Attempt(room, hidden, 1e9, None, 0)
    while not all(a.found):
        live = [s for s in a.unfound_cands() if s not in a.searched]
        sid = min(live, key=lambda s: dist(a.pos, a.spot(s)))
        if teleport:
            a.pos = a.spot(sid)
        else:
            a.walk(sid, 1.0, 1.0)
        a.search(sid, 0.0)
    return a.result()


def play_brute(room, hidden, clock, cap=True, looks=True):
    """Ignores the clues and taps everything: nearest unsearched prop next, 0.5 s to pick it, normal walking."""
    a = Attempt(room, hidden, clock, None, 0)
    if not looks:
        a.looks = 10 ** 9
    p = PROFILES["normal"]
    while not all(a.found):
        live = [s["id"] for s in room["spots"] if s["id"] not in a.searched]
        sid = min(live, key=lambda s: dist(a.pos, a.spot(s)))
        a.spend(0.5)
        a.walk(sid, p["eff"], p["detour"])
        a.search(sid, p["select"])
        if a.over(cap):
            break
    return a.result()


def play_sweep(room, hidden, rng, clock, slip=0.05, hz=None):
    """A systematic human: walks to the nearest prop not yet glanced at, checks it against every unfound chip
    (0.35 s + 0.1 s per unfound clue [A]), and searches it only if it fits one (or, with prob slip, one that fits
    none). Walking, select and hazards as the normal profile."""
    p = PROFILES["normal"]
    a = Attempt(room, hidden, clock, hz, p["p_hit"])
    a.spend(p["read"] * room["n"])
    seen = set()
    while not all(a.found) and not a.over(True):
        rest = [s["id"] for s in room["spots"] if s["id"] not in seen]
        if not rest:
            break
        sid = min(rest, key=lambda s: dist(a.pos, a.spot(s)))
        seen.add(sid)
        a.walk(sid, p["eff"], p["detour"])
        a.spend(0.35 + 0.1 * (len(a.found) - sum(a.found)))
        if sid in a.unfound_cands() or rng.random() < slip:
            a.search(sid, p["select"])
    return a.result()


def stars(res, clock):
    found = res["found"]
    swift = found and res["t"] <= SWIFT_FRACTION * clock
    sharp = found and res["off"] <= SHARP_SLIPS and not res["hint"]
    return found, swift, sharp


def q(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    i = min(len(xs) - 1, max(0, int(math.ceil(p * len(xs))) - 1))
    return xs[i]


def ceil5(x):
    return int(5 * math.ceil(x / 5.0))


# ----------------------------------------------------------------------------------------------- parts
def part1():
    print("== Part 1: the generator (2000 rooms per chapter)")
    rng = random.Random(1)
    print(" ch  N k  S  | gen attempts mean/max | candidates exact k + disjoint | partial share of fillers | brute/clue spot ratio")
    for chapter in CHAPTERS + [DAILY]:
        atts, bad, partial, fill = [], 0, 0, 0
        for _ in range(2000):
            room, att = build_room(rng, chapter, near_door_first=(chapter[0] == 1))
            atts.append(att)
            for ci, c in enumerate(room["clues"]):
                m = [s["id"] for s in room["spots"] if matches(s, c)]
                if sorted(m) != sorted(room["cands"][ci]) or len(m) != room["k"]:
                    bad += 1
            for s in room["spots"]:
                if s["role"] != "cand":
                    fill += 1
                    partial += s["role"] == "partial"
        ch, n, k, S = chapter[:4]
        name = "daily" if ch == 0 else "%2d" % ch
        print(" %s %2d %d %2d  | %.3f / %d | %d rooms off | %.2f | %.2f" % (
            name, n, k, S, statistics.mean(atts), max(atts), bad, partial / max(1, fill), S / (n * k)))

    # The secret has no tell: over 120 000 hides of ONE fixed room, every candidate is picked 1/k of the time,
    # and the hidden spot's distance from the door has the same mean as all candidates'.
    room, _ = build_room(random.Random(7), CHAPTERS[7])
    hrng = random.Random(8)
    counts = {}
    for _ in range(120000):
        for ci, sid in enumerate(hide(hrng, room)):
            counts[(ci, sid)] = counts.get((ci, sid), 0) + 1
    exp = 120000 / room["k"]
    chi = sum((v - exp) ** 2 / exp for v in counts.values())
    dof = room["n"] * (room["k"] - 1)
    worst = max(abs(v - exp) / exp for v in counts.values())
    print(" uniform hiding, ch8 room, 120000 hides: chi-square %.1f on %d dof (p=0.001 critical about %d); worst cell off by %.2f%%"
          % (chi, dof, int(dof + 3.1 * math.sqrt(2 * dof) + 1), 100 * worst))

    # client-built parts in a room: the spot props, their tables and shelves, and the capped extras
    per_kind = {"box": 1, "basket": 3, "jar": 2, "vase": 2, "pot": 2, "cushion": 1, "bag": 2, "chest": 2}
    worst_parts = 0
    rng = random.Random(3)
    for chapter in CHAPTERS + [DAILY]:
        for _ in range(300):
            room, _ = build_room(rng, chapter)
            props = sum(per_kind[s["kind"]] for s in room["spots"])
            tables = math.ceil(sum(s["height"] == "table" for s in room["spots"]) / 3) * 2
            shelves = math.ceil(sum(s["height"] == "high" for s in room["spots"]) / 4) * 3
            worst_parts = max(worst_parts, props + tables + shelves)
    extras = {"screens": 4, "decor": 40, "critters": 10, "found items": 9 * 3, "hazard": 3, "lamps": 4}
    print(" client parts, worst of 3900 rooms: props+tables+shelves %d, + capped extras %s = %d"
          % (worst_parts, extras, worst_parts + sum(extras.values())))


def uncapped_times(chapter, prof, n, seed):
    rng = random.Random(seed)
    hrng = random.Random(seed + 1)
    ts = []
    for _ in range(n):
        room, _ = build_room(rng, chapter, near_door_first=(chapter[0] == 1))
        r = play_human(room, hide(hrng, room), prof, rng, 1e9, hz=None, cap=False, use_hint=False, looks=False)
        ts.append(r["t"])
    return ts


def part2():
    print("== Part 2: the chapters. Clocks from the normal profile's UNCAPPED clear time (hint off, no hazards)")
    derived = {}
    print(" ch | normal uncapped p50 / target quantile -> clock | first-try with clock+hint+hazards: found / swift / sharp  (fast; normal; slow)")
    for chapter in CHAPTERS:
        ch = chapter[0]
        ts = uncapped_times(chapter, PROFILES["normal"], 2000, 100 + ch)
        tq = CLOCK_TARGET.get(ch, 0.90)
        clock = ceil5(q(ts, tq))
        derived[ch] = clock
        row = []
        for name in ("fast", "normal", "slow"):
            rng = random.Random(200 + ch)
            hrng = random.Random(300 + ch)
            f = sw = sh = ool = 0
            N = 2000
            for _ in range(N):
                room, _ = build_room(rng, chapter, near_door_first=(ch == 1))
                hz = HazardClock(rng)
                hz.exposed = rng.uniform(0, HZ_MIN)  # mid-career: a hazard may be close
                r = play_human(room, hide(hrng, room), PROFILES[name], rng, clock, hz=hz)
                a, b, c = stars(r, clock)
                f += a
                sw += b
                sh += c
                ool += r["out_of_looks"]
            row.append("%.2f/%.2f/%.2f (%d out of looks)" % (f / N, sw / N, sh / N, ool))
        print(" %2d | %5.1f s / p%d %5.1f -> %3d s | %s" % (ch, statistics.median(ts), round(tq * 100), q(ts, tq), clock, "; ".join(row)))

    if derived != CLOCKS:
        raise SystemExit("CLOCKS differ from the derivation: %s" % derived)
    print(" CLOCKS equals the derivation")
    print(" the bot (script with the rules), the teleporting bot, and the tap-everything player (mean s with unlimited looks;")
    print(" 'solves' = P(found within the clock AND the looks, N*k+%d)" % LOOKS_SLACK)
    for chapter in CHAPTERS:
        ch = chapter[0]
        rng = random.Random(400 + ch)
        hrng = random.Random(500 + ch)
        b, tb, br, brf, srch_b, srch_n = [], [], [], 0, [], []
        for _ in range(500):
            room, _ = build_room(rng, chapter, near_door_first=(ch == 1))
            h = hide(hrng, room)
            rb = play_bot(room, h)
            b.append(rb["t"])
            srch_b.append(rb["searches"])
            tb.append(play_bot(room, h, teleport=True)["t"])
            rr = play_brute(room, h, CLOCKS[ch], cap=False, looks=False)
            br.append(rr["t"])
            brf += play_brute(room, h, CLOCKS[ch])["found"]
            rn = play_human(room, h, PROFILES["normal"], rng, 1e9, cap=False, use_hint=False)
            srch_n.append(rn["searches"] - rn["off"])
        print(" %2d | bot %5.1f, teleport %5.1f, brute %5.1f (solves %.2f) | on-clue searches: bot %.2f, normal %.2f, expected N(k+1)/2 = %.1f"
              % (ch, statistics.mean(b), statistics.mean(tb), statistics.mean(br), brf / 500,
                 statistics.mean(srch_b), statistics.mean(srch_n), chapter[1] * (chapter[2] + 1) / 2))
    sweep_rows()


def sweep_rows():
    print(" sensitivity: the SWEEPER (systematic walk, 0.35 s + 0.1 s per unfound clue to check each prop, search what fits)")
    for chapter in CHAPTERS:
        ch = chapter[0]
        rng = random.Random(800 + ch)
        hrng = random.Random(850 + ch)
        ts, f, sw, sh = [], 0, 0, 0
        for _ in range(500):
            room, _ = build_room(rng, chapter, near_door_first=(ch == 1))
            r = play_sweep(room, hide(hrng, room), rng, CLOCKS[ch])
            ts.append(r["t"])
            a, b, c = stars(r, CLOCKS[ch])
            f += a
            sw += b
            sh += c
        print(" %2d | p50 %5.1f s | found %.2f, swift %.2f, sharp %.2f" % (ch, statistics.median(ts), f / 500, sw / 500, sh / 500))


def play_career(prof, rng, hrng, gold=True, cap_minutes=600.0, sweep=False):
    """Book One from a fresh join. Returns the minute each chapter was first cleared, the minute the 36 stars
    were complete (stars are kept per chapter once earned), the hazards met and the first find."""
    hz = HazardClock(rng)
    t = SESSION_START
    exposed_start = 0.0
    clear_at = {}
    star_got = {ch: [False, False, False] for ch in CLOCKS}
    first_find = None
    ch1_clear = None
    attempts = 0
    for chapter in CHAPTERS:
        ch = chapter[0]
        intro = INTRO_FIRST
        while True:
            attempts += 1
            room, _ = build_room(rng, chapter, near_door_first=(ch == 1))
            t += intro + MOVE
            intro = INTRO_RETRY
            if sweep:
                r = play_sweep(room, hide(hrng, room), rng, CLOCKS[ch], hz=hz)
            else:
                r = play_human(room, hide(hrng, room), prof, rng, CLOCKS[ch], hz=hz)
            if first_find is None and r["first"] is not None:
                first_find = t + r["first"]
            t += r["spent"] + CLEAR_CARD
            s = stars(r, CLOCKS[ch])
            star_got[ch] = [x or y for x, y in zip(star_got[ch], s)]
            if r["found"]:
                clear_at[ch] = t / 60.0
                if ch == 1:
                    ch1_clear = t
                break
    brag_hz, brag_hits, brag_exposed = hz.count, hz.hits, hz.exposed
    gold_at = None
    if gold:
        while t / 60.0 < cap_minutes:
            missing = [c for c in CHAPTERS if not all(star_got[c[0]])]
            if not missing:
                gold_at = t / 60.0
                break
            for chapter in missing:
                ch = chapter[0]
                room, _ = build_room(rng, chapter)
                t += INTRO_RETRY + MOVE
                if sweep:
                    r = play_sweep(room, hide(hrng, room), rng, CLOCKS[ch], hz=hz)
                else:
                    r = play_human(room, hide(hrng, room), prof, rng, CLOCKS[ch], hz=hz)
                t += r["spent"] + CLEAR_CARD
                star_got[ch] = [x or y for x, y in zip(star_got[ch], stars(r, CLOCKS[ch]))]
    return {"clear_at": clear_at, "gold_at": gold_at, "hazards": brag_hz, "hits": brag_hits,
            "exposed": brag_exposed, "first_find": first_find, "ch1_clear": ch1_clear, "brag_t": clear_at[15] * 60.0,
            "attempts": attempts}


def part3():
    print("== Part 3: pacing. Cumulative minutes from join (cards, moves, retries and hazards included)")
    for name in ("fast", "normal", "slow"):
        rng = random.Random(600)
        hrng = random.Random(601)
        runs = [play_career(PROFILES[name], rng, hrng) for _ in range(1000)]
        brag = [r["clear_at"][15] for r in runs]
        gold = [r["gold_at"] if r["gold_at"] is not None else 600.0 for r in runs]
        never = sum(r["gold_at"] is None for r in runs)
        bands = []
        for lo, hi in BANDS:
            mins = [r["clear_at"][hi] - (r["clear_at"][lo - 1] if lo > 1 else 0.0) for r in runs]
            bands.append("%.1f" % statistics.median(mins))
        print(" %-6s BOOK ONE SOLVED p10 %.1f / p50 %.1f / p90 %.1f min | attempts to clear the book p50 %d | minutes per band (3 chapters each) %s"
              % (name, q(brag, 0.1), statistics.median(brag), q(brag, 0.9),
                 statistics.median([r["attempts"] for r in runs]), " / ".join(bands)))
        print("        Gold Book (45 stars) p50 %.1f min (p90 %.1f; %d of 1000 not by 600 min) | first find p50 %.1f s, chapter 1 cleared p50 %.1f s from join"
              % (statistics.median(gold), q(gold, 0.9), never,
                 statistics.median([r["first_find"] for r in runs]), statistics.median([r["ch1_clear"] for r in runs])))
        play_min = [r["brag_t"] / 60.0 for r in runs]
        hz_per = [r["hazards"] for r in runs]
        print("        hazards on the way to BOOK ONE SOLVED: p50 %d; one per %.2f min of play (%d hit of %d)"
              % (statistics.median(hz_per), statistics.median(play_min) / max(1, statistics.median(hz_per)),
                 sum(r["hits"] for r in runs), sum(hz_per)))
    sweep_career()


def sweep_career():
    rng = random.Random(610)
    hrng = random.Random(611)
    runs = [play_career(PROFILES["normal"], rng, hrng, sweep=True) for _ in range(500)]
    brag = [r["clear_at"][15] for r in runs]
    gold = [r["gold_at"] if r["gold_at"] is not None else 600.0 for r in runs]
    print(" sweeper  BOOK ONE SOLVED p10 %.1f / p50 %.1f / p90 %.1f min | Gold Book p50 %.1f min"
          % (q(brag, 0.1), statistics.median(brag), q(brag, 0.9), statistics.median(gold)))


def part4():
    print("== Part 4: hazard rate on a normal player's way to BOOK ONE SOLVED, per minute of PLAY (rooms + cards + moves)")
    for lo, hi in ((80, 120), (100, 140), (120, 180)):
        global HZ_MIN, HZ_MAX
        HZ_MIN, HZ_MAX = float(lo), float(hi)
        rng = random.Random(700)
        hrng = random.Random(701)
        runs = [play_career(PROFILES["normal"], rng, hrng, gold=False) for _ in range(500)]
        per_min = [r["brag_t"] / 60.0 / max(1, r["hazards"]) for r in runs]
        share = [r["exposed"] / r["brag_t"] for r in runs]
        nm = [r["brag_t"] / 60.0 / max(1, r["hazards"] - r["hits"]) for r in runs]
        print(" interval %d-%d s exposed: one hazard per %.2f min of play (p10 %.2f, p90 %.2f), one near-miss (dodged) per %.2f min; exposed share of play %.2f"
              % (lo, hi, statistics.median(per_min), q(per_min, 0.1), q(per_min, 0.9), statistics.median(nm),
                 statistics.median(share)))
    HZ_MIN, HZ_MAX = 100.0, 140.0


def part5():
    print("== Part 5: the Daily Case (6 items, k 4, 44 spots: chapter 7's size)")
    ts = uncapped_times(DAILY, PROFILES["normal"], 3000, 900)
    clock = ceil5(q(ts, 0.98))
    if clock != DAILY_CLOCK:
        raise SystemExit("DAILY_CLOCK is %d, the model derives %d" % (DAILY_CLOCK, clock))
    print(" normal uncapped p50 %.1f s, p98 %.1f -> clock %d s" % (statistics.median(ts), q(ts, 0.98), clock))
    for name in ("fast", "normal", "slow"):
        rng = random.Random(910)
        hrng = random.Random(911)
        f, mins = 0, []
        for _ in range(3000):
            room, _ = build_room(rng, DAILY)
            r = play_human(room, hide(hrng, room), PROFILES[name], rng, clock, hz=HazardClock(rng))
            f += r["found"]
            mins.append((r["spent"] + INTRO_FIRST + MOVE + CLEAR_CARD) / 60.0)
        print(" %-6s solves on the first attempt %.3f; one attempt takes p50 %.1f min" % (name, f / 3000, statistics.median(mins)))
    rng = random.Random(920)
    hrng = random.Random(921)
    br = 0
    bt = []
    for _ in range(1000):
        room, _ = build_room(rng, DAILY)
        h = hide(hrng, room)
        br += play_brute(room, h, clock)["found"]
        bt.append(play_bot(room, h)["t"])
    print(" tap-everything solves %.3f; the rules bot takes %.1f s mean" % (br / 1000, statistics.mean(bt)))


def part6():
    print("== Part 6: the board value and the store text")
    SCALE = 2e9
    days = 3653  # ten years of Daily Cases
    top = (15 + days) * SCALE + (SCALE - 1791331200)  # reached 2026-10-07 at the earliest
    print(" Cases Solved after ten years: %d; encoded %.6e < 2^53 = %.6e: %s" % (15 + days, top, 2.0 ** 53, top < 2.0 ** 53))
    try:
        with open(__file__.replace("model.py", "store.txt"), encoding="ascii") as f:
            text = f.read().rstrip("\n")
        print(" store text: %d characters, ASCII only (read as ascii)" % len(text))
    except FileNotFoundError:
        print(" store text: design/store.txt missing")


def pause_trial(chapter, rng, policy, rule, p_pause, slip=0.0):
    """Looks only, plus a crude clock for the brute (2.4 s a search, 3 s a pause). A pause re-dresses the room on
    resume: every prop moves, every unfound item gets a fresh clue and a fresh hiding spot.
    rule 'keep' (the design): item i's new clue fits exactly as many props as i had UNSEARCHED candidates, and the
    looks are unchanged. rule 'reset' (rejected): every unfound item gets k candidates again and the looks are
    reset to N_rem * k + LOOKS_SLACK. rule 'never': the brute never pauses (baseline).
    policy 'careful': searches an unsearched candidate of an unfound clue (with prob slip, a prop that fits none)
    and pauses with prob p_pause before a search. policy 'brute': any unsearched prop; pauses whenever its looks
    drop below what the remaining candidates need."""
    ch, n, k, S = chapter[:4]
    looks = n * k + LOOKS_SLACK
    unfound = n
    left = [k] * n                       # unsearched candidates per item (0 = found)
    others = S - n * k                   # props that fit no unfound clue and are unsearched
    t, clock, pauses = 0.0, CLOCKS.get(ch, DAILY_CLOCK), 0
    while unfound > 0:
        if looks <= 0:
            return False, pauses
        need = sum(left)
        pause = (policy == "careful" and rng.random() < p_pause) or                 (policy == "brute" and rule != "never" and looks < need and pauses < 200)
        if pause:
            pauses += 1
            t += 3.0
            if rule == "reset":
                left = [k if x > 0 else 0 for x in left]
                looks = unfound * k + LOOKS_SLACK
            others = S - sum(left)       # the re-dress refills the room with fresh, unsearched props
            continue
        looks -= 1
        t += 2.4
        if policy == "brute" and t > clock:
            return False, pauses
        cand = sum(left)
        if policy == "careful":
            if rng.random() < slip and others > 0:
                others -= 1
                continue
            r = rng.randrange(cand)
        else:
            r = rng.randrange(cand + others)
            if r >= cand:
                others -= 1
                continue
        for i in range(n):
            if r < left[i]:
                break
            r -= left[i]
        if rng.random() < 1.0 / left[i]:  # the hiding spot is uniform among item i's unsearched candidates
            others += left[i] - 1         # its other unsearched candidates now fit no unfound clue
            left[i] = 0
            unfound -= 1
        else:
            left[i] -= 1
    return True, pauses


def part7():
    print("== Part 7: the pause rule (re-dress on resume) against the looks budget")
    for chapter in (CHAPTERS[0], CHAPTERS[6], CHAPTERS[14], DAILY):
        name = "daily" if chapter[0] == 0 else "ch%d" % chapter[0]
        rng = random.Random(1000 + chapter[0])
        careful = sum(not pause_trial(chapter, rng, "careful", "keep", 0.15)[0] for _ in range(20000))
        sloppy = sum(not pause_trial(chapter, rng, "careful", "keep", 0.15, slip=0.07)[0] for _ in range(20000))
        sloppy0 = sum(not pause_trial(chapter, rng, "careful", "keep", 0.0, slip=0.07)[0] for _ in range(20000))
        never = sum(pause_trial(chapter, rng, "brute", "never", 0.0)[0] for _ in range(5000)) / 5000
        keep = sum(pause_trial(chapter, rng, "brute", "keep", 0.0)[0] for _ in range(5000)) / 5000
        reset = sum(pause_trial(chapter, rng, "brute", "reset", 0.0)[0] for _ in range(5000)) / 5000
        print(" %-5s careful, a pause before ~1 search in 7: out of looks %d of 20000; with 7%% slips %d (never pausing: %d)"
              % (name, careful, sloppy, sloppy0))
        print("        tap-everything solves %.3f never pausing, %.3f pausing to refill under the design rule, %.3f if a pause reset clues and looks"
              % (never, keep, reset))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--part", type=int, default=0)
    args = ap.parse_args()
    parts = [part1, part2, part3, part4, part5, part6, part7]
    for i, f in enumerate(parts, 1):
        if args.part in (0, i):
            f()
