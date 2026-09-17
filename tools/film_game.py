"""Film short gameplay clips of the published games from inside Roblox Studio.

    py -3 tools/film_game.py plus1 climb_tier1 codes_launch ...
    py -3 tools/film_game.py plus1 --list

Studio must have the game open with MCP attached (tools/studio_open.ps1 <game>) and be in Play.
Every clip is a screen recording of the real Studio viewport (tools/record_studio.py), so it is
`--source capture` footage: the real renderer, the real HUD, real physics.

What a scenario may stage, stated so nobody has to guess from the pictures:
  * where the character starts (a server-side teleport before recording starts),
  * the camera, for shots marked `camera` (a scripted camera path in the running game),
  * in-game codes the game itself offers every player (Config.Codes).
It never edits the game's numbers, never fakes progress the HUD then displays, and never shows
the emulator. Each clip's staging is written to <game>/marketing/clips/manifest.json.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import record_studio as R  # noqa: E402
from studio_mcp import Studio, text_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Shot:
    def __init__(self, st, rect):
        self.st, self.rect = st, rect

    def lua(self, code, dm="Client"):
        return text_of(self.st.call("execute_luau", {"code": code, "datamodel_type": dm})).strip()

    def server(self, code):
        return self.lua(code, "Server")

    def nav(self, x, y, z, speed=1.0):
        return text_of(self.st.call("character_navigation", {
            "datamodel_type": "Client", "x": x, "y": y, "z": z, "speed_multiplier": speed}))

    def hop(self, x, y, z):
        """Hold W, tap Space, let go - with the camera swung behind the character toward the target,
        because W is camera-relative. Studio's character_navigation plans with the default 7.2-stud
        jump and refuses taller steps, and Humanoid:MoveTo from execute_luau does not move a
        player character (measured, 2026-09-17), so this is the input a player gives."""
        cx, cy, cz = [float(v) for v in self.where().split(",")]
        dx, dz = x - cx, z - cz
        d = (dx * dx + dz * dz) ** 0.5
        if d > 0.5:
            self.camera_behind(dx, dz, back=22, up=10)
        hold = max(180, int(d / 16 * 1000) - 120)
        self.keys([{"action": "keyDown", "key_code": "W"}, {"action": "wait", "wait_time_ms": 40},
                   {"action": "keyDown", "key_code": "Space"}, {"action": "wait", "wait_time_ms": 110},
                   {"action": "keyUp", "key_code": "Space"}, {"action": "wait", "wait_time_ms": hold},
                   {"action": "keyUp", "key_code": "W"}, {"action": "wait", "wait_time_ms": 750}])
        return self.where()

    def keys(self, actions):
        return text_of(self.st.call("user_keyboard_input", {"datamodel_type": "Client",
                                                            "actions": actions}))

    def jump(self, hold_ms=120):
        return self.keys([{"action": "keyDown", "key_code": "Space"},
                          {"action": "wait", "wait_time_ms": hold_ms},
                          {"action": "keyUp", "key_code": "Space"}])

    def teleport(self, x, y, z, face=None):
        look = "" if face is None else ", Vector3.new(%f,%f,%f)" % face
        return self.server("""
local p = game.Players:GetPlayers()[1]
local c = p.Character
local hrp = c and c:FindFirstChild("HumanoidRootPart")
if not hrp then return "NOCHAR" end
local hum = c:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(hrp.Position) end
hrp.AssemblyLinearVelocity = Vector3.zero
hrp.CFrame = CFrame.new(Vector3.new(%f,%f,%f)%s)
if hum then hum:MoveTo(hrp.Position) end
return "ok"
""" % (x, y, z, look))

    def camera_behind(self, fx, fz, back=18, up=9):
        """Swing the follow camera to BEHIND the character, looking along (fx, fz). A teleport does
        not turn the camera, so without this it can end up on the far side of the next tile."""
        return self.lua("""
local c = workspace.CurrentCamera
local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
local d = Vector3.new(%f, 0, %f).Unit
c.CameraType = Enum.CameraType.Custom
c.CFrame = CFrame.lookAt(hrp.Position - d * %f + Vector3.new(0, %f, 0), hrp.Position + d * 6)
return "ok"
""" % (fx, fz, back, up))

    def where(self):
        return self.lua("local h=game.Players.LocalPlayer.Character.HumanoidRootPart "
                        "return string.format('%.1f,%.1f,%.1f',h.Position.X,h.Position.Y,h.Position.Z)")

    def zoom(self, dist):
        """Pin the follow camera's distance. Staging, recorded in the manifest: the default lets the
        camera collide into platforms and end up inside the character's hair."""
        return self.lua("local p=game.Players.LocalPlayer p.CameraMinZoomDistance=%f "
                        "p.CameraMaxZoomDistance=%f return 'ok'" % (dist, dist))

    def restart_play(self, settle=18):
        """A fresh Play session is a fresh profile (Studio has no DataStore), so counters start at 0."""
        text_of(self.st.call("start_stop_play", {"is_start": False}))
        time.sleep(3)
        text_of(self.st.call("start_stop_play", {"is_start": True}))
        time.sleep(settle)

    def camera_default(self):
        return self.lua("local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Custom "
                        "c.CameraSubject=game.Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid') return 'ok'")


def encode(raw, out, start=0.0, dur=None, speed=1.0):
    cmd = [R._tool("ffmpeg"), "-v", "error", "-y", "-ss", "%.2f" % start, "-i", raw]
    if dur:
        cmd += ["-t", "%.2f" % dur]
    vf = "scale=1080:1920:flags=lanczos,fps=30"
    if speed != 1.0:
        vf = "setpts=(PTS-STARTPTS)/%f,%s" % (speed, vf)
    cmd += ["-vf", vf, "-c:v", "libx264", "-preset", "slow",
            "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", out]
    subprocess.run(cmd, check=True)


def run(game, scenarios, names):
    st = Studio()
    st.handshake()
    if not st.tools():
        raise SystemExit("Studio advertises no tools - run tools/studio_open.ps1 first")
    info = R.locate(st)
    rect = R.vertical_strip(info["rect"])
    shot = Shot(st, rect)
    gdir = os.path.join(ROOT, game["dir"], "marketing", "clips")
    os.makedirs(os.path.join(gdir, "raw"), exist_ok=True)
    mpath = os.path.join(gdir, "manifest.json")
    manifest = {}
    if os.path.exists(mpath):
        with io.open(mpath, encoding="utf-8") as f:
            manifest = json.load(f)
    try:
        for name in names:
            fn, meta = scenarios[name]
            raw = os.path.join(gdir, "raw", name + ".mp4")
            print("== %s" % name)
            if meta.get("fresh"):
                shot.restart_play()
            if meta.get("zoom"):
                shot.zoom(meta["zoom"])
            setup = meta.get("setup")
            if setup:
                setup(shot)
            rec = R.record(rect, meta.get("max_seconds", 40), raw)
            time.sleep(0.8)
            log = fn(shot) or []
            time.sleep(meta.get("tail", 1.0))
            R.stop(rec)
            cuts = meta.get("cuts") or [(name, meta.get("trim", 0.0), meta.get("dur"), 1.0, meta["what"])]
            for cname, start, dur, speed, what in cuts:
                out = os.path.join(gdir, cname + ".mp4")
                encode(raw, out, start, dur, speed)
                manifest[cname] = {"file": os.path.relpath(out, ROOT).replace("\\", "/"),
                                   "source": "capture", "what": what,
                                   "speed": speed, "from_raw": [name, start, dur],
                                   "staging": meta.get("staging", []), "log": log,
                                   "recorded": time.strftime("%Y-%m-%d %H:%M")}
                print("   wrote", os.path.relpath(out, ROOT), "x%.1f" % speed, log[-2:] if log else "")
            shot.camera_default()
    finally:
        with io.open(mpath, "w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
            f.write("\n")
        st.close()


# ------------------------------------------------------------------------------------ +1 Jump

def _plus1_platforms(shot):
    raw = shot.server("local o={} for _,d in workspace.Tower:GetChildren() do if d:IsA('BasePart') "
                      "and d.Name:match('^P_') then o[#o+1]=d.Name..'='..string.format('%.1f,%.1f,%.1f',"
                      "d.Position.X,d.Position.Y,d.Position.Z) end end return table.concat(o,' ')")
    out = {}
    for tok in raw.split():
        n, xyz = tok.split("=")
        _, t, i = n.split("_")
        out[(int(t), int(i))] = tuple(float(v) for v in xyz.split(","))
    return out


def plus1_climb(tier_from, hops, pause=0.35):
    def fn(shot):
        plats = _plus1_platforms(shot)
        log = []
        seq = [k for k in sorted(plats) if k >= (tier_from, 1)][:hops]
        for k in seq:
            x, y, z = plats[k]
            if float(shot.where().split(",")[1]) > y + 2:
                continue  # already above this tile (an overshoot landed on the next one)
            here = shot.hop(x, y + 3, z)
            log.append("%s -> %s" % (k, here))
            time.sleep(pause)
        return log
    return fn


def plus1_setup_spawn(shot):
    shot.teleport(0, 11, 0, face=(0, 11, 10))
    time.sleep(0.8)
    shot.camera_behind(0, 1, back=20, up=8)
    time.sleep(0.6)


def plus1_redeem(shot, *codes):
    return shot.lua("local f=game.ReplicatedStorage:WaitForChild('Plus1Remotes'):WaitForChild('Redeem') "
                    "local o={} for _,c in {%s} do local ok,r=pcall(function() return f:InvokeServer(c) end) "
                    "o[#o+1]=c..'='..tostring(r) end return table.concat(o,' ')"
                    % ",".join("'%s'" % c for c in codes))


def plus1_code_jump(shot):
    log = []
    time.sleep(0.8)
    shot.jump(); time.sleep(1.4)
    log.append("before: " + shot.where())
    log.append(plus1_redeem(shot, "LAUNCH"))
    time.sleep(1.6)
    shot.jump(); time.sleep(0.9)
    log.append("apex: " + shot.where())
    time.sleep(2.2)
    return log


def plus1_teleport_to(tier, idx, lift=4):
    def setup(shot):
        plats = _plus1_platforms(shot)
        x, y, z = plats[(tier, idx)]
        nx, _, nz = plats.get((tier, idx + 1), plats.get((tier + 1, 1), (x, y, z + 10)))
        shot.teleport(x, y + lift, z, face=(nx, y + lift, nz))
        time.sleep(0.8)
        dx, dz = nx - x, nz - z
        if abs(dx) + abs(dz) < 0.1:
            dz = 1
        shot.camera_behind(dx, dz, back=22, up=10)
        time.sleep(0.6)
    return setup


def plus1_codes_setup(tier, idx):
    tp = plus1_teleport_to(tier, idx)

    def setup(shot):
        # Only the two small codes: at +185 the jump is capped at 60 studs, which overshoots a
        # 10-stud step so far that navigation cannot route (measured: "Can not find a route").
        plus1_redeem(shot, "WELCOME", "SKYHIGH")
        time.sleep(1.0)
        tp(shot)
    return setup


def plus1_walk_off(shot):
    cx, cy, cz = [float(v) for v in shot.where().split(",")]
    log = [shot.where()]
    shot.hop(cx + 14, cy, cz + 6)  # a hop out past the tile's edge, away from the tower
    for _ in range(6):
        time.sleep(0.5)
        log.append(shot.where())
    return log


PATHCAM = """
local RS = game:GetService("RunService")
local cam = workspace.CurrentCamera
local pts = {__PTS__}
local secs, back, up = __SECS__, __BACK__, __UP__
cam.CameraType = Enum.CameraType.Scriptable
local n = #pts
local t0 = os.clock()
local conn
local function at(u)
    local f = 1 + u * (n - 1)
    local i = math.clamp(math.floor(f), 1, n - 1)
    local a = f - i
    return pts[i]:Lerp(pts[i + 1], a)
end
conn = RS.RenderStepped:Connect(function()
    local u = math.clamp((os.clock() - t0) / secs, 0, 1)
    local e = u * u * (3 - 2 * u)
    local p = at(e)
    local ahead = at(math.min(1, e + 0.08))
    local dir = Vector3.new(ahead.X - p.X, 0, ahead.Z - p.Z)
    if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
    dir = dir.Unit
    cam.CFrame = CFrame.lookAt(p - dir * back + Vector3.new(0, up, 0), ahead + Vector3.new(0, 4, 0))
    if u >= 1 then conn:Disconnect() end
end)
return "pathcam " .. n
"""


def plus1_pathcam(tiers, secs=10.0, back=26, up=14):
    def fn(shot):
        plats = _plus1_platforms(shot)
        keys = [k for k in sorted(plats) if k[0] <= tiers]
        pts = ",".join("Vector3.new(%.1f,%.1f,%.1f)" % plats[k] for k in keys)
        code = (PATHCAM.replace("__PTS__", pts).replace("__SECS__", str(secs))
                .replace("__BACK__", str(back)).replace("__UP__", str(up)))
        r = shot.lua(code)
        time.sleep(secs + 0.2)
        return [r]
    return fn


ORBIT = """
local RS = game:GetService("RunService")
local cam = workspace.CurrentCamera
local c0 = Vector3.new(__CX__, __Y0__, __CZ__)
local y1, r, secs = __Y1__, __R__, __SECS__
cam.CameraType = Enum.CameraType.Scriptable
local t0 = os.clock()
local conn
conn = RS.RenderStepped:Connect(function()
    local a = math.clamp((os.clock() - t0) / secs, 0, 1)
    local e = a * a * (3 - 2 * a)
    local ang = __A0__ + e * __SWEEP__
    local y = c0.Y + (y1 - c0.Y) * e
    local pos = Vector3.new(c0.X + math.cos(ang) * r, y + __UP__, c0.Z + math.sin(ang) * r)
    cam.CFrame = CFrame.lookAt(pos, Vector3.new(c0.X, y, c0.Z))
    if a >= 1 then conn:Disconnect() end
end)
return "orbit"
"""


def orbit(cx, cz, y0, y1, r, secs, a0=0.0, sweep=3.14, up=10):
    code = (ORBIT.replace("__CX__", str(cx)).replace("__CZ__", str(cz)).replace("__Y0__", str(y0))
            .replace("__Y1__", str(y1)).replace("__R__", str(r)).replace("__SECS__", str(secs))
            .replace("__A0__", str(a0)).replace("__SWEEP__", str(sweep)).replace("__UP__", str(up)))

    def fn(shot):
        shot.lua(code)
        time.sleep(secs + 0.3)
        return ["orbit %.0f->%.0f r%.0f %.1fs" % (y0, y1, r, secs)]
    return fn


PLUS1 = {
    "dir": "plus1-jump",
    "scenarios": {
        "climb_tier1": (plus1_climb(1, 6, 0.55), {
            "fresh": True, "tail": 0.4, "zoom": 20, "setup": plus1_teleport_to(1, 1, lift=-2) if False else plus1_setup_spawn,
            "what": "a fresh player climbs tier 1; the jump counter goes up on every new tile",
            "staging": ["new Play session (fresh profile)", "camera distance pinned to 20 studs",
                        "character placed on the base pad"]}),
        "code_launch": (plus1_code_jump, {
            "fresh": True, "zoom": 26, "setup": plus1_setup_spawn,
            "what": "a normal hop, then the public code LAUNCH (+100 jump power), then the same hop again",
            "staging": ["new Play session", "camera distance pinned to 26 studs",
                        "code LAUNCH redeemed through the game's own Redeem remote (every player has it)"]}),
        "climb_tier3": (plus1_climb(3, 6, 0.5), {
            "fresh": True, "zoom": 22, "setup": plus1_codes_setup(2, 6),
            "what": "tier 3 climb with the four public codes' jump power",
            "staging": ["public codes WELCOME and SKYHIGH redeemed (+35 jump power)", "character placed on the last tile of tier 2",
                        "camera distance pinned to 22 studs"]}),
        "saw_tier5": (plus1_climb(5, 5, 0.6), {
            "zoom": 24, "setup": plus1_codes_setup(4, 6),
            "what": "tier 5, the first tier with a hazard (a saw), climbed past it",
            "staging": ["public codes WELCOME and SKYHIGH redeemed (+35 jump power)", "character placed on the last tile of tier 4",
                        "camera distance pinned to 24 studs"]}),
        "pendulum_tier6": (plus1_climb(6, 6, 0.6), {
            "zoom": 24, "setup": plus1_codes_setup(5, 6),
            "what": "tier 6 and the pendulum",
            "staging": ["public codes WELCOME and SKYHIGH redeemed (+35 jump power)", "character placed on the last tile of tier 5",
                        "camera distance pinned to 24 studs"]}),
        "long_fall": (plus1_walk_off, {
            "zoom": 30, "setup": plus1_teleport_to(6, 6, lift=3), "tail": 1.5,
            "what": "walking off the top tile of tier 6 - the whole tower goes past",
            "staging": ["character placed on the top tile of tier 6", "camera distance pinned to 30 studs"]}),
        "tower_path": (plus1_pathcam(6, 11.0), {
            "tail": 0.3, "what": "the camera flies up the tile path of tiers 1-6, hazards included",
            "staging": ["scripted camera path in the running game (no character involved)"]}),
    },
}

# ----------------------------------------------------------------------------- Grow a Crystal

def crystal_click(shot, socket_idx, uid_expr="game.Players.LocalPlayer.UserId"):
    """A real left click on the socket (or the crystal in it), at the pixel the camera draws it."""
    p = shot.lua("local c=workspace.CurrentCamera local plot=workspace.Plots:FindFirstChild('Plot_0') "
                 "local part=plot:FindFirstChild('Socket_'..%s..'_%d') "
                 "local pos=part.Position+Vector3.new(0,0.6,0) "
                 "local v=c:WorldToViewportPoint(pos) return string.format('%%.0f,%%.0f',v.X,v.Y)"
                 % (uid_expr, socket_idx))
    x, y = [float(v) for v in p.split(",")]
    shot.st.call("user_mouse_input", {"datamodel_type": "Client", "actions": [
        {"action": "moveTo", "x": x, "y": y}, {"action": "wait", "wait_time_ms": 150},
        {"action": "mouseButtonClick", "mouse_button": "left"}]})
    return "click %d @%.0f,%.0f" % (socket_idx, x, y)


def crystal_static_cam(shot, look=(-4, 2.5, 5), frm=(-4, 6.5, -7)):
    shot.lua("local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable "
             "c.CFrame=CFrame.lookAt(Vector3.new(%f,%f,%f),Vector3.new(%f,%f,%f)) return 'ok'"
             % (frm + look))
    shot.server("local p=game.Players:GetPlayers()[1] local h=p.Character.HumanoidRootPart "
                "h.CFrame=CFrame.new(24,3,-10) return 'ok'")
    time.sleep(0.8)


def crystal_grow_cycle(shot):
    log = []
    for i in (2, 3, 4):
        log.append(crystal_click(shot, i))
        time.sleep(0.9)
    time.sleep(64)
    for i in (2, 3, 4):
        log.append(crystal_click(shot, i))
        time.sleep(1.6)
    time.sleep(1.5)
    log.append(shot.lua("return game.Players.LocalPlayer.PlayerGui:GetDescendants()[1] and 'hud' or ''"))
    return log


def pathcam_points(points, secs=10.0, back=10, up=6):
    def fn(shot):
        pts = ",".join("Vector3.new(%.1f,%.1f,%.1f)" % p for p in points)
        r = shot.lua(PATHCAM.replace("__PTS__", pts).replace("__SECS__", str(secs))
                     .replace("__BACK__", str(back)).replace("__UP__", str(up)))
        time.sleep(secs + 0.2)
        return [r]
    return fn


CAVERN_UP = [(0, 5, -4), (0, 7, 18), (0, 10, 44), (0, 14, 70), (0, 18, 96), (0, 26, 118)]


CRYSTAL = {
    "dir": "grow-a-crystal",
    "scenarios": {
        "grow_cycle": (crystal_grow_cycle, {
            "fresh": True, "setup": crystal_static_cam, "tail": 0.5, "max_seconds": 95,
            "cuts": [
                ("plant_three", 0.5, 5.0, 1.0, "three Shard seeds planted with real clicks, starting Gem Dust 30"),
                ("grow_timelapse", 0.5, 68.0, 6.5, "the same three crystals growing through all four stages - 68 s of real time at 6.5x"),
                ("harvest_three", 66.0, 9.0, 1.0, "harvesting the grown crystals; each one rolls refraction for a rarer tier"),
            ],
            "what": "plant, grow, harvest",
            "staging": ["new Play session (fresh profile)", "fixed scripted camera on the middle socket",
                        "character parked behind the camera", "grow_timelapse is sped up, and says so"]}),
        "cavern_climb": (pathcam_points(CAVERN_UP, 11.0, back=12, up=7), {
            "tail": 0.3, "what": "the camera climbs the cavern's eight terraces, locked chambers and all, up to the basin",
            "staging": ["scripted camera path in the running game"]}),
        "cavern_descend": (pathcam_points(list(reversed(CAVERN_UP)), 11.0, back=10, up=9), {
            "tail": 0.3, "what": "from the basin at the top of the cavern back down to the planting sockets",
            "staging": ["scripted camera path in the running game"]}),
    },
}

# --------------------------------------------------------------------------- Labyrinth Mariozo

def laby_objects(shot):
    raw = shot.server("local m=nil for _,c in workspace:GetChildren() do if c.Name:match('^Maze_') then m=c end end "
                      "if not m then return 'NOMAZE' end local o={m.Name} for _,d in m:GetDescendants() do "
                      "if d:IsA('BasePart') and d.Name~='Wall' and d.Name~='Floor' then "
                      "o[#o+1]=d.Name..'='..string.format('%.1f,%.1f,%.1f',d.Position.X,d.Position.Y,d.Position.Z) end end "
                      "return table.concat(o,' ')")
    if raw.startswith("NOMAZE"):
        return None, {}
    toks = raw.split()
    objs = {}
    for t in toks[1:]:
        n, xyz = t.split("=")
        objs.setdefault(n, []).append(tuple(float(v) for v in xyz.split(",")))
    return toks[0], objs


def laby_click_gui(shot, text_part, gui="LobbyPicker"):
    p = shot.lua("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('%s') if not g then return 'nogui' end "
                 "for _,d in g:GetDescendants() do if d:IsA('TextButton') and d.Text:find('%s') then "
                 "d.Name='ClaudeTarget' return d:GetFullName() end end return 'none'" % (gui, text_part))
    if "Players." not in p:
        return "no button: " + p
    path = "LocalPlayer." + p.split(".", 2)[2]
    shot.st.call("user_mouse_input", {"datamodel_type": "Client", "actions": [
        {"action": "moveTo", "instance_path": path}, {"action": "wait", "wait_time_ms": 250},
        {"action": "mouseButtonClick", "mouse_button": "left"}]})
    return "clicked " + text_part


def laby_prompt(shot, door="SoloDoor"):
    return shot.lua("local p=workspace.Lobby.%s:FindFirstChildOfClass('ProximityPrompt') "
                    "p:InputHoldBegin() task.wait(p.HoldDuration+0.15) p:InputHoldEnd() return 'held'" % door)


def laby_lobby_enter(shot):
    log = [shot.nav(-16, 4, -15)]
    time.sleep(0.4)
    log.append(laby_prompt(shot))
    time.sleep(1.4)
    log.append(laby_click_gui(shot, "Continue"))
    time.sleep(3.5)
    log.append(shot.where())
    return log


def laby_overhead(shot, back=9, up=26):
    name, objs = laby_objects(shot)
    ex = objs.get("Exit", [(0, 0, 0)])[0]
    cx, cy, cz = [float(v) for v in shot.where().split(",")]
    shot.camera_behind(ex[0] - cx, ex[2] - cz, back=back, up=up)


def laby_collect(kinds, then_exit=True):
    def fn(shot):
        name, objs = laby_objects(shot)
        log = [name]
        cx, cy, cz = [float(v) for v in shot.where().split(",")]
        targets = []
        for k in kinds:
            targets += objs.get(k, [])
        # nearest-first tour, so the walk looks like a player's, not a zigzag
        tour = []
        px, pz = cx, cz
        while targets:
            t = min(targets, key=lambda q: (q[0] - px) ** 2 + (q[2] - pz) ** 2)
            targets.remove(t)
            tour.append(t)
            px, pz = t[0], t[2]
        for t in tour[:4]:
            log.append("%s -> %s" % (shot.nav(t[0], t[1], t[2])[:10], shot.where()))
        if then_exit and objs.get("Exit"):
            e = objs["Exit"][0]
            log.append("exit %s -> %s" % (shot.nav(e[0], e[1] + 2, e[2])[:10], shot.where()))
            time.sleep(2.0)
        return log
    return fn


def laby_in_maze(shot):
    name, _ = laby_objects(shot)
    if not name:
        laby_lobby_enter(shot)
        time.sleep(1.0)
    shot.zoom(16)
    laby_overhead(shot)
    time.sleep(0.8)


LABY = {
    "dir": "labyrint-spill",
    "scenarios": {
        "lobby_enter": (laby_lobby_enter, {
            "fresh": True, "zoom": 16, "tail": 1.5,
            "setup": lambda shot: (shot.camera_behind(0, -1, back=16, up=8), time.sleep(0.6)),
            "cuts": [("lobby_enter", 0.0, 7.0, 1.0, "the lobby: three doors, and the Solo Climb picker")],
            "what": "from the lobby through the Solo Climb door into a dark level-1 maze",
            "staging": ["new Play session", "camera distance pinned to 16 studs"]}),
        "coins_and_exit": (laby_collect(["Coin", "Gem"]), {
            "setup": laby_in_maze, "tail": 1.0,
            "cuts": [("coins_and_exit", 1.0, 28.5, 2.0, "collecting coins and gems on level 1, then out through the exit - played at 2x")],
            "what": "collecting coins and gems in the dark, then out through the exit",
            "staging": ["camera pitched high behind the player (pinned 16 studs)"]}),
        "level2_run": (laby_collect(["Coin", "Gem", "Trophy"]), {
            "setup": laby_in_maze, "tail": 1.0,
            "cuts": [("level2_run", 1.0, None, 2.0, "level 2, coins and gems, to the exit - played at 2x")],
            "what": "level 2", "staging": ["camera pitched high behind the player (pinned 16 studs)"]}),
        "level3_run": (laby_collect(["Coin", "Gem"]), {
            "setup": laby_in_maze, "tail": 1.0,
            "cuts": [("level3_run", 1.0, None, 2.0, "level 3, the first level with traps - played at 2x")],
            "what": "level 3", "staging": ["camera pitched high behind the player (pinned 16 studs)"]}),
        "level4_run": (laby_collect(["Coin", "Gem"]), {
            "setup": laby_in_maze, "tail": 1.0,
            "cuts": [("level4_run", 1.0, None, 2.0, "level 4, the first level with a monster - played at 2x")],
            "what": "level 4", "staging": ["camera pitched high behind the player (pinned 16 studs)"]}),
    },
}

GAMES = {"plus1": PLUS1, "crystal": CRYSTAL, "laby": LABY}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game", choices=sorted(GAMES))
    ap.add_argument("names", nargs="*")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    g = GAMES[a.game]
    if a.list or not a.names:
        for n, (_, m) in g["scenarios"].items():
            print("%-20s %s" % (n, m["what"]))
        return
    run(g, g["scenarios"], a.names)


if __name__ == "__main__":
    main()
