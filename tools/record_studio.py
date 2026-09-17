"""Record real gameplay out of the Roblox Studio viewport, as video.

    py -3 tools/record_studio.py locate                 print the viewport rectangle on screen
    py -3 tools/record_studio.py rec out.mp4 --seconds 12

Why a screen recording and not `screen_capture`: an MCP capture is one still per round trip and
does not render BillboardGuis (fork-tower/STUDIO.md, section 8). A clip needs 30 frames a second
of what the player actually sees, HUD and billboards included.

How the viewport is found, rather than guessed from the window layout: a full-screen magenta
ScreenGui is put up in the client for one grab, the magenta rectangle IS the viewport, and the
ScreenGui is removed again. Recording then crops exactly that rectangle with ffmpeg's gdigrab.

Studio has to be the foreground window: gdigrab records the desktop, so anything on top of Studio
is recorded too, and an unfocused Studio renders at a throttled frame rate. `rec` brings it to
the front first.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.wintypes as wt
import json
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from studio_mcp import Studio, text_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "robloxemu"))
from pipeline import _tool  # noqa: E402

ctypes.windll.user32.SetProcessDPIAware()
U = ctypes.windll.user32

MAGENTA_ON = """
local plr = game:GetService("Players").LocalPlayer
local g = Instance.new("ScreenGui")
g.Name = "__RecLocate"; g.IgnoreGuiInset = true; g.DisplayOrder = 100000; g.ResetOnSpawn = false
local f = Instance.new("Frame", g)
f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromRGB(255, 0, 255); f.BorderSizePixel = 0
g.Parent = plr:WaitForChild("PlayerGui")
local v = workspace.CurrentCamera.ViewportSize
return string.format("%d,%d", v.X, v.Y)
"""
MAGENTA_OFF = """
local g = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("__RecLocate")
if g then g:Destroy() end
return "off"
"""


def studio_hwnd():
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(h, _):
        n = U.GetWindowTextLengthW(h)
        if n and U.IsWindowVisible(h):
            buf = ctypes.create_unicode_buffer(n + 1)
            U.GetWindowTextW(h, buf, n + 1)
            if "Roblox Studio" in buf.value:
                found.append(h)
        return True

    U.EnumWindows(cb, 0)
    if not found:
        raise SystemExit("no visible Roblox Studio window")
    return found[0]


def to_front(h):
    # The right half of the screen, not all of it: the owner keeps working on the left half while
    # a recording runs (2026-09-17). The viewport is re-measured every run, so nothing else changes.
    sw, sh = U.GetSystemMetrics(0), U.GetSystemMetrics(1)
    U.ShowWindow(h, 9)  # SW_RESTORE, so the window can be positioned
    U.SetWindowPos(h, 0, sw // 2, 0, sw - sw // 2, sh - 40, 0x0040)
    # Windows refuses SetForegroundWindow from a background process unless an input event just
    # happened; an Alt tap is the documented way around that.
    U.keybd_event(0x12, 0, 0, 0)
    U.keybd_event(0x12, 0, 2, 0)
    U.SetForegroundWindow(h)
    time.sleep(0.8)


def grab(x, y, w, h, path):
    subprocess.run([_tool("ffmpeg"), "-v", "error", "-y", "-f", "gdigrab", "-offset_x", str(x),
                    "-offset_y", str(y), "-video_size", "%dx%d" % (w, h), "-i", "desktop",
                    "-frames:v", "1", path], check=True)


def locate(st):
    h = studio_hwnd()
    to_front(h)
    r = wt.RECT()
    U.GetWindowRect(h, ctypes.byref(r))
    vp = text_of(st.call("execute_luau", {"code": MAGENTA_ON, "datamodel_type": "Client"})).strip()
    time.sleep(0.8)
    tmp = os.path.join(tempfile.gettempdir(), "rec_locate.png")
    try:
        x0, y0 = max(r.left, 0), max(r.top, 0)
        x1 = min(r.right, U.GetSystemMetrics(0))
        y1 = min(r.bottom, U.GetSystemMetrics(1))
        grab(x0, y0, x1 - x0, y1 - y0, tmp)
    finally:
        st.call("execute_luau", {"code": MAGENTA_OFF, "datamodel_type": "Client"})
    from PIL import Image
    im = Image.open(tmp).convert("RGB")
    W, H = im.size
    px = im.load()
    xs, ys = [], []
    for yy in range(0, H, 2):
        for xx in range(0, W, 2):
            p = px[xx, yy]
            if p[0] > 235 and p[1] < 25 and p[2] > 235:
                xs.append(xx); ys.append(yy)
    if len(xs) < 1000:
        raise SystemExit("magenta viewport not found on screen (is Studio covered or minimised?)")
    rect = [x0 + min(xs), y0 + min(ys), max(xs) - min(xs) + 2, max(ys) - min(ys) + 2]
    rect[2] -= rect[2] % 2
    rect[3] -= rect[3] % 2
    return {"rect": rect, "viewport_reported": vp, "window": [r.left, r.top, r.right, r.bottom]}


def vertical_strip(rect):
    """The centred 9:16 slice of the viewport - exactly what a Short shows, and a quarter of the
    pixels, which is what lets gdigrab hold 30 fps (the full 2890x1200 viewport managed 18)."""
    x, y, w, h = rect
    sw = int(h * 9 / 16) // 2 * 2
    return [x + (w - sw) // 2, y, sw, h]


def record(rect, seconds, out, fps=30):
    x, y, w, h = rect
    return subprocess.Popen([_tool("ffmpeg"), "-v", "error", "-y", "-f", "gdigrab", "-framerate",
                             str(fps), "-draw_mouse", "0", "-offset_x", str(x), "-offset_y", str(y),
                             "-video_size", "%dx%d" % (w, h), "-i", "desktop", "-t", str(seconds),
                             "-c:v", "libx264", "-preset", "veryfast", "-crf", "16",
                             "-pix_fmt", "yuv420p", out], stdin=subprocess.PIPE)


def stop(proc):
    """End a recording early and cleanly: ffmpeg finishes the file when it reads 'q'."""
    try:
        proc.stdin.write(b"q")
        proc.stdin.flush()
    except OSError:
        pass
    proc.wait()


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("locate")
    r = sub.add_parser("rec")
    r.add_argument("out")
    r.add_argument("--seconds", type=float, default=12)
    r.add_argument("--full", action="store_true", help="whole viewport instead of the 9:16 strip")
    a = ap.parse_args()
    st = Studio()
    st.handshake()
    try:
        info = locate(st)
        print(json.dumps(info))
        if a.cmd == "rec":
            rect = info["rect"] if a.full else vertical_strip(info["rect"])
            p = record(rect, a.seconds, a.out)
            p.wait()
            print("wrote", a.out)
    finally:
        st.close()


if __name__ == "__main__":
    main()
