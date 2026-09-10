# Spot-the-difference pairs

One folder per anomaly id. Each holds a matched pair of real Roblox Studio captures —
`clean.png` and `anomaly.png`, the **same hall from the same camera**, one pass apart — and
`spot.mp4`, the short cut from them. `manifest.json` records, per pair, the camera, the zone
origin, which pass serial each half came from, and the measurements that decided whether the
pair was publishable at all.

## What is here now (2026-09-10, the first run)

Three clips, all `vertical` 1080x1920, 7s (4s hold + 3s reveal), all real Studio captures:

| id | name | how different the crop is | vs noise floor |
| --- | --- | --- | --- |
| `scope_gone` | Missing Telescope | 3.09% | 0.02% |
| `twin_scope` | The Twin | 1.96% | 0.02% |
| `lights_out` | Blackout | 88.2% | 0.01% |

`figure_end/` and `figure_window/` hold matched stills but **no clip**: the gate rejected them and
they are kept as evidence of why. Both anomalies are a near-black figure (RGB 8,8,12) standing
80-odd studs down a hall whose walls are RGB 30,34,48. In the vertical crop the figure moves
0.007% and 0.053% of the pixels — for `figure_end` that is under 30 pixels, and the per-pixel
contrast is at the edge of the detector's threshold. Widening to `square` or `wide` does not
rescue them, because the wider crop lets the potted plant in and its regenerated grass speckle
(0.88%) is then larger than the figure. They are perfectly fair anomalies to *play* against — you
walk toward them and they resolve — and they are not spottable in a still taken from the start of
the hall. A camera placed at the far end would fix them; this rig deliberately uses one camera
for the whole run so every pair is comparable.

`flicker_hall` was rolled twice during the run and skipped by `--skip`, as designed.

## Make more

```
tools\studio_open.ps1 anomaly-observatory      builds the place, restarts Studio, attaches MCP
py -3 tools\film_anomaly.py --want 6 --max-passes 40
```

That is the whole loop. It starts Play, reads each pass off the zone, photographs the ones it
still needs, answers correctly so the hall rolls again, and at the end pairs, measures and calls
`pipeline.py spot` on everything that passed the gate. Add `--no-render` to stop after the
stills; `--skip a,b,c` to exclude anomaly ids; `--keep-play` to leave Studio running.

`tools/studio_open.ps1` is not optional after a Studio restart: the in-Studio MCP toggle **looks**
enabled when it is not, and cycling it is what actually attaches Studio. If `film_anomaly.py`
says Studio advertises no tools, that is what happened.

Which anomaly you get is a dice roll — the server picks one per pass and the day-1 pool is only
the first eight catalog entries, widening by one every two days. So the way to reach the deeper
ones is simply to let it run longer: `--max-passes 40` and up. Each pass costs roughly 12
seconds.

## How a pair is kept honest

* **Which hall is on screen** comes from the game, not from the pixels. `beginPass` writes
  `Clean`, `AnomalyId` and `Serial` onto the zone model as attributes; the tool reads them.
  `robloxemu/check_anomaly_attrs.luau` is the check that those attributes are true — it
  identifies the clean hall from the world alone and asserts the attributes agree with it, pass
  after pass.
* **The camera** is derived from the zone's `Floor` part, never from a bounding box of the zone.
  An anomaly adds and removes parts, so a bbox-derived camera would move between the two halves
  of the pair. It is computed once and re-checked every pass; the run stops if it ever drifts.
* **The HUD is switched off and the avatar parked behind the camera** for each shot. The HUD
  shows a day counter that changes every pass and the avatar idles mid-frame — either would read
  as "the difference". Both are stated in the manifest. Nothing in the hall itself is touched and
  the lighting is not lifted, so these are `--source capture` and carry no promotional stamp.
* **The pair has to be measurably different.** Two clean passes are also photographed, and the
  pixel difference between them is the noise floor. A pair ships only if its own difference,
  measured inside the crop the clip actually shows, is at least twice that floor and at least
  0.15% of the frame. Anything below that is written into the manifest with the numbers and no
  clip, rather than shipped as a puzzle with no answer.

## What the gate rejects, and why that is right

* **`flicker_hall` is skipped by default.** The Flicker is a light strobing on an irregular
  cycle, so for about half of every cycle the hall is bit-for-bit the clean hall. It is a real
  anomaly and a fair one to play against; it is simply not a thing a photograph can show.
* **Anomalies close to the camera and off to the side fall outside the crop.** The vertical
  short keeps only the middle ~23% of a 1920x798 capture. Something like the potted plant, ten
  studs away at the edge of frame, is obvious in the still and absent from the clip — so the tool
  tries `vertical`, then `square`, then `wide`, and takes the first format whose crop actually
  contains the difference.

## Traps already paid for

* **Let Studio's renderer warm up.** Two *clean* passes shot either side of the first half-minute
  of a Play session differed by 3% of the frame — more than most anomalies do. `--warmup-passes`
  (default 2) photographs nothing until it has settled.
* **Stop the avatar, do not just move it.** `character_navigation` leaves a walk order running on
  the Humanoid, and teleporting the body does not cancel it, so the avatar walks back down the
  hall and stands at the far end in some frames and not others. The first pairs shot with this
  rig had a person-shaped blob as their brightest difference.
* **The potted plant is not stable.** Its `Grass` material is regenerated with a fresh random
  speckle every rebuild, so it differs between two identical clean halls. It sits outside the
  vertical crop, which is the only reason it does not dominate every measurement.

## The three clips were re-rendered on 2026-09-10, because the first three were not spot-the-difference

`pipeline.py spot` took `<clean.png>` as its first positional argument and never read it. Both
segments rendered the anomaly frame, so the viewer was shown the same hall twice: asked to spot a
difference against nothing, and then given a reveal that revealed nothing. The stills and the
measurement gate were fine; only the render was wrong, and it was wrong silently — the clips play,
they are the right length and the right size, and nothing in the output says the wrong image went
in twice.

The command now renders three parts:

| part | frame | why |
|---|---|---|
| `--ref` seconds (default 1.2) | **clean** | a viewer who has never played cannot know what normal looks like. Without this there is no reference and the format does not work. |
| `--hold` seconds (default 4) | **anomaly** | hook plus the per-second countdown, unchanged |
| `--reveal` seconds (default 3) | **alternates**, 6 blinks, ending on the anomaly | the one changed thing moves and everything else stays still. A blink comparator also needs no screen coordinates for the anomaly, which we do not have and would have to keep in step with the world. |

Re-rendered and then checked frame by frame rather than trusted: a frame pulled from inside the
reference segment and one from inside the countdown, each fitted to the same 1080x1920 crop and
compared against both source stills.

| clip | reference vs clean | reference vs anomaly | hold vs clean | hold vs anomaly |
|---|---|---|---|---|
| `lights_out` | 1.796% | 87.319% | 89.271% | 2.459% |
| `scope_gone` | 1.795% | 4.890% | 5.469% | 3.335% |
| `twin_scope` | 1.797% | 3.835% | 5.119% | 3.110% |

Every clip now opens on the clean hall and holds on the anomalous one. The ~1.8% residual against
the matching still is the caption drawn over it; the countdown digit inflates both hold columns,
which is why `scope_gone` and `twin_scope` read closer than they look.
