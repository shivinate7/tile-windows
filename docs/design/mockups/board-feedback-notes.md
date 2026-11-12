# Board feedback: design notes

Mockup: `board-feedback.html`, beside this file. Owner feedback 2026-11-11 16:10 CST.
Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark`, `hit=1` (handle hit areas) and
`hide=<option,...>`. With no `t`, the page follows the system theme. `#s=all` shows every state.
States: `pb-today`, `pb-note-after`, `pb-note-rest`, `pb-layer-after`, `pb-layer-rest`,
`pb-named-after`, `pb-named-rest`, `fill-on`, `fill-off`, `clear-before`, `clear-after`,
`rs-handles`, `rs-drag`. Option keys for `hide`: `note`, `layer`, `named`, `switch`, `clear`,
`handles`. Each option has a switch on the page that hides it.

Sizes: 1440 and 1024, the brief's sizes; `layout.py devices` gives no device list for this repo.
1024 is drawn at the brief's 57px wide-monitor cells (scale 0.0755), because the live board is
height-bound there. 1440 keeps the stack-and-lock mockup's width-bound scale; it was not measured
against the live `layout()`. Tokens and the "Today" tile CSS are copied from `app.html` as it is on
main after the badge and grip fix. No web fonts, so the page opens with no network.

Focus ids for the waiting page, one per option, each prefixed by its state key:
`-drop-note`, `-peek`, `-named-badge`, `-fill-switch`, `-clear-board`, `-handles`.

## Put Behind

Today (`app.html` `putBehind()`): the dropped window animates into the cell and hides under the
front tile, the front tile is selected, a 3px edge and a "+1" chip appear, and the only words are
"Put Excel behind Claude." in the status bar. The fill then puts the next window (Calculator) into
Excel's old cell at once, so a tile is still where Excel was. The answer is not where the drop was
(house rule `ux-answer-at-press`).

1. **Drop Note.** A note on the tile that took the drop: "**Excel** is behind **Claude**" with
   Undo. It uses the toast's look (`app.html` `.toast`), anchored under the tile with a pointer.
   It stays about 6 seconds or until the next press; with reduced motion it does not fade. Only
   its Undo takes the pointer, so a drag over the cell below still reaches that cell. The status
   bar keeps the same words, and the note is `role="status"`.
   Gain: the answer shows at the drop, in words, at both sizes; Undo is one press away; at rest the
   board is unchanged. Lose: it covers the cell below for a few seconds; at rest the stack looks as
   faint as today.
2. **Peeking Layer.** The back window is a full layer under the front tile. The front tile gives up
   a strip at its top (15px at 1440, 13px at 1024), and the strip names the back app. Right after
   the drop the strip has a blue ring for about 1.5 seconds.
   Gain: the stack reads at rest, by name, with no click. Lose: every stacked tile is shorter. At
   1024 the front tile keeps its tag and badge but loses its title line. A second drawing of the
   back window joins the 3px edge's job, so the edge goes.
3. **Named Badge.** The badge names the window right behind ("Excel", or "Excel +1" for two)
   instead of "+1". A narrow tile at 1024 has no room for a name, so it shows Excel's initial in
   Excel's category colour; the count moves to the tooltip and label. Right after the drop the
   badge has a blue ring for about 1.5 seconds.
   Gain: a small change to an existing control; it reads at rest at 1440. Lose: at 1024 an
   initial is a weak cue; the badge grows and may meet Stay Put sooner on a selected tile.

**Pick: Drop Note.** Gain: it answers the drop where it happened, in words, at both sizes, and
adds Undo. Lose: the stack at rest stays as faint as today. If the owner also wants a lasting cue,
add Named Badge at 1440 only.
Departs from: `decisions/stack-and-lock.md` ruled the +N badge and the stack edge as the stack's
look. Drop Note adds to them and changes neither. Peeking Layer replaces the edge, and Named Badge
changes the badge text: both are `Owner grant: yes`.

## Fill controls

Owner ruling 2026-11-11 16:16 CST (`decisions/fill-controls.md`): build both. Owner ruling
2026-11-12 12:05 CST replaces the Off hold with a held layout and no pins. These notes give the
look.

4. **Fill Empty Cells switch.** A switch in the Monitor section, right above Fill Order, on the
   monitor that fills (today: `app.html` `renderInsp()`, the `s.fill.mon===m.role` branch). It is
   saved per scene. The hint under it reads "Windows that are not pinned fill the free cells." when
   on, and "Windows stay where they are. A new window waits in Windows That Stay Put." when off.
   Off disables Fill Order, with "Fill is off, so the fill order does nothing" on hover and focus
   (`ux-control-earns-place`).
   The monitor label reads "5×2 · fill off" instead of "· fills" (`render()`, `fills`).
   Turning it off holds the layout (owner, 2026-11-12 12:05 CST): in the same `edit()`, each
   window the fill or a zone placed is held in its current cell, with no pin, then `fill.off` is
   set. Nothing moves. The held layout is kept apart from the pins (see the engine change, below).
   A span keeps its block. A window the fill put on a closed pin's cell (locked or not) is not held: it
   goes to Windows That Stay Put, unpinned, and the locked pin keeps its lock (decision
   `stack-and-lock`: nothing is placed over a locked tile, so nothing is held over one). A window
   taken off the board leaves its cell empty, and a new window goes to Windows That Stay Put.
   Turning the switch back on clears the held layout, and the fill places windows as usual. Pins
   the owner set stay as they are. The status line names the count: "Fill Empty Cells is off. 6
   windows are held where they are. Nothing moves."
   Gain: the fill's settings keep one home. Lose: while a monitor that does not fill is picked,
   the switch is out of view (that monitor shows "This monitor does not fill itself.").
   Other place: the Scene section, under Name: always in view, but a second home for fill
   settings. Pick: the Monitor section, beside Fill Order.
   Departs from: main, where the fill always runs and Fill Order sits alone in the Monitor section.
5. **Windows That Stay Put with fill off.** Every window that is not pinned shows in the list with
   the reason "Fill is off" (a new `BAYWHY` entry): the windows Clear Board cleared and any window
   that opens later. The switch alone leaves none, since it holds what was placed. The list keeps today's "Show N More" cap: one
   row per category under 820px of window height, two above. Pins, locks and stacks stay.
6. **Clear Board.** A button in the board's action bar, beside Draw Zone. One `edit()`: it clears
   first, then turns Fill Empty Cells off with nothing held (unlike the switch, which holds
   what was placed), so every unpinned window goes to Windows That Stay Put, and the header's
   Undo brings the board back. The status line says "Cleared the board. 6 windows stay put, and
   Fill Empty Cells is off." When only pinned windows are on the board, the button is disabled,
   with "Only pinned windows are on the board." on hover, and on focus through the inspector's
   `aria-describedby` reason pattern (`#whyoff`), since a disabled button takes no focus.
   Gain: one press on the board, where the owner sorts. Lose: a second control for the same state.
7. **How Clear Board sends windows to the list.** Option one: it turns the switch off with nothing
   held, and the unpinned windows show in the list because fill is off. Option two: it also writes
   each one into the scene's bay, as Keep Where It Is does (`bayEdit()`); then turning fill back on
   still leaves them out, one by one. Pick: option one, so the switch alone brings the board back.
   The owner ruling of 2026-11-12 12:05 CST names option one ("with nothing held"). Owner grant: yes.
8. **Zones with fill off.** Zones stop too, since `tile.ps1` runs pins, then zones, then the fill.
   The mockup has no zone, so this is not drawn.
   Pick: zones pause while fill is off, and their outlines stay on the board. Windows a zone had
   placed are held in their cells when the switch goes off, so they stay. Owner grant: yes.
9. **Engine change.** The switch adds a scene field (for example `fill.off`), and `tile.ps1`
   `Pass` must skip the zone and fill phases when it is set. The held layout is a second scene
   field, separate from the pins, and turning fill on clears it. This is outside the design folder.

## Resize from any corner

Today only the bottom-right corner has a grip (`.tile .rsz`, 20px). The top-left holds the tag,
the top-right the lock, and the bottom-left the badge; Stay Put sits left of the grip.

10. **Handles on every edge and corner.** On the selected tile only, eight handles sit just outside
    its selection ring: four corner brackets (10px arms at 1440, 8px at 1024) and four edge bars
    (16px and 12px), 3px thick, in the act colour. They are drawn on the stage, not in the tile,
    because the tile clips its children (`.tile{overflow:hidden}`), like `.stkedge` and `#rzdraw`.
    The bottom-right grip inside the tile stays. Hit areas lie outside the tile's border only:
    10×10 at each corner and a 7px band along each edge (`#s=rs-handles&hit=1`), so the tag, lock,
    badge, Stay Put and grip keep every pixel. A drag works as the grip does today: the outline
    snaps to whole cells, the label reads "2×2 · 3 windows move · 3 to the list", covered windows
    move to free cells or to the list, and a locked tile stops it. The handles follow the outline.
    Hover shows no handles, because a neighbour's handles would meet across the 2px cell gap.
    Gain: resize from any side with no control moved. Lose: the hit areas are small (7px bands,
    under the 24px of WCAG 2.5.8); the steppers and keys are the equivalent path. While a tile is
    selected, its handles take the outer 3 to 4px of each neighbour.
11. **Fits at 1024: yes.** At 57px cells the handles take no tile area, and every control keeps
    its place. The handles overlap the neighbours' outer 3 to 4px, where neighbours have only
    padding and the last 1 to 2px of a lock's hit area.
12. **Keyboard.** Shift+arrows move the bottom or right edge, as today. New: Ctrl+Shift+arrows
    move the top or left edge (WCAG 2.5.7 asks for a non-drag path). Alt+Shift is not used: it
    switches the input language on Windows. This is a proposal; no ruling names keys.

**Pick: Handles on Every Edge.** Gain: any corner or edge resizes, and no corner control moves.
Lose: small hit areas, and it adds a stage-level element per selected tile.
Departs from: `decisions/stack-and-lock.md` ruled "a corner handle". Owner grant: yes.

13. **Builder note.** The stage's `pointerdown` handlers (`app.html`, the drag handler and the grip
    handler) must start a resize from a handle with the pressed edge or corner, and `rzTarget()`
    must anchor the opposite corner. A handle needs a cursor per side: `nwse-resize`,
    `nesw-resize`, `ns-resize`, `ew-resize`.
