---
name: tile-windows
description: Use when the user asks to tile, sort, grid, arrange, or snap their open windows (Claude windows, Chrome, Teams, Outlook) on the ultrawide, laptop, or portrait monitor, in any custom layout ("Teams takes the left 2 columns of a 5x2", "Chrome in slot 1"), or says "tile my windows" or "tile-windows". Runs tile.ps1 in this folder. Machine-local to this PC.
---

# tile-windows

`tile.ps1` in this folder puts open windows into a grid on one monitor. Some windows can be pinned to chosen slots, and a pinned window may span several slots. The other windows fill the open slots.

## Steps

1. Turn the user's words into flags (see "Translate a request" below). If an app or window is unclear, run `-List` first. It moves nothing.
2. Run with `-DryRun` and check that each line matches the request. If a line does not match, fix the flags.
3. Say in one line that windows will move on the user's screen. Then run the same flags without `-DryRun`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w ~/.claude/skills/tile-windows/tile.ps1)" <flags>`
4. Report the last line (grid, pinned, tiled), plus the windows left out, if any. Give the command as a `bash` block so the user can re-run it.

## Default setup

If the user asks to tile windows and names no layout, use `-Default`. It runs three passes:

| Monitor | Windows |
|---|---|
| Portrait (`tall`) | Outlook classic (process `outlook`, its main window with "- Outlook" in the title) in the top half. Teams in the bottom half. |
| Laptop | New Outlook (process `olk`) fills the screen. |
| Ultrawide, 5×2 | Claude windows first, then Chrome, then all other app windows. |

A missing app is skipped, with a warning. If there are more windows than the 10 ultrawide slots, the extras stay where they are. Name them in the report. If the user changes one part ("default, but 6x2 on the ultrawide"), run the three passes by hand with that change. Copy them from the `$Default` block in `tile.ps1`.

## Flags

| Flag | Meaning | Default |
|---|---|---|
| `-Cells n` | Grid with n cells. The script picks the rows: 1–4 → 1 row, 5–12 → 2 rows, 13+ → 3 rows. 8 → 4×2. | Ultrawide: 10 (5×2). Other monitors: fit the window count. |
| `-Cols n -Rows n` | Exact grid shape. Use it when the user names one, like "4x2". | none |
| `-Pin 'app=slots;app:title=slots'` | Put an app's window in the given slots. Join slots with `+`. A pin covers the smallest rectangle around its slots. `:text` picks the window whose title contains that text. Without it, the leftmost window of the app is picked. | none |
| `-Proc a,b` | Apps whose windows fill the open slots, in this order. Pinned apps place only their pinned window, unless they are listed here too. | `claude` |
| `-Proc ...,*` | `*` = every other app window, at that place in the order | |
| `-Order 'a\|b'` | Windows whose title contains a come first, then b, and so on. Windows that match nothing go last. | none |
| `-Skip a,b` | Apps that `*` leaves out (wildcards allowed) | input and PowerToys shell windows |
| `-Default` | The default setup above. Works with `-DryRun`. | off |
| `-Monitor` | `wide` (ultrawide, 4096×1680), `laptop` (1536×912), `tall` (portrait, 1200×1872), or a 0-based index | `wide` |
| `-List` | Print windows (app and title) and monitors, then stop | off |
| `-DryRun` | Print where each window would go, then stop | off |

App names: Chrome `chrome`, Teams `ms-teams`, Edge `msedge`, Outlook `olk` or `outlook`, Claude `claude`. For any other app, use `-List` to get its name.

## Translate a request

Slots number row by row from 1, top-left. Draw the grid before you pick slots. A 5×2 grid:

```
 1  2  3  4  5
 6  7  8  9 10
```

- "column k" = slots k, k+Cols, k+2·Cols, and so on. "Left 2 columns" in 5×2 = `1+2+6+7`.
- "row r" = slots (r-1)·Cols+1 through r·Cols. "Top row" in 5×2 = `1+2+3+4+5`.
- "Right half" = the right Cols/2 columns. If Cols is odd, ask which way to round.
- A pin must form a rectangle. If the slots do not touch (like 4 and 8 in 5×2), ask the user before you run.
- With no size named, use the default (5×2 on the ultrawide) and draw the grid for that size. "8 cells" → `-Cells 8`. "4x2" → `-Cols 4 -Rows 2`. A size applies to this run only.

Examples (5×2):
- Chrome in slot 1, Teams in the right column, Claude in the rest: `-Cols 5 -Rows 2 -Pin 'chrome=1;ms-teams=5+10'`
- Teams in the left 2 columns, the RFP Chrome window in slot 3: `-Cols 5 -Rows 2 -Pin 'ms-teams=1+2+6+7;chrome:RFP=3'`

## Group Claude windows by repo

A Claude window's title is its session title. To group by repo:

1. Call `mcp__ccd_session_mgmt__list_sessions` (limit 40). Each row gives `title` and `cwd`. The repo is the last folder of `cwd`.
2. Match each Claude window title from `-List` to a session title. The window titled "Claude" is the app's main window. Put it last.
3. Pass `-Order 'title1|title2|...'`, with the titles of each repo kept together. Put the largest repo first. A short unique part of each title is enough.
4. Pick a grid that fits the window count, and say which repo fills which slots.

## Order of the fill

Windows that are not pinned fill the open slots row by row. They sort by app (in `-Proc` order), then by where they sit now: top row first, left to right. Re-running keeps the user's arrangement. To swap two windows, the user drags one onto the other's spot and runs it again. If there are more windows than open slots, the extras do not move. Name them in the report.

## Limits

- One monitor per run. For several monitors, run once per monitor.
- Bash runs inside the Claude app's package. Never write new files under AppData from it (see the machine note on MSIX AppData).
- The "Ultrawide 6x2" FancyZones layout is separate. It covers Shift-drag by hand.

## Sandbox

`sandbox.html` (this folder) lets the user drag windows on a drawing of their monitors, then click Apply.

1. Run `tile.ps1 -Json`. It prints monitors and windows as JSON and moves nothing. Default `-Proc '*'`; `-Proc`/`-Skip` narrow it. Minimized windows are left out.
2. The user opens `sandbox.html` in a browser, pastes the JSON, and arranges the windows. A sample snapshot loads with no input.
3. Apply downloads `last-place.json` (moved windows only) and shows the command:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\tile-windows\tile.ps1" -PlaceFile "$env:USERPROFILE\Downloads\last-place.json"`
4. `-Place '<json>'` takes the same array inline, but prefer `-PlaceFile`: titles carry quotes and apostrophes. Entries are `{app,title,x,y,w,h}` in screen pixels. Each matches an open window by app plus exact title, else title contains. The last line reports placed and unmatched counts. `-DryRun` prints each move and moves nothing. Claude runs the same command, with `-DryRun` first.
