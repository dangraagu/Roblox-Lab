# Night-shift queue — progress ledger

Newest night first. Each job: done / in progress (with exact resume point) / blocked (why).

## Night of 2026-09-27 (run started 00:17, stopped early)

**Why it stopped early:** mid-run both clocks (Bash `date` and PowerShell `Get-Date`) jumped from about
00:55 to 22:55 on 2026-09-27. The PC most likely slept for about 22 hours while Studio was restarting. 22:55 is
outside the 00:00-06:00 window, so the run stopped at once: no gates re-run, nothing published, nothing
merged to main. The work below is on branch `night/2026-09-27-plus1-sitdrop`, NOT on main.

### H. Eye-candy — plus1-jump: IN PROGRESS

Done:
- Studio opened with `tools/studio_open.ps1 plus1-jump`; MCP attached. Play works; DataStores are
  unavailable in the unpublished place, so nothing was saved (console: "progress will NOT be saved").
- Console on join: only the two expected datastore warnings and the load line. No errors.
- **Real bug found and fixed (test first): the ☕ Rest button did not rest.** In real Studio, pressing Rest
  set `Humanoid.Sit = true` and 20 ms later the rest ended. Heartbeat trace: a Humanoid sat without a seat
  drops onto the floor (root vy -3 .. -26, bounce +9, settled in ~0.3 s), and `Sky.client` counted
  "seated and |vy| >= 2" as falling, so the first frame of the drop woke the rest.
  - Failing check first: `robloxemu/check_plus1jump_sitdrop.luau` replays the measured trace. It failed
    3/6 on the old build, exactly as in Studio.
  - Fix: `Sky.client.luau` treats the first `SIT_SETTLE_SECONDS = 1.0` after the sit as supported
    (`satAt`). A sustained fall while seated still ends the rest (asserted).
  - Now 9/0. Mutations: settle 0 KILLED (6 fails), settle 5.0 KILLED (1 fail), comparison `< -1` KILLED;
    control (comment edit) survived. All proved in the rebuilt bundle.
  - Verified in real Studio after the fix: Sit stays true, the chip says Resting, DoF on, the server sees
    Sit=true (it replicates). Holding W wakes the rest (MoveDirection works while seated).
- Idle rest seen working in Studio: after standing still the chip says `💤 Idle`, and the button offers
  `▶ Climb`; pressing it ends idle rest.
- Second review (step 2) DONE: one independent read-only reviewer on 09c76b6 + 20212cf. It could not
  refute any round-2 fix (ring = zone, slow-load settle, capRates, first-only rebirth highlight). No
  high/medium findings. Four LOW findings, **not fixed yet**:
  1. The ring and banner hide at `arriveAt`, but `checkHit` runs until `duration`; 6-22 of 400 players who
     stepped to a random point inside the ring per kind were hit 0.02-0.15 s after it vanished (they never
     left the ring). Fix: keep the ring drawn until the hazard is out of reach.
  2. A returning climber who rebirthed in an earlier session gets "YOU REACHED SPACE!" again, because the
     announcer is seeded from leaderstats Tier (frontier), not bestTier (Sky.client ~683/692).
  3. Docs: EYECANDY.md still says "default = every rebirth lit" in the header, §1 rows, §2 and §8 item 19,
     contradicting `HighlightFirstRebirths = 1` since 20212cf.
  4. Duplicate FxAtmosphere/FxBloom if the client runs before they replicate; a second DoF next to the
     server's. **Not reproduced in Studio:** Lighting had exactly one of each, and no FxDoF on the client.
- Seen in Studio, not a game bug: with the camera zoomed right in, a seated avatar's camera can end inside
  the translucent tile `P_1_1` (Roblox's camera ignores translucent parts), which tints the top of the screen.

Resume point (next night, in this order):
1. Merge branch `night/2026-09-27-plus1-sitdrop` after running ALL plus1-jump gates (11 specs, every
   `robloxemu/check_plus1*`), with the new `check_plus1jump_sitdrop` added to the list in EYECANDY §7.
2. Fix reviewer findings 1-3 test first (4 only if seen).
3. Studio: the rest of the needs-Studio list in `plus1-jump/EYECANDY.md` §8. Config for shot session A
   (StreamAhead 260, hazard interval 100000) goes into the place only, via the Edit datamodel, never `src/`.
   Bands 2-8, hazards (session B), phone viewport HUD, then write the "Eye-candy" section in
   `plus1-jump/STUDIO.md` with screenshots.
4. Thumbnails (EYECANDY §9), upload per docs/thumbnails.md, then publish (verify versionNumber).

### I, A, B, C, D, E, F, G: not started this night.
