"""Read or set the Roblox Studio window size, so the viewport is 16:9 for 1920x1080 thumbnails.

    py -3 tools/studio_window.py                 print the screen and the window rect
    py -3 tools/studio_window.py 2630 1460       move to (0,0) and resize; then check the viewport with
                                                 py -3 tools/studio_mcp.py luau "return tostring(workspace.CurrentCamera.ViewportSize)"

Measured 2026-10-09 on the 3440x1440 screen with Studio's default panels: 2630x1460 gives a 1622x913 logical
viewport (about 2028x1140 physical), and screen_capture then returns 1919x1080. Resize that to 1920x1080 and save
as quality-92 JPEG. tools/studio_open.ps1 restarts Studio at its own size, so run this after it. Put the window
back afterwards (the owner works on the left half): py -3 tools/studio_window.py restore
"""
import ctypes, sys
from ctypes import wintypes as wt
ctypes.windll.user32.SetProcessDPIAware()
U = ctypes.windll.user32
found = []
@ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
def cb(h, _):
    n = U.GetWindowTextLengthW(h)
    if n and U.IsWindowVisible(h):
        buf = ctypes.create_unicode_buffer(n + 1); U.GetWindowTextW(h, buf, n + 1)
        if "Roblox Studio" in buf.value: found.append(h)
    return True
U.EnumWindows(cb, 0)
h = found[0]
sw, sh = U.GetSystemMetrics(0), U.GetSystemMetrics(1)
r = wt.RECT(); U.GetWindowRect(h, ctypes.byref(r))
print("screen", sw, sh, "window", r.left, r.top, r.right - r.left, r.bottom - r.top)
if len(sys.argv) > 1 and sys.argv[1] == "restore":
    U.SetWindowPos(h, 0, sw // 2, 0, sw - sw // 2, sh - 40, 0x0040)
    print("restored to the right half")
elif len(sys.argv) > 2:
    w, hh = int(sys.argv[1]), int(sys.argv[2])
    U.ShowWindow(h, 9)
    U.SetWindowPos(h, 0, 0, 0, w, hh, 0x0040)
    U.GetWindowRect(h, ctypes.byref(r)); print("now", r.right - r.left, r.bottom - r.top)
