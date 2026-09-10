# Open a place in Roblox Studio and get the MCP connection back.
#
#   powershell -ExecutionPolicy Bypass -File tools\studio_open.ps1 grow-a-crystal
#
# Switching places means restarting Studio, and a restart costs the MCP connection every time.
# Two separate things have to be true and neither is obvious:
#
#   1. The toggle must be CYCLED once per Studio session. The setting persists in
#      AssistantSettings\<userId>.json, so the switch comes back up looking on - and Studio has
#      not actually attached. Flipping it off and on is what makes it connect.
#   2. The first StudioMCP.exe to start binds port 13469 and becomes the broker that every other
#      client, and Studio itself, connects through. studio_mcp.py used to kill its own child on
#      exit, which killed the broker if it happened to be the first one, silently detaching
#      Studio. So a long-lived broker is started here and left running.
#
# It also dismisses the Auto-Recovery and Lighting Migration dialogs, which otherwise sit on top
# and swallow every click that follows.

param(
  [Parameter(Mandatory = $true)][string]$Game,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$places = @{
  "labyrint-spill"      = "Labyrint.rbxlx"
  "grow-a-crystal"      = "GrowCrystal.rbxlx"
  "plus1-jump"          = "Plus1.rbxlx"
  "anomaly-observatory" = "Anomaly.rbxlx"
  "fork-tower"          = "ForkTower.rbxlx"
  "nightwatch-manor"    = "NightwatchManor.rbxlx"
  "deep-vein"           = "DeepVein.rbxlx"
  "vault-runners"       = "VaultRunners.rbxlx"
}
if (-not $places.ContainsKey($Game)) {
  Write-Output "Unknown game '$Game'. Known: $($places.Keys -join ', ')"
  exit 1
}
$dir = Join-Path $root $Game
$place = Join-Path $dir $places[$Game]

if (-not $SkipBuild) {
  Push-Location $dir
  Write-Output "Building $($places[$Game]) from source..."
  & cmd.exe /c "rojo build -o $($places[$Game]) 2>&1" | Select-Object -Last 1
  Pop-Location
}

$studioExe = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Directory |
  ForEach-Object { Join-Path $_.FullName "RobloxStudioBeta.exe" } |
  Where-Object { Test-Path $_ } |
  Sort-Object { (Get-Item $_).LastWriteTime } -Descending |
  Select-Object -First 1
if (-not $studioExe) { Write-Output "No RobloxStudioBeta.exe found."; exit 1 }

Stop-Process -Name RobloxStudioBeta -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4

# The broker. Started from the same version folder as Studio so the two cannot drift apart -
# mcp.bat hard-codes an older path and only falls back when it is missing.
$brokerExe = Join-Path (Split-Path -Parent $studioExe) "StudioMCP.exe"
if (-not (Get-Process StudioMCP -ErrorAction SilentlyContinue)) {
  if (Test-Path $brokerExe) {
    Start-Process -FilePath $brokerExe -WindowStyle Hidden
    Start-Sleep -Seconds 4
    Write-Output "started the MCP broker"
  }
}

Start-Process -FilePath $studioExe -ArgumentList $place
$t = 0
$leaf = [IO.Path]::GetFileNameWithoutExtension($place)
while ($t -lt 240) {
  Start-Sleep -Seconds 5; $t += 5
  $p = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue
  if ($p -and $p.MainWindowTitle -like "*$leaf*") { break }
}
Write-Output "Studio opened $leaf after $t s"
Start-Sleep -Seconds 8

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public const uint DOWN = 0x0002, UP = 0x0004;
}
"@

$proc = Get-Process RobloxStudioBeta | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $proc.MainWindowHandle

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($h)
foreach ($name in @("Continue", "Ignore", "Don't Save", "OK")) {
  try {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $btn = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($btn) {
      $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
      Write-Output "  dismissed a dialog with '$name'"
      Start-Sleep -Seconds 2
    }
  } catch { }
}

[void][SW]::ShowWindow($h, 3)
Start-Sleep -Seconds 2
[void][SW]::SetForegroundWindow($h)
Start-Sleep -Seconds 1
$r = New-Object SW+RECT
[void][SW]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$ht = $r.Bottom - $r.Top

function Hit([int]$x, [int]$y) {
  [void][SW]::SetCursorPos(($r.Left + $x), ($r.Top + $y))
  Start-Sleep -Milliseconds 400
  [SW]::mouse_event([SW]::DOWN, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [SW]::mouse_event([SW]::UP, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Seconds 2
}

# Measured on a 3373x1456 maximised window, expressed against the right and bottom edges.
Hit ($w - 103) 69            # the Assistant (atom) icon - opens the panel
Hit ($w - 29) ($ht - 466)    # the ... at the top of the Assistant panel
Hit ($w - 96) ($ht - 378)    # Manage MCP Servers
Hit ([int]($w / 2) + 302) ([int]($ht / 2) - 138)   # the toggle: off
Start-Sleep -Seconds 2
Hit ([int]($w / 2) + 302) ([int]($ht / 2) - 138)   # and on again - this is what attaches Studio

Write-Output ""
$probe = & py -3 (Join-Path $PSScriptRoot "studio_mcp.py") studios 2>&1 | Out-String
if ($probe -match '"studios"') {
  Write-Output "MCP attached: $($probe.Trim())"
  exit 0
}
Write-Output "NOT attached. The probe said:"
Write-Output $probe.Trim()
Write-Output "Do it by hand: the atom icon top right -> ... -> Manage MCP Servers -> the toggle."
exit 1
