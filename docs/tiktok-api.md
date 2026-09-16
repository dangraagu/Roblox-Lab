# TikTok Content Posting API — what it would take, and whether it is worth it

Asked for on 2026-09-10 because TikTok will not accept a file from browser automation
([publishing-social.md](publishing-social.md) has the four dead routes). I went as far as I can go
and stopped at two things that are not mine to do.

## Where it stops, and why

`https://developers.tiktok.com/apps/` answers **"No access — You need to login to access this
page"**, and the login page says **"Don't have a developer account? Sign up"**. So:

- **There is no TikTok developer account for this project.** Creating one is creating an account.
- **The login is an email and a password.** Typing a password is entering a credential.

I do not do either on someone's behalf, including when asked directly. That is not a tooling
limit I can engineer past; it is the line itself.

Everything downstream of those two steps is built and waiting: `tools/tiktok_post.py`.

## Read this before spending an evening on it

> **"All content posted by unaudited clients will be restricted to private viewing mode.** Once
> you have successfully tested your integration, to lift the restrictions on content visibility,
> your API client must undergo an audit to verify compliance with our Terms of Service."
> — TikTok, *Get Started - Direct Post*, read 2026-09-10

So an approved app does **not** get you public posts. It gets you private ones until a separate
audit clears. `privacy_level: "PUBLIC_TO_EVERYONE"` is ignored while unaudited — the tool takes
the flag and says so in its help text rather than letting it look like it worked.

Set against that: dragging a file into `tiktok.com/tiktokstudio/upload` posts publicly, today, in
under a minute. **The API is worth starting only if TikTok becomes a channel worth automating for
months.** For three clips it is strictly worse than one drag.

## The five steps, if it goes ahead

Only the first two need the owner.

1. **Sign up** at `developers.tiktok.com` and accept the developer terms.
2. **Register an app.** It will want a name, a description, and a category. Something like:
   *"GusGamesNor clip publisher — posts short gameplay clips from our own Roblox games to our own
   TikTok account (@gusgamesnor). Single-account, no third-party users."* No redirect URI is
   needed for posting to your own account, but the OAuth flow that mints the token does want one;
   `http://localhost:8731/callback` is fine for a local-only client.
3. **Add the Content Posting API product** to the app, and turn on the **Direct Post**
   configuration. Without Direct Post the API only drops a draft into the app's inbox.
4. **Get `video.publish` approved**, then authorise the @gusgamesnor account for that scope. That
   yields an access token and an open ID.
5. **Put the access token in `tiktok_token.txt`** at the repo root — git-ignored, and the tool
   reads it from there rather than from an argument, because an argument lands in shell history
   and in the process list.

Then `py -3 tools/tiktok_post.py <clip.mp4> --title "caption #roblox"`.

## What the tool does

Written against the documented shapes and **never run against the live API** — its header says so.
Three calls:

| step | endpoint |
|---|---|
| ask the account what it permits | `POST /v2/post/publish/creator_info/query/` |
| start the upload | `POST /v2/post/publish/video/init/` with `source: FILE_UPLOAD` |
| send the bytes | `PUT` to the returned `upload_url` with a `Content-Range` header |
| check the result | `POST /v2/post/publish/status/fetch/` |

Two things it does deliberately. It queries creator info before every post and refuses a privacy
level the account does not offer, because the options are per-account and the UX guidelines
require the query. And it treats `error.code != "ok"` as a failure even on HTTP 200 — this API
returns its real verdict in the body, and this repo has already been bitten once by a publish
script that reported success on a rejection.

Only the single-chunk case is implemented. Our clips are around half a megabyte; the tool refuses
anything over 5 MB rather than guessing at chunk bounds the page we read did not pin down.
