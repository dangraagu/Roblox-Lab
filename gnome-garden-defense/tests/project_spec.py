"""project_spec.py: the place's project file pins what the game relies on (REVIEW-1).

Run: py -3 tests/project_spec.py   (from gnome-garden-defense/)

Workspace.StreamingEnabled must be OFF: the HUD, the garden view and the glowing pads read the player's own garden
as soon as it exists, and with streaming a client sees the bed's parts arrive later and in pieces (REVIEW-1
reproduced pads arriving after the HUD had bound the bed: no tap ever opened the sheet). The scripts now cope with
a late bed (robloxemu/check_gnomegardendefense_reach.luau section 0), and this pins the place setting too.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
passed = failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + msg)


with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as f:
    project = json.load(f)
tree = project.get("tree", {})
ws = tree.get("Workspace", {})
check(ws.get("$className") == "Workspace", "the project names the Workspace")
check(ws.get("$properties", {}).get("StreamingEnabled") is False, "Workspace.StreamingEnabled is pinned to false")
check(tree.get("ServerScriptService", {}).get("$path") == "src/server", "src/server -> ServerScriptService")
check(tree.get("ReplicatedStorage", {}).get("$path") == "src/shared", "src/shared -> ReplicatedStorage")
check(tree.get("StarterPlayer", {}).get("StarterPlayerScripts", {}).get("$path") == "src/client", "src/client -> StarterPlayerScripts")
client = sorted(os.listdir(os.path.join(ROOT, "src", "client")))
check("View.client.luau" in client, "the garden view's client script is in src/client (" + ", ".join(client) + ")")
print("project: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
