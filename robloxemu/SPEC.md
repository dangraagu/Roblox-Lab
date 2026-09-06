# robloxemu — headless Roblox shim + scene renderer

**Goal.** Run our real game server scripts *outside Roblox*, so we can (a) catch runtime bugs the
unit tests can't, and (b) dump the built world to JSON and render reference images.

**What this is NOT.** Not a Roblox reimplementation and not pixel-accurate. Roblox's engine is
closed. Images from the renderer are for development, verification and thumbnail *design* — they
must never be passed off to players as gameplay screenshots.

**Why it matters.** `require("./Rng")` compiled clean, passed 119 unit tests, and would still have
made the anomaly server fail to load in Roblox. A headless run catches that in one second. Same
for "clicking a socket does nothing because you own no seeds".

---

## Layout (each file owned by exactly one agent)

```
robloxemu/
  emu/datatypes.luau   -- Vector3, CFrame, Color3, UDim, UDim2, NumberRange,
                          NumberSequence(+Keypoint), ColorSequence, TweenInfo, Random, Enum
  emu/instance.luau    -- Instance.new + hierarchy + properties + signals + Attributes
  emu/services.luau    -- Players, ReplicatedStorage, Lighting, DataStoreService, RunService,
                          TweenService, HttpService (+ inert stubs for the rest)
  emu/scheduler.luau   -- virtual clock: task.spawn/wait/delay/defer, step(), advance(dt)
  emu/harness.luau     -- assembles the env, module registry, loads+runs a game, drives players,
                          dumps the scene
  scenes/*.json        -- scene dumps (generated)
  render.py            -- scene JSON -> PNG
  run_anomaly.luau     -- first target: boot anomaly-observatory's server
```

## Hard rules

1. **Pure Luau, runs under the luau CLI** at
   `C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe`.
2. **Never modify anything under `*/src/`** — the emulator adapts to the games, never the reverse.
   If a game needs a change to run, report it, don't do it.
3. Inside `robloxemu/`, modules may `require("./x")` (CLI-only code, never shipped to Roblox).
4. **Fidelity over convenience.** If Roblox semantics are subtle, match them. Especially:
   `UpdateAsync(key, transform)` MAY CALL THE TRANSFORM MORE THAN ONCE, and a transform returning
   `nil` ABORTS the write. Our session-lock correctness depends on exactly this.
5. Unknown property writes must succeed silently (Roblox scripts set lots of properties); unknown
   *method* calls should raise, so we notice a real gap.

## API surface actually used by our games (measured, not guessed)

- **Services:** Players(19), ReplicatedStorage(16), TweenService(6), RunService(6), Lighting(5),
  DataStoreService(4), TextChatService(2), UserInputService, TextService, SoundService,
  PathfindingService, MarketplaceService, HttpService
- **Instance classes:** Part, Model, Folder, PointLight, SpotLight, Attachment, Trail,
  ParticleEmitter, ProximityPrompt, ClickDetector, RemoteEvent, RemoteFunction, IntValue,
  ObjectValue, StringValue, WeldConstraint, SpawnLocation, Sound, Humanoid, BillboardGui, and the
  GUI family (ScreenGui, Frame, TextLabel, TextButton, TextBox, ScrollingFrame, UICorner, UIStroke,
  UIGradient, UIPadding, UIListLayout, UIGridLayout, UIScale, UISizeConstraint, UITextSizeConstraint)
- **Datatypes:** Color3.fromRGB(334)/new/fromHSV, Vector3.new(148)/zero, UDim2.new/fromOffset/fromScale,
  UDim.new, CFrame.new/Angles/`*`, NumberSequenceKeypoint.new, NumberRange.new, NumberSequence.new,
  ColorSequence.new, TweenInfo.new, Random.new
- **Enum families:** Font, Material, TextXAlignment, EasingStyle, EasingDirection, Technology,
  ZIndexBehavior, TextTruncate, SortOrder, KeyCode, ProductPurchaseDecision, PartType,
  ApplyStrokeMode, UserInputType, SurfaceType, NormalId

GUI classes only need to exist and hold properties — nothing headless renders them.

## Contract: `require` mapping

Our servers do `require(ReplicatedStorage:WaitForChild("Config"))` — an **Instance** require.
The harness must:
1. load each `src/shared/*.luau` via the CLI (string path),
2. create a fake Instance per module under a fake ReplicatedStorage, named after the file,
3. make the global `require(instance)` return that module's table (and keep string `require`
   working for the emulator's own files).

## Contract: scene JSON (produced by harness, consumed by render.py)

```json
{
  "name": "anomaly_day1_clean",
  "camera": { "pos": [0,6,10], "look": [0,6,-40], "fov": 70 },
  "lighting": { "ambient": [20,22,30], "brightness": 1.0,
                "fogEnd": 120, "fogColor": [12,14,22], "atmosphereDensity": 0.42 },
  "parts": [
    { "name": "Floor", "class": "Part",
      "size": [20,1,100],
      "cframe": [x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22],
      "color": [30,34,48], "material": "SmoothPlastic",
      "transparency": 0.0, "reflectance": 0.0 }
  ],
  "lights": [ { "class":"PointLight", "pos":[0,15,-10], "color":[235,235,245],
                "brightness":2, "range":24, "enabled":true } ]
}
```
`cframe` is position followed by the 3x3 rotation matrix in `CFrame:GetComponents()` order
(x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22). Colours are 0-255 integers.

## First target (definition of done for round 1)

`run_anomaly.luau` must:
1. boot `anomaly-observatory/src/server/Main.server.luau` with no error,
2. simulate a player joining,
3. play several passes by triggering the ADVANCE / TURN BACK prompts programmatically,
4. assert the Day counter moves correctly and a wrong call resets it,
5. dump one scene per anomaly id + one clean scene to `scenes/`,
6. report any anomaly whose only mutation is invisible from the camera (the
   `chart_flip` / `figure_window` / `sign_swap` bug class) — occlusion/'"did anything visibly
   change" checks are the highest-value output of this whole exercise.
