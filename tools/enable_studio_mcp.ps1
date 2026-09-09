# Re-enable "Studio as MCP server" after a Studio restart.
#
# The toggle does NOT persist. Restart Studio - which happens on every update, and every time a
# different place is opened this way - and it is off again, silently: the server still answers a
# handshake and still reports "Connected", it just advertises zero tools. So this has to be redone
# every session, and doing it by hand every time is how the whole content pipeline stalls.
#
# Studio draws its ribbon and Assistant panel inside one Qt widget with no accessibility tree, so
# there is nothing to invoke - this clicks pixels. That makes it specific to a maximised Studio
# window on this machine. It verifies the result rather than assuming it: the probe at the end is
# what decides whether it worked.
#
#   powershell -ExecutionPolicy Bypass -File tools\enable_studio_mcp.ps1

$ErrorActionPreference = "Stop"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
}
"@

$proc = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Output "Roblox Studio is not running."; exit 1 }
$h = $proc.MainWindowHandle

# Maximise once, then leave the geometry alone. An earlier version maximised before every click
# and the window was still animating when the pointer fired, so clicks landed on the title bar of
# the old rectangle.
[void][Win]::ShowWindow($h, 3)
Start-Sleep -Seconds 2
[void][Win]::SetForegroundWindow($h)
Start-Sleep -Seconds 1

# Clear anything modal first. Killing Studio to switch places leaves an Auto-Recovery prompt on
# the next launch, and a lighting-migration notice shows up whenever a place is opened that
# predates the Voxel change. Either one swallows every click below and the script reports failure
# for the wrong reason - which is exactly what happened the first time this ran.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
foreach ($name in @("Continue", "Ignore", "Don't Save", "OK", "Close")) {
  try {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($btn) {
      $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
      Write-Output "  dismissed a dialog with '$name'"
      Start-Sleep -Seconds 2
    }
  } catch { }
}

$r = New-Object Win+RECT
[void][Win]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left
$ht = $r.Bottom - $r.Top
Write-Output ("Studio window {0}x{1} at {2},{3}" -f $w, $ht, $r.Left, $r.Top)

function Click([int]$x, [int]$y, [string]$what) {
  # Window-relative in, screen-absolute out. The Assistant Settings window is its own top-level
  # window, so nothing here re-focuses the main window between clicks - that would put the
  # settings window behind it.
  $sx = $r.Left + $x
  $sy = $r.Top + $y
  [void][Win]::SetCursorPos($sx, $sy)
  Start-Sleep -Milliseconds 400
  [Win]::mouse_event([Win]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [Win]::mouse_event([Win]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
  Write-Output ("  clicked {0} at window({1},{2})" -f $what, $x, $y)
  Start-Sleep -Seconds 2
}

# Coordinates measured on a 3373x1456 maximised window. They are offsets from the window's right
# and bottom edges, so a different screen still lands on the same controls.
$assistantIcon = @(($w - 102), 69)      # the atom, between the share arrow and the bell
$panelMenu     = @(($w - 29), ($ht - 465)) # the ... at the top right of the Assistant panel
$menuItem      = @(($w - 96), ($ht - 378)) # "Manage MCP Servers"

Click $assistantIcon[0] $assistantIcon[1] "the Assistant (atom) icon"
Click $panelMenu[0] $panelMenu[1] "the Assistant panel's ... menu"
Click $menuItem[0] $menuItem[1] "Manage MCP Servers"

# The Assistant Settings window opens centred. "Enable Studio as MCP server" is its first toggle.
$cx = [int]($w / 2)
$cy = [int]($ht / 2)
Click ($cx + 302) ($cy - 138) "the Enable Studio as MCP server toggle"

Write-Output ""
Write-Output "Checking whether it took..."
$probe = & py -3 (Join-Path $PSScriptRoot "studio_mcp.py") studios 2>&1 | Out-String
if ($probe -match '"studios"\s*:\s*\[\s*\{') {
  Write-Output "MCP is live. Attached: $($probe.Trim())"
  exit 0
}
Write-Output "Still not attached. What the probe said:"
Write-Output $probe.Trim()
Write-Output ""
Write-Output "Do it by hand: the atom icon top right -> the ... in the Assistant panel ->"
Write-Output "Manage MCP Servers -> Enable Studio as MCP server."
exit 1
