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

`%LOCALAPPDATA%\Roblox\mcp.bat` is the launcher. It re-resolves the versioned
folder (`Versions\version-<hash>\StudioMCP.exe`) from the registry on every run,
so registering the `.bat` — rather than the `.exe` — survives Studio's automatic
updates. It is registered in `~/.claude.json` at user scope:

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

In Roblox Studio:

1. Open the **Assistant** panel.
2. Click the **…** (overflow) menu in that panel.
3. Choose **Manage MCP Servers**.
4. Turn on **Enable Studio as MCP server**.

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

## Restart Claude Code afterwards

Claude Code reads its MCP tool list once, at startup. The `mcp__Roblox_Studio__*`
tools do not appear in a session that was already running when the server was
registered or enabled, no matter what the probe says. Restart Claude Code, then
the tools are callable.
