# Failed preview message: design notes

Mockup: `selected-fail-status-only.html`, beside this file. Closes debt `selected-fail-status-only`
(a failed preview of the selected scene shows only in the status line).
Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark` and `hide=<option,...>`. With no `t`, the page follows the system theme. `#s=all` (the default) shows every state.
States: `today`, `under`, `banner`, `ok`. Option keys for `hide`: `under`, `banner`. Each option has a switch on the page.
Focus ids: `under-over` (the message line) and `banner-msg` (the banner).

Sizes: 1440 and 1024, light and dark. `layout.py devices` gives no device list for this repo, so the canvas column is drawn at 904 px (1440) and 524 px (1024): the page width less the 232 px rail and 268 px inspector in `app.html` `.app`. The two-monitor board is a sample; its scale was not measured against the live `layout()`. Whether the message line sits above the fold at 1024 is unmeasured.
Tokens and the board, tile and `.over` CSS are copied from `app.html` on main (ad8a0b8). No web fonts.

What the board does today when the preview fails (`app.html` `previewRun`, lines 1012-1015): `pfail[id]` is set, `prevs[id]` is deleted, the status line says "Preview failed for <scene>: <why>". `view()` then has no layout, so every window draws as a dashed "stays put" tile where it is on the desktop, and `overText` clears `#over`. The board looks like a scene that places nothing, with no word that it failed.

## The change

Read `pfail[selId]` in the render and say it on the board. Nothing else moves. The status line keeps its words. `pfail` is already cleared on the next success (`app.html` 1010), so the message goes by itself.

1. **Message Under the Board.** `overText(V)`, when there is no preview and `pfail[selId]` is set, fills `#over` with `<b>Preview failed:</b> <why>. The board shows the windows where they are now, not where <scene> would put them. Pick the scene again to try once more.` It reuses `.over.warn`, the line that already holds "Not open:". No new CSS, no new element.
   Gain: smallest change (one branch in one function); the look and place are ones the page already uses; the words say what the board is showing. The status line already announces the failure, so the line carries no `role="status"` and nothing is read twice.
   Loss: it sits under the board and the Keyboard summary, not on the board; amber is the page's warning colour, so a failure reads as quietly as "Not open:" does.
   Pick: yes. Departs from: main shows a failure only in the status line (the debt names this).
2. **Banner on the Board.** A banner inside `#stage`, over the bottom edge of the monitors, with a red left edge and a warning icon (`--bad`).
   Gain: the answer is on the board, where the eye already is (house rule `ux-answer-at-press`); red says failure, not caution.
   Loss: a new element and new CSS in `#stage`; it covers the bottom row of cells and any tile in it (about a quarter of the board at 1024), so it must take no pointer; it adds a second place for the same words.
   Pick: no. Departs from: as item 1, and it adds an element to the board that today has only monitors, tiles and handles.

## Not drawn, reported

- **Try Again button.** The recovery today is real: any board edit runs a preview (`edit`), and picking the scene's card runs one when it has none (`app.html` 3266). A button would be new behaviour the debt does not name, and `#over` is plain text, so it needs a click handler too. Departs from: no button on main. Left to the owner; not blocking.
- **A failed scene that is not selected.** It stays status-line only, as the debt says (selected scene).
- **Rail card mark.** A failed non-selected scene is not marked on its card. Out of the debt.

## For the builder

Red case first: with `pfail[selId]` set and no `prevs[selId]`, `$("over").textContent` contains "Preview failed". Then green. The selftest at `app.html` 3391 already reads `pfail` and is unchanged. If the case goes in a test file with a Shard-Init total, update the total and cuts and say so.

Owner grant: none. No spec or ruling changes.
