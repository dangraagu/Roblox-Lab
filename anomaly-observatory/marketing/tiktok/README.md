# The three clips, ready for TikTok

The whole folder is one drag away from being posted. `https://www.tiktok.com/tiktokstudio/upload`,
drag the file onto the page, paste the caption below it.

## Why this is a manual step

TikTok will not take a file from browser automation. Four routes were measured on 2026-09-10:

| route | result |
|---|---|
| the file handed to the page's own `input[type=file]` | spinner, `input.files` back to 0, **not one upload request on the wire** — only telemetry |
| a constructed `drop` carrying a real `File`, on six different targets | page unchanged |
| a click on "Velg video" to raise the OS picker | no `#32770` window appears in 8 s of polling |
| a real desktop drag from File Explorer | refused by the permission tier — File Explorer is granted click-only, Chrome read-only |

The first three are the same wall the Roblox Creator Dashboard puts up: neither site accepts a
`change` event whose `isTrusted` is false. On Roblox there was an API around it
(see [thumbnails.md](../../../docs/thumbnails.md)); TikTok's equivalent is the Content Posting API,
which needs an approved developer app.

**YouTube does not do this.** All three clips went up through browser automation with no trouble,
which is why the same content is already live as Shorts.

## The captions

Same structure each time: the hook is the question, the payoff is the game link. Keep the hashtags —
`#roblox` is the discovery surface that matters here.

### 1-missing-telescope.mp4
> One thing in this hall is wrong. Can you spot it?
>
> Nothing chases you in this game — the whole thing is whether you noticed. Play it: Anomaly:
> Night Shift at the Observatory on Roblox.
>
> #roblox #robloxhorror #spotthedifference #gamedev

### 2-the-twin.mp4
> Two telescopes. There should be one.
>
> The hall is rebuilt before every pass. Either it's clean, or exactly one thing is wrong — and a
> wrong call sends you back to Day 1.
>
> #roblox #robloxhorror #spotthedifference #gamedev

### 3-blackout.mp4
> The lights are wrong in this hall. Did you catch it?
>
> 24 anomaly types, one per pass at most. Day 1 gives you the eight obvious ones.
>
> #roblox #robloxhorror #spotthedifference #gamedev

Game link for the profile bio: https://www.roblox.com/games/123669267191209/
