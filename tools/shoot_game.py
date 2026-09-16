"""Photograph a game from inside Roblox Studio, without a human holding the camera.

Studio must already have the game's place open. Then:

    py -3 tools/shoot_game.py labyrint
    py -3 tools/shoot_game.py crystal --keep-play

It plays the game, waits for the server script to build the world, runs a short per-game setup
(entering a maze, planting a crystal), measures where things actually ended up, takes the shot
list from real coordinates rather than guesses, and puts everything back.

Two honesty rules, both enforced here rather than left to whoever is running it:

  * A shot marked `lift` temporarily removes the fog. Labyrinth is a dark maze on purpose - an
    overhead of it is pure black, which is correct and useless as a picture. Those shots go in a
    `promo/` subfolder and are captioned as promotional in the manifest, because no player ever
    sees the maze lit like that. Everything else goes in `gameplay/` and is what the game looks
    like.
  * Lighting is saved before it is touched and restored afterwards, in the same run, even when a
    capture fails.

Shots land in <game>/marketing/shots/, with a manifest.json recording camera, target, and
whether the fog was lifted, so a picture can always be traced back to how it was taken.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from studio_mcp import Studio, text_of, save_images  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIFT = """
local L = game:GetService("Lighting")
_G.__savedLighting = {
    FogEnd = L.FogEnd, FogStart = L.FogStart, Brightness = L.Brightness,
    ClockTime = L.ClockTime, Ambient = L.Ambient, OutdoorAmbient = L.OutdoorAmbient,
}
L.FogEnd = 100000; L.FogStart = 100000; L.Brightness = 3; L.ClockTime = 13
L.Ambient = Color3.fromRGB(120, 120, 130)
L.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
return "lifted"
"""

RESTORE = """
local L = game:GetService("Lighting")
local s = _G.__savedLighting
if not s then return "nothing to restore" end
L.FogEnd = s.FogEnd; L.FogStart = s.FogStart; L.Brightness = s.Brightness
L.ClockTime = s.ClockTime; L.Ambient = s.Ambient; L.OutdoorAmbient = s.OutdoorAmbient
_G.__savedLighting = nil
return "restored"
"""

# Measure a named folder's bounding box. Every camera below is derived from one of these, so a
# world that builds somewhere unexpected produces a bad measurement rather than a black picture.
BOUNDS = """
local target = nil
for _, c in workspace:GetChildren() do
    if string.match(c.Name, "__ANCHOR__") then target = c end
end
if not target then
    local names = {}
    for _, c in workspace:GetChildren() do table.insert(names, c.Name) end
    return "MISSING|" .. table.concat(names, ",")
end
local mnx, mny, mnz = math.huge, math.huge, math.huge
local mxx, mxy, mxz = -math.huge, -math.huge, -math.huge
local n = 0
for _, d in target:GetDescendants() do
    if d:IsA("BasePart") then
        n += 1
        local p, s = d.Position, d.Size
        mnx = math.min(mnx, p.X - s.X/2); mxx = math.max(mxx, p.X + s.X/2)
        mny = math.min(mny, p.Y - s.Y/2); mxy = math.max(mxy, p.Y + s.Y/2)
        mnz = math.min(mnz, p.Z - s.Z/2); mxz = math.max(mxz, p.Z + s.Z/2)
    end
end
return string.format("OK|%s|%d|%f|%f|%f|%f|%f|%f", target.Name, n, mnx, mxx, mny, mxy, mnz, mxz)
"""

GAMES = {
    "labyrint": {
        "dir": "labyrint-spill",
        "setup": [
            ("Client", 'local r = game:GetService("ReplicatedStorage"):FindFirstChild("LobbyRemotes")\n'
                       'if not r then return "no LobbyRemotes" end\n'
                       'r.StartRun:FireServer(1)\n'
                       'return "entered a run"'),
        ],
        "settle": 4,
        "anchor": "^Maze_",
        "shots": [
            # name, camera relative to the anchor box, look-at, lift the fog?
            ("maze_iso",    ("cx-80", "cy+58", "mnz-40"), ("cx+5", "cy-8", "cz+5"), True),
            ("maze_top",    ("cx", "cy+128", "cz-10"),    ("cx", "mny", "cz"),      True),
            ("corridor",    ("mnx+10", "mny+4", "mnz+6"), ("cx", "mny+4", "cz"),    False),
        ],
    },
    "crystal": {
        "dir": "grow-a-crystal",
        "setup": [],
        "settle": 5,
        "anchor": "^Plots$",
        # The cavern is a SEALED shell: x[-36,36], z[-18,138]. Every camera has to be INSIDE it.
        # The first attempt put one at z = mnz-26, which is 26 studs into the rock behind the
        # entrance wall, and duly photographed the inside of a boulder.
        "shots": [
            ("entrance", ("cx", "mny+14", "mnz+6"), ("cx", "mny+10", "cz-20")),
            ("terraces", ("cx", "cy+5", "mnz+38"),  ("cx", "mny+12", "cz+30")),
            ("pool",     ("cx", "cy+9", "mxz-43"),  ("cx", "cy-1", "mxz-13")),
        ],
    },
    "plus1": {
        "dir": "plus1-jump",
        "setup": [],
        "settle": 4,
        "anchor": "^Tower$",
        # The tower streams six tiers ahead of the highest player, so at a fresh join it is a
        # stack a few hundred studs tall starting at y = 8. Shoot it from beside and below.
        "shots": [
            ("climb",     ("cx+34", "mny+16", "cz+34"), ("cx", "mny+90", "cz")),
            ("tower_iso", ("cx-90", "cy", "cz-90"),     ("cx", "cy", "cz")),
            ("from_top",  ("cx+20", "mxy-20", "cz+20"), ("cx", "mny+20", "cz")),
        ],
    },
    "anomaly": {
        "dir": "anomaly-observatory",
        "setup": [],
        "settle": 4,
        # Each player gets a private Model named Concourse_<userId>, not a folder called Zone.
        "anchor": "^Concourse_",
        # The hall runs 80 studs away from the start pad and is deliberately near-black
        # (ClockTime 0.2). Shoot it down its own length, which is the only view a player has.
        "shots": [
            ("the_walk",  ("cx", "mny+8", "mxz-6"),  ("cx", "mny+8", "mnz+6")),
            ("far_end",   ("cx", "mny+8", "mnz+20"), ("cx", "mny+8", "mnz+2")),
        ],
    },
}


_OFFSET = re.compile(r"^\s*([a-z]{2,3})\s*(?:([+-])\s*([0-9]+(?:\.[0-9]+)?))?\s*$")


def resolve(expr, b):
    """Turn 'cx-80' into a number using the measured box.

    Deliberately a parser and not eval(). The strings all come from the GAMES table in this
    file, so eval would have been safe today - but a shot list is exactly the sort of thing
    that later gets read from a config file or a command line, and by then the eval would be
    load-bearing and unnoticed. One anchor name, one sign, one number, nothing else.
    """
    env = {
        "mnx": b["mnx"], "mxx": b["mxx"], "mny": b["mny"],
        "mxy": b["mxy"], "mnz": b["mnz"], "mxz": b["mxz"],
        "cx": (b["mnx"] + b["mxx"]) / 2,
        "cy": (b["mny"] + b["mxy"]) / 2,
        "cz": (b["mnz"] + b["mxz"]) / 2,
    }
    m = _OFFSET.match(expr)
    if not m:
        raise SystemExit("bad camera expression %r - want <anchor>[+-]<number>, "
                         "anchor one of %s" % (expr, ", ".join(sorted(env))))
    anchor, sign, amount = m.group(1), m.group(2), m.group(3)
    if anchor not in env:
        raise SystemExit("unknown anchor %r in %r - have %s"
                         % (anchor, expr, ", ".join(sorted(env))))
    value = env[anchor]
    if sign:
        value += float(amount) * (1 if sign == "+" else -1)
    return value


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", choices=sorted(GAMES))
    ap.add_argument("--keep-play", action="store_true",
                    help="leave Studio in Play mode afterwards (for a follow-up by hand)")
    args = ap.parse_args()

    spec = GAMES[args.game]
    outdir = os.path.join(ROOT, spec["dir"], "marketing", "shots")
    os.makedirs(os.path.join(outdir, "gameplay"), exist_ok=True)
    os.makedirs(os.path.join(outdir, "promo"), exist_ok=True)

    st = Studio()
    manifest = []
    lifted = False
    try:
        st.handshake()
        if not st.tools():
            raise SystemExit("Studio advertises no tools - the MCP toggle is off.")

        print(text_of(st.call("start_stop_play", {"is_start": True})))
        time.sleep(spec["settle"])

        for dm, code in spec["setup"]:
            print("setup:", text_of(st.call("execute_luau", {"code": code, "datamodel_type": dm})))
            time.sleep(spec["settle"])

        raw = text_of(st.call("execute_luau", {
            "code": BOUNDS.replace("__ANCHOR__", spec["anchor"]),
            "datamodel_type": "Server"}))
        if raw.startswith("MISSING"):
            raise SystemExit("could not find %r in the workspace. It holds: %s"
                             % (spec["anchor"], raw.split("|", 1)[1]))
        parts = raw.strip().split("|")
        b = dict(zip(["mnx", "mxx", "mny", "mxy", "mnz", "mxz"], [float(x) for x in parts[3:9]]))
        print("anchor %s: %s parts, x[%.0f,%.0f] y[%.0f,%.0f] z[%.0f,%.0f]"
              % (parts[1], parts[2], b["mnx"], b["mxx"], b["mny"], b["mxy"], b["mnz"], b["mxz"]))

        for shot in spec["shots"]:
            name, cam, look = shot[0], shot[1], shot[2]
            lift = len(shot) > 3 and shot[3]
            if lift and not lifted:
                print("lift:", text_of(st.call("execute_luau",
                                               {"code": LIFT, "datamodel_type": "Client"})))
                lifted = True
                time.sleep(1)
            elif lifted and not lift:
                print("restore:", text_of(st.call("execute_luau",
                                                  {"code": RESTORE, "datamodel_type": "Client"})))
                lifted = False
                time.sleep(1)

            c = [resolve(e, b) for e in cam]
            l = [resolve(e, b) for e in look]
            sub = "promo" if lift else "gameplay"
            path = os.path.join(outdir, sub, name + ".png")
            res = st.call("screen_capture", {
                "capture_id": "shot_" + name,
                "camera_position": c,
                "look_at_position": l,
            })
            saved = save_images(res, path)
            if saved:
                print("  %-16s %s (%d bytes)" % (name, os.path.relpath(saved[0], ROOT),
                                                 os.path.getsize(saved[0])))
                manifest.append({
                    "name": name, "file": os.path.relpath(saved[0], ROOT).replace("\\", "/"),
                    "camera": c, "look_at": l,
                    "fog_lifted": bool(lift),
                    "note": ("PROMOTIONAL: the fog was temporarily removed. No player sees the "
                             "world lit like this." if lift else "As the game actually looks."),
                })
            else:
                print("  %-16s NO IMAGE: %s" % (name, text_of(res)[:120]))
    finally:
        try:
            if lifted:
                print("restore:", text_of(st.call("execute_luau",
                                                  {"code": RESTORE, "datamodel_type": "Client"})))
            if not args.keep_play:
                print(text_of(st.call("start_stop_play", {"is_start": False})))
        except SystemExit:
            print("WARNING: could not restore Studio cleanly - check the lighting and play state")
        st.close()

    if manifest:
        mpath = os.path.join(outdir, "manifest.json")
        with io.open(mpath, "w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
        print("\nwrote", os.path.relpath(mpath, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
