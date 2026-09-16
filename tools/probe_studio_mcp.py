"""Speak MCP to Roblox Studio's built-in server over stdio and report what it actually offers.

Claude Code only picks up a newly registered MCP server's tools on restart, so this is how the
setup gets verified now rather than asserted. It performs the real handshake, lists the tools, and
asks which Studio sessions are attached — an enabled Studio answers with one, a Studio that has
not had "Enable Studio as MCP server" ticked answers with none.

Run: py -3 probe_studio_mcp.py
"""
import json
import os
import subprocess
import sys
import threading

BAT = os.path.expandvars(r"%LOCALAPPDATA%\Roblox\mcp.bat")

def main():
    if not os.path.exists(BAT):
        print("mcp.bat not found at", BAT)
        return 1

    proc = subprocess.Popen(
        ["cmd.exe", "/c", BAT],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", bufsize=1,
    )

    # Drain stderr so a chatty server cannot deadlock on a full pipe.
    errlines = []
    threading.Thread(target=lambda: [errlines.append(l) for l in proc.stderr], daemon=True).start()

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    def read(timeout=25):
        result = {}
        def rd():
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    result["msg"] = json.loads(line)
                except json.JSONDecodeError:
                    continue
                return
        t = threading.Thread(target=rd, daemon=True)
        t.start()
        t.join(timeout)
        return result.get("msg")

    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "setup-probe", "version": "1.0"},
    }})
    init = read()
    if init is None:
        print("no response to initialize")
        print("stderr:", "".join(errlines[:10]))
        proc.kill()
        return 1
    info = (init.get("result") or {}).get("serverInfo") or {}
    print("server: %s %s" % (info.get("name"), info.get("version")))

    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    tl = read()
    tools = ((tl or {}).get("result") or {}).get("tools") or []
    print("tools: %d" % len(tools))
    for t in sorted(tools, key=lambda x: x.get("name", "")):
        desc = (t.get("description") or "").split("\n")[0][:78]
        print("  %-26s %s" % (t.get("name"), desc))

    names = {t.get("name") for t in tools}
    print()
    print("screen_capture present:", "screen_capture" in names)

    if "list_roblox_studios" in names:
        send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": "list_roblox_studios", "arguments": {}}})
        r = read()
        content = ((r or {}).get("result") or {}).get("content") or []
        text = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
        print("attached Studio sessions:", text.strip()[:400] or "(empty)")

    proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
