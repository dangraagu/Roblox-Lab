"""project_spec.py: the place's project file pins what the game relies on.

Run: py -3 tests/project_spec.py   (from scrapline-tycoon/)

Workspace.StreamingEnabled must be OFF. Hud.client binds every ProximityPrompt (the six consoles, Fix, the board
toggle) to parts of the player's own plot, and the board's SurfaceGui to its BoardFace; it caches a console or board
prompt once the part is found. With streaming, a client receives those parts later and in pieces, and a part streamed
out and back in is a NEW instance, so a cached prompt would sit on a destroyed part (gnome-garden-defense REVIEW-1 R4
reproduced exactly that: no tap ever opened the sheet). The reflection default is false and Rojo writes no Workspace
unless the project names one, so a place created from a Studio template (StreamingEnabled = true) would keep
streaming on. This pins it (copied from gnome-garden-defense/tests/project_spec.py, adapted to this game's scripts).
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
check(tree.get("$className") == "DataModel", "the project is a place (DataModel)")
ws = tree.get("Workspace", {})
check(ws.get("$className") == "Workspace", "the project names the Workspace")
check(ws.get("$properties", {}).get("StreamingEnabled") is False, "Workspace.StreamingEnabled is pinned to false")
check(tree.get("ServerScriptService", {}).get("$path") == "src/server", "src/server -> ServerScriptService")
check(tree.get("ReplicatedStorage", {}).get("$path") == "src/shared", "src/shared -> ReplicatedStorage")
check(tree.get("StarterPlayer", {}).get("StarterPlayerScripts", {}).get("$path") == "src/client",
      "src/client -> StarterPlayerScripts")
client = sorted(os.listdir(os.path.join(ROOT, "src", "client")))
check(client == ["Hud.client.luau", "Yard.client.luau"], "the two client scripts are in src/client (" + ", ".join(client) + ")")
server = sorted(os.listdir(os.path.join(ROOT, "src", "server")))
check(server == ["Main.server.luau"], "the one server script is in src/server (" + ", ".join(server) + ")")
with open(os.path.join(ROOT, ".gitignore"), encoding="utf-8") as f:
    ignored = [l.strip() for l in f]
check("publish_*.bat" in ignored and "publish_*.sh" in ignored, ".gitignore keeps publish_*.bat and publish_*.sh out")
print("project: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
