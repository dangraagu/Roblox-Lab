# Daily Shorts upload (automatic)

Owner's decision, 2026-09-17: live with YouTube's upload cap until the channel's limit rises on its
own, rotate every published game evenly through the day, newest games weighted up, and upload
automatically every day. No confirmation needed; report afterwards.

Run once a day, at a time when the previous day's uploads are more than 24 hours old (the cap is
rolling). The scheduled task `roblox-daily-shorts` does it.

## Steps

1. `cd D:/Claude/Roblox && git pull --ff-only`.
2. Take the next posts from `docs/marketing/schedule.json`. Pick entries with `"youtube": null`, in
   date/time order, whose publish time is at least 3 hours in the future. Take at most **12**, or
   the new cap if a run finds that more uploads succeed.
   If fewer than 2 days of future posts are left, extend the plan first:
   `py -3 tools/content_schedule.py plan --from <first unplanned date> --to <that + 6 days> --per-day 12`.
   That command overwrites schedule.json, so merge: keep every entry that already has a `youtube`
   URL. Then run `py -3 tools/content_schedule.py tiktok --from <today> --to <end>`.
3. Upload each post in YouTube Studio (Claude-in-Chrome, channel `UCbeSe83K2QOwYBHZ0CYqREA`),
   using the blocks in `tools/yt_upload.js`, one post at a time:
   `navigate .../videos/upload?d=ud` → BLOCK TAG → `find "claude-file-input-0 file input"` →
   `file_upload` → set `window.__job = {title, description, date, time}` + BLOCK FILL → wait 10 →
   BLOCK POLL FILL → `computer key ctrl+a`, `type <date>`, `key Return` → BLOCK FINISH → wait 10 →
   BLOCK POLL FINISH.
   - `date` exactly as YouTube writes it: `19. sep. 2026`, `3. okt. 2026`, `1. nov. 2026`,
     `5. des. 2026`. `time` must be on the 15-minute grid (the plan's times are).
   - `CAP` from FILL, or the banner *"Daglig opplastingsgrense er nådd"*, means stop. Upload
     nothing more today and close the dialog.
   - `MISMATCH` from FINISH: the date did not take. Click the date input by `find` ref, then
     ctrl+a, type the date, press Return, and run FINISH again.
   - File over 10 MB: re-encode (`-crf 26 -maxrate 3M`) before uploading. Never upload an emulator
     render.
4. **Verify** on `.../videos/short` with BLOCK VERIFY. SUBMITTED is not proof: on 2026-09-17 an
   upload past the cap reported success and never appeared. A post counts only when its title shows
   `Planlagt` with the right date. Only then:
   - set its `youtube` field in schedule.json to `https://youtube.com/shorts/<id>`, and
   - add a row to `docs/marketing/youtube-schedule.md` (clip, title, `YYYY-MM-DD HH:MM`, Short URL,
     `Planlagt (verified in Studio <date>)`).
5. Commit only those two files plus any re-encoded clips or regenerated plan. End the message with
   the Co-Authored-By line. Push, and verify the push landed.
6. Report in Norwegian, briefly: how many were scheduled, the date range they cover, whether the
   cap was hit, and how many days of plan are left.

## Adding a newly published game

Add it to `GAMES` and `CLIPS` in `tools/content_schedule.py` with weight 2 in `WEIGHTS`. Its clips
come from `tools/film_game.py`, real Studio recordings only. Then re-plan from the first day that
has no uploads yet.
