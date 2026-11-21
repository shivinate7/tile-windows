# One name for Stay Put: design notes

Mockup: `one-act-four-names.html`, beside this file. Debt `one-act-four-names` (design review bay round 3, row 2). Informed designer. Line numbers are app.html at ad8a0b8.

Deep links: `#s=today|new|both`, `w=1440|1024`, `t=light|dark`, `drop=1` (a window dragged over the list), `hide=hint,drop,button,keys` (puts each named label back to today's words). Focus ids for the waiting page: `new-hint`, `new-dropslot`, `new-button`, `new-keys`, and `labels` (the table of every change). Sizes 1440 and 1024 (the repo has no device list); light and dark.

## The act and its four names

The act: send a window off the board into Windows That Stay Put, where Apply leaves it where it is. Today's names, all at app.html:
- "keep put": hint, 1322.
- "keep it where it is": drop slot 1401, keyboard line 717.
- "Keep Where It Is": inspector button `#tobay`, 1542.
- "Stay Put": tile button 1189, list heading 736.
- "pin": see item 2.

## Design choices

1. **The verb is Stay Put.** What: every label of the act uses it: the inspector button reads "Stay Put" (was Keep Where It Is); the hint reads "to the list to make it stay put"; the drop slot reads "Drag a window here to make it stay put" and, over it, "Release to make Claude: Voice macros stay put, under Code"; the keyboard line reads "K makes it stay put (off the board)". The tile button and the list heading already read it. Gain: one name from the tile, through the inspector, to the list; the inspector button now matches the tile button a user just saw. Loss: "Keep Where It Is" says the result in plain words; "Stay Put" is a name to learn. Pick: Stay Put. It is already the list heading, the tile button, the decision records and the tests' word for the list, so only 5 labels change. Owner grant: no.
   Not drawn, rejected: "Keep Where It Is" everywhere. It renames the tile button and the list heading too, and the tile button is a 14 to 18px icon on narrow tiles where the longer words cannot fit.
2. **Pin keeps its own name.** What: "pin", "pinned" and "Unpin and Let It Fill" stay. A pin holds a window on a cell; Stay Put takes it off the board. They are two acts with two outcomes (a pin is a scene entry, `kind==="pin"`; Stay Put is `unplace`). The hint now says "to pin it" and "to make it stay put", so each verb has one object. Gain: the hint no longer reads as two names for one drop. Loss: a reader who counts "pin" as a fourth name of Stay Put sees it still there. Pick: keep. Owner grant: no. See Input Needed in the report: the debt lists "pin" as a name; this reads it as a different act.
3. **State lines are not renamed.** "no cell (reason), stays where it is" (1402), "It stays where it is" (1530), "stays where it is" (1721, 3065) say what happened, not the act. Gain: a smaller change. Loss: the words "where it is" still appear in the app, as a result. Pick: leave them. Each is a sentence about a window's state, not a label for the act.
4. **Not in this debt.** "Take Out" (1536, a stack member leaves its cell for the list) is a fifth word for a related act. Left alone; it names a different place (one window out of a stack), and the debt names four lines.

## Layout effect

The full board hint (three sentences, app.html:1322) is drawn: its bar is the same height today and new at 1440 and 1024. The inspector's two buttons share a row at 1440 and 1024 with "Stay Put" (32px tall, one row); with "Keep Where It Is" they wrapped to two rows (70px) in the 268px and 252px columns. Reader: `getBoundingClientRect` of `.insp .row`, Browser pane, 2026-11-20, light and dark equal.

## For the builder

Change app.html at 717, 1322, 1401, 1542 only. Write the red label check first: it fails on `Keep Where It Is`, `keep it where it is`, and `keep put` in app.html's user-visible strings. `test/stack-lock.ps1` presses `Keep Where It Is` by name (lines 2839 to 2844, comments at 120, 122, 2779, 2836): re-point those to `Stay Put`. A new gate in a test file means an updated Shard-Init total and cuts.
