#!/usr/bin/env python3
"""render_test.py -- checks for robloxemu/render.py.

Plain stdlib script, no pytest. Run it:

    py -3 robloxemu/tests/render_test.py

The load-bearing checks are the last three geometry ones: they prove that
`diff_images()` can tell "the scene changed and you can SEE it" apart from
"the scene changed but it is hidden behind a wall" -- the chart_flip /
figure_window / sign_swap bug class that shipped three invisible anomalies.
"""

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # robloxemu/
SCENES = os.path.join(ROOT, "scenes")
RENDER_PY = os.path.join(ROOT, "render.py")
sys.path.insert(0, ROOT)

import render  # noqa: E402

W, H = 480, 270

_results = []


def check(name, fn):
    try:
        detail = fn()
        _results.append((True, name, detail or ""))
    except AssertionError as exc:
        _results.append((False, name, str(exc)))
    except Exception as exc:  # noqa: BLE001 - a crash is a test failure
        _results.append((False, name, "%s: %s" % (type(exc).__name__, exc)))


def scene(name):
    with open(os.path.join(SCENES, name + ".json"), "r", encoding="utf-8") as fh:
        return json.load(fh)


def draw(name_or_dict, w=W, h=H):
    s = scene(name_or_dict) if isinstance(name_or_dict, str) else name_or_dict
    return render.render_scene(s, width=w, height=h)


# --------------------------------------------------------------------------
# Geometry / CFrame convention
# --------------------------------------------------------------------------

def t_cframe_columns():
    """A +90 deg yaw must take the box's local +X to world -Z.

    This pins the row-major-rows / world-space-columns convention. If the
    rotation matrix were read transposed the sign would flip here, and every
    rotated part in every scene would be mirrored.
    """
    c, s = math.cos(math.pi / 2), math.sin(math.pi / 2)
    cf = [5, 6, 7, c, 0, s, 0, 1, 0, -s, 0, c]
    pos, ax, ay, az = render.cframe_axes(cf)
    assert pos == (5, 6, 7), "position mis-parsed: %r" % (pos,)
    assert abs(ax[0] - 0) < 1e-9 and abs(ax[2] - (-1)) < 1e-9, \
        "local +X should map to world -Z, got %r" % (ax,)
    assert abs(ay[1] - 1) < 1e-9, "local +Y should stay +Y, got %r" % (ay,)
    assert abs(az[0] - 1) < 1e-9, "local +Z should map to world +X, got %r" % (az,)
    return "local +X -> %s" % (tuple(round(v, 3) for v in ax),)


def t_box_extents():
    """`size` is full extents, so corners sit at +/- size/2."""
    faces = list(render.box_faces([4, 2, 6], [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]))
    assert len(faces) == 6, "expected 6 faces, got %d" % len(faces)
    xs = [c[0] for _n, q in faces for c in q]
    ys = [c[1] for _n, q in faces for c in q]
    zs = [c[2] for _n, q in faces for c in q]
    assert (min(xs), max(xs)) == (-2, 2), "x extents %r" % ((min(xs), max(xs)),)
    assert (min(ys), max(ys)) == (-1, 1), "y extents %r" % ((min(ys), max(ys)),)
    assert (min(zs), max(zs)) == (-3, 3), "z extents %r" % ((min(zs), max(zs)),)
    return "half-extents 2/1/3 from size 4/2/6"


# --------------------------------------------------------------------------
# Basic rendering
# --------------------------------------------------------------------------

def t_nonblank():
    fb = draw("sample_single_box")
    colors = set()
    data = fb.data
    for i in range(0, len(data), 3):
        colors.add(bytes(data[i:i + 3]))
        if len(colors) > 64:
            break
    assert len(colors) > 8, "image looks blank: only %d distinct colours" % len(colors)

    bg = fb.get(0, 0)
    n = fb.width * fb.height
    non_bg = sum(1 for i in range(0, n * 3, 3)
                 if (data[i], data[i + 1], data[i + 2]) != bg)
    frac = non_bg / n
    assert frac > 0.05, "only %.2f%% of pixels are non-background" % (frac * 100)
    return "%d+ colours, %.1f%% of pixels are geometry" % (len(colors), frac * 100)


def t_default_size():
    fb = render.render_scene(scene("sample_single_box"))
    assert (fb.width, fb.height) == (960, 540), \
        "default size is %dx%d" % (fb.width, fb.height)
    assert len(fb.data) == 960 * 540 * 3, "buffer length mismatch"
    return "default 960x540, %d bytes" % len(fb.data)


def t_png_roundtrip():
    fb = draw("sample_single_box")
    tmp = tempfile.mkdtemp(prefix="robloxemu_render_")
    try:
        path = os.path.join(tmp, "roundtrip.png")
        fb.save(path)
        assert os.path.getsize(path) > 0, "wrote an empty PNG"
        back = render.read_png(path)
        assert (back.width, back.height) == (fb.width, fb.height), "size changed on reload"
        d = render.diff_images(fb, back, tolerance=0)
        assert d == 0.0, "PNG roundtrip is lossy: %.6f of pixels differ" % d
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return "encode -> decode is bit-exact"


# --------------------------------------------------------------------------
# The visibility gate
# --------------------------------------------------------------------------

_cache = {}


def _occ(name):
    if name not in _cache:
        _cache[name] = draw(name)
    return _cache[name]


def t_visible_change():
    d = render.diff_images(_occ("sample_occluder_clean"),
                           _occ("sample_occluder_visible_change"))
    assert d > 0.02, "a box moved in front of the camera only moved %.6f of pixels" % d
    return "moved-into-view box changes %.2f%% of pixels" % (d * 100)


def t_occluded_change_invisible():
    d = render.diff_images(_occ("sample_occluder_clean"),
                           _occ("sample_occluder_hidden_change"))
    assert d < 0.0005, \
        ("a change fully behind an opaque wall changed %.6f of pixels -- the "
         "renderer is leaking hidden geometry" % d)
    return "occluded move+recolour+Neon changes %.6f of pixels" % d


def t_diff_discriminates():
    """The money test: the metric must separate the two cases by a wide margin."""
    clean = _occ("sample_occluder_clean")
    hidden = render.diff_images(clean, _occ("sample_occluder_hidden_change"))
    visible = render.diff_images(clean, _occ("sample_occluder_visible_change"))
    assert visible > 0.02, "visible change too small: %.6f" % visible
    assert hidden < 0.0005, "hidden change too large: %.6f" % hidden
    assert visible > hidden * 100, \
        "hidden %.6f vs visible %.6f -- not separable" % (hidden, visible)
    return "hidden=%.6f  visible=%.6f  (separated by >=100x)" % (hidden, visible)


def t_neon_visible_in_dark():
    """An emissive Neon part must survive near-zero ambient.

    Calibration note: the fixture's anomaly is 1.5 studs across at ~22 studs,
    which is only ~170 px of a 480x270 frame. A real anomaly gate therefore
    wants a threshold around 5e-4, NOT an intuitive 1% -- small props are
    genuinely visible to a player while moving well under 1% of pixels.
    """
    d = render.diff_images(draw("sample_dark_hall_clean"),
                           draw("sample_dark_hall_neon"))
    assert d > 0.0005, \
        "an emissive Neon anomaly is invisible in the dark hall (%.6f)" % d
    return "Neon anomaly at ambient [3,3,5] changes %.3f%% of pixels" % (d * 100)


def t_transparency_blends():
    """transparency 0.5 must actually composite, not just draw the part solid.

    Pixel *counts* cannot show this -- a translucent part still changes every
    pixel it covers, so the naive count is identical to the opaque case (this
    check passed vacuously until the assertion below was added). So compare
    actual pixel VALUES at the centre of the part: with alpha 0.5 over the
    wall, the result must be the midpoint of the clean and opaque renders.
    """
    s = scene("sample_occluder_visible_change")
    for p in s["parts"]:
        if p["name"] == "HiddenBox":
            p["transparency"] = 0.5
    clean = _occ("sample_occluder_clean")
    solid = _occ("sample_occluder_visible_change")
    ghost = draw(s)

    cx, cy = W // 2, H // 2  # the box is centred on the camera axis
    pc, ps, pg = clean.get(cx, cy), solid.get(cx, cy), ghost.get(cx, cy)
    assert pc != ps, "fixture is broken: the opaque box does not cover the centre pixel"
    assert pg != ps, \
        "transparency 0.5 rendered identically to opaque -- alpha is being ignored"
    for ch in range(3):
        want = (pc[ch] + ps[ch]) / 2.0
        assert abs(pg[ch] - want) <= 2, \
            ("channel %d: blended %d, expected ~%.1f (clean %d, opaque %d)"
             % (ch, pg[ch], want, pc[ch], ps[ch]))
    return "centre pixel clean%s + opaque%s -> blended%s" % (pc, ps, pg)


def t_fully_transparent_is_skipped():
    s = scene("sample_occluder_visible_change")
    for p in s["parts"]:
        if p["name"] == "HiddenBox":
            p["transparency"] = 1.0
    d = render.diff_images(_occ("sample_occluder_clean"), draw(s))
    assert d == 0.0, "transparency 1.0 still drew something (%.6f)" % d
    return "transparency 1.0 renders nothing, as in Roblox"


def t_size_mismatch_raises():
    a = draw("sample_single_box", 64, 36)
    b = draw("sample_single_box", 65, 36)
    try:
        render.diff_images(a, b)
    except ValueError:
        return "mismatched sizes raise instead of returning a bogus number"
    raise AssertionError("diff_images silently compared mismatched image sizes")


# --------------------------------------------------------------------------
# CLI end-to-end (this is how CI will actually gate an anomaly)
# --------------------------------------------------------------------------

def t_cli_gate():
    tmp = tempfile.mkdtemp(prefix="robloxemu_cli_")
    try:
        base = os.path.join(tmp, "clean.png")
        rc = subprocess.run(
            [sys.executable, RENDER_PY, os.path.join(SCENES, "sample_occluder_clean.json"),
             "-o", base, "--width", str(W), "--height", str(H), "-q"],
            capture_output=True, text=True)
        assert rc.returncode == 0, "render failed: %s" % rc.stderr.strip()
        assert os.path.exists(base), "CLI did not write the PNG"

        def gate(scene_name):
            return subprocess.run(
                [sys.executable, RENDER_PY, os.path.join(SCENES, scene_name + ".json"),
                 "--width", str(W), "--height", str(H),
                 "--diff", base, "--min-diff", "0.002"],
                capture_output=True, text=True)

        good = gate("sample_occluder_visible_change")
        assert good.returncode == 0, \
            "CLI gate rejected a genuinely visible change: %s" % good.stdout.strip()

        bad = gate("sample_occluder_hidden_change")
        assert bad.returncode == 1, \
            "CLI gate PASSED an invisible anomaly (rc=%d): %s" % (bad.returncode, bad.stdout.strip())
        assert "not visible" in bad.stderr, "gate failed without explaining why"
        return "--min-diff passes the visible anomaly, exit-1s the invisible one"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------

def main():
    checks = [
        ("cframe rotation convention", t_cframe_columns),
        ("box size is full extents", t_box_extents),
        ("render is not blank", t_nonblank),
        ("default image size 960x540", t_default_size),
        ("PNG write/read roundtrip", t_png_roundtrip),
        ("moved box changes the image", t_visible_change),
        ("occluded change is invisible", t_occluded_change_invisible),
        ("diff separates hidden from visible", t_diff_discriminates),
        ("Neon anomaly visible in the dark", t_neon_visible_in_dark),
        ("transparency alpha-blends", t_transparency_blends),
        ("transparency 1.0 draws nothing", t_fully_transparent_is_skipped),
        ("diff rejects size mismatch", t_size_mismatch_raises),
        ("CLI --min-diff gate", t_cli_gate),
    ]
    for name, fn in checks:
        check(name, fn)

    print("=" * 72)
    print("robloxemu render.py -- %d checks" % len(_results))
    print("=" * 72)
    for ok, name, detail in _results:
        print("  %s  %-38s %s" % ("PASS" if ok else "FAIL", name, detail))
    failed = [r for r in _results if not r[0]]
    print("-" * 72)
    print("%d passed, %d failed" % (len(_results) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
