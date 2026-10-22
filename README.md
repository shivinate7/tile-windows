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
- **Scenes** are on the left rail: Default, Focus, Meetings and Review, plus any you save. To put a scene on screen, click its **Apply** button. **Undo** moves the windows back.
- **The inspector** is on the right. Use it to set each monitor's grid and fill order, and a window's span and category. It also sets when a scene applies itself: by hand, on a schedule, when the monitors change, or when a Teams call starts (and, if you ask, back to the scene before when the call ends).
- **The tray icon** opens the app, and its menu applies any scene. It also runs the scenes that apply themselves.

A scene stores your intent, not pixels: app names, title matches, grids and a fill order. It keeps working as windows open and close. Scenes are saved in `%USERPROFILE%\.tile-windows\config.json`. The four starters come from [scenes.json](scenes.json).

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
| [tray.ps1](tray.ps1) | The tray agent. |
| [config.ps1](config.ps1) | Reads and writes the config. |

Run the checks. They move no window and use a temp profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File test\run.ps1
```

To work on the page without your real windows, serve the invented sample in [test/fixture.json](test/fixture.json). Every Apply is then a dry run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -From test\fixture.json
```

The decisions behind the app are in [decisions/](decisions/).
