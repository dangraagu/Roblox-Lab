"""Film matched CLEAN / ANOMALY pairs of the observatory hall, and cut them into shorts.

    py -3 tools/film_anomaly.py                 shoot until 4 anomaly types are in the can
    py -3 tools/film_anomaly.py --want 6 --max-passes 40
    py -3 tools/film_anomaly.py --no-render     shoot the stills, don't call the video pipeline

Studio must have Anomaly.rbxlx open with MCP attached - `tools/studio_open.ps1 anomaly-observatory`
does that in one command, and cycling the in-Studio MCP toggle (which that script does) is what
actually attaches it.

WHAT A "PAIR" IS AND WHY IT IS HARD. The spot-the-difference short needs two photographs of the
SAME hall from the SAME camera, one clean and one carrying exactly one anomaly. The game rebuilds
the hall from scratch every pass and rolls clean-or-anomalous privately, so the two halves of a
pair are two different passes minutes apart. Three things have to be pinned down or the pair is a
lie - the viewer would "spot" the wrong thing:

  * WHICH HALL IS ON SCREEN. `beginPass` publishes the roll on the zone model as the attributes
    `Clean`, `AnomalyId` and `Serial` (added for exactly this, and asserted in
    robloxemu/check_anomaly_attrs.luau). This tool reads them. It never guesses from pixels.
  * THE CAMERA. Derived from the zone's own Floor part - never from a bounding box of the whole
    zone, because an anomaly ADDS AND REMOVES PARTS and a bbox-derived camera would therefore
    move between the two halves. It is computed once and then re-verified every pass; if it ever
    drifts the run stops rather than shipping a mismatched pair.
  * EVERYTHING ELSE THAT MOVES. The HUD shows the day counter, which changes every pass, and the
    player's avatar idles in the middle of the frame. Both would read as "the difference". The
    HUD is switched off for the shot and back on afterwards, and the avatar is parked behind the
    camera. Both are recorded in the manifest.

HONESTY. These are real Studio captures of the real game, so they go through the pipeline as
`--source capture` and carry no promotional stamp. The only staging is the HUD and the avatar,
both stated above and in the manifest. Nothing in the hall itself is touched.

The gate that makes a pair publishable, measured rather than assumed: two CLEAN passes are also
photographed, and the pixel difference between them is the noise floor (drifting dust motes, a
particle or two). A pair only ships if its own difference is well clear of that floor AND the
difference actually lands inside the crop the vertical short will take. An anomaly that is real
but invisible in frame - something close to the camera and off to the side - is skipped and said
so, rather than shipped as a puzzle with no answer.

Output: anomaly-observatory/marketing/pairs/<anomalyId>/{clean.png,anomaly.png,spot.mp4}
plus marketing/pairs/manifest.json.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from studio_mcp import Studio, text_of, save_images  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "anomaly-observatory")
OUT = os.path.join(GAME, "marketing", "pairs")
PIPELINE = os.path.join(ROOT, "robloxemu", "pipeline.py")

# ---------------------------------------------------------------------------- Luau, run in Studio

# Everything the tool needs to know about this instant, in one round trip. The Floor is the anchor
# for the camera: it is the one part whose POSITION and SIZE no applier changes (floor_tilt turns
# it about its own centre, which moves neither), so a camera derived from it is identical for
# every pass. HALL_LEN is recovered from the floor's own size rather than copied from the server
# script, so the two cannot drift apart.
PASS_STATE = """
local zone = nil
for _, c in workspace:GetChildren() do
    if string.match(c.Name, "^Concourse_") then zone = c end
end
if not zone then return "NOZONE" end
local floor = zone:FindFirstChild("Floor")
if not (floor and floor:IsA("BasePart")) then return "NOFLOOR" end
local adv = zone:FindFirstChild("AdvancePad")
local back = zone:FindFirstChild("BackPad")
if not (adv and back) then return "NOPADS" end
local clean = zone:GetAttribute("Clean")
local id = zone:GetAttribute("AnomalyId")
local serial = zone:GetAttribute("Serial")
if clean == nil then return "NOATTRS" end
return table.concat({
    "OK", zone.Name,
    tostring(clean), tostring(id), tostring(serial),
    string.format("%f,%f,%f", floor.Position.X, floor.Position.Y, floor.Position.Z),
    string.format("%f,%f,%f", floor.Size.X, floor.Size.Y, floor.Size.Z),
    string.format("%f,%f,%f", adv.Position.X, adv.Position.Y + 1, adv.Position.Z + 5),
    string.format("%f,%f,%f", back.Position.X, back.Position.Y + 1, back.Position.Z + 5),
}, "|")
"""

# The catalog's display names, straight from the game's own Config so a clip can never be
# captioned with a name this build does not use.
NAMES = """
local C = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local out = {}
for _, e in C.Anomaly.Catalog do out[e.id] = e.name end
return game:GetService("HttpService"):JSONEncode(out)
"""

# Park the avatar behind the camera. beginPass teleports it to the start pad every pass, which is
# in front of the lens, so this runs again before every shot.
#
# STOPPING it is the part that matters, and the first version did not. `character_navigation`
# leaves a walk order running on the Humanoid; teleporting the body does not cancel it, so the
# avatar strolled back down the hall and stood at the far end - in some frames and not others.
# The first pairs shot with this tool therefore had a person-shaped blob as their brightest
# difference, next to the anomaly, which is precisely the puzzle-ruining thing the whole rig is
# supposed to prevent. Cancel the walk, then anchor: an anchored root part cannot drift.
PARK = """
local plr = game:GetService("Players"):GetPlayers()[1]
local char = plr and plr.Character
local hrp = char and char:FindFirstChild("HumanoidRootPart")
if not hrp then return "NOCHAR" end
local hum = char:FindFirstChildOfClass("Humanoid")
if hum then
    hum:MoveTo(hrp.Position)
    hum:Move(Vector3.new(0, 0, 0), false)
end
hrp.Anchored = true
hrp.CFrame = CFrame.new(__X__, __Y__, __Z__)
return "parked"
"""

# Let it walk again, or the navigation to the decision pad goes nowhere.
UNPARK = """
local plr = game:GetService("Players"):GetPlayers()[1]
local char = plr and plr.Character
local hrp = char and char:FindFirstChild("HumanoidRootPart")
if not hrp then return "NOCHAR" end
hrp.Anchored = false
return "released"
"""

# The HUD carries the day counter, which is different in the two halves of every pair. Switch it
# off for the shot; the saved state is restored in the `finally` below even if a capture fails.
HUD_OFF = """
local plr = game:GetService("Players").LocalPlayer
local gui = plr and plr:FindFirstChild("PlayerGui")
if not gui then return "NOGUI" end
_G.__filmHud = _G.__filmHud or {}
local n = 0
for _, c in gui:GetDescendants() do
    if c:IsA("ScreenGui") and c.Enabled then
        if _G.__filmHud[c] == nil then _G.__filmHud[c] = true end
        c.Enabled = false
        n += 1
    end
end
return "hid " .. n
"""

# Where the avatar actually is. The walk has to be CONFIRMED, not assumed.
WHERE = """
local plr = game:GetService("Players").LocalPlayer
local hrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
return hrp and string.format("%.1f,%.1f,%.1f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z) or "?"
"""

HUD_ON = """
local saved = _G.__filmHud
if not saved then return "nothing to restore" end
local n = 0
for gui in saved do
    if gui and gui.Parent then gui.Enabled = true; n += 1 end
end
_G.__filmHud = nil
return "restored " .. n
"""


# ------------------------------------------------------------------------------- image measuring

def _load(path):
    from PIL import Image
    return Image.open(path).convert("RGB")


def crop_window(width, height, fmt):
    """The slice `pipeline.py` will keep for this format.

    It scales to COVER and then centre-crops, so for a 1920x798 capture the vertical short keeps
    only the middle ~23% of the width. An anomaly outside that slice is invisible in the finished
    clip no matter how obvious it is in the still, which is why every measurement below is taken
    INSIDE this window rather than over the whole frame. (The potted plant, whose Grass material
    is regenerated with a fresh random speckle every rebuild, sits just outside the vertical
    window and would otherwise dominate the numbers on its own.)
    """
    fw, fh = {"vertical": (1080, 1920), "square": (1080, 1080), "wide": (1920, 1080)}[fmt]
    scale = max(fw / float(width), fh / float(height))
    kept_w = min(width, fw / scale)
    kept_h = min(height, fh / scale)
    x0 = (width - kept_w) / 2.0
    y0 = (height - kept_h) / 2.0
    return (int(x0), int(y0), int(x0 + kept_w), int(y0 + kept_h))


def diff_stats(a_path, b_path, window=None, threshold=28):
    """How different are two frames inside `window`, and WHERE?

    Returns (changed_fraction, bbox in FULL-frame coordinates or None). A pixel counts as changed
    when its largest channel difference clears `threshold` - high enough to ignore the shimmer
    around the neon light fixtures, low enough that a recoloured wall panel or a missing telescope
    lights up solidly.
    """
    from PIL import ImageChops
    a, b = _load(a_path), _load(b_path)
    if a.size != b.size:
        return 1.0, (0, 0, a.size[0], a.size[1])
    if window:
        a, b = a.crop(window), b.crop(window)
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v >= threshold else 0)
    changed = d.histogram()[255] / float(a.size[0] * a.size[1])
    bbox = d.getbbox()
    if bbox and window:
        bbox = (bbox[0] + window[0], bbox[1] + window[1],
                bbox[2] + window[0], bbox[3] + window[1])
    return changed, bbox


# ---------------------------------------------------------------------------------------- driving

def parse_state(raw):
    parts = raw.strip().split("|")
    if parts[0] != "OK":
        return None, raw.strip()
    def triple(s):
        return [float(v) for v in s.split(",")]
    return {
        "zone": parts[1],
        "clean": parts[2] == "true",
        "anomaly_id": None if parts[3] == "nil" else parts[3],
        "serial": int(float(parts[4])),
        "floor_pos": triple(parts[5]),
        "floor_size": triple(parts[6]),
        "advance_pad": triple(parts[7]),
        "back_pad": triple(parts[8]),
    }, None


def camera_for(state):
    """Camera and look-at, from the Floor alone.

    The hall is built at `origin` and runs 80 studs along -Z; the floor is centred half way down
    it and overhangs both ends by 10, so origin and the hall's length both fall out of the floor's
    own position and size. The camera stands just inside the near end at eye height and looks at
    the end wall - the view the player actually has.
    """
    fx, fy, fz = state["floor_pos"]
    _, sy, sz = state["floor_size"]
    hall_len = sz - 20.0
    ox, oy, oz = fx, fy, fz + sz / 2.0 - 10.0
    eye = oy + sy / 2.0 + 7.0
    return ([ox, eye, oz + 4.0], [ox, eye, oz - (hall_len + 6.0)], [ox, oy, oz])


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--want", type=int, default=4, help="how many anomaly types to capture")
    ap.add_argument("--max-passes", type=int, default=30, help="give up after this many passes")
    ap.add_argument("--settle", type=float, default=20.0, help="seconds to wait for the world")
    ap.add_argument("--warmup-passes", type=int, default=2,
                    help="photograph nothing for this many passes. Studio's renderer is still "
                         "settling for the first half-minute of a Play session - measured, two "
                         "CLEAN passes shot either side of that boundary differed by 3%% of the "
                         "frame, which is more than most anomalies do")
    ap.add_argument("--keep-play", action="store_true", help="leave Studio in Play mode")
    ap.add_argument("--no-render", action="store_true", help="skip the pipeline.py spot step")
    ap.add_argument("--skip", default="flicker_hall",
                    help="comma-separated anomaly ids that a STILL cannot show (default: the "
                         "strobing light, which is identical to clean for half of every cycle)")
    args = ap.parse_args()

    skip = {s.strip() for s in args.skip.split(",") if s.strip()}
    os.makedirs(OUT, exist_ok=True)
    raw_dir = os.path.join(OUT, "_raw")
    os.makedirs(raw_dir, exist_ok=True)

    st = Studio()
    camera = look = origin = None
    cleans = []          # every clean frame we caught, newest last
    anomalies = {}       # id -> {"file":..., "serial":...}
    log = []
    hud_hidden = False
    try:
        st.handshake()
        if not st.tools():
            raise SystemExit("Studio advertises no tools - the MCP toggle is off. Run "
                             "tools/studio_open.ps1 anomaly-observatory")

        print(text_of(st.call("start_stop_play", {"is_start": True})))
        time.sleep(args.settle)

        names = {}
        try:
            names = json.loads(text_of(st.call("execute_luau",
                                               {"code": NAMES, "datamodel_type": "Server"})))
        except (ValueError, SystemExit):
            print("  (could not read the anomaly catalog names; captions will use the raw id)")

        for p in range(1, args.max_passes + 1):
            raw = text_of(st.call("execute_luau",
                                  {"code": PASS_STATE, "datamodel_type": "Server"}))
            state, err = parse_state(raw)
            if state is None:
                raise SystemExit("could not read the pass. Studio said: %s" % err[:200])

            cam, lk, org = camera_for(state)
            if camera is None:
                camera, look, origin = cam, lk, org
                print("zone %s at origin %.0f,%.0f,%.0f" % (state["zone"], *origin))
                print("camera %.1f,%.1f,%.1f -> %.1f,%.1f,%.1f" % (*camera, *look))
            elif max(abs(a - b) for a, b in zip(cam, camera)) > 0.01:
                raise SystemExit(
                    "the camera moved between passes (%s -> %s). Every pair would be shot from a "
                    "different place, which is exactly the thing this tool exists to prevent."
                    % (camera, cam))

            label = state["anomaly_id"] or "clean"
            warming = p <= args.warmup_passes
            if state["clean"]:
                # A handful of clean frames SPREAD ACROSS THE RUN, not a burst at the start: each
                # anomaly is paired with the clean pass nearest it in time, so what matters is
                # coverage, and photographing every clean pass just spends minutes.
                want_this = (not warming) and len(cleans) < 5 and (
                    not cleans or state["serial"] - cleans[-1]["serial"] >= 3)
            else:
                want_this = (not warming) and label not in anomalies and label not in skip

            if want_this:
                # HUD off and avatar parked, every time - both come back on their own between
                # passes (a State push re-enables the HUD; beginPass teleports the avatar).
                st.call("execute_luau", {"code": HUD_OFF, "datamodel_type": "Client"})
                hud_hidden = True
                park = PARK.replace("__X__", "%f" % origin[0]) \
                           .replace("__Y__", "%f" % (origin[1] + 4)) \
                           .replace("__Z__", "%f" % (origin[2] + 7))
                st.call("execute_luau", {"code": park, "datamodel_type": "Server"})
                time.sleep(0.6)

                fname = "%s_s%d.png" % (label, state["serial"])
                path = os.path.join(raw_dir, fname)
                res = st.call("screen_capture", {
                    "capture_id": "film_%s" % fname,
                    "camera_position": camera,
                    "look_at_position": look,
                })
                saved = save_images(res, path)
                if not saved:
                    print("  pass %-2d %-16s NO IMAGE: %s" % (p, label, text_of(res)[:100]))
                else:
                    print("  pass %-2d %-16s captured %s" % (p, label, fname))
                    if state["clean"]:
                        cleans.append({"file": saved[0], "serial": state["serial"]})
                    else:
                        anomalies[label] = {"file": saved[0], "serial": state["serial"]}
            else:
                print("  pass %-2d %-16s (%s)" % (p, label,
                                                  "warm-up" if warming else "skipped"))
            log.append({"pass": p, "serial": state["serial"], "clean": state["clean"],
                        "anomaly_id": state["anomaly_id"], "captured": bool(want_this)})

            if len(cleans) >= 2 and len(anomalies) >= args.want:
                break

            # Answer the pass CORRECTLY, from the attribute we just read, so the loop keeps
            # rolling without the 2.5s death beat and the screen flash a wrong call triggers.
            #
            # WALK, CHECK YOU ARRIVED, THEN PRESS - the same lesson tools/playtest.py records.
            # A prompt is only armed within 12 studs of its pad, and the character is teleported
            # back to the start every time a pass resolves, so a press issued after a walk that
            # did not finish lands from 75 studs away and does nothing. Without the arrival check
            # this loop stalled: it re-photographed the same serial twice and burned ten minutes
            # on four passes.
            st.call("execute_luau", {"code": UNPARK, "datamodel_type": "Server"})
            key = "E" if state["clean"] else "Q"
            target = state["advance_pad"] if state["clean"] else state["back_pad"]
            advanced = False
            for attempt in range(3):
                st.call("character_navigation", {
                    "datamodel_type": "Client", "x": target[0], "y": target[1], "z": target[2],
                    "speed_multiplier": 3.0})
                here = text_of(st.call("execute_luau",
                                       {"code": WHERE, "datamodel_type": "Client"})).strip()
                try:
                    px, py, pz = [float(v) for v in here.split(",")]
                    reach = ((px - target[0]) ** 2 + (py - target[1]) ** 2
                             + (pz - target[2]) ** 2) ** 0.5
                except ValueError:
                    reach = 999.0
                if reach > 8:
                    print("       (at %s, %.0f studs short of the pad - walking again)"
                          % (here, reach))
                    continue
                st.call("user_keyboard_input", {"datamodel_type": "Client", "actions": [
                    {"action": "wait", "wait_time_ms": 400},
                    {"action": "keyDown", "key_code": key},
                    {"action": "wait", "wait_time_ms": 200},
                    {"action": "keyUp", "key_code": key},
                    {"action": "wait", "wait_time_ms": 2500},
                ]})
                nxt, _ = parse_state(text_of(st.call(
                    "execute_luau", {"code": PASS_STATE, "datamodel_type": "Server"})))
                if nxt and nxt["serial"] != state["serial"]:
                    advanced = True
                    break
                print("       (the %s press did not take; trying again)" % key)
            if not advanced:
                print("       GAVE UP on pass %d - the loop would not advance" % p)
    finally:
        try:
            if hud_hidden:
                print("HUD:", text_of(st.call("execute_luau",
                                              {"code": HUD_ON, "datamodel_type": "Client"})))
            if not args.keep_play:
                print(text_of(st.call("start_stop_play", {"is_start": False})))
        except SystemExit:
            print("WARNING: could not restore Studio cleanly - check Play mode and the HUD")
        st.close()

    if not cleans or not anomalies:
        raise SystemExit("nothing to pair: %d clean frames, %d anomalies"
                         % (len(cleans), len(anomalies)))

    # ------------------------------------------------------------------ pair, measure, and render
    with _load(cleans[0]["file"]) as im:
        W, H = im.size

    if len(cleans) < 2:
        raise SystemExit("only one clean frame was caught, so there is no measured noise floor "
                         "and no pair can be called publishable. Run again with more passes.")

    entries, made = [], []
    for aid in sorted(anomalies):
        a = anomalies[aid]
        # Pair each anomaly with the CLEAN pass nearest it in time, and take the noise floor from
        # the two clean passes nearest it. Anything that drifts slowly - and the renderer does -
        # then affects both halves of the pair equally instead of showing up as the difference.
        near = sorted(cleans, key=lambda c: abs(c["serial"] - a["serial"]))
        ref, other = near[0], near[1]

        pair_dir = os.path.join(OUT, aid)
        os.makedirs(pair_dir, exist_ok=True)
        clean_png = os.path.join(pair_dir, "clean.png")
        anom_png = os.path.join(pair_dir, "anomaly.png")
        shutil.copyfile(ref["file"], clean_png)
        shutil.copyfile(a["file"], anom_png)

        # Try the narrowest format first. Each candidate is judged in its OWN crop, against a
        # noise floor measured in the same crop, because that is the only region the clip shows.
        fmt = window = bbox = None
        changed = noise = 0.0
        tried = []
        for candidate in ("vertical", "square", "wide"):
            w = crop_window(W, H, candidate)
            ch, bb = diff_stats(clean_png, anom_png, w)
            nz, _ = diff_stats(ref["file"], other["file"], w)
            tried.append("%s %.3f%% vs %.3f%% floor" % (candidate, ch * 100, nz * 100))
            if ch >= max(nz * 2.0, 0.0015):
                fmt, window, changed, noise, bbox = candidate, w, ch, nz, bb
                break

        entry = {
            "anomaly_id": aid,
            "name": names.get(aid, aid),
            "clean": os.path.relpath(clean_png, ROOT).replace("\\", "/"),
            "anomaly": os.path.relpath(anom_png, ROOT).replace("\\", "/"),
            "clean_serial": ref["serial"],
            "anomaly_serial": a["serial"],
            "noise_floor_from_serials": [ref["serial"], other["serial"]],
            "camera": camera,
            "look_at": look,
            "zone_origin": origin,
            "capture_size": [W, H],
            "crop_window": list(window) if window else None,
            "changed_fraction_in_crop": round(changed, 6),
            "noise_floor_in_crop": round(noise, 6),
            "diff_bbox": list(bbox) if bbox else None,
            "format": fmt,
            "measured": tried,
            "verdict": "ok" if fmt else "not clearly visible in any crop",
        }

        if not fmt:
            print("  %-16s SKIP - not clearly visible in any crop (%s)" % (aid, "; ".join(tried)))
            entries.append(entry)
            continue

        print("  %-16s %s, %.3f%% of the crop changed (floor %.3f%%), bbox %s"
              % (aid, fmt, changed * 100, noise * 100, bbox))
        if not args.no_render:
            out_mp4 = os.path.join(pair_dir, "spot.mp4")
            cmd = [sys.executable, PIPELINE, "spot", clean_png, anom_png, "-o", out_mp4,
                   "--format", fmt, "--source", "capture",
                   "--name", names.get(aid, aid)]
            proc = subprocess.run(cmd, capture_output=True, text=True, cwd=os.path.dirname(PIPELINE))
            if proc.returncode != 0:
                print("     pipeline failed: %s" % (proc.stderr or proc.stdout)[-300:])
                entry["verdict"] = "pipeline failed"
            else:
                entry["clip"] = os.path.relpath(out_mp4, ROOT).replace("\\", "/")
                print("     %s" % proc.stdout.strip())
                made.append(aid)
        entries.append(entry)

    manifest = {
        "game": "anomaly-observatory",
        "source": "capture",
        "what": ("Real Roblox Studio captures of the running game. The pair for each anomaly is "
                 "the SAME camera on the SAME hall: the clean half is one pass, the anomalous "
                 "half another, matched by the Clean/AnomalyId attributes beginPass writes on "
                 "the zone."),
        "staging": ["the player HUD was switched off for the shot (it shows a day counter that "
                    "changes every pass, which would read as the difference)",
                    "the avatar was parked behind the camera for the same reason",
                    "nothing in the hall itself was touched, and the lighting was not lifted"],
        "camera": camera,
        "look_at": look,
        "zone_origin": origin,
        "capture_size": [W, H],
        "gate": ("a pair ships only if the difference inside the crop the clip actually shows is "
                 "at least twice what two CLEAN passes differ by in the same crop, and at least "
                 "0.15% of it. Both numbers are per pair, in `measured`."),
        "clean_frames": [{"file": os.path.relpath(c["file"], ROOT).replace("\\", "/"),
                          "serial": c["serial"]} for c in cleans],
        "passes": log,
        "pairs": entries,
    }
    mpath = os.path.join(OUT, "manifest.json")
    with io.open(mpath, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("\nwrote %s" % os.path.relpath(mpath, ROOT))
    print("%d clip%s: %s" % (len(made), "" if len(made) == 1 else "s", ", ".join(made) or "none"))
    return 0 if made else 1


if __name__ == "__main__":
    sys.exit(main())
