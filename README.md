# Tile Windows

Tile Windows snaps your open windows into a grid on each monitor. You save each arrangement as a scene and apply it in one click, or let it apply itself on a schedule or when monitors change.

Status: working. Windows 10 and 11 only. It needs only Windows PowerShell 5.1, which ships with Windows. No admin rights.

## Quick start

Paste this into Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/shivinate7/tile-windows/main/install.ps1 | iex
```

The installer does three things:

- It puts the app in `%USERPROFILE%\.tile-windows\app`.
- It adds **Tile Windows** to the Start menu.
- It starts the tray agent at login.

The app opens in your browser when the install finishes. To skip start-at-login, run this before the one-liner:

```powershell
$env:TILE_NO_STARTUP = 1
```

From a clone, run `install.ps1` directly. It takes `-NoStartup` and `-NoLaunch`.

## Use it

- **The board** shows your real monitors. To pin a window to a cell, drag it there. Windows you do not pin fill the fill monitor (the ultrawide in the starters), in the order you choose.
- **Scenes** are on the left rail: Default, Focus, Meetings, Review, Listen, Solo and Thursday Prep, plus any you save. To put a scene on screen, click its **Apply** button. **Undo** moves the windows back.
- **The inspector** is on the right. Use it to set each monitor's grid and fill order, and a window's span and category. It also sets when a scene applies itself: by hand, on a schedule, when the monitors change, or when a Teams call starts (and, if you ask, back to the scene before when the call ends). It also lists the other triggers, below.
- **The tray icon** opens the app, and its menu applies any scene. It also runs the scenes that apply themselves.

A scene stores your intent, not pixels: app names, title matches, grids and a fill order. It keeps working as windows open and close. Scenes are saved in `%USERPROFILE%\.tile-windows\config.json`. The starters come from [scenes.json](scenes.json).

## Triggers

A scene applies itself through one **main trigger** (pick one: by hand, on a schedule, when the monitors change, or when a Teams call starts) and any number of **extras**, each with its own switch. Both live in the inspector under "When this scene applies itself". Every extra is off until you tick it and Save. Anything switched on moves your windows without asking, and only while the tray agent runs. The starter scenes ship with every extra off. The rail shows each scene's switched-on extras as chips and says how many scenes apply themselves.

| Extra | What it does | Thresholds (edit beside the switch) | Whose switch counts |
|---|---|---|---|
| Put This Scene Back When I Return | After a lock, or input after a long idle with no lock, apply the scene on screen again. The first unlock of the day applies Default. | lock 5 min, idle 10 min | the scene on screen; Default for the first unlock |
| Place New Windows | A window of an app the scene places (400x300 or bigger) that stays open re-flows the scene on screen. | 3 s | the scene on screen |
| Switch Here When My Work Suits It | After a while in one kind of app, and the layout is not the scene that suits it, snap to that scene. The map is `activity` in config.json: an app, an optional title pattern for sites in Chrome, and a scene. It starts with Claude, Procore, NetSuite, PowerPoint and Excel. Not within a while of a scene you applied by hand. | 60 s in the app, 15 min after a hand-applied scene | the scene it snaps to |
| Resize the Grid by Claude Windows | When the tray applies the scene, its `claudeGrid` picks the ultrawide grid: `dense` at `at` or more Claude windows, back to `roomy` at two fewer. Tray applies only; the app and Apply on the board use the saved grid. | dense from 4 Claude windows | the scene it applies |
| Use This Scene for Calls of Its Size | A Teams call that starts during a meeting in `agenda.json` applies Listen (a big call) or Meetings. `meetingSize` in config.json names the scenes. | a big call is 25 people or more (set on Listen) | the scene it applies |
| Offer This Scene Before a Meeting | A tray balloon offers the scene for the meeting's size. Nothing moves unless you click the balloon. | 2 min before | the scene it offers |
| Use This Scene in a Gap Between Meetings | A next busy meeting is far off, none is on now, and input was within 2 minutes: apply the scene, once per gap. With no meeting left, or within 10 minutes of a call ending, it does nothing. | next meeting 60 min away | the scene it applies |
| Use This Scene for This Many Screens | When the monitors change, apply the scene whose `screens` equals the new count (Solo is 1). With no match, the scene that applies on a monitor change runs, as before. | screens | the scene it applies |
| Use This Scene When the External Monitors Go | One screen left for a while, while unlocked and not idle, and no monitor-set scene applied in the last minute: apply the scene. | 30 s | the scene it applies |

Thresholds are stored with the scene (`opt`), with the defaults in `optDefaults` in config.json. Thursday Prep is an ordinary schedule (Thursday 14:30): set "On a Schedule" on it. Applying a scene by hand is never limited.

Two scenes can hold the same extra (the gap, the laptop-only and the screen-count scenes can clash, as can two main triggers of the same kind). The first scene in the rail wins, and the inspector says "also used by ...".

Guards, for every automatic apply:

- During a Teams call only the call trigger applies. A scheduled apply that falls in a call is skipped, not kept for later.
- Nothing moves within 10 s of your own window drag, or while a mouse button is down. A manual move also cancels what was waiting before it (a dwell, a new window, a held one-shot), so nothing undoes your move. A one-shot trigger that arrives during the hold waits up to 60 s, then drops.
- At most one automatic apply per 30 s. The call trigger is exempt.

### agenda.json

Meeting size, Focus in gaps and the offer read `agenda.json` in the app folder (`%USERPROFILE%\.tile-windows\app`, or the clone's folder). Without the file, or when its `date` is not today, those three do nothing. Reinstalling replaces the app folder and removes the file, so write it each morning. It is not tracked by git.

```json
{ "date": "2026-10-22",
  "events": [
    { "start": "2026-10-22T09:30", "end": "2026-10-22T10:00", "attendees": 30, "teams": true, "showAs": "busy" }
  ] }
```

`date` is the local day. `start` and `end` are local times, `yyyy-MM-ddTHH:mm`. `attendees` counts everyone invited, you included. `teams` is true when the invite has a Teams link (`true`, "yes" and "1" count; anything else is false). An event whose start, end or `attendees` does not read is dropped. `showAs` is `free`, `tentative`, `busy` or `oof`; only `busy` and `oof` count as a meeting.

The weekday-morning scheduled task is not part of this repo. The prompt it would run:

> Read my Outlook calendar for today. Write `agenda.json` in my Tile Windows app folder with this shape: date (today, yyyy-MM-dd) and events, one per calendar entry, each with start and end (local, yyyy-MM-ddTHH:mm), attendees (invitees including me), teams (true if the invite has a Teams link) and showAs (free, tentative, busy or oof). Overwrite the file. Write nothing else.

## With Claude

[SKILL.md](SKILL.md) is a Claude Code skill. Ask Claude to "tile my windows", "put Teams in the left two columns", or "apply my Focus scene". Claude runs [tile.ps1](tile.ps1) with a dry run first. Precise one-off layouts are faster to ask Claude for than to build by hand.

To give Claude the skill, link its folder to a clone of this repo or to the installed app. A junction needs no admin rights:

```powershell
cmd /c mklink /J "$env:USERPROFILE\.claude\skills\tile-windows" "$env:USERPROFILE\.tile-windows\app"
```

## Remove it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.tile-windows\app\uninstall.ps1"
```

Your scenes stay. Add `-Purge` to delete them too.

## Development

| File | Role |
|---|---|
| [tile.ps1](tile.ps1) | The engine. The tray, the server and the skill all run every layout through it. |
| [serve.ps1](serve.ps1) | Serves [app.html](app.html) on 127.0.0.1, behind a random token. |
| [tray.ps1](tray.ps1) | The tray agent and its triggers. Each trigger is a pure function inside one tick. |
| [config.ps1](config.ps1) | Reads and writes the config. |

Run the checks. They move no window and use a temp profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File test\run.ps1
```

To work on the page without your real windows, serve the invented sample in [test/fixture.json](test/fixture.json). Every Apply is then a dry run, and scenes you save go to a throwaway folder in `%TEMP%`, not your real ones:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -From test\fixture.json
```

[test/triggers.ps1](test/triggers.ps1) holds the trigger checks and runs inside the same command, or alone. [test/redproof.ps1](test/redproof.ps1) breaks one guard at a time on a scratch copy of the agent and says which check went red.

The tests never touch your profile: they run with a temp `USERPROFILE`. Set `TILE_HOME` to keep scenes in another folder.

If `config.json` or `state.json` stops parsing, the app keeps it as `config.json.bad` (or `state.json.bad`), starts from the starter scenes (or an empty log), and says so on the page (and in a tray balloon) until you dismiss the note. A second bad file is kept with a time in its name, so the first `.bad` is never overwritten.

The decisions behind the app are in [decisions/](decisions/).
