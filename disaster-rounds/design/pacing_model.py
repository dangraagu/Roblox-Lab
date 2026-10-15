"""pacing_model.py -- DESIGN-TIME model for Disaster Rounds. Not game code, never shipped.

Every number in ../DESIGN.md marked "(m)" comes from this file. It carries its own copy of the design
numbers (the CFG block below mirrors DESIGN.md section 2). When the game is built,
tests/Pacing.spec.luau and the robloxemu checks must re-measure the same quantities against the REAL
src/shared/Config.luau and the real pure modules; this file is then retired, not kept in sync.

Why Python: on 2026-10-07 the luau CLI directory in the session scratchpad was empty and no luau.exe
existed on the machine; downloading one needs the owner's go. The model is arithmetic and Monte Carlo,
so the language does not matter; the build re-measures everything in Luau.

Run (from D:\\Claude\\Roblox\\disaster-rounds):   py -3 design/pacing_model.py           (full, about 5 min)
                                                 py -3 design/pacing_model.py quick     (fewer samples, about 1 min)

What it simulates
  * MapGen: the 13 x 13 terraced island generator of DESIGN.md section 3.1, with every validation rule;
  * the four disasters geometrically, second by second (dt 0.05 s), against players who react after a
    sampled reaction time, sometimes lapse, and walk 16 studs/s to the nearest safe point;
  * the per-player aimed rings (the Heat strikes) on open ground and on the crowded flood plateau;
  * sessions: join at a random phase of the 88 s round cycle, practice drop-in, rounds with the
    measured per-round survival, streak -> Heat, lifetime survivals -> bands, Codex, best streak.
"""

import math
import random
import statistics
import sys

QUICK = len(sys.argv) > 1 and sys.argv[1] == "quick"
SEED = 20261007

# ------------------------------------------------------------------------------------------- numbers
CFG = {
    "WalkSpeed": 16.0,
    "PlayerRadius": 1.5,
    "LatencySeconds": 0.10,      # one-way: the server sees the root this late
    "SampleSeconds": 0.10,       # server tick for hit tests (10 Hz)
    "LagGrace": 0.20,            # a hit needs the root inside at EVERY server sample in [T, T + 0.2]
    # round cycle
    "Intermission": 20.0, "Drop": 4.0, "Disaster": 60.0, "Outro": 4.0,
    "JumpInWindow": 50.0,        # practice drop-in allowed from the drop until 10 s before the disaster ends
    # island
    "N": 13, "Cell": 8.0, "LevelStuds": 4.0, "MaxLevel": 4,
    "MinHighCells": 18,          # level >= 3 cells (dry after the last flood rise)
    "FloodReachStuds": 100.0,
    "MaxPlayers": 8,
    "AmbientMean": 75.0,         # lobby stray-debris clock: one per 60-90 s of Lookout time (mean 75)
    # aimed rings (Heat strikes)
    "RingHit": 3.0, "RingTelegraph": 3.0, "RingPass": 0.6, "FirstRingAfter": 5.0, "RingJitter": 0.2,
    "MeteorIntervals": [6.0, 5.0, 4.2, 3.5, 3.0, 2.5],      # heat 0..5, Meteor Shower
    "OtherIntervals": [15.0, 12.0, 9.5, 7.5, 6.0, 5.0],     # heat 0..5, Flood / Tornado / Quake
    "MaxRingCoverage": 0.25,
    "ExitStuds": 7.0,            # a ring is placed only if everyone it covers can stand outside all rings within 7 studs     # live rings never cover more than this share of the walkable area
    "HeatPerStreak": 2,          # heat = min(5, floor(streak / 2))
    "MaxHeat": 5,
    # flood
    "FloodRises": 3, "FloodWarn": 9.0, "FloodRise": 4.0, "FloodFirst": 3.0, "FloodGrace": 0.6,
    "FloodPathFactor": 1.25,     # turns and jumps make a walked path 25 % longer than cell-centre steps
    # tornado
    "FunnelHit": 5.0, "FunnelSpeed": 9.0, "FunnelHorizon": 4.0, "FunnelStart": 3.0,
    "FunnelTurnDeg": 30.0, "FunnelChase": 0.5, "FunnelRetarget": 5.0,
    # quake
    "QuakeFirst": 3.0, "QuakeEvery": 6.0, "QuakeCrack": 3.0, "QuakeBatch": 10, "QuakeCap": 0.45,
    "QuakeOnPlayer": 0.6,
}

# The human part, written down instead of hidden. Reaction: lognormal, median `react`, sigma 0.35.
# A lapse is a threat noticed late (1.0-4.0 s more for a ring, 2-8 s for a flood banner).
PROFILES = {
    "fast":   {"react": 0.55, "lapseRing": 0.008, "lapseBig": 0.005},
    "normal": {"react": 0.80, "lapseRing": 0.020, "lapseBig": 0.010},
    "slow":   {"react": 1.20, "lapseRing": 0.035, "lapseBig": 0.020},
    # the fairness floor: a scripted dodger. If THIS player is ever hit, the disaster is unfair.
    "bot":    {"react": 0.60, "lapseRing": 0.0, "lapseBig": 0.0, "fixed": True},
}

# bands: lifetime counted survivals at which bands 2..6 start (band 1 at 0)
BANDS = [2, 6, 12, 21, 100]
BAND_NAMES = ["Calm Cove", "Windy Point", "Storm Coast", "Ember Isles", "Falling Sky", "New Dawn"]
KINDS = ["meteor", "flood", "tornado", "quake"]


def react_time(rng, prof, lapse_key, lapse_lo, lapse_hi):
    if prof.get("fixed"):
        return prof["react"]
    r = prof["react"] * math.exp(rng.gauss(0.0, 0.35))
    if rng.random() < prof[lapse_key]:
        r += rng.uniform(lapse_lo, lapse_hi)
    return r


def heat_of(streak):
    return min(CFG["MaxHeat"], streak // CFG["HeatPerStreak"])


# ------------------------------------------------------------------------------------------- MapGen
def gen_map(rng):
    """-> (levels[i][j], tries). Max of cones, clipped to [0, 4] and to the distance from the edge."""
    N = CFG["N"]
    tries = 0
    while True:
        tries += 1
        peaks = []
        for _ in range(rng.choice([1, 2, 2, 3])):
            peaks.append((rng.randint(4, N - 5), rng.randint(4, N - 5), rng.choice([4, 5, 5, 6]),
                          rng.uniform(0.55, 0.95)))
        lv = [[0] * N for _ in range(N)]
        for i in range(N):
            for j in range(N):
                best = 0
                for (pi, pj, h, s) in peaks:
                    v = h - math.floor(s * math.hypot(i - pi, j - pj))
                    if v > best:
                        best = v
                edge = min(i, j, N - 1 - i, N - 1 - j)
                lv[i][j] = max(0, min(CFG["MaxLevel"], best, edge))
        ok, _ = validate_map(lv)
        if ok:
            return lv, tries


def neighbours(i, j, N):
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        a, b = i + di, j + dj
        if 0 <= a < N and 0 <= b < N:
            yield a, b


def flood_escape(lv, rise):
    """BFS distance (cells) from every level == rise-1 cell to the nearest level >= rise cell, walking
    only on cells of level >= rise-1 (lower ones are already under water). None = unreachable."""
    N = len(lv)
    INF = 10 ** 9
    dist = [[INF] * N for _ in range(N)]
    q = []
    for i in range(N):
        for j in range(N):
            if lv[i][j] >= rise:
                dist[i][j] = 0
                q.append((i, j))
    k = 0
    while k < len(q):
        i, j = q[k]
        k += 1
        for a, b in neighbours(i, j, N):
            if lv[a][b] >= rise - 1 and dist[a][b] == INF and abs(lv[a][b] - lv[i][j]) <= 1:
                dist[a][b] = dist[i][j] + 1
                q.append((a, b))
    out = {}
    for i in range(N):
        for j in range(N):
            if lv[i][j] == rise - 1:
                out[(i, j)] = None if dist[i][j] == INF else dist[i][j]
    return out, dist


def validate_map(lv):
    N = len(lv)
    for i in range(N):
        for j in range(N):
            for a, b in neighbours(i, j, N):
                if abs(lv[i][j] - lv[a][b]) > 1:
                    return False, "step > 1 level"
    high = sum(1 for i in range(N) for j in range(N) if lv[i][j] >= 3)
    if high < CFG["MinHighCells"]:
        return False, "high cells %d" % high
    for rise in range(1, CFG["FloodRises"] + 1):
        esc, _ = flood_escape(lv, rise)
        for d in esc.values():
            if d is None:
                return False, "flood trap"
            if d * CFG["Cell"] + CFG["Cell"] / 2 > CFG["FloodReachStuds"] / CFG["FloodPathFactor"]:
                return False, "flood escape too long"
    return True, None


def map_stats(n, rng):
    tries, highs, per_level, worst = [], [], [0] * 5, []
    esc_studs = {1: [], 2: [], 3: []}
    for _ in range(n):
        lv, t = gen_map(rng)
        tries.append(t)
        N = len(lv)
        highs.append(sum(1 for i in range(N) for j in range(N) if lv[i][j] >= 3))
        for i in range(N):
            for j in range(N):
                per_level[lv[i][j]] += 1
        w = 0
        for rise in (1, 2, 3):
            esc, _ = flood_escape(lv, rise)
            for d in esc.values():
                s = d * CFG["Cell"] + CFG["Cell"] / 2
                esc_studs[rise].append(s)
                w = max(w, s)
        worst.append(w)
    tot = sum(per_level)
    return {
        "tries_mean": statistics.mean(tries), "tries_max": max(tries),
        "accept_rate": n / sum(tries),
        "high_min": min(highs), "high_med": statistics.median(highs), "high_max": max(highs),
        "level_share": [round(x / tot, 3) for x in per_level],
        "worst_escape_max": max(worst), "worst_escape_med": statistics.median(worst),
        "esc_p90": {r: pct(v, 0.9) for r, v in esc_studs.items()},
        "esc_med": {r: pct(v, 0.5) for r, v in esc_studs.items()},
    }


def pct(v, q):
    if not v:
        return 0.0
    s = sorted(v)
    return s[min(len(s) - 1, int(q * (len(s) - 1) + 0.5))]


# --------------------------------------------------------------------------------- shared geometry
class Mover:
    """A player: true position, a target, a short history so the server can see it LatencySeconds late."""

    def __init__(self, x, z):
        self.x, self.z = x, z
        self.tx, self.tz = None, None
        self.hist = []  # (t, x, z)
        self.alive = True

    def step(self, t, dt):
        if self.tx is not None:
            dx, dz = self.tx - self.x, self.tz - self.z
            d = math.hypot(dx, dz)
            m = CFG["WalkSpeed"] * dt
            if d <= m:
                self.x, self.z = self.tx, self.tz
                self.tx = self.tz = None
            else:
                self.x += dx / d * m
                self.z += dz / d * m
        self.hist.append((t, self.x, self.z))
        if len(self.hist) > 40:
            del self.hist[0]

    def seen(self, t):
        """Position the server sees at time t (the true position LatencySeconds earlier)."""
        want = t - CFG["LatencySeconds"]
        best = self.hist[0] if self.hist else (t, self.x, self.z)
        for h in self.hist:
            if h[0] <= want + 1e-9:
                best = h
        return best[1], best[2]


def nearest_free(x, z, blocked, bounds, margin=0.8, timed=None, now=0.0):
    """Nearest point to (x, z) outside every blocked disk (cx, cz, r), inside bounds. 32 dirs x 0.5 studs.
    timed: optional list of (cx, cz, r, impact). A candidate is refused when walking straight to it at
    WalkSpeed would put the walker inside one of those rings around its impact (a smart dodger never
    crosses a ring as it lands)."""
    if not any(math.hypot(x - cx, z - cz) < r + margin for (cx, cz, r) in blocked):
        return x, z
    for k in range(1, 61):
        d = 0.5 * k
        for a in range(32):
            ang = a * math.pi / 16
            px, pz = x + math.cos(ang) * d, z + math.sin(ang) * d
            if not bounds(px, pz):
                continue
            if any(math.hypot(px - cx, pz - cz) < r + margin for (cx, cz, r) in blocked):
                continue
            if timed and crosses_landing(x, z, px, pz, timed, now):
                continue
            return px, pz
    return x, z


def crosses_landing(x0, z0, x1, z1, timed, now):
    L = math.hypot(x1 - x0, z1 - z0)
    T = L / CFG["WalkSpeed"]
    for (cx, cz, r, impact) in timed:
        lo, hi = impact - 0.15 - now, impact + 0.25 - now
        if hi < 0:
            continue
        # sample the walk every 0.05 s inside [lo, hi]; after T the walker stands at the end point
        s = max(0.0, lo)
        while s <= hi:
            f = min(1.0, s / T) if T > 0 else 1.0
            px, pz = x0 + (x1 - x0) * f, z0 + (z1 - z0) * f
            if math.hypot(px - cx, pz - cz) < r:
                return True
            s += 0.05
    return False


def exit_distance(x, z, disks, bounds, margin=0.8):
    """How far a player at (x, z) must walk to stand outside every disk. 99 = no exit within 30 studs."""
    fx, fz = nearest_free(x, z, disks, bounds, margin)
    if any(math.hypot(fx - cx, fz - cz) < r + margin for (cx, cz, r) in disks):
        return 99.0
    return math.hypot(fx - x, fz - z)


# ------------------------------------------------------------------------------------- aimed rings
def ring_round(rng, prof, intervals, heat, n_players=1, half=40.0, cap_area=None, t_end=60.0, dt=0.05):
    """One round of aimed rings only. Returns (list of survived flags per player, rings per player).
    half: the walkable square is [-half, half]^2. cap_area: walkable area used by the coverage cap."""
    ring_r = CFG["RingHit"] + CFG["PlayerRadius"]
    ring_area = math.pi * ring_r * ring_r
    area = cap_area if cap_area else (2 * half) ** 2
    max_live = max(1, int(CFG["MaxRingCoverage"] * area / ring_area))
    bounds = lambda px, pz: -half <= px <= half and -half <= pz <= half
    ps = []
    for k in range(n_players):
        for _ in range(200):
            x, z = rng.uniform(-half + 2, half - 2), rng.uniform(-half + 2, half - 2)
            if all(math.hypot(x - p.x, z - p.z) > 4 for p in ps):
                break
        ps.append(Mover(x, z))
    iv = intervals[heat]
    nxt = [CFG["FirstRingAfter"] + rng.uniform(0, iv) for _ in ps]
    rings = []  # dict(x, z, impact, end, seenAt[list per player])
    count = [0] * n_players
    t = 0.0
    while t < t_end + 1e-9:
        live = [r for r in rings if r["end"] > t]
        if not live and all(p.tx is None for p in ps):
            soon = min([n for k, n in enumerate(nxt) if ps[k].alive] or [t_end + 1])
            if soon > t + dt:
                t += math.floor((soon - t) / dt) * dt
                if t > t_end:
                    break
                continue
        # spawn
        for k, p in enumerate(ps):
            if not p.alive:
                continue
            if t >= nxt[k]:
                if t + CFG["RingTelegraph"] > t_end:
                    nxt[k] = 1e9
                    continue
                if len(live) >= max_live:
                    nxt[k] = t + dt  # deferred: the cap is full
                    continue
                sx, sz = p.seen(t)
                # fairness: every player the new ring covers keeps an exit within ExitStuds
                disks = [(r["x"], r["z"], ring_r) for r in live] + [(sx, sz, ring_r)]
                trapped = False
                for q in ps:
                    if q.alive and math.hypot(q.x - sx, q.z - sz) < ring_r + 1.5:
                        if exit_distance(q.x, q.z, disks, bounds) > CFG["ExitStuds"]:
                            trapped = True
                            break
                if trapped:
                    nxt[k] = t + 0.25
                    continue
                r = {"x": sx, "z": sz, "impact": t + CFG["RingTelegraph"],
                     "end": t + CFG["RingTelegraph"] + CFG["RingPass"],
                     "seenAt": [t + react_time(rng, prof, "lapseRing", 1.0, 4.0) for _ in ps], "judged": False}
                rings.append(r)
                live.append(r)
                count[k] += 1
                nxt[k] = t + iv * rng.uniform(1 - CFG["RingJitter"], 1 + CFG["RingJitter"])
        # react
        for k, p in enumerate(ps):
            if not p.alive:
                continue
            seen_r = [r for r in live if r["seenAt"][k] <= t and r["impact"] + 0.25 > t]
            noticed = [(r["x"], r["z"], ring_r) for r in seen_r]
            if not noticed:
                continue
            timed = [(r["x"], r["z"], ring_r, r["impact"]) for r in seen_r]
            gx, gz = (p.tx, p.tz) if p.tx is not None else (p.x, p.z)
            bad_goal = any(math.hypot(gx - cx, gz - cz) < rr + 0.3 for (cx, cz, rr) in noticed)
            if not bad_goal and p.tx is not None:
                bad_goal = crosses_landing(p.x, p.z, p.tx, p.tz, timed, t)
            if bad_goal:
                fx, fz = nearest_free(p.x, p.z, noticed, bounds, timed=timed, now=t)
                if (fx, fz) != (p.x, p.z):
                    p.tx, p.tz = fx, fz
        for p in ps:
            if p.alive:
                p.step(t, dt)
        # judge: at impact + LagGrace, every server sample in [impact, impact + LagGrace] inside -> hit
        for r in live:
            if not r["judged"] and t >= r["impact"] + CFG["LagGrace"] - 1e-9:
                r["judged"] = True
                for p in ps:
                    if not p.alive:
                        continue
                    inside = True
                    s = r["impact"]
                    while s <= r["impact"] + CFG["LagGrace"] + 1e-9:
                        sx, sz = seen_at(p, s)  # what the server saw at sample time s
                        if math.hypot(sx - r["x"], sz - r["z"]) > ring_r:
                            inside = False
                            break
                        s += CFG["SampleSeconds"]
                    if inside:
                        p.alive = False
        t += dt
    return [p.alive for p in ps], count


def seen_at(p, s):
    """Server-observed position at server time s = true position at s - latency (from the history)."""
    want = s - CFG["LatencySeconds"]
    best = p.hist[0]
    for h in p.hist:
        if h[0] <= want + 1e-9:
            best = h
    return best[1], best[2]


def ring_survival(rng, prof, intervals, heat, rounds, **kw):
    ok, n, rings = 0, 0, 0
    for _ in range(rounds):
        alive, cnt = ring_round(rng, prof, intervals, heat, **kw)
        ok += sum(1 for a in alive if a)
        n += len(alive)
        rings += sum(cnt)
    return ok / n, rings / n


# ------------------------------------------------------------------------------------------- flood
def flood_round(rng, prof, lv):
    """Global part of a flood round for one player dropped on a random level >= 1 cell. -> survived, threats."""
    N = len(lv)
    cells = [(i, j) for i in range(N) for j in range(N) if lv[i][j] >= 1]
    i, j = rng.choice(cells)
    threats = 0
    avail = CFG["FloodWarn"] + CFG["FloodRise"] / 2 + CFG["FloodGrace"]  # water passes a cell top mid-rise
    for rise in range(1, CFG["FloodRises"] + 1):
        if lv[i][j] >= rise:
            continue
        threats += 1
        _, dist = flood_escape(lv, rise)
        d = dist[i][j]
        studs = d * CFG["Cell"] + CFG["Cell"] / 2
        need = react_time(rng, prof, "lapseBig", 2.0, 8.0) + studs * CFG["FloodPathFactor"] / CFG["WalkSpeed"]
        if need > avail:
            return False, threats
        # walk to the nearest dry cell (follow the BFS gradient)
        while dist[i][j] > 0:
            for a, b in neighbours(i, j, N):
                if lv[a][b] >= rise - 1 and dist[a][b] == dist[i][j] - 1 and abs(lv[a][b] - lv[i][j]) <= 1:
                    i, j = a, b
                    break
    return True, threats


# ----------------------------------------------------------------------------------------- tornado
def tornado_round(rng, prof, n_players, dt=0.05):
    """Global part of a tornado round. -> list of (survived, threats) per player."""
    half = CFG["N"] * CFG["Cell"] / 2 - 2.0
    zone = CFG["FunnelHit"] + CFG["PlayerRadius"]
    bounds = lambda px, pz: -half <= px <= half and -half <= pz <= half
    ps = []
    for _ in range(n_players):
        for _ in range(200):
            x, z = rng.uniform(-half + 4, half - 4), rng.uniform(-half + 4, half - 4)
            if all(math.hypot(x - p.x, z - p.z) > 10 for p in ps):
                break
        ps.append(Mover(x, z))
    # path: a list of (t, x, z) at 0.25 s resolution, appended up to now + horizon
    side = rng.randrange(4)
    u = rng.uniform(-half * 0.6, half * 0.6)
    sx, sz = [(-half, u), (half, u), (u, -half), (u, half)][side]
    heading = math.atan2(-sz, -sx) + rng.uniform(-0.4, 0.4)
    path = [(CFG["FunnelStart"], sx, sz)]
    target = None
    next_retarget = 0.0
    seg = 0.25
    turn = math.radians(CFG["FunnelTurnDeg"]) * seg  # per second -> per 0.25 s step

    def extend(upto):
        nonlocal heading, target, next_retarget
        while path[-1][0] < upto:
            t0, x0, z0 = path[-1]
            if target is None or t0 >= next_retarget or math.hypot(target[0] - x0, target[1] - z0) < 8:
                alive = [p for p in ps if p.alive]
                if alive and rng.random() < CFG["FunnelChase"]:
                    q = rng.choice(alive)
                    target = q.seen(t0 - CFG["FunnelHorizon"]) if q.hist else (q.x, q.z)
                else:
                    target = (rng.uniform(-half + 6, half - 6), rng.uniform(-half + 6, half - 6))
                next_retarget = t0 + CFG["FunnelRetarget"]
            want = math.atan2(target[1] - z0, target[0] - x0)
            dh = (want - heading + math.pi) % (2 * math.pi) - math.pi
            heading += max(-turn, min(turn, dh))
            nx = x0 + math.cos(heading) * CFG["FunnelSpeed"] * seg
            nz = z0 + math.sin(heading) * CFG["FunnelSpeed"] * seg
            if not (-half + 3 <= nx <= half - 3 and -half + 3 <= nz <= half - 3):
                heading = math.atan2(-z0, -x0)
                nx = x0 + math.cos(heading) * CFG["FunnelSpeed"] * seg
                nz = z0 + math.sin(heading) * CFG["FunnelSpeed"] * seg
            path.append((t0 + seg, nx, nz))

    def funnel_at(t):
        if t < path[0][0]:
            return None
        k = int((t - path[0][0]) / seg)
        if k + 1 >= len(path):
            return path[-1][1], path[-1][2]
        a, b = path[k], path[k + 1]
        f = (t - a[0]) / seg
        return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f

    extend(CFG["FunnelStart"] + CFG["FunnelHorizon"])
    threats = [0] * n_players
    covered = [False] * n_players
    seen_at_t = [None] * n_players
    inside_since = [None] * n_players
    t = 0.0
    while t < CFG["Disaster"] + 1e-9:
        if t >= CFG["FunnelStart"] - CFG["FunnelHorizon"]:
            extend(max(t, CFG["FunnelStart"]) + CFG["FunnelHorizon"])
        # ribbon = funnel path over [t, t + horizon]: disks along it
        ribbon = [(x, z, zone) for (pt, x, z) in path if t - 0.3 <= pt <= t + CFG["FunnelHorizon"] + 1e-9]
        for k, p in enumerate(ps):
            if not p.alive:
                continue
            on = any(math.hypot(p.x - cx, p.z - cz) < r for (cx, cz, r) in ribbon)
            gx, gz = (p.tx, p.tz) if p.tx is not None else (p.x, p.z)
            goal_on = any(math.hypot(gx - cx, gz - cz) < r + 0.3 for (cx, cz, r) in ribbon)
            if (on or goal_on) and not covered[k]:
                covered[k] = True
                threats[k] += 1
                seen_at_t[k] = t + react_time(rng, prof, "lapseRing", 1.0, 4.0)
            if not on and not goal_on:
                covered[k] = False
            if covered[k] and seen_at_t[k] is not None and t >= seen_at_t[k] and goal_on:
                p.tx, p.tz = nearest_free(p.x, p.z, ribbon, bounds)
        for p in ps:
            if p.alive:
                p.step(t, dt)
        f = funnel_at(t)
        if f is not None:
            for k, p in enumerate(ps):
                if not p.alive:
                    continue
                sx, sz = seen_at(p, t)
                if math.hypot(sx - f[0], sz - f[1]) <= zone:
                    if inside_since[k] is None:
                        inside_since[k] = t
                    if t - inside_since[k] >= CFG["LagGrace"] - 1e-9:
                        p.alive = False
                else:
                    inside_since[k] = None
        t += dt
    return [(p.alive, threats[k]) for k, p in enumerate(ps)]


# ------------------------------------------------------------------------------------------- quake
def quake_round(rng, prof, lv, n_players):
    """Global part of a quake round. -> (list of (survived, threats)), collapsed share, min escape margin s."""
    N = len(lv)
    cell = CFG["Cell"]
    total = N * N
    collapsed = set()
    cells = [(i, j) for i in range(N) for j in range(N) if lv[i][j] >= 1]
    pos = []
    for _ in range(n_players):
        i, j = rng.choice(cells)
        pos.append([i, j, rng.uniform(0.15, 0.85), rng.uniform(0.15, 0.85)])  # cell + offset in the cell
    alive = [True] * n_players
    threats = [0] * n_players
    t = CFG["QuakeFirst"]
    min_margin = 99.0
    while t + CFG["QuakeCrack"] <= CFG["Disaster"] - 3.0 + 1e-9:
        cracking = set()

        def eligible(c):
            i, j = c
            if c in collapsed or c in cracking:
                return False
            for a, b in neighbours(i, j, N):
                if (a, b) not in collapsed and (a, b) not in cracking and abs(lv[a][b] - lv[i][j]) <= 1:
                    return True
            return False

        def add(c):
            if len(collapsed) + len(cracking) >= int(CFG["QuakeCap"] * total):
                return False
            if len(cracking) >= CFG["QuakeBatch"] or not eligible(c):
                return False
            # adding c must not strand an already-chosen cracking cell without an escape
            cracking.add(c)
            for d in list(cracking):
                if d != c:
                    cracking.discard(d)
                    ok = eligible(d)
                    cracking.add(d)
                    if not ok:
                        cracking.discard(c)
                        return False
            return True

        order = list(range(n_players))
        rng.shuffle(order)
        for k in order:
            if alive[k] and rng.random() < CFG["QuakeOnPlayer"]:
                c = (pos[k][0], pos[k][1])
                if add(c):
                    nb = [(a, b) for a, b in neighbours(c[0], c[1], N)]
                    rng.shuffle(nb)
                    for d in nb:
                        if add(d):
                            break
        pool = [(i, j) for i in range(N) for j in range(N)]
        rng.shuffle(pool)
        for c in pool:
            if len(cracking) >= CFG["QuakeBatch"]:
                break
            add(c)
        # players on cracking cells must leave within QuakeCrack (+ the lag grace)
        for k in range(n_players):
            if not alive[k]:
                continue
            i, j, ox, oz = pos[k]
            if (i, j) not in cracking:
                continue
            threats[k] += 1
            best = None
            for a, b in neighbours(i, j, N):
                if (a, b) in collapsed or (a, b) in cracking or abs(lv[a][b] - lv[i][j]) > 1:
                    continue
                # distance from the player's spot to 1.5 studs inside the neighbour cell
                if a == i + 1:
                    d = (1 - ox) * cell
                elif a == i - 1:
                    d = ox * cell
                elif b == j + 1:
                    d = (1 - oz) * cell
                else:
                    d = oz * cell
                d += CFG["PlayerRadius"] + 0.5
                if best is None or d < best[0]:
                    best = (d, a, b)
            if best is None:
                alive[k] = False  # never happens if the eligibility rule holds
                continue
            need = react_time(rng, prof, "lapseRing", 1.0, 4.0) + best[0] * 1.15 / CFG["WalkSpeed"]
            margin = CFG["QuakeCrack"] + CFG["LagGrace"] - need
            if prof.get("fixed"):
                min_margin = min(min_margin, margin)
            if need > CFG["QuakeCrack"] + CFG["LagGrace"]:
                alive[k] = False
                continue
            ni, nj = best[1], best[2]
            pos[k] = [ni, nj, rng.uniform(0.2, 0.5) if ni > i else (rng.uniform(0.5, 0.8) if ni < i else ox),
                      rng.uniform(0.2, 0.5) if nj > j else (rng.uniform(0.5, 0.8) if nj < j else oz)]
        collapsed |= cracking
        t += CFG["QuakeEvery"]
    return [(alive[k], threats[k]) for k in range(n_players)], len(collapsed) / total, min_margin


# ---------------------------------------------------------------------------------- per-round tables
def build_tables(rng, R=None, profiles=None):
    R = R or (150 if QUICK else 500)
    maps = [gen_map(rng)[0] for _ in range(60 if QUICK else 200)]
    out = {"ring": {}, "rings_n": {}, "global": {}, "threats": {}, "quake_share": [], "quake_margin": 99.0}
    for pname in (profiles or PROFILES):
        prof = PROFILES[pname]
        rr = R if pname != "bot" else max(50, R // 2)
        for sched, iv in (("meteor", CFG["MeteorIntervals"]), ("other", CFG["OtherIntervals"])):
            for heat in range(6):
                s_, n_ = ring_survival(rng, prof, iv, heat, rr)
                out["ring"][(pname, sched, heat)] = s_
                out["rings_n"][(sched, heat)] = n_
        fs, ft = [], []
        for k in range(R):
            a_, th = flood_round(rng, prof, maps[k % len(maps)])
            fs.append(a_)
            ft.append(th)
        out["global"][(pname, "flood")] = sum(fs) / len(fs)
        out["threats"][("flood", pname)] = statistics.mean(ft)
        ts, tt = [], []
        for k in range(max(20, R // 4)):
            for (a_, th) in tornado_round(rng, prof, 1 if k % 2 == 0 else 8):
                ts.append(a_)
                tt.append(th)
        out["global"][(pname, "tornado")] = sum(ts) / len(ts)
        out["threats"][("tornado", pname)] = statistics.mean(tt)
        qs, qt = [], []
        for k in range(R):
            res, share, margin = quake_round(rng, prof, maps[k % len(maps)], 1 if k % 2 == 0 else 8)
            out["quake_share"].append(share)
            if pname == "bot":
                out["quake_margin"] = min(out["quake_margin"], margin)
            for (a_, th) in res:
                qs.append(a_)
                qt.append(th)
        out["global"][(pname, "quake")] = sum(qs) / len(qs)
        out["threats"][("quake", pname)] = statistics.mean(qt)
        out["global"][(pname, "meteor")] = 1.0
    return out


def p_survive(tables, prof, kind, heat):
    sched = "meteor" if kind == "meteor" else "other"
    return tables["global"][(prof, kind)] * tables["ring"][(prof, sched, heat)]


# ------------------------------------------------------------------------------------------ sessions
def first_and_start(phase):
    """Seconds from joining to (a) first time on the island (a counted drop or a practice drop-in) and
    (b) the first COUNTED drop. phase = seconds into the cycle at join (0 = intermission starts)."""
    I, D, W = CFG["Intermission"], CFG["Drop"], CFG["JumpInWindow"]
    cyc = I + D + CFG["Disaster"] + CFG["Outro"]
    tap = 3.0  # seconds to read the HUD and tap "Jump in"
    if phase < I:
        return I - phase, I - phase
    nxt = cyc - phase + I
    if phase + tap <= I + D + W:  # practice drop-in (from the drop until 20 s into the disaster)
        return tap, nxt
    return nxt, nxt


def session(rng, tables, prof, minutes, codex_needed=False):
    cyc = CFG["Intermission"] + CFG["Drop"] + CFG["Disaster"] + CFG["Outro"]
    phase = rng.uniform(0, cyc)
    first, t = first_and_start(phase)
    kind0 = rng.choice(KINDS)
    iv0 = (CFG["MeteorIntervals"] if kind0 == "meteor" else CFG["OtherIntervals"])[0]
    practice = abs(first - t) > 1e-9
    first_ring = first + (0.0 if practice else CFG["Drop"]) + CFG["FirstRingAfter"] + rng.uniform(0, iv0)
    survived = played = streak = best = 0
    band_t = [None] * len(BANDS)
    maxheat_t = None
    codex = set()
    codex_t = None
    best_at = {}
    codex_at = {}
    last = None
    lookout = 0.0
    end = minutes * 60
    while t < end:
        kinds = [k for k in KINDS if k != last]
        kind = rng.choice(kinds)
        last = kind
        heat = heat_of(streak)
        p = p_survive(tables, prof, kind, heat)
        played += 1
        round_end = t + CFG["Drop"] + CFG["Disaster"]
        if rng.random() < p:
            survived += 1
            streak += 1
            best = max(best, streak)
            for h in range(heat + 1):  # surviving a disaster at heat h fills its row up to h
                codex.add((kind, h))
            if len(codex) == 24 and codex_t is None:
                codex_t = round_end / 60
            for b, th in enumerate(BANDS):
                if band_t[b] is None and survived >= th:
                    band_t[b] = round_end / 60
            if heat_of(streak) == CFG["MaxHeat"] and maxheat_t is None:
                maxheat_t = round_end / 60
            lookout += CFG["Intermission"]
        else:
            streak = 0
            out_at = rng.uniform(5.0, CFG["Disaster"])  # approximation: uniform elimination time
            lookout += CFG["Intermission"] + CFG["Outro"] + (CFG["Disaster"] - out_at)
        for m in (30, 60, 120, 240):
            if m not in best_at and round_end >= m * 60:
                best_at[m] = best
                codex_at[m] = len(codex)
        t += cyc
        if codex_needed and codex_t is not None:
            break
    return {"first": first, "first_ring": first_ring, "kind0": kind0, "band_t": band_t, "maxheat_t": maxheat_t, "codex_t": codex_t, "best_at": best_at, "codex_at": codex_at,
            "survived": survived, "played": played, "lookout_share": lookout / max(1.0, t)}


def fmt3(v):
    v = [x for x in v if x is not None]
    if not v:
        return "never"
    return "%.1f / %.1f / %.1f" % (pct(v, 0.1), pct(v, 0.5), pct(v, 0.9))


def main():
    rng = random.Random(SEED)
    print("=== MapGen (%d maps) ===" % (100 if QUICK else 500))
    ms = map_stats(100 if QUICK else 500, rng)
    for k, v in ms.items():
        print("  %-18s %s" % (k, v))

    print("\n=== per-round tables ===")
    tables = build_tables(rng)
    print("aimed rings per player per round (mean):")
    for sched in ("meteor", "other"):
        print("  %-8s" % sched, " ".join("h%d %.1f" % (h, tables["rings_n"][(sched, h)]) for h in range(6)))
    print("global threats per player per round (mean, normal): ",
          {k: round(tables["threats"][(k, "normal")], 2) for k in ("flood", "tornado", "quake")})
    print("quake collapsed share: p50 %.2f max %.2f   bot's tightest quake margin %.2f s"
          % (pct(tables["quake_share"], 0.5), max(tables["quake_share"]), tables["quake_margin"]))
    print("\nP(survive round) = global x rings, by heat 0..5:")
    for pname in PROFILES:
        for kind in KINDS:
            print("  %-6s %-8s glob %.3f | %s" % (pname, kind, tables["global"][(pname, kind)],
                  " ".join("%.3f" % p_survive(tables, pname, kind, h) for h in range(6))))
        avg = [statistics.mean(p_survive(tables, pname, k, h) for k in KINDS) for h in range(6)]
        print("  %-6s %-8s       | %s" % (pname, "AVERAGE", " ".join("%.3f" % a for a in avg)))

    # crowded flood plateau: 8 players at heat 5 on 18 cells (a 32 x 36 stud rectangle ~ 1152 sq studs)
    print("\n=== crowded plateau: 8 players, heat 5, Flood hold (18 s), 18 dry cells ===")
    for pname in ("bot", "normal"):
        R = 60 if QUICK else 200
        ok = n = 0
        for _ in range(R):
            alive, _ = ring_round(rng, PROFILES[pname], CFG["OtherIntervals"], 5, n_players=8, half=17.0,
                                  cap_area=18 * 64, t_end=18.0)
            ok += sum(alive)
            n += len(alive)
        print("  %-6s survive the hold: %.3f" % (pname, ok / n))
    for pname in ("bot",):
        R = 60 if QUICK else 200
        ok = n = 0
        for _ in range(R):
            alive, _ = ring_round(rng, PROFILES[pname], CFG["MeteorIntervals"], 5, n_players=8, half=50.0)
            ok += sum(alive)
            n += len(alive)
        print("  %-6s 8 players, heat 5 Meteor Shower, open island: %.3f" % (pname, ok / n))

    print("\n=== fairness floor: 8 bots at heat 5, Meteor Shower, open island (bot-rounds lost) ===")
    keep_exit, keep_cross = CFG["ExitStuds"], crosses_landing
    R = 50 if QUICK else 150
    for label, ex, smart in (("placement rule OFF, naive dodger", 99.0, False),
                             ("placement rule ON, naive dodger", keep_exit, False),
                             ("placement rule OFF, smart dodger", 99.0, True),
                             ("placement rule ON, smart dodger", keep_exit, True)):
        CFG["ExitStuds"] = ex
        globals()["crosses_landing"] = keep_cross if smart else (lambda *a: False)
        lost = n = 0
        for _ in range(R):
            alive, _ = ring_round(rng, PROFILES["bot"], CFG["MeteorIntervals"], 5, n_players=8, half=50.0)
            lost += sum(1 for a in alive if not a)
            n += len(alive)
        print("  %-34s %d / %d" % (label, lost, n))
    CFG["ExitStuds"] = keep_exit
    globals()["crosses_landing"] = keep_cross

    print("\n=== sessions ===")
    S = 600 if QUICK else 3000
    cyc = CFG["Intermission"] + CFG["Drop"] + CFG["Disaster"] + CFG["Outro"]
    print("round cycle %.0f s -> %.2f rounds/min" % (cyc, 60 / cyc))
    res = {}
    for pname in ("normal", "fast", "slow", "bot"):
        res[pname] = [session(rng, tables, pname, 240) for _ in range(S)]
    print("first time on the island after joining (s, p10/p50/p90):",
          fmt3([r["first"] for r in res["normal"]]), " max %.1f" % max(r["first"] for r in res["normal"]))
    print("first aimed ring at you after joining (s): meteor round %s | other round %s" % (
        fmt3([r["first_ring"] for r in res["normal"] if r["kind0"] == "meteor"]),
        fmt3([r["first_ring"] for r in res["normal"] if r["kind0"] != "meteor"])))
    print("\nminutes to each band (p10 / median / p90):")
    for b in range(len(BANDS)):
        print("  band %d %-12s (%3d survivals):" % (b + 2, BAND_NAMES[b + 1], BANDS[b]),
              " | ".join("%s %s" % (p, fmt3([r["band_t"][b] for r in res[p]])) for p in ("normal", "fast", "slow")))
    for p in ("normal", "fast", "slow"):
        durs = []
        for b in range(len(BANDS) - 1):
            d = [r["band_t"][b + 1] - r["band_t"][b] for r in res[p] if r["band_t"][b + 1] is not None]
            durs.append(statistics.median(d) if d else float("nan"))
        print("  %-6s median minutes spent in bands 2..5: %s" % (p, " / ".join("%.1f" % d for d in durs)))
    for p in ("normal", "fast", "slow", "bot"):
        print("  %-6s first MAX HEAT (streak %d): %s  (reached in 4 h by %.0f %%)" % (
            p, CFG["MaxHeat"] * CFG["HeatPerStreak"], fmt3([r["maxheat_t"] for r in res[p]]),
            100 * sum(1 for r in res[p] if r["maxheat_t"] is not None) / S))
    for p in ("normal", "fast", "slow"):
        print("  %-6s best streak at 30/60/120/240 min (median): %s" % (
            p, " / ".join(str(statistics.median(r["best_at"].get(m, 0) for r in res[p])) for m in (30, 60, 120, 240))))
        print("  %-6s Codex entries at 30/60/120/240 min (median): %s" % (
            p, " / ".join(str(statistics.median(r["codex_at"].get(m, 0) for r in res[p])) for m in (30, 60, 120, 240))))
        share = statistics.median(r["lookout_share"] for r in res[p])
        print("  %-6s survived per hour (median): %.1f   Lookout share %.2f -> one stray (ambient) per %.1f min of play" % (
            p, statistics.median(r["survived"] for r in res[p]) / 4, share, CFG["AmbientMean"] / share / 60))
    # Codex
    C = 100 if QUICK else 300
    for p in ("normal", "fast"):
        cs = [session(rng, tables, p, 60 * 40, codex_needed=True)["codex_t"] for _ in range(C)]
        done = [c / 60 for c in cs if c is not None]
        print("  %-6s Codex 24/24 (hours): %s, finished in 40 h: %.0f %%" % (p, fmt3(done), 100 * len(done) / C))

    # sensitivity of the brag (band 5) to the lapse assumption
    print("\n=== sensitivity: normal player's band 5 (brag) median minutes ===")
    base = dict(PROFILES["normal"])
    for mult in (0.5, 2.0):
        PROFILES["normal"] = dict(base, lapseRing=base["lapseRing"] * mult, lapseBig=base["lapseBig"] * mult)
        t2 = build_tables(random.Random(SEED + 1), R=150, profiles=["normal"])
        rr = [session(rng, t2, "normal", 240) for _ in range(S // 2)]
        print("  lapse x%.1f: band 5 %s ; band 6 %s ; avg P(survive) h0 %.3f h5 %.3f" % (
            mult, fmt3([r["band_t"][3] for r in rr]), fmt3([r["band_t"][4] for r in rr]),
            statistics.mean(p_survive(t2, "normal", k, 0) for k in KINDS),
            statistics.mean(p_survive(t2, "normal", k, 5) for k in KINDS)))
    PROFILES["normal"] = base


if __name__ == "__main__":
    main()
