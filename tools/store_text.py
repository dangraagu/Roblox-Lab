"""Read and write the store text (name and description) of the live games.

The description a player reads is the one piece of the game that was never under version
control. It lived only in the Creator Dashboard, so nobody could see what it said without
logging in, and changing it meant a human clicking through a form. This makes it a file.

    py -3 tools/store_text.py pull                  # fetch what is live into store-text.json
    py -3 tools/store_text.py diff                  # show file vs live, change nothing
    py -3 tools/store_text.py push                  # apply the file to Roblox
    py -3 tools/store_text.py push --only crystal   # one game

The Open Cloud key lives inline in the git-ignored publish scripts. It is read into memory
here and never printed, never logged, and never written to any file. Only Roblox's own
responses are shown. The key needs the `universe` API system with `universe:write`, scoped to
these four experiences; without it a push comes back
`PERMISSION_DENIED: The required scope <universe:write> is missing.`
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE_FILE = os.path.join(ROOT, "docs", "marketing", "store-text.json")

GAMES = [
    # key,        directory,              publish script,          universe id
    ("labyrint",  "labyrint-spill",       "publish_live.bat",      "10547716861"),
    ("crystal",   "grow-a-crystal",       "publish_crystal.bat",   "10543994765"),
    ("plus1",     "plus1-jump",           "publish_plus1.bat",     "10543598100"),
    ("anomaly",   "anomaly-observatory",  "publish_anomaly.bat",   "10544008743"),
]

API = "https://apis.roblox.com/cloud/v2/universes/%s"


def read_key():
    """Pull the Open Cloud key out of whichever publish script still has one."""
    for _, d, bat, _ in GAMES:
        path = os.path.join(ROOT, d, bat)
        if not os.path.exists(path):
            continue
        txt = io.open(path, encoding="utf-8", errors="replace").read()
        m = re.search(r'set\s+"API_KEY=(.+?)"\s*$', txt, re.M)
        if m and m.group(1).strip() and "LIM_INN" not in m.group(1):
            return m.group(1).strip()
    raise SystemExit(
        "No Open Cloud key found. The publish_*.bat scripts are git-ignored, so a fresh\n"
        "checkout has none - copy one in, or run this on the machine that publishes."
    )


def call(key, url, method="GET", body=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("x-api-key", key)
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(body).encode("utf-8")
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, {"raw": e.read().decode("utf-8", "replace")}
    except Exception as e:
        return -1, {"raw": repr(e)}


def load_file():
    if not os.path.exists(STORE_FILE):
        return {}
    return json.load(io.open(STORE_FILE, encoding="utf-8"))


def save_file(data):
    os.makedirs(os.path.dirname(STORE_FILE), exist_ok=True)
    with io.open(STORE_FILE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def selected(only):
    if not only:
        return GAMES
    keys = {k.strip() for k in only.split(",")}
    picked = [g for g in GAMES if g[0] in keys]
    if not picked:
        raise SystemExit("No game matches --only %r. Known: %s"
                         % (only, ", ".join(g[0] for g in GAMES)))
    return picked


def show_change(label, live, want):
    if live == want:
        print("    %-12s unchanged" % label)
        return False
    print("    %-12s CHANGES" % label)
    print("      live: %s" % json.dumps(live[:120] if live else live, ensure_ascii=False))
    print("      file: %s" % json.dumps(want[:120] if want else want, ensure_ascii=False))
    return True


def cmd_pull(args):
    key = read_key()
    data = load_file()
    for gkey, _, _, universe in selected(args.only):
        status, body = call(key, API % universe)
        if status != 200:
            print("%-9s GET failed %s %s" % (gkey, status, body))
            continue
        data[gkey] = {
            "universe": universe,
            "title": body.get("displayName", ""),
            "description": body.get("description", ""),
        }
        print("%-9s pulled  %r" % (gkey, data[gkey]["title"]))
    save_file(data)
    print("\nwrote %s" % os.path.relpath(STORE_FILE, ROOT))


def cmd_diff(args, apply=False):
    key = read_key()
    data = load_file()
    if not data:
        raise SystemExit("%s is empty. Run `pull` first, or write it by hand."
                         % os.path.relpath(STORE_FILE, ROOT))

    changed_any = False
    for gkey, _, _, universe in selected(args.only):
        entry = data.get(gkey)
        print("\n%s (universe %s)" % (gkey, universe))
        if not entry:
            print("    not in the file, skipping")
            continue
        status, body = call(key, API % universe)
        if status != 200:
            print("    GET failed %s %s" % (status, body))
            continue

        want_title = entry.get("title", "")
        want_desc = entry.get("description", "")
        t = show_change("displayName", body.get("displayName", ""), want_title)
        d = show_change("description", body.get("description", ""), want_desc)
        if not (t or d):
            continue
        changed_any = True
        if not apply:
            continue

        mask = ",".join([m for m, on in (("displayName", t), ("description", d)) if on])
        payload = {}
        if t:
            payload["displayName"] = want_title
        if d:
            payload["description"] = want_desc
        status, body = call(key, (API % universe) + "?updateMask=" + mask,
                            method="PATCH", body=payload)
        if status == 200:
            print("    PATCH %s -> 200 applied" % mask)
        else:
            print("    PATCH %s -> %s  %s" % (mask, status, body))
            print("    NOT APPLIED.")

    if not changed_any:
        print("\nNothing differs. Roblox already serves what the file says.")
    elif not apply:
        print("\nNothing was written. Re-run with `push` to apply.")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["pull", "diff", "push"])
    ap.add_argument("--only", help="comma-separated game keys: %s"
                                   % ", ".join(g[0] for g in GAMES))
    args = ap.parse_args()

    if args.command == "pull":
        cmd_pull(args)
    elif args.command == "diff":
        cmd_diff(args, apply=False)
    else:
        cmd_diff(args, apply=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
