"""Talk to Roblox Studio's built-in MCP server from the command line.

Claude Code reads its MCP tool list once, at startup, so the mcp__Roblox_Studio__* tools do not
appear in a session that was already running when the server was switched on. This is the way in
that does not need a restart: it speaks the same protocol over the same stdio transport.

    py -3 tools/studio_mcp.py tools                     list what Studio offers
    py -3 tools/studio_mcp.py studios                   which Studio sessions are attached
    py -3 tools/studio_mcp.py call <name> '<json args>' call any tool, print the result
    py -3 tools/studio_mcp.py capture out.png           screenshot the viewport
    py -3 tools/studio_mcp.py capture out.png --camera 0,120,-60 --look 0,0,40
    py -3 tools/studio_mcp.py luau 'return #workspace:GetChildren()'

`capture` is the one that matters: it is how a game gets a thumbnail and how a clip gets frames,
without a human holding the camera.

Requires the toggle inside Studio: Assistant -> ... -> Manage MCP Servers -> Enable Studio as MCP
server. Without it the server still answers the handshake and advertises zero tools, so this
prints a specific message rather than a confusing empty list.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import subprocess
import sys
import threading

BAT = os.path.expandvars(r"%LOCALAPPDATA%\Roblox\mcp.bat")


class Studio:
    """One MCP session over the launcher's stdio."""

    def __init__(self, timeout=180):
        if not os.path.exists(BAT):
            raise SystemExit("mcp.bat not found at %s - is Roblox Studio installed?" % BAT)
        self.timeout = timeout
        self.proc = subprocess.Popen(
            ["cmd.exe", "/c", BAT],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1,
        )
        self._err = []
        threading.Thread(
            target=lambda: [self._err.append(l) for l in self.proc.stderr], daemon=True
        ).start()
        self._id = 0

    def _send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def _read(self, want_id):
        """Read until the reply with this id arrives; ignore notifications in between."""
        box = {}

        def rd():
            for line in self.proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if msg.get("id") == want_id:
                    box["msg"] = msg
                    return

        t = threading.Thread(target=rd, daemon=True)
        t.start()
        t.join(self.timeout)
        if "msg" not in box:
            raise SystemExit(
                "no reply to request %d within %ds. stderr:\n%s"
                % (want_id, self.timeout, "".join(self._err[:20]))
            )
        return box["msg"]

    def request(self, method, params=None):
        self._id += 1
        self._send({"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}})
        reply = self._read(self._id)
        if "error" in reply:
            raise SystemExit("%s failed: %s" % (method, json.dumps(reply["error"])[:400]))
        return reply.get("result", {})

    def handshake(self):
        info = self.request("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "roblox-lab", "version": "1.0"},
        })
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        return (info.get("serverInfo") or {})

    def tools(self):
        return self.request("tools/list").get("tools") or []

    def studio_id(self):
        """The attached Studio's id. Nearly every tool requires it, so resolve it once."""
        if getattr(self, "_studio_id", None):
            return self._studio_id
        res = self.call("list_roblox_studios", {}, auto_id=False)
        blob = text_of(res)
        try:
            studios = json.loads(blob).get("studios") or []
        except json.JSONDecodeError:
            raise SystemExit("could not read the Studio list: %s" % blob[:200])
        if not studios:
            raise SystemExit(
                "No Roblox Studio is attached to the MCP server. "
                "Open Studio with a place, and make sure Assistant -> ... -> Manage MCP Servers"
                " -> Enable Studio as MCP server is on."
            )
        self._studio_id = studios[0]["id"]
        return self._studio_id

    def call(self, name, arguments, auto_id=True):
        a = dict(arguments)
        if auto_id and "studio_id" not in a:
            a["studio_id"] = self.studio_id()
        return self.request("tools/call", {"name": name, "arguments": a})

    def close(self):
        try:
            self.proc.kill()
        except Exception:
            pass


def require_tools(st):
    tools = st.tools()
    if not tools:
        raise SystemExit(
            "Studio's MCP server answered, but advertises ZERO tools.\n"
            "That is the signature of the in-Studio toggle being off. Turn it on:\n"
            "  Assistant panel -> the ... menu -> Manage MCP Servers -> Enable Studio as MCP server"
        )
    return tools


def text_of(result):
    """Flatten a tool result's content blocks into readable text."""
    out = []
    for c in result.get("content") or []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "text":
            out.append(c.get("text", ""))
        elif c.get("type") == "image":
            out.append("<image %s, %d base64 chars>"
                       % (c.get("mimeType", "?"), len(c.get("data") or "")))
        else:
            out.append(json.dumps(c)[:400])
    return "\n".join(out)


def save_images(result, out_path):
    """Write every image block in a tool result to disk. Returns the paths written."""
    written = []
    blocks = [c for c in (result.get("content") or [])
              if isinstance(c, dict) and c.get("type") == "image" and c.get("data")]
    root, ext = os.path.splitext(out_path)
    for i, c in enumerate(blocks):
        path = out_path if i == 0 else "%s_%d%s" % (root, i + 1, ext or ".png")
        with open(path, "wb") as f:
            f.write(base64.b64decode(c["data"]))
        written.append(path)
    return written


def triple(s, what):
    parts = [p.strip() for p in s.split(",")]
    if len(parts) != 3:
        raise SystemExit("%s must be x,y,z - got %r" % (what, s))
    try:
        return [float(p) for p in parts]
    except ValueError:
        raise SystemExit("%s must be three numbers - got %r" % (what, s))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("tools", help="list the tools Studio offers")
    sub.add_parser("studios", help="list the attached Studio sessions")

    c = sub.add_parser("call", help="call any tool by name")
    c.add_argument("name")
    c.add_argument("args", nargs="?", default="{}", help="JSON object of arguments")
    c.add_argument("--args-file", help="read the JSON arguments from a file instead "
                                       "(PowerShell mangles nested quotes; this avoids it)")
    c.add_argument("--out", help="save any returned image here")

    p = sub.add_parser("capture", help="screenshot the Studio viewport")
    p.add_argument("out")
    p.add_argument("--camera", help="camera position as x,y,z")
    p.add_argument("--look", help="point to look at as x,y,z")
    p.add_argument("--id", help="capture id Studio echoes back (defaults to the file name)")

    l = sub.add_parser("luau", help="run Luau in Studio and print what it returns")
    l.add_argument("code", nargs="?", help="the code; omit and use --file for anything long")
    l.add_argument("--file", help="read the code from a file (no shell quoting to fight)")
    l.add_argument("--datamodel", default="Edit", choices=["Edit", "Server", "Client"],
                   help="which datamodel to run in (Studio requires this; default edit)")

    args = ap.parse_args()

    st = Studio()
    try:
        info = st.handshake()
        if args.cmd == "tools":
            tools = require_tools(st)
            print("server: %s %s  (%d tools)"
                  % (info.get("name"), info.get("version"), len(tools)))
            for t in sorted(tools, key=lambda x: x.get("name", "")):
                print("  %-26s %s" % (t.get("name"),
                                      (t.get("description") or "").split("\n")[0][:88]))
            return 0

        require_tools(st)

        if args.cmd == "studios":
            print(text_of(st.call("list_roblox_studios", {})))
            return 0

        if args.cmd == "luau":
            code = args.code
            if args.file:
                code = io.open(args.file, encoding="utf-8").read()
            if not code:
                raise SystemExit("give some code, or --file")
            print(text_of(st.call("execute_luau",
                                  {"code": code, "datamodel_type": args.datamodel})))
            return 0

        if args.cmd == "capture":
            # capture_id is required by the schema and is just a label Studio echoes back; name
            # it after the output file so a run is traceable to its image.
            a = {"capture_id": args.id or ("cap_" + os.path.splitext(os.path.basename(args.out))[0])}
            if args.camera:
                a["camera_position"] = triple(args.camera, "--camera")
            if args.look:
                a["look_at_position"] = triple(args.look, "--look")
            result = st.call("screen_capture", a)
            paths = save_images(result, args.out)
            if not paths:
                print("no image came back. What the tool said:")
                print(text_of(result))
                return 1
            for path in paths:
                print("saved %s (%d bytes)" % (path, os.path.getsize(path)))
            return 0

        if args.cmd == "call":
            raw = args.args
            if getattr(args, "args_file", None):
                raw = io.open(args.args_file, encoding="utf-8").read()
            try:
                a = json.loads(raw)
            except json.JSONDecodeError as e:
                raise SystemExit("arguments must be a JSON object: %s" % e)
            result = st.call(args.name, a)
            if args.out:
                for path in save_images(result, args.out):
                    print("saved %s (%d bytes)" % (path, os.path.getsize(path)))
            print(text_of(result))
            return 0
    finally:
        st.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
