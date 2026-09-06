#!/usr/bin/env python3
"""render.py -- scene JSON -> PNG, for robloxemu.

Consumes the scene JSON contract described in SPEC.md and produces a reference
image. Every part is a BOX, so this is a deliberately small, honest renderer:

  * right-handed look-at camera, +Y up, vertical FOV, perspective projection
  * each box -> 8 world corners -> 6 quad faces
  * painter's algorithm (faces sorted far -> near by centroid distance)
  * flat per-face Lambert + ambient + cheap point lights
  * alpha blending for `transparency`, linear distance fog toward `fogColor`
  * `material == "Neon"` renders unshaded at full colour (it is emissive)

NOT pixel-accurate to Roblox and never to be passed off as a gameplay
screenshot -- see SPEC.md.

Known simplifications (all deliberate):
  * Backfaces are always culled, so a camera placed INSIDE a solid part sees
    nothing. Rooms must be built from separate wall/floor/ceiling parts (as
    our halls are) rather than one hollow box. This fails safe: an empty
    render diffs to 0 and trips the --min-diff gate rather than passing.
  * Shading is flat per sub-quad, so large surfaces show faint banding under
    point lights or fog. Raise --subdiv for a smoother gradient.
  * No shadows, no z-buffer. Painter's algorithm is exact for our separated
    convex boxes but will misorder deeply interpenetrating parts.
  * `atmosphereDensity` is parsed but ignored; fog uses fogStart..fogEnd.

The highest-value entry point is `diff_images(a, b)`: render the clean hall and
the anomalous hall from the same camera and assert the images differ by more
than a threshold. That is how we stop shipping invisible anomalies like
chart_flip / figure_window / sign_swap.

DEPENDENCIES: none. PNG encode/decode is done by hand with `zlib` + `struct`.
Pillow, if installed, is used only as a fallback for reading PNG variants the
built-in decoder does not handle (interlaced / 16-bit / palette).

CLI:
    py -3 render.py <scene.json> [-o out.png] [--width W] [--height H]
    py -3 render.py <scene.json> --diff other.png [--min-diff 0.002]
    py -3 render.py <a.png>      --diff <b.png>
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import zlib

# --------------------------------------------------------------------------
# Tunables
# --------------------------------------------------------------------------

DEFAULT_WIDTH = 960
DEFAULT_HEIGHT = 540
NEAR_PLANE = 0.05

# Fixed key light: direction *towards* the light. A high front-left sun, so
# box faces separate from each other instead of reading as one flat blob.
KEY_DIR = (0.4243, 0.7543, 0.5001)  # normalized (0.45, 0.80, 0.53)
# Weak sky/ground hemisphere fill so nothing is pitch black in a dark hall.
FILL_STRENGTH = 0.12
# Colour that `reflectance` mixes towards (a stand-in for the sky).
SKY_COLOR = (0.78, 0.82, 0.90)

# Face tessellation: split a face into sub-quads so per-face flat shading
# still produces a gradient under point lights / fog. Sub-quad target edge
# length in studs, and the per-axis cap.
SUBDIV_TARGET_STUDS = 6.0
DEFAULT_SUBDIV = 4

DEFAULT_TOLERANCE = 8  # per-channel abs difference that still counts as "same"


# --------------------------------------------------------------------------
# Tiny vector helpers (plain tuples -- no numpy needed)
# --------------------------------------------------------------------------

def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def vlen(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def vnorm(a):
    n = vlen(a)
    if n < 1e-12:
        return (0.0, 0.0, 0.0)
    return (a[0] / n, a[1] / n, a[2] / n)


def clamp01(x):
    if x < 0.0:
        return 0.0
    if x > 1.0:
        return 1.0
    return x


# --------------------------------------------------------------------------
# Framebuffer + hand-rolled PNG codec
# --------------------------------------------------------------------------

class Framebuffer:
    """RGB8 pixel buffer. `data` is a flat bytearray of length w*h*3."""

    __slots__ = ("width", "height", "data")

    def __init__(self, width, height, fill=(0, 0, 0)):
        self.width = int(width)
        self.height = int(height)
        self.data = bytearray(bytes(fill) * (self.width * self.height))

    def __eq__(self, other):
        return (isinstance(other, Framebuffer)
                and self.width == other.width
                and self.height == other.height
                and self.data == other.data)

    def get(self, x, y):
        i = (y * self.width + x) * 3
        return (self.data[i], self.data[i + 1], self.data[i + 2])

    def save(self, path):
        write_png(path, self.width, self.height, self.data)
        return path


def _png_chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


def write_png(path, width, height, rgb):
    """Write RGB8 bytes as a non-interlaced PNG. Pure stdlib."""
    stride = width * 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw += rgb[y * stride:(y + 1) * stride]
    out = [b"\x89PNG\r\n\x1a\n",
           _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
           _png_chunk(b"IDAT", zlib.compress(bytes(raw), 6)),
           _png_chunk(b"IEND", b"")]
    with open(path, "wb") as fh:
        fh.write(b"".join(out))


def _decode_png(blob):
    """Decode 8-bit non-interlaced PNG (gray/GA/RGB/RGBA) -> Framebuffer."""
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    pos = 8
    width = height = depth = ctype = interlace = None
    idat = bytearray()
    while pos < len(blob):
        (length,) = struct.unpack(">I", blob[pos:pos + 4])
        tag = blob[pos + 4:pos + 8]
        payload = blob[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, ctype, _comp, _filt, interlace = \
                struct.unpack(">IIBBBBB", payload)
        elif tag == b"IDAT":
            idat += payload
        elif tag == b"IEND":
            break
    if depth != 8 or interlace != 0 or ctype not in (0, 2, 4, 6):
        raise ValueError(
            "unsupported PNG (depth=%s ctype=%s interlace=%s)" % (depth, ctype, interlace))

    channels = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    if len(raw) < height * (stride + 1):
        raise ValueError("truncated PNG image data")

    out = bytearray(width * height * 3)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ft != 0:
            raise ValueError("bad PNG filter type %d" % ft)
        prev = line

        o = y * width * 3
        if channels == 3:
            out[o:o + width * 3] = line
        elif channels == 4:
            for x in range(width):
                s = x * 4
                out[o + x * 3:o + x * 3 + 3] = line[s:s + 3]
        elif channels == 1:
            for x in range(width):
                v = line[x]
                out[o + x * 3] = v
                out[o + x * 3 + 1] = v
                out[o + x * 3 + 2] = v
        else:  # gray + alpha
            for x in range(width):
                v = line[x * 2]
                out[o + x * 3] = v
                out[o + x * 3 + 1] = v
                out[o + x * 3 + 2] = v

    fb = Framebuffer(width, height)
    fb.data = out
    return fb


def read_png(path):
    """Load a PNG into a Framebuffer. Falls back to Pillow for exotic files."""
    with open(path, "rb") as fh:
        blob = fh.read()
    try:
        return _decode_png(blob)
    except ValueError:
        try:
            from PIL import Image  # optional, only for formats we can't decode
        except ImportError:
            raise
        with Image.open(path) as im:
            im = im.convert("RGB")
            fb = Framebuffer(im.width, im.height)
            fb.data = bytearray(im.tobytes())
            return fb


# --------------------------------------------------------------------------
# Camera
# --------------------------------------------------------------------------

class Camera:
    """Right-handed look-at camera, up = +Y, vertical FOV in degrees."""

    def __init__(self, pos, look, fov_deg, width, height):
        self.pos = tuple(float(v) for v in pos)
        forward = vnorm(vsub(look, self.pos))
        if vlen(forward) < 1e-9:
            forward = (0.0, 0.0, -1.0)
        # Degenerate when looking straight up/down: pick a different reference.
        up_ref = (0.0, 0.0, -1.0) if abs(forward[1]) > 0.9999 else (0.0, 1.0, 0.0)
        self.right = vnorm(vcross(forward, up_ref))
        self.up = vcross(self.right, forward)
        self.forward = forward

        fov = math.radians(max(1.0, min(179.0, float(fov_deg))))
        self.focal = (height * 0.5) / math.tan(fov * 0.5)  # square pixels
        self.cx = width * 0.5
        self.cy = height * 0.5

    def to_view(self, p):
        """World point -> (x_right, y_up, depth). depth > 0 is in front."""
        d = vsub(p, self.pos)
        return (vdot(d, self.right), vdot(d, self.up), vdot(d, self.forward))

    def project(self, v):
        """View-space point -> screen pixel coords."""
        inv = self.focal / v[2]
        return (self.cx + v[0] * inv, self.cy - v[1] * inv)


def clip_near(view_poly):
    """Sutherland-Hodgman clip of a view-space polygon against depth >= NEAR."""
    out = []
    n = len(view_poly)
    for i in range(n):
        cur = view_poly[i]
        nxt = view_poly[(i + 1) % n]
        cur_in = cur[2] >= NEAR_PLANE
        nxt_in = nxt[2] >= NEAR_PLANE
        if cur_in:
            out.append(cur)
        if cur_in != nxt_in:
            t = (NEAR_PLANE - cur[2]) / (nxt[2] - cur[2])
            out.append((cur[0] + (nxt[0] - cur[0]) * t,
                        cur[1] + (nxt[1] - cur[1]) * t,
                        NEAR_PLANE))
    return out


# --------------------------------------------------------------------------
# Geometry: box -> faces
# --------------------------------------------------------------------------

# (local outward normal, four local corner sign-triples)
_BOX_FACES = (
    ((1, 0, 0), ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1))),
    ((-1, 0, 0), ((-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1))),
    ((0, 1, 0), ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1))),
    ((0, -1, 0), ((-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1))),
    ((0, 0, 1), ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))),
    ((0, 0, -1), ((1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1))),
)


def cframe_axes(cf):
    """Unpack a 12-number CFrame:GetComponents() list.

    Returns (position, right_axis, up_axis, back_axis). The rotation matrix is
    row-major and maps LOCAL -> WORLD, so the columns are the world-space
    images of the local X/Y/Z axes.
    """
    if cf is None or len(cf) < 12:
        pos = tuple(float(v) for v in (cf or (0, 0, 0))[:3]) if cf else (0.0, 0.0, 0.0)
        while len(pos) < 3:
            pos = pos + (0.0,)
        return pos, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
    c = [float(v) for v in cf]
    pos = (c[0], c[1], c[2])
    # rows: R00 R01 R02 / R10 R11 R12 / R20 R21 R22
    ax = (c[3], c[6], c[9])    # column 0 = local +X in world
    ay = (c[4], c[7], c[10])   # column 1 = local +Y in world
    az = (c[5], c[8], c[11])   # column 2 = local +Z in world
    return pos, ax, ay, az


def box_faces(size, cframe):
    """Yield (world_normal, [4 world corners]) for the 6 faces of a box."""
    hx, hy, hz = (float(size[0]) * 0.5, float(size[1]) * 0.5, float(size[2]) * 0.5)
    pos, ax, ay, az = cframe_axes(cframe)

    def to_world(sx, sy, sz):
        return (pos[0] + ax[0] * sx * hx + ay[0] * sy * hy + az[0] * sz * hz,
                pos[1] + ax[1] * sx * hx + ay[1] * sy * hy + az[1] * sz * hz,
                pos[2] + ax[2] * sx * hx + ay[2] * sy * hy + az[2] * sz * hz)

    for local_n, corners in _BOX_FACES:
        nx, ny, nz = local_n
        normal = vnorm((ax[0] * nx + ay[0] * ny + az[0] * nz,
                        ax[1] * nx + ay[1] * ny + az[1] * nz,
                        ax[2] * nx + ay[2] * ny + az[2] * nz))
        yield normal, [to_world(*c) for c in corners]


def subdivide_quad(quad, max_n):
    """Split a planar quad into a grid of sub-quads (bilinear on the corners)."""
    if max_n <= 1:
        return [quad]
    p0, p1, p2, p3 = quad
    # p0->p1 is one edge direction (u), p0->p3 the other (v).
    nu = max(1, min(max_n, int(vlen(vsub(p1, p0)) / SUBDIV_TARGET_STUDS)))
    nv = max(1, min(max_n, int(vlen(vsub(p3, p0)) / SUBDIV_TARGET_STUDS)))
    if nu == 1 and nv == 1:
        return [quad]

    def corner(u, v):
        # bilinear: p0 + u*(p1-p0) + v*(p3-p0) + u*v*(p2-p1-p3+p0)
        a = vadd(p0, vmul(vsub(p1, p0), u))
        b = vadd(p3, vmul(vsub(p2, p3), u))
        return vadd(a, vmul(vsub(b, a), v))

    out = []
    for j in range(nv):
        v0, v1 = j / nv, (j + 1) / nv
        for i in range(nu):
            u0, u1 = i / nu, (i + 1) / nu
            out.append((corner(u0, v0), corner(u1, v0),
                        corner(u1, v1), corner(u0, v1)))
    return out


# --------------------------------------------------------------------------
# Scene parsing
# --------------------------------------------------------------------------

def _col(value, default):
    if not value:
        return default
    try:
        return (clamp01(float(value[0]) / 255.0),
                clamp01(float(value[1]) / 255.0),
                clamp01(float(value[2]) / 255.0))
    except (TypeError, ValueError, IndexError):
        return default


def _vec(value, default):
    if not value:
        return default
    try:
        return (float(value[0]), float(value[1]), float(value[2]))
    except (TypeError, ValueError, IndexError):
        return default


def parse_lighting(scene):
    lit = scene.get("lighting") or {}
    fog_end = lit.get("fogEnd")
    fog_end = float(fog_end) if fog_end is not None else 1e9
    fog_start = float(lit.get("fogStart", 0.0))
    if fog_end <= fog_start:
        fog_end = fog_start + 1e-6
    return {
        "ambient": _col(lit.get("ambient"), (0.16, 0.16, 0.18)),
        "brightness": float(lit.get("brightness", 1.0)),
        "fog_start": fog_start,
        "fog_end": fog_end,
        "fog_color": _col(lit.get("fogColor"), (0.06, 0.07, 0.10)),
        "fog_active": fog_end < 1e8,
    }


def parse_lights(scene):
    out = []
    for l in scene.get("lights") or []:
        if l.get("enabled") is False:
            continue
        rng = float(l.get("range", 16.0))
        if rng <= 0:
            continue
        out.append({
            "pos": _vec(l.get("pos"), (0.0, 0.0, 0.0)),
            "color": _col(l.get("color"), (1.0, 1.0, 1.0)),
            "brightness": float(l.get("brightness", 1.0)),
            "range": rng,
        })
    return out


# --------------------------------------------------------------------------
# Shading
# --------------------------------------------------------------------------

def shade_face(normal, centroid, base_color, material, reflectance, lit, lights):
    """Flat per-face shading -> (r, g, b) floats in 0..1, pre-fog."""
    if "neon" in material:
        # Emissive in Roblox: full unshaded colour, plus a touch of bloom so it
        # reads as a light source. Several anomalies are Neon parts.
        return tuple(clamp01(c + 0.15 * (1.0 - c)) for c in base_color)

    amb = lit["ambient"]
    key = max(0.0, vdot(normal, KEY_DIR)) * max(0.0, lit["brightness"])
    fill = FILL_STRENGTH * (0.5 + 0.5 * normal[1])

    r = amb[0] + key + fill
    g = amb[1] + key + fill
    b = amb[2] + key + fill

    for lg in lights:
        d = vsub(lg["pos"], centroid)
        dist = vlen(d)
        if dist >= lg["range"]:
            continue
        atten = (1.0 - dist / lg["range"]) * lg["brightness"]
        if atten <= 0.0:
            continue
        lam = max(0.0, vdot(normal, vmul(d, 1.0 / dist))) if dist > 1e-9 else 1.0
        k = atten * lam
        if k <= 0.0:
            continue
        r += lg["color"][0] * k
        g += lg["color"][1] * k
        b += lg["color"][2] * k

    out = (clamp01(base_color[0] * r), clamp01(base_color[1] * g), clamp01(base_color[2] * b))
    if reflectance > 0.0:
        m = clamp01(reflectance) * 0.6
        out = (out[0] + (SKY_COLOR[0] - out[0]) * m,
               out[1] + (SKY_COLOR[1] - out[1]) * m,
               out[2] + (SKY_COLOR[2] - out[2]) * m)
    return out


def apply_fog(color, dist, lit):
    if not lit["fog_active"]:
        return color
    t = clamp01((dist - lit["fog_start"]) / (lit["fog_end"] - lit["fog_start"]))
    if t <= 0.0:
        return color
    fc = lit["fog_color"]
    return (color[0] + (fc[0] - color[0]) * t,
            color[1] + (fc[1] - color[1]) * t,
            color[2] + (fc[2] - color[2]) * t)


# --------------------------------------------------------------------------
# Rasterizer
# --------------------------------------------------------------------------

def fill_convex_poly(fb, pts, rgb, alpha):
    """Scanline-fill a convex screen-space polygon.

    Pixel centres are sampled at (x+0.5, y+0.5) with a half-open rule, so
    adjacent sub-quads tile without gaps or double-blending.
    """
    n = len(pts)
    if n < 3:
        return
    height, width, data = fb.height, fb.width, fb.data

    ymin = min(p[1] for p in pts)
    ymax = max(p[1] for p in pts)
    y0 = int(math.ceil(ymin - 0.5))
    y1 = int(math.ceil(ymax - 0.5))
    if y0 < 0:
        y0 = 0
    if y1 > height:
        y1 = height
    if y0 >= y1:
        return

    col = bytes((int(clamp01(rgb[0]) * 255.0 + 0.5),
                 int(clamp01(rgb[1]) * 255.0 + 0.5),
                 int(clamp01(rgb[2]) * 255.0 + 0.5)))
    opaque = alpha >= 0.999
    if not opaque:
        sr, sg, sb = col[0] * alpha, col[1] * alpha, col[2] * alpha
        inv_a = 1.0 - alpha

    for y in range(y0, y1):
        yc = y + 0.5
        xl = 1e30
        xr = -1e30
        hit = False
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            if ay == by:
                continue
            if (ay <= yc < by) or (by <= yc < ay):
                x = ax + (bx - ax) * ((yc - ay) / (by - ay))
                if x < xl:
                    xl = x
                if x > xr:
                    xr = x
                hit = True
        if not hit:
            continue
        x0 = int(math.ceil(xl - 0.5))
        x1 = int(math.ceil(xr - 0.5))
        if x0 < 0:
            x0 = 0
        if x1 > width:
            x1 = width
        if x0 >= x1:
            continue

        base = (y * width + x0) * 3
        count = x1 - x0
        if opaque:
            data[base:base + count * 3] = col * count
        else:
            i = base
            for _ in range(count):
                data[i] = int(data[i] * inv_a + sr)
                data[i + 1] = int(data[i + 1] * inv_a + sg)
                data[i + 2] = int(data[i + 2] * inv_a + sb)
                i += 3


# --------------------------------------------------------------------------
# The renderer
# --------------------------------------------------------------------------

def render_scene(scene, width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, subdiv=DEFAULT_SUBDIV):
    """Render a scene dict (SPEC.md contract) -> Framebuffer (RGB8)."""
    lit = parse_lighting(scene)
    lights = parse_lights(scene)

    cam_spec = scene.get("camera") or {}
    cam = Camera(_vec(cam_spec.get("pos"), (0.0, 10.0, 20.0)),
                 _vec(cam_spec.get("look"), (0.0, 0.0, 0.0)),
                 cam_spec.get("fov", 70.0),
                 width, height)

    bg = lit["fog_color"]
    fb = Framebuffer(width, height,
                     fill=(int(bg[0] * 255 + 0.5), int(bg[1] * 255 + 0.5), int(bg[2] * 255 + 0.5)))

    # Subdividing only buys us something when shading actually varies over a
    # face -- i.e. when there are point lights or fog.
    max_sub = subdiv if (lights or lit["fog_active"]) else 1

    campos = cam.pos
    draw_list = []  # (dist2, screen_pts, rgb, alpha)

    for part in scene.get("parts") or []:
        transparency = float(part.get("transparency", 0.0) or 0.0)
        if transparency >= 0.999:
            continue  # invisible in Roblox too
        alpha = 1.0 - transparency
        base_color = _col(part.get("color"), (0.64, 0.64, 0.64))
        material = str(part.get("material", "") or "").lower()
        reflectance = float(part.get("reflectance", 0.0) or 0.0)
        size = part.get("size") or (1.0, 1.0, 1.0)

        for normal, quad in box_faces(size, part.get("cframe")):
            # Backface cull: an outward normal pointing away from the camera is
            # hidden by the box's own front faces. Roblox draws the far surface
            # of a transparent part too; we deliberately do not, so a
            # transparent part reads as a single predictable tint over whatever
            # is behind it rather than a double-blended (and misleadingly dark)
            # two-layer stack. See SPEC.md -- not pixel-accurate by design.
            if vdot(normal, vsub(quad[0], campos)) >= 0.0:
                continue
            for sq in subdivide_quad(quad, max_sub):
                cx = (sq[0][0] + sq[1][0] + sq[2][0] + sq[3][0]) * 0.25
                cy = (sq[0][1] + sq[1][1] + sq[2][1] + sq[3][1]) * 0.25
                cz = (sq[0][2] + sq[1][2] + sq[2][2] + sq[3][2]) * 0.25
                centroid = (cx, cy, cz)

                view = [cam.to_view(p) for p in sq]
                if all(v[2] < NEAR_PLANE for v in view):
                    continue
                if any(v[2] < NEAR_PLANE for v in view):
                    view = clip_near(view)
                    if len(view) < 3:
                        continue

                pts = [cam.project(v) for v in view]
                # Cheap reject: entirely off-screen.
                if (max(p[0] for p in pts) < 0.0 or min(p[0] for p in pts) > width
                        or max(p[1] for p in pts) < 0.0 or min(p[1] for p in pts) > height):
                    continue

                d = vsub(centroid, campos)
                dist2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
                rgb = shade_face(normal, centroid, base_color, material,
                                 reflectance, lit, lights)
                rgb = apply_fog(rgb, math.sqrt(dist2), lit)
                draw_list.append((dist2, pts, rgb, alpha))

    # Painter's algorithm: far -> near.
    draw_list.sort(key=lambda item: item[0], reverse=True)
    for _dist2, pts, rgb, alpha in draw_list:
        fill_convex_poly(fb, pts, rgb, alpha)

    return fb


def render_file(scene_path, width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, subdiv=DEFAULT_SUBDIV):
    # utf-8-sig: Windows tooling happily writes JSON with a UTF-8 BOM, and
    # plain "utf-8" would blow up on it. Handles BOM-less files identically.
    with open(scene_path, "r", encoding="utf-8-sig") as fh:
        scene = json.load(fh)
    return render_scene(scene, width=width, height=height, subdiv=subdiv)


# --------------------------------------------------------------------------
# Image diff -- the anomaly-visibility gate
# --------------------------------------------------------------------------

def _as_framebuffer(img):
    if isinstance(img, Framebuffer):
        return img
    if isinstance(img, str):
        return read_png(img)
    if isinstance(img, dict):  # a scene dict
        return render_scene(img)
    raise TypeError("expected Framebuffer, PNG path or scene dict, got %r" % type(img))


def diff_images(a, b, tolerance=DEFAULT_TOLERANCE):
    """Fraction of pixels (0.0 - 1.0) that differ between two images.

    A pixel counts as different when ANY channel differs by more than
    `tolerance`. Accepts Framebuffers, PNG paths, or scene dicts.

    This is the check that proves an anomaly is actually visible: render the
    clean scene and the anomalous scene from the same camera and assert the
    result is above a threshold. A near-zero result means the mutation is
    occluded or off-camera -- the chart_flip / figure_window / sign_swap bug.
    """
    fa = _as_framebuffer(a)
    fb_ = _as_framebuffer(b)
    if fa.width != fb_.width or fa.height != fb_.height:
        raise ValueError("image size mismatch: %dx%d vs %dx%d"
                         % (fa.width, fa.height, fb_.width, fb_.height))
    da, db = fa.data, fb_.data
    total = fa.width * fa.height
    if total == 0:
        return 0.0
    tol = int(tolerance)
    differing = 0
    for i in range(0, total * 3, 3):
        if (abs(da[i] - db[i]) > tol
                or abs(da[i + 1] - db[i + 1]) > tol
                or abs(da[i + 2] - db[i + 2]) > tol):
            differing += 1
    return differing / total


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="render.py",
        description="Render a robloxemu scene JSON to PNG, and/or diff two images.")
    ap.add_argument("scene", help="scene .json to render (or a .png to diff against)")
    ap.add_argument("-o", "--out", help="output PNG path (default: alongside the scene)")
    ap.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    ap.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    ap.add_argument("--subdiv", type=int, default=DEFAULT_SUBDIV,
                    help="max face subdivisions per axis for lighting/fog gradients")
    ap.add_argument("--diff", metavar="OTHER.PNG",
                    help="compare the render against this PNG and print the differing fraction")
    ap.add_argument("--tolerance", type=int, default=DEFAULT_TOLERANCE,
                    help="per-channel tolerance for --diff (default 8)")
    ap.add_argument("--min-diff", type=float, default=None,
                    help="exit non-zero if the diff fraction is below this "
                         "(use to assert an anomaly is actually visible)")
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args(argv)

    if args.scene.lower().endswith(".png"):
        if not args.diff:
            ap.error("a .png input requires --diff OTHER.PNG")
        image = read_png(args.scene)
        out_path = args.out
    else:
        image = render_file(args.scene, args.width, args.height, args.subdiv)
        out_path = args.out
        if out_path is None and not args.diff:
            out_path = os.path.splitext(args.scene)[0] + ".png"

    if out_path:
        image.save(out_path)
        if not args.quiet:
            print("wrote %s (%dx%d)" % (out_path, image.width, image.height))

    if args.diff:
        frac = diff_images(image, args.diff, tolerance=args.tolerance)
        if not args.quiet:
            print("diff vs %s: %.6f (%.4f%% of pixels, tolerance %d)"
                  % (args.diff, frac, frac * 100.0, args.tolerance))
        if args.min_diff is not None and frac < args.min_diff:
            print("FAIL: diff %.6f is below --min-diff %.6f -- the change is "
                  "not visible from this camera" % (frac, args.min_diff),
                  file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
