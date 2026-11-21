# Draw Zone hard to find: design notes

Mockup: `draw-zone-hard-to-find.html`, beside this file. Debt `draw-zone-hard-to-find`
(retired after its fix in PR 111; decision `bay-and-group-zones`; design review
`docs/design/reviews/bay-round3.md` row 1). Designer kind: informed. Built from `app.html` on
main at ad8a0b8.

The harm: a user does not find Draw Zone. Today (`app.html` render, `#hint` and `#zadd`): the
button is a plain button; its click calls `drawZoneDialog()` (two corner menus); the hint never
says "zone". The debt asks for an armed state and a hint that names zones.

Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark`, `labels=0` (hides the Today and New
labels) and `hide=<option,...>`. With no `t`, the page follows the system theme. `#s=all` shows
every state. States: `dz-today`, `dz-hint`, `dz-armed`, `dz-cue`, `dz-drag`. Option keys for
`hide`: `armed`, `cue`, `hint`. Each option has a checkbox on the page that hides it.

Sizes: 1440 and 1024 (the brief's; `layout.py devices` lists none for this repo). Themes: light
and dark, from `app.html`'s own tokens. 1440 uses the earlier mockups' width-bound scale and 1024
their 57px-cell scale; neither was measured against the live `layout()`. The only new CSS is
`.btn[aria-pressed="true"]`, `.hint.armed`, `.cue` and `.zdraw`, which copies `#zdraw`.

Focus ids for the waiting page, prefixed by the state key: `dz-hint-hint-text`,
`dz-armed-armed-button`, `dz-cue-board-cue`, `dz-drag-drag-outline`.

1. **Armed Draw Zone.** Draw Zone becomes a toggle: press it and it stays pressed (`aria-pressed`,
   the ink fill that `.seg` and `.days` use). It turns off when a zone is added or cancelled, on
   Esc, or on a second press. While it is on, a press on any cell or window draws a zone (no
   Shift), and the existing outline, label and New Zone dialog follow. Gain: one press tells the
   owner the board is ready, and the drag path becomes the main path. Loss: a window cannot be
   dragged while it is on (Esc or the button leaves it). Pick: yes. Focus `-armed-button`.
   Departs from: the button's click opens `drawZoneDialog()` at once (`app.html`, click handler
   for `zadd`; README "Zones" says "Use Draw Zone under the board"). Owner grant: yes.
2. **The armed hint names zones.** "Draw Zone is on. Drag across cells to draw a zone. Esc
   cancels." in ink, 600 weight, replacing the hint while armed; the status bar says the same
   with the menu path (live region). This is the sentence the debt's red case asks for. Pick:
   yes. Part of item 1, so it has no switch. Focus `-armed-hint`. Owner grant: no.
3. **Pick Cells by Menu.** A plain button beside Draw Zone while armed. It opens today's
   `drawZoneDialog()` unchanged, so the keyboard path (README; the key list line) is kept. The
   key list line becomes "Draw Zone, then Pick Cells by Menu, picks a zone's cells with the
   keyboard." and the Esc line adds "or Draw Zone". Gain: nothing is lost by item 1. Loss: one
   more press for a keyboard user. Pick: yes. Part of item 1. Owner grant: no.
4. **Board cue.** While armed, every cell gets a blue dashed edge and a 9% tint, tiles take a
   crosshair pointer, and the pointer over the board is a crosshair. Gain: the board itself says
   it is in a drawing mode. Loss: blue dashed edges are close to the drop target's look, but only
   one mode is on at a time. Pick: yes. Hide it and the armed state is the button and hint only.
   Focus `-board-cue`. Owner grant: no.
5. **Idle hint names zones.** One sentence added: "Drag across empty cells to draw a zone."
   Gain: a user who never looks at the button learns zones exist. Loss: at 1440 the hint stays two
   lines; at 1024 it wraps to three, so the board is about 17px shorter. Pick: yes. Not needed
   for the debt's red case. Focus `-hint-text`. Owner grant: no.

For the builder (not drawn): a `zarmed` flag in `app.html`; `pointerdown` draws when
`LIVE&&!fm&&(!e||ev.shiftKey||zarmed)`; `endZone` and the Esc handler clear it; `render()` sets
`aria-pressed` and the hint, and clears it when the scene changes, Free Layout turns on (Draw
Zone is already disabled there) or the board is not live. The test case the debt names: the
live hint names zones while Draw Zone is armed. A press that is only a click while armed stays
armed and does not pick a cell.
