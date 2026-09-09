# Roblox Studio as an MCP server

This is what lets Claude drive Studio directly — read and edit scripts, run the
game, read the F9 console, and above all `screen_capture`, which returns the
Studio viewport as an image. That last one is the whole content pipeline: the
thumbnails and the TikTok/YouTube clips come from it, so nothing downstream can
be built until this is on.

## What is already done

The standalone `Roblox/studio-rust-mcp-server` project is **discontinued** (its
last tag is literally `END`) and now points at a server that ships inside Studio
itself. That built-in server is what we register.

`%LOCALAPPDATA%\Roblox\mcp.bat` is the launcher, and it is what gets registered in
`~/.claude.json` at user scope rather than the versioned
`Versions\version-<hash>\StudioMCP.exe` directly:

```json
"Roblox_Studio": {
  "type": "stdio",
  "command": "cmd.exe",
  "args": ["/c", "%LOCALAPPDATA%\Roblox\mcp.bat"],
  "env": {}
}
```

Note the `args` shape. Running `claude mcp add` from Git Bash rewrites the `/c`
flag into a path (`C:/`) because of MSYS path conversion, and the server then
never starts. Edit the JSON directly, or run the command from PowerShell.

**mcp.bat does not survive a Studio update as well as it looks.** An earlier
version of this file claimed it re-resolves the version folder from the registry
on every run. It does not: it hard-codes one path and only falls back to the
registry when that path is *missing*. After Studio updated on 9 September the new
build was `version-93202a13414c4131` while mcp.bat still named
`version-9fe94fb0e9d84c25`, whose folder was still on disk — so it kept launching
the old binary. It worked anyway, which is the part that makes this quiet. If
Roblox ever cleans up old version folders the fallback takes over; until then the
launcher and Studio can drift apart without a symptom.

`claude mcp list` reports `Roblox_Studio: ... - ✓ Connected`.

## The step that has to be done by hand

**"Connected" is not the same as working.** The server process starts and answers
the MCP handshake whether or not any Studio is attached to it. With no Studio
attached it advertises **zero tools**, which looks like a healthy connection in
every listing but can do nothing.

Attaching Studio is a GUI toggle inside Studio, with no settings file behind it —
`AssistantSettings/<userId>.json` keeps `"integrations": []` either way, and the
34 MCP entries in `ClientSettings/StudioAppSettings.json` are Roblox's own
feature flags, not this switch.

In Roblox Studio, and it took a while to find because none of it is labelled:

1. The **Assistant** is the **atom-shaped icon** in the top right of the ribbon,
   between the share arrow and the notification bell. It is not in the View menu
   and there is no "Assistant" text anywhere in the ribbon. Hovering it says
   "AI Assistant — Chat with Studio Assistant".
2. The Assistant panel opens docked bottom-right. Its **…** menu is at the top
   right of that panel, beside the conversation name.
3. **Manage MCP Servers** opens a window titled *Assistant Settings*.
4. **Enable Studio as MCP server** is the first toggle. Knob left and dark is OFF.
   Underneath it says "No clients connected", which stays accurate until a client
   actually attaches.

## Verifying it

Double-click `tools/verify_mcp.bat`, or:

```
py -3 tools/probe_studio_mcp.py
```

It performs a real MCP handshake over stdio and prints what the server actually
offers. Before the toggle:

```
server: RobloxStudio 1.0.0
tools: 0

screen_capture present: False
```

After the toggle the tool list should be populated — `script_read`, `multi_edit`,
`execute_luau`, `start_stop_play`, `get_console_output`, `screen_capture`,
`insert_asset`, `upload_image` and the rest — and `screen_capture present` should
read `True`. If it still says 0, the toggle did not take; check that the Studio
you toggled is still running.

## Using it without restarting Claude Code

`tools/studio_mcp.py` speaks the same protocol over the same stdio transport, so
the tools are usable immediately:

```
py -3 tools/studio_mcp.py tools                    what Studio offers
py -3 tools/studio_mcp.py studios                  which sessions are attached
py -3 tools/studio_mcp.py luau "return workspace.Name"
py -3 tools/studio_mcp.py capture out.png --camera 0,120,-60 --look 0,0,40
py -3 tools/studio_mcp.py call <tool> --args-file args.json --out image.png
```

Three things the schemas require that are easy to get wrong, and that this script
fills in or fixes for you: nearly every tool needs a `studio_id` (resolved once
from `list_roblox_studios`), `execute_luau` needs `datamodel_type` and its enum is
capitalised (`Edit`, not `edit`), and `screen_capture` needs a `capture_id` and
calls its second argument `look_at_position`, not `camera_look_at`.

`--file` and `--args-file` exist because PowerShell mangles nested quotes in JSON
badly enough that it is not worth fighting.

A capture comes back as a clean viewport image with no Studio chrome in it. In
Edit mode you get the place as authored, which for these games is close to empty -
the world is built at runtime by the server script. Use `start_stop_play` first
when the point is to photograph the actual game.

## Restart Claude Code afterwards

Claude Code reads its MCP tool list once, at startup. The `mcp__Roblox_Studio__*`
tools do not appear in a session that was already running when the server was
registered or enabled, no matter what the probe says. Restart Claude Code, then
the tools are callable.
