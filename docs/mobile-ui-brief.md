# Mobile UI brief — make every HUD survive a phone

## Why

A player reported on Reddit, about Grow a Crystal:

> the issue with the UI on mobile is it covers the entire screen and it's impossible to move
> or do anything

They are right, and the same mistake is in all four games. Every HUD is authored in fixed
pixels against a desktop window: 250x470 side panels, 200x300 leaderboards, 460-wide hint
text. On a typical Roblox phone viewport (~800x360) the left panel alone is taller than the
screen, two side panels cover more than half the width, and anything parked at the bottom
sits underneath Roblox's own touch controls where it can never be tapped.

## The shared tool

`src/shared/Responsive.luau` is already in every game, with `tests/responsive.spec.luau`
(63 assertions, green). Do **not** edit either file — they are shared across the four games
and a change in one would drift from the others. Read the module; it is short and documented.

API (all pure, all in design-space pixels unless noted):

- `Responsive.layout(vx, vy, touch?) -> { mode, scale, compact, controlPad, viewportX, viewportY }`
  - `mode` is `"phone"` / `"tablet"` / `"desktop"`, derived from available room, not hardware
  - `scale` goes straight into a `UIScale` (never above 1, never below `Responsive.MIN_SCALE`)
  - `compact` is true on phones: collapse side panels behind a toggle button
  - `controlPad` is screen px at the bottom that Roblox's touch controls own
- `Responsive.usableHeight(vy, layout) -> screen px` a side panel may use vertically
- `Responsive.fitHeight(designH, usable, layout) -> design px` — shrinks a panel until it fits
  after scaling; returns `designH` untouched when it already fits
- `Responsive.sideWidth(designW, vx, layout) -> design px` — ceiling so a left panel plus a
  right panel can never cover more than half the screen between them

## The pattern to apply

```luau
local UserInputService = game:GetService("UserInputService")
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local camera = workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name = "..."; gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- A UIScale does NOTHING parented to a ScreenGui, so introduce a root Frame that owns it and
-- reparent every HUD element from `gui` to `root`.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

local function applyLayout()
    local v = camera.ViewportSize
    layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
    uiScale.Scale = layout.scale
    -- CRITICAL: grow the root by 1/scale so root * scale lands exactly on the viewport.
    -- Skip this and the whole HUD shrinks into the top-left corner on phones while looking
    -- perfectly fine on desktop, where scale is 1 and the bug is invisible.
    root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
    -- ... per-panel sizing, compact toggles, bottom-margin adjustments
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
```

## Rules

1. **Layout only.** Do not touch gameplay, remotes, economy, or server logic. No behaviour
   changes beyond where pixels land and what is visible.
2. **Every side panel** gets `Responsive.sideWidth(...)` for width and
   `Responsive.fitHeight(designH, Responsive.usableHeight(v.Y, layout), layout)` for height.
   Panels that become scrollable are better than panels that get clipped — prefer a
   `ScrollingFrame` when a list can outgrow its box.
3. **Phones collapse.** When `layout.compact`, side panels start hidden behind a small toggle
   button. Toggles go along the TOP edge, never the bottom. At most one drawer open at a time
   if two would overlap.
4. **Keep out of the touch controls.** Nothing interactive within `layout.controlPad` px of
   the bottom in the left ~35% (movement thumbstick) or the right ~25% (jump button) of the
   screen. Move bottom-anchored panels up by `controlPad`, or relocate them entirely.
5. **Full-width text** (hints, toasts) must use scale-based width with an offset cap, e.g.
   `UDim2.new(0.9, 0, 0, 22)` plus a `UISizeConstraint` MaxSize, not a bare `0, 460`.
6. **Re-run on viewport change.** Rotating a phone or resizing a window must re-apply.
7. **Never use a bare string `require`.** `require("./Responsive")` resolves in the luau CLI
   and is INVALID in Roblox — it has shipped and broken a game here before. Client scripts use
   `require(ReplicatedStorage:WaitForChild("Responsive"))`.
8. **Comments and commit text in normal English prose**, matching the density of the file you
   are editing.

## Verification (all of it, before you report back)

Binaries live at
`C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/`

```bash
L="C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau"
# 1. syntax of every file you edited
"$L/luau-compile.exe" --binary <file> > /dev/null
# 2. static analysis; only Roblox-global noise is acceptable
"$L/luau-analyze.exe" <file> | grep -v -E 'Unknown global|Unknown type|Unknown require|unsupported path|Unknown symbol'
# 3. the game's existing tests must still pass
for t in tests/*.spec.luau; do "$L/luau.exe" "$t"; done
```

Report: files changed, what each phone-mode behaviour now is, and the exact verification
output. If something cannot be verified from the CLI, say so plainly rather than implying it
was tested.
