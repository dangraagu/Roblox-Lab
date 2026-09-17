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

## Batch 2 (2026-09-17): eight more

Real Studio captures, re-paired and checked frame by frame on 2026-09-17 (see `../pairs/manifest.json`).
Same layout as the first three posts on @gusgamesnor: the hook, the game text, then the hashtags.
`#shorts` is left out here because it does nothing on TikTok.

| file | anomaly | YouTube (scheduled) | suggested TikTok time |
|---|---|---|---|
| `4-skewed.mp4` | Skewed | 17.09 16:40, https://youtube.com/shorts/iCEs-sLx37k | to. 17.09 kl. 18:30 |
| `5-red-shift.mp4` | Red Shift | 17.09 21:30, https://youtube.com/shorts/_Q8WxtTtKn8 | fr. 18.09 kl. 12:00 |
| `6-one-too-many.mp4` | One Too Many | 18.09 07:30, https://youtube.com/shorts/U77JGpQKZDM | fr. 18.09 kl. 20:30 |
| `7-the-climber.mp4` | The Climber | 18.09 19:05, https://youtube.com/shorts/aY_qPpi0NFM | lø. 19.09 kl. 09:15 |
| `8-too-big.mp4` | Too Big | 19.09 12:15, https://youtube.com/shorts/PwTaD5-cGyA | lø. 19.09 kl. 18:00 |
| `9-dead-channel.mp4` | Dead Channel | 19.09 20:45, https://youtube.com/shorts/kaf61sB1_HU | sø. 20.09 kl. 13:30 |
| `10-displaced.mp4` | Displaced | 20.09 08:50, https://youtube.com/shorts/ubfPNN6AFkk | sø. 20.09 kl. 21:00 |
| `11-the-extra-door.mp4` | The Extra Door | 20.09 17:20, https://youtube.com/shorts/-eGFyaBYOwc | ma. 21.09 kl. 16:15 |

### 4-skewed.mp4
```
Something in this hall is aimed wrong. Can you spot it?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the telescope, aimed at the floor. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 5-red-shift.mp4
```
One panel in this hall is the wrong colour. Spot it in 4 seconds?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the wall panel glowing red. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 6-one-too-many.mp4
```
Count the mirrors. Is this hall clean?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the extra mirror on the wall. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 7-the-climber.mp4
```
Something is in this hall that should not be. Did you find it?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the thing on the ceiling. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 8-too-big.mp4
```
One thing in this hall grew. Can you spot it?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the bench, scaled up. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 9-dead-channel.mp4
```
A screen in this hall is showing the wrong thing. Find it?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the monitor showing static. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 10-displaced.mp4
```
Something in this hall moved. Did you catch it?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the chair, moved from its usual spot. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```

### 11-the-extra-door.mp4
```
This hall has one door too many. Can you find it?

Anomaly: Night Shift at the Observatory - a Roblox game where nothing chases you. The hall is rebuilt before every pass, and either it is clean or exactly one thing about it is wrong. Walk the 80 studs, then press E to ADVANCE if it looked clean or Q to TURN BACK if you caught it. A wrong call sends you back to Day 1 from however deep you were. This one was the extra door. Play it: https://www.roblox.com/games/123669267191209/

#roblox #robloxhorror #spotthedifference #gamedev
```
