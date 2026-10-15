"""Outpost Zero: the place settings Rojo builds from default.project.json (REVIEW-1 F8).

Run:  py -3 tests/project_check.py

The luau gates read only src/ (robloxemu/wrap.py bundles nothing else), so the project file needs its own check.
Workspace.StreamingEnabled must be pinned to false: Hud.client finds the starred lot's post (the ★ marker, its glow,
★ Show me) under workspace.Shelves, and builds the Census SurfaceGui once, adorned to the owner's BoardFace. With
streaming on, a post that has not streamed in has no marker, and a board face that streams out and back loses its
rows for the session. Everything a player can reach is within about 90 studs of their pad, and 6 shelves are at most
~1 500 server parts, so nothing here needs streaming. stormgrow, escape-room-lab, facility-nightmare and signal-lost
pin it the same way (adapted from stormgrow/tests/project_check.py).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
passed = failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + msg)


with open(os.path.join(HERE, "default.project.json"), encoding="utf-8") as fh:
    project = json.load(fh)
tree = project.get("tree", {})
ws = tree.get("Workspace", {})
check(ws.get("$className") == "Workspace", "the tree has a Workspace node")
check(ws.get("$properties", {}).get("StreamingEnabled") is False, "Workspace.StreamingEnabled is pinned to false")
check(tree.get("ServerScriptService", {}).get("$path") == "src/server", "src/server -> ServerScriptService")
check(tree.get("ReplicatedStorage", {}).get("$path") == "src/shared", "src/shared -> ReplicatedStorage")
check(tree.get("StarterPlayer", {}).get("StarterPlayerScripts", {}).get("$path") == "src/client",
      "src/client -> StarterPlayer.StarterPlayerScripts")

print("project: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
