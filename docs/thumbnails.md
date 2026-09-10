# Uploading a game thumbnail without a human at the keyboard

The Creator Dashboard's thumbnail page cannot be driven the way the rest of the dashboard can.
This is the route that works, why the obvious ones do not, and the exact call to make.

Verified 2026-09-10 against all four live games. Each returned HTTP 200 with a distinct
`targetId`, and each thumbnail was then read back off the dashboard's **Experience Detail Page**
tab in a fresh page load.

## The call

```
POST https://publish.roblox.com/v1/games/{universeId}/thumbnail/image?fileExtension=png
     multipart/form-data, one field named exactly `request`, holding the PNG
     header  x-csrf-token: <token>
     cookies: the logged-in session (send it from a create.roblox.com page, credentials:'include')
```

Response on success: `200 {"targetId": <number>}`. The image is queued for moderation and shows
on the Experience Detail Page immediately.

Get the token by POSTing to the same URL with no body first: Roblox answers `403` and puts the
token in the `x-csrf-token` **response** header. That 403 is the CSRF gate, not a routing answer —
it fires for any POST to any of these hosts, so **a 403 is not evidence that a path exists.**
Two candidate paths that returned a clean 403 turned out to 404 the moment a valid token was
attached.

Images must be 1920x1080. All four of ours already were; a wrong size is not what the dashboard
rejects on (see below).

## Why the obvious routes do not work

- **Clicking the visible "Upload thumbnails" button** does not raise a file picker that Windows UI
  Automation can see. A poll of every visible top-level window for class `#32770` over 8 seconds
  found nothing. `input.click()` from injected JavaScript raises no picker at all — Chrome
  requires a user activation for that, and injected script does not carry one.
- **Handing the page the file** does work at the DOM level and still gets you nowhere. The
  extension's `file_upload` populates `input.files` and dispatches `change`; the page's own
  listener sees `files=1` on both the capture and bubble phase, and then React resets
  `input.files` to 0 and fires **no** network request at all. The dashboard's uploader declines
  the file. It is not a size or dimension check — 1920x1080 PNGs at 473 KB and at 1.33 MB are
  refused identically.
- **Fetching the bytes from a local HTTP server** fails silently. `http://127.0.0.1:8731` served
  the file fine to curl (`200`, correct length, `Access-Control-Allow-Origin: *`), and the page's
  `fetch` still died as a bare `TypeError: Failed to fetch` with **nothing logged to the console**
  and **no request reaching the server**. Adding `Access-Control-Allow-Private-Network: true` and
  a permissive preflight did not change it. A CSP block would have logged a violation; this does
  not, which points at Chrome's local-network gate rather than the page's CSP.
- **Inlining the image as base64 in the injected script** works in principle and is not worth it:
  a 1920x1080 PNG is 0.5-1.3 MB, so ~0.7-1.8 MB of base64 per game.

## The route that does work

Let the page take the file, but take the `File` object off the event before React throws it away,
then send it yourself:

1. On a `create.roblox.com` dashboard page, find `input[type=file]`, give it an `aria-label` so
   the accessibility tree hands back a ref, and add a **capture-phase** `change` listener that
   stashes `ev.target.files[0]`.
2. `file_upload` the PNG into that ref. React will clear `input.files`; the stash survives.
3. POST the stashed `File` as above. The page's cookies and origin come along for free, so no
   credential ever has to be read out of the browser or off disk.

The universe id is the only thing that changes between games — one page can push all four.

Never point a local file server at the repository root to do this. It would publish the games'
source and the git-ignored `publish_*.bat` scripts, which carry an Open Cloud API key inline, to
anything that can reach the port.

## Read the result back

A 200 is not proof. `apis.roblox.com/thumbnail-personalization-api/v1/universe/{id}/thumbnails`
is the **Home Page** personalization set and is empty for a game that has a perfectly good
thumbnail — reading that endpoint says nothing about this upload. Check the dashboard's
**Experience Detail Page** tab, or `games.roblox.com/v1/games/{id}/media`.
