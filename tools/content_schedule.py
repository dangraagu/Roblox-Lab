"""Plan the Shorts / TikTok schedule for every published game, and lay out the TikTok folders.

    py -3 tools/content_schedule.py plan  --from 2026-09-18 --to 2026-09-25
    py -3 tools/content_schedule.py tiktok --from 2026-09-17 --to 2026-09-25

Owner's rules (2026-09-17):
  * YouTube: one Short every 3 hours, all day. Two clips per game per day.
  * When a game's unique clips run out, republish them (rotating titles), through the year.
  * TikTok is posted by hand: one folder per date, `7am` and `7pm` inside it, and in each one
    video N next to text file N, so it is drag-and-drop plus copy-paste.

`plan` writes docs/marketing/schedule.json: every post with its slot, clip, title and description.
Posts that are already live or scheduled in YouTube Studio are read from
docs/marketing/youtube-schedule.md and keep their slot; nothing is double-booked.
`tiktok` copies the clips into tiktok-queue/ (git-ignored: it is a copy of committed clips).
"""

from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLOTS = ["01:00", "04:00", "07:00", "10:00", "13:00", "16:00", "19:00", "22:00"]
AI_LINE = ("Made by one person with an AI coding assistant: I set the design, pick the numbers and "
           "test the builds.")

GAMES = {
    "anomaly": {
        "name": "Anomaly: Night Shift at the Observatory",
        "link": "https://www.roblox.com/games/123669267191209/",
        "tags": "#roblox #robloxhorror #spotthedifference #gamedev",
        "base": ("Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. "
                 "The hall is rebuilt before every pass, and either it is clean or exactly one thing "
                 "about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or "
                 "Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however "
                 "deep you were."),
        "tiktok_order": 1,
    },
    "plus1": {
        "name": "+1 Jump Every Step",
        "link": "https://www.roblox.com/games/120040655253410/",
        "tags": "#roblox #obby #robloxobby #gamedev",
        "base": ("+1 Jump Every Step - a Roblox sky-temple obby. You start with a normal 7.2 stud jump, "
                 "and every platform past the highest one you have reached gives +1 Jump Power. Six "
                 "platforms per tier, one tower for the whole server, and no kill bricks: fall and you "
                 "are put back on the platform you last earned."),
        "tiktok_order": 2,
    },
    "crystal": {
        "name": "Grow a Crystal",
        "link": "https://www.roblox.com/games/106123351742435/",
        "tags": "#roblox #idlegame #robloxgames #gamedev",
        "base": ("Grow a Crystal - a cozy Roblox idle game. Plant a seed-crystal in a socket, let it "
                 "grow (a Shard takes 60 seconds, a Mythic 40 minutes, and it keeps growing while you "
                 "are logged out), then harvest it for Gem Dust. Every harvest rolls refraction: one "
                 "tier up per hit, from Shard all the way to Mythic."),
        "tiktok_order": 3,
    },
    "laby": {
        "name": "Labyrinth Mariozo",
        "link": "https://www.roblox.com/games/121268951050692/",
        "tags": "#roblox #maze #robloxobby #gamedev",
        "base": ("Labyrinth Mariozo - a Roblox maze game. Dark maze, one torch, one way out. Grab the "
                 "coins and gems, hit a coloured button to drop the wall in that colour, and touch the "
                 "green EXIT to have the next maze build around you. Every level comes from one world "
                 "seed, so level 40 is the same maze for everyone."),
        "tiktok_order": 4,
    },
}

# Each clip: file, what THIS clip shows (appended to the base text), and title variants. The first
# variant is used the first time; republishes rotate through the rest.
CLIPS = {
    "anomaly": [
        ("anomaly-observatory/marketing/pairs/scope_gone/spot.mp4", "This one was the telescope.",
         ["Spot what is missing before the reveal", "4 seconds. One thing is gone. Find it"]),
        ("anomaly-observatory/marketing/pairs/twin_scope/spot.mp4", "This one was the second telescope.",
         ["Clean hall or not? Look twice", "Something in this hall is doubled"]),
        ("anomaly-observatory/marketing/pairs/lights_out/spot.mp4", "This one was the lights.",
         ["This hall looks wrong. Why?", "Easy one. Did you get it?"]),
        ("anomaly-observatory/marketing/pairs/scope_tilt/spot.mp4", "This one was the telescope, aimed at the floor.",
         ["One object is pointing the wrong way", "Look at the telescope. Now look again"]),
        ("anomaly-observatory/marketing/pairs/poster_red/spot.mp4", "This one was the wall panel glowing red.",
         ["Did the colour change or did you imagine it?", "Spot the wrong colour in this hall"]),
        ("anomaly-observatory/marketing/pairs/mirror_extra/spot.mp4", "This one was the extra mirror on the wall.",
         ["One thing too many on the right wall", "Would you have turned back here?"]),
        ("anomaly-observatory/marketing/pairs/figure_ceiling/spot.mp4", "This one was the thing on the ceiling.",
         ["Look up before you advance", "There is someone else in this hall"]),
        ("anomaly-observatory/marketing/pairs/scale_bench/spot.mp4", "This one was the bench, scaled up.",
         ["Something in this hall is the wrong size", "Hardest one so far. Find it"]),
        ("anomaly-observatory/marketing/pairs/static_screen/spot.mp4", "This one was the monitor showing static.",
         ["A tiny detail changed. Did you see it?", "Only the sharp-eyed get this one"]),
        ("anomaly-observatory/marketing/pairs/chair_moved/spot.mp4", "This one was the chair, moved from its usual spot.",
         ["Nothing is missing. Something moved", "Advance or turn back? You have 4 seconds"]),
        ("anomaly-observatory/marketing/pairs/door_extra/spot.mp4", "This one was the extra door.",
         ["Count the doors", "The far end of this hall is wrong"]),
    ],
    "plus1": [
        ("plus1-jump/marketing/clips/climb_tier1.mp4",
         "This is tier 1 from a fresh start: every new platform, the counter goes up by one.",
         ["Every step you take gives +1 jump", "Watch the counter go up with every jump"]),
        ("plus1-jump/marketing/clips/code_launch.mp4",
         "A normal hop, then the code LAUNCH (+100 Jump Power), then the same hop again.",
         ["What +100 jump power does to one jump", "Same jump. Before and after one code"]),
        ("plus1-jump/marketing/clips/tower_path.mp4",
         "A camera flight up the platform path of tiers 1 to 6.",
         ["The whole sky tower in 12 seconds", "Every platform up to tier 6"]),
        ("plus1-jump/marketing/clips/climb_tier3.mp4",
         "Tier 3, where the steps get taller and each jump pays +1 again.",
         ["Tier 3: taller steps, same +1", "When the steps get taller, so does your jump"]),
        ("plus1-jump/marketing/clips/saw_tier5.mp4",
         "Tier 5, the first tier with an obstacle on it.",
         ["Tier 5 is where the obstacles start", "Climbing past the first obstacle"]),
        ("plus1-jump/marketing/clips/pendulum_tier6.mp4",
         "Tier 6 and the pendulum.",
         ["Tier 6: steps at 17 studs and climbing", "Six more platforms, six more jump power"]),
    ],
    "crystal": [
        ("grow-a-crystal/marketing/clips/grow_timelapse.mp4",
         "One crystal growing through all four stages - 68 seconds of real time, sped up 6.5x.",
         ["A crystal growing in 60 seconds, sped up", "Watch a Shard crystal grow"]),
        ("grow-a-crystal/marketing/clips/harvest.mp4",
         "Harvesting grown crystals: the Gem Dust counter goes from 30 to 62.",
         ["Harvest day in the cavern", "Clicking a grown crystal for Gem Dust"]),
        ("grow-a-crystal/marketing/clips/cavern_climb.mp4",
         "A camera flight up the cavern's terraces, past the locked chambers, to the basin.",
         ["The cavern you unlock one chamber at a time", "Eight terraces of crystal sockets"]),
        ("grow-a-crystal/marketing/clips/plant_seed.mp4",
         "Planting a Shard seed: one click on a glowing socket.",
         ["One click, one crystal", "Planting the first seed"]),
        ("grow-a-crystal/marketing/clips/cavern_descend.mp4",
         "From the top of the cavern back down to the planting sockets.",
         ["Down through the crystal cavern", "From the basin to the first socket"]),
    ],
    "laby": [
        ("labyrint-spill/marketing/clips/coins_and_exit.mp4",
         "Level 1: coins and gems, then out through the exit. Played at 2x.",
         ["Clearing level 1 of the maze", "Coins, gems, exit. Level 1 done"]),
        ("labyrint-spill/marketing/clips/level2_run.mp4",
         "Level 2 from start to exit. Played at 2x.",
         ["Level 2, start to exit", "Can you find the exit faster?"]),
        ("labyrint-spill/marketing/clips/lobby_enter.mp4",
         "The lobby: Solo Climb, Group, or Play with Friends.",
         ["Pick a door: solo, group or friends", "Three doors into the maze"]),
    ],
}


def game_of(path):
    for g, clips in CLIPS.items():
        if any(c[0] == path for c in clips):
            return g
    return None


def load_existing():
    """Posts already in YouTube Studio, from the log: (datetime, clip path, title), every game.

    Rows name the clip either as `pairs/<id>/spot.mp4` (the Anomaly rows written first) or by its
    repo path. A row whose clip is not in CLIPS is reported, never skipped silently."""
    path = os.path.join(ROOT, "docs", "marketing", "youtube-schedule.md")
    out = []
    with io.open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\| `([^`]+\.mp4)` \| (.*?) \| (\d{4}-\d{2}-\d{2})(?: (\d{2}:\d{2}))? \|", line)
            if not m:
                continue
            clip = m.group(1)
            if clip.startswith("pairs/"):
                clip = "anomaly-observatory/marketing/" + clip
            if game_of(clip) is None:
                raise SystemExit("youtube-schedule.md names a clip the planner does not know: " + clip)
            when = dt.datetime.strptime(m.group(3) + " " + (m.group(4) or "12:00"), "%Y-%m-%d %H:%M")
            out.append((when, clip, m.group(2)))
    return out


def window(t):
    """Index of the 3-hour window a time falls in (01-04 is 0, ..., 22-01 is 7)."""
    return ((t.hour - 1) % 24) // 3


def build(start, end):
    existing = load_existing()
    used = {}
    for g, clips in CLIPS.items():
        for c in clips:
            used[c[0]] = sum(1 for _, p, _t in existing if p == c[0])
    # Rotation: the least-posted clip goes next, ties broken by list order.
    posts = []
    day = start
    order = ["plus1", "crystal", "laby", "anomaly"]
    d_i = 0
    while day <= end:
        taken = {window(w) for w, _p, _t in existing if w.date() == day}
        booked = {g: 0 for g in GAMES}
        for w, p, _t in existing:
            if w.date() == day:
                booked[game_of(p)] += 1
        free = [i for i in range(8) if i not in taken]
        # Interleave games so the same game never gets two adjacent free slots when avoidable.
        rot = order[d_i % 4:] + order[:d_i % 4]
        queue = []
        while len(queue) < len(free):
            progressed = False
            for g in rot:
                if booked[g] < 2 and len(queue) < len(free):
                    queue.append(g)
                    booked[g] += 1
                    progressed = True
            if not progressed:
                break
        for slot_i, g in zip(free, queue):
            clips = CLIPS[g]
            k = min(range(len(clips)), key=lambda i: (used[clips[i][0]], i))
            path, what, titles = clips[k]
            n = used[path]
            used[path] += 1
            title = titles[n % len(titles)]
            info = GAMES[g]
            yt_desc = "%s %s Play it: %s %s" % (info["base"], what, info["link"], AI_LINE)
            posts.append({
                "date": day.isoformat(), "time": SLOTS[slot_i], "game": g, "clip": path,
                "title": title + " #shorts #roblox", "description": yt_desc,
                "republish": n > 0,
                "tiktok_text": "%s\n\n%s %s Play it: %s\n\n%s" % (title, info["base"], what,
                                                              info["link"], info["tags"]),
                "youtube": None,
            })
        day += dt.timedelta(days=1)
        d_i += 1
    return posts


def tiktok(schedule, existing_posts, start, end):
    """Two TikTok slots a day. Per game, its earlier post of the day goes in 7am, the later in 7pm."""
    qroot = os.path.join(ROOT, "tiktok-queue")
    by_day = {}
    for p in existing_posts + schedule:
        by_day.setdefault(p["date"], []).append(p)
    written = 0
    for date, posts in sorted(by_day.items()):
        d = dt.date.fromisoformat(date)
        if not (start <= d <= end):
            continue
        per_game = {}
        for p in sorted(posts, key=lambda p: p["time"]):
            per_game.setdefault(p["game"], []).append(p)
        for slot_name, idx in (("7am", 0), ("7pm", 1)):
            folder = os.path.join(qroot, date, slot_name)
            items = [(GAMES[g]["tiktok_order"], ps[idx]) for g, ps in per_game.items() if len(ps) > idx]
            if not items:
                continue
            os.makedirs(folder, exist_ok=True)
            for n, (_, p) in enumerate(sorted(items, key=lambda t: t[0]), start=1):
                if not os.path.exists(os.path.join(ROOT, p["clip"])):
                    raise SystemExit("clip missing, TikTok folder %s left incomplete: %s" % (folder, p["clip"]))
                shutil.copyfile(os.path.join(ROOT, p["clip"]), os.path.join(folder, "%d.mp4" % n))
                with io.open(os.path.join(folder, "%d.txt" % n), "w", encoding="utf-8") as f:
                    f.write(p["tiktok_text"] + "\n")
                written += 1
    return written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["plan", "tiktok"])
    ap.add_argument("--from", dest="start", required=True)
    ap.add_argument("--to", dest="end", required=True)
    a = ap.parse_args()
    start, end = dt.date.fromisoformat(a.start), dt.date.fromisoformat(a.end)
    spath = os.path.join(ROOT, "docs", "marketing", "schedule.json")
    if a.cmd == "plan":
        # Posts already uploaded are in youtube-schedule.md and count as existing; drop them from
        # the new plan instead of planning them twice.
        posts = build(start, end)
        with io.open(spath, "w", encoding="utf-8", newline="\n") as f:
            json.dump(posts, f, indent=1, ensure_ascii=False)
            f.write("\n")
        for p in posts:
            print(p["date"], p["time"], "%-8s" % p["game"], "R" if p["republish"] else " ",
                  os.path.basename(os.path.dirname(p["clip"])) if p["game"] == "anomaly"
                  else os.path.basename(p["clip"]), "|", p["title"])
        print(len(posts), "posts")
    else:
        with io.open(spath, encoding="utf-8") as f:
            posts = json.load(f)
        logged = {(p["date"], p["time"]) for p in posts}
        existing = []
        for when, path, title in load_existing():
            g = game_of(path)
            if (when.date().isoformat(), when.strftime("%H:%M")) in logged:
                continue  # already in schedule.json, uploaded from it
            clip = next(c for c in CLIPS[g] if c[0] == path)
            info = GAMES[g]
            existing.append({"date": when.date().isoformat(), "time": when.strftime("%H:%M"),
                             "game": g, "clip": path,
                             "tiktok_text": "%s\n\n%s %s Play it: %s\n\n%s" % (
                                 title, info["base"], clip[1], info["link"], info["tags"])})
        print(tiktok(posts, existing, start, end), "TikTok files written to tiktok-queue/")


if __name__ == "__main__":
    main()
