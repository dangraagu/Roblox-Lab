"""Play a game through its own loop in Roblox Studio and assert what happened.

The headless checks in robloxemu prove the code loads, the numbers are right, and the HUD fits on
a phone. They cannot press a key. Everything between "the server built a hall" and "pressing E
advanced the day" was untested in all four of these games, and three of them had never been run
by a person at all.

This drives the real engine: walk the character, press the key, read the HUD back, and fail if
the number did not move. Studio must have the game's place open with MCP attached -
`tools/studio_open.ps1 <game>` does that in one command.

    py -3 tools/playtest.py anomaly

Assertions are made against the HUD the player actually sees, not a server-local table. If the
label says DAY 2, the player is on day 2; if a server variable says so and the label does not,
the player is the one who is right.

THE "ONE PRESS IN THREE" IS EXPLAINED (night shift 2026-10-09, by measurement). An input probe now counts, per
press, whether the key reached the game, whether a prompt began a hold, whether it triggered, and whether the
pass ended in a wrong call (the Death remote). Results:
  * Anomaly: in 8 runs every one of 24 presses arrived and triggered its prompt. The "lost presses" were wrong
    calls at Day 1: a wrong answer resets to Day 1, so on Day 1 the counter does not move, and the old check
    read that as a dropped key. The checks now accept a move OR a Death, per pass and for the run.
  * Labyrint's door (HoldDuration 0.20): a keyPress triggered 0/8 and a 200 ms hold 0/8, while a 400 ms hold
    triggered 8/8; the key arrived 24/24. Presses are now held 400 ms.
  * Control: with both prompt handlers made no-ops in the open place, the run went 4 of 7 red while the probe
    showed every key arriving and triggering, so a broken loop cannot hide behind the probe.
Runs 6-8 after the last change: 7/7 each. Treat it as a gate for anomaly; other games need a recipe first.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from studio_mcp import Studio, text_of  # noqa: E402

HUD = """
local plr = game:GetService("Players").LocalPlayer
local gui = plr and plr:FindFirstChild("PlayerGui")
if not gui then return "NOGUI" end
local out = {}
for _, c in gui:GetDescendants() do
    if c:IsA("TextLabel") and typeof(c.Text) == "string" and c.Text ~= "" then
        table.insert(out, c.Text)
    end
end
return table.concat(out, " || ")
"""

WHERE = """
local plr = game:GetService("Players").LocalPlayer
local hrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
return hrp and string.format("%.0f,%.0f,%.0f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z) or "?"
"""

# The input probe (night shift 2026-10-09). Counts, on the client, what each press actually did: did the key
# reach the game (InputBegan), did a ProximityPrompt start its hold (PromptButtonHoldBegan), did it fire
# (PromptTriggered), and which enabled prompt was nearest just before the press. A miss is then classified
# instead of guessed at.
PROBE_INSTALL = """
local plr = game:GetService("Players").LocalPlayer
if plr:FindFirstChild("InputProbe") then return "already" end
local UIS = game:GetService("UserInputService")
local PPS = game:GetService("ProximityPromptService")
local f = Instance.new("Folder"); f.Name = "InputProbe"; f.Parent = plr
for _, k in {"began", "holdBegan", "triggered", "death"} do f:SetAttribute(k, 0) end
-- A wrong call is a resolved pass too, even when the counter does not move (Day 1 -> wrong -> Day 1).
for _, r in game:GetService("ReplicatedStorage"):GetDescendants() do
    if r:IsA("RemoteEvent") and r.Name == "Death" then
        r.OnClientEvent:Connect(function() f:SetAttribute("death", f:GetAttribute("death") + 1) end)
    end
end
UIS.InputBegan:Connect(function(i) if i.KeyCode ~= Enum.KeyCode.Unknown then f:SetAttribute("began", f:GetAttribute("began") + 1) end end)
PPS.PromptButtonHoldBegan:Connect(function() f:SetAttribute("holdBegan", f:GetAttribute("holdBegan") + 1) end)
PPS.PromptTriggered:Connect(function() f:SetAttribute("triggered", f:GetAttribute("triggered") + 1) end)
return "installed"
"""

PROBE_READ = """
local plr = game:GetService("Players").LocalPlayer
local f = plr:FindFirstChild("InputProbe")
if not f then return "0|0|0|0|none" end
local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
local best, bestD = "none", math.huge
if hrp then
    for _, d in workspace:GetDescendants() do
        if d:IsA("ProximityPrompt") and d.Enabled and d.Parent and d.Parent:IsA("BasePart") then
            local dist = (d.Parent.Position - hrp.Position).Magnitude
            if dist < bestD then
                bestD = dist
                best = string.format("%s@%.1f/%.0f hold%.2f", d.KeyboardKeyCode.Name, dist, d.MaxActivationDistance, d.HoldDuration)
            end
        end
    end
end
return string.format("%d|%d|%d|%d|%s", f:GetAttribute("began"), f:GetAttribute("holdBegan"), f:GetAttribute("triggered"), f:GetAttribute("death"), best)
"""

# Find the far end of the per-player hall rather than hardcoding it: the zone is built at an
# origin derived from a recycled index, so its coordinates differ between runs and players.
# Where each decision pad is, so the walk goes to the RIGHT one.
#
# Standing in the middle of the hall between the two pads, roughly one press in three does
# nothing - measured repeatedly, before and after setting the prompts to AlwaysShow, so
# prompt exclusivity is not the explanation. Standing beside a pad, its key worked 3 times out of
# 3, twice. Whatever the cause, a player walking down the centre of the hall can press a key and
# have nothing happen, which is worth knowing about a game whose entire interface is two keys.
# The test walks to the pad so that it measures the GAME rather than that marginal interaction.
ANOMALY_TARGET = """
local zone = nil
for _, c in workspace:GetChildren() do
    if string.match(c.Name, "^Concourse_") then zone = c end
end
if not zone then return "NONE" end
local adv = zone:FindFirstChild("AdvancePad", true)
local back = zone:FindFirstChild("BackPad", true)
if not (adv and back) then return "NOPADS" end
return string.format("%f|%f|%f|%f|%f|%f",
    adv.Position.X, adv.Position.Y + 1, adv.Position.Z + 5,
    back.Position.X, back.Position.Y + 1, back.Position.Z + 5)
"""

RECIPES = {
    "anomaly": {
        "target": ANOMALY_TARGET,
        "counter": r"DAY (\d+)",
        "what": "the day counter",
        # Either key is right or wrong depending on what the pass rolled, so the assertion is
        # that the day MOVED. A loop that quietly does nothing is the failure being hunted; a
        # wrong call resetting to Day 1 is a move and is correct behaviour.
        "presses": ["E", "Q", "E"],
        "also": [(r"Field Guide: (\d+)/24", "the field guide count")],
    },
}


def counter(text, pattern):
    m = re.search(pattern, text)
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", choices=sorted(RECIPES))
    ap.add_argument("--keep-play", action="store_true")
    args = ap.parse_args()
    spec = RECIPES[args.game]

    st = Studio()
    passed = failed = 0

    def check(cond, msg):
        nonlocal passed, failed
        if cond:
            passed += 1
            print("   ok   %s" % msg)
        else:
            failed += 1
            print("   FAIL %s" % msg)

    def hud():
        return text_of(st.call("execute_luau", {"code": HUD, "datamodel_type": "Client"}))

    try:
        st.handshake()
        if not st.tools():
            raise SystemExit("Studio advertises no tools - the MCP toggle is off. "
                             "Run tools/studio_open.ps1 <game>.")
        print(text_of(st.call("start_stop_play", {"is_start": True})))
        # Long enough for the server to build the world and the client HUD to exist. Raising it
        # from 6 to 12 did NOT reduce the lost presses, so startup time is not the cause of those.
        time.sleep(10)
        print("input probe:", text_of(st.call("execute_luau", {"code": PROBE_INSTALL, "datamodel_type": "Client"})))

        def probe():
            raw = text_of(st.call("execute_luau", {"code": PROBE_READ, "datamodel_type": "Client"})).strip()
            parts = raw.split("|")
            try:
                return [int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])], parts[4]
            except (ValueError, IndexError):
                return [0, 0, 0, 0], raw

        loc = text_of(st.call("execute_luau",
                              {"code": spec["target"], "datamodel_type": "Server"})).strip()
        if loc.count("|") != 5:
            raise SystemExit("the world did not build. The locator said: %s" % loc)
        nums = [float(v) for v in loc.split("|")]
        spots = {"E": nums[0:3], "Q": nums[3:6]}
        print("ADVANCE pad at %.0f,%.0f,%.0f   TURN BACK pad at %.0f,%.0f,%.0f"
              % tuple(nums))

        before = hud()
        start = counter(before, spec["counter"])
        check(start is not None, "%s is on screen before anything happens (%s)"
              % (spec["what"], start))

        seen = [start]
        resolved = 0
        for i, key in enumerate(spec["presses"], 1):
            wx, wy, wz = spots[key]
            # Walk, then CHECK you arrived, and walk again if not.
            #
            # This is what the intermittent failures were. A resolved decision teleports the
            # player back to the start pad; issuing the next walk while that teleport is in
            # flight leaves the character at the start, and the key is then pressed from 75 studs
            # away where the prompt is not armed. It looked exactly like input being dropped,
            # which is what it was blamed on twice - including once in a source comment that had
            # to be corrected. The game was never at fault.
            pos = ""
            for attempt in range(3):
                st.call("character_navigation", {
                    "datamodel_type": "Client", "x": wx, "y": wy, "z": wz,
                    "speed_multiplier": 3.0})
                pos = text_of(st.call("execute_luau",
                                      {"code": WHERE, "datamodel_type": "Client"})).strip()
                try:
                    px, py, pz = [float(v) for v in pos.split(",")]
                except ValueError:
                    break
                if ((px - wx) ** 2 + (py - wy) ** 2 + (pz - wz) ** 2) ** 0.5 <= 8:
                    break
                print("   (still %s, wanted %.0f,%.0f,%.0f - walking again)" % (pos, wx, wy, wz))
                time.sleep(1)
            # keyDown, hold, keyUp - NOT keyPress. A synthetic keyPress puts the down and the up
            # in the same instant, and Roblox's ProximityPrompt misses roughly one in three of
            # them: the run before this change failed a different pass each time with no HUD lag
            # and no second press taking either. Holding it for 200ms is what a person does.
            # Held for 400 ms, not 200 (measured 2026-10-09 on labyrint-spill's door, HoldDuration 0.20:
            # keyPress 0/8 and a 200 ms hold 0/8 triggered, a 400 ms hold 8/8; the key itself arrived
            # 24/24). A hold must outlast the prompt's HoldDuration with margin.
            before_p, near = probe()
            st.call("user_keyboard_input", {"datamodel_type": "Client", "actions": [
                {"action": "wait", "wait_time_ms": 700},
                {"action": "keyDown", "key_code": key},
                {"action": "wait", "wait_time_ms": 400},
                {"action": "keyUp", "key_code": key},
                {"action": "wait", "wait_time_ms": 3000},
            ]})
            after_p, _ = probe()
            d = [x - y for x, y in zip(after_p, before_p)]
            now = counter(hud(), spec["counter"])
            print("  pass %d: walked to %s, pressed %s   [probe: key arrived %d, hold began %d, "
                  "triggered %d, wrong-call (Death) %d; nearest prompt before the press: %s]"
                  % (i, pos, key, d[0], d[1], d[2], d[3], near))
            died = d[3] > 0

            # A press that appears to do nothing has two very different causes, and lumping them
            # together would hide the one that matters. Wait and re-read FIRST: if the number
            # moves, the HUD was simply behind the server and nothing is wrong. Only if it is
            # still unchanged is the input itself suspect - the hall is rebuilt between passes,
            # and a key pressed while the new prompts are being created can be swallowed. That is
            # a real thing a player can hit, so it is reported rather than retried away silently.
            lagged = False
            if now == seen[-1] and not died:
                time.sleep(3)
                again = counter(hud(), spec["counter"])
                if again != seen[-1]:
                    lagged = True
                    now = again
            if now == seen[-1]:
                st.call("user_keyboard_input", {"datamodel_type": "Client", "actions": [
                    {"action": "keyDown", "key_code": key},
                    {"action": "wait", "wait_time_ms": 400},
                    {"action": "keyUp", "key_code": key},
                    {"action": "wait", "wait_time_ms": 3500},
                ]})
                retried = counter(hud(), spec["counter"])
                if retried != seen[-1]:
                    print("   NOTE  the first press was swallowed; a second one took. The hall is "
                          "rebuilt between passes and a key pressed during that is lost.")
                    now = retried
            elif lagged:
                print("   NOTE  the HUD was behind the server by a beat; it caught up.")

            # A wrong call at Day 1 resolves the pass and leaves the counter on 1: the old check called that
            # a lost press, and it was most of the "one in three" (2026-10-09: the probe saw every key arrive
            # and every prompt trigger in 6 of 6 presses while the counter stood still).
            check(now is not None and (now != seen[-1] or died),
                  "%s moved or the pass resolved as a wrong call (%s -> %s%s)"
                  % (spec["what"], seen[-1], now, ", Death" if died else ""))
            if now is not None and (now != seen[-1] or died):
                resolved += 1
            seen.append(now)

        final = hud()
        for pattern, what in spec.get("also", []):
            v = counter(final, pattern)
            check(v is not None, "%s is on screen (%s)" % (what, v))

        # A run that never left day one, or never came back to it, is a loop that is not looping - unless every
        # pass was a wrong call at Day 1 (2026-10-09: three in a row happens, about one run in eight). So the
        # run-level check is that EVERY pass resolved (a move or a Death), with the values printed.
        check(resolved == len(spec["presses"]), "every pass resolved (%d of %d; counter %s)"
              % (resolved, len(spec["presses"]), ",".join(str(s) for s in seen)))

        errs = text_of(st.call("get_console_output", {}))
        bad = [l for l in errs.split("\n")
               if ("error" in l.lower() or "stack begin" in l.lower())]
        check(not bad, "the console reported no errors during play%s"
              % ("" if not bad else ": " + bad[0][:90]))
    finally:
        try:
            if not args.keep_play:
                st.call("start_stop_play", {"is_start": False})
        except SystemExit:
            print("   WARNING: could not leave Play mode cleanly")
        st.close()

    print("\nplaytest %s: %d passed, %d failed" % (args.game, passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
