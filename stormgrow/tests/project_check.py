"""StormGrow: the place settings Rojo builds from default.project.json (REVIEW-1 B4).

Run:  py -3 tests/project_check.py

The luau gates read only src/ (robloxemu/wrap.py bundles nothing else), so the project file needs its own check.
Workspace.StreamingEnabled must be pinned to false: Farm.client draws every farm's crops, the boards and the
porch art assume the whole valley is present, and a streaming place would leave far farms bare (Farm.client now
also copes with tiles that arrive late or leave, check_stormgrow_stream.luau, but the pin is the first line).
escape-room-lab, facility-nightmare and signal-lost pin it the same way.
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
