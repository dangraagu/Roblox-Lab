# Publishing clips, unattended

**Standing directive, 2026-09-10:** *"jeg vil at alt dette skal gå helt automatisk, slik at jeg
ikke trenger å følge med på hva og når ting blir publisert."* Publish without asking, once the
gates are green. Do not queue things for review, do not ask which video goes up when, and do not
wait for a go on a routine publish. Say what went out afterwards.

That covers Roblox place publishes, YouTube Shorts and Reddit posts. It does **not** create
permission for anything the owner has not already approved as a class — money, new accounts,
agreements, or a new platform.

## YouTube — fully automatic

Channel [@GusGamesNor](https://www.youtube.com/@GusGamesNor), `UCbeSe83K2QOwYBHZ0CYqREA`.

The uploader takes a file from browser automation without complaint, which is the whole reason
this half works and TikTok's does not.

1. `https://studio.youtube.com/channel/<channelId>/videos/upload?d=ud`, then wait — the dialog
   renders late.
2. The `input[type=file]` is **inside a shadow root**. A plain `document.querySelectorAll` misses
   it; walk every element's `shadowRoot` recursively. Give it an `aria-label` so `find` returns a
   ref, then `file_upload` that ref.
3. **The first typing pass lands before the form is interactive and is silently lost.** It
   happened on two of three uploads. Type the title and description, screenshot, and if the title
   still reads `spot`, type both again. Always verify before moving on.
4. Title box at `(683, 178)`, description at `(683, 272)` in a 1568x783 frame. Triple-click,
   `ctrl+a`, then type.

### The standing answers

| Field | Value | Why |
|---|---|---|
| Målgruppe | **Nei, den er ikke laget for barn** | Owner's decision, 2026-09-10. Anomaly is horror on a dev channel. "Ja" disables comments, notifications and end screens, which is the feedback loop the clips exist for. |
| Synlighet | **Offentlig** | |
| Altered/synthetic content | leave unset | Real game capture. The disclosure covers realistic synthetic media, not footage of a game, and not "an AI wrote the code". |
| Description | ends with *"Made by one person with an AI coding assistant: I set the design, pick the numbers and test the builds."* | Same posture as the Reddit posts. The audience already worked it out once. |
| Hashtags | `#shorts #roblox` | `#shorts` is what routes a 1080x1920 clip into the Shorts feed. |

Published this way on 2026-09-10, verified as Offentlig/Publisert in Studio:

| Clip | Short |
|---|---|
| `scope_gone` | https://youtube.com/shorts/nhswR3SDHg4 |
| `twin_scope` | https://youtube.com/shorts/JsbLDKZjHjM |
| `lights_out` | https://youtube.com/shorts/MDi1RzMiEIo |

## TikTok — cannot be automated from here

[@gusgamesnor](https://www.tiktok.com/@gusgamesnor). Four routes measured, all dead:

| route | result |
|---|---|
| file into the page's own `input[type=file]` | spinner, `input.files` back to 0, **no upload request on the wire** — only telemetry |
| constructed `drop` with a real `File`, six targets | page unchanged |
| click "Velg video" to raise the OS picker | no `#32770` window in 8 s of polling |
| real desktop drag from File Explorer | refused by the permission tier |

The first three are the same wall the Roblox Creator Dashboard puts up: neither site accepts a
`change` event whose `isTrusted` is false. On Roblox there was an API around it
([thumbnails.md](thumbnails.md)); TikTok's equivalent is the Content Posting API and needs an
approved developer app.

The fourth is not a technical limit and must not be engineered around. Computer-use tiers are set
by app category, not by what the owner approves: a browser is always granted `read` (no clicks,
no typing) and the Windows shell always `click` (**no drag-drop**). Re-requesting returns the same
grant — measured, `grantedAt` unchanged and `"denied":[]` both times — and a click into Chrome is
refused outright. Routing the drag through some third application to get around that would be
defeating the restriction, not solving the problem.

So TikTok is one of two things: the owner drags each file in once (files and captions staged in
`anomaly-observatory/marketing/tiktok/`), or somebody registers the developer app. Until then,
**do not report TikTok as pending work each session** — it is blocked on a decision, not on effort.
