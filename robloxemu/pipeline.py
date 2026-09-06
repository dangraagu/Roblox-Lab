#!/usr/bin/env python3
"""pipeline.py - turn frames into publishable short-form video.

Deliberately source-agnostic: it consumes a directory of PNG frames (or a single
still) and does not care whether they came from `render.py` (our emulator) or from
a real OBS capture of Roblox Studio. That way the same machinery serves both, and
switching to real gameplay footage later changes nothing downstream.

HONESTY RULE, enforced in code below: emulator renders are OUR approximation of the
game's geometry, not Roblox's renderer. `--source emulator` stamps the output as
promotional/stylised. Do not publish emulator output as "gameplay" - a viewer who
clicks through would see something different. Real captures use `--source capture`
and carry no stamp.

Formats:
  vertical  1080x1920  TikTok / Shorts / Reels
  square    1080x1080  feed posts
  wide      1920x1080  YouTube landscape
  thumb     1920x1080  Roblox experience thumbnail (still)
  icon       512x512   Roblox experience icon (still)

Usage:
  py -3 pipeline.py video  <frames_dir> -o out.mp4 [--format vertical] [--fps 30]
                           [--source emulator|capture] [--caption "text"] [--music f.mp3]
  py -3 pipeline.py still  <frame.png>  -o out.png  [--format thumb] [--title "..."]
                           [--subtitle "..."] [--source ...]
  py -3 pipeline.py spot   <clean.png> <anomaly.png> -o out.mp4 [--name "The Watcher"]
        Builds the "spot the difference" short: hold on the anomalous hall with a
        countdown, then reveal. This is the format the anomaly game is natively
        shaped for, and it is the one we can mass-produce.
  py -3 pipeline.py check
        Verify ffmpeg is reachable and print the resolved path.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------- ffmpeg lookup
# winget puts ffmpeg on PATH but only for NEW shells, so resolve it explicitly and
# fall back to a PATH lookup. Override with FFMPEG_BIN if it ever moves.
_WINGET_FFMPEG = (
    Path(os.environ.get("LOCALAPPDATA", ""))
    / "Microsoft/WinGet/Packages"
    / "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe"
    / "ffmpeg-9.0.1-full_build/bin"
)


def _tool(name: str) -> str:
    env = os.environ.get(f"{name.upper()}_BIN")
    if env and Path(env).exists():
        return env
    cand = _WINGET_FFMPEG / f"{name}.exe"
    if cand.exists():
        return str(cand)
    found = shutil.which(name)
    if found:
        return found
    # last resort: any winget build, version-independent
    root = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Packages"
    if root.exists():
        for p in root.rglob(f"{name}.exe"):
            return str(p)
    raise SystemExit(
        f"{name} not found. Install it with:  winget install --id Gyan.FFmpeg -e\n"
        f"or set {name.upper()}_BIN to its full path."
    )


def _fontfile() -> str:
    """ffmpeg's drawtext needs an explicit font on Windows - there is no fontconfig,
    so without this every drawtext call dies with 'Cannot load default config file'."""
    env = os.environ.get("PIPELINE_FONT")
    cands = ([env] if env else []) + [
        r"C:\Windows\Fonts\segoeuib.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\arial.ttf",
    ]
    for c in cands:
        if c and Path(c).exists():
            # ffmpeg filter syntax: escape the drive colon and use forward slashes
            return c.replace("\\", "/").replace(":", r"\:")
    raise SystemExit("no usable font found; set PIPELINE_FONT to a .ttf path")


FONT = _fontfile()


FORMATS = {
    "vertical": (1080, 1920),
    "square": (1080, 1080),
    "wide": (1920, 1080),
    "thumb": (1920, 1080),
    "icon": (512, 512),
}

STAMP = "stylised preview - not gameplay footage"


def _run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = "\n".join((proc.stderr or "").strip().splitlines()[-15:])
        raise SystemExit(f"ffmpeg failed ({proc.returncode}):\n{tail}")


def _esc(text: str) -> str:
    """Escape text for ffmpeg's drawtext filter."""
    return (
        text.replace("\\", r"\\\\")
        .replace(":", r"\:")
        .replace("'", r"\'")
        .replace("%", r"\%")
        .replace(",", r"\,")
        .replace("[", r"\[")
        .replace("]", r"\]")
    )


def _fit(w: int, h: int) -> str:
    """Scale to cover, then crop to the exact frame - no letterboxing, no squash."""
    return (
        f"scale={w}:{h}:force_original_aspect_ratio=increase,"
        f"crop={w}:{h},setsar=1"
    )


def _stamp_filter(w: int, h: int) -> str:
    size = max(16, w // 45)
    return (
        f"drawtext=fontfile='{FONT}':text='{_esc(STAMP)}':fontcolor=white@0.55:fontsize={size}:"
        f"x=(w-text_w)/2:y=h-{int(size * 2.2)}:box=1:boxcolor=black@0.35:boxborderw={size // 3}"
    )


def _caption_filter(text: str, w: int, h: int, y_frac: float = 0.78) -> str:
    size = max(28, w // 18)
    return (
        f"drawtext=fontfile='{FONT}':text='{_esc(text)}':fontcolor=white:fontsize={size}:"
        f"x=(w-text_w)/2:y=h*{y_frac}:box=1:boxcolor=black@0.55:boxborderw={size // 3}"
    )


# ---------------------------------------------------------------- commands
def cmd_check(_args) -> None:
    ff = _tool("ffmpeg")
    print(f"ffmpeg: {ff}")
    out = subprocess.run([ff, "-version"], capture_output=True, text=True)
    print(out.stdout.splitlines()[0] if out.stdout else "(no version output)")
    print(f"ffprobe: {_tool('ffprobe')}")
    print("formats:", ", ".join(f"{k} {v[0]}x{v[1]}" for k, v in FORMATS.items()))


def cmd_video(args) -> None:
    frames = Path(args.frames)
    if not frames.is_dir():
        raise SystemExit(f"not a directory: {frames}")
    pngs = sorted(frames.glob("*.png"))
    if not pngs:
        raise SystemExit(f"no PNG frames in {frames}")
    w, h = FORMATS[args.format]

    chain = [_fit(w, h)]
    if args.caption:
        chain.append(_caption_filter(args.caption, w, h))
    if args.source == "emulator":
        chain.append(_stamp_filter(w, h))

    # A glob pattern avoids requiring frames to be numbered from 0 with no gaps.
    cmd = [
        _tool("ffmpeg"), "-y",
        "-framerate", str(args.fps),
        "-pattern_type", "glob",
        "-i", str(frames / "*.png"),
    ]
    if args.music:
        cmd += ["-i", str(args.music), "-shortest",
                "-c:a", "aac", "-b:a", "192k"]
    cmd += [
        "-vf", ",".join(chain),
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-profile:v", "high", "-crf", "18",
        "-movflags", "+faststart",
        str(args.out),
    ]
    _run(cmd)
    print(f"wrote {args.out}  ({len(pngs)} frames @ {args.fps}fps, {w}x{h}, source={args.source})")
    if args.source == "emulator":
        print(f"  NOTE: stamped '{STAMP}' - do not publish this as gameplay.")


def cmd_still(args) -> None:
    w, h = FORMATS[args.format]
    chain = [_fit(w, h)]
    if args.title:
        size = max(40, w // 14)
        chain.append(
            f"drawtext=fontfile='{FONT}':text='{_esc(args.title)}':fontcolor=white:fontsize={size}:"
            f"x=(w-text_w)/2:y=h*0.08:box=1:boxcolor=black@0.5:boxborderw={size // 4}"
        )
    if args.subtitle:
        size = max(26, w // 26)
        chain.append(
            f"drawtext=fontfile='{FONT}':text='{_esc(args.subtitle)}':fontcolor=white@0.9:fontsize={size}:"
            f"x=(w-text_w)/2:y=h*0.82:box=1:boxcolor=black@0.45:boxborderw={size // 4}"
        )
    if args.source == "emulator":
        chain.append(_stamp_filter(w, h))
    _run([_tool("ffmpeg"), "-y", "-i", str(args.frame),
          "-vf", ",".join(chain), "-frames:v", "1", str(args.out)])
    print(f"wrote {args.out}  ({w}x{h}, source={args.source})")


def cmd_spot(args) -> None:
    """The 'spot the anomaly' short.

    Structure, tuned for short-form retention: an immediate hook, a countdown that
    creates a commitment moment, then a payoff. The whole thing is under 10s so it
    loops, and looping is what the algorithms actually reward.
    """
    w, h = FORMATS[args.format]
    hold, reveal = args.hold, args.reveal
    ff = _tool("ffmpeg")

    hook = args.hook or "Can you spot the anomaly?"
    name = args.name or "the anomaly"

    # Segment 1: the anomalous hall + hook + a countdown driven by frame time.
    seg1 = [
        _fit(w, h),
        _caption_filter(hook, w, h, 0.08),
        # countdown numbers, one per second, drawn only in their own window
    ]
    for i in range(hold, 0, -1):
        t0, t1 = hold - i, hold - i + 1
        size = max(90, w // 7)
        seg1.append(
            f"drawtext=fontfile='{FONT}':text='{i}':fontcolor=white:fontsize={size}:"
            f"x=(w-text_w)/2:y=(h-text_h)/2:"
            f"box=1:boxcolor=black@0.35:boxborderw={size // 6}:"
            f"enable='between(t,{t0},{t1})'"
        )
    if args.source == "emulator":
        seg1.append(_stamp_filter(w, h))

    seg2 = [_fit(w, h), _caption_filter(f"It was: {name}", w, h, 0.08)]
    if args.source == "emulator":
        seg2.append(_stamp_filter(w, h))

    tmp = Path(args.out).with_suffix(".seg1.mp4")
    tmp2 = Path(args.out).with_suffix(".seg2.mp4")
    try:
        _run([ff, "-y", "-loop", "1", "-t", str(hold), "-i", str(args.anomaly),
              "-vf", ",".join(seg1), "-r", "30",
              "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(tmp)])
        _run([ff, "-y", "-loop", "1", "-t", str(reveal), "-i", str(args.anomaly),
              "-vf", ",".join(seg2), "-r", "30",
              "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(tmp2)])
        lst = Path(args.out).with_suffix(".concat.txt")
        lst.write_text(f"file '{tmp.name}'\nfile '{tmp2.name}'\n", encoding="utf-8")
        _run([ff, "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
              "-c", "copy", "-movflags", "+faststart", str(args.out)])
    finally:
        for f in (tmp, tmp2, Path(args.out).with_suffix(".concat.txt")):
            if f.exists():
                f.unlink()
    print(f"wrote {args.out}  ({hold}s hold + {reveal}s reveal, {w}x{h})")
    if args.source == "emulator":
        print(f"  NOTE: stamped '{STAMP}' - do not publish this as gameplay.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--format", choices=list(FORMATS), default="vertical")
        p.add_argument("--source", choices=["emulator", "capture"], default="emulator",
                       help="emulator output is stamped as a stylised preview")

    c = sub.add_parser("check"); c.set_defaults(fn=cmd_check)

    v = sub.add_parser("video"); common(v)
    v.add_argument("frames"); v.add_argument("-o", "--out", required=True)
    v.add_argument("--fps", type=int, default=30)
    v.add_argument("--caption"); v.add_argument("--music")
    v.set_defaults(fn=cmd_video)

    s = sub.add_parser("still"); common(s)
    s.add_argument("frame"); s.add_argument("-o", "--out", required=True)
    s.add_argument("--title"); s.add_argument("--subtitle")
    s.set_defaults(fn=cmd_still)

    sp = sub.add_parser("spot"); common(sp)
    sp.add_argument("clean"); sp.add_argument("anomaly")
    sp.add_argument("-o", "--out", required=True)
    sp.add_argument("--name"); sp.add_argument("--hook")
    sp.add_argument("--hold", type=int, default=4)
    sp.add_argument("--reveal", type=int, default=3)
    sp.set_defaults(fn=cmd_spot)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
