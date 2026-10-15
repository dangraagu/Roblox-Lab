"""Find It! Chapters: the place settings Rojo builds from default.project.json (REVIEW-1 B5).

Run:  py -3 tests/project_check.py

The luau gates read only src/ (robloxemu/wrap.py bundles nothing else), so the project file needs its own check.
Workspace.StreamingEnabled must be pinned to false: the server moves a player from the hub spawn to a lane's door mat
about 460 studs away (startAttempt -> teleportTo) with no RequestStreamAroundAsync, and the Room client builds the
room on the lane's server-built floor. With streaming on (a new place's default) the lane might not have streamed in
when the character arrives: a fall, a death, and the attempt ends (onCharacterAdded). The whole world is 12 lane
shells of 9 parts and a hub of under 160, so nothing here needs streaming. escape-room-lab, disaster-rounds,
facility-nightmare and outpost-zero pin it the same way (adapted from outpost-zero/tests/project_check.py).
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
check(isinstance(ws, dict) and len(ws) > 0, "the tree has a Workspace node")
check(ws.get("$properties", {}).get("StreamingEnabled") is False, "Workspace.StreamingEnabled is pinned to false")
check(tree.get("ServerScriptService", {}).get("$path") == "src/server", "src/server -> ServerScriptService")
check(tree.get("ReplicatedStorage", {}).get("$path") == "src/shared", "src/shared -> ReplicatedStorage")
check(tree.get("StarterPlayer", {}).get("StarterPlayerScripts", {}).get("$path") == "src/client",
      "src/client -> StarterPlayer.StarterPlayerScripts")

print("project: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
