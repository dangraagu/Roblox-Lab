# Publishing and rolling back

Written because a deploy gate found the documented rollback path did not run: `DEPLOY.md` points
at `labyrint-spill/deploy_to_roblox.bat`, which hard-exits on a missing `roblox_api_key.txt`, and
that file does not exist in any game directory. The working credential lives inline in the
git-ignored `publish_*.bat` scripts instead. Finding that out at 02:00 with a game broken is the
wrong time.

**A `git push` does not update a live Roblox game.** Publishing is a separate, explicit step, once
per game.

## The script to use, per game

| Game | Publish with | Universe / place |
|---|---|---|
| Labyrinth Mariozo | `labyrint-spill/publish_live.bat` | 10547716861 / 121268951050692 |
| Grow a Crystal | `grow-a-crystal/publish_crystal.bat` | 10543994765 / 106123351742435 |
| +1 Jump Every Step | `plus1-jump/publish_plus1.bat` | 10543598100 / 120040655253410 |
| Anomaly: Night Shift | `anomaly-observatory/publish_anomaly.bat` | 10544008743 / 123669267191209 |

Each is git-ignored and carries an Open Cloud API key inline — never display, echo, paste or
commit one. `labyrint-spill/deploy_to_roblox.bat` and `publish_now.bat` are tracked and keyless;
they read a key from a file that is not present, so they do not currently work. Either supply
`roblox_api_key.txt` or ignore them.

Roblox Studio must be closed, or `rojo build` hits a file lock.

## Reading the result

Every script now checks the HTTP status. Until recently they did not: `curl -sS` prints the
server's error body and still exits 0, so a rejected publish printed "Ferdig." and looked exactly
like a successful one — an expired key would have been indistinguishable from a shipped fix.

- `[OK] Roblox godtok publiseringen` — accepted. The status code is printed above it.
- `[FEIL] Publiseringen ble AVVIST av Roblox. Spillet er IKKE oppdatert.` — rejected, exit code 1,
  with the server's response in `publish_response.json` beside the script (git-ignored). The usual
  cause is an expired key or one lacking place-publish scope.

## After publishing, two things that are easy to miss

1. **Existing servers keep the old code.** A place version change affects newly-started server
   instances only; instances already running serve the build they booted with until they empty. A
   game with a trickle of joins may never drain on its own. Use **Shut Down All Servers** in the
   Creator Dashboard, then join a freshly created server before believing the change is live.
2. **Confirm the server script actually loaded.** Each game prints a line on boot, visible in the
   F9 developer console: `[Labyrint] Lobby-modus lastet.`, `[Crystal] Grow a Crystal lastet.`,
   `[Plus1] +1 Jump Every Step lastet.`, `[Anomaly] Night Shift at the Observatory loaded.`
   Its absence is the only signal for a class of failure that raises no error — a `WaitForChild`
   on a module that did not reach ReplicatedStorage yields forever and logs a warning, not a fault.

## Rolling back

Fastest, and needs no key or toolchain: **Creator Dashboard → the place → Version History →
Revert to this version.** Then shut down all servers, as above.

From source: check out the previous commit, `rojo build`, and run the same `publish_*.bat`. The
gate verifies before every ship that the rollback target still builds — at the time of writing,
all four games build at both the release commit and its predecessor.

## What the local gate does and does not prove

`robloxemu` boots each game's real server and client scripts headless and measures the HUD across
ten viewports. It proves the code loads, the numbers are right, and no control lands off screen,
under Roblox's touch controls, or below the 44 px tap floor.

It renders nothing, runs no `UIListLayout` positioning, and cannot measure a panel that is closed
at boot. It prints what it did not check rather than implying full coverage. The luau CLI it runs
on is not pinned by any manifest in this repo, so its counts cannot be reproduced from a clean
checkout — a `rokit.toml` is the fix and has not been written.
