@echo off
REM Verify that Roblox Studio's built-in MCP server is actually serving tools.
REM A registered server that answers with 0 tools means Studio itself has not been
REM enabled as an MCP server yet (Assistant -> ... -> Manage MCP Servers).
setlocal
cd /d "%~dp0"
echo Probing the Roblox Studio MCP server...
echo.
py -3 probe_studio_mcp.py
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" (
  echo Probe failed with exit code %RC%.
) else (
  echo If "tools" above is 0, open Roblox Studio and turn on:
  echo   Assistant -^> ... -^> Manage MCP Servers -^> Enable Studio as MCP server
  echo Then run this file again.
)
echo.
pause
